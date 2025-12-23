// Container Apps Environment Module
// Creates the Container Apps environment with Dapr enabled and VNET integration

param location string
param environmentName string
param workspaceId string
@secure()
param workspaceSharedKey string
@secure()
param appInsightsConnectionString string
@secure()
param appInsightsInstrumentationKey string
param containerAppsSubnetId string
param storageAccountName string
param serviceBusNamespaceName string
param managedIdentityClientId string
param tags object = {}

resource environment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false  // External for demo, set to true for production
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(workspaceId, '2022-10-01').customerId
        sharedKey: workspaceSharedKey
      }
    }
    daprAIConnectionString: appInsightsConnectionString
    daprAIInstrumentationKey: appInsightsInstrumentationKey
    zoneRedundant: false
  }
}

// Dapr Component: Azure Service Bus Topics for Pub/Sub with Managed Identity
resource daprPubSubComponent 'Microsoft.App/managedEnvironments/daprComponents@2025-07-01' = {
  parent: environment
  name: 'pubsub'
  properties: {
    componentType: 'pubsub.azure.servicebus.topics'
    version: 'v1'
    secrets: []
    metadata: [
      {
        name: 'namespaceName'
        value: '${serviceBusNamespaceName}.servicebus.windows.net'
      }
      {
        name: 'azureClientId'
        value: managedIdentityClientId
      }
    ]
    scopes: [
      'worker'
      'dashboard'
    ]
  }
}

// Dapr Component: State Store (Azure Blob Storage) with Managed Identity
resource daprStateStoreComponent 'Microsoft.App/managedEnvironments/daprComponents@2025-07-01' = {
  parent: environment
  name: 'statestore'
  properties: {
    componentType: 'state.azure.blobstorage'
    version: 'v1'
    secrets: []
    metadata: [
      {
        name: 'accountName'
        value: storageAccountName
      }
      {
        name: 'azureClientId'
        value: managedIdentityClientId
      }
      {
        name: 'containerName'
        value: 'dapr-state'
      }
    ]
    scopes: [
      'worker'
    ]
  }
}

output environmentId string = environment.id
output environmentName string = environment.name
output environmentDefaultDomain string = environment.properties.defaultDomain
