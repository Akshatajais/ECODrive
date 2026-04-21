from __future__ import annotations

from pathlib import Path

import numpy as np

from ecodrive_ml.labeling import VEHICLE_CLASSES
from ecodrive_ml.models import (
    make_preprocess,
    save_preprocess_bundle,
    train_random_forest,
    train_xgboost,
)
from ecodrive_ml.nn import predict_dense_nn, train_dense_nn
from scripts._train_utils import load_real_and_synth, print_eval


def main() -> None:
    art = load_real_and_synth(label_col="vehicle_label", seed=42)
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
        rf_acc = print_eval(
            art.y_val, rf.predict(art.X_val), VEHICLE_CLASSES, "Vehicle / RandomForest (val on real)"
        )
    else:
        print("\n=== Vehicle / RandomForest ===\nSkipped val eval (not enough real sessions).")

    # --- XGBoost benchmark (optional) ---
    xgbm = train_xgboost(
        split=type("S", (), {"X_train": art.X_train, "y_train": art.y_train})(),
        feature_columns=art.feature_columns,
        seed=42,
    )
    xgb_acc = -1.0
    if xgbm is not None and has_val:
        xgb_acc = print_eval(
            art.y_val, xgbm.predict(art.X_val), VEHICLE_CLASSES, "Vehicle / XGBoost (val on real)"
        )
    else:
        print("\n=== Vehicle / XGBoost ===\nSkipped (xgboost not installed).")

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
        class_names=VEHICLE_CLASSES,
        seed=42,
    )
    nn_acc = -1.0
    if has_val:
        nn_acc = print_eval(
            art.y_val,
            predict_dense_nn(nn_res.model, nn_res.label_encoder, Xva),
            VEHICLE_CLASSES,
            "Vehicle / DenseNN (val on real)",
        )
    else:
        print("\n=== Vehicle / DenseNN ===\nSkipped val eval (not enough real sessions).")

    best_name, best_acc = max(
        [("RandomForest", rf_acc), ("XGBoost", xgb_acc), ("DenseNN", nn_acc)],
        key=lambda x: x[1],
    )
    if has_val:
        print(f"\nBest validation model (vehicle): {best_name} (acc={best_acc:.4f})")
    else:
        print("\nBest model selection skipped (no real val set).")

    # Test eval
    if has_test:
        nn_test_pred = predict_dense_nn(nn_res.model, nn_res.label_encoder, Xte)
        print_eval(art.y_test, nn_test_pred, VEHICLE_CLASSES, "Vehicle / DenseNN (test on real)")

        if best_name == "RandomForest":
            print_eval(art.y_test, rf.predict(art.X_test), VEHICLE_CLASSES, "Vehicle / RandomForest (test on real)")
        elif best_name == "XGBoost" and xgbm is not None:
            print_eval(art.y_test, xgbm.predict(art.X_test), VEHICLE_CLASSES, "Vehicle / XGBoost (test on real)")

    # Save deployable artifacts.
    nn_res.model.save(models_dir / "vehicle_nn.keras")
    save_preprocess_bundle(preprocess, art.feature_columns, str(models_dir / "vehicle_preprocess.joblib"))
    (models_dir / "vehicle_classes.txt").write_text("\n".join(VEHICLE_CLASSES), encoding="utf-8")
    print("\nSaved vehicle artifacts to models/.")


if __name__ == "__main__":
    main()

