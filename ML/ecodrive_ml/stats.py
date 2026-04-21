from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


NUM_COLS = ("rawGas", "temperature", "humidity", "emissionScore")


@dataclass(frozen=True)
class RealDataStats:
    mins: dict[str, float]
    maxs: dict[str, float]
    means: dict[str, float]
    stds: dict[str, float]
    corr: pd.DataFrame
    emission_ar1: float
    emission_diff_std: float
    median_sampling_seconds: float


def compute_real_stats(df: pd.DataFrame) -> RealDataStats:
    d = df.copy()
    for c in NUM_COLS:
        d[c] = pd.to_numeric(d[c], errors="coerce")
    d = d.dropna(subset=["dt", *NUM_COLS]).sort_values("dt").reset_index(drop=True)
    if d.empty:
        raise ValueError("No usable numeric rows in real dataset.")

    mins = {c: float(d[c].min()) for c in NUM_COLS}
    maxs = {c: float(d[c].max()) for c in NUM_COLS}
    means = {c: float(d[c].mean()) for c in NUM_COLS}
    stds = {c: float(d[c].std(ddof=0) if d[c].std(ddof=0) > 0 else 1e-6) for c in NUM_COLS}
    corr = d[list(NUM_COLS)].corr().fillna(0.0)

    # AR(1) coefficient estimate for emissionScore to mimic temporal persistence.
    e = d["emissionScore"].to_numpy(dtype=float)
    e0, e1 = e[:-1], e[1:]
    denom = float(np.dot(e0, e0)) if len(e0) else 0.0
    ar1 = float(np.dot(e0, e1) / denom) if denom > 1e-12 else 0.6
    ar1 = float(np.clip(ar1, -0.95, 0.95))

    diffs = np.diff(e)
    emission_diff_std = float(np.std(diffs) if len(diffs) else stds["emissionScore"])

    deltas = d["dt"].diff().dt.total_seconds().dropna()
    median_sampling_seconds = float(deltas.median()) if len(deltas) else 5.0
    if not np.isfinite(median_sampling_seconds) or median_sampling_seconds <= 0:
        median_sampling_seconds = 5.0

    return RealDataStats(
        mins=mins,
        maxs=maxs,
        means=means,
        stds=stds,
        corr=corr,
        emission_ar1=ar1,
        emission_diff_std=emission_diff_std,
        median_sampling_seconds=median_sampling_seconds,
    )

