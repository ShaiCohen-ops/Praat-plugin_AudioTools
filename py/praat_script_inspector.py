#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      praat_script_inspector.py
# Author:      Shai Cohen
# Version:     0.4 (2026)
#
# Changelog v0.4:
#   - FIXED: classify_output() only recognised the 16-bit "Save as WAV file",
#     so a bridge upgraded to "Save as 32-bit WAV file" was declared
#     no_audio_output and blocked -- improving its quality made it ineligible.
#     Any bit depth counts now, and so does reading audio back in, which is
#     how a bridge actually produces its Sound.
#   - "Open long sound file:" no longer counts as a bridge readback: it makes
#     a LongSound, which the chain cannot consume.  Such bridges are blocked
#     at scan time with that reason instead of failing mid-render.
#
# Changelog v0.3:
#   - Modern form fields read their value from the LAST argument: realvector
#     carries a format argument and a multi-line text field can carry a line
#     count, both of which made parts[1] the wrong value.
#   - Python bridges are classified rather than blocked wholesale: the backend
#     .py is located and read, and the bridge is called chainable only when the
#     Praat side reads audio back in AFTER calling Python.  Interactive
#     backends (tkinter/Qt/wx/pygame/matplotlib show/input) stay blocked.
#   - scan_library(include_py=True) scans py/, where most bridge launchers are.
#
# Changelog v0.2:
#   - FIXED: legacy form fields with a trailing comment or no default at all
#     ("real Window 0.02 seconds", "boolean Play") returned a None regex match
#     and raised AttributeError, which aborted the scan of the ENTIRE library
#     before the GUI could open.  Legacy fields are now split by tokens.
#   - FIXED: the selection guard written as two lines -- "n = numberOfSelected
#     (\"Sound\")" then "if n <> 1" -- was not recognised, so scripts using
#     that idiom were excluded as "input requirement unclear".  A stored count
#     is now traced to its later comparison.
#   - FIXED: a form field whose type keyword was not in the known list was
#     dropped entirely, so runScript: received too few arguments and every
#     value after the dropped field belonged to the wrong parameter ("Found 13
#     arguments but expected more").  Field detection is now a blacklist:
#     anything on a form line counts as a field unless it is comment/heading/
#     caption/option/button.  "button" lines now feed choice options, and
#     "..." continuation lines are merged into the line above.
#   - A malformed field is recorded as a warning on that script; an unhandled
#     error in one file marks that file ineligible.  Neither stops the scan.
# License:     MIT License
#
# Description:
#   Static inspector for .praat files.  Parses a script WITHOUT running it
#   and reports: form parameters (legacy and modern colon syntax), how many
#   Sound objects it needs selected, whether it leaves a Sound selected for
#   a host to save, external dependencies, and anything that blocks headless
#   (praat --run) execution.
#
#   Used by matrix_chain.py to build the 4-slot matrix catalog, but is
#   standalone: run it over the plugin folder to get an eligibility report.
#
# Usage:
#   python praat_script_inspector.py <folder-or-file> [--report] [--csv out.csv]
#   python praat_script_inspector.py <file.praat> --json
# ============================================================

from __future__ import annotations

import csv
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

NUMERIC_TYPES = {"real", "positive", "integer", "natural"}
TEXT_TYPES = {"word", "sentence", "text", "infile", "outfile", "folder"}
MENU_TYPES = {"optionmenu", "choice"}
VECTOR_TYPES = {"realvector", "positivevector", "integervector", "naturalvector",
                "numvec", "complexvector"}
FIELD_TYPES = (NUMERIC_TYPES | TEXT_TYPES | MENU_TYPES | VECTOR_TYPES |
               {"boolean"})

# Keywords inside a form that consume NO runScript argument.  Everything else
# on a form line is treated as a field, even a type this parser has never seen:
# a whitelist of known types silently drops unknown ones, and every argument
# after the dropped field then lands in the wrong parameter.
NO_ARG_KEYWORDS = {"comment", "heading", "caption", "option", "button",
                   "endform", "form"}

# Booleans the host switches OFF for a chain render.  The AudioTools library
# convention is a `Play` boolean defaulting to 1; left on, every slot would
# audition itself mid-render (and block for the sound's duration).
PLAY_NAME_RE = re.compile(r"^(play|audition|preview|listen|play_result|play_sound)$", re.I)
DRAW_NAME_RE = re.compile(
    r"(draw|visuali|plot|picture|figure|graph|spectrogram_panel|show_)", re.I)

# Commands that produce or transform audio.  Used only to decide whether a
# script plausibly leaves a Sound behind; absence of ALL of them is a strong
# signal that the script is analysis/drawing only.
AUDIO_CMD_RE = re.compile(
    r"(?<![A-Za-z])(Create Sound|Copy:|Formula:|Formula \(part\):|Filter |"
    r"Concatenate|Resample:|Get resynthesis|To Sound|Extract part|"
    r"Convert to mono|Convert to stereo|Scale peak|Scale intensity|Multiply|"
    r"Override sampling frequency|Combine to stereo|Extract one channel|"
    r"Deepen band modulation|Lengthen|"
    # reading audio back in makes a Sound just as surely as processing one --
    # this is how every Python bridge produces its output
    r"Read from file|Read Sound from|Read two Sounds from stereo file|"
    # any bit depth, not just the 16-bit default
    r"Save as (?:\d+-bit )?(?:WAV|AIFF|AIFC|FLAC|NeXt/Sun) file)")

SAVE_AUDIO_RE = re.compile(
    r"\bSave as (?:\d+-bit )?(?:WAV|AIFF|AIFC|NeXt/Sun|FLAC) file:", re.I)
PYTHON_BRIDGE_RE = re.compile(r"(runSubprocess|runSystem|system\$?\s*:|\bsystem_nocheck\b)")
PY_FILE_RE = re.compile(r"\.py\b")
CHOOSER_RE = re.compile(r"\b(chooseReadFile\$|chooseWriteFile\$|chooseFolder\$)")
EDITOR_RE = re.compile(r"^\s*(View & Edit|Edit\b|demo\b|demoShow|demoWaitForInput)")
ABS_PATH_RE = re.compile(r"""["'](?:[A-Za-z]:[\\/]|/Users/|/home/|/Volumes/)""")
FILELIST_RE = re.compile(r"Create Strings as file list")

BLOCK_OPEN_RE = re.compile(r"^\s*(for\b|while\b|repeat\b|procedure\b)")
BLOCK_CLOSE_RE = re.compile(r"^\s*(endfor\b|endwhile\b|until\b|endproc\b)")


# ─────────────────────────────────────────────────────────────────────────────
# DATA MODEL
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Param:
    """One form field."""
    index: int                      # 1-based position in the form = runScript arg order
    var: str                        # Praat variable name the script will see
    label: str                      # text as written in the form
    ptype: str                      # real / positive / integer / natural / boolean /
                                    # optionmenu / choice / word / sentence / text / ...
    default: str = ""               # as a string, exactly as it will be passed back
    options: list = field(default_factory=list)   # menu option texts, in order
    minimum: float | None = None    # only when the label carries a range, e.g. "(0-1)"
    maximum: float | None = None
    is_play: bool = False
    is_draw: bool = False

    @property
    def passes_option_text(self) -> bool:
        # runScript: sends optionmenu/choice as the option TEXT, not the index.
        return self.ptype in MENU_TYPES


GUI_BACKEND_RE = re.compile(
    r"^\s*(?:import|from)\s+(tkinter|PyQt5|PyQt6|PySide2|PySide6|wx|kivy|"
    r"pygame|streamlit|webview|gradio|dearpygui|PySimpleGUI)\b", re.M)
BLOCKING_BACKEND_RE = re.compile(
    r"(mainloop\s*\(|\binput\s*\(|plt\.show\s*\(|pyplot\.show\s*\(|"
    r"app\.exec_?\s*\()")
# What counts as a readback: it must put a Sound in the object list.
# "Open long sound file:" creates a LongSound, which the chain's output
# contract cannot consume, so it is deliberately NOT here.
READBACK_RE = re.compile(
    r"Read from file:|Read Sound from|Read two Sounds from stereo file")
LONGSOUND_RE = re.compile(r"Open long sound file:")


