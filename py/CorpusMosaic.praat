# ============================================================
# Praat AudioTools - CorpusMosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Offline Corpus Mosaic Synthesizer.
#
#   Reconstructs a target Sound object by splicing together tiny 
#   grains of audio from a folder of corpus sounds. The matching 
#   is performed offline via a Python engine which extracts a 6D 
#   feature vector (Loudness, Centroid, Flatness, Rolloff, ZCR, Pitch) 
#   for every grain, normalizes the space, and computes distances.
#   Includes repetition penalties, continuity bonuses, and silence gating.
#
# Python engine: corpus_mosaic_engine.py
#
# Dependencies (Python):
#   pip install numpy scipy soundfile librosa
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-
#   Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form "Offline Corpus Mosaic Synthesizer"
    positive Grain_size_ms 100
    real Overlap_percent 50.0
    real Pitch_weight 1.0
    real Timbre_weight 1.0
    real Loudness_weight 1.0
    positive Top_k_candidates 5
    real Randomness 0.5
    real Continuity_preference 0.3
    real Repetition_penalty 1.5
    real Gate_threshold_dB -40.0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sourceId = selected("Sound")
sourceName$ = selected$("Sound")

corpusDir$ = chooseDirectory$("Select Corpus Folder (WAV/FLAC/AIFF)")
if corpusDir$ == ""
    exitScript: "Operation cancelled."
endif

# ============================================================
# OS-Specific Python Discovery
# ============================================================
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
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

# ============================================================
# Paths Setup
# ============================================================
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/corpus_mosaic_engine.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/corpus_mosaic_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find corpus_mosaic_engine.py." + newline$ + "Expected at: " + pluginDir$ + "py/"
endif

tempSource$  = temporaryDirectory$ + "/temp_mosaic_source.wav"
tempOutput$  = temporaryDirectory$ + "/temp_mosaic_output.wav"
tempCsv$     = temporaryDirectory$ + "/temp_mosaic_path.csv"
tempStats$   = temporaryDirectory$ + "/temp_mosaic_stats.txt"
pyLog$       = temporaryDirectory$ + "/temp_mosaic_error.log"
probeMarker$ = temporaryDirectory$ + "/temp_mosaic_probe.ok"

# Replace backslashes for the Python inline probe to prevent escape character crashes on Windows
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ============================================================
# Cleanup Procedure
# ============================================================
procedure cleanUpTempFiles
    if fileReadable(tempSource$)
        deleteFile: tempSource$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempCsv$)
        deleteFile: tempCsv$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ============================================================
# Check Python Dependencies
# ============================================================
clearinfo
writeInfoLine: "=== Offline Corpus Mosaic ==="
appendInfoLine: "Scanning corpus: ", corpusDir$
appendInfoLine: "[1/3] Detecting Python and Librosa..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile, librosa; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Missing Python dependencies!" + newline$ + "Please open your terminal/command prompt and run: pip install numpy scipy soundfile librosa"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ============================================================
# Stage 2 — Run Python engine
# ============================================================
appendInfoLine: "[2/3] Running Python Engine..."

selectObject: sourceId
Save as WAV file: tempSource$

overlapRatio = overlap_percent / 100.0
normFlag$ = ""
if normalize_output
    normFlag$ = "--normalize"
