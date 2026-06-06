# ============================================================
# Praat AudioTools - Pulsar_Synthesis_Engine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced Pulsar Synthesis engine inspired by Curtis Roads'
#   pulsar synthesis technique (Roads, 2001). Generates sounds
#   ranging from pitched tones through rhythmic pulsing to
#   complex noise textures by controlling the ratio of pulsaret
#   duty-cycle to inter-onset interval.
#
#   Implements two synthesis modes:
#     MODE A — Periodic Pulsar Train (regular inter-onset intervals)
#       - Constant or chirped pulse period
#       - Convolution with a Sound loaded from the Praat Objects list
#       - Hanning-windowed pulse shaping (duty cycle control)
#
#     MODE B — Stochastic Pulsar Cloud (Poisson-distributed onsets)
#       - Inter-onset intervals drawn from exponential distribution
#       - Density parameter controls mean onset rate (pulses/sec)
#       - Convolution with a Sound loaded from the Praat Objects list
#       - Hanning-windowed post-convolution shaping
#
#   Additional synthesis controls:
#     - Pulsaret duty cycle: fraction of period occupied by waveform
#     - Global amplitude envelope (cosine fade in/out)
#     - Amplitude modulation (tremolo): rate + depth
#     - Period chirp (MODE A): frequency glide over time
#     - Stochastic pitch scatter (both modes): jitter on period
#
#   Visualization (8 × 5.9 inch canvas, matching Grisey engine):
#     - Title row: preset + parameters
#     - Waveform overview (full duration)
#     - Zoom: start vs end waveforms
#     - Spectrogram with pulse-onset markers
#     - PointProcess overlay on waveform
#     - Stats / summary panel
#     - Legend
#
#   References:
#     - Roads, C. (2001). Microsound. MIT Press.
#     - Roads, C. (1978). Automated Granular Synthesis of Sound.
#       Computer Music Journal.
#     - Gabor, D. (1947). Acoustical Quanta and the Theory of
#       Hearing. Nature.
#     - Roads, C. & Wieneke, P. (1979). Grains, Clouds and
#       Augmented Instruments. ICMC Proceedings.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Generative & Synthesis Systems
# ============================================================

# ============================================================
# FORM
# ============================================================
form Pulsar Synthesis Engine v1.0
    comment === Preset ===
    optionmenu Preset: 2
        option Custom
        option Periodic Tone (harmonic fundamental)
        option Rhythmic Pulse (sub-audio period)
        option Stochastic Cloud (Poisson density)
        option Chirp Sweep (gliding pitch)
        option Tremolo Web (AM texture)
        option Noise Burst (dense stochastic)
    comment === Mode ===
    optionmenu Synthesis_mode: 1
        option Periodic (PointProcess Fill)
        option Stochastic (Poisson Process)
    comment === Timing ===
    positive Duration_s 3
    positive Period_s 0.01
    comment === Stochastic (Mode B only) ===
    positive Density_pulses_per_s 100
    comment === Pulsaret Shape ===
    positive Duty_cycle 0.5
    real Period_jitter_ratio 0.0
    comment === Chirp (Periodic mode only) ===
    boolean Enable_chirp 0
    positive Chirp_end_period_s 0.005
    comment === Amplitude Modulation ===
    boolean Enable_am 0
    real Am_rate_hz 4.0
    real Am_depth 0.5
    comment === Envelope ===
    positive Fade_in_s 0.05
    positive Fade_out_s 0.10
    comment === Output ===
    positive Sample_rate 44100
    boolean Show_visualization 1
endform

# ============================================================
# APPLY PRESETS
# ============================================================

# Defaults (overridden by preset blocks)
enableChirp = enable_chirp
chirpEndPeriod = chirp_end_period_s
enableAM = enable_am
amRate = am_rate_hz
amDepth = am_depth
fadeIn = fade_in_s
fadeOut = fade_out_s
dutyC = duty_cycle
jitter = period_jitter_ratio
synthMode = synthesis_mode
density = density_pulses_per_s

