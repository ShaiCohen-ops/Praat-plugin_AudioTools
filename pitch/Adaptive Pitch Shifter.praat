# Adaptive Pitch Shifter - pitch changes with amplitude
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

form Adaptive Pitch Shift
    positive Base_pitch_shift 1.0
    positive Modulation_amount 0.5
endform

selectObject: sound
Copy: "pitch_shifted"
processed = selected("Sound")

# Simple pitch modulation based on amplitude
selectObject: processed
Formula: "self * sin(2*pi*440*x * (base_pitch_shift + modulation_amount * abs(self)))"

Play