# ============================================================
# Praat AudioTools - SpectralPanningMapper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed and enhanced
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral-driven dynamic panning. Analyzes spectral flatness
#   (Wiener entropy) and roughness to control stereo movement:
#   - Flatness -> panning width (noise = wider)
#   - Roughness -> motion speed (variation = faster)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - FIXED: Right channel extraction (was extracting ch1 twice!)
#   - FIXED: IntensityTier dB values
#   - Removed goto statement
#   - Added presets
#   - Added visualization
#   - Added wet/dry mix
#   - Added play/visualization toggles
#   - Edge case handling for short files
#   - Final output scaling
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
duration = Get total duration
sr = Get sampling frequency
nCh = Get number of channels

# Check minimum duration
if duration < 0.3
    exitScript: "Sound must be at least 0.3 seconds long."
endif

form Spectral Panning Mapper v0.2
    comment ==== Presets ====
    optionmenu Preset: 1
        option Custom
        option Subtle Drift (gentle response)
        option Standard Response (balanced)
        option Hyperactive (strong response)
        option Noise Tracker (flatness focused)
        option Transient Chaser (roughness focused)
        option Slow Evolution (gradual movement)
    comment ==== Analysis Settings ====
    positive Analysis_windows 8
    positive Panning_update_rate_Hz 100
    comment ==== Spectral Mapping ====
    positive Base_panning_depth 0.3
    positive Flatness_influence 0.7
    positive Base_motion_speed_Hz 0.5
    positive Roughness_influence 3.0
    comment ==== Output (Mix: 0=dry 100=wet) ====
    real Mix_percent 100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 2
    # Subtle Drift
    analysis_windows = 6
    panning_update_rate_Hz = 50
    base_panning_depth = 0.15
    flatness_influence = 0.3
    base_motion_speed_Hz = 0.2
    roughness_influence = 1.0
    presetName$ = "SubtleDrift"
elsif preset = 3
    # Standard Response
    analysis_windows = 8
    panning_update_rate_Hz = 100
    base_panning_depth = 0.3
    flatness_influence = 0.7
    base_motion_speed_Hz = 0.5
    roughness_influence = 3.0
    presetName$ = "StandardResponse"
elsif preset = 4
    # Hyperactive
    analysis_windows = 16
    panning_update_rate_Hz = 200
    base_panning_depth = 0.5
    flatness_influence = 1.0
    base_motion_speed_Hz = 1.0
    roughness_influence = 8.0
    presetName$ = "Hyperactive"
elsif preset = 5
    # Noise Tracker
    analysis_windows = 12
    panning_update_rate_Hz = 100
    base_panning_depth = 0.1
    flatness_influence = 1.5
    base_motion_speed_Hz = 0.3
    roughness_influence = 1.0
    presetName$ = "NoiseTracker"
elsif preset = 6
    # Transient Chaser
    analysis_windows = 20
    panning_update_rate_Hz = 150
    base_panning_depth = 0.4
    flatness_influence = 0.2
    base_motion_speed_Hz = 0.2
    roughness_influence = 10.0
    presetName$ = "TransientChaser"
elsif preset = 7
    # Slow Evolution
    analysis_windows = 4
    panning_update_rate_Hz = 50
    base_panning_depth = 0.4
    flatness_influence = 0.5
    base_motion_speed_Hz = 0.1
    roughness_influence = 0.5
    presetName$ = "SlowEvolution"
else
    presetName$ = "Custom"
endif

# Clamp mix
if mix_percent < 0
    mix_percent = 0
elsif mix_percent > 100
    mix_percent = 100
endif
wetLevel = mix_percent / 100
dryLevel = 1 - wetLevel

writeInfoLine: "=== Spectral Panning Mapper v0.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Analysis windows: ", analysis_windows
appendInfoLine: ""

# ============================================================
# PREPARE SOURCE
# ============================================================

selectObject: original
if nCh = 1
    appendInfoLine: "Mono input - converting to stereo"
    monoSource = Copy: "temp_mono"
    stereoSource = Convert to stereo
    selectObject: monoSource
    Remove
else
    appendInfoLine: "Stereo input - extracting channels"
    stereoSource = Copy: "temp_stereo"
endif

# Extract channels (FIXED: was extracting ch1 twice!)
selectObject: stereoSource
leftChannel = Extract one channel: 1
selectObject: stereoSource
rightChannel = Extract one channel: 2

# ============================================================
# SPECTRAL ANALYSIS
# ============================================================

numAnalysisPoints = analysis_windows
analysisTimes# = zero#(numAnalysisPoints)
flatness# = zero#(numAnalysisPoints)
roughness# = zero#(numAnalysisPoints)

appendInfoLine: "Analyzing ", numAnalysisPoints, " time windows..."

# Analysis window size (adaptive to duration)
windowHalf = 0.1
if windowHalf * 2 > duration / numAnalysisPoints
    windowHalf = duration / (numAnalysisPoints * 2.5)
endif
if windowHalf < 0.02
    windowHalf = 0.02
endif

for point from 1 to numAnalysisPoints
    # Distribute analysis points evenly
    if numAnalysisPoints > 1
        analysisTimes#[point] = windowHalf + (point - 1) * (duration - 2 * windowHalf) / (numAnalysisPoints - 1)
    else
        analysisTimes#[point] = duration / 2
    endif
    
    # Extract analysis window
    beginTime = analysisTimes#[point] - windowHalf
    endTime = analysisTimes#[point] + windowHalf
    
    if beginTime < 0
        beginTime = 0
    endif
    if endTime > duration
        endTime = duration
    endif
    
    selectObject: original
    windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"
    
    # Convert to mono for analysis if stereo
    selectObject: windowSound
    windowCh = Get number of channels
    if windowCh > 1
        windowMono = Convert to mono
        selectObject: windowSound
        Remove
        windowSound = windowMono
    endif
    
    # Create spectrum
    selectObject: windowSound
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    
    # Analysis frequency range
    minFreq = 80
    maxFreq = 8000
    
    # Initialize accumulators
    lnSum = 0
    linearSum = 0
    validBins = 0
    roughnessSum = 0
    roughnessBins = 0
    prevAmp = 0
    
    selectObject: spectrum
    nBins = Get number of bins
    binWidth = Get bin width
    
    for bin from 1 to nBins
        freq = (bin - 1) * binWidth
        if freq >= minFreq and freq <= maxFreq
            realPart = Get real value in bin: bin
            imagPart = Get imaginary value in bin: bin
            amp = sqrt(realPart * realPart + imagPart * imagPart)
            
            power = amp * amp
            if power < 1e-12
                power = 1e-12
            endif
            
            lnSum = lnSum + ln(power)
            linearSum = linearSum + power
            
            # Roughness: spectral flux / variation
            if validBins > 0
                roughnessSum = roughnessSum + abs(amp - prevAmp)
                roughnessBins = roughnessBins + 1
            endif
            prevAmp = amp
            
            validBins = validBins + 1
        endif
    endfor
    
    # Calculate flatness (Wiener entropy) and roughness
    if validBins > 0
        geometricMean = exp(lnSum / validBins)
        arithmeticMean = linearSum / validBins
        if arithmeticMean > 0
            flatness#[point] = geometricMean / arithmeticMean
        else
            flatness#[point] = 0
        endif
    else
        flatness#[point] = 0.2
    endif
    
    if roughnessBins > 0
        roughness#[point] = roughnessSum / roughnessBins
        # Normalize roughness to 0-1 range approximately
        roughness#[point] = roughness#[point] * 10
        if roughness#[point] > 1
            roughness#[point] = 1
        endif
    else
        roughness#[point] = 0.1
    endif
    
    # Cleanup
    selectObject: windowSound
    plusObject: spectrum
    Remove
endfor

appendInfoLine: "Analysis complete"
appendInfoLine: ""

