## EcoDrive ML (Firebase-seeded hybrid pipeline)

This folder contains a production-quality Python ML pipeline that:

- Loads **real historical data** from Firebase Realtime Database (`carEmissions/history/...`).
- Flattens the nested date/time structure into a clean `pandas.DataFrame`.
- Computes **real-data statistics + correlations** and uses them to generate **realistic synthetic drive sessions**.
- Creates session windows (50–100 readings per session).
- Generates labels for two tasks:
  - **Task A (Driver Behavior)**: Eco / Normal / Aggressive / Idle-heavy
  - **Task B (Vehicle Health)**: Healthy / Needs Service / Critical
- Trains and compares:
  - Random Forest
  - XGBoost (if installed)
  - Small Dense Neural Network (TensorFlow)
- Exports the best model per task to **quantized TensorFlow Lite** for Flutter.

### Project layout

- `ecodrive_ml/`: reusable library code
- `scripts/`: runnable entry points
- `data/`: local caches and derived datasets (not committed by default)
- `models/`: saved preprocessors and exported `.tflite`

### Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Fill `.env` with:

- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `FIREBASE_DATABASE_URL`
- `FIREBASE_HISTORY_PATH` (default: `carEmissions/history`)

### Run end-to-end

```bash
mkdir -p data models reports

# 1) Fetch from Firebase (and optionally cache)
python -m scripts.01_fetch_firebase

# 2) Flatten + build sessions + compute stats
python -m scripts.02_prepare_dataset

# 3) Generate synthetic sessions from real stats
python -m scripts.03_generate_synthetic

# 4) Train + evaluate Driver Behavior models
python -m scripts.04_train_driver

# 5) Train + evaluate Vehicle Health models
python -m scripts.05_train_vehicle

# 6) Export best models to quantized TFLite
python -m scripts.06_export_tflite
```

Outputs:

- `models/driver_model.tflite`
- `models/vehicle_model.tflite`
- `models/driver_preprocess.joblib`
- `models/vehicle_preprocess.joblib`

### How Flutter will feed live readings to TFLite later

- Your Flutter app (already receiving MQTT/Firebase readings) should build a **rolling buffer** of the last \(N\) readings (50–100).
- Run the **same feature engineering** as in `ecodrive_ml/features.py` on that buffer to produce a single feature vector per session.
- Apply the saved preprocessing (scaler + column order) and call the TFLite model.

The conversion scripts export metadata (feature order) inside the `*.joblib` preprocess bundle so Flutter can keep consistent input ordering.

### Notes

- Labels are **rule-based** (pseudo-labeling) because the raw RTDB history is unlabeled. Rules are designed to be data-driven using your real distribution and per-session dynamics.
- You can replace the labeler later with human labels or a richer definition without changing the rest of the pipeline.
