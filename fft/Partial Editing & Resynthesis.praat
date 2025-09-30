################################################################################
# FAST SPEAR-like Partial Editing & Resynthesis (per-frame, gated Formula)
# - Minimal-but-sounding defaults
# - Optional pre-resampling to 11025 or 22050 Hz
# - Per frame: Sound → Spectrum → Ltas(1-to-1) → pick top-N → add small sum gated to window
################################################################################

form Sinusoidal partial editor (minimal, resampling option)
    comment --- Quick, good-sounding defaults ---
    positive window_length           0.030   ; s (try 0.02–0.05)
    positive hop_size                0.015   ; s (smaller → closer match, slower)
    positive min_frequency           120     ; Hz
    positive max_frequency           3500    ; Hz
    integer  max_partials_per_frame  6       ; raise to 12–20 for richer result
    integer  suppress_bins           2       ; ±bins suppressed around picks

    comment --- Optional transpose / scaling ---
    real     transpose_semitones     0
    real     formant_shift_ratio     1.0
    real     amplitude_scale         1.0

    comment --- Optional pre-resampling for speed ---
    choice   resample_to             1
        button No resampling
        button 11025 Hz
        button 22050 Hz

    comment Show progress every N frames (0 = off)
    integer  progress_every          20
endform

# Preconditions
if numberOfSelected ("Sound") = 0
    exit Please select a Sound first.
endif
selectObject: selected ("Sound", 1)
origName$ = selected$ ("Sound")

# Capture user selection (if any) before copy/resample
t1sel = Get start time
t2sel = Get end time

# --- Make a working copy / optionally resample --------------------------------
# We work on "Sound input" so originals stay untouched.
Copy... input
selectObject: "Sound input"

if resample_to = 2
    # 11025 Hz
    Resample... 11025 50
    Rename: "input"
elsif resample_to = 3
    # 22050 Hz
    Resample... 22050 50
    Rename: "input"
endif

# Use time selection if set; otherwise full duration (clamped to new sound)
t1 = t1sel
t2 = t2sel
totdur = Get total duration
if t2 <= t1 or t1 < 0 or t2 > totdur
    t1 = 0
    t2 = totdur
endif
dur = t2 - t1
fs  = Get sampling frequency
nyq = fs / 2

# Accumulator (silence)
Create Sound from formula: "resynth", 1, 0, dur, fs, "0"

# Frames (≥1)
nframes = floor ((dur - window_length) / hop_size)
if nframes < 0
    nframes = 0
endif
nframes = nframes + 1

# Precompute constants
tr    = 2 ^ (transpose_semitones / 12)
fr    = formant_shift_ratio
sigma = window_length / 2.355
two_pi$ = "6.283185307179586"

# ===== Frame loop ==============================================================
for i from 0 to nframes - 1
    if progress_every > 0 and (i mod progress_every) = 0
        writeInfoLine: "Frame ", i + 1, " / ", nframes
    endif

    tc = i * hop_size + window_length/2

    # frame bounds in working segment time
    left  = tc - window_length/2
    if left < 0
        left = 0
    endif
    right = tc + window_length/2
    if right > dur
        right = dur
    endif
    winDur = right - left
    if winDur <= 0
        next
    endif

    # frame → Spectrum → LTAS
    selectObject: "Sound input"
    Extract part: t1 + left, t1 + right, "hanning", 1, "yes"   ; absolute times on "input"
    Rename: "frame"

    selectObject: "Sound frame"
    To Spectrum: "yes"
    sframe = selected ("Spectrum")

    selectObject: sframe
    To Ltas (1-to-1)
    ltas = selected ("Ltas")

    # band & bin range
    fmin = min_frequency
    fmax = max_frequency
    if fmax > nyq - 1
        fmax = nyq - 1
    endif
    if fmin < 0
        fmin = 0
    endif

    selectObject: ltas
    nbins = Get number of bins
    bmin = Get bin number from frequency: fmin
    bmin = round (bmin)
    if bmin < 1
        bmin = 1
    endif
    bmax = Get bin number from frequency: fmax
    bmax = round (bmax)
    if bmax > nbins
        bmax = nbins
    endif
    if bmax < bmin
        tmp = bmin
        bmin = bmax
        bmax = tmp
    endif
    df = nyq / nbins

    # Cache LTAS values into a table (column 'val')
    Create Table with column names: "ltas_vals", nbins, "val"
    for b from 1 to nbins
        selectObject: ltas
        v = Get value in bin: b
        selectObject: "Table ltas_vals"
        Set numeric value: b, "val", v
    endfor

    # Suppression flags (column 'flag')
    Create Table with column names: "suppressed", nbins, "flag"
    for b from 1 to nbins
        Set numeric value: b, "flag", 0
    endfor

    # Picked bins (column 'b')
    Create Table with column names: "picked", 0, "b"

    # Pick up to N peaks with simple non-maximum suppression
    for k from 1 to max_partials_per_frame
        bestBin = 0
        bestVal = -1e30

        for b from bmin to bmax
            selectObject: "Table suppressed"
            sup = Get value: b, "flag"
            if sup = 0
                selectObject: "Table ltas_vals"
                val_here = Get value: b, "val"
                if val_here > bestVal
                    bestVal = val_here
                    bestBin = b
                endif
            endif
        endfor

        if bestBin <> 0
            selectObject: "Table picked"
            Append row
            rp = Get number of rows
            Set numeric value: rp, "b", bestBin

            # suppress neighborhood
            s_from = bestBin - suppress_bins
            if s_from < 1
                s_from = 1
            endif
            s_to = bestBin + suppress_bins
            if s_to > nbins
                s_to = nbins
            endif

            selectObject: "Table suppressed"
            for sb from s_from to s_to
                Set numeric value: sb, "flag", 1
            endfor
        endif
    endfor

    # ----- build one small sum for this frame (absolute time x, then gate)
    s$   = fixed$ (sigma, 12)
    # absolute center of the frame within the output segment [0,dur]
    t0$  = fixed$ ( (left + right) / 2, 12 )
    sum$ = "0"

    selectObject: "Table picked"
    nP = Get number of rows
    if nP > max_partials_per_frame
        nP = max_partials_per_frame
    endif

    for rr from 1 to nP
        selectObject: "Table picked"
        bb = Get value: rr, "b"
        fpk = (bb - 1) * df

        # amplitude (dB) → linear
        selectObject: "Table ltas_vals"
        val_db = Get value: bb, "val"
        a0 = 10 ^ (val_db / 20)
        if a0 <= 1e-10
            a0 = 1e-10
        endif
        a0 = a0 * amplitude_scale

        # transforms
        f2 = fpk * tr * fr
        if f2 > 0 and f2 < nyq
            a$  = fixed$ (a0, 12)
            f$  = fixed$ (f2, 12)
            tp$ = two_pi$
            term$ = a$ + " * exp(- (x - " + t0$ + ")^2 / (2 * " + s$ + "^2)) * sin(" + tp$ + " * " + f$ + " * x)"
            sum$  = sum$ + " + (" + term$ + ")"
        endif
    endfor

    # Gate to [left,right] so we only add inside this frame’s window
    gate$ = "(x >= " + fixed$(left,12) + ") * (x <= " + fixed$(right,12) + ")"
    expr$ = "self + (" + gate$ + ") * (" + sum$ + ")"

    # Single pass for this frame
    selectObject: "Sound resynth"
    Formula: expr$

    # cleanup per-frame objects
    selectObject: "Table picked"
    Remove
    selectObject: "Table suppressed"
    Remove
    selectObject: "Table ltas_vals"
    Remove
    selectObject: ltas
    Remove
    selectObject: sframe
    Remove
    selectObject: "Sound frame"
    Remove
endfor

# Normalize
selectObject: "Sound resynth"
Scale intensity: 70