if preset = 2
    # PERIODIC TONE: Short period -> audible pitch ~100 Hz
    presetName$ = "Periodic Tone"
    synthMode = 1
    period_s = 0.01
    dutyC = 0.5
    jitter = 0.0
    enableChirp = 0
    chirpEndPeriod = 0.01
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.03
    fadeOut = 0.10

elsif preset = 3
    # RHYTHMIC PULSE: Long period -> sub-audio rhythm ~4 Hz
    presetName$ = "Rhythmic Pulse"
    synthMode = 1
    period_s = 0.25
    dutyC = 0.15
    jitter = 0.05
    enableChirp = 0
    chirpEndPeriod = 0.25
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.02
    fadeOut = 0.05

elsif preset = 4
    # STOCHASTIC CLOUD: Poisson 100 pulses/s
    presetName$ = "Stochastic Cloud"
    synthMode = 2
    period_s = 0.01
    density = 100
    dutyC = 0.5
    jitter = 0.0
    enableChirp = 0
    chirpEndPeriod = 0.01
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.05
    fadeOut = 0.10

elsif preset = 5
    # CHIRP SWEEP: Period glides 0.02 s -> 0.002 s (50 Hz -> 500 Hz)
    presetName$ = "Chirp Sweep"
    synthMode = 1
    period_s = 0.02
    dutyC = 0.5
    jitter = 0.01
    enableChirp = 1
    chirpEndPeriod = 0.002
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.04
    fadeOut = 0.12

elsif preset = 6
    # TREMOLO WEB: AM at 6 Hz over a stochastic cloud
    presetName$ = "Tremolo Web"
    synthMode = 2
    period_s = 0.008
    density = 150
    dutyC = 0.4
    jitter = 0.0
    enableChirp = 0
    chirpEndPeriod = 0.008
    enableAM = 1
    amRate = 6.0
    amDepth = 0.7
    fadeIn = 0.08
    fadeOut = 0.15

elsif preset = 7
    # NOISE BURST: Very dense Poisson, short duty cycle -> near-noise
    presetName$ = "Noise Burst"
    synthMode = 2
    period_s = 0.005
    density = 400
    dutyC = 0.8
    jitter = 0.0
    enableChirp = 0
    chirpEndPeriod = 0.005
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.01
    fadeOut = 0.04

else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================
piVal = 3.14159265358979
sr = sample_rate
duration = duration_s
basePeriod = period_s
nyquist = sr / 2

# Duty cycle: clamp to (0,1)
if dutyC <= 0
    dutyC = 0.01
endif
if dutyC >= 1
    dutyC = 0.99
endif

# Fade clamp
if fadeIn < 0.005
    fadeIn = 0.005
endif
if fadeIn > duration * 0.4
    fadeIn = duration * 0.4
endif
if fadeOut < 0.005
    fadeOut = 0.005
endif
if fadeOut > duration * 0.4
    fadeOut = duration * 0.4
endif

# Mode labels
if synthMode = 1
    modeName$ = "Periodic"
else
    modeName$ = "Stochastic"
endif

# ============================================================
# STORE INPUT SOUND REFERENCE
# ============================================================
# User must have a Sound selected before running.
# That Sound will be used as the convolution kernel (pulsaret waveform).
tmp = selected("Sound")

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine: "=== Pulsar Synthesis Engine v1.0 ==="
appendInfoLine: ""
appendInfoLine: "Preset:        ", presetName$
appendInfoLine: "Mode:          ", modeName$
appendInfoLine: "Duration:      ", fixed$(duration, 2), " s"
appendInfoLine: "Base period:   ", fixed$(basePeriod, 5), " s  (",
    ... fixed$(1 / basePeriod, 1), " Hz)"
if synthMode = 2
    appendInfoLine: "Density:       ", fixed$(density, 1), " pulses/s"
endif
appendInfoLine: "Duty cycle:    ", fixed$(dutyC, 2)
appendInfoLine: "Jitter:        ", fixed$(jitter, 3)
if enableChirp = 1 and synthMode = 1
    appendInfoLine: "Chirp end:     ", fixed$(chirpEndPeriod, 5), " s  (",
        ... fixed$(1 / chirpEndPeriod, 1), " Hz)"
