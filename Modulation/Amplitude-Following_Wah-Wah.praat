# ============================================================
# Praat AudioTools - Amplitude-Following_Wah-Wah.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Amplitude-following wah-wah using a FormantGrid resonant filter.
#   A true attack/release envelope follower maps input level to a
#   time-varying filter centre: louder -> higher/brighter, quieter ->
#   lower/darker. The mapping uses a fixed dB range below the observed
#   envelope peak, avoiding min/max normalization of numerical noise.
#
# Changelog v0.5:
#   - Standardized visualization typography/layout to the AudioTools reference:
#     effect-only title, compact metadata subtitle, short panel labels, and a
#     left-aligned Summary block with 6 pt parameter lines. DSP is unchanged.
#
# Changelog v0.4:
#   - Replaced file-wise min/max Intensity normalization with a true
#     attack/release amplitude follower and fixed Envelope_range_dB mapping.
#   - Constant-level material no longer expands tiny numerical variations
#     into a full-range wah sweep.
#   - Added Dry_wet_percent with exact 0% bypass.
#   - Replaced unconditional peak normalization with attenuation-only
#     Safety_peak (0 disables).
#   - Preserves sample rate, start time, duration, and all input channels.
#   - Added Nyquist-aware frequency validation/clamping.
#   - Updated visualization to AudioTools house style and plots the actual
#     envelope control and mapped filter-centre trajectory.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
dur = Get total duration
fs = Get sampling frequency
numChannels = Get number of channels
startTime = Get start time
endTime = Get end time
nyquist = fs / 2

# === Form ===
form Amplitude Following Wah-Wah
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Style 1
        option Classic Guitar (mid-range, sharp)
        option Funky Bass (low-range, thumpy)
        option Subtle Vocal (wide, gentle)
        option Sci-Fi Zap (extreme range, very sharp)
        option Custom (use settings below)

    comment === Custom Filter Settings ===
    positive Custom_min_Hz 400
    positive Custom_max_Hz 2500
    positive Custom_bandwidth_Hz 150

    comment === Envelope Follower ===
    real Attack_ms 8
    real Release_ms 80
    positive Envelope_range_dB 30
    comment (peak = max frequency; range dB below peak = min frequency)

    comment === Mix / Safety ===
    real Dry_wet_percent 100
    comment (0 = exact dry bypass, 100 = full wah)
    real Safety_peak 0.99
    comment (0 disables; otherwise attenuation only)

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if style = 1
    min_cutoff = 400
    max_cutoff = 2500
    bw = 100
    presetName$ = "Classic Guitar"
elsif style = 2
    min_cutoff = 80
    max_cutoff = 800
    bw = 80
    presetName$ = "Funky Bass"
elsif style = 3
    min_cutoff = 500
    max_cutoff = 1500
    bw = 300
    presetName$ = "Subtle Vocal"
elsif style = 4
    min_cutoff = 200
    max_cutoff = 4000
    bw = 50
    presetName$ = "Sci-Fi Zap"
else
    min_cutoff = custom_min_Hz
    max_cutoff = custom_max_Hz
    bw = custom_bandwidth_Hz
    presetName$ = "Custom"
endif

# === Validate / Clamp Parameters ===
attack_ms = max(0, attack_ms)
release_ms = max(0, release_ms)
envelope_range_dB = max(1, envelope_range_dB)
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))
wetAmt = dry_wet_percent / 100

minAllowed = 20
maxAllowed = max(minAllowed + 1, nyquist * 0.95)

if wetAmt > 0
    if min_cutoff < minAllowed
        min_cutoff = minAllowed
    endif
    if max_cutoff > maxAllowed
        max_cutoff = maxAllowed
    endif
    if max_cutoff <= min_cutoff
        exitScript: "Filter range is invalid for this sample rate. Choose a maximum frequency above the minimum and below Nyquist."
    endif

    bw = max(1, bw)
    bw = min(bw, nyquist * 0.9)
endif

# === Info ===
writeInfoLine: "=== Amplitude-Following Wah-Wah v0.4 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", round(fs), " Hz"
appendInfoLine: "Filter range: ", fixed$(min_cutoff, 1), " - ", fixed$(max_cutoff, 1), " Hz"
appendInfoLine: "Bandwidth: ", fixed$(bw, 1), " Hz"
appendInfoLine: "Envelope: attack ", fixed$(attack_ms, 1), " ms | release ", fixed$(release_ms, 1), " ms | range ", fixed$(envelope_range_dB, 1), " dB"
appendInfoLine: "Mix: ", fixed$(dry_wet_percent, 1), "% wet | Safety peak: ", fixed$(safety_peak, 2)
appendInfoLine: ""

# ============================================================
# EXACT DRY BYPASS
# ============================================================
if wetAmt = 0
    selectObject: original
    result = Copy: name$ + "_wah_" + presetName$
    appendInfoLine: "Dry bypass: exact (processing skipped)."

