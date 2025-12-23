// Container Registry Module
// Creates Azure Container Registry for storing container images with Private Endpoint

param location string
param registryName string
param privateEndpointsSubnetId string
param acrPrivateDnsZoneId string
param tags object = {}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: 'Premium'  // Premium required for Private Link
  }
  properties: {
    adminUserEnabled: false  // Disabled - using managed identity
    publicNetworkAccess: 'Disabled'  // Disable public access
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
  }
}

// Private Endpoint for Container Registry
resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${registryName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${registryName}-connection'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for ACR
resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: acrPrivateEndpoint
  name: 'acr-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'acr-config'
        properties: {
          privateDnsZoneId: acrPrivateDnsZoneId
        }
      }
    ]
  }
}

output registryId string = containerRegistry.id
output registryName string = containerRegistry.name
output registryLoginServer string = containerRegistry.properties.loginServer
output privateEndpointId string = acrPrivateEndpoint.id
