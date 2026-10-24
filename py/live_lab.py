#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      live_lab.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.1.1 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Praat AudioTools Live Lab - MIDI-controlled live capture,
#   Praat analysis-resynthesis and multichannel one-shot performance.
#
#   LIVE INPUT -> HOLD TO RECORD -> PRAAT PROCESSING (isolated worker)
#              -> RESULT BANK -> ONE-SHOT PLAYBACK / CROSSFADE
#
#   Started by Live_Lab.praat (in py/ or Vector Chain/), never by hand:
#     python live_lab.py --plugin-dir DIR --chain-dir DIR
#                        --error-file FILE [--praat-hint EXE]
#
#   Built on the Performance Launcher architecture (performance_launcher.py
#   v1.7.3): same ASIO enabling, host-API device identity, verified MIDI
#   port handling, focus guard, lock-free status surfacing from the audio
#   callback, and config persistence in plugin_AudioTools.
#
# Architecture (three independent responsibilities):
#   Capture Engine   - inside the single full-duplex PortAudio callback:
#                      pre-roll ring + preallocated capture buffers. No disk
#                      I/O; a writer thread turns finished buffers into WAVs.
#   Praat Worker     - ONE headless Praat process per job running the worker
#                      script embedded below (WORKER_PRAAT), FIFO queue, one
#                      job at a time, lowered CPU priority, kill-on-close job
#                      object (Windows) / process group (POSIX), timeout.
#   Playback Engine  - one-shot voices mapped through an explicit routing
#                      matrix into the physical output space, THEN faded
#                      (equal-power), trimmed and metered.
#
# LATEST CAPTURE PRIORITY (deterministic rule, documented in README too):
#   Every performance decision receives the next decision number:
#   starting a capture (pedal/F press), Regenerate, manual Play/Retrigger,
#   manual Crossfade, Stop All. A job stores the number of the decision
#   that created it (its capture start, or its Regenerate press).
#   When a job finishes processing and its audio is fully loaded, it
#   auto-plays (crossfade) ONLY IF all of these hold:
#     1. its policy, frozen when its recording started, is AUTO;
#     2. Auto Suspend is off at completion time;
#     3. its decision number is still the latest one (nothing newer was
#        decided while it was processing - no newer capture, no manual
#        playback action, no Regenerate, no Stop All).
#   Otherwise it enters the bank as READY. Completion order is irrelevant,
#   so a slow older job can never override a newer decision.
#
# ZERO-RESIDUE: every temporary file lives in one session workspace
#   <system temp>/PraatAudioToolsLiveLab/session_<stamp>_<pid>_<rand>/
#   held by an OS file lock while the session runs. It is deleted on close,
#   files are deleted as soon as they are no longer needed, and at the next
#   launch any workspace whose lock is free (owner dead) is removed. Nothing
#   else in the temp folder is ever touched. Only live_lab_config.json (in
#   plugin_AudioTools) and explicitly exported audio persist.
#
# Changelog v1.1.1 (second review - targeted fixes, architecture and UI unchanged):
#   - FIX: a stream that was created but failed in start() was dropped
#     without close() (reproduced; would keep an ASIO driver busy). The
#     stream is now held locally and aborted + closed on any failure.
#   - FIX: the output protection was a block-rate gain plus np.clip, so
#     transients at a block boundary were hard-clipped (14-17 samples
#     measured) and quiet material earlier in the same block was ducked.
#     Replaced by a true lookahead peak limiter (2 ms delay, 1 ms smooth
#     attack that finishes before the peak, 250 ms linear release). Gain is
#     provably <= ceiling/|x|, so no clipping happens; the clamp remains as
#     a numerical backstop with a counter (measured: 0 samples). Below the
#     ceiling the output is bit-identical to the input, delayed by 2 ms.
#   - FIX: atexit removed the workspace unconditionally, even when the
#     shutdown kept it because the capture writer was still busy. The
#     workspace now has an explicit CLEANUP_PENDING state that every
#     removal path (atexit included) honours; the next launch removes it.
#   - FIX: Apply in Setup > Audio (and Capture / Routing changes that need a
#     stream restart) changed the configuration before checking whether a
#     restart was possible. Now transactional: busy -> nothing changes;
#     the proposal is opened first and committed only if the stream
#     started; on failure the previous settings are reopened.
#   - Each Praat worker gets TEMP / TMP / TMPDIR pointing into its job
#     folder, so module temp files are deleted with the job.
#   - Verified at runtime (Linux, Praat 7.0 and 6.4.63, DISPLAY unset so any
#     window would fail the run): all nine chains run OK, write no file
#     outside their job folder (none inside it either besides the result),
#     and leave the plugin folder, HOME and the temp folder unchanged.
#   - Correction: Live 4-6 reproduce bit-identically on the same Praat
#     build; across builds only to within 1 float32 LSB (see below).
#
# Changelog v1.1 (external review fixes - architecture and UI unchanged):
#   - FIX (review 1): equal-power crossfades of correlated material rose
#     +3 dB (0.8 + 0.8 -> 1.131 peak, reproduced). Crossfading a result into
#     itself now uses the constant-amplitude law, and a safety limiter
#     (default on, ceiling -0.3 dBFS, Setup > Routing) catches every other
#     over. It is bit-transparent below the ceiling (tested).
#   - FIX (review 2): Windows job object - explicit ctypes signatures
#     (64-bit HANDLEs), IsProcessInJob verification, and a worker that
#     cannot be protected is killed and its job fails with the reason.
#   - FIX (review 3): shutdown waits for the capture writer (up to 30 s),
#     pending takes are discarded instead of written, and the workspace is
#     never deleted while the writer may still use it.
#   - FIX (review 4): results handed to the audio callback but not yet
#     voiced are protected from bank eviction.
#   - FIX (review 5): FINALIZING state - an audio restart waits until a
#     released take is saved; finished takes survive a restart and carry
#     their own sample rate; stale capture buffers are not reused.
#   - FIX (review 6): positive completion report (--done-file); Praat only
#     says "closed cleanly" when it exists. Launch files no longer need a
#     folder (Praat cannot delete folders).
#   - NEW (review A): the worker seeds Praat's generator from the take's
#     seed. Measured: Live 4/5/6 now reproduce bit-identically on the same
#     Praat build (SHA-256 of the samples; v1.1.1 correction: across 6.4.63
#     and 7.0 they agree to within 1 float32 LSB, -138 dB, but are not always
#     bit-identical); Live 1-3 and the Random chains cannot, because
#     their modules are called with Seed 0 and re-randomize by design.
#     Seed column marks reproducible results with a check mark.
#   - NEW (review B): Setup > Audio states Stereo capture -> mono processing.
#   - NEW (review C): pre-flight also verifies NoDraw - no drawing commands
#     in the chain and every module Draw/Show/Play switch passed as 0.
#   - NEW (review D): stale live_lab_config.json.tmp_<pid> files removed.
#
# Changelog v1.0:
#   - Initial release.
# ============================================================

import sys
import os
import re
import json
import copy
import time
import math
import shutil
import signal
import random
import hashlib
import secrets
import argparse
import threading
import traceback
import subprocess
import collections
import queue

# Enable ASIO on Windows before sounddevice is imported (same reason as
# performance_launcher.py v1.4: multichannel interfaces only expose >2
# channels as one device under ASIO).
if sys.platform == "win32":
    os.environ.setdefault("SD_ENABLE_ASIO", "1")

import numpy as np

# sounddevice / soundfile / tkinter / rtmidi are imported lazily in main(),
# so the pure logic below (routing, bank, priority, adapters, workspace) can
# be tested without audio hardware or a display.
sd = None
sf = None
rtmidi = None
_RTMIDI_ERR = ''

APP_NAME = "PraatAudioToolsLiveLab"
APP_TITLE = "PRAAT AUDIOTOOLS  ·  LIVE LAB 1.1.1"
APP_VERSION = "1.1.1"

# ── The nine Live chains (order = keyboard 1-9) ──────────────────────
CHAINS = [
    {'key': 'live1',  'label': 'Live 1',          'file': 'Live_1.praat',        'random': False},
    {'key': 'live2',  'label': 'Live 2',          'file': 'Live_2.praat',        'random': False},
    {'key': 'live3',  'label': 'Live 3',          'file': 'Live_3.praat',        'random': False},
    {'key': 'live4', 'repro': True,  'label': 'Live 4',          'file': 'Live_4.praat',        'random': False},
    {'key': 'live5', 'repro': True,  'label': 'Live 5',          'file': 'Live_5.praat',        'random': False},
    {'key': 'live6', 'repro': True,  'label': 'Live 6',          'file': 'Live_6.praat',        'random': False},
    {'key': 'live1r', 'label': 'Live 1 Random',   'file': 'Live_1_Random.praat', 'random': True},
    {'key': 'live2r', 'label': 'Live 2 Random',   'file': 'Live_2_Random.praat', 'random': True},
    {'key': 'live3r', 'label': 'Live 3 Random',   'file': 'Live_3_Random.praat', 'random': True},
]
CHAIN_BY_KEY = {c['key']: c for c in CHAINS}

SELFTEST_CHAIN = {'key': 'selftest', 'label': 'Worker self-test', 'file': '', 'random': False}


def log_line(msg):
    """stderr only - never written to disk (no residue)."""
    try:
        sys.stderr.write(time.strftime("[%H:%M:%S] ") + msg + "\n")
    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════
#  SESSION WORKSPACE + CRASH RECOVERY
# ══════════════════════════════════════════════════════════════════════
SESSION_DIR_RE = re.compile(r'^session_\d{8}_\d{6}_\d+_[0-9a-f]{6}$')
LAUNCH_FILE_RE = re.compile(r'^PraatAudioToolsLiveLab_launch_\d+\.(ok|err|perr|midi|py|done)$')
OWNER_FILE = 'owner.json'
LOCK_FILE = 'session.lock'


def default_workspace_root():
    import tempfile
    return os.path.join(tempfile.gettempdir(), APP_NAME)


def _try_lock(fh):
    """Non-blocking exclusive lock on an open file. True = acquired."""
    try:
        if os.name == 'nt':
            import msvcrt
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except (OSError, IOError):
        return False


def _unlock(fh):
    try:
        if os.name == 'nt':
            import msvcrt
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
    except (OSError, IOError):
        pass


def _rmtree_retry(path, attempts=6, delay=0.25):
    """rmtree with retries: on Windows a just-exited child can hold a
    handle for a moment. Returns True when the folder is gone."""
    for i in range(attempts):
        try:
            if os.path.isdir(path):
                shutil.rmtree(path)
            return not os.path.exists(path)
        except OSError:
            time.sleep(delay * (i + 1))
    return not os.path.exists(path)


class SessionWorkspace:
    """One uniquely named, lock-held folder that owns every temp file."""

    def __init__(self, root=None):
        self.root = root or default_workspace_root()
        self.path = None
        self._lock_fh = None
        self.removed = False
        # CLEANUP_PENDING: set by the shutdown sequence when something may
        # still be writing into the workspace. Then nothing in this process
        # deletes it (not even atexit); the next launch's recovery does,
        # once the lock is free.
        self.cleanup_pending = False

    def create(self):
        os.makedirs(self.root, exist_ok=True)
        name = "session_%s_%d_%s" % (time.strftime("%Y%m%d_%H%M%S"),
                                     os.getpid(), secrets.token_hex(3))
        path = os.path.join(self.root, name)
        os.makedirs(path)
        # Lock first, then the owner marker: a folder with a marker but no
        # held lock is, by construction, abandoned.
        fh = open(os.path.join(path, LOCK_FILE), 'a+')
        if not _try_lock(fh):
            fh.close()
            raise RuntimeError("could not lock new session workspace")
        self._lock_fh = fh
        with open(os.path.join(path, OWNER_FILE), 'w', encoding='utf-8') as f:
            json.dump({'app': APP_NAME, 'version': APP_VERSION,
                       'pid': os.getpid(), 'created': time.time()}, f)
        for sub in ('captures', 'jobs'):
            os.makedirs(os.path.join(path, sub))
        self.path = path
        return path

    def sub(self, *parts):
        return os.path.join(self.path, *parts)

    def file_report(self):
        """(n_files, n_bytes, [relative paths]) excluding the lock/owner pair."""
        n, total, names = 0, 0, []
        if not self.path or not os.path.isdir(self.path):
            return 0, 0, []
        for dp, _dn, fns in os.walk(self.path):
            for fn in fns:
                rel = os.path.relpath(os.path.join(dp, fn), self.path)
                if rel in (LOCK_FILE, OWNER_FILE):
                    continue
                n += 1
                names.append(rel)
                try:
                    total += os.path.getsize(os.path.join(dp, fn))
                except OSError:
                    pass
        return n, total, names

    def remove_at_exit(self):
        """atexit hook: last resort ONLY - respects CLEANUP_PENDING."""
        if self.cleanup_pending:
            return False
        return self.remove()

    def remove(self):
        """Release the lock and delete the whole session folder."""
        if self.path is None or self.removed:
            return True
        if self.cleanup_pending:
            return False
        fh, self._lock_fh = self._lock_fh, None
        if fh is not None:
            _unlock(fh)
            try:
                fh.close()
            except Exception:
                pass
        ok = _rmtree_retry(self.path)
        self.removed = ok
        # Remove the app root too, but only if it is now empty.
        try:
            if ok and os.path.isdir(self.root) and not os.listdir(self.root):
                os.rmdir(self.root)
        except OSError:
            pass
        return ok


def _posix_kill_orphan_worker(session_path):
    """Best effort on Linux: a worker of a crashed session that is still
    running is identified by its own command line and killed."""
    pid_file = os.path.join(session_path, 'worker.pid')
    try:
        pid = int(open(pid_file).read().strip())
    except Exception:
        return False
    if os.name == 'nt' or not os.path.isdir('/proc/%d' % pid):
        return False
    try:
        cmd = open('/proc/%d/cmdline' % pid, 'rb').read().decode('utf-8', 'replace')
    except Exception:
        return False
    if 'Live_Lab_Worker.praat' in cmd and session_path in cmd:
        try:
            os.kill(pid, signal.SIGKILL)
            return True
        except OSError:
            return False
    return False


def recover_stale_sessions(root=None, launch_file_age=86400.0):
    """Remove ONLY Live Lab session folders proven abandoned:
       name matches our pattern, owner.json says it is ours, and its
       session.lock can be acquired (= no live process holds it).
       Returns a list of human-readable report lines."""
    root = root or default_workspace_root()
    report = []
    now = time.time()
    # Launch-handshake files of Live_Lab.praat sit next to the app folder
    # (in the temp folder itself). The launcher deletes them; only files
    # with this exact app-prefixed name AND older than a day are touched.
    parent = os.path.dirname(os.path.abspath(root))
    try:
        for name in os.listdir(parent):
            full = os.path.join(parent, name)
            if LAUNCH_FILE_RE.match(name) and os.path.isfile(full):
                try:
                    if now - os.path.getmtime(full) > launch_file_age:
                        os.remove(full)
                        report.append("removed stale launch file " + name)
                except OSError:
                    pass
    except OSError:
        pass
    if not os.path.isdir(root):
        return report
    for name in sorted(os.listdir(root)):
        full = os.path.join(root, name)
        if not (os.path.isdir(full) and SESSION_DIR_RE.match(name)):
            continue
        owner = os.path.join(full, OWNER_FILE)
        try:
            with open(owner, 'r', encoding='utf-8') as f:
                if json.load(f).get('app') != APP_NAME:
                    continue
        except Exception:
            continue          # not provably ours -> never touched
        lock_path = os.path.join(full, LOCK_FILE)
        if not os.path.exists(lock_path):
            # Crash between mkdir and lock creation: only if clearly old.
            if now - os.path.getmtime(owner) > 600:
                if _rmtree_retry(full):
                    report.append("removed incomplete session " + name)
            continue
        try:
            fh = open(lock_path, 'a+')
        except OSError:
            continue          # cannot even open -> treat as in use
        if _try_lock(fh):
            _unlock(fh)
            fh.close()
            _posix_kill_orphan_worker(full)
            if _rmtree_retry(full):
                report.append("recovered stale session " + name)
            else:
                report.append("could not remove stale session " + name)
        else:
            fh.close()
            report.append("left active session " + name + " (another Live Lab is running)")
    return report


# ══════════════════════════════════════════════════════════════════════
#  CHILD PROCESS GUARD  (no orphaned Praat workers)
# ══════════════════════════════════════════════════════════════════════
class ProcessGuardError(Exception):
    pass


class ProcessGuard:
    """Windows: a Job Object with KILL_ON_JOB_CLOSE - every process put in
    it (and everything it spawns) dies when Live Lab exits, even on a crash.
    POSIX: each worker runs in its own session/process group, killed as a
    group."""

    def __init__(self):
        self.job = None
        self.error = ''
        # Windows: a worker is only started if it can be placed in the
        # kill-on-close job. POSIX: process groups need no such check.
        self.enforce = (os.name == 'nt')
        if os.name == 'nt':
            try:
                self._init_job()
            except Exception as e:
                self.error = "process protection (job object) unavailable: %s" % e
                log_line(self.error)
                self.job = None

    def _assign(self, proc):
        """Put proc into the job and VERIFY it is there. True = protected."""
        if os.name != 'nt':
            return True
        if not self.job:
            return False
        h = self._wt.HANDLE(int(proc._handle))
        if not self._k32.AssignProcessToJobObject(self.job, h):
            self.error = "AssignProcessToJobObject failed (error %d)" % self._ct.get_last_error()
            return False
        inside = self._wt.BOOL(False)
        if not self._k32.IsProcessInJob(h, self.job, self._ct.byref(inside)) or not inside.value:
            self.error = "worker is not inside the protection job after assignment"
            return False
        return True

    def _init_job(self):
        import ctypes
        from ctypes import wintypes

        class IO_COUNTERS(ctypes.Structure):
            _fields_ = [(n, ctypes.c_ulonglong) for n in (
                'ReadOperationCount', 'WriteOperationCount', 'OtherOperationCount',
                'ReadTransferCount', 'WriteTransferCount', 'OtherTransferCount')]

        class BASIC(ctypes.Structure):
            _fields_ = [('PerProcessUserTimeLimit', ctypes.c_longlong),
                        ('PerJobUserTimeLimit', ctypes.c_longlong),
                        ('LimitFlags', wintypes.DWORD),
                        ('MinimumWorkingSetSize', ctypes.c_size_t),
                        ('MaximumWorkingSetSize', ctypes.c_size_t),
                        ('ActiveProcessLimit', wintypes.DWORD),
                        ('Affinity', ctypes.c_size_t),
                        ('PriorityClass', wintypes.DWORD),
                        ('SchedulingClass', wintypes.DWORD)]

        class EXTENDED(ctypes.Structure):
            _fields_ = [('BasicLimitInformation', BASIC),
                        ('IoInfo', IO_COUNTERS),
                        ('ProcessMemoryLimit', ctypes.c_size_t),
                        ('JobMemoryLimit', ctypes.c_size_t),
                        ('PeakProcessMemoryUsed', ctypes.c_size_t),
                        ('PeakJobMemoryUsed', ctypes.c_size_t)]

        k32 = ctypes.WinDLL('kernel32', use_last_error=True)
        # Explicit signatures: HANDLEs are pointer-sized on 64-bit Windows;
        # without these, ctypes would pass them as 32-bit ints.
        k32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        k32.CreateJobObjectW.restype = wintypes.HANDLE
        k32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int,
                                                ctypes.c_void_p, wintypes.DWORD]
        k32.SetInformationJobObject.restype = wintypes.BOOL
        k32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        k32.AssignProcessToJobObject.restype = wintypes.BOOL
        k32.IsProcessInJob.argtypes = [wintypes.HANDLE, wintypes.HANDLE, ctypes.POINTER(wintypes.BOOL)]
        k32.IsProcessInJob.restype = wintypes.BOOL
        k32.CloseHandle.argtypes = [wintypes.HANDLE]
        k32.CloseHandle.restype = wintypes.BOOL
        self._wt = wintypes
        self._ct = ctypes
        job = k32.CreateJobObjectW(None, None)
        if not job:
            raise OSError("CreateJobObject failed (error %d)" % ctypes.get_last_error())
        info = EXTENDED()
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not k32.SetInformationJobObject(job, 9, ctypes.byref(info), ctypes.sizeof(info)):
            err = ctypes.get_last_error()
            k32.CloseHandle(job)
            raise OSError("SetInformationJobObject failed (error %d)" % err)
        self._k32 = k32
        self.job = job

    def popen(self, cmd, log_fh, cwd=None, env=None):
        kwargs = dict(stdout=log_fh, stderr=subprocess.STDOUT,
                      stdin=subprocess.DEVNULL, cwd=cwd, env=env)
        if os.name == 'nt':
            CREATE_NO_WINDOW = 0x08000000
            BELOW_NORMAL_PRIORITY_CLASS = 0x00004000
            kwargs['creationflags'] = CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS
        else:
            kwargs['start_new_session'] = True
            kwargs['preexec_fn'] = lambda: os.nice(10)   # audio keeps priority
        if self.enforce and os.name == 'nt' and not self.job:
            raise ProcessGuardError(self.error or "process protection unavailable")
        proc = subprocess.Popen(cmd, **kwargs)
        ok = False
        try:
            ok = self._assign(proc)
        except Exception as e:
            self.error = "process protection failed: %s" % e
        if self.enforce and not ok:
            # Never leave an unprotected worker running: kill and reap it,
            # then fail the job with the reason.
            self.kill_tree(proc)
            try:
                proc.wait(10)
            except Exception:
                pass
            raise ProcessGuardError(self.error or "worker could not be protected")
        return proc

    @staticmethod
    def kill_tree(proc):
        if proc is None or proc.poll() is not None:
            return
        try:
            if os.name == 'nt':
                # /T kills the whole tree (Praat + anything a module spawned).
                subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               creationflags=0x08000000, timeout=10)
            else:
                os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

    def close(self):
        if os.name == 'nt' and self.job:
            try:
                self._k32.CloseHandle(self.job)   # kills anything still inside
            except Exception:
                pass
            self.job = None


# ══════════════════════════════════════════════════════════════════════
#  PROCESSING ADAPTERS  (derived at runtime from the ORIGINAL chains)
# ══════════════════════════════════════════════════════════════════════
class AdapterError(Exception):
    pass


_FORM_RE = re.compile(r'^[ \t]*form\b[^\n]*\n.*?^[ \t]*endform\b[^\n]*\n?', re.S | re.M | re.I)
_RECORD_RE = re.compile(r'^[ \t]*Record Sound \(fixed time\):[^\n]*$', re.M)
_PLAY_LINE_RE = re.compile(r'^[ \t]*Play[ \t]*$', re.M)
_RECORD_SR_RE = re.compile(r'Record Sound \(fixed time\):\s*"[^"]*"\s*,\s*[^,]+,\s*[^,]+,\s*"?(\d+)"?\s*,')

ADAPTER_FORM = (
    "form Live Lab adapter\n"
    "    sentence Lab_input_wav\n"
    "    real Recording_time_seconds 5.0\n"
    "    integer Random_seed 0\n"
    "endform\n")


def _praat_literal(path):
    """A Praat string literal for a path, or None if it cannot be expressed
    safely (a double quote, or an apostrophe, which Praat would read as
    variable interpolation)."""
    p = path.replace('\\', '/')
    if '"' in p or "'" in p:
        return None
    return '"' + p + '"'


def derive_adapter(src_text, chain_dir, plugin_dir, chain_name='chain'):
    """Return (adapter_text, report_lines).

    Exactly three structural edits, everything else byte-identical:
      1. the chain's own form is replaced by the adapter form (same
         variable names: recording_time_seconds, random_seed + the input);
      2. the single 'Record Sound (fixed time): ...' line becomes a marked
         block that reads the captured take and conforms it to what that
         recorder produced (mono, at the rate written in the line) - the
         chain's own normalize / trim / rename preparation that follows is
         kept unchanged;
      3. the final 'Play' line is removed (the worker saves instead).
    Plus two literal substitutions so module lookup does not depend on
    where the adapter file lives or on worker preferences:
      defaultDirectory$     -> "<Vector Chain folder>"
      preferencesDirectory$ -> "<folder containing plugin_AudioTools>"
    Any deviation from the expected structure raises AdapterError rather
    than guessing."""
    text = src_text.replace('\r\n', '\n').replace('\r', '\n')
    if text.startswith('\ufeff'):
        text = text[1:]
    report = []

    forms = list(_FORM_RE.finditer(text))
    if len(forms) != 1:
        raise AdapterError("%s: expected exactly one form block, found %d" % (chain_name, len(forms)))
    form_txt = forms[0].group(0)
    if 'Recording_time_seconds' not in form_txt:
        raise AdapterError("%s: form has no Recording_time_seconds field" % chain_name)
    has_seed = 'Random_seed' in form_txt

    records = list(_RECORD_RE.finditer(text))
    if len(records) != 1:
        raise AdapterError("%s: expected exactly one 'Record Sound (fixed time)' line, found %d"
                           % (chain_name, len(records)))
    if records[0].start() < forms[0].end():
        raise AdapterError("%s: recording command appears inside the form" % chain_name)

    plays = list(_PLAY_LINE_RE.finditer(text))
    if len(plays) != 1:
        raise AdapterError("%s: expected exactly one bare 'Play' line, found %d" % (chain_name, len(plays)))
    tail = text[plays[0].end():]
    if any(ln.strip() and not ln.strip().startswith('#') for ln in tail.split('\n')):
        raise AdapterError("%s: 'Play' is not the final command" % chain_name)

    # Apply edits back-to-front so earlier offsets stay valid.
    out = text
    p = plays[0]
    out = out[:p.start()] + "# [Live Lab] final Play removed - the worker saves the result" + out[p.end():]
    r = records[0]
    indent = re.match(r'[ \t]*', r.group(0)).group(0)
    # The chain receives EXACTLY what its own recorder produced:
    #  - 'Record Sound (fixed time)' always yields a MONO Sound (balance 0.5
    #    mixes left and right equally) and the chain's next step (Trim
    #    silences) requires mono -> a stereo capture is mixed the same way;
    #  - it records at the rate written in that line ("44100" in all nine),
    #    and the chains depend on it (Live 2 / 2R force one stage to 44100 Hz
    #    and later Concatenate it with the others) -> the take is resampled
    #    to that rate. The worker converts the RESULT to the stream rate.
    m_sr = _RECORD_SR_RE.search(r.group(0))
    if not m_sr:
        raise AdapterError("%s: cannot read the sampling frequency from its Record Sound line" % chain_name)
    rec_sr = int(m_sr.group(1))
    report.append("input: mono @ %d Hz (as the original recorder)" % rec_sr)
    repl = [
        "# [Live Lab] begin - live recording replaced by the captured take",
        "Read from file: lab_input_wav$",
        "lab_nch = Get number of channels",
        "if lab_nch > 1",
        "    lab_tmp = selected(\"Sound\")",
        "    Convert to mono",
        "    removeObject: lab_tmp",
        "endif",
        "lab_sr = Get sampling frequency",
        "if lab_sr <> %d" % rec_sr,
        "    lab_tmp = selected(\"Sound\")",
        "    Resample: %d, 50" % rec_sr,
        "    removeObject: lab_tmp",
        "endif",
        "# [Live Lab] end",
    ]
    out = out[:r.start()] + "\n".join(indent + ln for ln in repl) + out[r.end():]
    f = forms[0]
    out = out[:f.start()] + ADAPTER_FORM + out[f.end():]

    n_def = out.count('defaultDirectory$')
    lit = _praat_literal(os.path.abspath(chain_dir))
    if n_def and lit:
        out = out.replace('defaultDirectory$', lit)
        report.append("defaultDirectory$ -> Vector Chain folder (%d)" % n_def)
    elif n_def:
        report.append("WARNING: Vector Chain path contains a quote; defaultDirectory$ fallback left as is")

    n_pref = out.count('preferencesDirectory$')
    pd = os.path.abspath(plugin_dir)
    if n_pref and os.path.basename(pd.rstrip('/\\')) == 'plugin_AudioTools':
        lit2 = _praat_literal(os.path.dirname(pd.rstrip('/\\')))
        if lit2:
            out = out.replace('preferencesDirectory$', lit2)
            report.append("preferencesDirectory$ -> plugin parent folder (%d)" % n_pref)
    report.append("random seed field: %s" % ("yes" if has_seed else "no"))

    sha = hashlib.sha256(src_text.encode('utf-8')).hexdigest()[:16]
    header = ("# ============================================================\n"
              "# AUTO-GENERATED by Live Lab %s - processing-only adapter\n"
              "# Source: %s  (sha256 %s)\n"
              "# Lives only inside the session workspace; deleted after the job.\n"
              "# ============================================================\n"
              % (APP_VERSION, chain_name, sha))
    return header + out, report


_FIELD_RE = re.compile(r'^\s*(real|positive|integer|natural|word|sentence|text|boolean|choice|'
                       r'optionmenu|infile|outfile|folder)\b\s*:?', re.I)


def module_form_field_count(path):
    """Number of form fields of a module script (legacy and colon syntax)."""
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.read().splitlines()
    inside, n = False, 0
    for ln in lines:
        st = ln.strip()
        if not inside and re.match(r'^form\b', st, re.I):
            inside = True
            continue
        if inside:
            if re.match(r'^endform\b', st, re.I):
                return n
            if _FIELD_RE.match(st):
                n += 1
    return n if inside else -1


def _split_args(s):
    out, cur, q = [], '', False
    for ch in s:
        if ch == '"':
            q = not q
        if ch == ',' and not q:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def audit_chain_calls(src_text, plugin_dir):
    """Compare every 'runScript: path_x$, ...' in a chain with the current
    module's form. Returns a list of problems (a mismatch always fails at
    run time, so it is caught before the performance)."""
    txt = re.sub(r'\n[ \t]*\.\.\.', ' ', src_text.replace('\r\n', '\n'))
    paths = dict(re.findall(r'^[ \t]*(path_\w+\$)\s*=\s*pluginPath\$\s*\+\s*"([^"]+)"', txt, re.M))
    problems = []
    for m in re.finditer(r'^[ \t]*runScript:\s*(path_\w+\$)\s*,(.*)$', txt, re.M):
        rel = paths.get(m.group(1))
        if not rel:
            continue
        mod = os.path.join(plugin_dir, rel)
        if not os.path.isfile(mod):
            problems.append("module missing: %s" % rel)
            continue
        nf = module_form_field_count(mod)
        na = len(_split_args(m.group(2)))
        if nf >= 0 and nf != na:
            problems.append("%s: chain passes %d arguments, module form has %d"
                            % (os.path.basename(rel), na, nf))
    return problems


_FIELD_NAME_RE = re.compile(r'^\s*(?:real|positive|integer|natural|word|sentence|text|boolean|choice|'
                            r'optionmenu|infile|outfile|folder)\b\s*:?\s*"?([A-Za-z_][A-Za-z0-9_]*)', re.I)
_VIEW_FLAG_RE = re.compile(r'^(draw|visuali|play|plot|picture|show_?spec)', re.I)
_DRAW_CMD_RE = re.compile(r'^\s*(Erase all|Draw\b|Paint\b|Select (outer|inner) viewport|'
                          r'Text (top|bottom|left|right)\b|Marks (left|right|top|bottom)|One mark|'
                          r'Save as .*PNG)', re.I)
_OFF_LITERALS = {'0', '"no"', 'no', '"0"', '"No"'}


