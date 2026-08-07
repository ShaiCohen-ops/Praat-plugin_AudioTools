# ============================================================
# Praat AudioTools - Resonant.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Resonant comb-cascade effect. A single recursive feedback comb
#
#       y[n] = x[n] + fb * y[n-D]
#
#   is applied repeatedly in series. "Cascade stages" therefore means
#   filter order, NOT the number of audible repeats. For N stages, the
#   impulse coefficient at k*D is proportional to
#
#       C(k+N-1, N-1) * fb^k
#
#   so multi-stage responses can rise before they decay.
#
#   Delay can be fixed or chosen uniformly at random from 1..Delay_samples.
#   A non-zero random seed makes the random delay reproducible.
#
#   No loudness normalization is applied. Safety_peak only attenuates the
#   final wet/dry mix when needed; it never boosts quiet material.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Resonant Comb Cascade v1.3
    optionmenu Preset: 1
        option Custom
        option Light Echo (5-stage cascade)
        option Medium Resonance (10-stage)
        option Dense Resonance (20-stage)
        option Extreme Resonance (30-stage)
        option Subtle Texture (3-stage)
        option Metallic Comb
        option Short Comb
        option Short Random Echo
        option Cathedral-like Resonance
        option Small Room-like Resonance
        option Long Random Echo
    natural Cascade_stages 20
    real Feedback_amount 0.5
    optionmenu Delay_mode: 1
        option Random 1..Delay_samples
        option Fixed Delay_samples
    positive Delay_samples 1000
    integer Random_seed 0
    positive Safety_peak 0.99
    real Dry_wet_mix 0.7
    boolean Show_spectrum 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS - same numeric characters as v1.2; names are more literal
# ============================================================
if preset = 2
    cascade_stages = 5
    feedback_amount = 0.5
    delay_samples = 1000
    dry_wet_mix = 0.7
    presetName$ = "LightEcho"
elsif preset = 3
    cascade_stages = 10
    feedback_amount = 0.5
    delay_samples = 1500
    dry_wet_mix = 0.7
    presetName$ = "MediumResonance"
elsif preset = 4
    cascade_stages = 20
    feedback_amount = 0.5
    delay_samples = 2000
    dry_wet_mix = 0.7
    presetName$ = "DenseResonance"
elsif preset = 5
    cascade_stages = 30
    feedback_amount = 0.6
    delay_samples = 2500
    dry_wet_mix = 0.7
    presetName$ = "ExtremeResonance"
elsif preset = 6
    cascade_stages = 3
    feedback_amount = 0.4
    delay_samples = 800
    dry_wet_mix = 0.7
    presetName$ = "SubtleTexture"
elsif preset = 7
    cascade_stages = 20
    feedback_amount = 0.6
    delay_samples = 50
    dry_wet_mix = 0.6
    presetName$ = "MetallicComb"
elsif preset = 8
    cascade_stages = 10
    feedback_amount = 0.5
    delay_samples = 30
    dry_wet_mix = 0.5
    presetName$ = "ShortComb"
elsif preset = 9
    cascade_stages = 3
    feedback_amount = 0.4
    delay_samples = 2000
    dry_wet_mix = 0.5
    presetName$ = "ShortRandomEcho"
elsif preset = 10
    cascade_stages = 25
    feedback_amount = 0.55
    delay_samples = 3000
    dry_wet_mix = 0.7
    presetName$ = "CathedralLike"
elsif preset = 11
    cascade_stages = 8
    feedback_amount = 0.45
    delay_samples = 500
    dry_wet_mix = 0.5
    presetName$ = "SmallRoomLike"
elsif preset = 12
    cascade_stages = 5
    feedback_amount = 0.5
    delay_samples = 3000
    dry_wet_mix = 0.5
    presetName$ = "LongRandomEcho"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP / VALIDATION
# ============================================================
selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency
numSamples = Get number of samples
numChannels = Get number of channels
xmin = Get start time
inputPeak = Get absolute extremum: 0, 0, "None"

if numSamples < 2
    exitScript: "Sound must contain at least 2 samples."
endif

if cascade_stages < 1
    cascade_stages = 1
endif
if cascade_stages > 50
    cascade_stages = 50
endif
if feedback_amount < 0
    feedback_amount = 0
endif
if feedback_amount > 0.9
    feedback_amount = 0.9
endif
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif
if safety_peak > 1
    safety_peak = 1
endif

delay_samples = round(delay_samples)
if delay_samples < 1
    delay_samples = 1
endif
if delay_samples > numSamples - 1
    delay_samples = numSamples - 1
endif

# Resolve actual delay.
if delay_mode = 1
    if random_seed <> 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
    endif
    delay = randomInteger(1, delay_samples)
    if random_seed <> 0
        random_initializeSafelyAndUnpredictably ()
    endif
    delayModeName$ = "Random"
else
    delay = delay_samples
    delayModeName$ = "Fixed"
endif

delayMs = delay / sampleRate * 1000
maxDelayMs = delay_samples / sampleRate * 1000

clearinfo
writeInfoLine: "=== Resonant Comb Cascade v1.3 ==="
appendInfoLine: "Input: ", soundName$, "   ", fixed$(duration, 3), " s   ", numChannels, " ch   ", round(sampleRate), " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Cascade stages: ", cascade_stages, "  (stages, not repeat count)"
appendInfoLine: "Feedback: ", fixed$(feedback_amount * 100, 1), "%"
appendInfoLine: "Delay mode: ", delayModeName$
if delay_mode = 1
    appendInfoLine: "Random range: 1..", delay_samples, " samples (max ", fixed$(maxDelayMs, 2), " ms)"
    if random_seed <> 0
        appendInfoLine: "Random seed: ", random_seed
    else
        appendInfoLine: "Random seed: unpredictable"
    endif
endif
appendInfoLine: "Actual delay: ", delay, " samples (", fixed$(delayMs, 3), " ms)"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 1), "% wet"
appendInfoLine: "Safety peak: ", fixed$(safety_peak, 3), " (attenuation only)"
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================
wetID = 0
safetyApplied = 0
safetyGain = 1

if dry_wet_mix = 0
    # Exact bypass: no filtering and no safety attenuation.
    selectObject: soundID
    resultID = Copy: soundName$ + "_" + presetName$
    appendInfoLine: "Dry/Wet = 0: exact dry bypass."
else
    appendInfoLine: "Processing recursive comb cascade..."

    selectObject: soundID
    wetID = Copy: "wet_processing"

    delay$ = string$(delay)
    fb$ = string$(feedback_amount)

    for stage from 1 to cascade_stages
        selectObject: wetID
        Formula: "self + " + fb$ + " * self[col - " + delay$ + "]"
    endfor

    # Linear dry/wet mix. No wet pre-normalization.
    selectObject: soundID
    resultID = Copy: soundName$ + "_" + presetName$

    dryAmount = 1 - dry_wet_mix
    wetAmount = dry_wet_mix
    dryAmt$ = string$(dryAmount)
    wetAmt$ = string$(wetAmount)
    wetId$ = string$(wetID)

    selectObject: resultID
    Formula: dryAmt$ + " * self + " + wetAmt$ + " * object(" + wetId$ + ", x)"

    # Safety attenuation only. Preserve the dry/wet ratio and never boost.
    preSafetyPeak = Get absolute extremum: 0, 0, "None"
    if preSafetyPeak > safety_peak
        safetyGain = safety_peak / preSafetyPeak
        Formula: "self * " + string$(safetyGain)
        safetyApplied = 1
        appendInfoLine: "Safety attenuation: ", fixed$(20 * log10(safetyGain), 2), " dB"
    endif
endif

