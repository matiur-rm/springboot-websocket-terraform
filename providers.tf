provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key  # Pass via variables or TF_VAR_
  secret_key = var.aws_secret_key
}