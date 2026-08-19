"""
host_vst.py  –  Praat → Python → VST3 native-editor host v1.6
========================================================
CLI (legacy / Praat-driven):
    py host_vst.py input.wav output.wav plugin.vst3 [tail] [buf] [params] [dump]

GUI (launched by the new Praat script or manually):
    py host_vst.py --gui input.wav output.wav [plugin.vst3] [tail] [buf] [params]

When --gui is present the Tkinter window opens pre-populated from the remaining
arguments and from the last-used JSON config. The user can open the VST3's
native editor, audition an 8-second rendered preview, then click Process (or
Cancel). No file-pickers for input/output WAVs are shown.
"""

from __future__ import annotations

import json
import os
import sys
import subprocess
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk
from typing import Any, Dict, Optional, Tuple

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

CONFIG_DIR  = Path.home() / ".vst_host"
CONFIG_FILE = CONFIG_DIR / "settings.json"
PRESET_DIR  = CONFIG_DIR / "presets"
VST_CACHE_FILE = CONFIG_DIR / "vst_plugins.json"

# ---------------------------------------------------------------------------
# Dependency helpers
# ---------------------------------------------------------------------------

def _check_dependencies() -> None:
    missing = []
    try:
        import pedalboard          # noqa: F401
        from pedalboard.io import AudioFile  # noqa: F401
    except ImportError:
        missing.append("pedalboard")
    if missing:
        msg = ("Missing Python packages: " + ", ".join(missing)
               + "\nInstall with:  pip install " + " ".join(missing))
        _fail(msg)


def _fail(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)

# ---------------------------------------------------------------------------
# Parameter parsing
# ---------------------------------------------------------------------------

def _parse_param_string(param_string: str) -> Dict[str, float]:
    result: Dict[str, float] = {}
    if not param_string.strip():
        return result
    for item in param_string.split(","):
        item = item.strip()
        if not item:
            continue
        if "=" in item:
            key, value = item.split("=", 1)
        elif " " in item.strip():
            key, value = item.strip().split(None, 1)
        else:
            _fail(f"Bad parameter assignment '{item}'. Use name=value or name value, comma-separated.")
        try:
            result[key.strip()] = float(value.strip())
        except ValueError:
            _fail(f"Bad numeric value in parameter assignment '{item}'")
    return result

# ---------------------------------------------------------------------------
# Core offline processor (shared by CLI and GUI)
# ---------------------------------------------------------------------------

def _apply_param_assignments(plugin, param_string: str, emit=print) -> None:
    """Apply host text-field assignments to an already-loaded plugin."""
    available_params = list(plugin.parameters.keys()) if hasattr(plugin, "parameters") else []
    assignments = _parse_param_string(param_string)
    for key, value in assignments.items():
        if key not in available_params:
            emit(f"WARNING: parameter '{key}' not found - skipping.")
            continue
        try:
            setattr(plugin, key, value)
            emit(f"Set {key} = {value}")
        except Exception as exc:
            emit(f"WARNING: could not set '{key}' to {value}: {exc}")

def _reset_plugin_state(plugin, emit=print) -> None:
    """Reset delay/reverb/LFO state without changing parameter values."""
    try:
        plugin.reset()
    except Exception as exc:
        emit(f"WARNING: plugin reset failed; continuing with current state: {exc}")

def run_offline(
    in_wav: str,
    out_wav: str,
    plugin_path: str,
    tail_seconds: float = 1.0,
    buffer_size: int = 8192,
    param_string: str = "",
    dump_params: bool = False,
    log=None,           # callable(str) for GUI feedback; None -> print
    plugin=None,        # pre-loaded plugin object (must be loaded on main thread)
    apply_params: bool = True,
) -> None:
    """Load plugin, set params, render in_wav → out_wav."""
    _check_dependencies()
    from pedalboard import load_plugin
    from pedalboard.io import AudioFile
    import numpy as np

    def emit(s: str) -> None:
        if log:
            log(s)
        else:
            print(s)

    if not os.path.isfile(in_wav):
        raise FileNotFoundError(f"Input file not found: {in_wav}")
    if plugin is None:
        if not os.path.exists(plugin_path):
            raise FileNotFoundError(f"VST3 plugin not found: {plugin_path}")
        if not plugin_path.lower().endswith(".vst3"):
            raise ValueError("Plugin path must end with .vst3")
        emit(f"Loading plugin: {plugin_path}")
        plugin = load_plugin(plugin_path)
    emit(f"Loaded: {plugin}")

    available_params = list(plugin.parameters.keys()) if hasattr(plugin, "parameters") else []

    if dump_params:
        emit("Available parameters:")
        emit(f"  {'Name':<45} {'Min':>10} {'Max':>10} {'Default':>10} {'Current':>10}")
        emit(f"  {'-'*45} {'-'*10} {'-'*10} {'-'*10} {'-'*10}")
        for name in available_params:
            def fmt(v: Any) -> str:
                try:
                    return f"{float(v):>10.4g}"
                except (TypeError, ValueError):
                    return f"{str(v):>10}"
            try:
                param = plugin.parameters[name]
                mn = getattr(param, "min_value",     "?")
                mx = getattr(param, "max_value",     "?")
                df = getattr(param, "default_value", "?")
                try:
                    cur = getattr(plugin, name)
                except Exception:
                    cur = "?"
                emit(f"  {name:<45}{fmt(mn)}{fmt(mx)}{fmt(df)}{fmt(cur)}")
            except Exception as exc:
                emit(f"  {name:<45}  (error: {exc})")

    if apply_params:
        _apply_param_assignments(plugin, param_string, emit)

    # GUI mode may have auditioned this same plugin instance already. Reset
    # DSP history before the final render; Pedalboard documents that reset()
    # preserves parameter values while clearing internal delay/LFO/etc. state.
    _reset_plugin_state(plugin, emit)

    with AudioFile(in_wav) as f:
        audio       = f.read(f.frames)
        sr          = f.samplerate
        num_channels = f.num_channels

    emit(f"Input:    {in_wav}")
    emit(f"Output:   {out_wav}")
    emit(f"SR: {sr}  Channels: {num_channels}  Frames: {audio.shape[-1]}")

    # reset=False avoids the "must be reloaded on the main thread" error that
    # some VST3s raise when reset=True is passed (reset forces a re-init which
    # some plugins only allow on the thread they were loaded on).
    processed = plugin(audio, sr, buffer_size=buffer_size, reset=False)

    tail_seconds = max(0.0, tail_seconds)
    if tail_seconds > 0:
        tail_frames = int(round(tail_seconds * sr))
        silence     = np.zeros((num_channels, tail_frames), dtype=np.float32)
        tail        = plugin(silence, sr, buffer_size=buffer_size, reset=False)
        processed   = np.concatenate([processed, tail], axis=1)

    with AudioFile(out_wav, "w", sr, processed.shape[0]) as f:
        f.write(processed)

    emit(f"OK: wrote {out_wav}")

# ---------------------------------------------------------------------------
# Config / preset helpers
# ---------------------------------------------------------------------------

def _load_config() -> Dict[str, Any]:
    try:
        if CONFIG_FILE.exists():
            return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {}


def _save_config(data: Dict[str, Any]) -> None:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")
    except Exception as exc:
        print(f"WARNING: could not save config: {exc}", file=sys.stderr)


