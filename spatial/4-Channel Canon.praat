# --- Multi-channel Canon Settings
resample_sf = 44100

# Different shift rates for each channel
shift_rate_1 = 49392
shift_rate_2 = 46660
shift_rate_3 = 52388
shift_rate_4 = 41608

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
Copy... base_for_pair1
Copy... base_for_pair3

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

# Create stereo pairs
select Sound base_for_pair1
plus Sound shift1
Combine to stereo
Rename... canon_pair1

select Sound shift2
plus Sound shift3
Combine to stereo
Rename... canon_pair2

select Sound shift4
plus Sound base_for_pair3
Combine to stereo
Rename... canon_pair3

# Play first result
select Sound canon_pair1
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
select Sound base_for_pair1
Remove
select Sound base_for_pair3
Remove
select Sound shift1
Remove
select Sound shift2
Remove
select Sound shift3
Remove
select Sound shift4
Remove
select Sound canon_pair2
Remove
select Sound canon_pair3
Remove

# Rename the final result for clarity
select Sound canon_pair1
Rename... multichannel_canon_result