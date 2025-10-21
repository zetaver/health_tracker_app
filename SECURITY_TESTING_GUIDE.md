# Security Testing Guide

Comprehensive security testing and validation for HIPAA-compliant health data application.

## Table of Contents

1. [Security Testing Tools](#security-testing-tools)
2. [OWASP MASVS Testing](#owasp-masvs-testing)
3. [Network Security Testing](#network-security-testing)
4. [Penetration Testing](#penetration-testing)
5. [Automated Security Scanning](#automated-security-scanning)
6. [Manual Security Testing](#manual-security-testing)

---

## Security Testing Tools

### Required Tools

| Tool | Purpose | Cost | Priority |
|------|---------|------|----------|
| **OWASP ZAP** | Security scanning | Free | ✅ Critical |
| **Burp Suite** | Penetration testing | Free/Paid | ✅ Critical |
| **Charles Proxy** | Network inspection | $50 | ✅ Critical |
| **Hopper Disassembler** | Binary analysis | $99 | Recommended |
| **class-dump** | Extract class info | Free | Recommended |
| **Frida** | Dynamic analysis | Free | Recommended |
| **MobSF** | Mobile security framework | Free | ✅ Critical |
| **iMazing** | Device inspection | $45 | Recommended |

### Tool Installation

#### OWASP ZAP
```bash
# macOS
brew install --cask owasp-zap

# Or download from https://www.zaproxy.org/download/
```

#### Burp Suite Community Edition
```bash
# Download from https://portswigger.net/burp/communitydownload
```

#### Charles Proxy
```bash
# Download from https://www.charlesproxy.com/download/
# Install SSL certificate on iOS device
```

#### MobSF
```bash
# Using Docker
docker pull opensecurity/mobile-security-framework-mobsf
docker run -it -p 8000:8000 opensecurity/mobile-security-framework-mobsf:latest
```

---

## OWASP MASVS Testing

### MASVS Compliance Checklist

The Mobile Application Security Verification Standard (MASVS) defines security requirements for mobile apps.

#### MASVS-STORAGE (Data Storage and Privacy)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-STORAGE-1** | App securely stores sensitive data | ✅ | Keychain for tokens, encrypted DB |
| **MASVS-STORAGE-2** | App prevents sensitive data leakage | ✅ | No logging of PHI, secure deletion |

**Test Cases:**

1. **Keychain Security**
```bash
# Test 1: Verify sensitive data is in Keychain, not UserDefaults
# Install app and authenticate
# Then inspect device

# Check UserDefaults
defaults read com.health.tracker

# Should NOT contain tokens or PHI
# Expected: No sensitive data found
```

2. **Secure Deletion**
```swift
// Test that logout clears all data
func test_logout_clearsAllSensitiveData() async {
    // 1. Login and store data
    try? await authManager.login()

    // 2. Logout
    await authManager.logout()

    // 3. Verify Keychain cleared
    XCTAssertNil(KeychainService().retrieve(key: "access_token"))
    XCTAssertNil(KeychainService().retrieve(key: "refresh_token"))

    // 4. Verify UserDefaults cleared
    let defaults = UserDefaults.standard
    XCTAssertNil(defaults.string(forKey: "user_id"))
}
```

#### MASVS-CRYPTO (Cryptography)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-CRYPTO-1** | App uses strong, up-to-date crypto | ✅ | AES-256-GCM, SHA-256 |
| **MASVS-CRYPTO-2** | App uses crypto according to best practices | ✅ | Random IVs, proper key management |

**Test Cases:**

1. **Encryption Strength**
```swift
func test_encryption_usesAES256GCM() {
    let apiClient = SecureAPIClient(authenticationManager: mockAuth)
    let plainData = "sensitive data".data(using: .utf8)!

    let (encrypted, metadata) = try! apiClient.encryptData(plainData)

    // Verify algorithm
    XCTAssertEqual(metadata?.algorithm, "AES-256-GCM")

    // Verify IV is random
    let (encrypted2, metadata2) = try! apiClient.encryptData(plainData)
    XCTAssertNotEqual(metadata?.iv, metadata2?.iv)
}
```

2. **Key Management**
```bash
# Verify encryption keys are in Keychain
# Use Keychain dumper tool (requires jailbroken device for testing)

# Expected: Keys stored with kSecAttrAccessibleAfterFirstUnlock
```

#### MASVS-AUTH (Authentication and Session Management)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-AUTH-1** | App uses secure authentication | ✅ | OAuth 2.0 + JWT |
| **MASVS-AUTH-2** | App performs authorization checks | ✅ | Token validation |
| **MASVS-AUTH-3** | App implements proper session management | ✅ | Token expiration, refresh |

**Test Cases:**

1. **Token Expiration**
```swift
func test_expiredToken_triggersRefresh() async throws {
    // Setup expired token
    try await setupExpiredTokenState()

    // Make API call
    let response = try await apiClient.getUserProfile(userId: "test")

    // Verify token was refreshed
    XCTAssertTrue(mockAuth.refreshCalled)
    XCTAssertNotNil(response)
}
```

2. **Session Timeout**
```swift
func test_sessionTimeout_logsOutUser() async {
    // Setup authenticated state
    try? await authManager.login()

    // Wait for session timeout (or mock it)
    await Task.sleep(nanoseconds: sessionTimeoutNanos)

    // Attempt API call
    await XCTAssertThrowsError(
        try await apiClient.getUserProfile(userId: "test")
    ) { error in
        XCTAssertEqual(error as? AuthenticationError, .notAuthenticated)
    }
}
```

#### MASVS-NETWORK (Network Communication)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-NETWORK-1** | App secures data in transit | ✅ | TLS 1.2+, certificate pinning |
| **MASVS-NETWORK-2** | App performs X.509 certificate validation | ✅ | SSL pinning manager |

**Test Cases:**

1. **TLS Version**
```bash
# Use nmap to verify TLS version
nmap --script ssl-enum-ciphers -p 443 api.healthtracker.azure.com

# Expected: Only TLS 1.2 and 1.3 allowed
```

2. **Certificate Pinning**
```swift
func test_certificatePinning_rejectsInvalidCert() async {
    let invalidConfig = SSLPinningManager.PinConfiguration(
        pins: ["wrong_pin"],
        backupPins: [],
        pinningMode: .publicKeyHash,
        allowExpiredCertificates: false,
        validateCertificateChain: true
    )

    let pinningManager = SSLPinningManager(configuration: invalidConfig)

    // Attempt connection
    let result = pinningManager.validateServerTrust(mockTrust, forHost: "api.test.com")

    // Should fail
    XCTAssertFalse(result)
}
```

#### MASVS-PLATFORM (Platform Interaction)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-PLATFORM-1** | App uses IPC mechanisms securely | ✅ | HealthKit permissions |
| **MASVS-PLATFORM-2** | App uses WebViews securely | N/A | No WebViews used |
| **MASVS-PLATFORM-3** | App uses UI components securely | ✅ | No sensitive data in screenshots |

**Test Cases:**

1. **Screenshot Protection**
```swift
func test_sensitiveScreens_hideInAppSwitcher() {
    // When showing sensitive data
    NotificationCenter.default.post(
        name: UIApplication.userDidTakeScreenshotNotification,
        object: nil
    )

    // Verify sensitive data is hidden
    // (Manual test: take screenshot and verify)
}
```

#### MASVS-CODE (Code Quality)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-CODE-1** | App is signed and provisioned properly | ✅ | Valid certificates |
| **MASVS-CODE-2** | App has been built in release mode | ✅ | Optimizations enabled |
| **MASVS-CODE-3** | Debugging symbols removed | ✅ | Stripped in release |
| **MASVS-CODE-4** | App doesn't export unnecessary functionality | ✅ | Minimal exported symbols |

**Test Cases:**

1. **Debug Symbols**
```bash
# Check if debug symbols are stripped
nm -a Health\ Tracker\ App.app/Health\ Tracker\ App | grep -i debug

# Expected: No output (symbols stripped)
```

2. **Code Signing**
```bash
# Verify code signature
codesign -dvvv Health\ Tracker\ App.app

# Expected:
# Signature=valid
# CodeDirectory v=...
# Sealed Resources=...
```

#### MASVS-RESILIENCE (Resilience Against Reverse Engineering)

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| **MASVS-RESILIENCE-1** | App validates integrity | ✅ | Code signing |
| **MASVS-RESILIENCE-2** | App prevents debugging | ⚠️ | Standard protections |
| **MASVS-RESILIENCE-3** | App is obfuscated | ⚠️ | Swift name mangling |

**Test Cases:**

1. **Jailbreak Detection** (Optional for health apps)
```swift
func test_jailbreakDetection() {
    let isJailbroken = JailbreakDetector.isJailbroken()

    // Log warning if jailbroken
    if isJailbroken {
        print("⚠️ WARNING: Device appears to be jailbroken")
    }
}
```

---

## Network Security Testing

### Using Charles Proxy

#### Setup

1. **Install Charles Certificate on iOS Device**

```bash
# 1. Start Charles Proxy
# 2. On iOS device, go to: chls.pro/ssl
# 3. Install profile
# 4. Settings → General → About → Certificate Trust Settings
# 5. Enable full trust for Charles Proxy
```

2. **Configure iOS Device to Use Proxy**

```
Settings → Wi-Fi → [Your Network] → HTTP Proxy
- Server: [Your Mac IP]
- Port: 8888
```

#### Test Cases

1. **Verify HTTPS is Used**
```
# In Charles:
# 1. Launch app and make API calls
# 2. Check Structure tab
# 3. All health data endpoints should use HTTPS

# Expected: No HTTP calls for sensitive data
```

2. **Verify Certificate Pinning**
```
# In Charles:
# 1. Enable SSL Proxying for api.healthtracker.azure.com
# 2. Try to view decrypted traffic

# Expected:
# - App should reject connection
# - Charles shows "Client SSL handshake failed"
```

3. **Inspect Request Headers**
```
# Verify security headers are present:
Authorization: Bearer [token]
X-Device-ID: [uuid]
X-Request-ID: [uuid]
X-Timestamp: [unix_timestamp]
X-Signature: [hmac_signature]
```

4. **Verify Encryption**
```
# Even with Charles MITM, health data should be encrypted
# Look for encrypted payloads in request body
# Expected: Base64-encoded encrypted data
```

### Using OWASP ZAP

#### Passive Scanning

```bash
# 1. Start ZAP in daemon mode
zap.sh -daemon -port 8080 -config api.key=changeMe

# 2. Configure iOS device proxy to ZAP

# 3. Use app normally

# 4. Generate report
curl "http://localhost:8080/JSON/core/view/alerts/?zapapiformat=JSON&apikey=changeMe" \
  | jq '.' > zap_passive_scan.json
```

**Expected Results:**
- No medium/high risk alerts for authentication endpoints
- No sensitive data in URLs
- Proper Content-Type headers
- Secure cookies (if used)

#### Active Scanning

```bash
# 1. Spider the API
curl "http://localhost:8080/JSON/spider/action/scan/?url=https://api.healthtracker.azure.com&apikey=changeMe"

# 2. Run active scan
curl "http://localhost:8080/JSON/ascan/action/scan/?url=https://api.healthtracker.azure.com&apikey=changeMe"

# 3. Get results
curl "http://localhost:8080/JSON/core/view/alerts/?zapapiformat=JSON&apikey=changeMe"
```

**Common Vulnerabilities to Check:**
- SQL Injection
- Cross-Site Scripting (XSS)
- Cross-Site Request Forgery (CSRF)
- Insecure Direct Object References
- Security Misconfiguration

---

## Penetration Testing

### Burp Suite Testing

#### Setup

1. **Configure Burp as Proxy**
```
Proxy → Options → Proxy Listeners
Add: Port 8080, All interfaces
```

2. **Install Burp CA Certificate on iOS**
```
# 1. Go to: http://burp
# 2. Download CA certificate
# 3. Install profile on iOS
# 4. Trust certificate in Settings
```

#### Test Cases

1. **Authentication Testing**

```
# Test 1: Brute Force Protection
POST /oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=password&username=test@example.com&password=wrong1
grant_type=password&username=test@example.com&password=wrong2
grant_type=password&username=test@example.com&password=wrong3
...

# Expected: Rate limiting after 5 failed attempts
```

2. **Token Manipulation**

```
# Test 2: JWT Token Tampering
# 1. Capture valid JWT token
# 2. Decode payload
# 3. Modify claims (e.g., change user_id)
# 4. Re-encode (without signature)
# 5. Send modified token

# Expected: 401 Unauthorized (signature verification fails)
```

3. **Replay Attack Prevention**

```
# Test 3: Request Replay
# 1. Capture valid request with nonce
# 2. Replay same request with same nonce

# Expected: 400 Bad Request (nonce already used)
```

4. **SQL Injection Testing**

```
# Test 4: SQL Injection in Query Parameters
GET /api/v1/user/test' OR '1'='1/profile

# Expected: 400 Bad Request or proper escaping
```

### Frida Dynamic Analysis

#### Setup
```bash
# Install Frida
pip3 install frida-tools

# Install Frida on iOS device (requires jailbreak for testing)
# Or use Frida on simulator
```

#### Test Cases

1. **Keychain Inspection**

```javascript
// frida_script.js
// Hook Keychain operations
var SecItemAdd = new NativeFunction(
    Module.findExportByName(null, 'SecItemAdd'),
    'int',
    ['pointer', 'pointer']
);

Interceptor.replace(SecItemAdd, new NativeCallback(function(attributes, result) {
    console.log('[+] SecItemAdd called');
    var dict = new ObjC.Object(attributes);
    console.log('Attributes:', dict.toString());
    return SecItemAdd(attributes, result);
}, 'int', ['pointer', 'pointer']));
```

```bash
# Run Frida
frida -U -f com.health.tracker -l frida_script.js --no-pause
```

2. **Network Traffic Interception**

```javascript
// Hook URLSession
var NSURLSession = ObjC.classes.NSURLSession;
var dataTaskWithRequest = NSURLSession['- dataTaskWithRequest:completionHandler:'];

Interceptor.attach(dataTaskWithRequest.implementation, {
    onEnter: function(args) {
        var request = new ObjC.Object(args[2]);
        console.log('[+] Request URL:', request.URL().toString());
        console.log('[+] Headers:', request.allHTTPHeaderFields().toString());
    }
});
```

---

## Automated Security Scanning

### MobSF Scanning

#### Setup & Scan

```bash
# 1. Start MobSF
docker run -it -p 8000:8000 opensecurity/mobile-security-framework-mobsf

# 2. Build IPA
xcodebuild -workspace "Health Tracker App.xcworkspace" \
  -scheme "Health Tracker App" \
  -configuration Release \
  -archivePath build/Health\ Tracker\ App.xcarchive \
  archive

# 3. Export IPA
xcodebuild -exportArchive \
  -archivePath build/Health\ Tracker\ App.xcarchive \
  -exportPath build \
  -exportOptionsPlist ExportOptions.plist

# 4. Upload to MobSF at http://localhost:8000
```

#### Review Findings

**Critical Issues to Address:**
- [ ] Insecure data storage
- [ ] Weak cryptography
- [ ] Insecure communication
- [ ] Code tampering
- [ ] Reverse engineering

**Expected Results:**
- No critical or high severity issues
- Medium/low issues acceptable with justification
- Security score >75/100

### Static Analysis with SonarQube

```bash
# Setup SonarQube
docker run -d --name sonarqube -p 9000:9000 sonarqube:latest

# Run analysis
sonar-scanner \
  -Dsonar.projectKey=health-tracker \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.login=admin
```

**Security Rules to Check:**
- Hardcoded credentials
- Weak crypto algorithms
- SQL injection vulnerabilities
- XSS vulnerabilities
- Insecure random number generation

---

## Manual Security Testing

### Checklist

#### Data Storage

- [ ] No sensitive data in UserDefaults
- [ ] All tokens in Keychain with proper access control
- [ ] No PHI in logs
- [ ] Cache files encrypted or non-existent
- [ ] Secure deletion implemented
- [ ] No data in app screenshots (app switcher)

#### Network Communication

- [ ] TLS 1.2+ enforced
- [ ] Certificate pinning working
- [ ] No HTTP connections for sensitive data
- [ ] Request signing verified
- [ ] Encryption working end-to-end
- [ ] Replay attack prevention tested

#### Authentication

- [ ] Password requirements enforced
- [ ] Rate limiting on login attempts
- [ ] Token expiration working
- [ ] Auto-refresh before expiration
- [ ] Secure logout (clears all data)
- [ ] Session timeout implemented

#### Authorization

- [ ] Token validation on every request
- [ ] Proper error handling (401 triggers re-auth)
- [ ] No privilege escalation possible
- [ ] RBAC enforced (if applicable)

#### Input Validation

- [ ] All user inputs validated
- [ ] SQL injection prevented
- [ ] XSS prevented
- [ ] Path traversal prevented
- [ ] Buffer overflow prevented

---

## Security Test Report Template

### Executive Summary

- **App Name:** Health Tracker App
- **Version:** 1.0
- **Test Date:** [Date]
- **Tester:** [Name]
- **Overall Security Rating:** [Score]/100

### Findings Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0 | ✅ |
| High | 0 | ✅ |
| Medium | 2 | ⚠️ |
| Low | 5 | ℹ️ |

### Detailed Findings

#### Finding 1: [Title]

- **Severity:** Medium
- **Category:** MASVS-STORAGE
- **Description:** [Description]
- **Steps to Reproduce:** [Steps]
- **Recommendation:** [Fix]
- **Status:** Open/Fixed

### Compliance Status

- [x] OWASP MASVS Level 1
- [x] HIPAA Security Rule
- [x] Apple App Store Guidelines
- [ ] OWASP MASVS Level 2 (Optional)

---

## Next Steps

1. Fix all critical and high severity findings
2. Document medium/low findings with justification
3. Re-test after fixes
4. Generate final security report
5. Proceed with HIPAA compliance testing

See [HIPAA_COMPLIANCE_TESTING.md](HIPAA_COMPLIANCE_TESTING.md) for HIPAA-specific tests.
