data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "archive_file" "validate" {
  type        = "zip"
  source_file = "${path.module}/lambda/validate.py"
  output_path = "${path.module}/lambda/validate.zip"
}

data "archive_file" "log_metrics" {
  type        = "zip"
  source_file = "${path.module}/lambda/log_metrics.py"
  output_path = "${path.module}/lambda/log_metrics.zip"
}
