# ============================================================
# Praat AudioTools - Adaptive_Pitch_Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Pitch Shifter - applies pitch shifting modulated
#   by amplitude, pitch contour, LFO, or combined sources.
#   Creates effects from subtle vibrato to extreme warping.
#
# Changelog v0.2:
#   - Fixed input validation
#   - Fixed undefined variables
#   - Added visualization
#   - Modern syntax
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
originalName$ = selected$("Sound")

# === Form ===
form Adaptive Pitch Shifter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Wobble
        option Robot Voice
        option Harmonic Shimmer
        option Deep Bass Mod
        option Vibrato Effect
        option Extreme Warp
    
    comment === Basic Controls ===
    positive Base_pitch_shift 1.0
    positive Modulation_amount 0.5
    
    comment === Modulation Source ===
    optionmenu Modulation_source 1
        option Amplitude
        option Pitch Contour
        option Time-based LFO
        option Combined
    positive LFO_frequency 3.0
    positive Smoothing_factor 0.1
    
    comment === Processing ===
    boolean Apply_formant_preservation 1
    boolean Add_stereo_width 0
    positive Output_gain 1.0
    
    comment === Quality ===
    optionmenu Quality 2
        option Fast
        option Standard
        option High Quality
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Wobble
    base_pitch_shift = 1.0
    modulation_amount = 0.15
    modulation_source = 1
    lFO_frequency = 4.0
    smoothing_factor = 0.2
elsif preset = 3
    # Robot Voice
    base_pitch_shift = 0.8
    modulation_amount = 0.8
    modulation_source = 3
    lFO_frequency = 8.0
    smoothing_factor = 0.05
elsif preset = 4
    # Harmonic Shimmer
    base_pitch_shift = 1.5
    modulation_amount = 0.3
    modulation_source = 2
    lFO_frequency = 2.0
    smoothing_factor = 0.3
elsif preset = 5
    # Deep Bass Mod
    base_pitch_shift = 0.5
    modulation_amount = 1.0
    modulation_source = 4
    lFO_frequency = 1.5
    smoothing_factor = 0.15
elsif preset = 6
    # Vibrato Effect
    base_pitch_shift = 1.0
    modulation_amount = 0.08
    modulation_source = 3
    lFO_frequency = 5.5
    smoothing_factor = 0.4
elsif preset = 7
    # Extreme Warp
    base_pitch_shift = 1.2
    modulation_amount = 1.5
    modulation_source = 4
    lFO_frequency = 10.0
    smoothing_factor = 0.0
endif

# === Get Names ===
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Subtle Wobble"
elsif preset = 3
    presetName$ = "Robot Voice"
elsif preset = 4
    presetName$ = "Harmonic Shimmer"
elsif preset = 5
    presetName$ = "Deep Bass"
elsif preset = 6
    presetName$ = "Vibrato"
else
    presetName$ = "Extreme Warp"
endif

if modulation_source = 1
    modSourceName$ = "Amplitude"
elsif modulation_source = 2
    modSourceName$ = "Pitch Contour"
elsif modulation_source = 3
    modSourceName$ = "LFO"
else
    modSourceName$ = "Combined"
endif

# === Set Quality Parameters ===
if quality = 1
    timestep = 0.01
    pitchFloor = 75
    pitchCeiling = 600
elsif quality = 2
    timestep = 0.005
    pitchFloor = 75
    pitchCeiling = 600
else
    timestep = 0.001
    pitchFloor = 50
    pitchCeiling = 800
endif

# === Info ===
writeInfoLine: "=== Adaptive Pitch Shifter ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Modulation: ", modSourceName$
appendInfoLine: ""
appendInfoLine: "Base shift: ", base_pitch_shift
appendInfoLine: "Mod amount: ", modulation_amount
if modulation_source = 3 or modulation_source = 4
    appendInfoLine: "LFO freq: ", lFO_frequency, " Hz"
endif
appendInfoLine: ""

# === Extract Analysis Objects ===
if modulation_source = 2 or modulation_source = 4
    appendInfoLine: "Extracting pitch contour..."
    selectObject: sound
    pitch = To Pitch: timestep, pitchFloor, pitchCeiling
endif

if modulation_source = 1 or modulation_source = 4
    selectObject: sound
    appendInfoLine: "Extracting amplitude envelope..."
    intensity = To Intensity: pitchFloor, timestep, "yes"
    intensityTier = Down to IntensityTier
endif

# === Create Manipulation Object ===
selectObject: sound
appendInfoLine: "Creating manipulation object..."
manipulation = To Manipulation: timestep, pitchFloor, pitchCeiling

# === Extract Pitch Tier ===
selectObject: manipulation
pitchTier = Extract pitch tier
origPitchTier = Copy: "original_pitch"

selectObject: pitchTier
numPoints = Get number of points

appendInfoLine: "Modifying pitch at ", numPoints, " points..."

# === Store for Visualization ===
maxPoints = min(numPoints, 500)
originalFreqs# = zero#(maxPoints)
newFreqs# = zero#(maxPoints)
times# = zero#(maxPoints)

# === Modify Pitch Tier ===
for i from 1 to numPoints
    selectObject: pitchTier
    time = Get time from index: i
    originalFreq = Get value at index: i
    
    if originalFreq <> undefined
        modulation = 0
        
        # Calculate modulation based on source
        if modulation_source = 1
            # Amplitude-based
            selectObject: intensityTier
            amplitude = Get value at time: time
            if amplitude <> undefined
                normalizedAmp = (amplitude - 40) / 60
                normalizedAmp = max(0, min(1, normalizedAmp))
                modulation = normalizedAmp
            endif
            
        elsif modulation_source = 2
            # Pitch contour-based
            selectObject: pitch
            currentPitch = Get value at time: time, "Hertz", "Linear"
            if currentPitch <> undefined
                normalizedPitch = (currentPitch - pitchFloor) / (pitchCeiling - pitchFloor)
                modulation = normalizedPitch
            endif
            
        elsif modulation_source = 3
            # Time-based LFO
            modulation = (sin(2 * pi * lFO_frequency * time) + 1) / 2
            
        elsif modulation_source = 4
            # Combined (Amplitude + LFO)
            selectObject: intensityTier
            amplitude = Get value at time: time
            if amplitude <> undefined
                normalizedAmp = (amplitude - 40) / 60
                normalizedAmp = max(0, min(1, normalizedAmp))
                lfo = (sin(2 * pi * lFO_frequency * time) + 1) / 2
                modulation = (normalizedAmp + lfo) / 2
            endif
        endif
        
        # Apply smoothing
        if smoothing_factor > 0 and i > 1
            selectObject: pitchTier
            prevFreq = Get value at index: i - 1
            if prevFreq <> undefined
                modulation = modulation * (1 - smoothing_factor) + (prevFreq / originalFreq - 1) * smoothing_factor
            endif
        endif
        
        # Calculate new frequency
        pitchMultiplier = base_pitch_shift + (modulation * modulation_amount)
        newFreq = originalFreq * pitchMultiplier
        
        # Clamp to reasonable range
        newFreq = max(50, min(1000, newFreq))
        
        # Store for visualization
        if i <= maxPoints
            originalFreqs#[i] = originalFreq
            newFreqs#[i] = newFreq
            times#[i] = time
        endif
        
        # Update pitch tier
        selectObject: pitchTier
        Remove point: i
        Add point: time, newFreq
    endif
endfor

storedPoints = min(numPoints, maxPoints)

# === Apply Modified Pitch Tier ===
selectObject: manipulation, pitchTier
Replace pitch tier

# === Synthesize Output ===
selectObject: manipulation
appendInfoLine: "Synthesizing output..."
if apply_formant_preservation
    output = Get resynthesis (overlap-add)
else
    output = Get resynthesis (PSOLA)
endif

Rename: originalName$ + "_shifted_" + presetName$

# === Apply Output Gain ===
selectObject: output
Formula: ~ self * output_gain

# === Add Stereo Width ===
selectObject: output
numChannels = Get number of channels
if add_stereo_width and numChannels = 1
    appendInfoLine: "Adding stereo width..."
    stereoOutput = Convert to stereo
    selectObject: stereoOutput
    Formula: ~ if col = 1 then self * 1.1 else self * 0.9 fi
    removeObject: output
    output = stereoOutput
endif

# Scale peak
selectObject: output
Scale peak: 0.95

# === Cleanup ===
if modulation_source = 2 or modulation_source = 4
    removeObject: pitch
endif
if modulation_source = 1 or modulation_source = 4
    removeObject: intensity, intensityTier
endif
removeObject: manipulation, pitchTier, origPitchTier

# === Visualization ===
if draw_visualization and storedPoints > 0
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Adaptive Pitch Shifter: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: output
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Shifted"
    Text bottom: "yes", "Time (s)"
    
    # Pitch curves comparison
    Select outer viewport: 0, 8, 3.3, 5.0
    Select inner viewport: 0.6, 7.6, 3.5, 4.9
    
    # Find pitch range
    minFreq = originalFreqs#[1]
    maxFreq = originalFreqs#[1]
    for pt from 2 to storedPoints
        if originalFreqs#[pt] > 0
            if originalFreqs#[pt] < minFreq
                minFreq = originalFreqs#[pt]
            endif
            if originalFreqs#[pt] > maxFreq
                maxFreq = originalFreqs#[pt]
            endif
        endif
        if newFreqs#[pt] > 0
            if newFreqs#[pt] < minFreq
                minFreq = newFreqs#[pt]
            endif
            if newFreqs#[pt] > maxFreq
                maxFreq = newFreqs#[pt]
            endif
        endif
    endfor
    
    margin = (maxFreq - minFreq) * 0.1
    if margin < 20
        margin = 20
    endif
    
    Axes: 0, duration, minFreq - margin, maxFreq + margin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minFreq - margin, maxFreq + margin
    
    # Draw original pitch
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1
    for pt from 2 to storedPoints
        if originalFreqs#[pt] > 0 and originalFreqs#[pt - 1] > 0
            Draw line: times#[pt - 1], originalFreqs#[pt - 1], times#[pt], originalFreqs#[pt]
        endif
    endfor
    
    # Draw new pitch
    Colour: "{0.4, 0.6, 0.8}"
    Line width: 2
    for pt from 2 to storedPoints
        if newFreqs#[pt] > 0 and newFreqs#[pt - 1] > 0
            Draw line: times#[pt - 1], newFreqs#[pt - 1], times#[pt], newFreqs#[pt]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.6, 0.6, 0.6}"
    Text: 0.02, "left", 1.02, "half", "Original"
    Colour: "{0.4, 0.6, 0.8}"
    Text: 0.12, "left", 1.02, "half", "Shifted"
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base: " + fixed$(base_pitch_shift, 2) + "x | Mod: " + modSourceName$ + " (" + fixed$(modulation_amount, 2) + ") | Smoothing: " + fixed$(smoothing_factor, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: output

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: output
    Play
endif

selectObject: output