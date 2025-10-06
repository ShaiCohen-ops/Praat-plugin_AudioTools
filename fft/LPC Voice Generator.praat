# ============================================================
# Praat AudioTools - LPC Voice Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Check if a sound is selected
if numberOfSelected("Sound") = 0
    exitScript: "Please select a sound first."
endif

# Get the selected sound
selectedSound$ = selected$("Sound")
selectObject: "Sound 'selectedSound$'"

# Extract pitch information
To Pitch: 0, 75, 600
pitchObj = selected("Pitch")
Smooth: 10
smoothPitchObj = selected("Pitch")
Down to PitchTier
pitchTierObj = selected("PitchTier")

# Create synthesized voice from pitch
selectObject: pitchTierObj
To Sound (phonation): 44100, 1, 0.05, 0.7, 0.03, 3, 4, "no"
synthVoiceObj = selected("Sound")

# Extract spectral envelope from original
selectObject: "Sound 'selectedSound$'"
To LPC (autocorrelation): 44, 0.025, 0.005, 50
lpcObj = selected("LPC")

# Apply original spectral characteristics to synthetic voice
selectObject: lpcObj
plusObject: synthVoiceObj
Filter: "no"
finalObj = selected("Sound")
Rename: "voice_synthesized"

# Final processing
selectObject: finalObj
Scale intensity: 70
Play

# Clean up intermediate objects
selectObject: pitchObj, smoothPitchObj, pitchTierObj, synthVoiceObj, lpcObj
Remove

# Select original and result
selectObject: "Sound 'selectedSound$'", finalObj