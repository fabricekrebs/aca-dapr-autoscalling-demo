#!/bin/bash

# Deploy Dapr Demo Infrastructure to Azure
# This script deploys all Azure resources using Bicep

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
LOCATION="italynorth"
APP_NAME="daprdemo"
INSTANCE="01"
RESOURCE_GROUP="rg-${LOCATION}-${APP_NAME}-${INSTANCE}"
BICEP_FILE="./infra/main.bicep"
PARAMETERS_FILE="./infra/parameters.json"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Dapr Demo - Azure Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
echo -e "${YELLOW}Checking Azure login status...${NC}"
az account show &> /dev/null || {
    echo -e "${RED}Not logged in to Azure${NC}"
    echo -e "${YELLOW}Please login:${NC}"
    az login
}

# Get current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}Using subscription:${NC} $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo ""

# Confirm deployment
echo -e "${YELLOW}This will deploy the following resources:${NC}"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - Location: $LOCATION"
echo "  - Container Registry: acrin${APP_NAME}${INSTANCE}"
echo "  - Storage Account: sain${APP_NAME}${INSTANCE}"
echo "  - Event Grid Namespace: egns-${LOCATION}-${APP_NAME}-${INSTANCE}"
echo "  - Container Apps Environment: env-${LOCATION}-${APP_NAME}-${INSTANCE}"
echo "  - API Container App: app-${LOCATION}-${APP_NAME}-api-${INSTANCE}"
echo "  - Worker Container App: app-${LOCATION}-${APP_NAME}-worker-${INSTANCE}"
echo "  - Log Analytics Workspace: law-${LOCATION}-${APP_NAME}-${INSTANCE}"
echo "  - Application Insights: ai-${LOCATION}-${APP_NAME}-${INSTANCE}"
echo ""

read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Validate Bicep template
echo -e "${YELLOW}Validating Bicep template...${NC}"
az deployment sub validate \
    --location $LOCATION \
    --template-file $BICEP_FILE \
    --parameters $PARAMETERS_FILE

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Template validation successful${NC}"
else
    echo -e "${RED}✗ Template validation failed${NC}"
    exit 1
fi

# Deploy infrastructure
echo -e "${YELLOW}Deploying infrastructure...${NC}"
DEPLOYMENT_NAME="daprdemo-infra-deployment"

az deployment sub create \
    --name $DEPLOYMENT_NAME \
    --location $LOCATION \
    --template-file $BICEP_FILE \
    --parameters $PARAMETERS_FILE

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Infrastructure deployment successful${NC}"
else
    echo -e "${RED}✗ Infrastructure deployment failed${NC}"
    exit 1
fi

# Get deployment outputs
echo -e "${YELLOW}Retrieving deployment outputs...${NC}"
REGISTRY_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.containerRegistryName.value -o tsv)
REGISTRY_LOGIN_SERVER=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.containerRegistryLoginServer.value -o tsv)
API_FQDN=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.apiAppFQDN.value -o tsv)
WORKER_FQDN=$(az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs.workerAppFQDN.value -o tsv)

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Container Registry:${NC}"
echo "  Name: $REGISTRY_NAME"
echo "  Login Server: $REGISTRY_LOGIN_SERVER"
echo ""
echo -e "${GREEN}Container Apps:${NC}"
echo "  API: https://$API_FQDN"
echo "  Worker: https://$WORKER_FQDN"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Build and push container images:"
echo "     ./scripts/build-images.sh"
echo ""
echo "  2. Test the API:"
echo "     curl https://$API_FQDN/health"
echo ""
echo "  3. Create an order:"
echo "     curl -X POST https://$API_FQDN/api/orders \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"order_id\": \"order-001\", \"customer_name\": \"John Doe\", \"items\": [\"item1\", \"item2\"], \"total\": 99.99}'"
echo ""
