# ============================================================
# Praat AudioTools - VST_Effect_from_Praat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   VST3 Effect — Praat -> Python GUI host -> VST3 -> Praat
#
#   This script serves as a bridge between Praat and a Python-based 
#   GUI host for VST3 plugins. It allows users to process Praat 
#   Sound objects through external VST3 effects while maintaining 
#   a responsive front-end.
#
# Citation:
#   Cohen, S. (2026). VST3 Host:
#   Python GUI Bridge for Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

q$ = """"

# ============================================================
# Platform setup & OS-SPECIFIC PYTHON DISCOVERY
# ============================================================

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
    platform$ = "macOS"
elsif windows
    pythonCmd$ = "python"
    platform$ = "Windows"
else
    pythonCmd$ = "python3"
    platform$ = "Linux"
endif

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/host_vst.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/host_vst.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: host_vst.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempInput$  = tempDir$ + "vst_temp_input.wav"
tempOutput$ = tempDir$ + "vst_temp_output.wav"
tempLog$    = tempDir$ + "vst_temp_gui_log.txt"
tempDone$   = tempDir$ + "vst_temp_done.txt"
probePy$    = tempDir$ + "vst_temp_probe.py"
probeMarker$= tempDir$ + "vst_temp_probe.ok"

# The preferences file stays in the plugin directory so it persists across runs
prefsFile$  = pluginDir$ + "last_vst_plugin.txt"

# Enforce forward slashes for all paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
tempLogJ$      = replace_regex$(tempLog$, "\\", "/", 0)
tempDoneJ$     = replace_regex$(tempDone$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
prefsFileJ$    = replace_regex$(prefsFile$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(tempDone$)
        deleteFile: tempDone$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import pedalboard, soundfile, tkinter"
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
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install pedalboard soundfile"
endif

# ============================================================
# Load last-used plugin path
# ============================================================

defaultPlugin$ = ""
if fileReadable(prefsFile$)
    defaultPlugin$ = readFile$(prefsFile$)
    if right$(defaultPlugin$, 1) = newline$
        defaultPlugin$ = left$(defaultPlugin$, length(defaultPlugin$) - 1)
    endif
endif

# ============================================================
# Settings form  (lightweight – most settings are in the GUI)
# ============================================================

beginPause: "VST3 Effect — Launch GUI v1.1"
    comment: "Adjust detailed settings in the Python window that will open."
    if defaultPlugin$ <> ""
        comment: "Last plugin: " + defaultPlugin$
    else
        comment: "No last-used plugin found (will open blank GUI)."
    endif
    real:    "Tail seconds",  1.0
    natural: "Buffer size",   8192
    sentence: "Parameters",  ""
    boolean: "Play result",   1
    boolean: "Save as default plugin", 1
clicked = endPause: "Cancel", "Open GUI", 2

if clicked = 1
    exitScript: "Cancelled."
endif

curTail$   = fixed$(tail_seconds, 3)
curBuf$    = string$(buffer_size)
curParams$ = parameters$
curPlay    = play_result
curSave    = save_as_default_plugin

# ============================================================
# Write input WAV
# ============================================================

selectObject: sound
Save as WAV file: tempInput$

# ============================================================
# Build command  (--gui flag → Python opens the Tkinter window)
# Python will write tempDone$ when it exits (success or cancel).
# ============================================================

pyArgs$ = " --gui"
    ... + " " + q$ + tempInputJ$ + q$
    ... + " " + q$ + tempOutputJ$ + q$
    ... + " " + q$ + defaultPlugin$ + q$
    ... + " " + curTail$
    ... + " " + curBuf$
    ... + " " + q$ + curParams$ + q$
    ... + " " + q$ + tempDoneJ$ + q$

# Launch Python detached so Praat is NOT blocked
if windows
    # "start /b" launches without a new window and returns immediately
    cmd$ = "start /b " + pythonCmd$ + " " + q$ + pythonScriptJ$ + q$ + pyArgs$
    ...   + " > " + q$ + tempLogJ$ + q$ + " 2>&1"
else
    # "&" backgrounds the process on mac / Linux
    cmd$ = pythonCmd$ + " " + q$ + pythonScriptJ$ + q$ + pyArgs$
    ...   + " > " + q$ + tempLogJ$ + q$ + " 2>&1 &"
endif

clearinfo
writeInfoLine:  "=== Praat -> Python GUI -> VST3 ==="
appendInfoLine: "Input sound:   ", soundName$
appendInfoLine: "Platform:      ", platform$
appendInfoLine: "Python:        ", pythonCmd$
appendInfoLine: ""
appendInfoLine: "Launching GUI (Praat stays responsive)…"

runSystem_nocheck: cmd$

# ============================================================
# Poll for the sentinel file (Python writes it on exit).
# Praat stays fully responsive; the loop just checks the disk.
# Timeout after ~10 minutes (600 × 1 s pauses).
# ============================================================

appendInfoLine: "Waiting for Python GUI to finish…"

maxWait   = 600
waited    = 0
gotResult = 0

repeat
    pauseScript: "Waiting for VST GUI to close. Do not click Continue here.", "Continue", 1
    waited += 1
    if fileReadable(tempDone$)
        gotResult = 1
    endif
until gotResult = 1 or waited >= maxWait

# ============================================================
# Show Python log output
# ============================================================

if fileReadable(tempLog$)
    log$ = readFile$(tempLog$)
    appendInfoLine: log$
endif

# ============================================================
# Import result
# ============================================================

if waited >= maxWait and not gotResult
    appendInfoLine: ""
    appendInfoLine: "*** Timed out waiting for Python (10 min). ***"
    appendInfoLine: "The GUI may still be open. Close it and re-run if needed."
    @cleanUpTempFiles

elsif fileReadable(tempOutput$)
    Read from file: tempOutput$
    Rename: soundName$ + "_vst"
    resultSound = selected("Sound")
    
    appendInfoLine: "Done. Created: ", soundName$ + "_vst"

    if curSave and defaultPlugin$ <> ""
        writeFileLine: prefsFile$, defaultPlugin$
    endif

    @cleanUpTempFiles

    if curPlay
        selectObject: resultSound
        Play
    endif
else
    appendInfoLine: ""
    appendInfoLine: "*** No output WAV produced. ***"
    appendInfoLine: "The user cancelled, or processing failed."
    appendInfoLine: "Check the log above for details."
    @cleanUpTempFiles
endif