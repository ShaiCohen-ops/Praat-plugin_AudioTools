# ============================================================
# Praat AudioTools - VST_Effect_from_Praat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.9.2 (2026) - release cleanup
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   VST3 Host - Praat -> Python host -> native plugin editor/audition -> Praat
#
#   AUDIO EFFECT       one Sound selected
#                      Sound -> Pedalboard VST3 effect -> Sound "<name>_vst"
#
#   INSTRUMENT RENDER  one Strings object holding MusicXML selected
#                      MusicXML -> parsed notes -> DawDreamer VST instrument
#                      -> Sound "<name>_vsti"
#
#   Canonical Python backend filename: host_vst.py
#   Release/version numbers are kept inside the host, not in the filename.
#
# Changelog v1.9.2:
#   - Production split is now explicit: Pedalboard for effects, DawDreamer for VSTi.
#   - Removed all experimental v1.8 instrument fallback paths.
#   - Python dependency probe now reports the missing package(s) explicitly.
#   - Canonical backend filename remains host_vst.py.
#
# Citation:
#   Cohen, S. (2026). VST3 Host: Python GUI Bridge for Praat.
#   Praat AudioTools Plugin.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# Mode from the selection
# ============================================================

nSelected = numberOfSelected()
if nSelected = 1 and numberOfSelected("Sound") = 1
    mode$ = "effect"
    sound = selected("Sound")
    soundName$ = selected$("Sound")
    inputName$ = soundName$
    resultName$ = soundName$ + "_vst"
elsif nSelected = 1 and numberOfSelected("Strings") = 1
    mode$ = "instrument"
    scoreStrings = selected("Strings")
    stringsName$ = selected$("Strings")
    inputName$ = stringsName$
    nScoreLines = Get number of strings
    if nScoreLines < 3
        exitScript: "The selected Strings object is too short to be a MusicXML score."
    endif
    # Look for the root element near the top (declaration and DOCTYPE come first).
    scoreKind$ = ""
    for iLine from 1 to min(nScoreLines, 12)
        line$ = Get string: iLine
        if scoreKind$ = "" and index(line$, "<score-partwise") > 0
            scoreKind$ = "partwise"
        elsif scoreKind$ = "" and index(line$, "<score-timewise") > 0
            scoreKind$ = "timewise"
        endif
    endfor
    if scoreKind$ = "timewise"
        exitScript: "This is a score-timewise MusicXML file; only score-partwise is supported."
    elsif scoreKind$ = ""
        exitScript: "The selected Strings object does not look like MusicXML (no <score-partwise> in its first lines)."
    endif
    # musicxml_<name> (AudioTools scripts) and <name>_musicxml (BasicPitchTranscriber)
    baseName$ = stringsName$
    if length(baseName$) > 9 and left$(baseName$, 9) = "musicxml_"
        baseName$ = mid$(baseName$, 10, length(baseName$) - 9)
    endif
    if length(baseName$) > 9 and right$(baseName$, 9) = "_musicxml"
        baseName$ = left$(baseName$, length(baseName$) - 9)
    endif
    if baseName$ = ""
        baseName$ = "score"
    endif
    resultName$ = baseName$ + "_vsti"
else
    exitScript: "Select exactly one object:" + newline$ + "  a Sound - to process it with a VST3 effect, or" + newline$ + "  a Strings object holding MusicXML - to render it with a VST3 instrument."
endif

# Praat 7.0 gates file writing and system commands; ask once, up front.
# The version guard keeps 6.x from evaluating askForTrust, which it lacks.
if praatVersion >= 7000
    trustGranted = askForTrust ()
    if trustGranted = 0
        exitScript: "The VST host needs permission to write temporary files and start Python."
    endif
endif

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

# Canonical host filename: stable across releases.
# The version is tracked inside host_vst.py, not in the filename.
pythonScript$ = pluginDir$ + "py/host_vst.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/host_vst.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find host_vst.py." + newline$ + "Copy it into: " + pluginDir$ + "py/ or the current Praat directory."
endif


tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempInput$  = tempDir$ + "vst_temp_input.wav"
tempScore$  = tempDir$ + "vst_temp_score.musicxml"
tempOutput$ = tempDir$ + "vst_temp_output.wav"
tempLog$    = tempDir$ + "vst_temp_gui_log.txt"
tempDone$   = tempDir$ + "vst_temp_done.txt"
probePy$    = tempDir$ + "vst_temp_probe.py"
probeMarker$= tempDir$ + "vst_temp_probe.ok"
probeReport$= tempDir$ + "vst_temp_probe.txt"

