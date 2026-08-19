"""
rhythmic_voice_flattener.py  —  Rhythmic Voice Flattener  v3.3

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Email: shai.cohen@biu.ac.il

Called by RhythmicVoiceFlattener.praat — not run directly.

Usage:
    python rhythmic_voice_flattener.py \\
        --events      events.csv \\
        --score       score.csv \\
        --stats       stats.txt \\
        --arrangement spectral \\
        --arc         arch \\
        --rhythm      soft \\
        --target_f0   0 \\
        --allow_rep   1 \\
        --preset      none \\
        --sparsity    0.5 \\
        --seed        42

v3.3 corrections:
    • CSP now enforces duration, density, and entropy jointly during search,
      using the exact event-specific metric durations that will be rendered.
    • Paired long_short / short_long tails are modelled explicitly and count
      toward the parent operation for entropy rather than inventing new classes.
    • CSP statistics are measured from final duration_ratio / skip values,
      including soft-rhythm scaling, so reported deviations match the score CSV.
    • Dropped events no longer receive a second automatic event-length gap;
      skip replaces the source event with silence once, and silence_after_s is
      reserved for genuinely additional rests.
    • Custom sparsity is clamped to [0,1].

Architecture (v3):
    A — Parse event CSV from Praat (seg_id, start_s, end_s, voiced,
        f0_hz, intensity_db, centroid_hz, gesture_id, pause_after_s)
    B — Compute target F0 (40th-percentile voiced F0, or manual)
    C — Polytonal metric grid: simultaneous multi-BPM frameworks per
        gesture; nearest_beat_dur() now picks best fit across all
        active frameworks rather than a single beat family.
        Tempo dramaturgy arc: full accelerando / ritardando / metric-
        modulation trajectory across gestures (not just mild offset).
    D — Compute tension arc per gesture (rising / arch / falling / wave /
        plateau / fractal / staircase / pulse)
    E — Silence architecture: tension-driven inter-gesture gaps
    F — Constraint-Satisfaction rhythmic engine (v3 core):
        * Defines per-gesture duration-budget, density, and entropy
          targets derived from the tension arc and global design.
        * Backtracking search + arc-consistency propagation assigns
          operations that collectively satisfy those targets.
        * Operations: sustain / compress / stutter / drop / long_short /
          short_long / burst / grid
        * rhythm=="free" now routes through the engine with near-zero
          grid weight rather than bypassing it entirely.
    F2— Intra-gesture rest injection (tension + entropy driven)
    F3— Note-duration fetcher: assigns articulation label and note_dur_s
        (staccatissimo → staccato → portato → tenuto continuum) to each
        event after duration ratios are resolved.
    G — Accent assignment: boundary, spectral extremity, voicing, tension
    H — Gesture arrangement (original / spectral / reversed / fragmented /
        density / palindrome) + structural repetition with motif scatter
    I — Write score CSV + stats

v3 additions over v2:
    • Polytonal metric grid (Section C): each gesture carries up to 3
      simultaneous BPM frameworks; subdivision candidates are drawn from
      all active frameworks and ranked by aggregate fit.
    • Tempo dramaturgy arc (Section C): gesture BPMs are sculpted by a
      global tempo-trajectory shape (linear, arch, accelerando, ritardando,
      modulation) with configurable intensity, replacing "mild heterogeneity."
    • CSP rhythmic engine (Section F): replaces weighted-table sampler with
      a backtracking solver that satisfies explicit per-gesture constraints:
        - duration_budget_ratio  ∈ [lo, hi]  (total played / original)
        - density_quota          ∈ [lo, hi]  (fraction of events kept)
        - entropy_target         ∈ [lo, hi]  (op-type diversity)
      Soft-constraint relaxation kicks in after N backtracks to ensure
      termination; deviation from targets is logged in stats.
    • Note-duration fetcher (Section F3): maps final played duration to
      a standard articulation on the staccatissimo→tenuto spectrum:
        staccatissimo  < 10 % of beat
        staccato       10–25 %
        mezzo-staccato 25–50 %
        portato        50–75 %
        tenuto         75–100 %
        sostenuto      > 100 %
      Written as note_dur_s and articulation columns in the score CSV.
    • Fixed free mode: routes through CSP engine with grid-weight ≈ 0.01
      instead of bypassing and leaving duration_ratio = 1.0 unchanged.

Presets (override individual parameters):
    none         — no override, use all explicit flags
    minimal      — sparse, slow, lots of silence, free rhythm
    pulse        — tight grid, hard rhythm, medium density
    scattered    — fragmented arrangement, high sparsity, wave arc
    mechanical   — hard rhythm, dense, low silence, arch arc
    decay        — falling arc, reversed arrangement, decreasing density
    breath       — high sparsity, free rhythm, arch arc, slow silences
    ritual       — palindrome arrangement, wave arc, soft rhythm, motif scatter
    stutter_loop — stutter-heavy, burst operations, dense, pulse arc
    ghost        — very low amplitude offsets, sparse, drop-heavy, falling arc

Outputs:
    score CSV  — one row per event, columns:
                 step, source_start_s, source_end_s, voiced,
                 target_pitch_hz, duration_ratio,
                 amplitude_db_offset, silence_after_s, skip,
                 note_dur_s, articulation
    stats txt  — target_f0, n_events, n_gestures, bpm, preset,
                 csp_budget_dev, csp_density_dev, csp_entropy_dev
"""

import argparse
import csv
import math
import sys
from collections import Counter


