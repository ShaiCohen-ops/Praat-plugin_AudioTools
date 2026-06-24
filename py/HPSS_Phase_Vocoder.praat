# ============================================================
# Praat AudioTools - HPSS_Phase_Vocoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026) — WSOLA percussive stretch (pitch/transient preserving)
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
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

tempInput$   = temporaryDirectory$ + "/temp_hpss_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_hpss_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_hpss_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_hpss_probe.ok"

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
endproc

@cleanUpTempFiles

# ---- FORM ----
form HPSS Phase Vocoder v2.2
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
writeInfoLine:  "=== HPSS Phase Vocoder v2.2 ==="
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

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + fixed$(stretch_factor, 6)
    ... + " " + string$(fFT_size)
    ... + " " + fixed$(hPSS_margin, 2)

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
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title (own band) ===
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##HPSS Phase Vocoder##"

    # === Subtitle (separate band so it can't collide with the title) ===
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", soundName$ + " | x" + fixed$(stretch_factor, 2) + " | " + presetName$ + " | FFT=" + string$(fFT_size)

    # === Input waveform ===
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

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.5, 2.35
    Select inner viewport: 0.6, 7.7, 1.55, 2.30
    selectObject: resultSound
    Colour: "{0.25, 0.55, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stretched"
    Text bottom: "yes", "Time (s)"

    # === Original spectrogram ===
    Select outer viewport: 0, 8, 2.45, 3.7
    Select inner viewport: 0.6, 7.7, 2.55, 3.65

    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig_hpss"
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
    Select outer viewport: 0, 8, 3.75, 5.0
    Select inner viewport: 0.6, 7.7, 3.85, 4.95

    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut_hpss"
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
    Text top: "no", "Stretched spectrogram"
    removeObject: specOut, tmpOut

    # === Summary panel ===
    Select outer viewport: 0, 8, 5.2, 6.4
    Select inner viewport: 0.6, 7.7, 5.3, 6.3
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.68, "half",
        ... "Preset: " + presetName$
        ... + "  |  Stretch: x" + fixed$(stretch_factor, 2)
        ... + "  |  In: " + fixed$(dur, 2) + "s  ->  Out: " + fixed$(durOut, 2) + "s"
    Text: 0.02, "left", 0.48, "half",
        ... "FFT: " + string$(fFT_size)
        ... + "  |  HPSS margin: " + fixed$(hPSS_margin, 1)
        ... + "  |  H/P ratio: " + hpRatioStat$
    Text: 0.02, "left", 0.28, "half",
        ... "Harmonic RMS: " + harmonicRmsStat$
        ... + "  |  Percussive RMS: " + percRmsStat$
        ... + "  |  Peak: " + outPeakStat$
    Text: 0.02, "left", 0.08, "half",
        ... "RMS: " + fixed$(rms_in, 4) + " -> " + fixed$(rms_out, 4)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"

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