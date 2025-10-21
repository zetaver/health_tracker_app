# HIPAA Compliance & Security Checklist

This checklist ensures your Health Tracker iOS app meets HIPAA technical safeguards and security best practices.

---

## 1. HIPAA Technical Safeguards Overview

HIPAA requires three categories of technical safeguards:

1. **Access Control** - Limit PHI access to authorized users
2. **Audit Controls** - Log all PHI access and modifications
3. **Integrity Controls** - Ensure PHI is not altered or destroyed
4. **Transmission Security** - Protect PHI during transmission

---

## 2. Access Control Implementation

### 2.1 User Authentication

- [ ] **Biometric Authentication Required**
  - Implement Face ID / Touch ID using LocalAuthentication framework
  - Fallback to device passcode
  - Re-authenticate after 15 minutes of inactivity

```swift
// Required implementation
func authenticateUser() async throws -> Bool {
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
        throw AuthError.biometricNotAvailable
    }

    return try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: "Authenticate to access your health data"
    )
}
```

- [ ] **OAuth 2.0 + PKCE for Backend**
  - Use Authorization Code flow with PKCE
  - Never store passwords locally
  - Implement token refresh mechanism
  - Auto-logout after token expiration

- [ ] **Session Management**
  - Maximum session timeout: 15 minutes
  - Clear sensitive data from memory on logout
  - Invalidate tokens on server-side logout

### 2.2 Role-Based Access Control (if multi-user)

- [ ] Implement user roles (patient, provider, admin)
- [ ] Restrict data access based on role
- [ ] Log role-based access attempts

---

## 3. Audit Controls (Logging)

### 3.1 Required Audit Events

- [ ] **Log all PHI access**
  ```swift
  struct AuditLog {
      let userId: String          // Hashed
      let timestamp: Date
      let action: AuditAction     // .read, .write, .delete, .export
      let dataType: HealthMetricType
      let recordId: UUID?
      let ipAddress: String?
      let deviceId: String
      let success: Bool
      let failureReason: String?
  }
  ```

- [ ] **Log authentication events**
  - Successful logins
  - Failed login attempts
  - Logout events
  - Password/PIN changes

- [ ] **Log data modifications**
  - Create, update, delete operations
  - Export/share operations
  - Sync events

### 3.2 Audit Log Storage

- [ ] Encrypt audit logs using CryptoKit
- [ ] Store locally in separate CoreData entity
- [ ] Sync to backend every 24 hours
- [ ] Retain logs for minimum 6 years (HIPAA requirement)
- [ ] Implement tamper-proof mechanism (hash chain)

```swift
// Hash chain for tamper detection
struct AuditLogEntry {
    let id: UUID
    let timestamp: Date
    let event: AuditEvent
    let previousHash: String
    let currentHash: String  // SHA-256 of (previousHash + event data)
}
```

---

## 4. Integrity Controls

### 4.1 Data Validation

- [ ] **Input Validation**
  - Validate all user inputs (type, range, format)
  - Sanitize data before storage
  - Prevent SQL injection (CoreData protected, but validate anyway)

- [ ] **Data Integrity Checks**
  - Use checksums for critical data
  - Implement version control for records
  - Detect and prevent unauthorized modifications

```swift
// Example: Hash verification
func verifyIntegrity(data: HealthMetric, storedHash: String) -> Bool {
    let computedHash = SHA256.hash(data: data.toData())
    return computedHash.compactMap { String(format: "%02x", $0) }.joined() == storedHash
}
```

### 4.2 Backup and Recovery

- [ ] Enable iCloud Keychain for credential backup
- [ ] DO NOT backup PHI to iCloud (exclude from backup)
- [ ] Implement data export for user-initiated backups
- [ ] Test restore procedures

```swift
// Exclude CoreData files from iCloud backup
func excludeFromBackup(url: URL) throws {
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var url = url
    try url.setResourceValues(resourceValues)
}
```

---

## 5. Transmission Security

### 5.1 TLS Configuration

- [ ] **Use TLS 1.3 (minimum TLS 1.2)**
  ```swift
  let config = URLSessionConfiguration.default
  config.tlsMinimumSupportedProtocolVersion = .TLSv13
  ```

- [ ] **Certificate Pinning (MANDATORY)**
  ```swift
  class CertificatePinningDelegate: NSObject, URLSessionDelegate {
      func urlSession(
          _ session: URLSession,
          didReceive challenge: URLAuthenticationChallenge,
          completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
      ) {
          guard let serverTrust = challenge.protectionSpace.serverTrust else {
              completionHandler(.cancelAuthenticationChallenge, nil)
              return
          }

          // Verify certificate
          let credential = URLCredential(trust: serverTrust)
          completionHandler(.useCredential, credential)
      }
  }
  ```

- [ ] **Perfect Forward Secrecy (PFS)**
  - Verify server supports PFS cipher suites
  - Use ephemeral key exchange (DHE/ECDHE)

