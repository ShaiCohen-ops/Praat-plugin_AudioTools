# ============================================================
# Praat AudioTools - LPC Voice Morphing.praat
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

form LPC Vocoder
    comment This script creates a vocoded version using LPC analysis
    comment Pitch analysis parameters:
    positive time_step 0.1
    positive minimum_pitch 75
    positive maximum_pitch 600
    comment Pitch smoothing:
    positive smoothing_bandwidth 10
    comment (Hz, higher = more smoothing)
    comment Phonation parameters:
    positive sampling_frequency 44100
    positive pitch_tier_amplitude 1
    positive open_phase 0.05
    positive collision_phase 0.7
    positive power_1 0.03
    positive power_2 3
    positive power_3 4
    boolean flutter no
    comment LPC analysis parameters:
    natural prediction_order 44
    positive analysis_width 0.025
    positive time_step_lpc 0.005
    positive pre_emphasis_from 50
    comment Output parameters:
    positive target_intensity_db 70
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a sound is selected
if numberOfSelected("Sound") = 0
    exitScript: "Please select a sound first."
endif

# Get the selected sound
selectedSound$ = selected$("Sound")
selectObject: "Sound 'selectedSound$'"

# Extract and process pitch
To Pitch: time_step, minimum_pitch, maximum_pitch
pitchObj = selected("Pitch")

# Smooth the pitch contour
Smooth: smoothing_bandwidth
smoothPitchObj = selected("Pitch")

# Convert to PitchTier
Down to PitchTier
pitchTierObj = selected("PitchTier")

# Create synthesized voice from PitchTier
selectObject: pitchTierObj
To Sound (phonation): sampling_frequency, pitch_tier_amplitude, open_phase, collision_phase, power_1, power_2, power_3, flutter
synthVoiceObj = selected("Sound")
Rename: "synthesized_voice"

# Perform LPC analysis on original sound
selectObject: "Sound 'selectedSound$'"
To LPC (autocorrelation): prediction_order, analysis_width, time_step_lpc, pre_emphasis_from
lpcObj = selected("LPC")

# Filter the synthesized voice through LPC
selectObject: lpcObj
plusObject: synthVoiceObj
Filter: "no"
finalObj = selected("Sound")
Rename: selectedSound$ + "_vocoded"

# Scale intensity of the final result
selectObject: finalObj
Scale intensity: target_intensity_db

# Play if requested
if play_after_processing
    selectObject: finalObj
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    selectObject: pitchObj, smoothPitchObj, pitchTierObj, synthVoiceObj, lpcObj
    Remove
endif

# Select final result
selectObject: finalObj