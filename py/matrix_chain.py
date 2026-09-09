#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      matrix_chain.py
# Author:      Shai Cohen
# Version:     0.3 (2026)
#
# Changelog v0.3:
#   - The render is written with "Save as 32-bit WAV file": plain "Save as WAV
#     file" is 16-bit, so every render was quantised on the way out even when
#     the whole chain ran in memory.  (Praat's 32-bit WAV is integer PCM in a
#     WAVE_FORMAT_EXTENSIBLE header, not float.)
#   - The peak ceiling is now its own "Safety ceiling" checkbox instead of an
#     unannounced attenuation; with it off the output is untouched.
#   - "Include Python bridges" is saved with the chain and switched on
#     automatically when a saved chain contains a bridge slot.
#   - WAV reading handles float and extensible headers, and winsound plays a
#     16-bit copy since the old multimedia API mishandles 32-bit extensible.
#   - Audition downmixes anything wider than stereo to a temporary stereo copy
#     and says so in the status line.  Multichannel playback through the
#     default device depends on the interface's channel mapping, so it would
#     be unpredictable; the render and Apply keep every channel.
#   - The Praat subprocess inherits a PATH with this interpreter's folder (and
#     its venv Scripts/bin) prepended, so a bridge script's own "python"
#     lookup finds the same environment the host runs in instead of a system
#     Python without the backend's packages.
#   - Output decoding handles a mixed stream: Praat's UTF-16 and a nested
#     Python backend's UTF-8 in one pipe are decoded run by run, so a
#     backend's error text stays readable instead of turning into mojibake.
#   - Output contract: resolveSound no longer falls back to the input Sound,
#     so a slot that leaves nothing selected fails the render instead of being
#     silently bypassed.  It also logs when a slot leaves several Sounds, when
#     it modifies its input in place, and each stage's duration.
#   - Python bridges are selectable behind "Include Python bridges", which
#     rescans with py/ included.  A bridge slot must leave a NEW Sound object,
#     never the input, or the render fails with a bridge-specific message.
#   - A generator can only be the first active slot, in Series mode: filtered
#     out of rows 2-4 and re-checked at render time, so a saved chain cannot
#     slip past the picker.
#   - Booleans are normalised through one truthy() helper, so a default of
#     "On"/"Yes"/"TRUE" no longer displays unticked and get sent as 0.
#   - Mix% is labelled Branch% -- it is that branch's gain in the sum, not a
#     wet/dry balance.  APP_VERSION now matches the header.
#
# Changelog v0.2:
#   - Empty numeric parameter values are filled with a legal default rather
#     than sent to runScript: as an empty string (see inspector v0.2).
#   - The render runs in a worker thread instead of blocking Tk: the window
#     stays live, an indeterminate bar animates, and the status line reports
#     the slot Praat is actually executing ("slot 2: X (2/3) — 6.4 s"), read
#     from the wrapper's progress file.  Stop now cancels a running render.
#   - FIXED: readonly comboboxes drew their text grey-on-grey once focus moved
#     away, so a chosen category/script looked like it had been cleared.  The
#     style now sets foreground AND the readonly/focus selection colours, and
#     the dropdown list is themed through the option database.
#   - A parameter forced off for the render is shown unticked rather than as a
#     greyed-out tick, matching the value actually sent.
#   - Audition no longer needs sounddevice: it falls back to winsound on
#     Windows (stdlib, plays a WAV asynchronously) and then to afplay/aplay/
#     paplay, and stops playback before a render overwrites the scratch file.
#   - The focused slot is highlighted, the Mix box is enabled only in Parallel
#     mode, each row states its routing, and a signal-flow line shows the chain
#     exactly as the wrapper will build it.
#   - Praat's stdout/stderr are decoded as UTF-16 when the null pattern says
#     so: on Windows an error message was arriving as the single letter "P".
#   - The progress file now records a line BEFORE each step ("reading input",
#     "calling slot 2: X"), so the failing script is named even with no usable
#     stderr.
#   - Praat detection no longer parses stdout: on Windows Praat is a GUI
#     binary whose stdout is empty when launched from Python, so a good
#     executable was reported as "not found".  The probe now runs a three-line
#     script that writes praatVersion to a marker file, trying --FULL-TRUST
#     first (Praat 7) and plain --run second (Praat 6), and keeps whichever
#     worked.
#   - Renders no longer depend on stdout either: the wrapper appends its
#     progress and result statistics to a plain text file, so a failure can
#     name the last stage that completed even when Windows returns nothing.
#   - Praat executable: a "Praat…" button locates it by hand and remembers it
#     in matrix_chain_config.json; praatExe$ / the picker now also accept the
#     FOLDER that contains Praat.exe; autodetect looks in Desktop/Downloads/
#     Documents/Music sub-folders as well as the standard install paths.
# License:     MIT License
#
# Description:
#   Python-hosted GUI that chains up to four AudioTools .praat scripts in
#   series and/or parallel over one Sound exported from Praat.  Praat is the
#   entry and exit point only; this process is the host.
#
#   Every Audition/Apply click generates ONE disposable wrapper .praat file
#   for the whole active chain and runs it in ONE headless `praat --run`
#   subprocess.  Sound objects are passed from slot to slot in memory --
#   `Save as WAV file` is called exactly once, at the very end.
#
# Usage:
#   python matrix_chain.py <manifest.json>              (launched by Praat)
#   python matrix_chain.py --wav in.wav --library DIR   (standalone testing)
# ============================================================

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import traceback

from praat_script_inspector import scan_library, MENU_TYPES

APP_VERSION = "0.3"
N_SLOTS = 4

# ── Top-level error trap (same convention as arranger.py) ────────────────────
_error_file = None


def _crash(exc):
    tb = traceback.format_exc()
    msg = f"{type(exc).__name__}: {exc}\n\n{tb}"
    if _error_file:
        try:
            with open(_error_file, "w", encoding="utf-8") as f:
                f.write(msg)
        except Exception:
            pass
    print(msg, file=sys.stderr)
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# PRAAT DISCOVERY AND EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

def decode_praat_output(raw):
    """Decode Praat's stdout/stderr, which can hold TWO encodings at once.

    Windows Praat writes UTF-16, but a Python backend called by a bridge
    script writes UTF-8 into the same pipe.  Decoding the buffer with one
    encoding turns whichever half guessed wrong into mojibake -- and the half
    that gets lost is usually the backend's error message.  So decode the
    UTF-16 runs (ASCII interleaved with nulls) separately from the rest.
    """
    if not raw:
        return ""
    if isinstance(raw, str):
        return raw
    if raw.count(b"\x00") == 0:
        for enc in ("utf-8", "cp1252", "latin-1"):
            try:
                return raw.decode(enc)
            except UnicodeDecodeError:
                continue
        return raw.decode("utf-8", errors="replace")

    out, pos = [], 0
    # a run of UTF-16-LE text: printable byte, null, repeated
    for m in re.finditer(rb"(?:[\x09\x0a\x0d\x20-\xff]\x00){3,}", raw):
        if m.start() > pos:
            out.append(raw[pos:m.start()].replace(b"\x00", b"")
                       .decode("utf-8", errors="replace"))
        out.append(m.group(0).decode("utf-16-le", errors="replace"))
        pos = m.end()
    if pos < len(raw):
        out.append(raw[pos:].replace(b"\x00", b"")
                   .decode("utf-8", errors="replace"))
    text = "".join(out)
    if text.startswith("\ufeff"):
        text = text[1:]
    return text


def child_env():
    """Environment for the Praat subprocess.

    A bridge script runs its own Python discovery inside Praat, usually
    trying bare "python" first.  Praat launches this host by calling the venv
    interpreter directly, which does NOT put the venv on PATH, so that nested
    "python" resolves to the system install -- missing torch, numpy and the
    rest, and the backend fails.  Prepending this interpreter's own folder
    makes the nested lookup find the interpreter that is already running us.
    """
    env = dict(os.environ)
    here = os.path.dirname(os.path.abspath(sys.executable))
    parts = [here]
    scripts = os.path.join(os.path.dirname(here), "Scripts")
    if os.path.isdir(scripts) and scripts not in parts:
        parts.append(scripts)
    binx = os.path.join(os.path.dirname(here), "bin")
    if os.path.isdir(binx) and binx not in parts:
        parts.append(binx)
    env["PATH"] = os.pathsep.join(parts + [env.get("PATH", "")])
    venv = os.path.dirname(here)
    if os.path.isfile(os.path.join(venv, "pyvenv.cfg")):
        env["VIRTUAL_ENV"] = venv
    env.setdefault("PYTHONIOENCODING", "utf-8")
    return env


