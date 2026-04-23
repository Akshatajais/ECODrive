from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import joblib


def _extract_scaler(bundle: dict[str, Any]) -> tuple[list[str], list[float], list[float]]:
    feature_cols = list(bundle["feature_columns"])
    preprocess = bundle["preprocess"]

    # preprocess is a ColumnTransformer with ("num", StandardScaler(), feature_cols)
    # After fitting, StandardScaler is available in named_transformers_.
    scaler = preprocess.named_transformers_["num"]
    mean = [float(x) for x in scaler.mean_]
    scale = [float(x) for x in scaler.scale_]
    return feature_cols, mean, scale


def export_one(joblib_path: Path, out_json_path: Path) -> None:
    bundle = joblib.load(joblib_path)
    cols, mean, scale = _extract_scaler(bundle)
    out = {
        "feature_columns": cols,
        "mean": mean,
        "scale": scale,
    }
    out_json_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"Wrote {out_json_path}")


def main() -> None:
    models_dir = Path("models")
    export_one(models_dir / "driver_preprocess.joblib", models_dir / "driver_preprocess.json")
    export_one(models_dir / "vehicle_preprocess.joblib", models_dir / "vehicle_preprocess.json")


if __name__ == "__main__":
    main()

