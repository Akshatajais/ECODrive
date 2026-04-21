from __future__ import annotations

from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import tensorflow as tf

from ecodrive_ml.tflite import export_quantized_tflite


def _export_one(
    keras_path: Path,
    preprocess_path: Path,
    out_tflite_path: Path,
    rep_source_csv: Path,
    label_col: str,
) -> None:
    _ = label_col  # kept for symmetry / future per-task representative filtering
    bundle = joblib.load(preprocess_path)
    preprocess = bundle["preprocess"]
    feature_cols = bundle["feature_columns"]

    if not rep_source_csv.exists():
        raise FileNotFoundError(f"Representative source missing: {rep_source_csv}")

    rep_df = pd.read_csv(rep_source_csv)[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0.0)
    X_rep = preprocess.transform(rep_df).astype(np.float32)
    # Use a subsample for representative dataset.
    if len(X_rep) > 2000:
        X_rep = X_rep[:2000]

    model = tf.keras.models.load_model(keras_path)
    res = export_quantized_tflite(model, X_rep, str(out_tflite_path), int8=True)
    print(f"Exported {out_tflite_path} (in={res.input_dtype}, out={res.output_dtype})")


def main() -> None:
    models_dir = Path("models")
    data_dir = Path("data")
    models_dir.mkdir(parents=True, exist_ok=True)

    _export_one(
        keras_path=models_dir / "driver_nn.keras",
        preprocess_path=models_dir / "driver_preprocess.joblib",
        out_tflite_path=models_dir / "driver_model.tflite",
        rep_source_csv=data_dir / "synthetic_session_features_labeled.csv",
        label_col="driver_label",
    )
    _export_one(
        keras_path=models_dir / "vehicle_nn.keras",
        preprocess_path=models_dir / "vehicle_preprocess.joblib",
        out_tflite_path=models_dir / "vehicle_model.tflite",
        rep_source_csv=data_dir / "synthetic_session_features_labeled.csv",
        label_col="vehicle_label",
    )


if __name__ == "__main__":
    main()

