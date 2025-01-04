variable "web_acl_name" {
  type        = string
  description = "Name of the WAF Web ACL"
}

variable "web_acl_metric_name" {
  type        = string
  description = "Name of the WAF Web ACL metric to watch"
}

variable "log_group_name" {
  type        = string
  description = "Name of the Log Group we'll extract logs from"
  validation { # Starts with /aws-waf-logs-
    condition     = can(regex("^aws-waf-logs-", var.log_group_name))
    error_message = "The log_group_name must start with \"aws-waf-logs-\" since we consume WAF Logs."
  }
}

variable "terminating_rule_id" {
  type        = string
  description = "The ID of the terminating rule"
  default     = "AWS-AWSManagedRulesATPRuleSet"
}

variable "threshold_per_ja3" {
  type        = number
  description = "How many times a given Ja3FingerPrint must have triggered the Terminating Rule"
  default     = 10
}

variable "threshold_alarm" {
  type        = number
  description = "How many times the Terminating Rule should match to trigger workflow execution"
  default     = 15
}

variable "ja3_ban_duration_in_seconds" {
  type        = number
  description = "Duration in seconds for which the Ja3 fingerprint will be banned"
  default     = 900
}

variable "prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "ja3"
}

variable "log_retention_in_days" {
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

variable "lambda_concurrency" {
  type        = number
  description = "The amount of reserved concurrency for the Lambda function. If you don't set this you might hit throttling errors on WAF GetRuleGroup API "
  default     = -1
}