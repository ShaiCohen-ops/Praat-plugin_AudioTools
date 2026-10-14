"""Acoustic Morphology Composer 1.2.1
Geometry-Driven Spectral Transformation and Spatial Resynthesis

    Draw the space.  Shape the sound.  Compose its transformation.

Praat AudioTools - Hybrid Systems
Author:      Shai Cohen
Affiliation: Department of Music, Bar-Ilan University, Israel
Email:       shai.cohen@biu.ac.il
License:     MIT License
Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools

Draw a two-dimensional acoustic space (walls, obstacles, openings, one
source, up to four microphones); a finite-difference time-domain wave
simulation computes its impulse response at each microphone, and those
responses filter the recording.  Spaces are stored as acoustic states,
compared, and sequenced on a timeline.

FILES - the whole tool is two files, side by side in plugin_AudioTools/py/:
    Acoustic_Morphology_Composer.praat   Praat launcher (select a Sound, run it)
    acoustic_morphology_composer.py      this file: acoustic core, GUI, manual,
                                         examples and self-test

REQUIREMENTS - Python 3.9+:
    python -m pip install PySide6 numpy scipy soundfile pyqtgraph sounddevice
    (sounddevice is optional: audition only)

COMMAND LINE
    python acoustic_morphology_composer.py                    standalone window
    python acoustic_morphology_composer.py --project FILE     open a project
    python acoustic_morphology_composer.py --selftest [--praat PRAAT_EXE ...]
    python acoustic_morphology_composer.py --make-example DIR
    python acoustic_morphology_composer.py --validate DIR [--quality Q]
    python acoustic_morphology_composer.py --manual            print the manual
    (the Praat launcher calls it with a session manifest)

The full manual - workflow, interface, states, timeline, presets, projects,
tests, troubleshooting and the acoustic model with its measured accuracy - is
MANUAL near the end of this file; in the window it is under Help.

LAYOUT OF THIS FILE
    geometry - FDTD solver - impulse responses - rendering - states and
    timeline - project files - presets - GUI (common, editor, panels,
    timeline) - session protocol and main window - examples and validation -
    self-test - manual - command line

Changelog v1.2.1 (2026):
  - Session folders: removed after every run on Windows too, created in
    %TEMP% instead of the home folder; empty leftovers from earlier runs are
    cleaned up at start (remove_stale_sessions; only EMPTY AMC_session_*
    folders are ever removed).
Changelog v1.2 (2026):
  - FIX (critical): the dry signal was added once PER MICROPHONE in the mono
    and stereo mixes of a state (3 microphones at 0 % wet = 3x the source).
    One mixing function (mix_output) now serves single states, timelines,
    previews and bypass: dry exactly once; microphone gain and pan act on the
    wet layer only; a mono source sits equal-power in stereo (-3 dB per
    channel) everywhere - single-state renders had used full level, the
    timeline -3 dB, and the single-state stereo mix had panned the dry signal
    with each microphone.
  - Mixes of N microphones are scaled by 1/sqrt(N), so adding a microphone
    keeps the mix power about constant instead of making it louder.
  - Preview runs in its own background worker (the window never blocks, and
    a preview can run while a simulation computes).
  - Preview == Render: both call render_main() with the same settings; a
    preview plays its region of the FULL render (formerly the region was
    rendered alone, in tail mode, with its own peak protection - so it
    lacked reverberation from earlier sound and could differ in level).
    The result is cached and shared, so Render after a preview is instant.
  - Timeline memory: weights are evaluated block by block and the input
    crossfade is a block (overlap-add) convolution - no full-length weight
    curve per state.  finish() and the dry path work in place.  A 120 s
    stereo timeline render: peak 647 MB -> 141 MB, 3.7 s -> 1.8 s.
  - Cache key: microphone ids added (a new microphone at an old position
    used to match a cached response that has no entry for it, and was then
    silently missing from renders).  Responses saved by v1.0/1.1 are
    therefore marked outdated once; press Compute all outdated.
  - Render report: RMS re source, peak before protection, the protection
    gain, and a WARNING when protection had to remove more than 6 dB.
  - Render / Preview composition with uncomputed timeline states (e.g. right
    after loading the Moving Aperture preset) now offers to compute them and
    then continues automatically, instead of only refusing.
  - Self-test: tests 10-15 (one per review item) and new GUI checks.
Changelog v1.1 (2026):
  - Everything in two files: the former amc_core/ and amc_gui/ packages,
    the examples, the tests and the documentation are merged into this file.
    --selftest replaces pytest (same tests; test 9 with --praat),
    --make-example / --validate replace the example scripts, Help shows the
    manual.  The acoustics and the GUI are unchanged.
  - Windows: Praat's UTF-16 console output is decoded in the Praat test.
Changelog v1.0 (2026):
  - Initial release.
"""
from __future__ import annotations

import copy
import hashlib
import html
import json
import math
import numpy as np
import os
import pyqtgraph as pg
import re
import shutil
import soundfile as sf
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import uuid
from PySide6 import QtCore, QtGui, QtWidgets
from dataclasses import asdict, dataclass, field
from fractions import Fraction
from scipy import signal
from typing import Callable, Dict, List, Optional, Tuple
from types import SimpleNamespace

APP_NAME = "Acoustic Morphology Composer"
APP_VERSION = "1.2.1"
SOLVER_VERSION = "amc-fdtd-1.0"
HERE = os.path.dirname(os.path.abspath(__file__))


# ============================================================================
# GEOMETRY
# ============================================================================
# Geometry model for the Acoustic Morphology Composer.
#
# All coordinates are in metres, origin at the lower-left corner of the room
# (the simulation domain), x to the right, y upwards.
#
# Primitives (deliberately few and robust - no free-form polygons):
#
#   wall     straight segment (x0,y0)-(x1,y1) with a thickness
#   rect     solid rectangular obstacle (x0,y0)-(x1,y1)
#   opening  rectangular region that is forced to AIR; it cuts doors and
#            apertures through walls and obstacles
#
# Each wall / rect carries a material: absorption coefficient alpha in [0, 0.99]
# (0 = rigid).  alpha is a frequency-independent, normal-incidence value; see
# the manual (Part 2, the acoustic model) for what that approximation means.
#
# The room boundary (outer edges of the domain) is one of
#   rigid      perfectly reflecting
#   partial    locally reacting, frequency-independent absorption alpha
#   absorbing  perfectly matched layer (open field: waves leave the domain)
ELEMENT_KINDS = ("wall", "rect", "opening")
BOUNDARY_MODES = ("rigid", "partial", "absorbing")
MAX_MICS = 4
MIN_ROOM = 0.3     # m
MAX_ROOM = 30.0    # m


class GeometryError(ValueError):
    """Raised for geometry that cannot be simulated."""


def new_id(prefix: str) -> str:
    return f"{prefix}{uuid.uuid4().hex[:6]}"


@dataclass
class Element:
    kind: str
    x0: float
    y0: float
    x1: float
    y1: float
    thickness: float = 0.06      # walls only
    alpha: float = 0.0           # absorption (walls / rects)
    id: str = ""

    def __post_init__(self):
        if not self.id:
            self.id = new_id(self.kind[0])

    def bbox(self) -> Tuple[float, float, float, float]:
        if self.kind == "wall":
            h = self.thickness / 2
            return (min(self.x0, self.x1) - h, min(self.y0, self.y1) - h,
                    max(self.x0, self.x1) + h, max(self.y0, self.y1) + h)
        return (min(self.x0, self.x1), min(self.y0, self.y1),
                max(self.x0, self.x1), max(self.y0, self.y1))

    def length(self) -> float:
        return math.hypot(self.x1 - self.x0, self.y1 - self.y0)


@dataclass
class Mic:
    x: float
    y: float
    name: str = "M1"
    enabled: bool = True
    gain_db: float = 0.0
    pan: float = 0.0             # -1 = left, +1 = right (stereo mix)
    id: str = ""

    def __post_init__(self):
        if not self.id:
            self.id = new_id("m")


@dataclass
class Boundary:
    mode: str = "partial"
    alpha: float = 0.1


@dataclass
class Geometry:
    width: float = 4.0
    height: float = 3.0
    elements: List[Element] = field(default_factory=list)
    source: Tuple[float, float] = (1.0, 1.5)
    mics: List[Mic] = field(default_factory=list)
    boundary: Boundary = field(default_factory=Boundary)

    # ------------------------------------------------------------------ io
    def to_dict(self) -> dict:
        return {
            "width": self.width, "height": self.height,
            "elements": [asdict(e) for e in self.elements],
            "source": [float(self.source[0]), float(self.source[1])],
            "mics": [asdict(m) for m in self.mics],
            "boundary": asdict(self.boundary),
        }

    @staticmethod
    def from_dict(d: dict) -> "Geometry":
        """Build a Geometry from untrusted data, validating every field."""
        if not isinstance(d, dict):
            raise GeometryError("geometry must be an object")
        w = _num(d.get("width"), "width", MIN_ROOM, MAX_ROOM)
        h = _num(d.get("height"), "height", MIN_ROOM, MAX_ROOM)
        els = []
        raw = d.get("elements", [])
        if not isinstance(raw, list) or len(raw) > 500:
            raise GeometryError("elements must be a list (max 500)")
        for e in raw:
            if not isinstance(e, dict):
                raise GeometryError("element must be an object")
            kind = e.get("kind")
            if kind not in ELEMENT_KINDS:
                raise GeometryError(f"unknown element kind {kind!r}")
            els.append(Element(
                kind=kind,
                x0=_num(e.get("x0"), "x0", -MAX_ROOM, 2 * MAX_ROOM),
                y0=_num(e.get("y0"), "y0", -MAX_ROOM, 2 * MAX_ROOM),
                x1=_num(e.get("x1"), "x1", -MAX_ROOM, 2 * MAX_ROOM),
                y1=_num(e.get("y1"), "y1", -MAX_ROOM, 2 * MAX_ROOM),
                thickness=_num(e.get("thickness", 0.06), "thickness", 0.001, 5.0),
                alpha=_num(e.get("alpha", 0.0), "alpha", 0.0, 0.99),
                id=_ident(e.get("id", "")),
            ))
        src = d.get("source")
        if not (isinstance(src, (list, tuple)) and len(src) == 2):
            raise GeometryError("source must be [x, y]")
        source = (_num(src[0], "source x", -MAX_ROOM, 2 * MAX_ROOM),
                  _num(src[1], "source y", -MAX_ROOM, 2 * MAX_ROOM))
        mics = []
        rawm = d.get("mics", [])
        if not isinstance(rawm, list) or len(rawm) > MAX_MICS:
            raise GeometryError(f"mics must be a list of at most {MAX_MICS}")
        for m in rawm:
            if not isinstance(m, dict):
                raise GeometryError("mic must be an object")
            mics.append(Mic(
                x=_num(m.get("x"), "mic x", -MAX_ROOM, 2 * MAX_ROOM),
                y=_num(m.get("y"), "mic y", -MAX_ROOM, 2 * MAX_ROOM),
                name=str(m.get("name", "M"))[:32],
                enabled=bool(m.get("enabled", True)),
                gain_db=_num(m.get("gain_db", 0.0), "mic gain", -60.0, 24.0),
                pan=_num(m.get("pan", 0.0), "mic pan", -1.0, 1.0),
                id=_ident(m.get("id", "")),
            ))
        b = d.get("boundary", {})
        if not isinstance(b, dict) or b.get("mode") not in BOUNDARY_MODES:
            raise GeometryError("boundary.mode must be rigid / partial / absorbing")
        boundary = Boundary(mode=b["mode"],
                            alpha=_num(b.get("alpha", 0.0), "boundary alpha", 0.0, 0.99))
        return Geometry(w, h, els, source, mics, boundary)

    def copy(self) -> "Geometry":
        return copy.deepcopy(self)

    def canonical_json(self) -> str:
        """Stable text used for cache keys.  Included: room, boundary, every
        element's kind / coordinates / thickness / absorption, source, and each
        microphone's POSITION and ID (responses are stored per microphone id,
        so a new microphone - even at an old position - needs its own
        response).  Excluded, because they do not change the simulation:
        element ids, microphone names, gains, pans and enabled flags (every
        microphone is always simulated)."""
        d = self.to_dict()
        for e in d["elements"]:
            e.pop("id", None)
            if e["kind"] != "wall":
                e.pop("thickness", None)
            if e["kind"] == "opening":
                e.pop("alpha", None)
        d["mics"] = [{"x": round(m["x"], 6), "y": round(m["y"], 6), "id": m["id"]} for m in d["mics"]]
        return json.dumps(_round(d), sort_keys=True)

    def mic_by_id(self, mid: str) -> Optional[Mic]:
        for m in self.mics:
            if m.id == mid:
                return m
        return None


def _round(o):
    if isinstance(o, float):
        return round(o, 6)
    if isinstance(o, dict):
        return {k: _round(v) for k, v in o.items()}
    if isinstance(o, list):
        return [_round(v) for v in o]
    return o


def _num(v, name, lo, hi) -> float:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise GeometryError(f"{name} must be a number")
    v = float(v)
    if not math.isfinite(v) or v < lo or v > hi:
        raise GeometryError(f"{name} = {v} outside [{lo}, {hi}]")
    return v


def _ident(v) -> str:
    s = str(v)[:40]
    return "".join(ch for ch in s if ch.isalnum() or ch in "_-")


# ---------------------------------------------------------------- raster


@dataclass
class Raster:
    """Geometry sampled on the simulation grid (user domain only, no PML)."""
    dx: float
    nx: int
    ny: int
    solid: np.ndarray          # bool (nx, ny)
    alpha: np.ndarray          # float (nx, ny), absorption of solid cells
    thin_openings: List[str] = field(default_factory=list)

    def cell_of(self, x: float, y: float) -> Tuple[int, int]:
        i = int(math.floor(x / self.dx))
        j = int(math.floor(y / self.dx))
        return min(max(i, 0), self.nx - 1), min(max(j, 0), self.ny - 1)


def rasterize(geom: Geometry, dx: float) -> Raster:
    nx = max(4, int(round(geom.width / dx)))
    ny = max(4, int(round(geom.height / dx)))
    xc = (np.arange(nx) + 0.5) * dx
    yc = (np.arange(ny) + 0.5) * dx
    X, Y = np.meshgrid(xc, yc, indexing="ij")
    solid = np.zeros((nx, ny), bool)
    alpha = np.zeros((nx, ny), float)
    for e in geom.elements:
        if e.kind == "wall":
            m = _segment_mask(X, Y, e, dx)
        elif e.kind == "rect":
            m = _rect_mask(X, Y, e, dx)
        else:
            continue
        solid |= m
        alpha[m] = np.maximum(alpha[m], e.alpha)
    thin = []
    for e in geom.elements:
        if e.kind != "opening":
            continue
        m = _rect_mask(X, Y, e, dx)
        solid &= ~m
        alpha[m] = 0.0
        wmin = min(abs(e.x1 - e.x0), abs(e.y1 - e.y0))
        if wmin < 2 * dx:
            thin.append(e.id)
    return Raster(dx, nx, ny, solid, alpha, thin)


def _rect_mask(X, Y, e: Element, dx: float) -> np.ndarray:
    x0, x1 = sorted((e.x0, e.x1))
    y0, y1 = sorted((e.y0, e.y1))
    # a rectangle always covers at least the cell its centre falls in
    if x1 - x0 < dx:
        xm = 0.5 * (x0 + x1); x0, x1 = xm - 0.5 * dx, xm + 0.5 * dx
    if y1 - y0 < dx:
        ym = 0.5 * (y0 + y1); y0, y1 = ym - 0.5 * dx, ym + 0.5 * dx
    return (X >= x0) & (X < x1) & (Y >= y0) & (Y < y1)


def _segment_mask(X, Y, e: Element, dx: float) -> np.ndarray:
    ax, ay, bx, by = e.x0, e.y0, e.x1, e.y1
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    if L2 < 1e-12:
        d = np.hypot(X - ax, Y - ay)
    else:
        t = np.clip(((X - ax) * vx + (Y - ay) * vy) / L2, 0.0, 1.0)
        d = np.hypot(X - (ax + t * vx), Y - (ay + t * vy))
    # half-diagonal floor keeps any wall 8-connected, hence airtight on the
    # staggered grid (pressure cells only couple through shared faces)
    half = max(e.thickness / 2.0, dx * 0.71)
    return d <= half


# ---------------------------------------------------------------- checks


@dataclass
class GeometryReport:
    errors: List[str]
    warnings: List[str]
    mic_connected: Dict[str, bool]


def check(geom: Geometry, raster: Raster) -> GeometryReport:
    """Validate positions against the raster.  Errors make simulation
    impossible; warnings flag results that need care."""
    from scipy import ndimage
    errors, warnings = [], []
    sx, sy = geom.source
    if not (0 <= sx < geom.width and 0 <= sy < geom.height):
        errors.append("The source lies outside the room.")
    si, sj = raster.cell_of(sx, sy)
    if raster.solid[si, sj]:
        errors.append("The source lies inside a wall or obstacle.")
    if not geom.mics:
        errors.append("Place at least one microphone.")
    if not any(m.enabled for m in geom.mics):
        errors.append("All microphones are disabled.")
    labels, _ = ndimage.label(~raster.solid)
    src_label = labels[si, sj]
    connected = {}
    for m in geom.mics:
        if not (0 <= m.x < geom.width and 0 <= m.y < geom.height):
            errors.append(f"Microphone {m.name} lies outside the room.")
            connected[m.id] = False
            continue
        mi, mj = raster.cell_of(m.x, m.y)
        if raster.solid[mi, mj]:
            errors.append(f"Microphone {m.name} lies inside a wall or obstacle.")
            connected[m.id] = False
            continue
        ok = labels[mi, mj] == src_label and src_label > 0
        connected[m.id] = bool(ok)
        if not ok:
            warnings.append(f"Microphone {m.name} is in a cavity with no air path to the "
                            "source: its response will be (numerically) silent.")
        if math.hypot(m.x - sx, m.y - sy) < 3 * raster.dx:
            warnings.append(f"Microphone {m.name} is within 3 grid cells of the source; "
                            "the near field is poorly resolved there.")
    for oid in raster.thin_openings:
        warnings.append(f"Opening {oid} is narrower than two grid cells: its transmission "
                        "is dominated by grid staircasing. Use a finer quality or a wider opening.")
    if raster.solid.all():
        errors.append("The whole room is solid.")
    return GeometryReport(errors, warnings, connected)


def snap(v: float, step: float) -> float:
    return round(v / step) * step if step > 0 else v



# ============================================================================
# FDTD SOLVER
# ============================================================================
# Two-dimensional pressure-velocity FDTD solver.
#
# Scheme
# ------
# Linear acoustics, first-order system on a staggered (Yee) grid:
#
#     dp/dt = -rho c^2 (dvx/dx + dvy/dy)        (pressure at cell centres)
#     dv/dt = -(1/rho) grad p                   (velocities on cell faces)
#
# Leapfrog in time.  Eliminating v gives the 2-D wave equation
# p_tt = c^2 (p_xx + p_yy); the scheme is second-order accurate in space and
# time and stable for the Courant number  lambda = c dt / dx <= 1/sqrt(2).
#
# Boundaries
# ----------
# * rigid       : normal velocity on the face is held at zero
# * impedance   : locally reacting face, v_n = p / Z with
#                 Z = rho c (1 + R) / (1 - R),  R = sqrt(1 - alpha)
#                 (frequency-independent, calibrated at normal incidence)
# * PML         : split-field perfectly matched layer (open field), cubic
#                 conductivity profile, backed by a rigid wall
#
# Source: soft (additive) pressure source in one cell driven by a band-limited
# impulse.  Receivers: bilinear interpolation over the neighbouring AIR cells.
C_AIR = 343.0
RHO_AIR = 1.204
LAMBDA_MAX = 1.0 / math.sqrt(2.0)

# Spatial step per quality.  The reliable bandwidth follows from the dispersion
# criterion (see bandwidth()) - it is computed, not assumed.
QUALITIES: Dict[str, dict] = {
    "Draft": {"dx": 0.030, "ir_length": 0.5},
    "Standard": {"dx": 0.015, "ir_length": 0.8},
    "High Resolution": {"dx": 0.0075, "ir_length": 1.0},
}

# measured on the development machine (cell-updates per second, NumPy, float32);
# refined at run time from the last simulation
_throughput = {"cells_per_s": 2.0e8}


class SimulationError(RuntimeError):
    """The simulation cannot run or produced an untrustworthy result."""


class Cancelled(Exception):
    """Raised when the user cancels a running simulation."""


@dataclass
class SimSettings:
    quality: str = "Standard"
    dx: Optional[float] = None          # overrides the quality's dx
    ir_length: Optional[float] = None   # s; overrides the quality's default
    accuracy: float = 0.01              # max phase-velocity error in the band
    audio_fs: int = 48000
    c: float = C_AIR
    rho: float = RHO_AIR
    pml_cells: int = 20
    viz_frames: int = 180
    viz_max_px: int = 320

    def resolved_dx(self) -> float:
        dx = self.dx if self.dx else QUALITIES.get(self.quality, QUALITIES["Standard"])["dx"]
        if not (0.002 <= dx <= 0.2):
            raise SimulationError(f"Grid spacing {dx} m outside 0.002-0.2 m.")
        return float(dx)

    def resolved_ir_length(self) -> float:
        L = self.ir_length if self.ir_length else QUALITIES.get(
            self.quality, QUALITIES["Standard"])["ir_length"]
        if not (0.02 <= L <= 6.0):
            raise SimulationError("Response length must be 0.02-6 s.")
        return float(L)

    def to_dict(self) -> dict:
        return {"quality": self.quality, "dx": self.dx, "ir_length": self.ir_length,
                "accuracy": self.accuracy, "audio_fs": self.audio_fs, "c": self.c,
                "rho": self.rho, "pml_cells": self.pml_cells}

    @staticmethod
    def from_dict(d: dict) -> "SimSettings":
        s = SimSettings()
        if not isinstance(d, dict):
            raise SimulationError("settings must be an object")
        q = d.get("quality", "Standard")
        s.quality = q if q in QUALITIES else "Standard"
        for k, lo, hi in (("dx", 0.002, 0.2), ("ir_length", 0.02, 6.0)):
            v = d.get(k)
            if v is None:
                setattr(s, k, None)
            elif isinstance(v, (int, float)) and not isinstance(v, bool) and lo <= v <= hi:
                setattr(s, k, float(v))
            else:
                raise SimulationError(f"invalid {k}")
        for k, lo, hi in (("accuracy", 0.001, 0.1), ("c", 200.0, 2000.0), ("rho", 0.1, 2000.0)):
            v = d.get(k, getattr(s, k))
            if not (isinstance(v, (int, float)) and lo <= v <= hi):
                raise SimulationError(f"invalid {k}")
            setattr(s, k, float(v))
        fs = d.get("audio_fs", 48000)
        if not (isinstance(fs, int) and 8000 <= fs <= 384000):
            raise SimulationError("invalid audio_fs")
        s.audio_fs = fs
        pc = d.get("pml_cells", 20)
        if not (isinstance(pc, int) and 6 <= pc <= 80):
            raise SimulationError("invalid pml_cells")
        s.pml_cells = pc
        return s

    def canonical(self) -> dict:
        """Fields that change the acoustic response (cache key)."""
        return {"dx": round(self.resolved_dx(), 7), "ir": round(self.resolved_ir_length(), 6),
                "acc": self.accuracy, "fs": self.audio_fs, "c": self.c, "rho": self.rho,
                "pml": self.pml_cells}


# ------------------------------------------------------------- dispersion


def phase_velocity_error(f: float, dx: float, dt: float, c: float, theta: float) -> float:
    """Relative phase-velocity error of the scheme at frequency f travelling
    at angle theta to the x axis (exact discrete dispersion relation)."""
    w = 2 * math.pi * f
    rhs = (dx / (c * dt)) ** 2 * math.sin(w * dt / 2) ** 2
    ct, st = abs(math.cos(theta)), abs(math.sin(theta))

    def g(k):
        return math.sin(k * ct * dx / 2) ** 2 + math.sin(k * st * dx / 2) ** 2 - rhs

    kmax = math.pi / (dx * max(ct, st))
    if g(kmax) < 0:
        return float("inf")          # beyond the grid's representable band
    lo, hi = 1e-12, kmax
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        if g(mid) > 0:
            hi = mid
        else:
            lo = mid
    k = 0.5 * (lo + hi)
    return (w / k) / c - 1.0


def bandwidth(dx: float, dt: float, c: float, accuracy: float) -> float:
    """Highest frequency at which the phase-velocity error stays within
    +-accuracy in every propagation direction."""
    thetas = np.linspace(0, math.pi / 4, 7)

    def worst(f):
        return max(abs(phase_velocity_error(f, dx, dt, c, t)) for t in thetas)

    lo, hi = 1.0, 0.5 / dt
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if worst(mid) <= accuracy:
            lo = mid
        else:
            hi = mid
    return lo


# ----------------------------------------------------------------- plan


@dataclass
class SimPlan:
    dx: float
    dt: float
    fs_sim: float
    courant: float
    up: int
    down: int
    f_valid: float
    f_excite: float
    nx: int
    ny: int
    pml: int
    n_steps: int
    n_ir: int
    src_delay: int
    ir_length: float
    cells: int
    est_seconds: float
    mem_mb: float
    points_per_wavelength: float

    width: float = 0.0          # drawn room size (m)
    height: float = 0.0

    def describe(self) -> str:
        W, H = self.nx * self.dx, self.ny * self.dx
        size = ""
        if self.width and (abs(W - self.width) > 0.0005 or abs(H - self.height) > 0.0005):
            # every dimension is quantised to whole cells; mode frequencies follow the GRID size
            size = f" = {W:.3f} x {H:.3f} m simulated"
        return (f"grid {self.nx} x {self.ny} cells ({self.dx * 100:.2f} cm){size}"
                f"{' + PML ' + str(self.pml) if self.pml else ''}, "
                f"fs_sim {self.fs_sim:.0f} Hz, Courant {self.courant:.3f}, "
                f"reliable band <= {self.f_valid:.0f} Hz, {self.n_steps} steps, "
                f"~{self.est_seconds:.0f} s, ~{self.mem_mb:.0f} MB")


def make_plan(geom: Geometry, s: SimSettings) -> SimPlan:
    dx = s.resolved_dx()
    L = s.resolved_ir_length()
    c = s.c
    fs_min = c / (dx * LAMBDA_MAX)
    target = c / (dx * 0.97 * LAMBDA_MAX)
    ratio = Fraction(target / s.audio_fs).limit_denominator(12)
    if s.audio_fs * float(ratio) < fs_min * (1 + 1e-9):
        ratio = Fraction(math.ceil(target / s.audio_fs * 12), 12)
    fs_sim = s.audio_fs * float(ratio)
    down, up = ratio.numerator, ratio.denominator     # audio = sim * up / down
    dt = 1.0 / fs_sim
    lam = c * dt / dx
    if lam > LAMBDA_MAX + 1e-12:
        raise SimulationError("Courant condition violated (internal error).")
    f_valid = min(bandwidth(dx, dt, c, s.accuracy), 0.45 * s.audio_fs)
    f_excite = min(1.6 * f_valid, 0.40 * fs_sim)
    nx = max(4, int(round(geom.width / dx)))
    ny = max(4, int(round(geom.height / dx)))
    pml = s.pml_cells if geom.boundary.mode == "absorbing" else 0
    ntaps = _src_taps(fs_sim, f_excite)
    src_delay = (ntaps - 1) // 2
    n_ir = int(math.ceil(L * fs_sim))
    n_steps = n_ir + src_delay + 2
    cells = (nx + 2 * pml) * (ny + 2 * pml)
    est = cells * n_steps * (2.0 if pml else 1.0) / _throughput["cells_per_s"]
    mem = cells * 4 * 8 / 1e6 + _viz_mem(nx, ny, s) / 1e6
    return SimPlan(dx, dt, fs_sim, lam, up, down, f_valid, f_excite, nx, ny, pml,
                   n_steps, n_ir, src_delay, L, cells, est, mem, c / (f_valid * dx),
                   geom.width, geom.height)


def _src_taps(fs_sim, f_excite) -> int:
    trans = 0.35 * f_excite
    n = int(math.ceil(5.0 * fs_sim / trans)) | 1
    return max(n, 31)


def _viz_mem(nx, ny, s: SimSettings) -> float:
    q = max(1, math.ceil(max(nx, ny) / s.viz_max_px))
    return s.viz_frames * (nx // q + 1) * (ny // q + 1) * 2


def excitation(plan: SimPlan) -> np.ndarray:
    """Band-limited impulse (unit DC gain, linear phase, delay src_delay)."""
    n = 2 * plan.src_delay + 1
    return signal.firwin(n, plan.f_excite, window=("kaiser", 8.0), fs=plan.fs_sim)


# ---------------------------------------------------------------- result


@dataclass
class SimResult:
    plan: SimPlan
    mic_ids: List[str]
    mic_signals: Dict[str, np.ndarray]     # raw pressure at fs_sim, delay removed
    energy_t: np.ndarray
    energy: np.ndarray
    frames: Optional[np.ndarray]           # (n, fx, fy) float16
    frame_times: Optional[np.ndarray]
    frame_mask: Optional[np.ndarray]       # solid mask, decimated
    frame_step: int
    warnings: List[str]
    elapsed: float
    connected: Dict[str, bool]


# ---------------------------------------------------------------- solver


def impedance_from_alpha(alpha: float, rho: float, c: float) -> float:
    if alpha <= 0:
        return math.inf
    R = math.sqrt(max(0.0, 1.0 - alpha))
    return rho * c * (1 + R) / (1 - R)


def simulate(geom: Geometry, s: SimSettings,
             progress: Optional[Callable[[float, str], None]] = None,
             cancel: Optional[Callable[[], bool]] = None,
             store_frames: bool = True) -> SimResult:
    """Run the FDTD simulation for EVERY microphone of geom (receivers are
    nearly free; enabling a microphone later then never needs a recompute)."""
    t_start = time.perf_counter()
    plan = make_plan(geom, s)
    raster = rasterize(geom, plan.dx)
    rep = check(geom, raster)
    if rep.errors:
        raise GeometryError("\n".join(rep.errors))
    warnings = list(rep.warnings)
    if plan.mem_mb > 3000:
        raise SimulationError(f"This simulation needs about {plan.mem_mb:.0f} MB. "
                              "Choose a coarser quality or a smaller room.")
    if plan.cells > 6_000_000:
        raise SimulationError(f"{plan.cells} grid cells is too many for this solver. "
                              "Choose a coarser quality or a smaller room.")

    c, rho, dx, dt = s.c, s.rho, plan.dx, plan.dt
    P = plan.pml
    NX, NY = plan.nx + 2 * P, plan.ny + 2 * P
    solid = np.zeros((NX, NY), bool)
    alpha = np.zeros((NX, NY))
    solid[P:P + plan.nx, P:P + plan.ny] = raster.solid
    alpha[P:P + plan.nx, P:P + plan.ny] = raster.alpha
    air = ~solid
    f32 = np.float32
    Kp = f32(rho * c * c * dt / dx)
    Kv = f32(dt / (rho * dx))

    # ---- face classification ------------------------------------------
    # x faces: index i in 0..NX, between cells i-1 and i
    openX = np.zeros((NX + 1, NY), f32)
    openX[1:-1] = (air[:-1] & air[1:]).astype(f32)
    openY = np.zeros((NX, NY + 1), f32)
    openY[:, 1:-1] = (air[:, :-1] & air[:, 1:]).astype(f32)
    imp_groups = _impedance_faces(air, alpha, rho, c, geom, P)

    # ---- PML coefficients ------------------------------------------------
    use_pml = P > 0
    if use_pml:
        Lp = P * dx
        sig_max = -(3 + 1) * c * math.log(1e-5) / (2 * Lp)

        def sig(pos):  # pos in cells measured from domain edge into the layer
            d = np.clip(pos, 0, P) / P
            return sig_max * d ** 3

        # cell centres
        ic = np.arange(NX) + 0.5
        jc = np.arange(NY) + 0.5
        sxc = sig(np.maximum(P - ic, ic - (NX - P)))
        syc = sig(np.maximum(P - jc, jc - (NY - P)))
        # faces
        fi = np.arange(1, NX).astype(float)
        fj = np.arange(1, NY).astype(float)
        sxf = sig(np.maximum(P - fi, fi - (NX - P)))
        syf = sig(np.maximum(P - fj, fj - (NY - P)))

        def ab(sg, K):
            a = (1 - sg * dt / 2) / (1 + sg * dt / 2)
            b = K / (1 + sg * dt / 2)
            return a.astype(f32), b.astype(f32)

        ax_f, bx_f = ab(sxf, float(Kv)); ax_f, bx_f = ax_f[:, None], bx_f[:, None]
        ay_f, by_f = ab(syf, float(Kv)); ay_f, by_f = ay_f[None, :], by_f[None, :]
        apx, bpx = ab(sxc, float(Kp)); apx, bpx = apx[:, None], bpx[:, None]
        apy, bpy = ab(syc, float(Kp)); apy, bpy = apy[None, :], bpy[None, :]
        px = np.zeros((NX, NY), f32)
        py = np.zeros((NX, NY), f32)

    p = np.zeros((NX, NY), f32)
    vx = np.zeros((NX + 1, NY), f32)
    vy = np.zeros((NX, NY + 1), f32)
    gx = np.empty((NX - 1, NY), f32)
    gy = np.empty((NX, NY - 1), f32)
    dv = np.empty((NX, NY), f32)
    dv2 = np.empty((NX, NY), f32)
    has_solid = bool(solid.any())
    # bind impedance faces to the live velocity arrays (updated in place)
    imp = [({"vx": vx, "vy": vy}[nm], fi_, fj_, ci_, cj_, g_)
           for (nm, fi_, fj_, ci_, cj_, g_) in imp_groups]

    # ---- source / receivers -------------------------------------------
    exc = excitation(plan).astype(f32)
    # source distributed bilinearly over the neighbouring air cells, so its
    # position is not quantised to a cell centre
    src_taps = _receiver_weights(geom.source[0], geom.source[1], dx, air, P)
    si = np.array([t[0] for t in src_taps]); sj = np.array([t[1] for t in src_taps])
    sw = np.array([t[2] for t in src_taps], f32)
    mics = list(geom.mics)
    rec = {m.id: _receiver_weights(m.x, m.y, dx, air, P) for m in mics}
    # gather all receiver taps into one fancy-index for speed
    rx_i, rx_j, rx_w, rx_slot = [], [], [], []
    for k, m in enumerate(mics):
        for (ii, jj, ww) in rec[m.id]:
            rx_i.append(ii); rx_j.append(jj); rx_w.append(ww); rx_slot.append(k)
    rx_i = np.array(rx_i); rx_j = np.array(rx_j)
    rx_w = np.array(rx_w); rx_slot = np.array(rx_slot)
    rec_mat = np.zeros((len(mics), plan.n_steps))

    # ---- visualisation frames -----------------------------------------
    diag = math.hypot(geom.width, geom.height)
    t_viz = min(plan.ir_length, max(0.03, 2.5 * diag / c))
    n_viz = min(plan.n_steps, int(t_viz / dt) + plan.src_delay)
    fstep = max(1, n_viz // max(1, s.viz_frames))
    q = max(1, math.ceil(max(plan.nx, plan.ny) / s.viz_max_px))
    frames = [] if store_frames else None
    ftimes = []
    in_dom = (slice(P, P + plan.nx), slice(P, P + plan.ny))
    air_dom = air[in_dom]

    # ---- energy monitor -------------------------------------------------
    e_every = 16
    e_t, e_v = [], []
    e_ref = 0.0
    src_end = len(exc) + 4
    closed_lossless = (geom.boundary.mode == "rigid" and not np.any(raster.alpha[raster.solid] > 0))
    t_loop = time.perf_counter()
    report_every = max(1, plan.n_steps // 200)

    dvx = (slice(P, P + plan.nx + 1), slice(P, P + plan.ny))
    dvy = (slice(P, P + plan.nx), slice(P, P + plan.ny + 1))
    # overflow is detected explicitly (energy / finiteness checks below)
    with np.errstate(over="ignore", invalid="ignore"):
        for n in range(plan.n_steps):
            e_step = (n % e_every == 0)
            if e_step:
                # exact discrete invariant of the leapfrog scheme:
                # sum p^n^2 / (2 rho c^2) + rho/2 sum v^(n-1/2) . v^(n+1/2)
                pd = p[in_dom][air_dom].astype(np.float64)
                e_p = (pd @ pd) / (2 * rho * c * c)
                vx_old = vx[dvx].astype(np.float64)
                vy_old = vy[dvy].astype(np.float64)
            # velocities (time n+1/2) - in place, no temporaries
            np.subtract(p[1:], p[:-1], out=gx)
            np.subtract(p[:, 1:], p[:, :-1], out=gy)
            if use_pml:
                gx *= bx_f; vx[1:-1] *= ax_f; vx[1:-1] -= gx
                gy *= by_f; vy[:, 1:-1] *= ay_f; vy[:, 1:-1] -= gy
            else:
                gx *= Kv; vx[1:-1] -= gx
                gy *= Kv; vy[:, 1:-1] -= gy
            if has_solid:
                vx *= openX
                vy *= openY
            for (vv, fi_, fj_, ci_, cj_, g_) in imp:
                vv[fi_, fj_] = g_ * p[ci_, cj_]
            if e_step:
                E = (e_p + 0.5 * rho * (float(np.vdot(vx_old, vx[dvx])) + float(np.vdot(vy_old, vy[dvy])))) * dx * dx
            # pressure (time n+1)
            if use_pml:
                np.subtract(vx[1:], vx[:-1], out=dv); dv *= bpx; px *= apx; px -= dv
                np.subtract(vy[:, 1:], vy[:, :-1], out=dv); dv *= bpy; py *= apy; py -= dv
                if n < len(exc):
                    px[si, sj] += (0.5 * exc[n]) * sw
                    py[si, sj] += (0.5 * exc[n]) * sw
                np.add(px, py, out=p)
            else:
                np.subtract(vx[1:], vx[:-1], out=dv)
                np.subtract(vy[:, 1:], vy[:, :-1], out=dv2)
                dv += dv2; dv *= Kp; p -= dv
                if n < len(exc):
                    p[si, sj] += exc[n] * sw
            # receivers
            if len(rx_i):
                np.add.at(rec_mat[:, n], rx_slot, rx_w * p[rx_i, rx_j])
            # frames
            if frames is not None and n < n_viz and n % fstep == 0:
                fr = np.where(air_dom, p[in_dom], 0.0)
                frames.append(fr[::q, ::q].astype(np.float16))
                ftimes.append((n - plan.src_delay) * dt)
            # energy + stability
            if e_step:
                e_t.append(n * dt); e_v.append(E)
                if not math.isfinite(E):
                    raise SimulationError(f"Numerical instability at step {n} (non-finite field). "
                                          "The response was discarded.")
                if n <= src_end + 4 * e_every:
                    e_ref = max(e_ref, E)
                elif e_ref > 0 and E > 50.0 * e_ref:
                    raise SimulationError(f"Numerical instability at step {n}: acoustic energy grew "
                                          f"{E / e_ref:.0f}x after the source stopped. The response was discarded.")
            if n % 50 == 0 and cancel is not None and cancel():
                raise Cancelled()
            if progress is not None and n % report_every == 0:
                progress(n / plan.n_steps, f"step {n}/{plan.n_steps}")

    elapsed_loop = time.perf_counter() - t_loop
    if elapsed_loop > 0.5:
        # normalised to the unsplit (no-PML) update, which costs about half
        _throughput["cells_per_s"] = plan.cells * plan.n_steps * (2.0 if use_pml else 1.0) / elapsed_loop

    d = plan.src_delay
    mic_signals = {m.id: rec_mat[k, d:d + plan.n_ir].copy() for k, m in enumerate(mics)}
    for mid, sig_ in mic_signals.items():
        if not np.all(np.isfinite(sig_)):
            raise SimulationError("Non-finite receiver signal - response discarded.")
    if closed_lossless and len(e_v) > 4:
        tail = np.array(e_v[len(e_v) // 2:])
        drift = (tail.max() - tail.min()) / max(tail.mean(), 1e-30)
        if drift > 0.05:
            warnings.append(f"Energy drift {drift * 100:.1f}% in a lossless room (expected ~0).")
    fm = air_dom[::q, ::q] if frames is not None else None
    return SimResult(
        plan=plan, mic_ids=[m.id for m in mics], mic_signals=mic_signals,
        energy_t=np.array(e_t), energy=np.array(e_v),
        frames=np.array(frames) if frames else None,
        frame_times=np.array(ftimes) if frames else None,
        frame_mask=(~fm) if fm is not None else None, frame_step=fstep,
        warnings=warnings, elapsed=time.perf_counter() - t_start,
        connected=rep.mic_connected)


def _receiver_weights(x, y, dx, air, P):
    """Bilinear weights over neighbouring air cells (renormalised)."""
    gx, gy = x / dx - 0.5, y / dx - 0.5
    i0, j0 = int(math.floor(gx)), int(math.floor(gy))
    fx, fy = gx - i0, gy - j0
    taps = []
    for di, wx in ((0, 1 - fx), (1, fx)):
        for dj, wy in ((0, 1 - fy), (1, fy)):
            ii, jj = i0 + di + P, j0 + dj + P
            if 0 <= ii < air.shape[0] and 0 <= jj < air.shape[1] and air[ii, jj] and wx * wy > 0:
                taps.append([ii, jj, wx * wy])
    if not taps:
        ii, jj = int(x / dx) + P, int(y / dx) + P
        return [(ii, jj, 1.0)]
    tot = sum(t[2] for t in taps)
    return [(t[0], t[1], t[2] / tot) for t in taps]


def _impedance_faces(air, alpha, rho, c, geom: Geometry, P):
    """Faces between air and an absorbing solid (or an absorbing room edge).

    Returns groups (velocity_array_name, face_i, face_j, cell_i, cell_j, gain)
    with v_face = gain * p_cell; gain carries the sign of the outward normal.
    """
    NX, NY = air.shape
    xs = {"fi": [], "fj": [], "ci": [], "cj": [], "g": []}
    ys = {"fi": [], "fj": [], "ci": [], "cj": [], "g": []}

    def add(d, fi, fj, ci, cj, g):
        d["fi"].append(fi); d["fj"].append(fj); d["ci"].append(ci); d["cj"].append(cj); d["g"].append(g)

    Zc = {}

    def Zinv(a):
        if a not in Zc:
            Z = impedance_from_alpha(a, rho, c)
            Zc[a] = 0.0 if math.isinf(Z) else 1.0 / Z
        return Zc[a]

    solid = ~air
    # internal x faces
    L, R = solid[:-1], solid[1:]
    ii, jj = np.nonzero(L & ~R & (alpha[:-1] > 0))     # wall left, air right
    for i, j in zip(ii, jj):
        add(xs, i + 1, j, i + 1, j, -Zinv(alpha[i, j]))
    ii, jj = np.nonzero(~L & R & (alpha[1:] > 0))      # air left, wall right
    for i, j in zip(ii, jj):
        add(xs, i + 1, j, i, j, +Zinv(alpha[i + 1, j]))
    B, T = solid[:, :-1], solid[:, 1:]
    ii, jj = np.nonzero(B & ~T & (alpha[:, :-1] > 0))
    for i, j in zip(ii, jj):
        add(ys, i, j + 1, i, j + 1, -Zinv(alpha[i, j]))
    ii, jj = np.nonzero(~B & T & (alpha[:, 1:] > 0))
    for i, j in zip(ii, jj):
        add(ys, i, j + 1, i, j, +Zinv(alpha[i, j + 1]))
    # room edges
    if geom.boundary.mode == "partial" and geom.boundary.alpha > 0 and P == 0:
        zi = Zinv(geom.boundary.alpha)
        for j in range(NY):
            if air[0, j]:
                add(xs, 0, j, 0, j, -zi)
            if air[NX - 1, j]:
                add(xs, NX, j, NX - 1, j, +zi)
        for i in range(NX):
            if air[i, 0]:
                add(ys, i, 0, i, 0, -zi)
            if air[i, NY - 1]:
                add(ys, i, NY, i, NY - 1, +zi)
    groups = []
    for name, d in (("vx", xs), ("vy", ys)):
        if d["fi"]:
            groups.append((name, np.array(d["fi"]), np.array(d["fj"]),
                           np.array(d["ci"]), np.array(d["cj"]),
                           np.array(d["g"], np.float32)))
    return groups



# ============================================================================
# IMPULSE RESPONSES AND ACOUSTIC FINGERPRINT
# ============================================================================
# Impulse-response construction and acoustic-fingerprint measurements.
#
# From raw receiver pressure (simulation rate) to an impulse response at the
# audio rate:
#
#   1. polyphase resampling fs_sim -> fs_audio (rational, exact ratio)
#   2. truncation check, then a short raised-cosine fade at the response end
#   3. 2.5-D correction  C(w) = sqrt(w_n) / sqrt(i w + w_lo)
#      A 2-D (line-source) field grows +3 dB/oct relative to a point source and
#      has a 1/sqrt(t) wake; this half-integrator turns the 2-D Green's function
#      into a compact, flat-spectrum arrival (exact in the far field).
#      Optional (on by default), clearly labelled.
#   4. high-pass 20 Hz, CAUSAL (2nd-order Butterworth) - a closed 2-D room
#      otherwise holds a static pressure offset after the source has injected
#      mass.  (A zero-phase high-pass would smear that DC removal over the whole
#      buffer and put energy BEFORE the direct sound.)
#   5. modelled-band mask: zero-phase raised-cosine low-pass whose -6 dB point
#      is f_valid (0.85..1.15 f_valid transition).  Nothing above the reliable
#      band survives; render.py decides what to do there (preserve / attenuate
#      / creative extension) with the exactly complementary high-pass.
#   6. level: divided by the analytic free-field response of the same source at
#      1 m, so 0 dB = the 2-D free field at 1 m ("physically relative level").
W_NORM = 2 * math.pi * 1000.0      # 2.5-D correction reference
W_LO = 2 * math.pi * 15.0          # regularisation of the half-integrator
F_HP = 20.0
XO_LO, XO_HI = 0.85, 1.15          # crossover transition (x f_valid)


@dataclass
class MicResponse:
    mic_id: str
    ir: np.ndarray                 # modelled-band IR at audio fs, physical level
    truncated_db: float            # energy level of the last 10% re total (dB)
    connected: bool = True


@dataclass
class AcousticResponse:
    key: str
    fs: int
    f_valid: float
    ir_length: float
    mics: Dict[str, MicResponse]
    plan_text: str
    warnings: List[str]
    elapsed: float
    correction_25d: bool
    frames: Optional[np.ndarray] = None
    frame_times: Optional[np.ndarray] = None
    frame_mask: Optional[np.ndarray] = None
    energy_t: Optional[np.ndarray] = None
    energy: Optional[np.ndarray] = None
    dx: float = 0.0


def free_field_constant(plan: SimPlan, c: float) -> float:
    """|P(w)| of the corrected 2-D free field at r = 1 m for a unit source.

    Soft source adding a[n] to one cell == volume source per unit length
    Q(w) = A(w) dx^2 / (rho c^2).  Far field of a line source:
    |p| = (w rho |Q| / 4) sqrt(2 / (pi k r)).  After the correction
    sqrt(w_n / w):  K = dx^2 / (4 c^2) * sqrt(2 c w_n / pi)   (r = 1, |A| = 1).
    """
    return plan.dx ** 2 / (4 * c * c) * math.sqrt(2 * c * W_NORM / math.pi)


def crossover_masks(freqs: np.ndarray, f_valid: float):
    """Zero-phase complementary low/high masks (sum exactly 1)."""
    lo, hi = XO_LO * f_valid, XO_HI * f_valid
    L = np.ones_like(freqs)
    t = np.clip((freqs - lo) / (hi - lo), 0, 1)
    L = 0.5 * (1 + np.cos(np.pi * t))
    L[freqs <= lo] = 1.0
    L[freqs >= hi] = 0.0
    return L, 1.0 - L


def build_response(result: SimResult, key: str, c: float,
                   correction_25d: bool = True, keep_frames: bool = True) -> AcousticResponse:
    plan = result.plan
    fs = int(round(plan.fs_sim * plan.up / plan.down))
    n_a = int(round(plan.ir_length * fs))
    K = free_field_constant(plan, c)
    mics = {}
    warnings = list(result.warnings)
    for mid in result.mic_ids:
        raw = result.mic_signals[mid]
        y = signal.resample_poly(raw, plan.up, plan.down, window=("kaiser", 10.0))
        y = y[:n_a] if len(y) >= n_a else np.pad(y, (0, n_a - len(y)))
        nfft = 1 << int(math.ceil(math.log2(2 * n_a + 1024)))
        Y = np.fft.rfft(y, nfft)
        f = np.fft.rfftfreq(nfft, 1 / fs)
        w = 2 * np.pi * f
        if correction_25d:
            Y *= np.sqrt(W_NORM) / np.sqrt(1j * w + W_LO)
        # (uncorrected: same constant K, so 0 dB = free field at 1 m and 1 kHz,
        #  with the native 2-D +3 dB/oct tilt)
        Lmask, _ = crossover_masks(f, plan.f_valid)
        Y *= Lmask
        h = np.fft.irfft(Y, nfft)[:n_a] / (K * fs)
        h = signal.sosfilt(signal.butter(2, F_HP, "highpass", fs=fs, output="sos"), h)
        # truncation: level of the last 10 % before the fade
        e = h ** 2
        tot = e.sum()
        tail = e[int(0.9 * n_a):].sum()
        tdb = 10 * math.log10(tail / tot) if tot > 0 and tail > 0 else -200.0
        nf = max(8, int(0.03 * n_a))
        h[-nf:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, nf)))
        if not np.all(np.isfinite(h)):
            raise ValueError("non-finite impulse response")
        mics[mid] = MicResponse(mid, h.astype(np.float64), tdb, result.connected.get(mid, True))
        if tdb > -35:
            warnings.append(f"Response of mic {mid} is still decaying at the end of the "
                            f"{plan.ir_length:.2f} s window (last 10% at {tdb:.0f} dB): it was faded "
                            "out. Lengthen the response or add absorption.")
    return AcousticResponse(
        key=key, fs=fs, f_valid=plan.f_valid, ir_length=plan.ir_length, mics=mics,
        plan_text=plan.describe(), warnings=warnings, elapsed=result.elapsed,
        correction_25d=correction_25d,
        frames=result.frames if keep_frames else None,
        frame_times=result.frame_times if keep_frames else None,
        frame_mask=result.frame_mask if keep_frames else None,
        energy_t=result.energy_t, energy=result.energy, dx=plan.dx)


# ------------------------------------------------------------ fingerprint


@dataclass
class Fingerprint:
    freqs: np.ndarray
    mag_db: np.ndarray            # physical level (dB re 2-D free field @ 1 m)
    phase: np.ndarray
    peaks: List[tuple]            # (Hz, dB)
    notches: List[tuple]
    level_db: float               # broadband in-band level re free field 1 m
    direct_ms: float              # first arrival
    edc_t: np.ndarray
    edc_db: np.ndarray
    edt: Optional[float]
    t20: Optional[float]
    t30: Optional[float]
    centroid: float
    energy_windows: List[tuple]   # (t0 ms, t1 ms, % of energy)


def fingerprint(ir: np.ndarray, fs: int, f_valid: float, n_peaks: int = 8) -> Fingerprint:
    n = len(ir)
    nfft = 1 << int(math.ceil(math.log2(max(n, 4096) * 2)))
    H = np.fft.rfft(ir, nfft)
    f = np.fft.rfftfreq(nfft, 1 / fs)
    mag = np.abs(H)
    mag_db = 20 * np.log10(np.maximum(mag, 1e-12))
    band = (f >= 30) & (f <= f_valid * 0.95)
    # 1/12-octave smoothing for peak picking
    sm = _smooth_log(f, mag ** 2, 1 / 12)
    sm_db = 10 * np.log10(np.maximum(sm, 1e-24))
    idx = np.nonzero(band)[0]
    peaks, notches = [], []
    if len(idx) > 5:
        seg = sm_db[idx]
        pk, pp = signal.find_peaks(seg, prominence=3.0)
        order = np.argsort(pp["prominences"])[::-1][:n_peaks]
        peaks = sorted((float(f[idx][pk[o]]), float(seg[pk[o]])) for o in order)
        nk, npp = signal.find_peaks(-seg, prominence=6.0)
        order = np.argsort(npp["prominences"])[::-1][:n_peaks]
        notches = sorted((float(f[idx][nk[o]]), float(seg[nk[o]])) for o in order)
    pw = mag[band] ** 2
    level = 10 * math.log10(max(pw.mean(), 1e-24)) if len(pw) else -240.0
    centroid = float((f[band] * pw).sum() / max(pw.sum(), 1e-30)) if len(pw) else 0.0
    e = ir ** 2
    if e.max() > 0:
        # first arrival = PEAK of the first arrival: onset at -20 dB, then the
        # local maximum within two periods of f_valid (a band-limited pulse has
        # side lobes about 1/f_valid wide before its peak)
        i0 = int(np.argmax(e >= e.max() * 10 ** (-20 / 10)))
        w = max(2, int(2 * fs / max(f_valid, 1.0)))
        direct = float((i0 + int(np.argmax(e[i0:i0 + w]))) / fs * 1000)
    else:
        direct = float("nan")
    edc = np.cumsum(e[::-1])[::-1]
    edc_db = 10 * np.log10(np.maximum(edc / max(edc[0], 1e-30), 1e-20))
    t = np.arange(n) / fs
    edt = _decay_time(t, edc_db, 0, -10)
    t20 = _decay_time(t, edc_db, -5, -25)
    t30 = _decay_time(t, edc_db, -5, -35)
    tot = e.sum()
    wins = []
    for a, b in ((0, 5), (5, 20), (20, 50), (50, 100), (100, 200), (200, 10000)):
        i0, i1 = int(a * fs / 1000), min(n, int(b * fs / 1000))
        if i0 < n:
            wins.append((a, min(b, n * 1000 / fs), 100 * e[i0:i1].sum() / max(tot, 1e-30)))
    return Fingerprint(f, mag_db, np.unwrap(np.angle(H)), peaks, notches, level,
                       direct, t, edc_db, edt, t20, t30, centroid, wins)


def _decay_time(t, edc_db, a, b):
    """Reverberation time extrapolated to -60 dB from the [a, b] dB range."""
    m = (edc_db <= a) & (edc_db >= b)
    if m.sum() < 8 or edc_db.min() > b:
        return None
    A = np.vstack([t[m], np.ones(m.sum())]).T
    slope, _ = np.linalg.lstsq(A, edc_db[m], rcond=None)[0]
    if slope >= 0:
        return None
    return float(-60.0 / slope)


def _smooth_log(f, p, frac):
    out = np.empty_like(p)
    cs = np.concatenate([[0.0], np.cumsum(p)])
    lo = np.searchsorted(f, f * 2 ** (-frac / 2))
    hi = np.searchsorted(f, f * 2 ** (frac / 2), side="right")
    hi = np.maximum(hi, lo + 1)
    out = (cs[hi] - cs[lo]) / (hi - lo)
    return out


def spectral_difference(fa: Fingerprint, fb: Fingerprint, f_valid: float):
    """dB difference B - A on a common grid (1/6-octave smoothed)."""
    band = (fa.freqs >= 30) & (fa.freqs <= f_valid * 0.95)
    pa = _smooth_log(fa.freqs, 10 ** (fa.mag_db / 10), 1 / 6)
    pb = _smooth_log(fb.freqs, 10 ** (fb.mag_db / 10), 1 / 6)
    d = 10 * np.log10(np.maximum(pb, 1e-24)) - 10 * np.log10(np.maximum(pa, 1e-24))
    return fa.freqs[band], d[band]


def spectrogram_db(ir: np.ndarray, fs: int, f_max: float):
    nper = 512 if fs > 30000 else 256
    f, t, S = signal.spectrogram(ir, fs, nperseg=nper, noverlap=nper * 7 // 8, mode="psd")
    keep = f <= f_max
    return f[keep], t, 10 * np.log10(np.maximum(S[keep], 1e-24))



# ============================================================================
# RENDERING
# ============================================================================
# Rendering: geometry-derived IRs applied to a source recording.
#
# y(t) = x(t) * h(t)  (FFT convolution).  The modelled-band IR comes from the
# FDTD simulation; above the reliable band f_valid one of three clearly
# labelled strategies applies:
#
#   attenuate  nothing above f_valid (the wet signal is band-limited)
#   preserve   the unmodelled high band passes through UNSIMULATED: an
#              exactly complementary zero-phase high-pass of the dry signal,
#              delayed to the direct arrival and level-matched to the
#              modelled response at the band edge
#   extend     CREATIVE: seeded noise shaped by the decay envelope of the top
#              modelled octave continues the response above f_valid.  It is
#              not a simulation.
#
# The low/high masks sum to exactly one, so band splitting recombines
# without gain error.
BAND_STRATEGIES = ("attenuate", "preserve", "extend")
STEREO_POLICIES = ("mono", "per_channel", "left", "right")
DURATION_MODES = ("preserve", "tail")


@dataclass
class RenderSettings:
    mix: float = 1.0                  # 0 dry .. 1 wet (dry/wet balance)
    wet_gain_db: float = 0.0
    trim_db: float = 0.0
    peak_protect: bool = True
    ceiling_db: float = -1.0
    duration: str = "preserve"        # preserve source length | tail
    bypass: bool = False
    band_strategy: str = "preserve"
    stereo_policy: str = "mono"       # for stereo sources
    seed: int = 1

    def to_dict(self):
        return asdict(self)

    @staticmethod
    def from_dict(d: dict) -> "RenderSettings":
        r = RenderSettings()
        if not isinstance(d, dict):
            raise ValueError("render settings must be an object")
        for k, lo, hi in (("mix", 0, 1), ("wet_gain_db", -60, 40), ("trim_db", -60, 24),
                          ("ceiling_db", -24, 0)):
            v = d.get(k, getattr(r, k))
            if not (isinstance(v, (int, float)) and not isinstance(v, bool) and lo <= v <= hi):
                raise ValueError(f"invalid {k}")
            setattr(r, k, float(v))
        for k in ("peak_protect", "bypass"):
            setattr(r, k, bool(d.get(k, getattr(r, k))))
        for k, allowed in (("duration", DURATION_MODES), ("band_strategy", BAND_STRATEGIES),
                           ("stereo_policy", STEREO_POLICIES)):
            v = d.get(k, getattr(r, k))
            if v not in allowed:
                raise ValueError(f"invalid {k}")
            setattr(r, k, v)
        sd = d.get("seed", 1)
        r.seed = int(sd) if isinstance(sd, int) and 0 <= sd < 2 ** 31 else 1
        return r


def effective(output: RenderSettings, state: RenderSettings) -> RenderSettings:
    """Project output settings + the state's own wet gain / band strategy / seed."""
    r = RenderSettings(**output.to_dict())
    r.wet_gain_db = state.wet_gain_db
    r.band_strategy = state.band_strategy
    r.seed = state.seed
    return r


# --------------------------------------------------------------- full IR


def full_ir(ir_band: np.ndarray, fs: int, f_valid: float, strategy: str,
            seed: int = 1) -> np.ndarray:
    """Modelled-band IR + the chosen treatment of the unmodelled band."""
    if strategy == "attenuate":
        return ir_band.copy()
    n = len(ir_band)
    nfft = 1 << int(math.ceil(math.log2(2 * n + 2048)))
    f = np.fft.rfftfreq(nfft, 1 / fs)
    Lm, Hm = crossover_masks(f, f_valid)
    Hb = np.fft.rfft(ir_band, nfft)
    edge = (f >= 0.6 * f_valid) & (f <= 0.82 * f_valid)
    g_edge = math.sqrt(np.mean(np.abs(Hb[edge]) ** 2)) if edge.any() else 0.0
    e = ir_band ** 2
    if e.max() <= 0:
        return ir_band.copy()
    # direct arrival: the peak of the first arrival (onset at -10 dB, then
    # the local maximum within two periods of f_valid)
    i0 = int(np.argmax(e >= e.max() * 0.1))
    w = max(2, int(2 * fs / f_valid))
    t_d = i0 + int(np.argmax(np.abs(ir_band[i0:i0 + w])))
    if strategy == "preserve":
        # unsimulated high band: dry, delayed to the direct arrival, level-matched
        D = np.exp(-2j * np.pi * f * t_d / fs) * g_edge
        h = np.fft.irfft(Hb + D * Hm, nfft)[:n]
        return h
    # creative extension
    rng = np.random.default_rng(seed)
    # decay envelope of the top modelled octave
    band_hi = _bandpass_fft(ir_band, fs, 0.5 * f_valid, 0.85 * f_valid)
    env = np.sqrt(_smooth(band_hi ** 2, int(0.004 * fs)))
    env[:t_d] = 0.0
    noise = rng.standard_normal(n) * env
    N = np.fft.rfft(noise, nfft)
    # 1/f^(1/2) continuation of the band-edge level, -3 dB/oct above f_valid
    tilt = np.where(f > 0, np.sqrt(np.maximum(f_valid, 1) / np.maximum(f, 1)), 0.0)
    tilt = np.minimum(tilt, 1.0)
    Nb_edge = np.sqrt(np.mean(np.abs(N[(f >= f_valid) & (f <= 1.5 * f_valid)]) ** 2) + 1e-30)
    N *= Hm * tilt * (g_edge / Nb_edge)
    return np.fft.irfft(Hb + N, nfft)[:n]


def _bandpass_fft(x, fs, lo, hi):
    n = len(x)
    nfft = 1 << int(math.ceil(math.log2(2 * n)))
    f = np.fft.rfftfreq(nfft, 1 / fs)
    X = np.fft.rfft(x, nfft)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, nfft)[:n]


def _smooth(x, w):
    w = max(1, w)
    k = np.ones(w) / w
    return np.convolve(x, k, mode="same")


# ------------------------------------------------------------- channels


def source_channels(x: np.ndarray, policy: str) -> np.ndarray:
    """(n, ch) -> (n, k) according to the stereo policy (k = 1 or 2)."""
    if x.ndim == 1:
        return x[:, None]
    if x.shape[1] == 1:
        return x
    if policy == "mono":
        return x.mean(axis=1, keepdims=True)
    if policy == "left":
        return x[:, :1]
    if policy == "right":
        return x[:, 1:2]
    return x[:, :2]


def convolve_channels(xc: np.ndarray, h: np.ndarray) -> np.ndarray:
    """Full linear convolution of every channel with h."""
    return np.stack([signal.oaconvolve(xc[:, k], h) for k in range(xc.shape[1])], axis=1)


def _peak(y: np.ndarray) -> float:
    """max |y| without allocating |y| (NaN / inf propagate)."""
    return max(float(y.max()), -float(y.min())) if y.size else 0.0


def finish(y: np.ndarray, n_src: int, fs: int, settings: RenderSettings,
           ) -> Tuple[np.ndarray, dict]:
    """Duration policy, trim, peak protection.  Returns (y, info).

    Works IN PLACE on y (callers pass arrays they own): no full-length copy
    of the render is made here, which matters for long sources."""
    info = {}
    if settings.duration == "preserve":
        cut = y.shape[0] > n_src and _peak(y[n_src:]) > 1e-9
        y = y[:n_src]
        if cut:
            nf = min(n_src, int(0.010 * fs))
            if nf > 1:
                y[-nf:] *= (0.5 * (1 + np.cos(np.linspace(0, np.pi, nf))))[:, None]
            info["tail_cut"] = True
    else:
        # drop trailing silence below -100 dBFS (keeps the full decay); scanned
        # backwards block by block
        end, B = None, 1 << 15
        for b1 in range(y.shape[0], 0, -B):
            b0 = max(0, b1 - B)
            blk = y[b0:b1]
            rows = np.flatnonzero(((blk > 1e-5) | (blk < -1e-5)).any(axis=1))
            if len(rows):
                end = b0 + rows[-1] + 1 + int(0.02 * fs)
                break
        end = n_src if end is None else end
        y = y[:max(n_src, min(end, y.shape[0]))]
    if settings.trim_db != 0:
        y *= 10 ** (settings.trim_db / 20)
    peak = _peak(y)
    if not math.isfinite(peak):
        raise ValueError("non-finite samples in the render")
    info["peak_before"] = peak
    if settings.peak_protect and peak > 0:
        ceil = 10 ** (settings.ceiling_db / 20)
        if peak > ceil:
            y *= ceil / peak
            info["protect_gain_db"] = 20 * math.log10(ceil / peak)
    info["peak"] = _peak(y)
    return y, info


# --------------------------------------------------------------- render


@dataclass
class MicSetting:
    id: str
    name: str
    enabled: bool
    gain_db: float
    pan: float


def render_state(x: np.ndarray, fs: int, response: AcousticResponse,
                 mics: List[MicSetting], settings: RenderSettings,
                 want: Tuple[str, ...] = ("mics", "mono", "stereo")) -> Dict[str, Tuple[np.ndarray, dict]]:
    """Render one acoustic state.

    Returns {key: (signal (n, ch), info)} with keys "mic:<id>", "mix_mono",
    "mix_stereo".  Each microphone's wet path is convolved ONCE and reused;
    all outputs are assembled by mix_output() - the same function the
    timeline uses - so the dry signal enters every output exactly once.
    """
    if fs != response.fs:
        raise ValueError(f"source rate {fs} Hz differs from the response rate {response.fs} Hz")
    xc = source_channels(x, settings.stereo_policy)
    n = xc.shape[0]
    g_state = 10 ** (settings.wet_gain_db / 20)
    layers = []                                   # (MicSetting, wet layer incl. mic + state gain)
    for m in mics:
        if not m.enabled or m.id not in response.mics:
            continue
        h = full_ir(response.mics[m.id].ir, fs, response.f_valid, settings.band_strategy, settings.seed)
        layers.append((m, convolve_channels(xc, h) * (g_state * 10 ** (m.gain_db / 20))))
    out = {}
    if not layers:
        return out
    if "mics" in want:
        for m, lay in layers:
            out[f"mic:{m.id}"] = finish(mix_output(xc, [(m, lay)], f"mic:{m.id}", settings), n, fs, settings)
    for key, tgt in (("mono", "mix_mono"), ("stereo", "mix_stereo")):
        if key in want:
            out[tgt] = finish(mix_output(xc, layers, tgt, settings), n, fs, settings)
    return out


# ---------------------------------------------------------------- mixing
#
# ONE place defines how wet layers and the dry signal combine, for single
# states, timelines, previews and bypass alike:
#
#   wet layer of mic m   L_m = 10^(state wet gain/20) * 10^(mic gain/20) * (x * h_m)
#   "mic:<m>"            y = (1 - mix) * x            + mix * L_m
#   "mix_mono"           y = (1 - mix) * mean(x)      + mix * (1/sqrt N) * sum_m mean(L_m)
#   "mix_stereo"         y = (1 - mix) * D(x)         + mix * (1/sqrt N) * sum_m P(L_m, pan_m)
#
# D(x): a stereo source as it is; a mono source equal-power centred (-3 dB per
# channel, total power = the mono power).  P: equal-power pan of a mono layer,
# balance (with the matching +3 dB) of a stereo layer.  N: number of enabled
# microphones mixed - 1/sqrt(N) keeps the mix power about constant when
# microphones are added (their responses are largely uncorrelated), so adding
# a microphone does not simply make the render louder.  The dry signal is
# added ONCE, never once per microphone.  Bypass = the dry term alone (mix 0).


def mix_norm(n_mics: int) -> float:
    return 1.0 / math.sqrt(max(1, n_mics))


def dry_for(xc: np.ndarray, target: str) -> np.ndarray:
    if target == "mix_mono":
        return xc.mean(axis=1, keepdims=True)
    if target == "mix_stereo":
        return xc if xc.shape[1] == 2 else np.repeat(xc * math.sqrt(0.5), 2, axis=1)
    return xc


def add_dry(y: np.ndarray, xc: np.ndarray, target: str, gain: float):
    """y[:n] += gain * dry_for(xc, target), channel by channel (no full-length
    stereo copy of the source)."""
    if gain == 0:
        return
    n = xc.shape[0]
    if target == "mix_mono":
        y[:n, 0] += (gain / xc.shape[1]) * xc.sum(axis=1)
    elif target == "mix_stereo" and xc.shape[1] == 1:
        g = gain * math.sqrt(0.5)
        y[:n, 0] += g * xc[:, 0]
        y[:n, 1] += g * xc[:, 0]
    else:
        for c in range(xc.shape[1]):
            y[:n, c] += gain * xc[:, c]


def place_layer(lay: np.ndarray, target: str, pan: float) -> np.ndarray:
    """A wet layer in the target's channel layout (pan only for the stereo mix)."""
    if target == "mix_mono":
        return lay.mean(axis=1, keepdims=True)
    if target == "mix_stereo":
        th = (pan + 1) * math.pi / 4                      # equal-power pan
        gl, gr = math.cos(th), math.sin(th)
        if lay.shape[1] == 1:
            return np.stack([gl * lay[:, 0], gr * lay[:, 0]], axis=1)
        return np.stack([math.sqrt(2) * gl * lay[:, 0], math.sqrt(2) * gr * lay[:, 1]], axis=1)
    return lay


def mix_output(xc: np.ndarray, layers, target: str, settings: RenderSettings,
               n_mix: Optional[int] = None) -> np.ndarray:
    """Dry once + the (normalised) sum of the wet layers, in the target's layout.
    layers: [(mic, wet array)]; n_mix: microphones the mix is normalised for
    (default: len(layers); single-microphone outputs are never normalised)."""
    if settings.bypass:
        return dry_for(xc, target).copy()
    nch = 1 if target == "mix_mono" else (2 if target == "mix_stereo" else xc.shape[1])
    L = max([lay.shape[0] for _, lay in layers] + [xc.shape[0]])
    y = np.zeros((L, nch))
    add_dry(y, xc, target, 1.0 - settings.mix)
    g = settings.mix * (mix_norm(n_mix if n_mix is not None else len(layers)) if target in ("mix_mono", "mix_stereo")
                        else 1.0)
    for m, lay in layers:
        pl = place_layer(lay, target, m.pan)
        y[:pl.shape[0]] += g * pl
    return y


# ------------------------------------------------------------- utilities


def rms_db(y: np.ndarray) -> float:
    v = float(np.sqrt(np.mean(np.square(y)))) if y.size else 0.0
    return 20 * math.log10(v) if v > 0 else -200.0


def level_report(y: np.ndarray, fs: int, info: dict, src_rms_db: Optional[float] = None) -> str:
    """Plain-language level summary of a render: duration, peak, RMS (re the
    source), and what peak protection did - a large protection gain is
    REPORTED, not silently absorbed."""
    pk = float(np.abs(y).max()) if y.size else 0.0
    pk_db = 20 * math.log10(pk) if pk > 0 else -200.0
    r = rms_db(y)
    s = f"{y.shape[0] / fs:.2f} s, {y.shape[1]} ch, peak {pk_db:.1f} dBFS, RMS {r:.1f} dBFS"
    if src_rms_db is not None and src_rms_db > -190:
        s += f" ({r - src_rms_db:+.1f} dB re source)"
    pb = info.get("peak_before")
    if pb is not None and pb > 0 and info.get("protect_gain_db"):
        g = info["protect_gain_db"]
        s += f"\npeak protection: {20 * math.log10(pb):+.1f} dBFS before, scaled by {g:.1f} dB"
        if g < -6:
            s += (f"\nWARNING: the mix was {-g:.1f} dB too hot for the ceiling - lower the wet gain or the "
                  "output trim rather than relying on protection")
    if info.get("tail_cut"):
        s += "\nreverberation tail faded at the source end (duration preserved)"
    return s


def match_level(y: np.ndarray, ref: np.ndarray) -> np.ndarray:
    """Scale y to the RMS of ref (matched-level A/B)."""
    ry, rr = rms_db(y), rms_db(ref)
    if ry < -190 or rr < -190:
        return y
    return y * 10 ** ((rr - ry) / 20)



# ============================================================================
# ACOUSTIC STATES, CACHE, TIMELINE, GEOMETRY MORPH
# ============================================================================
# Acoustic states, the response cache, the composition timeline and the
# geometry morph.
#
# Two kinds of morphing (kept strictly apart):
#
# Mode 1 - acoustic OUTPUT morphing (implemented):
#   each state's response is applied to the recording and the results are
#   mixed by time-varying weights.  Two variants:
#     * "input"  (tail-preserving, default) - the INPUT is split by the weights
#       and each part is convolved with its state's IR, so sound already sent
#       into state A keeps decaying in A after the transition;
#     * "output" - each state's full wet render is crossfaded; tails are
#       faded with their state.
#   Neither represents moving walls: they mix responses of static geometries.
#
# Mode 2 - geometry morphing (implemented as a generator):
#   intermediate geometries between two states with matching elements are
#   generated, each is SIMULATED, and the resulting static responses are
#   sequenced with Mode 1.  It approximates a changing room by a sequence of
#   static rooms; it is not a time-varying FDTD.
CURVES = ("linear", "equal_power", "smoothstep", "hold")
XFADE_MODES = ("input", "output")


def response_key(geom: Geometry, sim: SimSettings, correction_25d: bool) -> str:
    """Hash of everything that changes the simulated responses."""
    payload = json.dumps({"g": json.loads(geom.canonical_json()), "s": sim.canonical(),
                          "c25": bool(correction_25d), "v": 2}, sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()[:20]


@dataclass
class AcousticState:
    name: str
    geometry: Geometry
    sim: SimSettings = field(default_factory=SimSettings)
    render: RenderSettings = field(default_factory=RenderSettings)
    correction_25d: bool = True
    response_key: Optional[str] = None      # key of the last computed response
    id: str = ""
    notes: str = ""
    preset: str = ""                        # preset key this state came from (Reset Preset)

    def __post_init__(self):
        if not self.id:
            self.id = "s" + uuid.uuid4().hex[:8]

    def current_key(self) -> str:
        return response_key(self.geometry, self.sim, self.correction_25d)

    def status(self, cache: "ResponseCache") -> str:
        """'computed' | 'outdated' | 'none'"""
        if self.response_key is None:
            return "none"
        if self.response_key != self.current_key():
            return "outdated"
        return "computed" if cache.has(self.response_key) else "none"

    def mic_settings(self) -> List[MicSetting]:
        return [MicSetting(m.id, m.name, m.enabled, m.gain_db, m.pan) for m in self.geometry.mics]

    def duplicate(self, name: Optional[str] = None) -> "AcousticState":
        s = copy.deepcopy(self)
        s.id = "s" + uuid.uuid4().hex[:8]
        s.name = name or (self.name + " copy")
        return s

    def to_dict(self) -> dict:
        return {"id": self.id, "name": self.name, "geometry": self.geometry.to_dict(),
                "sim": self.sim.to_dict(), "render": self.render.to_dict(),
                "correction_25d": self.correction_25d, "response_key": self.response_key,
                "notes": self.notes, "preset": self.preset}

    @staticmethod
    def from_dict(d: dict) -> "AcousticState":
        if not isinstance(d, dict):
            raise ValueError("state must be an object")
        st = AcousticState(
            name=str(d.get("name", "State"))[:80],
            geometry=Geometry.from_dict(d.get("geometry")),
            sim=SimSettings.from_dict(d.get("sim", {})),
            render=RenderSettings.from_dict(d.get("render", {})),
            correction_25d=bool(d.get("correction_25d", True)),
            id=_ident(d.get("id", "")),
            notes=str(d.get("notes", ""))[:2000],
            preset=_ident(d.get("preset", "")))
        rk = d.get("response_key")
        st.response_key = rk if isinstance(rk, str) and len(rk) == 20 and rk.isalnum() else None
        return st




class ResponseCache:
    """In-memory cache of AcousticResponses keyed by response_key.  Unaffected
    entries survive geometry edits - only the edited state's key changes."""

    def __init__(self):
        self._d: Dict[str, AcousticResponse] = {}

    def has(self, key: Optional[str]) -> bool:
        return key is not None and key in self._d

    def get(self, key: str) -> AcousticResponse:
        return self._d[key]

    def put(self, resp: AcousticResponse):
        self._d[resp.key] = resp

    def keys(self):
        return list(self._d.keys())

    def prune(self, keep: List[str]):
        for k in list(self._d):
            if k not in keep:
                del self._d[k]


# --------------------------------------------------------------- timeline


@dataclass
class Keyframe:
    state_id: str
    time: float                 # s, where the target mixture is reached
    transition: float = 1.0     # s, length of the transition INTO this keyframe
    curve: str = "equal_power"  # shape of that transition
    amount: float = 1.0         # 0..1: how far the mixture moves toward this state
                                # (1 = fully this state; 0.4 = 40 % this state,
                                # 60 % the previous mixture)


@dataclass
class Timeline:
    keyframes: List[Keyframe] = field(default_factory=list)
    xfade: str = "input"
    loop: bool = False
    loop_length: float = 0.0     # s (0 = last keyframe time)

    def sorted(self) -> List[Keyframe]:
        return sorted(self.keyframes, key=lambda k: k.time)

    def to_dict(self):
        return {"keyframes": [k.__dict__ for k in self.sorted()], "xfade": self.xfade,
                "loop": self.loop, "loop_length": self.loop_length}

    @staticmethod
    def from_dict(d: dict, valid_states: List[str]) -> "Timeline":
        if not isinstance(d, dict):
            raise ValueError("timeline must be an object")
        kfs = []
        for k in d.get("keyframes", [])[:200]:
            if not isinstance(k, dict) or k.get("state_id") not in valid_states:
                raise ValueError("timeline keyframe refers to an unknown state")
            t, tr = k.get("time"), k.get("transition", 1.0)
            if not all(isinstance(v, (int, float)) and 0 <= v <= 36000 for v in (t, tr)):
                raise ValueError("invalid keyframe time")
            cv = k.get("curve", "equal_power")
            if cv not in CURVES:
                raise ValueError("invalid curve")
            am = k.get("amount", 1.0)
            if not (isinstance(am, (int, float)) and not isinstance(am, bool) and 0 <= am <= 1):
                raise ValueError("invalid keyframe amount")
            kfs.append(Keyframe(k["state_id"], float(t), float(tr), cv, float(am)))
        xf = d.get("xfade", "input")
        if xf not in XFADE_MODES:
            raise ValueError("invalid xfade")
        ll = d.get("loop_length", 0.0)
        if not (isinstance(ll, (int, float)) and 0 <= ll <= 36000):
            raise ValueError("invalid loop length")
        return Timeline(kfs, xf, bool(d.get("loop", False)), float(ll))

    # ---------------------------------------------------------------- weights
    def targets(self) -> List[Dict[str, float]]:
        """Target mixture reached at each (sorted) keyframe:
        v_k = amount_k * e(state_k) + (1 - amount_k) * v_(k-1);  v_0 = e(state_0)."""
        out: List[Dict[str, float]] = []
        prev: Dict[str, float] = {}
        for i, k in enumerate(self.sorted()):
            a = 1.0 if i == 0 else min(max(k.amount, 0.0), 1.0)
            v = {sid: (1 - a) * w for sid, w in prev.items()}
            v[k.state_id] = v.get(k.state_id, 0.0) + a
            v = {sid: w for sid, w in v.items() if w > 1e-12}
            out.append(v)
            prev = v
        return out

    def weights(self, n: int, fs: int) -> Dict[str, np.ndarray]:
        """Per-state weight curves over n samples (see weights_at)."""
        return self.weights_at(np.arange(n) / fs, fs)

    def weights_at(self, t: np.ndarray, fs: int) -> Dict[str, np.ndarray]:
        """Per-state weights at the times t (s, any block of the timeline:
        renders evaluate them block by block, so no full-length curve is
        ever stored).

        Between two keyframes the mixture moves from target A to target B.
        Weight both targets share stays constant; only the EXCHANGED part
        follows the transition curve (leaving part x c_out(u), arriving part
        x c_in(u)).  For a full A -> B change this is the plain crossfade; for
        equal power it keeps the exchanged power constant."""
        kfs = self.sorted()
        if not kfs:
            return {}
        V = self.targets()
        t = np.asarray(t, dtype=float)
        n = len(t)
        W: Dict[str, np.ndarray] = {}

        def w_of(sid):
            if sid not in W:
                W[sid] = np.zeros(n)
            return W[sid]

        if self.loop and len(kfs) > 1:
            Lp = self.loop_length if self.loop_length > 0 else kfs[-1].time
            if Lp <= kfs[-1].time - kfs[0].time:
                Lp = kfs[-1].time - kfs[0].time + max(kfs[0].transition, 1e-3)
            # cyclic: the last mixture leads into the first one of the next cycle
            first, last = kfs[0], kfs[-1]
            ext = ([Keyframe(last.state_id, last.time - Lp, last.transition, last.curve)] + kfs
                   + [Keyframe(first.state_id, first.time + Lp, first.transition, first.curve)])
            Vx = [V[-1]] + V + [V[0]]
            t = kfs[0].time + np.mod(t - kfs[0].time, Lp)
        else:
            ext, Vx = kfs, V
            for sid, wv in V[0].items():
                w_of(sid)[t < kfs[0].time] += wv
            for sid, wv in V[-1].items():
                w_of(sid)[t >= kfs[-1].time] += wv
        for (a, va), (b, vb) in zip(zip(ext[:-1], Vx[:-1]), zip(ext[1:], Vx[1:])):
            seg = (t >= a.time) & (t < b.time)
            if not seg.any():
                continue
            tr = min(max(b.transition, 0.0), b.time - a.time)
            t0 = b.time - tr
            if tr > 0:
                u = np.clip((t[seg] - t0) / tr, 0, 1)
            else:
                u = (t[seg] >= b.time).astype(float)
            c_out, c_in = _curve(u, b.curve, tr, fs)
            for sid in set(va) | set(vb):
                wa, wb = va.get(sid, 0.0), vb.get(sid, 0.0)
                shared = min(wa, wb)
                w_of(sid)[seg] += shared + (wa - shared) * c_out + (wb - shared) * c_in
        return W


def _curve(u: np.ndarray, kind: str, tr: float, fs: int):
    if kind == "linear":
        return 1 - u, u
    if kind == "equal_power":
        return np.cos(u * np.pi / 2), np.sin(u * np.pi / 2)
    if kind == "smoothstep":
        s = u * u * (3 - 2 * u)
        return 1 - s, s
    # hold: switch at the END of the window with a 3 ms raised-cosine de-click
    d = 0.003 * fs
    if tr * fs > d:
        edge = 1 - d / (tr * fs)
        v = np.clip((u - edge) / (1 - edge), 0, 1)
    else:
        v = u
    s = 0.5 * (1 - np.cos(np.pi * v))
    return 1 - s, s


TIMELINE_BLOCK = 1 << 15          # samples per block in timeline rendering


def render_timeline(x: np.ndarray, fs: int, timeline: Timeline,
                    states: Dict[str, AcousticState], cache: ResponseCache,
                    output: str, settings: RenderSettings,
                    progress: Optional[Callable[[float, str], None]] = None,
                    cancel: Optional[Callable[[], bool]] = None):
    """Render the evolving transformation.

    output: "mic:<index>" (the k-th microphone of every state, by position in
    its mic list), "mix_mono" or "mix_stereo".  Mixing follows mix_output():
    the dry signal once, each state's wet layers weighted by the timeline.

    Memory: the weights are evaluated block by block (TIMELINE_BLOCK samples)
    and the input crossfade is a block (overlap-add) convolution, so besides
    the output only one block per microphone is held.  The output crossfade
    needs one full-length wet signal at a time (it weights the OUTPUT).
    """
    xc = source_channels(x, settings.stereo_policy)
    n = xc.shape[0]
    if not timeline.keyframes:
        raise ValueError("The timeline is empty.")
    used = []
    for v in timeline.targets():
        for sid in v:
            if sid not in used:
                used.append(sid)
    for sid in used:
        st = states.get(sid)
        if st is None:
            raise ValueError("The timeline refers to a deleted state.")
        if st.status(cache) != "computed":
            raise ValueError(f"State '{st.name}' has no up-to-date response "
                             f"({st.status(cache)}). Compute it first.")
    nch = 1 if output == "mix_mono" else (2 if output == "mix_stereo" else xc.shape[1])
    if settings.bypass:
        return finish(dry_for(xc, output).copy(), n, fs, settings)
    # wet gain and band strategy come from each STATE (st.render); the output
    # stage (mix, trim, protection, duration, stereo policy) from `settings`
    paths = []                 # (sid, mic, h, gain, norm)
    for sid in used:
        st = states[sid]
        resp = cache.get(st.response_key)
        if resp.fs != fs:
            raise ValueError("Response rate differs from the source rate.")
        mics = _timeline_mics(st, resp, output)
        g_state = 10 ** (st.render.wet_gain_db / 20)
        for m in mics:
            h = full_ir(resp.mics[m.id].ir, fs, resp.f_valid, st.render.band_strategy, st.render.seed)
            paths.append((sid, m, h, g_state * 10 ** (m.gain_db / 20),
                          mix_norm(len(mics)) if output in ("mix_mono", "mix_stereo") else 1.0))
    hmax = max(len(p[2]) for p in paths)
    y = np.zeros((n + hmax - 1, nch))
    add_dry(y, xc, output, 1.0 - settings.mix)
    B = TIMELINE_BLOCK
    if timeline.xfade == "input":
        # each block of the input is split by the weights and convolved with
        # every path (overlap-add); sound sent into a state keeps decaying there
        nfft = 1 << int(math.ceil(math.log2(B + hmax - 1)))
        H = [np.fft.rfft(p[2], nfft) for p in paths]
        nblk = (n + B - 1) // B
        for k, b0 in enumerate(range(0, n, B)):
            if cancel is not None and cancel():
                raise Cancelled()
            if progress and k % 4 == 0:
                progress(k / nblk, f"block {k + 1}/{nblk}")
            b1 = min(n, b0 + B)
            W = timeline.weights_at(np.arange(b0, b1) / fs, fs)
            for (sid, m, h, g, nrm), Hp in zip(paths, H):
                w = W.get(sid)
                if w is None or not np.any(w > 0):
                    continue
                xb = xc[b0:b1] * w[:, None]
                X = np.fft.rfft(xb, nfft, axis=0)
                yb = np.fft.irfft(X * Hp[:, None], nfft, axis=0)[:b1 - b0 + len(h) - 1]
                pl = place_layer(yb * g, output, m.pan)
                y[b0:b0 + pl.shape[0]] += settings.mix * nrm * pl
    else:
        # output crossfade: the full wet signal of each path, weighted by the
        # timeline at OUTPUT time (the tail keeps the final weight)
        for k, (sid, m, h, g, nrm) in enumerate(paths):
            if cancel is not None and cancel():
                raise Cancelled()
            if progress:
                progress(k / len(paths), f"{states[sid].name}: {m.name}")
            wet = convolve_channels(xc, h)
            for b0 in range(0, wet.shape[0], B):
                b1 = min(wet.shape[0], b0 + B)
                tt = np.minimum(np.arange(b0, b1), n - 1) / fs
                w = timeline.weights_at(tt, fs).get(sid)
                if w is None or not np.any(w > 0):
                    continue
                pl = place_layer(wet[b0:b1] * (g * w[:, None]), output, m.pan)
                y[b0:b1] += settings.mix * nrm * pl
            del wet
    return finish(y, n, fs, settings)


def _timeline_mics(st, resp, output):
    if output.startswith("mic:"):
        k = int(output.split(":")[1])
        if k >= len(st.geometry.mics):
            raise ValueError(f"State '{st.name}' has no microphone {k + 1}.")
        m = st.geometry.mics[k]
        if not m.enabled or m.id not in resp.mics:
            raise ValueError(f"Microphone {k + 1} of '{st.name}' is disabled or not computed.")
        return [m]
    return [m for m in st.geometry.mics if m.enabled and m.id in resp.mics]


def render_main(x: np.ndarray, fs: int, states: Dict[str, AcousticState], cache: ResponseCache,
                timeline: Timeline, use_timeline: bool, current: Optional[AcousticState],
                settings: RenderSettings, target: str,
                progress: Optional[Callable[[float, str], None]] = None,
                cancel: Optional[Callable[[], bool]] = None):
    """THE main output - used by Render, Preview, Preview composition and the
    Praat automation alike, so a preview of any range is sample-identical to
    the same range of the final render with the same settings.

    use_timeline (and keyframes present): the composition; else the current
    state.  Returns (y (n, ch), info, description, [states used])."""
    if use_timeline and timeline.keyframes:
        y, info = render_timeline(x, fs, timeline, states, cache, target, settings, progress, cancel)
        used = []
        for k in timeline.sorted():
            if states[k.state_id] not in used:
                used.append(states[k.state_id])
        desc = f"timeline: {' -> '.join(st.name for st in used)}; {timeline.xfade} crossfade; {target}"
        return y, info, desc, used
    st = current
    if st is None or st.status(cache) != "computed":
        raise ValueError(f"'{st.name if st else '?'}' has no up-to-date response - press Compute first.")
    key = target
    if target.startswith("mic:"):
        k = int(target[4:])
        if k >= len(st.geometry.mics):
            raise ValueError(f"'{st.name}' has no microphone {k + 1}.")
        key = f"mic:{st.geometry.mics[k].id}"
    want = ("mics",) if key.startswith("mic:") else (("mono",) if key == "mix_mono" else ("stereo",))
    res = render_state(x, fs, cache.get(st.response_key), st.mic_settings(), effective(settings, st.render), want)
    if key not in res:
        raise ValueError(f"'{st.name}': {target} is disabled or has no response.")
    y, info = res[key]
    return y, info, f"state '{st.name}'; {target}", [st]


def render_signature(x, states: Dict[str, AcousticState], timeline: Timeline, use_timeline: bool,
                     current: Optional[AcousticState], settings: RenderSettings, target: str) -> str:
    """Everything render_main's result depends on (cache key for preview/render)."""
    tl = bool(use_timeline and timeline.keyframes)
    involved = list(states.values()) if tl else ([current] if current else [])
    d = {"tl": tl, "timeline": timeline.to_dict() if tl else None, "settings": settings.to_dict(),
         "target": target, "src": [id(x), None if x is None else list(x.shape)],
         "states": [(s.id, s.response_key, s.render.to_dict(),
                     [(m.id, m.enabled, m.gain_db, m.pan) for m in s.geometry.mics]) for s in involved]}
    return hashlib.sha256(json.dumps(d, sort_keys=True, default=str).encode()).hexdigest()


# ----------------------------------------------------------- geometry morph


def geometry_morph(a: Geometry, b: Geometry, steps: int) -> List[Geometry]:
    """Intermediate geometries strictly between a and b (Mode 2).

    Requires the same room size, the same element ids/kinds in both, and the
    same microphone ids.  Coordinates, thicknesses, absorption, source and mic
    positions are interpolated linearly.  Raises GeometryError otherwise.
    """
    if steps < 1 or steps > 32:
        raise GeometryError("1-32 intermediate steps.")
    if abs(a.width - b.width) > 1e-9 or abs(a.height - b.height) > 1e-9:
        raise GeometryError("Geometry morph needs the same room size in both states.")
    ea = {e.id: e for e in a.elements}
    eb = {e.id: e for e in b.elements}
    if set(ea) != set(eb) or any(ea[k].kind != eb[k].kind for k in ea):
        raise GeometryError("Geometry morph needs corresponding elements (same ids and kinds); "
                            "make state B by duplicating state A and editing it.")
    ma = {m.id: m for m in a.mics}
    mb = {m.id: m for m in b.mics}
    if set(ma) != set(mb):
        raise GeometryError("Geometry morph needs the same microphones in both states.")
    if a.boundary.mode != b.boundary.mode:
        raise GeometryError("Geometry morph needs the same boundary type in both states.")
    out = []
    for k in range(1, steps + 1):
        u = k / (steps + 1)
        g = a.copy()
        for e in g.elements:
            f = eb[e.id]
            for attr in ("x0", "y0", "x1", "y1", "thickness", "alpha"):
                setattr(e, attr, (1 - u) * getattr(e, attr) + u * getattr(f, attr))
        g.source = ((1 - u) * a.source[0] + u * b.source[0], (1 - u) * a.source[1] + u * b.source[1])
        for m in g.mics:
            f = mb[m.id]
            m.x = (1 - u) * m.x + u * f.x
            m.y = (1 - u) * m.y + u * f.y
        g.boundary.alpha = (1 - u) * a.boundary.alpha + u * b.boundary.alpha
        out.append(g)
    return out



# ============================================================================
# PROJECT FILES
# ============================================================================
# Project files.
#
# <name>.amcproj            JSON (UTF-8): states, timeline, settings, source
#                           reference, cache metadata
# <name>_cache/<key>.npz    impulse responses (plain float arrays; loaded with
#                           allow_pickle=False)
#
# Everything read back is validated: unknown or malformed fields raise
# ProjectError, arrays must be finite 1-D float arrays of sane length, and a
# cached response is only attached to a state whose CURRENT geometry and
# settings hash to the same key - so a stale response can never be used
# silently.
FORMAT = "AcousticMorphologyComposer"
VERSION = 1
OUTPUT_TARGETS = ("mix_stereo", "mix_mono", "mic:0", "mic:1", "mic:2", "mic:3")


class ProjectError(ValueError):
    pass


@dataclass
class OutputSettings:
    target: str = "mix_stereo"          # what "Render" produces as the main output
    use_timeline: bool = True           # timeline if it has >= 1 keyframe
    export_irs: bool = True
    export_layers: bool = False         # per-mic layers of the current state

    def to_dict(self):
        return dict(self.__dict__)

    @staticmethod
    def from_dict(d):
        o = OutputSettings()
        if not isinstance(d, dict):
            raise ProjectError("output settings must be an object")
        t = d.get("target", o.target)
        if t not in OUTPUT_TARGETS:
            raise ProjectError("invalid output target")
        o.target = t
        for k in ("use_timeline", "export_irs", "export_layers"):
            o.__dict__[k] = bool(d.get(k, o.__dict__[k]))
        return o


@dataclass
class SourceRef:
    path: str = ""
    fs: int = 0
    channels: int = 0
    duration: float = 0.0
    name: str = ""


@dataclass
class Project:
    states: List[AcousticState] = field(default_factory=list)
    current_state: Optional[str] = None
    timeline: Timeline = field(default_factory=Timeline)
    render: RenderSettings = field(default_factory=RenderSettings)
    output: OutputSettings = field(default_factory=OutputSettings)
    source: SourceRef = field(default_factory=SourceRef)
    workflow: str = "A"

    def state(self, sid) -> Optional[AcousticState]:
        for s in self.states:
            if s.id == sid:
                return s
        return None

    def states_by_id(self) -> Dict[str, AcousticState]:
        return {s.id: s for s in self.states}


def save_project_file(project: Project, path: str, cache: ResponseCache):
    path = os.path.abspath(path)
    base = os.path.dirname(path)
    stem = os.path.splitext(os.path.basename(path))[0]
    cdir = os.path.join(base, stem + "_cache")
    os.makedirs(cdir, exist_ok=True)
    meta = []
    keep = set()
    for st in project.states:
        if st.response_key and cache.has(st.response_key) and st.response_key not in keep:
            r = cache.get(st.response_key)
            fn = r.key + ".npz"
            arrays = {f"ir_{mid}": mr.ir.astype(np.float64) for mid, mr in r.mics.items()}
            np.savez_compressed(os.path.join(cdir, fn), **arrays)
            meta.append({"key": r.key, "file": stem + "_cache/" + fn, "fs": r.fs,
                         "f_valid": r.f_valid, "ir_length": r.ir_length,
                         "mics": {mid: {"truncated_db": mr.truncated_db, "connected": mr.connected}
                                  for mid, mr in r.mics.items()},
                         "plan_text": r.plan_text, "warnings": r.warnings,
                         "correction_25d": r.correction_25d, "dx": r.dx,
                         "elapsed": r.elapsed, "saved": time.strftime("%Y-%m-%d %H:%M:%S")})
            keep.add(r.key)
    src_rel = ""
    if project.source.path:
        try:
            src_rel = os.path.relpath(project.source.path, base)
        except ValueError:          # other drive on Windows
            src_rel = ""
    doc = {
        "format": FORMAT, "version": VERSION,
        "source": {"path": project.source.path.replace("\\", "/"), "relative": src_rel.replace("\\", "/"),
                   "fs": project.source.fs, "channels": project.source.channels,
                   "duration": project.source.duration, "name": project.source.name},
        "workflow": project.workflow,
        "current_state": project.current_state,
        "states": [s.to_dict() for s in project.states],
        "timeline": project.timeline.to_dict(),
        "render": project.render.to_dict(),
        "output": project.output.to_dict(),
        "cache": meta,
    }
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def load_project_file(path: str) -> (Project, ResponseCache, List[str]):
    """Returns (project, cache, notes).  notes lists anything dropped."""
    notes = []
    path = os.path.abspath(path)
    base = os.path.dirname(path)
    if os.path.getsize(path) > 50_000_000:
        raise ProjectError("Project file is implausibly large.")
    with open(path, "r", encoding="utf-8") as f:
        try:
            doc = json.load(f)
        except json.JSONDecodeError as e:
            raise ProjectError(f"Not a valid project file: {e}")
    if not isinstance(doc, dict) or doc.get("format") != FORMAT:
        raise ProjectError("Not an Acoustic Morphology Composer project.")
    if doc.get("version") != VERSION:
        raise ProjectError(f"Unsupported project version {doc.get('version')!r}.")
    try:
        states = [AcousticState.from_dict(d) for d in _list(doc.get("states"), 200)]
    except Exception as e:
        raise ProjectError(f"Invalid state: {e}")
    if len({s.id for s in states}) != len(states):
        raise ProjectError("Duplicate state ids.")
    ids = [s.id for s in states]
    try:
        tl = Timeline.from_dict(doc.get("timeline", {}), ids)
        rs = RenderSettings.from_dict(doc.get("render", {}))
        out = OutputSettings.from_dict(doc.get("output", {}))
    except Exception as e:
        raise ProjectError(str(e))
    s = doc.get("source", {})
    if not isinstance(s, dict):
        raise ProjectError("invalid source")
    src = SourceRef(path=str(s.get("path", ""))[:4096], fs=_int(s.get("fs", 0)),
                    channels=_int(s.get("channels", 0)), duration=_float(s.get("duration", 0.0)),
                    name=str(s.get("name", ""))[:200])
    rel = s.get("relative", "")
    if src.path and not os.path.exists(src.path) and isinstance(rel, str) and rel:
        cand = os.path.normpath(os.path.join(base, rel))
        if os.path.exists(cand):
            src.path = cand
            notes.append("Source audio found at its project-relative location.")
    cache = ResponseCache()
    for m in _list(doc.get("cache", []), 400):
        try:
            r = _load_response(base, m)
            cache.put(r)
        except Exception as e:
            notes.append(f"Cached response skipped ({e}); it will be recomputed when needed.")
    for st in states:
        if st.response_key and st.response_key != st.current_key():
            notes.append(f"State '{st.name}': stored response does not match its geometry/settings "
                         "- marked outdated.")
        if st.response_key and not cache.has(st.response_key):
            st.response_key = None if st.response_key == st.current_key() else st.response_key
    cur = doc.get("current_state")
    wf = doc.get("workflow", "A")
    p = Project(states=states, current_state=cur if cur in ids else (ids[0] if ids else None),
                timeline=tl, render=rs, output=out, source=src,
                workflow=wf if wf in ("A", "B", "C", "D", "E") else "A")
    return p, cache, notes


def _load_response(base, m) -> AcousticResponse:
    if not isinstance(m, dict):
        raise ProjectError("bad cache entry")
    key = m.get("key")
    if not (isinstance(key, str) and len(key) == 20 and key.isalnum()):
        raise ProjectError("bad cache key")
    fn = m.get("file", "")
    full = os.path.normpath(os.path.join(base, fn))
    if not full.startswith(os.path.normpath(base) + os.sep):
        raise ProjectError("cache file outside the project folder")
    fs = _int(m.get("fs"))
    if not 8000 <= fs <= 384000:
        raise ProjectError("bad fs")
    with np.load(full, allow_pickle=False) as z:
        mics = {}
        minfo = m.get("mics", {})
        if not isinstance(minfo, dict):
            raise ProjectError("bad mic info")
        for k in z.files:
            if not k.startswith("ir_"):
                continue
            a = z[k]
            if a.ndim != 1 or a.dtype.kind != "f" or not (16 <= len(a) <= fs * 10) or not np.all(np.isfinite(a)):
                raise ProjectError("bad IR array")
            mid = k[3:]
            info = minfo.get(mid, {}) if isinstance(minfo.get(mid, {}), dict) else {}
            mics[mid] = MicResponse(mid, a.astype(np.float64), _float(info.get("truncated_db", -200.0)),
                                    bool(info.get("connected", True)))
    return AcousticResponse(key=key, fs=fs, f_valid=_float(m.get("f_valid")),
                            ir_length=_float(m.get("ir_length")), mics=mics,
                            plan_text=str(m.get("plan_text", ""))[:500],
                            warnings=[str(w)[:500] for w in _list(m.get("warnings", []), 50)],
                            elapsed=_float(m.get("elapsed", 0.0)),
                            correction_25d=bool(m.get("correction_25d", True)),
                            dx=_float(m.get("dx", 0.0)))


def _list(v, cap):
    if v is None:
        return []
    if not isinstance(v, list) or len(v) > cap:
        raise ProjectError("expected a list")
    return v


def _int(v):
    if isinstance(v, bool) or not isinstance(v, int):
        raise ProjectError("expected an integer")
    return v


def _float(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise ProjectError("expected a number")
    return float(v)


def save_geometry_file(geom, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"format": FORMAT + "-geometry", "version": 1, "geometry": geom.to_dict()}, f, indent=1)


def load_geometry_file(path):
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    if not isinstance(doc, dict) or doc.get("format") != FORMAT + "-geometry":
        raise ProjectError("Not a geometry file.")
    return Geometry.from_dict(doc.get("geometry"))



# ============================================================================
# PRESETS
# ============================================================================
# The eight compositional presets.
#
# Every preset is a real geometry (walls, obstacles, openings, boundary,
# source, microphones) - never an EQ curve.  The descriptions state acoustic
# TENDENCIES; the actual response depends on the numerical settings and on any
# edits, and is whatever the simulation computes.
T = 0.06   # default wall thickness (m)


def W(x0, y0, x1, y1, alpha=0.0, t=T, id=""):
    return Element("wall", x0, y0, x1, y1, thickness=t, alpha=alpha, id=id)


def O(x0, y0, x1, y1, id=""):
    return Element("opening", x0, y0, x1, y1, id=id)


def R(x0, y0, x1, y1, alpha=0.0, id=""):
    return Element("rect", x0, y0, x1, y1, alpha=alpha, id=id)


def M(x, y, name, pan=0.0, id=""):
    return Mic(x, y, name, True, 0.0, pan, id=id)


PRESETS: Dict[str, dict] = {}


def _reg(key, name, description, tendencies):
    def deco(fn):
        PRESETS[key] = {"name": name, "description": description,
                        "tendencies": tendencies, "build": fn}
        return fn
    return deco


@_reg("open_field", "1 Open Field",
      "No walls; the room edges are a perfectly matched layer, so sound leaves the domain.",
      "Reference: the direct sound only.  Level falls about 3 dB per doubling of distance "
      "(2-D spreading); the spectrum stays close to flat inside the reliable band.")
def _open_field():
    g = Geometry(4.0, 3.0, [], (1.0, 1.5),
                 [M(2.5, 1.5, "M1", -0.5, "m1"), M(3.2, 2.4, "M2", 0.5, "m2")],
                 Boundary("absorbing", 0.0))
    return [AcousticState("Open Field", g)], None


@_reg("resonant_chamber", "2 Resonant Chamber",
      "A 1.4 x 1.0 m enclosure with nearly rigid walls (alpha 0.06).",
      "Strong, sparse low resonances at the 2-D room modes c/2 * sqrt((m/1.4)^2 + (n/1.0)^2) "
      "(123, 172, 211 Hz ...), ringing after the note stops, and 15-18 dB louder than the free "
      "field.  Off-centre positions excite odd and even modes alike.")
def _resonant_chamber():
    g = Geometry(1.4, 1.0, [], (0.31, 0.27),
                 [M(1.07, 0.71, "M1", -0.5, "m1"), M(0.58, 0.83, "M2", 0.5, "m2")],
                 Boundary("partial", 0.06))
    return [AcousticState("Resonant Chamber", g)], None


@_reg("narrow_passage", "3 Narrow Passage",
      "Two spaces separated by a rigid wall with a 10 cm slot.",
      "Behind the slot the sound is much quieter (the slot passes little energy) and its colour "
      "is set mainly by the modes of the receiving room, heard through the slot - not by a "
      "simple low-pass: in this enclosed, absorbing room the balance can even be brighter than "
      "in the open field.  (In an open field a narrower aperture does darken the sound; see "
      "test 3.)  The near-side microphone hears the source plus the wall reflection.")
def _narrow_passage():
    g = Geometry(4.0, 2.4, [W(2.0, 0.0, 2.0, 2.4, id="div"), O(1.9, 1.15, 2.1, 1.25, id="slot")],
                 (0.9, 1.2),
                 [M(3.0, 1.2, "Behind", -0.4, "m1"), M(3.0, 2.0, "Off-axis", 0.4, "m2"),
                  M(1.4, 1.7, "Near side", 0.0, "m3")],
                 Boundary("partial", 0.5))
    return [AcousticState("Narrow Passage", g)], None


@_reg("parallel_walls", "4 Parallel Walls",
      "Two long, mostly reflecting walls (alpha 0.1), centre lines 1.2 m apart, in an otherwise open field.",
      "Repeated reflections between the walls (flutter): a comb-like spectrum.  The wall faces "
      "are 1.14 m apart, so the comb spacing is c / (2 * 1.14 m) ~ 150 Hz; a source on the centre "
      "line (as here) excites only every second tooth, ~300 Hz apart (312, 620, 926 Hz ...).  Move "
      "the source off-centre to hear the full comb.")
def _parallel_walls():
    g = Geometry(4.0, 3.0, [W(0.4, 0.9, 3.6, 0.9, 0.1, id="w1"), W(0.4, 2.1, 3.6, 2.1, 0.1, id="w2")],
                 (1.2, 1.5),
                 [M(2.8, 1.5, "Centre", -0.4, "m1"), M(2.0, 1.25, "Low", 0.4, "m2")],
                 Boundary("absorbing", 0.0))
    return [AcousticState("Parallel Walls", g)], None


@_reg("side_cavity", "5 Side Cavity",
      "A corridor with a closed side chamber attached through a short neck.",
      "The cavity and its neck form a Helmholtz-type side resonator (about 50 Hz here, heard in "
      "both microphones); inside the cavity its own modes dominate and it decays more slowly "
      "than the corridor.")
def _side_cavity():
    els = [W(0.2, 0.6, 3.8, 0.6, 0.1, id="cb"), W(0.2, 1.4, 3.8, 1.4, 0.1, id="ct"),
           W(1.6, 1.4, 1.6, 2.3, id="kl"), W(2.6, 1.4, 2.6, 2.3, id="kr"),
           W(1.6, 2.3, 2.6, 2.3, id="kt"), O(2.04, 1.33, 2.16, 1.47, id="neck")]
    g = Geometry(4.0, 2.6, els, (0.5, 1.0),
                 [M(3.5, 1.0, "Corridor", -0.4, "m1"), M(2.1, 1.9, "Cavity", 0.4, "m2")],
                 Boundary("partial", 0.3))
    return [AcousticState("Side Cavity", g)], None


@_reg("labyrinth", "6 Acoustic Labyrinth",
      "Staggered internal walls forming a folded corridor in a moderately absorbing room.",
      "Many paths of different lengths: a dense, irregular, long response.  At the far end the "
      "first sound arrives much later than a straight line would take (about 24 ms instead of "
      "10 ms) and the onset is smeared.")
def _labyrinth():
    els = [W(0.9, 0.0, 0.9, 2.2, id="l1"), W(1.8, 0.8, 1.8, 3.0, id="l2"),
           W(2.7, 0.0, 2.7, 2.2, id="l3"), W(3.2, 1.5, 4.0, 1.5, id="l4"),
           R(1.25, 2.45, 1.45, 2.65, id="p1")]
    g = Geometry(4.0, 3.0, els, (0.45, 0.5),
                 [M(3.4, 2.5, "Far end", 0.5, "m1"), M(2.25, 0.4, "Middle", -0.5, "m2")],
                 Boundary("partial", 0.15))
    return [AcousticState("Labyrinth", g)], None


@_reg("moving_aperture", "7 Moving Aperture",
      "Two states of one room: the dividing wall's opening is 60 cm (A) or 8 cm (B), with "
      "a timeline A -> B -> A.",
      "Narrowing the opening mainly attenuates the transmitted sound (about 4-8 dB here) and "
      "changes which modes of the two rooms couple; the timeline turns that into an evolving "
      "filter.  The elements correspond, so 'Geometry morph' (Mode 2) can generate and "
      "simulate intermediate openings.")
def _moving_aperture():
    def g(o0, o1):
        return Geometry(3.6, 2.4, [W(1.8, 0.0, 1.8, 2.4, id="div"), O(1.7, o0, 1.9, o1, id="ap")],
                        (0.8, 1.2),
                        [M(2.8, 1.2, "Behind", -0.4, "m1"), M(2.8, 0.5, "Corner", 0.4, "m2")],
                        Boundary("partial", 0.25))
    a = AcousticState("Aperture wide", g(0.9, 1.5))
    b = AcousticState("Aperture narrow", g(1.16, 1.24))
    tl = Timeline([Keyframe(a.id, 0.0, 0.0, "equal_power"),
                   Keyframe(b.id, 3.0, 2.5, "equal_power"),
                   Keyframe(a.id, 6.0, 2.5, "equal_power")], "input")
    return [a, b], tl


@_reg("dual_chamber", "8 Dual Chamber",
      "A small chamber (1.5 x 1.6 m) and a larger L-shaped one, joined by a doorway.",
      "The two microphones show different sets of resonances (their chambers' modes, coupled "
      "through the doorway) while sharing one slow coupled decay.")
def _dual_chamber():
    els = [W(1.5, 0.0, 1.5, 1.6, id="div"), W(0.0, 1.6, 1.5, 1.6, id="top"),
           O(1.4, 0.6, 1.6, 0.95, id="door")]
    g = Geometry(4.2, 2.6, els, (2.9, 1.3),
                 [M(0.6, 0.8, "Small room", -0.6, "m1"), M(3.6, 2.0, "Large room", 0.6, "m2")],
                 Boundary("partial", 0.12))
    return [AcousticState("Dual Chamber", g)], None


def build_preset(key: str):
    """-> (list of AcousticState, Timeline or None)"""
    states, tl = PRESETS[key]["build"]()
    for k, st in enumerate(states):
        st.preset = f"{key}-{k}"
    return states, tl


def rebuild_state_geometry(preset_ref: str):
    """Original geometry of the state a preset produced ('key-index')."""
    key, _, idx = preset_ref.rpartition("-")
    if key not in PRESETS or not idx.isdigit():
        return None
    states, _ = PRESETS[key]["build"]()
    k = int(idx)
    return states[k].geometry if k < len(states) else None


def preset_keys() -> List[str]:
    return list(PRESETS.keys())



# ---------------------------------------------------------------- module-style access
# (the code below was organised as modules; these namespaces keep its calls readable)
presets = SimpleNamespace(PRESETS=PRESETS, build=build_preset, preset_keys=preset_keys,
                          rebuild_state_geometry=rebuild_state_geometry)
projmod = SimpleNamespace(Project=Project, SourceRef=SourceRef, OutputSettings=OutputSettings,
                          ProjectError=ProjectError, save=save_project_file, load=load_project_file,
                          save_geometry=save_geometry_file, load_geometry=load_geometry_file)
project = projmod



# ============================================================================
# GUI: COMMON (colours, audio player, background workers)
# ============================================================================
# Shared GUI infrastructure: theme, audio playback, background workers.
# ------------------------------------------------------------------ theme

ACCENT = "#c8762b"        # source / highlights
MIC_COLORS = ["#2b7bb9", "#3a9d6a", "#8e5bb5", "#b9483f"]
WALL = "#3b3f45"
WALL_ABS = "#6f8fa8"
OPENING = "#fbfbf8"
ROOM_BG = "#fbfbf8"
OUTSIDE = "#e6e6e3"
GRID = "#e2e2de"

STYLE = """
QMainWindow, QWidget { font-size: 9pt; }
QToolBar { spacing: 4px; padding: 2px; border: 0; }
QToolButton { padding: 3px 7px; }
QTabWidget::pane { border: 1px solid #cfcfcb; }
QGroupBox { font-weight: 600; margin-top: 8px; }
QGroupBox::title { subcontrol-origin: margin; left: 6px; padding: 0 3px; }
QLabel#hint { color: #555; padding: 3px 6px; background: #f2f1ec; border-radius: 3px; }
QLabel#warn { color: #8a4b00; }
"""


def diverging_lut(n=256) -> np.ndarray:
    """Blue - white - red map with a neutral (white) zero."""
    t = np.linspace(-1, 1, n)
    neg = np.array([33, 102, 172]) / 255.0
    pos = np.array([178, 24, 43]) / 255.0
    white = np.ones(3)
    lut = np.empty((n, 4))
    for k, v in enumerate(t):
        a = abs(v) ** 0.8
        col = white * (1 - a) + (pos if v > 0 else neg) * a
        lut[k, :3] = col
        lut[k, 3] = 1.0
    return (lut * 255).astype(np.ubyte)


# ------------------------------------------------------------------ audio


class Player(QtCore.QObject):
    """Non-blocking playback.  sounddevice if available, else Qt Multimedia."""
    started = QtCore.Signal()
    stopped = QtCore.Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.backend = None
        self._sd = None
        self._sink = None
        self._buf = None
        self._t0 = 0.0
        self._offset = 0.0
        self._dur = 0.0
        self._timer = QtCore.QTimer(self)
        self._timer.setInterval(100)
        self._timer.timeout.connect(self._poll)
        self.reason = ""
        try:
            import sounddevice as sd       # noqa
        except Exception:
            sd = None
            self.reason = "install sounddevice for audition"
        try:
            if sd is None:
                raise RuntimeError(self.reason)
            sd.query_devices(kind="output")    # raises if there is no output device
            self._sd = sd
            self.backend = "sounddevice"
        except Exception:
            if sd is not None:
                self.reason = "no audio output device found"
            try:
                # Qt Multimedia only where its audio backend is the system's own
                # (WASAPI / CoreAudio).  On Linux its device query can crash the
                # process when PipeWire/Pulse client libraries are misconfigured,
                # so there sounddevice is required for playback.
                import sys as _sys
                if _sys.platform not in ("win32", "darwin"):
                    raise RuntimeError("Qt Multimedia fallback disabled on this platform")
                from PySide6 import QtMultimedia   # noqa
                if QtMultimedia.QMediaDevices.defaultAudioOutput().isNull():
                    raise RuntimeError("no output device")
                self.backend = "Qt Multimedia"
            except Exception:
                self.backend = None

    @property
    def available(self) -> bool:
        return self.backend is not None

    def play(self, y: np.ndarray, fs: int, offset: float = 0.0):
        self.stop()
        if not self.available or y.size == 0:
            return
        y = np.asarray(y, dtype=np.float32)
        if y.ndim == 1:
            y = y[:, None]
        peak = float(np.abs(y).max())
        if peak > 1.0:
            y = y / peak                   # never clip on audition
        self._offset = offset
        self._dur = y.shape[0] / fs
        self._t0 = time.perf_counter()
        if self._sd is not None:
            self._sd.play(y, fs)
        else:
            from PySide6 import QtMultimedia
            fmt = QtMultimedia.QAudioFormat()
            fmt.setSampleRate(int(fs))
            fmt.setChannelCount(y.shape[1])
            fmt.setSampleFormat(QtMultimedia.QAudioFormat.Int16)
            pcm = (np.clip(y, -1, 1) * 32767).astype("<i2").tobytes()
            self._buf = QtCore.QBuffer()
            self._buf.setData(QtCore.QByteArray(pcm))
            self._buf.open(QtCore.QIODevice.ReadOnly)
            self._sink = QtMultimedia.QAudioSink(QtMultimedia.QMediaDevices.defaultAudioOutput(), fmt)
            self._sink.start(self._buf)
        self._timer.start()
        self.started.emit()

    def position(self) -> Optional[float]:
        if not self._timer.isActive():
            return None
        return self._offset + (time.perf_counter() - self._t0)

    def stop(self):
        was = self._timer.isActive()
        self._timer.stop()
        if self._sd is not None:
            try:
                self._sd.stop()
            except Exception:
                pass
        if self._sink is not None:
            self._sink.stop()
            self._sink = None
        if was:
            self.stopped.emit()

    def _poll(self):
        if time.perf_counter() - self._t0 > self._dur + 0.2:
            self.stop()


# ---------------------------------------------------------------- workers


class Worker(QtCore.QObject):
    """Runs fn(progress, cancel) in a QThread.  Emits finished(result) or
    failed(message, is_cancel).  The GUI thread never runs the solver."""
    progress = QtCore.Signal(float, str)
    finished = QtCore.Signal(object)
    failed = QtCore.Signal(str, bool)

    def __init__(self, fn: Callable, label: str):
        super().__init__()
        self.fn = fn
        self.label = label
        self.cancel_event = threading.Event()

    def run(self):
        try:
            res = self.fn(lambda f, m="": self.progress.emit(float(f), m), self.cancel_event.is_set)
            if self.cancel_event.is_set():
                self.failed.emit("Cancelled", True)
            else:
                self.finished.emit(res)
        except Cancelled:
            self.failed.emit("Cancelled", True)
        except Exception as e:      # reported to the user, never swallowed
            msg = f"{type(e).__name__}: {e}"
            if not isinstance(e, (ValueError, RuntimeError)):
                msg += "\n\n" + traceback.format_exc(limit=6)
            self.failed.emit(msg, False)


class TaskRunner(QtCore.QObject):
    """One background task at a time (compute or render).

    Worker signals are connected to slots of THIS object, which lives in the
    GUI thread, so every callback runs in the GUI thread (queued)."""
    busy_changed = QtCore.Signal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.thread: Optional[QtCore.QThread] = None
        self.worker: Optional[Worker] = None
        self._cb = (None, None, None)

    @property
    def busy(self) -> bool:
        return self.thread is not None

    def start(self, worker: Worker, on_done, on_fail, on_progress):
        if self.busy:
            raise RuntimeError("A task is already running.")
        th = QtCore.QThread()
        worker.moveToThread(th)
        th.started.connect(worker.run)
        worker.progress.connect(self._on_progress)
        worker.finished.connect(self._on_finished)
        worker.failed.connect(self._on_failed)
        self._cb = (on_done, on_fail, on_progress)
        self.thread, self.worker = th, worker
        self.busy_changed.emit(True)
        th.start()

    def cancel(self):
        if self.worker is not None:
            self.worker.cancel_event.set()

    def _cleanup(self):
        th = self.thread
        self.thread, self.worker = None, None
        if th is not None:
            th.quit()
            th.wait(5000)
        self.busy_changed.emit(False)

    @QtCore.Slot(float, str)
    def _on_progress(self, f, m):
        if self._cb[2]:
            self._cb[2](f, m)

    @QtCore.Slot(object)
    def _on_finished(self, r):
        cb = self._cb[0]
        self._cleanup()
        cb(r)

    @QtCore.Slot(str, bool)
    def _on_failed(self, m, c):
        cb = self._cb[1]
        self._cleanup()
        cb(m, c)


def spin(lo, hi, val, step=0.01, dec=3, suffix="", tip="") -> QtWidgets.QDoubleSpinBox:
    s = QtWidgets.QDoubleSpinBox()
    s.setRange(lo, hi); s.setDecimals(dec); s.setSingleStep(step); s.setValue(val)
    if suffix:
        s.setSuffix(suffix)
    if tip:
        s.setToolTip(tip)
    s.setKeyboardTracking(False)
    return s



# ============================================================================
# GUI: GEOMETRY EDITOR
# ============================================================================
# Interactive geometry editor (left panel).
#
# Scene coordinates are metres with y pointing DOWN (scene_y = H - y); the model
# keeps y up.  Items are rebuilt from the model after every change - geometries
# are small, and it keeps model and picture identical by construction.
#
# The editor never runs the solver; it only edits the Geometry and pushes undo
# snapshots.
TOOLS = ("select", "wall", "rect", "opening", "source", "mic", "pan")
TOOL_TIPS = {
    "select": "Select, move (drag) and resize (drag a handle).  Delete removes the selection.",
    "wall": "Draw a wall: press and drag.  Thickness and absorption are set in the properties.",
    "rect": "Draw a solid rectangular obstacle: press and drag.",
    "opening": "Draw an opening: a rectangle forced to AIR that cuts doors and slits "
               "through walls and obstacles.",
    "source": "Click to place the (single) sound source.",
    "mic": f"Click to add a microphone (up to {MAX_MICS}).",
    "pan": "Drag to pan (or use the middle mouse button anywhere).  Wheel zooms.",
}


class SnapshotCommand(QtGui.QUndoCommand):
    """Undo step = geometry before/after (complete snapshots)."""

    def __init__(self, editor, geom: Geometry, before: dict, after: dict, text: str):
        super().__init__(text)
        self.editor, self.geom, self.before, self.after = editor, geom, before, after
        self._first = True

    def redo(self):
        if self._first:
            self._first = False
            return
        self.editor.apply_snapshot(self.geom, self.after)

    def undo(self):
        self.editor.apply_snapshot(self.geom, self.before)


class GeometryEditor(QtWidgets.QGraphicsView):
    changed = QtCore.Signal()                 # model changed (any edit)
    selection_changed = QtCore.Signal(object)
    status = QtCore.Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setScene(QtWidgets.QGraphicsScene(self))
        self.setRenderHints(QtGui.QPainter.Antialiasing | QtGui.QPainter.SmoothPixmapTransform)
        self.setTransformationAnchor(QtWidgets.QGraphicsView.AnchorUnderMouse)
        self.setViewportUpdateMode(QtWidgets.QGraphicsView.FullViewportUpdate)
        self.setMouseTracking(True)
        self.setMinimumSize(360, 280)
        self.geom: Optional[Geometry] = None
        self.undo_stack: Optional[QtGui.QUndoStack] = None
        self.tool = "select"
        self.snap = True
        self.grid_step = 0.05
        self.show_grid = True
        self.raster_dx: Optional[float] = None
        self._raster_img: Optional[QtGui.QImage] = None
        self.sel: Optional[Tuple] = None
        self.default_alpha = 0.0
        self.default_thickness = 0.06
        self._drag = None
        self._before = None
        self._preview = None
        self._panning = None
        self._zoom_fitted = False

    # ---------------------------------------------------------------- model
    def set_geometry(self, geom: Geometry, stack: QtGui.QUndoStack):
        self.geom = geom
        self.undo_stack = stack
        self.sel = None
        self.rebuild()
        self.fit()
        self.selection_changed.emit(None)

    def apply_snapshot(self, geom: Geometry, d: dict):
        g2 = Geometry.from_dict(d)
        geom.width, geom.height = g2.width, g2.height
        geom.elements, geom.source, geom.mics, geom.boundary = g2.elements, g2.source, g2.mics, g2.boundary
        if geom is self.geom:
            if self.sel and not self._sel_exists(self.sel):
                self.sel = None
                self.selection_changed.emit(None)
            self.rebuild()
        self.changed.emit()

    def begin_edit(self):
        self._before = self.geom.to_dict()

    def end_edit(self, text: str):
        if self._before is None:
            return
        after = self.geom.to_dict()
        if after != self._before and self.undo_stack is not None:
            self.undo_stack.push(SnapshotCommand(self, self.geom, self._before, after, text))
            self.changed.emit()
        self._before = None

    def edit(self, fn, text: str):
        """Apply fn() to the model as one undoable step."""
        self.begin_edit()
        fn()
        self.rebuild()
        self.end_edit(text)

    def _sel_exists(self, sel):
        if sel[0] == "element":
            return any(e.id == sel[1] for e in self.geom.elements)
        if sel[0] == "mic":
            return any(m.id == sel[1] for m in self.geom.mics)
        return True

    # ------------------------------------------------------------ geometry
    def to_scene(self, x, y) -> QtCore.QPointF:
        return QtCore.QPointF(x, self.geom.height - y)

    def to_model(self, p: QtCore.QPointF) -> Tuple[float, float]:
        return p.x(), self.geom.height - p.y()

    def snapped(self, x, y):
        if self.snap:
            s = self.grid_step
            return round(x / s) * s, round(y / s) * s
        return x, y

    def px(self) -> float:
        """metres per screen pixel"""
        return 1.0 / max(self.transform().m11(), 1e-9)

    def fit(self):
        if self.geom is None:
            return
        m = 0.08 * max(self.geom.width, self.geom.height)
        r = QtCore.QRectF(-m, -m, self.geom.width + 2 * m, self.geom.height + 2 * m)
        self.scene().setSceneRect(r.adjusted(-50, -50, 50, 50))
        self.fitInView(r, QtCore.Qt.KeepAspectRatio)

    def set_raster(self, dx: Optional[float]):
        self.raster_dx = dx
        self._update_raster()
        self.viewport().update()

    def _update_raster(self):
        self._raster_img = None
        if self.raster_dx and self.geom is not None:
            try:
                r = rasterize(self.geom, self.raster_dx)
            except Exception:
                return
            a = np.zeros((r.ny, r.nx, 4), np.uint8)
            sol = r.solid.T[::-1]
            a[sol] = (200, 70, 40, 110)
            a[~sol] = (0, 0, 0, 0)
            a = np.ascontiguousarray(a)
            self._raster_img = QtGui.QImage(a.data, r.nx, r.ny, 4 * r.nx, QtGui.QImage.Format_RGBA8888).copy()
            self._raster_extent = (r.nx * r.dx, r.ny * r.dx)

    # ------------------------------------------------------------ drawing
    def rebuild(self):
        sc = self.scene()
        sc.clear()
        g = self.geom
        if g is None:
            return
        # elements: solids first, openings on top
        for e in g.elements:
            if e.kind == "wall":
                col = QtGui.QColor(WALL if e.alpha <= 0 else WALL_ABS)
                pen = QtGui.QPen(col, max(e.thickness, 0.001), QtCore.Qt.SolidLine, QtCore.Qt.RoundCap)
                it = sc.addLine(QtCore.QLineF(self.to_scene(e.x0, e.y0), self.to_scene(e.x1, e.y1)), pen)
            elif e.kind == "rect":
                col = QtGui.QColor(WALL if e.alpha <= 0 else WALL_ABS)
                it = sc.addRect(self._rect(e), QtGui.QPen(QtCore.Qt.NoPen), QtGui.QBrush(col))
            else:
                continue
            it.setToolTip(f"{e.kind} {e.id}  alpha {e.alpha:.2f}")
        for e in g.elements:
            if e.kind != "opening":
                continue
            pen = QtGui.QPen(QtGui.QColor("#7a7a72"), 0)
            pen.setStyle(QtCore.Qt.DashLine)
            it = sc.addRect(self._rect(e), pen, QtGui.QBrush(QtGui.QColor(OPENING)))
            it.setToolTip(f"opening {e.id}")
        # source
        r = 0.05 * max(1.0, max(g.width, g.height) / 4)
        s = self.to_scene(*g.source)
        it = sc.addEllipse(s.x() - r, s.y() - r, 2 * r, 2 * r, QtGui.QPen(QtGui.QColor("#5a3510"), 0),
                           QtGui.QBrush(QtGui.QColor(ACCENT)))
        self._label(sc, "S", s, "#ffffff", bold=True)
        # mics
        for k, m in enumerate(g.mics):
            c = QtGui.QColor(MIC_COLORS[k % len(MIC_COLORS)] if m.enabled else "#9a9a9a")
            p = self.to_scene(m.x, m.y)
            rr = 0.8 * r
            sc.addEllipse(p.x() - rr, p.y() - rr, 2 * rr, 2 * rr, QtGui.QPen(c.darker(150), 0),
                          QtGui.QBrush(c))
            self._label(sc, m.name, QtCore.QPointF(p.x() + 1.4 * rr, p.y() - 1.4 * rr), c.darker(140).name(),
                        anchor_left=True)
        # selection
        if self.sel:
            self._draw_selection(sc)
        if self._preview is not None:
            kind, a, b = self._preview
            pen = QtGui.QPen(QtGui.QColor(ACCENT), 0, QtCore.Qt.DashLine)
            if kind == "wall":
                sc.addLine(QtCore.QLineF(self.to_scene(*a), self.to_scene(*b)), pen)
            else:
                sc.addRect(QtCore.QRectF(self.to_scene(*a), self.to_scene(*b)).normalized(), pen)
        self._update_raster()
        self.viewport().update()

    def _rect(self, e: Element) -> QtCore.QRectF:
        return QtCore.QRectF(self.to_scene(e.x0, e.y0), self.to_scene(e.x1, e.y1)).normalized()

    def _label(self, sc, text, pos, color, bold=False, anchor_left=False):
        t = sc.addSimpleText(text)
        f = t.font(); f.setPointSizeF(8); f.setBold(bold); t.setFont(f)
        t.setBrush(QtGui.QBrush(QtGui.QColor(color)))
        t.setFlag(QtWidgets.QGraphicsItem.ItemIgnoresTransformations)
        br = t.boundingRect()
        t.setPos(pos)
        if not anchor_left:
            # the item ignores the view transform, so this shift is in pixels
            t.setTransform(QtGui.QTransform.fromTranslate(-br.width() / 2, -br.height() / 2))
        return t

    def _handles(self):
        """[(name, x, y)] handles of the selected element (model coords)."""
        if not self.sel or self.sel[0] != "element":
            return []
        e = self._elem(self.sel[1])
        if e is None:
            return []
        if e.kind == "wall":
            return [("p0", e.x0, e.y0), ("p1", e.x1, e.y1)]
        return [("c00", e.x0, e.y0), ("c10", e.x1, e.y0), ("c01", e.x0, e.y1), ("c11", e.x1, e.y1)]

    def _draw_selection(self, sc):
        pen = QtGui.QPen(QtGui.QColor(ACCENT), 0)
        pen.setCosmetic(True); pen.setWidthF(1.5)
        kind = self.sel[0]
        if kind == "element":
            e = self._elem(self.sel[1])
            if e is None:
                return
            x0, y0, x1, y1 = e.bbox()
            sc.addRect(QtCore.QRectF(self.to_scene(x0, y0), self.to_scene(x1, y1)).normalized(), pen)
            for _, hx, hy in self._handles():
                h = sc.addRect(-4, -4, 8, 8, QtGui.QPen(QtGui.QColor("#5a3510"), 0),
                               QtGui.QBrush(QtGui.QColor(ACCENT)))
                h.setFlag(QtWidgets.QGraphicsItem.ItemIgnoresTransformations)
                h.setPos(self.to_scene(hx, hy))
        else:
            if kind == "mic":
                m = self.geom.mic_by_id(self.sel[1])
                if m is None:
                    return
                x, y = m.x, m.y
            else:
                x, y = self.geom.source
            c = self.to_scene(x, y)
            h = sc.addEllipse(-11, -11, 22, 22, pen)
            h.setFlag(QtWidgets.QGraphicsItem.ItemIgnoresTransformations)
            h.setPos(c)

    def drawBackground(self, painter, rect):
        painter.fillRect(rect, QtGui.QColor(OUTSIDE))
        if self.geom is None:
            return
        g = self.geom
        room = QtCore.QRectF(0, 0, g.width, g.height)
        painter.fillRect(room, QtGui.QColor(ROOM_BG))
        if self.show_grid:
            step = self.grid_step
            while step / self.px() < 8:
                step *= 2
            pen = QtGui.QPen(QtGui.QColor(GRID), 0)
            painter.setPen(pen)
            x = 0.0
            while x <= g.width + 1e-9:
                painter.drawLine(QtCore.QLineF(x, 0, x, g.height)); x += step
            y = 0.0
            while y <= g.height + 1e-9:
                painter.drawLine(QtCore.QLineF(0, g.height - y, g.width, g.height - y)); y += step
            pen = QtGui.QPen(QtGui.QColor("#cdcdc7"), 0)
            painter.setPen(pen)
            for k in range(int(g.width) + 1):
                painter.drawLine(QtCore.QLineF(k, 0, k, g.height))
            for k in range(int(g.height) + 1):
                painter.drawLine(QtCore.QLineF(0, g.height - k, g.width, g.height - k))
        if self._raster_img is not None:
            w, h = self._raster_extent
            painter.drawImage(QtCore.QRectF(0, g.height - h, w, h), self._raster_img)
        mode = g.boundary.mode
        pen = QtGui.QPen(QtGui.QColor("#30343a"))
        pen.setCosmetic(True)
        if mode == "rigid":
            pen.setWidthF(4)
        elif mode == "partial":
            pen.setWidthF(2.5); pen.setColor(QtGui.QColor(WALL_ABS).darker(130))
        else:
            pen.setWidthF(1.2); pen.setStyle(QtCore.Qt.DotLine)
        painter.setPen(pen)
        painter.drawRect(room)

    def drawForeground(self, painter, rect):
        if self.geom is None:
            return
        painter.save()
        painter.resetTransform()
        vp = self.viewport().rect()
        mpp = self.px()
        # scale bar with a "nice" length
        target = 110 * mpp
        nice = [0.01, 0.02, 0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 5, 10]
        L = min(nice, key=lambda v: abs(v - target))
        Lpx = L / mpp
        x0, y0 = 14, vp.height() - 16
        painter.setPen(QtGui.QPen(QtGui.QColor("#30343a"), 2))
        painter.drawLine(QtCore.QPointF(x0, y0), QtCore.QPointF(x0 + Lpx, y0))
        painter.drawLine(QtCore.QPointF(x0, y0 - 4), QtCore.QPointF(x0, y0 + 4))
        painter.drawLine(QtCore.QPointF(x0 + Lpx, y0 - 4), QtCore.QPointF(x0 + Lpx, y0 + 4))
        painter.setFont(QtGui.QFont(painter.font().family(), 8))
        lab = f"{L * 100:.0f} cm" if L < 1 else f"{L:g} m"
        painter.drawText(QtCore.QPointF(x0 + Lpx + 6, y0 + 4), lab)
        g = self.geom
        info = f"room {g.width:.2f} x {g.height:.2f} m   boundary: {g.boundary.mode}"
        if g.boundary.mode == "partial":
            info += f" (alpha {g.boundary.alpha:.2f})"
        if self.raster_dx:
            info += f"   grid overlay {self.raster_dx * 100:.2f} cm"
        painter.setPen(QtGui.QColor("#555"))
        painter.drawText(QtCore.QPointF(x0, 16), info)
        painter.restore()

    # ------------------------------------------------------------ hit test
    def _elem(self, eid) -> Optional[Element]:
        for e in self.geom.elements:
            if e.id == eid:
                return e
        return None

    def hit(self, x, y):
        tol = 9 * self.px()
        for name, hx, hy in self._handles():
            if math.hypot(x - hx, y - hy) < tol:
                return ("handle", name)
        for m in self.geom.mics:
            if math.hypot(x - m.x, y - m.y) < tol * 1.3:
                return ("mic", m.id)
        sx, sy = self.geom.source
        if math.hypot(x - sx, y - sy) < tol * 1.3:
            return ("source",)
        # openings first (drawn on top), then solids, last drawn first
        order = [e for e in self.geom.elements if e.kind == "opening"][::-1] + \
                [e for e in self.geom.elements if e.kind != "opening"][::-1]
        for e in order:
            if e.kind == "wall":
                if _seg_dist(x, y, e) <= e.thickness / 2 + tol * 0.6:
                    return ("element", e.id)
            else:
                x0, y0, x1, y1 = e.bbox()
                if x0 - tol * 0.3 <= x <= x1 + tol * 0.3 and y0 - tol * 0.3 <= y <= y1 + tol * 0.3:
                    return ("element", e.id)
        return None

    def select(self, sel):
        self.sel = sel
        self.rebuild()
        self.selection_changed.emit(sel)

    # ------------------------------------------------------------- mouse
    def set_tool(self, tool):
        self.tool = tool
        self.setCursor(QtCore.Qt.OpenHandCursor if tool == "pan" else
                       (QtCore.Qt.ArrowCursor if tool == "select" else QtCore.Qt.CrossCursor))
        self.status.emit(TOOL_TIPS[tool])

    def wheelEvent(self, ev):
        f = 1.0015 ** ev.angleDelta().y()
        self.scale(f, f)

    def mousePressEvent(self, ev):
        if self.geom is None:
            return
        if ev.button() == QtCore.Qt.MiddleButton or (ev.button() == QtCore.Qt.LeftButton and self.tool == "pan"):
            self._panning = ev.position()
            self.setCursor(QtCore.Qt.ClosedHandCursor)
            return
        if ev.button() != QtCore.Qt.LeftButton:
            return
        x, y = self.to_model(self.mapToScene(ev.position().toPoint()))
        sx, sy = self.snapped(x, y)
        if self.tool == "select":
            h = self.hit(x, y)
            if h is None:
                self.select(None)
                return
            self.begin_edit()
            if h[0] == "handle":
                self._drag = ("handle", h[1], self.sel[1])
            else:
                if h != self.sel:
                    self.select(h)
                self._drag = ("move", h, (sx, sy), self.geom.to_dict())
        elif self.tool in ("wall", "rect", "opening"):
            self._drag = ("draw", self.tool, (sx, sy))
            self._preview = (self.tool, (sx, sy), (sx, sy))
        elif self.tool == "source":
            self.edit(lambda: setattr(self.geom, "source", (sx, sy)), "Move source")
            self.select(("source",))
        elif self.tool == "mic":
            h = self.hit(x, y)
            if h and h[0] == "mic":
                self.select(h)
                self.begin_edit()
                self._drag = ("move", h, (sx, sy), self.geom.to_dict())
                return
            if len(self.geom.mics) >= MAX_MICS:
                self.status.emit(f"At most {MAX_MICS} microphones.")
                return
            used = {m.name for m in self.geom.mics}
            k = 1
            while f"M{k}" in used:
                k += 1
            mic = Mic(sx, sy, f"M{k}")
            self.edit(lambda: self.geom.mics.append(mic), "Add microphone")
            self.select(("mic", mic.id))

    def mouseMoveEvent(self, ev):
        if self.geom is None:
            return
        if self._panning is not None:
            d = ev.position() - self._panning
            self._panning = ev.position()
            self.horizontalScrollBar().setValue(self.horizontalScrollBar().value() - int(d.x()))
            self.verticalScrollBar().setValue(self.verticalScrollBar().value() - int(d.y()))
            return
        x, y = self.to_model(self.mapToScene(ev.position().toPoint()))
        sx, sy = self.snapped(x, y)
        self.status.emit(f"x {x:.3f} m   y {y:.3f} m")
        if self._drag is None:
            return
        if self._drag[0] == "draw":
            self._preview = (self._drag[1], self._drag[2], (sx, sy))
            self.rebuild()
        elif self._drag[0] == "move":
            _, h, (ox, oy), base = self._drag
            dx, dy = sx - ox, sy - oy
            g0 = Geometry.from_dict(base)
            if h[0] == "element":
                e = self._elem(h[1]); e0 = next(q for q in g0.elements if q.id == h[1])
                e.x0, e.x1, e.y0, e.y1 = e0.x0 + dx, e0.x1 + dx, e0.y0 + dy, e0.y1 + dy
            elif h[0] == "mic":
                m = self.geom.mic_by_id(h[1]); m0 = g0.mic_by_id(h[1])
                m.x, m.y = m0.x + dx, m0.y + dy
            elif h[0] == "source":
                self.geom.source = (g0.source[0] + dx, g0.source[1] + dy)
            self.rebuild()
            self.selection_changed.emit(self.sel)
        elif self._drag[0] == "handle":
            _, name, eid = self._drag
            e = self._elem(eid)
            if name == "p0":
                e.x0, e.y0 = sx, sy
            elif name == "p1":
                e.x1, e.y1 = sx, sy
            else:
                if name[1] == "0":
                    e.x0 = sx
                else:
                    e.x1 = sx
                if name[2] == "0":
                    e.y0 = sy
                else:
                    e.y1 = sy
            self.rebuild()
            self.selection_changed.emit(self.sel)

    def mouseReleaseEvent(self, ev):
        if self._panning is not None:
            self._panning = None
            self.set_tool(self.tool)
            return
        if self._drag is None:
            return
        d = self._drag
        self._drag = None
        if d[0] == "draw":
            kind, a = d[1], d[2]
            b = self._preview[2]
            self._preview = None
            if kind == "wall":
                if math.hypot(b[0] - a[0], b[1] - a[1]) < 0.02:
                    self.rebuild(); return
                e = Element("wall", a[0], a[1], b[0], b[1], self.default_thickness, self.default_alpha)
            else:
                if abs(b[0] - a[0]) < 0.01 or abs(b[1] - a[1]) < 0.01:
                    self.rebuild(); return
                e = Element(kind, min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]),
                            alpha=self.default_alpha if kind == "rect" else 0.0)
            self.edit(lambda: self.geom.elements.append(e), f"Add {kind}")
            self.select(("element", e.id))
        else:
            self.end_edit("Move" if d[0] == "move" else "Resize")
            self.rebuild()

    def keyPressEvent(self, ev):
        if ev.key() in (QtCore.Qt.Key_Delete, QtCore.Qt.Key_Backspace):
            self.delete_selection()
        elif ev.key() == QtCore.Qt.Key_Escape:
            self._drag = None; self._preview = None
            self.select(None)
        else:
            super().keyPressEvent(ev)

    def delete_selection(self):
        s = self.sel
        if not s:
            return
        if s[0] == "element":
            self.edit(lambda: setattr(self.geom, "elements", [e for e in self.geom.elements if e.id != s[1]]),
                      "Delete element")
        elif s[0] == "mic":
            if len(self.geom.mics) <= 1:
                self.status.emit("Keep at least one microphone.")
                return
            self.edit(lambda: setattr(self.geom, "mics", [m for m in self.geom.mics if m.id != s[1]]),
                      "Delete microphone")
        else:
            self.status.emit("The source cannot be deleted (move it instead).")
            return
        self.select(None)

    def clear_elements(self):
        self.edit(lambda: setattr(self.geom, "elements", []), "Clear geometry")
        self.select(None)


def _seg_dist(x, y, e):
    ax, ay, bx, by = e.x0, e.y0, e.x1, e.y1
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    if L2 < 1e-12:
        return math.hypot(x - ax, y - ay)
    t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / L2))
    return math.hypot(x - (ax + t * vx), y - (ay + t * vy))


# ------------------------------------------------------------- properties


class PropertiesPanel(QtWidgets.QWidget):
    """Numeric editing of the selection (or of the room when nothing is selected)."""

    def __init__(self, editor: GeometryEditor, parent=None):
        super().__init__(parent)
        self.ed = editor
        self.form = QtWidgets.QFormLayout(self)
        self.form.setContentsMargins(4, 4, 4, 4)
        self.form.setLabelAlignment(QtCore.Qt.AlignRight)
        editor.selection_changed.connect(self.refresh)
        editor.changed.connect(self._on_changed)
        self._busy = False
        self._own_edit = False

    def _on_changed(self):
        # an edit made from this panel must not rebuild the spin box being used
        if not self._own_edit:
            self.refresh(self.ed.sel)

    def _clear(self):
        while self.form.rowCount():
            self.form.removeRow(0)

    def _num(self, label, val, lo, hi, setter, step=0.01, dec=3, suffix=" m", tip=""):
        s = QtWidgets.QDoubleSpinBox()
        s.setRange(lo, hi); s.setDecimals(dec); s.setSingleStep(step); s.setValue(val)
        s.setSuffix(suffix); s.setKeyboardTracking(False)
        if tip:
            s.setToolTip(tip)
        s.valueChanged.connect(lambda v: self._apply(setter, v, label))
        self.form.addRow(label, s)
        return s

    def _apply(self, setter, v, label):
        if self._busy:
            return
        self._own_edit = True
        try:
            self.ed.edit(lambda: setter(v), f"Set {label}")
        finally:
            self._own_edit = False

    def refresh(self, sel):
        if self.ed.geom is None:
            return
        self._busy = True
        self._clear()
        g = self.ed.geom
        ALPHA_TIP = ("Absorption coefficient (0 = rigid).  Frequency-independent, calibrated at normal "
                     "incidence: a locally reacting impedance Z = rho c (1+R)/(1-R), R = sqrt(1-alpha).")
        try:
            if sel is None:
                self.form.addRow(QtWidgets.QLabel("<b>Room</b>"))
                self._num("Width", g.width, 0.3, 30, lambda v: setattr(g, "width", v), 0.1, 2)
                self._num("Height", g.height, 0.3, 30, lambda v: setattr(g, "height", v), 0.1, 2)
                cb = QtWidgets.QComboBox()
                cb.addItems(["rigid", "partial", "absorbing"])
                cb.setCurrentText(g.boundary.mode)
                cb.setToolTip("rigid: perfectly reflecting edges.  partial: absorbing edges with alpha.  "
                              "absorbing: perfectly matched layer - waves leave the domain (open field).")
                cb.currentTextChanged.connect(lambda t: self._apply(lambda v: setattr(g.boundary, "mode", v), t, "boundary"))
                self.form.addRow("Boundary", cb)
                if g.boundary.mode == "partial":
                    self._num("Edge alpha", g.boundary.alpha, 0.0, 0.99,
                              lambda v: setattr(g.boundary, "alpha", v), 0.01, 2, "", ALPHA_TIP)
                n = len(g.elements)
                self.form.addRow(QtWidgets.QLabel(f"{n} element(s), {len(g.mics)} microphone(s)"))
            elif sel[0] == "element":
                e = self.ed._elem(sel[1])
                if e is None:
                    return
                self.form.addRow(QtWidgets.QLabel(f"<b>{e.kind.capitalize()}</b>  <span style='color:#888'>{e.id}</span>"))
                for nm in ("x0", "y0", "x1", "y1"):
                    self._num(nm, getattr(e, nm), -30, 60, (lambda n: lambda v: setattr(e, n, v))(nm))
                if e.kind == "wall":
                    self._num("Thickness", e.thickness, 0.005, 2.0, lambda v: setattr(e, "thickness", v), 0.01)
                if e.kind != "opening":
                    self._num("Absorption", e.alpha, 0.0, 0.99, lambda v: setattr(e, "alpha", v), 0.05, 2, "",
                              ALPHA_TIP)
            elif sel[0] == "mic":
                m = g.mic_by_id(sel[1])
                if m is None:
                    return
                self.form.addRow(QtWidgets.QLabel("<b>Microphone</b>"))
                le = QtWidgets.QLineEdit(m.name)
                le.editingFinished.connect(lambda: self._apply(lambda v: setattr(m, "name", v[:32] or "M"),
                                                               le.text(), "name"))
                self.form.addRow("Name", le)
                self._num("x", m.x, -30, 60, lambda v: setattr(m, "x", v))
                self._num("y", m.y, -30, 60, lambda v: setattr(m, "y", v))
                ch = QtWidgets.QCheckBox("enabled")
                ch.setChecked(m.enabled)
                ch.toggled.connect(lambda b: self._apply(lambda v: setattr(m, "enabled", v), b, "enabled"))
                self.form.addRow("", ch)
                self._num("Output gain", m.gain_db, -60, 24, lambda v: setattr(m, "gain_db", v), 0.5, 1, " dB",
                          "Gain of this microphone's layer in renders and mixes (does not change the simulation).")
                self._num("Pan", m.pan, -1, 1, lambda v: setattr(m, "pan", v), 0.1, 2, "",
                          "Stereo-mix position: -1 left, 0 centre, +1 right (equal-power).")
            else:
                self.form.addRow(QtWidgets.QLabel("<b>Source</b>"))
                self._num("x", g.source[0], -30, 60, lambda v: setattr(g, "source", (v, g.source[1])))
                self._num("y", g.source[1], -30, 60, lambda v: setattr(g, "source", (g.source[0], v)))
                self.form.addRow(QtWidgets.QLabel("Point source (one grid cell, bilinear)."))
        finally:
            self._busy = False



# ============================================================================
# GUI: ANALYSIS PANELS
# ============================================================================
# Right-hand panels: acoustic fingerprint, measurements, comparison and the
# wavefield viewer.  Everything shown is computed from the solver's data.
pg.setConfigOptions(antialias=True, background="w", foreground="#333")

LEVEL_MODES = ("Physical level (dB re 2-D free field at 1 m)",
               "Normalized timbre (each response peak = 0 dB)")


class LogFreqAxis(pg.AxisItem):
    """Frequency axis for log mode: readable labels (20, 50, 100 ... 20k)
    instead of pyqtgraph's overlapping 'a*10^b' minor-tick labels."""
    MAJOR = (10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000)

    def tickValues(self, minVal, maxVal, size):
        if not self.logMode:
            return super().tickValues(minVal, maxVal, size)
        lo, hi = 10 ** minVal, 10 ** maxVal
        major = [math.log10(v) for v in self.MAJOR if lo <= v <= hi]
        minor = [math.log10(m * d) for d in (1, 10, 100, 1000, 10000)
                 for m in range(1, 10) if lo <= m * d <= hi and m * d not in self.MAJOR]
        return [(1.0, major), (0.1, minor)]

    def tickStrings(self, values, scale, spacing):
        if not self.logMode:
            return super().tickStrings(values, scale, spacing)
        out = []
        for v in values:
            f = 10 ** v
            if spacing < 1.0:                # minor ticks: no labels
                out.append("")
            elif f >= 1000:
                out.append(f"{f / 1000:g}k")
            else:
                out.append(f"{f:g}")
        return out


def _plot(title, xlab, ylab, logx=False, legend=True):
    w = pg.PlotWidget(axisItems={"bottom": LogFreqAxis(orientation="bottom")})
    w.setTitle(title, size="9pt")
    w.setLabel("bottom", xlab); w.setLabel("left", ylab)
    for ax in ("bottom", "left"):
        w.getAxis(ax).enableAutoSIPrefix(False)     # no silent "(x0.001)" rescaling
    w.showGrid(x=True, y=True, alpha=0.25)
    if logx:
        w.setLogMode(x=True, y=False)
    if legend:
        w.addLegend(offset=(-8, 8), labelTextSize="8pt", brush=pg.mkBrush(255, 255, 255, 215),
                    pen=pg.mkPen("#cccccc"))
    return w


class FingerprintPanel(QtWidgets.QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        v = QtWidgets.QVBoxLayout(self); v.setContentsMargins(2, 2, 2, 2)
        self.banner = QtWidgets.QLabel("No response computed yet - press Compute.")
        self.banner.setObjectName("hint"); self.banner.setWordWrap(True)
        v.addWidget(self.banner)
        row = QtWidgets.QHBoxLayout()
        self.mic_box = QtWidgets.QHBoxLayout()
        row.addLayout(self.mic_box)
        row.addStretch(1)
        self.level = QtWidgets.QComboBox(); self.level.addItems(LEVEL_MODES)
        self.level.setToolTip("Physical: every response on one absolute scale, so differences in "
                              "transmission level stay visible.  Normalized: each response scaled to its "
                              "own peak, for comparing spectral SHAPE only.")
        row.addWidget(self.level)
        self.decay = QtWidgets.QComboBox()
        self.decay.addItems(["Energy decay (EDC)", "Spectrogram", "Phase (direct delay removed)"])
        row.addWidget(self.decay)
        v.addLayout(row)
        self.p_ir = _plot("Impulse response", "time (ms)", "pressure", legend=False)
        self.p_fr = _plot("Frequency response", "frequency (Hz)", "dB", logx=True)
        self.p_dec = _plot("Decay", "time (s)", "dB", legend=False)
        self.spec = pg.ImageItem()
        split = QtWidgets.QSplitter(QtCore.Qt.Vertical)
        for w in (self.p_ir, self.p_fr, self.p_dec):
            split.addWidget(w)
        split.setSizes([200, 260, 200])
        v.addWidget(split, 1)
        self.level.currentIndexChanged.connect(self.redraw)
        self.decay.currentIndexChanged.connect(self.redraw)
        self.resp = None
        self.geom = None
        self.mic_checks: Dict[str, QtWidgets.QCheckBox] = {}
        self.fps: Dict[str, Fingerprint] = {}

    def set_status(self, text, warn=False):
        self.banner.setText(text)
        self.banner.setObjectName("warn" if warn else "hint")
        self.banner.setStyleSheet("color:#8a4b00; background:#fbeedd; padding:3px 6px;" if warn else "")

    def set_response(self, resp, geom):
        self.resp, self.geom = resp, geom
        while self.mic_box.count():
            it = self.mic_box.takeAt(0)
            if it.widget():
                it.widget().deleteLater()
        self.mic_checks = {}
        self.fps = {}
        if resp is None:
            self.redraw()
            return
        for k, m in enumerate(geom.mics):
            if m.id not in resp.mics:
                continue
            cb = QtWidgets.QCheckBox(m.name)
            cb.setChecked(True)
            cb.setStyleSheet(f"color:{MIC_COLORS[k % 4]}; font-weight:600")
            cb.toggled.connect(self.redraw)
            self.mic_box.addWidget(cb)
            self.mic_checks[m.id] = cb
            self.fps[m.id] = fingerprint(resp.mics[m.id].ir, resp.fs, resp.f_valid)
        self.redraw()

    def selected(self):
        return [mid for mid, cb in self.mic_checks.items() if cb.isChecked()]

    def redraw(self):
        for p in (self.p_ir, self.p_fr, self.p_dec):
            p.clear()
        r = self.resp
        if r is None:
            return
        norm = self.level.currentIndex() == 1
        order = [m.id for m in self.geom.mics]
        # unmodelled band
        reg = pg.LinearRegionItem(values=(math.log10(r.f_valid), math.log10(r.fs / 2)), movable=False,
                                  brush=pg.mkBrush(120, 120, 120, 40), pen=pg.mkPen(None))
        self.p_fr.addItem(reg)
        txt = pg.TextItem(f"not modelled (> {r.f_valid:.0f} Hz)", color="#777", anchor=(0, 0))
        self.p_fr.addItem(txt); txt.setPos(math.log10(r.f_valid * 1.05), 0)
        lo_db, hi_db = [], []
        for mid in self.selected():
            k = order.index(mid) if mid in order else 0
            col = MIC_COLORS[k % 4]
            name = self.geom.mics[k].name if k < len(self.geom.mics) else mid
            h = r.mics[mid].ir
            fp = self.fps[mid]
            g = 1.0 / np.abs(h).max() if (norm and np.abs(h).max() > 0) else 1.0
            t = np.arange(len(h)) / r.fs * 1000
            n_show = min(len(h), int(0.25 * r.fs))
            self.p_ir.plot(t[:n_show], (h * g)[:n_show], pen=pg.mkPen(col, width=1), name=name)
            f = fp.freqs
            keep = (f >= 20) & (f <= r.fs / 2)
            mdb = fp.mag_db.copy()
            if norm:
                band = (f >= 30) & (f <= r.f_valid)
                mdb -= mdb[band].max() if band.any() else 0
            step = max(1, keep.sum() // 4000)
            ff, mm = f[keep][::step], mdb[keep][::step]
            self.p_fr.plot(ff, mm, pen=pg.mkPen(col, width=1.4), name=name)
            inb = ff < r.f_valid
            lo_db.append(np.percentile(mm[inb], 2) if inb.any() else -60)
            hi_db.append(mm[inb].max() if inb.any() else 0)
            if fp.peaks:
                off = (fp.mag_db[(f >= 30) & (f <= r.f_valid)].max() if norm else 0)
                self.p_fr.plot([a for a, _ in fp.peaks[:6]], [b - off for _, b in fp.peaks[:6]], pen=None,
                               symbol="t1", symbolSize=8, symbolBrush=col, symbolPen=None)
            if self.decay.currentIndex() == 0:
                self.p_dec.plot(fp.edc_t, fp.edc_db, pen=pg.mkPen(col, width=1.4), name=name)
            elif self.decay.currentIndex() == 2:
                band = (f >= 30) & (f <= r.f_valid)
                td = fp.direct_ms / 1000 if math.isfinite(fp.direct_ms) else 0.0
                ph = fp.phase[band] + 2 * np.pi * f[band] * td
                stp = max(1, band.sum() // 2000)
                self.p_dec.plot(f[band][::stp], ph[::stp], pen=pg.mkPen(col, width=1.2), name=name)
        self.p_dec.setLogMode(x=self.decay.currentIndex() == 2, y=False)
        if self.decay.currentIndex() == 2:
            self.p_dec.setLabel("left", "phase (rad)"); self.p_dec.setLabel("bottom", "frequency (Hz)")
            self.p_dec.setTitle("Phase response, direct-path delay removed (modelled band)", size="9pt")
        elif self.decay.currentIndex() == 1 and self.selected():
            mid = self.selected()[0]
            fs_, ts_, S = spectrogram_db(r.mics[mid].ir, r.fs, r.f_valid)
            img = pg.ImageItem(S.T)
            mx = S.max()
            img.setLevels([mx - 70, mx])
            img.setColorMap(pg.colormap.get("viridis"))
            img.setRect(QtCore.QRectF(0, 0, ts_[-1] if len(ts_) else 1, fs_[-1] if len(fs_) else 1))
            self.p_dec.addItem(img)
            self.p_dec.setLabel("left", "frequency (Hz)"); self.p_dec.setLabel("bottom", "time (s)")
            self.p_dec.setTitle(f"Spectrogram ({self.mic_checks[mid].text()}, modelled band)", size="9pt")
        else:
            self.p_dec.setLabel("left", "dB"); self.p_dec.setLabel("bottom", "time (s)")
            self.p_dec.setTitle("Energy decay curve (Schroeder)", size="9pt")
            self.p_dec.setYRange(-70, 2)
        if lo_db:
            top = 3 if norm else max(hi_db) + 3
            self.p_fr.setYRange(max(min(lo_db) - 6, top - 90), top, padding=0)
            txt.setPos(math.log10(r.f_valid * 1.05), top - 2)
        self.p_fr.setXRange(math.log10(20), math.log10(r.fs / 2))
        self.p_fr.setLabel("left", "dB (normalized)" if norm else "dB re 2-D free field @ 1 m")


class MeasurementsPanel(QtWidgets.QTextBrowser):
    def show_response(self, resp, geom, state_name, status):
        if resp is None:
            self.setHtml("<p>No response computed for this state.</p>")
            return
        rows = []
        for k, m in enumerate(geom.mics):
            if m.id not in resp.mics:
                continue
            fp = fingerprint(resp.mics[m.id].ir, resp.fs, resp.f_valid)
            d = math.hypot(m.x - geom.source[0], m.y - geom.source[1])
            fmt = lambda v: "-" if v is None else f"{v:.2f} s"
            pk = ", ".join(f"{f:.0f}" for f, _ in fp.peaks[:6]) or "-"
            nt = ", ".join(f"{f:.0f}" for f, _ in fp.notches[:4]) or "-"
            ew = " / ".join(f"{p:.0f}%" for _, _, p in fp.energy_windows[:5])
            rows.append(f"<tr><td style='color:{MIC_COLORS[k % 4]}'><b>{html.escape(m.name)}</b></td>"
                        f"<td>{d:.2f} m</td><td>{fp.direct_ms:.2f} ms ({d / 343 * 1000:.2f})</td>"
                        f"<td>{fp.level_db:+.1f} dB</td><td>{fp.centroid:.0f} Hz</td>"
                        f"<td>{fmt(fp.edt)}</td><td>{fmt(fp.t20)}</td><td>{fmt(fp.t30)}</td>"
                        f"<td>{pk}</td><td>{nt}</td><td>{ew}</td>"
                        f"<td>{resp.mics[m.id].truncated_db:.0f} dB</td></tr>")
        names = {m.id: m.name for m in geom.mics}

        def named(w):          # the core reports microphone ids; show their names
            for mid, nm in names.items():
                w = w.replace(f"mic {mid} ", f"microphone '{nm}' ")
            return html.escape(w)
        warn = "".join(f"<li>{named(w)}</li>" for w in resp.warnings) or "<li>none</li>"
        self.setHtml(f"""
<h3 style='margin:2px 0'>{html.escape(state_name)} <span style='font-weight:normal;color:#777'>({status})</span></h3>
<p style='color:#555'>{html.escape(resp.plan_text)}<br>computed in {resp.elapsed:.1f} s.
2.5-D correction: {'on' if resp.correction_25d else 'off'}.</p>
<table border=0 cellspacing=0 cellpadding=3 style='font-size:8.5pt'>
<tr style='background:#eee'><th>mic</th><th>dist.</th><th>first arrival (geom.)</th><th>level*</th>
<th>centroid*</th><th>EDT</th><th>T20</th><th>T30</th><th>resonant peaks (Hz)</th><th>notches (Hz)</th>
<th>energy 0-5/5-20/20-50/50-100/100-200 ms</th><th>last 10 %</th></tr>
{''.join(rows)}</table>
<p style='color:#666;font-size:8pt'>* within the modelled band (&le; {resp.f_valid:.0f} Hz).  Levels are dB re the
2-D free field at 1 m.  Decay times are 2-D values extrapolated to -60 dB and are only indicative:
a 2-D room has no floor or ceiling and decays differently from a real 3-D room.</p>
<p><b>Warnings</b></p><ul>{warn}</ul>""")


class ComparePanel(QtWidgets.QWidget):
    """Spectral Architecture: overlay and difference of computed states."""
    def __init__(self, parent=None):
        super().__init__(parent)
        v = QtWidgets.QVBoxLayout(self); v.setContentsMargins(2, 2, 2, 2)
        row = QtWidgets.QHBoxLayout()
        self.list = QtWidgets.QListWidget()
        self.list.setMaximumHeight(90)
        row.addWidget(self.list, 1)
        col = QtWidgets.QVBoxLayout()
        self.mic = QtWidgets.QComboBox(); self.mic.addItems(["mic 1", "mic 2", "mic 3", "mic 4"])
        self.level = QtWidgets.QComboBox(); self.level.addItems(LEVEL_MODES)
        col.addWidget(QtWidgets.QLabel("Microphone (by position in each state)")); col.addWidget(self.mic)
        col.addWidget(self.level)
        row.addLayout(col)
        v.addLayout(row)
        self.p = _plot("Frequency responses", "frequency (Hz)", "dB", logx=True)
        self.d = _plot("Difference (2nd checked - 1st checked, 1/6 oct)", "frequency (Hz)", "dB", logx=True,
                       legend=False)
        self.table = QtWidgets.QTextBrowser(); self.table.setMaximumHeight(140)
        split = QtWidgets.QSplitter(QtCore.Qt.Vertical)
        split.addWidget(self.p); split.addWidget(self.d); split.addWidget(self.table)
        v.addWidget(split, 1)
        self.list.itemChanged.connect(self.redraw)
        self.mic.currentIndexChanged.connect(self.redraw)
        self.level.currentIndexChanged.connect(self.redraw)
        self.states = []
        self.cache = None

    def set_states(self, states, cache):
        checked = {self.list.item(i).data(QtCore.Qt.UserRole) for i in range(self.list.count())
                   if self.list.item(i).checkState() == QtCore.Qt.Checked}
        self.states, self.cache = states, cache
        self.list.blockSignals(True)
        self.list.clear()
        for st in states:
            stat = st.status(cache)
            it = QtWidgets.QListWidgetItem(f"{st.name}   [{stat}]")
            it.setData(QtCore.Qt.UserRole, st.id)
            it.setFlags(it.flags() | QtCore.Qt.ItemIsUserCheckable)
            if stat != "computed":
                it.setFlags(it.flags() & ~QtCore.Qt.ItemIsEnabled)
            it.setCheckState(QtCore.Qt.Checked if (st.id in checked and stat == "computed") else QtCore.Qt.Unchecked)
            self.list.addItem(it)
        self.list.blockSignals(False)
        self.redraw()

    def redraw(self):
        self.p.clear(); self.d.clear()
        k = self.mic.currentIndex()
        norm = self.level.currentIndex() == 1
        sel = []
        for i in range(self.list.count()):
            it = self.list.item(i)
            if it.checkState() == QtCore.Qt.Checked:
                st = next((s for s in self.states if s.id == it.data(QtCore.Qt.UserRole)), None)
                if st and st.status(self.cache) == "computed" and k < len(st.geometry.mics):
                    m = st.geometry.mics[k]
                    r = self.cache.get(st.response_key)
                    if m.id in r.mics:
                        sel.append((st, r, fingerprint(r.mics[m.id].ir, r.fs, r.f_valid)))
        palette = ["#1f5f99", "#b9483f", "#3a9d6a", "#8e5bb5", "#c8762b", "#555555"]
        rows = []
        for j, (st, r, fp) in enumerate(sel):
            f = fp.freqs; keep = (f >= 20) & (f <= r.f_valid * 1.2)
            m = fp.mag_db.copy()
            if norm:
                m -= m[(f >= 30) & (f <= r.f_valid)].max()
            step = max(1, keep.sum() // 3000)
            self.p.plot(f[keep][::step], m[keep][::step], pen=pg.mkPen(palette[j % 6], width=1.4), name=st.name)
            pk = ", ".join(f"{a:.0f}" for a, _ in fp.peaks[:5])
            rows.append(f"<tr><td style='color:{palette[j % 6]}'><b>{html.escape(st.name)}</b></td><td>{fp.level_db:+.1f} dB</td>"
                        f"<td>{fp.centroid:.0f} Hz</td><td>{'-' if fp.t30 is None else f'{fp.t30:.2f} s'}</td>"
                        f"<td>{pk}</td><td>{r.f_valid:.0f} Hz</td></tr>")
        if len(sel) >= 2:
            fv = min(sel[0][1].f_valid, sel[1][1].f_valid)
            ff, dd = spectral_difference(sel[0][2], sel[1][2], fv)
            step = max(1, len(ff) // 3000)
            self.d.plot(ff[::step], dd[::step], pen=pg.mkPen("#333", width=1.4))
            self.d.addItem(pg.InfiniteLine(0, angle=0, pen=pg.mkPen("#999", style=QtCore.Qt.DashLine)))
            rms = float(np.sqrt(np.mean(dd ** 2)))
            self.d.setTitle(f"Difference {sel[1][0].name} - {sel[0][0].name}: RMS {rms:.1f} dB", size="9pt")
        self.table.setHtml("<table cellpadding=3 style='font-size:8.5pt'><tr style='background:#eee'><th>state</th>"
                           "<th>level*</th><th>centroid*</th><th>T30 (2-D)</th><th>peaks (Hz)</th><th>band</th></tr>"
                           + "".join(rows) + "</table>"
                           "<p style='color:#666;font-size:8pt'>Check states above (computed ones only).  "
                           "* in the modelled band, dB re 2-D free field at 1 m.</p>")


class WavefieldPanel(QtWidgets.QWidget):
    """Animated pressure field from the solver's stored frames."""
    def __init__(self, parent=None):
        super().__init__(parent)
        v = QtWidgets.QVBoxLayout(self); v.setContentsMargins(2, 2, 2, 2)
        self.glw = pg.GraphicsLayoutWidget()
        self.vb = self.glw.addViewBox(lockAspect=True)
        self.vb.setMouseEnabled(True, True)
        self.img = pg.ImageItem()
        self.img.setLookupTable(diverging_lut())
        self.mask_img = pg.ImageItem()
        self.mics = pg.ScatterPlotItem(size=9, pen=pg.mkPen("k"))
        self.src = pg.ScatterPlotItem(size=11, brush=pg.mkBrush(ACCENT), pen=pg.mkPen("k"))
        for it in (self.img, self.mask_img, self.mics, self.src):
            self.vb.addItem(it)
        v.addWidget(self.glw, 1)
        row = QtWidgets.QHBoxLayout()
        self.play = QtWidgets.QPushButton("Play"); self.play.setCheckable(True)
        self.back = QtWidgets.QToolButton(); self.back.setText("<")
        self.fwd = QtWidgets.QToolButton(); self.fwd.setText(">")
        self.slider = QtWidgets.QSlider(QtCore.Qt.Horizontal)
        self.tlab = QtWidgets.QLabel("t = -")
        self.tlab.setMinimumWidth(80)
        for w in (self.back, self.play, self.fwd):
            row.addWidget(w)
        row.addWidget(self.slider, 1); row.addWidget(self.tlab)
        v.addLayout(row)
        row2 = QtWidgets.QHBoxLayout()
        self.speed = QtWidgets.QComboBox(); self.speed.addItems(["5 fps", "12 fps", "25 fps", "50 fps"])
        self.speed.setCurrentIndex(2)
        self.scale = QtWidgets.QSlider(QtCore.Qt.Horizontal); self.scale.setRange(-30, 30); self.scale.setValue(0)
        self.scale.setToolTip("Pressure scale (colour range), +-30 dB around the automatic level.")
        self.freeze = QtWidgets.QCheckBox("Freeze")
        self.freeze.setToolTip("Keep showing this field when another state is selected or recomputed "
                               "(for visual comparison).")
        self.show_geom = QtWidgets.QCheckBox("geometry"); self.show_geom.setChecked(True)
        self.show_mics = QtWidgets.QCheckBox("microphones"); self.show_mics.setChecked(True)
        row2.addWidget(QtWidgets.QLabel("speed")); row2.addWidget(self.speed)
        row2.addWidget(QtWidgets.QLabel("pressure scale")); row2.addWidget(self.scale, 1)
        for w in (self.freeze, self.show_geom, self.show_mics):
            row2.addWidget(w)
        v.addLayout(row2)
        self.note = QtWidgets.QLabel("Frames are the solver's own pressure field (decimated for display). "
                                     "Red = positive, blue = negative pressure, white = 0.")
        self.note.setObjectName("hint"); self.note.setWordWrap(True)
        v.addWidget(self.note)
        self.timer = QtCore.QTimer(self)
        self.timer.timeout.connect(self._tick)
        self.play.toggled.connect(self._toggle)
        self.back.clicked.connect(lambda: self._step(-1))
        self.fwd.clicked.connect(lambda: self._step(1))
        self.slider.valueChanged.connect(self._show)
        self.scale.valueChanged.connect(lambda _: self._show(self.slider.value()))
        self.speed.currentIndexChanged.connect(self._toggle)
        self.show_geom.toggled.connect(lambda b: self.mask_img.setVisible(b))
        self.show_mics.toggled.connect(lambda b: (self.mics.setVisible(b), self.src.setVisible(b)))
        self.frames = None

    def set_response(self, resp, geom):
        if self.freeze.isChecked() and self.frames is not None:
            return
        self.timer.stop(); self.play.setChecked(False)
        if resp is None or resp.frames is None or len(resp.frames) == 0:
            self.frames = None
            self.img.clear(); self.mask_img.clear()
            self.mics.setData([]); self.src.setData([])
            self.tlab.setText("no frames")
            return
        self.frames = resp.frames.astype(np.float32)
        self.times = resp.frame_times
        nfx, nfy = self.frames.shape[1], self.frames.shape[2]
        W, H = geom.width, geom.height
        cell = W / nfx
        self._rect = QtCore.QRectF(0, 0, nfx * cell, nfy * cell)
        m = resp.frame_mask
        rgba = np.zeros((m.shape[0], m.shape[1], 4), np.uint8)
        rgba[m] = (60, 63, 69, 255)
        # setRect only AFTER an image exists: on an empty ImageItem pyqtgraph
        # computes the scale from a 0-size image and shows one pixel stretched
        self.mask_img.setImage(rgba, levels=(0, 255), autoLevels=False)
        self.mask_img.setRect(self._rect)
        self.img.setImage(self.frames[0], levels=(-1, 1), autoLevels=False)
        self.img.setRect(self._rect)
        # robust automatic level: high percentile of |p| over the middle frames
        mid = self.frames[len(self.frames) // 4: max(len(self.frames) // 4 + 1, 3 * len(self.frames) // 4)]
        self.auto = float(np.percentile(np.abs(mid), 99.5)) or 1e-9
        self.mics.setData([mm.x for mm in geom.mics if mm.enabled], [mm.y for mm in geom.mics if mm.enabled],
                          brush=[pg.mkBrush(MIC_COLORS[k % 4]) for k, mm in enumerate(geom.mics) if mm.enabled])
        self.src.setData([geom.source[0]], [geom.source[1]])
        self.slider.blockSignals(True)
        self.slider.setRange(0, len(self.frames) - 1); self.slider.setValue(0)
        self.slider.blockSignals(False)
        self.vb.setRange(QtCore.QRectF(0, 0, W, H), padding=0.02)
        self._show(0)

    def _show(self, k):
        if self.frames is None:
            return
        k = int(np.clip(k, 0, len(self.frames) - 1))
        lev = self.auto * 10 ** (-self.scale.value() / 20)
        self.img.setImage(self.frames[k], levels=(-lev, lev), autoLevels=False)
        self.tlab.setText(f"t = {self.times[k] * 1000:.1f} ms")

    def _step(self, d):
        if self.frames is not None:
            self.slider.setValue((self.slider.value() + d) % len(self.frames))

    def _toggle(self, *_):
        if self.play.isChecked() and self.frames is not None:
            fps = [5, 12, 25, 50][self.speed.currentIndex()]
            self.timer.start(int(1000 / fps))
            self.play.setText("Pause")
        else:
            self.timer.stop()
            self.play.setText("Play")

    def _tick(self):
        self._step(1)



# ============================================================================
# GUI: COMPOSITION TIMELINE
# ============================================================================
# Composition timeline (bottom panel).
#
# A keyframe says: "at time t the mixture has moved AMOUNT of the way to state
# S" (100 % = S alone; 40 % = 40 % S, 60 % the previous mixture).  Its
# transition is the stretch BEFORE t during which the previous mixture hands
# over, shaped by a curve (linear / equal-power / smoothstep / hold).  Drag a keyframe to move
# it, drag the left edge of its shaded transition to lengthen or shorten the
# transition, double-click to edit numerically, right-click for more.
CURVE_LABELS = {"linear": "Linear", "equal_power": "Equal power", "smoothstep": "Smoothstep",
                "hold": "Hold (abrupt, 3 ms de-click)"}
STATE_COLORS = ["#1f5f99", "#b9483f", "#3a9d6a", "#8e5bb5", "#c8762b", "#5b6770", "#a0522d", "#2e8b8b"]


class TimelineView(QtWidgets.QWidget):
    changed = QtCore.Signal()
    cursor_moved = QtCore.Signal(float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumHeight(130)
        self.setMouseTracking(True)
        self.tl: Timeline = Timeline()
        self.names: Dict[str, str] = {}
        self.colors: Dict[str, str] = {}
        self.env = None             # (min, max) arrays of the source waveform
        self.duration = 4.0
        self.cursor = 0.0
        self.playhead: Optional[float] = None
        self._drag = None
        self._before = None
        self.undo_cb = None          # callable(before_dict, after_dict)

    # -------------------------------------------------------------- data
    def set_timeline(self, tl: Timeline, states: List):
        self.tl = tl
        self.names = {s.id: s.name for s in states}
        self.colors = {s.id: STATE_COLORS[k % len(STATE_COLORS)] for k, s in enumerate(states)}
        self.update()

    def set_source(self, x: Optional[np.ndarray], fs: int):
        if x is None or len(x) == 0:
            self.env = None
            self.duration = max(4.0, self._last_time() + 1.0)
        else:
            mono = x.mean(axis=1) if x.ndim == 2 else x
            n = 800
            hop = max(1, len(mono) // n)
            m = mono[:hop * (len(mono) // hop)].reshape(-1, hop)
            self.env = (m.min(axis=1), m.max(axis=1))
            self.duration = len(mono) / fs
        self.update()

    def _last_time(self):
        return max([k.time for k in self.tl.keyframes], default=0.0)

    def span(self):
        return max(self.duration, self._last_time() + 0.5, 0.5)

    # ---------------------------------------------------------- geometry
    def _x(self, t):
        return 10 + (self.width() - 20) * t / self.span()

    def _t(self, x):
        return max(0.0, (x - 10) / max(1, self.width() - 20) * self.span())

    # ------------------------------------------------------------ paint
    def paintEvent(self, ev):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        W, H = self.width(), self.height()
        p.fillRect(self.rect(), QtGui.QColor("#fbfbf8"))
        top, bot = 26, H - 18
        # waveform
        if self.env is not None:
            lo, hi = self.env
            n = len(lo)
            mid = (top + bot) / 2
            amp = (bot - top) / 2 * 0.9 / max(1e-9, max(abs(lo).max(), abs(hi).max()))
            path = QtGui.QPainterPath()
            xs = [self._x(i / n * self.duration) for i in range(n)]
            p.setPen(QtGui.QPen(QtGui.QColor("#d4d4ce"), 1))
            for i in range(n):
                p.drawLine(QtCore.QPointF(xs[i], mid - hi[i] * amp), QtCore.QPointF(xs[i], mid - lo[i] * amp))
        # time axis
        p.setPen(QtGui.QColor("#777"))
        f = p.font(); f.setPointSizeF(7.5); p.setFont(f)
        span = self.span()
        step = next(s for s in (0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60, 120) if span / s <= 12)
        t = 0.0
        while t <= span + 1e-9:
            x = self._x(t)
            p.drawLine(QtCore.QPointF(x, bot), QtCore.QPointF(x, bot + 4))
            p.drawText(QtCore.QPointF(x + 2, H - 4), f"{t:g}s")
            t += step
        if self.tl.loop and self.tl.keyframes:
            Lp = self.tl.loop_length or max(k.time for k in self.tl.keyframes)
            x = self._x(Lp)
            p.setPen(QtGui.QPen(QtGui.QColor("#8e5bb5"), 1, QtCore.Qt.DashDotLine))
            p.drawLine(QtCore.QPointF(x, top - 6), QtCore.QPointF(x, bot))
            p.drawText(QtCore.QPointF(x + 3, top - 8), "loop")
        # weight curves (computed by the same code the renderer uses)
        kfs = self.tl.sorted()
        if kfs:
            n = 600
            fs = n / span
            Wts = self.tl.weights(n, fs)
            for sid, w in Wts.items():
                col = QtGui.QColor(self.colors.get(sid, "#555"))
                fill = QtGui.QColor(col); fill.setAlpha(38)
                path = QtGui.QPainterPath()
                path.moveTo(self._x(0), bot)
                for i in range(n):
                    path.lineTo(self._x(i / fs), bot - (bot - top) * w[i])
                path.lineTo(self._x((n - 1) / fs), bot)
                p.fillPath(path, fill)
                p.setPen(QtGui.QPen(col, 1.4))
                p.drawPath(path)
        # keyframes
        for k in kfs:
            x = self._x(k.time)
            col = QtGui.QColor(self.colors.get(k.state_id, "#555"))
            x0 = self._x(k.time - k.transition)
            p.setPen(QtGui.QPen(col, 1, QtCore.Qt.DotLine))
            p.drawLine(QtCore.QPointF(x0, top), QtCore.QPointF(x0, bot))
            p.setPen(QtGui.QPen(col, 2))
            p.drawLine(QtCore.QPointF(x, top - 4), QtCore.QPointF(x, bot))
            label = self.names.get(k.state_id, "?")
            if k.amount < 0.999:
                label += f" {k.amount * 100:.0f}%"
            fm = p.fontMetrics()
            w = fm.horizontalAdvance(label) + 8
            r = QtCore.QRectF(x - w / 2, 3, w, 16)
            p.setBrush(col); p.setPen(QtCore.Qt.NoPen)
            p.drawRoundedRect(r, 3, 3)
            p.setPen(QtGui.QColor("white"))
            p.drawText(r, QtCore.Qt.AlignCenter, label)
        # cursor and playhead
        p.setPen(QtGui.QPen(QtGui.QColor(ACCENT), 1, QtCore.Qt.DashLine))
        xc = self._x(self.cursor)
        p.drawLine(QtCore.QPointF(xc, top - 4), QtCore.QPointF(xc, bot))
        if self.playhead is not None:
            p.setPen(QtGui.QPen(QtGui.QColor("#d02020"), 1.5))
            xp = self._x(self.playhead)
            p.drawLine(QtCore.QPointF(xp, 0), QtCore.QPointF(xp, H))
        if not kfs:
            p.setPen(QtGui.QColor("#888"))
            p.drawText(self.rect(), QtCore.Qt.AlignCenter,
                       "Empty timeline - click to set the cursor, then 'Add keyframe' places the current state there.")
        p.end()

    # ------------------------------------------------------------ mouse
    def _hit(self, x, y):
        for k in self.tl.keyframes:
            if abs(self._x(k.time) - x) < 6:
                return ("kf", k)
            if k.transition > 0 and abs(self._x(k.time - k.transition) - x) < 5 and y > 22:
                return ("tr", k)
        return None

    def mousePressEvent(self, ev):
        x, y = ev.position().x(), ev.position().y()
        h = self._hit(x, y)
        if ev.button() == QtCore.Qt.RightButton:
            if h:
                self._menu(h[1], ev.globalPosition().toPoint())
            return
        if h:
            self._before = self.tl.to_dict()
            self._drag = h
        else:
            self.cursor = self._t(x)
            self.cursor_moved.emit(self.cursor)
            self.update()

    def mouseMoveEvent(self, ev):
        x = ev.position().x()
        h = self._hit(x, ev.position().y())
        self.setCursor(QtCore.Qt.SizeHorCursor if h else QtCore.Qt.ArrowCursor)
        if not self._drag:
            return
        t = round(self._t(x) / 0.05) * 0.05
        kind, k = self._drag
        if kind == "kf":
            k.time = max(0.0, t)
        else:
            k.transition = max(0.0, min(k.time, k.time - t))
        self.update()

    def mouseReleaseEvent(self, ev):
        if self._drag:
            self._drag = None
            self._commit()

    def mouseDoubleClickEvent(self, ev):
        h = self._hit(ev.position().x(), ev.position().y())
        if h:
            self.edit_keyframe(h[1])

    def _commit(self):
        after = self.tl.to_dict()
        if self._before is not None and after != self._before and self.undo_cb:
            self.undo_cb(self._before, after)
        self._before = None
        self.changed.emit()
        self.update()

    def _menu(self, k: Keyframe, pos):
        m = QtWidgets.QMenu(self)
        sm = m.addMenu("State")
        for sid, nm in self.names.items():
            a = sm.addAction(nm)
            a.setCheckable(True); a.setChecked(sid == k.state_id)
            a.triggered.connect(lambda _=False, s=sid: self._set(k, "state_id", s))
        cm = m.addMenu("Transition curve")
        for c in CURVES:
            a = cm.addAction(CURVE_LABELS[c])
            a.setCheckable(True); a.setChecked(c == k.curve)
            a.triggered.connect(lambda _=False, c=c: self._set(k, "curve", c))
        m.addAction("Edit...").triggered.connect(lambda: self.edit_keyframe(k))
        m.addAction("Delete").triggered.connect(lambda: self.delete_keyframe(k))
        m.exec(pos)

    def _set(self, k, attr, v):
        self._before = self.tl.to_dict()
        setattr(k, attr, v)
        self._commit()

    def delete_keyframe(self, k):
        self._before = self.tl.to_dict()
        self.tl.keyframes = [q for q in self.tl.keyframes if q is not k]
        self._commit()

    def edit_keyframe(self, k):
        d = QtWidgets.QDialog(self)
        d.setWindowTitle("Keyframe")
        f = QtWidgets.QFormLayout(d)
        st = QtWidgets.QComboBox()
        ids = list(self.names)
        for sid in ids:
            st.addItem(self.names[sid], sid)
        st.setCurrentIndex(ids.index(k.state_id) if k.state_id in ids else 0)
        t = QtWidgets.QDoubleSpinBox(); t.setRange(0, 36000); t.setDecimals(3); t.setValue(k.time); t.setSuffix(" s")
        tr = QtWidgets.QDoubleSpinBox(); tr.setRange(0, 36000); tr.setDecimals(3); tr.setValue(k.transition)
        tr.setSuffix(" s")
        cv = QtWidgets.QComboBox()
        for c in CURVES:
            cv.addItem(CURVE_LABELS[c], c)
        cv.setCurrentIndex(CURVES.index(k.curve))
        am = QtWidgets.QSpinBox(); am.setRange(0, 100); am.setValue(int(round(k.amount * 100))); am.setSuffix(" %")
        am.setToolTip("How far the mixture moves toward this state (100 % = this state alone).")
        f.addRow("State", st); f.addRow("Reached at", t); f.addRow("Transition (before)", tr); f.addRow("Curve", cv)
        f.addRow("Amount", am)
        bb = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel)
        bb.accepted.connect(d.accept); bb.rejected.connect(d.reject)
        f.addRow(bb)
        if d.exec() == QtWidgets.QDialog.Accepted:
            self._before = self.tl.to_dict()
            k.state_id = st.currentData(); k.time = t.value(); k.transition = tr.value(); k.curve = cv.currentData()
            k.amount = am.value() / 100.0
            self._commit()


class TimelinePanel(QtWidgets.QWidget):
    add_requested = QtCore.Signal(float)
    morph_requested = QtCore.Signal()
    preview_requested = QtCore.Signal()
    stop_requested = QtCore.Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        v = QtWidgets.QVBoxLayout(self); v.setContentsMargins(2, 2, 2, 2)
        row = QtWidgets.QHBoxLayout()
        self.add = QtWidgets.QPushButton("Add keyframe")
        self.add.setToolTip("Place the current state at the timeline cursor.")
        self.curve = QtWidgets.QComboBox()
        for c in CURVES:
            self.curve.addItem(CURVE_LABELS[c], c)
        self.curve.setCurrentIndex(1)
        self.curve.setToolTip("Curve for new keyframes.  Equal power keeps loudness steady when the two "
                              "states' outputs are uncorrelated; linear keeps amplitude steady when they are "
                              "similar.")
        self.trans = QtWidgets.QDoubleSpinBox(); self.trans.setRange(0, 600); self.trans.setValue(1.0)
        self.trans.setSuffix(" s"); self.trans.setToolTip("Transition length for new keyframes.")
        self.amount = QtWidgets.QSpinBox(); self.amount.setRange(0, 100); self.amount.setValue(100)
        self.amount.setSuffix(" %")
        self.amount.setToolTip("Amount for new keyframes: how far the mixture moves toward the state "
                               "(100 % = the state alone; 40 % keeps 60 % of the previous mixture).")
        self.xfade = QtWidgets.QComboBox()
        self.xfade.addItem("Input crossfade (tail-preserving)", "input")
        self.xfade.addItem("Output crossfade", "output")
        self.xfade.setToolTip("Mode 1 - output morphing between static responses (NOT moving walls).\n"
                              "Input crossfade: the recording is split between states and each part is "
                              "convolved with its own state, so sound already in state A keeps decaying in A.\n"
                              "Output crossfade: the full wet outputs are crossfaded; A's tail fades with A.")
        self.loop = QtWidgets.QCheckBox("Loop")
        self.loop_len = QtWidgets.QDoubleSpinBox(); self.loop_len.setRange(0, 36000); self.loop_len.setSuffix(" s")
        self.loop_len.setToolTip("Cycle length (0 = last keyframe time + first transition).")
        self.morph = QtWidgets.QPushButton("Geometry morph...")
        self.morph.setToolTip("Mode 2: generate and SIMULATE intermediate geometries between two "
                              "corresponding states, and sequence them.  A chain of static rooms, not a "
                              "time-varying simulation.")
        self.preview = QtWidgets.QPushButton("Preview composition")
        self.stop = QtWidgets.QPushButton("Stop")
        for w in (self.add, QtWidgets.QLabel("curve"), self.curve, QtWidgets.QLabel("length"), self.trans,
                  QtWidgets.QLabel("amount"), self.amount, self.xfade, self.loop, self.loop_len, self.morph):
            row.addWidget(w)
        row.addStretch(1)
        row.addWidget(self.preview); row.addWidget(self.stop)
        v.addLayout(row)
        self.view = TimelineView()
        v.addWidget(self.view, 1)
        self.add.clicked.connect(lambda: self.add_requested.emit(self.view.cursor))
        self.morph.clicked.connect(self.morph_requested.emit)
        self.preview.clicked.connect(self.preview_requested.emit)
        self.stop.clicked.connect(self.stop_requested.emit)
        self.xfade.currentIndexChanged.connect(self._opts)
        self.loop.toggled.connect(self._opts)
        self.loop_len.valueChanged.connect(self._opts)

    def sync(self):
        tl = self.view.tl
        for w in (self.xfade, self.loop, self.loop_len):
            w.blockSignals(True)
        self.xfade.setCurrentIndex(0 if tl.xfade == "input" else 1)
        self.loop.setChecked(tl.loop)
        self.loop_len.setValue(tl.loop_length)
        for w in (self.xfade, self.loop, self.loop_len):
            w.blockSignals(False)

    def _opts(self, *_):
        tl = self.view.tl
        before = tl.to_dict()
        tl.xfade = self.xfade.currentData()
        tl.loop = self.loop.isChecked()
        tl.loop_length = self.loop_len.value()
        if self.view.undo_cb and before != tl.to_dict():
            self.view.undo_cb(before, tl.to_dict())
        self.view.changed.emit()
        self.view.update()



# ============================================================================
# SESSION PROTOCOL, AUTOMATION, MAIN WINDOW
# ============================================================================
# Acoustic Morphology Composer - Geometry-Driven Spectral Transformation and
# Spatial Resynthesis.  Praat AudioTools, Hybrid Systems.
#
#     Draw the space.  Shape the sound.  Compose its transformation.
#
# Usage
# -----
#   python acoustic_morphology_composer.py                 standalone
#   python acoustic_morphology_composer.py MANIFEST.json   launched by
#                                                          Acoustic_Morphology_Composer.praat
#   python acoustic_morphology_composer.py MANIFEST.json --automate SPEC.json
#         headless: no window; compute + render as SPEC says, write the outputs
#         and the completion manifest (used by the round-trip test)
#
# Praat session protocol (see Acoustic_Morphology_Composer.praat)
# ---------------------------------------------------------------
# Praat writes MANIFEST.json (UTF-8 or UTF-16) with input_file, session_dir,
# done_file, error_file, source_name, ... and blocks in runSubprocess until this
# process exits.  On "Return to Praat" this program writes the rendered WAVs
# into session_dir, then done.json (full description) and done.tsv (one line
# per output: kind <TAB> object name <TAB> file name), and exits.  done.tsv is
# written LAST, atomically, so Praat never sees a half-written result.  If the
# user closes without returning, no done file exists and Praat imports
# nothing.  An unexpected exception is written to error_file.
#
# Author: Shai Cohen - Department of Music, Bar-Ilan University - MIT License
#!/usr/bin/env python3


HERE = os.path.dirname(os.path.abspath(__file__))



# ======================================================================
# session / manifest helpers (no Qt needed)
# ======================================================================

def read_text_any(path: str) -> str:
    """Praat may write UTF-8 or UTF-16 depending on its preferences."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16")
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


def load_manifest(path: str) -> dict:
    m = json.loads(read_text_any(path))
    if not isinstance(m, dict):
        raise ValueError("manifest is not a JSON object")
    for k in ("input_file", "session_dir", "done_file", "error_file"):
        if not isinstance(m.get(k), str) or not m[k]:
            raise ValueError(f"manifest lacks '{k}'")
    m["session_dir"] = os.path.normpath(m["session_dir"])
    return m


def praat_name(s: str) -> str:
    """A safe Praat object name (letters, digits, underscore)."""
    s = re.sub(r"[^A-Za-z0-9_]+", "_", s).strip("_")
    return s[:60] or "x"


def write_error(manifest: dict, text: str):
    try:
        with open(manifest["error_file"], "w", encoding="utf-8") as f:
            f.write(text)
    except Exception:
        pass


def write_outputs(manifest: dict, outputs: list, summary: dict):
    """outputs: [(kind, name, array (n, ch), fs, description)].
    Writes WAVs, done.json, then done.tsv atomically (the commit point)."""
    import soundfile as sf
    sd = manifest["session_dir"]
    os.makedirs(sd, exist_ok=True)
    rows, desc = [], []
    used = set()
    for k, (kind, name, y, fs, text) in enumerate(outputs):
        nm = praat_name(name)
        base = nm
        j = 2
        while nm in used:
            nm = f"{base}_{j}"; j += 1
        used.add(nm)
        fn = f"out_{k:02d}_{kind}.wav"
        sf.write(os.path.join(sd, fn), y.astype("float32"), int(fs), subtype="FLOAT")
        rows.append(f"{kind}\t{nm}\t{fn}")
        desc.append({"kind": kind, "name": nm, "file": fn, "fs": int(fs), "channels": int(y.shape[1]),
                     "duration": y.shape[0] / fs, "description": text})
    done_json = os.path.join(sd, "done.json")
    with open(done_json + ".tmp", "w", encoding="utf-8") as f:
        json.dump({"status": "ok", "app": APP_NAME, "version": APP_VERSION, "outputs": desc,
                   "summary": summary, "time": time.strftime("%Y-%m-%d %H:%M:%S")}, f, indent=1,
                  ensure_ascii=False)
    os.replace(done_json + ".tmp", done_json)
    tsv = manifest["done_file"]
    with open(tsv + ".tmp", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    os.replace(tsv + ".tmp", tsv)


def load_audio(path: str):
    import numpy as np
    import soundfile as sf
    try:
        x, fs = sf.read(path, always_2d=True, dtype="float64")
    except Exception as e:
        raise ValueError(f"Cannot read audio file '{os.path.basename(path)}': {e}")
    if x.shape[1] > 2:
        raise ValueError(f"{x.shape[1]} channels: only mono and stereo sources are supported.")
    if x.shape[0] == 0:
        raise ValueError("The audio file is empty.")
    if not np.all(np.isfinite(x)):
        raise ValueError("The audio contains non-finite samples.")
    return x, int(fs)


# ======================================================================
# headless automation (round-trip test, batch use)
# ======================================================================

def automate(manifest: dict, spec: dict):
    import numpy as np

    action = spec.get("action", "render")
    if action == "cancel":          # behave like a user closing the window without returning
        return
    if action == "fail":            # deliberate crash (tests the error path)
        raise RuntimeError("deliberate failure requested by the automation spec")
    if action == "abort":           # hard crash without a traceback (like a Qt abort)
        os.abort()
    x, fs = load_audio(manifest["input_file"])
    states, tl = presets.build(spec.get("preset", "narrow_passage"))
    cache = ResponseCache()
    for st in states:
        st.sim = SimSettings(spec.get("quality", "Draft"), ir_length=spec.get("ir_length"))
        st.sim.audio_fs = fs
        r = simulate(st.geometry, st.sim, store_frames=False)
        resp = build_response(r, st.current_key(), st.sim.c)
        cache.put(resp)
        st.response_key = resp.key
    out_set = RenderSettings.from_dict(spec.get("render", {}))
    target = spec.get("target", "mix_stereo")
    src = praat_name(manifest.get("source_name", "Source"))
    outs = []
    y, info, text, _used = render_main(x, fs, {s.id: s for s in states}, cache, tl or Timeline(),
                                       tl is not None and spec.get("use_timeline", True), states[0],
                                       out_set, target)
    outs.append(("render", f"{src}_acoustic_morphology", y, fs, text))
    if spec.get("export_irs", True):
        for k, st in enumerate(states):
            r = cache.get(st.response_key)
            for m in st.geometry.mics:
                if m.id in r.mics:
                    outs.append(("ir", f"Acoustic_IR_{chr(65 + k)}_{m.name}", r.mics[m.id].ir[:, None], r.fs,
                                 f"modelled-band IR, state {st.name}, mic {m.name}, <= {r.f_valid:.0f} Hz"))
    write_outputs(manifest, outs, {"mode": "automate", "spec": spec, "peak": info.get("peak")})


# ======================================================================
# GUI
# ======================================================================

def run_gui(manifest: dict | None, project_path: str | None = None, scenario_out: str | None = None):
    import numpy as np
    from PySide6 import QtCore, QtGui, QtWidgets
    import pyqtgraph as pg


    WORKFLOWS = {
        "A": ("A  Resonance Sculpting",
              "Design one geometry and use its response as a resonant filter.  Edit, Compute, audition "
              "(Source & Audition), then Render."),
        "B": ("B  Acoustic Morphing",
              "Build several states, place them on the Timeline and render the evolving transformation "
              "(Mode 1: output morphing; Geometry morph = Mode 2)."),
        "C": ("C  Moving Listener",
              "Keep the source and geometry; store states that differ only in microphone positions "
              "('New listener state'), then sequence them on the Timeline.  Each position is simulated."),
        "D": ("D  Resonant Counterpoint",
              "Use several microphones as related layers: render the stereo mix or export every "
              "microphone as its own layer (Render tab, 'Export microphone layers')."),
        "E": ("E  Spectral Architecture",
              "Design contrasting geometries and compare their measured responses (Compare tab): "
              "spectra, differences, resonances and levels."),
    }

    class MainWindow(QtWidgets.QMainWindow):
        def __init__(self):
            super().__init__()
            self.manifest = manifest
            self.setWindowTitle(f"{APP_NAME} {APP_VERSION}")
            self.resize(1500, 950)
            self.project = projmod.Project()
            self.cache = ResponseCache()
            self.project_path = None
            self.x = None
            self.fs = 48000
            self.src_name = "Source"
            self.player = Player(self)
            self.runner = TaskRunner(self)
            self.prev_runner = TaskRunner(self)       # previews: separate worker, the GUI never blocks
            self._main_cache = None                   # (signature, y, info, desc, used) of render_main
            self.undo_group = QtGui.QUndoGroup(self)
            self.stacks = {}
            self.last_render = None
            self.render_dirty = True
            self.returned = False
            self.queue = []
            self._build_ui()
            self.runner.busy_changed.connect(self._busy)
            # initial content
            if manifest:
                try:
                    self.load_source(manifest["input_file"], manifest.get("source_name"))
                except Exception as e:
                    QtWidgets.QMessageBox.critical(self, APP_NAME, str(e))
            self.load_preset("narrow_passage", replace=True)
            self.set_workflow("A")
            self.statusBar().showMessage("Ready.  Draw the space, press Compute, then audition and render.")

        # ------------------------------------------------------------ UI
        def _build_ui(self):
            tb = self.addToolBar("Main")
            tb.setMovable(False)
            tb.setIconSize(QtCore.QSize(16, 16))
            self.a_open = tb.addAction("Open project", self.open_project)
            self.a_save = tb.addAction("Save project", self.save_project)
            tb.addSeparator()
            pm = QtWidgets.QMenu(self)
            for key in presets.preset_keys():
                info = presets.PRESETS[key]
                a = pm.addAction(info["name"])
                a.setToolTip(info["description"] + "\n\nTendency: " + info["tendencies"])
                a.triggered.connect(lambda _=False, k=key: self.load_preset(k))
            pm.setToolTipsVisible(True)
            pm.addSeparator()
            pm.addAction("Reset preset (current state)", self.reset_preset)
            pb = QtWidgets.QToolButton(); pb.setText("Presets"); pb.setMenu(pm)
            pb.setPopupMode(QtWidgets.QToolButton.InstantPopup)
            tb.addWidget(pb)
            tb.addSeparator()
            tb.addWidget(QtWidgets.QLabel(" Quality "))
            self.quality = QtWidgets.QComboBox()
            for q, d in QUALITIES.items():
                self.quality.addItem(q)
            self.quality.setToolTip("Draft: 3 cm grid, ~1.1 kHz modelled band, seconds.\n"
                                    "Standard: 1.5 cm, ~2.4 kHz, ~10-30 s.\n"
                                    "High Resolution: 0.75 cm, ~4.8 kHz, a few minutes.\n"
                                    "The exact band and cost for the current room are shown in the status bar.")
            tb.addWidget(self.quality)
            tb.addWidget(QtWidgets.QLabel(" length "))
            self.irlen = QtWidgets.QDoubleSpinBox(); self.irlen.setRange(0.05, 6.0); self.irlen.setDecimals(2)
            self.irlen.setSingleStep(0.1); self.irlen.setSuffix(" s")
            self.irlen.setToolTip("Simulated response length (cost grows linearly).  Responses still "
                                  "ringing at the end are faded and flagged.")
            tb.addWidget(self.irlen)
            self.c25 = QtWidgets.QCheckBox("2.5-D")
            self.c25.setChecked(True)
            self.c25.setToolTip("2.5-D correction: turns the 2-D line-source response (+3 dB/oct, 1/sqrt(t) "
                                "wake) into a compact, flat point-source-like arrival.  Exact for the far-field "
                                "direct sound; an approximation for reflections.  Off = native 2-D response.")
            tb.addWidget(self.c25)
            self.a_compute = tb.addAction("Compute", self.compute_current)
            self.a_compute.setToolTip("Simulate the current state (background thread; the editor stays live).")
            self.a_cancel = tb.addAction("Cancel", self.runner.cancel)
            self.a_cancel.setEnabled(False)
            tb.addSeparator()
            self.a_preview = tb.addAction("Preview", lambda: self.play_processed())
            self.a_store = tb.addAction("Store state", self.store_state)
            self.a_render = tb.addAction("Render", self.render)
            self.a_export = tb.addAction("Return to Praat" if self.manifest else "Export...", self.export)
            tb.addSeparator()
            self.undo_act = self.undo_group.createUndoAction(self, "Undo")
            self.undo_act.setShortcut(QtGui.QKeySequence.Undo)
            self.redo_act = self.undo_group.createRedoAction(self, "Redo")
            self.redo_act.setShortcut(QtGui.QKeySequence.Redo)
            tb.addAction(self.undo_act); tb.addAction(self.redo_act)
            tb.addSeparator()
            tb.addWidget(QtWidgets.QLabel(" Workflow "))
            self.workflow = QtWidgets.QComboBox()
            for k, (nm, tip) in WORKFLOWS.items():
                self.workflow.addItem(nm, k)
                self.workflow.setItemData(self.workflow.count() - 1, tip, QtCore.Qt.ToolTipRole)
            self.workflow.currentIndexChanged.connect(lambda i: self.set_workflow(self.workflow.itemData(i)))
            tb.addWidget(self.workflow)
            tb.addAction("Help", self.show_help)

            # ---- left: editor
            left = QtWidgets.QWidget()
            lv = QtWidgets.QVBoxLayout(left); lv.setContentsMargins(2, 2, 2, 2)
            tools = QtWidgets.QHBoxLayout()
            self.tool_group = QtWidgets.QButtonGroup(self)
            labels = {"select": "Select", "wall": "Wall", "rect": "Obstacle", "opening": "Opening",
                      "source": "Source", "mic": "Mic", "pan": "Pan"}
            for t in TOOLS:
                b = QtWidgets.QToolButton(); b.setText(labels[t]); b.setCheckable(True)
                b.setToolTip(TOOL_TIPS[t])
                self.tool_group.addButton(b)
                b.clicked.connect(lambda _=False, t=t: self.editor.set_tool(t))
                tools.addWidget(b)
                if t == "select":
                    b.setChecked(True)
            tools.addStretch(1)
            lv.addLayout(tools)
            opts = QtWidgets.QHBoxLayout()
            self.snap = QtWidgets.QCheckBox("snap"); self.snap.setChecked(True)
            self.gstep = QtWidgets.QComboBox(); self.gstep.addItems(["1 cm", "2 cm", "5 cm", "10 cm", "25 cm"])
            self.gstep.setCurrentIndex(2)
            self.gshow = QtWidgets.QCheckBox("grid"); self.gshow.setChecked(True)
            self.rshow = QtWidgets.QCheckBox("sim. cells")
            self.rshow.setToolTip("Overlay the simulation grid's solid cells for the chosen quality - shows "
                                  "how walls and openings are staircased.")
            for w in (self.snap, self.gstep, self.gshow, self.rshow):
                opts.addWidget(w)
            opts.addStretch(1)
            for txt, fn in (("Fit", lambda: self.editor.fit()), ("Delete", lambda: self.editor.delete_selection()),
                            ("Clear", self.clear_geometry), ("Load geom.", self.load_geometry),
                            ("Save geom.", self.save_geometry)):
                b = QtWidgets.QToolButton(); b.setText(txt); b.clicked.connect(fn); opts.addWidget(b)
            lv.addLayout(opts)
            self.editor = GeometryEditor()
            lv.addWidget(self.editor, 1)
            self.props = PropertiesPanel(self.editor)
            sa = QtWidgets.QScrollArea(); sa.setWidget(self.props); sa.setWidgetResizable(True)
            sa.setMaximumHeight(200)
            lv.addWidget(sa)
            self.snap.toggled.connect(lambda b: setattr(self.editor, "snap", b))
            self.gstep.currentIndexChanged.connect(
                lambda i: (setattr(self.editor, "grid_step", [0.01, 0.02, 0.05, 0.1, 0.25][i]),
                           self.editor.viewport().update()))
            self.gshow.toggled.connect(lambda b: (setattr(self.editor, "show_grid", b), self.editor.viewport().update()))
            self.rshow.toggled.connect(self._raster_overlay)
            self.editor.changed.connect(self.geometry_changed)
            self.editor.status.connect(lambda s: self.statusBar().showMessage(s, 4000))

            # ---- right: analysis
            self.rtabs = QtWidgets.QTabWidget()
            self.fp = FingerprintPanel()
            self.wave = WavefieldPanel()
            self.meas = MeasurementsPanel()
            self.cmp = ComparePanel()
            self.rtabs.addTab(self.fp, "Acoustic fingerprint")
            self.rtabs.addTab(self.wave, "Wavefield")
            self.rtabs.addTab(self.meas, "Measurements")
            self.rtabs.addTab(self.cmp, "Compare states")

            # ---- bottom
            self.btabs = QtWidgets.QTabWidget()
            self.btabs.addTab(self._states_panel(), "States")
            self.tlp = TimelinePanel()
            self.btabs.addTab(self.tlp, "Timeline")
            self.btabs.addTab(self._source_panel(), "Source && audition")
            self.btabs.addTab(self._render_panel(), "Render")
            self.tlp.add_requested.connect(self.add_keyframe)
            self.tlp.morph_requested.connect(self.geometry_morph)
            self.tlp.preview_requested.connect(lambda: self.play_processed(timeline=True))
            self.tlp.stop_requested.connect(self.player.stop)
            self.tlp.view.changed.connect(self._timeline_changed)
            self.tlp.view.undo_cb = self._timeline_undoable

            top = QtWidgets.QSplitter(QtCore.Qt.Horizontal)
            top.addWidget(left); top.addWidget(self.rtabs)
            top.setSizes([760, 740])
            main = QtWidgets.QSplitter(QtCore.Qt.Vertical)
            main.addWidget(top); main.addWidget(self.btabs)
            main.setSizes([640, 300])
            wrap = QtWidgets.QWidget()
            wv = QtWidgets.QVBoxLayout(wrap); wv.setContentsMargins(4, 2, 4, 2)
            self.hint = QtWidgets.QLabel(); self.hint.setObjectName("hint"); self.hint.setWordWrap(True)
            wv.addWidget(self.hint)
            wv.addWidget(main, 1)
            self.setCentralWidget(wrap)
            self.plan_lab = QtWidgets.QLabel()
            self.prog = QtWidgets.QProgressBar(); self.prog.setMaximumWidth(220); self.prog.setVisible(False)
            self.statusBar().addPermanentWidget(self.plan_lab)
            self.statusBar().addPermanentWidget(self.prog)
            self.quality.currentIndexChanged.connect(self.sim_settings_changed)
            self.irlen.valueChanged.connect(self.sim_settings_changed)
            self.c25.toggled.connect(self.sim_settings_changed)
            self.play_timer = QtCore.QTimer(self); self.play_timer.setInterval(50)
            self.play_timer.timeout.connect(self._playhead)
            self.player.started.connect(self.play_timer.start)
            self.player.stopped.connect(self._play_stopped)

        def _states_panel(self):
            w = QtWidgets.QWidget(); h = QtWidgets.QHBoxLayout(w); h.setContentsMargins(2, 2, 2, 2)
            self.table = QtWidgets.QTableWidget(0, 6)
            self.table.setHorizontalHeaderLabels(["State", "Response", "Grid / band", "Microphones",
                                                  "Render (wet gain, high band)", "Notes"])
            self.table.horizontalHeader().setStretchLastSection(True)
            self.table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
            self.table.setSelectionMode(QtWidgets.QAbstractItemView.SingleSelection)
            self.table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
            self.table.verticalHeader().setVisible(False)
            self.table.itemSelectionChanged.connect(self._table_select)
            h.addWidget(self.table, 1)
            col = QtWidgets.QVBoxLayout()
            for txt, fn, tip in (
                    ("Store as new", self.store_state, "Store a copy of the current state under a new name."),
                    ("Duplicate", lambda: self.store_state(ask=False), "Copy the current state."),
                    ("New listener state", self.new_listener, "Moving Listener: copy with the same geometry "
                                                              "and source - then move the microphones."),
                    ("Rename", self.rename_state, ""),
                    ("Delete", self.delete_state, ""),
                    ("Recompute", self.compute_current, "Compute the current state's response."),
                    ("Compute all outdated", self.compute_all, "Compute every state without an up-to-date "
                                                                "response, one after the other."),
                    ("Compare", lambda: self.rtabs.setCurrentWidget(self.cmp), "")):
                b = QtWidgets.QPushButton(txt); b.clicked.connect(fn)
                if tip:
                    b.setToolTip(tip)
                col.addWidget(b)
            col.addStretch(1)
            h.addLayout(col)
            return w

        def _source_panel(self):
            w = QtWidgets.QWidget(); v = QtWidgets.QVBoxLayout(w); v.setContentsMargins(2, 2, 2, 2)
            row = QtWidgets.QHBoxLayout()
            self.src_lab = QtWidgets.QLabel("No source loaded.")
            row.addWidget(self.src_lab, 1)
            if not self.manifest:
                b = QtWidgets.QPushButton("Load source..."); b.clicked.connect(self.load_source_dialog)
                row.addWidget(b)
            v.addLayout(row)
            self.wplot = pg.PlotWidget()
            self.wplot.setMaximumHeight(120); self.wplot.hideAxis("left")
            self.wplot.setMouseEnabled(x=False, y=False)
            self.region = pg.LinearRegionItem(values=(0, 2), brush=pg.mkBrush(200, 118, 43, 40))
            self.region.setToolTip("Listening region (drag the edges).")
            self.phead = pg.InfiniteLine(0, pen=pg.mkPen("#d02020", width=1.5))
            v.addWidget(self.wplot)
            row = QtWidgets.QHBoxLayout()
            for txt, fn in (("Play original", self.play_original), ("Play processed", self.play_processed),
                            ("A/B", self.ab_switch), ("Preview composition", lambda: self.play_processed(timeline=True)),
                            ("Stop", self.player.stop)):
                b = QtWidgets.QPushButton(txt); b.clicked.connect(fn); row.addWidget(b)
            self.bypass = QtWidgets.QCheckBox("Bypass")
            self.bypass.setToolTip("Processed playback returns the unprocessed source.")
            self.matched = QtWidgets.QCheckBox("Matched level"); self.matched.setChecked(True)
            self.matched.setToolTip("Scale processed audition to the RMS of the original region, so A/B "
                                    "compares timbre rather than loudness (renders are not affected).")
            row.addWidget(self.bypass); row.addWidget(self.matched)
            row.addStretch(1)
            self.audio_lab = QtWidgets.QLabel()
            row.addWidget(self.audio_lab)
            v.addLayout(row)
            self.audio_lab.setText(f"audio: {self.player.backend}" if self.player.available
                                   else f"audio playback unavailable ({self.player.reason}) - renders still work")
            self._ab = "processed"
            return w

        def _render_panel(self):
            w = QtWidgets.QWidget(); h = QtWidgets.QHBoxLayout(w); h.setContentsMargins(2, 2, 2, 2)
            g1 = QtWidgets.QGroupBox("Current state")
            f1 = QtWidgets.QFormLayout(g1)
            self.wet = spin(-60, 40, 0, 0.5, 1, " dB", "Gain of this state's wet path.  Responses are on the "
                                                     "physical scale (0 dB = 2-D free field at 1 m), so closed "
                                                     "rooms are louder than the free field.")
            self.band = QtWidgets.QComboBox()
            for s, lab in (("preserve", "Preserve (dry, not simulated)"), ("attenuate", "Attenuate (remove)"),
                           ("extend", "Creative extension (not physical)")):
                self.band.addItem(lab, s)
            self.band.setToolTip("Above the modelled band the simulation says nothing.  Preserve: pass the dry "
                                 "high band, delayed to the direct arrival and level-matched (not simulated).  "
                                 "Attenuate: band-limit the wet signal.  Creative: seeded noise shaped by the top "
                                 "modelled octave's decay - an artistic extension, not physics.")
            f1.addRow("Wet gain", self.wet); f1.addRow("Above the band", self.band)
            self.wet.valueChanged.connect(self._state_render_changed)
            self.band.currentIndexChanged.connect(self._state_render_changed)
            h.addWidget(g1)
            g2 = QtWidgets.QGroupBox("Output")
            f2 = QtWidgets.QFormLayout(g2)
            self.mix = QtWidgets.QSlider(QtCore.Qt.Horizontal); self.mix.setRange(0, 100); self.mix.setValue(100)
            self.mix_lab = QtWidgets.QLabel("100 % wet")
            mrow = QtWidgets.QHBoxLayout(); mrow.addWidget(self.mix, 1); mrow.addWidget(self.mix_lab)
            self.trim = spin(-60, 24, 0, 0.5, 1, " dB")
            self.protect = QtWidgets.QCheckBox("peak protection")
            self.protect.setToolTip("Scale the whole render down so its peak stays at the ceiling (no limiter).")
            self.ceiling = spin(-24, 0, -1, 0.5, 1, " dBFS")
            self.duration = QtWidgets.QComboBox()
            self.duration.addItem("Preserve source duration", "preserve")
            self.duration.addItem("Include reverberation tail", "tail")
            self.stereo = QtWidgets.QComboBox()
            for s, lab in (("mono", "Stereo source: mix to mono"), ("per_channel", "Stereo source: each channel"),
                           ("left", "Stereo source: left only"), ("right", "Stereo source: right only")):
                self.stereo.addItem(lab, s)
            self.target = QtWidgets.QComboBox()
            for s, lab in (("mix_stereo", "Stereo mix (mic pans)"), ("mix_mono", "Mono mix"), ("mic:0", "Microphone 1"),
                           ("mic:1", "Microphone 2"), ("mic:2", "Microphone 3"), ("mic:3", "Microphone 4")):
                self.target.addItem(lab, s)
            self.use_tl = QtWidgets.QCheckBox("Render the timeline (if it has keyframes)")
            self.use_tl.setChecked(True)
            self.exp_irs = QtWidgets.QCheckBox("Export impulse responses")
            self.exp_layers = QtWidgets.QCheckBox("Export microphone layers (current state)")
            f2.addRow("Dry / wet", mrow); f2.addRow("Output trim", self.trim)
            prow = QtWidgets.QHBoxLayout(); prow.addWidget(self.protect); prow.addWidget(self.ceiling)
            f2.addRow("", prow)
            f2.addRow("Duration", self.duration); f2.addRow("Channels", self.stereo)
            f2.addRow("Main output", self.target); f2.addRow("", self.use_tl)
            f2.addRow("", self.exp_irs); f2.addRow("", self.exp_layers)
            for wd in (self.trim, self.ceiling):
                wd.valueChanged.connect(self._output_changed)
            for wd in (self.protect, self.use_tl, self.exp_irs, self.exp_layers):
                wd.toggled.connect(self._output_changed)
            for wd in (self.duration, self.stereo, self.target):
                wd.currentIndexChanged.connect(self._output_changed)
            self.mix.valueChanged.connect(self._output_changed)
            h.addWidget(g2, 1)
            g3 = QtWidgets.QGroupBox("Result")
            v3 = QtWidgets.QVBoxLayout(g3)
            self.render_info = QtWidgets.QTextBrowser()
            v3.addWidget(self.render_info, 1)
            r = QtWidgets.QHBoxLayout()
            b = QtWidgets.QPushButton("Render"); b.clicked.connect(self.render); r.addWidget(b)
            b = QtWidgets.QPushButton("Play render"); b.clicked.connect(self.play_render); r.addWidget(b)
            b = QtWidgets.QPushButton("Return to Praat" if self.manifest else "Export WAVs...")
            b.clicked.connect(self.export); r.addWidget(b)
            v3.addLayout(r)
            h.addWidget(g3, 1)
            return w

        # ------------------------------------------------------ state mgmt
        def cur(self) -> AcousticState:
            return self.project.state(self.project.current_state)

        def stack_for(self, st):
            if st.id not in self.stacks:
                s = QtGui.QUndoStack(self)
                self.undo_group.addStack(s)
                self.stacks[st.id] = s
            return self.stacks[st.id]

        def set_current(self, sid):
            self.project.current_state = sid
            st = self.cur()
            st.sim.audio_fs = self.fs
            stack = self.stack_for(st)
            self.undo_group.setActiveStack(stack)
            self.editor.set_geometry(st.geometry, stack)
            for wd, val in ((self.quality, st.sim.quality),):
                wd.blockSignals(True); wd.setCurrentText(val); wd.blockSignals(False)
            self.irlen.blockSignals(True); self.irlen.setValue(st.sim.resolved_ir_length()); self.irlen.blockSignals(False)
            self.c25.blockSignals(True); self.c25.setChecked(st.correction_25d); self.c25.blockSignals(False)
            self.wet.blockSignals(True); self.wet.setValue(st.render.wet_gain_db); self.wet.blockSignals(False)
            self.band.blockSignals(True)
            self.band.setCurrentIndex([self.band.itemData(i) for i in range(self.band.count())].index(st.render.band_strategy))
            self.band.blockSignals(False)
            self._raster_overlay(self.rshow.isChecked())
            self.refresh_all()

        def refresh_all(self):
            self.refresh_table()
            self.refresh_response()
            self.update_plan()
            self.tlp.view.set_timeline(self.project.timeline, self.project.states)
            self.tlp.sync()
            self.cmp.set_states(self.project.states, self.cache)

        def refresh_table(self):
            t = self.table
            t.blockSignals(True)
            t.setRowCount(len(self.project.states))
            for r, st in enumerate(self.project.states):
                stat = st.status(self.cache)
                lab = {"computed": "computed", "outdated": "OUTDATED - geometry/settings changed",
                       "none": "not computed"}[stat]
                items = [st.name + ("  (editing)" if st.id == self.project.current_state else ""), lab]
                if stat == "computed":
                    resp = self.cache.get(st.response_key)
                    items.append(f"{resp.dx * 100:.2f} cm, <= {resp.f_valid:.0f} Hz, {resp.ir_length:.2f} s")
                else:
                    items.append(f"{st.sim.quality}")
                items.append(", ".join(m.name + ("" if m.enabled else " (off)") for m in st.geometry.mics))
                items.append(f"{st.render.wet_gain_db:+.1f} dB, {st.render.band_strategy}")
                items.append(st.notes or presets.PRESETS.get(st.preset.rpartition('-')[0], {}).get("name", ""))
                for c, txt in enumerate(items):
                    it = QtWidgets.QTableWidgetItem(txt)
                    if c == 1:
                        it.setForeground(QtGui.QColor({"computed": "#2e7d32", "outdated": "#b45309",
                                                       "none": "#777"}[stat]))
                    if st.id == self.project.current_state:
                        f = it.font(); f.setBold(True); it.setFont(f)
                    t.setItem(r, c, it)
                if st.id == self.project.current_state:
                    t.selectRow(r)
            t.resizeColumnsToContents()
            t.blockSignals(False)

        def refresh_response(self):
            st = self.cur()
            stat = st.status(self.cache)
            resp = self.cache.get(st.response_key) if (st.response_key and self.cache.has(st.response_key)) else None
            if stat == "computed":
                self.fp.set_status(f"Response of '{st.name}' is up to date.  {resp.plan_text}")
            elif stat == "outdated":
                self.fp.set_status(f"OUTDATED: '{st.name}' changed after its response was computed.  The curves "
                                   "below belong to the PREVIOUS geometry/settings and will not be used for "
                                   "rendering.  Press Compute.", warn=True)
            else:
                self.fp.set_status(f"'{st.name}' has no response yet - press Compute.")
            self.fp.set_response(resp, st.geometry if resp else st.geometry)
            self.meas.show_response(resp, st.geometry, st.name, stat)
            self.wave.set_response(resp, st.geometry)
            self.render_dirty = True

        def update_plan(self):
            st = self.cur()
            try:
                plan = make_plan(st.geometry, st.sim)
                r = rasterize(st.geometry, plan.dx)
                rep = check(st.geometry, r)
                msg = plan.describe()
                if rep.errors:
                    msg = "Cannot compute: " + rep.errors[0]
                elif rep.warnings:
                    msg += "   |  " + rep.warnings[0]
                self.plan_lab.setText(msg)
                self.plan_lab.setToolTip("\n".join(rep.errors + rep.warnings) or plan.describe())
            except Exception as e:
                self.plan_lab.setText(f"Invalid settings: {e}")

        def _table_select(self):
            rows = self.table.selectionModel().selectedRows()
            if rows:
                st = self.project.states[rows[0].row()]
                if st.id != self.project.current_state:
                    self.set_current(st.id)

        def geometry_changed(self):
            self.refresh_table()
            self.refresh_response()
            self.update_plan()
            self.cmp.set_states(self.project.states, self.cache)

        def sim_settings_changed(self, *_):
            st = self.cur()
            st.sim.quality = self.quality.currentText()
            st.sim.ir_length = self.irlen.value()
            st.correction_25d = self.c25.isChecked()
            st.sim.audio_fs = self.fs
            self._raster_overlay(self.rshow.isChecked())
            self.geometry_changed()

        def _raster_overlay(self, on):
            self.editor.set_raster(self.cur().sim.resolved_dx() if on else None)

        def _state_render_changed(self, *_):
            st = self.cur()
            st.render.wet_gain_db = self.wet.value()
            st.render.band_strategy = self.band.currentData()
            self.render_dirty = True
            self.refresh_table()

        def _output_changed(self, *_):
            r = self.project.render
            r.mix = self.mix.value() / 100
            self.mix_lab.setText(f"{self.mix.value()} % wet")
            r.trim_db = self.trim.value()
            r.peak_protect = self.protect.isChecked()
            r.ceiling_db = self.ceiling.value()
            r.duration = self.duration.currentData()
            r.stereo_policy = self.stereo.currentData()
            o = self.project.output
            o.target = self.target.currentData()
            o.use_timeline = self.use_tl.isChecked()
            o.export_irs = self.exp_irs.isChecked()
            o.export_layers = self.exp_layers.isChecked()
            self.render_dirty = True

        def _sync_output_widgets(self):
            r, o = self.project.render, self.project.output
            ws = (self.mix, self.trim, self.protect, self.ceiling, self.duration, self.stereo, self.target,
                  self.use_tl, self.exp_irs, self.exp_layers)
            for wd in ws:
                wd.blockSignals(True)
            self.mix.setValue(int(round(r.mix * 100))); self.mix_lab.setText(f"{self.mix.value()} % wet")
            self.trim.setValue(r.trim_db); self.protect.setChecked(r.peak_protect); self.ceiling.setValue(r.ceiling_db)
            self.duration.setCurrentIndex(0 if r.duration == "preserve" else 1)
            self.stereo.setCurrentIndex(STEREO_POLICIES.index(r.stereo_policy))
            self.target.setCurrentIndex([self.target.itemData(i) for i in range(self.target.count())].index(o.target))
            self.use_tl.setChecked(o.use_timeline); self.exp_irs.setChecked(o.export_irs)
            self.exp_layers.setChecked(o.export_layers)
            for wd in ws:
                wd.blockSignals(False)

        def store_state(self, ask=True):
            st = self.cur()
            name = st.name + " copy"
            if ask:
                name, ok = QtWidgets.QInputDialog.getText(self, "Store state", "Name of the stored state:",
                                                          text=st.name + " B")
                if not ok or not name.strip():
                    return
            new = st.duplicate(name.strip())
            self.project.states.append(new)
            self.refresh_all()
            self.statusBar().showMessage(f"Stored '{new.name}' (its response is shared while the geometry "
                                         "stays identical).", 5000)

        def new_listener(self):
            st = self.cur()
            k = sum(1 for s in self.project.states if s.name.startswith(st.name + " - listener")) + 1
            new = st.duplicate(f"{st.name} - listener {k}")
            new.notes = "Moving Listener: move the microphones; source and walls unchanged."
            self.project.states.append(new)
            self.set_current(new.id)
            self.set_workflow("C")

        def rename_state(self):
            st = self.cur()
            name, ok = QtWidgets.QInputDialog.getText(self, "Rename state", "Name:", text=st.name)
            if ok and name.strip():
                st.name = name.strip()[:80]
                self.refresh_all()

        def delete_state(self):
            st = self.cur()
            if len(self.project.states) <= 1:
                QtWidgets.QMessageBox.information(self, APP_NAME, "Keep at least one state.")
                return
            used = any(k.state_id == st.id for k in self.project.timeline.keyframes)
            msg = f"Delete state '{st.name}'?" + ("\nIts keyframes will be removed from the timeline." if used else "")
            if QtWidgets.QMessageBox.question(self, APP_NAME, msg) != QtWidgets.QMessageBox.Yes:
                return
            self.project.timeline.keyframes = [k for k in self.project.timeline.keyframes if k.state_id != st.id]
            self.project.states = [s for s in self.project.states if s.id != st.id]
            self.set_current(self.project.states[0].id)

        def load_preset(self, key, replace=False):
            states, tl = presets.build(key)
            for s in states:
                s.sim.quality = self.quality.currentText() if hasattr(self, "quality") else "Standard"
                s.sim.audio_fs = self.fs
            if replace or not self.project.states:
                self.project.states = states
                self.project.timeline = tl or Timeline()
            else:
                self.project.states.extend(states)
                if tl is not None and not self.project.timeline.keyframes:
                    self.project.timeline = tl
            self._fit_timeline_to_source(tl)
            self.set_current(states[0].id)
            info = presets.PRESETS[key]
            self.statusBar().showMessage(f"{info['name']}: {info['tendencies']}", 12000)

        def _fit_timeline_to_source(self, tl):
            """Spread a preset timeline over the source duration."""
            if tl is None or self.x is None or not tl.keyframes:
                return
            dur = self.x.shape[0] / self.fs
            last = max(k.time for k in tl.keyframes)
            if last > 0:
                f = dur / last * 0.95
                for k in tl.keyframes:
                    k.time *= f
                    k.transition *= f

        def reset_preset(self):
            st = self.cur()
            g = presets.rebuild_state_geometry(st.preset) if st.preset else None
            if g is None:
                QtWidgets.QMessageBox.information(self, APP_NAME, "This state did not come from a preset.")
                return
            self.editor.edit(lambda: self.editor.apply_snapshot(st.geometry, g.to_dict()), "Reset preset")

        def clear_geometry(self):
            if QtWidgets.QMessageBox.question(self, APP_NAME, "Remove all walls, obstacles and openings of "
                                              "this state?  (Undo restores them.)") == QtWidgets.QMessageBox.Yes:
                self.editor.clear_elements()

        def set_workflow(self, k):
            self.project.workflow = k
            i = list(WORKFLOWS).index(k)
            if self.workflow.currentIndex() != i:
                self.workflow.blockSignals(True); self.workflow.setCurrentIndex(i); self.workflow.blockSignals(False)
            nm, tip = WORKFLOWS[k]
            self.hint.setText(f"<b>{nm}</b> - {tip}")
            if k == "B":
                self.btabs.setCurrentWidget(self.tlp)
            elif k == "C":
                self.btabs.setCurrentIndex(0)
            elif k == "D":
                self.btabs.setCurrentIndex(3)
                self.exp_layers.setChecked(True)
            elif k == "E":
                self.rtabs.setCurrentWidget(self.cmp)
            else:
                self.btabs.setCurrentIndex(2)

        # -------------------------------------------------------- compute
        def compute_current(self):
            self._compute([self.cur().id])

        def compute_all(self):
            ids = [s.id for s in self.project.states if s.status(self.cache) != "computed"]
            if not ids:
                self.statusBar().showMessage("All states are up to date.", 4000)
                return
            self._compute(ids)

        def _compute(self, ids):
            if self.runner.busy:
                return
            self.queue = list(ids)
            self._next_compute()

        def _timeline_ready(self, resume, what):
            """True if every timeline state has an up-to-date response.  If
            not, offer to compute the missing ones and resume `resume` (the
            render or preview) automatically when they are done."""
            states = self.project.states_by_id()
            missing = []
            for k in self.project.timeline.sorted():
                st = states.get(k.state_id)
                if st is not None and st.status(self.cache) != "computed" and st.id not in missing:
                    missing.append(st.id)
            if not missing:
                return True
            if self.runner.busy:
                self.statusBar().showMessage("A computation is running - try again when it has finished.", 5000)
                return False
            names = "\n".join("  - " + states[i].name for i in missing)
            r = QtWidgets.QMessageBox.question(
                self, APP_NAME, f"These timeline states have no up-to-date response yet:\n{names}\n\n"
                f"Compute them now (each at its own quality setting) and then {what} automatically?")
            if r == QtWidgets.QMessageBox.Yes:
                self._after_compute = resume
                self._compute(missing)
            return False

        def _next_compute(self):
            if not self.queue:
                cb, self._after_compute = getattr(self, "_after_compute", None), None
                if cb is not None:
                    QtCore.QTimer.singleShot(0, cb)    # continue the render / preview that asked
                return
            sid = self.queue.pop(0)
            st = self.project.state(sid)
            if st is None:
                return self._next_compute()
            st.sim.audio_fs = self.fs
            key = st.current_key()
            if self.cache.has(key):              # identical geometry already computed
                st.response_key = key
                self.refresh_all()
                return self._next_compute()
            geom = st.geometry.copy()            # snapshot: edits during the run cannot race
            sim = SimSettings.from_dict(st.sim.to_dict())
            sim.audio_fs = self.fs
            c25 = st.correction_25d
            name = st.name

            def job(progress, cancel):
                r = simulate(geom, sim, progress=progress, cancel=cancel)
                return build_response(r, key, sim.c, correction_25d=c25)

            self._job_state = (sid, key, name)
            self.runner.start(Worker(job, f"Computing {name}"), self._compute_done, self._compute_failed,
                              lambda f, m: self._progress(f, f"Computing '{name}': {m}"))

        def _compute_done(self, resp):
            sid, key, name = self._job_state
            self.cache.put(resp)
            st = self.project.state(sid)
            if st is not None:
                if st.current_key() == key:
                    st.response_key = key
                    msg = f"'{name}' computed in {resp.elapsed:.1f} s."
                else:
                    msg = (f"'{name}' changed during the computation: the result was kept for the old "
                           "geometry, the state stays outdated.")
                self.statusBar().showMessage(msg, 8000)
            self.refresh_all()
            if resp.warnings:
                self.rtabs.setCurrentWidget(self.meas) if any("decaying" in w for w in resp.warnings) else None
            self._next_compute()

        def _compute_failed(self, msg, cancelled):
            self.queue = []
            self._after_compute = None                # do not render with missing states
            if cancelled:
                self.statusBar().showMessage("Computation cancelled - previous responses unchanged.", 6000)
            else:
                QtWidgets.QMessageBox.warning(self, APP_NAME, f"The simulation did not produce a response:\n\n{msg}")
            self.refresh_all()

        def _progress(self, f, m):
            self.prog.setVisible(True)
            self.prog.setValue(int(100 * f))
            self.statusBar().showMessage(m)

        def _busy(self, b):
            self.a_cancel.setEnabled(b)
            self.a_compute.setEnabled(not b)
            self.a_render.setEnabled(not b)
            if not b:
                self.prog.setVisible(False)

        # ---------------------------------------------------------- source
        def load_source(self, path, name=None):
            x, fs = load_audio(path)
            if x.shape[0] / fs > 1800:
                raise ValueError("Sources longer than 30 minutes are not supported.")
            self.x, self.fs = x, fs
            self.src_name = name or os.path.splitext(os.path.basename(path))[0]
            self.project.source = projmod.SourceRef(os.path.abspath(path), fs, x.shape[1], x.shape[0] / fs,
                                                    self.src_name)
            for st in self.project.states:
                st.sim.audio_fs = fs
            self.src_lab.setText(f"<b>{html.escape(self.src_name)}</b>  {x.shape[0] / fs:.2f} s, {fs} Hz, "
                                 f"{'stereo' if x.shape[1] == 2 else 'mono'}"
                                 + (f", peak {20 * math.log10(np.abs(x).max()):.1f} dBFS" if np.abs(x).max() > 0
                                    else ", SILENT"))
            self.wplot.clear()
            mono = x.mean(axis=1)
            step = max(1, len(mono) // 6000)
            t = np.arange(len(mono))[::step] / fs
            self.wplot.plot(t, mono[::step], pen=pg.mkPen("#7d7d76", width=1))
            self.wplot.addItem(self.region); self.wplot.addItem(self.phead)
            dur = x.shape[0] / fs
            self.region.setBounds((0, dur))
            self.region.setRegion((0, min(dur, 6.0)))
            self.tlp.view.set_source(x, fs)
            self._main_cache = None
            self.render_dirty = True
            if self.project.states:
                self.refresh_all()

        def load_source_dialog(self):
            p, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Source audio", "",
                                                         "Audio (*.wav *.aif *.aiff *.flac *.ogg);;All (*)")
            if p:
                try:
                    self.load_source(p)
                except Exception as e:
                    QtWidgets.QMessageBox.warning(self, APP_NAME, str(e))

        def _region(self):
            a, b = self.region.getRegion()
            i0, i1 = int(a * self.fs), int(b * self.fs)
            if i1 - i0 < int(0.01 * self.fs):
                i0, i1 = 0, self.x.shape[0]
            return i0, i1

        def play_original(self, rng=None):
            if self.x is None:
                return
            i0, i1 = rng or self._region()
            self._ab = "original"
            self.player.play(self.x[i0:i1], self.fs, offset=i0 / self.fs)

        # ---- the main output, shared by Preview and Render ----------------
        def _main_args(self, timeline_mode):
            """Snapshot of everything render_main needs (the worker never sees
            live, editable objects)."""
            proj = self.project
            states = {s.id: copy.deepcopy(s) for s in proj.states}
            tl = Timeline.from_dict(proj.timeline.to_dict(), list(states))
            cur = states.get(proj.current_state)
            return (self.x, self.fs, states, self.cache, tl, timeline_mode, cur,
                    RenderSettings.from_dict(proj.render.to_dict()), proj.output.target)

        def _main_sig(self, args):
            x, fs, states, cache, tl, mode, cur, rs, target = args
            return render_signature(x, states, tl, mode, cur, rs, target)

        def _cached_main(self, sig):
            c = self._main_cache
            return c if (c is not None and c[0] == sig) else None

        def play_processed(self, timeline=False, rng=None):
            """Preview = the region of the FULL main render (render_main, the
            same function and settings as Render), computed in a background
            worker and cached; only 'Matched level' (audition only) differs."""
            if self.x is None:
                QtWidgets.QMessageBox.information(self, APP_NAME, "Load a source first.")
                return
            i0, i1 = rng or self._region()
            if self.bypass.isChecked():
                self._ab = "processed"
                self.player.play(self.x[i0:i1], self.fs, offset=i0 / self.fs)
                return
            if timeline and not self.project.timeline.keyframes:
                QtWidgets.QMessageBox.information(self, APP_NAME, "The timeline is empty.")
                return
            if timeline and not self._timeline_ready(lambda: self.play_processed(True, rng), "preview"):
                return
            args = self._main_args(timeline)
            sig = self._main_sig(args)
            hit = self._cached_main(sig)
            if hit is not None:
                self._play_slice(hit[1], i0, i1)
                return
            if self.prev_runner.busy:
                self.statusBar().showMessage("A preview is already being rendered...", 3000)
                return

            def job(progress, cancel):
                return (sig,) + render_main(*args, progress=progress, cancel=cancel)

            def done(r):
                self._main_cache = r
                self.statusBar().showMessage("Preview ready.", 3000)
                self._play_slice(r[1], i0, i1)

            def failed(msg, cancelled):
                if not cancelled:
                    QtWidgets.QMessageBox.information(self, APP_NAME, msg.split("\n")[0].split(": ", 1)[-1])

            self.statusBar().showMessage("Rendering the preview in the background...")
            self.prev_runner.start(Worker(job, "Preview"), done, failed,
                                   lambda f, m: self.statusBar().showMessage(f"Rendering the preview: {m}"))

        def _play_slice(self, y, i0, i1):
            seg = y[i0:i1]
            if self.matched.isChecked():
                seg = match_level(seg, self.x[i0:i1])
            self._ab = "processed"
            self.player.play(seg, self.fs, offset=i0 / self.fs)

        def ab_switch(self):
            """Switch original <-> processed, continuing near the current position."""
            if self.x is None:
                return
            i0, i1 = self._region()
            pos = self.player.position()
            if pos is not None and i0 / self.fs < pos < i1 / self.fs:
                i0 = int(pos * self.fs)
            if self._ab == "processed":
                self.play_original((i0, i1))
            else:
                self.play_processed(rng=(i0, i1))

        def _playhead(self):
            pos = self.player.position()
            if pos is None:
                return
            self.phead.setValue(pos)
            self.tlp.view.playhead = pos
            self.tlp.view.update()

        def _play_stopped(self):
            self.play_timer.stop()
            self.tlp.view.playhead = None
            self.tlp.view.update()

        # -------------------------------------------------------- timeline
        def _timeline_undoable(self, before, after):
            """Timeline edits go onto the active undo stack, so Undo/Redo walk
            back through geometry AND timeline edits in the order they were made."""
            win = self

            class Cmd(QtGui.QUndoCommand):
                def __init__(self):
                    super().__init__("timeline edit")
                    self.first = True

                def _apply(self, d):
                    ids = [s.id for s in win.project.states]
                    d = dict(d, keyframes=[k for k in d["keyframes"] if k["state_id"] in ids])
                    win.project.timeline = Timeline.from_dict(d, ids)
                    win.tlp.view.set_timeline(win.project.timeline, win.project.states)
                    win.tlp.sync()
                    win.render_dirty = True

                def redo(self):
                    if self.first:          # the edit itself already happened
                        self.first = False
                        return
                    self._apply(after)

                def undo(self):
                    self._apply(before)

            stack = self.undo_group.activeStack()
            if stack is not None:
                stack.push(Cmd())

        def add_keyframe(self, t):
            before = self.project.timeline.to_dict()
            kfs = self.project.timeline.keyframes
            tr = self.tlp.trans.value() if kfs else 0.0
            am = self.tlp.amount.value() / 100.0 if kfs else 1.0
            kfs.append(Keyframe(self.cur().id, round(t, 3), tr, self.tlp.curve.currentData(), am))
            self._timeline_undoable(before, self.project.timeline.to_dict())
            self._timeline_changed()

        def _timeline_changed(self):
            self.tlp.view.set_timeline(self.project.timeline, self.project.states)
            self.render_dirty = True

        def geometry_morph(self):
            sts = self.project.states
            if len(sts) < 2:
                QtWidgets.QMessageBox.information(self, APP_NAME, "Store at least two states first.")
                return
            d = QtWidgets.QDialog(self); d.setWindowTitle("Geometry morph (Mode 2)")
            f = QtWidgets.QFormLayout(d)
            a = QtWidgets.QComboBox(); b = QtWidgets.QComboBox()
            for s in sts:
                a.addItem(s.name, s.id); b.addItem(s.name, s.id)
            b.setCurrentIndex(1)
            n = QtWidgets.QSpinBox(); n.setRange(1, 16); n.setValue(4)
            t0 = QtWidgets.QDoubleSpinBox(); t0.setRange(0, 36000); t0.setSuffix(" s")
            dur = (self.x.shape[0] / self.fs) if self.x is not None else 6.0
            t1 = QtWidgets.QDoubleSpinBox(); t1.setRange(0, 36000); t1.setSuffix(" s"); t1.setValue(dur * 0.9)
            f.addRow(QtWidgets.QLabel("Generates intermediate geometries by interpolating corresponding elements,\n"
                                      "SIMULATES each one, and sequences them on the timeline (crossfaded).\n"
                                      "This approximates a changing room by a chain of static rooms;\n"
                                      "it is not a time-varying simulation."))
            f.addRow("From state", a); f.addRow("To state", b); f.addRow("Intermediate steps", n)
            f.addRow("Start time", t0); f.addRow("End time", t1)
            bb = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel)
            bb.accepted.connect(d.accept); bb.rejected.connect(d.reject); f.addRow(bb)
            if d.exec() != QtWidgets.QDialog.Accepted:
                return
            sa, sb = self.project.state(a.currentData()), self.project.state(b.currentData())
            try:
                mids = geometry_morph(sa.geometry, sb.geometry, n.value())
            except GeometryError as e:
                QtWidgets.QMessageBox.warning(self, APP_NAME, str(e))
                return
            chain = [sa]
            for k, g in enumerate(mids):
                st = sa.duplicate(f"{sa.name} > {sb.name} {k + 1}/{len(mids)}")
                st.geometry = g
                st.response_key = None
                st.notes = "Mode 2 intermediate geometry"
                self.project.states.append(st)
                chain.append(st)
            chain.append(sb)
            T0, T1 = t0.value(), max(t1.value(), t0.value() + 0.1)
            seg = (T1 - T0) / (len(chain) - 1)
            kfs = [k for k in self.project.timeline.keyframes if not (T0 <= k.time <= T1)]
            for i, st in enumerate(chain):
                kfs.append(Keyframe(st.id, T0 + i * seg, 0.0 if i == 0 else seg, "equal_power"))
            self.project.timeline.keyframes = kfs
            self.refresh_all()
            self.btabs.setCurrentWidget(self.tlp)
            if QtWidgets.QMessageBox.question(self, APP_NAME, f"{len(mids)} intermediate states created.  "
                                              "Compute all outdated states now?") == QtWidgets.QMessageBox.Yes:
                self.compute_all()

        # ---------------------------------------------------------- render
        def render(self, then=None):
            if self.x is None:
                QtWidgets.QMessageBox.information(self, APP_NAME, "Load a source first.")
                return
            if self.runner.busy:
                return
            proj = self.project
            o = proj.output
            states = proj.states_by_id()
            use_tl = o.use_timeline and bool(proj.timeline.keyframes)
            st = self.cur()
            if not use_tl and st.status(self.cache) != "computed":
                QtWidgets.QMessageBox.information(self, APP_NAME, f"'{st.name}' has no up-to-date response - "
                                                  "press Compute first.")
                return
            if use_tl and not self._timeline_ready(lambda: self.render(then), "render"):
                return
            x, fs, cache, src = self.x, self.fs, self.cache, praat_name(self.src_name)
            args = self._main_args(use_tl)
            states = args[2]
            st = args[6]
            out_set = args[7]
            target = o.target
            sig = self._main_sig(args)
            hit = self._cached_main(sig)

            def job(progress, cancel):
                outs = []
                if hit is not None:                       # identical to the last preview/render
                    _s, y, info, desc, used = hit
                else:
                    y, info, desc, used = render_main(*args, progress=progress, cancel=cancel)
                self._main_cache_pending = (sig, y, info, desc, used)
                outs.append(("render", f"{src}_acoustic_morphology", y, fs, desc, info))
                if cancel():
                    return None
                if o.export_irs:
                    seen = []
                    for s in used:
                        if s.id in seen:
                            continue
                        seen.append(s.id)
                        letter = chr(65 + len(seen) - 1) if len(seen) <= 26 else str(len(seen))
                        r = cache.get(s.response_key)
                        for m in s.geometry.mics:
                            if m.enabled and m.id in r.mics:
                                outs.append(("ir", f"Acoustic_IR_{letter}_{m.name}", r.mics[m.id].ir[:, None], r.fs,
                                             f"modelled-band IR of '{s.name}', {m.name} (<= {r.f_valid:.0f} Hz, "
                                             f"dB re 2-D free field at 1 m)", {}))
                if o.export_layers and st.status(cache) == "computed":
                    res = render_state(x, fs, cache.get(st.response_key), st.mic_settings(),
                                       effective(out_set, st.render), ("mics",))
                    for m in st.geometry.mics:
                        if f"mic:{m.id}" in res:
                            y2, i2 = res[f"mic:{m.id}"]
                            outs.append(("layer", f"{src}_layer_{m.name}", y2, fs,
                                         f"layer: '{st.name}', {m.name}", i2))
                return outs

            self.runner.start(Worker(job, "Rendering"), lambda r: self._render_done(r, then), self._render_failed,
                              lambda f, m: self._progress(f, f"Rendering: {m}"))

        def _render_done(self, outs, then):
            if outs is None:
                return
            self.last_render = outs
            self.render_dirty = False
            if getattr(self, "_main_cache_pending", None) is not None:
                self._main_cache = self._main_cache_pending      # previews now play this exact render
                self._main_cache_pending = None
            lines = []
            src_rms = rms_db(self.x) if self.x is not None else -200.0
            for kind, name, y, fs, desc, info in outs:
                lines.append(f"<b>{html.escape(name)}</b> ({kind})<br>" + html.escape(level_report(y, fs, info, src_rms
                             if kind != "ir" else None)).replace("\n", "<br>")
                             + f"<br><span style='color:#666'>{html.escape(desc)}</span>")
            self.render_info.setHtml("<br><br>".join(lines))
            self.btabs.setCurrentIndex(3)
            self.statusBar().showMessage("Render finished.", 5000)
            if then:
                then()

        def _render_failed(self, msg, cancelled):
            if not cancelled:
                QtWidgets.QMessageBox.warning(self, APP_NAME, f"Render failed:\n\n{msg}")

        def play_render(self):
            if not self.last_render:
                self.render(then=self.play_render)
                return
            y, fs = self.last_render[0][2], self.last_render[0][3]
            self.player.play(y, fs)

        def export(self):
            if self.last_render is None or self.render_dirty:
                self.render(then=self.export)
                return
            outs = [(k, n, y, fs, d) for (k, n, y, fs, d, _i) in self.last_render]
            if self.manifest:
                try:
                    write_outputs(self.manifest, outs, {"states": [s.name for s in self.project.states],
                                                        "timeline": self.project.timeline.to_dict()})
                except Exception as e:
                    QtWidgets.QMessageBox.critical(self, APP_NAME, f"Could not write the results:\n{e}")
                    return
                self.returned = True
                self.close()
            else:
                d = QtWidgets.QFileDialog.getExistingDirectory(self, "Export WAV files to")
                if not d:
                    return
                import soundfile as sf
                for kind, name, y, fs, desc in outs:
                    sf.write(os.path.join(d, praat_name(name) + ".wav"), y.astype("float32"), fs, subtype="FLOAT")
                self.statusBar().showMessage(f"{len(outs)} file(s) written to {d}", 6000)

        # --------------------------------------------------------- project
        def save_project(self):
            p, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Save project", self.project_path or "",
                                                         "AMC project (*.amcproj)")
            if not p:
                return
            if not p.endswith(".amcproj"):
                p += ".amcproj"
            try:
                projmod.save(self.project, p, self.cache)
                self.project_path = p
                self.statusBar().showMessage(f"Saved {p}", 5000)
            except Exception as e:
                QtWidgets.QMessageBox.critical(self, APP_NAME, f"Could not save:\n{e}")

        def open_project(self):
            p, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Open project", "", "AMC project (*.amcproj)")
            if p:
                self.open_project_path(p)

        def open_project_path(self, p):
            try:
                proj, cache, notes = projmod.load(p)
            except Exception as e:
                QtWidgets.QMessageBox.critical(self, APP_NAME, f"Could not open the project:\n{e}")
                return
            if not proj.states:
                QtWidgets.QMessageBox.critical(self, APP_NAME, "The project has no states.")
                return
            self.project, self.cache, self.project_path = proj, cache, p
            self.stacks = {}
            if not self.manifest:
                sp = proj.source.path
                if sp and not os.path.exists(sp):
                    r = QtWidgets.QMessageBox.question(
                        self, APP_NAME, f"The source audio was not found:\n{sp}\n\nLocate (relink) it?")
                    if r == QtWidgets.QMessageBox.Yes:
                        q, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Relink source", "",
                                                                     "Audio (*.wav *.aif *.aiff *.flac)")
                        sp = q or ""
                    else:
                        sp = ""
                if sp and os.path.exists(sp):
                    try:
                        self.load_source(sp, proj.source.name or None)
                    except Exception as e:
                        QtWidgets.QMessageBox.warning(self, APP_NAME, str(e))
            if self.x is not None and any(s.sim.audio_fs != self.fs for s in proj.states):
                notes.append(f"The source rate ({self.fs} Hz) differs from the project's; responses at the "
                             "old rate are marked outdated.")
                for s in proj.states:
                    s.sim.audio_fs = self.fs
            self._sync_output_widgets()
            self.set_current(proj.current_state or proj.states[0].id)
            self.set_workflow(proj.workflow)
            if notes:
                QtWidgets.QMessageBox.information(self, APP_NAME, "\n".join(notes))

        def save_geometry(self):
            p, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Save geometry", "", "Geometry (*.amcgeom)")
            if p:
                if not p.endswith(".amcgeom"):
                    p += ".amcgeom"
                projmod.save_geometry(self.cur().geometry, p)

        def load_geometry(self):
            p, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Load geometry", "", "Geometry (*.amcgeom)")
            if p:
                try:
                    g = projmod.load_geometry(p)
                except Exception as e:
                    QtWidgets.QMessageBox.warning(self, APP_NAME, f"Not a valid geometry:\n{e}")
                    return
                st = self.cur()
                self.editor.edit(lambda: self.editor.apply_snapshot(st.geometry, g.to_dict()), "Load geometry")
                self.editor.fit()

        # ------------------------------------------------------------ misc
        def show_help(self):
            """The manual (it is part of this file: MANUAL at the end)."""
            d = QtWidgets.QDialog(self)
            d.setWindowTitle(f"{APP_NAME} {APP_VERSION} - manual")
            d.resize(980, 760)
            v = QtWidgets.QVBoxLayout(d)
            tb = QtWidgets.QTextBrowser()
            tb.setOpenExternalLinks(True)
            tb.setMarkdown(MANUAL)
            v.addWidget(tb)
            bb = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.Close)
            bb.rejected.connect(d.reject)
            v.addWidget(bb)
            d.exec()

        def closeEvent(self, ev):
            if self.runner.busy:
                self.runner.cancel()
                self.runner.thread.wait(10000) if self.runner.thread else None
            if self.manifest and not self.returned:
                r = QtWidgets.QMessageBox.question(
                    self, APP_NAME, "Close without returning a result to Praat?\n\n"
                    "Yes = close, nothing is imported.   No = keep working.",
                    QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No, QtWidgets.QMessageBox.No)
                if r != QtWidgets.QMessageBox.Yes:
                    ev.ignore()
                    return
            self.player.stop()
            ev.accept()

    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setStyleSheet(STYLE)
    win = MainWindow()
    win._sync_output_widgets()
    win.show()
    if project_path:
        win.open_project_path(project_path)
    if scenario_out:                              # --selftest: the GUI scenario
        QtCore.QTimer.singleShot(400, lambda: _gui_scenario(win, app, scenario_out))
    if os.environ.get("AMC_GUI_SCRIPT"):          # test hook: run a script inside the event loop
        import runpy
        QtCore.QTimer.singleShot(300, lambda: runpy.run_path(os.environ["AMC_GUI_SCRIPT"],
                                                             init_globals={"win": win, "app": app}))
    return app.exec()


# ======================================================================
# entry point
# ======================================================================

def remove_stale_sessions(manifest: dict | None):
    """Remove EMPTY AMC_session_* folders left by earlier runs (versions up
    to 1.2 could not remove their folder on Windows).  Only empty folders are
    touched (os.rmdir), never the current session."""
    if manifest is None:
        return
    own = os.path.normcase(os.path.abspath(manifest["session_dir"]))
    dirs = [os.path.dirname(own)] + [d for d in manifest.get("cleanup_dirs", []) if isinstance(d, str)]
    for d in dict.fromkeys(os.path.normcase(os.path.abspath(x)) for x in dirs):
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for nm in names:
            p = os.path.join(d, nm)
            if (nm.startswith("AMC_session_") and nm[12:].isdigit()
                    and os.path.normcase(os.path.abspath(p)) != own and os.path.isdir(p)):
                try:
                    os.rmdir(p)          # fails (harmlessly) unless the folder is empty
                except OSError:
                    pass


def mark_alive(manifest: dict | None, state: str):
    """Session liveness marker read by the Praat launcher: 'running' while the
    application works, 'closed' after a normal exit.  A marker still saying
    'running' after the process ended means it crashed without a traceback
    (for example a Qt abort); no marker means Python never started."""
    if manifest is None:
        return
    try:
        p = os.path.join(manifest["session_dir"], "alive.txt")
        with open(p + ".tmp", "w", encoding="utf-8") as f:
            f.write(state)
        os.replace(p + ".tmp", p)
    except Exception:
        pass


def check_display():
    """Qt aborts the whole process when it cannot open a display; say so
    instead (the message reaches Praat through error.txt)."""
    if sys.platform.startswith("linux") and not os.environ.get("QT_QPA_PLATFORM"):
        if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            raise RuntimeError("No graphical display is available (DISPLAY / WAYLAND_DISPLAY not set): "
                               "the composer window cannot open.")




# ============================================================================
# EXAMPLES AND VALIDATION  (--make-example DIR, --validate DIR)
# ============================================================================
def synthetic_cello(seconds=6.0, fs=48000, f0=98.0, seed=7):
    rng = np.random.default_rng(seed)
    n = int(seconds * fs)
    t = np.arange(n) / fs
    vib = 1 + 0.0035 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.8, 0, 1)   # vibrato after the attack
    phase = 2 * np.pi * np.cumsum(f0 * vib) / fs
    y = np.zeros(n)
    kmax = int(0.45 * fs / f0)
    for k in range(1, kmax + 1):
        y += np.sin(k * phase + rng.uniform(0, 2 * np.pi)) / k
    # body resonances (peaking filters) - the instrument's own colour, constant
    for fc, q, g_db in ((280, 4, 7), (480, 5, 5), (1000, 3, 4)):
        b, a = signal.iirpeak(fc, q, fs)
        y = y + (10 ** (g_db / 20) - 1) * signal.lfilter(b, a, y)
    noise = signal.lfilter(*signal.butter(2, [1500, 6000], "bandpass", fs=fs), rng.standard_normal(n))
    y = y / np.abs(y).max() + 0.015 * noise
    swell = 0.75 + 0.25 * np.sin(np.pi * t / seconds)
    env = np.clip(t / 0.09, 0, 1) * np.clip((seconds - t) / 0.35, 0, 1) * swell
    y = y * env
    return (0.5 * y / np.abs(y).max()).astype(np.float32), fs


_VAL_PRESETS = [("open_field", "Open Field"), ("resonant_chamber", "Resonant Chamber"),
           ("narrow_passage", "Narrow Passage")]


_VAL_F0 = 98.0


def _val_bands(f_lo, f_hi, frac=6):
    edges = [f_lo]
    while edges[-1] < f_hi:
        edges.append(edges[-1] * 2 ** (1 / frac))
    return np.array(edges)


def _val_band_db(f, p, edges):
    out = []
    for a, b in zip(edges[:-1], edges[1:]):
        m = (f >= a) & (f < b)
        out.append(10 * math.log10(max(p[m].mean(), 1e-30)) if m.any() else np.nan)
    return np.array(out)


def _val_harmonic_db(f, p, f0, kmax):
    """Peak power around each harmonic (+-4 %: vibrato is 0.35 %)."""
    out = []
    for k in range(1, kmax + 1):
        m = (f >= k * f0 * 0.96) & (f <= k * f0 * 1.04)
        out.append(10 * math.log10(max(p[m].max(), 1e-30)))
    return np.array(out)


def musical_validation(out_dir, quality="Standard"):
    os.makedirs(out_dir, exist_ok=True)
    fs = 48000
    x, _ = synthetic_cello(6.0, fs)
    x = x.astype(np.float64)[:, None]
    tone_end = 6.0                      # the tone's release ends here
    sus = (int(0.6 * fs), int(5.4 * fs))
    nper = 1 << 15
    fx, px = signal.welch(x[sus[0]:sus[1], 0], fs, nperseg=nper)
    results = {"quality": quality, "tone": "synthetic bowed string, G2 = 98 Hz, 6 s", "presets": {}}
    curves = {}
    for key, name in _VAL_PRESETS:
        states, _ = presets.build(key)
        st = states[0]
        st.sim = SimSettings(quality)
        st.sim.audio_fs = fs
        t0 = time.time()
        sim = simulate(st.geometry, st.sim, store_frames=False)
        resp = build_response(sim, st.current_key(), st.sim.c)
        mic = st.geometry.mics[0]
        h = resp.mics[mic.id].ir
        fv = resp.f_valid
        # wet only, unmodelled band removed, no peak protection: levels stay physical
        rs = RenderSettings(mix=1.0, band_strategy="attenuate", peak_protect=False, duration="tail")
        y = render_state(x, fs, resp, st.mic_settings(), rs, ("mics",))[f"mic:{mic.id}"][0]
        # listening version: unmodelled band preserved, peak -1 dBFS
        rl = RenderSettings(mix=1.0, band_strategy="preserve", peak_protect=True, duration="tail")
        yl = render_state(x, fs, resp, st.mic_settings(), rl, ("mics",))[f"mic:{mic.id}"][0]
        sf.write(os.path.join(out_dir, f"{key}_{mic.name}.wav"), yl.astype(np.float32), fs, subtype="PCM_24")
        fy, py = signal.welch(y[sus[0]:sus[1], 0], fs, nperseg=nper)
        H = np.fft.rfft(h, 1 << 19)
        fh = np.fft.rfftfreq(1 << 19, 1 / fs)
        P = np.abs(H) ** 2
        kmax = int(0.9 * fv / _VAL_F0)
        harm = _val_harmonic_db(fy, py, _VAL_F0, kmax) - _val_harmonic_db(fx, px, _VAL_F0, kmax)
        # simulated |H|^2 averaged over the vibrato range of each harmonic (+-0.35 %)
        harm_sim = np.array([10 * math.log10(max(P[(fh >= k * _VAL_F0 * 0.9965) & (fh <= k * _VAL_F0 * 1.0035)].mean(),
                                                  1e-30)) for k in range(1, kmax + 1)])
        corr = float(np.corrcoef(harm, harm_sim)[0, 1])
        dev = float(np.sqrt(np.mean((harm - harm_sim) ** 2)))
        inb = (fy >= 60) & (fy <= 0.9 * fv)
        centroid = float((fy[inb] * py[inb]).sum() / py[inb].sum())
        cx = float((fx[inb] * px[inb]).sum() / px[inb].sum())
        e0 = int((tone_end + 0.1) * fs); e1 = int((tone_end + 0.3) * fs)
        ring = rms_db(y[e0:e1]) - rms_db(y[int(4.0 * fs):int(5.0 * fs)])
        fp = fingerprint(h, fs, fv)
        results["presets"][key] = {
            "name": name, "mic": mic.name, "f_valid_Hz": round(fv, 1), "sim_seconds": round(time.time() - t0, 1),
            "level_dB_re_input": round(rms_db(y[sus[0]:sus[1]]) - rms_db(x[sus[0]:sus[1]]), 2),
            "centroid_in_band_Hz": round(centroid, 1), "input_centroid_in_band_Hz": round(cx, 1),
            "harmonics_measured_vs_simulated_corr": round(corr, 4),
            "harmonics_measured_vs_simulated_rms_dB": round(dev, 2),
            "harmonics_dB_re_input": [round(v, 1) for v in harm],
            "harmonics_simulated_H_dB": [round(v, 1) for v in harm_sim],
            "ringing_100_300ms_after_end_dB_re_sustain": round(ring, 1),
            "resonant_peaks_Hz": [round(a) for a, _ in fp.peaks[:6]],
            "T30_2D_s": None if fp.t30 is None else round(fp.t30, 3),
        }
        curves[key] = dict(harm=harm, harm_sim=harm_sim, h=h, fv=fv, fh=fh, P=P)
        print(f"{name:17s} level {results['presets'][key]['level_dB_re_input']:+6.1f} dB  centroid "
              f"{centroid:6.0f} Hz  harmonics vs simulation: r {corr:.3f}, {dev:.2f} dB rms  "
              f"ringing {ring:+.1f} dB")
    # level-matched timbre distance between presets: harmonic profiles with
    # their mean removed (common harmonics only)
    keys = [k for k, _ in _VAL_PRESETS]
    dist = {}
    for i in range(3):
        for j in range(i + 1, 3):
            a, b = curves[keys[i]]["harm"], curves[keys[j]]["harm"]
            n = min(len(a), len(b))
            d = (a[:n] - a[:n].mean()) - (b[:n] - b[:n].mean())
            dist[f"{keys[i]} vs {keys[j]}"] = round(float(np.sqrt(np.mean(d ** 2))), 2)
    results["level_matched_timbre_distance_dB"] = dist
    print("level-matched timbre distance (dB RMS over harmonics):", dist)
    with open(os.path.join(out_dir, "results.json"), "w") as f:
        json.dump(results, f, indent=1)
    sf.write(os.path.join(out_dir, "input_synthetic_cello.wav"), x.astype(np.float32), fs, subtype="PCM_24")
    try:
        _val_figure(curves, results, os.path.join(out_dir, "validation.png"))
    except ImportError:
        print("(matplotlib not installed: validation.png not drawn)")
    return results


def _val_figure(curves, results, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    cols = {"open_field": "#1f5f99", "resonant_chamber": "#b9483f", "narrow_passage": "#3a9d6a"}
    fig, ax = plt.subplots(2, 1, figsize=(8, 7.2))
    for key, c in curves.items():
        nm = results["presets"][key]["name"]
        r = results["presets"][key]["harmonics_measured_vs_simulated_corr"]
        sel = (c["fh"] >= 50) & (c["fh"] <= c["fv"])
        ff, pp = c["fh"][sel], 10 * np.log10(np.maximum(c["P"][sel], 1e-30))
        step = max(1, len(ff) // 4000)
        ax[0].semilogx(ff[::step], pp[::step], color=cols[key], lw=0.8, alpha=0.75, label=f"{nm}: simulated |H|")
        k = np.arange(1, len(c["harm"]) + 1)
        ax[0].semilogx(k * 98.0, c["harm"], "o", ms=4, color=cols[key], mfc="white", mew=1.2,
                       label=f"{nm}: measured on the tone's harmonics (r = {r:.3f})")
        ax[1].plot(k * 98.0, c["harm"] - c["harm"].mean(), "-o", ms=3, lw=1.1, color=cols[key], label=nm)
    ax[0].set_title("Simulated response vs. what happened to each harmonic of the tone", fontsize=10)
    ax[0].set_xlabel("frequency (Hz)"); ax[0].set_ylabel("dB (re input; |H| re 2-D free field at 1 m)")
    ax[0].grid(alpha=0.3, which="both"); ax[0].legend(fontsize=6.5, ncol=1)
    ax[1].set_title("Timbre: harmonic profile after each geometry, level-matched (mean removed)", fontsize=10)
    ax[1].set_xlabel("harmonic frequency (Hz)"); ax[1].set_ylabel("dB"); ax[1].grid(alpha=0.3)
    ax[1].legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(path, dpi=130)


_MC_C = 343.0


def _mc_resp(g, q="Draft", L=0.05, c25=True):
    s = SimSettings(q, ir_length=L)
    s.audio_fs = 48000
    return build_response(simulate(g, s, store_frames=False), "k" * 20, _MC_C, correction_25d=c25)


def model_checks():
    print("QUALITY MODES (48 kHz audio)")
    g = Geometry(4.0, 3.0, [], (1, 1), [Mic(2, 2)], Boundary("partial", 0.1))
    for q in QUALITIES:
        s = SimSettings(q); s.audio_fs = 48000
        p = make_plan(g, s)
        print(f"  {q:16s} dx {p.dx * 100:5.2f} cm  fs_sim {p.fs_sim:7.0f} Hz  Courant {p.courant:.3f}  "
              f"band <= {p.f_valid:5.0f} Hz  ({p.points_per_wavelength:.1f} cells/wavelength)  "
              f"{p.cells} cells, {p.n_steps} steps for {p.ir_length} s")
    s = SimSettings("Standard"); s.audio_fs = 48000
    p = make_plan(g, s)
    errs = [phase_velocity_error(p.f_valid, p.dx, p.dt, _MC_C, t) for t in np.linspace(0, math.pi / 4, 9)]
    print(f"  phase-velocity error at the band edge (Standard): {min(errs) * 100:+.2f} .. {max(errs) * 100:+.2f} %")

    print("\nFREE FIELD (PML, 2.5-D correction on)")
    g = Geometry(4.0, 3.0, [], (1.0, 1.5), [Mic(2.0, 1.5, "1m"), Mic(3.0, 1.5, "2m"),
                                             Mic(1 + 2 / math.sqrt(2), 1.5 + 2 / math.sqrt(2), "2m diag")],
                 Boundary("absorbing", 0))
    r = _mc_resp(g, L=0.03)
    for m, d, exp in zip(g.mics, (1, 2, 2), (0, -3.01, -3.01)):
        h = r.mics[m.id].ir
        fp = fingerprint(h, r.fs, r.f_valid)
        tp = np.argmax(np.abs(h)) / r.fs
        band = (fp.freqs > 100) & (fp.freqs < 0.8 * r.f_valid)
        print(f"  {m.name:8s} level {fp.level_db:+6.2f} dB (2-D theory {exp:+.2f})  arrival error "
              f"{(tp - d / _MC_C) * 1e6:+6.1f} us ({(tp - d / _MC_C) * r.fs:+.2f} samples)  in-band ripple "
              f"{np.ptp(fp.mag_db[band]):.2f} dB")

    print("\nPML RESIDUAL REFLECTION (small domain vs. a 4x larger one)")
    for name, src, mic in (("normal", (0.6, 1.0), (1.6, 1.0)), ("grazing", (0.25, 0.2), (1.75, 0.2))):
        a = _mc_resp(Geometry(2.0, 2.0, [], src, [Mic(*mic)], Boundary("absorbing", 0)), L=0.04)
        b = _mc_resp(Geometry(8.0, 8.0, [], (src[0] + 3, src[1] + 3), [Mic(mic[0] + 3, mic[1] + 3)],
                          Boundary("absorbing", 0)), L=0.04)
        ha = list(a.mics.values())[0].ir; hb = list(b.mics.values())[0].ir
        print(f"  {name:8s} {20 * math.log10(np.abs(ha - hb).max() / np.abs(hb).max()):6.1f} dB re direct sound")

    print("\nWALL ABSORPTION (normal incidence, 1-D duct): requested alpha vs measured 1 - R^2")
    for alpha in (0.1, 0.3, 0.5, 0.9):
        s = SimSettings("Draft", ir_length=0.03); s.audio_fs = 48000
        dx = s.resolved_dx(); H = 3 * dx
        g = Geometry(8.0, H, [Element("rect", 7.0, -1, 9, 2, alpha=alpha)], (1.0, H / 2), [Mic(4.0, H / 2, "M")],
                     Boundary("rigid", 0))
        rr = build_response(simulate(g, s, store_frames=False), "k" * 20, _MC_C, correction_25d=False)
        h = list(rr.mics.values())[0].ir
        w = int(0.004 * 48000)
        inc = h[int(3 / _MC_C * 48000) - w:int(3 / _MC_C * 48000) + w]
        ref = h[int(9 / _MC_C * 48000) - w:int(9 / _MC_C * 48000) + w]
        f = np.fft.rfftfreq(4096, 1 / 48000)
        band = (f > 100) & (f < 0.8 * rr.f_valid)
        R = np.median(np.abs(np.fft.rfft(ref, 4096))[band] / np.abs(np.fft.rfft(inc, 4096))[band])
        print(f"  alpha {alpha:.2f}: measured {1 - R * R:.3f}")

    print("\nRIGID RECTANGLE 1.0 x 0.7 m: simulated mode frequencies vs c/2*sqrt((m/Lx)^2+(n/Ly)^2)")
    print("  (peak of |H| within +-3 % of each mode; 'grid' uses the room size as quantised to whole cells,")
    print("   'drawn' the size as drawn; modes the source/microphone positions barely excite are skipped)")
    Lx, Ly = 1.0, 0.7
    g = Geometry(Lx, Ly, [], (0.23, 0.17), [Mic(0.81, 0.53, "M")], Boundary("rigid", 0))
    for q in ("Draft", "Standard"):
        s = SimSettings(q, ir_length=1.0); s.audio_fs = 48000
        p = make_plan(g, s)
        Lxg, Lyg = p.nx * p.dx, p.ny * p.dx
        r = _mc_resp(g, q=q, L=1.0)
        h = list(r.mics.values())[0].ir
        Hm = np.abs(np.fft.rfft(h, 1 << 20)); f = np.fft.rfftfreq(1 << 20, 1 / 48000)
        modes = sorted((_MC_C / 2 * math.hypot(m / Lx, n / Ly), m, n) for m in range(8) for n in range(8) if m + n)
        rows = []
        for ft, m, n in modes:
            if not 80 < ft < 0.7 * r.f_valid:
                continue
            # coupling of source and microphone to this mode (cosine mode shape)
            cpl = abs(math.cos(m * math.pi * 0.23 / Lx) * math.cos(n * math.pi * 0.17 / Ly)
                      * math.cos(m * math.pi * 0.81 / Lx) * math.cos(n * math.pi * 0.53 / Ly))
            if cpl < 0.1:
                continue
            fg = _MC_C / 2 * math.hypot(m / Lxg, n / Lyg)
            sel = (f > fg * 0.97) & (f < fg * 1.03)
            fp = f[sel][np.argmax(Hm[sel])]
            rows.append(f"({m},{n}) {fp:.1f} Hz: grid {100 * (fp - fg) / fg:+.2f}%, drawn {100 * (fp - ft) / ft:+.2f}%")
            if len(rows) >= 7:
                break
        print(f"  {q} (grid room {Lxg:.3f} x {Lyg:.3f} m)")
        for row in rows:
            print("    " + row)

    print("\nENERGY (closed rigid room, after the source): relative variation of the discrete invariant")
    g = Geometry(1.0, 0.7, [Element("wall", 0.5, 0.0, 0.5, 0.4)], (0.23, 0.17), [Mic(0.81, 0.53)],
                 Boundary("rigid", 0))
    sim = simulate(g, SimSettings("Draft", ir_length=0.6), store_frames=False)
    E = sim.energy[len(sim.energy) // 10:]
    print(f"  max/min - 1 = {E.max() / E.min() - 1:.2e} over {len(E)} checks")
    g.boundary = Boundary("partial", 0.2)
    sim = simulate(g, SimSettings("Draft", ir_length=0.6), store_frames=False)
    E = sim.energy[len(sim.energy) // 10:]
    print(f"  with absorbing edges (alpha 0.2): energy falls {10 * math.log10(E[0] / E[-1]):.1f} dB, "
          f"monotonic: {bool(np.all(np.diff(E) <= 1e-12 * E[0]))}")


def make_example(out_dir, quality="Draft"):
    wav = os.path.join(out_dir, "synthetic_cello_G2.wav")
    if not os.path.exists(wav):
        y, fs = synthetic_cello(6.0, 48000)
        sf.write(wav, y, fs, subtype="FLOAT")
    info = sf.info(wav)
    states, _ = build_preset("moving_aperture")
    a, b = states
    a.name, b.name = "A  wide aperture (60 cm)", "B  narrow aperture (8 cm)"
    a.notes = "Example: dividing wall with a 60 cm opening."
    b.notes = "Example: the same wall with an 8 cm opening (elements correspond: Mode 2 morph possible)."
    cache = ResponseCache()
    for st in states:
        st.sim = SimSettings(quality, ir_length=0.6)
        st.sim.audio_fs = info.samplerate
        r = build_response(simulate(st.geometry, st.sim, store_frames=False), st.current_key(), st.sim.c)
        cache.put(r)
        st.response_key = r.key
        print(f"{st.name}: {r.plan_text}")
    tl = Timeline([Keyframe(a.id, 0.5, 0.0, "equal_power"),
                   Keyframe(b.id, 2.8, 1.8, "equal_power"),
                   Keyframe(a.id, 5.0, 1.6, "smoothstep", 0.6)], "input")
    proj = Project(states=states, current_state=a.id, timeline=tl,
                           source=SourceRef(wav, info.samplerate, info.channels, info.duration,
                                                    "synthetic_cello_G2"),
                           workflow="B")
    proj.output.target = "mix_stereo"
    out = os.path.join(out_dir, "example_moving_aperture.amcproj")
    save_project_file(proj, out, cache)
    # keep the source reference relative only (the absolute path is machine-specific)
    import json
    with open(out, encoding="utf-8") as f:
        doc = json.load(f)
    doc["source"]["path"] = "synthetic_cello_G2.wav"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    print("wrote", out)


# ============================================================================
# SELF-TEST: CORE TESTS 1-8 AND EXTRAS  (run by --selftest)
# ============================================================================
_T_FS = 48000
_T_C = 343.0


def _t_response(geom, quality="Draft", ir_length=0.05, c25=True):
    s = SimSettings(quality, ir_length=ir_length)
    r = simulate(geom, s, store_frames=False)
    return build_response(r, "k" * 20, s.c, correction_25d=c25)


def _t_ir_of(resp, geom, k=0):
    return resp.mics[geom.mics[k].id].ir


def _t_computed(state, cache, quality="Draft"):
    state.sim = SimSettings(quality)
    r = simulate(state.geometry, state.sim, store_frames=False)
    resp = build_response(r, state.current_key(), state.sim.c)
    cache.put(resp)
    state.response_key = resp.key
    return resp


def _t_tone(dur=1.0, f0=110.0, ch=1, seed=0):
    t = np.arange(int(dur * _T_FS)) / _T_FS
    y = sum((0.5 / k) * np.sin(2 * np.pi * k * f0 * t) for k in range(1, 30) if k * f0 < 20000)
    y *= np.minimum(1, t * 30) * np.minimum(1, (dur - t) * 30)
    y = 0.4 * y / np.abs(y).max()
    if ch == 2:
        y2 = 0.1 * np.random.default_rng(seed).standard_normal(len(t))
        return np.stack([y, y2], 1)
    return y[:, None]


# ------------------------------------------------------------------ test 1


def test1_free_propagation_travel_time_and_level():
    g = Geometry(4.0, 3.0, [], (1.0, 1.5),
                 [Mic(2.0, 1.5, "1m"), Mic(3.0, 1.5, "2m"),
                  Mic(1 + 2 / math.sqrt(2), 1.5 + 2 / math.sqrt(2), "2m diag")],
                 Boundary("absorbing", 0))
    resp = _t_response(g, ir_length=0.03)
    for k, (d, expect_db) in enumerate([(1.0, 0.0), (2.0, -3.01), (2.0, -3.01)]):
        h = _t_ir_of(resp, g, k)
        t_peak = np.argmax(np.abs(h)) / resp.fs
        assert abs(t_peak - d / _T_C) < 2.5 / resp.fs, (k, t_peak, d / _T_C)
        fp = fingerprint(h, resp.fs, resp.f_valid)
        # 2-D free field: 0 dB at 1 m, -3 dB per distance doubling
        assert abs(fp.level_db - expect_db) < 0.5, (k, fp.level_db)
        band = (fp.freqs > 100) & (fp.freqs < 0.8 * resp.f_valid)
        assert np.ptp(fp.mag_db[band]) < 1.5          # flat after the 2.5-D correction


def test1b_dispersion_bandwidth_criterion():
    s = SimSettings("Standard")
    g = Geometry(2, 2, [], (0.5, 0.5), [Mic(1.5, 1.5)], Boundary("rigid", 0))
    plan = make_plan(g, s)
    worst = max(abs(phase_velocity_error(plan.f_valid, plan.dx, plan.dt, _T_C, t))
                for t in np.linspace(0, math.pi / 4, 9))
    assert worst <= s.accuracy * 1.05
    worst_above = max(abs(phase_velocity_error(1.5 * plan.f_valid, plan.dx, plan.dt, _T_C, t))
                      for t in np.linspace(0, math.pi / 4, 9))
    assert worst_above > s.accuracy
    assert plan.courant <= 1 / math.sqrt(2) + 1e-12


# ------------------------------------------------------------------ test 2


def test2_reflecting_wall_gives_delayed_reflection():
    # source and mic 0.5 m in front of a long rigid wall, 1 m apart
    wall_y = 1.0
    g = Geometry(5.0, 3.0, [Element("wall", 0.2, wall_y, 4.8, wall_y, 0.06, 0.0)], (2.0, 1.5),
                 [Mic(3.0, 1.5, "M")], Boundary("absorbing", 0))
    gref = Geometry(5.0, 3.0, [], (2.0, 1.5), [Mic(3.0, 1.5, "M")], Boundary("absorbing", 0))
    h = _t_ir_of(_t_response(g, ir_length=0.03), g)
    h0 = _t_ir_of(_t_response(gref, ir_length=0.03), gref)
    refl = h - h0
    fs = _T_FS
    d_img = math.hypot(1.0, 2 * (1.5 - wall_y - 0.03))      # image path (wall face at y=1.03)
    t_r = np.argmax(np.abs(refl)) / fs
    assert abs(t_r - d_img / _T_C) < 3 / fs, (t_r, d_img / _T_C)
    # rigid wall: reflection level ~ image source at d_img (2-D spreading)
    lev = 20 * math.log10(np.abs(refl).max() / np.abs(h0).max())
    expect = -10 * math.log10(d_img / 1.0)
    assert abs(lev - expect) < 1.5, (lev, expect)


# ------------------------------------------------------------------ test 3


def test3_narrow_aperture_frequency_dependent_transmission():
    res = {}
    for width in (0.6, 0.2, 0.08):
        y0, y1 = 1.2 - width / 2, 1.2 + width / 2
        g = Geometry(4.0, 2.4, [Element("wall", 2.0, 0, 2.0, 2.4, 0.06), Element("opening", 1.9, y0, 2.1, y1)],
                     (1.0, 1.2), [Mic(3.0, 1.2, "behind")], Boundary("absorbing", 0))
        resp = _t_response(g, ir_length=0.06)
        fp = fingerprint(_t_ir_of(resp, g), resp.fs, resp.f_valid)
        f, m = fp.freqs, 10 ** (fp.mag_db / 10)
        lo = 10 * math.log10(m[(f > 100) & (f < 300)].mean())
        hi = 10 * math.log10(m[(f > 600) & (f < 0.9 * resp.f_valid)].mean())
        res[width] = (lo, hi)
    # narrower opening -> less transmission overall ...
    assert res[0.6][0] > res[0.2][0] > res[0.08][0]
    assert res[0.6][1] > res[0.2][1] > res[0.08][1]
    # ... and a darker balance (high band loses more than the low band)
    tilt = {w: res[w][1] - res[w][0] for w in res}
    assert tilt[0.08] < tilt[0.6] - 2.0, tilt


# ------------------------------------------------------------------ test 4


def test4_resonant_chamber_modes_match_2d_theory():
    Lx, Ly = 1.0, 0.7
    g = Geometry(Lx, Ly, [], (0.23, 0.17), [Mic(0.81, 0.53, "M")], Boundary("rigid", 0))
    resp = _t_response(g, ir_length=1.0)
    fp = fingerprint(_t_ir_of(resp, g), resp.fs, resp.f_valid, n_peaks=20)
    theory = sorted({_T_C / 2 * math.hypot(m / Lx, n / Ly) for m in range(8) for n in range(8) if m + n})
    theory = [f for f in theory if 80 < f < 0.7 * resp.f_valid]
    peaks = [p[0] for p in fp.peaks]
    matched = 0
    for f in theory[:6]:
        err = min(abs(p - f) / f for p in peaks)
        if err < 0.02:
            matched += 1
    assert matched >= 5, (theory[:6], peaks)


def test4b_lossless_room_conserves_energy():
    g = Geometry(1.0, 0.7, [Element("wall", 0.5, 0.0, 0.5, 0.4)], (0.23, 0.17),
                 [Mic(0.81, 0.53, "M")], Boundary("rigid", 0))
    r = simulate(g, SimSettings("Draft", ir_length=0.6), store_frames=False)
    E = r.energy[len(r.energy) // 10:]
    assert E.max() / E.min() - 1 < 1e-4
    assert not r.warnings


# ------------------------------------------------------------------ test 5


def test5_geometry_sensitivity():
    cache = ResponseCache()
    a = presets.build("open_field")[0][0]
    b = presets.build("resonant_chamber")[0][0]
    ra, rb = _t_computed(a, cache), _t_computed(b, cache)
    ha, hb = _t_ir_of(ra, a.geometry), _t_ir_of(rb, b.geometry)
    fa, fb = fingerprint(ha, _T_FS, ra.f_valid), fingerprint(hb, _T_FS, rb.f_valid)
    band = (fa.freqs > 80) & (fa.freqs < 0.9 * min(ra.f_valid, rb.f_valid))
    spec_dist = np.sqrt(np.mean((fa.mag_db[band] - fb.mag_db[band]) ** 2))
    assert spec_dist > 6.0
    x = _t_tone(1.0)
    ya = render_state(x, _T_FS, ra, a.mic_settings(), RenderSettings(peak_protect=False), ("mics",))
    yb = render_state(x, _T_FS, rb, b.mic_settings(), RenderSettings(peak_protect=False), ("mics",))
    sa = ya[f"mic:{a.geometry.mics[0].id}"][0][:, 0]
    sb = yb[f"mic:{b.geometry.mics[0].id}"][0][:, 0]
    Sa = np.abs(np.fft.rfft(sa)); Sb = np.abs(np.fft.rfft(sb))
    f = np.fft.rfftfreq(len(sa), 1 / _T_FS)
    # compare the harmonic levels of the 110 Hz tone inside the modelled band
    harm = [k * 110 for k in range(1, 30) if k * 110 < 0.9 * ra.f_valid]
    da = np.array([20 * np.log10(Sa[np.argmin(abs(f - h))]) for h in harm])
    db = np.array([20 * np.log10(Sb[np.argmin(abs(f - h))]) for h in harm])
    d = (db - db.mean()) - (da - da.mean())
    assert np.sqrt(np.mean(d ** 2)) > 3.0      # audible timbre difference


# ------------------------------------------------------------------ test 6


def test6_repeatability():
    g = presets.build("labyrinth")[0][0].geometry
    s = SimSettings("Draft", ir_length=0.2)
    r1 = build_response(simulate(g, s, store_frames=False), "k" * 20, _T_C)
    r2 = build_response(simulate(g, s, store_frames=False), "k" * 20, _T_C)
    for mid in r1.mics:
        assert np.array_equal(r1.mics[mid].ir, r2.mics[mid].ir)
    x = _t_tone(0.5)
    mics = AcousticState("x", g).mic_settings()
    for strat in BAND_STRATEGIES:
        o1 = render_state(x, _T_FS, r1, mics, RenderSettings(band_strategy=strat), ("mono",))
        o2 = render_state(x, _T_FS, r2, mics, RenderSettings(band_strategy=strat), ("mono",))
        assert np.array_equal(o1["mix_mono"][0], o2["mix_mono"][0])


# ------------------------------------------------------------------ test 7


def test7_audio_consistency():
    cache = ResponseCache()
    st = presets.build("narrow_passage")[0][0]
    resp = _t_computed(st, cache)
    mics = st.mic_settings()
    xm, xs = _t_tone(0.8), _t_tone(0.8, ch=2)
    n = xm.shape[0]
    # sample-rate mismatch is refused, never silently resampled
    with _raises(ValueError):
        render_state(xm, 44100, resp, mics, RenderSettings())
    # channel routing
    for x, pol, ch in ((xm, "mono", 1), (xs, "mono", 1), (xs, "per_channel", 2),
                       (xs, "left", 1), (xs, "right", 1)):
        out = render_state(x, _T_FS, resp, mics, RenderSettings(stereo_policy=pol))
        for key, (y, info) in out.items():
            want = 2 if key == "mix_stereo" else (1 if key == "mix_mono" else ch)
            assert y.shape == (n, want), (pol, key, y.shape)
            assert np.all(np.isfinite(y))
            assert info["peak"] <= 10 ** (-1 / 20) + 1e-9
    # left/right policies really pick the channel
    xl = xs.copy(); xl[:, 1] = 0
    out_r = render_state(xl, _T_FS, resp, mics, RenderSettings(stereo_policy="right"), ("mics",))
    assert all(np.abs(v[0]).max() == 0 for v in out_r.values())
    # tail mode keeps the decay, preserve mode keeps the exact length
    out_t = render_state(xm, _T_FS, resp, mics, RenderSettings(duration="tail"), ("mono",))
    assert out_t["mix_mono"][0].shape[0] > n
    # bypass returns the (policy-folded) source untouched, apart from trim/protection
    out_b = render_state(xm, _T_FS, resp, mics, RenderSettings(bypass=True, peak_protect=False),
                         ("mono", "stereo"))
    assert np.allclose(out_b["mix_mono"][0], xm)
    # bypass = the dry term of the mix: a mono source equal-power centred in stereo
    assert np.allclose(out_b["mix_stereo"][0], np.repeat(xm * math.sqrt(0.5), 2, axis=1))
    # dry-only mix equals the source
    out_d = render_state(xm, _T_FS, resp, mics[:1], RenderSettings(mix=0.0, peak_protect=False), ("mics",))
    assert np.allclose(list(out_d.values())[0][0], xm)
    # silent and very short material
    z = np.zeros((2000, 1))
    out_z = render_state(z, _T_FS, resp, mics, RenderSettings())
    assert all(np.abs(v[0]).max() == 0 for v in out_z.values())
    short = _t_tone(0.004)
    out_s = render_state(short, _T_FS, resp, mics, RenderSettings())
    assert all(v[0].shape[0] == short.shape[0] for v in out_s.values())


def test7b_band_split_is_complementary():
    f = np.linspace(0, 24000, 5000)
    L, H = crossover_masks(f, 1500.0)
    assert np.allclose(L + H, 1.0)
    # 'preserve' on a response that is flat in band reconstructs a flat full band
    n = 4096
    d = np.zeros(n); d[100] = 1.0
    F = np.fft.rfftfreq(2 * n, 1 / _T_FS)
    Lm, _ = crossover_masks(F, 1500.0)
    band = np.fft.irfft(np.fft.rfft(d, 2 * n) * Lm, 2 * n)[:n]
    full = full_ir(band, _T_FS, 1500.0, "preserve")
    mag = np.abs(np.fft.rfft(full, 2 * n))
    keep = (F > 50) & (F < 20000)
    assert np.ptp(20 * np.log10(mag[keep])) < 0.5


# ------------------------------------------------------------------ test 8


def _ma_states(cache):
    sts, tl = presets.build("moving_aperture")
    for st in sts:
        _t_computed(st, cache)
    return sts, tl


def test8_morph_continuity_and_tails():
    cache = ResponseCache()
    (a, b), tl = _ma_states(cache)
    states = {a.id: a, b.id: b}
    x = _t_tone(2.0)
    n = x.shape[0]
    for curve in ("linear", "equal_power", "smoothstep", "hold"):
        tl2 = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(b.id, 1.0, 0.5, curve)], "input")
        W = tl2.weights(n, _T_FS)
        wa, wb = W[a.id], W[b.id]
        if curve == "linear" or curve == "smoothstep" or curve == "hold":
            assert np.allclose(wa + wb, 1.0)
        else:
            assert np.allclose(wa ** 2 + wb ** 2, 1.0)
        # weight curves are continuous: no step steeper than the 3 ms
        # raised-cosine de-click ramp (max slope pi / (2 * 0.003 s))
        assert np.abs(np.diff(wa)).max() <= 1.01 * math.pi / (2 * 0.003 * _T_FS)
        y, _ = render_timeline(x, _T_FS, tl2, states, cache, "mix_mono",
                               RenderSettings(peak_protect=False, duration="tail"))
        # no click: the largest sample-to-sample step stays within what the
        # stationary renders already contain
        ya, _ = render_timeline(x, _T_FS, Timeline([Keyframe(a.id, 0, 0)]), states, cache, "mix_mono",
                                RenderSettings(peak_protect=False, duration="tail"))
        yb, _ = render_timeline(x, _T_FS, Timeline([Keyframe(b.id, 0, 0)]), states, cache, "mix_mono",
                                RenderSettings(peak_protect=False, duration="tail"))
        lim = max(np.abs(np.diff(ya[:, 0])).max(), np.abs(np.diff(yb[:, 0])).max())
        # equal power legitimately reaches wa + wb = sqrt(2) mid-transition
        lim *= float((wa + wb).max())
        assert np.abs(np.diff(y[:, 0])).max() <= 1.05 * lim, curve
    # tail preservation: with the input crossfade, sound sent into A before the
    # switch keeps decaying in A after it - so the A-path energy after the
    # transition is > 0 and equals the stand-alone tail of that input
    tl3 = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(b.id, 1.0, 0.05, "linear")], "input")
    W = tl3.weights(n, _T_FS)
    h_a = full_ir(cache.get(a.response_key).mics[a.geometry.mics[0].id].ir, _T_FS,
                  cache.get(a.response_key).f_valid, "preserve")
    part_a = np.convolve(x[:, 0] * W[a.id], h_a)
    after = part_a[int(1.0 * _T_FS):int(1.3 * _T_FS)]
    assert np.sqrt(np.mean(after ** 2)) > 1e-3
    # the output crossfade fades that tail with its weight instead
    tl3.xfade = "output"
    y_out, _ = render_timeline(x, _T_FS, tl3, states, cache, "mic:0",
                               RenderSettings(peak_protect=False, mix=1.0, band_strategy="preserve"))
    tl3.xfade = "input"
    y_in, _ = render_timeline(x, _T_FS, tl3, states, cache, "mic:0",
                              RenderSettings(peak_protect=False, mix=1.0, band_strategy="preserve"))
    assert not np.allclose(y_out, y_in)


def test8b_loop_wraps_smoothly():
    cache = ResponseCache()
    (a, b), _ = _ma_states(cache)
    tl = Timeline([Keyframe(a.id, 0.0, 0.3), Keyframe(b.id, 1.0, 0.3)], "input", True, 2.0)
    W = tl.weights(int(5 * _T_FS), _T_FS)
    assert np.allclose(W[a.id] ** 2 + W[b.id] ** 2, 1.0)
    assert np.abs(np.diff(W[a.id])).max() < 0.01
    # the cycle repeats
    assert np.allclose(W[a.id][:_T_FS], W[a.id][2 * _T_FS:3 * _T_FS])


# ------------------------------------------------- v1.2 review items 1-7


def _np_preset(cache, key="narrow_passage", quality="Draft", ir=0.25):
    st = presets.build(key)[0][0]
    st.sim = SimSettings(quality, ir_length=ir)
    st.sim.audio_fs = _T_FS
    r = build_response(simulate(st.geometry, st.sim, store_frames=False), st.current_key(), st.sim.c)
    cache.put(r)
    st.response_key = r.key
    return st, r


def test10_dry_signal_enters_multi_mic_mixes_once():
    cache = ResponseCache()
    st, r = _np_preset(cache)                      # three microphones
    x = _t_tone(1.0)
    mics = st.mic_settings()
    N = len([m for m in mics if m.enabled])
    assert N == 3
    for target, key in (("mix_mono", "mono"), ("mix_stereo", "stereo")):
        dry = dry_for(x, target)
        y0 = render_state(x, _T_FS, r, mics, RenderSettings(mix=0.0, peak_protect=False), (key,))[target][0]
        assert np.allclose(y0[:len(x)], dry), target                     # dry only: exactly the source
        yb = render_state(x, _T_FS, r, mics, RenderSettings(bypass=True, peak_protect=False), (key,))[target][0]
        assert np.allclose(yb, y0[:len(yb)]), target                     # bypass == the dry term
        y1 = render_state(x, _T_FS, r, mics, RenderSettings(mix=1.0, peak_protect=False, duration="tail"),
                          (key,))[target][0]
        yh = render_state(x, _T_FS, r, mics, RenderSettings(mix=0.5, peak_protect=False, duration="tail"),
                          (key,))[target][0]
        # half/half: 0.5 * dry ONCE + 0.5 * the full wet mix (not 0.5 * dry per microphone)
        ref = 0.5 * y1
        ref[:len(dry)] += 0.5 * dry
        k = min(len(yh), len(ref))                 # tail mode trims silence: compare the common part
        assert np.allclose(yh[:k], ref[:k]), target
    # the timeline uses the same mixing: dry-only timeline = the source
    tl = Timeline([Keyframe(st.id, 0.0, 0.0)])
    yt, _ = render_timeline(x, _T_FS, tl, {st.id: st}, cache, "mix_mono", RenderSettings(mix=0.0, peak_protect=False))
    assert np.allclose(yt, x)


def _reference_timeline(x, fs, tl, states, cache, output, settings):
    """Straightforward full-length implementation (every weight curve and
    every weighted input held in memory) - the reference for the chunked one."""
    xc = source_channels(x, settings.stereo_policy)
    n = xc.shape[0]
    W = tl.weights(n, fs)
    dry = dry_for(xc, output)
    acc = np.zeros((n + 20 * fs, dry.shape[1]))
    acc[:n] += (1 - settings.mix) * dry
    L = n
    for sid, w in W.items():
        st = states[sid]
        resp = cache.get(st.response_key)
        mics = _timeline_mics(st, resp, output)
        nrm = mix_norm(len(mics)) if output in ("mix_mono", "mix_stereo") else 1.0
        for m in mics:
            h = full_ir(resp.mics[m.id].ir, fs, resp.f_valid, st.render.band_strategy, st.render.seed)
            g = 10 ** (st.render.wet_gain_db / 20) * 10 ** (m.gain_db / 20)
            if tl.xfade == "input":
                y = convolve_channels(xc * w[:, None], h)
            else:
                y = convolve_channels(xc, h)
                wp = np.full(y.shape[0], w[-1]); wp[:n] = w
                y = y * wp[:, None]
            pl = place_layer(y * g, output, m.pan)
            acc[:pl.shape[0]] += settings.mix * nrm * pl
            L = max(L, pl.shape[0])
    return finish(acc[:L], n, fs, settings)


def test11_chunked_timeline_equals_full_and_uses_less_memory():
    import tracemalloc
    cache = ResponseCache()
    (a, b), _ = _ma_states(cache)
    states = {a.id: a, b.id: b}
    x = _t_tone(3.0)
    rs = RenderSettings(peak_protect=False, mix=0.7, duration="tail")
    for xf in ("input", "output"):
        for loop in (False, True):
            tl = Timeline([Keyframe(a.id, 0.2, 0.0), Keyframe(b.id, 1.4, 0.8, "equal_power"),
                           Keyframe(a.id, 2.4, 0.5, "smoothstep", 0.4)], xf, loop, 2.6 if loop else 0.0)
            for out in ("mix_mono", "mix_stereo", "mic:1"):
                y, _ = render_timeline(x, _T_FS, tl, states, cache, out, rs)
                yr, _ = _reference_timeline(x, _T_FS, tl, states, cache, out, rs)
                assert y.shape == yr.shape, (xf, loop, out, y.shape, yr.shape)
                assert np.abs(y - yr).max() <= 1e-9 * max(1.0, np.abs(yr).max()), (xf, loop, out)
    # memory: a 40 s source, input crossfade (the default)
    xl = _t_tone(40.0)
    tl = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(b.id, 20.0, 10.0)], "input")
    peaks = []
    for fn in (_reference_timeline, render_timeline):
        tracemalloc.start()
        fn(xl, _T_FS, tl, states, cache, "mix_stereo", rs)
        peaks.append(tracemalloc.get_traced_memory()[1])
        tracemalloc.stop()
    out_bytes = (len(xl) + 4 * _T_FS) * 2 * 8
    assert peaks[1] < 0.5 * peaks[0], peaks
    assert peaks[1] < 6 * out_bytes, (peaks, out_bytes)


def test12_render_main_is_the_single_code_path():
    """Preview, Render and the Praat automation all call render_main: the
    same inputs give identical output, the signature tracks every setting
    that changes it, and a preview slice IS the final render's slice."""
    cache = ResponseCache()
    st, r = _np_preset(cache)
    x = _t_tone(1.5)
    states = {st.id: st}
    tl = Timeline()
    rs = RenderSettings(mix=0.8)
    y1 = render_main(x, _T_FS, states, cache, tl, False, st, rs, "mix_stereo")[0]
    y2 = render_main(x, _T_FS, states, cache, tl, False, st, rs, "mix_stereo")[0]
    assert np.array_equal(y1, y2)
    i0, i1 = int(0.3 * _T_FS), int(0.9 * _T_FS)
    assert np.array_equal(y1[i0:i1], y2[i0:i1])
    sig = render_signature(x, states, tl, False, st, rs, "mix_stereo")
    assert sig == render_signature(x, states, tl, False, st, RenderSettings(mix=0.8), "mix_stereo")
    for change in (lambda: setattr(st.geometry.mics[0], "gain_db", 3.0),
                   lambda: setattr(st.geometry.mics[1], "pan", -1.0),
                   lambda: setattr(st.render, "wet_gain_db", -2.0),
                   lambda: setattr(st.render, "band_strategy", "attenuate")):
        change()
        s2 = render_signature(x, states, tl, False, st, rs, "mix_stereo")
        assert s2 != sig
        sig = s2
    assert render_signature(x, states, tl, False, st, RenderSettings(mix=0.5), "mix_stereo") != sig
    assert render_signature(x, states, tl, False, st, rs, "mix_mono") != sig
    # the region of the full render differs from rendering the region alone
    # (reverberation from earlier sound, whole-file peak protection) - which
    # is why previews slice the full render instead
    yr = render_main(x[i0:i1], _T_FS, states, cache, tl, False, st, rs, "mix_stereo")[0]
    assert not np.allclose(yr[:i1 - i0], y2[i0:i1])


def test13_cache_invalidates_only_what_changes_the_simulation():
    g = presets.build("narrow_passage")[0][0].geometry
    st = AcousticState("A", g)
    k0 = st.current_key()
    # rendering-only changes: same key, no recomputation
    for change in (lambda: setattr(g.mics[0], "gain_db", -6.0), lambda: setattr(g.mics[1], "pan", 0.9),
                   lambda: setattr(g.mics[2], "enabled", False), lambda: setattr(g.mics[0], "name", "renamed"),
                   lambda: setattr(g.elements[0], "id", "otherid"),
                   lambda: setattr(st.render, "wet_gain_db", 5.0), lambda: setattr(st.render, "band_strategy", "extend")):
        change()
        assert st.current_key() == k0
    # simulation changes: new key
    def changed(fn):
        s2 = st.duplicate()
        assert s2.current_key() == k0                 # a duplicate shares the response
        fn(s2)
        return s2.current_key() != k0
    assert changed(lambda s: setattr(s.geometry.elements[0], "x0", 1.95))
    assert changed(lambda s: setattr(s.geometry.elements[0], "alpha", 0.3))
    assert changed(lambda s: setattr(s.geometry, "source", (0.8, 1.2)))
    assert changed(lambda s: setattr(s.geometry.mics[0], "x", 3.1))
    assert changed(lambda s: setattr(s.geometry.mics[0], "id", "mNEW"))     # new microphone, same place
    assert changed(lambda s: setattr(s.geometry.boundary, "alpha", 0.2))
    assert changed(lambda s: setattr(s.sim, "quality", "High Resolution"))
    assert changed(lambda s: setattr(s.sim, "ir_length", 0.3))
    assert changed(lambda s: setattr(s.sim, "audio_fs", 44100))
    assert changed(lambda s: setattr(s, "correction_25d", False))
    # editing one state never invalidates another
    cache = ResponseCache()
    a, ra = _np_preset(cache)
    b = a.duplicate("B")
    assert b.status(cache) == "computed"
    b.geometry.mics[0].x += 0.2
    assert b.status(cache) == "outdated" and a.status(cache) == "computed"


def test14_output_levels_are_predictable():
    cache = ResponseCache()
    st, r = _np_preset(cache)
    x = 0.1 * np.random.default_rng(3).standard_normal((_T_FS, 1))       # broadband, stationary
    rs = RenderSettings(mix=1.0, peak_protect=False)
    mics = st.mic_settings()
    single = [rms_db(render_state(x, _T_FS, r, [m], rs, ("mono",))["mix_mono"][0]) for m in mics]
    for k in (1, 2, 3):
        ms = [MicSetting(m.id, m.name, i < k, m.gain_db, m.pan) for i, m in enumerate(mics)]
        mixdb = rms_db(render_state(x, _T_FS, r, ms, rs, ("mono",))["mix_mono"][0])
        # 1/sqrt(N): the mix stays at the power average of its layers (within 2 dB) instead of
        # growing with every added microphone
        avg = 10 * math.log10(np.mean([10 ** (v / 10) for v in single[:k]]))
        assert abs(mixdb - avg) < 2.0, (k, mixdb, avg)
    # mic gain moves exactly its own layer
    ms = [MicSetting(m.id, m.name, m.enabled, (6.0 if i == 0 else 0.0), m.pan) for i, m in enumerate(mics)]
    l0 = render_state(x, _T_FS, r, mics[:1], rs, ("mics",))[f"mic:{mics[0].id}"][0]
    l6 = render_state(x, _T_FS, r, ms[:1], rs, ("mics",))[f"mic:{mics[0].id}"][0]
    assert abs(rms_db(l6) - rms_db(l0) - 6.0) < 1e-6
    # peak protection is reported, and a large reduction is flagged
    hot = render_state(x * 20, _T_FS, r, mics, RenderSettings(mix=1.0), ("mono",))["mix_mono"]
    assert hot[1]["protect_gain_db"] < -6 and "WARNING" in level_report(hot[0], _T_FS, hot[1])
    calm = render_state(x * 0.01, _T_FS, r, mics, RenderSettings(mix=1.0), ("mono",))["mix_mono"]
    assert "protect_gain_db" not in calm[1] and "WARNING" not in level_report(calm[0], _T_FS, calm[1])


def test15_transitions_no_clicks_no_level_jumps_tails_kept():
    cache = ResponseCache()
    (a, b), _ = _ma_states(cache)
    states = {a.id: a, b.id: b}
    rng = np.random.default_rng(5)
    x = 0.1 * signal.lfilter([1.0], [1.0, -0.9], rng.standard_normal((int(3.0 * _T_FS), 1)), axis=0)
    rs = RenderSettings(mix=1.0, peak_protect=False, duration="tail")
    win = int(0.010 * _T_FS)

    def env_db(y):
        e = np.sqrt(np.mean(y[:len(y) // win * win, 0].reshape(-1, win) ** 2, axis=1))
        return 20 * np.log10(np.maximum(e, 1e-12))

    ya = render_timeline(x, _T_FS, Timeline([Keyframe(a.id, 0, 0)]), states, cache, "mix_mono", rs)[0]
    yb = render_timeline(x, _T_FS, Timeline([Keyframe(b.id, 0, 0)]), states, cache, "mix_mono", rs)[0]
    base_jump = max(np.abs(np.diff(env_db(ya)[10:-40])).max(), np.abs(np.diff(env_db(yb)[10:-40])).max())
    for xf in ("input", "output"):
        for curve in ("linear", "equal_power", "smoothstep"):
            tl = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(b.id, 1.8, 1.0, curve)], xf)
            y = render_timeline(x, _T_FS, tl, states, cache, "mix_mono", rs)[0]
            e = env_db(y)
            seg = slice(int(0.7 / 0.010), int(1.9 / 0.010))
            # no level jump: 10 ms envelope steps in the transition no larger than the
            # stationary renders' own fluctuation + 1 dB
            assert np.abs(np.diff(e[seg])).max() <= base_jump + 1.0, (xf, curve)
            # no click: largest sample step within that of the stationary renders, scaled by the
            # largest weight sum (equal power reaches sqrt 2 mid-transition)
            lim = max(np.abs(np.diff(ya[:, 0])).max(), np.abs(np.diff(yb[:, 0])).max())
            wsum = max(float(sum(tl.weights_at(np.array([t]), _T_FS)[s][0] for s in (a.id, b.id)))
                       for t in np.linspace(0.8, 1.8, 41))
            assert np.abs(np.diff(y[:, 0])).max() <= 1.05 * lim * wsum, (xf, curve)
    # hold: abrupt by design, but de-clicked
    tl = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(b.id, 1.8, 1.0, "hold")], "input")
    y = render_timeline(x, _T_FS, tl, states, cache, "mix_mono", rs)[0]
    lim = max(np.abs(np.diff(ya[:, 0])).max(), np.abs(np.diff(yb[:, 0])).max())
    assert np.abs(np.diff(y[:, 0])).max() <= 1.05 * lim
    # tails: the source stops BEFORE the transition; with the input crossfade the
    # output afterwards IS state A's natural decay (not cut), with the output
    # crossfade it is faded with A's weight
    xs = x.copy(); xs[int(1.0 * _T_FS):] = 0
    tl = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(b.id, 1.3, 0.2, "linear")], "input")
    y_in = render_timeline(xs, _T_FS, tl, states, cache, "mix_mono", rs)[0]
    y_a = render_timeline(xs, _T_FS, Timeline([Keyframe(a.id, 0, 0)]), states, cache, "mix_mono", rs)[0]
    t0, t1 = int(1.1 * _T_FS), int(1.5 * _T_FS)
    assert np.allclose(y_in[t0:t1], y_a[t0:t1], atol=1e-12)              # A's tail intact
    assert rms_db(y_a[t0:t1]) > rms_db(y_a[int(0.5 * _T_FS):int(0.9 * _T_FS)]) - 60
    # the output crossfade instead REPLACES A's tail by B's own reverberation of
    # the same earlier sound once the transition is over
    tl.xfade = "output"
    y_out = render_timeline(xs, _T_FS, tl, states, cache, "mix_mono", rs)[0]
    y_b = render_timeline(xs, _T_FS, Timeline([Keyframe(b.id, 0, 0)]), states, cache, "mix_mono", rs)[0]
    seg = slice(int(1.31 * _T_FS), t1)
    assert np.allclose(y_out[seg], y_b[seg], atol=1e-12)
    assert not np.allclose(y_out[seg], y_a[seg], atol=1e-6)
    # equal power between CORRELATED states bumps the level (by design, documented):
    # identical states -> +3 dB mid-transition with equal power, flat with linear
    a2 = a.duplicate("A copy")
    st2 = {a.id: a, a2.id: a2}
    for curve, bump in (("linear", 0.0), ("equal_power", 3.01)):
        tl = Timeline([Keyframe(a.id, 0.0, 0.0), Keyframe(a2.id, 1.8, 1.0, curve)], "input")
        y = render_timeline(x, _T_FS, tl, st2, cache, "mix_mono", rs)[0]
        d = rms_db(y[int(1.25 * _T_FS):int(1.35 * _T_FS)]) - rms_db(ya[int(1.25 * _T_FS):int(1.35 * _T_FS)])
        assert abs(d - bump) < 0.5, (curve, d)


# ---------------------------------------------------------------- extras


def _wall_absorption(alpha):
    s = SimSettings("Draft", ir_length=0.03)
    dx = s.resolved_dx()
    H = 3 * dx
    g = Geometry(8.0, H, [Element("rect", 7.0, -1, 9, 2, alpha=alpha)], (1.0, H / 2),
                 [Mic(4.0, H / 2, "M")], Boundary("rigid", 0))
    resp = build_response(simulate(g, s, store_frames=False), "k" * 20, _T_C, correction_25d=False)
    h = _t_ir_of(resp, g)
    w = int(0.004 * _T_FS)
    inc = h[int(3 / _T_C * _T_FS) - w:int(3 / _T_C * _T_FS) + w]
    ref = h[int(9 / _T_C * _T_FS) - w:int(9 / _T_C * _T_FS) + w]
    f = np.fft.rfftfreq(4096, 1 / _T_FS)
    band = (f > 100) & (f < 0.8 * resp.f_valid)
    R = np.median(np.abs(np.fft.rfft(ref, 4096))[band] / np.abs(np.fft.rfft(inc, 4096))[band])
    assert abs(R - math.sqrt(1 - alpha)) < 0.02


def test_extra_wall_absorption_is_calibrated():
    for alpha in (0.2, 0.5, 0.8):
        _wall_absorption(alpha)


def test_extra_pml_reflection_is_small():
    def h(W, Hh, src, mic):
        g = Geometry(W, Hh, [], src, [Mic(*mic)], Boundary("absorbing", 0))
        return _t_ir_of(_t_response(g, ir_length=0.04), g)
    a = h(2.0, 2.0, (0.6, 1.0), (1.6, 1.0))
    b = h(8.0, 8.0, (3.6, 4.0), (4.6, 4.0))
    assert 20 * math.log10(np.abs(a - b).max() / np.abs(b).max()) < -50


def test_extra_cancellation_raises_and_leaves_no_result():
    g = presets.build("labyrinth")[0][0].geometry
    calls = {"n": 0}

    def cancel():
        calls["n"] += 1
        return calls["n"] > 3
    with _raises(Cancelled):
        simulate(g, SimSettings("Draft"), cancel=cancel)


def test_extra_instability_is_detected():
    g = Geometry(1.0, 0.7, [], (0.23, 0.17), [Mic(0.81, 0.53)], Boundary("rigid", 0))
    real = make_plan

    def bad_plan(geom, s):
        p = real(geom, s)
        p.dt *= 1.6                      # violate the Courant limit on purpose
        return p
    globals()["make_plan"] = bad_plan    # simulate() looks make_plan up at call time
    try:
        with _raises(SimulationError):
            simulate(g, SimSettings("Draft", ir_length=0.3), store_frames=False)
    finally:
        globals()["make_plan"] = real


def test_extra_invalid_geometry():
    g = Geometry(2, 2, [Element("rect", 0.5, 0.5, 1.5, 1.5)], (1.0, 1.0), [Mic(0.2, 0.2)],
                 Boundary("rigid", 0))
    with _raises(GeometryError):
        simulate(g, SimSettings("Draft", ir_length=0.05))
    # microphone sealed in a closed box: warning, not a misleading response
    g = Geometry(2, 2, [Element("wall", 1.2, 1.2, 1.8, 1.2), Element("wall", 1.2, 1.8, 1.8, 1.8),
                        Element("wall", 1.2, 1.2, 1.2, 1.8), Element("wall", 1.8, 1.2, 1.8, 1.8)],
                 (0.4, 0.4), [Mic(1.5, 1.5, "sealed"), Mic(0.8, 0.4, "open")], Boundary("rigid", 0))
    rep = check(g, rasterize(g, 0.03))
    assert not rep.errors and any("no air path" in w for w in rep.warnings)
    assert rep.mic_connected[g.mics[0].id] is False
    with _raises(GeometryError):
        Geometry.from_dict({"width": "4", "height": 3})


def test_extra_states_outdated_and_project_roundtrip():
    cache = ResponseCache()
    (a, b), tl = _ma_states(cache)
    assert a.status(cache) == "computed"
    a.geometry.elements[1].y1 += 0.1
    assert a.status(cache) == "outdated"            # stale response is flagged
    a.geometry.elements[1].y1 -= 0.1
    assert a.status(cache) == "computed"            # and valid again when restored
    p = project.Project(states=[a, b], current_state=a.id, timeline=tl)
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "projet é 1.amcproj")      # spaces + non-ASCII
        project.save(p, path, cache)
        p2, cache2, notes = project.load(path)
        assert [s.name for s in p2.states] == [a.name, b.name]
        for s in p2.states:
            assert s.status(cache2) == "computed"
            r1, r2 = cache.get(s.response_key), cache2.get(s.response_key)
            for mid in r1.mics:
                assert np.array_equal(r1.mics[mid].ir, r2.mics[mid].ir)
        assert len(p2.timeline.keyframes) == 3
        # tampering with the geometry in the file marks the state outdated
        import json
        doc = json.load(open(path, encoding="utf-8"))
        doc["states"][0]["geometry"]["elements"][1]["y1"] += 0.2
        json.dump(doc, open(path, "w", encoding="utf-8"))
        p3, cache3, notes3 = project.load(path)
        assert p3.states[0].status(cache3) == "outdated"
        assert any("outdated" in n for n in notes3)
        # malformed project is refused, not half-loaded
        doc["states"][0]["geometry"]["width"] = -1
        json.dump(doc, open(path, "w", encoding="utf-8"))
        with _raises(project.ProjectError):
            project.load(path)


def test_extra_geometry_morph_mode2():
    (a, b), _ = presets.build("moving_aperture")
    mids = geometry_morph(a.geometry, b.geometry, 3)
    ws = [abs(g.elements[1].y1 - g.elements[1].y0) for g in mids]
    assert ws[0] > ws[1] > ws[2]
    other = presets.build("labyrinth")[0][0]
    with _raises(GeometryError):
        geometry_morph(a.geometry, other.geometry, 2)


def test_extra_all_presets_simulate():
    for key in presets.preset_keys():
        sts, _ = presets.build(key)
        for st in sts:
            r = simulate(st.geometry, SimSettings("Draft", ir_length=0.1), store_frames=False)
            assert all(np.all(np.isfinite(v)) for v in r.mic_signals.values())


def test8c_partial_keyframe_amounts():
    """'A -> B 100 % -> _T_C 40 % -> A' style curves: a keyframe may reach its
    state only partly; the plateau mixture and the sum rule must hold."""
    fs = 1000
    tl = Timeline([Keyframe("A", 0.0, 0.0, "linear"),
                   Keyframe("B", 2.0, 1.0, "linear", 1.0),
                   Keyframe("C", 4.0, 1.0, "linear", 0.4),
                   Keyframe("A", 6.0, 1.0, "linear", 1.0)], "input")
    V = tl.targets()
    assert V[1] == {"B": 1.0}
    assert abs(V[2]["B"] - 0.6) < 1e-12 and abs(V[2]["C"] - 0.4) < 1e-12
    assert V[3] == {"A": 1.0}
    W = tl.weights(7000, fs)
    at = lambda sid, t: W[sid][int(t * fs)]
    assert abs(at("B", 4.5) - 0.6) < 1e-9 and abs(at("C", 4.5) - 0.4) < 1e-9 and at("A", 4.5) == 0
    tot = sum(W.values())
    assert np.allclose(tot, 1.0, atol=1e-9)            # linear curves preserve the sum everywhere
    # shared weight is held during a transition: B stays >= 0.6 while moving to 60/40
    assert W["B"][int(3.0 * fs):int(4.0 * fs)].min() >= 0.6 - 1e-9
    # equal power on the exchanged part only: no bump on the shared component
    tl2 = Timeline([Keyframe("A", 0.0, 0.0), Keyframe("B", 2.0, 2.0, "equal_power", 0.4)])
    W2 = tl2.weights(3000, fs)
    assert W2["A"].min() >= 0.6 - 1e-9 and W2["A"].max() <= 1.0 + 1e-9
    ex_power = (W2["A"] - 0.6) ** 2 + W2["B"] ** 2       # exchanged 0.4 crossfades at constant power
    assert np.allclose(ex_power[:2000], 0.16, atol=1e-9)
    # amount is saved and validated
    d = tl.to_dict()
    assert Timeline.from_dict(d, ["A", "B", "C"]).keyframes[2].amount == 0.4
    d["keyframes"][2]["amount"] = 1.5
    with _raises(ValueError):
        Timeline.from_dict(d, ["A", "B", "C"])


# ============================================================================
# SELF-TEST: GUI SCENARIO  (run by --selftest, offscreen)
# ============================================================================
def _gui_scenario(win, app, OUT):
    """GUI scenario self-test: drives the real main window with synthetic
    mouse and keyboard events and checks the model after each step.  Writes
    OUT/scenario.log ending in "SCENARIO PASSED" or "SCENARIO FAILED"."""
    from PySide6.QtTest import QTest
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    LOG = open(os.path.join(OUT, "scenario.log"), "w", encoding="utf-8")
    FAILS = []

    # modal dialogs would block the scenario: answer them automatically
    _answers = []
    QtWidgets.QMessageBox.question = staticmethod(lambda *a, **k: (_answers.append(a[2] if len(a) > 2 else ""),
                                                                QtWidgets.QMessageBox.Yes)[1])
    QtWidgets.QMessageBox.information = staticmethod(lambda *a, **k: _answers.append(a[2] if len(a) > 2 else ""))
    QtWidgets.QMessageBox.warning = staticmethod(lambda *a, **k: _answers.append("WARNING " + (a[2] if len(a) > 2 else "")))
    QtWidgets.QMessageBox.critical = staticmethod(lambda *a, **k: _answers.append("CRITICAL " + (a[2] if len(a) > 2 else "")))


    def L(*a):
        print(*a, file=LOG, flush=True)


    def check(cond, what):
        L(("PASS " if cond else "FAIL ") + what)
        if not cond:
            FAILS.append(what)


    def shot(name):
        win.grab().save(os.path.join(OUT, name + ".png"))


    ed = win.editor


    def vp_point(x, y):
        """Model metres -> editor viewport pixel."""
        return ed.mapFromScene(ed.to_scene(x, y))


    def drag(x0, y0, x1, y1, steps=6):
        p0, p1 = vp_point(x0, y0), vp_point(x1, y1)
        QTest.mousePress(ed.viewport(), QtCore.Qt.LeftButton, QtCore.Qt.NoModifier, p0)
        for k in range(1, steps + 1):
            q = p0 + (p1 - p0) * (k / steps)
            QTest.mouseMove(ed.viewport(), q)
        QTest.mouseRelease(ed.viewport(), QtCore.Qt.LeftButton, QtCore.Qt.NoModifier, p1)


    def click(x, y):
        QTest.mouseClick(ed.viewport(), QtCore.Qt.LeftButton, QtCore.Qt.NoModifier, vp_point(x, y))


    def tool(t):
        ed.set_tool(t)


    steps = []


    def step(fn, delay=200):
        steps.append((fn, delay))


    def wait_idle():
        def f():
            if win.runner.busy or win.prev_runner.busy:
                steps.insert(0, (f, 300))
        return f

    pv = {}

    def s_preview_async():
        win._main_cache = None
        win.region.setRegion((1.0, 2.5))
        t0 = time.perf_counter()
        win.play_processed()
        dt = time.perf_counter() - t0
        check(dt < 0.3 and win.prev_runner.busy, f"Preview starts a background render and returns at once ({dt * 1000:.0f} ms)")
        check(not win.runner.busy, "the compute/render worker stays free during a preview")

    def s_preview_done():
        c = win._main_cache
        check(c is not None, "preview render finished and cached")
        if c is not None:
            i0, i1 = win._region()
            pv["slice"] = c[1][i0:i1].copy()
            pv["range"] = (i0, i1)
        win._main_cache = None             # force the final render to compute independently
        win.target.setCurrentIndex(0)
        win.use_tl.setChecked(False)
        win.render()

    def s_preview_equals_render():
        outs = win.last_render
        if outs and "slice" in pv:
            i0, i1 = pv["range"]
            y = outs[0][2]
            check(np.array_equal(y[i0:i1], pv["slice"]),
                  "preview of a region == the same region of the final render (sample-identical)")
        else:
            check(False, "preview/render comparison ran")
        win.use_tl.setChecked(True)


    def run_steps():
        if not steps:
            finish()
            return
        fn, d = steps.pop(0)
        try:
            fn()
        except Exception:
            FAILS.append("exception")
            L("ERROR " + traceback.format_exc())
        QtCore.QTimer.singleShot(d, run_steps)


    def finish():
        L("dialog texts: " + json.dumps(_answers[-8:])[:2000])
        L("SCENARIO " + ("PASSED" if not FAILS else f"FAILED ({len(FAILS)}): " + "; ".join(FAILS)))
        LOG.close()
        win.returned = True                 # skip the close confirmation
        app.quit()


    # ------------------------------------------------------------------ scenario
    def s_load():
        win.resize(1500, 950)
        src = os.path.join(OUT, "synthetic_cello_G2.wav")
        y, fs = synthetic_cello(6.0, 48000)
        sf.write(src, y, fs, subtype="PCM_24")
        win.load_source(src)
        win.load_preset("resonant_chamber", replace=True)
        win.quality.setCurrentText("Draft")
        win.irlen.setValue(0.4)
        check(win.x is not None and win.fs == 48000, "source loaded (48 kHz)")
        check(win.cur().name == "Resonant Chamber", "preset loaded")


    def s_room_bigger():
        # make room for drawing: room 3 x 2 m (properties panel path = editor.edit)
        g = win.cur().geometry
        ed.edit(lambda: (setattr(g, "width", 3.0), setattr(g, "height", 2.0)), "room size")
        ed.fit()
        check(abs(g.width - 3.0) < 1e-9, "room resized")


    def s_draw():
        g = win.cur().geometry
        n0 = len(g.elements)
        tool("wall"); drag(1.6, 0.0, 1.6, 1.4)
        check(len(g.elements) == n0 + 1 and g.elements[-1].kind == "wall", "wall drawn by dragging")
        w = g.elements[-1]
        check(abs(w.x0 - 1.6) < 1e-6 and abs(w.y1 - 1.4) < 1e-6, f"wall snapped to grid ({w.x0:.3f},{w.y0:.3f})-({w.x1:.3f},{w.y1:.3f})")
        tool("rect"); drag(2.3, 1.3, 2.6, 1.6)
        check(g.elements[-1].kind == "rect", "obstacle drawn")
        tool("opening"); drag(1.5, 0.6, 1.7, 0.9)
        check(g.elements[-1].kind == "opening", "opening drawn")
        tool("source"); click(0.5, 0.5)
        check(abs(g.source[0] - 0.5) < 1e-6 and abs(g.source[1] - 0.5) < 1e-6, "source placed")
        nm = len(g.mics)
        tool("mic"); click(2.6, 0.6)
        check(len(g.mics) == nm + 1, "microphone added")
        shot("10_drawn")


    def s_move_resize():
        g = win.cur().geometry
        tool("select")
        m = g.mics[-1]
        drag(m.x, m.y, 2.7, 0.4)
        check(abs(m.x - 2.7) < 1e-6 and abs(m.y - 0.4) < 1e-6, f"mic moved to ({m.x:.2f},{m.y:.2f})")
        r = [e for e in g.elements if e.kind == "rect"][-1]
        click(2.45, 1.45)                               # select the obstacle
        check(win.editor.sel and win.editor.sel[1] == r.id, "obstacle selected")
        drag(2.6, 1.6, 2.8, 1.8)                        # top-right handle -> resize
        check(abs(r.x1 - 2.8) < 1e-6 and abs(r.y1 - 1.8) < 1e-6, f"obstacle resized to x1={r.x1:.2f} y1={r.y1:.2f}")
        drag(2.5, 1.5, 2.3, 1.2)                        # body -> move
        check(abs(r.x0 - 2.1) < 1e-6, f"obstacle moved (x0={r.x0:.2f})")


    def s_delete_undo():
        g = win.cur().geometry
        n = len(g.elements)
        r = [e for e in g.elements if e.kind == "rect"][-1]
        ed.select(("element", r.id))
        QTest.keyClick(ed.viewport(), QtCore.Qt.Key_Delete)
        check(len(g.elements) == n - 1, "obstacle deleted with Delete")
        win.undo_act.trigger()
        check(len(g.elements) == n, "undo restores it")
        win.redo_act.trigger()
        check(len(g.elements) == n - 1, "redo deletes it again")
        win.undo_act.trigger()


    def s_zoom_snap():
        t0 = ed.transform().m11()
        ev_pos = QtCore.QPointF(ed.viewport().width() / 2, ed.viewport().height() / 2)
        we = QtWidgets.QWidget  # noqa
        wheel = QtGui.QWheelEvent(ev_pos, ed.mapToGlobal(ev_pos.toPoint()), QtCore.QPoint(0, 0), QtCore.QPoint(0, 240),
                                  QtCore.Qt.NoButton, QtCore.Qt.NoModifier, QtCore.Qt.NoScrollPhase, False)
        QtWidgets.QApplication.sendEvent(ed.viewport(), wheel)
        check(ed.transform().m11() > t0 * 1.3, "wheel zooms in")
        ed.fit()
        win.snap.setChecked(False)
        g = win.cur().geometry
        tool("mic"); click(0.913, 1.777)
        check(abs(g.mics[-1].x - 0.913) < 0.01 and abs(g.mics[-1].x - 0.9) > 0.004 or len(g.mics) == 4,
              f"snap off: free position ({g.mics[-1].x:.3f})")
        win.snap.setChecked(True)
        tool("select")
        # geometry save / load round trip
        p = os.path.join(OUT, "g.amcgeom")
        projmod.save_geometry(g, p)
        g2 = projmod.load_geometry(p)
        check(json.dumps(g2.to_dict(), sort_keys=True) == json.dumps(g.to_dict(), sort_keys=True),
              "geometry save/load round trip")


    def s_compute():
        check(win.cur().status(win.cache) == "none", "state not computed before Compute")
        win.compute_current()
        check(win.runner.busy, "compute runs in the background (GUI thread free)")
        # the editor stays usable while computing
        g = win.cur().geometry
        ed.edit(lambda: None, "noop")


    def s_after_compute():
        st = win.cur()
        check(st.status(win.cache) == "computed", f"state computed ({st.status(win.cache)})")
        win.rtabs.setCurrentIndex(0)
        shot("11_fingerprint")
        win.rtabs.setCurrentIndex(1)
        win.wave.slider.setValue(min(60, win.wave.slider.maximum()))
        shot("12_wavefield")
        win.rtabs.setCurrentIndex(2)
        shot("13_measurements")


    def s_stale():
        st = win.cur()
        g = st.geometry
        op = [e for e in g.elements if e.kind == "opening"][-1]
        ed.edit(lambda: setattr(op, "y1", 1.1), "widen opening")
        check(st.status(win.cache) == "outdated", "geometry edit marks the response OUTDATED")
        win.rtabs.setCurrentIndex(0)
        shot("14_outdated")
        try:
            render_main(*win._main_args(False))
            check(False, "stale response refused for preview/render")
        except ValueError:
            check(True, "stale response refused for preview/render")
        win.undo_act.trigger()
        check(st.status(win.cache) == "computed", "undo makes it current again (same geometry, cached)")


    def s_store_b():
        a = win.cur()
        win.store_state(ask=False)
        b = win.project.states[-1]
        win.set_current(b.id)
        b.name = "Chamber B"
        g = b.geometry
        w = [e for e in g.elements if e.kind == "wall"][-1]
        ed.edit(lambda: (setattr(w, "x0", 1.2), setattr(w, "x1", 1.2)), "move the dividing wall")
        op = [e for e in g.elements if e.kind == "opening"][-1]
        ed.edit(lambda: (setattr(op, "x0", 1.1), setattr(op, "x1", 1.3)), "move the opening with it")
        check(b.status(win.cache) != "computed" and a.status(win.cache) == "computed",
              "editing B leaves A's response intact")
        win.compute_current()


    def s_compare():
        a, b = win.project.states[0], win.project.states[-1]
        check(b.status(win.cache) == "computed", "state B computed")
        win.cmp.set_states(win.project.states, win.cache)
        for i in range(win.cmp.list.count()):
            win.cmp.list.item(i).setCheckState(QtCore.Qt.Checked)
        win.rtabs.setCurrentWidget(win.cmp)
        shot("15_compare")
        check("RMS" in win.cmp.d.plotItem.titleLabel.text, "difference plot shows an RMS difference")


    def s_timeline():
        a, b = win.project.states[0], win.project.states[-1]
        win.btabs.setCurrentWidget(win.tlp)
        tl = win.project.timeline
        tl.keyframes = []
        win.set_current(a.id); win.add_keyframe(0.0)
        win.set_current(b.id); win.tlp.trans.setValue(1.5); win.add_keyframe(2.5)
        win.set_current(a.id); win.tlp.amount.setValue(40); win.add_keyframe(4.5)
        check(len(tl.keyframes) == 3 and abs(tl.sorted()[2].amount - 0.4) < 1e-9, "keyframes incl. a 40 % one")
        win.undo_act.trigger()
        check(len(win.project.timeline.keyframes) == 2, "undo removes the last keyframe")
        win.redo_act.trigger()
        check(len(win.project.timeline.keyframes) == 3, "redo restores it")
        shot("16_timeline")
        win.target.setCurrentIndex(0)                # stereo mix
        win.render()


    def s_render_check():
        outs = win.last_render
        check(outs is not None, "timeline render produced output")
        if outs:
            kind, name, y, fs, desc, info = outs[0]
            check(y.shape[0] == win.x.shape[0] and y.shape[1] == 2, f"render length == source, stereo ({y.shape})")
            check(np.all(np.isfinite(y)) and np.abs(y).max() <= 10 ** (-1 / 20) + 1e-6, "finite, peak <= -1 dBFS")
            check(any(o[0] == "ir" for o in outs), "impulse responses included")
        shot("17_rendered")


    def s_project_roundtrip():
        p = os.path.join(OUT, "scenario.amcproj")
        projmod.save(win.project, p, win.cache)
        n_states = len(win.project.states)
        keys = [s.response_key for s in win.project.states]
        win.open_project_path(p)
        check(len(win.project.states) == n_states, "project reopened with all states")
        check([s.status(win.cache) for s in win.project.states].count("computed") == len(
            [k for k in keys if k]), "cached responses restored, nothing silently recomputed")
        check(len(win.project.timeline.keyframes) == 3, "timeline restored")


    def s_auto_compute_start():
        win.load_preset("moving_aperture", replace=True)
        win.quality.setCurrentText("Draft")
        for st_ in win.project.states:
            st_.sim.quality = "Draft"; st_.sim.ir_length = 0.3
        win.use_tl.setChecked(True)
        win.last_render = None
        n_q = len(_answers)
        win.render()                                   # states not computed: asks, answer = Yes
        check(len(_answers) > n_q and "no up-to-date response" in _answers[-1],
              "Render with uncomputed timeline states offers to compute them")
        check(win.runner.busy, "...and starts computing")

    def s_auto_compute_done():
        check(all(st_.status(win.cache) == "computed" for st_ in win.project.states),
              "all timeline states computed")
        check(win.last_render is not None and win.last_render[0][1].endswith("acoustic_morphology"),
              "the render continued automatically afterwards")

    def s_close():
        shot("18_final")


    for fn in (s_load, s_room_bigger, s_draw, s_move_resize, s_delete_undo, s_zoom_snap, s_compute, wait_idle(),
               s_after_compute, s_preview_async, wait_idle(), s_preview_done, wait_idle(), s_preview_equals_render,
               s_stale, s_store_b, wait_idle(), s_compare, s_timeline, wait_idle(),
               s_render_check, s_project_roundtrip, s_auto_compute_start, wait_idle(), wait_idle(),
               wait_idle(), s_auto_compute_done, s_close):
        step(fn, 250)
    QtCore.QTimer.singleShot(400, run_steps)


# ============================================================================
# MANUAL  (Help in the window; --manual on the command line)
# ============================================================================
MANUAL = r"""# Acoustic Morphology Composer
### Geometry-Driven Spectral Transformation and Spatial Resynthesis

*Praat AudioTools — Hybrid Systems · Shai Cohen, Department of Music,
Bar-Ilan University · MIT License · v1.2 (2026)*

> **Draw the space. Shape the sound. Compose its transformation.**

You draw a two-dimensional acoustic space: walls, obstacles, openings, one
sound source and up to four microphones. A finite-difference time-domain
(FDTD) wave simulation computes how that space responds at each microphone,
and those responses filter your recording. Nothing in the filtering is an
equalizer curve: every resonance, notch and decay comes from the simulated
geometry. Spaces are stored as *acoustic states*, compared, and sequenced on a
timeline, so the geometry itself becomes an evolving transformation of the
sound.

What is simulated, how accurately, and where simulation ends and creative
processing begins is documented in **Part 2 of this manual (the acoustic model)**.

---

## 1. Installation

**Two files**, both in `plugin_AudioTools/py/` like the other hybrid tools:

```
py/Acoustic_Morphology_Composer.praat     Praat launcher (appears in AudioTools - py)
py/acoustic_morphology_composer.py        the whole application: acoustic core, GUI,
                                          this manual, examples and self-test
```

**Python 3.9 or newer** with:

```
python -m pip install PySide6 numpy scipy soundfile pyqtgraph sounddevice
```

| Package | Purpose |
|---|---|
| PySide6 | GUI |
| numpy | solver |
| scipy | signal processing |
| soundfile | audio files |
| pyqtgraph | plots |
| sounddevice | *optional:* audition (playback). Rendering and returning to Praat work without it. |

**Telling Praat which Python to use.** The launcher looks for Python in this
order:
1. the environment named at the top of `Acoustic_Morphology_Composer.praat`
   (`pyCandidate1$`, e.g. your existing `praat_ddsp_env`);
2. `python`, `py` or `python3` on Windows (`python3` / `python` elsewhere).

Each candidate is probed for the required modules. The first one that has
them all is used. If none qualifies, the error lists each candidate with the
modules it is missing.

**Praat 6.x and 7.x.** Praat 7.0 gates file writing and subprocesses behind
*full trust*. The launcher asks with Praat's own dialog (`askForTrust()`) on
7.0+ only. Tested on 6.4.06, 6.4.63 and 7.0.

## 2. Workflow

1. In Praat, select **one Sound** (mono or stereo) and run
   **AudioTools - py → Acoustic_Morphology_Composer**. Praat waits while the
   composer window is open.
2. Draw or pick a geometry: **Presets**, or the drawing tools.
3. Press **Compute**. The simulation runs in the background with a progress
   bar and **Cancel**, and the editor stays usable.
4. Audition in **Source & audition**: Play original / Play processed / A/B,
   with a listening region, bypass and matched level. A preview is rendered
   in the background and is exactly the corresponding part of what **Render**
   will produce with the same settings (only *matched level* is audition-only).
5. Store more states, sequence them on the **Timeline**, and preview.
6. **Render** (the **Render** tab sets dry/wet, trim, duration, channels, main
   output and the IR/layer exports).
7. **Return to Praat**. The results appear as new Sound objects. Closing the
   window without returning imports nothing.

**Objects returned to Praat.** Names are made unique with `_2`, `_3` … if an
object of that name already exists:

| Object | Content |
|---|---|
| `<source>_acoustic_morphology` | the render (single state or timeline) |
| `Acoustic_IR_A_<mic>`, `Acoustic_IR_B_<mic>` … | impulse responses of the states used (A = first state on the timeline …) |
| `<source>_layer_<mic>` | one render per microphone of the current state (if "Export microphone layers") |

The original Sound is never modified. The Info window reports every imported
object and whether the source duration was preserved, to the sample.

The application also runs **standalone** (`python acoustic_morphology_composer.py`)
with **Load source…** and **Export WAVs…** in place of the Praat session.

## 3. The window

**Top toolbar**
* Open/Save project and **Presets** (with *Reset preset*).
* **Quality** with response length, and the **2.5-D** correction.
* **Compute** / **Cancel**, **Preview**, **Store state**, **Render**,
  **Return to Praat**.
* **Undo/Redo**: geometry and timeline edits, in the order made.
* **Workflow** selector and **Help**.

**Left — geometry editor**

| Tool | Action |
|---|---|
| Select | Click to select. Drag to move. Drag a handle to resize or move wall ends. **Delete** removes. **Esc** deselects. |
| Wall | Press–drag a segment. Thickness and absorption are in the properties. |
| Obstacle | Press–drag a solid rectangle. |
| Opening | Press–drag a rectangle that is forced to air, cutting doors and slits through walls and obstacles. |
| Source | Click to place the single source. |
| Mic | Click to add (up to 4). Drag to move. |
| Pan | Drag to pan (the middle mouse button pans in any tool). The wheel zooms. |

* **View aids:** snap and grid step, grid display, **sim. cells** (the solver's
  actual solid cells, i.e. staircasing), **Fit**, **Clear**, **Load/Save geom.**
  A scale bar in metres is always shown.
* **Properties panel:** numeric editing of the selection, or of the room when
  nothing is selected. This covers size, the boundary (*rigid*, *partial* with
  α, or *absorbing* = open field), and each microphone's name, enabled state,
  output gain and stereo pan.

**Right — analysis**
* **Acoustic fingerprint.** The impulse response, frequency response (the
  unmodelled band is shaded, resonant peaks are marked) and an energy decay
  curve, a spectrogram or the phase. Choose **Physical level** (one absolute
  scale: transmission differences stay visible) or **Normalized timbre** (shape
  only).
* **Wavefield.** The solver's own pressure field over time: play/pause, step,
  speed, pressure scale, freeze, and show/hide geometry and microphones. It is
  a diverging map: red is positive, blue negative, white zero.
* **Measurements.**
  * Per microphone: distance, first arrival (with the geometric value), level,
    centroid, EDT/T20/T30, resonant peaks, notches and energy distribution.
  * The plan: grid, bandwidth and cost.
  * Every warning.
* **Compare states.** Overlaid responses of chosen states, their difference
  with its RMS, and a table of levels, centroids, decays and peaks.

**Bottom.** *States* (store, duplicate, *new listener state*, rename, delete,
recompute, compute all outdated, compare) · *Timeline* · *Source & audition* ·
*Render*.

## 4. Acoustic states

A state stores its geometry, source, microphones, boundary, simulation
settings, render settings (wet gain, high-band strategy), name and notes, and
a reference to its computed response. Each state has a status:

* **computed** — the response matches the current geometry and settings;
* **OUTDATED** — edited after computing. The old curves stay visible with a
  warning banner, but they are **never used** for audition or rendering until
  you recompute;
* **not computed.**

Responses are cached by a hash of everything that affects the acoustics:
geometry, positions, boundary, grid, length and correction. As a result:

* undoing an edit makes a state current again without recomputing;
* identical states share one response;
* editing one state never invalidates another.

Microphone gain, pan and enabled state do not affect the simulation (all
microphones are always simulated), so changing them never forces a recompute.

## 5. Timeline and morphing

* **Add keyframe** places the current state at the cursor. Each keyframe has
  a time, a transition length before it, a curve, and an **amount**.
  * Curves: linear / equal power / smoothstep / hold.
  * Amount: 100 % = that state alone; 40 % = 40 % of it mixed with the
    previous mixture.
* **Editing keyframes:** drag a keyframe or its transition edge,
  double-click to edit, right-click for state/curve/delete.
* **Loop** repeats the pattern, with a smooth wrap.
* The drawn weight curves are computed by the same code that renders.

**Input crossfade** (default) splits the recording between states before
convolution, so each state's reverberation tail rings out. **Output
crossfade** crossfades the finished renders. Both are *Mode 1: output
morphing* — mixes of static spaces, not moving walls.

**Geometry morph… (Mode 2)** generates intermediate geometries between two
states whose elements correspond (make B by duplicating A and editing it).
It simulates each one and sequences them. It costs one simulation per step.

## 6. Presets

Each preset is a real geometry and stays editable. The tendencies below were
measured from the presets' own simulations at Standard quality. Edits and
numerical settings change them; the presets describe tendencies, not fixed
filter curves.

| Preset | Geometry | Tendency |
|---|---|---|
| 1 Open Field | no walls, absorbing (PML) edges | reference: direct sound only, flat in band, −3 dB per distance doubling |
| 2 Resonant Chamber | 1.4 × 1.0 m, α 0.06 | strong sparse 2-D room modes (123, 172, 211 Hz …), rings after the note, 15–18 dB louder than free field |
| 3 Narrow Passage | wall with a 10 cm slot, α 0.5 | far quieter behind the slot; low harmonics lost most; the receiving room's modes colour it |
| 4 Parallel Walls | two long reflecting walls, faces 1.14 m apart | flutter comb, 150 Hz spacing; the centred source excites every second tooth (~300 Hz) |
| 5 Side Cavity | corridor + closed side chamber via a neck | Helmholtz-type side resonance (~50 Hz) in both microphones; cavity modes and slower decay inside |
| 6 Acoustic Labyrinth | staggered internal walls | dense, long, irregular response; far-end onset ~24 ms instead of 10 ms straight-line |
| 7 Moving Aperture | two states: 60 cm / 8 cm opening + timeline | narrowing attenuates about 4–8 dB and re-weights the coupled modes; Mode 2 ready |
| 8 Dual Chamber | small + L-shaped large chamber, doorway | different resonance sets per microphone, one shared slow coupled decay |

## 7. Five ways of working (Workflow menu)

* **A Resonance Sculpting:** one geometry as a resonant filter. Best for
  sustained tones, drones and synthesis.
* **B Acoustic Morphing:** several states on the timeline. Suits long
  transformations and form.
* **C Moving Listener:** *New listener state* copies the geometry and source.
  Move only the microphones, then sequence the copies. Every position is
  simulated.
* **D Resonant Counterpoint:** several microphones as related layers. Render
  the stereo mix, or export each microphone as its own layer.
* **E Spectral Architecture:** design contrasting geometries and decide with
  the **Compare** tab, using response plots, differences, resonance locations
  and relative levels.

## 8. Rendering options

* **Dry/wet**, **wet gain** (per state), **output trim**.
* **Mixing rules** (identical for single states, timelines, previews):
  * the dry signal enters every output **once**;
  * microphone gain and pan act on that microphone's wet layer only;
  * the mono and stereo mixes of N microphones are scaled by 1/√N, so adding
    a microphone keeps the mix power about constant;
  * a mono source is equal-power centred in stereo (−3 dB per channel).
* **Peak protection:** a static gain to the ceiling, not a limiter. The
  render report shows the peak before protection and the gain applied, and
  warns when more than 6 dB had to be removed: lower the wet gain or trim
  instead of relying on protection.
* **Duration:** *preserve* (exact source length) or *include reverberation
  tail*.
* **Stereo sources:**
  * mix to mono;
  * each channel;
  * left only;
  * right only.
* **Main output:**
  * stereo mix (microphone pans);
  * mono mix;
  * microphone 1–4.
* **Above the band** (per state):
  * *Preserve*: dry and unsimulated;
  * *Attenuate*;
  * *Creative extension*: artistic, not physics.

  See Part 2, section 9.

Responses are on a physical scale (0 dB = 2-D free field at 1 m), so a closed
resonant room really is louder than an open field. Use wet gain or peak
protection for the final level. Audition can use **matched level** to compare
timbre rather than loudness.

## 9. Projects

`File.amcproj` (JSON) plus `File_cache/<key>.npz` (impulse responses).

* **Contents:** states, timeline, render and output settings, the source
  reference (absolute and project-relative) and cache metadata.
* **Loading** validates every field, reads arrays with `allow_pickle=False`,
  and attaches a cached response only to a state whose *current* geometry and
  settings hash to the same key.
* **Moved source audio:** if the source is missing, it is looked for relative
  to the project, then you are offered **relink**.

**Example:** `python acoustic_morphology_composer.py --make-example DIR` writes
`example_moving_aperture.amcproj` into DIR: two geometries (60 cm and 8 cm
aperture), one source, two microphones and a timeline A → B → A (60 %),
already computed, using a synthetic tone `synthetic_cello_G2.wav` written
next to it. Open it with **Open project**, or with
`--project DIR/example_moving_aperture.amcproj`.

## 10. Tests and validation

```
python acoustic_morphology_composer.py --selftest                     # tests 1-8, extras, GUI (~2 min)
python acoustic_morphology_composer.py --selftest --praat "C:/.../Praat.exe"   # + test 9
python acoustic_morphology_composer.py --validate DIR                 # musical validation + model checks
```

`--validate` writes the WAVs and `results.json` into DIR (plus
`validation.png` if matplotlib is installed), and prints the calibration
figures quoted in Part 2.

| Test | Checks |
|---|---|
| 1 Free propagation | arrival = d/c (± 2 samples), 0 / −3 dB at 1 / 2 m, flat in band; bandwidth criterion |
| 2 Reflecting boundary | reflection at the image-source delay |
| 3 Narrow aperture | narrower → less transmission and darker (open field) |
| 4 Resonant chamber | peaks match 2-D modes within 2 %; energy conserved in a lossless room |
| 5 Geometry sensitivity | different geometries → measurably different IRs and outputs |
| 6 Repeatability | identical inputs → identical outputs |
| 7 Audio consistency | rates, channel policies, exact lengths, finite samples, peak ceiling; complementary band split |
| 8 Morph continuity | no clicks at transitions, tails not truncated; loop wrap; partial keyframe amounts |
| 9 Praat round trip | the real launcher on Praat 6.4.06 / 6.4.63 / 7.0, plus several failure paths (below) |
| extra | absorption calibration, PML reflection, cancellation, instability detection, invalid geometry, outdated states and project round trip, Mode 2, all presets |
| GUI scenario | drives the real window end to end (offscreen); 38 checks |

Test 9's Praat round trip covers:
* sample-exact duration, the same rate and the same F0, mono and stereo;
* tail mode;
* cancel;
* a Python error;
* a hard crash;
* no display;
* missing modules;
* a plugin path with a space and non-ASCII characters.

**Verified here:**
* all of the above, on Linux;
* an end-to-end run where Praat 7.0's GUI opened the composer window, which
  computed, rendered and returned four Sounds.

**Not runtime-tested:**
* Windows and macOS. The code paths are standard Qt and NumPy and paths are
  passed without a shell, but please run `--selftest` once on your machine.
* Audio playback, because there is no sound device in the test environment.

## 11. Troubleshooting

| Message | Meaning |
|---|---|
| *No suitable Python found* | The listed candidates lack the listed modules. Install them, or set `pyCandidate1$`. |
| *The composer did not start* / *ended unexpectedly* | Run the printed command in a terminal to see Python's own message. Typical causes are a Qt installation problem or no display. |
| *audio playback unavailable* | Install `sounddevice`, or connect an output device. Rendering is unaffected. |
| A state shows **OUTDATED** | Its geometry or settings changed after Compute. Press Compute or Compute all outdated. |
| *still decaying at the end of the window* | Lengthen the response, or add absorption. The response was faded, not truncated. |
| Compute is slow | Use Draft while designing, then Standard/High for the final render. The status bar shows the expected cost. |

---

# Part 2 — the acoustic model

This document says what is simulated, how, how accurately, and where the
simulation stops and creative signal processing begins. Every accuracy figure
is produced by `python acoustic_morphology_composer.py --validate DIR`, so you
can re-run it on your own machine.

Three kinds of processing are kept apart throughout:

| | What it is | Where |
|---|---|---|
| **Physical simulation** | 2-D wave propagation through the drawn geometry | solver, impulse responses below the reliable band |
| **Numerical approximation** | grid, dispersion, 2.5-D correction, frequency-independent absorption | documented below, with measured size |
| **Creative processing** | output morphing, "preserve" and "creative extension" above the band, gains, mixes | labelled as such in the interface |

---

## 1. Dimensionality

The model is **two-dimensional**. The drawing is a horizontal slice through a
space whose walls are infinitely tall, with no floor and no ceiling. The
consequences are:

* **The source is a line source.** A point in the drawing is an infinitely
  long line perpendicular to it. Sound spreads cylindrically, so the level
  falls **3 dB per doubling of distance** instead of 6 dB.
* **The raw 2-D response has the wrong spectral tilt and a wake.** Relative to
  a point source it rises +3 dB/octave, and its impulse trails off as
  1/√t. The *2.5-D correction* (section 8) removes both for the direct sound.
* **Room modes are 2-D modes.** A rectangle has modes at
  f = c/2 · √((m/Lx)² + (n/Ly)²). There are no height modes, and the mode
  density grows linearly with frequency instead of quadratically.
* **Decay times are 2-D decay times.** With no floor or ceiling to absorb
  energy, a "room" decays differently from a real 3-D room. T20/T30 values
  are shown for comparing states with each other, not as predictions for a
  real hall.

The result is a physically consistent *2-D acoustic world*. It is not an
auralisation of a real 3-D room.

## 2. Equations and discretisation

Linear acoustics as a first-order system, with pressure *p* and particle
velocity **v**:

    ∂p/∂t = −ρc² (∂vx/∂x + ∂vy/∂y)
    ∂v/∂t = −(1/ρ) ∇p

Eliminating **v** gives the wave equation ∂²p/∂t² = c²(∂²p/∂x² + ∂²p/∂y²).
The equations are discretised on a staggered (Yee) grid, with pressure at cell
centres and velocities on cell faces, and a leapfrog in time. The scheme is
second-order accurate in space and time and has **no numerical dissipation**:
without absorbing boundaries, a discrete energy is conserved exactly (section 5.4).
The update is fully vectorised NumPy (float32) with preallocated buffers and
in-place operations. No Python loop runs over grid cells. c = 343 m/s and
ρ = 1.204 kg/m³ by default.

## 3. Stability

The Courant number λ = c·Δt/Δx must satisfy **λ ≤ 1/√2** in 2-D. The time step
is not free. It is chosen so that the simulation rate f_sim = 1/Δt is an exact
rational multiple of the audio rate (for exact polyphase resampling), with
λ ≈ 0.97/√2 or a little below. The plan refuses to run if the condition is
violated. While running, the solver checks the field every 16 steps:

* a non-finite value aborts the run;
* acoustic energy growing more than 50× after the source has stopped aborts
  the run;
* in a closed lossless room, an energy drift above 5 % is reported as a
  warning.

An aborted or cancelled run never produces a response. The previous state of
the project is left untouched.

## 4. Reliable simulation bandwidth

The grid limits accuracy through **numerical dispersion**: high frequencies
travel slightly too slowly, and the error depends on direction (worst along
the grid axes). The criterion is explicit and computed, not assumed:

> **f_valid** is the highest frequency at which the scheme's phase velocity
> is within **±1 %** of c in *every* direction (from the exact discrete
> dispersion relation, checked over 0–45°).

For λ ≈ 0.68 this works out to about 9.6 cells per wavelength.

| Quality | Δx | f_sim (48 kHz audio) | Reliable band | Default response | 4 × 3 m room, closed / open field* |
|---|---|---|---|---|---|
| Draft | 3.0 cm | 20 000 Hz | ≤ 1071 Hz | 0.5 s | 1.4 s / 3.3 s |
| Standard | 1.5 cm | 33 600 Hz | ≤ 2388 Hz | 0.8 s | 10 s / 18 s |
| High Resolution | 0.75 cm | 67 200 Hz | ≤ 4776 Hz | 1.0 s | 139 s / ~150 s |

\* Wall-clock time measured on a 2-core cloud machine (NumPy, single thread).
Halving Δx costs 8× (4× the cells, 2× the steps). The status bar shows the
exact band, cost and memory for the current room before you compute.

Within the band the dispersion error is a lag of 0.07–1.0 %, so very high
modelled modes sit up to about 1 % low. Above f_valid the simulation says
nothing trustworthy. That band is never passed off as simulated (section 9).

## 5. Boundaries

### 5.1 Rigid walls and obstacles
The normal velocity on a face between air and a solid cell is held at zero,
which gives perfect reflection.

### 5.2 Absorbing walls (frequency-independent α)
A face between air and an absorbing solid, or an absorbing room edge, is a
**locally reacting impedance** v_n = p / Z with a real, frequency-independent

    Z = ρc (1 + R) / (1 − R),   R = √(1 − α)

so a plane wave at **normal incidence** loses the fraction α of its energy.
Measured in a 1-D duct (Draft):

| requested α | 0.10 | 0.30 | 0.50 | 0.90 |
|---|---|---|---|---|
| measured 1 − R² | 0.094 | 0.292 | 0.491 | 0.897 |

**Limitations:**
* Real materials absorb in a strongly frequency-dependent way. Here α is the
  same at every frequency.
* A locally reacting real impedance reflects differently at oblique incidence:
  R(θ) = (Z cos θ − ρc)/(Z cos θ + ρc).
* α is therefore a calibrated *design parameter* for the drawing, **not** a
  validated wall impedance of any real material.

### 5.3 Open field: perfectly matched layer
With the "absorbing" room boundary, a 20-cell split-field PML (cubic
conductivity profile, design reflection 10⁻⁵) surrounds the room, so waves
leave the domain. The residual reflection, measured by comparing a 2 × 2 m
domain with an 8 × 8 m one, is **−94 dB** at normal incidence and **−79 dB**
at grazing incidence, relative to the direct sound.

### 5.4 Intentional absorption vs. numerical dissipation
The leapfrog scheme conserves the discrete invariant

    E = Σ p² / (2ρc²) + (ρ/2) Σ v^(n−½) · v^(n+½)   (× cell area)

* **Closed rigid room:** E stays constant to **3.2 × 10⁻⁷** (relative) after the
  source stops, so the scheme adds no numerical damping.
* **Absorbing edges (α = 0.2):** E falls monotonically, by 86 dB over 0.6 s.

All energy loss is therefore intentional (impedance walls or PML) and none is
numerical. The energy curve is recorded with every response.

## 6. Geometry on the grid

* **Primitives:** walls (segments with a thickness), rectangular obstacles,
  and rectangular *openings* that force cells to air. There are no free-form
  polygons.
* **Rasterisation:** cells whose centre lies inside a primitive are solid.
* **Wall thickness:** a wall is drawn at least about 1.4 cells thick, so it is
  always airtight on the staggered grid.
* **Grid quantisation:** every dimension is rounded to whole cells. A
  1.0 × 0.7 m room is simulated as 0.990 × 0.690 m at Draft and
  1.005 × 0.705 m at Standard. The plan line states the simulated size
  whenever it differs from the drawn one, and mode frequencies follow the
  **simulated** size (section 12).
* **Staircasing:** oblique walls become staircases. Openings narrower than two
  cells are flagged, because their transmission is dominated by staircasing.
  The "sim. cells" overlay shows exactly what is simulated.
* **Validity checks:** a source or microphone inside a solid is an error.
  A microphone in a cavity with no air path to the source, detected by
  connected-component labelling, gets a warning: its response is silent, and
  this is never hidden.

## 7. Source and receivers

* **Source:** a *soft* (additive) pressure source driven by a band-limited
  impulse (a linear-phase Kaiser FIR at about 1.6 f_valid, unit DC gain, flat
  over the reliable band). It is spread bilinearly over the four surrounding
  air cells, so its position is not snapped to a cell. Its delay is removed
  from the recorded signals.
* **Receivers:** omnidirectional pressure, bilinearly interpolated over the
  neighbouring air cells. All microphones are recorded in one run, including
  disabled ones, so enabling a microphone never needs a recompute.

**Instrument as a point source.** A cello, a voice or a loudspeaker has size
and frequency-dependent directivity: it radiates differently in different
directions and changes with pitch. Here it is a single omnidirectional point,
and in 2-D a line. The recording you process already contains the instrument's
own radiation as heard by *its* microphone. The simulated geometry is applied
on top of that. It does not re-radiate the instrument.

## 8. From solver output to impulse response

For each microphone:

1. **Resampling:** polyphase resampling from f_sim to the audio rate, using
   the exact rational ratio chosen in section 3.
2. **2.5-D correction (on by default, labelled):**
   C(ω) = √ω_n / √(iω + ω_lo). This half-integrator turns the 2-D
   Green's function into a compact, spectrally flat arrival, matching a point
   source for the far-field direct sound. Reflections keep their 2-D
   geometric spreading. Measured in free field: in-band ripple ≤ 0.4 dB.
   Switching it off gives the native 2-D response.
3. **Modelled-band mask:** a zero-phase raised-cosine low-pass with −6 dB at
   f_valid (transition 0.85–1.15 f_valid). The complementary high-pass
   (exactly 1 − mask) is used for the band strategies in section 9.
4. **20 Hz high-pass:** causal, second order. A closed 2-D room otherwise holds
   a static pressure offset after the source has injected mass. A causal
   filter is used because a zero-phase one would put energy before the direct
   sound.
5. **Truncation check:** if the last 10 % of the response window still holds
   more than −35 dB of its energy, the response is flagged "still decaying"
   and faded with a raised cosine over its last 3 %. Lengthen the response or
   add absorption.
6. **Level:** the response is divided by the analytic 2-D free-field response
   of the same source at 1 m. **0 dB = the 2-D free field at 1 m.**
   * Measured: −0.20 dB at 1 m and −3.24 dB at 2 m (2-D theory: 0 and −3.01 dB).
   * First arrivals land within two audio samples of distance/c.

**Physical vs. normalized display.** In *physical level*, every response is on
the scale above. A closed resonant room is genuinely louder than the free
field (+15 to +18 dB in the Resonant Chamber preset) and a narrow slot is genuinely quieter,
and these transmission differences stay visible. *Normalized timbre* scales
each response to its own peak, for comparing spectral shape only. Both are
labelled in the interface.

## 9. Above the reliable band

Recordings contain energy above f_valid, which the simulation does not
cover. Each state chooses one clearly labelled strategy. All three use the
exactly complementary crossover masks, so splitting and recombining adds no
gain error (tested).

| Strategy | What happens above f_valid | Physical? |
|---|---|---|
| **Preserve** (default) | The dry high band passes **unsimulated**, delayed to the direct arrival and level-matched at the band edge | no — labelled "not simulated" |
| **Attenuate** | Nothing: the wet signal is band-limited | the remaining band is |
| **Creative extension** | Seeded noise, shaped by the decay envelope of the top modelled octave and tilted −3 dB/oct, continues the response | no — labelled artistic |

## 10. Rendering

* **Convolution:** y = x ∗ h by FFT (overlap-add) per channel, with the full
  linear convolution.
* **Duration:** *Preserve source duration* returns exactly the source length
  in samples. If a tail had to be cut, a 10 ms raised-cosine fade is applied
  and reported. *Include reverberation tail* keeps the decay, trimming only
  silence below −100 dBFS.
* **Stereo sources:** an explicit policy, never a silent drop:
  * mix to mono;
  * each channel through the same response;
  * left only;
  * right only.
* **Microphones:**
  * individual layers;
  * a mono mix;
  * a stereo mix with per-microphone gain and equal-power pan.
* **Mix definition:** with L_m the wet layer of microphone m (state wet gain ×
  microphone gain × x ∗ h_m):
  * mic m: y = (1 − mix)·x + mix·L_m;
  * mono mix: y = (1 − mix)·mean(x) + mix·(1/√N)·Σ mean(L_m);
  * stereo mix: y = (1 − mix)·D(x) + mix·(1/√N)·Σ P(L_m);
  * D: a mono source equal-power centred; P: equal-power pan;
  * the dry term appears once, and bypass is the dry term alone.
* **Dry/wet, wet gain, trim:** the wet path is on the physical scale, so a
  resonant room at 100 % wet is louder than the dry sound.
* **Peak protection:** one static gain that brings the peak to the ceiling.
  It is not a limiter and does not change the waveform shape. The applied
  gain is reported.
* **Checks:** every render is checked for non-finite samples. Sample rates
  must match exactly (the response is computed at the source's rate), so
  rendering never changes pitch or duration (Praat round trip, test 9).

## 11. Composition: morphing between states

**Mode 1 — acoustic output morphing (implemented).** Each state's response is
applied to the recording, and the results are mixed by time-varying weights.

**Keyframes.** A keyframe says that at time *t* the mixture has moved
*amount* of the way to state *S*:

    v_k = amount · S + (1 − amount) · v_(k−1)

so "A → B 100 % → C 40 % → A" is expressible. During a transition, weight
that two targets share stays constant, and only the exchanged part follows
the curve:

* **linear:** amplitude-constant;
* **equal-power:** power-constant for uncorrelated outputs. Between strongly
  correlated states (similar rooms, the same room with a moved microphone at
  low frequencies) it rises up to +3 dB mid-transition: measured +3.0 dB for
  two identical states (test 15). Use **linear** there;
* **smoothstep;**
* **hold:** a switch with a 3 ms de-click.

**Crossfade variants:**
* **Input crossfade (default, tail-preserving):** the *input* is split by the
  weights, and each part is convolved with its own state's response. Sound
  already sent into state A keeps decaying in A after the transition, so
  tails are never truncated and the joins are click-free (tests 8 and 15:
  after the transition the output is sample-identical to A's own decay).
  It is computed block by block, so memory stays about 1.5 × the output.
* **Output crossfade:** the full wet renders are crossfaded, so A's tail fades
  with A.

**Mode 1 does not simulate moving walls.** Both variants mix the responses of
*static* geometries.

**Mode 2 — geometry morphing (implemented as a generator).** For two states
whose elements correspond (same ids, kinds, room size and microphones),
intermediate geometries are generated by interpolating coordinates,
thicknesses, absorption, source and microphone positions. Each one is
**simulated**, and the chain is sequenced with Mode 1. This approximates a
changing room by a sequence of static rooms. It is not a time-varying FDTD
simulation, and it costs one simulation per step.

## 12. Measured accuracy (summary)

| Check | Result |
|---|---|
| Free-field level, 1 m / 2 m (2-D theory 0 / −3.01 dB) | −0.20 / −3.24 dB |
| First-arrival time | within 2 audio samples of distance/c |
| In-band ripple, free field, 2.5-D on | ≤ 0.41 dB |
| Phase-velocity error at the band edge | −0.07 … −1.00 % (criterion ±1 %) |
| Rigid rectangle modes vs. theory for the simulated size (Standard) | 0.00–0.08 % for the first six excited modes, 0.76 % for (0,3) |
| Same, vs. the drawn size (shows grid quantisation) | −0.5 … −1.5 % (Standard), +0.6 … +1.4 % (Draft) |
| Wall absorption at normal incidence | within 0.009 of the requested α |
| PML residual reflection | −94 dB normal, −79 dB grazing |
| Energy invariant, closed rigid room | constant to 3.2 × 10⁻⁷ |

## 13. Musical validation

A synthetic, harmonically rich sustained tone (bowed-string-like, G2 = 98 Hz,
6 s, generated by the program itself; no recording needed) was rendered
through three presets at Standard quality, using microphone 1 of each. The
unmodelled band was attenuated, so only simulated physics was measured.

| | Open Field | Resonant Chamber | Narrow Passage |
|---|---|---|---|
| Output level re input | −1.9 dB | +16.6 dB | −12.9 dB |
| Spectral centroid in the modelled band (input 276 Hz) | 277 Hz | 448 Hz | 644 Hz |
| Harmonic levels vs. simulated \|H\| (r / RMS deviation) | 1.000 / 0.00 dB | 0.995 / 0.90 dB | 1.000 / 0.23 dB |
| Level 100–300 ms after the tone ends, re sustain | silent | −36.5 dB (rings) | −75.9 dB |

Level-matched timbre distance between the presets (RMS difference of their
harmonic profiles, mean removed):

| | dB |
|---|---|
| Open Field ↔ Resonant Chamber | 8.7 |
| Open Field ↔ Narrow Passage | 9.7 |
| Resonant Chamber ↔ Narrow Passage | 14.5 |

**Reading the results:**
* The geometries change the sound by large, measurable amounts.
* Each change follows the simulated response harmonic by harmonic (r ≥ 0.995).
* Only the closed chamber rings after the note.
* The narrow passage's main effect in this enclosed, absorbing room is a
  strong loss of the lowest harmonics (the fundamental is cut by about 35 dB),
  so it sounds thinner and brighter, not darker.
* In an open field a narrower aperture *does* darken the sound (test 3). The
  outcome depends on the whole geometry, which is why the presets describe
  tendencies and not fixed filter curves.

`--validate DIR` reproduces the figure, numbers and audio. The WAVs use the
"preserve" strategy for listening.

## 14. Summary of artistic approximations

* The 2-D world, its line source, 2-D spreading and 2-D modes, and the
  optional 2.5-D correction of the direct sound.
* Frequency-independent, locally reacting absorption α.
* An omnidirectional point source and point microphones.
* The band above f_valid: preserved dry, removed, or creatively extended.
* Mode 1 morphing mixes static responses. Mode 2 sequences static
  intermediate rooms.
* Wet gain, mixes and peak protection are mixing decisions, not acoustics.
"""

# ============================================================================
# SELF-TEST  (python acoustic_morphology_composer.py --selftest [--praat EXE])
# ============================================================================
#
# Three groups:
#   core   numerical and audio tests 1-8 of the specification plus calibration,
#          robustness and persistence checks (the functions named test* above)
#   gui    the GUI scenario: the real window driven by synthetic mouse and key
#          events (offscreen; no display needed)
#   praat  test 9, the Praat round trip through Acoustic_Morphology_Composer.praat
#          (needs a Praat executable: --praat "C:/.../Praat.exe"; several allowed)


class _raises:
    """with _raises(SomeError): ...  - the block must raise SomeError."""

    def __init__(self, exc):
        self.exc = exc

    def __enter__(self):
        return self

    def __exit__(self, et, ev, tb):
        if et is None:
            raise AssertionError(f"{self.exc.__name__} was not raised")
        return issubclass(et, self.exc)


def _run_tests(tests, label):
    n_ok, fails = 0, []
    for name, fn in tests:
        t0 = time.perf_counter()
        try:
            fn()
            n_ok += 1
            print(f"  PASS  {name}  ({time.perf_counter() - t0:.1f} s)", flush=True)
        except Exception as e:
            fails.append(name)
            msg = str(e).split("\n")[0][:300]
            print(f"  FAIL  {name}: {type(e).__name__}: {msg}", flush=True)
            traceback.print_exc(limit=3)
    print(f"{label}: {n_ok} passed, {len(fails)} failed", flush=True)
    return fails


def selftest_core():
    tests = [(k, v) for k, v in list(globals().items()) if k.startswith("test") and callable(v)]
    return _run_tests(tests, "core")


def selftest_gui():
    with tempfile.TemporaryDirectory() as out:
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        subprocess.run([sys.executable, os.path.abspath(__file__), "--gui-scenario", out],
                       env=env, timeout=900, capture_output=True)
        p = os.path.join(out, "scenario.log")
        log = open(p, encoding="utf-8").read() if os.path.exists(p) else "no log written"
        ok = "SCENARIO PASSED" in log
        n = log.count("\nPASS ") + log.startswith("PASS ")
        print(f"  {'PASS' if ok else 'FAIL'}  GUI scenario ({n} checks)", flush=True)
        if not ok:
            print("\n".join(l for l in log.split("\n") if not l.startswith("PASS ")))
        print(f"gui: {1 if ok else 0} passed, {0 if ok else 1} failed", flush=True)
        return [] if ok else ["gui scenario"]


# ---------------------------------------------------------------- test 9

_PRAAT_WRAPPER = r'''
launcher$ = "{launcher}"
s = Create Sound from formula: "rt_src", {ch}, 0, {dur}, {fs}, "0.25 * (sin(2*pi*220*x) + 0.5*sin(2*pi*440*x) + 0.3*sin(2*pi*660*x) + 0.2*sin(2*pi*880*x))"
srcN = Get number of samples
p = To Pitch: 0, 75, 600
srcF0 = Get mean: 0, 0, "Hertz"
removeObject: p
selectObject: s
runScript: launcher$, "no"
writeInfoLine: "RESULT srcN=", srcN, " srcF0=", fixed$ (srcF0, 3)
select all
n = numberOfSelected ()
for i to n
    id[i] = selected (i)
endfor
for i to n
    selectObject: id[i]
    nm$ = selected$ ()
    if startsWith (nm$, "Sound ")
        nn = Get number of samples
        fsx = Get sampling frequency
        c = Get number of channels
        f0 = undefined
        if index (nm$, "acoustic_morphology") > 0 or nm$ = "Sound rt_src"
            p = To Pitch: 0, 75, 600
            f0 = Get mean: 0, 0, "Hertz"
            removeObject: p
        endif
        appendInfoLine: "OBJ|", nm$, "|", nn, "|", fsx, "|", c, "|", fixed$ (f0, 3)
    endif
endfor
'''


def _praat_version(exe):
    out = _decode(subprocess.run([exe, "--version"], capture_output=True).stdout)
    m = re.search(r"Praat (\d+)\.(\d+)(?:\.(\d+))?", out)
    return int(m.group(1)) * 1000 + int(m.group(2)) * 100 + int(m.group(3) or 0) if m else 0


def _decode(b):
    """Windows Praat writes its console output as UTF-16."""
    if b[:2] in (b"\xff\xfe", b"\xfe\xff") or (len(b) > 1 and b.count(b"\x00") > len(b) // 4):
        return b.decode("utf-16", "replace")
    return b.decode("utf-8", "replace")


def _praat_run(exe, tmp, spec, ch=1, dur=1.7, fs=44100, plugin_dir=None, env=None):
    plugin_dir = plugin_dir or HERE
    launcher = os.path.join(plugin_dir, "Acoustic_Morphology_Composer.praat").replace("\\", "/")
    wp = os.path.join(tmp, "wrapper.praat")
    with open(wp, "w", encoding="utf-8") as f:
        f.write(_PRAAT_WRAPPER.format(launcher=launcher, ch=ch, dur=dur, fs=fs))
    env = dict(env if env is not None else os.environ, PYTHONIOENCODING="utf-8")
    env.pop("AMC_AUTOMATE", None)
    if spec is not None:                       # None = GUI mode
        sp = os.path.join(tmp, "spec.json")
        with open(sp, "w", encoding="utf-8") as f:
            json.dump(spec, f)
        env["AMC_AUTOMATE"] = sp
    args = [exe, "--run"] + (["--FULL-TRUST"] if _praat_version(exe) >= 7000 else [])
    r = subprocess.run(args + [wp], capture_output=True, env=env, timeout=900)
    return r.returncode, _decode(r.stdout) + _decode(r.stderr)


def _praat_objs(out):
    objs = {}
    for line in out.splitlines():
        if line.startswith("OBJ|"):
            _, nm, nn, fsx, c, f0 = line.strip().split("|")
            objs[nm] = dict(n=int(nn), fs=float(fsx), ch=int(c), f0=None if "undef" in f0 else float(f0))
    return objs


def _praat_session(out):
    m = re.search(r"Session:\s+(.+)", out)
    return m.group(1).strip() if m else None


def _praat_tests(exe, first):
    T = []

    def round_trip(ch):
        def t():
            with tempfile.TemporaryDirectory() as tmp:
                spec = {"preset": "narrow_passage", "quality": "Draft", "ir_length": 0.3,
                        "render": {"mix": 1.0, "duration": "preserve", "stereo_policy": "per_channel"},
                        "target": "mix_stereo", "export_irs": True}
                rc, out = _praat_run(exe, tmp, spec, ch=ch)
                assert rc == 0, out
                objs = _praat_objs(out)
                src, main_ = objs["Sound rt_src"], objs["Sound rt_src_acoustic_morphology"]
                assert main_["n"] == src["n"], (main_, src)              # sample-exact duration
                assert main_["fs"] == src["fs"] and main_["ch"] == 2
                assert abs(main_["f0"] - src["f0"]) < 0.01 * src["f0"], (main_, src)   # no rate change
                assert len([k for k in objs if k.startswith("Sound Acoustic_IR_A_")]) == 3, objs
                assert "Duration preserved" in out and "was not modified" in out
        return t
    T.append(("9 round trip, mono: duration, rate, pitch, IRs", round_trip(1)))
    T.append(("9 round trip, stereo", round_trip(2)))

    def tail():
        with tempfile.TemporaryDirectory() as tmp:
            rc, out = _praat_run(exe, tmp, {"preset": "resonant_chamber", "quality": "Draft", "ir_length": 0.4,
                                            "render": {"duration": "tail"}, "target": "mix_mono",
                                            "export_irs": False})
            assert rc == 0, out
            objs = _praat_objs(out)
            assert objs["Sound rt_src_acoustic_morphology"]["n"] > objs["Sound rt_src"]["n"]
            assert "tail included" in out
    T.append(("9b tail mode returns a longer Sound", tail))

    def failure(action, expect, nonzero=False):
        def t():
            with tempfile.TemporaryDirectory() as tmp:
                rc, out = _praat_run(exe, tmp, {"action": action})
                assert expect in out, out
                assert "  + " not in out and "RESULT" not in out, out    # nothing imported
                if nonzero:
                    assert rc != 0
                sd = _praat_session(out)
                assert sd and not os.path.exists(sd), sd                  # session folder removed
        return t
    T.append(("9c cancel imports nothing", failure("cancel", "nothing imported")))
    T.append(("9d Python error reported, nothing imported", failure("fail", "deliberate failure", True)))
    T.append(("9f hard crash is not reported as a cancel", failure("abort", "ended unexpectedly")))

    if first:
        def paths():
            with tempfile.TemporaryDirectory() as tmp:
                plug = os.path.join(tmp, "AudioTools test \u00fc\u05e9")     # space, u-umlaut, Hebrew shin
                os.makedirs(plug)
                for fn in ("Acoustic_Morphology_Composer.praat", os.path.basename(__file__)):
                    shutil.copy(os.path.join(HERE, fn), os.path.join(plug, fn))
                rc, out = _praat_run(exe, tmp, {"preset": "open_field", "quality": "Draft", "ir_length": 0.2,
                                                "target": "mix_mono", "export_irs": False}, plugin_dir=plug)
                assert rc == 0, out
                assert "Sound rt_src_acoustic_morphology" in _praat_objs(out), out
        T.append(("9e plugin path with a space and non-ASCII characters", paths))

        def session_folders():
            # (1) the Python fallback the launcher uses where deleteFile cannot remove
            #     a folder (Windows): removes an EMPTY folder, leaves a non-empty one
            with tempfile.TemporaryDirectory() as tmp:
                empty, full = os.path.join(tmp, "e m p t y"), os.path.join(tmp, "full")
                os.makedirs(empty); os.makedirs(full)
                open(os.path.join(full, "keep.txt"), "w").write("x")
                pr = os.path.join(tmp, "rm.praat")
                with open(pr, "w", encoding="utf-8") as f:
                    for d in (empty, full):
                        f.write(f'nocheck runSubprocess: "{sys.executable}", "-c", '
                                f'"import os,sys;os.rmdir(sys.argv[1])", "{d}"\n')
                args = [exe, "--run"] + (["--FULL-TRUST"] if _praat_version(exe) >= 7000 else [])
                subprocess.run(args + [pr], capture_output=True, timeout=120)
                assert not os.path.exists(empty), "empty folder not removed"
                assert os.path.exists(os.path.join(full, "keep.txt")), "non-empty folder touched"
            # (2) a real run removes its own session folder and EMPTY leftovers of
            #     earlier runs, never a folder that still holds files
            with tempfile.TemporaryDirectory() as tmp:
                rc, out = _praat_run(exe, tmp, {"action": "cancel"})
                base = os.path.dirname(_praat_session(out))
                old_empty = os.path.join(base, "AMC_session_000001")
                old_full = os.path.join(base, "AMC_session_000002")
                os.makedirs(old_empty, exist_ok=True); os.makedirs(old_full, exist_ok=True)
                open(os.path.join(old_full, "x.txt"), "w").write("x")
                try:
                    rc, out = _praat_run(exe, tmp, {"preset": "open_field", "quality": "Draft", "ir_length": 0.2,
                                                    "target": "mix_mono", "export_irs": False})
                    assert rc == 0, out
                    assert not os.path.exists(_praat_session(out)), "session folder left behind"
                    assert not os.path.exists(old_empty), "empty leftover not cleaned"
                    assert os.path.exists(os.path.join(old_full, "x.txt")), "non-empty folder touched"
                finally:
                    shutil.rmtree(old_full, ignore_errors=True)
                    shutil.rmtree(old_empty, ignore_errors=True)
            # (3) a missing Python leaves no folder at all (the probe runs before it exists)
        T.append(("9i session folders removed (incl. the Windows fallback), leftovers cleaned", session_folders))
        if sys.platform.startswith("linux"):
            def no_display():
                with tempfile.TemporaryDirectory() as tmp:
                    env = {k: v for k, v in os.environ.items()
                           if k not in ("DISPLAY", "WAYLAND_DISPLAY", "QT_QPA_PLATFORM")}
                    rc, out = _praat_run(exe, tmp, None, env=env)
                    assert "No graphical display" in out, out
            T.append(("9g no display: explicit message", no_display))
        if os.name == "posix":
            def missing_modules():
                with tempfile.TemporaryDirectory() as tmp:
                    venv = os.path.join(tmp, "bare")
                    subprocess.run([sys.executable, "-m", "venv", "--without-pip", venv], check=True)
                    bindir = os.path.join(tmp, "bin")
                    os.makedirs(bindir)
                    for nm in ("python3", "python"):
                        pth = os.path.join(bindir, nm)
                        with open(pth, "w") as f:
                            f.write(f'#!/bin/sh\nexec "{venv}/bin/python3" "$@"\n')
                        os.chmod(pth, 0o755)
                    env = dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"])
                    rc, out = _praat_run(exe, tmp, {"preset": "open_field"}, env=env)
                    assert "No suitable Python found" in out, out
                    for m in ("PySide6", "numpy", "scipy", "soundfile", "pyqtgraph"):
                        assert m in out
            T.append(("9h missing Python modules are named", missing_modules))
    return T


def selftest_praat(exes):
    fails = []
    for k, exe in enumerate(exes):
        if not os.path.exists(exe):
            print(f"  FAIL  Praat not found: {exe}")
            fails.append(exe)
            continue
        v = _praat_version(exe)
        print(f"Praat {v // 1000}.{(v % 1000) // 100}.{v % 100:02d}  ({exe})", flush=True)
        fails += _run_tests(_praat_tests(exe, first=(k == 0)), f"praat {v}")
    return fails


def selftest(praats):
    print(f"{APP_NAME} {APP_VERSION} - self-test  (Python {sys.version.split()[0]}, numpy {np.__version__}, "
          f"{sys.platform})", flush=True)
    t0 = time.perf_counter()
    fails = selftest_core() + selftest_gui()
    if praats:
        fails += selftest_praat(praats)
    else:
        print("praat: skipped (add --praat PATH_TO_PRAAT to run test 9, the Praat round trip)")
    print(f"\nSELF-TEST {'PASSED' if not fails else 'FAILED: ' + ', '.join(fails)}  "
          f"({time.perf_counter() - t0:.0f} s)")
    return 0 if not fails else 1


# ============================================================================
# COMMAND LINE
# ============================================================================

USAGE = """\
usage:
  python acoustic_morphology_composer.py                      standalone window
  python acoustic_morphology_composer.py --project FILE       standalone, open a project
  python acoustic_morphology_composer.py MANIFEST.json        (used by the Praat launcher)
  python acoustic_morphology_composer.py --selftest [--praat PRAAT_EXE ...]
  python acoustic_morphology_composer.py --make-example DIR   synthetic tone + demonstration project
  python acoustic_morphology_composer.py --validate DIR [--quality Draft|Standard|High Resolution]
                                       musical validation (3 geometries x 1 tone) + model checks
  python acoustic_morphology_composer.py --manual             print the manual
"""


def _arg(argv, flag, default=None):
    if flag in argv:
        i = argv.index(flag)
        if i + 1 < len(argv):
            return argv[i + 1]
        raise SystemExit(f"{flag} needs a value\n\n{USAGE}")
    return default


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(USAGE)
        return 0
    if "--manual" in argv:
        print(MANUAL)
        return 0
    if "--selftest" in argv:
        praats = [argv[i + 1] for i, a in enumerate(argv) if a == "--praat" and i + 1 < len(argv)]
        return selftest(praats)
    if "--gui-scenario" in argv:                 # internal: one GUI scenario run (offscreen)
        return run_gui(None, scenario_out=_arg(argv, "--gui-scenario"))
    if "--make-example" in argv:
        d = _arg(argv, "--make-example")
        os.makedirs(d, exist_ok=True)
        make_example(d, _arg(argv, "--quality", "Draft"))
        return 0
    if "--validate" in argv:
        d = _arg(argv, "--validate")
        os.makedirs(d, exist_ok=True)
        musical_validation(d, _arg(argv, "--quality", "Standard"))
        model_checks()
        return 0
    manifest = None
    if len(argv) > 1 and not argv[1].startswith("--"):
        try:
            manifest = load_manifest(argv[1])
        except Exception as e:
            print(f"Cannot read the session manifest: {e}", file=sys.stderr)
            return 2
    mark_alive(manifest, "running")
    remove_stale_sessions(manifest)
    try:
        if "--automate" in argv:
            spec = json.loads(read_text_any(_arg(argv, "--automate")))
            if manifest is None:
                raise ValueError("--automate needs a manifest")
            automate(manifest, spec)
            mark_alive(manifest, "closed")
            return 0
        auto_env = os.environ.get("AMC_AUTOMATE")
        if auto_env and manifest is not None:
            automate(manifest, json.loads(read_text_any(auto_env)))
            mark_alive(manifest, "closed")
            return 0
        check_display()
        rc = run_gui(manifest, project_path=_arg(argv, "--project"))
        mark_alive(manifest, "closed")
        return rc
    except SystemExit:
        mark_alive(manifest, "closed")
        raise
    except BaseException:
        tb = traceback.format_exc()
        if manifest is not None:
            write_error(manifest, tb)
        mark_alive(manifest, "closed")
        print(tb, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
