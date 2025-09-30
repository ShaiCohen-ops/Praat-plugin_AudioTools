# Check if a sound is selected
if numberOfSelected("Sound") = 0
    exitScript: "Please select a sound first."
endif

# Get the selected sound
selectedSound$ = selected$("Sound")
selectObject: "Sound 'selectedSound$'"

# Process the selected sound
To Pitch: 0, 75, 600
pitchObj = selected("Pitch")
Smooth: 10
smoothPitchObj = selected("Pitch")
Down to PitchTier
pitchTierObj = selected("PitchTier")

# Create synthesized sound from PitchTier
selectObject: pitchTierObj
To Sound (phonation): 44100, 1, 0.05, 0.7, 0.03, 3, 4, "no"
synthVoiceObj = selected("Sound")
Rename: "synthesized_voice"

# Process the original sound for LPC analysis
selectObject: "Sound 'selectedSound$'"
To LPC (autocorrelation): 44, 0.025, 0.005, 50
lpcObj = selected("LPC")

# Filter the synthesized voice through LPC
selectObject: lpcObj
plusObject: synthVoiceObj
Filter: "no"
finalObj = selected("Sound")
Rename: "final_output"

# Scale intensity of the final result
selectObject: finalObj
Scale intensity: 70

# Play the final result
selectObject: finalObj
Play

# Clean up ALL intermediate objects using object IDs
selectObject: pitchObj, smoothPitchObj, pitchTierObj, synthVoiceObj, lpcObj
Remove

# Keep only the original and final sounds
selectObject: "Sound 'selectedSound$'", finalObj