# ============================================================
# Praat AudioTools - Pulsar_Synthesis_Engine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (reviewed 2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pulsar synthesis using a selected Sound as the pulsaret/timbre kernel.
#   The engine separates four stages explicitly:
#       1. onset process (periodic/chirped/jittered or Poisson),
#       2. band-limited impulse train,
#       3. convolution with the selected Sound,
#       4. per-IOI Hann duty gate + global envelope / AM.
#
#   The duty cycle is the fraction of each realized inter-onset interval
#   during which the convolved pulsaret remains active. The Hann gate is
#   applied AFTER convolution, so changing duty cycle changes the sound.
#
#   Visualization is mechanism-first rather than result-first:
#       A. realized onset intervals versus the generating rule,
#       B. actual duty-cycle gate inside a representative IOI,
#       C. selected kernel plus global envelope / AM controls,
#       D. measured output waveform, followed by process/QC summary.
#
# References:
#   Roads, C. (2001). Microsound. MIT Press.
#   Roads, C. (1978). Automated Granular Synthesis of Sound.
#   Gabor, D. (1947). Acoustical Quanta and the Theory of Hearing.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#
# Category: Generative & Synthesis Systems
# ============================================================

# ============================================================
# COMPACT FORM
# ============================================================
form Pulsar Synthesis Engine v1.1
    optionmenu Preset 2
        option Custom
        option Periodic Tone (harmonic fundamental)
        option Rhythmic Pulse (sub-audio period)
        option Stochastic Cloud (Poisson density)
        option Chirp Sweep (gliding pitch)
        option Tremolo Web (AM texture)
        option Noise Burst (dense stochastic)

    optionmenu Synthesis_mode 1
        option Periodic
        option Stochastic Poisson

    positive Duration_s 3
    positive Period_s 0.01
    positive Density_pulses_per_s 100
    positive Duty_cycle 0.5

    boolean Edit_details 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS
# ============================================================
period_jitter_ratio = 0.0
enable_chirp = 0
chirp_end_period_s = 0.005
enable_am = 0
am_rate_hz = 4.0
am_depth = 0.5
fade_in_s = 0.05
fade_out_s = 0.10
sample_rate_hz = 44100
output_peak = 0.95
random_seed = 0

# ============================================================
# OPTIONAL COMPACT ADVANCED PAGE
# ============================================================
if edit_details
    beginPause: "Pulsar Synthesis - Details"
        real: "Periodic IOI jitter ratio", period_jitter_ratio
        boolean: "Enable periodic chirp", enable_chirp
        positive: "Chirp end period (s)", chirp_end_period_s
        boolean: "Enable amplitude modulation", enable_am
        real: "AM rate (Hz)", am_rate_hz
        real: "AM depth", am_depth
        real: "Fade in (s)", fade_in_s
        real: "Fade out (s)", fade_out_s
        integer: "Sample rate (Hz)", sample_rate_hz
        real: "Output peak", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ============================================================
# PRESETS
# ============================================================
presetName$ = "Custom"
synthMode = synthesis_mode
duration = duration_s
basePeriod = period_s
density = density_pulses_per_s
dutyC = duty_cycle
jitter = period_jitter_ratio
enableChirp = enable_chirp
chirpEndPeriod = chirp_end_period_s
enableAM = enable_am
amRate = am_rate_hz
amDepth = am_depth
fadeIn = fade_in_s
fadeOut = fade_out_s
sr = sample_rate_hz
outPeak = output_peak
seed = random_seed

if preset = 2
    presetName$ = "Periodic Tone"
    synthMode = 1
    basePeriod = 0.01
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
    presetName$ = "Rhythmic Pulse"
    synthMode = 1
    basePeriod = 0.25
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
    presetName$ = "Stochastic Cloud"
    synthMode = 2
    density = 100
    dutyC = 0.5
    jitter = 0.0
    enableChirp = 0
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.05
    fadeOut = 0.10

elsif preset = 5
    presetName$ = "Chirp Sweep"
    synthMode = 1
    basePeriod = 0.02
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
    presetName$ = "Tremolo Web"
    synthMode = 2
    density = 150
    dutyC = 0.4
    jitter = 0.0
    enableChirp = 0
    enableAM = 1
    amRate = 6.0
    amDepth = 0.7
    fadeIn = 0.08
    fadeOut = 0.15