def _list_presets() -> list[str]:
    try:
        PRESET_DIR.mkdir(parents=True, exist_ok=True)
        return sorted(p.stem for p in PRESET_DIR.glob("*.json"))
    except Exception:
        return []


def _load_preset(name: str) -> Optional[Dict[str, Any]]:
    try:
        path = PRESET_DIR / f"{name}.json"
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        pass
    return None


def _save_preset(name: str, data: Dict[str, Any]) -> None:
    PRESET_DIR.mkdir(parents=True, exist_ok=True)
    path = PRESET_DIR / f"{name}.json"
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


# ---------------------------------------------------------------------------
# VST3 discovery / cache
# ---------------------------------------------------------------------------

def _default_vst3_roots() -> list[Path]:
    """Return conventional VST3 search roots for the current platform."""
    roots: list[Path] = []

    def add(path: Optional[str | Path]) -> None:
        if not path:
            return
        p = Path(path).expanduser()
        key = os.path.normcase(os.path.abspath(str(p)))
        if all(os.path.normcase(os.path.abspath(str(existing))) != key for existing in roots):
            roots.append(p)

    if sys.platform == "win32":
        # Steinberg's normal system-wide VST3 location, plus common variants.
        for env_name in ("COMMONPROGRAMFILES", "CommonProgramW6432"):
            base = os.environ.get(env_name)
            if base:
                add(Path(base) / "VST3")
        for env_name in ("PROGRAMFILES", "PROGRAMFILES(X86)"):
            base = os.environ.get(env_name)
            if base:
                add(Path(base) / "Common Files" / "VST3")
        local = os.environ.get("LOCALAPPDATA")
        if local:
            add(Path(local) / "Programs" / "Common" / "VST3")
    elif sys.platform == "darwin":
        add("/Library/Audio/Plug-Ins/VST3")
        add(Path.home() / "Library/Audio/Plug-Ins/VST3")
    else:
        add("/usr/lib/vst3")
        add("/usr/local/lib/vst3")
        add(Path.home() / ".vst3")

    return roots


def _scan_vst3_paths(extra_paths: Optional[list[str]] = None) -> tuple[list[str], list[str]]:
    """Discover .vst3 bundles/files without loading any plugins.

    Directory bundles ending in .vst3 are treated as a single plugin and are
    pruned from os.walk so their internal files are never mistaken for plugins.
    Returns (plugin_paths, roots_that_were_scanned).
    """
    roots = _default_vst3_roots()

    # If the currently selected plugin lives outside a standard root, include
    # its parent so Scan VSTs does not make that plugin disappear from the list.
    for raw in extra_paths or []:
        if not raw:
            continue
        p = Path(raw).expanduser()
        parent = p.parent if p.suffix.lower() == ".vst3" else p
        if parent.exists():
            key = os.path.normcase(os.path.abspath(str(parent)))
            if all(os.path.normcase(os.path.abspath(str(r))) != key for r in roots):
                roots.append(parent)

    found: dict[str, str] = {}
    scanned_roots: list[str] = []

    for root in roots:
        try:
            if not root.exists() or not root.is_dir():
                continue
            scanned_roots.append(str(root))
            for current, dirs, files in os.walk(root, topdown=True):
                kept_dirs = []
                for dirname in dirs:
                    full = Path(current) / dirname
                    if dirname.lower().endswith(".vst3"):
                        normalized = os.path.normcase(os.path.abspath(str(full)))
                        found[normalized] = str(full)
                    else:
                        kept_dirs.append(dirname)
                dirs[:] = kept_dirs

                for filename in files:
                    if filename.lower().endswith(".vst3"):
                        full = Path(current) / filename
                        normalized = os.path.normcase(os.path.abspath(str(full)))
                        found[normalized] = str(full)
        except (OSError, PermissionError):
            # One protected/broken folder should not abort the whole scan.
            continue

    paths = sorted(found.values(), key=lambda p: (Path(p).stem.casefold(), p.casefold()))
    return paths, scanned_roots


def _load_vst_cache() -> list[str]:
    try:
        if not VST_CACHE_FILE.exists():
            return []
        data = json.loads(VST_CACHE_FILE.read_text(encoding="utf-8"))
        raw_paths = data.get("paths", []) if isinstance(data, dict) else data
        result = []
        seen = set()
        for raw in raw_paths:
            if not isinstance(raw, str) or not raw.lower().endswith(".vst3"):
                continue
            key = os.path.normcase(os.path.abspath(raw))
            if key in seen:
                continue
            seen.add(key)
            result.append(raw)
        return result
    except Exception:
        return []


def _save_vst_cache(paths: list[str]) -> None:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        VST_CACHE_FILE.write_text(
            json.dumps({"version": 1, "paths": paths}, indent=2),
            encoding="utf-8",
        )
    except Exception as exc:
        print(f"WARNING: could not save VST cache: {exc}", file=sys.stderr)


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------

_DARK  = "#1a1c20"
_PANEL = "#22252b"
_CARD  = "#2a2e36"
_ACCENT = "#5b8fff"
_ACCENT2 = "#c084fc"
_TEXT  = "#e8eaf0"
_MUTED = "#7a7f8e"
_GREEN = "#4ade80"
_RED   = "#f87171"
_AMBER = "#fbbf24"
_BORDER = "#3a3f4b"
_FONT_MONO = ("Courier New", 9)
_FONT_BODY = ("Segoe UI", 10) if sys.platform == "win32" else ("Helvetica Neue", 10)
_FONT_HEAD = ("Segoe UI Semibold", 11) if sys.platform == "win32" else ("Helvetica Neue", 11)
_FONT_TITLE = ("Segoe UI Bold", 13) if sys.platform == "win32" else ("Helvetica Neue", 13)