endif
if enableAM = 1
    appendInfoLine: "AM:            ", fixed$(amRate, 2),
        ... " Hz, depth ", fixed$(amDepth, 2)
endif
appendInfoLine: "Fade in:       ", fixed$(fadeIn, 3), " s"
appendInfoLine: "Fade out:      ", fixed$(fadeOut, 3), " s"
appendInfoLine: "Sample rate:   ", sr, " Hz"
appendInfoLine: ""

# ============================================================
# STEP 1: Build PointProcess (pulse onsets)
# ============================================================
appendInfoLine: "[1/5] Building pulse onset process..."

if synthMode = 1
    # --- PERIODIC MODE ---
    # Build the pulse train via Fill on an empty PointProcess.
    # If chirp is on, we manually place pulses at chirped intervals.

    if enableChirp = 1 and chirpEndPeriod > 0 and chirpEndPeriod <> basePeriod
        # Chirped periodic train: period varies linearly from
        # basePeriod (t=0) to chirpEndPeriod (t=duration).
        # Place pulses one by one.
        Create empty PointProcess: "pulsar_pp", 0, duration
        pp = selected("PointProcess")

        t_now = 0
        pulseCount = 0
        while t_now < duration
            Add point: t_now
            pulseCount = pulseCount + 1

            # Linear interpolation of period at this moment
            frac = t_now / duration
            p_now = basePeriod + (chirpEndPeriod - basePeriod) * frac

            # Optional jitter
            if jitter > 0
                jitterAmt = randomGauss(0, p_now * jitter)
                p_now = p_now + jitterAmt
                if p_now < 0.0001
                    p_now = 0.0001
                endif
            endif

            t_now = t_now + p_now
        endwhile

    elsif jitter > 0
        # Periodic with jitter: place pulses manually
        Create empty PointProcess: "pulsar_pp", 0, duration
        pp = selected("PointProcess")

        t_now = 0
        pulseCount = 0
        while t_now < duration
            Add point: t_now
            pulseCount = pulseCount + 1

            p_now = basePeriod + randomGauss(0, basePeriod * jitter)
            if p_now < 0.0001
                p_now = 0.0001
            endif
            t_now = t_now + p_now
        endwhile

    else
        # Clean periodic: use built-in Fill
        Create empty PointProcess: "pulsar_pp", 0, duration
        pp = selected("PointProcess")
        Fill: 0, 0, basePeriod
        pulseCount = Get number of points
    endif

    appendInfoLine: "  Placed ", pulseCount, " pulses (periodic)"

else
    # --- STOCHASTIC MODE (Poisson) ---
    Create Poisson process: "pulsar_pp", 0, duration, density
    pp = selected("PointProcess")
    pulseCount = Get number of points
    appendInfoLine: "  Placed ", pulseCount, " pulses (Poisson, density=",
        ... fixed$(density, 1), " /s)"
endif

appendInfoLine: "  Mean IOI: ", fixed$(duration / pulseCount * 1000, 2), " ms"
appendInfoLine: ""

# ============================================================
# STEP 2: Convert PointProcess to pulse-train Sound
# ============================================================
appendInfoLine: "[2/5] Generating pulse-train sound..."

selectObject: pp
# adaptFactor=1.0 means amplitude scales with local IOI (natural)
# maximumPeriod=2000 Hz ceiling -> any pulse below 0.0005 s skipped
To Sound (pulse train): sr, 1, 0.05, 2000
pulseTrain = selected("Sound")

appendInfoLine: "  Pulse train created (", sr, " Hz)"
appendInfoLine: ""

# ============================================================
# STEP 3: Apply Hanning window (duty-cycle shaping)
# ============================================================
appendInfoLine: "[3/5] Shaping pulsarets (duty cycle = ",
    ... fixed$(dutyC, 2), ")..."

# The Hanning window shortens each pulsaret relative to the IOI.
# Praat's Multiply by window operates on the whole signal;
# instead, we modulate the pulse train with a duty-cycle envelope
# built from the PointProcess so each pulsaret fades within
# dutyC * IOI.  We approximate this by multiplying by a
# repeating raised-cosine gate derived from the PointProcess.

# Duty-cycle gate: for each pulse at time t_k, the gate is
#   g(t) = 0.5*(1 - cos(pi*(t-t_k)/w))  for  t in [t_k, t_k+w]
#   g(t) = 0                              otherwise
# where  w = dutyC * IOI_k
# We build this as a formula Sound, then multiply.

durStr$ = fixed$(duration, 10)
dutyStr$ = fixed$(dutyC, 8)
piStr$ = fixed$(piVal, 14)

# --- Build duty-cycle gate from PointProcess time table ---
# For efficiency, use a formula that computes the gate sample-by-sample.
# We iterate over all pulses and accumulate gate contributions.

selectObject: pulseTrain
Copy: "gate_tmp"
gateSnd = selected("Sound")
Formula: "0"   ; zero out

for k from 1 to pulseCount
    selectObject: pp
    t_k = Get time from index: k

    # Determine window width from next IOI (or remaining duration)
    if k < pulseCount
        selectObject: pp
        t_next = Get time from index: k + 1
        ioi_k = t_next - t_k
    else
        ioi_k = basePeriod
    endif

    w_k = dutyC * ioi_k
    if w_k < 1 / sr
        w_k = 1 / sr
    endif

    t_start = t_k
    t_end = t_k + w_k
    if t_end > duration
        t_end = duration
    endif

    # Accumulate Hanning gate for this pulsaret window
    tkStr$ = fixed$(t_k, 10)
    wkStr$ = fixed$(w_k, 10)
    tendStr$ = fixed$(t_end, 10)

    selectObject: gateSnd
    Formula (part): t_start, t_end, 1, 1,
        ... "self + 0.5 * (1 - cos(" + piStr$
        ... + " * (x - " + tkStr$ + ") / " + wkStr$ + "))"

    # Progress every 50 pulses
    kMod = k - floor(k / 50) * 50
    if kMod = 0 or k = pulseCount
        appendInfoLine: "  ... pulsaret ", k, " / ", pulseCount
    endif
endfor

# Apply gate to pulse train
selectObject: pulseTrain
Formula: "self * object[gateSnd]"

removeObject: gateSnd

appendInfoLine: "  Duty-cycle shaping complete."
appendInfoLine: ""

# ============================================================
# STEP 4: Convolve with input Sound (pulsaret timbre)
# ============================================================
appendInfoLine: "[4/5] Convolving with pulsaret waveform..."

# Select pulseTrain + input sound, then convolve
selectObject: tmp
plusObject: pulseTrain
Convolve: "peak 0.99", "zero"
convolved = selected("Sound")

removeObject: pulseTrain

appendInfoLine: "  Convolution done."
appendInfoLine: ""

# ============================================================
# STEP 5: Envelope + AM + normalize
# ============================================================
appendInfoLine: "[5/5] Applying envelope, AM, normalization..."

selectObject: convolved

# Truncate to intended duration (convolution may extend it)
Extract part: 0, duration, "rectangular", 1, "no"
shaped = selected("Sound")
removeObject: convolved

# --- Cosine fade in/out ---
fadeInStr$ = fixed$(fadeIn, 10)
fadeOutStart = duration - fadeOut
fadeOutStartStr$ = fixed$(fadeOutStart, 10)
fadeOutStr$ = fixed$(fadeOut, 10)

selectObject: shaped
Formula: "self * (if x < " + fadeInStr$
    ... + " then 0.5 - 0.5 * cos(" + piStr$
    ... + " * x / " + fadeInStr$ + ")"
    ... + " else (if x > " + fadeOutStartStr$
    ... + " then 0.5 + 0.5 * cos(" + piStr$
    ... + " * (x - " + fadeOutStartStr$
    ... + ") / " + fadeOutStr$ + ")"
    ... + " else 1 fi) fi)"

