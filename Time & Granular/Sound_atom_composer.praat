# ============================================================
# Praat AudioTools - Sound_atom_composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Added visualizations
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound Atom Composer - breaks audio into small "atoms" (grains)
#   and reorganizes them to create new textures ("clouds", "drones").
#   Uses true granular synthesis with pitch shifting, stereo panning,
#   and temporal jitter for rich, evolving soundscapes.
#
# Usage:
#   Run this script and select a folder containing audio clips.
#
# Changelog v0.3:
#   - Added comprehensive visualization
#   - Atom distribution plot (frequency vs time)
#   - Stereo field visualization
#   - Energy/spectral analysis display
#   - Play option
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form "Sound Atom Composer - True Granular"
    comment This version uses the ACTUAL AUDIO from your files.
    
    comment === Preset ===
    optionmenu Preset_style 1
        option Custom (Use settings below)
        option Time Stretch (Slow down, maintain pitch)
        option Pitch Shifted Cloud (Dense, high pitch)
        option Shuffle Texture (Randomized order)
    
    comment === Analysis ===
    positive Time_step 0.05
    positive Min_energy 30
    
    comment === Selection ===
    positive Min_freq 50
    positive Max_freq 4000
    positive Max_atoms 400
    
    comment === Transformation ===
    real Transpose_semitones 0
    boolean Randomize_order 1
    
    comment === Synthesis ===
    positive Output_duration 10.0
    positive Atom_duration_multiplier 1.5
    real Amplitude_scale 1.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

writeInfoLine: "=== Sound Atom Composer ==="
appendInfoLine: ""
appendInfoLine: "Starting True Granular Composer..."

################################################################################
# PRESET LOGIC
################################################################################

if preset_style = 2
    # Time Stretch (Slow down, maintain pitch)
    time_step = 0.05
    max_atoms = 1000
    transpose_semitones = 0
    randomize_order = 0
    output_duration = 20.0
    atom_duration_multiplier = 2.0
    
elsif preset_style = 3
    # Pitch Shifted Cloud (Dense, high pitch)
    time_step = 0.03
    max_atoms = 600
    transpose_semitones = 12
    randomize_order = 1
    output_duration = 8.0
    atom_duration_multiplier = 1.0
    
elsif preset_style = 4
    # Shuffle Texture (Randomized order)
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

appendInfoLine: "  Found ", numFiles, " WAV files"

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

selectObject: sourceBankID
sourceDuration = Get total duration
appendInfoLine: "  Source bank duration: ", fixed$(sourceDuration, 2), " s"

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

appendInfoLine: "  Source Bank created. Analyzing..."

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

appendInfoLine: ""
appendInfoLine: "Step 2: Analysis complete"
appendInfoLine: "  Atoms found: ", atom_counter
appendInfoLine: "  Time step: ", time_step, " s"
appendInfoLine: "  Min energy: ", min_energy, " dB"
appendInfoLine: "  Frequency range: ", min_freq, "-", max_freq, " Hz"

################################################################################
# STEP 3: SELECT AND SHUFFLE
################################################################################

selectObject: "Table atomDictionary"
numAtoms = Get number of rows

if randomize_order = 1
    Randomize rows
    appendInfoLine: "  Order: Randomized"
else
    appendInfoLine: "  Order: Sequential"
endif

if numAtoms > max_atoms
    numAtoms = max_atoms
    appendInfoLine: "  Using first ", numAtoms, " atoms (limited by max_atoms)"
else
    appendInfoLine: "  Using all ", numAtoms, " atoms"
endif

################################################################################
# STEP 4: TRUE GRANULAR SYNTHESIS
################################################################################

appendInfoLine: ""
appendInfoLine: "Step 3: Synthesizing (Sample Based)..."
appendInfoLine: "  Output duration: ", output_duration, " s"
appendInfoLine: "  Transpose: ", transpose_semitones, " semitones"
appendInfoLine: "  Amplitude scale: ", amplitude_scale

samplingFreq = 44100
Create Sound from formula: "Left", 1, 0, output_duration, samplingFreq, "0"
leftID = selected("Sound")

Create Sound from formula: "Right", 1, 0, output_duration, samplingFreq, "0"
rightID = selected("Sound")

playRate = 2 ^ (transpose_semitones / 12)

# Store atom placement info for visualization
for i from 1 to numAtoms
    atomOutputTime[i] = 0
    atomPan[i] = 0.5
    atomFreq[i] = 100
    atomAmp[i] = 60
endfor

