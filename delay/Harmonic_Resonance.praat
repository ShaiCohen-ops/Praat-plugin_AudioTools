# ============================================================
# Praat AudioTools - Harmonic_Resonance.praat
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

form Harmonic Sound Processing
    optionmenu Preset: 1
        option "Default (2.5 base, 0.6 decay)"
        option "Soft Harmonics (1.8 base, 0.4 decay)"
        option "Strong Harmonics (3.5 base, 0.8 decay)"
        option "Wide Random (1.2–5.0 range)"
        option "Custom"
    comment Harmonic processing parameters:
    natural num_iterations 7
    comment Harmonic base range (for randomization):
    positive harmonic_base_min 1.5
    positive harmonic_base_max 4.0
    comment Or use a fixed harmonic base:
    boolean use_fixed_base 0
    positive fixed_harmonic_base 2.5
    comment Amplitude decay parameters:
    positive decay_factor 0.6
    comment Output options:
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# Apply preset if not Custom
if preset = 1
    fixed_harmonic_base = 2.5
    harmonic_base_min = 1.5
    harmonic_base_max = 4.0
    decay_factor = 0.6
elsif preset = 2
    fixed_harmonic_base = 1.8
    harmonic_base_min = 1.2
    harmonic_base_max = 2.5
    decay_factor = 0.4
elsif preset = 3
    fixed_harmonic_base = 3.5
    harmonic_base_min = 2.5
    harmonic_base_max = 4.5
    decay_factor = 0.8
elsif preset = 4
    harmonic_base_min = 1.2
    harmonic_base_max = 5.0
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Determine harmonic base
if use_fixed_base
    harmonicBase = fixed_harmonic_base
else
    harmonicBase = randomUniform(harmonic_base_min, harmonic_base_max)
endif

# Main harmonic processing loop
for k from 1 to num_iterations
    # Exponential harmonic progression
    shiftFactor = harmonicBase ^ k
    b = a / shiftFactor
    
    # Bidirectional formula with harmonic weighting
    Formula: "(self [col + round(b)] - self [col - round(b/2)]) * (1/k)"
    
    # Harmonic amplitude decay
    Formula: "self * (1 - k/num_iterations * 'decay_factor')"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
