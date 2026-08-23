# ============================================================
# Praat AudioTools - Constraint-Based_Duration_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Constraint-Based Duration Control using Optimality Theory (OT).
#   Auto-segments audio by silence detection, then applies OT
#   evaluation to adjust note durations based on weighted constraints:
#   - TARGET: Push toward target duration
#   - FAITHFULNESS: Preserve original duration
#
# Optimality Theory (Prince & Smolensky, 1993):
#   GEN: Generate candidate outputs
#   EVAL: Evaluate against ranked/weighted constraints
#   SELECT: Pick candidate with lowest violation score
#
# Changelog v0.4.1:
#   - Visualization-only alignment to the current Praat AudioTools suite.
#   - Reframed as Source -> Weighted duration solution -> Output -> Summary.
#   - The central map now directly visualizes the Harmonic Grammar law:
#       gray = original duration, red = target, blue = weighted solution.
#   - Unified panel geometry, left edges, typography and display-name sanitization.
#   - No DSP, segmentation, weighting or resynthesis changes.
#
# Changelog v0.4:
#   - CRITICAL: DurationTier construction rewritten. A single point at the
#     midpoint of each sounding interval caused Praat to linearly interpolate
#     ratios across neighbouring intervals and silences. v0.4 builds an
#     approximately piecewise-constant tier with transition points placed
#     immediately around each sounding boundary, leaving silences at 1.0.
#   - EVAL upgraded from three coarse candidates (original / target / 50-50)
#     to the exact minimum of the weighted squared-violation objective:
#         d* = (Wt * target + Wf * original) / (Wt + Wf)
#     This is the closed-form Harmonic Grammar solution and makes the numeric
#     weights behave continuously as advertised.
#   - Stereo is preserved. Analysis still uses a mono fold, but mono and
#     stereo channels are resynthesized separately with the same DurationTier
#     and stereo outputs are recombined in their original L/R order.
#   - Added validation for weights, pitch floor, segmentation values, and
#     the no-sounding-interval case.
#   - Uses DurationTier: Get target duration to report the exact duration
#     implied by the tier before resynthesis.
#   - Winner labels now describe faithful / target / weighted compromise
#     correctly; visualization remains compatible with the three categories.
#   - Non-zero Sound time domains are handled explicitly.
#
# Changelog v0.3:
#   - Mono fold for analysis: To TextGrid (silences) and To Manipulation
#     are mono-only; stereo input previously crashed. Output was mono.
#   - EVAL used squared violations (Harmonic Grammar style).
#   - Viz fix: legend viewport was 0..18 on an 8-inch page; corrected.
#
# Changelog v0.2:
#   - Fixed elsif syntax
#   - Added visualization
#   - Improved info output
# ============================================================

form OT Duration Control v0.4.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Staccato (short notes)
        option Legato (long notes)
        option Strict Timing (force target)
        option Natural (preserve original)
        option Balanced
    
    comment === OT Constraints ===
    real Weight_target_duration 2.0
    real Weight_faithfulness 1.0
    positive Target_duration_s 0.4
    
    comment === Auto-Segmentation ===
    positive Min_pitch_Hz 100
    real Silence_threshold_dB -25.0
    real Min_silent_interval_s 0.1
    real Min_sounding_interval_s 0.1
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Staccato
    weight_target_duration = 5.0
    weight_faithfulness = 0.5
    target_duration_s = 0.2
elsif preset = 3
    # Legato
    weight_target_duration = 1.0
    weight_faithfulness = 0.5
    target_duration_s = 0.8
elsif preset = 4
    # Strict Timing
    weight_target_duration = 10.0
    weight_faithfulness = 0.1
    target_duration_s = 0.4
elsif preset = 5
    # Natural
    weight_target_duration = 0.1
    weight_faithfulness = 5.0
    target_duration_s = 0.4
elsif preset = 6
    # Balanced
    weight_target_duration = 2.0
    weight_faithfulness = 1.0
    target_duration_s = 0.4
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Validate ===
if weight_target_duration < 0 or weight_faithfulness < 0
    exitScript: "Constraint weights must be >= 0."
endif
if weight_target_duration = 0 and weight_faithfulness = 0
    exitScript: "At least one constraint weight must be > 0."
endif
if min_pitch_Hz <= 0 or min_pitch_Hz >= 600
    exitScript: "Min pitch must be > 0 and < 600 Hz."
endif
if min_silent_interval_s < 0 or min_sounding_interval_s < 0
    exitScript: "Minimum silence/sounding interval durations must be >= 0."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sourceStart = Get start time
