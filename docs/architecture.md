# Architecture Overview

This document describes the architecture of the Dapr Demo application running on Azure Container Apps with enterprise-grade security using Private Endpoints and Managed Identity.

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Virtual Network (vnet-italynorth-daprdemo-01)        │
│                                 10.0.0.0/16                              │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │      Container Apps Subnet (snet-italynorth-daprdemo-apps-01)      │  │
│  │                         10.0.0.0/23                                │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │       Container Apps Environment (env-*)                    │  │  │
│  │  │                                                             │  │  │
│  │  │  ┌──────────────────┐        ┌──────────────────┐         │  │  │
│  │  │  │  API App         │        │  Worker App      │         │  │  │
│  │  │  │  + Dapr :3500    │        │  + Dapr :3501    │         │  │  │
│  │  │  │  + Managed ID    │        │  + Managed ID    │         │  │  │
│  │  │  └────────┬─────────┘        └────────┬─────────┘         │  │  │
│  │  └───────────┼──────────────────────────┼────────────────────┘  │  │
│  └──────────────┼──────────────────────────┼───────────────────────┘  │
│                 │                          │                           │
│  ┌──────────────┼──────────────────────────┼───────────────────────┐  │
│  │  Private Endpoints Subnet (snet-italynorth-daprdemo-pe-01)      │  │
│  │                     10.0.2.0/24                                 │  │
│  │                                                                 │  │
│  │    ┌────────────┐     ┌────────────┐     ┌────────────┐      │  │
│  │    │ Blob PE    │     │ Event Grid │     │   ACR PE   │      │  │
│  │    │ (Storage)  │     │    PE      │     │            │      │  │
│  │    └─────┬──────┘     └─────┬──────┘     └─────┬──────┘      │  │
│  └──────────┼──────────────────┼──────────────────┼─────────────┘  │
│             │                  │                  │                  │
└─────────────┼──────────────────┼──────────────────┼──────────────────┘
              │ Private          │ Private          │ Private
              │ Connection       │ Connection       │ Connection
              │                  │                  │
     ┌────────▼────────┐  ┌─────▼──────┐  ┌────────▼────────┐
     │  Blob Storage   │  │ Event Grid │  │ Container Reg.  │
     │  (State Store)  │  │  (Pub/Sub) │  │  (Images)       │
     │  Public: OFF    │  │ Public: OFF│  │  Public: OFF    │
     └─────────────────┘  └────────────┘  └─────────────────┘

   Authentication: Managed Identity (id-italynorth-daprdemo-01)
   - Storage Blob Data Contributor (State Store)
   - EventGrid Data Sender (Pub/Sub)
   - AcrPull (Container Images)
```

## Components

### 1. API Service

**Purpose**: REST API for order management

**Container App**: `app-italynorth-daprdemo-api-01`

**Endpoints**:
- `GET /` - Service information
- `GET /health` - Health check (liveness probe)
- `GET /ready` - Readiness check (readiness probe)
- `POST /api/orders` - Create new order and publish event
- `GET /api/orders/{order_id}` - Retrieve order from state store

**Dapr Integration**:
- **App ID**: `api`
- **App Port**: `8080`
- **Dapr Port**: `3500`
- **Publishes to**: Event Grid topic `orders` via `eventgrid-pubsub` component
- **Reads from**: State store via `statestore` component

**Autoscaling**:
- Min replicas: 1
- Max replicas: 10
- Triggers:
  - HTTP: 10 concurrent requests
  - CPU: 70% utilization
  - Memory: 80% utilization

### 2. Worker Service

**Purpose**: Background processor for order events

**Container App**: `app-italynorth-daprdemo-worker-01`

**Endpoints**:
- `GET /` - Service information
- `GET /health` - Health check (liveness probe)
- `GET /ready` - Readiness check (readiness probe)
- `GET /dapr/subscribe` - Dapr subscription endpoint
- `POST /orders` - Event handler for order events

**Dapr Integration**:
- **App ID**: `worker`
- **App Port**: `8081`
- **Dapr Port**: `3501`
- **Subscribes to**: Event Grid topic `orders` via `eventgrid-pubsub` component
- **Writes to**: State store via `statestore` component

**Autoscaling**:
- Min replicas: 1
- Max replicas: 10
- Triggers:
  - HTTP: 10 concurrent requests
  - CPU: 70% utilization
  - Memory: 80% utilization

## Dapr Components

### Event Grid Pub/Sub Component

**Name**: `eventgrid-pubsub`

**Type**: `pubsub.azure.eventgrid`

**Authentication**: Managed Identity (no access keys)

**Configuration**:
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: eventgrid-pubsub
spec:
  type: pubsub.azure.eventgrid
  version: v1
  metadata:
  - name: endpoint
    value: <Event Grid namespace endpoint>
  - name: azureClientId
    value: <Managed Identity Client ID>
  - name: topicEndpoint
    value: <Topic endpoint>
scopes:
- api
- worker
```

