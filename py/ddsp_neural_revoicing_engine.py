"""
ddsp_neural_revoicing_engine.py — DDSP Neural Revoicing engine
Version: 0.12 (2026)

Part of Praat AudioTools plugin.
Author: Shai Cohen, Department of Music, Bar-Ilan University.
License: MIT.

Called by DDSPNeuralRevoicing.praat — not run directly.

Changelog v0.12:
  - Added note-gap deepening (--gap_depth, default 0/off): deepens inter-note
    loudness valleys so sustained models (Trumpet, Tenor_Saxophone) stop
    slurring across short staccato gaps. Keys on the loudness drop below a
    local peak, so it catches SHORT gaps without touching loud sustained
    notes. Try 15-25 dB for staccato material.

Changelog v0.11:
  - Confidence gate reworked so it no longer distorts the amplitude curve:
    gates only SUSTAINED, low-loudness, low-confidence runs (genuine note-off
    tails) with tapered edges, instead of hard-silencing every isolated
    low-confidence frame (which punched dips into the envelope mid-note).

Changelog v0.10:
  - Output level control (--output_level, default match_input): DDSP renders
    quiet, so the output is now scaled to the source's RMS (peak-guarded, no
    clipping). Options: match_input / peak (~0.95) / raw. Pure post gain.

Changelog v0.9:
  - Output can match the input sample rate (--match_input_rate, default 1):
    the 16 kHz synthesis is resampled up (scipy polyphase) so files drop into
    44.1/48 kHz sessions. Honest about it: stats report output_sample_rate
    AND synthesis_rate (16000), since no content above ~8 kHz is added.

Changelog v0.8:
  - Added a CREPE-confidence gate (--confidence_gate, default 0.15, ON):
    frames where the pitch tracker is unsure are silenced, fixing the
    'pitch wanders at the note tail' artifact at its source. Set 0 to disable.

Changelog v0.7:
  - Python 3.10+ compatibility shim added before any DDSP import: restores
    collections.Iterable / Mapping / etc. (removed in 3.10, moved to
    collections.abc) so DDSP 1.6.5's older code runs. Fixes
    "module 'collections' has no attribute 'Iterable'" at model build.

Changelog v0.6:
  - Dependency check reports the EXACT missing module (e.g. google.auth) with
    a pip hint, instead of collapsing every google.* failure to
    'google-cloud-storage' — a missing sub-dependency no longer masquerades as
    its parent package.

Changelog v0.5:
  - Dependency check maps common DDSP sub-imports to their real pip names
    (google-cloud-storage, tensorflow-datasets/-addons/-probability, future),
    so the Praat log tells you exactly what to 'pip install' into the venv.

Changelog v0.4:
  - Dependency check now exercises ddsp.training and reports the actual
    missing sub-package by name (e.g. cloudml-hypertune, which DDSP imports
    unconditionally via ddsp.training.cloud even though it is cloud-training
    only) instead of crashing mid-run.

Changelog v0.3:
  - Model fetch over plain HTTPS (GCS JSON list + object download), so it no
    longer needs the gs:// filesystem plugin (tensorflow-io-gcs-filesystem).
    Fixes "File system scheme 'gs' not implemented" on TF builds without GCS.
    Falls back to known-filename fetch if bucket listing is disallowed.

Changelog v0.2:
  - Model fetch fixed. The pretrained checkpoints are a GCS *folder*
    (solo_<model>_ckpt), not a per-model .zip; the old urlretrieve('.zip')
    always 404'd. Now copied with tf.io.gfile from the public bucket (no
    gsutil needed). Base path overridable via DDSP_GCS_CKPT_BASE.

What it does
------------
Renders an input sound through a *pretrained* Magenta DDSP timbre-transfer
model (Violin, Flute, Flute2, Trumpet, Tenor_Saxophone). It preserves the
input's pitch contour and loudness gesture and re-renders them with the chosen
model. This is NEURAL REVOICING / DDSP timbre transfer — it is NOT literal
instrument conversion and NOT guaranteed-natural timbre. Output is stylized and
works best on clean MONOPHONIC input; polyphonic/noisy material is unstable.

Nothing is trained here. Inference runs locally after the model is downloaded
once (then cached). No web service is used for inference. No Colab required.

Pipeline (Magenta DDSP timbre-transfer flow)
--------------------------------------------
  input wav -> mono -> resample 16 kHz
            -> extract f0 (CREPE) + loudness (A-weighted, DDSP)
            -> adjust: pitch_shift (octaves), loudness_shift (dB),
                       autotune (snap f0 toward chromatic grid),
                       quiet (attenuate below note-on threshold)
            -> pretrained DDSP Autoencoder(features) -> audio
            -> write output wav + stats txt

Honesty
-------
  * The five targets are the standard DDSP timbre-transfer checkpoints.
  * "autotune" really is pitch snapping toward the chromatic grid (0..1).
  * "quiet" really attenuates loudness in below-threshold (note-off) regions.
  * "threshold" is the note-on loudness gate in dB below the loudness peak.
  * If TensorFlow / ddsp / crepe / a model are missing, a clear message is
    printed to stderr AND written into the stats file; the run fails cleanly.
"""

