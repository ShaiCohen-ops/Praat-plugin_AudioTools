# ============================================================
# Praat AudioTools - Sound_atom_composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.6 (2026) - visualization QA alignment
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
# Changelog v1.3.6:
#   - VISUALIZATION ONLY: preserves the existing Source/Result, Atom Distribution,
#     and Stereo Field concept while fixing rendered spacing and axis readability.
#   - Source and Result use one shared amplitude scale; Source stays neutral grey and
#     Result keeps the script's existing blue waveform colour.
#   - Atom markers use adaptive physical-mm sizes so dense displays remain legible.
#   - Atom Distribution now zooms to the actually selected atom-frequency range
#     (with padding) instead of wasting most of the panel on an unused analysis range.
#   - Adds numeric time/frequency/pan marks, dedicated title bands, explicit colour-key
#     wording, and a larger Summary band so text cannot collide.
#   - DSP, public form, preset logic, output object name, and synthesis are unchanged.
#
# Changelog v1.3.5:
#   - PARSER FIX: renamed the temporary loop index `fi` to `fileScan`.
#     In Praat formula expressions, `fi` is a reserved token that closes
#     `if ... then ... else ... fi`, so `bankStart#[fi]` cannot be parsed
#     as vector indexing.
#   - No public form, preset, output-name, or DSP parameter changes.
#
# Changelog v1.3.4:
#   - PARSER FIX: restored compact vector indexing (`name#[i]`) everywhere.
#     The original v1.2 already used this form successfully; v1.3.2/1.3.3
#     mistakenly changed it to `name# [i]`, which this Praat build rejects
#     in scalar expressions such as `x = vector# [i]`.
#   - No public form, preset, output-name, or DSP parameter changes.
#
# Changelog v1.3.1:
#   - FIX: v1.3 used invalid `Shift times to: 0`. The command expects
#     a string option first, so current Praat stopped at runtime. v1.3.1
#     reads the numeric start time and uses `Shift times by` instead.
#
# Changelog v1.3.2:
#   - RUNTIME FIX: source-bank bookkeeping now uses explicit numeric vectors
#     (fileDur#, bankStart#, bankEnd#) with Praat vector indexing syntax.
#   - ATTEMPTED parser normalization inserted a space before [index];
#     superseded by v1.3.4 after this proved incompatible with the target Praat build.
#   - No public form, preset, output-name, or DSP parameter changes.
#
# Changelog v1.3.3:
#   - ATTEMPTED parser workaround copied vector elements to scalar
#     temporaries; superseded by v1.3.4 because the spaced vector read itself
#     still failed in the target Praat build.
#   - No public form or output-name changes.
#
# Changelog v1.3:
#   - API COMPATIBILITY: public form is byte-for-byte unchanged from v1.2.
#     Output object name remains "Granular_Output".
#   - FIX: Min_freq / Max_freq now actually control the Pitch analysis.
#     v1.2 hard-coded 75..600 Hz despite exposing defaults of 50..4000 Hz.
#   - FIX: unvoiced Pitch frames are no longer relabelled as an invented
#     100 Hz F0. Only genuinely voiced frames enter the pitch-filtered atom
#     dictionary.
#   - FIX: SourceBank order is now explicitly the alphabetical file-list
#     order even after resampling. Praat Concatenate follows Object-list
#     order, and resampled files receive newer object IDs.
#   - FIX: atoms are rejected if their forward source read would cross a
#     boundary between two input files; grains no longer splice unrelated
#     files inside the concatenated source bank.
#   - FIX: output-edge grains are clipped and rendered instead of being
#     discarded wholesale when their end reaches/passes Output_duration.
#     Negative right-channel jitter is clipped safely at time 0.
#   - FIX: Gaussian grains are edge-zeroed, eliminating the old ~0.135
#     amplitude discontinuity at nominal grain boundaries.
#   - FIX: Amplitude_scale is no longer cancelled by unconditional final
#     peak normalization. Final scaling is now a 0.99 safety ceiling only.
#   - HARDENING: Max_atoms is floored internally to an integer >= 1;
#     analysis ceiling is capped below Nyquist; SourceBank is shifted to 0.
#
# Changelog v1.2:
#   - Added a "Folder" form field (mirrors Timbral_Similarity_Browser):
#     type a path, or leave it blank to fall back to the folder-selection
#     dialog. The path is whitespace- and trailing-slash-trimmed, then a
#     single separator is re-added; cancelling the dialog exits cleanly.
#
# Changelog v1.1:
#   - Force each loaded file to mono before concatenation. Stereo or
#     mixed-channel inputs previously crashed Concatenate and made the
#     object() grain read ambiguous. The stereo image is produced by
#     per-grain panning, so a mono source bank is the correct input.
#   - Visualization: added explicit "Axes: 0,1,0,1" to the title, both
#     panel subtitles, and the statistics block. Without it those text
#     panels inherited the previous panel's world coordinates, pushing
#     the stats second line (and the atom-distribution subtitle) off
#     screen. Coordinates re-expressed in 0..1 so text is duration-
#     independent.
#
# Changelog v1.0:
#   - Fixed object reference syntax (now uses object() function)
#   - Added preset name for display
#   - Added safety check for zero atoms
#   - Improved error handling
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form "Sound Atom Composer - True Granular"
    comment This version uses the ACTUAL AUDIO from your files.
    
    comment === Audio Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
    
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
    preset$ = "Time Stretch"
    
