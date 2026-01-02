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
form Stochastic Synthesis with Spatial Effects
    real Duration 2.0
    real Sampling_frequency 44100
    real Base_frequency 150
    real Frequency_variance 300
    real Grain_duration 0.03
    real Density_(grains_per_second) 40
    real Amplitude_variance 0.4
    optionmenu Preset: 1
        option Custom
        option Cloud Texture
        option Rain Drops
        option Buzzing Insects
        option Wind Chimes
        option Digital Static
        option Underwater Bubbles
        option Fire Crackle
        option Metallic Rain
        option Cosmic Dust
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
endform

# Apply presets
if preset > 1
    if preset = 2
        # Cloud Texture - soft, evolving cloud
        base_frequency = 200
        frequency_variance = 150
        grain_duration = 0.05
        density = 30
        amplitude_variance = 0.3
        
    elsif preset = 3
        # Rain Drops - sparse, percussive
        base_frequency = 80
        frequency_variance = 400
        grain_duration = 0.01
        density = 15
        amplitude_variance = 0.7
        
    elsif preset = 4
        # Buzzing Insects - dense, high-frequency
        base_frequency = 1200
        frequency_variance = 800
        grain_duration = 0.02
        density = 60
        amplitude_variance = 0.4
        
    elsif preset = 5
        # Wind Chimes - melodic, sparse
        base_frequency = 440
        frequency_variance = 800
        grain_duration = 0.2
        density = 4
        amplitude_variance = 0.6
        
    elsif preset = 6
        # Digital Static - harsh, noisy
        base_frequency = 800
        frequency_variance = 2000
        grain_duration = 0.005
        density = 100
        amplitude_variance = 0.8
        
    elsif preset = 7
        # Underwater Bubbles - low, resonant
        base_frequency = 60
        frequency_variance = 100
        grain_duration = 0.08
        density = 8
        amplitude_variance = 0.5
        
    elsif preset = 8
        # Fire Crackle - irregular, bright
        base_frequency = 500
        frequency_variance = 1500
        grain_duration = 0.015
        density = 20
        amplitude_variance = 0.9
        
    elsif preset = 9
        # Metallic Rain - metallic, ringing
        base_frequency = 800
        frequency_variance = 1200
        grain_duration = 0.1
        density = 15
        amplitude_variance = 0.4
        
    elsif preset = 10
        # Cosmic Dust - very sparse, wide range
        base_frequency = 50
        frequency_variance = 3000
        grain_duration = 0.15
        density = 3
        amplitude_variance = 0.8
    endif
endif

echo Using preset: 'preset'
echo Parameters:
echo - Base frequency: 'base_frequency' Hz
echo - Frequency variance: 'frequency_variance' Hz
echo - Grain duration: 'grain_duration' s
echo - Density: 'density' grains/s
echo - Amplitude variance: 'amplitude_variance'

# Create empty sound first
Create Sound from formula: "gen_output", 1, 0, duration, sampling_frequency, "0"
gen_output = selected("Sound")

total_grains = round(density * duration)
echo Generating 'total_grains' grains...

for i to total_grains
    # Random parameters for each grain
    grain_freq = base_frequency + frequency_variance * (randomUniform(0,1) - 0.5)
    grain_amp = 0.5 + amplitude_variance * (randomUniform(0,1) - 0.5)
    grain_start = randomUniform(0, duration - grain_duration)
    
    # Create individual grain
    grain = Create Sound from formula: "grain", 1, 0, grain_duration, sampling_frequency,
    ... string$(grain_amp) + " * sin(2*pi*" + string$(grain_freq) + "*x)"
    
    # Add grain to main sound at random position
    select gen_output
    start_sample = round(grain_start * sampling_frequency) + 1
    end_sample = start_sample + round(grain_duration * sampling_frequency) - 1
    
    # Use Formula to add the grain
    select grain
    Extract part: 0, grain_duration, "rectangular", 1, "no"
    grain_part = selected("Sound")
    
    select gen_output
    Formula: "if col >= " + string$(start_sample) + " and col <= " + string$(end_sample) + 
    ... " then self + object['grain_part', col - " + string$(start_sample - 1) + "] else self fi"
    
    # Clean up
    select grain
    plus grain_part
    Remove
    
    if i mod 10 = 0
        echo Added grain 'i'/'total_grains'
    endif
endfor

select gen_output
Scale peak: 0.9
echo Granular synthesis complete!

# ====== SPATIAL PROCESSING ======

select gen_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "stochastic_synthesis"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO WIDE - Static wide image
    Copy: "stochastic_left"
    left_sound = selected("Sound")
    
    select gen_output
    Copy: "stochastic_right" 
    right_sound = selected("Sound")
    
    # Add spectral differences for width
    select left_sound
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, 4000, 100
    
    select right_sound
    Formula: "self * 0.8"
    Filter (pass Hann band): 200, 8000, 100
    
    # Combine to stereo
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "stochastic_synthesis"
    output_sound = selected("Sound")
    
    # Cleanup
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # ROTATING - Circular panning
    Copy: "stochastic_left"
    left_sound = selected("Sound")
    
    select gen_output
    Copy: "stochastic_right"
    right_sound = selected("Sound")
    
    # Apply rotation
    rotation_rate = 0.15
    select left_sound
    Formula: "self * (0.6 + 0.4 * cos(2*pi*rotation_rate*x))"
    
    select right_sound
    Formula: "self * (0.6 + 0.4 * sin(2*pi*rotation_rate*x))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "stochastic_synthesis"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL - Simple binaural simulation
    Copy: "stochastic_left"
    left_sound = selected("Sound")
    
    select gen_output
    Copy: "stochastic_right"
    right_sound = selected("Sound")
    
    # Left channel: fuller, bass emphasis
    select left_sound
    Filter (pass Hann band): 50, 3000, 80
    
    # Right channel: brighter with different spectrum
    select right_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 200, 6000, 80
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "stochastic_synthesis"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Spatial processing complete!
echo Final sound: 'selected$()'


