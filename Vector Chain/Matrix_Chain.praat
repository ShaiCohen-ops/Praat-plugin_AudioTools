# ============================================================
# Praat AudioTools Plugin
# Script:      Matrix_Chain.praat
# Author:      Shai Cohen
# Version:     0.3 (2026)
#
# Changelog v0.3:
#   - The exported input is written with "Save as 32-bit WAV file".  Plain
#     "Save as WAV file" is 16-bit, so the sound was quantised on the way INTO
#     the chain as well as on the way out.
# License:     MIT License
#
# Description:
#   Exports the selected Sound, writes a manifest JSON, launches the Python
#   Matrix Chain host (matrix_chain.py), and imports the rendered result back
#   into Praat.  The host chains up to four AudioTools scripts in series and/or
#   parallel and renders them through ONE headless "praat --run" per click.
#
# Usage:
#   Select exactly one Sound object, then run this script.
#   runSubprocess blocks until the GUI window is closed -- same as Arranger.
#
# Notes:
#   - Praat 7.0 gates file writing, file deletion and subprocess launching
#     behind FULL TRUST.  askForTrust() is called on 7.0+ and is never
#     evaluated on 6.x, where the flag does not exist.
#   - The host needs a Praat executable of its own to run the chain headless.
#     It auto-detects one; set praatExe$ below if your install is elsewhere.
#     Either the executable itself or the FOLDER containing it is accepted.
#     The host also has a "Praat..." button that remembers your choice.
# ============================================================

# ---- EDIT THESE TWO LINES IF YOUR INSTALL IS NON-STANDARD ----
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"
praatExe$     = "C:/Users/User/Desktop/programs/audio"
# --------------------------------------------------------------

# ---- Praat 7 trust ----
if praatVersion >= 7000
    trustGranted = askForTrust()
endif

# ---- Verify selection ----
nSounds = numberOfSelected ("Sound")
if nSounds <> 1
    exitScript: "Please select exactly one Sound object."
endif
snd      = selected ("Sound")
sndName$ = selected$ ("Sound")

selectObject: snd
srcDur = Get total duration
srcSR  = Get sampling frequency
srcCh  = Get number of channels

# ---- Python interpreter candidates (verified cascade, as in Arranger) ----
nPyCand = 1
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

# ---- Paths ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/matrix_chain.py"
if not fileReadable (pythonScript$)
    pythonScript$ = defaultDirectory$ + "/matrix_chain.py"
endif
if not fileReadable (pythonScript$)
    exitScript: "Cannot find matrix_chain.py." + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

inspector$ = replace_regex$ (pythonScript$, "matrix_chain\.py$",
    ... "praat_script_inspector.py", 0)
if not fileReadable (inspector$)
    exitScript: "Cannot find praat_script_inspector.py next to matrix_chain.py."
        ... + newline$ + "Both files belong in plugin_AudioTools/py/."
endif

manifestFile$ = temporaryDirectory$ + "/temp_matrix_manifest.json"
doneFile$     = temporaryDirectory$ + "/temp_matrix_done.json"
resultFile$   = temporaryDirectory$ + "/temp_matrix_result.wav"
errorFile$    = temporaryDirectory$ + "/temp_matrix_error.txt"
inputFile$    = temporaryDirectory$ + "/temp_matrix_input.wav"
probeOkFile$  = temporaryDirectory$ + "/temp_matrix_probe.ok"
probeScript$  = temporaryDirectory$ + "/temp_matrix_probe.py"

