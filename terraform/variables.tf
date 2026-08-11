variable "aws_region" {
  description = "AWS region to deploy the training pipeline into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix used to name all resources created by this project"
  type        = string
  default     = "mlops-train-automation"
}

variable "lambda_runtime" {
  description = "Python runtime used by the Lambda functions"
  type        = string
  default     = "python3.12"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period for the Lambda functions"
  type        = number
  default     = 14
}
