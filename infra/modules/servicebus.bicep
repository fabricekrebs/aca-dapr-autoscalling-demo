// Service Bus Module
// Creates Azure Service Bus namespace and topic for Dapr pub/sub with Private Endpoint

param location string
param serviceBusNamespaceName string
param topicName string = 'orders'
param privateEndpointsSubnetId string
param serviceBusPrivateDnsZoneId string
param tags object = {}

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: 1
  }
  properties: {
    publicNetworkAccess: 'Disabled'  // Disable public access
    disableLocalAuth: false  // Allow both AAD and connection string auth
    zoneRedundant: true  // Enable zone redundancy for high availability
  }
}

// Service Bus Topic
resource topic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: topicName
  properties: {
    maxMessageSizeInKilobytes: 1024
    defaultMessageTimeToLive: 'P1D'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    enableBatchedOperations: true
    supportOrdering: true
    enablePartitioning: false
  }
}

// Private Endpoint for Service Bus
resource serviceBusPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${serviceBusNamespaceName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${serviceBusNamespaceName}-connection'
        properties: {
          privateLinkServiceId: serviceBusNamespace.id
          groupIds: [
            'namespace'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for Service Bus
resource serviceBusPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: serviceBusPrivateEndpoint
  name: 'servicebus-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'servicebus-config'
        properties: {
          privateDnsZoneId: serviceBusPrivateDnsZoneId
        }
      }
    ]
  }
}

output serviceBusNamespaceId string = serviceBusNamespace.id
output serviceBusNamespaceName string = serviceBusNamespace.name
output topicName string = topic.name
output endpoint string = 'https://${serviceBusNamespace.name}.servicebus.windows.net'
output privateEndpointId string = serviceBusPrivateEndpoint.id
