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

form Advanced Brownian Synthesis
    real Duration 8.0
    real Sampling_frequency 44100
    integer Number_voices 2
    real Base_frequency 150
    real Frequency_spread 100
    real Step_size 10
    boolean Enable_drift yes
    real Drift_force 0.1
    real Fade_out_duration 1.5
endform

echo Creating 'number_voices' Brownian voices...

formula$ = "0"

for voice to number_voices
    echo Building voice 'voice'
    voice_freq = base_frequency + (voice-1) * frequency_spread
    voice_formula$ = "0"
    current_time = 0
    control_rate = 40
    time_step = 1/control_rate
    voice_phase = 0  ; Initialize phase for this voice
    
    while current_time < duration
        segment_duration = min(time_step, duration - current_time)
        
        if segment_duration > 0.001
            brownian_step = randomGauss(0, 1) * step_size
            
            if enable_drift = 1
                drift = (base_frequency - voice_freq) * drift_force * time_step
                brownian_step = brownian_step + drift
            endif
            
            voice_freq = voice_freq + brownian_step
            voice_freq = max(30, min(5000, voice_freq))
            
            voice_amp = 0.6 / number_voices
            
            ; Apply fade-out envelope if in fade region
            fade_start = duration - fade_out_duration
            if current_time >= fade_start
                ; Linear fade out: 1.0 at fade_start to 0.0 at duration
                fade_factor = 1 - ((current_time - fade_start) / fade_out_duration)
                ; For segments that cross the fade boundary, we'd need more complex handling
                ; but this approximation works well for small segments
                segment_amp = voice_amp * fade_factor
            else
                segment_amp = voice_amp
            endif
            
            ; Use phase-offset formula for continuity
            segment_formula$ = "if x >= " + string$(current_time) + " and x < " + string$(current_time + segment_duration)
            segment_formula$ = segment_formula$ + " then " + string$(segment_amp)
            segment_formula$ = segment_formula$ + " * sin(" + string$(voice_phase) + " + 2*pi*" + string$(voice_freq) + "*(x - " + string$(current_time) + "))"
            segment_formula$ = segment_formula$ + " else 0 fi"
            
            if voice_formula$ = "0"
                voice_formula$ = segment_formula$
            else
                voice_formula$ = voice_formula$ + " + " + segment_formula$
            endif
            
            ; Advance phase for next segment
            voice_phase = voice_phase + 2 * pi * voice_freq * segment_duration
        endif
        
        current_time = current_time + time_step
    endwhile
    
    if formula$ = "0"
        formula$ = voice_formula$
    else
        formula$ = formula$ + " + " + voice_formula$
    endif
endfor

Create Sound from formula... advanced_brownian 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9
Play

echo Advanced Brownian Synthesis complete!
echo Advanced Brownian Synthesis complete!