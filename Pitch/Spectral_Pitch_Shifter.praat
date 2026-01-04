# ============================================================
# Praat AudioTools - Spectral_Pitch_Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Pitch Shifter - analyzes spectral flatness and
#   roughness to drive pitch modulation. Noisy/harsh sections
#   get deeper, faster pitch modulation. Creates adaptive,
#   content-aware pitch effects.
#
# Changelog v0.2:
#   - Added form with parameters
#   - Modern syntax
#   - Removed goto
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency

# === Form ===
form Spectral Pitch Shifter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Response
        option Moderate Response
        option Strong Response
        option Extreme Response
    
    comment === Analysis ===
    natural Num_analysis_points 8
    positive Min_frequency 80
    positive Max_frequency 5000
    
    comment === Pitch Modulation ===
    positive Base_shift_depth 2
    positive Flatness_multiplier 6
    positive Base_mod_speed 0.5
    positive Roughness_multiplier 3.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle
    base_shift_depth = 1
    flatness_multiplier = 3
    base_mod_speed = 0.3
    roughness_multiplier = 1.5
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate
    base_shift_depth = 2
    flatness_multiplier = 6
    base_mod_speed = 0.5
    roughness_multiplier = 3.0
    presetName$ = "Moderate"
elsif preset = 4
    # Strong
    base_shift_depth = 4
    flatness_multiplier = 10
    base_mod_speed = 1.0
    roughness_multiplier = 5.0
    presetName$ = "Strong"
elsif preset = 5
    # Extreme
    base_shift_depth = 6
    flatness_multiplier = 15
    base_mod_speed = 1.5
    roughness_multiplier = 8.0
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral Pitch Shifter ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis points: ", num_analysis_points
appendInfoLine: "Frequency range: ", min_frequency, "-", max_frequency, " Hz"
appendInfoLine: "Shift depth: ", base_shift_depth, " + flatness×", flatness_multiplier
appendInfoLine: "Mod speed: ", base_mod_speed, " + roughness×", roughness_multiplier
appendInfoLine: ""

# === Analyze Spectral Features ===
analysisTimes# = zero#(num_analysis_points)
flatness# = zero#(num_analysis_points)
roughness# = zero#(num_analysis_points)

appendInfoLine: "Analyzing ", num_analysis_points, " time windows..."

