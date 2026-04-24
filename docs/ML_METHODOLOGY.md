# EcoDrive — ML Methodology (Driver Behavior + Vehicle Health)

This document explains the **machine learning methodology** used in EcoDrive: how the models were built, what they learn, and how they run **on-device** inside the Flutter app.

---

## Project-report add-ons (copy/paste ready)

### Cover page blurb

EcoDrive is a smart vehicle emission monitoring system that combines IoT-based sensing with on-device machine learning to interpret recent emission telemetry and provide actionable insights. The system classifies **driver behavior** (Eco/Normal/Aggressive/Idle-heavy) and **vehicle health** (Healthy/Needs Service/Critical) from short session windows, using a Firebase-seeded synthetic-data pipeline for training and a quantized TensorFlow Lite deployment for fast, offline inference in a Flutter app.

### Abstract (150–200 words)

Vehicle emissions vary dynamically with driving style, maintenance condition, and environmental factors, making point-wise threshold alerts noisy and often non-actionable. This work presents EcoDrive, a mobile-first emission monitoring pipeline that performs **session-based inference** over recent telemetry to produce interpretable driver and vehicle insights. Historical readings are collected from Firebase Realtime Database and transformed into fixed-length session windows. Because raw data are largely unlabeled, we generate realistic synthetic sessions seeded by real-data statistics and correlations, and apply rule-based pseudo-labeling to create supervised targets for two multi-class tasks: driver behavior (Eco/Normal/Aggressive/Idle-heavy) and vehicle health (Healthy/Needs Service/Critical). Each session is converted into an engineered feature vector capturing emission variability, spike frequency, recovery rate, idle stability, and drift. Multiple model families are trained and compared, and the selected neural models are exported as **int8 quantized TensorFlow Lite** for on-device deployment. The Flutter application computes the same session features, applies consistent standardization, and runs inference locally to display predictions and recommendations even when connectivity is limited. The approach emphasizes reproducibility, efficient deployment, and actionable feedback, while noting limitations of pseudo-labeling and potential distribution shift.

### References (recommended)

Use whichever citation style your institute requires (IEEE/APA/MLA). These are the most relevant sources to cite:

- TensorFlow Lite. *TensorFlow Lite documentation (model conversion & quantization)*.
- Flutter. *Flutter documentation (assets, platform integration)*.
- scikit-learn. *StandardScaler, Pipeline, ColumnTransformer documentation*.
- Breiman, L. “Random Forests.” *Machine Learning*, 45(1), 2001.
- Chen, T., Guestrin, C. “XGBoost: A Scalable Tree Boosting System.” *KDD*, 2016. (only if you mention XGBoost)
- Goodfellow, I., Bengio, Y., Courville, A. *Deep Learning*. MIT Press, 2016. (general deep learning background)
- Bishop, C. *Pattern Recognition and Machine Learning*. Springer, 2006. (general ML background)

### Figures (captions + placeholders)

Below is a clean “recommended set” of figures you can include in a project report. Replace each placeholder with a diagram/screenshot.

#### Figure 1 — System overview (end-to-end)

**Caption:** EcoDrive system architecture showing ingestion from sensors (MQTT/Firebase), session buffering in the mobile app, on-device feature engineering, TFLite inference, and user-facing insights/recommendations.

**Placeholder:** *(Insert a high-level block diagram: Sensors → MQTT/Firebase → Flutter app rolling buffer → Feature extractor → TFLite models → Predictions/Recommendations.)*

#### Figure 2 — Offline ML training pipeline (recommended “main” diagram)

**Caption:** Offline ML pipeline used to build EcoDrive models: Firebase history ingestion, flattening, sessionization, statistics extraction, realistic synthetic session generation, pseudo-labeling, model training/selection, and quantized TFLite export for Flutter.

**Placeholder:** *(Insert a flowchart aligned to `ML/scripts/01_fetch_firebase` → `02_prepare_dataset` → `03_generate_synthetic` → `04_train_driver`/`05_train_vehicle` → `06_export_tflite` → `07_export_preprocess_json`.)*

#### Figure 3 — Session-to-feature transformation

**Caption:** Feature engineering from a session window: `emissionScore` and `rawGas` time-series mapped to interpretable dynamics features (spikes, recovery rate, idle ratio, drift/sustained-high ratio) and assembled into a fixed-order feature vector.

