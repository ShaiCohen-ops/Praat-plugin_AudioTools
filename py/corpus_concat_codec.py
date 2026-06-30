#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - corpus_concat_codec.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.3 (2026)
# License: MIT License
# ============================================================
#
# Corpus-Based Concatenative Synthesis using a neural audio codec
# (EnCodec or DAC) as the token space.
#
# Pipeline:
#   Praat exports the selected Sound -> this script detects ONSETS in the
#   source (amplitude/energy based) and segments the source onset-to-onset
#   (not a fixed grid). Each onset-bounded segment is further subdivided
#   into a fine grid of analysis sub-windows (the onset boundaries stay the
#   only authoritative rhythm markers - subdivision is internal to matching
#   only), encodes each sub-window into codec tokens, compares against a
#   pre-encoded corpus of grains using BOTH timbre (cosine distance on
#   token features) and loudness (log-RMS similarity), then places each
#   matched corpus grain's own loudest moment exactly on the source onset
#   its segment started from. This is what keeps the OUTPUT's rhythm locked
#   to the INPUT's rhythm: source onset times drive where things happen,
#   corpus material determines what they sound like - and since each
#   segment is now matched sub-window by sub-window, a decaying/evolving
#   span of source audio is no longer forced to match ONE static corpus
#   grain for its whole duration. The output WAV is read back into Praat.
#
# Two subcommands:
#   build-corpus  : slice target audio into grains (fixed grid - the corpus
#                   has no rhythm of its own to preserve), encode each,
#                   record its loudest-moment offset and RMS, save an index
#   match         : detect source onsets, segment onset-to-onset, subdivide
#                   each segment into analysis sub-windows, match each
#                   sub-window against the index, place matched grains at
#                   their source-aligned times (segment head peak-aligned,
#                   later sub-windows tiling forward), reconstruct
#
# IMPORTANT - token IDs are CATEGORICAL symbols, not continuous numbers.
#   We never take Euclidean distance on raw token IDs. Instead we build a
#   searchable representation from each grain's [n_codebooks, n_frames] token
#   matrix using:
#       - per-codebook token-ID histograms   (marginal distribution)
#       - hashed bigram transition features   (local sequence structure)
#   concatenated into one fixed-length vector, compared with COSINE distance.
#   This timbre distance says nothing about LOUDNESS (a near-silent grain and
#   a loud one can have similar token-histogram shapes), so match() adds a
#   separate log-RMS energy term so quiet corpus material can't substitute
#   for an energetic source onset just because its spectral shape rhymes.
# ============================================================

import os
import sys
import json
import glob
import argparse
import traceback

import numpy as np


# ============================================================
# Stderr logging (no shell redirect needed)
#   The Praat front-end calls this script via runSubprocess, which does NOT
#   go through a shell, so a "2> file" redirect is not available. Instead,
#   the caller passes --log <path> and we tee everything written to
#   sys.stderr into that file (in addition to the real stderr, so running
#   the script directly from a terminal still shows errors as usual).
# ============================================================

class _Tee:
    def __init__(self, *streams):
        self._streams = [s for s in streams if s is not None]

    def write(self, data):
        for s in self._streams:
            try:
                s.write(data)
                s.flush()
            except Exception:
                pass

    def flush(self):
        for s in self._streams:
            try:
                s.flush()
            except Exception:
                pass


_LOG_DIR = None


def _install_log_tee(log_path):
    """If log_path is given, mirror everything written to sys.stderr into it."""
    global _LOG_DIR
    if not log_path:
        return
    try:
        log_f = open(log_path, "w", encoding="utf-8")
        sys.stderr = _Tee(sys.stderr, log_f)
        _LOG_DIR = os.path.dirname(os.path.abspath(log_path))
    except Exception:
        # If the log file can't be opened, fall back to plain stderr silently;
        # this must never be the reason the actual task fails.
        pass


# ============================================================
# Audio I/O helpers (sample-rate + mono/stereo safe)
# ============================================================

def load_audio_mono(path, target_sr):
    """Load any WAV, force mono, resample to target_sr. Returns float32 in [-1,1]."""
    import soundfile as sf
    data, sr = sf.read(path, always_2d=True)        # shape [n, channels]
    data = data.astype(np.float32)
    mono = data.mean(axis=1)                          # safe mono downmix
    if sr != target_sr:
        mono = resample_to(mono, sr, target_sr)
    # guard against NaN/inf
    mono = np.nan_to_num(mono, nan=0.0, posinf=0.0, neginf=0.0)
    return mono


