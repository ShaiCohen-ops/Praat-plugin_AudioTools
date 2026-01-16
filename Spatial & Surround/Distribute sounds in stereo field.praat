# ============================================================
# Praat AudioTools - Distribute_sounds_in_stereo_field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distributes multiple selected sounds across the stereo field
#   using constant-power panning and mixes to single stereo output.
# ============================================================

# Get number of selected sounds
numberOfSounds = numberOfSelected("Sound")

if numberOfSounds < 2
    exitScript: "Please select at least 2 Sound objects to create a mix."
endif

# Feedback for user
writeInfoLine: "Mixing ", numberOfSounds, " sounds..."

# Store all sound IDs
for i from 1 to numberOfSounds
    sound[i] = selected("Sound", i)
endfor

# Determine Output Parameters
selectObject: sound[1]
sampleRate = Get sampling frequency
maxDuration = 0

# Find maximum duration across all files
for i from 1 to numberOfSounds
    selectObject: sound[i]
    thisDuration = Get total duration
    if thisDuration > maxDuration
        maxDuration = thisDuration
    endif
endfor

# Create the canvas (Empty Stereo Sound)
selectObject: sound[1]
baseName$ = selected$("Sound")
stereoMix = Create Sound from formula: baseName$ + "_mix", 2, 0, maxDuration, sampleRate, "0"

# Process and Mix
for i from 1 to numberOfSounds
    selectObject: sound[i]
    
    # Calculate Pan Position (-1 to +1)
    pan = -1 + (2 * (i - 1) / (numberOfSounds - 1))
    
    # Handle Stereo inputs (fold down to mono before panning)
    nChannels = Get number of channels
    if nChannels > 1
        mono = Convert to mono
    else
        mono = Copy: "temp_mono"
    endif
    
    # Calculate Constant Power Gains
    leftGain = sqrt((1 - pan) / 2)
    rightGain = sqrt((1 + pan) / 2)
    
    # Get duration of this specific sound
    selectObject: mono
    soundDuration = Get total duration
    
    # Add to LEFT channel
    selectObject: stereoMix
    Formula (part): 0, soundDuration, 1, 1, "self + object[mono] * " + string$(leftGain)
    
    # Add to RIGHT channel
    Formula (part): 0, soundDuration, 2, 2, "self + object[mono] * " + string$(rightGain)
    
    # Clean up temp object
    removeObject: mono
    
    # Update info window
    appendInfoLine: "  ", i, ". pan=", fixed$(pan, 2), " (L:", fixed$(leftGain, 2), " R:", fixed$(rightGain, 2), ")"
endfor

# Finalize - Prevent Clipping
selectObject: stereoMix
Scale peak: 0.95

appendInfoLine: ""
appendInfoLine: "Done! Output scaled to 0.95 peak."

selectObject: stereoMix
Play