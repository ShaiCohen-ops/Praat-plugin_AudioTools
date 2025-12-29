# ============================================================
# Praat AudioTools - Simple Tier Control.praat
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

form Simple Tier Control
    real Duration 3.0
    real Sampling_frequency 44100
    real Grain_density 20.0
    real Base_frequency 200
    optionmenu Preset: 1
        option Custom
        option Rising Cloud
        option Falling Rain
        option Pulsing Drone
        option Wind Sweep
        option Bell Chimes
        option Ocean Waves
        option Fire Crackle
        option Cosmic Wind
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
endform

echo Creating Simple Tier Control...

# Apply presets
if preset > 1
    if preset = 2
        # Rising Cloud - ascending pitch cloud
        base_frequency = 150
        grain_density = 25
        
    elsif preset = 3
        # Falling Rain - descending pitches
        base_frequency = 400
        grain_density = 15
        
    elsif preset = 4
        # Pulsing Drone - rhythmic amplitude
        base_frequency = 110
        grain_density = 30
        
    elsif preset = 5
        # Wind Sweep - slow pitch sweeps
        base_frequency = 80
        grain_density = 12
        
    elsif preset = 6
        # Bell Chimes - sparse, melodic
        base_frequency = 220
        grain_density = 8
        
    elsif preset = 7
        # Ocean Waves - wave-like motion
        base_frequency = 180
        grain_density = 18
        
    elsif preset = 8
        # Fire Crackle - bright, irregular
        base_frequency = 600
        grain_density = 35
        
    elsif preset = 9
        # Cosmic Wind - wide range, sparse
        base_frequency = 100
        grain_density = 10
    endif
endif

echo Using preset: 'preset'

total_grains = round(duration * grain_density)
formula$ = "0"

Create PitchTier: "simple_pitch", 0, duration
Create IntensityTier: "simple_amp", 0, duration  
Create DurationTier: "simple_dur", 0, duration

points = 20
for i to points
    time = (i-1) * duration / (points-1)
    
    # Preset-specific contour shapes
    if preset = 2
        # Rising Cloud - steady rise
        pitch_value = base_frequency * (0.5 + 1.0 * time/duration)
        amp_value = 0.4 + 0.4 * sin(2*pi*time/duration * 0.5)
        dur_value = 0.04 + 0.08 * (0.5 + 0.5 * cos(2*pi*time/duration))
        
    elsif preset = 3
        # Falling Rain - descending with variation
        pitch_value = base_frequency * (1.5 - 1.0 * time/duration)
        amp_value = 0.3 + 0.5 * randomGauss(0, 0.3)
        dur_value = 0.02 + 0.06 * randomUniform(0, 1)
        
    elsif preset = 4
        # Pulsing Drone - rhythmic pulses
        pitch_value = base_frequency * (0.8 + 0.4 * sin(2*pi*time))
        amp_value = 0.2 + 0.6 * (0.5 + 0.5 * sin(2*pi*time * 2))
        dur_value = 0.05 + 0.1 * (0.5 + 0.5 * cos(2*pi*time))
        
    elsif preset = 5
        # Wind Sweep - slow sweeps
        pitch_value = base_frequency * (0.3 + 1.4 * (0.5 + 0.5 * sin(2*pi*time/duration * 0.3)))
        amp_value = 0.4 + 0.3 * (0.5 + 0.5 * cos(2*pi*time/duration * 0.7))
        dur_value = 0.08 + 0.12 * (0.5 + 0.5 * sin(2*pi*time/duration))
        
    elsif preset = 6
        # Bell Chimes - harmonic series
        pitch_value = base_frequency * (1 + round(randomUniform(0, 4)))
        amp_value = 0.6 + 0.3 * exp(-time * 2)
        dur_value = 0.2 + 0.3 * randomUniform(0, 1)
        
    elsif preset = 7
        # Ocean Waves - wave motion
        pitch_value = base_frequency * (0.7 + 0.6 * sin(2*pi*time/duration * 0.8))
        amp_value = 0.3 + 0.5 * (0.5 + 0.5 * sin(2*pi*time * 0.5))
        dur_value = 0.06 + 0.09 * (0.5 + 0.5 * cos(2*pi*time/duration * 1.2))
        
    elsif preset = 8
        # Fire Crackle - bright and irregular
        pitch_value = base_frequency * (0.5 + 1.5 * randomUniform(0, 1))
        amp_value = 0.2 + 0.7 * randomUniform(0, 1)
        dur_value = 0.01 + 0.04 * randomUniform(0, 1)
        
    elsif preset = 9
        # Cosmic Wind - sparse and wide
        pitch_value = base_frequency * (0.2 + 3.0 * randomUniform(0, 1))
        amp_value = 0.1 + 0.4 * (0.5 + 0.5 * sin(2*pi*time/duration * 0.2))
        dur_value = 0.1 + 0.2 * randomUniform(0, 1)
        
    else
        # Custom - original contours
        pitch_value = base_frequency * (0.7 + 0.6 * sin(2*pi*time/duration))
        amp_value = 0.3 + 0.5 * (0.5 + 0.5 * cos(2*pi*time/duration))
        dur_value = 0.03 + 0.1 * (0.5 + 0.5 * sin(2*pi*time/duration * 2))
    endif
    
    selectObject: "PitchTier simple_pitch"
    Add point: time, pitch_value
    
    selectObject: "IntensityTier simple_amp"
    Add point: time, amp_value
    
    selectObject: "DurationTier simple_dur"
    Add point: time, dur_value
