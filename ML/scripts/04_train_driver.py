from __future__ import annotations

from pathlib import Path

import numpy as np

from ecodrive_ml.labeling import DRIVER_CLASSES
from ecodrive_ml.models import (
    make_preprocess,
    save_preprocess_bundle,
    train_random_forest,
    train_xgboost,
)
from ecodrive_ml.nn import predict_dense_nn, train_dense_nn
from scripts._train_utils import load_real_and_synth, print_eval


def main() -> None:
    art = load_real_and_synth(label_col="driver_label", seed=42)
    models_dir = Path("models")
    models_dir.mkdir(parents=True, exist_ok=True)

    has_val = len(art.X_val) > 0
    has_test = len(art.X_test) > 0

    # --- RF benchmark ---
    rf = train_random_forest(
        split=type("S", (), {"X_train": art.X_train, "y_train": art.y_train})(),
        feature_columns=art.feature_columns,
        seed=42,
    )
    rf_acc = -1.0
    if has_val:
        rf_val = rf.predict(art.X_val)
        rf_acc = print_eval(art.y_val, rf_val, DRIVER_CLASSES, "Driver / RandomForest (val on real)")
    else:
        print("\n=== Driver / RandomForest ===\nSkipped val eval (not enough real sessions).")

    # --- XGBoost benchmark (optional) ---
    xgbm = train_xgboost(
        split=type("S", (), {"X_train": art.X_train, "y_train": art.y_train})(),
        feature_columns=art.feature_columns,
        seed=42,
    )
    xgb_acc = -1.0
    if xgbm is not None and has_val:
        xgb_val = xgbm.predict(art.X_val)
        xgb_acc = print_eval(art.y_val, xgb_val, DRIVER_CLASSES, "Driver / XGBoost (val on real)")
    else:
        print("\n=== Driver / XGBoost ===\nSkipped (xgboost not installed).")

    # --- Deployable NN (always trained) ---
    preprocess = make_preprocess(art.feature_columns)
    preprocess.fit(art.X_train)
    Xtr = preprocess.transform(art.X_train).astype(np.float32)
    Xva = preprocess.transform(art.X_val).astype(np.float32) if has_val else Xtr[:0]
    Xte = preprocess.transform(art.X_test).astype(np.float32) if has_test else Xtr[:0]

    nn_res = train_dense_nn(
        X_train=Xtr,
        y_train=art.y_train,
        X_val=Xva if has_val else Xtr[: min(len(Xtr), 256)],
        y_val=art.y_val if has_val else art.y_train[: min(len(art.y_train), 256)],
        class_names=DRIVER_CLASSES,
        seed=42,
    )
    nn_acc = -1.0
    if has_val:
        nn_val_pred = predict_dense_nn(nn_res.model, nn_res.label_encoder, Xva)
        nn_acc = print_eval(art.y_val, nn_val_pred, DRIVER_CLASSES, "Driver / DenseNN (val on real)")
    else:
        print("\n=== Driver / DenseNN ===\nSkipped val eval (not enough real sessions).")

    # Choose best overall (for reporting) and best deployable (NN) for export.
    best_name, best_acc = max(
        [("RandomForest", rf_acc), ("XGBoost", xgb_acc), ("DenseNN", nn_acc)],
        key=lambda x: x[1],
    )
    if has_val:
        print(f"\nBest validation model (driver): {best_name} (acc={best_acc:.4f})")
    else:
        print("\nBest model selection skipped (no real val set).")

    # Final test eval for NN (deployable) + also for best sklearn model if it wins.
    if has_test:
        nn_test_pred = predict_dense_nn(nn_res.model, nn_res.label_encoder, Xte)
        print_eval(art.y_test, nn_test_pred, DRIVER_CLASSES, "Driver / DenseNN (test on real)")

        if best_name == "RandomForest":
            print_eval(art.y_test, rf.predict(art.X_test), DRIVER_CLASSES, "Driver / RandomForest (test on real)")
        elif best_name == "XGBoost" and xgbm is not None:
            print_eval(art.y_test, xgbm.predict(art.X_test), DRIVER_CLASSES, "Driver / XGBoost (test on real)")

    # Save deployable artifacts.
    nn_res.model.save(models_dir / "driver_nn.keras")
    save_preprocess_bundle(preprocess, art.feature_columns, str(models_dir / "driver_preprocess.joblib"))
    (models_dir / "driver_classes.txt").write_text("\n".join(DRIVER_CLASSES), encoding="utf-8")
    print("\nSaved driver artifacts to models/.")


if __name__ == "__main__":
    main()

