from __future__ import annotations

import json
from pathlib import Path

from ecodrive_ml.config import load_config
from ecodrive_ml.firebase_loader import fetch_history


def main() -> None:
    cfg = load_config()
    out_dir = Path("data")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "firebase_history.json"

    nested = fetch_history(cfg, use_cache=True)
    out_path.write_text(json.dumps(nested, indent=2, sort_keys=True), encoding="utf-8")
    print(f"Wrote {out_path} with {len(nested)} date keys.")


if __name__ == "__main__":
    main()

