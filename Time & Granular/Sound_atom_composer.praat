# ============================================================
# Praat AudioTools - Sound_atom_composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   It breaks audio into small "atoms" (grains) and reorganizes them to create new textures ("clouds", "drones").
#
# Usage:
#   Run this script and select a folder containing audio clips.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form "Sound Atom Composer - True Granular"
    comment This version uses the ACTUAL AUDIO from your files.
    
    # PRESET SELECTOR
    optionmenu Preset_style: 1
        option Custom (Use settings below)
        option Time Stretch (Slow down, maintain pitch)
        option Pitch Shifted Cloud (Dense, high pitch)
        option Shuffle Texture (Randomized order)
    
    comment --------------------------------------------------------
    comment CUSTOM PARAMETERS
    comment --------------------------------------------------------
    
    comment Analysis:
    positive Time_step 0.05
    positive Min_energy 30
    
    comment Selection:
    positive Min_freq 50
    positive Max_freq 4000
    positive Max_atoms 400
    
    comment Transformation:
    real Transpose_semitones 0
    boolean Randomize_order 1
    
    comment Synthesis:
    positive Output_duration 10.0
    positive Atom_duration_multiplier 1.5
    real Amplitude_scale 1.0
endform

clearinfo
appendInfoLine: "Starting True Granular Composer..."

################################################################################
# PRESET LOGIC
################################################################################

if preset_style$ == "Time Stretch (Slow down, maintain pitch)"
    time_step = 0.05
    max_atoms = 1000
    transpose_semitones = 0
    randomize_order = 0
    output_duration = 20.0
    atom_duration_multiplier = 2.0
    
elif preset_style$ == "Pitch Shifted Cloud (Dense, high pitch)"
    time_step = 0.03
    max_atoms = 600
    transpose_semitones = 12
    randomize_order = 1
    output_duration = 8.0
    atom_duration_multiplier = 1.0
    
elif preset_style$ == "Shuffle Texture (Randomized order)"
    time_step = 0.1
    max_atoms = 200
    transpose_semitones = -5
    randomize_order = 1
    output_duration = 10.0
    atom_duration_multiplier = 1.0
endif

################################################################################
# STEP 1: LOAD AND PREPARE SOURCE BANK
################################################################################

appendInfoLine: ""
appendInfoLine: "Step 1: Loading Source Audio..."

input_folder$ = chooseDirectory$: "Select folder with WAV files"
if input_folder$ = ""
    exitScript: "Cancelled."
endif

# 1. Create List of Files
Create Strings as file list: "fileList", input_folder$ + "/*.wav"
numFiles = Get number of strings
if numFiles = 0
    exitScript: "No WAV files found."
endif

# 2. Track Loaded IDs
Create Table with column names: "loadedSounds", numFiles, "id"

# 3. Load Loop
for i to numFiles
    selectObject: "Strings fileList"
    fileName$ = Get string: i
    Read from file: input_folder$ + "/" + fileName$
    soundID = selected("Sound")
    
    selectObject: "Table loadedSounds"
    Set numeric value: i, "id", soundID
endfor

# 4. Read IDs into memory (Robust Selection Fix)
selectObject: "Table loadedSounds"
nRows = Get number of rows
id_list# = zero# (nRows)
for i to nRows
    id_list#[i] = Get value: i, "id"
endfor

# 5. Select sounds
for i to nRows
    currentID = id_list#[i]
    if i = 1
        selectObject: currentID
    else
        plusObject: currentID
    endif
endfor

# 6. Concatenate and Rename to a Safe Identifier
Concatenate
Rename: "SourceBankTemp"
sourceBankID = selected("Sound")

# 7. Cleanup Individual Files
for i to nRows
    currentID = id_list#[i]
    if i = 1
        selectObject: currentID
    else
        plusObject: currentID
    endif
endfor
Remove

selectObject: "Strings fileList"
plusObject: "Table loadedSounds"
Remove

appendInfoLine: "Source Bank created. Analyzing..."

################################################################################
# STEP 2: ANALYZE SOURCE BANK
################################################################################

selectObject: sourceBankID
To Intensity: 75, time_step, "yes"
intensityID = selected("Intensity")

selectObject: sourceBankID
To Pitch: time_step, 75, 600
pitchID = selected("Pitch")

Create Table with column names: "atomDictionary", 0, "time duration frequency amplitude"

