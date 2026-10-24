# ============================================================
# Praat AudioTools Plugin
# Script:      Live_Lab.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     1.1.1 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Entry point of Praat AudioTools Live Lab - MIDI-controlled live
#   capture, Praat analysis-resynthesis through the nine Live chains,
#   and multichannel one-shot performance.
#
#   This script only: locates the plugin, verifies a Python interpreter
#   with the required packages (verified cascade, as PerformanceLauncher
#   v1.6+), and hands over to py/live_lab.py. It creates NO Praat objects.
#   Every chain runs later in a separate, headless Praat worker process
#   (its script is embedded in live_lab.py), never in this Praat session.
#
#   Live Lab is exactly two files, normally side by side in py/
#   (like PerformanceLauncher.praat + performance_launcher.py):
#     Live_Lab.praat   (this script - py/ or Vector Chain/ both work)
#     live_lab.py      (the performance application)
#   The nine chains are read from plugin_AudioTools/Vector Chain/.
#
#   Praat stays busy while Live Lab is open (same as Performance Launcher)
#   and reports any crash or cleanup problem in the Info window when the
#   Live Lab window is closed.
#
# Usage:
#   Run this script (no selection needed). In the Live Lab window:
#   Setup > Audio (ASIO device, rate, Mono/Stereo input) > Apply,
#   Setup > MIDI > "Learn (press & HOLD)" for the pedal, Setup > Praat
#   (auto-detected; "Run worker self-test" to check). Then perform:
#     1-9 select chain   F (hold) / pedal = record   Space = play/retrigger
#     C = crossfade      R = regenerate              [ ] = prev/next result
#     L = latest ready   P = pin   A = Auto Suspend  F2 = arm   Esc = stop all
#   Chains are MANUAL by default (result waits as READY); set AUTO per chain
#   in Setup > Chains. Close the window to end - all temp files are removed;
#   only plugin_AudioTools/live_lab_config.json and explicit exports persist.
#
# Requirements:
#   python -m pip install numpy sounddevice soundfile
#   optional (MIDI pedal / controller):  python -m pip install python-rtmidi
#
# Files: launch handshake files are <system temp>/PraatAudioToolsLiveLab_launch_*
#   (never in temporaryDirectory$, which can be the home folder on Windows)
#   and are deleted before this script ends. Live Lab's own session folder
#   <system temp>/PraatAudioToolsLiveLab/ is created and removed by live_lab.py.
#
# Changelog v1.1.1: no changes in this file except the version (fixes are in live_lab.py).
#
# Changelog v1.1:
#   - Positive completion check: "closed cleanly" is reported only when
#     live_lab.py confirms its verified shutdown (done file). A crash or a
#     killed process is now reported as such, not hidden.
#   - Launch handshake files are named PraatAudioToolsLiveLab_launch_* in
#     the temp folder itself - no folder is created, so none can be left.
#   - The venv candidate is relative to the user's home folder.
#   - Works from py/ or Vector Chain/; chains always read from Vector Chain.
#
# Changelog v1.0:
#   - Initial release.
# ============================================================

# ---- Praat 7 full-trust model: we write/delete handshake files and start
#      a subprocess. askForTrust() is guarded so Praat 6.x never evaluates it.
if praatVersion >= 7000
    trusted = askForTrust ()
    if not trusted
        exitScript: "Live Lab needs permission to start Python and to write its launch files." + newline$
            ... + "Run again and allow it, or use Run > Run with FULL TRUST."
    endif
endif

# ---- PYTHON INTERPRETER CANDIDATES (verified cascade) ----
# #1 is the known-good venv, located RELATIVE to the user's home folder
# (USERPROFILE on Windows, HOME elsewhere), so no user name is hard-coded.
# Edit only the venv folder name if yours differs. Then OS-appropriate
# fallbacks. Each candidate is probed (no shell) below; a missing one is
# simply skipped.
pyVenvName$ = "praat_ddsp_env"
nPyCand = 1
if windows
    pyHome$ = environment$ ("USERPROFILE")
    pyCandidate1$ = pyHome$ + "/" + pyVenvName$ + "/Scripts/python.exe"
else
    pyHome$ = environment$ ("HOME")
    pyCandidate1$ = pyHome$ + "/" + pyVenvName$ + "/bin/python"
endif
pyCandidate1$ = replace_regex$ (pyCandidate1$, "\\", "/", 0)

if macintosh
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/opt/homebrew/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/usr/local/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
elsif windows
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "py"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
else
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python"
endif

