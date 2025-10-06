# ============================================================
# Praat AudioTools - 8-Channel Canon.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form 8-Channel Canon
    comment Sampling rate:
    positive Resample_frequency 44100
    
    comment Shift rates (Hz):
    positive Shift_rate_1 49392
    positive Shift_rate_2 46660
    positive Shift_rate_3 52388
    positive Shift_rate_4 41608
    positive Shift_rate_5 39686
    positive Shift_rate_6 55426
    positive Shift_rate_7 37454
    positive Shift_rate_8 58740
    
    comment Options:
    boolean Keep_intermediate_files 0
    boolean Play_result 1
endform

# must have a Sound selected
if not selected ("Sound")
    exit Please select a Sound object first.
endif

# Get original name and create base mono
orig$ = selected$ ("Sound")
select Sound 'orig$'
Copy... base_original
Convert to mono
Resample... 'resample_frequency' 50

# Create all necessary copies of the base sound first
select Sound base_original
Copy... base1
Copy... base2
Copy... base3
Copy... base4
Copy... base5
Copy... base6
Copy... base7
Copy... base8

# Create shifted version 1
select Sound base1
Override sampling frequency... 'shift_rate_1'
Resample... 'resample_frequency' 50
Rename... shift1

# Create shifted version 2  
select Sound base2
Override sampling frequency... 'shift_rate_2'
Resample... 'resample_frequency' 50
Rename... shift2

# Create shifted version 3
select Sound base3
Override sampling frequency... 'shift_rate_3'
Resample... 'resample_frequency' 50
Rename... shift3

# Create shifted version 4
select Sound base4
Override sampling frequency... 'shift_rate_4'
Resample... 'resample_frequency' 50
Rename... shift4

# Create shifted version 5
select Sound base5
Override sampling frequency... 'shift_rate_5'
Resample... 'resample_frequency' 50
Rename... shift5

# Create shifted version 6
select Sound base6
Override sampling frequency... 'shift_rate_6'
Resample... 'resample_frequency' 50
Rename... shift6

# Create shifted version 7
select Sound base7
Override sampling frequency... 'shift_rate_7'
Resample... 'resample_frequency' 50
Rename... shift7

# Create shifted version 8
select Sound base8
Override sampling frequency... 'shift_rate_8'
Resample... 'resample_frequency' 50
Rename... shift8

# Create 4 stereo pairs
select Sound shift1
plus Sound shift2
Combine to stereo
Rename... pair_1_2

select Sound shift3
plus Sound shift4
Combine to stereo
Rename... pair_3_4

select Sound shift5
plus Sound shift6
Combine to stereo
Rename... pair_5_6

select Sound shift7
plus Sound shift8
Combine to stereo
Rename... pair_7_8

# Combine pairs into larger groups
select Sound pair_1_2
plus Sound pair_3_4
Combine to stereo
Rename... channels_1234_mixed

select Sound pair_5_6
plus Sound pair_7_8
Combine to stereo
Rename... channels_5678_mixed

# Final combination
select Sound channels_1234_mixed
plus Sound channels_5678_mixed
Combine to stereo
Rename... canon_8ch_final_mix

# Play if requested
if play_result
    select Sound canon_8ch_final_mix
    Play
endif

# Clean up if not keeping intermediate files
if not keep_intermediate_files
    select Sound base_original
    plus Sound base_original_mono
    plus Sound base_original_mono_44100
    plus Sound base1
    plus Sound base2
    plus Sound base3
    plus Sound base4
    plus Sound base5
    plus Sound base6
    plus Sound base7
    plus Sound base8
    plus Sound shift1
    plus Sound shift2
    plus Sound shift3
    plus Sound shift4
    plus Sound shift5
    plus Sound shift6
    plus Sound shift7
    plus Sound shift8
    plus Sound pair_1_2
    plus Sound pair_3_4
    plus Sound pair_5_6
    plus Sound pair_7_8
    plus Sound channels_1234_mixed
    plus Sound channels_5678_mixed
    Remove
endif

# Rename final result
select Sound canon_8ch_final_mix
Rename... canon_8channel_result