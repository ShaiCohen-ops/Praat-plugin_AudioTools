"""
spectral_permute.py — Spectral Permutation Engine  v2.3.1

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Usage (called by Praat, not directly):
    python spectral_permute.py input.wav output.wav stats.txt
        --start 0.5 --end 2.0
        --axis band_time --num_blocks 4 --num_bands 8
        --band_spacing bark --decorrelation 1.0
        --kind random_shuffle [--custom_order 3,1,4,2] --seed 42
        --phase_mode lock
        --fft_size 2048 --hop_size 512 --edge_fade_ms 15.0
        --num_variants 1 --energy_mode magnitude
        [--cleanup]

═══════════════════════════════════════════════════════════════════════════
WHAT CHANGED IN v2.3.1
═══════════════════════════════════════════════════════════════════════════
  - band_energy now uses conservative power rebinning (energy preserved
    exactly per frame, also for single-bin peaks). v2.3 interpolated
    magnitudes and normalised afterwards, which could erase a narrow peak
    completely and then had nothing left to rescale.

═══════════════════════════════════════════════════════════════════════════
WHAT CHANGED IN v2.3
═══════════════════════════════════════════════════════════════════════════
  - time_freq: one phase policy for every band. Magnitude comes from the
    source band at the source time block; phase ALWAYS comes from the
    destination band at the destination time. v2.0 used destination phase
    when a band moved but took the whole complex block (source-time phase)
    when the band permutation happened to leave a band in place, so one
    result mixed two phase behaviours. Phase lock is not applied on
    time_freq: the destination phase is already the original continuous
    trajectory, and rotating it would break that.
  - --energy_mode for freq / time_freq: "magnitude" (v2.0 behaviour,
    default) linearly resamples magnitudes between bands of different
    width, which also changes energy (a wide band squeezed into a narrow
    one loses most of it, a narrow band spread over a wide one gains);
    "band_energy" rescales every frame so the destination band carries the
    source band's energy (sum |Z|^2).
  - Phase lock leaves the DC and Nyquist bins unrotated, so they stay
    real. Described as identity-phase-locking-INSPIRED seam alignment: the
    correction is computed at peaks and shared by each peak's region, but
    applied once per block, not frame by frame as in a phase vocoder.
  - Stats: real block boundaries (seconds, region-relative) for the
    figure; variant_assigned_bands / unique_orders / bands_differing_from_
    master instead of a count that included repeated or master orders; a
    warning when every variant has the same permutation (deterministic
    kinds); a seam metric measured only around the block boundaries.
  - stats.txt is written last and is the completion marker.

═══════════════════════════════════════════════════════════════════════════
WHAT CHANGED IN v2.0 — and why
═══════════════════════════════════════════════════════════════════════════

v1.x sliced the STFT along the FRAME axis into contiguous blocks and
reordered those blocks. But a contiguous block of STFT columns
overlap-adds back to exactly its original time segment, so that operation
is mathematically a time-domain splice with Hann crossfades of length
(nperseg - hop). The frequency axis was never touched. Measured against a
plain time-domain reversal splice of the same material, spectrogram
magnitudes agreed to about 21%, essentially all of it at the joins.

v2.0 makes the operation actually spectral. Five permutation axes:

  time        Legacy v1 behaviour, kept and fixed. Global time-block
              permutation. With phase_mode off, equivalent to a
              time-domain splice (lock rotates block phases, so then it is
              not exactly one); retained
              as a reference and because it is a musically useful
              starting point.

  band_time   The main new mode. The bin axis is split into K bands and
              EACH BAND GETS ITS OWN PERMUTATION of the N time blocks.
              This unglues the time axis across frequency: at any instant
              the low band may be playing block 3 while the high band
              plays block 1. The result cannot be produced by any
              time-domain rearrangement of the source.

  freq        Permutation along the FREQUENCY axis, time held fixed. Band
              contents are transplanted between bands. Bands generally
              differ in bin count (log/bark/erb spacing), so the source
              band's magnitude envelope is linearly resampled onto the
              destination band's bin grid. PHASE IS TAKEN FROM THE
              DESTINATION's own original bins, which preserves temporal
              phase coherence and avoids the buzz you get from
              transplanting phase along with magnitude.

  time_freq   Both axes at once: band b receives its content from a
              different band, and within that band the time blocks are
              also permuted.

  mag_phase   Magnitude time-blocks are permuted while phase runs
              CONTINUOUSLY in its original order. No phase seams;
              magnitude can still change abruptly at a block boundary.
              Spectral content is rearranged onto the original phase
              trajectory, which is unavailable in the time domain.

Two defects from v1 are fixed:

  1. boundary='zeros' was placing analysis-window ramp frames at the head
     and tail of the analysed region. When the first or last block was
     permuted into the interior, its fade-to-zero travelled with it. On a
     steady 440 Hz tone (where a block permutation should be inaudible)
     v1 produced envelope holes down to 0.052 against a 0.40 peak, about
     -18 dB. v2.0 analyses a CONTEXT-EXTENDED segment (one FFT length of
     real audio on each side where available) and only permutes frames
     whose entire window support lies inside the requested region. The
     boundary frames stay put and provide proper overlap-add support at
     the edges; they are trimmed off after resynthesis.

  2. The v1 phase realignment was a single constant angle applied to
     every bin of a block. A constant angle is not a time alignment — a
     time offset is LINEAR phase across frequency, whereas a constant
     offset rotates every partial by the same angle regardless of its
     period. Measured with and without it, envelope minima were 0.3844 vs
     0.3854: no effect. It also injected imaginary content into the DC
     and Nyquist bins, which irfft silently discards.

     v2.0 replaces it with --phase_mode:
       off   no phase manipulation; the Hann overlap-add handles the seam
       lock  per-bin phase continuation with Laroche-Dolson identity
             phase locking. At each seam, the phase each bin SHOULD have
             is predicted from the previously placed frame plus that
             bin's nominal advance; the correction angle is computed only
             at spectral PEAKS and applied to the whole region of
             influence around each peak, so bin-to-bin relationships
             within a partial survive. The whole incoming block is
             rotated by that per-bin constant, so nothing inside the
             block is warped.

     This is still a heuristic, not exact reconstruction. The stats file
     reports a MEASURED seam metric (max sample-to-sample step, in and
     out) rather than a count of corrections applied, so its effect is
     visible rather than asserted.

Also new:
  - Blocks are now EQUAL length. v1 distributed remainder frames to the
    earliest blocks, which meant a permuted block landed at a shifted
    time. Leftover frames are left unpermuted as a tail and reported.
  - --num_variants K renders K differently-seeded results in one process.
  - The applied permutation is written to stats.txt per band so the front
    end can display it and the result can be reproduced.
  - A permutation map (bands x blocks grid of source-block indices) and
    the band edge frequencies are written to stats.txt for plotting.

No external model downloads. No internet. numpy + scipy + soundfile only.
"""