elsif preset_style = 3
    # Pitch Shifted Cloud (Dense, high pitch)
    time_step = 0.03
    max_atoms = 600
    transpose_semitones = 12
    randomize_order = 1
    output_duration = 8.0
    atom_duration_multiplier = 1.0
    preset$ = "Pitch Shifted Cloud"
    
elsif preset_style = 4
    # Shuffle Texture (Randomized order)
    time_step = 0.1
    max_atoms = 200
    transpose_semitones = -5
    randomize_order = 1
    output_duration = 10.0
    atom_duration_multiplier = 1.0
    preset$ = "Shuffle Texture"
    
else
    # Custom
    preset$ = "Custom"
endif

# Internal validation / canonicalization (public parameters unchanged)
if min_freq >= max_freq
    exitScript: "Min_freq must be smaller than Max_freq."
endif
maxAtomsInt = floor(max_atoms)
if maxAtomsInt < 1
    maxAtomsInt = 1
endif

writeInfoLine: "=== Sound Atom Composer ==="
appendInfoLine: "Preset: ", preset$
appendInfoLine: ""
appendInfoLine: "Starting True Granular Composer..."

################################################################################
# STEP 1: LOAD AND PREPARE SOURCE BANK
################################################################################

appendInfoLine: ""
appendInfoLine: "Step 1: Loading Source Audio..."

# --- FOLDER DISCOVERY ---
# Mirrors Timbral_Similarity_Browser: use the typed Folder path, or fall
# back to a dialog when it is left blank. Whitespace and trailing slashes
# are trimmed first, then a single separator is re-added for the *.wav glob
# (and for "+ fileName$" in the load loop below).
input_folder$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
input_folder$ = replace_regex$(input_folder$, "[\\/]+$", "", 0)

if input_folder$ == ""
    input_folder$ = chooseDirectory$: "Select folder with WAV files"
    input_folder$ = replace_regex$(input_folder$, "[\\/]+$", "", 0)
endif

if input_folder$ == ""
    exitScript: "Cancelled. Please supply a valid folder path."
endif

if right$(input_folder$, 1) <> "/" and right$(input_folder$, 1) <> "\"
    if index(input_folder$, "\") > 0
        input_folder$ = input_folder$ + "\"
    else
        input_folder$ = input_folder$ + "/"
    endif
endif

appendInfoLine: "  Loading from: ", input_folder$

# 1. Create List of Files
Create Strings as file list: "fileList", input_folder$ + "*.wav"
numFiles = Get number of strings
if numFiles = 0
    removeObject: "Strings fileList"
    exitScript: "No WAV files found in the selected folder."
endif

appendInfoLine: "  Found ", numFiles, " WAV files"

# 2. Track Loaded IDs
Create Table with column names: "loadedSounds", numFiles, "id"

# 3. Load Loop
for i to numFiles
    selectObject: "Strings fileList"
    fileName$ = Get string: i
    Read from file: input_folder$ + fileName$
    soundID = selected("Sound")

    # Force mono: stereo or mixed-channel files would crash Concatenate
    # and make the object() grain read ambiguous. The stereo image is
    # built later from per-grain panning, so a mono source bank is correct.
    nch = Get number of channels
    if nch > 1
        Convert to mono
        monoID = selected("Sound")
        removeObject: soundID
        soundID = monoID
    endif

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

# 5. Find max sample rate across all files
maxSR = 0
for i to nRows
    selectObject: id_list#[i]
    thisSR = Get sampling frequency
    if thisSR > maxSR
        maxSR = thisSR
    endif
endfor

# 6. Resample any files that don't match maxSR
fileDur# = zero#(nRows)
bankStart# = zero#(nRows)
bankEnd# = zero#(nRows)

for i to nRows
    selectObject: id_list#[i]
    thisSR = Get sampling frequency
    if thisSR <> maxSR
        Resample: maxSR, 50
        newID = selected("Sound")
        removeObject: id_list#[i]
        id_list#[i] = newID
    endif
    selectObject: id_list#[i]
    fileDur#[i] = Get total duration
endfor

# Requested frequency range, capped below Nyquist.
analysisPitchFloor = min_freq
analysisPitchCeiling = min(max_freq, 0.49 * maxSR)
if analysisPitchCeiling <= analysisPitchFloor
    for i to nRows
        removeObject: id_list#[i]
    endfor
    removeObject: "Strings fileList", "Table loadedSounds"
    exitScript: "Requested pitch range is above the usable Nyquist range for these files."
endif

# 7. Build SourceBank in explicit file-list order.
# Resampling can create newer object IDs, while Concatenate follows Object-list
# order rather than selection order. Fresh copies make intended order explicit.
bankStart#[1] = 0
bankEnd#[1] = fileDur#[1]
selectObject: id_list#[1]
bankID = Copy: "bank_accum"

for i from 2 to nRows
    bankStart#[i] = bankEnd#[i - 1]
    bankEnd#[i] = bankStart#[i] + fileDur#[i]

    selectObject: id_list#[i]
    bankPart = Copy: "bank_part"

    selectObject: bankID
    plusObject: bankPart
    Concatenate
    newBank = selected("Sound")
    removeObject: bankID, bankPart
    bankID = newBank
endfor

# 8. Rename / zero-base the bank for time-addressed object() reads.
selectObject: bankID
Rename: "SourceBankTemp"
sourceBankID = selected("Sound")
bankStartTime = Get start time
Shift times by: -bankStartTime

sourceBankStr$ = string$(sourceBankID)

selectObject: sourceBankID
sourceDuration = Get total duration
appendInfoLine: "  Source bank duration: ", fixed$(sourceDuration, 2), " s"
appendInfoLine: "  Effective pitch analysis: ", fixed$(analysisPitchFloor, 1),
    ... "-", fixed$(analysisPitchCeiling, 1), " Hz"

# 10. Cleanup Individual Files
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
To Intensity: analysisPitchFloor, time_step, "yes"
intensityID = selected("Intensity")

selectObject: sourceBankID
To Pitch: time_step, analysisPitchFloor, analysisPitchCeiling
pitchID = selected("Pitch")

Create Table with column names: "atomDictionary", 0, "time duration frequency amplitude"

selectObject: pitchID
numFrames = Get number of frames
atom_counter = 0

atomDurRequested = max(time_step * atom_duration_multiplier, 2 / maxSR)

for iframe to numFrames
    selectObject: pitchID
    time = Get time from frame: iframe
    f0 = Get value in frame: iframe, "Hertz"

    voiced = 1
    if f0 = undefined
        voiced = 0
    endif

    if voiced
        selectObject: intensityID
        energy = Get value at time: time, "Cubic"

        # Synthesis reads forward from srcTime by atomDurRequested. Reject
        # candidates whose read would cross from one source file into another.
        fileIndex = 0
        fileEnd = 0
        for fileScan from 1 to nRows
            candidateStart = bankStart#[fileScan]
            candidateEnd = bankEnd#[fileScan]
            if time >= candidateStart
                if time < candidateEnd
                    fileIndex = fileScan
                    fileEnd = candidateEnd
                endif
            endif
        endfor

        insideOneFile = 0
        if fileIndex > 0
            sourceReadEnd = time + atomDurRequested
            if sourceReadEnd <= fileEnd + 1e-12
                insideOneFile = 1
            endif
        endif

        if insideOneFile and energy > min_energy
            if f0 >= min_freq and f0 <= max_freq
                selectObject: "Table atomDictionary"
                Append row
                atom_counter = atom_counter + 1
                row = Get number of rows

                Set numeric value: row, "time", time
                Set numeric value: row, "duration", atomDurRequested
                Set numeric value: row, "frequency", f0
                Set numeric value: row, "amplitude", energy
            endif
        endif
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

# Safety check: ensure we have atoms to work with
if numAtoms = 0
    removeObject: sourceBankID
    removeObject: "Table atomDictionary"
    exitScript: "No atoms found matching criteria. Try lowering min_energy or adjusting frequency range."
endif

if randomize_order = 1
    Randomize rows
    appendInfoLine: "  Order: Randomized"
else
    appendInfoLine: "  Order: Sequential"
endif

if numAtoms > maxAtomsInt
    numAtoms = maxAtomsInt
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

selectObject: sourceBankID
samplingFreq = Get sampling frequency
Create Sound from formula: "Left", 1, 0, output_duration, samplingFreq, "0"
leftID = selected("Sound")

Create Sound from formula: "Right", 1, 0, output_duration, samplingFreq, "0"
rightID = selected("Sound")

playRate = 2 ^ (transpose_semitones / 12)

# Store atom placement info for visualization
gaussianEdge = exp(-2)

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

    atomOutputTime [i] = dstTime
    atomPan [i] = pan
    atomFreq [i] = freq
    atomAmp [i] = amp

    # Render the intersection with the output domain instead of discarding
    # the whole atom if only its tail exceeds Output_duration.
    renderStartL = max(0, dstStartL)
    renderEndL = min(output_duration, dstEndL)
    if renderEndL - renderStartL >= 2 / samplingFreq
        renderDurL = renderEndL - renderStartL
        midL = (renderStartL + renderEndL) / 2
        widthL = renderDurL / 4

        selectObject: leftID
        cmd$ = "self + " + fixed$(gainL, 6)
        cmd$ = cmd$ + " * object(" + sourceBankStr$ + ", " + fixed$(srcTime, 9) + " + (x - " + fixed$(dstStartL, 9) + ") * " + fixed$(playRate, 9) + ") "
        cmd$ = cmd$ + " * ((exp(-0.5 * ((x - " + fixed$(midL, 9) + ") / " + fixed$(widthL, 9) + ")^2) - " + fixed$(gaussianEdge, 12) + ") / (1 - " + fixed$(gaussianEdge, 12) + "))"
        Formula (part): renderStartL, renderEndL, 1, 1, cmd$
    endif

    renderStartR = max(0, dstStartR)
    renderEndR = min(output_duration, dstEndR)
    if renderEndR - renderStartR >= 2 / samplingFreq
        renderDurR = renderEndR - renderStartR
        midR = (renderStartR + renderEndR) / 2
        widthR = renderDurR / 4

        selectObject: rightID
        cmd$ = "self + " + fixed$(gainR, 6)
        cmd$ = cmd$ + " * object(" + sourceBankStr$ + ", " + fixed$(srcTime, 9) + " + (x - " + fixed$(dstStartR, 9) + ") * " + fixed$(playRate, 9) + ") "
        cmd$ = cmd$ + " * ((exp(-0.5 * ((x - " + fixed$(midR, 9) + ") / " + fixed$(widthR, 9) + ")^2) - " + fixed$(gaussianEdge, 12) + ") / (1 - " + fixed$(gaussianEdge, 12) + "))"
        Formula (part): renderStartR, renderEndR, 1, 1, cmd$
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

finalPeak = Get absolute extremum: 0, 0, "Sinc70"
if finalPeak > 0.99
    Scale peak: 0.99
endif

selectObject: leftID
plusObject: rightID
Remove

appendInfoLine: "  Synthesis complete!"

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    Erase all

    # Shared display amplitude: Source and Result are directly comparable.
    selectObject: sourceBankID
    sourceDisplayPeak = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: finalID
    resultDisplayPeak = Get absolute extremum: 0, 0, "Sinc70"
    displayPeak = max(sourceDisplayPeak, resultDisplayPeak)
    if displayPeak <= 0
        displayPeak = 1
    endif
    displayPeak = displayPeak * 1.05

    # Title
    Select outer viewport: 0, 8, 0.10, 0.48
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "Sound Atom Composer: " + preset$

    # Source Bank Waveform
    Select outer viewport: 0.15, 7.85, 0.62, 1.58
    Select inner viewport: 0.70, 7.62, 0.72, 1.47
    selectObject: sourceBankID
    Colour: "{0.62, 0.62, 0.62}"
    Draw: 0, 0, -displayPeak, displayPeak, "no", "Curve"
    Axes: 0, sourceDuration, -displayPeak, displayPeak
    Colour: "{0.28, 0.28, 0.28}"
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Select outer viewport: 0.15, 7.85, 0.62, 1.58
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.28, 0.28, 0.28}"
    Text left: "yes", "Source Bank"

    # Result Waveform (Stereo)
    Select outer viewport: 0.15, 7.85, 1.78, 2.78
    Select inner viewport: 0.70, 7.62, 1.88, 2.61
    selectObject: finalID
    Colour: "{0.30, 0.60, 0.80}"
    Draw: 0, 0, -displayPeak, displayPeak, "no", "Curve"
    Axes: 0, output_duration, -displayPeak, displayPeak
    Colour: "{0.28, 0.28, 0.28}"
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.15, 7.85, 1.78, 2.78
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.28, 0.28, 0.28}"
    Text left: "yes", "Result (Stereo)"

    # Shared marker-size rule in physical Picture units.
    if numAtoms <= 120
        atomMarkerMm = 1.15
    elsif numAtoms <= 250
        atomMarkerMm = 0.95
    elsif numAtoms <= 500
        atomMarkerMm = 0.78
    else
        atomMarkerMm = 0.64
    endif

    # Find actual display ranges and amplitudes.
    minFreqActual = 1e30
    maxFreqActual = -1e30
    minAmp = 1e30
    maxAmp = -1e30
    for i to numAtoms
        if atomFreq [i] < minFreqActual
            minFreqActual = atomFreq [i]
        endif
        if atomFreq [i] > maxFreqActual
            maxFreqActual = atomFreq [i]
        endif
        if atomAmp [i] < minAmp
            minAmp = atomAmp [i]
        endif
        if atomAmp [i] > maxAmp
            maxAmp = atomAmp [i]
        endif
    endfor

    freqSpan = maxFreqActual - minFreqActual
    if freqSpan <= 0
        freqPad = max(10, 0.05 * max(1, minFreqActual))
    else
        freqPad = max(10, 0.10 * freqSpan)
    endif
    minFreqViz = max(min_freq, minFreqActual - freqPad)
    maxFreqViz = min(max_freq, maxFreqActual + freqPad)
    if maxFreqViz <= minFreqViz
        minFreqViz = max(min_freq, minFreqActual - 10)
        maxFreqViz = min(max_freq, maxFreqActual + 10)
    endif
    if maxFreqViz <= minFreqViz
        maxFreqViz = minFreqViz + 1
    endif

    # Lower-panel title bands are separate from both data and x-axis labels.
    Select outer viewport: 0.15, 3.90, 3.04, 3.28
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.34, 0.34, 0.34}"
    Text: 0.5, "centre", 0.5, "half", "Atom Distribution  -  colour = amplitude (quiet to loud)"

    Select outer viewport: 4.10, 7.85, 3.04, 3.28
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.34, 0.34, 0.34}"
    Text: 0.5, "centre", 0.5, "half", "Stereo Field  -  colour = frequency (low to high)"

    # Atom Distribution (Frequency vs Time, colored by Amplitude)
    Select outer viewport: 0.15, 3.90, 3.30, 5.25
    Select inner viewport: 0.72, 3.66, 3.43, 5.02
    Axes: 0, output_duration, minFreqViz, maxFreqViz
    Paint rectangle: "{0.975, 0.975, 0.975}", 0, output_duration, minFreqViz, maxFreqViz

    for i to numAtoms
        if maxAmp > minAmp
            normAmp = (atomAmp [i] - minAmp) / (maxAmp - minAmp)
        else
            normAmp = 0.5
        endif
        red = normAmp
        green = 0.3 + (1 - normAmp) * 0.4
        blue = 1 - normAmp
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$, atomOutputTime [i], atomFreq [i], atomMarkerMm
    endfor

    Colour: "{0.28, 0.28, 0.28}"
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 5, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # Stereo Field (Pan vs Time, colored by Frequency)
    Select outer viewport: 4.10, 7.85, 3.30, 5.25
    Select inner viewport: 4.67, 7.61, 3.43, 5.02
    Axes: 0, output_duration, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.975}", 0, output_duration, 0, 1

    for i to numAtoms
        if maxFreqActual > minFreqActual
            normFreq = (atomFreq [i] - minFreqActual) / (maxFreqActual - minFreqActual)
        else
            normFreq = 0.5
        endif
        red = 1 - normFreq
        green = 0.4
        blue = normFreq
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$, atomOutputTime [i], atomPan [i], atomMarkerMm
    endfor

    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: 0, 0.5, output_duration, 0.5
    Solid line

    Colour: "{0.28, 0.28, 0.28}"
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Pan (L-R)"
    Text bottom: "yes", "Time (s)"

    # Summary: dedicated band with enough physical line spacing.
    avgFreq = 0
    for i to numAtoms
        avgFreq = avgFreq + atomFreq [i]
    endfor
    avgFreq = avgFreq / numAtoms

    Select outer viewport: 0.30, 7.70, 5.48, 6.42
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.35}"
    Font size: 7.5
    Text: 0.02, "left", 0.80, "half", "Summary"
    Font size: 6.8
    Text: 0.02, "left", 0.50, "half", "Atoms: " + string$(numAtoms) + " | Avg Freq: " + fixed$(avgFreq, 0) + " Hz | Transpose: " + fixed$(transpose_semitones, 1) + " st | Duration: " + fixed$(output_duration, 1) + " s"
    Text: 0.02, "left", 0.18, "half", "Source: " + string$(numFiles) + " files (" + fixed$(sourceDuration, 1) + " s) | Analysis: " + fixed$(min_freq, 0) + "-" + fixed$(max_freq, 0) + " Hz | Time step: " + fixed$(time_step * 1000, 0) + " ms | Randomized: " + string$(randomize_order)

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
appendInfoLine: "Preset: ", preset$
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