# ============================================================
# Praat AudioTools - GranularNavigationEngine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Granular Navigation Engine
#
#   Selects a folder of sounds and delegates all scanning, grain
#   segmentation, and feature extraction to a Python engine.
#   Python trains a latent autoencoder, scores transitions, and
#   returns a navigation path. Praat reads the path CSV and
#   reconstructs the result from the original audio.
#
#   Role separation:
#     Praat  — folder selection, path CSV read,
#              reconstruction, visualization.
#     Python — folder scan, grain slicing, ALL feature
#              extraction, autoencoder training,
#              path generation, stats. Zero Praat objects.
#
# Python engine: granular_navigation_engine.py
#
# Dependencies (Python):
#   pip install torch numpy soundfile
# ============================================================

# ---- OS-Specific Python Discovery ----
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

# ---- Paths Setup ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/granular_navigation_engine.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/granular_navigation_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find granular_navigation_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/" + newline$ + "or next to this script."
endif

tempPath$    = temporaryDirectory$ + "/temp_gne_path.csv"
tempStats$   = temporaryDirectory$ + "/temp_gne_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_gne_probe.ok"
pyLog$       = temporaryDirectory$ + "/temp_gne_error.log"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- Cleanup Procedure ----
procedure cleanUpTempFiles
    if fileReadable(tempPath$)
        deleteFile: tempPath$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
endproc

@cleanUpTempFiles

folder$ = chooseDirectory$: "Select folder of audio files"
if folder$ = ""
    exitScript: "No folder selected."
endif

# Universally sanitize backslashes to forward slashes to prevent Windows escape character crashes
folderJ$ = replace_regex$(folder$, "\\", "/", 0)
if right$(folderJ$, 1) <> "/"
    folderJ$ = folderJ$ + "/"
endif

# ---- FORM ----
form Granular Navigation Engine
    optionmenu Navigation_mode: 1
        option Similarity
        option Smooth
        option Contrast
        option Brighter
        option Darker
        option Noisier
        option Harmonic
        option Denser
        option Sparser
    positive Grain_ms 150
    integer Path_length 60
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Fixed parameters
epochs = 80
seed   = 42

# ---- MODE NAME ----
if navigation_mode = 1
    modeStr$ = "similarity"
elsif navigation_mode = 2
    modeStr$ = "smooth"
elsif navigation_mode = 3
    modeStr$ = "contrast"
elsif navigation_mode = 4
    modeStr$ = "brighter"
elsif navigation_mode = 5
    modeStr$ = "darker"
elsif navigation_mode = 6
    modeStr$ = "noisier"
elsif navigation_mode = 7
    modeStr$ = "harmonic"
elsif navigation_mode = 8
    modeStr$ = "denser"
else
    modeStr$ = "sparser"
endif

clearinfo
writeInfoLine: "=== Granular Navigation Engine ==="
appendInfoLine: "Folder: ", folderJ$
appendInfoLine: "Mode:   ", modeStr$
appendInfoLine: "Grain:  ", grain_ms, " ms"
appendInfoLine: "Path:   ", path_length, " grains"
appendInfoLine: ""

# ============================================================
# Stage 1 — Detect Python Dependencies
# ============================================================
appendInfoLine: "[1/3] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import torch, numpy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Cannot find Python with required packages." + newline$ + "  pip install torch numpy soundfile"
endif
deleteFile: probeMarker$

appendInfoLine: "  Python found: ", pythonCmd$

# ============================================================
# Stage 2 — Run Python engine
# ============================================================
appendInfoLine: "[2/3] Running Python engine..."

grainMsStr$    = fixed$(grain_ms, 0)
pathLengthStr$ = string$(path_length)
epochsStr$     = string$(epochs)
seedStr$       = string$(seed)

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
pyCmd$ = pyCmd$ + " --folder """    + folderJ$     + """"
pyCmd$ = pyCmd$ + " --path_out """  + tempPath$    + """"
pyCmd$ = pyCmd$ + " --stats """     + tempStats$   + """"
pyCmd$ = pyCmd$ + " --mode "        + modeStr$
pyCmd$ = pyCmd$ + " --grain_ms "    + grainMsStr$
pyCmd$ = pyCmd$ + " --path_length " + pathLengthStr$
pyCmd$ = pyCmd$ + " --epochs "      + epochsStr$
pyCmd$ = pyCmd$ + " --seed "        + seedStr$

if windows
    pyCmd$ = pyCmd$ + " 2> """ + pyLog$ + """"
else
    pyCmd$ = pyCmd$ + " 2> """ + pyLog$ + """"
endif

runSystem_nocheck: pyCmd$

if not fileReadable(tempPath$)
    errMsg$ = ""
    if fileReadable(pyLog$)
        errMsg$ = readFile$: pyLog$
    endif
    @cleanUpTempFiles
    if errMsg$ = ""
        errMsg$ = "(no error output captured. Ensure audio files exist in the chosen folder.)"
    endif
    exitScript: "Python engine failed." + newline$ + newline$ + errMsg$ + newline$ + newline$ + "Fix: pip install torch numpy soundfile"
endif

appendInfoLine: "  Engine complete."

# ============================================================
# Stage 3 — Read path and reconstruct
# ============================================================
appendInfoLine: "[3/3] Reconstructing..."

pathTable = Read Table from comma-separated file: tempPath$
selectObject: pathTable
nPath = Get number of rows

if nPath = 0
    removeObject: pathTable
    @cleanUpTempFiles
    exitScript: "Path CSV is empty."
endif

appendInfoLine: "  Path: ", nPath, " grains"

grainSec = grain_ms / 1000
xfSec    = min(0.012, grainSec * 0.40)

# Source file cache
maxSrc   = 500
nSrc     = 0
targetSR = 0
for q to maxSrc
    srcId[q] = 0
endfor
nOk = 0

for g to nPath
    selectObject: pathTable
    fn$ = Get value: g, "filename"
    ts  = Get value: g, "start_s"
    te  = Get value: g, "end_s"

    if fn$ = "" or ts = undefined or te = undefined
        appendInfoLine: "  row ", g, ": missing data — skip"
    else
        srcSlot = 0
        for q to nSrc
            if srcFn_'q'$ = fn$
                srcSlot = q
            endif
        endfor
        if srcSlot = 0
            fp$ = folderJ$ + fn$
            if fileReadable(fp$)
                lSnd = Read from file: fp$
                selectObject: lSnd
                nc2 = Get number of channels
                if nc2 > 1
                    mSnd = Convert to mono
                    removeObject: lSnd
                    lSnd = mSnd
                endif
                # --- sample-rate normalisation ---
                selectObject: lSnd
                lSR = Get sampling frequency
                if targetSR = 0
                    targetSR = lSR
                elsif lSR <> targetSR
                    rSnd = Resample: targetSR, 50
                    removeObject: lSnd
                    lSnd = rSnd
                    appendInfo: "~"
                endif
                # ----------------------------------
                nSrc = nSrc + 1
                srcFn_'nSrc'$ = fn$
                srcId[nSrc]   = lSnd
                srcSlot = nSrc
                appendInfo: "+"
            endif
        endif

        if srcSlot > 0
            sid  = srcId[srcSlot]
            selectObject: sid
            sDur = Get total duration
            tsCl = max(ts, 0.0)
            teCl = min(te, sDur)
            if teCl - tsCl >= 0.005
                selectObject: sid
                gSnd = Extract part: tsCl, teCl, "rectangular", 1, "yes"
                nOk  = nOk + 1
                Rename: "GNE_g_" + string$(nOk)
                gne_g_'nOk' = selected("Sound")
            endif
        endif
    endif
endfor

appendInfoLine: ""
appendInfoLine: "  Grains assembled: ", nOk, "/", nPath

if nOk = 0
    for q to nSrc
        removeObject: srcId[q]
    endfor
    removeObject: pathTable
    @cleanUpTempFiles
    exitScript: "No grains assembled."
endif

selectObject: gne_g_1
for g from 2 to nOk
    plusObject: gne_g_'g'
endfor
Concatenate with overlap: xfSec
resultSound = selected("Sound")
Scale peak: 0.92
outName$ = "GNE_" + modeStr$ + "_" + string$(nOk) + "gr"
Rename: outName$
outDur = Get total duration

for g to nOk
    removeObject: gne_g_'g'
endfor
for q to nSrc
    removeObject: srcId[q]
endfor

# ============================================================
# Read stats
# ============================================================
statGrains$  = "?"
statEpochs$  = "?"
statLatent$  = "?"
statPath$    = "?"
statMode$    = "?"
statSources$ = "?"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "total_grains="
    statGrains$ = parseStatLine.result$
    @parseStatLine: statsText$, "epochs="
    statEpochs$ = parseStatLine.result$
    @parseStatLine: statsText$, "latent_dim="
    statLatent$ = parseStatLine.result$
    @parseStatLine: statsText$, "path_length="
    statPath$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode="
    statMode$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_sources="
    statSources$ = parseStatLine.result$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # — Title —
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Granular Navigation Engine##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", -1.0, "half",
        ... "Mode: " + modeStr$
        ... + "  |  Grains: " + string$(nOk)
        ... + "  |  Duration: " + fixed$(outDur, 1) + " s"
        ... + "  |  Seed: " + string$(seed)

    # 8-colour palette for source files
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

    nUF = 0
    for uf to 8
        uFile_'uf'$ = ""
    endfor
    for g to nPath
        selectObject: pathTable
        fn$ = Get value: g, "filename"
        found = 0
        for uf to nUF
            if uFile_'uf'$ = fn$
                found = 1
            endif
        endfor
        if found = 0 and nUF < 8
            nUF = nUF + 1
            uFile_'nUF'$ = fn$
        endif
    endfor

    # — Grain timeline —
    Select outer viewport: 0, 8, 0.60, 1.55
    Select inner viewport: 0.6, 7.7, 0.65, 1.50
    Axes: 0, nPath, 0, 1
    for g to nPath
        selectObject: pathTable
        fn$ = Get value: g, "filename"
        ci  = 1
        for uf to nUF
            if uFile_'uf'$ = fn$
                ci = uf
            endif
        endfor
        if ci > 8
            ci = 8
        endif
        Paint rectangle: "{" + fixed$(cr#[ci], 2) + "," + fixed$(cg#[ci], 2) + "," + fixed$(cb#[ci], 2) + "}", g-0.95, g-0.05, 0.05, 0.95
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text bottom: "yes", "Grain step"
    Text top: "no", string$(nUF) + " source files — colour coded"

    # — Transition score curve —
    Select outer viewport: 0, 8, 1.65, 2.60
    Select inner viewport: 0.6, 7.7, 1.70, 2.55
    Axes: 0, nPath, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nPath, 0, 1

    nCols = 0
    selectObject: pathTable
    nCols = Get number of columns
    hasTS = 0
    for c to nCols
        cn$ = Get column label: c
        if cn$ = "transition_score"
            hasTS = 1
        endif
    endfor

    if hasTS = 1
        Colour: "{0.22, 0.50, 0.82}"
        Line width: 1.5
        prevG = 0
        prevV = 0
        for g to nPath
            selectObject: pathTable
            tv = Get value: g, "transition_score"
            if tv = undefined
                tv = 0.5
            endif
            tv = min(max(tv, 0), 1)
            if g > 1
                Draw line: prevG, prevV, g, tv
            endif
            prevG = g
            prevV = tv
        endfor
        Line width: 1
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "T-score"
    Text bottom: "yes", "Grain step"

    # — Embedding scatter —
    hasEmb = 0
    selectObject: pathTable
    nCols2 = Get number of columns
    for c to nCols2
        cn$ = Get column label: c
        if cn$ = "emb_x"
            hasEmb = 1
        endif
    endfor

    if hasEmb = 1
        Select outer viewport: 0, 8, 2.70, 4.90
        Select inner viewport: 0.6, 7.7, 2.80, 4.80

        selectObject: pathTable
        minEx = Get minimum: "emb_x"
        maxEx = Get maximum: "emb_x"
        minEy = Get minimum: "emb_y"
        maxEy = Get maximum: "emb_y"
        px = (maxEx - minEx) * 0.12 + 0.01
        py = (maxEy - minEy) * 0.12 + 0.01

        Axes: minEx-px, maxEx+px, minEy-py, maxEy+py
        Paint rectangle: "{0.97, 0.97, 0.97}", minEx-px, maxEx+px, minEy-py, maxEy+py

        Colour: "{0.78, 0.78, 0.78}"
        Line width: 0.8
        prevEx = 0
        prevEy = 0
        for g to nPath
            selectObject: pathTable
            ex = Get value: g, "emb_x"
            ey = Get value: g, "emb_y"
            if ex = undefined
                ex = 0
            endif
            if ey = undefined
                ey = 0
            endif
            if g > 1
                Draw line: prevEx, prevEy, ex, ey
            endif
            prevEx = ex
            prevEy = ey
        endfor
        Line width: 1

        dr = (maxEx - minEx + 2*px) * 0.013
        for g to nPath
            selectObject: pathTable
            ex  = Get value: g, "emb_x"
            ey  = Get value: g, "emb_y"
            fn$ = Get value: g, "filename"
            if ex = undefined
                ex = 0
            endif
            if ey = undefined
                ey = 0
            endif
            ci = 1
            for uf to nUF
                if uFile_'uf'$ = fn$
                    ci = uf
                endif
            endfor
            if ci > 8
                ci = 8
            endif
            Paint circle: "{" + fixed$(cr#[ci], 2) + "," + fixed$(cg#[ci], 2) + "," + fixed$(cb#[ci], 2) + "}", ex, ey, dr
        endfor

        selectObject: pathTable
        ex1 = Get value: 1, "emb_x"
        ey1 = Get value: 1, "emb_y"
        exN = Get value: nPath, "emb_x"
        eyN = Get value: nPath, "emb_y"
        if ex1 = undefined
            ex1 = 0
        endif
        if ey1 = undefined
            ey1 = 0
        endif
        if exN = undefined
            exN = 0
        endif
        if eyN = undefined
            eyN = 0
        endif
        dr2 = dr * 1.9
        Paint circle: "{0.10, 0.68, 0.25}", ex1, ey1, dr2
        Paint circle: "{0.80, 0.12, 0.20}", exN, eyN, dr2
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "PCA dim 2"
        Text bottom: "yes", "PCA dim 1  (green=start  red=end)"
    endif

    # — Mode strip —
    Select outer viewport: 0, 8, 5.00, 5.30
    Select inner viewport: 0.6, 7.7, 5.03, 5.27
    Axes: 0, 1, 0, 1
    if navigation_mode = 1
        Paint rectangle: "{0.22, 0.48, 0.80}", 0, 1, 0, 1
    elsif navigation_mode = 2
        Paint rectangle: "{0.15, 0.62, 0.45}", 0, 1, 0, 1
    elsif navigation_mode = 3
        Paint rectangle: "{0.78, 0.28, 0.22}", 0, 1, 0, 1
    elsif navigation_mode = 4
        Paint rectangle: "{0.78, 0.52, 0.08}", 0, 1, 0, 1
    elsif navigation_mode = 5
        Paint rectangle: "{0.35, 0.20, 0.60}", 0, 1, 0, 1
    elsif navigation_mode = 6
        Paint rectangle: "{0.78, 0.28, 0.22}", 0, 1, 0, 1
    elsif navigation_mode = 7
        Paint rectangle: "{0.15, 0.62, 0.62}", 0, 1, 0, 1
    elsif navigation_mode = 8
        Paint rectangle: "{0.40, 0.40, 0.40}", 0, 1, 0, 1
    else
        Paint rectangle: "{0.60, 0.60, 0.60}", 0, 1, 0, 1
    endif
    Font size: 9
    Colour: "White"
    Text: 0.5, "centre", 0.5, "half", "##" + modeStr$ + "##"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # — Summary panel —
    Select outer viewport: 0, 8, 5.40, 6.50
    Select inner viewport: 0.6, 7.7, 5.45, 6.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.65, "half",
        ... "Grains: " + statGrains$ + "  |  Sources: " + statSources$
        ... + "  |  Mode: " + statMode$
    Text: 0.02, "left", 0.42, "half",
        ... "Latent dim: " + statLatent$ + "  |  Epochs: " + statEpochs$
        ... + "  |  Path: " + statPath$ + " grains"
    Text: 0.02, "left", 0.20, "half",
        ... "Grain: " + fixed$(grain_ms, 0) + " ms  |  Hop: 50%"
        ... + "  |  Crossfade: " + fixed$(xfSec * 1000, 1) + " ms"
        ... + "  |  Seed: " + string$(seed)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Final info + cleanup
# ============================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:   ", outName$
appendInfoLine: "Duration: ", fixed$(outDur, 2), " s"
appendInfoLine: "Grains:   ", statGrains$
appendInfoLine: "Sources:  ", statSources$
appendInfoLine: "Mode:     ", statMode$
appendInfoLine: "Latent:   ", statLatent$
appendInfoLine: "Epochs:   ", statEpochs$
appendInfoLine: "Path:     ", statPath$

selectObject: resultSound
removeObject: pathTable

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