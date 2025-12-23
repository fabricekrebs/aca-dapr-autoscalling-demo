# Dapr Component Configuration for Local Development

This directory contains Dapr component definitions for:

- **eventgrid-pubsub.yaml**: Azure Event Grid pub/sub component
- **statestore.yaml**: Azure Blob Storage state store component

## Local Development

For local development, you can use:

1. **Azurite** (Azure Storage Emulator) for state store
2. **In-memory pub/sub** component for testing

### Local State Store Component

Create a `statestore-local.yaml` for local development:

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.in-memory
  version: v1
  metadata: []
```

### Local Pub/Sub Component

Create an `eventgrid-pubsub-local.yaml` for local development:

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: eventgrid-pubsub
spec:
  type: pubsub.in-memory
  version: v1
  metadata: []
```

## Azure Deployment

In Azure Container Apps, these components will be configured with actual Azure resources:

- Event Grid namespace: `egns-italynorth-daprdemo-01`
- Storage Account: `saindaprdemo01`
- Credentials will be injected via managed identity or secrets