import sys
import os

PRAAT_TEMP_PREFIX = "temp_specperm_"

AXES = ["time", "band_time", "freq", "time_freq", "mag_phase"]
KINDS = ["reverse", "rotate", "random_shuffle", "custom_order"]
SPACINGS = ["linear", "log", "mel", "bark", "erb"]
PHASE_MODES = ["off", "lock"]
ENERGY_MODES = ["magnitude", "band_energy"]


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

def check_dependencies():
    missing = []
    for pkg in ["numpy", "scipy", "soundfile"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)


def _is_praat_temp(path):
    return os.path.basename(path).startswith(PRAAT_TEMP_PREFIX)


def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════
# Permutation construction
# ═══════════════════════════════════════════════════════════════════════════

def parse_custom(custom_str, n):
    try:
        order = [int(x.strip()) - 1 for x in custom_str.split(",") if x.strip() != ""]
    except ValueError:
        die("--custom_order must be a comma-separated list of integers")
    if sorted(order) != list(range(n)):
        die("--custom_order must be a permutation of 1..%d (got: %s)" % (n, custom_str))
    return order


def master_order(n, kind, custom_str, seed):
    """order[i] = index of the ORIGINAL block placed at NEW position i."""
    import numpy as np
    if kind == "reverse":
        return list(reversed(range(n)))
    if kind == "rotate":
        return list(range(1, n)) + [0]
    if kind == "random_shuffle":
        return [int(i) for i in np.random.RandomState(seed).permutation(n)]
    if kind == "custom_order":
        return parse_custom(custom_str, n)
    die("unknown permutation kind: %s" % kind)


def variant_order(n, kind, custom_str, seed, b, master):
    """An order for band b that DIFFERS from the master order.

    Decorrelation has to mean something specific for each kind, otherwise
    'reverse' would give every band the same reversal and the per-band mode
    would collapse back to the global one.
      reverse / custom : master order, cyclically rotated by b+1
      rotate           : rotate by b+1 instead of by 1
      random_shuffle   : independent shuffle seeded seed + b + 1
    """
    import numpy as np
    if kind == "random_shuffle":
        return [int(i) for i in np.random.RandomState(seed + b + 1).permutation(n)]
    if kind == "rotate":
        k = (b + 1) % n
        return list(range(k, n)) + list(range(k))
    k = (b + 1) % n
    return master[k:] + master[:k]


def build_band_orders(n_blocks, n_bands, kind, custom_str, seed, decorrelation):
    """One time-order per band. `decorrelation` in [0,1] is the probability
    that a band gets its own order rather than the master's. At 0 every band
    shares the master order and band_time degenerates to time; at 1 every
    band is independent."""
    import numpy as np
    master = master_order(n_blocks, kind, custom_str, seed)
    rng = np.random.RandomState(seed + 7919)
    orders = []
    n_assigned = 0
    for b in range(n_bands):
        if decorrelation > 0 and rng.random_sample() < decorrelation:
            orders.append(variant_order(n_blocks, kind, custom_str, seed, b, master))
            n_assigned += 1
        else:
            orders.append(list(master))
    counts = {"assigned": n_assigned,
              "unique": len({tuple(o) for o in orders}),
              "differ": sum(1 for o in orders if o != master)}
    return master, orders, counts


