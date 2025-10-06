# ============================================================
# Praat AudioTools - Time Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Sound Manipulation
    real Duration_factor 1.0
    boolean Play_result 1
endform

# Check if a sound object is selected
if numberOfSelected("Sound") = 0
    exit Please select a Sound object first
endif

# Get the selected sound
originalSound = selected("Sound")

# Get original duration
selectObject: originalSound
duration = Get total duration

# Create manipulation object
selectObject: originalSound
manipulation = To Manipulation: 0.01, 75, 600

# Create duration tier with user-specified factor
durationTier = Create DurationTier: "duration", 0, duration
Add point: 0, duration_factor
Add point: duration, duration_factor

# Replace duration tier in manipulation
selectObject: manipulation
plusObject: durationTier
Replace duration tier

# Resynthesize using overlap-add method
selectObject: manipulation
resynthesized = Get resynthesis (overlap-add)

# Clean up intermediate objects
removeObject: durationTier, manipulation

# Play if requested
if play_result
    Play
endif

# Select the result
selectObject: resynthesized