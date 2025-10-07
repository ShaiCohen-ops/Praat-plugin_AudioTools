# ============================================================
# Praat AudioTools - Advanced Brownian Synthesis.praat
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

form Advanced Brownian Synthesis System
    positive Duration_(sec) 10
    positive Base_frequency_(Hz) 150
    positive Number_of_layers 4
    real Frequency_spread_(Hz) 100
    real Step_size 10
    boolean Enable_drift 1
    real Drift_force 0.1
    positive Fade_time_(sec) 2
    optionmenu Synthesis_mode: 1
        option Brownian Walk
        option Brownian Chaos
        option Filtered Brownian
        option Brownian Harmonics
        option Pulsed Brownian
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    boolean Normalize_output 1
endform

# Validation
if number_of_layers > 16
    number_of_layers = 16
endif

# Initialize
sample_rate = 44100
control_rate = 40
time_step = 1/control_rate

# ====== BROWNIAN SYNTHESIS ENGINE ======

if synthesis_mode = 1
    # BROWNIAN WALK - Basic frequency walk
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        voice_freq = base_frequency + (layer-1) * frequency_spread
        voice_phase = 0
        voice_formula$ = "0"
        current_time = 0
        
        while current_time < duration
            segment_duration = min(time_step, duration - current_time)
            
            if segment_duration > 0.001
                brownian_step = randomGauss(0, 1) * step_size
                
                if enable_drift
                    drift = (base_frequency - voice_freq) * drift_force * time_step
                    brownian_step = brownian_step + drift
                endif
                
                voice_freq = voice_freq + brownian_step
                voice_freq = max(30, min(5000, voice_freq))
                
                voice_amp = (0.6 / number_of_layers) * (1 - (layer-1)/number_of_layers * 0.3)
                
                segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + segment_duration)
                segment_formula$ = segment_formula$ + " then " + string$(voice_amp)
                segment_formula$ = segment_formula$ + " * sin(" + string$(voice_phase) + " + 2*pi*" + string$(voice_freq) + "*(x - " + string$(current_time) + "))"
                segment_formula$ = segment_formula$ + " else 0 fi"
                
                if voice_formula$ = "0"
                    voice_formula$ = segment_formula$
                else
                    voice_formula$ = voice_formula$ + " + " + segment_formula$
                endif
                
                voice_phase = voice_phase + 2 * pi * voice_freq * segment_duration
            endif
            
            current_time = current_time + time_step
        endwhile
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, voice_formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 2
    # BROWNIAN CHAOS - More extreme variations
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        voice_freq = base_frequency * (0.5 + layer * 0.3)
        voice_phase = 0
        voice_formula$ = "0"
        current_time = 0
        chaos_factor = step_size * (1 + layer * 0.5)
        
        while current_time < duration
            segment_duration = min(time_step, duration - current_time)
            
            if segment_duration > 0.001
                # More chaotic steps with occasional large jumps
                brownian_step = randomGauss(0, 1) * chaos_factor
                if randomUniform(0, 1) < 0.1
                    brownian_step = brownian_step * 5
                endif
                
                if enable_drift
                    drift = (base_frequency * 2 - voice_freq) * drift_force * time_step * 2
                    brownian_step = brownian_step + drift
                endif
                
                voice_freq = voice_freq + brownian_step
                voice_freq = max(20, min(8000, voice_freq))
                
                # Amplitude modulation based on frequency stability
                stability = exp(-abs(brownian_step)/chaos_factor)
                voice_amp = (0.7 / number_of_layers) * stability
                
                segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + segment_duration)
                segment_formula$ = segment_formula$ + " then " + string$(voice_amp)
                segment_formula$ = segment_formula$ + " * sin(" + string$(voice_phase) + " + 2*pi*" + string$(voice_freq) + "*(x - " + string$(current_time) + "))"
                segment_formula$ = segment_formula$ + " else 0 fi"
                
                if voice_formula$ = "0"
                    voice_formula$ = segment_formula$
                else
                    voice_formula$ = voice_formula$ + " + " + segment_formula$
                endif
                
                voice_phase = voice_phase + 2 * pi * voice_freq * segment_duration
            endif
            
            current_time = current_time + time_step
        endwhile
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, voice_formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 3
    # FILTERED BROWNIAN - Noise with Brownian-filtered frequencies
    Create Sound from formula: "gen_base", 1, 0, duration, sample_rate, "randomGauss(0, 0.4)"
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        select Sound gen_base
        Copy: "layer_'layer'"
        
        center_freq = base_frequency * (1 + layer * 0.8)
        current_freq = center_freq
        
        # Create Brownian trajectory for filter frequency
        filter_trajectory$ = string$(center_freq)
        steps = duration * control_rate
        for step from 1 to steps
            brownian_step = randomGauss(0, 1) * step_size * 5
            if enable_drift
                drift = (center_freq - current_freq) * drift_force * time_step
                brownian_step = brownian_step + drift
            endif
            current_freq = current_freq + brownian_step
            current_freq = max(50, min(4000, current_freq))
            filter_trajectory$ = filter_trajectory$ + " + if x >= " + string$(step * time_step) + 
            ... " then " + string$(current_freq - center_freq) + " else 0 fi"
        endfor
        
        # Apply dynamic filtering
        Formula: "self * (0.5 + 0.3 * sin(2*pi*(" + filter_trajectory$ + ")*x/44100))"
        Filter (pass Hann band): center_freq * 0.5, center_freq * 2, 50 + layer * 20
        Rename: "layer_'layer'_filtered"
        
        call applyFadeEnvelope
        
        select Sound gen_output
        Formula: "self + Sound_layer_'layer'_filtered[] / 'number_of_layers'"
        
        select Sound layer_'layer'
        plus Sound layer_'layer'_filtered
        Remove
    endfor
    
    select Sound gen_base
    Remove
    
