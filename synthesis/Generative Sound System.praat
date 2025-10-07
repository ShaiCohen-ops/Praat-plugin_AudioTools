# ============================================================
# Praat AudioTools - Generative Sound System.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generative Sound System script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Enhanced Generative System
    positive Duration_(sec) 10
    positive Base_frequency_(Hz) 110
    positive Number_of_layers 4
    real Evolution_rate 0.5 
    optionmenu Synthesis_mode: 1
        option Harmonic Drift
        option Granular Cloud
        option FM Chaos
        option Spectral Morph
        option Rhythmic Pulse
        option Subtractive Noise
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    positive Fade_time_(sec) 2
    boolean Normalize_output 1
endform

# Validation
if number_of_layers > 16
    number_of_layers = 16
endif

# Initialize
sample_rate = 44100

# ====== SYNTHESIS ENGINE ======

if synthesis_mode = 1
    # HARMONIC DRIFT - Evolving harmonic series
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        harmonic = layer
        freq = base_frequency * harmonic
        drift_rate = evolution_rate * (0.3 + layer * 0.1)
        detune = 1 + sin(layer * 1.7) * 0.02
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate,
        ... "sin(2*pi*'freq'*'detune'*x + sin(2*pi*'drift_rate'*x)*2) * 
        ... (1 / ('layer' + 1)) * 
        ... (0.6 + sin(2*pi*'drift_rate'*0.5*x) * 0.4)"
        
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 2
    # GRANULAR CLOUD - Grain-based texture
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        grain_freq = base_frequency * (1 + layer * 0.3)
        grain_rate = 20 + layer * 15
        grain_density = evolution_rate * 10
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate,
        ... "sin(2*pi*'grain_freq'*x) * 
        ... (abs(sin(2*pi*'grain_rate'*x + 'layer')) > 0.7) * 
        ... exp(-abs(sin(2*pi*'grain_rate'*x)) * 'grain_density') * 
        ... randomGauss(0, 0.15 + sin(2*pi*'evolution_rate'*x) * 0.1)"
        
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 3
    # FM CHAOS - Chaotic frequency modulation
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        carrier = base_frequency * (1 + layer * 0.25)
        mod_freq = carrier * (1.5 + layer * 0.3)
        mod_index = 3 + sin(layer * 2.3) * 2
        chaos_rate = evolution_rate * (0.5 + layer * 0.2)
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate,
        ... "sin(2*pi*'carrier'*x + 
        ... 'mod_index' * sin(2*pi*'mod_freq'*x * (1 + sin(2*pi*'chaos_rate'*x)*0.5))) * 
        ... (0.5 / 'number_of_layers')"
        
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 4
    # SPECTRAL MORPH - Filter bank sweep
    Create Sound from formula: "gen_base", 1, 0, duration, sample_rate,
    ... "randomGauss(0, 0.3)"
    
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        select Sound gen_base
        Copy: "layer_'layer'"
        
        center_freq = base_frequency * (1 + layer * 2)
        sweep_range = center_freq * 0.5
        sweep_rate = evolution_rate * (0.2 + layer * 0.1)
        
        # Dynamic filter with sweeping center frequency
        Formula: "self * (1 + sin(2*pi*('center_freq' + 'sweep_range' * sin(2*pi*'sweep_rate'*x))*x/44100) * 0.5)"
        
        Filter (pass Hann band): center_freq * 0.7, center_freq * 1.5, 100
        Rename: "layer_'layer'_filtered"
        
        call applyFadeEnvelope
        
        # Add back to output
        select Sound gen_output
        Formula: "self + Sound_layer_'layer'_filtered[] / 'number_of_layers'"
        
        select Sound layer_'layer'
        plus Sound layer_'layer'_filtered
        Remove
    endfor
    
    select Sound gen_base
    Remove
    
