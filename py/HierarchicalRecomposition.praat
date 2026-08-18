# ============================================================
# Praat AudioTools - HierarchicalRecomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026) - Structural stereo spatialization + process map
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
form Hierarchical Neural Recomposition v1.3
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
writeInfoLine:  "=== Hierarchical Neural Recomposition v1.3 ==="
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
###############################################################################

if draw_visualization

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Font size: 10

    # === Title strip ===
    Select outer viewport: 0, 8, 0, 0.48
    Select inner viewport: 0.15, 7.85, 0.08, 0.44
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "{0.2, 0.2, 0.4}"
    Text: 0.5, "centre", 0.72, "half", "Hierarchical Recomposition - Process Map"
    Select outer viewport: 0, 8, 0, 0.48
    Select inner viewport: 0.15, 7.85, 0.08, 0.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", 0.24, "half", soundName$ + " | " + presetName$ + " | seed " + string$(random_seed)

    # === 1. SOURCE -> EVENT SEGMENTATION ===
    Select outer viewport: 0, 8, 0.55, 1.75
    Select inner viewport: 0.65, 7.75, 0.68, 1.65
    Axes: 0, dur, -1, 1
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, dur, -1, 1

    # phrase strips at top of waveform
    for iP from 0 to nPhraseViz - 1
        Colour: "{0.88, 0.91, 0.97}"
        Paint rectangle: "{0.88, 0.91, 0.97}", phStart_'iP', phEnd_'iP', 0.78, 0.98
    endfor

    selectObject: sound
    Colour: "{0.2, 0.4, 0.75}"
    Draw: 0, dur, -1, 1, "no", "Curve"

    # Actual detected event starts
    Select outer viewport: 0, 8, 0.55, 1.75
    Select inner viewport: 0.65, 7.75, 0.68, 1.65
    Axes: 0, dur, -1, 1
    Colour: "{0.55, 0.55, 0.62}"
    Line width: 0.7
    for iE from 0 to nEventViz - 1
        Draw line: evStart_'iE', -0.95, evStart_'iE', 0.72
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text top: "no", "1  Onset segmentation: actual event boundaries; phrase spans shown as top strips"
    Text bottom: "yes", "Source time (s)"

    # === 2. EVENT -> PHRASE HIERARCHY ===
    Select outer viewport: 0, 8, 1.82, 2.85
    Select inner viewport: 0.65, 7.75, 1.92, 2.77
    Axes: 0, dur, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, dur, 0, 1

    # event blocks: these are actual source-time spans
    for iE from 0 to nEventViz - 1
        Colour: "{0.35, 0.55, 0.82}"
        Paint rectangle: "{0.82, 0.88, 0.96}", evStart_'iE', evEnd_'iE', 0.66, 0.84
        Draw rectangle: evStart_'iE', evEnd_'iE', 0.66, 0.84
    endfor

    # phrase blocks: actual grouping returned by group_into_phrases
    for iP from 0 to nPhraseViz - 1
        Colour: "{0.35, 0.35, 0.45}"
        Paint rectangle: "{0.88, 0.88, 0.91}", phStart_'iP', phEnd_'iP', 0.34, 0.54
        Draw rectangle: phStart_'iP', phEnd_'iP', 0.34, 0.54
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "2  Hierarchy: events are grouped into phrases by feature similarity + coherence"
    Text bottom: "yes", "Source time (s)"

    # Free text can change Praat Picture viewport state; reselect before each label.
    Select outer viewport: 0, 8, 1.82, 2.85
    Select inner viewport: 0.65, 7.75, 1.92, 2.77
    Axes: 0, dur, 0, 1
    Text: 0.01 * dur, "left", 0.75, "half", "Events"
    Select outer viewport: 0, 8, 1.82, 2.85
    Select inner viewport: 0.65, 7.75, 1.92, 2.77
    Axes: 0, dur, 0, 1
    Text: 0.01 * dur, "left", 0.44, "half", "Phrases"
    if nPhraseViz <= 14
        for iP from 0 to nPhraseViz - 1
            Select outer viewport: 0, 8, 1.82, 2.85
            Select inner viewport: 0.65, 7.75, 1.92, 2.77
            Axes: 0, dur, 0, 1
            Text: (phStart_'iP' + phEnd_'iP') / 2, "centre", 0.44, "half", "P" + string$(phIndex_'iP' + 1)
        endfor
    endif

    # === 3. SEEDED NEURAL PLAN GENERATOR ===
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.965, 0.97, 0.985}", 0, 1, 0, 1

    # five explicit processing stages
    Colour: "{0.2, 0.4, 0.75}"
    Paint rectangle: "{0.88, 0.92, 0.98}", 0.02, 0.17, 0.52, 0.78
    Draw rectangle: 0.02, 0.17, 0.52, 0.78
    Paint rectangle: "{0.88, 0.92, 0.98}", 0.22, 0.38, 0.52, 0.78
    Draw rectangle: 0.22, 0.38, 0.52, 0.78
    Paint rectangle: "{0.88, 0.92, 0.98}", 0.43, 0.61, 0.52, 0.78
    Draw rectangle: 0.43, 0.61, 0.52, 0.78
    Paint rectangle: "{0.88, 0.92, 0.98}", 0.66, 0.79, 0.52, 0.78
    Draw rectangle: 0.66, 0.79, 0.52, 0.78
    Paint rectangle: "{0.88, 0.92, 0.98}", 0.84, 0.98, 0.52, 0.78
    Draw rectangle: 0.84, 0.98, 0.52, 0.78

    Colour: "{0.25, 0.25, 0.35}"
    Draw arrow: 0.17, 0.65, 0.22, 0.65
    Draw arrow: 0.38, 0.65, 0.43, 0.65
    Draw arrow: 0.61, 0.65, 0.66, 0.65
    Draw arrow: 0.79, 0.65, 0.84, 0.65

    # Draw the frame before free text; then restore inner viewport for each label.
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 6
    Colour: "Black"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.095, "centre", 0.65, "half", "7-D event features"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.30, "centre", 0.65, "half", "Event Encoder"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.52, "centre", 0.65, "half", "Phrase Transformer"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.725, "centre", 0.65, "half", "Bi-GRU"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.91, "centre", 0.65, "half", "16-D plan"

    Font size: 7
    Colour: "{0.2, 0.2, 0.35}"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.91, "half", "3  Seeded plan generator (untrained weights; deterministic for this seed)"
    Font size: 6
    Colour: "{0.35, 0.35, 0.42}"
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.31, "half",
        ... "Actual plan means: repeat " + fixed$(planRep, 2)
        ... + " | fragment " + fixed$(planFrag, 2)
        ... + " | overlap " + fixed$(planOverlap, 2)
    Select outer viewport: 0, 8, 2.92, 4.12
    Select inner viewport: 0.45, 7.8, 3.02, 4.04
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.15, "half",
        ... "stretch " + fixed$(planStretch, 2)
        ... + " | memory " + fixed$(planMemory, 2)
        ... + " | braid " + fixed$(planBraid, 2)

    # === 4. PLAN -> ACTUAL SCHEDULED OPERATIONS ===
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, dur_out, 0, 7

    # lanes: place 6, repeat 5, fragment 4, recall 3, braid 2, echo/invert 1
    for iO from 0 to nOpViz - 1
        typ$ = opType_'iO'$
        oy = 1.0
        fill$ = "{0.70, 0.70, 0.75}"
        if typ$ = "place"
            oy = 6.0
            fill$ = "{0.45, 0.65, 0.88}"
        elsif typ$ = "repeat"
            oy = 5.0
            fill$ = "{0.62, 0.74, 0.88}"
        elsif typ$ = "fragment"
            oy = 4.0
            fill$ = "{0.84, 0.68, 0.45}"
        elsif typ$ = "recall"
            oy = 3.0
            fill$ = "{0.68, 0.58, 0.78}"
        elsif typ$ = "braid"
            oy = 2.0
            fill$ = "{0.50, 0.72, 0.68}"
        elsif typ$ = "echo"
            oy = 1.0
            fill$ = "{0.72, 0.72, 0.80}"
        elsif typ$ = "invert"
            oy = 1.0
            fill$ = "{0.55, 0.55, 0.65}"
        endif
        if opEnd_'iO' > opStart_'iO'
            Paint rectangle: fill$, opStart_'iO', opEnd_'iO', oy - 0.27, oy + 0.27
            Colour: "{0.35, 0.35, 0.42}"
            Draw rectangle: opStart_'iO', opEnd_'iO', oy - 0.27, oy + 0.27
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "4  Actual operations scheduled for this render; stereo field at bottom"
    Text bottom: "yes", "Output time (s)"

    # Lane labels after all data-world painting; restore viewport before each Text.
    Font size: 6
    Colour: "{0.35, 0.35, 0.42}"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 6.0, "half", "place"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 5.0, "half", "repeat"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 4.0, "half", "fragment"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 3.0, "half", "recall"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 2.0, "half", "braid"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 1.0, "half", "echo / invert"

    # Actual stereo field inside the unused bottom of the operations panel.
    # pan -1 -> L (0.12), 0 -> C (0.36), +1 -> R (0.60).
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Colour: "{0.82, 0.82, 0.86}"
    Line width: 0.6
    Draw line: 0, 0.12, dur_out, 0.12
    Draw line: 0, 0.36, dur_out, 0.36
    Draw line: 0, 0.60, dur_out, 0.60
    for iO from 0 to nOpViz - 1
        panY = 0.36 + 0.24 * opPan_'iO'
        Colour: "{0.25, 0.45, 0.72}"
        Line width: 1.4
        if opEnd_'iO' > opStart_'iO'
            Draw line: opStart_'iO', panY, opEnd_'iO', panY
        endif
    endfor
    Line width: 1
    Colour: "{0.35, 0.35, 0.42}"
    Font size: 5
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 0.12, "half", "L"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 0.36, "half", "C"
    Select outer viewport: 0, 8, 4.2, 5.78
    Select inner viewport: 0.9, 7.75, 4.33, 5.67
    Axes: 0, dur_out, 0, 7
    Text: 0.005 * dur_out, "left", 0.60, "half", "R"

    # === 5. MEASURED ACOUSTIC RESULT — SAME AXES ===
    Select outer viewport: 0, 8, 5.86, 7.08
    Select inner viewport: 0.65, 7.75, 5.98, 6.98
    if dur_out > dur
        axisDur = dur_out
    else
        axisDur = dur
    endif
    Axes: 0, axisDur, -1, 1
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, axisDur, -1, 1

    selectObject: sound
    Colour: "{0.62, 0.62, 0.65}"
    Line width: 1
    Draw: 0, axisDur, -1, 1, "no", "Curve"
    Select outer viewport: 0, 8, 5.86, 7.08
    Select inner viewport: 0.65, 7.75, 5.98, 6.98
    Axes: 0, axisDur, -1, 1
    selectObject: resultSound
    Colour: "{0.2, 0.4, 0.75}"
    Line width: 1.5
    Draw: 0, axisDur, -1, 1, "no", "Curve"

    Select outer viewport: 0, 8, 5.86, 7.08
    Select inner viewport: 0.65, 7.75, 5.98, 6.98
    Axes: 0, axisDur, -1, 1
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "5  Same-scale waveform: grey source / blue recomposition | " + spatialMode$
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"

    # === Bottom QC / summary bar ===
    Select outer viewport: 0, 8, 7.17, 8.0
    Select inner viewport: 0.35, 7.75, 7.25, 7.9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.95, 0.97}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 6
    Select outer viewport: 0, 8, 7.17, 8.0
    Select inner viewport: 0.35, 7.75, 7.25, 7.9
    Axes: 0, 1, 0, 1
    Text: 0.02, "left", 0.72, "half",
        ... "Events " + nEvStat$ + " -> Phrases " + nPhStat$ + " | Ops " + string$(nOpsTotal)
        ... + " [place " + string$(nOpPlace) + ", repeat " + string$(nOpRepeat)
        ... + ", fragment " + string$(nOpFragment) + ", recall " + string$(nOpRecall) + "]"
    Select outer viewport: 0, 8, 7.17, 8.0
    Select inner viewport: 0.35, 7.75, 7.25, 7.9
    Axes: 0, 1, 0, 1
    Text: 0.02, "left", 0.40, "half",
        ... "Secondary ops: braid " + string$(nOpBraid) + " | echo " + string$(nOpEcho)
        ... + " | invert " + string$(nOpInvert) + " | model " + neuralModel$
        ... + " | analysis " + monoStrategy$
    Select outer viewport: 0, 8, 7.17, 8.0
    Select inner viewport: 0.35, 7.75, 7.25, 7.9
    Axes: 0, 1, 0, 1
    Text: 0.02, "left", 0.12, "half",
        ... "Duration " + fixed$(dur, 2) + "s -> " + fixed$(dur_out, 2) + "s"
        ... + " | RMS " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
        ... + " | " + string$(outputChannels) + "ch " + spatialMode$
        ... + " | pan " + fixed$(panMin, 2) + ".." + fixed$(panMax, 2)

    Font size: 10
    Colour: "Black"

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