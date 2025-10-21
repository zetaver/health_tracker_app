# AI-Ready Health Data Schema & Format Specification

Comprehensive data format design for transmitting HealthKit vitals to Azure OpenAI and Google Vertex AI for analysis.

## Table of Contents

1. [Schema Design Principles](#schema-design-principles)
2. [Data Format Specification](#data-format-specification)
3. [Temporal Data Structure](#temporal-data-structure)
4. [Normalization & Preprocessing](#normalization--preprocessing)
5. [Feature Engineering](#feature-engineering)
6. [HIPAA-Compliant Data Exchange](#hipaa-compliant-data-exchange)
7. [Azure OpenAI Integration](#azure-openai-integration)
8. [Google Vertex AI Integration](#google-vertex-ai-integration)

---

## Schema Design Principles

### 1. AI/ML Optimization

**Time-Series Ready**
- Consistent timestamp format (ISO 8601 / Unix epoch)
- Regular sampling intervals when possible
- Temporal aggregations (hourly, daily, weekly)
- Missing data indicators

**Feature-Rich**
- Pre-calculated statistics (mean, median, std, min, max)
- Derived features (heart rate variability, sleep efficiency)
- Contextual metadata (activity level, time of day)
- Temporal features (day of week, hour of day)

**Normalized & Standardized**
- Standard units (SI when possible)
- Z-score normalization options
- Min-max scaling options
- Categorical encoding

### 2. HIPAA Compliance

**Data Minimization**
- Only include necessary fields
- Aggregate where possible
- Remove PII not needed for analysis

**Audit Trail**
- Include request ID for tracking
- Timestamp all operations
- Track data lineage
- Log AI model versions used

**Encryption Requirements**
- All data encrypted in transit (TLS 1.2+)
- Payload encryption (AES-256-GCM)
- Key rotation support
- Secure deletion support

### 3. Flexibility

**Multi-Model Support**
- Works with Azure OpenAI GPT models
- Compatible with Vertex AI models
- Supports custom ML models
- Version-controlled schema

**Extensibility**
- Easy to add new vital types
- Supports custom metrics
- Metadata extension points
- Backward compatible

---

## Data Format Specification

### Core Schema Structure

```json
{
  "schema_version": "1.0",
  "request_id": "uuid",
  "timestamp": "ISO8601",

  "user": {
    "user_id": "hashed-uuid",
    "demographics": { ... },
    "metadata": { ... }
  },

  "time_window": {
    "start_date": "ISO8601",
    "end_date": "ISO8601",
    "duration_seconds": 0,
    "timezone": "UTC"
  },

  "vitals": {
    "heart_rate": { ... },
    "blood_pressure": { ... },
    "steps": { ... },
    "sleep": { ... }
  },

  "aggregations": {
    "daily": [ ... ],
    "hourly": [ ... ],
    "weekly": [ ... ]
  },

  "features": {
    "derived": { ... },
    "statistical": { ... },
    "temporal": { ... }
  },

  "context": {
    "data_quality": { ... },
    "device_info": { ... },
    "preprocessing": { ... }
  }
}
```

### User Information (De-identified)

```json
{
  "user": {
    "user_id": "usr_a1b2c3d4e5f6",  // Hashed, not real user ID

    "demographics": {
      "age_range": "30-40",           // Range, not exact age
      "gender": "M",                  // Optional
      "height_cm": 175.0,
      "weight_kg": 70.0,
      "bmi": 22.9
    },

    "health_profile": {
      "conditions": ["hypertension"],  // Optional
      "medications": ["beta_blocker"], // Optional
      "activity_level": "moderate"     // low, moderate, high, very_high
    },

    "metadata": {
      "data_collection_start": "2024-01-01T00:00:00Z",
      "total_days_active": 90,
      "consent_version": "2.0",
      "privacy_level": "standard"      // standard, enhanced
    }
  }
}
```

### Time Window

```json
{
  "time_window": {
    "start_date": "2024-01-01T00:00:00Z",
    "end_date": "2024-01-07T23:59:59Z",
    "duration_seconds": 604800,
    "timezone": "America/Los_Angeles",
    "daylight_saving": true,

    "granularity": "daily",  // raw, hourly, daily, weekly
    "sampling_rate_seconds": 300  // For raw data
  }
}
```

### Vital Metrics - Heart Rate

```json
{
  "vitals": {
    "heart_rate": {
      "unit": "bpm",
      "data_points": [
        {
          "timestamp": "2024-01-01T08:30:00Z",
          "value": 72.0,
          "context": "resting",           // resting, active, recovery
          "quality": "high",               // high, medium, low
          "source_device": "Apple Watch Series 9"
        }
      ],

      "statistics": {
        "count": 1440,
        "mean": 75.2,
        "median": 74.0,
        "std_dev": 12.5,
        "min": 52.0,
        "max": 158.0,
        "percentile_25": 68.0,
        "percentile_75": 82.0,
        "percentile_95": 105.0
      },

      "derived_metrics": {
        "resting_heart_rate": 58.0,
        "max_heart_rate_observed": 158.0,
        "heart_rate_variability_sdnn": 45.2,  // ms
        "recovery_time_seconds": 120,
        "heart_rate_reserve": 100.0
      },

      "temporal_patterns": {
        "avg_by_hour": {
          "00": 60.5,
          "01": 58.2,
          // ... all 24 hours
          "23": 62.1
        },
        "avg_by_day_of_week": {
          "monday": 74.2,
          "tuesday": 75.1,
          // ... all days
        }
      },

      "anomalies": [
        {
          "timestamp": "2024-01-01T14:30:00Z",
          "value": 158.0,
          "type": "spike",
          "confidence": 0.95,
          "context": "potential_exercise"
        }
      ]
    }
  }
}
```

### Vital Metrics - Blood Pressure

```json
{
  "vitals": {
    "blood_pressure": {
      "unit": "mmHg",
      "data_points": [
        {
          "timestamp": "2024-01-01T08:00:00Z",
          "systolic": 120.0,
          "diastolic": 80.0,
          "mean_arterial_pressure": 93.3,
          "pulse_pressure": 40.0,
          "classification": "normal",
          "measurement_position": "sitting",
          "source_device": "Omron BP Monitor"
        }
      ],

      "statistics": {
        "systolic": {
          "mean": 122.5,
          "std_dev": 8.2,
          "min": 110.0,
          "max": 138.0
        },
        "diastolic": {
          "mean": 78.5,
          "std_dev": 6.1,
          "min": 68.0,
          "max": 88.0
        }
      },

      "trends": {
        "systolic_trend": "stable",       // increasing, decreasing, stable
        "diastolic_trend": "stable",
        "trend_confidence": 0.85,
        "slope_per_day": 0.05
      },

      "risk_indicators": {
        "hypertension_risk": "low",       // low, moderate, high
        "variability_score": 0.15,        // 0-1, lower is better
        "white_coat_effect": false
      }
    }
  }
}
```

### Vital Metrics - Steps & Activity

```json
{
  "vitals": {
    "steps": {
      "unit": "count",
      "data_points": [
        {
          "timestamp": "2024-01-01T00:00:00Z",
          "value": 8542,
          "duration_seconds": 86400,
          "active_minutes": 120,
          "distance_meters": 6834.0,
          "source_device": "iPhone 14 Pro"
        }
      ],

      "statistics": {
        "daily_average": 8234.5,
        "total_steps": 57642,
        "days_over_10k": 3,
        "days_under_5k": 1,
        "consistency_score": 0.78  // 0-1
      },

      "activity_patterns": {
        "peak_hours": [8, 12, 18],
        "sedentary_hours": [0, 1, 2, 3, 22, 23],
        "most_active_day": "wednesday",
        "weekend_vs_weekday_ratio": 0.85
      },

      "goals": {
        "daily_goal": 10000,
        "achievement_rate": 0.57,
        "streak_days": 12
      }
    },

    "active_energy": {
      "unit": "kcal",
      "data_points": [
        {
          "timestamp": "2024-01-01T00:00:00Z",
          "value": 456.0,
          "intensity": "moderate",
          "activity_type": "walking"
        }
      ],

      "statistics": {
        "daily_average": 423.5,
        "total_burned": 2965.0,
        "by_intensity": {
          "light": 1200.0,
          "moderate": 1400.0,
          "vigorous": 365.0
        }
      }
    }
  }
}
```

### Vital Metrics - Sleep

```json
{
  "vitals": {
    "sleep": {
      "data_points": [
        {
          "date": "2024-01-01",
          "start_time": "2024-01-01T22:30:00Z",
          "end_time": "2024-01-02T06:45:00Z",
          "total_duration_seconds": 29700,
          "total_duration_hours": 8.25,

          "stages": {
            "awake": {
              "duration_seconds": 1800,
              "percentage": 6.1,
              "count": 3
            },
            "light": {
              "duration_seconds": 14850,
              "percentage": 50.0
            },
            "deep": {
              "duration_seconds": 7425,
              "percentage": 25.0
            },
            "rem": {
              "duration_seconds": 5625,
              "percentage": 18.9
            }
          },

          "quality_metrics": {
            "sleep_efficiency": 0.94,        // 0-1
            "sleep_latency_minutes": 12,     // Time to fall asleep
            "wake_count": 3,
            "restlessness_score": 0.15,      // 0-1, lower is better
            "sleep_score": 85                // 0-100
          },

          "heart_rate_during_sleep": {
            "average": 58.2,
            "lowest": 52.0,
            "highest": 68.0,
            "variability": 12.5
          },

          "source_device": "Apple Watch Series 9"
        }
      ],

      "statistics": {
        "avg_duration_hours": 7.5,
        "avg_efficiency": 0.89,
        "avg_deep_sleep_hours": 2.1,
        "avg_rem_sleep_hours": 1.5,
        "consistency_score": 0.82,          // 0-1
        "sleep_debt_hours": -2.5            // Negative = deficit
      },

      "patterns": {
        "avg_bedtime": "22:45:00",
        "avg_wake_time": "06:30:00",
        "bedtime_regularity": 0.75,         // 0-1
        "weekend_shift_hours": 1.5,
        "optimal_sleep_window": "22:00-06:30"
      },

      "trends": {
        "duration_trend": "stable",
        "efficiency_trend": "improving",
        "deep_sleep_trend": "stable"
      }
    }
  }
}
```

---

## Temporal Data Structure

### Raw Time Series

```json
{
  "time_series": {
    "metric": "heart_rate",
    "unit": "bpm",
    "sampling_rate_seconds": 60,
    "interpolation": "linear",  // none, linear, cubic

    "data": [
      [1704067200, 72.0],  // [unix_timestamp, value]
      [1704067260, 73.5],
      [1704067320, 71.0]
      // ... more data points
    ],

    "missing_intervals": [
      {
        "start": 1704070800,
        "end": 1704074400,
        "reason": "device_off"
      }
    ]
  }
}
```

### Aggregated Time Series

```json
{
  "aggregations": {
    "hourly": [
      {
        "timestamp": "2024-01-01T00:00:00Z",
        "hour_of_day": 0,
        "day_of_week": "monday",

        "heart_rate": {
          "mean": 60.5,
          "min": 58.0,
          "max": 65.0,
          "std_dev": 2.1,
          "count": 60,
          "missing_count": 0
        },

        "steps": {
          "total": 245,
          "avg_per_minute": 4.1
        },

        "activity_level": "sedentary"
      }
      // ... 24 hours
    ],

    "daily": [
      {
        "date": "2024-01-01",
        "day_of_week": "monday",
        "is_weekend": false,

        "heart_rate": {
          "mean": 75.2,
          "resting": 58.0,
          "max": 158.0,
          "std_dev": 12.5
        },

        "steps": {
          "total": 8542,
          "goal": 10000,
          "achievement": 0.85
        },

        "sleep": {
          "duration_hours": 8.25,
          "efficiency": 0.94,
          "score": 85
        },

        "overall_health_score": 78.5  // 0-100
      }
      // ... 7-30 days
    ],

    "weekly": [
      {
        "week_start": "2024-01-01",
        "week_number": 1,

        "averages": {
          "heart_rate": 76.3,
          "steps": 7845,
          "sleep_hours": 7.5
        },

        "trends": {
          "heart_rate_change": -1.2,    // vs previous week
          "steps_change": 523,
          "sleep_change": 0.3
        },

        "compliance": {
          "data_completeness": 0.95,    // 0-1
          "days_with_data": 7
        }
      }
    ]
  }
}
```

---

## Normalization & Preprocessing

### Normalization Methods

```json
{
  "preprocessing": {
    "normalization": {
      "method": "z_score",  // z_score, min_max, robust, none

      "parameters": {
        "heart_rate": {
          "mean": 75.0,
          "std_dev": 12.0,
          "min": 40.0,
          "max": 200.0
        },
        "blood_pressure_systolic": {
          "mean": 120.0,
          "std_dev": 15.0,
          "min": 90.0,
          "max": 180.0
        }
      },

      "applied": true,
      "inverse_transform_available": true
    },

    "outlier_handling": {
      "method": "iqr",  // iqr, z_score, isolation_forest
      "threshold": 3.0,
      "action": "cap",  // remove, cap, flag
      "outliers_detected": 12,
      "outliers_removed": 0,
      "outliers_capped": 12
    },

    "missing_data": {
      "strategy": "interpolation",  // forward_fill, interpolation, median, remove
      "missing_percentage": 2.5,
      "imputed_count": 36
    },

    "smoothing": {
      "applied": true,
      "method": "moving_average",  // moving_average, exponential, savitzky_golay
      "window_size": 5
    }
  }
}
```

---

## Feature Engineering

### Derived Features

```json
{
  "features": {
    "derived": {
      // Cardiovascular health
      "cardiovascular_fitness_score": 78.5,
      "heart_rate_recovery_score": 82.0,
      "cardiac_stress_index": 0.35,

      // Activity metrics
      "sedentary_percentage": 0.65,
      "active_percentage": 0.25,
      "vigorous_percentage": 0.10,
      "activity_regularity": 0.75,

      // Sleep quality
      "sleep_quality_index": 0.85,
      "sleep_debt_hours": -2.5,
      "circadian_alignment": 0.78,

      // Overall health
      "vitality_score": 75.5,
      "recovery_score": 68.0,
      "stress_score": 32.0
    },

    "statistical": {
      "heart_rate_variability_features": {
        "sdnn": 45.2,
        "rmssd": 38.5,
        "pnn50": 12.3,
        "lf_hf_ratio": 1.2
      },

      "blood_pressure_variability": {
        "coefficient_of_variation": 0.08,
        "average_real_variability": 5.2
      }
    },

    "temporal": {
      "day_of_week_encoded": [0, 1, 0, 0, 0, 0, 0],  // One-hot
      "hour_of_day_sin": 0.5,
      "hour_of_day_cos": 0.866,
      "is_weekend": false,
      "is_work_hours": true,
      "season": "winter"
    },

    "contextual": {
      "days_since_last_exercise": 2,
      "streak_days_over_10k_steps": 5,
      "recent_sleep_quality_trend": "improving"
    }
  }
}
```

---

## HIPAA-Compliant Data Exchange

### Complete Payload Structure

```json
{
  // Schema metadata
  "schema_version": "1.0",
  "request_id": "req_a1b2c3d4e5f6g7h8",
  "timestamp": "2024-01-08T12:00:00Z",

  // Encryption metadata
  "encryption": {
    "algorithm": "AES-256-GCM",
    "key_id": "key_v1_prod",
    "iv": "base64_encoded_iv",
    "encrypted": true
  },

  // Data integrity
  "integrity": {
    "checksum": "sha256_hash",
    "signature": "hmac_sha256_signature"
  },

  // Audit trail
  "audit": {
    "data_collection_start": "2024-01-01T00:00:00Z",
    "data_collection_end": "2024-01-07T23:59:59Z",
    "processing_timestamp": "2024-01-08T11:59:30Z",
    "purpose": "health_analysis",
    "consent_id": "consent_v2_user123",
    "retention_days": 90
  },

  // De-identified user
  "user": { ... },

  // Time window
  "time_window": { ... },

  // Vitals data
  "vitals": { ... },

  // Aggregations
  "aggregations": { ... },

  // Features
  "features": { ... },

  // Context
  "context": {
    "data_quality": {
      "completeness": 0.95,
      "accuracy_score": 0.92,
      "consistency_score": 0.88,
      "reliability": "high"
    },

    "device_info": {
      "primary_device": "Apple Watch Series 9",
      "ios_version": "17.5",
      "healthkit_version": "17.0"
    },

    "preprocessing": { ... }
  }
}
```

---

## Azure OpenAI Integration

### Prompt-Ready Format

```json
{
  "ai_analysis_request": {
    "model": "gpt-4",
    "task": "health_insights",

    "context": {
      "user_profile": {
        "age_range": "30-40",
        "activity_level": "moderate",
        "health_goals": ["improve_sleep", "increase_activity"]
      }
    },

    "data_summary": {
      "period": "7_days",

      "key_metrics": {
        "avg_heart_rate": 75.2,
        "avg_resting_hr": 58.0,
        "avg_steps": 8234,
        "avg_sleep_hours": 7.5,
        "sleep_efficiency": 0.89
      },

      "notable_patterns": [
        "Heart rate elevated on Tuesday (avg 82 vs 75)",
        "Sleep efficiency decreased over weekend",
        "Steps below goal 4 out of 7 days"
      ],

      "anomalies": [
        "Unusually high heart rate spike on Tuesday at 2pm (158 bpm)"
      ]
    },

    "time_series_data": {
      // Condensed time series for context window efficiency
      "daily_aggregates": [ ... ]
    },

    "requested_insights": [
      "overall_health_assessment",
      "personalized_recommendations",
      "risk_factors",
      "trend_analysis"
    ]
  }
}
```

---

## Google Vertex AI Integration

### Prediction Request Format

```json
{
  "instances": [
    {
      "user_features": {
        "age_range_encoded": 3,
        "gender_encoded": 1,
        "bmi": 22.9,
        "activity_level_encoded": 2
      },

      "vital_features": {
        "heart_rate_mean": 75.2,
        "heart_rate_std": 12.5,
        "heart_rate_min": 52.0,
        "heart_rate_max": 158.0,
        "resting_heart_rate": 58.0,
        "hrv_sdnn": 45.2,

        "systolic_mean": 122.5,
        "diastolic_mean": 78.5,

        "steps_daily_avg": 8234,
        "active_minutes_avg": 120,

        "sleep_duration_avg": 7.5,
        "sleep_efficiency_avg": 0.89,
        "deep_sleep_percentage": 0.25
      },

      "temporal_features": {
        "day_of_week_sin": 0.5,
        "day_of_week_cos": 0.866,
        "hour_of_day_sin": 0.0,
        "hour_of_day_cos": 1.0,
        "is_weekend": 0
      },

      "derived_features": {
        "cardiovascular_fitness_score": 78.5,
        "sleep_quality_index": 0.85,
        "activity_regularity": 0.75,
        "stress_score": 32.0
      },

      "time_series": {
        "heart_rate_sequence": [72, 73, 71, 75, 78, ...],  // Last N values
        "steps_sequence": [8542, 7234, 9123, ...],
        "sleep_hours_sequence": [8.25, 7.5, 6.75, ...]
      }
    }
  ],

  "parameters": {
    "prediction_horizon": "7_days",
    "confidence_threshold": 0.8
  }
}
```

---

## Best Practices

### 1. Data Quality

- **Completeness**: Ensure >90% data availability
- **Consistency**: Validate ranges and patterns
- **Accuracy**: Filter outliers appropriately
- **Timeliness**: Include recent data

### 2. Privacy & Security

- **De-identification**: Hash user IDs
- **Aggregation**: Use ranges instead of exact values
- **Minimization**: Only include necessary fields
- **Encryption**: Always encrypt payloads

### 3. AI Optimization

- **Normalization**: Standardize all numeric features
- **Feature Engineering**: Create meaningful derived metrics
- **Temporal Encoding**: Properly encode cyclical features
- **Batching**: Group related data points

### 4. Version Control

- **Schema Versioning**: Track schema changes
- **Model Versioning**: Record AI model versions
- **Backward Compatibility**: Support older versions
- **Migration Path**: Plan for schema updates
