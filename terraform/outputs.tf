output "ec2_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "app_url" {
  description = "Public URL for the frontend application"
  value       = "http://${aws_instance.app_server.public_ip}"
}

output "backend_url" {
  description = "Public URL for the backend API"
  value       = "http://${aws_instance.app_server.public_ip}:5000"
}