def resample_to(x, sr_in, sr_out):
    if sr_in == sr_out or len(x) == 0:
        return x.astype(np.float32)
    from math import gcd
    g = gcd(int(sr_in), int(sr_out))
    up, down = int(sr_out // g), int(sr_in // g)
    from scipy.signal import resample_poly
    return resample_poly(x, up, down).astype(np.float32)


def write_audio(path, x, sr):
    import soundfile as sf
    x = np.nan_to_num(np.asarray(x, dtype=np.float32))
    peak = float(np.abs(x).max()) if x.size else 0.0
    if peak > 1.0:
        x = x / (peak * 1.01)
    sf.write(path, x, sr, subtype="PCM_16")


# ============================================================
# Codec adapter interface
#   Each adapter exposes: sample_rate, codebook_size, encode(wav)->tokens,
#   decode(tokens)->wav.  tokens is an int array [n_codebooks, n_frames].
#   The mock adapter lets the whole pipeline be tested without torch.
# ============================================================

class CodecAdapter:
    name = "base"
    sample_rate = 24000
    codebook_size = 1024

    def encode(self, wav):
        raise NotImplementedError

    def decode(self, tokens):
        raise NotImplementedError


class EncodecAdapter(CodecAdapter):
    name = "encodec"

    def __init__(self, bandwidth=6.0):
        import torch
        from encodec import EncodecModel
        self.torch = torch
        self.model = EncodecModel.encodec_model_24khz()
        self.model.set_target_bandwidth(bandwidth)
        self.model.eval()
        self.sample_rate = self.model.sample_rate          # 24000
        self.codebook_size = 1024                           # EnCodec RVQ codebook

    def encode(self, wav):
        torch = self.torch
        x = torch.from_numpy(wav).float().unsqueeze(0).unsqueeze(0)  # [1,1,T]
        with torch.no_grad():
            frames = self.model.encode(x)
        # frames: list of (codes [1, n_q, T], scale). Concatenate along time.
        codes = torch.cat([f[0] for f in frames], dim=-1)  # [1, n_q, T]
        return codes.squeeze(0).cpu().numpy().astype(np.int64)  # [n_q, T]

    def decode(self, tokens):
        torch = self.torch
        codes = torch.from_numpy(tokens).long().unsqueeze(0)   # [1, n_q, T]
        with torch.no_grad():
            wav = self.model.decode([(codes, None)])
        return wav.squeeze().cpu().numpy().astype(np.float32)


class DACAdapter(CodecAdapter):
    name = "dac"

    def __init__(self, model_type="44khz"):
        import torch
        import dac
        self.torch = torch
        model_path = dac.utils.download(model_type=model_type)
        self.model = dac.DAC.load(model_path)
        self.model.eval()
        self.sample_rate = self.model.sample_rate          # 44100 for 44khz
        self.codebook_size = self.model.codebook_size      # typically 1024

    def encode(self, wav):
        torch = self.torch
        x = torch.from_numpy(wav).float().unsqueeze(0).unsqueeze(0)  # [1,1,T]
        x = self.model.preprocess(x, self.sample_rate)
        with torch.no_grad():
            _, codes, _, _, _ = self.model.encode(x)
        # codes: [1, n_codebooks, T]
        return codes.squeeze(0).cpu().numpy().astype(np.int64)

    def decode(self, tokens):
        torch = self.torch
        codes = torch.from_numpy(tokens).long().unsqueeze(0)
        with torch.no_grad():
            z, _, _ = self.model.quantizer.from_codes(codes)
            wav = self.model.decode(z)
        return wav.squeeze().cpu().numpy().astype(np.float32)


class MockAdapter(CodecAdapter):
    """Deterministic spectral-feature 'codec' for testing the pipeline without
    torch. Produces categorical tokens so similar audio -> similar tokens."""
    name = "mock"

    def __init__(self):
        self.sample_rate = 24000
        self.codebook_size = 256
        self.n_codebooks = 4
        self.hop = 320

    def encode(self, wav):
        nf = max(2, len(wav) // self.hop)
        toks = np.zeros((self.n_codebooks, nf), dtype=np.int64)
        for f in range(nf):
            seg = wav[f * self.hop:(f + 1) * self.hop]
            if len(seg) < 8:
                seg = np.pad(seg, (0, 8 - len(seg)))
            spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
            cen = int(spec.argmax() % self.codebook_size)
            eng = int(min(self.codebook_size - 1,
                          (spec.sum() * 5) % self.codebook_size))
            for cb in range(self.n_codebooks):
                toks[cb, f] = (cen * (cb + 1) + eng) % self.codebook_size
        return toks

    def decode(self, tokens):
        # mock decode is unused for reconstruction (we splice real grain audio)
        return np.zeros(tokens.shape[1] * self.hop, dtype=np.float32)


def make_codec(name):
    name = (name or "").lower()
    if name == "encodec":
        return EncodecAdapter()
    if name == "dac":
        return DACAdapter()
    if name == "mock":
        return MockAdapter()
    raise ValueError("Unknown codec '%s' (use encodec, dac, or mock)" % name)


# ============================================================
# Searchable representation (CATEGORICAL token features)
# ============================================================

def token_histogram(tokens, codebook_size):
    """Per-codebook normalised histogram of token IDs -> concatenated vector.
    Compares the DISTRIBUTION of categorical symbols, not their magnitudes."""
    feats = []
    for cb in range(tokens.shape[0]):
        h, _ = np.histogram(tokens[cb], bins=codebook_size, range=(0, codebook_size))
        s = h.sum()
        feats.append(h / s if s > 0 else h.astype(np.float32))
    return np.concatenate(feats).astype(np.float32)


def token_bigrams(tokens, n_buckets=64):
    """Hashed bigram transition counts pooled across codebooks. Captures local
    token SEQUENCE structure - discriminates better than marginal histograms,
    especially for short grains."""
    v = np.zeros(n_buckets, dtype=np.float32)
    for cb in range(tokens.shape[0]):
        row = tokens[cb]
        for i in range(len(row) - 1):
            b = (int(row[i]) * 131 + int(row[i + 1])) % n_buckets
            v[b] += 1.0
    s = v.sum()
    return v / s if s > 0 else v


def grain_feature(tokens, codebook_size, hist_weight=1.0, bigram_weight=1.0):
    """Full searchable feature: histogram (+) bigram. Both are L1-normalised
    distributions, so cosine distance is meaningful on the concatenation."""
    hist = token_histogram(tokens, codebook_size) * hist_weight
    bg = token_bigrams(tokens) * bigram_weight
    return np.concatenate([hist, bg]).astype(np.float32)


def cosine_distance(a, b):
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na == 0.0 or nb == 0.0:
        return 1.0
    return 1.0 - float(np.dot(a, b) / (na * nb))


# ============================================================
# Grain slicing
# ============================================================

def slice_grains(wav, sr, grain_ms, hop_ms):
    """Yield (start_sample, grain_audio) tuples. hop_ms < grain_ms = overlap."""
    gn = max(1, int(round(grain_ms / 1000.0 * sr)))
    hn = max(1, int(round(hop_ms / 1000.0 * sr)))
    out = []
    i = 0
    n = len(wav)
    if n == 0:
        return out
    while i < n:
        seg = wav[i:i + gn]
        if len(seg) < gn:
            # pad the final short grain so the codec gets a full window
            seg = np.pad(seg, (0, gn - len(seg)))
        out.append((i, seg))
        if i + gn >= n:
            break
        i += hn
    return out


# ============================================================
# Onset detection (source side only)
#   The corpus is just a bag of grains on a uniform grid - it has no
#   "rhythm" of its own to preserve. The SOURCE does: whatever transients
#   (attacks, consonant bursts, plucks, hits) appear in the selection should
#   appear at the SAME TIME in the output, regardless of how long the
#   matched corpus grain naturally is. A uniform grid (slice_grains) has no
#   idea where those transients are, so it routinely splits one onset across
#   two overlapping grains or buries it mid-grain - which is exactly why the
#   old output had "no connection between the input onsets and the output".
#   Fix: detect onsets in the source and use THEM as segment boundaries.
# ============================================================

def detect_onsets(wav, sr, frame_ms=10.0, min_interval_ms=60.0,
                   sensitivity=1.5):
    """Simple amplitude/energy-based onset detector, no extra dependencies.

    Steps:
      1. RMS energy per short frame (frame_ms).
      2. Half-wave rectified frame-to-frame energy RISE (onsets are increases
         in energy, not decreases - this rejects decays/releases).
      3. Adaptive threshold = local mean + sensitivity * local std, so it
         tracks the overall dynamics of the source instead of one fixed
         number that's wrong for quiet vs loud material.
      4. Peak-pick candidates above threshold, enforcing a minimum spacing
         (min_interval_ms) so one transient can't fire twice.

    Returns: sorted list of onset times in SAMPLES, always including sample 0
    (so the very first sound is never dropped before its own "onset").
    """
    n = len(wav)
    if n == 0:
        return [0]
    frame_n = max(1, int(round(frame_ms / 1000.0 * sr)))
    n_frames = max(1, n // frame_n)
    if n_frames < 3:
        return [0]

    # per-frame RMS energy
    energy = np.zeros(n_frames, dtype=np.float64)
    for i in range(n_frames):
        seg = wav[i * frame_n:(i + 1) * frame_n]
        energy[i] = np.sqrt(np.mean(seg.astype(np.float64) ** 2) + 1e-12)

    # half-wave rectified energy rise (frame-to-frame increase only)
    rise = np.diff(energy, prepend=energy[0])
    rise = np.maximum(rise, 0.0)

    # adaptive threshold from the rise signal's own statistics
    mean_r = float(np.mean(rise))
    std_r = float(np.std(rise))
    threshold = mean_r + sensitivity * std_r

    # treat near-silent material (no real dynamics) as having no interior
    # onsets, so a quiet/short selection doesn't get chopped on noise floor
    # fluctuations alone
    if std_r < 1e-9:
        return [0]

    min_gap_frames = max(1, int(round(min_interval_ms / frame_ms)))

    candidates = np.where(rise > threshold)[0]
    onset_frames = []
    last = -min_gap_frames
    for f in candidates:
        if f - last >= min_gap_frames:
            onset_frames.append(int(f))
            last = f

    onset_samples = sorted(set([0] + [int(f * frame_n) for f in onset_frames]))
    return onset_samples


def onset_segments(wav, sr, onset_ms):
    """Slice wav into segments bounded by detected onsets.

    Each segment runs from one onset up to (but not including) the next -
    i.e. segment lengths are whatever the actual rhythm of the source gives,
    not a fixed grain size. Returns (start_sample, segment_audio) tuples,
    identical shape to slice_grains' output so downstream matching code
    doesn't need to know which path produced them.
    """
    n = len(wav)
    onsets = detect_onsets(wav, sr, min_interval_ms=onset_ms)
    bounds = onsets + [n]
    out = []
    for k in range(len(bounds) - 1):
        start = bounds[k]
        end = bounds[k + 1]
        if end > start:
            out.append((start, wav[start:end]))
    return out


def subdivide_segment(seg_start, seg, sr, analysis_grain_ms, analysis_hop_ms):
    """Break ONE onset-bounded segment into a fine analysis grid of
    sub-windows, so a segment that isn't just a single static moment - a
    decaying note, a vowel sliding between formants, anything whose
    spectral content keeps changing after the attack - doesn't get matched
    to ONE corpus grain for its entire length. Each sub-window is matched
    independently, so the corpus material can follow the source as it
    evolves.

    This is an internal ANALYSIS step only. `onset_segments` is still the
    sole authority on rhythm: the segment's own start sample is never
    touched here, and this function is never called on anything but a
    single already-onset-bounded segment, so subdividing it can't smear a
    boundary or invent a new one. Reuses the same fixed-hop tiling shape as
    `slice_grains`, just scoped to one segment instead of the whole file.

    Returns a list of (sub_start_sample, sub_audio, is_head) tuples:
      - sub_start_sample is in the SAME absolute sample coordinates as
        `seg_start` (i.e. seg_start + local offset), ready to hand straight
        to the placement/matching loop unchanged.
      - is_head is True only for the FIRST sub-window - the one that begins
        exactly at the segment's onset and therefore carries the actual
        attack/transient. Only that one should get peak-offset alignment;
        everything after it is filling forward continuously and should be
        placed at its own buffer start.

    Unlike `slice_grains` (which zero-pads a short trailing grain so the
    corpus gets a uniform buffer shape for indexing), a short trailing
    sub-window here is left at its natural length: this is live source
    material going straight into codec encoding and matching, not a slot
    that needs a fixed size, and padding it with silence would dilute its
    token features and overstate how long the matched grain should play.
    """
    n = len(seg)
    gn = max(1, int(round(analysis_grain_ms / 1000.0 * sr)))
    if n <= gn:
        # Segment is already no bigger than one analysis window - nothing to
        # subdivide. Hand it back whole as a single head sub-window rather
        # than manufacturing a duplicate (or silence-padded) copy of itself.
        return [(seg_start, seg, True)]

    hn = max(1, int(round(analysis_hop_ms / 1000.0 * sr)))
    out = []
    i = 0
    is_head = True
    while i < n:
        sub = seg[i:i + gn]
        out.append((seg_start + i, sub, is_head))
        is_head = False
        if i + gn >= n:
            break
        i += hn
    return out


# ============================================================
# build-corpus subcommand
# ============================================================

def spectral_centroid_hz(wav, sr):
    """Spectral centroid in Hz - energy-weighted mean frequency, a standard
    'brightness' descriptor. Draw mode uses it to pick corpus grains matching a
    drawn brightness contour."""
    if len(wav) < 4:
        return 0.0
    spec = np.abs(np.fft.rfft(wav.astype(np.float64) * np.hanning(len(wav))))
    freqs = np.fft.rfftfreq(len(wav), 1.0 / sr)
    s = spec.sum()
    return float((freqs * spec).sum() / s) if s > 0 else 0.0


def grain_peak_offset(seg, sr, frame_ms=10.0):
    """Sample offset of the grain's loudest moment, found from a smoothed
    RMS envelope (not a single raw sample) so one stray click doesn't skew
    it. This is the point inside the grain's own buffer that should land
    exactly on the source onset when the grain is placed in the output -
    a grain sliced from a blind fixed grid almost never has its energy
    sitting right at sample 0, so without this offset, placing the grain's
    BUFFER START at the onset routinely puts its actual transient noticeably
    later than the onset it was matched to."""
    n = len(seg)
    frame_n = max(1, int(round(frame_ms / 1000.0 * sr)))
    n_frames = max(1, n // frame_n)
    if n_frames < 1:
        return 0
    energy = np.zeros(n_frames, dtype=np.float64)
    for i in range(n_frames):
        f = seg[i * frame_n:(i + 1) * frame_n]
        energy[i] = np.sqrt(np.mean(f.astype(np.float64) ** 2) + 1e-12)
    peak_frame = int(np.argmax(energy))
    return peak_frame * frame_n


def build_corpus(args):
    codec = make_codec(args.codec)
    cb = getattr(codec, "codebook_size", 1024)

    # Ensure the index's parent directory exists (Praat's createDirectory does
    # not create nested parents, so the target folder may be missing).
    index_parent = os.path.dirname(os.path.abspath(args.index))
    if index_parent:
        os.makedirs(index_parent, exist_ok=True)

    # gather target audio files
    files = []
    for pat in args.corpus_audio.split(os.pathsep):
        pat = pat.strip().strip('"')
        if not pat:
            continue
        if os.path.isdir(pat):
            for ext in ("*.wav", "*.WAV", "*.flac", "*.aif", "*.aiff"):
                files.extend(glob.glob(os.path.join(pat, ext)))
        else:
            files.extend(glob.glob(pat))
    files = sorted(set(files))
    if not files:
        sys.stderr.write("No corpus audio files found in: %s\n" % args.corpus_audio)
        sys.exit(2)

    grains_meta = []
    feats = []
    grain_audio_dir = args.index + "_grains"
    # Wipe any grains left over from a PREVIOUS build before writing new ones.
    # Without this, rebuilding on a smaller/changed corpus_audio folder leaves
    # old grain_NNNNNN.npy files behind that nothing in the new index.json
    # references - orphaned data sitting in the one folder meant to hold
    # exactly what's needed to run again, nothing more.
    if os.path.isdir(grain_audio_dir):
        import shutil
        shutil.rmtree(grain_audio_dir)
    os.makedirs(grain_audio_dir, exist_ok=True)

    gid = 0
    for fp in files:
        try:
            wav = load_audio_mono(fp, codec.sample_rate)
        except Exception as e:
            sys.stderr.write("Skipping %s (%s)\n" % (fp, e))
            continue
        for (start, seg) in slice_grains(wav, codec.sample_rate,
                                         args.grain_ms, args.hop_ms):
            if np.abs(seg).max() < args.silence_floor:
                continue  # skip near-silent grains
            tokens = codec.encode(seg)
            feat = grain_feature(tokens, cb)
            peak_offset = grain_peak_offset(seg, codec.sample_rate)
            rms = float(np.sqrt(np.mean(seg.astype(np.float64) ** 2)))
            centroid = spectral_centroid_hz(seg, codec.sample_rate)
            # store the grain AUDIO so reconstruction uses real corpus material
            grain_path = os.path.join(grain_audio_dir, "grain_%06d.npy" % gid)
            np.save(grain_path, seg.astype(np.float32))
            grains_meta.append({
                "id": gid,
                "source_file": os.path.basename(fp),
                "start_s": round(start / codec.sample_rate, 4),
                "end_s": round((start + len(seg)) / codec.sample_rate, 4),
                "duration_s": round(len(seg) / codec.sample_rate, 4),
                "peak_offset_s": round(peak_offset / codec.sample_rate, 4),
                "rms": round(rms, 6),
                "centroid_hz": round(centroid, 2),
                "codec": codec.name,
                "grain_audio": grain_path,
            })
            feats.append(feat)
            gid += 1

    if not feats:
        sys.stderr.write("No grains produced (all silent or files unreadable).\n")
        sys.exit(2)

    feats = np.stack(feats).astype(np.float32)
    np.save(args.index + "_feats.npy", feats)
    with open(args.index + ".json", "w") as f:
        json.dump({
            "codec": codec.name,
            "sample_rate": codec.sample_rate,
            "codebook_size": cb,
            "grain_ms": args.grain_ms,
            "hop_ms": args.hop_ms,
            "n_grains": len(grains_meta),
            "feature_dim": int(feats.shape[1]),
            "grains": grains_meta,
        }, f, indent=1)
    sys.stdout.write("Built corpus index: %d grains from %d files -> %s.json\n"
                     % (len(grains_meta), len(files), args.index))


# ============================================================
# match subcommand (the main concatenative synthesis)
# ============================================================

def onset_place(placements, sr, total_len, xfade_ms):
    """Write each (onset_sample, grain_audio, peak_offset_sample) into an
    output buffer of fixed length `total_len`, so every matched corpus
    grain's own loudest moment - not just its buffer start - lands at the
    SAME sample position its source onset occurred.

    Why peak_offset matters: corpus grains are sliced from a blind fixed
    grid, so a grain's actual attack/transient is rarely at sample 0 of its
    own buffer - it might be 80% of the way through. Writing the grain
    starting exactly at the onset sample would put that attack noticeably
    AFTER the onset it was matched to, which is the real source of "no
    connection between input onsets and output" even once onset-aligned
    PLACEMENT (this function) is in place. The fix: shift the grain
    backward so peak_offset_sample lands exactly on onset_sample - i.e. the
    grain is written starting at (onset_sample - peak_offset_sample).

    Crossfading: each grain contributes through an equal-power window that
    fades IN over xfade_ms at its own written start (except the very first
    grain) and fades OUT over xfade_ms at its own written end (except the
    very last grain). Overlapping windows are simply summed.
    """
    out = np.zeros(total_len, dtype=np.float32)
    xf = max(0, int(round(xfade_ms / 1000.0 * sr)))
    n_g = len(placements)

    for k, (onset, g, peak_off) in enumerate(placements):
        g = g.astype(np.float32)
        if len(g) == 0:
            continue
        # shift so the grain's OWN peak lands on the onset, not its buffer
        # start; clamp to 0 so a peak near a grain's start at an early onset
        # doesn't ask for negative output indices
        write_start = max(0, onset - peak_off)
        if write_start >= total_len:
            continue

        avail = min(len(g), total_len - write_start)
        seg = g[:avail].copy()
        L = len(seg)
        if L <= 0:
            continue

        # cap each fade to at most half the grain's length so fade-in and
        # fade-out windows can't overlap each other within a short grain
        # (which would dip the middle below unity gain)
        fin = min(xf, L // 2) if k > 0 else 0
        fout = min(xf, L // 2) if k < n_g - 1 else 0

        if fin > 0:
            t = np.linspace(0.0, np.pi / 2.0, fin, dtype=np.float32)
            seg[:fin] *= np.sin(t)

        if fout > 0:
            t = np.linspace(0.0, np.pi / 2.0, fout, dtype=np.float32)
            seg[L - fout:] *= np.cos(t)

        out[write_start:write_start + L] += seg

    return out


def match(args):
    # load index
    with open(args.index + ".json") as f:
        index = json.load(f)
    feats = np.load(args.index + "_feats.npy")
    cb = index["codebook_size"]
    sr = index["sample_rate"]
    grains_meta = index["grains"]

    # codec must match the one the corpus was built with
    if index["codec"] != args.codec and args.codec != "auto":
        sys.stderr.write("Warning: corpus codec '%s' != requested '%s'; using corpus codec.\n"
                         % (index["codec"], args.codec))
    codec = make_codec(index["codec"])

    # load + encode the source selection
    src = load_audio_mono(args.input, codec.sample_rate)
    if len(src) < int(0.01 * sr):
        sys.stderr.write("Source selection too short (<10 ms).\n")
        sys.exit(3)

    # ---- ONSET-BOUNDED SEGMENTATION ----
    # Segments now run onset-to-onset in the SOURCE, instead of a fixed
    # grain_ms/hop_ms grid. This is what keeps each matched corpus grain
    # anchored to the same TIME its source transient occurred, rather than
    # wherever it happened to fall inside an arbitrary fixed window. Each
    # segment is further subdivided into independently-matched analysis
    # sub-windows below (subdivide_segment) - the onset boundaries found
    # here remain the only authoritative rhythm markers either way.
    src_grains = onset_segments(src, sr, args.onset_min_interval_ms)

    # precompute corpus norms for fast cosine, and corpus grain RMS for the
    # energy-similarity term (log scale: a grain at 0.003 vs source at 0.87
    # is a ~250x level gap that a LINEAR difference barely registers, since
    # both numbers are small in absolute terms - log-ratio makes that gap as
    # large as it actually sounds).
    corpus_norms = np.linalg.norm(feats, axis=1) + 1e-9
    has_rms = all("rms" in g for g in grains_meta)
    if has_rms:
        corpus_rms = np.array([g["rms"] for g in grains_meta], dtype=np.float64)
        corpus_log_rms = np.log(np.maximum(corpus_rms, 1e-6))
    else:
        # index built before the "rms" field existed - skip the energy term
        # entirely rather than guessing every grain is silent.
        sys.stderr.write(
            "Note: corpus index has no per-grain RMS data (built with an "
            "older version); energy-aware matching is disabled for this "
            "run. Rebuild the corpus index to enable it.\n")
        corpus_log_rms = None

    placements = []   # (onset_sample, grain_audio, peak_offset_sample) for onset_place
    used = []
    last_choice = -1
    # ---- SUB-WINDOW SUBDIVISION (within each onset segment) ----
    # A real decay/sustain tail isn't one static loop - its spectral content
    # keeps moving. Rather than matching ONE corpus grain to the whole
    # onset-to-onset segment, break each segment into a fine analysis grid
    # (subdivide_segment) and match every sub-window independently, so the
    # corpus material can follow the source as it evolves. The onset
    # boundary itself is untouched by this - only the FIRST sub-window of
    # each segment (the one starting exactly on the onset, carrying the
    # actual attack) gets peak-offset alignment; later sub-windows are just
    # filling forward continuously and are placed at their own buffer start.
    for (seg_start, seg) in src_grains:
        sub_windows = subdivide_segment(seg_start, seg, sr,
                                        args.analysis_grain_ms, args.analysis_hop_ms)
        for (start, sub, is_head) in sub_windows:
            sub_peak = float(np.abs(sub).max())
            if sub_peak < args.silence_floor:
                # Genuinely below the noise floor - this span of the SOURCE
                # was silent, so the OUTPUT should be silent here too.
                # Crucially we do NOT just skip/continue: that would drop
                # this sub-window out of `placements` entirely, leaving an
                # abrupt edge where the PREVIOUS grain's fade-out simply
                # stops with nothing to fade into - which is exactly what
                # reads as a noise-gate cutting in and out. Instead, place
                # an explicit silent grain of the same duration, so the
                # timeline has no holes and neighbouring fades resolve to
                # zero smoothly instead of hitting a wall.
                placements.append((start, np.zeros_like(sub), 0))
                used.append({
                    "src_start_s": round(start / sr, 4),
                    "src_duration_s": round(len(sub) / sr, 4),
                    "segment_head": is_head,
                    "corpus_grain_id": None,
                    "corpus_file": None,
                    "corpus_start_s": None,
                    "distance": None,
                })
                continue
            tokens = codec.encode(sub)
            q = grain_feature(tokens, cb)
            qn = np.linalg.norm(q) + 1e-9
            # cosine distance to every corpus grain (vectorised)
            sims = feats.dot(q) / (corpus_norms * qn)
            timbre_dist = 1.0 - sims

            # energy-similarity penalty: how far each corpus grain's
            # loudness is from THIS sub-window's loudness, in log space,
            # normalised to roughly the same [0, ~1+] scale as cosine
            # distance so one term can't trivially dominate the other
            # regardless of args.energy_weight.
            if corpus_log_rms is not None:
                sub_rms = float(np.sqrt(np.mean(sub.astype(np.float64) ** 2)))
                sub_log_rms = np.log(max(sub_rms, 1e-6))
                energy_dist = np.abs(corpus_log_rms - sub_log_rms) / 4.0  # ~4 nats spans the audible range
                dists = timbre_dist + args.energy_weight * energy_dist
            else:
                dists = timbre_dist
            # optional: discourage repeating the exact same grain back-to-back
            if args.repeat_penalty > 0 and 0 <= last_choice < len(dists):
                dists[last_choice] += args.repeat_penalty
            best = int(np.argmin(dists))
            last_choice = best
            g = np.load(grains_meta[best]["grain_audio"])
            # peak_offset_s may be absent on an index built before this
            # field existed; fall back to 0 (old behaviour: align buffer
            # start) rather than crashing on a stale corpus index. Only the
            # segment's HEAD sub-window gets the peak-offset shift at all -
            # later sub-windows tile forward continuously, and shifting them
            # backward to align a peak would reintroduce gaps/overlaps in
            # the timeline that subdividing was meant to avoid.
            if is_head:
                peak_off_s = grains_meta[best].get("peak_offset_s", 0.0)
                peak_off = int(round(peak_off_s * sr))
            else:
                peak_off = 0
            placements.append((start, g, peak_off))
            used.append({
                "src_start_s": round(start / sr, 4),
                "src_duration_s": round(len(sub) / sr, 4),
                "segment_head": is_head,
                "corpus_grain_id": grains_meta[best]["id"],
                "corpus_file": grains_meta[best]["source_file"],
                "corpus_start_s": grains_meta[best]["start_s"],
                "distance": round(float(dists[best]), 4),
            })

    if not placements:
        sys.stderr.write("No usable source grains (all silent?).\n")
        sys.exit(3)

    # Output buffer is pre-sized to the source length, so onset positions
    # are exact by construction - not the result of accumulating grain
    # lengths and hoping the total lines up.
    out = onset_place(placements, sr, len(src), args.xfade_ms)

    # preserve source duration as much as possible: trim/pad to source length
    # (onset_place already sizes to len(src), but match-duration=0 callers
    # may want the natural buffer length unmodified - this stays as a no-op
    # safety net in the common case)
    if args.match_duration:
        target_n = len(src)
        if len(out) > target_n:
            out = out[:target_n]
        elif len(out) < target_n:
            out = np.pad(out, (0, target_n - len(out)))

    write_audio(args.output, out, sr)

    # optional metadata (which corpus grains were used, and exactly when)
    if args.metadata:
        with open(args.metadata, "w") as f:
            json.dump({
                "codec": index["codec"],
                "sample_rate": sr,
                "n_onset_segments": len(src_grains),
                "n_sub_windows_used": len(used),
                "output_duration_s": round(len(out) / sr, 4),
                "grains": used,
            }, f, indent=1)

    # optional Praat TextGrid marking each grain's source file on a tier,
    # at its ACTUAL onset-aligned position (not evenly-spaced placeholder
    # intervals)
    if args.textgrid:
        write_textgrid(args.textgrid, used, sr, len(out))

    sys.stdout.write("Concatenative synthesis done: %d source onset(s), %d matched sub-window(s), %.2f s -> %s\n"
                     % (len(src_grains), len(used), len(out) / sr, args.output))


def read_realtier(path):
    """Parse a Praat RealTier text file into sorted (time, value) points.
    Returns (xmin, xmax, [(t, v), ...]). Tolerant of whitespace/ordering."""
    times = []
    values = []
    xmin = 0.0
    xmax = 1.0
    pending_t = None
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("xmin") and "=" in line and not times:
                try:
                    xmin = float(line.split("=")[1])
                except ValueError:
                    pass
            elif line.startswith("xmax") and "=" in line and pending_t is None and not times:
                try:
                    xmax = float(line.split("=")[1])
                except ValueError:
                    pass
            elif line.startswith("number") and "=" in line:
                try:
                    pending_t = float(line.split("=")[1])
                except ValueError:
                    pending_t = None
            elif line.startswith("value") and "=" in line and pending_t is not None:
                try:
                    v = float(line.split("=")[1])
                    times.append(pending_t)
                    values.append(v)
                except ValueError:
                    pass
                pending_t = None
    if not times:
        return xmin, xmax, []
    order = np.argsort(times)
    pts = [(float(times[i]), float(values[i])) for i in order]
    return xmin, xmax, pts


def draw(args):
    """Brightness-contour synthesis. A drawn RealTier curve (time -> level in
    roughly [0,1]) is sampled at a fixed grain rate; at each step the corpus
    grain whose (log) brightness best matches the drawn level is placed, then
    crossfaded. No input sound - the gesture is drawn, the corpus voices it."""
    with open(args.index + ".json") as f:
        index = json.load(f)
    sr = index["sample_rate"]
    grains_meta = index["grains"]

    if not all("centroid_hz" in g for g in grains_meta):
        sys.stderr.write(
            "This corpus index has no per-grain brightness data (built with an "
            "older version). Rebuild the corpus index to use draw mode.\n")
        sys.exit(4)

    # corpus brightness on a LOG axis, normalised to [0,1] so a drawn [0,1]
    # contour maps perceptually evenly across the corpus (pitch/brightness is
    # logarithmic - a linear-Hz axis would bunch most grains at the bottom).
    cents = np.array([max(g["centroid_hz"], 1e-6) for g in grains_meta])
    logc = np.log(cents)
    cmin, cmax = float(logc.min()), float(logc.max())
    bright = (logc - cmin) / (cmax - cmin + 1e-9)

    xmin, xmax, pts = read_realtier(args.tier)
    if len(pts) < 1:
        sys.stderr.write("Drawn curve has no points.\n")
        sys.exit(4)

    duration = args.duration if args.duration > 0 else (xmax - xmin)
    if duration <= 0:
        duration = 1.0

    # sample the drawn curve at the fixed grain rate (linear interp; clamp ends)
    pt_t = np.array([p[0] for p in pts])
    pt_v = np.array([p[1] for p in pts])
    # normalise drawn values to [0,1] using the curve's own range, so the
    # gesture's shape is what matters, not the absolute numbers the user drew
    vmin, vmax = float(pt_v.min()), float(pt_v.max())
    if vmax - vmin > 1e-9:
        pt_v = (pt_v - vmin) / (vmax - vmin)
    else:
        pt_v = np.full_like(pt_v, 0.5)

    step = max(0.001, args.grain_rate_ms / 1000.0)
    n_steps = max(1, int(round(duration / step)))

    placements = []
    used = []
    last_choice = -1
    for k in range(n_steps):
        t = k * step
        # drawn level at this time (map t back into the tier's own x-range)
        tier_t = xmin + (t / duration) * (xmax - xmin)
        level = float(np.interp(tier_t, pt_t, pt_v))
        # nearest-brightness grain
        dist = np.abs(bright - level)
        if args.repeat_penalty > 0 and 0 <= last_choice < len(dist):
            dist[last_choice] += args.repeat_penalty
        best = int(np.argmin(dist))
        last_choice = best
        g = np.load(grains_meta[best]["grain_audio"])
        onset = int(round(t * sr))
        placements.append((onset, g, 0))
        used.append({
            "src_start_s": round(t, 4),
            "src_duration_s": round(step, 4),
            "drawn_level": round(level, 4),
            "corpus_grain_id": grains_meta[best]["id"],
            "corpus_file": grains_meta[best]["source_file"],
            "corpus_start_s": grains_meta[best]["start_s"],
            "distance": round(float(dist[best]), 4),
        })

    total_len = int(round(duration * sr))
    out = onset_place(placements, sr, total_len, args.xfade_ms)
    write_audio(args.output, out, sr)

    if args.metadata:
        with open(args.metadata, "w") as f:
            json.dump({
                "mode": "draw",
                "codec": index["codec"],
                "sample_rate": sr,
                "n_steps": n_steps,
                "grain_rate_ms": args.grain_rate_ms,
                "output_duration_s": round(len(out) / sr, 4),
                "grains": used,
            }, f, indent=1)

    if args.textgrid:
        write_textgrid(args.textgrid, used, sr, len(out))

    sys.stdout.write("Draw synthesis done: %d grains over %.2f s -> %s\n"
                     % (n_steps, len(out) / sr, args.output))


def write_textgrid(path, used, sr, out_len):
    """Write a minimal TextGrid: one interval tier labelling each grain by its
    corpus source file, placed at its REAL onset-aligned position in the
    output (src_start_s / src_duration_s from `used`) - not evenly-spaced
    placeholder intervals. Gaps between detected onsets and the source
    selection's start/end are filled with empty intervals so the tier still
    covers [0, total] with no overlaps or holes.

    `used` entries are no longer guaranteed non-overlapping in time: when a
    segment gets subdivided into analysis sub-windows with
    analysis_hop_ms < analysis_grain_ms (the normal/default case), each
    sub-window's nominal [a, b) span overlaps the next sub-window's start,
    the same way slice_grains' overlapping grains always have. A TextGrid
    IntervalTier can't represent that (Praat requires each interval's xmin
    to equal the previous interval's xmax, no overlaps) - so every interval
    start is clamped forward to the current cursor before being written;
    only the genuinely non-overlapping head-of-segment boundaries ever
    trigger an explicit empty gap-filler interval below.
    """
    total = out_len / sr
    n = len(used)
    if n == 0:
        return

    intervals = []  # (xmin, xmax, label)
    cursor = 0.0
    for u in used:
        a = max(u["src_start_s"], cursor)
        b = round(u["src_start_s"] + u["src_duration_s"], 6)
        b = min(b, total)
        if b <= a + 1e-6:
            # Clamping ate the whole interval (this sub-window's span was
            # fully inside material already covered by the previous one) -
            # nothing left to represent on the tier, so skip it rather than
            # emit a zero/negative-length interval.
            continue
        if a > cursor + 1e-6:
            intervals.append((cursor, a, ""))
        if u["corpus_file"] is None:
            # Explicit silence placeholder (sub-window was below the
            # silence floor) - no corpus grain to label it with.
            label = ""
        else:
            label = "%s@%.2f" % (u["corpus_file"], u["corpus_start_s"])
            label = label.replace('"', "'")
        intervals.append((a, b, label))
        cursor = b
    if cursor < total - 1e-6:
        intervals.append((cursor, total, ""))

    lines = []
    lines.append('File type = "ooTextFile"')
    lines.append('Object class = "TextGrid"')
    lines.append("")
    lines.append("xmin = 0")
    lines.append("xmax = %.6f" % total)
    lines.append("tiers? <exists>")
    lines.append("size = 1")
    lines.append("item []:")
    lines.append("    item [1]:")
    lines.append('        class = "IntervalTier"')
    lines.append('        name = "grains"')
    lines.append("        xmin = 0")
    lines.append("        xmax = %.6f" % total)
    lines.append("        intervals: size = %d" % len(intervals))
    for i, (a, b, label) in enumerate(intervals):
        lines.append("        intervals [%d]:" % (i + 1))
        lines.append("            xmin = %.6f" % a)
        lines.append("            xmax = %.6f" % b)
        lines.append('            text = "%s"' % label)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


# ============================================================
# gesture-rhyme subcommand
#   "Compositional Gestural Rhyming - Exploiting Hashed Bigrams"
#
#   Re-voices an abstract KINETIC gesture (accelerating clicks, a bouncing
#   ball, an explosive attack decaying into hiss, a microtonal dive, tremolo
#   flutter, ...) using corpus grains whose codec-token TRANSITION structure
#   rhymes with the source - NOT whose timbre matches. The match is driven by
#   the hashed-bigram section of the feature with a high bigram weight and a
#   low histogram weight, so a click-train source can be voiced by speech
#   syllables, field recordings, or instrument noises that simply MOVE the
#   same way frame-to-frame.
#
#   Reuses the existing onset segmentation, sub-window subdivision, peak-
#   aligned onset_place reconstruction, and TextGrid writer. The corpus index
#   is loaded read-only - this mode never builds or reslices the corpus.
#
#   FEATURE-COMPATIBILITY NOTE (existing indexes):
#   The stored corpus feature matrix was written by build_corpus with the
#   DEFAULT grain_feature weights (hist_weight=1, bigram_weight=1) and the
#   raw tokens are NOT stored. grain_feature lays each row out as
#       [ histogram (n_codebooks * codebook_size) | bigrams (64 buckets) ]
#   so the bigram section is always the trailing N_BIGRAM_BUCKETS columns.
#   We therefore SPLIT each stored row into its histogram and bigram sections
#   and re-apply (hist_weight, bigram_weight) at match time, exactly mirroring
#   how grain_feature weights the freshly-encoded source. No rebuild needed.
# ============================================================

N_BIGRAM_BUCKETS = 64   # must match token_bigrams' default n_buckets


def gesture_rhyme(args):
    # ---- Load index (read-only; never built or resliced here) ----
    json_path = args.index + ".json"
    feats_path = args.index + "_feats.npy"
    if not os.path.isfile(json_path):
        sys.stderr.write("ERROR: corpus index not found: %s\n"
                         "Build a corpus index first (build-corpus); "
                         "gesture-rhyme never builds one.\n" % json_path)
        sys.exit(2)
    if not os.path.isfile(feats_path):
        sys.stderr.write("ERROR: corpus feature matrix not found: %s\n"
                         "The index JSON exists but its _feats.npy is missing; "
                         "rebuild the corpus index.\n" % feats_path)
        sys.exit(2)

    with open(json_path) as f:
        index = json.load(f)
    feats = np.load(feats_path)
    cb = index["codebook_size"]
    sr = index["sample_rate"]
    grains_meta = index["grains"]
    feature_dim = int(feats.shape[1])

    # ---- Feature-layout compatibility: split into hist | bigram sections ----
    hist_dim = feature_dim - N_BIGRAM_BUCKETS
    if hist_dim <= 0:
        sys.stderr.write(
            "ERROR: corpus feature layout is incompatible with gesture-rhyme.\n"
            "Expected [histogram | %d bigram buckets] but feature_dim=%d leaves "
            "no histogram section. Rebuild the index with this codec.\n"
            % (N_BIGRAM_BUCKETS, feature_dim))
        sys.exit(2)

    bigram_weight = float(args.bigram_weight)
    hist_weight = float(args.hist_weight)
    energy_weight = float(args.energy_weight)
    seq_context = max(0, int(args.sequence_context))

    # Re-weight the stored corpus features by section (the stored rows used
    # weights 1.0/1.0, so multiplying each section IS the reweighting).
    corpus_hist = feats[:, :hist_dim]
    corpus_bg = feats[:, hist_dim:]
    weighted_corpus = np.concatenate(
        [corpus_hist * hist_weight, corpus_bg * bigram_weight], axis=1
    ).astype(np.float32)
    corpus_norms = np.linalg.norm(weighted_corpus, axis=1) + 1e-9

    # codec is dictated by the corpus (warn, like match, if the request differs)
    if index["codec"] != args.codec and args.codec != "auto":
        sys.stderr.write("Warning: corpus codec '%s' != requested '%s'; "
                         "using corpus codec.\n"
                         % (index["codec"], args.codec))
    codec = make_codec(index["codec"])

    # ---- Load + check the source gesture ----
    src = load_audio_mono(args.input, codec.sample_rate)
    if len(src) < int(0.01 * sr):
        sys.stderr.write("Source gesture too short (<10 ms).\n")
        sys.exit(3)

    src_grains = onset_segments(src, sr, args.onset_min_interval_ms)

    # per-grain RMS for the (low-weighted) energy term, log scale - same as match
    has_rms = all("rms" in g for g in grains_meta)
    if has_rms:
        corpus_rms = np.array([g["rms"] for g in grains_meta], dtype=np.float64)
        corpus_log_rms = np.log(np.maximum(corpus_rms, 1e-6))
    else:
        sys.stderr.write(
            "Note: corpus index has no per-grain RMS data (older build); "
            "energy term disabled for this gesture-rhyme run.\n")
        corpus_log_rms = None

    placements = []   # (onset_sample, grain_audio, peak_offset_sample)
    used = []
    last_choice = -1
    context_buf = []  # rolling weighted source features for --sequence-context

    for (seg_start, seg) in src_grains:
        sub_windows = subdivide_segment(seg_start, seg, sr,
                                        args.analysis_grain_ms,
                                        args.analysis_hop_ms)
        for (start, sub, is_head) in sub_windows:
            sub_peak = float(np.abs(sub).max())
            if sub_peak < args.silence_floor:
                # explicit silence placeholder (no holes in the timeline) and
                # reset the sequence context so kinetics don't bleed across a gap
                placements.append((start, np.zeros_like(sub), 0))
                used.append(_gr_used_entry(start, sub, sr, is_head, None,
                                           None, None, None, None, None, None,
                                           bigram_weight, hist_weight,
                                           energy_weight))
                context_buf = []
                continue

            tokens = codec.encode(sub)
            q = grain_feature(tokens, cb, hist_weight, bigram_weight)

            # --- sequence context: average over the last (seq_context+1)
            # weighted sub-window features, privileging SUSTAINED transition
            # structure over a single isolated window ---
            context_buf.append(q)
            if len(context_buf) > seq_context + 1:
                context_buf.pop(0)
            q_match = np.mean(np.stack(context_buf), axis=0) if len(context_buf) > 1 else q
            qn = np.linalg.norm(q_match) + 1e-9

            # kinetic (bigram-dominant) cosine distance to every corpus grain
            sims = weighted_corpus.dot(q_match) / (corpus_norms * qn)
            gesture_dist = 1.0 - sims

            if corpus_log_rms is not None:
                sub_rms = float(np.sqrt(np.mean(sub.astype(np.float64) ** 2)))
                sub_log_rms = np.log(max(sub_rms, 1e-6))
                energy_dist = np.abs(corpus_log_rms - sub_log_rms) / 4.0
                dists = gesture_dist + energy_weight * energy_dist
            else:
                energy_dist = None
                dists = gesture_dist

            if args.repeat_penalty > 0 and 0 <= last_choice < len(dists):
                dists[last_choice] += args.repeat_penalty

            best = int(np.argmin(dists))
            last_choice = best

            # per-component contributions for the chosen grain (interpretable:
            # gesture/bigram should match well even when timbre/hist does not)
            q_hist, q_bg = q_match[:hist_dim], q_match[hist_dim:]
            c_hist = weighted_corpus[best, :hist_dim]
            c_bg = weighted_corpus[best, hist_dim:]
            timbre_contrib = cosine_distance(q_hist, c_hist)
            gesture_contrib = cosine_distance(q_bg, c_bg)
            energy_contrib = (float(energy_weight * energy_dist[best])
                              if energy_dist is not None else None)

            # load the chosen grain's audio (fail clearly if it's missing)
            gp = grains_meta[best]["grain_audio"]
            if not os.path.isfile(gp):
                sys.stderr.write(
                    "ERROR: corpus grain audio missing: %s\n"
                    "(referenced by grain id %s in %s). The index is "
                    "incomplete; rebuild the corpus.\n"
                    % (gp, grains_meta[best]["id"], json_path))
                sys.exit(2)
            g = np.load(gp)

            # head sub-window carries the attack -> peak-align it to the onset;
            # later sub-windows tile forward continuously (peak_off = 0)
            if is_head:
                peak_off = int(round(grains_meta[best].get("peak_offset_s", 0.0) * sr))
            else:
                peak_off = 0
            placements.append((start, g, peak_off))
            used.append(_gr_used_entry(
                start, sub, sr, is_head,
                grains_meta[best]["id"], grains_meta[best]["source_file"],
                grains_meta[best]["start_s"], round(float(dists[best]), 4),
                round(timbre_contrib, 4), round(gesture_contrib, 4),
                (round(energy_contrib, 4) if energy_contrib is not None else None),
                bigram_weight, hist_weight, energy_weight))

    if not placements:
        sys.stderr.write("No usable source material (gesture all silent?).\n")
        sys.exit(3)

    out = onset_place(placements, sr, len(src), args.xfade_ms)
    if args.match_duration:
        target_n = len(src)
        if len(out) > target_n:
            out = out[:target_n]
        elif len(out) < target_n:
            out = np.pad(out, (0, target_n - len(out)))

    write_audio(args.output, out, sr)

    if args.metadata:
        with open(args.metadata, "w") as f:
            json.dump({
                "mode": "gesture-rhyme",
                "codec": index["codec"],
                "sample_rate": sr,
                "bigram_weight": bigram_weight,
                "hist_weight": hist_weight,
                "energy_weight": energy_weight,
                "sequence_context": seq_context,
                "n_onset_segments": len(src_grains),
                "n_sub_windows_used": len(used),
                "output_duration_s": round(len(out) / sr, 4),
                "grains": used,
            }, f, indent=1)

    if args.textgrid:
        write_textgrid(args.textgrid, used, sr, len(out))

    sys.stdout.write(
        "Gesture rhyme done: %d source onset(s), %d matched sub-window(s), "
        "%.2f s -> %s\n"
        % (len(src_grains), len(used), len(out) / sr, args.output))


def _gr_used_entry(start, sub, sr, is_head, grain_id, corpus_file,
                   corpus_start_s, distance, timbre_contrib, gesture_contrib,
                   energy_contrib, bigram_weight, hist_weight, energy_weight):
    """One metadata record per matched sub-window. Keeps the keys
    write_textgrid needs (src_start_s, src_duration_s, corpus_file,
    corpus_start_s) plus the gesture-rhyme provenance fields, so it's possible
    to study which UNRELATED corpus grains voiced each abstract gesture."""
    return {
        "src_start_s": round(start / sr, 4),
        "src_duration_s": round(len(sub) / sr, 4),
        "segment_head": is_head,
        "corpus_grain_id": grain_id,
        "corpus_file": corpus_file,
        "corpus_start_s": corpus_start_s,
        "distance": distance,
        "timbre_contribution": timbre_contrib,
        "gesture_contribution": gesture_contrib,
        "energy_contribution": energy_contrib,
        "bigram_weight": bigram_weight,
        "hist_weight": hist_weight,
        "energy_weight": energy_weight,
    }


# ============================================================
# CLI
# ============================================================

def main():
    # Shared by both subcommands: where to mirror stderr output (replaces the
    # old shell "2> file" redirect, which doesn't exist when called via
    # Praat's runSubprocess).
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--log", default=None,
                         help="optional path to mirror all stderr/error output to")

    p = argparse.ArgumentParser(description="Corpus-based concatenative synthesis via neural codec tokens")
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build-corpus", parents=[common], help="slice + encode a target corpus into an index")
    b.add_argument("--codec", default="mock", help="encodec | dac | mock")
    b.add_argument("--corpus-audio", required=True,
                   help="file(s)/dir(s) of target audio, os.pathsep-separated")
    b.add_argument("--index", required=True, help="output index path prefix")
    b.add_argument("--grain-ms", type=float, default=150.0)
    b.add_argument("--hop-ms", type=float, default=75.0)
    b.add_argument("--silence-floor", type=float, default=1e-3)
    b.set_defaults(func=build_corpus)

    m = sub.add_parser("match", parents=[common], help="encode source, match corpus, reconstruct")
    m.add_argument("--codec", default="auto", help="encodec | dac | mock | auto")
    m.add_argument("--input", required=True, help="source WAV from Praat")
    m.add_argument("--output", required=True, help="output WAV")
    m.add_argument("--index", required=True, help="corpus index path prefix")
    m.add_argument("--metadata", default=None, help="optional JSON metadata path")
    m.add_argument("--textgrid", default=None, help="optional TextGrid path")
    m.add_argument("--xfade-ms", type=float, default=20.0)
    m.add_argument("--repeat-penalty", type=float, default=0.05)
    m.add_argument("--energy-weight", type=float, default=1.0,
                   help="weight of the loudness-similarity term in grain matching "
                        "(0 = pure timbre matching, like before; higher = stronger "
                        "preference for corpus grains matching the source's loudness)")
    m.add_argument("--silence-floor", type=float, default=1e-4,
                   help="peak amplitude below which a source segment is treated as "
                        "true silence (explicitly placed as silence, not dropped) "
                        "rather than matched against the corpus. Lowered from the "
                        "build-side default since this now gates whether quiet "
                        "passages get represented at all.")
    m.add_argument("--onset-min-interval-ms", type=float, default=60.0,
                   dest="onset_min_interval_ms",
                   help="minimum spacing between detected source onsets (ms)")
    m.add_argument("--analysis-grain-ms", type=float, default=60.0,
                   help="size (ms) of the internal analysis sub-window used to "
                        "subdivide each onset-bounded segment for matching. "
                        "Separate from build-corpus's --grain-ms: this only "
                        "controls how finely a segment's evolving decay/sustain "
                        "is re-matched against the corpus after the onset; it "
                        "never moves the onset boundary itself.")
    m.add_argument("--analysis-hop-ms", type=float, default=30.0,
                   help="hop (ms) between analysis sub-windows within a segment; "
                        "hop < analysis-grain-ms means overlapping analysis "
                        "windows (smoother tracking of the decay), same shape as "
                        "build-corpus's grain/hop relationship")
    m.add_argument("--match-duration", type=int, default=1,
                   help="1 = trim/pad output to source duration")
    m.set_defaults(func=match)

    dr = sub.add_parser("draw", parents=[common],
                        help="brightness-contour synthesis from a drawn RealTier")
    dr.add_argument("--tier", required=True, help="RealTier text file (drawn curve)")
    dr.add_argument("--output", required=True, help="output WAV")
    dr.add_argument("--index", required=True, help="corpus index path prefix")
    dr.add_argument("--metadata", default=None, help="optional JSON metadata path")
    dr.add_argument("--textgrid", default=None, help="optional TextGrid path")
    dr.add_argument("--duration", type=float, default=0.0,
                    help="output duration (s); 0 = use the tier's own xmax")
    dr.add_argument("--grain-rate-ms", type=float, default=80.0,
                    help="place one grain every N ms along the drawn curve")
    dr.add_argument("--xfade-ms", type=float, default=20.0)
    dr.add_argument("--repeat-penalty", type=float, default=0.05)
    dr.set_defaults(func=draw)

    gr = sub.add_parser("gesture-rhyme", parents=[common],
                        help="re-voice an abstract gesture by codec-token "
                             "transition (hashed-bigram) rhyming")
    gr.add_argument("--codec", default="auto", help="encodec | dac | mock | auto")
    gr.add_argument("--input", required=True, help="source gesture WAV from Praat")
    gr.add_argument("--output", required=True, help="output WAV")
    gr.add_argument("--index", required=True,
                    help="EXISTING corpus index prefix (never built here)")
    gr.add_argument("--metadata", default=None, help="optional JSON metadata path")
    gr.add_argument("--textgrid", default=None, help="optional TextGrid path")
    gr.add_argument("--bigram-weight", type=float, default=4.0,
                    help="weight of the hashed-bigram (token-transition) section; "
                         "high by default so kinetic motion drives the match")
    gr.add_argument("--hist-weight", type=float, default=0.5,
                    help="weight of the token-histogram (timbre) section; low by "
                         "default so literal tone-colour is de-emphasised")
    gr.add_argument("--energy-weight", type=float, default=0.2,
                    help="weight of the log-RMS loudness term; low by default so "
                         "energy can't dominate the kinetic bigram match")
    gr.add_argument("--analysis-grain-ms", type=float, default=60.0)
    gr.add_argument("--analysis-hop-ms", type=float, default=30.0)
    gr.add_argument("--onset-min-interval-ms", type=float, default=60.0,
                    dest="onset_min_interval_ms")
    gr.add_argument("--repeat-penalty", type=float, default=0.05)
    gr.add_argument("--xfade-ms", type=float, default=20.0)
    gr.add_argument("--match-duration", type=int, default=1,
                    help="1 = trim/pad output to source duration")
    gr.add_argument("--sequence-context", type=int, default=0,
                    dest="sequence_context",
                    help="average source features over this many PRECEDING "
                         "sub-windows (0 = independent windows); >0 privileges "
                         "sustained transition structure over isolated windows")
    gr.add_argument("--silence-floor", type=float, default=1e-4)
    gr.set_defaults(func=gesture_rhyme)

    args = p.parse_args()
    _install_log_tee(getattr(args, "log", None))
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # Land the crash dump wherever --log pointed (so it stays alongside
        # the other run artefacts the caller chose); fall back to next to
        # the script itself if --log wasn't given.
        crash_dir = _LOG_DIR or os.path.dirname(os.path.abspath(__file__))
        crash = os.path.join(crash_dir, "corpus_concat_crash.txt")
        try:
            with open(crash, "w") as f:
                f.write(traceback.format_exc())
        except Exception:
            pass
        sys.stderr.write("ERROR:\n" + traceback.format_exc() + "\n")
        sys.exit(1)
