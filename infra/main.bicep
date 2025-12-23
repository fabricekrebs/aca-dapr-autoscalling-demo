// Main Bicep Template for Dapr Demo on Azure Container Apps
// Deploys all infrastructure following naming convention: {prefix}-{location}-{app}-{instance}

targetScope = 'subscription'

// Parameters
@description('Azure region for all resources')
param location string = 'italynorth'

@description('Application name')
param appName string = 'daprdemo'

@description('Instance number for resources')
param instance string = '01'

@description('Container image tag for Worker')
param workerImageTag string = 'latest'

@description('Container image tag for Dashboard')
param dashboardImageTag string = 'latest'

@description('Minimum replicas for autoscaling')
param minReplicas int = 1

@description('Maximum replicas for autoscaling')
param maxReplicas int = 10

@description('Tags to apply to all resources')
param tags object = {
  Application: 'DaprDemo'
  Environment: 'Demo'
  ManagedBy: 'Bicep'
  Project: 'DaprDemo'
}

// Variables for resource names following naming convention
var resourceGroupName = 'rg-${location}-${appName}-${instance}'
var vnetName = 'vnet-${location}-${appName}-${instance}' // vnet-italynorth-daprdemo-01
var managedIdentityName = 'id-${location}-${appName}-${instance}' // id-italynorth-daprdemo-01
var storageAccountName = 'sa${locationAbbr}${appName}${instance}' // saindaprdemo01
var containerRegistryName = 'acr${locationAbbr}${appName}${instance}' // acrindaprdemo01
var serviceBusNamespaceName = 'sb-${location}-${appName}-${instance}' // sb-italynorth-daprdemo-01
var environmentName = 'env-${location}-${appName}-${instance}' // env-italynorth-daprdemo-01
var workerAppName = 'app-${location}-${appName}-worker-${instance}' // app-italynorth-daprdemo-worker-01
var logAnalyticsName = 'law-${location}-${appName}-${instance}' // law-italynorth-daprdemo-01
var appInsightsName = 'ai-${location}-${appName}-${instance}' // ai-italynorth-daprdemo-01

// Location abbreviation for storage and registry (no hyphens allowed)
var locationAbbr = location == 'italynorth' ? 'in' : location == 'westeurope' ? 'we' : location == 'northeurope' ? 'ne' : 'unk'

// Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Monitoring Infrastructure
module monitoring 'modules/monitoring.bicep' = {
  scope: resourceGroup
  name: 'monitoring-deployment'
  params: {
    location: location
    workspaceName: logAnalyticsName
    appInsightsName: appInsightsName
    tags: tags
  }
}

// Virtual Network with Private DNS Zones
module network 'modules/network.bicep' = {
  scope: resourceGroup
  name: 'network-deployment'
  params: {
    location: location
    vnetName: vnetName
    tags: tags
  }
}

// Storage Account for Dapr State Store with Private Endpoint
module storage 'modules/storage.bicep' = {
  scope: resourceGroup
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    privateEndpointsSubnetId: network.outputs.privateEndpointsSubnetId
    blobPrivateDnsZoneId: network.outputs.blobPrivateDnsZoneId
    tags: tags
  }
}

// Service Bus Namespace for Dapr Pub/Sub with Private Endpoint
module serviceBus 'modules/servicebus.bicep' = {
  scope: resourceGroup
  name: 'servicebus-deployment'
  params: {
    location: location
    serviceBusNamespaceName: serviceBusNamespaceName
    topicName: 'orders'
    privateEndpointsSubnetId: network.outputs.privateEndpointsSubnetId
    serviceBusPrivateDnsZoneId: network.outputs.serviceBusPrivateDnsZoneId
    tags: tags
  }
}

// Container Registry with Private Endpoint
module containerRegistry 'modules/container-registry.bicep' = {
  scope: resourceGroup
  name: 'acr-deployment'
  params: {
    location: location
    registryName: containerRegistryName
    privateEndpointsSubnetId: network.outputs.privateEndpointsSubnetId
    acrPrivateDnsZoneId: network.outputs.acrPrivateDnsZoneId
    tags: tags
  }
}

// Managed Identity with Role Assignments (depends on resources being deployed)
module managedIdentity 'modules/managed-identity.bicep' = {
  scope: resourceGroup
  name: 'identity-deployment'
  params: {
    location: location
    identityName: managedIdentityName
    storageAccountName: storageAccountName
    serviceBusNamespaceName: serviceBusNamespaceName
    containerRegistryName: containerRegistryName
    tags: tags
  }
  dependsOn: [
    storage
    serviceBus
    containerRegistry
  ]
}

// Container Apps Environment with Dapr and VNET Integration
module containerEnvironment 'modules/container-environment.bicep' = {
  scope: resourceGroup
  name: 'environment-deployment'
  params: {
    location: location
    environmentName: environmentName
    containerAppsSubnetId: network.outputs.containerAppsSubnetId
    workspaceId: monitoring.outputs.workspaceId
    workspaceSharedKey: monitoring.outputs.workspaceSharedKey
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    storageAccountName: storageAccountName
    serviceBusEndpoint: serviceBus.outputs.endpoint
    serviceBusNamespaceName: serviceBusNamespaceName
    topicName: 'orders'
    managedIdentityClientId: managedIdentity.outputs.clientId
    tags: tags
  }
}

// Worker Container App with Managed Identity and Service Bus Scaling
module workerApp 'modules/container-app-worker.bicep' = {
  scope: resourceGroup
  name: 'worker-app-deployment'
  params: {
    location: location
    appName: workerAppName
    environmentId: containerEnvironment.outputs.environmentId
    containerImage: '${containerRegistry.outputs.registryLoginServer}/worker:${workerImageTag}'
    containerPort: 8081
    containerRegistryServer: containerRegistry.outputs.registryLoginServer
    managedIdentityId: managedIdentity.outputs.identityId
    managedIdentityClientId: managedIdentity.outputs.clientId
    daprAppId: 'worker'
    daprAppPort: 8081
    minReplicas: 0
    maxReplicas: 30
    cpu: '0.5'
    memory: '1Gi'
    tags: tags
    serviceBusNamespaceName: serviceBusNamespaceName
    serviceBusTopicName: 'orders'
    serviceBusSubscriptionName: 'worker'
    messageCountTarget: 5
    environmentVariables: [
      {
        name: 'PORT'
        value: '8081'
      }
      {
        name: 'DAPR_HTTP_PORT'
        value: '3500'
      }
    ]
  }
}

// Outputs
output resourceGroupName string = resourceGroup.name
output vnetName string = network.outputs.vnetName
output managedIdentityName string = managedIdentity.outputs.identityName
output storageAccountName string = storage.outputs.storageAccountName
output containerRegistryName string = containerRegistry.outputs.registryName
output containerRegistryLoginServer string = containerRegistry.outputs.registryLoginServer
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusNamespaceName
output environmentName string = containerEnvironment.outputs.environmentName
output workerAppName string = workerApp.outputs.containerAppName
output logAnalyticsWorkspaceName string = logAnalyticsName
output appInsightsName string = appInsightsName