elsif preset = 7
    presetName$ = "Noise Burst"
    synthMode = 2
    density = 400
    dutyC = 0.8
    jitter = 0.0
    enableChirp = 0
    enableAM = 0
    amRate = 0
    amDepth = 0
    fadeIn = 0.01
    fadeOut = 0.04
endif

# ============================================================
# VALIDATION / LABELS
# ============================================================
piVal = 3.141592653589793
nyquist = sr / 2

if duration <= 0 or duration > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sr < 8000 or sr > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if basePeriod <= 0
    exitScript: "Periodic period must be greater than zero."
endif
if density <= 0
    exitScript: "Poisson density must be greater than zero."
endif
if dutyC <= 0 or dutyC > 1
    exitScript: "Duty cycle must be > 0 and <= 1."
endif
if jitter < 0 or jitter > 0.95
    exitScript: "Periodic IOI jitter ratio must be between 0 and 0.95."
endif
if chirpEndPeriod <= 0
    exitScript: "Chirp end period must be greater than zero."
endif
if amRate < 0
    exitScript: "AM rate cannot be negative."
endif
if amDepth < 0 or amDepth > 1
    exitScript: "AM depth must be between 0 and 1."
endif
if fadeIn < 0 or fadeOut < 0
    exitScript: "Fade times cannot be negative."
endif
if outPeak <= 0 or outPeak > 1
    exitScript: "Output peak must be > 0 and <= 1."
endif
if seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if fadeIn > duration * 0.45
    fadeIn = duration * 0.45
endif
if fadeOut > duration * 0.45
    fadeOut = duration * 0.45
endif

if synthMode = 1
    modeName$ = "Periodic"
    minRequestedPeriod = basePeriod
    if enableChirp = 1 and chirpEndPeriod < minRequestedPeriod
        minRequestedPeriod = chirpEndPeriod
    endif
    if 1 / minRequestedPeriod > nyquist * 0.95
        exitScript: "Requested periodic pulse rate exceeds 95% of Nyquist. Increase the period or sample rate."
    endif
else
    modeName$ = "Stochastic Poisson"
endif

if seed > 0
    random_initializeWithSeedUnsafelyButPredictably (seed)
endif

# ============================================================
# SELECTED INPUT SOUND / WORKING KERNEL
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Pulsar Synthesis Engine: select exactly ONE Sound object as the pulsaret/timbre kernel."
endif

inputSound = selected("Sound")
inputName$ = selected$("Sound")
inputChannels = Get number of channels
inputSR = Get sampling frequency
inputStart = Get start time
inputEnd = Get end time
inputDuration = inputEnd - inputStart
inputPeak = Get absolute extremum: 0, 0, "None"

if inputDuration <= 0
    exitScript: "The selected kernel Sound has no usable duration."
endif
if inputPeak = 0
    exitScript: "The selected kernel Sound is silent."
endif

# Zero-shift a copy so convolution begins at each event time.
selectObject: inputSound
Extract part: inputStart, inputEnd, "rectangular", 1, "no"
kernelWork = selected("Sound")
Rename: "pulsar_kernel_work"

if inputSR <> sr
    Resample: sr, 50
    kernelResampled = selected("Sound")
    removeObject: kernelWork
    kernelWork = kernelResampled
    Rename: "pulsar_kernel_work"
endif

selectObject: kernelWork
kernelDuration = Get total duration
kernelPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine: "=== Pulsar Synthesis Engine v1.1 ==="
appendInfoLine: "Preset:        ", presetName$
appendInfoLine: "Mode:          ", modeName$
appendInfoLine: "Duration:      ", fixed$(duration, 3), " s"
if synthMode = 1
    appendInfoLine: "Period:        ", fixed$(basePeriod * 1000, 3), " ms (", fixed$(1/basePeriod, 2), " Hz)"
    if enableChirp = 1
        appendInfoLine: "Chirp:         ", fixed$(basePeriod * 1000, 3), " -> ", fixed$(chirpEndPeriod * 1000, 3), " ms"
    endif
    appendInfoLine: "IOI jitter:    ", fixed$(jitter, 3)
else
    appendInfoLine: "Density:       ", fixed$(density, 2), " pulses/s; expected IOI ", fixed$(1000/density, 3), " ms"
endif
appendInfoLine: "Duty cycle:    ", fixed$(dutyC, 3)
appendInfoLine: "Kernel:        ", inputName$, " | ", inputChannels, " ch | ", fixed$(kernelDuration*1000,2), " ms"
appendInfoLine: "Sample rate:   ", sr, " Hz"
appendInfoLine: ""

# ============================================================
# STEP 1: ONSET PROCESS
# ============================================================
appendInfoLine: "[1/5] Building onset process..."
minIOI = 2 / sr
timingClampCount = 0

if synthMode = 1
    Create empty PointProcess: "pulsar_pp", 0, duration
    pp = selected("PointProcess")

    if enableChirp = 0 and jitter = 0
        Fill: 0, 0, basePeriod
        pulseCount = Get number of points
    else
        t_now = 0
        pulseCount = 0
        while t_now < duration
            Add point: t_now
            pulseCount = pulseCount + 1

            if enableChirp = 1
                frac = t_now / duration
                p_now = basePeriod + (chirpEndPeriod - basePeriod) * frac
            else
                p_now = basePeriod
            endif

            if jitter > 0
                p_now = p_now + randomGauss(0, p_now * jitter)
            endif
            if p_now < minIOI
                p_now = minIOI
                timingClampCount = timingClampCount + 1
            endif
            t_now = t_now + p_now
        endwhile
    endif
else
    Create Poisson process: "pulsar_pp", 0, duration, density
    pp = selected("PointProcess")
    pulseCount = Get number of points
endif

# Realized IOI statistics
sumIOI = 0
sumIOI2 = 0
minRealIOI = undefined
maxRealIOI = undefined
if pulseCount > 1
    for k from 1 to pulseCount - 1
        selectObject: pp
        tk0 = Get time from index: k
        tk1 = Get time from index: k + 1
        dtk = tk1 - tk0
        sumIOI = sumIOI + dtk
        sumIOI2 = sumIOI2 + dtk * dtk
        if k = 1 or dtk < minRealIOI
            minRealIOI = dtk
        endif
        if k = 1 or dtk > maxRealIOI
            maxRealIOI = dtk
        endif
    endfor
    meanIOI = sumIOI / (pulseCount - 1)
    varIOI = sumIOI2 / (pulseCount - 1) - meanIOI * meanIOI
    if varIOI < 0
        varIOI = 0
    endif
    sdIOI = sqrt(varIOI)
    if meanIOI > 0
        ioiCV = sdIOI / meanIOI
    else
        ioiCV = undefined
    endif
else
    if synthMode = 1
        meanIOI = basePeriod
    else
        meanIOI = 1 / density
    endif
    sdIOI = undefined
    ioiCV = undefined
    minRealIOI = meanIOI
    maxRealIOI = meanIOI
endif

realizedRate = pulseCount / duration
appendInfoLine: "  Pulses:       ", pulseCount
if pulseCount > 1
    appendInfoLine: "  Mean IOI:     ", fixed$(meanIOI*1000, 3), " ms"
    appendInfoLine: "  IOI CV:       ", fixed$(ioiCV, 3)
else
    appendInfoLine: "  Mean IOI:     unavailable (fewer than two pulses)"
endif
appendInfoLine: ""

# ============================================================
# STEP 2: BAND-LIMITED IMPULSE TRAIN
# ============================================================
appendInfoLine: "[2/5] Creating band-limited impulse train..."
selectObject: pp
# Adaptation factor 1.0 means pulse heights are NOT attenuated after gaps.
To Sound (pulse train): sr, 1, 0.05, 2000
pulseTrain = selected("Sound")
appendInfoLine: "  PointProcess -> sinc-band-limited pulse train"
appendInfoLine: ""

# ============================================================
# STEP 3: CONVOLUTION WITH SELECTED KERNEL
# ============================================================
appendInfoLine: "[3/5] Convolving pulse train with selected kernel..."
selectObject: pulseTrain
plusObject: kernelWork
# 'sum' is the appropriate discrete filtering convention for an impulse
# train convolved with a finite impulse response / selected sound.
Convolve: "sum", "zero"
convolved = selected("Sound")

# Convolution extends the time domain; return to requested duration and zero.
Extract part: 0, duration, "rectangular", 1, "no"
preGate = selected("Sound")
removeObject: convolved
appendInfoLine: "  Convolution complete; duration restored to ", fixed$(duration,3), " s"
appendInfoLine: ""

# ============================================================
# STEP 4: TRUE PULSAR DUTY GATE (AFTER CONVOLUTION)
# ============================================================
appendInfoLine: "[4/5] Applying per-IOI Hann duty gate..."

Create Sound from formula: "pulsar_duty_gate", 1, 0, duration, sr, "0"
gateSnd = selected("Sound")

activeSum = 0
activeCount = 0
underResolvedGateCount = 0
repIndex = 1
if pulseCount > 1
    repIndex = floor((pulseCount - 1) / 2) + 1
endif
repOnset = 0
repIOI = meanIOI
repActive = dutyC * repIOI

for k from 1 to pulseCount
    selectObject: pp
    t_k = Get time from index: k

    if k < pulseCount
        t_next = Get time from index: k + 1
        ioi_k = t_next - t_k
    elsif pulseCount > 1
        t_prev = Get time from index: k - 1
        ioi_k = t_k - t_prev
    elsif synthMode = 1
        ioi_k = basePeriod
    else
        ioi_k = 1 / density
    endif

    active_k = dutyC * ioi_k
    # Keep the gate inside its realized IOI. Very short stochastic IOIs can
    # be under-resolved; we report them rather than changing the onset model.
    if active_k > ioi_k
        active_k = ioi_k
    endif
    if active_k < 4 / sr
        underResolvedGateCount = underResolvedGateCount + 1
    endif
    if active_k < 1 / sr
        active_k = 1 / sr
        if active_k > ioi_k
            active_k = ioi_k
        endif
    endif

    if k = repIndex
        repOnset = t_k
        repIOI = ioi_k
        repActive = active_k
    endif

    activeSum = activeSum + active_k
    activeCount = activeCount + 1

    gateEnd = t_k + active_k
    if gateEnd > duration
        gateEnd = duration
    endif

    if gateEnd > t_k and active_k > 0
        tStr$ = fixed$(t_k, 12)
        wStr$ = fixed$(active_k, 12)
        selectObject: gateSnd
        Formula (part): t_k, gateEnd, 1, 1,
            ... "self + 0.5 * (1 - cos(2 * pi * (x - " + tStr$ + ") / " + wStr$ + "))"
    endif
endfor

if activeCount > 0
    meanActive = activeSum / activeCount
else
    meanActive = dutyC * meanIOI
endif
if meanActive > 0
    kernelToActiveRatio = kernelDuration / meanActive
else
    kernelToActiveRatio = undefined
endif

# Prevent any numerical overlap from exceeding unity.
selectObject: gateSnd
Formula: "min(self, 1)"

selectObject: preGate
Formula: "self * object[gateSnd,1,col]"
gated = selected("Sound")

appendInfoLine: "  Mean active window: ", fixed$(meanActive*1000, 3), " ms"
appendInfoLine: "  Duty ratio:         ", fixed$(dutyC, 3)
appendInfoLine: "  Kernel/mean-active: ", fixed$(kernelToActiveRatio, 3)
if kernelToActiveRatio > 1
    appendInfoLine: "  QC: kernel exceeds the mean duty window; post-convolution tails are intentionally clipped/gated."
endif
if underResolvedGateCount > 0
    appendInfoLine: "  QC: ", underResolvedGateCount, " active windows use fewer than 4 samples."
endif
appendInfoLine: ""

# ============================================================
# STEP 5: GLOBAL ENVELOPE + AM + OUTPUT
# ============================================================
appendInfoLine: "[5/5] Applying global controls..."

fadeInStr$ = fixed$(fadeIn, 12)
fadeOutStart = duration - fadeOut
fadeOutStartStr$ = fixed$(fadeOutStart, 12)
fadeOutStr$ = fixed$(fadeOut, 12)