# ============================================================
# CREATE PANNING ENVELOPES
# ============================================================

appendInfoLine: "Creating panning envelopes..."

leftTier = Create IntensityTier: "left_pan", 0, duration
rightTier = Create IntensityTier: "right_pan", 0, duration

timeStep = 1 / panning_update_rate_Hz
numGridPoints = round(duration / timeStep) + 1

# Store pan values for visualization
panValues# = zero#(numGridPoints)
panTimes# = zero#(numGridPoints)

currentPhase = 0
previousTime = 0

for i from 1 to numGridPoints
    currentTime = (i - 1) * timeStep
    if currentTime > duration
        currentTime = duration
    endif
    
    panTimes#[i] = currentTime
    
    # Find which analysis segment we're in (without goto)
    segment = 1
    for p from 1 to numAnalysisPoints - 1
        if currentTime >= analysisTimes#[p] and currentTime < analysisTimes#[p + 1]
            segment = p
        endif
    endfor
    
    # Handle edge cases
    if currentTime < analysisTimes#[1]
        segment = 1
    elsif currentTime >= analysisTimes#[numAnalysisPoints]
        segment = numAnalysisPoints - 1
    endif
    
    # Ensure segment+1 is valid
    if segment >= numAnalysisPoints
        segment = numAnalysisPoints - 1
    endif
    
    # Interpolate spectral features
    segmentStart = analysisTimes#[segment]
    segmentEnd = analysisTimes#[segment + 1]
    
    if segmentEnd > segmentStart
        progress = (currentTime - segmentStart) / (segmentEnd - segmentStart)
        if progress < 0
            progress = 0
        elsif progress > 1
            progress = 1
        endif
    else
        progress = 0
    endif
    
    currentFlatness = flatness#[segment] + progress * (flatness#[segment + 1] - flatness#[segment])
    currentRoughness = roughness#[segment] + progress * (roughness#[segment + 1] - roughness#[segment])
    
    # Map spectral features to panning parameters
    panningDepth = base_panning_depth + (currentFlatness * flatness_influence)
    if panningDepth > 1
        panningDepth = 1
    endif
    
    motionSpeed = base_motion_speed_Hz + (currentRoughness * roughness_influence)
    
    # Update phase (continuous oscillator)
    if i > 1
        timeDelta = currentTime - previousTime
        phaseDelta = 2 * pi * motionSpeed * timeDelta
        currentPhase = currentPhase + phaseDelta
    endif
    
    # Calculate pan position (-1 to +1)
    panPosition = panningDepth * sin(currentPhase)
    panValues#[i] = panPosition
    
    # Convert to constant-power gains
    panNorm = (panPosition + 1) / 2
    leftGain = cos(panNorm * pi / 2)
    rightGain = sin(panNorm * pi / 2)
    
    # Convert to dB for IntensityTier (with floor)
    if leftGain < 0.001
        leftGain = 0.001
    endif
    if rightGain < 0.001
        rightGain = 0.001
    endif
    
    leftDb = 20 * log10(leftGain)
    rightDb = 20 * log10(rightGain)
    
    # Add to tiers
    selectObject: leftTier
    Add point: currentTime, leftDb
    
    selectObject: rightTier
    Add point: currentTime, rightDb
    
    previousTime = currentTime
endfor

appendInfoLine: "Created ", numGridPoints, " panning points"

# ============================================================
# APPLY PANNING
# ============================================================

appendInfoLine: "Applying spectral panning..."

selectObject: leftChannel
plusObject: leftTier
Multiply: "yes"
leftResult = selected("Sound")

selectObject: rightChannel
plusObject: rightTier
Multiply: "yes"
rightResult = selected("Sound")

# Combine to stereo
selectObject: leftResult
plusObject: rightResult
Combine to stereo
wetSound = selected("Sound")

# ============================================================
# WET/DRY MIX
# ============================================================

if dryLevel > 0
    # Prepare dry signal
    selectObject: original
    if nCh = 1
        drySound = Convert to stereo
    else
        drySound = Copy: "temp_dry"
    endif
    
    wetStr$ = string$(wetLevel)
    dryStr$ = string$(dryLevel)
    dryIdStr$ = string$(drySound)
    
    selectObject: wetSound
    Formula: "self * " + wetStr$ + " + Object_" + dryIdStr$ + "[row, col] * " + dryStr$
    
    selectObject: drySound
    Remove
endif

# Finalize
selectObject: wetSound
Rename: originalName$ + "_specpan_" + presetName$
result = selected("Sound")
Scale peak: 0.99

resultName$ = selected$("Sound")

# ============================================================
# CLEANUP
# ============================================================

selectObject: stereoSource
plusObject: leftChannel
plusObject: rightChannel
plusObject: leftResult
plusObject: rightResult
plusObject: leftTier
plusObject: rightTier
Remove

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Panning Mapper: " + presetName$
    
    # Original waveform
    Select outer viewport: 0, 7, 0.5, 1.5
    Select inner viewport: 0.6, 6.6, 0.6, 1.4
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 7, 1.5, 2.5
    Select inner viewport: 0.6, 6.6, 1.6, 2.4
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Result"
    
    # Spectral features plot
    Select outer viewport: 0, 7, 2.7, 3.9
    Select inner viewport: 0.6, 6.6, 2.85, 3.75
    
    Axes: 0, duration, 0, 1.2
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 1.2
    
    # Draw flatness
    Colour: "{0.8, 0.4, 0.2}"
    Line width: 2
    for p from 2 to numAnalysisPoints
        Draw line: analysisTimes#[p-1], flatness#[p-1], analysisTimes#[p], flatness#[p]
    endfor
    
    # Draw roughness
    Colour: "{0.2, 0.6, 0.4}"
    for p from 2 to numAnalysisPoints
        Draw line: analysisTimes#[p-1], roughness#[p-1], analysisTimes#[p], roughness#[p]
    endfor
    Line width: 1
    
    # Legend
    Font size: 6
    Colour: "{0.8, 0.4, 0.2}"
    Text: duration * 0.85, "left", 1.1, "half", "Flatness"
    Colour: "{0.2, 0.6, 0.4}"
    Text: duration * 0.85, "left", 1.0, "half", "Roughness"
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Features"
    Text top: "no", "Spectral Features"
    
    # Pan trajectory
    Select outer viewport: 0, 7, 4.1, 5.5
    Select inner viewport: 0.6, 6.6, 4.25, 5.35
    
    Axes: 0, duration, -1.2, 1.2
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -1.2, 1.2
    
    # Center line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, duration, 0
    
    # L/R labels
    Font size: 6
    Colour: "{0.6, 0.6, 0.6}"
    Text: duration * 0.01, "left", -1.0, "half", "L"
    Text: duration * 0.01, "left", 1.0, "half", "R"
    
    # Draw pan trajectory (subsample for speed)
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1.5
    step = round(numGridPoints / 500)
    if step < 1
        step = 1
    endif
    
    i = 1 + step
    while i <= numGridPoints
        prevIdx = i - step
        if prevIdx < 1
            prevIdx = 1
        endif
        Draw line: panTimes#[prevIdx], panValues#[prevIdx], panTimes#[i], panValues#[i]
        i = i + step
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Pan"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Spectral-Driven Pan Position"
    
    # Parameters
    Select outer viewport: 0, 7, 5.6, 6.0
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Windows: " + string$(analysis_windows) + " | Base depth: " + fixed$(base_panning_depth, 2) + " | Flatness infl: " + fixed$(flatness_influence, 1) + " | Base speed: " + fixed$(base_motion_speed_Hz, 1) + "Hz | Rough infl: " + fixed$(roughness_influence, 1)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original: ", originalName$
appendInfoLine: "Result: ", resultName$
appendInfoLine: "Mix: ", fixed$(mix_percent, 0), "%"
appendInfoLine: ""

if play_result
    selectObject: result
    Play
endif
