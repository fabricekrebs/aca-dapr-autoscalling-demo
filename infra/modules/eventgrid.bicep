// Event Grid Module
// Creates Azure Event Grid namespace and topic for Dapr pub/sub with Private Endpoint

param location string
param eventGridNamespaceName string
param topicName string = 'orders'
param privateEndpointsSubnetId string
param eventGridPrivateDnsZoneId string
param tags object = {}

// Event Grid Namespace
resource eventGridNamespace 'Microsoft.EventGrid/namespaces@2023-12-15-preview' = {
  name: eventGridNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    isZoneRedundant: true  // Required in regions that support availability zones
    publicNetworkAccess: 'Disabled'  // Disable public access
  }
}

// Event Grid Topic
resource topic 'Microsoft.EventGrid/namespaces/topics@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: topicName
  properties: {
    publisherType: 'Custom'
    inputSchema: 'CloudEventSchemaV1_0'
    eventRetentionInDays: 1
  }
}

// Event Grid Topic Subscription
resource subscription 'Microsoft.EventGrid/namespaces/topics/eventSubscriptions@2023-12-15-preview' = {
  parent: topic
  name: '${topicName}-subscription'
  properties: {
    deliveryConfiguration: {
      deliveryMode: 'Queue'
      queue: {
        receiveLockDurationInSeconds: 60
        maxDeliveryCount: 10
        eventTimeToLive: 'P1D'
      }
    }
    eventDeliverySchema: 'CloudEventSchemaV1_0'
  }
}

// Private Endpoint for Event Grid
resource eventGridPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${eventGridNamespaceName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${eventGridNamespaceName}-connection'
        properties: {
          privateLinkServiceId: eventGridNamespace.id
          groupIds: [
            'topic'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for Event Grid
resource eventGridPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: eventGridPrivateEndpoint
  name: 'eventgrid-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'eventgrid-config'
        properties: {
          privateDnsZoneId: eventGridPrivateDnsZoneId
        }
      }
    ]
  }
}

output eventGridNamespaceId string = eventGridNamespace.id
output eventGridNamespaceName string = eventGridNamespace.name
output topicName string = topic.name
output endpoint string = 'https://${eventGridNamespace.name}.${location}-1.eventgrid.azure.net'
output privateEndpointId string = eventGridPrivateEndpoint.id
