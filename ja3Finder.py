import boto3
import os
import time

# Initialize Cloudwatch client
cloudwatch = boto3.client('logs')
ORIGIN_TERMINATING_RULE_ID = os.environ['TERMINATING_RULE_ID']
ORIGIN_THRESHOLD = os.environ['THRESHOLD']

def lambda_handler(event, context):
    # Query logs
    start_query_response = cloudwatch.start_query(
        logGroupName='aws-waf-logs-legacy',
        startTime=int(round(time.time() * 1000)) - 15 * 60 * 1000, # Last 15 minutes (don't be too strict to due Cloudwatch Alarm delay)
        endTime=int(round(time.time() * 1000)),
        queryString="fields ja3Fingerprint | filter terminatingRuleId = '" + ORIGIN_TERMINATING_RULE_ID + "' | stats count(*) as NumberOfRecords by ja3Fingerprint | filter NumberOfRecords > " + ORIGIN_THRESHOLD + " | sort by NumberOfRecords desc"
    )

    query_id = start_query_response['queryId']
    response = None
    while response == None or response['status'] == 'Scheduled' or response['status'] == 'Running':
        print('Waiting for query to complete ...')
        time.sleep(1)
        response = cloudwatch.get_query_results(queryId=query_id)
        print(response)

    return [record[0]['value'] for record in response['results']]

