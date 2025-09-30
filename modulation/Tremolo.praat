# Adaptive Tremolo - modulation depth follows input amplitude
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

form Adaptive Tremolo
    positive Modulation_rate_Hz 3
    positive Max_modulation_depth 0.7
endform

selectObject: sound
Copy: "adaptive_tremolo"
processed = selected("Sound")

# Create amplitude modulation that adapts to signal level
selectObject: processed
Formula: "self * (1 - max_modulation_depth * (1 + sin(2*pi*modulation_rate_Hz*x))/2 * (0.5 + 0.5 * abs(self)))"

Play