import argparse
import os
import sys
import math
import shutil
import zipfile
import traceback

# --- Python 3.10+ compatibility shim (MUST run before importing ddsp) -------
# DDSP 1.6.5 predates Python 3.10 and still references collections.Iterable etc.
# Those aliases were removed from `collections` in 3.10 (moved to
# collections.abc). Restore them process-wide so DDSP's older code imports and
# runs. Harmless on older Pythons (the attributes already exist).
import collections
import collections.abc as _collections_abc
for _abc_name in ("Iterable", "Mapping", "MutableMapping", "Sequence",
                  "MutableSequence", "Set", "MutableSet", "Callable",
                  "Hashable", "Container", "Sized", "Iterator", "Generator",
                  "Reversible", "Collection", "ByteString", "KeysView",
                  "ItemsView", "ValuesView", "MappingView", "Awaitable",
                  "Coroutine", "AsyncIterable", "AsyncIterator",
                  "AsyncGenerator"):
    if not hasattr(collections, _abc_name) and hasattr(_collections_abc, _abc_name):
        setattr(collections, _abc_name, getattr(_collections_abc, _abc_name))
# ---------------------------------------------------------------------------

# Heavy imports (numpy/tensorflow/ddsp/crepe) are done lazily inside functions so
# that check_dependencies() and stats-writing still work when they are missing.

VERSION = "0.3"
DDSP_SAMPLE_RATE = 16000
MODELS = ["Violin", "Flute", "Flute2", "Trumpet", "Tenor_Saxophone"]

# Pretrained checkpoints as used by Magenta's DDSP timbre-transfer Colab.
# IMPORTANT: the Colab does NOT download a per-model .zip — it copies a FOLDER
# of checkpoint files (operative_config-0.gin, checkpoint, ckpt-N.index,
# ckpt-N.data-*) named  solo_<model_lowercase>_ckpt  from this PUBLIC GCS
# bucket (via gsutil). We do the same with tf.io.gfile — TensorFlow is already
# a dependency, so no gsutil/gcloud is needed and public objects need no auth.
# Override the base with the DDSP_GCS_CKPT_BASE env var if the path ever moves.
GCS_CKPT_BASE = os.environ.get(
    "DDSP_GCS_CKPT_BASE",
    "gs://ddsp/models/timbre_transfer_colab/2021-01-06")

_LOG_PATH = None  # set from --log; log() tees here so the Praat front-end can show it


def log(msg):
    """Everything user-facing goes to stderr so the Praat front-end can show it.
    Also tee to the --log file, since runSubprocess has no shell and cannot
    redirect stderr itself (stdout is kept clean)."""
    line = str(msg) + "\n"
    sys.stderr.write(line)
    sys.stderr.flush()
    if _LOG_PATH:
        try:
            with open(_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
def check_dependencies():
    """Return a list of missing pip package names (empty = all present).

    We exercise `ddsp.training` (what the engine actually uses), and if it fails
    on a sub-dependency that DDSP imports unconditionally even for inference
    (notably `hypertune` = cloudml-hypertune, cloud-training only), we report
    that package by name — turning a mid-run crash into a clear message."""
    missing = []
    for mod, pip_name in [("numpy", "numpy"),
                          ("soundfile", "soundfile"),
                          ("tensorflow", "tensorflow"),
                          ("crepe", "crepe"),
                          ("gin", "gin-config")]:
        try:
            __import__(mod)
        except Exception:
            if pip_name not in missing:
                missing.append(pip_name)

    # ddsp + its (sometimes-missing) sub-imports. Map known ones to pip names.
    # module (exact or longest-prefix) -> pip package hint
    pip_for = {"hypertune": "cloudml-hypertune",
               "google.cloud.storage": "google-cloud-storage",
               "google.cloud": "google-cloud-core",
               "google.auth": "google-auth",
               "google.api_core": "google-api-core",
               "google.resumable_media": "google-resumable-media",
               "google": "google-cloud-storage",
               "tensorflow_datasets": "tensorflow-datasets",
               "tensorflow_addons": "tensorflow-addons",
               "tensorflow_probability": "tensorflow-probability",
               "future": "future", "ddsp": "ddsp"}
    try:
        __import__("ddsp.training")
    except ModuleNotFoundError as e:
        # Report the EXACT missing module (not a collapsed root) so a missing
        # sub-dependency doesn't masquerade as its parent package. Add a pip
        # hint via the longest known prefix.
        name = getattr(e, "name", "") or "ddsp"
        pip = None
        parts = name.split(".")
        for i in range(len(parts), 0, -1):
            cand = ".".join(parts[:i])
            if cand in pip_for:
                pip = pip_for[cand]
                break
        pip = pip or parts[0]
        item = "%s  ->  pip install %s" % (name, pip)
        if item not in missing:
            missing.append(item)
    except Exception as e:
        item = "ddsp.training import failed: %s" % e
        if item not in missing:
            missing.append(item)
    return missing


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------
STATS_KEYS = [
    "status", "version", "model",
    "input", "output",
    "input_duration_s", "output_duration_s",
    "input_sample_rate", "output_sample_rate", "synthesis_rate",
    "output_level_mode", "output_rms", "output_peak",
    "threshold", "pitch_shift", "loudness_shift", "autotune", "quiet",
    "confidence_gate", "gap_depth",
    "model_cache_path", "model_source",
    "warnings",
]


def write_stats(path, d):
    """Write key=value lines in a stable order (Praat reads this back)."""
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as f:
            for k in STATS_KEYS:
                v = d.get(k, "")
                if v is None:
                    v = ""
                f.write("%s=%s\n" % (k, v))
    except Exception as e:
        log("WARNING: could not write stats file: %s" % e)


# ---------------------------------------------------------------------------
# Cache / model resolution
# ---------------------------------------------------------------------------
def resolve_cache_dir(cache_dir):
    """Stable cache under the plugin/preferences folder (passed from Praat).
    Falls back to ~/.praat_audiotools/ddsp_cache if nothing was given."""
    if not cache_dir:
        cache_dir = os.path.join(os.path.expanduser("~"),
                                 ".praat_audiotools", "ddsp_cache")
    cache_dir = os.path.abspath(cache_dir)
    os.makedirs(cache_dir, exist_ok=True)
    os.makedirs(os.path.join(cache_dir, "models"), exist_ok=True)
    return cache_dir


def _has_checkpoint(model_dir):
    """A usable DDSP checkpoint folder has a gin config + a TF checkpoint."""
    if not os.path.isdir(model_dir):
        return False
    has_gin = any(fn.endswith(".gin") for fn in os.listdir(model_dir))
    has_ckpt = os.path.exists(os.path.join(model_dir, "checkpoint")) or \
        any(fn.startswith("ckpt") for fn in os.listdir(model_dir))
    return has_gin and has_ckpt


def _parse_gcs_base(base):
    """gs://bucket/some/prefix -> ('bucket', 'some/prefix')."""
    b = base[5:] if base.startswith("gs://") else base
    if "/" in b:
        return b.split("/", 1)[0], b.split("/", 1)[1]
    return b, ""


def _gcs_object_url(bucket, name):
    import urllib.parse
    return "https://storage.googleapis.com/%s/%s" % (
        bucket, urllib.parse.quote(name, safe="/"))


def _gcs_list_https(bucket, prefix, timeout=60):
    """List object names under a prefix via GCS's public JSON API (paginated).
    Works over plain HTTPS — no gs:// filesystem plugin needed."""
    import urllib.request, urllib.parse, json
    names = []
    token = None
    while True:
        q = {"prefix": prefix}
        if token:
            q["pageToken"] = token
        url = "https://storage.googleapis.com/storage/v1/b/%s/o?%s" % (
            bucket, urllib.parse.urlencode(q))
        with urllib.request.urlopen(url, timeout=timeout) as r:
            data = json.load(r)
        for it in data.get("items", []):
            names.append(it["name"])
        token = data.get("nextPageToken")
        if not token:
            break
    return names


def _gcs_download(bucket, name, dst, timeout=300):
    import urllib.request
    req = urllib.request.Request(_gcs_object_url(bucket, name))
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dst, "wb") as f:
        shutil.copyfileobj(r, f)