def find_backend(text, script_path, root):
    """Resolve the .py file a bridge script calls, if we can find it on disk."""
    names = re.findall(r"[\"\'/\\+ ]([\w\-.]+\.py)\b", text)
    seen = []
    for n in names:
        if n in seen:
            continue
        seen.append(n)
        here = os.path.dirname(script_path)
        for cand in (os.path.join(here, n),
                     os.path.join(here, "py", n),
                     os.path.join(root or here, "py", n),
                     os.path.join(os.path.dirname(root or here), "py", n)):
            if os.path.isfile(cand):
                return cand, n
    return "", (seen[0] if seen else "")


def classify_bridge(text, script_path, root):
    """chainable / interactive / external-output, plus the backend path.

    A bridge is only chainable if the Praat side reads audio back in AFTER
    calling Python: that readback is what leaves a Sound for the next slot.
    Everything else either blocks on a window or ends outside the object list.
    """
    m = PYTHON_BRIDGE_RE.search(text)
    after = text[m.end():] if m else ""
    reads_back = bool(READBACK_RE.search(after))
    backend, name = find_backend(text, script_path, root)
    if backend:
        try:
            with open(backend, "r", encoding="utf-8", errors="replace") as f:
                btext = f.read()
        except OSError:
            btext = ""
        if GUI_BACKEND_RE.search(btext) or BLOCKING_BACKEND_RE.search(btext):
            return "interactive", backend, name
    if not reads_back:
        if LONGSOUND_RE.search(after):
            return "longsound", backend, name
        return "external-output", backend, name
    return "chainable", backend, name


@dataclass
class ScriptInfo:
    path: str
    name: str
    category: str
    params: list = field(default_factory=list)
    form_syntax: str = "none"          # none / legacy / modern
    input_requirement: str = "unknown"  # one / multi / none / unknown
    input_evidence: str = ""
    output_strategy: str = "host_saves_selected_sound"
    writes_own_file: bool = False
    plays_audio: bool = False
    dependencies: list = field(default_factory=list)
    is_bridge: bool = False
    bridge_kind: str = ""          # chainable / interactive / external-output
    backend: str = ""
    backend_name: str = ""
    blockers: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    parse_error: str = ""

    @property
    def eligible(self) -> bool:
        return not self.blockers

    @property
    def slot1_only(self) -> bool:
        return self.input_requirement == "none"

    def to_dict(self):
        d = asdict(self)
        d["eligible"] = self.eligible
        d["slot1_only"] = self.slot1_only
        return d


# ─────────────────────────────────────────────────────────────────────────────
# FORM PARSING
# ─────────────────────────────────────────────────────────────────────────────

def praat_variable_name(label: str) -> str:
    """Praat's label -> variable rule.

    Everything from the first '(' is dropped (units/ranges), spaces become
    underscores, and ONLY the first character is lowercased -- so a label
    like "RMS threshold (dB)" arrives in the script as rMS_threshold.
    """
    s = label.split("(")[0].strip()
    s = re.sub(r"\s+", "_", s)
    s = s.strip("_")
    if not s:
        return ""
    return s[0].lower() + s[1:]


def _strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1].replace('""', '"')
    return s


def _split_top_level_comma(s: str):
    """Split on commas that are outside double quotes."""
    out, buf, inq = [], [], False
    i = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            if inq and i + 1 < len(s) and s[i + 1] == '"':
                buf.append('""')
                i += 2
                continue
            inq = not inq
            buf.append(c)
        elif c == "," and not inq:
            out.append("".join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1
    out.append("".join(buf))
    return [p.strip() for p in out]


def _range_from_label(label: str):
    """Pull a numeric range out of a label like "Mix (0-1)" or "Gain (-24..24 dB)"."""
    m = re.search(r"\(\s*(-?\d+(?:\.\d+)?)\s*(?:-|\.\.|to)\s*(-?\d+(?:\.\d+)?)",
                  label)
    if m:
        try:
            lo, hi = float(m.group(1)), float(m.group(2))
            if lo < hi:
                return lo, hi
        except ValueError:
            pass
    return None, None


def parse_form(lines):
    """Return (params, syntax, form_span) for the FIRST form block in `lines`."""
    start = end = None
    syntax = "none"
    for i, raw in enumerate(lines):
        s = raw.strip()
        if start is None:
            if re.match(r"^form:\s*\"", s):
                start, syntax = i, "modern"
            elif re.match(r"^form\s+\S", s):
                start, syntax = i, "legacy"
        elif re.match(r"^endform\b", s):
            end = i
            break
    if start is None:
        return [], "none", (None, None), []
    if end is None:
        end = len(lines)

    params: list[Param] = []
    problems: list[str] = []
    idx = 0

    # Praat continuation lines ("... more text") belong to the line above.
    merged = []
    for raw in lines[start + 1:end]:
        if raw.strip().startswith("..."):
            if merged:
                merged[-1] = merged[-1] + " " + raw.strip()[3:].strip()
                continue
        merged.append(raw)

    for raw in merged:
      try:
          s = raw.strip()
          if not s or s.startswith("#"):
              continue

          kw = re.match(r"^([A-Za-z_]+)\s*:?\s*", s)
          keyword = kw.group(1).lower() if kw else ""

          # ---- option / button lines belong to the previous menu field ----
          if keyword in ("option", "button"):
              m = re.match(r"^(?:option|button):?\s*(.*)$", s, re.I)
              if m and params and params[-1].ptype in MENU_TYPES:
                  params[-1].options.append(_strip_quotes(m.group(1)))
              continue

          if keyword in NO_ARG_KEYWORDS:
              continue
          if not keyword:
              continue

          modern = bool(re.match(r"^[A-Za-z_]+\s*:", s))
          ptype = keyword if keyword in FIELD_TYPES else "unknown"

          if modern:
              # real: "Gain (dB)", "0.5"
              # Some field types carry extra arguments between the label and
              # the value -- realvector takes a format argument, and a
              # multi-line text field can take a line count BEFORE the label.
              # The value is always the last argument, so read it from the end
              # instead of assuming it is parts[1].
              body = s.split(":", 1)[1]
              parts = _split_top_level_comma(body)
              while parts and re.fullmatch(r"-?\d+(\.\d+)?", parts[0].strip()):
                  parts = parts[1:]           # leading layout argument
              label = _strip_quotes(parts[0]) if parts else ""
              default = _strip_quotes(parts[-1]) if len(parts) > 1 else ""
          else:
              rest = re.sub(r"^[A-Za-z_]+\s*", "", s).strip()
              if ptype in MENU_TYPES or (ptype == "unknown" and ":" in rest):
                  if ":" in rest:
                      head, _, tail = rest.partition(":")
                      label = head.strip()
                      tail = tail.strip()
                      default = tail.split()[0] if tail else ""
                  else:
                      toks = rest.split()
                      label = toks[0] if toks else ""
                      default = toks[1] if len(toks) > 1 else ""
              elif ptype in TEXT_TYPES or ptype in VECTOR_TYPES:
                  toks = rest.split(None, 1)
                  label = toks[0] if toks else ""
                  default = toks[1].strip() if len(toks) > 1 else ""
              else:
                  # numeric, boolean, vector, unknown: name then default; any
                  # further tokens are a trailing comment.
                  toks = rest.split(None, 1)
                  label = toks[0] if toks else ""
                  remainder = toks[1].strip() if len(toks) > 1 else ""
                  default = remainder.split()[0] if remainder else ""
              label = label.replace("_", " ").strip()

          if not label:
              continue
          var = praat_variable_name(label)
          if not var:
              continue
          idx += 1
          lo, hi = _range_from_label(label)
          params.append(Param(idx, var, label, ptype, _strip_quotes(default),
                              minimum=lo, maximum=hi,
                              is_play=bool(PLAY_NAME_RE.match(var)),
                              is_draw=bool(DRAW_NAME_RE.search(var))))
          continue
      except Exception as exc:                      # noqa: BLE001
        # One malformed field must never abort the scan of a 480-script
        # library.  Record it and carry on.
        problems.append(f"{raw.strip()[:60]} -> {type(exc).__name__}: {exc}")

    # A field written with no default at all would send an empty string to
    # runScript:, which Praat rejects for a numeric field.  Fill it in.
    for p in params:
        if p.default == "":
            if p.ptype == "boolean":
                p.default = "0"
            elif p.ptype in ("positive", "natural"):
                p.default = "1"
            elif p.ptype in NUMERIC_TYPES:
                p.default = "0"

    # menu defaults are 1-based indices in the form definition; convert to the
    # option TEXT, because that is what runScript: expects to receive.
    for p in params:
        if p.ptype in MENU_TYPES and p.options:
            try:
                i = int(float(p.default))
                p.default = p.options[i - 1] if 1 <= i <= len(p.options) else p.options[0]
            except (ValueError, TypeError):
                if p.default not in p.options:
                    p.default = p.options[0]
    return params, syntax, (start, end), problems


# ─────────────────────────────────────────────────────────────────────────────
# BODY ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────

def _depth_map(lines):
    """Loop/procedure nesting depth per line (0 = top level)."""
    depth, out = 0, []
    for raw in lines:
        s = raw.strip()
        closing = bool(BLOCK_CLOSE_RE.match(s))
        if closing:
            depth = max(0, depth - 1)
        out.append(depth)
        if BLOCK_OPEN_RE.match(s):
            depth += 1
    return out


def analyse_body(lines, form_span):
    """Everything that is not the form block."""
    fs, fe = form_span
    body = list(lines)
    if fs is not None:
        body = lines[:fs] + ["" for _ in range(fe - fs + 1)] + lines[fe + 1:]
    stripped = [l.split("#")[0] if l.strip().startswith("#") else l for l in body]
    text = "\n".join(stripped)
    depths = _depth_map(stripped)
    return stripped, text, depths


def classify_input(text) -> tuple[str, str]:
    """How many Sound objects must be selected before the script runs."""

    def verdict(op, n, ev):
        if n >= 2:
            return "multi", ev
        return "one", ev

    # 1. the count compared inline:  if numberOfSelected("Sound") <> 1
    for m in re.finditer(
            r"numberOfSelected\s*\(?\s*\"Sound\"\s*\)?\s*(<>|<=|>=|<|>|=)\s*(\d+)",
            text):
        return verdict(m.group(1), int(m.group(2)),
                       f'numberOfSelected("Sound") {m.group(1)} {m.group(2)}')

    # 2. the count STORED first, compared later -- the common house style:
    #        nSelected = numberOfSelected("Sound")
    #        if nSelected <> 1
    #    Matching only the inline form (1) wrongly reported these as unclear.
    counters = re.findall(
        r"(\w+)\s*=\s*numberOfSelected\s*\(?\s*\"Sound\"", text)
    for var in counters:
        m = re.search(r"\b" + re.escape(var) +
                      r"\s*(<>|<=|>=|<|>|=)\s*(\d+)", text)
        if m:
            return verdict(m.group(1), int(m.group(2)),
                           f"{var} = numberOfSelected(\"Sound\"), "
                           f"then {var} {m.group(1)} {m.group(2)}")

    if counters:
        # counted and used, but never compared with a literal
        if re.search(r"selected\s*\(\s*\"Sound\"\s*,", text):
            return "multi", "iterates over the selection"
        return "one", (f"{counters[0]} = numberOfSelected(\"Sound\"), "
                       f"no literal comparison found")

    if re.search(r"selected\s*\(\s*\"Sound\"\s*,\s*[2-9]", text):
        return "multi", 'selected("Sound", 2) or higher'
    if re.search(r"selected\$?\s*\(\s*\"Sound\"", text) or \
       re.search(r"\bselected\$?\s*\(\s*\)", text):
        return "one", "reads the selected Sound without a count check"
    if re.search(r"Create Sound (from formula|as pure tone|from tone complex)",
                 text):
        return "none", "creates its own Sound; no input needed"
    return "unknown", "no recognisable Sound selection"


def classify_output(text) -> tuple[str, bool]:
    writes = bool(SAVE_AUDIO_RE.search(text))
    has_audio = bool(AUDIO_CMD_RE.search(text))
    if not has_audio:
        return "no_audio_output", writes
    if writes and PYTHON_BRIDGE_RE.search(text):
        return "script_writes_own_file", True
    return "host_saves_selected_sound", writes


def inspect_script(path, root=None) -> ScriptInfo:
    name = os.path.splitext(os.path.basename(path))[0]
    category = ""
    if root:
        rel = os.path.relpath(os.path.dirname(path), root)
        category = "" if rel == "." else rel.replace(os.sep, "/")

    info = ScriptInfo(path=path, name=name, category=category)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()
    except OSError as exc:
        info.parse_error = str(exc)
        info.blockers.append(f"unreadable: {exc}")
        return info

    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    params, syntax, span, problems = parse_form(lines)
    info.params, info.form_syntax = params, syntax
    for pr in problems:
        info.warnings.append(f"form field not parsed: {pr}")
    body, text, depths = analyse_body(lines, span)

    info.input_requirement, info.input_evidence = classify_input(text)
    info.output_strategy, info.writes_own_file = classify_output(text)

    # ---- dependencies ----
    if PYTHON_BRIDGE_RE.search(text):
        if PY_FILE_RE.search(text):
            info.is_bridge = True
            kind, backend, name = classify_bridge(text, path, root)
            info.bridge_kind, info.backend, info.backend_name = kind, backend, name
            info.dependencies.append(
                f"python bridge -> {name or 'unknown .py'}"
                f"{'' if backend else ' (backend not found on disk)'}")
            if kind == "interactive":
                info.blockers.append(
                    f"python bridge with an interactive backend "
                    f"({os.path.basename(backend)}): it would open a window and "
                    f"stall the headless render")
            elif kind == "longsound":
                info.blockers.append(
                    "python bridge that reads its result back as a LongSound: "
                    "the chain needs a Sound object, so it cannot feed the "
                    "next slot")
            elif kind == "external-output":
                info.blockers.append(
                    "python bridge that never reads audio back into Praat: "
                    "it leaves no Sound for the next slot")
            else:
                info.warnings.append(
                    "python bridge: runs an external backend, render is slower")
        else:
            info.dependencies.append("shells out to an external command")
            info.warnings.append("runs an external command")
    if ABS_PATH_RE.search(text):
        info.dependencies.append("hard-coded absolute path")
    if FILELIST_RE.search(text):
        info.dependencies.append("reads a folder of files (corpus)")
        info.blockers.append("needs an external corpus folder")

    # ---- interactivity that blocks a headless run ----
    for i, ln in enumerate(body):
        s = ln.strip()
        if re.match(r"^(beginPause:?|pauseScript:?)\b", s):
            if depths[i] > 0:
                info.blockers.append(
                    f"pause dialog inside a loop or procedure (line {i + 1})")
            else:
                info.warnings.append(
                    "top-level pause dialog: headless runs auto-continue with "
                    "its DEFAULTS, so those fields are not controllable here")
        if EDITOR_RE.match(s):
            info.blockers.append(f"opens an editor or demo window (line {i + 1})")

    for m in CHOOSER_RE.finditer(text):
        ctx = text[max(0, m.start() - 200):m.start()]
        # A chooser used only as a fallback for an empty form field is survivable
        # (it returns "" immediately under praat --run) but still yields nothing.
        if re.search(r'=\s*""|<>\s*""|if\s+\w+\$\s*=', ctx.splitlines()[-1] if ctx.splitlines() else ""):
            info.warnings.append("file/folder picker used as a fallback")
        else:
            info.blockers.append("needs a file/folder picker (returns empty headless)")
        break

    # ---- output-side blockers ----
    if info.output_strategy == "no_audio_output":
        info.blockers.append("no audio output: analysis/drawing only")
    if info.input_requirement == "multi":
        info.blockers.append("needs 2+ selected Sounds")
    if info.input_requirement == "unknown":
        info.blockers.append(f"input requirement unclear ({info.input_evidence})")

    # ---- warnings ----
    if info.writes_own_file and info.output_strategy == "host_saves_selected_sound":
        info.warnings.append("also saves a file of its own")
    if re.search(r"^\s*Play\s*$", text, re.M):
        info.plays_audio = True
        has_play_flag = any(p.is_play for p in params)
        if not has_play_flag:
            info.warnings.append("unconditional Play: will audition itself mid-render")
    if syntax == "none" and info.input_requirement in ("one", "none"):
        info.warnings.append("no form: runs with its built-in values")

    return info


# ─────────────────────────────────────────────────────────────────────────────
# LIBRARY SCAN
# ─────────────────────────────────────────────────────────────────────────────

SKIP_DIRS = {"py", "Vector Chain", "scl", "Kemar_HRIR", "__pycache__"}


def scan_library(root, skip_dirs=None, include_py=False):
    """Walk `root` and inspect every .praat file.  Returns a list of ScriptInfo.

    `py/` holds the Praat side of the Python bridges; it is skipped unless
    bridges are wanted, in which case those launchers are exactly what we
    need to look at.
    """
    skip = set(SKIP_DIRS if skip_dirs is None else skip_dirs)
    if include_py:
        skip.discard("py")
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip and not d.startswith(".")]
        for fn in sorted(filenames):
            if fn.lower().endswith(".praat"):
                full = os.path.join(dirpath, fn)
                try:
                    out.append(inspect_script(full, root))
                except Exception as exc:                       # noqa: BLE001
                    # A script the inspector cannot handle is reported as
                    # ineligible, never allowed to abort the whole scan.
                    bad = ScriptInfo(path=full,
                                     name=os.path.splitext(fn)[0],
                                     category=("" if os.path.relpath(
                                         dirpath, root) == "." else
                                         os.path.relpath(dirpath, root).replace(
                                             os.sep, "/")))
                    bad.parse_error = f"{type(exc).__name__}: {exc}"
                    bad.blockers.append(f"inspector error: {bad.parse_error}")
                    out.append(bad)
    out.sort(key=lambda s: (s.category.lower(), s.name.lower()))
    return out


def report(scripts, verbose=False):
    lines = []
    ok = [s for s in scripts if s.eligible]
    bad = [s for s in scripts if not s.eligible]
    lines.append(f"Scanned {len(scripts)} scripts: "
                 f"{len(ok)} eligible, {len(bad)} excluded")
    lines.append("")
    by_cat = {}
    for s in scripts:
        by_cat.setdefault(s.category or "(root)", []).append(s)
    for cat in sorted(by_cat):
        items = by_cat[cat]
        n_ok = sum(1 for s in items if s.eligible)
        lines.append(f"--- {cat}   [{n_ok}/{len(items)} eligible]")
        for s in items:
            mark = "  OK " if s.eligible else "  -- "
            tag = f"{len(s.params)}p {s.form_syntax[:3]} {s.input_requirement}"
            lines.append(f"{mark}{s.name:<52} {tag}")
            if verbose or not s.eligible:
                for b in s.blockers:
                    lines.append(f"        BLOCK  {b}")
            if verbose:
                for w in s.warnings:
                    lines.append(f"        warn   {w}")
        lines.append("")
    return "\n".join(lines)


def main(argv):
    if len(argv) < 2:
        print(__doc__ or "usage: praat_script_inspector.py <folder|file> [--report]")
        return 1
    target = argv[1]
    verbose = "--verbose" in argv or "-v" in argv
    if os.path.isfile(target):
        info = inspect_script(target, os.path.dirname(target))
        if "--json" in argv:
            print(json.dumps(info.to_dict(), indent=2))
        else:
            print(f"{info.name}   [{info.form_syntax} form, "
                  f"{len(info.params)} parameters]")
            print(f"  input      : {info.input_requirement}  ({info.input_evidence})")
            print(f"  output     : {info.output_strategy}"
                  f"{'  (+writes its own file)' if info.writes_own_file else ''}")
            print(f"  eligible   : {info.eligible}")
            for b in info.blockers:
                print(f"  BLOCK      : {b}")
            for w in info.warnings:
                print(f"  warn       : {w}")
            for d in info.dependencies:
                print(f"  depends    : {d}")
            print("  parameters :")
            for p in info.params:
                extra = f" options={p.options}" if p.options else ""
                print(f"     {p.index:2d}. {p.var:<28} {p.ptype:<11} "
                      f"= {p.default!r}{extra}")
        return 0

    scripts = scan_library(target)
    if "--csv" in argv:
        out = argv[argv.index("--csv") + 1]
        with open(out, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["category", "name", "eligible", "input", "output",
                        "params", "form", "blockers", "warnings"])
            for s in scripts:
                w.writerow([s.category, s.name, s.eligible, s.input_requirement,
                            s.output_strategy, len(s.params), s.form_syntax,
                            " | ".join(s.blockers), " | ".join(s.warnings)])
        print(f"wrote {out}")
    print(report(scripts, verbose))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
