variable "aws_region" {
  description = "AWS region (e.g., us-east-1)"
  type        = string
  default     = "us-east-1"
}
variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}