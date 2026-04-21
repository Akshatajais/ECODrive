from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix


@dataclass(frozen=True)
class TrainArtifacts:
    feature_columns: list[str]
    X_train: pd.DataFrame
    X_val: pd.DataFrame
    X_test: pd.DataFrame
    y_train: np.ndarray
    y_val: np.ndarray
    y_test: np.ndarray


def load_real_and_synth(
    label_col: str,
    seed: int = 42,
) -> TrainArtifacts:
    """
    Split REAL sessions into train/val/test; add SYNTHETIC only to train.
    This keeps evaluation grounded on real data.
    """
    data_dir = Path("data")
    real = pd.read_csv(data_dir / "real_session_features_labeled.csv")
    synth = pd.read_csv(data_dir / "synthetic_session_features_labeled.csv")

    # Clean: keep rows, impute numeric NaNs; drop only if label missing.
    real = real.replace([np.inf, -np.inf], np.nan)
    synth = synth.replace([np.inf, -np.inf], np.nan)

    # Feature columns = numeric features (exclude ids + labels).
    exclude = {"session_id", "driver_label", "vehicle_label"}
    feature_columns = [c for c in real.columns if c not in exclude]

    # Ensure consistent columns in synth.
    synth = synth[feature_columns + [label_col]]
    real = real[feature_columns + [label_col]]

    # Drop rows missing labels, then impute numeric features.
    real = real.dropna(subset=[label_col]).reset_index(drop=True)
    synth = synth.dropna(subset=[label_col]).reset_index(drop=True)
    for c in feature_columns:
        med_r = float(real[c].median()) if c in real.columns else 0.0
        real[c] = pd.to_numeric(real[c], errors="coerce").fillna(med_r)
        med_s = float(synth[c].median()) if c in synth.columns else med_r
        synth[c] = pd.to_numeric(synth[c], errors="coerce").fillna(med_s)

    from sklearn.model_selection import train_test_split

    Xr = real[feature_columns]
    yr = real[label_col]

    def _can_stratify(y: pd.Series) -> bool:
        vc = y.value_counts()
        return len(vc) >= 2 and int(vc.min()) >= 2

    if len(real) < 10:
        # Tiny real dataset: keep evaluation but avoid empty splits.
        X_train_r, X_val_r, X_test_r = Xr, Xr.iloc[:0], Xr.iloc[:0]
        y_train_r, y_val_r, y_test_r = yr, yr.iloc[:0], yr.iloc[:0]
    else:
        strat1 = yr if _can_stratify(yr) else None
        X_train_r, X_tmp_r, y_train_r, y_tmp_r = train_test_split(
            Xr, yr, test_size=0.3, random_state=seed, stratify=strat1
        )
        strat2 = y_tmp_r if _can_stratify(y_tmp_r) else None
        X_val_r, X_test_r, y_val_r, y_test_r = train_test_split(
            X_tmp_r, y_tmp_r, test_size=0.5, random_state=seed, stratify=strat2
        )

    # Add synthetic to train set only.
    X_train = pd.concat([X_train_r, synth[feature_columns]], ignore_index=True)
    y_train = np.concatenate([y_train_r.to_numpy(), synth[label_col].to_numpy()])

    return TrainArtifacts(
        feature_columns=feature_columns,
        X_train=X_train,
        X_val=X_val_r.reset_index(drop=True),
        X_test=X_test_r.reset_index(drop=True),
        y_train=y_train,
        y_val=y_val_r.to_numpy(),
        y_test=y_test_r.to_numpy(),
    )


def print_eval(y_true: np.ndarray, y_pred: np.ndarray, class_names: list[str], title: str) -> float:
    acc = float(accuracy_score(y_true, y_pred))
    print(f"\n=== {title} ===")
    print(f"Accuracy: {acc:.4f}")
    print("Confusion matrix:")
    print(confusion_matrix(y_true, y_pred, labels=class_names))
    print("\nClassification report:")
    print(classification_report(y_true, y_pred, labels=class_names))
    return acc

