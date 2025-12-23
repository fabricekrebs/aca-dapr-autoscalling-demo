# Azure Resource Naming Convention

This document defines the standardized naming convention for all Azure resources in the DaprDemo project.

## Overview

All Azure resources follow a consistent, hierarchical naming pattern that includes:
- **Resource type prefix** - Identifies the type of Azure resource
- **Location** - Azure region where the resource is deployed
- **Application name** - The project/application name
- **Environment** - Deployment environment (dev, staging, prod) - *Note: Omitted in this demo*
- **Instance number** - Allows multiple instances of the same resource type

## Standard Format

```
{prefix}-{location}-{app}-{instance}
```

For resources with strict naming constraints (no hyphens allowed):
```
{prefix}{locationAbbr}{app}{instance}
```

## Location Abbreviations

For resources with length constraints, we use abbreviated location codes:

| Full Location | Abbreviation |
|---------------|--------------|
| `westeurope` | `we` |
| `northeurope` | `ne` |
| `italynorth` | `in` |
| `eastus` | `eu` |
| `eastus2` | `eu2` |
| `westus` | `wu` |
| `westus2` | `wu2` |

For resources without strict length limits, use the full location name.

## Resource Naming Patterns

### Infrastructure Resources

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Resource Group | `rg` | `rg-{location}-{app}-{instance}` | `rg-italynorth-daprdemo-01` |
| Virtual Network | `vnet` | `vnet-{location}-{app}-{instance}` | `vnet-italynorth-daprdemo-01` |
| Subnet | `snet` | `snet-{location}-{app}-{purpose}-{instance}` | `snet-italynorth-daprdemo-containerapp-01` |

### Compute Resources

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Container Apps Environment | `env` | `env-{location}-{app}-{instance}` | `env-italynorth-daprdemo-01` |
| Container App | `app` | `app-{location}-{app}-{instance}` | `app-italynorth-daprdemo-api-01` |
| App Service Plan | `plan` | `plan-{location}-{app}-{instance}` | `plan-italynorth-daprdemo-01` |
| App Service | `as` | `as-{location}-{app}-{instance}` | `as-italynorth-daprdemo-01` |
| Function App | `func` | `func-{location}-{app}-{instance}` | `func-italynorth-daprdemo-01` |

### Container & Registry

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Container Registry | `acr` | `acr{locationAbbr}{app}{instance}` | `acrindaprdemo01` |
| Container Instance | `ci` | `ci-{location}-{app}-{instance}` | `ci-italynorth-daprdemo-01` |

**Note**: Container Registry names must be globally unique, lowercase alphanumeric only (5-50 chars), no hyphens.

### Data & Storage

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Storage Account | `sa` | `sa{locationAbbr}{app}{instance}` | `saindaprdemo01` |
| Blob Container | N/A | `{purpose}` | `dapr-state`, `uploads`, `processed` |
| File Share | N/A | `{purpose}` | `data`, `backups` |

**Note**: Storage Account names must be globally unique, lowercase alphanumeric only (3-24 chars), no hyphens.

### Database Resources

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| PostgreSQL Server | `psql` | `psql-{location}-{app}-{instance}` | `psql-italynorth-daprdemo-01` |
| MySQL Server | `mysql` | `mysql-{location}-{app}-{instance}` | `mysql-italynorth-daprdemo-01` |
| SQL Server | `sql` | `sql-{location}-{app}-{instance}` | `sql-italynorth-daprdemo-01` |
| Cosmos DB Account | `cosmos` | `cosmos-{location}-{app}-{instance}` | `cosmos-italynorth-daprdemo-01` |

### Messaging & Events

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Event Grid Namespace | `egns` | `egns-{location}-{app}-{instance}` | `egns-italynorth-daprdemo-01` |
| Event Hub Namespace | `evh` | `evh-{location}-{app}-{instance}` | `evh-italynorth-daprdemo-01` |
| Service Bus Namespace | `sb` | `sb-{location}-{app}-{instance}` | `sb-italynorth-daprdemo-01` |
| Redis Cache | `red` | `red-{location}-{app}-{instance}` | `red-italynorth-daprdemo-01` |