for i from 1 to numAtoms
    selectObject: "Table atomDictionary"
    srcTime = Get value: i, "time"
    dur = Get value: i, "duration"
    freq = Get value: i, "frequency"
    amp = Get value: i, "amplitude"
    
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
    
    # Store for visualization
    atomOutputTime[i] = dstTime
    atomPan[i] = pan
    atomFreq[i] = freq
    atomAmp[i] = amp
    
    if dstEndL < output_duration
        selectObject: leftID
        midL = dstStartL + (effDur / 2)
        width = effDur / 4
        
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
Remove

appendInfoLine: "  Synthesis complete!"

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Sound Atom Composer: Granular Synthesis"
    
    # Source Bank Waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: sourceBankID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 1.6
    Text left: "yes", "Source Bank"
    
    # Result Waveform (Stereo)
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: finalID
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result (Stereo)"
    Text bottom: "yes", "Time (s)"
    
    # Atom Distribution (Frequency vs Time, colored by Amplitude)
    Select outer viewport: 0, 4, 2.9, 4.5
    Select inner viewport: 0.6, 3.6, 3.0, 4.4
    
    # Find min/max for scaling
    minFreq = min_freq
    maxFreq = max_freq
    minAmp = 1000
    maxAmp = 0
    
    for i to numAtoms
        if atomAmp[i] > maxAmp
            maxAmp = atomAmp[i]
        endif
        if atomAmp[i] < minAmp
            minAmp = atomAmp[i]
        endif
    endfor
    
    Axes: 0, output_duration, minFreq, maxFreq
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, output_duration, minFreq, maxFreq
    
    # Draw atoms as dots colored by amplitude
    for i to numAtoms
        # Normalize amplitude to color range
        if maxAmp > minAmp
            normAmp = (atomAmp[i] - minAmp) / (maxAmp - minAmp)
        else
            normAmp = 0.5
        endif
        
        # Color: blue (quiet) to red (loud)
        red = normAmp
        green = 0.3 + (1 - normAmp) * 0.4
        blue = 1 - normAmp
        
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        
        Paint circle (mm): dotColor$, atomOutputTime[i], atomFreq[i], 0.8
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 0, 4, 2.7, 2.9
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 2.0, "centre", 0.5, "half", "Atom Distribution (color = amplitude)"
    
    # Stereo Field (Pan vs Time)
    Select outer viewport: 4, 8, 2.9, 4.5
    Select inner viewport: 4.6, 7.6, 3.0, 4.4
    
    Axes: 0, output_duration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, output_duration, 0, 1
    
    # Draw pan positions
    for i to numAtoms
        # Color by frequency
        if maxFreq > minFreq
            normFreq = (atomFreq[i] - minFreq) / (maxFreq - minFreq)
        else
            normFreq = 0.5
        endif
        
        # Color: low freq = red, high freq = blue
        red = 1 - normFreq
        green = 0.4
        blue = normFreq
        
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        
        Paint circle (mm): dotColor$, atomOutputTime[i], atomPan[i], 0.8
    endfor
    
    # Center line (mono position)
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, output_duration, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan (L-R)"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 4, 8, 2.7, 2.9
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 6.0, "centre", 0.5, "half", "Stereo Field (color = frequency)"
    
    # Statistics and Legend
    Select outer viewport: 0, 8, 4.6, 5.2
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    # Calculate statistics
    avgFreq = 0
    for i to numAtoms
        avgFreq = avgFreq + atomFreq[i]
    endfor
    avgFreq = avgFreq / numAtoms
    
    Text: 1.0, "left", 0.3, "half", "Atoms: " + string$(numAtoms) + " | Avg Freq: " + fixed$(avgFreq, 0) + " Hz | Transpose: " + fixed$(transpose_semitones, 1) + " st | Duration: " + fixed$(output_duration, 1) + " s"
    Text: 1.0, "left", -2.7, "half", "Source: " + string$(numFiles) + " files (" + fixed$(sourceDuration, 1) + "s) | Time step: " + fixed$(time_step * 1000, 0) + " ms | Randomized: " + string$(randomize_order)
    
    Font size: 10
    Colour: "Black"
endif

################################################################################
# CLEANUP AND FINALIZE
################################################################################

selectObject: sourceBankID
plusObject: "Table atomDictionary"
Remove

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: Granular_Output"
appendInfoLine: "Duration: ", fixed$(output_duration, 2), " s"
appendInfoLine: "Total atoms placed: ", numAtoms

# === Play ===
if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    selectObject: finalID
    Play
endif

selectObject: finalID
