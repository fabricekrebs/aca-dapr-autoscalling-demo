# Azure Container Apps Dapr Autoscaling Demo

A demonstration project showcasing **KEDA-based autoscaling** with **Azure Container Apps** and **Dapr**, featuring **Service Bus pub/sub**, **managed identity authentication**, and complete **Bicep infrastructure-as-code**.

## 🎯 Overview

This project demonstrates:

- **Azure Container Apps** - Serverless container platform with KEDA autoscaling
- **Dapr** (Distributed Application Runtime) - Microservices building blocks
- **Service Bus** - Enterprise messaging for Dapr pub/sub with topic/subscription pattern
- **KEDA Autoscaling** - Scale from 0 to 30 replicas based on Service Bus queue depth
- **Private Endpoints** - Secure private connectivity to Azure services
- **Managed Identity** - Keyless authentication using workload identity
- **Bicep** - Infrastructure-as-code for Azure resource deployment
- **Web Dashboard** - Generate up to 10,000 orders and monitor autoscaling in real-time

## 🔒 Security Features

### Private Networking
- **Virtual Network Integration** - All resources deployed within private VNET
- **Private Endpoints** - Storage, Event Grid, and Container Registry accessible only via private IPs
- **No Public Access** - Backend services not exposed to the internet
- **Private DNS Zones** - Automatic DNS resolution for private endpoints

### Identity-Based Authentication
- **Managed Identity** - User-assigned identity for all container apps
- **Zero Secrets** - No storage keys or access keys required
- **RBAC Permissions** - Fine-grained role assignments (Storage Blob Data Contributor, EventGrid Data Sender, AcrPull)
- **Audit Trail** - All authentication events logged in Azure Activity Log

## 🏗️ Architecture

The demo consists of two microservices:

1. **Dashboard** (`app-dashboard-daprdemo-01`)
   - Web UI for generating orders and monitoring metrics
   - Publishes orders to Service Bus via Dapr
   - Displays Service Bus queue depth and worker replica count
   - External ingress for public access
   - Can generate up to 10,000 orders for load testing

2. **Worker Service** (`app-worker-daprdemo-01`)
   - Subscribes to order events from Service Bus via Dapr
   - Processes orders and saves state to Azure Storage
   - **KEDA Autoscaling**: Scales 0-30 replicas based on queue depth
   - **Scaling Target**: 100 messages per replica
   - Internal only (no external ingress)

### Dapr Components (Managed Identity)

- **Pub/Sub**: Azure Service Bus Premium (`sb-italynorth-daprdemo-01`)
  - Topic: `orders`
  - Subscription: `worker` (auto-created by Dapr)
  - Authentication: Workload Identity (system)
  - RBAC: Azure Service Bus Data Owner

- **State Store**: Azure Blob Storage (`saindaprdemo01`)
  - Container: `dapr-state`
  - Authentication: Managed Identity
  - RBAC: Storage Blob Data Contributor

### Network Architecture

- **Virtual Network**: `vnet-italynorth-daprdemo-01` (10.12.2.0/24)
  - Container Apps Subnet: `10.12.2.0/25` (128 addresses)
  - Private Endpoints Subnet: `10.12.2.128/25` (128 addresses)
- **Private DNS Zones**: 
  - `privatelink.blob.core.windows.net`
  - `privatelink.azurecr.io`
  - `privatelink.eventgrid.azure.net`
  - `privatelink.servicebus.windows.net`

### KEDA Autoscaling Configuration

Worker service autoscaling:
- **Min Replicas**: 0 (scales to zero when no messages)
- **Max Replicas**: 30
- **Trigger**: Azure Service Bus topic subscription
- **Target**: 5 messages per replica
- **Polling Interval**: 2 seconds
- **Cooldown Period**: 10 seconds
- **Authentication**: Workload Identity (system)

**Example**: 150 messages in queue = 30 replicas (capped at max)

## 📁 Project Structure

