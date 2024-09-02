# WAF
resource "aws_wafv2_rule_group" "rule_group" {
  name     = var.rule_group_name
  scope    = var.rule_group_scope
  capacity = 2 * var.rule_group_maxsize

  visibility_config {
    cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
    metric_name                = var.metric_name
    sampled_requests_enabled   = var.sampled_requests_enabled
  }

  lifecycle {
    ignore_changes = [rule]
  }
}

# Lambda
data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/waf-log-to-waf-rule.py"
  output_path = "lambda.zip"
}

resource "aws_lambda_function" "rule_group_maintainer" {
  function_name    = var.lambda_name
  filename         = data.archive_file.python_lambda_package.output_path
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role             = aws_iam_role.lambda_execution_role.arn
  runtime          = "python3.12"
  handler          = "waf-log-to-waf-rule.lambda_handler"
  timeout          = 60
  environment {
    variables = {
      RULE_GROUP_ARN = aws_wafv2_rule_group.rule_group.arn
      RULE_GROUP_SCOPE = var.rule_group_scope
      RULE_GROUP_MAXSIZE = var.rule_group_maxsize
    }
  }
}

# Cloudwatch
data "aws_cloudwatch_log_group" "log_group" {
  name = var.log_group_name
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_subscription_filter" "test_lambdafunction_logfilter" {
  name            = var.lambda_name
  log_group_name  = var.log_group_name
  filter_pattern  = var.log_filter_pattern
  destination_arn = aws_lambda_function.rule_group_maintainer.arn
  depends_on      = [aws_lambda_permission.allow_cloudwatch_call_lambda]
}

data "aws_region" "curent_region" {}

resource "aws_lambda_permission" "allow_cloudwatch_call_lambda" {
  statement_id   = "AllowExecutionFromCloudWatchLogs"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rule_group_maintainer.function_name
  principal      = "logs.${data.aws_region.curent_region.id}.amazonaws.com"
  source_arn     = "${data.aws_cloudwatch_log_group.log_group.arn}:*"
  source_account = data.aws_caller_identity.current.account_id

  lifecycle {
    replace_triggered_by = [
      aws_lambda_function.rule_group_maintainer
    ]
  }
}

# IAM
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "wafv2:GetRuleGroup",
      "wafv2:UpdateRuleGroup"
    ]
    resources = [
      aws_wafv2_rule_group.rule_group.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = var.lambda_name
  path   = "/lambda/"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

data "aws_iam_policy" "lambda_basic_execution_role" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = var.lambda_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_rule_group_policy" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

resource "aws_iam_role_policy_attachment" "attach_managed_lambda_policy" {
  policy_arn = data.aws_iam_policy.lambda_basic_execution_role.arn
  role       = aws_iam_role.lambda_execution_role.name
}