variable "log_filter_pattern" {
  type        = string
  description = "Log filter pattern, for instance \"{ $.terminatingRuleId = \"AWS-AWSManagedRulesATPRuleSet\"}\""
}

variable "log_group_name" {
  type        = string
  description = "The LogGroup name you want to extract logs from"
}

variable "lambda_name" {
  type        = string
  description = "The name of the Lambda function that will parse the logs and update the WAF rule"
  default     = "ja3-fingerprints-blocklist-maintainer"
}

variable "lambda_log_retention_in_days" {
  type        = number
  description = "The number of days to retain the Lambda log"
  default     = 30
}

variable "rule_group_name" {
  type        = string
  description = "The name of the WAF rule group"
  default     = "ja3-fingerprints-blocklist"
}

variable "rule_group_maxsize" {
  type        = number
  description = "The maximum number of Ja3FingerPrint rules that can be stored in the WAF rule group. Each rule will cost 2 WCU"
  default     = 750 // 750 * 2 WCU = 1500 WCU, which is the maximum for a rule group
}

variable "rule_group_scope" {
  type        = string
  description = "The scope of the WAF rule group"
  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.rule_group_scope)
    error_message = "Invalid value for rule_group_scope. Valid values are \"REGIONAL\" and \"CLOUDFRONT\"."
  }
}

variable "cloudwatch_metrics_enabled" {
  type        = bool
  description = "Whether to enable CloudWatch metrics"
  default     = false
}

variable "metric_name" {
  type        = string
  description = "The name of the CloudWatch metric."
  default     = "ja3-fingerprints-blocklist"
}

variable "sampled_requests_enabled" {
  type        = bool
  description = "Whether to enable sampled requests logging"
  default     = false
}