for point from 1 to num_analysis_points
    analysisTimes#[point] = (point - 1) * duration / (num_analysis_points - 1)
    
    # Clamp to valid range
    if analysisTimes#[point] < 0.1
        analysisTimes#[point] = 0.1
    endif
    if analysisTimes#[point] > duration - 0.2
        analysisTimes#[point] = duration - 0.2
    endif
    
    beginTime = analysisTimes#[point] - 0.1
    endTime = analysisTimes#[point] + 0.1
    
    if beginTime < 0
        beginTime = 0
    endif
    if endTime > duration
        endTime = duration
    endif
    
    # Extract window
    selectObject: original
    windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"
    
    selectObject: windowSound
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    
    # Calculate flatness and roughness
    lnSum = 0
    linearSum = 0
    validBins = 0
    roughnessSum = 0
    roughnessBins = 0
    
    selectObject: spectrum
    nBins = Get number of bins
    binWidth = Get bin width
    
    for bin from 1 to nBins
        freq = (bin - 1) * binWidth
        if freq >= min_frequency and freq <= max_frequency
            amp = Get real value in bin: bin
            power = amp * amp
            power = max(power, 1e-12)
            lnSum = lnSum + ln(power)
            linearSum = linearSum + power
            
            if bin > 1 and bin < nBins
                ampPrev = Get real value in bin: bin - 1
                ampNext = Get real value in bin: bin + 1
                roughnessSum = roughnessSum + abs(amp - (ampPrev + ampNext) / 2)
                roughnessBins = roughnessBins + 1
            endif
            
            validBins = validBins + 1
        endif
    endfor
    
    if validBins > 0 and roughnessBins > 0
        flatness#[point] = exp(lnSum / validBins) / (linearSum / validBins)
        roughness#[point] = roughnessSum / roughnessBins
    else
        flatness#[point] = 0.2
        roughness#[point] = 0.02
    endif
    
    appendInfoLine: "  Window ", point, " (", fixed$(analysisTimes#[point], 2), "s): ",
        ... "flat=", fixed$(flatness#[point], 3), " rough=", fixed$(roughness#[point], 3)
    
    removeObject: windowSound, spectrum
endfor

# === Create Manipulation ===
appendInfoLine: ""
appendInfoLine: "Creating pitch modulation..."

selectObject: original
workingSound = Copy: "working_" + originalName$

selectObject: workingSound
manipulation = To Manipulation: 0.01, 75, 600

selectObject: manipulation
originalPitchTier = Extract pitch tier

# Create fresh pitch tier
shiftedPitchTier = Create PitchTier: "spectral_shifted_pitch", 0, duration

timeStep = 0.01
numGridPoints = round(duration / timeStep) + 1

# Store for visualization
maxVizPoints = min(numGridPoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizDepths# = zero#(maxVizPoints)
vizSpeeds# = zero#(maxVizPoints)
vizStep = numGridPoints / maxVizPoints

currentPhase = 0
previousTime = 0

for i from 1 to numGridPoints
    currentTime = (i - 1) * timeStep
    
    # Find segment (without goto)
    segment = num_analysis_points - 1
    for p from 1 to num_analysis_points - 1
        if currentTime >= analysisTimes#[p] and currentTime <= analysisTimes#[p + 1]
            segment = p
            p = num_analysis_points
        endif
    endfor
    
    if currentTime < analysisTimes#[1]
        segment = 1
    endif
    
    # Interpolate spectral features
    segmentStart = analysisTimes#[segment]
    segmentEnd = analysisTimes#[segment + 1]
    
    if segmentEnd > segmentStart
        progress = (currentTime - segmentStart) / (segmentEnd - segmentStart)
    else
        progress = 0
    endif
    
    currentFlatness = flatness#[segment] + progress * (flatness#[segment + 1] - flatness#[segment])
    currentRoughness = roughness#[segment] + progress * (roughness#[segment + 1] - roughness#[segment])
    
    # Calculate modulation parameters from spectral features
    shiftDepth = base_shift_depth + (currentFlatness * flatness_multiplier)
    modulationSpeed = base_mod_speed + (currentRoughness * roughness_multiplier)
    
    # Get original pitch
    selectObject: originalPitchTier
    originalFreq = Get value at time: currentTime
    
    if originalFreq > 0
        # Update phase
        if i > 1
            timeDelta = currentTime - previousTime
            phaseDelta = 2 * pi * modulationSpeed * timeDelta
            currentPhase = currentPhase + phaseDelta
        else
            currentPhase = 0
        endif
        
        # Calculate pitch shift
        semitoneShift = shiftDepth * sin(currentPhase)
        freqMultiplier = 2 ^ (semitoneShift / 12)
        newFreq = originalFreq * freqMultiplier
        
        selectObject: shiftedPitchTier
        Add point: currentTime, newFreq
        
        # Store for visualization
        vizIdx = floor(i / vizStep) + 1
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizTimes#[vizIdx] = 0
                vizTimes#[vizIdx] = currentTime
                vizShifts#[vizIdx] = semitoneShift
                vizDepths#[vizIdx] = shiftDepth
                vizSpeeds#[vizIdx] = modulationSpeed
            endif
        endif
        
        previousTime = currentTime
    endif
endfor

# === Resynthesize ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

selectObject: manipulation, shiftedPitchTier
Replace pitch tier

selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_spectral_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Pitch Shifter: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Spectral"
    Text bottom: "yes", "Time (s)"
    
    # Pitch shift curve
    Select outer viewport: 0, 8, 2.5, 3.5
    Select inner viewport: 0.6, 7.6, 2.6, 3.4
    
    # Find range
    minS = vizShifts#[1]
    maxS = vizShifts#[1]
    for vp from 2 to maxVizPoints
        if vizShifts#[vp] < minS
            minS = vizShifts#[vp]
        endif
        if vizShifts#[vp] > maxS
            maxS = vizShifts#[vp]
        endif
    endfor
    
    sMargin = max((maxS - minS) * 0.1, 2)
    
    Axes: 0, duration, minS - sMargin, maxS + sMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minS - sMargin, maxS + sMargin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    
    # Draw shift curve
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shift (st)"
    
    # Spectral features
    Select outer viewport: 0, 4, 3.7, 4.7
    Select inner viewport: 0.6, 3.8, 3.8, 4.6
    
    # Flatness
    maxFlat = flatness#[1]
    for p from 2 to num_analysis_points
        if flatness#[p] > maxFlat
            maxFlat = flatness#[p]
        endif
    endfor
    
    Axes: 0, duration, 0, maxFlat * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, maxFlat * 1.2
    
    Colour: "{0.7, 0.5, 0.5}"
    for p from 2 to num_analysis_points
        Draw line: analysisTimes#[p - 1], flatness#[p - 1], analysisTimes#[p], flatness#[p]
    endfor
    
    # Mark analysis points
    for p from 1 to num_analysis_points
        Paint circle (mm): "{0.7, 0.5, 0.5}", analysisTimes#[p], flatness#[p], 1.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Flatness"
    Text bottom: "yes", "Time (s)"
    
    # Roughness
    Select outer viewport: 4, 8, 3.7, 4.7
    Select inner viewport: 4.4, 7.6, 3.8, 4.6
    
    maxRough = roughness#[1]
    for p from 2 to num_analysis_points
        if roughness#[p] > maxRough
            maxRough = roughness#[p]
        endif
    endfor
    
    Axes: 0, duration, 0, maxRough * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, maxRough * 1.2
    
    Colour: "{0.5, 0.7, 0.5}"
    for p from 2 to num_analysis_points
        Draw line: analysisTimes#[p - 1], roughness#[p - 1], analysisTimes#[p], roughness#[p]
    endfor
    
    for p from 1 to num_analysis_points
        Paint circle (mm): "{0.5, 0.7, 0.5}", analysisTimes#[p], roughness#[p], 1.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Roughness"
    Text bottom: "yes", "Time (s)"
    
    # Parameter mapping legend
    Select outer viewport: 0, 8, 4.9, 5.3
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.5, "centre", 0.5, "half", "Flatness → Shift Depth | Roughness → Modulation Speed"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: workingSound, manipulation, originalPitchTier, shiftedPitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result