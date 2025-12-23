#!/bin/bash

# Local Development with Dapr
# This script runs the API and Worker services locally with Dapr sidecars

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Dapr Demo - Local Development${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Dapr CLI is installed
if ! command -v dapr &> /dev/null; then
    echo -e "${RED}Error: Dapr CLI is not installed${NC}"
    echo "Please install it from: https://docs.dapr.io/getting-started/install-dapr-cli/"
    exit 1
fi

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    exit 1
fi

# Initialize Dapr (if not already initialized)
echo -e "${YELLOW}Checking Dapr installation...${NC}"
dapr --version
echo ""

# Install Python dependencies for API
echo -e "${YELLOW}Installing Python dependencies for API...${NC}"
cd src/api
pip3 install -r requirements.txt
cd ../..

# Install Python dependencies for Worker
echo -e "${YELLOW}Installing Python dependencies for Worker...${NC}"
cd src/worker
pip3 install -r requirements.txt
cd ../..

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Starting Services${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Starting API service with Dapr sidecar...${NC}"
echo -e "${YELLOW}API will be available at: http://localhost:8080${NC}"
echo -e "${YELLOW}Dapr sidecar at: http://localhost:3500${NC}"
echo ""
echo -e "${YELLOW}Starting Worker service with Dapr sidecar...${NC}"
echo -e "${YELLOW}Worker will be available at: http://localhost:8081${NC}"
echo -e "${YELLOW}Dapr sidecar at: http://localhost:3501${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Run API with Dapr in the background
dapr run \
    --app-id api \
    --app-port 8080 \
    --dapr-http-port 3500 \
    --components-path ./.dapr/components \
    --log-level info \
    -- python3 src/api/app.py &

API_PID=$!

# Wait a bit for API to start
sleep 3

# Run Worker with Dapr in the background
dapr run \
    --app-id worker \
    --app-port 8081 \
    --dapr-http-port 3501 \
    --components-path ./.dapr/components \
    --log-level info \
    -- python3 src/worker/app.py &

WORKER_PID=$!

# Function to cleanup on exit
cleanup() {
    echo ""
    echo -e "${YELLOW}Stopping services...${NC}"
    dapr stop --app-id api
    dapr stop --app-id worker
    kill $API_PID 2>/dev/null || true
    kill $WORKER_PID 2>/dev/null || true
    echo -e "${GREEN}Services stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Wait for both processes
wait