### 5.2 Data Encryption in Transit

- [ ] All API requests use HTTPS
- [ ] No PHI in URL parameters (use POST body)
- [ ] Encrypt request/response payloads (optional additional layer)
- [ ] Implement request signing for integrity

---

## 6. Encryption at Rest

### 6.1 Local Storage Encryption

- [ ] **CoreData Encryption**
  - Enable SQLite encryption
  - Use `NSPersistentStoreFileProtectionKey`
  - Set to `.complete` file protection

```swift
description?.setOption(
    FileProtectionType.complete as NSObject,
    forKey: NSPersistentStoreFileProtectionKey
)
```

- [ ] **Field-Level Encryption (CryptoKit)**
  - Encrypt all PHI fields individually
  - Use AES-256-GCM
  - Store encryption keys in Keychain

```swift
// Example: Encrypt sensitive field
let sensitiveData = "Blood Pressure: 120/80"
let key = SymmetricKey(size: .bits256)
let sealedBox = try AES.GCM.seal(sensitiveData.data(using: .utf8)!, using: key)
```

- [ ] **Keychain Storage**
  - Store all credentials in Keychain
  - Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - Enable Data Protection on keychain items

### 6.2 Key Management

- [ ] Store encryption keys in Keychain (NOT in code/UserDefaults)
- [ ] Use Secure Enclave when available
- [ ] Implement key rotation policy (every 90 days)
- [ ] Securely delete old keys after rotation

```swift
// Check for Secure Enclave availability
if SecureEnclave.isAvailable {
    let key = try SecureEnclave.P256.KeyAgreement.PrivateKey()
}
```

---

## 7. Data Minimization

### 7.1 Only Collect Necessary Data

- [ ] Request only required HealthKit permissions
- [ ] Do NOT collect identifiable information unless necessary
- [ ] Implement data retention policy (delete after X days)
- [ ] Provide user control over data collection

### 7.2 De-identification

- [ ] Hash user IDs before logging
- [ ] Remove direct identifiers from analytics
- [ ] Use pseudonymization for research data

