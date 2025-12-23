// Container App Module for Worker with Service Bus Scaling
// Creates a Container App with Dapr enabled and KEDA-based autoscaling on Service Bus topic subscription

param location string
param appName string
param environmentId string
param containerImage string
param containerPort int
param containerRegistryServer string
param managedIdentityId string
param daprAppId string
param daprAppPort int
param minReplicas int = 0
param maxReplicas int = 30
param cpu string = '0.5'
param memory string = '1Gi'
param tags object = {}
param environmentVariables array = []
param serviceBusNamespaceName string
param serviceBusTopicName string
param serviceBusSubscriptionName string = 'worker'  // Dapr creates a subscription with the app's daprAppId
param messageCountTarget int = 100  // Target number of messages per replica

resource containerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: containerRegistryServer
          identity: managedIdentityId
        }
      ]
      dapr: {
        enabled: true
        appId: daprAppId
        appPort: daprAppPort
        appProtocol: 'http'
        enableApiLogging: true
        logLevel: 'info'
      }
    }
    template: {
      containers: [
        {
          name: daprAppId
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: environmentVariables
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: containerPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 15
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        pollingInterval: 5
        cooldownPeriod: 300
        rules: [
          {
            name: 'azure-servicebus-topic-rule'
            custom: {
              type: 'azure-servicebus'
              identity: managedIdentityId
              metadata: {
                topicName: serviceBusTopicName
                subscriptionName: serviceBusSubscriptionName
                messageCount: '${messageCountTarget}'
                namespace: serviceBusNamespaceName
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output containerAppLatestRevisionName string = containerApp.properties.latestRevisionName
