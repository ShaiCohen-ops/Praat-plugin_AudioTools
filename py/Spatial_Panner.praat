# ============================================================
# Praat AudioTools Plugin
# Script:      Spatial_Panner.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.0 (2025)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Opens a Python GUI with a 2D circular spatial trajectory editor.
#   - Draw a moving source path inside a circle
#   - Assign a time value to each path point
#   - The source motion is converted to N-channel loudspeaker gains
#     using DBAP (Distance-Based Amplitude Panning)
#   - Default: 8 speakers arranged in a ring
#
# Workflow:
#   1. Selected Sound → exported to temp WAV
#   2. Python opens 2D stage GUI
#   3. User draws trajectory, clicks Apply
#   4. Python writes N-channel WAV
#   5. Praat imports result as new Sound object
#
# Dependencies (Python):
#   pip install numpy soundfile scipy
#   tkinter — included in standard Python
#
# Usage:
#   Select a Sound object, then run this script.
# ============================================================

# ---- Verify selection ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected ("Sound")
soundName$ = selected$ ("Sound")

# ---- Paths ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/spatial_panner.py"
tempInput$    = pluginDir$ + "temp_spatial_input.wav"
tempOutput$   = pluginDir$ + "temp_spatial_output.wav"

# ---- Export selected sound to temp WAV ----
selectObject: sound
Save as WAV file: tempInput$

# ---- Robust Python detection ----
pythonCmd$   = ""
probeMarker$ = pluginDir$ + "temp_spatial_probe.ok"

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

    if fileReadable (probeMarker$)
        deleteFile: probeMarker$
    endif

    probeCode$ = "import numpy,soundfile,scipy; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable (probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
    endif

    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    deleteFile: tempInput$
    exitScript: "Cannot find Python with required packages." + newline$
        ... + "" + newline$
        ... + "Please install:" + newline$
        ... + "  pip install numpy soundfile scipy"
endif

# ---- Launch GUI ----
clearinfo
appendInfoLine: "=== Spatial Panner ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Python:  ", pythonCmd$
appendInfoLine: ""
appendInfoLine: "Opening spatial trajectory editor..."
appendInfoLine: "(Waiting for GUI)"

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"

# ---- Check result ----
if not fileReadable (tempOutput$)
    deleteFile: tempInput$
    appendInfoLine: ""
    appendInfoLine: "Cancelled."
    exitScript: "Spatial Panner cancelled."
endif

# ---- Import result ----
appendInfoLine: ""
appendInfoLine: "Importing result..."
Read from file: tempOutput$
Rename: soundName$ + "_spatial"
result = selected ("Sound")

# ---- Report output ----
selectObject: result
dur_out = Get total duration
sr_out  = Get sampling frequency
nch_out = Get number of channels
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "Duration:  ", fixed$ (dur_out, 3), " s"
appendInfoLine: "SR:        ", sr_out, " Hz"
appendInfoLine: "Channels:  ", nch_out
appendInfoLine: "RMS:       ", fixed$ (rms_out, 6)

if rms_out < 0.0001
    appendInfoLine: "WARNING: output is silent or near-zero!"
else
    appendInfoLine: "OK: audio looks valid"
endif

# ---- Cleanup ----
deleteFile: tempInput$
deleteFile: tempOutput$

selectObject: result
Play
appendInfoLine: ""
appendInfoLine: "Done. New object: ", soundName$ + "_spatial"
