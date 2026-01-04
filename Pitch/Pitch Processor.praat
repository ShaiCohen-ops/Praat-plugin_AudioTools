# ============================================================
# Praat AudioTools - Pitch Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Pitch Processor
    comment --- Operation Mode ---
    choice Mode 1
        button Instant Stereo Harmonizer
        button Time-Delayed Canon

    comment --- Presets (Canon Only) ---
    choice Preset 1
        button Custom (Use settings below)
        button Major Arpeggio (Fast)
        button Spooky Cluster (Slow)
        button Octave Stacks
    
    comment --- Mode 1: Stereo Harmonizer Settings ---
    positive Override_sample_rate 40000

    comment --- Mode 2: Canon Settings (Custom) ---
    natural Number_of_voices 4
    positive Delay_between_entries 0.5
    integer Semitone_step 7
    boolean Wrap_to_octave 1
    real Start_intensity_dB 70
    real Intensity_step_dB -3

    comment --- Global Settings ---
    positive Output_sample_rate 44100
    positive Resample_precision 50
    boolean Play_after_processing 1
    boolean Keep_intermediate_objects 0
endform

# --- Input Check ---
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# --- Apply Presets ---
if mode == 2
    if preset == 2
        # Major Arpeggio
        number_of_voices = 4
        delay_between_entries = 0.25
        semitone_step = 4
        wrap_to_octave = 0
    elsif preset == 3
        # Spooky Cluster
        number_of_voices = 5
        delay_between_entries = 1.2
        semitone_step = 1
        wrap_to_octave = 0
        intensity_step_dB = -1
    elsif preset == 4
        # Octave Stacks
        number_of_voices = 3
        delay_between_entries = 0.5
        semitone_step = 12
        wrap_to_octave = 0
        intensity_step_dB = -2
    endif
endif

orig$ = selected$("Sound")
id_original = selected("Sound")
id_final_output = 0

# ============================================================
# MODE 1: Instant Stereo Harmonizer
# ============================================================
if mode == 1
    selectObject: id_original
    
    # 1. Left Channel
    Copy: "temp_L_raw"
    id_L_raw = selected("Sound")
    Resample: output_sample_rate, resample_precision
    id_L_final = selected("Sound")
    
    # 2. Right Channel
    selectObject: id_original
    Copy: "temp_R_raw"
    id_R_raw = selected("Sound")
    Override sampling frequency: override_sample_rate
    Resample: output_sample_rate, resample_precision
    id_R_final = selected("Sound")

    # 3. Combine
    selectObject: id_L_final
    plusObject: id_R_final
    Combine to stereo
    Rename: orig$ + "_stereo_shift"
    id_final_output = selected("Sound")
    
    # 4. Cleanup
    selectObject: id_L_raw
    plusObject: id_R_raw
    plusObject: id_L_final
    plusObject: id_R_final
    Remove
endif

# ============================================================
# MODE 2: Time-Delayed Canon
# ============================================================
if mode == 2
    selectObject: id_original
    Copy: "base"
    id_base = selected("Sound")
    f0 = Get sampling frequency

    for v from 1 to number_of_voices
        # --- A. Pitch Calculation ---
        s = (v - 1) * semitone_step
        if wrap_to_octave
            s = s - 12 * floor(s / 12)
        endif
        factor = 2 ^ (s / 12)
        f_override = floor(f0 * factor + 0.5)
        
        # --- B. Create Voice (Strict Cleanup) ---
        selectObject: id_base
        Copy: "voice_raw"
        id_step1 = selected("Sound")
        
        Override sampling frequency: f_override
        Resample: output_sample_rate, resample_precision
        id_step2 = selected("Sound")  ; New object created by Resample
        
        Convert to mono
        Rename: "voice"
        id_voice = selected("Sound")  ; New object created by Convert
        
        # CLEANUP RAW VOICES
        selectObject: id_step1
        plusObject: id_step2
        Remove
        
        # --- C. Delay (Padding) ---
        d = (v - 1) * delay_between_entries
        if d > 0
            Create Sound from formula: "pad", 1, 0, d, output_sample_rate, "0"
            id_pad = selected("Sound")
            
            selectObject: id_pad
            plusObject: id_voice
            Concatenate
            id_chain = selected("Sound")
            
            selectObject: id_pad
            plusObject: id_voice
            Remove
            
            selectObject: id_chain
            Rename: "voice"
            id_voice = selected("Sound")
        endif
        
        # --- D. Intensity ---
        gain_dB = start_intensity_dB + (v - 1) * intensity_step_dB
        selectObject: id_voice
        Scale intensity: gain_dB
        
        # --- E. Mixing ---
        if v = 1
            Rename: "mix"
            id_mix = selected("Sound")
        else
            # 1. Ensure Rate Match
            selectObject: id_mix
            Resample: output_sample_rate, resample_precision
            id_mix_new = selected("Sound")
            if id_mix_new != id_mix
                selectObject: id_mix
                Remove
                id_mix = id_mix_new
            endif

            selectObject: id_voice
            Resample: output_sample_rate, resample_precision
            id_voice_new = selected("Sound")
            if id_voice_new != id_voice
                selectObject: id_voice
                Remove
                id_voice = id_voice_new
            endif

            # 2. Length Match
            selectObject: id_mix
            dur_mix = Get end time
            selectObject: id_voice
            dur_voice = Get end time
            
            if dur_mix < dur_voice
                pad_len = dur_voice - dur_mix
                Create Sound from formula: "pad_end", 1, 0, pad_len, output_sample_rate, "0"
                id_pad_end = selected("Sound")
                selectObject: id_mix
                plusObject: id_pad_end
                Concatenate
                id_mix_ext = selected("Sound")
                selectObject: id_mix
                plusObject: id_pad_end
                Remove
                id_mix = id_mix_ext
            endif
            
            if dur_voice < dur_mix
                pad_len = dur_mix - dur_voice
                Create Sound from formula: "pad_end", 1, 0, pad_len, output_sample_rate, "0"
                id_pad_end = selected("Sound")
                selectObject: id_voice
                plusObject: id_pad_end
                Concatenate
                id_voice_ext = selected("Sound")
                selectObject: id_voice
                plusObject: id_pad_end
                Remove
                id_voice = id_voice_ext
            endif
            
            # 3. Combine and Clean Stereo Intermediate
            selectObject: id_mix
            plusObject: id_voice
            Combine to stereo
            id_stereo_temp = selected("Sound")
            
            Convert to mono
            id_mix_sum = selected("Sound")
            
            # CRITICAL CLEANUP
            selectObject: id_stereo_temp
            Remove
            selectObject: id_mix
            plusObject: id_voice
            Remove
            
            # Setup for next loop
            selectObject: id_mix_sum
            Scale peak: 0.99
            Rename: "mix"
            id_mix = selected("Sound")
        endif
    endfor

    # Finalize
    selectObject: id_mix
    Rename: orig$ + "_canon_mix"
    id_final_output = selected("Sound")
    
    selectObject: id_base
    Remove
endif

# --- Play ---
if id_final_output > 0
    selectObject: id_final_output
    if play_after_processing
        Play
    endif
endif