appendInfoLine: "  Fade in: ", fixed$(fadeIn, 3), " s"
appendInfoLine: "  Fade out: ", fixed$(fadeOut, 3), " s"

# --- Amplitude Modulation (tremolo) ---
if enableAM = 1
    amRateStr$ = fixed$(amRate, 8)
    amDepthStr$ = fixed$(amDepth, 8)

    selectObject: shaped
    Formula: "self * (1 + " + amDepthStr$
        ... + " * sin(2 * " + piStr$ + " * "
        ... + amRateStr$ + " * x))"

    appendInfoLine: "  AM: ", fixed$(amRate, 2),
        ... " Hz, depth ", fixed$(amDepth, 2)
endif

# --- Normalize ---
selectObject: shaped
Scale peak: 0.95
finalName$ = "Pulsar_" + presetName$ + "_" + modeName$
Rename: finalName$
finalOutput = selected("Sound")

appendInfoLine: "  Output: ", finalName$
appendInfoLine: ""

# ============================================================
# VISUALIZATION
# ============================================================
if show_visualization = 1
    appendInfoLine: "[Viz] Building visualization..."
    
    Erase all

    # Spectrogram parameters (narrow-band for partial resolution)
    specWindow = 0.03
    specMaxFreq = min(4000, nyquist)

    selectObject: finalOutput
    To Spectrogram: specWindow, specMaxFreq, 0.002, 20, "Gaussian"
    specGram = selected("Spectrogram")

    # ==========================================================
    # TITLE (matches Grisey engine: outer 0,8 / 0,0.55)
    # ==========================================================
    Select outer viewport: 0, 8, 0, 0.85
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.90, "half",
        ... "##Pulsar Synthesis Engine v1.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.28, "half",
        ... presetName$ + " | " + modeName$ + " | T="
        ... + fixed$(basePeriod * 1000, 2) + " ms"
        ... + " | duty=" + fixed$(dutyC, 2)
        ... + " | " + fixed$(duration, 1) + " s"

    # ==========================================================
    # WAVEFORM OVERVIEW (full duration) outer 0,8 / 0.6,2.2
    # ==========================================================
    Select outer viewport: 0, 8, 0.6, 2.2
    Select inner viewport: 0.8, 7.5, 0.7, 2.15

    selectObject: finalOutput
    Colour: "{0.2, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Overlay pulse onset markers (vertical tick lines at each pulse onset)
    # Draw thin markers for first 200 pulses to avoid overplotting

    ovAmp = Get maximum: 0, 0, "Sinc70"
    ovMin = Get minimum: 0, 0, "Sinc70"
    absOvAmp = ovAmp
    if ovMin < 0
        absOvMin = -ovMin
    else
        absOvMin = ovMin
    endif
    if absOvMin > absOvAmp
        absOvAmp = absOvMin
    endif
    if absOvAmp < 0.001
        absOvAmp = 0.001
    endif

    Axes: 0, duration, -absOvAmp, absOvAmp

    maxMarkersToShow = 200
    if pulseCount < maxMarkersToShow
        maxMarkersToShow = pulseCount
    endif

    for k from 1 to maxMarkersToShow
        selectObject: pp
        tk = Get time from index: k
        # Tick line: short vertical mark at 80% of amplitude range
        Colour: "{0.8, 0.55, 0.15}"
        Line width: 1
        selectObject: finalOutput
        Draw line: tk, absOvAmp * 0.6, tk, absOvAmp * 0.95
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Waveform Overview with Pulse Onsets (orange)"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"

    # ==========================================================
    # SPECTROGRAM (main panel) outer 0,8 / 2.3,4.1
    # ==========================================================
    Select outer viewport: 0, 8, 2.3, 4.1
    Select inner viewport: 0.8, 7.5, 2.4, 4.05

    selectObject: specGram
    Paint: 0, 0, 0, specMaxFreq, 100, "yes", 50, 6, 0, "no"

    # Overlay vertical onset lines on spectrogram
    Axes: 0, duration, 0, specMaxFreq

    for k from 1 to maxMarkersToShow
        selectObject: pp
        tk = Get time from index: k
        Colour: "{0.85, 0.65, 0.20}"
        Line width: 1
        Draw line: tk, 0, tk, specMaxFreq * 0.08
    endfor

    # If chirp: overlay chirp frequency curve
    if enableChirp = 1 and synthMode = 1
        Colour: "{0.9, 0.3, 0.1}"
        Line width: 2
        nCurvePoints = 60
        prevT = 0
        prevF = 1 / basePeriod
        for cp from 1 to nCurvePoints
            t_cp = cp / nCurvePoints * duration
            frac_cp = t_cp / duration
            p_cp = basePeriod + (chirpEndPeriod - basePeriod) * frac_cp
            f_cp = 1 / p_cp
            if f_cp <= specMaxFreq and prevF <= specMaxFreq
                Draw line: prevT, prevF, t_cp, f_cp
            endif
            prevT = t_cp
            prevF = f_cp
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Spectrogram with Onset Markers"
    Marks left every: 1, 500, "yes", "yes", "no"

    removeObject: specGram

    # ==========================================================
    # WAVEFORM ZOOMS: Start vs End (outer 0,4 and 4,8 / 4.2,5.05)
    # ==========================================================
    zoomDur = 0.05
    if zoomDur > duration * 0.15
        zoomDur = duration * 0.15
    endif
    if zoomDur < 0.005
        zoomDur = 0.005
    endif

    # Compute shared amplitude range for both panels
    selectObject: finalOutput
    sm1 = Get maximum: fadeIn, fadeIn + zoomDur, "Sinc70"
    sm2 = Get minimum: fadeIn, fadeIn + zoomDur, "Sinc70"
    zm1 = sm1
    if sm2 < 0
        sm2neg = -sm2
    else
        sm2neg = sm2
    endif
    if sm2neg > zm1
        zm1 = sm2neg
    endif

    em1 = Get maximum: duration - fadeOut - zoomDur, duration - fadeOut, "Sinc70"
    em2 = Get minimum: duration - fadeOut - zoomDur, duration - fadeOut, "Sinc70"
    zm2 = em1
    if em2 < 0
        em2neg = -em2
    else
        em2neg = em2
    endif
    if em2neg > zm2
        zm2 = em2neg
    endif

    if zm1 > zm2
        zAmp = zm1 * 1.1
    else
        zAmp = zm2 * 1.1
    endif
    if zAmp < 0.001
        zAmp = 0.001
    endif

    # Start zoom (harmonic / coherent state)
    Select outer viewport: 0, 4, 4.2, 5.05
    Select inner viewport: 0.8, 3.7, 4.25, 5.0

    selectObject: finalOutput
    Colour: "{0.3, 0.5, 0.8}"
    Draw: fadeIn, fadeIn + zoomDur, -zAmp, zAmp, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Start: " + fixed$(zoomDur * 1000, 0) + " ms"
    Text left: "yes", "Amp"

    # End zoom (evolved / stochastic state)
    Select outer viewport: 4, 8, 4.2, 5.05
    Select inner viewport: 4.4, 7.5, 4.25, 5.0

    zoomEndStart = duration - fadeOut - zoomDur
    zoomEndEnd = duration - fadeOut

    selectObject: finalOutput
    Colour: "{0.8, 0.4, 0.2}"
    Draw: zoomEndStart, zoomEndEnd, -zAmp, zAmp, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "End: " + fixed$(zoomDur * 1000, 0) + " ms"
    Text left: "yes", "Amp"

    # ==========================================================
    # STATS PANEL (outer 0,8 / 5.1,5.6)
    # ==========================================================
    Select outer viewport: 0, 8, 5.1, 5.6
    Select inner viewport: 0.6, 7.7, 5.15, 5.58
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Pulsar Synthesis Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"

    Text: 0.02, "left", 0.65, "half",
        ... "Mode: " + modeName$
        ... + " | Preset: " + presetName$
        ... + " | Duration: " + fixed$(duration, 2) + " s"
        ... + " | SR: " + string$(sr) + " Hz"
    Text: 0.02, "left", 0.42, "half",
        ... "Period: " + fixed$(basePeriod * 1000, 3) + " ms"
        ... + " (" + fixed$(1 / basePeriod, 1) + " Hz)"
        ... + " | Duty: " + fixed$(dutyC, 2)
        ... + " | Jitter: " + fixed$(jitter, 3)
        ... + " | Pulses: " + string$(pulseCount)
    if enableAM = 1
        amInfoStr$ = "AM: " + fixed$(amRate, 2) + " Hz (depth " + fixed$(amDepth, 2) + ")"
    else
        amInfoStr$ = "AM: off"
    endif
    if enableChirp = 1 and synthMode = 1
        chirpInfoStr$ = "Chirp: " + fixed$(1/basePeriod, 1) + " -> " + fixed$(1/chirpEndPeriod, 1) + " Hz"
    else
        chirpInfoStr$ = "Chirp: off"
    endif
    Text: 0.02, "left", 0.19, "half",
        ... chirpInfoStr$
        ... + " | " + amInfoStr$
        ... + " | Fade in: " + fixed$(fadeIn, 3) + " s"
        ... + " / out: " + fixed$(fadeOut, 3) + " s"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ==========================================================
    # LEGEND (outer 0,8 / 5.65,5.95)
    # ==========================================================
    Select outer viewport: 0, 8, 5.65, 5.95
    Axes: 0, 1, 0, 1
    Font size: 6

    Colour: "{0.2, 0.45, 0.75}"
    Draw line: 0.02, 0.5, 0.06, 0.5
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Waveform"

    Colour: "{0.8, 0.55, 0.15}"
    Draw line: 0.20, 0.5, 0.24, 0.5
    Colour: "Black"
    Text: 0.25, "left", 0.5, "half", "Pulse onsets"

    Colour: "{0.3, 0.5, 0.8}"
    Draw line: 0.42, 0.5, 0.46, 0.5
    Colour: "Black"
    Text: 0.47, "left", 0.5, "half", "Start zoom"

    Colour: "{0.8, 0.4, 0.2}"
    Draw line: 0.60, 0.5, 0.64, 0.5
    Colour: "Black"
    Text: 0.65, "left", 0.5, "half", "End zoom"

    if enableChirp = 1 and synthMode = 1
        Colour: "{0.9, 0.3, 0.1}"
        Draw line: 0.78, 0.5, 0.82, 0.5
        Colour: "Black"
        Text: 0.83, "left", 0.5, "half", "Chirp curve"
    endif

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete."
    appendInfoLine: ""
