# ============================================================
# Praat AudioTools - SympatheticResonance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Review + multichannel/analysis repair
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sympathetic Resonance -- Virtual String Physical Model
#
#   Sends the selected Sound into a Python physical model engine.
#   Python analyses the spectral content, discovers the latent
#   pitch collection embedded in the source, builds a bank of
#   virtual resonant strings tuned to that discovered scale, and
#   excites them with the source signal.
#
#   The result is the sympathetic resonance aura of the source:
#   a glowing image of the sound as if it had excited a giant
#   metallic, glassy, wooden, or airy resonant body.
#
#   Role separation:
#     Praat  -- selection, export, import, visualization.
#     Python -- all analysis, physical modelling, and rendering.
#
#   Python engine: sympathetic_resonance.py
#   Dependencies (Python): numpy  soundfile  scipy
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

pythonScript$ = pluginDir$ + "py/sympathetic_resonance.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/sympathetic_resonance.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: sympathetic_resonance.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runTag$ = "sr_" + string$(origSound) + "_" + string$(randomInteger(100000, 999999))
tempInput$   = tempDir$ + runTag$ + "_input.wav"
tempOutput$  = tempDir$ + runTag$ + "_output.wav"
tempStats$   = tempDir$ + runTag$ + "_stats.txt"
tempResCSV$  = tempDir$ + runTag$ + "_resonances.csv"
tempLog$     = tempDir$ + runTag$ + "_python.log"
probePy$     = tempDir$ + runTag$ + "_probe.py"
probeMarker$ = tempDir$ + runTag$ + "_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
tempStatsJ$    = replace_regex$(tempStats$, "\\", "/", 0)
tempResCSVJ$   = replace_regex$(tempResCSV$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
tempLogJ$     = replace_regex$(tempLog$, "\\", "/", 0)

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
    if fileReadable(tempResCSV$)
        deleteFile: tempResCSV$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Sympathetic Resonance v1.2
    optionmenu Preset: 1
        option Custom
        option Piano Frame
        option Metal Plate
        option Harp Body
        option Glass Chamber
        option Wood Box
        option Shimmer Cloud
    comment --- Custom parameters (ignored when Preset is not Custom) ---
    optionmenu Character: 1
        option Metallic
        option Glassy
        option Wooden
        option Airy
    integer N_strings 32
    comment N_strings is the maximum active resonator count.
    optionmenu Pitch_basis: 1
        option Measured peaks
        option Cloud fill
    positive Decay_ceiling_s 5.0
    positive Coupling 0.30
    comment Wet/dry  ( 0 = 100% resonance   1 = 100% dry original )
    real Wet_dry 0.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

decay_s = decay_ceiling_s

# ---- PRESETS ----
if preset = 2
    pitch_basis = 1
    character = 1
    n_strings = 48
    decay_s   = 8.0
    coupling  = 0.35
    wet_dry   = 0.10
elsif preset = 3
    pitch_basis = 1
    character = 1
    n_strings = 64
    decay_s   = 14.0
    coupling  = 0.50
    wet_dry   = 0.0
elsif preset = 4
    pitch_basis = 1
    character = 4
    n_strings = 32
    decay_s   = 4.0
    coupling  = 0.20
    wet_dry   = 0.15
elsif preset = 5
    pitch_basis = 1
    character = 2
    n_strings = 64
    decay_s   = 20.0
    coupling  = 0.60
    wet_dry   = 0.0
elsif preset = 6
    pitch_basis = 1
    character = 3
    n_strings = 24
    decay_s   = 1.8
    coupling  = 0.40
    wet_dry   = 0.25
elsif preset = 7
    pitch_basis = 2
    character = 4
    n_strings = 56
    decay_s   = 9.0
    coupling  = 0.70
    wet_dry   = 0.0
endif

# ---- PRESET NAME ----
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Piano Frame"
elsif preset = 3
    presetName$ = "Metal Plate"
elsif preset = 4
    presetName$ = "Harp Body"
elsif preset = 5
    presetName$ = "Glass Chamber"
elsif preset = 6
    presetName$ = "Wood Box"
else
    presetName$ = "Shimmer Cloud"
endif

# ---- CHARACTER STRING ----
if character = 1
    charStr$ = "metallic"
elsif character = 2
    charStr$ = "glassy"
elsif character = 3
    charStr$ = "wooden"
else
    charStr$ = "airy"
endif

if pitch_basis = 2
    pitchMode$ = "cloud"
    pitchModeLabel$ = "Cloud fill"
else
    pitchMode$ = "measured"
    pitchModeLabel$ = "Measured peaks"
endif

# ---- CLAMP PARAMETERS ----
if n_strings < 4
    n_strings = 4
endif
if n_strings > 96
    n_strings = 96
endif
if decay_s < 0.1
    decay_s = 0.1
endif
if decay_s > 60
    decay_s = 60
endif
if coupling < 0
    coupling = 0
endif
if coupling > 2
    coupling = 2
endif
if wet_dry < 0
    wet_dry = 0
endif
if wet_dry > 1
    wet_dry = 1
endif

# ---- BASIC SOUND INFO ----
selectObject: origSound
totalDur  = Get total duration
origSR    = Get sampling frequency
nChannels = Get number of channels
analysisChannel = 1
analysisRms = -1
if nChannels > 1
    for iCh from 1 to nChannels
        selectObject: origSound
        chProbe = Extract one channel: iCh
        chRms = Get root-mean-square: 0, 0
        if chRms > analysisRms
            analysisRms = chRms
            analysisChannel = iCh
        endif
        removeObject: chProbe
    endfor
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Sympathetic Resonance v1.2 ==="
appendInfoLine: "Source:    ", origName$
appendInfoLine: "Preset:    ", presetName$
appendInfoLine: "Character: ", charStr$
appendInfoLine: "Max resonators: ", n_strings
appendInfoLine: "Pitch basis:    ", pitchModeLabel$
appendInfoLine: "Decay ceiling: ", fixed$(decay_s, 2), " s"
appendInfoLine: "Coupling:  ", fixed$(coupling, 3)
appendInfoLine: "Wet/dry:   ", fixed$(wet_dry, 3)
appendInfoLine: "Duration:  ", fixed$(totalDur, 2), " s  |  SR: ", origSR, " Hz  |  analysis ch", analysisChannel
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/4] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