### Security & Secrets

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Key Vault | `kv` | `kv{locationAbbr}{app}{instance}` | `kvindaprdemo01` |
| Managed Identity | `id` | `id-{location}-{app}-{instance}` | `id-italynorth-daprdemo-01` |

**Note**: Key Vault names must be globally unique, alphanumeric and hyphens only (3-24 chars). We omit hyphens for brevity.

### Monitoring & Logging

| Resource Type | Prefix | Pattern | Example (italynorth) |
|--------------|--------|---------|----------------------|
| Log Analytics Workspace | `law` | `law-{location}-{app}-{instance}` | `law-italynorth-daprdemo-01` |
| Application Insights | `ai` | `ai-{location}-{app}-{instance}` | `ai-italynorth-daprdemo-01` |
| Action Group | `ag` | `ag-{location}-{app}-{instance}` | `ag-italynorth-daprdemo-01` |

## Complete Example: DaprDemo (italynorth)

```yaml
Resource Group:           rg-italynorth-daprdemo-01
Container Apps Env:       env-italynorth-daprdemo-01
Container App (API):      app-italynorth-daprdemo-api-01
Container App (Worker):   app-italynorth-daprdemo-worker-01
Container Registry:       acrindaprdemo01
Event Grid Namespace:     egns-italynorth-daprdemo-01
Storage Account:          saindaprdemo01
Application Insights:     ai-italynorth-daprdemo-01
Log Analytics Workspace:  law-italynorth-daprdemo-01
```

## Azure Resource Naming Rules & Constraints

| Resource Type | Min Length | Max Length | Valid Characters | Global Unique | Case Sensitive |
|--------------|-----------|------------|------------------|---------------|----------------|
| Resource Group | 1 | 90 | Alphanumeric, underscore, parentheses, hyphen, period | No | No |
| Container Registry | 5 | 50 | Alphanumeric only | Yes | No |
| Container App | 2 | 32 | Lowercase, alphanumeric, hyphen | No | Yes |
| Storage Account | 3 | 24 | Lowercase alphanumeric only | Yes | No |
| Key Vault | 3 | 24 | Alphanumeric, hyphen | Yes | No |
| Event Grid Namespace | 3 | 50 | Alphanumeric, hyphen | No | No |
| App Insights | 1 | 260 | Alphanumeric, hyphen, underscore, parentheses, period | No | No |
| Log Analytics | 4 | 63 | Alphanumeric, hyphen | No | No |

## Tags

All resources should include these standard tags:

```yaml
Application: DaprDemo
Environment: Demo
ManagedBy: Bicep
Project: DaprDemo
```

## Benefits of This Convention

1. ✅ **Consistency** - All resources follow the same pattern
2. ✅ **Clarity** - Resource type, location, and purpose are immediately visible
3. ✅ **Searchability** - Easy to find and filter resources in Azure Portal
4. ✅ **Automation** - Predictable names enable script automation
5. ✅ **Governance** - Supports cost tracking and policy enforcement
6. ✅ **Scalability** - Instance numbers allow for multiple deployments
7. ✅ **Compliance** - Adheres to Azure naming rules and constraints

## Implementation

The naming convention is implemented in:
- **Bicep Templates**: `/infra/main.bicep` and `/infra/modules/*.bicep`
- **Parameter Files**: `/infra/parameters.json`
- **Scripts**: `/scripts/*.sh`

## References

- [Azure Naming Conventions Best Practices](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Azure Resource Naming Rules](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules)
- [Cloud Adoption Framework - Naming Standards](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)

---

**Last Updated**: December 22, 2025  
**Version**: 1.0