```
dapr/
├── src/
│   ├── dashboard/              # Dashboard UI (Python/Flask)
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── templates/
│   │       └── index.html
│   └── worker/                 # Worker service (Python/Flask)
│       ├── app.py
│       ├── requirements.txt
│       └── Dockerfile
├── infra/                      # Bicep infrastructure
│   ├── main.bicep              # Main deployment template
│   ├── parameters.json         # Deployment parameters
│   └── modules/                # Modular Bicep files
│       ├── network.bicep               # VNET, subnets, Private DNS
│       ├── managed-identity.bicep      # User-assigned identity + RBAC
│       ├── monitoring.bicep
│       ├── storage.bicep               # Storage with Private Endpoint
│       ├── servicebus.bicep            # Service Bus with Private Endpoint
│       ├── container-registry.bicep    # ACR with Private Endpoint
│       ├── container-environment.bicep # Container Apps Environment (VNET)
│       ├── container-app.bicep         # Dashboard container app
│       └── container-app-worker.bicep  # Worker with KEDA autoscaling
├── scripts/                    # Automation scripts
│   ├── full-deploy.sh          # Complete deployment (recommended)
│   ├── deploy.sh               # Deploy infrastructure only
│   ├── build-images.sh         # Build and push images
│   └── local-dev.sh            # Run locally with Dapr
└── docs/                       # Documentation
    ├── naming-convention.md    # Azure naming standards
    ├── architecture.md         # Architecture details
    └── deployment.md           # Deployment guide
```

## 🚀 Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Docker](https://docs.docker.com/get-docker/)
- Azure subscription with appropriate permissions
- Linux/macOS (or WSL on Windows) for running scripts

### One-Command Deployment

The easiest way to deploy the entire solution:

```bash
# Login to Azure
az login

# Run complete deployment
./scripts/full-deploy.sh
```

This script performs all steps:
1. ✅ Creates resource group
2. ✅ Validates Bicep template
3. ✅ Deploys all infrastructure (10-15 minutes)
4. ✅ Assigns AcrPull permissions to managed identity
5. ✅ Builds and pushes container images
6. ✅ Updates container apps with new images
7. ✅ Displays dashboard URL and verification steps

### Manual Deployment Steps

If you prefer to deploy manually:

#### 1. Create Resource Group

```bash
az group create --name rg-italynorth-daprdemo-01 --location italynorth
```

#### 2. Deploy Infrastructure

```bash
cd infra
az deployment group create \
  --name dapr-demo-deployment \
  --resource-group rg-italynorth-daprdemo-01 \
  --template-file main.bicep \
  --parameters parameters.json
```

#### 3. Assign ACR Permissions

```bash
# Get identities
REGISTRY_ID=$(az acr show --name acrindaprdemo01 --query id -o tsv)
IDENTITY_ID=$(az identity show --name id-italynorth-daprdemo-01 --resource-group rg-italynorth-daprdemo-01 --query principalId -o tsv)

# Assign AcrPull role
az role assignment create \
  --assignee $IDENTITY_ID \
  --role AcrPull \
  --scope $REGISTRY_ID
```

#### 4. Build and Push Images

```bash
./scripts/build-images.sh
```

#### 5. Access Dashboard

```bash
# Get dashboard URL
DASHBOARD_URL=$(az containerapp show \
    --name app-dashboard-daprdemo-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query properties.configuration.ingress.fqdn \
    -o tsv)

echo "Dashboard: https://$DASHBOARD_URL"
```

### Testing Autoscaling

1. Open the dashboard in your browser
2. Click "10,000 Orders" button to generate load
3. Watch worker replicas scale from 0 to 30
4. Monitor Service Bus queue depth in real-time
5. Observe scale-down after queue is empty (cooldown period: 10s)

## 🔧 Local Development

To run the services locally with Dapr, you'll need:
- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/)
- Local Azure Service Bus or Service Bus emulator

Configure Dapr components for your local environment in `.dapr/components/` directory.

## 📊 Monitoring

View logs and metrics in Azure Portal or query logs with Azure CLI:

```bash
# View Dashboard logs
az containerapp logs show \
    --name app-dashboard-daprdemo-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow

# View Worker logs
az containerapp logs show \
    --name app-worker-daprdemo-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow

# Check worker replica count
az containerapp replica list \
    --name app-worker-daprdemo-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table

# Monitor Service Bus queue depth
az servicebus topic subscription show \
    --resource-group rg-italynorth-daprdemo-01 \
    --namespace-name sb-italynorth-daprdemo-01 \
    --topic-name orders \
    --name worker \
    --query messageCount
```

## 🧹 Cleanup

Delete all resources:

```bash
az group delete --name rg-italynorth-daprdemo-01 --yes --no-wait
```

## 📚 Documentation

- [Naming Convention](docs/naming-convention.md) - Azure resource naming standards
- [Architecture](docs/architecture.md) - Detailed architecture overview
- [Deployment Guide](docs/deployment.md) - Step-by-step deployment instructions

## 🔗 Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Dapr Documentation](https://docs.dapr.io/)
- [KEDA Scalers](https://keda.sh/docs/latest/scalers/azure-service-bus/)
- [Azure Service Bus Documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Managed Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)

## 📝 License

This is a demo project for educational purposes.
