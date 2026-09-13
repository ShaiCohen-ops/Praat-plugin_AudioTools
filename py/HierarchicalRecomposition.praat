# ============================================================
# Praat AudioTools - HierarchicalRecomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6 (2026) - Structural stereo spatialization + process map
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hierarchical Neural Recomposition.
#   Segments audio into events -> phrases -> sections.
#   A PyTorch three-level hierarchical model (EventEncoder,
#   PhraseEncoder, SectionPlanner) generates a recomposition
#   plan. Audio is re-rendered from the original source material.
#
# Changelog v1.6:
#   - The static five-box "plan generator" diagram is replaced by the plan the
#     generator actually produced: a phrase x slot matrix of the 16 compositional
#     values, exported by hierarchical_recomposition.py v1.5.
#   - New panel: where in the SOURCE each scheduled operation's material came
#     from, which is what makes recall, repetition and braiding visible.
#   - The stereo-field strip is now its own panel and is drawn only when the
#     render is actually spatial, instead of a flat line squeezed under the
#     operations lanes in mono.
#   - Every time panel shares one axis, so the duration change reads as width.
#   - Fixed: no panel drew axis numbers; panel captions were painted over by the
#     previous panel's axis label; underscores in model and mode names were
#     rendered as subscript markup.
#
# Changelog v1.5:
#   - Pairs with hierarchical_recomposition.py v1.4: RecursiveSpeechChoir voices
#     are equal-power panned across stereo; braid strands and EchoArchitecture
#     echoes receive deterministic structural pan positions. Non-spatial presets
#     remain mono.
#   - The actual-operations panel now includes a bottom stereo-field trace from
#     per-operation pan telemetry, and QC reports output channels/pan extent.
#
# Changelog v1.4:
#   - Replaced the mostly before/after visualization with a process map built
#     from actual Python telemetry: source event boundaries, phrase spans, the
#     seeded neural plan-generator chain, actual scheduled operations, and one
#     same-scale acoustic before/after panel.
#   - Pairs with hierarchical_recomposition.py v1.3, which exports diagnostic
#     process telemetry only; audio planning/rendering is unchanged.
#
# Changelog v1.3:
#   - Removed Density, Source trace, and Custom Section contrast from the visible
#     form because they do not affect the current Custom renderer/planner. Legacy
#     positional placeholders are still passed so the CLI layout remains stable.
#   - Pairs with hierarchical_recomposition.py v1.2 (phase-safe multichannel
#     analysis and explicit seeded-random/untrained neural-model documentation).
#   - Dependency probe no longer blocks the documented NumPy fallback when torch
#     is absent, and uses importlib.find_spec instead of importing heavy packages.
#
# Changelog v1.2:
#   - On engine failure the captured Python stderr (traceback) is now
#     shown in the error dialog instead of "check the console", which is
#     invisible when Praat runs from the GUI.
#   - Pairs with hierarchical_recomposition.py v1.1 (fallback reachable,
#     surprise-swap crash fixed, real sample rate in the planner, FFT
#     autocorrelation).
#
# Dependencies (Python):
#   Required: pip install numpy scipy soundfile
#   Optional: torch (uses the seeded NumPy fallback when unavailable)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-
#   Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

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

# ---- PATHS ----
# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/hierarchical_recomposition.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/hierarchical_recomposition.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: hierarchical_recomposition.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_hnr_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_hnr_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_hnr_stats.txt"
tempLog$     = temporaryDirectory$ + "/temp_hnr_log.txt"
probeMarker$ = temporaryDirectory$ + "/temp_hnr_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Hierarchical Neural Recomposition v1.6
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Latent Counterpoint
        option Memory Spiral
        option Fragmented Litany
        option Formal Braiding
        option Collapsing Refrain
        option Echo Architecture
        option Recursive Speech Choir
        option Hidden Sonata
    comment === Target ===
    real    Target_duration  1.0
    comment === Event / Phrase Level ===
    real    Phrase_coherence 0.5
    real    Fragmentation    0.3
    comment === Section Level ===
    real    Memory_strength  0.5
    real    Repetition       0.5
    comment === Rendering ===
    real    Overlap_amount   0.3
    real    Formal_surprise  0.2
    comment === Output ===
    integer Random_seed       42
    boolean Draw_visualization 1
    boolean Play_result        1
endform

# Legacy positional placeholders retained for Python CLI compatibility.
# The v1.1/v1.2 engine does not use these values in planning or rendering.
density = 0.5
section_contrast = 0.5
source_trace = 0.0

# ---- RESOLVE PRESET NAME ----
presetName$ = "Custom"
if preset = 2
    presetName$ = "LatentCounterpoint"
elsif preset = 3
    presetName$ = "MemorySpiral"
elsif preset = 4
    presetName$ = "FragmentedLitany"
elsif preset = 5
    presetName$ = "FormalBraiding"
elsif preset = 6
    presetName$ = "CollapsingRefrain"