# ═══════════════════════════════════════════════════════════════════════════
# Band layout
# ═══════════════════════════════════════════════════════════════════════════

def _hz_to_mel(f):
    import numpy as np
    return 2595.0 * np.log10(1.0 + f / 700.0)


def _mel_to_hz(m):
    return 700.0 * (10.0 ** (m / 2595.0) - 1.0)


def _hz_to_bark(f):
    import numpy as np
    return 13.0 * np.arctan(0.00076 * f) + 3.5 * np.arctan((f / 7500.0) ** 2)


def _hz_to_erb(f):
    import numpy as np
    return 21.4 * np.log10(1.0 + 0.00437 * f)


def _erb_to_hz(e):
    return (10.0 ** (e / 21.4) - 1.0) / 0.00437


def band_edges(n_bins, sr, n_fft, n_bands, spacing):
    """Return a list of (lo_bin, hi_bin), hi exclusive, covering [0, n_bins),
    strictly increasing, every band at least one bin wide."""
    import numpy as np

    nyq = sr / 2.0
    f_lo = max(20.0, 2.0 * sr / n_fft)      # below this the bins are unusable
    if spacing == "linear":
        edges_hz = np.linspace(0.0, nyq, n_bands + 1)
    elif spacing == "log":
        edges_hz = np.concatenate([[0.0],
                                   np.logspace(np.log10(f_lo), np.log10(nyq), n_bands)])
    elif spacing == "mel":
        edges_hz = _mel_to_hz(np.linspace(_hz_to_mel(0.0), _hz_to_mel(nyq), n_bands + 1))
    elif spacing == "bark":
        # the bark curve has no clean closed-form inverse; a dense table
        # lookup is exact enough for band edges
        grid = np.linspace(0.0, nyq, 20000)
        bk = _hz_to_bark(grid)
        edges_hz = np.interp(np.linspace(bk[0], bk[-1], n_bands + 1), bk, grid)
    elif spacing == "erb":
        edges_hz = _erb_to_hz(np.linspace(_hz_to_erb(0.0), _hz_to_erb(nyq), n_bands + 1))
    else:
        die("unknown band spacing: %s" % spacing)

    bins = np.round(np.asarray(edges_hz) / nyq * (n_bins - 1)).astype(int)
    bins[0] = 0
    bins[-1] = n_bins
    for i in range(1, len(bins)):
        if bins[i] <= bins[i - 1]:
            bins[i] = bins[i - 1] + 1
    if bins[-1] > n_bins:
        bins[-1] = n_bins
        for i in range(len(bins) - 2, -1, -1):
            if bins[i] >= bins[i + 1]:
                bins[i] = bins[i + 1] - 1
    if bins[0] < 0:
        die("num_bands (%d) is too large for this FFT size (%d bins)" % (n_bands, n_bins))
    return [(int(bins[i]), int(bins[i + 1])) for i in range(n_bands)]


# ═══════════════════════════════════════════════════════════════════════════
# Seam phase alignment (inspired by Laroche-Dolson identity phase locking)
# ═══════════════════════════════════════════════════════════════════════════

def peak_regions(mag):
    """Assign every bin to the nearest spectral peak. owner[k] is the bin
    index of the peak that governs bin k."""
    import numpy as np
    n = len(mag)
    if n < 3:
        return np.zeros(n, dtype=int) + int(np.argmax(mag))
    peaks = [k for k in range(1, n - 1)
             if mag[k] > mag[k - 1] and mag[k] >= mag[k + 1]]
    if not peaks:
        return np.zeros(n, dtype=int) + int(np.argmax(mag))
    peaks = np.asarray(peaks)
    owner = np.empty(n, dtype=int)
    b = 0
    for p in range(len(peaks)):
        if p == len(peaks) - 1:
            end = n
        else:
            lo, hi = int(peaks[p]), int(peaks[p + 1])
            end = lo + int(np.argmin(mag[lo:hi + 1]))
            end = max(end, lo + 1)
        owner[b:end] = peaks[p]
        b = end
    owner[b:] = peaks[-1]
    return owner


