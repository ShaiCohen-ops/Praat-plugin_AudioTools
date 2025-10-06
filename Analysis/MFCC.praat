# ============================================================
# Praat AudioTools - MFCC.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Praat script to extract MFCC from a selected sound and create a table in Objects window

# Get the selected sound object
sound = selected("Sound")
sound_name$ = selected$("Sound")

# Get sound duration
selectObject: sound
sound_duration = Get total duration

# Extract MFCC (12 coefficients)
num_coefficients = 12
selectObject: sound
To MFCC: num_coefficients, 0.015, 0.005, 100, 100, 0.0
mfcc = selected("MFCC")

# Get number of frames and time step
selectObject: mfcc
num_frames = Get number of frames
time_step = Get time step

# Adjust num_frames to match sound duration
expected_frames = floor(sound_duration / time_step) + 1
if num_frames > expected_frames
    num_frames = expected_frames
endif

# Create a table to store frame times and MFCC coefficients
Create Table with column names: "MFCC_Table", num_frames, "FrameTime C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12"
table = selected("Table")

# Fill the table with frame times and MFCC coefficients
selectObject: mfcc
To Matrix
matrix = selected("Matrix")
for frame from 1 to num_frames
    frame_time = (frame - 1) * time_step
    selectObject: table
    Set numeric value: frame, "FrameTime", frame_time
    for coef from 1 to num_coefficients
        selectObject: matrix
        if frame <= num_frames
            coef_value = Get value in cell: coef, frame
        else
            coef_value = 0
        endif
        selectObject: table
        if coef_value <> undefined
            Set numeric value: frame, "C" + string$(coef), coef_value
        else
            Set numeric value: frame, "C" + string$(coef), 0
        endif
    endfor
endfor

# Clean up: remove MFCC and Matrix objects, keep table
selectObject: mfcc
plusObject: matrix
Remove

# Reselect the original sound
selectObject: sound

# Inform user
writeInfoLine: "MFCC extraction complete. Table 'MFCC_Table' created in Objects window."