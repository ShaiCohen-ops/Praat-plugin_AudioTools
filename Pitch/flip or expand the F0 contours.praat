# ============================================================
# Praat AudioTools - flip_or_expand_the_F0_contours.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Manipulates F0 (pitch) contours using PSOLA resynthesis.
#   Can flip, expand/contract, or flatten pitch contours.
# ============================================================
#
# Changelog v0.7.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.7: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.7:
#   - Flip and Expand/Contract now operate in logarithmic pitch space.
#     Flip mirrors musical intervals around a robust median-F0 centre.
#   - Expand/Contract scales interval distance around that centre.
#   - Preserves the original channel count: one mono pitch analysis is
#     applied as the same target PitchTier to every original channel.
#   - Uses a fixed 100-Hz control grid and preserves xmin/xmax.
#   - Stops when no usable pitch is detected instead of inventing a mean.
#   - Validates pitch limits and Flatten_target_hz.
#   - Prevents non-positive / sampling-unsafe target F0 values.
#   - Visualization uses the real Sound time domain and explicit title axes.
#   - Final peak handling is attenuation-only.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form F0 Contour Manipulation v0.7.1
    optionmenu Preset: 1
        option Custom
        option Flip (Mirror pitch)
        option Expand (More expressive)
        option Contract (Less expressive)
        option Flatten (Monotone)
        option Exaggerate (Strong expansion)
        option Subtle Expansion
        option High Voice Flatten
        option Low Voice Flatten
    comment === Method ===
    optionmenu Method: 1
        option Flip F0 contour
        option Expand/Contract F0
        option Flatten F0
    comment === Parameters ===
    positive Expansion_factor 1.3
    comment (>1 expand, <1 contract)
    real Flatten_target_hz 0
    comment (0 = use mean pitch)
    comment === Pitch Range ===
    positive Min_pitch 70
    positive Max_pitch 400
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    method = 1
    presetName$ = "Flip"
elsif preset = 3
    method = 2
    expansion_factor = 1.5
    presetName$ = "Expand"
elsif preset = 4
    method = 2
    expansion_factor = 0.5
    presetName$ = "Contract"
elsif preset = 5
    method = 3
    flatten_target_hz = 0
    presetName$ = "Flatten"
elsif preset = 6
    method = 2
    expansion_factor = 2.0
    presetName$ = "Exaggerate"
elsif preset = 7
    method = 2
    expansion_factor = 1.2
    presetName$ = "SubtleExpand"
elsif preset = 8
    method = 3
    flatten_target_hz = 200
    presetName$ = "HighFlatten"
elsif preset = 9
    method = 3
    flatten_target_hz = 100
    presetName$ = "LowFlatten"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
startTime = Get start time
endTime = Get end time
duration = endTime - startTime
sampleRate = Get sampling frequency
nChannels = Get number of channels

# === Validate Parameters ===
if min_pitch >= max_pitch
    exitScript: "Min_pitch must be lower than Max_pitch."
endif
if max_pitch >= sampleRate / 2
    exitScript: "Max_pitch must be below the Nyquist frequency (" + fixed$(sampleRate / 2, 1) + " Hz)."
endif
if flatten_target_hz < 0
    exitScript: "Flatten_target_hz must be 0 (use detected centre) or a positive frequency."
endif
if flatten_target_hz > 0 and flatten_target_hz >= 0.45 * sampleRate
    exitScript: "Flatten_target_hz is too high for the current sampling rate."
endif

clearinfo
writeInfoLine: "=== F0 Contour Manipulation v0.7.1 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Channels preserved: ", nChannels
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
if method = 1
    appendInfoLine: "Method: Flip"
elsif method = 2
    appendInfoLine: "Method: Expand/Contract (factor: ", expansion_factor, ")"
else
    appendInfoLine: "Method: Flatten"
endif
appendInfoLine: "Pitch range: ", min_pitch, "-", max_pitch, " Hz"
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================

appendInfoLine: "Creating mono pitch-analysis reference..."

selectObject: originalID
if nChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: originalName$ + "_F0_analysis"
endif

selectObject: analysisMono
analysisPitchID = To Pitch: 0.01, min_pitch, max_pitch

# The median is robust; because log-frequency is monotonic, this is also the
# median reference point in logarithmic pitch space.
selectObject: analysisPitchID
centrePitch = Get quantile: 0, 0, 0.5, "Hertz"

if centrePitch = undefined or centrePitch <= 0
    removeObject: analysisPitchID, analysisMono
    exitScript: "No usable pitch was detected." + newline$
        ... + "F0 Contour Manipulation requires voiced / periodic material."
endif

appendInfoLine: "Reference centre (median F0): ", fixed$(centrePitch, 1), " Hz"

if method = 3
    if flatten_target_hz = 0
        targetPitch = centrePitch
    else
        targetPitch = flatten_target_hz
    endif
endif

Create PitchTier: "modified_pitch", startTime, endTime
newPitchTierID = selected("PitchTier")

controlStep = 0.01
numSteps = ceiling(duration / controlStep)
targetMinHz = 20
targetMaxHz = 0.45 * sampleRate
voicedPoints = 0
limitedPoints = 0
observedMin = 1e30
observedMax = 0

appendInfo: "Applying ", presetName$, "..."