class PraatRunner:
    """Locates a Praat executable, learns its version, runs wrapper scripts."""

    def __init__(self, exe=None):
        self.exe = exe or ""
        self.version = 0          # 6406 for 6.4.06, 7000 for 7.0
        self.version_str = ""
        self.error = ""
        self.full_trust = False
        if not self.exe:
            self.autodetect()
        elif not self.probe(self.exe):
            self.autodetect()

    def autodetect(self):
        for cand in praat_candidates() + extra_candidates():
            path = cand if os.path.isfile(cand) else shutil.which(cand)
            if path and self.probe(path):
                self.exe = path
                return True
        # Do not leave a stale bad path behind: an empty exe is what the
        # render path checks before it tries to launch anything.
        self.exe = ""
        self.version = 0
        self.version_str = ""
        self.error = ("No Praat executable found - click 'Praat…' to locate "
                      "Praat.exe, or set praatExe$ in Matrix_Chain.praat.")
        return False

    @staticmethod
    def _resolve(path):
        """Accept an executable OR the folder that contains it."""
        if not path:
            return ""
        path = os.path.expanduser(path)
        if os.path.isdir(path):
            for exe in ("Praat.exe", "praat.exe", "Praat", "praat",
                        "praat_nogui", "Praat.app/Contents/MacOS/Praat"):
                cand = os.path.join(path, exe)
                if os.path.isfile(cand):
                    return cand
            return ""
        return path

    def probe(self, path):
        """Confirm a Praat executable by RUNNING it, not by reading stdout.

        On Windows Praat is a GUI-subsystem binary: launched from Python its
        stdout is normally empty, so a `--version` parse reports "not found"
        for a perfectly good executable.  Instead we run a three-line script
        that writes praatVersion to a marker file.  That proves the three
        things that actually matter: the binary runs, it runs headless, and it
        is allowed to write a file.
        """
        path = self._resolve(path)
        if not path:
            self.error = "No Praat executable at that location."
            return False

        tmp = tempfile.gettempdir()
        marker = os.path.join(tmp, "mc_version.txt")
        script = os.path.join(tmp, "mc_version.praat")
        try:
            with open(script, "w", encoding="utf-8") as f:
                f.write("if praatVersion >= 7000\n"
                        "    trustGranted = askForTrust()\n"
                        "endif\n"
                        f"writeFileLine: {praat_str(marker)}, praatVersion\n")
        except OSError as exc:
            self.error = f"Cannot write a probe script to {tmp}: {exc}"
            return False

        # Praat 7 needs --FULL-TRUST to write anything; Praat 6 rejects the
        # flag outright.  We do not know which we have yet, so try both.
        last = ""
        for flags in (["--FULL-TRUST", "--run"], ["--run"]):
            if os.path.exists(marker):
                try:
                    os.remove(marker)
                except OSError:
                    pass
            try:
                r = subprocess.run([path] + flags + [script],
                                   capture_output=True, timeout=60)
                last = (decode_praat_output(r.stderr) +
                        decode_praat_output(r.stdout)).strip()[:200]
            except subprocess.TimeoutExpired:
                self.error = (f"{path} did not exit within 60 s. If a Praat "
                              f"window opened, this build hands the command to "
                              f"the running instance instead of running "
                              f"headless.")
                return False
            except Exception as exc:                          # noqa: BLE001
                last = str(exc)
                continue
            if os.path.exists(marker):
                try:
                    with open(marker, "r", encoding="utf-8",
                              errors="replace") as f:
                        v = int(float(f.read().strip().split()[0]))
                except Exception:
                    v = 0
                self.version = v or 6000
                major, rest = divmod(self.version, 1000)
                minor, patch = divmod(rest, 100)
                self.version_str = (f"{major}.{minor}" +
                                    (f".{patch:02d}" if patch else ""))
                self.exe = path
                self.error = ""
                self.full_trust = "--FULL-TRUST" in flags
                return True
        self.error = (f"{os.path.basename(path)} ran but wrote no marker file. "
                      f"{last}" if last else
                      f"{os.path.basename(path)} ran but wrote no marker file.")
        return False

    def argv(self, script_path):
        args = [self.exe, "--run"]
        if self.full_trust or self.version >= 7000:
            # Writing a WAV is trust-gated from Praat 7.0 onward.  6.x rejects
            # the flag outright ("Unrecognized command line option"), so it is
            # added only when the version says it exists.
            args.insert(1, "--FULL-TRUST")
        return args + [script_path]

    def popen(self, script_path):
        """Launch a wrapper without waiting, so the GUI stays responsive."""
        argv = self.argv(script_path)
        return subprocess.Popen(argv, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=child_env()), argv

    def run(self, script_path, timeout):
        argv = self.argv(script_path)
        try:
            r = subprocess.run(argv, capture_output=True, timeout=timeout,
                               env=child_env())
        except subprocess.TimeoutExpired:
            return -1, "", f"Timed out after {timeout} s", argv
        return (r.returncode, decode_praat_output(r.stdout),
                decode_praat_output(r.stderr), argv)


# ─────────────────────────────────────────────────────────────────────────────
# WRAPPER GENERATION
# ─────────────────────────────────────────────────────────────────────────────

def truthy(value) -> bool:
    """Praat writes booleans as 1/0, yes/no, on/off and any capitalisation.

    Two different spellings-lists (one in the host, one in the GUI) meant a
    default of "On" or "Yes" displayed unticked and was then sent as 0.
    """
    return str(value).strip().lower() in ("1", "yes", "true", "on", "y")


def praat_str(value: str) -> str:
    """Praat string literal.

    A single quote can NEVER appear in a Praat string literal -- it starts
    variable interpolation and pairs with the next one it finds, even across
    two separate literals.  Library files such as Risset's_Mutations.praat
    therefore have to be assembled from unicode$(39).
    """
    s = str(value).replace('"', '""')
    if "'" not in s:
        return f'"{s}"'
    parts = s.split("'")
    out = []
    for i, p in enumerate(parts):
        if i:
            out.append("apo$")
        if p:
            out.append(f'"{p}"')
    return " + ".join(out) if out else '""'


def chain_stages(slots):
    """Group active slots into stages: consecutive Parallel slots collapse."""
    stages, cur = [], None
    for s in slots:
        if not s.active:
            continue
        if s.mode == "Series":
            if cur:
                stages.append(("parallel", cur))
                cur = None
            stages.append(("series", [s]))
        else:
            cur = (cur or []) + [s]
    if cur:
        stages.append(("parallel", cur))
    return stages


class Slot:
    """One matrix position: a script, a routing mode, a mix weight, parameters."""

    def __init__(self, index):
        self.index = index
        self.script = None       # ScriptInfo
        self.mode = "Off"        # Series / Parallel / Off
        self.mix = 100.0         # percent, used only when Parallel
        self.values = {}         # param.var -> string value

    @property
    def active(self):
        return self.script is not None and self.mode in ("Series", "Parallel")

    def defaults(self):
        if self.script:
            self.values = {p.var: p.default for p in self.script.params}

    def arg_list(self, force_play_off=True, force_draw_off=True):
        args = []
        for p in self.script.params:
            v = self.values.get(p.var, p.default)
            if force_play_off and p.is_play:
                v = "0"
            if force_draw_off and p.is_draw and p.ptype == "boolean":
                v = "0"
            if p.ptype == "boolean":
                v = "1" if truthy(v) else "0"
            v = str(v)
            if not v.strip() and p.ptype in ("real", "positive", "integer",
                                             "natural"):
                v = "1" if p.ptype in ("positive", "natural") else "0"
            args.append(v)
        return args