**Azure Resource**: `egns-italynorth-daprdemo-01`

**Topic**: `orders`

**Security**:
- Private Endpoint enabled
- Public network access disabled
- Managed Identity authentication via EventGrid Data Sender role

**Features**:
- CloudEvents 1.0 schema
- 1-day event retention
- Dead-letter queue for failed deliveries
- Max 10 delivery attempts

### State Store Component

**Name**: `statestore`

**Type**: `state.azure.blobstorage`

**Authentication**: Managed Identity (no account keys)

**Configuration**:
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: statestore
spec:
  type: state.azure.blobstorage
  version: v1
  metadata:
  - name: accountName
    value: saindaprdemo01
  - name: azureClientId
    value: <Managed Identity Client ID>
  - name: containerName
    value: dapr-state
scopes:
- api
- worker
```

**Azure Resource**: `saindaprdemo01`

**Container**: `dapr-state`

**Security**:
- Private Endpoint enabled
- Public network access disabled
- Managed Identity authentication via Storage Blob Data Contributor role

**Features**:
- Blob storage for state persistence
- Key-value access pattern
- TTL support
- Encryption at rest

## Communication Flow

### Order Creation Flow (with Private Endpoints)

```
1. Client sends POST request to API (via public ingress)
   ↓
2. API validates order data
   ↓
3. API calls Dapr sidecar to publish event
   ↓
4. Dapr authenticates using Managed Identity (EventGrid Data Sender)
   ↓
5. Dapr publishes event to Event Grid via Private Endpoint
   ↓
6. Event Grid delivers event to Worker subscription (within VNET)
   ↓
7. Dapr delivers event to Worker app
   ↓
8. Worker processes order
   ↓
9. Worker calls Dapr sidecar to save state
   ↓
10. Dapr authenticates using Managed Identity (Storage Blob Data Contributor)
    ↓
11. Dapr saves state to Blob Storage via Private Endpoint
    ↓
12. Worker returns success to Dapr
    ↓
13. Event Grid marks event as delivered
```

### Order Retrieval Flow (with Private Endpoints)

```
1. Client sends GET request to API for order (via public ingress)
   ↓
2. API calls Dapr sidecar to get state
   ↓
3. Dapr authenticates using Managed Identity (Storage Blob Data Contributor)
   ↓
4. Dapr retrieves state from Blob Storage via Private Endpoint
   ↓
5. Dapr returns state to API
   ↓
