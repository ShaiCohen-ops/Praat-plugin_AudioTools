#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - corpus_concat_codec.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.8.3 (2026)
#   v1.8.3: "@file" argument files (one argument per line, UTF-8 or UTF-16 as
#   Praat writes them). Root cause of the Windows Polyphonic Layers failure:
#   the child process received only the first 1024 characters of its command
#   line, so --result was cut to "C:/Users/User/A" and --log was lost; mode 6
#   now passes its arguments through a file.
# Version: 1.8.2 (2026)
#   v1.8.2: a missing stdout/stderr (GUI Praat on Windows, plain runSubprocess)
#   is replaced by a null sink instead of crashing the final status print.
#   polyphonic-layers reports failures as "status error" in its result file
#   and exits 0, and echoes the absolute paths of its result, log and voice
#   files (with existence) on stdout for the front-end's diagnostics.
# Version: 1.8.1 (2026)
#   v1.8.1: "-" is accepted as "no file" for optional path arguments
#   (--textgrid, --metadata, --export-dir, --result, --contour-out, ...), and
#   the log is opened before argument parsing. Praat's runSubprocess on Windows
#   drops EMPTY arguments, so "--export-dir ''" became "--export-dir
#   --export-name ..." and argparse exited before any log existed - reported
#   as "Polyphonic Layers failed - the backend produced no result" with an empty
#   Info window. The same latent fault hit every mode with Import TextGrid off.
# Version: 1.8.0 (2026)
#   v1.8.0: new subcommand polyphonic-layers ("Corpus Polyphonic Layers"): the
#   whole source phrase is analysed over time (step grid = corpus hop; level,
#   relative loudness, brightness, band shape + codec latent, spectral change,
#   F0/periodicity, onset density, presence with hysteresis; fast/slow masked
#   smoothing, direction of change, rest/sustained/active segmentation) and
#   1-3 sample-aligned voices are planned through the EXISTING transition
#   graph (schema 3, unchanged) with cost = transition + source relationship
#   (parallel / complementary / independent targets and weights) + voice
#   trajectory + inter-voice interaction (same grain / same passage /
#   delayed copy / similar timbre, activity, brightness - scaled by
#   diversity) + repetition + jump cost. Sequential conditioning plus an
#   optional refinement sweep; per-voice SeedSequence streams. Voices are
#   rendered with the continuation's Tukey OLA, resampled to the source rate,
#   level-matched to the source's active RMS, written as 32-bit float WAV of
#   exactly N samples; optional float DAW stems with a no-overwrite policy.
#   Corpus schema 3 and graph schema 3 unchanged; continuation-tail and all
#   other subcommands untouched (bit-identical output verified against 1.7.4).
# Version: 1.7.4 (2026)
#   v1.7.4 (from a listening test with a DAC corpus at 44.1 kHz):
#   (1) BUG: chronological links were tested with a fixed 3-sample tolerance,
#   but start_s is stored rounded to 0.1 ms (up to 4.4 samples of error in a
#   difference at 44.1 kHz) -> ~11 % of genuine "next grain" links were lost
#   and treated as jumps (re-aligned and level-corrected mid-flow). Tolerance
#   is now 2 % of the hop. Mock tests ran at 24 kHz and could not show it.
#   (2) Rate-of-change control: jumps cost extra at the start of the tail
#   (decaying over it) and a second jump within 0.3 s costs more, so the
#   continuation first sustains like the source; Textural's push for variety
#   ramps in gradually. (3) --normalize loudness: tail body matched to the
#   phrase's active loudness and its peaks capped at the source peak, so the
#   front-end's single common gain never attenuates the source.
#   Graph schema 2 -> 3 (rebuilt automatically).
# Version: 1.7.3 (2026)
#   v1.7.3: the continuation result file also reports source_active_rms (median
#   RMS of the phrase's active 10 ms frames) and tail_body_rms (RMS of the new
#   material where its envelope is >= 0.5), used by the Praat front-end's
#   optional loudness normalisation.
# Version: 1.7.2 (2026)
#   v1.7.2: tail level (user report: "the add-on is weak, power imbalances").
#   The tail was matched to the source's faded END level and kept the corpus
#   grains' own level swings (15-25 dB), and exp-decay fell 43 dB over the
#   tail. Now: --tail-level phrase (default) settles at the phrase's median
#   active level, rising from the join level over 0.3 s (ending = previous
#   behaviour); a slow levelling stage removes 75 % of the grain-to-grain
#   level swings (boost <= +12 dB, ~100 ms smoothing) before the envelope;
#   exp-decay / tremolo-decay are gentler (-26 dB over the tail).
# Version: 1.7.1 (2026)
#   v1.7.1 fix pass after a real flute test ("noise at the end instead of a
#   continuation"). Cause: a voiced->unvoiced transition cost a flat 0.15
#   while a pitch difference cost up to 4.0, so with no same-pitch material in
#   the corpus a tonal ending was continued by noise; the terminal state was
#   also read from the faint release near the noise floor, and the tail could
#   be boosted by up to +18 dB. Fixes: (1) _pitch_cost = tonal term
#   |periodicity a - b| + pitch distance capped at one octave (voiced pairs
#   only); tonal/pitch weight raised and used in candidate permissibility (it
#   used to filter on spectral shape alone, removing every pitched grain
#   before tonality was weighed); in Textural it decays over the tail. (2)
#   Terminal state from the last STRONG sound (>= 15 dB above the noise
#   floor); level match still at the true end. (3) A pitched quiet release is
#   sound: analysis end extends through it and trimming refuses any trailing
#   material with clear periodicity. (4) Grains > 30 dB below their own
#   recording are background - never a start or jump target. (5) Tail boost
#   limited to +12 dB. (6) Energy continuity weight doubled. (7) The grain
#   that meets the source is always the best match, also in Textural.
#   Graph schema 1 -> 2 (existing graph caches rebuild automatically).
# Version: 1.7 (2026)
#   v1.7: new subcommand continuation-tail (+ continuation-graph). Analyses the
#   terminal state of a source phrase (activity end with hysteresis, terminal
#   window, trajectory slopes, YIN pitch, codec latent + spectral descriptors,
#   categorical token feature) and plans a grain sequence over a cached
#   CORPUS TRANSITION GRAPH: genuine chronological links (same recording,
#   exactly one hop apart) plus boundary-matched cross edges retrieved with a
#   sub-quadratic inverted-file nearest-neighbour index and re-ranked.
#   Tight mode = deterministic chain-following with graded switching; Textural
#   = seeded top-K sampling with decaying source attachment. Writes ONLY the
#   tail buffer (32-bit float, the source's own rate, exact length) and a
#   key/value result file - the Praat front-end performs the join so the
#   original samples are untouched. Graph cache = separately versioned sidecar
#   (<index>_graph.json/.npz, graph schema 1) bound to the index JSON hash;
#   corpus schema_version stays 3. build-corpus additionally records optional
#   per-grain source_uid / source_index / real_samples (backward compatible).
#   Codec adapters gained latent_from_tokens() (EnCodec quantizer.decode, DAC
#   quantizer.from_codes), verified at graph build with a spectral fallback.
#   Existing match / draw / gesture-rhyme / build-corpus paths are unchanged
#   apart from _load_corpus_index's optional mmap flag (default off).
# Version: 1.6 (2026)
#   v1.6: Draw contours are now serializable and reloadable. Draw accepts either
#   a Praat RealTier (--tier, backward compatible) or a compact human-readable
#   contour file (--contour). The exact normalized time->brightness trajectory
#   actually used by the synthesis can be written with --contour-out, making
#   Draw runs reproducible and suitable for batch processing / gesture libraries.
# Version: 1.5 (2026)
#   v1.5: build-corpus gained optional --atomic transactional replacement.
#   A new corpus is built completely in a staging directory and only promoted
#   over the live index after JSON, feature matrix, and grain folder all exist.
#   If encoding/building fails, the previous successful corpus remains intact.
#   The index also records the user-supplied corpus_audio specification.
# Version: 1.4 (2026)
#   v1.4 fix pass: per-codebook bigram bucketing (was pooling all codebooks
#   into 64 shared, alias-prone buckets - see token_bigrams); onset
#   peak-picking now finds the true rise-maximum in each candidate run
#   instead of the first frame to cross threshold; silence placeholders now
#   actually truncate any earlier grain's tail that would otherwise bleed
#   through them; corpus indexes store grain paths relative to the index
#   folder (portable across machines) plus schema_version/provenance
#   metadata; gesture-rhyme's --sequence-context is documented accurately as
#   context SMOOTHING (an unordered mean, not an order-aware sequence
#   model) and gained a --random-baseline ablation condition; weight/penalty
#   CLI args reject negative values; metadata field names
#   (histogram_distance/bigram_distance/weighted_energy_distance/
#   combined_distance) reflect what they actually are instead of implying
#   they sum to a total.
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
#   into a fine grid of analysis sub-windows, encodes each sub-window into
#   codec tokens, compares against a pre-encoded corpus of grains using BOTH
#   timbre (cosine distance on token features) and loudness (log-RMS
#   similarity), then places each matched corpus grain's own loudest moment
#   exactly on the source onset its segment started from. This is what
#   keeps the OUTPUT's rhythm locked to the INPUT's rhythm: source onset
#   times drive where things happen, corpus material determines what they
#   sound like. Source onsets define the macro-articulatory skeleton, while
#   the analysis hop introduces a SECONDARY corpus-mosaic articulation
#   within each onset-bounded segment - every sub-window (not just the
#   onset-aligned head) independently selects and places its OWN corpus
#   grain, so subdivision is not merely internal bookkeeping for matching:
#   a decaying/evolving span of source audio is no longer forced to sound
#   like ONE static corpus grain for its whole duration, it is re-voiced by
#   a sequence of them. The output WAV is read back into Praat.
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
# Feature schema version
#   Bumped whenever the on-disk feature vector LAYOUT changes (bucket
#   counts, hash function, section ordering, etc) in a way that makes an
#   old index's _feats.npy numerically incompatible with a freshly-encoded
#   query vector. v3 bumps this because BIGRAM_BUCKETS_PER_CODEBOOK changed
#   (256 -> 1021) and the bigram hash function changed (see token_bigrams) -
#   both change every bigram feature's dimensionality/meaning, so indexes
#   built under v2 or earlier are NOT reinterpretable and must be rebuilt.
#   See _load_corpus_index: match/gesture-rhyme now HARD-FAIL on a mismatch
#   instead of silently guessing a legacy layout.
# ============================================================
CURRENT_SCHEMA_VERSION = 3


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
    # v1.7: True when latent_from_tokens() can map a token matrix back to the
    # codec's own QUANTIZED continuous latent (the vectors its decoder
    # consumes). Used by the continuation graph for boundary descriptors.
    # Token IDs themselves are never treated as numbers.
    has_latent = False

    def latent_from_tokens(self, tokens):
        """tokens [n_codebooks, n_frames] int -> float32 [latent_dim, n_frames]."""
        raise NotImplementedError

    def latent_decode_check(self, tokens):
        """Return (wav_via_latent, wav_via_decode) so the latent path can be
        verified against the adapter's normal decode() - see
        verify_codec_latent()."""
        raise NotImplementedError

    def encode(self, wav):
        raise NotImplementedError

    def decode(self, tokens):
        raise NotImplementedError

    def provenance(self):
        """Extra codec-specific fields to fold into the corpus index JSON,
        beyond name/sample_rate/codebook_size (which every adapter already
        exposes). Lets a corpus index be traced back to the exact model
        configuration and package version that produced its tokens."""
        return {}


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
        self.bandwidth = bandwidth

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

    has_latent = True

    def latent_from_tokens(self, tokens):
        # EnCodec's RVQ: quantizer.decode takes codes as [n_q, B, T] and
        # returns the summed codebook embeddings [B, D, T] (D = 128) - the
        # exact tensor model.decoder() turns back into audio.
        torch = self.torch
        codes = torch.from_numpy(np.asarray(tokens)).long().unsqueeze(0)  # [1, n_q, T]
        with torch.no_grad():
            emb = self.model.quantizer.decode(codes.transpose(0, 1))
        return emb.squeeze(0).cpu().numpy().astype(np.float32)

    def latent_decode_check(self, tokens):
        torch = self.torch
        lat = torch.from_numpy(self.latent_from_tokens(tokens)).float().unsqueeze(0)
        with torch.no_grad():
            via_latent = self.model.decoder(lat)
        return (via_latent.squeeze().cpu().numpy().astype(np.float32),
                self.decode(tokens))

    def provenance(self):
        try:
            import importlib.metadata as _im
            pkg_version = _im.version("encodec")
        except Exception:
            pkg_version = None
        return {
            "encodec_bandwidth": self.bandwidth,
            "encodec_package_version": pkg_version,
        }


class DACAdapter(CodecAdapter):
    name = "dac"

    def __init__(self, model_type="44khz"):
        import torch
        import dac
        self.torch = torch
        self.model_type = model_type
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

    has_latent = True

    def latent_from_tokens(self, tokens):
        # DAC: quantizer.from_codes returns (z_q, z_p, codes); z_q [B, D, T]
        # (D = 1024 for the 44 kHz model) is what model.decode() consumes.
        torch = self.torch
        codes = torch.from_numpy(np.asarray(tokens)).long().unsqueeze(0)
        with torch.no_grad():
            z, _, _ = self.model.quantizer.from_codes(codes)
        return z.squeeze(0).cpu().numpy().astype(np.float32)

    def latent_decode_check(self, tokens):
        torch = self.torch
        z = torch.from_numpy(self.latent_from_tokens(tokens)).float().unsqueeze(0)
        with torch.no_grad():
            via_latent = self.model.decode(z)
        return (via_latent.squeeze().cpu().numpy().astype(np.float32),
                self.decode(tokens))

    def provenance(self):
        try:
            import importlib.metadata as _im
            pkg_version = _im.version("descript-audio-codec")
        except Exception:
            pkg_version = None
        return {
            "dac_model_type": self.model_type,
            "dac_package_version": pkg_version,
        }


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


BIGRAM_BUCKETS_PER_CODEBOOK = 1021  # per-codebook bucket count (see token_bigrams)
# ^ MUST be prime (or at least not a power of two) - see the mod-256
# aliasing bug this replaces, documented in token_bigrams below. 1021 is the
# largest prime under 1024, chosen so a 1024-symbol codebook (1024*1024 =
# 1,048,576 possible ordered token pairs) gets far less lossy bucketing than
# the previous 256 (~4096 possible pairs colliding per bucket on average)
# while keeping the feature vector a small, fixed size.

_MIN_TOKEN_FRAMES_WARN = 3  # below this, a sub-window has <=2 bigram
                             # transitions per codebook - not enough for the
                             # bigram section to be meaningfully populated

_MASK64 = 0xFFFFFFFFFFFFFFFF


def _mix64(h):
    """Avalanche finalizer mix (murmur3/splitmix64-style) so every output
    bit depends on ALL of the input's bits before we reduce mod n_buckets.
    A bare multiply-and-add hash can still leave high input bits poorly
    mixed into the low output bits a modulo actually keeps - this closes
    that gap."""
    h &= _MASK64
    h ^= h >> 33
    h = (h * 0xFF51AFD7ED558CCD) & _MASK64
    h ^= h >> 33
    h = (h * 0xC4CEB9FE1A85EC53) & _MASK64
    h ^= h >> 33
    return h


def token_bigrams(tokens, n_buckets_per_codebook=BIGRAM_BUCKETS_PER_CODEBOOK):
    """Hashed bigram transition counts, kept SEPARATE per codebook and hashed
    into a bucket count large enough that collisions are the exception, not
    the representation.

    Three things the previous version got wrong, all fixed here:
      1. All codebooks were pooled into the SAME 64 cells, so a grain's
         codebook identity was destroyed before matching ever happened.
         (Fixed in the prior pass: each codebook now gets its own
         contiguous slice of n_buckets_per_codebook cells.)
      2. The hash was `(t1*131 + t2) % 64`. Since 131 % 64 == 3, the result
         depended only on (t1*3 + t2) % 64 - i.e. on token IDs' low-order
         residues mod 64, not on the tokens themselves.
      3. The REPLACEMENT for #2 still had a live version of the same bug:
         `h % 256` with a 256-bucket (power-of-two) modulus. For ANY
         multiplier, odd or not, (t1*C) mod 2^k depends only on t1 mod 2^k
         (multiplying by an odd constant is a bijection mod 2^k that never
         touches bits above position k). So [1,2,3,4] and
         [257,258,259,260] - which differ by exactly 256 in every token -
         hashed IDENTICALLY under the 256-bucket version despite sharing no
         token. Fixed two ways at once: n_buckets_per_codebook is now 1021,
         a PRIME (mod-prime does not have the power-of-two
         low-bits-only property), and the raw multiply-add hash is passed
         through a real 64-bit avalanche mix (_mix64) before the modulo, so
         a collision now requires an actual coincidence in the full mixed
         hash rather than a fixed additive offset.
    """
    n_cb = tokens.shape[0]
    v = np.zeros(n_cb * n_buckets_per_codebook, dtype=np.float32)
    for cb in range(n_cb):
        row = tokens[cb]
        base = cb * n_buckets_per_codebook
        for i in range(len(row) - 1):
            t1 = int(row[i])
            t2 = int(row[i + 1])
            h = _mix64(t1 * 0x9E3779B97F4A7C15 + t2 * 0xD1B54A32D192ED03
                        + ((t1 ^ t2) * 0xBF58476D1CE4E5B9))
            v[base + (h % n_buckets_per_codebook)] += 1.0
    s = v.sum()
    return v / s if s > 0 else v


def grain_feature(tokens, codebook_size, hist_weight=1.0, bigram_weight=1.0,
                   bigram_buckets_per_codebook=BIGRAM_BUCKETS_PER_CODEBOOK):
    """Full searchable feature: histogram (+) bigram. Both are L1-normalised
    distributions, so cosine distance is meaningful on the concatenation."""
    hist = token_histogram(tokens, codebook_size) * hist_weight
    bg = token_bigrams(tokens, bigram_buckets_per_codebook) * bigram_weight
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

    # Peak-pick: group contiguous above-threshold frames into runs and take
    # the frame of MAXIMUM rise within each run (the actual attack peak),
    # not just the first frame to cross threshold - on a gradual transient
    # the earliest above-threshold frame can sit well before the strongest
    # part of the rise, placing the onset too early.
    candidates = np.where(rise > threshold)[0]
    peak_frames = []
    if len(candidates) > 0:
        run_start = candidates[0]
        prev = candidates[0]
        runs = []
        for f in candidates[1:]:
            if f - prev > 1:
                runs.append((run_start, prev))
                run_start = f
            prev = f
        runs.append((run_start, prev))
        for (a, b) in runs:
            peak_frames.append(int(a + np.argmax(rise[a:b + 1])))

    # enforce minimum spacing between PEAKS; if two run-peaks land closer
    # together than min_gap_frames, keep whichever one has the stronger rise
    onset_frames = []
    for f in sorted(peak_frames):
        if not onset_frames or f - onset_frames[-1] >= min_gap_frames:
            onset_frames.append(f)
        elif rise[f] > rise[onset_frames[-1]]:
            onset_frames[-1] = f

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


def _sha256_file(path):
    """Best-effort file hash for run-provenance metadata; never fatal."""
    import hashlib
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None


def _source_uid(path):
    """Stable 12-hex identifier of one corpus SOURCE file (absolute path), so
    two files with the same basename in different folders never look like one
    recording to the continuation graph's chronological adjacency test."""
    import hashlib
    try:
        p = os.path.normcase(os.path.abspath(path))
    except Exception:
        p = str(path)
    return hashlib.sha1(p.encode("utf-8", "replace")).hexdigest()[:12]


def _corpus_manifest_sha256(files):
    """Hash (relative name, size, mtime) of every corpus SOURCE file that
    build-corpus was asked to encode, so an index can be tied back to the
    exact audio it was built from (not just "some corpus that used the same
    codec"). Content-hashing every file would be more airtight but is
    expensive for large corpora; name+size+mtime catches the common
    reproducibility failure (wrong/edited/reordered source files) cheaply.
    """
    import hashlib
    h = hashlib.sha256()
    for fp in sorted(files):
        h.update(os.path.basename(fp).encode("utf-8", "replace"))
        try:
            st = os.stat(fp)
            h.update(str(st.st_size).encode("ascii"))
            h.update(str(int(st.st_mtime)).encode("ascii"))
        except OSError:
            h.update(b"?")
    return h.hexdigest()


def _load_corpus_index(index_path_prefix, mmap=False):
    """Load a corpus index (.json + _feats.npy), refusing to proceed if its
    feature schema doesn't match CURRENT_SCHEMA_VERSION.

    Earlier versions tried to stay "compatible" with older indexes by
    reading a stored bigram_dim/defaulting to a legacy pooled-64 layout
    when it was missing. In practice a freshly-encoded QUERY vector is
    always built with the CURRENT code's bucket count/hash, so the moment
    the corpus's stored layout differs from that even slightly, the two
    vectors have different dimensions (or the same dimension but
    incompatible meaning) and every downstream cosine-distance call is
    either a crash (shape mismatch) or silently wrong (same size, garbage
    comparison). There is no safe partial compatibility here, so we stop
    immediately with an actionable message instead of guessing.
    """
    json_path = index_path_prefix + ".json"
    feats_path = index_path_prefix + "_feats.npy"
    if not os.path.isfile(json_path):
        sys.stderr.write(
            "ERROR: corpus index not found: %s\n"
            "Build a corpus index first (build-corpus).\n" % json_path)
        sys.exit(2)
    with open(json_path) as f:
        index = json.load(f)
    found_version = index.get("schema_version")
    if found_version != CURRENT_SCHEMA_VERSION:
        sys.stderr.write(
            "ERROR: this corpus index uses an obsolete feature schema "
            "(schema_version=%r, this script requires %d).\n"
            "The stored feature layout (bigram bucket count/hash) is not "
            "compatible with a freshly-encoded query, so it cannot be used "
            "as-is. Please rebuild the corpus index with build-corpus.\n"
            % (found_version, CURRENT_SCHEMA_VERSION))
        sys.exit(2)
    if not os.path.isfile(feats_path):
        sys.stderr.write(
            "ERROR: corpus feature matrix not found: %s\n"
            "The index JSON exists but its _feats.npy is missing; "
            "rebuild the corpus index.\n" % feats_path)
        sys.exit(2)
    # v1.7: mmap=True (continuation-tail) streams the potentially large
    # feature matrix instead of loading it whole; default unchanged.
    feats = np.load(feats_path, mmap_mode="r" if mmap else None)
    return index, feats


def _rmtree_retry(path, attempts=6, delay=0.4):
    """shutil.rmtree, hardened for Windows.

    A folder of many small files that this SAME process just finished
    writing (e.g. a previous build's *_grains/ directory) is a classic
    target for Windows antivirus or the search indexer to briefly hold a
    lock on one file right as we try to delete it. shutil.rmtree deletes
    every file it can, then calls rmdir() on the now-should-be-empty
    directory - if even one file was momentarily locked, rmdir() fails with
    WinError 145 "The directory is not empty", even though every unlink()
    call reported success. This is a timing race, not a real permissions
    or ownership problem, so the fix is simply to retry after a short
    pause (clearing the read-only bit on any straggler first, since that's
    the other common Windows cause of a failed delete) rather than failing
    the whole build over a transient lock.
    """
    import shutil
    import stat
    import time

    def _onerror(func, p, exc_info):
        try:
            os.chmod(p, stat.S_IWRITE)
            func(p)
        except Exception:
            pass

    last_err = None
    for _ in range(attempts):
        try:
            shutil.rmtree(path, onerror=_onerror)
            return
        except OSError as e:
            last_err = e
            if not os.path.isdir(path):
                return  # it actually succeeded despite raising
            time.sleep(delay)
    raise last_err


def _resolve_grain_path(index_path_prefix, grain_audio):
    """grain_audio may be stored relative to the index's own directory
    (current indexes, see build_corpus) or as an absolute path (older
    indexes, kept working for backward compatibility). Resolve either into
    something np.load can open regardless of where the index folder has
    been moved to since it was built."""
    if os.path.isabs(grain_audio) and os.path.isfile(grain_audio):
        return grain_audio
    base = os.path.dirname(os.path.abspath(index_path_prefix))
    candidate = os.path.join(base, grain_audio)
    if os.path.isfile(candidate):
        return candidate
    return grain_audio  # last resort - let the caller's own error fire


def _build_corpus_impl(args):
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
        try:
            _rmtree_retry(grain_audio_dir)
        except OSError as e:
            sys.stderr.write(
                "ERROR: could not clear the old grain folder before "
                "rebuilding: %s\n(%s)\n"
                "This is usually a file left open by another program - "
                "close any file explorer window, antivirus scan, or other "
                "process that might be touching files under that folder, "
                "then try the build again.\n" % (grain_audio_dir, e))
            sys.exit(2)
    os.makedirs(grain_audio_dir, exist_ok=True)

    n_codebooks_at_build = None
    gid = 0
    for file_index, fp in enumerate(files):
        try:
            wav = load_audio_mono(fp, codec.sample_rate)
        except Exception as e:
            sys.stderr.write("Skipping %s (%s)\n" % (fp, e))
            continue
        # v1.7: stable per-file identifier (basenames alone can collide when
        # several folders are given) - consumed by the continuation graph.
        source_uid = _source_uid(fp)
        for (start, seg) in slice_grains(wav, codec.sample_rate,
                                         args.grain_ms, args.hop_ms):
            # v1.7: how many samples of this grain are REAL audio. Only the
            # final grain of a file can be shorter than seg (slice_grains
            # zero-pads it); recorded so nothing downstream has to guess.
            real_samples = int(min(len(seg), len(wav) - start))
            if np.abs(seg).max() < args.silence_floor:
                continue  # skip near-silent grains
            tokens = codec.encode(seg)
            if n_codebooks_at_build is None:
                n_codebooks_at_build = int(tokens.shape[0])
            feat = grain_feature(tokens, cb)
            peak_offset = grain_peak_offset(seg, codec.sample_rate)
            rms = float(np.sqrt(np.mean(seg.astype(np.float64) ** 2)))
            centroid = spectral_centroid_hz(seg, codec.sample_rate)
            # store the grain AUDIO so reconstruction uses real corpus material
            grain_path = os.path.join(grain_audio_dir, "grain_%06d.npy" % gid)
            np.save(grain_path, seg.astype(np.float32))
            # Store the grain path RELATIVE to the index's own directory so
            # the index folder can be moved/copied to another machine or
            # location without every grain reference breaking. Resolved
            # back to an absolute path at load time via _resolve_grain_path.
            rel_grain_path = (os.path.relpath(grain_path, index_parent)
                              if index_parent else grain_path)
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
                "grain_audio": rel_grain_path,
                # v1.7 optional fields (schema_version stays 3; older
                # readers ignore them, the continuation graph uses them
                # when present and falls back to detection otherwise)
                "source_uid": source_uid,
                "source_index": file_index,
                "real_samples": real_samples,
            })
            feats.append(feat)
            gid += 1

    if not feats:
        sys.stderr.write("No grains produced (all silent or files unreadable).\n")
        sys.exit(2)

    import platform
    import hashlib
    feats = np.stack(feats).astype(np.float32)
    np.save(args.index + "_feats.npy", feats)
    n_cb_used = n_codebooks_at_build or 1
    index_out = {
        "schema_version": CURRENT_SCHEMA_VERSION,
        "corpus_audio_spec": args.corpus_audio,
        "codec": codec.name,
        "sample_rate": codec.sample_rate,
        "codebook_size": cb,
        "n_codebooks": n_cb_used,
        "bigram_buckets_per_codebook": BIGRAM_BUCKETS_PER_CODEBOOK,
        "bigram_dim": n_cb_used * BIGRAM_BUCKETS_PER_CODEBOOK,
        "grain_ms": args.grain_ms,
        "hop_ms": args.hop_ms,
        "silence_floor": args.silence_floor,
        "n_grains": len(grains_meta),
        "feature_dim": int(feats.shape[1]),
        "python_version": platform.python_version(),
        "feats_sha256": hashlib.sha256(feats.tobytes()).hexdigest(),
        # Reproducibility provenance beyond just the codec name: which
        # specific model configuration/package version produced these
        # tokens, plus a manifest hash of the source corpus files actually
        # encoded (so an index can be tied back to the exact audio it was
        # built from).
        "corpus_source_manifest_sha256": _corpus_manifest_sha256(files),
        "grains": grains_meta,
    }
    index_out.update(codec.provenance())
    with open(args.index + ".json", "w") as f:
        json.dump(index_out, f, indent=1)
    sys.stdout.write("Built corpus index: %d grains from %d files -> %s.json\n"
                     % (len(grains_meta), len(files), args.index))


