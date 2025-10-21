# Backend Security Architecture Plan

Comprehensive security plan for connecting the Health Tracker iOS app with a HIPAA-compliant Azure backend.

## Table of Contents

1. [Security Requirements](#security-requirements)
2. [Authentication Strategy](#authentication-strategy)
3. [SSL Certificate Pinning](#ssl-certificate-pinning)
4. [API Security](#api-security)
5. [Secrets Management](#secrets-management)
6. [HIPAA Compliance](#hipaa-compliance)
7. [Implementation Roadmap](#implementation-roadmap)

---

## Security Requirements

### HIPAA Compliance Checklist

For HIPAA-compliant health data transmission, the following are required:

✅ **Encryption in Transit**
- TLS 1.2+ for all API communications
- Strong cipher suites (AES-256-GCM)
- Certificate validation and pinning

✅ **Encryption at Rest**
- End-to-end encryption of health data
- Secure local storage (iOS Keychain)
- Encrypted database fields on backend

✅ **Authentication & Authorization**
- Strong user authentication (OAuth 2.0 / JWT)
- Multi-factor authentication (MFA) support
- Session management with timeout
- Token refresh mechanisms

✅ **Access Controls**
- Role-based access control (RBAC)
- Audit logging of all data access
- User consent tracking

✅ **Data Integrity**
- Request/response signing
- Checksum validation
- Replay attack prevention

✅ **Secure Development**
- Code obfuscation
- Secret protection
- Regular security audits

---

## Authentication Strategy

### Recommended Approach: OAuth 2.0 + JWT

#### Why OAuth 2.0?

1. **Industry Standard** - Widely adopted, well-tested
2. **Flexible** - Supports multiple grant types
3. **Secure** - Separation of concerns (auth server vs resource server)
4. **Azure Integration** - Native Azure AD B2C support

#### Why JWT?

1. **Stateless** - No server-side session storage needed
2. **Self-contained** - Contains user claims
3. **Compact** - Efficient for mobile
4. **Secure** - Cryptographically signed

### Authentication Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. User Login (iOS App)                                     │
│    - Email/Password OR Biometric                            │
│    - Optional: MFA (TOTP, SMS)                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Azure AD B2C Authentication                              │
│    - Validates credentials                                  │
│    - Checks MFA if enabled                                  │
│    - Generates tokens                                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Token Response                                           │
│    - Access Token (JWT, short-lived: 15-60 min)            │
│    - Refresh Token (long-lived: 7-30 days)                 │
│    - ID Token (user profile)                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Store Tokens Securely (iOS Keychain)                    │
│    - Access token in memory (ephemeral)                    │
│    - Refresh token in Keychain                             │
│    - Automatic cleanup on logout                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. API Requests                                             │
│    - Add Authorization: Bearer <access_token>               │
│    - Automatic token refresh if expired                    │
│    - Retry failed requests after refresh                   │
└─────────────────────────────────────────────────────────────┘
```

### JWT Structure

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT",
    "kid": "key-id-12345"
  },
  "payload": {
    "sub": "user-123",
    "email": "user@example.com",
    "iat": 1640000000,
    "exp": 1640003600,
    "iss": "https://login.yourapp.com",
    "aud": "health-tracker-api",
    "scope": "read:health write:health"
  },
  "signature": "..."
}
```

### Token Lifecycle Management

```
Access Token Expires:
├─ Interceptor detects 401 Unauthorized
├─ Attempt refresh using refresh token
│  ├─ Success → Retry original request
│  └─ Failure → Logout user
└─ Update tokens in Keychain
```

---

## SSL Certificate Pinning

### What is Certificate Pinning?

Certificate pinning validates that the server certificate matches a known, trusted certificate, preventing man-in-the-middle (MITM) attacks even if a device's trust store is compromised.

### Types of Pinning

#### 1. Certificate Pinning
- Pins the entire certificate
- **Pros:** Most secure
- **Cons:** Must update app when certificate rotates

#### 2. Public Key Pinning (Recommended)
- Pins only the public key
- **Pros:** Survives certificate rotation if same key
- **Cons:** Slightly less secure than full cert pinning

#### 3. Certificate Authority Pinning
- Pins the CA certificate
- **Pros:** Flexible, survives cert changes
- **Cons:** Less secure if CA is compromised

### Recommended Approach: Public Key Pinning with Backup Keys

```
Primary Pin: Current public key
Backup Pin 1: Next rotation public key (Azure Key Vault)
Backup Pin 2: Emergency backup key
```

### Implementation Strategy

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Obtain Public Keys                                       │
│    - Extract from current Azure SSL certificate            │
│    - Generate backup keys in Azure Key Vault               │
│    - Convert to SHA-256 hash                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Bundle Pins in App                                       │
│    - Store in Info.plist or config file                    │
│    - Obfuscate if possible                                 │
│    - Include expiration dates                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. URLSession Delegate                                     │
│    - Implement didReceiveChallenge                         │
│    - Validate server trust                                 │
│    - Compare public key hash                               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Pin Validation                                           │
│    - Extract public key from server cert                   │
│    - Generate SHA-256 hash                                 │
│    - Compare with bundled pins                             │
│    - Allow if match found, reject otherwise                │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Fallback Strategy                                        │
│    - Try primary pin                                        │
│    - Try backup pins if primary fails                      │
│    - Log pin validation failures                           │
│    - Alert if all pins fail (potential MITM)               │
└─────────────────────────────────────────────────────────────┘
```

### Pin Rotation Strategy

```
Week 0: App released with Pin A
Week 4: Generate Pin B, store in Azure
Week 8: App update includes Pin A + Pin B
Week 12: Rotate certificate to use Key B
Week 16: App update includes Pin B + Pin C
```

### Emergency Pin Update

For critical security incidents:

1. **Remote Configuration** - Store pins in remote config (Firebase, Azure App Config)
2. **Fallback Mechanism** - Allow temporary pin bypass for emergency updates
3. **Force Update** - Require app update if pins are compromised

---

## API Security

### Request Security

#### 1. Authentication Headers

```http
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
X-Device-ID: A1B2C3D4-E5F6-G7H8-I9J0-K1L2M3N4O5P6
X-App-Version: 1.2.3
X-Platform: iOS
X-Request-ID: 550e8400-e29b-41d4-a716-446655440000
```

#### 2. Request Signing

Sign all requests to prevent tampering:

```
Signature = HMAC-SHA256(
    method + url + timestamp + body,
    secret_key
)
```

Example:
```http
POST /api/v1/health/upload
X-Timestamp: 1640000000
X-Signature: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

#### 3. Request Encryption

For sensitive health data:

```
Plain Data → AES-256-GCM Encrypt → Base64 → HTTPS
```

#### 4. Replay Attack Prevention

```http
X-Request-Nonce: 8f4e2c1a-9b7d-4f3e-a1c2-5d8e9f0b1a2c
X-Timestamp: 1640000000
```

Server validates:
- Nonce is unique (not seen before)
- Timestamp is within acceptable window (±5 minutes)

### Response Security

#### 1. Response Validation

```swift
// Validate response integrity
let receivedChecksum = response.headers["X-Checksum"]
let calculatedChecksum = SHA256.hash(data: responseData)

guard receivedChecksum == calculatedChecksum else {
    throw APIError.responseIntegrityFailed
}
```

#### 2. Encrypted Responses

For sensitive data, decrypt response:

```
HTTPS → Base64 Decode → AES-256-GCM Decrypt → JSON Parse
```

#### 3. Rate Limiting Headers

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1640003600
```

### API Versioning

```
Base URL: https://api.healthtracker.azure.com/v1
```

Benefits:
- Backward compatibility
- Gradual rollout of breaking changes
- A/B testing of new features

---

## Secrets Management

### What NOT to Do ❌

```swift
// ❌ NEVER hardcode secrets
let apiKey = "sk_live_abc123xyz789"
let clientSecret = "secret_value_here"

// ❌ NEVER commit secrets to Git
// ❌ NEVER store in UserDefaults
// ❌ NEVER log secrets
```

### Recommended Approach ✅

#### 1. Development vs Production Separation

```
Development:
├── Uses development API endpoints
├── Less strict security (for testing)
└── Separate credentials

Production:
├── Uses production Azure endpoints
├── Full security enforcement
└── Production credentials
```

#### 2. Configuration Files (Not in Git)

**Config.swift** (gitignored):
```swift
struct APIConfig {
    static let baseURL = "https://api.healthtracker.azure.com"
    static let clientID = "abc123"
    // Loaded from Keychain or environment
}
```

**.gitignore**:
```
Config.swift
*.xcconfig
Secrets/
*.plist (if contains secrets)
```

#### 3. Xcode Configuration Files (.xcconfig)

**Development.xcconfig**:
```
API_BASE_URL = https:/$()/dev.api.healthtracker.azure.com
OAUTH_CLIENT_ID = dev-client-id
```

**Production.xcconfig**:
```
API_BASE_URL = https:/$()/api.healthtracker.azure.com
OAUTH_CLIENT_ID = prod-client-id
```

Access in code:
```swift
let baseURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
```

#### 4. iOS Keychain

Store sensitive tokens:

```swift
import Security

class KeychainService {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }
}
```

#### 5. Azure Key Vault Integration

For production apps, fetch secrets from Azure Key Vault:

```swift
// On first launch or token expiration
let azureKeyVault = AzureKeyVaultClient()
let apiKey = try await azureKeyVault.getSecret(name: "health-api-key")

// Store in Keychain for offline use
KeychainService.save(key: "api_key", value: apiKey)
```

#### 6. Environment Variables (CI/CD)

In Azure DevOps pipeline:

```yaml
variables:
  - group: health-tracker-secrets

steps:
  - task: Xcode@5
    env:
      API_BASE_URL: $(PROD_API_URL)
      OAUTH_CLIENT_ID: $(PROD_CLIENT_ID)
      OAUTH_CLIENT_SECRET: $(PROD_CLIENT_SECRET)
```

#### 7. Code Obfuscation

Use Swift Package Manager or CocoaPods for obfuscation:

```swift
// Use string obfuscation for sensitive values
let obfuscated = "QlBJX0tFWV9IRVJFCg==".base64Decoded()
```

Better: Don't store secrets in code at all!

---

## HIPAA Compliance

### Required Security Controls

#### 1. Audit Logging

Log all API requests:

```swift
struct AuditLog: Codable {
    let userId: String
    let action: String  // "data_access", "data_upload", "permission_change"
    let resource: String
    let timestamp: Date
    let ipAddress: String?
    let deviceId: String
    let result: String  // "success", "failure"
}
```

#### 2. User Consent Tracking

```swift
struct UserConsent: Codable {
    let userId: String
    let consentType: String  // "data_collection", "data_sharing"
    let consentGiven: Bool
    let timestamp: Date
    let version: String  // Privacy policy version
}
```

#### 3. Data Minimization

Only transmit necessary data:

```swift
// ✅ Good: Only send required fields
struct HealthDataUpload {
    let heartRate: Double
    let timestamp: Date
}

// ❌ Bad: Sending unnecessary data
struct HealthDataUpload {
    let heartRate: Double
    let timestamp: Date
    let deviceModel: String  // Not needed
    let osVersion: String    // Not needed
    let location: CLLocation // Definitely not needed!
}
```

#### 4. Secure Deletion

```swift
func deleteUserData(userId: String) async throws {
    // 1. Delete from backend (Azure)
    try await apiClient.deleteUser(userId: userId)

    // 2. Delete local cache
    await cacheService.clearAllCache()

    // 3. Delete tokens
    KeychainService.delete(key: "access_token")
    KeychainService.delete(key: "refresh_token")

    // 4. Clear UserDefaults
    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)

    // 5. Notify user
    print("All data securely deleted")
}
```

#### 5. Encryption Requirements

```
┌─────────────────────────────────────────────┐
│ iOS App (End-to-End Encryption)            │
│  - AES-256-GCM encryption                   │
│  - Keys stored in Keychain                  │
└────────────────┬────────────────────────────┘
                 │
                 │ HTTPS (TLS 1.2+)
                 │
┌────────────────▼────────────────────────────┐
│ Azure API Gateway                           │
│  - SSL/TLS termination                      │
│  - Certificate validation                   │
└────────────────┬────────────────────────────┘
                 │
                 │ Encrypted at Rest
                 │
┌────────────────▼────────────────────────────┐
│ Azure SQL Database                          │
│  - Transparent Data Encryption (TDE)        │
│  - Always Encrypted columns                 │
└─────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

- [ ] Set up Azure AD B2C tenant
- [ ] Configure OAuth 2.0 flows
- [ ] Implement JWT authentication manager
- [ ] Create Keychain wrapper
- [ ] Set up development vs production configs

### Phase 2: Security Hardening (Week 3-4)

- [ ] Implement SSL certificate pinning
- [ ] Add request/response signing
- [ ] Implement replay attack prevention
- [ ] Add rate limiting handling
- [ ] Create secure logging system

### Phase 3: API Integration (Week 5-6)

- [ ] Enhance API client with authentication
- [ ] Implement automatic token refresh
- [ ] Add retry logic with exponential backoff
- [ ] Create error handling framework
- [ ] Implement offline queue

### Phase 4: HIPAA Compliance (Week 7-8)

- [ ] Implement audit logging
- [ ] Add user consent tracking
- [ ] Create secure data deletion
- [ ] Add encryption at rest
- [ ] Implement data minimization

### Phase 5: Testing & Hardening (Week 9-10)

- [ ] Security testing (penetration testing)
- [ ] Code obfuscation
- [ ] Secrets audit
- [ ] Performance testing
- [ ] HIPAA compliance audit

---

## Next Steps

1. **Review Azure AD B2C Setup** - Ensure OAuth 2.0 is configured
2. **Obtain SSL Certificates** - Get production certificates from Azure
3. **Extract Public Keys** - For certificate pinning
4. **Set Up Azure Key Vault** - For secret management
5. **Implement Code** - Start with authentication manager

See implementation files:
- `AuthenticationManager.swift` - JWT token management
- `SSLPinningManager.swift` - Certificate pinning
- `SecureAPIClient.swift` - Enhanced API client
- `SecretsManager.swift` - Configuration and secrets

---

## Security Checklist

Before going to production:

- [ ] All secrets removed from code
- [ ] SSL pinning implemented and tested
- [ ] Token refresh working correctly
- [ ] Audit logging in place
- [ ] HIPAA compliance verified
- [ ] Penetration testing completed
- [ ] Code obfuscation applied
- [ ] Emergency update mechanism tested
- [ ] Incident response plan documented
- [ ] Security training completed

---

## Contact

For security concerns or questions:
- Security Team: security@healthtracker.com
- HIPAA Compliance: hipaa@healthtracker.com
- Emergency: Use Azure Security Center alerts
