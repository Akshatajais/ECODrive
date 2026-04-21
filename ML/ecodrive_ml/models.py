from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.ensemble import RandomForestClassifier


try:
    import xgboost as xgb  # type: ignore

    _HAS_XGB = True
except Exception:
    xgb = None
    _HAS_XGB = False


@dataclass(frozen=True)
class SplitData:
    X_train: pd.DataFrame
    X_val: pd.DataFrame
    X_test: pd.DataFrame
    y_train: np.ndarray
    y_val: np.ndarray
    y_test: np.ndarray


def split_dataset(
    X: pd.DataFrame, y: pd.Series, seed: int = 42
) -> SplitData:
    X_train, X_tmp, y_train, y_tmp = train_test_split(
        X, y, test_size=0.3, random_state=seed, stratify=y
    )
    X_val, X_test, y_val, y_test = train_test_split(
        X_tmp, y_tmp, test_size=0.5, random_state=seed, stratify=y_tmp
    )
    return SplitData(
        X_train=X_train,
        X_val=X_val,
        X_test=X_test,
        y_train=y_train.to_numpy(),
        y_val=y_val.to_numpy(),
        y_test=y_test.to_numpy(),
    )


def make_preprocess(feature_columns: list[str]) -> ColumnTransformer:
    # All features are numeric; keep them in a fixed order.
    return ColumnTransformer(
        transformers=[
            ("num", StandardScaler(), feature_columns),
        ],
        remainder="drop",
        verbose_feature_names_out=False,
    )


def train_random_forest(
    split: SplitData, feature_columns: list[str], seed: int = 42
) -> Pipeline:
    pipe = Pipeline(
        steps=[
            ("preprocess", make_preprocess(feature_columns)),
            (
                "clf",
                RandomForestClassifier(
                    n_estimators=400,
                    random_state=seed,
                    class_weight="balanced_subsample",
                    n_jobs=-1,
                ),
            ),
        ]
    )
    pipe.fit(split.X_train, split.y_train)
    return pipe


def train_xgboost(
    split: SplitData, feature_columns: list[str], seed: int = 42
) -> Any | None:
    if not _HAS_XGB:
        return None

    le = LabelEncoder()
    y_enc = le.fit_transform(split.y_train)

    pipe = Pipeline(
        steps=[
            ("preprocess", make_preprocess(feature_columns)),
            (
                "clf",
                xgb.XGBClassifier(
                    n_estimators=600,
                    max_depth=5,
                    learning_rate=0.05,
                    subsample=0.9,
                    colsample_bytree=0.9,
                    reg_lambda=1.0,
                    random_state=seed,
                    n_jobs=-1,
                    objective="multi:softprob",
                    eval_metric="mlogloss",
                ),
            ),
        ]
    )
    pipe.fit(split.X_train, y_enc)

    class _Wrapped:
        def __init__(self, pipeline: Pipeline, encoder: LabelEncoder):
            self.pipeline = pipeline
            self.encoder = encoder

        def predict(self, X: pd.DataFrame) -> np.ndarray:
            pred = self.pipeline.predict(X)
            pred = pred.astype(int)
            return self.encoder.inverse_transform(pred)

        def predict_proba(self, X: pd.DataFrame) -> np.ndarray:
            return self.pipeline.predict_proba(X)

    return _Wrapped(pipe, le)


def evaluate_model(
    model: Any,
    X: pd.DataFrame,
    y_true: np.ndarray,
    class_names: list[str],
    title: str,
) -> dict[str, Any]:
    y_pred = model.predict(X)
    acc = float(accuracy_score(y_true, y_pred))
    cm = confusion_matrix(y_true, y_pred, labels=class_names)
    report = classification_report(y_true, y_pred, labels=class_names, output_dict=False)
    return {"title": title, "accuracy": acc, "confusion_matrix": cm, "report": report}


def save_preprocess_bundle(
    preprocess: ColumnTransformer, feature_columns: list[str], out_path: str
) -> None:
    joblib.dump(
        {"preprocess": preprocess, "feature_columns": feature_columns},
        out_path,
    )


def load_preprocess_bundle(path: str) -> dict[str, Any]:
    return joblib.load(path)

