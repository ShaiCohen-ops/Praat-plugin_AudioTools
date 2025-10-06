# ============================================================
# Praat AudioTools - Gravitational_Lens_ Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reverberation or diffusion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Gravitational Lens Stereo
    comment This script simulates gravitational lensing effects on delays
    positive tail_duration_seconds 4
    natural mass_points 12
    natural rays_per_mass 8
    positive space_curvature 0.8
    positive mass_strength_mean 1.2
    positive mass_strength_stddev 0.5
    positive ray_delay_start 0.05
    positive ray_delay_increment 0.06
    positive lensing_amplitude 0.16
    positive time_dilation_factor 0.15
    positive fadeout_duration 1.0
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

original_sound$ = selected$("Sound")
select Sound 'original_sound$'
sampling_rate = Get sample rate
channels = Get number of channels

# Create silent tail
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_seconds, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_seconds, sampling_rate, "0"
endif

# Concatenate
select Sound 'original_sound$'
plus Sound silent_tail
Concatenate
Rename: "extended_sound"

select Sound extended_sound

if channels = 2
    Extract one channel: 1
    Rename: "left_channel"
    select Sound extended_sound
    Extract one channel: 2
    Rename: "right_channel"
    
    # Process left
    select Sound left_channel
    Copy: "reverb_copy_left"
    
    for mass from 1 to mass_points
        mass_position = randomUniform(0.03, 0.9)
        mass_strength = randomGauss(mass_strength_mean, mass_strength_stddev)
        
        for ray from 1 to rays_per_mass
            straight_delay = ray_delay_start + ray * ray_delay_increment
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.005)
            curved_delay = straight_delay + bending * space_curvature
            lensing_amp = lensing_amplitude / (1 + bending)
            time_dilation = sqrt(1 - mass_strength * time_dilation_factor)
            Formula: "self + lensing_amp * self(x - curved_delay * time_dilation)"
        endfor
    endfor
    
    # Process right (slightly different)
    select Sound right_channel
    Copy: "reverb_copy_right"
    
    for mass from 1 to mass_points
        mass_position = randomUniform(0.04, 0.85)
        mass_strength = randomGauss(1.1, 0.6)
        
        for ray from 1 to rays_per_mass
            straight_delay = 0.06 + ray * 0.055
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.006)
            curved_delay = straight_delay + bending * 0.75
            lensing_amp = 0.14 / (1 + bending)
            time_dilation = sqrt(1 - mass_strength * 0.18)
            Formula: "self + lensing_amp * self(x - curved_delay * time_dilation)"
        endfor
    endfor
    
    # Combine
    select Sound reverb_copy_left
    plus Sound reverb_copy_right
    Combine to stereo
    Rename: original_sound$ + "_gravitational"
    
    removeObject: "Sound reverb_copy_left", "Sound reverb_copy_right"
    
else
    Copy: "reverb_copy"
    
    for mass from 1 to mass_points
        mass_position = randomUniform(0.03, 0.9)
        mass_strength = randomGauss(mass_strength_mean, mass_strength_stddev)
        
        for ray from 1 to rays_per_mass
            straight_delay = ray_delay_start + ray * ray_delay_increment
            distance_to_mass = abs(straight_delay - mass_position)
            bending = mass_strength / (distance_to_mass + 0.005)
            curved_delay = straight_delay + bending * space_curvature
            lensing_amp = lensing_amplitude / (1 + bending)
            time_dilation = sqrt(1 - mass_strength * time_dilation_factor)
            Formula: "self + lensing_amp * self(x - curved_delay * time_dilation)"
        endfor
    endfor
    
    Convert to stereo
    Rename: original_sound$ + "_gravitational"
    
    removeObject: "Sound reverb_copy"
endif

# Apply fadeout
select Sound 'original_sound$'_gravitational
total_duration = Get total duration
fade_start = total_duration - fadeout_duration
Formula: "if x > fade_start then self * (0.5 + 0.5 * cos(pi * (x - fade_start) / 'fadeout_duration')) else self fi"

# Cleanup
select Sound silent_tail
plus Sound extended_sound
if channels = 2
    plus Sound left_channel
    plus Sound right_channel
endif
Remove

select Sound 'original_sound$'_gravitational

if play_after_processing
    Play
endif