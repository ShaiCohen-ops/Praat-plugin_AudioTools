"""The autosave engine: background loop, atomic save cycle, crash watch."""

from __future__ import annotations

import logging
import shutil
import struct
import threading
import time
from pathlib import Path

from . import config, rotation
from .praat_link import PraatLink, praat_quote, render_template
from .project import Project, dedupe, sanitize_name, timestamp_now

MIN_WAV_BYTES = 45      # RIFF header is 44 bytes; demand at least 1 data byte


def make_logger(project: Project) -> logging.Logger:
    logger = logging.getLogger(f"autosave.{project.name}")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        project.logs.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(project.log_path, encoding="utf-8")
        fh.setFormatter(logging.Formatter(
            "%(asctime)s [%(levelname)s] " + project.name + ": %(message)s"))
        logger.addHandler(fh)
        sh = logging.StreamHandler()
        sh.setFormatter(logging.Formatter("  [autosave] %(message)s"))
        logger.addHandler(sh)
    return logger


def wav_looks_valid(path: Path) -> bool:
    try:
        if path.stat().st_size < MIN_WAV_BYTES:
            return False
        with open(path, "rb") as f:
            head = f.read(12)
        return head[:4] == b"RIFF" and head[8:12] == b"WAVE"
    except OSError:
        return False


class AutosaveManager:
    """Runs autosave cycles on a background thread."""

    def __init__(self, project: Project, link: PraatLink, cfg: dict):
        self.project = project
        self.link = link
        self.cfg = cfg
        self.logger = make_logger(project)
        link.logger = self.logger
        self.interval_s = 60 * float(
            project.read_session().get("autosave_interval_minutes")
            or cfg["autosave_interval_minutes"])
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread = None
        self._cycle_lock = threading.Lock()
        self.praat_crashed = False

    # ------------------------------------------------------------ control
    def start(self):
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        self.logger.info("autosave loop started (interval %.0f s)",
                         self.interval_s)

    def stop(self, wait: bool = True):
        """Stop safely: never interrupts a cycle midway (the lock)."""
        self._stop.set()
        self._wake.set()
        if wait and self._thread:
            self._thread.join(timeout=self.cfg["job_timeout_seconds"] + 30)
        self.logger.info("autosave loop stopped")

    def save_now(self):
        self._wake.set()

    def set_interval_minutes(self, minutes: float):
        self.interval_s = max(0.5, minutes) * 60
        self.project.update_session(autosave_interval_minutes=minutes)
        self.logger.info("autosave interval set to %.1f minute(s)", minutes)

    def is_busy_saving(self) -> bool:
        if self._cycle_lock.acquire(blocking=False):
            self._cycle_lock.release()
            return False
        return True

    # ------------------------------------------------------------ loop
    def _run(self):
        while not self._stop.is_set():
            triggered = self._wake.wait(timeout=self.interval_s)
            self._wake.clear()
            if self._stop.is_set():
                break
            if not self.link.praat_alive():
                self._handle_crash()
                break
            self.run_cycle(manual=triggered)
            if self.praat_crashed:
                break

    def _handle_crash(self):
        self.praat_crashed = True
        self.logger.error(
            "PRAAT CRASHED or was closed: autosave loop stopping; "
            "the last successful backup in latest/ is preserved untouched")

    # ------------------------------------------------------------ cycle
    def run_cycle(self, manual: bool = False, history: bool = True) -> bool:
        """history=False (used by the exit flow) updates latest/ only,
        without writing a timestamped cycle into autosaved_wav/."""
        with self._cycle_lock:
            return self._cycle_inner(manual, history)

    def _cycle_inner(self, manual: bool, history: bool) -> bool:
        ts = timestamp_now()
        self.logger.info("autosave started (%s%s)",
                         "manual" if manual else "scheduled",
                         "" if history else ", latest only")

        # 1. clean previous temp artefacts so leftovers can't be mistaken
        self.project.clean_tmp(self.logger)
        tmp = self.project.tmp
        manifest = tmp / "manifest.txt"
        done = tmp / "done.txt"

        # 2. send the export job to Praat
        job = render_template("autosave_job.template.praat",
                              {"TMP_DIR": praat_quote(tmp)})
        ok = self.link.run_job(job, tmp / "autosave_job.praat", done)

        if not ok:
            if not self.link.praat_alive():
                self._handle_crash()
            else:
                self.logger.error(
                    "Praat UNRESPONSIVE: no reply within %d s; latest/ NOT "
                    "updated, previous backup preserved; will retry next cycle",
                    self.cfg["job_timeout_seconds"])
            self.project.clean_tmp(self.logger)   # remove partial temp WAVs
            return False

        # 3. read the manifest Praat wrote
        entries = []      # (index, saved_ok, original object name)
        try:
            for line in manifest.read_text(encoding="utf-8").splitlines():
                parts = line.split("\t", 2)
                if len(parts) == 3:
                    entries.append((int(parts[0]), parts[1] == "1", parts[2]))
        except (OSError, ValueError) as e:
            self.logger.error("manifest unreadable (%s); latest/ NOT updated", e)
            self.project.clean_tmp(self.logger)
            return False

        self.logger.info("Praat responded: %d Sound object(s) found",
                         len(entries))
        if not entries:
            self.project.update_session(last_autosave_time=ts)
            self.logger.info("nothing to save; latest/ unchanged")
            return True

        # 4. verify temp WAVs, then move into autosaved_wav/ + latest/
        bases = dedupe([sanitize_name(name) for _, _, name in entries])
        self.project.autosaved.mkdir(parents=True, exist_ok=True)
        self.project.latest.mkdir(parents=True, exist_ok=True)

        saved, failed, cycle_files, latest_list, obj_names = 0, 0, [], [], []
        for (idx, praat_ok, orig_name), base in zip(entries, bases):
            src = tmp / f"snd_{idx:04d}.wav"
            if not praat_ok or not wav_looks_valid(src):
                failed += 1
                self.logger.error("object '%s' NOT saved (Praat status=%s, "
                                  "file valid=%s)", orig_name, praat_ok,
                                  wav_looks_valid(src))
                continue

            latest_final = self.project.latest / f"{base}_latest.wav"
            latest_tmp = self.project.latest / f".{base}_latest.wav.part"

            if history:
                dest = self.project.autosaved / f"{ts}_{base}.wav"
                n = 2
                while dest.exists():                   # never overwrite
                    dest = self.project.autosaved / f"{ts}_{base}_{n}.wav"
                    n += 1
                shutil.move(str(src), str(dest))
                # atomic latest/ update: copy to temp, then os.replace
                shutil.copy2(str(dest), str(latest_tmp))
                latest_tmp.replace(latest_final)
                cycle_files.append(dest.name)
                self.logger.info("saved: %s  ->  latest/%s",
                                 dest.name, latest_final.name)
            else:
                # latest-only (exit flow): move straight into latest/,
                # still via temp name + atomic replace
                shutil.move(str(src), str(latest_tmp))
                latest_tmp.replace(latest_final)
                self.logger.info("saved (latest only): latest/%s",
                                 latest_final.name)

            saved += 1
            latest_list.append(latest_final.name)
            obj_names.append(orig_name)

        # 5. bookkeeping (only after at least one confirmed save)
        if saved:
            self.project.update_session(
                last_autosave_time=ts,
                latest_files=latest_list,
                object_names=obj_names,
            )
            config.record_save_time(self.project.root, ts)
            if history:
                self.project.append_backup_cycle(ts, cycle_files)
                rotation.rotate(self.project, self.cfg["retention"],
                                self.logger)

        self.project.clean_tmp(self.logger)
        self.logger.info(
            "autosave finished: %d saved, %d failed, latest/ %s",
            saved, failed, "updated" if saved else "NOT updated")
        return failed == 0