def ensure_model(model, cache_dir):
    """Return (model_dir, source) where source is 'cache' or 'download'.

    (1) use a cached / manually-placed checkpoint if present; else (2) fetch the
    pretrained checkpoint FOLDER (solo_<model>_ckpt: .gin + checkpoint + ckpt-*
    shards) over plain HTTPS from the public GCS bucket — no gs:// filesystem
    plugin required. Tries a folder listing first; if listing is disallowed,
    falls back to fetching the known filenames (reading the 'checkpoint' pointer
    to learn the ckpt-N name). Raises RuntimeError with copy-paste fixes if it
    cannot get a usable checkpoint."""
    model_dir = os.path.join(cache_dir, "models", model)
    if _has_checkpoint(model_dir):
        return model_dir, "cache"

    bucket, base_prefix = _parse_gcs_base(GCS_CKPT_BASE)
    folder = "solo_%s_ckpt" % model.lower()
    prefix = (base_prefix.rstrip("/") + "/" + folder + "/").lstrip("/")
    log("Model '%s' not in cache. Fetching over HTTPS:\n  bucket=%s  prefix=%s"
        % (model, bucket, prefix))
    os.makedirs(model_dir, exist_ok=True)
    errors = []

    # (1) List the folder, download every object.
    try:
        names = _gcs_list_https(bucket, prefix)
        for name in names:
            fn = os.path.basename(name.rstrip("/"))
            if not fn:
                continue
            _gcs_download(bucket, name, os.path.join(model_dir, fn))
        if _has_checkpoint(model_dir):
            return model_dir, "download"
    except Exception as e:
        errors.append("listing: %s" % e)

    # (2) Fallback: fetch by KNOWN names (no listing permission needed). Read the
    # 'checkpoint' pointer file to discover the ckpt-N shard names.
    try:
        import urllib.request, re as _re
        for gin_name in ("operative_config-0.gin", "operative_config-0.0.gin"):
            try:
                _gcs_download(bucket, prefix + gin_name,
                              os.path.join(model_dir, gin_name))
                break
            except Exception:
                continue
        with urllib.request.urlopen(_gcs_object_url(bucket, prefix + "checkpoint"),
                                    timeout=60) as r:
            ckpt_txt = r.read().decode("utf-8", "ignore")
        with open(os.path.join(model_dir, "checkpoint"), "w") as f:
            f.write(ckpt_txt)
        m = _re.search(r'model_checkpoint_path:\s*"([^"]+)"', ckpt_txt)
        if m:
            ckpt = os.path.basename(m.group(1))
            for suffix in (".index", ".data-00000-of-00001"):
                _gcs_download(bucket, prefix + ckpt + suffix,
                              os.path.join(model_dir, ckpt + suffix))
        if _has_checkpoint(model_dir):
            return model_dir, "download"
    except Exception as e:
        errors.append("known-names: %s" % e)

    raise RuntimeError(
        "Could not fetch the pretrained '%s' checkpoint over HTTPS.\n"
        "  bucket=%s  prefix=%s\n"
        "  errors: %s\n"
        "  Options:\n"
        "  (A) Enable gs:// in your TF env, then re-run:\n"
        "        pip install tensorflow-io-gcs-filesystem\n"
        "  (B) Download the folder yourself and drop the files into:\n"
        "        %s\n"
        "      e.g. with gsutil / gcloud:\n"
        "        gsutil -m cp \"%s/solo_%s_ckpt/*\" \"%s\"\n"
        "      (the folder holds a .gin config, a 'checkpoint' file, and\n"
        "       ckpt-*.index / ckpt-*.data files).\n"
        "  If the bucket path has moved, set env var DDSP_GCS_CKPT_BASE to the\n"
        "  current base and re-run."
        % (model, bucket, prefix, " | ".join(errors) or "unknown",
           model_dir, GCS_CKPT_BASE, model.lower(), model_dir))


# ---------------------------------------------------------------------------
# Audio I/O
# ---------------------------------------------------------------------------
def load_audio_mono_16k(path):
    """Load -> mono -> 16 kHz float32. Returns (audio[1,N], orig_sr, orig_dur)."""
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(path, always_2d=True)
    orig_sr = int(sr)
    orig_dur = audio.shape[0] / float(sr)
    mono = audio.mean(axis=1).astype("float32")   # force mono
    if orig_sr != DDSP_SAMPLE_RATE:
        mono = _resample_linear(mono, orig_sr, DDSP_SAMPLE_RATE)
    return mono[np.newaxis, :], orig_sr, orig_dur


