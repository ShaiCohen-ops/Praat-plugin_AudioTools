# ============================================================
# Praat AudioTools - CorpusMosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5 (2026) - Compact preset dialog, concept visualization
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
#   "Loudness" is frame RMS (energy), not a psychoacoustic loudness model.
#   Analysis and output are mono, at the source Sound's sample rate.
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
#
# Changelog v1.5 (engine v1.4.0):
#   - Compact form: the preset is a single dropdown. The ten detail
#     parameters live in a second dialog, opened for Custom or when
#     "Edit_preset_parameters" is ticked, pre-filled with the preset's values
#     (a changed preset is reported as "<name> (edited)"). Default preset is
#     now Balanced. Batch callers: runScript passes the preset by NAME; the
#     detail dialog cannot be driven by runScript (and silently ends the
#     script under headless Praat 6.4.63+/7.0), so batch runs use presets.
#   - New figure that explains the method: (1) grain anatomy on the loudest
#     target passage, (2) the 2-D match map with the corpus cloud, target
#     path and chosen neighbours, (3) the preset fingerprint, (4) target vs
#     mosaic loudness/brightness/pitch, (5) corpus read-out lanes where
#     rising streaks are continuous reads and lone dots are jumps, (6) the
#     mosaic coloured by source file. Row-2 panels share one time axis.
#   - Matching and audio output are unchanged from v1.4.1.
#
# Changelog v1.4.1 (engine v1.3.1):
#   - Added seven modes: Custom plus six compositional presets (Balanced,
#     Pitch Lock, Timbre Morph, Continuity Stream, Granular Scatter,
#     Percussive Cut). Presets set the full matching/behaviour profile.
#   - Corpus file discovery is case-insensitive on every OS.
#   - Pitch matching is reliability-aware for short/noise-like grains; the
#     adaptive YIN floor and source reliability are reported in the summary.
#   - The corpus-strip legend now mentions dark grey only when a file beyond
#     the seventh is actually used.
#
# Changelog v1.4 (engine v1.3.0):
#   - Output level no longer depends on Overlap_percent: overlap-add is
#     amplitude-flat at every setting (was ~8 dB grain-rate tremolo at
#     25-30%, gaps at 0%, double level at 75%).
#   - Pitch / Timbre / Loudness weights are now equal category weights
#     (1/1/1 = one third each; timbre used to get two thirds).
#   - The distance panel now shows the PURE acoustic match distance; the
#     penalty/continuity-adjusted decision value is a separate CSV column.
#   - New Random_seed field (0 = new seed each run; the seed used is shown
#     in the summary so a run can be repeated exactly).
#   - Summary reports skipped/unreadable corpus files and effective weights.
#   - Praat 7: asks for full trust up front (file writes + Python call).
#   - Picture fixes: "%" and "_" in the title no longer turn into italic /
#     subscript markup; corpus strip no longer paints files beyond the 7th
#     in file 1's colour; the picture ends on the full 8x8 canvas so
#     Save/Copy exports the whole figure.
#
# Changelog v1.3:
#   - Added a "Corpus_folder" form field (mirrors VoidMosaic): type a
#     path, or leave it blank to fall back to a folder-selection dialog.
#     The path is whitespace- and trailing-slash-trimmed; cancelling the
#     dialog exits cleanly. The trimmed path is passed straight to the
#     Python engine (no Praat-side slash re-add, as the engine globs the
#     corpus itself). Synced the version across header/form/banner.
# ============================================================

form "Offline Corpus Mosaic Synthesizer v1.5"
    comment Corpus folder (leave blank to choose with a dialog)
    sentence Corpus_folder
    optionmenu Preset 2
        option Custom
        option Balanced
        option Pitch Lock
        option Timbre Morph
        option Continuity Stream
        option Granular Scatter
        option Percussive Cut
    boolean Edit_preset_parameters 0
    integer Random_seed 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Presets
# ============================================================
# Presets are complete behavioural profiles. Random_seed, normalization,
# visualization and playback stay user-controlled in every mode.
# Custom starts from the historical defaults and always opens the
# parameter dialog.
presetName$ = preset$
presetBlurb$ = "manual parameters"
grain_size_ms = 100
overlap_percent = 50
pitch_weight = 1.0
timbre_weight = 1.0
loudness_weight = 1.0
top_k_candidates = 5
randomness = 0.5
continuity_preference = 0.3
repetition_penalty = 1.5
gate_threshold_dB = -40

if preset$ = "Balanced"
    presetBlurb$ = "even pitch, timbre and loudness match with moderate variety"
    grain_size_ms = 100
    overlap_percent = 50
    pitch_weight = 1.0
    timbre_weight = 1.0
    loudness_weight = 1.0
    top_k_candidates = 5
    randomness = 0.35
    continuity_preference = 0.35
    repetition_penalty = 1.5
    gate_threshold_dB = -40
elsif preset$ = "Pitch Lock"
    presetBlurb$ = "follows the target melody with long, smooth grains"
    grain_size_ms = 140
    overlap_percent = 60
    pitch_weight = 2.5
    timbre_weight = 0.6
    loudness_weight = 0.7
    top_k_candidates = 4
    randomness = 0.15
    continuity_preference = 0.50
    repetition_penalty = 1.0
    gate_threshold_dB = -45
elsif preset$ = "Timbre Morph"
    presetBlurb$ = "follows tone colour; pitch matters little"
    grain_size_ms = 80
    overlap_percent = 70
    pitch_weight = 0.25
    timbre_weight = 2.5
    loudness_weight = 0.75
    top_k_candidates = 8
    randomness = 0.55
    continuity_preference = 0.25
    repetition_penalty = 1.8
    gate_threshold_dB = -42
elsif preset$ = "Continuity Stream"
    presetBlurb$ = "reads corpus files in long continuous runs"
    grain_size_ms = 120
    overlap_percent = 65
    pitch_weight = 0.8
    timbre_weight = 1.2
    loudness_weight = 1.0
    top_k_candidates = 6
    randomness = 0.20
    continuity_preference = 0.95
    repetition_penalty = 0.5
    gate_threshold_dB = -45
elsif preset$ = "Granular Scatter"
    presetBlurb$ = "tiny grains, wide random choice, few repeats"
    grain_size_ms = 35
    overlap_percent = 75
    pitch_weight = 0.15
    timbre_weight = 1.6
    loudness_weight = 0.8
    top_k_candidates = 15
    randomness = 0.90
    continuity_preference = 0.05
    repetition_penalty = 2.8
    gate_threshold_dB = -38
