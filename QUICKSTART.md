# Quick Start Guide

Get the Dapr Demo with Enterprise Security up and running!

## ⚠️ Important: Security Configuration

This project uses **Private Endpoints** and **Managed Identity** for security. This means:

- Azure services (Storage, Event Grid, ACR) are **not accessible from the public internet**
- Deployment must be done from **Azure Cloud Shell** or a VM in the same VNET
- **RBAC role assignments** take 5-10 minutes to propagate

## ⚡ Quick Start (Azure Cloud Shell Recommended)

### 1. Prerequisites Check

```bash
# Verify you have the required tools
az --version          # Azure CLI
docker --version      # Docker (available in Cloud Shell)
git --version         # Git
```

### 2. Clone and Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd dapr

# Login to Azure (already done in Cloud Shell)
az login
```

### 3. Deploy Everything

```bash
# Deploy infrastructure (10-15 minutes)
# This creates VNET, Private Endpoints, Managed Identity, and all resources
./scripts/deploy.sh

# ⏱️ IMPORTANT: Wait 5-10 minutes for RBAC role assignments to propagate!
# Otherwise, image pulls and Dapr authentication will fail

# Build and push images (3-5 minutes)
# This uses Azure CLI authentication to push to private ACR
./scripts/build-images.sh

# Wait for container apps to pull images via Managed Identity (2-3 minutes)
```

### 4. Test It Out

```bash
# Run automated tests
./scripts/test-api.sh
```

**That's it! You're done! 🎉**

## 🔒 Security Features Deployed

- ✅ **Virtual Network** - Private networking (10.0.0.0/16)
- ✅ **Private Endpoints** - Storage, Event Grid, ACR accessible only via private IPs
- ✅ **Managed Identity** - Zero secrets authentication
- ✅ **RBAC Roles** - Storage Blob Data Contributor, EventGrid Data Sender, AcrPull
- ✅ **Public Access Disabled** - All backend services isolated from internet
- ✅ **Private DNS** - Automatic resolution to private endpoints

## 📋 What Gets Deployed

### Azure Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| Resource Group | `rg-italynorth-daprdemo-01` | Container for all resources |
| Container Registry | `acrindaprdemo01` | Stores Docker images |
| Storage Account | `saindaprdemo01` | Dapr state store |
| Event Grid Namespace | `egns-italynorth-daprdemo-01` | Pub/sub messaging |
| Container Apps Env | `env-italynorth-daprdemo-01` | Runtime environment |
| API Container App | `app-italynorth-daprdemo-api-01` | REST API service |
| Worker Container App | `app-italynorth-daprdemo-worker-01` | Event processor |
| Log Analytics | `law-italynorth-daprdemo-01` | Centralized logging |
| Application Insights | `ai-italynorth-daprdemo-01` | Monitoring & tracing |

**Total Resources**: 9  
**Estimated Cost**: ~$10-20/month (varies with usage)  
**Deployment Time**: ~10-15 minutes

## 🧪 Quick Tests

### Test 1: Health Check

```bash
# Get API URL
API_URL=$(az containerapp show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query properties.configuration.ingress.fqdn -o tsv)

# Test health
curl https://$API_URL/health
```

**Expected**: `{"status": "healthy", ...}`

### Test 2: Create Order

```bash
# Create an order
curl -X POST https://$API_URL/api/orders \
    -H "Content-Type: application/json" \
    -d '{
        "order_id": "test-001",
        "customer_name": "Test User",
        "items": ["Item A"],
        "total": 99.99
    }'
```

**Expected**: `{"message": "Order created and published successfully", ...}`

### Test 3: Verify Processing

```bash
# Wait a few seconds
sleep 5

# Retrieve order
curl https://$API_URL/api/orders/test-001
```

**Expected**: Order with `"status": "processed"`

## 🔥 Quick Load Test

```bash
# Install hey
brew install hey  # macOS
# or: go install github.com/rakyll/hey@latest

# Generate load
hey -z 30s -c 20 https://$API_URL/health

# Watch replicas scale
watch -n 2 'az containerapp replica list \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table'
```

**Expected**: Replica count increases from 1 to multiple replicas

## 📊 Quick Monitoring

### View Logs

```bash
# API logs
az containerapp logs show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow

# Worker logs
az containerapp logs show \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow
```

### View Metrics

```bash
# Open Azure Portal to Container Apps
az containerapp browse \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01
```

## 🧹 Quick Cleanup

```bash
# Delete everything
az group delete --name rg-italynorth-daprdemo-01 --yes --no-wait

# Verify deletion
az group exists --name rg-italynorth-daprdemo-01
# Should return: false
```

## 🔧 Local Development

Want to run locally with Dapr?

```bash
# Install Dapr CLI
wget -q https://raw.githubusercontent.com/dapr/cli/master/install/install.sh -O - | /bin/bash

# Initialize Dapr
dapr init

# Install Python dependencies
pip install -r src/api/requirements.txt
pip install -r src/worker/requirements.txt

# Run locally
./scripts/local-dev.sh
```

**Access**:
- API: `http://localhost:8080`
- Worker: `http://localhost:8081`
- Dapr Dashboard: `http://localhost:8080` (run `dapr dashboard`)

## 🚨 Troubleshooting

### Problem: Deployment fails

**Solution**:
```bash
# Check if providers are registered
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.EventGrid

# Wait a few minutes and retry
```

### Problem: Images not pulling

**Solution**:
```bash
# Verify images exist
az acr repository list --name acrindaprdemo01

# Manually trigger new revision
az containerapp revision copy \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01
```

### Problem: Events not processing

**Solution**:
```bash
# Check worker logs
az containerapp logs show \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --tail 50

# Look for Dapr subscription info
```

## 📚 Learn More

- **Full Documentation**: See [docs/](docs/) folder
  - [Architecture](docs/architecture.md) - System design details
  - [Naming Convention](docs/naming-convention.md) - Azure naming rules
  - [Deployment Guide](docs/deployment.md) - Detailed deployment steps

- **Azure Docs**:
  - [Container Apps](https://docs.microsoft.com/en-us/azure/container-apps/)
  - [Dapr](https://docs.dapr.io/)
  - [Event Grid](https://docs.microsoft.com/en-us/azure/event-grid/)

## 💡 Tips

1. **Cost Savings**: Scale to zero by setting `minReplicas: 0` in parameters.json
2. **Performance**: Increase `maxReplicas` for handling more load
3. **Monitoring**: Enable Application Insights sampling to reduce costs
4. **Security**: Use Managed Identity instead of access keys (see architecture.md)

## 🎯 Next Steps

After this quick start, consider:

1. ✅ Explore the [Architecture](docs/architecture.md)
2. ✅ Review [Naming Conventions](docs/naming-convention.md)
3. ✅ Set up CI/CD with GitHub Actions
4. ✅ Add custom domain
5. ✅ Enable VNET integration
6. ✅ Configure alerts and dashboards

---

**Need Help?** Check the [Deployment Guide](docs/deployment.md) for detailed troubleshooting.
