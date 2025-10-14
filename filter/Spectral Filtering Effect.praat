# ============================================================
# Praat AudioTools - Adaptive Low-pass Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Brightness Filter script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Spectral Brightness Filter
# Modifies the brightness of a sound

form Brightness Filter
    comment Brightness adjustment:
    choice brightness_change: 1
        button Increase brightness
        button Decrease brightness
    positive strength 50
    comment Output:
    boolean preview 1
endform

sound = selected("Sound")
if sound = 0
    exitScript: "Please select a Sound object first"
endif

sound_name$ = selected$("Sound")
appendInfoLine: "Applying brightness filter to: " + sound_name$

# Copy the original sound
select sound
Copy: "brightness_filtered"
filtered_sound = selected("Sound")

# Apply filter bank approach
if brightness_change = 1
    # Increase brightness - boost high frequencies
    select filtered_sound
    Filter (pass Hann band): 1000, 10000, 100
    filtered1 = selected("Sound")
    Formula: "self + (self * strength/100)"
    
    select filtered_sound
    Filter (pass Hann band): 5000, 15000, 100
    filtered2 = selected("Sound") 
    Formula: "self * (strength/200)"
    
    select filtered_sound
    plus filtered1
    plus filtered2
    Combine to stereo
    result = selected("Sound")
    Convert to mono
    final_sound = selected("Sound")
    
else
    # Decrease brightness - attenuate high frequencies
    select filtered_sound
    Filter (stop Hann band): 2000, 10000, 100
    final_sound = selected("Sound")
endif

# Cleanup
select filtered_sound
if brightness_change = 1
    plus filtered1
    plus filtered2
    plus result
endif
Remove

appendInfoLine: "Brightness filter applied! Strength: " + string$(strength) + "%"

if preview
    select final_sound
    Play
endif