elsif preset$ = "Percussive Cut"
    presetBlurb$ = "short slices matched on energy and colour"
    grain_size_ms = 25
    overlap_percent = 20
    pitch_weight = 0.0
    timbre_weight = 1.8
    loudness_weight = 1.2
    top_k_candidates = 6
    randomness = 0.35
    continuity_preference = 0.10
    repetition_penalty = 2.2
    gate_threshold_dB = -32
endif

# ------------------------------------------------------------
# Detail dialog: always for Custom, optional for a preset.
# Pre-filled with the preset values so a preset is never a black box.
# ------------------------------------------------------------
if preset$ = "Custom" or edit_preset_parameters
    p1 = grain_size_ms
    p2 = overlap_percent
    p3 = pitch_weight
    p4 = timbre_weight
    p5 = loudness_weight
    p6 = top_k_candidates
    p7 = randomness
    p8 = continuity_preference
    p9 = repetition_penalty
    p10 = gate_threshold_dB
    beginPause: "Corpus Mosaic - " + presetName$ + " parameters"
        comment: "Grains"
        positive: "Grain_size_ms", string$(grain_size_ms)
        real: "Overlap_percent", string$(overlap_percent)
        comment: "What counts as a close match (relative weights)"
        real: "Pitch_weight", string$(pitch_weight)
        real: "Timbre_weight", string$(timbre_weight)
        real: "Loudness_weight", string$(loudness_weight)
        comment: "How a match is chosen"
        positive: "Top_k_candidates", string$(top_k_candidates)
        real: "Randomness", string$(randomness)
        real: "Continuity_preference", string$(continuity_preference)
        real: "Repetition_penalty", string$(repetition_penalty)
        real: "Gate_threshold_dB", string$(gate_threshold_dB)
    clicked = endPause: "Cancel", "Run", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
    top_k_candidates = max(1, round(top_k_candidates))
    if preset$ <> "Custom"
        changed = 0
        if p1 <> grain_size_ms or p2 <> overlap_percent or p3 <> pitch_weight or p4 <> timbre_weight
            changed = 1
        endif
        if p5 <> loudness_weight or p6 <> top_k_candidates or p7 <> randomness
            changed = 1
        endif
        if p8 <> continuity_preference or p9 <> repetition_penalty or p10 <> gate_threshold_dB
            changed = 1
        endif
        if changed
            presetName$ = presetName$ + " (edited)"
        endif
    endif
endif

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Praat 7 blocks file writes and system calls without full trust.
if praatVersion >= 7000
    if not askForTrust ()
        exitScript: "Corpus Mosaic needs full trust (it writes temp files and runs Python)."
    endif
endif

sourceId = selected("Sound")
sourceName$ = selected$("Sound")

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Corpus folder field is left blank. Trim whitespace and trailing
# slashes; the trimmed path is passed straight to the Python engine
# (which globs the corpus), so no trailing slash is re-added here.
corpusDir$ = replace_regex$(corpus_folder$, "^[ \t]*|[ \t]*$", "", 0)
corpusDir$ = replace_regex$(corpusDir$, "[\\/]+$", "", 0)

if corpusDir$ == ""
    corpusDir$ = chooseFolder$: "Select Corpus Folder (WAV/FLAC/AIFF)"
    corpusDir$ = replace_regex$(corpusDir$, "[\\/]+$", "", 0)
endif

if corpusDir$ == ""
    exitScript: "Operation cancelled. Please supply a valid Corpus folder path."
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
tempMap$     = temporaryDirectory$ + "/temp_mosaic_map.csv"
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