selectObject: resultID
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Mono, zero-based display copies only; audio result is untouched.
    selectObject: soundID
    if numChannels > 1
        vizInID = Convert to mono
    else
        vizInID = Copy: "viz_input"
    endif
    selectObject: resultID
    if numChannels > 1
        vizOutID = Convert to mono
    else
        vizOutID = Copy: "viz_output"
    endif

    selectObject: vizInID
    vizInStart = Get start time
    if vizInStart <> 0
        Shift times by: -vizInStart
    endif
    selectObject: vizOutID
    vizOutStart = Get start time
    if vizOutStart <> 0
        Shift times by: -vizOutStart
    endif

    if show_spectrum
        selectObject: vizInID
        origSpecID = To Spectrum: "yes"
        selectObject: vizOutID
        resSpecID = To Spectrum: "yes"
    endif

    Erase all
    Helvetica
    Line width: 1

    colInput$ = "{0.55, 0.55, 0.55}"
    colOutput$ = "{0.20, 0.48, 0.82}"
    colAccent$ = "{0.46, 0.35, 0.72}"
    colGrey$ = "{0.97, 0.97, 0.97}"
    colGrid$ = "{0.86, 0.86, 0.88}"

    # TITLE
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Resonant Comb Cascade v1.3##"
    Font size: 7
    Colour: colAccent$
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$ + " | " + presetName$
        ... + " | " + string$(cascade_stages) + " stages"
        ... + " | fb " + fixed$(feedback_amount * 100, 0) + "%"
        ... + " | D " + string$(delay) + " samp (" + fixed$(delayMs, 2) + " ms)"
        ... + " | wet " + fixed$(dry_wet_mix * 100, 0) + "%"

    # PANEL A: ACTUAL CASCADE IMPULSE COEFFICIENTS
    Select outer viewport: 0, 4.1, 0.75, 3.55
    Select inner viewport: 0.65, 3.90, 0.95, 3.40

    if feedback_amount = 0
        displayEchoes = 12
    else
        modeK = floor((cascade_stages - 1) * feedback_amount / (1 - feedback_amount))
        displayEchoes = modeK + 24
        if displayEchoes < 20
            displayEchoes = 20
        endif
        if displayEchoes > 100
            displayEchoes = 100
        endif
    endif

    rawMax = 1
    rawAmp = 1
    for k from 1 to displayEchoes
        rawAmp = rawAmp * feedback_amount * (k + cascade_stages - 1) / k
        if rawAmp > rawMax
            rawMax = rawAmp
        endif
    endfor

    xAxisMax = (displayEchoes + 0.5) * delayMs
    if xAxisMax < 1
        xAxisMax = 1
    endif
    Axes: 0, xAxisMax, 0, 1.08
    Paint rectangle: colGrey$, 0, xAxisMax, 0, 1.08
    Colour: colGrid$
    Draw line: 0, 0.5, xAxisMax, 0.5
    Draw line: 0, 1.0, xAxisMax, 1.0

    rawAmp = 1
    Colour: colOutput$
    Line width: 1.5
    Draw line: 0, 0, 0, 1 / rawMax
    for k from 1 to displayEchoes
        rawAmp = rawAmp * feedback_amount * (k + cascade_stages - 1) / k
        xk = k * delayMs
        if xk <= xAxisMax
            Draw line: xk, 0, xk, rawAmp / rawMax
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Cascade impulse coefficients (display normalized to peak)"
    Text left: "yes", "Relative amp"
    Text bottom: "yes", "Time (ms)"

    # PANEL B: PARAMETER REPORT
    Select outer viewport: 4.1, 8, 0.75, 3.55
    Select inner viewport: 4.45, 7.75, 0.95, 3.40
    Axes: 0, 1, 0, 1
    Paint rectangle: colGrey$, 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.25, 0.25, 0.30}"
    Text: 0.05, "left", 0.91, "half", "##Algorithm##"
    Font size: 7
    Text: 0.08, "left", 0.83, "half", "One stage: y[n] = x[n] + fb * y[n-D]"
    Text: 0.08, "left", 0.76, "half", "Cascaded " + string$(cascade_stages) + " times in series"
    Text: 0.08, "left", 0.66, "half", "Actual delay: " + string$(delay) + " samples = " + fixed$(delayMs, 3) + " ms"
    Text: 0.08, "left", 0.59, "half", "Delay mode: " + delayModeName$
    Text: 0.08, "left", 0.52, "half", "Feedback: " + fixed$(feedback_amount * 100, 1) + "%"
    Text: 0.08, "left", 0.45, "half", "Mix: " + fixed$((1-dry_wet_mix)*100,0) + "% dry / " + fixed$(dry_wet_mix*100,0) + "% wet"
    Text: 0.08, "left", 0.35, "half", "Input peak: " + fixed$(inputPeak, 4)
    Text: 0.08, "left", 0.28, "half", "Output peak: " + fixed$(finalPeak, 4)
    if safetyApplied
        Text: 0.08, "left", 0.21, "half", "Safety attenuation: " + fixed$(20*log10(safetyGain), 2) + " dB"
    else
        Text: 0.08, "left", 0.21, "half", "Safety attenuation: none"
    endif
    Font size: 6
    Colour: colAccent$
    Text: 0.08, "left", 0.10, "half", "Stages change the cascade response; they are not a repeat counter."

    # PANEL C: ZOOM OVERLAY
    Select outer viewport: 0, 8, 3.65, 4.75
    Select inner viewport: 0.65, 7.72, 3.76, 4.65
    zoomDur = min(0.2, duration)
    selectObject: vizInID
    z1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizOutID
    z2 = Get absolute extremum: 0, zoomDur, "None"
    zMax = max(z1, z2)
    if zMax < 0.001
        zMax = 0.001
    endif
    zAmp = zMax * 1.12
    Axes: 0, zoomDur, -zAmp, zAmp
    Paint rectangle: colGrey$, 0, zoomDur, -zAmp, zAmp
    Colour: colGrid$
    Draw line: 0, 0, zoomDur, 0
    selectObject: vizInID
    Colour: colInput$
    Draw: 0, zoomDur, -zAmp, zAmp, "no", "Curve"
    selectObject: vizOutID
    Colour: colOutput$
    Draw: 0, zoomDur, -zAmp, zAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "First " + fixed$(zoomDur*1000,0) + " ms  (gray=input, blue=output)"
    Text bottom: "yes", "Time (s)"

    # PANEL D: FULL WAVEFORM OR SPECTRUM
    Select outer viewport: 0, 8, 4.85, 6.15
    Select inner viewport: 0.65, 7.72, 4.96, 6.05
    if show_spectrum
        maxDisplayHz = min(5000, sampleRate/2)
        Axes: 0, maxDisplayHz, 0, 80
        Paint rectangle: colGrey$, 0, maxDisplayHz, 0, 80
        selectObject: origSpecID
        Colour: colInput$
        Draw: 0, maxDisplayHz, 0, 80, "no"
        selectObject: resSpecID
        Colour: colOutput$
        Draw: 0, maxDisplayHz, 0, 80, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Spectrum overlay (gray=input, blue=output)"
        Text bottom: "yes", "Frequency (Hz)"
    else
        outAmp = max(finalPeak, 0.001) * 1.12
        Axes: 0, finalDur, -outAmp, outAmp
        Paint rectangle: colGrey$, 0, finalDur, -outAmp, outAmp
        Colour: colGrid$
        Draw line: 0, 0, finalDur, 0
        selectObject: vizOutID
        Colour: colOutput$
        Draw: 0, finalDur, -outAmp, outAmp, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Processed waveform"
        Text bottom: "yes", "Time (s)"
    endif

    # SUMMARY
    Select outer viewport: 0, 8, 6.25, 7.05
    Select inner viewport: 0.65, 7.72, 6.32, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.30}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetName$ + "##  " + string$(cascade_stages) + " stages"
        ... + "  fb=" + fixed$(feedback_amount, 3)
        ... + "  D=" + string$(delay) + " samp"
        ... + "  wet=" + fixed$(dry_wet_mix*100,0) + "%"
    Text: 0.02, "left", 0.30, "half",
        ... "In " + fixed$(duration,2) + " s / " + string$(numChannels) + " ch"
        ... + "  peak " + fixed$(inputPeak,3) + " -> " + fixed$(finalPeak,3)
        ... + "  SR " + string$(round(sampleRate)) + " Hz"
        ... + "  start " + fixed$(xmin,3) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    if show_spectrum
        removeObject: origSpecID, resSpecID
    endif
    removeObject: vizInID, vizOutID
endif

# ============================================================
# CLEANUP / OUTPUT
# ============================================================
if wetID <> 0
    removeObject: wetID
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", soundName$, "_", presetName$
appendInfoLine: "Output peak: ", fixed$(finalPeak, 4)

selectObject: resultID
if play_result
    Play
endif
selectObject: resultID