selectObject: pitchID
numFrames = Get number of frames
atom_counter = 0

for iframe to numFrames
    selectObject: pitchID
    time = Get time from frame: iframe
    f0 = Get value in frame: iframe, "Hertz"
    
    if f0 = undefined
        f0 = 100 
    endif
    
    selectObject: intensityID
    energy = Get value at time: time, "Cubic"
    
    if energy > min_energy and f0 >= min_freq and f0 <= max_freq
        selectObject: "Table atomDictionary"
        Append row
        atom_counter = atom_counter + 1
        row = Get number of rows
        
        Set numeric value: row, "time", time
        Set numeric value: row, "duration", time_step * atom_duration_multiplier
        Set numeric value: row, "frequency", f0
        Set numeric value: row, "amplitude", energy
    endif
endfor

selectObject: intensityID
plusObject: pitchID
Remove

appendInfoLine: "Analysis complete. Atoms found: ", atom_counter

################################################################################
# STEP 3: SELECT AND SHUFFLE
################################################################################

selectObject: "Table atomDictionary"
numAtoms = Get number of rows

if randomize_order = 1
    Randomize rows
endif

if numAtoms > max_atoms
    numAtoms = max_atoms
endif

################################################################################
# STEP 4: TRUE GRANULAR SYNTHESIS
################################################################################

appendInfoLine: ""
appendInfoLine: "Step 4: Synthesizing (Sample Based)..."

samplingFreq = 44100
Create Sound from formula: "Left", 1, 0, output_duration, samplingFreq, "0"
leftID = selected("Sound")

Create Sound from formula: "Right", 1, 0, output_duration, samplingFreq, "0"
rightID = selected("Sound")

playRate = 2 ^ (transpose_semitones / 12)

for i from 1 to numAtoms
    selectObject: "Table atomDictionary"
    srcTime = Get value: i, "time"
    dur = Get value: i, "duration"
    
    dstTime = (i - 1) * (output_duration / numAtoms)
    jitter = randomGauss(0, 0.01)
    
    dstStartL = dstTime
    dstStartR = dstTime + jitter
    
    effDur = dur / playRate
    
    dstEndL = dstStartL + effDur
    dstEndR = dstStartR + effDur
    
    pan = randomUniform(0, 1)
    gainL = (1 - pan) * amplitude_scale
    gainR = pan * amplitude_scale
    
    if dstEndL < output_duration
        selectObject: leftID
        midL = dstStartL + (effDur / 2)
        width = effDur / 4
        
        # --- FORMULA FIX ---
        # We use Sound_SourceBankTemp(time) instead of object("SourceBankTemp", time)
        # This bypasses the string parser issues.
        # We also use fixed$() to prevent scientific notation confusion.
        
        cmd$ = "self + " + fixed$(gainL, 6) 
        cmd$ = cmd$ + " * Sound_SourceBankTemp(" + fixed$(srcTime, 6) + " + (x - " + fixed$(dstStartL, 6) + ") * " + fixed$(playRate, 6) + ") "
        cmd$ = cmd$ + " * exp(-0.5 * ((x - " + fixed$(midL, 6) + ") / " + fixed$(width, 6) + ")^2)"
        
        Formula (part): dstStartL, dstEndL, 1, 1, cmd$
    endif

    if dstEndR < output_duration
        selectObject: rightID
        midR = dstStartR + (effDur / 2)
        width = effDur / 4
        
        cmd$ = "self + " + fixed$(gainR, 6) 
        cmd$ = cmd$ + " * Sound_SourceBankTemp(" + fixed$(srcTime, 6) + " + (x - " + fixed$(dstStartR, 6) + ") * " + fixed$(playRate, 6) + ") "
        cmd$ = cmd$ + " * exp(-0.5 * ((x - " + fixed$(midR, 6) + ") / " + fixed$(width, 6) + ")^2)"
        
        Formula (part): dstStartR, dstEndR, 1, 1, cmd$
    endif
    
    if i mod 50 = 0
        appendInfoLine: "  Atom ", i, " / ", numAtoms
    endif
endfor

selectObject: leftID
plusObject: rightID
Combine to stereo
Rename: "Granular_Output"
finalID = selected("Sound")

Scale peak: 0.99

selectObject: leftID
plusObject: rightID
plusObject: sourceBankID
plusObject: "Table atomDictionary"
Remove

selectObject: finalID
Play

appendInfoLine: "Done! Created True Granular Texture."