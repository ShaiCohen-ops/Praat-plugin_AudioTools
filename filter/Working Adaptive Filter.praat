# Adaptive Low-pass Filter - cutoff frequency sweeps over time
sound = selected("Sound")
if !sound
    exitScript: "Please select a Sound object first."
endif

form Adaptive Filter
    positive Start_cutoff_Hz 200
    positive End_cutoff_Hz 2000
endform

selectObject: sound
duration = Get total duration

# Create a filter that sweeps frequency
Copy: "adaptive_filter"
processed = selected("Sound")

# Simple frequency sweep effect
selectObject: processed
Formula: "self * sin(2*pi*(start_cutoff_Hz + (end_cutoff_Hz-start_cutoff_Hz)*(x/duration))*x)"

Play