class WrapperBuilder:
    """Builds one .praat file that renders the whole chain in one Praat run."""

    def __init__(self, slots, input_wav, output_wav, opts, stats_path=""):
        self.slots = [s for s in slots if s.active]
        self.input_wav = input_wav
        self.output_wav = output_wav
        self.stats_path = stats_path
        self.o = opts
        self.lines = []

    def w(self, line=""):
        self.lines.append(line)

    def stages(self):
        return chain_stages(self.slots)

    def run_script_call(self, slot, var_prefix):
        args = slot.arg_list(self.o["force_play_off"], self.o["force_draw_off"])
        path = praat_str(slot.script.path)
        # A "calling" line is written BEFORE the call, so a script that dies
        # headless is named in the progress file even when Praat returns
        # nothing usable on stderr.
        self.w(f'appendFileLine: mcStats$, "calling slot {slot.index}: '
               f'{slot.script.name} ({len(args)} args)"')
        if args:
            arglist = ", ".join(praat_str(a) for a in args)
            self.w(f"runScript: {path}, {arglist}")
        else:
            self.w(f"runScript: {path}")
        need_new = 1 if getattr(slot.script, "is_bridge", False) else 0
        self.w(f"@resolveSound: {var_prefix}, {slot.index}, {need_new}")
        self.w(f"{var_prefix} = resolvedSound")

    def conform(self, var, sr_var, nch_var):
        """Align one Sound's start time, sample rate and channel count."""
        self.w(f"selectObject: {var}")
        self.w('Shift times to: "start time", 0')
        self.w("cfSR = Get sampling frequency")
        self.w(f"if cfSR <> {sr_var}")
        self.w(f"    Resample: {sr_var}, 50")
        self.w(f"    {var} = selected(\"Sound\")")
        self.w(f"    selectObject: {var}")
        self.w("endif")
        self.w("cfCH = Get number of channels")
        self.w(f"if cfCH <> {nch_var}")
        self.w(f"    if {nch_var} = 1")
        self.w("        Convert to mono")
        self.w("    else")
        self.w("        Convert to stereo")
        self.w("    endif")
        self.w(f"    {var} = selected(\"Sound\")")
        self.w("endif")

    def build(self):
        o = self.o
        self.w("# ============================================================")
        self.w(f"# Auto-generated by matrix_chain.py v{APP_VERSION} - disposable.")
        self.w("# One Praat run for the whole chain; Sounds are passed in memory.")
        self.w("# ============================================================")
        self.w("apo$ = unicode$(39)")
        self.w(f"mcStats$ = {praat_str(self.stats_path)}")
        self.w('writeFileLine: mcStats$, "start"')
        self.w("if praatVersion >= 7000")
        self.w("    trustGranted = askForTrust()")
        self.w("endif")
        self.w("")
        # Output contract.  There is deliberately NO fallback to the input
        # Sound: a slot that leaves nothing selected used to be bypassed in
        # silence, so a failed effect looked like a successful render.
        self.w("procedure resolveSound: .prev, .slot, .requireNew")
        self.w('    .n = numberOfSelected("Sound")')
        self.w("    if .n = 0")
        self.w('        appendFileLine: mcStats$, "MC-ERROR slot ", .slot,')
        self.w('            ... " left no Sound selected"')
        self.w('        exitScript: "MC-ERROR: slot ", .slot, " left no Sound '
               'selected. It is not usable as a chain effect."')
        self.w("    endif")
        self.w("    .best = 0")
        self.w("    for .k from 1 to .n")
        self.w('        .c = selected("Sound", .k)')
        self.w("        if .c > .best")
        self.w("            .best = .c")
        self.w("        endif")
        self.w("    endfor")
        self.w("    if .n > 1")
        self.w('        appendFileLine: mcStats$, "note: slot ", .slot, " left ",')
        self.w('            ... .n, " Sounds selected; taking the newest"')
        self.w("    endif")
        self.w("    if .requireNew = 1 and .best <= .prev")
        self.w('        appendFileLine: mcStats$, "MC-ERROR slot ", .slot,')
        self.w('            ... " python bridge produced no new Sound"')
        self.w('        exitScript: "MC-ERROR: slot ", .slot, " python bridge '
               'produced no chainable Sound output."')
        self.w("    endif")
        self.w("    if .best = .prev")
        self.w('        appendFileLine: mcStats$, "note: slot ", .slot,')
        self.w('            ... " modified its input in place (no new object)"')
        self.w("    endif")
        self.w("    resolvedSound = .best")
        self.w("endproc")
        self.w("")
        self.w(f'appendFileLine: mcStats$, "reading input"')
        self.w(f"Read from file: {praat_str(self.input_wav)}")
        self.w("mcDur = Get total duration")
        self.w('appendFileLine: mcStats$, "input ok ", mcDur')
        self.w('cur = selected("Sound")')
        self.w("selectObject: cur")
        self.w('Rename: "mc_input"')
        need_dry = o["dry_wet"] < 0.999
        if need_dry:
            self.w("selectObject: cur")
            self.w('Copy: "mc_dry"')
            self.w('dry = selected("Sound")')
        self.w("")

        for si, (kind, members) in enumerate(self.stages(), start=1):
            if kind == "series":
                s = members[0]
                self.w(f"# --- stage {si}: series, slot {s.index} "
                       f"({s.script.name}) ---")
                self.w("selectObject: cur")
                self.run_script_call(s, "cur")
                self.w("selectObject: cur")
                self.w(f'appendInfoLine: "@@MC stage {si} series {s.script.name}'
                       f' -> ", selected$("Sound")')
                self.w("mcD = Get total duration")
                self.w(f'appendFileLine: mcStats$, "stage {si} series '
                       f'{s.script.name} -> ", selected$("Sound"), " dur ", mcD')
                self.w("")
            else:
                self.w(f"# --- stage {si}: parallel x{len(members)} ---")
                self.w("selectObject: cur")
                self.w('Copy: "mc_par_src"')
                self.w('parsrc = selected("Sound")')
                ids = []
                for mi, s in enumerate(members, start=1):
                    var = f"p{si}_{mi}"
                    ids.append((var, s))
                    self.w(f"# parallel member {mi}: slot {s.index} "
                           f"({s.script.name})")
                    self.w("selectObject: parsrc")
                    self.w(f'Copy: "mc_p{si}_{mi}_in"')
                    self.w(f'{var} = selected("Sound")')
                    self.w(f"selectObject: {var}")
                    self.run_script_call(s, var)
                    self.w(f"selectObject: {var}")
                    self.w(f'appendInfoLine: "@@MC stage {si} parallel '
                           f'{s.script.name} -> ", selected$("Sound")')
                    self.w("mcD = Get total duration")
                    self.w(f'appendFileLine: mcStats$, "stage {si} parallel '
                           f'{s.script.name} -> ", selected$("Sound"), " dur ", mcD')
                # target format
                for k, (var, _s) in enumerate(ids):
                    self.w(f"selectObject: {var}")
                    self.w(f"d{k} = Get total duration")
                    self.w(f"s{k} = Get sampling frequency")
                    self.w(f"c{k} = Get number of channels")
                self.w("maxDur = d0")
                self.w("srT = s0")
                self.w("minCh = c0")
                self.w("maxCh = c0")
                for k in range(1, len(ids)):
                    self.w(f"if d{k} > maxDur")
                    self.w(f"    maxDur = d{k}")
                    self.w("endif")
                    self.w(f"if s{k} > srT")
                    self.w(f"    srT = s{k}")
                    self.w("endif")
                    self.w(f"if c{k} < minCh")
                    self.w(f"    minCh = c{k}")
                    self.w("endif")
                    self.w(f"if c{k} > maxCh")
                    self.w(f"    maxCh = c{k}")
                    self.w("endif")
                self.w("nchT = maxCh")
                self.w("if minCh <> maxCh")
                self.w("    if maxCh = 2")
                self.w("        nchT = 2")
                self.w("    else")
                self.w("        nchT = 1")
                self.w("    endif")
                self.w("endif")
                self.w('appendFileLine: mcStats$, "parallel target ", nchT,')
                self.w('    ... " ch at ", srT, " Hz (branches beyond stereo '
               'are folded to mono)"')
                for var, _s in ids:
                    self.conform(var, "srT", "nchT")
                self.w('Create Sound from formula: "mc_par_mix", nchT, 0, maxDur,'
                       ' srT, "0"')
                self.w('parmix = selected("Sound")')
                for var, s in ids:
                    wgt = max(0.0, s.mix) / 100.0
                    self.w(f'Formula: "self + {wgt:.6f} * object({var}, x)"')
                self.w("cur = parmix")
                self.w("selectObject: cur")
                self.w(f'appendInfoLine: "@@MC stage {si} mixed ", '
                       f'{len(ids)}, " branches"')
                self.w(f'appendFileLine: mcStats$, "stage {si} mixed '
                       f'{len(ids)} branches"')
                self.w("")

        # ---- global dry/wet ----
        if need_dry:
            wet = o["dry_wet"]
            self.w("# --- global dry/wet ---")
            self.w("selectObject: cur")
            self.w("durW = Get total duration")
            self.w("srW = Get sampling frequency")
            self.w("nchW = Get number of channels")
            self.w('Shift times to: "start time", 0')
            self.conform("dry", "srW", "nchW")
            self.w('Create Sound from formula: "mc_wetdry", nchW, 0, durW, srW, "0"')
            self.w('outmix = selected("Sound")')
            self.w(f'Formula: "self + {wet:.6f} * object(cur, x) + '
                   f'{1.0 - wet:.6f} * object(dry, x)"')
            self.w("cur = outmix")
            self.w("")

        # ---- post: trim / fade / normalize ----
        self.w("selectObject: cur")
        self.w('Shift times to: "start time", 0')
        if o["post"]:
            self.w("# --- trim silence, edge fades, peak normalize ---")
            self.w("durP = Get total duration")
            self.w("pk0 = Get absolute extremum: 0, 0, \"None\"")
            self.w("if durP > 0.2 and pk0 > 0")
            self.w("    Copy: \"mc_trimsrc\"")
            self.w("    trimsrc = selected(\"Sound\")")
            self.w("    To Intensity: 100, 0, \"yes\"")
            self.w("    intId = selected(\"Intensity\")")
            self.w("    nFr = Get number of frames")
            self.w("    peakdB = Get maximum: 0, 0, \"Parabolic\"")
            self.w(f"    thrdB = peakdB - {o['trim_db']:.1f}")
            self.w("    firstFr = 0")
            self.w("    lastFr = 0")
            self.w("    for fr from 1 to nFr")
            self.w("        v = Get value in frame: fr")
            self.w("        if v <> undefined and v > thrdB")
            self.w("            if firstFr = 0")
            self.w("                firstFr = fr")
            self.w("            endif")
            self.w("            lastFr = fr")
            self.w("        endif")
            self.w("    endfor")
            self.w("    if firstFr > 0 and lastFr > firstFr")
            self.w("        t0 = Get time from frame number: firstFr")
            self.w("        t1 = Get time from frame number: lastFr")
            self.w("        if t0 < 0")
            self.w("            t0 = 0")
            self.w("        endif")
            self.w("        if t1 > durP")
            self.w("            t1 = durP")
            self.w("        endif")
            self.w("        selectObject: trimsrc")
            self.w('        Extract part: t0, t1, "rectangular", 1, "no"')
            self.w('        cur = selected("Sound")')
            self.w("        selectObject: cur")
            self.w('        Shift times to: "start time", 0')
            self.w("    endif")
            self.w("    removeObject: intId")
            self.w("endif")
            self.w("selectObject: cur")
            self.w("durP = Get total duration")
            self.w("nchP = Get number of channels")
            self.w(f"fadeS = {o['fade_ms'] / 1000.0:.6f}")
            self.w("if fadeS > durP / 4")
            self.w("    fadeS = durP / 4")
            self.w("endif")
            self.w("if fadeS > 0")
            self.w('    Formula (part): 0, fadeS, 1, nchP, '
                   '"self * (0.5 - 0.5 * cos(pi * x / fadeS))"')
            self.w('    Formula (part): durP - fadeS, durP, 1, nchP, '
                   '"self * (0.5 - 0.5 * cos(pi * (durP - x) / fadeS))"')
            self.w("endif")
            self.w('pk = Get absolute extremum: 0, 0, "None"')
            self.w("if pk > 0")
            self.w(f"    gain = {o['peak_target']:.4f} / pk")
            self.w('    Formula: "self * gain"')
            self.w("endif")
        elif o["ceiling"]:
            self.w("# --- safety ceiling: attenuate only if it would clip ---")
            self.w('pk = Get absolute extremum: 0, 0, "None"')
            self.w(f"if pk > {o['peak_target']:.4f}")
            self.w(f"    gain = {o['peak_target']:.4f} / pk")
            self.w('    Formula: "self * gain"')
            self.w('    appendFileLine: mcStats$, "safety ceiling applied, was ", pk')
            self.w("endif")
        else:
            self.w("# --- no gain stage at all: the chain output is untouched ---")
            self.w('appendFileLine: mcStats$, "no gain stage (ceiling off)"')
        self.w("")

        # ---- single save + report ----
        self.w("selectObject: cur")
        self.w("outDur = Get total duration")
        self.w("outSR = Get sampling frequency")
        self.w("outCh = Get number of channels")
        self.w("outRMS = Get root-mean-square: 0, 0")
        self.w('outPk = Get absolute extremum: 0, 0, "None"')
        # 32-bit integer PCM.  Plain "Save as WAV file" is 16-bit, which put
        # a quantisation step on the way out of every render even when the
        # whole chain ran in memory.
        self.w(f"Save as 32-bit WAV file: {praat_str(self.output_wav)}")
        self.w('appendInfoLine: "@@MC result duration ", outDur')
        self.w('appendInfoLine: "@@MC result samplerate ", outSR')
        self.w('appendInfoLine: "@@MC result channels ", outCh')
        self.w('appendInfoLine: "@@MC result rms ", outRMS')
        self.w('appendInfoLine: "@@MC result peak ", outPk')
        self.w('appendInfoLine: "@@MC ok"')
        self.w('appendFileLine: mcStats$, "duration ", outDur')
        self.w('appendFileLine: mcStats$, "samplerate ", outSR')
        self.w('appendFileLine: mcStats$, "channels ", outCh')
        self.w('appendFileLine: mcStats$, "rms ", outRMS')
        self.w('appendFileLine: mcStats$, "peak ", outPk')
        self.w('appendFileLine: mcStats$, "ok"')
        return "\n".join(self.lines) + "\n"


