# ============================================================
# Praat AudioTools - Tempo-Pitch Curves (Accelerando & Ritardando)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tempo Curves (Accelerando & Ritardando) with Visualization.
# ============================================================
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Tempo and pitch now follow the same LOCAL curve in Pitch+Duration mode.
#   - Target duration is built directly into the DurationTier; no post-process
#     Change gender stage is used.
#   - DurationTier and PitchTier are fully xmin/xmax safe.
#   - Mono is used for pitch analysis only; exact source channel count is preserved.
#   - Adaptive pitch analysis: 40 .. min(1200, 0.45*sampleRate) Hz.
#   - No-pitch material still receives the duration curve; pitch shifting is skipped.
#   - Strength=0 with Keep original duration is a true identity copy (PSOLA bypassed).
#   - Effective tempo curve shown in visualization matches the normalized/applied tier.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; title/stats coordinate bugs corrected.
# ============================================================

form Tempo Curves (Accelerando & Ritardando) v0.4.1
    comment Apply tempo variations to the selected sound
    comment 
    optionmenu Pattern_type 1
        option Accelerando (slow -> fast)
        option Ritardando (fast -> slow)
        option Slow-Fast-Slow
    comment 
    optionmenu Pitch_behavior 1
        option Pitch changes with tempo (PSOLA + pitch shift)
        option Keep pitch constant (PSOLA duration only)
    comment 
    real Strength 2.0
    comment    (1 = mild, 2 = medium, 3 = strong)
    comment 
    optionmenu Duration_mode 1
        option Keep original duration
        option Specify new duration
    real Target_duration 5.0
    comment 
    boolean Draw_visualization 1
    boolean Play_result_when_finished 1
endform

##############################################################################
# STEP 1: Validate input and read source metadata
##############################################################################

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: sound
originalDuration = Get total duration
samplingFrequency = Get sampling frequency
numberOfChannels = Get number of channels
xmin = Get start time
xmax = Get end time

patternType = pattern_type
pitchBehavior = pitch_behavior
durationMode = duration_mode
targetDuration = target_duration

if patternType = 1
    patternName$ = "Accelerando"
elsif patternType = 2
    patternName$ = "Ritardando"
else
    patternName$ = "Slow-Fast-Slow"
endif

if originalDuration <= 0
    exitScript: "Error: The selected Sound has no positive duration."
endif
if strength < 0 or strength > 5
    exitScript: "Error: Strength must be between 0 and 5."
endif
if durationMode = 2 and targetDuration <= 0.01
    exitScript: "Error: Target duration must be greater than 0.01 seconds."
endif
if samplingFrequency < 1000
    exitScript: "Error: Sampling frequency is too low for safe pitch processing."
endif

if durationMode = 1
    desiredDurationRatio = 1
else
    desiredDurationRatio = targetDuration / originalDuration
    # DurationTier safety range below is 0.3..3.0; requests outside this
    # ratio cannot be represented robustly without a second time-scaling stage.
    if desiredDurationRatio < 0.3 or desiredDurationRatio > 3.0
        exitScript: "Error: Target duration must be between 0.3x and 3.0x the original duration."
    endif
endif

# True identity only when both the curve and requested duration are neutral.
identity_mode = 0
if strength = 0 and desiredDurationRatio = 1
    identity_mode = 1
endif

##############################################################################
# STEP 2: Build the effective tempo/duration curve
##############################################################################

minTempoFactor = 1.0 - (0.25 * strength)
maxTempoFactor = 1.0 + (0.35 * strength)

if minTempoFactor < 0.4
    minTempoFactor = 0.4
endif
if maxTempoFactor > 3.0
    maxTempoFactor = 3.0
endif

numPoints = 100
curveTimesRel# = zero#(numPoints + 1)
rawDurationFactors# = zero#(numPoints + 1)
appliedDurationFactors# = zero#(numPoints + 1)
vizTimes# = zero#(numPoints + 1)
vizFactors# = zero#(numPoints + 1)

# Raw duration factor = inverse of desired tempo factor.
for i from 0 to numPoints
    x = i / numPoints
    tRel = x * originalDuration

    if patternType = 1
        rawTempo = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
    elsif patternType = 2
        rawTempo = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
    else
        centered = (x - 0.5) * 2
        rawTempo = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
    endif

    rawDur = 1 / rawTempo
    if rawDur < 0.3
        rawDur = 0.3
    elsif rawDur > 3.0
        rawDur = 3.0
    endif

    curveTimesRel#[i + 1] = tRel
    rawDurationFactors#[i + 1] = rawDur
endfor

# Find a single global scale by bisection so the mean APPLIED duration factor
# matches the requested output-duration ratio, even when safety clamping occurs.
scaleLow = 0.0001
scaleHigh = 10000

for iter from 1 to 50
    testScale = (scaleLow + scaleHigh) / 2
    integral = 0

    for i from 1 to numPoints
        d1 = rawDurationFactors#[i] * testScale
        d2 = rawDurationFactors#[i + 1] * testScale

        if d1 < 0.3
            d1 = 0.3
        elsif d1 > 3.0
            d1 = 3.0
        endif
        if d2 < 0.3
            d2 = 0.3
        elsif d2 > 3.0
            d2 = 3.0
        endif

        dt = curveTimesRel#[i + 1] - curveTimesRel#[i]
        integral += 0.5 * (d1 + d2) * dt
    endfor

    testMean = integral / originalDuration

    if testMean < desiredDurationRatio
        scaleLow = testScale
    else
        scaleHigh = testScale
    endif
endfor

durationScale = (scaleLow + scaleHigh) / 2

# Final applied DurationTier values and the ACTUAL effective tempo curve.
for i from 0 to numPoints
    appliedDur = rawDurationFactors#[i + 1] * durationScale
    if appliedDur < 0.3
        appliedDur = 0.3
    elsif appliedDur > 3.0
        appliedDur = 3.0
    endif

    appliedDurationFactors#[i + 1] = appliedDur
    vizTimes#[i + 1] = curveTimesRel#[i + 1]
    vizFactors#[i + 1] = 1 / appliedDur
endfor

# Log the actual integrated ratio represented by the final tier.
integral = 0
for i from 1 to numPoints
    dt = curveTimesRel#[i + 1] - curveTimesRel#[i]
    integral += 0.5 * (appliedDurationFactors#[i] + appliedDurationFactors#[i + 1]) * dt
endfor
representedDurationRatio = integral / originalDuration

writeInfoLine: "=== Tempo-Pitch Curves v0.4.1 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(originalDuration, 3), " s, ", numberOfChannels, " ch)"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: "Strength: ", strength
appendInfoLine: "Requested duration ratio: ", fixed$(desiredDurationRatio, 4)
appendInfoLine: "Tier duration ratio: ", fixed$(representedDurationRatio, 4)
appendInfoLine: ""

##############################################################################
# STEP 3: Identity path or shared analysis/tiers
##############################################################################

safetyApplied = 0
pitchAvailable = 0
analysisMono = 0
analysisManip = 0
originalPitchTier = 0
shiftedPitchTier = 0
durationTier = 0

if identity_mode
    selectObject: sound
    newSound = Copy: soundName$ + "_tempo_identity"
    appendInfoLine: "Strength=0 and original-duration mode: exact copy (PSOLA bypassed)."

