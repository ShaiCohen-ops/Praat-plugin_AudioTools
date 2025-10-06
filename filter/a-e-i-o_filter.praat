# ============================================================
# Praat AudioTools - a-e-i-o_filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# === Work on the currently selected Sound ===
sound = selected ("Sound")
if sound = 0 or numberOfSelected ("Sound") <> 1
    exit ("Please select exactly one Sound object first.")
endif

# Get name, duration, and sampling frequency of the original Sound
selectObject: sound
origName$ = selected$("Sound")
dur = Get duration
fs = Get sampling frequency
fs$ = fixed$ (fs, 0)

# --- Create Vocal Tracts (vowels) ---
Create Vocal Tract from phone: "a"
Create Vocal Tract from phone: "e"
Create Vocal Tract from phone: "i"
Create Vocal Tract from phone: "o"

# --- Bundle -> tier -> LPCs ---
selectObject: "VocalTract a"
plusObject: "VocalTract e"
plusObject: "VocalTract i"
plusObject: "VocalTract o"
To VocalTractTier: 0, dur, 0.5
To LPC: 0.005

# --- Filter with each LPC, resample, and rename with fs suffix ---
selectObject: sound
plusObject: "LPC a"
Filter: "no"
Rename: "VT_a"
Resample: fs, 50
Rename: "VT_a_" + fs$

selectObject: sound
plusObject: "LPC e"
Filter: "no"
Rename: "VT_e"
Resample: fs, 50
Rename: "VT_e_" + fs$

selectObject: sound
plusObject: "LPC i"
Filter: "no"
Rename: "VT_i"
Resample: fs, 50
Rename: "VT_i_" + fs$

selectObject: sound
plusObject: "LPC o"
Filter: "no"
Rename: "VT_o"
Resample: fs, 50
Rename: "VT_o_" + fs$

# --- Concatenate the four resampled results ---
selectObject: "Sound VT_a_" + fs$
plusObject: "Sound VT_e_" + fs$
plusObject: "Sound VT_i_" + fs$
plusObject: "Sound VT_o_" + fs$
Concatenate
Rename: "VT_concatenated_" + fs$
Play

# --- Keep only original + output ---
select all
minusObject: "Sound " + origName$
minusObject: "Sound VT_concatenated_" + fs$
Remove
