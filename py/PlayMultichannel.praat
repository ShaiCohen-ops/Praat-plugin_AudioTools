# ============================================================
# Praat AudioTools - PlayMultichannel.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
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
#   3. Set Device_ID (-1 = system default) and click OK / Play.
#   4. Python plays back the audio on the chosen device.
#   5. Temp file is deleted automatically when playback ends.
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
probePy$         = tempDir$ + "temp_play_probe.py"
probeMarker$     = tempDir$ + "temp_play_probe.ok"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$   = replace_regex$(pythonScript$, "\\", "/", 0)
tempWavJ$        = replace_regex$(tempWav$, "\\", "/", 0)
deviceListFileJ$ = replace_regex$(deviceListFile$, "\\", "/", 0)
playStatusFileJ$ = replace_regex$(playStatusFile$, "\\", "/", 0)
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
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Multichannel Playback v1.1
    comment ── Device selection (-1 = system default) ───────────────────
    integer Device_ID -1
    comment ── Latency (low = ASIO optimised;  high = more stable) ──────
    optionmenu Latency: 1
        option low
        option high
    comment ── Utilities ────────────────────────────────────────────────
    boolean Downmix_to_stereo_if_needed 0
    boolean List_devices_and_exit 0
    boolean Print_debug_info 0
endform

# ---- CAPTURE SOUND STATS ----
selectObject: sound
nChannels = Get number of channels
sr        = Get sampling frequency
dur       = Get total duration

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Multichannel Playback v1.1 ==="
appendInfoLine: "Sound:    ", soundName$
appendInfoLine: "Channels: ", nChannels
appendInfoLine: "SR:       ", sr, " Hz"
appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: ""

# ---- LATENCY STRING ----
if latency = 1
    latencyStr$ = "low"
else
    latencyStr$ = "high"
endif

# ===========================================================================
# Stage 1 — Detect Python Dependencies
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
# Stage 2 — List Devices Mode
# ===========================================================================
if list_devices_and_exit
    appendInfoLine: "Available output devices:"
    appendInfoLine: ""
    listCmd$ = pythonCmd$ + " """ + pythonScriptJ$ + """ --list-devices --list-devices-file """ + deviceListFileJ$ + """"
    runSystem_nocheck: listCmd$
    
    if fileReadable(deviceListFile$)
        deviceText$ = readFile$(deviceListFile$)
        appendInfoLine: deviceText$
        deleteFile: deviceListFile$
    else
        appendInfoLine: "(Could not capture device list — check terminal output)"
    endif
    appendInfoLine: "Re-run with List_devices_and_exit = 0 and Device_ID set to play."
    goto END
endif

# ===========================================================================
# Stage 3 — Export Temp WAV
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
# Stage 4 — Playback
# ===========================================================================
appendInfoLine: "[2/3] Starting Python playback engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """" + " """ + tempWavJ$ + """"

if device_ID >= 0
    pythonCall$ = pythonCall$ + " --device " + string$(device_ID)
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

# ---- PLAY (blocking) — nocheck so cleanup always runs ----
runSystem_nocheck: pythonCall$

# ===========================================================================
# Stage 5 — Cleanup
# ===========================================================================
appendInfoLine: "[3/3] Cleaning up..."
if fileReadable(tempWav$)
    deleteFile: tempWav$
    appendInfoLine: "      Deleted: ", tempWav$
else
    appendInfoLine: "      (temp file already gone)"
endif

if not fileReadable(playStatusFile$)
    @cleanUpTempFiles
    exitScript: "Python playback failed. Check terminal for errors."
else
    deleteFile: playStatusFile$
endif

label END

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
selectObject: sound