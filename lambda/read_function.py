# lambda/read_function.py
import json
import boto3
import os
from decimal import Decimal
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', 'HighAvailabilityTable')
table = dynamodb.Table(table_name)

def decimal_default(obj):
    """Convert Decimal objects to float/int for JSON serialization."""
    if isinstance(obj, Decimal):
        return float(obj) if '.' in str(obj) else int(obj)
    raise TypeError(f"Object of type {type(obj).__name__} is not JSON serializable")

def lambda_handler(event, context):
    try:
        response = table.scan()
        items = response['Items']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps(items, default=decimal_default)  # Use custom serializer
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps({'error': str(e)}, default=decimal_default)
        }
