locals {
  ja3_rulegroup_updater_name = "${var.prefix}-rulegroup-updater"
  ja3_finder_name            = "${var.prefix}-finder"
  ja3_stepfunction_name      = "${var.prefix}-workflow"
}

# WAF
resource "aws_wafv2_rule_group" "rule_group" {
  name     = var.rule_group_name
  scope    = var.rule_group_scope
  capacity = 4 * var.rule_group_maxsize

  visibility_config {
    cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
    metric_name                = var.metric_name
    sampled_requests_enabled   = var.sampled_requests_enabled
  }

  lifecycle {
    ignore_changes = [rule]
  }
}

# Lambdas
data "archive_file" "ja3_finder_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/ja3Finder.py"
  output_path = "lambda-ja3Finder.zip"
}


resource "aws_lambda_function" "ja3_finder" {
  function_name                  = local.ja3_finder_name
  filename                       = data.archive_file.ja3_finder_lambda_package.output_path
  source_code_hash               = data.archive_file.ja3_finder_lambda_package.output_base64sha256
  role                           = aws_iam_role.ja3_finder_execution_role.arn
  runtime                        = "python3.12"
  handler                        = "ja3Finder.lambda_handler"
  timeout                        = 240
  reserved_concurrent_executions = var.lambda_concurrency

  environment {
    variables = {
      TERMINATING_RULE_ID = var.terminating_rule_id
      THRESHOLD           = var.threshold_per_ja3
    }
  }
}

data "archive_file" "ja3_rulegroup_updater_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/ja3RuleGroupUpdater.py"
  output_path = "lambda-ja3RuleGroupUpdater.zip"
}

resource "aws_lambda_function" "ja3_rulegroup_updater" {
  function_name                  = local.ja3_rulegroup_updater_name
  filename                       = data.archive_file.ja3_rulegroup_updater_lambda_package.output_path
  source_code_hash               = data.archive_file.ja3_rulegroup_updater_lambda_package.output_base64sha256
  role                           = aws_iam_role.rulegroup_updater_execution_role.arn
  runtime                        = "python3.12"
  handler                        = "ja3RuleGroupUpdater.lambda_handler"
  timeout                        = 60
  reserved_concurrent_executions = var.lambda_concurrency

  environment {
    variables = {
      RULE_GROUP_ARN     = aws_wafv2_rule_group.rule_group.arn
      RULE_GROUP_SCOPE   = var.rule_group_scope
      RULE_GROUP_MAXSIZE = var.rule_group_maxsize
    }
  }
}

resource "aws_cloudwatch_log_group" "finder_lambda_logs" {
  name              = "/aws/lambda/${local.ja3_finder_name}"
  retention_in_days = var.log_retention_in_days
}

resource "aws_cloudwatch_log_group" "rulegroup_updater_lambda_logs" {
  name              = "/aws/lambda/${local.ja3_rulegroup_updater_name}"
  retention_in_days = var.log_retention_in_days
}

# Cloudwatch
data "aws_cloudwatch_log_group" "log_group" {
  name = var.log_group_name
}

data "aws_caller_identity" "current" {}

# Step Functions
resource "aws_sfn_state_machine" "ja3_workflow" {
  name     = local.ja3_stepfunction_name
  role_arn = aws_iam_role.stepfunction_execution_role.arn

  definition = <<EOF
{
  "Comment": "This maintains a rule group in AWS WAF v2, banning ja3FingerPrints for a specified time window.",
  "StartAt": "Wait for logs to be available in Log Insights",
  "States": {
    "Wait for logs to be available in Log Insights": {
      "Type": "Wait",
      "Seconds": 180,
      "Next": "Find ja3FingerPrints to blacklist"
    },
    "Find ja3FingerPrints to blacklist": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.ja3_finder.arn}:$LATEST"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Ja3FinferPrints to process?",
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "Fail"
        }
      ]
    },
    "Ja3FinferPrints to process?": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$[0]",
          "IsPresent": false,
          "Next": "Success",
          "Comment": "Nothing to process"
        }
      ],
      "Default": "Add ja3fingerPrint to blacklist"
    },
    "Success": {
      "Type": "Succeed"
    },
    "Add ja3fingerPrint to blacklist": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.ja3_rulegroup_updater.arn}:$LATEST",
        "Payload": {
          "action": "ADD_TO_BLACKLIST",
          "fingerprints.$": "$"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Keep ja3FingerPrint in the blacklist for N seconds",
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "Fail"
        }
      ],
      "ResultPath": null
    },
    "Fail": {
      "Type": "Fail"
    },
    "Keep ja3FingerPrint in the blacklist for N seconds": {
      "Type": "Wait",
      "Seconds": ${var.ja3_ban_duration_in_seconds},
      "Next": "Remove ja3fingerPrint from blacklist"
    },
    "Remove ja3fingerPrint from blacklist": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.ja3_rulegroup_updater.arn}:$LATEST",
        "Payload": {
          "action": "REMOVE_FROM_BLACKLIST",
          "fingerprints.$": "$"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "Fail"
        }
      ],
      "End": true,
      "ResultPath": null
    }
  }
}
EOF
}

# CloudWatch alarm to StepFunction workflow
## 1. Cloudwatch alarm
resource "aws_cloudwatch_metric_alarm" "ja3_fingerprint_alarm" {
  alarm_name          = "${var.prefix}-alarm"
  alarm_description   = "Triggers the step function workflow when a ja3 fingerprint is detected"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.threshold_alarm
  treat_missing_data  = "notBreaching"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  datapoints_to_alarm = 1
  dimensions = var.rule_group_scope == "CLOUDFRONT" ? {
    WebACL = var.web_acl_name
    Rule   = var.web_acl_metric_name
  } : {
    WebACL = var.web_acl_name
    Rule   = var.web_acl_metric_name
    Region = data.aws_region.current.name
  }
}

data "aws_region" "current" {}

## 2. Alarm event to stepfunction using Eventbridge
resource "aws_cloudwatch_event_rule" "ja3_fingerprint_event_rule" {
  name        = "${var.prefix}-rule"
  description = "Triggers Step Function ja3FingerPrint workflow"

  event_pattern = <<EOF
{
  "source": ["aws.cloudwatch"],
  "detail-type": ["CloudWatch Alarm State Change"],
  "detail": {
    "alarmName": ["${aws_cloudwatch_metric_alarm.ja3_fingerprint_alarm.alarm_name}"],
    "state": {
      "value": ["ALARM"]
    }
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "ja3_fingerprint_event_target" {
  rule      = aws_cloudwatch_event_rule.ja3_fingerprint_event_rule.name
  target_id = "${var.prefix}-target"
  arn       = aws_sfn_state_machine.ja3_workflow.arn
  role_arn  = aws_iam_role.eventbridge_execution_role.arn
}