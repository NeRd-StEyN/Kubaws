# Cost Control & Production Thinking

## AWS Free Tier Management
To ensure we stay within the **AWS Free Tier** ($0 cost), we apply these rules:
1. **EC2 Instance**: Use only `t2.micro` or `t3.micro`. These provide 750 hours/month for free (enough for one instance to run 24/7).
2. **S3 Storage**: Stay under 5GB of standard storage.
3. **Avoid EKS**: Amazon EKS (Kubernetes) costs ~$73/month just to exist. We run Kubernetes **locally** (Kind/Minikube) or on a standard EC2 to avoid this bill.
4. **Data Transfer**: Be mindful of egress (data leaving AWS). Stay under 100GB/month.

## Auto-Stop Mechanism (Example)
In a real project, we use AWS Lambda or a Cron job to stop EC2 instances at night:
```bash
# Example AWS CLI command to stop our instance
aws ec2 stop-instances --instance-ids i-1234567890abcdef0
```

## Production readiness Checklist
- **Secrets Management**: Move API keys and DB passwords out of code and into **AWS Secrets Manager** or **HashiCorp Vault**.
- **High Availability**: Use an **Auto Scaling Group** to ensure that if one server goes down, another starts automatically.
- **Monitoring**: Set up **CloudWatch Alarms** to email you if CPU usage stays above 80% for 5 minutes.
