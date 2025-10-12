# ============================================================
# Praat AudioTools - Accelerating Polyrhythm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Accelerating Polyrhythm
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
form Creative Accelerating Polyrhythm
    comment Basic Settings:
    real Base_duration 2.0
    integer Total_cycles 8
    integer Samplerate 44100
    
    comment Pattern 1:
    integer Pattern1_beats 3
    real Pattern1_frequency 300
    real Pattern1_amp 0.3
    
    comment Pattern 2:
    integer Pattern2_beats 4  
    real Pattern2_frequency 500
    real Pattern2_amp 0.3
    
    comment Acceleration:
    real Acceleration_factor 2.0
    boolean Exponential_acceleration 1
    choice Morph_type: 1
        option Frequency morph
        option Amplitude morph
        option Rhythm morph
        option Random evolution
    comment Tone:
    real Tone_duration 0.1
    comment Effects:
    boolean Stereo_pan 1
endform

# Creative Polyrhythm with Multiple Variations
# Creates evolving polyrhythmic patterns

# Calculate total duration
total_duration = 0
for cycle to total_cycles
    if exponential_acceleration
        total_duration += base_duration / (acceleration_factor^(cycle-1))
    else
        total_duration += base_duration / (1 + (cycle-1) * (acceleration_factor-1))
    endif
endfor

# Create empty sound
Create Sound from formula: "creative_poly", 1, 0, total_duration, samplerate, "0"
select Sound creative_poly

# Current start time for each cycle
current_time = 0

for cycle to total_cycles
    # Calculate duration for this cycle
    if exponential_acceleration
        cycle_duration = base_duration / (acceleration_factor^(cycle-1))
    else
        cycle_duration = base_duration / (1 + (cycle-1) * (acceleration_factor-1))
    endif
    
    # Initialize variables for this cycle
    current_freq1 = pattern1_frequency
    current_freq2 = pattern2_frequency
    current_amp1 = pattern1_amp
    current_amp2 = pattern2_amp
    current_beats1 = pattern1_beats
    current_beats2 = pattern2_beats
    
    # Apply morphing based on cycle
    if morph_type = 1
        # Frequency morph - frequencies evolve
        current_freq1 = pattern1_frequency * (1 + (cycle-1)/total_cycles)
        current_freq2 = pattern2_frequency * (1.5 - (cycle-1)/(2*total_cycles))
    elif morph_type = 2
        # Amplitude morph - amplitudes evolve
        current_amp1 = pattern1_amp * (1 - (cycle-1)/(2*total_cycles))
        current_amp2 = pattern2_amp * (0.5 + (cycle-1)/(2*total_cycles))
    elif morph_type = 3
        # Rhythm morph - beat counts evolve
        current_beats1 = pattern1_beats + cycle - 1
        current_beats2 = pattern2_beats
    elif morph_type = 4
        # Random evolution
        current_freq1 = pattern1_frequency * (0.8 + randomInteger(0,4)/10)
        current_freq2 = pattern2_frequency * (0.8 + randomInteger(0,4)/10)
        current_amp1 = pattern1_amp * (0.7 + randomInteger(0,6)/10)
        current_amp2 = pattern2_amp * (0.7 + randomInteger(0,6)/10)
    endif
    
    # Calculate spacing
    slow_spacing = cycle_duration / current_beats1
    fast_spacing = cycle_duration / current_beats2
    
    # Add pattern 1 (sine waves only)
    for i to current_beats1
        start = current_time + (i-1) * slow_spacing
        
        # Stereo panning
        if stereo_pan and current_beats1 > 1
            pan = -0.5 + (i-1)/(current_beats1-1)
            pan_amp = current_amp1 * (1 - abs(pan))
        else
            pan_amp = current_amp1
        endif
        
        formula$ = "if x >= " + string$(start) + " and x < " + string$(start + tone_duration)
        formula$ = formula$ + " then self + " + string$(pan_amp) + "*sin(2*pi*" + string$(current_freq1) + "*x) else self fi"
        Formula: formula$
    endfor
    
    # Add pattern 2 (sine waves only)
    for i to current_beats2
        start = current_time + (i-1) * fast_spacing
        
        # Stereo panning
        if stereo_pan and current_beats2 > 1
            pan = 0.5 - (i-1)/(current_beats2-1)
            pan_amp = current_amp2 * (1 - abs(pan))
        else
            pan_amp = current_amp2
        endif
        
        formula$ = "if x >= " + string$(start) + " and x < " + string$(start + tone_duration)
        formula$ = formula$ + " then self + " + string$(pan_amp) + "*sin(2*pi*" + string$(current_freq2) + "*x) else self fi"
        Formula: formula$
    endfor
    
    # Move to next cycle
    current_time += cycle_duration
endfor

# Play the result
select Sound creative_poly
Scale peak: 0.9
Play

echo Creative polyrhythm created!
echo "Pattern: 'pattern1_beats' against 'pattern2_beats'"
echo "'total_cycles' cycles, total duration: 'total_duration:2' seconds"
echo "Morph type: 'morph_type'"