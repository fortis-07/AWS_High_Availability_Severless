# lambda/write_function.py
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME', 'HighAvailabilityTable')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    # Set default CORS headers
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    }

    try:
        # 1. Check if body exists
        if not event.get('body'):
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Request body is missing'})
            }

        # 2. Parse JSON safely
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid JSON format'})
            }

        # 3. Validate required fields
        if not all(key in body for key in ['ItemId', 'Data']):
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing required fields (ItemId and Data)'})
            }

        # 4. Write to DynamoDB
        table.put_item(Item={
            'ItemId': str(body['ItemId']),  # Ensure string type
            'Data': body['Data']
        })

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'message': 'Item saved successfully'})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }
