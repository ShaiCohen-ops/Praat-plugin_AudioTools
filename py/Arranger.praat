# ============================================================
# Praat AudioTools Plugin
# Script:      Arranger.praat
# Author:      Shai Cohen
# Version:     1.3 (2026) - Unified Cross-Platform Version
# License:     MIT License
#
# Description:
#   Selects one or more Sound objects, exports each as a WAV,
#   writes a manifest JSON, launches the Python arranger GUI,
#   then imports the rendered stereo mix back into Praat.
#
# Usage:
#   Select one or more Sound objects, then run this script.
#
# Changelog v1.3:
#
#   TIER 1 (polish):
#     - Version bump 1.2 -> 1.3
#     - Output filename now includes clip count and total duration
#       (e.g. "arrangement_3clips_24.5s") so multiple runs in the
#       same session with different selections produce distinct
#       Praat object names. Same-selection re-runs still go
#       through Praat's automatic _2, _3 de-conflict.
#
#   TIER 2 (real bugs, audio bit-identical for 16-bit same-SR inputs):
#     - FIXED: mixed sample rates produced wrong timing/pitch.
#       v1.2 recorded each clip's SR but used ONLY the FIRST
#       clip's SR (`firstSR`) in the manifest. Python read all
#       WAVs assuming that SR -- so a 48 kHz clip placed after a
#       44.1 kHz clip would play at the wrong tempo.
#       v1.3 finds the MAX SR across the selection, resamples
#       any clip that doesn't match (via a COPY -- originals are
#       untouched), saves the resampled copies, then removes the
#       temporary objects. All clips written at the same SR.
#       For same-SR selections (the common case), Resample is
#       skipped entirely and audio is bit-identical to v1.2.
#
#   Python-side fixes in v1.3 (arranger.py):
#     - 8-bit WAV decoding: now subtracts 128 before scaling
#       (unsigned bytes centered at 128). v1.2 produced a DC
#       offset + 2x amplitude for 8-bit input.
#     - 24-bit WAV (sw=3) is now properly decoded as packed
#       little-endian signed integers. v1.2 fell through to the
#       8-bit branch and produced garbage for any 24-bit input.
#     - 16-bit and 32-bit decoding paths unchanged. Praat saves
#       16-bit by default, so v1.3 is bit-identical to v1.2 in
#       practice for typical AudioTools sessions.
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
probeOkFile$  = temporaryDirectory$ + "/temp_arranger_probe.ok"
probeOkFileJ$ = replace_regex$ (probeOkFile$, "\\", "/", 0)

if fileReadable(probeOkFile$)
    deleteFile: probeOkFile$
endif

