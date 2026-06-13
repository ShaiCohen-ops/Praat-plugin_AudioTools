"""Launching Praat and sending scripts to the running instance.

Transport order:
  1. `praat --send job.praat`  (built into Praat 6.x, no extra install)
  2. `sendpraat praat 'runScript: "job.praat"'`  (if configured)

All jobs are real .praat files written into <project>/tmp/ and the
running Praat executes them on its GUI thread. Completion is detected
by a marker file the job writes as its last action; absence of the
marker within the timeout means Praat is busy, frozen, or gone.
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

TEMPLATE_DIR = Path(__file__).parent / "praat_scripts"

MIN_SEND_VERSION = (6, 2)      # praat --send exists from Praat 6.2


def praat_version(praat_path: str):
    """Return (major, minor) of the Praat executable, or None if unknown.
    Uses `praat --version`, which prints and exits in all modern versions."""
    try:
        r = subprocess.run([resolve_executable(praat_path), "--version"],
                           capture_output=True, timeout=10)
        m = re.search(rb"(\d+)\.(\d+)", r.stdout + r.stderr)
        if m:
            return (int(m.group(1)), int(m.group(2)))
    except (subprocess.TimeoutExpired, OSError):
        pass
    return None


def praat_quote(p) -> str:
    """Path/str -> safe Praat double-quoted string content."""
    return str(p).replace("\\", "/").replace('"', '""')


def resolve_executable(praat_path: str) -> str:
    """Accept a mac .app bundle path and resolve to the inner binary."""
    p = Path(praat_path)
    if sys.platform == "darwin" and p.suffix == ".app":
        inner = p / "Contents" / "MacOS" / "Praat"
        if inner.exists():
            return str(inner)
    return str(p)


def render_template(name: str, mapping: dict) -> str:
    text = (TEMPLATE_DIR / name).read_text(encoding="utf-8")
    for key, value in mapping.items():
        text = text.replace("%" + key + "%", value)
    return text


class PraatLink:
    def __init__(self, praat_path: str, sendpraat_path: str = "",
                 job_timeout: int = 90, logger=None):
        self.praat_path = resolve_executable(praat_path)
        self.sendpraat_path = sendpraat_path.strip()
        self.job_timeout = job_timeout
        self.logger = logger
        self.process = None          # Popen handle if WE launched Praat

    # ----------------------------------------------------------- launch
    def launch(self):
        """Start the Praat GUI and keep the process handle."""
        self.process = subprocess.Popen([self.praat_path])
        return self.process

    def launch_and_attach(self, tmp_dir: Path, total: int = 90) -> bool:
        """Start Praat (or attach to an already-running instance) without
        any startup race: the FIRST `--send` ping is itself the launcher.

        - If no Praat is running, `praat --send ping.praat` becomes the
          GUI instance (runs the ping at startup, stays open); we keep
          its process handle.
        - If Praat is already running, the helper forwards the ping and
          exits; we attach (no process handle, ping still proves life).

        NOTHING IS EVER KILLED HERE."""
        if self.sendpraat_path:
            self.launch()
            return self.wait_until_responsive(tmp_dir, total)

        tmp_dir.mkdir(parents=True, exist_ok=True)
        pong = tmp_dir / "pong.txt"
        try:
            pong.unlink()
        except FileNotFoundError:
            pass
        job_path = tmp_dir / "ping_job.praat"
        job_path.write_text(
            render_template("ping_job.template.praat",
                            {"PONG_PATH": praat_quote(pong)}),
            encoding="utf-8")

        try:
            proc = subprocess.Popen([self.praat_path, "--send",
                                     str(job_path)])
        except OSError as e:
            if self.logger:
                self.logger.error("could not start Praat: %s", e)
            return False

        deadline = time.monotonic() + total
        while time.monotonic() < deadline:
            if pong.exists():
                if proc.poll() is None:
                    self.process = proc          # we ARE the GUI instance
                    if self.logger:
                        self.logger.info("launched new Praat instance")
                else:
                    self.process = None          # attached to existing GUI
                    if self.logger:
                        self.logger.info("attached to running Praat")
                try:
                    pong.unlink()
                except FileNotFoundError:
                    pass
                return True
            rc = proc.poll()
            if rc is not None and rc != 0:
                if self.logger:
                    self.logger.error("Praat exited with code %d during "
                                      "startup ping", rc)
                return False
            time.sleep(0.5)
        if self.logger:
            self.logger.error("Praat gave no answer within %d s "
                              "(process left untouched)", total)
        return False

    def praat_alive(self) -> bool:
        """True if the Praat process we launched is still running.
        If we did not launch it (None), fall back to 'unknown -> True'
        and let ping decide responsiveness."""
        if self.process is None:
            return True
        return self.process.poll() is None

    # ----------------------------------------------------------- send
    def _dispatch(self, job_path: Path) -> bool:
        """Hand the job script to the running Praat.

        SAFETY RULE: a `praat --send` helper process is NEVER killed.
        If no instance is found, the helper BECOMES a Praat GUI - and a
        GUI the user may be working in must never be terminated. If the
        helper neither exits nor is needed, we leave it alone and let
        the done-marker decide whether the job actually ran."""
        if self.sendpraat_path:
            # sendpraat is a tiny CLI tool: a run-with-timeout is safe.
            try:
                cmd = [self.sendpraat_path, "praat",
                       f'runScript: "{praat_quote(job_path)}"']
                r = subprocess.run(cmd, capture_output=True, timeout=12)
                if r.returncode != 0 and self.logger:
                    self.logger.warning(
                        "sendpraat returned %d: %s", r.returncode,
                        r.stderr.decode(errors="replace").strip())
                return r.returncode == 0
            except (subprocess.TimeoutExpired, OSError) as e:
                if self.logger:
                    self.logger.error("sendpraat failed: %s", e)
                return False

        try:
            proc = subprocess.Popen([self.praat_path, "--send",
                                     str(job_path)])
        except OSError as e:
            if self.logger:
                self.logger.error("transport failed: %s", e)
            return False

        grace = time.monotonic() + 10
        while time.monotonic() < grace:
            rc = proc.poll()
            if rc is not None:
                if rc != 0 and self.logger:
                    self.logger.warning("--send helper exited with %d", rc)
                return rc == 0
            time.sleep(0.25)

        # Helper still running after the grace period: it most likely
        # became a Praat GUI instance because none was found. Adopt it
        # as our instance if we have none; NEVER kill it.
        if self.process is None or self.process.poll() is not None:
            self.process = proc
            if self.logger:
                self.logger.info("--send helper became the Praat instance; "
                                 "adopted its process handle")
        elif self.logger:
            self.logger.warning("--send helper still running; leaving it "
                                "untouched (done-marker will decide)")
        return True

    def run_job(self, job_text: str, job_path: Path, done_path: Path,
                timeout: int = None) -> bool:
        """Write the job, send it, and wait for its done-marker file.
        Returns True only when the marker appears (job fully completed)."""
        timeout = timeout or self.job_timeout
        try:
            done_path.unlink()
        except FileNotFoundError:
            pass
        job_path.parent.mkdir(parents=True, exist_ok=True)
        job_path.write_text(job_text, encoding="utf-8")

        if not self._dispatch(job_path):
            return False

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if done_path.exists():
                return True
            if not self.praat_alive():
                return False           # crashed mid-job
            time.sleep(0.5)
        return False                   # unresponsive (busy or frozen)

    # ----------------------------------------------------------- ping
    def ping(self, tmp_dir: Path, timeout: int = 15) -> bool:
        pong = tmp_dir / "pong.txt"
        job = render_template("ping_job.template.praat",
                              {"PONG_PATH": praat_quote(pong)})
        ok = self.run_job(job, tmp_dir / "ping_job.praat", pong, timeout)
        try:
            pong.unlink()
        except FileNotFoundError:
            pass
        return ok

    def wait_until_responsive(self, tmp_dir: Path, total: int = 60) -> bool:
        """After launching, poll until Praat answers a ping."""
        deadline = time.monotonic() + total
        while time.monotonic() < deadline:
            if not self.praat_alive():
                return False
            if self.ping(tmp_dir, timeout=8):
                return True
            time.sleep(1.0)
        return False

    # ----------------------------------------------------------- quit
    def quit_praat(self, tmp_dir: Path, timeout: int = 20) -> bool:
        """Gracefully close Praat by sending it a Quit script. The job
        writes its acknowledgement marker BEFORE quitting, so a True
        return means Praat received the request. Praat is never killed."""
        ack = tmp_dir / "quit_ack.txt"
        job = (f'writeFileLine: "{praat_quote(ack)}", "bye"\n'
               f'Quit\n')
        ok = self.run_job(job, tmp_dir / "quit_job.praat", ack, timeout)
        try:
            ack.unlink()
        except FileNotFoundError:
            pass
        return ok

    # ----------------------------------------------------------- load
    def load_files(self, pairs: list, tmp_dir: Path) -> bool:
        """pairs = [(wav_path, praat_object_name)]; loads into running Praat."""
        lines = []
        for wav, objname in pairs:
            lines.append(f'nocheck Read from file: "{praat_quote(wav)}"')
            lines.append('if numberOfSelected ("Sound") = 1')
            lines.append(f'    Rename: "{praat_quote(objname)}"')
            lines.append("endif")
        done = tmp_dir / "load_done.txt"
        job = render_template("load_job.template.praat", {
            "LOAD_LINES": "\n".join(lines),
            "DONE_PATH": praat_quote(done),
        })
        ok = self.run_job(job, tmp_dir / "load_job.praat", done,
                          timeout=max(self.job_timeout, 120))
        try:
            done.unlink()
        except FileNotFoundError:
            pass
        return ok
