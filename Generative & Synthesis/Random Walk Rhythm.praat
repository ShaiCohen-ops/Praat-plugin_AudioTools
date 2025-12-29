# ============================================================
# Praat AudioTools - Random Walk Rhythm.praat
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

form Random Walk Rhythm
    real Duration 6.0
    real Sampling_frequency 44100
    real Tempo 120
    integer Steps_per_beat 4
    real Base_frequency 180
    real Frequency_step 50
    real Probability_up 0.4
    real Probability_down 0.4
    optionmenu Preset: 1
        option Custom
        option Gentle Bounce
        option Chaotic Dance
        option Steady Climb
        option Falling Steps
        option Pulsing Heart
        option Nervous Ticks
        option Ocean Waves
        option Machine Pulse
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Ping-Pong
        option Rotating Walk
        option Binaural Rhythm
endform

echo Creating Random Walk Rhythm...

if preset > 1
    if preset = 2
        tempo = 90
        steps_per_beat = 2
        base_frequency = 150
        frequency_step = 30
        probability_up = 0.5
        probability_down = 0.3
        
    elsif preset = 3
        tempo = 160
        steps_per_beat = 8
        base_frequency = 200
        frequency_step = 80
        probability_up = 0.4
        probability_down = 0.4
        
    elsif preset = 4
        tempo = 100
        steps_per_beat = 4
        base_frequency = 120
        frequency_step = 40
        probability_up = 0.6
        probability_down = 0.2
        
    elsif preset = 5
        tempo = 80
        steps_per_beat = 4
        base_frequency = 200
        frequency_step = 60
        probability_up = 0.3
        probability_down = 0.5
        
    elsif preset = 6
        tempo = 60
        steps_per_beat = 2
        base_frequency = 100
        frequency_step = 20
        probability_up = 0.4
        probability_down = 0.4
        
    elsif preset = 7
        tempo = 140
        steps_per_beat = 16
        base_frequency = 180
        frequency_step = 100
        probability_up = 0.45
        probability_down = 0.45
        
    elsif preset = 8
        tempo = 70
        steps_per_beat = 3
        base_frequency = 130
        frequency_step = 25
        probability_up = 0.5
        probability_down = 0.3
        
    elsif preset = 9
        tempo = 110
        steps_per_beat = 4
        base_frequency = 160
        frequency_step = 35
        probability_up = 0.4
        probability_down = 0.4
    endif
endif

echo Using preset: 'preset'

beats_per_second = tempo / 60
beat_duration = 1 / beats_per_second
step_duration = beat_duration / steps_per_beat
total_steps = round(duration / step_duration)

current_freq = base_frequency
formula$ = "0"

for step to total_steps
    step_time = (step-1) * step_duration
    
    if step_time < duration
        event_duration = step_duration * 0.8
        if step_time + event_duration > duration
            event_duration = duration - step_time
        endif
        
        if event_duration > 0.001
            event_formula$ = "if x >= " + string$(step_time) + " and x < " + string$(step_time + event_duration)
            event_formula$ = event_formula$ + " then 0.8 * sin(2*pi*" + string$(current_freq) + "*x)"
            event_formula$ = event_formula$ + " * exp(-15*(x-" + string$(step_time) + ")/" + string$(event_duration) + ")"
            event_formula$ = event_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = event_formula$
            else
                formula$ = formula$ + " + " + event_formula$
            endif
        endif
        
        r = randomUniform(0,1)
        if r < probability_up
            current_freq = current_freq + frequency_step
        elsif r < probability_up + probability_down
            current_freq = current_freq - frequency_step
        endif
        
        current_freq = max(80, min(1500, current_freq))
    endif
    
    if step mod 50 = 0
        echo Processed 'step'/'total_steps' steps
    endif
endfor

Create Sound from formula: "rhythm_output", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

select Sound rhythm_output

if spatial_mode = 1
    Rename: "random_walk_mono"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    Copy: "rhythm_left"
    left_sound = selected("Sound")
    
    select Sound rhythm_output
    Copy: "rhythm_right" 
    right_sound = selected("Sound")
    
    select left_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 0, 3000, 100
    
    select right_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 200, 5000, 100
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "random_walk_pingpong"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    Copy: "rhythm_left"
    left_sound = selected("Sound")
    
    select Sound rhythm_output
    Copy: "rhythm_right"
    right_sound = selected("Sound")
    
    rotation_rate = tempo / 120
    select left_sound
    Formula: "self * (0.5 + 0.4 * cos(2*pi*rotation_rate*x))"
    
    select right_sound
    Formula: "self * (0.5 + 0.4 * sin(2*pi*rotation_rate*x))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "random_walk_rotating"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    Copy: "rhythm_left"
    left_sound = selected("Sound")
    
    select Sound rhythm_output
    Copy: "rhythm_right"
    right_sound = selected("Sound")
    
    select left_sound
    Filter (pass Hann band): 80, 2500, 80
    Formula: "self * (0.8 + 0.1 * sin(2*pi*x*0.3))"
    
    select right_sound
    Filter (pass Hann band): 120, 4000, 80
    Formula: "self * (0.7 + 0.2 * cos(2*pi*x*0.4))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "random_walk_binaural"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Random Walk Rhythm complete!
echo Preset: 'preset'
echo Spatial mode: 'spatial_mode'
echo Tempo: 'tempo' BPM
echo Total steps: 'total_steps'