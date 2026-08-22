# ============================================================
# Praat AudioTools - Panning_filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Panner - frequency-dependent stereo panning of a mono source.
#   Frequencies below and above a smooth crossover are panned to opposite
#   sides. The pan law is equal-power: L^2 + R^2 = 1 at every frequency.
#
#   Multichannel input is intentionally downmixed to mono before spectral
#   panning; the output is always stereo. Existing stereo imaging is not
#   preserved by this effect.
#
# Changelog v0.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.3:
#   - Replaced constant-sum low/high reconstruction with direct equal-power
#     spectral panning. Centre is -3.01 dB per channel; total stereo power
#     remains constant through the crossover.
#   - Removed unconditional peak normalization. Output is attenuated only
#     when required to keep its peak at or below 0.99; quiet signals are
#     never boosted.
#   - Preserves the input start time.
#   - All multichannel inputs are explicitly downmixed to mono before the
#     stereo spectral split (v0.2 handled only exactly-2-channel input).
#   - Robust crossover edge validation near DC/Nyquist.
#   - Visualization updated to AudioTools house style and plots the actual
#     equal-power channel gains used by the processor.
# ============================================================

form Spectral Panner v0.4
    optionmenu Preset: 1
        option Custom
        option Subtle Split (800 Hz)
        option Classic Mid (500 Hz)
        option Deep Bass Left (200 Hz)
        option High Split (2000 Hz)
        option Wide Separation
    comment === Crossover ===
    positive Crossover_frequency_(Hz) 500
    positive Crossover_width_(Hz) 100
    comment === Panning ===
    optionmenu Low_frequencies_to: 1
        option Left
        option Right
    real Pan_depth 1.0
    comment (0 = centre, 1 = full opposite-side split; equal-power law)
    comment === Output ===
    boolean Draw_response 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    crossover_frequency = 800
    crossover_width = 150
    pan_depth = 0.7
    presetName$ = "SubtleSplit"
elsif preset = 3
    crossover_frequency = 500
    crossover_width = 100
    pan_depth = 1.0
    presetName$ = "ClassicMid"
elsif preset = 4
    crossover_frequency = 200
    crossover_width = 50
    pan_depth = 1.0
    presetName$ = "DeepBassLeft"
elsif preset = 5
    crossover_frequency = 2000
    crossover_width = 300
    pan_depth = 0.8
    presetName$ = "HighSplit"
elsif preset = 6
    crossover_frequency = 600
    crossover_width = 400
    pan_depth = 1.0
    presetName$ = "WideSeparation"
else
    presetName$ = "Custom"
endif

# Clamp pan depth. Values outside 0..1 do not have a useful panning meaning.
if pan_depth > 1
    pan_depth = 1
elsif pan_depth < 0
    pan_depth = 0
endif

# ============================================================
# INPUT VALIDATION + GEOMETRY
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
originalDur = Get total duration
sampleRate = Get sampling frequency
numChan = Get number of channels
xminOriginal = Get start time
peakIn = Get absolute extremum: 0, 0, "None"
nyquist = sampleRate / 2

if originalDur <= 0
    exitScript: "Input Sound has zero duration."
endif
if crossover_frequency <= 0 or crossover_frequency >= nyquist
    exitScript: "Crossover frequency must be above 0 Hz and below Nyquist (" + fixed$(nyquist, 1) + " Hz)."
endif
if crossover_width <= 0
    exitScript: "Crossover width must be positive."
endif

lowEdge = max(crossover_frequency - crossover_width / 2, 0)
highEdge = min(crossover_frequency + crossover_width / 2, nyquist)
span = highEdge - lowEdge
if span <= 0
    exitScript: "Crossover width/frequency combination produced an empty transition band."
endif

lowEdgeStr$ = fixed$(lowEdge, 12)
highEdgeStr$ = fixed$(highEdge, 12)
spanStr$ = fixed$(span, 12)
depthStr$ = fixed$(pan_depth, 12)

# ============================================================
# PREPARE MONO, ZERO-BASED WORKING SOURCE
# ============================================================
selectObject: originalID
if numChan > 1
    monoSound = Convert to mono
