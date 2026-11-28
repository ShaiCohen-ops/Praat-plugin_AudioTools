"""
tinysol_retrieval.py — TinySOL Orchestration Retrieval Backend
Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.11.6

Usage (called by Praat via TinySOL_Retrieval.praat):
    python tinysol_retrieval.py  target.wav  params.txt  output.wav  results.txt  [done.txt]

Maintenance commands (run by hand; never touch existing .db files):
    python tinysol_retrieval.py --build-db   <corpus_root> <new_output_dir> [--descriptors mfcc,specenv,moments,specpeaks]
    python tinysol_retrieval.py --verify-db  <db_dir> <corpus_root> [--probe-files 12]

params.txt is a key=value file written by Praat:
    db_dir=D:/old D/waves/TinySOL_2020
    corpus_root=D:/old D/waves/TinySOL_2020/TinySOL
    allowed_families=Brass,Strings,Winds,Keyboards
    allowed_instruments=          (empty = all)
    min_midi=36
    max_midi=96
    preferred_dynamics=mf          (empty = no preference)
    descriptor_weights=mfcc:0.25,specenv:0.20,moments:0,specpeaks:0,harmonic:0.35
    n_results=8
    render_mode=best               (best=1 | blend=3 rank-weighted | top2 | top3 | top4 instruments)
    render_gain=0.8                (output peak, 0 < g <= 1)
    envelope_follow=0.85
    duration_policy=target         (target | natural)
    match_threshold=0              (calibrated score units; 0 = gate off)
    report_path=                   (optional JSON analysis report; Praat does not request it)

Output contract: output.wav (temporary exchange file, deleted by Praat after
import) holds ONE channel per rendered instrument; the summed reference mix
is internal only.  results.txt carries the retrieval RANKING (diagnostic)
and, separately, the RENDERED channel map (chanN_* lines) that Praat draws.

Changes in v1.11.6 (fixed ensemble, events, verify-db, results protocol):
    - Frame mode: render_mode = number of distinct instruments in the WHOLE
      result.  allocate_instruments() ranks every instrument by the
      energy-weighted mean of its best legal frame score (frames where it
      has no legal sample count ALLOC_UNCOVERED_COST = 2.0) and keeps the N
      lowest; each kept instrument gets its own per-event Viterbi voice
      restricted to its samples.  An instrument may rest and re-enter; its
      channel never changes.  Polyphonic events avoid doubling an evidenced
      chord note while another evidenced note is uncovered.
    - Whole file: first entry of each instrument in the unchanged ranking;
      a sample that fails to load is replaced by the next instrument.
    - Fewer instruments than requested -> fewer channels;
      instruments_requested / instruments_rendered / instruments_note.
    - layer_selection removed (ignored with a warning).
    - build_events: Spectral interpretation never splits on F0; in Auto a
      pitch_step needs a confirming next frame and is refused when the
      sound only decays (level -3 dB, no new spectral energy).
      _new_partial_share ignores partials that merely surfaced because
      stronger ones decayed.
    - --verify-db: exit 0 COMPLETE / 3 PARTIAL / 2 FAILED (an empty or
      missing directory can no longer pass); lists checked/passed tables.
    - Results: chanN_name/family/notes/dyn/score/samples/files/units/
      active_s/activity/notespans (activity measured on the final channels,
      20 ms blocks, -45 dB re loudest block, gaps < 60 ms closed).

Changes in v1.11.5 (distinct instrument layers):
    - Whole file, render_mode with N > 1 layers: the ranked list keeps the
      best-scoring entry of each instrument (scores and order unchanged), so
      the N layers are N different instruments = N output channels.
    - Frame mode: render_mode gives N instrument voices (was always 1).  Each
      voice uses the same per-event Viterbi on the same frame scores, with
      the instruments of earlier voices in that frame excluded; inside a
      polyphonic event, uncovered chord notes are preferred.  Voice grains
      are scaled to w_v * frame RMS with sum(w_v^2) = 1.  Voice 1 is the
      v1.11.4 single-voice selection.
    - layer_selection=scores restored the v1.11.4 layering (removed in v1.11.6).

Changes in v1.11.4 (output architecture):
    - The instrument channels ARE the output.  output.wav (the temporary
      exchange file) now holds one channel per distinct rendered instrument;
      there is no mono/stereo preview and no persistent export.  The
      reference mix used for envelope following and level matching is
      internal only (sum of the channels).  When no instrument is rendered,
      no output file is written (nothing is fabricated).
    - Removed: stereo_output, pitch_pan_stereo, multichannel_path (ignored
      with a warning if a caller still sends them), write_multichannel.
    - Results file: out_channels, channel_map, channel_<n>, channel_sum_check.

Changes in v1.11.3 (output level, multichannel stems):
    - The renderers no longer peak-normalise to render_gain (except in
      level_matching=off, the v1.11.2 behaviour).  After rendering and the
      target-envelope transfer, the COMPLETE mix is measured with BS.1770-4
      K-weighted gated loudness (channel mean; see measure_loudness) and one
      scalar gain is applied: attenuate (default, never raises), bidirectional
      (max +12 dB) or off.  render_gain is a peak ceiling in matching modes;
      if the ceiling limits the gain, the remaining difference is reported.
      No compressor/limiter.  Gain refined by re-measurement near the -70 LUFS
      absolute gate.
    - Instrument stems are built inside blend_samples / render_frame_matches
      (one unpanned mono bus per distinct rendered instrument, same OLA
      normalisation, envelope curve and master gain as the mix), optionally
      written as one 32-bit float multichannel WAV (multichannel_path; never
      overwrites).  Channel order: whole-file = first rendered rank; frame
      mode = orchestral score order.  Stems sum to the mono mix.
    - Report: level_matching block and multichannel channel map.

Changes in v1.11.2 (fix):
    - A non-monophonic sound (chord, bell, noise) with NO verified timbral
      descriptor produced silent output labelled "no frame matches": the only
      remaining term (harmonic) is correctly disabled for such events, so no
      frame could be scored.  The run now stops with an explicit diagnosis
      (which tables are unverified, why) and the --build-db command, in both
      analysis modes.  Silence caused by this is reported as
      no_valid_descriptors, not frame_unmatched.

Changes in v1.11.1 (pitch confidence, event-aware frame retrieval):
    - Pitch is no longer binary.  Each frame carries periodicity (normalised
      ACF at the candidate period), harmonic share and occupancy of a harmonic
      series whose fundamental is PRESENT (a chord's common subharmonic never
      qualifies), tonality, energy of further harmonic series, and temporal
      consistency with its neighbours (glides allowed).  confidence =
      periodicity * share * occupancy * temporal.  Frame classes: harmonic,
      polyphonic, inharmonic, unpitched, uncertain, silent.  The v1.8 ACF value
      is kept whenever it agrees with the spectral F0 (clean tones unchanged).
    - Events: frames are grouped by evidence (energy onsets, new partials,
      pitch steps after a stable pitch).  Decays, balance changes, vibrato and
      glides are not boundaries.  Event class (energy-weighted vote):
      monophonic / spectral / polyphonic / unpitched / ambiguous.
    - Only reliable frames of monophonic events get the pitch gate and the
      harmonic term, and the harmonic term uses the MEASURED partials (no
      synthetic 1/h series from an uncertain F0).  No last-pitch reuse.
      Other frames are pitch-neutral, restricted to the event's evidenced
      pitch set where one exists (reliable notes of the event / fundamentals
      of a chord's harmonic series); inharmonic events stay fully pitch-neutral.
    - Event-level Viterbi selection replaces the persistence bonus: a sample
      change costs SWITCH_COST, a MIDI change PITCH_SWITCH_COST (calibrated
      units); new events start free.
    - Rendering reads each event from the start of its corpus sample (attacks
      re-articulate) and stays phase-coherent across selection changes.
    - pitch_interpretation = auto | monophonic | spectral.  Whole-file mode
      uses the same evidence to decide whether the file F0 may drive harmonic
      scoring and the legacy pitch penalty.
    - Report: per-frame diagnostics, events, summary counts.  Results file:
      pitch_interpretation, interpretation_label/_class, n_events,
      pitch_changes, sample_changes.

Changes in v1.11.0 (descriptor validity, numerical reliability):
    - DESCRIPTOR CONTRACTS.  Every descriptor is defined by an explicit
      extraction contract (rate, FFT, window, aggregation, units, ordering,
      distance).  A .db file is accepted only when its stored vectors are
      REPRODUCED by a named extractor on probe files taken from the corpus
      itself (recompute-and-compare).  Vector length alone never qualifies a
      database.  Categories: A = AudioTools contract reproduced, B = documented
      Orchidea definition reproduced, C = unverified/incompatible -> excluded
      from scoring and reported (never silently scored).
    - SPECTRAL MOMENTS.  The spectral PMF used an absolute 1e-10 floor, which
      made skewness/kurtosis level-dependent (identical 440 Hz sines at 0 dB
      and -40 dB: kurtosis 17.9 vs 143240, v1.10.3 moments distance 71611).
      The PMF is now normalised without an absolute floor, and the distance
      compares log2-centroid, log2-spread, asinh(skewness) and ln(kurtosis),
      each standardised by its robust corpus scale (MAD).  Default weight is 0
      until validated on the real corpus.
    - SPECTRAL PEAKS default weight is now 0.  The at1 contract stores the 16
      highest local maxima WITHOUT their frequencies; on noisy or vibrato
      sounds most of them are noise-ripple peaks whose height falls as more
      frames are averaged, so the descriptor encodes DURATION (a synthetic
      flute note re-synthesised 2.5x longer was 2.7 typical-pair distances
      from itself and retrieved the wrong note).  It remains selectable for
      experiments; no distance function can repair the stored representation.
    - CALIBRATED SCORES.  Each descriptor distance is divided by the median
      distance between random pairs of corpus entries in that descriptor
      (deterministic pair sample).  1.0 therefore means "as far apart as a
      typical pair of TinySOL notes", for every descriptor, so weights express
      relative influence.  Raw and calibrated distances are reported.
    - LEVEL-INVARIANT TIMBRE DISTANCES.  MFCC distance omits c0; log-spectral
      descriptors are compared after removing their mean (optimal gain
      alignment).  Target gain no longer changes the ranking.
    - SILENCE GATE.  match_threshold is expressed in calibrated units; 0 means
      off in BOTH analysis modes.  The legacy silence_threshold key is not
      reinterpreted on the new scale.
    - FRAME MODE uses the same 4096/2048 contract as whole-file mode (it used a
      different FFT size before), rejects frames shorter than one contract
      window, and no longer falls back silently to whole-file descriptors when
      a frame analysis fails.  Per-frame descriptors are computed once and the
      persistence check reuses the same scores (no rescoring).
    - RENDERING.  duration_policy=target (default) makes whole-file output
      exactly the target length, with a raised-cosine fade where samples are
      cut.  Reported layer counts are layers actually rendered.  Output gain is
      a peak target <= 1.0 (no hard clipping).
    - DIAGNOSTICS.  Optional JSON report; silence reasons distinguish silent
      target / no legal candidates / no valid descriptor comparison / score
      threshold / no frame matches / render failure.
    - FRAME OLA CONTINUITY.  Grains are read phase-coherently (corpus position
      advances 1:1 with output time) whenever the corpus sample is long
      enough; the v1.2 proportional read made overlapping grains cancel
      partially (4.7 dB hop-rate ripple on a steady tone).
    - PERFORMANCE.  Mel filterbank, DCT and calibration are cached; scoring is
      vectorised over the candidate domain.

Earlier history (v1.1 - v1.10.3) is kept in TinySOL_Retrieval.praat.

Dependencies: numpy, scipy, soundfile
"""

import sys
import os
import re
import math
import json
import functools

VERSION = "1.11.6"

# ─────────────────────────────────────────────────────────────────────────────
# Descriptor contract (AudioTools profile "at1")
# ─────────────────────────────────────────────────────────────────────────────

DB_NAMES = ("mfcc", "specenv", "moments", "specpeaks")
KNOWN_WEIGHT_NAMES = set(DB_NAMES) | {"harmonic"}
COMPACT_DESCRIPTOR_DIMS = {"mfcc": 20, "specenv": 24, "moments": 4, "specpeaks": 16}

DESCRIPTOR_SAMPLE_RATE = 44100
CONTRACT_N_FFT = 4096
CONTRACT_HOP = 2048
AT_PROFILE_ID = "audiotools-at1"

CONTRACT_TEXT = {
    "sample_rate": DESCRIPTOR_SAMPLE_RATE,
    "n_fft": CONTRACT_N_FFT,
    "hop": CONTRACT_HOP,
    "window": "numpy.hanning(4096) (symmetric Hann)",
    "frames": "floor((N - 4096) / 2048) + 1, single zero-padded frame if N < 4096",
    "channel": "strongest-RMS channel (TinySOL is mono)",
    "aggregation": "mean power spectrum over frames, then feature",
}

# Probe tolerance for recompute-and-compare verification.  Values are stored
# as text, typically float32: a faithful reproduction differs by ~1e-6
# relative.  1e-3 median / 2e-2 worst-file leaves room for float32 storage and
# platform FFT differences while rejecting a different algorithm (a different
# FFT size, band layout or scaling gives errors of 1e-1 and above).
PROBE_MEDIAN_TOL = 1e-3
PROBE_MAX_TOL = 2e-2
PROBE_MIN_FILES = 3

# Comparison-domain dynamic range (applies to mfcc / specenv / specpeaks).  Log-spectral components more than 80 dB
# below the strongest component of the same vector are set to that limit
# (target and corpus alike) before comparing.  Such components are decided
# by numerical floors and window leakage (stored as log(P + 1e-10)), not by
# timbre: without the limit a clean -40 dB sine moved 0.95 typical-pair
# distances in MFCC.  80 dB is below the noise floor of acoustic orchestral
# recordings; verify_tools reports how often real corpus vectors reach it.
DYNAMIC_RANGE_DB = 80.0
LN_POWER_DB = 10.0 / math.log(10.0)     # dB per natural-log unit of power
LN_MAG_DB = 20.0 / math.log(10.0)       # dB per natural-log unit of magnitude

# Calibration: deterministic random-pair sample of the corpus.
CALIB_SEED = 11011
CALIB_MAX_PAIRS = 4000

# Soft preferences, in CALIBRATED units (1.0 = typical distance between two
# random TinySOL notes).  One dynamic step away from the preferred set costs a
# tenth of that; one semitone of legacy pitch distance a twentieth.
# (v1.11.1: the frame persistence bonus is replaced by event-level Viterbi
#  selection with SWITCH_COST / PITCH_SWITCH_COST, defined with the event layer.)
DYN_PENALTY_PER_STEP = 0.10
LEGACY_PITCH_PENALTY_PER_ST = 0.05

DYN_ORDER = {"ppp": 0, "pp": 1, "p": 2, "mp": 3, "mf": 4, "f": 5, "ff": 6, "fff": 7}

FAMILY_MAP = {
    "Bn": "Winds",   "Cb": "Strings",  "Cb-": "Strings",
    "ClBb": "Winds", "Fl": "Winds",    "Hn": "Brass",
    "Ob": "Winds",   "TpC": "Brass",   "Tbn": "Brass",
    "BTb": "Brass",  "Va": "Strings",  "Vc": "Strings",
    "Vn": "Strings",
    "Acc": "Keyboards",
    "ASax": "Winds",
    "SaxA": "Winds",
}

NOTE_NAME_TO_MIDI = {}
_NOTE_LETTERS = ["C", "C#", "D", "D#", "E", "F",
                 "F#", "G", "G#", "A", "A#", "B"]
for _oct in range(0, 10):
    for _i, _name in enumerate(_NOTE_LETTERS):
        _midi = (_oct + 1) * 12 + _i
        NOTE_NAME_TO_MIDI["%s%d" % (_name, _oct)] = _midi
        if "#" in _name:
            _letter = _name[0]
            _next = chr(ord(_letter) + 1) if _letter != 'G' else 'A'
            NOTE_NAME_TO_MIDI[_next + "b" + str(_oct)] = _midi


def _hz_to_midi(hz):
    if hz is None or hz <= 0.0:
        return None
    return int(round(69.0 + 12.0 * math.log(hz / 440.0, 2)))


