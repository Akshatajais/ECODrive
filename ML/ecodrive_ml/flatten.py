from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

import pandas as pd


@dataclass(frozen=True)
class FlattenResult:
    df: pd.DataFrame
    dropped_rows: int


def _parse_datetime(date_key: str, time_key: str) -> datetime | None:
    # Accept HH-MM-SS or HH:MM:SS-ish variations just in case.
    for fmt in ("%Y-%m-%d %H-%M-%S", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(f"{date_key} {time_key}", fmt)
        except ValueError:
            continue
    return None


def flatten_history(nested: dict[str, Any]) -> FlattenResult:
    """
    Flatten history nested by date/time into a DataFrame.

    Output columns:
      - dt (datetime)
      - date_key, time_key
      - rawGas, temperature, humidity, emissionScore
      - timestamp (string as stored)
    """
    rows: list[dict[str, Any]] = []
    dropped = 0

    for date_key, times in (nested or {}).items():
        if not isinstance(times, dict):
            continue
        for time_key, payload in times.items():
            if not isinstance(payload, dict):
                continue

            dt = _parse_datetime(str(date_key), str(time_key))
            if dt is None:
                dropped += 1
                continue

            rows.append(
                {
                    "dt": dt,
                    "date_key": str(date_key),
                    "time_key": str(time_key),
                    "rawGas": payload.get("rawGas", None),
                    "temperature": payload.get("temperature", None),
                    "humidity": payload.get("humidity", None),
                    "emissionScore": payload.get("emissionScore", None),
                    "timestamp": payload.get("timestamp", None),
                }
            )

    if not rows:
        df = pd.DataFrame(
            columns=[
                "dt",
                "date_key",
                "time_key",
                "rawGas",
                "temperature",
                "humidity",
                "emissionScore",
                "timestamp",
            ]
        )
        return FlattenResult(df=df, dropped_rows=dropped)

    df = pd.DataFrame(rows)

    # Coerce numeric.
    for col in ("rawGas", "temperature", "humidity", "emissionScore"):
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.sort_values("dt").reset_index(drop=True)
    return FlattenResult(df=df, dropped_rows=dropped)