else
    monoSound = Copy: "specpan_mono"
endif
selectObject: monoSound
Shift times to: "start time", 0

# ============================================================
# DIRECT EQUAL-POWER SPECTRAL PANNING
# ============================================================
# Smooth transition s(f): 0 below lowEdge, 1 above highEdge, raised-cosine
# between. panPosition is -depth..+depth for low->Left, reversed otherwise.
# Equal-power gains:
#   angle = (panPosition + 1) * pi/4
#   L = cos(angle), R = sin(angle)
# Therefore L^2 + R^2 = 1 at every frequency.

selectObject: monoSound
spectrumFull = To Spectrum: "yes"

if low_frequencies_to = 1
    panExpr$ = "('depthStr$') * (2 * (if x <= 'lowEdgeStr$' then 0 else if x >= 'highEdgeStr$' then 1 else 0.5 - 0.5*cos(pi*(x-'lowEdgeStr$')/'spanStr$') fi fi) - 1)"
    direction$ = "Low -> Left, High -> Right"
else
    panExpr$ = "('depthStr$') * (1 - 2 * (if x <= 'lowEdgeStr$' then 0 else if x >= 'highEdgeStr$' then 1 else 0.5 - 0.5*cos(pi*(x-'lowEdgeStr$')/'spanStr$') fi fi))"
    direction$ = "Low -> Right, High -> Left"
endif

selectObject: spectrumFull
spectrumLeft = Copy: "specpan_L"
selectObject: spectrumLeft
Formula: "self * cos((1 + " + panExpr$ + ") * pi / 4)"

selectObject: spectrumFull
spectrumRight = Copy: "specpan_R"
selectObject: spectrumRight
Formula: "self * sin((1 + " + panExpr$ + ") * pi / 4)"

selectObject: spectrumLeft
soundLeftFull = To Sound
selectObject: spectrumRight
soundRightFull = To Sound

# Crop away FFT zero-padding and retain the exact source duration.
selectObject: soundLeftFull
leftChan = Extract part: 0, originalDur, "rectangular", 1, "no"
Rename: "specpan_left"
selectObject: soundRightFull
rightChan = Extract part: 0, originalDur, "rectangular", 1, "no"
Rename: "specpan_right"

selectObject: leftChan
plusObject: rightChan
stereoOutput = Combine to stereo
Rename: originalName$ + "_specpan"

# Restore the source time domain.
selectObject: stereoOutput
if xminOriginal <> 0
    Shift times by: xminOriginal
endif

# Safety attenuation only: never boost a quiet result.
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
safetyGain = 1
if peakBeforeSafety > 0.99
    safetyGain = 0.99 / peakBeforeSafety
    Formula: "self * " + fixed$(safetyGain, 12)
endif
peakOut = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION - AUDIOTOOLS HOUSE STYLE
# ============================================================
if draw_response
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Helvetica
    Line width: 1

    colLeft$ = "{0.20, 0.40, 0.80}"
    colRight$ = "{0.52, 0.34, 0.72}"
    colGrey$ = "{0.97, 0.97, 0.97}"
    colGrid$ = "{0.84, 0.84, 0.84}"
    colText$ = "{0.35, 0.35, 0.50}"

    # ---- Header ----
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Spectral Panner v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.75, 4.65
    Select inner viewport: 0.75, 7.70, 0.95, 4.45
    Axes: 0, nyquist, 0, 1.08
    Paint rectangle: colGrey$, 0, nyquist, 0, 1.08

    if nyquist > 15000
        gridStep = 5000
    elsif nyquist > 8000
        gridStep = 2000
    else
        gridStep = 1000
    endif
    Colour: colGrid$
    gridFreq = gridStep
    while gridFreq < nyquist
        Draw line: gridFreq, 0, gridFreq, 1
        gridFreq = gridFreq + gridStep
    endwhile
    Draw line: 0, sqrt(0.5), nyquist, sqrt(0.5)

    stepHz = nyquist / 320
    prevF = 0
    if low_frequencies_to = 1
        p0 = -pan_depth
    else
        p0 = pan_depth
    endif
    prevL = cos((p0 + 1) * pi / 4)
    prevR = sin((p0 + 1) * pi / 4)

    for q from 1 to 320
        f = q * stepHz
        if f <= lowEdge
            s = 0
        elsif f >= highEdge
            s = 1
        else
            s = 0.5 - 0.5 * cos(pi * (f - lowEdge) / span)
        endif
        if low_frequencies_to = 1
            p = pan_depth * (2 * s - 1)
        else
            p = pan_depth * (1 - 2 * s)
        endif
        gL = cos((p + 1) * pi / 4)
        gR = sin((p + 1) * pi / 4)

        Colour: colLeft$
        Line width: 2
        Draw line: prevF, prevL, f, gL
        Colour: colRight$
        Draw line: prevF, prevR, f, gR
        prevF = f
        prevL = gL
        prevR = gR
    endfor

    Line width: 1
    Colour: "{0.62, 0.62, 0.62}"
    Draw line: lowEdge, 0, lowEdge, 1
    Draw line: highEdge, 0, highEdge, 1
    Colour: "Black"
    Dotted line
    Draw line: crossover_frequency, 0, crossover_frequency, 1
    Solid line

    Draw inner box
    Marks bottom every: 1, gridStep, "yes", "yes", "no"
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Linear channel gain"
    Text top: "no", "Actual equal-power response"

    Font size: 6
    Colour: colLeft$
    Text: nyquist * 0.02, "left", 1.01, "half", "Left"
    Colour: colRight$
    Text: nyquist * 0.11, "left", 1.01, "half", "Right"

    # ---- Summary ----
    Select outer viewport: 0, 8, 4.80, 6.15
    Select inner viewport: 0.60, 7.70, 4.92, 6.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half",
        ... "##Crossover##  " + fixed$(crossover_frequency, 1) + " Hz"
        ... + "   band " + fixed$(lowEdge, 1) + "-" + fixed$(highEdge, 1) + " Hz"
        ... + "   depth " + fixed$(pan_depth * 100, 0) + "%"
    Text: 0.02, "left", 0.48, "half",
        ... "##Input##  " + string$(numChan) + " ch -> mono analysis"
        ... + "   SR " + fixed$(sampleRate, 0) + " Hz"
        ... + "   start " + fixed$(xminOriginal, 3) + " s"
        ... + "   duration " + fixed$(originalDur, 3) + " s"
    Text: 0.02, "left", 0.18, "half",
        ... "##Output##  stereo"
        ... + "   peak " + fixed$(peakIn, 4) + " -> " + fixed$(peakOut, 4)
        ... + "   safety gain " + fixed$(safetyGain, 4)
        ... + "   " + direction$

    Font size: 10
    Colour: "Black"
    Line width: 1
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoSound, spectrumFull, spectrumLeft, spectrumRight
removeObject: soundLeftFull, soundRightFull, leftChan, rightChan

# ============================================================
# INFO
# ============================================================
clearinfo
writeInfoLine: "=== Spectral Panner v0.4 ==="
appendInfoLine: "Input: ", originalName$, "  (", numChan, " ch -> mono analysis, ", fixed$(sampleRate, 0), " Hz)"
appendInfoLine: "Output: stereo  |  start ", fixed$(xminOriginal, 3), " s  |  duration ", fixed$(originalDur, 3), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Crossover: ", fixed$(crossover_frequency, 1), " Hz  |  transition ", fixed$(lowEdge, 1), "-", fixed$(highEdge, 1), " Hz"
appendInfoLine: "Pan depth: ", fixed$(pan_depth * 100, 0), "%  |  equal-power law"
appendInfoLine: direction$
appendInfoLine: "Peak: ", fixed$(peakIn, 4), " -> ", fixed$(peakOut, 4)
if safetyGain < 1
    appendInfoLine: "Safety attenuation: x", fixed$(safetyGain, 6), " (no normalization/boost applied)"
else
    appendInfoLine: "Safety attenuation: none (no normalization/boost applied)"
endif

selectObject: stereoOutput
if play_result
    Play
endif