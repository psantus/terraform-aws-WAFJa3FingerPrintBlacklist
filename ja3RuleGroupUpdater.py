import os
import json
import boto3
import botocore

# Initialize AWS clients
wafv2 = boto3.client('wafv2')

# Fetch the Rule Group ARN from the environment variable
RULE_GROUP_ARN = os.environ['RULE_GROUP_ARN']
RULE_GROUP_SCOPE = os.environ['RULE_GROUP_SCOPE']
RULE_GROUP_MAXSIZE = os.environ['RULE_GROUP_MAXSIZE']
LABEL_TO_FILTER = os.environ['LABEL_TO_FILTER']
rule_group_id = RULE_GROUP_ARN.split('/')[-1]

def lambda_handler(event, context):
    # Keep unique values only
    ja3_fingerprints = event['fingerprints']
    action = event['action']

    # Get the existing Rule Group
    rule_group = wafv2.get_rule_group(
        ARN=RULE_GROUP_ARN,
        Scope=RULE_GROUP_SCOPE
    )

    rules = rule_group['RuleGroup']['Rules']
    existing_priorities = [rule['Priority'] for rule in rules]
    existing_ja3_fingerprints = [rule['Statement']['ByteMatchStatement']['SearchString'].decode() for rule in rules]
    added_fingerprints = []
    removed_rules = []

    # Case ADD_TO_BLACKLIST
    if action == 'ADD_TO_BLACKLIST':
        next_priority = max(existing_priorities) + 1 if existing_priorities else 1

        # Create a new rule for each element in ja3_fingerprints that does not already have a rule
        for ja3_fingerprint in ja3_fingerprints:
            # Check if a rule with the JA3 fingerprint already exists
            rule_exists = any(
                fingerprint == ja3_fingerprint
                for fingerprint in existing_ja3_fingerprints
            )

            if not rule_exists:
                # Create a new rule based on the JA3 fingerprint
                added_fingerprints.append(ja3_fingerprint)
                rule_name = f'JA3FingerprintRule-{ja3_fingerprint}'
                new_rule = {
                    "Name": rule_name,
                    "Priority": next_priority,
                    "Action": {
                        "Block": {}
                    },
                    "VisibilityConfig": {
                        "SampledRequestsEnabled": True,
                        "CloudWatchMetricsEnabled": True,
                        "MetricName": rule_name
                    },
                    "Statement": {
                        "AndStatement": {
                            "Statements": [
                                {
                                    "ByteMatchStatement": {
                                        "FieldToMatch": {
                                            "JA3Fingerprint": {
                                                "FallbackBehavior": "MATCH"
                                            }
                                        },
                                        "PositionalConstraint": "EXACTLY",
                                        "SearchString": ja3_fingerprint,
                                        "TextTransformations": [
                                            {
                                                "Type": "NONE",
                                                "Priority": 0
                                            }
                                        ]
                                    }
                                },
                                {
                                    "LabelMatchStatement": {
                                        "Scope": "LABEL",
                                        "Key": LABEL_TO_FILTER
                                    }
                                }
                            ]
                        }
                    }
                }
                next_priority += 1

                # Append the new rule to the existing rules
                rules.append(new_rule)

        # Keep only the last RULE_GROUP_MAXSIZE rules
        removed_rules = [rule['Statement']['ByteMatchStatement']['SearchString'].decode() for rule in rules[:-int(RULE_GROUP_MAXSIZE)]]
        rules = rules[-int(RULE_GROUP_MAXSIZE):]

    if action == 'REMOVE_FROM_BLACKLIST':
        removed_rules = ja3_fingerprints
        rules = [rule for rule in rules if rule['Statement']['ByteMatchStatement']['SearchString'].decode() not in ja3_fingerprints]

    # Reindex rules from 1
    for index, rule in enumerate(rules):
        rule['Priority'] = index + 1

    # Update the Rule Group with the new rules
    if len(added_fingerprints) > 0 or len(removed_rules) > 0:
        try:
            response = wafv2.update_rule_group(
                Id=rule_group_id,
                Name=rule_group['RuleGroup']['Name'],
                Scope=RULE_GROUP_SCOPE,
                VisibilityConfig=rule_group['RuleGroup']['VisibilityConfig'],
                LockToken=rule_group['LockToken'],
                Rules=rules
            )
        except botocore.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'WAFInvalidParameterException':
                print(f"Error updating Rule Group: {e.response['Error']['Message']}")
            else:
                print(f'Error updating Rule Group: {e}')

    print(json.dumps({
        "rule_group_id": rule_group_id,
        "existingRules": len(existing_ja3_fingerprints),
        "existingJa3FingerPrints": existing_ja3_fingerprints,
        "addedRules": len(added_fingerprints),
        "addedJa3FingerPrints": added_fingerprints,
        "resultingRules": len(rules),
        "removedRules": len(removed_rules),
        "removedJa3FingerPrint": removed_rules,
        "ruleGroupMaxSize": RULE_GROUP_MAXSIZE
    }))