def lock_phase(prev_frame, block, bin_offset, n_fft, hop):
    """Rotate `block` (bins x frames) by a per-bin constant so its first
    frame continues `prev_frame`'s phase. The correction is computed only at
    spectral peaks and shared across each peak's region of influence, so
    relationships between the bins of one partial are preserved. The rotation
    is constant across frames, so nothing inside the block is warped."""
    import numpy as np
    if prev_frame is None or block.shape[1] == 0:
        return block
    first = block[:, 0]
    mag = np.abs(first)
    if float(np.max(mag)) < 1e-12:
        return block
    k_abs = np.arange(bin_offset, bin_offset + block.shape[0])
    advance = 2.0 * np.pi * k_abs * hop / float(n_fft)
    delta_all = (np.angle(prev_frame) + advance) - np.angle(first)
    owner = peak_regions(mag)               # local (band-relative) indices
    delta = delta_all[owner]
    # DC and Nyquist must stay real (v2.0 rotated them too; irfft then
    # silently dropped the imaginary part)
    n_bins_total = n_fft // 2 + 1
    for kk in (0, n_bins_total - 1):
        loc = kk - bin_offset
        if 0 <= loc < block.shape[0]:
            delta[loc] = 0.0
    return block * np.exp(1j * delta)[:, None]


# ═══════════════════════════════════════════════════════════════════════════
# The permutation operators
# ═══════════════════════════════════════════════════════════════════════════

def resample_band(mag_src, n_dst):
    """Linearly resample a (bins x frames) magnitude patch onto n_dst bins."""
    import numpy as np
    n_src = mag_src.shape[0]
    if n_src == n_dst:
        return mag_src
    if n_src == 1:
        return np.repeat(mag_src, n_dst, axis=0)
    xs = np.linspace(0.0, 1.0, n_src)
    xd = np.linspace(0.0, 1.0, n_dst)
    out = np.empty((n_dst, mag_src.shape[1]), dtype=mag_src.dtype)
    for j in range(mag_src.shape[1]):
        out[:, j] = np.interp(xd, xs, mag_src[:, j])
    return out


def rebin_matrix(n_src, n_dst):
    """Conservative rebinning weights W (n_dst x n_src). Source bin i covers
    [i/n_src, (i+1)/n_src) of the band, destination bin j covers
    [j/n_dst, (j+1)/n_dst); W[j, i] is the fraction of source bin i that
    falls in destination bin j. Every column sums to 1, so W @ power
    preserves the total power exactly — no peak can fall between samples."""
    import numpy as np
    W = np.zeros((n_dst, n_src))
    for i in range(n_src):
        a0, a1 = i / n_src, (i + 1) / n_src
        j0 = int(np.floor(a0 * n_dst))
        j1 = min(n_dst - 1, int(np.ceil(a1 * n_dst)) - 1)
        for j in range(j0, j1 + 1):
            ov = min(a1, (j + 1) / n_dst) - max(a0, j / n_dst)
            if ov > 0:
                W[j, i] = ov * n_src
    return W


def transplant(src_cplx, dst_cplx, energy_mode):
    """Magnitude of a source band patch on the destination band's bin grid,
    with the destination's phase.
      magnitude    linear interpolation of magnitudes (v2.2 behaviour;
                   band energy changes with band width)
      band_energy  conservative POWER rebinning: |Z|^2 is shared among the
                   destination bins by overlap, then sqrt. Energy per frame
                   is preserved exactly, sparse/tonal content included.
                   (v2.3 interpolated first and normalised afterwards, which
                   lost a narrow peak that fell between interpolation points:
                   [0,1,0] onto 2 bins gave [0,0] and stayed silent.)"""
    import numpy as np
    mag_src = np.abs(src_cplx)
    n_dst = dst_cplx.shape[0]
    if energy_mode == "band_energy":
        W = rebin_matrix(mag_src.shape[0], n_dst)
        patch = np.sqrt(W @ (mag_src ** 2))
    else:
        patch = resample_band(mag_src, n_dst)
    return patch * np.exp(1j * np.angle(dst_cplx))


