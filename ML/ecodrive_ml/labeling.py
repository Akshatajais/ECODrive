from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


DRIVER_CLASSES = ["Eco Driver", "Normal Driver", "Aggressive Driver", "Idle-heavy Driver"]
VEHICLE_CLASSES = ["Healthy", "Needs Service", "Critical"]


@dataclass(frozen=True)
class LabelThresholds:
    # Driver
    eco_mean_es_max: float
    aggressive_spike_freq_min: float
    aggressive_std_es_min: float
    idle_idle_ratio_min: float
    idle_std_rawgas_max: float
    # Vehicle
    critical_sustained_high_min: float
    critical_drift_min: float
    service_sustained_high_min: float
    service_drift_min: float


def derive_thresholds_from_real(feature_df: pd.DataFrame) -> LabelThresholds:
    """
    Create data-driven thresholds from real-session feature distribution.
    This keeps synthetic labels anchored to your actual sensor behavior.
    """
    if feature_df.empty:
        raise ValueError("Empty feature_df; cannot derive thresholds.")

    def q(col: str, p: float, fallback: float) -> float:
        if col not in feature_df.columns:
            return fallback
        v = feature_df[col].replace([np.inf, -np.inf], np.nan).dropna()
        return float(v.quantile(p)) if len(v) else fallback

    eco_mean_es_max = q("mean_emissionScore", 0.25, fallback=float(feature_df["mean_emissionScore"].median()))
    aggressive_spike_freq_min = q("spike_freq", 0.85, fallback=0.05)
    aggressive_std_es_min = q("std_emissionScore", 0.80, fallback=float(feature_df["std_emissionScore"].median()))
    idle_idle_ratio_min = q("idle_ratio", 0.85, fallback=0.6)
    idle_std_rawgas_max = q("std_rawGas", 0.25, fallback=float(feature_df["std_rawGas"].median()))

    critical_sustained_high_min = q("sustained_high_ratio", 0.90, fallback=0.5)
    critical_drift_min = q("baseline_drift", 0.90, fallback=0.2)
    service_sustained_high_min = q("sustained_high_ratio", 0.75, fallback=0.25)
    service_drift_min = q("baseline_drift", 0.75, fallback=0.05)

    return LabelThresholds(
        eco_mean_es_max=eco_mean_es_max,
        aggressive_spike_freq_min=aggressive_spike_freq_min,
        aggressive_std_es_min=aggressive_std_es_min,
        idle_idle_ratio_min=idle_idle_ratio_min,
        idle_std_rawgas_max=idle_std_rawgas_max,
        critical_sustained_high_min=critical_sustained_high_min,
        critical_drift_min=critical_drift_min,
        service_sustained_high_min=service_sustained_high_min,
        service_drift_min=service_drift_min,
    )


def label_driver_behavior(features: pd.Series, th: LabelThresholds) -> str:
    # Prioritize clear "idle-heavy" first.
    if (
        float(features.get("idle_ratio", 0.0)) >= th.idle_idle_ratio_min
        and float(features.get("std_rawGas", 0.0)) <= th.idle_std_rawgas_max
    ):
        return "Idle-heavy Driver"

    # Aggressive: frequent spikes or high variability.
    if (
        float(features.get("spike_freq", 0.0)) >= th.aggressive_spike_freq_min
        or float(features.get("std_emissionScore", 0.0)) >= th.aggressive_std_es_min
    ):
        return "Aggressive Driver"

    # Eco: low mean score + low spikes.
    if float(features.get("mean_emissionScore", 0.0)) <= th.eco_mean_es_max and float(
        features.get("spike_freq", 0.0)
    ) <= th.aggressive_spike_freq_min * 0.35:
        return "Eco Driver"

    return "Normal Driver"


def label_vehicle_health(features: pd.Series, th: LabelThresholds) -> str:
    sustained = float(features.get("sustained_high_ratio", 0.0))
    drift = float(features.get("baseline_drift", 0.0))

    if sustained >= th.critical_sustained_high_min and drift >= th.critical_drift_min:
        return "Critical"
    if sustained >= th.service_sustained_high_min or drift >= th.service_drift_min:
        return "Needs Service"
    return "Healthy"


def add_labels(feature_df: pd.DataFrame, th: LabelThresholds) -> pd.DataFrame:
    out = feature_df.copy()
    out["driver_label"] = out.apply(lambda r: label_driver_behavior(r, th), axis=1)
    out["vehicle_label"] = out.apply(lambda r: label_vehicle_health(r, th), axis=1)
    return out

