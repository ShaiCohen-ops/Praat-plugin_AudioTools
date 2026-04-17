# ============================================================
# Praat AudioTools - SSMComposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SSM Morph Composer — Structure-Driven Audio Recomposition
#
#   Segments a Sound into events and sends boundaries + patches
#   to a Python engine that builds a Self-Similarity Matrix (SSM),
#   transforms it, and navigates a new event path through the
#   modified structure.
#
#   Praat then reassembles the original audio by extracting and
#   concatenating events in the new order with crossfade.
#
#   SSM transformation modes:
#     Blur         — smooth structural boundaries (ambient)
#     Sharpen      — reinforce motifs (repetitive)
#     Diffusion    — spread similarity across structure (evolving)
#     MotifAmplify — amplify diagonal bands (loop-like)
#     StructureWarp — warp SSM coordinates (folded time)
#
# Dependencies (Python):
#   pip install numpy scipy soundfile
#
# Citation:
#   Cohen, S. (2026). SSM Morph Composer:
#   Structure-Driven Audio Recomposition in Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound = selected("Sound")
origName$ = selected$("Sound")
nChannels = Get number of channels
isStereo  = (nChannels = 2)

# ---- OS-SPECIFIC PYTHON DISCOVERY ----
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

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/ssm_morph_engine.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/ssm_morph_engine.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: ssm_morph_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

