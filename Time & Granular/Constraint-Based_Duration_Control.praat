# ============================================================
# Praat AudioTools - Constraint-Based_Duration_Control.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
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
# Changelog v0.3:
#   - Mono fold for analysis: To TextGrid (silences) and To Manipulation
#     are mono-only; stereo input previously crashed. Output is mono
#     (PSOLA resynthesis is inherently mono).
#   - EVAL now uses squared violations (Harmonic Grammar style). Under
#     the old linear (L1) violations the compromise candidate was the
#     average of the two extremes and could never win; squared violations
#     let the midpoint beat both, so all three candidates are reachable.
#   - Viz fix: legend viewport was 0..18 on an 8-inch page (3 of 5 items
#     fell off the right edge); now 0..8 with explicit axes.
#
# Changelog v0.2:
#   - Fixed elsif syntax
#   - Added visualization
#   - Improved info output
# ============================================================

form OT Duration Control
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
    real Min_pitch_Hz 100
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

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# Mono fold for analysis (To TextGrid/To Manipulation are mono-only)
if numChannels > 1
    selectObject: sound
    analysisSound = Convert to mono
    createdMono = 1
else
    analysisSound = sound
    createdMono = 0
endif

# === Info ===
writeInfoLine: "=== OT Duration Control ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Constraints:"
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

# === Create Manipulation Object ===
selectObject: analysisSound
manipulation = To Manipulation: 0.01, min_pitch_Hz, 600

selectObject: manipulation
durTier = Extract duration tier

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

# === OT Evaluation Loop ===
appendInfoLine: "=== OT Evaluation ==="
appendInfoLine: "Interval | Original | Winner | Ratio | Best Candidate"
appendInfoLine: "---------|----------|--------|-------|---------------"

intervals_processed = 0

for i to numIntervals
    selectObject: textGrid
    label$ = Get label of interval: 1, i
    
    if label$ = "sounding"
        intervals_processed += 1
        
        startTime = Get start time of interval: 1, i
        endTime = Get end time of interval: 1, i
        currentDur = endTime - startTime
        
        # === GEN: Generate Candidates ===
        # Candidate A: Faithful (keep original)
        candA = currentDur
        # Candidate B: Target (use target duration)
        candB = target_duration_s
        # Candidate C: Compromise (50/50 blend)
        candC = (currentDur * 0.5) + (target_duration_s * 0.5)
        
        # === EVAL: Calculate Violation Scores (squared / Harmonic Grammar) ===
        
        # Candidate A (faithful): No faithfulness violation
        violTarget_A = (candA - target_duration_s) ^ 2
        violFaith_A = 0
        score_A = (violTarget_A * weight_target_duration) + (violFaith_A * weight_faithfulness)
        
        # Candidate B (target): No target violation
        violTarget_B = 0
        violFaith_B = (candB - currentDur) ^ 2
        score_B = (violTarget_B * weight_target_duration) + (violFaith_B * weight_faithfulness)
        
        # Candidate C (compromise): Partial violations
        violTarget_C = (candC - target_duration_s) ^ 2
        violFaith_C = (candC - currentDur) ^ 2
        score_C = (violTarget_C * weight_target_duration) + (violFaith_C * weight_faithfulness)
        
        # === SELECT: Pick Winner ===
        winnerDur = candA
        bestScore = score_A
        winnerName$ = "A (faithful)"
        winnerType = 1
        
        if score_B < bestScore
            winnerDur = candB
            bestScore = score_B
            winnerName$ = "B (target)"
            winnerType = 2
        endif
        if score_C < bestScore
            winnerDur = candC
            bestScore = score_C
            winnerName$ = "C (compromise)"
            winnerType = 3
        endif
        
        # Store for visualization
        intNewDur[intervals_processed] = winnerDur
        intWinnerType[intervals_processed] = winnerType
        
        # Calculate duration ratio
        ratio = winnerDur / currentDur
        
        # Apply to duration tier
        selectObject: durTier
        midpoint = (startTime + endTime) / 2
        Add point: midpoint, ratio
        
        # Log
        appendInfoLine: "   ", intervals_processed, "    |  ", fixed$(currentDur, 3), "  |  ", fixed$(winnerDur, 3), " | ", fixed$(ratio, 2), "  | ", winnerName$
    endif
endfor

# === Resynthesis ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

selectObject: manipulation
plusObject: durTier
Replace duration tier

selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: sound_name$ + "_OT"

# === Cleanup ===
removeObject: textGrid, manipulation, durTier
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
appendInfoLine: "Result duration: ", fixed$(resultDuration, 2), " s"
appendInfoLine: "Intervals processed: ", intervals_processed
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result