elsif synthesis_mode = 5
    # RHYTHMIC PULSE - Synced pulse trains
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        pulse_freq = base_frequency * (1 + layer * 0.5)
        rhythm_rate = evolution_rate * (1 + layer * 0.5)
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate,
        ... "(abs(sin(2*pi*'pulse_freq'*x)) > 0.95) * 
        ... sin(2*pi*'pulse_freq'*x) * 
        ... (0.5 + sin(2*pi*'rhythm_rate'*x) * 0.5) * 
        ... (1 / sqrt('layer'))"
        
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 6
    # SUBTRACTIVE NOISE - Filtered evolving noise
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate,
    ... "randomGauss(0, 0.5)"
    
    for layer from 1 to number_of_layers
        select Sound gen_output
        Copy: "layer_'layer'"
        
        filter_freq = base_frequency * (2 ^ layer)
        resonance = 50 + layer * 30
        sweep_rate = evolution_rate * 0.3
        
        # Apply resonant filter with modulation
        Formula: "self * (1 + sin(2*pi*'filter_freq'*(1 + sin(2*pi*'sweep_rate'*x)*0.3)*x/44100) * 0.8)"
        
        Filter (pass Hann band): filter_freq * 0.8, filter_freq * 1.2, resonance
        Rename: "layer_'layer'_filtered"
        
        select Sound layer_'layer'_filtered
        call applyFadeEnvelope
        
        select Sound gen_output
        Formula: "self * 0.3 + Sound_layer_'layer'_filtered[] / 'number_of_layers'"
        
        select Sound layer_'layer'
        plus Sound layer_'layer'_filtered
        Remove
    endfor
endif

# ====== SPATIAL PROCESSING ======

select Sound gen_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "generative_system"
    output = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO WIDE - Static wide image
    Copy: "gen_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "gen_right"
    right_sound = selected("Sound")
    
    # Add slight detuning and delay for width
    select left_sound
    Formula: "self * 0.95"
    
    select right_sound
    Formula: "Sound_gen_left[col + 50] * 1.05 + self * 0.05"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "generative_system"
    output = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # ROTATING - Circular panning
    Copy: "gen_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "gen_right"
    right_sound = selected("Sound")
    
    # Apply rotation (0.25 Hz rotation)
    rotation_rate = 0.25
    select left_sound
    Formula: "self * (0.5 + cos(2*pi*'rotation_rate'*x) * 0.5)"
    
    select right_sound
    Formula: "Sound_gen_output[] * (0.5 + sin(2*pi*'rotation_rate'*x) * 0.5)"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "generative_system"
    output = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL - Phase and spectral differences
    
    # Left channel: low-pass emphasis
    Copy: "gen_left"
    left_sound = selected("Sound")
    Filter (pass Hann band): 0, base_frequency * 8, 100
    Scale intensity: 72
    
    # Right channel: high-pass emphasis with delay
    select Sound gen_output
    Copy: "gen_right"
    right_sound = selected("Sound")
    
    # Create delayed version for phase shift
    delay_samples = 100
    Formula: "if col > 'delay_samples' then self[col - 'delay_samples'] else 0 fi"
    Filter (pass Hann band): base_frequency * 2, 0, 100
    Scale intensity: 72
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "generative_system"
    output = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

# ====== FINALIZE ======

select output

# Normalize
if normalize_output
    Scale peak: 0.85
endif

# Play
Play

# Clean up and select final output
select Sound gen_output
Remove

select output

# ====== PROCEDURES ======

procedure applyFadeEnvelope
    if fade_time > 0
        fade_samples = fade_time * sample_rate
        total_samples = duration * sample_rate
        Formula: "if col < 'fade_samples' then self * (col/'fade_samples') 
        ... else if col > ('total_samples' - 'fade_samples') then self * (('total_samples' - col)/'fade_samples') 
        ... else self fi fi"
    endif
endproc

procedure addToOutput
    select Sound gen_output
    Formula: "self + Sound_layer_'layer'[] / 'number_of_layers'"
    
    select Sound layer_'layer'
    Remove
endproc