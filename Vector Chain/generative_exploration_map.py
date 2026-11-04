"""
generative_exploration_map.py — Generative Exploration Map  v1.1.1

Part of Praat AudioTools plugin (Vector Chain category)
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.1.1 (2026)
License: MIT

Changelog v1.1.1:
  - Manage Cache window (button in the map): per-map usage (source, points,
    MP3 files, disk use, last used), Open Folder, Clear Current Exploration,
    Clear All Cache with an optional, unchecked-by-default box for legacy
    v1.0/v1.0.1 sessions. Both deletions need explicit confirmation showing
    what will be removed; Clear All is refused as a whole if any live session
    holds a map.
  - Deletion renames a folder to .gemdeleting-<run>-<name> first (atomic),
    then removes it; an interrupted or Windows-locked deletion leaves only a
    folder no version ever reads as a map, which the next run's sweep
    finishes. Failures are reported, never hidden.
  - Legacy sessions are recognized by structure and metadata (session.json
    or staging/plan.json naming this tool, only the expected entries), not by
    folder name. Anything else is never listed or deleted.
  - No change to the Weaver, Progressive Exploration, synthesis or the store
    format; v1.1 maps open unchanged.

Companion of Generative_Exploration_Map.praat v1.1. Engine: Markov
Soundscape Weaver (the Praat script remains the only sound generator).

Changelog v1.1:
  - Progressive Exploration. A small, diverse initial batch (default 24,
    cost-screened), then listening-guided rounds: "Around marked",
    "Between marked", "Other seeds of marked". New points are generated in
    normalized parameter space (log and categorical parameters respected)
    and pass through the same validity repair as before.
  - Cumulative, content-addressed store. Every variation is identified by
    its EFFECTIVE (post-repair) parameter text and seed; the store folder
    by source content, engine file hash/version and preview settings. An
    identical configuration is never rendered twice.
  - Resumable. Each finished variation is saved on its own; an interrupted
    batch resumes with only the missing configurations.
  - Ownership-aware cleanup: per-run lock files with a heartbeat and a
    process-liveness check; complete variations are never deleted.
  - Map continuity: the PCA is recomputed every round and aligned to the
    previous layout (similarity Procrustes on the shared points).
  - GUI state (marks, current point, view, axes, colour, audio settings,
    window geometry, batch size) persists between rounds and sessions.

Phases (both blocking, called by Praat):
  plan    <manifest.json>  fingerprint, lock, sweep, initial batch or
                           resume; writes the list of configurations
                           Praat still has to render.
  explore <manifest.json>  ingest rendered previews (analysis on the
                           lossless WAV), project, open the GUI; returns
                           "selected", "refine" (a new batch was queued)
                           or "cancelled".
"""

import os
import sys
import json
import time
import math
import glob
import shutil
import socket
import hashlib
import logging
import re

TOOL_NAME = "Generative Exploration Map"
TOOL_VERSION = "1.1.1"
STORE_FORMAT = "gem-store-1"
ENGINE_NAME = "Markov Soundscape Weaver"
ENGINE_FILENAMES = ("Markov_Soundscape_Weaver.praat", "Neural_Markov_Soundscape_Weaver.praat")
SAMPLER_VERSION = "gem-sampler-2"
FEATURE_VERSION = "gem-features-1"
PARAM_DEF_VERSION = "mssw-0.8-params-1"
MP3_ENCODING = "Praat built-in LAME, Save as highest quality MP3 file (VBR)"
RUN_PREFIX = "gem11_"
STALE_HEARTBEAT_S = 30 * 60      # a run lock untouched this long ...
ORPHAN_AGE_S = 6 * 3600          # ... or an un-locked run file this old
                                 # is only removed when ALSO not owned by
                                 # a live process (see run_is_live)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


# ════════════════════════════════════════════════════════════════
# Parameter definitions (Weaver v0.8 form + validation block; unchanged
# from v1.0.1, so effective parameters are comparable).
# ════════════════════════════════════════════════════════════════
PARAMS = [
    ("grain_size_ms",              "Grain_size_ms",               "cont", 20.0, 400.0, "log"),
    ("analysis_overlap",           "Analysis_overlap",            "cont", 0.0,  0.95,  "lin"),
    ("number_of_states",           "Number_of_states",            "int",  1,    16,    "log"),
    ("markov_order",               "Markov_order",                "cat",  None, None,  None),
    ("randomness",                 "Randomness",                  "cont", 0.0,  1.0,   "lin"),
    ("synthesis_overlap",          "Synthesis_overlap",           "cont", 0.0,  0.95,  "lin"),
    ("varispeed_scatter_semitones","Varispeed_scatter_semitones", "cont", 0.0,  12.0,  "lin"),
    ("position_jitter",            "Position_jitter",             "cont", 0.0,  1.0,   "lin"),
    ("density_variation",          "Density_variation",           "cont", 0.0,  1.0,   "lin"),
    ("stereo_decorrelation",       "Stereo_decorrelation",        "cont", 0.0,  1.0,   "lin"),
]
ORDER_VALUES = ["First Order", "Second Order"]
P = {p[0]: p for p in PARAMS}
SAMPLED = [p[0] for p in PARAMS]
D = len(SAMPLED)
MIN_HOP_S = 0.002
MAX_ANALYSIS_GRAINS = 6000

TSV_COLS = ["id", "label", "seed"] + SAMPLED + ["wav", "mp3", "done"]
SEL_COLS = ["id", "label", "seed"] + SAMPLED

# Relative render-cost proxy, fitted (R^2 0.999) to 18 measured Weaver runs
# on a 5 s segment (Praat 6.4.06). Used ONLY to rank configurations; actual
# times are measured per variation and shown in the GUI.
COST_W = (0.0721, 3.01e-4, 5.8e-5, 2.49e-4, 2.3e-5)


# ════════════════════════════════════════════════════════════════
# Utilities
# ════════════════════════════════════════════════════════════════
def fwd(p: str) -> str:
    return p.replace("\\", "/")


def atomic_write_text(path: str, text: str):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def atomic_write_json(path: str, obj):
    atomic_write_text(path, json.dumps(obj, indent=1, ensure_ascii=False))


def read_json(path: str, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def write_kv_tsv(path: str, kv: dict):
    lines = ["key\tvalue"]
    for k, v in kv.items():
        lines.append(f"{k}\t" + str(v).replace("\t", " ").replace("\n", " "))
    atomic_write_text(path, "\n".join(lines) + "\n")


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cache_root() -> str:
    if sys.platform.startswith("win"):
        base = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Local")
    elif sys.platform == "darwin":
        base = os.path.join(os.path.expanduser("~"), "Library", "Caches")
    else:
        base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    # v1.1 keeps its own sub-folder: v1.0.1 sessions (one level up) are
    # never read, swept or modified by v1.1.
    return os.path.join(base, "PraatAudioTools", "GenerativeExplorationMap", "v1.1")


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform.startswith("win"):
        try:
            import ctypes
            k32 = ctypes.windll.kernel32
            h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
            if not h:
                return False
            code = ctypes.c_ulong()
            ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
            k32.CloseHandle(h)
            return bool(ok) and code.value == 259  # STILL_ACTIVE
        except Exception:
            return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except Exception:
        return False


def run_lock_path(temp_dir: str, token: str) -> str:
    return os.path.join(temp_dir, f"{RUN_PREFIX}{token}.lock")


def owner_path(temp_dir: str, token: str) -> str:
    return os.path.join(temp_dir, f"{RUN_PREFIX}{token}_owner.txt")


def _proc_info(pid: int):
    """(parent pid, executable name) of a process, or (None, None)."""
    try:
        if sys.platform.startswith("linux"):
            with open(f"/proc/{pid}/stat", encoding="utf-8", errors="replace") as f:
                st = f.read()
            ppid = int(st[st.rindex(")") + 2:].split()[1])
            with open(f"/proc/{pid}/comm", encoding="utf-8", errors="replace") as f:
                name = f.read().strip()
            return ppid, name
        if sys.platform == "darwin":
            import subprocess
            out = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(pid)], capture_output=True,
                                 text=True, timeout=5).stdout.strip()
            pp, name = out.split(None, 1)
            return int(pp), os.path.basename(name)
        if sys.platform.startswith("win"):
            import ctypes
            from ctypes import wintypes

            class PE(ctypes.Structure):
                _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
                            ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.c_void_p),
                            ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
                            ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", ctypes.c_long),
                            ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_char * 260)]
            k32 = ctypes.windll.kernel32
            snap = k32.CreateToolhelp32Snapshot(0x2, 0)
            pe = PE(); pe.dwSize = ctypes.sizeof(PE)
            res = (None, None)
            ok = k32.Process32First(snap, ctypes.byref(pe))
            while ok:
                if pe.th32ProcessID == pid:
                    res = (int(pe.th32ParentProcessID), pe.szExeFile.decode(errors="replace"))
                    break
                ok = k32.Process32Next(snap, ctypes.byref(pe))
            k32.CloseHandle(snap)
            return res
    except Exception:
        pass
    return None, None


def find_praat_pid() -> int | None:
    """The Praat process that launched us: walk up at most three parents
    (Praat -> optional shell / cmd.exe -> python) and accept only a process
    whose name contains 'praat'."""
    pid = os.getpid()
    for _ in range(3):
        ppid, _ = _proc_info(pid)
        if not ppid:
            return None
        _, name = _proc_info(ppid)
        if name and "praat" in name.lower():
            return ppid
        pid = ppid
    return None


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform.startswith("win"):
        try:
            import ctypes
            k32 = ctypes.windll.kernel32
            h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
            if not h:
                return False
            code = ctypes.c_ulong()
            ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
            k32.CloseHandle(h)
            return bool(ok) and code.value == 259  # STILL_ACTIVE
        except Exception:
            return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except Exception:
        return False


def write_owner(temp_dir: str, token: str):
    pid = find_praat_pid()
    try:
        atomic_write_text(owner_path(temp_dir, token),
                          f"praat_pid {pid if pid else 0} host {socket.gethostname()}\n")
    except OSError:
        pass


def run_is_live(temp_dir: str, token: str) -> bool:
    """Liveness of another run, decided by ownership first, age last:
      1. its owner file names the Praat process: live exactly while that
         process exists (a crashed run is recognized immediately);
      2. otherwise, its map window recorded a Python pid that is alive;
      3. otherwise (owner unknown), a heartbeat newer than 30 min."""
    lock = run_lock_path(temp_dir, token)
    host = socket.gethostname()
    try:
        with open(owner_path(temp_dir, token), encoding="utf-8", errors="replace") as f:
            m = re.search(r"praat_pid (\d+) host (\S+)", f.read())
        if m and int(m.group(1)) > 0 and m.group(2) == host:
            return pid_alive(int(m.group(1)))
    except OSError:
        pass
    try:
        with open(lock, encoding="utf-8", errors="replace") as f:
            m = re.search(r"pid (\d+) host (\S+)", f.read())
        if m and m.group(2) == host and pid_alive(int(m.group(1))):
            return True
        return time.time() - os.path.getmtime(lock) < STALE_HEARTBEAT_S
    except OSError:
        return False


def heartbeat(lock_path: str):
    try:
        atomic_write_text(lock_path, f"pid {os.getpid()} host {socket.gethostname()} t {time.time():.0f}\n")
    except OSError:
        pass


def find_engine(manifest: dict) -> str | None:
    script_dir = manifest.get("script_dir", "")
    plugin_dir = manifest.get("plugin_dir", "")
    for d in [script_dir, os.path.dirname(script_dir.rstrip("/")) if script_dir else ""]:
        for n in ENGINE_FILENAMES:
            p = os.path.join(d, n) if d else ""
            if p and os.path.isfile(p):
                return fwd(os.path.abspath(p))
    hits = []
    for root in [plugin_dir, script_dir]:
        if root and os.path.isdir(root):
            for n in ENGINE_FILENAMES:
                hits += glob.glob(os.path.join(root, "**", n), recursive=True)
    hits = sorted(set(os.path.abspath(h) for h in hits))
    return fwd(hits[0]) if hits else None


