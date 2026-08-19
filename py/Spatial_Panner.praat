# ============================================================
# Praat AudioTools Plugin
# Script:      Spatial_Panner.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     2.3 (2026) - Unified Cross-Platform Version
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modernized Spatial Panner with robust path handling and 
#   dependency probing. Opens a Python GUI for 2D trajectory editing.
# ============================================================

# ---- SELECTION CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
inputName$ = selected$("Sound")

# ---- PATH NORMALIZATION (Forward Slashes) ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$    = replace_regex$(pluginDirRaw$, "\\", "/", 0)

tempDirRaw$   = temporaryDirectory$ + "/"
tempDir$      = replace_regex$(tempDirRaw$, "\\", "/", 0)

# File Paths

pythonScript$ = pluginDir$ + "py/spatial_panner.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/spatial_panner.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: spatial_panner.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

runTag$       = string$(inputSound)
tempInput$    = tempDir$ + "temp_spatial_input_" + runTag$ + ".wav"
tempOutput$   = tempDir$ + "temp_spatial_output_" + runTag$ + ".wav"
probePy$      = tempDir$ + "temp_spatial_probe_" + runTag$ + ".py"
probeMarker$  = tempDir$ + "temp_spatial_probe_" + runTag$ + ".ok"
pyLog$        = tempDir$ + "temp_spatial_log_" + runTag$ + ".txt"

# Escape paths for system calls (quoted)
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
pyLogJ$        = replace_regex$(pyLog$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
endproc

@cleanUpFiles

# ===========================================================================
# Stage 0 — File-Based Python Dependency Probe
# ===========================================================================
writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile, tkinter"
appendFileLine: probePy$, "    if sys.version_info < (3, 8): sys.exit(1)"
appendFileLine: probePy$, "    with open(sys.argv[1], 'w', encoding='utf-8') as f: f.write('ok')"
appendFileLine: probePy$, "except Exception:"
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

    # Run the probe script
    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """ """ + probeMarkerJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpFiles
    exitScript: "Cannot find Python 3.8+ with required packages (numpy, scipy, soundfile, tkinter)."
endif

# ===========================================================================
# Stage 1 — Execution
# ===========================================================================
clearinfo
appendInfoLine: "=== Spatial Panner v2.3 ==="
appendInfoLine: "Input:  ", inputName$
appendInfoLine: "Python: ", pythonCmd$
appendInfoLine: ""

# Export selected sound to temporary space
selectObject: inputSound
Save as WAV file: tempInput$

appendInfoLine: "Opening spatial trajectory editor..."
appendInfoLine: "Audition device selection is available in the GUI when Python sounddevice is installed."
appendInfoLine: "(Waiting for GUI to close)"

# Execute Python GUI and capture diagnostics. Use nocheck so Praat can show
# the Python traceback instead of aborting before cleanup.
runSystem_nocheck: pythonCmd$ + " """ + pythonScriptJ$ + """ """ + tempInputJ$ + """ """ + tempOutputJ$ + """ > """ + pyLogJ$ + """ 2>&1"

# Check if user saved a result or cancelled/failed
if not fileReadable(tempOutput$)
    pyLogText$ = ""
    if fileReadable(pyLog$)
        pyLogText$ = readFile$: pyLog$
    endif
    if index(pyLogText$, "Cancelled.") > 0
        @cleanUpFiles
        appendInfoLine: "Cancelled by user."
        exitScript: "Spatial Panner cancelled."
    endif
    @cleanUpFiles
    if pyLogText$ = ""
        pyLogText$ = "(no Python diagnostic output was captured)"
    endif
    exitScript: "Spatial Panner Python engine failed." + newline$ + newline$ + pyLogText$
endif

# Import and label the result
appendInfoLine: "Importing multi-channel result..."
Read from file: tempOutput$
Rename: inputName$ + "_spatial"
resultSound = selected("Sound")

# Final Stats Reporting
selectObject: resultSound
dur = Get total duration
sr  = Get sampling frequency
nch = Get number of channels
rms = Get root-mean-square: 0, 0

appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "SR:       ", sr, " Hz"
appendInfoLine: "Channels: ", nch
appendInfoLine: "RMS:      ", fixed$(rms, 6)

if rms < 0.0001
    appendInfoLine: "WARNING: Output signal is near silence!"
endif

# Clean up and finish
@cleanUpFiles
appendInfoLine: ""
appendInfoLine: "Done."
selectObject: resultSound
Play