# Persistent preference: remember the last-used VST plugin
# Effects and instruments are remembered separately.
if mode$ = "instrument"
    prefsName$ = "last_vsti_plugin.txt"
else
    prefsName$ = "last_vst_plugin.txt"
endif
prefsFile$ = pluginDir$ + prefsName$
legacyPrefsFile$ = defaultDirectory$ + "/../" + prefsName$

# Preserve an existing Praat 6-era preference when running
# from the old plugin location under Praat 7
if not fileReadable(prefsFile$) and fileReadable(legacyPrefsFile$)
    prefsFile$ = legacyPrefsFile$
elsif not folderExists(pluginDir$)
    prefsFile$ = legacyPrefsFile$
endif

prefsFile$ = replace_regex$(prefsFile$, "\\", "/", 0)

# Enforce forward slashes for all paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempInputJ$    = replace_regex$(tempInput$, "\\", "/", 0)
tempScoreJ$    = replace_regex$(tempScore$, "\\", "/", 0)
tempOutputJ$   = replace_regex$(tempOutput$, "\\", "/", 0)
tempLogJ$      = replace_regex$(tempLog$, "\\", "/", 0)
tempDoneJ$     = replace_regex$(tempDone$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
probeReportJ$  = replace_regex$(probeReport$, "\\", "/", 0)
prefsFileJ$    = replace_regex$(prefsFile$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempScore$)
        deleteFile: tempScore$
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
    if fileReadable(probeReport$)
        deleteFile: probeReport$
    endif
endproc

@cleanUpTempFiles

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================

writeFileLine: probePy$, "import importlib, sys"
if mode$ = "instrument"
    appendFileLine: probePy$, "mods = ['pedalboard', 'soundfile', 'tkinter', 'dawdreamer']"
else
    appendFileLine: probePy$, "mods = ['pedalboard', 'tkinter']"
endif
appendFileLine: probePy$, "missing = []"
appendFileLine: probePy$, "for m in mods:"
appendFileLine: probePy$, "    try: importlib.import_module(m)"
appendFileLine: probePy$, "    except ImportError: missing.append(m)"
appendFileLine: probePy$, "with open(r'" + probeReportJ$ + "', 'w') as f: f.write(', '.join(missing) if missing else 'OK')"
appendFileLine: probePy$, "if missing: sys.exit(1)"
appendFileLine: probePy$, "with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"

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

# The probe result must be able to say "nothing worked". In v1.6 pythonCmd$ was
# pre-seeded with an OS default and only overwritten on success, so the
# "cannot find Python" branch below was unreachable: a machine without the
# packages launched a broken command and the user waited out the full 10-minute
# timeout instead of reading the one-line explanation.
pythonCmd$ = ""
lastProbe$ = ""

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
    if fileReadable(probeReport$)
        deleteFile: probeReport$
    endif

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        if fileReadable(probeReport$)
            deleteFile: probeReport$
        endif
        iCand = nCandidates + 1 ; Break early
    elsif fileReadable(probeReport$)
        missingHere$ = readFile$(probeReport$)
        if missingHere$ <> "" and missingHere$ <> "OK"
            lastProbe$ = tryCmd$ + ": missing " + missingHere$
        endif
        deleteFile: probeReport$
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    if lastProbe$ <> ""
        if mode$ = "instrument"
            exitScript: "Python was found, but Instrument mode is missing required package(s)." + newline$ + lastProbe$ + newline$ + "Install into that Python with: python -m pip install pedalboard soundfile dawdreamer"
        else
            exitScript: "Python was found, but Effect mode is missing required package(s)." + newline$ + lastProbe$ + newline$ + "Install into that Python with: python -m pip install pedalboard"
        endif
    else
        exitScript: "Cannot find a usable Python 3 installation." + newline$ + "Tried: python3, python, py"
    endif
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

# The host window owns tail / buffer / parameters / plugin choice and persists
# them itself, so asking for them here made the user answer the same questions
# twice before seeing a single plugin. Only the genuinely Praat-side decision
# is left.
if mode$ = "instrument"
    pauseTitle$ = "VST3 Instrument - DawDreamer Host v1.9.2"
    lastWord$ = "Last instrument: "
else
    pauseTitle$ = "VST3 Effect - Launch Host v1.9.2"
    lastWord$ = "Last plugin: "
endif
# Pre-set the pause field: batch runs that auto-continue a pause never
# assign it, and the script would otherwise stop on an unknown variable.
play_result = 1
beginPause: pauseTitle$
    if mode$ = "instrument"
        comment: "Score: " + stringsName$ + " (" + string$(nScoreLines) + " lines of MusicXML)"
        comment: "The host lists VST3 instruments; all parts play the one instrument."
    else
        comment: "The host window handles plugin choice, the native VST3 editor and audition."
    endif
    if defaultPlugin$ <> ""
        comment: lastWord$ + defaultPlugin$
    else
        comment: "No last-used plugin yet - the host will scan for installed VST3s."
    endif
    boolean: "Play result", 1
clicked = endPause: "Cancel", "Open host", 2

if clicked = 1
    exitScript: "Cancelled."
endif

curPlay = play_result

# Empty strings tell the host to use its saved settings. Instrument mode uses
# an explicit DAW-sized block; effect mode keeps its own saved/default value.
curTail$   = ""
if mode$ = "instrument"
    curBuf$ = "512"
else
    curBuf$ = ""
endif
curParams$ = ""

# The host writes the plugin the user actually picked, once a render succeeds.
prefsOutJ$ = prefsFileJ$

# ============================================================
# Write input WAV
# ============================================================

if mode$ = "instrument"
    # Plain lines, as the MusicXML writers produced them. Praat writes ASCII
    # when it can and UTF-16 otherwise; the host reads both.
    selectObject: scoreStrings
    Save as raw text file: tempScore$
    hostInputJ$ = tempScoreJ$
    modeFlag$ = " --gui --instrument"
else
    selectObject: sound
    Save as WAV file: tempInput$
    hostInputJ$ = tempInputJ$
    modeFlag$ = " --gui"
endif

# ============================================================
# Build command  (--gui flag → Python opens the Tkinter window)
# Python will write tempDone$ when it exits (success or cancel).
# ============================================================

# Every argument is quoted, including the ones that may now be empty. An
# unquoted empty string collapses to nothing on the command line and silently
# shifts every later positional argument -- which would hand the host the
# sentinel path as its parameter string and leave Praat polling forever.
pyArgs$ = modeFlag$
    ... + " " + q$ + hostInputJ$ + q$
    ... + " " + q$ + tempOutputJ$ + q$
    ... + " " + q$ + defaultPlugin$ + q$
    ... + " " + q$ + curTail$ + q$
    ... + " " + q$ + curBuf$ + q$
    ... + " " + q$ + curParams$ + q$
    ... + " " + q$ + tempDoneJ$ + q$
    ... + " " + q$ + prefsOutJ$ + q$

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
writeInfoLine:  "=== Praat -> Python host -> native VST3 -> Praat ==="
if mode$ = "instrument"
    appendInfoLine: "Mode:          instrument render (MusicXML -> VST3 instrument)"
    appendInfoLine: "Input score:   ", stringsName$, " (", nScoreLines, " lines)"
else
    appendInfoLine: "Mode:          audio effect"
    appendInfoLine: "Input sound:   ", soundName$
endif
appendInfoLine: "Platform:      ", platform$
appendInfoLine: "Python:        ", pythonCmd$
appendInfoLine: "VST host:      ", pythonScript$
appendInfoLine: ""
appendInfoLine: "Launching host GUI with native plugin editor and audition..."

runSystem_nocheck: cmd$

# ============================================================
# Poll for the sentinel file (Python writes it on exit).
# Praat stays fully responsive; the loop just checks the disk.
# Timeout after ~10 minutes (600 × 1 s pauses).
# ============================================================

appendInfoLine: "Waiting for Python host to finish..."

# Poll without a modal pause window. sleep() is the standard Praat scripting
# mechanism for a short timed wait; 6000 x 0.1 s = 10 minutes.
maxWait   = 6000
waited    = 0
gotResult = 0

repeat
    sleep(0.1)
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
    Rename: resultName$
    resultSound = selected("Sound")

    appendInfoLine: "Done. Created: ", resultName$

    # Default VST persistence is handled by the Python GUI so the plugin
    # selected from the new VST list is the one remembered next time.

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