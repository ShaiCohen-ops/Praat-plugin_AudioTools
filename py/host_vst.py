"""
host_vst.py  –  Praat → Python → VST3 offline processor
========================================================
CLI (legacy / Praat-driven):
    py host_vst.py input.wav output.wav plugin.vst3 [tail] [buf] [params] [dump]

GUI (launched by the new Praat script or manually):
    py host_vst.py --gui input.wav output.wav [plugin.vst3] [tail] [buf] [params]

When --gui is present the Tkinter window opens pre-populated from the remaining
arguments and from the last-used JSON config.  The user adjusts settings and
clicks Process (or Cancel).  No file-pickers for input/output WAVs are shown.
"""

from __future__ import annotations

import json
import os
import sys
import threading
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

def run_offline(
    in_wav: str,
    out_wav: str,
    plugin_path: str,
    tail_seconds: float = 1.0,
    buffer_size: int = 8192,
    param_string: str = "",
    dump_params: bool = False,
    log=None,           # callable(str) for GUI feedback; None → print
    plugin=None,        # pre-loaded plugin object (must be loaded on main thread)
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

    assignments = _parse_param_string(param_string)
    for key, value in assignments.items():
        if key not in available_params:
            emit(f"WARNING: parameter '{key}' not found – skipping.")
            continue
        try:
            setattr(plugin, key, value)
            emit(f"Set {key} = {value}")
        except Exception as exc:
            emit(f"WARNING: could not set '{key}' to {value}: {exc}")

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
    ) -> None:
        super().__init__()

        self._in_wav      = in_wav
        self._out_wav     = out_wav
        self._exit_code   = 0

        # ── Load saved config and merge with CLI args ──────────────────────
        cfg = _load_config()
        self._plugin_path = plugin_path  or cfg.get("plugin_path", "")
        self._tail        = tail_seconds if tail_seconds != 1.0 else float(cfg.get("tail_seconds", 1.0))
        self._buf         = buffer_size  if buffer_size  != 8192 else int(cfg.get("buffer_size",  8192))
        self._params      = param_string or cfg.get("param_string", "")

        # ── Window ──────────────────────────────────────────────────────────
        self.title("VST Host")
        self.configure(bg=_DARK)
        self.resizable(True, True)
        self.minsize(640, 520)

        self._build_style()
        self._build_ui()
        self._center_window(680, 620)

        self.protocol("WM_DELETE_WINDOW", self._on_cancel)

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
        lbl_mode = ttk.Label(title_row, text="● OFFLINE", style="Accent.TLabel")
        lbl_mode.pack(side="right")

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

        # ── Plugin path ──────────────────────────────────────────────────────
        ttk.Label(root, text="VST3 Plugin", style="Head.TLabel").grid(
            row=3, column=0, sticky="w", pady=(8, 2))

        plugin_row = ttk.Frame(root)
        plugin_row.grid(row=4, column=0, sticky="ew")
        plugin_row.columnconfigure(0, weight=1)

        self._plugin_var = tk.StringVar(value=self._plugin_path)
        plugin_entry = ttk.Entry(plugin_row, textvariable=self._plugin_var, font=_FONT_MONO)
        plugin_entry.grid(row=0, column=0, sticky="ew", padx=(0, 6))

        ttk.Button(plugin_row, text="Browse…",
                   command=self._browse_plugin).grid(row=0, column=1)
        ttk.Button(plugin_row, text="Scan Params",
                   command=self._scan_params).grid(row=0, column=2, padx=(4, 0))

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
        ttk.Entry(root, textvariable=self._params_var, font=_FONT_MONO).grid(
            row=8, column=0, sticky="ew")

        # ── Presets ───────────────────────────────────────────────────────────
        preset_row = ttk.Frame(root)
        preset_row.grid(row=9, column=0, sticky="ew", pady=(8, 0))

        ttk.Label(preset_row, text="Preset:", style="Muted.TLabel").pack(side="left", padx=(0, 6))
        self._preset_var = tk.StringVar()
        self._preset_cb  = ttk.Combobox(preset_row, textvariable=self._preset_var,
                                         values=_list_presets(), width=22)
        self._preset_cb.pack(side="left")
        ttk.Button(preset_row, text="Load",  command=self._load_preset).pack(side="left", padx=(4, 0))
        ttk.Button(preset_row, text="Save…", command=self._save_preset).pack(side="left", padx=(4, 0))

        # ── Log ───────────────────────────────────────────────────────────────
        ttk.Label(root, text="Log", style="Head.TLabel").grid(
            row=10, column=0, sticky="w", pady=(12, 2))
        self._log = scrolledtext.ScrolledText(
            root, height=8, font=_FONT_MONO,
            bg=_PANEL, fg=_TEXT, insertbackground=_TEXT,
            selectbackground=_ACCENT, selectforeground=_DARK,
            relief="flat", borderwidth=1,
            highlightbackground=_BORDER, highlightthickness=1,
            state="disabled")
        self._log.grid(row=11, column=0, sticky="nsew", pady=(0, 10))
        root.rowconfigure(11, weight=1)

        # ── Status bar ───────────────────────────────────────────────────────
        self._status_var = tk.StringVar(value="Ready")
        self._status_lbl = ttk.Label(root, textvariable=self._status_var,
                                     style="Muted.TLabel")
        self._status_lbl.grid(row=12, column=0, sticky="w")

        # ── Action buttons ────────────────────────────────────────────────────
        btn_row = ttk.Frame(root)
        btn_row.grid(row=13, column=0, sticky="e", pady=(10, 0))

        self._cancel_btn = ttk.Button(btn_row, text="Cancel",
                                      style="Cancel.TButton",
                                      command=self._on_cancel)
        self._cancel_btn.pack(side="left", padx=(0, 8))

        self._process_btn = ttk.Button(btn_row, text="▶  Process",
                                       style="Process.TButton",
                                       command=self._on_process)
        self._process_btn.pack(side="left")

    # ── Helpers ──────────────────────────────────────────────────────────────

    def _center_window(self, w: int, h: int) -> None:
        self.update_idletasks()
        sw, sh = self.winfo_screenwidth(), self.winfo_screenheight()
        x, y = (sw - w) // 2, (sh - h) // 2
        self.geometry(f"{w}x{h}+{x}+{y}")

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

    # ── Browse ────────────────────────────────────────────────────────────────

    def _browse_plugin(self) -> None:
        path = filedialog.askopenfilename(
            title="Select VST3 Plugin",
            filetypes=[("VST3 Plugin", "*.vst3"), ("All files", "*.*")])
        if path:
            self._plugin_var.set(path)

    # ── Scan params ──────────────────────────────────────────────────────────

    def _scan_params(self) -> None:
        plugin_path = self._plugin_var.get().strip()
        if not plugin_path:
            messagebox.showwarning("No Plugin", "Enter or browse to a VST3 plugin first.")
            return
        if not os.path.exists(plugin_path):
            messagebox.showerror("Not Found", f"Plugin not found:\n{plugin_path}")
            return
        self._set_status("Scanning parameters…", _AMBER)
        self._log_append(f"=== Scanning: {plugin_path} ===")
        self._process_btn.state(["disabled"])

        # Load plugin on the main thread — many VST3s refuse to load on a worker thread
        try:
            _check_dependencies()
            from pedalboard import load_plugin
            plugin_obj = load_plugin(plugin_path)
        except Exception as exc:
            self._process_btn.state(["!disabled"])
            self._scan_done(None, str(exc))
            return

        def worker() -> None:
            try:
                plugin = plugin_obj
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
                        p   = plugin.parameters[name]
                        mn  = getattr(p, "min_value",     "?")
                        mx  = getattr(p, "max_value",     "?")
                        df  = getattr(p, "default_value", "?")
                        cur = getattr(plugin, name, "?")
                        lines.append(f"  {name:<45}{fmt(mn)}{fmt(mx)}{fmt(df)}{fmt(cur)}")
                    except Exception as exc:
                        lines.append(f"  {name:<45}  (error: {exc})")
                self.after(0, lambda: self._scan_done("\n".join(lines), None))
            except Exception as exc:
                self.after(0, lambda e=exc: self._scan_done(None, str(e)))

        threading.Thread(target=worker, daemon=True).start()

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
        if "plugin_path"  in data: self._plugin_var.set(data["plugin_path"])
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
        self._set_status("Loading plugin…", _AMBER)
        self._log_append("=== Processing ===")

        # Load plugin on the main thread — many VST3s require this
        try:
            _check_dependencies()
            from pedalboard import load_plugin
            loaded_plugin = load_plugin(plugin_path)
            self._log_append(f"Loaded: {loaded_plugin}")
        except Exception as exc:
            self._process_failure(str(exc))
            return

        self._set_status("Processing…", _AMBER)

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
                )
                self._process_success()
            except Exception as exc:
                self._process_failure(str(exc))

        _save_config(settings)
        self.after(0, do_render)

    def _process_success(self) -> None:
        self._set_status("Done ✓", _GREEN)
        self._log_append("=== Done ===")
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


def _run_gui(args: list[str]) -> int:
    # args: input.wav output.wav [plugin.vst3 [tail [buf [params [sentinel]]]]]
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
    gui_mode, remaining = _parse_args()
    if gui_mode:
        code = _run_gui(remaining)
    else:
        code = _run_cli(remaining)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
