# ============================================================
# Praat AudioTools - Spectral_Eraser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Eraser — interactive time-frequency eraser.
#   Opens a Python/tkinter GUI showing the spectrogram.
#   The user draws on it to silence specific frequency-time
#   regions.  Uses STFT → mask → iSTFT round-trip.
#
#   Pipeline:
#     1. Praat exports mono WAV to temp path
#     2. Python computes STFT, displays spectrogram GUI
#     3. User paints erasure regions (sets STFT bins to zero)
#     4. Python applies mask, iSTFT, writes output WAV
#     5. Praat imports result, visualises before/after
#
#   Dependencies: Python 3 with numpy, soundfile, tkinter
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ---- Input check ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# ---- Form ----
form Spectral Eraser v1.0
    comment === FFT Resolution ===
    optionmenu FFT_size: 2
        option 512 (fast, low freq resolution)
        option 1024 (balanced)
        option 2048 (high resolution)
        option 4096 (very high, slower GUI)

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Map menu choice to actual FFT size
if fFT_size = 1
    fftN = 512
elsif fFT_size = 2
    fftN = 1024
elsif fFT_size = 3
    fftN = 2048
else
    fftN = 4096
endif

# ============================================================
# PATHS  (plugin-relative for distribution)
# ============================================================

pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/spectral_eraser.py"

tempInput$  = pluginDir$ + "temp_speceraser_input.wav"
tempOutput$ = pluginDir$ + "temp_speceraser_output.wav"
doneFile$   = pluginDir$ + "temp_speceraser_done.txt"

# Verify Python script exists
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# Clean stale files from any previous run
if fileReadable(tempInput$)
    deleteFile: tempInput$
endif
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(doneFile$)
    deleteFile: doneFile$
endif

# ============================================================
# ROBUST PYTHON DETECTION  (4-candidate probe with tkinter check)
# ============================================================

pythonCmd$ = ""
probeMarker$ = pluginDir$ + "temp_speceraser_probe.ok"

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

    probeCode$ = "import tkinter; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
    endif

    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find Python with tkinter." + newline$
        ... + "Install Python 3 (with tkinter) and ensure it is in PATH." + newline$
        ... + "Also install:  pip install numpy soundfile"
endif

# ============================================================
# INFO
# ============================================================

clearinfo
writeInfoLine: "=== Spectral Eraser v1.0 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "FFT size: ", fftN
appendInfoLine: "Python: ", pythonCmd$
appendInfoLine: ""

# ============================================================
# EXPORT MONO WAV
# ============================================================

appendInfoLine: "[1/4] Exporting mono WAV..."

selectObject: sound
if numChannels > 1
    monoTemp = Convert to mono
else
    monoTemp = Copy: "mono_work"
endif

selectObject: monoTemp
Save as WAV file: tempInput$
removeObject: monoTemp

# ============================================================
# LAUNCH PYTHON GUI
# ============================================================

appendInfoLine: "[2/4] Opening Spectral Eraser GUI..."
appendInfoLine: "       (draw on the spectrogram, then click Apply)"
appendInfoLine: ""

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + doneFile$ + """"
    ... + " " + string$(fftN)

# ============================================================
# CHECK RESULT
# ============================================================

# Read done file
if not fileReadable(doneFile$)
    # Python crashed or was killed
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    exitScript: "Python did not complete." + newline$
        ... + "Possible causes:" + newline$
        ... + "  - numpy or soundfile not installed" + newline$
        ... + "  - Python error (check terminal for messages)"
endif

doneStatus$ = readFile$(doneFile$)
deleteFile: doneFile$
deleteFile: tempInput$

if doneStatus$ = "CANCEL"
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    appendInfoLine: "Cancelled by user."
    selectObject: sound
    exitScript: "Spectral Eraser cancelled."
endif

if not fileReadable(tempOutput$)
    exitScript: "Output file not found — Python may have failed."
endif

# ============================================================
# IMPORT RESULT
# ============================================================

appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
result = selected("Sound")
deleteFile: tempOutput$

selectObject: result
Scale peak: 0.95
Rename: soundName$ + "_erased"
resultDur = Get total duration

appendInfoLine: "Result: ", selected$("Sound"), " (", fixed$(resultDur, 2), " s)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "[4/4] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Spectral Eraser##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$ + "  |  FFT=" + string$(fftN)
        ... + "  |  " + fixed$(duration, 2) + " s"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: result
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Erased"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Input spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.24, 3.64
    Select inner viewport: 0.55, 3.85, 2.34, 3.54

    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizOrigCh = selected("Sound")
    else
        Copy: "vizOrigCh"
        vizOrigCh = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig, vizOrigCh
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original spectrogram"

    # ----------------------------------------------------------
    # Output spectrogram (shows erased regions)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.24, 3.64
    Select inner viewport: 4.40, 7.65, 2.34, 3.54

    selectObject: result
    Copy: "vizResCh"
    vizResCh = selected("Sound")
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes, vizResCh
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Erased spectrogram"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.74, 4.44
    Select inner viewport: 0.55, 7.65, 3.80, 4.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.42, "half",
        ... "Source: " + soundName$
        ... + "  |  FFT: " + string$(fftN)
        ... + "  |  Hop: " + string$(fftN / 4)
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
        ... + "  |  SR: " + string$(sampleRate) + " Hz"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ============================================================
# FINAL
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
