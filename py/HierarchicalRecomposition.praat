# ============================================================
# Praat AudioTools - HierarchicalRecomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Captures Python stderr on failure
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
# Changelog v1.2:
#   - On engine failure the captured Python stderr (traceback) is now
#     shown in the error dialog instead of "check the console", which is
#     invisible when Praat runs from the GUI.
#   - Pairs with hierarchical_recomposition.py v1.1 (fallback reachable,
#     surprise-swap crash fixed, real sample rate in the planner, FFT
#     autocorrelation).
#
# Dependencies (Python):
#   pip install numpy scipy soundfile torch
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
form Hierarchical Neural Recomposition v1.2
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
    real    Density          0.5
    real    Phrase_coherence 0.5
    real    Fragmentation    0.3
    comment === Section Level ===
    real    Section_contrast 0.5
    real    Memory_strength  0.5
    real    Repetition       0.5
    comment === Rendering ===
    real    Overlap_amount   0.3
    real    Source_trace     0.85
    real    Formal_surprise  0.2
    comment === Output ===
    integer Random_seed       42
    boolean Draw_visualization 1
    boolean Play_result        1
endform

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
if density < 0
    density = 0
endif
if density > 1
    density = 1
endif
if phrase_coherence < 0
    phrase_coherence = 0
endif
if phrase_coherence > 1
    phrase_coherence = 1
endif
if section_contrast < 0
    section_contrast = 0
endif
if section_contrast > 1
    section_contrast = 1
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
if source_trace < 0
    source_trace = 0
endif
if source_trace > 1
    source_trace = 1
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
writeInfoLine:  "=== Hierarchical Neural Recomposition v1.2 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: ""
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s"
appendInfoLine: "SR:            ", sr, " Hz"
appendInfoLine: "Channels:      ", nChannels
appendInfoLine: ""
appendInfoLine: "Target duration ratio: ", target_duration
appendInfoLine: "Density:               ", density
appendInfoLine: "Phrase coherence:      ", phrase_coherence
appendInfoLine: "Section contrast:      ", section_contrast
appendInfoLine: "Memory strength:       ", memory_strength
appendInfoLine: "Repetition:            ", repetition
appendInfoLine: "Fragmentation:         ", fragmentation
appendInfoLine: "Overlap amount:        ", overlap_amount
appendInfoLine: "Source trace:          ", source_trace
appendInfoLine: "Formal surprise:       ", formal_surprise
appendInfoLine: "Seed:                  ", random_seed
appendInfoLine: ""

# ---- PYTHON DEPENDENCY VALIDATION ----
appendInfoLine: "[1/4] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile, torch; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile torch"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

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
endif

appendInfoLine: ""
appendInfoLine: "Events:     ", nEvStat$
appendInfoLine: "Phrases:    ", nPhStat$
appendInfoLine: "Sections:   ", nSecStat$
appendInfoLine: "PyTorch:    ", torchStat$
appendInfoLine: "Density:    ", densityStat$
appendInfoLine: "Brightness: ", brightStat$

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Hierarchical Neural Recomposition##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Events: " + nEvStat$ + " | Phrases: " + nPhStat$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.45
    Select inner viewport: 0.6, 7.7, 0.65, 1.40
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.35
    Select inner viewport: 0.6, 7.7, 1.55, 2.30
    selectObject: resultSound
    Colour: "{0.25, 0.55, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Recomp."
    Text bottom: "yes", "Time (s)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.45, 3.7
    Select inner viewport: 0.6, 7.7, 2.55, 3.65

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig_hnr"
        tmpOrig = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output Spectrogram ===
    Select outer viewport: 0, 8, 3.75, 5.0
    Select inner viewport: 0.6, 7.7, 3.85, 4.95

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut_hnr"
        tmpOut = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Recomposed Spectrogram"
    removeObject: specOut, tmpOut

    # === Intensity Comparison ===
    Select outer viewport: 0, 8, 5.1, 6.1
    Select inner viewport: 0.6, 7.7, 5.2, 6.0

    # Use the longer of the two for the axis
    if dur_out > dur
        axisDur = dur_out
    else
        axisDur = dur
    endif
    Axes: 0, axisDur, 30, 90
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, axisDur, 30, 90

    # Original intensity (grey)
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrigI = selected("Sound")
    else
        Copy: "tmpOrigI_hnr"
        tmpOrigI = selected("Sound")
    endif
    To Intensity: 100, 0, "yes"
    intOrig = selected("Intensity")
    selectObject: intOrig
    Colour: "{0.6, 0.6, 0.6}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOrig, tmpOrigI

    # Recomposed intensity (blue)
    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOutI = selected("Sound")
    else
        Copy: "tmpOutI_hnr"
        tmpOutI = selected("Sound")
    endif
    To Intensity: 100, 0, "yes"
    intOut = selected("Intensity")
    selectObject: intOut
    Colour: "{0.25, 0.55, 0.75}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    removeObject: intOut, tmpOutI

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, 20, "yes", "yes", "no"
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Intensity: grey=Original  blue=Recomposed"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.2, 8.0
    Select inner viewport: 0.6, 7.7, 6.3, 7.85

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.76, "half",
        ... "Preset: " + presetName$ + "  |  Events: " + nEvStat$
        ... + "  |  Phrases: " + nPhStat$ + "  |  Sections: " + nSecStat$
    Text: 0.02, "left", 0.60, "half",
        ... "Target dur ratio: " + fixed$(target_duration, 2)
        ... + "  |  In: " + fixed$(dur, 2) + "s  ->  Out: " + fixed$(dur_out, 2) + "s"
    Text: 0.02, "left", 0.44, "half",
        ... "Coherence: " + fixed$(phrase_coherence, 2)
        ... + "  |  Memory: " + fixed$(memory_strength, 2)
        ... + "  |  Contrast: " + fixed$(section_contrast, 2)
        ... + "  |  Repetition: " + fixed$(repetition, 2)
    Text: 0.02, "left", 0.28, "half",
        ... "Fragm: " + fixed$(fragmentation, 2)
        ... + "  |  Overlap: " + fixed$(overlap_amount, 2)
        ... + "  |  Source trace: " + fixed$(source_trace, 2)
        ... + "  |  Surprise: " + fixed$(formal_surprise, 2)
    Text: 0.02, "left", 0.12, "half",
        ... "RMS: " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
        ... + "  |  PyTorch: " + torchStat$
        ... + "  |  Seed: " + string$(random_seed)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

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