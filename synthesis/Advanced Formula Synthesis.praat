# ============================================================
# Praat AudioTools - Advanced Formula Synthesis.praat
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

form Advanced Formula Synthesis System
    positive Duration_(sec) 10
    positive Base_frequency_(Hz) 120
    positive Number_of_layers 3
    real Modulation_depth 0.6
    real Complexity_factor 1.0
    boolean Randomize_parameters 1
    positive Fade_time_(sec) 2
    optionmenu Synthesis_mode: 3
        option Simple Modulation
        option Competing Oscillators
        option Chaotic System
        option Harmonic Series
        option Fibonacci Ratios
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
    # Simple Modulation
    for layer from 1 to number_of_layers
        if randomize_parameters
            base_freq = base_frequency * (0.8 + 0.4 * randomUniform(0, 1))
            mod_depth = modulation_depth * (0.7 + 0.6 * randomUniform(0, 1))
        else
            base_freq = base_frequency
            mod_depth = modulation_depth
        endif
        
        layer_amp = 0.6 / number_of_layers
        
        formula$ = "'layer_amp' * sin(2*pi*'base_freq'*x * (1 + 'mod_depth'*0.3*sin(2*pi*2*x))) * (0.7 + 0.3*sin(2*pi*0.1*x))"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 2
    # Competing Oscillators
    for layer from 1 to number_of_layers
        if randomize_parameters
            base_freq = base_frequency * (0.7 + 0.6 * randomUniform(0, 1))
        else
            base_freq = base_frequency
        endif
        
        layer_amp = 0.5 / number_of_layers
        
        formula$ = "'layer_amp' * ("
        formula$ = formula$ + "sin(2*pi*'base_freq'*x * (1 + 0.2*sin(2*pi*1.5*x))) + "
        formula$ = formula$ + "0.5*sin(2*pi*'base_freq'*1.618*x * (1 + 0.3*sin(2*pi*2.5*x))) + "
        formula$ = formula$ + "0.3*sin(2*pi*'base_freq'*2.718*x * (1 + 0.4*sin(2*pi*0.7*x)))"
        formula$ = formula$ + ") * (0.6 + 0.4*sin(2*pi*0.05*x))"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 3
    # Complex Chaotic System
    for layer from 1 to number_of_layers
        if randomize_parameters
            base_freq = base_frequency * (0.6 + 0.8 * randomUniform(0, 1))
            mod_depth = modulation_depth * (0.8 + 0.4 * randomUniform(0, 1))
        else
            base_freq = base_frequency
            mod_depth = modulation_depth
        endif
        
        layer_amp = 0.55 / number_of_layers
        
        formula$ = "'layer_amp' * ("
        formula$ = formula$ + "sin(2*pi*'base_freq'*x * "
        formula$ = formula$ + "(1 + 'mod_depth'*0.4*sin(2*pi*1.2*x + 1.5*sin(2*pi*0.3*x)))) + "
        formula$ = formula$ + "0.7*sin(2*pi*'base_freq'*1.5*x * "
        formula$ = formula$ + "(1 + 'mod_depth'*0.3*sin(2*pi*2.1*x + 0.8*sin(2*pi*0.5*x)))) + "
        formula$ = formula$ + "0.4*sin(2*pi*'base_freq'*2.2*x * "
        formula$ = formula$ + "(1 + 'mod_depth'*0.5*sin(2*pi*0.9*x + 1.2*sin(2*pi*0.2*x))))"
        formula$ = formula$ + ") * (0.5 + 0.5*sin(2*pi*0.08*x)) * exp(-0.3*x/'duration')"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 4
    # Harmonic Series
    for layer from 1 to number_of_layers
        harmonic = layer
        layer_freq = base_frequency * harmonic
        layer_amp = 0.7 / (number_of_layers * harmonic)
        
        if randomize_parameters
            phase_offset = randomUniform(0, 6.28)
        else
            phase_offset = 0
        endif
        
        formula$ = "'layer_amp' * sin(2*pi*'layer_freq'*x + 'phase_offset') * "
        formula$ = formula$ + "(0.8 + 0.2*sin(2*pi*'complexity_factor'*0.15*x)) * "
        formula$ = formula$ + "(1 - 0.3*sin(2*pi*'complexity_factor'*0.08*x))"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 5
    # Fibonacci Ratios
    for layer from 1 to number_of_layers
        if layer = 1
            ratio = 1.0
        elsif layer = 2
            ratio = 1.618
        elsif layer = 3
            ratio = 2.618
        elsif layer = 4
            ratio = 4.236
        elsif layer = 5
            ratio = 6.854
        elsif layer = 6
            ratio = 11.09
        elsif layer = 7
            ratio = 17.944
        else
            ratio = 29.034
        endif
        
        layer_freq = base_frequency * ratio
        layer_amp = 0.65 / (number_of_layers * sqrt(ratio))
        
        if randomize_parameters
            mod_rate = 0.5 + randomUniform(0, 1.5)
        else
            mod_rate = 1.0
        endif
        
        formula$ = "'layer_amp' * sin(2*pi*'layer_freq'*x * "
        formula$ = formula$ + "(1 + 'modulation_depth'*0.2*sin(2*pi*'mod_rate'*x))) * "
        formula$ = formula$ + "(0.6 + 0.4*sin(2*pi*'complexity_factor'*0.1*x))"
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
endif

# Select gen_output for spatial processing
select Sound gen_output

if spatial_mode = 1
    Rename: "formula_synthesis"
    final_sound = selected("Sound")
    
elsif spatial_mode = 2
    Copy: "formula_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "formula_right"
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
    Rename: "formula_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    Copy: "formula_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "formula_right"
    right_sound = selected("Sound")
    
    rotation_rate = 0.2
    select left_sound
    Formula: "self * (0.6 + cos(2*pi*'rotation_rate'*x) * 0.4)"
    
    select right_sound
    Formula: "self * (0.6 + sin(2*pi*'rotation_rate'*x) * 0.4)"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "formula_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    Copy: "formula_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "formula_right"
    right_sound = selected("Sound")
    
    select left_sound
    Filter (pass Hann band): 50, 3000, 80
    
    select right_sound
    Formula: "if col > 30 then self[col - 30] else 0 fi"
    Filter (pass Hann band): 200, 6000, 80
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "formula_synthesis"
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

echo Advanced Formula Synthesis complete!

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