endif

# ============================================================
# CLEANUP + PLAY
# ============================================================
removeObject: pp

selectObject: finalOutput
Play

appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: ""
appendInfoLine: "--- Compositional Notes ---"
appendInfoLine: "Pulsar synthesis spans the full perceptual continuum:"
appendInfoLine: "  - Short period (< 20 ms) -> pitched tone region"
appendInfoLine: "  - Medium period (20-200 ms) -> transition texture"
appendInfoLine: "  - Long period (> 200 ms) -> rhythmic pulse / rhythm"
appendInfoLine: "  - Duty cycle < 0.2 -> sparse clicks / sparser texture"
appendInfoLine: "  - Duty cycle > 0.7 -> overlapping, washy texture"
appendInfoLine: "  - Poisson mode -> stochastic cloud / granular noise"
appendInfoLine: "  - Chirp sweep -> gliding pitch / spectral smear"
appendInfoLine: "  - Combine with AM -> tremolo / formant-like modulation"
appendInfoLine: ""
appendInfoLine: "Suggested uses:"
appendInfoLine: "  - Cross-synthesis: use musical sounds as pulsaret kernel"
appendInfoLine: "  - Rhythm-to-pitch continuum exploration"
appendInfoLine: "  - Stochastic textures for electroacoustic composition"
appendInfoLine: "  - Layering with Grisey Spectral Becoming Engine output"