# ============================================================
# Check Python Dependencies
# ============================================================
clearinfo
writeInfoLine: "=== Offline Corpus Mosaic v1.5 ==="
appendInfoLine: "Preset: ", presetName$, " - ", presetBlurb$
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
pyCmd$ = pyCmd$ + " --out_map """ + tempMap$ + """"
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
pyCmd$ = pyCmd$ + " --seed " + string$(max(0, random_seed))
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
statSkipped$      = "?"
statSeed$         = "?"
statWeights$      = "?"
statRate$         = "?"
statPitchRel$     = "?"
statPitchFmin$    = "?"
statHop$          = "?"
statGrainExact$   = "?"
statTaper$        = "?"
statChain$        = "0"
statMeanDist$     = "?"
statMapVar$       = "?"
statAxis1$        = "?"
statAxis2$        = "?"
statLegendN$      = "0"
statLegendOther$  = "0|0"
for li to 7
    legend_'li'$ = ""
endfor

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

    @parseStatLine: statsText$, "Corpus files skipped: "
    statSkipped$ = parseStatLine.result$

    @parseStatLine: statsText$, "Random seed: "
    statSeed$ = parseStatLine.result$

    @parseStatLine: statsText$, "Effective weights (L/T/P): "
    statWeights$ = parseStatLine.result$

    @parseStatLine: statsText$, "Sample rate: "
    statRate$ = parseStatLine.result$

    @parseStatLine: statsText$, "Pitch reliability (source active mean): "
    statPitchRel$ = parseStatLine.result$

    @parseStatLine: statsText$, "Adaptive YIN fmin: "
    statPitchFmin$ = parseStatLine.result$

    @parseStatLine: statsText$, "Hop ms: "
    statHop$ = parseStatLine.result$
    @parseStatLine: statsText$, "Grain ms exact: "
    statGrainExact$ = parseStatLine.result$
    @parseStatLine: statsText$, "Taper ms: "
    statTaper$ = parseStatLine.result$
    @parseStatLine: statsText$, "Continuity ratio: "
    statChain$ = parseStatLine.result$
    @parseStatLine: statsText$, "Mean distance: "
    statMeanDist$ = parseStatLine.result$
    @parseStatLine: statsText$, "Map variance: "
    statMapVar$ = parseStatLine.result$
    @parseStatLine: statsText$, "Map axis 1: "
    statAxis1$ = parseStatLine.result$
    @parseStatLine: statsText$, "Map axis 2: "
    statAxis2$ = parseStatLine.result$
    @parseStatLine: statsText$, "Legend count: "
    statLegendN$ = parseStatLine.result$
    @parseStatLine: statsText$, "Legend other: "
    statLegendOther$ = parseStatLine.result$
    for li to 7
        @parseStatLine: statsText$, "Legend " + string$(li) + ": "
        if parseStatLine.result$ <> "?"
            legend_'li'$ = parseStatLine.result$
        endif
    endfor
endif

# ============================================================
# Visualization
# ============================================================
# Layout (8-inch canvas, inner panels 0.6-7.7 in):
#   Row 1  three concept panels: grain anatomy | match map | preset
#   Row 2  one shared time axis: target + descriptor tracks,
#          corpus read-out lanes, mosaic result
#   Summary panel at the bottom.
# Drawing-frame rule: Font size -> Select inner viewport -> Axes -> draw,
# and re-select after every Text / Draw inner box.
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    haveData = 0
    if fileReadable(tempCsv$)
        csvTable = Read Table from comma-separated file: tempCsv$
        nRows = Get number of rows
        if nRows > 0
            haveData = 1
        endif
    endif

    # ---------- palette: 7 named files + "other" ----------
    pr# = {0.22, 0.82, 0.15, 0.85, 0.55, 0.10, 0.90, 0.45}
    pg# = {0.50, 0.22, 0.62, 0.55, 0.25, 0.65, 0.40, 0.45}
    pb# = {0.82, 0.28, 0.40, 0.05, 0.70, 0.75, 0.65, 0.45}

    # ---------- mono copy of the target for drawing ----------
    selectObject: sourceId
    nChSrc = Get number of channels
    if nChSrc > 1
        drawSrc = Convert to mono
    else
        drawSrc = Copy: "drawSrc_mosaic"
    endif
    selectObject: drawSrc
    Shift times to: "start time", 0
    srcDur = Get total duration
    srcAmp = Get absolute extremum: 0, 0, "None"
    if srcAmp <= 0
        srcAmp = 1
    endif
    selectObject: resultSound
    outAmp = Get absolute extremum: 0, 0, "None"
    if outAmp <= 0
        outAmp = 1
    endif

    hopSec = number(statHop$) / 1000
    if hopSec = undefined or hopSec <= 0
        hopSec = grain_size_ms * (1 - overlap_percent / 100) / 1000
    endif
    grainSec = number(statGrainExact$) / 1000
    if grainSec = undefined or grainSec <= 0
        grainSec = grain_size_ms / 1000
    endif
    taperSec = number(statTaper$) / 1000
    if taperSec = undefined or taperSec < 0
        taperSec = grainSec / 2
    endif

    # ---------- read the match table once into vectors ----------
    if haveData
        selectObject: csvTable
        tS# = zero#(nRows)
        rk# = zero#(nRows)
        ch# = zero#(nRows)
        ps# = zero#(nRows)
        tl# = zero#(nRows)
        ml# = zero#(nRows)
        tb# = zero#(nRows)
        mb# = zero#(nRows)
        tp# = zero#(nRows)
        mp# = zero#(nRows)
        trl# = zero#(nRows)
        mrl# = zero#(nRows)
        tx# = zero#(nRows)
        ty# = zero#(nRows)
        mx# = zero#(nRows)
        my# = zero#(nRows)
        act# = zero#(nRows)
        nAct = 0
        for r to nRows
            tS#[r] = Get value: r, "source_time_sec"
            rk#[r] = Get value: r, "file_rank"
            ch#[r] = Get value: r, "chain"
            ps#[r] = Get value: r, "corpus_pos"
            tl#[r] = Get value: r, "t_loud_db"
            ml#[r] = Get value: r, "m_loud_db"
            tb#[r] = Get value: r, "t_bright_hz"
            mb#[r] = Get value: r, "m_bright_hz"
            tp#[r] = Get value: r, "t_pitch_hz"
            mp#[r] = Get value: r, "m_pitch_hz"
            trl#[r] = Get value: r, "t_pitch_rel"
            mrl#[r] = Get value: r, "m_pitch_rel"
            tx#[r] = Get value: r, "tx"
            ty#[r] = Get value: r, "ty"
            mx#[r] = Get value: r, "mx"
            my#[r] = Get value: r, "my"
            if rk#[r] > 0
                act#[r] = 1
                nAct = nAct + 1
            endif
        endfor
        removeObject: csvTable

        nLegend = number(statLegendN$)
        if nLegend = undefined
            nLegend = 0
        endif
        otherUses = extractNumber(statLegendOther$, "")
        otherFiles = extractNumber(statLegendOther$, "|")
        if otherUses = undefined
            otherUses = 0
        endif
        if otherFiles = undefined
            otherFiles = 0
        endif
        nLanes = nLegend
        if otherFiles > 0
            nLanes = nLanes + 1
        endif
        if nLanes < 1
            nLanes = 1
        endif

        # Zoom grains for the anatomy panel: the loudest active grain that
        # is followed by enough active grains.
        nShow = min(4, nRows)
        zc = 1
        bestL = -1e9
        for r to nRows - nShow + 1
            okRun = 1
            for q from r to r + nShow - 1
                if act#[q] = 0
                    okRun = 0
                endif
            endfor
            if okRun and tl#[r] > bestL
                bestL = tl#[r]
                zc = r
            endif
        endfor
        zEnd = zc + nShow - 1
        zoomT0 = tS#[zc]
        zoomT1 = min(tS#[zEnd] + grainSec, srcDur)
    endif

    Erase all
    Font size: 7
    Line width: 1
    Colour: "Black"

    # =========================================================
    # Title
    # =========================================================
    Font size: 13
    Select inner viewport: 0, 8, 0.05, 0.70
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.80, "half", "##Corpus Mosaic Synthesizer##"
    Font size: 7
    Select inner viewport: 0, 8, 0.05, 0.70
    Axes: 0, 1, 0, 1
    @pictureSafe: sourceName$
    Colour: "{0.30, 0.30, 0.45}"
    Text: 0.5, "centre", 0.44, "half", "Target: " + pictureSafe.result$
        ... + "   |   Preset: ##" + presetName$ + "##  - " + presetBlurb$
    Colour: "{0.40, 0.40, 0.40}"
    Font size: 6
    Select inner viewport: 0, 8, 0.05, 0.70
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.16, "half",
        ... "The target is cut into grains; every grain is replaced by the corpus grain whose "
        ... + "loudness, timbre and pitch are closest, and the chosen grains are overlap-added."
    Colour: "Black"

    if haveData
        # =====================================================
        # Row 1, panel 1: grain anatomy
        # =====================================================
        ax0 = 0.60
        ax1 = 2.55
        rowTop = 1.10
        rowBot = 3.05
        @msLabel: grainSec * 1000
        capG$ = msLabel.s$
        @msLabel: hopSec * 1000
        capH$ = msLabel.s$
        @msLabel: taperSec * 1000
        capT$ = msLabel.s$
        @caption: ax0, ax1, rowTop, "1", "Cut into grains",
            ... capG$ + " ms grains, hop " + capH$ + " ms, crossfade " + capT$ + " ms"

        zoomMs = (zoomT1 - zoomT0) * 1000
        selectObject: drawSrc
        zoomSnd = Extract part: zoomT0, zoomT1, "rectangular", 1, "no"
        zAmp = Get absolute extremum: 0, 0, "None"
        if zAmp <= 0
            zAmp = 1
        endif
        Font size: 6
        Select inner viewport: ax0, ax1, rowTop, rowBot
        Axes: 0, zoomMs, -1.15, 1.15
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, zoomMs, -1.15, 1.15
        Colour: "{0.70, 0.70, 0.70}"
        Draw: 0, 0, -1.25 * zAmp, 1.25 * zAmp, "no", "Curve"
        removeObject: zoomSnd

        # grain windows, coloured by the corpus file each grain came from
        Select inner viewport: ax0, ax1, rowTop, rowBot
        Axes: 0, zoomMs, -1.15, 1.15
        gMs = grainSec * 1000
        tMs = taperSec * 1000
        for g from zc to zEnd
            gi = min(rk#[g], 8)
            @rgb: pr#[gi], pg#[gi], pb#[gi]
            Colour: rgb.s$
            Line width: 2
            s0 = (tS#[g] - zoomT0) * 1000
            prevWx = s0
            prevWy = -1
            for k to 48
                u = gMs * k / 48
                w = 1
                if tMs > 0 and u < tMs
                    w = sin(pi / 2 * u / tMs) ^ 2
                elsif tMs > 0 and u > gMs - tMs
                    w = sin(pi / 2 * (gMs - u) / tMs) ^ 2
                endif
                wx = min(s0 + u, zoomMs)
                wy = -1 + 2 * w
                Draw line: prevWx, prevWy, wx, wy
                prevWx = wx
                prevWy = wy
            endfor
            Line width: 1
            Paint circle (mm): rgb.s$, s0 + gMs / 2, 1.07, 0.9
        endfor
        # hop and grain brackets on the first grain
        Colour: "{0.25, 0.25, 0.25}"
        Arrow size: 0.5
        if nShow > 1
            h0 = (tS#[zc] - zoomT0) * 1000
            h1 = (tS#[zc + 1] - zoomT0) * 1000
            Draw two-way arrow: h0, -0.88, h1, -0.88
            Text: h1, "left", -0.88, "half", " hop"
        endif
        Draw two-way arrow: 0, -0.62, min(gMs, zoomMs), -0.62
        Text: min(gMs, zoomMs), "left", -0.62, "half", " grain"
        Arrow size: 1
        Colour: "Black"
        Select inner viewport: ax0, ax1, rowTop, rowBot
        Axes: 0, zoomMs, -1.15, 1.15
        Draw inner box
        @niceStep: zoomMs, 4
        Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
        Text bottom: "yes", "ms (loudest passage)"

        # =====================================================
        # Row 1, panel 2: the match map
        # =====================================================
        mx0 = 3.00
        mx1 = 5.25
        @caption: mx0, mx1, rowTop, "2", "Find the nearest corpus grain",
            ... "grey = corpus  |  black = target  |  colour = match"

        nMap = 0
        if fileReadable(tempMap$)
            mapTable = Read Table from comma-separated file: tempMap$
            nMap = Get number of rows
            cx# = zero#(max(nMap, 1))
            cy# = zero#(max(nMap, 1))
            for r to nMap
                cx#[r] = Get value: r, "x"
                cy#[r] = Get value: r, "y"
            endfor
            removeObject: mapTable
        endif

        # range from 1st-99th percentiles of everything shown
        nAll = nMap + 2 * nAct
        allX# = zero#(max(nAll, 1))
        allY# = zero#(max(nAll, 1))
        n = 0
        for r to nMap
            n = n + 1
            allX#[n] = cx#[r]
            allY#[n] = cy#[r]
        endfor
        for r to nRows
            if act#[r]
                n = n + 1
                allX#[n] = tx#[r]
                allY#[n] = ty#[r]
                n = n + 1
                allX#[n] = mx#[r]
                allY#[n] = my#[r]
            endif
        endfor
        @vecRange: allX#, n
        xLo = vecRange.lo
        xHi = vecRange.hi
        @vecRange: allY#, n
        yLo = vecRange.lo
        yHi = vecRange.hi

        Font size: 6
        Select inner viewport: mx0, mx1, rowTop, rowBot
        Axes: xLo, xHi, yLo, yHi
        Paint rectangle: "{0.98, 0.98, 0.98}", xLo, xHi, yLo, yHi
        for r to nMap
            @clampXY: cx#[r], cy#[r]
            Paint circle (mm): "{0.78, 0.78, 0.78}", clampXY.x, clampXY.y, 0.25
        endfor
        # target path (broken at gated grains)
        Colour: "{0.45, 0.45, 0.45}"
        for r from 2 to nRows
            if act#[r] and act#[r - 1]
                @clampXY: tx#[r - 1], ty#[r - 1]
                ax = clampXY.x
                ay = clampXY.y
                @clampXY: tx#[r], ty#[r]
                Draw line: ax, ay, clampXY.x, clampXY.y
            endif
        endfor
        # a sample of target -> match links
        linkStep = max(1, round(nAct / 40))
        cnt = 0
        Colour: "{0.62, 0.66, 0.75}"
        for r to nRows
            if act#[r]
                cnt = cnt + 1
                if (cnt - 1) mod linkStep = 0
                    @clampXY: tx#[r], ty#[r]
                    ax = clampXY.x
                    ay = clampXY.y
                    @clampXY: mx#[r], my#[r]
                    Draw line: ax, ay, clampXY.x, clampXY.y
                endif
            endif
        endfor
        # chosen grains (file colour), then target grains (black)
        dotR = 0.45
        if nAct > 600
            dotR = 0.30
        endif
        for r to nRows
            if act#[r]
                gi = min(rk#[r], 8)
                @rgb: pr#[gi], pg#[gi], pb#[gi]
                @clampXY: mx#[r], my#[r]
                Paint circle (mm): rgb.s$, clampXY.x, clampXY.y, dotR
            endif
        endfor
        for r to nRows
            if act#[r]
                @clampXY: tx#[r], ty#[r]
                Paint circle (mm): "{0.10, 0.10, 0.10}", clampXY.x, clampXY.y, 0.22
            endif
        endfor
        # the zoomed grains from panel 1, emphasised
        Line width: 2
        for g from zc to zEnd
            gi = min(rk#[g], 8)
            @rgb: pr#[gi], pg#[gi], pb#[gi]
            Colour: rgb.s$
            @clampXY: tx#[g], ty#[g]
            ax = clampXY.x
            ay = clampXY.y
            @clampXY: mx#[g], my#[g]
            Draw line: ax, ay, clampXY.x, clampXY.y
            Paint circle (mm): rgb.s$, clampXY.x, clampXY.y, 0.9
            Paint circle (mm): "{0.10, 0.10, 0.10}", ax, ay, 0.6
        endfor
        Line width: 1
        Colour: "{0.35, 0.35, 0.35}"
        Select inner viewport: mx0, mx1, rowTop, rowBot
        Axes: 0, 1, 0, 1
        Text: 0.98, "right", 0.03, "bottom", "2-D view keeps " + statMapVar$ + "\% "
        Colour: "Black"
        Select inner viewport: mx0, mx1, rowTop, rowBot
        Axes: 0, 1, 0, 1
        Draw inner box
        Select inner viewport: mx0, mx1, rowTop, rowBot
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", -0.04, "top", "Helvetica", 6, "0", "axis 1:  " + statAxis1$ + "  \-> "
        Text special: -0.03, "centre", 0.5, "bottom", "Helvetica", 6, "90", "axis 2:  " + statAxis2$ + "  \-> "

        # =====================================================
        # Row 1, panel 3: preset fingerprint
        # =====================================================
        fx0 = 5.55
        fx1 = 7.70
        @caption: fx0, fx1, rowTop, "3", "Preset fingerprint", "each bar shows a setting within its usual range"

        wP = max(0, pitch_weight)
        wT = max(0, timbre_weight)
        wL = max(0, loudness_weight)
        wSum = wP + wT + wL
        if wSum <= 0
            wP = 1
            wT = 1
            wL = 1
            wSum = 3
        endif
        Font size: 6
        Select inner viewport: fx0, fx1, rowTop, rowBot
        Axes: 0, 1, 0, 13
        Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, 0, 13
        yRow = 13
        @fpHead: yRow, "What counts as close"
        @fpBar: yRow - 1, "Loudness", wL / wSum, fixed$(100 * wL / wSum, 0) + "\% "
        @fpBar: yRow - 2, "Timbre", wT / wSum, fixed$(100 * wT / wSum, 0) + "\% "
        @fpBar: yRow - 3, "Pitch", wP / wSum, fixed$(100 * wP / wSum, 0) + "\% "
        @fpHead: yRow - 4.2, "How one is chosen"
        @fpBar: yRow - 5.2, "Top-k pool", min(1, top_k_candidates / 20), string$(top_k_candidates)
        @fpBar: yRow - 6.2, "Randomness", min(1, randomness), fixed$(randomness, 2)
        @fpBar: yRow - 7.2, "Continuity", min(1, continuity_preference), fixed$(continuity_preference, 2)
        @fpBar: yRow - 8.2, "No-repeat", min(1, repetition_penalty / 3), fixed$(repetition_penalty, 2)
        @fpHead: yRow - 9.4, "Result"
        chainPct = number(statChain$)
        if chainPct = undefined
            chainPct = 0
        endif
        @fpBar: yRow - 10.4, "Continuous", chainPct / 100, fixed$(chainPct, 0) + "\% "
        filesUsed = number(statUniqueUsed$)
        filesAll = number(statCorpusFiles$)
        if filesUsed = undefined or filesAll = undefined or filesAll <= 0
            filesUsed = 0
            filesAll = 1
        endif
        @fpBar: yRow - 11.4, "Files used", filesUsed / filesAll, statUniqueUsed$ + " / " + statCorpusFiles$
        Select inner viewport: fx0, fx1, rowTop, rowBot
        Axes: 0, 1, 0, 13
        Draw inner box

        # =====================================================
        # Row 2: shared time axis
        # =====================================================
        tx0 = 0.60
        tx1 = 7.70
        railX = -0.045

        # ---- 4: target and descriptor tracks ----
        y4 = 3.62
        @caption: tx0, tx1, y4, "4", "Follow the target",
            ... "black = target  |  colour = chosen grain (pitch drawn only where it is reliable)"
        ya0 = y4
        ya1 = y4 + 0.55
        Font size: 6
        Select inner viewport: tx0, tx1, ya0, ya1
        Axes: 0, srcDur, -1, 1
        for r to nRows
            if act#[r] = 0
                g0 = tS#[r]
                g1 = min(tS#[r] + hopSec, srcDur)
                Paint rectangle: "{0.90, 0.90, 0.90}", g0, g1, -1, 1
            endif
        endfor
        Colour: "{0.35, 0.35, 0.35}"
        selectObject: drawSrc
        Draw: 0, 0, -srcAmp * 1.05, srcAmp * 1.05, "no", "Curve"
        Select inner viewport: tx0, tx1, ya0, ya1
        Axes: 0, srcDur, -1, 1
        Colour: "{0.85, 0.20, 0.20}"
        Line width: 1.5
        Draw rectangle: zoomT0, zoomT1, -0.98, 0.98
        Line width: 1
        Text: zoomT1, "left", 0.55, "half", " 1"
        Colour: "Black"
        Draw inner box
        @rail: tx0, tx1, ya0, ya1, railX, "Target"
        Select inner viewport: tx0, tx1, ya0, ya1
        Axes: 0, srcDur, -1, 1
        @niceStep: srcDur, 8
        timeStep = niceStep.result
        Marks bottom every: 1, timeStep, "no", "yes", "no"

        # three flush descriptor tracks
        trH = 0.42
        trGap = 0.04
        for trk to 3
            yb0 = ya1 + trGap + (trk - 1) * (trH + trGap)
            yb1 = yb0 + trH
            nV = 0
            vals# = zero#(2 * nRows + 1)
            for r to nRows
                if act#[r]
                    if trk = 1
                        nV = nV + 1
                        vals#[nV] = tl#[r]
                        nV = nV + 1
                        vals#[nV] = ml#[r]
                    elsif trk = 2
                        nV = nV + 1
                        vals#[nV] = log10(max(tb#[r], 20))
                        nV = nV + 1
                        vals#[nV] = log10(max(mb#[r], 20))
                    else
                        if trl#[r] >= 0.5
                            nV = nV + 1
                            vals#[nV] = log10(max(tp#[r], 20))
                        endif
                        if mrl#[r] >= 0.5
                            nV = nV + 1
                            vals#[nV] = log10(max(mp#[r], 20))
                        endif
                    endif
                endif
            endfor
            @vecRange: vals#, nV
            vLo = vecRange.lo
            vHi = vecRange.hi

            Font size: 6
            Select inner viewport: tx0, tx1, yb0, yb1
            Axes: 0, srcDur, vLo, vHi
            Paint rectangle: "{0.98, 0.98, 0.98}", 0, srcDur, vLo, vHi
            # chosen grains first (thick, file colour), target on top
            Line width: 2.5
            for r to nRows
                if act#[r]
                    if trk = 1
                        v = ml#[r]
                        ok = 1
                    elsif trk = 2
                        v = log10(max(mb#[r], 20))
                        ok = 1
                    else
                        v = log10(max(mp#[r], 20))
                        ok = mrl#[r] >= 0.5
                    endif
                    if ok
                        v = max(vLo, min(vHi, v))
                        gi = min(rk#[r], 8)
                        @rgb: pr#[gi], pg#[gi], pb#[gi]
                        Colour: rgb.s$
                        Draw line: tS#[r], v, min(tS#[r] + hopSec, srcDur), v
                    endif
                endif
            endfor
            Line width: 1.2
            Colour: "{0.05, 0.05, 0.05}"
            havePrev = 0
            for r to nRows
                ok = act#[r]
                if trk = 1
                    v = tl#[r]
                elsif trk = 2
                    v = log10(max(tb#[r], 20))
                else
                    v = log10(max(tp#[r], 20))
                    if trl#[r] < 0.5
                        ok = 0
                    endif
                endif
                if ok
                    v = max(vLo, min(vHi, v))
                    g1 = min(tS#[r] + hopSec, srcDur)
                    if havePrev
                        Draw line: tS#[r], prevV, tS#[r], v
                    endif
                    Draw line: tS#[r], v, g1, v
                    prevV = v
                    havePrev = 1
                else
                    havePrev = 0
                endif
            endfor
            Line width: 1
            Colour: "Black"
            Select inner viewport: tx0, tx1, yb0, yb1
            Axes: 0, srcDur, vLo, vHi
            Draw inner box
            Select inner viewport: tx0, tx1, yb0, yb1
            Axes: 0, srcDur, vLo, vHi
            Marks bottom every: 1, timeStep, "no", "yes", "no"
            if nV = 0
                emptyMsg$ = "no reliable pitch at this grain size"
                if pitch_weight <= 0
                    emptyMsg$ = "pitch is not used by this setting"
                endif
                Colour: "{0.45, 0.45, 0.45}"
                Text: srcDur / 2, "centre", (vLo + vHi) / 2, "half", "(" + emptyMsg$ + ")"
                Colour: "Black"
            endif
            for mk to 2 * (nV > 0)
                mv = vLo + (vHi - vLo) * (0.22 + 0.56 * (mk - 1))
                if trk = 1
                    mLab$ = fixed$(mv, 0)
                    if round(mv) = 0
                        mLab$ = "0"
                    endif
                else
                    @hzLabel: 10 ^ mv
                    mLab$ = hzLabel.s$
                endif
                One mark left: mv, "no", "yes", "no", mLab$
            endfor
            if trk = 1
                trName$ = "Loud dB"
            elsif trk = 2
                trName$ = "Bright Hz"
            else
                trName$ = "Pitch Hz"
            endif
            @rail: tx0, tx1, yb0, yb1, railX, trName$
        endfor
        tracksBot = ya1 + trGap + 3 * (trH + trGap) - trGap

        # ---- 5: corpus read-out lanes ----
        y5 = tracksBot + 0.52
        laneH = min(0.30, 1.30 / nLanes)
        if laneH < 0.12
            laneH = 0.12
        endif
        yl0 = y5 + 0.14
        yl1 = yl0 + nLanes * laneH
        @caption: tx0, tx1, y5, "5", "Where each grain came from",
            ... "one lane per file, height = position inside the file:  rising streak = continuous read,  lone dot = jump"
        # legend line under the caption
        Font size: 6
        Select inner viewport: tx0, tx1, y5 - 0.02, y5 + 0.12
        Axes: 0, tx1 - tx0, 0, 1
        nItems = nLegend
        if otherFiles > 0
            nItems = nItems + 1
        endif
        slotW = (tx1 - tx0) / max(nItems, 1)
        charW = 0.055
        for li to nLegend
            nm$ = legend_'li'$
            bar = index(nm$, "|")
            uses$ = left$(nm$, bar - 1)
            nm$ = mid$(nm$, bar + 1, length(nm$) - bar)
            slash = rindex(nm$, "/")
            if slash > 0
                nm$ = mid$(nm$, slash + 1, length(nm$) - slash)
            endif
            dot = rindex(nm$, ".")
            if dot > 1
                nm$ = left$(nm$, dot - 1)
            endif
            maxChars = floor((slotW - 0.16) / charW) - length(string$(li)) - length(uses$) - 4
            if maxChars < 3
                maxChars = 3
            endif
            if length(nm$) > maxChars
                nm$ = left$(nm$, maxChars - 1) + "~"
            endif
            @pictureSafe: nm$
            @rgb: pr#[li], pg#[li], pb#[li]
            lx = (li - 1) * slotW
            Paint rectangle: rgb.s$, lx, lx + 0.09, 0.25, 0.75
            Text: lx + 0.12, "left", 0.5, "half", string$(li) + " " + pictureSafe.result$ + " (" + uses$ + ")"
        endfor
        if otherFiles > 0
            @rgb: pr#[8], pg#[8], pb#[8]
            lx = nLegend * slotW
            Paint rectangle: rgb.s$, lx, lx + 0.09, 0.25, 0.75
            otherLab$ = "+ " + fixed$(otherFiles, 0) + " more (" + fixed$(otherUses, 0) + ")"
            if slotW > 1.2
                otherLab$ = "+ " + fixed$(otherFiles, 0) + " more files (" + fixed$(otherUses, 0) + ")"
            endif
            Text: lx + 0.12, "left", 0.5, "half", otherLab$
        endif

        Font size: 6
        Select inner viewport: tx0, tx1, yl0, yl1
        Axes: 0, srcDur, 0, nLanes
        for ln to nLanes
            if ln mod 2 = 0
                Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDur, nLanes - ln, nLanes - ln + 1
            endif
        endfor
        for r to nRows
            if act#[r] = 0
                Paint rectangle: "{0.90, 0.90, 0.90}", tS#[r], min(tS#[r] + hopSec, srcDur), 0, nLanes
            endif
        endfor
        laneDot = 0.40
        if nAct > 400
            laneDot = 0.28
        endif
        if nAct > 1500
            laneDot = 0.22
        endif
        for r to nRows
            if act#[r]
                ln = min(rk#[r], nLanes)
                gi = min(rk#[r], 8)
                @rgb: pr#[gi], pg#[gi], pb#[gi]
                yy = nLanes - ln + 0.12 + 0.76 * ps#[r]
                xx = tS#[r] + hopSec / 2
                if ch#[r] and r > 1
                    Colour: rgb.s$
                    Line width: 2
                    Draw line: tS#[r - 1] + hopSec / 2, nLanes - ln + 0.12 + 0.76 * ps#[r - 1], xx, yy
                    Line width: 1
                endif
                Paint circle (mm): rgb.s$, xx, yy, laneDot
            endif
        endfor
        Colour: "{0.80, 0.80, 0.80}"
        for ln to nLanes - 1
            Draw line: 0, ln, srcDur, ln
        endfor
        Colour: "Black"
        Select inner viewport: tx0, tx1, yl0, yl1
        Axes: 0, srcDur, 0, nLanes
        Draw inner box
        Select inner viewport: tx0, tx1, yl0, yl1
        Axes: 0, srcDur, 0, nLanes
        Marks bottom every: 1, timeStep, "no", "yes", "no"
        for ln to nLanes
            laneLab$ = string$(ln)
            if ln > nLegend
                laneLab$ = "+"
            endif
            One mark left: nLanes - ln + 0.5, "no", "no", "no", laneLab$
        endfor
        @rail: tx0, tx1, yl0, yl1, railX, "Corpus file"

        # ---- 6: mosaic result ----
        y6 = yl1 + 0.40
        @caption: tx0, tx1, y6, "6", "Overlap-add the chosen grains",
            ... "background = source file of each grain  |  grey = gated silence"
        yo0 = y6
        yo1 = y6 + 0.70
        Font size: 6
        Select inner viewport: tx0, tx1, yo0, yo1
        Axes: 0, srcDur, -1, 1
        r = 1
        while r <= nRows
            runRank = rk#[r]
            r2 = r
            while r2 < nRows and rk#[min(r2 + 1, nRows)] = runRank
                r2 = r2 + 1
            endwhile
            b0 = tS#[r]
            b1 = min(tS#[r2] + hopSec, srcDur)
            if r2 = nRows
                b1 = srcDur
            endif
            if runRank = 0
                Paint rectangle: "{0.90, 0.90, 0.90}", b0, b1, -1, 1
            else
                gi = min(runRank, 8)
                @rgb: pr#[gi] + (1 - pr#[gi]) * 0.72, pg#[gi] + (1 - pg#[gi]) * 0.72, pb#[gi] + (1 - pb#[gi]) * 0.72
                Paint rectangle: rgb.s$, b0, b1, -1, 1
            endif
            r = r2 + 1
        endwhile
        Colour: "{0.20, 0.20, 0.25}"
        selectObject: resultSound
        Draw: 0, 0, -outAmp * 1.05, outAmp * 1.05, "no", "Curve"
        Colour: "Black"
        Select inner viewport: tx0, tx1, yo0, yo1
        Axes: 0, srcDur, -1, 1
        Draw inner box
        @rail: tx0, tx1, yo0, yo1, railX, "Mosaic"
        Select inner viewport: tx0, tx1, yo0, yo1
        Axes: 0, srcDur, -1, 1
        Marks bottom every: 1, timeStep, "yes", "yes", "no"
        Text bottom: "yes", "Time (s)"
        sumTop = yo1 + 0.52
    else
        # No match data: show target and result only.
        Font size: 7
        Select inner viewport: 0.6, 7.7, 1.1, 1.9
        selectObject: drawSrc
        Draw: 0, 0, -srcAmp, srcAmp, "no", "Curve"
        Select inner viewport: 0.6, 7.7, 1.1, 1.9
        Draw inner box
        Select inner viewport: 0.6, 7.7, 2.2, 3.0
        selectObject: resultSound
        Draw: 0, 0, -outAmp, outAmp, "no", "Curve"
        Select inner viewport: 0.6, 7.7, 2.2, 3.0
        Draw inner box
        Select inner viewport: 0.6, 7.7, 2.2, 3.0
        Axes: 0, 1, 0, 1
        Text: 0.5, "centre", 1.3, "half", "(match table missing - concept panels skipped)"
        sumTop = 3.5
    endif

    # =========================================================
    # Summary panel
    # =========================================================
    sumBot = sumTop + 0.72
    Font size: 7
    Select inner viewport: 0.6, 7.7, sumTop, sumBot
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Text: 0.015, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, sumTop, sumBot
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    skippedN$ = statSkipped$
    spPos = index(skippedN$, " ")
    if spPos > 0
        skippedN$ = left$(skippedN$, spPos - 1)
    endif
    @pictureSafe: statPitchRel$
    pitchRelSafe$ = pictureSafe.result$
    Text: 0.015, "left", 0.58, "half",
        ... "Target grains: " + statSourceGrains$ + " (" + statSilenced$ + " gated)"
        ... + "   |   Corpus: " + statCorpusGrains$ + " grains from " + statCorpusFiles$ + " files"
        ... + " (" + skippedN$ + " skipped)"
        ... + "   |   Files used: " + statUniqueUsed$
        ... + "   |   Continuous reads: " + statChain$ + "\% "
    Text: 0.015, "left", 0.36, "half",
        ... "Grain " + fixed$(grain_size_ms, 0) + " ms, overlap " + fixed$(overlap_percent, 0) + "\% "
        ... + ", gate " + fixed$(gate_threshold_dB, 0) + " dB"
        ... + "   |   Weights P/T/L " + fixed$(pitch_weight, 2) + " / " + fixed$(timbre_weight, 2)
        ... + " / " + fixed$(loudness_weight, 2)
        ... + "   |   Top-k " + string$(top_k_candidates) + ", random " + fixed$(randomness, 2)
        ... + ", continuity " + fixed$(continuity_preference, 2) + ", no-repeat " + fixed$(repetition_penalty, 2)
    Text: 0.015, "left", 0.14, "half",
        ... "Mean match distance " + statMeanDist$
        ... + "   |   Pitch reliability " + pitchRelSafe$ + " (YIN floor " + statPitchFmin$ + ")"
        ... + "   |   " + statRate$ + " Hz   |   Seed " + statSeed$
        ... + "   |   Render " + statTime$
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, sumTop, sumBot
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: drawSrc
    Font size: 10
    Line width: 1
    Colour: "Black"
    Select outer viewport: 0, 8, 0, sumBot + 0.15
endif

# ============================================================
# Final info + cleanup
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Preset:        ", presetName$, " - ", presetBlurb$
appendInfoLine: "Parameters:    grain ", fixed$(grain_size_ms, 0), " ms, overlap ", fixed$(overlap_percent, 0),
    ... " %, weights P/T/L ", fixed$(pitch_weight, 2), "/", fixed$(timbre_weight, 2), "/", fixed$(loudness_weight, 2)
appendInfoLine: "               top-k ", string$(top_k_candidates), ", randomness ", fixed$(randomness, 2),
    ... ", continuity ", fixed$(continuity_preference, 2), ", penalty ", fixed$(repetition_penalty, 2),
    ... ", gate ", fixed$(gate_threshold_dB, 0), " dB"
appendInfoLine: "Continuous:    ", statChain$, " % of grains continue the previous corpus read"
appendInfoLine: "Target grains: ", statSourceGrains$
appendInfoLine: "Silenced:      ", statSilenced$
appendInfoLine: "Corpus pool:   ", statCorpusGrains$
appendInfoLine: "Files used:    ", statUniqueUsed$
appendInfoLine: "Skipped files: ", statSkipped$
appendInfoLine: "Weights L/T/P: ", statWeights$, " %"
appendInfoLine: "Pitch rel.:    ", statPitchRel$, "  |  YIN fmin: ", statPitchFmin$
appendInfoLine: "Random seed:   ", statSeed$
appendInfoLine: "Render time:   ", statTime$

selectObject: resultSound

@cleanUpTempFiles

if play_result
    Play
endif

# ============================================================
# Procedures
# ============================================================

procedure pictureSafe: .s$
    # Picture-window markup: _ subscript, % italic, # bold, ^ superscript.
    .result$ = replace$(.s$, "_", "\_ ", 0)
    .result$ = replace$(.result$, "%", "\% ", 0)
    .result$ = replace$(.result$, "#", "\# ", 0)
    .result$ = replace$(.result$, "^", "\^ ", 0)
endproc

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
# ------------------------------------------------------------
# Drawing helpers
# ------------------------------------------------------------

procedure rgb: .r, .g, .b
    .s$ = "{" + fixed$(max(0, min(1, .r)), 2) + ", " + fixed$(max(0, min(1, .g)), 2)
        ... + ", " + fixed$(max(0, min(1, .b)), 2) + "}"
endproc

procedure caption: .x0, .x1, .yTop, .num$, .title$, .sub$
    # Two-line caption above a panel whose inner top is .yTop.
    Font size: 7
    Select inner viewport: .x0, .x1, .yTop - 0.34, .yTop - 0.02
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0, "left", 0.72, "half", "##" + .num$ + "##   ##" + .title$ + "##"
    Font size: 6
    Select inner viewport: .x0, .x1, .yTop - 0.34, .yTop - 0.02
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0, "left", 0.22, "half", .sub$
    Colour: "Black"
endproc

procedure rail: .x0, .x1, .y0, .y1, .labelX, .text$
    # Rotated panel name on one shared left rail.
    Font size: 6
    Select inner viewport: .x0, .x1, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: .labelX, "centre", 0.5, "bottom", "Helvetica", 6, "90", .text$
endproc

procedure fpHead: .y, .text$
    Colour: "Black"
    Text: 0.03, "left", .y - 0.5, "half", "##" + .text$ + "##"
endproc

procedure fpBar: .y, .label$, .frac, .value$
    # One fingerprint row: label | bar | value (world: x 0..1, row height 1).
    .frac = max(0, min(1, .frac))
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.06, "left", .y - 0.5, "half", .label$
    Paint rectangle: "{0.88, 0.88, 0.90}", 0.42, 0.84, .y - 0.78, .y - 0.22
    if .frac > 0
        Paint rectangle: "{0.30, 0.42, 0.62}", 0.42, 0.42 + 0.42 * .frac, .y - 0.78, .y - 0.22
    endif
    Text: 0.86, "left", .y - 0.5, "half", .value$
    Colour: "Black"
endproc

procedure niceStep: .span, .n
    # Round tick step (1, 2 or 5 x 10^k) giving about .n ticks.
    .raw = max(.span, 1e-9) / .n
    .p = 10 ^ floor(log10(.raw))
    .f = .raw / .p
    if .f < 1.5
        .m = 1
    elsif .f < 3.5
        .m = 2
    elsif .f < 7.5
        .m = 5
    else
        .m = 10
    endif
    .result = .m * .p
endproc

procedure vecRange: .v#, .n
    # 1st-99th percentile range with an 8 % margin; safe for n = 0.
    if .n < 1
        .lo = 0
        .hi = 1
    else
        .s# = zero#(.n)
        for .i to .n
            .s#[.i] = .v#[.i]
        endfor
        .srt# = sort#(.s#)
        .iLo = max(1, round(0.01 * .n))
        .iHi = min(.n, max(.iLo, round(0.99 * .n)))
        .lo = .srt#[.iLo]
        .hi = .srt#[.iHi]
        if .hi - .lo < 1e-6
            .lo = .lo - 0.5
            .hi = .hi + 0.5
        endif
        .pad = 0.08 * (.hi - .lo)
        .lo = .lo - .pad
        .hi = .hi + .pad
    endif
endproc

procedure clampXY: .x, .y
    # Keep map points inside the map panel (Paint/Draw do not clip).
    .x = max(xLo, min(xHi, .x))
    .y = max(yLo, min(yHi, .y))
endproc

procedure hzLabel: .hz
    if .hz >= 1000
        .s$ = fixed$(.hz / 1000, 1) + "k"
    else
        .s$ = fixed$(.hz, 0)
    endif
endproc

procedure msLabel: .ms
    if abs(.ms - round(.ms)) < 0.05
        .s$ = fixed$(.ms, 0)
    else
        .s$ = fixed$(.ms, 1)
    endif
endproc