probeCmd$ = pythonCmd$ + " -c ""import tkinter; open('""" + probeOkFileJ$ + """', 'w').write('OK')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeOkFile$)
    exitScript: "Cannot find Python with tkinter. Tkinter ships with standard Python -- please reinstall Python."
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

# ---- PASS 1: Collect metadata + find target SR ----
# v1.3: scan all clips first to determine the highest SR. We'll resample
# any non-matching clip to this rate before saving, so all WAVs go to
# Python at a unified sample rate.
totalDuration = 0
maxSR         = 0

for i from 1 to nSounds
    selectObject: sound'i'
    dur'i' = Get total duration
    sr'i'  = Get sampling frequency
    nch'i' = Get number of channels
    totalDuration = totalDuration + dur'i'
    if sr'i' > maxSR
        maxSR = sr'i'
    endif
endfor

targetSR = maxSR

# Count how many will need resampling (for the info log)
nResampled = 0
for i from 1 to nSounds
    if sr'i' <> targetSR
        nResampled = nResampled + 1
    endif
endfor

# ---- PASS 2: Export each Sound as WAV (resample if needed) ----
for i from 1 to nSounds
    clipFile'i'$  = temporaryDirectory$ + "/temp_arranger_clip_" + string$ (i) + ".wav"
    clipFileJ'i'$ = replace_regex$ (clipFile'i'$, "\\", "/", 0)

    if fileReadable (clipFile'i'$)
        deleteFile: clipFile'i'$
    endif

    selectObject: sound'i'

    if sr'i' <> targetSR
        # Resample on a COPY -- the user's original Sound is never
        # modified. Resample creates a new Sound; we save it, then
        # remove it.
        Resample: targetSR, 50
        tmpResampled = selected ("Sound")
        Save as WAV file: clipFile'i'$
        removeObject: tmpResampled
    else
        # SR already matches target -- save the original directly.
        # Audio is bit-identical to v1.2 in this branch.
        Save as WAV file: clipFile'i'$
    endif
endfor

# ---- Build manifest JSON ----
# All clips are now at targetSR after Pass 2, so the manifest reports
# targetSR for both the project and each clip.
nl$ = newline$
manifest$ = "{" + nl$
manifest$ = manifest$ + "  ""project_duration"": " + fixed$ (totalDuration, 6) + "," + nl$
manifest$ = manifest$ + "  ""sample_rate"": "      + string$ (targetSR)        + "," + nl$
manifest$ = manifest$ + "  ""result_file"": """    + resultFileJ$              + """," + nl$
manifest$ = manifest$ + "  ""done_file"": """      + doneFileJ$                + """," + nl$
manifest$ = manifest$ + "  ""error_file"": """     + errorFileJ$               + """," + nl$
manifest$ = manifest$ + "  ""clips"": [" + nl$

for i from 1 to nSounds
    safeName'i'$ = replace_regex$ (soundName'i'$, """", "'", 0)

    manifest$ = manifest$ + "    {" + nl$
    manifest$ = manifest$ + "      ""id"": "           + string$ (i - 1)         + "," + nl$
    manifest$ = manifest$ + "      ""name"": """       + safeName'i'$            + """," + nl$
    manifest$ = manifest$ + "      ""filename"": """   + clipFileJ'i'$           + """," + nl$
    manifest$ = manifest$ + "      ""duration"": "     + fixed$ (dur'i', 6)      + "," + nl$
    manifest$ = manifest$ + "      ""channels"": "     + string$ (nch'i')        + "," + nl$
    manifest$ = manifest$ + "      ""sample_rate"": "  + string$ (targetSR)      + "," + nl$
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
appendInfoLine: "=== Arranger 1.3 ==="
appendInfoLine: "Clips:      ", nSounds
appendInfoLine: "Duration:   ", fixed$ (totalDuration, 3), " s"
appendInfoLine: "Target SR:  ", targetSR, " Hz (max across selection)"
if nResampled > 0
    appendInfoLine: "Resampled:  ", nResampled, " of ", nSounds, " clips to ", targetSR, " Hz"
else
    appendInfoLine: "Resampled:  none (all clips already at target SR)"
endif
appendInfoLine: "Python:     ", pythonCmd$
appendInfoLine: "Script:     ", pythonScript$
appendInfoLine: "Manifest:   ", manifestFile$
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
    exitScript: "Python crashed -- see Praat Info window for the traceback."
endif

# ---- Check done signal ----
if not fileReadable (doneFile$)
    appendInfoLine: "Cancelled -- cleaning up."
    @cleanUpTempFiles
    exitScript: "Arranger cancelled."
endif

appendInfoLine: "Result received. Importing into Praat..."

# ---- Import rendered mix ----
resultSound = Read from file: resultFile$

# v1.3: output filename now embeds clip count + total duration so that
# different selections produce distinct Praat object names. Same
# selection re-runs still rely on Praat's automatic _2, _3 suffixing.
compositeName$ = "arrangement_" + string$ (nSounds) + "clips_" + fixed$ (totalDuration, 1) + "s"
Rename: compositeName$

# ---- Cleanup AND DONE  ----
@cleanUpTempFiles

# ---- Summary ----
selectObject: resultSound
dur_out = Get total duration
rms_out = Get root-mean-square: 0, 0
nch_out = Get number of channels

appendInfoLine: ""
appendInfoLine: "--- Output: ", compositeName$, " ---"
appendInfoLine: "Duration:   ", fixed$ (dur_out, 3), " s   Channels: ", nch_out
appendInfoLine: "SR:         ", targetSR, " Hz"
appendInfoLine: "RMS:        ", fixed$ (rms_out, 6)
if rms_out < 0.0001
    appendInfoLine: "WARNING: output is silent -- check clip paths and render."
else
    appendInfoLine: "OK"
endif
appendInfoLine: ""
appendInfoLine: "Done."

selectObject: resultSound
Play
