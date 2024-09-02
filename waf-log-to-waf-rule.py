import os
import json
import gzip
import base64
import boto3
import botocore

# Initialize AWS clients
wafv2 = boto3.client('wafv2')

# Fetch the Rule Group ARN from the environment variable
RULE_GROUP_ARN = os.environ['RULE_GROUP_ARN']
RULE_GROUP_SCOPE = os.environ['RULE_GROUP_SCOPE']
RULE_GROUP_MAXSIZE = os.environ['RULE_GROUP_MAXSIZE']
rule_group_id = RULE_GROUP_ARN.split('/')[-1]

def lambda_handler(event, context):
    # Process the CloudWatch Logs event
    compressed_payload = base64.b64decode(event['awslogs']['data'])
    uncompressed_payload = gzip.decompress(compressed_payload)
    log_data = json.loads(uncompressed_payload)

    # An array to store all fingerprints from the log events
    ja3_fingerprints = []

    # Iterate over the logEvents
    for log_event in log_data['logEvents']:
        # Parse the JSON-encoded message
        log_message = json.loads(log_event['message'])

        # Extract the JA3 fingerprint from the log message and store in ja3_fingerprints
        ja3_fingerprints.append(log_message.get('ja3Fingerprint'))

    # Keep unique values only
    ja3_fingerprints = list(set(ja3_fingerprints))

    # Get the existing Rule Group
    rule_group = wafv2.get_rule_group(
        ARN=RULE_GROUP_ARN,
        Scope=RULE_GROUP_SCOPE
    )

    rules = rule_group['RuleGroup']['Rules']
    existing_priorities = [rule['Priority'] for rule in rules]
    existing_ja3_fingerprints = [rule['Statement']['ByteMatchStatement']['SearchString'].decode() for rule in rules]
    next_priority = max(existing_priorities) + 1 if existing_priorities else 1
    added_fingerprints = []

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
                }
            }
            next_priority += 1

            # Append the new rule to the existing rules
            rules.append(new_rule)

    # Keep only the last RULE_GROUP_MAXSIZE rules
    removed_rules = [rule['Statement']['ByteMatchStatement']['SearchString'].decode() for rule in rules[:-int(RULE_GROUP_MAXSIZE)]]
    rules = rules[-int(RULE_GROUP_MAXSIZE):]

    # Reindex rules from 1
    for index, rule in enumerate(rules):
        rule['Priority'] = index + 1

    # Update the Rule Group with the new rules
    if len(added_fingerprints) > 0:
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
