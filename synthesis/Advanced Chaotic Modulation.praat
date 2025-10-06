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

form Advanced Chaotic Modulation
    real Duration 12.0
    real Sampling_frequency 44100
    real Base_frequency 150
    integer Number_voices 3
    boolean Use_logistic_freq yes
    boolean Use_lorenz_amp yes
    boolean Use_henon_filter yes
    real Chaos_intensity 0.7
    real Filter_smoothing 0.3
    boolean Randomize_parameters yes
    real Fade_out_duration 0.2
endform

echo Creating Advanced Chaotic Modulation with 'number_voices' voices...

control_rate = 150
time_step = 1/control_rate
total_points = round(duration * control_rate)
formula$ = "0"

; Low-pass filter buffers for smoothing chaotic modulation
freq_filter_buf = 0
amp_filter_buf = 0
filter_filter_buf = 0
smoothing = max(0.01, min(0.99, filter_smoothing))

for voice to number_voices
    echo Building voice 'voice'...
    
    ; Parameter randomization for each voice
    if randomize_parameters = 1
        ; Randomize base frequency slightly
        voice_base_freq = base_frequency * (0.8 + 0.4 * randomUniform(0, 1))
        
        ; Randomize chaos parameters
        voice_logistic_r = 3.6 + randomUniform(0, 1) * 0.4
        voice_logistic_x = randomUniform(0, 1)
        
        voice_lorenz_x = randomUniform(-1, 1)
        voice_lorenz_y = randomUniform(-1, 1)
        voice_lorenz_z = 20 + randomUniform(0, 1) * 10
        
        voice_henon_x = randomUniform(-0.5, 0.5)
        voice_henon_y = randomUniform(-0.5, 0.5)
        voice_henon_a = 1.3 + randomUniform(0, 1) * 0.2
        voice_henon_b = 0.2 + randomUniform(0, 1) * 0.2
        
        ; Randomize chaos intensity slightly
        voice_chaos_intensity = chaos_intensity * (0.7 + 0.6 * randomUniform(0, 1))
    else
        voice_base_freq = base_frequency
        voice_logistic_r = 3.7
        voice_logistic_x = 0.5
        voice_lorenz_x = 0.1
        voice_lorenz_y = 0.1
        voice_lorenz_z = 25.0
        voice_henon_x = 0.1
        voice_henon_y = 0.1
        voice_henon_a = 1.4
        voice_henon_b = 0.3
        voice_chaos_intensity = chaos_intensity
    endif
    
    ; Voice-specific parameters
    lorenz_sigma = 10.0
    lorenz_rho = 28.0
    lorenz_beta = 2.666
    
    ; Initialize phase for continuous waveform
    phase = 2 * pi * randomUniform(0, 1)  ; Random initial phase
    
    ; Reset filter buffers for this voice
    freq_filter_buf = voice_base_freq
    amp_filter_buf = 0.6
    filter_filter_buf = 1.0
    
    voice_formula$ = "0"
    
    for i to total_points
        current_time = (i-1) * time_step
        
        ; Frequency modulation using Logistic map
        if use_logistic_freq = 1
            voice_logistic_x = voice_logistic_r * voice_logistic_x * (1 - voice_logistic_x)
            raw_freq_mod = voice_base_freq * (1 + 0.8 * voice_chaos_intensity * (voice_logistic_x - 0.5))
            raw_freq_mod = max(20, min(5000, raw_freq_mod))
            
            ; Apply low-pass filtering to smooth frequency changes
            freq_filter_buf = smoothing * freq_filter_buf + (1 - smoothing) * raw_freq_mod
            freq_mod = freq_filter_buf
        else
            freq_mod = voice_base_freq
        endif
        
        ; Amplitude modulation using Lorenz system
        if use_lorenz_amp = 1
            lorenz_dx = lorenz_sigma * (voice_lorenz_y - voice_lorenz_x)
            lorenz_dy = voice_lorenz_x * (lorenz_rho - voice_lorenz_z) - voice_lorenz_y
            lorenz_dz = voice_lorenz_x * voice_lorenz_y - lorenz_beta * voice_lorenz_z
            
            voice_lorenz_x = voice_lorenz_x + lorenz_dx * 0.01
            voice_lorenz_y = voice_lorenz_y + lorenz_dy * 0.01
            voice_lorenz_z = voice_lorenz_z + lorenz_dz * 0.01
            
            ; Safe amplitude modulation (0.1 to 0.9)
            raw_amp_mod = 0.5 + 0.4 * tanh(voice_lorenz_z / 30)
            
            ; Apply low-pass filtering to smooth amplitude changes
            amp_filter_buf = smoothing * amp_filter_buf + (1 - smoothing) * raw_amp_mod
            amp_mod = amp_filter_buf
        else
            amp_mod = 0.6
        endif
        
        ; Filter modulation using Hénon map
        if use_henon_filter = 1
            henon_x_new = 1 - voice_henon_a * voice_henon_x * voice_henon_x + voice_henon_y
            henon_y_new = voice_henon_b * voice_henon_x
            voice_henon_x = henon_x_new
            voice_henon_y = henon_y_new
            
            ; Constrain Hénon output and use as low-pass filter coefficient
            raw_filter_mod = 0.3 + 0.7 * (0.5 + 0.5 * sin(voice_henon_x))
            
            ; Apply low-pass filtering to smooth filter changes
            filter_filter_buf = smoothing * filter_filter_buf + (1 - smoothing) * raw_filter_mod
            filter_mod = filter_filter_buf
        else
            filter_mod = 1.0
        endif
        
        if current_time + time_step > duration
            current_dur = duration - current_time
        else
            current_dur = time_step
        endif
        
        ; Apply fade-out envelope
        fade_start = duration - fade_out_duration
        if current_time >= fade_start
            fade_factor = 1 - ((current_time - fade_start) / fade_out_duration)
            final_amp = amp_mod * fade_factor / number_voices
        else
            final_amp = amp_mod / number_voices
        endif
        
        if current_dur > 0.001
            ; Use phase-continuous formula
            segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + current_dur)
            segment_formula$ = segment_formula$ + " then " + string$(final_amp)
            segment_formula$ = segment_formula$ + " * sin(" + string$(phase) + " + 2*pi*" + string$(freq_mod) + "*(x - " + string$(current_time) + "))"
            segment_formula$ = segment_formula$ + " * " + string$(filter_mod)
            segment_formula$ = segment_formula$ + " else 0 fi"
            
            if voice_formula$ = "0"
                voice_formula$ = segment_formula$
            else
                voice_formula$ = voice_formula$ + " + " + segment_formula$
            endif
            
            ; Update phase for next segment
            phase = phase + 2 * pi * freq_mod * current_dur
        endif
    endfor
    
    if formula$ = "0"
        formula$ = voice_formula$
    else
        formula$ = formula$ + " + " + voice_formula$
    endif
endfor

Create Sound from formula... advanced_chaos 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9
Play

echo Advanced Chaotic Modulation complete!