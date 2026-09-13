# ============================================================
# Praat AudioTools - HPSS_Phase_Vocoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4 (2026) — linked multichannel WSOLA + process-narrative figure
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   High-quality time-stretching via HPSS + phase vocoder.
#   Harmonic content is stretched with the phase vocoder.
#   Percussive/transient content is WSOLA time-stretched — pitch and
#   attacks are preserved, no metallic smearing and no detuning.
#
#   Python engine: stretch.py (numpy/scipy/soundfile, no librosa)
#
# Changelog v2.4:
#   - The figure now shows the separation itself rather than a diagram of it:
#     an HPSS decision profile over time, what the margin exponent did to the
#     mask, the WSOLA similarity search's per-frame deviation and correlation,
#     and the two separated layers as spectrograms. All four spectrograms share
#     one time axis, so the stretch reads as width.
#   - Fixed: no panel drew axis numbers; the stretched panel's axis label was
#     painted over by the next band's caption; per-panel spectrogram autoscaling
#     made the input and result look the same length.
#
# Changelog v2.3:
#   - Multichannel percussive branch uses linked WSOLA alignment to preserve
#     inter-channel timing; mono rendering remains on the established path.
#   - Very short WSOLA inputs are handled safely by the Python engine.
#   - Python interchange WAV is 32-bit float (no extra PCM16 quantisation).
#   - Visualization now shows the processing mechanism and uses a shared
#     time/amplitude scale for the original/stretched waveforms.
#
# Changelog v2.2:
#   - Engine (stretch.py): percussive band now uses WSOLA instead of
#     resampling. Resampling stretched by changing playback rate, which
#     slowed attacks and pitched percussion down by the stretch factor;
#     WSOLA changes duration only. n_fft is also forced even.
#
# Dependencies (Python):
#   pip install numpy scipy soundfile
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
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/stretch.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/stretch.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: stretch.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_hpss_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_hpss_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_hpss_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_hpss_probe.ok"
tempHarm$    = temporaryDirectory$ + "/temp_hpss_harmonic.wav"
tempPerc$    = temporaryDirectory$ + "/temp_hpss_percussive.wav"
tempProfile$ = temporaryDirectory$ + "/temp_hpss_profile.csv"
tempHist$    = temporaryDirectory$ + "/temp_hpss_maskhist.csv"
tempWsola$   = temporaryDirectory$ + "/temp_hpss_wsola.csv"

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
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(tempHarm$)
        deleteFile: tempHarm$
    endif
    if fileReadable(tempPerc$)
        deleteFile: tempPerc$
    endif
    if fileReadable(tempProfile$)
        deleteFile: tempProfile$
    endif
    if fileReadable(tempHist$)
        deleteFile: tempHist$
    endif
    if fileReadable(tempWsola$)
        deleteFile: tempWsola$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form HPSS Phase Vocoder v2.4
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Gentle (x1.3)
        option Medium (x1.5)
        option Extreme (x2.0)
        option Half speed (x2.0, large window)
        option Compress (x0.75)
        option Fast preview (small window)
    comment === Parameters ===
    positive Stretch_factor 1.5
    integer  FFT_size 4096
    real     HPSS_margin 3.0
    comment === Output ===
    boolean  Draw_visualization 1
    boolean  Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    stretch_factor = 1.3
    fFT_size       = 4096
    hPSS_margin    = 3.0
    presetName$    = "Gentle"
elsif preset = 3
    stretch_factor = 1.5
    fFT_size       = 4096
    hPSS_margin    = 3.0
    presetName$    = "Medium"
elsif preset = 4
    stretch_factor = 2.0
    fFT_size       = 4096
    hPSS_margin    = 3.0
    presetName$    = "Extreme"
elsif preset = 5
    stretch_factor = 2.0
    fFT_size       = 8192
    hPSS_margin    = 4.0
    presetName$    = "HalfSpeed"
elsif preset = 6
    stretch_factor = 0.75
    fFT_size       = 4096
    hPSS_margin    = 3.0
    presetName$    = "Compress"
