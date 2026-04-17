# ============================================================
# Praat AudioTools Plugin
# Script:      Arranger.praat
# Author:      Shai Cohen
# Version:     1.2 (2026) — Unified Cross-Platform Version
# License:     MIT License
#
# Description:
#   Selects one or more Sound objects, exports each as a WAV,
#   writes a manifest JSON, launches the Python arranger GUI,
#   then imports the rendered stereo mix back into Praat.
#
# Usage:
#   Select one or more Sound objects, then run this script.
# ============================================================

# ---- Verify selection ----
nSounds = numberOfSelected ("Sound")
if nSounds < 1
    exitScript: "Please select at least one Sound object."
endif

# ---- Store selected sound IDs ----
for i from 1 to nSounds
    sound'i'      = selected ("Sound", i)
    soundName'i'$ = selected$ ("Sound", i)
endfor

# ---- OS-SPECIFIC PYTHON DISCOVERY  ----
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

# ---- PATHS  ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/arranger.py"

manifestFile$ = temporaryDirectory$ + "/temp_arranger_manifest.json"
doneFile$     = temporaryDirectory$ + "/temp_arranger_done.json"
resultFile$   = temporaryDirectory$ + "/temp_arranger_result.wav"
errorFile$    = temporaryDirectory$ + "/temp_arranger_error.txt"

# JSON string formatting requires forward slashes, even on Windows
manifestFileJ$ = replace_regex$ (manifestFile$, "\\", "/", 0)
resultFileJ$   = replace_regex$ (resultFile$,   "\\", "/", 0)
doneFileJ$     = replace_regex$ (doneFile$,     "\\", "/", 0)
errorFileJ$    = replace_regex$ (errorFile$,    "\\", "/", 0)

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

# ---- PYTHON DEPENDENCY VALIDATION  ----
# We use the dummy file trick, making sure to convert slashes so Windows doesn't interpret them as escape characters
probeOkFile$  = temporaryDirectory$ + "/temp_arranger_probe.ok"
probeOkFileJ$ = replace_regex$ (probeOkFile$, "\\", "/", 0)

if fileReadable(probeOkFile$)
    deleteFile: probeOkFile$
endif