# ─────────────────────────────────────────────────────────────────────────────
# GUI
# ─────────────────────────────────────────────────────────────────────────────

BG = "#12121e"
PANEL = "#1a1a2e"
FG = "#dcdcf0"
DIM = "#7878a8"
ACCENT = "#5b9bd5"
WARN = "#e0a050"
BAD = "#c06060"


class MatrixApp:
    def __init__(self, cfg):
        import tkinter as tk
        from tkinter import ttk
        self.tk, self.ttk = tk, ttk

        self.cfg = cfg
        self.input_wav = cfg["input_file"]
        self.result_file = cfg.get("result_file", "")
        self.done_file = cfg.get("done_file", "")
        self.error_file = cfg.get("error_file", "")
        self.library_root = cfg["library_root"]
        self.tmpdir = cfg.get("temp_dir") or tempfile.gettempdir()
        self.scratch = os.path.join(self.tmpdir, "mc_audition.wav")
        self.wrapper_path = os.path.join(self.tmpdir, "mc_wrapper.praat")
        self.log_path = os.path.join(self.tmpdir, "mc_last_run.log")
        self.applied = False
        self.last_log = ""
        self._player = ""
        self._proc = None
        self._play_error = ""
        self._rendering = False
        self._render_proc = None
        self._render_thread = None
        self._render_result = None
        self._cancelled = False

        self.runner = PraatRunner(cfg.get("praat_exe", ""))
        self.catalog = []
        self.slots = [Slot(i + 1) for i in range(N_SLOTS)]
        self.active_slot = 0

        self.root = tk.Tk()
        self.root.title(f"AudioTools — Matrix Chain Host {APP_VERSION}")
        self.root.configure(bg=BG)
        self._build_style()
        self._build_ui()
        self.rescan(initial=True)
        self.wet_var.trace_add("write", lambda *a: self.update_flow())
        self.post_var.trace_add("write", lambda *a: self.update_flow())
        self.refresh_rows()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ---------- styling ----------
    def _build_style(self):
        st = self.ttk.Style()
        try:
            st.theme_use("clam")
        except Exception:
            pass
        st.configure(".", background=BG, foreground=FG, fieldbackground=PANEL)
        st.configure("TFrame", background=BG)
        st.configure("Panel.TFrame", background=PANEL)
        st.configure("TLabel", background=BG, foreground=FG)
        st.configure("Dim.TLabel", background=BG, foreground=DIM)
        st.configure("Warn.TLabel", background=BG, foreground=WARN)
        st.configure("Bad.TLabel", background=BG, foreground=BAD)
        st.configure("TButton", background=PANEL, foreground=FG)
        st.map("TButton",
               background=[("active", "#26314a"), ("pressed", ACCENT)],
               foreground=[("disabled", DIM)])

        # A readonly ttk Combobox draws its text with the SELECTION colours
        # while focused and with `foreground` otherwise.  Setting only
        # fieldbackground leaves every unfocused box grey-on-grey, which reads
        # as "the selection was lost" when it is merely invisible.
        st.configure("TCombobox", fieldbackground=PANEL, background=PANEL,
                     foreground=FG, arrowcolor=FG, bordercolor="#2a2a4a",
                     lightcolor=PANEL, darkcolor=PANEL,
                     selectbackground=PANEL, selectforeground=FG)
        st.map("TCombobox",
               fieldbackground=[("readonly", PANEL), ("disabled", BG)],
               background=[("readonly", PANEL), ("active", "#26314a")],
               foreground=[("readonly", FG), ("disabled", DIM)],
               selectbackground=[("readonly", PANEL), ("focus", PANEL)],
               selectforeground=[("readonly", FG), ("focus", FG)],
               arrowcolor=[("disabled", DIM)])

        st.configure("TEntry", fieldbackground=PANEL, foreground=FG,
                     insertcolor=FG, bordercolor="#2a2a4a",
                     lightcolor=PANEL, darkcolor=PANEL)
        st.map("TEntry", foreground=[("disabled", DIM)],
               fieldbackground=[("disabled", BG)])
        st.configure("TSpinbox", fieldbackground=PANEL, foreground=FG,
                     arrowcolor=FG, insertcolor=FG, bordercolor="#2a2a4a",
                     lightcolor=PANEL, darkcolor=PANEL)
        st.map("TSpinbox",
               fieldbackground=[("disabled", BG)],
               foreground=[("disabled", "#4a4a68")],
               arrowcolor=[("disabled", "#4a4a68")])

        st.configure("TCheckbutton", background=BG, foreground=FG,
                     indicatorcolor=PANEL, focuscolor=BG)
        st.map("TCheckbutton",
               background=[("active", BG)],
               indicatorcolor=[("selected", ACCENT), ("!selected", PANEL),
                               ("disabled", "#20202e")],
               foreground=[("disabled", DIM)])
        st.configure("TRadiobutton", background=BG, foreground=FG,
                     indicatorcolor=PANEL, focuscolor=BG)
        st.map("TRadiobutton", background=[("active", BG)],
               indicatorcolor=[("selected", ACCENT), ("!selected", PANEL)])
        st.configure("TScale", background=BG, troughcolor=PANEL)
        st.configure("TProgressbar", background=ACCENT, troughcolor=PANEL,
                     bordercolor=PANEL, lightcolor=ACCENT, darkcolor=ACCENT)
        st.configure("Horizontal.TProgressbar", background=ACCENT,
                     troughcolor=PANEL, bordercolor=PANEL,
                     lightcolor=ACCENT, darkcolor=ACCENT)
        st.configure("Vertical.TScrollbar", background=PANEL,
                     troughcolor=BG, arrowcolor=FG, bordercolor=BG)

        # The dropdown list is a plain Tk listbox: it takes its colours from
        # the option database, not from the ttk style.
        self.root.option_add("*TCombobox*Listbox.background", PANEL)
        self.root.option_add("*TCombobox*Listbox.foreground", FG)
        self.root.option_add("*TCombobox*Listbox.selectBackground", ACCENT)
        self.root.option_add("*TCombobox*Listbox.selectForeground", "#101018")
        self.root.option_add("*TCombobox*Listbox.font", "TkDefaultFont")

    # ---------- layout ----------
    def _build_ui(self):
        tk, ttk = self.tk, self.ttk
        root = self.root

        top = ttk.Frame(root, padding=(10, 8, 10, 4))
        top.grid(row=0, column=0, sticky="ew")
        self.src_var = tk.StringVar(value=os.path.basename(self.input_wav))
        ttk.Label(top, text="Source:").grid(row=0, column=0, sticky="w")
        ttk.Label(top, textvariable=self.src_var, style="Dim.TLabel").grid(
            row=0, column=1, sticky="w", padx=(4, 16))
        self.praat_var = tk.StringVar(value=self._praat_label())
        ttk.Label(top, textvariable=self.praat_var, style="Dim.TLabel").grid(
            row=0, column=2, sticky="w", padx=(0, 16))
        ttk.Button(top, text="Rescan", width=8,
                   command=self.rescan).grid(row=0, column=3)
        ttk.Button(top, text="Praat…", width=8,
                   command=self.set_praat).grid(row=0, column=4, padx=4)
        ttk.Button(top, text="Test Praat", width=10,
                   command=self.test_praat).grid(row=0, column=5, padx=4)
        ttk.Button(top, text="Log", width=6,
                   command=self.show_log).grid(row=0, column=6)

        # ---- slot rows ----
        slots = ttk.Frame(root, padding=(10, 4))
        slots.grid(row=1, column=0, sticky="ew")
        hdr = ["", "Slot", "Category", "Script", "Mode", "Branch %", "Status"]
        for c, h in enumerate(hdr):
            ttk.Label(slots, text=h, style="Dim.TLabel").grid(
                row=0, column=c, sticky="w", padx=3)
        self.sel_var = tk.IntVar(value=0)
        self.cat_vars, self.scr_vars, self.mode_vars, self.mix_vars = [], [], [], []
        self.cat_boxes, self.scr_boxes, self.status_labels = [], [], []
        self.row_marks, self.mix_boxes = [], []
        for i in range(N_SLOTS):
            r = i + 1
            ttk.Radiobutton(slots, variable=self.sel_var, value=i,
                            command=self.on_slot_focus).grid(row=r, column=0)
            mark = tk.Label(slots, text=f" {i + 1} ", bg=PANEL, fg=DIM,
                            font=("TkDefaultFont", 10, "bold"), width=3)
            mark.grid(row=r, column=1, sticky="ns", pady=1)
            mark.bind("<Button-1>", lambda e, i=i: (self.sel_var.set(i),
                                                    self.on_slot_focus()))
            cv, sv = tk.StringVar(), tk.StringVar()
            mv = tk.StringVar(value="Off")
            xv = tk.DoubleVar(value=100.0)
            cb = ttk.Combobox(slots, textvariable=cv, width=22, state="readonly")
            cb.grid(row=r, column=2, padx=3, pady=2)
            cb.bind("<<ComboboxSelected>>",
                    lambda e, i=i: self.on_category(i))
            sb = ttk.Combobox(slots, textvariable=sv, width=42, state="readonly")
            sb.grid(row=r, column=3, padx=3)
            sb.bind("<<ComboboxSelected>>", lambda e, i=i: self.on_script(i))
            mb = ttk.Combobox(slots, textvariable=mv, width=9, state="readonly",
                              values=["Off", "Series", "Parallel"])
            mb.grid(row=r, column=4, padx=3)
            mb.bind("<<ComboboxSelected>>", lambda e, i=i: self.on_mode(i))
            sp = ttk.Spinbox(slots, textvariable=xv, from_=0, to=200,
                             increment=5, width=6)
            sp.grid(row=r, column=5, padx=3)
            self.mix_boxes.append(sp)
            lab = ttk.Label(slots, text="", style="Dim.TLabel")
            lab.grid(row=r, column=6, sticky="w", padx=6)
            self.row_marks.append(mark)
            xv.trace_add("write", lambda *a, i=i: self.on_mix(i))
            self.cat_vars.append(cv); self.scr_vars.append(sv)
            self.mode_vars.append(mv); self.mix_vars.append(xv)
            self.cat_boxes.append(cb); self.scr_boxes.append(sb)
            self.status_labels.append(lab)

        # ---- signal-flow preview ----
        self.flow_var = tk.StringVar(value="input → (nothing active) → output")
        flow = tk.Label(root, textvariable=self.flow_var, bg=PANEL, fg=ACCENT,
                        anchor="w", padx=8, pady=5, justify="left",
                        font=("TkDefaultFont", 10, "bold"))
        flow.grid(row=2, column=0, sticky="ew", padx=10, pady=(2, 4))

        # ---- parameter panel ----
        pf = ttk.Frame(root, padding=(10, 6))
        pf.grid(row=3, column=0, sticky="nsew")
        root.rowconfigure(3, weight=1)
        root.columnconfigure(0, weight=1)
        self.param_title = tk.StringVar(value="Slot 1 — no script")
        head = ttk.Frame(pf)
        head.grid(row=0, column=0, sticky="ew")
        ttk.Label(head, textvariable=self.param_title).grid(row=0, column=0,
                                                            sticky="w")
        ttk.Button(head, text="Reset to defaults", width=16,
                   command=self.reset_params).grid(row=0, column=1, padx=10)
        self.canvas = tk.Canvas(pf, bg=BG, highlightthickness=0, height=260)
        self.canvas.grid(row=1, column=0, sticky="nsew")
        pf.rowconfigure(1, weight=1)
        pf.columnconfigure(0, weight=1)
        vs = ttk.Scrollbar(pf, orient="vertical", command=self.canvas.yview)
        vs.grid(row=1, column=1, sticky="ns")
        self.canvas.configure(yscrollcommand=vs.set)
        self.pframe = ttk.Frame(self.canvas, padding=(4, 4))
        self.canvas.create_window((0, 0), window=self.pframe, anchor="nw")
        self.pframe.bind("<Configure>", lambda e: self.canvas.configure(
            scrollregion=self.canvas.bbox("all")))

        # ---- globals ----
        g = ttk.Frame(root, padding=(10, 4))
        g.grid(row=4, column=0, sticky="ew")
        self.wet_var = tk.DoubleVar(value=100.0)
        ttk.Label(g, text="Dry/Wet %").grid(row=0, column=0, sticky="w")
        ttk.Scale(g, from_=0, to=100, variable=self.wet_var, length=170,
                  orient="horizontal").grid(row=0, column=1, padx=4)
        self.wet_lab = ttk.Label(g, text="100", style="Dim.TLabel", width=4)
        self.wet_lab.grid(row=0, column=2)
        self.wet_var.trace_add("write", lambda *a: self.wet_lab.configure(
            text=f"{self.wet_var.get():.0f}"))
        self.post_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(g, text="Trim / fade / normalize", variable=self.post_var
                        ).grid(row=0, column=3, padx=12)
        self.play_off_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(g, text="Force Play off", variable=self.play_off_var
                        ).grid(row=0, column=4, padx=6)
        self.draw_off_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(g, text="Force Draw off", variable=self.draw_off_var
                        ).grid(row=0, column=5, padx=6)
        self.ceiling_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(g, text="Safety ceiling", variable=self.ceiling_var
                        ).grid(row=0, column=9, padx=6)
        self.bridges_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(g, text="Include Python bridges (slower)",
                        variable=self.bridges_var,
                        command=self.rescan).grid(row=0, column=8, padx=(12, 0))
        ttk.Label(g, text="Timeout s").grid(row=0, column=6, padx=(12, 2))
        self.timeout_var = tk.IntVar(value=int(self.cfg.get("timeout", 180)))
        ttk.Spinbox(g, textvariable=self.timeout_var, from_=10, to=3600,
                    increment=10, width=6).grid(row=0, column=7)

        # ---- buttons ----
        b = ttk.Frame(root, padding=(10, 6))
        b.grid(row=5, column=0, sticky="ew")
        self.btn_audition = ttk.Button(b, text="▶  Audition", width=14,
                                       command=self.on_audition)
        self.btn_audition.grid(row=0, column=0)
        self.btn_stop = ttk.Button(b, text="■  Stop", width=9,
                                   command=self.on_stop)
        self.btn_stop.grid(row=0, column=1, padx=4)
        self.btn_apply = ttk.Button(b, text="Apply → Praat", width=15,
                                    command=self.on_apply)
        self.btn_apply.grid(row=0, column=2, padx=14)
        ttk.Button(b, text="Save chain…", width=12,
                   command=self.save_chain).grid(row=0, column=3)
        ttk.Button(b, text="Load chain…", width=12,
                   command=self.load_chain).grid(row=0, column=4, padx=4)
        ttk.Button(b, text="Close", width=8,
                   command=self._on_close).grid(row=0, column=5, padx=14)

        sbar = ttk.Frame(root, padding=(10, 2, 10, 8))
        sbar.grid(row=6, column=0, sticky="ew")
        self.progress = ttk.Progressbar(sbar, mode="indeterminate", length=150)
        self.progress.grid(row=0, column=0, padx=(0, 10))
        self.progress.grid_remove()
        self.status = tk.StringVar(value="Ready.")
        ttk.Label(sbar, textvariable=self.status,
                  style="Dim.TLabel").grid(row=0, column=1, sticky="w")

    def _praat_label(self):
        if self.runner.exe:
            return f"Praat {self.runner.version_str}: {self.runner.exe}"
        return f"Praat NOT FOUND — {self.runner.error}"

    # ---------- catalog ----------
    def rescan(self, initial=False):
        self.status.set("Scanning library…")
        self.root.update_idletasks()
        want_bridges = bool(getattr(self, "bridges_var", None)
                            and self.bridges_var.get())
        self.catalog = scan_library(self.library_root, include_py=want_bridges)
        self.eligible = [s for s in self.catalog
                         if s.eligible and s.input_requirement in ("one", "none")
                         and (want_bridges or not s.is_bridge)]
        cats = sorted({s.category or "(root)" for s in self.eligible})
        for i in range(N_SLOTS):
            self.cat_boxes[i].configure(values=cats)
        n_gen = sum(1 for s in self.eligible if s.slot1_only)
        n_py = sum(1 for s in self.eligible if s.is_bridge)
        extra = f", {n_py} python bridges" if n_py else ""
        self.status.set(
            f"{len(self.eligible)} of {len(self.catalog)} scripts usable "
            f"({n_gen} generators, slot 1 only{extra}) — "
            f"{len(self.catalog) - len(self.eligible)} excluded, see Log")
        self.last_log = self._catalog_report()
        if initial and self.cfg.get("last_chain"):
            try:
                chain, self.cfg["last_chain"] = self.cfg["last_chain"], None
                self.apply_chain(chain)
            except Exception:
                pass

    def _catalog_report(self):
        from praat_script_inspector import report
        return report(self.catalog, verbose=True)

    def scripts_in(self, category, slot_index=0):
        """Scripts offerable in this row.

        A generator ignores its input, so in slot 2-4 it would silently
        discard everything the chain built before it.  Filtering it out of
        the picker is not enough on its own -- render() enforces the same
        rule, so a saved chain or a hand-edited JSON cannot slip past.
        """
        out = [s for s in self.eligible
               if (s.category or "(root)") == category]
        if slot_index > 0:
            out = [s for s in out if not s.slot1_only]
        return out

    def on_category(self, i):
        cat = self.cat_vars[i].get()
        names = [s.name for s in self.scripts_in(cat, i)]
        self.scr_boxes[i].configure(values=names)
        self.scr_vars[i].set("")
        self.slots[i].script = None
        self.status_labels[i].configure(text="")
        self.refresh_rows()
        if self.sel_var.get() == i:
            self.render_params()

    def on_script(self, i):
        cat, name = self.cat_vars[i].get(), self.scr_vars[i].get()
        info = next((s for s in self.scripts_in(cat, i) if s.name == name), None)
        self.slots[i].script = info
        self.slots[i].defaults()
        if self.mode_vars[i].get() == "Off":
            self.mode_vars[i].set("Series")
            self.slots[i].mode = "Series"
        self.update_slot_status(i)
        self.sel_var.set(i)
        self.render_params()
        self.refresh_rows()

    def on_mode(self, i):
        self.slots[i].mode = self.mode_vars[i].get()
        self.update_slot_status(i)
        self.refresh_rows()

    def update_slot_status(self, i):
        s = self.slots[i]
        if not s.script:
            self.status_labels[i].configure(text="", style="Dim.TLabel")
            return
        mode = self.mode_vars[i].get()
        head = ("OFF" if mode == "Off" else
                ("SERIES" if mode == "Series"
                 else f"BRANCH {self.slots[i].mix:.0f}%"))
        bits = [head]
        if s.script.is_bridge:
            bits.append("PY")
        bits.append(f"{len(s.script.params)} params")
        style = "Dim.TLabel"
        if s.script.slot1_only:
            bits.append("generator: ignores its input")
            style = "Warn.TLabel"
        if s.script.warnings:
            bits.append(s.script.warnings[0])
            style = "Warn.TLabel"
        self.status_labels[i].configure(text="  •  ".join(bits), style=style)

    def on_mix(self, i):
        try:
            self.slots[i].mix = float(self.mix_vars[i].get())
        except Exception:
            return
        self.update_slot_status(i)
        self.update_flow()

    def on_slot_focus(self):
        self.render_params()
        self.refresh_rows()

    def refresh_rows(self):
        """Make the focused slot and the active slots visible at a glance."""
        focus = self.sel_var.get()
        for i, mark in enumerate(self.row_marks):
            slot = self.slots[i]
            mode = self.mode_vars[i].get()
            if i == focus:
                mark.configure(bg=ACCENT, fg="#101018")
            elif slot.script and mode in ("Series", "Parallel"):
                mark.configure(bg="#26314a", fg=FG)
            else:
                mark.configure(bg=PANEL, fg=DIM)
            state = "normal" if mode == "Parallel" else "disabled"
            try:
                self.mix_boxes[i].configure(state=state)
            except Exception:
                pass
        self.update_flow()

    def update_flow(self):
        """One line showing the signal path exactly as the wrapper will build it."""
        for i, s in enumerate(self.slots):
            s.mode = self.mode_vars[i].get()
        stages = chain_stages(self.slots)
        if not stages:
            self.flow_var.set("input → (no active slot) → output")
            return
        parts = []
        for kind, members in stages:
            if kind == "series":
                m = members[0]
                parts.append(f"[{m.index}: {m.script.name}]")
            else:
                inner = "  +  ".join(
                    f"[{m.index}: {m.script.name} {m.mix:.0f}%]"
                    for m in members)
                parts.append(f"( {inner} )")
        tail = []
        wet = float(self.wet_var.get())
        if wet < 99.5:
            tail.append(f"wet {wet:.0f}%")
        if self.post_var.get():
            tail.append("trim/fade/normalize")
        line = "input → " + " → ".join(parts)
        if tail:
            line += " → " + " → ".join(tail)
        self.flow_var.set(line + " → output")

    # ---------- parameter panel ----------
    def render_params(self):
        tk, ttk = self.tk, self.ttk
        for w in self.pframe.winfo_children():
            w.destroy()
        i = self.sel_var.get()
        self.active_slot = i
        slot = self.slots[i]
        if not slot.script:
            self.param_title.set(f"Slot {i + 1} — no script selected")
            return
        info = slot.script
        self.param_title.set(
            f"Slot {i + 1} — {info.name}   [{info.form_syntax} form, "
            f"{len(info.params)} parameters]")
        r = 0
        for w in info.warnings:
            ttk.Label(self.pframe, text="⚠  " + w, style="Warn.TLabel"
                      ).grid(row=r, column=0, columnspan=3, sticky="w")
            r += 1
        if not info.params:
            ttk.Label(self.pframe, text="This script takes no parameters.",
                      style="Dim.TLabel").grid(row=r, column=0, sticky="w")
            return
        self.param_widgets = {}
        for p in info.params:
            forced = ((p.is_play and self.play_off_var.get()) or
                      (p.is_draw and p.ptype == "boolean"
                       and self.draw_off_var.get()))
            label = p.label or p.var
            ttk.Label(self.pframe, text=label, width=34,
                      style="Dim.TLabel" if forced else "TLabel"
                      ).grid(row=r, column=0, sticky="w", pady=1)
            var = tk.StringVar(value=str(slot.values.get(p.var, p.default)))
            if p.ptype == "boolean":
                # A forced parameter is sent as 0, so it must not be displayed
                # ticked: a greyed-out tick reads as "on but locked".
                bv = tk.BooleanVar(value=False if forced else truthy(var.get()))
                cbx = ttk.Checkbutton(self.pframe, variable=bv)
                cbx.grid(row=r, column=1, sticky="w")
                if forced:
                    cbx.state(["disabled"])
                self.param_widgets[p.var] = ("bool", bv)
            elif p.ptype in MENU_TYPES:
                cb = ttk.Combobox(self.pframe, textvariable=var, width=30,
                                  state="readonly", values=p.options)
                cb.grid(row=r, column=1, sticky="w")
                self.param_widgets[p.var] = ("str", var)
            else:
                e = ttk.Entry(self.pframe, textvariable=var, width=22)
                e.grid(row=r, column=1, sticky="w")
                self.param_widgets[p.var] = ("str", var)
            hint = p.ptype
            if p.minimum is not None:
                hint += f"  [{p.minimum:g} … {p.maximum:g}]"
            if forced:
                hint += "  — forced off for chain rendering"
            ttk.Label(self.pframe, text=hint, style="Dim.TLabel"
                      ).grid(row=r, column=2, sticky="w", padx=8)
            r += 1

    def harvest_params(self):
        """Copy widget values back into the active slot."""
        slot = self.slots[self.active_slot]
        if not slot.script or not hasattr(self, "param_widgets"):
            return
        for var, (kind, tkvar) in self.param_widgets.items():
            if kind == "bool":
                slot.values[var] = "1" if tkvar.get() else "0"
            else:
                slot.values[var] = tkvar.get()

    def reset_params(self):
        self.slots[self.active_slot].defaults()
        self.render_params()

    # ---------- chain presets ----------
    def chain_state(self):
        self.harvest_params()
        out = []
        for i, s in enumerate(self.slots):
            out.append({"category": self.cat_vars[i].get(),
                        "script": s.script.name if s.script else "",
                        "mode": self.mode_vars[i].get(),
                        "mix": float(self.mix_vars[i].get()),
                        "values": dict(s.values)})
        return {"slots": out, "wet": float(self.wet_var.get()),
                "post": bool(self.post_var.get()),
                "ceiling": bool(self.ceiling_var.get()),
                "include_bridges": bool(self.bridges_var.get())}

    def apply_chain(self, state):
        # A saved chain containing a bridge is unloadable while bridges are
        # filtered out of the catalog, so turn them on (and rescan) first.
        wants = state.get("include_bridges")
        if wants is None:
            wants = any((sd.get("category") or "").lower().startswith("py")
                        for sd in state.get("slots", []))
        if wants and not self.bridges_var.get():
            self.bridges_var.set(True)
            self.rescan()
        for i, sd in enumerate(state.get("slots", [])[:N_SLOTS]):
            if not sd.get("script"):
                continue
            self.cat_vars[i].set(sd.get("category", ""))
            self.on_category(i)
            self.scr_vars[i].set(sd["script"])
            self.on_script(i)
            self.mode_vars[i].set(sd.get("mode", "Off"))
            self.on_mode(i)
            self.mix_vars[i].set(sd.get("mix", 100.0))
            if self.slots[i].script:
                self.slots[i].values.update(sd.get("values", {}))
        self.wet_var.set(state.get("wet", 100.0))
        self.post_var.set(state.get("post", False))
        self.ceiling_var.set(state.get("ceiling", True))
        self.render_params()
        self.refresh_rows()

    def save_chain(self):
        from tkinter import filedialog
        p = filedialog.asksaveasfilename(defaultextension=".json",
                                         initialdir=self.tmpdir,
                                         title="Save chain")
        if not p:
            return
        with open(p, "w", encoding="utf-8") as f:
            json.dump(self.chain_state(), f, indent=2)
        self.status.set(f"Chain saved to {p}")

    def load_chain(self):
        from tkinter import filedialog
        p = filedialog.askopenfilename(filetypes=[("JSON", "*.json")],
                                       initialdir=self.tmpdir,
                                       title="Load chain")
        if not p:
            return
        with open(p, "r", encoding="utf-8") as f:
            self.apply_chain(json.load(f))
        self.status.set(f"Chain loaded from {p}")

    # ---------- rendering ----------
    def opts(self):
        return {"dry_wet": float(self.wet_var.get()) / 100.0,
                "post": bool(self.post_var.get()),
                "ceiling": bool(self.ceiling_var.get()),
                "force_play_off": bool(self.play_off_var.get()),
                "force_draw_off": bool(self.draw_off_var.get()),
                "trim_db": 60.0,
                "fade_ms": 20.0,
                "peak_target": 0.98 if self.post_var.get() else 0.99}

    def render(self, out_wav, done_cb):
        """Build one wrapper, run it in a worker thread, poll for progress.

        subprocess.run() on the main thread freezes Tk for the whole render,
        so nothing can animate and the window greys out.  The Praat process
        now runs in a thread while the GUI polls the wrapper's own progress
        file, which reports the slot actually being executed rather than a
        meaningless spinner.
        """
        self._stop_playback()      # a file still playing cannot be overwritten
        self.harvest_params()
        for i, s in enumerate(self.slots):
            s.mode = self.mode_vars[i].get()
            try:
                s.mix = float(self.mix_vars[i].get())
            except Exception:
                s.mix = 100.0
        active = [s for s in self.slots if s.active]
        if not active:
            done_cb(False, "No active slots — set at least one to Series or "
                           "Parallel.")
            return
        if not self.runner.exe:
            done_cb(False, f"Praat not found. {self.runner.error}")
            return
        for pos, sl in enumerate(active):
            if sl.script.slot1_only and (pos > 0 or sl.mode != "Series"):
                done_cb(False, f"Slot {sl.index} ({sl.script.name}) is a "
                               f"generator: it ignores its input, so it can "
                               f"only be the FIRST active slot, in Series "
                               f"mode. Move it or switch it off.")
                return
        if self._rendering:
            done_cb(False, "A render is already running.")
            return

        stats_path = os.path.join(self.tmpdir, "mc_stats.txt")
        for stale in (stats_path, out_wav):
            if os.path.exists(stale):
                try:
                    os.remove(stale)
                except OSError:
                    pass
        wrapper = WrapperBuilder(self.slots, self.input_wav, out_wav,
                                 self.opts(), stats_path).build()
        with open(self.wrapper_path, "w", encoding="utf-8") as f:
            f.write(wrapper)

        self._rendering = True
        self._render_result = None
        self._set_busy(True)
        timeout = self.timeout_var.get()
        n_active = len(active)

        try:
            proc, argv = self.runner.popen(self.wrapper_path)
        except Exception as exc:                                # noqa: BLE001
            self._rendering = False
            self._set_busy(False)
            done_cb(False, f"Could not launch Praat: {exc}")
            return
        self._render_proc = proc

        def worker():
            try:
                out, err = proc.communicate(timeout=timeout)
                self._render_result = (proc.returncode,
                                       decode_praat_output(out),
                                       decode_praat_output(err), argv)
            except subprocess.TimeoutExpired:
                proc.kill()
                out, err = proc.communicate()
                self._render_result = (-1, decode_praat_output(out),
                                       f"Timed out after {timeout} s "
                                       f"(raise Timeout s and retry)", argv)
            except Exception as exc:                            # noqa: BLE001
                self._render_result = (-1, "", str(exc), argv)

        self._render_thread = threading.Thread(target=worker, daemon=True)
        self._render_thread.start()
        self.root.after(120, self._poll_render, out_wav, stats_path, wrapper,
                        time.time(), n_active, done_cb)

    def _poll_render(self, out_wav, stats_path, wrapper, t0, n_active, done_cb):
        elapsed = time.time() - t0
        if self._render_result is None:
            step = ""
            try:
                with open(stats_path, "r", encoding="utf-8",
                          errors="replace") as f:
                    lines = [l.strip() for l in f if l.strip()]
                if lines:
                    last = lines[-1]
                    done = sum(1 for l in lines if l.startswith("stage"))
                    if last.startswith("calling "):
                        step = f"{last[len('calling '):]}  ({done + 1}/{n_active})"
                    elif last == "reading input":
                        step = "reading the input WAV"
                    else:
                        step = f"{last}  ({done}/{n_active})"
            except OSError:
                pass
            if not step:
                step = "starting Praat"
            self.status.set(f"⏳  {step}   —   {elapsed:4.1f} s"
                            f"{'   (press Stop to cancel)' if elapsed > 3 else ''}")
            self.root.after(150, self._poll_render, out_wav, stats_path,
                            wrapper, t0, n_active, done_cb)
            return

        code, out, err, argv = self._render_result
        self._rendering = False
        self._render_proc = None
        self._set_busy(False)

        stats_text = ""
        if os.path.exists(stats_path):
            try:
                with open(stats_path, "r", encoding="utf-8",
                          errors="replace") as f:
                    stats_text = f.read()
            except OSError:
                pass
        self.last_log = ("COMMAND: " + " ".join(argv) + "\n\n"
                         f"elapsed: {elapsed:.1f} s\n\n"
                         "--- progress file ---\n" + (stats_text or "(none)") +
                         "\n--- stdout ---\n" + out +
                         "\n--- stderr ---\n" + err +
                         "\n\n--- wrapper ---\n" + wrapper)
        try:
            with open(self.log_path, "w", encoding="utf-8") as f:
                f.write(self.last_log)
        except OSError:
            pass

        if self._cancelled:
            self._cancelled = False
            done_cb(False, f"Cancelled after {elapsed:.1f} s.")
            return

        if code != 0 or not os.path.exists(out_wav):
            # Windows Praat is a GUI binary and often returns nothing on
            # stdout/stderr, so the progress file is the primary evidence.
            steps = [l.strip() for l in stats_text.splitlines() if l.strip()]
            last = steps[-1] if steps else ""
            mcerr = [l for l in steps if l.startswith("MC-ERROR")]
            if mcerr:
                # the wrapper's own contract check fired: report it verbatim
                done_cb(False, mcerr[-1].replace("MC-ERROR ", "") +
                        "   [see Log]")
                return
            if not steps:
                where = ("Praat produced no progress file at all — the run "
                         "never reached the first line")
            elif last.startswith("calling "):
                where = f"died inside {last[len('calling '):]}"
            elif last == "reading input":
                where = "could not read the exported input WAV"
            elif last == "start":
                where = "died before reading the input WAV"
            else:
                where = f"got as far as: {last}"
            tail = (err.strip() or out.strip() or "").splitlines()
            tail = " / ".join(tail[-3:])[:220]
            msg = f"Praat failed (exit {code}) — {where}"
            argerr = re.search(r"Found (\d+) arguments? but expected (\w+)",
                               err + out)
            if argerr:
                name = last[len("calling "):] if last.startswith("calling ") \
                    else "that script"
                msg = (f"Argument-count mismatch in {name}: the inspector read "
                       f"{argerr.group(1)} form fields, Praat expected "
                       f"{argerr.group(2)}. Press Rescan; if it persists that "
                       f"form uses a field this parser still mis-reads.")
            elif tail:
                msg += f": {tail}"
            done_cb(False, msg + "   [see Log]")
            return
        done_cb(True, self._summary(stats_text or out) +
                f"   —   rendered in {elapsed:.1f} s")

    def _set_busy(self, busy):
        for b in (self.btn_audition, self.btn_apply):
            try:
                b.state(["disabled"] if busy else ["!disabled"])
            except Exception:
                pass
        if busy:
            self.progress.grid()
            self.progress.start(14)
        else:
            self.progress.stop()
            self.progress.grid_remove()

    @staticmethod
    def _summary(text):
        vals = {}
        for m in re.finditer(r"@@MC result (\w+) ([-\d.eE]+)", text):
            vals[m.group(1)] = m.group(2)
        for m in re.finditer(r"^(duration|samplerate|channels|rms|peak) "
                             r"([-\d.eE]+)", text, re.M):
            vals.setdefault(m.group(1), m.group(2))
        if not vals:
            return "Rendered."
        try:
            d = float(vals.get("duration", 0))
            rms = float(vals.get("rms", 0))
            pk = float(vals.get("peak", 0))
            msg = (f"{d:.3f} s  •  {vals.get('channels', '?')} ch  •  "
                   f"{float(vals.get('samplerate', 0)):.0f} Hz  •  "
                   f"peak {pk:.3f}  •  RMS {rms:.5f}")
            if rms < 0.0001:
                msg += "   ⚠ OUTPUT IS SILENT"
            return msg
        except ValueError:
            return "Rendered."

    def on_audition(self):
        def done(ok, msg):
            if not ok:
                self.status.set("✖ " + msg)
                return
            self.status.set("▶ " + msg)
            self.play(self.scratch)
        self.render(self.scratch, done)

    @staticmethod
    def _downmix_to_stereo(data):
        """Fold N>2 channels to stereo: odd channels left, even channels right.

        Averaging within each group keeps the level sane without clipping and
        preserves some sense of the layout for the ring/array orders the
        AudioTools multichannel scripts produce.
        """
        import numpy as np
        n = data.shape[1]
        left = data[:, 0::2].mean(axis=1)
        right = data[:, 1::2].mean(axis=1) if n > 1 else left
        return np.stack([left, right], axis=1).astype("float32")

    def _pcm16_file(self, data, sr, name="mc_audition_play.wav"):
        """Write a 16-bit PCM file for players that cannot take an array."""
        import wave
        import numpy as np
        out = os.path.join(self.tmpdir, name)
        pcm = (np.clip(data, -1.0, 1.0) * 32767.0).astype("<i2")
        with wave.open(out, "wb") as w:
            w.setnchannels(int(pcm.shape[1]))
            w.setsampwidth(2)
            w.setframerate(int(sr))
            w.writeframes(pcm.tobytes())
        return out

    def play(self, path):
        """Play the scratch render.

        Anything wider than stereo is downmixed FOR PLAYBACK ONLY.  Handing a
        6- or 8-channel array to the default output device depends entirely on
        the interface and its channel mapping, and winsound cannot be trusted
        with arbitrary multichannel WAV at all -- so audition would be a
        lottery.  The rendered file and Apply keep every channel.
        """
        self._stop_playback()
        data = sr = None
        note = ""
        try:
            data, sr = self._read_wav(path)
            nch = data.shape[1]
            if nch > 2:
                data = self._downmix_to_stereo(data)
                note = (f"   —   Audition: {nch}-channel render downmixed to "
                        f"stereo for playback; Apply preserves all {nch} "
                        f"channels.")
        except Exception:                                   # noqa: BLE001
            data = None

        if note:
            self.status.set(self.status.get() + note)

        # 1. sounddevice
        if data is not None:
            try:
                import sounddevice as sd
                sd.play(data, samplerate=sr, blocking=False)
                self._player = "sounddevice"
                return
            except Exception as exc:                        # noqa: BLE001
                self._play_error = str(exc)

        # 2. winsound (Windows, stdlib).  It goes through the old multimedia
        # API, so it always gets a plain 16-bit stereo/mono file.
        if sys.platform.startswith("win"):
            try:
                import winsound
                target = (self._pcm16_file(data, sr) if data is not None
                          else path)
                winsound.PlaySound(target, winsound.SND_FILENAME |
                                   winsound.SND_ASYNC)
                self._player = "winsound"
                return
            except Exception as exc:                        # noqa: BLE001
                self.status.set(self.status.get() +
                                f"   (winsound failed: {exc})")

        # 3. an external player
        target = path
        if data is not None:
            try:
                target = self._pcm16_file(data, sr)
            except Exception:                               # noqa: BLE001
                target = path
        cmds = ([["afplay", target]] if sys.platform == "darwin"
                else [["aplay", "-q", target], ["paplay", target]])
        for cmd in cmds:
            exe = shutil.which(cmd[0])
            if not exe:
                continue
            try:
                self._proc = subprocess.Popen([exe] + cmd[1:],
                                              stdout=subprocess.DEVNULL,
                                              stderr=subprocess.DEVNULL)
                self._player = cmd[0]
                return
            except Exception:                               # noqa: BLE001
                continue
        self.status.set(self.status.get() +
                        "   (rendered, but no way to play it: "
                        "pip install sounddevice)")

    def _stop_playback(self):
        if getattr(self, "_proc", None):
            try:
                self._proc.terminate()
            except Exception:
                pass
            self._proc = None
        if getattr(self, "_player", "") == "winsound":
            try:
                import winsound
                winsound.PlaySound(None, winsound.SND_PURGE)
            except Exception:
                pass
        try:
            import sounddevice as sd
            sd.stop()
        except Exception:
            pass
        self._player = ""

    @staticmethod
    def _read_wav(path):
        """Return (frames, samplerate) as float32, shape (n, channels)."""
        try:
            import soundfile as sf
            data, sr = sf.read(path, dtype="float32", always_2d=True)
            return data, sr
        except Exception:                                   # noqa: BLE001
            pass
        return MatrixApp._read_wav_riff(path)

    @staticmethod
    def _read_wav_riff(path):
        """Minimal RIFF reader: PCM 8/16/24/32 and IEEE float 32/64.

        Python's wave module rejects float WAVs outright, which a Python
        bridge backend can easily produce.
        """
        import struct
        import numpy as np
        with open(path, "rb") as f:
            raw = f.read()
        if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
            raise ValueError("not a RIFF WAVE file")
        i, fmt, bits, nch, sr, data = 12, None, None, None, None, None
        while i + 8 <= len(raw):
            cid, sz = raw[i:i + 4], struct.unpack("<I", raw[i + 4:i + 8])[0]
            body = raw[i + 8:i + 8 + sz]
            if cid == b"fmt ":
                fmt, nch, sr = struct.unpack("<HHI", body[:8])
                bits = struct.unpack("<H", body[14:16])[0]
                if fmt == 0xFFFE and sz >= 40:      # WAVE_FORMAT_EXTENSIBLE
                    fmt = struct.unpack("<H", body[24:26])[0]
            elif cid == b"data":
                data = body
                break
            i += 8 + sz + (sz & 1)
        if data is None or fmt is None:
            raise ValueError("no fmt/data chunk")
        if fmt == 3:
            a = np.frombuffer(data, dtype="<f4" if bits == 32 else "<f8")
            a = a.astype(np.float32)
        elif bits == 16:
            a = np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0
        elif bits == 32:
            a = np.frombuffer(data, dtype="<i4").astype(np.float32) / 2147483648.0
        elif bits == 8:
            a = (np.frombuffer(data, dtype=np.uint8).astype(np.float32)
                 - 128.0) / 128.0
        elif bits == 24:
            b = np.frombuffer(data, dtype=np.uint8)
            b = b[:len(b) // 3 * 3].reshape(-1, 3).astype(np.int32)
            v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
            v = np.where(v & 0x800000, v - 0x1000000, v)
            a = v.astype(np.float32) / 8388608.0
        else:
            raise ValueError(f"unsupported: fmt {fmt}, {bits} bits")
        return a.reshape(-1, nch), sr

    def on_stop(self):
        if self._rendering and self._render_proc:
            self._cancelled = True
            try:
                self._render_proc.kill()
            except Exception:
                pass
            self.status.set("Cancelling the render…")
            return
        self._stop_playback()
        self.status.set("Stopped.")

    def on_apply(self):
        if not self.result_file:
            self.status.set("Standalone mode: no result path was supplied by Praat.")
            return
        def finished(ok, msg):
            if not ok:
                self.status.set("✖ " + msg)
                return
            self._write_done(msg)
        self.render(self.result_file, finished)

    def _write_done(self, msg):
        done = {"result": self.result_file,
                "slots": [s.script.name for s in self.slots if s.active],
                "modes": [s.mode for s in self.slots if s.active],
                "wet": float(self.wet_var.get()) / 100.0,
                "post": bool(self.post_var.get())}
        with open(self.done_file, "w", encoding="utf-8") as f:
            json.dump(done, f, indent=2)
        self.applied = True
        self.status.set("✔ Applied — " + msg +
                        "   (window stays open; close it to return to Praat)")

    # ---------- diagnostics ----------
    def set_praat(self):
        """Locate the Praat executable by hand and remember it."""
        from tkinter import filedialog
        types = [("Praat executable", "*.exe")] if sys.platform.startswith("win") \
            else [("All files", "*")]
        p = filedialog.askopenfilename(title="Select the Praat executable",
                                       filetypes=types)
        if not p:
            return
        if self.runner.probe(p):
            self.praat_var.set(self._praat_label())
            self.status.set(f"✔ Using Praat {self.runner.version_str} "
                            f"at {self.runner.exe} (remembered).")
            self._save_config()
        else:
            self.status.set("✖ " + self.runner.error)

    def _save_config(self):
        cfgp = self.cfg.get("config_path")
        if not cfgp:
            return
        try:
            with open(cfgp, "w", encoding="utf-8") as f:
                json.dump({"praat_exe": self.runner.exe,
                           "last_chain": self.chain_state()}, f, indent=2)
        except Exception:
            pass

    def test_praat(self):
        if not self.runner.exe:
            self.status.set("✖ " + self.runner.error)
            return
        probe = os.path.join(self.tmpdir, "mc_probe.praat")
        marker = os.path.join(self.tmpdir, "mc_probe.wav")
        with open(probe, "w", encoding="utf-8") as f:
            f.write("if praatVersion >= 7000\n    trustGranted = askForTrust()\n"
                    "endif\n"
                    'Create Sound from formula: "probe", 1, 0, 0.1, 44100, "0.1"\n'
                    f"Save as WAV file: {praat_str(marker)}\n"
                    'appendInfoLine: "@@MC probe ok ", praatVersion$\n')
        if os.path.exists(marker):
            os.remove(marker)
        code, out, err, argv = self.runner.run(probe, 60)
        self.last_log = ("COMMAND: " + " ".join(argv) + "\n\nstdout:\n" + out +
                         "\nstderr:\n" + err)
        if os.path.exists(marker):
            self.status.set(f"✔ Praat {self.runner.version_str} runs headless "
                            f"and can write audio.")
        else:
            self.status.set(f"✖ Praat probe failed (exit {code}) — see Log.")

    def show_log(self):
        tk, ttk = self.tk, self.ttk
        win = tk.Toplevel(self.root)
        win.title("Matrix Chain — log")
        win.configure(bg=BG)
        txt = tk.Text(win, width=118, height=40, bg=PANEL, fg=FG,
                      insertbackground=FG, wrap="none")
        txt.grid(row=0, column=0, sticky="nsew")
        sb = ttk.Scrollbar(win, orient="vertical", command=txt.yview)
        sb.grid(row=0, column=1, sticky="ns")
        txt.configure(yscrollcommand=sb.set)
        txt.insert("1.0", self.last_log or "(nothing rendered yet)")
        ttk.Label(win, text=f"Full log written to {self.log_path}",
                  style="Dim.TLabel").grid(row=1, column=0, sticky="w")

    # ---------- lifecycle ----------
    def _on_close(self):
        self._stop_playback()
        if self._render_proc:
            try:
                self._render_proc.kill()
            except Exception:
                pass
        self._save_config()
        for p in (self.scratch,):
            if os.path.exists(p):
                try:
                    os.remove(p)
                except OSError:
                    pass
        self.root.destroy()

    def run(self):
        self.root.mainloop()
        return self.applied


# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def load_config(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(here, "matrix_chain_config.json")
    stored = {}
    if os.path.isfile(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                stored = json.load(f)
        except Exception:
            stored = {}

    cfg = {"config_path": config_path,
           "praat_exe": stored.get("praat_exe", ""),
           "last_chain": stored.get("last_chain"),
           "library_root": os.path.dirname(here)}

    if "--wav" in argv:                       # standalone test mode
        cfg["input_file"] = argv[argv.index("--wav") + 1]
        if "--library" in argv:
            cfg["library_root"] = argv[argv.index("--library") + 1]
        if "--praat" in argv:
            cfg["praat_exe"] = argv[argv.index("--praat") + 1]
        cfg["temp_dir"] = tempfile.gettempdir()
        return cfg

    manifest_path = argv[1]
    with open(manifest_path, "r", encoding="utf-8") as f:
        man = json.load(f)
    global _error_file
    _error_file = man.get("error_file", "")
    cfg.update({k: man[k] for k in
                ("input_file", "result_file", "done_file", "error_file")
                if k in man})
    if man.get("library_root"):
        cfg["library_root"] = man["library_root"]
    if man.get("praat_exe"):
        cfg["praat_exe"] = man["praat_exe"]
    cfg["temp_dir"] = man.get("temp_dir") or os.path.dirname(manifest_path)
    cfg["timeout"] = man.get("timeout", 180)
    return cfg


def main():
    if len(sys.argv) < 2:
        print(__doc__ or "usage: matrix_chain.py <manifest.json> | --wav f.wav")
        return 1
    try:
        cfg = load_config(sys.argv)
        if not os.path.isfile(cfg.get("input_file", "")):
            raise FileNotFoundError(f"input WAV not found: {cfg.get('input_file')}")
        if not os.path.isdir(cfg["library_root"]):
            raise NotADirectoryError(f"library not found: {cfg['library_root']}")
        app = MatrixApp(cfg)
        ok = app.run()
        return 0 if ok else 1
    except Exception as exc:
        _crash(exc)


if __name__ == "__main__":
    sys.exit(main())
