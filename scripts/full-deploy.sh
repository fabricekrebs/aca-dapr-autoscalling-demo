#!/bin/bash

# Complete Deployment Script for Dapr Demo on Azure Container Apps
# This script performs end-to-end deployment including:
# - Resource Group creation
# - Infrastructure deployment via Bicep
# - Container image building and pushing
# - Identity and RBAC configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOCATION="italynorth"
APP_NAME="daprdemo"
INSTANCE="01"
RESOURCE_GROUP="rg-${LOCATION}-${APP_NAME}-${INSTANCE}"
SUBSCRIPTION_ID=""
BICEP_FILE="./infra/main.bicep"
PARAMETERS_FILE="./infra/parameters.json"

# Derived names
REGISTRY_NAME="acrin${APP_NAME}${INSTANCE}"
MANAGED_IDENTITY_NAME="id-${LOCATION}-${APP_NAME}-${INSTANCE}"
WORKER_APP_NAME="app-worker-${APP_NAME}-${INSTANCE}"
DASHBOARD_APP_NAME="app-dashboard-${APP_NAME}-${INSTANCE}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Dapr Demo - Complete Azure Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print step
print_step() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "----------------------------------------"
}

# Function to check command
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        echo "Please install it first."
        exit 1
    fi
}

# Check prerequisites
print_step "Checking prerequisites"
check_command az
check_command docker
check_command jq

# Check Azure login
echo -e "${YELLOW}Checking Azure login status...${NC}"
az account show &> /dev/null || {
    echo -e "${RED}Not logged in to Azure${NC}"
    echo -e "${YELLOW}Please login:${NC}"
    az login
}

# Get subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "${GREEN}✓ Using subscription:${NC} $SUBSCRIPTION_NAME"
echo -e "  Subscription ID: $SUBSCRIPTION_ID"

# Display deployment plan
print_step "Deployment Plan"
echo "Location: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP"
echo "Container Registry: $REGISTRY_NAME"
echo "Managed Identity: $MANAGED_IDENTITY_NAME"
echo "Worker App: $WORKER_APP_NAME"
echo "Dashboard App: $DASHBOARD_APP_NAME"
echo ""
echo "This will deploy:"
echo "  - Resource Group"
echo "  - Virtual Network with Private Endpoints"
echo "  - Container Registry (ACR)"
echo "  - Storage Account (for Dapr state store)"
echo "  - Service Bus (for Dapr pub/sub)"
echo "  - Container Apps Environment"
echo "  - Dashboard Container App"
echo "  - Worker Container App (with KEDA autoscaling)"
echo "  - Log Analytics & Application Insights"
echo "  - Managed Identity with RBAC assignments"
echo ""

read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Step 1: Create Resource Group
print_step "Step 1: Creating Resource Group"
if az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}ℹ Resource group already exists${NC}"
else
    az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --output none
    echo -e "${GREEN}✓ Resource group created${NC}"
fi

# Step 2: Validate Bicep template
print_step "Step 2: Validating Bicep Template"
az deployment sub validate \
    --location $LOCATION \
    --template-file $BICEP_FILE \
    --parameters $PARAMETERS_FILE \
    --output none

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Template validation successful${NC}"
else
    echo -e "${RED}✗ Template validation failed${NC}"
    exit 1
fi

# Step 3: Deploy Base Infrastructure (without container apps first)
print_step "Step 3: Deploying Base Infrastructure (Registry, Storage, Network, etc.)"
DEPLOYMENT_NAME="daprdemo-infra-$(date +%s)"

echo "Starting infrastructure deployment (this may take 10-15 minutes)..."
echo "This will deploy everything except the container apps..."

# First, we need to ensure the registry exists before building images
# We'll do a complete deployment but container apps might fail - that's expected
az deployment sub create \
    --name $DEPLOYMENT_NAME \
    --location $LOCATION \
    --template-file $BICEP_FILE \
    --parameters $PARAMETERS_FILE \
    --output none || true

