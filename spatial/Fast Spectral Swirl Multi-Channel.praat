# ============================================================
# Praat AudioTools - Fast Spectral Swirl Multi-Channel.praat
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

# Fast Spectral Swirl Multi-Channel Script
# Creates 8-channel output with spectral swirl effect

form Spectral Swirl Multi-Channel
    positive Base_depth 50
    positive Depth_increment 25
    comment Creates 8-channel sound with different swirl parameters per channel
endform

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

sound = selected("Sound")
sound$ = selected$("Sound")
original_duration = Get total duration
sampling_rate = Get sampling frequency

# Clean up any leftover objects from previous runs (except original sound)
select all
minus sound
numberOfLeftover = numberOfSelected()
if numberOfLeftover > 0
    Remove
endif

select sound

writeInfoLine: "Starting spectral swirl processing..."
appendInfoLine: "Original: ", sound$
appendInfoLine: "Duration: ", fixed$(original_duration, 3), " seconds"
appendInfoLine: "Sampling rate: ", sampling_rate, " Hz"
appendInfoLine: "Creating 8-channel output..."

# Create 8 variations of the entire sound
for i from 1 to 8
    appendInfoLine: "Creating variation ", i, "/8"
    
    select sound
    spec = To Spectrum: "yes"
    
    cycle = i + 1
    depthVal = base_depth + depth_increment * i
    
    appendInfoLine: "  Cycle: ", cycle, ", Depth: ", depthVal
    
    # Apply spectral swirl formula
    select spec
    Formula: "if row = 1 then self[1, min(max(round(col + 'depthVal' * sin(2 * pi * 'cycle' * col / ncol)), 1), ncol)] else self[2, min(max(round(col + 'depthVal' * sin(2 * pi * 'cycle' * col / ncol)), 1), ncol)] fi"
    
    select spec
    swirled_sound = To Sound
    Scale peak: 0.99
    Rename: "swirl_" + string$(i)
    
    # Clean up spectrum
    select spec
    Remove
endfor

appendInfoLine: "Combining 8 variations into multi-channel sound..."

# Combine all 8 variations into one 8-channel sound
select Sound swirl_1
for i from 2 to 8
    plus Sound swirl_'i'
endfor

result = Combine to stereo
Rename: "vocal2_swirl_8ch"

# Verify channel count
select result
final_channels = Get number of channels
final_duration = Get total duration
appendInfoLine: "Created ", final_channels, "-channel sound"
appendInfoLine: "Final duration: ", fixed$(final_duration, 3), " seconds"

# Clean up individual variation sounds
appendInfoLine: "Cleaning up temporary objects..."
for i from 1 to 8
    select Sound swirl_'i'
    Remove
endfor

# Final scaling
select result
Scale peak: 0.99
Play

# Remove ALL other objects except the final result AND original sound
select all
minus result
minus sound
numberOfSelected = numberOfSelected()
if numberOfSelected > 0
    Remove
endif


# Final selection and info
select result
final_channels = Get number of channels
appendInfoLine: "=== PROCESSING COMPLETE ==="
appendInfoLine: "Objects remaining:"
appendInfoLine: "  - ", sound$, " (original input)"
appendInfoLine: "  - vocal2_swirl_8ch (8-channel result)"
appendInfoLine: ""
appendInfoLine: "Result details:"
appendInfoLine: "  Channels: ", final_channels
appendInfoLine: "  Duration: ", fixed$(final_duration, 3), " seconds"
appendInfoLine: "  Sample rate: ", sampling_rate, " Hz"
appendInfoLine: ""
appendInfoLine: "Channel parameters:"
for i from 1 to 8
    cycle = i + 1
    depthVal = base_depth + depth_increment * i
    appendInfoLine: "  Channel ", i, ": cycle=", cycle, ", depth=", depthVal
endfor