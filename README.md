# AWS WAF Ja3FingerPrint Blacklist module

Terraform module to maintain a Ja3FingerPrint Blacklist as a WAFv2 Rule Group.

This is particularly useful when your WAF ACL contains an "expensive rule", such as Account TakeOver Prevention (ATP),
Account Creation Fraud Prevention (ACFP). 

Instead of relying solely on these rules, use the logs they generate to feed a Ja3 FingerPrint blacklist, and include 
the blacklist rule group as part of your WebACL, before the expensive rule. 

## Usage

```hcl
module "ja3fingerprint_blacklist" {
  source = "psantus/ja3fingerprint-blacklist"
  
  log_group_name = "/aws-waf-logs-myacl"
  log_filter_pattern = "{ $.terminatingRuleId = \"AWS-AWSManagedRulesATPRuleSet\"}"
  rule_group_scope = "REGIONAL"
  rule_group_maxsize = 200
}
```

## What this module creates

* a CloudWatch Log filter forwards WAFv2 logs to a Lambda
* the Lambda
  * extracts unique Ja3FingerPrints from the logs
  * adds a rule to a rule group, within the defined limit (since every rule will cost 2 WCUs).

## Deployment note

If the scope is CLOUDFRONT, then your provider should be in us-east-1 region.

## Disclaimer

Note that the license agreement explicitely states you're responsible for the use of this module. I, in particular, 
cannot be held responsible for any cost incurred due to the use or mis-use of this module, whether those costs are 
generated directly by the resources deployed by this module, or by WAF, should the process set up by this module fail
to protect you from those costs.