else
    # Shared duration tier in the source's TRUE time domain.
    Create DurationTier: "tempo_curve", xmin, xmax
    durationTier = selected("DurationTier")

    for i from 0 to numPoints
        tAbs = xmin + curveTimesRel#[i + 1]
        selectObject: durationTier
        Add point: tAbs, appliedDurationFactors#[i + 1]
    endfor

    # Pitch analysis only when the user asks for pitch to follow tempo.
    if pitchBehavior = 1
        pitchFloor = 40
        pitchCeil = min(1200, 0.45 * samplingFrequency)

        if pitchCeil <= pitchFloor
            exitScript: "Error: Sampling frequency is too low for the adaptive pitch range."
        endif

        selectObject: sound
        if numberOfChannels > 1
            analysisMono = Convert to mono
        else
            analysisMono = Copy: "TPC_analysis"
        endif

        selectObject: analysisMono
        analysisManip = To Manipulation: 0.01, pitchFloor, pitchCeil

        selectObject: analysisManip
        originalPitchTier = Extract pitch tier

        selectObject: originalPitchTier
        nPitchPoints = Get number of points

        if nPitchPoints > 0
            pitchAvailable = 1

            Create PitchTier: "tempo_pitch", xmin, xmax
            shiftedPitchTier = selected("PitchTier")

            synthFloor = 20
            synthCeil = 0.45 * samplingFrequency
            limitedPitchPoints = 0

            # Local pitch multiplier = LOCAL EFFECTIVE TEMPO factor.
            for p from 1 to nPitchPoints
                selectObject: originalPitchTier
                pointTime = Get time from index: p
                pointPitch = Get value at index: p

                x = (pointTime - xmin) / originalDuration
                if x < 0
                    x = 0
                elsif x > 1
                    x = 1
                endif

                scaledIndex = x * numPoints
                lowerIndex = floor(scaledIndex) + 1
                if lowerIndex < 1
                    lowerIndex = 1
                elsif lowerIndex > numPoints
                    lowerIndex = numPoints
                endif

                frac = scaledIndex - floor(scaledIndex)
                tempo1 = vizFactors#[lowerIndex]
                tempo2 = vizFactors#[lowerIndex + 1]
                localTempo = tempo1 + frac * (tempo2 - tempo1)

                newPitch = pointPitch * localTempo

                if newPitch < synthFloor
                    newPitch = synthFloor
                    limitedPitchPoints += 1
                elsif newPitch > synthCeil
                    newPitch = synthCeil
                    limitedPitchPoints += 1
                endif

                selectObject: shiftedPitchTier
                Add point: pointTime, newPitch
            endfor

            if limitedPitchPoints > 0
                appendInfoLine: "Pitch safety limits applied: ", limitedPitchPoints, " point(s)"
            endif
        else
            appendInfoLine: "No voiced pitch detected: applying duration curve only."
        endif
    endif

    ##############################################################################
    # STEP 4: Resynthesize each original channel
    ##############################################################################

    if pitchBehavior = 1
        modeStr$ = "Pitch + Duration"
        if pitchAvailable = 0
            modeStr$ = "Duration Only (no voiced pitch)"
        endif
    else
        modeStr$ = "Duration Only"
    endif

    appendInfoLine: "Processing mode: ", modeStr$
    appendInfoLine: "Resynthesizing ", numberOfChannels, " channel(s)..."

    # Pitch analysis range is needed by Manipulation even for duration-only mode.
    pitchFloor = 40
    pitchCeil = min(1200, 0.45 * samplingFrequency)
    if pitchCeil <= pitchFloor
        exitScript: "Error: Sampling frequency is too low for safe Manipulation."
    endif

    channelResults# = zero#(numberOfChannels)

    for ch from 1 to numberOfChannels
        selectObject: sound
        if numberOfChannels = 1
            channelWork = Copy: "TPC_ch1"
        else
            channelWork = Extract one channel: ch
            Rename: "TPC_ch" + string$(ch)
        endif

        selectObject: channelWork
        manipulation = To Manipulation: 0.01, pitchFloor, pitchCeil

        selectObject: manipulation
        plusObject: durationTier
        Replace duration tier

        if pitchBehavior = 1 and pitchAvailable
            selectObject: manipulation
            plusObject: shiftedPitchTier
            Replace pitch tier
        endif

        selectObject: manipulation
        channelResult = Get resynthesis (overlap-add)
        Rename: "TPC_result_ch" + string$(ch)
        channelResults#[ch] = channelResult

        removeObject: manipulation, channelWork
    endfor

    # Preserve exact source channel count.
    if numberOfChannels = 1
        newSound = channelResults#[1]
    else
        selectObject: channelResults#[1]
        result_xmin = Get start time
        result_xmax = Get end time
        result_sr = Get sampling frequency

        Create Sound from formula: "TPC_result_build", numberOfChannels,
            ... result_xmin, result_xmax, result_sr, "0"
        newSound = selected("Sound")

        for ch from 1 to numberOfChannels
            selectObject: newSound
            Formula (part): result_xmin, result_xmax, ch, ch,
                ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
            removeObject: channelResults#[ch]
        endfor
    endif

    # Rename final object consistently with the original script.
    selectObject: newSound
    if patternType = 1
        if pitchBehavior = 1
            Rename: soundName$ + "_accel_pitched"
        else
            Rename: soundName$ + "_accel_PSOLA"
        endif
    elsif patternType = 2
        if pitchBehavior = 1
            Rename: soundName$ + "_ritard_pitched"
        else
            Rename: soundName$ + "_ritard_PSOLA"
        endif
    else
        if pitchBehavior = 1
            Rename: soundName$ + "_slowFastSlow_pitched"
        else
            Rename: soundName$ + "_slowFastSlow_PSOLA"
        endif
    endif

    # Final attenuation-only peak safety.
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0.99
        Scale peak: 0.99
        safetyApplied = 1
    endif
endif

##############################################################################
# STEP 5: VISUALIZATION
##############################################################################

if draw_visualization
    Erase all
    
    # --- 1. Title ---
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Tempo-Pitch Curves v0.4.1: " + soundName$ + " (" + patternName$ + ")"
    
    # --- 2. Original Waveform ---
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # --- 3. Result Waveform ---
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: newSound
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # --- 4. Tempo/Factor Curve ---
    Select outer viewport: 0, 8, 2.9, 4.4
    Select inner viewport: 0.6, 7.6, 3.1, 4.3
    
    # Determine bounds
    vizMin = 0.3
    vizMax = 3.0
    
    Axes: 0, originalDuration, vizMin, vizMax
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, originalDuration, vizMin, vizMax
    
    # Reference Line (1.0 = No change)
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 1.0, originalDuration, 1.0
    Solid line
    
    # Draw Tempo Curve
    Colour: "{0.5, 0.4, 0.7}"
    Line width: 2
    
    for i from 2 to numPoints + 1
        t1 = vizTimes#[i-1]
        v1 = vizFactors#[i-1]
        t2 = vizTimes#[i]
        v2 = vizFactors#[i]
        Draw line: t1, v1, t2, v2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Tempo Factor"
    Text right: "yes", "( >1 Fast, <1 Slow )"
    Text bottom: "yes", "Input Time (s)"
    
    # --- 5. Stats ---
    Select outer viewport: 0, 8, 4.5, 5.0
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    modeStr$ = "Duration Only"
    if pitchBehavior = 1
        modeStr$ = "Pitch + Duration"
    endif
    
    Text: 0.5, "centre", 0.5, "half", "Pattern: " + patternName$ + " | Strength: " + string$(strength) + " | Mode: " + modeStr$
    
    Font size: 10
    Colour: "Black"

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
    Text: 0.02, "left", 0.45, "half", "Tempo curve • linked pitch trajectory • rendered output"
    Text: 0.02, "left", 0.20, "half", "Tempo-Pitch Curves • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 5.78
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

##############################################################################
# STEP 6: Clean up and finalize
##############################################################################

if identity_mode = 0
    if durationTier <> 0
        removeObject: durationTier
    endif
    if shiftedPitchTier <> 0
        removeObject: shiftedPitchTier
    endif
    if originalPitchTier <> 0
        removeObject: originalPitchTier
    endif
    if analysisManip <> 0
        removeObject: analysisManip
    endif
    if analysisMono <> 0
        removeObject: analysisMono
    endif
endif

selectObject: newSound

# Play if requested
if play_result_when_finished
    Play
endif

finalActualDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=============================="
appendInfoLine: "Tempo curve applied successfully!"
appendInfoLine: "=============================="
appendInfoLine: "Original duration: ", fixed$(originalDuration, 3), " s"
appendInfoLine: "Result duration: ", fixed$(finalActualDuration, 3), " s"
if durationMode = 2
    appendInfoLine: "Requested duration: ", fixed$(targetDuration, 3), " s"
endif
appendInfoLine: "Channels preserved: ", numberOfChannels
appendInfoLine: "Peak safety applied: ", safetyApplied
appendInfoLine: ""
appendInfoLine: "Output: ", selected$("Sound")

selectObject: newSound