else
    # ========================================================
    # BUILD CHANNEL-SAFE AMPLITUDE CONTROL
    # Square every channel first, then average channels, so opposite-polarity
    # stereo does not cancel in the envelope analysis.
    # ========================================================
    appendInfoLine: "Building attack/release envelope..."

    selectObject: original
    envSquares = Copy: "envSquares"
    Formula: "self^2"

    if numChannels > 1
        selectObject: envSquares
        envInput = Convert to mono
        removeObject: envSquares
    else
        envInput = envSquares
    endif

    selectObject: envInput
    Formula: "sqrt(self)"
    Rename: "envInput"

    # One-pole attack/release follower, evaluated sample by sample.
    attackSec = attack_ms / 1000
    releaseSec = release_ms / 1000
    if attackSec > 0
        alphaA = exp(-1 / (attackSec * fs))
    else
        alphaA = 0
    endif
    if releaseSec > 0
        alphaR = exp(-1 / (releaseSec * fs))
    else
        alphaR = 0
    endif

    selectObject: envInput
    envFollower = Copy: "envFollower"
    alphaAStr$ = fixed$(alphaA, 12)
    alphaRStr$ = fixed$(alphaR, 12)
    envInputIDStr$ = string$(envInput)
    Formula: "if col = 1 then object[" + envInputIDStr$ + ", 1, col] else if object[" + envInputIDStr$ + ", 1, col] > self[col-1] then " + alphaAStr$ + "*self[col-1] + (1-" + alphaAStr$ + ")*object[" + envInputIDStr$ + ", 1, col] else " + alphaRStr$ + "*self[col-1] + (1-" + alphaRStr$ + ")*object[" + envInputIDStr$ + ", 1, col] fi fi"

    selectObject: envFollower
    peakEnv = Get maximum: 0, 0, "None"

    # ========================================================
    # BUILD FORMANTGRID CONTROL
    # ========================================================
    appendInfoLine: "Building resonant filter trajectory..."

    formantGrid = Create FormantGrid: name$ + "_filter", startTime, endTime, 1, min_cutoff, 1000, bw, 50
    selectObject: formantGrid
    Remove formant points between: 1, startTime, endTime
    Remove bandwidth points between: 1, startTime, endTime

    # Up to 5000 control points; normally 5 ms spacing.
    controlStep = 0.005
    nControl = max(2, ceiling(dur / controlStep) + 1)
    nControl = min(5000, nControl)

    ctrlTimes# = zero#(nControl)
    ctrlNorm# = zero#(nControl)
    ctrlFreq# = zero#(nControl)

    minObservedFreq = max_cutoff
    maxObservedFreq = min_cutoff

    for k to nControl
        if nControl > 1
            relTime = (k - 1) * dur / (nControl - 1)
        else
            relTime = 0
        endif
        t = startTime + relTime

        if peakEnv > 1e-15
            selectObject: envFollower
            envVal = Get value at time: 1, t, "Linear"
            envVal = max(envVal, peakEnv * 1e-12)
            relDb = 20 * ln(envVal / peakEnv) / ln(10)
            normVal = (relDb + envelope_range_dB) / envelope_range_dB
            normVal = min(1, max(0, normVal))
        else
            normVal = 0
        endif

        targetFreq = min_cutoff + (max_cutoff - min_cutoff) * normVal

        ctrlTimes#[k] = relTime
        ctrlNorm#[k] = normVal
        ctrlFreq#[k] = targetFreq

        minObservedFreq = min(minObservedFreq, targetFreq)
        maxObservedFreq = max(maxObservedFreq, targetFreq)

        selectObject: formantGrid
        Add formant point: 1, t, targetFreq
        Add bandwidth point: 1, t, bw
    endfor

    appendInfoLine: "Mapped centre range: ", fixed$(minObservedFreq, 1), " - ", fixed$(maxObservedFreq, 1), " Hz"

    # ========================================================
    # APPLY WAH FILTER
    # ========================================================
    appendInfoLine: "Applying FormantGrid filter..."
    selectObject: original
    plusObject: formantGrid
    wetSound = Filter

    # ========================================================
    # DRY/WET MIX
    # ========================================================
    if wetAmt < 1
        selectObject: original
        result = Copy: name$ + "_wah_" + presetName$
        wetIDStr$ = string$(wetSound)
        wetStr$ = fixed$(wetAmt, 12)
        dryStr$ = fixed$(1 - wetAmt, 12)
        selectObject: result
        Formula: "self*" + dryStr$ + " + object[" + wetIDStr$ + ", row, col]*" + wetStr$
    else
        selectObject: wetSound
        result = Copy: name$ + "_wah_" + presetName$
    endif

    # Safety attenuation only: never boost.
    if safety_peak > 0
        selectObject: result
        outPeak = Get absolute extremum: 0, 0, "None"
        if outPeak > safety_peak
            safetyGain = safety_peak / outPeak
            Formula: "self * safetyGain"
            appendInfoLine: "Safety attenuation: ", fixed$(20 * ln(safetyGain) / ln(10), 2), " dB"
        endif
    endif

    # ========================================================
    # VISUALIZATION
    # ========================================================
    if draw_visualization
        Erase all

        # === TITLE ===
        Select outer viewport: 0, 8, 0, 0.5
        Axes: 0, 1, 0, 1
        Font size: 12
        Colour: "Black"
        Text: 0.5, "centre", 0.68, "half", "##Amplitude-Following Wah-Wah##"
        Font size: 7
        Colour: "{0.35, 0.35, 0.52}"
        Text: 0.5, "centre", -1.30, "half",
        ... name$ + "  |  " + presetName$ + "  |  Envelope follower"

        # Input waveform
        Select outer viewport: 0, 8, 0.6, 1.35
        Select inner viewport: 0.6, 7.6, 0.68, 1.27
        selectObject: original
        Colour: "{0.55, 0.55, 0.55}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Input"

        # Output waveform
        Select outer viewport: 0, 8, 1.45, 2.20
        Select inner viewport: 0.6, 7.6, 1.53, 2.12
        selectObject: result
        Colour: "{0.22, 0.46, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Output"
        Text bottom: "yes", "Time (s)"

        # Normalized envelope
        Select outer viewport: 0, 8, 2.35, 3.45
        Select inner viewport: 0.6, 7.6, 2.47, 3.34
        Axes: 0, dur, -0.05, 1.05
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, 0, 1
        Colour: "{0.82, 0.82, 0.82}"
        Dotted line
        Draw line: 0, 0.5, dur, 0.5
        Solid line
        Colour: "{0.48, 0.35, 0.74}"
        Line width: 1.5
        vizStep = max(1, ceiling(nControl / 500))
        prevK = 1
        k = 1 + vizStep
        while k <= nControl
            Draw line: ctrlTimes#[prevK], ctrlNorm#[prevK], ctrlTimes#[k], ctrlNorm#[k]
            prevK = k
            k = k + vizStep
        endwhile
        if prevK < nControl
            Draw line: ctrlTimes#[prevK], ctrlNorm#[prevK], ctrlTimes#[nControl], ctrlNorm#[nControl]
        endif
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Envelope"

        # Filter centre trajectory
        Select outer viewport: 0, 8, 3.60, 4.75
        Select inner viewport: 0.6, 7.6, 3.72, 4.64
        freqMargin = max(10, (max_cutoff - min_cutoff) * 0.08)
        Axes: 0, dur, max(0, min_cutoff - freqMargin), max_cutoff + freqMargin
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, max(0, min_cutoff - freqMargin), max_cutoff + freqMargin
        Colour: "{0.82, 0.82, 0.82}"
        Dotted line
        Draw line: 0, min_cutoff, dur, min_cutoff
        Draw line: 0, max_cutoff, dur, max_cutoff
        Solid line
        Colour: "{0.22, 0.46, 0.82}"
        Line width: 1.5
        prevK = 1
        k = 1 + vizStep
        while k <= nControl
            Draw line: ctrlTimes#[prevK], ctrlFreq#[prevK], ctrlTimes#[k], ctrlFreq#[k]
            prevK = k
            k = k + vizStep
        endwhile
        if prevK < nControl
            Draw line: ctrlTimes#[prevK], ctrlFreq#[prevK], ctrlTimes#[nControl], ctrlFreq#[nControl]
        endif
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Centre (Hz)"
        Text bottom: "yes", "Time (s)"

        # === SUMMARY ===
        Select outer viewport: 0, 8, 4.90, 5.60
        Select inner viewport: 0.6, 7.7, 4.95, 5.55
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.80, "half", "##Summary##"
        Font size: 6
        Colour: "{0.28, 0.28, 0.28}"
        Text: 0.02, "left", 0.50, "half",
        ... "Range: " + fixed$(min_cutoff, 0) + "-" + fixed$(max_cutoff, 0) + " Hz"
        ... + "  |  Bandwidth: " + fixed$(bw, 0) + " Hz"
        ... + "  |  Attack/Release: " + fixed$(attack_ms, 0) + "/" + fixed$(release_ms, 0) + " ms"
        Text: 0.02, "left", 0.18, "half",
        ... "Envelope range: " + fixed$(envelope_range_dB, 0) + " dB"
        ... + "  |  Wet: " + fixed$(dry_wet_percent, 0) + "%"
        ... + "  |  Safety: " + fixed$(safety_peak, 2)
        ... + "  |  " + string$(numChannels) + " ch"
        ... + "  |  " + fixed$(dur, 2) + " s"

        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
        Font size: 10
        Colour: "Black"
    endif

    # Cleanup intermediates
    removeObject: envInput, envFollower, formantGrid, wetSound
endif

# ============================================================
# FINALIZE
# ============================================================
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
