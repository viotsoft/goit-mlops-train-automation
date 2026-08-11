output "state_machine_arn" {
  description = "ARN of the Step Function state machine — set this as STATE_MACHINE_ARN in GitLab CI"
  value       = aws_sfn_state_machine.train_pipeline.arn
}

output "validate_lambda_arn" {
  description = "ARN of the ValidateData Lambda function"
  value       = aws_lambda_function.validate.arn
}

output "log_metrics_lambda_arn" {
  description = "ARN of the LogMetrics Lambda function"
  value       = aws_lambda_function.log_metrics.arn
}
