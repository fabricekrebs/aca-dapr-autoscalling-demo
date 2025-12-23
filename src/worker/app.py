"""
Dapr Demo Worker Service
A Flask-based worker that subscribes to Azure Service Bus events via Dapr pub/sub.
Processes orders and saves state to Dapr state store.
"""

import os
import json
import logging
import time
from datetime import datetime
from flask import Flask, request, jsonify
import requests
from cloudevents.http import from_http

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Dapr configuration
DAPR_HTTP_PORT = os.getenv('DAPR_HTTP_PORT', '3500')
DAPR_PUBSUB_NAME = 'pubsub'
TOPIC_NAME = 'orders'
STATE_STORE_NAME = 'statestore'


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for Container Apps"""
    return jsonify({
        'status': 'healthy',
        'service': 'worker',
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check endpoint"""
    return jsonify({
        'status': 'ready',
        'service': 'worker',
        'dapr_port': DAPR_HTTP_PORT
    }), 200


@app.route('/dapr/subscribe', methods=['GET'])
def subscribe():
    """
    Dapr calls this endpoint to discover subscriptions.
    Returns the list of topics this service subscribes to.
    """
    subscriptions = [
        {
            'pubsubname': DAPR_PUBSUB_NAME,
            'topic': TOPIC_NAME,
            'route': '/orders'
        }
    ]
    logger.info(f"Subscription endpoint called, returning: {subscriptions}")
    return jsonify(subscriptions), 200


@app.route('/orders', methods=['POST'])
def process_order():
    """
    Processes incoming order events from Azure Service Bus via Dapr.
    Saves processed order to state store.
    """
    try:
        # Get the CloudEvent
        content_type = request.headers.get('Content-Type', '')
        
        logger.info(f"Received event with content-type: {content_type}")
        logger.info(f"Request headers: {dict(request.headers)}")
        
        # Parse the event data
        if 'application/cloudevents+json' in content_type:
            # CloudEvents format
            event = from_http(request.headers, request.get_data())
            # event.data might already be a dict or might be a string
            if isinstance(event.data, dict):
                order_data = event.data
            elif isinstance(event.data, str):
                order_data = json.loads(event.data)
            else:
                order_data = event.data
            logger.info(f"Received CloudEvent type: {event.get('type', 'unknown')}")
        else:
            # Regular JSON format
            order_data = request.get_json()
            logger.info(f"Received regular JSON event")
        
        if not order_data:
            logger.error("No order data received")
            return jsonify({'error': 'No data provided'}), 400
        
        order_id = order_data.get('order_id')
        if not order_id:
            logger.error("Order ID missing from event")
            return jsonify({'error': 'Missing order_id'}), 400
        
        logger.info(f"Processing order: {order_id}")
        logger.info(f"Order data: {json.dumps(order_data, indent=2)}")
        
        # Simulate processing time
        logger.info("Simulating processing time: waiting 1 second")
        time.sleep(1.0)
        
        # Process the order (simulate business logic)
        processed_order = {
            **order_data,
            'status': 'processed',
            'processed_at': datetime.utcnow().isoformat(),
            'processed_by': 'worker-service'
        }
        
        # Save to Dapr state store
        state_url = f'http://localhost:{DAPR_HTTP_PORT}/v1.0/state/{STATE_STORE_NAME}'
        
        state_data = [
            {
                'key': order_id,
                'value': processed_order
            }
        ]
        
        logger.info(f"Saving order {order_id} to state store")
        
        response = requests.post(
            state_url,
            json=state_data,
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status_code in [200, 201, 204]:
            logger.info(f"Successfully processed and saved order {order_id}")
            # Return SUCCESS status for Dapr pub/sub
            return jsonify({'status': 'SUCCESS'}), 200
        else:
            logger.error(f"Failed to save order state: {response.status_code} - {response.text}")
            # Return RETRY status to tell Dapr to retry this message
            return jsonify({'status': 'RETRY'}), 500
            
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON data: {str(e)}")
        return jsonify({'status': 'DROP'}), 400
    except requests.exceptions.RequestException as e:
        logger.error(f"Error communicating with Dapr: {str(e)}")
        return jsonify({'status': 'RETRY'}), 500
    except Exception as e:
        logger.error(f"Unexpected error processing order: {str(e)}")
        return jsonify({'status': 'RETRY'}), 500


@app.route('/', methods=['GET'])
def root():
    """Root endpoint with worker information"""
    return jsonify({
        'service': 'Dapr Demo Worker',
        'version': '1.0.0',
        'subscriptions': {
            'pubsub': DAPR_PUBSUB_NAME,
            'topic': TOPIC_NAME
        },
        'dapr': {
            'port': DAPR_HTTP_PORT,
            'statestore': STATE_STORE_NAME
        }
    }), 200


if __name__ == '__main__':
    port = int(os.getenv('PORT', '8081'))
    logger.info(f"Starting Worker service on port {port}")
    logger.info(f"Dapr sidecar expected on port {DAPR_HTTP_PORT}")
    logger.info(f"Subscribing to topic '{TOPIC_NAME}' on pubsub '{DAPR_PUBSUB_NAME}'")
    app.run(host='0.0.0.0', port=port, debug=False)