# JSON needs forward slashes, even on Windows
manifestFileJ$ = replace_regex$ (manifestFile$, "\\", "/", 0)
doneFileJ$     = replace_regex$ (doneFile$,     "\\", "/", 0)
resultFileJ$   = replace_regex$ (resultFile$,   "\\", "/", 0)
errorFileJ$    = replace_regex$ (errorFile$,    "\\", "/", 0)
inputFileJ$    = replace_regex$ (inputFile$,    "\\", "/", 0)
probeOkFileJ$  = replace_regex$ (probeOkFile$,  "\\", "/", 0)
tempDirJ$      = replace_regex$ (temporaryDirectory$, "\\", "/", 0)
libraryJ$      = replace_regex$ (pluginDir$, "\\", "/", 0)
libraryJ$      = replace_regex$ (libraryJ$, "/$", "", 0)
praatExeJ$     = replace_regex$ (praatExe$, "\\", "/", 0)

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
    if fileReadable (inputFile$)
        deleteFile: inputFile$
    endif
    if fileReadable (probeScript$)
        deleteFile: probeScript$
    endif
    if fileReadable (probeOkFile$)
        deleteFile: probeOkFile$
    endif
endproc

@cleanUpTempFiles

# ---- Python dependency validation (no-shell, file-based probe) ----
# tkinter is required; numpy/soundfile/sounddevice are needed only for
# Audition playback, so the probe reports them rather than rejecting.
writeFileLine:  probeScript$, "import sys"
appendFileLine: probeScript$, "try:"
appendFileLine: probeScript$, "    import tkinter"
appendFileLine: probeScript$, "except Exception:"
appendFileLine: probeScript$, "    sys.exit(1)"
appendFileLine: probeScript$, "opt = []"
appendFileLine: probeScript$, "for m in ('numpy', 'soundfile', 'sounddevice'):"
appendFileLine: probeScript$, "    try:"
appendFileLine: probeScript$, "        __import__(m)"
appendFileLine: probeScript$, "        opt.append(m)"
appendFileLine: probeScript$, "    except Exception:"
appendFileLine: probeScript$, "        pass"
appendFileLine: probeScript$, "open(r'" + probeOkFileJ$ + "', 'w').write(' '.join(opt))"

pythonCmd$ = ""
pySource$  = ""
pyExtras$  = ""
pyTried$   = ""

for iPyCand to nPyCand
    thisPyCand$ = pyCandidate'iPyCand'$
    pyTried$ = pyTried$ + "  - " + thisPyCand$ + newline$
    if pythonCmd$ = ""
        isBarePyCmd = (thisPyCand$ = "python3") or (thisPyCand$ = "python") or (thisPyCand$ = "py")
        if isBarePyCmd or fileReadable (thisPyCand$)
            if fileReadable (probeOkFile$)
                deleteFile: probeOkFile$
            endif
            nocheck runSubprocess: thisPyCand$, probeScript$
            if fileReadable (probeOkFile$)
                pythonCmd$ = thisPyCand$
                pyExtras$  = readFile$ (probeOkFile$)
                if iPyCand = 1
                    pySource$ = "configured venv"
                else
                    pySource$ = "auto-detected"
                endif
            endif
        endif
    endif
endfor

if fileReadable (probeOkFile$)
    deleteFile: probeOkFile$
endif
if fileReadable (probeScript$)
    deleteFile: probeScript$
endif

if pythonCmd$ = ""
    exitScript: "Cannot find Python with tkinter." + newline$ + newline$
        ... + "Tried:" + newline$ + pyTried$ + newline$
        ... + "Tkinter ships with standard Python - if none of the above" + newline$
        ... + "have it, reinstall Python with tcl/tk included, or point" + newline$
        ... + "pyCandidate1$ at a venv that has it."
endif

# ---- Export the selected Sound (the one unavoidable input-side export) ----
# 32-bit, not the 16-bit default: this is the chain's only input quantisation.
selectObject: snd
Save as 32-bit WAV file: inputFile$

