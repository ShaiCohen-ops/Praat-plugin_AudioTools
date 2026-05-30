# ============================================================
# Praat AudioTools Plugin
# Script:      PerformanceLauncher.praat
# Author:      Shai Cohen
# Version:     1.3 (2026) — Version sync (engine live master gain)
# License:     MIT License
#
# Description:
#   Prepares selected Sound objects, resamples them to a unified
#   maximum sample rate, writes a performance manifest, and hands
#   complete execution over to the real-time Python audio engine.
#
# Usage:
#   Select one or more Sound objects, then run this script.
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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/performance_launcher.py"

manifestFile$ = temporaryDirectory$ + "/temp_launcher_manifest.json"
errorFile$    = temporaryDirectory$ + "/temp_launcher_error.txt"
logFile$      = temporaryDirectory$ + "/temp_launcher_log.txt"
configFile$   = temporaryDirectory$ + "/temp_launcher_config.json"

# JSON formatting requires unified forward slashes across all platforms
manifestFileJ$ = replace_regex$ (manifestFile$, "\\", "/", 0)
errorFileJ$    = replace_regex$ (errorFile$,    "\\", "/", 0)
logFileJ$      = replace_regex$ (logFile$,      "\\", "/", 0)
configFileJ$   = replace_regex$ (configFile$,   "\\", "/", 0)

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python performance script at: " + pythonScript$ + newline$ + "Verify installation paths."
endif

# ---- PYTHON DEPENDENCY VALIDATION ----
probeOkFile$  = temporaryDirectory$ + "/temp_launcher_probe.ok"
probeOkFileJ$ = replace_regex$ (probeOkFile$, "\\", "/", 0)

if fileReadable(probeOkFile$)
    deleteFile: probeOkFile$
endif

probeCmd$ = pythonCmd$ + " -c ""import tkinter, numpy, sounddevice, soundfile; open('""" + probeOkFileJ$ + """', 'w').write('OK')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeOkFile$)
    exitScript: "Missing Python dependencies. The performance engine requires: tkinter, numpy, sounddevice, soundfile." + newline$ + "Install with:  python -m pip install sounddevice soundfile numpy"
endif
deleteFile: probeOkFile$

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable (manifestFile$)
        deleteFile: manifestFile$
    endif
    if fileReadable (errorFile$)
        deleteFile: errorFile$
    endif
    for c_i from 1 to nSounds
        tmpWav$ = temporaryDirectory$ + "/temp_launcher_clip_" + string$ (c_i) + ".wav"
        if fileReadable (tmpWav$)
            deleteFile: tmpWav$
        endif
    endfor
endproc

# Clear residual metadata definitions
@cleanUpTempFiles

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
manifest$ = manifest$ + "  ""plugin_version"": ""1.3""," + nl$
manifest$ = manifest$ + "  ""project_sample_rate"": " + string$ (targetSR) + "," + nl$
manifest$ = manifest$ + "  ""project_max_channels"": " + string$ (maxChannels) + "," + nl$
manifest$ = manifest$ + "  ""temp_dir"": """ + replace_regex$(temporaryDirectory$, "\\", "/", 0) + """," + nl$
manifest$ = manifest$ + "  ""error_file"": """ + errorFileJ$ + """," + nl$
manifest$ = manifest$ + "  ""log_file"": """ + logFileJ$ + """," + nl$
manifest$ = manifest$ + "  ""config_file"": """ + configFileJ$ + """," + nl$
manifest$ = manifest$ + "  ""debug"": 0," + nl$
manifest$ = manifest$ + "  ""clips"": [" + nl$

for i from 1 to nSounds
    safeName'i'$ = replace_regex$ (soundName'i'$, """", "'", 0)
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
appendInfoLine: "=== Performance Launcher 1.3 ==="
appendInfoLine: "Loaded Cues: ", nSounds
appendInfoLine: "Target System Rate: ", targetSR, " Hz"
appendInfoLine: "Max File Channels:  ", maxChannels
if nResampled > 0
    appendInfoLine: "Resample Status:    Converted ", nResampled, " item tracks to sync rates."
else
    appendInfoLine: "Resample Status:    Native matching."
endif
appendInfoLine: "Spawning Thread Engine..."

# ---- Launch Performance Space ----
runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ """ + manifestFile$ + """"

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
appendInfoLine: "Launcher closed cleanly. Temporary buffers flushed."