def check_dependencies():
    missing = []
    for pkg in ["numpy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


check_dependencies()

import numpy as np


# ─────────────────────────────────────────────────────────────────────────────
# Presets
# ─────────────────────────────────────────────────────────────────────────────

PRESETS = {
    "none": {},
    "minimal": {
        "arrangement": "original", "arc": "falling", "rhythm": "free",
        "sparsity": 0.8, "allow_rep": 0,
        "_silence_scale": 2.5, "_op_bias": "sustain",
        "_tempo_shape": "ritardando", "_tempo_intensity": 0.6,
    },
    "pulse": {
        "arrangement": "original", "arc": "arch", "rhythm": "hard",
        "sparsity": 0.2, "allow_rep": 1,
        "_silence_scale": 0.6, "_op_bias": "grid",
        "_tempo_shape": "arch", "_tempo_intensity": 0.3,
    },
    "scattered": {
        "arrangement": "fragmented", "arc": "wave", "rhythm": "soft",
        "sparsity": 0.65, "allow_rep": 1,
        "_silence_scale": 1.2, "_op_bias": "varied",
        "_tempo_shape": "wave", "_tempo_intensity": 0.5,
    },
    "mechanical": {
        "arrangement": "density", "arc": "arch", "rhythm": "hard",
        "sparsity": 0.15, "allow_rep": 1,
        "_silence_scale": 0.4, "_op_bias": "grid",
        "_tempo_shape": "linear", "_tempo_intensity": 0.1,
    },
    "decay": {
        "arrangement": "reversed", "arc": "falling", "rhythm": "soft",
        "sparsity": 0.5, "allow_rep": 0,
        "_silence_scale": 1.8, "_op_bias": "sustain",
        "_tempo_shape": "ritardando", "_tempo_intensity": 0.7,
    },
    "breath": {
        "arrangement": "original", "arc": "arch", "rhythm": "free",
        "sparsity": 0.75, "allow_rep": 0,
        "_silence_scale": 3.0, "_op_bias": "sustain",
        "_tempo_shape": "arch", "_tempo_intensity": 0.4,
    },
    "ritual": {
        "arrangement": "palindrome", "arc": "wave", "rhythm": "soft",
        "sparsity": 0.4, "allow_rep": 1,
        "_silence_scale": 1.5, "_op_bias": "varied",
        "_tempo_shape": "modulation", "_tempo_intensity": 0.8,
    },
    "stutter_loop": {
        "arrangement": "spectral", "arc": "pulse", "rhythm": "hard",
        "sparsity": 0.3, "allow_rep": 1,
        "_silence_scale": 0.5, "_op_bias": "stutter",
        "_tempo_shape": "accelerando", "_tempo_intensity": 0.65,
    },
    "ghost": {
        "arrangement": "original", "arc": "falling", "rhythm": "free",
        "sparsity": 0.9, "allow_rep": 0,
        "_silence_scale": 2.8, "_op_bias": "drop",
        "_amp_ceiling": 1.5, "_global_amp_offset": -6.0,
        "_tempo_shape": "ritardando", "_tempo_intensity": 0.9,
    },
}

PRESET_NAMES = sorted(PRESETS.keys())


# ─────────────────────────────────────────────────────────────────────────────
# Data model
# ─────────────────────────────────────────────────────────────────────────────

class Segment:
    __slots__ = (
        "seg_id", "start_s", "end_s", "voiced",
        "f0_hz", "intensity_db", "centroid_hz",
        "gesture_id", "pause_after_s",
        # computed
        "duration_ratio", "amplitude_db_offset",
        "silence_after_s", "target_pitch_hz",
        "skip",           # True = omit event, insert silence instead
        "op_tag",         # which rhythmic operation was applied
        "note_dur_s",     # v3: actual played duration in seconds
        "articulation",   # v3: staccatissimo → sostenuto label
    )

    def __init__(self, row):
        def _f(k, d=0.0):
            try:
                v = float(row.get(k, d))
                return v if math.isfinite(v) else d
            except (ValueError, TypeError):
                return d

        self.seg_id        = int(_f("seg_id",       1))
        self.start_s       = max(0.0, _f("start_s"))
        self.end_s         = max(0.0, _f("end_s"))
        self.voiced        = int(_f("voiced",       0))
        self.f0_hz         = max(0.0, _f("f0_hz"))
        self.intensity_db  = _f("intensity_db",    60.0)
        self.centroid_hz   = max(50.0, _f("centroid_hz", 2000.0))
        self.gesture_id    = int(_f("gesture_id",   1))
        self.pause_after_s = max(0.0, _f("pause_after_s"))
        # Computed later
        self.duration_ratio      = 1.0
        self.amplitude_db_offset = 0.0
        self.silence_after_s     = 0.0
        self.target_pitch_hz     = 0.0
        self.skip                = False
        self.op_tag              = "grid"
        self.note_dur_s          = 0.0
        self.articulation        = "tenuto"

    @property
    def orig_dur(self):
        return max(self.end_s - self.start_s, 0.010)


class Gesture:
    __slots__ = (
        "gesture_id", "events", "silence_after", "bpm",
        "_tension_val",
        # v3: polytonal frameworks
        "bpm_frameworks",  # list of up to 3 BPM values active for this gesture
    )

    def __init__(self, gesture_id):
        self.gesture_id    = gesture_id
        self.events        = []
        self.silence_after = 0.30
        self.bpm           = 120.0
        self.bpm_frameworks = [120.0]

    @property
    def mean_centroid(self):
        if not self.events:
            return 2000.0
        return float(np.mean([e.centroid_hz for e in self.events]))

    @property
    def n_events(self):
        return len(self.events)

    @property
    def total_dur(self):
        return sum(e.orig_dur for e in self.events)

    @property
    def mean_intensity(self):
        if not self.events:
            return 60.0
        return float(np.mean([e.intensity_db for e in self.events]))


# ─────────────────────────────────────────────────────────────────────────────
# A — Parse
# ─────────────────────────────────────────────────────────────────────────────

def parse_events(csv_path):
    segments = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            segments.append(Segment(row))
    return segments


def group_into_gestures(segments):
    gestures = {}
    for s in segments:
        gid = s.gesture_id
        if gid not in gestures:
            gestures[gid] = Gesture(gid)
        gestures[gid].events.append(s)
    return [gestures[k] for k in sorted(gestures)]


# ─────────────────────────────────────────────────────────────────────────────
# B — Target F0
# ─────────────────────────────────────────────────────────────────────────────

def compute_target_f0(segments, manual=0.0):
    """
    40th-percentile voiced F0 — slightly below median so the flat pitch
    sits in a natural low-centre of the speaker's range and minimises
    PSOLA distortion on upward-pitched frames.
    """
    if manual > 50.0:
        return float(manual)
    voiced = [s.f0_hz for s in segments if s.voiced and s.f0_hz > 50]
    if not voiced:
        return 130.0
    return float(np.percentile(voiced, 40))


# ─────────────────────────────────────────────────────────────────────────────
# C — Polytonal metric grid + Tempo dramaturgy arc  (v3 rewrite)
# ─────────────────────────────────────────────────────────────────────────────

def _ioi_to_bpm(onsets, bpm_min=40.0, bpm_max=320.0, fallback=120.0):
    """Convert a list of onset times to a BPM estimate via IOI histogram."""
    if len(onsets) < 4:
        return fallback
    iois = np.diff(sorted(onsets))
    lo, hi = 60.0 / bpm_max, 60.0 / bpm_min
    iois = iois[(iois > lo) & (iois < hi)]
    if len(iois) == 0:
        return fallback
    bpms = 60.0 / iois
    hist, edges = np.histogram(bpms, bins=280, range=(bpm_min, bpm_max))
    hist_s = np.convolve(hist.astype(float), [0.25, 0.5, 0.25], mode="same")
    peak = int(np.argmax(hist_s))
    peak = min(peak, len(edges) - 2)
    return float((edges[peak] + edges[peak + 1]) / 2.0)


def find_global_tempo(segments):
    return _ioi_to_bpm([s.start_s for s in segments])


# ── Tempo dramaturgy shapes ────────────────────────────────────────────────

def _tempo_arc(n, shape, intensity, global_bpm):
    """
    Return a length-n array of BPM values forming a global tempo trajectory.

    shape:
      linear       — flat (intensity controls how much BPM wanders at all)
      arch         — slow → fast → slow (inverse-arch)
      accelerando  — steady ramp upward
      ritardando   — steady ramp downward
      modulation   — abrupt metric modulation at the ≈60 % point (ratio 3:2)
      wave         — sinusoidal oscillation

    intensity in [0, 1]: 0 = no tempo variation; 1 = full-range excursion.
    The range is ±40 % of global_bpm scaled by intensity.
    """
    if n < 2:
        return np.full(n, global_bpm)

    t = np.linspace(0.0, 1.0, n)
    half_range = global_bpm * 0.40 * intensity  # maximum BPM swing each way

    if shape == "linear":
        # Slight drift — not truly flat, but no drama
        delta = np.linspace(-half_range * 0.3, half_range * 0.3, n)
    elif shape == "arch":
        # Peak in middle → feels like ritardando at both ends
        arch = np.where(t < 0.5, t * 2.0, (1.0 - t) * 2.0)
        delta = (arch - 0.5) * 2.0 * half_range
    elif shape == "accelerando":
        delta = np.linspace(-half_range, half_range, n)
    elif shape == "ritardando":
        delta = np.linspace(half_range, -half_range, n)
    elif shape == "modulation":
        # First 60 %: stable; then abrupt ratio shift of 3:2
        pivot = int(n * 0.60)
        delta = np.zeros(n)
        # After pivot: tempo multiplied by ~1.33 (3:2 metric modulation)
        modulation_jump = global_bpm * 0.33 * intensity
        delta[pivot:] = modulation_jump
        # Add slight ritardando in each section
        delta[:pivot] += np.linspace(0, -half_range * 0.25, pivot)
        delta[pivot:] += np.linspace(0, -half_range * 0.15, n - pivot)
    elif shape == "wave":
        delta = half_range * np.sin(2.0 * np.pi * t * 1.5)
    else:
        delta = np.zeros(n)

    bpms = np.clip(global_bpm + delta, 30.0, 400.0)
    return bpms


# ── Polytonal framework assignment ─────────────────────────────────────────

_POLYTONL_RATIOS = (2.0, 3.0 / 2.0, 4.0 / 3.0, 3.0 / 4.0, 2.0 / 3.0, 0.5)


def _derive_frameworks(base_bpm, n_frameworks=3):
    """
    Given a base BPM, derive up to n_frameworks related BPM values that
    are in simple integer-ratio relationship (3:2, 4:3, 2:1 etc.).
    These represent simultaneously active metrical layers.
    """
    frameworks = [base_bpm]
    for ratio in _POLYTONL_RATIOS:
        candidate = np.clip(base_bpm * ratio, 30.0, 400.0)
        # Keep only if meaningfully distinct from existing
        if all(abs(candidate - f) > 5.0 for f in frameworks):
            frameworks.append(float(candidate))
        if len(frameworks) >= n_frameworks:
            break
    return frameworks


def assign_gesture_tempos(gestures, global_bpm, tempo_shape, tempo_intensity):
    """
    v3: Two-stage tempo assignment.
    1. Global dramaturgy arc sculpts each gesture's primary BPM.
    2. Polytonal frameworks are derived from that BPM, giving each
       gesture a set of simultaneously active metrical layers.
    """
    n = len(gestures)
    bpm_arc = _tempo_arc(n, tempo_shape, tempo_intensity, global_bpm)

    for i, g in enumerate(gestures):
        # Per-gesture local BPM from internal IOIs (as before)
        local_bpm = _ioi_to_bpm(
            [e.start_s for e in g.events], fallback=float(bpm_arc[i]))
        # Blend local estimate with the dramaturgy target (70 % drama, 30 % local)
        blended = 0.70 * float(bpm_arc[i]) + 0.30 * local_bpm
        g.bpm = float(np.clip(blended, 30.0, 400.0))
        g.bpm_frameworks = _derive_frameworks(g.bpm, n_frameworks=3)


def nearest_beat_dur(dur_s, bpm_frameworks):
    """
    v3: Return the beat duration nearest to dur_s, searching across ALL
    active metrical frameworks simultaneously.

    Extended subdivision table now includes:
      Standard: 4, 3, 2, 1.5, 1, 0.75, 0.5, 0.333, 0.25, 0.125
      Added in v2: dotted-eighth (0.75 = 1.5*0.5), quintuplet (0.2)
      Added in v3: septuplet (1/7 ≈ 0.143), 32nd-note equiv (0.0625),
                   double-dotted (1.75), triplet-dotted (0.667),
                   staccatissimo anchor (0.05 of beat)
    """
    mults = (
        4.0, 3.5, 3.0, 2.0, 1.75, 1.5, 1.333, 1.0,
        0.8, 0.75, 0.667, 0.5, 1 / 3, 0.25, 0.2,
        1 / 6, 0.143, 0.125, 0.0625, 0.05,
    )

    candidates = []
    for bpm in bpm_frameworks:
        beat = 60.0 / max(bpm, 1.0)
        for m in mults:
            d = beat * m
            if 0.015 < d < 8.0:
                candidates.append(d)

    if not candidates:
        return dur_s

    diffs = [abs(c - dur_s) for c in candidates]
    return candidates[int(np.argmin(diffs))]


# ─────────────────────────────────────────────────────────────────────────────
# D — Tension arc
# ─────────────────────────────────────────────────────────────────────────────

def compute_tension_arc(n, arc_type):
    """
    Returns a [0,1] tension array of length n.

    v1 shapes: rising, arch, falling, wave
    v2/v3 shapes: plateau, fractal, staircase, pulse
    """
    t = np.linspace(0.0, 1.0, max(n, 2))

    if arc_type == "rising":
        return t.copy()
    if arc_type == "arch":
        skewed = np.where(t < 2 / 3, t * (3 / 2), (1 - t) * 3.0)
        return np.clip(skewed, 0.0, 1.0)
    if arc_type == "falling":
        return 1.0 - t
    if arc_type == "wave":
        return 0.5 + 0.5 * np.sin(2.0 * np.pi * t)
    if arc_type == "plateau":
        rise = 1.0 / (1.0 + np.exp(-20.0 * (t - 0.25)))
        fall = 1.0 / (1.0 + np.exp(20.0 * (t - 0.88)))
        return np.clip(rise * fall, 0.0, 1.0)
    if arc_type == "fractal":
        base  = np.where(t < 2 / 3, t * (3 / 2), (1 - t) * 3.0)
        base  = np.clip(base, 0.0, 1.0)
        noise = 0.18 * np.sin(7.0 * np.pi * t) + 0.09 * np.sin(17.0 * np.pi * t)
        return np.clip(base + noise, 0.0, 1.0)
    if arc_type == "staircase":
        n_steps = max(3, n // 3)
        steps   = np.floor(t * n_steps) / n_steps
        dip     = 0.12 * np.sin(n_steps * np.pi * t) * (t < 0.95)
        return np.clip(steps - dip, 0.0, 1.0)
    if arc_type == "pulse":
        base   = 0.15
        pulses = np.sin(np.pi * t * 5.5) ** 2
        return np.clip(base + 0.85 * pulses, 0.0, 1.0)

    return np.full(n, 0.5)


# ─────────────────────────────────────────────────────────────────────────────
# E — Silence architecture
# ─────────────────────────────────────────────────────────────────────────────

def assign_gesture_silences(gestures, tension, silence_scale=1.0):
    """
    Inter-gesture silence: inversely proportional to tension.
    silence_scale allows presets to globally compress or expand all gaps.
    """
    for g, t in zip(gestures, tension):
        complexity = float(np.clip(g.n_events / 6.0, 0.2, 1.8))
        base       = 0.22 + 0.18 * complexity
        scale      = (2.8 - 2.4 * float(t)) * silence_scale
        g.silence_after = float(np.clip(base * scale, 0.04, 8.0))


# ─────────────────────────────────────────────────────────────────────────────
# F — Constraint-Satisfaction Rhythmic Engine  (v3 core)
# ─────────────────────────────────────────────────────────────────────────────
#
# Design
# ──────
# Instead of sampling operations independently per-event from weighted tables,
# v3 solves for an assignment of operations across all events in a gesture
# that simultaneously satisfies three per-gesture constraints:
#
#   1. duration_budget_ratio  [lo, hi]
#      sum(played_dur) / sum(orig_dur) must land in this window.
#      "Played duration" for a dropped event is 0; for all others it is
#      orig_dur * duration_ratio.
#
#   2. density_quota  [lo, hi]
#      Fraction of non-skipped events must lie in this window.
#
#   3. entropy_target  [lo, hi]
#      Shannon entropy of the op-type distribution across events in the
#      gesture, normalised to [0,1].  Ensures variety (high entropy) or
#      uniformity (low entropy) as required by the design.
#
# The constraints are derived from the tension arc and rhythm mode:
#   • High tension  → tighter budget window, higher density quota,
#                     higher entropy (more varied operations).
#   • Low tension   → wider budget window, lower density quota,
#                     lower entropy (simpler, sparser texture).
#   • rhythm=free   → grid weight ≈ 0.01 (not bypass); wide budget window.
#   • rhythm=hard   → tight budget window; grid weight = normal.
#   • sparsity      → shifts density quota toward 0 (more drops).
#
# Search algorithm
# ────────────────
#   forward_assign() — bounded backtracking over exact event-specific ratios.
#     Duration, density and entropy all participate in feasibility pruning.
#     Paired long_short / short_long operations consume two event slots and
#     are evaluated with the same ratios later written to the score.
#
#   If forward_assign() cannot satisfy all constraints within the search-node
#   cap, soft_relax() widens the windows by RELAX_FACTOR and retries once.
#   Final deviation is always measured from the rendered event state against
#   the original, unrelaxed design targets.
#
# ─────────────────────────────────────────────────────────────────────────────

_OPS = ("sustain", "compress", "stutter", "drop", "long_short",
        "short_long", "burst", "grid")

# Base probability table for *initial candidate ordering* (not hard weights —
# the CSP solver uses these as a preference order, not a probability).
# Indexed by tension quartile 0–3.
_OP_PROBS = np.array([
    [0.30, 0.05, 0.02, 0.03, 0.10, 0.10, 0.02, 0.38],
    [0.20, 0.10, 0.06, 0.05, 0.12, 0.12, 0.05, 0.30],
    [0.10, 0.12, 0.12, 0.08, 0.12, 0.12, 0.10, 0.24],
    [0.05, 0.08, 0.18, 0.12, 0.10, 0.10, 0.18, 0.19],
], dtype=float)

_BIAS_BOOSTS = {
    "sustain": {"sustain": 0.35},
    "grid":    {"grid": 0.40},
    "stutter": {"stutter": 0.35, "burst": 0.20},
    "drop":    {"drop": 0.40},
    "varied":  {},
}

MAX_BACKTRACKS = 10000   # v3.3 exact-CSP search-node cap
RELAX_FACTOR   = 0.25   # widen each constraint window by this fraction on relax


def _candidate_order(t_val, bias, sparsity, rng, rhythm):
    """
    Return a shuffled ordering of _OPS with preference shaped by tension,
    bias, sparsity, and rhythm mode.
    Returns a list of op strings, most-preferred first.
    """
    tq = int(np.clip(t_val * 3.999, 0, 3))
    p  = _OP_PROBS[tq].copy()

    boosts = _BIAS_BOOSTS.get(bias, {})
    for op, boost in boosts.items():
        p[_OPS.index(op)] += boost

    # Sparsity
    p[_OPS.index("drop")]    += sparsity * 0.25
    p[_OPS.index("sustain")] += sparsity * 0.10
    p[_OPS.index("burst")]    = max(0.0, p[_OPS.index("burst")]  - sparsity * 0.08)
    p[_OPS.index("grid")]     = max(0.0, p[_OPS.index("grid")]   - sparsity * 0.12)

    # free mode: strongly depress "grid"; other ops remain available
    if rhythm == "free":
        p[_OPS.index("grid")] = max(0.0, p[_OPS.index("grid")] * 0.01)

    p = np.clip(p, 0.0, None)
    # Add tiny floor so all ops remain selectable for without-replacement
    # sampling (numpy requires at least len(_OPS) non-zero entries).
    p = np.maximum(p, 1e-6)
    s = p.sum()
    if s < 1e-9:
        p = np.ones(len(_OPS)) / len(_OPS)
    else:
        p /= s

    return list(rng.choice(list(_OPS), size=len(_OPS), replace=False, p=p))


def _op_duration_ratio(op, event, bpm_frameworks, rng=None):
    """
    Compute the duration_ratio that the given op would produce on this event,
    without modifying the event.  Returns (duration_ratio, skip, op_tag).
    """
    orig  = event.orig_dur
    grid  = nearest_beat_dur(orig, bpm_frameworks)
    beat  = 60.0 / max(bpm_frameworks[0], 1.0)

    if op == "grid":
        r = float(np.clip(grid / orig, 0.50, 4.0))
        return r, False, "grid"

    elif op == "sustain":
        target = nearest_beat_dur(orig * 1.8, bpm_frameworks)
        target = max(target, orig * 1.4)
        r = float(np.clip(target / orig, 0.50, 4.0))
        return r, False, "sustain"

    elif op == "compress":
        target = nearest_beat_dur(orig * 0.55, bpm_frameworks)
        target = min(target, orig * 0.65)
        target = max(target, 0.030)
        r = float(np.clip(target / orig, 0.50, 4.0))
        return r, False, "compress"

    elif op == "burst":
        target = max(0.060, min(0.130, beat * 0.25))
        r = float(np.clip(target / orig, 0.50, 4.0))
        return r, False, "burst"

    elif op == "stutter":
        target = max(0.040, beat * 0.5)
        r = float(np.clip(target / orig, 0.50, 4.0))
        return r, False, "stutter"

    elif op == "drop":
        return 0.0, True, "drop"

    elif op == "long_short":
        target = nearest_beat_dur(orig * 1.5, bpm_frameworks)
        r = float(np.clip(target / orig, 0.50, 4.0))
        return r, False, "long_short"

    elif op == "short_long":
        target = nearest_beat_dur(orig * 0.5, bpm_frameworks)
        target = max(target, 0.030)
        r = float(np.clip(target / orig, 0.50, 4.0))
        return r, False, "short_long"

    return 1.0, False, op


def _apply_op_to_event(event, op, bpm_frameworks, next_event=None, amp_ceiling=6.0):
    """Apply op in-place; returns op_tag (same as _apply_op in v2 but uses polytonal grid)."""
    orig  = event.orig_dur
    beat  = 60.0 / max(bpm_frameworks[0], 1.0)

    if op == "grid":
        grid = nearest_beat_dur(orig, bpm_frameworks)
        event.duration_ratio = float(np.clip(grid / orig, 0.50, 4.0))

    elif op == "sustain":
        target = nearest_beat_dur(orig * 1.8, bpm_frameworks)
        target = max(target, orig * 1.4)
        event.duration_ratio = float(np.clip(target / orig, 0.50, 4.0))

    elif op == "compress":
        target = nearest_beat_dur(orig * 0.55, bpm_frameworks)
        target = min(target, orig * 0.65)
        target = max(target, 0.030)
        # Floor at 0.50: below this PSOLA discards too many pitch periods,
        # producing aperiodic / hoarse-sounding resynthesis
        event.duration_ratio = float(np.clip(target / orig, 0.50, 4.0))

    elif op == "burst":
        target = max(0.060, min(0.130, beat * 0.25))
        # burst is a very short accent hit — floor at 0.50 to stay PSOLA-clean
        event.duration_ratio = float(np.clip(target / orig, 0.50, 4.0))
        event.amplitude_db_offset = float(
            np.clip(event.amplitude_db_offset + 3.5, -4.0, amp_ceiling))

    elif op == "stutter":
        target = max(0.040, beat * 0.5)
        event.duration_ratio = float(np.clip(target / orig, 0.50, 4.0))
        event.op_tag = "stutter"
        return "stutter"

    elif op == "drop":
        event.skip = True
        event.duration_ratio = 0.0
        event.op_tag = "drop"
        return "drop"

    elif op == "long_short":
        long_target = nearest_beat_dur(orig * 1.5, bpm_frameworks)
        event.duration_ratio = float(np.clip(long_target / orig, 0.50, 4.0))
        if next_event is not None:
            short_target = nearest_beat_dur(next_event.orig_dur * 0.5, bpm_frameworks)
            short_target = max(short_target, 0.030)
            next_event.duration_ratio = float(
                np.clip(short_target / next_event.orig_dur, 0.50, 4.0))
            next_event.op_tag = "long_short_tail"

    elif op == "short_long":
        short_target = nearest_beat_dur(orig * 0.5, bpm_frameworks)
        short_target = max(short_target, 0.030)
        event.duration_ratio = float(np.clip(short_target / orig, 0.50, 4.0))
        if next_event is not None:
            long_target = nearest_beat_dur(next_event.orig_dur * 1.5, bpm_frameworks)
            next_event.duration_ratio = float(
                np.clip(long_target / next_event.orig_dur, 0.50, 4.0))
            next_event.op_tag = "short_long_tail"

    event.op_tag = op
    return op


# ── Constraint derivation ──────────────────────────────────────────────────

def _gesture_constraints(tension_val, sparsity, rhythm):
    """
    Derive (budget_lo, budget_hi, density_lo, density_hi, entropy_lo, entropy_hi)
    from the current gesture's tension and global parameters.
    """
    t = float(tension_val)
    s = float(sparsity)

    # Duration budget: ratio of total played duration to total original duration
    # High tension → compress or vary more (budget can go lower)
    # Low tension → sustain or drop (budget stretches or shrinks via drops)
    budget_center = 0.85 - 0.35 * t          # 0.85 at t=0, 0.50 at t=1
    budget_half   = 0.30 + 0.20 * (1.0 - t)  # tighter at high tension
    budget_lo = max(0.10, budget_center - budget_half)
    budget_hi = min(3.50, budget_center + budget_half)

    # Density: fraction of events that are NOT dropped
    density_center = 1.0 - s * 0.70          # sparsity drives drops
    density_half   = 0.15 + 0.10 * t
    density_lo = max(0.05, density_center - density_half)
    density_hi = min(1.00, density_center + density_half)

    # Entropy target: high tension → high variety; free mode → wide window
    entropy_center = 0.30 + 0.55 * t
    entropy_half   = 0.20
    if rhythm == "free":
        # Free mode wants variety but not necessarily high tension ops
        entropy_center = 0.50
        entropy_half   = 0.40
    elif rhythm == "hard":
        entropy_half = 0.12   # tighter — must match the target
    entropy_lo = max(0.0, entropy_center - entropy_half)
    entropy_hi = min(1.0, entropy_center + entropy_half)

    return (budget_lo, budget_hi, density_lo, density_hi, entropy_lo, entropy_hi)


def _canonical_op_tag(op):
    """Map internal pair-tail tags back to their musical operation class."""
    if op == "long_short_tail":
        return "long_short"
    if op == "short_long_tail":
        return "short_long"
    return op


def _entropy_of_ops(op_list):
    """Normalised Shannon entropy of musical op classes; returns [0,1]."""
    if not op_list:
        return 0.0
    canonical = [_canonical_op_tag(op) for op in op_list]
    counts = Counter(canonical)
    n = len(canonical)
    probs = [c / n for c in counts.values()]
    raw = -sum(p * math.log2(p) for p in probs if p > 0)
    max_ent = math.log2(len(_OPS))
    return float(np.clip(raw / max_ent if max_ent > 0 else 0.0, 0.0, 1.0))


def _constraint_deviation(values, limits):
    """Raw per-constraint deviation outside (budget,density,entropy) windows."""
    out = []
    for v, lo, hi in zip(values, limits[::2], limits[1::2]):
        if v < lo:
            out.append(lo - v)
        elif v > hi:
            out.append(v - hi)
        else:
            out.append(0.0)
    return tuple(out)


def _metrics_from_events(events):
    """Measure the constraints from the exact final event state."""
    if not events:
        return (1.0, 1.0, 0.0)
    total_orig = sum(e.orig_dur for e in events)
    total_played = sum(
        0.0 if e.skip else e.orig_dur * e.duration_ratio for e in events)
    density = sum(0 if e.skip else 1 for e in events) / float(len(events))
    entropy = _entropy_of_ops([e.op_tag for e in events])
    budget = total_played / total_orig if total_orig > 0 else 1.0
    return float(budget), float(density), float(entropy)


def _soften_ratio(ratio, op, rhythm, skip=False):
    """Mirror the post-operation soft-rhythm transform used by the renderer."""
    if rhythm == "soft" and not skip and op not in ("burst", "stutter"):
        return 1.0 + 0.45 * (ratio - 1.0)
    return ratio


def _pair_tail_ratio(parent_op, next_event, bpm_frameworks):
    """Exact ratio applied to the second event of a paired operation."""
    if next_event is None:
        return None
    if parent_op == "long_short":
        target = nearest_beat_dur(next_event.orig_dur * 0.5, bpm_frameworks)
        target = max(target, 0.030)
    elif parent_op == "short_long":
        target = nearest_beat_dur(next_event.orig_dur * 1.5, bpm_frameworks)
    else:
        return None
    return float(np.clip(target / next_event.orig_dur, 0.50, 4.0))


def _solver_candidate(events, i, op, bpm_frameworks, rhythm):
    """
    Return exact assignments for one CSP choice.
    Each tuple is (index, tag, duration_ratio, skip).
    Paired ops consume the following event and tag it as an internal tail.
    """
    event = events[i]
    ratio, skip, tag = _op_duration_ratio(op, event, bpm_frameworks)
    ratio = _soften_ratio(ratio, op, rhythm, skip)
    assignments = [(i, tag, float(ratio), bool(skip))]

    if op in ("long_short", "short_long") and i + 1 < len(events):
        tail_ratio = _pair_tail_ratio(op, events[i + 1], bpm_frameworks)
        tail_tag = op + "_tail"
        assignments.append((i + 1, tail_tag, float(tail_ratio), False))
    return assignments


def _entropy_bounds(counts, remaining):
    """
    Conservative achievable entropy bounds after `remaining` event slots.
    Minimum: put all remaining slots into the dominant class.
    Maximum: distribute them greedily among the least-used of the 8 classes.
    """
    classes = list(_OPS)
    base = {op: int(counts.get(op, 0)) for op in classes}

    cmin = dict(base)
    if remaining > 0:
        dominant = max(classes, key=lambda op: cmin[op])
        cmin[dominant] += remaining
    vals_min = [v for v in cmin.values() if v > 0]
    nmin = sum(vals_min)
    if nmin:
        pmin = [v / nmin for v in vals_min]
        hmin = -sum(p * math.log2(p) for p in pmin) / math.log2(len(_OPS))
    else:
        hmin = 0.0

    cmax = dict(base)
    for _ in range(remaining):
        least = min(classes, key=lambda op: cmax[op])
        cmax[least] += 1
    vals_max = [v for v in cmax.values() if v > 0]
    nmax = sum(vals_max)
    if nmax:
        pmax = [v / nmax for v in vals_max]
        hmax = -sum(p * math.log2(p) for p in pmax) / math.log2(len(_OPS))
    else:
        hmax = 0.0
    return float(hmin), float(hmax)


def _forward_assign(events, bpm_frameworks, tension_val, bias, sparsity,
                    rhythm, rng, amp_ceiling,
                    budget_lo, budget_hi, density_lo, density_hi,
                    entropy_lo, entropy_hi):
    """
    Backtracking CSP over exact event-specific operation durations.

    Duration, density, and entropy are all active constraints. Paired operations
    consume two event slots. If the search cap is reached, return the best
    complete assignment encountered so soft relaxation can decide what to do.
    """
    n = len(events)
    if n == 0:
        return [], True

    total_orig = sum(e.orig_dur for e in events)
    candidate_orders = [
        _candidate_order(tension_val, bias, sparsity, rng, rhythm)
        for _ in range(n)
    ]

    # Maximum physically allowed future duration (all ratios clamp at 4).
    suffix_orig = [0.0] * (n + 1)
    for j in range(n - 1, -1, -1):
        suffix_orig[j] = suffix_orig[j + 1] + events[j].orig_dur

    max_nodes = max(MAX_BACKTRACKS, 120)
    nodes = 0
    best_ops = None
    best_score = float("inf")

    def evaluate_complete(ops, played, kept, counts):
        nonlocal best_ops, best_score
        budget = played / total_orig if total_orig > 0 else 1.0
        density = kept / float(n)
        entropy = _entropy_of_ops(ops)
        vals = (budget, density, entropy)
        limits = (budget_lo, budget_hi, density_lo, density_hi,
                  entropy_lo, entropy_hi)
        dev = _constraint_deviation(vals, limits)

        # Balance unlike units by each constraint window's natural range.
        widths = (max(budget_hi - budget_lo, 0.10),
                  max(density_hi - density_lo, 0.10),
                  max(entropy_hi - entropy_lo, 0.10))
        score = sum(d / w for d, w in zip(dev, widths))
        if score < best_score:
            best_score = score
            best_ops = list(ops)
        return max(dev) <= 1e-12

    def dfs(i, ops, played, kept, counts):
        nonlocal nodes
        nodes += 1
        if nodes > max_nodes:
            return None

        if i >= n:
            return list(ops) if evaluate_complete(ops, played, kept, counts) else None

        for op in candidate_orders[i]:
            assignments = _solver_candidate(events, i, op, bpm_frameworks, rhythm)
            next_i = assignments[-1][0] + 1

            new_ops = list(ops)
            new_played = played
            new_kept = kept
            new_counts = Counter(counts)

            for idx, tag, ratio, skip in assignments:
                new_ops[idx] = tag
                if not skip:
                    new_played += events[idx].orig_dur * ratio
                    new_kept += 1
                new_counts[_canonical_op_tag(tag)] += 1

            remaining = n - next_i

            # Budget feasibility: future events can range from all-dropped to
            # the global 4x ratio clamp.
            if new_played > budget_hi * total_orig + 1e-12:
                continue
            max_future = 4.0 * suffix_orig[next_i]
            if new_played + max_future < budget_lo * total_orig - 1e-12:
                continue

            # Density feasibility.
            if new_kept > density_hi * n + 1e-12:
                continue
            if new_kept + remaining < density_lo * n - 1e-12:
                continue

            # Entropy feasibility.
            hmin, hmax = _entropy_bounds(new_counts, remaining)
            if hmax < entropy_lo - 1e-12 or hmin > entropy_hi + 1e-12:
                continue

            found = dfs(next_i, new_ops, new_played, new_kept, new_counts)
            if found is not None:
                return found

        return None

    initial_ops = [None] * n
    found = dfs(0, initial_ops, 0.0, 0, Counter())
    if found is not None:
        return found, True
    if best_ops is not None:
        return best_ops, False

    # Search cap can theoretically be reached before any complete solution.
    # Fall back to grid so the engine always terminates deterministically.
    return ["grid"] * n, False


def _relax_constraints(budget_lo, budget_hi, density_lo, density_hi,
                       entropy_lo, entropy_hi, factor=RELAX_FACTOR):
    """Widen all constraint windows by `factor` fraction of their current width."""
    def widen(lo, hi, f):
        w = (hi - lo) * f
        return max(0.0, lo - w), min(1.0 if hi <= 1.0 else hi * 2, hi + w)

    b_lo, b_hi = widen(budget_lo, budget_hi, factor)
    b_hi = min(4.0, b_hi)
    d_lo, d_hi = widen(density_lo, density_hi, factor)
    e_lo, e_hi = widen(entropy_lo, entropy_hi, factor)
    return b_lo, b_hi, d_lo, d_hi, e_lo, e_hi


# ── Main engine entry point ────────────────────────────────────────────────

# Accumulated constraint deviation for stats
_csp_stats = {"budget_dev": 0.0, "density_dev": 0.0, "entropy_dev": 0.0,
              "n_gestures": 0}


def assign_duration_ratios(gestures, rhythm, sparsity, op_bias, rng, amp_ceiling=6.0):
    """
    v3.3: exact CSP rhythmic assignment.

    Search uses the same event-specific duration ratios that will be written to
    the score. Duration, density, and entropy are jointly enforced. A single
    soft-relaxation retry is allowed; final deviations are always measured
    against the original (unrelaxed) design constraints.
    """
    global _csp_stats
    _csp_stats = {
        "budget_dev": 0.0, "density_dev": 0.0, "entropy_dev": 0.0,
        "n_gestures": 0, "relaxed_gestures": 0, "unsatisfied_gestures": 0,
    }

    for g in gestures:
        tension = getattr(g, "_tension_val", 0.5)
        bpm_fw  = g.bpm_frameworks
        n       = len(g.events)

        limits = _gesture_constraints(tension, sparsity, rhythm)
        (b_lo, b_hi, d_lo, d_hi, e_lo, e_hi) = limits

        ops, ok = _forward_assign(
            g.events, bpm_fw, tension, op_bias, sparsity, rhythm, rng,
            amp_ceiling, b_lo, b_hi, d_lo, d_hi, e_lo, e_hi)

        if not ok:
            _csp_stats["relaxed_gestures"] += 1
            relaxed = _relax_constraints(*limits)
            ops, _ = _forward_assign(
                g.events, bpm_fw, tension, op_bias, sparsity, rhythm, rng,
                amp_ceiling, *relaxed)

        # Apply the selected exact operation assignment.
        for i, e in enumerate(g.events):
            op = ops[i] if ops[i] is not None else "grid"

            if op in ("long_short_tail", "short_long_tail"):
                # The parent pair already writes this event's exact ratio/tag.
                continue

            next_ev = g.events[i + 1] if i < n - 1 else None
            _apply_op_to_event(e, op, bpm_fw, next_ev, amp_ceiling)

            if rhythm == "soft" and not e.skip and e.op_tag not in ("burst", "stutter"):
                e.duration_ratio = 1.0 + 0.45 * (e.duration_ratio - 1.0)

        # Measure what will actually be rendered, not approximate op ratios.
        values = _metrics_from_events(g.events)
        dev = _constraint_deviation(values, limits)
        if max(dev) > 1e-9:
            _csp_stats["unsatisfied_gestures"] += 1

        _csp_stats["budget_dev"]  += dev[0]
        _csp_stats["density_dev"] += dev[1]
        _csp_stats["entropy_dev"] += dev[2]
        _csp_stats["n_gestures"]  += 1

        for e in g.events:
            e.amplitude_db_offset = float(
                np.clip(e.amplitude_db_offset, -4.0, amp_ceiling))


# ─────────────────────────────────────────────────────────────────────────────
# F2 — Intra-gesture rest injection
# ─────────────────────────────────────────────────────────────────────────────

def inject_intra_gesture_rests(gestures, sparsity, rng):
    """
    Inserts small rests inside gestures at interior event boundaries.
    Probability for each interior event = 0.12 + 0.30 * local_tension * sparsity.
    Rest duration drawn uniformly from {0.5, 1.0, 1.5} * one beat.
    Skipped events always get silence equal to their effective played duration.
    """
    rest_mults = (0.5, 1.0, 1.5)

    for g in gestures:
        beat    = 60.0 / max(g.bpm_frameworks[0], 1.0)
        tension = getattr(g, "_tension_val", 0.5)
        n       = len(g.events)

        for i, e in enumerate(g.events):
            if i == n - 1:
                continue

            if e.skip:
                # Praat replaces the skipped source event itself with a silent
                # slot of its original duration. silence_after_s is therefore
                # reserved for *additional* rest and must not duplicate it.
                e.silence_after_s = 0.0
                continue

            p_rest = 0.12 + 0.30 * tension * sparsity
            if rng.random() < p_rest:
                mult = float(rng.choice(rest_mults))
                e.silence_after_s = float(np.clip(beat * mult, 0.025, 2.5))


# ─────────────────────────────────────────────────────────────────────────────
# F3 — Note-duration fetcher  (v3 new stage)
# ─────────────────────────────────────────────────────────────────────────────
#
# After all duration ratios are finalised, compute the actual played duration
# (note_dur_s) and classify it against the standard articulation spectrum.
#
# Articulation thresholds are expressed as fractions of one beat duration:
#
#   staccatissimo  <  0.10  of beat   (very short wedge; ≈ grace-note length)
#   staccato       0.10 – 0.25        (dot; roughly quarter of full value)
#   mezzo-staccato 0.25 – 0.50        (portato-dot; half-staccato)
#   portato        0.50 – 0.75        (tenuto + staccato hybrid)
#   tenuto         0.75 – 1.10        (full written value, slightly over)
#   sostenuto      > 1.10             (elongated past the beat)
#
# The beat used is the primary BPM framework (bpm_frameworks[0]).
# For dropped (skip=True) events, note_dur_s = 0 and articulation = "rest".
# ─────────────────────────────────────────────────────────────────────────────

_ARTICULATION_THRESHOLDS = (
    # (upper_frac_of_beat, label)  — evaluated in order; first match wins
    (0.10, "staccatissimo"),
    (0.25, "staccato"),
    (0.50, "mezzo-staccato"),
    (0.75, "portato"),
    (1.10, "tenuto"),
)
_ARTICULATION_SOSTENUTO = "sostenuto"


def assign_note_durations(gestures):
    """
    v3: Compute note_dur_s and articulation for every event.
    Must be called AFTER all duration_ratio assignments are complete.
    """
    for g in gestures:
        beat = 60.0 / max(g.bpm_frameworks[0], 1.0)

        for e in g.events:
            if e.skip:
                e.note_dur_s   = 0.0
                e.articulation = "rest"
                continue

            e.note_dur_s = max(0.0, e.orig_dur * e.duration_ratio)

            frac = e.note_dur_s / beat if beat > 0 else 1.0
            label = _ARTICULATION_SOSTENUTO
            for threshold, art_label in _ARTICULATION_THRESHOLDS:
                if frac < threshold:
                    label = art_label
                    break
            e.articulation = label


# ─────────────────────────────────────────────────────────────────────────────
# G — Accent assignment
# ─────────────────────────────────────────────────────────────────────────────

def assign_accents(gestures, tension):
    """
    Accent sources (all additive → amplitude_db_offset):
      +2.0 dB  — first or last event in gesture (boundary position)
      +0.5 dB  — voiced event
      0–2.5 dB — spectral extremity within gesture (bright/dark outliers)
      0–1.5 dB — local tension contribution
      burst ops carry their own +3.5 dB boost from _apply_op_to_event
    Clamped to [-4, +8] dB.
    """
    for g, t in zip(gestures, tension):
        g._tension_val = float(t)
        n         = len(g.events)
        centroids = np.array([e.centroid_hz for e in g.events], dtype=float)
        mean_c    = float(np.mean(centroids))
        std_c     = float(np.std(centroids)) + 1.0

        for i, e in enumerate(g.events):
            if e.skip:
                continue
            acc = 0.0
            if i == 0 or i == n - 1:
                acc += 2.0
            if e.voiced:
                acc += 0.5
            dev  = abs(e.centroid_hz - mean_c) / std_c
            acc += float(np.clip(dev * 1.5, 0.0, 2.5))
            acc += float(t) * 1.5
            e.amplitude_db_offset = float(np.clip(acc, -4.0, 8.0))


# ─────────────────────────────────────────────────────────────────────────────
# H — Arrangement and repetition
# ─────────────────────────────────────────────────────────────────────────────

def arrange_gestures(gestures, arrangement, rng):
    """
    original   — preserve input order
    spectral   — brightest-last (ascending mean centroid)
    reversed   — reverse temporal order
    fragmented — sort by centroid then shuffle/interleave
    density    — sort ascending by event count
    palindrome — forward then mirrored reverse (A B C B' A')
    """
    if arrangement == "spectral":
        return sorted(gestures, key=lambda g: g.mean_centroid)
    if arrangement == "reversed":
        return list(reversed(gestures))
    if arrangement == "density":
        return sorted(gestures, key=lambda g: g.n_events)
    if arrangement == "palindrome":
        fwd = list(gestures)
        rev = list(reversed(gestures[:-1]))
        return fwd + rev
    if arrangement == "fragmented":
        base = sorted(gestures, key=lambda g: g.mean_centroid)
        for i, g in enumerate(base):
            if rng.random() < 0.40 and len(g.events) > 2:
                g.events = list(reversed(g.events))
        result = []
        skip_next = False
        for i in range(len(base)):
            if skip_next:
                skip_next = False
                continue
            if (i < len(base) - 1
                    and rng.random() < 0.20
                    and len(base[i].events) >= 2
                    and len(base[i + 1].events) >= 2):
                merged = Gesture(base[i].gesture_id)
                a_evs  = base[i].events
                b_evs  = base[i + 1].events
                for j in range(max(len(a_evs), len(b_evs))):
                    if j < len(a_evs):
                        merged.events.append(a_evs[j])
                    if j < len(b_evs):
                        merged.events.append(b_evs[j])
                merged.bpm_frameworks = list(base[i].bpm_frameworks)
                merged.bpm            = base[i].bpm
                merged.silence_after  = (base[i].silence_after
                                         + base[i + 1].silence_after) / 2.0
                result.append(merged)
                skip_next = True
            else:
                result.append(base[i])
        return result
    return list(gestures)


def _clone_gesture(source, amp_offset_delta):
    echo = Gesture(source.gesture_id + 10000)
    echo.bpm = source.bpm
    echo.bpm_frameworks = list(source.bpm_frameworks)
    for e in source.events:
        clone = Segment.__new__(Segment)
        for slot in Segment.__slots__:
            setattr(clone, slot, getattr(e, slot))
        clone.amplitude_db_offset = float(
            np.clip(e.amplitude_db_offset + amp_offset_delta, -6.0, 8.0))
        echo.events.append(clone)
    echo.silence_after = max(0.08, source.silence_after * 0.55)
    return echo


def _extract_motif(gesture, n=3):
    valid = [e for e in gesture.events if not e.skip]
    if not valid:
        return []
    ranked = sorted(valid, key=lambda e: e.amplitude_db_offset, reverse=True)
    return ranked[:min(n, len(ranked))]


def _make_motif_gesture(events, amp_delta, silence_after, gesture_id,
                        source_gesture=None, invert_durations=False):
    g = Gesture(gesture_id)
    if source_gesture is not None:
        g.bpm = source_gesture.bpm
        g.bpm_frameworks = list(source_gesture.bpm_frameworks)
    for e in events:
        clone = Segment.__new__(Segment)
        for slot in Segment.__slots__:
            setattr(clone, slot, getattr(e, slot))
        clone.amplitude_db_offset = float(
            np.clip(e.amplitude_db_offset + amp_delta, -6.0, 8.0))
        if invert_durations and clone.duration_ratio > 0.01:
            inv = 1.0 / max(clone.duration_ratio, 0.20)
            clone.duration_ratio = float(np.clip(inv, 0.20, 4.0))
        g.events.append(clone)
    g.silence_after = silence_after
    return g


def add_repetition(arranged, tension, rng, arc_type):
    if len(arranged) < 3:
        return arranged

    peak_idx  = int(np.argmax(tension))
    peak_idx  = min(peak_idx, len(arranged) - 1)
    peak_gest = arranged[peak_idx]

    echo       = _clone_gesture(peak_gest, amp_offset_delta=-3.0)
    insert_pos = max(1, int(len(arranged) * 0.82))
    result     = arranged[:insert_pos] + [echo] + arranged[insert_pos:]

    motif = _extract_motif(peak_gest, n=3)
    if motif:
        n_scatter = int(rng.integers(2, 4))
        n_result  = len(result)
        positions = sorted(rng.choice(
            range(1, max(2, n_result - 1)), size=min(n_scatter, n_result - 2),
            replace=False))

        invert    = bool(rng.random() < 0.5)
        base_sil  = peak_gest.silence_after * 0.4

        for k, pos in enumerate(positions):
            amp_delta = -5.0 - float(k) * 1.5
            mg = _make_motif_gesture(
                motif, amp_delta=amp_delta,
                silence_after=float(np.clip(base_sil, 0.04, 2.0)),
                gesture_id=20000 + k,
                source_gesture=peak_gest,
                invert_durations=(invert and k % 2 == 1))
            result.insert(pos + k, mg)

    return result


# ─────────────────────────────────────────────────────────────────────────────
# I — Writers
# ─────────────────────────────────────────────────────────────────────────────

def write_score(score_path, arranged_gestures, target_f0):
    """
    One row per event.
    v2: added skip column.
    v3: added note_dur_s and articulation columns.
    Stutter events generate two rows (event + quieter echo).
    """
    with open(score_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "step", "source_start_s", "source_end_s", "voiced",
            "target_pitch_hz", "duration_ratio",
            "amplitude_db_offset", "silence_after_s", "skip",
            "note_dur_s", "articulation",
        ])
        step   = 0
        n_gest = len(arranged_gestures)

        for gi, g in enumerate(arranged_gestures):
            n_ev         = len(g.events)
            is_last_gest = (gi == n_gest - 1)

            for ei, e in enumerate(g.events):
                step      += 1
                is_last_ev = (ei == n_ev - 1)

                if is_last_ev and not is_last_gest:
                    sil = g.silence_after
                else:
                    sil = e.silence_after_s

                t_f0     = target_f0 if (e.voiced and not e.skip) else 0.0
                skip_int = 1 if e.skip else 0

                w.writerow([
                    step,
                    "%.6f" % e.start_s,
                    "%.6f" % e.end_s,
                    e.voiced,
                    "%.3f" % t_f0,
                    "%.4f" % e.duration_ratio,
                    "%.4f" % e.amplitude_db_offset,
                    "%.4f" % sil,
                    skip_int,
                    "%.4f" % e.note_dur_s,
                    e.articulation,
                ])

                # Stutter echo row
                if e.op_tag == "stutter" and not e.skip:
                    step += 1
                    echo_sil = float(np.clip(sil * 0.5, 0.010, 0.5))
                    echo_amp = float(np.clip(e.amplitude_db_offset - 3.5, -6.0, 8.0))
                    w.writerow([
                        step,
                        "%.6f" % e.start_s,
                        "%.6f" % e.end_s,
                        e.voiced,
                        "%.3f" % t_f0,
                        "%.4f" % e.duration_ratio,
                        "%.4f" % echo_amp,
                        "%.4f" % echo_sil,
                        0,
                        "%.4f" % e.note_dur_s,
                        e.articulation,
                    ])


def write_stats(stats_path, segments, gestures, target_f0, bpm, preset,
                seed_used, global_amp_offset):
    ng = _csp_stats["n_gestures"]
    if ng > 0:
        b_dev = _csp_stats["budget_dev"]  / ng
        d_dev = _csp_stats["density_dev"] / ng
        e_dev = _csp_stats["entropy_dev"] / ng
    else:
        b_dev = d_dev = e_dev = 0.0

    with open(stats_path, "w", encoding="utf-8") as f:
        f.write("target_f0=%.1f\n"       % target_f0)
        f.write("n_events=%d\n"          % len(segments))
        f.write("n_gestures=%d\n"        % len(gestures))
        f.write("bpm=%.1f\n"             % bpm)
        f.write("preset=%s\n"            % preset)
        f.write("seed=%d\n"              % seed_used)
        f.write("global_amp_offset_db=%.2f\n" % global_amp_offset)
        f.write("csp_budget_dev=%.4f\n"  % b_dev)
        f.write("csp_density_dev=%.4f\n" % d_dev)
        f.write("csp_entropy_dev=%.4f\n" % e_dev)
        f.write("csp_relaxed_gestures=%d\n" % _csp_stats.get("relaxed_gestures", 0))
        f.write("csp_unsatisfied_gestures=%d\n" % _csp_stats.get("unsatisfied_gestures", 0))


# ─────────────────────────────────────────────────────────────────────────────
# Preset resolver
# ─────────────────────────────────────────────────────────────────────────────

def apply_preset(args):
    extra = {}
    pdata = PRESETS.get(args.preset, {})
    for k, v in pdata.items():
        if k.startswith("_"):
            extra[k] = v
        else:
            setattr(args, k, v)
    return extra


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Rhythmic Voice Flattener v3.3 — CSP compositional voice transformer")
    parser.add_argument("--events",      required=True)
    parser.add_argument("--score",       required=True)
    parser.add_argument("--stats",       required=True)
    parser.add_argument("--arrangement", default="spectral",
        choices=["original", "spectral", "reversed",
                 "fragmented", "density", "palindrome"])
    parser.add_argument("--arc",         default="arch",
        choices=["rising", "arch", "falling", "wave",
                 "plateau", "fractal", "staircase", "pulse"])
    parser.add_argument("--rhythm",      default="soft",
        choices=["free", "soft", "hard"])
    parser.add_argument("--target_f0",   type=float, default=0.0)
    parser.add_argument("--allow_rep",   type=int,   default=1)
    parser.add_argument("--sparsity",    type=float, default=0.5,
        help="0=dense, 1=sparse; affects drop probability and intra-rests")
    parser.add_argument("--preset",      default="none",
        choices=PRESET_NAMES,
        help="Named preset overrides arrangement/arc/rhythm/sparsity")
    parser.add_argument("--seed",        type=int,   default=42)
    args = parser.parse_args()

    args.sparsity = float(np.clip(args.sparsity, 0.0, 1.0))
    args.allow_rep = 1 if args.allow_rep else 0
    args.seed = max(0, int(args.seed))
    if args.seed == 0:
        seed_used = int(np.random.SeedSequence().generate_state(1, dtype=np.uint32)[0])
    else:
        seed_used = args.seed
    rng = np.random.default_rng(seed_used)

    extra = apply_preset(args)
    silence_scale   = extra.get("_silence_scale",    1.0)
    op_bias         = extra.get("_op_bias",           "varied")
    amp_ceiling     = extra.get("_amp_ceiling",       6.0)
    global_amp_offset = extra.get("_global_amp_offset", 0.0)
    tempo_shape     = extra.get("_tempo_shape",       "linear")
    tempo_intensity = extra.get("_tempo_intensity",   0.3)

    print("[Py] Preset: %s | Arrangement: %s | Arc: %s | Rhythm: %s | Sparsity: %.2f"
          % (args.preset, args.arrangement, args.arc, args.rhythm, args.sparsity))
    print("[Py] Tempo shape: %s | Intensity: %.2f | Seed: %d"
          % (tempo_shape, tempo_intensity, seed_used))

    # ── A: Parse ──────────────────────────────────────────────────────────
    print("[Py 1/7] Parsing events...")
    segments = parse_events(args.events)
    gestures = group_into_gestures(segments)
    print("    Events: %d  |  Gestures: %d" % (len(segments), len(gestures)))
    if not segments:
        print("ERROR: No events in CSV.", file=sys.stderr)
        sys.exit(1)

    # ── B+C: Target F0, polytonal grid, tempo dramaturgy ──────────────────
    print("[Py 2/7] Target F0, polytonal grid, tempo arc...")
    target_f0  = compute_target_f0(segments, args.target_f0)
    global_bpm = find_global_tempo(segments)
    assign_gesture_tempos(gestures, global_bpm, tempo_shape, tempo_intensity)
    print("    Target F0: %.1f Hz  |  Global BPM: %.1f" % (target_f0, global_bpm))
    fw_summary = " / ".join("%.0f" % f for f in gestures[0].bpm_frameworks) if gestures else "—"
    print("    Gesture 0 frameworks: [%s] BPM" % fw_summary)
    for s in segments:
        s.target_pitch_hz = target_f0 if s.voiced else 0.0

    # ── D+G (first pass): Tension and accents ─────────────────────────────
    print("[Py 3/7] Tension arc and accents...")
    tension = compute_tension_arc(len(gestures), args.arc)
    assign_accents(gestures, tension)

    # ── E: Inter-gesture silences ─────────────────────────────────────────
    assign_gesture_silences(gestures, tension, silence_scale)

    # ── F: CSP duration ratios ────────────────────────────────────────────
    print("[Py 4/7] CSP rhythmic engine...")
    assign_duration_ratios(gestures, args.rhythm, args.sparsity,
                           op_bias, rng, amp_ceiling)
    ng = _csp_stats["n_gestures"]
    if ng > 0:
        print("    CSP mean deviations — budget: %.3f | density: %.3f | entropy: %.3f"
              % (_csp_stats["budget_dev"] / ng,
                 _csp_stats["density_dev"] / ng,
                 _csp_stats["entropy_dev"] / ng))
        print("    CSP relaxation: %d/%d gestures | unsatisfied after render: %d"
              % (_csp_stats.get("relaxed_gestures", 0), ng,
                 _csp_stats.get("unsatisfied_gestures", 0)))

    if global_amp_offset != 0.0:
        for g in gestures:
            for e in g.events:
                if not e.skip:
                    e.amplitude_db_offset += float(global_amp_offset)
        print("    Global level offset: %+.1f dB" % global_amp_offset)

    # ── F2: Intra-gesture rests ───────────────────────────────────────────
    print("[Py 5/7] Intra-gesture rest injection...")
    inject_intra_gesture_rests(gestures, args.sparsity, rng)

    # ── F3: Note-duration fetcher ─────────────────────────────────────────
    print("[Py 6/7] Note-duration fetcher (articulation labelling)...")
    assign_note_durations(gestures)

    # ── H: Arrange ────────────────────────────────────────────────────────
    print("[Py 7/7] Arranging and writing score...")
    arranged = arrange_gestures(gestures, args.arrangement, rng)

    if args.allow_rep and len(arranged) >= 3:
        tension_arr  = compute_tension_arc(len(arranged), args.arc)
        arranged     = add_repetition(arranged, tension_arr, rng, args.arc)
        tension_arr2 = compute_tension_arc(len(arranged), args.arc)
        assign_gesture_silences(arranged, tension_arr2, silence_scale)
        # Re-run note-duration fetcher for cloned/motif gestures
        assign_note_durations(arranged)

    # ── I: Write ──────────────────────────────────────────────────────────
    write_score(args.score, arranged, target_f0)
    write_stats(args.stats, segments, gestures, target_f0, global_bpm, args.preset,
                seed_used, global_amp_offset)

    n_out  = sum(len(g.events) for g in arranged)
    n_skip = sum(1 for g in arranged for e in g.events if e.skip)

    # Articulation distribution summary
    art_counts = Counter(
        e.articulation for g in arranged for e in g.events if not e.skip)
    art_str = " | ".join("%s:%d" % (k, v)
                         for k, v in sorted(art_counts.items(),
                                            key=lambda x: -x[1]))
    print("    Score: %d rows across %d gestures (%d skipped/dropped)"
          % (n_out, len(arranged), n_skip))
    print("    Articulations: %s" % art_str)
    print("OK: %s" % args.score)


if __name__ == "__main__":
    main()
