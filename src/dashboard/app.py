"""
Dapr Demo Dashboard
A Flask-based dashboard for monitoring and generating orders.
Displays Service Bus queue metrics and provides load testing interface.
"""

import os
import json
import logging
from datetime import datetime
from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import requests
from azure.identity import DefaultAzureCredential
from azure.servicebus.management import ServiceBusAdministrationClient

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configuration
DAPR_HTTP_PORT = os.getenv('DAPR_HTTP_PORT', '3500')
DAPR_PUBSUB_NAME = 'pubsub'
TOPIC_NAME = 'orders'
SERVICE_BUS_NAMESPACE = os.getenv('SERVICE_BUS_NAMESPACE', 'sb-italynorth-daprdemo-01.servicebus.windows.net')
SUBSCRIPTION_NAME = 'worker'  # Dapr creates subscription based on worker's appId
MANAGED_IDENTITY_CLIENT_ID = os.getenv('MANAGED_IDENTITY_CLIENT_ID', '')


def get_servicebus_client():
    """Get Service Bus admin client with managed identity"""
    try:
        if MANAGED_IDENTITY_CLIENT_ID:
            credential = DefaultAzureCredential(
                managed_identity_client_id=MANAGED_IDENTITY_CLIENT_ID
            )
        else:
            credential = DefaultAzureCredential()
        
        return ServiceBusAdministrationClient(
            fully_qualified_namespace=SERVICE_BUS_NAMESPACE,
            credential=credential
        )
    except Exception as e:
        logger.error(f"Failed to create Service Bus client: {e}")
        return None


