output "rule_group_arn" {
  value = aws_wafv2_rule_group.rule_group.arn
  description = "The ARN of the WAF rule group, that can be used in your ACL"
}