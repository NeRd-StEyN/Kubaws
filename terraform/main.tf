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

# --- 0. Security Group ---
resource "aws_security_group" "app_sg" {
  name        = "devops_app_sg"
  description = "Allow web traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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

# --- 2. MULTI-CHANNEL NOTIFICATIONS (SNS) ---
resource "aws_sns_topic" "alerts" {
  name = "devops-app-alerts"
}

# 1. EMAIL ALERT
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "nipun0411@gmail.com"
}

# 2. MOBILE SMS ALERT
resource "aws_sns_topic_subscription" "sms" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sms"
  endpoint  = "+919075850416" # ⚠️ REPLACE WITH YOUR PHONE NUMBER (E.164 format)
}

# 3. MOBILE PUSH NOTIFICATION (Example structure)
# Note: For Push (pop-ups), you must create a "Platform Application" first.
# resource "aws_sns_topic_subscription" "mobile_push" {
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "application"
#   endpoint  = "arn:aws:sns:REGION:ACCOUNT_ID:endpoint/GCM/MyMobileApp/DeviceID"
# }

# --- 3. EC2 Instance (Free Tier: t2.micro) ---
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  key_name      = "devops-key"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  tags = { Name = "DevOpsStepByStep-Server" }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              
              echo "=== DevOps Demo: Docker Setup ==="
              yum update -y
              
              # Install Docker
              echo "Installing Docker..."
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              
              # Wait for Docker to be ready
              echo "Waiting for Docker daemon..."
              sleep 5
              
              # Pull custom images from GitHub Container Registry (public, no auth needed)
              # Note: Replace YOUR_GITHUB_USERNAME with actual username
              GITHUB_REPO="ghcr.io/nerd-steyn/kubaws"
              
              echo "Pulling Frontend image..."
              docker pull $GITHUB_REPO/frontend:latest || docker pull nginx:alpine
              
              echo "Pulling Backend image..."  
              docker pull $GITHUB_REPO/backend:latest || docker pull python:3.9-slim
              
              # Run Frontend (React app on port 80)
              echo "Starting Frontend container..."
              docker run -d \
                --name frontend \
                --restart always \
                -p 80:80 \
                $GITHUB_REPO/frontend:latest 2>/dev/null || \
                docker run -d --name frontend --restart always -p 80:80 nginx:alpine
              
              # Run Backend (Node.js API on port 5000)
              echo "Starting Backend container..."
              docker run -d \
                --name backend \
                --restart always \
                -p 5000:5000 \
                -e PORT=5000 \
                -e AWS_REGION=${var.aws_region} \
                -e SNS_TOPIC_ARN=${aws_sns_topic.alerts.arn} \
                $GITHUB_REPO/backend:latest 2>/dev/null || \
                docker run -d --name backend --restart always -p 5000:5000 python:3.9-slim python3 -m http.server 5000
              
              # Verify containers are running
              echo "=== Containers Status ==="
              docker ps
              
              echo "=== Setup Complete! ==="
              echo "Frontend: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):80"
              echo "Backend:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5000"
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