@app.route('/')
def index():
    """Serve the dashboard UI"""
    return render_template('index.html')


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'dashboard',
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check endpoint"""
    return jsonify({
        'status': 'ready',
        'service': 'dashboard'
    }), 200


@app.route('/api/metrics', methods=['GET'])
def get_metrics():
    """
    Get Service Bus queue metrics
    Returns message counts and queue statistics
    """
    try:
        client = get_servicebus_client()
        if not client:
            return jsonify({
                'error': 'Failed to connect to Service Bus',
                'activeMessages': 0,
                'deadLetterMessages': 0
            }), 500
        
        # Get topic runtime properties
        topic_properties = client.get_topic_runtime_properties(TOPIC_NAME)
        
        # Get subscription runtime properties
        subscription_properties = client.get_subscription_runtime_properties(
            TOPIC_NAME, 
            SUBSCRIPTION_NAME
        )
        
        return jsonify({
            'topic': {
                'name': TOPIC_NAME,
                'activeMessages': topic_properties.active_message_count if hasattr(topic_properties, 'active_message_count') else 0,
                'scheduledMessages': topic_properties.scheduled_message_count if hasattr(topic_properties, 'scheduled_message_count') else 0,
                'sizeInBytes': topic_properties.size_in_bytes if hasattr(topic_properties, 'size_in_bytes') else 0
            },
            'subscription': {
                'name': SUBSCRIPTION_NAME,
                'activeMessages': subscription_properties.active_message_count if hasattr(subscription_properties, 'active_message_count') else 0,
                'deadLetterMessages': subscription_properties.dead_letter_message_count if hasattr(subscription_properties, 'dead_letter_message_count') else 0,
                'transferDeadLetterMessages': subscription_properties.transfer_dead_letter_message_count if hasattr(subscription_properties, 'transfer_dead_letter_message_count') else 0
            },
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Error fetching metrics: {e}")
        return jsonify({
            'error': str(e),
            'activeMessages': 0,
            'deadLetterMessages': 0
        }), 500


@app.route('/api/orders', methods=['POST'])
def create_order():
    """
    Create a single order
    """
    try:
        order_data = request.get_json()
        
        if not order_data:
            return jsonify({'error': 'No data provided'}), 400
        
        # Validate required fields
        required_fields = ['order_id', 'customer_name', 'items', 'total']
        for field in required_fields:
            if field not in order_data:
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        # Add metadata
        order_data['created_at'] = datetime.utcnow().isoformat()
        order_data['status'] = 'pending'
        
        # Publish to Dapr pub/sub
        publish_url = f'http://localhost:{DAPR_HTTP_PORT}/v1.0/publish/{DAPR_PUBSUB_NAME}/{TOPIC_NAME}'
        
        logger.info(f"Publishing order {order_data['order_id']} to {publish_url}")
        
        response = requests.post(
            publish_url,
            json=order_data,
            headers={'Content-Type': 'application/json'},
            timeout=5
        )
        
        logger.info(f"Dapr response status: {response.status_code}, body: {response.text}")
        
        if response.status_code in [200, 204]:
            return jsonify({
                'message': 'Order created successfully',
                'order_id': order_data['order_id']
            }), 201
        else:
            logger.error(f"Dapr publish failed: {response.status_code} - {response.text}")
            return jsonify({
                'error': 'Failed to publish order',
                'details': response.text,
                'status_code': response.status_code
            }), 500
            
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Connection error to Dapr: {e}")
        return jsonify({'error': f'Cannot connect to Dapr: {str(e)}'}), 503
    except requests.exceptions.Timeout as e:
        logger.error(f"Timeout connecting to Dapr: {e}")
        return jsonify({'error': 'Timeout connecting to Dapr'}), 504
    except Exception as e:
        logger.error(f"Error creating order: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500


@app.route('/api/orders/bulk', methods=['POST'])
def create_bulk_orders():
    """
    Create multiple orders for load testing
    Expected payload: { "count": 10, "prefix": "load-test" }
    """
    try:
        data = request.get_json()
        count = data.get('count', 10)
        prefix = data.get('prefix', 'bulk')
        
        if count > 10000:
            return jsonify({'error': 'Maximum 10000 orders per request'}), 400
        
        created_orders = []
        failed_orders = []
        
        publish_url = f'http://localhost:{DAPR_HTTP_PORT}/v1.0/publish/{DAPR_PUBSUB_NAME}/{TOPIC_NAME}'
        
        for i in range(1, count + 1):
            order_data = {
                'order_id': f'{prefix}-{i:04d}',
                'customer_name': f'Customer {i}',
                'items': [f'item-{i}'],
                'total': round(10.0 + (i * 0.5), 2),
                'created_at': datetime.utcnow().isoformat(),
                'status': 'pending'
            }
            
            try:
                response = requests.post(
                    publish_url,
                    json=order_data,
                    headers={'Content-Type': 'application/json'},
                    timeout=2
                )
                
                if response.status_code in [200, 204]:
                    created_orders.append(order_data['order_id'])
                else:
                    failed_orders.append(order_data['order_id'])
            except Exception as e:
                logger.error(f"Failed to publish order {order_data['order_id']}: {e}")
                failed_orders.append(order_data['order_id'])
        
        return jsonify({
            'message': f'Created {len(created_orders)} orders',
            'created': len(created_orders),
            'failed': len(failed_orders),
            'orders': created_orders[:10]  # Return first 10 for confirmation
        }), 201
        
    except Exception as e:
        logger.error(f"Error creating bulk orders: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """
    Get overall system statistics
    """
    try:
        # Get Dapr metadata
        metadata_url = f'http://localhost:{DAPR_HTTP_PORT}/v1.0/metadata'
        
        try:
            metadata_response = requests.get(metadata_url, timeout=2)
            dapr_metadata = metadata_response.json() if metadata_response.status_code == 200 else {}
        except:
            dapr_metadata = {}
        
        # Get Service Bus metrics
        client = get_servicebus_client()
        sb_stats = {'connected': False}
        
        if client:
            try:
                subscription_props = client.get_subscription_runtime_properties(
                    TOPIC_NAME, 
                    SUBSCRIPTION_NAME
                )
                sb_stats = {
                    'connected': True,
                    'activeMessages': subscription_props.active_message_count,
                    'deadLetterMessages': subscription_props.dead_letter_message_count
                }
            except:
                pass
        
        return jsonify({
            'dapr': {
                'appId': dapr_metadata.get('id', 'dashboard'),
                'components': len(dapr_metadata.get('components', []))
            },
            'servicebus': sb_stats,
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Error fetching stats: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', '8082'))
    app.run(host='0.0.0.0', port=port, debug=False)
