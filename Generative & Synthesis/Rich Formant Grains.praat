# ============================================================
# Praat AudioTools - Rich Formant Grains.praat
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

form Rich Formant Grains
    real Duration 5.0
    real Sampling_frequency 44100
    real Grain_density 35.0
    real Base_frequency 120
    optionmenu Preset: 1
        option Custom
        option Vowel Cloud
        option Whisper Choir
        option Robotic Speech
        option Alien Language
        option Gregorian Chant
        option Baby Babble
        option Synthetic Singing
        option Ghost Voices
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Choir
        option Rotating Voices
        option Binaural Whisper
endform

echo Creating Rich Formant Grains...

if preset > 1
    if preset = 2
        grain_density = 25
        base_frequency = 110
    elsif preset = 3
        grain_density = 15
        base_frequency = 180
    elsif preset = 4
        grain_density = 40
        base_frequency = 80
    elsif preset = 5
        grain_density = 30
        base_frequency = 140
    elsif preset = 6
        grain_density = 20
        base_frequency = 90
    elsif preset = 7
        grain_density = 45
        base_frequency = 250
    elsif preset = 8
        grain_density = 28
        base_frequency = 130
    elsif preset = 9
        grain_density = 12
        base_frequency = 160
    endif
endif

echo Using preset: 'preset'

total_grains = round(duration * grain_density)
formula$ = "0"

for grain to total_grains
    grain_time = randomUniform(0, duration - 0.15)
    
    if preset = 2
        r = randomUniform(0,1)
        if r < 0.2
            f1 = 730
            f2 = 1090
            f3 = 2440
        elsif r < 0.4
            f1 = 270
            f2 = 2290
            f3 = 3010
        elsif r < 0.6
            f1 = 300
            f2 = 870
            f3 = 2240
        elsif r < 0.8
            f1 = 530
            f2 = 1840
            f3 = 2480
        else
            f1 = 570
            f2 = 840
            f3 = 2410
        endif
        grain_dur = 0.05 + 0.10 * randomUniform(0,1)
        grain_amp = 0.6 + 0.3 * randomUniform(0,1)
        
    elsif preset = 3
        r = randomUniform(0,1)
        if r < 0.3
            f1 = 730
            f2 = 1090
            f3 = 2440
        elsif r < 0.6
            f1 = 300
            f2 = 870
            f3 = 2240
        else
            f1 = 570
            f2 = 840
            f3 = 2410
        endif
        grain_dur = 0.08 + 0.15 * randomUniform(0,1)
        grain_amp = 0.4 + 0.2 * randomUniform(0,1)
        
    elsif preset = 4
        r = randomUniform(0,1)
        if r < 0.25
            f1 = 270
            f2 = 2290
            f3 = 3010
        elsif r < 0.5
            f1 = 530
            f2 = 1840
            f3 = 2480
        elsif r < 0.75
            f1 = 730
            f2 = 1090
            f3 = 2440
        else
            f1 = 300
            f2 = 870
            f3 = 2240
        endif
        grain_dur = 0.03 + 0.05 * randomUniform(0,1)
        grain_amp = 0.8 + 0.1 * randomUniform(0,1)
        
    elsif preset = 5
        r = randomUniform(0,1)
        if r < 0.2
            f1 = 200
            f2 = 3000
            f3 = 4000
        elsif r < 0.4
            f1 = 800
            f2 = 1200
            f3 = 2800
        elsif r < 0.6
            f1 = 150
            f2 = 500
            f3 = 3500
        elsif r < 0.8
            f1 = 600
            f2 = 2500
            f3 = 3200
        else
            f1 = 400
            f2 = 600
            f3 = 2600
        endif
        grain_dur = 0.04 + 0.08 * randomUniform(0,1)
        grain_amp = 0.7 + 0.2 * randomUniform(0,1)
        
    elsif preset = 6
        r = randomUniform(0,1)
        if r < 0.4
            f1 = 300
            f2 = 870
            f3 = 2240
        elsif r < 0.7
            f1 = 570
            f2 = 840
            f3 = 2410
        else
            f1 = 730
            f2 = 1090
            f3 = 2440
        endif
        grain_dur = 0.10 + 0.20 * randomUniform(0,1)
        grain_amp = 0.5 + 0.3 * randomUniform(0,1)
        
    elsif preset = 7
        r = randomUniform(0,1)
        if r < 0.3
            f1 = 800
            f2 = 1200
            f3 = 2600
        elsif r < 0.6
            f1 = 400
            f2 = 2500
            f3 = 3200
        else
            f1 = 350
            f2 = 1000
            f3 = 2400
        endif
        grain_dur = 0.02 + 0.04 * randomUniform(0,1)
        grain_amp = 0.5 + 0.4 * randomUniform(0,1)
        
    elsif preset = 8
        r = randomUniform(0,1)
        if r < 0.25
            f1 = 530
            f2 = 1840
            f3 = 2480
        elsif r < 0.5
            f1 = 730
            f2 = 1090
            f3 = 2440
        elsif r < 0.75
            f1 = 570
            f2 = 840
            f3 = 2410
        else
            f1 = 270
            f2 = 2290
            f3 = 3010
        endif
        grain_dur = 0.06 + 0.12 * randomUniform(0,1)
        grain_amp = 0.7 + 0.2 * randomUniform(0,1)
        
    elsif preset = 9
        r = randomUniform(0,1)
        if r < 0.5
            f1 = 300
            f2 = 870
            f3 = 2240
        else
            f1 = 270
            f2 = 2290
            f3 = 3010
        endif
        grain_dur = 0.12 + 0.25 * randomUniform(0,1)
        grain_amp = 0.3 + 0.2 * randomUniform(0,1)
        
    else
        r = randomUniform(0,1)
        if r < 0.25
            f1 = 730
            f2 = 1090
            f3 = 2440
        elsif r < 0.45
            f1 = 270
            f2 = 2290
            f3 = 3010
        elsif r < 0.6
            f1 = 300
            f2 = 870
            f3 = 2240
        elsif r < 0.75
            f1 = 530
            f2 = 1840
            f3 = 2480
        else
            f1 = 570
            f2 = 840
            f3 = 2410
        endif
        grain_dur = 0.04 + 0.08 * randomUniform(0,1)
        grain_amp = 0.7 + 0.2 * randomUniform(0,1)
    endif
    
    pitch_variation = 0.9 + 0.2 * randomUniform(0,1)
    
    if grain_time + grain_dur > duration
        grain_dur = duration - grain_time
    endif
    
    if grain_dur > 0.001
        grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * (0.3*sin(2*pi*" + string$(base_frequency) + "*" + string$(pitch_variation) + "*x) + "
        grain_formula$ = grain_formula$ + "0.5*sin(2*pi*" + string$(f1) + "*x) + "
        grain_formula$ = grain_formula$ + "0.4*sin(2*pi*" + string$(f2) + "*x) + "
        grain_formula$ = grain_formula$ + "0.3*sin(2*pi*" + string$(f3) + "*x))"
        grain_formula$ = grain_formula$ + " * sin(pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + ")"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = grain_formula$
        else
            formula$ = formula$ + " + " + grain_formula$
        endif
    endif