elsif preset = 7
    presetName$ = "EchoArchitecture"
elsif preset = 8
    presetName$ = "RecursiveSpeechChoir"
elsif preset = 9
    presetName$ = "HiddenSonata"
endif

# ---- CLAMP ALL PARAMS ----
if target_duration < 0.1
    target_duration = 0.1
endif
if target_duration > 5.0
    target_duration = 5.0
endif
if phrase_coherence < 0
    phrase_coherence = 0
endif
if phrase_coherence > 1
    phrase_coherence = 1
endif
if memory_strength < 0
    memory_strength = 0
endif
if memory_strength > 1
    memory_strength = 1
endif
if repetition < 0
    repetition = 0
endif
if repetition > 1
    repetition = 1
endif
if fragmentation < 0
    fragmentation = 0
endif
if fragmentation > 1
    fragmentation = 1
endif
if overlap_amount < 0
    overlap_amount = 0
endif
if overlap_amount > 1
    overlap_amount = 1
endif
if formal_surprise < 0
    formal_surprise = 0
endif
if formal_surprise > 1
    formal_surprise = 1
endif

# ---- CAPTURE INPUT PROPERTIES ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Hierarchical Neural Recomposition v1.6 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: ""
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s"
appendInfoLine: "SR:            ", sr, " Hz"
appendInfoLine: "Channels:      ", nChannels
appendInfoLine: ""
appendInfoLine: "Target duration ratio: ", target_duration
appendInfoLine: "Phrase coherence:      ", phrase_coherence
appendInfoLine: "Memory strength:       ", memory_strength
appendInfoLine: "Repetition:            ", repetition
appendInfoLine: "Fragmentation:         ", fragmentation
appendInfoLine: "Overlap amount:        ", overlap_amount
appendInfoLine: "Formal surprise:       ", formal_surprise
appendInfoLine: "Seed:                  ", random_seed
appendInfoLine: ""

# ---- PYTHON DEPENDENCY VALIDATION ----
appendInfoLine: "[1/4] Detecting Python dependencies..."

