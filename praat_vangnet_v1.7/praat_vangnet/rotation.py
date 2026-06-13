"""Backup rotation: prune old autosave cycles per the retention policy.

Protected cycles (never deleted):
  - the newest `keep_last_cycles` cycles
  - if keep_hourly_today: the newest cycle of each hour of today
  - if keep_daily: the newest cycle of each previous day
originals/ and latest/ are never touched by rotation.
"""

from __future__ import annotations

import time

from .project import Project


def _cycle_key(ts: str) -> tuple:
    # ts = "YYYY-MM-DD_HH-MM-SS"
    return (ts[:10], ts[11:13])     # (day, hour)


def backup_usage(project: Project) -> tuple:
    """(number of backup files, total bytes) in autosaved_wav/."""
    n, size = 0, 0
    if project.autosaved.is_dir():
        for f in project.autosaved.glob("*.wav"):
            try:
                size += f.stat().st_size
                n += 1
            except OSError:
                pass
    return n, size


def prune_keep_n(project: Project, keep_n: int, logger=None) -> tuple:
    """Manually delete all backup cycles except the newest keep_n.
    keep_n=0 deletes ALL timestamped backups.
    NEVER touches latest/ or originals/.
    Returns (files_deleted, bytes_freed)."""
    keep_n = max(0, int(keep_n))
    stamps = project.list_backup_timestamps()          # newest first
    deleted, freed = 0, 0
    for ts in stamps[keep_n:]:
        for path, _base in project.files_for_timestamp(ts):
            try:
                freed += path.stat().st_size
                path.unlink()
                deleted += 1
            except OSError as e:
                if logger:
                    logger.warning("cleanup could not delete %s: %s",
                                   path, e)
    if logger:
        logger.info("manual cleanup: removed %d file(s), freed %.1f MB, "
                    "kept newest %d cycle(s)",
                    deleted, freed / 1e6, keep_n)
    return deleted, freed


def rotate(project: Project, retention: dict, logger=None) -> int:
    keep_last = int(retention.get("keep_last_cycles", 20))
    hourly_today = bool(retention.get("keep_hourly_today", True))
    daily = bool(retention.get("keep_daily", True))

    stamps = project.list_backup_timestamps()      # newest first
    if len(stamps) <= keep_last:
        return 0

    today = time.strftime("%Y-%m-%d")
    protected = set(stamps[:keep_last])

    if hourly_today:
        seen_hours = set()
        for ts in stamps:                          # newest first
            day, hour = _cycle_key(ts)
            if day == today and hour not in seen_hours:
                seen_hours.add(hour)
                protected.add(ts)

    if daily:
        seen_days = set()
        for ts in stamps:                          # newest of each day
            day, _ = _cycle_key(ts)
            if day not in seen_days:
                seen_days.add(day)
                protected.add(ts)

    deleted = 0
    for ts in stamps:
        if ts in protected:
            continue
        for path, _base in project.files_for_timestamp(ts):
            try:
                path.unlink()
                deleted += 1
            except OSError as e:
                if logger:
                    logger.warning("rotation could not delete %s: %s", path, e)
    if deleted and logger:
        logger.info("rotation removed %d file(s) from old cycles", deleted)
    return deleted