# ---- LOCATE THE PLUGIN ----
# This script may live in <plugin>/py/ (next to live_lab.py, like
# PerformanceLauncher.praat) or in <plugin>/Vector Chain/. Either way its
# folder's PARENT is plugin_AudioTools, and the chains are always in
# <plugin>/Vector Chain/. No absolute path is assumed.
scriptDir$ = replace_regex$ (defaultDirectory$, "\\", "/", 0)
scriptDir$ = replace_regex$ (scriptDir$, "/+$", "", 0)
pluginDir$ = replace_regex$ (scriptDir$, "/[^/]*$", "", 0)
chainDir$ = pluginDir$ + "/Vector Chain"

# Python app: next to this script first, then <plugin>/py/
pythonScript$ = scriptDir$ + "/live_lab.py"
if not fileReadable (pythonScript$)
    pythonScript$ = pluginDir$ + "/py/live_lab.py"
endif
# Last resort: the standard plug-in folder of this Praat installation
if not fileReadable (pythonScript$) or not fileReadable (chainDir$ + "/Live_1.praat")
    altPlugin$ = replace_regex$ (preferencesDirectory$, "\\", "/", 0) + "/plugin_AudioTools"
    if fileReadable (altPlugin$ + "/py/live_lab.py") and fileReadable (altPlugin$ + "/Vector Chain/Live_1.praat")
        pluginDir$ = altPlugin$
        chainDir$ = altPlugin$ + "/Vector Chain"
        pythonScript$ = altPlugin$ + "/py/live_lab.py"
    endif
endif
if not fileReadable (pythonScript$)
    exitScript: "Cannot find Python performance script: live_lab.py" + newline$
        ... + "Expected next to this script or at: " + pluginDir$ + "/py/"
endif
if not fileReadable (chainDir$ + "/Live_1.praat")
    exitScript: "Cannot find the Live chains (Live_1.praat ...)." + newline$
        ... + "Expected in: " + chainDir$
endif

# ---- LAUNCH FOLDER (app-owned, in the system temp folder) ----
if windows
    tmpRoot$ = environment$ ("TEMP")
    if tmpRoot$ = ""
        tmpRoot$ = environment$ ("TMP")
    endif
else
    tmpRoot$ = environment$ ("TMPDIR")
    if tmpRoot$ = ""
        tmpRoot$ = "/tmp"
    endif
endif
if tmpRoot$ = ""
    exitScript: "Cannot determine the system temporary folder (TEMP / TMPDIR)."
endif
tmpRoot$ = replace_regex$ (tmpRoot$, "\\", "/", 0)
tmpRoot$ = replace_regex$ (tmpRoot$, "/+$", "", 0)
# Handshake files go straight into the temp folder under a unique,
# app-prefixed name - Praat can delete files but has no folder deletion,
# so no folder is created here at all.
token$ = string$ (randomInteger (100000000, 999999999))
launchBase$ = tmpRoot$ + "/PraatAudioToolsLiveLab_launch_" + token$
probeScript$ = launchBase$ + ".py"
probeOk$     = launchBase$ + ".ok"
probeErr$    = launchBase$ + ".perr"
probeMidi$   = launchBase$ + ".midi"
errorFile$   = launchBase$ + ".err"
doneFile$    = launchBase$ + ".done"

procedure removeLaunchFiles
    if fileReadable (probeScript$)
        deleteFile: probeScript$
    endif
    if fileReadable (probeOk$)
        deleteFile: probeOk$
    endif
    if fileReadable (probeErr$)
        deleteFile: probeErr$
    endif
    if fileReadable (probeMidi$)
        deleteFile: probeMidi$
    endif
    if fileReadable (errorFile$)
        deleteFile: errorFile$
    endif
    if fileReadable (doneFile$)
        deleteFile: doneFile$
    endif
endproc

# ---- PYTHON DEPENDENCY PROBE (file-based, no shell, no quoting tricks) ----
writeFileLine: probeScript$, "import sys"
appendFileLine: probeScript$, "missing = []"
appendFileLine: probeScript$, "for pkg in ['tkinter', 'numpy', 'sounddevice', 'soundfile']:"
appendFileLine: probeScript$, "    try:"
appendFileLine: probeScript$, "        __import__(pkg)"
appendFileLine: probeScript$, "    except Exception as e:"
appendFileLine: probeScript$, "        missing.append(pkg + ' (' + str(e) + ')')"
appendFileLine: probeScript$, "if sys.version_info < (3, 8):"
appendFileLine: probeScript$, "    missing.append('Python 3.8 or newer (found ' + sys.version.split()[0] + ')')"
appendFileLine: probeScript$, "try:"
appendFileLine: probeScript$, "    import rtmidi"
appendFileLine: probeScript$, "    open(r'" + probeMidi$ + "', 'w').write('OK')"
appendFileLine: probeScript$, "except Exception:"
appendFileLine: probeScript$, "    pass"
appendFileLine: probeScript$, "if missing:"
appendFileLine: probeScript$, "    open(r'" + probeErr$ + "', 'w').write('Missing: ' + ', '.join(missing))"
appendFileLine: probeScript$, "else:"
appendFileLine: probeScript$, "    open(r'" + probeOk$ + "', 'w').write(sys.executable)"

