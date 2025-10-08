# ============================================================
# Praat AudioTools - Algorithmic Metallic Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Algorithmic Metallic Synthesis script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Advanced Metallic Synthesis System
    positive Duration_(sec) 3
    positive Base_frequency_(Hz) 200
    positive Number_of_voices 5
    positive Modulation_rate_(Hz) 0.5
    positive Resonance_decay_(sec) 0.1
    integer Number_of_layers 3
    boolean Randomize_parameters 1
    positive Fade_time_(sec) 0.5
    optionmenu Synthesis_mode: 1
        option Standard Metallic
        option Dense Shimmer
        option Sparse Bells
        option Rhythmic Clang
        option Chaotic Resonance
    optionmenu Spatial_mode: 2
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    boolean Normalize_output 1
endform

if number_of_voices > 12
    number_of_voices = 12
endif

if number_of_layers > 8
    number_of_layers = 8
endif

sample_rate = 44100

echo Building Advanced Metallic Synthesis...

# Create base sound
Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"

if synthesis_mode = 1
    # Standard Metallic
    for layer from 1 to number_of_layers
        layer_voices = number_of_voices
        
        if randomize_parameters
            layer_mod_rate = modulation_rate * (0.7 + 0.6 * randomUniform(0, 1))
            layer_decay = resonance_decay * (0.8 + 0.4 * randomUniform(0, 1))
        else
            layer_mod_rate = modulation_rate
            layer_decay = resonance_decay
        endif
        
        for i from 1 to layer_voices
            this_freq = (i + 2) * base_frequency * (1 + (layer - 1) * 0.1)
            detune = 1 + ((i - 1) * 0.02)
            voice_amp = 0.4 / (number_of_layers * sqrt(layer_voices))
            
            Create Sound from formula: "carrier", 1, 0, duration, sample_rate, "'voice_amp' * sin(2*pi*'this_freq'*x*'detune' + sin(2*pi*'layer_mod_rate'*x)*3)"
            
            Create Sound from formula: "trigger", 1, 0, duration, sample_rate, "if (x*('i'+2)) mod 1 < 0.2 then 1 else 0 fi"
            
            select Sound carrier
            Formula: "self * Sound_trigger[]"
            Filter (pass Hann band): this_freq, this_freq, 200
            Formula: "self * (0.5 + 0.5 * exp(-x/'layer_decay'))"
            Rename: "voice"
            
            select Sound gen_output
            Formula: "self + Sound_voice[]"
            
            select Sound carrier
            plus Sound trigger
            plus Sound voice
            Remove
        endfor
    endfor
    
elsif synthesis_mode = 2
    # Dense Shimmer
    for layer from 1 to number_of_layers
        layer_voices = number_of_voices * 2
        
        if randomize_parameters
            layer_mod_rate = modulation_rate * 2 * (0.8 + 0.4 * randomUniform(0, 1))
            layer_decay = resonance_decay * 0.6 * (0.9 + 0.2 * randomUniform(0, 1))
        else
            layer_mod_rate = modulation_rate * 2
            layer_decay = resonance_decay * 0.6
        endif
        
        for i from 1 to layer_voices
            this_freq = (i + 1) * base_frequency * (1.5 + (layer - 1) * 0.2)
            detune = 1 + ((i - 1) * 0.015)
            voice_amp = 0.3 / (number_of_layers * sqrt(layer_voices))
            
            Create Sound from formula: "carrier", 1, 0, duration, sample_rate, "'voice_amp' * sin(2*pi*'this_freq'*x*'detune' + sin(2*pi*'layer_mod_rate'*x)*2)"
            
            Create Sound from formula: "trigger", 1, 0, duration, sample_rate, "if (x*('i'+3)) mod 0.8 < 0.15 then 1 else 0 fi"
            
            select Sound carrier
            Formula: "self * Sound_trigger[]"
            Filter (pass Hann band): this_freq, this_freq, 300
            Formula: "self * (0.6 + 0.4 * exp(-x/'layer_decay'))"
            Rename: "voice"
            
            select Sound gen_output
            Formula: "self + Sound_voice[]"
            
            select Sound carrier
            plus Sound trigger
            plus Sound voice
            Remove
        endfor
    endfor
    
elsif synthesis_mode = 3
    # Sparse Bells
    for layer from 1 to number_of_layers
        layer_voices = max(2, number_of_voices / 2)
        
        if randomize_parameters
            layer_mod_rate = modulation_rate * 0.3 * (0.6 + 0.8 * randomUniform(0, 1))
            layer_decay = resonance_decay * 2 * (0.8 + 0.4 * randomUniform(0, 1))
        else
            layer_mod_rate = modulation_rate * 0.3
            layer_decay = resonance_decay * 2
        endif
        
        for i from 1 to layer_voices
            this_freq = (i + 3) * base_frequency * (0.8 + (layer - 1) * 0.3)
            detune = 1 + ((i - 1) * 0.01)
            voice_amp = 0.6 / (number_of_layers * sqrt(layer_voices))
            
            Create Sound from formula: "carrier", 1, 0, duration, sample_rate, "'voice_amp' * sin(2*pi*'this_freq'*x*'detune' + sin(2*pi*'layer_mod_rate'*x)*4)"
            
            Create Sound from formula: "trigger", 1, 0, duration, sample_rate, "if (x*('i'+1)) mod 1.5 < 0.3 then 1 else 0 fi"
            
            select Sound carrier
            Formula: "self * Sound_trigger[]"
            Filter (pass Hann band): this_freq, this_freq, 150
            Formula: "self * (0.3 + 0.7 * exp(-x/'layer_decay'))"
            Rename: "voice"
            
            select Sound gen_output
            Formula: "self + Sound_voice[]"
            
            select Sound carrier
            plus Sound trigger
            plus Sound voice
            Remove
        endfor
    endfor
    
elsif synthesis_mode = 4
    # Rhythmic Clang
    for layer from 1 to number_of_layers
        layer_voices = number_of_voices
        
        if randomize_parameters
            layer_mod_rate = modulation_rate * 1.5 * (0.85 + 0.3 * randomUniform(0, 1))
            layer_decay = resonance_decay * 0.8 * (0.9 + 0.2 * randomUniform(0, 1))
        else
            layer_mod_rate = modulation_rate * 1.5
            layer_decay = resonance_decay * 0.8
        endif
        
        for i from 1 to layer_voices
            this_freq = i * base_frequency * (1 + (layer - 1) * 0.15)
            detune = 1 + ((i - 1) * 0.025)
            voice_amp = 0.5 / (number_of_layers * sqrt(layer_voices))
            
            Create Sound from formula: "carrier", 1, 0, duration, sample_rate, "'voice_amp' * sin(2*pi*'this_freq'*x*'detune' + sin(2*pi*'layer_mod_rate'*x)*2.5)"
            
            Create Sound from formula: "trigger", 1, 0, duration, sample_rate, "if (x*'i') mod 0.5 < 0.1 then 1 else 0 fi"
            
            select Sound carrier
            Formula: "self * Sound_trigger[]"
            Filter (pass Hann band): this_freq, this_freq, 250
            Formula: "self * (0.4 + 0.6 * exp(-x/'layer_decay'))"
            Rename: "voice"
            
            select Sound gen_output
            Formula: "self + Sound_voice[]"
            
            select Sound carrier
            plus Sound trigger
            plus Sound voice
            Remove
        endfor
    endfor
    
elsif synthesis_mode = 5
    # Chaotic Resonance
    for layer from 1 to number_of_layers
        layer_voices = number_of_voices
        
        if randomize_parameters
            layer_mod_rate = modulation_rate * (0.5 + randomUniform(0, 1.5))
            layer_decay = resonance_decay * (0.5 + randomUniform(0, 1))
        else
            layer_mod_rate = modulation_rate * (0.5 + randomUniform(0, 1.5))
            layer_decay = resonance_decay * (0.5 + randomUniform(0, 1))
        endif
        
        for i from 1 to layer_voices
            this_freq = (i + randomUniform(0, 3)) * base_frequency * (0.7 + randomUniform(0, 0.8))
            detune = 1 + (randomUniform(0, 0.05))
            voice_amp = 0.5 / (number_of_layers * sqrt(layer_voices))
            
            Create Sound from formula: "carrier", 1, 0, duration, sample_rate, "'voice_amp' * sin(2*pi*'this_freq'*x*'detune' + sin(2*pi*'layer_mod_rate'*x)*randomUniform(2, 5))"
            
            trigger_mod = randomUniform(0.3, 1.2)
            trigger_thresh = randomUniform(0.1, 0.3)
            Create Sound from formula: "trigger", 1, 0, duration, sample_rate, "if (x*randomUniform(2, 8)) mod 'trigger_mod' < 'trigger_thresh' then 1 else 0 fi"
            
            select Sound carrier
            Formula: "self * Sound_trigger[]"
            Filter (pass Hann band): this_freq, this_freq, randomUniform(100, 400)
            Formula: "self * (randomUniform(0.3, 0.6) + randomUniform(0.4, 0.7) * exp(-x/'layer_decay'))"
            Rename: "voice"
            
            select Sound gen_output
            Formula: "self + Sound_voice[]"
            
            select Sound carrier
            plus Sound trigger
            plus Sound voice
            Remove
        endfor
    endfor
endif

# Select gen_output for spatial processing
select Sound gen_output

if spatial_mode = 1
    Rename: "metallic_synthesis"
    final_sound = selected("Sound")
    
elsif spatial_mode = 2
    Copy: "metallic_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "metallic_right"
    right_sound = selected("Sound")
    
    select left_sound
    Formula: "self * 0.8"
    
    select right_sound
    Formula: "sin(2*pi*0.5*x) * 0.2 + self * 0.8"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "metallic_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    Copy: "metallic_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "metallic_right"
    right_sound = selected("Sound")
    
    rotation_rate = 0.3
    select left_sound
    Formula: "self * (0.6 + cos(2*pi*'rotation_rate'*x) * 0.4)"
    
    select right_sound
    Formula: "self * (0.6 + sin(2*pi*'rotation_rate'*x) * 0.4)"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "metallic_synthesis"
    final_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    Copy: "metallic_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "metallic_right"
    right_sound = selected("Sound")
    
    select left_sound
    Filter (pass Hann band): 100, 4000, 100
    
    select right_sound
    Formula: "if col > 20 then self[col - 20] else 0 fi"
    Filter (pass Hann band): 300, 8000, 100
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "metallic_synthesis"
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

echo Advanced Metallic Synthesis complete!

procedure applyFinalFade
    if fade_time > 0
        fade_samples = fade_time * sample_rate
        total_samples = duration * sample_rate
        Formula: "if col < 'fade_samples' then self * (col/'fade_samples') else if col > ('total_samples' - 'fade_samples') then self * (('total_samples' - col)/'fade_samples') else self fi fi"
    endif
endproc