# Lightweight probe: required packages only. PyTorch is optional because the
# engine has a seeded NumPy fallback. find_spec avoids importing heavy modules.
probeCmd$ = pythonCmd$ + " -c ""import importlib.util; m=[p for p in ('numpy','scipy','soundfile') if importlib.util.find_spec(p) is None]; open('""" + probeMarkerJ$ + """','w').write(','.join(m))"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python could not be started."
endif

missingDeps$ = readFile$(probeMarker$)
deleteFile: probeMarker$
if length(missingDeps$) > 0
    @cleanUpTempFiles
    exitScript: "Missing required Python package(s): " + missingDeps$ + newline$ + "Install: pip install numpy scipy soundfile"
endif
appendInfoLine: "  Python found: ", pythonCmd$
appendInfoLine: "  PyTorch optional; NumPy fallback is supported."

# ---- EXPORT WAV ----
appendInfoLine: "[2/4] Exporting audio..."
selectObject: sound
Save as WAV file: tempInput$

# ---- RUN PYTHON ----
appendInfoLine: "[3/4] Running hierarchical neural recomposition..."
appendInfoLine: "  (event segmentation + phrase grouping + section planning + rendering)"

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + fixed$(target_duration, 4)
    ... + " " + fixed$(density, 4)
    ... + " " + fixed$(phrase_coherence, 4)
    ... + " " + fixed$(section_contrast, 4)
    ... + " " + fixed$(memory_strength, 4)
    ... + " " + fixed$(repetition, 4)
    ... + " " + fixed$(fragmentation, 4)
    ... + " " + fixed$(overlap_amount, 4)
    ... + " " + fixed$(source_trace, 4)
    ... + " " + fixed$(formal_surprise, 4)
    ... + " " + string$(random_seed)
    ... + " " + presetName$
    ... + " 2> """ + tempLog$ + """"

runSystem_nocheck: pyCmd$

# ---- VERIFY OUTPUT ----
if not fileReadable(tempOutput$)
    errMsg$ = "Python recomposition failed."
    if fileReadable(tempLog$)
        errMsg$ = errMsg$ + newline$ + newline$ + "Python error output:" + newline$ + readFile$(tempLog$)
    endif
    @cleanUpTempFiles
    exitScript: errMsg$
endif

# ---- IMPORT RESULT ----
appendInfoLine: "[4/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_hnr_" + presetName$
resultSound = selected("Sound")
dur_out     = Get total duration
rms_out     = Get root-mean-square: 0, 0

appendInfoLine: "  Result: ", soundName$ + "_hnr_" + presetName$
appendInfoLine: "  Output duration: ", fixed$(dur_out, 2), " s"

# ---- READ STATS ----
nEvStat$    = "?"
nPhStat$    = "?"
nSecStat$   = "?"
torchStat$  = "?"
densityStat$ = "?"
brightStat$ = "?"
neuralModel$ = "?"
monoStrategy$ = "?"
spatialMode$ = "mono"
outputChannels = 1
panMin = 0
panMax = 0
nSpatialOps = 0
planRep = 0
planFrag = 0
planOverlap = 0
planStretch = 0
planMemory = 0
planBraid = 0
nEventViz = 0
nPhraseViz = 0
nOpViz = 0
nOpsTotal = 0
nOpPlace = 0
nOpRepeat = 0
nOpFragment = 0
nOpRecall = 0
nOpBraid = 0
nOpEcho = 0
nOpInvert = 0
nPlanViz = 0
nPlanCols = 0
nPlanRowsAll = 0
nMapOps = 0
planSpread$ = "?"

procedure parseStatLine: .text$, .key$
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl = 0
            .nl = length(.rest$) + 1
        endif
        .result$ = left$(.rest$, .nl - 1)
    else
        .result$ = "?"
    endif
endproc

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_phrases="
    nPhStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_sections="
    nSecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "torch_used="
    torchStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_density="
    densityStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_brightness="
    brightStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "neural_model="
    neuralModel$ = parseStatLine.result$
    @parseStatLine: statsText$, "mono_strategy="
    monoStrategy$ = parseStatLine.result$
    @parseStatLine: statsText$, "spatial_mode="
    if parseStatLine.result$ <> "?"
        spatialMode$ = parseStatLine.result$
    endif
    @parseStatLine: statsText$, "output_channels="
    if parseStatLine.result$ <> "?"
        outputChannels = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "pan_min="
    if parseStatLine.result$ <> "?"
        panMin = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "pan_max="
    if parseStatLine.result$ <> "?"
        panMax = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_spatial_ops="
    if parseStatLine.result$ <> "?"
        nSpatialOps = number(parseStatLine.result$)
    endif

    @parseStatLine: statsText$, "plan_repetition_mean="
    if parseStatLine.result$ <> "?"
        planRep = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_fragmentation_mean="
    if parseStatLine.result$ <> "?"
        planFrag = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_overlap_mean="
    if parseStatLine.result$ <> "?"
        planOverlap = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_stretch_mean="
    if parseStatLine.result$ <> "?"
        planStretch = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_memory_mean="
    if parseStatLine.result$ <> "?"
        planMemory = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_braid_mean="
    if parseStatLine.result$ <> "?"
        planBraid = number(parseStatLine.result$)
    endif

    @parseStatLine: statsText$, "n_event_viz="
    if parseStatLine.result$ <> "?"
        nEventViz = number(parseStatLine.result$)
    endif
    for iE from 0 to nEventViz - 1
        @parseStatLine: statsText$, "event_" + string$(iE) + "="
        row$ = parseStatLine.result$
        c1 = index(row$, ",")
        rest$ = mid$(row$, c1 + 1, length(row$) - c1)
        c2 = index(rest$, ",")
        rest2$ = mid$(rest$, c2 + 1, length(rest$) - c2)
        c3 = index(rest2$, ",")
        evStart_'iE' = number(left$(row$, c1 - 1))
        evEnd_'iE' = number(left$(rest$, c2 - 1))
        evPhrase_'iE' = number(left$(rest2$, c3 - 1))
        evIndex_'iE' = number(mid$(rest2$, c3 + 1, length(rest2$) - c3))
    endfor

    @parseStatLine: statsText$, "n_phrase_viz="
    if parseStatLine.result$ <> "?"
        nPhraseViz = number(parseStatLine.result$)
    endif
    for iP from 0 to nPhraseViz - 1
        @parseStatLine: statsText$, "phrase_" + string$(iP) + "="
        row$ = parseStatLine.result$
        c1 = index(row$, ",")
        rest$ = mid$(row$, c1 + 1, length(row$) - c1)
        c2 = index(rest$, ",")
        rest2$ = mid$(rest$, c2 + 1, length(rest$) - c2)
        c3 = index(rest2$, ",")
        phStart_'iP' = number(left$(row$, c1 - 1))
        phEnd_'iP' = number(left$(rest$, c2 - 1))
        phCount_'iP' = number(left$(rest2$, c3 - 1))
        phIndex_'iP' = number(mid$(rest2$, c3 + 1, length(rest2$) - c3))
    endfor

    @parseStatLine: statsText$, "n_op_viz="
    if parseStatLine.result$ <> "?"
        nOpViz = number(parseStatLine.result$)
    endif
    for iO from 0 to nOpViz - 1
        @parseStatLine: statsText$, "op_" + string$(iO) + "="
        row$ = parseStatLine.result$
        c1 = index(row$, ",")
        opType_'iO'$ = left$(row$, c1 - 1)
        rest$ = mid$(row$, c1 + 1, length(row$) - c1)
        c2 = index(rest$, ",")
        opStart_'iO' = number(left$(rest$, c2 - 1))
        rest2$ = mid$(rest$, c2 + 1, length(rest$) - c2)
        c3 = index(rest2$, ",")
        opEnd_'iO' = number(left$(rest2$, c3 - 1))
        rest3$ = mid$(rest2$, c3 + 1, length(rest2$) - c3)
        c4 = index(rest3$, ",")
        opEvent_'iO' = number(left$(rest3$, c4 - 1))
        rest4$ = mid$(rest3$, c4 + 1, length(rest3$) - c4)
        c5 = index(rest4$, ",")
        if c5 > 0
            opGain_'iO' = number(left$(rest4$, c5 - 1))
            rest5$ = mid$(rest4$, c5 + 1, length(rest4$) - c5)
            c6 = index(rest5$, ",")
            if c6 > 0
                opPan_'iO' = number(left$(rest5$, c6 - 1))
                opVoice_'iO' = number(mid$(rest5$, c6 + 1, length(rest5$) - c6))
            else
                opPan_'iO' = number(rest5$)
                opVoice_'iO' = 0
            endif
        else
            # Backward-compatible old telemetry: type,start,end,event,gain
            opGain_'iO' = number(rest4$)
            opPan_'iO' = 0
            opVoice_'iO' = 0
        endif
    endfor

    @parseStatLine: statsText$, "n_ops_total="
    if parseStatLine.result$ <> "?"
        nOpsTotal = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_place="
    if parseStatLine.result$ <> "?"
        nOpPlace = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_repeat="
    if parseStatLine.result$ <> "?"
        nOpRepeat = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_fragment="
    if parseStatLine.result$ <> "?"
        nOpFragment = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_recall="
    if parseStatLine.result$ <> "?"
        nOpRecall = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_braid="
    if parseStatLine.result$ <> "?"
        nOpBraid = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_echo="
    if parseStatLine.result$ <> "?"
        nOpEcho = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_op_invert="
    if parseStatLine.result$ <> "?"
        nOpInvert = number(parseStatLine.result$)
    endif

    # Source span of each drawn operation. Kept in its own key so the fixed
    # op_ field layout stays readable by older front-ends.
    for iO from 0 to nOpViz - 1
        opSrcStart_'iO' = -1
        opSrcEnd_'iO' = -1
        @parseStatLine: statsText$, "opsrc_" + string$(iO) + "="
        if parseStatLine.result$ <> "?"
            srow$ = parseStatLine.result$
            cs = index(srow$, ",")
            if cs > 0
                opSrcStart_'iO' = number(left$(srow$, cs - 1))
                opSrcEnd_'iO' = number(mid$(srow$, cs + 1, length(srow$) - cs))
                if opSrcStart_'iO' >= 0
                    nMapOps = nMapOps + 1
                endif
            endif
        endif
    endfor

    # The generated plan matrix.
    @parseStatLine: statsText$, "n_plan_viz="
    if parseStatLine.result$ <> "?"
        nPlanViz = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_plan_cols="
    if parseStatLine.result$ <> "?"
        nPlanCols = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_rows_all="
    if parseStatLine.result$ <> "?"
        nPlanRowsAll = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "plan_row_spread="
    planSpread$ = parseStatLine.result$
    for iC from 0 to nPlanCols - 1
        @parseStatLine: statsText$, "plan_col_" + string$(iC) + "="
        planCol_'iC'$ = parseStatLine.result$
    endfor
    for iR from 0 to nPlanViz - 1
        @parseStatLine: statsText$, "plan_row_" + string$(iR) + "="
        prow$ = parseStatLine.result$
        for iC from 0 to nPlanCols - 1
            cpos = index(prow$, ",")
            if cpos > 0
                vtxt$ = left$(prow$, cpos - 1)
                prow$ = mid$(prow$, cpos + 1, length(prow$) - cpos)
            else
                vtxt$ = prow$
                prow$ = ""
            endif
            pk = iR * nPlanCols + iC
            planVal_'pk' = number(vtxt$)
        endfor
    endfor
endif

appendInfoLine: ""
appendInfoLine: "Events:     ", nEvStat$
appendInfoLine: "Phrases:    ", nPhStat$
appendInfoLine: "Sections:   ", nSecStat$
appendInfoLine: "PyTorch:    ", torchStat$
appendInfoLine: "Density:    ", densityStat$
appendInfoLine: "Brightness: ", brightStat$

###############################################################################
# VISUALIZATION — actual process map
#
# Every time panel shares one axis running 0..axisDur, so a source panel ends
# partway across while an output panel fills its width: the change in duration
# is visible as width rather than hidden by per-panel autoscaling.
#
#   1  source waveform with the detected event boundaries, and the event ->
#      phrase grouping directly underneath it;
#   2  the plan the seeded generator actually produced, one row per phrase and
#      one column per compositional slot;
#   3  the operations that plan turned into, by type, over output time;
#   4  their stereo positions (drawn only when the render is actually spatial);
#   5  where in the SOURCE each operation's material came from;
#   6  the rendered result on the same time scale as the source.
###############################################################################

if draw_visualization
    vizL = 0.65
    vizR = 7.70
    railX = -0.043

    selectObject: sound
    srcHi = Get maximum: 0, 0, "None"
    srcLo = Get minimum: 0, 0, "None"
    selectObject: resultSound
    outHi = Get maximum: 0, 0, "None"
    outLo = Get minimum: 0, 0, "None"
    ampViz = max(abs(srcHi), abs(srcLo))
    ampViz = max(ampViz, max(abs(outHi), abs(outLo)))
    if ampViz < 0.001
        ampViz = 0.001
    endif
    axisDur = max(dur, dur_out)

    @snapStep: axisDur, 8
    snapT = snapStep.step

    # The stereo-field strip is only drawn when the render is actually spatial;
    # in mono it was a flat line through the middle of a panel.
    showPan = 0
    if panMax - panMin > 0.01
        showPan = 1
    endif

    hasPlan = 0
    if nPlanViz > 0 and nPlanCols > 0
        hasPlan = 1
    endif

    # An engine older than v1.5 reports no source span per operation, so the
    # map would be an empty framed panel under a caption promising content.
    hasMap = 0
    if nMapOps > 0
        hasMap = 1
    endif

    # --- layout --------------------------------------------------------------
    yWa = 0.80
    yWb = 1.45
    yHa = 1.47
    yHb = 1.95

    yPa = 2.62
    yPb = 4.35
    if hasPlan = 0
        yPa = 2.62
        yPb = 2.62
    endif

    yOpsA = 5.00
    yOpsB = 5.95
    if hasPlan = 0
        yOpsA = 2.75
        yOpsB = 3.70
    endif

    yPanA = yOpsB + 0.02
    yPanB = yPanA + 0.45
    if showPan = 0
        yPanB = yOpsB
    endif

    yMapA = yPanB + 0.34
    yMapB = yMapA + 0.90
    if hasMap = 0
        yMapA = yPanB
        yMapB = yPanB
    endif
    yResA = yMapB + 0.32
    yResB = yResA + 0.65
    ySumA = yResB + 0.54
    ySumB = ySumA + 0.90
    canvasH = ySumB + 0.15

    Erase all
    Colour: "Black"
    Line width: 1
    Solid line

    # --- title ---------------------------------------------------------------
    @sanitize: soundName$
    hdrName$ = sanitize.out$
    @sanitize: presetName$
    hdrPreset$ = sanitize.out$
    Font size: 13
    Select inner viewport: vizL, vizR, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##Hierarchical Recomposition##"
    Font size: 7
    Select inner viewport: vizL, vizR, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", 0.24, "half", hdrName$ + "   |   " + hdrPreset$
        ... + "   |   seed " + string$(random_seed)
        ... + "   |   " + nEvStat$ + " events, " + nPhStat$ + " phrases, " + nSecStat$ + " sections"
    Colour: "Black"

    # --- 1a: source waveform with detected event boundaries -------------------
    @caption: vizL, vizR, yWa, yWb, "1  Onset segmentation and the event to phrase grouping it feeds"
    Font size: 7
    Select inner viewport: vizL, vizR, yWa, yWb
    selectObject: sound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, axisDur, -ampViz, ampViz, "no", "Curve"
    Select inner viewport: vizL, vizR, yWa, yWb
    Axes: 0, axisDur, -ampViz, ampViz
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    for iE from 0 to nEventViz - 1
        Draw line: evStart_'iE', -ampViz, evStart_'iE', ampViz
    endfor
    Colour: "Black"
    Select inner viewport: vizL, vizR, yWa, yWb
    Axes: 0, axisDur, -ampViz, ampViz
    Draw inner box
    Marks bottom every: 1, snapT, "no", "yes", "no"
    @rail: yWa, yWb, "Source"

    # --- 1b: event and phrase spans ------------------------------------------
    Font size: 7
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, axisDur, 0, 2
    Paint rectangle: "{1.00, 1.00, 1.00}", 0, axisDur, 0, 2
    for iE from 0 to nEventViz - 1
        Paint rectangle: "{0.80, 0.86, 0.95}", evStart_'iE', evEnd_'iE', 1.12, 1.82
        Colour: "{0.35, 0.45, 0.62}"
        Draw rectangle: evStart_'iE', evEnd_'iE', 1.12, 1.82
    endfor
    for iP from 0 to nPhraseViz - 1
        Paint rectangle: "{0.87, 0.87, 0.91}", phStart_'iP', phEnd_'iP', 0.18, 0.88
        Colour: "{0.35, 0.35, 0.45}"
        Draw rectangle: phStart_'iP', phEnd_'iP', 0.18, 0.88
    endfor
    Colour: "Black"
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, axisDur, 0, 2
    if nPhraseViz <= 16
        Font size: 5.5
        Select inner viewport: vizL, vizR, yHa, yHb
        Axes: 0, axisDur, 0, 2
        Colour: "{0.30, 0.30, 0.38}"
        for iP from 0 to nPhraseViz - 1
            Text: (phStart_'iP' + phEnd_'iP') / 2, "centre", 0.53, "half", "P" + string$(phIndex_'iP' + 1)
        endfor
        Colour: "Black"
    endif
    Font size: 7
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, axisDur, 0, 2
    Draw inner box
    One mark left: 1.47, "no", "yes", "no", "events"
    One mark left: 0.53, "no", "yes", "no", "phrases"
    Marks bottom every: 1, snapT, "yes", "yes", "no"
    Text bottom: "yes", "Source time (s)"

    # --- 2: the generated plan -----------------------------------------------
    if hasPlan
        @caption: vizL, vizR, yPa, yPb, "2  The plan the seeded generator produced - one column per phrase, one row per compositional slot (darker = higher)"
        Font size: 5.5
        Select inner viewport: vizL, vizR, yPa, yPb
        Axes: 0, nPlanViz, 0, nPlanCols
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, nPlanViz, 0, nPlanCols
        for iR from 0 to nPlanViz - 1
            for iC from 0 to nPlanCols - 1
                pk = iR * nPlanCols + iC
                pv = planVal_'pk'
                if pv = undefined
                    pv = 0
                endif
                pv = min(1, max(0, pv))
                cellCol$ = "{" + fixed$(0.97 - 0.82 * pv, 3)
                    ... + ", " + fixed$(0.98 - 0.63 * pv, 3)
                    ... + ", " + fixed$(0.99 - 0.31 * pv, 3) + "}"
                yTop = nPlanCols - iC
                Paint rectangle: cellCol$, iR, iR + 1, yTop - 1, yTop
            endfor
        endfor
        Colour: "Black"
        Select inner viewport: vizL, vizR, yPa, yPb
        Axes: 0, nPlanViz, 0, nPlanCols
        Draw inner box
        for iC from 0 to nPlanCols - 1
            @sanitize: planCol_'iC'$
            One mark left: nPlanCols - iC - 0.5, "no", "yes", "no", sanitize.out$
        endfor
        if nPlanViz <= 24
            for iR from 0 to nPlanViz - 1
                One mark bottom: iR + 0.5, "no", "yes", "no", "P" + string$(iR + 1)
            endfor
        else
            @snapStep: nPlanViz, 8
            Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        endif
        Font size: 6
        Select inner viewport: vizL, vizR, yPa, yPb
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "Phrase  (plan row, after user-parameter modulation)"
    endif

    # --- 3: scheduled operations by type -------------------------------------
    @caption: vizL, vizR, yOpsA, yOpsB, "3  Operations actually scheduled for this render"
    Font size: 7
    Select inner viewport: vizL, vizR, yOpsA, yOpsB
    Axes: 0, axisDur, 0, 7
    Paint rectangle: "{1.00, 1.00, 1.00}", 0, axisDur, 0, 7
    for iO from 0 to nOpViz - 1
        @opLane: opType_'iO'$
        if opEnd_'iO' > opStart_'iO'
            Paint rectangle: opLane.fill$, opStart_'iO', opEnd_'iO', opLane.y - 0.28, opLane.y + 0.28
            Colour: opLane.line$
            Draw rectangle: opStart_'iO', opEnd_'iO', opLane.y - 0.28, opLane.y + 0.28
        endif
    endfor
    Colour: "Black"
    Select inner viewport: vizL, vizR, yOpsA, yOpsB
    Axes: 0, axisDur, 0, 7
    Draw inner box
    @laneLabel: 6.5, nOpPlace, "place"
    @laneLabel: 5.5, nOpRepeat, "repeat"
    @laneLabel: 4.5, nOpFragment, "fragment"
    @laneLabel: 3.5, nOpRecall, "recall"
    @laneLabel: 2.5, nOpBraid, "braid"
    @laneLabel: 1.5, nOpEcho, "echo"
    @laneLabel: 0.5, nOpInvert, "invert"
    Font size: 7
    Select inner viewport: vizL, vizR, yOpsA, yOpsB
    Axes: 0, axisDur, 0, 7
    Marks bottom every: 1, snapT, "no", "yes", "no"

    # --- 4: stereo field (spatial renders only) ------------------------------
    if showPan
        Font size: 7
        Select inner viewport: vizL, vizR, yPanA, yPanB
        Axes: 0, axisDur, -1.15, 1.15
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, axisDur, -1.15, 1.15
        Dotted line
        Colour: "{0.75, 0.75, 0.80}"
        Draw line: 0, 0, axisDur, 0
        Solid line
        Select inner viewport: vizL, vizR, yPanA, yPanB
        Axes: 0, axisDur, -1.15, 1.15
        Line width: 2
        for iO from 0 to nOpViz - 1
            @opLane: opType_'iO'$
            Colour: opLane.line$
            if opEnd_'iO' > opStart_'iO'
                Draw line: opStart_'iO', opPan_'iO', opEnd_'iO', opPan_'iO'
            endif
        endfor
        Line width: 1
        Colour: "Black"
        Select inner viewport: vizL, vizR, yPanA, yPanB
        Axes: 0, axisDur, -1.15, 1.15
        Draw inner box
        One mark left: 0.85, "no", "yes", "no", "R"
        One mark left: 0, "no", "yes", "no", "0"
        One mark left: -0.85, "no", "yes", "no", "L"
        Marks bottom every: 1, snapT, "no", "yes", "no"
        @rail: yPanA, yPanB, "Pan"
    endif

    # --- 5: where each operation's material came from ------------------------
    if hasMap
        @caption: vizL, vizR, yMapA, yMapB, "5  Source of every scheduled operation - a flat run is a held source position, a jump down is a recall"
        Font size: 7
        Select inner viewport: vizL, vizR, yMapA, yMapB
        Axes: 0, axisDur, 0, axisDur
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, axisDur, 0, axisDur
        Dotted line
        Colour: "{0.78, 0.78, 0.84}"
        Draw line: 0, 0, axisDur, axisDur
        Solid line
        Select inner viewport: vizL, vizR, yMapA, yMapB
        Axes: 0, axisDur, 0, axisDur
        Line width: 2
        for iO from 0 to nOpViz - 1
            if opSrcStart_'iO' >= 0 and opEnd_'iO' > opStart_'iO'
                @opLane: opType_'iO'$
                Colour: opLane.line$
                Draw line: opStart_'iO', opSrcStart_'iO', opEnd_'iO', opSrcEnd_'iO'
            endif
        endfor
        Line width: 1
        Colour: "Black"
        Select inner viewport: vizL, vizR, yMapA, yMapB
        Axes: 0, axisDur, 0, axisDur
        Draw inner box
        @snapStep: axisDur, 4
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        Marks bottom every: 1, snapT, "no", "yes", "no"
        @rail: yMapA, yMapB, "Source s"
    endif

    # --- 6: the rendered result ----------------------------------------------
    @caption: vizL, vizR, yResA, yResB, "6  Rendered recomposition, drawn at the same time and amplitude scale as the source in panel 1"
    Font size: 7
    Select inner viewport: vizL, vizR, yResA, yResB
    selectObject: resultSound
    Colour: "{0.20, 0.40, 0.75}"
    Draw: 0, axisDur, -ampViz, ampViz, "no", "Curve"
    Colour: "Black"
    Select inner viewport: vizL, vizR, yResA, yResB
    Axes: 0, axisDur, -ampViz, ampViz
    Draw inner box
    Marks bottom every: 1, snapT, "yes", "yes", "no"
    Text bottom: "yes", "Output time (s)"
    @rail: yResA, yResB, "Result"

    # --- summary --------------------------------------------------------------
    @sanitize: neuralModel$
    modelTxt$ = sanitize.out$
    @sanitize: spatialMode$
    spatialTxt$ = sanitize.out$
    @sanitize: monoStrategy$
    monoTxt$ = sanitize.out$

    Font size: 7
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 8
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.015, "left", 0.90, "half", "##Process summary##"

    Font size: 7
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Text: 0.015, "left", 0.755, "half", "Hierarchy: " + nEvStat$ + " events to " + nPhStat$
        ... + " phrases to " + nSecStat$ + " sections"
        ... + "   coherence " + fixed$(phrase_coherence, 2)
        ... + ", fragmentation " + fixed$(fragmentation, 2)
        ... + "   mean density " + densityStat$ + ", mean brightness " + brightStat$
    planTxt$ = "Plan: " + modelTxt$ + ", seed " + string$(random_seed)
    if hasPlan
        planTxt$ = planTxt$ + ", " + string$(nPlanRowsAll) + " rows x " + string$(nPlanCols) + " slots"
            ... + ", phrase-to-phrase spread " + planSpread$
    endif
    Text: 0.015, "left", 0.620, "half", planTxt$
        ... + "   means repeat " + fixed$(planRep, 2)
        ... + ", fragment " + fixed$(planFrag, 2)
        ... + ", overlap " + fixed$(planOverlap, 2)
        ... + ", stretch " + fixed$(planStretch, 2)
        ... + ", memory " + fixed$(planMemory, 2)
        ... + ", braid " + fixed$(planBraid, 2)
    Text: 0.015, "left", 0.485, "half", "Operations: " + string$(nOpsTotal) + " total"
        ... + "   place " + string$(nOpPlace) + ", repeat " + string$(nOpRepeat)
        ... + ", fragment " + string$(nOpFragment) + ", recall " + string$(nOpRecall)
        ... + ", braid " + string$(nOpBraid) + ", echo " + string$(nOpEcho)
        ... + ", invert " + string$(nOpInvert)
    opDrawn$ = string$(nOpViz) + " of " + string$(nOpsTotal)
    Text: 0.015, "left", 0.350, "half", "Rendering: target ratio x" + fixed$(target_duration, 2)
        ... + ", overlap " + fixed$(overlap_amount, 2)
        ... + ", surprise " + fixed$(formal_surprise, 2)
        ... + "   analysis " + monoTxt$
        ... + "   " + opDrawn$ + " operations drawn"
    Text: 0.015, "left", 0.215, "half", "Output: " + string$(outputChannels) + " ch, " + spatialTxt$
        ... + ", " + string$(nSpatialOps) + " panned operations, pan " + fixed$(panMin, 2)
        ... + " to " + fixed$(panMax, 2)
    Text: 0.015, "left", 0.080, "half", "Level: duration " + fixed$(dur, 2) + " to " + fixed$(dur_out, 2)
        ... + " s   RMS " + fixed$(rms_orig, 4) + " to " + fixed$(rms_out, 4)
    if hasPlan = 0 or hasMap = 0
        Colour: "{0.70, 0.35, 0.10}"
        Text: 0.985, "right", 0.90, "half", "stages 2 and 5 need engine v1.5 or newer"
        Colour: "Black"
    endif
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1

    # Save as / Copy follow the CURRENT viewport selection, so end on the whole
    # canvas or the export is silently cropped to the last panel.
    Select outer viewport: 0, 8, 0, canvasH
endif

# ---- CLEANUP AND FINISH ----
@cleanUpTempFiles

# ---- PLAY ----
if play_result
    selectObject: resultSound
    Play
endif

# ---- FINAL INFO ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: " + soundName$ + "_hnr_" + presetName$
appendInfoLine: "Duration: " + fixed$(dur_out, 2) + " s"

# -----------------------------------------------------------------------------
# Drawing helpers
# -----------------------------------------------------------------------------

# Picture-window text treats _ ^ # % and \ as markup, so machine-generated
# labels (object names, model names, plan slot names) must be escaped.
procedure sanitize: .s$
    .out$ = replace$(.s$, "\", "\bs ", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
endproc

# A tick step derived as span/N prints labels like 0.6569; snap it to 1/2/5.
procedure snapStep: .span, .target
    .step = 1
    if .span > 0
        if .target > 0
            .raw = .span / .target
            .mag = 10 ^ floor(log10(.raw))
            .n = .raw / .mag
            if .n <= 1.5
                .step = .mag
            elsif .n <= 3.5
                .step = 2 * .mag
            elsif .n <= 7.5
                .step = 5 * .mag
            else
                .step = 10 * .mag
            endif
        endif
    endif
endproc

# Text left: anchors against whatever drawing frame is current, which puts each
# panel's name at a different x. Place the rail by hand at one shared offset.
procedure rail: .y1, .y2, .name$
    Font size: 7
    Select inner viewport: vizL, vizR, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure caption: .x1, .x2, .y1, .y2, .txt$
    Font size: 6
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.45}"
    Text top: "no", .txt$
    Colour: "Black"
endproc

# One palette for every operation type, used by the lane chart, the stereo
# strip and the source map so a colour means the same thing in all three.
procedure opLane: .typ$
    .y = 1.5
    .r = 0.55
    .g = 0.55
    .b = 0.70
    if .typ$ = "place"
        .y = 6.5
        .r = 0.20
        .g = 0.45
        .b = 0.78
    elsif .typ$ = "repeat"
        .y = 5.5
        .r = 0.40
        .g = 0.62
        .b = 0.85
    elsif .typ$ = "fragment"
        .y = 4.5
        .r = 0.80
        .g = 0.55
        .b = 0.20
    elsif .typ$ = "recall"
        .y = 3.5
        .r = 0.55
        .g = 0.38
        .b = 0.72
    elsif .typ$ = "braid"
        .y = 2.5
        .r = 0.20
        .g = 0.60
        .b = 0.52
    elsif .typ$ = "echo"
        .y = 1.5
        .r = 0.55
        .g = 0.55
        .b = 0.70
    elsif .typ$ = "invert"
        .y = 0.5
        .r = 0.35
        .g = 0.35
        .b = 0.45
    endif
    .line$ = "{" + fixed$(.r, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(.b, 3) + "}"
    .fill$ = "{" + fixed$(.r + (1 - .r) * 0.55, 3)
        ... + ", " + fixed$(.g + (1 - .g) * 0.55, 3)
        ... + ", " + fixed$(.b + (1 - .b) * 0.55, 3) + "}"
endproc

# Lane names carry their own count, and a lane this render never used is greyed
# rather than hidden, so the same seven rows appear for every preset.
procedure laneLabel: .y, .count, .name$
    Font size: 5.5
    Select inner viewport: vizL, vizR, yOpsA, yOpsB
    Axes: 0, axisDur, 0, 7
    if .count > 0
        Colour: "{0.25, 0.25, 0.32}"
    else
        Colour: "{0.70, 0.70, 0.75}"
    endif
    One mark left: .y, "no", "yes", "no", .name$ + "  " + string$(.count)
    Colour: "Black"
endproc