def module_form_field_names(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.read().splitlines()
    inside, names = False, []
    for ln in lines:
        st = ln.strip()
        if not inside and re.match(r'^form\b', st, re.I):
            inside = True
            continue
        if inside:
            if re.match(r'^endform\b', st, re.I):
                break
            m = _FIELD_NAME_RE.match(st)
            if m:
                names.append(m.group(1))
    return names


def audit_nodraw(src_text, plugin_dir):
    """NoDraw requirement: no drawing commands in the chain itself, and
    every module switch named Draw / Show / Visualize / Play / Plot passed
    as a LITERAL off value. Returns a list of problems."""
    txt = src_text.replace('\r\n', '\n')
    problems = []
    for i, ln in enumerate(txt.split('\n'), 1):
        if ln.strip().startswith('#'):
            continue
        if _DRAW_CMD_RE.match(ln):
            problems.append("line %d draws: %s" % (i, ln.strip()[:40]))
    flat = re.sub(r'\n[ \t]*\.\.\.', ' ', txt)
    paths = dict(re.findall(r'^[ \t]*(path_\w+\$)\s*=\s*pluginPath\$\s*\+\s*"([^"]+)"', flat, re.M))
    for m in re.finditer(r'^[ \t]*runScript:\s*(path_\w+\$)\s*,(.*)$', flat, re.M):
        rel = paths.get(m.group(1))
        mod = os.path.join(plugin_dir, rel) if rel else ''
        if not rel or not os.path.isfile(mod):
            continue
        names = module_form_field_names(mod)
        args = _split_args(m.group(2))
        for name, arg in zip(names, args):
            if _VIEW_FLAG_RE.search(name) and arg.strip() not in _OFF_LITERALS:
                problems.append("%s: %s = %s (must be 0 / \"no\")" % (os.path.basename(rel), name, arg.strip()))
    return problems


# The isolated processing worker. It is embedded here (Live Lab ships as
# exactly two files) and written into the session workspace at startup,
# so it is deleted with everything else when the session closes.
WORKER_FILENAME = 'Live_Lab_Worker.praat'
WORKER_PRAAT = r'''# ============================================================
# Praat AudioTools Plugin
# Script:      Live_Lab_Worker.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.0 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Isolated processing worker for Praat AudioTools Live Lab.
#   live_lab.py launches ONE instance of this script per job, as a
#   separate headless Praat process:
#
#     praat --no-pref-files --no-plugins -8 [--FULL-TRUST] --run
#           Live_Lab_Worker.praat <adapter> <in.wav> <out.wav>
#           <status.txt> <capture_seconds> <seed> <target_sr>
#
#   The worker never touches the performer's interactive Praat session,
#   the audio device, or any file outside the job folder it is given.
#
#   <adapter> is a processing-only copy of one Live chain, derived at
#   runtime by live_lab.py from the ORIGINAL chain file (form, recording
#   command and final Play removed; every processing line unchanged).
#
#   Completion protocol (read by live_lab.py only after this process
#   has EXITED, so no file is ever read while still open):
#     - status.txt starts as "state=started"
#     - on success it is rewritten LAST with "state=ok" + metadata
#     - any Praat error aborts the process with a non-zero exit code;
#       live_lab.py then reports the captured stderr text
#
#   Nothing is drawn and nothing is played: the adapter has no Play,
#   and every module is called with Draw = 0 / Play = 0 by the chain.
# ============================================================

form Live Lab Worker
    sentence Adapter_script
    sentence Input_wav
    sentence Output_wav
    sentence Status_file
    real Capture_seconds 5.0
    integer Random_seed 0
    positive Target_sample_rate 48000
endform

writeFileLine: status_file$, "state=started"

if not fileReadable (adapter_script$)
    writeFileLine: status_file$, "state=error", newline$, "error=adapter script not found: ", adapter_script$
    exitScript: "Live Lab worker: adapter script not found."
endif
if not fileReadable (input_wav$)
    writeFileLine: status_file$, "state=error", newline$, "error=captured audio not found: ", input_wav$
    exitScript: "Live Lab worker: captured audio not found."
endif

# This process owns no objects yet; anything it creates is released below.
writeFileLine: status_file$, "state=running"

# ---- Seed Praat's random generator from the take's seed ----
# Chains whose modules do not re-seed themselves (measured: Live 4, 5, 6)
# then reproduce bit-identically from the stored seed on the same Praat
# build (across builds: within 1 float32 LSB). Modules called with
# Seed 0 (drone, Bimodal Contour, Whisper Morph) deliberately re-randomize,
# so Live 1-3 and the Random chains still vary - by the chains' design.
if random_seed > 0 and praatVersion >= 6400
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# ---- Run the chain (processing only) ----
runScript: adapter_script$, input_wav$, capture_seconds, random_seed

# ---- Validate the result ----
nSel = numberOfSelected ("Sound")
if nSel <> 1
    writeFileLine: status_file$, "state=error", newline$, "error=chain finished with ", nSel, " selected Sound objects (expected exactly 1)"
    exitScript: "Live Lab worker: chain did not leave exactly one Sound selected."
endif

result = selected ("Sound")
chainChannels = Get number of channels
chainDuration = Get total duration
chainRate = Get sampling frequency
chainFrames = Get number of samples

if chainDuration <= 0 or chainFrames < 2
    writeFileLine: status_file$, "state=error", newline$, "error=chain produced an empty Sound"
    exitScript: "Live Lab worker: empty result."
endif

# ---- Bring the result to the live stream rate (no resampling in the RT callback) ----
outSound = result
resampled = 0
if chainRate <> target_sample_rate
    selectObject: result
    outSound = Resample: target_sample_rate, 50
    resampled = 1
endif

# Resampling can overshoot a 0.99 peak very slightly; guard 24-bit PCM against clipping.
selectObject: outSound
peak = Get absolute extremum: 0, 0, "None"
clipGuard = 0
if peak > 0.999
    Scale peak: 0.99
    clipGuard = 1
    peak = 0.99
endif

outChannels = Get number of channels
outDuration = Get total duration
outRate = Get sampling frequency
outFrames = Get number of samples

Save as 24-bit WAV file: output_wav$

# ---- Release every object this worker process created ----
select all
Remove

# Status is written LAST: its "state=ok" line means the WAV above is complete.
status$ = "state=ok" + newline$
status$ = status$ + "channels=" + string$ (outChannels) + newline$
status$ = status$ + "duration=" + fixed$ (outDuration, 6) + newline$
status$ = status$ + "sample_rate=" + string$ (outRate) + newline$
status$ = status$ + "frames=" + string$ (outFrames) + newline$
status$ = status$ + "chain_channels=" + string$ (chainChannels) + newline$
status$ = status$ + "chain_sample_rate=" + string$ (chainRate) + newline$
status$ = status$ + "resampled=" + string$ (resampled) + newline$
status$ = status$ + "clip_guard=" + string$ (clipGuard) + newline$
status$ = status$ + "peak=" + fixed$ (peak, 6) + newline$
status$ = status$ + "seed=" + string$ (random_seed) + newline$
status$ = status$ + "praat_version=" + praatVersion$ + newline$
writeFile: status_file$, status$
'''


def write_worker(workspace):
    path = workspace.sub(WORKER_FILENAME)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(WORKER_PRAAT)
    return path


SELFTEST_ADAPTER = (
    "# Live Lab worker self-test: passthrough (proves Praat, trust flags,\n"
    "# file handoff and resampling work, without running any chain).\n"
    + ADAPTER_FORM +
    "Read from file: lab_input_wav$\n"
    "Scale peak: 0.5\n")


# ══════════════════════════════════════════════════════════════════════
#  PRAAT EXECUTABLE DISCOVERY
# ══════════════════════════════════════════════════════════════════════
def _decode_praat_output(raw):
    """Windows Praat writes UTF-16LE (no BOM) by default; we pass -8 to the
    worker, but --version/--help probes may still come back as UTF-16."""
    if not raw:
        return ''
    if raw.count(b'\x00') > len(raw) // 4:
        try:
            return raw.decode('utf-16-le', 'replace')
        except Exception:
            pass
    return raw.decode('utf-8', 'replace')


def praat_candidates(hint='', configured=''):
    c = []
    for p in (configured, hint):
        if p:
            c.append(p)
    for name in ('praat', 'Praat', 'praat_nogui', 'praat_barren'):
        w = shutil.which(name)
        if w:
            c.append(w)
    home = os.path.expanduser('~')
    if os.name == 'nt':
        for base in (os.environ.get('ProgramFiles', r'C:\Program Files'),
                     os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'),
                     os.environ.get('LOCALAPPDATA', '')):
            if base:
                c.append(os.path.join(base, 'Praat', 'Praat.exe'))
                c.append(os.path.join(base, 'Praat.exe'))
        for d in ('Desktop', 'Downloads', os.path.join('Desktop', 'programs', 'audio'),
                  os.path.join('Desktop', 'programs')):
            c.append(os.path.join(home, d, 'Praat.exe'))
    elif sys.platform == 'darwin':
        c += ['/Applications/Praat.app/Contents/MacOS/Praat',
              os.path.join(home, 'Applications/Praat.app/Contents/MacOS/Praat')]
    else:
        c += ['/usr/bin/praat', '/usr/bin/praat_nogui', '/usr/local/bin/praat']
    seen, out = set(), []
    for p in c:
        k = os.path.normcase(os.path.abspath(p))
        if k not in seen:
            seen.add(k)
            out.append(p)
    return out


def probe_praat(exe, timeout=15):
    """Return dict(path, version, major, minor, flags) or None."""
    if not exe or not os.path.isfile(exe):
        return None
    cf = 0x08000000 if os.name == 'nt' else 0
    try:
        r = subprocess.run([exe, '--version'], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                           timeout=timeout, creationflags=cf)
        txt = _decode_praat_output(r.stdout)
    except Exception:
        return None
    m = re.search(r'Praat\s+(\d+)\.(\d+)(?:\.(\d+))?', txt)
    if not m:
        return None
    major, minor = int(m.group(1)), int(m.group(2))
    patch = int(m.group(3) or 0)
    try:
        h = subprocess.run([exe, '--help'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           stdin=subprocess.DEVNULL, timeout=timeout, creationflags=cf)
        help_txt = _decode_praat_output(h.stdout)
    except Exception:
        help_txt = ''
    flags = ['--no-pref-files']
    if '--no-plugins' in help_txt:
        flags.append('--no-plugins')
    if '--utf8' in help_txt:
        flags.append('-8')
    # Praat 7 full-trust model: saving the result WAV is a trust-gated action.
    if major >= 7 or '--FULL-TRUST' in help_txt:
        flags.append('--FULL-TRUST')
    return {'path': exe, 'version': '%d.%d.%d' % (major, minor, patch),
            'major': major, 'minor': minor, 'flags': flags}


def find_praat(hint='', configured=''):
    tried = []
    for cand in praat_candidates(hint, configured):
        tried.append(cand)
        info = probe_praat(cand)
        if info:
            info['tried'] = tried
            return info
    return {'path': '', 'tried': tried}


# ══════════════════════════════════════════════════════════════════════
#  OUTPUT ROUTING  (explicit matrices - no wrap-around, no silent folding)
# ══════════════════════════════════════════════════════════════════════
class RoutingError(Exception):
    pass


MONO_LAWS = {
    '-3 dB (equal power)': 1.0 / math.sqrt(2.0),
    '-6 dB (linear)': 0.5,
    '0 dB (dual mono)': 1.0,
}
MONO_OCTO_MODES = ('Front Stereo Pair', 'Single speaker', 'All 8 speakers (-9 dB each)')
DOWNMIX_MODES = ('None (reject 8-ch results)',
                 'Ring -> stereo, equal-power by azimuth (-6 dB)',
                 'Odd -> L, even -> R (-6 dB)')
PROFILES = ('Stereo', 'Octophonic')

DEFAULT_ROUTING = {
    'profile': 'Stereo',
    'phys_channels': 2,
    'stereo_out': [1, 2],                       # physical channels (1-based) for L, R
    'speaker_map': [1, 2, 3, 4, 5, 6, 7, 8],    # physical channel of speaker 1..8
    'front_pair': [1, 2],                       # speakers (1-based) used for stereo results
    'mono_law': '-3 dB (equal power)',
    'mono_octo': 'Front Stereo Pair',
    'mono_speaker': 1,
    'downmix_8_to_2': DOWNMIX_MODES[0],
    'ring_start_deg': -22.5,                    # azimuth of speaker 1 (0 = front, + = clockwise)
    'trims_db': [0.0] * 8,
}


def _ints(v, n=None):
    out = [int(x) for x in v]
    if n is not None and len(out) != n:
        raise RoutingError("expected %d values, got %d" % (n, len(out)))
    return out


def validate_routing(rt):
    """Return a list of human-readable problems with a routing config
    (empty list = valid). Checks the layout itself, independent of any
    particular result's channel count."""
    errs = []
    try:
        nphys = int(rt.get('phys_channels', 0))
    except (TypeError, ValueError):
        return ["physical output channel count is not a number"]
    if nphys < 1 or nphys > 64:
        errs.append("physical output channels must be 1..64 (got %d)" % nphys)
        return errs
    prof = rt.get('profile', 'Stereo')
    if prof not in PROFILES:
        errs.append("unknown output profile %r" % prof)
        return errs
    if prof == 'Stereo':
        try:
            lr = _ints(rt.get('stereo_out', [1, 2]), 2)
            if nphys < 2:
                errs.append("Stereo profile needs at least 2 physical outputs")
            for c in lr:
                if not 1 <= c <= nphys:
                    errs.append("stereo output channel %d is outside 1..%d" % (c, nphys))
            if lr[0] == lr[1]:
                errs.append("left and right are routed to the same physical channel %d" % lr[0])
        except (RoutingError, TypeError, ValueError) as e:
            errs.append("stereo outputs: %s" % e)
    else:
        if nphys < 8:
            errs.append("Octophonic profile needs at least 8 physical outputs (device stream has %d)" % nphys)
        try:
            sm = _ints(rt.get('speaker_map', []), 8)
            for i, c in enumerate(sm):
                if not 1 <= c <= nphys:
                    errs.append("speaker %d -> physical %d is outside 1..%d" % (i + 1, c, nphys))
            if len(set(sm)) != 8:
                errs.append("speaker map assigns two speakers to the same physical channel")
        except (RoutingError, TypeError, ValueError) as e:
            errs.append("speaker map: %s" % e)
        try:
            fp = _ints(rt.get('front_pair', [1, 2]), 2)
            for s in fp:
                if not 1 <= s <= 8:
                    errs.append("Front Stereo Pair speaker %d is outside 1..8" % s)
            if fp[0] == fp[1]:
                errs.append("Front Stereo Pair uses the same speaker twice")
        except (RoutingError, TypeError, ValueError) as e:
            errs.append("Front Stereo Pair: %s" % e)
        if rt.get('mono_octo') not in MONO_OCTO_MODES:
            errs.append("unknown mono mapping %r" % rt.get('mono_octo'))
        if rt.get('mono_octo') == 'Single speaker':
            try:
                ms = int(rt.get('mono_speaker', 1))
                if not 1 <= ms <= 8:
                    errs.append("mono speaker %d is outside 1..8" % ms)
            except (TypeError, ValueError):
                errs.append("mono speaker is not a number")
    if rt.get('mono_law') not in MONO_LAWS:
        errs.append("unknown mono gain law %r" % rt.get('mono_law'))
    if rt.get('downmix_8_to_2') not in DOWNMIX_MODES:
        errs.append("unknown downmix %r" % rt.get('downmix_8_to_2'))
    try:
        trims = [float(x) for x in rt.get('trims_db', [])]
        for t in trims:
            if not -60.0 <= t <= 12.0:
                errs.append("channel trim %.1f dB is outside -60..+12 dB" % t)
    except (TypeError, ValueError):
        errs.append("channel trims are not numbers")
    return errs


def trims_vector(rt):
    nphys = int(rt.get('phys_channels', 2))
    t = [float(x) for x in rt.get('trims_db', [])]
    t = (t + [0.0] * nphys)[:nphys]
    return (10.0 ** (np.asarray(t, dtype=np.float64) / 20.0)).astype(np.float32)


def build_routing_matrix(n_in, rt):
    """Return (M, description) with M shaped (n_in, n_phys) float32 so that
    out = chunk @ M. Raises RoutingError for anything not explicitly
    configured - including every channel count other than 1, 2 or 8."""
    errs = validate_routing(rt)
    if errs:
        raise RoutingError("; ".join(errs))
    nphys = int(rt['phys_channels'])
    prof = rt['profile']
    M = np.zeros((n_in, nphys), dtype=np.float64)
    law = MONO_LAWS[rt['mono_law']]

    if n_in not in (1, 2, 8):
        raise RoutingError("results with %d channels have no defined routing "
                           "(supported: mono, stereo, 8-channel)" % n_in)

    if prof == 'Stereo':
        L, R = [c - 1 for c in rt['stereo_out']]
        if n_in == 1:
            M[0, L] = law
            M[0, R] = law
            desc = "mono -> L/R (%s)" % rt['mono_law']
        elif n_in == 2:
            M[0, L] = 1.0
            M[1, R] = 1.0
            desc = "stereo -> L/R (preserved)"
        else:
            mode = rt['downmix_8_to_2']
            if mode == DOWNMIX_MODES[0]:
                raise RoutingError("8-channel result on a Stereo output needs an approved "
                                   "downmix matrix (Setup > Routing > 8-ch to stereo)")
            if mode == DOWNMIX_MODES[1]:
                start = float(rt.get('ring_start_deg', -22.5))
                for k in range(8):
                    az = math.radians(start + 45.0 * k)
                    p = max(-1.0, min(1.0, math.sin(az)))       # -1 = hard left
                    th = (p + 1.0) * math.pi / 4.0
                    M[k, L] = math.cos(th) * 0.5
                    M[k, R] = math.sin(th) * 0.5
                desc = "8-ch ring -> stereo, equal-power azimuth pan, -6 dB"
            else:
                for k in range(8):
                    M[k, L if k % 2 == 0 else R] = 0.5
                desc = "8-ch odd->L / even->R, -6 dB"
    else:
        sm = [c - 1 for c in rt['speaker_map']]
        fa, fb = [s - 1 for s in rt['front_pair']]
        if n_in == 1:
            mode = rt['mono_octo']
            if mode == 'Front Stereo Pair':
                M[0, sm[fa]] = law
                M[0, sm[fb]] = law
                desc = "mono -> Front Stereo Pair (spk %d/%d, %s)" % (fa + 1, fb + 1, rt['mono_law'])
            elif mode == 'Single speaker':
                s = int(rt.get('mono_speaker', 1)) - 1
                M[0, sm[s]] = 1.0
                desc = "mono -> speaker %d" % (s + 1)
            else:
                for k in range(8):
                    M[0, sm[k]] = 1.0 / math.sqrt(8.0)
                desc = "mono -> all 8 speakers, -9 dB each"
        elif n_in == 2:
            M[0, sm[fa]] = 1.0
            M[1, sm[fb]] = 1.0
            desc = "stereo -> Front Stereo Pair (spk %d/%d)" % (fa + 1, fb + 1)
        else:
            for k in range(8):
                M[k, sm[k]] = 1.0
            desc = "8-ch -> speakers 1-8 (saved layout)"
    return M.astype(np.float32), desc


# ══════════════════════════════════════════════════════════════════════
#  LATEST CAPTURE PRIORITY
# ══════════════════════════════════════════════════════════════════════
class DecisionClock:
    """Monotonic performance-decision counter (see header for the rule)."""

    def __init__(self):
        self.latest = 0
        self.last_kind = ''

    def decide(self, kind):
        self.latest += 1
        self.last_kind = kind
        return self.latest


def autoplay_verdict(result, auto_suspend, clock):
    """(should_autoplay, reason). Pure function of the documented rule."""
    if result.policy != 'auto':
        return False, "manual policy"
    if auto_suspend:
        return False, "Auto Suspend active"
    if result.decision_no != clock.latest:
        return False, "superseded by a newer decision (%s)" % (clock.last_kind or 'newer')
    return True, "latest decision"


# ══════════════════════════════════════════════════════════════════════
#  TAKES, RESULTS, RESULT BANK
# ══════════════════════════════════════════════════════════════════════
ST_QUEUED, ST_PROCESSING, ST_READY, ST_FAILED, ST_CANCELLED = (
    'QUEUED', 'PROCESSING', 'READY', 'FAILED', 'CANCELLED')


class Take:
    """One captured recording (the original, kept for Regenerate)."""

    def __init__(self, take_id, capture_path, capture_dur, in_ch, sr, chain_key, reason=''):
        self.take_id = int(take_id)
        self.capture_path = capture_path
        self.capture_dur = float(capture_dur)
        self.in_ch = int(in_ch)
        self.sr = int(sr)
        self.chain_key = chain_key
        self.stop_reason = reason
        self.created = time.time()
        self.regen_count = 0

    @property
    def label(self):
        return "T%03d" % self.take_id


class Result:
    """One processing of a Take through a chain (first run or Regenerate)."""

    def __init__(self, take, chain_key, policy, xfade, decision_no, seed, regen_index):
        self.take = take
        self.chain_key = chain_key
        self.policy = policy                  # frozen at capture start / regenerate press
        self.xfade = float(xfade)
        self.decision_no = int(decision_no)
        self.seed = int(seed)
        self.regen_index = int(regen_index)   # 1 = original processing, 2.. = regenerations
        self.rid = "%s.%d" % (take.label, regen_index)
        self.status = ST_QUEUED
        self.audio = None                     # float32 (frames, ch) at stream rate
        self.out_dur = 0.0
        self.out_ch = 0
        self.out_sr = 0
        self.error = ''
        self.pinned = False
        self.meta = {}
        self.created = time.time()
        self.completed = 0.0
        self.autoplay_note = ''

    @property
    def nbytes(self):
        return 0 if self.audio is None else int(self.audio.nbytes)

    def record(self):
        """Traceability record (what the spec asks every Take to carry)."""
        return {
            'result_id': self.rid, 'take_id': self.take.label,
            'capture_file': os.path.basename(self.take.capture_path),
            'capture_duration_s': round(self.take.capture_dur, 4),
            'input_channels': self.take.in_ch, 'capture_sample_rate': self.take.sr,
            'chain': CHAIN_BY_KEY.get(self.chain_key, SELFTEST_CHAIN)['label'],
            'chain_file': CHAIN_BY_KEY.get(self.chain_key, SELFTEST_CHAIN)['file'],
            'status': self.status, 'output_duration_s': round(self.out_dur, 4),
            'output_channels': self.out_ch, 'output_sample_rate': self.out_sr,
            'playback_policy': self.policy, 'crossfade_s': self.xfade,
            'random_seed': self.seed,
            'seed_reproduces_result': bool(CHAIN_BY_KEY.get(self.chain_key, {}).get('repro')),
            'seed_reproduction_scope': ('bit-identical on the same Praat build'
                                        if CHAIN_BY_KEY.get(self.chain_key, {}).get('repro') else 'none'),
            'regeneration': self.regen_index,
            'worker_meta': self.meta, 'error': self.error,
        }


class ResultBank:
    """Bounded, protection-aware store. Eviction never touches a result
    that is pinned, playing, queued or processing. If nothing is
    evictable the bank refuses NEW captures instead of deleting data."""

    def __init__(self, capacity=16, memory_mb=1500, on_take_released=None):
        self.capacity = int(capacity)
        self.memory_bytes_cap = int(memory_mb) * 1024 * 1024
        self.results = []
        self.selected = -1
        self.on_take_released = on_take_released
        self.evicted_total = 0

    # -- queries --
    def __len__(self):
        return len(self.results)

    def by_rid(self, rid):
        for r in self.results:
            if r.rid == rid:
                return r
        return None

    def selected_result(self):
        if 0 <= self.selected < len(self.results):
            return self.results[self.selected]
        return None

    def memory_used(self):
        return sum(r.nbytes for r in self.results)

    def is_protected(self, r, playing):
        return r.pinned or r.status in (ST_QUEUED, ST_PROCESSING) or r.rid in playing

    def evictable(self, playing):
        return [r for r in self.results if not self.is_protected(r, playing)]

    def can_accept_new(self, playing):
        if len(self.results) < self.capacity:
            return True
        return bool(self.evictable(playing))

    def latest_ready(self):
        ready = [r for r in self.results if r.status == ST_READY]
        if not ready:
            return None
        return max(ready, key=lambda r: r.completed)

    # -- mutation --
    def add(self, result, playing=()):
        self.results.append(result)
        evicted = self._enforce(set(playing))
        if self.selected < 0:
            self.selected = len(self.results) - 1
        return evicted

    def _enforce(self, playing):
        evicted = []
        while len(self.results) > self.capacity:
            cand = self.evictable(playing)
            if not cand:
                break
            evicted.append(self._evict(cand[0]))      # oldest first
        while self.memory_used() > self.memory_bytes_cap:
            cand = [r for r in self.evictable(playing) if r.nbytes > 0]
            if not cand:
                break
            evicted.append(self._evict(cand[0]))
        return evicted

    def enforce(self, playing=()):
        return self._enforce(set(playing))

    def _evict(self, r):
        sel = self.selected_result()
        self.results.remove(r)
        r.audio = None
        self.evicted_total += 1
        if sel is r:
            self.selected = min(len(self.results) - 1, max(0, self.selected))
        elif sel is not None:
            self.selected = self.results.index(sel)
        self._release_take_if_unused(r.take)
        return r.rid

    def _release_take_if_unused(self, take):
        if any(x.take is take for x in self.results):
            return
        if self.on_take_released:
            self.on_take_released(take)

    def select_rid(self, rid):
        for i, r in enumerate(self.results):
            if r.rid == rid:
                self.selected = i
                return True
        return False

    def step(self, delta):
        if not self.results:
            self.selected = -1
            return None
        if self.selected < 0:
            self.selected = len(self.results) - 1
        else:
            self.selected = max(0, min(len(self.results) - 1, self.selected + delta))
        return self.selected_result()

    def clear_all(self):
        takes = {id(r.take): r.take for r in self.results}
        for r in self.results:
            r.audio = None
        self.results = []
        self.selected = -1
        if self.on_take_released:
            for t in takes.values():
                self.on_take_released(t)


# ══════════════════════════════════════════════════════════════════════
#  AUDIO ENGINE  (one full-duplex stream: capture + playback)
# ══════════════════════════════════════════════════════════════════════
DECLICK_S = 0.002          # 2 ms safety ramps at a voice's own start/end
RETRIGGER_FADE_S = 0.02    # old instance of a retriggered result


class Voice:
    """One one-shot playback instance. All state is touched only by the
    audio callback after the voice has been handed over."""
    __slots__ = ('rid', 'audio', 'M', 'pos', 'n', 'fi_len', 'fi_pos', 'fo_len', 'fo_pos',
                 'fo_g0', 'gain', 'declick', 'done', 'kind', 'fi_linear', 'fo_linear')

    def __init__(self, rid, audio, M, fade_in_frames, declick_frames, kind):
        self.rid = rid
        self.audio = audio
        self.M = M
        self.pos = 0
        self.n = int(audio.shape[0])
        self.fi_len = int(max(0, min(fade_in_frames, self.n)))
        self.fi_pos = 0
        self.fo_len = 0
        self.fo_pos = 0
        self.fo_g0 = 1.0
        self.gain = 0.0 if self.fi_len > 0 else 1.0
        self.declick = int(max(1, declick_frames))
        self.done = False
        self.kind = kind          # 'play' | 'xfade-in'
        # Equal-power (sin/cos) is right for different material; for
        # IDENTICAL material (crossfading a result into itself) the two
        # voices are correlated and equal-power would rise +3 dB, so those
        # fades use the constant-amplitude (linear) law instead.
        self.fi_linear = False
        self.fo_linear = False

    def start_fade_out(self, frames, linear=False):
        """Fade from the CURRENT gain to zero (equal-power cosine, or linear
        for correlated material). A voice that is still fading in therefore
        never jumps up first."""
        if self.done:
            return
        if self.fo_len > 0 and self.fo_len - self.fo_pos <= frames:
            return                # already fading out at least this fast
        self.fo_linear = bool(linear)
        self.fo_g0 = self.gain
        self.fo_len = int(max(1, frames))
        self.fo_pos = 0
        self.fi_pos = self.fi_len  # stop any fade-in

    @property
    def fading_out(self):
        return self.fo_len > 0


class AudioEngine:
    def __init__(self):
        self.stream = None
        self.sr = 48000
        self.n_out = 2
        self.n_in_open = 0
        self.cap_sel = np.zeros(0, dtype=np.intp)
        self.capture_enabled = False
        self.duplex = False
        self.api_name = ''
        self.error = ''
        self.cmd = collections.deque()          # control -> callback (lock-free)
        self.voices = []                        # owned by callback
        self.master = np.float32(1.0)
        self.trims = np.ones(2, dtype=np.float32)
        self.in_peak = np.zeros(2, dtype=np.float32)
        self.out_peak = np.zeros(2, dtype=np.float32)
        self.clip_count = 0           # blocks whose mix exceeded full scale (before protection)
        self.limit_on = True          # output protection (safety limiter)
        self.ceiling = np.float32(10 ** (-0.3 / 20.0))
        self.lim_gain = 1.0
        self.lim_events = 0           # blocks in which the limiter reduced gain
        self.lim_backstop = 0         # samples the final safety clamp had to touch (should stay 0)
        self._la_x = None             # lookahead delay line (samples not yet output)
        self._reset_limiter()
        self.pending_play = set()     # rids handed to the callback, not yet voiced
        self.buf_shape = None
        self.status_count = 0
        self.last_status = ''
        self.blocks = 0
        # capture state (callback-owned once the stream runs)
        self.ring = None
        self.ring_pos = 0
        self.ring_filled = 0
        self.preroll_frames = 0
        self.max_frames = 0
        self.free_bufs = collections.deque()
        self.done_caps = collections.deque()    # callback -> writer thread
        self.rec_active = False
        self.rec_buf = None
        self.rec_pos = 0
        self.rec_seq = 0
        self.rec_pre = 0
        self.rec_refused = 0
        self.rec_started_seq = 0                # last seq actually started (GUI)
        self._tmp = None
        self._gbuf = None
        self._tone = []

    # ── configuration ────────────────────────────────────────────────
    def configure_capture(self, n_cap, max_s, preroll_s, n_buffers=3):
        """Preallocate everything the callback will write into."""
        self.max_frames = int(max_s * self.sr)
        self.preroll_frames = int(max(0.0, preroll_s) * self.sr)
        self.ring = np.zeros((max(1, self.preroll_frames), max(1, n_cap)), dtype=np.float32)
        self.ring_pos = 0
        self.ring_filled = 0
        self.free_bufs.clear()
        self.buf_shape = (self.max_frames + self.preroll_frames + 8, max(1, n_cap))
        for _ in range(n_buffers):
            self.free_bufs.append(np.zeros(self.buf_shape, dtype=np.float32))
        self.in_peak = np.zeros(max(1, n_cap), dtype=np.float32)

    LIM_ATTACK_S = 0.001          # A: gain ramps down over 1 ms BEFORE a peak
    LIM_RELEASE_S = 0.25          # full-scale recovery time (linear)

    def _reset_limiter(self):
        A = max(4, int(self.LIM_ATTACK_S * self.sr))
        self._lim_A = A
        self._lim_D = 2 * A                         # lookahead delay = 2 ms at any rate
        self._la_x = np.zeros((self._lim_D, max(1, self.n_out)), dtype=np.float32)
        self._la_t = np.ones(self._lim_D, dtype=np.float64)
        self._la_m = np.ones(A, dtype=np.float64)   # history of the windowed minimum
        self.lim_gain = 1.0

    def _protect(self, mix, frames, pk_all):
        """Output protection: a true LOOKAHEAD peak limiter (2 ms delay on
        the playback path only - capture is unaffected).

        Per sample t[n] = min(1, ceiling / |x[n]|) (max over channels).
        m[n] = min of t over the next 2A samples (lookahead), then the gain is
        the moving average of m over the previous A+1 samples. Every term of
        that average contains index n, so gain[n] <= t[n] holds exactly: the
        output never exceeds the ceiling and NO hard clipping is needed. The
        average makes the attack a smooth 1 ms ramp that ends before the
        peak; release is a linear rise limited to 1 / (0.25 s).
        Below the ceiling t = 1 everywhere, so the gain is exactly 1.0 and
        the output is the input delayed by 2 ms, bit for bit."""
        if self._la_x is None or self._la_x.shape[1] != mix.shape[1]:
            self._reset_limiter()
        A, D, N = self._lim_A, self._lim_D, frames
        c = float(self.ceiling)
        absmax = np.max(np.abs(mix), axis=1).astype(np.float64)
        t = np.minimum(1.0, c / np.maximum(absmax, 1e-12))
        x_ext = np.concatenate([self._la_x, mix], axis=0)
        t_ext = np.concatenate([self._la_t, t])
        m = np.lib.stride_tricks.sliding_window_view(t_ext, D + 1)[:N].min(axis=1)
        m_ext = np.concatenate([self._la_m, m])
        cs = np.concatenate([[0.0], np.cumsum(m_ext)])
        g = (cs[A + 1:A + 1 + N] - cs[:N]) / (A + 1)
        rel = 1.0 / (self.LIM_RELEASE_S * self.sr)
        idx = np.arange(N, dtype=np.float64)
        h = np.minimum.accumulate(np.minimum(g - idx * rel, self.lim_gain + rel))
        g = np.minimum(np.minimum(g, h + idx * rel), 1.0)
        if g.min() < 1.0:
            self.lim_events += 1
        out = x_ext[:N] * g.astype(np.float32)[:, None]
        over = np.abs(out) > c * 1.0001
        if over.any():                              # numerical backstop only
            self.lim_backstop += int(over.sum())
            np.clip(out, -c, c, out=out)
        mix[:] = out
        self._la_x = x_ext[N:].copy()
        self._la_t = t_ext[N:].copy()
        self._la_m = m_ext[-A:].copy()
        self.lim_gain = float(g[-1])

    def _alloc_block_buffers(self, frames):
        self._tmp = np.zeros((frames, self.n_out), dtype=np.float32)
        self._mix = np.zeros((frames, self.n_out), dtype=np.float32)
        self._gbuf = np.ones(frames, dtype=np.float32)

    def open(self, sr, blocksize, out_dev, n_out, in_dev=None, in_sel=(), max_s=60.0,
             preroll_s=0.25):
        """Open ONE stream. Full duplex when an input device is given."""
        self.close()
        self.sr = int(sr)
        self.n_out = int(n_out)
        self.trims = np.ones(self.n_out, dtype=np.float32) if len(self.trims) != self.n_out else self.trims
        self.out_peak = np.zeros(self.n_out, dtype=np.float32)
        self.error = ''
        self.voices = []
        self.cmd.clear()
        self.pending_play.clear()
        # done_caps is NOT cleared: a finished take still waiting for the
        # writer survives an audio restart (each entry carries its own rate).
        self.rec_active = False
        self.rec_buf = None
        bs = int(blocksize)
        self._alloc_block_buffers(max(bs, 64) * 2)
        self._reset_limiter()
        st = None                 # local until start() succeeded - closed on ANY failure
        try:
            out_info = sd.query_devices(out_dev)
            self.api_name = sd.query_hostapis(out_info['hostapi'])['name']
            if self.n_out > int(out_info['max_output_channels']):
                raise ValueError("device provides %d outputs, %d requested"
                                 % (out_info['max_output_channels'], self.n_out))
            if in_dev is not None and len(in_sel):
                in_info = sd.query_devices(in_dev)
                in_api = sd.query_hostapis(in_info['hostapi'])['name']
                if 'ASIO' in (self.api_name + in_api).upper() and in_dev != out_dev:
                    raise ValueError("ASIO full duplex needs the SAME device for input and output")
                self.n_in_open = int(max(in_sel)) + 1
                if self.n_in_open > int(in_info['max_input_channels']):
                    raise ValueError("input channel %d requested, device has %d inputs"
                                     % (self.n_in_open, in_info['max_input_channels']))
                self.cap_sel = np.asarray(list(in_sel), dtype=np.intp)
                self.configure_capture(len(in_sel), max_s, preroll_s)
                st = sd.Stream(samplerate=self.sr, blocksize=bs, dtype='float32',
                                        device=(in_dev, out_dev),
                                        channels=(self.n_in_open, self.n_out),
                                        callback=self._cb_duplex, latency='low')
                self.capture_enabled = True
                self.duplex = True
            else:
                self.capture_enabled = False
                self.duplex = False
                st = sd.OutputStream(samplerate=self.sr, blocksize=bs, dtype='float32',
                                              device=out_dev, channels=self.n_out,
                                              callback=self._cb_out, latency='low')
            st.start()
            self.stream = st
            return True
        except Exception as e:
            if st is not None:
                # A stream that was created but failed to start still holds
                # the device (an ASIO driver stays busy) - release it now.
                for meth in ('abort', 'close'):
                    try:
                        getattr(st, meth)()
                    except Exception:
                        pass
            hint = ("set the interface to %d Hz (ASIO does not resample) and close other "
                    "programs using it" % self.sr) if 'ASIO' in self.api_name.upper() else \
                   ("check sample rate %d Hz / channel counts and that the device is free" % self.sr)
            self.error = "%s  (%s)" % (e, hint)
            self.stream = None
            self.capture_enabled = False
            return False

    def close(self):
        s, self.stream = self.stream, None
        if s is not None:
            try:
                s.stop()
            except Exception:
                pass
            try:
                s.close()
            except Exception:
                pass
        self.voices = []
        self.pending_play.clear()
        self.capture_enabled = False

    def is_alive(self):
        try:
            return self.stream is not None and bool(self.stream.active)
        except Exception:
            return False

    # ── control API (any thread) ────────────────────────────────────
    def play(self, rid, audio, M, mode, xfade_s=0.0):
        """mode: 'play' (layer; retrigger fades the old instance of the same
        result) or 'xfade' (equal-power crossfade from everything playing)."""
        if mode == 'xfade':
            fi = int(max(0.0, xfade_s) * self.sr)
        else:
            fi = 0
        v = Voice(rid, audio, M, fi, DECLICK_S * self.sr, 'xfade-in' if mode == 'xfade' else 'play')
        self.pending_play.add(rid)        # protected from eviction until voiced
        self.cmd.append(('play', v, mode, int(max(0.0, xfade_s) * self.sr)))

    def stop_all(self, fade_s):
        self.cmd.append(('stop_all', int(max(0.001, fade_s) * self.sr)))

    def stop_rid(self, rid, fade_s):
        self.cmd.append(('stop_rid', rid, int(max(0.001, fade_s) * self.sr)))

    def rec_start(self, seq):
        self.cmd.append(('rec_start', int(seq)))

    def rec_stop(self):
        self.cmd.append(('rec_stop',))

    def test_tone(self, phys_ch, seconds=1.0, level_db=-30.0, freq=1000.0):
        self.cmd.append(('tone', int(phys_ch), int(seconds * self.sr),
                         float(10 ** (level_db / 20.0)), float(freq)))

    def playing_rids(self):
        """Results that are playing OR handed to the callback but not yet
        started - both must be protected from bank eviction."""
        return {v.rid for v in list(self.voices) if not v.done} | set(self.pending_play)

    def salvage_recording(self):
        """Only after the stream is dead (device lost): hand the partial
        capture to the writer instead of losing it."""
        if self.is_alive():
            return False
        if self.rec_active and self.rec_buf is not None:
            self.done_caps.append((self.rec_seq, self.rec_buf, self.rec_pos, 'device lost', self.rec_pre,
                                   self.sr))
            self.rec_active = False
            self.rec_buf = None
            return True
        return False

    def return_buffer(self, buf):
        # A buffer from before an audio restart may have a different shape
        # (other max duration / channel count): drop it instead of reusing.
        if self.buf_shape is not None and buf.shape == self.buf_shape:
            self.free_bufs.append(buf)

    # ── real-time callback ─────────────────────────────────────────
    def _cb_duplex(self, indata, outdata, frames, time_info, status):
        if status:
            self.last_status = str(status)
            self.status_count += 1
        self._drain_commands()
        self._capture_block(indata, frames)
        self._render(outdata, frames)

    def _cb_out(self, outdata, frames, time_info, status):
        if status:
            self.last_status = str(status)
            self.status_count += 1
        self._drain_commands()
        self._render(outdata, frames)

    def process_block(self, indata, frames):
        """Test hook: run one callback without PortAudio."""
        out = np.zeros((frames, self.n_out), dtype=np.float32)
        self._drain_commands()
        if indata is not None:
            self._capture_block(indata, frames)
        self._render(out, frames)
        return out

    def _drain_commands(self):
        cmd = self.cmd
        while cmd:
            try:
                c = cmd.popleft()
            except IndexError:
                break
            op = c[0]
            if op == 'play':
                _, v, mode, xf = c
                if mode == 'xfade':
                    for o in self.voices:
                        same = (o.rid == v.rid)          # identical material -> linear law
                        o.start_fade_out(max(1, xf), linear=same)
                        if same:
                            v.fi_linear = True
                else:
                    for o in self.voices:
                        if o.rid == v.rid:
                            o.start_fade_out(int(RETRIGGER_FADE_S * self.sr))
                self.voices.append(v)
                self.pending_play.discard(v.rid)
            elif op == 'stop_all':
                for o in self.voices:
                    o.start_fade_out(c[1])
                self._tone = []
            elif op == 'stop_rid':
                for o in self.voices:
                    if o.rid == c[1]:
                        o.start_fade_out(c[2])
            elif op == 'rec_start':
                self._rec_begin(c[1])
            elif op == 'rec_stop':
                self._rec_finish('released')
            elif op == 'tone':
                if c[1] < self.n_out:
                    self._tone = [c[1], 0, c[2], c[3], c[4]]

    def _rec_begin(self, seq):
        if self.rec_active or not self.capture_enabled or self.ring is None:
            self.rec_refused += 1
            return
        try:
            buf = self.free_bufs.popleft()
        except IndexError:
            self.rec_refused += 1          # all capture buffers still being written
            return
        p = min(self.ring_filled, self.preroll_frames)
        if p > 0:
            rl = self.ring.shape[0]
            start = (self.ring_pos - p) % rl
            first = min(p, rl - start)
            buf[:first] = self.ring[start:start + first]
            if first < p:
                buf[first:p] = self.ring[:p - first]
        self.rec_buf = buf
        self.rec_pos = p
        self.rec_pre = p
        self.rec_seq = seq
        self.rec_active = True
        self.rec_started_seq = seq

    def _rec_finish(self, reason):
        if not self.rec_active:
            return
        self.done_caps.append((self.rec_seq, self.rec_buf, self.rec_pos, reason, self.rec_pre, self.sr))
        self.rec_active = False
        self.rec_buf = None

    def _capture_block(self, indata, frames):
        if not self.capture_enabled or self.ring is None:
            return
        x = indata[:frames, self.cap_sel]
        if x.shape[0]:
            self.in_peak[:] = np.max(np.abs(x), axis=0)
        if self.preroll_frames > 0:
            rl = self.ring.shape[0]
            n = x.shape[0]
            if n >= rl:
                self.ring[:] = x[n - rl:]
                self.ring_pos = 0
            else:
                e = self.ring_pos + n
                if e <= rl:
                    self.ring[self.ring_pos:e] = x
                else:
                    k = rl - self.ring_pos
                    self.ring[self.ring_pos:] = x[:k]
                    self.ring[:n - k] = x[k:]
                self.ring_pos = e % rl
            self.ring_filled = min(rl, self.ring_filled + n)
        if self.rec_active:
            limit = self.rec_pre + self.max_frames
            n = min(x.shape[0], limit - self.rec_pos)
            if n > 0:
                self.rec_buf[self.rec_pos:self.rec_pos + n] = x[:n]
                self.rec_pos += n
            if self.rec_pos >= limit:
                self._rec_finish('max duration')

    def _render(self, outdata, frames):
        if self._tmp is None or self._tmp.shape[0] < frames or self._tmp.shape[1] != self.n_out:
            self._alloc_block_buffers(frames)           # rare: unexpected block size
        mix = self._mix[:frames]
        mix.fill(0.0)
        tmp_full = self._tmp
        g_full = self._gbuf
        alive = []
        for v in self.voices:
            if v.done:
                continue
            n = min(frames, v.n - v.pos)
            if n <= 0:
                v.done = True
                continue
            g = g_full[:n]
            g.fill(1.0)
            if v.fo_len > 0:
                k = min(n, v.fo_len - v.fo_pos)
                if k > 0:
                    t = np.arange(v.fo_pos + 1, v.fo_pos + k + 1, dtype=np.float32) / v.fo_len
                    g[:k] = v.fo_g0 * ((1.0 - t) if v.fo_linear else np.cos(0.5 * np.pi * t))
                    if v.fo_pos + k >= v.fo_len:
                        g[k - 1] = 0.0          # cos(pi/2) in float32 is -4e-8, not 0
                g[max(k, 0):] = 0.0
                v.fo_pos += max(k, 0)
            elif v.fi_pos < v.fi_len:
                k = min(n, v.fi_len - v.fi_pos)
                t = np.arange(v.fi_pos + 1, v.fi_pos + k + 1, dtype=np.float32) / v.fi_len
                g[:k] = t if v.fi_linear else np.sin(0.5 * np.pi * t)
                v.fi_pos += k
            # 2 ms declick at the file's own start (only when not fading in)
            # and at its natural end - the result itself is never altered.
            if v.fi_len == 0 and v.pos < v.declick:
                k = min(n, v.declick - v.pos)
                g[:k] *= np.arange(v.pos + 1, v.pos + k + 1, dtype=np.float32) / v.declick
            tail0 = v.n - v.declick
            if v.pos + n > tail0:
                s = max(0, tail0 - v.pos)
                idx = np.arange(v.pos + s, v.pos + n, dtype=np.float32)
                g[s:n] *= np.clip((v.n - 1 - idx) / max(1, v.declick - 1), 0.0, 1.0)
            tmp = tmp_full[:n]
            np.dot(v.audio[v.pos:v.pos + n], v.M, out=tmp)
            tmp *= g[:, None]
            mix[:n] += tmp
            v.gain = float(g[n - 1])
            v.pos += n
            if v.pos >= v.n or (v.fo_len > 0 and v.fo_pos >= v.fo_len):
                v.done = True
            else:
                alive.append(v)
        self.voices = alive
        mix *= self.trims[:self.n_out] * self.master
        if self._tone:
            ch, pos, tot, amp, fr = self._tone
            n = min(frames, tot - pos)
            if n > 0:
                t = (np.arange(pos, pos + n, dtype=np.float32)) / self.sr
                env = np.minimum(1.0, np.minimum(t / 0.01, (tot - np.arange(pos, pos + n)) / (0.01 * self.sr)))
                mix[:n, ch] += (amp * env * np.sin(2 * np.pi * fr * t)).astype(np.float32) * self.trims[ch]
                self._tone[1] = pos + n
            if self._tone[1] >= tot:
                self._tone = []
        pk_all = float(np.max(np.abs(mix))) if frames else 0.0
        if pk_all > 1.0:
            self.clip_count += 1
        if self.limit_on:
            self._protect(mix, frames, pk_all)
        self.out_peak[:] = np.max(np.abs(mix), axis=0)
        outdata[:frames] = mix
        self.blocks += 1


# ══════════════════════════════════════════════════════════════════════
#  CAPTURE WRITER  (buffer -> WAV, outside the callback)
# ══════════════════════════════════════════════════════════════════════
class CaptureWriter(threading.Thread):
    def __init__(self, engine, workspace, events, settings):
        super().__init__(name='LiveLabCaptureWriter', daemon=True)
        self.engine = engine
        self.ws = workspace
        self.events = events
        self.settings = settings          # dict with 'min_capture_s'
        self.stop_evt = threading.Event()
        self.discard = False

    def run(self):
        while not self.stop_evt.is_set():
            self.drain()
            self.stop_evt.wait(0.01)
        self.drain()

    def drain(self):
        while True:
            try:
                seq, buf, n, reason, pre, sr = self.engine.done_caps.popleft()
            except IndexError:
                return
            if self.discard:                  # shutting down: nothing will process it
                self.engine.return_buffer(buf)
                self.events.put(('capture_failed', seq, "discarded at shutdown"))
                continue
            held = (n - pre) / float(sr)
            try:
                if held < float(self.settings.get('min_capture_s', 0.2)):
                    self.events.put(('capture_short', seq, held, reason))
                    continue
                if not np.all(np.isfinite(buf[:n])):
                    self.events.put(('capture_failed', seq, "non-finite samples in capture"))
                    continue
                path = self.ws.sub('captures', 'take_%04d.wav' % seq)
                try:
                    sf.write(path, buf[:n], sr, subtype='PCM_24')
                except Exception as e:
                    try:
                        if os.path.exists(path):
                            os.remove(path)
                    except OSError:
                        pass
                    self.events.put(('capture_failed', seq, "could not write capture: %s" % e))
                    continue
                self.events.put(('capture_ready', seq, path, n / float(sr), buf.shape[1], sr,
                                 reason, held))
            finally:
                self.engine.return_buffer(buf)


# ══════════════════════════════════════════════════════════════════════
#  PRAAT PROCESSING MANAGER  (one isolated worker at a time, FIFO)
# ══════════════════════════════════════════════════════════════════════
def worker_env(jdir):
    """Environment for one Praat worker: every temp-dir variable points
    into the job folder, so anything a module writes to "the temp folder"
    is deleted together with the job."""
    env = dict(os.environ)
    tdir = os.path.join(jdir, 'tmp')
    os.makedirs(tdir, exist_ok=True)
    for k in ('TEMP', 'TMP', 'TMPDIR'):
        env[k] = tdir
    return env


class Job:
    def __init__(self, result, target_sr):
        self.result = result
        self.target_sr = int(target_sr)
        self.started = 0.0
        self.jid = "%s_%s" % (result.rid.replace('.', '_'), secrets.token_hex(3))


def parse_status(text):
    d = {}
    for ln in text.splitlines():
        if '=' in ln:
            k, v = ln.split('=', 1)
            d[k.strip()] = v.strip()
    return d


class ProcessingManager(threading.Thread):
    def __init__(self, workspace, guard, events, paths, praat_info, timeout_s=300.0):
        super().__init__(name='LiveLabProcessing', daemon=True)
        self.ws = workspace
        self.guard = guard
        self.events = events
        self.paths = paths                 # dict: plugin_dir, chain_dir, worker
        self.praat = praat_info or {}
        self.timeout_s = float(timeout_s)
        self.q = collections.deque()
        self.cv = threading.Condition()
        self.accepting = True
        self.stopping = False
        self.current = None
        self.proc = None
        self.cancel_current = False
        self.done_count = 0
        self.fail_count = 0

    # -- control (main thread) --
    def submit(self, job):
        with self.cv:
            if not self.accepting:
                return False
            self.q.append(job)
            self.cv.notify()
            return True

    def queued(self):
        with self.cv:
            return [j.result.rid for j in self.q]

    def cancel_all(self):
        with self.cv:
            dropped = list(self.q)
            self.q.clear()
            self.cancel_current = True
        for j in dropped:
            self.events.put(('job_cancelled', j.result.rid, "cancelled"))
        p = self.proc
        if p is not None:
            self.guard.kill_tree(p)

    def shutdown(self, wait_s=10.0):
        with self.cv:
            self.accepting = False
            self.stopping = True
            self.cv.notify_all()
        self.cancel_all()
        self.join(wait_s)
        return not self.is_alive()

    def set_praat(self, info):
        self.praat = info or {}

    # -- worker thread --
    def run(self):
        while True:
            with self.cv:
                while not self.q and not self.stopping:
                    self.cv.wait(0.5)
                if self.stopping:
                    return
                job = self.q.popleft()
                self.current = job
                self.cancel_current = False
            try:
                self._run_job(job)
            except Exception as e:
                self.fail_count += 1
                self.events.put(('job_failed', job.result.rid, "internal error: %s" % e))
            finally:
                self.current = None
                self.proc = None

    def _run_job(self, job):
        """Run one job; the outcome event is posted only AFTER the job
        folder has been removed, so 'done' really means no residue."""
        self._outbox = []
        try:
            self._run_job_inner(job)
        finally:
            for ev in self._outbox:
                self.events.put(ev)
            self._outbox = []

    def _emit(self, ev):
        self._outbox.append(ev)

    def _run_job_inner(self, job):
        r = job.result
        job.started = time.time()
        self.events.put(('job_started', r.rid))  # immediate
        exe = self.praat.get('path', '')
        if not exe:
            self.fail_count += 1
            self._emit(('job_failed', r.rid, "no Praat executable configured (Setup > Praat)"))
            return
        jdir = self.ws.sub('jobs', 'job_' + job.jid)
        os.makedirs(jdir)
        try:
            adapter = os.path.join(jdir, 'adapter.praat')
            if r.chain_key == 'selftest':
                txt = SELFTEST_ADAPTER
            else:
                ch = CHAIN_BY_KEY[r.chain_key]
                src = os.path.join(self.paths['chain_dir'], ch['file'])
                with open(src, 'r', encoding='utf-8') as f:
                    txt, _rep = derive_adapter(f.read(), self.paths['chain_dir'],
                                               self.paths['plugin_dir'], ch['file'])
            with open(adapter, 'w', encoding='utf-8', newline='\n') as f:
                f.write(txt)
            out_wav = os.path.join(jdir, 'result.wav')
            status = os.path.join(jdir, 'status.txt')
            log_path = os.path.join(jdir, 'worker_log.txt')
            cmd = ([exe] + list(self.praat.get('flags', [])) + ['--run', self.paths['worker'],
                   adapter, r.take.capture_path, out_wav, status,
                   "%.6f" % r.take.capture_dur, str(r.seed), str(job.target_sr)])
            with open(log_path, 'wb') as log_fh:
                self.proc = self.guard.popen(cmd, log_fh, cwd=jdir, env=worker_env(jdir))
                pid_file = self.ws.sub('worker.pid')
                try:
                    with open(pid_file, 'w') as pf:
                        pf.write(str(self.proc.pid))
                except OSError:
                    pass
                verdict = None
                while self.proc.poll() is None:
                    if self.cancel_current:
                        self.guard.kill_tree(self.proc)
                        verdict = 'cancelled'
                    elif time.time() - job.started > self.timeout_s:
                        self.guard.kill_tree(self.proc)
                        verdict = 'timeout'
                    time.sleep(0.05)
                try:
                    self.proc.wait(10)        # reap
                except Exception:
                    pass
                code = self.proc.returncode
                if verdict is None and self.cancel_current:
                    verdict = 'cancelled'       # killed directly by cancel_all()
                try:
                    os.remove(pid_file)
                except OSError:
                    pass
            if verdict == 'cancelled':
                self._emit(('job_cancelled', r.rid, "cancelled while processing"))
                return
            if verdict == 'timeout':
                self.fail_count += 1
                self._emit(('job_failed', r.rid, "worker timeout after %.0f s (killed)" % self.timeout_s))
                return
            st = {}
            if os.path.exists(status):
                with open(status, 'r', encoding='utf-8', errors='replace') as f:
                    st = parse_status(f.read())
            if code != 0 or st.get('state') != 'ok':
                try:
                    with open(log_path, 'rb') as f:
                        tail = _decode_praat_output(f.read()[-4000:]).strip()
                except OSError:
                    tail = ''
                msg = st.get('error') or (tail.splitlines()[-6:] and " | ".join(tail.splitlines()[-6:])) \
                    or "worker exited with code %s" % code
                self.fail_count += 1
                self._emit(('job_failed', r.rid, "Praat: %s" % msg))
                return
            # Validate the handoff before anything is shown as READY.
            info = sf.info(out_wav)
            if info.samplerate != job.target_sr:
                raise ValueError("result rate %d Hz, expected %d Hz" % (info.samplerate, job.target_sr))
            if str(info.channels) != st.get('channels') or str(info.frames) != st.get('frames'):
                raise ValueError("result file does not match the worker report "
                                 "(%d ch / %d frames vs %s / %s)" % (info.channels, info.frames,
                                                                    st.get('channels'), st.get('frames')))
            audio, _sr = sf.read(out_wav, dtype='float32', always_2d=True)
            if audio.shape[0] < 2 or not np.all(np.isfinite(audio)):
                raise ValueError("result audio is empty or contains non-finite samples")
            audio = np.ascontiguousarray(audio)
            self.done_count += 1
            self._emit(('job_done', r.rid, audio, st, time.time() - job.started))
        except AdapterError as e:
            self.fail_count += 1
            self._emit(('job_failed', r.rid, "adapter: %s" % e))
        except Exception as e:
            self.fail_count += 1
            self._emit(('job_failed', r.rid, "%s" % e))
        finally:
            _rmtree_retry(jdir)       # processing success or failure: no residue


# ══════════════════════════════════════════════════════════════════════
#  MIDI INPUT + MAPPING
# ══════════════════════════════════════════════════════════════════════
ACTIONS = ([('hold_record', 'Hold to Record (pedal)')]
           + [('chain_%d' % (i + 1), 'Select %s' % c['label']) for i, c in enumerate(CHAINS)]
           + [('play', 'Play / Retrigger'), ('prev', 'Previous result'), ('next', 'Next result'),
              ('latest', 'Latest Ready'), ('regenerate', 'Regenerate'),
              ('crossfade', 'Crossfade to selected'), ('auto_suspend', 'Toggle Auto Suspend'),
              ('arm', 'ARM / DISARM'), ('pin', 'Pin / Unpin'), ('stop_all', 'Stop All')])
ACTION_LABEL = dict(ACTIONS)

DEFAULT_KEYS = {
    'hold_record': 'f', 'play': 'space', 'regenerate': 'r', 'prev': 'bracketleft',
    'next': 'bracketright', 'crossfade': 'c', 'auto_suspend': 'a', 'pin': 'p',
    'stop_all': 'Escape', 'latest': 'l', 'arm': 'F2',
}
for _i in range(9):
    DEFAULT_KEYS['chain_%d' % (_i + 1)] = str(_i + 1)

_NOTE_NAMES = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B')


def midi_note_name(n):
    if n is None or n < 0 or n > 127:
        return '-'
    return "%s%d" % (_NOTE_NAMES[n % 12], n // 12 - 1)


def mapping_text(m):
    if not m:
        return "(unmapped)"
    ch = m.get('channel', 0)
    chs = (" ch%d" % ch) if ch else ""
    if m.get('type') == 'note':
        return "Note %s (%d)%s" % (midi_note_name(m['number']), m['number'], chs)
    return "CC %d%s" % (m['number'], chs)


class MidiMapper:
    """Pure MIDI -> event logic, edge-triggered. handle() runs on the rtmidi
    thread; it only reads attributes that the main thread swaps whole."""

    def __init__(self):
        self.mappings = {}         # action -> {'type','number','channel'}
        self.channel = 0           # 0 = omni
        self.polarity = 'normal'   # pedal CC polarity
        self.cc_on = 64
        self.cc_off = 40
        self.learn = None          # None | action name
        self.pedal_down = False
        self._cc_armed = {}        # (ch, cc) -> True when below release
        self.last_cc = {}

    def set_mappings(self, m):
        self.mappings = dict(m)

    def _match(self, kind, number, ch):
        hits = []
        for act, m in self.mappings.items():
            if m and m.get('type') == kind and m.get('number') == number:
                if m.get('channel', 0) in (0, ch):
                    hits.append(act)
        return hits

    def pedal_released_by_disconnect(self):
        if self.pedal_down:
            self.pedal_down = False
            return [('pedal', False, 'disconnect')]
        return []

    def handle(self, msg):
        if not msg:
            return []
        status = msg[0]
        kind = status & 0xF0
        if kind not in (0x80, 0x90, 0xB0) or len(msg) < 3:
            return []
        ch = (status & 0x0F) + 1
        d1, d2 = msg[1], msg[2]
        desc = ("Note %s v%d ch%d" % (midi_note_name(d1), d2, ch)) if kind != 0xB0 else \
               ("CC %d=%d ch%d" % (d1, d2, ch))
        if self.channel and ch != self.channel:
            return [('filtered', desc)]
        ev = [('raw', desc)]

        # MIDI learn: the next qualifying message becomes the mapping.
        if self.learn is not None:
            target = self.learn
            if kind == 0x90 and d2 > 0:
                self.learn = None
                ev.append(('learned', target, {'type': 'note', 'number': d1, 'channel': ch}, ''))
            elif kind == 0xB0 and d1 not in (120, 123):
                if target == 'hold_record':
                    # "press and HOLD": a high value now = normal pedal,
                    # a low value now = inverted (reversed-polarity) pedal.
                    pol = 'normal' if d2 >= 64 else 'inverted'
                    self.learn = None
                    ev.append(('learned', target, {'type': 'cc', 'number': d1, 'channel': ch}, pol))
                elif d2 >= 64:
                    self.learn = None
                    ev.append(('learned', target, {'type': 'cc', 'number': d1, 'channel': ch}, ''))
            return ev

        if kind == 0xB0 and d1 in (120, 123):
            ev.append(('action', 'stop_all'))
            return ev

        if kind in (0x90, 0x80):
            on = kind == 0x90 and d2 > 0
            acts = self._match('note', d1, ch)
            if not acts:
                if on:
                    ev.append(('unmapped', desc))
                return ev
            for a in acts:
                if a == 'hold_record':
                    if on and not self.pedal_down:
                        self.pedal_down = True
                        ev.append(('pedal', True, desc))
                    elif not on and self.pedal_down:
                        self.pedal_down = False
                        ev.append(('pedal', False, desc))
                elif on:
                    ev.append(('action', a))
            return ev

        # Control change
        acts = self._match('cc', d1, ch)
        if not acts:
            if d2 >= 64:
                ev.append(('unmapped', desc))
            return ev
        self.last_cc[(ch, d1)] = d2
        for a in acts:
            if a == 'hold_record':
                v = d2 if self.polarity == 'normal' else 127 - d2
                if v >= self.cc_on and not self.pedal_down:
                    self.pedal_down = True
                    ev.append(('pedal', True, desc))
                elif v <= self.cc_off and self.pedal_down:
                    self.pedal_down = False
                    ev.append(('pedal', False, desc))
            else:
                key = (ch, d1, a)
                armed = self._cc_armed.get(key, True)
                if d2 >= 64 and armed:
                    self._cc_armed[key] = False
                    ev.append(('action', a))
                elif d2 <= 40:
                    self._cc_armed[key] = True
        return ev


def _norm_port_name(name):
    return re.sub(r'\s+\d+(:\d+)?$', '', name or '').strip()


class MidiInput:
    """python-rtmidi wrapper (from performance_launcher.py v1.7.3)."""

    def __init__(self, on_message):
        self.available = rtmidi is not None
        self.port_name = ''
        self._in = None
        self._on_message = on_message

    def list_ports(self):
        if not self.available:
            return []
        try:
            probe = rtmidi.MidiIn()
            ports = list(probe.get_ports())
            del probe
            return ports
        except Exception:
            return []

    def find_port(self, wanted, ports=None):
        ports = self.list_ports() if ports is None else ports
        if not wanted:
            return -1
        if wanted in ports:
            return ports.index(wanted)
        w = _norm_port_name(wanted)
        for i, p in enumerate(ports):
            if _norm_port_name(p) == w:
                return i
        return -1

    def open(self, wanted):
        self.close()
        if not self.available:
            return False, "python-rtmidi is not installed"
        ports = self.list_ports()
        idx = self.find_port(wanted, ports)
        if idx < 0:
            return False, "MIDI port not found: %s" % wanted
        try:
            mi = rtmidi.MidiIn()
            mi.ignore_types(sysex=True, timing=True, active_sense=True)
            mi.open_port(idx)
            mi.set_callback(self._callback)
            self._in = mi
            self.port_name = ports[idx]
            return True, "MIDI in: %s" % self.port_name
        except Exception as e:
            self._in = None
            return False, ("Could not open MIDI port %s: %s (already open in another app?)"
                           % (ports[idx], e))

    def _callback(self, event, _data=None):
        try:
            msg, _delta = event
            self._on_message(msg)
        except Exception:
            pass

    def close(self):
        if self._in is not None:
            try:
                self._in.cancel_callback()
            except Exception:
                pass
            try:
                self._in.close_port()
            except Exception:
                pass
            try:
                del self._in
            except Exception:
                pass
            self._in = None
        self.port_name = ''

    @property
    def is_open(self):
        return self._in is not None


# ══════════════════════════════════════════════════════════════════════
#  CONFIGURATION  (the only thing that persists, besides exports)
# ══════════════════════════════════════════════════════════════════════
def _default_export_dir():
    docs = os.path.join(os.path.expanduser('~'), 'Documents')
    return os.path.join(docs if os.path.isdir(docs) else os.path.expanduser('~'), 'Live Lab Exports')


def default_config():
    return {
        'version': 1,
        'audio': {'hostapi': '', 'in_device': '', 'out_device': '', 'sample_rate': 48000,
                  'blocksize': 512, 'input_mode': 'Mono', 'input_ch': [1, 2],
                  'capture_enabled': True},
        'routing': json.loads(json.dumps(DEFAULT_ROUTING)),
        'master_gain_db': 0.0,
        'stop_fade_s': 0.25,
        'capture': {'min_s': 0.2, 'max_s': 60.0, 'preroll_on': True, 'preroll_ms': 250},
        'bank': {'capacity': 16, 'memory_mb': 1500},
        'midi': {'port': '', 'channel': 'Omni', 'mappings': {}, 'polarity': 'normal',
                 'cc_on': 64, 'cc_off': 40},
        'keys': dict(DEFAULT_KEYS),
        'chains': {c['key']: {'policy': 'manual', 'xfade': 3.0} for c in CHAINS},
        'praat': {'path': '', 'timeout_s': 300},
        'export_dir': _default_export_dir(),
        'auto_suspend': False,
        'limiter': {'on': True, 'ceiling_db': -0.3},
        'presets': {},
    }


def _merge(base, over):
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(base.get(k), dict) and k not in ('presets', 'mappings'):
            _merge(base[k], v)
        else:
            base[k] = v
    return base


def load_config(path):
    cfg = default_config()
    try:
        with open(path, 'r', encoding='utf-8') as f:
            _merge(cfg, json.load(f))
    except FileNotFoundError:
        pass
    except Exception as e:
        log_line("config unreadable, using defaults: %s" % e)
    # New-config default: every chain MANUAL (only set when absent).
    for c in CHAINS:
        cc = cfg['chains'].setdefault(c['key'], {'policy': 'manual', 'xfade': 3.0})
        if cc.get('policy') not in ('manual', 'auto'):
            cc['policy'] = 'manual'
        try:
            cc['xfade'] = max(0.0, min(30.0, float(cc.get('xfade', 3.0))))
        except (TypeError, ValueError):
            cc['xfade'] = 3.0
    return cfg


def save_config(path, cfg):
    """Atomic write: temp file in the same folder, then replace."""
    if not path:
        return False
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        tmp = path + '.tmp_%d' % os.getpid()
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)
        os.replace(tmp, path)
        return True
    except Exception as e:
        log_line("config save failed: %s" % e)
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except Exception:
            pass
        return False


PRESET_KEYS = ('routing', 'chains', 'master_gain_db', 'stop_fade_s', 'capture', 'keys', 'midi_map')


def make_preset(cfg):
    p = {k: json.loads(json.dumps(cfg[k])) for k in PRESET_KEYS if k in cfg}
    p['midi_map'] = {k: cfg['midi'][k] for k in ('mappings', 'polarity', 'cc_on', 'cc_off', 'channel')}
    return p


def apply_preset(cfg, p):
    for k in ('routing', 'chains', 'master_gain_db', 'stop_fade_s', 'capture', 'keys'):
        if k in p:
            cfg[k] = json.loads(json.dumps(p[k]))
    if 'midi_map' in p:
        cfg['midi'].update(json.loads(json.dumps(p['midi_map'])))


# ══════════════════════════════════════════════════════════════════════
#  GUI
# ══════════════════════════════════════════════════════════════════════
BG = "#0f0f17"
PANEL = "#171724"
PANEL2 = "#1f1f30"
BTN = "#2a2a44"
FG = "#f2f2f8"
DIM = "#8a8ab0"
ACCENT = "#ffaa44"
REC = "#e0304a"
OK = "#3fbf6a"
WARN = "#e8c547"
ERR = "#c84646"
SEL = "#3d5afe"
PLAYING = "#2e7d4f"
FONT = "Segoe UI" if sys.platform == "win32" else ("Helvetica Neue" if sys.platform == "darwin" else "DejaVu Sans")
MONO = "Consolas" if sys.platform == "win32" else ("Menlo" if sys.platform == "darwin" else "DejaVu Sans Mono")
TEXT_CLASSES = {'Entry', 'TEntry', 'Spinbox', 'TSpinbox', 'Text', 'TCombobox', 'Listbox'}


def fmt_time(s):
    s = max(0.0, s)
    return "%d:%02d.%d" % (int(s) // 60, int(s) % 60, int((s - int(s)) * 10))


def db(x):
    return -120.0 if x <= 1e-6 else 20.0 * math.log10(x)


class Meter:
    """Simple vertical peak meters with hold, -60..0 dBFS."""

    def __init__(self, parent, n, width=120, height=90, labels=None):
        import tkinter as tk
        self.c = tk.Canvas(parent, width=width, height=height, bg=PANEL, highlightthickness=0)
        self.n = n
        self.w, self.h = width, height
        self.hold = [-120.0] * n
        self.hold_t = [0.0] * n
        self.labels = labels or [str(i + 1) for i in range(n)]

    def set_n(self, n, labels=None):
        self.n = n
        self.hold = [-120.0] * n
        self.hold_t = [0.0] * n
        self.labels = labels or [str(i + 1) for i in range(n)]

    def update(self, peaks):
        c = self.c
        c.delete('all')
        n = max(1, self.n)
        bw = max(4, (self.w - 8) / n - 3)
        top, bot = 4, self.h - 14
        now = time.monotonic()
        for i in range(n):
            p = float(peaks[i]) if i < len(peaks) else 0.0
            d = max(-60.0, min(0.0, db(p)))
            if d > self.hold[i] or now - self.hold_t[i] > 1.5:
                self.hold[i] = d
                self.hold_t[i] = now
            x0 = 4 + i * (bw + 3)
            frac = (d + 60.0) / 60.0
            y = bot - frac * (bot - top)
            col = OK if d < -12 else (WARN if d < -3 else REC)
            c.create_rectangle(x0, top, x0 + bw, bot, fill="#0a0a12", outline="")
            if frac > 0:
                c.create_rectangle(x0, y, x0 + bw, bot, fill=col, outline="")
            hy = bot - (self.hold[i] + 60.0) / 60.0 * (bot - top)
            c.create_line(x0, hy, x0 + bw, hy, fill=FG)
            c.create_text(x0 + bw / 2, self.h - 6, text=self.labels[i] if i < len(self.labels) else '',
                          fill=DIM, font=(FONT, 7))


class LiveLabApp:
    def __init__(self, root, args, workspace, recovery_report):
        import tkinter as tk
        from tkinter import ttk
        self.tk, self.ttk = tk, ttk
        self.root = root
        self.args = args
        self.ws = workspace
        self.plugin_dir = os.path.abspath(args.plugin_dir)
        self.chain_dir = os.path.abspath(args.chain_dir)
        std = os.path.join(self.plugin_dir, 'Vector Chain')
        if (not os.path.isfile(os.path.join(self.chain_dir, CHAINS[0]['file']))
                and os.path.isfile(os.path.join(std, CHAINS[0]['file']))):
            self.chain_dir = std          # e.g. launched from a script that sits in py/
        self.worker_script = write_worker(self.ws)       # embedded, lives in the workspace
        self.config_path = os.path.join(self.plugin_dir, 'live_lab_config.json')
        self.cfg = load_config(self.config_path)
        self.closing = False
        self.log = collections.deque(maxlen=600)
        for ln in recovery_report:
            self._log(ln)

        self.events = queue.Queue()
        self.midi_q = queue.Queue()
        self.guard = ProcessGuard()
        self.engine = AudioEngine()
        self.clock = DecisionClock()
        self.bank = ResultBank(self.cfg['bank']['capacity'], self.cfg['bank']['memory_mb'],
                               on_take_released=self._release_take)
        self.armed = True
        self.auto_suspend = bool(self.cfg.get('auto_suspend', False))
        self.sel_chain = 0
        self.recording = False
        self.rec_seq = 0
        self.rec_t0 = 0.0
        self.rec_refused_seen = 0
        self.pending = {}
        self.finalizing = {}          # take seq -> time of release, until the writer reports
        self.next_take = 1
        self.audio_expected = False
        self.audio_msg = "audio not started"
        self.praat = {'path': ''}
        self.status_var = tk.StringVar(value="Starting…")
        self.capture_settings = {'min_capture_s': self.cfg['capture']['min_s']}
        self._apply_limiter_cfg()
        self._key_hold_pending = None
        self._key_hold_down = False
        self._last_port_check = 0.0
        self._devices = []
        self._test_seq = []
        self._seen_status = 0
        self._seen_clip = 0
        self._last_xfade_note = ''

        self.mapper = MidiMapper()
        self._apply_midi_cfg()
        self.midi = MidiInput(self._on_midi_message)

        self.proc_mgr = ProcessingManager(self.ws, self.guard, self.events,
                                          {'plugin_dir': self.plugin_dir, 'chain_dir': self.chain_dir,
                                           'worker': self.worker_script},
                                          None, self.cfg['praat'].get('timeout_s', 300))
        self.proc_mgr.start()
        self.writer = CaptureWriter(self.engine, self.ws, self.events, self.capture_settings)
        self.writer.start()

        self._build_ui()
        self._refresh_auto_btn()
        self._check_chains()
        self._apply_master()
        self._open_audio()
        self._open_saved_midi()
        threading.Thread(target=self._detect_praat_bg, daemon=True).start()

        root.protocol("WM_DELETE_WINDOW", self.close)
        root.bind_all('<KeyPress>', self._on_key_press, add='+')
        root.bind_all('<KeyRelease>', self._on_key_release, add='+')
        root.bind_all('<<ComboboxSelected>>', lambda e: root.after_idle(self._reclaim_focus), add='+')
        root.bind_all('<ButtonRelease-1>', self._on_click_release, add='+')
        root.bind('<FocusOut>', self._on_focus_out, add='+')
        self._front_id = root.after(200, self._bring_front)
        self._tick()
        self._refresh_ui()

    # ── logging / status ─────────────────────────────────────────────
    def _log(self, msg):
        line = time.strftime("%H:%M:%S ") + msg
        self.log.append(line)
        log_line(msg)
        w = getattr(self, 'log_text', None)
        if w is not None:
            try:
                w.configure(state='normal')
                w.insert('end', line + "\n")
                w.see('end')
                w.configure(state='disabled')
            except Exception:
                pass

    def status(self, msg, log=True):
        self.status_var.set(msg)
        if log:
            self._log(msg)

    # ── UI construction ──────────────────────────────────────────────
    def _build_ui(self):
        tk, ttk = self.tk, self.ttk
        r = self.root
        r.title("Praat AudioTools Live Lab 1.0")
        r.configure(bg=BG)
        r.geometry("1280x860")
        r.minsize(1060, 720)
        st = ttk.Style()
        try:
            st.theme_use('clam')
        except Exception:
            pass
        st.configure('.', background=PANEL, foreground=FG, fieldbackground=PANEL2)
        st.configure('TNotebook', background=BG, borderwidth=0)
        st.configure('TNotebook.Tab', background=BTN, foreground=FG, padding=(12, 5))
        st.map('TNotebook.Tab', background=[('selected', SEL)])
        st.configure('Treeview', background=PANEL2, fieldbackground=PANEL2, foreground=FG,
                     rowheight=22, font=(FONT, 10))
        st.configure('Treeview.Heading', background=BTN, foreground=FG, font=(FONT, 9, 'bold'))
        st.map('Treeview', background=[('selected', SEL)])
        st.configure('TCombobox', fieldbackground=PANEL2, background=BTN, foreground=FG,
                     arrowcolor=FG)
        st.map('TCombobox', fieldbackground=[('readonly', PANEL2)], foreground=[('readonly', FG)])
        st.configure('Horizontal.TProgressbar', troughcolor=PANEL2, background=OK, thickness=10)
        st.configure('X.Horizontal.TProgressbar', troughcolor=PANEL2, background=ACCENT, thickness=10)

        # top bar
        top = tk.Frame(r, bg=PANEL)
        top.pack(fill='x', padx=6, pady=(6, 3))
        tk.Label(top, text=APP_TITLE, bg=PANEL, fg=FG, font=(FONT, 14, 'bold')).pack(side='left', padx=10, pady=6)
        self.view_btns = {}
        for name in ('SETUP', 'PERFORMANCE'):
            b = tk.Button(top, text=name, bg=BTN, fg=FG, relief='flat', font=(FONT, 10, 'bold'),
                          padx=12, activebackground=SEL, activeforeground=FG,
                          command=lambda n=name: self.show_view(n))
            b.pack(side='right', padx=3, pady=5)
            self.view_btns[name] = b
        self.arm_btn = tk.Button(top, text="ARMED", bg=REC, fg=FG, relief='flat', width=10,
                                 font=(FONT, 11, 'bold'), command=self.toggle_arm)
        self.arm_btn.pack(side='right', padx=10)
        self.midi_lbl = tk.Label(top, text="MIDI: -", bg=PANEL, fg=DIM, font=(FONT, 10))
        self.midi_lbl.pack(side='right', padx=10)
        self.audio_lbl = tk.Label(top, text="AUDIO: -", bg=PANEL, fg=DIM, font=(FONT, 10))
        self.audio_lbl.pack(side='right', padx=10)

        self.perf = tk.Frame(r, bg=BG)
        self.setup = tk.Frame(r, bg=BG)
        self._build_performance(self.perf)
        self._build_setup(self.setup)
        tk.Label(r, textvariable=self.status_var, bg=PANEL, fg=DIM, anchor='w',
                 font=(FONT, 10)).pack(fill='x', side='bottom', padx=6, pady=(0, 6))
        self.show_view('PERFORMANCE')

    def _panel(self, parent, title):
        tk = self.tk
        f = tk.Frame(parent, bg=PANEL, highlightthickness=0)
        tk.Label(f, text=title, bg=PANEL, fg=DIM, font=(FONT, 9, 'bold'), anchor='w').pack(fill='x', padx=8, pady=(5, 0))
        return f

    def _build_performance(self, p):
        tk, ttk = self.tk, self.ttk
        row1 = tk.Frame(p, bg=BG)
        row1.pack(fill='x', padx=6, pady=3)

        # Global input
        inp = self._panel(row1, "GLOBAL INPUT")
        inp.pack(side='left', fill='y', padx=(0, 4))
        self.in_mode_lbl = tk.Label(inp, text="-", bg=PANEL, fg=FG, font=(FONT, 11, 'bold'))
        self.in_mode_lbl.pack(padx=8, anchor='w')
        self.in_meter = Meter(inp, 2, width=110, height=120)
        self.in_meter.c.pack(padx=8, pady=6)

        # Chains
        ch = self._panel(row1, "PROCESSING CHAINS  (keys 1-9)")
        ch.pack(side='left', fill='both', expand=True, padx=4)
        grid = tk.Frame(ch, bg=PANEL)
        grid.pack(fill='both', expand=True, padx=6, pady=6)
        self.chain_btns = []
        for i, c in enumerate(CHAINS):
            b = tk.Button(grid, text='', bg=BTN, fg=FG, relief='flat', justify='left', anchor='w',
                          font=(FONT, 11, 'bold'), padx=10, pady=6, activebackground=SEL,
                          activeforeground=FG, command=lambda k=i: self.select_chain(k))
            b.grid(row=i // 3, column=i % 3, sticky='nsew', padx=3, pady=3)
            self.chain_btns.append(b)
        for k in range(3):
            grid.columnconfigure(k, weight=1)
            grid.rowconfigure(k, weight=1)

        # Capture
        cap = self._panel(row1, "CAPTURE")
        cap.pack(side='left', fill='y', padx=(4, 0))
        self.rec_lbl = tk.Label(cap, text="HOLD TO RECORD", bg=PANEL2, fg=FG, width=18,
                                font=(FONT, 20, 'bold'), pady=14)
        self.rec_lbl.pack(padx=8, pady=(6, 4))
        self.rec_time = tk.Label(cap, text="0:00.0", bg=PANEL, fg=FG, font=(MONO, 22, 'bold'))
        self.rec_time.pack()
        self.rec_info = tk.Label(cap, text="Take -   ·   chain -", bg=PANEL, fg=DIM, font=(FONT, 10))
        self.rec_info.pack(pady=(2, 0))
        self.rec_state = tk.Label(cap, text="", bg=PANEL, fg=ACCENT, font=(FONT, 10), wraplength=300)
        self.rec_state.pack(pady=(2, 8))

        row2 = tk.Frame(p, bg=BG)
        row2.pack(fill='x', padx=6, pady=3)

        pr = self._panel(row2, "PROCESSING  (one Praat worker, FIFO)")
        pr.pack(side='left', fill='both', expand=True, padx=(0, 4))
        self.proc_active = tk.Label(pr, text="idle", bg=PANEL, fg=FG, font=(FONT, 12, 'bold'), anchor='w')
        self.proc_active.pack(fill='x', padx=8, pady=(4, 0))
        self.proc_counts = tk.Label(pr, text="", bg=PANEL, fg=DIM, font=(FONT, 10), anchor='w')
        self.proc_counts.pack(fill='x', padx=8)
        self.proc_err = tk.Label(pr, text="", bg=PANEL, fg=ERR, font=(FONT, 9), anchor='w',
                                 justify='left', wraplength=520)
        self.proc_err.pack(fill='x', padx=8, pady=(0, 6))

        pb = self._panel(row2, "PLAYBACK")
        pb.pack(side='left', fill='both', expand=True, padx=4)
        self.now_lbl = tk.Label(pb, text="NOW PLAYING: -", bg=PANEL, fg=FG, font=(FONT, 12, 'bold'), anchor='w')
        self.now_lbl.pack(fill='x', padx=8, pady=(4, 0))
        self.now_bar = ttk.Progressbar(pb, mode='determinate', maximum=1000)
        self.now_bar.pack(fill='x', padx=8, pady=2)
        self.xf_lbl = tk.Label(pb, text="", bg=PANEL, fg=ACCENT, font=(FONT, 10), anchor='w')
        self.xf_lbl.pack(fill='x', padx=8)
        self.next_lbl = tk.Label(pb, text="NEXT / READY: -", bg=PANEL, fg=DIM, font=(FONT, 11), anchor='w')
        self.next_lbl.pack(fill='x', padx=8, pady=(2, 2))
        gl = tk.Frame(pb, bg=PANEL)
        gl.pack(fill='x', padx=8, pady=(0, 6))
        tk.Label(gl, text="Master", bg=PANEL, fg=DIM).pack(side='left')
        self.master_var = tk.DoubleVar(value=self.cfg.get('master_gain_db', 0.0))
        tk.Scale(gl, from_=-40, to=6, resolution=0.5, orient='horizontal', variable=self.master_var,
                 bg=PANEL, fg=FG, troughcolor=PANEL2, highlightthickness=0, length=180, showvalue=True,
                 command=lambda _v: self._apply_master()).pack(side='left', padx=6)
        self.auto_btn = tk.Button(gl, text="", bg=BTN, fg=FG, relief='flat', width=15,
                                  command=self.toggle_auto_suspend)
        self.auto_btn.pack(side='left', padx=6)
        tk.Button(gl, text="■ STOP ALL  [Esc]", bg=ERR, fg=FG, relief='flat', font=(FONT, 11, 'bold'),
                  padx=10, command=self.stop_all).pack(side='right')

        om = self._panel(row2, "OUTPUT")
        om.pack(side='left', fill='y', padx=(4, 0))
        self.out_meter = Meter(om, 2, width=200, height=100)
        self.out_meter.c.pack(padx=8, pady=(4, 0))
        self.ovl_lbl = tk.Label(om, text="", bg=PANEL, fg=DIM, font=(FONT, 9), wraplength=200, justify='left')
        self.ovl_lbl.pack(padx=8, pady=(0, 6), anchor='w')

        # Result bank
        bk = self._panel(p, "RESULT BANK")
        bk.pack(fill='both', expand=True, padx=6, pady=(3, 3))
        cols = ('id', 'chain', 'status', 'dur', 'ch', 'policy', 'pin', 'seed', 'note')
        self.tree = ttk.Treeview(bk, columns=cols, show='headings', height=8, selectmode='browse')
        for c, w, t in (('id', 70, 'ID'), ('chain', 130, 'Chain'), ('status', 110, 'Status'),
                        ('dur', 70, 'Dur'), ('ch', 40, 'Ch'), ('policy', 70, 'Policy'),
                        ('pin', 45, 'Pin'), ('seed', 75, 'Seed'), ('note', 520, 'Note')):
            self.tree.heading(c, text=t)
            self.tree.column(c, width=w, anchor='w', stretch=(c == 'note'))
        self.tree.tag_configure('PLAYING', background=PLAYING)
        self.tree.tag_configure('FAILED', foreground=ERR)
        self.tree.tag_configure('PROCESSING', foreground=WARN)
        self.tree.tag_configure('QUEUED', foreground=DIM)
        self.tree.pack(fill='both', expand=True, padx=6, pady=(4, 2))
        self.tree.bind('<<TreeviewSelect>>', self._on_tree_select)
        self.tree.bind('<Double-1>', lambda e: self.play_selected())
        bb = tk.Frame(bk, bg=PANEL)
        bb.pack(fill='x', padx=6, pady=(0, 6))
        for txt, cmd in (("▶ Play / Retrigger [Space]", self.play_selected),
                         ("⇄ Crossfade [C]", self.crossfade_selected),
                         ("↻ Regenerate [R]", self.regenerate_selected),
                         ("📌 Pin [P]", self.pin_selected),
                         ("◆ Latest Ready [L]", self.latest_ready),
                         ("⇩ Export selected", self.export_selected)):
            tk.Button(bb, text=txt, bg=BTN, fg=FG, relief='flat', padx=10, pady=3,
                      command=cmd).pack(side='left', padx=3)
        self.bank_info = tk.Label(bb, text="", bg=PANEL, fg=DIM, font=(FONT, 9))
        self.bank_info.pack(side='right', padx=6)

    # ── setup view ───────────────────────────────────────────────────
    def _row(self, parent, label, widget_fn, r, hint=''):
        tk = self.tk
        tk.Label(parent, text=label, bg=PANEL, fg=DIM, anchor='w').grid(row=r, column=0, sticky='w', padx=8, pady=3)
        w = widget_fn(parent)
        w.grid(row=r, column=1, sticky='w', padx=8, pady=3)
        if hint:
            tk.Label(parent, text=hint, bg=PANEL, fg=DIM, anchor='w', font=(FONT, 8)).grid(
                row=r, column=2, sticky='w', padx=4)
        return w

    def _entry(self, var, width=10):
        return lambda p: self.tk.Entry(p, textvariable=var, width=width, bg=PANEL2, fg=FG,
                                       insertbackground=FG, relief='flat')

    def _combo(self, var, values, width=30):
        def mk(p):
            c = self.ttk.Combobox(p, textvariable=var, values=values, width=width, state='readonly')
            return c
        return mk

    def _build_setup(self, s):
        tk, ttk = self.tk, self.ttk
        nb = ttk.Notebook(s)
        nb.pack(fill='both', expand=True, padx=6, pady=4)
        self.setup_nb = nb
        tabs = {}
        for name in ('Audio', 'Routing', 'Capture', 'MIDI', 'Keyboard', 'Chains', 'Praat', 'Presets',
                     'Diagnostics'):
            f = tk.Frame(nb, bg=PANEL)
            nb.add(f, text=name)
            tabs[name] = f
        self._build_tab_audio(tabs['Audio'])
        self._build_tab_routing(tabs['Routing'])
        self._build_tab_capture(tabs['Capture'])
        self._build_tab_midi(tabs['MIDI'])
        self._build_tab_keys(tabs['Keyboard'])
        self._build_tab_chains(tabs['Chains'])
        self._build_tab_praat(tabs['Praat'])
        self._build_tab_presets(tabs['Presets'])
        self._build_tab_diag(tabs['Diagnostics'])

    # Audio tab
    def _build_tab_audio(self, t):
        tk = self.tk
        a = self.cfg['audio']
        self.v_hostapi = tk.StringVar(value=a.get('hostapi', ''))
        self.v_in_dev = tk.StringVar(value=a.get('in_device', ''))
        self.v_out_dev = tk.StringVar(value=a.get('out_device', ''))
        self.v_sr = tk.StringVar(value=str(a.get('sample_rate', 48000)))
        self.v_bs = tk.StringVar(value=str(a.get('blocksize', 512)))
        self.v_in_mode = tk.StringVar(value=a.get('input_mode', 'Mono'))
        self.v_in_a = tk.StringVar(value=str(a.get('input_ch', [1, 2])[0]))
        self.v_in_b = tk.StringVar(value=str((a.get('input_ch', [1, 2]) + [2])[1]))
        self.v_cap_en = tk.BooleanVar(value=a.get('capture_enabled', True))
        self.c_hostapi = self._row(t, "Host API", self._combo(self.v_hostapi, [], 30), 0,
                                   "ASIO is preferred on Windows (one full-duplex stream)")
        self.c_hostapi.bind('<<ComboboxSelected>>', lambda e: self._fill_device_lists())
        self.c_in = self._row(t, "Input device", self._combo(self.v_in_dev, [], 55), 1)
        self.c_out = self._row(t, "Output device", self._combo(self.v_out_dev, [], 55), 2)
        self._row(t, "Sample rate", self._combo(self.v_sr, ['44100', '48000', '88200', '96000'], 10), 3,
                  "capture and playback share this rate")
        self._row(t, "Block size", self._combo(self.v_bs, ['128', '256', '512', '1024', '2048'], 10), 4)
        self._row(t, "Capture enabled", lambda p: tk.Checkbutton(p, variable=self.v_cap_en, bg=PANEL,
                                                                 selectcolor=PANEL2, activebackground=PANEL), 5,
                  "off = playback only (output stream)")
        fr = self._row(t, "Input mode", lambda p: tk.Frame(p, bg=PANEL), 6, "one Global Input for all nine chains")
        for m in ('Mono', 'Stereo'):
            tk.Radiobutton(fr, text=m, variable=self.v_in_mode, value=m, bg=PANEL, fg=FG,
                           selectcolor=PANEL2, activebackground=PANEL).pack(side='left', padx=4)
        self._row(t, "Input channel (Mono / Left)", self._entry(self.v_in_a, 5), 7, "physical input, 1-based")
        self._row(t, "Input channel (Right)", self._entry(self.v_in_b, 5), 8,
                  "Stereo capture -> MONO processing (L+R, as the chains' own recorder) -> chain output; "
                  "the stereo original is kept for Export")
        bf = self._row(t, "", lambda p: tk.Frame(p, bg=PANEL), 9)
        tk.Button(bf, text="Apply & restart audio", bg=SEL, fg=FG, relief='flat', padx=10,
                  command=self.apply_audio).pack(side='left', padx=2)
        tk.Button(bf, text="Rescan devices", bg=BTN, fg=FG, relief='flat', padx=10,
                  command=self._scan_devices).pack(side='left', padx=6)
        self.audio_setup_msg = tk.Label(t, text="", bg=PANEL, fg=ACCENT, justify='left', anchor='w',
                                        wraplength=900)
        self.audio_setup_msg.grid(row=10, column=0, columnspan=3, sticky='w', padx=8, pady=8)
        tk.Label(t, text="Monitor the acoustic input with the interface's DIRECT MONITORING. "
                         "Live Lab never routes the input to the outputs.",
                 bg=PANEL, fg=DIM, anchor='w').grid(row=11, column=0, columnspan=3, sticky='w', padx=8)
        self._scan_devices()

    def _scan_devices(self):
        devs = []
        try:
            apis = sd.query_hostapis()
            for i, d in enumerate(sd.query_devices()):
                devs.append({'index': i, 'name': d['name'], 'api': apis[d['hostapi']]['name'],
                             'in': int(d['max_input_channels']), 'out': int(d['max_output_channels'])})
            api_names = [a['name'] for a in apis]
        except Exception as e:
            api_names = []
            self.audio_setup_msg.configure(text="Device scan failed: %s" % e)
        self._devices = devs
        self.c_hostapi['values'] = api_names
        if self.v_hostapi.get() not in api_names:
            pref = [n for n in api_names if 'ASIO' in n.upper()]
            self.v_hostapi.set(pref[0] if pref else (api_names[0] if api_names else ''))
        self._fill_device_lists()

    @staticmethod
    def _dev_label(d):
        return "%s  (%d in / %d out) [%s]" % (d['name'], d['in'], d['out'], d['api'])

    def _fill_device_lists(self):
        api = self.v_hostapi.get()
        ins = [self._dev_label(d) for d in self._devices if d['api'] == api and d['in'] > 0]
        outs = [self._dev_label(d) for d in self._devices if d['api'] == api and d['out'] > 0]
        self.c_in['values'] = ins
        self.c_out['values'] = outs
        if self.v_in_dev.get() not in ins:
            self.v_in_dev.set(ins[0] if ins else '')
        if self.v_out_dev.get() not in outs:
            self.v_out_dev.set(outs[0] if outs else '')

    def _dev_index(self, label, need):
        for d in self._devices:
            if self._dev_label(d) == label and d[need] > 0:
                return d['index']
        return None

    def apply_audio(self):
        a = copy.deepcopy(self.cfg['audio'])          # a PROPOSAL - cfg is untouched until it works
        a['hostapi'] = self.v_hostapi.get()
        a['in_device'] = self.v_in_dev.get()
        a['out_device'] = self.v_out_dev.get()
        try:
            a['sample_rate'] = int(self.v_sr.get())
            a['blocksize'] = int(self.v_bs.get())
            a['input_ch'] = [max(1, int(self.v_in_a.get())), max(1, int(self.v_in_b.get()))]
        except ValueError:
            self.audio_setup_msg.configure(text="Sample rate, block size and input channels must be numbers.")
            return
        a['input_mode'] = self.v_in_mode.get()
        a['capture_enabled'] = bool(self.v_cap_en.get())
        if a['input_mode'] == 'Stereo' and a['input_ch'][0] == a['input_ch'][1]:
            self.audio_setup_msg.configure(text="Stereo input needs two different physical channels.")
            return
        r = self._audio_transaction(audio=a)
        if r == 'busy':
            self.audio_setup_msg.configure(text="NOT applied: " + self._audio_busy() +
                                           "\nThe active settings are unchanged; press Apply again.")

    def _audio_busy(self):
        if self.recording:
            return "audio restart refused while recording."
        if self.finalizing:
            return ("audio restart postponed: take %s is still being saved."
                    % ", ".join("T%03d" % k for k in sorted(self.finalizing)))
        return None

    def _audio_transaction(self, audio=None, routing=None, capture=None):
        """Transactional stream restart. The proposal is opened first; the
        configuration changes ONLY if the new stream started. On failure
        the previous settings are reopened and the configuration is left
        as it was. Returns 'ok', 'failed' or 'busy' (nothing touched)."""
        if self._audio_busy():
            return 'busy'
        old = (self.cfg['audio'], self.cfg['routing'], self.cfg['capture'])
        new = (audio if audio is not None else old[0],
               routing if routing is not None else old[1],
               capture if capture is not None else old[2])
        r = self._open_audio(*new)
        if r:
            self.cfg['audio'], self.cfg['routing'], self.cfg['capture'] = (copy.deepcopy(x) for x in new)
            save_config(self.config_path, self.cfg)
            self._audio_feedback(True)
            return 'ok'
        err = self.audio_msg
        back = self._open_audio(*old)
        self.audio_msg = ("NOT applied - the new settings failed (%s). Previous settings %s."
                          % (err, "restored" if back else "could not be reopened either - check the device"))
        self._audio_feedback(bool(back))
        return 'failed'

    def _open_audio(self, a=None, rt=None, cap=None):
        """Open the stream with the given settings (default: the active
        configuration). Never modifies or saves the configuration.
        Returns True / False, or None when refused because a take is busy."""
        busy = self._audio_busy()
        if busy:
            self.status(busy[0].upper() + busy[1:])
            return None
        a = self.cfg['audio'] if a is None else a
        rt = self.cfg['routing'] if rt is None else rt
        self.engine.close()
        self.audio_expected = False
        out_idx = self._dev_index(a.get('out_device', ''), 'out')
        if out_idx is None:
            self.audio_msg = "no output device selected (Setup > Audio)"
            self._audio_feedback(False)
            return False
        in_idx = None
        sel = []
        if a.get('capture_enabled', True):
            in_idx = self._dev_index(a.get('in_device', ''), 'in')
            if in_idx is not None:
                chs = a['input_ch'][:1] if a.get('input_mode') == 'Mono' else a['input_ch'][:2]
                sel = [c - 1 for c in chs]
        rt_errs = validate_routing(rt)
        nphys = int(rt.get('phys_channels', 2))
        if rt_errs:
            self.audio_msg = "routing invalid: " + "; ".join(rt_errs)
            self._audio_feedback(False)
            return False
        cap = self.cfg['capture'] if cap is None else cap
        pre = cap['preroll_ms'] / 1000.0 if cap.get('preroll_on', True) else 0.0
        self.engine.trims = trims_vector(rt)
        ok = self.engine.open(a['sample_rate'], a['blocksize'], out_idx, nphys, in_idx, sel,
                              cap['max_s'], pre)
        if ok:
            self.audio_expected = True
            self.audio_msg = "%s · %d Hz · %d out%s" % (
                self.engine.api_name, self.engine.sr, nphys,
                (" · %s in %s" % (a['input_mode'], "+".join(str(c + 1) for c in sel))) if self.engine.capture_enabled
                else " · capture OFF")
            self.in_meter.set_n(max(1, len(sel)), [str(c + 1) for c in sel] or ['-'])
            self.out_meter.set_n(nphys)
        else:
            self.audio_msg = "audio error: " + self.engine.error
        self._audio_feedback(ok)
        return ok

    def _audio_feedback(self, ok):
        self.audio_lbl.configure(text="AUDIO: " + ("OK" if ok else "ERROR"), fg=OK if ok else ERR)
        self.audio_setup_msg.configure(text=self.audio_msg)
        mode = self.cfg['audio'].get('input_mode', 'Mono')
        self.in_mode_lbl.configure(text="%s  in %s" % (mode, "+".join(
            str(c) for c in (self.cfg['audio']['input_ch'][:1] if mode == 'Mono' else self.cfg['audio']['input_ch'][:2]))))
        self.status(self.audio_msg)

    # Routing tab
    def _build_tab_routing(self, t):
        tk = self.tk
        rt = self.cfg['routing']
        self.v_prof = tk.StringVar(value=rt['profile'])
        self.v_nphys = tk.StringVar(value=str(rt['phys_channels']))
        self.v_stout = tk.StringVar(value=" ".join(str(x) for x in rt['stereo_out']))
        self.v_spk = tk.StringVar(value=" ".join(str(x) for x in rt['speaker_map']))
        self.v_front = tk.StringVar(value=" ".join(str(x) for x in rt['front_pair']))
        self.v_monolaw = tk.StringVar(value=rt['mono_law'])
        self.v_monooct = tk.StringVar(value=rt['mono_octo'])
        self.v_monospk = tk.StringVar(value=str(rt['mono_speaker']))
        self.v_dmx = tk.StringVar(value=rt['downmix_8_to_2'])
        self.v_ring = tk.StringVar(value=str(rt.get('ring_start_deg', -22.5)))
        self.v_trims = tk.StringVar(value=" ".join("%g" % x for x in rt['trims_db']))
        self._row(t, "Output profile", self._combo(self.v_prof, list(PROFILES), 14), 0)
        self._row(t, "Physical output channels", self._entry(self.v_nphys, 5), 1, "stream channel count")
        self._row(t, "Stereo: L R physical channels", self._entry(self.v_stout, 10), 2, "e.g.  1 2")
        self._row(t, "Octo: speaker 1-8 -> physical", self._entry(self.v_spk, 24), 3, "saved speaker layout")
        self._row(t, "Front Stereo Pair (speakers)", self._entry(self.v_front, 10), 4,
                  "stereo results in Octophonic go here (default 1 2)")
        self._row(t, "Mono gain law (to a pair)", self._combo(self.v_monolaw, list(MONO_LAWS), 22), 5)
        self._row(t, "Mono in Octophonic", self._combo(self.v_monooct, list(MONO_OCTO_MODES), 28), 6)
        self._row(t, "Mono single speaker", self._entry(self.v_monospk, 5), 7)
        self._row(t, "8-ch to stereo downmix", self._combo(self.v_dmx, list(DOWNMIX_MODES), 44), 8,
                  "None = 8-ch results are refused on Stereo")
        self._row(t, "Ring: speaker 1 azimuth (deg)", self._entry(self.v_ring, 7), 9, "0 = front, + = clockwise")
        self._row(t, "Per-channel trim (dB)", self._entry(self.v_trims, 40), 10, "one value per physical channel")
        lim = self.cfg.get('limiter', {})
        self.v_lim_on = tk.BooleanVar(value=lim.get('on', True))
        self.v_lim_db = tk.StringVar(value=str(lim.get('ceiling_db', -0.3)))
        lf = self._row(t, "Output protection", lambda p: tk.Frame(p, bg=PANEL), 11,
                       "inactive below the ceiling; catches crossfade/layer overs")
        tk.Checkbutton(lf, text="safety limiter, ceiling (dBFS)", variable=self.v_lim_on, bg=PANEL, fg=FG,
                       selectcolor=PANEL2, activebackground=PANEL).pack(side='left')
        tk.Entry(lf, textvariable=self.v_lim_db, width=6, bg=PANEL2, fg=FG, relief='flat',
                 insertbackground=FG).pack(side='left', padx=4)
        bf = self._row(t, "", lambda p: tk.Frame(p, bg=PANEL), 12)
        tk.Button(bf, text="Validate & apply", bg=SEL, fg=FG, relief='flat', padx=10,
                  command=self.apply_routing).pack(side='left', padx=2)
        tk.Label(bf, text="   Speaker test, channel:", bg=PANEL, fg=DIM).pack(side='left')
        self.v_testch = tk.StringVar(value="1")
        tk.Entry(bf, textvariable=self.v_testch, width=4, bg=PANEL2, fg=FG, relief='flat',
                 insertbackground=FG).pack(side='left', padx=4)
        tk.Button(bf, text="Test (-30 dBFS)", bg=BTN, fg=FG, relief='flat',
                  command=self.speaker_test).pack(side='left', padx=2)
        tk.Button(bf, text="Test all in turn", bg=BTN, fg=FG, relief='flat',
                  command=self.speaker_test_all).pack(side='left', padx=2)
        self.route_msg = tk.Label(t, text="", bg=PANEL, fg=ACCENT, justify='left', anchor='w', wraplength=950,
                                  font=(MONO, 9))
        self.route_msg.grid(row=13, column=0, columnspan=3, sticky='w', padx=8, pady=8)
        self._show_route_summary()

    def _parse_routing_form(self):
        def ints(s):
            return [int(x) for x in s.replace(',', ' ').split()]
        rt = dict(self.cfg['routing'])
        rt['profile'] = self.v_prof.get()
        rt['phys_channels'] = int(self.v_nphys.get())
        rt['stereo_out'] = ints(self.v_stout.get())
        rt['speaker_map'] = ints(self.v_spk.get())
        rt['front_pair'] = ints(self.v_front.get())
        rt['mono_law'] = self.v_monolaw.get()
        rt['mono_octo'] = self.v_monooct.get()
        rt['mono_speaker'] = int(self.v_monospk.get())
        rt['downmix_8_to_2'] = self.v_dmx.get()
        rt['ring_start_deg'] = float(self.v_ring.get())
        tr = [float(x) for x in self.v_trims.get().replace(',', ' ').split()]
        rt['trims_db'] = (tr + [0.0] * rt['phys_channels'])[:max(rt['phys_channels'], len(tr))]
        return rt

    def _show_route_summary(self, rt=None, prefix=''):
        rt = rt or self.cfg['routing']
        lines = [prefix] if prefix else []
        for n in (1, 2, 8):
            try:
                M, desc = build_routing_matrix(n, rt)
                nz = ["in%d->out%d %.3f" % (i + 1, j + 1, M[i, j]) for i in range(n)
                      for j in range(M.shape[1]) if abs(M[i, j]) > 0]
                lines.append("%d-ch result: %s   [%s]" % (n, desc, ", ".join(nz)))
            except RoutingError as e:
                lines.append("%d-ch result: REFUSED - %s" % (n, e))
        self.route_msg.configure(text="\n".join(lines))

    def apply_routing(self):
        try:
            rt = self._parse_routing_form()
        except ValueError as e:
            self.route_msg.configure(text="Not a number: %s" % e)
            return
        errs = validate_routing(rt)
        if errs:
            self.route_msg.configure(text="Routing NOT applied:\n  - " + "\n  - ".join(errs))
            return
        try:
            lim = {'on': bool(self.v_lim_on.get()), 'ceiling_db': float(self.v_lim_db.get())}
        except ValueError:
            self.route_msg.configure(text="Limiter ceiling must be a number (dBFS, -12..0).")
            return
        restart = int(rt['phys_channels']) != int(self.cfg['routing']['phys_channels'])
        if restart:
            r = self._audio_transaction(routing=rt)
            if r != 'ok':
                why = self._audio_busy() if r == 'busy' else self.audio_msg
                self.route_msg.configure(text="Routing NOT applied (the channel count needs an audio restart): %s\n"
                                              "The active routing is unchanged." % why)
                return
        else:
            # Voices carry their own matrices; stop them so nothing keeps
            # playing through an outdated layout.
            if self.engine.playing_rids():
                self.engine.stop_all(0.05)
            self.cfg['routing'] = rt
            self.engine.trims = trims_vector(rt)
        self.cfg['limiter'] = lim
        self._apply_limiter_cfg()
        self.v_lim_db.set(str(self.cfg['limiter']['ceiling_db']))
        save_config(self.config_path, self.cfg)
        self._show_route_summary(rt, "Applied." + (" Audio restarted (channel count changed)." if restart else ""))

    def speaker_test(self, ch=None):
        try:
            c = int(self.v_testch.get()) if ch is None else ch
        except ValueError:
            return
        if not self.engine.is_alive() or not 1 <= c <= self.engine.n_out:
            self.status("Speaker test: channel %s not available on the open stream" % c)
            return
        self.engine.test_tone(c - 1, 1.0, -30.0, 1000.0)
        self.status("Speaker test: physical output %d, 1 kHz, -30 dBFS (trim applied)" % c, log=False)

    def speaker_test_all(self):
        n = self.engine.n_out if self.engine.is_alive() else 0
        seq = list(range(1, n + 1))

        def step():
            if not seq or self.closing:
                return
            self.speaker_test(seq.pop(0))
            self.root.after(1300, step)
        step()

    # Capture tab
    def _build_tab_capture(self, t):
        tk = self.tk
        c = self.cfg['capture']
        self.v_min = tk.StringVar(value=str(c['min_s']))
        self.v_max = tk.StringVar(value=str(c['max_s']))
        self.v_pre_on = tk.BooleanVar(value=c['preroll_on'])
        self.v_pre = tk.StringVar(value=str(c['preroll_ms']))
        self.v_stopfade = tk.StringVar(value=str(self.cfg['stop_fade_s']))
        self.v_cap = tk.StringVar(value=str(self.cfg['bank']['capacity']))
        self.v_mem = tk.StringVar(value=str(self.cfg['bank']['memory_mb']))
        self.v_export = tk.StringVar(value=self.cfg['export_dir'])
        self._row(t, "Minimum capture (s)", self._entry(self.v_min, 6), 0, "shorter takes are discarded")
        self._row(t, "Maximum capture (s)", self._entry(self.v_max, 6), 1, "recording stops and submits itself")
        self._row(t, "Pre-roll", lambda p: tk.Checkbutton(p, variable=self.v_pre_on, bg=PANEL,
                                                          selectcolor=PANEL2, activebackground=PANEL), 2)
        self._row(t, "Pre-roll length (ms)", self._entry(self.v_pre, 6), 3, "audio before the pedal press")
        self._row(t, "Stop All fade (s)", self._entry(self.v_stopfade, 6), 4)
        self._row(t, "Result Bank capacity", self._entry(self.v_cap, 6), 5, "minimum 16")
        self._row(t, "Result Bank memory limit (MB)", self._entry(self.v_mem, 6), 6)
        self._row(t, "Export folder", self._entry(self.v_export, 60), 7, "explicit exports only")
        bf = self._row(t, "", lambda p: tk.Frame(p, bg=PANEL), 8)
        tk.Button(bf, text="Apply", bg=SEL, fg=FG, relief='flat', padx=10,
                  command=self.apply_capture).pack(side='left')
        self.cap_msg = tk.Label(t, text="Capture length and pre-roll changes restart the audio stream.",
                                bg=PANEL, fg=DIM, anchor='w')
        self.cap_msg.grid(row=9, column=0, columnspan=3, sticky='w', padx=8, pady=8)

    def apply_capture(self):
        try:
            mn = max(0.05, float(self.v_min.get()))
            mx = max(mn + 0.5, min(600.0, float(self.v_max.get())))
            pre = max(0, min(2000, int(float(self.v_pre.get()))))
            sf_ = max(0.005, min(10.0, float(self.v_stopfade.get())))
            cap = max(16, int(self.v_cap.get()))
            mem = max(200, int(self.v_mem.get()))
        except ValueError:
            self.cap_msg.configure(text="All fields must be numbers.", fg=ERR)
            return
        c = self.cfg['capture']
        restart = (mx != c['max_s'] or pre != c['preroll_ms'] or bool(self.v_pre_on.get()) != c['preroll_on'])
        newc = dict(c)
        newc.update({'min_s': mn, 'max_s': mx, 'preroll_ms': pre, 'preroll_on': bool(self.v_pre_on.get())})
        if restart:
            # All-or-nothing: nothing below is applied unless the stream
            # restarted with the new capture length / pre-roll.
            r = self._audio_transaction(capture=newc)
            if r != 'ok':
                why = self._audio_busy() if r == 'busy' else self.audio_msg
                self.cap_msg.configure(text="NOT applied: %s  The active settings are unchanged." % why, fg=ERR)
                return
        else:
            self.cfg['capture'] = newc
        self.capture_settings['min_capture_s'] = mn
        self.cfg['stop_fade_s'] = sf_
        self.cfg['bank'] = {'capacity': cap, 'memory_mb': mem}
        self.bank.capacity = cap
        self.bank.memory_bytes_cap = mem * 1024 * 1024
        self.cfg['export_dir'] = self.v_export.get().strip() or _default_export_dir()
        self.cap_msg.configure(text="Applied.", fg=OK)
        save_config(self.config_path, self.cfg)

    # MIDI tab
    def _build_tab_midi(self, t):
        tk, ttk = self.tk, self.ttk
        m = self.cfg['midi']
        top = tk.Frame(t, bg=PANEL)
        top.pack(fill='x', padx=8, pady=6)
        tk.Label(top, text="MIDI input port", bg=PANEL, fg=DIM).pack(side='left')
        self.v_mport = tk.StringVar(value=m.get('port', ''))
        self.c_mport = ttk.Combobox(top, textvariable=self.v_mport, width=40, state='readonly')
        self.c_mport.pack(side='left', padx=6)
        self.c_mport.bind('<<ComboboxSelected>>', lambda e: self._on_midi_port_selected())
        tk.Button(top, text="⟳", bg=BTN, fg=FG, relief='flat', command=self._fill_midi_ports).pack(side='left')
        tk.Label(top, text="   Channel", bg=PANEL, fg=DIM).pack(side='left')
        self.v_mch = tk.StringVar(value=str(m.get('channel', 'Omni')))
        cb = ttk.Combobox(top, textvariable=self.v_mch, width=6, state='readonly',
                          values=['Omni'] + [str(i) for i in range(1, 17)])
        cb.pack(side='left', padx=6)
        cb.bind('<<ComboboxSelected>>', lambda e: self._midi_opts_changed())
        if not self.midi.available:
            tk.Label(top, text="   python-rtmidi missing:  python -m pip install python-rtmidi",
                     bg=PANEL, fg=ERR).pack(side='left')

        ped = tk.Frame(t, bg=PANEL)
        ped.pack(fill='x', padx=8, pady=4)
        tk.Label(ped, text="Pedal polarity", bg=PANEL, fg=DIM).pack(side='left')
        self.v_pol = tk.StringVar(value=m.get('polarity', 'normal'))
        for v in ('normal', 'inverted'):
            tk.Radiobutton(ped, text=v, variable=self.v_pol, value=v, bg=PANEL, fg=FG, selectcolor=PANEL2,
                           activebackground=PANEL, command=self._midi_opts_changed).pack(side='left', padx=3)
        tk.Label(ped, text="   CC press ≥", bg=PANEL, fg=DIM).pack(side='left')
        self.v_ccon = tk.StringVar(value=str(m.get('cc_on', 64)))
        tk.Entry(ped, textvariable=self.v_ccon, width=4, bg=PANEL2, fg=FG, relief='flat',
                 insertbackground=FG).pack(side='left', padx=3)
        tk.Label(ped, text="release ≤", bg=PANEL, fg=DIM).pack(side='left')
        self.v_ccoff = tk.StringVar(value=str(m.get('cc_off', 40)))
        tk.Entry(ped, textvariable=self.v_ccoff, width=4, bg=PANEL2, fg=FG, relief='flat',
                 insertbackground=FG).pack(side='left', padx=3)
        tk.Button(ped, text="Apply thresholds", bg=BTN, fg=FG, relief='flat',
                  command=self._midi_opts_changed).pack(side='left', padx=6)
        self.pedal_state_lbl = tk.Label(ped, text="pedal: up", bg=PANEL2, fg=FG, width=16)
        self.pedal_state_lbl.pack(side='left', padx=12)
        self.midi_event_lbl = tk.Label(ped, text="last event: -", bg=PANEL, fg=ACCENT, font=(MONO, 9))
        self.midi_event_lbl.pack(side='left', padx=6)

        tbl = tk.Frame(t, bg=PANEL)
        tbl.pack(fill='both', expand=True, padx=8, pady=6)
        self.map_lbls = {}
        for i, (act, lab) in enumerate(ACTIONS):
            r, c = i % 11, (i // 11) * 4
            tk.Label(tbl, text=lab, bg=PANEL, fg=FG, anchor='w', width=22).grid(row=r, column=c, sticky='w', pady=2)
            l = tk.Label(tbl, text=mapping_text(self.cfg['midi']['mappings'].get(act)), bg=PANEL2, fg=ACCENT,
                         width=22, anchor='w', font=(MONO, 9))
            l.grid(row=r, column=c + 1, padx=4)
            self.map_lbls[act] = l
            tk.Button(tbl, text="Learn" if act != 'hold_record' else "Learn (press & HOLD)", bg=BTN, fg=FG,
                      relief='flat', command=lambda a=act: self.midi_learn(a)).grid(row=r, column=c + 2, padx=2)
            tk.Button(tbl, text="✕", bg=BTN, fg=FG, relief='flat', width=2,
                      command=lambda a=act: self.midi_clear(a)).grid(row=r, column=c + 3, padx=(2, 18))
        self._fill_midi_ports()

    # Keyboard tab
    def _build_tab_keys(self, t):
        tk = self.tk
        tk.Label(t, text="Tk key names: letters/digits as typed, space, Escape, bracketleft, bracketright, F1-F12. "
                         "Keys do nothing while typing in a text field.",
                 bg=PANEL, fg=DIM, anchor='w').pack(fill='x', padx=8, pady=6)
        g = tk.Frame(t, bg=PANEL)
        g.pack(fill='x', padx=8)
        self.key_vars = {}
        for i, (act, lab) in enumerate(ACTIONS):
            r, c = i % 11, (i // 11) * 2
            tk.Label(g, text=lab, bg=PANEL, fg=FG, anchor='w', width=24).grid(row=r, column=c, sticky='w', pady=2)
            v = tk.StringVar(value=self.cfg['keys'].get(act, ''))
            tk.Entry(g, textvariable=v, width=14, bg=PANEL2, fg=FG, relief='flat',
                     insertbackground=FG).grid(row=r, column=c + 1, padx=(4, 30))
            self.key_vars[act] = v
        bf = tk.Frame(t, bg=PANEL)
        bf.pack(fill='x', padx=8, pady=8)
        tk.Button(bf, text="Apply keys", bg=SEL, fg=FG, relief='flat', padx=10,
                  command=self.apply_keys).pack(side='left')
        tk.Button(bf, text="Restore defaults", bg=BTN, fg=FG, relief='flat', padx=10,
                  command=self.restore_keys).pack(side='left', padx=6)
        self.keys_msg = tk.Label(bf, text="", bg=PANEL, fg=ACCENT)
        self.keys_msg.pack(side='left', padx=8)

    def apply_keys(self):
        new = {a: v.get().strip() for a, v in self.key_vars.items()}
        used = {}
        for a, k in new.items():
            if not k:
                continue
            kk = k.lower() if len(k) == 1 else k
            if kk in used:
                self.keys_msg.configure(text="'%s' is assigned twice (%s / %s)" % (k, ACTION_LABEL[used[kk]],
                                                                                ACTION_LABEL[a]), fg=ERR)
                return
            used[kk] = a
        self.cfg['keys'] = new
        save_config(self.config_path, self.cfg)
        self.keys_msg.configure(text="Applied.", fg=OK)
        self._refresh_chain_buttons()

    def restore_keys(self):
        for a, v in self.key_vars.items():
            v.set(DEFAULT_KEYS.get(a, ''))
        self.apply_keys()

    # Chains tab
    def _build_tab_chains(self, t):
        tk, ttk = self.tk, self.ttk
        tk.Label(t, text="Policy and crossfade are frozen into each job when its recording starts. "
                         "New configurations start with every chain on MANUAL.",
                 bg=PANEL, fg=DIM, anchor='w').grid(row=0, column=0, columnspan=5, sticky='w', padx=8, pady=6)
        self.chain_pol = {}
        self.chain_xf = {}
        self.chain_status = {}
        for i, c in enumerate(CHAINS):
            cc = self.cfg['chains'][c['key']]
            tk.Label(t, text="%d  %s" % (i + 1, c['label']), bg=PANEL, fg=FG, width=18, anchor='w',
                     font=(FONT, 10, 'bold')).grid(row=i + 1, column=0, sticky='w', padx=8, pady=3)
            pv = tk.StringVar(value=cc['policy'].upper())
            cb = ttk.Combobox(t, textvariable=pv, values=['MANUAL', 'AUTO'], width=9, state='readonly')
            cb.grid(row=i + 1, column=1, padx=4)
            cb.bind('<<ComboboxSelected>>', lambda e, k=c['key']: self._chain_changed(k))
            xv = tk.StringVar(value="%g" % cc['xfade'])
            tk.Label(t, text="crossfade (s)", bg=PANEL, fg=DIM).grid(row=i + 1, column=2, padx=4)
            en = tk.Entry(t, textvariable=xv, width=6, bg=PANEL2, fg=FG, relief='flat', insertbackground=FG)
            en.grid(row=i + 1, column=3, padx=4)
            en.bind('<Return>', lambda e, k=c['key']: self._chain_changed(k))
            en.bind('<FocusOut>', lambda e, k=c['key']: self._chain_changed(k))
            sl = tk.Label(t, text="", bg=PANEL, fg=DIM, anchor='w', font=(FONT, 9))
            sl.grid(row=i + 1, column=4, sticky='w', padx=8)
            self.chain_pol[c['key']] = pv
            self.chain_xf[c['key']] = xv
            self.chain_status[c['key']] = sl
        tk.Button(t, text="Re-check chain files", bg=BTN, fg=FG, relief='flat',
                  command=self._check_chains).grid(row=11, column=0, padx=8, pady=10, sticky='w')

    def _chain_changed(self, key):
        cc = self.cfg['chains'][key]
        cc['policy'] = 'auto' if self.chain_pol[key].get() == 'AUTO' else 'manual'
        try:
            cc['xfade'] = max(0.0, min(30.0, float(self.chain_xf[key].get())))
        except ValueError:
            self.chain_xf[key].set("%g" % cc['xfade'])
        save_config(self.config_path, self.cfg)
        self._refresh_chain_buttons()

    def _check_chains(self):
        """Derive every adapter now (in memory only) so a structural problem
        shows up before the performance, not on the first take."""
        self.chain_ok = {}
        for c in CHAINS:
            p = os.path.join(self.chain_dir, c['file'])
            lbl = self.chain_status.get(c['key'])
            try:
                with open(p, 'r', encoding='utf-8') as f:
                    src = f.read()
                _txt, rep = derive_adapter(src, self.chain_dir, self.plugin_dir, c['file'])
                calls = audit_chain_calls(src, self.plugin_dir) + audit_nodraw(src, self.plugin_dir)
                if calls:
                    raise AdapterError("; ".join(calls))
                self.chain_ok[c['key']] = True
                inp = [x for x in rep if x.startswith('input:')]
                msg = "adapter OK  ·  " + (inp[0][7:].split(' (')[0] if inp else '') + \
                    ("  ·  seed passed" if 'random seed field: yes' in rep else '')
                col = OK
            except FileNotFoundError:
                self.chain_ok[c['key']] = False
                msg, col = "file not found: " + p, ERR
            except AdapterError as e:
                self.chain_ok[c['key']] = False
                msg, col = "INCOMPATIBLE: %s" % e, ERR
            if lbl is not None:
                lbl.configure(text=msg, fg=col)
            if not self.chain_ok[c['key']]:
                self._log("Chain %s: %s" % (c['label'], msg))
        self._refresh_chain_buttons()

    # Praat tab
    def _build_tab_praat(self, t):
        tk = self.tk
        self.v_praat = tk.StringVar(value=self.cfg['praat'].get('path', ''))
        self.v_timeout = tk.StringVar(value=str(self.cfg['praat'].get('timeout_s', 300)))
        self._row(t, "Praat executable", self._entry(self.v_praat, 70), 0, "blank = auto-detect")
        self._row(t, "Worker timeout (s)", self._entry(self.v_timeout, 6), 1, "job is killed after this")
        bf = self._row(t, "", lambda p: tk.Frame(p, bg=PANEL), 2)
        tk.Button(bf, text="Apply / detect", bg=SEL, fg=FG, relief='flat', padx=10,
                  command=self.apply_praat).pack(side='left')
        tk.Button(bf, text="Browse…", bg=BTN, fg=FG, relief='flat', padx=10,
                  command=self.browse_praat).pack(side='left', padx=6)
        tk.Button(bf, text="Run worker self-test", bg=BTN, fg=FG, relief='flat', padx=10,
                  command=self.worker_selftest).pack(side='left', padx=6)
        self.praat_msg = tk.Label(t, text="detecting…", bg=PANEL, fg=ACCENT, justify='left', anchor='w',
                                  wraplength=950, font=(MONO, 9))
        self.praat_msg.grid(row=3, column=0, columnspan=3, sticky='w', padx=8, pady=8)
        tk.Label(t, text="Each job runs in its own headless Praat process (never your open Praat session), "
                         "at lowered CPU priority, inside a kill-on-exit process group.",
                 bg=PANEL, fg=DIM, anchor='w').grid(row=4, column=0, columnspan=3, sticky='w', padx=8)

    def browse_praat(self):
        from tkinter import filedialog
        p = filedialog.askopenfilename(title="Praat executable", parent=self.root)
        self._reclaim_focus()
        if p:
            self.v_praat.set(p)
            self.apply_praat()

    def apply_praat(self):
        self.cfg['praat']['path'] = self.v_praat.get().strip()
        try:
            self.cfg['praat']['timeout_s'] = max(10, int(float(self.v_timeout.get())))
        except ValueError:
            pass
        self.proc_mgr.timeout_s = self.cfg['praat']['timeout_s']
        save_config(self.config_path, self.cfg)
        self.praat_msg.configure(text="detecting…")
        threading.Thread(target=self._detect_praat_bg, daemon=True).start()

    def _detect_praat_bg(self):
        info = find_praat(getattr(self.args, 'praat_hint', '') or '', self.cfg['praat'].get('path', ''))
        self.events.put(('praat_info', info))

    def worker_selftest(self):
        """1 s tone -> passthrough adapter through the real worker path."""
        if not self.praat.get('path'):
            self.praat_msg.configure(text="No Praat executable - cannot self-test.")
            return
        sr = self.engine.sr if self.engine.is_alive() else int(self.cfg['audio']['sample_rate'])
        seq = self.next_take
        self.next_take += 1
        path = self.ws.sub('captures', 'take_%04d.wav' % seq)
        t = np.arange(int(sr)) / float(sr)
        tone = (0.5 * np.sin(2 * np.pi * 440 * t) * np.minimum(1, np.minimum(t, 1 - t) / 0.01)).astype(np.float32)
        sf.write(path, tone, int(sr), subtype='PCM_24')
        take = Take(seq, path, 1.0, 1, sr, 'selftest', 'self-test')
        dn = self.clock.decide('self-test')
        r = Result(take, 'selftest', 'manual', 0.0, dn, 0, 1)
        self.bank.add(r, self.engine.playing_rids())
        self.proc_mgr.submit(Job(r, sr))
        self.praat_msg.configure(text=self.praat_msg.cget('text') + "\nSelf-test submitted as %s - watch the bank." % r.rid)
        self._refresh_bank()

    # Presets tab
    def _build_tab_presets(self, t):
        tk = self.tk
        tk.Label(t, text="A preset stores routing, chain policies/crossfades, master gain, capture settings, "
                         "keyboard and MIDI mappings (not the audio devices).",
                 bg=PANEL, fg=DIM, anchor='w').pack(fill='x', padx=8, pady=6)
        f = tk.Frame(t, bg=PANEL)
        f.pack(fill='x', padx=8)
        self.v_preset = tk.StringVar()
        tk.Entry(f, textvariable=self.v_preset, width=30, bg=PANEL2, fg=FG, relief='flat',
                 insertbackground=FG).pack(side='left')
        for txt, cmd in (("Save", self.preset_save), ("Load", self.preset_load), ("Delete", self.preset_delete)):
            tk.Button(f, text=txt, bg=BTN, fg=FG, relief='flat', padx=10, command=cmd).pack(side='left', padx=4)
        self.preset_list = tk.Listbox(t, bg=PANEL2, fg=FG, height=12, relief='flat', selectbackground=SEL)
        self.preset_list.pack(fill='x', padx=8, pady=8)
        self.preset_list.bind('<<ListboxSelect>>', lambda e: self._preset_pick())
        self.preset_msg = tk.Label(t, text="", bg=PANEL, fg=ACCENT, anchor='w')
        self.preset_msg.pack(fill='x', padx=8)
        self._fill_presets()

    def _fill_presets(self):
        self.preset_list.delete(0, 'end')
        for n in sorted(self.cfg['presets']):
            self.preset_list.insert('end', n)

    def _preset_pick(self):
        s = self.preset_list.curselection()
        if s:
            self.v_preset.set(self.preset_list.get(s[0]))

    def preset_save(self):
        n = self.v_preset.get().strip()
        if not n:
            self.preset_msg.configure(text="Type a preset name first.")
            return
        self.cfg['presets'][n] = make_preset(self.cfg)
        save_config(self.config_path, self.cfg)
        self._fill_presets()
        self.preset_msg.configure(text="Saved preset '%s'." % n)

    def preset_load(self):
        n = self.v_preset.get().strip()
        p = self.cfg['presets'].get(n)
        if not p:
            self.preset_msg.configure(text="No preset named '%s'." % n)
            return
        if self.recording:
            self.preset_msg.configure(text="Not while recording.")
            return
        apply_preset(self.cfg, p)
        save_config(self.config_path, self.cfg)
        self._reload_setup_vars()
        self.preset_msg.configure(text="Loaded '%s'. Routing/capture re-applied." % n)

    def preset_delete(self):
        n = self.v_preset.get().strip()
        if self.cfg['presets'].pop(n, None) is not None:
            save_config(self.config_path, self.cfg)
            self._fill_presets()
            self.preset_msg.configure(text="Deleted '%s'." % n)

    def _reload_setup_vars(self):
        rt = self.cfg['routing']
        self.v_prof.set(rt['profile'])
        self.v_nphys.set(str(rt['phys_channels']))
        self.v_stout.set(" ".join(str(x) for x in rt['stereo_out']))
        self.v_spk.set(" ".join(str(x) for x in rt['speaker_map']))
        self.v_front.set(" ".join(str(x) for x in rt['front_pair']))
        self.v_monolaw.set(rt['mono_law'])
        self.v_monooct.set(rt['mono_octo'])
        self.v_monospk.set(str(rt['mono_speaker']))
        self.v_dmx.set(rt['downmix_8_to_2'])
        self.v_ring.set(str(rt.get('ring_start_deg', -22.5)))
        self.v_trims.set(" ".join("%g" % x for x in rt['trims_db']))
        c = self.cfg['capture']
        self.v_min.set(str(c['min_s']))
        self.v_max.set(str(c['max_s']))
        self.v_pre_on.set(c['preroll_on'])
        self.v_pre.set(str(c['preroll_ms']))
        self.v_stopfade.set(str(self.cfg['stop_fade_s']))
        for k in self.chain_pol:
            self.chain_pol[k].set(self.cfg['chains'][k]['policy'].upper())
            self.chain_xf[k].set("%g" % self.cfg['chains'][k]['xfade'])
        for a, v in self.key_vars.items():
            v.set(self.cfg['keys'].get(a, ''))
        m = self.cfg['midi']
        self.v_pol.set(m.get('polarity', 'normal'))
        self.v_ccon.set(str(m.get('cc_on', 64)))
        self.v_ccoff.set(str(m.get('cc_off', 40)))
        self.v_mch.set(str(m.get('channel', 'Omni')))
        self._apply_midi_cfg()
        for act, l in self.map_lbls.items():
            l.configure(text=mapping_text(m['mappings'].get(act)))
        self.master_var.set(self.cfg.get('master_gain_db', 0.0))
        self._apply_master()
        self.capture_settings['min_capture_s'] = c['min_s']
        self._show_route_summary()
        self._open_audio()
        self._refresh_chain_buttons()

    # Diagnostics tab
    def _build_tab_diag(self, t):
        tk = self.tk
        tk.Label(t, text="Session workspace (deleted on close):", bg=PANEL, fg=DIM, anchor='w').pack(fill='x', padx=8, pady=(6, 0))
        tk.Label(t, text=self.ws.path, bg=PANEL, fg=FG, anchor='w', font=(MONO, 9)).pack(fill='x', padx=8)
        tk.Label(t, text="Config (persistent): " + self.config_path, bg=PANEL, fg=DIM, anchor='w',
                 font=(MONO, 9)).pack(fill='x', padx=8)
        bf = tk.Frame(t, bg=PANEL)
        bf.pack(fill='x', padx=8, pady=6)
        tk.Button(bf, text="Inspect workspace", bg=BTN, fg=FG, relief='flat', padx=10,
                  command=self.inspect_workspace).pack(side='left')
        tk.Button(bf, text="Cancel all processing", bg=BTN, fg=FG, relief='flat', padx=10,
                  command=self.cancel_processing).pack(side='left', padx=6)
        self.diag_msg = tk.Label(t, text="", bg=PANEL, fg=ACCENT, justify='left', anchor='w', font=(MONO, 9))
        self.diag_msg.pack(fill='x', padx=8)
        self.log_text = tk.Text(t, height=18, bg=PANEL2, fg=FG, relief='flat', font=(MONO, 9),
                                state='disabled', wrap='none')
        self.log_text.pack(fill='both', expand=True, padx=8, pady=6)
        self.log_text.configure(state='normal')
        for ln in self.log:
            self.log_text.insert('end', ln + "\n")
        self.log_text.configure(state='disabled')

    def inspect_workspace(self):
        n, b, names = self.ws.file_report()
        cur = self.proc_mgr.current
        pid = self.proc_mgr.proc.pid if (self.proc_mgr.proc and self.proc_mgr.proc.poll() is None) else None
        lines = ["files: %d  (%.1f MB)" % (n, b / 1048576.0)]
        lines += ["  " + x for x in names[:20]]
        if len(names) > 20:
            lines.append("  … %d more" % (len(names) - 20))
        lines.append("worker: %s" % ("PID %d processing %s" % (pid, cur.result.rid) if pid and cur else "none"))
        lines.append("queued: %s" % (", ".join(self.proc_mgr.queued()) or "none"))
        lines.append("bank: %d results, %.1f MB audio in memory" % (len(self.bank), self.bank.memory_used() / 1048576.0))
        self.diag_msg.configure(text="\n".join(lines))

    def cancel_processing(self):
        self.proc_mgr.cancel_all()
        self.status("All processing cancelled.")

    # ── view switching ───────────────────────────────────────────────
    def show_view(self, name):
        self.perf.pack_forget()
        self.setup.pack_forget()
        (self.perf if name == 'PERFORMANCE' else self.setup).pack(fill='both', expand=True)
        for n, b in self.view_btns.items():
            b.configure(bg=SEL if n == name else BTN)
        self._reclaim_focus()

    # ── focus handling (from the Performance Launcher) ───────────────
    def _reclaim_focus(self, *_):
        try:
            self.root.focus_set()
        except Exception:
            pass

    def _bring_front(self):
        try:
            self.root.lift()
            self.root.attributes('-topmost', True)
            self.root.after(300, lambda: self.root.attributes('-topmost', False))
            self.root.focus_force()
        except Exception:
            pass

    def _on_click_release(self, event):
        try:
            cls = event.widget.winfo_class()
        except Exception:
            return
        if cls not in TEXT_CLASSES and cls != 'Treeview':
            self.root.after_idle(self._reclaim_focus)

    def _on_focus_out(self, event):
        # Window lost focus while F was held: no KeyRelease will come, so
        # release the keyboard "pedal" instead of recording forever.
        if event.widget is self.root and self._key_hold_down:
            self.root.after(60, self._check_focus_lost)

    def _check_focus_lost(self):
        try:
            if self.root.focus_get() is None and self._key_hold_down:
                self._key_hold_down = False
                self.pedal(False, 'keyboard (focus lost)')
        except Exception:
            pass

    # ── keyboard ─────────────────────────────────────────────────────
    def _key_action(self, event):
        ks = event.keysym
        for act, k in self.cfg['keys'].items():
            if not k:
                continue
            if k == ks or (len(k) == 1 and len(ks) == 1 and k.lower() == ks.lower()):
                return act
        return None

    def _typing(self, event):
        try:
            return event.widget.winfo_class() in TEXT_CLASSES
        except Exception:
            return False

    def _on_key_press(self, event):
        if self._typing(event):
            if event.keysym == 'Escape':
                self._reclaim_focus()
            return
        act = self._key_action(event)
        if act is None:
            return
        if act == 'hold_record':
            if self._key_hold_pending is not None:
                # X11 auto-repeat sends Release+Press pairs: swallow them.
                self.root.after_cancel(self._key_hold_pending)
                self._key_hold_pending = None
                return
            if not self._key_hold_down:
                self._key_hold_down = True
                self.pedal(True, 'keyboard')
            return
        if getattr(event, 'state', 0) & 0x4:
            return                      # ignore Ctrl+key
        self.do_action(act, 'keyboard')
        return 'break'

    def _on_key_release(self, event):
        if self._typing(event):
            return
        if self._key_action(event) == 'hold_record' and self._key_hold_down:
            if self._key_hold_pending is not None:
                self.root.after_cancel(self._key_hold_pending)
            self._key_hold_pending = self.root.after(40, self._key_hold_release)

    def _key_hold_release(self):
        self._key_hold_pending = None
        if self._key_hold_down:
            self._key_hold_down = False
            self.pedal(False, 'keyboard')

    # ── actions ──────────────────────────────────────────────────────
    def do_action(self, act, source=''):
        if act.startswith('chain_'):
            self.select_chain(int(act.split('_')[1]) - 1)
        elif act == 'play':
            self.play_selected()
        elif act == 'prev':
            self.step_bank(-1)
        elif act == 'next':
            self.step_bank(1)
        elif act == 'latest':
            self.latest_ready()
        elif act == 'regenerate':
            self.regenerate_selected()
        elif act == 'crossfade':
            self.crossfade_selected()
        elif act == 'auto_suspend':
            self.toggle_auto_suspend()
        elif act == 'arm':
            self.toggle_arm()
        elif act == 'pin':
            self.pin_selected()
        elif act == 'stop_all':
            self.stop_all()

    def select_chain(self, i):
        if 0 <= i < len(CHAINS):
            self.sel_chain = i
            self._refresh_chain_buttons()
            ok = self.chain_ok.get(CHAINS[i]['key'], True)
            self.status("Chain: %s%s" % (CHAINS[i]['label'], "" if ok else "  (INCOMPATIBLE - see Setup > Chains)"),
                        log=False)

    def toggle_arm(self):
        self.armed = not self.armed
        if not self.armed and self.recording:
            self.pedal(False, 'disarm')
        self.arm_btn.configure(text="ARMED" if self.armed else "DISARMED", bg=REC if self.armed else BTN)
        self.status("Capture %s." % ("ARMED" if self.armed else "DISARMED"))

    def toggle_auto_suspend(self):
        self.auto_suspend = not self.auto_suspend
        self.cfg['auto_suspend'] = self.auto_suspend
        self._refresh_auto_btn()
        self.status("Auto Suspend %s." % ("ON - finished results wait as READY" if self.auto_suspend else "off"))

    def _refresh_auto_btn(self):
        self.auto_btn.configure(text="AUTO SUSPEND: ON" if self.auto_suspend else "Auto Suspend: off",
                                bg=WARN if self.auto_suspend else BTN, fg="#000" if self.auto_suspend else FG)

    # Capture
    def pedal(self, down, source):
        if down:
            self.start_capture(source)
        else:
            self.stop_capture(source)

    def start_capture(self, source):
        if self.closing:
            return
        if not self.armed:
            self.rec_state.configure(text="DISARMED - press ARM to record", fg=WARN)
            return
        if not self.engine.is_alive() or not self.engine.capture_enabled:
            self.rec_state.configure(text="Capture unavailable: %s" % self.audio_msg, fg=ERR)
            return
        if self.recording:
            return
        ch = CHAINS[self.sel_chain]
        if not self.chain_ok.get(ch['key'], True):
            self.rec_state.configure(text="%s is incompatible - pick another chain" % ch['label'], fg=ERR)
            return
        if not self.bank.can_accept_new(self.engine.playing_rids()):
            self.rec_state.configure(text="BANK FULL: every result is pinned, playing or processing - "
                                          "unpin something", fg=ERR)
            return
        seq = self.next_take
        self.next_take += 1
        dn = self.clock.decide('capture T%03d' % seq)
        cc = self.cfg['chains'][ch['key']]
        self.pending[seq] = {'chain': ch['key'], 'policy': cc['policy'], 'xfade': cc['xfade'],
                             'decision': dn, 'seed': random.randint(1, 999999)}
        self.rec_refused_seen = self.engine.rec_refused
        self.engine.rec_start(seq)
        self.recording = True
        self.rec_seq = seq
        self.rec_t0 = time.monotonic()
        self.rec_state.configure(text="recording (%s)" % source, fg=REC)

    def stop_capture(self, source):
        if not self.recording:
            return
        self.engine.rec_stop()
        self.recording = False
        # FINALIZING: the take is complete only when the writer reports it;
        # audio restarts wait for this (see _open_audio).
        self.finalizing[self.rec_seq] = time.monotonic()
        self.rec_state.configure(text="submitted - writing take (%s)" % source, fg=ACCENT)

    # Bank / playback
    def _sel(self):
        return self.bank.selected_result()

    def _routing_for(self, r):
        try:
            return build_routing_matrix(r.out_ch, self.cfg['routing'])
        except RoutingError as e:
            self.status("Cannot play %s: %s" % (r.rid, e))
            return None, None

    def _playable(self, r):
        if r is None:
            self.status("No result selected.", log=False)
            return False
        if r.status != ST_READY or r.audio is None:
            self.status("%s is %s - nothing to play yet." % (r.rid, r.status), log=False)
            return False
        if not self.engine.is_alive():
            self.status("Audio stream is not running.")
            return False
        if r.out_sr != self.engine.sr:
            self.status("%s was rendered at %d Hz but the stream runs at %d Hz - Regenerate it."
                        % (r.rid, r.out_sr, self.engine.sr))
            return False
        return True

    def play_selected(self):
        r = self._sel()
        if not self._playable(r):
            return
        M, desc = self._routing_for(r)
        if M is None:
            return
        self.clock.decide('manual play %s' % r.rid)
        self.engine.play(r.rid, r.audio, M, 'play')
        self.status("PLAY %s  (%s)" % (r.rid, desc))

    def crossfade_selected(self):
        r = self._sel()
        if not self._playable(r):
            return
        self.clock.decide('manual crossfade %s' % r.rid)
        xf = self.cfg['chains'].get(r.chain_key, {}).get('xfade', r.xfade)
        self._crossfade(r, xf, 'manual')

    def _crossfade(self, r, xf, why):
        M, desc = self._routing_for(r)
        if M is None:
            return False
        xf = min(float(xf), max(0.01, r.out_dur / 2.0)) if r.out_dur > 0 else float(xf)
        was = bool(self.engine.playing_rids())
        self.engine.play(r.rid, r.audio, M, 'xfade', xf)
        self._last_xfade_note = "%s crossfade -> %s over %.1f s%s" % (
            why.upper(), r.rid, xf, "" if was else " (fade-in from silence)")
        self.status("%s  (%s)" % (self._last_xfade_note, desc))
        return True

    def stop_all(self):
        self.clock.decide('stop all')
        self.engine.stop_all(self.cfg.get('stop_fade_s', 0.25))
        self.status("STOP ALL (%.2f s fade)" % self.cfg.get('stop_fade_s', 0.25))

    def step_bank(self, d):
        r = self.bank.step(d)
        self._refresh_bank()
        if r:
            self.status("Selected %s (%s, %s)" % (r.rid, self._chain_label(r.chain_key), r.status), log=False)

    def latest_ready(self):
        r = self.bank.latest_ready()
        if r is None:
            self.status("No READY result yet.", log=False)
            return
        self.bank.select_rid(r.rid)
        self._refresh_bank()
        self.status("Latest ready: %s" % r.rid, log=False)

    def pin_selected(self):
        r = self._sel()
        if r is None:
            return
        r.pinned = not r.pinned
        self.bank.enforce(self.engine.playing_rids())
        self._refresh_bank()
        self.status("%s %s." % (r.rid, "PINNED" if r.pinned else "unpinned"), log=False)

    def regenerate_selected(self):
        r = self._sel()
        if r is None:
            self.status("No result selected.", log=False)
            return
        take = r.take
        if not take.capture_path or not os.path.exists(take.capture_path):
            self.status("Original capture of %s is no longer available." % take.label)
            return
        if take.chain_key == 'selftest':
            self.status("Self-test takes cannot be regenerated through a chain.")
            return
        ch = CHAINS[self.sel_chain]
        if not self.chain_ok.get(ch['key'], True):
            self.status("%s is incompatible - pick another chain" % ch['label'])
            return
        if not self.bank.can_accept_new(self.engine.playing_rids()):
            self.status("BANK FULL: unpin something before regenerating.")
            return
        cc = self.cfg['chains'][ch['key']]
        idx = 1 + max([x.regen_index for x in self.bank.results if x.take is take] + [take.regen_count])
        take.regen_count = idx
        dn = self.clock.decide('regenerate %s' % take.label)
        nr = Result(take, ch['key'], cc['policy'], cc['xfade'], dn,
                    random.randint(1, 999999), idx)
        self.bank.add(nr, self.engine.playing_rids())
        self.bank.select_rid(nr.rid)
        if self.proc_mgr.submit(Job(nr, self.engine.sr)):
            self.status("REGENERATE %s from %s through %s" % (nr.rid, take.label, ch['label']))
        else:
            nr.status = ST_CANCELLED
        self._refresh_bank()

    def export_selected(self):
        r = self._sel()
        if r is None:
            return
        d = self.cfg.get('export_dir') or _default_export_dir()
        try:
            os.makedirs(d, exist_ok=True)
            stamp = time.strftime("%Y%m%d_%H%M%S")
            base = "LiveLab_%s_%s_%s" % (stamp, r.rid.replace('.', '-'),
                                         re.sub(r'[^A-Za-z0-9]+', '', self._chain_label(r.chain_key)))
            written = []
            if r.audio is not None:
                p = os.path.join(d, base + "_result.wav")
                sf.write(p, r.audio, r.out_sr, subtype='PCM_24')
                written.append(p)
            if r.take.capture_path and os.path.exists(r.take.capture_path):
                p = os.path.join(d, base + "_capture.wav")
                shutil.copyfile(r.take.capture_path, p)
                written.append(p)
            with open(os.path.join(d, base + ".json"), 'w', encoding='utf-8') as f:
                json.dump(r.record(), f, indent=2)
            self.status("Exported %s to %s (%d audio file(s) + metadata)" % (r.rid, d, len(written)))
        except Exception as e:
            self.status("Export failed: %s" % e)

    def _release_take(self, take):
        """Called by the bank when no stored result references a Take."""
        try:
            if take.capture_path and os.path.exists(take.capture_path):
                os.remove(take.capture_path)
        except OSError as e:
            self._log("could not delete capture %s: %s" % (take.capture_path, e))

    def _chain_label(self, key):
        return CHAIN_BY_KEY.get(key, SELFTEST_CHAIN)['label']

    # ── MIDI ─────────────────────────────────────────────────────────
    def _apply_midi_cfg(self):
        m = self.cfg['midi']
        self.mapper.set_mappings(m.get('mappings', {}))
        ch = str(m.get('channel', 'Omni'))
        self.mapper.channel = int(ch) if ch.isdigit() else 0
        self.mapper.polarity = m.get('polarity', 'normal')
        try:
            self.mapper.cc_on = int(m.get('cc_on', 64))
            self.mapper.cc_off = int(m.get('cc_off', 40))
        except (TypeError, ValueError):
            self.mapper.cc_on, self.mapper.cc_off = 64, 40

    def _midi_opts_changed(self):
        m = self.cfg['midi']
        m['channel'] = self.v_mch.get()
        m['polarity'] = self.v_pol.get()
        try:
            on, off = int(self.v_ccon.get()), int(self.v_ccoff.get())
            if not (0 <= off < on <= 127):
                raise ValueError
            m['cc_on'], m['cc_off'] = on, off
        except ValueError:
            self.status("CC thresholds: need 0 <= release < press <= 127")
            self.v_ccon.set(str(m.get('cc_on', 64)))
            self.v_ccoff.set(str(m.get('cc_off', 40)))
        self._apply_midi_cfg()
        save_config(self.config_path, self.cfg)
        self._reclaim_focus()

    def _fill_midi_ports(self):
        ports = self.midi.list_ports()
        self.c_mport['values'] = ['(none)'] + ports
        cur = self.midi.port_name or self.cfg['midi'].get('port', '')
        i = self.midi.find_port(cur, ports) if cur else -1
        self.v_mport.set(ports[i] if i >= 0 else ('(none)' if not cur else cur))

    def _open_saved_midi(self):
        want = self.cfg['midi'].get('port', '')
        if not self.midi.available:
            self.midi_lbl.configure(text="MIDI: rtmidi missing", fg=WARN)
            return
        if not want:
            self.midi_lbl.configure(text="MIDI: no port", fg=DIM)
            return
        ok, msg = self.midi.open(want)
        self._log(msg)
        self.midi_lbl.configure(text=("MIDI: " + self.midi.port_name) if ok else "MIDI: PORT MISSING",
                                fg=OK if ok else WARN)
        self._fill_midi_ports()

    def _on_midi_port_selected(self):
        sel = self.v_mport.get()
        if sel in ('', '(none)'):
            self.midi.close()
            self.cfg['midi']['port'] = ''
            self.midi_lbl.configure(text="MIDI: no port", fg=DIM)
        else:
            ok, msg = self.midi.open(sel)
            if ok:
                self.cfg['midi']['port'] = sel
            self.status(msg)
            self.midi_lbl.configure(text=("MIDI: " + self.midi.port_name) if ok else "MIDI: OPEN FAILED",
                                    fg=OK if ok else ERR)
        save_config(self.config_path, self.cfg)

    def midi_learn(self, act):
        if not self.midi.is_open:
            self.status("Select a MIDI input port first (Setup > MIDI).")
            return
        self.mapper.learn = act
        self.map_lbls[act].configure(text="…waiting", fg=WARN)
        self.status("MIDI learn: %s - %s (Esc cancels)" % (
            ACTION_LABEL[act], "press and HOLD the pedal" if act == 'hold_record' else "press a key/pad/switch"))

    def midi_clear(self, act):
        self.cfg['midi']['mappings'].pop(act, None)
        self._apply_midi_cfg()
        self.map_lbls[act].configure(text=mapping_text(None), fg=ACCENT)
        save_config(self.config_path, self.cfg)

    def _on_midi_message(self, msg):
        # rtmidi thread: pure logic + queue; never touches Tk.
        for ev in self.mapper.handle(msg):
            self.midi_q.put(ev)

    def _drain_midi(self):
        while True:
            try:
                ev = self.midi_q.get_nowait()
            except queue.Empty:
                return
            k = ev[0]
            if k == 'pedal':
                self.pedal_state_lbl.configure(text="pedal: DOWN" if ev[1] else "pedal: up",
                                               bg=REC if ev[1] else PANEL2)
                self.pedal(ev[1], 'MIDI ' + ev[2])
            elif k == 'action':
                self.do_action(ev[1], 'MIDI')
                self.midi_event_lbl.configure(text="-> " + ACTION_LABEL.get(ev[1], ev[1]))
            elif k == 'raw':
                self.midi_event_lbl.configure(text="last event: " + ev[1])
            elif k == 'filtered':
                self.midi_event_lbl.configure(text="FILTERED (channel): " + ev[1])
            elif k == 'unmapped':
                self.midi_event_lbl.configure(text="unmapped: " + ev[1])
            elif k == 'learned':
                _, act, mapping, pol = ev
                for a, m in list(self.cfg['midi']['mappings'].items()):
                    if a != act and m and m.get('type') == mapping['type'] and m.get('number') == mapping['number']:
                        self.cfg['midi']['mappings'].pop(a)
                        self.map_lbls[a].configure(text=mapping_text(None), fg=ACCENT)
                self.cfg['midi']['mappings'][act] = mapping
                if act == 'hold_record' and pol:
                    self.cfg['midi']['polarity'] = pol
                    self.v_pol.set(pol)
                self._apply_midi_cfg()
                self.map_lbls[act].configure(text=mapping_text(mapping), fg=OK)
                save_config(self.config_path, self.cfg)
                self.status("MIDI learned: %s -> %s%s" % (ACTION_LABEL[act], mapping_text(mapping),
                                                         (" (polarity %s)" % pol) if pol else ""))

    def _check_midi_port(self):
        want = self.cfg['midi'].get('port', '')
        if not self.midi.available or not want:
            return
        ports = self.midi.list_ports()
        present = self.midi.find_port(want, ports) >= 0
        if self.midi.is_open and not present:
            self.midi.close()
            self.midi_lbl.configure(text="MIDI: PORT LOST", fg=ERR)
            self.status("MIDI port disconnected - %s" % want)
            for ev in self.mapper.pedal_released_by_disconnect():
                self.midi_q.put(ev)
        elif not self.midi.is_open and present:
            ok, msg = self.midi.open(want)
            self.midi_lbl.configure(text=("MIDI: " + self.midi.port_name) if ok else "MIDI: PORT MISSING",
                                    fg=OK if ok else WARN)
            if ok:
                self.status("MIDI port reconnected - " + self.midi.port_name)

    # ── output protection ────────────────────────────────────────────
    def _apply_limiter_cfg(self):
        lim = self.cfg.setdefault('limiter', {'on': True, 'ceiling_db': -0.3})
        try:
            cdb = max(-12.0, min(0.0, float(lim.get('ceiling_db', -0.3))))
        except (TypeError, ValueError):
            cdb = -0.3
        lim['ceiling_db'] = cdb
        self.engine.limit_on = bool(lim.get('on', True))
        self.engine.ceiling = np.float32(10 ** (cdb / 20.0))

    # ── master gain ──────────────────────────────────────────────────
    def _apply_master(self):
        d = float(self.master_var.get())
        self.cfg['master_gain_db'] = d
        self.engine.master = np.float32(10.0 ** (d / 20.0))

    # ── event loop ───────────────────────────────────────────────────
    def _tick(self):
        if self.closing:
            return
        try:
            self._drain_midi()
            self._drain_events()
            if (self.recording or self.rec_seq in self.finalizing) and \
                    self.engine.rec_refused > self.rec_refused_seen:
                self.recording = False
                self.finalizing.pop(self.rec_seq, None)
                self.pending.pop(self.rec_seq, None)
                self.rec_state.configure(text="capture refused (capture buffers busy) - try again", fg=ERR)
            if self.audio_expected and not self.engine.is_alive():
                self.audio_expected = False
                salvaged = self.engine.salvage_recording()
                self.recording = False
                self.audio_msg = "AUDIO DEVICE LOST - Setup > Audio > Apply & restart audio"
                self.audio_lbl.configure(text="AUDIO: LOST", fg=ERR)
                self.status(self.audio_msg + ("  (partial take salvaged)" if salvaged else ""))
            now = time.monotonic()
            if now - self._last_port_check > 2.0:
                self._last_port_check = now
                self._check_midi_port()
        except Exception:
            self._log("tick error: " + traceback.format_exc().splitlines()[-1])
        self._tick_id = self.root.after(15, self._tick)

    def _drain_events(self):
        while True:
            try:
                ev = self.events.get_nowait()
            except queue.Empty:
                return
            k = ev[0]
            if k == 'capture_ready':
                _, seq, path, dur, nch, sr, reason, held = ev
                self.finalizing.pop(seq, None)
                snap = self.pending.pop(seq, None)
                if self.recording and self.rec_seq == seq:
                    self.recording = False          # stopped by itself (max duration)
                if snap is None:
                    try:
                        os.remove(path)
                    except OSError:
                        pass
                    continue
                take = Take(seq, path, dur, nch, sr, snap['chain'], reason)
                r = Result(take, snap['chain'], snap['policy'], snap['xfade'], snap['decision'], snap['seed'], 1)
                self.bank.add(r, self.engine.playing_rids())
                self.bank.select_rid(r.rid)
                if not self.proc_mgr.submit(Job(r, sr)):
                    r.status = ST_CANCELLED
                note = " - MAX DURATION reached" if reason == 'max duration' else (
                    " - " + reason if reason not in ('released',) else "")
                self.rec_state.configure(text="%s submitted: %.1f s %s%s" % (
                    take.label, held, "mono" if nch == 1 else "stereo", note), fg=OK)
                self._log("%s captured %.2f s (%d ch, %d Hz, %s) -> %s, %s" % (
                    take.label, dur, nch, sr, reason, self._chain_label(snap['chain']), snap['policy'].upper()))
            elif k == 'capture_short':
                _, seq, held, reason = ev
                self.finalizing.pop(seq, None)
                self.pending.pop(seq, None)
                if self.recording and self.rec_seq == seq:
                    self.recording = False
                self.rec_state.configure(text="T%03d too short (%.2f s < %.2f s) - discarded"
                                         % (seq, held, self.cfg['capture']['min_s']), fg=WARN)
            elif k == 'capture_failed':
                _, seq, msg = ev
                self.finalizing.pop(seq, None)
                self.pending.pop(seq, None)
                if self.recording and self.rec_seq == seq:
                    self.recording = False
                self.rec_state.configure(text="T%03d failed: %s" % (seq, msg), fg=ERR)
                self._log("T%03d capture failed: %s" % (seq, msg))
            elif k == 'job_started':
                r = self.bank.by_rid(ev[1])
                if r:
                    r.status = ST_PROCESSING
            elif k == 'job_done':
                _, rid, audio, st, secs = ev
                r = self.bank.by_rid(rid)
                if r is None:
                    continue
                r.audio = audio
                r.out_ch = int(audio.shape[1])
                r.out_sr = int(st.get('sample_rate', self.engine.sr))
                r.out_dur = audio.shape[0] / float(r.out_sr)
                r.meta = st
                r.status = ST_READY
                r.completed = time.time()
                go, why = autoplay_verdict(r, self.auto_suspend, self.clock)
                r.autoplay_note = why
                self._log("%s READY in %.1f s (%d ch, %.1f s) - %s" % (rid, secs, r.out_ch, r.out_dur,
                                                                     "AUTO PLAY" if go else "READY: " + why))
                if go and self._playable(r):
                    self._crossfade(r, r.xfade, 'auto')
                self.bank.enforce(self.engine.playing_rids())
            elif k == 'job_failed':
                _, rid, msg = ev
                r = self.bank.by_rid(rid)
                if r:
                    r.status = ST_FAILED
                    r.error = msg
                self.proc_err.configure(text="%s failed: %s" % (rid, msg[:400]))
                self._log("%s FAILED: %s" % (rid, msg))
            elif k == 'job_cancelled':
                _, rid, msg = ev
                r = self.bank.by_rid(rid)
                if r:
                    r.status = ST_CANCELLED
                    r.error = msg
            elif k == 'praat_info':
                info = ev[1]
                self.praat = info
                self.proc_mgr.set_praat(info)
                if info.get('path'):
                    txt = "Praat %s  ·  %s\nworker flags: %s\nworker script (session copy): %s" % (
                        info['version'], info['path'], " ".join(info['flags']), self.worker_script)
                    if self.guard.error and not self.guard.job and os.name == 'nt':
                        txt += "\nPROCESSING DISABLED: " + self.guard.error
                    self._log("Praat %s found: %s" % (info['version'], info['path']))
                else:
                    txt = ("No working Praat executable found - processing disabled.\nTried:\n  "
                           + "\n  ".join(info.get('tried', [])) + "\nSet the path above.")
                    self._log("Praat executable not found")
                self.praat_msg.configure(text=txt)

    # ── periodic UI refresh ─────────────────────────────────────────
    def _refresh_chain_buttons(self):
        keys = self.cfg['keys']
        for i, (b, c) in enumerate(zip(self.chain_btns, CHAINS)):
            cc = self.cfg['chains'][c['key']]
            k = keys.get('chain_%d' % (i + 1), '')
            ok = getattr(self, 'chain_ok', {}).get(c['key'], True)
            b.configure(text="[%s]  %s\n%s%s" % (k or '-', c['label'], cc['policy'].upper(),
                                                 ("  ·  xf %.1fs" % cc['xfade']) if cc['policy'] == 'auto' else '')
                        + ("" if ok else "\nINCOMPATIBLE"),
                        bg=SEL if i == self.sel_chain else (ERR if not ok else BTN))

    def _refresh_bank(self):
        tree = self.tree
        playing = self.engine.playing_rids()
        want = [r.rid for r in self.bank.results]
        have = list(tree.get_children())
        for iid in have:
            if iid not in want:
                tree.delete(iid)
        for r in self.bank.results:
            st = 'PLAYING' if r.rid in playing else r.status
            note = r.error if r.status == ST_FAILED else (r.autoplay_note if r.status == ST_READY else '')
            if r.status == ST_READY and r.meta.get('clip_guard') == '1':
                note = (note + "; " if note else "") + "peak guard applied"
            vals = (r.rid, self._chain_label(r.chain_key), st,
                    ("%.1f s" % r.out_dur) if r.out_dur else ("cap %.1f s" % r.take.capture_dur),
                    r.out_ch or r.take.in_ch, r.policy.upper(), "📌" if r.pinned else "",
                    (("%d%s" % (r.seed, " ✓" if CHAIN_BY_KEY.get(r.chain_key, {}).get('repro') else ""))
                     if r.seed else ""), note)
            if tree.exists(r.rid):
                tree.item(r.rid, values=vals, tags=(st,))
            else:
                tree.insert('', 'end', iid=r.rid, values=vals, tags=(st,))
        sel = self.bank.selected_result()
        if sel is not None and tree.exists(sel.rid):
            if tuple(tree.selection()) != (sel.rid,):
                tree.selection_set(sel.rid)
            tree.see(sel.rid)
        self.bank_info.configure(text="%d / %d  ·  %.0f MB  ·  %d evicted" % (
            len(self.bank), self.bank.capacity, self.bank.memory_used() / 1048576.0, self.bank.evicted_total))

    def _on_tree_select(self, _e):
        s = self.tree.selection()
        if s:
            self.bank.select_rid(s[0])

    def _refresh_ui(self):
        if self.closing:
            return
        try:
            self._refresh_frame()
        except Exception:
            self._log("ui error: " + traceback.format_exc().splitlines()[-1])
        self._ui_id = self.root.after(70, self._refresh_ui)

    def _refresh_frame(self):
        e = self.engine
        # capture
        ch = CHAINS[self.sel_chain]
        if self.recording:
            t = time.monotonic() - self.rec_t0
            self.rec_lbl.configure(text="● RECORDING", bg=REC)
            self.rec_time.configure(text=fmt_time(t), fg=REC)
            self.rec_info.configure(text="Take T%03d  ·  %s" % (self.rec_seq, CHAIN_BY_KEY[self.pending.get(
                self.rec_seq, {'chain': ch['key']})['chain']]['label']))
        else:
            self.rec_lbl.configure(text="HOLD TO RECORD" if self.armed else "DISARMED",
                                   bg=PANEL2 if self.armed else BTN)
            self.rec_time.configure(fg=DIM)
            self.rec_info.configure(text="next take T%03d  ·  %s" % (self.next_take, ch['label']))
        self.in_meter.update(e.in_peak if e.capture_enabled else [])
        self.out_meter.update(e.out_peak)
        # processing
        cur = self.proc_mgr.current
        if cur is not None:
            self.proc_active.configure(text="▶ %s  ·  %s  ·  %.0f s" % (
                cur.result.rid, self._chain_label(cur.result.chain_key), time.time() - cur.started), fg=WARN)
        else:
            self.proc_active.configure(text="idle" if self.praat.get('path') else "NO PRAAT - Setup > Praat",
                                       fg=FG if self.praat.get('path') else ERR)
        ready = sum(1 for r in self.bank.results if r.status == ST_READY)
        self.proc_counts.configure(text="queued %d  ·  completed %d  ·  failed %d  ·  ready in bank %d" % (
            len(self.proc_mgr.queued()), self.proc_mgr.done_count, self.proc_mgr.fail_count, ready))
        # playback
        vs = [v for v in list(e.voices) if not v.done]
        main = [v for v in vs if not v.fading_out]
        fading = [v for v in vs if v.fading_out]
        if vs:
            v = main[-1] if main else vs[-1]
            rem = (v.n - v.pos) / float(e.sr)
            self.now_lbl.configure(text="NOW PLAYING: %s  ·  -%s%s" % (
                v.rid, fmt_time(rem), ("   (+%d layered)" % (len(main) - 1)) if len(main) > 1 else ""))
            self.now_bar['value'] = 1000.0 * v.pos / max(1, v.n)
        else:
            self.now_lbl.configure(text="NOW PLAYING: -")
            self.now_bar['value'] = 0
        if fading:
            f = fading[0]
            self.xf_lbl.configure(text="crossfade: %s out %d%%  →  %s" % (
                f.rid, int(100 * f.fo_pos / max(1, f.fo_len)), main[-1].rid if main else "silence"))
        elif main and main[-1].fi_pos < main[-1].fi_len:
            m = main[-1]
            self.xf_lbl.configure(text="fading in %s  %d%%" % (m.rid, int(100 * m.fi_pos / max(1, m.fi_len))))
        else:
            self.xf_lbl.configure(text=self._last_xfade_note and ("last: " + self._last_xfade_note) or "")
        sel = self.bank.selected_result()
        if sel is not None:
            self.next_lbl.configure(text="NEXT / READY: %s  ·  %s  ·  %s" % (
                sel.rid, self._chain_label(sel.chain_key), sel.status),
                fg=OK if sel.status == ST_READY else DIM)
        else:
            self.next_lbl.configure(text="NEXT / READY: -", fg=DIM)
        # overload / callback status
        msgs = []
        if e.limit_on and e.lim_gain < 0.999:
            msgs.append("LIMITER %.1f dB" % (20 * math.log10(max(e.lim_gain, 1e-6))))
        if e.clip_count != self._seen_clip:
            msgs.append(("overs caught by limiter: %d" if e.limit_on else "OUTPUT CLIP x%d") % e.clip_count)
        if e.status_count != self._seen_status:
            msgs.append("callback: %s (x%d)" % (e.last_status.strip(), e.status_count))
        self.ovl_lbl.configure(text="  ·  ".join(msgs) if msgs else "no overloads",
                               fg=ERR if msgs else DIM)
        self._refresh_bank()

    # ── shutdown (zero residue) ─────────────────────────────────────
    def close(self):
        if self.closing:
            return
        self.closing = True
        for aid in (getattr(self, '_tick_id', None), getattr(self, '_ui_id', None),
                    getattr(self, '_front_id', None), self._key_hold_pending):
            if aid:
                try:
                    self.root.after_cancel(aid)
                except Exception:
                    pass
        report = shutdown_sequence(self)
        try:
            self.root.destroy()
        except Exception:
            pass
        self.shutdown_report = report


def shutdown_sequence(app):
    """Ordered teardown; returns a list of problems (empty = clean)."""
    problems = []
    # 1. disarm, refuse new jobs
    app.armed = False
    with app.proc_mgr.cv:
        app.proc_mgr.accepting = False
    # 2. stop recording (the take is dropped: nothing would process it)
    if app.recording:
        app.engine.rec_stop()
        app.recording = False
    # 3. stop playback, release the audio stream
    try:
        app.engine.stop_all(0.05)
        time.sleep(0.12)
    except Exception:
        pass
    app.engine.close()
    # 4. MIDI
    try:
        app.midi.close()
    except Exception as e:
        problems.append("MIDI close: %s" % e)
    # 5./6. workers: cancel, kill tree, reap
    if not app.proc_mgr.shutdown(15.0):
        problems.append("processing thread did not stop")
    p = app.proc_mgr.proc
    if p is not None and p.poll() is None:
        ProcessGuard.kill_tree(p)
        try:
            p.wait(5)
        except Exception:
            problems.append("Praat worker PID %d could not be reaped" % p.pid)
    app.writer.discard = True               # pending takes are dropped, not written
    app.writer.stop_evt.set()
    t0 = time.monotonic()
    while app.writer.is_alive() and time.monotonic() - t0 < 30.0:
        app.writer.join(0.5)
    writer_busy = app.writer.is_alive()
    if writer_busy:
        # CLEANUP_PENDING: the one place that decides about deletion says
        # "not now"; the atexit hook honours it, the next launch removes it.
        app.ws.cleanup_pending = True
        problems.append("capture writer still busy after 30 s - workspace kept (CLEANUP_PENDING), "
                        "it is removed at the next launch")
    # 7. buffers and file handles
    app.engine.done_caps.clear()
    app.engine.free_bufs.clear()
    app.bank.on_take_released = None
    app.bank.clear_all()
    # persistent configuration first (outside the workspace) ...
    save_config(app.config_path, app.cfg)
    app.guard.close()
    # 8. ... then the entire session workspace (never while a writer may use it)
    if writer_busy:
        pass
    elif not app.ws.remove():
        problems.append("session workspace could not be fully removed: %s" % app.ws.path)
    elif os.path.exists(app.ws.path):
        problems.append("session workspace still exists: %s" % app.ws.path)
    if problems:
        log_line("SHUTDOWN PROBLEMS: " + "; ".join(problems))
    else:
        log_line("Shutdown clean: no workers, streams or workspace files remain.")
    return problems


# ══════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════
def _write_error_file(path, text):
    """The ONLY file Live Lab writes outside its workspace besides the
    config: a crash/cleanup report that Live_Lab.praat shows and deletes."""
    if not path:
        return
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)      # the empty app root may have been removed
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
    except Exception:
        pass


CONFIG_TMP_RE = re.compile(r'^live_lab_config\.json\.tmp_\d+$')


def recover_config_temp_files(plugin_dir, age_s=60.0):
    """A crash between writing live_lab_config.json.tmp_<pid> and replacing
    the config can leave that exact file behind; remove only that pattern."""
    out = []
    try:
        names = os.listdir(plugin_dir)
    except OSError:
        return out
    now = time.time()
    for n in names:
        if CONFIG_TMP_RE.match(n):
            full = os.path.join(plugin_dir, n)
            try:
                if os.path.isfile(full) and now - os.path.getmtime(full) > age_s:
                    os.remove(full)
                    out.append("removed stale config temp file " + n)
            except OSError:
                pass
    return out


def _import_runtime(error_file):
    global sd, sf, rtmidi, _RTMIDI_ERR
    missing = []
    try:
        import tkinter  # noqa: F401
    except Exception:
        missing.append('tkinter')
    try:
        import sounddevice as _sd
        sd = _sd
    except Exception as e:
        missing.append('sounddevice (%s)' % e)
    try:
        import soundfile as _sf
        sf = _sf
    except Exception as e:
        missing.append('soundfile (%s)' % e)
    if missing:
        msg = ("Live Lab cannot start - missing Python packages:\n  " + "\n  ".join(missing) +
               "\n\nInstall them into the Python that Live_Lab.praat selected, e.g.:\n"
               "  python -m pip install numpy sounddevice soundfile\n"
               "Optional (MIDI pedal / controller):\n  python -m pip install python-rtmidi")
        _write_error_file(error_file, msg)
        print(msg, file=sys.stderr)
        sys.exit(2)
    try:
        import rtmidi as _rt
        rtmidi = _rt
    except Exception as e:
        rtmidi = None
        _RTMIDI_ERR = str(e)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Praat AudioTools Live Lab")
    ap.add_argument('--plugin-dir', required=True)
    ap.add_argument('--chain-dir', required=True)
    ap.add_argument('--error-file', default='')
    ap.add_argument('--done-file', default='')
    ap.add_argument('--praat-hint', default='')
    ap.add_argument('--workspace-root', default='')
    args = ap.parse_args(argv)

    _import_runtime(args.error_file)
    root_dir = args.workspace_root or default_workspace_root()
    report = recover_stale_sessions(root_dir)
    report += recover_config_temp_files(args.plugin_dir)
    for ln in report:
        log_line(ln)
    ws = SessionWorkspace(root_dir)
    try:
        ws.create()
    except Exception as e:
        _write_error_file(args.error_file, "Live Lab could not create its session workspace in %s:\n%s"
                          % (root_dir, e))
        return 3

    import atexit
    atexit.register(ws.remove_at_exit)  # last resort; honours CLEANUP_PENDING

    import tkinter as tk
    app = None
    try:
        root = tk.Tk()
        app = LiveLabApp(root, args, ws, report)

        def _sig(*_a):
            try:
                root.after(0, app.close)
            except Exception:
                pass
        for s in (signal.SIGINT, signal.SIGTERM):
            try:
                signal.signal(s, _sig)
            except Exception:
                pass
        ac = os.environ.get('LIVE_LAB_AUTOCLOSE_S', '')     # test hook only
        if ac:
            root.after(int(float(ac) * 1000), app.close)
        root.mainloop()
        if not app.closing:
            app.close()
        problems = getattr(app, 'shutdown_report', None)
        if problems is None:
            _write_error_file(args.error_file, "Live Lab window closed without running its shutdown sequence.")
            return 5
        if problems:
            _write_error_file(args.error_file, "Live Lab closed, but cleanup reported problems:\n  - "
                              + "\n  - ".join(problems))
            return 4
        # POSITIVE completion report: Live_Lab.praat only says "closed
        # cleanly" when this file exists - not merely when no error file does.
        _write_error_file(args.done_file, "clean\nworkspace removed: %s\n" % ws.path)
        return 0
    except Exception:
        tb = traceback.format_exc()
        cleanup = ''
        try:
            if app is not None and not app.closing:
                app.closing = True
                probs = shutdown_sequence(app)
                cleanup = ("\nEmergency cleanup: " + ("clean" if not probs else "; ".join(probs)))
            elif not ws.removed:
                cleanup = "\nEmergency cleanup: workspace %s" % ("removed" if ws.remove() else "NOT removed")
        except Exception as e:
            cleanup = "\nEmergency cleanup failed: %s" % e
        _write_error_file(args.error_file, "Live Lab crashed:\n" + tb + cleanup)
        print(tb, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
