form Harsh Distortion Effect
    comment This script applies extreme distortion with gating
    comment Distortion parameters:
    positive base_amplitude 0.5
    positive modulation_amplitude 0.3
    positive modulation_frequency 100
    comment Gating parameters:
    positive gate_period 0.05
    positive gate_duty_cycle 0.025
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_distorted"

# Apply harsh distortion with modulation and gating
Formula: "if self > 0 then 1 else -1 fi * ('base_amplitude' + 'modulation_amplitude' * sin('modulation_frequency' * x)) * if (x mod 'gate_period' > 'gate_duty_cycle') then 1 else 0 fi"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
