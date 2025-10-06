# ============================================================
# Praat AudioTools - Pitch Stylization and Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Pitch Stylization and Shift
    real Stylize_frequency 2
    real Shift_amount -20
    boolean Play_result 1
endform

# Check if a sound object is selected
if numberOfSelected("Sound") = 0
    exit Please select a Sound object first
endif

# Get the selected sound
originalSound = selected("Sound")

# Create manipulation object
selectObject: originalSound
manipulation = To Manipulation: 0.01, 75, 600

# Get duration for the shift command
selectObject: originalSound
duration = Get total duration

# Create manipulation object
selectObject: originalSound
manipulation = To Manipulation: 0.01, 75, 600

# Extract pitch tier for modifications
selectObject: manipulation
pitchTier = Extract pitch tier

# Stylize the pitch tier if frequency > 0
if stylize_frequency > 0
    selectObject: pitchTier
    Stylize: stylize_frequency, "Hz"
endif

# Shift pitch frequencies on the pitch tier
selectObject: pitchTier
Shift frequencies: 0, duration, shift_amount, "Hertz"

# Put the modified pitch tier back into manipulation
selectObject: manipulation
plusObject: pitchTier
Replace pitch tier

# Get resynthesis using overlap-add method
selectObject: manipulation
resynthesized = Get resynthesis (overlap-add)

# Clean up all intermediate objects
removeObject: pitchTier, manipulation

# Play if requested
if play_result
    Play
endif

# Select the result
selectObject: resynthesized