def check_dependencies():
    missing = []
    for pkg in ["numpy", "soundfile", "scipy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 — Parameter parsing
# ─────────────────────────────────────────────────────────────────────────────

def _split_csv(s):
    return [x.strip() for x in s.split(",") if x.strip()]


def _flag(v):
    return str(v).strip().lower() not in ("0", "false", "no", "")


def parse_params(params_path):
    params = {}
    with open(params_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, _, v = line.partition("=")
                params[k.strip()] = v.strip()

    params["_warnings"] = []

    # Legacy silence_threshold (v1.10.3 scale) is NOT reinterpreted.
    if "match_threshold" not in params and "silence_threshold" in params:
        try:
            legacy = float(params["silence_threshold"])
        except ValueError:
            legacy = 2.0
        if legacy < 2.0:
            params["_warnings"].append(
                "legacy silence_threshold=%.3f refers to the v1.10.3 score scale; "
                "it is ignored (gate off). Set match_threshold on the calibrated scale."
                % legacy)
        params["match_threshold"] = "0"

    defaults = {
        "db_dir": "", "corpus_root": "",
        "allowed_families": "Brass,Strings,Winds,Keyboards",
        "allowed_instruments": "",
        "min_midi": "21", "max_midi": "108",
        "preferred_dynamics": "",
        "max_layers": "4",
        "descriptor_weights": "mfcc:0.25,specenv:0.20,moments:0,specpeaks:0,harmonic:0.35",
        "n_results": "8",
        "render_mode": "best",
        "render_gain": "0.8",
        "envelope_follow": "0.85",
        "analysis_mode": "whole_file",
        "frame_size_ms": "150",
        "hop_size_ms": "75",
        "pitch_tolerance": "2",
        "match_threshold": "0",
        "speech_mode": "0",
        "duration_policy": "target",
        "report_path": "",
        "probe_files": "12",
        "allow_unverified": "0",
        "pitch_interpretation": "auto",
        "level_matching": "attenuate",
    }
    for k, v in defaults.items():
        params.setdefault(k, v)

    params["_allowed_families"] = _split_csv(params["allowed_families"])
    params["_allowed_instruments"] = [
        x for x in _split_csv(params["allowed_instruments"])
        if x and not x.startswith("(")]
    params["_preferred_dynamics"] = [d.lower() for d in _split_csv(params["preferred_dynamics"])]
    params["_min_midi"] = int(float(params["min_midi"]))
    params["_max_midi"] = int(float(params["max_midi"]))
    params["_max_layers"] = max(1, int(float(params["max_layers"])))
    params["_n_results"] = max(1, int(float(params["n_results"])))
    params["_render_gain"] = float(params["render_gain"])
    params["_envelope_follow"] = max(0.0, min(1.0, float(params["envelope_follow"])))
    params["_analysis_mode"] = params["analysis_mode"].strip().lower()
    params["_frame_size_ms"] = float(params["frame_size_ms"])
    params["_hop_size_ms"] = float(params["hop_size_ms"])
    params["_pitch_tolerance"] = int(float(params["pitch_tolerance"]))
    params["_match_threshold"] = float(params["match_threshold"])
    params["_speech_mode"] = _flag(params["speech_mode"])
    params["_duration_policy"] = params["duration_policy"].strip().lower()
    params["_report_path"] = params["report_path"].strip()
    params["_probe_files"] = max(PROBE_MIN_FILES, int(float(params["probe_files"])))
    params["_allow_unverified"] = _flag(params["allow_unverified"])
    params["_level_matching"] = params["level_matching"].strip().lower()
    if params["_level_matching"] not in LEVEL_MODES:
        raise ValueError("level_matching must be attenuate, bidirectional or off")
    for obsolete in ("stereo_output", "pitch_pan_stereo", "multichannel_path"):
        if obsolete in params:
            params["_warnings"].append(
                "%s is obsolete since v1.11.4 and ignored: the output is always one "
                "channel per rendered instrument, written to the normal output file" % obsolete)
    if "layer_selection" in params:
        params["_warnings"].append(
            "layer_selection is obsolete since v1.11.6 and ignored: render_mode always "
            "selects a fixed set of distinct instruments")
    params["_pitch_interpretation"] = params["pitch_interpretation"].strip().lower()
    if params["_pitch_interpretation"] not in PITCH_INTERPRETATIONS:
        raise ValueError("pitch_interpretation must be auto, monophonic or spectral")

    dw = {}
    for tok in params["descriptor_weights"].split(","):
        tok = tok.strip()
        if ":" in tok:
            name, w = tok.split(":", 1)
            try:
                dw[name.strip()] = float(w.strip())
            except ValueError:
                raise ValueError("Descriptor weight for '%s' is not a number: %r"
                                 % (name.strip(), w.strip()))
    if not dw:
        dw = {"mfcc": 0.25, "specenv": 0.20, "moments": 0.0,
              "specpeaks": 0.0, "harmonic": 0.35}
    params["_descriptor_weights"] = dw

    if params["_speech_mode"]:
        params["_descriptor_weights"] = {
            "mfcc": 0.45, "specenv": 0.30, "moments": 0.0,
            "specpeaks": 0.0, "harmonic": 0.00}
        print("  [PARAMS] speech_mode=1: descriptor weights overridden for speech input.")

    for name, w in params["_descriptor_weights"].items():
        if not math.isfinite(w) or w < 0:
            raise ValueError("Descriptor weight %s must be a finite number >= 0" % name)
    if sum(params["_descriptor_weights"].values()) <= 0.0:
        raise ValueError("At least one descriptor weight must be > 0")
    unknown = sorted(set(params["_descriptor_weights"]) - KNOWN_WEIGHT_NAMES)
    if unknown:
        raise ValueError("Unknown descriptor weight name(s): %s" % ", ".join(unknown))
    if params["_analysis_mode"] not in ("whole_file", "frame_based"):
        raise ValueError("analysis_mode must be whole_file or frame_based")
    if params["render_mode"] not in ("best", "blend", "top2", "top3", "top4"):
        raise ValueError("render_mode must be best, blend, top2, top3, or top4")
    if params["_duration_policy"] not in ("target", "natural"):
        raise ValueError("duration_policy must be target or natural")
    if params["_frame_size_ms"] <= 0 or params["_hop_size_ms"] <= 0:
        raise ValueError("frame_size_ms and hop_size_ms must be > 0")
    if params["_pitch_tolerance"] < 0:
        raise ValueError("pitch_tolerance must be >= 0")
    if params["_min_midi"] > params["_max_midi"]:
        raise ValueError("min_midi must be <= max_midi")
    if not math.isfinite(params["_match_threshold"]) or params["_match_threshold"] < 0:
        raise ValueError("match_threshold must be >= 0 (0 = gate off)")
    if not (0.0 < params["_render_gain"] <= 1.0):
        g = min(1.0, max(0.01, params["_render_gain"]))
        params["_warnings"].append("render_gain %.3f clamped to %.3f (peak target, no clipping)"
                                   % (params["_render_gain"], g))
        params["_render_gain"] = g
    return params


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — .db loading
# ─────────────────────────────────────────────────────────────────────────────

def _normalise_path(p):
    return p.replace("\\", "/").lower().strip()


def _path_stem(p):
    base = os.path.basename(p.replace("\\", "/"))
    stem, _ = os.path.splitext(base)
    return stem.lower().strip()


def _parse_row(line):
    """Return (path, vector) for a data row or None.  Rows whose values are
    not all finite numbers are malformed."""
    import numpy as np
    sep = line.find(";")
    if sep <= 0:
        return None
    raw_path = line[:sep]
    fields = [x for x in line[sep + 1:].split(";") if x.strip() != ""]
    if not fields:
        return None
    try:
        vec = np.array([float(x) for x in fields], dtype=np.float64)
    except ValueError:
        return None
    if not np.all(np.isfinite(vec)):
        return None
    return raw_path, vec


def _parse_header(line):
    """Parse an AudioTools provenance header:
        #AUDIOTOOLS_DESCRIPTOR_DB profile=audiotools-at1 descriptor=mfcc extractor=at1-mfcc dim=20 ...
    Returns dict (empty for any other header)."""
    out = {}
    if not line.startswith("#AUDIOTOOLS_DESCRIPTOR_DB"):
        return out
    for tok in line.split()[1:]:
        if "=" in tok:
            k, _, v = tok.partition("=")
            out[k] = v
    return out


class DbStore:
    """All loaded .db tables, with exact-path and unambiguous-stem indices."""

    def __init__(self):
        self.full_index = {}
        self.stem_index = {}
        self.ambiguous_stems = {}
        self.headers = {}
        self.header_info = {}
        self._sample_path = {}
        self.dimensions = {}
        self.malformed = {}
        self.paths = {}

    def load(self, db_dir, name):
        path = os.path.join(db_dir, "TinySOL.%s.db" % name)
        if not os.path.isfile(path):
            print("  [DB] WARNING: %s not found." % path, file=sys.stderr)
            return False
        full_tbl, stem_tbl, stem_paths = {}, {}, {}
        header, n_loaded, n_bad, first_raw = "", 0, 0, ""
        dims = {}
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for lineno, raw in enumerate(fh, 1):
                line = raw.rstrip("\r\n")
                if not line.strip():
                    continue
                parsed = _parse_row(line)
                if lineno == 1 and parsed is None:
                    header = line          # first line is a header only if not a data row
                    continue
                if parsed is None:
                    n_bad += 1
                    continue
                raw_path, vec = parsed
                norm_full = _normalise_path(raw_path)
                stem = _path_stem(raw_path)
                full_tbl[norm_full] = vec
                stem_paths.setdefault(stem, set()).add(norm_full)
                stem_tbl[stem] = vec
                dims[int(vec.size)] = dims.get(int(vec.size), 0) + 1
                n_loaded += 1
                if not first_raw:
                    first_raw = raw_path
        ambiguous = {s for s, ps in stem_paths.items() if len(ps) > 1}
        for s in ambiguous:
            stem_tbl.pop(s, None)
        self.full_index[name] = full_tbl
        self.stem_index[name] = stem_tbl
        self.ambiguous_stems[name] = ambiguous
        self.headers[name] = header
        self.header_info[name] = _parse_header(header)
        self._sample_path[name] = first_raw
        self.dimensions[name] = dims
        self.malformed[name] = n_bad
        self.paths[name] = path
        dim_text = "/".join("%d(x%d)" % (d, c) for d, c in sorted(dims.items())) or "?"
        print("  [DB] Loaded %-10s: %d rows  dim=%s  malformed=%d  ambiguous_stems=%d"
              % (name, n_loaded, dim_text, n_bad, len(ambiguous)))
        return True

    def get(self, name, abs_path):
        ft = self.full_index.get(name)
        if ft is not None:
            vec = ft.get(_normalise_path(abs_path))
            if vec is not None:
                return vec
        st = self.stem_index.get(name)
        if st is not None:
            return st.get(_path_stem(abs_path))
        return None

    def vectors(self, name):
        """All rows of one table in deterministic (sorted path) order."""
        tbl = self.full_index.get(name, {})
        return [tbl[k] for k in sorted(tbl)]


# ─────────────────────────────────────────────────────────────────────────────
# Stage 3/4 — filename parsing + index
# ─────────────────────────────────────────────────────────────────────────────

_FNAME_RE = re.compile(
    r"^(?P<inst>[A-Za-z]+(?:[A-Za-z#0-9]*?))"
    r"-(?P<tech>[a-zA-Z]+)"
    r"-(?P<note>[A-Gb#]+\d+)"
    r"-(?P<dyn>[a-zA-Z]+)"
    r"(?:-(?P<variant>\S+?))?"
    r"\.wav$",
    re.IGNORECASE,
)
_INST_PREFIXES = sorted(FAMILY_MAP.keys(), key=len, reverse=True)


def parse_filename(fname):
    base = os.path.basename(fname)
    m = _FNAME_RE.match(base)
    if not m:
        return None
    note = m.group("note")
    midi = _note_to_midi(note)
    if midi is None:
        return None
    inst = m.group("inst")
    return {"inst": inst, "tech": m.group("tech").lower(), "note": note,
            "dyn": m.group("dyn").lower(), "variant": m.group("variant") or "",
            "midi": midi, "family": _family_for_instrument(inst)}


def _note_to_midi(note_str):
    note_str_up = note_str[0].upper() + note_str[1:]
    if note_str_up in NOTE_NAME_TO_MIDI:
        return NOTE_NAME_TO_MIDI[note_str_up]
    norm = re.sub(r"([A-Ga-g])([#b]?)(\d+)",
                  lambda mm: mm.group(1).upper() + mm.group(2) + mm.group(3), note_str_up)
    return NOTE_NAME_TO_MIDI.get(norm)


def _family_for_instrument(inst):
    for prefix in _INST_PREFIXES:
        if inst.startswith(prefix):
            return FAMILY_MAP[prefix]
    if inst.startswith(("Vn", "Va", "Vc", "Cb")):
        return "Strings"
    if inst.startswith(("Fl", "Ob", "Cl", "Bn", "ASax", "Sax")):
        return "Winds"
    if inst.startswith(("Hn", "Tp", "Tbn", "BTb")):
        return "Brass"
    if inst.startswith(("Acc", "Acd")):
        return "Keyboards"
    return "Unknown"


def _family_from_path(path):
    canonical = {"brass": "Brass", "strings": "Strings",
                 "winds": "Winds", "keyboards": "Keyboards"}
    for part in [x for x in re.split(r"[\\/]+", str(path)) if x]:
        fam = canonical.get(part.strip().lower())
        if fam is not None:
            return fam
    return None


def _instrument_name_from_path(path):
    parts = [x for x in re.split(r"[\\/]+", str(path)) if x]
    for i, part in enumerate(parts):
        if part.strip().lower() == "ordinario" and i > 0:
            return parts[i - 1].strip()
    return ""


def _norm_label(text):
    return re.sub(r"[^a-z0-9]+", "", str(text).lower())


class TinySolEntry:
    __slots__ = ("abs_path", "norm_path", "inst", "instrument_name",
                 "tech", "note", "dyn", "variant", "midi", "family",
                 "descriptors")

    def __init__(self, abs_path, meta):
        self.abs_path = abs_path
        self.norm_path = _normalise_path(abs_path)
        self.inst = meta["inst"]
        self.instrument_name = _instrument_name_from_path(abs_path) or self.inst
        self.tech = meta["tech"]
        self.note = meta["note"]
        self.dyn = meta["dyn"]
        self.variant = meta["variant"]
        self.midi = meta["midi"]
        self.family = meta["family"]
        self.descriptors = {}

    def populate_descriptors(self, db_store, names=DB_NAMES):
        for name in names:
            vec = db_store.get(name, self.abs_path)
            if vec is not None:
                self.descriptors[name] = vec

    def __repr__(self):
        return "<Entry %s %s %s %s>" % (self.inst, self.note, self.dyn, self.variant)


def scan_corpus(corpus_root):
    """Walk corpus_root; return sorted list of TinySolEntry (no descriptors)."""
    entries, n_junk, n_nometa = [], 0, 0
    for dirpath, dirnames, filenames in os.walk(corpus_root):
        dirnames.sort()
        for fname in sorted(filenames):
            if os.path.splitext(fname)[1].lower() != ".wav":
                n_junk += 1
                continue
            abs_path = os.path.join(dirpath, fname)
            meta = parse_filename(fname)
            if meta is None:
                n_nometa += 1
                continue
            fam = _family_from_path(abs_path)
            if fam is not None:
                meta["family"] = fam
            entries.append(TinySolEntry(abs_path, meta))
    entries.sort(key=lambda e: e.norm_path)
    return entries, n_junk, n_nometa


def build_index(corpus_root, db_store, params=None):
    entries, n_junk, n_nometa = scan_corpus(corpus_root)
    for e in entries:
        e.populate_descriptors(db_store)
    n_with = sum(1 for e in entries if e.descriptors)
    print("  [IDX] Corpus entries: %d  (junk=%d, no-meta=%d, with-desc=%d)"
          % (len(entries), n_junk, n_nometa, n_with))
    if entries and n_with == 0:
        name = next(iter(db_store._sample_path), "mfcc")
        print("  [IDX] DIAG: corpus path sample : %s" % entries[0].abs_path, file=sys.stderr)
        print("  [IDX] DIAG: db path sample     : %s" % db_store._sample_path.get(name, "?"),
              file=sys.stderr)
    return entries


# ─────────────────────────────────────────────────────────────────────────────
# Stage 5 — DSP primitives (contract implementation)
# ─────────────────────────────────────────────────────────────────────────────

def _analysis_mono(audio):
    import numpy as np
    x = np.asarray(audio)
    if x.ndim == 1:
        return x, 0
    if x.shape[1] == 1:
        return x[:, 0], 0
    rms = np.sqrt(np.mean(x.astype(np.float64) ** 2, axis=0))
    ch = int(np.argmax(rms))
    return x[:, ch], ch


def _resample(x, sr_in, sr_out):
    import numpy as np
    if int(sr_in) == int(sr_out):
        return np.asarray(x)
    from scipy.signal import resample_poly
    g = math.gcd(int(sr_out), int(sr_in))
    return resample_poly(x, int(sr_out) // g, int(sr_in) // g)


@functools.lru_cache(maxsize=8)
def _hann(n):
    import numpy as np
    w = np.hanning(n)
    w.setflags(write=False)
    return w


def _stft_frames(x, n_fft, hop):
    import numpy as np
    window = _hann(n_fft)
    n_frames = max(1, (len(x) - n_fft) // hop + 1)
    out = np.zeros((n_fft // 2 + 1, n_frames), dtype=np.complex128)
    for i in range(n_frames):
        s = i * hop
        seg = x[s:s + n_fft]
        if len(seg) < n_fft:
            seg = np.pad(seg, (0, n_fft - len(seg)))
        out[:, i] = np.fft.rfft(seg * window)
    return out


def contract_power(x44):
    """Power spectrogram under the AudioTools contract (x at 44.1 kHz)."""
    import numpy as np
    return np.abs(_stft_frames(np.asarray(x44, dtype=np.float64),
                               CONTRACT_N_FFT, CONTRACT_HOP)) ** 2


@functools.lru_cache(maxsize=16)
def _mel_filterbank(sr, n_fft, n_mels):
    import numpy as np
    n_bins = n_fft // 2 + 1

    def hz2mel(h):
        return 2595.0 * np.log10(1.0 + h / 700.0)

    def mel2hz(m):
        return 700.0 * (10.0 ** (m / 2595.0) - 1.0)

    mel_pts = np.linspace(hz2mel(20.0), hz2mel(sr / 2.0), n_mels + 2)
    bin_pts = np.clip(np.floor((n_fft + 1) * mel2hz(mel_pts) / sr).astype(int), 0, n_bins - 1)
    fl = bin_pts[:-2][:, None].astype(np.float64)
    fc = bin_pts[1:-1][:, None].astype(np.float64)
    fr = bin_pts[2:][:, None].astype(np.float64)
    k = np.arange(n_bins, dtype=np.float64)
    rising = (k - fl) / np.maximum(1.0, fc - fl)
    falling = (fr - k) / np.maximum(1.0, fr - fc)
    fb = np.where((k >= fl) & (k <= fc), rising,
                  np.where((k > fc) & (k <= fr), falling, 0.0))
    fb = np.where((fc > fl) & (fr > fc), fb, 0.0)
    fb.setflags(write=False)
    return fb


@functools.lru_cache(maxsize=16)
def _dct_matrix(n_mfcc, n_mels):
    import numpy as np
    i_arr = np.arange(n_mfcc, dtype=np.float64)[:, None]
    m_arr = np.arange(n_mels, dtype=np.float64) + 0.5
    d = np.cos(math.pi * i_arr / n_mels * m_arr)
    d.setflags(write=False)
    return d


def _compute_mfcc(power, sr, n_fft, n_mels=20, n_mfcc=20):
    """at1-mfcc: log(mel energy of the frame-mean power + 1e-10), unnormalised
    DCT-II.  Identical numerics to v1.7-v1.10.3 (filterbank now cached)."""
    import numpy as np
    fb = _mel_filterbank(int(sr), int(n_fft), int(n_mels))
    mel_energy = np.log(fb.dot(power.mean(axis=1)) + 1e-10)
    return _dct_matrix(int(n_mfcc), int(n_mels)) @ mel_energy


def _compute_specenv(power, sr, n_fft, n_bands=24):
    """at1-specenv: natural log of mean power in n_bands equal-width
    linear-frequency bands over 0..sr/2.  NOT a cepstral envelope."""
    import numpy as np
    mean_power = np.asarray(power, dtype=np.float64).mean(axis=1)
    n_bins = int(mean_power.size)
    n_bands = int(n_bands)
    if n_bands < 1 or n_bands > n_bins:
        raise ValueError("specenv: %d bands requested from %d bins" % (n_bands, n_bins))
    edges = np.linspace(0, n_bins, n_bands + 1, dtype=int)
    env = np.empty(n_bands, dtype=np.float64)
    for b in range(n_bands):
        lo, hi = int(edges[b]), int(edges[b + 1])
        if hi <= lo:
            hi = min(n_bins, lo + 1)
        env[b] = np.log(np.mean(mean_power[lo:hi]) + 1e-10)
    return env


def _compute_moments(power, sr, n_fft):
    """at1-moments: centroid (Hz), spread (Hz), skewness, kurtosis (non-excess)
    of the frame-mean power spectrum treated as a PMF over 0..sr/2.

    v1.11: no absolute additive floor.  The old +1e-10 per bin made the PMF
    level-dependent (a -40 dB copy of a sine had 8000x the kurtosis).
    Returns NaN for an all-zero spectrum (no defined moments)."""
    import numpy as np
    n_bins = power.shape[0]
    freqs = np.linspace(0, sr / 2.0, n_bins)
    mean_power = np.asarray(power, dtype=np.float64).mean(axis=1)
    total = float(mean_power.sum())
    if not math.isfinite(total) or total <= 1e-300:
        return np.full(4, np.nan)
    pmf = mean_power / total
    c1 = float(np.dot(freqs, pmf))
    c2 = float(np.sqrt(np.dot((freqs - c1) ** 2, pmf)))
    if c2 > 0:
        z = (freqs - c1) / c2
        c3 = float(np.dot(z ** 3, pmf))
        c4 = float(np.dot(z ** 4, pmf))
    else:
        c3, c4 = 0.0, 1.0
    return np.array([c1, c2, c3, c4], dtype=np.float64)


def _compute_specpeaks(power, sr, n_fft, n_peaks=16):
    """at1-specpeaks: natural-log power of the n strongest local maxima of the
    frame-mean power spectrum, ordered by frequency; missing peaks filled with
    log(0.001 * mean power).  Frequencies are NOT stored.  Vectorised; identical
    selection and tie-breaking to the v1.10.3 loop."""
    import numpy as np
    mp = np.asarray(power, dtype=np.float64).mean(axis=1)
    noise_floor = float(np.log(np.mean(mp) * 0.001 + 1e-10))
    b = np.arange(1, mp.size - 1)
    is_peak = (mp[b] > mp[b - 1]) & (mp[b] > mp[b + 1])
    pb = b[is_peak]
    pa = mp[pb]
    order = np.lexsort((-pb, -pa))[:int(n_peaks)]      # amp desc, then bin desc
    sel = np.sort(pb[order])
    out = np.full(int(n_peaks), noise_floor, dtype=np.float64)
    out[:sel.size] = np.log(mp[sel] + 1e-10)
    return out


def _orch_cepstral_envelope(power, sr, n_fft, dim=1024, lifter=80, scale="ln"):
    """Reproduction of the DOCUMENTED OrchideaSOL spectral envelope (Cella &
    Ghisi 2020, sec. 5.3): per-frame log magnitude -> real cepstrum -> keep 80
    low quefrency coefficients -> FFT -> first 1024 bins, averaged over frames.
    Undocumented details (log base, averaging domain) are tried as variants;
    a variant counts only if it reproduces the stored vectors."""
    import numpy as np
    mag = np.sqrt(np.maximum(np.asarray(power, dtype=np.float64), 0.0))
    logmag = np.log(np.maximum(mag, 1e-12))
    cep = np.fft.irfft(logmag, n=n_fft, axis=0)
    lift = np.zeros(n_fft)
    lift[:lifter] = 1.0
    lift[n_fft - lifter + 1:] = 1.0
    env_ln = np.real(np.fft.rfft(cep * lift[:, None], axis=0))[:dim, :]
    if scale == "ln":
        return env_ln.mean(axis=1)
    if scale == "db":
        return (20.0 / math.log(10.0)) * env_ln.mean(axis=1)
    if scale == "lin":
        return np.exp(env_ln).mean(axis=1)
    raise ValueError(scale)


class Extractor:
    """One named descriptor extraction definition (a contract)."""

    def __init__(self, ext_id, descriptor, dim, fn, domain, category, db_per_unit=LN_POWER_DB):
        self.id = ext_id
        self.descriptor = descriptor
        self.dim = int(dim)
        self.fn = fn                 # fn(power, sr, n_fft) -> vector
        self.domain = domain         # mfcc | logspec | linspec | moments
        self.category = category     # "A" (AudioTools) or "B" (documented Orchidea)
        self.db_per_unit = float(db_per_unit)   # dB represented by one stored log unit

    def __call__(self, power, sr=DESCRIPTOR_SAMPLE_RATE, n_fft=CONTRACT_N_FFT):
        import numpy as np
        return np.asarray(self.fn(power, sr, n_fft), dtype=np.float64)

    def describe(self):
        return {"id": self.id, "descriptor": self.descriptor, "dim": self.dim,
                "domain": self.domain, "category": self.category,
                "db_per_unit": self.db_per_unit}


def at1_extractor(name, dim):
    dim = int(dim)
    if name == "mfcc":
        if not (2 <= dim <= 64):
            return None
        return Extractor("at1-mfcc%d" % dim, name, dim,
                         lambda p, sr, n: _compute_mfcc(p, sr, n, n_mels=max(20, dim), n_mfcc=dim),
                         "mfcc", "A")
    if name == "specenv":
        if not (4 <= dim <= 2048):
            return None
        return Extractor("at1-specenv-linband%d" % dim, name, dim,
                         lambda p, sr, n: _compute_specenv(p, sr, n, n_bands=dim),
                         "logspec", "A")
    if name == "moments":
        if dim != 4:
            return None
        return Extractor("at1-moments", name, 4, _compute_moments, "moments", "A")
    if name == "specpeaks":
        if not (1 <= dim <= 512):
            return None
        return Extractor("at1-specpeaks%d" % dim, name, dim,
                         lambda p, sr, n: _compute_specpeaks(p, sr, n, n_peaks=dim),
                         "logspec", "A")
    return None


def candidate_extractors(name, dim):
    """Every extraction definition that could have produced a <name> table of
    vector length <dim>.  Vector length only selects candidates; acceptance
    requires reproduction (see verify_descriptor)."""
    out = []
    at = at1_extractor(name, dim)
    if at is not None:
        out.append(at)
    if name == "specenv" and int(dim) == 1024:
        for scale, dom, dbu in (("ln", "logspec", LN_MAG_DB), ("db", "logspec", 1.0),
                                ("lin", "linspec", LN_MAG_DB)):
            out.append(Extractor("orchidea-doc-specenv-cep80-%s" % scale, name, 1024,
                                 functools.partial(_orch_cepstral_envelope, scale=scale),
                                 dom, "B", dbu))
    # OrchideaSOL specpeaks (120) layout is undocumented: no reproduction exists,
    # so such a table can only be category C.
    return out


def default_profile():
    return {n: at1_extractor(n, COMPACT_DESCRIPTOR_DIMS[n]) for n in DB_NAMES}


def descriptors_from_power(power, extractors, sr=DESCRIPTOR_SAMPLE_RATE):
    import numpy as np
    out = {}
    for name, ext in extractors.items():
        try:
            out[name] = ext(power, sr, CONTRACT_N_FFT)
        except Exception:
            out[name] = np.full(ext.dim, np.nan)
    return out


def load_contract_audio(path):
    """Strongest channel, resampled to 44.1 kHz, float64."""
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(path, always_2d=False)
    mono, ch = _analysis_mono(np.asarray(audio, dtype=np.float64))
    return np.asarray(_resample(mono, sr, DESCRIPTOR_SAMPLE_RATE), dtype=np.float64), int(sr), ch


# ─────────────────────────────────────────────────────────────────────────────
# Descriptor verification (recompute-and-compare)
# ─────────────────────────────────────────────────────────────────────────────

class DescriptorStatus:
    def __init__(self, name):
        self.name = name
        self.category = "C"
        self.extractor = None
        self.dim = None
        self.provenance = ""
        self.reason = ""
        self.probe = {}
        self.header = {}
        self.unverified_override = False

    @property
    def usable(self):
        return self.extractor is not None and (self.category in ("A", "B") or self.unverified_override)

    def to_dict(self):
        return {"descriptor": self.name, "category": self.category,
                "usable": self.usable,
                "unverified_override": self.unverified_override,
                "dim": self.dim,
                "extractor": self.extractor.describe() if self.extractor else None,
                "provenance": self.provenance, "reason": self.reason,
                "probe": self.probe, "header": self.header}


def _rel_err(a, b):
    import numpy as np
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    if a.shape != b.shape or not np.all(np.isfinite(a)):
        return float("inf")
    return float(np.linalg.norm(a - b) / max(np.linalg.norm(b), 1e-12))


def _probe_entries(entries, name, n_probe):
    pool = [e for e in entries if name in e.descriptors and os.path.isfile(e.abs_path)]
    if not pool:
        return []
    if len(pool) <= n_probe:
        return pool
    idx = sorted(set(int(round(i * (len(pool) - 1) / (n_probe - 1))) for i in range(n_probe)))
    return [pool[i] for i in idx]


def verify_descriptor(name, db_store, entries, n_probe=12, power_cache=None):
    """Decide category A/B/C for one loaded table by reproducing its vectors."""
    import numpy as np
    st = DescriptorStatus(name)
    dims = db_store.dimensions.get(name, {})
    st.header = dict(db_store.header_info.get(name, {}))
    if not db_store.full_index.get(name):
        st.reason = "no TinySOL.%s.db loaded or no valid rows" % name
        return st
    if len(dims) != 1:
        st.reason = "inconsistent vector lengths %s" % sorted(dims)
        return st
    dim = int(next(iter(dims)))
    st.dim = dim
    cands = candidate_extractors(name, dim)
    if st.header.get("extractor"):
        cands.sort(key=lambda c: 0 if c.id == st.header["extractor"] else 1)
    if not cands:
        st.reason = ("no known extraction definition produces %s vectors of length %d "
                     "(vector length alone is not evidence of compatibility)" % (name, dim))
        return st
    probes = _probe_entries(entries, name, n_probe)
    if len(probes) < PROBE_MIN_FILES:
        st.reason = ("only %d corpus WAV(s) with %s rows were found; at least %d are needed "
                     "to verify the table" % (len(probes), name, PROBE_MIN_FILES))
        st.extractor = cands[0]   # kept only for the optional unverified override
        return st
    if power_cache is None:
        power_cache = {}
    results = []
    for ext in cands:
        errs = []
        for e in probes:
            if e.abs_path not in power_cache:
                try:
                    x44, _, _ = load_contract_audio(e.abs_path)
                    power_cache[e.abs_path] = contract_power(x44)
                except Exception:
                    power_cache[e.abs_path] = None
            P = power_cache[e.abs_path]
            if P is None:
                errs.append(float("inf"))
                continue
            try:
                errs.append(_rel_err(ext(P), e.descriptors[name]))
            except Exception:
                errs.append(float("inf"))
        errs = np.asarray(errs)
        med = float(np.median(errs))
        mx = float(np.max(errs))
        ok = med <= PROBE_MEDIAN_TOL and mx <= PROBE_MAX_TOL
        results.append({"extractor": ext.id, "median_rel_err": med,
                        "max_rel_err": mx, "passed": bool(ok)})
        if ok and st.category == "C":
            st.extractor = ext
            st.category = ext.category
    st.probe = {"n_files": len(probes), "files": [os.path.basename(e.abs_path) for e in probes],
                "tolerance": {"median": PROBE_MEDIAN_TOL, "max": PROBE_MAX_TOL},
                "candidates": results}
    if st.category in ("A", "B"):
        st.provenance = ("header+probe" if st.header.get("extractor") == st.extractor.id
                         else "probe")
        st.reason = "reproduced by %s on %d corpus files" % (st.extractor.id, len(probes))
    else:
        best = min(results, key=lambda r: r["median_rel_err"])
        st.extractor = cands[0]
        claim = (" (header claims %s)" % st.header["extractor"]) if st.header.get("extractor") else ""
        st.reason = ("not reproduced by any known extractor%s; closest %s median rel. err %.3g"
                     % (claim, best["extractor"], best["median_rel_err"]))
    return st


def resolve_descriptor_profile(db_store, entries, params, names):
    """Verify each active table.  Returns {name: DescriptorStatus}."""
    statuses = {}
    cache = {}
    for name in names:
        st = verify_descriptor(name, db_store, entries, params["_probe_files"], cache)
        if not st.usable and params["_allow_unverified"] and st.extractor is not None \
                and st.extractor.category == "A" and st.dim is not None:
            st.unverified_override = True
            st.reason += "  [allow_unverified=1: SCORED ANYWAY, results are not validated]"
        statuses[name] = st
        flag = st.category + ("!" if st.unverified_override else "")
        print("  [VERIFY] %-10s cat=%s dim=%s  %s" % (name, flag, st.dim, st.reason))
    return statuses


# ─────────────────────────────────────────────────────────────────────────────
# Distances and calibration
# ─────────────────────────────────────────────────────────────────────────────

def _moments_transform(M):
    """[centroid Hz, spread Hz, skewness, kurtosis] -> [log2 centroid,
    log2 spread, asinh skewness, ln kurtosis].  Logs compress the scale-like
    quantities; asinh keeps the sign of skewness and grows logarithmically;
    kurtosis (non-excess) is >= 1 for every distribution so ln() >= 0.  1 Hz
    floors are far below the 10.8 Hz bin spacing of the contract."""
    import numpy as np
    M = np.atleast_2d(np.asarray(M, dtype=np.float64))
    out = np.empty_like(M)
    out[:, 0] = np.log2(np.maximum(M[:, 0], 1.0))
    out[:, 1] = np.log2(np.maximum(M[:, 1], 1.0))
    out[:, 2] = np.arcsinh(M[:, 2])
    out[:, 3] = np.log(np.maximum(M[:, 3], 1.0))
    return out


def _robust_scale(X):
    """Per-column MAD * 1.4826 (consistent with the standard deviation for
    Gaussian data); falls back to the standard deviation, then to 1."""
    import numpy as np
    med = np.median(X, axis=0)
    s = 1.4826 * np.median(np.abs(X - med), axis=0)
    sd = np.std(X, axis=0)
    s = np.where(s > 1e-9, s, sd)
    return np.where(s > 1e-9, s, 1.0)


def _floor_dynamic_range(L, units):
    """Raise every log component to at least (row max - units)."""
    import numpy as np
    return np.maximum(L, L.max(axis=1, keepdims=True) - units)


def floored_fraction(extractor, V):
    """Fraction of components raised by the dynamic-range floor (diagnostic)."""
    import numpy as np
    V = np.atleast_2d(np.asarray(V, dtype=np.float64))
    units = DYNAMIC_RANGE_DB / extractor.db_per_unit
    if extractor.domain == "mfcc":
        n = V.shape[1]
        if extractor.id != "at1-mfcc%d" % n or n < 20:
            return 0.0
        V = np.linalg.solve(_dct_matrix(n, n), V.T).T
    elif extractor.domain == "linspec":
        V = np.log(np.maximum(V, 1e-300))
    elif extractor.domain != "logspec":
        return 0.0
    return float(np.mean(V < V.max(axis=1, keepdims=True) - units))


class DescriptorSpace:
    """Preprocessing + RMS distance for one verified descriptor, with its
    corpus-null calibration scale."""

    def __init__(self, name, extractor, corpus_vectors):
        import numpy as np
        self.name = name
        self.extractor = extractor
        self.domain = extractor.domain
        V = np.asarray(corpus_vectors, dtype=np.float64)
        self.moment_scale = None
        if self.domain == "moments":
            self.moment_scale = _robust_scale(_moments_transform(V))
        self.null = calibrate_null(self.transform(V))
        self.scale = self.null["scale"]

    def transform(self, V):
        import numpy as np
        V = np.atleast_2d(np.asarray(V, dtype=np.float64))
        rng = DYNAMIC_RANGE_DB / self.extractor.db_per_unit
        if self.domain == "mfcc":
            n = V.shape[1]
            if self.extractor.id == "at1-mfcc%d" % n and n >= 20:
                D = _dct_matrix(n, n)                         # invertible when n_mfcc == n_mels
                L = np.linalg.solve(D, V.T).T                 # back to log-mel energies
                L = _floor_dynamic_range(L, rng)
                V = (D @ L.T).T
            return V[:, 1:]                                   # drop c0 (gain)
        if self.domain == "logspec":
            L = _floor_dynamic_range(V, rng)
            return L - L.mean(axis=1, keepdims=True)          # gain alignment
        if self.domain == "linspec":
            L = np.log(np.maximum(V, 1e-300))
            L = _floor_dynamic_range(L, rng)
            return L - L.mean(axis=1, keepdims=True)
        if self.domain == "moments":
            return _moments_transform(V) / self.moment_scale
        raise ValueError(self.domain)

    def raw_distance(self, Xt, t):
        """RMS difference between transformed corpus rows Xt and target t."""
        import numpy as np
        d = Xt - t[None, :]
        return np.sqrt(np.mean(d * d, axis=1))


def calibrate_null(X):
    """Median RMS distance between deterministic random pairs of rows.

    Rationale: dividing by the median of the corpus null distribution maps
    every descriptor to the same unit ("a typical pair of corpus notes"), is
    robust to heavy tails, and is reproducible (fixed seed, sorted rows)."""
    import numpy as np
    n = X.shape[0]
    if n < 2:
        return {"scale": 1.0, "n_pairs": 0, "status": "uncalibrated (fewer than 2 rows)",
                "q10": None, "q50": None, "q90": None}
    if n * (n - 1) // 2 <= CALIB_MAX_PAIRS:
        ii, jj = np.triu_indices(n, k=1)
    else:
        rng = np.random.default_rng(CALIB_SEED)
        ii = rng.integers(0, n, CALIB_MAX_PAIRS)
        jj = (ii + rng.integers(1, n, CALIB_MAX_PAIRS)) % n
    d = np.sqrt(np.mean((X[ii] - X[jj]) ** 2, axis=1))
    d = d[np.isfinite(d)]
    q10, q50, q90 = [float(np.percentile(d, q)) for q in (10, 50, 90)] if d.size else (0, 0, 0)
    if q50 > 1e-12:
        return {"scale": q50, "n_pairs": int(d.size), "status": "ok",
                "q10": q10, "q50": q50, "q90": q90}
    mean = float(np.mean(d)) if d.size else 0.0
    if mean > 1e-12:
        return {"scale": mean, "n_pairs": int(d.size), "status": "median zero; mean used",
                "q10": q10, "q50": q50, "q90": q90}
    return {"scale": 1.0, "n_pairs": int(d.size), "status": "degenerate (all rows identical)",
            "q10": q10, "q50": q50, "q90": q90}


def harmonic_contribution_distance(target_partials_hz, target_partials_amp,
                                   corpus_midi, n_harmonics=16, tolerance=0.03):
    """0 = the corpus note's harmonic series covers every target partial,
    1 = covers none.  (Unchanged from v1.3.)"""
    if not target_partials_hz or corpus_midi is None:
        return 0.5
    corpus_f0 = 440.0 * 2.0 ** ((corpus_midi - 69) / 12.0)
    harmonics = [corpus_f0 * h for h in range(1, n_harmonics + 1)]
    covered = total = 0.0
    for tp_hz, tp_amp in zip(target_partials_hz, target_partials_amp):
        total += tp_amp
        for ch in harmonics:
            if abs(ch - tp_hz) / max(1.0, tp_hz) < tolerance:
                covered += tp_amp
                break
    if total < 1e-12:
        return 0.5
    return 1.0 - covered / total


def _synthetic_partials(midi, n=16, nyq=20000.0):
    f0 = 440.0 * 2.0 ** ((midi - 69) / 12.0)
    hz = [f0 * h for h in range(1, n + 1) if f0 * h < nyq]
    amp = [1.0 / h for h in range(1, len(hz) + 1)]
    s = sum(amp)
    return hz, [a / s for a in amp]


def calibrate_harmonic(midis):
    """Null scale for the harmonic term: median distance between the 1/h
    harmonic series of one random corpus note and the pitch of another."""
    import numpy as np
    midis = np.asarray(sorted(midis))
    n = len(midis)
    if n < 2:
        return {"scale": 1.0, "n_pairs": 0, "status": "uncalibrated (fewer than 2 rows)"}
    rng = np.random.default_rng(CALIB_SEED)
    m = min(CALIB_MAX_PAIRS, n * (n - 1))
    ii = rng.integers(0, n, m)
    jj = (ii + rng.integers(1, n, m)) % n
    cache = {}
    d = []
    for i, j in zip(ii, jj):
        a, b = int(midis[i]), int(midis[j])
        if (a, b) not in cache:
            hz, amp = _synthetic_partials(a)
            cache[(a, b)] = harmonic_contribution_distance(hz, amp, b)
        d.append(cache[(a, b)])
    d = np.asarray(d)
    q50 = float(np.median(d))
    scale = q50 if q50 > 1e-6 else (float(np.mean(d)) if float(np.mean(d)) > 1e-6 else 1.0)
    return {"scale": scale, "n_pairs": int(m), "status": "ok" if q50 > 1e-6 else "median zero",
            "q10": float(np.percentile(d, 10)), "q50": q50, "q90": float(np.percentile(d, 90))}


class Calibration:
    """Corpus-level calibration (computed on every loaded row of each verified
    table, independent of the user's family/MIDI filters)."""

    def __init__(self, db_store, statuses, entries):
        self.spaces = {}
        for name, st in statuses.items():
            if st.usable:
                self.spaces[name] = DescriptorSpace(name, st.extractor, db_store.vectors(name))
        self.harmonic = calibrate_harmonic([e.midi for e in entries]) if entries else \
            {"scale": 1.0, "n_pairs": 0, "status": "uncalibrated"}

    def to_dict(self):
        out = {n: dict(s.null, extractor=s.extractor.id,
                       moment_scale=(s.moment_scale.tolist() if s.moment_scale is not None else None))
               for n, s in self.spaces.items()}
        out["harmonic"] = self.harmonic
        return out


class Scorer:
    """Vectorised, contract-consistent scoring over one legal candidate domain."""

    def __init__(self, domain, calibration, weights, preferred_dyns, speech_mode=False):
        import numpy as np
        self.domain = domain
        self.cal = calibration
        self.speech_mode = speech_mode
        self.weights = {k: float(v) for k, v in weights.items() if float(v) > 0}
        self.mats = {}
        for name, sp in calibration.spaces.items():
            if name in self.weights:
                self.mats[name] = sp.transform(np.vstack([e.descriptors[name] for e in domain])) \
                    if domain else None
        self.midi = np.array([e.midi for e in domain], dtype=np.int64)
        pref = [DYN_ORDER.get(d, 4) for d in preferred_dyns]
        pen = np.zeros(len(domain))
        if preferred_dyns:
            for i, e in enumerate(domain):
                if e.dyn not in preferred_dyns:
                    v = DYN_ORDER.get(e.dyn, 4)
                    pen[i] = DYN_PENALTY_PER_STEP * min(abs(v - p) for p in pref)
        self.dyn_penalty = pen

    def score(self, target_descs, target_partials=None, target_midi=None,
              gate_midi=None, gate_tol=0, harmonic_reason=None, allowed_midis=None):
        """Returns dict with 'score' (NaN = gated out), 'raw', 'cal',
        'used' (descriptors that contributed), 'skipped' (with reasons)."""
        import numpy as np
        n = len(self.domain)
        raw, cal, used, skipped = {}, {}, [], {}
        total = np.zeros(n)
        wsum = 0.0
        for name, w in self.weights.items():
            if name == "harmonic":
                if self.speech_mode:
                    skipped[name] = "speech mode"
                    continue
                if not target_partials:
                    skipped[name] = harmonic_reason or "target unvoiced (no partials)"
                    continue
                hz = [p[0] for p in target_partials]
                amp = [p[1] for p in target_partials]
                memo = {}
                d = np.array([memo.setdefault(int(m), harmonic_contribution_distance(hz, amp, int(m)))
                              for m in self.midi])
                scale = self.cal.harmonic["scale"]
            else:
                if name not in self.mats:
                    skipped[name] = "excluded (descriptor not verified)"
                    continue
                t = target_descs.get(name)
                if t is None or not np.all(np.isfinite(t)):
                    skipped[name] = "target descriptor undefined"
                    continue
                sp = self.cal.spaces[name]
                tt = sp.transform(t)[0]
                if tt.shape[0] != self.mats[name].shape[1]:
                    raise ValueError("Descriptor length mismatch for %s: target=%d corpus=%d"
                                     % (name, tt.shape[0], self.mats[name].shape[1]))
                d = sp.raw_distance(self.mats[name], tt)
                scale = sp.scale
            raw[name] = d
            cal[name] = d / scale
            total += w * cal[name]
            wsum += w
            used.append(name)
        if wsum <= 0:
            return {"score": np.full(n, np.nan), "raw": raw, "cal": cal,
                    "used": used, "skipped": skipped, "penalty": np.zeros(n)}
        pen = self.dyn_penalty.copy()
        if target_midi is not None and "harmonic" not in used and not self.speech_mode:
            pen = pen + LEGACY_PITCH_PENALTY_PER_ST * np.abs(self.midi - int(target_midi))
        score = total / wsum + pen
        if gate_midi is not None:
            score = np.where(np.abs(self.midi - int(gate_midi)) > gate_tol, np.nan, score)
        elif allowed_midis:
            ok = np.isin(self.midi, np.asarray(sorted(allowed_midis)))
            if ok.any():
                score = np.where(ok, score, np.nan)
        return {"score": score, "raw": raw, "cal": cal, "used": used,
                "skipped": skipped, "penalty": pen,
                "effective_weights": {k: self.weights[k] / wsum for k in used}}


def _active_db_descriptors(params):
    return [n for n in DB_NAMES if float(params["_descriptor_weights"].get(n, 0.0)) > 0.0]


def build_candidate_domain(entries, params, usable_names):
    """Hard constraints (family, instrument, MIDI range, complete verified
    descriptor set).  Returns (domain, rejection_counts)."""
    allowed_fam = set(params["_allowed_families"])
    allowed_inst = {_norm_label(x) for x in params["_allowed_instruments"] if x}
    required = set(usable_names)
    domain = []
    rej = {"family": 0, "instrument": 0, "midi": 0, "incomplete_descriptors": 0}
    for e in entries:
        if allowed_fam and e.family not in allowed_fam:
            rej["family"] += 1
            continue
        if allowed_inst and not (allowed_inst & {_norm_label(e.inst), _norm_label(e.instrument_name)}):
            rej["instrument"] += 1
            continue
        if e.midi < params["_min_midi"] or e.midi > params["_max_midi"]:
            rej["midi"] += 1
            continue
        if required and not required.issubset(e.descriptors.keys()):
            rej["incomplete_descriptors"] += 1
            continue
        domain.append(e)
    print("  [DOMAIN] %d legal candidates  (rejected: fam=%d inst=%d midi=%d incomplete_desc=%d)"
          % (len(domain), rej["family"], rej["instrument"], rej["midi"],
             rej["incomplete_descriptors"]))
    return domain, rej


# ─────────────────────────────────────────────────────────────────────────────
# Target analysis
# ─────────────────────────────────────────────────────────────────────────────

def _detect_f0(frame, sr, min_hz=40.0, max_hz=3000.0, voiced_thresh=0.35):
    """Overlap-normalised autocorrelation F0 (unchanged from v1.8)."""
    import numpy as np
    x = np.asarray(frame, dtype=np.float64)
    n = len(x)
    if n < 16:
        return None
    x = x - float(np.mean(x))
    x *= np.hanning(n)
    if float(np.dot(x, x)) < 1e-12:
        return None
    max_hz = min(float(max_hz), sr * 0.45)
    min_hz = max(20.0, float(min_hz))
    min_lag = max(1, int(sr / max_hz))
    max_lag = min(n - 3, int(sr / min_hz))
    if min_lag >= max_lag:
        return None
    nfft = 1 << int(math.ceil(math.log2(2 * n - 1)))
    X = np.fft.rfft(x, n=nfft)
    ac = np.fft.irfft(X * np.conj(X), n=nfft)[:n]
    cs = np.concatenate([[0.0], np.cumsum(x * x)])
    lags = np.arange(min_lag, max_lag + 1)
    denom = np.sqrt(np.maximum(cs[n - lags] * (cs[n] - cs[lags]), 1e-24))
    corr = ac[lags] / denom
    if len(corr) < 3:
        return None
    local = np.where((corr[1:-1] >= corr[:-2]) & (corr[1:-1] > corr[2:]))[0] + 1
    if len(local) == 0:
        j = int(np.argmax(corr))
        if corr[j] < voiced_thresh:
            return None
    else:
        peak_vals = corr[local]
        cands = local[peak_vals >= max(voiced_thresh, 0.88 * float(np.max(peak_vals)))]
        if len(cands) == 0:
            return None
        j = int(cands[0])
    lag = float(lags[j])
    if 0 < j < len(corr) - 1:
        y0, y1, y2 = float(corr[j - 1]), float(corr[j]), float(corr[j + 1])
        den = y0 - 2.0 * y1 + y2
        if abs(den) > 1e-12:
            delta = 0.5 * (y0 - y2) / den
            if abs(delta) <= 1.0:
                lag += delta
    return float(sr) / max(lag, 1e-12)


def analyse_target(audio_path, extractors=None):
    """Contract descriptors + median F0 + harmonic partials of the target.
    Returns (descriptors, original_sr, original_n_samples, pitch_info)."""
    import numpy as np
    import soundfile as sf
    if extractors is None:
        extractors = default_profile()
    elif extractors and not isinstance(next(iter(extractors.values())), Extractor):
        # v1.10.3 signature compatibility: {name: dim}
        extractors = {n: at1_extractor(n, d) for n, d in extractors.items()}
    info = sf.info(audio_path)
    x, sr, ch = load_contract_audio(audio_path)
    asr = DESCRIPTOR_SAMPLE_RATE
    power = contract_power(x)
    result = descriptors_from_power(power, extractors)

    pitch_frame = min(4096, len(x))
    pitch_hop = max(1, pitch_frame // 2)
    f0s = []
    n_pf = max(1, (len(x) - pitch_frame) // pitch_hop + 1)
    for i in range(n_pf):
        seg = x[i * pitch_hop:i * pitch_hop + pitch_frame]
        if len(seg) < pitch_frame:
            seg = np.pad(seg, (0, pitch_frame - len(seg)))
        f0 = _detect_f0(seg, asr)
        if f0 is not None:
            f0s.append(f0)
    n_voiced = len(f0s)
    median_f0 = float(np.median(f0s)) if f0s else None
    partials_hz, partials_amp = [], []
    if median_f0 is not None:
        mp = power.mean(axis=1)
        freqs = np.linspace(0, asr / 2.0, len(mp))
        noise_floor = float(np.mean(mp)) * 0.1
        for h in range(1, 17):
            fh = h * median_f0
            if fh >= asr / 2.0 - 100:
                break
            lo = max(0, int(fh * 0.85 / (asr / 2.0) * (len(mp) - 1)))
            hi = min(len(mp) - 1, int(fh * 1.15 / (asr / 2.0) * (len(mp) - 1)))
            if lo >= hi:
                continue
            pk = lo + int(np.argmax(mp[lo:hi + 1]))
            if float(mp[pk]) > noise_floor:
                partials_hz.append(float(freqs[pk]))
                partials_amp.append(float(mp[pk]))
        s = sum(partials_amp)
        if s > 0:
            partials_amp = [a / s for a in partials_amp]
    pitch_info = {
        "f0_hz": median_f0, "midi": _hz_to_midi(median_f0),
        "partials_hz": partials_hz, "partials_amp": partials_amp,
        "n_voiced": n_voiced, "n_frames": n_pf, "analysis_channel": ch + 1,
        "target_rms": float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0,
    }
    return result, int(info.samplerate), int(info.frames), pitch_info


def analyse_frames(audio_path, frame_size_ms, hop_size_ms, keep_power=False):
    """Per-frame level, silence and PITCH EVIDENCE (v1.11.1).

    Level/silence and the rendering grid use the target's own rate (as
    before).  Pitch evidence and descriptors share ONE contract spectrum per
    frame, computed from the 44.1 kHz copy (stored in frame["power"] when
    keep_power=True so descriptor extraction reuses it).

    Backward compatibility: frame["f0_hz"] / frame["midi"] are set ONLY for
    frames whose pitch is reliable (see classify_pitch_frame); uncertain
    frames carry f0_est + pitch_confidence instead."""
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(audio_path, always_2d=False)
    audio, ch = _analysis_mono(np.asarray(audio, dtype=np.float64))
    x = audio.astype(np.float64)
    x44 = np.asarray(_resample(x, sr, DESCRIPTOR_SAMPLE_RATE), dtype=np.float64)
    frame_size = max(64, int(round(frame_size_ms * sr / 1000.0)))
    hop_size = max(1, int(round(hop_size_ms * sr / 1000.0)))
    f44 = max(64, int(round(frame_size_ms * DESCRIPTOR_SAMPLE_RATE / 1000.0)))
    frames = []
    idx = 0
    while idx * hop_size < len(x):
        start = idx * hop_size
        frame = x[start:start + frame_size]
        if len(frame) < frame_size:
            frame = np.pad(frame, (0, frame_size - len(frame)))
        frames.append({"idx": idx, "time_s": start / sr, "start": start,
                       "rms": float(np.sqrt(np.mean(frame ** 2))),
                       "f0_hz": None, "midi": None, "silent": False,
                       "analysis_channel": ch + 1})
        idx += 1
    max_rms = max([f["rms"] for f in frames] + [0.0])
    floor = max(1e-10, max_rms * 10.0 ** (-70.0 / 20.0))
    for f in frames:
        f["silent"] = f["rms"] <= floor
        d0 = int(round(f["time_s"] * DESCRIPTOR_SAMPLE_RATE))
        seg = x44[d0:d0 + f44]
        if len(seg) < 64:
            f["silent"] = True
            f["power"] = None
            f["pitch"] = _silent_evidence("outside analysed audio")
            continue
        power = contract_power(seg)
        if keep_power:
            f["power"] = power
        if f["silent"]:
            f["pitch"] = _silent_evidence("silent frame")
        else:
            f["pitch"] = pitch_evidence(seg, power.mean(axis=1))
    finalize_pitch(frames, hop_size_ms / 1000.0)
    return frames, sr, len(x), frame_size, hop_size


# ─────────────────────────────────────────────────────────────────────────────
# Pitch evidence, frame classes and events (v1.11.1)
# ─────────────────────────────────────────────────────────────────────────────
#
# A frame is analysed with three independent kinds of evidence:
#   periodicity  P : normalised autocorrelation of the frame at the lag of the
#                    candidate F0 (overlap-energy normalised, as in v1.8);
#   harmonic fit E : share of the spectral-peak energy that lies on the
#                    harmonic series of the candidate F0, with the
#                    fundamental itself present (no "missing fundamental" -
#                    a chord's common subharmonic never qualifies);
#   occupancy    O : distinct harmonic slots filled / highest filled slot
#                    (a subharmonic explains peaks but leaves gaps);
# plus spectral context:
#   tonality       : share of the 0-6 kHz energy within +-2 bins of the 12
#                    strongest peaks (noise ~0.2, tones > 0.9);
#   extra sources  : share of the energy explained by a 2nd and 3rd harmonic
#                    series (each with its fundamental and >= 2 partials)
#                    found among the peaks the first series leaves over;
# and, after all frames are known, temporal consistency T (agreement with
# neighbouring frames, allowing glides up to GLIDE_ST_PER_S).
# Confidence = P * E * O * T, reported per frame.

PITCH_FMIN_HZ = 40.0
PITCH_FMAX_HZ = 2200.0
PEAK_FLOOR_DB = 50.0          # peaks within 50 dB of the strongest
PEAK_FMAX_HZ = 6000.0
PEAK_MAX_N = 48
HARM_KMAX = 16
HARM_GATHER_TOL = 0.06        # first pass: +-6 % of the F0 spacing
HARM_FINAL_TOL = 0.03         # after least-squares F0 refinement
HARM_TOL_BINS = 1.2           # never tighter than 1.2 FFT bins (12.9 Hz)
TONAL_MIN = 0.50              # below: noise-like / unpitched
REL_PERIODICITY = 0.50
REL_EXPLAINED = 0.80
REL_OCCUPANCY = 0.50
REL_CONFIDENCE = 0.35
POLY_MIN_SHARE = 0.10         # a 2nd harmonic source must carry >= 10 % energy
POLY_MIN_TOTAL = 0.75         # and 1-3 harmonic sources must explain >= 75 %
EXTRA_SOURCE_MIN_PARTIALS = 3 # a 2nd/3rd series needs >= 3 partials: two
                              # near-harmonic bell partials are not a "note"
STEP_MIN_ST = 0.75            # pitch step: jump >= 0.75 st after ...
STEP_STABLE_ST = 0.35         # ... a stable pitch (spread <= 0.35 st)
NEIGHBOUR_TOL_ST = 0.5
GLIDE_ST_PER_S = 15.0
ONSET_RISE_DB = 6.0
ONSET_FLOOR_DB = 50.0
NEW_PARTIAL_SHARE = 0.35
NEW_PARTIAL_TOL = 0.01
EVENT_MONO_SHARE = 0.60
EVENT_POLY_SHARE = 0.25
EVENT_TONAL_SHARE = 0.50
# Event-level selection (calibrated units: 1 = typical pair of corpus notes).
SWITCH_COST = {"monophonic": 0.15, "spectral": 0.50, "polyphonic": 0.50,
               "unpitched": 0.50, "ambiguous": 0.50}
PITCH_SWITCH_COST = {"monophonic": 0.30, "spectral": 0.50, "polyphonic": 0.50,
                     "unpitched": 0.50, "ambiguous": 0.50}
# Rationale: a sample change must be repaid by an accumulated score gain of
# SWITCH_COST (+ PITCH_SWITCH_COST if the MIDI note changes).  In monophonic
# events reliable frames carry the harmonic term, which separates the right
# note from a neighbour by ~0.4-0.6 units at default weights, so real note
# changes still pass while an isolated uncertain frame cannot move the pitch.
VITERBI_TOP_K = 8

PITCH_INTERPRETATIONS = ("auto", "monophonic", "spectral")
INTERPRETATION_LABELS = {
    "monophonic": "Monophonic — reliable pitch tracking",
    "spectral": "Spectral event — uncertain F0",
    "polyphonic": "Polyphonic event — no single F0",
    "unpitched": "Unpitched / noise — spectral retrieval",
    "ambiguous": "Ambiguous — pitch-neutral retrieval",
}


def _silent_evidence(reason):
    return {"class": "silent", "acf_f0": None, "f0_est": None, "periodicity": 0.0,
            "harmonic_share": 0.0, "occupancy": 0.0, "tonality": 0.0,
            "extra_sources": 0.0, "confidence": 0.0, "temporal": 0.0,
            "reliable": False, "reason": reason, "peaks": None, "partials": None,
            "sources": []}


def _acf_core(frame, sr, min_hz=40.0, max_hz=3000.0):
    """(lags, normalised correlation) used by _detect_f0 and periodicity."""
    import numpy as np
    x = np.asarray(frame, dtype=np.float64)
    n = len(x)
    if n < 16:
        return None
    x = x - float(np.mean(x))
    x = x * np.hanning(n)
    if float(np.dot(x, x)) < 1e-12:
        return None
    max_hz = min(float(max_hz), sr * 0.45)
    min_lag = max(1, int(sr / max_hz))
    max_lag = min(n - 3, int(sr / max(20.0, float(min_hz))))
    if min_lag >= max_lag:
        return None
    nfft = 1 << int(math.ceil(math.log2(2 * n - 1)))
    X = np.fft.rfft(x, n=nfft)
    ac = np.fft.irfft(X * np.conj(X), n=nfft)[:n]
    cs = np.concatenate([[0.0], np.cumsum(x * x)])
    lags = np.arange(min_lag, max_lag + 1)
    denom = np.sqrt(np.maximum(cs[n - lags] * (cs[n] - cs[lags]), 1e-24))
    return lags, ac[lags] / denom


def _spectral_peaks(mean_power, sr=DESCRIPTOR_SAMPLE_RATE, n_fft=CONTRACT_N_FFT):
    """Local maxima of the mean contract spectrum within PEAK_FLOOR_DB of the
    strongest, 30 Hz .. PEAK_FMAX_HZ, parabolically interpolated frequency,
    energy = 3-bin sum.  Returns (freqs, energies) sorted by frequency."""
    import numpy as np
    P = np.asarray(mean_power, dtype=np.float64)
    df = sr / float(n_fft)
    b = np.arange(1, P.size - 1)
    pb = b[(P[b] > P[b - 1]) & (P[b] >= P[b + 1])]
    pb = pb[(pb * df >= 30.0) & (pb * df <= PEAK_FMAX_HZ)]
    if pb.size == 0 or P[pb].max() <= 0:
        return np.zeros(0), np.zeros(0)
    pb = pb[P[pb] >= P[pb].max() * 10.0 ** (-PEAK_FLOOR_DB / 10.0)]
    pb = pb[np.argsort(-P[pb], kind="stable")][:PEAK_MAX_N]
    L = np.log(np.maximum(P, 1e-300))
    y0, y1, y2 = L[pb - 1], L[pb], L[pb + 1]
    den = y0 - 2.0 * y1 + y2
    d = np.clip(np.where(np.abs(den) > 1e-12, 0.5 * (y0 - y2) / np.where(den == 0, 1, den), 0.0), -0.5, 0.5)
    o = np.argsort(pb)
    return ((pb + d) * df)[o], (P[pb - 1] + P[pb] + P[pb + 1])[o]


def _harmonic_fit(f, a, c, df):
    """Two-pass harmonic-series fit of peaks (f, a) to candidate F0 c."""
    import numpy as np
    out = {"f0": c, "share": 0.0, "occupancy": 0.0, "fund": False, "ks": [], "mask": np.zeros(f.size, bool)}
    if f.size == 0 or c <= 0:
        return out
    for tol_frac in (HARM_GATHER_TOL, HARM_FINAL_TOL):
        k = np.round(f / c)
        tol = min(0.25 * c, max(tol_frac * c, HARM_TOL_BINS * df))
        m = (k >= 1) & (k <= HARM_KMAX) & (np.abs(f - k * c) <= tol)
        if not m.any():
            return out
        if tol_frac == HARM_GATHER_TOL:          # least-squares F0 refinement
            w = a[m]
            c = float(np.sum(w * f[m] * k[m]) / np.sum(w * k[m] ** 2))
    ks = sorted(set(int(v) for v in k[m]))
    out.update(f0=c, share=float(a[m].sum() / a.sum()), occupancy=len(ks) / float(max(ks)),
               fund=(1 in ks), ks=ks, mask=m)
    return out


def _best_series(f, a, df, seeds=(), min_partials=1):
    """Best-supported harmonic series among candidate F0s (seed values and
    their multiples/submultiples, strongest peaks and their 1/2, 1/3).
    Requires the fundamental to be present.  Score = share * occupancy;
    ties prefer the higher F0 (never a subharmonic)."""
    import numpy as np
    cands = set()
    for s in seeds:
        if s:
            cands |= {s * r for r in (0.5, 1.0, 2.0, 3.0, 4.0)}
    for fp in f[np.argsort(-a, kind="stable")][:6]:
        cands |= {fp, fp / 2.0, fp / 3.0}
    best = None
    for c in sorted(cands):
        if not (PITCH_FMIN_HZ <= c <= PITCH_FMAX_HZ):
            continue
        r = _harmonic_fit(f, a, c, df)
        if not r["fund"] or len(r["ks"]) < min_partials:
            continue
        s = r["share"] * r["occupancy"]
        if best is None or s > best[0] + 1e-9 or (abs(s - best[0]) <= 1e-9 and r["f0"] > best[1]["f0"]):
            best = (s, r)
    return best[1] if best else None


def pitch_evidence(seg44, mean_power, sr=DESCRIPTOR_SAMPLE_RATE):
    """Instantaneous pitch evidence of one frame (no temporal context yet)."""
    import numpy as np
    df = sr / float(CONTRACT_N_FFT)
    ev = _silent_evidence("")
    ev["class"] = "uncertain"
    acf = _acf_core(seg44, sr)
    ev["acf_f0"] = _detect_f0(seg44, sr)
    f, a = _spectral_peaks(mean_power, sr)
    P = np.asarray(mean_power, dtype=np.float64)
    lim = np.arange(P.size) * df <= PEAK_FMAX_HZ
    tot = float(P[lim].sum())
    if f.size and tot > 0:
        mask = np.zeros(P.size, bool)
        for fb in f[np.argsort(-a, kind="stable")][:12]:
            b = int(round(fb / df))
            mask[max(0, b - 2):b + 3] = True
        ev["tonality"] = float(P[mask & lim].sum() / tot)
    ev["peaks"] = (f, a)
    if f.size == 0:
        ev["reason"] = "no spectral peaks"
        ev["class"] = "unpitched"
        return ev
    first = _best_series(f, a, df, seeds=(ev["acf_f0"],))
    if first is None:
        ev["reason"] = "no harmonic series with a present fundamental"
        ev["class"] = "inharmonic" if ev["tonality"] >= TONAL_MIN else "unpitched"
        return ev
    c = first["f0"]
    # The v1.8 detector's value is kept when it agrees (<= 50 cents) with the
    # spectrally supported F0 -- unchanged behaviour on clean tones.
    if ev["acf_f0"] and abs(1200.0 * math.log2(ev["acf_f0"] / c)) <= 50.0:
        c = ev["acf_f0"]
    ev["f0_est"] = float(c)
    ev["harmonic_share"] = first["share"]
    ev["occupancy"] = first["occupancy"]
    if acf is not None:
        lags, corr = acf
        lag = sr / c
        if lags[0] <= lag <= lags[-1]:
            ev["periodicity"] = float(max(0.0, np.interp(lag, lags, corr)))
    covered = first["mask"].copy()
    extra = 0.0
    ev["sources"] = [(float(c), first["share"])]
    for _ in range(2):
        res = np.where(~covered)[0]
        if res.size < 2:
            break
        r2 = _best_series(f[res], a[res], df, min_partials=EXTRA_SOURCE_MIN_PARTIALS)
        if r2 is None:
            break
        share2 = float(a[res][r2["mask"]].sum() / a.sum())
        extra += share2
        ev["sources"].append((float(r2["f0"]), share2))
        covered[res[r2["mask"]]] = True
    ev["extra_sources"] = extra
    m = first["mask"]
    ev["partials"] = list(zip(f[m].tolist(), (a[m] / a[m].sum()).tolist()))
    if ev["tonality"] < TONAL_MIN:
        ev["class"], ev["reason"] = "unpitched", "noise-like spectrum (tonality %.2f)" % ev["tonality"]
    elif extra >= POLY_MIN_SHARE and first["share"] + extra >= POLY_MIN_TOTAL:
        ev["class"], ev["reason"] = "polyphonic", "several harmonic series (%.2f + %.2f)" % (first["share"], extra)
    elif (first["share"] >= REL_EXPLAINED and first["occupancy"] >= REL_OCCUPANCY
          and ev["periodicity"] >= REL_PERIODICITY):
        ev["class"], ev["reason"] = "harmonic", ""
    elif first["share"] + extra < POLY_MIN_TOTAL:
        ev["class"], ev["reason"] = "inharmonic", "peaks not explained by harmonic series (%.2f)" % (first["share"] + extra)
    else:
        ev["class"], ev["reason"] = "uncertain", "weak periodicity/harmonic support"
    ev["confidence"] = ev["periodicity"] * ev["harmonic_share"] * ev["occupancy"]
    return ev


def _midi_float(hz):
    return 69.0 + 12.0 * math.log2(hz / 440.0)


def finalize_pitch(frames, hop_s):
    """Temporal consistency, final confidence and reliability flags."""
    n = len(frames)
    m = [(_midi_float(fr["pitch"]["f0_est"]) if fr["pitch"]["class"] == "harmonic" and fr["pitch"]["f0_est"]
          else None) for fr in frames]
    for i, fr in enumerate(frames):
        ev = fr["pitch"]
        if ev["class"] == "silent":
            continue
        best = 0.0
        if m[i] is not None:
            for side in (-1, 1):
                ok = 0
                for d in (1, 2):
                    j = i + side * d
                    if 0 <= j < n and m[j] is not None and \
                            abs(m[j] - m[i]) <= NEIGHBOUR_TOL_ST + GLIDE_ST_PER_S * hop_s * d:
                        ok += 1
                best = max(best, ok / 2.0)
        ev["temporal"] = best
        ev["confidence"] = ev["periodicity"] * ev["harmonic_share"] * ev["occupancy"] * best
        ev["reliable"] = ev["class"] == "harmonic" and ev["confidence"] >= REL_CONFIDENCE
        if ev["class"] == "harmonic" and not ev["reliable"]:
            ev["reason"] = ("isolated pitch (no consistent neighbours)" if best == 0
                            else "low pitch confidence %.2f" % ev["confidence"])
        if ev["reliable"]:
            fr["f0_hz"] = ev["f0_est"]
            fr["midi"] = _hz_to_midi(ev["f0_est"])
        else:
            fr["f0_hz"] = None
            fr["midi"] = None


def _new_partial_share(prev, cur):
    import numpy as np
    if prev is None or cur is None:
        return 0.0
    (fp, _ap), (fc, ac) = prev, cur
    if fc.size == 0 or ac.sum() <= 0:
        return 0.0
    if fp.size == 0:
        return 1.0
    df = DESCRIPTOR_SAMPLE_RATE / float(CONTRACT_N_FFT)
    near = np.min(np.abs(fc[:, None] - fp[None, :]), axis=1) <= np.maximum(NEW_PARTIAL_TOL * fc, 1.5 * df)
    # v1.11.6: a peak that merely surfaced because stronger partials decayed
    # (relative-strength change) is not new energy.  It counts only when its
    # ABSOLUTE energy exceeds what the previous frame could have hidden: the
    # previous peak floor (PEAK_FLOOR_DB below its strongest peak) and, when
    # the previous list was truncated at PEAK_MAX_N, its weakest kept peak.
    hidden = float(_ap.max()) * 10.0 ** (-PEAK_FLOOR_DB / 10.0)
    if _ap.size >= PEAK_MAX_N:
        hidden = max(hidden, float(_ap.min()))
    new = (~near) & (ac > hidden)
    return float(ac[new].sum() / ac.sum())


STEP_DECAY_DB = 3.0           # level fall that marks "still decaying" (v1.11.6)
STEP_CONFIRM_ST = 1.0         # look-ahead frame must confirm the new pitch


def _pitch_step_supported(frames, level, cur, i, lag):
    """Event-context check for a candidate pitch_step (v1.11.6).
    Rejected when
      * the next frame does not confirm the new pitch (a single stable-looking
        estimate is not a note), or
      * the sound is only decaying: the level has fallen >= STEP_DECAY_DB
        since the previous non-overlapping frame AND no new spectral energy
        arrived (new-partial share below NEW_PARTIAL_SHARE).  This is the
        bell case: as upper partials die, a lower (sub)harmonic series that
        was already sounding becomes the best F0 fit.
    A legato note change keeps its level or brings new partials, so it passes."""
    ev = frames[i]["pitch"]
    if i + 1 >= len(frames):
        return False
    nx = frames[i + 1]["pitch"]
    if not (nx["reliable"] and nx["f0_est"] and
            abs(_midi_float(nx["f0_est"]) - _midi_float(ev["f0_est"])) <= STEP_CONFIRM_ST):
        return False
    j = max(cur["first"], i - lag)
    if j < i and level[i] <= level[j] - STEP_DECAY_DB and \
            _new_partial_share(frames[j]["pitch"]["peaks"], ev["peaks"]) < NEW_PARTIAL_SHARE:
        return False
    return True


def build_events(frames, hop_s, interpretation="auto", frame_s=None):
    """Segment frames into acoustic events and interpret each one.

    Boundaries (evidence, not a minimum duration):
      after_silence / start : first sounding frame;
      onset_energy          : level rises >= ONSET_RISE_DB over the lower of
                              the two previous frames (repeated attacks);
      pitch_step            : a reliable pitch jumps >= STEP_MIN_ST away from a
                              pitch that was stable over the previous frames
                              (a glide is never stable, so it never steps),
                              confirmed by the next frame and not a mere
                              decay without new energy (v1.11.6); never
                              under Spectral interpretation;
      new_partials          : >= NEW_PARTIAL_SHARE of the peak energy sits on
                              frequencies absent from the previous frame and
                              the change is not a continuous pitch glide
                              (legato note changes, new chord content).
    Decaying partials, changing balance, vibrato and glides create no
    boundary.  Event class = energy-weighted vote of its frames."""
    events = []
    lag = max(1, int(math.ceil((frame_s or 2 * hop_s) / hop_s - 1e-9)))
    level = [20.0 * math.log10(max(fr["rms"], 1e-12)) for fr in frames]
    peak_level = max(level) if level else 0.0
    cur = None
    for i, fr in enumerate(frames):
        ev = fr["pitch"]
        fr["event"] = -1
        fr["boundary"] = ""
        if ev["class"] == "silent":
            cur = None
            continue
        reason = ""
        if cur is None:
            reason = "start" if not events else "after_silence"
        else:
            lo = min(level[max(0, i - 2):i]) if i > 0 else level[i]
            rise = level[i] - lo >= ONSET_RISE_DB and level[i] >= peak_level - ONSET_FLOOR_DB
            prev_rise = False
            if i >= 2 and frames[i - 1]["event"] == cur["id"]:
                lo1 = min(level[max(0, i - 3):i - 1])
                prev_rise = level[i - 1] - lo1 >= ONSET_RISE_DB
            step = False
            # v1.11.6: under Spectral interpretation an F0 change never makes
            # a boundary on its own (attacks and new spectral energy still do).
            if interpretation != "spectral" and ev["reliable"] and \
                    frames[i - 1]["boundary"] != "pitch_step":
                prev = [_midi_float(frames[j]["pitch"]["f0_est"])
                        for j in range(max(cur["first"], i - 4), i) if frames[j]["pitch"]["reliable"]][-3:]
                if len(prev) >= 2 and max(prev) - min(prev) <= STEP_STABLE_ST:
                    mp = sorted(prev)[len(prev) // 2]
                    step = abs(_midi_float(ev["f0_est"]) - mp) >= STEP_MIN_ST
                if step:
                    step = _pitch_step_supported(frames, level, cur, i, lag)
            if rise and not prev_rise:
                reason = "onset_energy"
            elif step:
                reason = "pitch_step"
            elif frames[i - 1]["boundary"] not in ("new_partials", "pitch_step"):
                # Compare with the first previous frame that does not overlap
                # this one, so a change is not split over two overlapping frames.
                j = max(cur["first"], i - lag)
                pv = frames[j]["pitch"]
                glide = (pv["class"] == "harmonic" and ev["class"] == "harmonic" and pv["f0_est"] and ev["f0_est"]
                         and abs(_midi_float(ev["f0_est"]) - _midi_float(pv["f0_est"]))
                         <= NEIGHBOUR_TOL_ST + GLIDE_ST_PER_S * hop_s * (i - j))
                tonal = ev["class"] != "unpitched" and pv["class"] not in ("unpitched", "silent")
                if j < i and tonal and not glide and \
                        _new_partial_share(pv["peaks"], ev["peaks"]) >= NEW_PARTIAL_SHARE:
                    reason = "new_partials"
        if reason:
            cur = {"id": len(events), "first": i, "last": i, "reason": reason}
            events.append(cur)
        cur["last"] = i
        fr["event"] = cur["id"]
        fr["boundary"] = reason
    for e in events:
        idx = range(e["first"], e["last"] + 1)
        w = {k: 0.0 for k in ("reliable", "harmonic", "polyphonic", "inharmonic", "unpitched", "uncertain")}
        tot = 0.0
        for i in idx:
            ev = frames[i]["pitch"]
            en = frames[i]["rms"] ** 2
            tot += en
            if ev["reliable"]:
                w["reliable"] += en
            elif ev["class"] in w:
                w[ev["class"]] += en
        sh = {k: (v / tot if tot > 0 else 0.0) for k, v in w.items()}
        if interpretation == "monophonic":
            cls = "monophonic"
        elif interpretation == "spectral":
            cls = "spectral"
        elif sh["reliable"] >= EVENT_MONO_SHARE:
            cls = "monophonic"
        elif sh["polyphonic"] >= EVENT_POLY_SHARE and sh["polyphonic"] >= sh["inharmonic"]:
            cls = "polyphonic"
        elif sh["unpitched"] >= EVENT_TONAL_SHARE:
            cls = "unpitched"
        elif sh["inharmonic"] + sh["polyphonic"] + sh["harmonic"] + sh["uncertain"] >= EVENT_TONAL_SHARE:
            cls = "spectral"
        else:
            cls = "ambiguous"
        e["class"] = cls
        e["shares"] = sh
        e["pitch_set"] = _event_pitch_set(frames, e, cls)
        e["n_frames"] = e["last"] - e["first"] + 1
        e["start_s"] = frames[e["first"]]["time_s"]
    return events


def _event_pitch_set(frames, e, cls):
    """Evidenced pitches of an event (the stable orchestral reference).
    monophonic : notes of its RELIABLE frames;
    polyphonic : fundamentals of the harmonic series found in its frames,
                 energy-weighted, keeping those with >= 15 % of the event's
                 series energy (component notes, not a melody);
    otherwise  : empty (inharmonic / unpitched events stay pitch-neutral)."""
    idx = range(e["first"], e["last"] + 1)
    if cls == "monophonic":
        return sorted({_hz_to_midi(frames[i]["pitch"]["f0_est"]) for i in idx if frames[i]["pitch"]["reliable"]})
    if cls != "polyphonic":
        return []
    w = {}
    for i in idx:
        ev = frames[i]["pitch"]
        if ev["class"] not in ("polyphonic", "harmonic"):
            continue
        en = frames[i]["rms"] ** 2
        for f0, share in ev.get("sources", []):
            mm = _hz_to_midi(f0)
            if mm is not None:
                w[mm] = w.get(mm, 0.0) + en * share
    tot = sum(w.values())
    return sorted(m for m, v in w.items() if tot > 0 and v / tot >= 0.15)


def frame_pitch_gate(fr, event_class, interpretation, speech_mode):
    """Decide pitch gate + harmonic scoring for one frame.
    Returns (gate_midi or None, partials or None, reason)."""
    ev = fr["pitch"]
    if speech_mode:
        return None, None, "speech mode"
    if event_class != "monophonic":
        return None, None, "%s event: pitch-neutral" % event_class
    if ev["reliable"]:
        return _hz_to_midi(ev["f0_est"]), ev["partials"], ""
    if interpretation == "monophonic":
        # Explicit monophonic input: accept weaker-but-valid pitch, still
        # rejecting clearly invalid measurements.
        if (ev["f0_est"] and ev["acf_f0"] and ev["class"] in ("harmonic", "uncertain")
                and ev["harmonic_share"] >= 0.5 and ev["temporal"] >= 0.5):
            return _hz_to_midi(ev["f0_est"]), None, "monophonic: relaxed pitch, no harmonic scoring"
        return None, None, "invalid pitch rejected: %s" % (ev["reason"] or ev["class"])
    return None, None, "frame pitch unreliable: %s" % (ev["reason"] or ev["class"])


def interpretation_summary(events, frames):
    """Energy-dominant event class -> label for Praat/Info."""
    if not events:
        return "none", "No sounding events"
    w = {}
    for e in events:
        en = sum(frames[i]["rms"] ** 2 for i in range(e["first"], e["last"] + 1))
        w[e["class"]] = w.get(e["class"], 0.0) + en
    dom = max(w, key=w.get)
    label = INTERPRETATION_LABELS.get(dom, dom)
    if len(w) > 1:
        label += " (%d events, mixed)" % len(events)
    elif len(events) > 1:
        label += " (%d events)" % len(events)
    return dom, label


def _viterbi_select(S, midi, switch_cost, pitch_cost, top_k=VITERBI_TOP_K):
    """Piecewise-constant selection over consecutive frames.
    S: (F, N) scores, NaN = not allowed.  Each frame keeps its own best
    candidates; a change of sample costs switch_cost, a change of MIDI note
    additionally pitch_cost (calibrated units).  Returns domain indices."""
    import numpy as np
    F = S.shape[0]
    states = set()
    for r in range(F):
        row = S[r]
        ok = np.where(np.isfinite(row))[0]
        if ok.size:
            states |= set(ok[np.argsort(row[ok], kind="stable")[:top_k]].tolist())
    states = np.array(sorted(states))
    C = S[:, states]
    C = np.where(np.isfinite(C), C, np.inf)
    sm = midi[states]
    trans = switch_cost * (states[:, None] != states[None, :]) + \
        pitch_cost * (sm[:, None] != sm[None, :])
    D = C[0].copy()
    back = np.zeros((F, states.size), dtype=np.int64)
    for r in range(1, F):
        tot = D[:, None] + trans
        back[r] = np.argmin(tot, axis=0)
        D = tot[back[r], np.arange(states.size)] + C[r]
    path = [int(np.argmin(D))]
    for r in range(F - 1, 0, -1):
        path.append(int(back[r][path[-1]]))
    path.reverse()
    return [int(states[p]) for p in path]


# ─────────────────────────────────────────────────────────────────────────────
# Retrieval
# ─────────────────────────────────────────────────────────────────────────────

def retrieve(scorer, target_descs, target_midi=None, target_partials=None,
             harmonic_reason=None):
    """Whole-file ranking.  Returns (scored_list, score_info) where scored_list
    holds (score, entry, detail) sorted ascending, best variant per
    (instrument, note, dynamic)."""
    import numpy as np
    info = scorer.score(target_descs, target_partials, target_midi,
                        harmonic_reason=harmonic_reason)
    s = info["score"]
    best = {}
    for i, e in enumerate(scorer.domain):
        if not np.isfinite(s[i]):
            continue
        key = (e.inst, e.note, e.dyn)
        if key not in best or s[i] < s[best[key]]:
            best[key] = i
    order = sorted(best.values(), key=lambda i: (s[i], scorer.domain[i].norm_path))
    out = []
    for i in order:
        detail = {"raw": {k: float(v[i]) for k, v in info["raw"].items()},
                  "cal": {k: float(v[i]) for k, v in info["cal"].items()},
                  "penalty": float(info["penalty"][i])}
        out.append((float(s[i]), scorer.domain[i], detail))
    return out, info


# ─────────────────────────────────────────────────────────────────────────────
# Rendering
# ─────────────────────────────────────────────────────────────────────────────

def load_audio(path, target_sr=None):
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(path, always_2d=False)
    audio, _ = _analysis_mono(np.asarray(audio, dtype=np.float32))
    if target_sr is not None and sr != target_sr:
        audio = _resample(audio, sr, target_sr)
        sr = int(target_sr)
    return np.asarray(audio, dtype=np.float32), int(sr)


def _fade_out(n, sr, max_ms=20.0):
    """Raised-cosine fade length: 20 ms, or 10% of the output if shorter."""
    return max(1, min(int(round(max_ms * 1e-3 * sr)), max(1, n // 10)))


RENDER_LAYERS = {"best": 1, "blend": 3, "top2": 2, "top3": 3, "top4": 4}

# Orchestral score order of the TinySOL instrument prefixes; used to order the
# multichannel stems in frame mode (unknown instruments follow, alphabetically).
SCORE_ORDER = ["Fl", "Ob", "ClBb", "Bn", "ASax", "SaxA", "Hn", "TpC", "Tbn", "BTb",
               "Acc", "Vn", "Va", "Vc", "Cb"]


def instrument_key(entry):
    """Channel identity of a corpus entry: (family, instrument).  The
    instrument is TinySOL's own folder name when the official layout is used,
    otherwise the filename prefix; nothing else is inferred."""
    return (entry.family, entry.instrument_name or entry.inst)


def distinct_instruments(scored):
    """Keep the best-scoring entry of each instrument, in score order (v1.11.5).
    Scores and their order are unchanged; only lower-ranked entries of an
    instrument that already appears are dropped, so the first N layers are N
    different instruments (= N output channels) whenever N are available."""
    seen, out = set(), []
    for item in scored:
        k = instrument_key(item[1])
        if k in seen:
            continue
        seen.add(k)
        out.append(item)
    return out


def _score_rank(stem):
    p = stem["prefix"]
    return (SCORE_ORDER.index(p) if p in SCORE_ORDER else len(SCORE_ORDER), stem["instrument"].lower())


def _new_stem(entry, n):
    import numpy as np
    fam, name = instrument_key(entry)
    return {"family": fam, "instrument": name, "prefix": entry.inst,
            "audio": np.zeros(n), "files": [], "midis": [], "units": 0, "weights": [], "ranks": [],
            "notes": [], "dyns": [], "scores": [], "spans": []}


def _note_use(stem, entry, weight=None, rank=None, span=None, score=None):
    fn = os.path.basename(entry.abs_path)
    if fn not in stem["files"]:
        stem["files"].append(fn)
    if entry.midi not in stem["midis"]:
        stem["midis"].append(entry.midi)
        stem["notes"].append(entry.note)
    if entry.dyn not in stem["dyns"]:
        stem["dyns"].append(entry.dyn)
    if score is not None and math.isfinite(score):
        stem["scores"].append(float(score))
    if span is not None:
        stem["spans"].append((int(span[0]), int(span[1]), entry.midi, entry.note))
    stem["units"] += 1
    if weight is not None:
        stem["weights"].append(weight)
    if rank is not None:
        stem["ranks"].append(rank)


def blend_samples(entries_and_scores, target_len_samples, sr, render_mode, gain,
                  duration_policy="target", return_info=False, normalize=True, ranks=None):
    """Mix the top-N retrieved samples (independent per-sample ranking; this is
    not a joint orchestration optimisation).

    duration_policy: 'target'  -> output is exactly target_len_samples; a layer
                                  longer than that is cut with a raised-cosine
                                  fade (20 ms max).
                     'natural' -> output is max(target, longest layer)."""
    import numpy as np
    n = min(RENDER_LAYERS.get(render_mode, 1), len(entries_and_scores))
    if ranks is None:
        ranks = list(range(1, len(entries_and_scores) + 1))
    raw_w = [1.0 / (i + 1) for i in range(n)] if render_mode == "blend" else [1.0] * n
    audios, weights, rendered, failed, rentries, rscores = [], [], [], [], [], []
    # v1.11.6: walk the (instrument-distinct) list until n layers have LOADED;
    # a sample that fails is reported and the next instrument takes its place,
    # so a failure never leaves a channel with false metadata.
    for idx, (_s, entry, _d) in enumerate(entries_and_scores):
        if len(audios) >= n:
            break
        try:
            if not os.path.isfile(entry.abs_path):
                raise IOError("file not found")
            aud, _ = load_audio(entry.abs_path, target_sr=sr)
            if aud.size == 0:
                raise IOError("empty file")
            audios.append(aud.astype(np.float64))
            weights.append(raw_w[len(audios) - 1])
            rendered.append(ranks[idx])
            rentries.append(entry)
            rscores.append(float(_s))
        except Exception as exc:
            failed.append({"rank": ranks[idx], "path": entry.abs_path, "error": str(exc)})
            print("  [RENDER] WARNING: could not load %s: %s" % (entry.abs_path, exc),
                  file=sys.stderr)
    tl = max(1, int(target_len_samples))
    if duration_policy == "natural" and audios:
        out_len = max(tl, max(len(a) for a in audios))
    else:
        out_len = tl
    info = {"selected": n, "rendered_ranks": rendered, "failed": failed,
            "truncated_layers": 0, "fade_samples": 0, "out_len": out_len, "stems": [],
            "norm_gain": 1.0}
    if not audios:
        out = np.zeros(out_len, dtype=np.float32)
        return (out, info) if return_info else out
    total_w = sum(weights)
    fade = _fade_out(out_len, sr)
    ramp = 0.5 * (1.0 + np.cos(np.linspace(0.0, math.pi, fade)))
    layers = []
    for aud in audios:
        lay = np.zeros(out_len)
        m = min(len(aud), out_len)
        lay[:m] = aud[:m]
        if len(aud) > out_len:
            lay[out_len - fade:] *= ramp
            info["truncated_layers"] += 1
            info["fade_samples"] = fade
        layers.append(lay)
    # Instrument stems (v1.11.3): one unpanned mono bus per distinct rendered
    # instrument, in order of first rendered rank; layers of the same
    # instrument are summed into its bus with their mixing weights.
    stems = {}
    for lay, w, e, rk, sc, aud in zip(layers, weights, rentries, rendered, rscores, audios):
        k = instrument_key(e)
        if k not in stems:
            stems[k] = _new_stem(e, out_len)
        stems[k]["audio"] += (w / total_w) * lay
        _note_use(stems[k], e, weight=w / total_w, rank=rk, span=(0, min(len(aud), out_len)), score=sc)
    stem_list = list(stems.values())
    out = np.zeros(out_len)                     # internal reference mix = sum of buses
    for st in stem_list:
        out += st["audio"]
    scale = 1.0
    peak = float(np.max(np.abs(out)))
    if normalize and peak > 1e-12:
        scale = gain / peak
    out = (out * scale).astype(np.float32)
    for st in stem_list:
        st["audio"] = st["audio"] * scale
    info["stems"] = stem_list
    info["norm_gain"] = scale
    return (out, info) if return_info else out


def _envelope_power_trace(audio):
    import numpy as np
    x = np.asarray(audio, dtype=np.float64)
    return x * x if x.ndim == 1 else np.mean(x * x, axis=1)


def _macro_rms_envelope(audio, sr, smooth_ms=100.0):
    import numpy as np
    from scipy.ndimage import gaussian_filter1d
    p = _envelope_power_trace(audio)
    if p.size == 0:
        return np.zeros(0)
    sigma = max(1.0, (smooth_ms * 0.001 * sr) / 2.355)
    return np.sqrt(np.maximum(gaussian_filter1d(p, sigma=sigma, mode="nearest"), 0.0))


def _norm_envelope(env):
    import numpy as np
    env = np.asarray(env, dtype=np.float64)
    if env.size == 0:
        return env
    ref = float(np.percentile(env, 95.0))
    if ref <= 1e-12:
        ref = float(np.max(env))
    if ref <= 1e-12:
        return np.zeros_like(env)
    return np.clip(env / ref, 0.0, 1.5)


def _envelope_correlation(a, b):
    import numpy as np
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    if len(a) != len(b) or len(a) < 2:
        return 0.0
    if np.std(a) < 1e-10 or np.std(b) < 1e-10:
        return 1.0 if np.allclose(a, b, atol=1e-8) else 0.0
    return float(np.corrcoef(a, b)[0, 1])


def apply_target_macro_envelope(output, target_audio, sr, amount,
                                smooth_ms=100.0, boost_limit_db=12.0):
    """Transfer the target's macro RMS gesture (unchanged from v1.9).
    amount=0 preserves the samples' own dynamics exactly; the output peak is
    restored to its pre-transfer value, so no clipping is introduced."""
    import numpy as np
    x = np.asarray(output, dtype=np.float64)
    amount = float(np.clip(amount, 0.0, 1.0))
    stats0 = {"envelope_follow": amount, "envelope_corr_before": 0.0, "envelope_corr_after": 0.0}
    if x.size == 0 or amount <= 0.0:
        return np.asarray(output).copy(), stats0
    target_env = _norm_envelope(_macro_rms_envelope(target_audio, sr, smooth_ms))
    out_env = _norm_envelope(_macro_rms_envelope(x, sr, smooth_ms))
    n = x.shape[0]
    if len(target_env) == 0 or len(out_env) == 0:
        return np.asarray(output).copy(), stats0
    if len(target_env) != n:
        target_env = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(target_env)), target_env)
    if len(out_env) != n:
        out_env = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(out_env)), out_env)
    corr_before = _envelope_correlation(target_env, out_env)
    ratio = np.clip(target_env / np.maximum(out_env, 10.0 ** (-30.0 / 20.0)),
                    0.0, 10.0 ** (boost_limit_db / 20.0))
    g = (1.0 - amount) + amount * ratio
    y = x * g if x.ndim == 1 else x * g[:, None]
    pb = float(np.max(np.abs(x)))
    pa = float(np.max(np.abs(y)))
    restore = pb / pa if (pb > 1e-12 and pa > 1e-12) else 1.0
    y *= restore
    corr_after = _envelope_correlation(target_env, _norm_envelope(_macro_rms_envelope(y, sr, smooth_ms)))
    return y.astype(np.float32), {"envelope_follow": amount,
                                  "envelope_corr_before": corr_before,
                                  "envelope_corr_after": corr_after,
                                  "_curve": g * restore}


def apply_curve_to_stems(stems, curve):
    """Apply the envelope-transfer gain curve computed from the COMBINED mix
    to every instrument stem (no per-stem envelope follower)."""
    if curve is None:
        return
    for st in stems:
        st["audio"] = st["audio"] * curve


def render_frame_matches(frame_matches, frame_size, hop_size, target_len, sr, gain,
                         return_info=False, normalize=True):
    """Overlap-add of per-frame grains (v1.2 logic).  Returns the audio and,
    on request, how many matched frames actually produced audio.

    v1.11.3: every grain is also added, unpanned, to the bus of its
    instrument.  All buses and the preview share ONE overlap-add
    normalisation curve and one scale factor, so the buses sum exactly to
    the internal reference mix returned as the first value."""
    import numpy as np
    out_len = max(target_len, (len(frame_matches) - 1) * hop_size + frame_size)
    out = np.zeros(out_len)
    norm = np.zeros(out_len)
    stems = {}
    hann = np.hanning(frame_size)
    cache, failed_paths = {}, set()
    total = max(1, (len(frame_matches) - 1) * hop_size + frame_size)
    n_rendered = 0
    for fm in frame_matches:
        fi, match = fm["frame"], fm["match"]
        start = fi["start"]
        end = start + frame_size
        norm[start:end] += hann
        fm["rendered"] = False
        fm.pop("read_mode", None)
        if match is None:
            continue
        layers = fm.get("layers") or [{"voice": 1, "match": match, "weight": 1.0}]
        for lay in layers:
            if _render_grain(fm, fi, lay["match"][1], lay["weight"], start, end, frame_size,
                             target_len, total, sr, hann, cache, failed_paths, stems, out,
                             score=lay["match"][0]):
                fm["rendered"] = True
        if fm["rendered"]:
            n_rendered += 1
    safe = np.maximum(norm, 1e-9)
    out /= safe
    stem_list = sorted(stems.values(), key=_score_rank)
    for st in stem_list:
        st["audio"] = st["audio"] / safe
    scale = 1.0
    peak = float(np.max(np.abs(out)))
    if normalize and peak > 1e-12:
        scale = gain / peak
    out *= scale
    res = out[:target_len].astype(np.float32)
    for st in stem_list:
        st["audio"] = st["audio"][:target_len] * scale
    info = {"rendered_frames": n_rendered, "failed_files": sorted(failed_paths),
            "coherent_frames": sum(1 for fm in frame_matches if fm.get("read_mode") == "coherent"),
            "stems": stem_list, "norm_gain": scale}
    return (res, info) if return_info else res


def _render_grain(fm, fi, entry, weight, start, end, frame_size, target_len, total, sr, hann,
                  cache, failed_paths, stems, out, score=None):
    """One grain of one voice (v1.2/v1.11.1 read logic, unchanged); the grain
    is scaled to weight * frame RMS.  Returns True when audio was added."""
    import numpy as np
    if entry.abs_path not in cache:
        try:
            cache[entry.abs_path], _ = load_audio(entry.abs_path, target_sr=sr)
        except Exception:
            failed_paths.add(entry.abs_path)
            cache[entry.abs_path] = None
    ca = cache[entry.abs_path]
    if ca is None or ca.size == 0:
        return False
    s0 = max(int(0.20 * len(ca)), int(0.050 * sr))
    s1 = len(ca) - frame_size
    if s1 <= s0:
        s0, s1 = 0, max(0, len(ca) - frame_size)
    slen = max(1, s1 - s0)
    if "event_start" in fm:
        # v1.11.1: event-relative read.  Each acoustic event starts the
        # corpus sample from its beginning (a repeated attack re-articulates);
        # within the event the read is phase-coherent, also across a
        # selection change (the new sample is read at the same event time).
        ev_len = fm["event_end"] - fm["event_start"]
        rel = start - fm["event_start"]
        if ev_len <= len(ca):
            ro = rel
            mode = "coherent"
        else:
            span = max(1, len(ca) - frame_size)
            ro = min(int(float(rel) / max(1, ev_len) * span), span)
            mode = "proportional"
    elif target_len <= len(ca):
        s0c = max(0, min(s0, len(ca) - target_len))   # skip as much attack as fits
        # v1.11: phase-coherent read.  Corpus position advances 1:1 with
        # output time, so overlapping grains of the same sample hold the
        # SAME audio and the Hann OLA reconstructs it exactly.  The v1.2
        # proportional mapping advanced at slen/total samples per sample,
        # so overlapping grains of a harmonic tone summed out of phase:
        # measured 4.7 dB hop-rate ripple on a steady tone (1.2 dB in the
        # source), now ~source level.
        ro = s0c + start
        mode = "coherent"
    else:
        # Sample shorter than the target: spread one pass over the sustain
        # region (v1.2 behaviour; overlap is not phase-coherent here).
        ro = min(s0 + int(float(start) / float(total) * slen), s0 + slen - 1)
        mode = "proportional"
    fm.setdefault("read_mode", mode)
    if mode == "coherent":
        grain = np.zeros(frame_size)
        seg = ca[ro:ro + frame_size]
        grain[:len(seg)] = seg                 # past the end: zero tail
    elif ro + frame_size <= len(ca):
        grain = ca[ro:ro + frame_size].astype(np.float64)
    elif len(ca) >= frame_size:
        grain = ca[:frame_size].astype(np.float64)
    else:
        grain = np.zeros(frame_size)
        grain[:len(ca)] = ca
    grain = grain * hann
    grms = float(np.sqrt(np.mean(grain ** 2)))
    if fi["rms"] <= 1e-10 or grms <= 1e-9:
        return False
    grain *= weight * fi["rms"] / grms
    k = instrument_key(entry)
    if k not in stems:
        stems[k] = _new_stem(entry, len(out))
    stems[k]["audio"][start:end] += grain
    _note_use(stems[k], entry, span=(start, end), score=score)
    out[start:end] += grain
    return True


# ─────────────────────────────────────────────────────────────────────────────
# Final level matching (v1.11.3)
# ─────────────────────────────────────────────────────────────────────────────
#
# Measurement: ITU-R BS.1770-4 integrated loudness -- K-weighting (high-shelf
# +4 dB @ 1.5 kHz, Q 0.707; high-pass 38 Hz, Q 0.5; biquads by bilinear
# transform at the actual sample rate, as in pyloudnorm), 400 ms blocks with
# 75 % overlap, absolute gate -70 LUFS, relative gate -10 LU.
# Deviations, stated rather than hidden:
#   * channels are AVERAGED, not summed (Praat plays a mono result on both
#     speakers, so a mono output and a dual-mono target must compare equal;
#     BS.1770 summation would add 3.01 dB to the stereo one).  Values are
#     therefore reported as "LKFS (channel mean)", not as LUFS compliance;
#   * a signal shorter than one 400 ms block is measured as one block;
#   * when every block falls below the -70 LUFS absolute gate (a nearly silent
#     signal), the ungated K-weighted mean is used and flagged "ungated".
# Validated in the tests: 997 Hz full-scale-peak sine = -3.01 LKFS at 44.1 and
# 48 kHz; agreement with pyloudnorm (if installed) on mono test signals.

LOUDNESS_METHOD = "BS.1770-4 K-weighted, gated (400 ms / 75 %, -70 LUFS abs, -10 LU rel), channel mean"
LEVEL_MODES = ("attenuate", "bidirectional", "off")
MAX_BOOST_DB = 12.0          # bidirectional mode: never raise by more than 12 dB
SILENT_LKFS = -90.0          # below this (ungated) a signal is treated as silent


@functools.lru_cache(maxsize=8)
def _k_weighting_sos(sr):
    import numpy as np

    def biquad(kind, G, Q, fc):
        A = 10.0 ** (G / 40.0)
        w0 = 2.0 * math.pi * fc / sr
        alpha = math.sin(w0) / (2.0 * Q)
        c = math.cos(w0)
        if kind == "high_shelf":
            b = [A * ((A + 1) + (A - 1) * c + 2 * math.sqrt(A) * alpha),
                 -2 * A * ((A - 1) + (A + 1) * c),
                 A * ((A + 1) + (A - 1) * c - 2 * math.sqrt(A) * alpha)]
            a = [(A + 1) - (A - 1) * c + 2 * math.sqrt(A) * alpha,
                 2 * ((A - 1) - (A + 1) * c),
                 (A + 1) - (A - 1) * c - 2 * math.sqrt(A) * alpha]
        else:   # high_pass
            b = [(1 + c) / 2.0, -(1 + c), (1 + c) / 2.0]
            a = [1 + alpha, -2 * c, 1 - alpha]
        return [v / a[0] for v in b] + [1.0] + [v / a[0] for v in a[1:]]

    return np.array([biquad("high_shelf", 4.0, 1.0 / math.sqrt(2.0), 1500.0),
                     biquad("high_pass", 0.0, 0.5, 38.0)])


def measure_loudness(audio, sr):
    """Integrated loudness of a mono or multichannel signal.
    Returns dict(lkfs, gated, blocks_used, blocks_total, method).
    lkfs is None for digital silence."""
    import numpy as np
    from scipy.signal import sosfilt
    x = np.asarray(audio, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    out = {"lkfs": None, "gated": True, "blocks_used": 0, "blocks_total": 0,
           "method": LOUDNESS_METHOD}
    if x.shape[0] == 0 or not np.any(x):
        out["gated"] = False
        return out
    y = sosfilt(_k_weighting_sos(int(sr)), x, axis=0)
    p = np.mean(y * y, axis=1)                         # channel mean
    n = p.size
    blk = int(round(0.400 * sr))
    hop = int(round(0.100 * sr))
    if n <= blk:
        z = np.array([float(np.mean(p))])
    else:
        cs = np.concatenate([[0.0], np.cumsum(p)])
        starts = np.arange(0, n - blk + 1, hop)
        z = (cs[starts + blk] - cs[starts]) / blk
    out["blocks_total"] = int(z.size)

    def lk(v):
        return -0.691 + 10.0 * math.log10(max(float(v), 1e-300))

    l_blocks = np.array([lk(v) for v in z])
    keep = l_blocks > -70.0
    if not keep.any():
        val = lk(np.mean(p))
        out.update(lkfs=val if val > SILENT_LKFS else None, gated=False)
        return out
    rel = lk(np.mean(z[keep])) - 10.0
    keep2 = keep & (l_blocks > rel)
    out.update(lkfs=lk(np.mean(z[keep2])), blocks_used=int(keep2.sum()))
    return out


def _peak(a):
    import numpy as np
    a = np.asarray(a)
    return float(np.max(np.abs(a))) if a.size else 0.0


def final_level_match(preview, stems, target_audio, sr, mode, ceiling):
    """Single scalar gain, computed from the COMPLETE preview mix (what Praat
    plays), applied identically to the preview and to every stem.

    mode 'attenuate'     : gain_db = min(0, target - rendered)      (default)
         'bidirectional' : gain_db = min(target - rendered, +12 dB)
         'off'           : gain 1 (legacy: renderer already peak-normalised)
    In the two matching modes `ceiling` (= render_gain) is a peak LIMIT: if
    the gain would put the preview peak above it, the gain is reduced to meet
    it exactly and the remaining loudness difference is reported.  There is no
    compressor or limiter.  An output measured as silent is never boosted.
    The natural-duration policy needs no special case: the output is measured
    over its full length, and gating keeps a long decaying tail from pulling
    the integrated value down."""
    import numpy as np
    t = measure_loudness(target_audio, sr)
    r = measure_loudness(preview, sr)
    rep = {"mode": mode, "method": LOUDNESS_METHOD, "ceiling": float(ceiling),
           "target_lkfs": t["lkfs"], "target_gated": t["gated"],
           "rendered_lkfs": r["lkfs"], "rendered_gated": r["gated"],
           "peak_before": _peak(preview), "requested_db": None, "applied_db": 0.0,
           "ceiling_limited": False, "note": ""}
    g_db = 0.0
    if mode != "off":
        if r["lkfs"] is None:
            rep["note"] = "rendered output is silent: no gain applied"
        elif t["lkfs"] is None:
            rep["note"] = "target is silent: output silenced"
            g_db = None
        else:
            req = t["lkfs"] - r["lkfs"]
            rep["requested_db"] = req
            g_db = min(0.0, req) if mode == "attenuate" else min(req, MAX_BOOST_DB)
            if mode == "bidirectional" and req > MAX_BOOST_DB:
                rep["note"] = "boost limited to +%.0f dB" % MAX_BOOST_DB
        if g_db is not None and rep["peak_before"] > 0:
            pk = rep["peak_before"] * 10.0 ** (g_db / 20.0)
            if pk > ceiling:
                g_db = 20.0 * math.log10(ceiling / rep["peak_before"])
                rep["ceiling_limited"] = True
    base = np.asarray(preview, dtype=np.float64)
    # Gating is level-dependent near the -70 LUFS absolute gate, so the
    # integrated value of a scaled signal is not exactly linear in the gain.
    # Refine the single scalar by re-measuring (fixed point, <= 4 steps),
    # never leaving the mode's limits or the peak ceiling.
    if mode != "off" and g_db is not None and rep["requested_db"] is not None:
        upper = 0.0 if mode == "attenuate" else MAX_BOOST_DB
        if rep["peak_before"] > 0:
            upper = min(upper, 20.0 * math.log10(ceiling / rep["peak_before"]))
        for _ in range(4):
            f = measure_loudness(base * 10.0 ** (g_db / 20.0), sr)["lkfs"]
            if f is None:
                break
            err = t["lkfs"] - f
            if abs(err) < 0.01 or (err > 0 and g_db >= upper - 1e-9):
                break
            g_db = min(g_db + err, upper)
    if g_db is None:
        g = 0.0
        rep["applied_db"] = None
    else:
        g = 10.0 ** (g_db / 20.0)
        rep["applied_db"] = g_db
    pv = (base * g).astype(np.float32)
    st = [(np.asarray(s, dtype=np.float64) * g).astype(np.float32) for s in stems]
    f = measure_loudness(pv, sr)
    rep["final_lkfs"] = f["lkfs"]
    rep["peak_after"] = _peak(pv)
    rep["gain_linear"] = g
    rep["remaining_db"] = (t["lkfs"] - f["lkfs"]) if (t["lkfs"] is not None and f["lkfs"] is not None) else None
    return pv, st, rep


# ─────────────────────────────────────────────────────────────────────────────
# Reporting
# ─────────────────────────────────────────────────────────────────────────────

SILENCE_REASONS = {
    "silent_target": "target RMS is effectively zero",
    "no_legal_candidates": "no corpus entry satisfies the family/instrument/MIDI/descriptor constraints",
    "no_valid_descriptors": "no descriptor could be compared for this target (all excluded, undefined or unvoiced)",
    "score_threshold": "best calibrated score exceeds match_threshold",
    "frame_unmatched": "no frame produced an acceptable match",
    "render_failed": "selected samples could not be loaded",
}


def _status_line(statuses, eff):
    parts = []
    for n in DB_NAMES:
        if n in statuses:
            st = statuses[n]
            tag = st.category + ("!" if st.unverified_override else "")
            parts.append("%s:%s%s" % (n, tag, "" if (st.usable and n in eff) else "-off"))
    return ",".join(parts)


def _common_header(f, ctx):
    f.write("version=%s\n" % VERSION)
    f.write("score_scale=calibrated\n")
    f.write("descriptor_status=%s\n" % ctx["status_line"])
    f.write("effective_weights=%s\n" % ",".join("%s:%.3f" % (k, v) for k, v in ctx["eff"].items()))
    f.write("match_threshold=%.4f\n" % ctx["threshold"])
    f.write("duration_policy=%s\n" % ctx["duration_policy"])
    f.write("legal_candidates=%d\n" % ctx["n_domain"])
    f.write("target_dur=%.4f\n" % ctx["target_dur"])
    f.write("output_dur=%.4f\n" % ctx["output_dur"])
    lv = ctx.get("level") or {}
    f.write("channel_sum_check=%s\n" % ("" if lv.get("channel_sum_vs_reference_max_abs") is None
                                         else "%.3g" % lv["channel_sum_vs_reference_max_abs"]))

    def num(v):
        return "" if v is None else "%.2f" % v
    f.write("level_mode=%s\n" % lv.get("mode", ""))
    f.write("level_method=%s\n" % lv.get("method", ""))
    f.write("target_lkfs=%s\n" % num(lv.get("target_lkfs")))
    f.write("rendered_lkfs=%s\n" % num(lv.get("rendered_lkfs")))
    f.write("requested_db=%s\n" % num(lv.get("requested_db")))
    f.write("applied_db=%s\n" % num(lv.get("applied_db")))
    f.write("final_lkfs=%s\n" % num(lv.get("final_lkfs")))
    f.write("remaining_db=%s\n" % num(lv.get("remaining_db")))
    f.write("peak_before=%s\n" % ("" if "peak_before" not in lv else "%.4f" % lv["peak_before"]))
    f.write("peak_after=%s\n" % ("" if "peak_after" not in lv else "%.4f" % lv["peak_after"]))
    f.write("ceiling_limited=%d\n" % (1 if lv.get("ceiling_limited") else 0))
    cmap = ctx.get("channels") or []
    f.write("out_channels=%d\n" % len(cmap))
    f.write("channel_map=%s\n" % " | ".join("%d %s" % (m["channel"], m["instrument"]) for m in cmap))
    for m in cmap:
        f.write("channel_%d=%s | %s | %s | MIDI %s | %d %s\n" % (
            m["channel"], m["instrument"], m["family"], ", ".join(m["files"][:6]) +
            (" ..." if len(m["files"]) > 6 else ""),
            ",".join(str(v) for v in m["midis"]), m["rendered_units"], m["unit"]))
    # v1.11.6 orchestration protocol: what was RENDERED (Praat draws only this)
    f.write("instruments_requested=%s\n" % ctx.get("n_requested", ""))
    f.write("instruments_rendered=%d\n" % len(cmap))
    f.write("instruments_note=%s\n" % (ctx.get("instr_note") or "").replace("\n", " "))
    f.write("voice_frames=%s\n" % ",".join(str(v) for v in ctx.get("voice_frames", [])))

    def clean(t):
        return str(t).replace("\n", " ").replace("|", "/").replace(";", ",")
    for m in cmap:
        c = m["channel"]
        f.write("chan%d_name=%s\n" % (c, clean(m["instrument"])))
        f.write("chan%d_family=%s\n" % (c, clean(m["family"])))
        f.write("chan%d_notes=%s\n" % (c, " ".join(m.get("notes") or [])))
        f.write("chan%d_dyn=%s\n" % (c, " ".join(m.get("dynamics") or [])))
        f.write("chan%d_score=%s\n" % (c, "" if m.get("score_mean") is None else "%.3f" % m["score_mean"]))
        f.write("chan%d_samples=%d\n" % (c, len(m["files"])))
        f.write("chan%d_files=%s\n" % (c, ", ".join(clean(x) for x in m["files"])))
        f.write("chan%d_units=%d %s\n" % (c, m["rendered_units"], m["unit"]))
        f.write("chan%d_active_s=%s\n" % (c, m.get("active_s", "")))
        f.write("chan%d_activity=%s\n" % (c, ";".join("%.3f-%.3f" % ab for ab in m.get("activity") or [])))
        spans = m.get("note_spans") or []
        if len(spans) > NOTE_SPAN_MAX:
            spans = []                       # too fragmented to label: omit, do not truncate silently
        f.write("chan%d_notespans=%s\n" % (c, ";".join("%.3f-%.3f:%s" % (a, b, n) for a, b, _m, n in spans)))
    f.write("pitch_interpretation=%s\n" % ctx.get("interpretation", ""))
    f.write("interpretation_label=%s\n" % ctx.get("interpretation_label", ""))
    f.write("interpretation_class=%s\n" % ctx.get("interpretation_class", ""))
    f.write("n_events=%s\n" % ctx.get("n_events", ""))
    f.write("pitch_changes=%s\n" % ctx.get("pitch_changes", ""))
    f.write("sample_changes=%s\n" % ctx.get("sample_changes", ""))
    for w in ctx.get("warnings", []):
        f.write("warning=%s\n" % w.replace("\n", " "))


def write_results(out_path, scored, params, target_sr, target_len,
                  render_mode, chosen_count, render_silence=False,
                  silence_reason="", envelope_stats=None, ctx=None):
    n_results = min(params["_n_results"], len(scored))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("=== TinySOL Retrieval Results ===\n")
        f.write("render_mode=%s\n" % render_mode)
        f.write("chosen_count=%d\n" % chosen_count)
        f.write("rendered_count=%d\n" % chosen_count)
        f.write("target_sr=%d\n" % target_sr)
        f.write("target_len=%.3f\n" % (target_len / max(1, target_sr)))
        f.write("n_candidates=%d\n" % len(scored))
        f.write("n_results=%d\n" % n_results)
        f.write("silence_rendered=%d\n" % (1 if render_silence else 0))
        f.write("silence_reason=%s\n" % (silence_reason if render_silence else ""))
        if envelope_stats is not None:
            f.write("envelope_follow=%.3f\n" % envelope_stats.get("envelope_follow", 0.0))
            f.write("envelope_corr_before=%.4f\n" % envelope_stats.get("envelope_corr_before", 0.0))
            f.write("envelope_corr_after=%.4f\n" % envelope_stats.get("envelope_corr_after", 0.0))
        if ctx is not None:
            _common_header(f, ctx)
        f.write("\n")
        f.write("rank,score,family,instrument,note,midi,dynamic,variant,technique,abs_path\n")
        for rank, (score, e, _d) in enumerate(scored[:n_results], 1):
            f.write("%d,%.6f,%s,%s,%s,%d,%s,%s,%s,%s\n" % (
                rank, score, e.family, e.inst, e.note, e.midi, e.dyn, e.variant, e.tech, e.abs_path))
        f.write("\n=== Descriptor Weights (requested) ===\n")
        for name, w in params["_descriptor_weights"].items():
            f.write("weight_%s=%.3f\n" % (name, w))
        if render_silence:
            f.write("\n=== NOTE ===\nOutput is silence: %s.\n"
                    % SILENCE_REASONS.get(silence_reason, silence_reason))


def write_frame_results(out_path, frame_matches, params, target_sr, target_len,
                        envelope_stats=None, ctx=None, reasons=None, rendered_frames=None):
    from collections import Counter
    import numpy as np
    n_frames = len(frame_matches)
    n_matched = sum(1 for fm in frame_matches if fm["match"] is not None)
    if rendered_frames is None:
        rendered_frames = n_matched
    usage, ssum, entry_of = Counter(), Counter(), {}
    for fm in frame_matches:
        if fm["match"] is None:
            continue
        # v1.11.5: every instrument voice counts (voice 1 only without layers)
        for lm in [l["match"] for l in fm.get("layers") or []] or [fm["match"]]:
            sc, e, _ = lm
            key = (e.family, e.inst, e.note, e.dyn)
            usage[key] += 1
            ssum[key] += float(sc)
            entry_of[key] = e
    mean_sc = {k: ssum[k] / max(1, usage[k]) for k in usage}
    n_results = min(params["_n_results"], len(usage))
    ranked = [k for k, _ in usage.most_common(n_results)]
    if n_matched == 0 and reasons and reasons.get("no_valid_descriptors", 0) > 0 and \
            reasons.get("no_valid_descriptors", 0) >= max(v for k, v in reasons.items()
                                                       if k not in ("silent", "pitch_gate_suppressed")):
        reason = "no_valid_descriptors"
    elif n_matched == 0:
        reason = "frame_unmatched"
    elif rendered_frames == 0:
        reason = "render_failed"
    else:
        reason = ""
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("=== TinySOL Retrieval Results ===\n")
        f.write("render_mode=frame_based\n")
        f.write("chosen_count=%d\n" % n_matched)
        f.write("rendered_count=%d\n" % rendered_frames)
        if envelope_stats is not None:
            f.write("envelope_follow=%.3f\n" % envelope_stats.get("envelope_follow", 0.0))
            f.write("envelope_corr_before=%.4f\n" % envelope_stats.get("envelope_corr_before", 0.0))
            f.write("envelope_corr_after=%.4f\n" % envelope_stats.get("envelope_corr_after", 0.0))
        f.write("target_sr=%d\n" % target_sr)
        f.write("target_len=%.3f\n" % (target_len / max(1, target_sr)))
        f.write("n_candidates=%d\n" % n_frames)
        f.write("n_results=%d\n" % n_results)
        f.write("silence_rendered=%d\n" % (1 if reason else 0))
        f.write("silence_reason=%s\n" % reason)
        if ctx is not None:
            _common_header(f, ctx)
        f.write("\n")
        f.write("rank,score,family,instrument,note,midi,dynamic,variant,technique,abs_path\n")
        for rank, key in enumerate(ranked, 1):
            e = entry_of[key]
            f.write("%d,%.6f,%s,%s,%s,%d,%s,%s,%s,%s\n" % (
                rank, mean_sc[key], e.family, e.inst, e.note, e.midi, e.dyn, e.variant, e.tech, e.abs_path))
        f.write("\n")
        for rank in range(1, 5):
            cnt = int(usage[ranked[rank - 1]]) if rank <= len(ranked) else 0
            f.write("rank%d_usage_count=%d\n" % (rank, cnt))
            f.write("rank%d_usage_pct=%.1f\n" % (rank, 100.0 * cnt / max(1, n_matched)))
        f.write("\n=== Frame Stats ===\n")
        f.write("total_frames=%d\n" % n_frames)
        f.write("matched_frames=%d\n" % n_matched)
        f.write("rendered_frames=%d\n" % rendered_frames)
        f.write("silent_frames=%d\n" % sum(1 for fm in frame_matches if fm["frame"].get("silent")))
        for k, v in sorted((reasons or {}).items()):
            f.write("frames_%s=%d\n" % (k, v))
        ms = [float(fm["match"][0]) for fm in frame_matches if fm["match"] is not None]
        f.write("mean_match_score=%.6f\n" % (float(np.mean(ms)) if ms else 0.0))
        f.write("frame_size_ms=%.1f\n" % params["_frame_size_ms"])
        f.write("hop_size_ms=%.1f\n" % params["_hop_size_ms"])
        f.write("pitch_tolerance=%d\n" % params["_pitch_tolerance"])
        f.write("\n=== Descriptor Weights (requested) ===\n")
        for name, w in params["_descriptor_weights"].items():
            f.write("weight_%s=%.3f\n" % (name, w))


def _json_safe(o):
    import numpy as np
    if isinstance(o, dict):
        return {str(k): _json_safe(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [_json_safe(v) for v in o]
    if isinstance(o, (np.floating, float)):
        v = float(o)
        return v if math.isfinite(v) else None
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, np.ndarray):
        return _json_safe(o.tolist())
    return o


def write_json_report(path, report):
    if not path:
        return
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(_json_safe(report), f, indent=2, sort_keys=False)
    print("  [REPORT] %s" % path)


def _entry_dict(e):
    return {"family": e.family, "instrument": e.inst, "note": e.note, "midi": e.midi,
            "dynamic": e.dyn, "variant": e.variant, "technique": e.tech, "path": e.abs_path}


# ─────────────────────────────────────────────────────────────────────────────
# Main pipeline
# ─────────────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--build-db":
        sys.exit(cli_build_db(sys.argv[2:]))
    if len(sys.argv) >= 2 and sys.argv[1] == "--verify-db":
        sys.exit(cli_verify_db(sys.argv[2:]))
    if len(sys.argv) < 5:
        print("Usage: python tinysol_retrieval.py target.wav params.txt output.wav results.txt [done.txt]\n"
              "       python tinysol_retrieval.py --build-db <corpus_root> <new_output_dir>\n"
              "       python tinysol_retrieval.py --verify-db <db_dir> <corpus_root>", file=sys.stderr)
        sys.exit(1)
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(errors="replace")
        except Exception:
            pass
    check_dependencies()
    import io
    import traceback
    target_wav, params_file, out_wav, results_txt = sys.argv[1:5]
    done_file = sys.argv[5] if len(sys.argv) > 5 else None

    class _TeeErr:
        def __init__(self, primary, capture):
            self.primary, self.capture = primary, capture

        def write(self, text):
            try:
                self.primary.write(text)
            except Exception:
                pass
            self.capture.write(text)
            return len(text)

        def flush(self):
            try:
                self.primary.flush()
            except Exception:
                pass

    cap = io.StringIO()
    orig = sys.stderr
    sys.stderr = _TeeErr(orig, cap)
    try:
        run_pipeline(target_wav, params_file, out_wav, results_txt)
        if done_file:
            with open(done_file, "w", encoding="utf-8") as f:
                f.write("OK\n")
    except SystemExit:
        if done_file:
            with open(done_file, "w", encoding="utf-8") as f:
                f.write("ERROR: Python exited with error.\n")
                detail = cap.getvalue().strip()
                if detail:
                    f.write(detail + "\n")
        raise
    except Exception as exc:
        tb = traceback.format_exc()
        if done_file:
            with open(done_file, "w", encoding="utf-8") as f:
                f.write("ERROR: %s\n%s" % (str(exc), tb))
        print("ERROR: %s" % exc, file=orig)
        sys.exit(1)
    finally:
        sys.stderr = orig


def _fail(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


BUILD_HINT = ("To build AudioTools-verified descriptor files from your own TinySOL WAVs "
              "(originals are never modified):\n"
              "  python tinysol_retrieval.py --build-db \"<corpus_root>\" \"<NEW empty folder>\"\n"
              "then set DB_directory to that new folder.")


def run_pipeline(target_wav, params_file, out_wav, results_txt):
    import numpy as np
    import soundfile as sf

    print("[1/8] Parsing parameters (backend v%s) ..." % VERSION)
    params = parse_params(params_file)
    for w in params["_warnings"]:
        print("  [PARAMS] WARNING: " + w)
    db_dir, corpus_root = params["db_dir"], params["corpus_root"]
    mode = params["_analysis_mode"]
    if not db_dir or not os.path.isdir(db_dir):
        _fail("db_dir not found: %s" % db_dir)
    if not corpus_root or not os.path.isdir(corpus_root):
        _fail("corpus_root not found: %s" % corpus_root)
    if mode == "frame_based":
        n44 = int(round(params["_frame_size_ms"] * DESCRIPTOR_SAMPLE_RATE / 1000.0))
        if n44 < CONTRACT_N_FFT:
            _fail("frame_size_ms=%.1f is shorter than one descriptor-contract window "
                  "(4096 samples = %.1f ms at 44.1 kHz); frame descriptors would not be "
                  "comparable with the database. Use frame size >= 93 ms."
                  % (params["_frame_size_ms"], 1000.0 * CONTRACT_N_FFT / DESCRIPTOR_SAMPLE_RATE))

    report = {"version": VERSION, "target": target_wav,
              "params": {k: v for k, v in params.items() if not k.startswith("_")},
              "warnings": list(params["_warnings"]), "contract": CONTRACT_TEXT}

    print("[2/8] Loading active .db descriptor files ...")
    active = _active_db_descriptors(params)
    db_store = DbStore()
    for name in active:
        db_store.load(db_dir, name)

    print("[3/8] Scanning corpus and verifying descriptor contracts ...")
    entries = build_index(corpus_root, db_store, params)
    if not entries:
        _fail("No corpus entries found under %s" % corpus_root)
    statuses = resolve_descriptor_profile(db_store, entries, params, active)
    usable = [n for n in active if statuses[n].usable]
    excluded = [n for n in active if not statuses[n].usable]
    report["descriptors"] = {n: statuses[n].to_dict() for n in active}
    if excluded:
        msg = ("descriptor(s) %s excluded: database contents could not be shown to match "
               "any known extraction contract." % ", ".join(excluded))
        print("  WARNING: " + msg)
        params["_warnings"].append(msg)
    hw = float(params["_descriptor_weights"].get("harmonic", 0.0))
    if not usable and (hw <= 0 or params["_speech_mode"]):
        _fail("No verified descriptor remains to score with.\n" +
              "\n".join("  %s: %s" % (n, statuses[n].reason) for n in active) + "\n" + BUILD_HINT)

    cal = Calibration(db_store, {n: statuses[n] for n in usable}, entries)
    report["calibration"] = cal.to_dict()
    for n, sp in cal.spaces.items():
        print("  [CAL] %-10s scale=%.5g  (%s, %d pairs)" % (n, sp.scale, sp.null["status"], sp.null["n_pairs"]))
    print("  [CAL] harmonic   scale=%.5g" % cal.harmonic["scale"])

    domain, rej = build_candidate_domain(entries, params, usable)
    report["domain"] = {"legal_candidates": len(domain), "rejected": rej}
    weights = {k: v for k, v in params["_descriptor_weights"].items()
               if k == "harmonic" or k in usable}
    scorer = Scorer(domain, cal, weights, params["_preferred_dynamics"], params["_speech_mode"])
    extractors = {n: statuses[n].extractor for n in usable}
    thresh = params["_match_threshold"]

    ctx = {"status_line": "", "eff": {}, "threshold": thresh,
           "duration_policy": params["_duration_policy"], "n_domain": len(domain),
           "target_dur": 0.0, "output_dur": 0.0, "warnings": params["_warnings"],
           "n_requested": RENDER_LAYERS.get(params["render_mode"], 1), "instr_note": ""}

    if mode == "frame_based":
        _run_frames(target_wav, out_wav, results_txt, params, scorer, extractors,
                    statuses, domain, ctx, report)
    else:
        _run_whole(target_wav, out_wav, results_txt, params, scorer, extractors,
                   statuses, domain, ctx, report)
    write_json_report(params["_report_path"], report)
    print("OK: done.")


def _run_whole(target_wav, out_wav, results_txt, params, scorer, extractors,
               statuses, domain, ctx, report):
    import numpy as np
    import soundfile as sf
    print("[4/8] Analysing target WAV ...")
    tdesc, tsr, tlen, pinfo = analyse_target(target_wav, extractors)
    ctx["target_dur"] = tlen / float(tsr)
    partials = None
    if pinfo["partials_hz"] and pinfo["partials_amp"]:
        partials = list(zip(pinfo["partials_hz"], pinfo["partials_amp"]))
    # v1.11.1: the file-level F0 may drive harmonic scoring and the legacy
    # pitch penalty only when the pitch evidence says the target is a reliable
    # monophonic source (energy-weighted over its events).
    interp = "spectral" if params["_speech_mode"] else params["_pitch_interpretation"]
    pframes, _, _, _, _ = analyse_frames(target_wav, 150.0, 75.0)
    pevents = build_events(pframes, 0.075, interp, 0.150)
    file_class, label = interpretation_summary(pevents, pframes)
    harm_reason = None
    if interp == "spectral":
        harm_reason = "pitch interpretation: spectral"
    elif file_class != "monophonic":
        harm_reason = "pitch unreliable (%s)" % file_class
    elif interp == "monophonic" and not any(f["pitch"]["f0_est"] for f in pframes):
        harm_reason = "monophonic requested but no valid pitch measured"
    if harm_reason:
        partials = None
        pinfo["midi_used"] = None
        if domain and pinfo["target_rms"] > 1e-8:
            _require_timbre(scorer, statuses, "This sound (%s)" % harm_reason)
    else:
        pinfo["midi_used"] = pinfo["midi"]
    ctx["interpretation"] = interp
    ctx["interpretation_label"] = label
    ctx["interpretation_class"] = file_class
    ctx["n_events"] = len(pevents)
    ctx["pitch_changes"] = 0
    ctx["sample_changes"] = 0
    report["pitch_interpretation"] = interp
    report["interpretation_label"] = label
    report["events"] = pevents
    if pinfo["f0_hz"] is not None and not harm_reason:
        print("  Detected F0: %.1f Hz (MIDI %d)  voiced %d/%d" % (
            pinfo["f0_hz"], pinfo["midi"], pinfo["n_voiced"], pinfo["n_frames"]))
    elif harm_reason:
        print("  Pitch not used: %s  [%s]" % (harm_reason, label))
    else:
        print("  No pitched content detected; harmonic term not used for this target.")
    report["target_analysis"] = {"f0_hz": pinfo["f0_hz"], "midi": pinfo["midi"],
                                 "n_voiced": pinfo["n_voiced"], "n_frames": pinfo["n_frames"],
                                 "rms": pinfo["target_rms"], "channel": pinfo["analysis_channel"],
                                 "descriptors": {k: v for k, v in tdesc.items()}}

    print("[5/8] Retrieving and ranking ...")
    scored, info = ([], {"used": [], "skipped": {}, "effective_weights": {}})
    silence_reason = ""
    if pinfo["target_rms"] <= 1e-8:
        silence_reason = "silent_target"
    elif not domain:
        silence_reason = "no_legal_candidates"
    else:
        scored, info = retrieve(scorer, tdesc, pinfo["midi_used"], partials,
                                harmonic_reason=harm_reason)
        n_layers = RENDER_LAYERS.get(params["render_mode"], 1)
        distinct = distinct_instruments(scored)
        rank_of = {id(item): r for r, item in enumerate(scored, 1)}
        ctx["selection_pool"] = (distinct, [rank_of[id(it)] for it in distinct])
        print("  Instrument selection: %d requested, %d distinct instruments among %d ranked entries"
              % (n_layers, len(distinct), len(scored)))
        if len(distinct) < n_layers:
            ctx["instr_note"] = ("%d instrument(s) requested, only %d distinct instrument(s) satisfy "
                                 "the family/instrument/MIDI/dynamics constraints"
                                 % (n_layers, len(distinct)))
            print("  [WARN] " + ctx["instr_note"])
        if not info["used"]:
            silence_reason = "no_valid_descriptors"
        elif thresh_gate(params["_match_threshold"], scored[0][0] if scored else None):
            silence_reason = "score_threshold"
    eff = info.get("effective_weights", {})
    ctx["eff"] = eff
    ctx["status_line"] = _status_line(statuses, eff)
    for rank, (sc, e, d) in enumerate(scored[:5], 1):
        print("    #%d  score=%.4f  %s %s %s %s  %s" % (
            rank, sc, e.family, e.inst, e.note, e.dyn,
            " ".join("%s=%.3f" % (k, v) for k, v in d["cal"].items())))
    if info.get("skipped"):
        print("  Not used: %s" % ", ".join("%s (%s)" % kv for kv in info["skipped"].items()))

    rmode = params["render_mode"]
    print("[6/8] Rendering (%s, duration=%s) ..." % (rmode, params["_duration_policy"]))
    env_stats = {"envelope_follow": params["_envelope_follow"],
                 "envelope_corr_before": 0.0, "envelope_corr_after": 0.0}
    rinfo = {"selected": 0, "rendered_ranks": [], "failed": [], "truncated_layers": 0}
    if silence_reason:
        print("  Output is silence: %s" % SILENCE_REASONS[silence_reason])
        out = np.zeros(tlen, dtype=np.float32)
    else:
        pool, pool_ranks = ctx["selection_pool"]
        out, rinfo = blend_samples(pool, tlen, tsr, rmode, params["_render_gain"],
                                   duration_policy=params["_duration_policy"], return_info=True,
                                   normalize=params["_level_matching"] == "off", ranks=pool_ranks)
        if not rinfo["rendered_ranks"]:
            silence_reason = "render_failed"
        else:
            tgt, _ = load_audio(target_wav, target_sr=tsr)
            out, env_stats = apply_target_macro_envelope(out, tgt, tsr, params["_envelope_follow"])
            print("  Rendered layers: %s  envelope corr %.3f -> %.3f" % (
                rinfo["rendered_ranks"], env_stats["envelope_corr_before"], env_stats["envelope_corr_after"]))
    channels = finish_output(out, rinfo if not silence_reason else None, env_stats, target_wav, tsr,
                             params, ctx, report)
    print("[7/8] Writing multichannel output WAV ...")
    ctx["output_dur"] = write_output(out_wav, channels, tsr)
    print("[8/8] Writing results file ...")
    n_rendered = len(rinfo["rendered_ranks"])
    write_results(results_txt, scored, params, tsr, tlen, rmode, n_rendered,
                  render_silence=bool(silence_reason), silence_reason=silence_reason,
                  envelope_stats=env_stats, ctx=ctx)
    report.update({
        "mode": "whole_file",
        "descriptors_used": info.get("used", []), "descriptors_skipped": info.get("skipped", {}),
        "effective_weights": eff,
        "results": [dict(_entry_dict(e), rank=i + 1, score=sc, raw=d["raw"], calibrated=d["cal"],
                         penalty=d["penalty"])
                    for i, (sc, e, d) in enumerate(scored[:params["_n_results"]])],
        "silence": {"rendered": bool(silence_reason), "reason": silence_reason,
                    "explanation": SILENCE_REASONS.get(silence_reason, ""),
                    "threshold": params["_match_threshold"],
                    "best_score": scored[0][0] if scored else None},
        "render": dict({k: v for k, v in rinfo.items() if k != "stems"}, rendered_count=n_rendered),
        "output_channels": 0 if channels is None else int(channels.shape[1]),
        "durations": {"target_s": ctx["target_dur"], "output_s": ctx["output_dur"]},
        "envelope": env_stats,
    })
    if scored:
        print("best_match=%s %s %s %s score=%.6f %s" % (
            scored[0][1].family, scored[0][1].inst, scored[0][1].note, scored[0][1].dyn,
            scored[0][0], ("SILENCE (%s)" % silence_reason) if silence_reason else ""))


def thresh_gate(threshold, best_score):
    """True if the gate rejects.  threshold <= 0 means gate off."""
    return threshold > 0 and best_score is not None and best_score > threshold


ACTIVITY_BLOCK_S = 0.020      # activity analysis resolution (20 ms blocks)
ACTIVITY_FLOOR_DB = 45.0      # active = block RMS within 45 dB of the loudest block
ACTIVITY_MIN_GAP_S = 0.060    # shorter gaps are closed (OLA/grain ripple)
ACTIVITY_MIN_RUN_S = 0.040    # shorter islands are dropped
NOTE_SPAN_MAX = 48            # note segments reported per channel


def channel_activity(channels, sr):
    """Measured participation of every output channel (v1.11.6), from the
    FINAL channel audio: 20 ms block RMS, active when within
    ACTIVITY_FLOOR_DB of the loudest block of the whole output (a common
    reference, so a quiet instrument is not inflated), gaps < 60 ms closed,
    islands < 40 ms removed.  Returns one [(t0, t1), ...] list per channel."""
    import numpy as np
    x = np.asarray(channels, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    b = max(1, int(round(ACTIVITY_BLOCK_S * sr)))
    nb = int(math.ceil(x.shape[0] / float(b)))
    pad = np.zeros((nb * b, x.shape[1]))
    pad[:x.shape[0]] = x
    rms = np.sqrt(np.mean(pad.reshape(nb, b, x.shape[1]) ** 2, axis=1))
    ref = float(rms.max()) if rms.size else 0.0
    out = []
    for c in range(x.shape[1]):
        if ref <= 0:
            out.append([])
            continue
        act = rms[:, c] >= ref * 10.0 ** (-ACTIVITY_FLOOR_DB / 20.0)
        runs, i = [], 0
        while i < nb:
            if act[i]:
                j = i
                while j < nb and act[j]:
                    j += 1
                runs.append([i, j])
                i = j
            else:
                i += 1
        gap = int(round(ACTIVITY_MIN_GAP_S / ACTIVITY_BLOCK_S))
        merged = []
        for r in runs:
            if merged and r[0] - merged[-1][1] < gap:
                merged[-1][1] = r[1]
            else:
                merged.append(r)
        mrun = int(round(ACTIVITY_MIN_RUN_S / ACTIVITY_BLOCK_S))
        dur = x.shape[0] / float(sr)
        out.append([(round(r[0] * b / float(sr), 3), round(min(dur, r[1] * b / float(sr)), 3))
                    for r in merged if r[1] - r[0] >= mrun])
    return out


def _note_spans(stem, sr, target_len):
    """Merge per-grain/per-layer spans into segments of constant sample note."""
    segs = []
    for a, b, midi, note in sorted(stem.get("spans", [])):
        b = min(b, target_len)
        if b <= a:
            continue
        if segs and segs[-1][2] == midi and a <= segs[-1][1]:
            segs[-1][1] = max(segs[-1][1], b)
        else:
            if segs and a < segs[-1][1]:
                # overlapping grains of different notes: split at the midpoint
                mid = (a + segs[-1][1]) // 2
                segs[-1][1], a = mid, mid
            segs.append([a, b, midi, note])
    return [(round(a / float(sr), 3), round(b / float(sr), 3), m, n) for a, b, m, n in segs]


def channel_map(stems, sr=None, target_len=None, activity=None):
    """Deterministic channel -> instrument mapping, built from the RENDERED
    stems only (report, results file and Praat drawing)."""
    out = []
    for i, st in enumerate(stems):
        sc = st.get("scores") or []
        m = {"channel": i + 1, "instrument": st["instrument"], "prefix": st["prefix"],
             "family": st["family"], "files": st["files"], "midis": sorted(st["midis"]),
             "notes": [n for _, n in sorted(zip(st.get("midis", []), st.get("notes", [])))],
             "dynamics": list(st.get("dyns", [])),
             "score_mean": (sum(sc) / len(sc)) if sc else None,
             "rendered_units": st["units"], "unit": "layers" if st["weights"] else "frames",
             "mixing_weights": st["weights"] or None, "ranks": st["ranks"] or None}
        if sr:
            m["note_spans"] = _note_spans(st, sr, target_len or 10 ** 12)
        if activity is not None and i < len(activity):
            m["activity"] = activity[i]
            m["active_s"] = round(sum(b - a for a, b in activity[i]), 3)
        out.append(m)
    return out


def finish_output(mix, rinfo, env_stats, target_wav, tsr, params, ctx, report):
    """Post-render stage shared by both modes (v1.11.4):
       envelope curve (from the combined mix) -> every instrument channel;
       final level matching measured on the internal reference mix
       (= sum of channels), one scalar for every channel.
       Returns the (n_samples, n_channels) float32 array that IS the output,
       or None when no instrument was rendered (nothing is fabricated)."""
    import numpy as np
    import soundfile as sf
    stems = rinfo.get("stems", []) if rinfo else []
    apply_curve_to_stems(stems, env_stats.pop("_curve", None))
    tgt_all, tsr0 = sf.read(target_wav, always_2d=False)
    tgt_all = np.asarray(tgt_all, dtype=np.float64)
    mix, scaled, level = final_level_match(mix, [st["audio"] for st in stems], tgt_all, tsr0,
                                           params["_level_matching"], params["_render_gain"])
    for st, a in zip(stems, scaled):
        st["audio"] = a
    channels = None
    if stems:
        channels = np.stack([np.asarray(st["audio"], dtype=np.float32) for st in stems], axis=1)
        recon = channels.astype(np.float64).sum(axis=1)
        level["channel_sum_vs_reference_max_abs"] = float(np.max(np.abs(recon - mix.astype(np.float64))))
    level["channels"] = len(stems)
    act = channel_activity(channels, tsr) if channels is not None else None
    cmap = channel_map(stems, tsr, len(mix), act)
    ctx["level"] = level
    ctx["channels"] = cmap
    n_req = ctx.get("n_requested") or 0
    if stems and len(cmap) < n_req and not ctx.get("instr_note"):
        fails = (rinfo or {}).get("failed") or (rinfo or {}).get("failed_files") or []
        ctx["instr_note"] = ("%d instrument(s) requested, %d rendered%s" % (
            n_req, len(cmap), "; %d sample file(s) failed to load" % len(fails) if fails
            else "; the other selected instrument(s) produced no audible grain"))
    if ctx.get("instr_note"):
        report["instruments_note"] = ctx["instr_note"]
    report["level_matching"] = level
    report["channels"] = {"count": len(stems), "sample_rate": int(tsr),
                          "shared_master_gain_db": level.get("applied_db"), "mapping": cmap}

    def f(v):
        return "n/a" if v is None else "%.2f" % v
    print("  Level (%s): target %s  rendered %s  requested %s dB  applied %s dB  final %s  "
          "remaining %s dB  peak %.3f -> %.3f%s" % (
              level["mode"], f(level["target_lkfs"]), f(level["rendered_lkfs"]), f(level["requested_db"]),
              f(level["applied_db"]), f(level["final_lkfs"]), f(level["remaining_db"]),
              level["peak_before"], level["peak_after"], "  [peak ceiling]" if level["ceiling_limited"] else ""))
    print("  Output channels: %s" % (", ".join("%d %s" % (m["channel"], m["instrument"]) for m in cmap)
                                     or "none (no instrument rendered)"))
    return channels


def write_output(out_wav, channels, tsr):
    """Write the multichannel result to the (temporary) output path; when no
    instrument was rendered, make sure no output file exists."""
    import soundfile as sf
    if channels is None:
        if os.path.exists(out_wav):
            os.remove(out_wav)
        return 0.0
    sf.write(out_wav, channels, int(tsr), subtype="FLOAT")
    return channels.shape[0] / float(tsr)


def _require_timbre(scorer, statuses, what):
    """Stop with an explicit diagnosis when a pitch-neutral event must be
    matched but no verified timbral descriptor carries weight (the only
    remaining term, harmonic, is correctly disabled for such events)."""
    if scorer.mats:
        return
    lines = []
    for n in ("mfcc", "specenv", "moments", "specpeaks"):
        if n in statuses:
            lines.append("  %s: category %s - %s" % (n, statuses[n].category, statuses[n].reason))
    _fail(("%s can only be matched by timbre (pitch-neutral retrieval), but no verified "
           "timbral descriptor has weight > 0.\n" % what) +
          ("\n".join(lines) + "\n" if lines else
           "  (all timbral descriptor weights are 0)\n") +
          "Nothing was rendered.  v1.11.0 produced sound here only by scoring an unreliable "
          "(often subharmonic) pitch estimate.\n" + BUILD_HINT)


ALLOC_UNCOVERED_COST = 2.0    # calibrated units: twice a typical corpus distance
ALLOC_CRITERION = ("instrument cost = energy-weighted mean over scorable frames of the "
                   "instrument's best legal frame score, a frame without a legal sample "
                   "counting %.1f; the N lowest costs are selected (ties: family, name)"
                   % ALLOC_UNCOVERED_COST)


def allocate_instruments(S, frames, inst_keys, n_req):
    """v1.11.6 global instrument allocation for frame mode.

    For every instrument k with at least one legal sample in a scorable frame:
        b[i,k]  = best (lowest) score of k's samples in frame i (NaN = none)
        c[i,k]  = b[i,k], or ALLOC_UNCOVERED_COST where k has no legal sample
        cost_k  = sum_i w_i c[i,k] / sum_i w_i,   w_i = frame RMS^2
    i.e. timbral fit and temporal coverage in one number, weighted by where the
    target has energy.  The N lowest costs are the fixed ensemble.  Returns
    {"selected": [...], "ranking": [...], "note": str}."""
    import numpy as np
    keys = sorted(set(inst_keys))
    if not S or not keys:
        return {"selected": [], "ranking": [],
                "note": "no scorable frame: no instrument could be allocated" if n_req else ""}
    col = {k: j for j, k in enumerate(keys)}
    cidx = np.array([col[k] for k in inst_keys], dtype=np.int64)
    rows = sorted(S)
    w = np.array([max(frames[i]["rms"], 1e-12) ** 2 for i in rows])
    B = np.full((len(rows), len(keys)), np.nan)
    for r, i in enumerate(rows):
        sc = S[i][0]
        ok = np.isfinite(sc)
        for j in np.unique(cidx[ok]):
            B[r, j] = float(np.min(sc[ok & (cidx == j)]))
    covered = np.isfinite(B)
    C = np.where(covered, B, ALLOC_UNCOVERED_COST)
    cost = (w[:, None] * C).sum(axis=0) / w.sum()
    cov = (w[:, None] * covered).sum(axis=0) / w.sum()
    cand = [j for j in range(len(keys)) if covered[:, j].any()]
    cand.sort(key=lambda j: (round(float(cost[j]), 12), keys[j]))
    ranking = [{"key": keys[j], "cost": float(cost[j]), "coverage": float(cov[j])} for j in cand]
    selected = ranking[:n_req]
    note = ""
    if len(selected) < n_req:
        note = ("%d instrument(s) requested, only %d have a legal sample in any sounding frame "
                "(family/instrument/MIDI/dynamics constraints)" % (n_req, len(selected)))
    return {"selected": selected, "ranking": ranking, "note": note}


def _viterbi_runs(Sv, events, midi_arr):
    """Per-event Viterbi over each run of consecutive frames present in Sv
    (same switch / pitch-switch costs as the single-voice engine)."""
    import numpy as np
    out = {}
    for e in events:
        run = []
        for i in list(range(e["first"], e["last"] + 1)) + [None]:
            if i is not None and i in Sv:
                run.append(i)
                continue
            if run:
                M = np.vstack([Sv[j] for j in run])
                path = _viterbi_select(M, midi_arr, SWITCH_COST[e["class"]],
                                       PITCH_SWITCH_COST[e["class"]])
                for j, c in zip(run, path):
                    out[j] = c
                run = []
    return out


def _run_frames(target_wav, out_wav, results_txt, params, scorer, extractors,
                statuses, domain, ctx, report):
    """Frame-based retrieval, v1.11.1:
       analysis (shared spectrum) -> events -> per-frame scores with a pitch
       gate / harmonic term ONLY where the event is monophonic and the frame's
       pitch is reliable -> event-level Viterbi selection -> OLA render."""
    import numpy as np
    import soundfile as sf
    from collections import Counter
    interp = "spectral" if params["_speech_mode"] else params["_pitch_interpretation"]
    print("[4/8] Analysing target frame by frame (pitch evidence + events, %s) ..." % interp)
    frames, tsr, tlen, fsize, hsize = analyse_frames(
        target_wav, params["_frame_size_ms"], params["_hop_size_ms"], keep_power=True)
    hop_s = params["_hop_size_ms"] / 1000.0
    events = build_events(frames, hop_s, interp, params["_frame_size_ms"] / 1000.0)
    ctx["target_dur"] = tlen / float(tsr)
    raw_audio, _ = load_audio(target_wav)
    for e in events:
        print("  event %d  %.2f s  %d frames  %-10s (%s)  pitch set %s" % (
            e["id"], e["start_s"], e["n_frames"], e["class"], e["reason"], e.get("pitch_set", [])))

    nonmono = [e for e in events if e["class"] != "monophonic"]
    if nonmono and domain:
        _require_timbre(scorer, statuses, "This sound (%s event%s)" % (
            ", ".join(sorted({e["class"] for e in nonmono})), "s" if len(nonmono) > 1 else ""))
    print("[5/8] Scoring frames and selecting per event ...")
    thresh = params["_match_threshold"]
    tol = params["_pitch_tolerance"]
    reasons = Counter()
    eff_union = {}
    S = {}
    diag = [dict() for _ in frames]
    midi_arr = np.array([e.midi for e in domain], dtype=np.int64)
    ev_class = {e["id"]: e["class"] for e in events}
    ev_pset = {e["id"]: e.get("pitch_set", []) for e in events}
    for i, fi in enumerate(frames):
        d = diag[i]
        d["gate"] = False
        d["harmonic"] = False
        if fi.get("silent"):
            reasons["silent"] += 1
            d["status"] = "silent"
            continue
        if not domain:
            reasons["no_legal_candidates"] += 1
            d["status"] = "no_legal_candidates"
            continue
        if fi.get("power") is None:
            reasons["analysis_failed"] += 1
            d["status"] = "analysis_failed"
            continue
        fdesc = descriptors_from_power(fi["power"], extractors)
        cls = ev_class.get(fi["event"], "ambiguous")
        gm, partials, why = frame_pitch_gate(fi, cls, interp, params["_speech_mode"])
        if gm is None and fi["pitch"]["acf_f0"] is not None:
            reasons["pitch_gate_suppressed"] += 1
        d["gate"] = gm is not None
        d["gate_midi"] = gm
        d["harmonic"] = bool(partials) and float(params["_descriptor_weights"].get("harmonic", 0)) > 0
        d["pitch_note"] = why
        pset = ev_pset.get(fi["event"], []) if (gm is None and not params["_speech_mode"]
                                                 and interp != "spectral") else []
        d["pitch_set"] = pset
        info = scorer.score(fdesc, partials, None, gm, tol, harmonic_reason=why or None,
                            allowed_midis=pset or None)
        s = info["score"]
        for k, v in info.get("effective_weights", {}).items():
            eff_union[k] = v
        if not info["used"]:
            reasons["no_valid_descriptors"] += 1
            d["status"] = "no_valid_descriptors"
            continue
        if not np.any(np.isfinite(s)):
            reasons["pitch_gate_empty"] += 1
            d["status"] = "pitch_gate_empty"
            continue
        if thresh_gate(thresh, float(np.nanmin(s))):
            reasons["threshold_rejected"] += 1
            d["status"] = "threshold_rejected"
            continue
        if thresh > 0:
            s = np.where(s > thresh, np.nan, s)
        S[i] = (s.astype(np.float64), info)
    # v1.11.6: global instrument allocation, then one Viterbi voice per
    # selected instrument (see allocate_instruments / _viterbi_runs).
    n_req = RENDER_LAYERS.get(params["render_mode"], 1)
    inst_keys = [instrument_key(e) for e in domain]
    alloc = allocate_instruments(S, frames, inst_keys, n_req)
    sel_keys = [a_["key"] for a_ in alloc["selected"]]
    print("  Instrument allocation (requested %d): %s" % (n_req, "; ".join(
        "%s cost %.3f coverage %.0f%%" % (a_["key"][1], a_["cost"], 100 * a_["coverage"])
        for a_ in alloc["selected"]) or "none"))
    if alloc["note"]:
        print("  [WARN] " + alloc["note"])
    inst_arr = np.array([sel_keys.index(k) if k in sel_keys else -1 for k in inst_keys],
                        dtype=np.int64) if domain else np.zeros(0, dtype=np.int64)
    voices = []
    for v in range(len(sel_keys)):
        Sv = {}
        for i in S:
            s_ = S[i][0].copy()
            s_[inst_arr != v] = np.nan
            if not np.any(np.isfinite(s_)):
                continue          # this instrument has no legal sample here: it rests
            cls = ev_class.get(frames[i]["event"], "ambiguous")
            pset = diag[i].get("pitch_set") or []
            used_midi = {int(midi_arr[vc[i]]) for vc in voices if i in vc}
            if cls == "polyphonic" and set(pset) - used_midi:
                # avoid doubling an evidenced chord note while another
                # evidenced note is still uncovered (no invented pitches:
                # candidates are already restricted to the event pitch set)
                s2 = s_.copy()
                s2[np.isin(midi_arr, list(used_midi))] = np.nan
                if np.any(np.isfinite(s2)):
                    s_ = s2
            Sv[i] = s_
        voices.append(_viterbi_runs(Sv, events, midi_arr))
    n_voices = len(voices)
    raw_vw = [1.0 / (v + 1) for v in range(n_voices)] if params["render_mode"] == "blend" \
        else [1.0] * n_voices

    matches = []
    pitch_changes = sample_changes = 0
    change_reasons = Counter()
    prev = [None] * n_voices
    for i, fi in enumerate(frames):
        d = diag[i]
        match = None
        layers = []
        present = [v for v in range(n_voices) if i in voices[v]]
        if present:
            reasons["matched"] += 1
            d["status"] = "matched"
            s, info = S[i]
            norm_w = math.sqrt(sum(raw_vw[v] ** 2 for v in present))
            for v in present:
                cv = voices[v][i]
                lm = (float(s[cv]), domain[cv], {"cal": {k: float(x[cv]) for k, x in info["cal"].items()}})
                layers.append({"voice": v + 1, "match": lm, "weight": raw_vw[v] / norm_w})
                pm = prev[v]
                if pm is not None:
                    if pm[0][1] is not domain[cv]:
                        sample_changes += 1
                        if fi["event"] != pm[1]:
                            why = "new_event:" + (fi["boundary"] or "?")
                        elif d.get("gate_midi") is not None and d.get("gate_midi") != pm[2]:
                            why = "pitch_transition"
                        else:
                            why = "spectral_evolution"
                        if v == present[0]:
                            d["change"] = why
                        change_reasons[why.split(":")[0]] += 1
                    if pm[0][1].midi != domain[cv].midi:
                        pitch_changes += 1
                prev[v] = (lm, fi["event"], d.get("gate_midi"))
            match = layers[0]["match"]
        matches.append({"frame": fi, "match": match, "layers": layers})
    n_matched = reasons["matched"]
    vcount = [sum(1 for m in matches if any(l["voice"] == v + 1 for l in m["layers"]))
              for v in range(n_voices)]
    print("  Instrument voices: %d  (frames per voice %s)" % (n_voices, vcount))
    ctx["voice_frames"] = vcount
    ctx["alloc"] = alloc
    ctx["instr_note"] = alloc["note"]
    report["instrument_allocation"] = {
        "requested": n_req, "criterion": ALLOC_CRITERION, "note": alloc["note"],
        "selected": [{"family": a_["key"][0], "instrument": a_["key"][1], "cost": a_["cost"],
                      "coverage": a_["coverage"]} for a_ in alloc["selected"]],
        "ranking": [{"family": a_["key"][0], "instrument": a_["key"][1], "cost": a_["cost"],
                     "coverage": a_["coverage"]} for a_ in alloc["ranking"]]}
    print("  Matched %d / %d frames  %s" % (n_matched, len(frames), dict(reasons)))
    print("  Orchestral pitch changes: %d   sample changes: %d  %s"
          % (pitch_changes, sample_changes, dict(change_reasons)))
    dom, label = interpretation_summary(events, frames)
    ctx["eff"] = eff_union
    ctx["status_line"] = _status_line(statuses, eff_union)
    ctx["interpretation"] = interp
    ctx["interpretation_label"] = label
    ctx["interpretation_class"] = dom
    ctx["n_events"] = len(events)
    ctx["pitch_changes"] = pitch_changes
    ctx["sample_changes"] = sample_changes

    # Event geometry for coherent rendering (target-rate samples).
    for m in matches:
        fi = m["frame"]
        if fi["event"] >= 0:
            e = events[fi["event"]]
            m["event_start"] = frames[e["first"]]["start"]
            m["event_end"] = frames[e["last"]]["start"] + fsize

    print("[6/8] Overlap-add render ...")
    out, rinfo = render_frame_matches(matches, fsize, hsize, tlen, tsr, params["_render_gain"],
                                      return_info=True,
                                      normalize=params["_level_matching"] == "off")
    out, env_stats = apply_target_macro_envelope(out, raw_audio, tsr, params["_envelope_follow"])
    channels = finish_output(out, rinfo, env_stats, target_wav, tsr, params, ctx, report)
    print("[7/8] Writing multichannel output WAV ...")
    ctx["output_dur"] = write_output(out_wav, channels, tsr)
    print("[8/8] Writing results file ...")
    write_frame_results(results_txt, matches, params, tsr, tlen, env_stats, ctx,
                        reasons=dict(reasons), rendered_frames=rinfo["rendered_frames"])
    usage = Counter(l["match"][1].abs_path for m in matches for l in (m.get("layers") or []))
    n_reliable = sum(1 for f in frames if f["pitch"]["reliable"])
    n_sounding = sum(1 for f in frames if not f.get("silent"))
    frame_rows = []
    for i, (fi, m) in enumerate(zip(frames, matches)):
        ev, d = fi["pitch"], diag[i]
        row = {"i": i, "time_s": round(fi["time_s"], 4), "event": fi["event"],
               "boundary": fi.get("boundary", ""),
               "event_class": ev_class.get(fi["event"], "") if fi["event"] >= 0 else "",
               "frame_class": ev["class"], "f0_est_hz": ev["f0_est"], "acf_f0_hz": ev["acf_f0"],
               "pitch_confidence": round(ev["confidence"], 4), "reliable": ev["reliable"],
               "periodicity": round(ev["periodicity"], 4), "harmonic_share": round(ev["harmonic_share"], 4),
               "occupancy": round(ev["occupancy"], 4), "extra_sources": round(ev["extra_sources"], 4),
               "tonality": round(ev["tonality"], 4), "temporal": ev["temporal"],
               "pitch_reason": ev["reason"], "gate": d.get("gate", False),
               "gate_midi": d.get("gate_midi"), "harmonic_scoring": d.get("harmonic", False),
               "gate_note": d.get("pitch_note", ""), "status": d.get("status", ""),
               "event_pitch_set_applied": d.get("pitch_set", []),
               "rms_db": round(20 * math.log10(max(fi["rms"], 1e-12)), 2)}
        if len(m.get("layers") or []) > 1:
            row["voices"] = ["%s %d" % (l["match"][1].inst, l["match"][1].midi) for l in m["layers"]]
        if m["match"]:
            row.update(instrument=m["match"][1].inst, midi=m["match"][1].midi,
                       dynamic=m["match"][1].dyn, path=m["match"][1].abs_path,
                       score=round(m["match"][0], 5), changed=bool(d.get("change")),
                       change_reason=d.get("change", ""))
        frame_rows.append(row)
    report.update({
        "mode": "frame_based",
        "pitch_interpretation": interp,
        "interpretation_label": label,
        "effective_weights": eff_union,
        "events": [{k: v for k, v in e.items()} for e in events],
        "frames": {"total": len(frames), "reasons": dict(reasons),
                   "matched": n_matched, "rendered": rinfo["rendered_frames"],
                   "coverage": n_matched / max(1, len(frames) - reasons["silent"]),
                   "switches": sample_changes, "failed_files": rinfo["failed_files"],
                   "phase_coherent_frames": rinfo["coherent_frames"]},
        "summary": {"events": len(events), "reliable_pitched_frames": n_reliable,
                    "ambiguous_frames": n_sounding - n_reliable,
                    "pitch_gate_suppressions": reasons["pitch_gate_suppressed"],
                    "orchestral_pitch_changes": pitch_changes,
                    "sample_changes": sample_changes,
                    "sample_change_reasons": dict(change_reasons),
                    "unmatched_frames": n_sounding - n_matched},
        "frame_diagnostics": frame_rows,
        "usage": [{"path": p, "frames": c} for p, c in usage.most_common(params["_n_results"])],
        "silence": {"rendered": n_matched == 0 or rinfo["rendered_frames"] == 0,
                    "reason": ("no_valid_descriptors" if n_matched == 0 and reasons["no_valid_descriptors"]
                               else "frame_unmatched") if n_matched == 0 else
                    ("render_failed" if rinfo["rendered_frames"] == 0 else ""),
                    "threshold": thresh},
        "durations": {"target_s": ctx["target_dur"], "output_s": ctx["output_dur"]},
        "envelope": env_stats,
    })


# ─────────────────────────────────────────────────────────────────────────────
# Maintenance CLI
# ─────────────────────────────────────────────────────────────────────────────

def build_descriptor_db(corpus_root, out_dir, names=DB_NAMES, progress=True):
    """Compute AudioTools at1 descriptors for every TinySOL WAV under
    corpus_root and write TinySOL.<name>.db files with a provenance header
    into out_dir.  Refuses to overwrite any existing file."""
    import numpy as np
    exts = {n: at1_extractor(n, COMPACT_DESCRIPTOR_DIMS[n]) for n in names}
    os.makedirs(out_dir, exist_ok=True)
    targets = {n: os.path.join(out_dir, "TinySOL.%s.db" % n) for n in names}
    clash = [p for p in targets.values() if os.path.exists(p)]
    if clash:
        raise FileExistsError("Refusing to overwrite existing file(s): %s" % ", ".join(clash))
    entries, _, _ = scan_corpus(corpus_root)
    rows = {n: [] for n in names}
    skipped = []
    for k, e in enumerate(entries):
        try:
            x44, _, _ = load_contract_audio(e.abs_path)
            P = contract_power(x44)
        except Exception as exc:
            skipped.append((e.abs_path, str(exc)))
            continue
        d = descriptors_from_power(P, exts)
        for n in names:
            if np.all(np.isfinite(d[n])):
                rows[n].append((e.abs_path.replace("\\", "/"), d[n]))
        if progress and (k + 1) % 200 == 0:
            print("  %d / %d" % (k + 1, len(entries)))
    for n in names:
        with open(targets[n], "w", encoding="utf-8", newline="\n") as f:
            f.write("#AUDIOTOOLS_DESCRIPTOR_DB profile=%s descriptor=%s extractor=%s dim=%d "
                    "sr=%d n_fft=%d hop=%d window=hann agg=mean_power builder=%s\n"
                    % (AT_PROFILE_ID, n, exts[n].id, exts[n].dim, DESCRIPTOR_SAMPLE_RATE,
                       CONTRACT_N_FFT, CONTRACT_HOP, VERSION))
            for p, v in rows[n]:
                f.write(p + ";" + ";".join(repr(float(x)) for x in v) + "\n")
    return {"entries": len(entries), "written": {n: len(rows[n]) for n in names},
            "skipped": skipped, "files": targets}


def cli_build_db(args):
    if len(args) < 2:
        print("usage: --build-db <corpus_root> <new_output_dir> [--descriptors a,b,...]", file=sys.stderr)
        return 1
    names = DB_NAMES
    if "--descriptors" in args:
        names = tuple(_split_csv(args[args.index("--descriptors") + 1]))
    try:
        res = build_descriptor_db(args[0], args[1], names)
    except FileExistsError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1
    print("Built %s from %d corpus files; skipped %d." % (res["written"], res["entries"], len(res["skipped"])))
    return 0


def cli_verify_db(args):
    """--verify-db <db_dir> <corpus_root> [--probe-files N] [--descriptors a,b]

    v1.11.6 exit codes (the tables are only read, never written):
      0  COMPLETE  every requested table loaded, has no malformed rows and was
                   reproduced (category A or B);
      3  PARTIAL   at least one requested table passed, at least one did not;
      2  FAILED    no requested table passed -- including an empty or wrong
                   directory where no table loads at all;
      1  usage error.
    The old rule all(usable) was vacuously true when nothing had loaded."""
    if len(args) < 2:
        print("usage: --verify-db <db_dir> <corpus_root> [--probe-files N] [--descriptors a,b,...]",
              file=sys.stderr)
        return 1
    n = int(args[args.index("--probe-files") + 1]) if "--probe-files" in args else 12
    requested = list(DB_NAMES)
    if "--descriptors" in args:
        requested = [x.strip() for x in _split_csv(args[args.index("--descriptors") + 1]) if x.strip()]
        unknown = [x for x in requested if x not in DB_NAMES]
        if unknown or not requested:
            print("ERROR: unknown descriptor table(s): %s (known: %s)"
                  % (", ".join(unknown) or "(none given)", ", ".join(DB_NAMES)), file=sys.stderr)
            return 1
    if not os.path.isdir(args[0]):
        print("VERIFY RESULT: FAILED -- database directory not found: %s" % args[0])
        return 2
    store = DbStore()
    loaded = [nm for nm in requested if store.load(args[0], nm)]
    entries = build_index(args[1], store) if loaded else []
    params = {"_probe_files": n, "_allow_unverified": False}
    st = resolve_descriptor_profile(store, entries, params, loaded) if loaded else {}
    rows, passed, failed = {}, [], []
    for nm in requested:
        if nm not in st:
            rows[nm] = {"loaded": False, "passed": False,
                        "reason": "TinySOL.%s.db not found in %s" % (nm, args[0])}
            failed.append(nm)
            continue
        d = st[nm].to_dict()
        bad = int(store.malformed.get(nm, 0))
        ok = bool(st[nm].usable) and not st[nm].unverified_override and bad == 0
        d.update(loaded=True, malformed_rows=bad, passed=ok)
        if bad and st[nm].usable:
            d["reason"] = "%d malformed row(s); %s" % (bad, d.get("reason", ""))
        rows[nm] = d
        (passed if ok else failed).append(nm)
    verdict = "COMPLETE" if passed and not failed else ("PARTIAL" if passed else "FAILED")
    print(json.dumps(_json_safe({"tables": rows, "verdict": verdict,
                                 "requested": requested, "passed": passed, "failed": failed}), indent=2))
    print("VERIFY RESULT: %s -- checked %d: %s; passed %d: %s; failed %d: %s" % (
        verdict, len(requested), ", ".join(requested), len(passed), ", ".join(passed) or "none",
        len(failed), ", ".join("%s (%s)" % (f, rows[f]["reason"]) for f in failed) or "none"))
    return {"COMPLETE": 0, "PARTIAL": 3, "FAILED": 2}[verdict]


if __name__ == "__main__":
    main()
