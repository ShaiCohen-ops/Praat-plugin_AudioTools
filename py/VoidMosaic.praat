# ============================================================
# Praat AudioTools - VoidMosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5.4 (2026) - Stable Praat-7 I/O, 44100 Hz delivery, corrected
#          Picture frame handling in the panel legends
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
#   Analysis and synthesis run at 22050 Hz; the engine resamples the finished
#   signal once to 44100 Hz before writing it, so the imported Sound is a
#   standard-rate file. The 11.025 kHz analysis ceiling is unchanged -- the
#   resample is a delivery-format step, not added bandwidth.
#
# Python engine: void_mosaic_engine.py
# ============================================================

form "Latent Void Mosaic v1.5.4"
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

# ---- PATHS: same pattern as stable AudioTools wrappers ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/void_mosaic_engine.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/void_mosaic_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: void_mosaic_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runToken = randomInteger(100000, 999999)
runToken$ = string$(runToken)
tempWav$   = tempDir$ + "temp_vm_" + runToken$ + "_output.wav"
tempCsv$   = tempDir$ + "temp_vm_" + runToken$ + "_grains.csv"
tempStats$ = tempDir$ + "temp_vm_" + runToken$ + "_stats.txt"
tempMap$   = tempDir$ + "temp_vm_" + runToken$ + "_map.csv"
pyLog$     = tempDir$ + "temp_vm_" + runToken$ + "_python.log"
probeMarker$ = tempDir$ + "temp_vm_" + runToken$ + "_probe.ok"

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
corpusDirJ$    = replace_regex$(corpusDir$, "\\", "/", 0)
tempWavJ$      = replace_regex$(tempWav$, "\\", "/", 0)
tempCsvJ$      = replace_regex$(tempCsv$, "\\", "/", 0)
tempStatsJ$    = replace_regex$(tempStats$, "\\", "/", 0)
tempMapJ$      = replace_regex$(tempMap$, "\\", "/", 0)
pyLogJ$        = replace_regex$(pyLog$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

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
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- Dependency probe: same synchronous runSystem_nocheck pattern used elsewhere ----
clearinfo
writeInfoLine: "=== Latent Void Mosaic v1.5.4 ==="
appendInfoLine: "Corpus:        ", corpusDir$
appendInfoLine: "Preset:        ", presetName$
appendInfoLine: "Target Length: ", target_Duration_s, " seconds"
appendInfoLine: "[1/3] Checking Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile, librosa; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Missing Python dependencies." + newline$ + "Required: numpy scipy soundfile librosa"
endif
deleteFile: probeMarker$

# ---- Run engine ----
appendInfoLine: "[2/3] Running Python Void Mosaic engine..."
pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " --corpus """ + corpusDirJ$ + """"
    ... + " --target_dur " + string$(target_Duration_s)
    ... + " --grain_dur " + string$(grain_Duration_ms)
    ... + " --overlap " + string$(overlap_percent)
    ... + " --jitter " + string$(length_Jitter_percent)
    ... + " --max_shift " + string$(max_pitch_shift_semitones)
    ... + " --rest_prob " + string$(rest_probability)
    ... + " --min_pitch " + string$(minPitchHz)
    ... + " --max_pitch " + string$(maxPitchHz)
    ... + " --void_spacing " + string$(void_spacing)
    ... + " --reuse_penalty " + string$(source_variety)
    ... + " --stereo " + string$(stereo_output)
    ... + " --pan_mode " + string$(pan_strategy)
    ... + " --stereo_width " + string$(stereo_width)
    ... + " --out_wav """ + tempWavJ$ + """"
    ... + " --out_csv """ + tempCsvJ$ + """"
    ... + " --out_stats """ + tempStatsJ$ + """"
if draw_visualization
    pythonCall$ = pythonCall$ + " --out_map """ + tempMapJ$ + """"
endif

runSystem_nocheck: pythonCall$ + " > """ + pyLogJ$ + """ 2>&1"

# ---- Verify output before touching it ----
if not fileReadable(tempWav$) or not fileReadable(tempStats$)
    errMsg$ = "Python Void Mosaic engine failed to produce its expected output."
    if fileReadable(pyLog$)
        errMsg$ = errMsg$ + newline$ + newline$ + readFile$(pyLog$)
    endif
    @cleanUpTempFiles
    exitScript: errMsg$
endif

statsText$ = readFile$(tempStats$)
if index(statsText$, "Status: Success") = 0
    errMsg$ = statsText$
    if fileReadable(pyLog$)
        errMsg$ = errMsg$ + newline$ + newline$ + readFile$(pyLog$)
    endif
    @cleanUpTempFiles
    exitScript: "Void Mosaic engine reported a failure:" + newline$ + newline$ + errMsg$
endif

# ---- Import result: same pattern as the stable wrappers ----
appendInfoLine: "[3/3] Importing result..."
Read from file: tempWav$
Rename: "Void_Mosaic"
resultSound = selected("Sound")

selectObject: resultSound
outDur = Get total duration
outRms = Get root-mean-square: 0, 0
nChannels = Get number of channels
outSampleRate = Get sampling frequency

# ---- LIGHTWEIGHT MECHANISM VISUALIZATION ----
# Important: this uses the stable in-memory Sound plus bounded CSV/map files.
# No mono fold-down, no Spectrogram object, and no unbounded Picture loops.
if draw_visualization
    # Representative real output channel: strongest RMS channel, never L+R fold-down.
    selectObject: resultSound
    bestVizRms = -1
    vizChannel = 1
    for ch from 1 to nChannels
        selectObject: resultSound
        chObj = Extract one channel: ch
        chRms = Get root-mean-square: 0, 0
        if chRms > bestVizRms
            bestVizRms = chRms
            vizChannel = ch
        endif
        removeObject: chObj
    endfor
    selectObject: resultSound
    if nChannels > 1
        vizSound = Extract one channel: vizChannel
    else
        Copy: "vm_viz_output"
        vizSound = selected("Sound")
    endif

    selectObject: vizSound
    wavePeak = Get absolute extremum: 0, 0, "none"
    wavePeak = wavePeak * 1.05
    if wavePeak < 0.000001
        wavePeak = 1
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Title strip
    Select outer viewport: 0, 8, 0, 0.62
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Latent Void Mosaic v1.5.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.48}"
    Text: 0.5, "centre", -1.22, "half", presetName$ + "  |  register=" + registerName$ + "  |  output ch" + string$(vizChannel)

    # Panel 1: actual output waveform
    Select outer viewport: 0, 8, 0.68, 2.05
    Select inner viewport: 0.62, 7.65, 0.76, 1.96
    Axes: 0, outDur, -wavePeak, wavePeak
    selectObject: vizSound
    Colour: "{0.18, 0.36, 0.58}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    # Restore before the label group: Draw inner box moved the frame to the
    # outer viewport, and this panel has wide margins, so "Time (s)" was landing
    # below the outer viewport and colliding with the row underneath.
    @restoreWaveFrame
    Font size: 7
    @niceStep: outDur
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: 2 * wavePeak
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Rendered mosaic waveform  [strongest real channel]"

    # Panel 2: 2-D projection of the 6-D selection geometry.
    Select outer viewport: 0, 4.10, 2.18, 5.15
    Select inner viewport: 0.62, 3.86, 2.30, 5.02
    if fileReadable(tempMap$)
        mapTable = Read Table from comma-separated file: tempMap$
        nMapRows = Get number of rows
        cMin = 1e30
        cMax = -1e30
        rMin = 1e30
        rMax = -1e30
        # Range scan. The selected-grain endpoints are included too: they are
        # real corpus grains that the decimated "C" sample may not contain, and
        # a connector running off the panel edge would be misleading.
        for mr from 1 to nMapRows
            selectObject: mapTable
            cx = Get value: mr, "centroid"
            ry = Get value: mr, "rolloff"
            sx = Get value: mr, "src_centroid"
            sy = Get value: mr, "src_rolloff"
            if sx <= 0 or sy <= 0
                sx = cx
                sy = ry
            endif
            cMin = min(cMin, cx, sx)
            cMax = max(cMax, cx, sx)
            rMin = min(rMin, ry, sy)
            rMax = max(rMax, ry, sy)
        endfor
        if cMax - cMin < 1
            cMax = cMin + 1
        endif
        if rMax - rMin < 1
            rMax = rMin + 1
        endif
        cPad = max(1, 0.06 * (cMax - cMin))
        rPad = max(1, 0.06 * (rMax - rMin))
        mapX0 = cMin - cPad
        mapX1 = cMax + cPad
        mapY0 = rMin - rPad
        # Extra headroom at the top so the legend strip is empty by
        # construction: void targets often cluster at an extreme of this
        # projection, and a legend printed over them is unreadable.
        mapY1 = rMax + rPad + 0.14 * (rMax - rMin + 2 * rPad)
        Axes: mapX0, mapX1, mapY0, mapY1
        Paint rectangle: "{0.97, 0.97, 0.98}", mapX0, mapX1, mapY0, mapY1

        # Connectors first, so the dots sit on top of them. Each line joins the
        # void target to the real corpus grain that was actually selected for
        # it: the line IS the nudge the engine performed, in these two axes.
        Colour: "{0.78, 0.70, 0.80}"
        Line width: 1
        for mr from 1 to nMapRows
            selectObject: mapTable
            typ$ = Get value: mr, "type"
            if typ$ = "V"
                cx = Get value: mr, "centroid"
                ry = Get value: mr, "rolloff"
                sx = Get value: mr, "src_centroid"
                sy = Get value: mr, "src_rolloff"
                if sx > 0 and sy > 0
                    Draw line: sx, sy, cx, ry
                endif
            endif
        endfor
        @restoreMapFrame

        # Corpus first, then void targets. Fixed mm sizes avoid scale-dependent dots.
        for mr from 1 to nMapRows
            selectObject: mapTable
            typ$ = Get value: mr, "type"
            if typ$ = "C"
                cx = Get value: mr, "centroid"
                ry = Get value: mr, "rolloff"
                Paint circle (mm): "{0.68, 0.68, 0.70}", cx, ry, 0.8
            endif
        endfor
        for mr from 1 to nMapRows
            selectObject: mapTable
            typ$ = Get value: mr, "type"
            if typ$ = "V"
                cx = Get value: mr, "centroid"
                ry = Get value: mr, "rolloff"
                Paint circle (mm): "{0.48, 0.18, 0.48}", cx, ry, 1.5
            endif
        endfor
        removeObject: mapTable

        # Paint circle can leave Picture on the outer viewport; restore explicitly.
        @restoreMapFrame
        Colour: "Black"
        Font size: 7
        @niceStep: mapX1 - mapX0
        Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
        @niceStep: mapY1 - mapY0
        Marks left every: 1, niceStep.step, "yes", "yes", "no"
        Draw inner box
        Text left: "yes", "Rolloff (Hz)"
        Text bottom: "yes", "Spectral centroid (Hz)"
        Text top: "no", "Void geometry: 6-D search projected to centroid / rolloff"
        # Draw inner box / Text left / Text top leave the drawing frame on the
        # OUTER viewport, and Axes alone does not restore it -- a world-coordinate
        # Text placed here without re-selecting lands outside the panel.
        @restoreMapFrame
        Font size: 6
        Colour: "{0.35, 0.35, 0.35}"
        Text: mapX0 + 0.03 * (mapX1 - mapX0), "left", mapY1 - 0.06 * (mapY1 - mapY0), "half", "grey corpus   purple void targets   line = grain -> void nudge"
    endif

    # Panel 3: measured pitch-mutation trace from the actual grain schedule.
    Select outer viewport: 4.10, 8, 2.18, 5.15
    Select inner viewport: 4.42, 7.65, 2.30, 5.02
    pitchY0 = 24
    pitchY1 = 108
    Axes: 0, outDur, pitchY0, pitchY1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, outDur, pitchY0, pitchY1

    # Target register as a shaded band. This is what makes the "register is a
    # preference bounded by Max Pitch Shift" claim checkable: every black
    # (reachable) dot lying OUTSIDE the band is a grain the shift ceiling
    # stopped short of the requested register.
    regLoMidi = 69 + 12 * ln(minPitchHz / 440) / ln(2)
    regHiMidi = 69 + 12 * ln(maxPitchHz / 440) / ln(2)
    regLoMidi = max(regLoMidi, pitchY0)
    regHiMidi = min(regHiMidi, pitchY1)
    if regHiMidi > regLoMidi
        Paint rectangle: "{0.90, 0.94, 0.90}", 0, outDur, regLoMidi, regHiMidi
    endif

    if fileReadable(tempCsv$)
        grainTable = Read Table from comma-separated file: tempCsv$
        nGrainRows = Get number of rows
        # Measured on this machine: 4000 Paint circle (mm) calls cost ~24 ms and
        # 4000 rows of Table queries ~53 ms, against a Python render measured in
        # seconds. Decimating to 120 points bought nothing and threw away detail.
        maxPitchPoints = 600
        stepRows = round(nGrainRows / maxPitchPoints)
        if stepRows < 1
            stepRows = 1
        endif
        nextDrawRow = 1
        for gr from 1 to nGrainRows
            if gr >= nextDrawRow
                selectObject: grainTable
                tOut = Get value: gr, "output_time_sec"
                srcHz = Get value: gr, "source_f0_hz"
                foldHz = Get value: gr, "folded_target_f0_hz"
                reachHz = Get value: gr, "reachable_output_f0_hz"
                if srcHz > 20
                    srcMidi = 69 + 12 * ln(srcHz / 440) / ln(2)
                    Paint circle (mm): "{0.62, 0.62, 0.64}", tOut, srcMidi, 0.8
                endif
                if foldHz > 20
                    foldMidi = 69 + 12 * ln(foldHz / 440) / ln(2)
                    Paint circle (mm): "{0.48, 0.18, 0.48}", tOut, foldMidi, 1.3
                endif
                if reachHz > 20
                    reachMidi = 69 + 12 * ln(reachHz / 440) / ln(2)
                    Paint circle (mm): "{0.12, 0.12, 0.12}", tOut, reachMidi, 0.9
                endif
                nextDrawRow = nextDrawRow + stepRows
            endif
        endfor
        removeObject: grainTable
    endif
    @restorePitchFrame
    Colour: "Black"
    Font size: 7
    # Marks left: 5 put ticks at 24 / 45 / 66 / 87 / 108 -- arithmetic, but not
    # musical. Every 12 semitones gives octaves, which is what this axis means.
    Marks left every: 1, 12, "yes", "yes", "no"
    @niceStep: outDur
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Draw inner box
    Text left: "yes", "MIDI"
    Text bottom: "yes", "Output time (s)"
    Text top: "no", "Pitch mutation trace"
    # Same frame caveat as the map panel: restore before any world-coordinate Text.
    @restorePitchFrame
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.03 * outDur, "left", 102, "half", "grey source   purple folded target   black reachable output   green band = target register"

    # Panel 4: mechanism + QC summary
    Select outer viewport: 0, 8, 5.30, 7.45
    Select inner viewport: 0.62, 7.65, 5.40, 7.34
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.97}", 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.03, "left", 0.88, "half", "##Mechanism##"
    Font size: 7
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.03, "left", 0.68, "half", "corpus grains -> 6-D standardization -> random probes -> deepest sparse voids -> nearest real grains"
    Text: 0.03, "left", 0.49, "half", "selected grain -> pitch folded to register (bounded by Max Shift) + RMS mutation -> overlap-add mosaic"
    @parseStatLine: statsText$, "Acoustic grains mutated: "
    numGrains$ = parseStatLine.result$
    @parseStatLine: statsText$, "Distinct source files: "
    filesUsed$ = parseStatLine.result$
    @parseStatLine: statsText$, "Voids meeting spacing: "
    spaced$ = parseStatLine.result$
    @parseStatLine: statsText$, "Total computation time: "
    timeUsed$ = parseStatLine.result$
    @parseStatLine: statsText$, "Grains at max shift: "
    clipped$ = parseStatLine.result$
    @parseStatLine: statsText$, "Analysis rate: "
    aRate$ = parseStatLine.result$
    @parseStatLine: statsText$, "Output rate: "
    oRate$ = parseStatLine.result$
    Text: 0.03, "left", 0.28, "half", "QC: grains=" + numGrains$ + "   source files=" + filesUsed$ + "   spaced voids=" + spaced$ + "   grains at shift ceiling=" + clipped$ + "   render=" + timeUsed$ + " s"
    Text: 0.03, "left", 0.10, "half", "Built at " + aRate$ + " Hz, delivered at " + oRate$ + " Hz (no added bandwidth). Map is a 2-D projection; the pitch trace is the schedule actually rendered."
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Bottom summary bar
    Select outer viewport: 0, 8, 7.55, 8.00
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    # A bare "%" is italic markup in Picture text: it is swallowed and the run
    # after it is italicised. "\%" prints a literal percent sign.
    Text: 0.5, "centre", 0.55, "half", "dur=" + fixed$(outDur, 2) + "s  |  " + string$(outSampleRate) + " Hz  |  RMS=" + fixed$(outRms, 4) + "  |  overlap=" + fixed$(overlap_percent, 1) + "\%  |  jitter=" + fixed$(length_Jitter_percent, 1) + "\%  |  width=" + fixed$(stereo_width, 2)

    removeObject: vizSound
    # Leave the Picture selection on the whole canvas. Save as PNG / PDF and
    # Copy export the CURRENT viewport selection, so ending on the summary bar
    # would export a 0.45-inch strip instead of the figure.
    Select outer viewport: 0, 8, 0, 8
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: Void_Mosaic"
appendInfoLine: "Duration: ", fixed$(outDur, 3), " s"
appendInfoLine: "Channels: ", nChannels
appendInfoLine: "Sample rate: ", outSampleRate, " Hz (built at 22050 Hz, resampled once on output)"
appendInfoLine: "RMS: ", fixed$(outRms, 6)
appendInfoLine: ""
appendInfoLine: statsText$

# Critical lifecycle: the Sound is now resident in Praat memory. Delete all
# temporary disk files BEFORE optional playback, exactly as the stable wrappers do.
@cleanUpTempFiles

selectObject: resultSound
if play_result
    Play
endif

# Draw inner box, Marks and Text left/bottom/top all leave the drawing frame on
# the OUTER viewport, and a following "Axes:" does not restore it. Measured at
# 300 dpi: a point drawn without restoring lands ~0.14 x 0.09 inch outside the
# panel. Any world-coordinate Text after those commands needs a full restore.
procedure restoreWaveFrame
    Select outer viewport: 0, 8, 0.68, 2.05
    Select inner viewport: 0.62, 7.65, 0.76, 1.96
    Axes: 0, outDur, -wavePeak, wavePeak
endproc

procedure restoreMapFrame
    Select outer viewport: 0, 4.10, 2.18, 5.15
    Select inner viewport: 0.62, 3.86, 2.30, 5.02
    Axes: mapX0, mapX1, mapY0, mapY1
endproc

procedure restorePitchFrame
    Select outer viewport: 4.10, 8, 2.18, 5.15
    Select inner viewport: 4.42, 7.65, 2.30, 5.02
    Axes: 0, outDur, pitchY0, pitchY1
endproc

# Round tick spacing (1 / 2 / 5 x 10^n) for a given axis span, aiming at about
# five marks. "Marks left: N" would instead place ticks at the data-derived
# extremes and print values like 3184.7.
procedure niceStep: .span
    .step = 1
    if .span > 0
        .raw = .span / 5
        .mag = 10 ^ floor(log10(.raw))
        .norm = .raw / .mag
        if .norm < 1.5
            .step = .mag
        elsif .norm < 3
            .step = 2 * .mag
        elsif .norm < 7
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endif
endproc

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