6. API returns order data to client
```

### Private Endpoint DNS Resolution

All Azure services are accessed via Private Endpoints with private DNS zones:

1. **Blob Storage**: `privatelink.blob.core.windows.net`
   - `saindaprdemo01.blob.core.windows.net` → `10.0.2.x` (private IP)

2. **Event Grid**: `privatelink.eventgrid.azure.net`
   - `egns-italynorth-daprdemo-01.*.eventgrid.azure.net` → `10.0.2.y` (private IP)

3. **Container Registry**: `privatelink.azurecr.io`
   - `acrindaprdemo01.azurecr.io` → `10.0.2.z` (private IP)

## Container Apps Environment

**Name**: `env-italynorth-daprdemo-01`

**Network Configuration**:
- **VNET Integration**: Connected to `vnet-italynorth-daprdemo-01`
- **Subnet**: `snet-italynorth-daprdemo-apps-01` (10.0.0.0/23)
- **Internal only**: No (external ingress enabled for API)

**Features**:
- **Dapr enabled** - Automatic sidecar injection
- **Log Analytics integration** - Centralized logging
- **Application Insights** - Distributed tracing
- **Managed Identity** - Assigned to all container apps
- **Ingress** - HTTP/HTTPS traffic management
- **Scaling** - KEDA-based autoscaling

**Dapr Configuration**:
- Dapr version: Latest stable
- Metrics enabled: Yes
- Tracing enabled: Yes (Application Insights)
- mTLS enabled: Yes (between sidecars)
- API logging: Enabled
- Component secrets: Managed Identity authentication (no keys)

## Autoscaling Details

### HTTP-Based Scaling

```yaml
rules:
  - name: http-scaling
    http:
      metadata:
        concurrentRequests: '10'
```

**Behavior**:
- Scales up when concurrent requests exceed 10 per replica
- Scales down when requests drop below threshold
- Fast response to traffic spikes

### CPU-Based Scaling

```yaml
rules:
  - name: cpu-scaling
    custom:
      type: cpu
      metadata:
        type: Utilization
        value: '70'
```

**Behavior**:
- Scales up when CPU utilization exceeds 70%
- Scales down when CPU drops below threshold
- Protects against CPU exhaustion

### Memory-Based Scaling

```yaml
rules:
  - name: memory-scaling
    custom:
      type: memory
      metadata:
        type: Utilization
        value: '80'