sourceEnd = Get end time
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

if numChannels > 2
    exitScript: "This version supports mono or stereo Sound objects."
endif

# Mono fold is used only for segmentation. Stereo resynthesis is preserved.
if numChannels > 1
    selectObject: sound
    analysisSound = Convert to mono
    createdMono = 1
else
    analysisSound = sound
    createdMono = 0
endif

# === Info ===
writeInfoLine: "=== Constraint-Based Duration Control v0.4.1 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(totalDuration, 2), " s; ", numChannels, " ch)"
appendInfoLine: ""
appendInfoLine: "Weighted constraints:"
appendInfoLine: "  TARGET weight: ", weight_target_duration, " (target: ", target_duration_s, " s)"
appendInfoLine: "  FAITHFULNESS weight: ", weight_faithfulness
appendInfoLine: ""

# === Auto-Segmentation ===
appendInfoLine: "Auto-segmenting by silence..."

selectObject: analysisSound
textGrid = To TextGrid (silences): min_pitch_Hz, 0.0, silence_threshold_dB, min_silent_interval_s, min_sounding_interval_s, "silent", "sounding"

selectObject: textGrid
numIntervals = Get number of intervals: 1

# Count sounding intervals
numSounding = 0
for i to numIntervals
    selectObject: textGrid
    label$ = Get label of interval: 1, i
    if label$ = "sounding"
        numSounding += 1
    endif
endfor

appendInfoLine: "Found ", numSounding, " sounding intervals"
appendInfoLine: ""

if numSounding < 1
    removeObject: textGrid
    if createdMono
        removeObject: analysisSound
    endif
    exitScript: "No sounding intervals were detected. Adjust the silence-detection settings."
endif

# === Store Original Durations for Visualization ===
intervalCount = 0
for i to numIntervals
    selectObject: textGrid
    label$ = Get label of interval: 1, i
    if label$ = "sounding"
        intervalCount += 1
        intStart[intervalCount] = Get start time of interval: 1, i
        intEnd[intervalCount] = Get end time of interval: 1, i
        intOrigDur[intervalCount] = intEnd[intervalCount] - intStart[intervalCount]
    endif
endfor

# === Weighted Constraint Evaluation ===
appendInfoLine: "=== Weighted Evaluation ==="
appendInfoLine: "Interval | Original | New dur | Ratio | Solution"
appendInfoLine: "---------|----------|---------|-------|--------------------"

intervals_processed = 0
weightSum = weight_target_duration + weight_faithfulness

for i to numIntervals
    selectObject: textGrid
    label$ = Get label of interval: 1, i

    if label$ = "sounding"
        intervals_processed += 1

        startTime = Get start time of interval: 1, i
        endTime = Get end time of interval: 1, i
        currentDur = endTime - startTime

        # Exact minimizer of:
        #   Wt * (d - target)^2 + Wf * (d - original)^2
        winnerDur = (weight_target_duration * target_duration_s + weight_faithfulness * currentDur) / weightSum

        # Classification is only for reporting/visualization.
        if weight_target_duration = 0
            winnerName$ = "A (faithful)"
            winnerType = 1
        elsif weight_faithfulness = 0
            winnerName$ = "B (target)"
            winnerType = 2
        else
            winnerName$ = "C (weighted compromise)"
            winnerType = 3
        endif

        ratio = winnerDur / currentDur

        # Store for visualization and DurationTier construction.
        intNewDur[intervals_processed] = winnerDur
        intWinnerType[intervals_processed] = winnerType
        intRatio[intervals_processed] = ratio

        appendInfoLine: "   ", intervals_processed, "    |  ", fixed$(currentDur, 3), "  |  ", fixed$(winnerDur, 3), " | ", fixed$(ratio, 3), " | ", winnerName$
    endif
endfor

# === Build Piecewise DurationTier ===
# Praat linearly interpolates DurationTier values. To make each sounding
# interval behave approximately as a constant ratio while preserving silences
# at ratio 1.0, put pairs of points immediately around each boundary.
Create DurationTier: "OT_duration", sourceStart, sourceEnd
durTier = selected("DurationTier")

# Baseline: unchanged duration outside sounding intervals.
selectObject: durTier
Add point: sourceStart, 1
Add point: sourceEnd, 1