def engine_version(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for _ in range(40):
                line = f.readline()
                if "Version:" in line:
                    return line.split("Version:", 1)[1].strip()
    except OSError:
        pass
    return "unknown"


# ════════════════════════════════════════════════════════════════
# Normalized parameter space
#   u in [0,1]^D; log parameters map exponentially, the integer state
#   count on a log scale, Markov order is categorical (u >= 0.5 = Second),
#   and "mono" (Stereo_decorrelation -1 in the Weaver) is a separate
#   boolean carried next to u.
# ════════════════════════════════════════════════════════════════
def u_to_value(key: str, u: float):
    _, _, kind, lo, hi, scale = P[key]
    u = min(1.0, max(0.0, float(u)))
    if kind == "cat":
        return ORDER_VALUES[1] if u >= 0.5 else ORDER_VALUES[0]
    if kind == "int":
        v = math.exp(math.log(lo) + u * (math.log(hi) - math.log(lo)))
        return int(min(hi, max(lo, round(v))))
    if scale == "log":
        return lo * (hi / lo) ** u
    return lo + u * (hi - lo)


def value_to_u(key: str, v) -> float:
    _, _, kind, lo, hi, scale = P[key]
    if kind == "cat":
        return 1.0 if v == ORDER_VALUES[1] else 0.0
    v = float(v)
    if key == "stereo_decorrelation" and v < 0:
        return 0.0
    if scale == "log":
        return (math.log(max(v, lo)) - math.log(lo)) / (math.log(hi) - math.log(lo))
    return min(1.0, max(0.0, (v - lo) / (hi - lo)))


def fmt_value(key: str, v) -> str:
    if key == "markov_order":
        return v
    if key == "number_of_states":
        return str(int(v))
    if key == "grain_size_ms":
        return f"{v:.2f}"
    return f"{v:.4f}"


def repair(cfg: dict, analysis_dur: float) -> list[str]:
    """Weaver preconditions (Sound >= 4 grains, nGrains >= 2 * states) and
    the tool's cost guards. Identical to v1.0.1."""
    changed = []
    g_max = min(P["grain_size_ms"][4], analysis_dur * 1000.0 / 4.0 * 0.999)
    if cfg["grain_size_ms"] > g_max:
        cfg["grain_size_ms"] = g_max
        changed.append("grain_size_ms")
    g = cfg["grain_size_ms"] / 1000.0
    hop_min = max(MIN_HOP_S, (analysis_dur - g) / (MAX_ANALYSIS_GRAINS - 1))
    aov_max = max(0.0, min(0.95, 1.0 - hop_min / g))
    if cfg["analysis_overlap"] > aov_max:
        cfg["analysis_overlap"] = aov_max
        changed.append("analysis_overlap")
    sov_max = max(0.0, min(0.95, 1.0 - MIN_HOP_S / g))
    if cfg["synthesis_overlap"] > sov_max:
        cfg["synthesis_overlap"] = sov_max
        changed.append("synthesis_overlap")

    def n_grains(aov):
        return math.floor((analysis_dur - g) / (g * (1.0 - aov)) + 1e-9) + 1

    ng = n_grains(cfg["analysis_overlap"])
    if ng < 2:
        cfg["analysis_overlap"] = aov_max
        ng = n_grains(aov_max)
        if "analysis_overlap" not in changed:
            changed.append("analysis_overlap")
    k_max = max(1, ng // 2)
    if cfg["number_of_states"] > k_max:
        cfg["number_of_states"] = k_max
        changed.append("number_of_states")
    return changed


def cost_proxy(values: dict, analysis_dur: float, preview_dur: float) -> float:
    g = float(values["grain_size_ms"]) / 1000.0
    hop_a = g * (1.0 - float(values["analysis_overlap"]))
    n_a = math.floor((analysis_dur - g) / hop_a) + 1
    hop_s = g * (1.0 - float(values["synthesis_overlap"]))
    ch = 1 if float(values["stereo_decorrelation"]) < 0 else 2
    n_s = ch * (preview_dur / hop_s + 1)
    k = int(values["number_of_states"])
    w = COST_W
    return w[0] + w[1] * n_a + w[2] * n_a * k + w[3] * n_s + w[4] * n_s * g * 1000.0


def make_config(u, mono: bool, seed: int, analysis_dur: float, preview_dur: float) -> dict:
    """unit vector -> effective (repaired) parameters, identity and metadata."""
    cfg = {key: u_to_value(key, u[j]) for j, key in enumerate(SAMPLED)}
    changed = repair(cfg, analysis_dur)
    if mono:
        cfg["stereo_decorrelation"] = -1.0
    text = {key: fmt_value(key, cfg[key]) for key in SAMPLED}
    values = {key: (text[key] if key == "markov_order" else float(text[key])) for key in SAMPLED}
    eff_u = [value_to_u(key, values[key]) for key in SAMPLED]
    extremes = {}
    for key in SAMPLED:
        if key == "markov_order":
            continue
        v, lo, hi = values[key], P[key][3], P[key][4]
        if key == "stereo_decorrelation" and v < 0:
            extremes[key] = "mono"
        elif abs(v - lo) <= 1e-9 * max(1.0, abs(hi)):
            extremes[key] = "min"
        elif abs(v - hi) <= 1e-9 * max(1.0, abs(hi)):
            extremes[key] = "max"
    return {"vid": variation_id(text, seed), "seed": int(seed), "params": values, "params_text": text,
            "unit": [round(x, 6) for x in eff_u], "mono": bool(mono), "repaired": changed,
            "extremes": extremes, "cost_proxy": round(cost_proxy(values, analysis_dur, preview_dur), 4)}


def variation_id(params_text: dict, seed: int) -> str:
    """Identity of one rendered preview inside a store: the EXACT effective
    parameter text handed to the Weaver plus the seed."""
    blob = json.dumps({"p": [params_text[k] for k in SAMPLED], "seed": int(seed)}, separators=(",", ":"))
    return hashlib.sha1(blob.encode()).hexdigest()[:12]


def fractional_factorial_16(n_factors: int):
    import itertools
    base = list(itertools.product([0, 1], repeat=4))
    gens = [(0, 1, 2), (0, 1, 3), (0, 2, 3), (1, 2, 3), (0, 1, 2, 3), (0, 1)]
    rows = []
    for b in base:
        cols = list(b) + [sum(b[i] for i in g) % 2 for g in gens]
        rows.append(cols[:n_factors])
    return rows


def greedy_maximin(cands, chosen_u, n, max_cost):
    """Pick n candidates one at a time, each farthest (unit space) from
    everything already chosen, skipping candidates above the cost cap."""
    import numpy as np
    pool = [c for c in cands if c["cost_proxy"] <= max_cost]
    picked = []
    sel = [np.asarray(u, float) for u in chosen_u]
    while pool and len(picked) < n:
        if sel:
            S = np.array(sel)
            dists = [np.min(np.sqrt(((S - np.asarray(c["_u"], float)) ** 2).sum(1))) for c in pool]
            i = int(np.argmax(dists))
        else:
            i = 0
        c = pool.pop(i)
        picked.append(c)
        sel.append(np.asarray(c["_u"], float))
    return picked


def unit_with_mono(c):
    return list(c["unit"]) + [1.0 if c["mono"] else 0.0]


def initial_batch(n_init: int, analysis_dur: float, preview_dur: float, seed: int):
    """Centre + a boundary share (about a third) + interior points, all
    chosen by greedy maximin in unit space and screened by relative cost:
    nothing above 2.5x the centre configuration's cost enters round 0."""
    import numpy as np
    rng = np.random.default_rng(int(seed) + 7919)
    order_j = SAMPLED.index("markov_order")

    def cand(u, mono, origin, note):
        c = make_config(u, mono, seed, analysis_dur, preview_dur)
        c.update({"origin": origin, "note": note, "parents": [], "depth": 0})
        c["_u"] = unit_with_mono(c)
        return c

    centre_u = [0.5] * D
    centre_u[order_j] = 0.0
    centre = cand(centre_u, False, "centre", "all parameters at mid-range")
    cap = 2.5 * centre["cost_proxy"]

    boundary = []
    for lvl, order, tag in [(0.0, 0.0, "all min, First Order"), (1.0, 1.0, "all max, Second Order"),
                            (0.0, 1.0, "all min, Second Order"), (1.0, 0.0, "all max, First Order")]:
        u = [lvl] * D
        u[order_j] = order
        boundary.append(cand(u, False, "boundary", tag))
    for row in fractional_factorial_16(D):
        boundary.append(cand([float(v) for v in row], False, "boundary", "2-level factorial corner"))
    for j, key in enumerate(SAMPLED):
        if key == "markov_order":
            u = list(centre_u); u[j] = 1.0
            boundary.append(cand(u, False, "boundary", "centre with Second Order"))
            continue
        for lvl, tag in [(0.0, "min"), (1.0, "max")]:
            u = list(centre_u); u[j] = lvl
            boundary.append(cand(u, False, "boundary", f"{key} at {tag}, others mid"))
    boundary.append(cand(centre_u, True, "boundary", "centre, mono output"))

    interior = []
    lhs = (np.arange(400)[:, None] + rng.random((400, D))) / 400
    for j in range(D):
        lhs[:, j] = lhs[rng.permutation(400), j]
    for row in lhs:
        u = [0.08 + 0.84 * float(x) for x in row]   # strictly interior
        u[order_j] = float(row[order_j])           # categorical: full range
        interior.append(cand(u, False, "interior", "interior Latin hypercube"))

    n_b = max(1, round((n_init - 1) / 3))
    n_i = n_init - 1 - n_b
    chosen = [centre]
    b = greedy_maximin(boundary, [centre["_u"]], n_b, cap)
    chosen += b
    chosen += greedy_maximin(interior, [c["_u"] for c in chosen], n_i, cap)
    seen, out = set(), []
    for c in chosen:
        if c["vid"] not in seen:
            seen.add(c["vid"])
            c.pop("_u", None)
            out.append(c)
    return out, cap


# ════════════════════════════════════════════════════════════════
# Refinement actions (called from the GUI)
# ════════════════════════════════════════════════════════════════
def around(parents, n_total, store_vids, analysis_dur, preview_dur, rng):
    """Gaussian perturbation in unit space around each marked point.
    sigma = 0.15 * 0.6^depth, so repeated "Around" in the same lineage
    zooms in. The parent's seed is kept, so the difference you hear is
    the parameter change. Markov order and mono flip with p = min(0.4, 1.5 sigma)."""
    out = []
    per = max(2, int(math.ceil(n_total / max(1, len(parents)))))
    order_j = SAMPLED.index("markov_order")
    for par in parents:
        depth = int(par.get("depth", 0))
        sigma = 0.15 * (0.6 ** depth)
        p_flip = min(0.4, 1.5 * sigma)
        made, tries = 0, 0
        while made < per and tries < per * 40:
            tries += 1
            u = [min(1.0, max(0.0, x + rng.normal(0.0, sigma))) for x in par["unit"]]
            pu = par["unit"][order_j]
            u[order_j] = (1.0 - pu) if rng.random() < p_flip else pu
            mono = (not par["mono"]) if rng.random() < p_flip * 0.5 else par["mono"]
            if par["mono"] and not mono:
                u[SAMPLED.index("stereo_decorrelation")] = float(rng.uniform(0, 2 * sigma))
            c = make_config(u, mono, par["seed"], analysis_dur, preview_dur)
            if c["vid"] in store_vids:
                continue
            c.update({"origin": "around", "parents": [par["vid"]], "depth": depth + 1,
                      "note": f"around #{par['n']} (sigma {sigma:.3f})"})
            store_vids.add(c["vid"])
            out.append(c)
            made += 1
    return out


def between(parents, n_total, store_vids, analysis_dur, preview_dur):
    """Linear interpolation in unit space between marked points. Two points:
    one segment; three or four: every pair; more: consecutive in marking
    order. Categorical values and the seed come from the nearer end."""
    out = []
    if len(parents) < 2:
        return out
    if len(parents) <= 4:
        pairs = [(parents[i], parents[j]) for i in range(len(parents)) for j in range(i + 1, len(parents))]
    else:
        pairs = list(zip(parents[:-1], parents[1:]))
    per = max(1, int(math.ceil(n_total / len(pairs))))
    order_j = SAMPLED.index("markov_order")
    for a, b in pairs:
        for i in range(1, per + 1):
            t = i / (per + 1)
            u = [(1 - t) * x + t * y for x, y in zip(a["unit"], b["unit"])]
            near = a if t <= 0.5 else b
            u[order_j] = near["unit"][order_j]
            c = make_config(u, near["mono"], near["seed"], analysis_dur, preview_dur)
            if c["vid"] in store_vids:
                continue
            c.update({"origin": "between", "parents": [a["vid"], b["vid"]],
                      "depth": max(int(a.get("depth", 0)), int(b.get("depth", 0))),
                      "note": f"between #{a['n']} and #{b['n']}, t = {t:.2f}"})
            store_vids.add(c["vid"])
            out.append(c)
    return out


def other_seeds(parents, n_total, store_vids, analysis_dur, preview_dur):
    """Identical effective parameters, new seeds (the lowest seeds not yet
    used for that configuration)."""
    out = []
    per = max(2, int(math.ceil(n_total / max(1, len(parents)))))
    for par in parents:
        made, s = 0, 1
        while made < per and s < 100000:
            if s != par["seed"]:
                vid = variation_id(par["params_text"], s)
                if vid not in store_vids:
                    c = {"vid": vid, "seed": s, "params": dict(par["params"]),
                         "params_text": dict(par["params_text"]), "unit": list(par["unit"]),
                         "mono": par["mono"], "repaired": list(par.get("repaired", [])),
                         "extremes": dict(par.get("extremes", {})), "cost_proxy": par["cost_proxy"],
                         "origin": "seeds", "parents": [par["vid"]], "depth": int(par.get("depth", 0)),
                         "note": f"#{par['n']} with seed {s}"}
                    store_vids.add(vid)
                    out.append(c)
                    made += 1
            s += 1
    return out


# ════════════════════════════════════════════════════════════════
# Descriptors (lossless preview, unchanged from v1.0.1)
# ════════════════════════════════════════════════════════════════
FEATURE_SETTINGS = {"n_fft": 2048, "hop": 512, "n_mfcc": 13, "recurrence_block_s": 0.1,
                    "recurrence_min_lag_s": 0.5, "recurrence_threshold": 0.8}
FEATURE_KEYS = (["rms_mean", "rms_db_std", "centroid_mean", "centroid_std", "bandwidth_mean",
                 "flatness_mean", "rolloff_mean", "zcr_mean"]
                + [f"mfcc_{i}" for i in range(13)]
                + ["mfcc_variability", "onset_strength_mean", "onset_density",
                   "recurrence_rate", "frame_diversity", "lr_correlation", "side_mid_db"])


def extract_features(y, sr: int) -> dict:
    import numpy as np
    import librosa
    S = FEATURE_SETTINGS
    if y.ndim == 1:
        y = y[None, :]
    mono = y.mean(axis=0).astype(np.float32)
    if mono.size < S["n_fft"]:
        mono = np.pad(mono, (0, S["n_fft"] - mono.size))
    n_fft, hop, eps = S["n_fft"], S["hop"], 1e-10
    rms = librosa.feature.rms(y=mono, frame_length=n_fft, hop_length=hop)[0]
    feats = {"rms_mean": float(np.mean(rms)), "rms_db_std": float(np.std(20 * np.log10(rms + 1e-6)))}
    Smag = np.abs(librosa.stft(mono, n_fft=n_fft, hop_length=hop))
    cen = librosa.feature.spectral_centroid(S=Smag, sr=sr)[0]
    feats["centroid_mean"] = float(np.mean(cen))
    feats["centroid_std"] = float(np.std(cen))
    feats["bandwidth_mean"] = float(np.mean(librosa.feature.spectral_bandwidth(S=Smag, sr=sr)))
    feats["flatness_mean"] = float(np.mean(librosa.feature.spectral_flatness(S=Smag + eps)))
    feats["rolloff_mean"] = float(np.mean(librosa.feature.spectral_rolloff(S=Smag, sr=sr)))
    feats["zcr_mean"] = float(np.mean(librosa.feature.zero_crossing_rate(mono, frame_length=n_fft, hop_length=hop)))
    mf = librosa.feature.mfcc(y=mono, sr=sr, n_mfcc=S["n_mfcc"], n_fft=n_fft, hop_length=hop)
    for i in range(13):
        feats[f"mfcc_{i}"] = float(np.mean(mf[i]))
    feats["mfcc_variability"] = float(np.mean(np.std(mf[1:], axis=1)))
    oenv = librosa.onset.onset_strength(y=mono, sr=sr, hop_length=hop)
    feats["onset_strength_mean"] = float(np.mean(oenv))
    onsets = librosa.onset.onset_detect(onset_envelope=oenv, sr=sr, hop_length=hop)
    feats["onset_density"] = float(len(onsets) / max(mono.size / sr, 1e-6))
    fpb = max(1, int(round(S["recurrence_block_s"] * sr / hop)))
    nb = mf.shape[1] // fpb
    if nb >= 3:
        blk = mf[1:, :nb * fpb].reshape(mf.shape[0] - 1, nb, fpb).mean(axis=2).T
        z = (blk - blk.mean(0)) / (blk.std(0) + 1e-9)
        zn = z / (np.linalg.norm(z, axis=1, keepdims=True) + 1e-9)
        cs = zn @ zn.T
        lag = int(round(S["recurrence_min_lag_s"] / S["recurrence_block_s"]))
        ii, jj = np.triu_indices(nb, k=max(1, lag))
        feats["recurrence_rate"] = float(np.mean(cs[ii, jj] > S["recurrence_threshold"])) if ii.size else 0.0
        dm = np.sqrt(((blk[:, None, :] - blk[None, :, :]) ** 2).sum(-1))
        feats["frame_diversity"] = float(dm[np.triu_indices(nb, k=1)].mean())
    else:
        feats["recurrence_rate"] = 0.0
        feats["frame_diversity"] = 0.0
    if y.shape[0] >= 2:
        L, R = y[0].astype(np.float64), y[1].astype(np.float64)
        feats["lr_correlation"] = float(np.corrcoef(L, R)[0, 1]) if np.std(L) > 0 and np.std(R) > 0 else 1.0
        mid, side = 0.5 * (L + R), 0.5 * (L - R)
        feats["side_mid_db"] = float(10 * np.log10((np.mean(side ** 2) + 1e-12) / (np.mean(mid ** 2) + 1e-12)))
    else:
        feats["lr_correlation"] = 1.0
        feats["side_mid_db"] = -120.0
    for k, v in feats.items():
        if not np.isfinite(v):
            feats[k] = 0.0
    return feats


def project_aligned(vids, features, prev_coords: dict):
    """z-score + PCA(2) over ALL current points, then a similarity
    Procrustes fit (rotation/reflection, uniform scale, translation) that
    maps the anchors - points present in the previous layout - as close as
    possible to where they were. Returns coords, explained variance, the
    anchor residual relative to the layout's spread, and the anchor count."""
    import numpy as np
    from sklearn.decomposition import PCA
    from sklearn.preprocessing import StandardScaler
    X = np.nan_to_num(np.array([[f.get(k, 0.0) for k in FEATURE_KEYS] for f in features], float))
    if X.shape[0] < 3:
        return {v: [0.0, 0.0] for v in vids}, [0.0, 0.0], None, 0
    pca = PCA(n_components=2, random_state=0)
    C = pca.fit_transform(StandardScaler().fit_transform(X))
    evr = [float(x) for x in pca.explained_variance_ratio_]
    idx = [i for i, v in enumerate(vids) if v in prev_coords]
    resid = None
    if len(idx) >= 3:
        A = C[idx]
        B = np.array([prev_coords[vids[i]] for i in idx], float)
        ma, mb = A.mean(0), B.mean(0)
        A0, B0 = A - ma, B - mb
        U, Sg, Vt = np.linalg.svd(A0.T @ B0)
        R = U @ Vt
        s = Sg.sum() / max((A0 ** 2).sum(), 1e-12)
        C = s * (C - ma) @ R + mb
        spread = np.sqrt(((B0) ** 2).sum(1).mean()) or 1.0
        resid = float(np.sqrt(((C[idx] - B) ** 2).sum(1).mean()) / spread)
    return {v: [float(c[0]), float(c[1])] for v, c in zip(vids, C)}, evr, resid, len(idx)


# ════════════════════════════════════════════════════════════════
# Store
# ════════════════════════════════════════════════════════════════
class Store:
    def __init__(self, path: str):
        self.path = path
        self.vdir = os.path.join(path, "variations")
        self.pdir = os.path.join(path, "previews")
        self.pending = os.path.join(path, "pending")
        for d in (self.vdir, self.pdir, self.pending):
            os.makedirs(d, exist_ok=True)

    # metadata ---------------------------------------------------
    def meta(self):
        return read_json(os.path.join(self.path, "meta.json"), {})

    def save_meta(self, m):
        atomic_write_json(os.path.join(self.path, "meta.json"), m)

    def state(self):
        return read_json(os.path.join(self.path, "state.json"), {})

    def save_state(self, s):
        atomic_write_json(os.path.join(self.path, "state.json"), s)

    # variations -------------------------------------------------
    def variation_path(self, vid):
        return os.path.join(self.vdir, vid + ".json")

    def complete_vids(self):
        return {os.path.splitext(f)[0] for f in os.listdir(self.vdir) if f.endswith(".json")}

    def variations(self):
        out = []
        for f in sorted(os.listdir(self.vdir)):
            if f.endswith(".json"):
                v = read_json(os.path.join(self.vdir, f))
                if v:
                    out.append(v)
        out.sort(key=lambda v: v.get("n", 0))
        return out

    # batches ----------------------------------------------------
    def batches(self):
        out = []
        for f in sorted(os.listdir(self.pending)):
            if f.startswith("batch_") and f.endswith(".json"):
                b = read_json(os.path.join(self.pending, f))
                if b:
                    b["_path"] = os.path.join(self.pending, f)
                    out.append(b)
        return out

    def queued_vids(self):
        return {v["vid"] for b in self.batches() for v in b["variations"]}

    def add_batch(self, configs, action, parents, analysis_dur):
        """Assign display numbers, queue the batch atomically. Returns the
        number of configurations queued (duplicates already removed)."""
        if not configs:
            return 0
        m = self.meta()
        n0 = int(m.get("next_n", 1))
        rnd = int(m.get("round", -1)) + 1
        for i, c in enumerate(configs):
            c["n"] = n0 + i
            c["round"] = rnd
        m["next_n"] = n0 + len(configs)
        m["round"] = rnd
        m.setdefault("history", []).append({"round": rnd, "action": action, "parents": parents,
                                            "count": len(configs), "time": time.strftime("%Y-%m-%d %H:%M:%S")})
        batch = {"round": rnd, "action": action, "parents": parents, "analysis_duration": analysis_dur,
                 "created": time.strftime("%Y-%m-%d %H:%M:%S"), "variations": configs}
        atomic_write_json(os.path.join(self.pending, f"batch_{rnd:04d}.json"), batch)
        self.save_meta(m)
        return len(configs)

    def pending_files(self, vid):
        return tuple(os.path.join(self.pending, vid + ext) for ext in (".wav", ".mp3", ".done"))

    def ingest(self, progress=None, beat=None):
        """Analyse every finished-but-unrecorded preview, then retire
        batches whose members are all recorded. Each variation is written
        on its own (atomic JSON written last), so an interruption never
        loses a finished one."""
        import soundfile as sf
        done_vids = self.complete_vids()
        n_new = 0
        for b in self.batches():
            remaining = 0
            for v in b["variations"]:
                if v["vid"] in done_vids:
                    continue
                wav, mp3, done = self.pending_files(v["vid"])
                if not os.path.isfile(done):
                    remaining += 1
                    continue
                with open(done, encoding="utf-8", errors="replace") as f:
                    parts = f.read().strip().split("\t")
                status = parts[0] if parts else "failed"
                render_s = float(parts[1]) if len(parts) > 1 and parts[1].replace(".", "", 1).isdigit() else None
                rec = dict(v)
                rec["render_s"] = render_s
                rec["mp3"] = v["vid"] + ".mp3"
                if status == "ok" and os.path.isfile(wav) and os.path.isfile(mp3) and os.path.getsize(mp3) > 0:
                    y, sr = sf.read(wav, dtype="float32", always_2d=True)
                    y = y.T
                    rec.update({"channels": int(y.shape[0]), "sample_rate": int(sr),
                                "duration": float(y.shape[1] / sr), "descriptors": extract_features(y, sr),
                                "status": "ok"})
                    os.replace(mp3, os.path.join(self.pdir, rec["mp3"]))
                else:
                    # a Weaver failure is recorded, so it is not retried forever
                    rec.update({"status": "failed", "descriptors": None})
                atomic_write_json(self.variation_path(v["vid"]), rec)
                for f_ in (wav, mp3, done):
                    if os.path.isfile(f_):
                        os.remove(f_)
                done_vids.add(v["vid"])
                n_new += 1
                if beat:
                    beat()
                if progress:
                    progress(n_new)
            if remaining == 0:
                os.remove(b["_path"])
        return n_new

    def to_render(self):
        """Batch members with neither a record nor a finished render.
        Partial leftovers of an interrupted render are discarded here."""
        done_vids = self.complete_vids()
        out = []
        for b in self.batches():
            for v in b["variations"]:
                if v["vid"] in done_vids:
                    continue
                wav, mp3, done = self.pending_files(v["vid"])
                if os.path.isfile(done):
                    continue  # rendered, awaiting analysis
                for f_ in (wav, mp3):
                    if os.path.isfile(f_):
                        os.remove(f_)
                out.append(v)
        return out

    # locking ----------------------------------------------------
    def lock_path(self):
        return os.path.join(self.path, "lock.json")

    def acquire(self, token: str, temp_dir: str) -> str | None:
        """Returns None on success, or a message if another LIVE run holds
        this store."""
        cur = read_json(self.lock_path())
        if cur and cur.get("token") != token and run_is_live(cur.get("temp_dir", ""), cur.get("token", "")):
            return ("This source is already open in another Generative Exploration Map session "
                    f"(started {cur.get('time', '?')}). Close that session first.")
        atomic_write_json(self.lock_path(), {"token": token, "temp_dir": temp_dir,
                                             "host": socket.gethostname(),
                                             "time": time.strftime("%Y-%m-%d %H:%M:%S")})
        return None

    def release(self, token: str):
        cur = read_json(self.lock_path())
        if cur and cur.get("token") == token:
            try:
                os.remove(self.lock_path())
            except OSError:
                pass

    def held_by_live_other(self, token: str) -> bool:
        cur = read_json(self.lock_path())
        return bool(cur and cur.get("token") != token and run_is_live(cur.get("temp_dir", ""), cur.get("token", "")))


# ════════════════════════════════════════════════════════════════
# Cleanup sweep (ownership-aware)
# ════════════════════════════════════════════════════════════════
RUN_FILE_RE = re.compile(r"^" + RUN_PREFIX + r"(\d{6,}_\d{6})(?:_[a-z_]+)?\.(json|tsv|wav|ok|py|txt|lock)$")


def sweep(temp_dir: str, root: str, token: str) -> dict:
    """Removes only what Generative Exploration Map v1.1 owns AND no live
    process owns:
      temp dir: gem11_<token>_* files of runs that are not live
        (run_is_live: owning Praat process gone; age only as last resort);
        files of a run that never wrote a lock or owner file are removed
        only after 6 h.
      store root (v1.1 only): partial pending renders (no .done marker) in
        stores no live run holds; stores with no recorded variation and no
        queued batch. Complete variations, queued batches and finished
        renders awaiting analysis are always kept."""
    report = {"temp_removed": 0, "temp_kept_live": 0, "partial_removed": 0, "empty_stores_removed": 0}
    try:
        names = os.listdir(temp_dir)
    except OSError:
        names = []
    by_tok = {}
    for n in names:
        m = RUN_FILE_RE.match(n)
        if m and m.group(1) != token:
            by_tok.setdefault(m.group(1), []).append(n)
    for tok, files in by_tok.items():
        lock = run_lock_path(temp_dir, tok)
        if os.path.isfile(lock) or os.path.isfile(owner_path(temp_dir, tok)):
            if run_is_live(temp_dir, tok):
                report["temp_kept_live"] += len(files)
                continue
        else:
            ages = [time.time() - os.path.getmtime(os.path.join(temp_dir, f)) for f in files
                    if os.path.exists(os.path.join(temp_dir, f))]
            if not ages or min(ages) < ORPHAN_AGE_S:
                continue
        for f in files:
            try:
                os.remove(os.path.join(temp_dir, f))
                report["temp_removed"] += 1
            except OSError:
                pass
    report["deletions_finished"] = 0
    for base in (root, os.path.dirname(root)):
        if not os.path.isdir(base):
            continue
        for name in os.listdir(base):
            m = re.match(re.escape(DELETING_PREFIX) + r"(\d{6,}_\d{6})-", name)
            p = os.path.join(base, name)
            if not (m and os.path.isdir(p)):
                continue
            if m.group(1) != token and run_is_live(temp_dir, m.group(1)):
                continue  # its owner may be deleting it right now
            shutil.rmtree(p, ignore_errors=True)
            report["deletions_finished"] += int(not os.path.exists(p))
    if os.path.isdir(root):
        for key in os.listdir(root):
            sdir = os.path.join(root, key)
            if not (os.path.isdir(sdir) and re.fullmatch(r"[0-9a-f]{24}", key)):
                continue
            st = Store(sdir)
            if st.held_by_live_other(token):
                continue
            for f in os.listdir(st.pending):
                if f.endswith((".wav", ".mp3")):
                    vid = os.path.splitext(f)[0]
                    if not os.path.isfile(os.path.join(st.pending, vid + ".done")):
                        try:
                            os.remove(os.path.join(st.pending, f))
                            report["partial_removed"] += 1
                        except OSError:
                            pass
                elif f.endswith(".tmp"):
                    try:
                        os.remove(os.path.join(st.pending, f))
                    except OSError:
                        pass
            if not st.complete_vids() and not st.batches() and \
                    not any(f.endswith(".done") for f in os.listdir(st.pending)):
                cur = read_json(st.lock_path())
                if not (cur and cur.get("token") == token):
                    shutil.rmtree(sdir, ignore_errors=True)
                    report["empty_stores_removed"] += 1
    return report


# ════════════════════════════════════════════════════════════════
# Cache management (v1.1.1)
# ════════════════════════════════════════════════════════════════
DELETING_PREFIX = ".gemdeleting-"
LEGACY_ACTIVE_S = 30 * 60
HEX24 = re.compile(r"[0-9a-f]{24}")


def legacy_root() -> str:
    """v1.0 / v1.0.1 kept their sessions directly in the parent folder."""
    return os.path.dirname(cache_root())


def dir_usage(path: str) -> tuple[int, int]:
    total, files = 0, 0
    for r, _ds, fs in os.walk(path):
        for f in fs:
            try:
                total += os.path.getsize(os.path.join(r, f))
                files += 1
            except OSError:
                pass
    return total, files


def fmt_bytes(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0
    return f"{n:.1f} GB"


def _mtime(*paths) -> float:
    best = 0.0
    for p in paths:
        try:
            best = max(best, os.path.getmtime(p))
        except OSError:
            pass
    return best


def is_v11_store(path: str) -> bool:
    if not (os.path.isdir(path) and HEX24.fullmatch(os.path.basename(path))):
        return False
    m = read_json(os.path.join(path, "meta.json"))
    return bool(m and isinstance(m.get("identity"), dict) and m["identity"].get("format") == STORE_FORMAT
                and os.path.isdir(os.path.join(path, "variations")))


LEGACY_ENTRIES = {"session.json", "previews", "staging"}


def legacy_info(path: str) -> dict | None:
    """A v1.0 / v1.0.1 session, recognized by STRUCTURE and METADATA:
    the folder holds only session.json / previews / staging (plus
    atomic-write .tmp leftovers), previews holds only .mp3, staging only
    .wav/.json/.tsv/.tmp, and the metadata names this tool. The
    24-hex name is required too, but never sufficient."""
    if not (os.path.isdir(path) and HEX24.fullmatch(os.path.basename(path))):
        return None
    try:
        entries = os.listdir(path)
    except OSError:
        return None
    if not entries or any(e not in LEGACY_ENTRIES and not e.endswith(".tmp") for e in entries):
        return None
    pv = os.path.join(path, "previews")
    sg = os.path.join(path, "staging")
    if os.path.isdir(pv) and any(not f.endswith(".mp3") for f in os.listdir(pv)):
        return None
    if os.path.isdir(sg) and any(not f.endswith((".wav", ".json", ".tsv", ".tmp")) for f in os.listdir(sg)):
        return None
    s = read_json(os.path.join(path, "session.json"))
    if s:
        if s.get("format") != "gem-session-1" or (s.get("tool") or {}).get("name") != TOOL_NAME:
            return None
        ver = (s.get("tool") or {}).get("version", "1.0")
        src = (s.get("source") or {}).get("source_name", "?")
        n = len(s.get("variations", []))
        complete = bool(s.get("complete"))
    else:
        pj = read_json(os.path.join(sg, "plan.json"))
        tool = ((pj or {}).get("identity") or {}).get("tool")
        if not (isinstance(tool, list) and tool and tool[0] == TOOL_NAME):
            return None
        ver, src = tool[1] if len(tool) > 1 else "1.0", (pj.get("manifest") or {}).get("source_name", "?")
        n, complete = len(pj.get("plan", [])), False
    size, files = dir_usage(path)
    mp3 = len(os.listdir(pv)) if os.path.isdir(pv) else 0
    newest = _mtime(os.path.join(path, "session.json"), sg, *(
        [os.path.join(sg, f) for f in os.listdir(sg)] if os.path.isdir(sg) else []))
    return {"kind": "legacy", "path": path, "version": ver, "source": src, "points": n, "mp3": mp3,
            "bytes": size, "files": files, "last_used": newest, "complete": complete}


def legacy_active(info: dict, temp_dir: str) -> bool:
    """v1.0.x records no owner, so only recency can tell: an incomplete
    session written to in the last 30 min, or a v1.0.x run manifest in the
    temp folder from the last 30 min, counts as possibly in use."""
    now = time.time()
    if not info["complete"] and now - info["last_used"] < LEGACY_ACTIVE_S:
        return True
    try:
        for f in os.listdir(temp_dir):
            if re.fullmatch(r"gem_manifest(_\d+_\d+)?\.json", f):
                if now - os.path.getmtime(os.path.join(temp_dir, f)) < LEGACY_ACTIVE_S:
                    return True
    except OSError:
        pass
    return False


def cache_inventory(temp_dir: str, token: str, current_dir: str = "") -> dict:
    root, lroot = cache_root(), legacy_root()
    maps, legacy, pending = [], [], []
    cur = os.path.normcase(os.path.abspath(current_dir)) if current_dir else ""
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            p = os.path.join(root, name)
            if name.startswith(DELETING_PREFIX) and os.path.isdir(p):
                pending.append({"path": p, "bytes": dir_usage(p)[0]})
            elif is_v11_store(p):
                st = Store(p)
                m = st.meta()
                vids = st.complete_vids()
                size, files = dir_usage(p)
                maps.append({"kind": "v1.1", "path": p, "source": (m.get("source") or {}).get("source_name", "?"),
                             "points": len(vids), "mp3": len(os.listdir(st.pdir)), "bytes": size, "files": files,
                             "rounds": int(m.get("round", -1)) + 1,
                             "last_used": _mtime(*(os.path.join(p, f) for f in
                                                   ("meta.json", "state.json", "projection.json", "lock.json")),
                                                 st.vdir),
                             "in_use": st.held_by_live_other(token),
                             "current": os.path.normcase(os.path.abspath(p)) == cur})
    if os.path.isdir(lroot):
        for name in sorted(os.listdir(lroot)):
            p = os.path.join(lroot, name)
            if name.startswith(DELETING_PREFIX) and os.path.isdir(p):
                pending.append({"path": p, "bytes": dir_usage(p)[0]})
                continue
            info = legacy_info(p)
            if info:
                info["in_use"] = legacy_active(info, temp_dir)
                info["current"] = False
                legacy.append(info)
    return {"maps": maps, "legacy": legacy, "pending": pending,
            "v11_bytes": sum(x["bytes"] for x in maps), "legacy_bytes": sum(x["bytes"] for x in legacy),
            "root": root, "legacy_root": lroot}


def safe_delete(path: str, token: str) -> tuple[bool, int, list[str]]:
    """Rename-then-remove. The rename is atomic: if it fails (a locked file
    on Windows, permissions) nothing is touched and the failure is
    returned. After it, the folder is .gemdeleting-<run>-<name>, which no
    version reads as a map; whatever rmtree cannot remove stays there and
    is finished by the next run's sweep. Returns (fully removed, bytes
    freed, failures)."""
    before, _ = dir_usage(path)
    target = os.path.join(os.path.dirname(path), f"{DELETING_PREFIX}{token}-{os.path.basename(path)}")
    try:
        os.rename(path, target)
    except OSError as e:
        return False, 0, [f"{path}: could not start deletion ({e.strerror or e}); nothing was removed"]
    failures = []

    def on_err(func, p, exc):
        try:
            os.chmod(p, 0o700)
            func(p)
        except Exception as e2:
            failures.append(f"{p}: {getattr(e2, 'strerror', None) or e2}")
    if sys.version_info >= (3, 12):
        shutil.rmtree(target, onexc=on_err)
    else:
        shutil.rmtree(target, onerror=lambda f, p, ei: on_err(f, p, ei[1]))
    left, _ = dir_usage(target) if os.path.exists(target) else (0, 0)
    return (not os.path.exists(target)), before - left, failures


def clear_all_check(temp_dir: str, token: str, include_legacy: bool) -> list[str]:
    """Everything that would block Clear All. Empty list = allowed."""
    inv = cache_inventory(temp_dir, token)
    blocked = [f"{m['source']} (v1.1 map, open in another session)" for m in inv["maps"] if m["in_use"]]
    if include_legacy:
        blocked += [f"{l['source']} (v{l['version']} session, possibly running: used in the last 30 min)"
                    for l in inv["legacy"] if l["in_use"]]
    return blocked


def clear_all(temp_dir: str, token: str, include_legacy: bool) -> dict:
    """Refuses as a whole if anything is in use; otherwise deletes every
    v1.1 map (and, if asked, every recognized legacy session)."""
    blocked = clear_all_check(temp_dir, token, include_legacy)
    if blocked:
        return {"refused": blocked, "removed": 0, "freed": 0, "failures": []}
    inv = cache_inventory(temp_dir, token)
    targets = [m["path"] for m in inv["maps"]] + ([l["path"] for l in inv["legacy"]] if include_legacy else [])
    removed, freed, failures = 0, 0, []
    for t in targets:
        ok, b, f = safe_delete(t, token)
        removed += int(ok)
        freed += b
        failures += f
    return {"refused": [], "removed": removed, "targets": len(targets), "freed": freed, "failures": failures}


# ════════════════════════════════════════════════════════════════
# Store identity
# ════════════════════════════════════════════════════════════════
def store_identity(man, source_sha, engine_sha, engine_ver):
    ident = {
        "format": STORE_FORMAT,
        "engine": [ENGINE_NAME, engine_ver, engine_sha],
        "source_sha256": source_sha, "source_sr": man["source_sr"],
        "source_channels": man["source_channels"], "source_samples": man["source_samples"],
        "preview_source": man["preview_source"],
        "segment_start": man["segment_start"] if man["preview_source"] == "segment" else None,
        "preview_duration": man["preview_duration"],
        "params": [PARAM_DEF_VERSION, PARAMS, MIN_HOP_S, MAX_ANALYSIS_GRAINS],
        "features": [FEATURE_VERSION, FEATURE_SETTINGS, FEATURE_KEYS],
        "mp3": MP3_ENCODING,
    }
    key = hashlib.sha256(json.dumps(ident, sort_keys=True, default=str).encode()).hexdigest()[:24]
    return key, ident


def analysis_duration(man) -> float:
    if man["preview_source"] == "segment":
        return min(float(man["preview_duration"]), float(man["source_duration"]) - float(man["segment_start"]))
    return float(man["source_duration"])


# ════════════════════════════════════════════════════════════════
# Phase 1: plan
# ════════════════════════════════════════════════════════════════
def phase_plan(man: dict):
    info = man["plan_info"]
    token = man["token"]
    run_lock = run_lock_path(man["temp_dir"], token)
    try:
        missing = []
        for pkg in ["numpy", "librosa", "soundfile", "sklearn"]:
            try:
                __import__(pkg)
            except ImportError:
                missing.append(pkg)
        if missing:
            raise RuntimeError("Missing Python packages: " + ", ".join(missing) +
                               ". Run: pip install numpy librosa soundfile sounddevice scikit-learn pyqtgraph PySide6")
        import soundfile as sf
        if "MP3" not in sf.available_formats():
            raise RuntimeError("This soundfile/libsndfile build cannot read MP3 (libsndfile 1.1 or later "
                               "needed). Run: pip install --upgrade soundfile")
        heartbeat(run_lock)
        write_owner(man["temp_dir"], token)
        root = cache_root()
        os.makedirs(root, exist_ok=True)
        swept = {}
        engine = man.get("engine_path", "")
        if man.get("store_dir"):
            sdir = man["store_dir"]
        else:
            engine = find_engine(man)
            if not engine:
                raise RuntimeError("Markov Soundscape Weaver not found (looked for " + " / ".join(ENGINE_FILENAMES) +
                                   " next to this tool and inside the plugin folder).")
            src = man["source_wav"]
            if not os.path.isfile(src):
                raise RuntimeError("Source export not found: " + src)
            source_sha = sha256_file(src)
            try:
                os.remove(src)
            except OSError:
                pass
            key, ident = store_identity(man, source_sha, sha256_file(engine), engine_version(engine))
            sdir = os.path.join(root, key)
            swept = sweep(man["temp_dir"], root, token)
            if man.get("discard") and os.path.isdir(sdir):
                if Store(sdir).held_by_live_other(token):
                    raise RuntimeError("Cannot discard: this source is open in another session.")
                shutil.rmtree(sdir, ignore_errors=True)
            st = Store(sdir)
            m = st.meta()
            if not m:
                st.save_meta({"identity": ident, "engine_path": engine, "engine_version": engine_version(engine),
                              "source": {k: man[k] for k in ("source_name", "source_duration", "source_sr",
                                                             "source_channels", "source_samples", "preview_source",
                                                             "segment_start", "preview_duration")},
                              "analysis_duration": analysis_duration(man), "tool_version": TOOL_VERSION,
                              "created": time.strftime("%Y-%m-%d %H:%M:%S"), "next_n": 1, "round": -1,
                              "history": []})
            else:
                m["engine_path"] = engine
                st.save_meta(m)
        st = Store(sdir)
        msg = st.acquire(token, man["temp_dir"])
        if msg:
            write_kv_tsv(info, {"status": "busy", "message": msg})
            return
        adur = analysis_duration(man)
        pdur = float(man["preview_duration"])
        initial_queued = 0
        if not st.complete_vids() and not st.batches():
            cfgs, _ = initial_batch(int(man["n_initial"]), adur, pdur, int(man["base_seed"]))
            initial_queued = st.add_batch(cfgs, "initial", [], adur)
        todo = st.to_render()
        lines = ["\t".join(TSV_COLS)]
        for v in todo:
            wav, mp3, done = (fwd(p) for p in st.pending_files(v["vid"]))
            lines.append("\t".join([v["vid"], f"p{v['n']:03d}", str(v["seed"])] +
                                   [v["params_text"][k] for k in SAMPLED] + [wav, mp3, done]))
        atomic_write_text(man["plan_tsv"], "\n".join(lines) + "\n")
        n_complete = len(st.complete_vids())
        write_kv_tsv(info, {"status": "render" if todo else "ready", "engine": engine or st.meta().get("engine_path", ""),
                            "store_dir": fwd(sdir), "count": len(todo), "complete": n_complete,
                            "initial_queued": initial_queued, "swept": json.dumps(swept)})
        logging.info(f"store {sdir}: {n_complete} recorded, {len(todo)} to render, swept {swept}")
    except Exception as e:
        logging.exception("plan failed")
        write_kv_tsv(info, {"status": "error", "message": str(e)})


# ════════════════════════════════════════════════════════════════
# Cache dialogs (module level so they can be driven without a screen)
# ════════════════════════════════════════════════════════════════
def info_dialog(parent, title: str, text: str):
    from PySide6.QtWidgets import QMessageBox
    QMessageBox.information(parent, title, text)


def confirm_dialog(parent, title: str, text: str) -> bool:
    from PySide6.QtWidgets import QMessageBox
    box = QMessageBox(QMessageBox.Warning, title, text, QMessageBox.Cancel, parent)
    delete = box.addButton("Delete", QMessageBox.DestructiveRole)
    box.setDefaultButton(QMessageBox.Cancel)
    box.exec()
    return box.clickedButton() is delete


def confirm_clear_all(parent, inv: dict) -> tuple[bool, bool]:
    """Explicit confirmation for Clear All; the legacy box starts unchecked
    and the text always shows exactly what the current choice deletes."""
    from PySide6.QtWidgets import QDialog, QVBoxLayout, QLabel, QCheckBox, QDialogButtonBox
    dlg = QDialog(parent)
    dlg.setWindowTitle("Clear All Cache")
    lay = QVBoxLayout(dlg)
    lbl = QLabel(); lbl.setWordWrap(True); lbl.setMinimumWidth(460)
    nl = len(inv["legacy"])
    box = QCheckBox(f"Also delete {nl} legacy v1.0 / v1.0.1 session(s) ({fmt_bytes(inv['legacy_bytes'])})")
    box.setChecked(False)
    box.setEnabled(nl > 0)

    def refresh():
        lbl.setText(clear_all_text(inv, box.isChecked()))
    box.stateChanged.connect(refresh)
    refresh()
    bb = QDialogButtonBox(QDialogButtonBox.Cancel)
    delete = bb.addButton("Delete", QDialogButtonBox.DestructiveRole)
    bb.rejected.connect(dlg.reject)
    delete.clicked.connect(dlg.accept)
    lay.addWidget(lbl); lay.addWidget(box); lay.addWidget(bb)
    ok = dlg.exec() == QDialog.Accepted
    return ok, box.isChecked()


def clear_all_text(inv: dict, include_legacy: bool) -> str:
    pts = sum(m["points"] for m in inv["maps"])
    mp3 = sum(m["mp3"] for m in inv["maps"])
    t = (f"This deletes ALL Generative Exploration Map v1.1 data:\n"
         f"  {len(inv['maps'])} map(s), {pts} points, {mp3} MP3 files, {fmt_bytes(inv['v11_bytes'])}\n"
         f"  in {inv['root']}\n")
    if include_legacy:
        lp = sum(l["points"] for l in inv["legacy"])
        lm = sum(l["mp3"] for l in inv["legacy"])
        t += (f"\nAND the legacy sessions:\n"
              f"  {len(inv['legacy'])} v1.0 / v1.0.1 session(s), {lp} points, {lm} MP3 files, "
              f"{fmt_bytes(inv['legacy_bytes'])}\n  in {inv['legacy_root']}\n"
              f"\nTotal: {fmt_bytes(inv['v11_bytes'] + inv['legacy_bytes'])}\n")
    t += ("\nExploration history, marks and selections are deleted with them; the next time "
          "you use a Sound its variations have to be rendered again. Your original recordings, "
          "Praat objects and results saved elsewhere are not touched.")
    return t


# ════════════════════════════════════════════════════════════════
# GUI
# ════════════════════════════════════════════════════════════════
def run_gui(st: Store, man: dict, coords, evr, resid, n_anchor, status_path: str):
    import numpy as np
    import soundfile as sf
    import sounddevice as sd
    import pyqtgraph as pg
    from PySide6.QtCore import Qt, QTimer, QByteArray
    from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
                                   QPushButton, QLabel, QComboBox, QSlider, QCheckBox, QScrollArea,
                                   QSpinBox, QGridLayout)

    run_lock = run_lock_path(man["temp_dir"], man["token"])
    adur = analysis_duration(man)
    pdur = float(man["preview_duration"])
    meta = st.meta()
    allv = st.variations()
    variations = [v for v in allv if v.get("status") == "ok" and v["vid"] in coords]
    n_failed = sum(1 for v in allv if v.get("status") != "ok")
    by_vid = {v["vid"]: i for i, v in enumerate(variations)}
    last_round = max((v.get("round", 0) for v in variations), default=0)
    state = st.state()

    class AudioEngine:
        """Corpus Map v2.5.1 playback engine."""
        def __init__(self):
            self.gain, self.exclusive, self.device_idx, self._streams = 0.8, True, None, {}

        def devices(self):
            return [{"index": i, "name": d["name"], "channels": d["max_output_channels"]}
                    for i, d in enumerate(sd.query_devices()) if d["max_output_channels"] > 0]

        def play(self, uid, audio, sr):
            if audio is None or self.device_idx is None:
                return
            if self.exclusive:
                self.panic()
            try:
                max_out = int(sd.query_devices(self.device_idx)["max_output_channels"])
            except Exception as e:
                logging.error(f"Device query error: {e}")
                return
            if max_out < 1:
                return
            data = (audio * self.gain).astype(np.float32)
            src_ch = 1 if data.ndim == 1 else data.shape[1]
            out_ch = min(src_ch, max_out)
            if data.ndim == 2 and out_ch < src_ch:
                data = data.mean(axis=1).astype(np.float32) if out_ch == 1 else data[:, :out_ch].copy()
            ch = 1 if data.ndim == 1 else data.shape[1]
            ptr = [0]

            def cb(outdata, frames, _t, _st):
                end = ptr[0] + frames
                chunk = data[ptr[0]:end]
                outdata[:len(chunk)] = chunk.reshape(-1, 1) if ch == 1 else chunk
                if len(chunk) < frames:
                    outdata[len(chunk):] = 0
                    raise sd.CallbackStop
                ptr[0] = end
            try:
                old = self._streams.pop(uid, None)
                if old is not None:
                    try:
                        old.stop(); old.close()
                    except Exception:
                        pass
                while len(self._streams) >= 16:
                    s = self._streams.pop(next(iter(self._streams)))
                    try:
                        s.stop(); s.close()
                    except Exception:
                        pass

                def _fin(u=uid):
                    self._streams.pop(u, None)
                s = sd.OutputStream(device=self.device_idx, samplerate=sr, channels=ch, callback=cb,
                                    finished_callback=_fin)
                s.start()
                self._streams[uid] = s
            except Exception as e:
                logging.error(f"Playback error: {e}")

        def panic(self):
            for s in list(self._streams.values()):
                try:
                    s.stop(); s.close()
                except Exception:
                    pass
            self._streams.clear()

    ORIGIN_COLORS = {"centre": (255, 209, 26), "boundary": (230, 57, 70), "interior": (42, 157, 143),
                     "around": (168, 130, 255), "between": (90, 170, 255), "seeds": (244, 162, 97)}
    LABEL = {p[0]: p[1].replace("_", " ") for p in PARAMS}

    class Window(QMainWindow):
        def __init__(self):
            super().__init__()
            self.engine = AudioEngine()
            self.cache = {}
            self.current = None
            self.marks = [m for m in state.get("marks", []) if m in by_vid]
            self.result = "cancelled"
            self.delete_legacy = False
            self.hover_active = False
            self.last_hover_t = 0.0
            self._build()
            self._restore()
            self._redraw()
            self.hb = QTimer(self)
            self.hb.timeout.connect(lambda: heartbeat(run_lock))
            self.hb.start(60000)
            heartbeat(run_lock)

        # ── UI ──────────────────────────────────────────────────
        def _build(self):
            self.setWindowTitle(f"{TOOL_NAME} v{TOOL_VERSION} — AudioTools")
            self.setMinimumSize(1150, 700)
            self.setStyleSheet("""
                QMainWindow, QWidget { background: #111; }
                QLabel { color: #ddd; font-family: 'Courier New'; font-size: 11px; }
                QPushButton { background: #1e1e1e; color: #ddd; border: 1px solid #333; padding: 6px; font-weight: bold; }
                QPushButton:hover { background: #2a2a2a; }
                QPushButton:disabled { color: #555; border-color: #222; }
                QComboBox, QSpinBox { background: #1e1e1e; color: #ddd; border: 1px solid #333; }
                QCheckBox { color: #ddd; }
                QToolTip { color: #111; background: #ffffdd; }
            """)
            root = QWidget(); self.setCentralWidget(root)
            layout = QHBoxLayout(root)
            side_w = QWidget(); side = QVBoxLayout(side_w); side.setContentsMargins(10, 10, 10, 10)
            scroll = QScrollArea(); scroll.setWidget(side_w); scroll.setWidgetResizable(True)
            scroll.setStyleSheet("QScrollArea { border: none; }")
            scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
            col_w = QWidget(); col_w.setFixedWidth(440)
            col = QVBoxLayout(col_w); col.setContentsMargins(0, 0, 0, 0)
            col.addWidget(scroll, stretch=1)
            act = QVBoxLayout(); act.setContentsMargins(10, 4, 10, 10)
            col.addLayout(act)

            t = QLabel(f"■ Generative Exploration Map  v{TOOL_VERSION}")
            t.setStyleSheet("font-size: 15px; color: #00ff88; font-weight: bold;")
            side.addWidget(t)
            src = meta.get("source", {})
            seg = "first " if src.get("preview_source") == "segment" else "whole sound, "
            anchor_txt = ("" if resid is None else
                          f"\nlayout aligned on {n_anchor} points (residual {100 * resid:.0f}% of spread)")
            side.addWidget(QLabel(
                f"{ENGINE_NAME} {meta.get('engine_version', '?').split()[0]}  |  source: {src.get('source_name', '?')}\n"
                f"{len(variations)} points over {last_round + 1} round(s)" +
                (f", {n_failed} failed" if n_failed else "") +
                f"\nanalysis: {seg}{adur:.2f} s  |  preview {pdur:.2f} s" + anchor_txt))

            side.addWidget(QLabel("\n[View]"))
            self.view = QComboBox(); self.view.addItems(["Sound Space (PCA of descriptors)", "Parameter Space"])
            side.addWidget(self.view)
            row = QHBoxLayout()
            self.xsel, self.ysel = QComboBox(), QComboBox()
            for k in SAMPLED:
                self.xsel.addItem(LABEL[k], k); self.ysel.addItem(LABEL[k], k)
            row.addWidget(QLabel("X")); row.addWidget(self.xsel); row.addWidget(QLabel("Y")); row.addWidget(self.ysel)
            side.addLayout(row)
            side.addWidget(QLabel("[Colour]"))
            self.csel = QComboBox()
            self.csel.addItem("Origin", "origin"); self.csel.addItem("Round", "round")
            for k in SAMPLED:
                self.csel.addItem(LABEL[k], k)
            side.addWidget(self.csel)
            self.ring_check = QCheckBox("Ring = any parameter at its min/max")
            self.lineage_check = QCheckBox("Lines = parents of the newest round")
            side.addWidget(self.ring_check); side.addWidget(self.lineage_check)
            self.legend = QLabel(""); self.legend.setWordWrap(True); side.addWidget(self.legend)

            side.addWidget(QLabel("\n[Audio output]"))
            self.dev = QComboBox()
            for d in self.engine.devices():
                self.dev.addItem(f"{d['name']}  ({d['channels']} ch)", d["index"])
            self.dev.currentIndexChanged.connect(lambda i: setattr(self.engine, "device_idx", self.dev.itemData(i)))
            side.addWidget(self.dev)
            if self.dev.count():
                self.engine.device_idx = self.dev.itemData(0)
            self.gain = QSlider(Qt.Horizontal); self.gain.setRange(0, 100); self.gain.setValue(80)
            self.gain.valueChanged.connect(lambda v: setattr(self.engine, "gain", v / 100))
            side.addWidget(QLabel("[Gain]")); side.addWidget(self.gain)
            self.excl = QCheckBox("Exclusive (one voice)"); self.excl.setChecked(True)
            self.excl.stateChanged.connect(lambda s: setattr(self.engine, "exclusive", bool(s)))
            self.hover = QCheckBox("Trigger on hover")
            self.hover.stateChanged.connect(lambda s: setattr(self, "hover_active", bool(s)))
            side.addWidget(self.excl); side.addWidget(self.hover)

            side.addWidget(QLabel("\n[Point]"))
            self.meta_lbl = QLabel("click a point to audition")
            self.meta_lbl.setWordWrap(True); self.meta_lbl.setTextFormat(Qt.PlainText)
            self.meta_lbl.setAlignment(Qt.AlignTop | Qt.AlignLeft); self.meta_lbl.setMinimumHeight(340)
            self.meta_lbl.setStyleSheet("background:#1a1a1a; border:1px dashed #333; padding:6px; color:#00ff88;")
            side.addWidget(self.meta_lbl)
            side.addStretch()

            # fixed action area -----------------------------------
            mrow = QHBoxLayout()
            self.mark_btn = QPushButton("Mark / unmark  (M)")
            self.mark_btn.setToolTip("Add the point you are hearing to the marked set (white ring), or remove it.")
            self.mark_btn.clicked.connect(self._toggle_mark)
            clear = QPushButton("Clear"); clear.setFixedWidth(70); clear.clicked.connect(self._clear_marks)
            mrow.addWidget(self.mark_btn); mrow.addWidget(clear)
            act.addLayout(mrow)
            self.marks_lbl = QLabel(""); self.marks_lbl.setStyleSheet("color:#ff9966;"); self.marks_lbl.setWordWrap(True)
            act.addWidget(self.marks_lbl)

            g = QGridLayout()
            self.n_spin = QSpinBox(); self.n_spin.setRange(2, 48); self.n_spin.setValue(12)
            self.n_spin.setToolTip("How many new points one exploration action adds.")
            g.addWidget(QLabel("Explore from marked points   new points:"), 0, 0, 1, 2)
            g.addWidget(self.n_spin, 0, 2)
            self.b_around = QPushButton("Around")
            self.b_around.setToolTip("New variations close to each marked point in parameter space.\n"
                                     "Each repeat in the same lineage looks closer (smaller steps).")
            self.b_between = QPushButton("Between")
            self.b_between.setToolTip("New variations on the straight path between marked points\n"
                                      "(needs at least two marks).")
            self.b_seeds = QPushButton("Other seeds")
            self.b_seeds.setToolTip("Exactly the same parameters with new random seeds:\n"
                                    "hear what is chance and what is the configuration.")
            for i, b in enumerate((self.b_around, self.b_between, self.b_seeds)):
                b.setStyleSheet("background:#1d2a44; color:#cfe0ff;")
                g.addWidget(b, 1, i)
            self.b_around.clicked.connect(lambda: self._explore("around"))
            self.b_between.clicked.connect(lambda: self._explore("between"))
            self.b_seeds.clicked.connect(lambda: self._explore("seeds"))
            act.addLayout(g)
            self.explore_lbl = QLabel(""); self.explore_lbl.setWordWrap(True); self.explore_lbl.setStyleSheet("color:#8899aa;")
            act.addWidget(self.explore_lbl)

            self.render_btn = QPushButton("▶  RENDER CURRENT  (full length)")
            self.render_btn.setToolTip("Render the point you are hearing on the whole Sound in Praat.")
            self.render_btn.setStyleSheet("background:#0a4d2e; color:white; font-size:13px; min-height:34px;")
            self.render_btn.clicked.connect(self._render)
            act.addWidget(self.render_btn)
            brow = QHBoxLayout()
            cache_btn = QPushButton("Manage Cache…")
            cache_btn.setToolTip("Disk usage of saved maps, Open Folder, Clear Current Exploration, Clear All Cache.")
            cache_btn.clicked.connect(self._manage_cache)
            brow.addWidget(cache_btn)
            cancel = QPushButton("✕  Close (no render)"); cancel.clicked.connect(self.close)
            panic = QPushButton("■  PANIC (Esc)")
            panic.setStyleSheet("background:#880000; color:white;"); panic.clicked.connect(self.engine.panic)
            brow.addWidget(cancel); brow.addWidget(panic)
            act.addLayout(brow)

            self.plot = pg.PlotWidget(); self.plot.setBackground("#0a0a0a")
            self.plot.showGrid(x=True, y=True, alpha=0.12)
            self.plot.getViewBox().setMouseMode(pg.ViewBox.PanMode)
            self.lines = pg.PlotDataItem(pen=pg.mkPen((120, 120, 140, 160), width=1), connect="pairs")
            self.plot.addItem(self.lines)
            self.scatter = pg.ScatterPlotItem(hoverable=True)
            self.scatter.sigClicked.connect(self._on_click); self.scatter.sigHovered.connect(self._on_hover)
            self.plot.addItem(self.scatter)
            self.mark_item = pg.ScatterPlotItem(size=24, brush=pg.mkBrush(0, 0, 0, 0), pen=pg.mkPen((255, 255, 255), width=2.5))
            self.cur_item = pg.ScatterPlotItem(size=18, brush=pg.mkBrush(0, 0, 0, 0), pen=pg.mkPen((0, 255, 136), width=2))
            self.plot.addItem(self.mark_item); self.plot.addItem(self.cur_item)
            layout.addWidget(col_w)
            layout.addWidget(self.plot, stretch=1)

            for w in (self.view, self.xsel, self.ysel, self.csel):
                w.currentIndexChanged.connect(self._redraw)
            for w in (self.ring_check, self.lineage_check):
                w.stateChanged.connect(self._redraw)

        # ── state ───────────────────────────────────────────────
        def _restore(self):
            s = state
            self.view.setCurrentIndex(int(s.get("view", 0)))
            for combo, key, default in ((self.xsel, "x", "grain_size_ms"), (self.ysel, "y", "synthesis_overlap"),
                                        (self.csel, "colour", "origin")):
                i = combo.findData(s.get(key, default))
                combo.setCurrentIndex(i if i >= 0 else max(0, combo.findData(default)))
            self.ring_check.setChecked(bool(s.get("ring", True)))
            self.lineage_check.setChecked(bool(s.get("lineage", True)))
            self.gain.setValue(int(s.get("gain", 80)))
            self.excl.setChecked(bool(s.get("exclusive", True)))
            self.hover.setChecked(bool(s.get("hover", False)))
            self.n_spin.setValue(int(s.get("batch", 12)))
            dev = s.get("device")
            if dev:
                for i in range(self.dev.count()):
                    if self.dev.itemText(i) == dev:
                        self.dev.setCurrentIndex(i)
            if s.get("current") in by_vid:
                self.current = by_vid[s["current"]]
                self.meta_lbl.setText(self._describe(variations[self.current]))
            geo = s.get("geometry")
            if geo:
                try:
                    import base64
                    self.restoreGeometry(QByteArray(base64.b64decode(geo)))
                except Exception:
                    pass
            self._update_marks_label()

        def _snapshot(self):
            import base64
            return {"view": self.view.currentIndex(), "x": self.xsel.currentData(), "y": self.ysel.currentData(),
                    "colour": self.csel.currentData(), "ring": self.ring_check.isChecked(),
                    "lineage": self.lineage_check.isChecked(), "gain": self.gain.value(),
                    "exclusive": self.excl.isChecked(), "hover": self.hover.isChecked(),
                    "batch": self.n_spin.value(), "device": self.dev.currentText(),
                    "marks": list(self.marks),
                    "current": variations[self.current]["vid"] if self.current is not None else None,
                    "geometry": base64.b64encode(bytes(self.saveGeometry())).decode(),
                    "saved": time.strftime("%Y-%m-%d %H:%M:%S")}

        # ── audio ───────────────────────────────────────────────
        def _audio(self, v):
            if v["vid"] not in self.cache:
                try:
                    a, sr = sf.read(os.path.join(st.pdir, v["mp3"]), dtype="float32", always_2d=True)
                    a = a[:, 0].copy() if a.shape[1] == 1 else a
                except Exception as e:
                    logging.error(f"Decode failed for {v['vid']}: {e}")
                    a, sr = None, 44100
                self.cache[v["vid"]] = (a, sr)
            return self.cache[v["vid"]]

        # ── geometry ────────────────────────────────────────────
        def _axis(self, v, key):
            val = v["params"][key]
            if key == "markov_order":
                return (1.0 if val == ORDER_VALUES[1] else 0.0) + ((v["n"] * 37) % 17 - 8) / 100.0
            if P[key][5] == "log":
                return math.log10(max(float(val), 1e-9))
            return float(val)

        def _pos(self, v):
            if self.view.currentIndex() == 0:
                return tuple(coords[v["vid"]])
            return (self._axis(v, self.xsel.currentData()), self._axis(v, self.ysel.currentData()))

        def _color(self, v):
            ck = self.csel.currentData()
            if ck == "origin":
                return ORIGIN_COLORS.get(v.get("origin"), (200, 200, 200))
            if ck == "round":
                u = v.get("round", 0) / max(1, last_round)
            else:
                if ck == "stereo_decorrelation" and v["params"][ck] < 0:
                    return (150, 150, 150)
                u = value_to_u(ck, v["params"][ck])
            u = min(1.0, max(0.0, u))
            return (int(40 + 215 * u), int(90 + 60 * (1 - abs(2 * u - 1))), int(230 - 190 * u))

        def _redraw(self):
            pv = self.view.currentIndex() == 1
            self.xsel.setEnabled(pv); self.ysel.setEnabled(pv)
            spots = []
            for i, v in enumerate(variations):
                ext = bool(v.get("extremes")) and self.ring_check.isChecked()
                newest = v.get("round", 0) == last_round and last_round > 0
                spots.append({"pos": self._pos(v), "size": 14 if newest else 11,
                              "brush": pg.mkBrush(*self._color(v), 225),
                              "pen": pg.mkPen((255, 255, 255), width=1.5) if ext else pg.mkPen(None), "data": i})
            self.scatter.setData(spots)
            xs, ys = [], []
            if self.lineage_check.isChecked() and last_round > 0:
                for v in variations:
                    if v.get("round") == last_round:
                        for pv_ in v.get("parents", []):
                            if pv_ in by_vid:
                                a, b = self._pos(variations[by_vid[pv_]]), self._pos(v)
                                xs += [a[0], b[0]]; ys += [a[1], b[1]]
            self.lines.setData(xs, ys)
            pi = self.plot.getPlotItem()
            for axis_name, key in (("bottom", self.xsel.currentData()), ("left", self.ysel.currentData())):
                ax = pi.getAxis(axis_name)
                if pv and P[key][5] == "log":
                    lo, hi = P[key][3], P[key][4]
                    ax.setTicks([[(math.log10(t), str(t)) for t in (1, 2, 4, 8, 16, 20, 50, 100, 200, 400)
                                  if lo <= t <= hi], []])
                elif pv and key == "markov_order":
                    ax.setTicks([[(0.0, "First"), (1.0, "Second")], []])
                else:
                    ax.setTicks(None)
            if pv:
                xk, yk = self.xsel.currentData(), self.ysel.currentData()
                pi.setLabel("bottom", LABEL[xk] + (" (log axis)" if P[xk][5] == "log" else ""))
                pi.setLabel("left", LABEL[yk] + (" (log axis)" if P[yk][5] == "log" else ""))
            else:
                pi.setLabel("bottom", f"PC1 ({100 * evr[0]:.1f}% of descriptor variance)")
                pi.setLabel("left", f"PC2 ({100 * evr[1]:.1f}% of descriptor variance)")
            pi.getViewBox().autoRange()
            ck = self.csel.currentData()
            if ck == "origin":
                self.legend.setText("yellow centre | red boundary | green interior | violet around | "
                                    "blue between | orange other seeds | larger = newest round")
            elif ck == "round":
                self.legend.setText(f"blue = round 0 .. red = round {last_round}")
            else:
                self.legend.setText(f"blue = min .. red = max of {LABEL[ck]}"
                                    + (" | grey = mono" if ck == "stereo_decorrelation" else ""))
            self._overlays()

        def _overlays(self):
            self.cur_item.setData([{"pos": self._pos(variations[self.current])}] if self.current is not None else [])
            self.mark_item.setData([{"pos": self._pos(variations[by_vid[m]])} for m in self.marks])

        # ── interaction ─────────────────────────────────────────
        def _describe(self, v):
            lines = [f"#{v['n']}  |  {v.get('origin')}  |  round {v.get('round', 0)}", v.get("note", ""),
                     f"seed {v['seed']}   id {v['vid']}"]
            if v.get("parents"):
                lines.append("from " + ", ".join(f"#{variations[by_vid[p]]['n']}" if p in by_vid else p
                                                 for p in v["parents"]))
            lines.append("")
            for k in SAMPLED:
                tag = v.get("extremes", {}).get(k, "")
                shown = "mono (-1)" if tag == "mono" else v["params_text"][k]
                lines.append(f"{LABEL[k]:<28s} {shown:>12s}  {('[' + tag.upper() + ']') if tag in ('min', 'max') else ''}")
            if v.get("repaired"):
                lines += ["", "adjusted to stay valid: " + ", ".join(LABEL[k] for k in v["repaired"])]
            d = v["descriptors"]
            rs = v.get("render_s")
            lines += ["", f"render {rs:.2f} s (measured)" if rs is not None else "render time not recorded",
                      f"rms {d['rms_mean']:.4f} | centroid {d['centroid_mean']:.0f} Hz",
                      f"onsets/s {d['onset_density']:.2f} | recurrence {d['recurrence_rate']:.2f}",
                      f"diversity {d['frame_diversity']:.1f} | L/R corr {d['lr_correlation']:+.2f}"]
            return "\n".join(lines)

        def _index_of_n(self, n):
            """row of the point with display number #n (or None)"""
            return next((i for i, v in enumerate(variations) if v["n"] == n), None)

        def _audition(self, i):
            self.current = i
            v = variations[i]
            a, sr = self._audio(v)
            self.engine.play(v["vid"], a, sr)
            self.meta_lbl.setText(("▶ " if a is not None else "(decode failed) ") + self._describe(v))
            self._overlays()

        def _on_click(self, _item, points):
            if len(points) > 0:
                self._audition(points[0].data())

        def _on_hover(self, _item, points):
            if len(points) == 0:
                return
            i = points[0].data()
            if self.hover_active:
                now = time.time()
                if now - self.last_hover_t > 0.15:
                    self._audition(i)
                    self.last_hover_t = now

        def _toggle_mark(self):
            if self.current is None:
                self.explore_lbl.setText("Audition a point first, then mark it.")
                return
            vid = variations[self.current]["vid"]
            if vid in self.marks:
                self.marks.remove(vid)
            else:
                self.marks.append(vid)
            self._update_marks_label()
            self._overlays()

        def _clear_marks(self):
            self.marks = []
            self._update_marks_label()
            self._overlays()

        def _update_marks_label(self):
            n = len(self.marks)
            self.marks_lbl.setText("marked: " + (", ".join(f"#{variations[by_vid[m]]['n']}" for m in self.marks) if n else "none"))
            self.b_around.setEnabled(n >= 1)
            self.b_seeds.setEnabled(n >= 1)
            self.b_between.setEnabled(n >= 2)

        def _explore(self, action):
            parents = [variations[by_vid[m]] for m in self.marks]
            known = st.complete_vids() | st.queued_vids()
            import numpy as np
            m = st.meta()
            rs = hashlib.sha1(json.dumps([self.marks, int(m.get("round", 0)), action]).encode()).hexdigest()
            rng = np.random.default_rng(int(rs[:8], 16))
            n = self.n_spin.value()
            if action == "around":
                cfgs = around(parents, n, known, adur, pdur, rng)
            elif action == "between":
                cfgs = between(parents, n, known, adur, pdur)
            else:
                cfgs = other_seeds(parents, n, known, adur, pdur)
            if not cfgs:
                self.explore_lbl.setText("All of those configurations already exist in this map; nothing new to render.")
                return
            queued = st.add_batch(cfgs, action, [p["vid"] for p in parents], adur)
            self.result = "refine"
            write_kv_tsv(status_path, {"status": "refine", "queued": queued, "action": action})
            self.close()

        def _render(self):
            if self.current is None:
                self.explore_lbl.setText("Audition a point first; RENDER renders the point you are hearing.")
                return
            v = variations[self.current]
            atomic_write_text(man["selection_tsv"], "\t".join(SEL_COLS) + "\n" +
                              "\t".join([v["vid"], f"p{v['n']:03d}", str(v["seed"])] +
                                        [v["params_text"][k] for k in SAMPLED]) + "\n")
            mm = st.meta()
            mm.setdefault("rendered", []).append({"vid": v["vid"], "n": v["n"], "time": time.strftime("%Y-%m-%d %H:%M:%S")})
            st.save_meta(mm)
            self.result = "selected"
            write_kv_tsv(status_path, {"status": "selected", "id": v["vid"]})
            self.close()

        # ── cache management ────────────────────────────────────
        def _manage_cache(self):
            from PySide6.QtWidgets import (QDialog, QTableWidget, QTableWidgetItem, QHeaderView,
                                           QAbstractItemView)
            inv = cache_inventory(man["temp_dir"], man["token"], st.path)
            dlg = QDialog(self)
            dlg.setWindowTitle("Manage Cache — Generative Exploration Map")
            dlg.setMinimumSize(760, 420)
            lay = QVBoxLayout(dlg)
            n_pts = sum(m["points"] for m in inv["maps"])
            n_mp3 = sum(m["mp3"] for m in inv["maps"])
            summary = (f"v1.1: {len(inv['maps'])} map(s), {n_pts} points, {n_mp3} MP3 files, "
                       f"{fmt_bytes(inv['v11_bytes'])}\n"
                       f"legacy v1.0 / v1.0.1: {len(inv['legacy'])} session(s), "
                       f"{sum(l['mp3'] for l in inv['legacy'])} MP3 files, {fmt_bytes(inv['legacy_bytes'])}")
            if inv["pending"]:
                summary += (f"\ninterrupted deletions awaiting cleanup: {len(inv['pending'])} "
                            f"({fmt_bytes(sum(x['bytes'] for x in inv['pending']))})")
            summary += f"\nlocation: {legacy_root()}"
            top = QLabel(summary); top.setWordWrap(True)
            lay.addWidget(top)
            rows = inv["maps"] + inv["legacy"]
            tab = QTableWidget(len(rows), 7)
            tab.setHorizontalHeaderLabels(["Source", "Kind", "Points", "MP3", "Size", "Last used", "Status"])
            tab.setEditTriggers(QAbstractItemView.NoEditTriggers)
            tab.setSelectionMode(QAbstractItemView.NoSelection)
            tab.verticalHeader().setVisible(False)
            tab.setStyleSheet("QTableWidget { background:#161616; color:#ddd; gridline-color:#333; } "
                              "QHeaderView::section { background:#222; color:#ccc; }")
            for r, x in enumerate(rows):
                status = ("current map" if x.get("current") else
                          "in use by another session" if x.get("in_use") and x["kind"] == "v1.1" else
                          "possibly running (recent)" if x.get("in_use") else "")
                kind = "v1.1" if x["kind"] == "v1.1" else f"legacy v{x['version']}"
                when = time.strftime("%Y-%m-%d %H:%M", time.localtime(x["last_used"])) if x["last_used"] else "?"
                for c, val in enumerate([x["source"], kind, str(x["points"]), str(x["mp3"]),
                                         fmt_bytes(x["bytes"]), when, status]):
                    tab.setItem(r, c, QTableWidgetItem(val))
            tab.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
            for c in range(1, 7):
                tab.horizontalHeader().setSectionResizeMode(c, QHeaderView.ResizeToContents)
            lay.addWidget(tab, stretch=1)
            row = QHBoxLayout()
            b_open = QPushButton("Open Folder")
            b_cur = QPushButton("Clear Current Exploration…")
            b_all = QPushButton("Clear All Cache…")
            b_close = QPushButton("Close")
            for b in (b_cur, b_all):
                b.setStyleSheet("background:#3a1a1a; color:#ffcccc;")
            for b in (b_open, b_cur, b_all, b_close):
                row.addWidget(b)
            lay.addLayout(row)
            b_open.clicked.connect(lambda: open_folder(legacy_root()))
            b_close.clicked.connect(dlg.reject)
            b_cur.clicked.connect(lambda: self._clear_current(dlg))
            b_all.clicked.connect(lambda: self._clear_all(dlg, inv))
            self._cache_dialog = dlg
            dlg.exec()

        def _clear_current(self, dlg=None):
            size, _ = dir_usage(st.path)
            n_mp3 = len(os.listdir(st.pdir))
            text = (f"Delete the saved exploration of '{meta.get('source', {}).get('source_name', '?')}'?\n\n"
                    f"  {len(st.complete_vids())} points, {n_mp3} MP3 files, {meta.get('round', 0) + 1} round(s), "
                    f"{fmt_bytes(size)}\n  {st.path}\n\n"
                    "Its exploration history, marks and selections are deleted too. The map closes and "
                    "nothing is rendered; next time this Sound starts again from a new initial set.\n"
                    "The original Sound and other maps are not touched.")
            if not confirm_dialog(self, "Clear Current Exploration", text):
                return
            self.result = "delete_current"
            if dlg is not None:
                dlg.accept()
            self.close()

        def _clear_all(self, dlg, inv):
            blocked = clear_all_check(man["temp_dir"], man["token"], include_legacy=False)
            if blocked:
                info_dialog(self, "Clear All Cache refused",
                            "Another live session is using the cache, so nothing is deleted:\n  " +
                            "\n  ".join(blocked) + "\n\nClose that session and try again.")
                return
            ok, legacy = confirm_clear_all(self, inv)
            if not ok:
                return
            if legacy:
                blocked = clear_all_check(man["temp_dir"], man["token"], include_legacy=True)
                if blocked:
                    info_dialog(self, "Clear All Cache refused",
                                "A legacy session may still be running, so nothing is deleted:\n  " +
                                "\n  ".join(blocked))
                    return
            self.result = "delete_all"
            self.delete_legacy = legacy
            if dlg is not None:
                dlg.accept()
            self.close()

        def keyPressEvent(self, e):
            if e.key() == Qt.Key_Escape:
                self.engine.panic()
            elif e.key() == Qt.Key_M:
                self._toggle_mark()
            else:
                super().keyPressEvent(e)

        def closeEvent(self, e):
            self.engine.panic()
            self.cache.clear()
            if self.result.startswith("delete"):
                e.accept()
                return
            try:
                st.save_state(self._snapshot())
            except Exception as ex:
                logging.warning(f"Could not save GUI state: {ex}")
            if self.result == "cancelled":
                write_kv_tsv(status_path, {"status": "cancelled"})
            e.accept()

    app = QApplication.instance() or QApplication(sys.argv)
    win = Window()
    win.show()
    print("[Py] Success. GUI launched.")
    app.exec()
    return win.result, win.delete_legacy


def open_folder(path: str):
    os.makedirs(path, exist_ok=True)
    try:
        if sys.platform.startswith("win"):
            os.startfile(path)
        else:
            import subprocess
            subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", path])
    except Exception as e:
        logging.warning(f"Open Folder failed: {e}")


def phase_explore(man: dict):
    status_path = man["explore_status"]
    token = man["token"]
    st = None
    result = "error"
    with_legacy = False
    try:
        for pkg in ["numpy", "librosa", "soundfile", "sounddevice", "sklearn", "pyqtgraph", "PySide6"]:
            __import__(pkg)
        heartbeat(run_lock_path(man["temp_dir"], token))
        st = Store(man["store_dir"])
        n_new = st.ingest(beat=lambda: heartbeat(run_lock_path(man["temp_dir"], token)))
        logging.info(f"ingested {n_new} new variation(s)")
        ok = [v for v in st.variations() if v.get("status") == "ok"]
        if not ok:
            raise RuntimeError("No preview rendered successfully; nothing to explore.")
        prev = read_json(os.path.join(st.path, "projection.json"), {}) or {}
        coords, evr, resid, n_anchor = project_aligned([v["vid"] for v in ok], [v["descriptors"] for v in ok],
                                                       prev.get("coords", {}))
        atomic_write_json(os.path.join(st.path, "projection.json"),
                          {"coords": coords, "explained_variance_ratio": evr, "anchor_residual": resid,
                           "n_anchors": n_anchor, "n_points": len(ok), "method": "z-score + PCA(2) + similarity Procrustes",
                           "time": time.strftime("%Y-%m-%d %H:%M:%S")})
        write_kv_tsv(status_path, {"status": "cancelled"})
        result, with_legacy = run_gui(st, man, coords, evr, resid, n_anchor, status_path)
        if result == "delete_current":
            st.release(token)
            ok, freed, fails = safe_delete(st.path, token)
            write_kv_tsv(status_path, {"status": "deleted", "scope": "current", "freed": fmt_bytes(freed),
                                       "failures": len(fails), "message":
                                       (f"Current exploration deleted ({fmt_bytes(freed)} freed)." if ok else
                                        "Current exploration NOT fully deleted: " + " | ".join(fails[:5]) +
                                        (" | the rest is finished automatically next run" if freed else ""))})
            st = None
        elif result == "delete_all":
            st.release(token)
            rep = clear_all(man["temp_dir"], token, with_legacy)
            if rep["refused"]:
                msg = "Clear All refused, nothing deleted - in use: " + "; ".join(rep["refused"])
            elif rep["failures"]:
                msg = (f"Clear All: {rep['removed']} of {rep['targets']} folder(s) fully deleted, "
                       f"{fmt_bytes(rep['freed'])} freed. Could not delete: " + " | ".join(rep["failures"][:5]) +
                       " (left in .gemdeleting folders, finished automatically next run)")
            else:
                msg = (f"Clear All: {rep['removed']} folder(s) deleted" +
                       (" incl. legacy sessions" if with_legacy else "") + f", {fmt_bytes(rep['freed'])} freed.")
            write_kv_tsv(status_path, {"status": "deleted", "scope": "all", "freed": fmt_bytes(rep["freed"]),
                                       "failures": len(rep["failures"]), "refused": len(rep["refused"]),
                                       "message": msg})
            st = None
    except ImportError as e:
        write_kv_tsv(status_path, {"status": "error", "message": f"Missing Python package: {e.name}. "
                                   "Run: pip install numpy librosa soundfile sounddevice scikit-learn pyqtgraph PySide6"})
    except Exception as e:
        logging.exception("explore failed")
        write_kv_tsv(status_path, {"status": "error", "message": str(e)})
    finally:
        # the store stays locked while Praat renders a refinement batch;
        # otherwise this run is done with it
        if st is not None and result != "refine" and os.path.isdir(st.path):
            st.release(token)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("plan", "explore"):
        print("ERROR: Usage: python generative_exploration_map.py plan|explore <manifest.json>", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[2], encoding="utf-8") as f:
        manifest = json.load(f)
    (phase_plan if sys.argv[1] == "plan" else phase_explore)(manifest)
