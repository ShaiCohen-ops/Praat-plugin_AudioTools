"""
tinysol_retrieval.py — TinySOL Orchestration Retrieval Backend
Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University
Version: 1.9

Usage (called by Praat via TinySOL_Retrieval.praat, not directly):
    python tinysol_retrieval.py  target.wav  params.txt  output.wav  results.txt

params.txt is a simple key=value file written by Praat:
    db_dir=D:\\old D\\waves\\TinySOL_2020
    corpus_root=D:\\old D\\waves\\TinySOL_2020\\TinySOL
    allowed_families=Brass,Strings,Winds
    allowed_instruments=          (empty = all)
    min_midi=36
    max_midi=96
    preferred_dynamics=mf,ff
    max_layers=1
    descriptor_weights=mfcc:0.25,specenv:0.20,moments:0.05,specpeaks:0.15,harmonic:0.35
    n_results=8
    render_mode=best          (best | blend | top2 | top3 | top4)
                               blend      = top-3, rank-weighted (1/rank)
                               top2/3/4   = equal mix of N layers
    render_gain=0.8
    envelope_follow=0.85

Changes in v1.9 (macro-envelope transfer):
    - Optional envelope_follow (0..1, default 0.85) transfers the target's
      smoothed RMS macro-envelope onto the rendered orchestral result.  The
      envelope is compared on a normalised 0..1 time axis, so TinySOL samples
      of different durations inherit the target gesture without time-stretching
      or pitch-shifting the corpus audio.
    - Envelope transfer uses power across real channels (no phase-cancelling
      fold-down), a 100 ms macro smoother, a -30 dB denominator floor and a
      +12 dB boost ceiling to avoid unstable pumping.  envelope_follow=0 is
      exactly v1.8 audio.
    - Frame-based mode also applies the same macro stage after OLA; its existing
      per-frame RMS matching remains intact, while the new stage corrects only
      slower attack/release shape.
    - Results report envelope correlation before/after transfer.

Changes in v1.8 (correctness + corpus coverage):
    - Replaced the old F0 autocorrelation/octave heuristic with overlap-energy-
      normalized FFT autocorrelation and first-strong-period selection.  The old
      detector systematically octave-divided clean tones (e.g. 440 Hz -> 220.5 Hz)
      and hard-capped detection at 600 Hz; v1.8 is reliable across TinySOL's
      practical note range, including the high violin register.
    - Frame-mode F0 smoothing now requires a voiced majority in the local window;
      isolated voiced detections no longer smear pitch gates across silence/noise.
    - Silent target frames are explicitly unmatched/rendered as silence.  v1.7
      left corpus grains at full amplitude when target_rms == 0.
    - silence_threshold now applies in frame mode too; threshold >= 2.0 is an
      explicit disabled gate, matching the UI/default intent.
    - Whole-file variant deduplication moved AFTER scoring, so the acoustically
      best string/instance variant is retained instead of choosing by filename
      length before hearing its descriptor distance.
    - Speech mode disables both harmonic scoring and legacy pitch penalties/gates.
    - Target multichannel analysis uses the strongest real RMS channel instead of
      phase-cancellable channel averaging.
    - TinySOL family is inferred first from the official corpus path; Keyboards
      (Accordion) and wind instruments not present in the old prefix table are no
      longer silently classified as Unknown.
    - Corpus sample-rate conversion uses scipy.signal.resample_poly instead of
      linear interpolation.
    - Output WAV is written as 32-bit float.

Changes in v1.7 (performance):
    - _compute_mfcc(): mel filterbank construction is now fully vectorised
      via numpy broadcasting instead of two nested Python loops.  For typical
      n_fft=4096 (n_bins=2049, n_mels=20) this collapses ~4000 Python-level
      operations into a few numpy calls.  Previous frame-based runs spent a
      meaningful fraction of CPU time in this loop; now it's a single matmul.
    - _compute_mfcc(): DCT-II is now a single matrix multiply instead of an
      n_mfcc-iteration Python loop.  Same numerical output, faster.
    - Output is mathematically identical to v1.6 — same triangular filterbank
      shape, same DCT-II coefficients.

Changes in v1.6 (bugfixes):
    - parse_params(): speech_mode weight override moved AFTER normal weight
      parsing.  Previously the override at line 252 was clobbered by the
      unconditional dw assignment at line 273, so speech_mode=1 had no effect
      on descriptor weights.
    - _analyse_frame(): now computes specpeaks (16 peaks) in addition to
      mfcc/specenv/moments.  Previously the specpeaks weight (0.15) was
      silently skipped in frame-based mode because _analyse_frame() didn't
      produce a specpeaks vector, causing score_entry() to skip it when
      t_vec was None.

Changes in v1.4 (speech input support):
    - parse_params(): new "speech_mode" parameter (default 0).  When set to 1,
      descriptor weights are automatically overridden to a speech-optimised
      profile (mfcc=0.45, specenv=0.30, moments=0.10, specpeaks=0.15,
      harmonic=0.00) before any retrieval takes place.  The harmonic weight is
      zeroed because orchestral harmonic-series matching is meaningless for
      aperiodic / speech signals and inflates scores above the silence gate.
    - analyse_target(): when the target has no voiced frames (n_voiced == 0),
      target_partials is set to None so harmonic_contribution_distance() returns
      the neutral 0.5 rather than a worst-case 1.0 (which it would if passed an
      empty list with a non-zero harmonic weight).
    - silence_threshold default raised to 2.0 (was 1.0).  The old default of
      1.0 is exactly at the natural upper bound of cosine distance, so any
      imperfect match on a complex signal would trigger the silence gate.
      2.0 is a safe "always render" value; users can lower it once they know
      their score range.

Changes in v1.3 (Orchidea-architecture pass):
    - build_candidate_domain(): new function that enforces ALL hard constraints
      (family, instrument, MIDI range) BEFORE scoring — mirrors Orchidea's
      Production::computeVariableDomains() separation of legal domains from scoring.
      Frame-based path now also builds the domain once and reuses it per frame.
    - MIDI range is now a HARD filter in build_candidate_domain(), not a soft
      penalty in score_entry().  Entries outside [min_midi, max_midi] are
      excluded entirely — no more "technically out of range but penalised" results.
    - specenv_distance(): dedicated distance dispatcher for specenv descriptors.
      Currently delegates to cosine_distance() (same behaviour as v1.2).
      hellinger_distance() and kl_distance_symmetric() are implemented and
      available for future use once descriptor weights are re-tuned against them.
      NOTE: Hellinger on log-energy vectors produces values 10-100x larger than
      cosine for the same comparisons; switching without weight recalibration
      causes spuriously high scores that trigger the silence gate.
    - silence_threshold param (default 1.0 = disabled): if the top-ranked match
      score exceeds this threshold, the output WAV is silence and results note
      the reason.  Default is 1.0 so it is opt-in — lower it consciously once
      you understand your typical score range (e.g. 0.85 for a well-tuned setup).
    - Architecture comment updated to reflect domain-first pipeline.

Changes in v1.2:
    - render_frame_matches: removed *3 wrap multiplier from read_offset.
      The position now advances linearly through the sustain region once,
      eliminating hard splices that caused audible clicks every ~6 seconds.
    - render_frame_matches: Hann window is now applied before RMS measurement.
      Previously the raw (unwindowed) grain was measured, which overestimated
      RMS and caused amplitude bumps at every hop after OLA normalisation.

Changes in v1.1:
    - blend_samples: top2/top3/top4 now use equal weights (not 1/rank).
      'blend' keeps rank-weighted behaviour.  Labels in Praat UI now match.
    - Silent constraint-loosening fallback removed from whole-file retrieve.
      Mismatched family/path errors now exit with a clear message.
    - Frame-based best_match line now reports the real score (was hardcoded 0).
    - Default hop_size_ms changed from 37 ms to 75 ms.

Architecture:
    Stage 1  — Parse parameters
    Stage 2  — Load .db files (lazy, cached in memory)
    Stage 3  — Parse TinySOL filename metadata
    Stage 4  — Build unified entry index
    Stage 4b — Build candidate domain (hard-constraint filter, Orchidea-style)
    Stage 5  — Analyse target WAV (MFCC, specenv, moments, specpeaks, partials)
    Stage 6  — Multi-descriptor retrieval + ranking (with harmonic contribution)
    Stage 7  — Optional small-mixture blending (up to 4 layers)
    Stage 8  — Render output WAV (silence if best score > silence_threshold)
    Stage 9  — Write results text file

Dependencies: numpy, soundfile, scipy  (same as latent_diffusion.py)
"""

import sys
import os
import re
import math

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

DB_NAMES = ("mfcc", "specenv", "moments", "specpeaks", "spectrum")

# Canonical dynamic order for comparison / normalisation
DYN_ORDER = {"ppp": 0, "pp": 1, "p": 2, "mp": 3, "mf": 4, "f": 5, "ff": 6, "fff": 7}

# Instrument-family mapping (prefix → family)
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

# MIDI note name → number
NOTE_NAME_TO_MIDI = {}
_NOTE_LETTERS = ["C", "C#", "D", "D#", "E", "F",
                 "F#", "G", "G#", "A", "A#", "B"]
for _oct in range(0, 10):
    for _i, _name in enumerate(_NOTE_LETTERS):
        _midi = (_oct + 1) * 12 + _i
        NOTE_NAME_TO_MIDI["%s%d" % (_name, _oct)] = _midi
        if "#" in _name:
            # Enharmonic flat: C#→Db, D#→Eb, F#→Gb, G#→Ab, A#→Bb
            _letter = _name[0]
            _next = chr(ord(_letter) + 1) if _letter != 'G' else 'A'
            _flat = _next + "b" + str(_oct)
            NOTE_NAME_TO_MIDI[_flat] = _midi

# Praat uses A#/Bb style — add explicit aliases
NOTE_NAME_TO_MIDI.update({
    "Bb0": NOTE_NAME_TO_MIDI.get("A#0", 22),
    "Bb1": NOTE_NAME_TO_MIDI.get("A#1", 34),
    "Bb2": NOTE_NAME_TO_MIDI.get("A#2", 46),
    "Bb3": NOTE_NAME_TO_MIDI.get("A#3", 58),
    "Bb4": NOTE_NAME_TO_MIDI.get("A#4", 70),
    "Bb5": NOTE_NAME_TO_MIDI.get("A#5", 82),
    "Eb3": NOTE_NAME_TO_MIDI.get("D#3", 51),
    "Eb4": NOTE_NAME_TO_MIDI.get("D#4", 63),
    "Eb5": NOTE_NAME_TO_MIDI.get("D#5", 75),
})


def _hz_to_midi(hz):
    """Convert a frequency in Hz to the nearest MIDI note number, or None."""
    if hz is None or hz <= 0.0:
        return None
    return int(round(69.0 + 12.0 * math.log(hz / 440.0, 2)))


# ─────────────────────────────────────────────────────────────────────────────
# Dependency check
# ─────────────────────────────────────────────────────────────────────────────

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

