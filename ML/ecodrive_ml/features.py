from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class FeatureConfig:
    spike_z: float = 2.0
    sustained_high_z: float = 1.0
    idle_rawgas_std_frac: float = 0.15


def _safe_std(x: np.ndarray) -> float:
    s = float(np.std(x))
    return s if np.isfinite(s) and s > 1e-12 else 0.0


def _lin_slope(y: np.ndarray) -> float:
    if len(y) < 2:
        return 0.0
    x = np.arange(len(y), dtype=float)
    x = x - x.mean()
    y = y - float(np.mean(y))
    denom = float(np.dot(x, x))
    if denom < 1e-12:
        return 0.0
    return float(np.dot(x, y) / denom)


def extract_session_features(session: pd.DataFrame, cfg: FeatureConfig | None = None) -> dict[str, float]:
    """
    Feature engineering for a single session window.

    Expected columns:
      - emissionScore, rawGas (required)
      - temperature, humidity (optional but supported)
    """
    cfg = cfg or FeatureConfig()

    e = pd.to_numeric(session["emissionScore"], errors="coerce").to_numpy(dtype=float)
    g = pd.to_numeric(session["rawGas"], errors="coerce").to_numpy(dtype=float)

    e = e[np.isfinite(e)]
    g = g[np.isfinite(g)]
    if len(e) == 0 or len(g) == 0:
        raise ValueError("Session has no finite emissionScore/rawGas values.")

    e_mean = float(np.mean(e))
    e_std = _safe_std(e)
    g_mean = float(np.mean(g))
    g_std = _safe_std(g)

    z = (e - e_mean) / (e_std if e_std > 1e-12 else 1.0)
    spikes = z > cfg.spike_z
    spike_count = int(np.sum(spikes))
    spike_freq = float(spike_count / max(1, len(e)))

    # Recovery rate after spike: average negative slope immediately following spikes.
    rec_slopes: list[float] = []
    spike_idx = np.where(spikes)[0]
    for idx in spike_idx:
        if idx + 1 >= len(e):
            continue
        rec_slopes.append(float(e[idx + 1] - e[idx]))
    recovery_rate = float(-np.mean(rec_slopes)) if rec_slopes else 0.0  # higher is "faster recovery"

    # Idle estimate: if rawGas is unusually stable, treat as more idling.
    # We approximate idle ratio as fraction of points within a tight band of the session median.
    g_med = float(np.median(g))
    band = max(1e-6, cfg.idle_rawgas_std_frac * (g_std if g_std > 1e-12 else max(1.0, abs(g_med))))
    idle_ratio = float(np.mean(np.abs(g - g_med) <= band))

    # Vehicle-health oriented features
    drift_slope = _lin_slope(e)
    worsening_trend_slope = drift_slope
    sustained_high_ratio = float(np.mean(z > cfg.sustained_high_z))
    variance = float(np.var(e))
    high_spike_count = float(spike_count)

    return {
        # Driver model (and generally useful)
        "mean_emissionScore": e_mean,
        "std_emissionScore": e_std,
        "mean_rawGas": g_mean,
        "std_rawGas": g_std,
        "spike_freq": spike_freq,
        "spike_count": float(spike_count),
        "recovery_rate": recovery_rate,
        "idle_ratio": idle_ratio,
        # Vehicle model
        "baseline_drift": drift_slope,
        "sustained_high_ratio": sustained_high_ratio,
        "variance_emissionScore": variance,
        "worsening_trend_slope": worsening_trend_slope,
        "high_spike_count": high_spike_count,
        # Session meta
        "session_len": float(len(e)),
    }


def build_feature_table(
    sessions: list[pd.DataFrame], cfg: FeatureConfig | None = None
) -> pd.DataFrame:
    rows: list[dict[str, float]] = []
    for s in sessions:
        r = extract_session_features(s, cfg=cfg)
        sid = int(s["session_id"].iloc[0]) if "session_id" in s.columns else None
        r["session_id"] = float(sid) if sid is not None else np.nan
        rows.append(r)
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows).set_index("session_id", drop=False)
    return df