def _remove_artifact(path):
    """Remove one corpus artefact (file or directory) if it exists."""
    if os.path.isdir(path):
        _rmtree_retry(path)
    elif os.path.exists(path):
        os.remove(path)


def _atomic_build_corpus(args):
    """Build into a sibling staging directory, then replace the live corpus.

    The staging prefix keeps the SAME basename as the final prefix so the
    relative grain paths written into index.json remain valid after promotion.
    Existing live artefacts are first moved to a backup directory. If any
    promotion step fails, the backup is restored before the error is re-raised.
    """
    import copy
    import time

    final_prefix = os.path.abspath(args.index)
    parent = os.path.dirname(final_prefix) or os.getcwd()
    base = os.path.basename(final_prefix)
    os.makedirs(parent, exist_ok=True)

    tag = "%d_%d" % (os.getpid(), int(time.time() * 1000))
    stage_dir = os.path.join(parent, ".%s_build_%s" % (base, tag))
    backup_dir = os.path.join(parent, ".%s_backup_%s" % (base, tag))
    os.makedirs(stage_dir, exist_ok=False)

    stage_prefix = os.path.join(stage_dir, base)
    staged = [stage_prefix + ".json",
              stage_prefix + "_feats.npy",
              stage_prefix + "_grains"]
    live = [final_prefix + ".json",
            final_prefix + "_feats.npy",
            final_prefix + "_grains"]
    backup = [os.path.join(backup_dir, os.path.basename(x)) for x in live]

    staged_args = copy.copy(args)
    staged_args.index = stage_prefix
    staged_args.atomic = False

    try:
        _build_corpus_impl(staged_args)
        missing = [x for x in staged if not os.path.exists(x)]
        if missing:
            raise RuntimeError("staged corpus build is incomplete; missing: %s"
                               % ", ".join(missing))

        os.makedirs(backup_dir, exist_ok=False)
        moved_old = []
        moved_new = []
        try:
            # Preserve the old live corpus until every staged artefact exists.
            for src, dst in zip(live, backup):
                if os.path.exists(src):
                    os.replace(src, dst)
                    moved_old.append((dst, src))

            # Promote the complete new corpus. Same filesystem => rename/replace.
            for src, dst in zip(staged, live):
                os.replace(src, dst)
                moved_new.append(dst)
        except Exception:
            # Roll back any partial promotion, then restore the previous corpus.
            for path in reversed(moved_new):
                try:
                    _remove_artifact(path)
                except Exception:
                    pass
            for src, dst in reversed(moved_old):
                if os.path.exists(src):
                    os.replace(src, dst)
            raise

        sys.stdout.write("Promoted corpus index atomically -> %s.json\n"
                         % final_prefix)

    finally:
        # Staging/backup are never part of the live corpus. Cleanup failure here
        # should not invalidate an otherwise successful promotion.
        for d in (stage_dir, backup_dir):
            if os.path.isdir(d):
                try:
                    _rmtree_retry(d)
                except Exception as e:
                    sys.stderr.write("WARNING: could not remove temporary build "
                                     "directory %s (%s)\n" % (d, e))


def build_corpus(args):
    if getattr(args, "atomic", False):
        _atomic_build_corpus(args)
    else:
        _build_corpus_impl(args)

    marker = getattr(args, "success_marker", None)
    if marker:
        marker_parent = os.path.dirname(os.path.abspath(marker))
        if marker_parent:
            os.makedirs(marker_parent, exist_ok=True)
        with open(marker, "w") as f:
            f.write("ok\n")


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

    # ---- pre-pass: stop earlier grains' tails from sounding THROUGH a
    # later silent placeholder ----
    # A silent placeholder means the SOURCE was below its silence floor at
    # that point in time, so the output is expected to be silent there too.
    # But grains are written at their own full natural length regardless of
    # what comes next, and with overlapping sub-windows (the normal case)
    # a long-enough grain can still be sounding when a later silent
    # window's write position arrives, playing straight through it. Fix:
    # truncate (with a short fade to zero) any earlier grain whose written
    # span would otherwise extend past the START of a later silent
    # placement.
    write_starts = [max(0, onset - peak_off) for (onset, g, peak_off) in placements]
    is_silent = [g is None or len(g) == 0 or float(np.abs(g).max()) == 0.0
                 for (_, g, _) in placements]
    fade_samples = max(1, int(round(0.008 * sr)))  # ~8 ms fade to zero
    placements = list(placements)
    for i, silent in enumerate(is_silent):
        if not silent:
            continue
        silent_start = write_starts[i]
        for j in range(i):
            if is_silent[j]:
                continue
            oj, gj, pj = placements[j]
            wj = write_starts[j]
            natural_end = wj + len(gj)
            if wj < silent_start < natural_end:
                keep = silent_start - wj
                gj2 = gj[:keep].copy()
                fn = min(fade_samples, len(gj2))
                if fn > 0:
                    t = np.linspace(0.0, np.pi / 2.0, fn, dtype=np.float32)
                    gj2[-fn:] *= np.cos(t)
                placements[j] = (oj, gj2, pj)

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
    # load index (hard-fails on an obsolete/incompatible feature schema
    # rather than silently building a query vector of a different shape -
    # see _load_corpus_index)
    index, feats = _load_corpus_index(args.index)
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
    warned_short_window = False
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
                    "n_token_frames": None,
                    "n_bigrams": None,
                })
                continue
            tokens = codec.encode(sub)
            n_token_frames = int(tokens.shape[1])
            n_bigrams = int(tokens.shape[0] * max(0, n_token_frames - 1))
            if n_token_frames < _MIN_TOKEN_FRAMES_WARN and not warned_short_window:
                sys.stderr.write(
                    "Warning: some analysis sub-windows encode to only %d "
                    "token frame(s) (< %d) - too few transitions for the "
                    "bigram section to carry much signal. Consider raising "
                    "--analysis-grain-ms (try 120-180ms) for this codec.\n"
                    % (n_token_frames, _MIN_TOKEN_FRAMES_WARN))
                warned_short_window = True
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
            g = np.load(_resolve_grain_path(args.index, grains_meta[best]["grain_audio"]))
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
                "n_token_frames": n_token_frames,
                "n_bigrams": n_bigrams,
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
        import platform
        with open(args.metadata, "w") as f:
            json.dump({
                "mode": "match",
                "codec": index["codec"],
                "sample_rate": sr,
                "feature_schema_version": index.get("schema_version"),
                "bigram_buckets_per_codebook": index.get("bigram_buckets_per_codebook"),
                "n_codebooks": index.get("n_codebooks"),
                "analysis_grain_ms": args.analysis_grain_ms,
                "analysis_hop_ms": args.analysis_hop_ms,
                "onset_min_interval_ms": args.onset_min_interval_ms,
                "repeat_penalty": args.repeat_penalty,
                "energy_weight": args.energy_weight,
                "xfade_ms": args.xfade_ms,
                "silence_floor": args.silence_floor,
                "python_version": platform.python_version(),
                "source_input_sha256": _sha256_file(args.input),
                "index_json_sha256": _sha256_file(args.index + ".json"),
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


DRAW_CONTOUR_MAGIC = "corpus_draw_contour"
DRAW_CONTOUR_FORMAT_VERSION = 1


def read_realtier(path):
    """Parse a Praat RealTier text file into sorted (time, value) points.
    Returns (xmin, xmax, [(t, v), ...]). Tolerant of whitespace/ordering."""
    times = []
    values = []
    xmin = 0.0
    xmax = 1.0
    pending_t = None
    with open(path, "r", encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if line.startswith("xmin") and "=" in line and not times:
                try:
                    xmin = float(line.split("=", 1)[1])
                except ValueError:
                    pass
            elif line.startswith("xmax") and "=" in line and pending_t is None and not times:
                try:
                    xmax = float(line.split("=", 1)[1])
                except ValueError:
                    pass
            elif line.startswith("number") and "=" in line:
                try:
                    pending_t = float(line.split("=", 1)[1])
                except ValueError:
                    pending_t = None
            elif line.startswith("value") and "=" in line and pending_t is not None:
                try:
                    v = float(line.split("=", 1)[1])
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


def _collapse_contour_points(points, duration):
    """Sort points, clamp time/value to the serialized Draw domain, and let the
    last point win when several rows share the same time."""
    rows = []
    for order, (t, v) in enumerate(points):
        t = float(t)
        v = float(v)
        if not (np.isfinite(t) and np.isfinite(v)):
            continue
        if -1e-9 <= t <= duration + 1e-9:
            rows.append((min(max(t, 0.0), duration), min(max(v, 0.0), 1.0), order))
    rows.sort(key=lambda r: (r[0], r[2]))
    out = []
    for t, v, _ in rows:
        if out and abs(out[-1][0] - t) < 1e-9:
            out[-1] = (t, v)
        else:
            out.append((t, v))
    return out


def read_draw_contour(path):
    """Read the persistent, human-readable Draw representation:

        format corpus_draw_contour 1
        duration 4.000000
        [CURVE]
        0.000000 0.100000
        1.250000 0.800000

    Values are the NORMALIZED brightness target actually used by Draw (0=dark,
    1=bright). Two-column rows, commas/tabs, and '#' comments are accepted so
    files can also be handwritten or generated externally.
    """
    duration = None
    points = []
    in_curve = False
    seen_format = False
    with open(path, "r", encoding="utf-8-sig") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            up = line.upper()
            if up == "[CURVE]":
                in_curve = True
                continue
            if not in_curve:
                key, _, rest = line.partition(" ")
                key = key.lower()
                if key == "format":
                    parts = rest.split()
                    if len(parts) < 2 or parts[0] != DRAW_CONTOUR_MAGIC:
                        raise ValueError("contour file line %d: unsupported format" % lineno)
                    version = int(parts[1])
                    if version != DRAW_CONTOUR_FORMAT_VERSION:
                        raise ValueError(
                            "contour format version %d is not supported (expected %d)"
                            % (version, DRAW_CONTOUR_FORMAT_VERSION))
                    seen_format = True
                elif key == "duration":
                    duration = float(rest.split()[0])
                continue
            parts = line.replace(",", " ").replace("\t", " ").split()
            if len(parts) < 2:
                raise ValueError("contour file line %d needs time and value" % lineno)
            try:
                points.append((float(parts[0]), float(parts[1])))
            except ValueError:
                raise ValueError("contour file line %d is not numeric: %r"
                                 % (lineno, raw.strip()))

    if not seen_format:
        raise ValueError("not a Praat AudioTools Draw contour file (missing format line)")
    if duration is None:
        duration = max((p[0] for p in points), default=0.0)
    if duration <= 0:
        raise ValueError("contour duration must be > 0")
    points = _collapse_contour_points(points, float(duration))
    if not points:
        raise ValueError("contour has no usable points")
    return float(duration), points


def write_draw_contour(path, duration, points, source=""):
    """Write the normalized compositional control representation used by Draw.
    This deliberately stores only the gesture (time -> brightness), not synthesis
    parameters; run parameters remain in the normal metadata / project manifest."""
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    points = _collapse_contour_points(points, float(duration))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Praat AudioTools - Corpus Concatenative Codec Draw contour\n")
        f.write("# time_s normalized_brightness   (0=dark, 1=bright)\n")
        if source:
            f.write("# source: %s\n" % source)
        f.write("format %s %d\n" % (DRAW_CONTOUR_MAGIC, DRAW_CONTOUR_FORMAT_VERSION))
        f.write("duration %.6f\n" % float(duration))
        f.write("[CURVE]\n")
        for t, v in points:
            f.write("%.6f %.6f\n" % (t, v))


def _normalise_realtier_contour(path, duration_override=0.0):
    """Convert an interactive RealTier to the persistent Draw representation.
    Time is remapped to [0,duration]; values are normalised by the tier's own
    min/max exactly as legacy Draw did, so existing interactive behaviour is
    unchanged. The returned points are therefore the exact normalized control
    representation that the synthesis will use."""
    xmin, xmax, pts = read_realtier(path)
    if not pts:
        raise ValueError("Drawn curve has no points")
    tier_duration = xmax - xmin
    duration = float(duration_override) if duration_override > 0 else tier_duration
    if duration <= 0:
        duration = 1.0

    raw_t = np.asarray([p[0] for p in pts], dtype=np.float64)
    raw_v = np.asarray([p[1] for p in pts], dtype=np.float64)
    vmin, vmax = float(raw_v.min()), float(raw_v.max())
    if vmax - vmin > 1e-9:
        norm_v = (raw_v - vmin) / (vmax - vmin)
    else:
        norm_v = np.full_like(raw_v, 0.5)

    if tier_duration > 1e-12:
        norm_t = (raw_t - xmin) / tier_duration * duration
    else:
        norm_t = np.linspace(0.0, duration, raw_t.size)
    points = _collapse_contour_points(zip(norm_t, norm_v), duration)
    return duration, points


def _stretch_contour(points, old_duration, new_duration):
    if new_duration <= 0 or abs(new_duration - old_duration) < 1e-12:
        return old_duration, list(points)
    scale = new_duration / old_duration
    return new_duration, [(t * scale, v) for t, v in points]


def draw(args):
    """Brightness-contour synthesis from either an interactive Praat RealTier or
    a persistent Draw contour file. The synthesis itself always operates on the
    same explicit normalized time->brightness representation."""
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

    # ---- explicit Draw control representation ----
    # Backward-compatible interactive path: RealTier values are normalized exactly
    # as before, then converted into a reusable time->brightness contour.
    if bool(args.tier) == bool(args.contour):
        sys.stderr.write(
            "Draw requires exactly one gesture source: --tier (Praat RealTier) "
            "or --contour (saved Draw contour file).\n")
        sys.exit(4)

    try:
        if args.contour:
            source_kind = "contour_file"
            source_path = args.contour
            source_duration, points = read_draw_contour(args.contour)
            duration, points = _stretch_contour(
                points, source_duration,
                float(args.duration) if args.duration > 0 else source_duration)
        else:
            source_kind = "realtier"
            source_path = args.tier
            duration, points = _normalise_realtier_contour(args.tier, args.duration)
    except Exception as e:
        sys.stderr.write("Could not read Draw contour: %s\n" % e)
        sys.exit(4)

    if args.contour_out:
        try:
            write_draw_contour(args.contour_out, duration, points, source=source_kind)
        except Exception as e:
            sys.stderr.write("Could not save normalized Draw contour: %s\n" % e)
            sys.exit(4)

    # From here on, Draw no longer cares where the gesture came from. It samples
    # the serialized representation directly at the fixed grain rate.
    pt_t = np.array([p[0] for p in points], dtype=np.float64)
    pt_v = np.array([p[1] for p in points], dtype=np.float64)

    step = max(0.001, args.grain_rate_ms / 1000.0)
    n_steps = max(1, int(round(duration / step)))

    placements = []
    used = []
    last_choice = -1
    for k in range(n_steps):
        t = k * step
        # normalized brightness target at this output time
        level = float(np.interp(t, pt_t, pt_v))
        # nearest-brightness grain
        dist = np.abs(bright - level)
        if args.repeat_penalty > 0 and 0 <= last_choice < len(dist):
            dist[last_choice] += args.repeat_penalty
        best = int(np.argmin(dist))
        last_choice = best
        g = np.load(_resolve_grain_path(args.index, grains_meta[best]["grain_audio"]))
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
                "contour_source": source_kind,
                "contour_source_file": os.path.abspath(source_path),
                "contour_source_sha256": _sha256_file(source_path),
                "normalized_contour_file": (os.path.abspath(args.contour_out)
                                              if args.contour_out else None),
                "normalized_contour_sha256": (_sha256_file(args.contour_out)
                                                  if args.contour_out else None),
                "contour_points": len(points),
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
#       [ histogram (n_codebooks * codebook_size) | bigrams (n_codebooks *
#         bigram_buckets_per_codebook) ]
#   The bigram section's width depends on how many codebooks the corpus was
#   built with, so it is read from the index's own "bigram_dim" field
#   (written by build_corpus) rather than assumed as a fixed constant. We
#   SPLIT each stored row into its histogram and bigram sections and
#   re-apply (hist_weight, bigram_weight) at match time, exactly mirroring
#   how grain_feature weights the freshly-encoded source. No rebuild needed
#   for indexes already built with the current (per-codebook) bigram layout.
# ============================================================


def gesture_rhyme(args):
    # ---- Load index (read-only; never built or resliced here) ----
    # _load_corpus_index hard-fails on an obsolete schema_version instead of
    # falling back to a guessed legacy layout: gesture-rhyme's own
    # feature-splitting below TRUSTS the index's schema_version to already
    # match this script's current bigram_dim - there is no safe partial
    # compatibility to fall back to (a stale bigram_dim just produces a
    # differently-shaped or differently-meaning-ed vector, not a merely
    # "less accurate" one).
    index, feats = _load_corpus_index(args.index)
    json_path = args.index + ".json"
    cb = index["codebook_size"]
    sr = index["sample_rate"]
    grains_meta = index["grains"]
    feature_dim = int(feats.shape[1])

    # ---- Split the (now schema-verified) feature vector into hist | bigram
    # sections. bigram_dim depends on n_codebooks * bigram_buckets_per_codebook
    # (each codebook has its own bucket range - see token_bigrams), so it is
    # read from the index rather than assumed as a fixed constant.
    bigram_dim = index["bigram_dim"]
    hist_dim = feature_dim - bigram_dim
    if hist_dim <= 0:
        sys.stderr.write(
            "ERROR: corpus feature layout is inconsistent with itself.\n"
            "Expected [histogram | %d bigram bucket(s)] but feature_dim=%d "
            "leaves no histogram section. Rebuild the index with this codec.\n"
            % (bigram_dim, feature_dim))
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

    random_baseline = bool(getattr(args, "random_baseline", 0))
    rng = np.random.default_rng(args.seed) if random_baseline else None
    n_corpus = len(grains_meta)

    placements = []   # (onset_sample, grain_audio, peak_offset_sample)
    used = []
    last_choice = -1
    warned_short_window = False
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
                                           energy_weight, random_baseline))
                context_buf = []
                continue

            tokens = codec.encode(sub)
            n_token_frames = int(tokens.shape[1])
            n_bigrams = int(tokens.shape[0] * max(0, n_token_frames - 1))
            if n_token_frames < _MIN_TOKEN_FRAMES_WARN and not warned_short_window:
                sys.stderr.write(
                    "Warning: some analysis sub-windows encode to only %d "
                    "token frame(s) (< %d) - too few transitions for the "
                    "bigram section to carry much signal. Consider raising "
                    "--analysis-grain-ms (try 120-180ms) for this codec.\n"
                    % (n_token_frames, _MIN_TOKEN_FRAMES_WARN))
                warned_short_window = True
            q = grain_feature(tokens, cb, hist_weight, bigram_weight)

            # --- sequence context (see gr.add_argument("--sequence-context")
            # for the accurate description: this is CONTEXT SMOOTHING, an
            # unordered mean over the last few windows, not a sequence /
            # order-aware match - averaging [A, B] and [B, A] gives the same
            # vector, so it stabilises matches across neighbouring windows
            # without encoding which one came first ---
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

            if random_baseline:
                # ---- Onset-aligned random corpus selection (ablation) ----
                # Same onsets, same sub-windows, same overlap-add as every
                # other condition - the ONLY thing that changes is that the
                # grain choice ignores all distances and is drawn uniformly
                # at random (seeded, so reproducible). This isolates how
                # much of Gesture Rhyme's output is attributable to
                # bigram/histogram/energy matching versus just inheriting
                # the source's rhythmic skeleton.
                best = int(rng.integers(0, n_corpus))
            else:
                best = int(np.argmin(dists))
            last_choice = best

            # per-section distances for the chosen grain, reported
            # separately (they do NOT sum to combined_distance - see
            # _gr_used_entry docstring)
            q_hist, q_bg = q_match[:hist_dim], q_match[hist_dim:]
            c_hist = weighted_corpus[best, :hist_dim]
            c_bg = weighted_corpus[best, hist_dim:]
            # A weight of 0 makes that section's vectors all-zero, which
            # cosine_distance reports as 1.0 (its "no valid direction to
            # compare" fallback) - that reads as "a bad match" when the
            # section was simply switched off. Report null instead so the
            # metadata can't be misread as a genuinely poor histogram/bigram
            # match when the term never participated in selection at all.
            histogram_distance = (cosine_distance(q_hist, c_hist)
                                   if hist_weight > 0 else None)
            bigram_distance = (cosine_distance(q_bg, c_bg)
                                if bigram_weight > 0 else None)
            weighted_energy_distance = (float(energy_weight * energy_dist[best])
                              if energy_dist is not None else None)

            # load the chosen grain's audio (fail clearly if it's missing)
            gp = _resolve_grain_path(args.index, grains_meta[best]["grain_audio"])
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
                (round(histogram_distance, 4) if histogram_distance is not None else None),
                (round(bigram_distance, 4) if bigram_distance is not None else None),
                (round(weighted_energy_distance, 4) if weighted_energy_distance is not None else None),
                bigram_weight, hist_weight, energy_weight, random_baseline,
                n_token_frames, n_bigrams))

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
        import platform
        with open(args.metadata, "w") as f:
            json.dump({
                "mode": "gesture-rhyme",
                "codec": index["codec"],
                "sample_rate": sr,
                "feature_schema_version": index.get("schema_version"),
                "bigram_buckets_per_codebook": index.get("bigram_buckets_per_codebook"),
                "n_codebooks": index.get("n_codebooks"),
                "bigram_weight": bigram_weight,
                "hist_weight": hist_weight,
                "energy_weight": energy_weight,
                "sequence_context": seq_context,
                "context_mode": "smoothing",  # unordered mean, NOT sequence-aware - see CLI help
                "random_baseline": random_baseline,
                "seed": args.seed if random_baseline else None,
                "analysis_grain_ms": args.analysis_grain_ms,
                "analysis_hop_ms": args.analysis_hop_ms,
                "onset_min_interval_ms": args.onset_min_interval_ms,
                "repeat_penalty": args.repeat_penalty,
                "xfade_ms": args.xfade_ms,
                "silence_floor": args.silence_floor,
                "python_version": platform.python_version(),
                "source_input_sha256": _sha256_file(args.input),
                "index_json_sha256": _sha256_file(json_path),
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
                   corpus_start_s, combined_distance, histogram_distance,
                   bigram_distance, weighted_energy_distance,
                   bigram_weight, hist_weight, energy_weight,
                   random_baseline=False, n_token_frames=None, n_bigrams=None):
    """One metadata record per matched sub-window. Keeps the keys
    write_textgrid needs (src_start_s, src_duration_s, corpus_file,
    corpus_start_s) plus the gesture-rhyme provenance fields, so it's possible
    to study which UNRELATED corpus grains voiced each abstract gesture.

    Field names describe what they ARE: histogram_distance and
    bigram_distance are each section's own cosine distance, computed
    separately - they do NOT sum to combined_distance, since the actual
    match is made on the concatenated, weighted, re-normalised vector, not
    by adding the sections' individual distances together."""
    return {
        "src_start_s": round(start / sr, 4),
        "src_duration_s": round(len(sub) / sr, 4),
        "segment_head": is_head,
        "corpus_grain_id": grain_id,
        "corpus_file": corpus_file,
        "corpus_start_s": corpus_start_s,
        "combined_distance": combined_distance,
        "histogram_distance": histogram_distance,
        "bigram_distance": bigram_distance,
        "weighted_energy_distance": weighted_energy_distance,
        "bigram_weight": bigram_weight,
        "hist_weight": hist_weight,
        "energy_weight": energy_weight,
        "random_baseline": random_baseline,
        "n_token_frames": n_token_frames,
        "n_bigrams": n_bigrams,
    }


# ============================================================
# continuation-tail subcommand (v1.7)
#   "Corpus Continuation Tail": analyse the TERMINAL state of a source phrase
#   and generate a continuation of a requested length from real corpus
#   grains, steered by an explicit corpus TRANSITION GRAPH.
#
#   Division of labour with the Praat front-end (deliberate, see v1.7 notes):
#     Python  - analysis, grain-sequence planning, overlap-add synthesis,
#               envelope, local level control. Writes ONLY the tail buffer
#               (crossfade region + new material) as 32-bit float WAV at the
#               SOURCE's own sampling rate, with an exact sample count, plus
#               a small key/value result file describing the join.
#     Praat   - the actual join, on the untouched in-memory Sound, so the
#               original's samples outside the crossfade are bit-exact and
#               the output length is exactly join_end + tail_samples.
#
#   Graph cache (separately versioned sidecar next to the corpus index):
#     <index>_graph.npz   descriptors, adjacency, cross edges
#     <index>_graph.json  graph schema, identity of the index it belongs to,
#                         descriptor mode, retrieval method/recall, npz hash.
#   The JSON is written LAST and records the npz's sha256, so a torn write is
#   detected as "stale" and rebuilt; the corpus index itself is never touched.
# ============================================================

import math
import time

GRAPH_SCHEMA_VERSION = 3   # v3: chronological links with rounding-safe tolerance
GRAPH_K = 24              # cross (non-chronological) edges kept per grain
GRAPH_RETRIEVE_M = 64     # approximate-NN candidates fetched before re-ranking
N_SPEC_BANDS = 24         # log-spaced band shape (level-invariant)
LATENT_PCA_DIM = 32       # codec latent projected to this many dims
EXACT_KNN_MAX = 3000      # up to this many grains, exact search is cheaper
CHRONO_TOL_SAMPLES = 3    # tolerance on start-time hop test (start_s is rounded)
VOICED_CONF = 0.70        # YIN confidence above which F0 is trusted
SPEC_W = math.sqrt(0.5)   # weight of spectral part in the combined descriptor
LAT_W = math.sqrt(0.5)    # weight of latent part (when the latent is verified)
MAX_TAIL_SECONDS = 300.0

ENVELOPES = ("exp-decay", "sustain-drop", "tremolo-decay", "swell-fade")


def _round_half_up(x):
    """floor(x + 0.5): identical to Praat's round(), unlike Python's banker's
    round(). Every sample count that BOTH sides compute uses this."""
    return int(math.floor(float(x) + 0.5))


def _unit(v):
    v = np.asarray(v, dtype=np.float32)
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else np.zeros_like(v)


# ---------------- per-region acoustic descriptors ----------------

_BAND_CACHE = {}


def _band_tables(n_fft, sr):
    key = (int(n_fft), int(sr))
    if key in _BAND_CACHE:
        return _BAND_CACHE[key]
    freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)
    fmax = min(16000.0, 0.95 * sr / 2.0)
    edges = np.geomspace(60.0, fmax, N_SPEC_BANDS + 1)
    M = np.zeros((N_SPEC_BANDS, len(freqs)), dtype=np.float64)
    for b in range(N_SPEC_BANDS):
        idx = np.flatnonzero((freqs >= edges[b]) & (freqs < edges[b + 1]))
        if idx.size == 0:  # band narrower than a bin: use the nearest bin
            idx = np.array([int(np.argmin(np.abs(freqs - 0.5 * (edges[b] + edges[b + 1]))))])
        M[b, idx] = 1.0 / idx.size
    flat_mask = (freqs >= 100.0) & (freqs <= min(8000.0, fmax))
    _BAND_CACHE[key] = (freqs, M, flat_mask)
    return _BAND_CACHE[key]