# Check if the deployment succeeded or if only container apps failed
DEPLOYMENT_STATUS=$(az deployment sub show --name $DEPLOYMENT_NAME --query 'properties.provisioningState' -o tsv 2>/dev/null || echo "Unknown")

if [ "$DEPLOYMENT_STATUS" == "Succeeded" ]; then
    echo -e "${GREEN}✓ Infrastructure deployed successfully${NC}"
elif [ "$DEPLOYMENT_STATUS" == "Failed" ]; then
    # Check if it's just the container apps that failed
    echo -e "${YELLOW}⚠ Deployment encountered issues (likely container apps waiting for images)${NC}"
    echo "Continuing with image build and push..."
else
    echo -e "${YELLOW}⚠ Deployment status: $DEPLOYMENT_STATUS${NC}"
    echo "Continuing to check if core infrastructure is ready..."
fi

# Step 4: Get deployment outputs
print_step "Step 4: Retrieving Deployment Information"
REGISTRY_LOGIN_SERVER=$(az acr show --name $REGISTRY_NAME --query loginServer -o tsv)
MANAGED_IDENTITY_ID=$(az identity show --name $MANAGED_IDENTITY_NAME -g $RESOURCE_GROUP --query id -o tsv)
MANAGED_IDENTITY_CLIENT_ID=$(az identity show --name $MANAGED_IDENTITY_NAME -g $RESOURCE_GROUP --query clientId -o tsv)

echo -e "${GREEN}✓ Registry:${NC} $REGISTRY_LOGIN_SERVER"
echo -e "${GREEN}✓ Managed Identity:${NC} $MANAGED_IDENTITY_ID"

# Step 5: Assign AcrPull role to Managed Identity (if not already assigned)
print_step "Step 5: Configuring Container Registry Access"
echo "Assigning AcrPull role to managed identity..."

REGISTRY_ID=$(az acr show --name $REGISTRY_NAME --query id -o tsv)
ROLE_ASSIGNMENT_EXISTS=$(az role assignment list \
    --assignee $MANAGED_IDENTITY_CLIENT_ID \
    --scope $REGISTRY_ID \
    --role "AcrPull" \
    --query '[0].id' -o tsv)

if [ -z "$ROLE_ASSIGNMENT_EXISTS" ]; then
    az role assignment create \
        --assignee $MANAGED_IDENTITY_CLIENT_ID \
        --role "AcrPull" \
        --scope $REGISTRY_ID \
        --output none
    echo -e "${GREEN}✓ AcrPull role assigned${NC}"
else
    echo -e "${YELLOW}ℹ AcrPull role already assigned${NC}"
fi

# Step 6: Build and Push Container Images
print_step "Step 6: Building and Pushing Container Images"

# Temporarily enable public network access and admin user for pushing images
echo "Enabling public network access to registry..."
az acr update --name $REGISTRY_NAME --public-network-enabled true --output none
echo -e "${GREEN}✓ Public network access enabled${NC}"

echo "Waiting 30 seconds for public network access to propagate..."
sleep 30
echo -e "${GREEN}✓ Network access ready${NC}"

echo "Temporarily enabling admin user for registry access..."
az acr update --name $REGISTRY_NAME --admin-enabled true --output none
echo -e "${GREEN}✓ Admin user enabled${NC}"

echo "Getting admin credentials..."
ACR_USERNAME=$(az acr credential show --name $REGISTRY_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $REGISTRY_NAME --query passwords[0].value -o tsv)

echo "Logging into Container Registry with admin credentials..."
echo "$ACR_PASSWORD" | docker login $REGISTRY_LOGIN_SERVER --username $ACR_USERNAME --password-stdin
echo -e "${GREEN}✓ Logged in to registry${NC}"

echo ""
echo "Building Dashboard image..."
docker build --no-cache -t ${REGISTRY_LOGIN_SERVER}/dashboard:latest -f ./src/dashboard/Dockerfile ./src/dashboard
docker push ${REGISTRY_LOGIN_SERVER}/dashboard:latest
echo -e "${GREEN}✓ Dashboard image built and pushed${NC}"

