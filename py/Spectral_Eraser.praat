# ============================================================
# Praat AudioTools - Spectral_Eraser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026) - Interactive Preview audition
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
#     1. Praat exports the selected Sound to a unique temp WAV
#     2. Python computes STFT, displays spectrogram GUI
#     3. User paints erasure regions (sets STFT bins to zero)
#     4. Python applies mask, iSTFT, writes output WAV
#     5. Praat imports result, visualises before/after
#
#   Dependencies: Python 3 with numpy, soundfile, tkinter
#   Optional for Preview audition: sounddevice
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis–Resynthesis
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

# ============================================================
# PATHS
# ============================================================

pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/spectral_eraser.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/spectral_eraser.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: spectral_eraser.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runTag$ = string$(sound)
tempInput$   = tempDir$ + "temp_speceraser_" + runTag$ + "_input.wav"
tempOutput$  = tempDir$ + "temp_speceraser_" + runTag$ + "_output.wav"
doneFile$    = tempDir$ + "temp_speceraser_" + runTag$ + "_done.txt"
tempStats$   = tempDir$ + "temp_speceraser_" + runTag$ + "_stats.txt"
pyLog$       = tempDir$ + "temp_speceraser_" + runTag$ + "_python.log"
probePy$     = tempDir$ + "temp_speceraser_" + runTag$ + "_probe.py"
probeMarker$ = tempDir$ + "temp_speceraser_" + runTag$ + "_probe.ok"

# Forward-slash versions for Python
tempInputJ$   = replace_regex$(tempInput$,   "\\", "/", 0)
tempOutputJ$  = replace_regex$(tempOutput$,  "\\", "/", 0)
doneFileJ$    = replace_regex$(doneFile$,    "\\", "/", 0)
tempStatsJ$   = replace_regex$(tempStats$,   "\\", "/", 0)
pyLogJ$       = replace_regex$(pyLog$,       "\\", "/", 0)
probePyJ$     = replace_regex$(probePy$,     "\\", "/", 0)
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ============================================================
# CLEANUP PROCEDURE
# ============================================================

procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(doneFile$)
        deleteFile: doneFile$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ============================================================
# STAGE 0 — Python Probe (file-based, runs before form)
# ============================================================

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

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "if sys.version_info < (3, 8): sys.exit(1)"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import tkinter, numpy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

pythonCmd$ = ""
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
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python with tkinter, numpy, and soundfile." + newline$
        ... + "Install Python 3 and run:  pip install numpy soundfile"
endif

# ============================================================
# FORM
# ============================================================

form Spectral Eraser v2.1
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
# INFO
# ============================================================

clearinfo
writeInfoLine: "=== Spectral Eraser v2.1 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "FFT size: ", fftN
appendInfoLine: "Python: ", pythonCmd$
appendInfoLine: ""

# ============================================================
# STAGE 1 — Choose representative analysis channel + export Sound
# ============================================================

appendInfoLine: "[1/4] Selecting analysis channel and exporting WAV..."

analysisChannel = 1
analysisRms = -1
if numChannels > 1
    for ch from 1 to numChannels
        selectObject: sound
        Extract one channel: ch
        chTemp = selected("Sound")
        chRms = Get root-mean-square: 0, 0
        if chRms > analysisRms
            analysisRms = chRms
            analysisChannel = ch
        endif
        removeObject: chTemp
    endfor
endif
appendInfoLine: "  Analysis channel: ", analysisChannel, " / ", numChannels

selectObject: sound
Save as WAV file: tempInput$

# ============================================================
# STAGE 2 — Launch Python GUI
# ============================================================

appendInfoLine: "[2/4] Opening Spectral Eraser GUI..."
appendInfoLine: "       (draw on the spectrogram, then click Apply)"
appendInfoLine: ""

runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + tempInputJ$ + """"
    ... + " """ + tempOutputJ$ + """"
    ... + " """ + doneFileJ$ + """"
    ... + " " + string$(fftN)
    ... + " " + string$(analysisChannel)
    ... + " """ + tempStatsJ$ + """"
    ... + " > """ + pyLogJ$ + """ 2>&1"

# ============================================================
# STAGE 3 — Check Result
# ============================================================

if not fileReadable(doneFile$)
    pyErr$ = ""
    if fileReadable(pyLog$)
        pyErr$ = readFile$(pyLog$)
    endif
    if pyErr$ = ""
        pyErr$ = "(no Python log was produced)"
    endif
    @cleanUpTempFiles
    exitScript: "Python did not complete." + newline$ + newline$ + pyErr$
endif

doneStatus$ = readFile$(doneFile$)

if doneStatus$ = "CANCEL"
    @cleanUpTempFiles
    appendInfoLine: "Cancelled by user."
    selectObject: sound
    exitScript: "Spectral Eraser cancelled."
endif

if not fileReadable(tempOutput$)
    pyErr$ = ""
    if fileReadable(pyLog$)
        pyErr$ = readFile$(pyLog$)
    endif
    @cleanUpTempFiles
    exitScript: "Output file not found — Python may have failed." + newline$ + pyErr$
endif

# ============================================================
# STAGE 4 — Import Result
# ============================================================

appendInfoLine: "[3/4] Importing result..."

Read from file: tempOutput$
result = selected("Sound")

selectObject: result
resultChannels = Get number of channels
if resultChannels <> numChannels
    @cleanUpTempFiles
    removeObject: result
    selectObject: sound
    exitScript: "Channel-count mismatch: input=" + string$(numChannels)
        ... + ", output=" + string$(resultChannels)
endif
Rename: soundName$ + "_erased"
resultDur = Get total duration

appendInfoLine: "Result: ", selected$("Sound"), " (", fixed$(resultDur, 2), " s, ", resultChannels, " ch)"
if fileReadable(tempStats$)
    appendInfoLine: "QC metrics:"
    appendInfoLine: readFile$(tempStats$)
endif

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
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Spectral Eraser##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.18, "half",
        ... soundName$ + "  |  FFT=" + string$(fftN)
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  ch " + string$(analysisChannel) + "/" + string$(numChannels)

    # ----------------------------------------------------------
    # Representative channels + one shared waveform scale
    # ----------------------------------------------------------
    selectObject: sound
    if numChannels > 1
        Extract one channel: analysisChannel
        vizOrigCh = selected("Sound")
    else
        Copy: "vizOrigCh"
        vizOrigCh = selected("Sound")
    endif
    inputMax = Get maximum: 0, 0, "Sinc70"
    inputMin = Get minimum: 0, 0, "Sinc70"
    inputPeak = max(abs(inputMax), abs(inputMin))

    selectObject: result
    if resultChannels > 1
        Extract one channel: analysisChannel
        vizResCh = selected("Sound")
    else
        Copy: "vizResCh"
        vizResCh = selected("Sound")
    endif
    outputMax = Get maximum: 0, 0, "Sinc70"
    outputMin = Get minimum: 0, 0, "Sinc70"
    outputPeak = max(abs(outputMax), abs(outputMin))
    waveY = max(inputPeak, outputPeak)
    if waveY < 0.000001
        waveY = 1
    endif
    waveY = waveY * 1.05

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: vizOrigCh
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input ch " + string$(analysisChannel)

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: vizResCh
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Erased ch " + string$(analysisChannel)
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Input spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.24, 3.64
    Select inner viewport: 0.55, 3.85, 2.34, 3.54

    vizMaxHz = sampleRate / 2
    selectObject: vizOrigCh
    To Spectrogram: 0.02, vizMaxHz, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig
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

    selectObject: vizResCh
    To Spectrogram: 0.02, vizMaxHz, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Erased spectrogram"

    removeObject: vizOrigCh, vizResCh

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
        ... + "  |  Analysis ch: " + string$(analysisChannel) + "/" + string$(numChannels)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
else
    appendInfoLine: "[4/4] Visualization skipped."
endif

# ============================================================
# CLEANUP & FINAL
# ============================================================

@cleanUpTempFiles

selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
