# ============================================================
# Praat AudioTools - XY_SHAPE_LFO_-_FREQUENCY_MODULATION.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   XY Shape LFO Modulation - maps normalized 2D parametric trajectories
#   to several audio modulation topologies. The legacy filename mentions
#   frequency modulation, but this is a multi-mode XY modulator rather than
#   oscillator FM synthesis.
#
#   Modes:
#   - Temporal Warp: X controls an offline bidirectional time displacement.
#   - Amplitude Modulation: X controls carrier-retaining amplitude modulation.
#   - XY Split: odd channels use X time warp; even channels use a Y gate.
#   - XY Stereo Rotation: X warps time, Y rotates each stereo pair with an
#     orthonormal constant-power matrix. Active mono expands to stereo.
#
# Changelog v0.5:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.4:
#   - Made all trajectory/fade timing local-time invariant.
#   - Removed unconditional fades and forced peak normalization.
#   - Added Dry/Wet and attenuation-only Safety peak.
#   - Renamed false Signal_feedback to truthful Signal_reactivity.
#   - Added reproducible shared Instability trajectory via Random_seed.
#   - Preserved multichannel count in spatial modes; no more 2x channel growth.
#   - Made Depth percent coherent across X and Y mappings; 0% is exact bypass.
#   - Preserved XY shape geometry with joint coordinate normalization.
#   - Reworked visualization to AudioTools house style with explicit mapping text.
# ============================================================

form XY Shape LFO Modulation v0.5
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Granular Time-Scrub
        option Robotic AM
        option Stereo Head-Spinner
        option Broken Glitch Storm
        option Signal-Reactive Chaos

    comment === Shape ===
    optionmenu Shape_type 6
        option Circle
        option Diamond
        option Lissajous (3:4)
        option Rose Curve
        option Star (Astroid)
        option Butterfly

    comment === Modulation Mode ===
    optionmenu Modulation_mode 1
        option Temporal Warp (X -> time)
        option Amplitude Modulation (X -> gain)
        option XY Split (X warp / Y gate)
        option XY Stereo Rotation (X warp + Y pan)

    comment === Parameters ===
    real Trajectory_rate_Hz 1.0
    real Depth_percent 50
    real Signal_reactivity 0.0
    real Instability 0.0
    integer Random_seed 0

    comment === Output ===
    real Dry_wet_percent 100
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object first."
endif

inputSound = selected("Sound")
originalName$ = selected$("Sound")
selectObject: inputSound
sampleRate = Get sampling frequency
duration = Get total duration
nSamples = Get number of samples
numChannels = Get number of channels
sound_xmin = Get start time
sound_xmax = Get end time

if duration <= 0
    exitScript: "The selected Sound has zero duration."
endif

uid$ = string$(inputSound) + "_" + string$(randomInteger(100000, 999999))

# -------------------------------------------------------------------------
# Presets
# -------------------------------------------------------------------------
preset_name$ = "Custom"
if preset = 2
    modulation_mode = 1
    trajectory_rate_Hz = 55.0
    depth_percent = 2
    signal_reactivity = 0.4
    instability = 0.0
    shape_type = 5
    dry_wet_percent = 100
    preset_name$ = "GranularScrub"
elsif preset = 3
    modulation_mode = 2
    trajectory_rate_Hz = 50.0
    depth_percent = 100
    signal_reactivity = 0.0
    instability = 0.0
    shape_type = 3
    dry_wet_percent = 100
    preset_name$ = "RoboticAM"
elsif preset = 4
    modulation_mode = 4
    trajectory_rate_Hz = 2.0
    depth_percent = 100
    signal_reactivity = 0.0
    instability = 0.0
    shape_type = 6
    dry_wet_percent = 100
    preset_name$ = "StereoSpinner"
elsif preset = 5
    modulation_mode = 1
    trajectory_rate_Hz = 8.0
    depth_percent = 60
    signal_reactivity = 0.8
    instability = 0.1
    shape_type = 2
    dry_wet_percent = 100
    preset_name$ = "GlitchStorm"
