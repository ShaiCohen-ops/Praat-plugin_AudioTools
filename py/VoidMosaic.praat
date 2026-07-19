# ============================================================
# Praat AudioTools - VoidMosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5 (2026) - Grain schedule covers target; register preference-bounded; honest pitch CSV; memory-safe void search
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Void Mosaic.
#
#   Combines the spatial negative-space mapping of the Void Sieve
#   with the real audio extraction of the Corpus Mosaic. Charts deep
#   acoustic voids in a 6-D feature space (RMS, centroid, flatness,
#   rolloff, ZCR, F0), then for each void selects the nearest real
#   corpus grain in that full 6-D space and nudges it TOWARD the void
#   along two axes -- pitch (folded toward the chosen register, as far as the
#   Max Pitch Shift limit allows) and loudness. The four spectral axes shape
#   selection, not mutation; the Matter Map plots the selected void targets,
#   not re-measured post-mutation grains.
#
# Python engine: void_mosaic_engine.py
# ============================================================

form "Latent Void Mosaic v1.5"
    comment ── Corpus Configuration ──
    comment (Leave blank to pick a folder with a dialog)
    sentence Corpus_folder 
    
    comment ── Sieve & Engine Parameters ──
    optionmenu Preset: 2
        option Custom Settings
        option Standard Mosaic (10 sec)
        option Deep Drone Mutation (30 sec)
        option Micro-Glitch Cloud (5 sec)
        option Extreme Warping (15 sec)
        option Sparse Rested Field (20 sec)
        
    positive Target_Duration_s 10.0
    positive Grain_Duration_ms 250
    real Overlap_percent 50.0
    real Length_Jitter_percent 0.0
    
    comment ── Mutation Constraints ──
    comment (Maximum allowed pitch-shift in semitones before clipping)
    real Max_pitch_shift_semitones 24.0
    
    comment ── Articulation & Spacing ──
    comment (Rest probability: 0.0 = no rests, 1.0 = all silence)
    real Rest_probability 0.0
    comment (Void spacing: min feature-space distance between voids)
    positive Void_spacing 2.0
    comment (Source variety: 0 = allow repeats, 1 = strongly diversify)
    real Source_variety 1.0
    
    comment ── Preferred Pitch Register (folded, subject to Max Pitch Shift) ──
    optionmenu Vocal_Register: 5
        option Bass (E2 - E4)
        option Tenor (C3 - C5)
        option Alto (F3 - F5)
        option Soprano (C4 - C6)
        option Full Range (50-2000 Hz)
    
    comment ── Stereo ──
    boolean Stereo_output 1
    optionmenu Pan_strategy: 1
        option Random per grain
        option Spectral centroid -> L/R
        option Alternate L/R
    real Stereo_width 0.85
    
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- FOLDER DISCOVERY ----
corpusDir$ = replace_regex$(corpus_folder$, "^[ \t]*|[ \t]*$", "", 0)
corpusDir$ = replace_regex$(corpusDir$, "[\\/]+$", "", 0)

if corpusDir$ == ""
    corpusDir$ = chooseFolder$: "Select the Corpus folder (audio files to mutate)"
    corpusDir$ = replace_regex$(corpusDir$, "[\\/]+$", "", 0)
endif

if corpusDir$ == ""
    exitScript: "Operation cancelled. Please supply a valid Corpus folder path."
endif

# ---- PRESET EVALUATION ----
if preset = 2
    target_Duration_s = 10.0
    grain_Duration_ms = 250
    overlap_percent = 50.0
    length_Jitter_percent = 10.0
    max_pitch_shift_semitones = 24.0
    rest_probability = 0.0
    void_spacing = 2.0
    source_variety = 1.0
    presetName$ = "Standard Mosaic"
elsif preset = 3
    target_Duration_s = 30.0
    grain_Duration_ms = 800
    overlap_percent = 75.0
    length_Jitter_percent = 5.0
    max_pitch_shift_semitones = 36.0
    rest_probability = 0.0
    void_spacing = 1.5
    source_variety = 0.6
    presetName$ = "Deep Drone Mutation"
elsif preset = 4
    target_Duration_s = 5.0
    grain_Duration_ms = 50
    overlap_percent = 15.0
    length_Jitter_percent = 40.0
    max_pitch_shift_semitones = 12.0
    rest_probability = 0.1
    void_spacing = 2.5
    source_variety = 1.0
    presetName$ = "Micro-Glitch Cloud"
elsif preset = 5
    target_Duration_s = 15.0
    grain_Duration_ms = 150
    overlap_percent = 50.0
    length_Jitter_percent = 25.0
    max_pitch_shift_semitones = 60.0
    rest_probability = 0.0
    void_spacing = 3.0
    source_variety = 1.0
    presetName$ = "Extreme Warping"
elsif preset = 6
    target_Duration_s = 20.0
    grain_Duration_ms = 400
    overlap_percent = 40.0
    length_Jitter_percent = 30.0
    max_pitch_shift_semitones = 24.0
    rest_probability = 0.35
    void_spacing = 2.5
    source_variety = 1.0
    presetName$ = "Sparse Rested Field"
else
    presetName$ = "Custom"
endif

# ---- REGISTER -> PITCH RANGE (octave folding) ----
if vocal_Register = 1
    minPitchHz = 82
    maxPitchHz = 330
    registerName$ = "Bass"
elsif vocal_Register = 2
    minPitchHz = 131
    maxPitchHz = 523
    registerName$ = "Tenor"
elsif vocal_Register = 3
    minPitchHz = 175
    maxPitchHz = 698
    registerName$ = "Alto"
elsif vocal_Register = 4
    minPitchHz = 262
    maxPitchHz = 1047
    registerName$ = "Soprano"
else
    minPitchHz = 50
    maxPitchHz = 2000
    registerName$ = "Full Range"
endif

# Parameter Safety
if target_Duration_s < 0.1
    target_Duration_s = 0.1
endif
if overlap_percent < 0.0
    overlap_percent = 0.0
endif
if overlap_percent > 95.0
    overlap_percent = 95.0
endif
if rest_probability < 0.0
    rest_probability = 0.0
endif
if rest_probability > 1.0
    rest_probability = 1.0
endif
if source_variety < 0.0
    source_variety = 0.0
endif
if source_variety > 1.0
    source_variety = 1.0
endif
if max_pitch_shift_semitones < 0.0
    max_pitch_shift_semitones = 0.0
endif
if length_Jitter_percent < 0.0
    length_Jitter_percent = 0.0
endif
if length_Jitter_percent > 100.0
    length_Jitter_percent = 100.0
endif
if stereo_width < 0.0
    stereo_width = 0.0
endif
if stereo_width > 1.0
    stereo_width = 1.0
endif

# ---- PYTHON ENVIRONMENT DISCOVERY ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/void_mosaic_engine.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/void_mosaic_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Missing engine component void_mosaic_engine.py"
endif

tempWav$     = temporaryDirectory$ + "/temp_vm.wav"
tempCsv$     = temporaryDirectory$ + "/temp_vm.csv"
tempStats$   = temporaryDirectory$ + "/temp_vm_stats.txt"
tempMap$     = temporaryDirectory$ + "/temp_vm_map.csv"
pyLog$       = temporaryDirectory$ + "/temp_vm_error.log"

# ---- CLEANUP ----
procedure cleanUpTempFiles
    if fileReadable(tempWav$)
        deleteFile: tempWav$
    endif
    if fileReadable(tempCsv$)
        deleteFile: tempCsv$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempMap$)
        deleteFile: tempMap$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
endproc
@cleanUpTempFiles