class VSTHostApp(tk.Tk):
    def __init__(
        self,
        in_wav: str,
        out_wav: str,
        plugin_path: str = "",
        tail_seconds: float = 1.0,
        buffer_size: int = 8192,
        param_string: str = "",
        prefs_output_path: str = "",
    ) -> None:
        super().__init__()

        self._in_wav      = in_wav
        self._out_wav     = out_wav
        self._exit_code   = 0
        self._prefs_output_path = prefs_output_path

        # Keep one VST instance alive for native-editor changes, audition, and
        # the final render. All plugin interaction stays on the Tk main thread.
        self._plugin_obj = None
        self._plugin_obj_path = ""
        self._native_editor_used = False
        self._preview_thread = None
        self._preview_stop = threading.Event()

        # VST3 catalog: friendly display name -> full plugin path. The cache is
        # populated by filesystem scanning only; plugins are not loaded here.
        self._vst_paths: list[str] = _load_vst_cache()
        self._vst_cache_available = bool(self._vst_paths)
        self._vst_label_to_path: Dict[str, str] = {}
        self._vst_path_to_label: Dict[str, str] = {}
        self._vst_scan_thread = None

        # Native VST editor runs in a SEPARATE Python process. This keeps the
        # Tk host responsive even when Pedalboard/JUCE blocks inside show_editor().
        # The child returns plugin.raw_state when it exits, so GUI edits are
        # transferred back to the main plugin instance.
        self._editor_proc = None
        self._editor_close_file = None
        self._editor_state_in = None
        self._editor_state_out = None
        self._editor_force_job = None

        # ── Load saved config and merge with CLI args ──────────────────────
        cfg = _load_config()
        self._plugin_path = plugin_path  or cfg.get("plugin_path", "")
        self._tail        = tail_seconds if tail_seconds != 1.0 else float(cfg.get("tail_seconds", 1.0))
        self._buf         = buffer_size  if buffer_size  != 8192 else int(cfg.get("buffer_size",  8192))
        self._params      = param_string or cfg.get("param_string", "")

        # ── Window ──────────────────────────────────────────────────────────
        self.title("VST Host v1.6")
        self.configure(bg=_DARK)
        self.resizable(True, True)
        self.minsize(600, 500)

        self._build_style()
        self._build_ui()
        self._populate_vst_choices(self._vst_paths, self._plugin_path)
        self._center_window(780, 700)

        # First run: discover plugins automatically. Later runs use the cache
        # immediately; Scan VSTs refreshes it on demand after installations.
        if not self._vst_cache_available:
            self.after(250, lambda: self._scan_vsts(auto=True))

        self.protocol("WM_DELETE_WINDOW", self._on_cancel)
        self.bind("<Escape>", lambda _event: self._on_cancel())

    # ── Style ────────────────────────────────────────────────────────────────

    def _build_style(self) -> None:
        s = ttk.Style(self)
        s.theme_use("clam")
        s.configure(".",
                     background=_DARK, foreground=_TEXT,
                     fieldbackground=_CARD, bordercolor=_BORDER,
                     troughcolor=_PANEL, selectbackground=_ACCENT,
                     selectforeground=_DARK, font=_FONT_BODY)
        s.configure("TFrame",  background=_DARK)
        s.configure("Card.TFrame", background=_CARD,
                     relief="flat", borderwidth=1)
        s.configure("TLabel", background=_DARK, foreground=_TEXT, font=_FONT_BODY)
        s.configure("Muted.TLabel", background=_DARK, foreground=_MUTED, font=_FONT_BODY)
        s.configure("Head.TLabel", background=_DARK, foreground=_TEXT, font=_FONT_HEAD)
        s.configure("Title.TLabel", background=_DARK, foreground=_TEXT, font=_FONT_TITLE)
        s.configure("Accent.TLabel", background=_DARK, foreground=_ACCENT, font=_FONT_BODY)
        s.configure("TEntry",
                     fieldbackground=_CARD, foreground=_TEXT,
                     insertcolor=_TEXT, bordercolor=_BORDER,
                     lightcolor=_BORDER, darkcolor=_BORDER, font=_FONT_BODY)
        s.configure("TCombobox",
                     fieldbackground=_CARD, foreground=_TEXT,
                     bordercolor=_BORDER, arrowcolor=_MUTED, font=_FONT_BODY)
        s.map("TCombobox", fieldbackground=[("readonly", _CARD)])
        s.configure("TButton",
                     background=_PANEL, foreground=_TEXT,
                     bordercolor=_BORDER, padding=(10, 5),
                     relief="flat", font=_FONT_BODY)
        s.map("TButton",
              background=[("active", _CARD), ("pressed", _BORDER)],
              foreground=[("active", _TEXT)])
        s.configure("Process.TButton",
                     background=_ACCENT, foreground=_DARK,
                     bordercolor=_ACCENT, font=_FONT_HEAD, padding=(14, 7))
        s.map("Process.TButton",
              background=[("active", "#7aaaff"), ("pressed", "#3a6fde")],
              foreground=[("active", _DARK)])
        s.configure("Cancel.TButton",
                     background=_PANEL, foreground=_MUTED,
                     bordercolor=_BORDER, padding=(10, 5))
        s.configure("TSeparator", background=_BORDER)
        s.configure("TSpinbox",
                     fieldbackground=_CARD, foreground=_TEXT,
                     bordercolor=_BORDER, arrowcolor=_MUTED, font=_FONT_BODY)

    # ── UI ──────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=16)
        root.pack(fill="both", expand=True)
        root.columnconfigure(0, weight=1)

        # Title row
        title_row = ttk.Frame(root)
        title_row.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        ttk.Label(title_row, text="VST  HOST", style="Title.TLabel").pack(side="left")

        # Keep a close control at the TOP of the window so it remains reachable
        # even when the bottom action row is obscured by a small screen/taskbar.
        ttk.Button(title_row, text="Close", style="Cancel.TButton",
                   command=self._on_cancel).pack(side="right")
        self._close_editor_top_btn = ttk.Button(
            title_row, text="CLOSE VST", style="Process.TButton",
            command=self._close_native_editor)
        self._close_editor_top_btn.pack(side="right", padx=(0, 8))
        self._close_editor_top_btn.state(["disabled"])
        lbl_mode = ttk.Label(title_row, text="OFFLINE", style="Accent.TLabel")
        lbl_mode.pack(side="right", padx=(0, 10))

        ttk.Separator(root, orient="horizontal").grid(row=1, column=0, sticky="ew", pady=(0, 12))

        # ── I/O info (read-only) ─────────────────────────────────────────────
        io_card = ttk.Frame(root, style="Card.TFrame", padding=10)
        io_card.grid(row=2, column=0, sticky="ew", pady=(0, 10))
        io_card.columnconfigure(1, weight=1)

        ttk.Label(io_card, text="Input WAV",  style="Muted.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 12))
        ttk.Label(io_card, text=self._in_wav,  foreground=_TEXT,
                  background=_CARD, font=_FONT_MONO, wraplength=500,
                  anchor="w").grid(row=0, column=1, sticky="ew")

        ttk.Label(io_card, text="Output WAV", style="Muted.TLabel").grid(row=1, column=0, sticky="w", padx=(0, 12))
        ttk.Label(io_card, text=self._out_wav, foreground=_TEXT,
                  background=_CARD, font=_FONT_MONO, wraplength=500,
                  anchor="w").grid(row=1, column=1, sticky="ew")

        # ── Plugin selection ─────────────────────────────────────────────────
        ttk.Label(root, text="VST3 Plugin", style="Head.TLabel").grid(
            row=3, column=0, sticky="w", pady=(8, 2))

        plugin_row = ttk.Frame(root)
        plugin_row.grid(row=4, column=0, sticky="ew")
        plugin_row.columnconfigure(0, weight=1)

        # _plugin_var always stores the real full path. The combobox displays a
        # compact friendly label, so the rest of the host can keep using paths.
        self._plugin_var = tk.StringVar(value=self._plugin_path)
        self._plugin_choice_var = tk.StringVar()
        self._plugin_combo = ttk.Combobox(
            plugin_row,
            textvariable=self._plugin_choice_var,
            values=[],
            state="readonly",
            width=48,
        )
        self._plugin_combo.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self._plugin_combo.bind("<<ComboboxSelected>>", self._on_plugin_selected)

        self._scan_vsts_btn = ttk.Button(plugin_row, text="Scan VSTs",
                                         command=self._scan_vsts)
        self._scan_vsts_btn.grid(row=0, column=1)
        self._browse_btn = ttk.Button(plugin_row, text="Browse...",
                                      command=self._browse_plugin)
        self._browse_btn.grid(row=0, column=2, padx=(4, 0))

        plugin_actions = ttk.Frame(plugin_row)
        plugin_actions.grid(row=1, column=0, columnspan=3, sticky="ew", pady=(5, 0))
        ttk.Button(plugin_actions, text="Scan Params",
                   command=self._scan_params).pack(side="left")
        self._open_editor_btn = ttk.Button(plugin_actions, text="Open Plugin UI",
                                           command=self._open_native_editor)
        self._open_editor_btn.pack(side="left", padx=(4, 0))
        self._close_editor_btn = ttk.Button(plugin_actions, text="Close VST UI",
                                            style="Cancel.TButton",
                                            command=self._close_native_editor)
        self._close_editor_btn.pack(side="left", padx=(4, 0))
        self._close_editor_btn.state(["disabled"])

        self._plugin_path_display_var = tk.StringVar(value=self._plugin_path or "No plugin selected")
        ttk.Label(plugin_row, textvariable=self._plugin_path_display_var,
                  style="Muted.TLabel", font=_FONT_MONO, wraplength=690,
                  anchor="w").grid(row=2, column=0, columnspan=3,
                                   sticky="ew", pady=(4, 0))

        # ── Tail / Buffer ────────────────────────────────────────────────────
        num_row = ttk.Frame(root)
        num_row.grid(row=5, column=0, sticky="ew", pady=(10, 0))
        num_row.columnconfigure(1, weight=1)
        num_row.columnconfigure(3, weight=1)

        ttk.Label(num_row, text="Tail Seconds", style="Head.TLabel").grid(
            row=0, column=0, sticky="w", padx=(0, 8))
        self._tail_var = tk.DoubleVar(value=self._tail)
        tail_spin = ttk.Spinbox(num_row, from_=0.0, to=30.0, increment=0.1,
                                textvariable=self._tail_var, width=8, format="%.2f")
        tail_spin.grid(row=0, column=1, sticky="w")

        ttk.Label(num_row, text="Buffer Size", style="Head.TLabel").grid(
            row=0, column=2, sticky="w", padx=(20, 8))
        self._buf_var = tk.IntVar(value=self._buf)
        buf_combo = ttk.Combobox(num_row, textvariable=self._buf_var,
                                 values=[256, 512, 1024, 2048, 4096, 8192, 16384, 32768],
                                 width=8, state="normal")
        buf_combo.grid(row=0, column=3, sticky="w")

        # ── Parameters ───────────────────────────────────────────────────────
        ttk.Label(root, text="Plugin Parameters", style="Head.TLabel").grid(
            row=6, column=0, sticky="w", pady=(10, 2))
        ttk.Label(root,
                  text="name=value, name=value  (leave blank for plugin defaults)",
                  style="Muted.TLabel").grid(row=7, column=0, sticky="w", pady=(0, 4))
        self._params_var = tk.StringVar(value=self._params)
        self._params_var.trace_add("write", self._on_text_params_changed)
        ttk.Entry(root, textvariable=self._params_var, font=_FONT_MONO).grid(
            row=8, column=0, sticky="ew")

        # Audition is render-then-play, not background VST processing: the VST
        # itself is processed on this main thread, then only the finished audio
        # buffer is handed to a playback thread.
        audition_row = ttk.Frame(root)
        audition_row.grid(row=9, column=0, sticky="ew", pady=(8, 0))
        ttk.Label(audition_row, text="Native editor state is kept for audition/process.",
                  style="Muted.TLabel").pack(side="left")
        self._stop_btn = ttk.Button(audition_row, text="Stop", command=self._stop_audition)
        self._stop_btn.pack(side="right")
        self._audition_btn = ttk.Button(audition_row, text="Audition 8 s",
                                        command=self._on_audition)
        self._audition_btn.pack(side="right", padx=(0, 6))

        # ── Presets ───────────────────────────────────────────────────────────
        preset_row = ttk.Frame(root)
        preset_row.grid(row=10, column=0, sticky="ew", pady=(8, 0))

        ttk.Label(preset_row, text="Preset:", style="Muted.TLabel").pack(side="left", padx=(0, 6))
        self._preset_var = tk.StringVar()
        self._preset_cb  = ttk.Combobox(preset_row, textvariable=self._preset_var,
                                         values=_list_presets(), width=22)
        self._preset_cb.pack(side="left")
        ttk.Button(preset_row, text="Load",  command=self._load_preset).pack(side="left", padx=(4, 0))
        ttk.Button(preset_row, text="Save...", command=self._save_preset).pack(side="left", padx=(4, 0))

        # ── Log ───────────────────────────────────────────────────────────────
        ttk.Label(root, text="Log", style="Head.TLabel").grid(
            row=11, column=0, sticky="w", pady=(12, 2))
        self._log = scrolledtext.ScrolledText(
            root, height=8, font=_FONT_MONO,
            bg=_PANEL, fg=_TEXT, insertbackground=_TEXT,
            selectbackground=_ACCENT, selectforeground=_DARK,
            relief="flat", borderwidth=1,
            highlightbackground=_BORDER, highlightthickness=1,
            state="disabled")
        self._log.grid(row=12, column=0, sticky="nsew", pady=(0, 10))
        root.rowconfigure(12, weight=1)

        # ── Status bar ───────────────────────────────────────────────────────
        self._status_var = tk.StringVar(value="Ready")
        self._status_lbl = ttk.Label(root, textvariable=self._status_var,
                                     style="Muted.TLabel")
        self._status_lbl.grid(row=13, column=0, sticky="w")

        # ── Action buttons ────────────────────────────────────────────────────
        btn_row = ttk.Frame(root)
        btn_row.grid(row=14, column=0, sticky="e", pady=(10, 0))

        self._cancel_btn = ttk.Button(btn_row, text="Cancel",
                                      style="Cancel.TButton",
                                      command=self._on_cancel)
        self._cancel_btn.pack(side="left", padx=(0, 8))

        self._process_btn = ttk.Button(btn_row, text="Process",
                                       style="Process.TButton",
                                       command=self._on_process)
        self._process_btn.pack(side="left")

    # ── Helpers ──────────────────────────────────────────────────────────────

    def _center_window(self, w: int, h: int) -> None:
        """Center the host inside the usable desktop area, never off-screen."""
        self.update_idletasks()

        left = top = 0
        work_w = int(self.winfo_screenwidth())
        work_h = int(self.winfo_screenheight())

        # On Windows, exclude the taskbar from the usable work area. This also
        # avoids a common DPI/taskbar case where the bottom buttons are hidden.
        if sys.platform == "win32":
            try:
                import ctypes

                class RECT(ctypes.Structure):
                    _fields_ = [
                        ("left", ctypes.c_long),
                        ("top", ctypes.c_long),
                        ("right", ctypes.c_long),
                        ("bottom", ctypes.c_long),
                    ]

                rect = RECT()
                SPI_GETWORKAREA = 0x0030
                ok = ctypes.windll.user32.SystemParametersInfoW(
                    SPI_GETWORKAREA, 0, ctypes.byref(rect), 0)
                if ok:
                    left, top = int(rect.left), int(rect.top)
                    work_w = int(rect.right - rect.left)
                    work_h = int(rect.bottom - rect.top)
            except Exception:
                pass

        margin = 24
        fit_w = max(560, min(int(w), max(560, work_w - 2 * margin)))
        fit_h = max(460, min(int(h), max(460, work_h - 2 * margin)))
        x = left + max(margin, (work_w - fit_w) // 2)
        y = top + max(margin, (work_h - fit_h) // 2)
        self.geometry(f"{fit_w}x{fit_h}+{x}+{y}")

    def _log_append(self, text: str) -> None:
        self._log.configure(state="normal")
        self._log.insert("end", text.rstrip("\n") + "\n")
        self._log.see("end")
        self._log.configure(state="disabled")
        self.update_idletasks()

    def _set_status(self, text: str, color: str = _MUTED) -> None:
        self._status_var.set(text)
        self._status_lbl.configure(foreground=color)
        self.update_idletasks()

    def _current_settings(self) -> Dict[str, Any]:
        return {
            "plugin_path":  self._plugin_var.get().strip(),
            "tail_seconds": self._tail_var.get(),
            "buffer_size":  int(self._buf_var.get()),
            "param_string": self._params_var.get().strip(),
        }

    def _on_text_params_changed(self, *_args) -> None:
        # If the user types host parameters after closing the native editor,
        # those explicit assignments become authoritative again. Other native
        # settings on the same plugin instance are still preserved.
        if self._native_editor_used:
            self._native_editor_used = False
            self._set_status("Text parameters changed; they will be applied on next audition/process.", _MUTED)

    # ── VST3 catalog / selection ──────────────────────────────────────────────

    @staticmethod
    def _plugin_key(path: str) -> str:
        return os.path.normcase(os.path.abspath(path))

    def _populate_vst_choices(self, paths: list[str], selected_path: str = "") -> None:
        """Build unique friendly labels while preserving exact plugin paths."""
        unique_paths: list[str] = []
        seen = set()
        for raw in paths:
            if not raw or not raw.lower().endswith(".vst3"):
                continue
            key = self._plugin_key(raw)
            if key in seen:
                continue
            seen.add(key)
            unique_paths.append(raw)

        if selected_path and selected_path.lower().endswith(".vst3"):
            key = self._plugin_key(selected_path)
            if key not in seen:
                unique_paths.append(selected_path)
                seen.add(key)

        unique_paths.sort(key=lambda p: (Path(p).stem.casefold(), p.casefold()))

        # Count duplicate stem names first. For duplicates show parent/vendor.
        counts: Dict[str, int] = {}
        for path in unique_paths:
            stem = Path(path).stem
            counts[stem.casefold()] = counts.get(stem.casefold(), 0) + 1

        label_to_path: Dict[str, str] = {}
        path_to_label: Dict[str, str] = {}
        for path in unique_paths:
            p = Path(path)
            stem = p.stem
            if counts.get(stem.casefold(), 0) > 1:
                parent = p.parent.name or str(p.parent)
                base_label = f"{stem} — {parent}"
            else:
                base_label = stem

            label = base_label
            suffix = 2
            while label in label_to_path and self._plugin_key(label_to_path[label]) != self._plugin_key(path):
                label = f"{base_label} [{suffix}]"
                suffix += 1

            label_to_path[label] = path
            path_to_label[self._plugin_key(path)] = label

        self._vst_paths = unique_paths
        self._vst_label_to_path = label_to_path
        self._vst_path_to_label = path_to_label
        labels = list(label_to_path.keys())
        self._plugin_combo.configure(values=labels)

        current = selected_path or self._plugin_var.get().strip()
        if current:
            label = path_to_label.get(self._plugin_key(current), Path(current).stem)
            self._plugin_choice_var.set(label)
            self._plugin_path_display_var.set(current)
        elif labels:
            self._select_plugin_path(label_to_path[labels[0]], add_to_catalog=False)
        else:
            self._plugin_choice_var.set("")
            self._plugin_path_display_var.set("No VST3 plugins found yet")

    def _select_plugin_path(self, path: str, add_to_catalog: bool = True) -> None:
        path = str(Path(path))
        old_path = self._plugin_var.get().strip()
        if old_path and self._plugin_key(old_path) != self._plugin_key(path):
            self._invalidate_plugin()

        if add_to_catalog and path.lower().endswith(".vst3"):
            paths = list(self._vst_paths)
            if all(self._plugin_key(p) != self._plugin_key(path) for p in paths):
                paths.append(path)
            self._populate_vst_choices(paths, path)
        else:
            self._plugin_var.set(path)
            self._plugin_path_display_var.set(path)
            label = self._vst_path_to_label.get(self._plugin_key(path), Path(path).stem)
            self._plugin_choice_var.set(label)

        self._plugin_var.set(path)
        self._plugin_path_display_var.set(path)

    def _on_plugin_selected(self, _event=None) -> None:
        label = self._plugin_choice_var.get().strip()
        path = self._vst_label_to_path.get(label)
        if not path:
            return
        self._select_plugin_path(path, add_to_catalog=False)
        self._set_status(f"Selected VST: {Path(path).stem}", _GREEN)
        self._log_append(f"Selected VST: {path}")

    def _scan_vsts(self, auto: bool = False) -> None:
        """Refresh the VST3 catalog in a filesystem-only worker thread."""
        if self._vst_scan_thread is not None and self._vst_scan_thread.is_alive():
            return
        if self._editor_is_open():
            if not auto:
                messagebox.showwarning("VST Editor Open", "Close the VST editor before rescanning plugins.")
            return

        selected = self._plugin_var.get().strip()
        self._scan_vsts_btn.state(["disabled"])
        self._set_status("Scanning installed VST3 plugins...", _AMBER)
        if not auto:
            self._log_append("=== Scanning installed VST3 plugins ===")

        def worker() -> None:
            try:
                paths, roots = _scan_vst3_paths([selected] if selected else None)
                self.after(0, lambda: self._finish_vst_scan(paths, roots, selected, None))
            except Exception as exc:
                self.after(0, lambda e=exc: self._finish_vst_scan([], [], selected, str(e)))

        self._vst_scan_thread = threading.Thread(target=worker, daemon=True, name="VST3Scanner")
        self._vst_scan_thread.start()

    def _finish_vst_scan(self, paths: list[str], roots: list[str], selected: str,
                         error: Optional[str]) -> None:
        self._scan_vsts_btn.state(["!disabled"])
        if error:
            self._set_status("VST scan failed.", _RED)
            self._log_append(f"ERROR scanning VST3 plugins: {error}")
            return

        # Keep an explicitly selected custom plugin even if its folder could not
        # be traversed during this scan.
        if selected and selected.lower().endswith(".vst3"):
            if all(self._plugin_key(p) != self._plugin_key(selected) for p in paths):
                paths.append(selected)

        self._populate_vst_choices(paths, selected)
        _save_vst_cache(self._vst_paths)
        self._set_status(f"Found {len(self._vst_paths)} VST3 plugin(s).", _GREEN)
        self._log_append(f"VST3 scan complete: {len(self._vst_paths)} plugin(s).")
        for root in roots:
            self._log_append(f"  scanned: {root}")

    # ── Browse ────────────────────────────────────────────────────────────────

    def _browse_plugin(self) -> None:
        path = filedialog.askopenfilename(
            title="Select VST3 Plugin",
            filetypes=[("VST3 Plugin", "*.vst3"), ("All files", "*.*")])
        if path:
            self._select_plugin_path(path, add_to_catalog=True)
            _save_vst_cache(self._vst_paths)
            self._set_status(f"Selected VST: {Path(path).stem}", _GREEN)

    def _invalidate_plugin(self) -> None:
        self._plugin_obj = None
        self._plugin_obj_path = ""
        self._native_editor_used = False

    def _ensure_plugin_loaded(self, apply_text_params: bool = True):
        plugin_path = self._plugin_var.get().strip()
        if not plugin_path:
            raise ValueError("Select a VST3 plugin first.")
        if not os.path.exists(plugin_path):
            raise FileNotFoundError(f"Plugin not found: {plugin_path}")

        if self._plugin_obj is None or self._plugin_obj_path != plugin_path:
            _check_dependencies()
            from pedalboard import load_plugin
            self._set_status("Loading plugin...", _AMBER)
            self.update_idletasks()
            self._plugin_obj = load_plugin(plugin_path)
            self._plugin_obj_path = plugin_path
            self._native_editor_used = False
            self._log_append(f"Loaded: {self._plugin_obj}")

        if apply_text_params and not self._native_editor_used:
            _apply_param_assignments(self._plugin_obj, self._params_var.get().strip(), self._log_append)
        return self._plugin_obj

    # ── Native VST editor ────────────────────────────────────────────────────

    def _editor_is_open(self) -> bool:
        return self._editor_proc is not None and self._editor_proc.poll() is None

    def _set_editor_buttons(self, is_open: bool) -> None:
        if is_open:
            self._open_editor_btn.state(["disabled"])
            self._close_editor_btn.state(["!disabled"])
            self._close_editor_top_btn.state(["!disabled"])
            self._plugin_combo.state(["disabled"])
            self._scan_vsts_btn.state(["disabled"])
            self._browse_btn.state(["disabled"])
        else:
            self._open_editor_btn.state(["!disabled"])
            self._close_editor_btn.state(["disabled"])
            self._close_editor_top_btn.state(["disabled"])
            self._plugin_combo.configure(state="readonly")
            if not (self._vst_scan_thread is not None and self._vst_scan_thread.is_alive()):
                self._scan_vsts_btn.state(["!disabled"])
            self._browse_btn.state(["!disabled"])

    def _open_native_editor(self) -> None:
        """Open the native VST UI in a child process.

        Pedalboard's show_editor() must run on the thread that loaded the plugin
        and blocks that thread until the editor closes. Running a dedicated
        worker process means the Tk host NEVER becomes blocked by the VST UI.
        The worker receives the current raw_state, opens the editor, then writes
        raw_state back when the window closes.
        """
        if self._editor_is_open():
            self._set_status("VST editor is already open.", _AMBER)
            return

        try:
            plugin = self._ensure_plugin_loaded(apply_text_params=True)
            if not hasattr(plugin, "show_editor"):
                raise RuntimeError("This plugin/host build does not expose a native editor.")

            # Start from exactly the state currently held by the host.
            try:
                state_bytes = bytes(plugin.raw_state)
            except Exception as exc:
                raise RuntimeError(f"Cannot read plugin state before opening editor: {exc}")

            ipc_dir = CONFIG_DIR / "editor_ipc"
            ipc_dir.mkdir(parents=True, exist_ok=True)
            token = f"{os.getpid()}_{time.time_ns()}"
            state_in = ipc_dir / f"{token}.in.state"
            state_out = ipc_dir / f"{token}.out.state"
            close_file = ipc_dir / f"{token}.close"
            state_in.write_bytes(state_bytes)
            for p in (state_out, close_file):
                try:
                    p.unlink()
                except FileNotFoundError:
                    pass

            worker_args = [
                sys.executable, os.path.abspath(__file__),
                "--editor-worker",
                self._plugin_var.get().strip(),
                str(state_in), str(state_out), str(close_file),
            ]
            creationflags = 0
            if sys.platform == "win32":
                creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

            self._editor_proc = subprocess.Popen(
                worker_args,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=creationflags,
            )
            self._editor_state_in = state_in
            self._editor_state_out = state_out
            self._editor_close_file = close_file
            self._set_editor_buttons(True)
            self._set_status("VST editor open. Use CLOSE VST in this window to close it.", _ACCENT2)
            self._log_append("Native VST editor opened in isolated worker process.")
            self.after(100, self._poll_editor_process)
        except Exception as exc:
            self._set_editor_buttons(False)
            self._set_status("Could not open plugin editor.", _RED)
            self._log_append(f"ERROR opening native editor: {exc}")
            messagebox.showerror("Plugin UI", str(exc))

    def _close_native_editor(self) -> None:
        """Request a clean editor close, then force-kill the child if needed."""
        if not self._editor_is_open():
            self._set_editor_buttons(False)
            return

        self._set_status("Closing VST editor...", _AMBER)
        self._log_append("Close VST requested.")
        try:
            if self._editor_close_file is not None:
                self._editor_close_file.write_text("close\n", encoding="utf-8")
        except Exception as exc:
            self._log_append(f"WARNING: could not signal editor cleanly: {exc}")

        # The child normally exits immediately after Event.set(). If the plugin
        # ignores/hangs during close, terminate the isolated process. Because the
        # VST UI lives only in that child, this guarantees the stuck window goes.
        if self._editor_force_job is not None:
            try:
                self.after_cancel(self._editor_force_job)
            except Exception:
                pass
        self._editor_force_job = self.after(1500, self._force_close_editor_process)

    def _force_close_editor_process(self) -> None:
        self._editor_force_job = None
        proc = self._editor_proc
        if proc is not None and proc.poll() is None:
            self._log_append("VST editor did not close cleanly; terminating isolated editor process.")
            try:
                proc.terminate()
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

    def _poll_editor_process(self) -> None:
        proc = self._editor_proc
        if proc is None:
            return
        if proc.poll() is None:
            self.after(100, self._poll_editor_process)
            return

        rc = proc.returncode
        if self._editor_force_job is not None:
            try:
                self.after_cancel(self._editor_force_job)
            except Exception:
                pass
            self._editor_force_job = None

        imported = False
        try:
            if self._editor_state_out is not None and self._editor_state_out.exists():
                new_state = self._editor_state_out.read_bytes()
                if new_state:
                    plugin = self._ensure_plugin_loaded(apply_text_params=False)
                    plugin.raw_state = new_state
                    self._native_editor_used = True
                    imported = True
        except Exception as exc:
            self._log_append(f"WARNING: could not import edited VST state: {exc}")

        if imported:
            self._set_status("VST editor closed; edited state imported.", _GREEN)
            self._log_append("Native editor closed; GUI state transferred back to host.")
        elif rc == 0:
            self._set_status("VST editor closed.", _GREEN)
            self._log_append("Native editor closed; no state data was returned.")
        else:
            self._set_status("VST editor was force-closed; previous host state retained.", _AMBER)
            self._log_append(f"Native editor worker exited with code {rc}; previous state retained.")

        for p in (self._editor_state_in, self._editor_state_out, self._editor_close_file):
            if p is not None:
                try:
                    p.unlink()
                except Exception:
                    pass

        self._editor_proc = None
        self._editor_state_in = None
        self._editor_state_out = None
        self._editor_close_file = None
        self._set_editor_buttons(False)

    # ── Audition ─────────────────────────────────────────────────────────────

    def _on_audition(self) -> None:
        if self._editor_is_open():
            messagebox.showwarning("VST Editor Open",
                                   "Close the VST editor first so its latest settings can be imported.")
            return
        if self._preview_thread is not None and self._preview_thread.is_alive():
            self._stop_audition()
        try:
            plugin = self._ensure_plugin_loaded(apply_text_params=not self._native_editor_used)
            settings = self._current_settings()
            from pedalboard.io import AudioFile
            import numpy as np

            with AudioFile(self._in_wav) as f:
                sr = float(f.samplerate)
                frames = min(int(round(sr * 8.0)), int(f.frames))
                audio = f.read(frames)
                num_channels = int(f.num_channels)

            self._set_status("Rendering audition...", _AMBER)
            self.update_idletasks()
            _reset_plugin_state(plugin, self._log_append)
            preview = plugin(audio, sr, buffer_size=settings["buffer_size"], reset=False)

            # Include a short tail, capped at 2 s so audition stays immediate.
            preview_tail = min(max(float(settings["tail_seconds"]), 0.0), 2.0)
            if preview_tail > 0:
                silence = np.zeros((num_channels, int(round(preview_tail * sr))), dtype=np.float32)
                tail = plugin(silence, sr, buffer_size=settings["buffer_size"], reset=False)
                preview = np.concatenate([preview, tail], axis=1)

            self._start_preview_playback(preview.astype(np.float32, copy=False), sr)
        except Exception as exc:
            self._set_status("Audition failed.", _RED)
            self._log_append(f"ERROR audition: {exc}")
            messagebox.showerror("Audition Failed", str(exc))

    def _start_preview_playback(self, audio, sample_rate: float) -> None:
        self._preview_stop.clear()
        self._audition_btn.state(["disabled"])
        self._set_status("Audition playing...", _GREEN)

        def worker() -> None:
            try:
                from pedalboard.io import AudioStream, StreamResampler
                import numpy as np

                # Pedalboard >= 0.9 uses output_device_name (not output_device).
                # Passing its reported default device name is more robust than
                # the legacy string "default" on Windows audio backends.
                output_name = getattr(AudioStream, "default_output_device_name", None)
                with AudioStream(output_device_name=output_name) as stream:
                    device_sr = float(stream.sample_rate)
                    data = audio
                    if abs(device_sr - sample_rate) > 0.5:
                        rs = StreamResampler(float(sample_rate), device_sr, int(audio.shape[0]))
                        parts = [rs.process(audio), rs.process()]
                        data = np.concatenate([p for p in parts if p.size], axis=1)
                    chunk = 2048
                    for pos in range(0, data.shape[1], chunk):
                        if self._preview_stop.is_set():
                            break
                        stream.write(data[:, pos:pos + chunk], device_sr)
            except Exception as exc:
                self.after(0, lambda e=exc: self._preview_failed(str(e)))
                return
            self.after(0, self._preview_finished)

        self._preview_thread = threading.Thread(target=worker, daemon=True)
        self._preview_thread.start()

    def _stop_audition(self) -> None:
        self._preview_stop.set()
        self._set_status("Stopping audition...", _MUTED)

    def _preview_finished(self) -> None:
        self._audition_btn.state(["!disabled"])
        self._set_status("Audition stopped." if self._preview_stop.is_set() else "Audition finished.", _GREEN)

    def _preview_failed(self, msg: str) -> None:
        self._audition_btn.state(["!disabled"])
        self._set_status("Playback failed.", _RED)
        self._log_append(f"ERROR playback: {msg}")

    # ── Scan params ──────────────────────────────────────────────────────────

    def _scan_params(self) -> None:
        plugin_path = self._plugin_var.get().strip()
        if not plugin_path:
            messagebox.showwarning("No Plugin", "Select or browse to a VST3 plugin first.")
            return
        try:
            self._set_status("Scanning parameters...", _AMBER)
            self._log_append(f"=== Scanning: {plugin_path} ===")
            plugin = self._ensure_plugin_loaded(apply_text_params=False)
            params = list(plugin.parameters.keys()) if hasattr(plugin, "parameters") else []
            lines = [f"{'Name':<45} {'Min':>10} {'Max':>10} {'Default':>10} {'Current':>10}",
                     "-" * 90]
            for name in params:
                def fmt(v: Any) -> str:
                    try:
                        return f"{float(v):>10.4g}"
                    except (TypeError, ValueError):
                        return f"{str(v):>10}"
                try:
                    p = plugin.parameters[name]
                    mn = getattr(p, "min_value", "?")
                    mx = getattr(p, "max_value", "?")
                    df = getattr(p, "default_value", "?")
                    cur = getattr(plugin, name, "?")
                    lines.append(f"  {name:<45}{fmt(mn)}{fmt(mx)}{fmt(df)}{fmt(cur)}")
                except Exception as exc:
                    lines.append(f"  {name:<45}  (error: {exc})")
            self._scan_done("\n".join(lines), None)
        except Exception as exc:
            self._scan_done(None, str(exc))

    def _scan_done(self, result: Optional[str], error: Optional[str]) -> None:
        self._process_btn.state(["!disabled"])
        if error:
            self._log_append(f"ERROR: {error}")
            self._set_status("Scan failed.", _RED)
        else:
            self._log_append(result or "")
            self._set_status("Scan complete.", _GREEN)

    # ── Presets ───────────────────────────────────────────────────────────────

    def _load_preset(self) -> None:
        name = self._preset_var.get().strip()
        if not name:
            messagebox.showwarning("Preset", "Select a preset name first.")
            return
        data = _load_preset(name)
        if data is None:
            messagebox.showerror("Preset", f"Preset '{name}' not found.")
            return
        if "plugin_path"  in data: self._select_plugin_path(data["plugin_path"], add_to_catalog=True)
        if "tail_seconds" in data: self._tail_var.set(float(data["tail_seconds"]))
        if "buffer_size"  in data: self._buf_var.set(int(data["buffer_size"]))
        if "param_string" in data: self._params_var.set(data["param_string"])
        self._set_status(f"Loaded preset: {name}", _GREEN)
        self._log_append(f"Loaded preset: {name}")

    def _save_preset(self) -> None:
        win = tk.Toplevel(self)
        win.title("Save Preset")
        win.configure(bg=_DARK)
        win.resizable(False, False)
        win.grab_set()

        ttk.Label(win, text="Preset name:").pack(padx=16, pady=(14, 4), anchor="w")
        name_var = tk.StringVar(value=self._preset_var.get())
        ttk.Entry(win, textvariable=name_var, width=30).pack(padx=16, pady=(0, 10))

        def do_save() -> None:
            name = name_var.get().strip()
            if not name:
                messagebox.showwarning("Preset", "Enter a name.", parent=win)
                return
            _save_preset(name, self._current_settings())
            self._preset_cb.configure(values=_list_presets())
            self._preset_var.set(name)
            self._log_append(f"Saved preset: {name}")
            self._set_status(f"Saved preset: {name}", _GREEN)
            win.destroy()

        btn_row = ttk.Frame(win)
        btn_row.pack(padx=16, pady=(0, 14), fill="x")
        ttk.Button(btn_row, text="Cancel", command=win.destroy).pack(side="right", padx=(4, 0))
        ttk.Button(btn_row, text="Save", style="Process.TButton",
                   command=do_save).pack(side="right")

    # ── Process ───────────────────────────────────────────────────────────────

    def _on_process(self) -> None:
        if self._editor_is_open():
            messagebox.showwarning("VST Editor Open",
                                   "Close the VST editor first so its latest settings can be imported.")
            return
        settings = self._current_settings()
        plugin_path = settings["plugin_path"]
        if not plugin_path:
            messagebox.showerror("No Plugin", "Select a VST3 plugin first.")
            return
        if not os.path.exists(plugin_path):
            messagebox.showerror("Plugin Not Found", f"Cannot find:\n{plugin_path}")
            return

        self._process_btn.state(["disabled"])
        self._cancel_btn.state(["disabled"])
        self._set_status("Loading plugin...", _AMBER)
        self._log_append("=== Processing ===")

        # Reuse the same main-thread plugin instance used by the native editor
        # and audition so GUI changes are preserved exactly.
        try:
            loaded_plugin = self._ensure_plugin_loaded(
                apply_text_params=not self._native_editor_used)
        except Exception as exc:
            self._process_failure(str(exc))
            return

        self._set_status("Processing...", _AMBER)

        # Run the render on the main thread (tkinter thread) so that the plugin
        # never crosses thread boundaries — which many VST3s forbid entirely.
        # We use after(0, …) so the UI can repaint once before the blocking call.
        def do_render() -> None:
            try:
                run_offline(
                    in_wav       = self._in_wav,
                    out_wav      = self._out_wav,
                    plugin_path  = plugin_path,
                    tail_seconds = settings["tail_seconds"],
                    buffer_size  = settings["buffer_size"],
                    param_string = settings["param_string"],
                    dump_params  = False,
                    log          = self._log_append,
                    plugin       = loaded_plugin,
                    apply_params = not self._native_editor_used,
                )
                self._process_success()
            except Exception as exc:
                self._process_failure(str(exc))

        _save_config(settings)
        self.after(0, do_render)

    def _process_success(self) -> None:
        self._preview_stop.set()
        self._set_status("Done", _GREEN)
        self._log_append("=== Done ===")

        # When launched from Praat with "Save as default plugin", write the
        # plugin actually selected in this GUI, not the stale path passed at launch.
        if self._prefs_output_path:
            selected = self._plugin_var.get().strip()
            if selected:
                try:
                    prefs_path = Path(self._prefs_output_path)
                    prefs_path.parent.mkdir(parents=True, exist_ok=True)
                    prefs_path.write_text(selected + "\n", encoding="utf-8")
                    self._log_append(f"Saved default VST: {selected}")
                except Exception as exc:
                    self._log_append(f"WARNING: could not save default VST: {exc}")

        self._exit_code = 0
        self.after(600, self.destroy)

    def _process_failure(self, msg: str) -> None:
        self._process_btn.state(["!disabled"])
        self._cancel_btn.state(["!disabled"])
        self._set_status(f"Failed: {msg}", _RED)
        self._log_append(f"ERROR: {msg}")
        self._exit_code = 1
        messagebox.showerror("Processing Failed", msg)

    # ── Cancel ────────────────────────────────────────────────────────────────

    def _on_cancel(self) -> None:
        self._preview_stop.set()
        proc = self._editor_proc
        if proc is not None and proc.poll() is None:
            try:
                proc.terminate()
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        self._exit_code = 0
        self.destroy()


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

def _parse_args() -> Tuple[bool, list[str]]:
    """Return (gui_mode, remaining_args)."""
    args = sys.argv[1:]
    if args and args[0] == "--gui":
        return True, args[1:]
    return False, args


def _write_sentinel(path: str) -> None:
    """Write the sentinel file that unblocks Praat's polling loop."""
    if not path:
        return
    try:
        Path(path).write_text("done\n", encoding="utf-8")
    except Exception as exc:
        print(f"WARNING: could not write sentinel '{path}': {exc}", file=sys.stderr)


def _run_editor_worker(args: list[str]) -> int:
    """Run one native VST editor in an isolated process.

    Args: plugin_path state_in state_out close_request
    The polling thread turns the parent's close-request file into the
    threading.Event expected by Pedalboard.show_editor().
    """
    if len(args) != 4:
        print("Usage: --editor-worker plugin.vst3 state_in state_out close_request", file=sys.stderr)
        return 2

    plugin_path, state_in, state_out, close_request = args
    try:
        _check_dependencies()
        from pedalboard import load_plugin

        plugin = load_plugin(plugin_path)
        in_path = Path(state_in)
        if in_path.exists():
            state = in_path.read_bytes()
            if state:
                plugin.raw_state = state

        close_event = threading.Event()

        def watch_close_request() -> None:
            req = Path(close_request)
            while not close_event.is_set():
                if req.exists():
                    close_event.set()
                    return
                time.sleep(0.05)

        threading.Thread(target=watch_close_request, daemon=True,
                         name="VSTEditorCloseRequest").start()

        plugin.show_editor(close_event)
        close_event.set()

        try:
            Path(state_out).write_bytes(bytes(plugin.raw_state))
        except Exception as exc:
            print(f"WARNING: could not save editor state: {exc}", file=sys.stderr)
        return 0
    except Exception as exc:
        print(f"ERROR editor worker: {exc}", file=sys.stderr)
        return 1


def _run_gui(args: list[str]) -> int:
    # args: input.wav output.wav [plugin.vst3 [tail [buf [params [sentinel [prefs_output]]]]]]
    if len(args) < 2:
        _fail("GUI mode requires at least: --gui input.wav output.wav")
    in_wav    = args[0]
    out_wav   = args[1]
    plugin    = args[2] if len(args) >= 3 else ""
    tail      = float(args[3]) if len(args) >= 4 else 1.0
    buf       = int(args[4])   if len(args) >= 5 else 8192
    params    = args[5]        if len(args) >= 6 else ""
    sentinel  = args[6]        if len(args) >= 7 else ""

    app = VSTHostApp(
        in_wav=in_wav, out_wav=out_wav,
        plugin_path=plugin, tail_seconds=tail,
        buffer_size=buf, param_string=params,
    )
    app.mainloop()
    # Always write sentinel on exit (Process, Cancel, or window close)
    # so Praat's polling loop always unblocks cleanly.
    _write_sentinel(sentinel)
    return app._exit_code


def _run_cli(args: list[str]) -> int:
    if len(args) < 3 or len(args) > 7:
        print(
            "Usage: py host_vst.py input.wav output.wav plugin.vst3 "
            "[tail_seconds] [buffer_size] [param_assignments] [dump_params]",
            file=sys.stderr,
        )
        print(
            "GUI:   py host_vst.py --gui input.wav output.wav [plugin.vst3] "
            "[tail] [buf] [params]",
            file=sys.stderr,
        )
        return 1

    in_wav      = args[0]
    out_wav     = args[1]
    plugin_path = args[2]
    tail        = float(args[3]) if len(args) >= 4 else 1.0
    buf         = int(args[4])   if len(args) >= 5 else 8192
    params      = args[5]        if len(args) >= 6 else ""
    dump        = bool(int(args[6])) if len(args) >= 7 else False

    try:
        run_offline(in_wav, out_wav, plugin_path,
                    tail_seconds=tail, buffer_size=buf,
                    param_string=params, dump_params=dump)
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except Exception:
            pass

    raw_args = sys.argv[1:]
    if raw_args and raw_args[0] == "--editor-worker":
        raise SystemExit(_run_editor_worker(raw_args[1:]))

    gui_mode, remaining = _parse_args()
    if gui_mode:
        code = _run_gui(remaining)
    else:
        code = _run_cli(remaining)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