# ---- Manifest ----
nl$ = newline$
safeName$ = replace_regex$ (sndName$, "\\", "/", 0)
safeName$ = replace_regex$ (safeName$, """", "'", 0)

manifest$ = "{" + nl$
manifest$ = manifest$ + "  ""source_name"": """ + safeName$     + """," + nl$
manifest$ = manifest$ + "  ""input_file"": """  + inputFileJ$    + """," + nl$
manifest$ = manifest$ + "  ""result_file"": """ + resultFileJ$   + """," + nl$
manifest$ = manifest$ + "  ""done_file"": """   + doneFileJ$     + """," + nl$
manifest$ = manifest$ + "  ""error_file"": """  + errorFileJ$    + """," + nl$
manifest$ = manifest$ + "  ""library_root"": """+ libraryJ$      + """," + nl$
manifest$ = manifest$ + "  ""temp_dir"": """    + tempDirJ$      + """," + nl$
manifest$ = manifest$ + "  ""praat_exe"": """   + praatExeJ$     + """," + nl$
manifest$ = manifest$ + "  ""duration"": "      + fixed$ (srcDur, 6) + "," + nl$
manifest$ = manifest$ + "  ""sample_rate"": "   + string$ (srcSR)    + "," + nl$
manifest$ = manifest$ + "  ""channels"": "      + string$ (srcCh)    + "," + nl$
manifest$ = manifest$ + "  ""timeout"": 300"                              + nl$
manifest$ = manifest$ + "}"

writeFile: manifestFile$, manifest$

# ---- Info log ----
clearinfo
appendInfoLine: "=== AudioTools Matrix Chain 0.3 ==="
appendInfoLine: "Source:     ", sndName$
appendInfoLine: "Duration:   ", fixed$ (srcDur, 3), " s   SR: ", srcSR, " Hz   Channels: ", srcCh
appendInfoLine: "Library:    ", libraryJ$
appendInfoLine: "Python:     ", pythonCmd$, " (", pySource$, ")"
if pyExtras$ = ""
    appendInfoLine: "Playback:   none of numpy/soundfile/sounddevice found -"
    appendInfoLine: "            Audition will render but not play."
else
    appendInfoLine: "Playback:   ", pyExtras$
endif
appendInfoLine: "Host:       ", pythonScript$
appendInfoLine: ""
appendInfoLine: "Opening the Matrix Chain window (Praat waits until you close it)..."

# ---- Launch the host (blocks until the window is closed) ----
nocheck runSubprocess: pythonCmd$, pythonScript$, manifestFile$

# ---- Python crash ----
if fileReadable (errorFile$)
    errMsg$ = readFile$ (errorFile$)
    appendInfoLine: "--- Python Error ---"
    appendInfoLine: errMsg$
    appendInfoLine: "--------------------"
    @cleanUpTempFiles
    exitScript: "Matrix Chain crashed - see the Praat Info window for the traceback."
endif

# ---- No Apply = cancellation ----
if not fileReadable (doneFile$)
    appendInfoLine: "Closed without Apply - nothing imported."
    @cleanUpTempFiles
    exitScript: "Matrix Chain cancelled."
endif

if not fileReadable (resultFile$)
    @cleanUpTempFiles
    exitScript: "Matrix Chain reported success but no result file was written."
endif

# ---- Import ----
appendInfoLine: "Result received. Importing into Praat..."
resultSound = Read from file: resultFile$
selectObject: resultSound

outDur = Get total duration
outCh  = Get number of channels
outSR  = Get sampling frequency
outRMS = Get root-mean-square: 0, 0

outName$ = sndName$ + "_matrix_" + fixed$ (outDur, 1) + "s"
Rename: outName$

@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "--- Output: ", outName$, " ---"
appendInfoLine: "Duration:   ", fixed$ (outDur, 3), " s   Channels: ", outCh
appendInfoLine: "SR:         ", outSR, " Hz"
appendInfoLine: "RMS:        ", fixed$ (outRMS, 6)
if outRMS < 0.0001
    appendInfoLine: "WARNING: the render is silent - check the chain and the host log."
else
    appendInfoLine: "OK"
endif
appendInfoLine: ""
appendInfoLine: "Done."

selectObject: resultSound
Play
