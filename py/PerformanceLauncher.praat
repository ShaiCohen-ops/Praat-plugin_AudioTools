# ============================================================
# Praat AudioTools Plugin
# Script:      PerformanceLauncher.praat
# Author:      Shai Cohen
# Version:     1.7 (2026) — MIDI keyboard cue triggering (optional)
# License:     MIT License
#
# Description:
#   Prepares selected Sound objects, resamples them to a unified
#   maximum sample rate, writes a performance manifest, and hands
#   complete execution over to the real-time Python audio engine.
#
# Usage:
#   Select one or more Sound objects, then run this script.
#   Optional: python -m pip install python-rtmidi  to trigger cues
#   from a MIDI keyboard (selection order = cue order = keys C3 upward
#   by default; remap in the launcher window).
#
# Changelog v1.7:
#   - Version sync with performance_launcher.py MIDI input. The probe
#     now also checks for python-rtmidi (optional - never blocks launch)
#     and the info window reports whether MIDI is available.
#
# Changelog v1.6:
#   - FIX: Python discovery was a single OS-based guess ("python" on
#     Windows), never verified until an inline "-c" probe run through a
#     real shell (runSystem_nocheck) with hand-escaped quotes - the same
#     class of fragility fixed elsewhere in the library. Replaced with the
#     verified cascade (configured venv tried first, "python3" included
#     since it resolves to a fuller install on this machine - see
#     Spectral_Eraser.praat), file-based per-package probe, and no-shell
#     runSubprocess for the engine launch itself.
#
# Changelog v1.5:
#   - Performance configuration moved out of the temporary directory into
#     plugin_AudioTools so device/routing/gain/fade settings persist across runs.
#   - Temporary log is reset at launch and removed after a clean close, but is
#     left available after an engine crash for diagnosis.
#   - Cue names are sanitized for JSON backslashes as well as quotation marks.
#   - Version synced with the Python engine live-safety/routing/fade fixes.
#
# Changelog v1.4:
#   - Version bump to match performance_launcher.py ASIO support
#     (multichannel interfaces now reachable on Windows) and host-API
#     device labels. Front-end logic unchanged; header, info banner,
#     and manifest plugin_version synced to 1.4.
#
# Changelog v1.3:
#   - Version bump to match performance_launcher.py live master-gain
#     control (Up/Down +/-1 dB, Left/Right +/-0.1 dB from the keyboard).
#     Front-end logic unchanged; header, info banner, and manifest
#     plugin_version synced to 1.3.
#
# Changelog v1.2:
#   - Dependency probe hardened: now imports tkinter, numpy,
#     sounddevice and soundfile (was tkinter only), so a missing
#     audio module is reported before the GUI launches rather than
#     surfacing later via the Python crash trap. Exit message lists
#     all required modules and the pip install command.
#   - Version synced to 1.2: info-window banner and manifest
#     plugin_version both updated (the v1.1 "header sync" left these
#     reading 1.0).
#   - Removed the dead done-file handshake (doneFile$ definitions,
#     manifest "done_file" entry, and its cleanup): this script only
#     ever read the error file; the Python engine no longer writes a
#     done file.
#
# Changelog v1.1:
#   - Version bump to match performance_launcher.py cross-platform
#     scroll fix (Linux Button-4/5 bindings in Python GUI).
#   - Header updated to match plugin standard format.
#
# Changelog v1.0:
#   - Initial release. OS-specific Python discovery, manifest JSON
#     generation, resampling pass, and Python engine handoff.
# ============================================================

# ---- Verify selection ----
nSounds = numberOfSelected ("Sound")
if nSounds < 1
    exitScript: "Please select at least one Sound object to populate the cue sheet."
endif

# ---- Store selected sound IDs ----
for i from 1 to nSounds
    sound'i'      = selected ("Sound", i)
    soundName'i'$ = selected$ ("Sound", i)
endfor

