# ============================================================
# Praat AudioTools - Spectral_Freeze_&_Glitch.praat
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

form Time Freeze Effect Processing
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Short Bursts"
        option "Long Freeze"
        option "Artifact Storm"
        option "Custom"
    comment Freeze parameters:
    natural freeze_points 12
    positive freeze_duration_divisor 25
    comment Freeze length variation:
    positive freeze_length_min_factor 0.5
    positive freeze_length_max_factor 1.5
    positive freeze_repeat_divisor 3
    comment Spectral artifacts:
    positive artifact_amplitude 0.1
    comment Output options:
    positive scale_peak 0.91
    boolean play_after_processing 1
    comment Random seed (optional, leave unchecked for random):
    boolean use_random_seed 0
    positive random_seed 12345
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    freeze_points = 12
    freeze_duration_divisor = 25
    freeze_length_min_factor = 0.5
    freeze_length_max_factor = 1.5
    freeze_repeat_divisor = 3
    artifact_amplitude = 0.1
    scale_peak = 0.91
elsif preset = 2
    # Short Bursts
    freeze_points = 8
    freeze_duration_divisor = 15
    freeze_length_min_factor = 0.3
    freeze_length_max_factor = 1.0
    freeze_repeat_divisor = 2
    artifact_amplitude = 0.05
    scale_peak = 0.91
elsif preset = 3
    # Long Freeze
    freeze_points = 16
    freeze_duration_divisor = 40
    freeze_length_min_factor = 0.8
    freeze_length_max_factor = 2.0
    freeze_repeat_divisor = 4
    artifact_amplitude = 0.12
    scale_peak = 0.91
elsif preset = 4
    # Artifact Storm
    freeze_points = 20
    freeze_duration_divisor = 20
    freeze_length_min_factor = 0.4
    freeze_length_max_factor = 1.6
    freeze_repeat_divisor = 2
    artifact_amplitude = 0.25
    scale_peak = 0.91
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Set random seed if specified
if use_random_seed
    random_seed_value = random_seed
endif

# Calculate freeze duration
freezeDuration = a / freeze_duration_divisor

# Main freeze processing loop
for point from 1 to freeze_points
    # Random freeze position
    freezePos = randomInteger(floor(freezeDuration), a - floor(freezeDuration))
    freezeLength = randomInteger(floor(freezeDuration * freeze_length_min_factor), floor(freezeDuration * freeze_length_max_factor))
    
    # Freeze and repeat segment
    Formula: "if col >= freezePos and col < freezePos + freezeLength then self[freezePos + ((col - freezePos) mod (freezeLength/'freeze_repeat_divisor'))] else self fi"
    
    # Add spectral artifacts
    Formula: "self * (1 + 'artifact_amplitude' * sin(2 * pi * point * col / a))"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
