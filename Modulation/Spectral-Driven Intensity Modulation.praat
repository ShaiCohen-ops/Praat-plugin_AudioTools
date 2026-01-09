# ============================================================
# Praat AudioTools - Spectral_Driven_Intensity_Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral-Driven Intensity Modulation - analyzes spectral
#   features (flatness and roughness) across the sound and uses
#   them to drive amplitude modulation. Noisy content gets deeper
#   tremolo, complex content gets faster tremolo. Tonal/smooth
#   content is protected with reduced modulation.
#
# Changelog v0.2:
#   - Added input check
#   - Added form with parameters
#   - Added presets
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
form Spectral-Driven Intensity Modulation
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Texture
        option Moderate Dynamics
        option Strong Spectral Response
        option Voice Protection Mode
        option Maximum Effect
    
    comment === Analysis ===
    natural Num_analysis_points 8
    positive Window_size_seconds 0.2
    positive Min_frequency_Hz 80
    positive Max_frequency_Hz 5000
    
    comment === Modulation Mapping ===
    positive Base_intensity_depth 20
    positive Max_intensity_depth 50
    positive Base_mod_speed 1.0
    positive Max_mod_speed 5.0
    
    comment === Protection (tonal content) ===
    positive Tonal_flatness_threshold 0.3
    positive Smooth_roughness_threshold 0.02
    real Tonal_depth_reduction 0.3
    real Tonal_speed_reduction 0.7
    
    comment === Output ===
    positive Time_step 0.01
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Texture
    base_intensity_depth = 15
    max_intensity_depth = 35
    base_mod_speed = 0.8
    max_mod_speed = 3.0
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate Dynamics
    base_intensity_depth = 20
    max_intensity_depth = 45
    base_mod_speed = 1.0
    max_mod_speed = 4.0
    presetName$ = "Moderate"
elsif preset = 4
    # Strong Spectral Response
    base_intensity_depth = 25
    max_intensity_depth = 55
    base_mod_speed = 1.5
    max_mod_speed = 6.0
    presetName$ = "Strong"
elsif preset = 5
    # Voice Protection Mode
    base_intensity_depth = 20
    max_intensity_depth = 40
    tonal_flatness_threshold = 0.4
    smooth_roughness_threshold = 0.03
    tonal_depth_reduction = 0.2
    tonal_speed_reduction = 0.5
    presetName$ = "VoicePro"
elsif preset = 6
    # Maximum Effect
    base_intensity_depth = 30
    max_intensity_depth = 60
    base_mod_speed = 2.0
    max_mod_speed = 8.0
    tonal_depth_reduction = 0.6
    presetName$ = "Maximum"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral-Driven Intensity Modulation ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis: ", num_analysis_points, " windows of ", window_size_seconds * 1000, " ms"
appendInfoLine: "Frequency range: ", min_frequency_Hz, " - ", max_frequency_Hz, " Hz"
appendInfoLine: ""
appendInfoLine: "Intensity depth: ", base_intensity_depth, " - ", max_intensity_depth, " dB"
appendInfoLine: "Modulation speed: ", base_mod_speed, " - ", max_mod_speed, " Hz"
appendInfoLine: ""

# === Analysis Phase ===
appendInfoLine: "Analyzing spectral features..."

analysisTimes# = zero#(num_analysis_points)
flatness# = zero#(num_analysis_points)
roughness# = zero#(num_analysis_points)

halfWindow = window_size_seconds / 2