endfor

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.05)
    
    selectObject: "PitchTier simple_pitch"
    grain_freq = Get value at time: grain_time
    
    selectObject: "IntensityTier simple_amp"
    grain_amp = Get value at time: grain_time
    
    selectObject: "DurationTier simple_dur"
    grain_dur = Get value at time: grain_time
    
    if grain_time + grain_dur > duration
        grain_dur = duration - grain_time
    endif
    
    if grain_dur > 0.001
        grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
        grain_formula$ = grain_formula$ + " * sin(pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + ")"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = grain_formula$
        else
            formula$ = formula$ + " + " + grain_formula$
        endif
    endif
endfor

Create Sound from formula: "tier_output", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

selectObject: "PitchTier simple_pitch"
plusObject: "IntensityTier simple_amp" 
plusObject: "DurationTier simple_dur"
Remove

# ====== SPATIAL PROCESSING ======
select Sound tier_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "tier_control_mono"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO WIDE - Static wide image
    Copy: "tier_left"
    left_sound = selected("Sound")
    
    select Sound tier_output
    Copy: "tier_right" 
    right_sound = selected("Sound")
    
    # Add spectral differences for width
    select left_sound
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, 3000, 80
    
    select right_sound
    Formula: "self * 0.8"
    Filter (pass Hann band): 150, 6000, 80
    
    # Combine to stereo
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "tier_control_stereo"
    output_sound = selected("Sound")
    
    # Cleanup
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # ROTATING - Circular panning
    Copy: "tier_left"
    left_sound = selected("Sound")
    
    select Sound tier_output
    Copy: "tier_right"
    right_sound = selected("Sound")
    
    # Apply rotation
    rotation_rate = 0.1
    select left_sound
    Formula: "self * (0.6 + 0.4 * cos(2*pi*rotation_rate*x))"
    
    select right_sound
    Formula: "self * (0.6 + 0.4 * sin(2*pi*rotation_rate*x))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "tier_control_rotating"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL - Simple binaural simulation
    Copy: "tier_left"
    left_sound = selected("Sound")
    
    select Sound tier_output
    Copy: "tier_right"
    right_sound = selected("Sound")
    
    # Left channel: fuller, bass emphasis
    select left_sound
    Filter (pass Hann band): 50, 2500, 60
    
    # Right channel: brighter
    select right_sound
    Filter (pass Hann band): 200, 5000, 60
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "tier_control_binaural"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Tier Control complete!
echo Preset: 'preset'
echo Spatial mode: 'spatial_mode'