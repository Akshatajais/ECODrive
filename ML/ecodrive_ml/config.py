from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class EcoDriveConfig:
    firebase_service_account_json: str | None
    firebase_database_url: str | None
    firebase_history_path: str
    firebase_cache_json: str | None
    seed: int


def load_config(env_path: str | None = ".env") -> EcoDriveConfig:
    if env_path:
        load_dotenv(env_path)

    service_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON") or None
    db_url = os.getenv("FIREBASE_DATABASE_URL") or None
    history_path = os.getenv("FIREBASE_HISTORY_PATH", "carEmissions/history")
    cache_json = os.getenv("FIREBASE_CACHE_JSON") or None
    seed = int(os.getenv("ECODRIVE_SEED", "42"))

    if service_json:
        # Normalize to absolute path for safer CLI use.
        service_json = str(Path(service_json).expanduser().resolve())

    return EcoDriveConfig(
        firebase_service_account_json=service_json,
        firebase_database_url=db_url,
        firebase_history_path=history_path.strip("/"),
        firebase_cache_json=cache_json,
        seed=seed,
    )

