# Health Tracker App - Architecture Diagrams

## 1. System Architecture Overview

```mermaid
graph TB
    subgraph "iOS Application"
        A[SwiftUI Views] --> B[ViewModels]
        B --> C[Use Cases]
        C --> D[Repositories]

        D --> E[HealthKit Manager]
        D --> F[CoreData Manager]
        D --> G[API Client]
        D --> H[Keychain Manager]

        E --> I[HealthKit Store]
        F --> J[Encrypted SQLite DB]
        G --> K[Backend API]
        H --> L[Secure Enclave]
    end

    subgraph "Apple Ecosystem"
        I --> M[Apple Watch]
        I --> N[iPhone Health App]
    end

    subgraph "Backend Infrastructure"
        K --> O[Azure/GCP FHIR Server]
        K --> P[Authentication Service]
        K --> Q[Encryption Key Service]
    end

    style A fill:#4CAF50
    style B fill:#2196F3
    style C fill:#FF9800
    style D fill:#9C27B0
    style J fill:#F44336
    style L fill:#F44336
```

---

## 2. Layered Architecture (Clean Architecture + MVVM)

```mermaid
graph LR
    subgraph "Presentation Layer"
        A1[DashboardView]
        A2[HeartRateView]
        A3[StepsView]
        B1[DashboardViewModel]
        B2[HeartRateViewModel]
        B3[StepsViewModel]

        A1 --> B1
        A2 --> B2
        A3 --> B3
    end

    subgraph "Domain Layer"
        C1[FetchHeartRateUseCase]
        C2[SyncHealthDataUseCase]
        C3[AuthenticateUserUseCase]

        D1[HealthDataRepository Protocol]
        D2[UserRepository Protocol]

        B1 --> C1
        B2 --> C1
        B3 --> C2

        C1 --> D1
        C2 --> D1
        C3 --> D2
    end

    subgraph "Data Layer"
        E1[HealthKitRepository Impl]
        E2[RemoteHealthRepository Impl]

        F1[HealthKitManager]
        F2[CoreDataManager]
        F3[APIClient]
        F4[KeychainManager]

        D1 --> E1
        D1 --> E2

        E1 --> F1
        E1 --> F2
        E2 --> F3
        E2 --> F4
    end

    style A1 fill:#E3F2FD
    style B1 fill:#BBDEFB
    style C1 fill:#FFF3E0
    style D1 fill:#FFE0B2
    style E1 fill:#F3E5F5
    style F1 fill:#E1BEE7
```

---

## 3. Data Flow: HealthKit to Backend

```mermaid
sequenceDiagram
    participant AW as Apple Watch
    participant HK as HealthKit Store
    participant HKM as HealthKitManager
    participant VM as ViewModel
    participant UC as Use Case
    participant Repo as Repository
    participant CD as CoreData
    participant Enc as Encryption Service
    participant API as API Client
    participant BE as Backend (Azure/GCP)

    AW->>HK: Sync heart rate data
    HK->>HKM: HKObserverQuery notification
    HKM->>HKM: Execute HKSampleQuery
    HK-->>HKM: Return HKQuantitySamples

    HKM->>Repo: Transform to domain entities
    Repo->>UC: Validate & process
    UC->>VM: Publish update (Combine)
    VM->>VM: Update @Published properties

    Note over Repo,CD: Local Storage Path
    Repo->>Enc: Encrypt PHI fields
    Enc-->>Repo: Return encrypted data
    Repo->>CD: Save to encrypted DB
    CD-->>Repo: Confirm saved

    Note over Repo,BE: Background Sync Path
    Repo->>API: Queue for upload
    API->>API: Add JWT token
    API->>API: Apply certificate pinning
    API->>BE: HTTPS POST (TLS 1.3)
    BE-->>API: 200 OK + server timestamp
    API-->>Repo: Mark as synced
    Repo->>CD: Update sync status
```

---

## 4. Security Architecture

```mermaid
graph TB
    subgraph "Data Security Layers"
        A[User Data Input] --> B{Authentication Required?}
        B -->|Yes| C[Biometric Auth]
        B -->|No| D[Proceed]
        C --> E{Auth Success?}
        E -->|No| F[Deny Access]
        E -->|Yes| D

        D --> G[Application Layer]
        G --> H[Encryption Layer]

        H --> I{Data Type?}
        I -->|Credentials/Tokens| J[Keychain]
        I -->|Health Metrics| K[CryptoKit Encryption]
        I -->|Audit Logs| L[Encrypted Audit Store]

        J --> M[Secure Enclave]
        K --> N[Encrypted CoreData]
        L --> N

        G --> O{Network Request?}
        O -->|Yes| P[TLS 1.3 Layer]
        O -->|No| Q[Local Only]

        P --> R[Certificate Pinning]
        R --> S[Backend API]

        S --> T[FHIR Store]
        S --> U[Audit Service]
    end

    style C fill:#4CAF50
    style M fill:#F44336
    style N fill:#F44336
    style R fill:#FF9800
    style T fill:#2196F3
```

---

## 5. Module Dependencies

```mermaid
graph TD
    subgraph "App Module"
        A[HealthTrackerApp]
        B[AppCoordinator]
        C[DependencyContainer]
    end

    subgraph "Presentation Module"
        D[Views]
        E[ViewModels]
    end

    subgraph "Domain Module - No External Dependencies"
        F[Entities]
        G[Use Cases]
        H[Repository Protocols]
    end

    subgraph "Data Module"
        I[Repository Implementations]
        J[Data Sources]
        K[HealthKit Integration]
        L[Network Layer]
    end

    subgraph "Core Module"
        M[Extensions]
        N[Utilities]
        O[Constants]
    end

    subgraph "Infrastructure"
        P[HealthKit Framework]
        Q[CoreData Framework]
        R[CryptoKit]
        S[Keychain Services]
    end

    A --> B
    A --> C
    C --> D
    D --> E
    E --> G
    G --> H
    H --> I
    I --> J
    J --> K
    J --> L

    K --> P
    I --> Q
    I --> R
    I --> S

    D -.-> M
    E -.-> M
    I -.-> M

    style F fill:#4CAF50
    style G fill:#4CAF50
    style H fill:#4CAF50
    style P fill:#2196F3
    style Q fill:#2196F3
    style R fill:#F44336
    style S fill:#F44336
```

---

## 6. Authentication Flow

```mermaid
sequenceDiagram
    participant U as User
    participant App as iOS App
    participant Bio as LocalAuthentication
    participant KM as KeychainManager
    participant API as API Client
    participant Auth as Auth Service (Backend)
    participant FHIR as FHIR Server

    U->>App: Open app
    App->>Bio: Request biometric auth
    Bio->>U: Show Face ID prompt
    U->>Bio: Authenticate
    Bio-->>App: Success

    App->>KM: Retrieve stored refresh token
    KM-->>App: Return encrypted token

    alt Has valid access token
        App->>API: Use cached access token
    else Token expired
        App->>Auth: POST /oauth/token (refresh)
        Auth-->>App: New access + refresh tokens
        App->>KM: Store new tokens
    end

    App->>API: Add Bearer token to requests
    API->>FHIR: Authorized API call
    FHIR-->>API: Protected health data
    API-->>App: Decrypted response
    App->>U: Display health metrics

    Note over App,Auth: Session timeout: 15 minutes
    Note over KM: Tokens stored in Secure Enclave
```

---

## 7. Offline-First Sync Strategy