def _region_spectral(x, sr):
    """Level-invariant band SHAPE (unit vector), log RMS, log centroid, and
    spectral flatness (0 = tonal, 1 = noise-like) of one audio region."""
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    if n < 32:
        return np.zeros(N_SPEC_BANDS, np.float32), math.log(1e-6), math.log(20.0), 1.0
    rms = float(np.sqrt(np.mean(x * x)))
    n_fft = 1 << int(math.ceil(math.log2(max(n, 256))))
    P = np.abs(np.fft.rfft(x * np.hanning(n), n_fft)) ** 2
    freqs, M, fm = _band_tables(n_fft, sr)
    lb = np.log(M.dot(P) + 1e-12)
    shape = lb - lb.mean()
    unit = _unit(shape) if rms > 1e-6 else np.zeros(N_SPEC_BANDS, np.float32)
    s = float(P.sum())
    cent = float((freqs * P).sum() / s) if s > 0 else 20.0
    Pf = P[fm] + 1e-20
    flat = float(np.exp(np.mean(np.log(Pf))) / np.mean(Pf)) if Pf.size else 1.0
    return unit.astype(np.float32), math.log(max(rms, 1e-6)), math.log(max(cent, 20.0)), flat


def _yin(x, sr, fmin=55.0, fmax=1600.0, thr=0.15):
    """Single-frame YIN over a whole region. Returns (f0_hz, confidence) with
    confidence = 1 - min(CMND); f0 = 0 when nothing periodic is found."""
    x = np.asarray(x, dtype=np.float64)
    x = x - x.mean()
    n = len(x)
    tau_max = min(int(sr / fmin), n // 2)
    tau_min = max(2, int(sr / fmax))
    if tau_max <= tau_min + 2:
        return 0.0, 0.0
    W = n - tau_max
    if W < tau_max // 2 or float(np.dot(x, x)) < 1e-10:
        return 0.0, 0.0
    L = 1 << int(math.ceil(math.log2(n + W)))
    a = x[:W]
    corr = np.fft.irfft(np.conj(np.fft.rfft(a, L)) * np.fft.rfft(x, L), L)[:tau_max + 1]
    cs = np.concatenate([[0.0], np.cumsum(x * x)])
    taus = np.arange(tau_max + 1)
    e_tau = cs[taus + W] - cs[taus]
    d = cs[W] + e_tau - 2.0 * corr
    d[0] = 0.0
    d = np.maximum(d, 0.0)
    cm = np.ones_like(d)
    run = np.cumsum(d[1:])
    with np.errstate(divide="ignore", invalid="ignore"):
        cm[1:] = np.where(run > 0, d[1:] * taus[1:] / run, 1.0)
    seg = cm[tau_min:tau_max]
    below = np.flatnonzero(seg < thr)
    if below.size:
        t = below[0]
        while t + 1 < seg.size and seg[t + 1] < seg[t]:
            t += 1
    else:
        t = int(np.argmin(seg))
    tau = t + tau_min
    best = float(cm[tau])
    if 1 <= tau < tau_max:  # parabolic interpolation
        y0, y1, y2 = cm[tau - 1], cm[tau], cm[tau + 1]
        den = y0 - 2 * y1 + y2
        shift = 0.5 * (y0 - y2) / den if abs(den) > 1e-12 else 0.0
        tau_f = tau + float(np.clip(shift, -1, 1))
    else:
        tau_f = float(tau)
    conf = float(np.clip(1.0 - best, 0.0, 1.0))
    if conf < 0.5 or tau_f <= 0:
        return 0.0, conf
    return float(sr / tau_f), conf


def _pitch_cost(f0a, ca, f0b, cb, unvoiced_mismatch=None):
    """Tonal/noisy continuity + pitch continuity.

    tonal : |periodicity confidence a - b|  (0 = both equally tonal/noisy,
            ~0.8 = a clearly pitched end followed by noise or vice versa).
            Works whether or not an F0 could be measured.
    pitch : cents distance / 1200, capped at one octave, counted ONLY when
            both ends are reliably voiced.
    v1.7 first release used a flat 0.15 for voiced->unvoiced but up to 4.0
    for a pitch difference, so with no same-pitch material in the corpus a
    tonal ending was continued by NOISE (reported on a flute phrase). Now a
    tonal ending prefers tonal material at another pitch over noise, and a
    noisy ending prefers noise - nothing is rejected, only ranked."""
    f0a = np.asarray(f0a, dtype=np.float64)
    f0b = np.asarray(f0b, dtype=np.float64)
    ca = np.asarray(ca, dtype=np.float64)
    cb = np.asarray(cb, dtype=np.float64)
    va = (f0a > 0) & (ca >= VOICED_CONF)
    vb = (f0b > 0) & (cb >= VOICED_CONF)
    with np.errstate(divide="ignore", invalid="ignore"):
        cents = np.abs(1200.0 * np.log2(np.where(va & vb, f0a / np.where(f0b > 0, f0b, 1.0), 1.0)))
    tonal = np.abs(np.clip(ca, 0, 1) - np.clip(cb, 0, 1))
    pitch = np.where(va & vb, np.minimum(cents, 1200.0) / 1200.0 * np.minimum(ca, cb), 0.0)
    return tonal + pitch


def _latent_region_mean(z, n_samples, a, b):
    """Mean of the latent frames whose centres fall inside samples [a, b)."""
    T = z.shape[1]
    if T == 0:
        return np.zeros(z.shape[0], np.float32)
    centres = (np.arange(T) + 0.5) * (n_samples / float(T))
    sel = np.flatnonzero((centres >= a) & (centres < b))
    if sel.size == 0:
        sel = np.array([int(np.clip(np.argmin(np.abs(centres - 0.5 * (a + b))), 0, T - 1))])
    return z[:, sel].mean(axis=1).astype(np.float32)


def verify_codec_latent(codec):
    """Check, for THIS installed codec, that latent_from_tokens really returns
    the quantized latent the decoder consumes. Any failure -> the graph uses
    spectral descriptors only (and says so in its JSON)."""
    rep = {"codec": codec.name, "ok": False}
    if not getattr(codec, "has_latent", False):
        rep["reason"] = "adapter exposes no codec latent (e.g. mock)"
        return rep
    try:
        sr = codec.sample_rate
        t = np.arange(int(0.5 * sr)) / sr
        tone = (0.30 * np.sin(2 * np.pi * 220 * t) + 0.10 * np.sin(2 * np.pi * 660 * t)).astype(np.float32)
        noise = (0.10 * np.random.default_rng(7).standard_normal(len(t))).astype(np.float32)
        tok = codec.encode(tone)
        z1 = codec.latent_from_tokens(tok)
        if z1.ndim != 2 or z1.shape[1] != tok.shape[1]:
            raise RuntimeError("latent shape %r does not match token frames %d"
                               % (z1.shape, tok.shape[1]))
        if not np.all(np.isfinite(z1)):
            raise RuntimeError("latent contains non-finite values")
        if not np.array_equal(z1, codec.latent_from_tokens(tok)):
            raise RuntimeError("latent extraction is not deterministic")
        wl, wd = codec.latent_decode_check(tok)
        m = min(len(wl), len(wd))
        rel = float(np.linalg.norm(wl[:m] - wd[:m]) / (np.linalg.norm(wd[:m]) + 1e-12))
        if rel > 1e-3:
            raise RuntimeError("decoding the extracted latent differs from decode(tokens) "
                               "(relative error %.3g)" % rel)
        z2 = codec.latent_from_tokens(codec.encode(noise))
        c = float(np.dot(_unit(z1.mean(1)), _unit(z2.mean(1))))
        if c > 0.995:
            raise RuntimeError("latent does not separate a tone from noise (cos %.4f)" % c)
        rep.update(ok=True, latent_dim=int(z1.shape[0]),
                   frames_per_second=round(z1.shape[1] / 0.5, 3),
                   decode_relative_error=rel, tone_vs_noise_cosine=round(c, 4))
    except Exception as e:  # pragma: no cover - depends on the installed codec
        rep["reason"] = "%s: %s" % (type(e).__name__, e)
    return rep


# ---------------- synthesis geometry ----------------

def _synthesis_geometry(G, H, sr):
    """Segment length Le, crossfade O, max read offset dmax for overlap-add.

    Each placed segment is grain[delta : delta + Le] under a Tukey window whose
    raised-cosine tapers are O long; segments are placed every H samples and
    O = Le - H, so neighbouring tapers sum to exactly 1 (sin^2 + cos^2). For a
    chronological run the overlapping audio is IDENTICAL (grain k+1 starts H
    samples into grain k), so the corpus recording is reconstructed exactly.
    dmax reserves a few ms of read offset for phase alignment on jumps."""
    contiguous = 0 < H < 0.95 * G
    Hs = H if contiguous else max(1, G // 2)
    dmax = int(max(0, min(_round_half_up(0.010 * sr), (G - Hs) // 4)))
    O = int(max(1, min(G - Hs - dmax, Hs)))
    return {"G": int(G), "H": int(Hs), "O": O, "Le": int(Hs + O), "dmax": dmax,
            "contiguous": bool(contiguous), "corpus_hop": int(H)}


def _tukey(Le, O, rise=True):
    w = np.ones(Le, dtype=np.float64)
    m = (np.arange(O) + 0.5) / O
    if rise:
        w[:O] = np.sin(0.5 * np.pi * m) ** 2
    w[Le - O:] = np.cos(0.5 * np.pi * m) ** 2
    return w


# ---------------- chronological adjacency ----------------

def chrono_successors(grains, sr, corpus_hop):
    """succ[i] = i+1 only when grain i+1 is the NEXT grain of the SAME
    recording: consecutive ids, same file (source_uid when both have it,
    else basename), and start times exactly one corpus hop apart. Because
    build-corpus assigns ids sequentially per file and skips silent grains
    without consuming an id, a same-basename file from another folder starts
    again at 0 s and can never pass the hop test - no false links."""
    n = len(grains)
    succ = np.full(n, -1, dtype=np.int64)
    collisions = 0
    for i in range(n - 1):
        a, b = grains[i], grains[i + 1]
        if int(b.get("id", i + 1)) != int(a.get("id", i)) + 1:
            continue
        ua, ub = a.get("source_uid"), b.get("source_uid")
        if ua and ub:
            if ua != ub:
                continue
        elif a.get("source_file") != b.get("source_file"):
            continue
        d = (float(b["start_s"]) - float(a["start_s"])) * sr
        if d < 0 and a.get("source_file") == b.get("source_file"):
            collisions += 1  # same basename, new file: correctly not linked
        # start_s is stored rounded to 0.1 ms, i.e. up to +-0.05 ms per grain:
        # at 44.1 kHz a difference of two starts can be off by 4.4 samples, so
        # a fixed 3-sample tolerance silently dropped ~11 % of genuine links
        # (v1.7.0-1.7.3). 2 % of the hop still separates 1 hop from 2 hops.
        tol = max(CHRONO_TOL_SAMPLES, 2e-4 * sr + 1, 0.02 * corpus_hop)
        if abs(d - corpus_hop) <= tol:
            succ[i] = i + 1
    return succ, collisions


def _runs(succ):
    n = len(succ)
    run_id = np.zeros(n, dtype=np.int64)
    run_pos = np.zeros(n, dtype=np.int64)
    r = -1
    for i in range(n):
        if i > 0 and succ[i - 1] == i:
            run_id[i] = run_id[i - 1]
            run_pos[i] = run_pos[i - 1] + 1
        else:
            r += 1
            run_id[i] = r
    run_len = np.bincount(run_id)
    remaining = run_len[run_id] - run_pos - 1   # grains left after this one
    return run_id, run_pos, remaining


# ---------------- approximate nearest neighbours (no new deps) ----------------

def _sqdist(Q, X, xx=None):
    if xx is None:
        xx = np.einsum("ij,ij->i", X, X)
    qq = np.einsum("ij,ij->i", Q, Q)
    return np.maximum(qq[:, None] + xx[None, :] - 2.0 * Q.dot(X.T), 0.0)


def _kmeans(X, C, rng, iters=8):
    N = len(X)
    cent = X[rng.choice(N, C, replace=False)].copy()
    xx = np.einsum("ij,ij->i", X, X)
    lab = np.zeros(N, dtype=np.int64)
    for _ in range(iters):
        for s in range(0, N, 4096):
            lab[s:s + 4096] = np.argmin(_sqdist(X[s:s + 4096], cent), axis=1)
        for c in range(C):
            m = lab == c
            if m.any():
                cent[c] = X[m].mean(axis=0)
            else:
                cent[c] = X[rng.integers(N)]
    for s in range(0, N, 4096):
        lab[s:s + 4096] = np.argmin(_sqdist(X[s:s + 4096], cent), axis=1)
    return cent, lab


def knn_search(Q, X, k, seed=0):
    """k nearest rows of X for every row of Q (squared Euclidean).

    N <= EXACT_KNN_MAX: exact, chunked. Larger: an inverted-file index
    (k-means into C ~ 4*sqrt(N) cells, each query scans only the cells
    nearest to it). Build O(N*C), queries O(Nq*(C + probed*N/C)), i.e.
    ~O(N^1.5) overall instead of the O(N^2) of all-pairs scoring.
    Returns (idx [Nq,k], sqd [Nq,k], info)."""
    Q = np.ascontiguousarray(Q, dtype=np.float32)
    X = np.ascontiguousarray(X, dtype=np.float32)
    N = len(X)
    k = int(min(k, N))
    idx = np.zeros((len(Q), k), dtype=np.int64)
    dd = np.zeros((len(Q), k), dtype=np.float32)
    if N <= EXACT_KNN_MAX:
        xx = np.einsum("ij,ij->i", X, X)
        for s in range(0, len(Q), 512):
            D = _sqdist(Q[s:s + 512], X, xx)
            part = np.argpartition(D, k - 1, axis=1)[:, :k]
            pd = np.take_along_axis(D, part, 1)
            o = np.argsort(pd, axis=1)
            idx[s:s + 512] = np.take_along_axis(part, o, 1)
            dd[s:s + 512] = np.take_along_axis(pd, o, 1)
        return idx, dd, {"method": "exact", "n": N}
    rng = np.random.default_rng(seed)
    C = int(round(4 * math.sqrt(N)))
    cent, lab = _kmeans(X, C, rng)
    order = np.argsort(lab, kind="stable")
    starts = np.searchsorted(lab[order], np.arange(C + 1))
    need = max(4 * k, 256)
    min_probe = max(8, int(round(0.02 * C)))
    for s in range(0, len(Q), 256):
        qb = Q[s:s + 256]
        dc = _sqdist(qb, cent)
        co = np.argsort(dc, axis=1)
        for r in range(len(qb)):
            cand = []
            tot = 0
            for p, c in enumerate(co[r]):
                a, b = starts[c], starts[c + 1]
                if b > a:
                    cand.append(order[a:b])
                    tot += b - a
                if p + 1 >= min_probe and tot >= need:
                    break
            cand = np.concatenate(cand)
            d = _sqdist(qb[r:r + 1], X[cand])[0]
            kk = min(k, len(cand))
            part = np.argpartition(d, kk - 1)[:kk]
            o = part[np.argsort(d[part])]
            idx[s + r, :kk] = cand[o]
            dd[s + r, :kk] = d[o]
            if kk < k:
                idx[s + r, kk:] = cand[o[-1]]
                dd[s + r, kk:] = d[o[-1]]
    return idx, dd, {"method": "ivf", "n": N, "cells": C, "min_probe": min_probe,
                     "min_candidates": need}


def _ivf_recall(Q, X, k, idx_approx, n_sample=200, seed=1):
    """Measured recall@k of the approximate search against exact search on a
    random sample of queries - stored in the graph JSON, not assumed."""
    rng = np.random.default_rng(seed)
    sel = rng.choice(len(Q), min(n_sample, len(Q)), replace=False)
    D = _sqdist(Q[sel].astype(np.float32), X.astype(np.float32))
    exact = np.argpartition(D, k - 1, axis=1)[:, :k]
    hits = [len(set(exact[i]).intersection(idx_approx[q, :k])) for i, q in enumerate(sel)]
    return float(np.sum(hits)) / (len(sel) * k)


# ---------------- graph build / load ----------------

def _graph_paths(index_prefix):
    return index_prefix + "_graph.json", index_prefix + "_graph.npz"


def _transition_components(tail_desc_i, tail_lnrms_i, tail_f0_i, tail_c_i,
                           head_desc, head_lnrms, head_f0, head_c):
    c_desc = np.linalg.norm(head_desc - tail_desc_i[None, :], axis=1)
    c_en = np.abs(head_lnrms - tail_lnrms_i) / math.log(4.0)
    c_p = _pitch_cost(np.full(len(head_f0), tail_f0_i), np.full(len(head_f0), tail_c_i),
                      head_f0, head_c)
    return c_desc.astype(np.float32), c_en.astype(np.float32), c_p.astype(np.float32)


def build_transition_graph(index_prefix, index, codec, log=sys.stderr):
    sr = int(index["sample_rate"])
    grains = index["grains"]
    N = len(grains)
    if N < 4:
        raise RuntimeError("corpus has only %d grains - too few to continue from" % N)
    G = _round_half_up(float(index["grain_ms"]) / 1000.0 * sr)
    H = _round_half_up(float(index["hop_ms"]) / 1000.0 * sr)
    # slice_grains used Python's round(); reproduce it exactly for the hop
    H_build = max(1, int(round(float(index["hop_ms"]) / 1000.0 * sr)))
    G_build = max(1, int(round(float(index["grain_ms"]) / 1000.0 * sr)))
    geo = _synthesis_geometry(G_build, H_build, sr)
    succ, collisions = chrono_successors(grains, sr, H_build)
    if not geo["contiguous"]:
        succ[:] = -1   # grains do not overlap in the corpus: no seamless chains
    run_id, run_pos, remaining = _runs(succ)

    lat_rep = verify_codec_latent(codec)
    use_lat = bool(lat_rep.get("ok"))
    log.write("Continuation graph: %d grains, descriptor = %s\n"
              % (N, "codec latent + spectral" if use_lat else "spectral only"))
    if not use_lat:
        log.write("  (latent unavailable: %s)\n" % lat_rep.get("reason"))

    O, Le, Hs = geo["O"], geo["Le"], geo["H"]
    spec = {r: np.zeros((N, N_SPEC_BANDS), np.float32) for r in ("head", "tail", "glob")}
    lnrms = {r: np.zeros(N, np.float32) for r in ("head", "tail", "glob")}
    lncent = {r: np.zeros(N, np.float32) for r in ("head", "tail", "glob")}
    flat = np.zeros(N, np.float32)
    f0 = {r: np.zeros(N, np.float32) for r in ("head", "tail", "glob")}
    conf = {r: np.zeros(N, np.float32) for r in ("head", "tail", "glob")}
    real_len = np.zeros(N, np.int64)
    real_src = np.zeros(N, np.int8)  # 1 = from index, 2 = detected, 0 = full
    lat_raw = {r: None for r in ("head", "tail", "glob")}

    for i, gm in enumerate(grains):
        gp = _resolve_grain_path(index_prefix, gm["grain_audio"])
        if not os.path.isfile(gp):
            raise RuntimeError("corpus grain audio missing: %s (grain id %s)" % (gp, gm.get("id")))
        g = np.load(gp).astype(np.float64)
        L = len(g)
        if "real_samples" in gm:
            rl = int(min(L, int(gm["real_samples"])))
            real_src[i] = 1
        elif succ[i] >= 0:
            rl = L   # a grain followed by its own next grain was never padded
        else:
            # Possibly the last grain of its file: slice_grains zero-pads ONLY
            # that one. Count exact trailing zeros; a grain whose audio runs
            # to its end (file length happened to fit) keeps its full length.
            nz = np.flatnonzero(g != 0.0)
            rl = int(nz[-1] + 1) if nz.size else 0
            if rl < L:
                real_src[i] = 2
        real_len[i] = rl
        x = g[:max(rl, 1)]
        if rl >= Le:
            reg = {"head": (0, O), "tail": (Hs, Le), "glob": (0, rl)}
        else:
            reg = {"head": (0, min(O, rl)), "tail": (max(0, rl - O), rl), "glob": (0, rl)}
        for r, (a, b) in reg.items():
            seg = x[a:b]
            u, lr, lc, fl = _region_spectral(seg, sr)
            spec[r][i], lnrms[r][i], lncent[r][i] = u, lr, lc
            if r == "glob":
                flat[i] = fl
            f, c = _yin(seg, sr)
            f0[r][i], conf[r][i] = f, c
        if use_lat:
            z = codec.latent_from_tokens(codec.encode(x.astype(np.float32)))
            for r, (a, b) in reg.items():
                v = _latent_region_mean(z, len(x), a, b)
                if lat_raw[r] is None:
                    lat_raw[r] = np.zeros((N, len(v)), np.float32)
                lat_raw[r][i] = v
        if (i + 1) % 500 == 0:
            log.write("  analysed %d / %d grains\n" % (i + 1, N))

    pca_mean = pca_comp = None
    if use_lat:
        stack = np.concatenate([lat_raw["head"], lat_raw["tail"], lat_raw["glob"]], axis=0)
        pca_mean = stack.mean(axis=0)
        Xc = (stack - pca_mean).astype(np.float64)
        cov = Xc.T.dot(Xc) / max(1, len(Xc) - 1)
        w, V = np.linalg.eigh(cov)
        dim = min(LATENT_PCA_DIM, V.shape[1])
        pca_comp = V[:, ::-1][:, :dim].T.astype(np.float32)   # [dim, D]

    def desc_of(r):
        if not use_lat:
            return spec[r].copy()
        lp = (lat_raw[r] - pca_mean).dot(pca_comp.T)
        lu = lp / np.maximum(np.linalg.norm(lp, axis=1, keepdims=True), 1e-9)
        return np.concatenate([SPEC_W * spec[r], LAT_W * lu], axis=1).astype(np.float32)

    head_d, tail_d, glob_d = desc_of("head"), desc_of("tail"), desc_of("glob")
    quiet_head = lnrms["head"] < math.log(1e-4)
    usable = (real_len >= Le) & ~quiet_head
    # Level of each grain RELATIVE to its own recording (95th percentile of
    # that file's grains). Grains > 30 dB below their recording are
    # background (room tone, hiss between events): their level-invariant
    # spectral shape can resemble a faint ending, but they are never chosen
    # as a starting point or a jump target (a chronological chain may still
    # pass through them).
    fkey = [g.get("source_uid") or "%s#%d" % (g.get("source_file"), 0) for g in grains]
    # old indexes: split same-basename files where start time restarts
    seg_no, prev = 0, None
    for i, g in enumerate(grains):
        if not g.get("source_uid"):
            if prev is not None and grains[prev].get("source_file") == g.get("source_file") \
                    and float(g["start_s"]) < float(grains[prev]["start_s"]):
                seg_no += 1
            fkey[i] = "%s#%d" % (g.get("source_file"), seg_no)
        prev = i
    rel_level = np.zeros(N, np.float32)
    keys = {}
    for i, k in enumerate(fkey):
        keys.setdefault(k, []).append(i)
    for k, idxs in keys.items():
        ref = float(np.percentile(lnrms["glob"][idxs], 95))
        rel_level[idxs] = lnrms["glob"][idxs] - ref
    background = rel_level < math.log(10 ** (-30 / 20.0))

    # ---- cross edges: tail_i -> head_j, approximate retrieval + re-rank ----
    base_idx = np.flatnonzero(usable & ~background)
    if base_idx.size < 2:
        base_idx = np.flatnonzero(usable)
    if base_idx.size < 2:
        raise RuntimeError("fewer than 2 corpus grains are long/loud enough to place")
    m = int(min(GRAPH_RETRIEVE_M + 8, base_idx.size))
    nn, _, kinfo = knn_search(tail_d, head_d[base_idx], m)
    if kinfo["method"] == "ivf":
        kinfo["recall_at_%d" % m] = round(_ivf_recall(tail_d, head_d[base_idx], m, nn), 4)
    K = int(min(GRAPH_K, base_idx.size - 1))
    e_dst = np.full((N, K), -1, np.int32)
    e_cd = np.zeros((N, K), np.float32)
    e_ce = np.zeros((N, K), np.float32)
    e_cp = np.zeros((N, K), np.float32)
    for i in range(N):
        cand = base_idx[nn[i]]
        keep = (cand != i) & (cand != succ[i]) & ~((run_id[cand] == run_id[i])
                                                    & (np.abs(run_pos[cand] - run_pos[i]) <= 2))
        cand = cand[keep]
        if cand.size == 0:
            continue
        cd, ce, cp = _transition_components(tail_d[i], lnrms["tail"][i], f0["tail"][i], conf["tail"][i],
                                            head_d[cand], lnrms["head"][cand], f0["head"][cand], conf["head"][cand])
        tot = cd + 1.0 * ce + 0.5 * cp
        o = np.argsort(tot, kind="stable")[:K]
        k = len(o)
        e_dst[i, :k] = cand[o]
        e_cd[i, :k], e_ce[i, :k], e_cp[i, :k] = cd[o], ce[o], cp[o]

    # chronological edge costs (for metadata / suitability checks)
    s_cd = np.zeros(N, np.float32)
    has = succ >= 0
    if has.any():
        a = np.flatnonzero(has)
        s_cd[a] = np.linalg.norm(tail_d[a] - head_d[succ[a]], axis=1)

    arrays = dict(
        head_desc=head_d, tail_desc=tail_d, glob_desc=glob_d,
        lnrms_head=lnrms["head"], lnrms_tail=lnrms["tail"], lnrms_glob=lnrms["glob"],
        lncent_glob=lncent["glob"], flat_glob=flat,
        f0_head=f0["head"], conf_head=conf["head"], f0_tail=f0["tail"], conf_tail=conf["tail"],
        f0_glob=f0["glob"], conf_glob=conf["glob"],
        real_len=real_len, real_src=real_src, usable=usable.astype(np.int8),
        rel_level=rel_level, background=background.astype(np.int8),
        succ=succ, run_id=run_id, run_pos=run_pos, remaining=remaining,
        edge_dst=e_dst, edge_c_desc=e_cd, edge_c_energy=e_ce, edge_c_pitch=e_cp,
        succ_c_desc=s_cd,
    )
    if use_lat:
        arrays["pca_mean"] = pca_mean.astype(np.float32)
        arrays["pca_comp"] = pca_comp
    info = {
        "graph_schema": GRAPH_SCHEMA_VERSION,
        "n_grains": N,
        "codec": index["codec"],
        "sample_rate": sr,
        "grain_ms": index["grain_ms"],
        "hop_ms": index["hop_ms"],
        "geometry": geo,
        "descriptor": {"mode": "latent+spectral" if use_lat else "spectral",
                       "spectral_bands": N_SPEC_BANDS,
                       "latent_pca_dim": int(pca_comp.shape[0]) if use_lat else 0,
                       "latent_check": lat_rep},
        "retrieval": kinfo,
        "edges_per_grain": K,
        "n_chrono_links": int((succ >= 0).sum()),
        "n_runs": int(run_id.max() + 1),
        "basename_restarts_not_linked": int(collisions),
        "n_usable": int(usable.sum()),
        "n_background": int(background.sum()),
        "n_padded_detected": int((real_src == 2).sum()),
        "n_real_samples_from_index": int((real_src == 1).sum()),
    }
    return arrays, info


def _write_graph_atomic(index_prefix, arrays, info, identity):
    jpath, npath = _graph_paths(index_prefix)
    tag = "%d_%d" % (os.getpid(), int(time.time() * 1000))
    ntmp = npath + ".tmp_" + tag + ".npz"
    jtmp = jpath + ".tmp_" + tag
    try:
        np.savez(ntmp, **arrays)
        info = dict(info)
        info.update(identity)
        info["npz_sha256"] = _sha256_file(ntmp)
        with open(jtmp, "w") as f:
            json.dump(info, f, indent=1)
        os.replace(ntmp, npath)   # npz first ...
        os.replace(jtmp, jpath)   # ... JSON last: it is the commit record
    finally:
        for p in (ntmp, jtmp):
            if os.path.exists(p):
                try:
                    os.remove(p)
                except OSError:
                    pass
    return info


def _graph_identity(index_prefix, index):
    return {"index_json_sha256": _sha256_file(index_prefix + ".json"),
            "feats_sha256": index.get("feats_sha256"),
            "corpus_schema_version": index.get("schema_version")}


def load_or_build_graph(index_prefix, index, codec, rebuild=False, log=sys.stderr):
    """Return (arrays, info, built_now, reason). Rebuilds when missing, when
    its schema differs, or when it belongs to a different corpus index (e.g.
    after Build / replace corpus) - never touches the corpus itself."""
    jpath, npath = _graph_paths(index_prefix)
    ident = _graph_identity(index_prefix, index)
    reason = "requested" if rebuild else None
    if not reason:
        if not (os.path.isfile(jpath) and os.path.isfile(npath)):
            reason = "no graph cache yet"
        else:
            try:
                with open(jpath) as f:
                    info = json.load(f)
                if info.get("graph_schema") != GRAPH_SCHEMA_VERSION:
                    reason = "graph schema %r != %d" % (info.get("graph_schema"), GRAPH_SCHEMA_VERSION)
                elif info.get("index_json_sha256") != ident["index_json_sha256"]:
                    reason = "corpus index changed since the graph was built"
                elif info.get("codec") != index["codec"]:
                    reason = "codec mismatch"
                elif info.get("npz_sha256") != _sha256_file(npath):
                    reason = "graph arrays do not match their JSON record (torn write)"
                else:
                    with np.load(npath) as z:
                        arrays = {k: z[k] for k in z.files}
                    return arrays, info, False, "valid cache"
            except Exception as e:
                reason = "unreadable graph cache (%s)" % e
    log.write("Building continuation graph (%s)...\n" % reason)
    t0 = time.time()
    arrays, info = build_transition_graph(index_prefix, index, codec, log=log)
    info["build_seconds"] = round(time.time() - t0, 2)
    info = _write_graph_atomic(index_prefix, arrays, info, ident)
    log.write("Continuation graph written in %.1f s\n" % info["build_seconds"])
    return arrays, info, True, reason


# ---------------- source analysis ----------------

def analyse_source_activity(x, sr, trim=True):
    """Find where the source's meaningful sound ends.

    analysis_end : end of the last ACTIVE region (adaptive threshold with
                   hysteresis, so a soft release or breath above the noise
                   floor still counts as sound). The terminal analysis window
                   ends here.
    join_end     : where the source is CUT for the join. Equal to the full
                   length unless trim is on AND the material after
                   analysis_end is clearly silence (long enough, and well
                   below both the release threshold and the noise floor + 10 dB).
                   Then the cut is analysis_end + 20 ms guard. Conservative by
                   design: uncertain cases are never trimmed."""
    n = len(x)
    fn = max(1, _round_half_up(0.010 * sr))
    nf = n // fn
    out = {"n": n, "analysis_end": n, "strong_end": n, "join_end": n, "trimmed": 0,
           "first_active": 0, "policy": "none"}
    if nf < 5:
        return out
    fr = x[:nf * fn].reshape(nf, fn)
    db = 20 * np.log10(np.sqrt(np.mean(fr * fr, axis=1)) + 1e-10)
    if nf >= 3:  # 3-frame median against single clicks
        db = np.median(np.stack([db, np.r_[db[0], db[:-1]], np.r_[db[1:], db[-1]]]), axis=0)
    # floor = quietest (median-filtered) frame: a short silent ending is only
    # a few % of the frames, so a percentile would land on the music itself
    peak, floor = float(np.percentile(db, 95)), float(db.min())
    out.update(peak_db=round(peak, 2), floor_db=round(floor, 2))
    if peak < -80:
        out["policy"] = "silent source"
        return out
    if peak - floor < 20:
        out["policy"] = "no distinct silence (dynamic range < 20 dB)"
        return out
    thr_on = max(floor + 15.0, peak - 45.0)
    thr_off = max(floor + 8.0, peak - 55.0)
    on = np.flatnonzero(db >= thr_on)
    if on.size == 0:
        return out
    e = int(on[-1])
    strong_end = min(n, (e + 1) * fn)        # end of the last STRONG sound
    while e + 1 < nf and db[e + 1] >= thr_off:
        e += 1
    analysis_end = min(n, (e + 1) * fn)
    # A quiet release that is still PITCHED (a fading flute note) is sound,
    # not silence, even below thr_off: extend through it in 50 ms chunks
    # while YIN finds clear periodicity a few dB above the noise floor.
    cn = _round_half_up(0.050 * sr)

    def periodic(a):
        seg = x[a:a + cn]
        if len(seg) < cn:
            return False
        lvl = 20 * math.log10(float(np.sqrt(np.mean(seg * seg))) + 1e-10)
        f, c = _yin(seg, sr)
        return f > 0 and c >= 0.75 and lvl >= floor + 3.0

    while analysis_end + cn <= n and periodic(analysis_end):
        analysis_end += cn
    first_active = int(on[0]) * fn
    out.update(analysis_end=analysis_end, strong_end=strong_end, first_active=first_active,
               thr_on_db=round(thr_on, 2), thr_off_db=round(thr_off, 2))
    e2 = min(nf - 1, analysis_end // fn)
    tail_db = db[e2:]
    tail_len = n - analysis_end
    tail_periodic = any(periodic(a) for a in range(analysis_end, max(analysis_end, n - cn) + 1, cn))
    clearly_silent = (tail_len >= 0.10 * sr and tail_db.size > 0
                      and float(tail_db.max()) < thr_off
                      and float(tail_db.max()) < floor + 10.0
                      and not tail_periodic)
    if trim and clearly_silent:
        je = min(n, analysis_end + _round_half_up(0.020 * sr))
        out.update(join_end=je, trimmed=n - je, policy="trimmed clearly silent tail")
    elif tail_len > 0:
        out["policy"] = ("trim disabled" if not trim else
                         "trailing material not clearly silent - kept")
    else:
        out["policy"] = "sound runs to the end"
    return out


def analyse_terminal(xc, sr_c, ae_c, codec, arrays, info, cat_cb):
    """Terminal-state representation of the source (at the corpus rate):
    global identity, boundary (last O samples), trajectory (slopes over six
    sub-windows), pitch, categorical token feature."""
    geo = info["geometry"]
    O, G = geo["O"], geo["G"]
    use_lat = info["descriptor"]["mode"] == "latent+spectral"
    W = _round_half_up(0.300 * sr_c)
    W = int(min(W, ae_c))
    act_len = ae_c
    if act_len < 0.6 * sr_c:
        W = int(max(min(ae_c, _round_half_up(0.05 * sr_c)), act_len // 2))
    if W < _round_half_up(0.03 * sr_c):
        raise RuntimeError("source has less than 30 ms of active sound to continue from")
    seg = np.asarray(xc[ae_c - W:ae_c], dtype=np.float64)
    z = None
    if use_lat:
        z = codec.latent_from_tokens(codec.encode(seg.astype(np.float32)))
        pm, pc = arrays["pca_mean"], arrays["pca_comp"]

    def region(a, b):
        u, lr, lc, fl = _region_spectral(seg[a:b], sr_c)
        f, c = _yin(seg[a:b], sr_c)
        if use_lat:
            lp = (_latent_region_mean(z, len(seg), a, b) - pm).dot(pc.T)
            d = np.concatenate([SPEC_W * u, LAT_W * _unit(lp)])
        else:
            d = u
        return {"desc": d.astype(np.float32), "lnrms": lr, "lncent": lc, "flat": fl, "f0": f, "conf": c}

    glob = region(0, W)
    bnd = region(max(0, W - O), W)
    nsub = 6
    L = max(int(W // 3), 32)
    hop = max(1, (W - L) // (nsub - 1))
    subs = [region(s * hop, min(W, s * hop + L)) for s in range(nsub)]
    tc = np.array([(s * hop + 0.5 * L) / sr_c for s in range(nsub)])

    def slope(vals, mask=None):
        vals = np.asarray(vals, float)
        m = np.ones(len(vals), bool) if mask is None else mask
        if m.sum() < 3 or np.ptp(tc[m]) <= 0:
            return 0.0
        return float(np.polyfit(tc[m], vals[m], 1)[0])

    vmask = np.array([s["f0"] > 0 and s["conf"] >= VOICED_CONF for s in subs])
    cents = np.array([1200 * math.log2(s["f0"] / 440.0) if s["f0"] > 0 else 0.0 for s in subs])
    d0 = np.mean([subs[0]["desc"], subs[1]["desc"]], axis=0)
    d1 = np.mean([subs[-2]["desc"], subs[-1]["desc"]], axis=0)
    dt = max(1e-3, float(tc[-1] - tc[0]) * (2.0 / 3.0))
    # categorical identity (existing token-histogram + bigram feature) on a
    # window the SAME length as a corpus grain
    cseg = seg[-G:] if len(seg) >= G else seg
    cat = grain_feature(codec.encode(cseg.astype(np.float32)), cat_cb)
    return {
        "window_samples": W, "glob": glob, "boundary": bnd, "subs": subs,
        "slope_lnrms": slope([s["lnrms"] for s in subs]),
        "slope_lncent": slope([s["lncent"] for s in subs]),
        "slope_cents": slope(cents, vmask),
        "voiced_subwindows": int(vmask.sum()),
        "desc_end": _unit(subs[-1]["desc"]),
        "desc_velocity": ((d1 - d0) / dt).astype(np.float32),
        "cat_feature": cat,
    }


def _cat_distance(feats_path, q):
    """Cosine distance between the source's categorical token feature and every
    stored corpus feature, streamed from a memory-mapped _feats.npy."""
    F = np.load(feats_path, mmap_mode="r")
    qn = float(np.linalg.norm(q)) + 1e-9
    out = np.zeros(F.shape[0], np.float32)
    for s in range(0, F.shape[0], 2048):
        blk = np.asarray(F[s:s + 2048], dtype=np.float32)
        out[s:s + 2048] = 1.0 - blk.dot(q) / ((np.linalg.norm(blk, axis=1) + 1e-9) * qn)
    return out


# ---------------- sequence planning ----------------

class _Trajectory:
    """Damped extrapolation of the source's terminal motion. Each quantity
    starts at the source's END state and keeps moving in the direction it was
    moving, saturating with time constant tau (so a 4 s tail does not run
    away), and is clamped to a bounded total change."""

    def __init__(self, term, tau=0.6):
        self.tau = tau
        self.d_end = term["desc_end"]
        self.v = term["desc_velocity"]
        self.lc_end = term["subs"][-1]["lncent"]
        self.s_lc = term["slope_lncent"]
        self.s_lr = term["slope_lnrms"]
        b = term["boundary"]
        self.voiced = b["f0"] > 0 and b["conf"] >= VOICED_CONF
        self.f0_end = b["f0"] if self.voiced else 0.0
        self.conf_end = float(np.clip(b["conf"], 0.0, 1.0))
        self.s_cents = term["slope_cents"] if term["voiced_subwindows"] >= 3 else 0.0
        self.lr_anchor = 0.0

    def damp(self, t):
        t = max(0.0, t)
        return self.tau * (1.0 - math.exp(-t / self.tau))

    def desc(self, t):
        dv = self.v * self.damp(t)
        nv = float(np.linalg.norm(dv))
        if nv > 0.5:
            dv = dv * (0.5 / nv)
        return _unit(self.d_end + dv)

    def lncent(self, t):
        return self.lc_end + float(np.clip(self.s_lc * self.damp(t), -0.7, 0.7))

    def lnrms(self, t):
        return self.lr_anchor + float(np.clip(self.s_lr * self.damp(t), -math.log(2), math.log(2)))

    def f0(self, t):
        if not self.voiced:
            return 0.0
        c = float(np.clip(self.s_cents * self.damp(t), -150.0, 150.0))
        return self.f0_end * 2.0 ** (c / 1200.0)


def _strength_params(mode, s):
    """Continuation Strength s in [0,1] -> concrete selection parameters.
    Changes WEIGHTS, the PERMISSIBLE candidate set, and how fast the
    attachment to the source decays - not an output effect."""
    if mode == "tight":
        return {"jump0": 0.6 + 0.8 * s, "jump_tau": 0.6, "dwell_pen": 0.5,
                "w_tr": 1.5, "w_id": 0.4 + 1.6 * s, "w_traj": 0.3 + 0.9 * s,
                "w_pt": 1.0 + 2.0 * s, "wp_tr": 1.0, "unvoiced_pen": 0.10,
                "switch_margin": 0.15 + 0.6 * (1 - s), "ident_quantile": 0.15 + 0.85 * (1 - s),
                "topk": 1, "temp": 0.0, "decay": None, "run_pen": 0.0, "run_L0": None}
    return {"jump0": 0.3 + 0.6 * s, "jump_tau": 0.35, "dwell_pen": 0.3,
            "w_tr": 1.0, "w_id": 0.3 + 1.2 * s, "w_traj": 0.2 + 0.6 * s,
            "w_pt": 1.0 + 2.0 * s, "wp_tr": 0.6, "unvoiced_pen": 0.0,
            "switch_margin": 0.0, "ident_quantile": 0.35 + 0.65 * (1 - s),
            "topk": 3 + _round_half_up(9 * (1 - s)), "temp": 0.03 + 0.25 * (1 - s),
            "decay": 0.5 + 1.5 * s, "run_pen": 0.15 + 0.35 * (1 - s), "run_L0": 0.3 + 1.2 * s}


def plan_sequence(arrays, info, term, ident, mode, strength, n_steps, step_time,
                  tail_seconds, grain_loader, src_region, rng, src_offset0=0):
    """Choose one corpus grain (and read offset) per synthesis step.

    step_time(k) -> seconds relative to the join (negative inside the
    crossfade). Returns a list of step dicts."""
    geo = info["geometry"]
    H, O, Le, dmax = geo["H"], geo["O"], geo["Le"], geo["dmax"]
    sr = info["sample_rate"]
    P = _strength_params(mode, strength)
    usable = arrays["usable"].astype(bool)
    foreground = usable & ~arrays["background"].astype(bool)
    if foreground.sum() < 2:
        foreground = usable
    succ, run_id, run_pos = arrays["succ"], arrays["run_id"], arrays["run_pos"]
    real_len = arrays["real_len"]
    head_d, tail_d, glob_d = arrays["head_desc"], arrays["tail_desc"], arrays["glob_desc"]
    lr_h, lr_t, lr_g = arrays["lnrms_head"], arrays["lnrms_tail"], arrays["lnrms_glob"]
    lc_g = arrays["lncent_glob"]
    f0_h, c_h, f0_t, c_t = arrays["f0_head"], arrays["conf_head"], arrays["f0_tail"], arrays["conf_tail"]
    f0_g, c_g = arrays["f0_glob"], arrays["conf_glob"]
    traj = _Trajectory(term)
    # Permissibility judges spectral/categorical identity AND tonal character:
    # filtering on spectral shape alone removed every pitched grain before the
    # tonal term was ever weighed (a breathy flute's band shape resembles hiss).
    conf_end = float(np.clip(term["boundary"]["conf"], 0.0, 1.0))
    perm_score = ident + np.abs(conf_end - np.clip(c_g, 0.0, 1.0))
    ident_limit = float(np.quantile(perm_score[foreground], min(1.0, P["ident_quantile"])))
    recent_window = max(2, int(math.ceil(1.5 * sr / H)))
    last_used = {}
    use_count = {}
    recent_runs = []  # (run_id, run_pos, step)

    def w_id(t):
        if P["decay"] is None:
            return P["w_id"]
        return P["w_id"] * math.exp(-max(0.0, t) / max(1e-3, P["decay"] * tail_seconds))

    def w_traj(t):
        if P["decay"] is None:
            return P["w_traj"]
        return P["w_traj"] * math.exp(-max(0.0, t) / max(1e-3, P["decay"] * tail_seconds))

    def w_pt(t):
        # tonal/pitch attachment: constant in Tight; in Textural it decays
        # with the identity, so a pitched ending may drift toward noisier
        # material LATER in the tail but does not start there
        if P["decay"] is None:
            return P["w_pt"]
        return P["w_pt"] * math.exp(-max(0.0, t) / max(1e-3, P["decay"] * tail_seconds))

    def traj_cost(js, t):
        dd = np.linalg.norm(glob_d[js] - traj.desc(t)[None, :], axis=1)
        dc = np.abs(lc_g[js] - traj.lncent(t)) / math.log(2.0)
        de = np.abs(lr_g[js] - traj.lnrms(t)) / math.log(4.0)
        return 0.5 * dd + 0.3 * dc + 0.2 * de

    def pitch_target_cost(js, t):
        ft = traj.f0(t)
        if ft <= 0:
            # unpitched ending: still keep its tonal/noisy character
            return np.abs(traj.conf_end - np.clip(c_g[js], 0, 1))
        return _pitch_cost(np.full(len(js), ft), np.full(len(js), traj.conf_end),
                           f0_g[js], c_g[js])

    replay_back = max(3, int(math.ceil(0.6 * sr / H)))
    dwell_steps = max(1, int(math.ceil(0.30 * sr / H)))
    last_jump = [0]

    def jump_cost(t, k):
        """Rate-of-change control: leaving the chronological chain costs
        extra at the START of the tail (the continuation first sustains like
        the source) and gets cheaper over time; a second jump within 0.3 s of
        the previous one costs more (no rapid-fire splicing)."""
        c = P["jump0"] * math.exp(-max(0.0, t) / max(1e-3, P["jump_tau"] * tail_seconds))
        if k - last_jump[0] < dwell_steps:
            c += P["dwell_pen"]
        return c

    def early(t):
        # 0 at the join -> 1 later: scales Textural's push for variety
        return 1.0 - math.exp(-max(0.0, t) / max(1e-3, P["jump_tau"] * tail_seconds))

    def rep_cost(js, k, jump=True):
        """Immediate reuse of a grain costs 0.6. For JUMPS, also landing in
        the same recording shortly BEFORE (or just after) recently played
        material costs 0.4: following the chain from there would replay what
        was just heard - the short-cycle case."""
        r = np.zeros(len(js))
        for n, j in enumerate(js):
            if j in last_used and k - last_used[j] <= recent_window:
                r[n] += 0.6
            # grows with every reuse anywhere in the tail, so a small corpus
            # cannot settle into an endless loop of the same fragment
            r[n] += 0.25 * use_count.get(j, 0)
            if not jump:
                continue
            for (rr, rp, ks) in recent_runs:
                if (run_id[j] == rr and rp - replay_back <= run_pos[j] <= rp + 3
                        and k - ks <= recent_window):
                    r[n] += 0.4
                    break
        return r

    def best_delta(prev, prev_delta, j, src_offset=0):
        """Read offset into grain j (0..dmax) maximising correlation of the
        overlap with the outgoing segment - reduces phase cancellation."""
        gj = grain_loader(j)
        if prev is None:
            ref = src_region
        else:
            gi = grain_loader(prev)
            ref = gi[prev_delta + H: prev_delta + Le]
        best, rho_best = 0, -2.0
        lim = int(min(dmax, real_len[j] - Le))
        if lim < 0 or ref is None or len(ref) < 8:
            return 0, 0.0
        r0 = ref - ref.mean()
        rn = float(np.linalg.norm(r0))
        for d in range(0, lim + 1, max(1, lim // 40) if lim > 40 else 1):
            seg = gj[d + src_offset:d + src_offset + len(ref)]
            if len(seg) < len(ref):
                break
            s0 = seg - seg.mean()
            den = rn * float(np.linalg.norm(s0))
            rho = float(np.dot(r0, s0) / den) if den > 1e-12 else 0.0
            if rho > rho_best:
                best, rho_best = d, rho
        return best, max(0.0, rho_best)

    steps = []
    # ---------- step 0: initial grain ----------
    t0 = step_time(0)
    cand = np.flatnonzero(foreground)
    allowed = cand[perm_score[cand] <= ident_limit]
    if allowed.size == 0:
        allowed = cand
    b = term["boundary"]
    bnd = (np.linalg.norm(head_d[allowed] - b["desc"][None, :], axis=1)
           + 0.5 * P["wp_tr"] * _pitch_cost(np.full(allowed.size, b["f0"]),
                                            np.full(allowed.size, b["conf"]),
                                            f0_h[allowed], c_h[allowed]))
    # trajectory WITHOUT the level term at t0 (absolute corpus vs source
    # level differs arbitrarily; the tail is gain-matched afterwards)
    tdd = np.linalg.norm(glob_d[allowed] - traj.desc(t0)[None, :], axis=1)
    tdc = np.abs(lc_g[allowed] - traj.lncent(t0)) / math.log(2.0)
    cost0 = (1.2 * bnd + w_id(t0) * ident[allowed] + w_traj(t0) * (0.5 * tdd + 0.3 * tdc)
             + w_pt(t0) * pitch_target_cost(allowed, t0))
    if mode == "tight":
        chain_s = arrays["remaining"][allowed] * H / float(sr)
        cost0 = cost0 + 0.2 * np.maximum(0.0, 1.0 - chain_s / 1.0)
    # The grain that meets the source is always the best match (both modes):
    # Textural's sampling starts from the second step, so the join itself is
    # never a low-probability draw.
    n0 = int(np.argmin(cost0))
    j0 = int(allowed[n0])
    # the source's join region coincides with grain0[delta + pre : ...]
    d0, rho0 = best_delta(None, 0, j0, src_offset=src_offset0)
    traj.lr_anchor = float(lr_h[j0])
    steps.append({"k": 0, "grain": j0, "delta": d0, "kind": "start", "rho": rho0,
                  "cost": round(float(cost0[n0]), 5), "fallback": None})
    last_used[j0] = 0
    use_count[j0] = 1
    recent_runs.append((int(run_id[j0]), int(run_pos[j0]), 0))
    run_len_steps = 1

    for k in range(1, n_steps):
        t = step_time(k)
        i = steps[-1]["grain"]
        di = steps[-1]["delta"]
        fallback = None
        s = int(succ[i])
        s_ok = s >= 0 and usable[s] and real_len[s] >= di + Le
        e = arrays["edge_dst"][i]
        valid = e >= 0
        ej = e[valid].astype(np.int64)
        tr_e = (arrays["edge_c_desc"][i][valid] + 1.0 * arrays["edge_c_energy"][i][valid]
                + P["wp_tr"] * arrays["edge_c_pitch"][i][valid])
        ok = foreground[ej]
        ej, tr_e = ej[ok], tr_e[ok]
        perm = perm_score[ej] <= ident_limit
        if ej.size and perm.any():
            ej, tr_e = ej[perm], tr_e[perm]
        elif ej.size:
            fallback = "identity constraint relaxed (no permissible graph neighbour)"
        if ej.size == 0 and not s_ok:
            # dead end: direct search of every usable head from this tail
            allj = np.flatnonzero(foreground & (np.arange(len(usable)) != i))
            cd, ce, cp = _transition_components(tail_d[i], lr_t[i], f0_t[i], c_t[i],
                                                head_d[allj], lr_h[allj], f0_h[allj], c_h[allj])
            tr_all = cd + 1.0 * ce + P["wp_tr"] * cp
            o = np.argsort(tr_all, kind="stable")[:32]
            ej, tr_e = allj[o], tr_all[o]
            fallback = "graph dead end - searched all heads directly"

        def score(js, tr, jump=True):
            return (P["w_tr"] * tr + w_id(t) * ident[js] + w_traj(t) * traj_cost(js, t)
                    + w_pt(t) * pitch_target_cost(js, t) + rep_cost(js, k, jump)
                    + (jump_cost(t, k) if jump else 0.0))

        sc_alt = score(ej, tr_e) if ej.size else np.zeros(0)
        choice, kind, delta, rho, cst = None, None, 0, 1.0, 0.0
        if s_ok:
            tr_s = float(arrays["succ_c_desc"][i])
            sc_s = float(score(np.array([s]), np.array([tr_s]), jump=False)[0])
            if mode == "textural":
                run_s = run_len_steps * H / float(sr)
                sc_s += early(t) * P["run_pen"] * max(0.0, run_s - P["run_L0"]) / P["run_L0"]
                pool = np.concatenate([[s], ej])
                sc = np.concatenate([[sc_s], sc_alt])
                n = _select(sc, P, rng)
                choice, cst = int(pool[n]), float(sc[n])
                kind = "chrono" if n == 0 else "graph"
            else:
                best_alt = float(sc_alt.min()) if sc_alt.size else float("inf")
                if sc_s <= best_alt + P["switch_margin"]:
                    choice, kind, cst = s, "chrono", sc_s
                else:
                    n = int(np.argmin(sc_alt))
                    choice, kind, cst = int(ej[n]), "graph", float(sc_alt[n])
        else:
            n = _select(sc_alt, P, rng)
            choice, kind, cst = int(ej[n]), "graph", float(sc_alt[n])
        if kind == "chrono":
            delta, rho = di, 1.0
            run_len_steps += 1
        else:
            delta, rho = best_delta(i, di, choice)
            run_len_steps = 1
            last_jump[0] = k
            if fallback and fallback.startswith("graph dead end"):
                kind = "fallback"
        steps.append({"k": k, "grain": choice, "delta": int(delta), "kind": kind,
                      "rho": float(rho), "cost": round(cst, 5), "fallback": fallback})
        last_used[choice] = k
        use_count[choice] = use_count.get(choice, 0) + 1
        recent_runs.append((int(run_id[choice]), int(run_pos[choice]), k))
        if len(recent_runs) > 4 * recent_window:
            recent_runs.pop(0)
    return steps, {"ident_limit": ident_limit, "params": P,
                   "trajectory": {"voiced_end": traj.voiced, "f0_end": traj.f0_end,
                                  "slope_cents_per_s": traj.s_cents,
                                  "slope_lncent_per_s": traj.s_lc,
                                  "slope_lnrms_per_s": traj.s_lr}}


def _select(costs, P, rng):
    """Tight: deterministic argmin (ties -> lowest index). Textural: sample
    from the top-K by a softmax over normalised cost with temperature."""
    costs = np.asarray(costs, dtype=np.float64)
    if costs.size == 1 or P["topk"] <= 1 or P["temp"] <= 0:
        return int(np.argmin(costs))
    k = int(min(P["topk"], costs.size))
    o = np.argsort(costs, kind="stable")[:k]
    c = costs[o]
    spread = max(1e-6, float(c[-1] - c[0]))
    z = -(c - c[0]) / spread / P["temp"]
    p = np.exp(z - z.max())
    p /= p.sum()
    return int(o[int(rng.choice(k, p=p))])


# ---------------- rendering ----------------

def render_sequence(steps, info, grain_loader, n_out):
    """Overlap-add the planned segments on the corpus-rate grid. Tukey tapers
    sum to exactly 1 between neighbours; on a JUMP the overlap is additionally
    corrected by 1/sqrt(f^2 + r^2 + 2 rho f r) (rho = measured correlation),
    i.e. unity for correlated material and equal-power for uncorrelated
    material, so a splice neither dips nor bulges."""
    geo = info["geometry"]
    H, O, Le = geo["H"], geo["O"], geo["Le"]
    out = np.zeros(n_out + Le + H, dtype=np.float64)
    gain = np.ones_like(out)
    w_first = _tukey(Le, O, rise=False)
    w = _tukey(Le, O, rise=True)
    m = (np.arange(O) + 0.5) / O
    f_fall = np.cos(0.5 * np.pi * m) ** 2
    f_rise = np.sin(0.5 * np.pi * m) ** 2
    for st in steps:
        p = st["k"] * H
        if p >= len(out):
            break
        g = grain_loader(st["grain"])
        seg = g[st["delta"]: st["delta"] + Le]
        if len(seg) < Le:
            seg = np.pad(seg, (0, Le - len(seg)))
        win = w_first if st["k"] == 0 else w
        end = min(len(out), p + Le)
        out[p:end] += (seg * win)[:end - p]
        if st["k"] > 0 and st["kind"] != "chrono":
            rho = float(np.clip(st["rho"], 0.0, 1.0))
            comp = 1.0 / np.sqrt(f_fall ** 2 + f_rise ** 2 + 2 * rho * f_fall * f_rise)
            e2 = min(len(out), p + O)
            gain[p:e2] *= comp[:e2 - p]
    return (out * gain)[:n_out]


def make_envelope(kind, n_tail, sr):
    """Gain curve for the NEW material only (index 0 = first sample after the
    source's end). Every curve starts at 1 and ends at exactly 0."""
    if n_tail <= 0:
        return np.zeros(0)
    if n_tail == 1:
        return np.zeros(1)
    T = (n_tail - 1) / float(sr)
    t = np.arange(n_tail) / float(sr)
    u = t / T if T > 0 else np.zeros(n_tail)
    if kind == "exp-decay":
        a = 3.0   # v1.7.2: was 5.0 (-43 dB over the tail; -11 dB after a quarter)
        env = (np.exp(-a * u) - math.exp(-a)) / (1.0 - math.exp(-a))
    elif kind == "sustain-drop":
        dl = float(np.clip(0.15 * T, 0.06, 0.6))
        dl = min(dl, T)
        env = np.ones(n_tail)
        ts = T - dl
        m = t > ts
        env[m] = np.cos(0.5 * np.pi * (t[m] - ts) / dl) ** 2
    elif kind == "tremolo-decay":
        a = 3.0
        base = (np.exp(-a * u) - math.exp(-a)) / (1.0 - math.exp(-a))
        rate, depth = 5.5, 0.6
        trem = 1.0 - depth * 0.5 * (1.0 - np.cos(2 * np.pi * rate * t))
        env = base * trem
    elif kind == "swell-fade":
        tp = float(np.clip(0.15 * T, 0.1, 0.6))
        tp = min(tp, 0.5 * T)
        peak = 1.4
        env = np.empty(n_tail)
        a = t <= tp
        env[a] = 1.0 + (peak - 1.0) * np.sin(0.5 * np.pi * t[a] / tp) ** 2
        b = ~a
        v = (t[b] - tp) / max(1e-9, T - tp)
        env[b] = peak * np.cos(0.5 * np.pi * np.clip(v, 0, 1)) ** 2
    else:
        raise ValueError("unknown envelope %r" % kind)
    env = np.nan_to_num(np.maximum(env, 0.0))
    env[-1] = 0.0
    return env


def _level_tail(raw, sr, xf, join_level, target_level, ramp_s=0.30,
                keep=0.25, max_boost=4.0, max_cut=8.0):
    """Slow automatic level control of the generated buffer (BEFORE the
    envelope). The target is join_level inside the crossfade, then moves to
    target_level over ramp_s (raised cosine), so the join stays continuous and
    the continuation settles at the requested level. Only `keep` of the
    corpus material's own level deviation is retained (0.25 = 75 % of the
    swings between grains removed); boost <= max_boost, cut <= max_cut,
    gain smoothed over ~100 ms in the log domain."""
    from scipy.ndimage import uniform_filter1d
    n = len(raw)
    w = max(1, _round_half_up(0.200 * sr))
    pw = uniform_filter1d(raw * raw, size=w, mode="nearest")
    lvl = np.sqrt(np.maximum(pw, 1e-14))
    tt = (np.arange(n) - xf) / float(sr)
    lj, lt = math.log(max(join_level, 1e-7)), math.log(max(target_level, 1e-7))
    u = np.clip(tt / max(ramp_s, 1e-3), 0.0, 1.0)
    tgt = lj + (lt - lj) * np.sin(0.5 * np.pi * u) ** 2
    # output level = target + keep * (corpus level - its median):
    # the target is met on average, a quarter of the corpus's own swings stay
    ll = np.log(lvl)
    med = float(np.median(ll[xf:] if n > xf else ll))
    lg = tgt + keep * (ll - med) - ll
    lg = np.clip(lg, -math.log(max_cut), math.log(max_boost))
    lg = uniform_filter1d(lg, size=max(1, _round_half_up(0.100 * sr)), mode="nearest")
    g = np.exp(lg)
    return raw * g, {"gain_db_min": float(20 * lg.min() / math.log(10)),
                     "gain_db_max": float(20 * lg.max() / math.log(10)),
                     "gain_db_median": float(20 * np.median(lg) / math.log(10))}


def _tail_limiter(tail, src_part, xf, a, b, c, ceiling=0.98, sr=44100):
    """Per-sample gain <= 1 applied to the TAIL only so the predicted join
    mixture and the tail stay under the ceiling. Min-filter + moving average
    (a standard look-ahead limiter shape) keeps it smooth and never above the
    requirement."""
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    req = np.ones(len(tail))
    with np.errstate(divide="ignore", invalid="ignore"):
        if xf > 0:
            s = np.abs(src_part * a * c)
            tb = np.abs(tail[:xf] * b * c)
            req[:xf] = np.where(tb > 1e-12, (ceiling - s) / tb, 1.0)
        t2 = np.abs(tail[xf:])
        req[xf:] = np.where(t2 > ceiling, ceiling / t2, 1.0)
    req = np.clip(np.nan_to_num(req, nan=1.0), 0.0, 1.0)
    if req.min() >= 1.0:
        return tail, 0.0
    w = max(1, _round_half_up(0.002 * sr))
    g = minimum_filter1d(req, size=4 * w + 1, mode="nearest")
    g = uniform_filter1d(g, size=2 * w + 1, mode="nearest")
    g = np.minimum(g, req)
    return tail * g, float(-20 * math.log10(max(g.min(), 1e-6)))


def _join_curves(xf, rho):
    """Crossfade laws used by BOTH Python (prediction) and Praat (actual
    join): a = cos^2, b = sin^2 over sample centres, with the same
    correlation-adaptive correction as internal splices."""
    if xf <= 0:
        return np.zeros(0), np.zeros(0), np.zeros(0)
    m = (np.arange(xf) + 0.5) / xf
    a = np.cos(0.5 * np.pi * m) ** 2
    b = np.sin(0.5 * np.pi * m) ** 2
    c = 1.0 / np.sqrt(a * a + b * b + 2 * rho * a * b)
    return a, b, c


def _write_cont_textgrid(path, steps, info, sr_c, pre_c, sr, base, total, sections):
    """Two tiers in FINAL-output coordinates: 'sections' (source / join /
    tail) and 'grains' (one interval per synthesis step, labelled with its
    transition type: S start, C chronological, J graph jump, F fallback).
    Steps own disjoint [k*H, (k+1)*H) slots, so the tier never overlaps."""
    H = info["geometry"]["H"]
    code = {"start": "S", "chrono": "C", "graph": "J", "fallback": "F"}

    def tier(intervals):
        out = []
        cur = 0.0
        for (a, b, lab) in intervals:
            a = max(a, cur)
            b = min(b, total)
            if b <= a + 1e-9:
                continue
            if a > cur + 1e-9:
                out.append((cur, a, ""))
            out.append((a, b, lab))
            cur = b
        if cur < total - 1e-9:
            out.append((cur, total, ""))
        return out

    ivs = []
    for st in steps:
        a = base + (st["k"] * H - pre_c) / float(sr_c)
        b = base + ((st["k"] + 1) * H - pre_c) / float(sr_c)
        lab = "%s %s@%.3f" % (code.get(st["kind"], "?"), st.get("file", ""), st.get("corpus_start_s", 0.0))
        ivs.append((max(a, max(base, 0.0)), b, lab.replace('"', "'")))
    tiers = [("sections", tier(sections)), ("grains", tier(ivs))]
    L = ['File type = "ooTextFile"', 'Object class = "TextGrid"', "",
         "xmin = 0", "xmax = %.9f" % total, "tiers? <exists>", "size = %d" % len(tiers), "item []:"]
    for n, (name, iv) in enumerate(tiers, 1):
        L += ["    item [%d]:" % n, '        class = "IntervalTier"', '        name = "%s"' % name,
              "        xmin = 0", "        xmax = %.9f" % total, "        intervals: size = %d" % len(iv)]
        for m, (a, b, lab) in enumerate(iv, 1):
            L += ["        intervals [%d]:" % m, "            xmin = %.9f" % a,
                  "            xmax = %.9f" % b, '            text = "%s"' % lab]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


# ---------------- the subcommand ----------------

def _fail(msg, code=6):
    sys.stderr.write("ERROR: %s\n" % msg)
    sys.exit(code)


def continuation_tail(args):
    import soundfile as sf
    index, _ = _load_corpus_index(args.index, mmap=True)
    if index["codec"] != args.codec and args.codec != "auto":
        sys.stderr.write("Warning: corpus codec '%s' != requested '%s'; using corpus codec.\n"
                         % (index["codec"], args.codec))
    codec = make_codec(index["codec"])
    try:
        arrays, ginfo, built_now, why = load_or_build_graph(args.index, index, codec,
                                                            rebuild=bool(args.rebuild_graph))
    except Exception as e:
        _fail("could not build the continuation graph: %s" % e)
    sr_c = int(index["sample_rate"])
    geo = ginfo["geometry"]
    H, O, Le = geo["H"], geo["O"], geo["Le"]

    # ---- source (native rate, never resampled for the join) ----
    try:
        info_src = sf.info(args.input)
    except Exception as e:
        _fail("cannot read source WAV: %s" % e, 3)
    if info_src.channels != 1:
        _fail("source has %d channels; Continuation Tail v1 accepts mono only "
              "(convert the Sound to mono first)" % info_src.channels, 5)
    x, sr = sf.read(args.input, dtype="float64", always_2d=True)
    x = np.nan_to_num(x[:, 0])
    n = len(x)
    if n < 0.05 * sr:
        _fail("source is shorter than 50 ms", 3)
    act = analyse_source_activity(x, sr, trim=bool(args.trim_silence))
    if act["policy"] == "silent source":
        _fail("source is silent (95th-percentile level below -80 dBFS)", 3)
    n_eff = int(act["join_end"])
    ae = int(act["analysis_end"])
    # The terminal STATE is read from the last STRONG sound (>= 15 dB above
    # the noise floor), not from a faint release whose level-invariant
    # spectrum is mostly room noise; the level match still uses the true
    # end of the sound (ae) so loudness is continuous at the join.
    te = int(act.get("strong_end", ae))
    if te < _round_half_up(0.05 * sr):
        te = ae

    if args.duration_mode == "percent":
        if args.tail_percent <= 0:
            _fail("tail percentage must be > 0", 4)
        n_tail = _round_half_up(n_eff * args.tail_percent / 100.0)
    else:
        if args.tail_seconds <= 0:
            _fail("tail duration must be > 0 s", 4)
        n_tail = _round_half_up(args.tail_seconds * sr)
    if n_tail < 1:
        _fail("requested tail is shorter than one sample", 4)
    if n_tail > MAX_TAIL_SECONDS * sr:
        _fail("requested tail (%.1f s) exceeds the %.0f s limit" % (n_tail / sr, MAX_TAIL_SECONDS), 4)
    xf_req = _round_half_up(args.xfade_ms / 1000.0 * sr)
    xf = int(max(1, min(xf_req, n_eff // 2, n_tail)))
    tail_seconds = n_tail / float(sr)

    # ---- terminal analysis on a corpus-rate copy ----
    xc = resample_to(x.astype(np.float32), sr, sr_c).astype(np.float64)
    ae_c = int(min(len(xc), _round_half_up(te * sr_c / float(sr))))
    je_c = int(min(len(xc), _round_half_up(n_eff * sr_c / float(sr))))
    try:
        term = analyse_terminal(xc, sr_c, ae_c, codec, arrays, ginfo, index["codebook_size"])
    except Exception as e:
        _fail("source-ending analysis failed: %s" % e, 3)
    ident = (0.6 * np.linalg.norm(arrays["glob_desc"] - term["glob"]["desc"][None, :], axis=1)
             + 0.4 * _cat_distance(args.index + "_feats.npy", term["cat_feature"])).astype(np.float64)

    # ---- plan + render on the corpus grid ----
    pre_c = _round_half_up(0.010 * sr_c)
    post_c = _round_half_up(0.050 * sr_c)
    xfc = _round_half_up(xf * sr_c / float(sr))
    need_c = int(math.ceil((xf + n_tail) * sr_c / float(sr))) + pre_c + post_c
    n_steps = int(math.ceil(need_c / float(H))) + 1
    cache = {}

    def loader(j):
        if j not in cache:
            cache[j] = np.load(_resolve_grain_path(args.index, index["grains"][j]["grain_audio"])).astype(np.float64)
        return cache[j]

    lr = int(min(xfc, Le - pre_c, je_c))
    src_region = xc[je_c - lr: je_c] if lr >= 8 else None

    def step_time(k):
        return (k * H + 0.5 * Le - pre_c - xfc) / float(sr_c)

    mode = args.continuation_mode
    strength = float(np.clip(args.continuation_strength / 100.0, 0.0, 1.0))
    rng = np.random.default_rng(int(args.seed))
    steps, plan_info = plan_sequence(arrays, ginfo, term, ident, mode, strength, n_steps,
                                     step_time, tail_seconds, loader, src_region, rng,
                                     src_offset0=pre_c)
    raw_c = render_sequence(steps, ginfo, loader, need_c)

    # ---- back to the source's rate, exact length ----
    raw = resample_to(raw_c.astype(np.float32), sr_c, sr).astype(np.float64)
    pre_n = _round_half_up(pre_c * sr / float(sr_c))
    total_n = xf + n_tail
    raw = raw[pre_n:pre_n + total_n]
    if len(raw) < total_n:
        raw = np.pad(raw, (0, total_n - len(raw)))
    raw = np.nan_to_num(raw)

    # ---- level: continuous at the join, then the requested tail level ----
    # ending level = the source's true end (last 100 ms before ae);
    # phrase level = median RMS of the phrase's ACTIVE 10 ms frames
    # (>= the activity threshold), i.e. how loud the phrase actually is.
    ref_a = max(0, ae - _round_half_up(0.100 * sr))
    end_rms = float(np.sqrt(np.mean(x[ref_a:ae] ** 2))) if ae > ref_a else 0.0
    fn = max(1, _round_half_up(0.010 * sr))
    nfr = n_eff // fn
    fr_rms = np.sqrt(np.mean(x[:nfr * fn].reshape(nfr, fn) ** 2, axis=1)) if nfr else np.zeros(1)
    thr = 10 ** (act.get("thr_on_db", -60.0) / 20.0)
    act_fr = fr_rms[fr_rms >= thr]
    phrase_rms = float(np.median(act_fr)) if act_fr.size else end_rms
    if end_rms <= 1e-7:
        end_rms = phrase_rms
    tail_target = phrase_rms if args.tail_level == "phrase" else end_rms
    raw, lvl_info = _level_tail(raw, sr, xf, end_rms, tail_target)
    g0 = 10 ** (lvl_info["gain_db_median"] / 20.0)

    # ---- envelope (new material only; crossfade region untouched) ----
    env = np.ones(total_n)
    env[xf:] = make_envelope(args.envelope, n_tail, sr)
    tail = raw * env

    # ---- join law + local level control ----
    s_join = x[n_eff - xf:n_eff]
    a0 = s_join - s_join.mean()
    b0 = tail[:xf] - tail[:xf].mean()
    den = float(np.linalg.norm(a0) * np.linalg.norm(b0))
    rho_join = float(np.clip(np.dot(a0, b0) / den, 0.0, 1.0)) if den > 1e-12 else 0.0
    ja, jb, jc = _join_curves(xf, rho_join)
    # Loudness normalisation (v1.7.4): match the tail's sustained body to the
    # phrase's active loudness here, in SOURCE units, and never let the tail
    # peak above the source's own peak. Praat then applies ONE common gain
    # (source peak -> -1 dBFS) to both, so the source is never pushed down to
    # make room for a peakier tail (seen in v1.7.3: source -6.9 dB).
    src_peak = float(np.abs(x[:n_eff]).max()) if n_eff > 0 else 0.0
    ceiling = 0.98
    norm_gain_db = 0.0
    if args.normalize == "loudness" and src_peak > 1e-6:
        envb = env[xf:] >= 0.5
        bodyp = tail[xf:][envb] if envb.sum() >= _round_half_up(0.05 * sr) else tail[xf:xf + _round_half_up(0.25 * sr)]
        brms = float(np.sqrt(np.mean(bodyp ** 2))) if bodyp.size else 0.0
        tpk = float(np.abs(tail).max())
        if brms > 1e-9 and tpk > 1e-9:
            gl = phrase_rms / brms
            gl = min(gl, 1.41 * src_peak / tpk, 8.0)   # <= +3 dB left for the limiter
            tail = tail * gl
            norm_gain_db = 20 * math.log10(gl)
        ceiling = min(0.98, src_peak)
    tail, lim_db = _tail_limiter(tail, s_join, xf, ja, jb, jc, ceiling=ceiling, sr=sr)
    tail = np.nan_to_num(tail).astype(np.float32)
    mix = (s_join * ja + tail[:xf] * jb) * jc
    predicted_peak = float(max(np.abs(mix).max() if xf else 0.0, np.abs(tail[xf:]).max() if n_tail else 0.0))

    sf.write(args.output, tail, sr, subtype="FLOAT")
    # loudness of the tail's sustained body (envelope >= 0.5), for the
    # optional loudness normalisation done in Praat
    body = tail[xf:][env[xf:] >= 0.5] if n_tail > 0 else np.zeros(0)
    if body.size < _round_half_up(0.05 * sr):
        body = tail[xf:xf + max(1, _round_half_up(0.25 * sr))]
    tail_body_rms = float(np.sqrt(np.mean(body.astype(np.float64) ** 2))) if body.size else 0.0

    total_out = n_eff + n_tail if args.output_mode == "original+tail" else n_tail
    for st in steps:
        gm = index["grains"][st["grain"]]
        st["grain_id"] = gm["id"]
        st["file"] = gm["source_file"]
        st["corpus_start_s"] = float(gm["start_s"])

    if args.result:
        with open(args.result, "w", encoding="utf-8", newline="\n") as f:
            f.write("ccc_continuation_result 1\n")
            f.write("status ok\n")
            f.write("sample_rate %d\n" % sr)
            f.write("source_samples %d\n" % n)
            f.write("join_end_sample %d\n" % n_eff)
            f.write("analysis_end_sample %d\n" % ae)
            f.write("trimmed_samples %d\n" % (n - n_eff))
            f.write("xfade_samples %d\n" % xf)
            f.write("new_tail_samples %d\n" % n_tail)
            f.write("buffer_samples %d\n" % total_n)
            f.write("output_samples %d\n" % total_out)
            f.write("join_rho %.9f\n" % rho_join)
            f.write("predicted_peak %.6f\n" % predicted_peak)
            f.write("source_active_rms %.9f\n" % phrase_rms)
            f.write("tail_body_rms %.9f\n" % tail_body_rms)
            f.write("source_peak %.9f\n" % src_peak)
            f.write("normalize_mode %s\n" % args.normalize)
            f.write("graph_built_now %d\n" % (1 if built_now else 0))

    counts = {}
    for st in steps:
        counts[st["kind"]] = counts.get(st["kind"], 0) + 1
    if args.metadata:
        with open(args.metadata, "w") as f:
            json.dump({
                "mode": "continuation-tail",
                "codec": index["codec"],
                "corpus_sample_rate": sr_c,
                "source_sample_rate": sr,
                "source_samples": n,
                "source_duration_s": n / float(sr),
                "analysis_end_s": ae / float(sr),
                "terminal_state_end_s": te / float(sr),
                "effective_duration_s": n_eff / float(sr),
                "trailing_silence": {k: act[k] for k in act if k not in ("n",)},
                "requested_tail_s": tail_seconds,
                "duration_mode": args.duration_mode,
                "tail_percent": args.tail_percent if args.duration_mode == "percent" else None,
                "output_mode": args.output_mode,
                "final_output_samples": total_out,
                "final_output_duration_s": total_out / float(sr),
                "corpus_index_json_sha256": ginfo.get("index_json_sha256"),
                "graph_schema": ginfo.get("graph_schema"),
                "graph_built_now": built_now,
                "graph_status": why,
                "graph_descriptor": ginfo.get("descriptor", {}).get("mode"),
                "graph_retrieval": ginfo.get("retrieval"),
                "continuation_mode": mode,
                "continuation_strength": args.continuation_strength,
                "envelope": args.envelope,
                "xfade_ms_requested": args.xfade_ms,
                "xfade_samples": xf,
                "xfade_clamped": xf != xf_req,
                "join_rho": rho_join,
                "tail_gain_db": 20 * math.log10(g0),
                "tail_level_mode": args.tail_level,
                "phrase_level_db": 20 * math.log10(max(phrase_rms, 1e-10)),
                "ending_level_db": 20 * math.log10(max(end_rms, 1e-10)),
                "levelling": lvl_info,
                "normalize": args.normalize,
                "loudness_norm_gain_db": norm_gain_db,
                "limiter_max_reduction_db": lim_db,
                "predicted_peak": predicted_peak,
                "seed": int(args.seed),
                "terminal_window_s": term["window_samples"] / float(sr_c),
                "terminal_f0_hz": term["boundary"]["f0"],
                "terminal_f0_conf": term["boundary"]["conf"],
                "plan": {"ident_limit": plan_info["ident_limit"], "trajectory": plan_info["trajectory"],
                         "transition_counts": counts},
                "note": ("transition types: start = initial grain matched to the source ending; "
                         "chrono = genuine next grain of the same corpus recording; graph = "
                         "boundary-matched jump along a cached transition edge; fallback = "
                         "direct search when the graph offered nothing. Token-histogram/bigram "
                         "similarity is whole-grain and unordered - it is NOT ordered token prediction."),
                "geometry": geo,
                "steps": [{
                    "k": st["k"], "grain_id": st["grain_id"], "corpus_file": st["file"],
                    "corpus_start_s": st["corpus_start_s"], "read_offset_samples": st["delta"],
                    "placement_s": (st["k"] * H - pre_c - xfc) / float(sr_c),
                    "transition": st["kind"], "cost": st["cost"],
                    "overlap_correlation": round(st["rho"], 4), "fallback": st["fallback"],
                } for st in steps],
            }, f, indent=1)

    if args.textgrid:
        if args.output_mode == "original+tail":
            base = (n_eff - xf) / float(sr)
            total = (n_eff + n_tail) / float(sr)
            sections = [(0.0, base, "source"), (base, n_eff / float(sr), "join"),
                        (n_eff / float(sr), total, "tail")]
        else:
            base = -xf / float(sr)
            total = n_tail / float(sr)
            sections = [(0.0, total, "tail")]
        _write_cont_textgrid(args.textgrid, steps, ginfo, sr_c, pre_c, sr, base, total, sections)

    sys.stdout.write("Continuation tail done: %s, %d steps (%s), %.3f s new material, graph %s\n"
                     % (mode, len(steps), ", ".join("%s %d" % kv for kv in sorted(counts.items())),
                        tail_seconds, "built" if built_now else "cached"))


def continuation_graph_cmd(args):
    """Build (or validate) the continuation graph without rendering - for
    batch preparation and testing."""
    index, _ = _load_corpus_index(args.index, mmap=True)
    codec = make_codec(index["codec"])
    arrays, info, built, why = load_or_build_graph(args.index, index, codec, rebuild=bool(args.rebuild))
    sys.stdout.write(json.dumps({"built_now": built, "status": why,
                                 "descriptor": info["descriptor"]["mode"],
                                 "retrieval": info["retrieval"],
                                 "n_grains": info["n_grains"],
                                 "n_chrono_links": info["n_chrono_links"],
                                 "n_usable": info["n_usable"]}) + "\n")


# ============================================================
# polyphonic-layers subcommand (v1.8.0)
#   "Corpus Polyphonic Layers": the WHOLE source phrase is analysed over time
#   and gives rise to 1-3 additional, simultaneously sounding voices built
#   from real corpus grains along the cached Corpus Transition Graph (graph
#   schema 3, reused unchanged). Every voice is exactly as long as the source,
#   sample-aligned from sample 0, at the source's own sampling rate.
#
#   Relationship modes (different TARGETS, WEIGHTS and PRESENCE rules - not
#   labels on one algorithm):
#     parallel      - voices follow the source's behaviour over time: activity
#                     (articulation), dynamic contour, brightness movement,
#                     pauses; grain changes are encouraged at source onsets.
#     complementary - voices answer the source: more internal movement while
#                     the source sustains, stable material while it is dense,
#                     activity in its pauses, moderate spectral contrast, and
#                     activity distributed across the ensemble.
#     independent   - each voice follows its own seeded behavioural walk and
#                     phrasing; attachment to the source's identity decays.
#   Per step and voice:  cost = transition + source relationship + voice
#   trajectory + inter-voice interaction + repetition (+ jump cost).
#   Voices are planned sequentially (v2 conditioned on v1, v3 on v1+v2), then
#   an optional refinement sweep re-plans each voice against ALL others and
#   keeps the new plan only if its mean cost is lower (--refine 0 keeps
#   voice 1 identical whatever the voice count).
#
#   Division of labour with Praat (as in continuation-tail): Python writes
#   each generated voice as 32-bit float mono WAV of exactly N samples and a
#   key/value result (pan gains, mix gain). Praat builds the stereo mix from
#   the UNTOUCHED in-memory source plus the imported voices. Optional DAW
#   stems are written here as 32-bit float from a lossless 32-bit PCM export
#   of the source, using exactly the gains Praat applies.
# ============================================================

from collections import OrderedDict

POLY_RELATIONSHIPS = ("parallel", "complementary", "independent")
POLY_MAX_VOICES = 3
POLY_AUTO_PANS = {1: (45.0,), 2: (-60.0, 60.0), 3: (-70.0, 70.0, 0.0)}
POLY_GRAIN_CACHE = 1536       # grains held in memory (float32) - bounded
POLY_SEED_SALT_SELECT = 0x504F4C59   # "POLY"
POLY_SEED_SALT_WALK = 0x57414C4B     # "WALK"
_LN2 = math.log(2.0)


class _GrainCache:
    """Bounded LRU cache of grain audio (float32)."""

    def __init__(self, index_prefix, grains, cap=POLY_GRAIN_CACHE):
        self.p, self.g, self.cap = index_prefix, grains, int(cap)
        self.d = OrderedDict()
        self.loads = 0

    def __call__(self, j):
        j = int(j)
        a = self.d.get(j)
        if a is not None:
            self.d.move_to_end(j)
            return a
        a = np.load(_resolve_grain_path(self.p, self.g[j]["grain_audio"])).astype(np.float32)
        self.loads += 1
        self.d[j] = a
        if len(self.d) > self.cap:
            self.d.popitem(last=False)
        return a


def _gauss_smooth(v, sigma):
    v = np.asarray(v, dtype=np.float64)
    if sigma < 0.3 or v.size < 3:
        return v.copy()
    r = int(math.ceil(3 * sigma))
    t = np.arange(-r, r + 1)
    w = np.exp(-0.5 * (t / sigma) ** 2)
    w /= w.sum()
    return np.convolve(np.pad(v, r, mode="edge"), w, mode="valid")


def _masked_smooth(v, m, sigma):
    """Smooth v using only the frames where m is true; frames with no valid
    neighbours take the nearest valid value (rests never pollute features)."""
    v = np.asarray(v, dtype=np.float64)
    m = np.asarray(m, dtype=np.float64)
    if m.sum() == 0:
        return v.copy()
    num = _gauss_smooth(v * m, sigma)
    den = _gauss_smooth(m, sigma)
    out = np.where(den > 1e-3, num / np.maximum(den, 1e-12), np.nan)
    good = np.flatnonzero(~np.isnan(out))
    bad = np.flatnonzero(np.isnan(out))
    if bad.size:
        near = good[np.clip(np.searchsorted(good, bad), 0, good.size - 1)]
        near2 = good[np.clip(np.searchsorted(good, bad) - 1, 0, good.size - 1)]
        pick = np.where(np.abs(near - bad) <= np.abs(near2 - bad), near, near2)
        out[bad] = out[pick]
    return out


def _cdf(ref_sorted, v):
    if ref_sorted.size == 0:
        return np.zeros(len(v))
    return np.searchsorted(ref_sorted, v, side="right") / float(ref_sorted.size)


def _hysteresis(score, on, off, min_on, min_off):
    """Boolean state: switches on when score >= on, off when score < off, and
    enforces minimum run lengths (in steps) by merging short runs."""
    st = np.zeros(len(score), dtype=bool)
    cur = False
    for i, s in enumerate(score):
        if not cur and s >= on:
            cur = True
        elif cur and s < off:
            cur = False
        st[i] = cur
    return _min_runs(st, min_on, min_off)


def _min_runs(st, min_true, min_false):
    st = st.copy()
    for target, mn in ((False, min_false), (True, min_true)):
        i, n = 0, len(st)
        while i < n:
            j = i
            while j < n and st[j] == st[i]:
                j += 1
            if st[i] == target and (j - i) < mn and i > 0 and j < n:
                st[i:j] = not target
            i = j
    return st


def corpus_behaviour(arrays):
    """Per-grain behaviour descriptors derived ONLY from the cached graph
    arrays (no new analysis pass, no new cache file): internal activity
    (head vs tail descriptor change + level change + change into the next
    chronological grain), mapped to its percentile among usable grains;
    level relative to its own recording (dB); brightness; tonality."""
    hd, td, gd = arrays["head_desc"], arrays["tail_desc"], arrays["glob_desc"]
    raw = (np.linalg.norm(hd - td, axis=1)
           + 0.5 * np.abs(arrays["lnrms_head"] - arrays["lnrms_tail"]) / math.log(4.0))
    succ = arrays["succ"]
    nxt = np.zeros(len(raw))
    has = succ >= 0
    nxt[has] = np.linalg.norm(gd[has] - gd[succ[has]], axis=1)
    raw = raw + 0.5 * nxt
    fg = arrays["usable"].astype(bool) & ~arrays["background"].astype(bool)
    if fg.sum() < 2:
        fg = arrays["usable"].astype(bool)
    ref = np.sort(raw[fg])
    return {"act_raw": raw, "act": _cdf(ref, raw), "act_ref": ref,
            "rel_db": 20.0 / math.log(10.0) * arrays["rel_level"].astype(np.float64),
            "lncent": arrays["lncent_glob"].astype(np.float64),
            "conf": np.clip(arrays["conf_glob"].astype(np.float64), 0, 1),
            "foreground": fg}


def analyze_source_trajectory(x, sr, codec, arrays, info, beh):
    """Time-varying analysis of the WHOLE source on the synthesis step grid
    (step k covers corpus-rate samples [k*H, k*H + Le)). Per step: level,
    relative loudness, brightness, band shape + codec latent descriptor,
    spectral change, F0 + periodicity, flatness, onset activity, articulation
    density, presence. Then temporal context: fast (~0.15 s) and slow
    (~0.5 s) masked smoothing, direction of change, phrase-level identity,
    and a hysteresis segmentation into rest / sustained / active."""
    sr_c = int(info["sample_rate"])
    geo = info["geometry"]
    H, O, Le, G = geo["H"], geo["O"], geo["Le"], geo["G"]
    xc = resample_to(x.astype(np.float32), sr, sr_c).astype(np.float64)
    Nc = len(xc)
    n_src = len(x)
    K = int(math.ceil(n_src * sr_c / float(sr) / H)) + 1
    use_lat = info["descriptor"]["mode"] == "latent+spectral"
    z = None
    if use_lat:
        z = codec.latent_from_tokens(codec.encode(xc.astype(np.float32)))
        pm, pc = arrays["pca_mean"], arrays["pca_comp"]
    pad = np.concatenate([xc, np.zeros(G + Le + H)])

    def region(a, b):
        seg = pad[a:b]
        u, lr, lc, fl = _region_spectral(seg, sr_c)
        if use_lat:
            lp = (_latent_region_mean(z, Nc, a, b) - pm).dot(pc.T)
            d = np.concatenate([SPEC_W * u, LAT_W * _unit(lp)])
        else:
            d = u
        return d.astype(np.float32), lr, lc, fl

    D = arrays["glob_desc"].shape[1]
    d_h = np.zeros((K, D), np.float32)
    d_t = np.zeros((K, D), np.float32)
    d_g = np.zeros((K, D), np.float32)
    lr_h, lr_t, lr_g = np.zeros(K), np.zeros(K), np.zeros(K)
    lc, fl, f0, cf = np.zeros(K), np.zeros(K), np.zeros(K), np.zeros(K)
    for k in range(K):
        a = k * H
        d_h[k], lr_h[k], _, _ = region(a, a + O)
        d_t[k], lr_t[k], _, _ = region(a + H, a + Le)
        d_g[k], lr_g[k], lc[k], fl[k] = region(a, a + G)
        f0[k], cf[k] = _yin(pad[a:a + G], sr_c)
    nxt = np.zeros(K)
    nxt[:-1] = np.linalg.norm(d_g[1:] - d_g[:-1], axis=1)
    act_raw = np.linalg.norm(d_h - d_t, axis=1) + 0.5 * np.abs(lr_h - lr_t) / math.log(4.0) + 0.5 * nxt
    flux = nxt.copy()

    # ---- presence: 10 ms frames, adaptive hysteresis thresholds (same
    # analysis as the continuation's activity detector, trim disabled) ----
    act_info = analyse_source_activity(x, sr, trim=False)
    fn = max(1, _round_half_up(0.010 * sr))
    nf = n_src // fn
    fr = x[:nf * fn].reshape(nf, fn) if nf else np.zeros((1, 1))
    fdb = 20 * np.log10(np.sqrt(np.mean(fr * fr, axis=1)) + 1e-10)
    if nf >= 3:
        fdb = np.median(np.stack([fdb, np.r_[fdb[0], fdb[:-1]], np.r_[fdb[1:], fdb[-1]]]), axis=0)
    if "thr_on_db" in act_info:
        on, off = act_info["thr_on_db"], act_info["thr_off_db"]
        fa = np.zeros(nf, bool)
        cur = False
        for i, v in enumerate(fdb):
            if not cur and v >= on:
                cur = True
            elif cur and v < off:
                cur = False
            fa[i] = cur
    else:
        fa = np.full(nf, act_info.get("policy") != "silent source")
    t_step = np.arange(K) * H / float(sr_c)            # slot start (s)
    slot = H / float(sr_c)
    present = np.zeros(K, bool)
    for k in range(K):
        a = int(t_step[k] * sr / fn)
        b = int(math.ceil((t_step[k] + slot) * sr / fn))
        if a < nf:
            present[k] = fa[a:min(b, nf)].mean() >= 0.3 if b > a else False
    act_fr = np.sqrt(np.mean(fr * fr, axis=1))
    thr_on_lin = 10 ** (act_info.get("thr_on_db", -200.0) / 20.0)
    a_fr = act_fr[act_fr >= thr_on_lin]
    phrase_rms = float(np.median(a_fr)) if a_fr.size else float(np.sqrt(np.mean(x ** 2)))

    # ---- onsets: articulation density and nearness ----
    ons = np.asarray(detect_onsets(x.astype(np.float32), sr), dtype=np.float64) / sr
    if ons.size and ons[0] == 0.0 and not (nf and fa[0]):
        ons = ons[1:]
    t_c = t_step + 0.5 * slot
    if ons.size:
        dist = np.abs(t_c[:, None] - ons[None, :])
        density = np.exp(-0.5 * (dist / 0.30) ** 2).sum(axis=1) / (0.30 * math.sqrt(2 * math.pi))
        t_join = t_step + 0.5 * O / float(sr_c)
        onset_near = np.exp(-np.abs(t_join[:, None] - ons[None, :]).min(axis=1) / 0.05)
    else:
        density = np.zeros(K)
        onset_near = np.zeros(K)

    m = present.astype(float)
    sig_f = 0.15 / slot
    sig_s = 0.50 / slot
    act_cdf = _cdf(beh["act_ref"], act_raw)
    A_fast = 0.6 * _masked_smooth(act_cdf, m, sig_f) + 0.4 * np.clip(density / 5.0, 0, 1)
    A_slow = 0.6 * _masked_smooth(act_cdf, m, sig_s) + 0.4 * np.clip(_gauss_smooth(density, sig_s) / 5.0, 0, 1)
    A_fast = np.where(present, A_fast, 0.0)
    db = 20.0 / math.log(10.0) * lr_g
    p95 = float(np.percentile(db[present], 95)) if present.any() else float(db.max())
    rel_db = np.clip(db - p95, -60.0, 6.0)
    rel_fast = np.where(present, _gauss_smooth(rel_db, sig_f), -60.0)
    rel_slow = _gauss_smooth(np.where(present, rel_db, -60.0), sig_s)
    lc_fast = _masked_smooth(lc, m, sig_f)
    lc_slow = _masked_smooth(lc, m, sig_s)
    cf_fast = _masked_smooth(np.clip(cf, 0, 1), m, sig_f)
    cf_slow = _masked_smooth(np.clip(cf, 0, 1), m, sig_s)
    pres_slow = _gauss_smooth(m, sig_s)
    d_fast = np.zeros_like(d_g)
    for k in range(K):
        lo, hi = max(0, k - 1), min(K, k + 2)
        w = m[lo:hi]
        d_fast[k] = _unit((d_g[lo:hi] * w[:, None]).sum(axis=0)) if w.sum() > 0 else d_g[k]
    phrase_desc = _unit(d_g[present].mean(axis=0)) if present.any() else _unit(d_g.mean(axis=0))
    # direction of change (per second) of the slow loudness / brightness
    slope_db = np.gradient(rel_slow) / slot
    slope_lc = np.gradient(lc_slow) / slot
    # segmentation (descriptive; also used by the complementary planner)
    seg_active = _hysteresis(A_fast, 0.55, 0.45, int(math.ceil(0.25 / slot)), int(math.ceil(0.25 / slot)))
    seg = np.where(~present, "rest", np.where(seg_active, "active", "sustained"))
    return {
        "K": K, "slot_s": slot, "t_step": t_step, "present": present, "pres_slow": pres_slow,
        "desc": d_g, "desc_fast": d_fast, "phrase_desc": phrase_desc,
        "lnrms": lr_g, "rel_db": rel_db, "rel_fast": rel_fast, "rel_slow": rel_slow,
        "lncent": lc, "lc_fast": lc_fast, "lc_slow": lc_slow,
        "lc_median": float(np.median(lc[present])) if present.any() else float(np.median(lc)),
        "conf": cf, "cf_fast": cf_fast, "cf_slow": cf_slow, "f0": f0, "flat": fl,
        "flux": flux, "act_raw": act_raw, "act_cdf": act_cdf, "A_fast": A_fast, "A_slow": A_slow,
        "density": density, "onset_near": onset_near, "onsets_s": ons,
        "slope_db": slope_db, "slope_lc": slope_lc, "segment": seg,
        "phrase_rms": phrase_rms, "activity_info": act_info, "n_src": n_src,
    }


def find_source_copy_grains(xc, tr, arrays, info, cache, thr=0.95, per_frame=6):
    """Corpus grains that ARE the source phrase (the source recording is part
    of the corpus): descriptor kNN per present source step, then verified by
    normalised waveform correlation over +-1 hop. Such grains get a strong
    penalty in every voice, so no voice simply replays (or delays) the
    phrase it accompanies. Returns a boolean mask over grains."""
    geo = info["geometry"]
    H, G = geo["H"], geo["G"]
    N = len(arrays["glob_desc"])
    is_copy = np.zeros(N, bool)
    ks = np.flatnonzero(tr["present"])
    if ks.size == 0:
        return is_copy
    fg = arrays["usable"].astype(bool)
    base = np.flatnonzero(fg)
    m = int(min(per_frame, base.size))
    nn, _, _ = knn_search(tr["desc"][ks], arrays["glob_desc"][base], m)
    pad = np.concatenate([np.zeros(H), xc, np.zeros(G + 2 * H)])
    checked = set()
    for r, k in enumerate(ks):
        ref = pad[k * H: k * H + G + 2 * H]          # source around step k (+-1 hop)
        if float(np.dot(ref, ref)) < 1e-10:
            continue
        for j in base[nn[r]]:
            if is_copy[j] or (j, k) in checked:
                continue
            checked.add((j, k))
            g = cache(j).astype(np.float64)[:G]
            gn = float(np.linalg.norm(g))
            if gn < 1e-9:
                continue
            L = 1 << int(math.ceil(math.log2(len(ref) + len(g))))
            cc = np.fft.irfft(np.fft.rfft(ref, L) * np.conj(np.fft.rfft(g, L)), L)[:len(ref) - len(g) + 1]
            e = np.convolve(ref * ref, np.ones(len(g)), mode="valid")
            rho = cc / (gn * np.sqrt(np.maximum(e, 1e-12)))
            if float(np.max(rho)) >= thr:
                is_copy[j] = True
    return is_copy


def _poly_params(mode, s, D):
    """Mode-dependent weights. s = relationship strength, D = diversity."""
    rel = 0.25 + 0.75 * s
    if mode == "parallel":
        P = dict(w_tr=1.2, wp=1.0, w_act=1.2, w_bri=0.8, w_loud=0.6, w_ton=0.8,
                 w_sim=0.6 + 0.8 * s, w_close=0.0, w_traj=0.5, jump0=0.5 + 0.5 * s,
                 topk=1 + _round_half_up(3 * (1 - s)), temp=0.03 + 0.15 * (1 - s), w_int_act=0.2)
    elif mode == "complementary":
        P = dict(w_tr=1.2, wp=0.6, w_act=1.2, w_bri=0.6, w_loud=0.6, w_ton=0.4,
                 w_sim=0.15 + 0.25 * s, w_close=0.4 * s, w_traj=0.7, jump0=0.6 + 0.4 * s,
                 topk=2 + _round_half_up(4 * (1 - s)), temp=0.05 + 0.20 * (1 - s), w_int_act=0.8)
    else:
        P = dict(w_tr=1.4, wp=0.6, w_act=0.8, w_bri=0.8, w_loud=0.3, w_ton=0.5,
                 w_sim=0.2 + 0.8 * s, w_close=0.0, w_traj=0.9, jump0=0.5,
                 topk=3 + _round_half_up(6 * (1 - s)), temp=0.10 + 0.25 * (1 - s), w_int_act=0.5)
    for k in ("w_act", "w_bri", "w_loud", "w_ton"):
        P[k] *= rel
    P["dwell_pen"] = 0.4
    P["s"], P["D"], P["mode"] = s, D, mode
    return P


def _voice_offset(v, D, scale):
    """Brightness offset (ln Hz) per voice slot: 0, +, - (voice 1 unshifted,
    so it does not depend on how many voices exist)."""
    return (0.0, +1.0, -1.0)[v] * scale * D * _LN2


def _poly_voice_targets(mode, v, tr, s, D, rng_walk, others_act):
    """Per-step targets for voice v (0-based). others_act: list of arrays
    (activity * presence) of the voices this one is conditioned on."""
    K = tr["K"]
    slot = tr["slot_s"]
    sig_s = 0.5 / slot
    T = K * slot
    present = tr["present"]
    out = {"jump_factor": np.ones(K), "contour_db": np.zeros(K), "ref_desc": None,
           "w_sim_t": np.ones(K), "w_close_t": np.zeros(K)}
    if mode == "parallel":
        bridge = _round_half_up(0.6 * (1 - s) / slot)
        pres = _min_runs(present, max(1, _round_half_up(0.2 / slot)), bridge + 1) if bridge > 0 else present.copy()
        # gaps longer than the bridge are kept: the voice follows the pauses
        out["presence"] = pres
        out["act"] = tr["A_fast"].copy()
        out["loud"] = tr["rel_fast"].copy()
        out["bright"] = tr["lc_fast"] + _voice_offset(v, D, 0.5)
        out["tonal"] = tr["cf_fast"].copy()
        out["ref_desc"] = tr["desc_fast"]
        out["jump_factor"] = 1.0 - 0.75 * s * tr["onset_near"]
        med = float(np.median(tr["rel_slow"][present])) if present.any() else 0.0
        out["contour_db"] = np.clip(0.6 * s * (tr["rel_slow"] - med), -15.0, 6.0)
    elif mode == "complementary":
        E = tr["A_slow"] * tr["pres_slow"]
        if others_act:
            E = E + 0.5 * np.mean([_gauss_smooth(a, sig_s) for a in others_act], axis=0)
        loudn = np.clip((tr["rel_slow"] + 30.0) / 30.0, 0.0, 1.0)
        rest_score = _gauss_smooth(E * loudn, sig_s * 0.5)
        thr = (0.60, 0.48, 0.70)[v] + 0.3 * (1 - s)
        busy = _hysteresis(rest_score, thr, thr - 0.05, _round_half_up(0.35 / slot), _round_half_up(0.5 / slot))
        out["presence"] = ~busy
        out["act"] = np.clip((1 - s) * 0.5 + s * (1.0 - E), 0.1, 0.9)
        out["loud"] = -12.0 * s * loudn
        med = tr["lc_median"]
        out["bright"] = med + 0.6 * s * (med - tr["lc_slow"]) + _voice_offset(v, D, 0.4)
        out["tonal"] = (1 - 0.35 * s) * tr["cf_slow"] + 0.35 * s * (1 - tr["cf_slow"])
        out["ref_desc"] = np.repeat(tr["phrase_desc"][None, :], K, axis=0)
        out["w_close_t"] = np.ones(K)
        out["jump_factor"] = 0.5 + 1.0 * tr["A_slow"]
        dense = np.clip(tr["A_slow"] * loudn, 0, 1)
        out["contour_db"] = _gauss_smooth(3.0 * s * (1 - tr["pres_slow"]) - 4.0 * s * dense, sig_s)
    else:  # independent
        # own phrasing: sound phrases 1.6-4.5 s separated by 0.2-0.8 s breaths,
        # optionally snapped to nearby source pauses when s >= 0.5
        pres = np.zeros(K, bool)
        k = _round_half_up(rng_walk.uniform(0.0, 0.8) / slot) if v > 0 else 0
        src_rest = np.flatnonzero(~present)
        while k < K:
            L = _round_half_up(rng_walk.uniform(1.6, 4.5) / slot)
            e = min(K, k + L)
            if s >= 0.5 and src_rest.size:
                near = src_rest[(src_rest >= e - _round_half_up(0.5 / slot)) & (src_rest <= e + _round_half_up(0.5 / slot))]
                if near.size:
                    e = int(near[0])
            pres[k:e] = True
            k = e + max(1, _round_half_up(rng_walk.uniform(0.2, 0.8) / slot))
        out["presence"] = pres

        def ou(x0, mu, theta, sigma, lo, hi):
            xs = np.zeros(K)
            xv = x0
            for i in range(K):
                xs[i] = xv
                xv = xv + theta * (mu - xv) * slot + sigma * math.sqrt(slot) * rng_walk.standard_normal()
                xv = min(hi, max(lo, xv))
            return xs
        b0 = tr["lc_median"] + _voice_offset(v, D, 0.7)
        out["bright"] = ou(b0, b0, 0.3, 0.25, b0 - 1.2, b0 + 1.2)
        a0 = float(np.mean(tr["A_fast"][present])) if present.any() else 0.5
        out["act"] = ou(a0, 0.5, 0.4, 0.30, 0.1, 0.9)
        c0 = float(np.median(tr["conf"][present])) if present.any() else 0.5
        out["tonal"] = ou(c0, c0, 0.3, 0.15, 0.0, 1.0)
        out["loud"] = ou(-6.0, -6.0, 0.5, 3.0, -18.0, 0.0)
        out["ref_desc"] = np.repeat(tr["phrase_desc"][None, :], K, axis=0)
        tt = np.arange(K) * slot
        out["w_sim_t"] = np.exp(-tt / max(1e-3, (0.25 + 0.75 * s) * T))
    return out


def polyphonic_relationship_cost(js, k, tg, beh, glob_desc, src_desc_k, P):
    """Source-relationship term for candidate grains js at step k."""
    c = (P["w_act"] * np.abs(beh["act"][js] - tg["act"][k])
         + P["w_bri"] * np.abs(beh["lncent"][js] - tg["bright"][k]) / _LN2
         + P["w_loud"] * np.abs(beh["rel_db"][js] - tg["loud"][k]) / 12.0
         + P["w_ton"] * np.abs(beh["conf"][js] - tg["tonal"][k]))
    if P["w_sim"] > 0:
        c = c + P["w_sim"] * tg["w_sim_t"][k] * np.linalg.norm(glob_desc[js] - tg["ref_desc"][k][None, :], axis=1)
    if beh.get("is_copy") is not None:
        c = c + 3.0 * beh["is_copy"][js]
    if P["w_close"] > 0 and tg["w_close_t"][k] > 0:
        # bounded penalty for being nearly identical to the simultaneous source
        # timbre - contrast without rewarding the most distant grain
        dd = np.linalg.norm(glob_desc[js] - src_desc_k[None, :], axis=1)
        c = c + P["w_close"] * np.maximum(0.0, 0.35 - dd) / 0.35
    return c


class _OtherVoices:
    """Precomputed view of already planned voices for the interaction term."""

    def __init__(self, plans, arrays, beh, D, window_steps):
        self.v = []
        rid, rpos = arrays["run_id"], arrays["run_pos"]
        for pl in plans:
            g = np.array([st["grain"] for st in pl], dtype=np.int64)
            key = np.where(g >= 0, rid[np.maximum(g, 0)] * 1000003 + rpos[np.maximum(g, 0)], -1)
            self.v.append({"g": g, "key": key})
        self.A, self.beh, self.D, self.W = arrays, beh, D, int(window_steps)

    def __bool__(self):
        return bool(self.v)

    def cost(self, js, k, P):
        c = np.zeros(len(js))
        if not self.v:
            return c
        A, beh, D = self.A, self.beh, self.D
        rid, rpos = A["run_id"][js], A["run_pos"][js]
        ckey = rid * 1000003 + rpos
        for o in self.v:
            g = o["g"]
            K = len(g)
            near = g[max(0, k - 1):min(K, k + 2)]
            near = near[near >= 0]
            if near.size:
                c += np.isin(js, near) * (1.0 + 2.0 * D)       # same grain, same time
            if D <= 0:
                continue
            if k < K and g[k] >= 0:
                gk = g[k]
                c += ((rid == A["run_id"][gk]) & (np.abs(rpos - A["run_pos"][gk]) <= 3)) * (2.0 * D)
                dd = np.linalg.norm(A["glob_desc"][js] - A["glob_desc"][gk], axis=1)
                c += D * 0.8 * np.maximum(0.0, 1.0 - dd / 0.6)
                c += D * P["w_int_act"] * np.maximum(0.0, 1.0 - np.abs(beh["act"][js] - beh["act"][gk]) / 0.3)
                c += D * 0.4 * np.maximum(0.0, 1.0 - np.abs(beh["lncent"][js] - beh["lncent"][gk]) / (0.5 * _LN2))
            past = o["key"][max(0, k - self.W):max(0, k - 1)]
            past = past[past >= 0]
            if past.size:
                c += np.isin(ckey, past) * (0.8 * D)            # delayed copy (canon)
        return c


def inter_voice_diversity_cost(js, k, others, P):
    return others.cost(js, k, P) if others else np.zeros(len(js))


def _poly_align(prev_seg_tail, gj, lim, length):
    """Read offset 0..lim into grain gj maximising correlation with the
    outgoing overlap (phase-aware splice). Returns (delta, rho>=0)."""
    if lim < 0 or prev_seg_tail is None or len(prev_seg_tail) < 8:
        return 0, 0.0
    r0 = prev_seg_tail - prev_seg_tail.mean()
    rn = float(np.linalg.norm(r0))
    best, rb = 0, -2.0
    step = max(1, lim // 40) if lim > 40 else 1
    for d in range(0, lim + 1, step):
        seg = gj[d:d + length]
        if len(seg) < length:
            break
        s0 = seg - seg.mean()
        den = rn * float(np.linalg.norm(s0))
        rho = float(np.dot(r0, s0) / den) if den > 1e-12 else 0.0
        if rho > rb:
            best, rb = d, rho
    return best, max(0.0, rb)


def _plan_voice(v, ctx, tg, others, P, rng, forced=None):
    """Greedy step-by-step planning of one voice (or, with forced, scoring a
    given plan with exactly the same cost terms). Returns (steps, stats)."""
    A, beh, tr, info, cache = ctx["arrays"], ctx["beh"], ctx["traj"], ctx["info"], ctx["cache"]
    geo = info["geometry"]
    H, O, Le, dmax = geo["H"], geo["O"], geo["Le"], geo["dmax"]
    sr_c = info["sample_rate"]
    K = tr["K"]
    fg = beh["foreground"]
    fg_idx = np.flatnonzero(fg)
    usable = A["usable"].astype(bool)
    succ, real_len = A["succ"], A["real_len"]
    gd = A["glob_desc"]
    run_id, run_pos = A["run_id"], A["run_pos"]
    N = len(succ)
    use_count = np.zeros(N)
    recent = []                       # (grain, run_id, run_pos, k)
    recent_w = max(2, int(math.ceil(1.5 * sr_c / H)))
    replay_back = max(3, int(math.ceil(0.6 * sr_c / H)))
    dwell = max(1, int(math.ceil(0.30 * sr_c / H)))
    alpha = min(1.0, H / (0.4 * sr_c))
    ema_d, ema_a = None, None
    last_jump = -10 ** 9
    steps = []
    own_sum, int_sum, n_sound = 0.0, 0.0, 0
    prev = None   # (grain, delta)

    def rep_cost(js, k, jump):
        r = 0.15 * use_count[js]
        if recent:
            rg = np.array([q[0] for q in recent if k - q[3] <= recent_w])
            if rg.size:
                r = r + np.isin(js, rg) * 0.6
            if jump:
                hit = np.zeros(len(js), bool)
                for (g_, rr, rp, kk) in recent:
                    if k - kk <= recent_w:
                        hit |= ((run_id[js] == rr) & (run_pos[js] >= rp - replay_back)
                                & (run_pos[js] <= rp + 3))
                r = r + hit * 0.4
        return r

    def traj_cost(js):
        if ema_d is None:
            return np.zeros(len(js))
        return (0.6 * np.linalg.norm(gd[js] - ema_d[None, :], axis=1)
                + 0.4 * np.abs(beh["act"][js] - ema_a))

    def jump_cost(k):
        c = P["jump0"] * float(tg["jump_factor"][k])
        if k - last_jump < dwell:
            c += P["dwell_pen"]
        return c

    def score(js, tr_c, k, jump, entry):
        own = (polyphonic_relationship_cost(js, k, tg, beh, gd, tr["desc"][k], P)
               + P["w_traj"] * traj_cost(js) + rep_cost(js, k, jump and not entry))
        if not entry:
            own = own + P["w_tr"] * tr_c
            if jump:
                own = own + jump_cost(k)
        inter = inter_voice_diversity_cost(js, k, others, P)
        return own, inter

    for k in range(K):
        fstep = forced[k] if forced is not None else None
        sounding = (fstep["grain"] >= 0) if fstep is not None else bool(tg["presence"][k])
        if not sounding:
            steps.append({"k": k, "grain": -1, "delta": 0, "kind": "rest", "rho": 0.0,
                          "own": 0.0, "inter": 0.0, "fallback": None})
            prev = None
            continue
        fallback = None
        if prev is None:
            js = fg_idx
            trc = np.zeros(js.size)
            kinds = np.array(["start"] * js.size, dtype=object)
            jumpmask = np.zeros(js.size, bool)
            entry = True
        else:
            entry = False
            i, di = prev
            s_ = int(succ[i])
            s_ok = s_ >= 0 and usable[s_] and real_len[s_] >= di + Le
            e = A["edge_dst"][i]
            valid = e >= 0
            ej = e[valid].astype(np.int64)
            te = (A["edge_c_desc"][i][valid] + 1.0 * A["edge_c_energy"][i][valid]
                  + P["wp"] * A["edge_c_pitch"][i][valid])
            ok = fg[ej]
            ej, te = ej[ok], te[ok]
            if ej.size == 0 and not s_ok:
                allj = fg_idx[fg_idx != i]
                cd, ce, cp = _transition_components(A["tail_desc"][i], A["lnrms_tail"][i], A["f0_tail"][i],
                                                    A["conf_tail"][i], A["head_desc"][allj], A["lnrms_head"][allj],
                                                    A["f0_head"][allj], A["conf_head"][allj])
                tall = cd + 1.0 * ce + P["wp"] * cp
                o = np.argsort(tall, kind="stable")[:32]
                ej, te = allj[o], tall[o]
                fallback = "graph dead end - searched all heads directly"
            if s_ok:
                js = np.concatenate([[s_], ej]).astype(np.int64)
                trc = np.concatenate([[float(A["succ_c_desc"][i])], te])
                kinds = np.array(["chrono"] + ["graph"] * ej.size, dtype=object)
            else:
                js, trc = ej, te
                kinds = np.array(["graph"] * ej.size, dtype=object)
            if fallback:
                kinds[kinds == "graph"] = "fallback"
            jumpmask = kinds != "chrono"
        if fstep is not None:
            g = int(fstep["grain"])
            hit = np.flatnonzero(js == g)
            if hit.size:
                n = int(hit[0])
                own_v, int_v = score(js[n:n + 1], trc[n:n + 1], k, bool(jumpmask[n]), entry)
            else:
                # forced grain outside this step's candidate set (other plan's
                # jump): score it with an exact transition cost
                if entry:
                    tcost = np.zeros(1)
                else:
                    i, di = prev
                    cd, ce, cp = _transition_components(A["tail_desc"][i], A["lnrms_tail"][i], A["f0_tail"][i],
                                                        A["conf_tail"][i], A["head_desc"][[g]], A["lnrms_head"][[g]],
                                                        A["f0_head"][[g]], A["conf_head"][[g]])
                    tcost = cd + ce + P["wp"] * cp
                own_v, int_v = score(np.array([g]), tcost, k, not entry, entry)
            ch, kind, delta, rho = g, fstep["kind"], int(fstep["delta"]), float(fstep["rho"])
            own_c, int_c = float(own_v[0]), float(int_v[0])
        else:
            own_a, int_a = score(js, trc, k, True, entry) if entry else (None, None)
            if not entry:
                own_a = np.zeros(js.size)
                int_a = np.zeros(js.size)
                for flag in (False, True):
                    sel = jumpmask == flag
                    if sel.any():
                        o_, i_ = score(js[sel], trc[sel], k, flag, False)
                        own_a[sel], int_a[sel] = o_, i_
            tot = own_a + int_a
            n = _select(tot, {"topk": P["topk"], "temp": P["temp"]}, rng)
            ch, kind = int(js[n]), str(kinds[n])
            own_c, int_c = float(own_a[n]), float(int_a[n])
            if kind == "chrono":
                delta, rho = prev[1], 1.0
            elif kind == "start":
                delta, rho = 0, 0.0
            else:
                i, di = prev
                gi = cache(i)
                tail_ref = gi[di + H: di + Le].astype(np.float64)
                gj = cache(ch).astype(np.float64)
                delta, rho = _poly_align(tail_ref, gj, int(min(dmax, real_len[ch] - Le)), len(tail_ref))
        if kind in ("graph", "fallback"):
            last_jump = k
        steps.append({"k": k, "grain": ch, "delta": int(delta), "kind": kind, "rho": float(rho),
                      "own": round(own_c, 5), "inter": round(int_c, 5), "fallback": fallback})
        own_sum += own_c
        int_sum += int_c
        n_sound += 1
        prev = (ch, int(delta))
        use_count[ch] += 1
        recent.append((ch, int(run_id[ch]), int(run_pos[ch]), k))
        if len(recent) > 4 * recent_w:
            recent.pop(0)
        dv = gd[ch].astype(np.float64)
        ema_d = dv if ema_d is None else (1 - alpha) * ema_d + alpha * dv
        ema_a = beh["act"][ch] if ema_a is None else (1 - alpha) * ema_a + alpha * beh["act"][ch]
    stats = {"own_mean": own_sum / max(1, n_sound), "inter_mean": int_sum / max(1, n_sound),
             "total_mean": (own_sum + int_sum) / max(1, n_sound), "sounding_steps": n_sound}
    return steps, stats


def _act_track(plan, beh):
    return np.array([beh["act"][st["grain"]] if st["grain"] >= 0 else 0.0 for st in plan])


def _voice_rng(seed, v, pass_no, salt):
    return np.random.default_rng(np.random.SeedSequence([int(seed) & 0xFFFFFFFF, salt, int(v), int(pass_no)]))


def plan_polyphonic_voices(ctx, mode, n_voices, s, D, seed, refine=True):
    """Sequential conditioning + optional refinement sweep (see header)."""
    tr = ctx["traj"]
    window = int(math.ceil(2.0 / tr["slot_s"]))
    plans, targets, stats, P = [], [], [], _poly_params(mode, s, D)
    walk = [_voice_rng(seed, v, 0, POLY_SEED_SALT_WALK) for v in range(n_voices)]
    walk_targets = {}
    for v in range(n_voices):
        others_act = [_act_track(pl, ctx["beh"]) for pl in plans]
        if mode == "independent":
            if v not in walk_targets:
                walk_targets[v] = _poly_voice_targets(mode, v, tr, s, D, walk[v], [])
            tg = walk_targets[v]
        else:
            tg = _poly_voice_targets(mode, v, tr, s, D, None, others_act)
        others = _OtherVoices(plans, ctx["arrays"], ctx["beh"], D, window)
        pl, st = _plan_voice(v, ctx, tg, others, P, _voice_rng(seed, v, 1, POLY_SEED_SALT_SELECT))
        plans.append(pl)
        targets.append(tg)
        stats.append(dict(st, refined=False, pass1_total_mean=st["total_mean"]))
    refine_log = []
    if refine and n_voices > 1:
        for v in range(n_voices):
            rest = [plans[u] for u in range(n_voices) if u != v]
            others = _OtherVoices(rest, ctx["arrays"], ctx["beh"], D, window)
            if mode == "independent":
                tg = walk_targets[v]
            else:
                tg = _poly_voice_targets(mode, v, tr, s, D, None, [_act_track(p, ctx["beh"]) for p in rest])
            _, old = _plan_voice(v, ctx, tg, others, P, None, forced=plans[v])
            new_pl, new = _plan_voice(v, ctx, tg, others, P, _voice_rng(seed, v, 2, POLY_SEED_SALT_SELECT))
            accept = new["total_mean"] < old["total_mean"] - 1e-9
            refine_log.append({"voice": v + 1, "old_total_mean": round(old["total_mean"], 5),
                               "new_total_mean": round(new["total_mean"], 5), "accepted": bool(accept)})
            if accept:
                changed = sum(1 for a, b in zip(plans[v], new_pl) if a["grain"] != b["grain"])
                refine_log[-1]["steps_changed"] = changed
                plans[v] = new_pl
                targets[v] = tg
                stats[v] = dict(new, refined=True, pass1_total_mean=stats[v]["pass1_total_mean"])
    return plans, targets, stats, P, refine_log


def render_polyphonic_voice(plan, info, cache, n_c):
    """Overlap-add on the corpus grid. Same Tukey geometry as continuation:
    chronological neighbours reconstruct the corpus recording exactly; jumps
    get the correlation-adaptive overlap correction; an entry after a rest
    (or at sample 0) uses the rising taper as its soft entrance and gets NO
    correction (there is nothing to cross-fade with)."""
    geo = info["geometry"]
    H, O, Le = geo["H"], geo["O"], geo["Le"]
    out = np.zeros(n_c + Le + H, dtype=np.float64)
    gain = np.ones_like(out)
    w = _tukey(Le, O, rise=True)
    m = (np.arange(O) + 0.5) / O
    f_fall = np.cos(0.5 * np.pi * m) ** 2
    f_rise = np.sin(0.5 * np.pi * m) ** 2
    for st in plan:
        if st["grain"] < 0:
            continue
        p = st["k"] * H
        if p >= len(out):
            break
        g = cache(st["grain"])
        seg = g[st["delta"]: st["delta"] + Le].astype(np.float64)
        if len(seg) < Le:
            seg = np.pad(seg, (0, Le - len(seg)))
        end = min(len(out), p + Le)
        out[p:end] += (seg * w)[:end - p]
        if st["kind"] in ("graph", "fallback"):
            rho = float(np.clip(st["rho"], 0.0, 1.0))
            comp = 1.0 / np.sqrt(f_fall ** 2 + f_rise ** 2 + 2 * rho * f_fall * f_rise)
            e2 = min(len(out), p + O)
            gain[p:e2] *= comp[:e2 - p]
    return (out * gain)[:n_c]


def _sound_mask(plan, info, sr, n):
    geo = info["geometry"]
    H, Le, sr_c = geo["H"], geo["Le"], info["sample_rate"]
    msk = np.zeros(n, bool)
    for st in plan:
        if st["grain"] >= 0:
            a = int(st["k"] * H * sr / float(sr_c))
            b = int(math.ceil((st["k"] * H + Le) * sr / float(sr_c)))
            msk[max(0, a):min(n, b)] = True
    return msk


def _active_median_rms(y, msk, sr, floor_db=40.0):
    """The SAME level measure as the source's active RMS: median RMS of the
    10 ms frames that lie inside the sounding mask and within floor_db of
    the loudest such frame."""
    fn = max(1, _round_half_up(0.010 * sr))
    nf = len(y) // fn
    if nf == 0:
        return 0.0
    fr = np.sqrt(np.mean(y[:nf * fn].reshape(nf, fn) ** 2, axis=1))
    fm = msk[:nf * fn].reshape(nf, fn).mean(axis=1) >= 0.5
    v = fr[fm]
    if v.size == 0 or v.max() <= 0:
        return 0.0
    v = v[v >= v.max() * 10 ** (-floor_db / 20.0)]
    return float(np.median(v))


def prepare_polyphonic_levels(y, msk, sr, phrase_rms, level_mode, voice_level_db, contour_db_steps, slot_s,
                              keep=0.5):
    """Voice level matching (distinct from final mix normalisation):
      match  - constant gain so the voice's median active level equals the
               source's active RMS + voice_level_db (bounded +-30 dB, so weak
               corpus material is not left inaudible), then a slow masked
               levelling that removes half of the grain-to-grain swings
               (bounded +-9 dB, 100 ms smoothing, computed only where the
               voice sounds so rests never pump), times the relationship's
               behavioural contour (parallel: follows the source dynamics;
               complementary: prominence in source pauses, recession in
               dense passages).
      corpus - corpus level kept, + voice_level_db and the contour only.
    Then a ceiling: if the voice would exceed 0.98 it is scaled down as a
    whole (recorded) - never per-voice peak normalisation upwards."""
    from scipy.ndimage import uniform_filter1d
    n = len(y)
    info = {}
    t = np.arange(n) / float(sr)
    contour = np.interp(t, np.arange(len(contour_db_steps)) * slot_s + 0.5 * slot_s, contour_db_steps) \
        if len(contour_db_steps) > 1 else np.zeros(n)
    g_log = np.zeros(n)
    if msk.any():
        w = max(1, _round_half_up(0.200 * sr))
        mf = msk.astype(np.float64)
        pw = uniform_filter1d(y * y * mf, size=w, mode="nearest")
        den = uniform_filter1d(mf, size=w, mode="nearest")
        valid = den > 0.2
        lvl = np.sqrt(np.maximum(pw / np.maximum(den, 1e-9), 1e-14))
        ll = np.log(lvl)
        med = float(np.median(ll[valid & msk])) if (valid & msk).any() else float(np.median(ll[msk]))
        if level_mode == "match":
            g0 = math.log(max(phrase_rms, 1e-7)) + voice_level_db / 20.0 * math.log(10.0) - med
            g0 = float(np.clip(g0, -math.log(10 ** 1.5), math.log(10 ** 1.5)))
            loc = (keep - 1.0) * (ll - med)
            loc = np.where(valid, np.clip(loc, -math.log(10 ** (9 / 20.0)), math.log(10 ** (9 / 20.0))), 0.0)
            idx = np.flatnonzero(valid)
            if idx.size:
                loc = np.interp(np.arange(n), idx, loc[idx])
            loc = uniform_filter1d(loc, size=max(1, _round_half_up(0.100 * sr)), mode="nearest")
            g_log = g0 + loc
            info["match_gain_db"] = 20 * g0 / math.log(10)
        else:
            g_log = np.full(n, voice_level_db / 20.0 * math.log(10.0))
            info["match_gain_db"] = voice_level_db
    g_log = g_log + contour / 20.0 * math.log(10.0)
    out = y * np.exp(g_log)
    if level_mode == "match" and msk.any():
        # one exact correction: the voice's active level (same measure as the
        # source's) lands on target, whatever the levelling did to its shape
        want = max(phrase_rms, 1e-7) * 10 ** (voice_level_db / 20.0)
        got = _active_median_rms(out, msk, sr)
        if got > 1e-9:
            corr = float(np.clip(want / got, 10 ** (-12 / 20.0), 10 ** (12 / 20.0)))
            out = out * corr
            info["correction_db"] = 20 * math.log10(corr)
    # technical fades only (no musical envelope): 5 ms at both ends
    f = max(1, _round_half_up(0.005 * sr))
    if n > 2 * f:
        r = np.sin(0.5 * np.pi * (np.arange(f) + 0.5) / f) ** 2
        out[:f] *= r
        out[-f:] *= r[::-1]
    pk = float(np.abs(out).max()) if n else 0.0
    ceil_db = 0.0
    if pk > 0.98:
        out *= 0.98 / pk
        ceil_db = 20 * math.log10(0.98 / pk)
    out = np.nan_to_num(out)
    info.update(ceiling_gain_db=ceil_db, peak=float(np.abs(out).max()) if n else 0.0,
                active_rms=_active_median_rms(out, msk, sr),
                target_rms=max(phrase_rms, 1e-7) * 10 ** (voice_level_db / 20.0) if level_mode == "match" else None,
                contour_db_range=[float(contour.min()) if n else 0.0, float(contour.max()) if n else 0.0])
    return out, info


def _pan_gains(p100):
    p = float(np.clip(p100, -100.0, 100.0)) / 100.0
    return math.cos((p + 1.0) * math.pi / 4.0), math.sin((p + 1.0) * math.pi / 4.0)


def _safe_stem_name(name):
    s = "".join("_" if ch in '\\/:*?"<>|' or ord(ch) < 32 else ch for ch in name).strip().rstrip(".")
    return s or "Sound"


def _export_stems(export_dir, base, source, voices, mix, sr):
    """Write a NEW stem set (never overwrite): if any target exists, the
    whole set gets a _set2, _set3, ... suffix. Float32 WAV, original rate."""
    import soundfile as sf
    os.makedirs(export_dir, exist_ok=True)
    base = _safe_stem_name(base)
    for n in range(1, 1000):
        stem = base if n == 1 else "%s_set%d" % (base, n)
        names = ["%s_Source.wav" % stem] + ["%s_Voice_%d.wav" % (stem, v + 1) for v in range(len(voices))]
        if mix is not None:
            names.append("%s_Stereo_Mix.wav" % stem)
        paths = [os.path.join(export_dir, nm) for nm in names]
        if not any(os.path.exists(p) for p in paths):
            break
    else:
        raise RuntimeError("could not find a free stem-set name in %s" % export_dir)
    data = [source] + list(voices) + ([mix] if mix is not None else [])
    tag = "%d_%d" % (os.getpid(), int(time.time() * 1000))
    written = []
    try:
        for p, d in zip(paths, data):
            tmp = p + ".part_" + tag + ".wav"
            sf.write(tmp, np.asarray(d, dtype=np.float32), sr, subtype="FLOAT")
            if os.path.exists(p):
                os.remove(tmp)
                raise RuntimeError("stem appeared during export, not overwriting: %s" % p)
            os.replace(tmp, p)
            written.append(p)
    except Exception:
        for p in written:
            try:
                os.remove(p)
            except OSError:
                pass
        raise
    return stem, paths


def _write_poly_textgrid(path, plans, tr, info, index, total_s):
    H, sr_c = info["geometry"]["H"], info["sample_rate"]
    code = {"start": "S", "chrono": "C", "graph": "J", "fallback": "F"}

    def tier(ivs):
        out, cur = [], 0.0
        for a, b, lab in ivs:
            a, b = max(a, cur), min(b, total_s)
            if b <= a + 1e-9:
                continue
            if a > cur + 1e-9:
                out.append((cur, a, ""))
            if out and out[-1][2] == lab and lab in ("", "rest", "sustained", "active") and abs(out[-1][1] - a) < 1e-9:
                out[-1] = (out[-1][0], b, lab)
            else:
                out.append((a, b, lab))
            cur = b
        if cur < total_s - 1e-9:
            out.append((cur, total_s, ""))
        return out
    tiers = [("source analysis", tier([(k * H / float(sr_c), (k + 1) * H / float(sr_c), str(tr["segment"][k]))
                                       for k in range(tr["K"])]))]
    for v, pl in enumerate(plans):
        ivs = []
        for st in pl:
            a, b = st["k"] * H / float(sr_c), (st["k"] + 1) * H / float(sr_c)
            if st["grain"] < 0:
                ivs.append((a, b, ""))
            else:
                gm = index["grains"][st["grain"]]
                ivs.append((a, b, ("%s %s@%.3f" % (code.get(st["kind"], "?"), gm["source_file"],
                                                   float(gm["start_s"]))).replace('"', "'")))
        tiers.append(("poly voice %d" % (v + 1), tier(ivs)))
    L = ['File type = "ooTextFile"', 'Object class = "TextGrid"', "", "xmin = 0",
         "xmax = %.9f" % total_s, "tiers? <exists>", "size = %d" % len(tiers), "item []:"]
    for n, (name, iv) in enumerate(tiers, 1):
        L += ["    item [%d]:" % n, '        class = "IntervalTier"', '        name = "%s"' % name,
              "        xmin = 0", "        xmax = %.9f" % total_s, "        intervals: size = %d" % len(iv)]
        for m, (a, b, lab) in enumerate(iv, 1):
            L += ["        intervals [%d]:" % m, "            xmin = %.9f" % a,
                  "            xmax = %.9f" % b, '            text = "%s"' % lab]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


def _poly_voice_stats(plan, beh, A, H, sr_c):
    kinds = [st["kind"] for st in plan]
    snd = [st for st in plan if st["grain"] >= 0]
    dur = len(plan) * H / float(sr_c)
    runs, r = [], 0
    for st in plan[1:]:
        if st["kind"] == "chrono":
            r += 1
        elif r:
            runs.append(r)
            r = 0
    if r:
        runs.append(r)
    first = next((st["k"] for st in plan if st["grain"] >= 0), None)
    last = next((st["k"] for st in reversed(plan) if st["grain"] >= 0), None)
    return {"sounding_fraction": len(snd) / max(1, len(plan)),
            "transitions": {k: kinds.count(k) for k in ("start", "chrono", "graph", "fallback", "rest")},
            "jumps_per_s": (kinds.count("graph") + kinds.count("fallback")) / max(1e-9, dur),
            "mean_chrono_run_s": (float(np.mean(runs)) * H / sr_c) if runs else 0.0,
            "distinct_grains": len(set(st["grain"] for st in snd)),
            "distinct_recordings": len(set(int(A["run_id"][st["grain"]]) for st in snd)),
            "first_sound_s": None if first is None else first * H / float(sr_c),
            "last_sound_end_s": None if last is None else (last + 1) * H / float(sr_c)}


def polyphonic_layers(args):
    """Wrapper: a failure is REPORTED (status error in the result file and on
    stdout, exit 0) so the front-end can show the reason instead of a
    generic 'no result'. The paths written are echoed on stdout."""
    code = 0
    try:
        _polyphonic_layers_impl(args)
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else 1
    except Exception:
        sys.stderr.write("ERROR:\n" + traceback.format_exc() + "\n")
        code = 1
    if code:
        if args.result:
            try:
                with open(args.result, "w", encoding="utf-8", newline="\n") as f:
                    f.write("ccc_poly_result 1\nstatus error\nexit_code %d\n" % code)
            except Exception:
                pass
        sys.stdout.write("CCC_POLY_STATUS error (code %d)\n" % code)
    else:
        sys.stdout.write("CCC_POLY_STATUS ok\n")
    for label, p in (("result", args.result), ("log", getattr(args, "log", None))):
        if p:
            sys.stdout.write("CCC_POLY_FILE %s %s exists=%s\n" % (label, os.path.abspath(p), os.path.exists(p)))
    for v in range(int(args.voices) if 1 <= int(args.voices) <= 3 else 0):
        p = os.path.join(args.output_dir, "%s_voice_%d.wav" % (args.run_tag, v + 1))
        sys.stdout.write("CCC_POLY_FILE voice%d %s exists=%s\n" % (v + 1, os.path.abspath(p), os.path.exists(p)))
    sys.stdout.flush()


def _polyphonic_layers_impl(args):
    import soundfile as sf
    nv = int(args.voices)
    if not 1 <= nv <= POLY_MAX_VOICES:
        _fail("--voices must be 1..3", 4)
    mode = args.relationship
    s = float(np.clip(args.relationship_strength / 100.0, 0.0, 1.0))
    D = float(np.clip(args.inter_voice_diversity / 100.0, 0.0, 1.0))
    index, _ = _load_corpus_index(args.index, mmap=True)
    codec = make_codec(index["codec"])
    try:
        arrays, ginfo, built_now, why = load_or_build_graph(args.index, index, codec, rebuild=False)
    except Exception as e:
        _fail("could not load or build the transition graph: %s" % e)
    try:
        si = sf.info(args.input)
    except Exception as e:
        _fail("cannot read source WAV: %s" % e, 3)
    if si.channels != 1:
        _fail("source has %d channels; Polyphonic Layers v1 accepts mono only" % si.channels, 5)
    x, sr = sf.read(args.input, dtype="float64", always_2d=True)
    x = np.nan_to_num(x[:, 0])
    N = len(x)
    if N < 0.3 * sr:
        _fail("source is shorter than 0.3 s", 3)
    if float(np.abs(x).max()) < 1e-6:
        _fail("source is silent", 3)
    beh = corpus_behaviour(arrays)
    if beh["foreground"].sum() < 2:
        _fail("the corpus has fewer than 2 usable grains", 6)
    t0 = time.time()
    tr = analyze_source_trajectory(x, sr, codec, arrays, ginfo, beh)
    if not tr["present"].any():
        _fail("no active sound found in the source", 3)
    cache = _GrainCache(args.index, index["grains"])
    xc_src = resample_to(x.astype(np.float32), sr, int(ginfo["sample_rate"])).astype(np.float64)
    beh["is_copy"] = find_source_copy_grains(xc_src, tr, arrays, ginfo, cache)
    t_an = time.time() - t0
    ctx = {"arrays": arrays, "beh": beh, "traj": tr, "info": ginfo, "cache": cache}
    t0 = time.time()
    plans, targets, vstats, P, refine_log = plan_polyphonic_voices(ctx, mode, nv, s, D, args.seed,
                                                                   refine=bool(args.refine))
    t_plan = time.time() - t0
    sr_c = int(ginfo["sample_rate"])
    H = ginfo["geometry"]["H"]
    n_c = int(math.ceil(N * sr_c / float(sr))) + 2 * H
    voices, linfo = [], []
    t0 = time.time()
    for v in range(nv):
        raw_c = render_polyphonic_voice(plans[v], ginfo, cache, n_c)
        y = resample_to(raw_c.astype(np.float32), sr_c, sr).astype(np.float64)
        y = y[:N] if len(y) >= N else np.pad(y, (0, N - len(y)))
        msk = _sound_mask(plans[v], ginfo, sr, N)
        y, li = prepare_polyphonic_levels(y, msk, sr, tr["phrase_rms"], args.level_mode, args.voice_level_db,
                                          targets[v]["contour_db"], tr["slot_s"])
        voices.append(y.astype(np.float32))
        linfo.append(li)
    t_render = time.time() - t0
    # ---- pans and the stereo mix (Praat performs the same arithmetic) ----
    if args.pan_mode == "auto":
        pans = list(POLY_AUTO_PANS[nv])
    else:
        pans = [float(np.clip(p, -100, 100)) for p in (args.pan_1, args.pan_2, args.pan_3)[:nv]]
    gS = _pan_gains(0.0)
    gV = [_pan_gains(p) for p in pans]
    L = gS[0] * x
    R = gS[1] * x
    for v in range(nv):
        L = L + gV[v][0] * voices[v].astype(np.float64)
        R = R + gV[v][1] * voices[v].astype(np.float64)
    mix_peak = float(max(np.abs(L).max(), np.abs(R).max()))
    target = 10 ** (args.mix_target_db / 20.0)
    mix_gain = (target / mix_peak) if (args.normalize_mix and mix_peak > 1e-9) else 1.0
    # ---- write voices atomically ----
    os.makedirs(args.output_dir, exist_ok=True)
    vpaths = []
    for v in range(nv):
        p = os.path.join(args.output_dir, "%s_voice_%d.wav" % (args.run_tag, v + 1))
        tmp = p + ".part.wav"
        sf.write(tmp, voices[v], sr, subtype="FLOAT")
        os.replace(tmp, p)
        vpaths.append(p)
    # ---- optional DAW stems ----
    stem_set, stem_paths = None, []
    src_exact = bool(np.array_equal(x.astype(np.float32).astype(np.float64), x))
    if args.export_dir:
        mix = None
        if args.export_mix:
            mix = np.stack([L * mix_gain, R * mix_gain], axis=1)
        try:
            stem_set, stem_paths = _export_stems(args.export_dir, args.export_name or "Sound", x, voices, mix, sr)
        except Exception as e:
            _fail("stem export failed (no files left behind): %s" % e, 7)
    if args.result:
        with open(args.result, "w", encoding="utf-8", newline="\n") as f:
            f.write("ccc_poly_result 1\nstatus ok\n")
            f.write("sample_rate %d\nsamples %d\nvoices %d\n" % (sr, N, nv))
            f.write("source_gain_L %.17g\nsource_gain_R %.17g\n" % gS)
            for v in range(nv):
                f.write("pan_%d %.17g\ngain_L_%d %.17g\ngain_R_%d %.17g\n"
                        % (v + 1, pans[v], v + 1, gV[v][0], v + 1, gV[v][1]))
                f.write("voice_rms_%d %.9g\nvoice_peak_%d %.9g\n"
                        % (v + 1, linfo[v]["active_rms"], v + 1, linfo[v]["peak"]))
            f.write("mix_peak_before %.17g\nmix_gain %.17g\n" % (mix_peak, mix_gain))
            f.write("source_active_rms %.9g\n" % tr["phrase_rms"])
            f.write("source_stem_exact %d\n" % (1 if src_exact else 0))
            f.write("graph_built_now %d\n" % (1 if built_now else 0))
            if stem_set is not None:
                f.write("export_count %d\n" % len(stem_paths))
                f.write("export_set %s\n" % stem_set)
    if args.metadata:
        write_polyphonic_metadata(args, index, ginfo, tr, plans, targets, vstats, P, refine_log, pans, gS, gV,
                                  linfo, mix_peak, mix_gain, N, sr, beh, arrays, why, built_now,
                                  stem_paths, src_exact, {"analysis_s": t_an, "planning_s": t_plan,
                                                          "render_s": t_render, "grain_loads": cache.loads})
    if args.textgrid:
        _write_poly_textgrid(args.textgrid, plans, tr, ginfo, index, N / float(sr))
    parts = []
    for v in range(nv):
        vs = _poly_voice_stats(plans[v], beh, arrays, H, sr_c)
        tc = vs["transitions"]
        parts.append("v%d S%d C%d J%d F%d, %.0f%% sounding" % (v + 1, tc["start"], tc["chrono"], tc["graph"],
                                                              tc["fallback"], 100 * vs["sounding_fraction"]))
    summ = "; ".join(parts)
    sys.stdout.write("Polyphonic layers done: %s, %d voice(s) [%s], graph %s\n"
                     % (mode, nv, summ, "built" if built_now else "cached"))


def write_polyphonic_metadata(args, index, ginfo, tr, plans, targets, vstats, P, refine_log, pans, gS, gV, linfo,
                              mix_peak, mix_gain, N, sr, beh, A, why, built_now, stem_paths, src_exact, timing):
    H, sr_c = ginfo["geometry"]["H"], ginfo["sample_rate"]
    per_voice = []
    for v, pl in enumerate(plans):
        steps = []
        for st in pl:
            if st["grain"] < 0:
                steps.append({"k": st["k"], "t_s": round(st["k"] * H / float(sr_c), 6), "transition": "rest"})
                continue
            gm = index["grains"][st["grain"]]
            steps.append({"k": st["k"], "t_s": round(st["k"] * H / float(sr_c), 6), "grain_id": gm["id"],
                          "corpus_file": gm["source_file"], "corpus_start_s": float(gm["start_s"]),
                          "read_offset_samples": st["delta"], "transition": st["kind"],
                          "own_cost": st["own"], "interaction_cost": st["inter"],
                          "overlap_correlation": round(st["rho"], 4), "fallback": st["fallback"]})
        per_voice.append({
            "voice": v + 1, "pan": pans[v], "gain_L": gV[v][0], "gain_R": gV[v][1],
            "levels": linfo[v], "planning": vstats[v],
            "summary": _poly_voice_stats(pl, beh, A, H, sr_c), "steps": steps})
    meta = {
        "mode": "polyphonic-layers",
        "decisions_vs_diagnostics": ("'voices[*].steps', pans, gains, mix_gain and 'parameters' are the "
                                     "algorithm's actual decisions; 'source_analysis' and 'voices[*].summary' are "
                                     "descriptive measurements. No harmonic/consonance claim is made."),
        "source": {"input": os.path.basename(args.input), "name": args.export_name, "samples": N,
                   "sample_rate": sr, "duration_s": N / float(sr), "active_rms": tr["phrase_rms"],
                   "stem_exact_in_float32": src_exact,
                   "corpus_grains_identified_as_this_source": int(beh["is_copy"].sum()),
                   "note": "grains identified as copies of the source phrase are penalised in every voice"},
        "corpus": {"codec": index["codec"], "index_json_sha256": ginfo.get("index_json_sha256"),
                   "corpus_sample_rate": sr_c, "graph_schema": ginfo.get("graph_schema"),
                   "graph_status": why, "graph_built_now": built_now,
                   "descriptor": ginfo.get("descriptor", {}).get("mode")},
        "parameters": {"relationship": args.relationship, "voices": len(plans),
                       "relationship_strength": args.relationship_strength,
                       "inter_voice_diversity": args.inter_voice_diversity, "seed": int(args.seed),
                       "refine": bool(args.refine), "level_mode": args.level_mode,
                       "voice_level_db": args.voice_level_db, "pan_mode": args.pan_mode,
                       "normalize_mix": bool(args.normalize_mix), "mix_target_db": args.mix_target_db,
                       "output_mode": args.output_mode, "weights": {k: (round(v, 4) if isinstance(v, float) else v)
                                                                     for k, v in P.items()}},
        "seeding": "per voice: numpy SeedSequence([seed, salt, voice, pass]) - independent of the voice count",
        "refinement": refine_log,
        "mix": {"source_gain_L": gS[0], "source_gain_R": gS[1], "peak_before_normalisation": mix_peak,
                "normalisation_gain": mix_gain, "normalisation_gain_db": 20 * math.log10(mix_gain),
                "applies_to": "stereo mix only - separate voice objects and stems keep their pre-mix level"},
        "exported_files": stem_paths,
        "timing": timing,
        "voices": per_voice,
        "source_analysis": {
            "step_s": tr["slot_s"], "segment": [str(x) for x in tr["segment"]],
            "present": [bool(x) for x in tr["present"]],
            "activity": [round(float(x), 4) for x in tr["A_fast"]],
            "rel_loudness_db": [round(float(x), 2) for x in tr["rel_db"]],
            "brightness_hz": [round(float(math.exp(x)), 1) for x in tr["lncent"]],
            "periodicity": [round(float(x), 3) for x in tr["conf"]],
            "f0_hz": [round(float(x), 1) for x in tr["f0"]],
            "onsets_s": [round(float(x), 4) for x in tr["onsets_s"]],
        },
    }
    with open(args.metadata, "w") as f:
        json.dump(meta, f, indent=1)


# ============================================================
# CLI
# ============================================================

def _nonneg_float(x):
    """argparse type: parses a float and clamps negative values to 0, with a
    warning. Weight/penalty fields (bigram/hist/energy weight, repeat
    penalty) are meant to scale a distance term up or down - since cosine
    distance is already sign-sensitive in ways a negative weight wouldn't
    cleanly invert, and a negative energy-weight or repeat-penalty would
    silently flip its intended effect (e.g. REWARDING repetition instead of
    penalising it), negative input is treated as a user error and clamped
    rather than accepted."""
    v = float(x)
    if v < 0:
        sys.stderr.write(
            "Warning: negative value %.4g not allowed for this parameter; "
            "clamped to 0.\n" % v)
        v = 0.0
    return v


def _expand_arg_files(argv):
    out = [argv[0]] if argv else []
    for a in argv[1:]:
        if a.startswith("@") and len(a) > 1 and os.path.isfile(a[1:]):
            raw = open(a[1:], "rb").read()
            if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
                txt = raw.decode("utf-16")
            else:
                try:
                    txt = raw.decode("utf-8-sig")
                except UnicodeDecodeError:
                    txt = raw.decode("latin-1")
            lines = txt.replace("\r\n", "\n").replace("\r", "\n").split("\n")
            if lines and lines[-1] == "":
                lines = lines[:-1]
            out.extend(lines)
        else:
            out.append(a)
    return out


_OPTIONAL_PATH_ARGS = ("textgrid", "metadata", "export_dir", "result", "contour_out", "log",
                       "success_marker", "export_name")


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
    b.add_argument("--atomic", action="store_true",
                   help="build in a staging directory and replace the live corpus "
                        "only after the complete build succeeds")
    b.add_argument("--success-marker", default=None,
                   help="optional file written only after a successful build/promotion")
    b.set_defaults(func=build_corpus)

    m = sub.add_parser("match", parents=[common], help="encode source, match corpus, reconstruct")
    m.add_argument("--codec", default="auto", help="encodec | dac | mock | auto")
    m.add_argument("--input", required=True, help="source WAV from Praat")
    m.add_argument("--output", required=True, help="output WAV")
    m.add_argument("--index", required=True, help="corpus index path prefix")
    m.add_argument("--metadata", default=None, help="optional JSON metadata path")
    m.add_argument("--textgrid", default=None, help="optional TextGrid path")
    m.add_argument("--xfade-ms", type=float, default=20.0)
    m.add_argument("--repeat-penalty", type=_nonneg_float, default=0.05)
    m.add_argument("--energy-weight", type=_nonneg_float, default=1.0,
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
    m.add_argument("--analysis-grain-ms", type=float, default=150.0,
                   help="size (ms) of the internal analysis sub-window used to "
                        "subdivide each onset-bounded segment for matching. "
                        "Separate from build-corpus's --grain-ms: this only "
                        "controls how finely a segment's evolving decay/sustain "
                        "is re-matched against the corpus after the onset; it "
                        "never moves the onset boundary itself. A window this "
                        "short (formerly 60ms default) can leave very few "
                        "token frames/transitions for some codecs - see the "
                        "n_token_frames/n_bigrams warning in match's output.")
    m.add_argument("--analysis-hop-ms", type=float, default=45.0,
                   help="hop (ms) between analysis sub-windows within a segment; "
                        "hop < analysis-grain-ms means overlapping analysis "
                        "windows (smoother tracking of the decay), same shape as "
                        "build-corpus's grain/hop relationship")
    m.add_argument("--match-duration", type=int, default=1,
                   help="1 = trim/pad output to source duration")
    m.set_defaults(func=match)

    dr = sub.add_parser("draw", parents=[common],
                        help="brightness-contour synthesis from a RealTier or saved contour")
    dr.add_argument("--tier", default=None,
                    help="Praat RealTier text file (interactive/backward-compatible source)")
    dr.add_argument("--contour", default=None,
                    help="saved corpus_draw_contour file (reproducible/batch source)")
    dr.add_argument("--contour-out", default=None,
                    help="optional path for the normalized time->brightness contour actually used")
    dr.add_argument("--output", required=True, help="output WAV")
    dr.add_argument("--index", required=True, help="corpus index path prefix")
    dr.add_argument("--metadata", default=None, help="optional JSON metadata path")
    dr.add_argument("--textgrid", default=None, help="optional TextGrid path")
    dr.add_argument("--duration", type=float, default=0.0,
                    help="output duration (s); 0 = use the tier's own xmax")
    dr.add_argument("--grain-rate-ms", type=float, default=80.0,
                    help="place one grain every N ms along the drawn curve")
    dr.add_argument("--xfade-ms", type=float, default=20.0)
    dr.add_argument("--repeat-penalty", type=_nonneg_float, default=0.05)
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
    gr.add_argument("--bigram-weight", type=_nonneg_float, default=4.0,
                    help="weight of the hashed-bigram (token-transition) section; "
                         "high by default so kinetic motion drives the match")
    gr.add_argument("--hist-weight", type=_nonneg_float, default=0.5,
                    help="weight of the token-histogram (timbre) section; low by "
                         "default so literal tone-colour is de-emphasised")
    gr.add_argument("--energy-weight", type=_nonneg_float, default=0.2,
                    help="weight of the log-RMS loudness term; low by default so "
                         "energy can't dominate the kinetic bigram match")
    gr.add_argument("--analysis-grain-ms", type=float, default=150.0,
                    help="size (ms) of the internal analysis sub-window "
                         "(see match's --analysis-grain-ms help for detail; "
                         "raised from a 60ms default since short windows can "
                         "starve the bigram section of real transitions)")
    gr.add_argument("--analysis-hop-ms", type=float, default=45.0)
    gr.add_argument("--onset-min-interval-ms", type=float, default=60.0,
                    dest="onset_min_interval_ms")
    gr.add_argument("--repeat-penalty", type=_nonneg_float, default=0.05)
    gr.add_argument("--xfade-ms", type=float, default=20.0)
    gr.add_argument("--match-duration", type=int, default=1,
                    help="1 = trim/pad output to source duration")
    gr.add_argument("--sequence-context", type=int, default=0,
                    dest="sequence_context",
                    help="CONTEXT SMOOTHING, not a sequence/order model: "
                         "averages source features over this many PRECEDING "
                         "sub-windows (0 = independent windows). Because it's "
                         "an unordered mean, [A, B] and [B, A] produce the "
                         "SAME averaged vector - it stabilises matches across "
                         "neighbouring windows, it does not know which window "
                         "came first or in what direction motion is heading.")
    gr.add_argument("--silence-floor", type=float, default=1e-4)
    gr.add_argument("--random-baseline", type=int, default=0,
                    dest="random_baseline",
                    help="1 = ablation condition: ignore all distance "
                         "matching and pick a uniformly random corpus grain "
                         "for every sub-window, keeping onsets, sub-window "
                         "subdivision, and overlap-add identical to every "
                         "other condition. Use with --seed for a "
                         "reproducible run. Isolates how much of the output "
                         "comes from bigram/histogram/energy matching versus "
                         "just inheriting the source's rhythmic skeleton.")
    gr.add_argument("--seed", type=int, default=1234,
                    help="random seed for --random-baseline (ignored "
                         "otherwise, since normal matching is a "
                         "deterministic argmin with no randomness). "
                         "Defaults to a fixed value rather than None so "
                         "that --random-baseline 1 without an explicit "
                         "--seed is still reproducible run to run.")
    gr.set_defaults(func=gesture_rhyme)

    ct = sub.add_parser("continuation-tail", parents=[common],
                        help="extend a phrase with a corpus-derived continuation "
                             "(writes the tail buffer only; the join is done in Praat)")
    ct.add_argument("--codec", default="auto", help="ignored except for a warning; the corpus codec is used")
    ct.add_argument("--input", required=True, help="source WAV (mono) exported by Praat")
    ct.add_argument("--output", required=True,
                    help="tail WAV: crossfade region + new material, 32-bit float, source rate")
    ct.add_argument("--result", default=None, help="key/value join description read by Praat")
    ct.add_argument("--index", required=True, help="EXISTING corpus index prefix")
    ct.add_argument("--duration-mode", choices=("percent", "seconds"), default="percent")
    ct.add_argument("--tail-percent", type=float, default=50.0)
    ct.add_argument("--tail-seconds", type=float, default=4.0)
    ct.add_argument("--continuation-mode", choices=("tight", "textural"), default="tight")
    ct.add_argument("--continuation-strength", type=float, default=75.0, help="0..100")
    ct.add_argument("--envelope", choices=ENVELOPES, default="exp-decay")
    ct.add_argument("--xfade-ms", type=_nonneg_float, default=50.0)
    ct.add_argument("--output-mode", choices=("original+tail", "tail-only"), default="original+tail",
                    help="only affects TextGrid/metadata coordinates; Praat assembles the output")
    ct.add_argument("--tail-level", choices=("phrase", "ending"), default="phrase",
                    help="phrase = settle at the phrase's median active level (rising from the "
                         "join level over 0.3 s); ending = stay at the level of the source's end")
    ct.add_argument("--normalize", choices=("off", "peak", "loudness"), default="off",
                    help="loudness = match the tail body to the phrase's active loudness and cap "
                         "its peaks at the source peak (Praat then scales both together)")
    ct.add_argument("--trim-silence", type=int, default=1,
                    help="1 = cut CLEARLY silent trailing material before joining (conservative)")
    ct.add_argument("--seed", type=int, default=1234)
    ct.add_argument("--metadata", default=None)
    ct.add_argument("--textgrid", default=None)
    ct.add_argument("--rebuild-graph", type=int, default=0)
    ct.set_defaults(func=continuation_tail)

    pl = sub.add_parser("polyphonic-layers", parents=[common],
                        help="generate 1-3 sample-aligned corpus voices that coexist with a phrase "
                             "(voices written as float WAV; the stereo mix is built in Praat)")
    pl.add_argument("--input", required=True, help="mono source WAV exported by Praat (32-bit PCM)")
    pl.add_argument("--index", required=True, help="EXISTING corpus index prefix")
    pl.add_argument("--output-dir", required=True, help="temporary working directory for the voice WAVs")
    pl.add_argument("--run-tag", required=True, help="unique run identifier used in the voice file names")
    pl.add_argument("--voices", type=int, default=2)
    pl.add_argument("--relationship", choices=POLY_RELATIONSHIPS, default="parallel")
    pl.add_argument("--relationship-strength", type=float, default=75.0, help="0..100")
    pl.add_argument("--inter-voice-diversity", type=float, default=50.0, help="0..100")
    pl.add_argument("--seed", type=int, default=1234)
    pl.add_argument("--refine", type=int, default=1,
                    help="1 = refinement sweep (each voice re-planned against all others, kept only if "
                         "cheaper); 0 = strictly sequential, voice 1 independent of the voice count")
    pl.add_argument("--level-mode", choices=("match", "corpus"), default="match",
                    help="match = voices matched to the source's active RMS + --voice-level-db")
    pl.add_argument("--voice-level-db", type=float, default=-6.0)
    pl.add_argument("--pan-mode", choices=("auto", "manual"), default="auto")
    pl.add_argument("--pan-1", type=float, default=-60.0)
    pl.add_argument("--pan-2", type=float, default=60.0)
    pl.add_argument("--pan-3", type=float, default=0.0)
    pl.add_argument("--normalize-mix", type=int, default=1)
    pl.add_argument("--mix-target-db", type=float, default=-1.0)
    pl.add_argument("--output-mode", choices=("mix", "voices", "both"), default="both",
                    help="recorded in metadata; Praat assembles the objects")
    pl.add_argument("--export-dir", default=None, help="write aligned 32-bit float DAW stems here")
    pl.add_argument("--export-name", default=None, help="base name of the stems (the Sound's name)")
    pl.add_argument("--export-mix", type=int, default=1, help="also export the normalised stereo mix")
    pl.add_argument("--metadata", default=None)
    pl.add_argument("--textgrid", default=None)
    pl.add_argument("--result", default=None, help="key/value result read by Praat")
    pl.set_defaults(func=polyphonic_layers)

    cg = sub.add_parser("continuation-graph", parents=[common],
                        help="build/validate the continuation transition graph only")
    cg.add_argument("--index", required=True)
    cg.add_argument("--rebuild", type=int, default=0)
    cg.set_defaults(func=continuation_graph_cmd)

    # v1.8.1: open the log BEFORE parsing, so a command-line error (e.g. an
    # argument the caller's platform dropped) reaches the log Praat shows,
    # instead of failing silently.
    # Under GUI Praat on Windows a plain runSubprocess gives the child NO
    # stdout (sys.stdout is None), so every final status print crashed with
    # AttributeError after the real work. Give such streams a null sink.
    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w")
    # v1.8.3: "@file" arguments are expanded from a file with one argument per
    # line. On a reported Windows machine the child received only the first
    # 1024 characters of its command line, silently cutting --result/--log;
    # an argument file keeps the command line short whatever the paths are.
    sys.argv = _expand_arg_files(sys.argv)
    log_pre = None
    for i, a in enumerate(sys.argv):
        if a == "--log" and i + 1 < len(sys.argv):
            log_pre = sys.argv[i + 1]
        elif a.startswith("--log="):
            log_pre = a[6:]
    _install_log_tee(log_pre if log_pre not in (None, "", "-") else None)
    args = p.parse_args()
    # "-" = "no file" for optional paths. Praat sends "-" rather than an empty
    # string, because Windows drops empty arguments from the command line.
    for k in _OPTIONAL_PATH_ARGS:
        if getattr(args, k, None) == "-":
            setattr(args, k, None)
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