selectObject: gated
if fadeIn > 0 or fadeOut > 0
    Formula: "self * (if x < " + fadeInStr$
        ... + " and " + fadeInStr$ + " > 0 then 0.5 - 0.5*cos(pi*x/" + fadeInStr$ + ")"
        ... + " else if x > " + fadeOutStartStr$
        ... + " and " + fadeOutStr$ + " > 0 then 0.5 + 0.5*cos(pi*(x-" + fadeOutStartStr$ + ")/" + fadeOutStr$ + ")"
        ... + " else 1 fi fi)"
endif

if enableAM = 1 and amDepth > 0 and amRate > 0
    amRateStr$ = fixed$(amRate, 10)
    amDepthStr$ = fixed$(amDepth, 10)
    Formula: "self * (1 + " + amDepthStr$ + " * sin(2*pi*" + amRateStr$ + "*x))"
endif

preNormPeak = Get absolute extremum: 0, 0, "None"
if normalize_output = 1 and preNormPeak > 0
    Scale peak: outPeak
endif

finalName$ = "Pulsar_" + presetName$ + "_" + modeName$
Rename: finalName$
finalOutput = selected("Sound")
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
outputChannels = Get number of channels

appendInfoLine: "  Pre-normalization peak: ", fixed$(preNormPeak, 6)
appendInfoLine: "  Final peak:             ", fixed$(finalPeak, 6)
appendInfoLine: "  RMS:                    ", fixed$(finalRMS, 6)
appendInfoLine: ""