```mermaid
stateDiagram-v2
    [*] --> FetchFromHealthKit

    FetchFromHealthKit --> EncryptData: New data available
    EncryptData --> SaveToCoreData: Encryption complete
    SaveToCoreData --> CheckNetworkStatus: Data saved locally

    CheckNetworkStatus --> QueueForSync: Offline
    CheckNetworkStatus --> SyncToBackend: Online

    QueueForSync --> WaitForNetwork: Add to sync queue
    WaitForNetwork --> SyncToBackend: Network available

    SyncToBackend --> HandleConflicts: Upload complete
    HandleConflicts --> MarkAsSynced: Conflicts resolved
    MarkAsSynced --> [*]

    HandleConflicts --> RetryWithBackoff: Server error
    RetryWithBackoff --> SyncToBackend: Retry

    note right of SaveToCoreData
        Data immediately available
        to user even offline
    end note

    note right of HandleConflicts
        Server timestamp wins
        Client data archived
    end note
```

---

## 8. Background Task Architecture

```mermaid
graph TB
    subgraph "iOS System"
        A[BGTaskScheduler]
        B[HKObserverQuery]
    end

    subgraph "Background Tasks"
        C[Health Data Sync Task]
        D[Expired Data Cleanup Task]
        E[Audit Log Upload Task]
    end

    subgraph "Execution Constraints"
        F{Battery Level > 20%?}
        G{WiFi Connected?}
        H{User Inactive?}
    end

    A --> C
    A --> D
    A --> E

    C --> F
    F -->|Yes| G
    G -->|Yes| H
    H -->|Yes| I[Execute Sync]

    F -->|No| J[Defer Task]
    G -->|No| J
    H -->|No| J

    I --> K[Fetch Unsynchronized Records]
    K --> L[Batch Upload to Backend]
    L --> M[Update Sync Status]
    M --> N[Complete Task]

    B --> O[Wake App]
    O --> C

    style I fill:#4CAF50
    style J fill:#FF9800
    style N fill:#2196F3
```

---

## 9. Error Handling & Retry Logic

```mermaid
graph TD
    A[API Request] --> B{Request Successful?}
    B -->|Yes| C[Return Data]
    B -->|No| D{Error Type?}

    D -->|Network Error| E{Retry Count < 4?}
    D -->|Auth Error 401| F[Refresh Token]
    D -->|Server Error 5xx| G{Retry Count < 3?}
    D -->|Client Error 4xx| H[Log Error & Fail]

    E -->|Yes| I[Exponential Backoff]
    E -->|No| J[Store in Local Queue]

    I --> K[Wait 2^n seconds]
    K --> A

    F --> L{Token Refreshed?}
    L -->|Yes| A
    L -->|No| M[Logout User]

    G -->|Yes| I
    G -->|No| J

    J --> N[Background Sync Task]

    style C fill:#4CAF50
    style H fill:#F44336
    style M fill:#F44336
    style N fill:#FF9800
```

---

## 10. CoreData Stack with Encryption

```mermaid
graph TB
    subgraph "Application Layer"
        A[ViewModel]
        B[Use Case]
    end

    subgraph "CoreData Manager"
        C[Main Context]
        D[Background Context]
        E[Persistent Container]
    end

    subgraph "Encryption Layer"
        F[CryptoKit Service]
        G[Key Derivation]
        H[Field-level Encryption]
    end

    subgraph "Storage Layer"
        I[NSPersistentStore]
        J[Encrypted SQLite File]
    end

    A --> C
    B --> D

    C --> E
    D --> E

    E --> F
    F --> G
    F --> H

    H --> I
    I --> J

    K[Encryption Key] --> G
    L[Keychain] --> K

    style J fill:#F44336
    style K fill:#F44336
    style L fill:#F44336
```

---

## Legend

- **Green**: User-facing components
- **Blue**: Business logic / Use cases
- **Purple**: Data layer
- **Red**: Security-critical components
- **Orange**: Network/API layer

---

**Note**: These diagrams are created using Mermaid syntax and can be rendered in:
- GitHub markdown files
- VS Code with Mermaid extension
- Online editors like mermaid.live
- Documentation platforms like GitBook, Notion, Confluence
