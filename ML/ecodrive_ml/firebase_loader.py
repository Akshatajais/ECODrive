from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ecodrive_ml.config import EcoDriveConfig


def _init_firebase_once(cfg: EcoDriveConfig) -> None:
    import firebase_admin
    from firebase_admin import credentials

    if firebase_admin._apps:
        return

    if not cfg.firebase_service_account_json:
        raise ValueError(
            "Missing FIREBASE_SERVICE_ACCOUNT_JSON. "
            "Set it in .env to a Firebase Admin SDK service account JSON path."
        )
    if not cfg.firebase_database_url:
        raise ValueError(
            "Missing FIREBASE_DATABASE_URL (Realtime Database URL). Set it in .env."
        )

    cred = credentials.Certificate(cfg.firebase_service_account_json)
    firebase_admin.initialize_app(cred, {"databaseURL": cfg.firebase_database_url})


def fetch_history(cfg: EcoDriveConfig, use_cache: bool = True) -> dict[str, Any]:
    """
    Fetch nested history from RTDB.

    Expected shape:
      carEmissions/history/YYYY-MM-DD/HH-MM-SS/{rawGas, temperature, humidity, emissionScore, timestamp}
    """
    cache_path: Path | None = Path(cfg.firebase_cache_json) if cfg.firebase_cache_json else None
    if use_cache and cache_path and cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    _init_firebase_once(cfg)

    from firebase_admin import db

    ref = db.reference(cfg.firebase_history_path)
    data = ref.get()
    if data is None:
        data = {}

    if cache_path:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")

    return data


def load_history_from_json(path: str) -> dict[str, Any]:
    p = Path(path)
    return json.loads(p.read_text(encoding="utf-8"))

