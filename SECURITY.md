# Security Architecture

This document describes the security features and best practices implemented in the Dapr Demo project.

## Overview

The project implements enterprise-grade security using Azure's native security features:

- **Private Networking** - All backend services isolated from the public internet
- **Identity-Based Authentication** - Zero standing credentials using Managed Identity
- **Zero Trust Architecture** - Explicit verification for every access request
- **Defense in Depth** - Multiple layers of security controls

## Security Features

### 1. Network Security

#### Virtual Network Isolation

All resources are deployed within a private Virtual Network:

```
vnet-italynorth-daprdemo-01 (10.0.0.0/16)
├── snet-italynorth-daprdemo-apps-01 (10.0.0.0/23)
│   └── Container Apps Environment
│       ├── API Container App
│       └── Worker Container App
└── snet-italynorth-daprdemo-pe-01 (10.0.2.0/24)
    ├── Storage Private Endpoint (10.0.2.4)
    ├── Event Grid Private Endpoint (10.0.2.5)
    └── Container Registry Private Endpoint (10.0.2.6)
```

**Benefits:**
- Traffic stays within Azure backbone
- No exposure to public internet
- Network-level isolation
- Controlled egress/ingress

#### Private Endpoints

All Azure services are configured with Private Endpoints:

| Service | Resource | Private Endpoint | Public Access |
|---------|----------|------------------|---------------|
| Blob Storage | `saindaprdemo01` | ✅ Enabled | ❌ Disabled |
| Event Grid | `egns-italynorth-daprdemo-01` | ✅ Enabled | ❌ Disabled |
| Container Registry | `acrindaprdemo01` | ✅ Enabled | ❌ Disabled |

**Configuration:**
```bicep
// Storage Account
publicNetworkAccess: 'Disabled'
networkAcls: {
  defaultAction: 'Deny'
}

// Event Grid
publicNetworkAccess: 'Disabled'

// Container Registry
publicNetworkAccess: 'Disabled'
adminUserEnabled: false
```

**Benefits:**
- Services not accessible from internet
- Data never leaves Azure network
- Reduced attack surface
- Compliance with data residency requirements

#### Private DNS Resolution

Three Private DNS Zones ensure proper name resolution:

1. **privatelink.blob.core.windows.net**
   - Resolves `saindaprdemo01.blob.core.windows.net` → `10.0.2.4`

2. **privatelink.azurecr.io**
   - Resolves `acrindaprdemo01.azurecr.io` → `10.0.2.5`

3. **privatelink.eventgrid.azure.net**
   - Resolves `egns-italynorth-daprdemo-01.*.eventgrid.azure.net` → `10.0.2.6`

**How it works:**
- Container Apps query Azure DNS
- Azure DNS checks Private DNS zones first
- Returns private IP if found
- Traffic routes through VNET, not internet

### 2. Identity and Access Management

#### Managed Identity

A User-Assigned Managed Identity eliminates the need for credentials:

**Resource:** `id-italynorth-daprdemo-01`

**Identity Assignment:**
```bicep
// Container Apps get the managed identity
identity: {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '${managedIdentity.id}': {}
  }
}
```

**Benefits:**
- No passwords, keys, or certificates to manage
- Automatic rotation of credentials
- Azure AD manages authentication
- Audit trail in Azure Activity Log

#### RBAC Role Assignments

The Managed Identity is granted only the permissions it needs:

| Role | Scope | Purpose | Granted To |
|------|-------|---------|------------|
| Storage Blob Data Contributor | Storage Account | Read/write state to blob container | Dapr sidecars |
| EventGrid Data Sender | Event Grid Namespace | Publish events to topics | API Dapr sidecar |
| AcrPull | Container Registry | Pull container images | Container Apps |

**Least Privilege Principle:**
- API can publish events but not manage Event Grid
- Worker can read/write state but not delete storage account
- Neither service can modify infrastructure

**Role Assignment:**
```bicep
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(managedIdentity.id, storageAccount.id, 'Storage Blob Data Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
```

#### Dapr Component Security

Dapr components authenticate using Managed Identity:

**Event Grid Pub/Sub:**
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
    value: https://egns-italynorth-daprdemo-01...
  - name: azureClientId
    value: <managed-identity-client-id>  # No access key!
  - name: topicEndpoint
    value: https://egns-italynorth-daprdemo-01.../orders
```

**Blob Storage State Store:**
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
    value: <managed-identity-client-id>  # No account key!
  - name: containerName
    value: dapr-state
```

**Key Differences:**
- ❌ Before: `accessKey` or `accountKey` in metadata
- ✅ After: `azureClientId` pointing to Managed Identity

### 3. Data Protection

#### Encryption at Rest

All data is encrypted when stored:

- **Blob Storage**: Microsoft-managed keys (AES-256)
- **Event Grid**: Encrypted by default
- **Container Registry**: Image layers encrypted

#### Encryption in Transit

All communication uses TLS/HTTPS:

- **API Ingress**: HTTPS only (HTTP redirects to HTTPS)
- **Dapr to Azure Services**: HTTPS (enforced by Private Endpoints)
- **Inter-service mTLS**: Dapr enables mutual TLS between sidecars

#### Secrets Management

**No secrets required!** The architecture eliminates secret management:

| Before (Keys) | After (Managed Identity) |
|---------------|--------------------------|
| Storage account keys in secrets | Managed Identity with RBAC |
| Event Grid access keys in secrets | Managed Identity with RBAC |
| ACR admin credentials in secrets | Managed Identity with AcrPull |

**Benefits:**
- No credential rotation required
- No risk of key leakage
- No secrets in code or configuration
- Simplified operations

### 4. Container Security

#### Container Registry

**Security Configuration:**
```bicep
properties: {
  adminUserEnabled: false          // No admin credentials
  publicNetworkAccess: 'Disabled'  // Private endpoint only
  networkRuleBypassOptions: 'None' // Strict enforcement
}
```

#### Container Images

**Multi-stage Builds:**
```dockerfile
# Build stage - includes dev tools
FROM python:3.11-slim AS builder
# ... build steps ...

# Production stage - minimal attack surface
FROM python:3.11-slim
COPY --from=builder /app /app
USER appuser  # Non-root user
```

**Security Benefits:**
- Smaller image size (fewer vulnerabilities)
- No build tools in production image
- Non-root user execution
- Reduced attack surface

### 5. Application Security

#### Health Checks

All container apps implement health endpoints:

```python
@app.route('/health')
def health():
    """Liveness probe - is the app running?"""
    return jsonify({"status": "healthy"}), 200

@app.route('/ready')
def ready():
    """Readiness probe - is the app ready for traffic?"""
    return jsonify({"status": "ready"}), 200
```

**Configured in Bicep:**
```bicep
probes: [
  {
    type: 'Liveness'
    httpGet: {
      path: '/health'
      port: appPort
    }
    initialDelaySeconds: 10
    periodSeconds: 30
  }
]
```

#### Input Validation

API validates all inputs:

```python
if not order_data or not isinstance(order_data, dict):
    return jsonify({"error": "Invalid request body"}), 400

required_fields = ['order_id', 'customer_name', 'items']
if not all(field in order_data for field in required_fields):
    return jsonify({"error": "Missing required fields"}), 400
```

## Security Monitoring

### Azure Activity Log

All Managed Identity operations are logged:
- Role assignments
- Permission grants
- Access attempts
- Authentication failures

### Application Insights

Security-relevant events tracked:
- Failed authentication attempts
- Unauthorized access attempts
- Exception and error rates
- Dependency failures

### Container Apps Logs

All application logs centralized:
- Dapr sidecar logs
- Application logs
- System logs
- Audit events

## Compliance Considerations

### Data Residency

- All resources deployed in Italy North region
- Data never leaves Azure network
- No internet egress for backend services

### Audit Requirements

- Azure Activity Log provides audit trail
- RBAC changes logged and timestamped
- Private Endpoint access logged
- Container Apps logs retained

### Zero Trust Principles

✅ **Verify explicitly**: Managed Identity authenticates every request
✅ **Least privilege access**: RBAC grants minimal required permissions
✅ **Assume breach**: Private Endpoints prevent lateral movement

## Security Best Practices

### Deployment

1. **Review Role Assignments**
   ```bash
   az role assignment list \
       --assignee <managed-identity-principal-id> \
       --all
   ```

2. **Verify Public Access Disabled**
   ```bash
   az storage account show --name saindaprdemo01 \
       --query publicNetworkAccess
   # Should return: Disabled
   ```

3. **Check Private Endpoints**
   ```bash
   az network private-endpoint list \
       --resource-group rg-italynorth-daprdemo-01
   ```

### Operations

1. **Regular Security Reviews**
   - Review RBAC assignments quarterly
   - Audit Private Endpoint connections
   - Check for unused resources

2. **Monitor Security Alerts**
   - Set up Azure Defender for Cloud
   - Configure Security Center recommendations
   - Review security advisories

3. **Update Management**
   - Keep base images updated
   - Scan images for vulnerabilities
   - Apply security patches promptly

### Incident Response

1. **Identify Anomalies**
   - Monitor Activity Log for unusual access patterns
   - Review Managed Identity usage patterns
   - Check for failed authentication attempts

2. **Investigate Issues**
   - Review Container Apps logs
   - Check Application Insights traces
   - Analyze network traffic patterns

3. **Respond to Incidents**
   - Revoke compromised identities
   - Update RBAC assignments
   - Rotate affected credentials (if any remain)

## Future Security Enhancements

1. **Azure Key Vault** - For application-specific secrets
2. **Azure Firewall** - Centralized egress traffic control
3. **DDoS Protection** - Standard tier for enhanced protection
4. **WAF Integration** - Web Application Firewall for API
5. **Azure Defender** - Advanced threat protection
6. **Customer-Managed Keys** - For encryption at rest
7. **Network Security Groups** - Additional subnet-level controls
8. **Azure Policy** - Enforce security compliance

## References

- [Azure Private Link Documentation](https://docs.microsoft.com/en-us/azure/private-link/)
- [Managed Identities Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [Azure RBAC Documentation](https://docs.microsoft.com/en-us/azure/role-based-access-control/)
- [Container Apps Networking](https://docs.microsoft.com/en-us/azure/container-apps/networking)
- [Dapr Security](https://docs.dapr.io/operations/security/)
- [Azure Security Baseline for Container Apps](https://docs.microsoft.com/en-us/security/benchmark/azure/baselines/container-apps-security-baseline)

---

**Last Updated**: December 22, 2025  
**Version**: 1.0
