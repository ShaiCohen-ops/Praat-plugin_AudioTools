# ============================================================
# Praat AudioTools - Stochastic Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound synthesis or generative algorithm script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Stochastic Synthesis - Direct Formula Mixing
# This method avoids the paste command entirely

form Stochastic Synthesis Parameters
    real Duration 4.0
    real Sampling_frequency 44100
    real Base_frequency 150
    real Frequency_variance 300
    real Grain_duration 0.03
    real Density_(grains_per_second) 80
    real Amplitude_variance 0.4
endform

# Create the sound using a formula that sums grains
formula$ = "0"
total_grains = round(density * duration)

for i to total_grains
    # Random parameters for each grain
    grain_freq = base_frequency + frequency_variance * (randomUniform(0,1) - 0.5)
    grain_amp = 0.5 + amplitude_variance * (randomUniform(0,1) - 0.5)
    grain_start = randomUniform(0, duration - grain_duration)
    
    # Create grain formula component
    grain_formula$ = "if x >= " + string$(grain_start) + " and x < " + string$(grain_start + grain_duration) + 
    ... " then " + string$(grain_amp) + " * sin(2*pi*" + string$(grain_freq) + "*x) else 0 fi"
    
    # Add to main formula
    if i = 1
        formula$ = grain_formula$
    else
        formula$ = formula$ + " + " + grain_formula$
    endif
    
    if i mod 50 == 0
        echo Building formula... 'i'/'total_grains' grains added
    endif
endfor

echo Creating final sound...
Create Sound from formula... stochastic_result 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Direct formula synthesis complete!