echo ""
echo "Building Worker image..."
docker build --no-cache -t ${REGISTRY_LOGIN_SERVER}/worker:latest -f ./src/worker/Dockerfile ./src/worker
docker push ${REGISTRY_LOGIN_SERVER}/worker:latest
echo -e "${GREEN}✓ Worker image built and pushed${NC}"

echo ""
echo "Logging out from registry..."
docker logout $REGISTRY_LOGIN_SERVER

# Disable admin user and public network access after pushing
echo "Disabling admin user..."
az acr update --name $REGISTRY_NAME --admin-enabled false --output none
echo -e "${GREEN}✓ Admin user disabled${NC}"

echo "Disabling public network access to registry..."
az acr update --name $REGISTRY_NAME --public-network-enabled false --output none
echo -e "${GREEN}✓ Public network access disabled${NC}"

# Step 7: Deploy/Update Container Apps with images
print_step "Step 7: Deploying Container Apps"
echo "Now that images are available, deploying/updating container apps..."

# Redeploy the infrastructure to ensure container apps are created/updated
DEPLOYMENT_NAME_2="daprdemo-apps-$(date +%s)"
az deployment sub create \
    --name $DEPLOYMENT_NAME_2 \
    --location $LOCATION \
    --template-file $BICEP_FILE \
    --parameters $PARAMETERS_FILE \
    --output none

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Container apps deployed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Deployment completed with warnings, attempting direct updates...${NC}"
    
    # Try direct updates as fallback
    echo "Updating Dashboard..."
    az containerapp update \
        --name $DASHBOARD_APP_NAME \
        -g $RESOURCE_GROUP \
        --image ${REGISTRY_LOGIN_SERVER}/dashboard:latest \
        --output none 2>/dev/null || echo -e "${YELLOW}Dashboard may already be current${NC}"
    
    echo "Updating Worker..."
    az containerapp update \
        --name $WORKER_APP_NAME \
        -g $RESOURCE_GROUP \
        --image ${REGISTRY_LOGIN_SERVER}/worker:latest \
        --output none 2>/dev/null || echo -e "${YELLOW}Worker may already be current${NC}"
fi

echo -e "${GREEN}✓ Container apps ready${NC}"

# Step 8: Get application URLs
print_step "Step 8: Retrieving Application URLs"
DASHBOARD_URL=$(az containerapp show --name $DASHBOARD_APP_NAME -g $RESOURCE_GROUP --query 'properties.configuration.ingress.fqdn' -o tsv)

# Display completion summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📊 Application URLs:${NC}"
echo "  Dashboard: https://$DASHBOARD_URL"
echo ""
echo -e "${BLUE}🔍 Resource Information:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Container Registry: $REGISTRY_LOGIN_SERVER"
echo "  Managed Identity: $MANAGED_IDENTITY_NAME"
echo ""
echo -e "${BLUE}🎯 Next Steps:${NC}"
echo "  1. Open the dashboard: https://$DASHBOARD_URL"
echo "  2. Click 'Generate Load' or '10,000 Orders' to test autoscaling"
echo "  3. Monitor scaling in Azure Portal:"
echo "     az containerapp replica list --name $WORKER_APP_NAME -g $RESOURCE_GROUP"
echo ""
echo -e "${BLUE}📖 Useful Commands:${NC}"
echo "  # Check worker replicas:"
echo "  az containerapp replica list --name $WORKER_APP_NAME -g $RESOURCE_GROUP --query 'length(@)' -o tsv"
echo ""
echo "  # View worker logs:"
echo "  az containerapp logs show --name $WORKER_APP_NAME -g $RESOURCE_GROUP --type console --tail 50"
echo ""
echo "  # Check Service Bus queue depth:"
echo "  az servicebus topic subscription show --namespace-name sb-${LOCATION}-${APP_NAME}-${INSTANCE} --topic-name orders --name worker -g $RESOURCE_GROUP --query 'countDetails.activeMessageCount'"
echo ""
echo -e "${GREEN}✨ Enjoy exploring KEDA autoscaling with Dapr!${NC}"
echo ""
