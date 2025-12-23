// Container App Module
// Creates a Container App with Dapr enabled and autoscaling configured

param location string
param appName string
param environmentId string
param containerImage string
param containerPort int
param containerRegistryServer string
param managedIdentityId string
param daprAppId string
param daprAppPort int
param minReplicas int = 1
param maxReplicas int = 10
param cpu string = '0.5'
param memory string = '1Gi'
param tags object = {}
param environmentVariables array = []

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
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
      ingress: {
        external: true
        targetPort: containerPort
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
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
              initialDelaySeconds: 5
              periodSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
          {
            name: 'cpu-scaling'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
          {
            name: 'memory-scaling'
            custom: {
              type: 'memory'
              metadata: {
                type: 'Utilization'
                value: '80'
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
output containerAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output containerAppLatestRevisionName string = containerApp.properties.latestRevisionName
