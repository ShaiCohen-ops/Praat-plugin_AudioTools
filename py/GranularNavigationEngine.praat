# ============================================================
# Praat AudioTools - GranularNavigationEngine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6.6 (2026) - production stable build; DSP/navigation unchanged
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.6.6:
#   - PRODUCTION STABLE: promotes the v1.6.5 crash-isolation lifecycle to the
#     normal wrapper after successful Praat 7 tests with visualization and Play
#     both enabled and disabled. The persistent stage writes are intentionally
#     retained at the same boundaries because removing them would change the
#     only configuration demonstrated stable after v1.6.3/v1.6.4 still crashed.
#   - Restored normal defaults: Draw_visualization=1 and Play_result=1.
#   - Keeps bounded-memory reconstruction, combined > log 2>&1 redirection,
#     Windows-safe Python logging, and the persistent GNE_last_stage.txt marker.
#   - No feature extraction, training, embedding, transition, navigation,
#     reconstruction, or visualization algorithm changed.
#
# Changelog v1.6.5:
#   - DIAGNOSTIC/STABILITY ISOLATION: writes a persistent last-stage marker to
#     preferencesDirectory$/GNE_last_stage.txt before/after every risky boundary
#     (Python return, CSV read, source read, grain extraction, concatenation,
#     normalization, visualization, cleanup and playback). A hard Praat crash can
#     therefore be localized without relying on the Info window surviving.
#   - Safe defaults: Draw_visualization=0 and Play_result=0. Re-enable only after
#     the core analysis/reconstruction run completes.
#   - Keeps v1.6.4 bounded-memory reconstruction and v1.6.3 > log 2>&1.
#   - No Python feature/training/embedding/navigation math changed.
#
# Changelog v1.6.4:
#   - STABILITY FIX: Praat reconstruction is now streaming/bounded-memory.
#     The wrapper no longer keeps every source Sound and every extracted grain
#     resident until the end. It holds only the current source, current grain,
#     and growing output accumulator, then releases intermediates immediately.
#   - Keeps v1.6.3 stable-I/O redirection (> log 2>&1).
#   - Python analysis/training/navigation math and visualization are unchanged.
#
# Changelog v1.6.3:
#   - STABILITY FIX ONLY: redirect BOTH Python stdout and stderr to the same
#     log (`> log 2>&1`) before returning control to Praat. This prevents
#     verbose Python/PyTorch stdout from remaining attached to Praat's process pipe.
#   - Added Praat/Python/engine path stamps for crash diagnostics.
#   - Reconstruction, cache, training, navigation and visualization are unchanged.
#
# Changelog v1.6.2:
#   - Compatibility fix: Praat no longer passes --cache_dir explicitly.
#     New Python engines still use their automatic persistent cache; older
#     engines no longer fail on an unknown argument.
#   - Visualization block unchanged from v1.6.1.
#
# Changelog v1.6.1:
#   - VISUALIZATION RESTORE ONLY: restored the complete embedding-scatter
#     block exactly to the known-working pre-v1.5.1 implementation.
#     Removes all later Paint circle (mm)/viewport experiments that caused
#     oversized markers. Runtime/cache/stereo/navigation code is unchanged.
#
# Changelog v1.6.0:
#   - Runtime: persistent two-level Python cache under plugin_AudioTools/cache/.
#     Unchanged corpus + Grain_ms reuses analysis; unchanged epochs/seed also
#     reuses the trained embedding + PCA. Navigation_mode / Path_length changes
#     therefore skip audio decode, FFT, 80-epoch training, and PCA.
#   - Runtime: removed the separate dependency-probe Python process entirely;
#     the engine itself reports missing packages, avoiding a second process launch.
#   - Visualization code is unchanged from the corrected v1.5.3 mm-marker version.
#
# Changelog v1.5.3:
#   - FIXED embedding visualization robustly: Praat has separate Paint circle
#     (world-coordinate radius) and Paint circle (mm) commands. The scatter now
#     uses Paint circle (mm) explicitly, so marker size cannot explode when the
#     PCA X/Y ranges differ. The inner viewport and Axes are reselected after
#     every painted marker because Picture drawing commands can alter viewport
#     state. No DSP/navigation changes.
#
# Changelog v1.5.2:
#   - Attempted visualization fix; superseded by v1.5.3.
#
# Changelog v1.5.1:
#   - Python no longer allocates a full N x N transition matrix; navigation
#     uses the identical score formula on demand, reducing corpus-size memory.
#   - Phase-cancelling stereo analysis is handled only when needed. The Python
#     path CSV records a representative channel for such files, and Praat uses
#     that same channel during reconstruction; normal stereo keeps the legacy
#     mono mean.
#
# Changelog v1.5:
#   - Added a "Folder" form field (mirrors VoidMosaic): type a path, or
#     leave it blank to fall back to a folder-selection dialog. The path
#     is whitespace- and trailing-slash-trimmed; cancelling exits cleanly.
#     Folder selection now happens via the form rather than a dialog that
#     pops up before it. The existing backslash-sanitize + trailing-slash
#     (folderJ$) is kept, as that path feeds both the Python engine and
#     Praat-side source reads during reconstruction. Synced version across
#     header / form title / banner.
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
pyLog$       = temporaryDirectory$ + "/temp_gne_error.log"
crashMarker$ = preferencesDirectory$ + "/GNE_last_stage.txt"
writeFileLine: crashMarker$, "v1.6.6 wrapper_start"

# ---- Cleanup Procedure ----
procedure cleanUpTempFiles
    if fileReadable(tempPath$)
        deleteFile: tempPath$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Granular Navigation Engine v1.6.6
    comment === Audio Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
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

# ---- FOLDER DISCOVERY ----
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Folder field is left blank. Trim whitespace and trailing slashes.
folder$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)

if folder$ == ""
    folder$ = chooseFolder$: "Select folder of audio files"
    folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)
endif

if folder$ == ""
    exitScript: "Operation cancelled. Please supply a valid folder path."
endif

# Universally sanitize backslashes to forward slashes to prevent Windows
# escape-character crashes. folderJ$ feeds both the Python --folder
# argument and Praat-side source reads during reconstruction, so it keeps
# a trailing slash.
folderJ$ = replace_regex$(folder$, "\\", "/", 0)
if right$(folderJ$, 1) <> "/"
    folderJ$ = folderJ$ + "/"
endif

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
writeInfoLine: "=== Granular Navigation Engine v1.6.6 ==="
appendInfoLine: "Folder: ", folderJ$
appendInfoLine: "Mode:   ", modeStr$
appendInfoLine: "Grain:  ", grain_ms, " ms"
appendInfoLine: "Path:   ", path_length, " grains"
appendInfoLine: "Praat:  ", appVersion$()
appendInfoLine: "Python: ", pythonCmd$
appendInfoLine: "Engine: ", pythonScript$
appendInfoLine: "Stability marker: ", crashMarker$
appendInfoLine: ""

# ============================================================
# Stage 1 — Run Python engine
# ============================================================
appendInfoLine: "[1/2] Running Python engine..."

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

# Praat 7 stability rule: never leave Python stdout attached to Praat.
# Capture stdout and stderr together so print(), warnings and tracebacks all
# land in one diagnostic file and the child cannot block on an unread pipe.
pyCmd$ = pyCmd$ + " > """ + pyLog$ + """ 2>&1"

writeFileLine: crashMarker$, "before_python_runSystem"
runSystem_nocheck: pyCmd$
writeFileLine: crashMarker$, "after_python_runSystem"

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
# Stage 2 — Read path and reconstruct
# ============================================================
appendInfoLine: "[2/2] Reconstructing..."

writeFileLine: crashMarker$, "before_path_csv_read"
pathTable = Read Table from comma-separated file: tempPath$
writeFileLine: crashMarker$, "after_path_csv_read"
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

# Bounded-memory reconstruction.
# The old implementation cached every source Sound and retained every grain
# object until one final Concatenate with overlap. Large/long corpora could
# therefore leave hundreds of decoded Sounds resident inside Praat at once.
# Keep only: current source + current grain + growing accumulator.
targetSR    = 0
nOk         = 0
resultSound = 0
writeFileLine: crashMarker$, "reconstruction_start nPath=", nPath

for g to nPath
    selectObject: pathTable
    fn$ = Get value: g, "filename"
    ts  = Get value: g, "start_s"
    te  = Get value: g, "end_s"
    analysisCh = Get value: g, "analysis_channel"
    if analysisCh = undefined
        analysisCh = 0
    endif

    if fn$ = "" or ts = undefined or te = undefined
        appendInfoLine: "  row ", g, ": missing data - skip"
    else
        fp$ = folderJ$ + fn$
        if fileReadable(fp$)
            writeFileLine: crashMarker$, "before_source_read grain=", g, " file=", fn$
            lSnd = Read from file: fp$
            writeFileLine: crashMarker$, "after_source_read grain=", g, " file=", fn$
            selectObject: lSnd
            nc2 = Get number of channels
            if nc2 > 1
                if analysisCh >= 1 and analysisCh <= nc2
                    mSnd = Extract one channel: round(analysisCh)
                else
                    mSnd = Convert to mono
                endif
                removeObject: lSnd
                lSnd = mSnd
            endif

            # Sample-rate normalisation while only one source is resident.
            selectObject: lSnd
            lSR = Get sampling frequency
            if targetSR = 0
                targetSR = lSR
            elsif lSR <> targetSR
                writeFileLine: crashMarker$, "before_resample grain=", g, " from=", lSR, " to=", targetSR
                rSnd = Resample: targetSR, 50
                writeFileLine: crashMarker$, "after_resample grain=", g
                removeObject: lSnd
                lSnd = rSnd
            endif

            selectObject: lSnd
            sDur = Get total duration
            tsCl = max(ts, 0.0)
            teCl = min(te, sDur)

            if teCl - tsCl >= 0.005
                writeFileLine: crashMarker$, "before_extract grain=", g, " ts=", tsCl, " te=", teCl
                gSnd = Extract part: tsCl, teCl, "rectangular", 1, "yes"
                writeFileLine: crashMarker$, "after_extract grain=", g
                # The full source is no longer needed once its grain exists.
                removeObject: lSnd
                lSnd = 0

                nOk = nOk + 1
                if nOk = 1
                    resultSound = gSnd
                    selectObject: resultSound
                    Rename: "GNE_acc"
                else
                    oldResult = resultSound
                    selectObject: oldResult
                    plusObject: gSnd
                    writeFileLine: crashMarker$, "before_concatenate grain=", g, " assembled=", nOk
                    Concatenate with overlap: xfSec
                    writeFileLine: crashMarker$, "after_concatenate grain=", g, " assembled=", nOk
                    newResult = selected("Sound")
                    removeObject: oldResult
                    removeObject: gSnd
                    resultSound = newResult
                endif
            else
                removeObject: lSnd
            endif
        else
            appendInfoLine: "  row ", g, ": source unreadable - skip"
        endif
    endif
endfor

appendInfoLine: ""
writeFileLine: crashMarker$, "reconstruction_loop_complete nOk=", nOk
appendInfoLine: "  Grains assembled: ", nOk, "/", nPath

if nOk = 0
    removeObject: pathTable
    @cleanUpTempFiles
    exitScript: "No grains assembled."
endif

selectObject: resultSound
writeFileLine: crashMarker$, "before_scale_peak"
Scale peak: 0.92
writeFileLine: crashMarker$, "after_scale_peak"
outName$ = "GNE_" + modeStr$ + "_" + string$(nOk) + "gr"
Rename: outName$
outDur = Get total duration

# ============================================================
# Read stats
# ============================================================
statGrains$  = "?"
statEpochs$  = "?"
statLatent$  = "?"
statPath$    = "?"
statMode$    = "?"
statSources$ = "?"
statPhaseSafe$ = "0"
statAnalysisCache$ = "0"
statEmbeddingCache$ = "0"
statExtractTime$ = "?"
statTrainTime$ = "?"
statNavigateTime$ = "?"
statTotalTime$ = "?"

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
    @parseStatLine: statsText$, "phase_safe_fallback_files="
    statPhaseSafe$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_cache_hit="
    statAnalysisCache$ = parseStatLine.result$
    @parseStatLine: statsText$, "embedding_cache_hit="
    statEmbeddingCache$ = parseStatLine.result$
    @parseStatLine: statsText$, "timing_extract_s="
    statExtractTime$ = parseStatLine.result$
    @parseStatLine: statsText$, "timing_train_s="
    statTrainTime$ = parseStatLine.result$
    @parseStatLine: statsText$, "timing_navigate_s="
    statNavigateTime$ = parseStatLine.result$
    @parseStatLine: statsText$, "timing_total_s="
    statTotalTime$ = parseStatLine.result$
endif

appendInfoLine: "  Cache: analysis=", statAnalysisCache$, " embedding=", statEmbeddingCache$
appendInfoLine: "  Python timing: analysis ", statExtractTime$, "s | train ", statTrainTime$, "s | navigate ", statNavigateTime$, "s | total ", statTotalTime$, "s"

writeFileLine: crashMarker$, "stats_complete"

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    writeFileLine: crashMarker$, "before_visualization"
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
        ... + "  |  phase-safe files: " + statPhaseSafe$
    Text: 0.02, "left", 0.42, "half",
        ... "Latent dim: " + statLatent$ + "  |  Epochs: " + statEpochs$
        ... + "  |  Path: " + statPath$ + " grains"
        ... + "  |  Python: " + statTotalTime$ + " s"
    Text: 0.02, "left", 0.20, "half",
        ... "Grain: " + fixed$(grain_ms, 0) + " ms  |  Hop: 50%"
        ... + "  |  Crossfade: " + fixed$(xfSec * 1000, 1) + " ms"
        ... + "  |  Seed: " + string$(seed)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    writeFileLine: crashMarker$, "after_visualization"
else
    writeFileLine: crashMarker$, "visualization_skipped"
endif

# ============================================================
# Final info + cleanup
# ============================================================
writeFileLine: crashMarker$, "before_final_cleanup"
@cleanUpTempFiles
writeFileLine: crashMarker$, "after_final_cleanup"

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
writeFileLine: crashMarker$, "before_remove_path_table"
removeObject: pathTable
writeFileLine: crashMarker$, "after_remove_path_table"

if play_result
    writeFileLine: crashMarker$, "before_play"
    Play
    writeFileLine: crashMarker$, "after_play"
else
    writeFileLine: crashMarker$, "play_skipped_complete"
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