elsif preset = 6
    modulation_mode = 1
    trajectory_rate_Hz = 4.0
    depth_percent = 80
    signal_reactivity = 2.5
    instability = 0.3
    shape_type = 6
    dry_wet_percent = 100
    preset_name$ = "ReactiveChaos"
endif

# Defensive clamps
if trajectory_rate_Hz < 0
    trajectory_rate_Hz = 0
endif
if trajectory_rate_Hz > 200
    trajectory_rate_Hz = 200
endif
if depth_percent < 0
    depth_percent = 0
endif
if depth_percent > 100
    depth_percent = 100
endif
if signal_reactivity < 0
    signal_reactivity = 0
endif
if signal_reactivity > 3
    signal_reactivity = 3
endif
if instability < 0
    instability = 0
endif
if instability > 1
    instability = 1
endif
if random_seed < 0
    random_seed = 0
endif
if random_seed > 2147483647
    random_seed = 2147483647
endif
if dry_wet_percent < 0
    dry_wet_percent = 0
endif
if dry_wet_percent > 100
    dry_wet_percent = 100
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

wet = dry_wet_percent / 100
dry = 1 - wet
depth_ratio = depth_percent / 100
willProcess = wet > 0 and depth_ratio > 0

if modulation_mode = 1
    modeName$ = "Temporal Warp"
    modeSafe$ = "TemporalWarp"
elsif modulation_mode = 2
    modeName$ = "Amplitude Modulation"
    modeSafe$ = "AmplitudeModulation"
elsif modulation_mode = 3
    modeName$ = "XY Split"
    modeSafe$ = "XYSplit"
else
    modeName$ = "XY Stereo Rotation"
    modeSafe$ = "XYStereoRotation"
endif

# Nominal mode mappings (reactivity/jitter can enlarge X displacement).
if modulation_mode = 1
    maxWarpSec = 0.050 * depth_ratio
    xMap$ = "X: bidirectional time offset +/-" + fixed$(maxWarpSec*1000, 2) + " ms before reactivity/jitter"
    yMap$ = "Y: trajectory companion (not mapped in this mode)"
elsif modulation_mode = 2
    xMap$ = "X: wet gain around unity, nominal range " + fixed$(1-depth_ratio,2) + ".." + fixed$(1+depth_ratio,2)
    yMap$ = "Y: trajectory companion (not mapped in this mode)"
elsif modulation_mode = 3
    maxWarpSec = 0.020 * depth_ratio
    xMap$ = "X: odd-channel time offset +/-" + fixed$(maxWarpSec*1000, 2) + " ms before reactivity/jitter"
    yMap$ = "Y: even-channel gate " + fixed$(1-depth_ratio,2) + "..1.00"
else
    maxWarpSec = 0.010 * depth_ratio
    xMap$ = "X: shared time offset +/-" + fixed$(maxWarpSec*1000, 2) + " ms before reactivity/jitter"
    yMap$ = "Y: stereo-pair rotation +/-" + fixed$(depth_ratio*45,1) + " deg (constant power)"
endif

# -------------------------------------------------------------------------
# Working source copy
# -------------------------------------------------------------------------
sourceName$ = "xy_source_" + uid$
selectObject: inputSound
Copy: sourceName$
sourceSound = selected("Sound")
sourceRef$ = "Sound_" + sourceName$

# -------------------------------------------------------------------------
# Shape formulas
# -------------------------------------------------------------------------
rate$ = string$(trajectory_rate_Hz)
if shape_type = 1
    xFormula$ = "sin(2*pi*" + rate$ + "*x)"
    yFormula$ = "cos(2*pi*" + rate$ + "*x)"
    shapeName$ = "Circle"
