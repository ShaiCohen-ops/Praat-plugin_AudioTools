"""Project folder structure, per-project state, and naming rules."""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

from . import config

SUBDIRS = ["originals", "autosaved_wav", "latest", "project_state", "logs", "tmp"]
TS_FORMAT = "%Y-%m-%d_%H-%M-%S"
TS_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_(.+)\.wav$")

# Windows reserved device names (case-insensitive)
_WIN_RESERVED = {
    "CON", "PRN", "AUX", "NUL",
    *{f"COM{i}" for i in range(1, 10)}, *{f"LPT{i}" for i in range(1, 10)},
}


def timestamp_now() -> str:
    return time.strftime(TS_FORMAT)


def sanitize_name(name: str) -> str:
    """Praat object name -> filename-safe base, valid on Win/mac/Linux."""
    safe = re.sub(r"[^A-Za-z0-9_\-]+", "_", name).strip("._ ")
    safe = safe[:100] or "unnamed"
    if safe.upper() in _WIN_RESERVED:
        safe = "snd_" + safe
    return safe


def dedupe(names: list) -> list:
    """Make a list of sanitized names unique by suffixing _2, _3, ..."""
    seen, out = {}, []
    for n in names:
        if n not in seen:
            seen[n] = 1
            out.append(n)
        else:
            seen[n] += 1
            candidate = f"{n}_{seen[n]}"
            while candidate in seen:
                seen[n] += 1
                candidate = f"{n}_{seen[n]}"
            seen[candidate] = 1
            out.append(candidate)
    return out


class Project:
    def __init__(self, root: Path):
        self.root = Path(root).expanduser().resolve()
        self.name = self.root.name

    # -------------------------------------------------------- paths
    @property
    def originals(self) -> Path:       return self.root / "originals"
    @property
    def autosaved(self) -> Path:       return self.root / "autosaved_wav"
    @property
    def latest(self) -> Path:          return self.root / "latest"
    @property
    def state_dir(self) -> Path:       return self.root / "project_state"
    @property
    def logs(self) -> Path:            return self.root / "logs"
    @property
    def tmp(self) -> Path:             return self.root / "tmp"
    @property
    def session_path(self) -> Path:    return self.state_dir / "last_session.json"
    @property
    def backup_index_path(self) -> Path:
        return self.state_dir / "backup_index.json"
    @property
    def log_path(self) -> Path:        return self.logs / "autosave_log.txt"

    # -------------------------------------------------------- lifecycle
    @classmethod
    def create(cls, root: Path) -> "Project":
        p = cls(root)
        for d in SUBDIRS:
            (p.root / d).mkdir(parents=True, exist_ok=True)
        if not p.session_path.exists():
            p.write_session({
                "project_name": p.name,
                "project_folder": str(p.root),
                "last_autosave_time": "",
                "latest_files": [],
                "object_names": [],
                "autosave_interval_minutes":
                    config.load_config()["autosave_interval_minutes"],
                "praat_path": config.load_config()["praat_path"],
                "sendpraat_path": config.load_config()["sendpraat_path"],
            })
        return p

    def is_valid(self) -> bool:
        return self.session_path.exists()

    # -------------------------------------------------------- state
    def read_session(self) -> dict:
        return config._read_json(self.session_path, {})

    def write_session(self, data: dict) -> None:
        config._write_json_atomic(self.session_path, data)

    def update_session(self, **kw) -> dict:
        s = self.read_session()
        s.update(kw)
        self.write_session(s)
        return s

    def read_backup_index(self) -> dict:
        return config._read_json(self.backup_index_path, {"cycles": []})

    def append_backup_cycle(self, ts: str, entries: list) -> None:
        idx = self.read_backup_index()
        idx["cycles"].append({"timestamp": ts, "files": entries})
        idx["cycles"] = idx["cycles"][-500:]   # bound the index file
        config._write_json_atomic(self.backup_index_path, idx)

    # -------------------------------------------------------- backups
    def list_backup_timestamps(self) -> list:
        """Distinct cycle timestamps found in autosaved_wav/, newest first."""
        stamps = set()
        if self.autosaved.is_dir():
            for f in self.autosaved.iterdir():
                m = TS_RE.match(f.name)
                if m:
                    stamps.add(m.group(1))
        return sorted(stamps, reverse=True)

    def files_for_timestamp(self, ts: str) -> list:
        out = []
        if self.autosaved.is_dir():
            for f in sorted(self.autosaved.iterdir()):
                m = TS_RE.match(f.name)
                if m and m.group(1) == ts:
                    out.append((f, m.group(2)))   # (path, base name)
        return out

    def latest_files(self) -> list:
        """[(path, object base name)] from latest/."""
        out = []
        if self.latest.is_dir():
            for f in sorted(self.latest.glob("*_latest.wav")):
                out.append((f, f.name[:-len("_latest.wav")]))
        return out

    # -------------------------------------------------------- tmp hygiene
    def clean_tmp(self, logger=None) -> int:
        """Remove stale temp files (crash leftovers / failed cycles)."""
        n = 0
        if self.tmp.is_dir():
            for f in self.tmp.iterdir():
                try:
                    if f.is_file():
                        f.unlink()
                        n += 1
                except OSError as e:
                    if logger:
                        logger.warning("could not remove temp file %s: %s", f, e)
        else:
            self.tmp.mkdir(parents=True, exist_ok=True)
        if n and logger:
            logger.info("cleaned %d stale temp file(s) from tmp/", n)
        return n