def parse_params(params_path):
    """Read key=value params file written by Praat."""
    params = {}
    with open(params_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, _, v = line.partition("=")
                params[k.strip()] = v.strip()

    # Apply defaults
    defaults = {
        "db_dir":              "",
        "corpus_root":         "",
        "allowed_families":    "Brass,Strings,Winds",
        "allowed_instruments": "",
        "min_midi":            "21",
        "max_midi":            "108",
        "preferred_dynamics":  "mf,ff",
        "max_layers":          "1",
        "descriptor_weights":  "mfcc:0.25,specenv:0.20,moments:0.05,specpeaks:0.15,harmonic:0.35",
        "n_results":           "8",
        "render_mode":         "best",
        "render_gain":         "0.8",
        "envelope_follow":      "0.85",
        "stereo_output":       "1",
        "analysis_mode":       "whole_file",
        "frame_size_ms":       "150",
        "hop_size_ms":         "75",
        "pitch_tolerance":     "2",
        "pitch_pan_stereo":    "1",
        "silence_threshold":   "2.0",
        "speech_mode":         "0",
    }
    for k, v in defaults.items():
        params.setdefault(k, v)

    # Parse composite fields
    params["_allowed_families"]    = _split_csv(params["allowed_families"])
    params["_allowed_instruments"] = [
        x for x in _split_csv(params["allowed_instruments"])
        if x and not x.startswith("(")   # strip Praat placeholder hints like "(empty = all families)"
    ]
    params["_preferred_dynamics"]  = _split_csv(params["preferred_dynamics"])
    params["_min_midi"]  = int(params["min_midi"])
    params["_max_midi"]  = int(params["max_midi"])
    params["_max_layers"] = int(params["max_layers"])
    params["_n_results"]  = int(params["n_results"])
    params["_render_gain"]    = float(params["render_gain"])
    params["_envelope_follow"] = max(0.0, min(1.0, float(params["envelope_follow"])))
    params["_stereo_output"]  = params["stereo_output"].strip() not in ("0", "false", "no", "")
    params["_analysis_mode"]  = params["analysis_mode"].strip().lower()
    params["_frame_size_ms"]  = float(params["frame_size_ms"])
    params["_hop_size_ms"]    = float(params["hop_size_ms"])
    params["_pitch_tolerance"]  = int(params["pitch_tolerance"])
    params["_pitch_pan_stereo"] = params["pitch_pan_stereo"].strip() not in ("0", "false", "no", "")
    params["_silence_threshold"] = float(params["silence_threshold"])
    params["_speech_mode"] = params["speech_mode"].strip() not in ("0", "false", "no", "")

    # Descriptor weights:  mfcc:0.25,specenv:0.20,moments:0.05,specpeaks:0.15,harmonic:0.35
    dw = {}
    for tok in params["descriptor_weights"].split(","):
        tok = tok.strip()
        if ":" in tok:
            name, w = tok.split(":", 1)
            try:
                dw[name.strip()] = float(w.strip())
            except ValueError:
                pass
    if not dw:
        dw = {"mfcc": 0.25, "specenv": 0.20, "moments": 0.05, "specpeaks": 0.15, "harmonic": 0.35}
    params["_descriptor_weights"] = dw

    # Speech mode: override descriptor weights AFTER normal parsing.
    # Harmonic weight is zeroed — orchestral harmonic matching is meaningless
    # for aperiodic / speech signals and inflates scores past the silence gate.
    if params["_speech_mode"]:
        params["_descriptor_weights"] = {
            "mfcc":     0.45,
            "specenv":  0.30,
            "moments":  0.10,
            "specpeaks": 0.15,
            "harmonic": 0.00,
        }
        print("  [PARAMS] speech_mode=1: descriptor weights overridden for speech input.")

    # Distances are internally normalized by the sum of active weights, so the
    # user need not make them sum to 1.  But at least one must be positive.
    if sum(max(0.0, float(v)) for v in params["_descriptor_weights"].values()) <= 0.0:
        raise ValueError("At least one descriptor weight must be > 0")

    return params


def _split_csv(s):
    """Split comma-separated string, strip whitespace, drop empties."""
    return [x.strip() for x in s.split(",") if x.strip()]


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — .db file loading
# ─────────────────────────────────────────────────────────────────────────────

class DbStore:
    """
    Holds all loaded .db tables.

    Two lookup indices per table:
      full_index : normalised_full_path  -> np.ndarray
      stem_index : lowercase_basename_no_ext -> np.ndarray

    Lookup order: full path first (precise), then basename stem (robust
    fallback when .db paths differ from the filesystem walk paths).
    This handles the common case where .db files were built on a different
    machine or with a different corpus root prefix.
    """

    def __init__(self):
        self.full_index   = {}   # db_name -> {norm_full_path: vec}
        self.stem_index   = {}   # db_name -> {basename_stem:  vec}
        self.headers      = {}   # db_name -> header string
        self._sample_path = {}   # db_name -> first raw path (diagnostics)

    def load(self, db_dir, name):
        """Load one .db file (e.g. 'mfcc') from db_dir."""
        import numpy as np

        path = os.path.join(db_dir, "TinySOL.%s.db" % name)
        if not os.path.isfile(path):
            print("  [DB] WARNING: %s not found, skipping." % path, file=sys.stderr)
            return

        full_tbl  = {}
        stem_tbl  = {}
        header    = ""
        n_loaded  = 0
        n_skipped = 0
        first_raw = ""

        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for lineno, raw in enumerate(fh, 1):
                line = raw.rstrip("\r\n")
                if lineno == 1:
                    header = line
                    continue
                if not line.strip():
                    continue
                sep = line.find(";")
                if sep < 0:
                    n_skipped += 1
                    continue
                raw_path   = line[:sep]
                values_str = line[sep + 1:]
                try:
                    vec = np.fromstring(values_str, dtype=np.float32, sep=";")
                except Exception:
                    n_skipped += 1
                    continue
                if vec.size == 0:
                    n_skipped += 1
                    continue

                norm_full = _normalise_path(raw_path)
                stem      = _path_stem(raw_path)
                full_tbl[norm_full] = vec
                stem_tbl[stem]      = vec   # last writer wins — OK for TinySOL
                n_loaded += 1
                if not first_raw:
                    first_raw = raw_path

        self.full_index[name]   = full_tbl
        self.stem_index[name]   = stem_tbl
        self.headers[name]      = header
        self._sample_path[name] = first_raw
        print("  [DB] Loaded %-10s: %d entries  (skipped %d)  sample='%s'"
              % (name, n_loaded, n_skipped,
                 os.path.basename(first_raw) if first_raw else "?"))

    def get(self, name, abs_path):
        """
        Return descriptor vector for abs_path, or None.
        Tries normalised full path first, then basename-stem fallback.
        """
        # 1) Full-path lookup
        norm = _normalise_path(abs_path)
        ft = self.full_index.get(name)
        if ft is not None:
            vec = ft.get(norm)
            if vec is not None:
                return vec
        # 2) Stem fallback (handles corpus-root prefix differences)
        stem = _path_stem(abs_path)
        st = self.stem_index.get(name)
        if st is not None:
            return st.get(stem)
        return None

    def stem_hit_rate(self, name, sample_abs_paths):
        """Diagnostic: fraction of sample paths that resolve via stem index."""
        hits = sum(1 for p in sample_abs_paths if self.get(name, p) is not None)
        return hits, len(sample_abs_paths)


def _normalise_path(p):
    """Canonical lowercase forward-slash form, stripped of whitespace."""
    return p.replace("\\", "/").lower().strip()


def _path_stem(p):
    """
    Lowercase basename without extension.
    e.g.  'D:\\TinySOL\\Brass\\BTb-ord-A#1-ff.wav'  ->  'btb-ord-a#1-ff'
    """
    base = os.path.basename(p.replace("\\", "/"))
    stem, _ = os.path.splitext(base)
    return stem.lower().strip()


# ─────────────────────────────────────────────────────────────────────────────
# Stage 3 — TinySOL filename parsing
# ─────────────────────────────────────────────────────────────────────────────

# Pattern:  <Instrument>-<Technique>-<Pitch><Octave>-<Dynamic>[-<Variant>]
# Examples: BTb-ord-A#1-ff.wav   Va-ord-A4-mf-2c.wav   Vn-ord-D5-pp-2c.wav
_FNAME_RE = re.compile(
    r"^(?P<inst>[A-Za-z]+(?:[A-Za-z#0-9]*?))"   # instrument (letters, possibly Bb, ClBb …)
    r"-(?P<tech>[a-zA-Z]+)"                       # technique
    r"-(?P<note>[A-Gb#]+\d+)"                     # note + octave  (A#1, Bb3, D5 …)
    r"-(?P<dyn>[a-zA-Z]+)"                        # dynamic
    r"(?:-(?P<variant>\S+?))?"                    # optional variant (-1c, -2c, -pizz …)
    r"\.wav$",
    re.IGNORECASE,
)

# Broader instrument prefix extraction for family lookup
_INST_PREFIXES = sorted(FAMILY_MAP.keys(), key=len, reverse=True)


def parse_filename(fname):
    """
    Parse a TinySOL WAV filename.
    Returns dict with keys: inst, tech, note, dyn, variant, midi, family
    or None if the filename does not match.
    """
    base = os.path.basename(fname)
    m = _FNAME_RE.match(base)
    if not m:
        return None

    inst    = m.group("inst")
    tech    = m.group("tech").lower()
    note    = m.group("note")          # e.g. "A#1"
    dyn     = m.group("dyn").lower()   # e.g. "ff"
    variant = m.group("variant") or "" # e.g. "2c"

    midi = _note_to_midi(note)
    if midi is None:
        return None

    family = _family_for_instrument(inst)

    return {
        "inst":    inst,
        "tech":    tech,
        "note":    note,
        "dyn":     dyn,
        "variant": variant,
        "midi":    midi,
        "family":  family,
    }


def _note_to_midi(note_str):
    """Convert 'A#1', 'D5', 'Bb3' to MIDI note number, or None."""
    # Try direct lookup first
    note_str_up = note_str[0].upper() + note_str[1:]
    if note_str_up in NOTE_NAME_TO_MIDI:
        return NOTE_NAME_TO_MIDI[note_str_up]

    # Try with capitalised accidental
    note_str_norm = re.sub(r"([A-Ga-g])([#b]?)(\d+)",
                           lambda mm: mm.group(1).upper() + mm.group(2) + mm.group(3),
                           note_str_up)
    return NOTE_NAME_TO_MIDI.get(note_str_norm)


def _family_for_instrument(inst):
    for prefix in _INST_PREFIXES:
        if inst.startswith(prefix):
            return FAMILY_MAP[prefix]
    # Fall back: try to infer from first letters
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
    """Return the canonical TinySOL family from a corpus path, if present."""
    canonical = {
        "brass": "Brass",
        "strings": "Strings",
        "winds": "Winds",
        "keyboards": "Keyboards",
    }
    parts = [x for x in re.split(r"[\\/]+", str(path)) if x]
    for part in parts:
        fam = canonical.get(part.strip().lower())
        if fam is not None:
            return fam
    return None


def _instrument_name_from_path(path):
    """Return TinySOL's full instrument folder name when using official layout."""
    parts = [x for x in re.split(r"[\\/]+", str(path)) if x]
    for i, part in enumerate(parts):
        if part.strip().lower() == "ordinario" and i > 0:
            return parts[i - 1].strip()
    return ""


def _norm_label(text):
    return re.sub(r"[^a-z0-9]+", "", str(text).lower())


# ─────────────────────────────────────────────────────────────────────────────
# Stage 4 — Unified entry index
# ─────────────────────────────────────────────────────────────────────────────

class TinySolEntry:
    """One sample from the TinySOL corpus."""
    __slots__ = ("abs_path", "norm_path", "inst", "instrument_name",
                 "tech", "note", "dyn", "variant", "midi", "family",
                 "descriptors")

    def __init__(self, abs_path, meta):
        self.abs_path   = abs_path
        self.norm_path  = _normalise_path(abs_path)
        self.inst       = meta["inst"]
        self.instrument_name = _instrument_name_from_path(abs_path) or self.inst
        self.tech       = meta["tech"]
        self.note       = meta["note"]
        self.dyn        = meta["dyn"]
        self.variant    = meta["variant"]
        self.midi       = meta["midi"]
        self.family     = meta["family"]
        self.descriptors = {}  # db_name -> np.ndarray

    def populate_descriptors(self, db_store):
        for name in DB_NAMES:
            vec = db_store.get(name, self.abs_path)
            if vec is not None:
                self.descriptors[name] = vec

    def has_descriptor(self, name):
        return name in self.descriptors

    def __repr__(self):
        return "<Entry %s %s %s %s>" % (self.inst, self.note, self.dyn, self.variant)


def build_index(corpus_root, db_store, params):
    """
    Walk corpus_root, parse every WAV filename, attach .db descriptors.
    Returns list of TinySolEntry.
    """
    entries = []
    n_junk  = 0
    n_nometa = 0
    n_nodesc = 0

    for dirpath, _, filenames in os.walk(corpus_root):
        for fname in filenames:
            # Skip junk
            ext = os.path.splitext(fname)[1].lower()
            if ext != ".wav":
                n_junk += 1
                continue

            abs_path = os.path.join(dirpath, fname)
            meta = parse_filename(fname)
            if meta is None:
                n_nometa += 1
                continue

            # TinySOL's official directory layout contains the authoritative
            # family name.  Prefer it over abbreviation heuristics so Accordion
            # (Keyboards), Alto Saxophone, and future corpus variants are covered.
            path_family = _family_from_path(abs_path)
            if path_family is not None:
                meta["family"] = path_family

            entry = TinySolEntry(abs_path, meta)
            entry.populate_descriptors(db_store)

            if not entry.descriptors:
                n_nodesc += 1

            entries.append(entry)

    # Diagnostic: report how many entries got descriptors and sample a path
    n_with_desc = sum(1 for e in entries if e.descriptors)
    print("  [IDX] Corpus entries: %d  (junk=%d, no-meta=%d, no-desc=%d, with-desc=%d)"
          % (len(entries), n_junk, n_nometa, n_nodesc, n_with_desc))

    if entries and n_with_desc == 0:
        # Help diagnose path mismatch: show a corpus path vs a db sample path
        sample_corp = entries[0].abs_path if entries else "?"
        sample_db   = db_store._sample_path.get("mfcc", "?")
        print("  [IDX] DIAG: corpus path sample : %s" % sample_corp, file=sys.stderr)
        print("  [IDX] DIAG: db path sample     : %s" % sample_db,   file=sys.stderr)
        print("  [IDX] DIAG: corpus stem sample : %s" % _path_stem(sample_corp), file=sys.stderr)
        print("  [IDX] DIAG: db stem sample     : %s" % _path_stem(sample_db),   file=sys.stderr)
    elif entries and n_with_desc > 0:
        pct = 100.0 * n_with_desc / len(entries)
        print("  [IDX] Descriptor coverage: %.1f%%" % pct)

    return entries


# ─────────────────────────────────────────────────────────────────────────────
# Stage 5 — Target audio analysis
# ─────────────────────────────────────────────────────────────────────────────

def _analysis_mono(audio):
    """Return a real source channel for analysis, avoiding phase cancellation.

    Returns (mono, channel_index_0_based).  Mono input reports channel 0.
    """
    import numpy as np
    x = np.asarray(audio)
    if x.ndim == 1:
        return x, 0
    if x.shape[1] == 1:
        return x[:, 0], 0
    rms = np.sqrt(np.mean(x.astype(np.float64) ** 2, axis=0))
    ch = int(np.argmax(rms))
    return x[:, ch], ch


def analyse_target(audio_path):
    """
    Compute the same descriptors that are stored in the .db files
    so we can compare them to corpus entries.

    Also detects F0 (median across frames) and the strongest partials
    for pitch-aware retrieval in whole-file mode.

    Returns (descriptors_dict, sr, n_samples, pitch_info)
    where pitch_info = {"f0_hz": float|None, "midi": int|None,
                        "partials_hz": list, "n_voiced": int, "n_frames": int}
    """
    import numpy as np
    import soundfile as sf

    audio, sr = sf.read(audio_path, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    audio, analysis_ch = _analysis_mono(audio)

    # Work in float64 for precision
    x = audio.astype(np.float64)

    n_fft  = 4096
    hop    = 2048

    frames = _stft_frames(x, n_fft, hop)   # (n_bins, n_frames)
    power  = np.abs(frames) ** 2           # power spectrum

    result = {}

    # ── MFCC (20 coefficients, averaged over frames) ──────────────────
    mfcc_vec = _compute_mfcc(power, sr, n_fft, n_mels=20, n_mfcc=20)
    result["mfcc"] = mfcc_vec.astype(np.float32)

    # ── Spectral envelope (specenv): mean power per linear band ─────
    specenv_vec = _compute_specenv(power, sr, n_fft, n_bands=24)
    result["specenv"] = specenv_vec.astype(np.float32)

    # ── Moments (spectral centroid, spread, skewness, kurtosis) ──────
    moments_vec = _compute_moments(power, sr, n_fft)
    result["moments"] = moments_vec.astype(np.float32)

    # ── Spectral peaks (specpeaks): log-amplitude of N strongest peaks ──
    # Matches the .db specpeaks descriptor for corpus entries.
    # Fixed-length vector: log-power at the N strongest frequency peaks.
    # Cosine distance then measures how similar the peak structures are.
    specpeaks_vec = _compute_specpeaks(power, sr, n_fft, n_peaks=16)
    result["specpeaks"] = specpeaks_vec.astype(np.float32)

    # ── Pitch detection (median F0 across analysis frames) ───────────
    # Use overlapping frames for robust F0 estimation
    pitch_frame_size = min(4096, len(x))
    pitch_hop = max(1, pitch_frame_size // 2)
    f0_values = []
    n_pitch_frames = max(1, (len(x) - pitch_frame_size) // pitch_hop + 1)

    for i in range(n_pitch_frames):
        s = i * pitch_hop
        seg = x[s:s + pitch_frame_size]
        if len(seg) < pitch_frame_size:
            seg = np.pad(seg, (0, pitch_frame_size - len(seg)))
        f0 = _detect_f0(seg, sr)
        if f0 is not None:
            f0_values.append(f0)

    n_voiced = len(f0_values)

    if n_voiced > 0:
        median_f0 = float(np.median(f0_values))
        median_midi = _hz_to_midi(median_f0)
    else:
        median_f0 = None
        median_midi = None

    # ── Partial detection (strongest peaks in mean power spectrum) ────
    partials_hz  = []
    partials_amp = []
    if median_f0 is not None:
        mean_power = power.mean(axis=1)
        freqs = np.linspace(0, sr / 2.0, len(mean_power))
        noise_floor = float(np.mean(mean_power)) * 0.1
        # Search for peaks at harmonic multiples of F0
        for h in range(1, 17):  # up to 16th harmonic
            fh = h * median_f0
            if fh >= sr / 2.0 - 100:
                break
            # Find the strongest bin within ±15% of expected harmonic
            lo_hz = fh * 0.85
            hi_hz = fh * 1.15
            lo_bin = max(0, int(lo_hz / (sr / 2.0) * (len(mean_power) - 1)))
            hi_bin = min(len(mean_power) - 1,
                         int(hi_hz / (sr / 2.0) * (len(mean_power) - 1)))
            if lo_bin >= hi_bin:
                continue
            region = mean_power[lo_bin:hi_bin + 1]
            peak_bin = lo_bin + int(np.argmax(region))
            peak_power = float(mean_power[peak_bin])
            # Only count if peak is above noise floor
            if peak_power > noise_floor:
                actual_hz = float(freqs[peak_bin])
                partials_hz.append(actual_hz)
                partials_amp.append(peak_power)

    # Normalise partial amplitudes to sum to 1.0
    if partials_amp:
        total_amp = sum(partials_amp)
        if total_amp > 0:
            partials_amp = [a / total_amp for a in partials_amp]

    # If no pitch was detected (speech, noise, etc.) keep partials empty
    # so callers can detect the unvoiced case cleanly.  An empty list with a
    # non-zero harmonic weight would score 1.0 (worst) instead of the neutral
    # 0.5 that None triggers in harmonic_contribution_distance().
    if n_voiced == 0:
        partials_hz  = []
        partials_amp = []

    pitch_info = {
        "f0_hz":        median_f0,
        "midi":         median_midi,
        "partials_hz":  partials_hz,
        "partials_amp": partials_amp,
        "n_voiced":     n_voiced,
        "n_frames":     n_pitch_frames,
        "analysis_channel": analysis_ch + 1,
        "target_rms": float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0,
    }

    return result, sr, len(audio), pitch_info


# ── Low-level DSP helpers ────────────────────────────────────────────────────

def _stft_frames(x, n_fft, hop):
    import numpy as np
    window  = np.hanning(n_fft)
    n_bins  = n_fft // 2 + 1
    n_frames = max(1, (len(x) - n_fft) // hop + 1)
    out = np.zeros((n_bins, n_frames), dtype=np.complex128)
    for i in range(n_frames):
        s = i * hop
        seg = x[s:s + n_fft]
        if len(seg) < n_fft:
            seg = np.pad(seg, (0, n_fft - len(seg)))
        out[:, i] = np.fft.rfft(seg * window)
    return out


def _compute_mfcc(power, sr, n_fft, n_mels=20, n_mfcc=20):
    """
    Compute MFCC from a power spectrogram using a triangular mel filterbank
    and DCT-II.

    v1.7: filterbank construction is fully vectorised via numpy broadcasting
    instead of two nested Python loops.  DCT-II is a single matmul.  Output
    is mathematically identical to v1.6 (same triangle shape, same DCT
    coefficients) but ~50x faster on typical n_fft=4096, n_mels=20 inputs.
    Frame-based mode benefits most because this is called per frame.
    """
    import numpy as np

    n_bins = power.shape[0]

    # Mel scale conversions
    def hz2mel(h):  return 2595.0 * np.log10(1.0 + h / 700.0)
    def mel2hz(m):  return 700.0 * (10.0 ** (m / 2595.0) - 1.0)

    low_mel  = hz2mel(20.0)
    high_mel = hz2mel(sr / 2.0)
    mel_pts  = np.linspace(low_mel, high_mel, n_mels + 2)
    hz_pts   = mel2hz(mel_pts)
    bin_pts  = np.clip(
        np.floor((n_fft + 1) * hz_pts / sr).astype(int), 0, n_bins - 1
    )

    # Vectorised triangular filterbank construction.
    # bin_pts has length n_mels+2: [edge_0, center_1, edge_1, center_2, ...]
    # Filter m uses (bin_pts[m-1], bin_pts[m], bin_pts[m+1]) as
    # (left, center, right).
    fl = bin_pts[:-2][:, None].astype(np.float64)   # (n_mels, 1)
    fc = bin_pts[1:-1][:, None].astype(np.float64)  # (n_mels, 1)
    fr = bin_pts[2:][:, None].astype(np.float64)    # (n_mels, 1)
    k  = np.arange(n_bins, dtype=np.float64)        # (n_bins,)

    # Rising slope (k - fl) / (fc - fl) for fl <= k <= fc;
    # falling slope (fr - k) / (fr - fc) for fc <= k <= fr.
    # np.maximum(1, ...) guards against zero-width slopes (degenerate filters).
    rising  = (k - fl) / np.maximum(1.0, fc - fl)
    falling = (fr - k) / np.maximum(1.0, fr - fc)

    # Build triangle: rising in [fl, fc], falling in (fc, fr], zero outside.
    fb = np.where(
        (k >= fl) & (k <= fc), rising,
        np.where((k > fc) & (k <= fr), falling, 0.0)
    )
    # Zero out filters where the slope condition fails (fc <= fl or fr <= fc)
    valid = (fc > fl) & (fr > fc)
    fb = np.where(valid, fb, 0.0)

    # Average power across frames then apply filterbank
    mean_power = power.mean(axis=1)
    mel_energy = np.log(fb.dot(mean_power) + 1e-10)

    # DCT-II: single matrix multiply instead of n_mfcc Python iterations.
    # dct_matrix[i, m] = cos(pi * i / n_mels * (m + 0.5))
    i_arr = np.arange(n_mfcc, dtype=np.float64)[:, None]   # (n_mfcc, 1)
    m_arr = np.arange(n_mels, dtype=np.float64) + 0.5      # (n_mels,)
    dct_matrix = np.cos(math.pi * i_arr / n_mels * m_arr)  # (n_mfcc, n_mels)
    mfcc = dct_matrix @ mel_energy
    return mfcc


def _compute_specenv(power, sr, n_fft, n_bands=24):
    """
    Spectral envelope: log-energy in n_bands linearly-spaced frequency bands.
    """
    import numpy as np
    n_bins = power.shape[0]
    mean_power = power.mean(axis=1)
    band_size = max(1, n_bins // n_bands)
    env = np.zeros(n_bands)
    for b in range(n_bands):
        lo = b * band_size
        hi = min(lo + band_size, n_bins)
        env[b] = np.log(np.mean(mean_power[lo:hi]) + 1e-10)
    return env


def _compute_moments(power, sr, n_fft):
    """
    4 spectral moments: centroid, spread, skewness, kurtosis.
    """
    import numpy as np
    n_bins = power.shape[0]
    freqs  = np.linspace(0, sr / 2.0, n_bins)
    mean_power = power.mean(axis=1) + 1e-10
    total  = mean_power.sum()
    pmf    = mean_power / total

    c1 = np.dot(freqs, pmf)                     # centroid
    c2 = np.sqrt(np.dot((freqs - c1) ** 2, pmf))  # spread
    if c2 > 0:
        c3 = np.dot(((freqs - c1) / c2) ** 3, pmf)  # skewness
        c4 = np.dot(((freqs - c1) / c2) ** 4, pmf)  # kurtosis
    else:
        c3 = c4 = 0.0
    return np.array([c1, c2, c3, c4], dtype=np.float64)


def _compute_specpeaks(power, sr, n_fft, n_peaks=16):
    """
    Spectral peaks descriptor: find the N strongest peaks in the mean
    magnitude spectrum and return their log-amplitudes, sorted by
    frequency.

    The result is a fixed-length vector (n_peaks elements) comparable
    to .db specpeaks via cosine distance.  If fewer than n_peaks are
    found, remaining elements are set to the noise floor.

    Peak detection: simple local-maximum test (bin > both neighbours).
    """
    import numpy as np

    n_bins     = power.shape[0]
    mean_power = power.mean(axis=1)
    noise_floor = float(np.log(np.mean(mean_power) * 0.001 + 1e-10))

    # Find local maxima (skip DC bin 0 and Nyquist)
    peaks = []
    for b in range(1, n_bins - 1):
        if mean_power[b] > mean_power[b - 1] and mean_power[b] > mean_power[b + 1]:
            peaks.append((float(mean_power[b]), b))

    # Sort by amplitude (strongest first), take top N
    peaks.sort(reverse=True)
    top_peaks = peaks[:n_peaks]

    # Sort selected peaks by frequency (bin index) for consistent ordering
    top_peaks.sort(key=lambda p: p[1])

    # Build output vector: log-amplitude of each peak
    result = np.full(n_peaks, noise_floor, dtype=np.float64)
    for i, (amp, _bin) in enumerate(top_peaks):
        result[i] = np.log(amp + 1e-10)

    return result

def cosine_distance(a, b):
    """1 - cosine_similarity; returns value in [0, 2]."""
    import numpy as np
    denom = (np.linalg.norm(a) * np.linalg.norm(b))
    if denom < 1e-12:
        return 1.0
    return float(1.0 - np.dot(a, b) / denom)


def euclidean_distance_normalised(a, b):
    """Euclidean distance divided by dimension, so it's scale-independent."""
    import numpy as np
    d = a - b
    return float(np.sqrt(np.dot(d, d) / max(1, len(d))))


def hellinger_distance(a, b):
    """
    Hellinger distance for spectral power distributions.

    Designed for specenv vectors, which are stored as log-energy per band.
    We recover linear power via exp(), normalise both vectors to probability
    simplices, then compute the Hellinger metric:

        H(p, q) = 1/sqrt(2) * sqrt( sum( (sqrt(p_i) - sqrt(q_i))^2 ) )

    This is the correct distance when comparing spectral shapes as power
    distributions.  Cosine distance on log-energy vectors measures the angle
    between log-vectors, which is insensitive to absolute spectral level
    differences that Hellinger captures naturally.

    Returns value in [0, 1]:  0 = identical distributions, 1 = disjoint.
    """
    import numpy as np
    # Recover linear power from log-energy (clamp to avoid overflow)
    pa = np.exp(np.clip(a.astype(np.float64), -50.0, 50.0))
    pb = np.exp(np.clip(b.astype(np.float64), -50.0, 50.0))
    # Normalise to probability distributions
    sa = float(pa.sum())
    sb = float(pb.sum())
    pa = pa / (sa if sa > 1e-30 else 1.0)
    pb = pb / (sb if sb > 1e-30 else 1.0)
    return float(np.sqrt(0.5 * np.sum((np.sqrt(pa) - np.sqrt(pb)) ** 2)))


def kl_distance_symmetric(a, b):
    """
    Symmetric (Jensen-Shannon) KL divergence for spectral distributions.

    Like hellinger_distance(), works on log-energy vectors (recovers linear
    power via exp before computing KL).  JSD = KL(a||m) + KL(b||m) where
    m = (a+b)/2.  Normalised to [0, 1] by dividing by log(2).

    Available as an alternative to Hellinger for specenv or specpeaks.
    Select via descriptor_weights by setting the feature prefix to "kl"
    (advanced use — requires matching .db vector generation).
    """
    import numpy as np
    pa = np.exp(np.clip(a.astype(np.float64), -50.0, 50.0))
    pb = np.exp(np.clip(b.astype(np.float64), -50.0, 50.0))
    sa, sb = float(pa.sum()), float(pb.sum())
    pa = pa / (sa if sa > 1e-30 else 1.0)
    pb = pb / (sb if sb > 1e-30 else 1.0)
    m   = 0.5 * (pa + pb)
    eps = 1e-30
    kl_a = float(np.sum(np.where(pa > eps, pa * np.log(pa / np.maximum(m, eps)), 0.0)))
    kl_b = float(np.sum(np.where(pb > eps, pb * np.log(pb / np.maximum(m, eps)), 0.0)))
    js   = 0.5 * (kl_a + kl_b)
    return float(min(1.0, js / math.log(2.0)))


def specenv_distance(a, b):
    """
    Distance function for specenv descriptors.

    Default: cosine distance on log-energy vectors (same as v1.2).

    Why not Hellinger by default:
      Hellinger operates on the exp()-recovered linear power distributions.
      For typical cross-timbre comparisons (target vs orchestra corpus) this
      produces values 10–100× larger than cosine on the same vectors, because
      Hellinger is sensitive to absolute distribution shape while cosine on
      log-energy measures the angle between log-vectors and is naturally
      insensitive to absolute level differences.

      Switching to Hellinger without recalibrating silence_threshold and all
      descriptor weights produces spurious high scores that trigger the silence
      gate.  Hellinger is available via hellinger_distance() for future use
      once the full weight set is re-tuned against it.

    To use Hellinger experimentally, replace the body with:
        return hellinger_distance(a, b)
    and set silence_threshold=1.0 until scores are understood.
    """
    return cosine_distance(a, b)


def moments_distance(a, b):
    """
    Distance metric for spectral moments [centroid, spread, skewness, kurtosis].

    Problem:  centroid and spread are in Hz (range 100–10000), while skewness
    and kurtosis are dimensionless (range -2 to +10).  Euclidean distance is
    dominated by centroid; cosine distance ignores magnitude entirely (treats
    [1000, 500, 0.5, 3] and [2000, 1000, 0.5, 3] as identical).

    Fix:  log-transform Hz-valued dimensions (indices 0 and 1) to compress
    the scale so all four dimensions have comparable ranges, then apply
    normalised Euclidean distance.
    """
    import numpy as np
    a_norm = np.array([np.log(max(1.0, a[0])), np.log(max(1.0, a[1])),
                       a[2] if len(a) > 2 else 0.0,
                       a[3] if len(a) > 3 else 0.0])
    b_norm = np.array([np.log(max(1.0, b[0])), np.log(max(1.0, b[1])),
                       b[2] if len(b) > 2 else 0.0,
                       b[3] if len(b) > 3 else 0.0])
    return euclidean_distance_normalised(a_norm, b_norm)


def _pad_or_trim(a, b):
    """Make two vectors the same length (pad shorter with zeros)."""
    import numpy as np
    la, lb = len(a), len(b)
    if la == lb:
        return a, b
    if la < lb:
        return np.pad(a, (0, lb - la)), b
    return a, np.pad(b, (0, la - lb))


def harmonic_contribution_distance(target_partials_hz, target_partials_amp,
                                   corpus_midi, n_harmonics=16,
                                   tolerance=0.03):
    """
    Orchidea-inspired distance: how well does a corpus note's harmonic
    series cover the target's detected partials?

    Unlike MFCC/specenv (static descriptor comparison), this measures
    a structural relationship — pitch matching emerges naturally from
    partial overlap without requiring F0 detection or pitch gates.

    Returns 0.0 = perfect coverage, 1.0 = zero overlap, 0.5 = neutral.

    Examples (target F0 = 220 Hz, partials at 220, 440, 660, 880 Hz):
      corpus A3  (220 Hz): harmonics at 220, 440, 660, 880 → ~0.0
      corpus A4  (440 Hz): harmonics at 440, 880, 1320     → ~0.5
      corpus C4  (262 Hz): harmonics at 262, 524, 786       → ~0.9
      corpus F#2 (93 Hz):  nothing aligns                   → ~1.0
    """
    if not target_partials_hz or corpus_midi is None:
        return 0.5   # neutral when no pitch info

    import math
    corpus_f0 = 440.0 * 2.0 ** ((corpus_midi - 69) / 12.0)
    corpus_harmonics = [corpus_f0 * h for h in range(1, n_harmonics + 1)]

    covered = 0.0
    total   = 0.0

    for tp_hz, tp_amp in zip(target_partials_hz, target_partials_amp):
        total += tp_amp
        for ch in corpus_harmonics:
            if abs(ch - tp_hz) / max(1.0, tp_hz) < tolerance:
                covered += tp_amp
                break

    if total < 1e-12:
        return 0.5

    return 1.0 - (covered / total)


def score_entry(entry, target_descs, weights, preferred_dyns, min_midi, max_midi,
                target_midi=None, target_partials=None, speech_mode=False):
    """
    Compute a weighted distance score for one corpus entry vs target.
    Lower = better match.

    target_partials: list of (hz, amp) pairs for harmonic contribution scoring.
                     When provided, the "harmonic" weight in weights dict
                     controls how much partial overlap matters.
    target_midi: legacy pitch proximity penalty (still applied if no
                 target_partials are available).

    Returns (score, detail_dict) or (None, {}) if not computable.
    """
    import numpy as np

    if not entry.descriptors:
        return None, {}

    dist_parts = {}
    total_w    = 0.0
    total_d    = 0.0

    for db_name, w in weights.items():
        if w <= 0:
            continue

        # Harmonic contribution is computed differently — not from .db descriptors
        if db_name == "harmonic":
            if target_partials is not None:
                tp_hz  = [p[0] for p in target_partials]
                tp_amp = [p[1] for p in target_partials]
                d = harmonic_contribution_distance(tp_hz, tp_amp, entry.midi)
                dist_parts["harmonic"] = d
                total_w += w
                total_d += w * d
            continue

        t_vec = target_descs.get(db_name)
        c_vec = entry.descriptors.get(db_name)
        if t_vec is None or c_vec is None:
            continue
        tv, cv = _pad_or_trim(t_vec.astype(np.float64),
                              c_vec.astype(np.float64))
        if db_name == "moments":
            d = moments_distance(tv, cv)
        elif db_name == "specenv":
            d = specenv_distance(tv, cv)
        else:
            d = cosine_distance(tv, cv)
        dist_parts[db_name] = d
        total_w += w
        total_d += w * d

    if total_w < 1e-9:
        return None, {}

    base_score = total_d / total_w

    # ── Soft penalties ────────────────────────────────────────────
    penalty = 0.0

    # NOTE: MIDI range is now a hard filter enforced in build_candidate_domain()
    # before scoring.  No soft MIDI-range penalty here — entries outside
    # [min_midi, max_midi] are excluded entirely, not penalised.

    # Dynamic preference penalty (soft — keeps preferred dynamics closer to top)
    if preferred_dyns:
        if entry.dyn not in preferred_dyns:
            dyn_val   = DYN_ORDER.get(entry.dyn, 4)
            best_dist = min(abs(dyn_val - DYN_ORDER.get(pd, 4))
                            for pd in preferred_dyns)
            penalty  += 0.08 * best_dist

    # Legacy pitch proximity penalty (only when harmonic weight is absent
    # or zero, and target_midi is available)
    harmonic_w = weights.get("harmonic", 0)
    if target_midi is not None and harmonic_w <= 0 and not speech_mode:
        pitch_dist = abs(entry.midi - target_midi)
        penalty += 0.05 * pitch_dist
        dist_parts["_pitch_dist_st"] = pitch_dist

    final_score = base_score + penalty
    return final_score, dist_parts


def build_candidate_domain(entries, params):
    """
    Orchidea-inspired candidate domain builder.

    Enforces ALL hard constraints before any scoring takes place — mirroring
    Production::computeVariableDomains() in orchids-master.  The key design
    principle from that codebase: legal candidate sets are computed ONCE and
    reused by the search engine; scoring never needs to filter or penalise for
    constraint violations because violating entries were never added.

    Hard constraints enforced here (entries failing any are excluded entirely):
      - Instrument family membership (allowed_families)
      - Specific instrument filter  (allowed_instruments)
      - MIDI pitch range            [min_midi, max_midi]
      - Non-empty descriptor set    (entry has at least one .db vector)

    Soft preferences (dynamics, pitch proximity to target) are NOT handled here
    — they remain as scoring penalties in score_entry(), because they depend on
    the target audio and can legitimately be traded off against timbral match.

    Returns: filtered list of TinySolEntry (the legal domain).
    """
    allowed_fam  = set(params["_allowed_families"])
    allowed_inst = {_norm_label(x) for x in params["_allowed_instruments"] if x}
    min_midi     = params["_min_midi"]
    max_midi     = params["_max_midi"]

    domain = []
    n_fam_reject  = 0
    n_inst_reject = 0
    n_midi_reject = 0
    n_nodesc      = 0

    for e in entries:
        if allowed_fam and e.family not in allowed_fam:
            n_fam_reject += 1
            continue
        if allowed_inst:
            entry_labels = {_norm_label(e.inst), _norm_label(e.instrument_name)}
            if not (allowed_inst & entry_labels):
                n_inst_reject += 1
                continue
        if e.midi < min_midi or e.midi > max_midi:
            n_midi_reject += 1
            continue
        if not e.descriptors:
            n_nodesc += 1
            continue
        domain.append(e)

    print("  [DOMAIN] %d legal candidates  (rejected: fam=%d inst=%d midi=%d nodesc=%d)"
          % (len(domain), n_fam_reject, n_inst_reject, n_midi_reject, n_nodesc))
    return domain


def retrieve(entries, target_descs, params, target_midi=None,
             target_partials=None):
    """
    Build the legal candidate domain, deduplicate, then score every entry.

    Calls build_candidate_domain() first so that ALL hard constraint filtering
    (family, instrument, MIDI range) happens in one place before any scoring.
    Soft preferences (dynamics, legacy pitch penalty) remain in score_entry().

    target_midi:     detected MIDI pitch of the target (whole-file mode).
    target_partials: list of (hz, amp) tuples for harmonic contribution.
    Returns list of (score, entry, detail) sorted ascending.
    """
    # ── Stage A: Hard-constraint filtering (Orchidea domain build) ───────
    domain = build_candidate_domain(entries, params)

    # ── Stage B: Score every legal variant first ───────────────────────────
    # TinySOL contains alternate takes/string positions whose timbres differ.
    # Choosing a variant by filename/coverage before scoring can discard the
    # acoustically closest take.  Score first, then keep the best variant per
    # (instrument, note, dynamic) key to preserve the prior diversity policy.
    pref_dyns = set(params["_preferred_dynamics"])
    min_midi  = params["_min_midi"]
    max_midi  = params["_max_midi"]
    weights   = params["_descriptor_weights"]

    all_scored = []
    for entry in domain:
        score, detail = score_entry(entry, target_descs, weights,
                                    pref_dyns, min_midi, max_midi,
                                    target_midi=target_midi,
                                    target_partials=target_partials,
                                    speech_mode=params["_speech_mode"])
        if score is None:
            continue
        all_scored.append((score, entry, detail))

    best_by_key = {}
    for item in all_scored:
        score, entry, _detail = item
        key = (entry.inst, entry.note, entry.dyn)
        prev = best_by_key.get(key)
        if prev is None or score < prev[0]:
            best_by_key[key] = item

    scored = sorted(best_by_key.values(), key=lambda t: t[0])
    return scored


# ─────────────────────────────────────────────────────────────────────────────
# Stage 7 — Small-mixture blending
# ─────────────────────────────────────────────────────────────────────────────

def load_audio(path, target_sr=None):
    """Load WAV as mono float32, using the strongest real channel.

    TinySOL itself is mono, but this also keeps target/custom-corpus stereo
    material from cancelling when L and R are out of phase.
    """
    import numpy as np
    import soundfile as sf

    audio, sr = sf.read(path, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    audio, _ = _analysis_mono(audio)

    if target_sr is not None and sr != target_sr:
        from scipy.signal import resample_poly
        from math import gcd
        g = gcd(int(target_sr), int(sr))
        up = int(target_sr) // g
        down = int(sr) // g
        audio = resample_poly(audio, up, down).astype(np.float32)
        sr = int(target_sr)

    return np.asarray(audio, dtype=np.float32), int(sr)


def blend_samples(entries_and_scores, target_len_samples, sr, render_mode, gain,
                  stereo=False):
    """
    Render audio output from selected entries.
    render_mode: 'best'  — single best match
                 'blend' — top-3, rank-weighted (1/rank); best match dominates
                 'top2'  — top-2, equal weight
                 'top3'  — top-3, equal weight
                 'top4'  — top-4, equal weight
    stereo: if True, distribute layers across the stereo field using
            constant-power panning (same formula as
            Distribute_sounds_in_stereo_field.praat).
            Single-layer output is centred (pan = 0).
    """
    import numpy as np

    if render_mode == "best":
        n = 1
    elif render_mode == "blend":
        n = 3
    elif render_mode == "top2":
        n = 2
    elif render_mode == "top3":
        n = 3
    elif render_mode == "top4":
        n = 4
    else:
        n = 1

    n = min(n, len(entries_and_scores))
    chosen = entries_and_scores[:n]

    # 'blend' uses 1/rank weights; top2/top3/top4 are equal mixes
    if render_mode == "blend":
        raw_weights = [1.0 / (i + 1) for i in range(n)]
    else:
        raw_weights = [1.0] * n

    audios = []
    weights_used = []
    for idx, (_score, entry, _detail) in enumerate(chosen):
        if not os.path.isfile(entry.abs_path):
            print("  [RENDER] WARNING: file not found: %s" % entry.abs_path,
                  file=sys.stderr)
            continue
        try:
            aud, _ = load_audio(entry.abs_path, target_sr=sr)
            audios.append(aud)
            weights_used.append(raw_weights[idx])
        except Exception as exc:
            print("  [RENDER] WARNING: could not load %s: %s"
                  % (entry.abs_path, exc), file=sys.stderr)

    if not audios:
        if stereo:
            return np.zeros((max(1, target_len_samples), 2), dtype=np.float32)
        return np.zeros(max(1, target_len_samples), dtype=np.float32)

    # Re-normalise in case some files failed to load
    total_w = sum(weights_used) or 1.0

    # Determine output length = max of target and longest sample
    out_len = max(target_len_samples, max(len(a) for a in audios))

    if stereo:
        # ── Stereo path: constant-power panning ─────────────────────────
        # Mirrors Distribute_sounds_in_stereo_field.praat:
        #   pan  = -1 + (2 * (i-1) / (N-1))   [ -1=full-left … +1=full-right ]
        #   L    = sqrt((1 - pan) / 2)
        #   R    = sqrt((1 + pan) / 2)
        # For a single layer pan=0 → L=R=sqrt(0.5) (centred).
        out = np.zeros((out_len, 2), dtype=np.float64)
        n_sounds = len(audios)

        for i, (aud, w) in enumerate(zip(audios, weights_used)):
            padded = np.zeros(out_len)
            padded[:len(aud)] = aud

            if n_sounds == 1:
                pan = 0.0
            else:
                pan = -1.0 + (2.0 * i / (n_sounds - 1))

            left_gain  = math.sqrt((1.0 - pan) / 2.0)
            right_gain = math.sqrt((1.0 + pan) / 2.0)

            print("  [STEREO] layer %d  pan=%+.2f  L=%.3f  R=%.3f  w=%.3f"
                  % (i + 1, pan, left_gain, right_gain, w / total_w))

            out[:, 0] += (w / total_w) * padded * left_gain
            out[:, 1] += (w / total_w) * padded * right_gain

        peak = np.max(np.abs(out))
        if peak > 1e-9:
            out = out * (gain / peak)
            if gain > 1.0:
                out = np.clip(out, -1.0, 1.0)

        return out.astype(np.float32)

    else:
        # ── Mono path ────────────────────────────────────────────────────
        out = np.zeros(out_len, dtype=np.float64)

        for aud, w in zip(audios, weights_used):
            padded = np.zeros(out_len)
            padded[:len(aud)] = aud
            out += (w / total_w) * padded

        peak = np.max(np.abs(out))
        if peak > 1e-9:
            out = out * (gain / peak)
            if gain > 1.0:
                out = np.clip(out, -1.0, 1.0)

        return out.astype(np.float32)



def _envelope_power_trace(audio):
    """Per-sample power trace without phase-cancelling channel fold-down."""
    import numpy as np
    x = np.asarray(audio, dtype=np.float64)
    if x.ndim == 1:
        return x * x
    return np.mean(x * x, axis=1)


def _macro_rms_envelope(audio, sr, smooth_ms=100.0):
    """Slow RMS envelope used for gesture transfer, one value per sample."""
    import numpy as np
    from scipy.ndimage import gaussian_filter1d
    p = _envelope_power_trace(audio)
    if p.size == 0:
        return np.zeros(0, dtype=np.float64)
    # Treat smooth_ms as approximate FWHM of the Gaussian smoother.
    sigma = max(1.0, (smooth_ms * 0.001 * sr) / 2.355)
    sm = gaussian_filter1d(p, sigma=sigma, mode="nearest")
    return np.sqrt(np.maximum(sm, 0.0))


def _norm_envelope(env):
    """Robust 0..1 envelope normalization; silence remains exactly zero."""
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
    """Transfer the target's *macro* RMS gesture to an already-rendered output.

    The target envelope is resampled on a normalized 0..1 time axis, so corpus
    samples may keep their natural duration.  No time stretch, pitch shift, or
    spectral processing is introduced.  amount=0 is an exact identity.

    Returns (audio, stats_dict).
    """
    import numpy as np
    x = np.asarray(output, dtype=np.float64)
    amount = float(np.clip(amount, 0.0, 1.0))
    if x.size == 0 or amount <= 0.0:
        return np.asarray(output).copy(), {
            "envelope_follow": amount,
            "envelope_corr_before": 0.0,
            "envelope_corr_after": 0.0,
        }

    target_env = _norm_envelope(_macro_rms_envelope(target_audio, sr, smooth_ms))
    out_env    = _norm_envelope(_macro_rms_envelope(x, sr, smooth_ms))
    n = x.shape[0]
    if len(target_env) == 0 or len(out_env) == 0:
        return np.asarray(output).copy(), {
            "envelope_follow": amount,
            "envelope_corr_before": 0.0,
            "envelope_corr_after": 0.0,
        }

    # Map target gesture to output duration rather than changing audio duration.
    if len(target_env) != n:
        target_env = np.interp(np.linspace(0.0, 1.0, n),
                               np.linspace(0.0, 1.0, len(target_env)),
                               target_env)
    if len(out_env) != n:
        out_env = np.interp(np.linspace(0.0, 1.0, n),
                            np.linspace(0.0, 1.0, len(out_env)), out_env)

    corr_before = _envelope_correlation(target_env, out_env)

    # Ratio follower with a denominator floor and bounded boost.  Deep target
    # silences can still attenuate all the way to zero; the ceiling only limits
    # upward gain where the rendered sample itself is weak.
    denom_floor = 10.0 ** (-30.0 / 20.0)
    boost_limit = 10.0 ** (boost_limit_db / 20.0)
    ratio = target_env / np.maximum(out_env, denom_floor)
    ratio = np.clip(ratio, 0.0, boost_limit)
    gain_curve = (1.0 - amount) + amount * ratio

    if x.ndim == 1:
        y = x * gain_curve
    else:
        y = x * gain_curve[:, None]

    # Preserve the pre-transfer global peak so Render_gain keeps its old meaning.
    peak_before = float(np.max(np.abs(x))) if x.size else 0.0
    peak_after  = float(np.max(np.abs(y))) if y.size else 0.0
    if peak_before > 1e-12 and peak_after > 1e-12:
        y *= peak_before / peak_after

    after_env = _norm_envelope(_macro_rms_envelope(y, sr, smooth_ms))
    corr_after = _envelope_correlation(target_env, after_env)
    stats = {
        "envelope_follow": amount,
        "envelope_corr_before": corr_before,
        "envelope_corr_after": corr_after,
    }
    return y.astype(np.float32), stats

# ─────────────────────────────────────────────────────────────────────────────
# Stage 8 — Write results text file
# ─────────────────────────────────────────────────────────────────────────────

def write_results(out_path, scored, params, target_sr, target_len,
                  render_mode, chosen_count, render_silence=False,
                  silence_reason="", envelope_stats=None):

    """Write a human-readable + Praat-parseable results file."""

    n_results = min(params["_n_results"], len(scored))

    # Use the OS default line separator so Praat's newline$ matches on Windows.
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("=== TinySOL Retrieval Results ===\n")
        f.write("render_mode=%s\n"   % render_mode)
        f.write("chosen_count=%d\n"  % chosen_count)
        f.write("target_sr=%d\n"     % target_sr)
        f.write("target_len=%.3f\n"  % (target_len / max(1, target_sr)))
        f.write("n_candidates=%d\n"  % len(scored))
        f.write("n_results=%d\n"     % n_results)
        f.write("silence_rendered=%d\n" % (1 if render_silence else 0))
        f.write("silence_reason=%s\n" % (silence_reason if render_silence else ""))
        if envelope_stats is not None:
            f.write("envelope_follow=%.3f\n" % envelope_stats.get("envelope_follow", 0.0))
            f.write("envelope_corr_before=%.4f\n" % envelope_stats.get("envelope_corr_before", 0.0))
            f.write("envelope_corr_after=%.4f\n" % envelope_stats.get("envelope_corr_after", 0.0))
        f.write("\n")
        f.write("rank,score,family,instrument,note,midi,dynamic,variant,"
                "technique,abs_path\n")
        for rank, (score, entry, _detail) in enumerate(scored[:n_results], 1):
            f.write("%d,%.6f,%s,%s,%s,%d,%s,%s,%s,%s\n" % (
                rank,
                score,
                entry.family,
                entry.inst,
                entry.note,
                entry.midi,
                entry.dyn,
                entry.variant,
                entry.tech,
                entry.abs_path,
            ))
        f.write("\n")
        f.write("=== Descriptor Weights ===\n")
        for name, w in params["_descriptor_weights"].items():
            f.write("%s=%.3f\n" % (name, w))
        if render_silence:
            f.write("\n=== NOTE ===\n")
            if silence_reason == "silent_target":
                f.write("Output is silence: target RMS is effectively zero.\n")
            else:
                f.write("Output is silence: best score (%.4f) exceeded "
                        "silence_threshold (%.2f).\n"
                        % (scored[0][0] if scored else 0.0,
                           params["_silence_threshold"]))


# ─────────────────────────────────────────────────────────────────────────────
# Frame-based (concatenative) synthesis — Stages A–D
# ─────────────────────────────────────────────────────────────────────────────

def _detect_f0(frame, sr, min_hz=40.0, max_hz=3000.0, voiced_thresh=0.35):
    """Normalized-autocorrelation F0 detector for TinySOL-range material.

    The v1.7 detector normalized only by lag-0 energy and then preferred a
    second autocorrelation peak near 2x the lag.  A periodic tone has strong
    peaks at every integer period, so that rule systematically octave-divided
    clean tones.  Here each lag is normalized by the actual overlap energy,
    then the earliest strong periodic maximum is selected.
    """
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

    # FFT autocorrelation, then exact overlap-energy normalization per lag.
    nfft = 1 << int(math.ceil(math.log2(2 * n - 1)))
    X = np.fft.rfft(x, n=nfft)
    ac = np.fft.irfft(X * np.conj(X), n=nfft)[:n]

    sq = x * x
    cs = np.concatenate([[0.0], np.cumsum(sq)])
    lags = np.arange(min_lag, max_lag + 1)
    e_left  = cs[n - lags]
    e_right = cs[n] - cs[lags]
    denom = np.sqrt(np.maximum(e_left * e_right, 1e-24))
    corr = ac[lags] / denom

    if len(corr) < 3:
        return None
    local = np.where((corr[1:-1] >= corr[:-2]) &
                     (corr[1:-1] >  corr[2:]))[0] + 1
    if len(local) == 0:
        j = int(np.argmax(corr))
        if corr[j] < voiced_thresh:
            return None
    else:
        peak_vals = corr[local]
        strongest = float(np.max(peak_vals))
        candidates = local[peak_vals >= max(voiced_thresh, 0.88 * strongest)]
        if len(candidates) == 0:
            return None
        j = int(candidates[0])   # first strong period = highest valid fundamental

    lag = float(lags[j])
    # Parabolic interpolation around the correlation maximum for sub-sample lag.
    if 0 < j < len(corr) - 1:
        y0, y1, y2 = float(corr[j - 1]), float(corr[j]), float(corr[j + 1])
        den = y0 - 2.0 * y1 + y2
        if abs(den) > 1e-12:
            delta = 0.5 * (y0 - y2) / den
            if abs(delta) <= 1.0:
                lag += delta

    return float(sr) / max(lag, 1e-12)


def _analyse_frame(frame, sr, n_fft):
    """
    Compute the same descriptor set as analyse_target() but for a single frame.
    Uses a smaller n_fft suited to the frame length so the vector dimensions
    (20 MFCCs, 24 specenv bands, 4 moments, 16 specpeaks) stay identical to
    the .db entries.
    """
    import numpy as np

    hop    = max(1, n_fft // 4)
    frames = _stft_frames(frame, n_fft, hop)
    power  = np.abs(frames) ** 2

    return {
        "mfcc":      _compute_mfcc(power, sr, n_fft, n_mels=20, n_mfcc=20).astype(np.float32),
        "specenv":   _compute_specenv(power, sr, n_fft, n_bands=24).astype(np.float32),
        "moments":   _compute_moments(power, sr, n_fft).astype(np.float32),
        "specpeaks": _compute_specpeaks(power, sr, n_fft, n_peaks=16).astype(np.float32),
    }


def analyse_frames(audio_path, frame_size_ms, hop_size_ms):
    """
    Slice target audio into overlapping frames and compute per-frame F0 + RMS.

    F0 contour is median-smoothed (5-frame window) to eliminate
    voiced/unvoiced jitter that causes erratic pitch-gate switching.
    """
    import numpy as np
    import soundfile as sf

    audio, sr = sf.read(audio_path, always_2d=False)
    audio = np.asarray(audio, dtype=np.float32)
    audio, analysis_ch = _analysis_mono(audio)
    x = audio.astype(np.float64)

    frame_size = max(64, int(round(frame_size_ms * sr / 1000.0)))
    hop_size   = max(1,  int(round(hop_size_ms   * sr / 1000.0)))

    n_samples   = len(x)
    frames_info = []
    idx         = 0
    raw_f0      = []

    # Pass 1: detect raw F0 per frame
    while True:
        start = idx * hop_size
        if start >= n_samples:
            break
        end   = start + frame_size
        frame = x[start:end]
        if len(frame) < frame_size:
            frame = np.pad(frame, (0, frame_size - len(frame)))

        rms   = float(np.sqrt(np.mean(frame ** 2)))
        f0_hz = _detect_f0(frame, sr)

        frames_info.append({
            "idx":    idx,
            "time_s": start / sr,
            "start":  start,
            "rms":    rms,
            "f0_hz":  f0_hz,
            "midi":   None,   # filled after smoothing
            "silent": False,
            "analysis_channel": analysis_ch + 1,
        })
        raw_f0.append(f0_hz)
        idx += 1

    # Pass 2: silence gate + median smoothing of the F0 contour.
    # A voiced MAJORITY is required in the local window; one stray pitch
    # detection no longer propagates into neighbouring unvoiced frames.
    max_rms = max([fi["rms"] for fi in frames_info] + [0.0])
    silence_floor = max(1e-10, max_rms * (10.0 ** (-70.0 / 20.0)))
    for i, fi in enumerate(frames_info):
        fi["silent"] = fi["rms"] <= silence_floor
        if fi["silent"]:
            raw_f0[i] = None

    smooth_radius = 2   # 5-frame median window
    for i in range(len(frames_info)):
        lo = max(0, i - smooth_radius)
        hi = min(len(raw_f0), i + smooth_radius + 1)
        window_vals = raw_f0[lo:hi]
        neighbourhood = [f for f in window_vals if f is not None]
        majority = (len(window_vals) // 2) + 1
        if (not frames_info[i]["silent"] and
                len(neighbourhood) >= majority):
            smoothed_f0 = float(np.median(neighbourhood))
            frames_info[i]["f0_hz"] = smoothed_f0
            frames_info[i]["midi"]  = _hz_to_midi(smoothed_f0)
        else:
            frames_info[i]["f0_hz"] = None
            frames_info[i]["midi"]  = None

    return frames_info, sr, n_samples, frame_size, hop_size


def retrieve_frame(domain, frame_info, params, whole_file_descs,
                   last_voiced_midi=None, prefer_path=None,
                   frame_audio=None, frame_sr=None, frame_n_fft=2048):
    """
    Find the best-matching corpus entry for a single analysis frame.

    `domain` is the pre-built legal candidate set returned by
    build_candidate_domain() — all hard constraints (family, instrument, MIDI
    range) have already been applied.

    Timbral descriptors: when `frame_audio` is provided, per-frame descriptors
    are computed from that audio slice (via _analyse_frame) and used for
    MFCC/specenv/moments scoring.  This allows the retrieval to follow
    timbre changes across the target — e.g. bright vs dark vowels in speech,
    or dynamic swells in a melody.  When frame_audio is None, the whole-file
    descriptors are used as a fallback (original behaviour).

    Harmonic contribution: if the frame has a detected F0, its harmonic series
    is synthesised and passed to harmonic_contribution_distance() to measure
    partial overlap with each corpus entry's pitch.

    Pitch gate: always uses the user-supplied pitch_tolerance (honoured
    regardless of harmonic weight).  Previously the gate was hardcoded to
    ±12 st whenever harmonic weight > 0, which caused the UI control to be
    silently ignored.

    If prefer_path is given, only score that specific entry
    (used for persistence checking).
    """
    import numpy as np

    weights       = params["_descriptor_weights"]
    pref_dyns     = set(params["_preferred_dynamics"])
    min_midi      = params["_min_midi"]
    max_midi      = params["_max_midi"]
    pitch_tol     = params["_pitch_tolerance"]

    frame_midi    = frame_info["midi"]
    frame_f0      = frame_info["f0_hz"]

    if frame_info.get("silent", False):
        return None

    # ── Per-frame timbral descriptors ─────────────────────────────────────
    # Compute from the actual audio slice so scores vary frame-to-frame.
    # Fall back to whole-file descriptors if audio is not supplied.
    if frame_audio is not None and len(frame_audio) >= 64:
        try:
            frame_descs = _analyse_frame(frame_audio, frame_sr, frame_n_fft)
        except Exception:
            frame_descs = whole_file_descs   # safe fallback
    else:
        frame_descs = whole_file_descs

    # ── Per-frame harmonic partials ───────────────────────────────────────
    frame_partials = None
    if frame_f0 is not None and frame_f0 > 20:
        n_harm = 12
        frame_partials = []
        for h in range(1, n_harm + 1):
            fh = frame_f0 * h
            if fh >= 0.48 * frame_sr:
                break
            frame_partials.append((fh, 1.0 / h))

    # ── Pitch gate — always honour user pitch_tolerance ───────────────────
    # Previously this was overridden to ±12 st when harmonic weight > 0,
    # causing the UI control to be silently ignored.  Now pitch_tolerance
    # is always respected; harmonic_contribution_distance() handles fine
    # pitch discrimination within the gate window.
    if params["_speech_mode"]:
        gate_midi = None
        gate_tol  = pitch_tol
    elif frame_midi is not None:
        gate_midi = frame_midi
        gate_tol  = pitch_tol
    elif last_voiced_midi is not None:
        gate_midi = last_voiced_midi
        gate_tol  = pitch_tol * 2   # wider when extrapolating
    else:
        gate_midi = None
        gate_tol  = pitch_tol

    scored = []
    for entry in domain:
        if prefer_path is not None and entry.abs_path != prefer_path:
            continue

        # Per-frame pitch gate
        if gate_midi is not None:
            if abs(entry.midi - gate_midi) > gate_tol:
                continue

        score, detail = score_entry(entry, frame_descs, weights,
                                    pref_dyns, min_midi, max_midi,
                                    target_partials=frame_partials,
                                    speech_mode=params["_speech_mode"])
        if score is None:
            continue
        scored.append((score, entry, detail))

    if not scored:
        return None
    scored.sort(key=lambda t: t[0])
    # Threshold >= 2.0 is the explicit disabled state.
    thresh = params["_silence_threshold"]
    if thresh < 2.0 and scored[0][0] > thresh:
        return None
    return scored[0]


def render_frame_matches(frame_matches, frame_size, hop_size,
                         target_len, sr, gain,
                         stereo=False, pitch_pan=True):
    """
    Overlap-add synthesis from per-frame retrieved samples.

    For each frame:
      1. Load the matched corpus WAV (cached to avoid redundant disk reads).
      2. Extract a grain that ADVANCES through the corpus sample's sustain
         region, proportional to the frame's position in the target timeline.
         This prevents the "identical grain" repetition that causes rhythmic
         artifacts on sustained inputs.
      3. Scale the grain's RMS to match the target frame's RMS.
      4. Apply a Hann window and accumulate via overlap-add.

    Stereo + pitch_pan:
      Maps each grain's detected MIDI pitch linearly across the stereo field.
    """
    import numpy as np

    out_len = max(target_len,
                  (len(frame_matches) - 1) * hop_size + frame_size)

    out  = np.zeros((out_len, 2) if stereo else out_len, dtype=np.float64)
    norm = np.zeros(out_len, dtype=np.float64)
    hann = np.hanning(frame_size)

    # Pre-compute MIDI range for pitch-panning
    if stereo and pitch_pan:
        voiced = [fm["frame"]["midi"] for fm in frame_matches
                  if fm["match"] is not None and fm["frame"]["midi"] is not None]
        midi_lo = min(voiced) if voiced else 60
        midi_hi = max(voiced) if voiced else 60

    # Cache loaded corpus audio to avoid reloading the same file per frame
    audio_cache = {}

    # Total target duration for proportional position calculation
    total_target_dur = max(1, (len(frame_matches) - 1) * hop_size + frame_size)

    for fm in frame_matches:
        fi    = fm["frame"]
        match = fm["match"]
        start = fi["start"]
        end   = start + frame_size

        hann_seg = hann
        norm[start:end] += hann_seg

        if match is None:
            continue

        _score, entry, _detail = match

        # Load corpus audio (cached)
        if entry.abs_path not in audio_cache:
            try:
                corpus_audio, _ = load_audio(entry.abs_path, target_sr=sr)
                audio_cache[entry.abs_path] = corpus_audio
            except Exception:
                continue
        corpus_audio = audio_cache[entry.abs_path]

        # Determine sustain region (skip attack transient)
        sustain_start = max(int(0.20 * len(corpus_audio)),
                            int(0.050 * sr))
        sustain_end   = len(corpus_audio) - frame_size
        if sustain_end <= sustain_start:
            # Corpus sample too short for sustain region — use full sample
            sustain_start = 0
            sustain_end   = max(0, len(corpus_audio) - frame_size)

        sustain_len = max(1, sustain_end - sustain_start)

        # Advance read position linearly through the sustain region once,
        # proportional to frame position in the target timeline.
        # No wrap multiplier — a single smooth pass avoids hard splices
        # that cause audible clicks when the position jumps discontinuously.
        target_phase = float(start) / float(total_target_dur)
        read_offset  = sustain_start + int(target_phase * sustain_len)
        # Clamp so we never read past the end of the sustain region
        read_offset  = min(read_offset, sustain_start + sustain_len - 1)

        if read_offset + frame_size <= len(corpus_audio):
            grain = corpus_audio[read_offset:
                                 read_offset + frame_size].astype(np.float64)
        elif len(corpus_audio) >= frame_size:
            grain = corpus_audio[:frame_size].astype(np.float64)
        else:
            grain = np.zeros(frame_size)
            grain[:len(corpus_audio)] = corpus_audio

        # Apply Hann window before RMS measurement so the scaling is
        # calibrated against what actually gets summed into the output.
        # Measuring on the raw grain overestimates RMS (edges included)
        # and causes amplitude bumps at every hop after OLA normalisation.
        grain *= hann_seg
        target_rms = fi["rms"]
        grain_rms  = float(np.sqrt(np.mean(grain ** 2)))
        if target_rms <= 1e-10:
            grain[:] = 0.0
        elif grain_rms > 1e-9:
            grain *= target_rms / grain_rms
        else:
            grain[:] = 0.0

        # Accumulate
        if stereo:
            if pitch_pan:
                midi = fi["midi"]
                if midi is not None and midi_hi > midi_lo:
                    pan = float(midi - midi_lo) / (midi_hi - midi_lo) * 2.0 - 1.0
                else:
                    pan = 0.0
            else:
                pan = 0.0

            # Constant-power panning (same formula as Distribute_sounds_in_stereo_field.praat)
            left_gain  = math.sqrt((1.0 - pan) / 2.0)
            right_gain = math.sqrt((1.0 + pan) / 2.0)
            out[start:end, 0] += grain * left_gain
            out[start:end, 1] += grain * right_gain
        else:
            out[start:end] += grain

    # Normalise by OLA window sum (avoids amplitude ripple at boundaries)
    safe_norm = np.maximum(norm, 1e-9)
    if stereo:
        out[:, 0] /= safe_norm
        out[:, 1] /= safe_norm
    else:
        out /= safe_norm

    # Apply output gain
    peak = float(np.max(np.abs(out)))
    if peak > 1e-9:
        out = out * (gain / peak)
        if gain > 1.0:
            out = np.clip(out, -1.0, 1.0)

    # Trim to input length and return
    result = out[:target_len]
    return result.astype(np.float32)


def write_frame_results(out_path, frame_matches, params, target_sr, target_len, envelope_stats=None):
    """
    Write a Praat-parseable results file for frame-based mode.
    Ranks corpus entries by how many frames they were chosen for.
    """
    from collections import Counter
    import numpy as np

    n_frames  = len(frame_matches)
    n_matched = sum(1 for fm in frame_matches if fm["match"] is not None)

    # Tally usage and MEAN selected score per (family, inst, note, dyn) key.
    # v1.7 reported the single best frame score, which made a frequently poor
    # match look deceptively excellent if it happened to fit one frame well.
    usage     = Counter()
    score_sum = Counter()
    entry_of  = {}
    for fm in frame_matches:
        if fm["match"] is None:
            continue
        score, entry, _ = fm["match"]
        key = (entry.family, entry.inst, entry.note, entry.dyn)
        usage[key] += 1
        score_sum[key] += float(score)
        entry_of[key] = entry

    mean_sc = {k: score_sum[k] / max(1, usage[k]) for k in usage}
    n_results = min(params["_n_results"], len(usage))
    ranked    = [k for k, _ in usage.most_common(n_results)]

    # Use the OS default line separator so Praat's newline$ matches on Windows.
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("=== TinySOL Retrieval Results ===\n")
        f.write("render_mode=frame_based\n")
        f.write("chosen_count=%d\n"  % n_matched)
        if envelope_stats is not None:
            f.write("envelope_follow=%.3f\n" % envelope_stats.get("envelope_follow", 0.0))
            f.write("envelope_corr_before=%.4f\n" % envelope_stats.get("envelope_corr_before", 0.0))
            f.write("envelope_corr_after=%.4f\n" % envelope_stats.get("envelope_corr_after", 0.0))
        f.write("target_sr=%d\n"     % target_sr)
        f.write("target_len=%.3f\n"  % (target_len / max(1, target_sr)))
        f.write("n_candidates=%d\n"  % n_frames)
        f.write("n_results=%d\n"     % n_results)
        f.write("silence_rendered=%d\n" % (1 if n_matched == 0 else 0))
        f.write("silence_reason=%s\n" % ("frame_unmatched" if n_matched == 0 else ""))
        f.write("\n")
        f.write("rank,score,family,instrument,note,midi,dynamic,variant,"
                "technique,abs_path\n")
        for rank, key in enumerate(ranked, 1):
            e = entry_of[key]
            f.write("%d,%.6f,%s,%s,%s,%d,%s,%s,%s,%s\n" % (
                rank, mean_sc[key],
                e.family, e.inst, e.note, e.midi,
                e.dyn, e.variant, e.tech, e.abs_path,
            ))
        f.write("\n")
        f.write("=== Frame Stats ===\n")
        f.write("total_frames=%d\n"      % n_frames)
        f.write("matched_frames=%d\n"    % n_matched)
        f.write("silent_frames=%d\n"     % sum(1 for fm in frame_matches if fm["frame"].get("silent", False)))
        matched_scores = [float(fm["match"][0]) for fm in frame_matches if fm["match"] is not None]
        f.write("mean_match_score=%.6f\n" % (float(np.mean(matched_scores)) if matched_scores else 0.0))
        f.write("silence_threshold=%.3f\n" % params["_silence_threshold"])
        f.write("frame_size_ms=%.1f\n"   % params["_frame_size_ms"])
        f.write("hop_size_ms=%.1f\n"     % params["_hop_size_ms"])
        f.write("pitch_tolerance=%d\n"   % params["_pitch_tolerance"])
        f.write("\n")
        f.write("=== Descriptor Weights ===\n")
        for name, w in params["_descriptor_weights"].items():
            f.write("%s=%.3f\n" % (name, w))


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 5:
        print(
            "Usage: python tinysol_retrieval.py "
            "target.wav  params.txt  output.wav  results.txt  [done.txt]",
            file=sys.stderr,
        )
        sys.exit(1)

    # Windows Praat may launch Python with a legacy code page.  Status text
    # must never be able to abort the DSP/retrieval pipeline.
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(errors="replace")
        except Exception:
            pass

    check_dependencies()

    import numpy as np
    import soundfile as sf

    target_wav  = sys.argv[1]
    params_file = sys.argv[2]
    out_wav     = sys.argv[3]
    results_txt = sys.argv[4]
    done_file   = sys.argv[5] if len(sys.argv) > 5 else None

    import io
    import traceback

    class _TeeErr:
        def __init__(self, primary, capture):
            self.primary = primary
            self.capture = capture
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

    _err_capture = io.StringIO()
    _orig_err = sys.stderr
    sys.stderr = _TeeErr(_orig_err, _err_capture)
    try:
        _run_pipeline(target_wav, params_file, out_wav, results_txt)
        if done_file:
            with open(done_file, "w", encoding="utf-8") as f:
                f.write("OK\n")
    except SystemExit:
        if done_file:
            detail = _err_capture.getvalue().strip()
            with open(done_file, "w", encoding="utf-8") as f:
                f.write("ERROR: Python exited with error.\n")
                if detail:
                    f.write(detail + "\n")
        raise
    except Exception as exc:
        tb = traceback.format_exc()
        if done_file:
            with open(done_file, "w", encoding="utf-8") as f:
                f.write("ERROR: %s\n%s" % (str(exc), tb))
        print("ERROR: %s" % exc, file=_orig_err)
        sys.exit(1)
    finally:
        sys.stderr = _orig_err


def _run_pipeline(target_wav, params_file, out_wav, results_txt):
    """Main pipeline — extracted so main() can wrap it in error handling."""
    import numpy as np
    import soundfile as sf

    # ── Stage 1: Parameters ──────────────────────────────────────────────
    print("[1/8] Parsing parameters from %s ..." % params_file)
    params = parse_params(params_file)
    db_dir        = params["db_dir"]
    corpus_root   = params["corpus_root"]
    render_mode   = params["render_mode"]
    analysis_mode = params["_analysis_mode"]

    if not db_dir or not os.path.isdir(db_dir):
        print("ERROR: db_dir not found: %s" % db_dir, file=sys.stderr)
        sys.exit(1)
    if not corpus_root or not os.path.isdir(corpus_root):
        print("ERROR: corpus_root not found: %s" % corpus_root, file=sys.stderr)
        sys.exit(1)

    print("  db_dir:        %s" % db_dir)
    print("  corpus_root:   %s" % corpus_root)
    print("  families:      %s" % params["allowed_families"])
    print("  dynamics:      %s" % params["preferred_dynamics"])
    print("  MIDI range:    %d – %d" % (params["_min_midi"], params["_max_midi"]))
    print("  analysis_mode: %s" % analysis_mode)
    if analysis_mode == "frame_based":
        print("  frame/hop:     %.0f ms / %.0f ms  pitch_tol: ±%d st"
              % (params["_frame_size_ms"], params["_hop_size_ms"],
                 params["_pitch_tolerance"]))
    else:
        print("  render_mode:   %s  max_layers: %d" % (render_mode, params["_max_layers"]))
    print("  envelope:      %.2f (macro RMS follow)" % params["_envelope_follow"])

    # ── Stage 2: Load .db files ──────────────────────────────────────────
    print("[2/8] Loading .db descriptor files ...")
    db_store = DbStore()
    for name in DB_NAMES:
        db_store.load(db_dir, name)

    # ── Stage 3+4: Build corpus index ────────────────────────────────────
    print("[3/8] Scanning corpus and building index ...")
    entries = build_index(corpus_root, db_store, params)

    if not entries:
        print("ERROR: No corpus entries found under %s" % corpus_root,
              file=sys.stderr)
        sys.exit(1)

    # ════════════════════════════════════════════════════════════════════
    #  FRAME-BASED PATH
    # ════════════════════════════════════════════════════════════════════
    if analysis_mode == "frame_based":

        # ── Stage 4: Frame analysis ──────────────────────────────────────
        print("[4/8] Analysing target WAV frame by frame ...")
        frames_info, target_sr, target_len, frame_size, hop_size = \
            analyse_frames(target_wav,
                           params["_frame_size_ms"],
                           params["_hop_size_ms"])
        n_voiced = sum(1 for fi in frames_info if fi["midi"] is not None)
        n_silent = sum(1 for fi in frames_info if fi.get("silent", False))
        analysis_ch = frames_info[0].get("analysis_channel", 1) if frames_info else 1
        print("  %d frames  (%.0f ms / %.0f ms)  voiced: %d  unvoiced: %d  silent: %d"
              % (len(frames_info),
                 params["_frame_size_ms"], params["_hop_size_ms"],
                 n_voiced, len(frames_info) - n_voiced, n_silent))
        print("  Analysis channel: %d" % analysis_ch)

        # ── Stage 4b: Whole-file target descriptors ───────────────────────
        # The .db files store whole-note averages; per-frame descriptors live
        # in a different region of feature space and produce wrong matches.
        # We compute the target's whole-file descriptors once here as a
        # fallback and for frames where audio extraction fails.
        # Per-frame descriptors are computed from the actual audio slice
        # inside retrieve_frame(), allowing timbral variation frame-to-frame.
        print("[4b/8] Computing whole-file target descriptors (fallback) ...")
        target_descs_wf, _, _, _ = analyse_target(target_wav)
        print("  Descriptors: %s" % list(target_descs_wf.keys()))

        # Load raw audio once so retrieve_frame can slice per-frame audio
        _raw_audio, _raw_sr = load_audio(target_wav)
        import numpy as np
        _raw_x = _raw_audio.astype(np.float64)

        # ── Stage 4c: Build candidate domain (Orchidea-style, done ONCE) ──
        # Hard constraints (family, instrument, MIDI range) are applied here
        # and the resulting domain is reused for every frame — not re-checked
        # per frame.  This matches Production::computeVariableDomains() in
        # orchids-master: compute legal candidates once, search operates on them.
        print("[4c/8] Building candidate domain (hard-constraint filter) ...")
        frame_domain = build_candidate_domain(entries, params)
        if not frame_domain:
            print("ERROR: No legal candidates after hard-constraint filtering.",
                  file=sys.stderr)
            print("  Check families, MIDI range, and that .db files are present.",
                  file=sys.stderr)
            sys.exit(1)

        # ── Stage 5: Per-frame retrieval with persistence ─────────────
        # Match persistence: if the same corpus entry won the last N frames,
        # give it a small score bonus so it's harder for a marginally-better
        # entry to take over.  This prevents erratic switching between
        # similar-scoring entries that causes timbral discontinuities.
        print("[5/8] Retrieving best match per frame (with persistence) ...")
        frame_matches   = []
        n_matched       = 0
        last_voiced_midi = None
        prev_entry_path  = None    # track previous winning entry
        persist_count    = 0       # how many consecutive frames it won
        persist_bonus    = 0.015   # score reduction per consecutive frame
        unvoiced_run     = 0       # expire pitch extrapolation after brief gaps

        for fi in frames_info:
            if fi.get("silent", False):
                last_voiced_midi = None
                unvoiced_run = 0
            elif fi["midi"] is None:
                unvoiced_run += 1
                if unvoiced_run > 2:
                    last_voiced_midi = None
            else:
                unvoiced_run = 0
            # Slice the raw audio for this frame so retrieve_frame can compute
            # per-frame descriptors (captures timbre variation across the target)
            f_start = fi["start"]
            f_end   = f_start + frame_size
            frame_audio_slice = _raw_x[f_start:min(f_end, len(_raw_x))]

            match = retrieve_frame(frame_domain, fi, params,
                                   target_descs_wf, last_voiced_midi,
                                   frame_audio=frame_audio_slice,
                                   frame_sr=_raw_sr,
                                   frame_n_fft=min(2048, frame_size))

            # Apply persistence: if the previous winner is still a valid
            # candidate, check if it would win with a persistence bonus.
            if match is not None and prev_entry_path is not None:
                _score, _entry, _detail = match
                if _entry.abs_path != prev_entry_path:
                    # Different entry won — check if previous entry is close enough
                    prev_match = retrieve_frame(frame_domain, fi, params,
                                                target_descs_wf, last_voiced_midi,
                                                prefer_path=prev_entry_path,
                                                frame_audio=frame_audio_slice,
                                                frame_sr=_raw_sr,
                                                frame_n_fft=min(2048, frame_size))
                    if prev_match is not None:
                        prev_score = prev_match[0]
                        bonus = min(persist_bonus * persist_count, 0.10)
                        if prev_score - bonus <= _score:
                            # Previous entry wins with persistence bonus
                            match = prev_match
                            persist_count += 1
                        else:
                            # New entry wins decisively — switch
                            persist_count = 1
                            prev_entry_path = _entry.abs_path
                    else:
                        persist_count = 1
                        prev_entry_path = _entry.abs_path
                else:
                    persist_count += 1
            elif match is not None:
                _score, _entry, _detail = match
                prev_entry_path = _entry.abs_path
                persist_count = 1

            if match is None:
                prev_entry_path = None
                persist_count = 0

            frame_matches.append({"frame": fi, "match": match})
            if match is not None:
                n_matched += 1
            if fi["midi"] is not None:
                last_voiced_midi = fi["midi"]
        print("  Matched %d / %d frames" % (n_matched, len(frames_info)))

        # Print most-used entries
        from collections import Counter
        top_keys = Counter()
        for fm in frame_matches:
            if fm["match"]:
                e = fm["match"][1]
                top_keys[(e.family, e.inst, e.note, e.dyn)] += 1
        print("  Most-used corpus entries:")
        for (fam, inst, note, dyn), cnt in top_keys.most_common(5):
            print("    %s %s %s %s  ×%d frames" % (fam, inst, note, dyn, cnt))

        # ── Stage 6: Overlap-add render ──────────────────────────────────
        print("[6/8] Rendering (overlap-add, stereo=%s, pitch_pan=%s) ..."
              % (params["_stereo_output"], params["_pitch_pan_stereo"]))
        output_audio = render_frame_matches(
            frame_matches, frame_size, hop_size,
            target_len, target_sr, params["_render_gain"],
            stereo=params["_stereo_output"],
            pitch_pan=params["_pitch_pan_stereo"],
        )
        output_audio, envelope_stats = apply_target_macro_envelope(
            output_audio, _raw_audio, target_sr, params["_envelope_follow"])
        print("  Envelope corr: %.3f -> %.3f" % (
            envelope_stats["envelope_corr_before"],
            envelope_stats["envelope_corr_after"]))

        # ── Stage 7: Write WAV ────────────────────────────────────────────
        print("[7/8] Writing output WAV ...")
        sf.write(out_wav, output_audio, target_sr, subtype="FLOAT")
        out_dur = len(output_audio) / target_sr
        peak    = float(np.max(np.abs(output_audio)))
        print("  Written: %.2f s  |  peak=%.4f" % (out_dur, peak))

        # ── Stage 8: Write results ────────────────────────────────────────
        print("[8/8] Writing results file ...")
        write_frame_results(results_txt, frame_matches, params,
                            target_sr, target_len, envelope_stats=envelope_stats)

        print("OK: done.")
        if top_keys:
            best_key = top_keys.most_common(1)[0][0]
            best_entry = next(fm["match"][1] for fm in frame_matches
                              if fm["match"] and
                              (fm["match"][1].family, fm["match"][1].inst,
                               fm["match"][1].note, fm["match"][1].dyn) == best_key)
            _best_scores = [float(fm["match"][0]) for fm in frame_matches
                            if fm["match"] and
                            (fm["match"][1].family, fm["match"][1].inst,
                             fm["match"][1].note, fm["match"][1].dyn) == best_key]
            best_score_val = float(np.mean(_best_scores)) if _best_scores else 0.0
            print("best_match=%s %s %s %s score=%.6f" % (
                best_entry.family, best_entry.inst,
                best_entry.note, best_entry.dyn, best_score_val))

    # ════════════════════════════════════════════════════════════════════
    #  WHOLE-FILE PATH  (original behaviour)
    # ════════════════════════════════════════════════════════════════════
    else:

        # ── Stage 5: Analyse target ──────────────────────────────────────
        print("[4/8] Analysing target WAV ...")
        target_descs, target_sr, target_len, pitch_info = analyse_target(target_wav)
        print("  Descriptors computed: %s" % list(target_descs.keys()))
        print("  Analysis channel: %d" % pitch_info.get("analysis_channel", 1))

        target_midi = pitch_info["midi"]
        # Build target partials for harmonic contribution scoring.
        # Use None (not an empty list) when unvoiced — harmonic_contribution_distance()
        # returns the neutral 0.5 for None, but 1.0 (worst) for an empty list with
        # a non-zero weight, which would unfairly penalise all corpus entries.
        target_partials = None
        if pitch_info["partials_hz"] and pitch_info["partials_amp"]:
            target_partials = list(zip(pitch_info["partials_hz"],
                                       pitch_info["partials_amp"]))

        if pitch_info["f0_hz"] is not None:
            print("  Detected F0: %.1f Hz  (MIDI %d)  voiced: %d/%d frames"
                  % (pitch_info["f0_hz"], pitch_info["midi"],
                     pitch_info["n_voiced"], pitch_info["n_frames"]))
            if pitch_info["partials_hz"]:
                partial_strs = ["%.0f" % h for h in pitch_info["partials_hz"][:8]]
                print("  Partials: %s Hz" % ", ".join(partial_strs))
                print("  Harmonic contribution scoring: enabled (%d partials)"
                      % len(pitch_info["partials_hz"]))
        else:
            print("  No pitched content detected (unvoiced/noise) — "
                  "harmonic contribution disabled, using timbre-only matching")

        # ── Stage 6: Retrieve and rank ────────────────────────────────────
        print("[5/8] Retrieving and ranking corpus entries ...")
        scored = retrieve(entries, target_descs, params,
                          target_midi=target_midi,
                          target_partials=target_partials)
        print("  Candidates after filtering: %d" % len(scored))

        n_with_desc = sum(1 for e in entries if e.descriptors)

        _af = set(params["_allowed_families"])
        _ai = set(params["_allowed_instruments"])
        n_fam_matched = sum(
            1 for e in entries
            if (not _af or e.family in _af)
            and (not _ai or e.inst in _ai)
        )

        if not scored:
            if n_with_desc == 0:
                print("CRITICAL: 0 of %d corpus entries have descriptor vectors." % len(entries),
                      file=sys.stderr)
                print("  .db file paths do not match corpus WAV paths.", file=sys.stderr)
                print("  Check db_dir and corpus_root point to the same TinySOL_2020 folder.",
                      file=sys.stderr)
                sys.exit(1)

            if n_fam_matched == 0:
                print("ERROR: No corpus entries matched the requested families (%s)."
                      % params["allowed_families"], file=sys.stderr)
                print("  Change the Instrument families filter, or select 'All families'.",
                      file=sys.stderr)
                print("  (Automatic fallback is disabled — results would be misleading.)",
                      file=sys.stderr)
                sys.exit(1)
            else:
                print("ERROR: %d entries in requested families had no scoreable descriptors."
                      % n_fam_matched, file=sys.stderr)
                print("  Check that .db files exist and descriptor coverage is > 0%%.",
                      file=sys.stderr)
                print("  (Automatic fallback is disabled — fix paths first.)",
                      file=sys.stderr)
                sys.exit(1)

        top5 = scored[:5]
        print("  Top 5 matches:")
        for rank, (sc, e, _d) in enumerate(top5, 1):
            print("    #%d  score=%.4f  %s %s %s %s" % (
                rank, sc, e.family, e.inst, e.note, e.dyn))

        # ── Silence threshold check ──────────────────────────────────────
        # Orchidea-inspired: if the best achievable match is still too far
        # from the target (score > silence_threshold), render silence rather
        # than a genuinely bad corpus substitute.  This is the "neutral
        # element" concept from orchids-master production logic.
        silence_thresh = params["_silence_threshold"]
        best_score_val = scored[0][0]
        target_is_silent = pitch_info.get("target_rms", 0.0) <= 1e-8
        gate_reject = (silence_thresh < 2.0 and
                       best_score_val > silence_thresh)
        render_silence = target_is_silent or gate_reject
        silence_reason = "silent_target" if target_is_silent else (
            "score_threshold" if gate_reject else "")

        if target_is_silent:
            print("  Target is effectively silent; rendering silence.")
        elif gate_reject:
            print("  WARNING: best score %.4f exceeds silence threshold %.2f"
                  % (best_score_val, silence_thresh))
            print("  Rendering silence (no corpus entry is a good match).")

        # ── Stage 7: Blend / render ──────────────────────────────────────
        max_layers = params["_max_layers"]
        n_blend    = 1 if render_mode == "best" else min(max_layers, 4)
        if render_mode in ("top2",):           n_blend = 2
        elif render_mode in ("top3", "blend"): n_blend = 3
        elif render_mode == "top4":            n_blend = 4

        print("[6/8] Rendering output (%s, %d layer(s), stereo=%s) ..."
              % (render_mode, n_blend, params["_stereo_output"]))

        if render_silence:
            # Neutral element: silence at the target's sample rate and length
            if params["_stereo_output"]:
                output_audio = np.zeros((target_len, 2), dtype=np.float32)
            else:
                output_audio = np.zeros(target_len, dtype=np.float32)
            envelope_stats = {
                "envelope_follow": params["_envelope_follow"],
                "envelope_corr_before": 0.0,
                "envelope_corr_after": 0.0,
            }
        else:
            output_audio = blend_samples(
                scored, target_len, target_sr,
                render_mode, params["_render_gain"],
                stereo=params["_stereo_output"]
            )
            target_audio_env, _ = load_audio(target_wav, target_sr=target_sr)
            output_audio, envelope_stats = apply_target_macro_envelope(
                output_audio, target_audio_env, target_sr,
                params["_envelope_follow"])
            print("  Envelope corr: %.3f -> %.3f" % (
                envelope_stats["envelope_corr_before"],
                envelope_stats["envelope_corr_after"]))

        # ── Stage 8: Write WAV ────────────────────────────────────────────
        print("[7/8] Writing output WAV ...")
        sf.write(out_wav, output_audio, target_sr, subtype="FLOAT")
        out_dur = len(output_audio) / target_sr
        peak    = float(np.max(np.abs(output_audio)))
        print("  Written: %.2f s  |  peak=%.4f" % (out_dur, peak))

        # ── Stage 9: Write results text ───────────────────────────────────
        print("[8/8] Writing results file ...")
        write_results(results_txt, scored, params, target_sr, target_len,
                      render_mode, n_blend,
                      render_silence=render_silence,
                      silence_reason=silence_reason,
                      envelope_stats=envelope_stats)

        print("OK: done.")
        silence_flag = ("SILENCE (%s)" % silence_reason) if render_silence else ""
        print("best_match=%s %s %s %s score=%.6f %s" % (
            scored[0][1].family,
            scored[0][1].inst,
            scored[0][1].note,
            scored[0][1].dyn,
            scored[0][0],
            silence_flag,
        ))


if __name__ == "__main__":
    main()
