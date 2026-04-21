from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.preprocessing import LabelEncoder


@dataclass(frozen=True)
class NNTrainResult:
    model: tf.keras.Model
    label_encoder: LabelEncoder
    history: Any


def make_dense_classifier(input_dim: int, n_classes: int, seed: int = 42) -> tf.keras.Model:
    tf.keras.utils.set_random_seed(seed)
    model = tf.keras.Sequential(
        [
            tf.keras.layers.Input(shape=(input_dim,), name="features"),
            tf.keras.layers.Dense(64, activation="relu"),
            tf.keras.layers.Dropout(0.15),
            tf.keras.layers.Dense(32, activation="relu"),
            tf.keras.layers.Dense(n_classes, activation="softmax"),
        ]
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def train_dense_nn(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_val: np.ndarray,
    y_val: np.ndarray,
    class_names: list[str],
    seed: int = 42,
    epochs: int = 60,
    batch_size: int = 64,
) -> NNTrainResult:
    le = LabelEncoder()
    le.fit(class_names)
    ytr = le.transform(y_train)
    yva = le.transform(y_val)

    model = make_dense_classifier(input_dim=X_train.shape[1], n_classes=len(class_names), seed=seed)
    cb = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy", patience=8, restore_best_weights=True
        )
    ]
    hist = model.fit(
        X_train,
        ytr,
        validation_data=(X_val, yva),
        epochs=epochs,
        batch_size=batch_size,
        verbose=0,
        callbacks=cb,
    )
    return NNTrainResult(model=model, label_encoder=le, history=hist)


def predict_dense_nn(model: tf.keras.Model, le: LabelEncoder, X: np.ndarray) -> np.ndarray:
    probs = model.predict(X, verbose=0)
    idx = np.argmax(probs, axis=1)
    return le.inverse_transform(idx)

