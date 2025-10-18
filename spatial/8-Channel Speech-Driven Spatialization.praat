# ============================================================
# Praat AudioTools - 8-Channel Speech-Driven Spatialization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# 8-Channel Speech-Driven Spatialization 
# Converts selected sound to mono and pans across 8 channels based on:
# - Pitch: controls azimuth (higher → front right, lower → back left)
# - Intensity: controls distance (louder → closer, softer → farther)

# Get selected sound
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

writeInfoLine: "Starting 8-channel spatialization for: ", soundName$

# Convert to mono if stereo
numberOfChannels = Get number of channels
if numberOfChannels > 1
    selectObject: sound
    monoSound = Convert to mono
    monoName$ = soundName$ + "_mono"
else
    selectObject: sound
    monoSound = Copy: soundName$ + "_mono"
    monoName$ = soundName$ + "_mono"
endif

# Extract features with proper object selection
writeInfoLine: "Extracting pitch..."
selectObject: monoSound
pitch = To Pitch: 0.01, 75, 600

writeInfoLine: "Extracting intensity..."
selectObject: monoSound
intensity = To Intensity: 100, 0.01, "yes"

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

# Create 8 copies of the mono sound (one per channel)
writeInfoLine: "Creating channel copies..."
speakerAngles# = { 315, 0, 45, 90, 135, 180, 225, 270 }

selectObject: monoSound
for ch from 1 to 8
    channel'ch' = Copy: "channel_'ch'"
endfor

# Process in chunks to build gain envelopes
frameShift = 0.01
numberOfFrames = floor(duration / frameShift)
chunkSize = min(1000, numberOfFrames)

writeInfoLine: "Processing ", numberOfFrames, " frames..."

# Create gain arrays
for ch from 1 to 8
    gain'ch'# = zero# (numberOfFrames)
endfor

# Build time-varying gains
lastPitchValue = pitchMean
chunkStart = 1

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
        
        # Get intensity at this time (FIXED: with correct interpolation method)
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
        
        # Map pitch to azimuth angle (0-360 degrees)
        # Low pitch → back left (225°), high pitch → front right (45°)
        targetAngle = 225 + pitchNorm * (45 - 225 + 360)
        if targetAngle >= 360
            targetAngle = targetAngle - 360
        endif
        
        # Map intensity to distance (louder = closer = more gain)
        distanceGain = 0.2 + intensityNorm * 0.8
        
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
        if angle2 != angle1
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
                # Very low gain for other channels
                gain'ch'#[frame] = distanceGain * 0.05
            endif
        endfor
    endfor
    
    chunkStart = chunkEnd + 1
endwhile

# Apply time-varying gains to each channel copy
writeInfoLine: "Applying gains to channels..."
for ch from 1 to 8
    selectObject: channel'ch'
    appendInfoLine: "  Processing channel ", ch, "..."
    
    # Apply gains using Formula
    Formula: "if x < 'frameShift' then self else self * gain'ch'#[max(1, min(numberOfFrames, round(x / frameShift)))] endif"
endfor

# Combine all channels into one multi-channel sound
writeInfoLine: "Combining channels..."
selectObject: channel1
for ch from 2 to 8
    plusObject: channel'ch'
endfor

multichannel = Combine to stereo
Rename: soundName$ + "_8ch_spatialized"

# Clean up intermediate objects but keep final result
selectObject: pitch, intensity
for ch from 1 to 8
    plusObject: channel'ch'
endfor
if monoSound <> sound
    plusObject: monoSound
endif
Remove

# Select the final result
selectObject: multichannel

appendInfoLine: ""
appendInfoLine: "✓ 8-channel spatialization complete!"
appendInfoLine: "Channel layout:"
appendInfoLine: "  1: Front Left (315°)"
appendInfoLine: "  2: Front Center (0°)"
appendInfoLine: "  3: Front Right (45°)"
appendInfoLine: "  4: Side Right (90°)"
appendInfoLine: "  5: Back Right (135°)"
appendInfoLine: "  6: Back Center (180°)"
appendInfoLine: "  7: Back Left (225°)"
appendInfoLine: "  8: Side Left (270°)"
appendInfoLine: ""
appendInfoLine: "Total duration: ", fixed$(duration, 2), " seconds"