def _resample_linear(x, sr_in, sr_out):
    """Dependency-light linear resample (DDSP only needs 16 kHz mono in)."""
    import numpy as np
    if sr_in == sr_out or len(x) == 0:
        return x.astype("float32")
    n_out = int(round(len(x) * sr_out / float(sr_in)))
    if n_out < 1:
        n_out = 1
    xp = np.linspace(0.0, 1.0, num=len(x), endpoint=False)
    xq = np.linspace(0.0, 1.0, num=n_out, endpoint=False)
    return np.interp(xq, xp, x).astype("float32")


def _resample_to_rate(audio, sr_in, sr_out):
    """Resample the finished 1-D output. Prefers scipy's polyphase resampler
    (a ddsp dependency, so it is present); falls back to linear."""
    import numpy as np
    audio = np.asarray(audio).reshape(-1)
    if sr_in == sr_out or audio.size == 0:
        return audio.astype("float32")
    try:
        from math import gcd
        from scipy.signal import resample_poly
        g = gcd(int(sr_in), int(sr_out))
        return resample_poly(audio, int(sr_out) // g, int(sr_in) // g).astype("float32")
    except Exception:
        return _resample_linear(audio, sr_in, sr_out)


def _apply_output_level(audio, mode, input_rms):
    """Post-synthesis level (pure gain; does not alter the neural character).

      match_input : scale RMS to the source's RMS, then peak-guard to <=0.99 so
                    it can never clip (a peaky source may land a touch under the
                    exact input RMS, but never over 0 dBFS).
      peak        : scale so the loudest sample is ~0.95.
      raw         : leave the model's native (quiet) level untouched.

    Returns (audio, out_rms, out_peak)."""
    import numpy as np
    a = np.asarray(audio, dtype="float64").reshape(-1)
    peak = float(np.max(np.abs(a))) if a.size else 0.0
    if peak < 1e-9:
        return a.astype("float32"), 0.0, 0.0
    if mode == "raw":
        pass
    elif mode == "peak":
        a = a * (0.95 / peak)
    else:  # match_input
        cur = float(np.sqrt(np.mean(a ** 2)))
        if cur > 1e-9 and input_rms > 0:
            a = a * (input_rms / cur)
        p = float(np.max(np.abs(a)))
        if p > 0.99:
            a = a * (0.99 / p)
    return (a.astype("float32"),
            float(np.sqrt(np.mean(a ** 2))),
            float(np.max(np.abs(a))))


# ---------------------------------------------------------------------------
# Feature extraction + conditioning adjustments (DDSP style)
# ---------------------------------------------------------------------------
def extract_features(audio):
    """CREPE f0 + DDSP A-weighted loudness, at the DDSP frame rate."""
    import ddsp
    import ddsp.training
    feats = ddsp.training.metrics.compute_audio_features(audio[0])
    feats["loudness_db"] = feats["loudness_db"].astype("float32")
    feats["audio"] = audio.astype("float32")
    return feats


def _hz_to_midi(f0_hz):
    import numpy as np
    f0_hz = np.asarray(f0_hz, dtype="float64")
    midi = np.zeros_like(f0_hz)
    nz = f0_hz > 0
    midi[nz] = 69.0 + 12.0 * np.log2(f0_hz[nz] / 440.0)
    return midi


def _midi_to_hz(midi):
    import numpy as np
    return 440.0 * (2.0 ** ((np.asarray(midi, dtype="float64") - 69.0) / 12.0))


def _sustained_runs(mask, min_run):
    """Zero out True-runs shorter than min_run frames, so isolated low-
    confidence wobbles don't gate a note that is still sounding."""
    import numpy as np
    m = np.asarray(mask).copy()
    n = m.shape[0]
    i = 0
    while i < n:
        if m[i]:
            j = i
            while j < n and m[j]:
                j += 1
            if (j - i) < min_run:
                m[i:j] = False
            i = j
        else:
            i += 1
    return m


def _smooth_ramp(x, ramp):
    """Moving-average smoothing to soften gate edges (avoids stair-stepping the
    envelope and clicks). ramp is in frames. Edge-padded so the boundaries are
    NOT pulled down (zero-padding would spuriously gate the first/last frames)."""
    import numpy as np
    x = np.asarray(x, dtype="float64")
    r = int(ramp)
    if r < 2 or x.size < r:
        return x
    xp = np.pad(x, r, mode="edge")
    k = np.ones(r) / float(r)
    sm = np.convolve(xp, k, mode="same")
    return sm[r:-r]


def _deepen_gaps(ld, gap_depth_db, frame_rate=250):
    """Deepen inter-note loudness valleys (staccato gaps) so sustained models
    (trumpet / sax) don't bridge them into a legato slur. Keys on the loudness
    DROP below a local running peak, so it (a) catches SHORT gaps the sustained
    confidence gate misses and (b) never touches loud sustained notes (they sit
    at the local peak, so their weight is 0 -> no mid-note holes). Tapered, so
    no hard edges."""
    import numpy as np
    ld = np.asarray(ld, dtype="float64")
    if gap_depth_db <= 0.0 or ld.size == 0:
        return ld
    try:
        from scipy.ndimage import maximum_filter1d
        win = max(3, int(0.15 * frame_rate))          # ~150 ms local peak
        local_max = maximum_filter1d(ld, size=win, mode="nearest")
    except Exception:
        return ld                                     # no scipy -> leave as-is
    below = local_max - ld                            # dB below the local peak
    # weight ramps 0 -> 1 as we fall 4 -> 12 dB below the local peak, so loud
    # notes (near the peak) are untouched and only real gaps are deepened.
    w = np.clip((below - 4.0) / 8.0, 0.0, 1.0)
    return ld - w * float(gap_depth_db)


def adjust_features(feats, pitch_shift, loudness_shift, autotune, quiet,
                    threshold, confidence_gate=0.0, gap_depth=0.0):
    """Apply the honest conditioning knobs.

      pitch_shift     : octaves (f0 *= 2**octaves)
      loudness_shift  : dB added to loudness
      autotune        : 0..1, snap f0 toward the nearest chromatic semitone
      quiet           : dB of attenuation applied in note-OFF regions
      threshold       : note-on gate, dB below the loudness peak
      confidence_gate : 0..1 CREPE-confidence floor. Frames where the pitch
                        tracker is less confident than this are forced to
                        note-off (silenced), so DDSP does not render a wandering
                        phantom pitch on unvoiced/decaying tails. 0 disables it.
    """
    import numpy as np
    out = {k: (v.copy() if hasattr(v, "copy") else v) for k, v in feats.items()}
    f0 = np.asarray(out["f0_hz"], dtype="float64").copy()
    ld = np.asarray(out["loudness_db"], dtype="float64").copy()

    # Pitch shift in octaves
    if abs(pitch_shift) > 1e-9:
        f0 = f0 * (2.0 ** float(pitch_shift))

    # Auto-tune: pull f0 toward its nearest semitone by `autotune` (0..1)
    if autotune > 1e-9:
        midi = _hz_to_midi(f0)
        snapped = np.round(midi)
        voiced = f0 > 0
        midi[voiced] = (1.0 - autotune) * midi[voiced] + autotune * snapped[voiced]
        f0 = np.where(voiced, _midi_to_hz(midi), f0)

    # Loudness shift in dB
    if abs(loudness_shift) > 1e-9:
        ld = ld + float(loudness_shift)

    # Quiet: note-on gate `threshold` dB below the peak; attenuate note-off
    # regions by `quiet` dB (leaves note-on gestures intact).
    if quiet > 1e-9:
        peak = float(np.max(ld)) if ld.size else 0.0
        note_off = ld < (peak - float(threshold))
        ld[note_off] = ld[note_off] - float(quiet)

    # Confidence gate: silence only GENUINE note-off regions (decaying tails /
    # gaps), without carving dips into the amplitude curve mid-note. A frame is
    # gated only if it is (a) low-confidence AND (b) already quiet (below the
    # note-on threshold) AND (c) part of a sustained run (isolated confidence
    # wobbles are ignored). Edges are tapered so the envelope isn't stair-
    # stepped and no clicks appear.
    conf = out.get("f0_confidence", None)
    if confidence_gate > 1e-9 and conf is not None:
        conf = np.asarray(conf, dtype="float64").reshape(-1)
        if conf.shape[0] == ld.shape[0] and ld.size:
            peak = float(np.max(ld))
            low_conf = conf < float(confidence_gate)
            not_loud = ld < (peak - 6.0)        # never gate within 6 dB of peak
            off = low_conf & not_loud
            off = _sustained_runs(off, min_run=12)         # ~50 ms at 250 fps
            gate_on = _smooth_ramp((~off).astype("float64"), ramp=8)  # ~32 ms
            floor = float(np.min(ld)) - 30.0
            # crossfade loudness toward the floor only inside sustained note-off
            ld = gate_on * ld + (1.0 - gate_on) * floor

    # Note-gap deepening (staccato preservation for sustained models).
    if gap_depth > 1e-9:
        ld = _deepen_gaps(ld, gap_depth)

    out["f0_hz"] = f0.astype("float32")
    out["loudness_db"] = ld.astype("float32")
    return out


# ---------------------------------------------------------------------------
# Model inference
# ---------------------------------------------------------------------------
def _find_gin(model_dir):
    for fn in os.listdir(model_dir):
        if fn.endswith(".gin"):
            return os.path.join(model_dir, fn)
    raise RuntimeError("No .gin operative config found in %s" % model_dir)


def run_model(model_dir, feats):
    """Restore the pretrained Autoencoder and render audio, matching the model's
    training hop so f0/loudness/audio line up (per the DDSP timbre-transfer
    Colab)."""
    import numpy as np
    import ddsp
    import ddsp.training
    import gin

    gin_file = _find_gin(model_dir)
    with gin.unlock_config():
        gin.parse_config_file(gin_file, skip_unknown=True)

    # Match the model's training hop so time_steps/n_samples are consistent.
    try:
        time_steps_train = int(gin.query_parameter("F0LoudnessPreprocessor.time_steps"))
        n_samples_train = int(gin.query_parameter("Harmonic.n_samples"))
    except Exception:
        time_steps_train = 1000
        n_samples_train = 64000
    hop_size = int(n_samples_train / time_steps_train)

    n_audio = int(feats["audio"].shape[1])
    time_steps = int(n_audio / hop_size)
    n_samples = time_steps * hop_size

    gin_params = [
        "Harmonic.n_samples = %d" % n_samples,
        "FilteredNoise.n_samples = %d" % n_samples,
        "F0LoudnessPreprocessor.time_steps = %d" % time_steps,
        "oscillator_bank.use_angular_cumsum = True",
    ]
    with gin.unlock_config():
        gin.parse_config(gin_params)

    # Trim features to the aligned length.
    feats = dict(feats)
    for key in ("f0_hz", "f0_confidence", "loudness_db"):
        if key in feats:
            feats[key] = feats[key][:time_steps]
    feats["audio"] = feats["audio"][:, :n_samples]

    model = ddsp.training.models.Autoencoder()
    model.restore(model_dir)

    outputs = model(feats, training=False)
    audio_gen = model.get_audio_from_outputs(outputs)
    audio_gen = np.asarray(audio_gen).reshape(-1).astype("float32")
    return audio_gen


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(
        description="DDSP Neural Revoicing engine (Praat AudioTools).")
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--stats", required=True)
    p.add_argument("--model", default="Violin", choices=MODELS)
    p.add_argument("--threshold", type=float, default=30.0,
                   help="note-on gate, dB below the loudness peak")
    p.add_argument("--pitch_shift", type=float, default=0.0,
                   help="octaves")
    p.add_argument("--loudness_shift", type=float, default=0.0,
                   help="dB")
    p.add_argument("--autotune", type=float, default=0.0,
                   help="0..1 snap toward chromatic grid")
    p.add_argument("--quiet", type=float, default=0.0,
                   help="dB of attenuation in note-off regions")
    p.add_argument("--confidence_gate", type=float, default=0.15,
                   help="0..1 CREPE-confidence floor; frames below it are "
                        "silenced (fixes wandering pitch on decaying tails). "
                        "0 disables.")
    p.add_argument("--gap_depth", type=float, default=0.0,
                   help="dB to deepen inter-note loudness gaps (staccato "
                        "preservation). Helps sustained models (Trumpet, "
                        "Tenor_Saxophone) stop slurring across short gaps. "
                        "0 disables; try 15-25 for staccato.")
    p.add_argument("--match_input_rate", type=int, default=1,
                   help="1 = resample the 16 kHz output up to the input rate "
                        "so it lines up with your session (no new highs); "
                        "0 = leave it at the model's native 16 kHz.")
    p.add_argument("--output_level", default="match_input",
                   choices=["match_input", "peak", "raw"],
                   help="post-synthesis level: match the source RMS (default), "
                        "peak-normalize to ~0.95, or leave raw.")
    p.add_argument("--cache_dir", default="")
    p.add_argument("--keep_temp", type=int, default=0)
    p.add_argument("--log", default="",
                   help="optional path; stderr diagnostics are teed here for "
                        "the Praat front-end")
    return p.parse_args()


def main():
    args = parse_args()

    global _LOG_PATH
    if args.log:
        _LOG_PATH = args.log
    stats = {
        "status": "FAILURE",
        "version": VERSION,
        "model": args.model,
        "input": args.input,
        "output": args.output,
        "threshold": args.threshold,
        "pitch_shift": args.pitch_shift,
        "loudness_shift": args.loudness_shift,
        "autotune": args.autotune,
        "quiet": args.quiet,
        "confidence_gate": args.confidence_gate,
        "gap_depth": args.gap_depth,
        "warnings": "",
    }
    warnings = []

    # ---- dependencies ----
    missing = check_dependencies()
    if missing:
        msg = ("Missing Python packages (install each into the SAME venv Praat "
               "uses):\n  - " + "\n  - ".join(missing) +
               "\n(TensorFlow + ddsp are required for neural revoicing. If a "
               "package is already installed, it went into a different Python.)")
        log("ERROR: " + msg)
        stats["warnings"] = "missing_dependencies: " + " ; ".join(missing)
        write_stats(args.stats, stats)
        sys.exit(2)

    if not os.path.isfile(args.input):
        log("ERROR: input file not found: %s" % args.input)
        stats["warnings"] = "input_not_found"
        write_stats(args.stats, stats)
        sys.exit(2)

    try:
        import soundfile as sf

        cache_dir = resolve_cache_dir(args.cache_dir)
        stats["model_cache_path"] = os.path.join(cache_dir, "models", args.model)

        # ---- model ----
        model_dir, source = ensure_model(args.model, cache_dir)
        stats["model_source"] = source
        stats["model_cache_path"] = model_dir
        log("Model ready (%s): %s" % (source, model_dir))

        # ---- audio ----
        audio, orig_sr, orig_dur = load_audio_mono_16k(args.input)
        import numpy as np
        input_rms = float(np.sqrt(np.mean(np.asarray(audio, dtype="float64") ** 2)))
        stats["input_sample_rate"] = orig_sr
        stats["input_duration_s"] = round(orig_dur, 4)
        if orig_dur < 0.25:
            warnings.append("input_very_short")

        # ---- features + conditioning ----
        log("Extracting f0 (CREPE) + loudness...")
        feats = extract_features(audio)
        feats = adjust_features(feats,
                                pitch_shift=args.pitch_shift,
                                loudness_shift=args.loudness_shift,
                                autotune=args.autotune,
                                quiet=args.quiet,
                                threshold=args.threshold,
                                confidence_gate=args.confidence_gate,
                                gap_depth=args.gap_depth)

        # ---- inference ----
        log("Running pretrained DDSP model '%s'..." % args.model)
        audio_out = run_model(model_dir, feats)

        # ---- optional resample to the input's rate ----
        # The model synthesizes at 16 kHz (its trained rate) — that is the true
        # bandwidth ceiling. Resampling up to the input rate only changes the
        # file's container rate so it lines up with a 44.1/48 kHz session; it
        # does NOT add any content above ~8 kHz. We report both rates in stats
        # so this stays honest.
        out_rate = DDSP_SAMPLE_RATE
        if args.match_input_rate and orig_sr and int(orig_sr) != DDSP_SAMPLE_RATE:
            audio_out = _resample_to_rate(audio_out, DDSP_SAMPLE_RATE, int(orig_sr))
            out_rate = int(orig_sr)

        # ---- output level ----
        # DDSP synthesizes at its own (quiet) internal level. Bring it to a
        # usable level per the chosen mode. This is a pure post-synthesis gain;
        # it does not touch the neural character. 'match_input' scales RMS to
        # the source and is peak-guarded so it can never clip.
        audio_out, out_rms, out_peak = _apply_output_level(
            audio_out, args.output_level, input_rms)
        stats["output_level_mode"] = args.output_level
        stats["output_rms"] = round(out_rms, 5)
        stats["output_peak"] = round(out_peak, 5)

        # ---- write ----
        sf.write(args.output, audio_out, out_rate)
        out_dur = len(audio_out) / float(out_rate)
        stats["output_sample_rate"] = out_rate
        stats["synthesis_rate"] = DDSP_SAMPLE_RATE
        stats["output_duration_s"] = round(out_dur, 4)
        stats["status"] = "SUCCESS"
        stats["warnings"] = ";".join(warnings)
        write_stats(args.stats, stats)
        log("Done -> %s (%.2fs @ %d Hz; synthesized at %d Hz)"
            % (args.output, out_dur, out_rate, DDSP_SAMPLE_RATE))

    except Exception as e:
        tb = traceback.format_exc()
        log("ERROR during revoicing:\n" + tb)
        stats["status"] = "FAILURE"
        stats["warnings"] = (";".join(warnings + [str(e).replace("\n", " | ")]))
        write_stats(args.stats, stats)
        sys.exit(1)


if __name__ == "__main__":
    main()
