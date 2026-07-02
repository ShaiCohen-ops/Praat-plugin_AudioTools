# ============================================================
# Praat AudioTools - RhythmicVoiceFlattener.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.2 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic Voice Flattener v3.2 - Compositional Voice Transformer
#
#   Takes a selected Sound (spoken or vocal audio), flattens its
#   pitch contour to a single centre pitch, and rebuilds the audio
#   as a formally shaped composition where all musical interest
#   arises from rhythm, timing, silence, density, grouping,
#   accent, and gesture structure - not melody.
#
#   v3 additions:
#     - CSP rhythmic engine: backtracking solver enforces per-gesture
#       duration-budget, density, and entropy constraints; replaces
#       independent weighted-table sampling from v2.
#     - Polytonal metric grid: each gesture tracks up to 3 simultaneous
#       BPM frameworks; nearest_beat_dur() searches all frameworks.
#     - Tempo dramaturgy arc: full accelerando / ritardando / metric-
#       modulation / wave trajectory (not just mild BPM offset).
#     - Note-duration fetcher: assigns articulation label and note_dur_s
#       (staccatissimo → staccato → mezzo-staccato → portato →
#        tenuto → sostenuto) to every event.
#     - Fixed free mode: routes through CSP engine with near-zero grid
#       weight instead of bypassing and leaving ratios at 1.0.
#     - Two new score columns: note_dur_s, articulation.
#     - Three new stats fields: csp_budget_dev, csp_density_dev,
#       csp_entropy_dev.
#   v2 additions (retained):
#     - Per-event rhythmic operations (sustain / compress / stutter /
#       drop / long-short / short-long / burst / grid)
#     - Intra-gesture rest injection (silence inside gestures)
#     - Per-gesture BPM (metric heterogeneity across gestures)
#     - New arrangement modes: fragmented / density / palindrome
#     - New tension arcs: plateau / fractal / staircase / pulse
#     - Structural motif scatter (multiple echoes, inverted durations)
#     - 10 named presets (none / minimal / pulse / scattered /
#       mechanical / decay / breath / ritual / stutter_loop / ghost)
#     - Sparsity parameter
#     - skip column in score CSV for dropped events
#
#   Role separation:
#     Praat  - event segmentation, feature extraction (F0,
#              intensity, spectral centroid), PSOLA pitch
#              flattening per event, score assembly.
#     Python - rhythmic operations, per-gesture tempo, tension arc,
#              silence architecture (inter + intra gesture),
#              duration ratios, accent weights, gesture arrangement,
#              repetition and motif scatter.
#
# Changelog v3.2:
#   - Fixed stereo crash: the analysis/PSOLA path used mono-only
#     commands (To Spectrum, To Manipulation) and the assembly mixes
#     mono silences via Concatenate. The input is now folded to mono
#     once and all analysis + extraction run on that copy. Mono input
#     is unchanged.
#   - Viz: title/subtitle split into separate bands (subtitle was at
#     y=-1.1, overprinting the original waveform).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origSound  = selected("Sound")
origName$  = selected$("Sound")

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

pythonScript$ = pluginDir$ + "py/rhythmic_voice_flattener.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/rhythmic_voice_flattener.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: rhythmic_voice_flattener.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