# ---- PYTHON INTERPRETER CANDIDATES (verified cascade) ----
# v1.6: previously this picked ONE name per OS (bare "python" on Windows)
# and never verified it had tkinter/numpy/sounddevice/soundfile until a
# shell-based inline probe further down - fragile (same class of quoting
# bug fixed across the library). Now matches the rest of the library: #1
# is your known-good venv (edit THAT ONE LINE if yours lives elsewhere),
# then an OS-appropriate fallback list. On Windows this includes
# "python3" - on this machine that resolves to the Microsoft Store
# Python, the one candidate confirmed to actually have tkinter (see
# Spectral_Eraser.praat). EACH candidate is actually probed below via a
# no-shell, file-based check before acceptance.
nPyCand = 1
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"

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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/performance_launcher.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/performance_launcher.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python performance script: performance_launcher.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

manifestFile$ = temporaryDirectory$ + "/temp_launcher_manifest.json"
errorFile$    = temporaryDirectory$ + "/temp_launcher_error.txt"
logFile$      = temporaryDirectory$ + "/temp_launcher_log.txt"
configFile$   = pluginDir$ + "performance_launcher_config.json"
# JSON formatting requires unified forward slashes across all platforms
manifestFileJ$ = replace_regex$ (manifestFile$, "\\", "/", 0)
errorFileJ$    = replace_regex$ (errorFile$,    "\\", "/", 0)
logFileJ$      = replace_regex$ (logFile$,      "\\", "/", 0)
configFileJ$   = replace_regex$ (configFile$,   "\\", "/", 0)

# ---- PYTHON DEPENDENCY VALIDATION (verified cascade, no-shell probe) ----
probeOkFile$  = temporaryDirectory$ + "/temp_launcher_probe.ok"
probeOkFileJ$ = replace_regex$ (probeOkFile$, "\\", "/", 0)
probeScript$  = temporaryDirectory$ + "/temp_launcher_probe.py"
probeError$   = temporaryDirectory$ + "/temp_launcher_probe_error.txt"
probeMidiFile$ = temporaryDirectory$ + "/temp_launcher_probe.midi"

if fileReadable(probeOkFile$)
    deleteFile: probeOkFile$
endif
if fileReadable(probeScript$)
    deleteFile: probeScript$
endif

writeFileLine: probeScript$, "import sys"
appendFileLine: probeScript$, "pkgs = ['tkinter', 'numpy', 'sounddevice', 'soundfile']"
appendFileLine: probeScript$, "missing = []"
appendFileLine: probeScript$, "for pkg in pkgs:"
appendFileLine: probeScript$, "    try:"
appendFileLine: probeScript$, "        __import__(pkg)"
appendFileLine: probeScript$, "    except Exception as e:"
appendFileLine: probeScript$, "        missing.append(pkg)"
appendFileLine: probeScript$, "try:"
appendFileLine: probeScript$, "    import rtmidi"
appendFileLine: probeScript$, "    open(r'" + replace_regex$(probeMidiFile$, "\\", "/", 0) + "', 'w').write('OK')"
appendFileLine: probeScript$, "except Exception:"
appendFileLine: probeScript$, "    pass"
appendFileLine: probeScript$, "if not missing:"
appendFileLine: probeScript$, "    open(r'" + probeOkFileJ$ + "', 'w').write('OK')"
appendFileLine: probeScript$, "else:"
appendFileLine: probeScript$, "    open(r'" + replace_regex$(probeError$, "\\", "/", 0) + "', 'w').write('Missing: ' + ', '.join(missing))"

pythonCmd$ = ""
pySource$  = ""
pyTried$   = ""

for iPyCand to nPyCand
    thisPyCand$ = pyCandidate'iPyCand'$
    pyTried$ = pyTried$ + "  - " + thisPyCand$ + newline$
    if pythonCmd$ = ""
        isBarePyCmd = (thisPyCand$ = "python3") or (thisPyCand$ = "python") or (thisPyCand$ = "py")
        if isBarePyCmd or fileReadable(thisPyCand$)
            if fileReadable(probeOkFile$)
                deleteFile: probeOkFile$
            endif
            if fileReadable(probeError$)
                deleteFile: probeError$
            endif
            if fileReadable(probeMidiFile$)
                deleteFile: probeMidiFile$
            endif
            nocheck runSubprocess: thisPyCand$, probeScript$
            if fileReadable(probeOkFile$)
                pythonCmd$ = thisPyCand$
                if iPyCand = 1
                    pySource$ = "configured venv"
                else
                    pySource$ = "auto-detected"
                endif
            endif
        endif
    endif
