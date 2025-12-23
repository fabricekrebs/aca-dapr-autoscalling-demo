#!/bin/bash

# Build and Push Container Images to Azure Container Registry
# This script builds Docker images for API and Worker services and pushes them to ACR

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
REGISTRY_NAME="acrin${APP_NAME}${INSTANCE}"
IMAGE_TAG="${1:-latest}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Building Container Images${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    exit 1
fi

# Get ACR login server
echo -e "${YELLOW}Getting ACR login server...${NC}"
REGISTRY_LOGIN_SERVER=$(az acr show --name $REGISTRY_NAME --query loginServer -o tsv 2>/dev/null || echo "")

if [ -z "$REGISTRY_LOGIN_SERVER" ]; then
    echo -e "${RED}Error: Container Registry not found. Please deploy infrastructure first.${NC}"
    echo "Run: ./scripts/deploy.sh"
    exit 1
fi

echo -e "${GREEN}Registry:${NC} $REGISTRY_LOGIN_SERVER"
echo -e "${GREEN}Image Tag:${NC} $IMAGE_TAG"
echo ""

# Login to ACR using Azure CLI (works with managed identity and RBAC)
echo -e "${YELLOW}Logging in to Azure Container Registry...${NC}"
az acr login --name $REGISTRY_NAME

# Note: ACR admin credentials are disabled for security.
# Using Azure CLI authentication which leverages your Azure identity.

# Build Dashboard image
echo -e "${YELLOW}Building Dashboard image...${NC}"
docker build -t ${REGISTRY_LOGIN_SERVER}/dashboard:${IMAGE_TAG} -f ./src/dashboard/Dockerfile ./src/dashboard
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Dashboard image built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build Dashboard image${NC}"
    exit 1
fi

# Build Worker image
echo -e "${YELLOW}Building Worker image...${NC}"
docker build -t ${REGISTRY_LOGIN_SERVER}/worker:${IMAGE_TAG} -f ./src/worker/Dockerfile ./src/worker
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Worker image built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build Worker image${NC}"
    exit 1
fi

# Push Dashboard image
echo -e "${YELLOW}Pushing Dashboard image to ACR...${NC}"
docker push ${REGISTRY_LOGIN_SERVER}/dashboard:${IMAGE_TAG}
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Dashboard image pushed successfully${NC}"
else
    echo -e "${RED}✗ Failed to push Dashboard image${NC}"
    exit 1
fi

# Push Worker image
echo -e "${YELLOW}Pushing Worker image to ACR...${NC}"
docker push ${REGISTRY_LOGIN_SERVER}/worker:${IMAGE_TAG}
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Worker image pushed successfully${NC}"
else
    echo -e "${RED}✗ Failed to push Worker image${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Images pushed:${NC}"
echo "  - ${REGISTRY_LOGIN_SERVER}/dashboard:${IMAGE_TAG}"
echo "  - ${REGISTRY_LOGIN_SERVER}/worker:${IMAGE_TAG}"
echo ""
echo -e "${YELLOW}The Container Apps will automatically pull these images.${NC}"
echo -e "${YELLOW}Wait a few minutes for the new revisions to deploy.${NC}"
echo ""
