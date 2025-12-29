# ============================================================
# Praat AudioTools - Simple Grain Mass.praat
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

form Simple Grain Mass
    real Duration 6.0
    real Sampling_frequency 44100
    real Grain_density 25.0
    real Base_frequency 180
    optionmenu Preset: 1
        option Custom
        option Dense Cloud
        option Sparse Mist
        option Metallic Shimmer
        option Deep Rumble
        option Wind Texture
        option Glass Fragments
        option Organic Swarm
        option Digital Snow
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Rotating Cloud
        option Binaural Space
endform

echo Creating Simple Grain Mass...

# Apply presets
if preset > 1
    if preset = 2
        # Dense Cloud - thick, continuous texture
        grain_density = 50
        base_frequency = 200
        
    elsif preset = 3
        # Sparse Mist - delicate, airy
        grain_density = 8
        base_frequency = 300
        
    elsif preset = 4
        # Metallic Shimmer - bright, ringing
        grain_density = 35
        base_frequency = 600
        
    elsif preset = 5
        # Deep Rumble - low frequency mass
        grain_density = 20
        base_frequency = 60
        
    elsif preset = 6
        # Wind Texture - breathy, evolving
        grain_density = 15
        base_frequency = 120
        
    elsif preset = 7
        # Glass Fragments - sharp, crystalline
        grain_density = 40
        base_frequency = 800
        
    elsif preset = 8
        # Organic Swarm - living, moving
        grain_density = 30
        base_frequency = 250
        
    elsif preset = 9
        # Digital Snow - noisy, granular
        grain_density = 60
        base_frequency = 400
    endif
endif

echo Using preset: 'preset'

total_grains = round(duration * grain_density)
formula$ = "0"

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.1)
    
    # Preset-specific grain parameters
    if preset = 2
        # Dense Cloud - uniform, dense
        grain_freq = base_frequency * (0.7 + 0.6 * randomUniform(0,1))
        grain_dur = 0.03 + 0.06 * randomUniform(0,1)
        grain_amp = 0.5 + 0.3 * randomUniform(0,1)
        
    elsif preset = 3
        # Sparse Mist - long, delicate
        grain_freq = base_frequency * (0.8 + 0.4 * randomUniform(0,1))
        grain_dur = 0.1 + 0.2 * randomUniform(0,1)
        grain_amp = 0.3 + 0.2 * randomUniform(0,1)
        
    elsif preset = 4
        # Metallic Shimmer - bright, short
        grain_freq = base_frequency * (0.4 + 1.2 * randomUniform(0,1))
        grain_dur = 0.02 + 0.04 * randomUniform(0,1)
        grain_amp = 0.6 + 0.3 * randomUniform(0,1)
        
    elsif preset = 5
        # Deep Rumble - low, long
        grain_freq = base_frequency * (0.5 + 1.0 * randomUniform(0,1))
        grain_dur = 0.08 + 0.15 * randomUniform(0,1)
        grain_amp = 0.8 + 0.1 * randomUniform(0,1)
        
    elsif preset = 6
        # Wind Texture - breathy, varied
        grain_freq = base_frequency * (0.6 + 0.8 * randomUniform(0,1))
        grain_dur = 0.05 + 0.12 * randomUniform(0,1)
        grain_amp = 0.4 + 0.4 * randomUniform(0,1)
        
    elsif preset = 7
        # Glass Fragments - sharp, bright
        grain_freq = base_frequency * (0.3 + 1.4 * randomUniform(0,1))
        grain_dur = 0.01 + 0.03 * randomUniform(0,1)
        grain_amp = 0.7 + 0.2 * randomUniform(0,1)
        
    elsif preset = 8
        # Organic Swarm - natural variation
        grain_freq = base_frequency * (0.5 + 1.0 * randomUniform(0,1))
        grain_dur = 0.04 + 0.09 * randomUniform(0,1)
        grain_amp = 0.5 + 0.4 * randomUniform(0,1)
        
    elsif preset = 9
        # Digital Snow - noisy, dense
        grain_freq = base_frequency * (0.2 + 1.6 * randomUniform(0,1))
        grain_dur = 0.02 + 0.05 * randomUniform(0,1)
        grain_amp = 0.4 + 0.5 * randomUniform(0,1)
        
    else
        # Custom - original parameters
        grain_freq = base_frequency * (0.5 + randomUniform(0,1))
        grain_dur = 0.05 + 0.1 * randomUniform(0,1)
        grain_amp = 0.7
    endif
    
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
    
    if grain mod 100 = 0
        echo Generated 'grain'/'total_grains' grains
    endif
endfor

Create Sound from formula: "grain_output", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

# ====== SPATIAL PROCESSING ======
select Sound grain_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "grain_mass_mono"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO WIDE - Static wide image
    Copy: "grain_left"
    left_sound = selected("Sound")
    
    select Sound grain_output
    Copy: "grain_right" 
    right_sound = selected("Sound")
    
    # Add spectral differences for width
    select left_sound
    Formula: "self * 0.85"
    Filter (pass Hann band): 0, 4000, 120
    
    select right_sound
    Formula: "self * 0.85"
    Filter (pass Hann band): 100, 8000, 120
    
    # Combine to stereo
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "grain_mass_stereo"
    output_sound = selected("Sound")
    
    # Cleanup
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # ROTATING CLOUD - Moving grain mass
    Copy: "grain_left"
    left_sound = selected("Sound")
    
    select Sound grain_output
    Copy: "grain_right"
    right_sound = selected("Sound")
    
    # Apply slow rotation to entire mass
    rotation_rate = 0.08
    select left_sound
    Formula: "self * (0.5 + 0.5 * cos(2*pi*rotation_rate*x))"
    
    select right_sound
    Formula: "self * (0.5 + 0.5 * sin(2*pi*rotation_rate*x))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "grain_mass_rotating"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL SPACE - 3D grain field
    Copy: "grain_left"
    left_sound = selected("Sound")
    
    select Sound grain_output
    Copy: "grain_right"
    right_sound = selected("Sound")
    
    # Left channel: warmer, centered
    select left_sound
    Filter (pass Hann band): 50, 3500, 100
    Formula: "self * (0.8 + 0.2 * sin(2*pi*x*0.3))"
    
    # Right channel: brighter, more diffuse
    select right_sound
    Filter (pass Hann band): 150, 6000, 100
    Formula: "self * (0.7 + 0.3 * cos(2*pi*x*0.4))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "grain_mass_binaural"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Grain Mass complete!
echo Preset: 'preset'
echo Spatial mode: 'spatial_mode'
echo Total grains: 'total_grains'