eventsCSV$   = tempDir$ + "temp_rvf_events.csv"
scoreCSV$    = tempDir$ + "temp_rvf_score.csv"
statsFile$   = tempDir$ + "temp_rvf_stats.txt"
probePy$     = tempDir$ + "temp_rvf_probe.py"
probeMarker$ = tempDir$ + "temp_rvf_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
scoreCSVJ$     = replace_regex$(scoreCSV$, "\\", "/", 0)
statsFileJ$    = replace_regex$(statsFile$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(scoreCSV$)
        deleteFile: scoreCSV$
    endif
    if fileReadable(statsFile$)
        deleteFile: statsFile$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Rhythmic Voice Flattener v3.2
    comment — Preset (overrides arrangement / arc / rhythm / sparsity) —
    optionmenu Preset: 1
        option none
        option minimal
        option pulse
        option scattered
        option mechanical
        option decay
        option breath
        option ritual
        option stutter_loop
        option ghost
    comment — Manual controls (ignored when a preset is active) —
    optionmenu Arrangement: 2
        option original
        option spectral
        option reversed
        option fragmented
        option density
        option palindrome
    optionmenu Tension_arc: 2
        option rising
        option arch
        option falling
        option wave
        option plateau
        option fractal
        option staircase
        option pulse
    optionmenu Rhythm: 2
        option free
        option soft
        option hard
    comment — Sparsity (0 = dense, 1 = sparse) —
    real Sparsity 0.5
    real Target_pitch_hz 0
    boolean Allow_repetition 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Hardcoded analysis constants
silThr       = -30
minSilS      = 0.040
minEventS    = 0.025
gestPauseThr = 0.28

# ---- MODE STRINGS ----
if preset = 1
    presetStr$ = "none"
elsif preset = 2
    presetStr$ = "minimal"
elsif preset = 3
    presetStr$ = "pulse"
elsif preset = 4
    presetStr$ = "scattered"
elsif preset = 5
    presetStr$ = "mechanical"
elsif preset = 6
    presetStr$ = "decay"
elsif preset = 7
    presetStr$ = "breath"
elsif preset = 8
    presetStr$ = "ritual"
elsif preset = 9
    presetStr$ = "stutter_loop"
else
    presetStr$ = "ghost"
endif

if arrangement = 1
    arrangStr$ = "original"
elsif arrangement = 2
    arrangStr$ = "spectral"
elsif arrangement = 3
    arrangStr$ = "reversed"
elsif arrangement = 4
    arrangStr$ = "fragmented"
elsif arrangement = 5
    arrangStr$ = "density"
else
    arrangStr$ = "palindrome"
endif

if tension_arc = 1
    arcStr$ = "rising"
elsif tension_arc = 2
    arcStr$ = "arch"
elsif tension_arc = 3
    arcStr$ = "falling"
elsif tension_arc = 4
    arcStr$ = "wave"
elsif tension_arc = 5
    arcStr$ = "plateau"
elsif tension_arc = 6
    arcStr$ = "fractal"
elsif tension_arc = 7
    arcStr$ = "staircase"
else
    arcStr$ = "pulse"
endif

if rhythm = 1
    rhythmStr$ = "free"
elsif rhythm = 2
    rhythmStr$ = "soft"
else
    rhythmStr$ = "hard"
endif

clearinfo
writeInfoLine:  "=== Rhythmic Voice Flattener v3.2 ==="
appendInfoLine: "Source:      ", origName$
appendInfoLine: "Preset:      ", presetStr$
appendInfoLine: "Arrangement: ", arrangStr$
appendInfoLine: "Arc:         ", arcStr$
appendInfoLine: "Rhythm:      ", rhythmStr$
appendInfoLine: "Sparsity:    ", fixed$(sparsity, 2)
appendInfoLine: ""

# ---- BASIC SOUND INFO ----
selectObject: origSound
totalDur  = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels

# Voice flattening is inherently mono (PSOLA/To Manipulation and the
# mono silence assembly require it); fold a stereo input down once and
# run all analysis + extraction on that copy.
if nChannels > 1
    selectObject: origSound
    workSound = Convert to mono
else
    selectObject: origSound
    workSound = Copy: "rvf_work_mono"
endif

# ===========================================================================
# Stage 0 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[0/4] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy"
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
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ============================================================
# Stage 1 - Analyse events and write events CSV
# ============================================================
appendInfoLine: "[1/4] Analysing events..."

selectObject: workSound
intObj   = To Intensity: 100, 0, "yes"

selectObject: workSound
pitchObj = To Pitch: 0, 50, 800

selectObject: intObj
tgObj = To TextGrid (silences): silThr, minSilS, minEventS, "silent", "sounding"

selectObject: tgObj
nIntervals = Get number of intervals: 1

if fileReadable(eventsCSV$)
    deleteFile: eventsCSV$
endif
writeFileLine: eventsCSV$,
    ... "seg_id,start_s,end_s,voiced,f0_hz,intensity_db,centroid_hz,gesture_id,pause_after_s"

evId      = 0
gestureId = 1

for iInt from 1 to nIntervals
    selectObject: tgObj
    lab$ = Get label of interval: 1, iInt
    if lab$ = "sounding"
        tS      = Get start time of interval: 1, iInt
        tE      = Get end time of interval:   1, iInt
        segDur  = tE - tS

        if segDur >= minEventS
            evId = evId + 1
            thisGestId = gestureId

            pauseAfter = 0
            if iInt < nIntervals
                selectObject: tgObj
                nxtLab$ = Get label of interval: 1, iInt + 1
                if nxtLab$ = "silent"
                    nxtEnd     = Get end time of interval: 1, iInt + 1
                    pauseAfter = nxtEnd - tE
                endif
            endif

            selectObject: pitchObj
            f0med = Get quantile: tS, tE, 0.5, "Hertz"
            if f0med = undefined or f0med = 0
                isVoiced = 0
                f0med    = 0
            else
                isVoiced = 1
            endif

            selectObject: intObj
            intVal = Get mean: tS, tE, "energy"
            if intVal = undefined
                intVal = 60
            endif

            selectObject: workSound
            segTmp  = Extract part: tS, tE, "Hanning", 1, "no"
            selectObject: segTmp
            specTmp = To Spectrum: "yes"
            centHz  = Get centre of gravity: 2
            if centHz = undefined
                centHz = 2000
            endif
            removeObject: specTmp, segTmp

            line$ = string$(evId)       + ","
                ... + fixed$(tS,         6) + ","
                ... + fixed$(tE,         6) + ","
                ... + string$(isVoiced)     + ","
                ... + fixed$(f0med,      3) + ","
                ... + fixed$(intVal,     3) + ","
                ... + fixed$(centHz,     2) + ","
                ... + string$(thisGestId)   + ","
                ... + fixed$(pauseAfter, 6)
            appendFileLine: eventsCSV$, line$

            if pauseAfter > gestPauseThr
                gestureId = gestureId + 1
            endif
        endif
    endif
endfor

removeObject: intObj, pitchObj, tgObj
nGestures = gestureId

appendInfoLine: "  Events: ", evId, "  Gestures: ", nGestures

if evId = 0
    @cleanUpTempFiles
    exitScript: "No sounding events found." + newline$ + "Try a lower silence threshold or a longer input."
endif

# ============================================================
# Stage 2 - Run Python engine
# ============================================================
appendInfoLine: "[2/4] Running Python engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " --events """      + eventsCSVJ$  + """"
    ... + " --score """       + scoreCSVJ$   + """"
    ... + " --stats """       + statsFileJ$  + """"
    ... + " --arrangement "   + arrangStr$
    ... + " --arc "           + arcStr$
    ... + " --rhythm "        + rhythmStr$
    ... + " --target_f0 "     + fixed$(target_pitch_hz, 1)
    ... + " --allow_rep "     + string$(allow_repetition)
    ... + " --sparsity "      + fixed$(sparsity, 4)
    ... + " --preset "        + presetStr$

runSystem_nocheck: pythonCall$

if not fileReadable(scoreCSV$)
    @cleanUpTempFiles
    exitScript: "Python engine failed - score CSV not found." + newline$ + "Check the terminal for Python error messages."
endif

appendInfoLine: "  Engine complete."

# ============================================================
# Stage 3 - Read score and reconstruct
# ============================================================
appendInfoLine: "[3/4] Reconstructing..."

scoreTable = Read Table from comma-separated file: scoreCSV$
selectObject: scoreTable
nScore = Get number of rows

if nScore = 0
    removeObject: scoreTable
    @cleanUpTempFiles
    exitScript: "Score CSV is empty."
endif

# Read stats for visualization
tgtF0global   = 130.0
statTgtF0$    = "?"
statGestures$ = "?"
statBPM$      = "?"
statEvents$   = "?"
statPreset$   = presetStr$
statBudgetDev$ = "?"
statDensityDev$ = "?"
statEntropyDev$ = "?"

if fileReadable(statsFile$)
    statsText$ = readFile$(statsFile$)
    @parseStatLine: statsText$, "target_f0="
    statTgtF0$    = parseStatLine.result$
    tgtF0global   = number(statTgtF0$)
    @parseStatLine: statsText$, "n_gestures="
    statGestures$ = parseStatLine.result$
    @parseStatLine: statsText$, "bpm="
    statBPM$      = parseStatLine.result$
    @parseStatLine: statsText$, "n_events="
    statEvents$   = parseStatLine.result$
    @parseStatLine: statsText$, "preset="
    statPreset$   = parseStatLine.result$
    @parseStatLine: statsText$, "csp_budget_dev="
    statBudgetDev$  = parseStatLine.result$
    @parseStatLine: statsText$, "csp_density_dev="
    statDensityDev$ = parseStatLine.result$
    @parseStatLine: statsText$, "csp_entropy_dev="
    statEntropyDev$ = parseStatLine.result$
endif

effectiveArcStr$    = arcStr$
effectiveArrangStr$ = arrangStr$
effectiveRhythmStr$ = rhythmStr$
effectiveSparsity   = sparsity

if presetStr$ = "minimal"
    effectiveArcStr$    = "falling"
    effectiveArrangStr$ = "original"
    effectiveRhythmStr$ = "free"
    effectiveSparsity   = 0.80
elsif presetStr$ = "pulse"
    effectiveArcStr$    = "arch"
    effectiveArrangStr$ = "original"
    effectiveRhythmStr$ = "hard"
    effectiveSparsity   = 0.20
elsif presetStr$ = "scattered"
    effectiveArcStr$    = "wave"
    effectiveArrangStr$ = "fragmented"
    effectiveRhythmStr$ = "soft"
    effectiveSparsity   = 0.65
elsif presetStr$ = "mechanical"
    effectiveArcStr$    = "arch"
    effectiveArrangStr$ = "density"
    effectiveRhythmStr$ = "hard"
    effectiveSparsity   = 0.15
elsif presetStr$ = "decay"
    effectiveArcStr$    = "falling"
    effectiveArrangStr$ = "reversed"
    effectiveRhythmStr$ = "soft"
    effectiveSparsity   = 0.50
elsif presetStr$ = "breath"
    effectiveArcStr$    = "arch"
    effectiveArrangStr$ = "original"
    effectiveRhythmStr$ = "free"
    effectiveSparsity   = 0.75
elsif presetStr$ = "ritual"
    effectiveArcStr$    = "wave"
    effectiveArrangStr$ = "palindrome"
    effectiveRhythmStr$ = "soft"
    effectiveSparsity   = 0.40
elsif presetStr$ = "stutter_loop"
    effectiveArcStr$    = "pulse"
    effectiveArrangStr$ = "spectral"
    effectiveRhythmStr$ = "hard"
    effectiveSparsity   = 0.30
elsif presetStr$ = "ghost"
    effectiveArcStr$    = "falling"
    effectiveArrangStr$ = "original"
    effectiveRhythmStr$ = "free"
    effectiveSparsity   = 0.90
endif

# Map effective arc string → integer for the drawing loop
effectiveArcInt = 1
if effectiveArcStr$ = "rising"
    effectiveArcInt = 1
elsif effectiveArcStr$ = "arch"
    effectiveArcInt = 2
elsif effectiveArcStr$ = "falling"
    effectiveArcInt = 3
elsif effectiveArcStr$ = "wave"
    effectiveArcInt = 4
elsif effectiveArcStr$ = "plateau"
    effectiveArcInt = 5
elsif effectiveArcStr$ = "fractal"
    effectiveArcInt = 6
elsif effectiveArcStr$ = "staircase"
    effectiveArcInt = 7
elsif effectiveArcStr$ = "pulse"
    effectiveArcInt = 8
endif

xfSec   = 0.005
nSounds = 0
nOk     = 0
prevWasSound = 0

for row from 1 to nScore
    selectObject: scoreTable
    srcStart = Get value: row, "source_start_s"
    srcEnd   = Get value: row, "source_end_s"
    isVcd    = Get value: row, "voiced"
    tgtF0    = Get value: row, "target_pitch_hz"
    durRat   = Get value: row, "duration_ratio"
    ampOff   = Get value: row, "amplitude_db_offset"
    silAfter = Get value: row, "silence_after_s"
    skipRow  = Get value: row, "skip"

    if srcStart = undefined or srcEnd = undefined
        # skip
    elsif skipRow = 1
        skipDur = srcEnd - srcStart
        if skipDur < 0.005
            skipDur = 0.060
        endif
        if silAfter <> undefined and silAfter > 0.005
            skipDur = skipDur + silAfter
        endif
        silSnd = Create Sound from formula: "sil", 1, 0, skipDur, sr, "0"
        nSounds = nSounds + 1
        score_snd_'nSounds' = silSnd
        prevWasSound = 0
    else
        if srcStart < 0
            srcStart = 0
        endif
        if srcEnd > totalDur
            srcEnd = totalDur
        endif
        segDur = srcEnd - srcStart

        if segDur >= 0.005
            selectObject: workSound
            segSnd = Extract part: srcStart, srcEnd, "rectangular", 1, "no"

            if prevWasSound = 1
                selectObject: segSnd
                nSegSamples = Get number of samples
                fadeSamples = round(xfSec * sr)
                if fadeSamples > 1 and fadeSamples < nSegSamples / 4
                    selectObject: segSnd
                    fadeEnd = fadeSamples / sr
                    Formula (part): 0, fadeEnd, 1, 1,
                        ... "self * (x / " + string$(fadeEnd) + ")"
                endif
            endif

            safetyFloor = (3.0 / segDur) + 1
            if tgtF0 > 50
                qualityFloor = tgtF0 * 0.40
            else
                qualityFloor = safetyFloor
            endif
            manipFloor = max(safetyFloor, qualityFloor)
            
            psolaOk = 1
            if manipFloor > tgtF0 * 0.85 and tgtF0 > 50
                if safetyFloor > tgtF0 * 0.85
                    psolaOk = 0
                else
                    manipFloor = tgtF0 * 0.40
                endif
            endif
            manipCeiling = manipFloor * 8
            if manipCeiling > 1400
                manipCeiling = 1400
            endif
            if manipFloor >= manipCeiling / 2
                manipCeiling = manipFloor * 3
            endif

            if isVcd = 1 and segDur >= 0.025 and tgtF0 > 50
                if durRat = undefined or durRat <= 0
                    durRat = 1.0
                endif
                durRat = max(0.50, min(4.0, durRat))

                if psolaOk = 1
                    selectObject: segSnd
                    manip = To Manipulation: 0.01, manipFloor, manipCeiling

                    ptNew = Create PitchTier: "flat", 0, segDur
                    Add point: segDur * 0.05, tgtF0
                    Add point: segDur * 0.95, tgtF0
                    selectObject: manip
                    plusObject: ptNew
                    Replace pitch tier

                    dtNew = Create DurationTier: "dur", 0, segDur
                    Add point: segDur * 0.10, durRat
                    Add point: segDur * 0.90, durRat
                    selectObject: manip
                    plusObject: dtNew
                    Replace duration tier

                    selectObject: manip
                    synthSnd = Get resynthesis (overlap-add)
                    removeObject: manip, ptNew, dtNew, segSnd
                    segSnd = synthSnd
                endif

            elsif isVcd = 0 and durRat <> undefined and durRat > 0 and durRat <> 1
                durRat = max(0.50, min(4.0, durRat))
                selectObject: segSnd
                manip = To Manipulation: 0.01, manipFloor, manipCeiling
                dtNew = Create DurationTier: "dur", 0, segDur
                Add point: segDur * 0.10, durRat
                Add point: segDur * 0.90, durRat
                selectObject: manip
                plusObject: dtNew
                Replace duration tier
                selectObject: manip
                synthSnd = Get resynthesis (overlap-add)
                removeObject: manip, dtNew, segSnd
                segSnd = synthSnd
            endif

            if ampOff <> undefined and ampOff <> 0
                selectObject: segSnd
                ampScale = 10 ^ (ampOff / 20)
                Formula: "self * " + fixed$(ampScale, 6)
            endif

            nSounds = nSounds + 1
            score_snd_'nSounds' = segSnd
            nOk = nOk + 1
            prevWasSound = 1

            if silAfter = undefined
                silAfter = 0
            endif
            if silAfter > 0.005
                silSnd = Create Sound from formula: "sil", 1, 0, silAfter, sr, "0"
                nSounds = nSounds + 1
                score_snd_'nSounds' = silSnd
                prevWasSound = 0
            endif
        endif
    endif
endfor

removeObject: workSound

appendInfoLine: "  Assembled: ", nOk, "/", nScore, " events"

if nOk = 0
    removeObject: scoreTable
    @cleanUpTempFiles
    exitScript: "No events could be reconstructed."
endif

outName$ = "RVF_" + origName$ + "_" + presetStr$
if presetStr$ = "none"
    outName$ = "RVF_" + origName$ + "_" + arrangStr$
endif

if nSounds = 1
    selectObject: score_snd_1
    Rename: outName$
    resultSound = selected("Sound")
else
    selectObject: score_snd_1
    for s from 2 to nSounds
        plusObject: score_snd_'s'
    endfor
    Concatenate
    resultSound = selected("Sound")
    Scale peak: 0.92
    Rename: outName$
    for s to nSounds
        removeObject: score_snd_'s'
    endfor
endif

selectObject: resultSound
outDur = Get total duration
removeObject: scoreTable

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[4/4] Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7

    # === Title (own band) ===
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Rhythmic Voice Flattener v3.2##"

    # === Subtitle (separate band) ===
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.5, "half",
        ... "preset: " + statPreset$
        ... + "  | " + effectiveArrangStr$
        ... + "  | arc: " + effectiveArcStr$
        ... + "  | rhythm: " + effectiveRhythmStr$
        ... + "  | F0: " + fixed$(tgtF0global, 0) + " Hz"
        ... + "  | dur: " + fixed$(outDur, 1) + " s"

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    selectObject: origSound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(totalDur, 2) + " s"

    # === Composed waveform ===
    Select outer viewport: 0, 8, 1.50, 2.40
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    Colour: "{0.15, 0.58, 0.62}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Composed"
    Text bottom: "yes", "Time (s)"

    # === Tension arc ===
    Select outer viewport: 0, 8, 2.50, 3.20
    Select inner viewport: 0.6, 7.7, 2.55, 3.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, 1, 0, 1

    nArcPts = 120
    Colour: "{0.22, 0.48, 0.80}"
    Line width: 2
    prevAx = 0
    prevAy = 0
    for iAp from 1 to nArcPts
        ax = (iAp - 1) / (nArcPts - 1)
        if effectiveArcInt = 1
            ay = ax
        elsif effectiveArcInt = 2
            if ax < 2/3
                ay = ax * (3/2)
            else
                ay = (1 - ax) * 3.0
            endif
            if ay > 1
                ay = 1
            endif
            if ay < 0
                ay = 0
            endif
        elsif effectiveArcInt = 3
            ay = 1 - ax
        elsif effectiveArcInt = 4
            ay = 0.5 + 0.5 * sin(2 * pi * ax)
        elsif effectiveArcInt = 5
            rise = 1 / (1 + exp(-20 * (ax - 0.25)))
            fall = 1 / (1 + exp( 20 * (ax - 0.88)))
            ay = rise * fall
        elsif effectiveArcInt = 6
            if ax < 2/3
                ay = ax * (3/2)
            else
                ay = (1 - ax) * 3.0
            endif
            ay = ay + 0.18 * sin(7 * pi * ax) + 0.09 * sin(17 * pi * ax)
            if ay > 1
                ay = 1
            endif
            if ay < 0
                ay = 0
            endif
        elsif effectiveArcInt = 7
            nSteps = 5
            ay = floor(ax * nSteps) / nSteps
            ay = ay - 0.12 * sin(nSteps * pi * ax) * (ax < 0.95)
            if ay > 1
                ay = 1
            endif
            if ay < 0
                ay = 0
            endif
        else
            ay = 0.15 + 0.85 * (sin(pi * ax * 5.5)) ^ 2
        endif
        
        ay = ay * 0.78 + 0.11
        if iAp > 1
            Draw line: prevAx, prevAy, ax, ay
        endif
        prevAx = ax
        prevAy = ay
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Tension"
    Text bottom: "yes", "arc: " + effectiveArcStr$

    # === Summary panel ===
    Select outer viewport: 0, 8, 3.30, 4.50
    Select inner viewport: 0.6, 7.7, 3.35, 4.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.76, "half",
        ... "Source: " + origName$
        ... + "  | Events: " + statEvents$
        ... + "  | Gestures: " + statGestures$
    Text: 0.02, "left", 0.60, "half",
        ... "Target F0: " + statTgtF0$ + " Hz"
        ... + "  | Tempo: " + statBPM$ + " BPM"
        ... + "  | Preset: " + statPreset$
    Text: 0.02, "left", 0.44, "half",
        ... "In: " + fixed$(totalDur, 1) + " s"
        ... + "  | Out: " + fixed$(outDur, 1) + " s"
        ... + "  | Rhythm: " + effectiveRhythmStr$
        ... + "  | Sparsity: " + fixed$(effectiveSparsity, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "Arc: " + effectiveArcStr$
        ... + "  | Arrangement: " + effectiveArrangStr$
    Text: 0.02, "left", 0.12, "half",
        ... "CSP dev — budget: " + statBudgetDev$
        ... + "  density: " + statDensityDev$
        ... + "  entropy: " + statEntropyDev$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ============================================================
# Cleanup temp files
# ============================================================
@cleanUpTempFiles

# ============================================================
# Final info + play
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", outName$
appendInfoLine: "Duration:  ", fixed$(outDur, 2), " s"
appendInfoLine: "Events:    ", statEvents$
appendInfoLine: "Gestures:  ", statGestures$
appendInfoLine: "Target F0: ", statTgtF0$, " Hz"
appendInfoLine: "Tempo:     ", statBPM$, " BPM"
appendInfoLine: "Preset:    ", statPreset$
appendInfoLine: "CSP dev — budget: ", statBudgetDev$,
    ... "  density: ", statDensityDev$,
    ... "  entropy: ", statEntropyDev$

selectObject: resultSound

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
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc