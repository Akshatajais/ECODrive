from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

from ecodrive_ml.stats import NUM_COLS, RealDataStats


@dataclass(frozen=True)
class SyntheticConfig:
    n_sessions: int = 2000
    min_len: int = 50
    max_len: int = 100
    # Controls how often random spikes appear.
    base_spike_prob: float = 0.02
    # Spike magnitude expressed as multiples of real-data std.
    spike_std_mult_range: tuple[float, float] = (1.5, 4.0)
    # Baseline drift per step expressed as fraction of std (vehicle health).
    drift_std_frac_range: tuple[float, float] = (0.0, 0.03)


def generate_synthetic_sessions(
    stats: RealDataStats, cfg: SyntheticConfig, seed: int = 42
) -> list[pd.DataFrame]:
    """
    Generate synthetic sessions using real-data distribution, correlation and temporal behavior.

    Approach (intentionally simple + controllable):
    - Sample correlated base vectors (rawGas, temperature, humidity, emissionScore) from a
      multivariate normal aligned to real means/covariance.
    - Impose temporal persistence on emissionScore via AR(1) + diff noise.
    - Inject realistic spikes and recovery tails.
    - Inject optional baseline drift in emissionScore (vehicle health degradation).
    - Clip to observed min/max bounds.
    """
    rng = np.random.default_rng(seed)

    mu = np.array([stats.means[c] for c in NUM_COLS], dtype=float)
    std = np.array([stats.stds[c] for c in NUM_COLS], dtype=float)
    corr = stats.corr.loc[list(NUM_COLS), list(NUM_COLS)].to_numpy(dtype=float)
    cov = np.outer(std, std) * corr

    sessions: list[pd.DataFrame] = []
    for sid in range(cfg.n_sessions):
        n = int(rng.integers(cfg.min_len, cfg.max_len + 1))

        # Sample base correlated values.
        x = rng.multivariate_normal(mean=mu, cov=cov, size=n)
        df = pd.DataFrame(x, columns=list(NUM_COLS))

        # Enforce AR(1)-like temporal behavior on emissionScore.
        e = df["emissionScore"].to_numpy(dtype=float)
        e_out = np.empty_like(e)
        e_out[0] = e[0]
        noise = rng.normal(0.0, stats.emission_diff_std, size=n)
        for t in range(1, n):
            e_out[t] = stats.emission_ar1 * e_out[t - 1] + (1 - stats.emission_ar1) * e[t] + noise[t]
        df["emissionScore"] = e_out

        # Vehicle-health drift: many sessions have near-zero, some have positive drift.
        drift_frac = float(rng.uniform(*cfg.drift_std_frac_range))
        drift_per_step = drift_frac * stats.stds["emissionScore"]
        df["emissionScore"] += drift_per_step * np.arange(n)

        # Spikes: emissionScore and rawGas co-spike.
        spike_prob = cfg.base_spike_prob * float(rng.uniform(0.7, 1.6))
        spikes = rng.random(n) < spike_prob
        if spikes.any():
            mags = rng.uniform(*cfg.spike_std_mult_range, size=n) * stats.stds["emissionScore"]
            df.loc[spikes, "emissionScore"] += mags[spikes]
            df.loc[spikes, "rawGas"] += 0.6 * mags[spikes]  # correlated sensor behavior

            # Recovery tail after spike: exponential decay.
            for idx in np.where(spikes)[0]:
                tail_len = int(rng.integers(3, 10))
                for k in range(1, tail_len):
                    j = idx + k
                    if j >= n:
                        break
                    df.at[j, "emissionScore"] += float(mags[idx]) * np.exp(-k / 3.0) * 0.35

        # Idle-heavy sessions: lower temperature variation and low rawGas movement.
        if rng.random() < 0.15:
            df["temperature"] = df["temperature"].mean() + rng.normal(0, stats.stds["temperature"] * 0.25, size=n)
            df["rawGas"] = df["rawGas"].mean() + rng.normal(0, stats.stds["rawGas"] * 0.20, size=n)

        # Clip all features to observed bounds to keep realism.
        for c in NUM_COLS:
            df[c] = df[c].clip(stats.mins[c], stats.maxs[c])

        df["session_id"] = sid
        df["t"] = np.arange(n)
        sessions.append(df)

    return sessions

