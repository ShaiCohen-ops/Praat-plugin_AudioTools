# ============================================================
# Praat AudioTools - Constraint-Based_Duration_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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

form OT Duration Control v0.4
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
writeInfoLine: "=== Constraint-Based Duration Control v0.4 ==="
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

# === Visualization ===
if draw_visualization and intervals_processed > 0
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "OT Duration Control: " + sound_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.9, 2.3
    Select inner viewport: 0.6, 7.6, 1.0, 2.2
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 2.8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.4, 3.8
    Select inner viewport: 0.6, 7.6, 2.5, 3.7
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "OT Result"
    Text bottom: "yes", "Time (s)"
    
    # Duration comparison bar chart
    Select outer viewport: 0, 8, 4.0, 6.0
    Select inner viewport: 0.6, 7.6, 4.2, 5.9
    
    # Find max duration for scaling
    maxDur = target_duration_s
    for k to intervals_processed
        if intOrigDur[k] > maxDur
            maxDur = intOrigDur[k]
        endif
        if intNewDur[k] > maxDur
            maxDur = intNewDur[k]
        endif
    endfor
    maxDur = maxDur * 1.1
    
    Axes: 0, intervals_processed + 1, 0, maxDur
    
    # Background
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, intervals_processed + 1, 0, maxDur
    
    # Target line
    Colour: "{0.8, 0.3, 0.3}"
    Dotted line
    Draw line: 0, target_duration_s, intervals_processed + 1, target_duration_s
    Solid line
    
    # Bars
    barWidth = 0.35
    for k to intervals_processed
        # Original (gray)
        Colour: "{0.6, 0.6, 0.6}"
        Paint rectangle: "{0.6, 0.6, 0.6}", k - barWidth, k, 0, intOrigDur[k]
        
        # New (colored by winner type)
        if intWinnerType[k] = 1
            # Green for faithful
            Colour: "{0.3, 0.7, 0.3}"
            Paint rectangle: "{0.3, 0.7, 0.3}", k, k + barWidth, 0, intNewDur[k]
        elsif intWinnerType[k] = 2
            # Red for target
            Colour: "{0.8, 0.3, 0.3}"
            Paint rectangle: "{0.8, 0.3, 0.3}", k, k + barWidth, 0, intNewDur[k]
        else
            # Blue for compromise
            Colour: "{0.3, 0.5, 0.8}"
            Paint rectangle: "{0.3, 0.5, 0.8}", k, k + barWidth, 0, intNewDur[k]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.2, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Duration (s)"
    Text bottom: "yes", "Interval"
    
    # Legend
    Select outer viewport: 0, 8, 6.1, 6.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.6, 0.6, 0.6}"
    Text: 0.15, "centre", 0.5, "half", "## Original"
    Colour: "{0.3, 0.7, 0.3}"
    Text: 0.35, "centre", 0.5, "half", "## Faithful"
    Colour: "{0.8, 0.3, 0.3}"
    Text: 0.55, "centre", 0.5, "half", "## Target"
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.75, "centre", 0.5, "half", "## Compromise"
    Colour: "{0.8, 0.3, 0.3}"
    Text: 0.92, "centre", 0.5, "half", "--- Target"
    
    Font size: 10
    Colour: "Black"
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