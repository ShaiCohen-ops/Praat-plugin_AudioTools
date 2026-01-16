# ============================================================
# Praat AudioTools - 8-Channel_Speech-Driven_Spatialization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Speech-Driven 8-Channel Spatialization
#   Maps pitch to azimuth angle and intensity to distance.
#   Uses constant-power panning for smooth movement.
#
# Changelog v0.2:
#   - Added form with presets
#   - Added input validation
#   - Added visualization
#   - Added play option
# ============================================================

form 8-Channel Speech-Driven Spatialization
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Full Range (pitch: 75-600 Hz)"
        option: "Voice Range (pitch: 100-300 Hz)"
        option: "Narrow Range (pitch: 150-250 Hz)"
        option: "Extended Range (pitch: 50-800 Hz)"
        option: "Inverted (high=back, low=front)"
    
    comment === Pitch mapping ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    real Low_pitch_angle 225
    real High_pitch_angle 45
    
    comment === Intensity mapping ===
    real Min_distance_gain 0.2
    real Max_distance_gain 1.0
    real Ambient_level 0.05
    
    comment === Analysis ===
    positive Time_step 0.01
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Full Range
    pitch_floor = 75
    pitch_ceiling = 600
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "FullRange"
elsif preset = 3
    # Voice Range
    pitch_floor = 100
    pitch_ceiling = 300
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "VoiceRange"
elsif preset = 4
    # Narrow Range
    pitch_floor = 150
    pitch_ceiling = 250
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "NarrowRange"
elsif preset = 5
    # Extended Range
    pitch_floor = 50
    pitch_ceiling = 800
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "ExtendedRange"
elsif preset = 6
    # Inverted
    pitch_floor = 75
    pitch_ceiling = 600
    low_pitch_angle = 45
    high_pitch_angle = 225
    presetName$ = "Inverted"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

writeInfoLine: "=== 8-Channel Speech-Driven Spatialization ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# Convert to mono if stereo
numberOfChannels = Get number of channels
if numberOfChannels > 1
    selectObject: sound
    monoSound = Convert to mono
else
    selectObject: sound
    monoSound = Copy: soundName$ + "_mono"
endif

# Extract features
appendInfoLine: "Extracting pitch..."
selectObject: monoSound
pitch = To Pitch: time_step, pitch_floor, pitch_ceiling

appendInfoLine: "Extracting intensity..."
selectObject: monoSound
intensity = To Intensity: 100, time_step, "yes"

# Get feature ranges for normalization
selectObject: pitch
pitchMean = Get mean: 0, 0, "Hertz"
pitchMin = Get minimum: 0, 0, "Hertz", "Parabolic"
pitchMax = Get maximum: 0, 0, "Hertz", "Parabolic"

selectObject: intensity
intensityMean = Get mean: 0, 0
intensityMin = Get minimum: 0, 0, "Parabolic"
intensityMax = Get maximum: 0, 0, "Parabolic"

appendInfoLine: "Pitch range: ", fixed$(pitchMin, 1), " - ", fixed$(pitchMax, 1), " Hz"
appendInfoLine: "Intensity range: ", fixed$(intensityMin, 1), " - ", fixed$(intensityMax, 1), " dB"

# Create 8 copies of the mono sound
appendInfoLine: ""
appendInfoLine: "Creating channel copies..."
speakerAngles# = { 315, 0, 45, 90, 135, 180, 225, 270 }

selectObject: monoSound
for ch from 1 to 8
    channel'ch' = Copy: "channel_" + string$(ch)
endfor

# Process in chunks to build gain envelopes
frameShift = time_step
numberOfFrames = floor(duration / frameShift)
chunkSize = min(1000, numberOfFrames)

appendInfoLine: "Processing ", numberOfFrames, " frames..."

# Create gain arrays
for ch from 1 to 8
    gain'ch'# = zero#(numberOfFrames)
endfor

# For visualization - store position history
if draw_visualization
    posHistory# = zero#(min(500, numberOfFrames))
    posHistoryY# = zero#(min(500, numberOfFrames))
    histStep = max(1, floor(numberOfFrames / 500))
endif

# Build time-varying gains
lastPitchValue = pitchMean
chunkStart = 1
histIdx = 0

while chunkStart <= numberOfFrames
    chunkEnd = min(chunkStart + chunkSize - 1, numberOfFrames)
    
    for frame from chunkStart to chunkEnd
        t = frame * frameShift
        
        # Get pitch at this time
        selectObject: pitch
        pitchValue = Get value at time: t, "Hertz", "linear"
        
        # Handle unvoiced frames
        if pitchValue = undefined
            pitchValue = lastPitchValue
        else
            lastPitchValue = pitchValue
        endif
        
        # Get intensity at this time
        selectObject: intensity
        intensityValue = Get value at time: t, "Linear"
        
        if intensityValue = undefined
            intensityValue = intensityMean
        endif
        
        # Normalize values and clamp to [0,1]
        if pitchMin < pitchMax
            pitchNorm = (pitchValue - pitchMin) / (pitchMax - pitchMin)
        else
            pitchNorm = 0.5
        endif
        pitchNorm = max(0, min(1, pitchNorm))
        
        if intensityMin < intensityMax
            intensityNorm = (intensityValue - intensityMin) / (intensityMax - intensityMin)
        else
            intensityNorm = 0.5
        endif
        intensityNorm = max(0, min(1, intensityNorm))
        
        # Map pitch to azimuth angle
        angleRange = high_pitch_angle - low_pitch_angle
        if angleRange < 0
            angleRange = angleRange + 360
        endif
        targetAngle = low_pitch_angle + pitchNorm * angleRange
        if targetAngle >= 360
            targetAngle = targetAngle - 360
        endif
        if targetAngle < 0
            targetAngle = targetAngle + 360
        endif
        
        # Store for visualization
if draw_visualization
    if (frame mod histStep) = 0
        if histIdx < 500
            histIdx = histIdx + 1
            posHistory#[histIdx] = targetAngle
            posHistoryY#[histIdx] = intensityNorm
        endif
    endif
