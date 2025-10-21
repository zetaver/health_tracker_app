# Google Cloud Platform (GCP) HIPAA Configuration Guide

## Overview

This guide provides detailed configuration steps for deploying a HIPAA-compliant iOS health tracker backend on Google Cloud Platform (GCP). GCP offers comprehensive services covered under their Business Associate Agreement (BAA) for HIPAA compliance.

**Document Version:** 1.0
**Last Updated:** October 21, 2025
**GCP Compliance Programs:** HIPAA/HITECH, HITRUST CSF, ISO 27001, SOC 2, FedRAMP

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Business Associate Agreement](#business-associate-agreement)
3. [Architecture Overview](#architecture-overview)
4. [GCP Services Configuration](#gcp-services-configuration)
5. [Security Configuration](#security-configuration)
6. [Monitoring & Compliance](#monitoring--compliance)
7. [Deployment Checklist](#deployment-checklist)

---

## Prerequisites

### Required GCP Resources

- GCP Organization or Folder (recommended for enterprise)
- GCP Project for HIPAA workloads
- Billing account enabled
- Appropriate IAM roles (Project Editor, Security Admin)
- gcloud CLI installed and configured
- Terraform or Deployment Manager (for infrastructure as code)

### Compliance Requirements

- Sign Business Associate Agreement (BAA) with Google
- Complete HIPAA Security Risk Assessment
- Designate Privacy and Security Officers
- Document policies and procedures
- Train workforce on HIPAA requirements

---

## Business Associate Agreement

### Obtaining the BAA

1. **Google Cloud Console:**
   - Navigate to: IAM & Admin > Service Status
   - Review BAA-eligible services
   - Request BAA through GCP Support or Account Manager

2. **Google Cloud Compliance:**
   - Visit: https://cloud.google.com/security/compliance/hipaa
   - Download compliance resources
   - Review HIPAA Implementation Guide

3. **Enterprise Customers:**
   - BAA available through Google Cloud sales team
   - Required for all projects handling PHI
   - Sign before deploying any PHI workloads

### BAA Covered Services

**HIPAA-Eligible GCP Services (Partial List):**

| Service Category | GCP Services |
|-----------------|--------------|
| Compute | Compute Engine, App Engine (Flexible), Cloud Functions, GKE, Cloud Run |
| Storage | Cloud Storage, Persistent Disk, Filestore |
| Database | Cloud SQL, Firestore, Bigtable, Spanner, Memorystore |
| Networking | VPC, Cloud Load Balancing, Cloud CDN, Cloud VPN, Cloud Interconnect |
| Security | Cloud KMS, Secret Manager, Cloud IAM, Identity Platform, Cloud Armor |
| Monitoring | Cloud Logging, Cloud Monitoring, Cloud Trace, Error Reporting |
| AI/ML | Vertex AI (select services), Healthcare API, Cloud Vision API (limited) |
| Data Analytics | BigQuery, Dataflow, Pub/Sub, Data Fusion |

**Not HIPAA-Eligible:**
- App Engine Standard (first generation)
- Some preview/beta services
- Third-party marketplace applications (unless separately certified)

**Important:** Always verify current HIPAA eligibility at https://cloud.google.com/security/compliance/hipaa-compliance

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
│                   Google Cloud Platform (HIPAA)                  │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │         Cloud Load Balancer + Cloud Armor (WAF)            │ │
│  │  (DDoS Protection, TLS Termination, SSL Certificate)       │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
│                                  │                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Cloud Endpoints / Apigee                 │ │
│  │  (API Gateway, Authentication, Rate Limiting, Monitoring)  │ │
│  └──────────────────────────────┬─────────────────────────────┘ │
│                                  │                                │
│  ┌──────────────────────────────┴─────────────────────────────┐ │
│  │                      VPC Network (Private)                  │ │
│  │                                                              │ │
│  │  ┌─────────────────┐         ┌──────────────────┐          │ │
│  │  │  Cloud Run /    │         │  Cloud Functions │          │ │
│  │  │  App Engine     │◀───────▶│  (Background     │          │ │
│  │  │  (REST API)     │         │   Processing)    │          │ │
│  │  │  + Service      │         └──────────────────┘          │ │
│  │  │  Account        │                   │                   │ │
│  │  └────────┬────────┘                   │                   │ │
│  │           │                             │                   │ │
│  │           │         ┌───────────────────┘                   │ │
│  │           │         │                                       │ │
│  │  ┌────────┴─────────┴─────┐   ┌──────────────────┐         │ │
│  │  │   Cloud SQL            │   │  Firestore       │         │ │
│  │  │   (PostgreSQL/MySQL)   │   │  (NoSQL)         │         │ │
│  │  │   + CMEK Encryption    │   │  + Encryption    │         │ │
│  │  │   + Private IP         │   │  + App Engine    │         │ │
│  │  └────────────────────────┘   └──────────────────┘         │ │
│  │                                                              │ │
│  │  ┌────────────────────────┐   ┌──────────────────┐         │ │
│  │  │  Cloud Storage         │   │  Cloud KMS       │         │ │
│  │  │  (Encrypted Files,     │◀──│  (Encryption     │         │ │
│  │  │   Backups, Logs)       │   │   Keys)          │         │ │
│  │  │  + CMEK Encryption     │   │  + HSM           │         │ │
│  │  └────────────────────────┘   └──────────────────┘         │ │
│  │                                                              │ │
│  │  ┌────────────────────────┐   ┌──────────────────┐         │ │
│  │  │  Secret Manager        │   │  Identity        │         │ │
│  │  │  (API Keys, Tokens,    │   │  Platform        │         │ │
│  │  │   Credentials)         │   │  (OAuth 2.0)     │         │ │
│  │  └────────────────────────┘   └──────────────────┘         │ │
│  │                                                              │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Security & Monitoring Layer                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │ │
│  │  │Cloud Logging │  │Cloud         │  │Security         │  │ │
│  │  │(Audit Logs,  │  │Monitoring    │  │Command Center   │  │ │
│  │  │ Access Logs) │  │(Metrics,     │  │(SIEM, Threat    │  │ │
│  │  │              │  │ Alerts)      │  │ Detection)      │  │ │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## GCP Services Configuration

### 1. Identity Platform (Firebase Authentication)

**Purpose:** User authentication, OAuth 2.0/OpenID Connect provider

#### Configuration:

```bash
# Enable Identity Platform API
gcloud services enable identitytoolkit.googleapis.com

# Configure Identity Platform
gcloud identity-platform tenant create \
    --display-name="Health Tracker Users" \
    --enable-email-link-signin \
    --enable-anonymous-users=false
```

#### Required Settings:

**OAuth 2.0 Configuration:**
- **Grant Type:** Authorization Code with PKCE
- **Token Type:** JWT
- **Access Token Lifetime:** 60 minutes (maximum)
- **Refresh Token Lifetime:** 14 days
- **ID Token Lifetime:** 1 hour

**Authentication Methods:**
- Email/Password (with strong password policy)
- Google Sign-In
- Apple Sign-In
- Multi-factor authentication (SMS, TOTP)

**Password Policy:**
```json
{
  "passwordPolicyConfig": {
    "passwordPolicyEnforcementState": "ENFORCE",
    "passwordPolicyVersions": [
      {
        "customStrengthOptions": {
          "minPasswordLength": 12,
          "maxPasswordLength": 128,
          "containsLowercaseCharacter": true,
          "containsUppercaseCharacter": true,
          "containsNumericCharacter": true,
          "containsNonAlphanumericCharacter": true
        }
      }
    ]
  }
}
```

**MFA Configuration:**
```bash
# Enable MFA
gcloud identity-platform config update \
    --enable-multi-factor-auth \
    --mfa-state=MANDATORY \
    --allowed-mfa-types=PHONE_SMS,SOFTWARE_TOTP
```

**Custom Claims for RBAC:**
```javascript
// Add custom claims via Admin SDK
admin.auth().setCustomUserClaims(uid, {
  role: 'patient',
  permissions: ['read:health_data', 'write:health_data']
});
```

---

### 2. Cloud Run (Serverless Container Platform)

**Purpose:** Host containerized REST API backend

#### Configuration:

```bash
# Enable Cloud Run API
gcloud services enable run.googleapis.com

# Deploy Cloud Run service
gcloud run deploy healthtracker-api \
    --image gcr.io/PROJECT_ID/healthtracker-api:latest \
    --platform managed \
    --region us-central1 \
    --no-allow-unauthenticated \
    --ingress internal-and-cloud-load-balancing \
    --vpc-connector healthtracker-connector \
    --service-account healthtracker-api@PROJECT_ID.iam.gserviceaccount.com \
    --set-env-vars "PROJECT_ID=PROJECT_ID" \
    --set-secrets "DB_PASSWORD=db-password:latest,JWT_SECRET=jwt-secret:latest" \
    --min-instances 1 \
    --max-instances 10 \
    --cpu 2 \
    --memory 1Gi \
    --timeout 300s \
    --concurrency 80
```

#### HIPAA Requirements:

**Security Settings:**
- **Authentication:** Required (`--no-allow-unauthenticated`)
- **Ingress:** Internal + Load Balancer only (no direct public access)
- **VPC Connector:** Connect to VPC for database access
- **Service Account:** Dedicated service account with minimal permissions
- **Secrets:** Use Secret Manager (not environment variables)

**Environment Configuration:**
```yaml
# service.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: healthtracker-api
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: '1'
        autoscaling.knative.dev/maxScale: '10'
        run.googleapis.com/vpc-access-connector: 'healthtracker-connector'
        run.googleapis.com/vpc-access-egress: 'private-ranges-only'
        run.googleapis.com/execution-environment: 'gen2'
    spec:
      serviceAccountName: healthtracker-api@PROJECT_ID.iam.gserviceaccount.com
      containerConcurrency: 80
      timeoutSeconds: 300
      containers:
      - image: gcr.io/PROJECT_ID/healthtracker-api:latest
        ports:
        - containerPort: 8080
        env:
        - name: PROJECT_ID
          value: PROJECT_ID
        - name: ENVIRONMENT
          value: production
        volumeMounts:
        - name: secrets
          mountPath: /secrets
          readOnly: true
        resources:
          limits:
            cpu: '2'
            memory: 1Gi
      volumes:
      - name: secrets
        secret:
          secretName: api-secrets
```

**IAM Permissions:**
```bash
# Create service account
gcloud iam service-accounts create healthtracker-api \
    --display-name "Health Tracker API Service Account"

# Grant minimum necessary permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

**VPC Connector:**
```bash
# Create VPC connector for Cloud Run
gcloud compute networks vpc-access connectors create healthtracker-connector \
    --region us-central1 \
    --network healthtracker-vpc \
    --range 10.8.0.0/28 \
    --min-instances 2 \
    --max-instances 10
```

---

### 3. Cloud SQL (Managed Relational Database)

**Purpose:** Store structured PHI (user health records, metadata)

#### Configuration:

```bash
# Create Cloud SQL instance (PostgreSQL)
gcloud sql instances create healthtracker-db \
    --database-version POSTGRES_15 \
    --tier db-custom-2-7680 \
    --region us-central1 \
    --network projects/PROJECT_ID/global/networks/healthtracker-vpc \
    --no-assign-ip \
    --database-flags cloudsql.iam_authentication=on \
    --enable-bin-log \
    --backup-start-time 02:00 \
    --retained-backups-count 30 \
    --retained-transaction-log-days 7 \
    --maintenance-window-day SUN \
    --maintenance-window-hour 3 \
    --require-ssl \
    --disk-encryption-key projects/PROJECT_ID/locations/us-central1/keyRings/healthtracker-kr/cryptoKeys/cloudsql-key

# Create database
gcloud sql databases create healthtracker \
    --instance healthtracker-db

# Create database user
gcloud sql users create dbadmin \
    --instance healthtracker-db \
    --password <strong-password>
```

#### HIPAA Security Requirements:

**Encryption:**
- **At Rest:** Customer-Managed Encryption Keys (CMEK) via Cloud KMS
- **In Transit:** SSL/TLS 1.2+ required
- **Transparent Data Encryption:** Enabled by default
- **Backups:** Encrypted with same CMEK

**Network Security:**
- **Private IP:** Required (no public IP address)
- **VPC Peering:** Connect to application VPC
- **Authorized Networks:** Empty (deny all external access)
- **SSL Enforcement:** Required for all connections

**Connection String:**
```
# Using Cloud SQL Proxy (recommended)
postgresql://username:password@localhost:5432/healthtracker?sslmode=require

# Using Private IP
postgresql://username:password@10.1.2.3:5432/healthtracker?sslmode=verify-full&sslrootcert=/path/to/server-ca.pem
```

**IAM Database Authentication (Recommended):**
```bash
# Create IAM user
gcloud sql users create healthtracker-api@PROJECT_ID.iam.gserviceaccount.com \
    --instance healthtracker-db \
    --type cloud_iam_service_account

# Connect using IAM
gcloud sql connect healthtracker-db --user=healthtracker-api@PROJECT_ID.iam.gserviceaccount.com
```

**Audit Logging:**
```bash
# Enable Cloud SQL audit logs
gcloud sql instances patch healthtracker-db \
    --database-flags \
    cloudsql.enable_pgaudit=on,\
    pgaudit.log=all,\
    log_connections=on,\
    log_disconnections=on,\
    log_duration=on,\
    log_lock_waits=on
```

**High Availability:**
```bash
# Enable HA configuration
gcloud sql instances patch healthtracker-db \
    --availability-type REGIONAL \
    --enable-point-in-time-recovery
```

**Backup & Recovery:**
- **Automated Backups:** Daily at 2:00 AM
- **Backup Retention:** 30 days minimum (6+ years for audit data)
- **Point-in-Time Recovery:** 7 days
- **Transaction Logs:** Retained for 7 days
- **Export to Cloud Storage:** Long-term archival (encrypted)

---

### 4. Firestore (NoSQL Database)

**Purpose:** Real-time data synchronization, session storage, metadata

#### Configuration:

```bash
# Create Firestore database (Native mode)
gcloud firestore databases create \
    --region=us-central1 \
    --type=firestore-native

# Enable CMEK encryption (requires Firestore API)
gcloud alpha firestore databases update \
    --database=(default) \
    --encryption-config=kms-key-name=projects/PROJECT_ID/locations/us-central1/keyRings/healthtracker-kr/cryptoKeys/firestore-key
```

#### HIPAA Requirements:

**Encryption:**
- **At Rest:** Customer-Managed Encryption Keys (CMEK)
- **In Transit:** TLS 1.2+ (automatic)
- **Field-Level Encryption:** Optional additional layer for highly sensitive data

**Security Rules:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper function to check authentication
    function isAuthenticated() {
      return request.auth != null;
    }

    // Helper function to check user owns the resource
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    // User can only access their own health data
    match /users/{userId}/healthRecords/{recordId} {
      allow read, write: if isOwner(userId);
    }

    // Providers can access assigned patients' data
    match /users/{userId}/healthRecords/{recordId} {
      allow read: if isAuthenticated()
                  && get(/databases/$(database)/documents/users/$(userId)).data.assignedProvider == request.auth.uid;
    }

    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

**Access Control:**
- **IAM Roles:** `roles/datastore.user` (application service account)
- **Security Rules:** Enforce user-level access control
- **VPC Service Controls:** Restrict data exfiltration

**Audit Logging:**
```bash
# Enable Firestore audit logs
gcloud logging sinks create firestore-audit-sink \
    storage.googleapis.com/healthtracker-audit-logs \
    --log-filter='resource.type="cloud_firestore_database" AND (protoPayload.methodName=~".*Write" OR protoPayload.methodName=~".*Read")'
```

**Backup & Export:**
```bash
# Schedule weekly exports
gcloud firestore export gs://healthtracker-backups/firestore/$(date +%Y%m%d) \
    --collection-ids=users,healthRecords
```

---

### 5. Cloud Storage (Object Storage)

**Purpose:** Store encrypted files, backups, audit logs

#### Configuration:

```bash
# Create Cloud Storage bucket
gcloud storage buckets create gs://healthtracker-phi-data \
    --location us-central1 \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --default-encryption-key projects/PROJECT_ID/locations/us-central1/keyRings/healthtracker-kr/cryptoKeys/storage-key

# Enable versioning
gcloud storage buckets update gs://healthtracker-phi-data \
    --versioning

# Set lifecycle policy
cat > lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 2555,
          "matchesPrefix": ["temp/"]
        }
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF

gcloud storage buckets update gs://healthtracker-phi-data \
    --lifecycle-file lifecycle.json
```

#### HIPAA Requirements:

**Encryption:**
- **Server-Side Encryption:** CMEK via Cloud KMS (AES-256)
- **Client-Side Encryption:** Optional additional layer
- **Encryption in Transit:** TLS 1.2+ (automatic)

**Access Control:**
```bash
# Grant service account access
gcloud storage buckets add-iam-policy-binding gs://healthtracker-phi-data \
    --member="serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"

# Prevent public access
gcloud storage buckets update gs://healthtracker-phi-data \
    --public-access-prevention
```

**Signed URLs for Temporary Access:**
```python
# Generate signed URL (expires in 15 minutes)
from google.cloud import storage
from datetime import timedelta

def generate_signed_url(bucket_name, blob_name):
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)

    url = blob.generate_signed_url(
        version="v4",
        expiration=timedelta(minutes=15),
        method="GET"
    )
    return url
```

**Audit Logging:**
```bash
# Enable access logging
gcloud storage buckets update gs://healthtracker-phi-data \
    --log-bucket gs://healthtracker-access-logs \
    --log-object-prefix access-logs/
```

**Retention & Compliance:**
- **Retention Policy:** 6 years for HIPAA compliance
- **Bucket Lock:** Prevent deletion during retention period
- **Object Versioning:** Track changes and enable recovery
- **Lifecycle Management:** Auto-archive old data

```bash
# Set retention policy (6 years)
gcloud storage buckets update gs://healthtracker-audit-logs \
    --retention-period 2190d

# Lock retention policy (irreversible)
gcloud storage buckets update gs://healthtracker-audit-logs \
    --lock-retention-policy
```

---

### 6. Cloud KMS (Key Management Service)

**Purpose:** Manage encryption keys for CMEK

#### Configuration:

```bash
# Create key ring
gcloud kms keyrings create healthtracker-kr \
    --location us-central1

# Create keys for different services
gcloud kms keys create cloudsql-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --purpose encryption \
    --protection-level hsm \
    --rotation-period 90d \
    --next-rotation-time 2025-01-20T00:00:00Z

gcloud kms keys create storage-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --purpose encryption \
    --protection-level hsm \
    --rotation-period 90d

gcloud kms keys create firestore-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --purpose encryption \
    --protection-level hsm \
    --rotation-period 90d

# Create application-level encryption key
gcloud kms keys create app-encryption-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --purpose encryption \
    --protection-level hsm \
    --rotation-period 90d
```

#### HIPAA Requirements:

**Key Protection:**
- **HSM-backed Keys:** Use `--protection-level hsm` for FIPS 140-2 Level 3
- **Automatic Rotation:** 90-day rotation period
- **Key Versions:** Maintain previous key versions for decryption
- **Audit Logging:** Track all key usage

**IAM Permissions:**
```bash
# Grant Cloud SQL permission to use key
gcloud kms keys add-iam-policy-binding cloudsql-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --member serviceAccount:service-PROJECT_NUMBER@gcp-sa-cloud-sql.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter

# Grant Cloud Storage permission
gcloud kms keys add-iam-policy-binding storage-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --member serviceAccount:service-PROJECT_NUMBER@gs-project-accounts.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter

# Grant application service account permission
gcloud kms keys add-iam-policy-binding app-encryption-key \
    --keyring healthtracker-kr \
    --location us-central1 \
    --member serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

**Key Usage Auditing:**
```bash
# Create log sink for KMS operations
gcloud logging sinks create kms-audit-sink \
    storage.googleapis.com/healthtracker-audit-logs \
    --log-filter='resource.type="cloudkms_cryptokey"'
```

---

### 7. Secret Manager

**Purpose:** Securely store API keys, passwords, tokens

#### Configuration:

```bash
# Enable Secret Manager API
gcloud services enable secretmanager.googleapis.com

# Create secrets
echo -n "your-database-password" | gcloud secrets create db-password \
    --data-file=- \
    --replication-policy automatic

echo -n "your-jwt-secret-key" | gcloud secrets create jwt-secret \
    --data-file=- \
    --replication-policy automatic

echo -n "your-api-key" | gcloud secrets create third-party-api-key \
    --data-file=- \
    --replication-policy automatic

# Enable CMEK encryption for secrets
gcloud secrets update db-password \
    --kms-key-name projects/PROJECT_ID/locations/us-central1/keyRings/healthtracker-kr/cryptoKeys/secrets-key
```

#### HIPAA Requirements:

**Access Control:**
```bash
# Grant service account access to specific secrets
gcloud secrets add-iam-policy-binding db-password \
    --member="serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# Audit who has access
gcloud secrets get-iam-policy db-password
```

**Secret Rotation:**
```bash
# Add new secret version
echo -n "new-database-password" | gcloud secrets versions add db-password \
    --data-file=-

# Disable old version
gcloud secrets versions disable 1 --secret db-password

# Destroy old version after verification
gcloud secrets versions destroy 1 --secret db-password
```

**Audit Logging:**
- All secret access is logged automatically
- Review logs regularly for unauthorized access
- Alert on suspicious patterns

---

### 8. Cloud Load Balancer + Cloud Armor

**Purpose:** HTTPS load balancing, DDoS protection, WAF

#### Configuration:

```bash
# Reserve static IP
gcloud compute addresses create healthtracker-ip \
    --global

# Create SSL certificate (managed)
gcloud compute ssl-certificates create healthtracker-cert \
    --domains api.healthtracker.com \
    --global

# Create backend service
gcloud compute backend-services create healthtracker-backend \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTPS \
    --port-name=https \
    --timeout=30s \
    --health-checks=healthtracker-health-check \
    --enable-cdn=false \
    --enable-logging \
    --logging-sample-rate=1.0

# Create URL map
gcloud compute url-maps create healthtracker-urlmap \
    --default-service healthtracker-backend

# Create target HTTPS proxy
gcloud compute target-https-proxies create healthtracker-https-proxy \
    --url-map healthtracker-urlmap \
    --ssl-certificates healthtracker-cert \
    --global-ssl-certificates healthtracker-cert \
    --ssl-policy modern-ssl-policy

# Create SSL policy (TLS 1.2+)
gcloud compute ssl-policies create modern-ssl-policy \
    --profile MODERN \
    --min-tls-version 1.2

# Create forwarding rule
gcloud compute forwarding-rules create healthtracker-https-rule \
    --address healthtracker-ip \
    --global \
    --target-https-proxy healthtracker-https-proxy \
    --ports 443
```

#### Cloud Armor Configuration:

```bash
# Create Cloud Armor security policy
gcloud compute security-policies create hipaa-security-policy \
    --description "HIPAA security policy for health tracker API"

# Block common attack patterns
gcloud compute security-policies rules create 1000 \
    --security-policy hipaa-security-policy \
    --expression "evaluatePreconfiguredExpr('sqli-stable')" \
    --action deny-403 \
    --description "Block SQL injection"

gcloud compute security-policies rules create 1001 \
    --security-policy hipaa-security-policy \
    --expression "evaluatePreconfiguredExpr('xss-stable')" \
    --action deny-403 \
    --description "Block XSS"

# Rate limiting
gcloud compute security-policies rules create 2000 \
    --security-policy hipaa-security-policy \
    --expression "true" \
    --action rate-based-ban \
    --rate-limit-threshold-count 100 \
    --rate-limit-threshold-interval-sec 60 \
    --ban-duration-sec 600 \
    --conform-action allow \
    --exceed-action deny-429 \
    --enforce-on-key IP

# Geographic restrictions (optional)
gcloud compute security-policies rules create 3000 \
    --security-policy hipaa-security-policy \
    --expression "origin.region_code in ['CN', 'RU']" \
    --action deny-403 \
    --description "Block specific regions"

# Attach policy to backend service
gcloud compute backend-services update healthtracker-backend \
    --security-policy hipaa-security-policy \
    --global
```

---

## Security Configuration

### 1. VPC Network

```bash
# Create VPC
gcloud compute networks create healthtracker-vpc \
    --subnet-mode custom \
    --bgp-routing-mode regional

# Create subnets
gcloud compute networks subnets create app-subnet \
    --network healthtracker-vpc \
    --region us-central1 \
    --range 10.1.0.0/24 \
    --enable-private-ip-google-access \
    --enable-flow-logs \
    --logging-aggregation-interval=interval-5-sec \
    --logging-flow-sampling=1.0

gcloud compute networks subnets create db-subnet \
    --network healthtracker-vpc \
    --region us-central1 \
    --range 10.1.1.0/24 \
    --enable-private-ip-google-access \
    --enable-flow-logs

# Create firewall rules (deny all by default)
gcloud compute firewall-rules create allow-internal \
    --network healthtracker-vpc \
    --allow tcp,udp,icmp \
    --source-ranges 10.1.0.0/16 \
    --description "Allow internal VPC traffic"

gcloud compute firewall-rules create allow-health-checks \
    --network healthtracker-vpc \
    --allow tcp:443 \
    --source-ranges 35.191.0.0/16,130.211.0.0/22 \
    --description "Allow Google Cloud health checks"

gcloud compute firewall-rules create deny-all-ingress \
    --network healthtracker-vpc \
    --action deny \
    --rules all \
    --source-ranges 0.0.0.0/0 \
    --priority 65535 \
    --description "Deny all other ingress traffic"
```

### 2. VPC Service Controls

**Purpose:** Data exfiltration prevention, additional perimeter security

```bash
# Create access policy (organization level)
gcloud access-context-manager policies create \
    --organization ORG_ID \
    --title "Health Tracker HIPAA Policy"

# Create service perimeter
gcloud access-context-manager perimeters create healthtracker_perimeter \
    --policy POLICY_ID \
    --title "Health Tracker Perimeter" \
    --resources "projects/PROJECT_NUMBER" \
    --restricted-services "storage.googleapis.com,sqladmin.googleapis.com,firestore.googleapis.com" \
    --vpc-allowed-services "storage.googleapis.com,sqladmin.googleapis.com" \
    --enable-vpc-accessible-services

# Add access levels
gcloud access-context-manager levels create corporate_network \
    --policy POLICY_ID \
    --title "Corporate Network Access" \
    --basic-level-spec ip_subnetworks="203.0.113.0/24"
```

### 3. IAM & Organization Policy

**Principle of Least Privilege:**

```bash
# Custom role for API service account
gcloud iam roles create healthTrackerAPIRole \
    --project PROJECT_ID \
    --title "Health Tracker API Role" \
    --description "Minimal permissions for API service" \
    --permissions "cloudsql.instances.connect,secretmanager.versions.access,cloudkms.cryptoKeyVersions.useToEncrypt,cloudkms.cryptoKeyVersions.useToDecrypt" \
    --stage GA

# Bind custom role
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:healthtracker-api@PROJECT_ID.iam.gserviceaccount.com" \
    --role="projects/PROJECT_ID/roles/healthTrackerAPIRole"
```

**Organization Policies:**

```bash
# Require OS Login
gcloud resource-manager org-policies enable-enforce \
    compute.requireOsLogin \
    --project PROJECT_ID

# Disable service account key creation
gcloud resource-manager org-policies enable-enforce \
    iam.disableServiceAccountKeyCreation \
    --project PROJECT_ID

# Restrict public IP addresses
gcloud resource-manager org-policies enable-enforce \
    compute.vmExternalIpAccess \
    --project PROJECT_ID

# Require CMEK encryption
gcloud resource-manager org-policies set-policy cmek-policy.yaml \
    --project PROJECT_ID
```

### 4. Security Command Center

```bash
# Enable Security Command Center (organization level)
gcloud services enable securitycenter.googleapis.com

# Enable Security Health Analytics
gcloud scc settings update \
    --organization ORG_ID \
    --enable-security-health-analytics

# Enable Web Security Scanner
gcloud scc settings update \
    --organization ORG_ID \
    --enable-web-security-scanner

# Create notification channel for findings
gcloud scc notifications create hipaa-security-findings \
    --organization ORG_ID \
    --description "HIPAA security findings" \
    --pubsub-topic projects/PROJECT_ID/topics/security-findings \
    --filter "state=\"ACTIVE\" AND severity=\"HIGH\""
```

---

## Monitoring & Compliance

### Cloud Logging

**HIPAA Audit Logs:**

```bash
# Create log bucket with retention
gcloud logging buckets create hipaa-audit-logs \
    --location us-central1 \
    --retention-days 2190 \
    --locked

# Create log sink for audit logs
gcloud logging sinks create hipaa-audit-sink \
    logging.googleapis.com/projects/PROJECT_ID/locations/us-central1/buckets/hipaa-audit-logs \
    --log-filter='protoPayload.methodName=~".*" AND
                  (resource.type="cloud_sql_database" OR
                   resource.type="gcs_bucket" OR
                   resource.type="cloud_firestore_database" OR
                   resource.type="cloudkms_cryptokey" OR
                   resource.type="audited_resource")'
```

**Required Log Types:**

| Log Type | GCP Service | HIPAA Requirement |
|----------|-------------|-------------------|
| Admin Activity | All services | Configuration changes |
| Data Access | Cloud SQL, Firestore, Storage | PHI access |
| System Event | All services | Automated events |
| Cloud Audit Logs | IAM, Cloud KMS | Access control changes |

**Log Queries for Compliance:**

```
# PHI data access
resource.type="cloud_sql_database"
protoPayload.methodName="cloudsql.instances.connect"

# Failed authentication
protoPayload.status.code!=0
protoPayload.authenticationInfo.principalEmail!=""

# Key access
resource.type="cloudkms_cryptokey"
protoPayload.methodName="Decrypt" OR protoPayload.methodName="Encrypt"

# Firewall rule changes
resource.type="gce_firewall_rule"
protoPayload.methodName=~"compute.firewalls.*"
```

### Cloud Monitoring

**Create Alerting Policies:**

```bash
# Alert on multiple failed authentications
gcloud alpha monitoring policies create \
    --notification-channels CHANNEL_ID \
    --display-name "Multiple Failed Auth Attempts" \
    --condition-display-name "5+ failed auth in 15 min" \
    --condition-threshold-value 5 \
    --condition-threshold-duration 900s \
    --condition-filter 'resource.type="cloud_run_revision" AND metric.type="logging.googleapis.com/user/failed_auth"'

# Alert on unauthorized data access
gcloud alpha monitoring policies create \
    --notification-channels CHANNEL_ID \
    --display-name "Unauthorized Data Access" \
    --condition-display-name "Access denied events" \
    --condition-threshold-value 1 \
    --condition-threshold-duration 60s \
    --condition-filter 'protoPayload.status.code=7'
```

### Compliance Reporting

**Cloud Asset Inventory:**

```bash
# Export asset inventory
gcloud asset export \
    --output-path gs://healthtracker-compliance/asset-inventory/$(date +%Y%m%d).json \
    --content-type resource \
    --project PROJECT_ID
```

**Compliance Dashboard:**
- Use Security Command Center for compliance posture
- Export to BigQuery for custom reporting
- Regular compliance reviews (monthly/quarterly)

---

## Deployment Checklist

### Pre-Deployment

- [ ] Sign Business Associate Agreement with Google
- [ ] Complete HIPAA Security Risk Assessment
- [ ] Document security policies and procedures
- [ ] Designate Privacy and Security Officers
- [ ] Complete workforce training

### Infrastructure

- [ ] Create GCP project in compliant region (us-central1, us-east4)
- [ ] Configure VPC with private subnets
- [ ] Enable VPC Flow Logs
- [ ] Configure firewall rules (deny-all default)
- [ ] Enable VPC Service Controls

### Identity & Access

- [ ] Configure Identity Platform
- [ ] Enable OAuth 2.0 with PKCE
- [ ] Require multi-factor authentication
- [ ] Implement RBAC with custom claims
- [ ] Configure password policy (12+ chars, complexity)

### Data Services

- [ ] Deploy Cloud SQL with CMEK encryption
- [ ] Enable private IP only (no public access)
- [ ] Enable Cloud SQL audit logs
- [ ] Configure automated backups (30+ days retention)
- [ ] Deploy Firestore with CMEK
- [ ] Configure Firestore security rules
- [ ] Create Cloud Storage buckets with CMEK
- [ ] Enable object versioning and lifecycle management

### Application Services

- [ ] Deploy Cloud Run with private ingress
- [ ] Configure VPC connector
- [ ] Use dedicated service account
- [ ] Store secrets in Secret Manager
- [ ] Enable Cloud Run audit logs

### Security Services

- [ ] Create Cloud KMS key ring
- [ ] Create HSM-backed encryption keys
- [ ] Enable automatic key rotation (90 days)
- [ ] Configure Secret Manager with CMEK
- [ ] Enable audit logging for key access

### Networking & Load Balancing

- [ ] Create Cloud Load Balancer
- [ ] Configure SSL certificate (managed)
- [ ] Enforce TLS 1.2+ (SSL policy)
- [ ] Enable Cloud Armor
- [ ] Configure WAF rules (SQL injection, XSS)
- [ ] Implement rate limiting

### Monitoring & Logging

- [ ] Enable Cloud Logging for all services
- [ ] Create log bucket with 6+ year retention
- [ ] Configure log sinks for audit logs
- [ ] Enable Cloud Monitoring
- [ ] Create alerting policies for security events
- [ ] Enable Security Command Center

### Compliance

- [ ] Configure organization policies
- [ ] Enable Security Health Analytics
- [ ] Set up VPC Service Controls perimeter
- [ ] Document data flows and architecture
- [ ] Schedule regular compliance audits

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

- [GCP HIPAA Compliance](https://cloud.google.com/security/compliance/hipaa)
- [HIPAA Implementation Guide](https://cloud.google.com/architecture/landing-zones/hipaa-guide)
- [GCP Security Best Practices](https://cloud.google.com/security/best-practices)
- [Healthcare & Life Sciences Solutions](https://cloud.google.com/solutions/healthcare-life-sciences)
- [HITRUST on GCP](https://cloud.google.com/security/compliance/hitrust)

---

## Support

For GCP HIPAA compliance questions:
- **GCP Support:** Create support case in Cloud Console
- **Compliance Documentation:** cloud.google.com/security/compliance
- **Healthcare Solutions Team:** Contact via GCP sales

---

**Document Version:** 1.0
**Last Updated:** October 21, 2025
