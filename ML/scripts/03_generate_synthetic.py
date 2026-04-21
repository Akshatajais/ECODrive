from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from ecodrive_ml.synthetic import SyntheticConfig, generate_synthetic_sessions
from ecodrive_ml.features import build_feature_table
from ecodrive_ml.labeling import LabelThresholds, add_labels


def main() -> None:
    data_dir = Path("data")
    data_dir.mkdir(parents=True, exist_ok=True)

    stats = json.loads((data_dir / "real_stats.json").read_text(encoding="utf-8"))
    corr = pd.DataFrame(stats["corr"])

    from ecodrive_ml.stats import RealDataStats

    real_stats = RealDataStats(
        mins={k: float(v) for k, v in stats["mins"].items()},
        maxs={k: float(v) for k, v in stats["maxs"].items()},
        means={k: float(v) for k, v in stats["means"].items()},
        stds={k: float(v) for k, v in stats["stds"].items()},
        corr=corr,
        emission_ar1=float(stats["emission_ar1"]),
        emission_diff_std=float(stats["emission_diff_std"]),
        median_sampling_seconds=float(stats["median_sampling_seconds"]),
    )

    th_dict = json.loads((data_dir / "label_thresholds.json").read_text(encoding="utf-8"))
    th = LabelThresholds(**{k: float(v) for k, v in th_dict.items()})

    syn_sessions = generate_synthetic_sessions(
        real_stats,
        SyntheticConfig(n_sessions=3000, min_len=50, max_len=100),
        seed=42,
    )
    syn_feat = build_feature_table(syn_sessions)
    syn_labeled = add_labels(syn_feat, th)
    syn_labeled.to_csv(data_dir / "synthetic_session_features_labeled.csv", index=False)
    print(f"Wrote synthetic labeled sessions: {len(syn_labeled)}")


if __name__ == "__main__":
    main()