```swift
// Hash user ID for audit logs
func hashUserId(_ userId: String) -> String {
    let data = userId.data(using: .utf8)!
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

---

## 8. Application Security

### 8.1 Secure Coding Practices

- [ ] **Prevent Screenshot Capture (PHI Screens)**
  ```swift
  // Add to PHI-displaying views
  .onAppear {
      UIApplication.shared.isIdleTimerDisabled = false
      // Optionally blur on screenshot
  }
  ```

- [ ] **Disable Copy/Paste for PHI Fields**
  ```swift
  TextField("Blood Pressure", text: $value)
      .textContentType(.none)
      .autocorrectionDisabled()
  ```

- [ ] **Clear Memory on Background**
  ```swift
  NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
      .sink { _ in
          // Clear sensitive data
          viewModel.clearSensitiveData()
      }
  ```

- [ ] **Jailbreak Detection**
  ```swift
  func isJailbroken() -> Bool {
      #if targetEnvironment(simulator)
      return false
      #else
      let paths = ["/Applications/Cydia.app", "/usr/sbin/sshd", "/bin/bash"]
      return paths.contains { FileManager.default.fileExists(atPath: $0) }
      #endif
  }
  ```

### 8.2 Third-Party Dependencies

- [ ] Minimize third-party libraries
- [ ] Audit all dependencies for security vulnerabilities
- [ ] Use Swift Package Manager (better security than CocoaPods)
- [ ] Keep dependencies updated
- [ ] Avoid libraries with telemetry/analytics

---

## 9. HealthKit-Specific Security

### 9.1 Permission Handling

- [ ] Request minimum necessary permissions
- [ ] Explain why each permission is needed (NSHealthShareUsageDescription)
- [ ] Handle permission denial gracefully
- [ ] Re-request permissions only when necessary

```swift
// Info.plist
<key>NSHealthShareUsageDescription</key>
<string>We need access to your heart rate to track your cardiovascular health and provide personalized insights.</string>
```

### 9.2 HealthKit Data Handling

- [ ] Never share HealthKit data without explicit user consent
- [ ] Do not use HealthKit data for advertising
- [ ] Comply with Apple's App Store guidelines for health apps
- [ ] Provide opt-out mechanism

---

## 10. Backend Integration Security

### 10.1 API Security

- [ ] **Authentication**
  - Use OAuth 2.0 / JWT tokens
  - Include token in Authorization header (NOT query params)
  - Implement token refresh flow
  - Validate tokens on every request

- [ ] **Authorization**
  - Implement server-side access control
  - Verify user has permission to access requested data
  - Use resource-based permissions

- [ ] **Rate Limiting**
  - Implement client-side rate limiting
  - Handle 429 (Too Many Requests) responses
  - Exponential backoff for retries

### 10.2 Data Transmission Best Practices

- [ ] Compress large payloads (gzip)
- [ ] Batch requests to reduce network calls
- [ ] Implement request idempotency
- [ ] Handle offline scenarios gracefully

```swift
// Example: Idempotent request
struct APIRequest {
    let idempotencyKey: UUID  // Client-generated
    let payload: HealthMetric
}
```

---

## 11. Privacy Compliance

### 11.1 User Consent

- [ ] Obtain explicit consent before collecting PHI
- [ ] Provide clear privacy policy
- [ ] Allow users to withdraw consent
- [ ] Implement data deletion requests (GDPR "Right to be Forgotten")

### 11.2 Privacy Policy Requirements

Must include:
- [ ] What data is collected
- [ ] How data is used
- [ ] How data is stored and protected
- [ ] Third parties with data access
- [ ] User rights (access, correction, deletion)
- [ ] Data retention policy
- [ ] Contact information for privacy concerns

---

## 12. Testing & Validation

### 12.1 Security Testing

- [ ] **Penetration Testing**
  - Test authentication bypass
  - Test encryption strength
  - Test certificate pinning
  - Test for data leakage

- [ ] **Static Code Analysis**
  - Use Xcode's built-in analyzer
  - Check for hardcoded secrets
  - Validate input sanitization

- [ ] **Dynamic Analysis**
  - Monitor network traffic (Charles Proxy)
  - Verify TLS version and cipher suites
  - Check for unencrypted data transmission

### 12.2 HIPAA-Specific Tests

- [ ] Verify all PHI is encrypted at rest
- [ ] Verify all PHI transmission is encrypted
- [ ] Test audit logging for all data access
- [ ] Verify session timeout enforcement
- [ ] Test user authentication flows
- [ ] Verify data integrity checks

---

## 13. Incident Response Plan

### 13.1 Data Breach Procedures

- [ ] Document incident response plan
- [ ] Identify security team contacts
- [ ] Establish breach notification timeline (60 days under HIPAA)
- [ ] Prepare breach notification templates

### 13.2 Monitoring

- [ ] Monitor for unusual access patterns
- [ ] Alert on multiple failed login attempts
- [ ] Track data export operations
- [ ] Log all security-related events

---

## 14. App Store Compliance

### 14.1 Apple Requirements

- [ ] Declare health data usage in App Privacy section
- [ ] Mark app as "Medical" category (if applicable)
- [ ] Provide privacy policy URL
- [ ] Obtain necessary certifications (FDA approval if medical device)

### 14.2 App Review Preparation

- [ ] Test app thoroughly on physical devices
- [ ] Prepare demo account for reviewers
- [ ] Document HealthKit usage justification
- [ ] Prepare compliance documentation

---

## 15. Pre-Launch Security Checklist

### Critical Items (MUST-HAVE)

- [ ] All PHI encrypted at rest (AES-256)
- [ ] All network traffic uses HTTPS with TLS 1.3
- [ ] Certificate pinning implemented
- [ ] Biometric authentication enabled
- [ ] Session timeout (15 min) enforced
- [ ] Audit logging implemented
- [ ] Keychain used for credentials
- [ ] No hardcoded secrets in code
- [ ] Data retention policy implemented
- [ ] Privacy policy published

### Recommended Items

- [ ] Jailbreak detection
- [ ] Screenshot prevention for PHI screens
- [ ] Secure Enclave usage (when available)
- [ ] Offline data queuing
- [ ] Data integrity checks (checksums)
- [ ] Multi-factor authentication (optional)

---

## 16. Ongoing Compliance

### Monthly

- [ ] Review audit logs
- [ ] Check for security updates (iOS, dependencies)
- [ ] Monitor for unusual activity

### Quarterly

- [ ] Security audit
- [ ] Review access logs
- [ ] Update dependencies
- [ ] Test incident response procedures

### Annually

- [ ] HIPAA compliance review
- [ ] Penetration testing
- [ ] Update privacy policy
- [ ] Review and rotate encryption keys
- [ ] Staff security training

---

## 17. Resources & Documentation

### HIPAA Resources
- HHS HIPAA Security Rule: https://www.hhs.gov/hipaa/for-professionals/security/
- HIPAA Breach Notification Rule: https://www.hhs.gov/hipaa/for-professionals/breach-notification/

### Apple Resources
- HealthKit Documentation: https://developer.apple.com/healthkit/
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Security Best Practices: https://developer.apple.com/security/

### Frameworks
- CryptoKit: https://developer.apple.com/documentation/cryptokit
- LocalAuthentication: https://developer.apple.com/documentation/localauthentication

---

## 18. Sign-Off

Before production release:

- [ ] Security team approval
- [ ] Legal team review (HIPAA compliance)
- [ ] Privacy officer sign-off
- [ ] QA testing complete
- [ ] Penetration test passed
- [ ] Documentation complete

---

**IMPORTANT**: This checklist is a guide. Consult with HIPAA compliance experts and legal counsel to ensure full regulatory compliance for your specific use case.

**Last Updated**: 2025-10-21
**Version**: 1.0