soundingIndex = 0
for i to numIntervals
    selectObject: textGrid
    label$ = Get label of interval: 1, i

    if label$ = "sounding"
        soundingIndex += 1
        startTime = Get start time of interval: 1, i
        endTime = Get end time of interval: 1, i
        currentDur = endTime - startTime
        ratio = intRatio[soundingIndex]

        # A micro-transition makes the integral differ from the ideal
        # piecewise-constant mapping only negligibly while avoiding a long
        # interpolation ramp through neighbouring silence.
        edgeEps = min(0.000001, currentDur / 4)

        selectObject: durTier

        if startTime > sourceStart
            Add point: max(sourceStart, startTime - edgeEps), 1
        endif
        Add point: min(endTime, startTime + edgeEps), ratio

        Add point: max(startTime, endTime - edgeEps), ratio
        if endTime < sourceEnd
            Add point: min(sourceEnd, endTime + edgeEps), 1
        endif
    endif
endfor

# Exact duration implied by the DurationTier integral.
selectObject: durTier
predictedDuration = Get target duration: sourceStart, sourceEnd
appendInfoLine: ""
appendInfoLine: "Duration implied by tier: ", fixed$(predictedDuration, 6), " s"

# === Resynthesis ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

if numChannels = 1
    # Mono: resynthesize the original channel directly.
    selectObject: sound
    manipulation = To Manipulation: 0.01, min_pitch_Hz, 600

    selectObject: manipulation
    plusObject: durTier
    Replace duration tier

    selectObject: manipulation
    result = Get resynthesis (overlap-add)
    Rename: sound_name$ + "_OT"

    removeObject: manipulation
else
    # Stereo: analyze/resynthesize each original channel independently,
    # using exactly the same DurationTier for temporal alignment.
    selectObject: sound
    Extract one channel: 1
    channel1 = selected("Sound")

    selectObject: channel1
    manipulation1 = To Manipulation: 0.01, min_pitch_Hz, 600
    selectObject: manipulation1
    plusObject: durTier
    Replace duration tier
    selectObject: manipulation1
    resultL = Get resynthesis (overlap-add)

    selectObject: sound
    Extract one channel: 2
    channel2 = selected("Sound")

    selectObject: channel2
    manipulation2 = To Manipulation: 0.01, min_pitch_Hz, 600
    selectObject: manipulation2
    plusObject: durTier
    Replace duration tier
    selectObject: manipulation2
    resultR = Get resynthesis (overlap-add)

    # resultL was created before resultR, so Object-list order is L then R.
    selectObject: resultL, resultR
    Combine to stereo
    result = selected("Sound")
    Rename: sound_name$ + "_OT"

    removeObject: manipulation1, manipulation2, channel1, channel2, resultL, resultR
endif

# === Cleanup ===
removeObject: textGrid, durTier
if createdMono
    removeObject: analysisSound
endif

# === Get Result Duration ===
selectObject: result
resultDuration = Get total duration

