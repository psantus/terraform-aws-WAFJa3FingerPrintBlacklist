# AWS WAF Ja3FingerPrint Blacklist module

Terraform module to maintain a Ja3FingerPrint Blacklist as a WAFv2 Rule Group.
* a CloudWatch Log filter forwards WAFv2 logs to a Lambda
* the Lambda  
  * extracts unique Ja3FingerPrints from the logs
  * adds a rule to a rule group, within the defined limit (since every rule will cost 2 WCUs).

Note: if the scope is CLOUDFRONT, then your provider should be in us-east-1 region.

## Usage

```hcl
module "ja3fingerprint_blacklist" {
  source = "psantus/ja3fingerprint-blacklist"

  
}
```