# ---- RUN PROCESSOR ----
clearinfo
writeInfoLine: "=== Latent Void Mosaic v1.5 ==="
appendInfoLine: "Preset:        ", presetName$
appendInfoLine: "Target Length: ", target_Duration_s, " seconds"
appendInfoLine: "Extracting acoustic matter and charting voids..."

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
pyCmd$ = pyCmd$ + " --corpus """ + corpusDir$ + """"
pyCmd$ = pyCmd$ + " --target_dur " + string$(target_Duration_s)
pyCmd$ = pyCmd$ + " --grain_dur " + string$(grain_Duration_ms)
pyCmd$ = pyCmd$ + " --overlap " + string$(overlap_percent)
pyCmd$ = pyCmd$ + " --jitter " + string$(length_Jitter_percent)
pyCmd$ = pyCmd$ + " --max_shift " + string$(max_pitch_shift_semitones)
pyCmd$ = pyCmd$ + " --rest_prob " + string$(rest_probability)
pyCmd$ = pyCmd$ + " --min_pitch " + string$(minPitchHz)
pyCmd$ = pyCmd$ + " --max_pitch " + string$(maxPitchHz)
pyCmd$ = pyCmd$ + " --void_spacing " + string$(void_spacing)
pyCmd$ = pyCmd$ + " --reuse_penalty " + string$(source_variety)
pyCmd$ = pyCmd$ + " --stereo " + string$(stereo_output)
pyCmd$ = pyCmd$ + " --pan_mode " + string$(pan_strategy)
pyCmd$ = pyCmd$ + " --stereo_width " + string$(stereo_width)
pyCmd$ = pyCmd$ + " --out_wav """ + tempWav$ + """"
pyCmd$ = pyCmd$ + " --out_csv """ + tempCsv$ + """"
pyCmd$ = pyCmd$ + " --out_stats """ + tempStats$ + """"
pyCmd$ = pyCmd$ + " --out_map """ + tempMap$ + """"
pyCmd$ = pyCmd$ + " 2> """ + pyLog$ + """"

runSystem_nocheck: pyCmd$

if not fileReadable(tempStats$)
    errMsg$ = "(No raw traceback printed.)"
    if fileReadable(pyLog$)
        errMsg$ = readFile$: pyLog$
    endif
    @cleanUpTempFiles
    exitScript: "Python Execution Halted:" + newline$ + newline$ + errMsg$
endif

statsText$ = readFile$(tempStats$)

# The engine writes a stats file even on failure, so check the Status line
# rather than merely the file's existence, and require the WAV to exist.
if index(statsText$, "Status: Success") = 0 or not fileReadable(tempWav$)
    errMsg$ = statsText$
    if fileReadable(pyLog$)
        errMsg$ = errMsg$ + newline$ + newline$ + readFile$: pyLog$
    endif
    @cleanUpTempFiles
    exitScript: "Void Mosaic engine reported a failure:" + newline$ + newline$ + errMsg$
endif

# ---- VISUALIZATION & OUTPUT ----
if fileReadable(tempWav$)
    Read from file: tempWav$
    Rename: "Void_Mosaic"
    result_id = selected("Sound")
    
    if draw_visualization
        # To Spectrogram requires mono; the output may be stereo. Build a mono
        # copy for the spectrogram and keep the (possibly stereo) result as the
        # actual output object. Only built when visualization is requested, so
        # a headless run does no wasted spectrogram computation.
        selectObject: result_id
        nCh = Get number of channels
        if nCh > 1
            specSrc = Convert to mono
        else
            specSrc = Copy: "vm_spec_src"
        endif
        To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
        spectrogram_id = selected("Spectrogram")
        removeObject: specSrc

        Erase all
        Select outer viewport: 0, 8, 0, 8
        
        # Panel 1: Master Title
        Select outer viewport: 0, 8, 0, 0.6
        Axes: 0, 1, 0, 1
        Font size: 12
        Colour: "Black"
        Text: 0.5, "centre", 0.65, "half", "##Latent Void Mosaic v1.5##"
        Font size: 7.5
        Colour: "{0.35, 0.35, 0.45}"
        Text: 0.5, "centre", -1.1, "half", 
            ... "Preset: " + presetName$ + 
            ... " | Target: " + string$(target_Duration_s) + "s" +
            ... " | Base Dur: " + string$(grain_Duration_ms) + "ms" +
            ... " | Max Pitch Shift: ±" + string$(max_pitch_shift_semitones) + " st"
            
        # Panel 2: Waveform
        Select outer viewport: 0, 8, 0.65, 2.30
        Select inner viewport: 0.70, 7.60, 0.70, 2.25
        selectObject: result_id
        Colour: "{0.5, 0.2, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Amplitude"
        Text top: "no", "Acoustically Mutated Waveform"
        
        # Panel 3: Spectrogram
        Select outer viewport: 0, 8, 2.40, 4.45
        Select inner viewport: 0.70, 7.60, 2.45, 4.40
        selectObject: spectrogram_id
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (sec)"
        Text top: "no", "Mutant Spectrogram Profile"
        
        # Panel 4: Map
        Select outer viewport: 0, 8, 4.55, 6.45
        Select inner viewport: 0.70, 7.60, 4.62, 6.40
        if fileReadable(tempMap$)
            mapTable = Read Table from comma-separated file: tempMap$
            nMapRows = Get number of rows
            cMin = 1e12
            cMax = -1e12
            rMin = 1e12
            rMax = -1e12
            for mr to nMapRows
                selectObject: mapTable
                cx = Get value: mr, "centroid"
                ry = Get value: mr, "rolloff"
                if cx < cMin
                    cMin = cx
                endif
                if cx > cMax
                    cMax = cx
                endif
                if ry < rMin
                    rMin = ry
                endif
                if ry > rMax
                    rMax = ry
                endif
            endfor
            if cMax - cMin < 1
                cMax = cMin + 1
            endif
            if rMax - rMin < 1
                rMax = rMin + 1
            endif
            cPad = (cMax - cMin) * 0.05
            rPad = (rMax - rMin) * 0.05
            Axes: cMin - cPad, cMax + cPad, rMin - rPad, rMax + rPad
            Paint rectangle: "{0.97, 0.97, 0.98}", cMin - cPad, cMax + cPad, rMin - rPad, rMax + rPad
            cSpan = (cMax + cPad) - (cMin - cPad)
            voidRadius = cSpan * 0.012
            corpRadius = cSpan * 0.007
            for mr to nMapRows
                selectObject: mapTable
                typ$ = Get value: mr, "type"
                cx = Get value: mr, "centroid"
                ry = Get value: mr, "rolloff"
                if typ$ = "C"
                    Paint circle: "{0.62, 0.62, 0.66}", cx, ry, corpRadius
                endif
            endfor
            for mr to nMapRows
                selectObject: mapTable
                typ$ = Get value: mr, "type"
                cx = Get value: mr, "centroid"
                ry = Get value: mr, "rolloff"
                if typ$ = "V"
                    Paint circle: "{0.50, 0.20, 0.40}", cx, ry, voidRadius
                endif
            endfor
            removeObject: mapTable
            Colour: "Black"
            Font size: 7
            Marks left: 3, "yes", "yes", "no"
            Marks bottom: 3, "yes", "yes", "no"
            Draw inner box
            Text left: "yes", "Rolloff (Hz)"
            Text bottom: "yes", "Spectral centroid (Hz)"
            Text top: "no", "Matter Map (grey = corpus grains, purple = selected void targets)"
        endif
        
        # Panel 5: Diagnostics
        Select outer viewport: 0, 8, 6.55, 8.00
        Select inner viewport: 0.70, 7.60, 6.58, 7.96
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.98}", 0, 1, 0, 1
        Font size: 8
        Colour: "Black"
        Text: 0.03, "left", 0.75, "half", "Engine Trace:"
        Font size: 7
        Colour: "{0.28, 0.28, 0.28}"
        @parseStatLine: statsText$, "Total computation time: "
        execTime$ = parseStatLine.result$
        @parseStatLine: statsText$, "Acoustic grains mutated: "
        numGrains$ = parseStatLine.result$
        @parseStatLine: statsText$, "Total audio length: "
        totalLen$ = parseStatLine.result$
        @parseStatLine: statsText$, "Distinct source files: "
        filesUsed$ = parseStatLine.result$
        
        Text: 0.03, "left", 0.45, "half", "• Spliced " + numGrains$ + " acoustic slices from " + filesUsed$ + " parent files."
        Text: 0.03, "left", 0.25, "half", "• Mutated and generated " + totalLen$ + " seconds of audio in " + execTime$ + " seconds."
        
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif
    
    appendInfoLine: ""
    appendInfoLine: statsText$
    
    if draw_visualization
        removeObject: spectrogram_id
    endif
    selectObject: result_id
    if play_result
        Play
    endif
endif

@cleanUpTempFiles

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc