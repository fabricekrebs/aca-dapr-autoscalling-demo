# Dapr Demo - Azure Container Apps with Enterprise Security

A demonstration project showcasing **Azure Container Apps** with **Dapr** integration, featuring **autoscaling** capabilities, **Private Endpoints**, **Managed Identity authentication**, and deployed using **Bicep** infrastructure-as-code.

## 🎯 Overview

This project demonstrates:

- **Azure Container Apps** - Serverless container platform with built-in scaling
- **Dapr** (Distributed Application Runtime) - Microservices building blocks
- **Event Grid** - Azure-native pub/sub messaging for Dapr
- **Autoscaling** - HTTP, CPU, and memory-based scaling rules
- **Private Endpoints** - Secure private connectivity to Azure services
- **Managed Identity** - Keyless authentication using Azure AD identities
- **Bicep** - Infrastructure-as-code for Azure resource deployment
- **Azure Naming Convention** - Standardized resource naming following best practices

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

The demo consists of two microservices running in a private VNET with secure access to Azure services:

1. **API Service** (`app-italynorth-daprdemo-api-01`)
   - REST API for creating and retrieving orders
   - Publishes events to Event Grid via Dapr and Managed Identity
   - Exposes health and readiness endpoints
   - Autoscales based on HTTP requests, CPU, and memory
   - External ingress for public API access

2. **Worker Service** (`app-italynorth-daprdemo-worker-01`)
   - Subscribes to order events from Event Grid via Dapr
   - Processes orders and saves state to Azure Storage using Managed Identity
   - Runs in the background with autoscaling
   - Internal only (no external ingress)

### Dapr Components (Managed Identity Authentication)

- **Pub/Sub**: Azure Event Grid (`egns-italynorth-daprdemo-01`)
  - Private Endpoint enabled
  - Public access disabled
  - EventGrid Data Sender role assigned to Managed Identity

- **State Store**: Azure Blob Storage (`saindaprdemo01`)
  - Private Endpoint enabled
  - Public access disabled
  - Storage Blob Data Contributor role assigned to Managed Identity

### Network Architecture

- **Virtual Network**: `vnet-italynorth-daprdemo-01` (10.0.0.0/16)
  - Container Apps Subnet: `10.0.0.0/23` (512 addresses)
  - Private Endpoints Subnet: `10.0.2.0/24` (256 addresses)
- **Private DNS Zones**: 
  - `privatelink.blob.core.windows.net`
  - `privatelink.azurecr.io`
  - `privatelink.eventgrid.azure.net`

### Autoscaling Rules

Both services are configured with:
- **HTTP Scaling**: Triggers at 10 concurrent requests
- **CPU Scaling**: Triggers at 70% utilization
- **Memory Scaling**: Triggers at 80% utilization
- **Replicas**: 1 min, 10 max

## 📁 Project Structure

```
dapr/
├── src/
│   ├── api/                    # API service (Python/Flask)
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── worker/                 # Worker service (Python/Flask)
│       ├── app.py
│       ├── requirements.txt
│       └── Dockerfile
├── .dapr/
│   └── components/             # Dapr component definitions
│       ├── eventgrid-pubsub.yaml
│       ├── statestore.yaml
│       └── README.md
├── infra/                      # Bicep infrastructure
│   ├── main.bicep              # Main deployment template
│   ├── parameters.json         # Deployment parameters
│   └── modules/                # Modular Bicep files
│       ├── network.bicep               # VNET, subnets, Private DNS
│       ├── managed-identity.bicep      # User-assigned identity + RBAC
│       ├── monitoring.bicep
│       ├── storage.bicep               # Storage with Private Endpoint
│       ├── eventgrid.bicep             # Event Grid with Private Endpoint
│       ├── container-registry.bicep    # ACR with Private Endpoint
│       ├── container-environment.bicep # Container Apps Environment (VNET)
│       └── container-app.bicep         # Container App with Managed Identity
├── scripts/                    # Automation scripts
│   ├── deploy.sh               # Deploy infrastructure
│   ├── build-images.sh         # Build and push images
│   ├── local-dev.sh            # Run locally with Dapr
│   └── test-api.sh             # Test deployed API
└── docs/                       # Documentation
    ├── naming-convention.md    # Azure naming standards
    ├── architecture.md         # Architecture details
    └── deployment.md           # Deployment guide
```

## 🚀 Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Docker](https://docs.docker.com/get-docker/)
- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) (for local development)
- Azure subscription

### 1. Deploy Infrastructure

```bash
# Login to Azure
az login

# Deploy all resources
./scripts/deploy.sh
```

This creates all Azure resources following the naming convention:
- Resource Group: `rg-italynorth-daprdemo-01`
- Container Registry: `acrindaprdemo01`
- Storage Account: `saindaprdemo01`
- Event Grid Namespace: `egns-italynorth-daprdemo-01`
- Container Apps Environment: `env-italynorth-daprdemo-01`
- API App: `app-italynorth-daprdemo-api-01`
- Worker App: `app-italynorth-daprdemo-worker-01`
- Log Analytics: `law-italynorth-daprdemo-01`
- Application Insights: `ai-italynorth-daprdemo-01`

### 2. Build and Push Images

```bash
# Build Docker images and push to ACR
./scripts/build-images.sh
```

### 3. Test the API

```bash
# Run automated tests
./scripts/test-api.sh
```

Or test manually:

```bash
# Get API URL
API_URL=$(az containerapp show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query properties.configuration.ingress.fqdn \
    -o tsv)

# Test health endpoint
curl https://$API_URL/health

# Create an order
curl -X POST https://$API_URL/api/orders \
    -H "Content-Type: application/json" \
    -d '{
        "order_id": "order-001",
        "customer_name": "John Doe",
        "items": ["Widget A", "Widget B"],
        "total": 149.99
    }'

# Retrieve order (after worker processes it)
curl https://$API_URL/api/orders/order-001
```

## 🔧 Local Development

Run the services locally with Dapr:

```bash
# Start API and Worker with Dapr sidecars
./scripts/local-dev.sh
```

This runs:
- API on `http://localhost:8080` with Dapr on `http://localhost:3500`
- Worker on `http://localhost:8081` with Dapr on `http://localhost:3501`

## 📊 Monitoring

View logs and metrics in Azure Portal:

```bash
# Open Azure Portal
az containerapp browse --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01
```

Or query logs with Azure CLI:

```bash
# View API logs
az containerapp logs show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow

# View Worker logs
az containerapp logs show \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow
```

## 📈 Testing Autoscaling

Generate load to trigger autoscaling:

```bash
# Install hey (HTTP load generator)
# macOS: brew install hey
# Linux: go install github.com/rakyll/hey@latest

# Generate load
hey -z 60s -c 50 https://$API_URL/health
```

Watch replicas scale up:

```bash
az containerapp replica list \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table
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
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## 📝 License

This is a demo project for educational purposes.
