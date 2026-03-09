# ============================================================
# Praat AudioTools - VST_Effect_from_Praat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
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
# Platform setup
# ============================================================

if windows
    sep$ = "\"
    pythonCmd$ = "py"
    platform$ = "Windows"
elsif macintosh
    sep$ = "/"
    pythonCmd$ = "python3"
    platform$ = "macOS"
else
    sep$ = "/"
    pythonCmd$ = "python3"
    platform$ = "Linux"
endif

pluginDir$ = preferencesDirectory$ + sep$ + "plugin_AudioTools" + sep$

# Create plugin dir if needed: writing the prefs file is enough to make the folder.
# (Praat creates parent directories automatically when writing a file.)

tempInput$  = pluginDir$ + "vst_input.wav"
tempOutput$ = pluginDir$ + "vst_output.wav"
tempLog$    = pluginDir$ + "vst_gui_log.txt"

# ============================================================
# Validate host script location
# ============================================================

pythonScript$ = "host_vst.py"
if not fileReadable(pythonScript$)
    exitScript: "Cannot find host_vst.py. Put host_vst.py in the same folder as this Praat script."
endif

# ============================================================
# Load last-used plugin path from Python config
# (Python saves ~/.vst_host/settings.json; we can't read JSON
#  directly from Praat, so we keep a plain-text mirror)
# ============================================================

prefsFile$ = pluginDir$ + "last_plugin.txt"
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

beginPause: "VST3 Effect — Launch GUI"
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

tempDone$ = pluginDir$ + "vst_done.txt"

# Remove any stale sentinel from a previous run
if fileReadable(tempDone$)
    deleteFile: tempDone$
endif
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif

pyArgs$ = " --gui"
    ... + " " + q$ + tempInput$ + q$
    ... + " " + q$ + tempOutput$ + q$
    ... + " " + q$ + defaultPlugin$ + q$
    ... + " " + curTail$
    ... + " " + curBuf$
    ... + " " + q$ + curParams$ + q$
    ... + " " + q$ + tempDone$ + q$

# Launch Python detached so Praat is NOT blocked
if windows
    # "start /b" launches without a new window and returns immediately
    cmd$ = "start /b " + pythonCmd$ + " " + q$ + pythonScript$ + q$ + pyArgs$
    ...   + " > " + q$ + tempLog$ + q$ + " 2>&1"
else
    # "&" backgrounds the process on mac / Linux
    cmd$ = pythonCmd$ + " " + q$ + pythonScript$ + q$ + pyArgs$
    ...   + " > " + q$ + tempLog$ + q$ + " 2>&1 &"
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
    pauseScript: 1
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
    deleteFile: tempLog$
endif

deleteFile: tempInput$
if fileReadable(tempDone$)
    deleteFile: tempDone$
endif

# ============================================================
# Import result
# ============================================================

if waited >= maxWait and not gotResult
    appendInfoLine: ""
    appendInfoLine: "*** Timed out waiting for Python (10 min). ***"
    appendInfoLine: "The GUI may still be open. Close it and re-run if needed."

elsif fileReadable(tempOutput$)
    Read from file: tempOutput$
    Rename: soundName$ + "_vst"
    resultSound = selected("Sound")
    deleteFile: tempOutput$
    appendInfoLine: "Done. Created: ", soundName$ + "_vst"

    if curSave and defaultPlugin$ <> ""
        writeFileLine: prefsFile$, defaultPlugin$
    endif

    if curPlay
        selectObject: resultSound
        Play
    endif
else
    appendInfoLine: ""
    appendInfoLine: "*** No output WAV produced. ***"
    appendInfoLine: "The user cancelled, or processing failed."
    appendInfoLine: "Check the log above for details."
endif