endfor

Create Sound from formula: "formant_output", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

select Sound formant_output

if spatial_mode = 1
    Rename: "formant_grains_mono"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    Copy: "formant_left"
    left_sound = selected("Sound")
    
    select Sound formant_output
    Copy: "formant_right" 
    right_sound = selected("Sound")
    
    select left_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 0, 2500, 120
    
    select right_sound
    Formula: "self * 0.9"
    Filter (pass Hann band): 150, 4000, 120
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "formant_grains_choir"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    Copy: "formant_left"
    left_sound = selected("Sound")
    
    select Sound formant_output
    Copy: "formant_right"
    right_sound = selected("Sound")
    
    rotation_rate = 0.12
    select left_sound
    Formula: "self * (0.5 + 0.4 * cos(2*pi*rotation_rate*x))"
    
    select right_sound
    Formula: "self * (0.5 + 0.4 * sin(2*pi*rotation_rate*x))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "formant_grains_rotating"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    Copy: "formant_left"
    left_sound = selected("Sound")
    
    select Sound formant_output
    Copy: "formant_right"
    right_sound = selected("Sound")
    
    select left_sound
    Filter (pass Hann band): 100, 3000, 80
    Formula: "self * (0.8 + 0.1 * sin(2*pi*x*0.2))"
    
    select right_sound
    Filter (pass Hann band): 80, 3500, 80
    Formula: "self * (0.7 + 0.2 * cos(2*pi*x*0.25))"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "formant_grains_binaural"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

select output_sound
Play

echo Rich Formant Grains complete!
echo Preset: 'preset'
echo Spatial mode: 'spatial_mode'
echo Total grains: 'total_grains'