elsif shape_type = 2
    xFormula$ = "(2/pi)*arcsin(sin(2*pi*" + rate$ + "*x))"
    yFormula$ = "(2/pi)*arcsin(sin(2*pi*" + rate$ + "*x + pi/2))"
    shapeName$ = "Diamond"
elsif shape_type = 3
    xFormula$ = "sin(3*2*pi*" + rate$ + "*x)"
    yFormula$ = "sin(4*2*pi*" + rate$ + "*x)"
    shapeName$ = "Lissajous 3:4"
elsif shape_type = 4
    xFormula$ = "cos(4*2*pi*" + rate$ + "*x)*cos(2*pi*" + rate$ + "*x)"
    yFormula$ = "cos(4*2*pi*" + rate$ + "*x)*sin(2*pi*" + rate$ + "*x)"
    shapeName$ = "Rose"
elsif shape_type = 5
    xFormula$ = "cos(2*pi*" + rate$ + "*x)^3"
    yFormula$ = "sin(2*pi*" + rate$ + "*x)^3"
    shapeName$ = "Astroid"
else
    xFormula$ = "sin(2*pi*" + rate$ + "*x)*(exp(cos(2*pi*" + rate$ + "*x))-2*cos(4*2*pi*" + rate$ + "*x)-sin(2*pi*" + rate$ + "*x/12)^5)"
    yFormula$ = "cos(2*pi*" + rate$ + "*x)*(exp(cos(2*pi*" + rate$ + "*x))-2*cos(4*2*pi*" + rate$ + "*x)-sin(2*pi*" + rate$ + "*x/12)^5)"
    shapeName$ = "Butterfly"
endif

xName$ = "xy_x_" + uid$
yName$ = "xy_y_" + uid$
xTraj = Create Sound from formula: xName$, 1, 0, duration, sampleRate, xFormula$
yTraj = Create Sound from formula: yName$, 1, 0, duration, sampleRate, yFormula$

# Joint normalization preserves the XY geometry instead of scaling axes independently.
selectObject: xTraj
xPeak = Get absolute extremum: 0, 0, "Sinc70"
selectObject: yTraj
yPeak = Get absolute extremum: 0, 0, "Sinc70"
trajPeak = max(xPeak, yPeak)
if trajPeak > 0
    selectObject: xTraj
    Multiply: 1 / trajPeak
    selectObject: yTraj
    Multiply: 1 / trajPeak
endif
xRef$ = "Sound_" + xName$
yRef$ = "Sound_" + yName$

# -------------------------------------------------------------------------
# Shared signal-reactivity source with cancellation fallback
# -------------------------------------------------------------------------
reactiveSound = 0
reactiveIsTemp = 0
reactiveSource$ = "off"
if signal_reactivity > 0 and willProcess
    selectObject: sourceSound
    Convert to mono
    reactiveSound = selected("Sound")
    reactiveIsTemp = 1
    foldRms = Get root-mean-square: 0, 0
    loudestRms = 0
    loudestChannel = 1

    if numChannels > 1
        for ch from 1 to numChannels
            selectObject: sourceSound
            Extract one channel: ch
            tempCh = selected("Sound")
            chRms = Get root-mean-square: 0, 0
            if chRms > loudestRms
                loudestRms = chRms
                loudestChannel = ch
            endif
            removeObject: tempCh
        endfor
    else
        loudestRms = foldRms
    endif

    if numChannels > 1 and loudestRms > 0 and foldRms < 0.1 * loudestRms
        removeObject: reactiveSound
        selectObject: sourceSound
        Extract one channel: loudestChannel
        reactiveSound = selected("Sound")
        reactiveSource$ = "channel " + string$(loudestChannel) + " fallback"
    else
        reactiveSource$ = "mono fold"
    endif
    reactiveName$ = "xy_reactive_" + uid$
    selectObject: reactiveSound
    Rename: reactiveName$
    reactiveRef$ = "Sound_" + reactiveName$
endif

# -------------------------------------------------------------------------
# Shared instability trajectory, reproducible when seed > 0
# -------------------------------------------------------------------------
jitterSound = 0
jitterIsTemp = 0
if instability > 0 and willProcess
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably(random_seed)
    endif
    jitterName$ = "xy_jitter_" + uid$
    jitterSound = Create Sound from formula: jitterName$, 1, 0, duration, sampleRate, "randomGauss(0,1)"
    jitterIsTemp = 1
    jitterRef$ = "Sound_" + jitterName$
    random_initializeSafelyAndUnpredictably()
endif

# Formula fragments
xmin$ = string$(sound_xmin)
xmax$ = string$(sound_xmax)
depth$ = string$(depth_ratio)
dry$ = string$(dry)
wet$ = string$(wet)
localT$ = "(x - " + xmin$ + ")"
xVal$ = xRef$ + "(" + localT$ + ")"
yVal$ = yRef$ + "(" + localT$ + ")"

if signal_reactivity > 0 and willProcess
    react$ = "min(4, 1 + " + string$(signal_reactivity) + "*abs(" + reactiveRef$ + "(x)))"
else
    react$ = "1"
endif
if instability > 0 and willProcess
    jitter$ = "max(-2, min(4, 1 + " + string$(instability) + "*" + jitterRef$ + "(" + localT$ + ")))"
else
    jitter$ = "1"
endif

# -------------------------------------------------------------------------
# Exact bypass
# -------------------------------------------------------------------------
if wet = 0 or depth_ratio = 0
    selectObject: inputSound
    Copy: originalName$ + "_xyLFO_" + modeSafe$ + "_" + preset_name$
    outputSound = selected("Sound")
    activeProcessing = 0
    outChannels = numChannels
    processingChannels = numChannels
    spatialExpanded = 0