elsif synthesis_mode = 4
    # BROWNIAN HARMONICS - Harmonic series with Brownian motion
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        harmonic_ratio = layer
        voice_freq = base_frequency * harmonic_ratio
        voice_phase = 0
        voice_formula$ = "0"
        current_time = 0
        harmonic_step = step_size * (0.5 + harmonic_ratio * 0.2)
        
        while current_time < duration
            segment_duration = min(time_step, duration - current_time)
            
            if segment_duration > 0.001
                brownian_step = randomGauss(0, 1) * harmonic_step
                
                if enable_drift
                    # Drift toward harmonic ratio
                    target_freq = base_frequency * harmonic_ratio
                    drift = (target_freq - voice_freq) * drift_force * time_step
                    brownian_step = brownian_step + drift
                endif
                
                voice_freq = voice_freq + brownian_step
                voice_freq = max(30, min(5000, voice_freq))
                
                voice_amp = (0.5 / number_of_layers) / harmonic_ratio
                
                segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + segment_duration)
                segment_formula$ = segment_formula$ + " then " + string$(voice_amp)
                segment_formula$ = segment_formula$ + " * sin(" + string$(voice_phase) + " + 2*pi*" + string$(voice_freq) + "*(x - " + string$(current_time) + "))"
                segment_formula$ = segment_formula$ + " else 0 fi"
                
                if voice_formula$ = "0"
                    voice_formula$ = segment_formula$
                else
                    voice_formula$ = voice_formula$ + " + " + segment_formula$
                endif
                
                voice_phase = voice_phase + 2 * pi * voice_freq * segment_duration
            endif
            
            current_time = current_time + time_step
        endwhile
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, voice_formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
    
