# HealthKit Integration Configuration Guide

This guide provides step-by-step instructions for configuring your Xcode project to use the HealthKit integration pipeline.

## Table of Contents

1. [Info.plist Configuration](#infoplist-configuration)
2. [Xcode Capabilities](#xcode-capabilities)
3. [Background Modes](#background-modes)
4. [Build Settings](#build-settings)
5. [Testing Configuration](#testing-configuration)

---

## Info.plist Configuration

### Required Privacy Keys

Add the following keys to your `Info.plist` file to request user permission for accessing health data:

#### 1. Health Share Usage Description

**Key:** `NSHealthShareUsageDescription`

**Type:** String

**Value Example:**
```xml
<key>NSHealthShareUsageDescription</key>
<string>We need access to your health data to track your fitness progress, monitor your heart health, and provide personalized insights. Your data is encrypted and never shared with third parties.</string>
```

**Purpose:** Explains why the app needs to read health data from HealthKit.

#### 2. Health Update Usage Description

**Key:** `NSHealthUpdateUsageDescription`

**Type:** String

**Value Example:**
```xml
<key>NSHealthUpdateUsageDescription</key>
<string>We may write health data such as blood pressure readings that you manually enter into the app.</string>
```

**Purpose:** Explains why the app needs to write health data to HealthKit (if applicable).

### Complete Info.plist Privacy Section

Add this to your Info.plist:

```xml
<key>NSHealthShareUsageDescription</key>
<string>We need access to your health data to track your fitness progress, monitor your heart health, and provide personalized insights. Your data is encrypted and never shared with third parties.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>We may write health data such as blood pressure readings that you manually enter into the app.</string>

<key>NSMotionUsageDescription</key>
<string>We need access to your motion data to accurately track your steps and activity levels.</string>

<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
    <string>fetch</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.health.tracker.healthkit.sync</string>
</array>
```

---

## Xcode Capabilities

### Enable HealthKit Capability

1. Open your Xcode project
2. Select your app target
3. Go to the **Signing & Capabilities** tab
4. Click the **+ Capability** button
5. Search for and add **HealthKit**
6. Ensure the following options are checked:
   - ☑ HealthKit
   - ☑ Background Delivery (if you want background updates)

### Entitlements

After enabling HealthKit, Xcode will automatically create an entitlements file with:

```xml
<key>com.apple.developer.healthkit</key>
<true/>

<key>com.apple.developer.healthkit.access</key>
<array>
    <string>health-records</string>
</array>
```

---

## Background Modes

### Enable Background Capabilities

For background health data synchronization:

1. In **Signing & Capabilities**
2. Click **+ Capability**
3. Add **Background Modes**
4. Check the following:
   - ☑ Background fetch
   - ☑ Background processing

### Register Background Task

In your `AppDelegate` or main app file, add:

```swift
import BackgroundTasks

func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Register background task
    HealthKitObserverManager.registerBackgroundTask()

    return true
}
```

---

## Build Settings

### Swift Compiler Settings

Ensure the following build settings are configured:

- **Swift Language Version:** Swift 5.0 or later
- **iOS Deployment Target:** iOS 17.0 or later (for full HealthKit support)

### Framework Linking

The following frameworks should be linked (automatically added when enabling HealthKit capability):

- HealthKit.framework
- Foundation.framework
- UIKit.framework
- CryptoKit.framework (for encryption)
- BackgroundTasks.framework (for background sync)

---

## Testing Configuration

### Simulator Limitations

⚠️ **Important:** HealthKit is **NOT available** in the iOS Simulator.

You must test on a **real device** (iPhone or Apple Watch).

### Testing on Physical Device

1. Build and run on a real iPhone
2. Grant HealthKit permissions when prompted
3. Use the Health app to add sample data for testing

### Sample Data for Testing

You can add sample health data via:

1. **Health app:** Manually add data points
2. **Test automation:** Use HealthKit's `HKHealthStore.save()` method
3. **Third-party apps:** Use Apple Watch or fitness apps to generate real data

---

## Environment Variables (Optional)

For the API client, you can configure the following environment variables or use a configuration file:

### API Configuration

Create a `HealthAPIConfig.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BaseURL</key>
    <string>https://api.healthtracker.example.com</string>

    <key>APIKey</key>
    <string>YOUR_API_KEY_HERE</string>

    <key>Timeout</key>
    <integer>30</integer>

    <key>EnableEncryption</key>
    <true/>

    <key>EnableCertificatePinning</key>
    <true/>
</dict>
</plist>
```

---

## Security Best Practices

### 1. API Keys

- **Never** hardcode API keys in source code
- Use environment variables or secure configuration files
- Store sensitive keys in the Keychain

### 2. Data Encryption

The provided `HealthAPIClient` uses AES-256-GCM encryption by default:

```swift
// Encryption is enabled by default
let config = HealthAPIClient.APIConfiguration.default
// config.enableEncryption = true
```

### 3. Certificate Pinning

For production, implement certificate pinning:

```swift
// In HealthAPIClient.swift, implement validateCertificate()
private func validateCertificate(_ challenge: URLAuthenticationChallenge) -> Bool {
    // Compare server certificate against pinned certificates
    // Return true only if match found
}
```

### 4. Transport Security

Ensure App Transport Security (ATS) is properly configured:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.healthtracker.example.com</key>
        <dict>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
        </dict>
    </dict>
</dict>
```

---

## Troubleshooting

### Common Issues

#### 1. "HealthKit not available"

- Check that you're running on a real device (not simulator)
- Verify HealthKit capability is enabled in project settings
- Ensure deployment target is iOS 8.0 or later

#### 2. "Authorization failed"

- Verify Info.plist contains required privacy keys
- Check that privacy descriptions are user-friendly
- Ensure you're requesting valid health data types

#### 3. "Background delivery not working"

- Verify Background Modes capability is enabled
- Check that background task identifier is registered
- Ensure device is not in Low Power Mode

#### 4. "Data not syncing"

- Check network connectivity
- Verify API endpoint URLs are correct
- Check battery level (sync may be throttled on low battery)
- Review sync configuration settings

---

## Next Steps

1. **Configure Info.plist** with the privacy keys above
2. **Enable HealthKit capability** in Xcode
3. **Test on a real device** with sample health data
4. **Configure your API endpoint** in `HealthAPIClient`
5. **Review the Integration Guide** for usage examples

For usage examples and integration instructions, see [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md).