```

**Behavior**:
- Scales up when memory utilization exceeds 80%
- Scales down when memory drops below threshold
- Prevents out-of-memory errors

### Scaling Characteristics

- **Scale-up**: Fast (within seconds)
- **Scale-down**: Gradual (configurable cooldown period)
- **Min replicas**: 1 (always available)
- **Max replicas**: 10 (cost control)
- **Target**: Maintain performance under load

## Monitoring & Observability

### Application Insights

**Name**: `ai-italynorth-daprdemo-01`

**Collects**:
- HTTP request traces
- Dependency calls (Dapr, Event Grid, Storage)
- Exceptions and errors
- Custom events and metrics
- Performance counters

**Features**:
- Distributed tracing across services
- Application map visualization
- Real-time metrics
- Failure analysis
- Performance profiling

### Log Analytics Workspace

**Name**: `law-italynorth-daprdemo-01`

**Collects**:
- Container logs (stdout/stderr)
- Dapr sidecar logs
- System logs
- Metrics (CPU, memory, network)

**Retention**: 30 days

**Query Language**: KQL (Kusto Query Language)

### Key Metrics to Monitor

1. **HTTP Metrics**:
   - Request rate
   - Response time (p50, p95, p99)
   - Error rate
   - Status code distribution

2. **Autoscaling Metrics**:
   - Current replica count
   - Scale events
   - CPU/Memory utilization
   - Concurrent requests

3. **Dapr Metrics**:
   - Pub/sub publish latency
   - State store operations
   - Component failures
   - Sidecar health

4. **Event Grid Metrics**:
   - Events published
   - Events delivered
   - Delivery failures
   - Delivery latency

## Security

### Network Security

- **VNET Integration** - All resources deployed within private virtual network
- **Private Endpoints** - All Azure services (Storage, Event Grid, ACR) accessible only via private IPs
- **Private DNS Zones** - Automatic DNS resolution to private endpoints
- **Public Access Disabled** - No internet-facing endpoints for backend services
- **HTTPS only** - All external traffic encrypted
- **Service-to-service mTLS** - Dapr automatically secures inter-service communication
- **Network Isolation** - Separate subnets for Container Apps and Private Endpoints

### Authentication & Authorization

- **Managed Identity** - User-assigned identity for all container apps
- **RBAC Roles**:
  - Storage Blob Data Contributor (for state store)
  - EventGrid Data Sender (for pub/sub)
  - AcrPull (for container image pulls)
- **No Access Keys** - Zero reliance on storage account keys or Event Grid access keys
- **Container Registry** - Admin user disabled, authentication via Managed Identity

### Secrets Management

- **No Secrets Required** - Managed Identity eliminates need for credentials
- **Container Apps environment** - Dapr components configured with Managed Identity client ID
- **Key Vault integration** - Can be added for application-specific secrets if needed

### Security Benefits

1. **Zero Trust Architecture** - No standing credentials to rotate or leak
2. **Least Privilege Access** - RBAC grants only required permissions
3. **Network Isolation** - Resources not accessible from internet
4. **Audit Trail** - All Managed Identity operations logged in Azure Activity Log
5. **Compliance** - Meets enterprise security requirements for private networking

## Deployment Model

### Infrastructure as Code

- **Bicep templates** - Declarative infrastructure
- **Modular design** - Reusable modules
- **Parameterized** - Environment-agnostic
- **Version controlled** - Git repository

### Container Images

- **Registry**: `acrindaprdemo01` (Private Endpoint enabled)
- **API image**: `acrindaprdemo01.azurecr.io/api:latest`
- **Worker image**: `acrindaprdemo01.azurecr.io/worker:latest`
- **Multi-stage builds** - Optimized image size
- **Non-root user** - Enhanced security
- **Authentication** - Managed Identity (AcrPull role)

### Deployment Process

1. **Build images** - Docker build
2. **Push to ACR** - Azure Container Registry
3. **Deploy infrastructure** - Bicep deployment
4. **Update revisions** - Container Apps pulls new images
5. **Traffic switch** - Gradual or instant

## Cost Considerations

### Pricing Components

1. **Container Apps**:
   - Compute (vCPU-seconds)
   - Memory (GiB-seconds)
   - Requests (first 2M free)

2. **Event Grid**:
   - Operations (publish, deliver)
   - Storage (minimal)

3. **Storage Account**:
   - Blob storage (GiB-month)
   - Operations (reads, writes)

4. **Log Analytics**:
   - Data ingestion (GiB)
   - Data retention

5. **Application Insights**:
   - Telemetry ingestion

6. **Container Registry**:
   - Storage (GiB-month)
   - Basic tier

### Cost Optimization

- **Scale to zero** - Can configure min replicas = 0
- **Right-size resources** - Adjust CPU/memory allocation
- **Log retention** - Reduce retention period
- **Sampling** - Application Insights sampling
- **Image optimization** - Smaller images = faster pulls
- **Private Endpoints** - Minimal cost (~$7.30/month per endpoint)

## Limitations & Considerations

1. **Event Grid**:
   - Max message size: 1 MB
   - Delivery order: Not guaranteed
   - Exactly-once delivery: Not guaranteed (at-least-once)

2. **Blob State Store**:
   - Not optimized for high-frequency updates
   - Eventually consistent
   - Consider Cosmos DB for stronger consistency

3. **Autoscaling**:
   - Scale-down has cooldown period
   - Minimum 1 replica for availability
   - Cold starts when scaling from zero

4. **Container Apps**:
   - Max 30 replicas per app (can be increased)
   - Max 2 vCPU, 4 GiB per container (consumption plan)

## Future Enhancements

1. **Custom Domain** - Custom DNS names
2. **API Management** - API gateway integration
3. **Cosmos DB** - Enhanced state store with stronger consistency
4. **Service Bus** - Alternative to Event Grid
5. **Key Vault** - Application-specific secrets management
6. **GitHub Actions** - CI/CD pipeline
7. **WAF** - Web Application Firewall integration
8. **DDoS Protection** - Standard tier for enhanced protection

---

**Last Updated**: December 22, 2025  
**Version**: 2.0 (Security Enhanced)
