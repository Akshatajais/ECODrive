from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class SessionConfig:
    min_len: int = 50
    max_len: int = 100
    # If there is a gap larger than this, start a new session.
    gap_seconds: int = 120


def build_sessions(df: pd.DataFrame, cfg: SessionConfig) -> list[pd.DataFrame]:
    """
    Split a time-ordered DataFrame into sessions, then chunk to [min_len, max_len].

    Assumptions:
    - `df` contains a `dt` datetime column and is sorted ascending.
    - Sampling is roughly 5–10 seconds; gaps imply separate drives.
    """
    if df.empty:
        return []

    d = df.sort_values("dt").reset_index(drop=True)
    deltas = d["dt"].diff().dt.total_seconds().fillna(0).to_numpy()
    split_idx = np.where(deltas > cfg.gap_seconds)[0]

    # Build contiguous drive segments.
    segments: list[pd.DataFrame] = []
    start = 0
    for idx in split_idx:
        seg = d.iloc[start:idx].reset_index(drop=True)
        if len(seg) > 0:
            segments.append(seg)
        start = idx
    last = d.iloc[start:].reset_index(drop=True)
    if len(last) > 0:
        segments.append(last)

    sessions: list[pd.DataFrame] = []
    for seg in segments:
        sessions.extend(_chunk_segment(seg, cfg.min_len, cfg.max_len))
    return sessions


def _chunk_segment(seg: pd.DataFrame, min_len: int, max_len: int) -> list[pd.DataFrame]:
    n = len(seg)
    if n < min_len:
        return []

    out: list[pd.DataFrame] = []
    i = 0
    while i < n:
        remaining = n - i
        if remaining < min_len:
            break
        take = min(max_len, remaining)
        window = seg.iloc[i : i + take].reset_index(drop=True)
        out.append(window)
        i += take
    return out


def sessions_to_long_df(sessions: Iterable[pd.DataFrame]) -> pd.DataFrame:
    rows: list[pd.DataFrame] = []
    for sid, s in enumerate(sessions):
        ss = s.copy()
        ss["session_id"] = sid
        ss["t"] = np.arange(len(ss))
        rows.append(ss)
    if not rows:
        return pd.DataFrame()
    return pd.concat(rows, ignore_index=True)