eventsCSV$   = tempDir$ + "temp_ssm_events.csv"
planCSV$     = tempDir$ + "temp_ssm_plan.csv"
statsTxt$    = tempDir$ + "temp_ssm_stats.txt"
patchDir$    = tempDir$
ssmOrigPng$  = tempDir$ + "temp_ssm_original.png"
ssmModPng$   = tempDir$ + "temp_ssm_modified.png"
probePy$     = tempDir$ + "temp_ssm_probe.py"
probeMarker$ = tempDir$ + "temp_ssm_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
planCSVJ$      = replace_regex$(planCSV$, "\\", "/", 0)
statsTxtJ$     = replace_regex$(statsTxt$, "\\", "/", 0)
patchDirJ$     = replace_regex$(patchDir$, "\\", "/", 0)
ssmOrigPngJ$   = replace_regex$(ssmOrigPng$, "\\", "/", 0)
ssmModPngJ$    = replace_regex$(ssmModPng$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(planCSV$)
        deleteFile: planCSV$
    endif
    if fileReadable(statsTxt$)
        deleteFile: statsTxt$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    for .iEv from 0 to 9999
        .patchPath$ = patchDir$ + "patch_" + string$(.iEv) + ".wav"
        if fileReadable(.patchPath$)
            deleteFile: .patchPath$
        else
            .iEv = 9999
        endif
    endfor
endproc

@cleanUpTempFiles

# ---- FORM ----
form SSM Morph Composer v1.1
    comment ── Preset ───────────────────────────────────────────────────
    optionmenu Preset: 1
        option Custom
        option Ambient blur
        option Motif mirror
        option Diffuse field
        option Loop engine
        option Folded time
        option Frozen texture
        option Spectral labyrinth

    comment ── SSM Mode ──────────────────────────────────────────────────
    optionmenu SSM_mode: 1
        option Blur
        option Sharpen
        option Diffusion
        option MotifAmplify
        option StructureWarp

    comment ── Structural controls ──────────────────────────────────────
    integer Output_events 300
    optionmenu Similarity_metric: 1
        option cosine
        option euclidean
    real Temperature 0.3
    integer Tabu_length 10
    real Teleport_probability 0.02
    real Visit_penalty 0.3
    integer Seed 1234

    comment ── Segmentation ──────────────────────────────────────────────
    real Silence_threshold_dB -25
    real Min_silent_interval_s 0.08
    real Min_sounding_interval_s 0.03

    comment ── Reconstruction ────────────────────────────────────────────
    real Crossfade_ms 10
    boolean Preserve_event_durations 1

    comment ── Output ────────────────────────────────────────────────────
    boolean Draw_SSM 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    sSM_mode                = 1
    output_events           = 400
    similarity_metric       = 1
    temperature             = 0.8
    tabu_length             = 5
    seed                    = 1234
    teleport_probability    = 0.03
    visit_penalty           = 0.4
    silence_threshold_dB    = -25
    min_silent_interval_s   = 0.08
    min_sounding_interval_s = 0.03
    crossfade_ms            = 30
    preserve_event_durations = 1
    presetName$             = "AmbientBlur"
elsif preset = 3
    sSM_mode                = 2
    output_events           = 200
    similarity_metric       = 1
    temperature             = 0.1
    tabu_length             = 3
    seed                    = 42
    teleport_probability    = 0.01
    visit_penalty           = 0.1
    silence_threshold_dB    = -20
    min_silent_interval_s   = 0.05
    min_sounding_interval_s = 0.03
    crossfade_ms            = 5
    preserve_event_durations = 1
    presetName$             = "MotifMirror"
elsif preset = 4
    sSM_mode                = 3
    output_events           = 300
    similarity_metric       = 1
    temperature             = 0.5
    tabu_length             = 8
    seed                    = 1234
    teleport_probability    = 0.02
    visit_penalty           = 0.3
    silence_threshold_dB    = -25
    min_silent_interval_s   = 0.08
    min_sounding_interval_s = 0.03
    crossfade_ms            = 15
    preserve_event_durations = 1
    presetName$             = "DiffuseField"
elsif preset = 5
    sSM_mode                = 4
    output_events           = 300
    similarity_metric       = 1
    temperature             = 0.05
    tabu_length             = 20
    seed                    = 7
    teleport_probability    = 0.005
    visit_penalty           = 0.5
    silence_threshold_dB    = -20
    min_silent_interval_s   = 0.05
    min_sounding_interval_s = 0.02
    crossfade_ms            = 8
    preserve_event_durations = 1
    presetName$             = "LoopEngine"
elsif preset = 6
    sSM_mode                = 5
    output_events           = 250
    similarity_metric       = 2
    temperature             = 0.4
    tabu_length             = 12
    seed                    = 999
    teleport_probability    = 0.02
    visit_penalty           = 0.3
    silence_threshold_dB    = -25
    min_silent_interval_s   = 0.08
    min_sounding_interval_s = 0.03
    crossfade_ms            = 20
    preserve_event_durations = 1
    presetName$             = "FoldedTime"
elsif preset = 7
    sSM_mode                = 1
    output_events           = 500
    similarity_metric       = 1
    temperature             = 0.02
    tabu_length             = 2
    seed                    = 1234
    teleport_probability    = 0.005
    visit_penalty           = 0.2
    silence_threshold_dB    = -30
    min_silent_interval_s   = 0.1
    min_sounding_interval_s = 0.05
    crossfade_ms            = 50
    preserve_event_durations = 1
    presetName$             = "FrozenTexture"
elsif preset = 8
    sSM_mode                = 3
    output_events           = 400
    similarity_metric       = 2
    temperature             = 0.9
    tabu_length             = 15
    seed                    = 314
    teleport_probability    = 0.05
    visit_penalty           = 0.6
    silence_threshold_dB    = -15
    min_silent_interval_s   = 0.05
    min_sounding_interval_s = 0.02
    crossfade_ms            = 10
    preserve_event_durations = 0
    presetName$             = "SpectralLabyrinth"
else
    presetName$ = "Custom"
endif

# ---- MAP OPTION MENUS TO STRINGS ----
if sSM_mode = 1
    modeStr$ = "Blur"
elsif sSM_mode = 2
    modeStr$ = "Sharpen"
elsif sSM_mode = 3
    modeStr$ = "Diffusion"
elsif sSM_mode = 4
    modeStr$ = "MotifAmplify"
else
    modeStr$ = "StructureWarp"
endif

if similarity_metric = 1
    metricStr$ = "cosine"
else
    metricStr$ = "euclidean"
endif

# ---- ORIGINAL STATS ----
selectObject: origSound
dur = Get total duration
sr  = Get sampling frequency

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== SSM Morph Composer v1.1 ==="
appendInfoLine: "Input:   ", origName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Mode:    ", modeStr$
appendInfoLine: "Metric:  ", metricStr$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/5] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy scipy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 1 — Segment into events
# ===========================================================================
appendInfoLine: "[1/5] Segmenting events..."

selectObject: origSound
if isStereo
    monoSound = Convert to mono
else
    Copy: "ssm_mono"
    monoSound = selected("Sound")
endif

selectObject: monoSound
tg = To TextGrid (silences): 100, 0, silence_threshold_dB,
    ... min_silent_interval_s, min_sounding_interval_s, "silent", "sounding"

nInt    = Get number of intervals: 1
nEvents = 0

for iInt from 1 to nInt
    selectObject: tg
    lab$ = Get label of interval: 1, iInt
    if lab$ = "sounding"
        evS = Get start time of interval: 1, iInt
        evE = Get end time of interval:   1, iInt
        if evE - evS >= min_sounding_interval_s
            nEvents = nEvents + 1
            evStart_'nEvents' = evS
            evEnd_'nEvents'   = evE
        endif
    endif