pythonCmd$ = ""
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

# ============================================================
# Stage 1 -- Export WAV
# ============================================================
appendInfoLine: "[1/4] Exporting WAV..."

selectObject: origSound
Save as 32-bit WAV file: tempInput$

# ============================================================
# Stage 2 -- Run Python engine
# ============================================================
appendInfoLine: "[2/4] Running sympathetic resonance engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " --input """       + tempInputJ$  + """"
    ... + " --output """      + tempOutputJ$ + """"
    ... + " --stats """       + tempStatsJ$  + """"
    ... + " --resonances """  + tempResCSVJ$ + """"
    ... + " --character "     + charStr$
    ... + " --n_strings "     + string$(n_strings)
    ... + " --decay_s "       + fixed$(decay_s, 3)
    ... + " --coupling "      + fixed$(coupling, 4)
    ... + " --wet_dry "       + fixed$(wet_dry, 4)
    ... + " --pitch_mode "    + pitchMode$

runSystem_nocheck: pythonCall$ + " > """ + tempLogJ$ + """ 2>&1"

if not fileReadable(tempOutput$)
    err$ = "Python engine failed -- output WAV not found."
    if fileReadable(tempLog$)
        err$ = err$ + newline$ + newline$ + readFile$(tempLog$)
    endif
    @cleanUpTempFiles
    exitScript: err$
endif

appendInfoLine: "  Engine complete."

# ============================================================
# Stage 3 -- Import result and read stats
# ============================================================
appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
if preset = 1
    outName$ = "SR_" + origName$ + "_" + charStr$
else
    outName$ = "SR_" + origName$ + "_" + presetName$
endif
Rename: outName$
resultSound = selected("Sound")

selectObject: resultSound
outDur = Get total duration

# Read stats
statStrings$  = "?"
statFlatness$ = "?"
statScale$    = "?"
statBPM$      = "?"
statPitches$  = "?"
statBaseCount$ = "?"
statEffT60$ = "?"
statTail$ = "?"
statFlatFrames$ = "?"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "n_strings="
    statStrings$ = parseStatLine.result$
    @parseStatLine: statsText$, "spectral_flatness="
    statFlatness$ = parseStatLine.result$
    @parseStatLine: statsText$, "top_pitches="
    statPitches$ = parseStatLine.result$
    @parseStatLine: statsText$, "base_pitch_count="
    statBaseCount$ = parseStatLine.result$
    @parseStatLine: statsText$, "effective_t60_max_s="
    statEffT60$ = parseStatLine.result$
    @parseStatLine: statsText$, "tail_s="
    statTail$ = parseStatLine.result$
    @parseStatLine: statsText$, "flatness_active_frames="
    statFlatFrames$ = parseStatLine.result$
endif

# Read resonances table for visualization
hasResTable = 0
if fileReadable(tempResCSV$)
    resTable    = Read Table from comma-separated file: tempResCSV$
    nStrViz     = Get number of rows
    hasResTable = 1
endif

appendInfoLine: "  Strings active: ", statStrings$
appendInfoLine: "  Spectral flatness: ", statFlatness$
appendInfoLine: "  Base pitches: ", statBaseCount$, "  |  active resonators: ", statStrings$
appendInfoLine: "  Effective max T60: ", statEffT60$, " s  |  rendered tail: ", statTail$, " s"

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[4/4] Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Sympathetic Resonance##"
    Font size: 8
    Colour: "{0.38, 0.38, 0.52}"
    Text: 0.5, "centre", -0.8, "half",
        ... origName$ + "  |  " + charStr$
        ... + "  |  " + pitchModeLabel$ + "  |  resonators: " + statStrings$
        ... + "  |  decay: " + fixed$(decay_s, 1) + " s"
        ... + "  |  flatness: " + statFlatness$

    # Representative real channels for comparable waveform/spectrogram panels.
    selectObject: origSound
    if nChannels > 1
        vizOrig = Extract one channel: analysisChannel
    else
        Copy: "sr_viz_orig"
        vizOrig = selected("Sound")
    endif

    selectObject: resultSound
    outChannels = Get number of channels
    bestOutChannel = 1
    bestOutRms = -1
    for iCh from 1 to outChannels
        selectObject: resultSound
        outProbe = Extract one channel: iCh
        outRms = Get root-mean-square: 0, 0
        if outRms > bestOutRms
            bestOutRms = outRms
            bestOutChannel = iCh
        endif
        removeObject: outProbe
    endfor
    selectObject: resultSound
    if outChannels > 1
        vizOut = Extract one channel: bestOutChannel
    else
        Copy: "sr_viz_out"
        vizOut = selected("Sound")
    endif
    selectObject: vizOrig
    peakOrig = Get absolute extremum: 0, 0, "none"
    selectObject: vizOut
    peakOut = Get absolute extremum: 0, 0, "none"
    wavePeak = 1.05 * max(peakOrig, peakOut)
    if wavePeak < 0.000001
        wavePeak = 1
    endif
    specCeil = min(8000, origSR / 2)

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    selectObject: vizOrig
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original ch" + string$(analysisChannel)
    Text top: "no", fixed$(totalDur, 2) + " s"

    # === Result waveform ===
    Select outer viewport: 0, 8, 1.50, 2.40
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: vizOut
    Colour: "{0.20, 0.62, 0.72}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Resonance ch" + string$(bestOutChannel)
    Text bottom: "yes", "Time (s)"

    # === Resonant string bank ===
    Select outer viewport: 0, 8, 2.50, 4.30
    Select inner viewport: 0.6, 7.7, 2.58, 4.22

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.04, 0.04, 0.08}", 0, 1, 0, 1

    if hasResTable = 1
        selectObject: resTable

        # Character colour for strings
        if character = 1
            strR = 0.92
            strG = 0.74
            strB = 0.18
        elsif character = 2
            strR = 0.35
            strG = 0.85
            strB = 0.97
        elsif character = 3
            strR = 0.65
            strG = 0.40
            strB = 0.14
        else
            strR = 0.58
            strG = 0.48
            strB = 0.88
        endif

        colStr$ = "{" + fixed$(strR, 2) + "," + fixed$(strG, 2) + "," + fixed$(strB, 2) + "}"

        for iStr from 1 to nStrViz
            selectObject: resTable
            fHz = Get value: iStr, "freq_hz"
            gn  = Get value: iStr, "gain"
            if fHz > 20 and fHz < 20000 and gn > 0
                xPos = ln(fHz / 20.0) / ln(20000.0 / 20.0)
                xPos = max(0.005, min(0.995, xPos))
                barH = max(0.04, min(0.92, gn))
                lw   = max(1, gn * 6)
                Line width: lw
                Colour: colStr$
                Draw line: xPos, 0.04, xPos, barH
            endif
        endfor

        Line width: 1
        Colour: "{0.55, 0.55, 0.55}"
        # Frequency reference ticks: 100 Hz, 1 kHz, 10 kHz
        x100  = ln(100.0   / 20.0) / ln(1000.0)
        x1k   = ln(1000.0  / 20.0) / ln(1000.0)
        x10k  = ln(10000.0 / 20.0) / ln(1000.0)
        Draw line: x100, 0, x100, 0.04
        Draw line: x1k,  0, x1k,  0.04
        Draw line: x10k, 0, x10k, 0.04

        removeObject: resTable
        hasResTable = 0
    endif

    Colour: "{0.55, 0.55, 0.55}"
    Draw inner box
    Font size: 7
    Colour: "{0.80, 0.80, 0.80}"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Log frequency  ( 20 Hz ... 20 kHz )"
    Text top: "no", "Resonator bank  ( bar height = relative resonator excitation gain )"

    # === Spectrogram of result ===
    Select outer viewport: 0, 8, 4.35, 5.85
    Select inner viewport: 0.6, 7.7, 4.42, 5.78

    selectObject: vizOut
    To Spectrogram: 0.010, specCeil, 0.004, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, specCeil, 100, "yes", 45, 6, 0, "no"
    removeObject: specRes

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Resonance spectrogram"

    # === Summary panel ===
    Select outer viewport: 0, 8, 5.95, 7.10
    Select inner viewport: 0.6, 7.7, 6.02, 7.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.93}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.66, "half",
        ... "Source: " + origName$ + "  |  Preset: " + presetName$ + "  |  Char: " + charStr$
        ... + "  |  " + pitchModeLabel$ + "  |  base pitches: " + statBaseCount$ + "  |  resonators: " + statStrings$
    Text: 0.02, "left", 0.45, "half",
        ... "Decay ceiling: " + fixed$(decay_s, 1) + " s"
        ... + "  |  Coupling: " + fixed$(coupling, 2)
        ... + "  |  Wet/dry: " + fixed$(wet_dry, 2)
        ... + "  |  Flatness: " + statFlatness$ + "  |  max T60: " + statEffT60$ + " s"
    Text: 0.02, "left", 0.24, "half",
        ... "Measured/synthetic base pitches (Hz): " + statPitches$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    removeObject: vizOrig, vizOut
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ============================================================
# Final Cleanup + Play
# ============================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", outName$
appendInfoLine: "Duration:  ", fixed$(outDur, 2), " s"
appendInfoLine: "Resonators: ", statStrings$
appendInfoLine: "Pitch basis: ", pitchModeLabel$ + "  |  base pitches: " + statBaseCount$
appendInfoLine: "Flatness:  ", statFlatness$
appendInfoLine: "Pitches:   ", statPitches$

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