else
    activeProcessing = 1
    spatialExpanded = 0

    # Modes 3/4 are explicitly spatial. Active mono expands to stereo only there.
    if (modulation_mode = 3 or modulation_mode = 4) and numChannels = 1
        selectObject: sourceSound
        Convert to stereo
        procSound = selected("Sound")
        procName$ = "xy_spatial_" + uid$
        Rename: procName$
        procIsTemp = 1
        spatialExpanded = 1
    else
        procSound = sourceSound
        procName$ = sourceName$
        procIsTemp = 0
    endif
    procRef$ = "Sound_" + procName$
    selectObject: procSound
    processingChannels = Get number of channels

    outputName$ = originalName$ + "_xyLFO_" + modeSafe$ + "_" + preset_name$

    # ---------------------------------------------------------------------
    # Mode 1: offline bidirectional time warp from X
    # ---------------------------------------------------------------------
    if modulation_mode = 1
        maxWarpSec = 0.050 * depth_ratio
        offset$ = "(" + xVal$ + "*" + string$(maxWarpSec) + "*" + react$ + "*" + jitter$ + ")"
        readT$ = "(x + " + offset$ + ")"
        wetBranch$ = "if " + readT$ + " < " + xmin$ + " or " + readT$ + " > " + xmax$ + " then 0 else " + procRef$ + "(" + readT$ + ") fi"
        selectObject: procSound
        Copy: outputName$
        outputSound = selected("Sound")
        Formula: dry$ + "*" + procRef$ + "(x) + " + wet$ + "*(" + wetBranch$ + ")"
        xMap$ = "X: bidirectional time offset +/-" + fixed$(maxWarpSec*1000, 2) + " ms before reactivity/jitter"
        yMap$ = "Y: trajectory companion (not mapped in this mode)"

    # ---------------------------------------------------------------------
    # Mode 2: carrier-retaining amplitude modulation from X
    # ---------------------------------------------------------------------
    elsif modulation_mode = 2
        gain$ = "(1 + " + depth$ + "*" + xVal$ + "*" + react$ + "*" + jitter$ + ")"
        selectObject: procSound
        Copy: outputName$
        outputSound = selected("Sound")
        Formula: dry$ + "*" + procRef$ + "(x) + " + wet$ + "*(" + procRef$ + "(x)*" + gain$ + ")"
        xMap$ = "X: wet gain around unity, nominal range " + fixed$(1-depth_ratio,2) + ".." + fixed$(1+depth_ratio,2)
        yMap$ = "Y: trajectory companion (not mapped in this mode)"

    # ---------------------------------------------------------------------
    # Mode 3: odd-channel X warp / even-channel Y gate
    # ---------------------------------------------------------------------
    elsif modulation_mode = 3
        maxWarpSec = 0.020 * depth_ratio
        offset$ = "(" + xVal$ + "*" + string$(maxWarpSec) + "*" + react$ + "*" + jitter$ + ")"
        readT$ = "(x + " + offset$ + ")"
        xWarp$ = "if " + readT$ + " < " + xmin$ + " or " + readT$ + " > " + xmax$ + " then 0 else " + procRef$ + "(" + readT$ + ") fi"
        gate$ = "(1 - " + depth$ + "*0.5*(1 - " + yVal$ + "))"
        wetBranch$ = "if row mod 2 = 1 then (" + xWarp$ + ") else " + procRef$ + "(x)*" + gate$ + " fi"
        selectObject: procSound
        Copy: outputName$
        outputSound = selected("Sound")
        Formula: dry$ + "*" + procRef$ + "(x) + " + wet$ + "*(" + wetBranch$ + ")"
        xMap$ = "X: odd-channel time offset +/-" + fixed$(maxWarpSec*1000, 2) + " ms before reactivity/jitter"
        yMap$ = "Y: even-channel gate " + fixed$(1-depth_ratio,2) + "..1.00"

    # ---------------------------------------------------------------------
    # Mode 4: shared X warp then constant-power stereo-pair rotation from Y
    # ---------------------------------------------------------------------
    else
        maxWarpSec = 0.010 * depth_ratio
        offset$ = "(" + xVal$ + "*" + string$(maxWarpSec) + "*" + react$ + "*" + jitter$ + ")"
        readT$ = "(x + " + offset$ + ")"
        wetWarp$ = "if " + readT$ + " < " + xmin$ + " or " + readT$ + " > " + xmax$ + " then 0 else " + procRef$ + "(" + readT$ + ") fi"

        selectObject: procSound
        Copy: "xy_warp_" + uid$
        warpSound = selected("Sound")
        Formula: wetWarp$
        warpId = warpSound

        theta$ = "(" + depth$ + "*pi/4*" + yVal$ + ")"
        monoNorm = 1
        if spatialExpanded
            monoNorm = 0.7071067811865476
        endif
        monoNorm$ = string$(monoNorm)

        rotated$ = "if row mod 2 = 1 and row < nrow then " + monoNorm$ + "*(cos(" + theta$ + ")*object[" + string$(warpId) + ",row,col] - sin(" + theta$ + ")*object[" + string$(warpId) + ",row+1,col]) else if row mod 2 = 0 then " + monoNorm$ + "*(sin(" + theta$ + ")*object[" + string$(warpId) + ",row-1,col] + cos(" + theta$ + ")*object[" + string$(warpId) + ",row,col]) else object[" + string$(warpId) + ",row,col] fi fi"

        selectObject: procSound
        Copy: outputName$
        outputSound = selected("Sound")
        Formula: dry$ + "*" + procRef$ + "(x) + " + wet$ + "*(" + rotated$ + ")"
        removeObject: warpSound
        xMap$ = "X: shared time offset +/-" + fixed$(maxWarpSec*1000, 2) + " ms before reactivity/jitter"
        yMap$ = "Y: stereo-pair rotation +/-" + fixed$(depth_ratio*45,1) + " deg (constant power)"
    endif

    if procIsTemp
        removeObject: procSound
    endif

    selectObject: outputSound
    outChannels = Get number of channels
endif

# -------------------------------------------------------------------------
# Safety: attenuation only, skipped for exact bypass
# -------------------------------------------------------------------------
selectObject: outputSound
outputPeak = Get absolute extremum: 0, 0, "Sinc70"
if activeProcessing and safety_peak > 0 and outputPeak > safety_peak
    Multiply: safety_peak / outputPeak
    outputPeak = safety_peak
endif

# -------------------------------------------------------------------------
# Info
# -------------------------------------------------------------------------
writeInfoLine: "=== XY Shape LFO Modulation v0.5 ==="
appendInfoLine: "Source: ", originalName$, "  |  Preset: ", preset_name$
appendInfoLine: "Shape: ", shapeName$, "  |  Mode: ", modeName$
appendInfoLine: "Rate: ", fixed$(trajectory_rate_Hz,2), " Hz  |  Depth: ", fixed$(depth_percent,1), "%  |  Dry/Wet: ", fixed$(100-dry_wet_percent,0), "/", fixed$(dry_wet_percent,0), "%"
appendInfoLine: "Channels: ", numChannels, " -> ", outChannels
if activeProcessing and modulation_mode = 4 and outChannels > 1 and outChannels mod 2 = 1
    appendInfoLine: "Stereo rotation: final unpaired channel receives X warp only."
endif
if signal_reactivity > 0
    if willProcess
        appendInfoLine: "Signal reactivity: ", fixed$(signal_reactivity,2), "  |  Analysis: ", reactiveSource$
    else
        appendInfoLine: "Signal reactivity: ", fixed$(signal_reactivity,2), "  |  Analysis skipped on bypass"
    endif
else
    appendInfoLine: "Signal reactivity: off"
endif
if instability > 0
    if willProcess
        if random_seed > 0
            appendInfoLine: "Instability: ", fixed$(instability,2), "  |  Seed: ", random_seed
        else
            appendInfoLine: "Instability: ", fixed$(instability,2), "  |  Seed: unpredictable"
        endif
    else
        appendInfoLine: "Instability: ", fixed$(instability,2), "  |  RNG skipped on bypass"
    endif
else
    appendInfoLine: "Instability: off"
endif
if modulation_mode = 1 or modulation_mode = 3 or modulation_mode = 4
    appendInfoLine: "Time-warp reads are offline/bidirectional and boundary-guarded."
endif
appendInfoLine: "Output peak: ", fixed$(outputPeak,4), "  |  Safety: ", fixed$(safety_peak,2)

# -------------------------------------------------------------------------
# Visualization
# -------------------------------------------------------------------------
if draw_visualization
    pageHeight = 5.7
    Erase all

    # Title / subtitle
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##XY Shape LFO Modulation v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", "XY_SHAPE_LFO_-_FREQUENCY_MODULATION.praat  |  " + preset_name$ + "  |  " + shapeName$ + "  |  " + modeName$

    # Input
    Select outer viewport: 0, 4, 0.65, 1.65
    Select inner viewport: 0.55, 3.75, 0.78, 1.52
    selectObject: inputSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output
    Select outer viewport: 4, 8, 0.65, 1.65
    Select inner viewport: 4.35, 7.55, 0.78, 1.52
    selectObject: outputSound
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # XY trajectory
    Select outer viewport: 0, 4, 1.85, 3.45
    Select inner viewport: 0.60, 3.75, 2.00, 3.28
    Axes: -1.12, 1.12, -1.12, 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.12, 1.12, -1.12, 1.12
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: -1.05, 0, 1.05, 0
    Draw line: 0, -1.05, 0, 1.05
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    nViz = 350
    for p from 2 to nViz
        t1 = (p-2)/(nViz-1)*duration
        t2 = (p-1)/(nViz-1)*duration
        s1 = round(t1 * sampleRate) + 1
        s2 = round(t2 * sampleRate) + 1
        if s1 < 1
            s1 = 1
        endif
        if s2 > nSamples
            s2 = nSamples
        endif
        selectObject: xTraj
        xv1 = Get value at sample number: 1, s1
        xv2 = Get value at sample number: 1, s2
        selectObject: yTraj
        yv1 = Get value at sample number: 1, s1
        yv2 = Get value at sample number: 1, s2
        Draw line: xv1, yv1, xv2, yv2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "X"
    Text left: "yes", "Y"
    Colour: "{0.28, 0.28, 0.28}"
    Text: -1.04, "left", 1.03, "half", shapeName$

    # X/Y trajectory values over local time
    Select outer viewport: 4, 8, 1.85, 3.45
    Select inner viewport: 4.35, 7.55, 2.00, 3.28
    vizDur = min(2, duration)
    Axes: 0, vizDur, -1.12, 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, -1.12, 1.12
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, vizDur, 0
    Line width: 1.3
    Colour: "{0.22, 0.46, 0.82}"
    for p from 2 to nViz
        t1 = (p-2)/(nViz-1)*vizDur
        t2 = (p-1)/(nViz-1)*vizDur
        s1 = round(t1 * sampleRate) + 1
        s2 = round(t2 * sampleRate) + 1
        if s1 < 1
            s1 = 1
        endif
        if s2 > nSamples
            s2 = nSamples
        endif
        selectObject: xTraj
        xv1 = Get value at sample number: 1, s1
        xv2 = Get value at sample number: 1, s2
        Draw line: t1, xv1, t2, xv2
    endfor
    Colour: "{0.48, 0.35, 0.74}"
    for p from 2 to nViz
        t1 = (p-2)/(nViz-1)*vizDur
        t2 = (p-1)/(nViz-1)*vizDur
        s1 = round(t1 * sampleRate) + 1
        s2 = round(t2 * sampleRate) + 1
        if s1 < 1
            s1 = 1
        endif
        if s2 > nSamples
            s2 = nSamples
        endif
        selectObject: yTraj
        yv1 = Get value at sample number: 1, s1
        yv2 = Get value at sample number: 1, s2
        Draw line: t1, yv1, t2, yv2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "XY value"
    Colour: "{0.22, 0.46, 0.82}"
    Text: 0.02*vizDur, "left", 0.96, "half", "X"
    Colour: "{0.48, 0.35, 0.74}"
    Text: 0.98*vizDur, "right", 0.96, "half", "Y"
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.50*vizDur, "centre", -0.96, "half", fixed$(trajectory_rate_Hz,2) + " Hz"

    # Mode mapping text
    Select outer viewport: 0, 8, 3.65, 4.55
    Select inner viewport: 0.25, 7.75, 3.72, 4.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Mode mapping##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", xMap$
    Text: 0.02, "left", 0.22, "half", yMap$ + "  |  Reactivity " + fixed$(signal_reactivity,2) + "  |  Instability " + fixed$(instability,2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Summary
    Select outer viewport: 0, 8, 4.70, 5.45
    Select inner viewport: 0.25, 7.75, 4.76, 5.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", shapeName$ + "  |  " + modeName$ + "  |  Rate " + fixed$(trajectory_rate_Hz,2) + " Hz  |  Depth " + fixed$(depth_percent,0) + "%  |  Wet " + fixed$(dry_wet_percent,0) + "%"
    Text: 0.02, "left", 0.18, "half", "Duration " + fixed$(duration,2) + " s  |  Channels " + string$(numChannels) + "->" + string$(outChannels) + "  |  Peak " + fixed$(outputPeak,3) + "  |  Safety " + fixed$(safety_peak,2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# -------------------------------------------------------------------------
# Cleanup
# -------------------------------------------------------------------------
if reactiveIsTemp
    removeObject: reactiveSound
endif
if jitterIsTemp
    removeObject: jitterSound
endif
removeObject: sourceSound, xTraj, yTraj

selectObject: outputSound
if play_result
    Play
endif
selectObject: outputSound
