# ============================================================
# Praat AudioTools - LPC Voice Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Added visualization
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
originalID = selected("Sound")
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

# ============================================================
# VISUALIZATION
# ============================================================

Erase all

# Title
Select outer viewport: 0, 8, 0, 0.5
Font size: 14
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "LPC Voice Generator: " + selectedSound$

# Original waveform
Select outer viewport: 0, 4, 0.6, 1.8
Select inner viewport: 0.5, 3.7, 0.7, 1.7
selectObject: originalID
Colour: "{0.7, 0.7, 0.7}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 8
Text top: "no", "Original"

# Synthesized waveform
Select outer viewport: 4, 8, 0.6, 1.8
Select inner viewport: 4.5, 7.7, 0.7, 1.7
selectObject: finalObj
Colour: "{0.2, 0.5, 0.8}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Text top: "no", "LPC Synthesized"

# Pitch contour
Select outer viewport: 0, 8, 2.0, 3.4
Select inner viewport: 0.6, 7.6, 2.2, 3.2
selectObject: smoothPitchObj
Colour: "{0.9, 0.4, 0.2}"
Line width: 2
Draw: 0, 0, 75, 600, "no"
Line width: 1
Colour: "Black"
Draw inner box
Font size: 9
Text top: "no", "Extracted Pitch Contour"
Text left: "yes", "F0 (Hz)"
Text bottom: "yes", "Time (s)"

# Original spectrogram
Select outer viewport: 0, 4, 3.6, 5.2
selectObject: originalID
origSpecID = To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
selectObject: origSpecID
Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
Font size: 8
Text top: "no", "Original Spectrogram"
removeObject: origSpecID

# Synthesized spectrogram
Select outer viewport: 4, 8, 3.6, 5.2
selectObject: finalObj
resSpecID = To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
selectObject: resSpecID
Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
Text top: "no", "Synthesized Spectrogram"
removeObject: resSpecID

Font size: 10

# ============================================================
# PLAY AND CLEANUP
# ============================================================

selectObject: finalObj
Play

# Clean up intermediate objects
selectObject: pitchObj
plusObject: smoothPitchObj
plusObject: pitchTierObj
plusObject: synthVoiceObj
plusObject: lpcObj
Remove

selectObject: originalID
plusObject: finalObj