**Placeholder:** *(Insert a diagram with a small time-series sketch + arrows to computed features; list 6–10 key features.)*

#### Figure 4 — On-device inference steps (Flutter)

**Caption:** On-device inference path: rolling buffer → feature computation → standardization (using `*_preprocess.json`) → int8 quantization → TFLite inference → dequantization + softmax confidence → predicted class (from `*_classes.txt`).

**Placeholder:** *(Insert a block diagram; show artifacts: `.tflite`, `*_preprocess.json`, `*_classes.txt`.)*

#### Figure 5 — Example outputs (UI screenshot)

**Caption:** EcoDrive “Insights” UI showing driver behavior and vehicle health predictions with confidence and suggested actions derived from recent telemetry.

**Placeholder:** *(Insert an app screenshot of the Insights screen.)*

### Which diagram to prioritize

If you can include only one diagram, include **Figure 2** (Offline ML training pipeline). It most clearly communicates the “research contribution” and the full methodology in a single view.

---

## 1) Problem definition

EcoDrive produces two classification insights from recent emission telemetry:

- **Driver behavior (Task A)**: `Eco`, `Normal`, `Aggressive`, `Idle-heavy`
- **Vehicle health (Task B)**: `Healthy`, `Needs Service`, `Critical`

These predictions are computed from a **session window** (a rolling buffer) of recent readings. The goal is to summarize *patterns* (spikes, stability, drift) rather than reacting to single noisy measurements.

---

## 2) Data sources

### 2.1 Real historical data (Firebase Realtime Database)

The ML pipeline reads historical records from Firebase Realtime Database:

- Path (default): `carEmissions/history/...`

This provides **real distributions** (ranges, noise, correlations) of the telemetry used to seed the rest of the pipeline.

### 2.2 Why synthetic data is used

The Firebase history is typically:

- **Unlabeled** (no ground-truth “aggressive driver” / “critical vehicle” labels)
- **Limited in coverage** (may not contain enough diverse driving patterns / failure modes)

To make supervised learning feasible and robust, the pipeline generates **real-statistics–seeded synthetic sessions** that resemble real data dynamics.

**Important**: synthetic data improves *training coverage* and generalization, but it does **not** replace the need for real readings at inference time. At runtime, the model still requires a recent window of inputs to compute features.

---

## 3) Sessionization (learning over windows, not points)

Instead of training on isolated readings, EcoDrive trains on **sessions**:

- A session is a window of roughly **50–100 consecutive readings**.

Rationale:

- Emissions are noisy at a per-sample level.
- Driver style and vehicle health are better captured by **temporal dynamics**:
  - how often spikes occur,
  - how quickly values recover,
  - whether values drift upward across time,
  - whether the signal is unusually stable (idling).

---

## 4) Feature engineering (working principle)

EcoDrive uses feature engineering to convert a session window into a single numeric feature vector.

Canonical implementation:

- `ML/ecodrive_ml/features.py`

### 4.1 Core input channels

The feature extractor expects (at minimum):

- `emissionScore`
- `rawGas`

Optional supported fields (pipeline-side) include:

- `temperature`
- `humidity`

### 4.2 Features computed per session

The model uses interpretable session statistics designed to capture spikes, stability, and drift:

**Driver-oriented features**

- `mean_emissionScore`, `std_emissionScore`
- `mean_rawGas`, `std_rawGas`
- `spike_count`, `spike_freq`
  - “spikes” are defined by z-score thresholding within a session
- `recovery_rate`
  - measures how quickly the signal returns after spikes
- `idle_ratio`
  - estimates idling by detecting unusually stable `rawGas` around its session median

**Vehicle-health-oriented features**

- `baseline_drift`, `worsening_trend_slope`
  - linear slope of `emissionScore` over time (drift)
- `sustained_high_ratio`
  - fraction of points above a “high” z-score threshold
- `variance_emissionScore`
- `high_spike_count`

**Session metadata**

- `session_len`

### 4.3 Why this works

The model’s “principle of operation” is:

> **recent session → engineered dynamics features → standardized vector → classifier → label + confidence**

This captures patterns that correspond to driver style and health conditions better than raw single-point thresholds.

### 4.4 Runtime window size (current implementation)