endfor

removeObject: tg, monoSound
appendInfoLine: "  Events: ", nEvents

if nEvents < 4
    appendInfoLine: "  Warning: fewer than 4 events — using 0.25 s grid"
    nEvents = 0
    t = 0
    while t + 0.25 <= dur
        nEvents = nEvents + 1
        evStart_'nEvents' = t
        evEnd_'nEvents'   = t + 0.25
        t = t + 0.25
    endwhile
    appendInfoLine: "  Grid events: ", nEvents
endif

# ===========================================================================
# Stage 2 — Export events CSV + audio patches
# ===========================================================================
appendInfoLine: "[2/5] Exporting events and patches..."

writeFileLine: eventsCSV$, "event_index,start_time,end_time,duration"

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'
    appendFileLine: eventsCSV$,
        ... string$(iEv - 1) + "," +
        ... fixed$(t1, 6) + "," +
        ... fixed$(t2, 6) + "," +
        ... fixed$(t2 - t1, 6)
endfor

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'
    selectObject: origSound
    patch = Extract part: t1, t2, "rectangular", 1, "no"
    if isStereo
        selectObject: patch
        patchMono = Convert to mono
        removeObject: patch
        patch = patchMono
    endif
    selectObject: patch
    Save as WAV file: patchDir$ + "patch_" + string$(iEv - 1) + ".wav"
    removeObject: patch
endfor

appendInfoLine: "  Wrote: ", nEvents, " events + patches"

# ===========================================================================
# Stage 3 — Run Python engine
# ===========================================================================
appendInfoLine: "[3/5] Running Python SSM engine..."

drawSsmFlag$ = "0"
if draw_SSM
    drawSsmFlag$ = "1"