for i from 0 to numSteps
    if i = numSteps
        t = endTime
    else
        t = min(endTime, startTime + i * controlStep)
    endif

    selectObject: analysisPitchID
    sourceF0 = Get value at time: t, "Hertz", "Linear"

    if sourceF0 <> undefined and sourceF0 > 0
        if method = 1
            # Log mirror: log(newF0) = 2*log(centre) - log(sourceF0)
            newF0 = centrePitch * centrePitch / sourceF0

        elsif method = 2
            # Log expansion/contraction:
            # log(new/centre) = factor * log(source/centre)
            newF0 = centrePitch * ((sourceF0 / centrePitch) ^ expansion_factor)

        else
            newF0 = targetPitch
        endif

        if newF0 < targetMinHz
            newF0 = targetMinHz
            limitedPoints += 1
        elsif newF0 > targetMaxHz
            newF0 = targetMaxHz
            limitedPoints += 1
        endif

        selectObject: newPitchTierID
        Add point: t, newF0
        voicedPoints += 1

        if sourceF0 < observedMin
            observedMin = sourceF0
        endif
        if newF0 < observedMin
            observedMin = newF0
        endif
        if sourceF0 > observedMax
            observedMax = sourceF0
        endif
        if newF0 > observedMax
            observedMax = newF0
        endif
    endif
endfor

appendInfoLine: " done"

if voicedPoints = 0
    removeObject: newPitchTierID, analysisPitchID, analysisMono
    exitScript: "Pitch analysis produced no usable F0 control points."
endif

appendInfoLine: "Control points: ", voicedPoints
if limitedPoints > 0
    appendInfoLine: "Sampling-safe F0 limits applied: ", limitedPoints, " point(s)"
endif

appendInfoLine: "Resynthesizing ", nChannels, " channel(s)..."

resultID = Create Sound from formula: originalName$ + "_F0_" + presetName$, nChannels, startTime, endTime, sampleRate, "0"

for ch from 1 to nChannels
    selectObject: originalID
    if nChannels = 1
        channelWork = Copy: originalName$ + "_F0_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: originalName$ + "_F0_ch" + string$(ch)
    endif

    selectObject: channelWork
    channelManip = To Manipulation: 0.01, min_pitch, max_pitch

    selectObject: newPitchTierID
    plusObject: channelManip
    Replace pitch tier

    selectObject: channelManip
    channelRes = Get resynthesis (overlap-add)

    selectObject: resultID
    Formula (part): startTime, endTime, ch, ch, "object['channelRes:0', 1, col]"

    removeObject: channelManip, channelWork, channelRes
endfor

selectObject: resultID
Rename: originalName$ + "_F0_" + presetName$

outputPeak = Get absolute extremum: 0, 0, "None"
if outputPeak > 0.99
    Scale peak: 0.99
    safetyApplied = 1
else
    safetyApplied = 0
endif

appendInfoLine: "Resynthesis done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    # Reuse the mono source pitch analysis for the original contour.
    origPitchID = analysisPitchID

    # Analyse a mono view of the processed output for display.
    selectObject: resultID
    if nChannels > 1
        resultVizMono = Convert to mono
    else
        resultVizMono = Copy: originalName$ + "_F0_viz"
    endif

    visPitchFloor = max(20, min(min_pitch, observedMin * 0.8))
    visPitchCeiling = min(0.45 * sampleRate, max(max_pitch, observedMax * 1.2))
    if visPitchCeiling <= visPitchFloor
        visPitchCeiling = min(0.45 * sampleRate, visPitchFloor * 2)
    endif

    selectObject: resultVizMono
    resPitchID = To Pitch: 0.01, visPitchFloor, visPitchCeiling
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "F0 Contour Manipulation v0.7.1: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Modified"
    
    # Pitch contour comparison
    Select outer viewport: 0, 8, 2.0, 4.2
    Select inner viewport: 0.6, 7.6, 2.3, 4.0

    plotMin = max(20, observedMin * 0.9)
    plotMax = min(0.45 * sampleRate, observedMax * 1.1)
    if plotMax <= plotMin
        plotMax = plotMin * 1.5
    endif

    Axes: startTime, endTime, plotMin, plotMax

    selectObject: origPitchID
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 2
    Draw: startTime, endTime, plotMin, plotMax, "no"

    selectObject: resPitchID
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw: startTime, endTime, plotMin, plotMax, "no"

    # Reference-centre line
    Colour: "{0.9, 0.4, 0.4}"
    Line width: 1
    Dotted line
    Draw line: startTime, centrePitch, endTime, centrePitch
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Pitch Contour (gray=original, blue=modified, red=median reference)"
    Text left: "yes", "F0 (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Info panel
    Select outer viewport: 0, 8, 4.4, 5.0
    Select inner viewport: 0.5, 7.7, 4.45, 4.95
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.3}"
    
    if method = 1
        Text: 0.02, "left", 0.5, "half", "Method: Flip around mean"
    elsif method = 2
        Text: 0.02, "left", 0.5, "half", "Method: Expand/Contract (x" + fixed$(expansion_factor, 2) + ")"
    else
        Text: 0.02, "left", 0.5, "half", "Method: Flatten to " + fixed$(targetPitch, 0) + " Hz"
    endif
    
    Text: 0.45, "left", 0.5, "half", "Median reference: " + fixed$(centrePitch, 1) + " Hz"
    Text: 0.7, "left", 0.5, "half", "Range: " + string$(min_pitch) + "-" + string$(max_pitch) + " Hz"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
    removeObject: resPitchID, resultVizMono

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.12, 5.68
    Select inner viewport: 0.60, 7.70, 5.12 + 0.04, 5.68 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Original F0 • contour transform law • transformed F0"
    Text: 0.02, "left", 0.20, "half", "F0 Contour Manipulation • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 5.78
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: analysisPitchID, analysisMono, newPitchTierID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_F0_", presetName$
appendInfoLine: "Output channels: ", nChannels
appendInfoLine: "Peak safety applied: ", safetyApplied

if play_result
    selectObject: resultID
    Play
endif