def permute_region(Z, f0, f1, cfg):
    """Permute Z[:, f0:f1] and return (Znew, info).

    Frames outside [f0, f1) are context and are never touched — they hold the
    overlap-add support at the region edges.
    """
    import numpy as np

    Zout = Z.copy()
    n_frames = f1 - f0
    N = cfg["n_blocks"]
    g0 = f0

    if cfg["axis"] == "freq":
        # Time is held fixed on this axis, so the block grid has no effect on
        # the sound at all - in v2.0 num_blocks only decided how many frames
        # fell into the untouched tail. Use the whole interior range.
        blk = n_frames
        used = n_frames
        tail = 0
        starts = [g0]
    else:
        blk = n_frames // N
        if blk < 1:
            return Zout, {"error": "not enough STFT frames (%d) for %d blocks" % (n_frames, N)}
        used = blk * N
        tail = n_frames - used                   # left unpermuted, reported
        starts = [g0 + i * blk for i in range(N)]

    bands = cfg["bands"]
    orders = cfg["band_orders"]
    band_order = cfg["band_order"]
    axis = cfg["axis"]
    phase_mode = cfg["phase_mode"]
    n_fft, hop = cfg["n_fft"], cfg["hop"]

    if axis == "mag_phase":
        mag = np.abs(Z)
        newmag = mag.copy()
        for b, (lo, hi) in enumerate(bands):
            for i, src in enumerate(orders[b]):
                newmag[lo:hi, starts[i]:starts[i] + blk] = \
                    mag[lo:hi, starts[src]:starts[src] + blk]
        Zout[:, g0:g0 + used] = (newmag[:, g0:g0 + used] *
                                 np.exp(1j * np.angle(Z[:, g0:g0 + used])))
        return Zout, {"tail_frames": tail, "block_frames": blk, "starts": starts}

    for b, (lo, hi) in enumerate(bands):
        order = orders[b]
        src_band = band_order[b] if axis in ("freq", "time_freq") else b
        slo, shi = bands[src_band]
        width = hi - lo

        if axis == "freq":
            Zout[lo:hi, g0:g0 + used] = transplant(Z[slo:shi, g0:g0 + used],
                                                   Z[lo:hi, g0:g0 + used], cfg["energy_mode"])
            continue

        if axis == "time_freq":
            # one policy for every band: magnitude from (source band, source
            # block), phase from (destination band, destination time). No
            # phase lock: the destination phase is already continuous.
            for i, src in enumerate(order):
                s, d = starts[src], starts[i]
                Zout[lo:hi, d:d + blk] = transplant(Z[slo:shi, s:s + blk], Z[lo:hi, d:d + blk],
                                                    cfg["energy_mode"])
            continue

        prev = Z[lo:hi, g0 - 1] if (phase_mode == "lock" and g0 >= 1) else None
        for i, src in enumerate(order):
            s = starts[src]
            d = starts[i]
            block = Z[lo:hi, s:s + blk].copy()

            if phase_mode == "lock":
                block = lock_phase(prev, block, lo, n_fft, hop)

            Zout[lo:hi, d:d + blk] = block
            prev = block[:, -1]

    return Zout, {"tail_frames": tail, "block_frames": blk, "starts": starts}


# ═══════════════════════════════════════════════════════════════════════════
# Analysis / resynthesis of one channel
# ═══════════════════════════════════════════════════════════════════════════

def apply_edge_fade(x, fade_n):
    """Equal-power (quarter-sine) taper on the first and last `fade_n`
    samples. Not a crossfade — there is nothing on the other side to blend
    with; this only stops an arbitrary non-zero sample at the clip boundaries
    from clicking."""
    import numpy as np
    n = len(x)
    fade_n = int(min(fade_n, n // 2))
    if fade_n <= 0:
        return x
    y = x.copy()
    t = np.linspace(0.0, np.pi / 2.0, fade_n)
    y[:fade_n] *= np.sin(t)
    y[n - fade_n:] *= np.cos(t)
    return y


def process_channel(audio_ch, sr, start_i, end_i, cfg, fade_n):
    """Context-extended STFT, permute only the fully-interior frames,
    resynthesise, cut the requested region back out."""
    import numpy as np
    from scipy.signal import stft, istft

    n_fft, hop = cfg["n_fft"], cfg["hop"]
    n_total = len(audio_ch)
    region_len = end_i - start_i

    if region_len < n_fft:
        reason = ("selected region (%d samples / %.3fs) is shorter than the "
                  "window (%d samples / %.3fs) - left unmodified. Use a smaller "
                  "Window_ms or select a longer region." %
                  (region_len, region_len / sr, n_fft, n_fft / sr))
        return apply_edge_fade(audio_ch[start_i:end_i].copy(), fade_n), {"error": reason}

    pad = n_fft
    c0 = max(0, start_i - pad)
    c1 = min(n_total, end_i + pad)
    seg = audio_ch[c0:c1]
    lead = start_i - c0                       # real context available before

    # boundary='zeros' pads n_fft//2 zeros at each end of seg, so frame m is
    # CENTRED on seg sample m*hop and spans [m*hop - n_fft//2, +n_fft).
    f, t, Z = stft(seg, fs=sr, window="hann", nperseg=n_fft,
                   noverlap=n_fft - hop, boundary="zeros", padded=True)
    n_frames = Z.shape[1]
    half = n_fft // 2

    # frames whose ENTIRE window support lies inside [lead, lead+region_len)
    f0 = int(np.ceil((lead + half) / float(hop)))
    f1 = int(np.floor((lead + region_len - half) / float(hop))) + 1
    f0 = max(0, min(f0, n_frames))
    f1 = max(f0, min(f1, n_frames))

    need = 1 if cfg["axis"] == "freq" else cfg["n_blocks"]
    if (f1 - f0) < need:
        reason = ("only %d fully-interior STFT frame(s) at this Window_ms / "
                  "Hop_size, fewer than the %d required - left unmodified. Use a "
                  "smaller Window_ms, a smaller Hop_size, fewer blocks, or a "
                  "longer region." % (f1 - f0, need))
        return apply_edge_fade(audio_ch[start_i:end_i].copy(), fade_n), {"error": reason}

    Znew, info = permute_region(Z, f0, f1, cfg)
    if "error" in info:
        return apply_edge_fade(audio_ch[start_i:end_i].copy(), fade_n), info

    _, y = istft(Znew, fs=sr, window="hann", nperseg=n_fft,
                 noverlap=n_fft - hop, boundary=True)
    y = np.asarray(y, dtype=np.float64)

    if len(y) < lead + region_len:
        y = np.pad(y, (0, lead + region_len - len(y)))
    out = y[lead:lead + region_len]
    info["interior_frames"] = f1 - f0
    # Real block boundaries, in seconds from the region start. Frame m is
    # centred on seg sample m*hop; the boundary between two consecutive
    # frames is taken half a hop before the first frame of a block.
    blk = info["block_frames"]
    edges = [s for s in info["starts"]] + [info["starts"][-1] + blk]
    info["bounds_s"] = [((m * hop - hop / 2.0) - lead) / sr for m in edges]
    info["bounds_samples"] = [int(round(m * hop - hop / 2.0 - lead)) for m in edges]
    return apply_edge_fade(out, fade_n), info


def seam_metric(src, out, bounds_samples, sr, win_ms=5.0):
    """Largest sample-to-sample step within +-win_ms of each INTERIOR block
    boundary, output vs source at the same place. Returns (ratio, worst
    output step, matching source step). ratio ~1 means the joins are no
    rougher than the source was there."""
    import numpy as np
    w = max(2, int(round(win_ms / 1000.0 * sr)))
    ratios, worst = [], (0.0, 0.0)
    for b in bounds_samples[1:-1]:
        a0, a1 = max(1, b - w), min(len(out), len(src), b + w)
        if a1 - a0 < 2:
            continue
        so = float(np.max(np.abs(np.diff(out[a0 - 1:a1]))))
        ss = float(np.max(np.abs(np.diff(src[a0 - 1:a1]))))
        ratios.append(so / max(ss, 1e-9))
        if so > worst[0]:
            worst = (so, ss)
    if not ratios:
        return None, 0.0, 0.0
    return float(np.median(ratios)), worst[0], worst[1]


def max_step(x):
    """Largest sample-to-sample jump over the WHOLE clip. Not a seam
    measure (any transient or added high-frequency energy dominates it);
    kept for continuity of the report. seam_metric() is the seam measure."""
    import numpy as np
    if len(x) < 2:
        return 0.0
    return float(np.max(np.abs(np.diff(x))))


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    import argparse
    import numpy as np
    import soundfile as sf

    p = argparse.ArgumentParser(
        description="Spectral permutation across time, frequency and per-band axes.")
    p.add_argument("input_wav")
    p.add_argument("output_wav")
    p.add_argument("stats_txt")
    p.add_argument("--start", type=float, default=0.0)
    p.add_argument("--end", type=float, default=0.0, help="0 = end of file")
    p.add_argument("--axis", type=str, default="band_time", choices=AXES)
    p.add_argument("--num_blocks", type=int, default=4)
    p.add_argument("--num_bands", type=int, default=8)
    p.add_argument("--band_spacing", type=str, default="bark", choices=SPACINGS)
    p.add_argument("--decorrelation", type=float, default=1.0)
    p.add_argument("--kind", type=str, default="random_shuffle", choices=KINDS)
    p.add_argument("--custom_order", type=str, default="")
    p.add_argument("--custom_band_order", type=str, default="")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--phase_mode", type=str, default="lock", choices=PHASE_MODES)
    p.add_argument("--fft_size", type=int, default=2048)
    p.add_argument("--hop_size", type=int, default=512)
    p.add_argument("--edge_fade_ms", type=float, default=15.0)
    p.add_argument("--num_variants", type=int, default=1)
    p.add_argument("--energy_mode", type=str, default="magnitude", choices=ENERGY_MODES)
    p.add_argument("--cleanup", action="store_true")
    args = p.parse_args()

    check_dependencies()

    print("  [Py 1/4] Loading audio...")
    audio, sr = sf.read(args.input_wav, always_2d=False)
    audio = np.asarray(audio, dtype=np.float64)
    mono = audio.ndim == 1
    n_ch = 1 if mono else audio.shape[1]
    n_samples = audio.shape[0]
    orig_dur = n_samples / sr

    start_t = max(0.0, args.start)
    end_t = args.end if args.end > 0 else orig_dur
    end_t = min(end_t, orig_dur)
    if end_t <= start_t:
        die("end_time must be greater than start_time")
    start_i = int(round(start_t * sr))
    end_i = int(round(end_t * sr))

    n_fft = max(64, args.fft_size)
    hop = args.hop_size
    if hop >= n_fft:
        hop = max(1, n_fft // 4)
        print("  WARNING: hop_size >= fft_size; clamped hop to %d" % hop)
    n_bins = n_fft // 2 + 1

    n_blocks = max(2, args.num_blocks)
    n_bands = max(1, args.num_bands)
    if args.axis == "time":
        n_bands = 1                       # one band spanning the whole spectrum
    if n_bands > n_bins:
        print("  WARNING: num_bands %d exceeds %d usable bins; clamped" % (n_bands, n_bins))
        n_bands = n_bins
    if args.axis in ("freq", "time_freq") and n_bands < 2:
        die("axis '%s' needs at least 2 bands" % args.axis)

    decor = min(1.0, max(0.0, args.decorrelation))
    if args.axis == "time":
        decor = 0.0

    bands = band_edges(n_bins, sr, n_fft, n_bands, args.band_spacing)
    fade_n = int(round(args.edge_fade_ms / 1000.0 * sr))
    n_variants = max(1, args.num_variants)

    print("  [Py 2/4] Region %.3f -> %.3f s | axis=%s | blocks=%d | bands=%d (%s)" %
          (start_t, end_t, args.axis, n_blocks, n_bands, args.band_spacing))
    print("    FFT=%d  hop=%d  phase=%s  decorrelation=%.2f  variants=%d" %
          (n_fft, hop, args.phase_mode, decor, n_variants))

    base, ext = os.path.splitext(args.output_wav)
    written = []
    stats_blocks = []

    for v in range(n_variants):
        seed = args.seed + v
        if args.axis == "freq":
            t_kind, t_custom = "rotate", ""     # unused; time is held fixed
        else:
            t_kind, t_custom = args.kind, args.custom_order
        master, band_orders, counts = build_band_orders(
            n_blocks, n_bands, t_kind, t_custom, seed, decor)

        if args.axis in ("freq", "time_freq"):
            if args.kind == "custom_order":
                # v2.0 silently fell back to random_shuffle here, because a
                # custom order has num_blocks entries while the band
                # permutation needs num_bands. The report then showed a band
                # order that looked fine and was never the one asked for.
                if not args.custom_band_order.strip():
                    die("axis '%s' with kind custom_order requires "
                        "--custom_band_order (a permutation of 1..%d)"
                        % (args.axis, n_bands))
                b_order = parse_custom(args.custom_band_order, n_bands)
            else:
                b_order = master_order(n_bands, args.kind, "", seed + 104729)
        else:
            b_order = list(range(n_bands))

        cfg = {"axis": args.axis, "n_blocks": n_blocks, "bands": bands,
               "band_orders": band_orders, "band_order": b_order,
               "phase_mode": args.phase_mode, "n_fft": n_fft, "hop": hop,
               "energy_mode": args.energy_mode}

        print("  [Py 3/4] Variant %d/%d (seed %d): permuting..." % (v + 1, n_variants, seed))

        warn = []
        if mono:
            res, info = process_channel(audio, sr, start_i, end_i, cfg, fade_n)
            if "error" in info:
                warn.append(info["error"])
            src_metric = audio[start_i:end_i]
        else:
            chans, seen, info = [], set(), {}
            for c in range(n_ch):
                r, inf = process_channel(audio[:, c], sr, start_i, end_i, cfg, fade_n)
                chans.append(r)
                info = inf
                if "error" in inf and inf["error"] not in seen:
                    warn.append(inf["error"])
                    seen.add(inf["error"])
            m = min(len(c) for c in chans)
            res = np.stack([c[:m] for c in chans], axis=1)
            src_metric = audio[start_i:end_i, 0]

        out_path = args.output_wav if n_variants == 1 else "%s_v%d%s" % (base, v + 1, ext)
        sf.write(out_path, res.astype(np.float32), sr, subtype="FLOAT")
        written.append(out_path)

        probe = res if res.ndim == 1 else res[:, 0]
        seam = (None, 0.0, 0.0)
        if "bounds_samples" in info and args.axis != "freq":
            seam = seam_metric(src_metric, probe, info["bounds_samples"], sr)
        stats_blocks.append({
            "seed": seed, "master": master, "band_orders": band_orders,
            "band_order": b_order, "counts": counts, "warn": warn, "info": info, "seam": seam,
            "path": out_path,
            "step_in": max_step(src_metric), "step_out": max_step(probe),
            "peak": float(np.max(np.abs(res))) if res.size else 0.0,
            "dur": res.shape[0] / sr,
        })
        for w in warn:
            print("  WARNING: %s" % w)

    print("  [Py 4/4] Writing stats...")
    s0 = stats_blocks[0]
    nyq = sr / 2.0
    stats_tmp = args.stats_txt + ".part"
    with open(stats_tmp, "w") as f:
        f.write("start_time=%.4f\n" % start_t)
        f.write("end_time=%.4f\n" % end_t)
        f.write("region_duration=%.4f\n" % (end_t - start_t))
        f.write("duration_in=%.4f\n" % orig_dur)
        f.write("duration_out=%.4f\n" % s0["dur"])
        f.write("sr=%d\n" % sr)
        f.write("channels=%d\n" % n_ch)
        f.write("axis=%s\n" % args.axis)
        f.write("kind=%s\n" % args.kind)
        f.write("num_blocks=%d\n" % (0 if args.axis == "freq" else n_blocks))
        f.write("num_bands=%d\n" % n_bands)
        f.write("band_spacing=%s\n" % args.band_spacing)
        f.write("decorrelation=%.3f\n" % decor)
        f.write("variant_assigned_bands=%d\n" % s0["counts"]["assigned"])
        f.write("unique_orders=%d\n" % s0["counts"]["unique"])
        f.write("bands_differing_from_master=%d\n" % s0["counts"]["differ"])
        f.write("energy_mode=%s\n" % (args.energy_mode if args.axis in ("freq", "time_freq") else "n/a"))
        f.write("phase_mode=%s\n" % args.phase_mode)
        f.write("phase_effective=%s\n" % (
            "lock (seam alignment)" if args.phase_mode == "lock" and args.axis in ("time", "band_time")
            else "off" if args.axis in ("time", "band_time")
            else "destination phase kept (lock not applicable)" if args.axis in ("freq", "time_freq")
            else "original phase trajectory kept (lock not applicable)"))
        f.write("fft_size=%d\n" % n_fft)
        f.write("hop_size=%d\n" % hop)
        f.write("edge_fade_ms=%.2f\n" % args.edge_fade_ms)
        f.write("seed=%d\n" % args.seed)
        f.write("num_variants=%d\n" % n_variants)
        f.write("interior_frames=%d\n" % s0["info"].get("interior_frames", 0))
        f.write("block_frames=%d\n" % s0["info"].get("block_frames", 0))
        f.write("tail_frames=%d\n" % s0["info"].get("tail_frames", 0))
        f.write("max_step_in=%.6f\n" % s0["step_in"])
        f.write("max_step_out=%.6f\n" % s0["step_out"])
        sr_, so_, ss_ = s0["seam"]
        f.write("seam_ratio=%s\n" % ("n/a" if sr_ is None else "%.3f" % sr_))
        f.write("seam_worst_out=%.6f\n" % so_)
        f.write("seam_worst_src=%.6f\n" % ss_)
        bs = s0["info"].get("bounds_s")
        f.write("block_bounds_s=%s\n" % (",".join("%.5f" % v for v in bs)
                                        if (bs and args.axis != "freq") else "none"))
        if bs:
            f.write("interior_start_s=%.5f\n" % bs[0])
            f.write("interior_end_s=%.5f\n" % bs[-1])
        f.write("peak_out=%.6f\n" % s0["peak"])
        if args.axis == "freq":
            f.write("master_order=n/a\n")
        else:
            f.write("master_order=%s\n" % ",".join(str(i + 1) for i in s0["master"]))
        f.write("band_order=%s\n" % ",".join(str(i + 1) for i in s0["band_order"]))
        map_is_band = (args.axis == "freq")
        f.write("map_value=%s\n" % ("band" if map_is_band else "block"))
        f.write("map_bands=%d\n" % n_bands)
        f.write("map_blocks=%d\n" % (1 if map_is_band else n_blocks))
        f.write("map_ramp=%d\n" % (n_bands if map_is_band else n_blocks))
        f.write("blocks_used=%s\n" % ("no" if map_is_band else "yes"))
        for b in range(n_bands):
            lo, hi = bands[b]
            f.write("band_%d_hz=%.1f,%.1f\n" % (b + 1, lo / (n_bins - 1) * nyq,
                                                hi / (n_bins - 1) * nyq))
            if map_is_band:
                row = [s0["band_order"][b] + 1]
            else:
                row = [i + 1 for i in s0["band_orders"][b]]
            f.write("map_row_%d=%s\n" % (b + 1, ",".join(str(i) for i in row)))
        for i, sb in enumerate(stats_blocks):
            f.write("variant_%d_seed=%d\n" % (i + 1, sb["seed"]))
            f.write("variant_%d_file=%s\n" % (i + 1, os.path.basename(sb["path"])))
        allwarn = []
        if n_variants > 1:
            sig = lambda sb: (tuple(sb["master"]), tuple(map(tuple, sb["band_orders"])), tuple(sb["band_order"]))
            if all(sig(sb) == sig(stats_blocks[0]) for sb in stats_blocks[1:]):
                allwarn.append("all %d variants have the same permutation for this parameter "
                               "combination (deterministic kind); the extra files are identical"
                               % n_variants)
        for sb in stats_blocks:
            for w in sb["warn"]:
                if w not in allwarn:
                    allwarn.append(w)
        f.write("warning=%s\n" % ("; ".join(allwarn) if allwarn else "none"))

    os.replace(stats_tmp, args.stats_txt)       # appears only when complete

    if args.cleanup and _is_praat_temp(args.input_wav) and os.path.exists(args.input_wav):
        os.remove(args.input_wav)
        print("    Deleted: %s" % args.input_wav)

    print("OK: wrote %s" % ", ".join(os.path.basename(w) for w in written))


if __name__ == "__main__":
    main()
