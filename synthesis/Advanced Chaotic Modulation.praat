# ============================================================
# Praat AudioTools - Advanced Chaotic Modulation.praat
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

form Advanced Chaotic Modulation System
    positive Duration_(sec) 12
    positive Base_frequency_(Hz) 150
    positive Number_of_layers 3
    real Chaos_intensity 0.7
    real Modulation_rate 2.0
    boolean Use_logistic_freq 1
    boolean Use_lorenz_amp 1
    boolean Use_henon_filter 1
    boolean Randomize_parameters 1
    positive Fade_time_(sec) 2
    optionmenu Synthesis_mode: 1
        option Chaotic Modulation
        option Logistic Frequencies
        option Lorenz Amplitudes
        option Hénon Filtering
        option Combined Chaos
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

Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"

if synthesis_mode = 1
    for layer from 1 to number_of_layers
        if randomize_parameters
            base_freq = base_frequency * (0.7 + 0.6 * randomUniform(0, 1))
            chaos_strength = chaos_intensity * (0.8 + 0.4 * randomUniform(0, 1))
        else
            base_freq = base_frequency
            chaos_strength = chaos_intensity
        endif
        
        layer_amp = 0.6 / number_of_layers
        
        formula$ = "'layer_amp' * sin(2*pi*'base_freq'*x"
        
        if use_logistic_freq
            formula$ = formula$ + " + 'chaos_strength'*sin(2*pi*'modulation_rate'*3.7*x)"
        endif
        
        formula$ = formula$ + ")"
        
        if use_lorenz_amp
            formula$ = formula$ + " * (0.5 + 0.3*sin(2*pi*'modulation_rate'*0.5*x) + 0.2*sin(2*pi*'modulation_rate'*1.3*x))"
        endif
        
        if use_henon_filter
            formula$ = formula$ + " * (0.7 + 0.3*sin(2*pi*'modulation_rate'*2.1*x))"
        endif
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 2
    for layer from 1 to number_of_layers
        if randomize_parameters
            base_freq = base_frequency * (0.6 + 0.8 * randomUniform(0, 1))
            chaos_strength = chaos_intensity * (0.7 + 0.6 * randomUniform(0, 1))
        else
            base_freq = base_frequency
            chaos_strength = chaos_intensity
        endif
        
        layer_amp = 0.6 / number_of_layers
        
        formula$ = "'layer_amp' * sin(2*pi*'base_freq'*x + 'chaos_strength'*1.5*sin(2*pi*'modulation_rate'*3.7*x) + 'chaos_strength'*0.8*sin(2*pi*'modulation_rate'*4.1*x))"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 3
    for layer from 1 to number_of_layers
        voice_freq = base_frequency * (0.8 + layer * 0.3)
        layer_amp = 0.6 / number_of_layers
        
        formula$ = "'layer_amp' * (0.4 + 0.4*sin(2*pi*'modulation_rate'*0.3*x) + 0.2*sin(2*pi*'modulation_rate'*1.7*x)) * sin(2*pi*'voice_freq'*x)"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 4
    for layer from 1 to number_of_layers
        voice_freq = base_frequency * (0.9 + layer * 0.2)
        layer_amp = 0.6 / number_of_layers
        
        formula$ = "'layer_amp' * (0.3 + 0.7*(0.5 + 0.5*sin(2*pi*'modulation_rate'*2.1*x))) * sin(2*pi*'voice_freq'*x)"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 5
    for layer from 1 to number_of_layers
        if randomize_parameters
            base_freq = base_frequency * (0.5 + randomUniform(0, 1))
            chaos_strength = chaos_intensity * (0.6 + 0.8 * randomUniform(0, 1))
        else
            base_freq = base_frequency
            chaos_strength = chaos_intensity
        endif
        
        layer_amp = 0.7 / number_of_layers
        
        formula$ = "'layer_amp' * (0.3 + 0.5*sin(2*pi*'modulation_rate'*0.7*x) + 0.2*sin(2*pi*'modulation_rate'*1.9*x)) * sin(2*pi*'base_freq'*x + 'chaos_strength'*2.0*sin(2*pi*'modulation_rate'*3.7*x)) * (0.4 + 0.6*(0.5 + 0.5*sin(2*pi*'modulation_rate'*2.3*x)))"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
endif

# Select gen_output for spatial processing - use simple approach
select Sound gen_output

if spatial_mode = 1
    Rename: "chaotic_modulation"
    final_sound = selected("Sound")
    
elsif spatial_mode = 2
    Copy: "chaotic_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "chaotic_right"
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
    Rename: "chaotic_modulation"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    Copy: "chaotic_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "chaotic_right"
    right_sound = selected("Sound")
    
    rotation_rate = 0.15
    select left_sound
    Formula: "self * (0.6 + cos(2*pi*'rotation_rate'*x) * 0.4)"
    
    select right_sound
    Formula: "self * (0.6 + sin(2*pi*'rotation_rate'*x) * 0.4)"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "chaotic_modulation"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    Copy: "chaotic_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "chaotic_right"
    right_sound = selected("Sound")
    
    select left_sound
    Filter (pass Hann band): 50, 3000, 80
    
    select right_sound
    Formula: "if col > 30 then self[col - 30] else 0 fi"
    Filter (pass Hann band): 200, 6000, 80
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "chaotic_modulation"
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

echo Advanced Chaotic Modulation complete!

procedure applyFadeEnvelope
    if fade_time > 0
        fade_samples = fade_time * sample_rate
        total_samples = duration * sample_rate
        Formula: "if col < 'fade_samples' then self * (col/'fade_samples') else if col > ('total_samples' - 'fade_samples') then self * (('total_samples' - col)/'fade_samples') else self fi fi"
    endif
endproc

procedure addToOutput
    select Sound gen_output
    Formula: "self + Sound_layer_'layer'[]"
    select Sound layer_'layer'
    Remove
endproc

procedure applyFinalFade
    if fade_time > 0
        fade_samples = fade_time * sample_rate
        total_samples = duration * sample_rate
        Formula: "if col < 'fade_samples' then self * (col/'fade_samples') else if col > ('total_samples' - 'fade_samples') then self * (('total_samples' - col)/'fade_samples') else self fi fi"
    endif
endproc