"""Global configuration and the recent-projects registry.

Global app data lives OUTSIDE any project (~/Praat_Vangnet/, or the
legacy ~/PraatAutosave/ if it already exists):
    config.json           - praat path, sendpraat path, defaults
    recent_projects.json  - last opened project, recents, last save times
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

def _app_dir() -> Path:
    """Global data dir. Existing installs keep ~/PraatAutosave so that
    projects, settings, and recents survive the rename to Praat_Vangnet;
    fresh installs use ~/Praat_Vangnet."""
    legacy = Path.home() / "PraatAutosave"
    if legacy.is_dir():
        return legacy
    return Path.home() / "Praat_Vangnet"


APP_DIR = _app_dir()
CONFIG_PATH = APP_DIR / "config.json"
RECENTS_PATH = APP_DIR / "recent_projects.json"

DEFAULT_CONFIG = {
    "praat_path": "",                 # set on first run / via menu
    "sendpraat_path": "",             # optional fallback transport
    "projects_dir": str(APP_DIR / "Projects"),
    "autosave_interval_minutes": 5,
    "job_timeout_seconds": 90,        # how long Praat may take to answer
    "retention": {
        "keep_last_cycles": 20,
        "keep_hourly_today": True,
        "keep_daily": True,
    },
}


def _read_json(path: Path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return json.loads(json.dumps(fallback))  # deep copy


def _write_json_atomic(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)  # atomic on the same volume


def load_config() -> dict:
    cfg = _read_json(CONFIG_PATH, DEFAULT_CONFIG)
    # fill any keys added in newer versions
    for k, v in DEFAULT_CONFIG.items():
        cfg.setdefault(k, v)
    for k, v in DEFAULT_CONFIG["retention"].items():
        cfg["retention"].setdefault(k, v)
    return cfg


def save_config(cfg: dict) -> None:
    _write_json_atomic(CONFIG_PATH, cfg)


# ---------------------------------------------------------------- recents

def load_recents() -> dict:
    return _read_json(RECENTS_PATH, {
        "last_opened_project": "",
        "recent_projects": [],            # list of folder paths, newest first
        "last_save_times": {},            # folder path -> ISO timestamp
        "inactive_projects": [],          # cleaned (originals kept) projects
    })


def save_recents(rec: dict) -> None:
    _write_json_atomic(RECENTS_PATH, rec)


def remember_project(folder: Path, opened: bool = True) -> None:
    rec = load_recents()
    s = str(folder)
    rec["recent_projects"] = [s] + [p for p in rec["recent_projects"] if p != s]
    rec["recent_projects"] = rec["recent_projects"][:15]
    if opened:
        rec["last_opened_project"] = s
    if s in rec.get("inactive_projects", []):
        rec["inactive_projects"].remove(s)
    save_recents(rec)


def record_save_time(folder: Path, iso_time: str) -> None:
    rec = load_recents()
    rec.setdefault("last_save_times", {})[str(folder)] = iso_time
    save_recents(rec)


def forget_project(folder: Path, mark_inactive: bool = False) -> None:
    rec = load_recents()
    s = str(folder)
    if mark_inactive:
        if s not in rec.setdefault("inactive_projects", []):
            rec["inactive_projects"].append(s)
    else:
        rec["recent_projects"] = [p for p in rec["recent_projects"] if p != s]
        rec.get("last_save_times", {}).pop(s, None)
        if s in rec.get("inactive_projects", []):
            rec["inactive_projects"].remove(s)
    if rec.get("last_opened_project") == s and not mark_inactive:
        rec["last_opened_project"] = ""
    save_recents(rec)


def default_praat_candidates() -> list:
    """Best-guess Praat executable locations per platform."""
    if sys.platform.startswith("win"):
        return [
            r"C:\Program Files\Praat\Praat.exe",
            r"C:\Program Files (x86)\Praat\Praat.exe",
            str(Path.home() / "Praat.exe"),
            str(Path.home() / "Desktop" / "Praat.exe"),
        ]
    if sys.platform == "darwin":
        return [
            "/Applications/Praat.app/Contents/MacOS/Praat",
            str(Path.home() / "Applications/Praat.app/Contents/MacOS/Praat"),
        ]
    return ["/usr/bin/praat", "/usr/local/bin/praat",
            str(Path.home() / "praat")]
