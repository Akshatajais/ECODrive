from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from ecodrive_ml.flatten import flatten_history
from ecodrive_ml.firebase_loader import load_history_from_json
from ecodrive_ml.sessionize import SessionConfig, build_sessions
from ecodrive_ml.stats import compute_real_stats
from ecodrive_ml.features import build_feature_table
from ecodrive_ml.labeling import add_labels, derive_thresholds_from_real


def main() -> None:
    data_dir = Path("data")
    data_dir.mkdir(parents=True, exist_ok=True)

    nested = load_history_from_json(str(data_dir / "firebase_history.json"))
    flat = flatten_history(nested)
    df = flat.df
    (data_dir / "flat_history.csv").write_text(df.to_csv(index=False), encoding="utf-8")
    print(f"Flattened rows: {len(df)} (dropped: {flat.dropped_rows})")

    sessions = build_sessions(df, SessionConfig(min_len=50, max_len=100, gap_seconds=120))
    print(f"Built sessions: {len(sessions)}")

    stats = compute_real_stats(df)
    (data_dir / "real_stats.json").write_text(
        json.dumps(
            {
                "mins": stats.mins,
                "maxs": stats.maxs,
                "means": stats.means,
                "stds": stats.stds,
                "corr": stats.corr.to_dict(),
                "emission_ar1": stats.emission_ar1,
                "emission_diff_std": stats.emission_diff_std,
                "median_sampling_seconds": stats.median_sampling_seconds,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )

    real_feat = build_feature_table(sessions)
    th = derive_thresholds_from_real(real_feat)
    labeled = add_labels(real_feat, th)
    labeled.to_csv(data_dir / "real_session_features_labeled.csv", index=False)
    (data_dir / "label_thresholds.json").write_text(
        json.dumps(th.__dict__, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(f"Wrote labeled real session features: {len(labeled)}")


if __name__ == "__main__":
    main()