endfor

# The last candidate probed is the accepted one (the loop stops probing
# once pythonCmd$ is set), so the MIDI flag describes that interpreter.
midiAvailable = fileReadable(probeMidiFile$)
if midiAvailable
    deleteFile: probeMidiFile$
endif

if fileReadable(probeOkFile$)
    deleteFile: probeOkFile$
endif
if fileReadable(probeScript$)
    deleteFile: probeScript$
endif

if pythonCmd$ = ""
    diagMsg$ = "Tried:" + newline$ + pyTried$ + newline$
        ... + "Fix: point pyCandidate1$ (near the top of the PYTHON" + newline$
        ... + "interpreter candidates section) at a venv that has them, or" + newline$
        ... + "install into one of the paths above, e.g.:" + newline$
        ... + "  python -m pip install sounddevice soundfile numpy"
    if fileReadable(probeError$)
        diagMsg$ = readFile$(probeError$) + newline$ + newline$ + diagMsg$
    endif
    exitScript: "Missing Python dependencies." + newline$ + newline$ + diagMsg$
endif

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable (manifestFile$)
        deleteFile: manifestFile$
    endif
    if fileReadable (errorFile$)
        deleteFile: errorFile$
    endif
    if fileReadable (probeScript$)
        deleteFile: probeScript$
    endif
    if fileReadable (probeError$)
        deleteFile: probeError$
    endif
    if fileReadable (probeMidiFile$)
        deleteFile: probeMidiFile$
    endif
    for c_i from 1 to nSounds
        tmpWav$ = temporaryDirectory$ + "/temp_launcher_clip_" + string$ (c_i) + ".wav"
        if fileReadable (tmpWav$)
            deleteFile: tmpWav$
        endif
    endfor
endproc

# Clear residual temporary buffers from a previous run. The persistent
# config file is intentionally not part of cleanUpTempFiles.
@cleanUpTempFiles
if fileReadable (logFile$)
    deleteFile: logFile$
endif

# ---- PASS 1: Calculate Target Sample Rate & Max Channels ----
totalDuration = 0
maxSR         = 0
maxChannels   = 0

for i from 1 to nSounds
    selectObject: sound'i'
    dur'i' = Get total duration
    sr'i'  = Get sampling frequency
    nch'i' = Get number of channels
    totalDuration = totalDuration + dur'i'
    if sr'i' > maxSR
        maxSR = sr'i'
    endif
    if nch'i' > maxChannels
        maxChannels = nch'i'
    endif
endfor

targetSR = maxSR

# ---- PASS 2: Export Multichannel Sounds Directly to RAM Cache WAVs ----
nResampled = 0
for i from 1 to nSounds
    clipFile'i'$  = temporaryDirectory$ + "/temp_launcher_clip_" + string$ (i) + ".wav"
    clipFileJ'i'$ = replace_regex$ (clipFile'i'$, "\\", "/", 0)

    if fileReadable (clipFile'i'$)
        deleteFile: clipFile'i'$
    endif

    selectObject: sound'i'
    if sr'i' <> targetSR
        # Resample on structural copies ensuring the user's base items remain safe
        Resample: targetSR, 50
        tmpResampled = selected ("Sound")
        Save as WAV file: clipFile'i'$
        removeObject: tmpResampled
        nResampled = nResampled + 1
    else
        Save as WAV file: clipFile'i'$
    endif
endfor

# ---- Build Manifest JSON Structure ----
nl$ = newline$
manifest$ = "{" + nl$
manifest$ = manifest$ + "  ""plugin_name"": ""Performance Launcher""," + nl$
manifest$ = manifest$ + "  ""plugin_version"": ""1.7""," + nl$
manifest$ = manifest$ + "  ""project_sample_rate"": " + string$ (targetSR) + "," + nl$
manifest$ = manifest$ + "  ""project_max_channels"": " + string$ (maxChannels) + "," + nl$
manifest$ = manifest$ + "  ""temp_dir"": """ + replace_regex$(temporaryDirectory$, "\\", "/", 0) + """," + nl$
manifest$ = manifest$ + "  ""error_file"": """ + errorFileJ$ + """," + nl$
manifest$ = manifest$ + "  ""log_file"": """ + logFileJ$ + """," + nl$
manifest$ = manifest$ + "  ""config_file"": """ + configFileJ$ + """," + nl$
manifest$ = manifest$ + "  ""debug"": 0," + nl$
manifest$ = manifest$ + "  ""clips"": [" + nl$

for i from 1 to nSounds
    safeName'i'$ = replace_regex$ (soundName'i'$, "\\", "/", 0)
    safeName'i'$ = replace_regex$ (safeName'i'$, """", "'", 0)
    manifest$ = manifest$ + "    {" + nl$
    manifest$ = manifest$ + "      ""id"": " + string$ (i - 1) + "," + nl$
    manifest$ = manifest$ + "      ""name"": """ + safeName'i'$ + """," + nl$
    manifest$ = manifest$ + "      ""filename"": """ + clipFileJ'i'$ + """," + nl$
    manifest$ = manifest$ + "      ""duration"": " + fixed$ (dur'i', 6) + "," + nl$
    manifest$ = manifest$ + "      ""channels"": " + string$ (nch'i') + "," + nl$
    manifest$ = manifest$ + "      ""sample_rate"": " + string$ (targetSR) + "," + nl$
    manifest$ = manifest$ + "      ""default_key"": """"," + nl$
    manifest$ = manifest$ + "      ""gain_db"": 0.0," + nl$
    manifest$ = manifest$ + "      ""fade_in"": 0.0," + nl$
    manifest$ = manifest$ + "      ""fade_out"": 0.1," + nl$
    manifest$ = manifest$ + "      ""color"": """"," + nl$
    manifest$ = manifest$ + "      ""playback_mode"": ""restart""" + nl$
    if i < nSounds
        manifest$ = manifest$ + "    }," + nl$
    else
        manifest$ = manifest$ + "    }" + nl$
    endif
endfor
manifest$ = manifest$ + "  ]" + nl$
manifest$ = manifest$ + "}"

writeFile: manifestFile$, manifest$

# ---- Execution Log Window Feed ----
clearinfo
appendInfoLine: "=== Performance Launcher 1.7 ==="
appendInfoLine: "Loaded Cues: ", nSounds
appendInfoLine: "Target System Rate: ", targetSR, " Hz"
appendInfoLine: "Max File Channels:  ", maxChannels
if nResampled > 0
    appendInfoLine: "Resample Status:    Converted ", nResampled, " item tracks to sync rates."
else
    appendInfoLine: "Resample Status:    Native matching."
endif
appendInfoLine: "Python:             ", pythonCmd$, " (", pySource$, ")"
if midiAvailable
    appendInfoLine: "MIDI:               available (choose a port in the launcher)"
else
    appendInfoLine: "MIDI:               off - ", pythonCmd$, " -m pip install python-rtmidi"
endif
appendInfoLine: "Spawning Thread Engine..."

# ---- Launch Performance Space ----
# v1.6: switched from runSystem_nocheck string concatenation (shell,
# quote-fragile) to no-shell runSubprocess with separate arguments.
nocheck runSubprocess: pythonCmd$, pythonScript$, manifestFile$

# ---- Catch Engine Fatal Disconnections ----
if fileReadable (errorFile$)
    errMsg$ = readFile$ (errorFile$)
    appendInfoLine: "--- Engine Execution Crash Traceback ---"
    appendInfoLine: errMsg$
    appendInfoLine: "----------------------------------------"
    @cleanUpTempFiles
    exitScript: "Performance frame interrupted. See Praat info window for detailed logs."
endif

@cleanUpTempFiles
if fileReadable (logFile$)
    deleteFile: logFile$
endif
appendInfoLine: "Launcher closed cleanly. Temporary buffers flushed; performance config retained."