# ============================================================
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> Weighted duration solution -> Output -> Summary.
# The central map directly embodies the weighted solution law:
#   d* = (Wt * target + Wf * original) / (Wt + Wf)
# gray = original duration, red = target, blue = weighted solution.
# ============================================================
if draw_visualization and intervals_processed > 0
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(sound_name$, "_", " ", 0)

    if preset = 1
        presetName$ = "Custom"
    elsif preset = 2
        presetName$ = "Staccato"
    elsif preset = 3
        presetName$ = "Legato"
    elsif preset = 4
        presetName$ = "Strict Timing"
    elsif preset = 5
        presetName$ = "Natural"
    else
        presetName$ = "Balanced"
    endif

    # Mono, zero-based display copies.
    selectObject: sound
    vizOrig = Convert to mono
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    selectObject: result
    vizResult = Convert to mono
    selectObject: vizResult
    vizResultStart = Get start time
    Shift times by: -vizResultStart

    # Shared source/output amplitude scale.
    selectObject: vizOrig
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    outPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(origPeak, outPeak)
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Constraint-Based Duration Control##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Constraint-Based Duration Control.praat  |  " + displayName$ + "  |  weighted TARGET + FAITHFULNESS"

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, totalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, -sharedAmp, sharedAmp

    # Neutral segmentation guides for the sounding intervals.
    Colour: "{0.88, 0.88, 0.90}"
    for k to intervals_processed
        segStart = intStart[k] - sourceStart
        segEnd = intEnd[k] - sourceStart
        Dotted line
        Draw line: segStart, -sharedAmp, segStart, sharedAmp
        Draw line: segEnd, -sharedAmp, segEnd, sharedAmp
        Solid line
    endfor

    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, totalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, totalDuration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * totalDuration, "left", 0.82 * sharedAmp, "half", string$(intervals_processed) + " sounding intervals  |  silence threshold " + fixed$(silence_threshold_dB, 1) + " dB"

    # ----------------------------------------------------------
    # WEIGHTED DURATION SOLUTION
    # ----------------------------------------------------------
    maxDur = target_duration_s
    minDur = target_duration_s
    for k to intervals_processed
        if intOrigDur[k] > maxDur
            maxDur = intOrigDur[k]
        endif
        if intNewDur[k] > maxDur
            maxDur = intNewDur[k]
        endif
        if intOrigDur[k] < minDur
            minDur = intOrigDur[k]
        endif
        if intNewDur[k] < minDur
            minDur = intNewDur[k]
        endif
    endfor
    durTop = max(maxDur * 1.28, target_duration_s + 0.18)
    if durTop <= 0
        durTop = 1
    endif

    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.22, 4.40
    Axes: 0.5, intervals_processed + 0.5, 0, durTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, intervals_processed + 0.5, 0, durTop

    # Target duration is common to every interval.
    Colour: "{0.82, 0.34, 0.24}"
    Dotted line
    Draw line: 0.5, target_duration_s, intervals_processed + 0.5, target_duration_s
    Solid line

    # Per-interval solution: original -> weighted optimum.
    for k to intervals_processed
        # neutral guide from original to target
        Colour: "{0.78, 0.78, 0.80}"
        Line width: 0.8
        Draw line: k, intOrigDur[k], k, target_duration_s

        # actual movement from original to solution
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1.8
        Draw line: k, intOrigDur[k], k, intNewDur[k]
        Line width: 1

        Paint circle (mm): "{0.58, 0.58, 0.62}", k, intOrigDur[k], 1.05
        Paint circle (mm): "{0.25, 0.50, 0.82}", k, intNewDur[k], 1.05
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Weighted duration solution##"
    Font size: 6
    Text left: "yes", "Duration (s)"
    Text bottom: "yes", "Sounding interval #"
    Marks left every: 1, 0.2, "yes", "yes", "no"

    # Same inset for all panel annotation text.
    Axes: 0.5, intervals_processed + 0.5, 0, durTop
    insetX = 0.5 + 0.01 * intervals_processed
    Colour: "{0.28, 0.28, 0.28}"
    Text: insetX, "left", 0.95 * durTop, "half", "gray = original  |  red = target  |  blue = weighted solution"
    Colour: "{0.35, 0.35, 0.52}"
    Text: insetX, "left", 0.87 * durTop, "half", "d* = (Wt target + Wf original) / (Wt + Wf)   |   Wt " + fixed$(weight_target_duration, 2) + "   Wf " + fixed$(weight_faithfulness, 2)

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, resultDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, resultDuration, -sharedAmp, sharedAmp
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, resultDuration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, resultDuration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * resultDuration, "left", 0.82 * sharedAmp, "half", "duration " + fixed$(totalDuration, 3) + " -> " + fixed$(resultDuration, 3) + " s  |  silences preserved at ratio 1.0"

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    ratioMean = 0
    minRatio = intRatio[1]
    maxRatio = intRatio[1]
    for k to intervals_processed
        ratioMean += intRatio[k]
        if intRatio[k] < minRatio
            minRatio = intRatio[k]
        endif
        if intRatio[k] > maxRatio
            maxRatio = intRatio[k]
        endif
    endfor
    ratioMean = ratioMean / intervals_processed

    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetName$ + "  |  target " + fixed$(target_duration_s, 3) + " s  |  Wt " + fixed$(weight_target_duration, 2) + "  |  Wf " + fixed$(weight_faithfulness, 2) + "  |  " + string$(intervals_processed) + " sounding intervals"
    Text: 0.02, "left", 0.18, "half", "Ratio mean " + fixed$(ratioMean, 3) + "  |  range " + fixed$(minRatio, 3) + "-" + fixed$(maxRatio, 3) + "  |  duration " + fixed$(totalDuration, 3) + " -> " + fixed$(resultDuration, 3) + " s  |  prediction error " + fixed$((resultDuration - predictedDuration) * 1000, 2) + " ms"

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig, vizResult
    selectObject: result
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original duration: ", fixed$(totalDuration, 2), " s"
appendInfoLine: "Predicted duration: ", fixed$(predictedDuration, 4), " s"
appendInfoLine: "Result duration: ", fixed$(resultDuration, 4), " s"
appendInfoLine: "Prediction error: ", fixed$((resultDuration - predictedDuration) * 1000, 2), " ms"
appendInfoLine: "Intervals processed: ", intervals_processed
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result