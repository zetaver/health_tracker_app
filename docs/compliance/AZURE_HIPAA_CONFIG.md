# Azure HIPAA Configuration Guide

## Overview

This guide provides detailed configuration steps for deploying a HIPAA-compliant iOS health tracker backend on Microsoft Azure. Azure offers a comprehensive set of services covered under their Business Associate Agreement (BAA) for HIPAA compliance.

**Document Version:** 1.0
**Last Updated:** October 21, 2025
**Azure Compliance Programs:** HIPAA/HITECH, HITRUST CSF, ISO 27001, SOC 2

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Business Associate Agreement](#business-associate-agreement)
3. [Architecture Overview](#architecture-overview)
4. [Azure Services Configuration](#azure-services-configuration)
5. [Security Configuration](#security-configuration)
6. [Monitoring & Compliance](#monitoring--compliance)
7. [Deployment Checklist](#deployment-checklist)

---

## Prerequisites

### Required Azure Resources

- Azure subscription (Enterprise Agreement or Microsoft Customer Agreement recommended)
- Azure Active Directory tenant
- Appropriate Azure role assignments (Contributor, Security Admin)
- Azure CLI or PowerShell installed
- Terraform or ARM templates (for infrastructure as code)

### Compliance Requirements

- Sign Business Associate Agreement (BAA) with Microsoft
- Complete HIPAA Security Risk Assessment
- Designate Privacy and Security Officers
- Document policies and procedures
- Train workforce on HIPAA requirements

---

## Business Associate Agreement

### Obtaining the BAA

1. **Azure Portal:**
   - Navigate to Trust Center > Compliance > HIPAA/HITECH
   - Request BAA through Azure Support (Enterprise customers)

2. **Microsoft Trust Center:**
   - Visit: https://aka.ms/azurecompliance
   - Download HIPAA/HITECH compliance resources

3. **Volume Licensing:**
   - BAA available through Microsoft Volume Licensing Service Center
   - Required for Enterprise Agreement customers

### BAA Covered Services

**HIPAA-Eligible Azure Services (Partial List):**

| Service Category | Azure Services |
|-----------------|----------------|
| Compute | Virtual Machines, App Service, Azure Functions, Container Instances, AKS |
| Storage | Blob Storage, File Storage, Disk Storage, Data Lake Storage |
| Database | SQL Database, Cosmos DB, Database for PostgreSQL, Database for MySQL |
| Networking | Virtual Network, Load Balancer, Application Gateway, VPN Gateway, ExpressRoute |
| Security | Key Vault, Azure AD, Security Center, Sentinel |
| Monitoring | Monitor, Log Analytics, Application Insights |
| AI/ML | Cognitive Services (select services), Machine Learning |

**Not HIPAA-Eligible:**
- Azure DevTest Labs (with PHI)
- Some preview/beta services
- Multi-tenant services without encryption

**Important:** Always verify current HIPAA eligibility at https://aka.ms/AzureCompliance

---

## Architecture Overview

### Recommended Architecture for iOS Health App Backend

```
┌─────────────────────────────────────────────────────────────────┐
│                          iOS App                                 │
│  ┌──────────────┐    ┌────────────────┐    ┌─────────────┐     │
│  │  HealthKit   │───▶│  App Logic     │───▶│  Network    │     │
│  │  Integration │    │  (Swift)       │    │  Layer      │     │
│  └──────────────┘    └────────────────┘    └──────┬──────┘     │
└─────────────────────────────────────────────────────┼───────────┘
                                                       │
                                      HTTPS/TLS 1.3   │
                                                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Azure Cloud (HIPAA)                         │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Azure Front Door / Application Gateway         │ │
│  │  (WAF, DDoS Protection, TLS Termination, Certificate)      │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
│                                  │                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                  Azure API Management                       │ │
│  │  (Authentication, Rate Limiting, API Gateway)              │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
│                                  │                                │
│  ┌──────────────────────────────┴─────────────────────────────┐ │
│  │                      Virtual Network (VNet)                 │ │
│  │                                                              │ │
│  │  ┌─────────────────┐         ┌──────────────────┐          │ │
│  │  │  App Service    │         │  Azure Functions │          │ │
│  │  │  (REST API)     │◀───────▶│  (Background     │          │ │
│  │  │  + Managed      │         │   Processing)    │          │ │
│  │  │  Identity       │         └──────────────────┘          │ │
│  │  └────────┬────────┘                   │                   │ │
│  │           │                             │                   │ │
│  │           │         ┌───────────────────┘                   │ │
│  │           │         │                                       │ │
│  │  ┌────────┴─────────┴─────┐   ┌──────────────────┐         │ │
│  │  │   Azure SQL Database   │   │  Azure Cosmos DB │         │ │
│  │  │   (PHI Storage)        │   │  (Metadata)      │         │ │
│  │  │   + TDE + Encryption   │   │  + Encryption    │         │ │
│  │  └────────────────────────┘   └──────────────────┘         │ │
│  │                                                              │ │
│  │  ┌────────────────────────┐   ┌──────────────────┐         │ │
│  │  │  Azure Blob Storage    │   │  Azure Key Vault │         │ │
│  │  │  (Encrypted Files,     │◀──│  (Keys, Secrets, │         │ │
│  │  │   Backups)             │   │   Certificates)  │         │ │
│  │  └────────────────────────┘   └──────────────────┘         │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Security & Monitoring Layer                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │Azure Sentinel│  │Log Analytics │  │Microsoft        │  │ │
│  │  │(SIEM)        │  │(Audit Logs)  │  │Defender for     │  │ │
│  │  │              │  │              │  │Cloud            │  │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Azure Services Configuration

### 1. Azure Active Directory (AAD)

**Purpose:** Identity and access management, OAuth 2.0/OpenID Connect authentication

#### Configuration Steps:

```bash
# Create Azure AD tenant (if not exists)
az ad tenant create --display-name "HealthTrackerApp"

# Register application
az ad app create \
  --display-name "HealthTrackerAPI" \
  --sign-in-audience "AzureADMyOrg" \
  --enable-id-token-issuance true \
  --enable-access-token-issuance true
```

#### Required Settings:

**App Registration:**
- **Application Type:** Web API
- **Redirect URIs:** `healthtracker://oauth/callback` (custom URL scheme)
- **Supported Account Types:** Single tenant
- **API Permissions:**
  - Microsoft Graph: `User.Read` (delegated)
  - Custom scopes: `read:health_data`, `write:health_data`

**Token Configuration:**
- **Token version:** v2.0
- **Access token lifetime:** 60 minutes (maximum)
- **Refresh token lifetime:** 14 days
- **Require proof of key exchange (PKCE):** Yes

**Authentication:**
```json
{
  "accessTokenAcceptedVersion": 2,
  "signInAudience": "AzureADMyOrg",
  "oauth2AllowIdTokenImplicitFlow": false,
  "oauth2AllowImplicitFlow": false,
  "oauth2Permissions": [
    {
      "id": "unique-guid",
      "type": "User",
      "adminConsentDescription": "Allow the app to read health data",
      "adminConsentDisplayName": "Read health data",
      "userConsentDescription": "Allow the app to read your health data",
      "userConsentDisplayName": "Read health data",
      "value": "read:health_data"
    }
  ]
}
```

**Conditional Access Policies:**
- Require multi-factor authentication
- Block legacy authentication
- Require compliant devices
- Require managed devices (optional)
- Session controls: Sign-in frequency 12 hours

**Azure AD B2C (Alternative for Consumer Apps):**
- Custom branding
- Social identity providers (Google, Apple)
- Custom user flows
- Identity protection

---

### 2. Azure App Service

**Purpose:** Host RESTful API backend

#### Configuration:

```bash
# Create App Service Plan
az appservice plan create \
  --name "healthtracker-plan" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --is-linux \
  --sku "P1V3" \
  --number-of-workers 2

# Create App Service
az webapp create \
  --name "healthtracker-api" \
  --plan "healthtracker-plan" \
  --resource-group "healthtracker-rg" \
  --runtime "NODE:18-lts"

# Enable managed identity
az webapp identity assign \
  --name "healthtracker-api" \
  --resource-group "healthtracker-rg"
```

#### Required Settings:

**HIPAA Requirements:**
- **Tier:** Premium (P1V3 or higher) - Includes VNet integration
- **Always On:** Enabled
- **HTTPS Only:** Enabled
- **TLS Version:** 1.2 minimum (1.3 recommended)
- **Client Certificates:** Required (for mutual TLS)

**Application Settings:**
```json
{
  "WEBSITE_HTTPLOGGING_RETENTION_DAYS": "90",
  "WEBSITES_ENABLE_APP_SERVICE_STORAGE": "false",
  "WEBSITE_LOAD_CERTIFICATES": "*",
  "AZURE_KEY_VAULT_ENDPOINT": "https://<keyvault>.vault.azure.net/",
  "DATABASE_CONNECTION_STRING": "@Microsoft.KeyVault(SecretUri=https://<keyvault>.vault.azure.net/secrets/db-connection/)",
  "JWT_SECRET": "@Microsoft.KeyVault(SecretUri=https://<keyvault>.vault.azure.net/secrets/jwt-secret/)",
  "ENVIRONMENT": "production"
}
```

**Network Configuration:**
- **VNet Integration:** Enabled (dedicated subnet)
- **Private Endpoints:** Enabled for inbound traffic
- **Outbound:** Service endpoints or private endpoints to databases
- **IP Restrictions:** Whitelist only (API Management IP, admin IPs)

**Deployment Slots:**
- Use staging slots for testing
- Swap with production after validation
- Enable auto-swap: No (manual validation required)

**Logging & Monitoring:**
```bash
# Enable diagnostic logging
az webapp log config \
  --name "healthtracker-api" \
  --resource-group "healthtracker-rg" \
  --web-server-logging "filesystem" \
  --detailed-error-messages true \
  --failed-request-tracing true \
  --application-logging "azureblobstorage"
```

---

### 3. Azure SQL Database

**Purpose:** Store structured PHI (user health records, metadata)

#### Configuration:

```bash
# Create SQL Server
az sql server create \
  --name "healthtracker-sql" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --admin-user "sqladmin" \
  --admin-password "<strong-password>" \
  --enable-public-network false

# Create SQL Database
az sql db create \
  --name "healthtracker-db" \
  --server "healthtracker-sql" \
  --resource-group "healthtracker-rg" \
  --service-objective "S3" \
  --zone-redundant false \
  --backup-storage-redundancy "GeoZone"

# Enable Transparent Data Encryption (TDE)
az sql db tde set \
  --database "healthtracker-db" \
  --server "healthtracker-sql" \
  --resource-group "healthtracker-rg" \
  --status "Enabled"
```

#### HIPAA Security Requirements:

**Encryption:**
- **Transparent Data Encryption (TDE):** Enabled (AES-256)
- **Customer-Managed Keys:** Recommended (via Azure Key Vault)
- **Always Encrypted:** For column-level encryption (highly sensitive PHI)
- **In-Transit:** TLS 1.2+ enforced

**Network Security:**
```bash
# Disable public access
az sql server update \
  --name "healthtracker-sql" \
  --resource-group "healthtracker-rg" \
  --enable-public-network false

# Create private endpoint
az network private-endpoint create \
  --name "sql-private-endpoint" \
  --resource-group "healthtracker-rg" \
  --vnet-name "healthtracker-vnet" \
  --subnet "database-subnet" \
  --private-connection-resource-id "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.Sql/servers/healthtracker-sql" \
  --group-id "sqlServer" \
  --connection-name "sql-private-connection"
```

**Access Control:**
- **Azure AD Authentication:** Enabled and preferred
- **SQL Authentication:** Disabled (or strong passwords only)
- **Managed Identity:** Use for App Service connections
- **Firewall Rules:** No public access, VNet rules only

**Auditing:**
```bash
# Enable server-level auditing
az sql server audit-policy update \
  --name "healthtracker-sql" \
  --resource-group "healthtracker-rg" \
  --state "Enabled" \
  --blob-storage-target-state "Enabled" \
  --storage-account "healthtrackerlogs" \
  --storage-endpoint "https://healthtrackerlogs.blob.core.windows.net" \
  --retention-days 90

# Enable Advanced Threat Protection
az sql server threat-policy update \
  --name "healthtracker-sql" \
  --resource-group "healthtracker-rg" \
  --state "Enabled" \
  --storage-account "healthtrackerlogs"
```

**Backup & Recovery:**
- **Automated Backups:** Enabled (default)
- **Backup Retention:** 35 days minimum (HIPAA: 6 years for audit logs)
- **Geo-Redundant Backup:** Enabled
- **Long-Term Retention (LTR):** Configure for 6+ years
- **Point-in-Time Restore:** Available

**Advanced Data Security:**
```bash
# Enable Defender for SQL
az sql db advanced-threat-protection-setting update \
  --resource-group "healthtracker-rg" \
  --server "healthtracker-sql" \
  --name "healthtracker-db" \
  --state "Enabled"

# Enable vulnerability assessment
az sql db threat-policy update \
  --resource-group "healthtracker-rg" \
  --server "healthtracker-sql" \
  --name "healthtracker-db" \
  --state "Enabled"
```

**Dynamic Data Masking (Optional):**
- Mask PHI for non-privileged users
- Configure masking rules for sensitive columns

---

### 4. Azure Cosmos DB

**Purpose:** High-performance NoSQL database for real-time data, metadata, session storage

#### Configuration:

```bash
# Create Cosmos DB account
az cosmosdb create \
  --name "healthtracker-cosmos" \
  --resource-group "healthtracker-rg" \
  --locations regionName="East US 2" failoverPriority=0 isZoneRedundant=True \
  --default-consistency-level "Session" \
  --enable-automatic-failover true \
  --enable-public-network false

# Create database
az cosmosdb sql database create \
  --account-name "healthtracker-cosmos" \
  --resource-group "healthtracker-rg" \
  --name "healthdata"

# Create container
az cosmosdb sql container create \
  --account-name "healthtracker-cosmos" \
  --database-name "healthdata" \
  --resource-group "healthtracker-rg" \
  --name "healthrecords" \
  --partition-key-path "/userId" \
  --throughput 400
```

#### HIPAA Requirements:

**Encryption:**
- **At Rest:** Enabled by default (AES-256)
- **In Transit:** TLS 1.2+ enforced
- **Customer-Managed Keys:** Configure via Azure Key Vault

**Network Security:**
- **Public Access:** Disabled
- **Private Endpoints:** Enabled
- **Firewall:** IP allowlist (empty = deny all)
- **VNet Integration:** Service endpoints or private endpoints

**Access Control:**
- **Azure AD RBAC:** Enabled
- **Managed Identity:** Use for application access
- **Connection Strings:** Store in Key Vault
- **Resource Tokens:** For fine-grained access control

**Auditing:**
```bash
# Enable diagnostic logs
az monitor diagnostic-settings create \
  --name "cosmos-diagnostics" \
  --resource "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.DocumentDB/databaseAccounts/healthtracker-cosmos" \
  --logs '[{"category":"DataPlaneRequests","enabled":true},{"category":"ControlPlaneRequests","enabled":true}]' \
  --workspace "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.OperationalInsights/workspaces/healthtracker-logs"
```

---

### 5. Azure Blob Storage

**Purpose:** Store encrypted files, backups, audit logs

#### Configuration:

```bash
# Create storage account
az storage account create \
  --name "healthtrackerstorage" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --sku "Standard_GRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --https-only true

# Enable infrastructure encryption (double encryption)
az storage account update \
  --name "healthtrackerstorage" \
  --resource-group "healthtracker-rg" \
  --encryption-key-source "Microsoft.Storage" \
  --require-infrastructure-encryption true
```

#### HIPAA Requirements:

**Encryption:**
- **Server-Side Encryption (SSE):** Enabled (default, AES-256)
- **Infrastructure Encryption:** Enabled (double encryption)
- **Customer-Managed Keys (CMEK):** Recommended via Key Vault
- **Client-Side Encryption:** Optional additional layer
- **Encryption Scopes:** For different data classifications

**Network Security:**
```bash
# Disable public blob access
az storage account update \
  --name "healthtrackerstorage" \
  --resource-group "healthtracker-rg" \
  --allow-blob-public-access false \
  --public-network-access "Disabled"

# Create private endpoint
az network private-endpoint create \
  --name "storage-private-endpoint" \
  --resource-group "healthtracker-rg" \
  --vnet-name "healthtracker-vnet" \
  --subnet "storage-subnet" \
  --private-connection-resource-id "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.Storage/storageAccounts/healthtrackerstorage" \
  --group-id "blob" \
  --connection-name "storage-private-connection"
```

**Access Control:**
- **Shared Access Signatures (SAS):** Use with short expiration (1-24 hours)
- **Stored Access Policies:** Define and revoke access easily
- **Azure AD Authentication:** Preferred over access keys
- **Managed Identity:** Use for service-to-service access
- **Immutable Storage:** For WORM compliance (audit logs)

**Blob Features:**
- **Soft Delete:** 90 days retention
- **Versioning:** Enabled
- **Change Feed:** For audit purposes
- **Lifecycle Management:** Auto-archive/delete old data

**Logging:**
```bash
# Enable storage analytics logging
az storage logging update \
  --account-name "healthtrackerstorage" \
  --services "b" \
  --log "rwd" \
  --retention 90
```

---

### 6. Azure Key Vault

**Purpose:** Secure storage for encryption keys, secrets, certificates

#### Configuration:

```bash
# Create Key Vault
az keyvault create \
  --name "healthtracker-kv" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --enable-purge-protection true \
  --retention-days 90 \
  --public-network-access "Disabled"

# Create private endpoint
az network private-endpoint create \
  --name "kv-private-endpoint" \
  --resource-group "healthtracker-rg" \
  --vnet-name "healthtracker-vnet" \
  --subnet "keyvault-subnet" \
  --private-connection-resource-id "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.KeyVault/vaults/healthtracker-kv" \
  --group-id "vault" \
  --connection-name "kv-private-connection"
```

#### HIPAA Requirements:

**Access Control:**
- **RBAC:** Azure RBAC for Key Vault (preferred over access policies)
- **Managed Identity:** Grant App Service/Functions access
- **Network Rules:** Private endpoints only
- **Firewall:** Deny all public access

**Secrets Management:**
```bash
# Store database connection string
az keyvault secret set \
  --vault-name "healthtracker-kv" \
  --name "db-connection-string" \
  --value "Server=tcp:healthtracker-sql.database.windows.net,1433;Database=healthtracker-db;Authentication=Active Directory Managed Identity;"

# Store JWT signing key
az keyvault secret set \
  --vault-name "healthtracker-kv" \
  --name "jwt-signing-key" \
  --value "<strong-random-key>"
```

**Key Management:**
```bash
# Create encryption key for SQL TDE
az keyvault key create \
  --vault-name "healthtracker-kv" \
  --name "sql-tde-key" \
  --protection "hsm" \
  --size 2048 \
  --kty "RSA"

# Create key for Storage encryption
az keyvault key create \
  --vault-name "healthtracker-kv" \
  --name "storage-encryption-key" \
  --protection "hsm" \
  --size 2048 \
  --kty "RSA"
```

**Certificate Management:**
```bash
# Import TLS certificate
az keyvault certificate import \
  --vault-name "healthtracker-kv" \
  --name "api-tls-cert" \
  --file "api-cert.pfx" \
  --password "<cert-password>"
```

**Auditing:**
```bash
# Enable diagnostic logging
az monitor diagnostic-settings create \
  --name "keyvault-diagnostics" \
  --resource "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.KeyVault/vaults/healthtracker-kv" \
  --logs '[{"category":"AuditEvent","enabled":true}]' \
  --workspace "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.OperationalInsights/workspaces/healthtracker-logs"
```

**Best Practices:**
- **Soft Delete:** Enabled (90 days)
- **Purge Protection:** Enabled (prevent accidental key deletion)
- **Key Rotation:** Automated rotation (90 days)
- **Backup:** Regular backups of critical keys/secrets
- **Least Privilege:** Grant minimum necessary permissions

---

### 7. Azure API Management

**Purpose:** API gateway, rate limiting, authentication, monitoring

#### Configuration:

```bash
# Create API Management instance
az apim create \
  --name "healthtracker-apim" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --publisher-email "admin@healthtracker.com" \
  --publisher-name "Health Tracker" \
  --sku-name "Developer" \
  --virtual-network "External"
```

#### HIPAA Requirements:

**API Policies:**

```xml
<policies>
    <inbound>
        <!-- Validate JWT token -->
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
            <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
            <required-claims>
                <claim name="aud">
                    <value>api://healthtracker</value>
                </claim>
            </required-claims>
        </validate-jwt>

        <!-- Rate limiting -->
        <rate-limit-by-key calls="100" renewal-period="60" counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject)" />

        <!-- HTTPS only -->
        <choose>
            <when condition="@(context.Request.Url.Scheme != "https")">
                <return-response>
                    <set-status code="403" reason="HTTPS Required" />
                </return-response>
            </when>
        </choose>

        <!-- Set backend URL -->
        <set-backend-service base-url="https://healthtracker-api.azurewebsites.net" />

        <!-- Remove sensitive headers -->
        <set-header name="X-Forwarded-For" exists-action="delete" />
        <set-header name="X-Forwarded-Host" exists-action="delete" />
    </inbound>

    <backend>
        <forward-request timeout="300" />
    </backend>

    <outbound>
        <!-- Security headers -->
        <set-header name="X-Content-Type-Options" exists-action="override">
            <value>nosniff</value>
        </set-header>
        <set-header name="X-Frame-Options" exists-action="override">
            <value>DENY</value>
        </set-header>
        <set-header name="Strict-Transport-Security" exists-action="override">
            <value>max-age=31536000; includeSubDomains</value>
        </set-header>

        <!-- Remove backend server headers -->
        <set-header name="Server" exists-action="delete" />
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="X-AspNet-Version" exists-action="delete" />
    </outbound>

    <on-error>
        <!-- Log errors but don't expose sensitive info -->
        <set-body>@{
            return new JObject(
                new JProperty("error", "An error occurred"),
                new JProperty("requestId", context.RequestId)
            ).ToString();
        }</set-body>
    </on-error>
</policies>
```

**Monitoring:**
- Enable Application Insights integration
- Log all API requests (sanitize PHI)
- Alert on anomalies and errors

---

### 8. Azure Monitor & Log Analytics

**Purpose:** Centralized logging, monitoring, and alerting

#### Configuration:

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
  --workspace-name "healthtracker-logs" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --retention-time 90

# Enable diagnostic settings for resources (example for App Service)
az monitor diagnostic-settings create \
  --name "appservice-diagnostics" \
  --resource "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.Web/sites/healthtracker-api" \
  --workspace "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg/providers/Microsoft.OperationalInsights/workspaces/healthtracker-logs" \
  --logs '[{"category":"AppServiceHTTPLogs","enabled":true},{"category":"AppServiceConsoleLogs","enabled":true},{"category":"AppServiceAppLogs","enabled":true},{"category":"AppServiceAuditLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

#### HIPAA Audit Logging:

**Required Logs:**
- Authentication events (Azure AD)
- API requests (API Management)
- Database queries (SQL/Cosmos DB)
- Storage access (Blob Storage)
- Key/secret access (Key Vault)
- Configuration changes (Activity Log)
- Security alerts (Security Center, Sentinel)

**Log Retention:**
- Operational logs: 90 days in Log Analytics
- Audit logs: 6+ years in immutable storage
- Archive to long-term storage (Azure Storage Archive tier)

**Kusto Queries for HIPAA Compliance:**

```kql
// PHI Access Audit
AzureDiagnostics
| where Category == "DataPlaneRequests"
| where ResourceProvider == "MICROSOFT.DOCUMENTDB"
| project TimeGenerated, identity_claim_oid_g, OperationName, Resource, requestResourceType_s, statusCode_s
| order by TimeGenerated desc

// Failed Authentication Attempts
SigninLogs
| where ResultType != 0
| summarize FailedAttempts=count() by UserPrincipalName, IPAddress, bin(TimeGenerated, 15m)
| where FailedAttempts >= 5

// Key Vault Access
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet" or OperationName == "KeyGet"
| project TimeGenerated, CallerIPAddress, identity_claim_http_schemas_microsoft_com_identity_claims_objectidentifier_g, OperationName, SecretName=id_s, ResultType
```

---

## Security Configuration

### 1. Virtual Network (VNet)

```bash
# Create VNet
az network vnet create \
  --name "healthtracker-vnet" \
  --resource-group "healthtracker-rg" \
  --location "eastus2" \
  --address-prefix "10.0.0.0/16"

# Create subnets
az network vnet subnet create \
  --name "app-subnet" \
  --vnet-name "healthtracker-vnet" \
  --resource-group "healthtracker-rg" \
  --address-prefix "10.0.1.0/24"

az network vnet subnet create \
  --name "database-subnet" \
  --vnet-name "healthtracker-vnet" \
  --resource-group "healthtracker-rg" \
  --address-prefix "10.0.2.0/24"

az network vnet subnet create \
  --name "storage-subnet" \
  --vnet-name "healthtracker-vnet" \
  --resource-group "healthtracker-rg" \
  --address-prefix "10.0.3.0/24"

# Create Network Security Group
az network nsg create \
  --name "app-nsg" \
  --resource-group "healthtracker-rg"

# Allow HTTPS only
az network nsg rule create \
  --name "AllowHTTPS" \
  --nsg-name "app-nsg" \
  --resource-group "healthtracker-rg" \
  --priority 100 \
  --direction "Inbound" \
  --access "Allow" \
  --protocol "Tcp" \
  --destination-port-ranges 443

# Deny all other inbound
az network nsg rule create \
  --name "DenyAll" \
  --nsg-name "app-nsg" \
  --resource-group "healthtracker-rg" \
  --priority 4096 \
  --direction "Inbound" \
  --access "Deny" \
  --protocol "*" \
  --destination-port-ranges "*"
```

### 2. Microsoft Defender for Cloud

```bash
# Enable Defender for Cloud (formerly Security Center)
az security pricing create \
  --name "VirtualMachines" \
  --tier "Standard"

az security pricing create \
  --name "SqlServers" \
  --tier "Standard"

az security pricing create \
  --name "AppServices" \
  --tier "Standard"

az security pricing create \
  --name "StorageAccounts" \
  --tier "Standard"

az security pricing create \
  --name "KeyVaults" \
  --tier "Standard"
```

**Security Recommendations:**
- Continuously monitor security posture
- Remediate high-severity recommendations
- Enable Just-In-Time VM access
- Enable adaptive application controls
- Regular vulnerability assessments

### 3. Azure Sentinel (SIEM)

```bash
# Enable Sentinel on Log Analytics workspace
az sentinel workspace create \
  --resource-group "healthtracker-rg" \
  --workspace-name "healthtracker-logs"
```

**HIPAA Use Cases:**
- Threat detection (anomalous access patterns)
- Automated incident response
- Compliance reporting
- Security orchestration, automation, and response (SOAR)

**Data Connectors:**
- Azure AD
- Azure Activity
- Microsoft Defender for Cloud
- Office 365 (if applicable)

### 4. Azure Policy

```bash
# Assign HIPAA/HITRUST initiative
az policy assignment create \
  --name "HIPAA-HITRUST" \
  --scope "/subscriptions/<sub-id>/resourceGroups/healthtracker-rg" \
  --policy-set-definition "/providers/Microsoft.Authorization/policySetDefinitions/a169a624-5599-4385-a696-c8d643089fab"
```

**Key Policies:**
- Enforce TLS 1.2 minimum
- Require encryption at rest
- Deny public network access
- Require managed identity
- Audit diagnostic logs

---

## Monitoring & Compliance

### Compliance Tools

**Azure Compliance Manager:**
- HIPAA/HITECH assessment
- Track compliance score
- Recommended actions
- Evidence collection

**Azure Blueprints:**
- Deploy HIPAA-compliant architecture
- Pre-configured policies and resources
- Repeatable deployments

**Azure Service Trust Portal:**
- Audit reports (SOC, ISO, HITRUST)
- Compliance documentation
- Data protection resources

### Regular Audits

**Monthly:**
- Review access logs
- Check failed authentication attempts
- Validate encryption status
- Review security alerts

**Quarterly:**
- Access certification (user access reviews)
- Vulnerability assessment
- Penetration testing
- Policy compliance review

**Annually:**
- Full security risk assessment
- BAA renewal verification
- Disaster recovery testing
- Compliance gap analysis

---

## Deployment Checklist

### Pre-Deployment

- [ ] Sign Business Associate Agreement with Microsoft
- [ ] Complete HIPAA Security Risk Assessment
- [ ] Document security policies and procedures
- [ ] Designate Privacy and Security Officers
- [ ] Complete workforce training

### Infrastructure

- [ ] Create resource group in compliant region
- [ ] Deploy VNet with proper subnetting
- [ ] Configure Network Security Groups
- [ ] Create private endpoints for all services
- [ ] Disable public network access

### Identity & Access

- [ ] Configure Azure AD tenant
- [ ] Register application in Azure AD
- [ ] Configure OAuth 2.0 with PKCE
- [ ] Enable multi-factor authentication
- [ ] Configure conditional access policies
- [ ] Implement RBAC for all resources

### Data Services

- [ ] Deploy Azure SQL with TDE enabled
- [ ] Configure customer-managed keys
- [ ] Enable SQL auditing and threat detection
- [ ] Deploy Cosmos DB with encryption
- [ ] Configure Blob Storage with encryption
- [ ] Enable storage analytics and logging

### Application Services

- [ ] Deploy App Service (Premium tier)
- [ ] Enable HTTPS only and TLS 1.2+
- [ ] Configure managed identity
- [ ] Implement VNet integration
- [ ] Configure application logging

### Security Services

- [ ] Create Key Vault with purge protection
- [ ] Configure private endpoints for Key Vault
- [ ] Enable RBAC for Key Vault
- [ ] Store all secrets in Key Vault
- [ ] Configure key rotation policies

### Monitoring & Logging

- [ ] Create Log Analytics workspace
- [ ] Enable diagnostic logs for all resources
- [ ] Configure 90-day retention in Log Analytics
- [ ] Set up long-term log archival (6+ years)
- [ ] Enable Application Insights
- [ ] Configure alerts for security events

### API Gateway

- [ ] Deploy API Management
- [ ] Configure JWT validation
- [ ] Implement rate limiting
- [ ] Add security headers
- [ ] Enable request/response logging

### Compliance

- [ ] Assign HIPAA/HITRUST policy initiative
- [ ] Enable Microsoft Defender for Cloud
- [ ] Configure Azure Sentinel
- [ ] Set up compliance dashboard
- [ ] Document data flows and architecture

### Testing

- [ ] Security testing (SAST/DAST)
- [ ] Penetration testing
- [ ] Disaster recovery drill
- [ ] Incident response testing
- [ ] Load testing

### Documentation

- [ ] System security plan
- [ ] Network architecture diagram
- [ ] Data flow diagrams
- [ ] Incident response plan
- [ ] Disaster recovery plan
- [ ] Breach notification procedures

---

## Additional Resources

- [Azure HIPAA/HITECH Offering](https://docs.microsoft.com/azure/compliance/offerings/offering-hipaa-us)
- [Azure Security Benchmark](https://docs.microsoft.com/security/benchmark/azure/)
- [Azure Architecture Center - Healthcare](https://docs.microsoft.com/azure/architecture/industries/healthcare)
- [HITRUST on Azure](https://docs.microsoft.com/azure/compliance/offerings/offering-hitrust)

---

## Support

For Azure HIPAA compliance questions:
- **Azure Support:** Create support ticket in Azure Portal
- **Microsoft Compliance Manager:** In-portal compliance guidance
- **Azure Security Center:** Security recommendations and alerts

---

**Document Version:** 1.0
**Last Updated:** October 21, 2025
