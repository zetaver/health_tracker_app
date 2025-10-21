# HIPAA Compliance Guide for iOS Health Tracker App

## Overview

This document outlines the key HIPAA (Health Insurance Portability and Accountability Act) compliance requirements for an iOS health tracking application that reads data from Apple HealthKit and transmits it to a cloud backend (Azure or Google Cloud Platform).

**Document Version:** 1.0
**Last Updated:** October 21, 2025
**Compliance Framework:** HIPAA/HITECH Act

---

## Table of Contents

1. [HIPAA Fundamentals](#hipaa-fundamentals)
2. [Data Encryption Standards](#data-encryption-standards)
3. [User Authentication & Authorization](#user-authentication--authorization)
4. [Handling PHI on iOS Devices](#handling-phi-on-ios-devices)
5. [Logging, Audit Trails & Access Control](#logging-audit-trails--access-control)
6. [HealthKit Best Practices](#healthkit-best-practices)
7. [Cloud Provider Requirements](#cloud-provider-requirements)
8. [Compliance Checklist](#compliance-checklist)

---

## HIPAA Fundamentals

### What is PHI (Protected Health Information)?

PHI includes any health information that can be linked to an individual, including:
- Health status, conditions, or treatment information
- Payment information for healthcare services
- Identifiable demographic data (name, address, SSN, medical record numbers)
- **HealthKit data combined with user identifiers**

### Key HIPAA Rules

1. **Privacy Rule** - Protects PHI confidentiality
2. **Security Rule** - Establishes safeguards for ePHI (electronic PHI)
3. **Breach Notification Rule** - Requires notification of PHI breaches
4. **Enforcement Rule** - Defines penalties for violations

### Covered Entities vs. Business Associates

- **Covered Entity**: Healthcare providers, health plans, healthcare clearinghouses
- **Business Associate**: Third parties that handle PHI on behalf of covered entities
- **Your app** may be a Business Associate if providing services to a Covered Entity

---

## Data Encryption Standards

### 1. Data at Rest Encryption

#### iOS Device Storage

**Requirements:**
- **AES-256 encryption** for all PHI stored locally
- Use iOS Data Protection API with appropriate protection classes
- Never store PHI in UserDefaults, NSUserDefaults, or unencrypted files

**Implementation Standards:**

```swift
// REQUIRED: File Protection Level
// Use .completeUntilFirstUserAuthentication or .complete
let protectionLevel: FileProtectionType = .completeUntilFirstUserAuthentication

// For highly sensitive PHI
let highSecurityLevel: FileProtectionType = .complete
```

**Protection Classes:**

| Protection Class | Use Case | Security Level |
|-----------------|----------|----------------|
| `.complete` | Maximum security, data only accessible when device unlocked | Highest |
| `.completeUnlessOpen` | Files can remain open when device locks | High |
| `.completeUntilFirstUserAuthentication` | Data available after first unlock | Medium-High |
| `.none` | **NEVER USE for PHI** | Unacceptable |

**Keychain Storage:**
- Use iOS Keychain for encryption keys, tokens, and credentials
- Set `kSecAttrAccessible` to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Enable `kSecAttrSynchronizable: false` to prevent iCloud Keychain sync

**Core Data/SQLite:**
- Enable encryption at database level
- Use SQLCipher or encrypted Core Data store
- Implement automatic purging of cached data

#### Cloud Storage (Azure/GCP)

**Requirements:**
- Server-side encryption (SSE) with AES-256
- Encryption keys managed by FIPS 140-2 validated HSMs
- Customer-managed encryption keys (CMEK) recommended
- Encryption must be enabled for:
  - Database storage
  - Blob/object storage
  - Backups
  - Temporary/cache storage
  - Log files

### 2. Data in Transit Encryption

**Mandatory Requirements:**

1. **TLS 1.2 or higher** (TLS 1.3 recommended)
2. **Certificate pinning** to prevent MITM attacks
3. **Strong cipher suites only**
4. **No fallback to unencrypted connections**

**Recommended Cipher Suites:**
- TLS_AES_256_GCM_SHA384
- TLS_AES_128_GCM_SHA256
- TLS_CHACHA20_POLY1305_SHA256
- TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
- TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256

**Prohibited:**
- SSLv3, TLS 1.0, TLS 1.1
- RC4, DES, 3DES cipher suites
- Cipher suites without forward secrecy

**Implementation Requirements:**

```swift
// REQUIRED: Certificate pinning implementation
// REQUIRED: Reject connections with invalid certificates
// REQUIRED: Minimum TLS version 1.2
```

**Network Security Configuration:**
- Implement App Transport Security (ATS)
- No ATS exceptions for PHI endpoints
- Use HTTPS exclusively
- Implement certificate validation
- Enable HSTS (HTTP Strict Transport Security) on backend

---

## User Authentication & Authorization

### 1. Authentication Standards

**Multi-Factor Authentication (MFA):**
- **REQUIRED** for all users accessing PHI
- Minimum two factors:
  - Knowledge factor (password/PIN)
  - Possession factor (device, hardware token, SMS OTP)
  - Biometric factor (Face ID, Touch ID) - acceptable as second factor

**Password Requirements:**
- Minimum 8 characters (12+ recommended)
- Complexity: uppercase, lowercase, numbers, special characters
- Password history: prevent reuse of last 5 passwords
- Maximum password age: 90 days
- Account lockout: 5 failed attempts, 30-minute lockout
- Secure password reset process with identity verification

### 2. OAuth 2.0 Implementation

**Recommended Flow:**
- **Authorization Code Flow with PKCE** (Proof Key for Code Exchange)
- PKCE required for mobile apps to prevent authorization code interception

**OAuth 2.0 Requirements:**

```
Grant Type: Authorization Code with PKCE
Token Type: JWT (JSON Web Tokens)
Access Token Lifetime: 15-60 minutes (maximum)
Refresh Token Lifetime: 14-30 days
Token Storage: iOS Keychain only
Token Transmission: HTTPS only
```

**Required OAuth Scopes:**
- `read:health_data` - Read HealthKit data
- `write:health_data` - Write health data to backend
- `read:profile` - Access user profile
- Define granular scopes for minimum necessary access

### 3. JWT Token Standards

**Token Structure:**

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT"
  },
  "payload": {
    "sub": "user_id",
    "iss": "https://your-auth-server.com",
    "aud": "health-tracker-app",
    "exp": 1698264000,
    "iat": 1698260400,
    "jti": "unique-token-id",
    "scope": "read:health_data write:health_data",
    "user_role": "patient"
  }
}
```

**Requirements:**
- **Algorithm**: RS256 or ES256 (asymmetric)
- **Never use**: HS256 with shared secrets on client
- **Signature validation**: Required on every API call
- **Expiration**: Short-lived access tokens (15-60 min)
- **Unique identifier**: `jti` for token revocation
- **Audience claim**: Validate to prevent token misuse

**Token Storage:**

```swift
// REQUIRED: Store tokens in Keychain
// NEVER store tokens in:
// - UserDefaults
// - Plist files
// - Unencrypted files
// - App bundle
// - Shared containers (unless properly encrypted)
```

### 4. Session Management

**Requirements:**
- Automatic session timeout: 15 minutes of inactivity
- Absolute session timeout: 12 hours maximum
- Re-authentication required after timeout
- Session invalidation on logout
- Concurrent session limits (1-3 devices per user)
- Server-side session tracking and revocation

### 5. Role-Based Access Control (RBAC)

**Define Roles:**
- `patient` - Access own health data only
- `provider` - Access assigned patients' data
- `admin` - System administration, no PHI access unless authorized
- `auditor` - Read-only access to audit logs

**Principle of Least Privilege:**
- Grant minimum permissions necessary
- Implement attribute-based access control (ABAC) for fine-grained control
- Regular access reviews and certification

---

## Handling PHI on iOS Devices

### 1. Data Minimization

**Collect Only What's Necessary:**
- Request minimum HealthKit permissions required
- Store minimum PHI locally (prefer cloud storage)
- Implement data retention policies
- Automatic deletion of temporary data

### 2. Local Storage Security

**Requirements:**

1. **Encrypted Storage:**
   - All PHI must be encrypted at rest
   - Use iOS Data Protection API
   - SQLCipher for databases
   - Encrypted Core Data stores

2. **Secure Coding Practices:**
   - No PHI in logs, debug output, or crash reports
   - Clear PHI from memory after use
   - Secure memory handling for sensitive data
   - No PHI in screenshots or task switcher

3. **App Sandbox:**
   - Keep PHI within app sandbox
   - No PHI in shared containers (unless encrypted)
   - No PHI in app extensions without proper encryption

### 3. Memory Management

**Secure Data Handling:**

```swift
// REQUIRED: Clear sensitive data from memory
// Use Data instead of String for sensitive information
// Overwrite memory before deallocation
// Avoid string interpolation with PHI
```

**Best Practices:**
- Use `Data` type for PHI (can be securely zeroed)
- Avoid `String` for PHI (immutable, remains in memory)
- Implement secure deallocation
- Disable caching for PHI views

### 4. Background Tasks & App Extensions

**Security Considerations:**
- PHI access in background: encrypt and authenticate
- App extensions: separate keychain groups, encrypted storage
- HealthKit background delivery: validate and encrypt immediately
- Disable screenshots in PHI-containing views

### 5. Data Synchronization

**Requirements:**
- Sync only over encrypted channels (TLS 1.2+)
- Authenticate before sync
- Validate data integrity (HMAC, digital signatures)
- Handle sync conflicts securely
- Log all sync activities

### 6. Device Security

**User Requirements:**
- Device passcode/biometric lock required
- Jailbreak detection (recommended)
- OS version requirements (latest or N-1)
- App-level encryption independent of device encryption

**Implementation:**

```swift
// REQUIRED: Check device passcode status
// RECOMMENDED: Detect jailbroken devices
// REQUIRED: Verify device security posture
```

---

## Logging, Audit Trails & Access Control

### 1. Audit Logging Requirements

**HIPAA Required Audit Events:**

| Event Type | Details to Log | Retention |
|------------|----------------|-----------|
| User authentication | User ID, timestamp, result, IP/device | 6 years |
| PHI access | User ID, record ID, action, timestamp | 6 years |
| PHI modifications | Before/after values, user, timestamp | 6 years |
| Security incidents | Type, severity, affected data, response | 6 years |
| Configuration changes | What changed, who, when | 6 years |
| Authorization failures | User, resource, reason, timestamp | 6 years |

**Specific Events to Log:**

1. **Authentication:**
   - Successful logins
   - Failed login attempts
   - Logout events
   - Session timeouts
   - MFA events
   - Password changes
   - Account lockouts

2. **PHI Access:**
   - HealthKit data read
   - HealthKit data write
   - PHI transmission to server
   - PHI downloads
   - Search/query operations
   - Report generation

3. **Data Modifications:**
   - Create, update, delete operations
   - Bulk operations
   - Data exports
   - Data imports

4. **Administrative:**
   - User provisioning/deprovisioning
   - Permission changes
   - Configuration updates
   - System maintenance

5. **Security:**
   - Certificate validation failures
   - Encryption key rotations
   - Suspicious activities
   - Rate limiting triggers
   - API abuse attempts

### 2. Audit Log Format

**Required Fields:**

```json
{
  "timestamp": "2025-10-21T10:30:00.000Z",
  "event_id": "uuid-v4",
  "event_type": "phi_access",
  "user_id": "user-12345",
  "user_role": "patient",
  "action": "read",
  "resource_type": "health_record",
  "resource_id": "record-67890",
  "result": "success",
  "ip_address": "192.168.1.100",
  "device_id": "device-abc123",
  "app_version": "1.2.3",
  "session_id": "session-xyz789",
  "details": {
    "healthkit_data_type": "HKQuantityTypeIdentifierHeartRate",
    "record_count": 50,
    "date_range": "2025-10-01 to 2025-10-21"
  }
}
```

### 3. Log Protection

**Security Requirements:**
- Logs contain PHI identifiers - treat as ePHI
- Encrypt logs at rest (AES-256)
- Encrypt logs in transit (TLS 1.2+)
- Tamper-evident logging (WORM storage, digital signatures)
- Centralized log management (SIEM integration)
- Retention: Minimum 6 years
- Access control: Audit logs accessible only to authorized personnel

**Prohibited:**
- **NEVER log actual PHI content** (health values, diagnoses, etc.)
- **NEVER log authentication credentials**
- **NEVER log encryption keys**
- Use record IDs and metadata only

### 4. Access Control Implementation

**Technical Controls:**

1. **Role-Based Access Control (RBAC):**
   - Define roles with specific permissions
   - Enforce least privilege principle
   - Regular access reviews

2. **Attribute-Based Access Control (ABAC):**
   - Patient relationship verification
   - Time-based access constraints
   - Location-based restrictions
   - Purpose-of-use validation

3. **iOS-Specific Controls:**
   - HealthKit authorization per data type
   - Background access restrictions
   - App-to-app data sharing controls
   - Pasteboard access limitations

**Access Control Matrix Example:**

| Role | Read Own PHI | Read Others' PHI | Modify PHI | Admin Access | Audit Logs |
|------|-------------|------------------|------------|--------------|------------|
| Patient | ✓ | ✗ | ✓ (own) | ✗ | ✗ |
| Provider | ✓ | ✓ (assigned) | ✓ (assigned) | ✗ | ✗ |
| Admin | ✗ | ✗ | ✗ | ✓ | ✗ |
| Auditor | ✗ | ✗ | ✗ | ✗ | ✓ (read-only) |

### 5. Real-Time Monitoring & Alerting

**Security Monitoring:**
- Failed authentication attempts (threshold: 5 in 15 min)
- Unusual data access patterns
- Large data exports
- Access from unusual locations/devices
- After-hours access
- Privilege escalation attempts
- API rate limit violations

**Incident Response:**
- Automated alerting for security events
- Security Operations Center (SOC) integration
- Incident response plan
- Breach notification procedures (72 hours)

---

## HealthKit Best Practices

### 1. HealthKit Permissions

**Request Minimum Necessary Permissions:**

```swift
// GOOD: Request only what you need
let readTypes: Set<HKSampleType> = [
    HKObjectType.quantityType(forIdentifier: .heartRate)!,
    HKObjectType.quantityType(forIdentifier: .stepCount)!
]

// BAD: Requesting all available types
// Don't request blanket access to all HealthKit data
```

**Permission Requirements:**
- Request permissions at the point of use
- Provide clear explanation of why data is needed
- Allow granular opt-in/opt-out
- Respect user permission denials
- Periodic permission re-validation

### 2. HealthKit Data Handling

**Reading Data:**

```swift
// REQUIRED: Handle authorization status
// REQUIRED: Respect user's permission choices
// REQUIRED: Encrypt data immediately after reading
// REQUIRED: Minimize local storage duration
```

**Best Practices:**
- Query only necessary date ranges
- Implement pagination for large datasets
- Cache encrypted data only when necessary
- Clear cache on logout
- Validate data integrity

### 3. HealthKit Privacy

**Apple's Requirements:**
- No selling HealthKit data (grounds for App Store rejection)
- No sharing HealthKit data with third parties without consent
- No using HealthKit data for advertising
- No transferring HealthKit data to analytics services

**HIPAA Alignment:**
- HealthKit data + user identifiers = PHI
- Apply all HIPAA safeguards to HealthKit data
- Obtain explicit consent for data use
- Provide privacy notice (Notice of Privacy Practices)

### 4. Info.plist Privacy Declarations

**Required Entries:**

```xml
<key>NSHealthShareUsageDescription</key>
<string>We need access to your health data to track your wellness goals and provide personalized health insights. Your data is encrypted and HIPAA-compliant.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>We need permission to update your health data to save your manually entered health information.</string>
```

**Privacy Manifest (PrivacyInfo.xcprivacy):**
- Declare all data collection
- Specify data usage purposes
- List third-party SDKs that access data
- Document data retention policies

### 5. Data Sharing & Export

**User Controls:**
- Allow users to export their data
- Provide data deletion capabilities
- Support data portability (right to data access)
- Clear disclosure of who can access data

**Implementation:**
- Secure export format (encrypted)
- Audit log all exports
- Require re-authentication for exports
- Verify user identity before export

---

## Cloud Provider Requirements

### General HIPAA Cloud Requirements

**Business Associate Agreement (BAA):**
- **REQUIRED** before storing any PHI
- Azure and GCP both offer BAAs for HIPAA compliance
- BAA defines responsibilities and liabilities
- Review and sign before production deployment

**Covered Services:**
- Not all cloud services are HIPAA-eligible
- Use only BAA-covered services for PHI
- Maintain inventory of all services handling PHI

**Shared Responsibility Model:**
- Cloud provider: Infrastructure security
- Customer (You): Application security, access control, data encryption

### For detailed Azure and GCP configurations, see:
- [Azure HIPAA Configuration Guide](./AZURE_HIPAA_CONFIG.md)
- [GCP HIPAA Configuration Guide](./GCP_HIPAA_CONFIG.md)

---

## Compliance Checklist

### Administrative Safeguards

- [ ] Privacy policies and procedures documented
- [ ] Security policies and procedures documented
- [ ] Designated Privacy Officer
- [ ] Designated Security Officer
- [ ] Workforce training on HIPAA compliance
- [ ] Business Associate Agreements (BAAs) in place
- [ ] Risk assessment completed
- [ ] Incident response plan documented
- [ ] Breach notification procedures defined
- [ ] Data backup and disaster recovery plan
- [ ] Sanctions policy for violations

### Physical Safeguards

- [ ] Device security policies (passcode, encryption)
- [ ] Facility access controls (for servers)
- [ ] Workstation security policies
- [ ] Device and media disposal procedures
- [ ] Data center physical security (cloud provider)

### Technical Safeguards

#### Access Control
- [ ] Unique user IDs for all users
- [ ] Multi-factor authentication implemented
- [ ] Automatic session timeout (15 min)
- [ ] Encryption of PHI at rest (AES-256)
- [ ] Encryption of PHI in transit (TLS 1.2+)
- [ ] Role-based access control (RBAC)
- [ ] Emergency access procedures

#### Audit Controls
- [ ] Audit logging implemented for all PHI access
- [ ] Audit logs encrypted and protected
- [ ] Audit log retention (6+ years)
- [ ] Regular audit log reviews
- [ ] Security monitoring and alerting

#### Integrity Controls
- [ ] Data integrity validation (checksums, signatures)
- [ ] Protection from improper alteration
- [ ] Version control for PHI records

#### Transmission Security
- [ ] TLS 1.2+ for all transmissions
- [ ] Certificate pinning implemented
- [ ] No fallback to unencrypted protocols
- [ ] End-to-end encryption for sensitive communications

### iOS-Specific Requirements

- [ ] HealthKit permissions: minimum necessary only
- [ ] File protection level: `.completeUntilFirstUserAuthentication` or higher
- [ ] Keychain storage for tokens and keys
- [ ] No PHI in UserDefaults or unencrypted storage
- [ ] App Transport Security (ATS) enabled
- [ ] No ATS exceptions for PHI endpoints
- [ ] Certificate pinning for API calls
- [ ] Jailbreak detection (recommended)
- [ ] Device passcode requirement check
- [ ] Screenshot prevention in PHI views
- [ ] Secure memory handling for PHI
- [ ] No PHI in logs or crash reports
- [ ] Privacy usage descriptions in Info.plist
- [ ] PrivacyInfo.xcprivacy manifest

### Cloud Backend Requirements

- [ ] Business Associate Agreement signed
- [ ] HIPAA-eligible services only
- [ ] Server-side encryption enabled
- [ ] Customer-managed encryption keys (CMEK)
- [ ] Network isolation (VPC/VNet)
- [ ] Firewall rules: minimum necessary access
- [ ] Identity and Access Management (IAM) configured
- [ ] Audit logging enabled on all resources
- [ ] Vulnerability scanning enabled
- [ ] DDoS protection enabled
- [ ] WAF (Web Application Firewall) configured
- [ ] Backup encryption enabled
- [ ] Compliance certifications verified (HITRUST, SOC 2)

### Testing & Validation

- [ ] Security testing (SAST/DAST)
- [ ] Penetration testing completed
- [ ] Vulnerability assessments regular
- [ ] Code review for security issues
- [ ] Third-party security audit
- [ ] Compliance gap analysis
- [ ] Disaster recovery testing
- [ ] Incident response drills

### Documentation

- [ ] System security plan documented
- [ ] Data flow diagrams created
- [ ] Risk assessment documented
- [ ] Privacy impact assessment completed
- [ ] Security awareness training materials
- [ ] User access request procedures
- [ ] Incident response procedures
- [ ] Breach notification templates
- [ ] Audit log review procedures

---

## Additional Resources

### HIPAA Regulations
- [HHS HIPAA for Professionals](https://www.hhs.gov/hipaa/for-professionals/index.html)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [HIPAA Privacy Rule](https://www.hhs.gov/hipaa/for-professionals/privacy/index.html)

### Apple Resources
- [Apple HealthKit Documentation](https://developer.apple.com/documentation/healthkit)
- [Protecting the User's Privacy](https://developer.apple.com/documentation/healthkit/protecting_user_privacy)
- [App Store Review Guidelines - Health](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)

### Cloud Provider Resources
- [Azure HIPAA Compliance](https://docs.microsoft.com/azure/compliance/offerings/offering-hipaa-us)
- [Google Cloud HIPAA Compliance](https://cloud.google.com/security/compliance/hipaa)

### Security Standards
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Mobile Security](https://owasp.org/www-project-mobile-security/)
- [HITRUST CSF](https://hitrustalliance.net/hitrust-csf/)

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-21 | Healthcare Compliance Engineer | Initial comprehensive guide |

---

## Contact & Support

For questions regarding HIPAA compliance:
- **Privacy Officer**: [Contact Information]
- **Security Officer**: [Contact Information]
- **Compliance Team**: [Contact Information]

**Emergency Security Incident**: [24/7 Contact]