pythonCmd$ = ""
pySource$ = ""
pyTried$ = ""
lastProbeError$ = ""
for iPyCand to nPyCand
    thisPyCand$ = pyCandidate'iPyCand'$
    if pythonCmd$ = ""
        pyTried$ = pyTried$ + "  - " + thisPyCand$ + newline$
        isBarePyCmd = (thisPyCand$ = "python3") or (thisPyCand$ = "python") or (thisPyCand$ = "py")
        if isBarePyCmd or fileReadable (thisPyCand$)
            if fileReadable (probeOk$)
                deleteFile: probeOk$
            endif
            if fileReadable (probeErr$)
                deleteFile: probeErr$
            endif
            if fileReadable (probeMidi$)
                deleteFile: probeMidi$
            endif
            nocheck runSubprocess: thisPyCand$, probeScript$
            if fileReadable (probeOk$)
                pythonCmd$ = thisPyCand$
                pyExe$ = readFile$ (probeOk$)
                if iPyCand = 1
                    pySource$ = "configured venv"
                else
                    pySource$ = "auto-detected"
                endif
            elsif fileReadable (probeErr$)
                lastProbeError$ = thisPyCand$ + ": " + readFile$ (probeErr$)
            endif
        endif
    endif
endfor
midiAvailable = fileReadable (probeMidi$)

if pythonCmd$ = ""
    diag$ = "Tried:" + newline$ + pyTried$ + newline$
    if lastProbeError$ <> ""
        diag$ = lastProbeError$ + newline$ + newline$ + diag$
    endif
    @removeLaunchFiles
    exitScript: "Live Lab: no Python with the required packages was found." + newline$ + newline$
        ... + diag$ + newline$
        ... + "Fix: set pyVenvName$ (top of Live_Lab.praat) to your venv folder in your home folder, or run:" + newline$
        ... + "  python -m pip install numpy sounddevice soundfile" + newline$
        ... + "  python -m pip install python-rtmidi      (optional, for MIDI)"
endif

# Probe files are no longer needed before the long-running session starts.
if fileReadable (probeScript$)
    deleteFile: probeScript$
endif
if fileReadable (probeOk$)
    deleteFile: probeOk$
endif
if fileReadable (probeMidi$)
    deleteFile: probeMidi$
endif

clearinfo
appendInfoLine: "=== Praat AudioTools Live Lab 1.1.1 ==="
appendInfoLine: "Plugin:   ", pluginDir$
appendInfoLine: "Python:   ", pythonCmd$, " (", pySource$, ")"
if midiAvailable
    appendInfoLine: "MIDI:     available"
else
    appendInfoLine: "MIDI:     off - ", pythonCmd$, " -m pip install python-rtmidi"
endif
appendInfoLine: "Praat is busy while the Live Lab window is open."
appendInfoLine: "Close the Live Lab window to end the session (all temporary files are removed)."

# ---- LAUNCH (no shell; Praat waits until the Live Lab window closes) ----
nocheck runSubprocess: pythonCmd$, pythonScript$,
    ... "--plugin-dir", pluginDir$, "--chain-dir", chainDir$, "--error-file", errorFile$,
    ... "--done-file", doneFile$

if fileReadable (errorFile$)
    report$ = readFile$ (errorFile$)
    @removeLaunchFiles
    appendInfoLine: ""
    appendInfoLine: "--- Live Lab report ---"
    appendInfoLine: report$
    appendInfoLine: "-----------------------"
    exitScript: "Live Lab ended with a problem - see the Info window."
endif

# Positive confirmation required: Live Lab writes the done file only after
# its shutdown sequence verified that nothing is left. Its absence (Python
# killed, crashed hard, or the window closed abnormally) is reported, not
# hidden behind "closed cleanly".
if not fileReadable (doneFile$)
    @removeLaunchFiles
    appendInfoLine: ""
    appendInfoLine: "--- Live Lab report ---"
    appendInfoLine: "Live Lab ended WITHOUT a completion report (it crashed or was terminated)."
    appendInfoLine: "Its temporary session folder is removed automatically at the next launch."
    appendInfoLine: "-----------------------"
    exitScript: "Live Lab ended abnormally - see the Info window."
endif

@removeLaunchFiles
appendInfoLine: ""
appendInfoLine: "Live Lab closed cleanly. Session workspace removed; configuration kept in plugin_AudioTools."
