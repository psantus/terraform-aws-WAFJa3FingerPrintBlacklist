
# IAM
## Commons
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

data "aws_iam_policy" "lambda_basic_execution_role" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

## Rule Group Updater
data "aws_iam_policy_document" "rulegroup_updater_lambda_policy" {
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

resource "aws_iam_policy" "rulegroup_updater_lambda_policy" {
  name   = local.ja3_rulegroup_updater_name
  path   = "/lambda/"
  policy = data.aws_iam_policy_document.rulegroup_updater_lambda_policy.json
}

resource "aws_iam_role" "rulegroup_updater_execution_role" {
  name               = local.ja3_rulegroup_updater_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_rule_group_policy" {
  role       = aws_iam_role.rulegroup_updater_execution_role.name
  policy_arn = aws_iam_policy.rulegroup_updater_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_basic_policy_to_rulegroup_updater" {
  role       = aws_iam_role.rulegroup_updater_execution_role.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution_role.arn
}

## Ja3Finder
data "aws_iam_policy_document" "ja3_finder_lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:StartQuery",
      "logs:GetQueryResults",
    ]
    resources = [
      data.aws_cloudwatch_log_group.log_group.arn,
      "${data.aws_cloudwatch_log_group.log_group.arn}:*"
    ]
  }
}

resource "aws_iam_policy" "ja3_finder_lambda_policy" {
  name   = local.ja3_finder_name
  path   = "/lambda/"
  policy = data.aws_iam_policy_document.ja3_finder_lambda_policy.json
}

resource "aws_iam_role" "ja3_finder_execution_role" {
  name               = local.ja3_finder_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_finder_policy" {
  role       = aws_iam_role.ja3_finder_execution_role.name
  policy_arn = aws_iam_policy.ja3_finder_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_basic_policy_to_ja3_finder" {
  role       = aws_iam_role.ja3_finder_execution_role.name
  policy_arn = data.aws_iam_policy.lambda_basic_execution_role.arn
}

## StepFunction workflow
data "aws_iam_policy_document" "stepfunction_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      values   = [data.aws_caller_identity.current.account_id]
      variable = "aws:SourceAccount"
    }
  }
}

data "aws_iam_policy_document" "stepfunction_policy" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      aws_lambda_function.ja3_finder.arn,
      "${aws_lambda_function.ja3_finder.arn}:$LATEST",
      aws_lambda_function.ja3_rulegroup_updater.arn,
      "${aws_lambda_function.ja3_rulegroup_updater.arn}:$LATEST",
    ]
  }
}

resource "aws_iam_policy" "stepfunction_policy" {
  name   = local.ja3_stepfunction_name
  path   = "/stepfunction/"
  policy = data.aws_iam_policy_document.stepfunction_policy.json
}

resource "aws_iam_role" "stepfunction_execution_role" {
  name               = local.ja3_stepfunction_name
  assume_role_policy = data.aws_iam_policy_document.stepfunction_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_stepfunction_policy" {
  role       = aws_iam_role.stepfunction_execution_role.name
  policy_arn = aws_iam_policy.stepfunction_policy.arn
}

# Role for EventBridge
data "aws_iam_policy_document" "eventbridge_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eventbridge_policy" {
  statement {
    effect = "Allow"
    actions = [
      "states:StartExecution"
    ]
    resources = [
      aws_sfn_state_machine.ja3_workflow.arn
    ]
  }
}

resource "aws_iam_policy" "eventbridge_policy" {
  name   = "${var.prefix}-eventbridge"
  path   = "/eventbridge/"
  policy = data.aws_iam_policy_document.eventbridge_policy.json
}

resource "aws_iam_role" "eventbridge_execution_role" {
  name               = "${var.prefix}-eventbridge"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_eventbridge_policy" {
  role       = aws_iam_role.eventbridge_execution_role.name
  policy_arn = aws_iam_policy.eventbridge_policy.arn
}