endif

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
pyCmd$ = pyCmd$ + " --source """ + tempSource$ + """"
pyCmd$ = pyCmd$ + " --corpus """ + corpusDir$ + """"
pyCmd$ = pyCmd$ + " --out_wav """ + tempOutput$ + """"
pyCmd$ = pyCmd$ + " --out_csv """ + tempCsv$ + """"
pyCmd$ = pyCmd$ + " --out_stats """ + tempStats$ + """"
pyCmd$ = pyCmd$ + " --grain_ms " + string$(grain_size_ms)
pyCmd$ = pyCmd$ + " --overlap " + string$(overlapRatio)
pyCmd$ = pyCmd$ + " --pitch_w " + string$(pitch_weight)
pyCmd$ = pyCmd$ + " --timbre_w " + string$(timbre_weight)
pyCmd$ = pyCmd$ + " --loudness_w " + string$(loudness_weight)
pyCmd$ = pyCmd$ + " --top_k " + string$(top_k_candidates)
pyCmd$ = pyCmd$ + " --randomness " + string$(randomness)
pyCmd$ = pyCmd$ + " --continuity " + string$(continuity_preference)
pyCmd$ = pyCmd$ + " --penalty " + string$(repetition_penalty)
pyCmd$ = pyCmd$ + " --gate_db " + string$(gate_threshold_dB)
pyCmd$ = pyCmd$ + " " + normFlag$

if windows
    pyCmd$ = pyCmd$ + " 2> """ + pyLog$ + """"
else
    pyCmd$ = pyCmd$ + " 2> """ + pyLog$ + """"
endif

runSystem_nocheck: pyCmd$

if not fileReadable(tempOutput$)
    errMsg$ = ""
    if fileReadable(pyLog$)
        errMsg$ = readFile$: pyLog$
    endif
    @cleanUpTempFiles
    if errMsg$ = ""
        errMsg$ = "(no error output captured. Ensure audio files exist in the corpus folder.)"
    endif
    exitScript: "Python engine failed." + newline$ + newline$ + errMsg$
endif

appendInfoLine: "  Engine complete."

# ============================================================
# Stage 3 — Load Output & Parse Stats
# ============================================================
appendInfoLine: "[3/3] Importing result..."

Read from file: tempOutput$
resultSound = selected("Sound")
Rename: sourceName$ + "_mosaic"

statSourceGrains$ = "0"
statSilenced$     = "0"
statCorpusFiles$  = "0"
statCorpusGrains$ = "0"
statUniqueUsed$   = "0"
statTime$         = "0.00"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    
    @parseStatLine: statsText$, "Source grains: "
    statSourceGrains$ = parseStatLine.result$
    
    @parseStatLine: statsText$, "Silenced grains (Gated): "
    statSilenced$ = parseStatLine.result$
    
    @parseStatLine: statsText$, "Corpus files analyzed: "
    statCorpusFiles$ = parseStatLine.result$
    
    @parseStatLine: statsText$, "Corpus grains available: "
    statCorpusGrains$ = parseStatLine.result$
    
    @parseStatLine: statsText$, "Unique files utilized: "
    statUniqueUsed$ = parseStatLine.result$
    
    @parseStatLine: statsText$, "Render time: "
    statTime$ = parseStatLine.result$
endif

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ---------------------------------------------------------
    # Title panel
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Corpus Mosaic Synthesizer##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", -1.0, "half",
        ... sourceName$
        ... + "  |  Grain=" + fixed$(grain_size_ms, 0) + " ms"
        ... + "  |  Overlap=" + fixed$(overlap_percent, 0) + "%"
        ... + "  |  Top-k=" + string$(top_k_candidates)

    # ---------------------------------------------------------
    # Source waveform
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    selectObject: sourceId
    Colour: "{0.50, 0.50, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Target"
    Text top: "no", "Source waveform"

    # ---------------------------------------------------------
    # Output waveform
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 1.45, 2.35
    Select inner viewport: 0.6, 7.7, 1.50, 2.30
    selectObject: resultSound
    Colour: "{0.22, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mosaic"
    Text bottom: "yes", "Time (s)"

    # ---------------------------------------------------------
    # Original spectrogram
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 2.45, 3.55
    Select inner viewport: 0.6, 7.7, 2.50, 3.50
    selectObject: sourceId
    nChSrc = Get number of channels
    if nChSrc > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig_mosaic"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # ---------------------------------------------------------
    # Output spectrogram
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 3.55, 4.65
    Select inner viewport: 0.6, 7.7, 3.60, 4.60
    selectObject: resultSound
    nChOut = Get number of channels
    if nChOut > 1
        Extract one channel: 1
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut_mosaic"
        tmpOut = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Mosaic spectrogram"
    removeObject: specOut, tmpOut

    # ---------------------------------------------------------
    # Corpus usage strip + distance trace
    # ---------------------------------------------------------
    csvTable = 0
    if fileReadable(tempCsv$)
        csvTable = Read Table from comma-separated file: tempCsv$
    endif

    if csvTable <> 0
        cr# = zero#(8)
        cg# = zero#(8)
        cb# = zero#(8)
        cr#[1]=0.22
        cg#[1]=0.50
        cb#[1]=0.82
        cr#[2]=0.82
        cg#[2]=0.22
        cb#[2]=0.28
        cr#[3]=0.15
        cg#[3]=0.65
        cb#[3]=0.45
        cr#[4]=0.78
        cg#[4]=0.52
        cb#[4]=0.08
        cr#[5]=0.60
        cg#[5]=0.20
        cb#[5]=0.70
        cr#[6]=0.15
        cg#[6]=0.68
        cb#[6]=0.75
        cr#[7]=0.90
        cg#[7]=0.35
        cb#[7]=0.60
        cr#[8]=0.45
        cg#[8]=0.45
        cb#[8]=0.45

        selectObject: csvTable
        nRows = Get number of rows

        nUF = 0
        for uf to 8
            uFile_'uf'$ = ""
        endfor
        for r to nRows
            selectObject: csvTable
            fn$ = Get value: r, "corpus_file"
            found = 0
            if fn$ <> "__SILENCE__" and fn$ <> ""
                for uf to nUF
                    if uFile_'uf'$ = fn$
                        found = 1
                    endif
                endfor
                if found = 0 and nUF < 8
                    nUF = nUF + 1
                    uFile_'nUF'$ = fn$
                endif
            endif
        endfor

        # Source-file timeline strip
        Select outer viewport: 0, 8, 4.75, 5.45
        Select inner viewport: 0.6, 7.7, 4.80, 5.40
        Axes: 0, nRows, 0, 1
        for r to nRows
            selectObject: csvTable
            fn$ = Get value: r, "corpus_file"
            if fn$ = "__SILENCE__"
                Paint rectangle: "{0.86, 0.86, 0.86}", r-0.95, r-0.05, 0.05, 0.95
            else
                ci = 1
                for uf to nUF
                    if uFile_'uf'$ = fn$
                        ci = uf
                    endif
                endfor
                if ci > 8
                    ci = 8
                endif
                Paint rectangle: "{" + fixed$(cr#[ci], 2) + "," + fixed$(cg#[ci], 2) + "," + fixed$(cb#[ci], 2) + "}", r-0.95, r-0.05, 0.05, 0.95
            endif
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Corpus"
        Text bottom: "yes", "Target grain"
        Text top: "no", string$(nUF) + " files  |  grey=silence"

        # Distance trace
        Select outer viewport: 0, 8, 5.55, 6.40
        Select inner viewport: 0.6, 7.7, 5.60, 6.35
        maxDist = 0
        for r to nRows
            selectObject: csvTable
            dv = Get value: r, "distance"
            if dv <> undefined and dv > maxDist
                maxDist = dv
            endif
        endfor
        if maxDist <= 0
            maxDist = 1
        endif
        Axes: 0, nRows, 0, maxDist
        Paint rectangle: "{0.96, 0.96, 0.98}", 0, nRows, 0, maxDist
        Colour: "{0.22, 0.50, 0.82}"
        Line width: 1.5
        prevX = 0
        prevY = 0
        havePrev = 0
        for r to nRows
            selectObject: csvTable
            dv = Get value: r, "distance"
            fn$ = Get value: r, "corpus_file"
            if dv = undefined
                dv = 0
            endif
            if fn$ = "__SILENCE__"
                dv = 0
            endif
            if havePrev = 1
                Draw line: prevX, prevY, r, dv
            endif
            prevX = r
            prevY = dv
            havePrev = 1
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Dist"
        Text bottom: "yes", "Target grain"
        Text top: "no", "Match distance profile"
    endif

    # ---------------------------------------------------------
    # Summary panel
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 6.55, 7.75
    Select inner viewport: 0.6, 7.7, 6.60, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.66, "half",
        ... "Target grains: " + statSourceGrains$
        ... + "  |  Silenced: " + statSilenced$
        ... + "  |  Corpus pool: " + statCorpusGrains$ + " grains"
    Text: 0.02, "left", 0.44, "half",
        ... "Files analysed: " + statCorpusFiles$
        ... + "  |  Unique files used: " + statUniqueUsed$
        ... + "  |  Render time: " + statTime$
    Text: 0.02, "left", 0.22, "half",
        ... "Pitch w: " + fixed$(pitch_weight, 2)
        ... + "  |  Timbre w: " + fixed$(timbre_weight, 2)
        ... + "  |  Loudness w: " + fixed$(loudness_weight, 2)
        ... + "  |  Rand: " + fixed$(randomness, 2)
        ... + "  |  Cont: " + fixed$(continuity_preference, 2)
        ... + "  |  Penalty: " + fixed$(repetition_penalty, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    if csvTable <> 0
        removeObject: csvTable
    endif

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Final info + cleanup
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Target grains: ", statSourceGrains$
appendInfoLine: "Silenced:      ", statSilenced$
appendInfoLine: "Corpus pool:   ", statCorpusGrains$
appendInfoLine: "Files used:    ", statUniqueUsed$
appendInfoLine: "Render time:   ", statTime$

selectObject: resultSound

@cleanUpTempFiles

if play_result
    Play
endif

# ============================================================
# Procedures
# ============================================================

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc