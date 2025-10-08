# ============================================================
# Praat AudioTools - Advanced Poisson Synthesis.praat
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

form Advanced Poisson Synthesis System
    positive Duration_(sec) 12
    positive Base_frequency_(Hz) 100
    positive Frequency_range_(Hz) 300
    positive Low_rate_(events/sec) 3
    positive High_rate_(events/sec) 15
    integer Number_of_layers 3
    boolean Randomize_parameters 1
    positive Fade_time_(sec) 2
    optionmenu Synthesis_mode: 1
        option Three Layer Standard
        option Dense Granular
        option Sparse Atmospheric
        option Rhythmic Pulses
        option Chaotic Scatter
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    boolean Normalize_output 1
endform

if number_of_layers > 8
    number_of_layers = 8
endif

sample_rate = 44100

echo Building Advanced Poisson Synthesis...

# Create base sound
Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"

if synthesis_mode = 1
    # Three Layer Standard
    for layer from 1 to number_of_layers
        if randomize_parameters
            layer_rate = low_rate + (high_rate - low_rate) * (layer - 1) / max(1, number_of_layers - 1) * (0.8 + 0.4 * randomUniform(0, 1))
        else
            layer_rate = low_rate + (high_rate - low_rate) * (layer - 1) / max(1, number_of_layers - 1)
        endif
        
        Create Poisson process: "poisson_layer_'layer'", 0, duration, layer_rate
        
        select PointProcess poisson_layer_'layer'
        num_points = Get number of points
        echo Layer 'layer': 'num_points' points at 'layer_rate:1' events/sec
        
        for point to num_points
            select PointProcess poisson_layer_'layer'
            point_time = Get time from index: point
            grain_freq = base_frequency + frequency_range * randomUniform(0, 1)
            grain_dur = 0.1 + 0.2 * randomUniform(0, 1)
            grain_amp = 1.5 / number_of_layers
            
            call addGrainToOutput
        endfor
        
        select PointProcess poisson_layer_'layer'
        Remove
    endfor
    
elsif synthesis_mode = 2
    # Dense Granular
    for layer from 1 to number_of_layers
        if randomize_parameters
            layer_rate = high_rate * 1.5 * (0.7 + 0.6 * randomUniform(0, 1))
        else
            layer_rate = high_rate * 1.5
        endif
        
        Create Poisson process: "poisson_layer_'layer'", 0, duration, layer_rate
        
        select PointProcess poisson_layer_'layer'
        num_points = Get number of points
        echo Layer 'layer': 'num_points' points at 'layer_rate:1' events/sec
        
        for point to num_points
            select PointProcess poisson_layer_'layer'
            point_time = Get time from index: point
            grain_freq = base_frequency * (0.5 + layer * 0.3) + frequency_range * randomUniform(0, 1)
            grain_dur = 0.03 + 0.08 * randomUniform(0, 1)
            grain_amp = 1.2 / number_of_layers
            
            call addGrainToOutput
        endfor
        
        select PointProcess poisson_layer_'layer'
        Remove
    endfor
    
elsif synthesis_mode = 3
    # Sparse Atmospheric
    for layer from 1 to number_of_layers
        if randomize_parameters
            layer_rate = low_rate * 0.5 * (0.6 + 0.8 * randomUniform(0, 1))
        else
            layer_rate = low_rate * 0.5
        endif
        
        Create Poisson process: "poisson_layer_'layer'", 0, duration, layer_rate
        
        select PointProcess poisson_layer_'layer'
        num_points = Get number of points
        echo Layer 'layer': 'num_points' points at 'layer_rate:1' events/sec
        
        for point to num_points
            select PointProcess poisson_layer_'layer'
            point_time = Get time from index: point
            grain_freq = base_frequency * (0.3 + layer * 0.4) + frequency_range * 0.5 * randomUniform(0, 1)
            grain_dur = 0.3 + 0.5 * randomUniform(0, 1)
            grain_amp = 2.0 / number_of_layers
            
            call addGrainToOutput
        endfor
        
        select PointProcess poisson_layer_'layer'
        Remove
    endfor
    
elsif synthesis_mode = 4
    # Rhythmic Pulses
    for layer from 1 to number_of_layers
        if randomize_parameters
            layer_rate = (low_rate + high_rate) / 2 * (0.9 + 0.2 * randomUniform(0, 1))
        else
            layer_rate = (low_rate + high_rate) / 2
        endif
        
        Create Poisson process: "poisson_layer_'layer'", 0, duration, layer_rate
        
        select PointProcess poisson_layer_'layer'
        num_points = Get number of points
        echo Layer 'layer': 'num_points' points at 'layer_rate:1' events/sec
        
        for point to num_points
            select PointProcess poisson_layer_'layer'
            point_time = Get time from index: point
            grain_freq = base_frequency * layer + frequency_range * 0.3 * randomUniform(0, 1)
            grain_dur = 0.08 + 0.12 * randomUniform(0, 1)
            grain_amp = 1.8 / number_of_layers
            
            call addGrainToOutput
        endfor
        
        select PointProcess poisson_layer_'layer'
        Remove
    endfor
    
elsif synthesis_mode = 5
    # Chaotic Scatter
    for layer from 1 to number_of_layers
        if randomize_parameters
            layer_rate = (low_rate + (high_rate - low_rate) * randomUniform(0, 1)) * (0.5 + randomUniform(0, 1))
        else
            layer_rate = low_rate + (high_rate - low_rate) * randomUniform(0, 1)
        endif
        
        Create Poisson process: "poisson_layer_'layer'", 0, duration, layer_rate
        
        select PointProcess poisson_layer_'layer'
        num_points = Get number of points
        echo Layer 'layer': 'num_points' points at 'layer_rate:1' events/sec
        
        for point to num_points
            select PointProcess poisson_layer_'layer'
            point_time = Get time from index: point
            grain_freq = base_frequency * (0.5 + 2 * randomUniform(0, 1)) + frequency_range * randomUniform(0, 1)
            grain_dur = 0.05 + 0.3 * randomUniform(0, 1)
            grain_amp = 1.5 / number_of_layers
            
            call addGrainToOutput
        endfor
        
        select PointProcess poisson_layer_'layer'
        Remove
    endfor
endif

# Select gen_output for spatial processing
select Sound gen_output

if spatial_mode = 1
    Rename: "poisson_synthesis"
    final_sound = selected("Sound")
    
elsif spatial_mode = 2
    Copy: "poisson_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "poisson_right"
    right_sound = selected("Sound")
    
    select left_sound
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, 4000, 100
    
    select right_sound
    Formula: "self * 0.8"
    Filter (pass Hann band): 200, 8000, 100
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "poisson_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    Copy: "poisson_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "poisson_right"
    right_sound = selected("Sound")
    
    rotation_rate = 0.25
    select left_sound
    Formula: "self * (0.6 + cos(2*pi*'rotation_rate'*x) * 0.4)"
    
    select right_sound
    Formula: "self * (0.6 + sin(2*pi*'rotation_rate'*x) * 0.4)"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "poisson_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    Copy: "poisson_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "poisson_right"
    right_sound = selected("Sound")
    
    select left_sound
    Filter (pass Hann band): 50, 3000, 80
    
    select right_sound
    Formula: "if col > 30 then self[col - 30] else 0 fi"
    Filter (pass Hann band): 200, 6000, 80
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "poisson_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

# Clean up gen_output if it still exists (not renamed in Mono mode)
if spatial_mode <> 1
    select Sound gen_output
    Remove
endif

select final_sound

if normalize_output
    Scale peak: 0.9
endif

call applyFinalFade

Play

echo Advanced Poisson Synthesis complete!

procedure addGrainToOutput
    if point_time + grain_dur > duration
        grain_dur = duration - point_time
    endif
    
    if grain_dur > 0.005
        # Create individual grain as a sound object
        grain_formula$ = "'grain_amp' * sin(2*pi*'grain_freq'*x) * (1 - cos(2*pi*x/'grain_dur'))/2"
        Create Sound from formula: "grain", 1, 0, grain_dur, sample_rate, grain_formula$
        
        # Extract part of gen_output, add grain, replace
        select Sound gen_output
        Extract part: point_time, point_time + grain_dur, "rectangular", 1, "no"
        Rename: "segment"
        
        select Sound segment
        Formula: "self + Sound_grain[]"
        
        # Replace the segment back into gen_output
        select Sound gen_output
        override_start = point_time
        override_end = point_time + grain_dur
        Formula: "if x >= 'override_start' and x < 'override_end' then Sound_segment[col - round('override_start'*'sample_rate')] else self fi"
        
        # Clean up temporary objects
        select Sound grain
        plus Sound segment
        Remove
    endif
endproc

procedure applyFinalFade
    if fade_time > 0
        fade_samples = fade_time * sample_rate
        total_samples = duration * sample_rate
        Formula: "if col < 'fade_samples' then self * (col/'fade_samples') else if col > ('total_samples' - 'fade_samples') then self * (('total_samples' - col)/'fade_samples') else self fi fi"
    endif
endproc