endif

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + eventsCSVJ$ + """"
    ... + " """ + planCSVJ$ + """"
    ... + " """ + statsTxtJ$ + """"
    ... + " --patch_dir """    + patchDirJ$ + """"
    ... + " --mode "           + modeStr$
    ... + " --metric "         + metricStr$
    ... + " --output_events "  + string$(output_events)
    ... + " --temperature "    + fixed$(temperature, 4)
    ... + " --tabu_length "    + string$(tabu_length)
    ... + " --seed "           + string$(seed)
    ... + " --teleport_prob "  + fixed$(teleport_probability, 4)
    ... + " --visit_lambda "   + fixed$(visit_penalty, 4)
    ... + " --draw_ssm "       + drawSsmFlag$
    ... + " --ssm_orig_png """ + ssmOrigPngJ$ + """"
    ... + " --ssm_mod_png """  + ssmModPngJ$ + """"

runSystem_nocheck: pythonCall$

if not fileReadable(planCSV$)
    @cleanUpTempFiles
    exitScript: "Python engine failed — plan CSV not found. Check terminal for error details."
endif

appendInfoLine: "  Engine complete."

# ===========================================================================
# Stage 4 — Read plan + reconstruct audio
# ===========================================================================
appendInfoLine: "[4/5] Reconstructing..."

Read Strings from raw text file: planCSV$
planStrings = selected("Strings")
nPlanLines  = Get number of strings

nPlan = 0
for iLine from 2 to nPlanLines
    selectObject: planStrings
    rowStr$ = Get string: iLine
    rowStr$ = replace$(rowStr$, " ", "", 0)
    if rowStr$ <> ""
        cp    = index(rowStr$, ",")
        evIdx = number(mid$(rowStr$, cp + 1, length(rowStr$)))
        nPlan = nPlan + 1
        planArr[nPlan] = evIdx + 1
    endif
endfor
removeObject: planStrings

appendInfoLine: "  Plan: ", nPlan, " steps"

crossfade_s  = crossfade_ms / 1000
output_name$ = origName$ + "_SSMComposer"
chunkIds#    = zero#(nPlan)

for iRow from 1 to nPlan
    evIdx = planArr[iRow]
    if evIdx < 1
        evIdx = 1
    endif
    if evIdx > nEvents
        evIdx = nEvents
    endif
    t1 = evStart_'evIdx'
    t2 = evEnd_'evIdx'
    selectObject: origSound
    chunk    = Extract part: t1, t2, "rectangular", 1, "no"
    chunkDur = Get total duration
    if chunkDur > crossfade_s * 2.5
        Fade in:  0, 0,                      crossfade_s, "yes"
        Fade out: 0, chunkDur - crossfade_s, crossfade_s, "yes"
    endif
    chunkIds#[iRow] = chunk
endfor

selectObject: chunkIds#[1]
for iRow from 2 to nPlan
    plusObject: chunkIds#[iRow]
endfor
Concatenate
resultSound = selected("Sound")
Rename: output_name$

for iRow from 1 to nPlan
    removeObject: chunkIds#[iRow]
endfor

# ---- Read stats ----
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

nEvStat$    = "?"
modeStat$   = "?"
metricStat$ = "?"
tempStat$   = "?"
tabuStat$   = "?"
nPlanStat$  = "?"
outDurStat$ = "?"
entrStat$   = "?"
diagStat$   = "?"
uniqueStat$ = "?"
repStat$    = "?"

if fileReadable(statsTxt$)
    statsText$ = readFile$(statsTxt$)
    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode="
    modeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "metric="
    metricStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "temperature="
    tempStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "tabu_length="
    tabuStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "plan_length="
    nPlanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "path_entropy="
    entrStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "diag_energy="
    diagStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "unique_events="
    uniqueStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "repetition_rate="
    repStat$ = parseStatLine.result$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##SSM Morph Composer##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half",
        ... origName$ + " | " + presetName$ + " | " + modeStr$ + " | " + metricStr$
        ... + " | events=" + nEvStat$ + " | plan=" + nPlanStat$

    # === SSM matrices — drawn inline using Paint cells ===
    if draw_SSM and nEvents > 1

        # Build MFCC feature matrix from mono mix
        selectObject: origSound
        if nChannels > 1
            ssmMono = Convert to mono
        else
            Copy: "ssm_drawmono"
            ssmMono = selected("Sound")
        endif
        selectObject: ssmMono
        ssmMfcc = To MFCC: 12, 0.025, 0.01, 100, 100, 0
        mfccFrames = Get number of frames

        # Build one feature vector per event (mean MFCC over frames)
        nF = 12
        for iEv from 1 to nEvents
            t1 = evStart_'iEv'
            t2 = evEnd_'iEv'
            for c from 1 to nF
                acc_'iEv'_'c' = 0
            endfor
            cnt_'iEv' = 0
            for fr from 1 to mfccFrames
                selectObject: ssmMfcc
                ft = Get time from frame: fr
                if ft >= t1 and ft <= t2
                    for c from 1 to nF
                        v = Get value in frame: fr, c
                        if v = undefined
                            v = 0
                        endif
                        acc_'iEv'_'c' = acc_'iEv'_'c' + v
                    endfor
                    cnt_'iEv' = cnt_'iEv' + 1
                endif
            endfor
            if cnt_'iEv' > 0
                for c from 1 to nF
                    acc_'iEv'_'c' = acc_'iEv'_'c' / cnt_'iEv'
                endfor
            endif
            norm_'iEv' = 0
            for c from 1 to nF
                norm_'iEv' = norm_'iEv' + acc_'iEv'_'c' * acc_'iEv'_'c'
            endfor
            norm_'iEv' = sqrt(norm_'iEv') + 1e-9
        endfor
        removeObject: ssmMfcc, ssmMono

        # Build SSM matrix using cosine similarity
        Create simple Matrix: "SSM_orig", nEvents, nEvents, "0"
        ssmMatOrig = selected("Matrix")
        for i from 1 to nEvents
            for j from 1 to nEvents
                dot = 0
                for c from 1 to nF
                    dot = dot + acc_'i'_'c' * acc_'j'_'c'
                endfor
                sim = (dot / (norm_'i' * norm_'j') + 1) / 2
                Set value: i, j, sim
            endfor
        endfor

        # Auto-contrast stretch + gamma lift original SSM for display
        selectObject: ssmMatOrig
        ssmDispOrig = Copy: "SSM_disp_orig"
        selectObject: ssmDispOrig
        minV = Get minimum
        maxV = Get maximum
        if maxV > minV
            Formula: "(self - " + string$(minV) + ") / " + string$(maxV - minV)
        endif
        Formula: "self ^ 0.3"

        # Auto-contrast stretch + gamma lift modified SSM for display
        selectObject: ssmMatOrig
        ssmMatMod = Copy: "SSM_mod"
        selectObject: ssmMatMod
        ssmDispMod = Copy: "SSM_disp_mod"
        selectObject: ssmDispMod
        minV2 = Get minimum
        maxV2 = Get maximum
        if maxV2 > minV2
            Formula: "(self - " + string$(minV2) + ") / " + string$(maxV2 - minV2)
        endif
        Formula: "self ^ 0.3"

        # Draw side-by-side SSMs
        Select outer viewport: 0, 4, 0.6, 2.5
        selectObject: ssmDispOrig
        Paint cells: 0, 0, 0, 0, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "SSM original (" + metricStr$ + ")"
        Text bottom: "yes", "Event"
        Text left: "yes", "Event"

        Select outer viewport: 4, 8, 0.6, 2.5
        selectObject: ssmDispMod
        Paint cells: 0, 0, 0, 0, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "SSM after " + modeStr$
        Text bottom: "yes", "Event"

        removeObject: ssmMatOrig, ssmMatMod, ssmDispOrig, ssmDispMod

        ssmShift = 2.0
    else
        ssmShift = 0.0
    endif

    # === Original waveform + event boundaries ===
    Select outer viewport: 0, 8, 0.6 + ssmShift, 1.45 + ssmShift
    Select inner viewport: 0.6, 7.7, 0.65 + ssmShift, 1.40 + ssmShift
    selectObject: origSound
    Colour: "{0.5, 0.5, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Axes: 0, dur, -1, 1
    Colour: "{0.75, 0.35, 0.35}"
    Line width: 1
    for iEv from 1 to nEvents
        evT = evStart_'iEv'
        if evT > 0 and evT < dur
            Draw line: evT, -0.85, evT, 0.85
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s  |  " + string$(nEvents) + " events"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.45 + ssmShift, 2.3 + ssmShift
    Select inner viewport: 0.6, 7.7, 1.50 + ssmShift, 2.25 + ssmShift
    selectObject: resultSound
    Colour: "{0.2, 0.5, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Text top: "no", outDurStat$ + " s  |  " + nPlanStat$ + " events  (" + modeStr$ + ")"

    # === Original spectrogram ===
    Select outer viewport: 0, 8, 2.4 + ssmShift, 3.6 + ssmShift
    Select inner viewport: 0.6, 7.7, 2.50 + ssmShift, 3.50 + ssmShift
    selectObject: origSound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 3.6 + ssmShift, 4.8 + ssmShift
    Select inner viewport: 0.6, 7.7, 3.70 + ssmShift, 4.70 + ssmShift
    selectObject: resultSound
    Copy: "tmpOut"
    tmpOut = selected("Sound")
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram"
    removeObject: specOut, tmpOut

    # === Event path line ===
    Select outer viewport: 0, 8, 4.9 + ssmShift, 5.9 + ssmShift
    Select inner viewport: 0.6, 7.7, 5.00 + ssmShift, 5.80 + ssmShift
    Axes: 0, nPlan, 0, nEvents
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nPlan, 0, nEvents
    Colour: "{0.2, 0.5, 0.75}"
    Line width: 1
    for iRow from 2 to nPlan
        Draw line: iRow - 2, planArr[iRow - 1] - 1, iRow - 1, planArr[iRow] - 1
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Event"
    Text bottom: "yes", "Step"
    Text top: "no", "Event path  (entropy=" + entrStat$ + "  |  diag energy=" + diagStat$ + ")"

    # === Summary panel ===
    Select outer viewport: 0, 8, 6.0 + ssmShift, 7.0 + ssmShift
    Select inner viewport: 0.6, 7.7, 6.10 + ssmShift, 6.90 + ssmShift
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Run statistics##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.62, "half",
        ... "Events: " + nEvStat$ +
        ... " | Mode: " + modeStat$ +
        ... " | Metric: " + metricStat$ +
        ... " | Temp: " + tempStat$ +
        ... " | Tabu: " + tabuStat$
    Text: 0.02, "left", 0.38, "half",
        ... "Plan: " + nPlanStat$ + " steps" +
        ... " | Output: " + outDurStat$ + " s" +
        ... " | Unique: " + uniqueStat$ +
        ... " | Rep: " + repStat$
    Text: 0.02, "left", 0.15, "half",
        ... "Entropy: " + entrStat$ + " | Diag: " + diagStat$
    Text: 0.02, "left", -0.08, "half",
        ... "Input: " + origName$ + "   Output: " + output_name$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "Visualization skipped."
endif

# ---- FINAL CLEANUP ----
@cleanUpTempFiles

# ---- Final summary ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:       ", output_name$
appendInfoLine: "Preset:       ", presetName$
appendInfoLine: "Mode:         ", modeStat$
appendInfoLine: "Events:       ", nEvStat$
appendInfoLine: "Plan:         ", nPlanStat$, " steps"
appendInfoLine: "Output dur:   ", outDurStat$, " s"
appendInfoLine: "Path entropy: ", entrStat$
appendInfoLine: "Diag energy:  ", diagStat$
appendInfoLine: "Unique evts:  ", uniqueStat$
appendInfoLine: "Repetition:   ", repStat$

selectObject: resultSound

if play_result
    Play
endif