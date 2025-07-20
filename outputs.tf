output "alb_dns_name" {
  description = "ALB DNS name for WebSocket connections"
  value       = aws_lb.alb.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker pushes"
  value       = aws_ecr_repository.websocket_app.repository_url
}