# ============================================================
# VISUALIZATION: MECHANISM FIRST
# ============================================================
if draw_visualization = 1
    appendInfoLine: "[Viz] Drawing process visualization..."
    Erase all

    # House layout: 8-inch width, explicit strips/panels, fixed scales.
    left = 0.80
    right = 7.55

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.05, 0.33
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.64, "half", "##Pulsar Synthesis Engine v1.1##"

    Select inner viewport: 0.35, 7.65, 0.37, 0.67
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30,0.30,0.36}"
    if synthMode = 1
        timingText$ = "period " + fixed$(basePeriod*1000,2) + " ms"
        if enableChirp = 1
            timingText$ = timingText$ + " -> " + fixed$(chirpEndPeriod*1000,2) + " ms"
        endif
    else
        timingText$ = "Poisson lambda=" + fixed$(density,1) + "/s"
    endif
    Text: 0.5, "centre", 0.62, "half",
        ... presetName$ + " | " + timingText$ + " | duty=" + fixed$(dutyC,2)
        ... + " | kernel=" + inputName$ + " | " + fixed$(duration,2) + " s"

    # ----------------------------------------------------------
    # PROCESS DIAGRAM
    # ----------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.75, 0.98
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.20,0.25,0.34}"
    Text: 0.50, "centre", 0.58, "half",
        ... "ONSET PROCESS  ->  SINC IMPULSES  ->  CONVOLVE h(t)  ->  HANN DUTY GATE  ->  ENVELOPE / AM  ->  OUTPUT"

    # ----------------------------------------------------------
    # PANEL A TITLE: ACTUAL TIMING PROCESS
    # ----------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 1.08, 1.28
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.55, "half", "##A  ONSET PROCESS##  | realized IOIs versus the generating rule"

    Select inner viewport: left, right, 1.35, 2.30
    ioiYMax = maxRealIOI * 1000 * 1.15
    if synthMode = 2
        expectedMs = 1000 / density
        if expectedMs * 2.5 > ioiYMax
            ioiYMax = expectedMs * 2.5
        endif
    else
        requestedMax = basePeriod
        if enableChirp = 1 and chirpEndPeriod > requestedMax
            requestedMax = chirpEndPeriod
        endif
        if requestedMax * 1000 * 1.25 > ioiYMax
            ioiYMax = requestedMax * 1000 * 1.25
        endif
    endif
    if ioiYMax < 1
        ioiYMax = 1
    endif
    Axes: 0, duration, 0, ioiYMax
    Colour: "{0.90,0.90,0.92}"
    Draw rectangle: 0, duration, 0, ioiYMax

    if pulseCount > 1
        plotStep = floor(((pulseCount - 1) + 179) / 180)
        if plotStep < 1
            plotStep = 1
        endif
        prevSet = 0
        for k from 1 to pulseCount - 1
            usePoint = 0
            k0 = k - 1
            if k0 - floor(k0 / plotStep) * plotStep = 0
                usePoint = 1
            endif
            if usePoint = 1
                selectObject: pp
                ta = Get time from index: k
                tb = Get time from index: k + 1
                yms = (tb - ta) * 1000
                if prevSet = 1
                    Colour: "{0.18,0.45,0.72}"
                    Line width: 1.5
                    Draw line: prevT, prevY, ta, yms
                endif
                Colour: "{0.18,0.45,0.72}"
                Draw circle: ta, yms, 0.035
                prevT = ta
                prevY = yms
                prevSet = 1
            endif
        endfor
    endif

    # Model/reference line
    if synthMode = 2
        refMs = 1000 / density
        Colour: "{0.80,0.35,0.18}"
        Line width: 1.5
        Draw line: 0, refMs, duration, refMs
        Font size: 6
        Text: duration * 0.99, "right", refMs, "bottom", "E[IOI] = 1/lambda"
    elsif enableChirp = 1
        Colour: "{0.80,0.35,0.18}"
        Line width: 1.5
        nCurve = 80
        prevT = 0
        prevPms = basePeriod * 1000
        for c from 1 to nCurve
            tc = c / nCurve * duration
            pc = basePeriod + (chirpEndPeriod - basePeriod) * (tc / duration)
            Draw line: prevT, prevPms, tc, pc * 1000
            prevT = tc
            prevPms = pc * 1000
        endfor
    else
        refMs = basePeriod * 1000
        Colour: "{0.80,0.35,0.18}"
        Line width: 1.5
        Draw line: 0, refMs, duration, refMs
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "IOI (ms)"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, max(0.5, duration/6), "yes", "yes", "no"

    # ----------------------------------------------------------
    # PANEL B: PULSAR GEOMETRY / ACTUAL DUTY GATE
    # ----------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.45, 2.65
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.55, "half", "##B  PULSAR GEOMETRY##  | one realized IOI: active Hann pulsaret + silence"

    Select inner viewport: left, right, 2.72, 3.62
    repEnd = repOnset + repIOI
    if repEnd > duration
        repEnd = duration
    endif
    Axes: repOnset, repEnd, 0, 1.05
    Colour: "{0.95,0.95,0.96}"
    Paint rectangle: "{0.95,0.95,0.96}", repOnset, repEnd, 0, 1.05
    selectObject: gateSnd
    Colour: "{0.18,0.55,0.35}"
    Line width: 2
    Draw: repOnset, repEnd, 0, 1.05, "no", "Curve"
    Axes: repOnset, repEnd, 0, 1.05
    activeEnd = repOnset + repActive
    if activeEnd > repEnd
        activeEnd = repEnd
    endif
    Colour: "{0.75,0.32,0.18}"
    Line width: 1
    Draw line: activeEnd, 0, activeEnd, 1.0
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gate"
    Text bottom: "yes", "Time (s)"
    Text: repOnset + 0.5 * repActive, "centre", 0.92, "half", "active = duty x IOI"
    if repEnd > activeEnd
        Text: activeEnd + 0.5 * (repEnd-activeEnd), "centre", 0.15, "half", "silence"
    endif

    # ----------------------------------------------------------
    # PANEL C: INPUT KERNEL + POST CONTROLS
    # ----------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 3.78, 3.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.55, "half", "##C  TIMBRE + POST CONTROL##  | selected h(t), global envelope and AM gain"

    # Kernel waveform (left)
    Select inner viewport: 0.80, 3.88, 4.05, 4.95
    selectObject: kernelWork
    kp = Get absolute extremum: 0, 0, "None"
    if kp < 0.000001
        kp = 1
    endif
    Colour: "{0.38,0.34,0.68}"
    Draw: 0, kernelDuration, -kp, kp, "no", "Curve"
    Axes: 0, kernelDuration, -kp, kp
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Selected kernel h(t)"
    Text bottom: "yes", "Time (s)"

    # Post-control curves (right): E(t) and AM gain.
    Select inner viewport: 4.20, 7.55, 4.05, 4.95
    controlYMax = 1.05
    if enableAM = 1 and 1 + amDepth > controlYMax
        controlYMax = 1 + amDepth + 0.05
    endif
    Axes: 0, duration, 0, controlYMax
    nCtrl = 160
    prevT = 0
    prevEnv = 0
    if fadeIn = 0
        prevEnv = 1
    endif
    prevAM = 1
    for c from 1 to nCtrl
        tc = c / nCtrl * duration
        envc = 1
        if fadeIn > 0 and tc < fadeIn
            envc = 0.5 - 0.5 * cos(piVal * tc / fadeIn)
        elsif fadeOut > 0 and tc > duration - fadeOut
            envc = 0.5 + 0.5 * cos(piVal * (tc - (duration-fadeOut)) / fadeOut)
        endif
        amc = 1
        if enableAM = 1 and amRate > 0 and amDepth > 0
            amc = 1 + amDepth * sin(2*piVal*amRate*tc)
        endif
        Colour: "{0.18,0.55,0.35}"
        Line width: 1.5
        Draw line: prevT, prevEnv, tc, envc
        if enableAM = 1 and amRate > 0 and amDepth > 0
            Colour: "{0.78,0.42,0.18}"
            Draw line: prevT, prevAM, tc, amc
        endif
        prevT = tc
        prevEnv = envc
        prevAM = amc
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text top: "no", "Envelope (green) / AM gain (orange)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # ----------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 5.10, 5.30
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.55, "half", "##D  MEASURED OUTPUT##  | verification after convolution, duty gate and global controls"

    Select inner viewport: left, right, 5.37, 6.30
    waveRange = finalPeak * 1.08
    if waveRange < 0.001
        waveRange = 0.001
    endif
    selectObject: finalOutput
    Colour: "{0.20,0.45,0.75}"
    Draw: 0, duration, -waveRange, waveRange, "no", "Curve"
    Axes: 0, duration, -waveRange, waveRange
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, max(0.5, duration/6), "yes", "yes", "no"

    # ----------------------------------------------------------
    # QC / CONCEPT SUMMARY
    # ----------------------------------------------------------
    Select inner viewport: 0.50, 7.50, 6.48, 7.78
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955,0.955,0.96}", 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##PROCESS / QC##"
    Font size: 6
    Colour: "{0.27,0.27,0.32}"

    if synthMode = 1
        modelStr$ = "Periodic onset model | target start " + fixed$(1/basePeriod,2) + " Hz"
        if enableChirp = 1
            modelStr$ = modelStr$ + " -> " + fixed$(1/chirpEndPeriod,2) + " Hz"
        endif
    else
        modelStr$ = "Homogeneous Poisson onset model | target lambda " + fixed$(density,2) + "/s"
    endif
    Text: 0.02, "left", 0.70, "half", modelStr$

    if pulseCount > 1
        statStr$ = "REALIZED | " + string$(pulseCount) + " pulses | rate " + fixed$(realizedRate,2)
            ... + "/s | mean IOI " + fixed$(meanIOI*1000,2) + " ms | CV " + fixed$(ioiCV,3)
    else
        statStr$ = "REALIZED | " + string$(pulseCount) + " pulse(s) | rate " + fixed$(realizedRate,2) + "/s"
    endif
    Text: 0.02, "left", 0.53, "half", statStr$

    dutyStr$ = "PULSARET | Hann duty " + fixed$(dutyC,3) + " | mean active " + fixed$(meanActive*1000,2)
        ... + " ms | kernel/active " + fixed$(kernelToActiveRatio,2) + " | under-resolved windows " + string$(underResolvedGateCount)
    Text: 0.02, "left", 0.36, "half", dutyStr$

    outputStr$ = "OUTPUT | " + string$(outputChannels) + " ch | peak " + fixed$(finalPeak,4)
        ... + " | RMS " + fixed$(finalRMS,4) + " | pre-norm peak " + fixed$(preNormPeak,4)
        ... + " | SR " + string$(sr) + " Hz"
    Text: 0.02, "left", 0.19, "half", outputStr$

    appendInfoLine: "  Visualization complete."
    appendInfoLine: ""
endif

# ============================================================
# CLEANUP + OPTIONAL PLAY
# ============================================================
removeObject: pp, pulseTrain, kernelWork, gateSnd

selectObject: finalOutput
if play_result = 1
    Play
endif

appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: ""
appendInfoLine: "Pulsar mechanism: onset process -> band-limited impulses -> convolution -> Hann duty gate -> envelope/AM."
