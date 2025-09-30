# --- 8-Channel Canon Settings
resample_sf = 44100

# Different shift rates for 8 channels (adjust these for desired intervals)
shift_rate_1 = 49392    ; ~+7 semitones
shift_rate_2 = 46660    ; ~+5 semitones  
shift_rate_3 = 52388    ; ~+3 semitones
shift_rate_4 = 41608    ; ~-3 semitones
shift_rate_5 = 39686    ; ~-5 semitones
shift_rate_6 = 55426    ; ~+4 semitones
shift_rate_7 = 37454    ; ~-7 semitones
shift_rate_8 = 58740    ; ~+6 semitones

# must have a Sound selected
if not selected ("Sound")
    exit Please select a Sound object first.
endif

# Get original name and create base mono
orig$ = selected$ ("Sound")
select Sound 'orig$'
Copy... base_original
Convert to mono
Resample... 'resample_sf' 50

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
Resample... 'resample_sf' 50
Rename... shift1

# Create shifted version 2  
select Sound base2
Override sampling frequency... 'shift_rate_2'
Resample... 'resample_sf' 50
Rename... shift2

# Create shifted version 3
select Sound base3
Override sampling frequency... 'shift_rate_3'
Resample... 'resample_sf' 50
Rename... shift3

# Create shifted version 4
select Sound base4
Override sampling frequency... 'shift_rate_4'
Resample... 'resample_sf' 50
Rename... shift4

# Create shifted version 5
select Sound base5
Override sampling frequency... 'shift_rate_5'
Resample... 'resample_sf' 50
Rename... shift5

# Create shifted version 6
select Sound base6
Override sampling frequency... 'shift_rate_6'
Resample... 'resample_sf' 50
Rename... shift6

# Create shifted version 7
select Sound base7
Override sampling frequency... 'shift_rate_7'
Resample... 'resample_sf' 50
Rename... shift7

# Create shifted version 8
select Sound base8
Override sampling frequency... 'shift_rate_8'
Resample... 'resample_sf' 50
Rename... shift8

# Create 4 stereo pairs (8 total channels)
# Pair 1: shift1 + shift2
select Sound shift1
plus Sound shift2
Combine to stereo
Rename... pair_1_2

# Pair 2: shift3 + shift4
select Sound shift3
plus Sound shift4
Combine to stereo
Rename... pair_3_4

# Pair 3: shift5 + shift6
select Sound shift5
plus Sound shift6
Combine to stereo
Rename... pair_5_6

# Pair 4: shift7 + shift8
select Sound shift7
plus Sound shift8
Combine to stereo
Rename... pair_7_8

# Now combine pairs to create larger multi-channel files
# Combine pair 1_2 with pair 3_4 (this will create a stereo mix, not true 4-channel)
select Sound pair_1_2
plus Sound pair_3_4
Combine to stereo
Rename... channels_1234_mixed

# Combine pair 5_6 with pair 7_8
select Sound pair_5_6
plus Sound pair_7_8
Combine to stereo
Rename... channels_5678_mixed

# Final combination - this creates the most complex mix
select Sound channels_1234_mixed
plus Sound channels_5678_mixed
Combine to stereo
Rename... canon_8ch_final_mix

# Play the final result
select Sound canon_8ch_final_mix
Play

# Clean up everything except original input and final result
# Remove all intermediate working copies
select Sound base_original
Remove
select Sound base_original_mono
Remove
select Sound base_original_mono_44100
Remove
select Sound base1
Remove
select Sound base2
Remove
select Sound base3
Remove
select Sound base4
Remove
select Sound base5
Remove
select Sound base6
Remove
select Sound base7
Remove
select Sound base8
Remove
select Sound shift1
Remove
select Sound shift2
Remove
select Sound shift3
Remove
select Sound shift4
Remove
select Sound shift5
Remove
select Sound shift6
Remove
select Sound shift7
Remove
select Sound shift8
Remove
select Sound pair_1_2
Remove
select Sound pair_3_4
Remove
select Sound pair_5_6
Remove
select Sound pair_7_8
Remove
select Sound channels_1234_mixed
Remove
select Sound channels_5678_mixed
Remove

# Keep only the original input and the final 8-channel mix
select Sound canon_8ch_final_mix
Rename... canon_8channel_result

# Final result: canon_8channel_result contains all 8 pitch-shifted versions
# mixed together into a stereo file with maximum harmonic complexity