In the current Flutter inference implementation (`lib/services/ml_insights_service.dart`), EcoDrive builds the session window from the **latest 80 readings** (or fewer if history is shorter). The offline ML pipeline still supports \(N \in [50, 100]\); the important constraint is that the **feature definitions and column ordering** match between training and mobile inference.

---

## 5) Labels (pseudo-labeling strategy)

Because the source history is not human-labeled, EcoDrive uses **rule-based pseudo-labeling** to create training targets.

The rules are designed to be **data-driven** and session-based:

- high spike frequency and poor recovery can indicate more aggressive behavior,
- high stability can indicate idle-heavy sessions,
- sustained high values and upward drift can indicate potential vehicle health degradation.

This enables supervised training while keeping the pipeline modular: the label definitions can be replaced later with human labels without changing the rest of the pipeline.

---

## 6) Model training and selection

The pipeline trains multiple model families and compares them:

- Random Forest
- XGBoost (optional)
- Dense Neural Network (TensorFlow/Keras)

The best-performing model per task is exported for mobile inference.

Exported artifacts in this project are the quantized **TensorFlow Lite** models consumed by the Flutter app.

---

## 7) Preprocessing (feature ordering + standardization)

To ensure training/inference consistency, preprocessing captures:

- **exact feature column order**
- **StandardScaler parameters** (mean and scale)

Standardization:

\[
x' = \frac{x - \mu}{\sigma}
\]

Artifacts:

- `ML/models/driver_preprocess.joblib`
- `ML/models/vehicle_preprocess.joblib`

For Flutter inference, the same parameters are exported to JSON:

- `ML/models/driver_preprocess.json`
- `ML/models/vehicle_preprocess.json`

These JSON files contain:

- `feature_columns`: ordered list of features
- `mean`: per-feature mean
- `scale`: per-feature scale (standard deviation)

---

## 8) TFLite export and quantization (mobile deployment)

The final Keras models are exported to **quantized TensorFlow Lite** for efficient on-device inference.

Implementation:

- `ML/ecodrive_ml/tflite.py`
- `ML/scripts/06_export_tflite.py`

Key points:

- Uses TFLiteConverter with `Optimize.DEFAULT`
- Uses a representative dataset to calibrate quantization
- Exports **int8** models for speed and size

Artifacts:

- `ML/models/driver_model.tflite`
- `ML/models/vehicle_model.tflite`
- class names:
  - `ML/models/driver_classes.txt`
  - `ML/models/vehicle_classes.txt`

**Note:** These files are declared as Flutter assets in `pubspec.yaml`. If they are missing in your working copy, regenerate them by running the ML pipeline export steps (`ML/scripts/06_export_tflite.py` and `ML/scripts/07_export_preprocess_json.py`) and ensure they exist at `ML/models/`.

---

## 9) On-device inference in Flutter (runtime flow)

At runtime the app performs the same logical sequence as training:

1. Maintain a rolling buffer of recent readings (session window).
2. Compute session features (same definitions as pipeline).
3. Reorder features by `feature_columns`.
4. Apply StandardScaler using `mean` and `scale`.
5. Quantize to int8 using the TFLite tensor quantization parameters.
6. Run inference.
7. Dequantize outputs and convert them into a probability distribution (softmax) to show:
   - predicted class label,
   - confidence score.

This is implemented in Flutter in:

- `lib/services/ml_insights_service.dart`

The UI displays results in:

- `lib/screens/ml_insights_screen.dart`

---

## 10) Practical constraints and limitations

### 10.1 Minimum data required at inference time

Even though training uses synthetic sessions, the model still needs **real input** to compute features. A short window is unreliable (e.g., 1–5 points does not produce meaningful spike/stability/trend measures).

### 10.2 Pseudo-labeling limitations

Pseudo-labels encode assumptions; the model will learn those definitions. For production-grade accuracy, replace pseudo-labels with:

- human-labeled sessions, or
- richer labeling rules validated against domain expertise.

### 10.3 Distribution shift

If real-world data changes (new sensor calibration, different vehicle types, new environments), the model should be retrained using updated Firebase history to re-seed statistics and regenerate synthetic data.

---

## 11) Reproducibility (how to rebuild)

ML pipeline entrypoints are in `ML/scripts/` (see `ML/README.md`). Typical flow:

- fetch Firebase history
- prepare sessions and compute stats
- generate synthetic sessions
- train driver and vehicle models
- export quantized TFLite models

Outputs are written to `ML/models/`.

