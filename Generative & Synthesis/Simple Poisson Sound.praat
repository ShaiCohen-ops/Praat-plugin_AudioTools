# ============================================================
# Praat AudioTools - Simple Poisson Sound.praat
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

form Simple Poisson Sound
    real Duration 4.0
    real Sampling_frequency 44100
    real Points_per_second 8.0
    real Base_frequency 200
    optionmenu Preset: 1
        option Custom
        option Gentle Rain
        option Digital Glitches
        option Heartbeat
        option Fireworks
        option Clock Ticks
        option Geiger Counter
        option Bubble Pop
        option Star Twinkle
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Random Pan
        option Binaural
endform

echo Creating Poisson process...

# Apply presets
if preset > 1
    if preset = 2
        # Gentle Rain - soft, sparse events
        points_per_second = 4
        base_frequency = 180
        
    elsif preset = 3
        # Digital Glitches - fast, bright events
        points_per_second = 15
        base_frequency = 800
        
    elsif preset = 4
        # Heartbeat - rhythmic pulse
        points_per_second = 2
        base_frequency = 80
        
    elsif preset = 5
        # Fireworks - explosive, bright events
        points_per_second = 1.5
        base_frequency = 300
        
    elsif preset = 6
        # Clock Ticks - regular-ish timing
        points_per_second = 2
        base_frequency = 120
        
    elsif preset = 7
        # Geiger Counter - rapid, urgent
        points_per_second = 20
        base_frequency = 400
        
    elsif preset = 8
        # Bubble Pop - low, resonant
        points_per_second = 6
        base_frequency = 90
        
    elsif preset = 9
        # Star Twinkle - high, sparse
        points_per_second = 3
        base_frequency = 1200
    endif
endif

echo Using preset: 'preset'

Create Poisson process: "points", 0, duration, points_per_second

selectObject: "PointProcess points"
numberOfPoints = Get number of points
echo Found 'numberOfPoints' Poisson points

formula$ = "0"

for point to numberOfPoints
    selectObject: "PointProcess points"
    pointTime = Get time from index: point
    
    # Preset-specific parameters
    if preset = 2
        # Gentle Rain
        freq = base_frequency * (0.7 + 0.6 * randomUniform(0,1))
        dur = 0.15
        amp = 0.4 + 0.3 * randomUniform(0,1)
        
    elsif preset = 3
        # Digital Glitches
        freq = base_frequency * (0.3 + 1.4 * randomUniform(0,1))
        dur = 0.03
        amp = 0.6 + 0.3 * randomUniform(0,1)
        
    elsif preset = 4
        # Heartbeat
        freq = base_frequency * (0.9 + 0.2 * randomUniform(0,1))
        dur = 0.25
        amp = 0.8
        
    elsif preset = 5
        # Fireworks
        freq = base_frequency * (0.5 + 1.5 * randomUniform(0,1))
        dur = 0.4
        amp = 0.9
        
    elsif preset = 6
        # Clock Ticks
        freq = base_frequency * (0.95 + 0.1 * randomUniform(0,1))
        dur = 0.05
        amp = 0.5
        
    elsif preset = 7
        # Geiger Counter
        freq = base_frequency * (0.8 + 0.4 * randomUniform(0,1))
        dur = 0.02
        amp = 0.7
        
    elsif preset = 8
        # Bubble Pop
        freq = base_frequency * (0.6 + 0.8 * randomUniform(0,1))
        dur = 0.2
        amp = 0.5 + 0.3 * randomUniform(0,1)
        
    elsif preset = 9
        # Star Twinkle
        freq = base_frequency * (0.5 + 1.0 * randomUniform(0,1))
        dur = 0.08
        amp = 0.3 + 0.4 * randomUniform(0,1)
        
    else
        # Custom
        freq = base_frequency * (0.8 + 0.4 * randomUniform(0,1))
        dur = 0.1
        amp = 0.7
    endif
    
    if pointTime + dur <= duration
        event_formula$ = "if x >= " + string$(pointTime) + " and x < " + string$(pointTime + dur)
        event_formula$ = event_formula$ + " then " + string$(amp)
        event_formula$ = event_formula$ + " * sin(2*pi*" + string$(freq) + "*x)"
        event_formula$ = event_formula$ + " * sin(pi*(x-" + string$(pointTime) + ")/" + string$(dur) + ")"
        event_formula$ = event_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = event_formula$
        else
            formula$ = formula$ + " + " + event_formula$
        endif
    endif
endfor

Create Sound from formula: "poisson_output", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

selectObject: "PointProcess points"
Remove

# ====== SPATIAL PROCESSING ======
select Sound poisson_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "poisson_mono"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO WIDE - Static wide image
    Copy: "poisson_left"
    left_sound = selected("Sound")
    
    select Sound poisson_output
    Copy: "poisson_right" 
    right_sound = selected("Sound")
    
    # Add spectral differences for width
    select left_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 0, 3500, 100
    
    select right_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 100, 7000, 100
    
    # Combine to stereo
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "poisson_stereo"
    output_sound = selected("Sound")
    
    # Cleanup
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # RANDOM PAN - Each event randomly panned
    Copy: "poisson_left"
    left_sound = selected("Sound")
    
    select Sound poisson_output
    Copy: "poisson_right"
    right_sound = selected("Sound")
    
    # Apply random panning to each event
    select left_sound
    Formula: "self * (0.3 + 0.5 * sin(2*pi*x*2.7))"
    
    select right_sound
    Formula: "self * (0.3 + 0.5 * cos(2*pi*x*2.7))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "poisson_random_pan"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL - Simple binaural simulation
    Copy: "poisson_left"
    left_sound = selected("Sound")
    
    select Sound poisson_output
    Copy: "poisson_right"
    right_sound = selected("Sound")
    
    # Left channel: fuller, bass emphasis
    select left_sound
    Filter (pass Hann band): 50, 3000, 80
    
    # Right channel: brighter with slight spectral shift
    select right_sound
    Formula: "self * (0.8 + 0.2 * sin(2*pi*x*0.5))"
    Filter (pass Hann band): 150, 5000, 80
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "poisson_binaural"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Poisson Sound complete!
echo Preset: 'preset'
echo Spatial mode: 'spatial_mode'
echo Total events: 'numberOfPoints'