for point from 1 to num_analysis_points
    # Calculate analysis time
    analysisTimes#[point] = (point - 1) * duration / (num_analysis_points - 1)
    
    # Clamp to valid range
    if analysisTimes#[point] < halfWindow
        analysisTimes#[point] = halfWindow
    endif
    if analysisTimes#[point] > duration - halfWindow
        analysisTimes#[point] = duration - halfWindow
    endif
    
    beginTime = analysisTimes#[point] - halfWindow
    endTime = analysisTimes#[point] + halfWindow
    
    if beginTime < 0
        beginTime = 0
    endif
    if endTime > duration
        endTime = duration
    endif
    
    # Extract window
    selectObject: original
    windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"
    
    # Get spectrum
    selectObject: windowSound
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    
    # Calculate spectral features
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
        
        if freq >= min_frequency_Hz and freq <= max_frequency_Hz
            re = Get real value in bin: bin
            im = Get imaginary value in bin: bin
            power = re*re + im*im
            power = max(power, 1e-12)
            
            lnSum = lnSum + ln(power)
            linearSum = linearSum + power
            
            # Roughness: deviation from neighbors
            if bin > 1 and bin < nBins
                rePrev = Get real value in bin: bin-1
                imPrev = Get imaginary value in bin: bin-1
                powerPrev = rePrev*rePrev + imPrev*imPrev
                
                reNext = Get real value in bin: bin+1
                imNext = Get imaginary value in bin: bin+1
                powerNext = reNext*reNext + imNext*imNext
                
                roughnessSum = roughnessSum + abs(power - (powerPrev + powerNext)/2)
                roughnessBins = roughnessBins + 1
            endif
            
            validBins = validBins + 1
        endif
    endfor
    
    # Calculate final values
    if validBins > 0 and roughnessBins > 0
        flatness#[point] = exp(lnSum / validBins) / (linearSum / validBins)
        roughness#[point] = roughnessSum / roughnessBins
    else
        flatness#[point] = 0.5
        roughness#[point] = 0.02
    endif
    
    appendInfoLine: "  Window ", point, " (", fixed$(analysisTimes#[point], 2), "s): flatness=", fixed$(flatness#[point], 3), " roughness=", fixed$(roughness#[point], 4)
    
    # Cleanup
    removeObject: windowSound, spectrum
endfor

# === Create Intensity Modulation ===
appendInfoLine: ""
appendInfoLine: "Creating intensity modulation..."

selectObject: original
workingSound = Copy: "working_" + originalName$

Create IntensityTier: "spectral_intensity", 0, duration
intensityTier = selected("IntensityTier")

numGridPoints = round(duration / time_step) + 1
currentPhase = 0
previousTime = 0

# Store for visualization
maxVizPoints = min(numGridPoints, 500)
vizTimes# = zero#(maxVizPoints)
vizIntensity# = zero#(maxVizPoints)
vizFlatness# = zero#(maxVizPoints)
vizSpeed# = zero#(maxVizPoints)

for i from 1 to numGridPoints
    currentTime = (i - 1) * time_step
    
    # Find which segment we're in (without goto)
    segment = num_analysis_points - 1
    for p from 1 to num_analysis_points - 1
        if currentTime >= analysisTimes#[p] and currentTime <= analysisTimes#[p + 1]
            segment = p
            p = num_analysis_points  ; exit loop
        endif
    endfor
    
    if currentTime < analysisTimes#[1]
        segment = 1
    endif
    
    # Interpolate spectral features
    segmentStart = analysisTimes#[segment]
    segmentEnd = analysisTimes#[segment + 1]
    
    if segmentStart = segmentEnd
        progress = 0
    else
        progress = (currentTime - segmentStart) / (segmentEnd - segmentStart)
    endif
    
    currentFlatness = flatness#[segment] + progress * (flatness#[segment + 1] - flatness#[segment])
    currentRoughness = roughness#[segment] + progress * (roughness#[segment + 1] - roughness#[segment])
    
    # Map to modulation parameters
    intensityDepth = base_intensity_depth + (currentFlatness * (max_intensity_depth - base_intensity_depth))
    modulationSpeed = base_mod_speed + (currentRoughness * (max_mod_speed - base_mod_speed) * 100)
    
    # Limit speed
    if modulationSpeed > max_mod_speed
        modulationSpeed = max_mod_speed
    endif
    
    # Protect tonal content
    if currentFlatness < tonal_flatness_threshold and currentRoughness < smooth_roughness_threshold
        intensityDepth = intensityDepth * tonal_depth_reduction
        modulationSpeed = modulationSpeed * tonal_speed_reduction
    endif
    
    # Update phase
    if i > 1
        timeDelta = currentTime - previousTime
        phaseDelta = 2 * pi * modulationSpeed * timeDelta
        currentPhase = currentPhase + phaseDelta
    else
        currentPhase = 0
    endif
    
    # Calculate intensity
    intensityVariation = intensityDepth * sin(currentPhase)
    currentIntensity = 70 + intensityVariation
    
    # Clamp
    if currentIntensity < 40
        currentIntensity = 40
    elsif currentIntensity > 100
        currentIntensity = 100
    endif
    
    # Add point
    selectObject: intensityTier
    Add point: currentTime, currentIntensity
    
    previousTime = currentTime
    
    # Store for visualization
    vizIdx = floor((i - 1) / numGridPoints * maxVizPoints) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        vizTimes#[vizIdx] = currentTime
        vizIntensity#[vizIdx] = currentIntensity
        vizFlatness#[vizIdx] = currentFlatness
        vizSpeed#[vizIdx] = modulationSpeed
    endif
endfor

# === Apply Modulation ===
appendInfoLine: "Applying intensity modulation..."

selectObject: workingSound, intensityTier
result = Multiply: "yes"
Rename: originalName$ + "_spectralMod_" + presetName$

# Cleanup
removeObject: workingSound, intensityTier

# Scale
selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral-Driven Intensity: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Modulated"
    Text bottom: "yes", "Time (s)"
    
    # Spectral flatness
    Select outer viewport: 0, 4, 2.5, 3.5
    Select inner viewport: 0.6, 3.8, 2.6, 3.4
    
    Axes: 0, duration, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 1
    
    # Tonal threshold line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, tonal_flatness_threshold, duration, tonal_flatness_threshold
    Solid line
    
    # Draw flatness curve
    Colour: "{0.7, 0.5, 0.5}"
    Line width: 1.5
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] > 0
            Draw line: vizTimes#[v - 1], vizFlatness#[v - 1], vizTimes#[v], vizFlatness#[v]
        endif
    endfor
    Line width: 1
    
    # Analysis points
    Colour: "{0.5, 0.3, 0.3}"
    for p from 1 to num_analysis_points
        Paint circle: "{0.7, 0.5, 0.5}", analysisTimes#[p], flatness#[p], 0.03
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Flatness"
    Text bottom: "yes", "Time"
    
    # Modulation speed
    Select outer viewport: 4, 8, 2.5, 3.5
    Select inner viewport: 4.4, 7.6, 2.6, 3.4
    
    Axes: 0, duration, 0, max_mod_speed * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, max_mod_speed * 1.2
    
    # Draw speed curve
    Colour: "{0.5, 0.5, 0.7}"
    Line width: 1.5
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] > 0
            Draw line: vizTimes#[v - 1], vizSpeed#[v - 1], vizTimes#[v], vizSpeed#[v]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Speed (Hz)"
    Text bottom: "yes", "Time"
    
    # Intensity modulation curve
    Select outer viewport: 0, 8, 3.7, 4.7
    Select inner viewport: 0.6, 7.6, 3.8, 4.6
    
    Axes: 0, duration, 40, 100
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 40, 100
    
    # Center line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 70, duration, 70
    Solid line
    
    # Draw intensity curve
    Colour: "{0.5, 0.7, 0.5}"
    Line width: 1.5
    for v from 2 to maxVizPoints
        if vizTimes#[v] > 0 and vizTimes#[v - 1] > 0
            Draw line: vizTimes#[v - 1], vizIntensity#[v - 1], vizTimes#[v], vizIntensity#[v]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Intensity"
    Text bottom: "yes", "Time (s)"
    
    # Mapping explanation
    Select outer viewport: 0, 8, 4.9, 5.5
    Select inner viewport: 0.6, 7.6, 5.0, 5.4
    
    Axes: 0, 8, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 8, 0, 2
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 2, "centre", 1.5, "half", "Flatness -> Depth"
    Text: 2, "centre", 0.5, "half", "(noisy = deeper)"
    Text: 6, "centre", 1.5, "half", "Roughness -> Speed"
    Text: 6, "centre", 0.5, "half", "(complex = faster)"
    
    # Arrow from flatness to depth
    Colour: "{0.7, 0.5, 0.5}"
    Draw arrow: 0.8, 1, 1.2, 1
    Draw arrow: 2.8, 1, 3.2, 1
    
    # Arrow from roughness to speed
    Colour: "{0.5, 0.5, 0.7}"
    Draw arrow: 4.8, 1, 5.2, 1
    Draw arrow: 6.8, 1, 7.2, 1
    
    Colour: "Black"
    Draw inner box
    
    # Stats
    Select outer viewport: 0, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    # Calculate average flatness and roughness
    avgFlat = 0
    avgRough = 0
    for p from 1 to num_analysis_points
        avgFlat = avgFlat + flatness#[p]
        avgRough = avgRough + roughness#[p]
    endfor
    avgFlat = avgFlat / num_analysis_points
    avgRough = avgRough / num_analysis_points
    
    Text: 0.5, "centre", 0.5, "half", "Avg flatness: " + fixed$(avgFlat, 3) + " | Avg roughness: " + fixed$(avgRough, 4) + " | Depth: " + fixed$(base_intensity_depth, 0) + "-" + fixed$(max_intensity_depth, 0) + " dB | Speed: " + fixed$(base_mod_speed, 1) + "-" + fixed$(max_mod_speed, 1) + " Hz"
    
    Font size: 10
    Colour: "Black"
endif

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