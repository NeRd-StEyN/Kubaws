terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- 0. Find latest Amazon Linux 2 AMI ---
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --- 1. DynamoDB (Free Tier: 25GB) ---
resource "aws_dynamodb_table" "messages" {
  name           = "DevOpsMessages"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- 2. SNS Topic (Free Tier: 1M Requests) ---
resource "aws_sns_topic" "alerts" {
  name = "devops-app-alerts"
}

# Subscribe your email here (Manual step for security, or via Terraform if you are brave)
# resource "aws_sns_topic_subscription" "email" {
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "email"
#   endpoint  = "your-email@example.com"
# }

# --- 3. EC2 Instance (Free Tier: t2.micro) ---
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = { Name = "DevOpsStepByStep-Server" }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              
              # 1. Install K3s (Lightweight Kubernetes)
              # --write-kubeconfig-mode 644 allows the 'ec2-user' to use kubectl without sudo
              curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

              # 2. Wait for K3s to be ready
              sleep 30

              # 3. Create a Namespace
              /usr/local/bin/kubectl create namespace app

              # 4. Deploy Backend directly via K8s
              cat <<EOM > /home/ec2-user/app-deploy.yaml
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: backend
                namespace: app
              spec:
                replicas: 1
                selector:
                  matchLabels:
                    app: backend
                template:
                  metadata:
                    labels:
                      app: backend
                  spec:
                    containers:
                    - name: backend
                      image: node:20-slim # Using a public image for demo, in prod use your ECR/DockerHub
                      env:
                      - name: SNS_TOPIC_ARN
                        value: ${aws_sns_topic.alerts.arn}
                      - name: AWS_REGION
                        value: ${var.aws_region}
                      ports:
                      - containerPort: 5000
              ---
              apiVersion: v1
              kind: Service
              metadata:
                name: backend-service
                namespace: app
              spec:
                selector:
                  app: backend
                ports:
                - port: 5000
                  targetPort: 5000
              EOM

              /usr/local/bin/kubectl apply -f /home/ec2-user/app-deploy.yaml
              EOF
}

# --- 4. IAM for EC2 (Permissions to use DynamoDB and SNS) ---
resource "aws_iam_role" "ec2_role" {
  name = "devops_ec2_role_v2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "ec2_cloud_access" {
  name = "ec2_cloud_access"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Scan"],
        Effect = "Allow",
        Resource = aws_dynamodb_table.messages.arn
      },
      {
        Action = "sns:Publish",
        Effect = "Allow",
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "devops_ec2_profile_v2"
  role = aws_iam_role.ec2_role.name
}

# --- 5. Lambda (Cost Control) ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/stop_ec2.py"
  output_path = "${path.module}/../lambda/stop_ec2.zip"
}

resource "aws_lambda_function" "cost_control" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "StopEC2Instance"
  role          = aws_iam_role.lambda_role.arn
  handler       = "stop_ec2.handler"
  runtime       = "python3.9"

  environment {
    variables = {
      INSTANCE_ID = aws_instance.app_server.id
    }
  }
}

# IAM for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "devops_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_ec2_stop" {
  name = "lambda_ec2_stop"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "ec2:StopInstances",
      Effect = "Allow",
      Resource = "*"
    }]
  })
}

# --- 6. CloudWatch Schedule (Stop EC2 every night at 8PM UTC) ---
resource "aws_cloudwatch_event_rule" "stop_at_night" {
  name                = "stop-ec2-at-night"
  schedule_expression = "cron(0 20 * * ? *)"
}

resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.stop_at_night.name
  target_id = "StopEC2"
  arn       = aws_lambda_function.cost_control.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_control.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_at_night.arn
}
