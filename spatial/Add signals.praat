# ============================================================
# Praat AudioTools - Add signals.praat
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

form Stereo Balance and Volume
    comment Enter volume multipliers (1.0=normal, 0.0=mute)
    comment Sound 1 (Left / Right)
    real ch1_1 1.0
    real ch2_1 1.0
    comment Sound 2
    real ch1_2 1.0
    real ch2_2 1.0
    comment Sound 3
    real ch1_3 1.0
    real ch2_3 1.0
    comment Sound 4
    real ch1_4 1.0
    real ch2_4 1.0
    comment Sound 5
    real ch1_5 1.0
    real ch2_5 1.0
endform

# Check for selected sounds and get Sound IDs
numberOfSounds = numberOfSelected("Sound")
if numberOfSounds = 0
    exitScript: "No sounds selected! Please select one or more 'Sound' objects."
endif

appendInfoLine: "Found ", numberOfSounds, " selected sound files"

# Store only the numeric Sound IDs for the sounds that actually exist
for i to numberOfSounds
    sound'i' = selected("Sound", i)
endfor

# Convert all sounds to stereo (required for separate L/R manipulation)
for i to numberOfSounds
    select sound'i'
    name$ = selected$("Sound")
    
    nChannels = Get number of channels
    if not nChannels = 2
        Convert to stereo
        sound'i' = selected("Sound")
        appendInfoLine: "Converted " + name$ + " to stereo."
    endif
endfor

# Create empty stereo sound as base
select sound1
duration = Get total duration
sampleRate = Get sampling frequency
resultSound = Create Sound from formula: "mixed_stereo", 2, 0, duration, sampleRate, "0"

# Mix each sound with ch1/ch2 gains
for i to numberOfSounds
    select sound'i'
    name$ = selected$("Sound")
    
    # Process only the first 5 sounds (as defined in the form)
    if i <= 5
        # Retrieve the user-defined gains
        leftGain = ch1_'i'
        rightGain = ch2_'i'
        
        # Apply gains to the selected sound
        tempSound = Copy: "temp_balanced"
        
        # Use Formula (part) for applying gain to specific channels
        Formula (part)... 0 0 1 1 self*leftGain
        Formula (part)... 0 0 2 2 self*rightGain
        
        # Add the newly gained sound to the result
        select resultSound
        Formula... self + object[tempSound]
        
        # Clean up temporary sound
        select tempSound
        Remove
        
        appendInfoLine: "Mixed " + name$ + " with Left Gain: " + string$(leftGain) + ", Right Gain: " + string$(rightGain)
    else
        appendInfoLine: "Skipping " + name$ + " (form only supports 5 sounds)."
    endif
endfor

# Finalization
select resultSound
appendInfoLine: "Created stereo mix 'mixed_stereo' with two-channel volume balance."