elsif synthesis_mode = 5
    # PULSED BROWNIAN - Rhythmic bursts with Brownian frequencies
    Create Sound from formula: "gen_output", 1, 0, duration, sample_rate, "0"
    
    for layer from 1 to number_of_layers
        voice_freq = base_frequency * (0.8 + layer * 0.4)
        voice_phase = 0
        voice_formula$ = "0"
        current_time = 0
        pulse_rate = 2 + layer * 1.5
        
        while current_time < duration
            segment_duration = min(time_step, duration - current_time)
            
            if segment_duration > 0.001
                brownian_step = randomGauss(0, 1) * step_size
                
                if enable_drift
                    drift = (base_frequency - voice_freq) * drift_force * time_step
                    brownian_step = brownian_step + drift
                endif
                
                voice_freq = voice_freq + brownian_step
                voice_freq = max(40, min(3000, voice_freq))
                
                # Pulsed amplitude
                pulse = (sin(2 * pi * pulse_rate * current_time) > 0.7) * 0.8 + 0.2
                voice_amp = (0.7 / number_of_layers) * pulse
                
                segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + segment_duration)
                segment_formula$ = segment_formula$ + " then " + string$(voice_amp)
                segment_formula$ = segment_formula$ + " * sin(" + string$(voice_phase) + " + 2*pi*" + string$(voice_freq) + "*(x - " + string$(current_time) + "))"
                segment_formula$ = segment_formula$ + " else 0 fi"
                
                if voice_formula$ = "0"
                    voice_formula$ = segment_formula$
                else
                    voice_formula$ = voice_formula$ + " + " + segment_formula$
                endif
                
                voice_phase = voice_phase + 2 * pi * voice_freq * segment_duration
            endif
            
            current_time = current_time + time_step
        endwhile
        
        Create Sound from formula: "layer_'layer'", 1, 0, duration, sample_rate, voice_formula$
        call applyFadeEnvelope
        call addToOutput
    endfor
endif

# ====== SPATIAL PROCESSING ======

# Make sure we have the gen_output sound selected
select Sound gen_output

if spatial_mode = 1
    # MONO - Keep as is
    Rename: "brownian_synthesis"
    output_sound = selected("Sound")
    
elsif spatial_mode = 2
    # STEREO WIDE - Static wide image
    Copy: "brownian_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "brownian_right" 
    right_sound = selected("Sound")
    
    # Add slight detuning and spectral differences for width
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
    Rename: "brownian_synthesis"
    output_sound = selected("Sound")
    
    # Cleanup
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 3
    # ROTATING - Circular panning
    Copy: "brownian_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "brownian_right"
    right_sound = selected("Sound")
    
    # Apply rotation (0.15 Hz rotation - slower for smoother motion)
    rotation_rate = 0.15
    select left_sound
    Formula: "self * (0.6 + cos(2*pi*'rotation_rate'*x) * 0.4)"
    
    select right_sound
    Formula: "self * (0.6 + sin(2*pi*'rotation_rate'*x) * 0.4)"
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "brownian_synthesis"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
    
elsif spatial_mode = 4
    # BINAURAL - Simple binaural simulation
    Copy: "brownian_left"
    left_sound = selected("Sound")
    
    select Sound gen_output
    Copy: "brownian_right"
    right_sound = selected("Sound")
    
    # Left channel: fuller, bass emphasis
    select left_sound
    Filter (pass Hann band): 50, 3000, 80
    
    # Right channel: brighter with slight delay
    select right_sound
    # Small delay for phase difference
    Formula: "if col > 30 then self[col - 30] else 0 fi"
    Filter (pass Hann band): 200, 6000, 80
    
    select left_sound
    plus right_sound
    Combine to stereo
    Rename: "brownian_synthesis"
    output_sound = selected("Sound")
    
    select left_sound
    plus right_sound
    Remove
endif

# ====== FINALIZE ======

select output_sound

# Normalize
if normalize_output
    Scale peak: 0.9
endif

# Apply final fade
call applyFinalFade

# Play
Play


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

procedure applyFinalFade
    if fade_time > 0
        fade_samples = fade_time * sample_rate
        total_samples = duration * sample_rate
        Formula: "if col < 'fade_samples' then self * (col/'fade_samples') 
        ... else if col > ('total_samples' - 'fade_samples') then self * (('total_samples' - col)/'fade_samples') 
        ... else self fi fi"
    endif
endproc