# Deployment Guide

This guide provides detailed step-by-step instructions for deploying the Dapr Demo application to Azure with enterprise-grade security using Private Endpoints and Managed Identity.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Infrastructure Deployment](#infrastructure-deployment)
4. [Container Image Deployment](#container-image-deployment)
5. [Verification](#verification)
6. [Testing](#testing)
7. [Monitoring](#monitoring)
8. [Security Considerations](#security-considerations)
9. [Troubleshooting](#troubleshooting)
10. [Cleanup](#cleanup)

## Prerequisites

### Required Tools

1. **Azure CLI** (version 2.50.0 or later)
   ```bash
   # Install on Linux
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Install on macOS
   brew update && brew install azure-cli
   
   # Verify installation
   az --version
   ```

2. **Docker** (version 20.10 or later)
   ```bash
   # Verify installation
   docker --version
   ```

3. **Git**
   ```bash
   # Verify installation
   git --version
   ```

4. **jq** (for JSON parsing in scripts)
   ```bash
   # Install on Linux
   sudo apt-get install jq
   
   # Install on macOS
   brew install jq
   ```

5. **Dapr CLI** (optional, for local development)
   ```bash
   # Install
   wget -q https://raw.githubusercontent.com/dapr/cli/master/install/install.sh -O - | /bin/bash
   
   # Verify
   dapr --version
   ```

### Azure Requirements

1. **Azure Subscription**
   - Active Azure subscription with Contributor or Owner role
   - Sufficient quota for:
     - Container Apps (10 replicas)
     - Storage accounts
     - Container registries
     - Event Grid namespaces
     - Virtual Networks and Private Endpoints

2. **Resource Providers**
   - Ensure the following providers are registered:
     ```bash
     az provider register --namespace Microsoft.App
     az provider register --namespace Microsoft.EventGrid
     az provider register --namespace Microsoft.Storage
     az provider register --namespace Microsoft.ContainerRegistry
     az provider register --namespace Microsoft.OperationalInsights
     az provider register --namespace Microsoft.Network
     ```

3. **Permissions**
   - Ability to create resource groups
   - Ability to create resources in Italy North region
   - Ability to assign RBAC roles (required for Managed Identity)

## Initial Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd dapr
```

### 2. Login to Azure

```bash
# Login interactively
az login

# Verify login
az account show

# (Optional) Set specific subscription
az account set --subscription "<subscription-id-or-name>"
```

### 3. Verify Current Configuration

```bash
# Show current subscription
az account show --query "{Name:name, ID:id, TenantID:tenantId}" -o table

# List available locations
az account list-locations --query "[?name=='italynorth']" -o table
```

## Infrastructure Deployment

### Step 1: Review Parameters

Edit `infra/parameters.json` if needed:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "italynorth"
    },
    "appName": {
      "value": "daprdemo"
    },
    "instance": {
      "value": "01"
    },
    "minReplicas": {
      "value": 1
    },
    "maxReplicas": {
      "value": 10
    }
  }
}
```

### Step 2: Validate Bicep Template

```bash
# Validate the template
az deployment sub validate \
    --location italynorth \
    --template-file ./infra/main.bicep \
    --parameters ./infra/parameters.json

# Check for warnings or errors
```

### Step 3: Deploy Infrastructure

#### Option A: Using the Deployment Script (Recommended)

```bash
# Make script executable
chmod +x ./scripts/deploy.sh

# Run deployment
./scripts/deploy.sh
```

The script will:
- Verify Azure login
- Show deployment preview
- Ask for confirmation
- Validate Bicep template
- Deploy all resources
- Display deployment outputs

#### Option B: Manual Deployment

```bash
# Create deployment
DEPLOYMENT_NAME="daprdemo-deployment-$(date +%Y%m%d-%H%M%S)"

az deployment sub create \
    --name $DEPLOYMENT_NAME \
    --location italynorth \
    --template-file ./infra/main.bicep \
    --parameters ./infra/parameters.json \
    --verbose

# Wait for deployment to complete (typically 5-10 minutes)
```

### Step 4: Verify Infrastructure Deployment

```bash
# Check deployment status
az deployment sub show \
    --name $DEPLOYMENT_NAME \
    --query "properties.provisioningState" -o tsv

# List created resources
az resource list \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table

# Get deployment outputs
az deployment sub show \
    --name $DEPLOYMENT_NAME \
    --query "properties.outputs" -o json
```

Expected resources:
- ✅ Resource Group: `rg-italynorth-daprdemo-01`
- ✅ Container Registry: `acrindaprdemo01`
- ✅ Storage Account: `saindaprdemo01`
- ✅ Event Grid Namespace: `egns-italynorth-daprdemo-01`
- ✅ Container Apps Environment: `env-italynorth-daprdemo-01`
- ✅ Container App (API): `app-italynorth-daprdemo-api-01`
- ✅ Container App (Worker): `app-italynorth-daprdemo-worker-01`
- ✅ Log Analytics: `law-italynorth-daprdemo-01`
- ✅ Application Insights: `ai-italynorth-daprdemo-01`

## Container Image Deployment

### Step 1: Build and Push Images

#### Option A: Using the Build Script (Recommended)

```bash
# Make script executable
chmod +x ./scripts/build-images.sh

# Build and push images with default tag (latest)
./scripts/build-images.sh

# Or specify a custom tag
./scripts/build-images.sh v1.0.0
```

#### Option B: Manual Build and Push

```bash
# Get registry details
REGISTRY_NAME="acrindaprdemo01"
REGISTRY_LOGIN_SERVER=$(az acr show --name $REGISTRY_NAME --query loginServer -o tsv)

# Login to ACR
az acr login --name $REGISTRY_NAME

# Build API image
docker build -t ${REGISTRY_LOGIN_SERVER}/api:latest -f ./src/api/Dockerfile ./src/api

# Build Worker image
docker build -t ${REGISTRY_LOGIN_SERVER}/worker:latest -f ./src/worker/Dockerfile ./src/worker

# Push API image
docker push ${REGISTRY_LOGIN_SERVER}/api:latest

# Push Worker image
docker push ${REGISTRY_LOGIN_SERVER}/worker:latest
```

### Step 2: Verify Images in Registry

```bash
# List repositories
az acr repository list --name $REGISTRY_NAME -o table

# Show tags for API
az acr repository show-tags --name $REGISTRY_NAME --repository api -o table

# Show tags for Worker
az acr repository show-tags --name $REGISTRY_NAME --repository worker -o table
```

### Step 3: Wait for Container Apps to Update

```bash
# Container Apps automatically pull new images
# Check API revision status
az containerapp revision list \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table

# Check Worker revision status
az containerapp revision list \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table

# Wait for "Running" status (typically 2-3 minutes)
```

## Verification

### Step 1: Get API Endpoint

```bash
# Get API FQDN
API_FQDN=$(az containerapp show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query properties.configuration.ingress.fqdn \
    -o tsv)

echo "API URL: https://$API_FQDN"
```

### Step 2: Test Health Endpoints

```bash
# Test API health
curl https://$API_FQDN/health | jq .

# Expected output:
# {
#   "status": "healthy",
#   "service": "api",
#   "timestamp": "2025-12-22T..."
# }

# Test API readiness
curl https://$API_FQDN/ready | jq .

# Test API root
curl https://$API_FQDN/ | jq .
```

### Step 3: Check Container App Status

```bash
# Check API status
az containerapp show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query "properties.{Status:runningStatus, Replicas:template.scale, Ingress:configuration.ingress.fqdn}" \
    -o table

# Check Worker status
az containerapp show \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query "properties.{Status:runningStatus, Replicas:template.scale}" \
    -o table
```

## Testing

### Step 1: Automated Testing

```bash
# Make test script executable
chmod +x ./scripts/test-api.sh

# Run automated tests
./scripts/test-api.sh
```

### Step 2: Manual Testing

#### Create an Order

```bash
# Create order
curl -X POST https://$API_FQDN/api/orders \
    -H "Content-Type: application/json" \
    -d '{
        "order_id": "order-001",
        "customer_name": "John Doe",
        "items": ["Widget A", "Widget B"],
        "total": 149.99
    }' | jq .

# Expected output:
# {
#   "message": "Order created and published successfully",
#   "order_id": "order-001",
#   "status": "published"
# }
```

#### Verify Event Processing

```bash
# Wait 5-10 seconds for worker to process
sleep 10

# Retrieve processed order
curl https://$API_FQDN/api/orders/order-001 | jq .

# Expected output includes:
# {
#   "order_id": "order-001",
#   "customer_name": "John Doe",
#   "status": "processed",
#   "processed_at": "2025-12-22T...",
#   "processed_by": "worker-service",
#   ...
# }
```

### Step 3: Test Autoscaling

#### Generate Load

```bash
# Install hey (load generator)
# macOS: brew install hey
# Linux: go install github.com/rakyll/hey@latest

# Generate load (50 concurrent requests for 60 seconds)
hey -z 60s -c 50 https://$API_FQDN/health
```

#### Monitor Scaling

```bash
# Watch replica count (run in separate terminal)
watch -n 2 'az containerapp replica list \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --output table'

# You should see replicas increase as load increases
```

## Monitoring

### View Logs

#### API Logs

```bash
# Stream API logs
az containerapp logs show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow

# View last 50 lines
az containerapp logs show \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --tail 50
```

#### Worker Logs

```bash
# Stream Worker logs
az containerapp logs show \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --follow
```

### Application Insights

```bash
# Open Application Insights in browser
APP_INSIGHTS_ID=$(az monitor app-insights component show \
    --app ai-italynorth-daprdemo-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --query id -o tsv)

az portal show --resource $APP_INSIGHTS_ID
```

### Log Analytics Queries

```bash
# Query Container App logs
az monitor log-analytics query \
    --workspace $(az monitor log-analytics workspace show \
        --resource-group rg-italynorth-daprdemo-01 \
        --workspace-name law-italynorth-daprdemo-01 \
        --query customerId -o tsv) \
    --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h) | order by TimeGenerated desc | limit 100" \
    --output table
```

## Security Considerations

### Private Endpoint Deployment

All Azure services (Storage, Event Grid, Container Registry) are deployed with Private Endpoints, meaning they are not accessible from the public internet.

#### Understanding Private Endpoints

**What happens during deployment:**

1. **VNET Creation** (first):
   - Virtual network: `vnet-italynorth-daprdemo-01`
   - Container Apps subnet: `10.0.0.0/23` (512 addresses)
   - Private Endpoints subnet: `10.0.2.0/24` (256 addresses)

2. **Private DNS Zones** (first):
   - `privatelink.blob.core.windows.net` - for Blob Storage
   - `privatelink.azurecr.io` - for Container Registry
   - `privatelink.eventgrid.azure.net` - for Event Grid

3. **Azure Services** (next):
   - Storage Account with `publicNetworkAccess=Disabled`
   - Event Grid with `publicNetworkAccess=Disabled`
   - Container Registry with `publicNetworkAccess=Disabled`

4. **Private Endpoints** (automatically):
   - Each service gets a private IP in the PE subnet (10.0.2.x)
   - DNS records automatically created in Private DNS zones
   - Container Apps resolve service names to private IPs

#### Implications

**During Deployment:**
- You cannot directly access Storage/Event Grid/ACR from your local machine
- Container Apps communicate internally via Private Endpoints
- Image builds must be pushed from a machine that can access ACR

**For Build and Push:**
```bash
# Option 1: Use Azure Cloud Shell (has network access to private endpoints)
# Upload your code and run:
./scripts/build-images.sh

# Option 2: Use Azure VM or GitHub Actions runner in the same VNET

# Option 3: Temporarily enable public access for initial deployment
# (Not recommended for production)
```

### Managed Identity Configuration

All authentication uses Managed Identity instead of access keys.

#### Identity Assignment

The deployment creates a User-Assigned Managed Identity: `id-italynorth-daprdemo-01`

**RBAC Role Assignments:**

1. **Storage Blob Data Contributor**
   - Scope: Storage Account (`saindaprdemo01`)
   - Purpose: Allows Dapr to read/write state to blob storage
   - Assigned during infrastructure deployment

2. **EventGrid Data Sender**
   - Scope: Event Grid Namespace (`egns-italynorth-daprdemo-01`)
   - Purpose: Allows Dapr to publish events
   - Assigned during infrastructure deployment

3. **AcrPull**
   - Scope: Container Registry (`acrindaprdemo01`)
   - Purpose: Allows Container Apps to pull images
   - Assigned during infrastructure deployment

#### RBAC Propagation Delay

**Important:** RBAC role assignments can take 5-10 minutes to propagate.

**Symptoms of propagation delay:**
- Container Apps fail to pull images (403 errors)
- Dapr components fail to access Storage/Event Grid
- Authentication errors in logs

**Solution:**
```bash
# Wait 5-10 minutes after initial deployment before pushing images
# Check role assignment status:
az role assignment list \
    --assignee $(az identity show \
        --name id-italynorth-daprdemo-01 \
        --resource-group rg-italynorth-daprdemo-01 \
        --query principalId -o tsv) \
    --output table
```

### Network Connectivity

#### Container Apps Environment

- Connected to VNET subnet: `10.0.0.0/23`
- Has outbound connectivity to Private Endpoints in `10.0.2.0/24`
- API has external ingress enabled (HTTPS only)
- Worker has no external ingress (internal only)

#### DNS Resolution

All Azure service FQDNs resolve to private IPs:

```bash
# Example DNS resolution from within Container Apps:
# saindaprdemo01.blob.core.windows.net → 10.0.2.4 (private IP)
# acrindaprdemo01.azurecr.io → 10.0.2.5 (private IP)
# egns-italynorth-daprdemo-01.*.eventgrid.azure.net → 10.0.2.6 (private IP)
```

### Security Best Practices

#### After Deployment

1. **Verify Public Access is Disabled:**
   ```bash
   # Check Storage Account
   az storage account show \
       --name saindaprdemo01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --query "publicNetworkAccess" -o tsv
   # Should return: Disabled

   # Check Event Grid
   az eventgrid namespace show \
       --name egns-italynorth-daprdemo-01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --query "publicNetworkAccess" -o tsv
   # Should return: Disabled

   # Check Container Registry
   az acr show \
       --name acrindaprdemo01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --query "{publicAccess:publicNetworkAccess, adminUser:adminUserEnabled}" -o json
   # Should return: publicNetworkAccess=Disabled, adminUserEnabled=false
   ```

2. **Verify Managed Identity Assignments:**
   ```bash
   # List all role assignments for the managed identity
   az role assignment list \
       --assignee $(az identity show \
           --name id-italynorth-daprdemo-01 \
           --resource-group rg-italynorth-daprdemo-01 \
           --query principalId -o tsv) \
       --all \
       --output table
   ```

3. **Review Network Security:**
   ```bash
   # List Private Endpoints
   az network private-endpoint list \
       --resource-group rg-italynorth-daprdemo-01 \
       --output table

   # Verify Private DNS Zone Links
   az network private-dns link vnet list \
       --resource-group rg-italynorth-daprdemo-01 \
       --zone-name privatelink.blob.core.windows.net \
       --output table
   ```

#### Deployment from Local Machine

Since services use Private Endpoints, you cannot directly access them from your local machine. Use one of these approaches:

**Option 1: Azure Cloud Shell (Recommended)**
```bash
# Upload your code to Cloud Shell
# Cloud Shell has network connectivity to private endpoints
git clone <your-repo>
cd dapr
./scripts/deploy.sh
./scripts/build-images.sh
```

**Option 2: Azure DevOps / GitHub Actions**
```yaml
# Use self-hosted runners in the same VNET or Azure-hosted agents
# Example GitHub Actions workflow would include:
- name: Login to Azure
  uses: azure/login@v1
  
- name: Deploy Infrastructure
  run: ./scripts/deploy.sh
  
- name: Build and Push Images
  run: ./scripts/build-images.sh
```

**Option 3: Azure Bastion / Jump Server**
```bash
# Deploy an Azure VM in the same VNET
# Use Azure Bastion to connect securely
# Run deployment commands from the VM
```

### Troubleshooting Security Issues

#### Issue: Cannot Push Images to ACR

**Error:** `Error response from daemon: Get "https://acrindaprdemo01.azurecr.io/v2/": dial tcp: lookup acrindaprdemo01.azurecr.io: no such host`

**Cause:** Your machine doesn't have access to the private endpoint

**Solution:**
- Use Azure Cloud Shell or VM in the same VNET
- Or temporarily add your IP to ACR firewall (not recommended for production)

#### Issue: Container Apps Cannot Pull Images

**Error:** `Failed to pull image: authentication required`

**Cause:** RBAC role assignment not yet propagated

**Solution:**
```bash
# Wait 5-10 minutes and trigger a new revision
az containerapp revision copy \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01
```

#### Issue: Dapr Components Cannot Access Storage/Event Grid

**Error:** `AuthorizationPermissionMismatch` in Dapr sidecar logs

**Cause:** Managed Identity doesn't have required RBAC roles

**Solution:**
```bash
# Verify role assignments exist
az role assignment list \
    --assignee $(az identity show \
        --name id-italynorth-daprdemo-01 \
        --resource-group rg-italynorth-daprdemo-01 \
        --query principalId -o tsv) \
    --all \
    --query "[].{Role:roleDefinitionName, Scope:scope}" \
    --output table

# If missing, they should be created automatically during deployment
# Wait 5-10 minutes for propagation
```

## Troubleshooting

### Issue: Container App Not Starting

**Symptoms**: Container app shows "Provisioning" or "Failed" status

**Solutions**:

1. Check container logs:
   ```bash
   az containerapp logs show \
       --name app-italynorth-daprdemo-api-01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --tail 100
   ```

2. Verify image exists in registry:
   ```bash
   az acr repository show \
       --name acrindaprdemo01 \
       --repository api
   ```

3. Check revision provisioning state:
   ```bash
   az containerapp revision list \
       --name app-italynorth-daprdemo-api-01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --query "[].{Name:name, Status:properties.provisioningState}" \
       -o table
   ```

### Issue: Events Not Being Delivered

**Symptoms**: Orders created but not processed by worker

**Solutions**:

1. Check Event Grid metrics:
   ```bash
   az monitor metrics list \
       --resource $(az eventgrid namespace show \
           --name egns-italynorth-daprdemo-01 \
           --resource-group rg-italynorth-daprdemo-01 \
           --query id -o tsv) \
       --metric "PublishedEvents"
   ```

2. Check Worker subscription:
   ```bash
   # View Worker logs for subscription info
   az containerapp logs show \
       --name app-italynorth-daprdemo-worker-01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --tail 50 | grep -i subscribe
   ```

3. Verify Dapr component configuration:
   ```bash
   az containerapp env dapr-component show \
       --name eventgrid-pubsub \
       --environment-name env-italynorth-daprdemo-01 \
       --resource-group rg-italynorth-daprdemo-01
   ```

### Issue: Cannot Access API

**Symptoms**: API endpoint returns connection errors

**Solutions**:

1. Verify ingress is enabled:
   ```bash
   az containerapp show \
       --name app-italynorth-daprdemo-api-01 \
       --resource-group rg-italynorth-daprdemo-01 \
       --query "properties.configuration.ingress" -o json
   ```

2. Check if external ingress is enabled:
   ```bash
   # Should show "external": true
   ```

3. Test from within Azure:
   ```bash
   # Use Cloud Shell or Azure VM in same region
   ```

### Get Support

1. **View all resources**:
   ```bash
   az resource list \
       --resource-group rg-italynorth-daprdemo-01 \
       --output table
   ```

2. **Export deployment template**:
   ```bash
   az deployment sub export \
       --name $DEPLOYMENT_NAME \
       --output json > deployment-export.json
   ```

3. **Check Azure Service Health**:
   ```bash
   az rest --method get \
       --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2020-05-01"
   ```

## Cleanup

### Delete All Resources

```bash
# Delete resource group (deletes all resources)
az group delete \
    --name rg-italynorth-daprdemo-01 \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-italynorth-daprdemo-01
```

### Selective Cleanup

```bash
# Delete only Container Apps (keep infrastructure)
az containerapp delete \
    --name app-italynorth-daprdemo-api-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --yes

az containerapp delete \
    --name app-italynorth-daprdemo-worker-01 \
    --resource-group rg-italynorth-daprdemo-01 \
    --yes

# Delete only images (keep registry)
az acr repository delete \
    --name acrindaprdemo01 \
    --repository api \
    --yes

az acr repository delete \
    --name acrindaprdemo01 \
    --repository worker \
    --yes
```

## Next Steps

After successful deployment:

1. **Set up CI/CD** - Automate deployments with GitHub Actions or Azure DevOps
2. **Configure custom domain** - Add custom DNS with SSL certificates
3. **Configure alerts** - Set up monitoring alerts in Application Insights
4. **Implement API Management** - Add API gateway for advanced features
5. **Add more services** - Extend the architecture with additional microservices
6. **Review security posture** - Regular security audits and compliance checks

## Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Private Endpoint Documentation](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Azure Managed Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [Dapr Documentation](https://docs.dapr.io/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Container Apps Networking](https://docs.microsoft.com/en-us/azure/container-apps/networking)

---

**Last Updated**: December 22, 2025  
**Version**: 2.0 (Security Enhanced)
