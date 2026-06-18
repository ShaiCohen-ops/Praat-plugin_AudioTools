# ============================================================
# Praat AudioTools - PlayMultichannel.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - Capture Python stdout/stderr to Info window on failure
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel Audio Playback Bridge
#
#   Praat cannot reliably play more than two channels.
#   This script exports the selected Sound to a temporary WAV
#   and delegates playback to Python (sounddevice / ASIO / WASAPI).
#   The temporary file is deleted automatically after playback.
#
#   Supports any channel count (2, 4, 8, 16 …).
#   Requires a professional audio interface (ASIO/WASAPI) for
#   more than 2 channels on Windows.
#
# Dependencies (Python):
#   pip install sounddevice soundfile numpy
#
# Usage:
#   1. Select a multichannel Sound in Praat object list.
#   2. Run this script.
#   3. Pick your output device (sound card) from the dropdown, then Play.
#      The list is queried live; your choice is remembered for next time.
#   4. Python plays back the audio on the chosen device.
#   5. Temp file is deleted automatically when playback ends.
#
# Changelog v1.3:
#   - On playback failure, the actual Python stdout/stderr is now captured to a
#     temp log and printed to Praat's Info window, instead of the unhelpful
#     "check terminal" message (the console window closes instantly on Windows).
#
# Changelog v1.2:
#   - Output device is chosen from a live dropdown built from the system's
#     actual output devices (no more reading a text table and typing an ID).
#     The last-used device is remembered between runs in play_device.cfg.
#   - multichannel_play.py gains a --devices-tsv mode emitting a parseable
#     id<TAB>label device list for the picker.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

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

pythonScript$ = pluginDir$ + "py/multichannel_play.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/multichannel_play.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: multichannel_play.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempWav$         = tempDir$ + "temp_play.wav"
deviceListFile$  = tempDir$ + "temp_play_devices.txt"
playStatusFile$  = tempDir$ + "temp_play_status.ok"
playLogFile$     = tempDir$ + "temp_play_log.txt"
probePy$         = tempDir$ + "temp_play_probe.py"
probeMarker$     = tempDir$ + "temp_play_probe.ok"
configFile$      = pluginDir$ + "play_device.cfg"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$   = replace_regex$(pythonScript$, "\\", "/", 0)
tempWavJ$        = replace_regex$(tempWav$, "\\", "/", 0)
deviceListFileJ$ = replace_regex$(deviceListFile$, "\\", "/", 0)
playStatusFileJ$ = replace_regex$(playStatusFile$, "\\", "/", 0)
playLogFileJ$    = replace_regex$(playLogFile$, "\\", "/", 0)
probePyJ$        = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$    = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempWav$)
        deleteFile: tempWav$
    endif
    if fileReadable(deviceListFile$)
        deleteFile: deviceListFile$
    endif
    if fileReadable(playStatusFile$)
        deleteFile: playStatusFile$
    endif
    if fileReadable(playLogFile$)
        deleteFile: playLogFile$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- CAPTURE SOUND STATS ----
selectObject: sound
nChannels = Get number of channels
sr        = Get sampling frequency
dur       = Get total duration

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Multichannel Playback v1.3 ==="
appendInfoLine: "Sound:    ", soundName$
appendInfoLine: "Channels: ", nChannels
appendInfoLine: "SR:       ", sr, " Hz"
appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: ""

# ===========================================================================
# Stage 1 - Detect Python Dependencies
# ===========================================================================
appendInfoLine: "Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, sounddevice, soundfile"
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
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    exitScript: "Cannot find Python with required packages." + newline$ + "  pip install sounddevice soundfile numpy"
endif

appendInfoLine: "  Python found: ", pythonCmd$
appendInfoLine: ""

# ===========================================================================
# Stage 2 - Enumerate output devices for the picker
# ===========================================================================
appendInfoLine: "Querying output devices..."

if fileReadable(deviceListFile$)
    deleteFile: deviceListFile$
endif

runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """ --devices-tsv """ + deviceListFileJ$ + """"

nDev = 0
if fileReadable(deviceListFile$)
    Read Strings from raw text file: deviceListFile$
    strObj = selected("Strings")
    nDev = Get number of strings
    for i from 1 to nDev
        selectObject: strObj
        line$ = Get string: i
        tabPos = index(line$, tab$)
        if tabPos > 0
            deviceId[i]     = number(left$(line$, tabPos - 1))
            deviceLabel$[i] = right$(line$, length(line$) - tabPos)
        else
            deviceId[i]     = -1
            deviceLabel$[i] = line$
        endif
    endfor
    removeObject: strObj
    deleteFile: deviceListFile$
endif

appendInfoLine: "  ", nDev, " output device(s) found."
appendInfoLine: ""

# ---- Remembered default device (from last run) ----
savedDevice = -1
if fileReadable(configFile$)
    savedDevice = number(readFile$(configFile$))
    if savedDevice = undefined
        savedDevice = -1
    endif
endif

defaultIdx = 1
for i from 1 to nDev
    if deviceId[i] = savedDevice
        defaultIdx = i + 1
    endif
endfor

# ===========================================================================
# Stage 3 - Playback options dialog (device picker dropdown)
# ===========================================================================
beginPause: "Multichannel Playback"
    comment: "Sound: " + soundName$ + "   (" + string$(nChannels) + " ch, " + string$(sr) + " Hz, " + fixed$(dur, 2) + " s)"
    comment: "Output device (your sound card):"
    optionmenu: "Device", defaultIdx
        option: "System default"
        for i from 1 to nDev
            option: deviceLabel$[i]
        endfor
    comment: "Latency: low = ASIO-optimised; high = more stable"
    optionmenu: "Latency", 1
        option: "low"
        option: "high"
    boolean: "Downmix to stereo if needed", 0
    boolean: "Print debug info", 0
clicked = endPause: "Cancel", "Play", 2, 1

if clicked = 1
    @cleanUpTempFiles
    exitScript: "Cancelled."
endif

# ---- Map dropdown choice -> device id, and remember it ----
if device = 1
    chosenDevice = -1
    appendInfoLine: "Device:   system default"
else
    chosenDevice = deviceId[device - 1]
    appendInfoLine: "Device:   ", deviceLabel$[device - 1]
endif

writeFile: configFile$, string$(chosenDevice)

# ---- Latency string ----
if latency = 1
    latencyStr$ = "low"
else
    latencyStr$ = "high"
endif
appendInfoLine: ""

# ===========================================================================
# Stage 4 - Export Temp WAV
# ===========================================================================
appendInfoLine: "[1/3] Exporting temp WAV..."
selectObject: sound
Save as WAV file: tempWav$

if not fileReadable(tempWav$)
    @cleanUpTempFiles
    exitScript: "Failed to write temp WAV: " + tempWav$
endif

appendInfoLine: "      Written: ", tempWav$

# ===========================================================================
# Stage 5 - Playback
# ===========================================================================
appendInfoLine: "[2/3] Starting Python playback engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """" + " """ + tempWavJ$ + """"

if chosenDevice >= 0
    pythonCall$ = pythonCall$ + " --device " + string$(chosenDevice)
endif

pythonCall$ = pythonCall$ + " --latency " + latencyStr$

if downmix_to_stereo_if_needed
    pythonCall$ = pythonCall$ + " --downmix"
endif

pythonCall$ = pythonCall$ + " --status-file """ + playStatusFileJ$ + """"

if print_debug_info
    pythonCall$ = pythonCall$ + " --debug"
    appendInfoLine: "  Command: ", pythonCall$
endif

# ---- PLAY (blocking) - nocheck so cleanup always runs ----
# Redirect Python's stdout+stderr to a log so any error survives the
# console window closing (works under cmd /c on Windows and sh -c elsewhere).
runSystem_nocheck: pythonCall$ + " > """ + playLogFileJ$ + """ 2>&1"

# ===========================================================================
# Stage 6 - Cleanup
# ===========================================================================
appendInfoLine: "[3/3] Cleaning up..."
if fileReadable(tempWav$)
    deleteFile: tempWav$
    appendInfoLine: "      Deleted: ", tempWav$
else
    appendInfoLine: "      (temp file already gone)"
endif

if not fileReadable(playStatusFile$)
    appendInfoLine: ""
    appendInfoLine: "--- Python output (stdout + stderr) ---"
    if fileReadable(playLogFile$)
        appendInfoLine: readFile$(playLogFile$)
    else
        appendInfoLine: "(no output was captured)"
    endif
    appendInfoLine: "---------------------------------------"
    @cleanUpTempFiles
    exitScript: "Python playback failed. See the Info window above for the Python error."
else
    deleteFile: playStatusFile$
    if fileReadable(playLogFile$)
        deleteFile: playLogFile$
    endif
endif

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
selectObject: sound