endif
        
        # Map intensity to distance gain
        distanceGain = min_distance_gain + intensityNorm * (max_distance_gain - min_distance_gain)
        
        # Find nearest speaker
        minAngleDiff = 360
        nearestSpeaker = 1
        for sp from 1 to 8
            angleDiff = abs(targetAngle - speakerAngles#[sp])
            if angleDiff > 180
                angleDiff = 360 - angleDiff
            endif
            if angleDiff < minAngleDiff
                minAngleDiff = angleDiff
                nearestSpeaker = sp
            endif
        endfor
        
        # Find adjacent speaker
        if targetAngle >= speakerAngles#[nearestSpeaker]
            adjacentSpeaker = nearestSpeaker + 1
            if adjacentSpeaker > 8
                adjacentSpeaker = 1
            endif
        else
            adjacentSpeaker = nearestSpeaker - 1
            if adjacentSpeaker < 1
                adjacentSpeaker = 8
            endif
        endif
        
        # Calculate pan position between nearest and adjacent speaker
        angle1 = speakerAngles#[nearestSpeaker]
        angle2 = speakerAngles#[adjacentSpeaker]
        
        # Handle wrap-around
        if abs(angle1 - angle2) > 180
            if angle1 < angle2
                angle1 = angle1 + 360
            else
                angle2 = angle2 + 360
            endif
            if targetAngle < 180
                targetAngle = targetAngle + 360
            endif
        endif
        
        # Linear panning between the two speakers
        if angle2 <> angle1
            panPosition = (targetAngle - angle1) / (angle2 - angle1)
        else
            panPosition = 0.5
        endif
        panPosition = max(0, min(1, panPosition))
        
        # Constant-power panning
        gain_main = sqrt(1 - panPosition) * distanceGain
        gain_adjacent = sqrt(panPosition) * distanceGain
        
        # Set gains for all channels
        for ch from 1 to 8
            if ch = nearestSpeaker
                gain'ch'#[frame] = gain_main
            elsif ch = adjacentSpeaker
                gain'ch'#[frame] = gain_adjacent
            else
                gain'ch'#[frame] = distanceGain * ambient_level
            endif
        endfor
    endfor
    
    chunkStart = chunkEnd + 1
endwhile

# Apply time-varying gains to each channel
appendInfoLine: "Applying gains to channels..."
for ch from 1 to 8
    selectObject: channel'ch'
    appendInfoLine: "  Channel ", ch, "..."
    Formula: "if x < 'frameShift' then self else self * gain'ch'#[max(1, min(numberOfFrames, round(x / frameShift)))] endif"
endfor

# Combine all channels
appendInfoLine: "Combining channels..."
selectObject: channel1
for ch from 2 to 8
    plusObject: channel'ch'
endfor

multichannel = Combine to stereo
Scale peak: 0.95
Rename: soundName$ + "_8chSpatial_" + presetName$

# Clean up
selectObject: pitch, intensity, monoSound
for ch from 1 to 8
    plusObject: channel'ch'
endfor
Remove

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Speech-Driven Spatialization: " + presetName$ + " | " + soundName$
    
    # Speaker layout with trajectory
    Select outer viewport: 0.5, 5.0, 0.8, 4.5
    Select inner viewport: 0.8, 4.7, 1.1, 4.2
    
    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.5, 1.5, -1.5, 1.5
    
    # Draw speakers
    Paint circle (mm): "{0.3, 0.5, 0.7}", -0.7, 0.7, 4
    Colour: "White"
    Font size: 7
    Text: -0.7, "centre", 0.7, "half", "1"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0, 1, 4
    Colour: "White"
    Text: 0, "centre", 1, "half", "2"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.7, 0.7, 4
    Colour: "White"
    Text: 0.7, "centre", 0.7, "half", "3"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", 1, 0, 4
    Colour: "White"
    Text: 1, "centre", 0, "half", "4"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0.7, -0.7, 4
    Colour: "White"
    Text: 0.7, "centre", -0.7, "half", "5"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", 0, -1, 4
    Colour: "White"
    Text: 0, "centre", -1, "half", "6"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", -0.7, -0.7, 4
    Colour: "White"
    Text: -0.7, "centre", -0.7, "half", "7"
    
    Paint circle (mm): "{0.3, 0.5, 0.7}", -1, 0, 4
    Colour: "White"
    Text: -1, "centre", 0, "half", "8"
    
    # Listener at center
    Paint circle (mm): "{0.2, 0.6, 0.3}", 0, 0, 3
    
    # Draw movement trajectory
    Line width: 1
    maxHist = min(histIdx, 500)
    if maxHist > 1
        for i from 2 to maxHist
            i1 = i - 1
            ang1 = posHistory#[i1] * pi / 180
            ang2 = posHistory#[i] * pi / 180
            r1 = 0.3 + posHistoryY#[i1] * 0.5
            r2 = 0.3 + posHistoryY#[i] * 0.5
            
            x1 = r1 * sin(ang1)
            y1 = r1 * cos(ang1)
            x2 = r2 * sin(ang2)
            y2 = r2 * cos(ang2)
            
            # Color gradient
            progress = i / maxHist
            rCol = progress
            bCol = 1 - progress
            Colour: "{" + fixed$(rCol, 2) + ", 0.3, " + fixed$(bCol, 2) + "}"
            Draw line: x1, y1, x2, y2
        endfor
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Movement Path"
    Text: 0, "centre", 1.35, "half", "Front"
    Text: 0, "centre", -1.35, "half", "Back"
    
    # Mapping diagram
    Select outer viewport: 5.2, 9.5, 0.8, 2.5
    Select inner viewport: 5.5, 9.2, 1.0, 2.3
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    # Pitch to angle
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    Draw arrow: 0.1, 0.75, 0.9, 0.75
    Font size: 7
    Colour: "Black"
    Text: 0.1, "left", 0.85, "half", "Low pitch"
    Text: 0.9, "right", 0.85, "half", "High pitch"
    Text: 0.5, "centre", 0.65, "half", "-> Azimuth angle"
    
    # Intensity to distance
    Colour: "{0.8, 0.4, 0.3}"
    Draw arrow: 0.1, 0.3, 0.9, 0.3
    Font size: 7
    Colour: "Black"
    Text: 0.1, "left", 0.4, "half", "Soft"
    Text: 0.9, "right", 0.4, "half", "Loud"
    Text: 0.5, "centre", 0.2, "half", "-> Distance (gain)"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Feature Mapping"
    
    # Output waveform
    Select outer viewport: 5.2, 9.5, 2.7, 4.5
    Select inner viewport: 5.5, 9.2, 2.9, 4.3
    selectObject: multichannel
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Channel layout:"
appendInfoLine: "  1: Front Left (315°)"
appendInfoLine: "  2: Front Center (0°)"
appendInfoLine: "  3: Front Right (45°)"
appendInfoLine: "  4: Side Right (90°)"
appendInfoLine: "  5: Back Right (135°)"
appendInfoLine: "  6: Back Center (180°)"
appendInfoLine: "  7: Back Left (225°)"
appendInfoLine: "  8: Side Left (270°)"

if play_result
    selectObject: multichannel
    Play
endif

selectObject: multichannel
