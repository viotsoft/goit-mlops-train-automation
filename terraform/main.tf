### IAM — Lambda execution role ###############################################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

### Lambda — validate #########################################################

resource "aws_cloudwatch_log_group" "validate" {
  name              = "/aws/lambda/${var.project_name}-validate"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "validate" {
  function_name    = "${var.project_name}-validate"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "validate.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.validate.output_path
  source_code_hash = data.archive_file.validate.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.validate,
  ]
}

### Lambda — log_metrics #######################################################

resource "aws_cloudwatch_log_group" "log_metrics" {
  name              = "/aws/lambda/${var.project_name}-log-metrics"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "log_metrics" {
  function_name    = "${var.project_name}-log-metrics"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "log_metrics.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.log_metrics.output_path
  source_code_hash = data.archive_file.log_metrics.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.log_metrics,
  ]
}

### IAM — Step Functions execution role #######################################

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn_exec" {
  name               = "${var.project_name}-sfn-exec"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

data "aws_iam_policy_document" "sfn_invoke_lambda" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.validate.arn,
      aws_lambda_function.log_metrics.arn,
    ]
  }
}

resource "aws_iam_role_policy" "sfn_invoke_lambda" {
  name   = "${var.project_name}-sfn-invoke-lambda"
  role   = aws_iam_role.sfn_exec.id
  policy = data.aws_iam_policy_document.sfn_invoke_lambda.json
}

### Step Function — validate -> log_metrics ###################################

resource "aws_sfn_state_machine" "train_pipeline" {
  name     = "${var.project_name}-train-pipeline"
  role_arn = aws_iam_role.sfn_exec.arn

  definition = jsonencode({
    Comment = "Simplified ML training workflow: validate data, then log metrics."
    StartAt = "ValidateData"
    States = {
      ValidateData = {
        Type     = "Task"
        Resource = aws_lambda_function.validate.arn
        Next     = "LogMetrics"
      }
      LogMetrics = {
        Type     = "Task"
        Resource = aws_lambda_function.log_metrics.arn
        End      = true
      }
    }
  })

  depends_on = [
    aws_iam_role_policy.sfn_invoke_lambda,
  ]
}