# Tell Python to import tkinter and, if successful, write a dummy file
probeCmd$ = pythonCmd$ + " -c ""import tkinter; open('""" + probeOkFileJ$ + """', 'w').write('OK')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeOkFile$)
    exitScript: "Cannot find Python with tkinter. Tkinter ships with standard Python — please reinstall Python."
endif

deleteFile: probeOkFile$

# ---- CLEANUP PROCEDURE  ----
procedure cleanUpTempFiles
    if fileReadable (manifestFile$)
        deleteFile: manifestFile$
    endif
    if fileReadable (doneFile$)
        deleteFile: doneFile$
    endif
    if fileReadable (resultFile$)
        deleteFile: resultFile$
    endif
    if fileReadable (errorFile$)
        deleteFile: errorFile$
    endif
    for c_i from 1 to nSounds
        tmpWav$ = temporaryDirectory$ + "/temp_arranger_clip_" + string$ (c_i) + ".wav"
        if fileReadable (tmpWav$)
            deleteFile: tmpWav$
        endif
    endfor
endproc

# Run cleanup at the beginning to clear any stale data
@cleanUpTempFiles

# ---- Export each Sound as WAV and collect metadata ----
totalDuration = 0
firstSR       = 0

for i from 1 to nSounds
    selectObject: sound'i'
    dur'i' = Get total duration
    sr'i'  = Get sampling frequency
    nch'i' = Get number of channels
    totalDuration = totalDuration + dur'i'
    if i = 1
        firstSR = sr'i'
    endif

    clipFile'i'$  = temporaryDirectory$ + "/temp_arranger_clip_" + string$ (i) + ".wav"
    clipFileJ'i'$ = replace_regex$ (clipFile'i'$, "\\", "/", 0)

    if fileReadable (clipFile'i'$)
        deleteFile: clipFile'i'$
    endif
    Save as WAV file: clipFile'i'$
endfor

# ---- Build manifest JSON ----
nl$ = newline$
manifest$ = "{" + nl$
manifest$ = manifest$ + "  ""project_duration"": " + fixed$ (totalDuration, 6) + "," + nl$
manifest$ = manifest$ + "  ""sample_rate"": "      + string$ (firstSR)          + "," + nl$
manifest$ = manifest$ + "  ""result_file"": """    + resultFileJ$               + """," + nl$
manifest$ = manifest$ + "  ""done_file"": """      + doneFileJ$                 + """," + nl$
manifest$ = manifest$ + "  ""error_file"": """     + errorFileJ$                + """," + nl$
manifest$ = manifest$ + "  ""clips"": [" + nl$

for i from 1 to nSounds
    safeName'i'$ = replace_regex$ (soundName'i'$, """", "'", 0)

    manifest$ = manifest$ + "    {" + nl$
    manifest$ = manifest$ + "      ""id"": "           + string$ (i - 1)         + "," + nl$
    manifest$ = manifest$ + "      ""name"": """       + safeName'i'$            + """," + nl$
    manifest$ = manifest$ + "      ""filename"": """   + clipFileJ'i'$           + """," + nl$
    manifest$ = manifest$ + "      ""duration"": "     + fixed$ (dur'i', 6)      + "," + nl$
    manifest$ = manifest$ + "      ""channels"": "     + string$ (nch'i')        + "," + nl$
    manifest$ = manifest$ + "      ""sample_rate"": "  + string$ (sr'i')         + "," + nl$
    manifest$ = manifest$ + "      ""default_track"": "+ string$ (i - 1)         + "," + nl$
    manifest$ = manifest$ + "      ""default_start"":  0.0"                             + nl$
    if i < nSounds
        manifest$ = manifest$ + "    }," + nl$
    else
        manifest$ = manifest$ + "    }"  + nl$
    endif
endfor

manifest$ = manifest$ + "  ]" + nl$
manifest$ = manifest$ + "}"

writeFile: manifestFile$, manifest$

# ---- Info log ----
clearinfo
appendInfoLine: "=== Arranger 1.2 ==="
appendInfoLine: "Clips:    ", nSounds
appendInfoLine: "Duration: ", fixed$ (totalDuration, 3), " s"
appendInfoLine: "Python:   ", pythonCmd$
appendInfoLine: "Script:   ", pythonScript$
appendInfoLine: "Manifest: ", manifestFile$
appendInfoLine: ""
appendInfoLine: "Opening arranger GUI..."

# ---- Launch GUI ----
runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ """ + manifestFile$ + """"

# ---- Check for Python error log ----
if fileReadable (errorFile$)
    errMsg$ = readFile$ (errorFile$)
    appendInfoLine: "--- Python Error ---"
    appendInfoLine: errMsg$
    appendInfoLine: "--------------------"
    @cleanUpTempFiles
    exitScript: "Python crashed — see Praat Info window for the traceback."
endif

# ---- Check done signal ----
if not fileReadable (doneFile$)
    appendInfoLine: "Cancelled — cleaning up."
    @cleanUpTempFiles
    exitScript: "Arranger cancelled."
endif

appendInfoLine: "Result received. Importing into Praat..."

# ---- Import rendered mix ----
resultSound = Read from file: resultFile$
Rename: "arrangement"

# ---- Cleanup AND DONE  ----
@cleanUpTempFiles

# ---- Summary ----
selectObject: resultSound
dur_out = Get total duration
rms_out = Get root-mean-square: 0, 0
nch_out = Get number of channels

appendInfoLine: ""
appendInfoLine: "--- Output: arrangement ---"
appendInfoLine: "Duration: ", fixed$ (dur_out, 3), " s   Channels: ", nch_out
appendInfoLine: "RMS:      ", fixed$ (rms_out, 6)
if rms_out < 0.0001
    appendInfoLine: "WARNING: output is silent — check clip paths and render."
else
    appendInfoLine: "OK"
endif
appendInfoLine: ""
appendInfoLine: "Done."

selectObject: resultSound
Play