elsif preset = 7
    stretch_factor = 1.5
    fFT_size       = 2048
    hPSS_margin    = 2.5
    presetName$    = "FastPreview"
else
    presetName$ = "Custom"
endif

# ---- CLAMP ----
if stretch_factor < 0.1
    stretch_factor = 0.1
endif
if stretch_factor > 10
    stretch_factor = 10
endif
if fFT_size < 256
    fFT_size = 256
endif
if fFT_size > 8192
    fFT_size = 8192
endif
if hPSS_margin < 1
    hPSS_margin = 1
endif
if hPSS_margin > 10
    hPSS_margin = 10
endif

# ---- CAPTURE STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_in    = Get root-mean-square: 0, 0

# ---- INFO ----
clearinfo
writeInfoLine:  "=== HPSS Phase Vocoder v2.4 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Ch: ", nChannels
appendInfoLine: "Stretch:  x", fixed$(stretch_factor, 3)
appendInfoLine: "FFT:      ", fFT_size, " | Margin: ", fixed$(hPSS_margin, 1)
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Export
# ===========================================================================
appendInfoLine: "[1/4] Exporting audio..."
selectObject: sound
Save as WAV file: tempInput$

# ===========================================================================
# Stage 2 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[2/4] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 3 — Run Python
# ===========================================================================
appendInfoLine: "[3/4] Running HPSS + Phase Vocoder..."

# Ask the installed engine what it supports before asking it for anything.
engineText$ = readFile$(pythonScript$)
engineHasExports = 0
if index(engineText$, "--wsola") > 0
    if index(engineText$, "--profile") > 0
        engineHasExports = 1
    endif
endif
if engineHasExports = 0
    appendInfoLine: "  Engine predates v2.4: process exports unavailable, drawing the compact figure."
endif

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + fixed$(stretch_factor, 6)
    ... + " " + string$(fFT_size)
    ... + " " + fixed$(hPSS_margin, 2)

if engineHasExports
    pyCmd$ = pyCmd$ + " --harmonic """ + tempHarm$ + """"
        ... + " --percussive """ + tempPerc$ + """"
        ... + " --profile """ + tempProfile$ + """"
        ... + " --maskhist """ + tempHist$ + """"
        ... + " --wsola """ + tempWsola$ + """"
endif

runSystem_nocheck: pyCmd$

# ---- Verify output ----
if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python engine failed — output file not created." + newline$ + "Check terminal for error messages."
endif

# ===========================================================================
# Stage 4 — Import + stats
# ===========================================================================
appendInfoLine: "[4/4] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_hpss_x" + fixed$(stretch_factor, 2)
resultSound = selected("Sound")
durOut  = Get total duration
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "  Output: ", fixed$(durOut, 2), " s"

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

harmonicRmsStat$ = "?"
percRmsStat$     = "?"
hpRatioStat$     = "?"
outPeakStat$     = "?"
linkedWsolaStat$  = "?"
maskMeanStat$      = "?"
maskDecisiveStat$  = "?"
harmEnergyStat$    = "?"
wsolaFramesStat$   = "?"
wsolaWindowStat$   = "?"
wsolaSynStat$      = "?"
wsolaAnaStat$      = "?"
wsolaSeekStat$     = "?"
wsolaDevStat$      = "?"
wsolaMaxDevStat$   = "?"
wsolaScoreStat$    = "?"
hopSecViz = (fFT_size / 8) / sr

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "harmonic_rms="
    harmonicRmsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "percussive_rms="
    percRmsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "hp_ratio="
    hpRatioStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_peak="
    outPeakStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "linked_wsola="
    linkedWsolaStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mask_mean="
    maskMeanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mask_decisive_share="
    maskDecisiveStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "harmonic_energy_share="
    harmEnergyStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_frames="
    wsolaFramesStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_window="
    wsolaWindowStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_syn_hop="
    wsolaSynStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_ana_hop="
    wsolaAnaStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_seek="
    wsolaSeekStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_mean_abs_dev_ms="
    wsolaDevStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_max_abs_dev_ms="
    wsolaMaxDevStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "wsola_mean_score="
    wsolaScoreStat$ = parseStatLine.result$
endif

# Shared comparison scale for the visualization.  The two waveform panels
# intentionally use the same X/Y axes so duration and level differences are
# visually meaningful rather than independently autoscaled.
selectObject: sound
peakVizIn = Get absolute extremum: 0, 0, "None"
selectObject: resultSound
peakVizOut = Get absolute extremum: 0, 0, "None"
peakViz = max(peakVizIn, peakVizOut)
if peakViz < 0.001
    peakViz = 0.001
endif
maxDurViz = max(dur, durOut)

###############################################################################
# VISUALIZATION
#
# Read top to bottom:
#   1. original and stretched waveforms on one shared time and amplitude scale;
#   2. where HPSS decided the material was harmonic and where percussive;
#   3. how hard that decision was (what the margin exponent actually did), and
#      how far the WSOLA similarity search had to move each percussive frame
#      away from its nominal position to keep attacks intact;
#   4. the four spectrograms - input, the two separated layers as they were
#      stretched, and their sum - all on the same time axis, so the stretch is
#      visible as width rather than hidden by per-panel autoscaling.
# Panels 2-3 and the layer spectrograms need the process exports written by
# stretch.py v2.4. With an older engine the script draws the compact figure.
###############################################################################

if draw_visualization
    vizL = 0.60
    vizR = 7.70
    railX = -0.040

    colHarm$ = "{0.25, 0.55, 0.75}"
    colPerc$ = "{0.75, 0.42, 0.22}"
    colGrey$ = "{0.50, 0.50, 0.50}"
    colRule$ = "{0.72, 0.72, 0.78}"

    # --- process tables ------------------------------------------------------
    hasProfile = 0
    nProf = 0
    if fileReadable(tempProfile$)
        profTbl = Read Table from comma-separated file: tempProfile$
        nProf = Get number of rows
        if nProf >= 2
            hasProfile = 1
        else
            removeObject: profTbl
        endif
    endif

    hasHist = 0
    nHist = 0
    if fileReadable(tempHist$)
        histTbl = Read Table from comma-separated file: tempHist$
        nHist = Get number of rows
        if nHist >= 2
            hasHist = 1
            histMax = Get maximum: "share"
        else
            removeObject: histTbl
        endif
    endif

    hasWsola = 0
    nWsola = 0
    if fileReadable(tempWsola$)
        wsolaTbl = Read Table from comma-separated file: tempWsola$
        nWsola = Get number of rows
        if nWsola >= 2
            hasWsola = 1
            devLo = Get minimum: "deviation_ms"
            devHi = Get maximum: "deviation_ms"
        else
            removeObject: wsolaTbl
        endif
    endif

    hasLayers = 0
    if fileReadable(tempHarm$)
        if fileReadable(tempPerc$)
            hasLayers = 1
        endif
    endif

    fullFigure = 0
    if hasProfile = 1 and hasLayers = 1
        fullFigure = 1
    endif

    # --- layout --------------------------------------------------------------
    if fullFigure
        canvasH = 10.50
        yAa = 0.78
        yAb = 1.42
        yBa = 1.44
        yBb = 2.08
        yCa = 2.10
        yCb = 2.80
        yDa = 3.45
        yDb = 4.65
        ySp1a = 5.30
        ySp1b = 6.20
        ySp2a = 6.22
        ySp2b = 7.12
        ySp3a = 7.14
        ySp3b = 8.04
        ySp4a = 8.06
        ySp4b = 8.96
        yHa = 9.50
        yHb = 10.35
    else
        canvasH = 6.85
        yAa = 0.78
        yAb = 1.52
        yBa = 1.54
        yBb = 2.28
        ySp1a = 2.58
        ySp1b = 3.73
        ySp4a = 3.75
        ySp4b = 4.90
        yHa = 5.45
        yHb = 6.68
    endif

    @snapStep: maxDurViz, 8
    snapT = snapStep.step

    Erase all
    Colour: "Black"
    Line width: 1
    Solid line

    # --- title ---------------------------------------------------------------
    @sanitize: soundName$
    hdrName$ = sanitize.out$
    Font size: 13
    Select inner viewport: vizL, vizR, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##HPSS Phase Vocoder##"
    Font size: 7
    Select inner viewport: vizL, vizR, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", 0.24, "half", hdrName$ + "   |   " + presetName$
        ... + "   |   x" + fixed$(stretch_factor, 2)
        ... + "   |   FFT " + string$(fFT_size) + ", hop " + string$(round(fFT_size / 8))
        ... + "   |   margin " + fixed$(hPSS_margin, 1)
    Colour: "Black"

    # --- A: original waveform ------------------------------------------------
    @caption: vizL, vizR, yAa, yAb, "Input and result on one shared time and amplitude scale - the stretch is the change in width"
    Font size: 7
    Select inner viewport: vizL, vizR, yAa, yAb
    selectObject: sound
    Colour: colGrey$
    Draw: 0, maxDurViz, -peakViz, peakViz, "no", "Curve"
    Colour: "Black"
    Select inner viewport: vizL, vizR, yAa, yAb
    Axes: 0, maxDurViz, -peakViz, peakViz
    Draw inner box
    Marks bottom every: 1, snapT, "no", "yes", "no"
    @rail: yAa, yAb, "Original"

    # --- B: stretched waveform -----------------------------------------------
    Font size: 7
    Select inner viewport: vizL, vizR, yBa, yBb
    selectObject: resultSound
    Colour: colHarm$
    Draw: 0, maxDurViz, -peakViz, peakViz, "no", "Curve"
    Colour: "Black"
    Select inner viewport: vizL, vizR, yBa, yBb
    Axes: 0, maxDurViz, -peakViz, peakViz
    Draw inner box
    Marks bottom every: 1, snapT, "no", "yes", "no"
    @rail: yBa, yBb, "Stretched"

    if fullFigure
        # --- C: HPSS separation profile over input time ----------------------
        Font size: 7
        Select inner viewport: vizL, vizR, yCa, yCb
        Axes: 0, maxDurViz, 0, 1
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, maxDurViz, 0, 1

        # One full-height column per STFT frame, split at that frame's harmonic
        # share of spectral energy: blue on top is what goes to the phase
        # vocoder, orange underneath is what goes to WSOLA. Pale columns are
        # low-level frames, where the split hardly matters.
        selectObject: profTbl
        for i from 1 to nProf
            pShare = Get value: i, "harmonic_share"
            pLevel = Get value: i, "level"
            pT0 = Get value: i, "time_s"
            pT1 = maxDurViz
            if i < nProf
                iNext = i + 1
                pT1 = Get value: iNext, "time_s"
            else
                pT1 = min(maxDurViz, pT0 + 1.5 * hopSecViz)
            endif
            # Paint rectangle does not clip, and the last STFT frames can sit
            # past the end of the audio, so clamp before drawing.
            pT0 = max(0, min(maxDurViz, pT0))
            pT1 = max(0, min(maxDurViz, pT1))
            if pT1 > pT0
                fade = 0.15 + 0.85 * min(1, max(0, pLevel * 3))
                harmCol$ = "{" + fixed$(0.25 + 0.75 * (1 - fade), 3)
                    ... + ", " + fixed$(0.55 + 0.45 * (1 - fade), 3)
                    ... + ", " + fixed$(0.75 + 0.25 * (1 - fade), 3) + "}"
                percCol$ = "{" + fixed$(0.75 + 0.25 * (1 - fade), 3)
                    ... + ", " + fixed$(0.42 + 0.58 * (1 - fade), 3)
                    ... + ", " + fixed$(0.22 + 0.78 * (1 - fade), 3) + "}"
                if pShare > 0
                    Paint rectangle: harmCol$, pT0, pT1, 1 - pShare, 1
                endif
                if pShare < 1
                    Paint rectangle: percCol$, pT0, pT1, 0, 1 - pShare
                endif
            endif
        endfor

        Select inner viewport: vizL, vizR, yCa, yCb
        Axes: 0, maxDurViz, 0, 1
        Dotted line
        Colour: colRule$
        Draw line: 0, 0.5, maxDurViz, 0.5
        Solid line
        Colour: "Black"
        Select inner viewport: vizL, vizR, yCa, yCb
        Axes: 0, maxDurViz, 0, 1
        Draw inner box
        One mark left: 0.5, "yes", "yes", "no", ""
        One mark left: 0.12, "no", "yes", "no", "P"
        One mark left: 0.88, "no", "yes", "no", "H"
        Marks bottom every: 1, snapT, "yes", "yes", "no"
        Text bottom: "yes", "Time (s)  -  input occupies 0 to " + fixed$(dur, 2) + " s, result 0 to " + fixed$(durOut, 2) + " s"
        @rail: yCa, yCb, "H share"

        # --- D left: mask hardness -------------------------------------------
        @caption: vizL, 3.90, yDa, yDb, "What the margin did - share of spectral energy by mask value (log scale)"
        # Linear would show only the two end bins; the whole point is whether
        # the exponent left anything undecided in the middle.
        histFloor = -4
        Font size: 7
        Select inner viewport: vizL, 3.90, yDa, yDb
        Axes: 0, 1, histFloor, 0.15
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, 1, histFloor, 0.15
        if hasHist
            selectObject: histTbl
            for i from 1 to nHist
                hLo = Get value: i, "lo"
                hHi = Get value: i, "hi"
                hSh = Get value: i, "share"
                hMid = 0.5 * (hLo + hHi)
                if hMid >= 0.5
                    barCol$ = colHarm$
                else
                    barCol$ = colPerc$
                endif
                if hSh > 0
                    hTop = max(histFloor, log10(hSh))
                    if hTop > histFloor
                        Paint rectangle: barCol$, hLo, hHi, histFloor, hTop
                    endif
                endif
            endfor
        endif
        Colour: "Black"
        Select inner viewport: vizL, 3.90, yDa, yDb
        Axes: 0, 1, histFloor, 0.15
        Draw inner box
        One mark left: 0, "no", "yes", "no", "1"
        One mark left: -1, "no", "yes", "no", "0.1"
        One mark left: -2, "no", "yes", "no", "0.01"
        One mark left: -3, "no", "yes", "no", "0.001"
        Marks bottom every: 1, 0.25, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: vizL, 3.90, yDa, yDb
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "harmonic mask value  (0 = all percussive, 1 = all harmonic)"
        Text left: "yes", "share of energy"
        Colour: "{0.45, 0.45, 0.55}"
        Text: 0.98, "right", 0.93, "half", "decisive (<0.15 or >0.85): " + maskDecisiveStat$
        Colour: "Black"

        # --- D right: WSOLA alignment ----------------------------------------
        @caption: 4.35, vizR, yDa, yDb, "WSOLA search - how far each percussive frame moved to keep attacks intact"
        devSpan = max(abs(devLo), abs(devHi))
        if devSpan < 0.5
            devSpan = 0.5
        endif
        devSpan = devSpan * 1.15
        Font size: 7
        Select inner viewport: 4.35, vizR, yDa, yDb
        Axes: 0, maxDurViz, -devSpan, devSpan
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, maxDurViz, -devSpan, devSpan
        Dotted line
        Colour: colRule$
        Draw line: 0, 0, maxDurViz, 0
        # The similarity search cannot move a frame further than its radius, so
        # deviations riding these lines mean the search wanted more room.
        seekMs = 0
        if wsolaSeekStat$ <> "?"
            seekMs = 1000 * number(wsolaSeekStat$) / sr
        endif
        if seekMs > 0 and seekMs < devSpan
            Colour: "{0.55, 0.55, 0.62}"
            Draw line: 0, seekMs, maxDurViz, seekMs
            Draw line: 0, -seekMs, maxDurViz, -seekMs
        endif
        Solid line
        Select inner viewport: 4.35, vizR, yDa, yDb
        Axes: 0, maxDurViz, -devSpan, devSpan
        # Dense runs saturate into a solid block, so thin and shrink the dots
        # once there are more frames than the panel can separate.
        wStride = 1
        if nWsola > 1500
            wStride = ceiling(nWsola / 1500)
        endif
        wScale = 1
        if nWsola > 600
            wScale = max(0.50, sqrt(600 / nWsola))
        endif
        if hasWsola
            selectObject: wsolaTbl
            for i from 1 to nWsola
                if i - wStride * floor(i / wStride) = 0 or wStride = 1
                    wT = Get value: i, "out_time_s"
                    wD = Get value: i, "deviation_ms"
                    wS = Get value: i, "score"
                    # Dot size carries the correlation the search achieved: a
                    # small dot is a frame it could not match well.
                    dotD = (0.6 + 1.0 * min(1, max(0, wS))) * wScale
                    Paint circle (mm): colPerc$, wT, wD, max(0.25, dotD)
                endif
            endfor
        endif
        Colour: "Black"
        Select inner viewport: 4.35, vizR, yDa, yDb
        Axes: 0, maxDurViz, -devSpan, devSpan
        Draw inner box
        @snapStep: 2 * devSpan, 4
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        Marks bottom every: 1, snapT, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: 4.35, vizR, yDa, yDb
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "output time (s)   -   dot size = correlation achieved"
        Text left: "yes", "deviation from nominal (ms)"
        if seekMs > 0
            Paint rectangle: "{1.00, 1.00, 1.00}", 0.46, 0.995, 0.885, 0.975
            Colour: "{0.45, 0.45, 0.55}"
            radTxt$ = "search radius \+- " + fixed$(seekMs, 2) + " ms"
            if wStride > 1
                radTxt$ = radTxt$ + "   |   every " + string$(wStride) + "th frame"
            endif
            Text: 0.98, "right", 0.93, "half", radTxt$
            Colour: "Black"
        endif
    endif

    # --- spectrogram stack ----------------------------------------------------
    # All four are painted over the SAME 0..maxDurViz axis, so the input ends
    # partway across its panel while the stretched layers fill theirs.
    specCap$ = "Input, the two separated layers as they were stretched, and their sum - all on one time axis"
    if fullFigure = 0
        specCap$ = "Input and result spectrograms on one time axis"
    endif
    @caption: vizL, vizR, ySp1a, ySp1b, specCap$

    @drawSpectro: vizL, vizR, ySp1a, ySp1b, sound, "Input"

    if fullFigure
        Read from file: tempHarm$
        harmSound = selected("Sound")
        @drawSpectro: vizL, vizR, ySp2a, ySp2b, harmSound, "Harmonic"
        removeObject: harmSound

        Read from file: tempPerc$
        percSound = selected("Sound")
        @drawSpectro: vizL, vizR, ySp3a, ySp3b, percSound, "Percussive"
        removeObject: percSound
    endif

    @drawSpectro: vizL, vizR, ySp4a, ySp4b, resultSound, "Result"

    # Time numbers only on the last panel of the flush stack.
    Font size: 7
    Select inner viewport: vizL, vizR, ySp4a, ySp4b
    Axes: 0, maxDurViz, 0, 5000
    Marks bottom every: 1, snapT, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    # --- summary --------------------------------------------------------------
    Font size: 7
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 8
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.015, "left", 0.90, "half", "##Process summary##"

    Font size: 7
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    achieved = 0
    if dur > 0
        achieved = durOut / dur
    endif
    Text: 0.015, "left", 0.755, "half", "Stretch: requested x" + fixed$(stretch_factor, 3)
        ... + ", achieved x" + fixed$(achieved, 3)
        ... + "   duration " + fixed$(dur, 3) + " to " + fixed$(durOut, 3) + " s"
        ... + "   STFT N=" + string$(fFT_size) + ", hop=" + string$(round(fFT_size / 8))
        ... + " (" + fixed$(1000 * fFT_size / sr, 1) + " ms window)"
    hpssTxt$ = "HPSS: margin " + fixed$(hPSS_margin, 1)
        ... + ", median kernels 31 x 31   harmonic RMS " + harmonicRmsStat$
        ... + ", percussive RMS " + percRmsStat$ + ", H/P " + hpRatioStat$
    if fullFigure
        hpssTxt$ = hpssTxt$ + "   harmonic energy share " + harmEnergyStat$
            ... + ", decisive mask " + maskDecisiveStat$
    endif
    Text: 0.015, "left", 0.620, "half", hpssTxt$
    Text: 0.015, "left", 0.485, "half", "Harmonic branch: phase vocoder, magnitude interpolated and phase advanced by measured instantaneous frequency (pitch preserved)"
    wsTxt$ = "Percussive branch: WSOLA, " + wsolaFramesStat$ + " frames, window " + wsolaWindowStat$
        ... + " samples, synthesis hop " + wsolaSynStat$ + ", analysis hop " + wsolaAnaStat$
        ... + ", search radius " + wsolaSeekStat$
    if fullFigure = 0
        wsTxt$ = "Percussive branch: WSOLA (telemetry not reported by this engine)"
    endif
    Text: 0.015, "left", 0.350, "half", wsTxt$
    devTxt$ = "Alignment: mean |deviation| " + wsolaDevStat$ + " ms, max " + wsolaMaxDevStat$
        ... + " ms, mean correlation " + wsolaScoreStat$
    if fullFigure = 0
        devTxt$ = "Alignment: not reported by this engine"
    endif
    Text: 0.015, "left", 0.215, "half", devTxt$
        ... + "   |   channels " + string$(nChannels)
        ... + ", linked WSOLA " + linkedWsolaStat$
    Text: 0.015, "left", 0.080, "half", "Level: RMS " + fixed$(rms_in, 4) + " to " + fixed$(rms_out, 4)
        ... + ", peak matched to input at " + outPeakStat$
    if fullFigure = 0
        Colour: "{0.70, 0.35, 0.10}"
        Text: 0.985, "right", 0.90, "half", "compact figure: engine did not export the process tables"
        Colour: "Black"
    endif
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1

    if hasProfile
        removeObject: profTbl
    endif
    if hasHist
        removeObject: histTbl
    endif
    if hasWsola
        removeObject: wsolaTbl
    endif

    # Save as / Copy follow the CURRENT viewport selection, so end on the whole
    # canvas or the export is silently cropped to the last panel.
    Select outer viewport: 0, 8, 0, canvasH
endif

# ---- CLEANUP TEMP FILES ----
@cleanUpTempFiles

# ---- PLAY ----
if play_result
    selectObject: resultSound
    Play
endif

# ---- SUMMARY ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:      ", soundName$ + "_hpss_x" + fixed$(stretch_factor, 2)
appendInfoLine: "Duration:    ", fixed$(dur, 2), " s -> ", fixed$(durOut, 2), " s"
appendInfoLine: "Stretch:     x", fixed$(stretch_factor, 2)
appendInfoLine: "H/P ratio:   ", hpRatioStat$
appendInfoLine: "RMS:         ", fixed$(rms_in, 4), " -> ", fixed$(rms_out, 4)
appendInfoLine: "Peak:        ", outPeakStat$

# -----------------------------------------------------------------------------
# Drawing helpers
# -----------------------------------------------------------------------------

# Picture-window text treats _ ^ # % and \ as markup, so machine-generated
# labels have to be escaped before they reach any Text command.
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
    Colour: "{0.40, 0.40, 0.50}"
    Text top: "no", .txt$
    Colour: "Black"
endproc

# Every spectrogram in the stack is painted over the SAME 0..maxDurViz axis, so
# a shorter object ends partway across its panel instead of being autoscaled to
# fill it. That is what makes the stretch visible as width.
procedure drawSpectro: .x1, .x2, .y1, .y2, .snd, .name$
    Font size: 7
    Select inner viewport: .x1, .x2, .y1, .y2
    selectObject: .snd
    .nch = Get number of channels
    if .nch > 1
        Extract one channel: 1
    else
        Copy: "hpssVizChannel"
    endif
    .tmp = selected("Sound")
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, maxDurViz, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec, .tmp
    Colour: "Black"
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, maxDurViz, 0, 5000
    Draw inner box
    Marks left every: 1, 2000, "yes", "yes", "no"
    Marks bottom every: 1, snapT, "no", "yes", "no"
    @rail: .y1, .y2, .name$
endproc
