# ============================================================
# Praat AudioTools - canon.praat
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

form Canon Voices Effect
    comment This script creates a canon with multiple pitch-shifted voices
    comment Canon parameters:
    natural number_of_voices 4
    positive delay_between_entries_seconds 0.50
    integer semitone_step 7
    comment (pitch interval between voices)
    boolean wrap_to_octave 1
    comment (wrap pitch to 0-11 semitones)
    comment Intensity shaping:
    real start_intensity_db 70
    real intensity_step_db -3
    comment (each voice gets this dB increment)
    comment Resampling:
    positive output_sample_rate 44100
    positive resample_precision 50
    comment Output options:
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

orig$ = selected$("Sound")

# Work on a copy
select Sound 'orig$'
Copy: "base"

# Get original sampling rate
select Sound base
f0 = Get sampling frequency

for v from 1 to number_of_voices
    # Calculate pitch shift
    s = (v - 1) * semitone_step
    if wrap_to_octave
        s = s - 12 * floor(s / 12)
    endif
    factor = 2 ^ (s / 12)
    f_override = floor(f0 * factor + 0.5)
    
    # Create pitched voice
    select Sound base
    Copy: "voice_raw"
    Override sampling frequency: f_override
    Resample: output_sample_rate, resample_precision
    Convert to mono
    Rename: "voice"
    
    selectObject: "Sound voice_raw"
    Remove
    
    # Add delay via silence
    d = (v - 1) * delay_between_entries_seconds
    if d > 0
        Create Sound from formula: "pad", 1, 0, d, output_sample_rate, "0"
        select Sound pad
        plus Sound voice
        Concatenate
        Rename: "voice"
        select Sound pad
        Remove
    endif
    
    # Apply intensity shaping
    gain_dB = start_intensity_db + (v - 1) * intensity_step_db
    select Sound voice
    Scale intensity: gain_dB
    
    # Mix voices
    if v = 1
        Rename: "mix"
    else
        select Sound mix
        Resample: output_sample_rate, resample_precision
        Convert to mono
        select Sound voice
        Resample: output_sample_rate, resample_precision
        Convert to mono
        
        # Ensure equal length
        select Sound mix
        dm = Get end time
        select Sound voice
        dv = Get end time
        
        if dm < dv
            pad_len = dv - dm
            Create Sound from formula: "pad_end", 1, 0, pad_len, output_sample_rate, "0"
            select Sound mix
            plus Sound pad_end
            Concatenate
            Rename: "mix"
            select Sound pad_end
            Remove
        endif
        
        if dv < dm
            pad_len = dm - dv
            Create Sound from formula: "pad_end", 1, 0, pad_len, output_sample_rate, "0"
            select Sound voice
            plus Sound pad_end
            Concatenate
            Rename: "voice"
            select Sound pad_end
            Remove
        endif
        
        # Combine and mix to mono
        select Sound mix
        plus Sound voice
        Combine to stereo
        Convert to mono
        Scale peak: 0.99
        Rename: "mix"
        selectObject: "Sound voice"
        Remove
    endif
endfor

# Finalize
select Sound mix
Rename: orig$ + "_canon_mix"

if play_after_processing
    Play
endif

# Cleanup
if not keep_intermediate_objects
    select all
    minusObject: "Sound 'orig$'"
    minusObject: "Sound 'orig$'_canon_mix"
    Remove
endif

select Sound 'orig$'_canon_mix