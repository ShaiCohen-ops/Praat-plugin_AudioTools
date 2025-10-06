# ============================================================
# Praat AudioTools - 4-Channel Canon.praat
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

# Multi-channel Canon Generator with Interactive Settings

form Multi-channel Canon Settings
    comment Base sampling rate settings:
    positive Resample_frequency 44100
    
    comment Pitch shift percentages for each channel:
    real Shift_percent_1 12.0 
    real Shift_percent_2 6.0 
    real Shift_percent_3 19.0 
    real Shift_percent_4 -5.5 
    
    comment Output options:
    boolean Keep_intermediate_files 0
    boolean Play_result 1
endform

# Validate input selection
if not selected ("Sound")
    exitScript: "Please select a Sound object first."
endif

# Calculate shift rates from percentages
shift_rate_1 = resample_frequency * (1 + (shift_percent_1/100))
shift_rate_2 = resample_frequency * (1 + (shift_percent_2/100))
shift_rate_3 = resample_frequency * (1 + (shift_percent_3/100))
shift_rate_4 = resample_frequency * (1 + (shift_percent_4/100))

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
Copy... base_for_pair1
Copy... base_for_pair3

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

# Play result if requested
if play_result
    select Sound canon_pair1
    Play
endif

# Clean up unless keep_intermediate_files is selected
if not keep_intermediate_files
    select Sound base_original
    plus Sound base_original_mono
    plus Sound base_original_mono_44100
    plus Sound base1
    plus Sound base2
    plus Sound base3
    plus Sound base4
    plus Sound base_for_pair1
    plus Sound base_for_pair3
    plus Sound shift1
    plus Sound shift2
    plus Sound shift3
    plus Sound shift4
    plus Sound canon_pair2
    plus Sound canon_pair3
    Remove
endif

# Rename the final result
select Sound canon_pair1
Rename... multichannel_canon_result