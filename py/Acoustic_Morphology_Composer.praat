# ============================================================
# Praat AudioTools Plugin - Hybrid Systems
# Script:      Acoustic_Morphology_Composer.praat
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email:       shai.cohen@biu.ac.il
# Version:     1.2.1 (2026)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ACOUSTIC MORPHOLOGY COMPOSER
# Geometry-Driven Spectral Transformation and Spatial Resynthesis
#
#     Draw the space.  Shape the sound.  Compose its transformation.
#
# Description:
#   Launches the Python application acoustic_morphology_composer.py for the
#   selected Sound.  In it you draw a 2-D acoustic geometry (walls, obstacles,
#   openings, one source, up to four microphones); a finite-difference
#   time-domain (FDTD) wave simulation computes the impulse response at each
#   microphone, and those responses filter the recording.  Acoustic states can
#   be stored, compared and sequenced on a timeline.  "Return to Praat" in the
#   application sends the results back here as new Sound objects.
#
# Changelog v1.2.1 (2026):
#   - The session folder AMC_session_<n> is removed after every run on
#     Windows too (Praat's deleteFile cannot remove folders there, so the
#     launcher asks Python to remove the empty folder); on Windows sessions
#     now live in the system temp folder (%TEMP%), not the home folder; the
#     dependency probe no longer creates a folder; empty leftovers of earlier
#     versions are removed at the next start.
#
# Changelog v1.2 (2026):
#   - Python side 1.2 (mixing, preview and timeline fixes; see the changelog
#     at the top of acoustic_morphology_composer.py).  Launcher unchanged.
#
# Changelog v1.1 (2026):
#   - The Python side is now a single file (acoustic_morphology_composer.py);
#     no package folders.  Session protocol and outputs unchanged.
#
# Usage:
#   Select exactly one Sound (mono or stereo), run this script.  Praat waits
#   (runSubprocess blocks) until the composer window is closed.
#
# Session protocol (no Objects-list access while Python runs):
#   1. A private session folder is created under the temporary directory.
#   2. The Sound is exported there as a 32-bit float WAV (the original object
#      is never modified), with manifest.json describing the session.
#   3. Python writes its WAVs, then done.json, then done.tsv LAST (atomic
#      rename) - one line per output: kind <TAB> object name <TAB> file.
#   4. Praat imports ONLY what done.tsv lists, and only if the file exists.
#      No done.tsv = cancelled: nothing is imported.  error.txt = Python
#      crashed: its traceback goes to the Info window.
#
# Output objects (names are made collision-safe with a _2, _3 ... suffix):
#   <source>_acoustic_morphology  the rendered Sound
#   Acoustic_IR_A_<mic>, ...      impulse responses (if exported)
#   <source>_layer_<mic>          microphone layers (if exported)
#
# Notes:
#   - Praat 7.0 gates file writing, deletion and subprocesses behind FULL
#     TRUST; askForTrust() is called on 7.0+ only (never evaluated on 6.x).
#   - Two files: this launcher and acoustic_morphology_composer.py, side by
#     side in plugin_AudioTools/py/.  The Python file holds everything else:
#     the acoustic core, the GUI, the manual (Help in the window, or
#     "python acoustic_morphology_composer.py --manual"), the examples and
#     the self-test ("--selftest", add --praat "<this Praat>" for test 9).
#   - Python 3.9+ with PySide6, numpy, scipy, soundfile and pyqtgraph
#     (sounddevice optional, for audition):
#       python -m pip install PySide6 numpy scipy soundfile pyqtgraph sounddevice
#   - Paths with spaces and non-ASCII characters are passed to Python as
#     separate arguments (no shell) and in a JSON manifest.
# ============================================================

form Acoustic Morphology Composer
    comment Select one Sound, press OK: the composer window opens and Praat waits.
    comment Results come back when you press "Return to Praat" in the composer.
    boolean Keep_session_files 0
endform

# ---- EDIT THIS LINE IF YOUR PYTHON ENVIRONMENT IS ELSEWHERE ----
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"
# ----------------------------------------------------------------

# ---- Praat 7 trust ----
if praatVersion >= 7000
    trustGranted = askForTrust ()
endif

# ---- Verify selection ----
if numberOfSelected ("Sound") <> 1 or numberOfSelected () <> 1
    exitScript: "Please select exactly one Sound object."
endif
snd = selected ("Sound")
sndName$ = selected$ ("Sound")
selectObject: snd
srcDur = Get total duration
srcSR = Get sampling frequency
srcCh = Get number of channels
srcN = Get number of samples
if srcCh > 2
    exitScript: "The Sound has " + string$ (srcCh) + " channels; only mono and stereo are supported."
endif
if srcDur < 0.01
    exitScript: "The Sound is shorter than 10 ms."
endif
if srcDur > 1800
    exitScript: "The Sound is longer than 30 minutes."
endif

# ---- Locate the Python application ----
# next to this script (plugin_AudioTools/py/), else the installed plugin folder
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = defaultDirectory$ + "/acoustic_morphology_composer.py"
if not fileReadable (pythonScript$)
    pythonScript$ = pluginDir$ + "py/acoustic_morphology_composer.py"
endif
if not fileReadable (pythonScript$)
    exitScript: "Cannot find acoustic_morphology_composer.py." + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "(it belongs next to this script, in plugin_AudioTools/py/)."
endif

# ---- Temporary folder ----
# On Windows Praat's temporaryDirectory$ can be the user's home folder; the
# system temp folder (%TEMP%) is the right place for short-lived files.
tempBase$ = temporaryDirectory$
if windows
    sysTemp$ = environment$ ("TEMP")
    if sysTemp$ <> ""
        if folderExists (sysTemp$)
            tempBase$ = sysTemp$
        endif
    endif
endif
tempBase$ = replace$ (tempBase$, "\", "/", 0)
sessionTag$ = string$ (randomInteger (100000, 999999))
sessionDir$ = tempBase$ + "/AMC_session_" + sessionTag$
while folderExists (sessionDir$)
    sessionTag$ = string$ (randomInteger (100000, 999999))
    sessionDir$ = tempBase$ + "/AMC_session_" + sessionTag$
endwhile
sessionCreated = 0

manifestFile$ = sessionDir$ + "/manifest.json"
inputFile$ = sessionDir$ + "/input.wav"
doneFile$ = sessionDir$ + "/done.tsv"
doneJson$ = sessionDir$ + "/done.json"
errorFile$ = sessionDir$ + "/error.txt"
aliveFile$ = sessionDir$ + "/alive.txt"
# the dependency probe runs BEFORE the session folder exists (plain files in
# the temp folder), so a missing Python never leaves a folder behind
probeScript$ = tempBase$ + "/AMC_probe_" + sessionTag$ + ".py"
probeOk$ = tempBase$ + "/AMC_probe_" + sessionTag$ + "_ok.txt"
probeMissing$ = tempBase$ + "/AMC_probe_" + sessionTag$ + "_missing.txt"

# ---- Python dependency probe (no shell; result written to a file) ----
writeFileLine: probeScript$, "import sys"
appendFileLine: probeScript$, "req = ('PySide6', 'numpy', 'scipy', 'soundfile', 'pyqtgraph')"
appendFileLine: probeScript$, "missing = []"
appendFileLine: probeScript$, "for m in req:"
appendFileLine: probeScript$, "    try:"
appendFileLine: probeScript$, "        __import__(m)"
appendFileLine: probeScript$, "    except Exception:"
appendFileLine: probeScript$, "        missing.append(m)"
appendFileLine: probeScript$, "opt = []"
appendFileLine: probeScript$, "try:"
appendFileLine: probeScript$, "    import sounddevice"
appendFileLine: probeScript$, "    opt.append('sounddevice')"
appendFileLine: probeScript$, "except Exception:"
appendFileLine: probeScript$, "    pass"
appendFileLine: probeScript$, "ver = '%d.%d' % sys.version_info[:2]"
appendFileLine: probeScript$, "if sys.version_info < (3, 9):"
appendFileLine: probeScript$, "    missing.append('Python >= 3.9 (found ' + ver + ')')"
appendFileLine: probeScript$, "out = sys.argv[2] if missing else sys.argv[1]"
appendFileLine: probeScript$, "txt = ver + (' - missing: ' + ', '.join(missing) if missing else (' + ' + ' '.join(opt) if opt else ''))"
appendFileLine: probeScript$, "open(out, 'w', encoding='utf-8').write(txt)"

nPyCand = 1
if macintosh
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/opt/homebrew/bin/python3"
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

pythonCmd$ = ""
pyInfo$ = ""
pyTried$ = ""
for iPy to nPyCand
    cand$ = pyCandidate'iPy'$
    if pythonCmd$ = ""
        isBare = (cand$ = "python3") or (cand$ = "python") or (cand$ = "py")
        if isBare or fileReadable (cand$)
            if fileReadable (probeOk$)
                deleteFile: probeOk$
            endif
            if fileReadable (probeMissing$)
                deleteFile: probeMissing$
            endif
            nocheck runSubprocess: cand$, probeScript$, probeOk$, probeMissing$
            if fileReadable (probeOk$)
                pythonCmd$ = cand$
                pyInfo$ = readFile$ (probeOk$)
            elsif fileReadable (probeMissing$)
                pyTried$ = pyTried$ + "  - " + cand$ + ": Python " + readFile$ (probeMissing$) + newline$
            else
                pyTried$ = pyTried$ + "  - " + cand$ + ": not found / did not run" + newline$
            endif
        else
            pyTried$ = pyTried$ + "  - " + cand$ + ": file not found" + newline$
        endif
    endif
endfor

if pythonCmd$ = ""
    @cleanUp
    exitScript: "No suitable Python found." + newline$ + newline$
        ... + "Tried:" + newline$ + pyTried$ + newline$
        ... + "Install the requirements into one of them, e.g." + newline$
        ... + "    python -m pip install PySide6 numpy scipy soundfile pyqtgraph sounddevice" + newline$
        ... + "or point pyCandidate1$ at the top of this script to your environment."
endif

# ---- Private session folder (removed again at the end) ----
createFolder: sessionDir$
if not folderExists (sessionDir$)
    @cleanUp
    exitScript: "Cannot create the session folder:" + newline$ + sessionDir$
endif
sessionCreated = 1

# ---- Export the Sound (32-bit float: no quantisation on the way in) ----
selectObject: snd
Save as 32-bit WAV file: inputFile$

# ---- Manifest (JSON; forward slashes; quotes and backslashes escaped) ----
@jsonPath: sessionDir$
sessionJ$ = jsonPath.s$
@jsonPath: inputFile$
inputJ$ = jsonPath.s$
@jsonPath: doneFile$
doneJ$ = jsonPath.s$
@jsonPath: errorFile$
errorJ$ = jsonPath.s$
nameJ$ = replace$ (sndName$, "\", "/", 0)
nameJ$ = replace$ (nameJ$, """", "'", 0)

nl$ = newline$
m$ = "{" + nl$
m$ = m$ + "  ""format"": ""AMC-session-1""," + nl$
m$ = m$ + "  ""source_name"": """ + nameJ$ + """," + nl$
m$ = m$ + "  ""input_file"": """ + inputJ$ + """," + nl$
m$ = m$ + "  ""session_dir"": """ + sessionJ$ + """," + nl$
m$ = m$ + "  ""done_file"": """ + doneJ$ + """," + nl$
m$ = m$ + "  ""error_file"": """ + errorJ$ + """," + nl$
@jsonPath: temporaryDirectory$
m$ = m$ + "  ""cleanup_dirs"": [""" + jsonPath.s$ + """]," + nl$
m$ = m$ + "  ""duration"": " + fixed$ (srcDur, 9) + "," + nl$
m$ = m$ + "  ""sample_rate"": " + string$ (srcSR) + "," + nl$
m$ = m$ + "  ""channels"": " + string$ (srcCh) + "," + nl$
m$ = m$ + "  ""samples"": " + string$ (srcN) + "," + nl$
m$ = m$ + "  ""praat_version"": """ + praatVersion$ + """" + nl$
m$ = m$ + "}"
writeFile: manifestFile$, m$

clearinfo
appendInfoLine: "=== Acoustic Morphology Composer 1.2.1 ==="
appendInfoLine: "Source:   ", sndName$, "  (", fixed$ (srcDur, 3), " s, ", srcSR, " Hz, ", srcCh, " ch)"
appendInfoLine: "Python:   ", pythonCmd$, "  (Python ", pyInfo$, ")"
appendInfoLine: "App:      ", pythonScript$
appendInfoLine: "Session:  ", sessionDir$
appendInfoLine: ""
appendInfoLine: "The composer window is open - Praat waits until you close it."

# ---- Launch (blocks until the window closes) ----
nocheck runSubprocess: pythonCmd$, pythonScript$, manifestFile$

# ---- Python crashed ----
if fileReadable (errorFile$)
    err$ = readFile$ (errorFile$)
    appendInfoLine: ""
    appendInfoLine: "--- Python error ---"
    appendInfoLine: err$
    appendInfoLine: "--------------------"
    @cleanUp
    exitScript: "The composer stopped with an error - see the Info window."
endif

# ---- No completion manifest: cancelled, crashed, or never started ----
if not fileReadable (doneFile$)
    alive$ = ""
    if fileReadable (aliveFile$)
        alive$ = readFile$ (aliveFile$)
    endif
    @cleanUp
    selectObject: snd
    if startsWith (alive$, "closed")
        appendInfoLine: "Closed without 'Return to Praat' - nothing imported."
        exitScript: "Acoustic Morphology Composer: cancelled, nothing imported."
    elsif startsWith (alive$, "running")
        appendInfoLine: "The composer ended unexpectedly (no error report) - nothing imported."
        exitScript: "The composer ended unexpectedly - nothing imported." + newline$
            ... + "Run it from a terminal to see the message:" + newline$
            ... + pythonCmd$ + " """ + pythonScript$ + """"
    else
        appendInfoLine: "The composer did not start - nothing imported."
        exitScript: "The composer did not start (" + pythonCmd$ + ")." + newline$
            ... + "Run it from a terminal to see the message:" + newline$
            ... + pythonCmd$ + " """ + pythonScript$ + """"
    endif
endif

# ---- Import exactly what done.tsv lists ----
listing = Read Strings from raw text file: doneFile$
nLines = Get number of strings
nImported = 0
nSkipped = 0
mainSound = 0
for iLine to nLines
    selectObject: listing
    line$ = Get string: iLine
    tab1 = index (line$, tab$)
    if tab1 > 0
        kind$ = left$ (line$, tab1 - 1)
        rest$ = mid$ (line$, tab1 + 1, length (line$) - tab1)
        tab2 = index (rest$, tab$)
        if tab2 > 0
            objName$ = left$ (rest$, tab2 - 1)
            fileName$ = mid$ (rest$, tab2 + 1, length (rest$) - tab2)
            # only plain file names inside the session folder are accepted
            safe = index (fileName$, "/") = 0 and index (fileName$, "\") = 0 and index (fileName$, "..") = 0
            path$ = sessionDir$ + "/" + fileName$
            if safe and fileReadable (path$)
                imp = Read from file: path$
                @uniqueName: objName$
                selectObject: imp
                Rename: uniqueName.s$
                nImported = nImported + 1
                imp'nImported' = imp
                d = Get total duration
                c = Get number of channels
                fsI = Get sampling frequency
                appendInfoLine: "  + ", uniqueName.s$, "  (", kind$, ", ", fixed$ (d, 3), " s, ", c, " ch, ", fsI, " Hz)"
                if kind$ = "render" and mainSound = 0
                    mainSound = imp
                    mainDur = d
                    mainSR = fsI
                endif
                if not keep_session_files
                    deleteFile: path$
                endif
            else
                nSkipped = nSkipped + 1
                appendInfoLine: "  ! skipped (missing or unsafe file): ", fileName$
            endif
        endif
    endif
endfor
removeObject: listing

# ---- Report ----
appendInfoLine: ""
appendInfoLine: "Imported ", nImported, " Sound(s)", if nSkipped > 0 then ", skipped " + string$ (nSkipped) else "" fi, "."
if mainSound > 0
    if abs (mainSR - srcSR) > 0.5
        appendInfoLine: "WARNING: rendered sample rate ", mainSR, " Hz differs from the source (", srcSR, " Hz)."
    endif
    if abs (mainDur - srcDur) <= 0.5 / srcSR
        appendInfoLine: "Duration preserved: ", fixed$ (mainDur, 6), " s (source ", fixed$ (srcDur, 6), " s)."
    else
        appendInfoLine: "Duration: ", fixed$ (mainDur, 6), " s (source ", fixed$ (srcDur, 6),
            ... " s) - reverberation tail included, as requested in the composer."
    endif
endif
appendInfoLine: "The original Sound '", sndName$, "' was not modified."

@cleanUp

if nImported > 0
    selectObject: imp1
    for k from 2 to nImported
        plusObject: imp'k'
    endfor
    if mainSound > 0
        selectObject: mainSound
    endif
else
    selectObject: snd
endif

# ============================================================
# PROCEDURES
# ============================================================

procedure jsonPath: .p$
    .s$ = replace$ (.p$, "\", "/", 0)
    .s$ = replace$ (.s$, """", "\""", 0)
endproc

# A name no existing object uses: name, name_2, name_3 ...
procedure uniqueName: .base$
    .s$ = .base$
    .k = 1
    .clash = 1
    while .clash
        .clash = 0
        .n = numberOfSelected ()
        for .i to .n
            .sel[.i] = selected (.i)
        endfor
        nocheck select all
        .nAll = numberOfSelected ()
        for .i to .nAll
            .full$ = selected$ (.i)
            .sp = index (.full$, " ")
            if .sp > 0
                if mid$ (.full$, .sp + 1, length (.full$) - .sp) = .s$ and selected (.i) <> imp
                    .clash = 1
                endif
            endif
        endfor
        selectObject: .sel[1]
        for .i from 2 to .n
            plusObject: .sel[.i]
        endfor
        if .clash
            .k = .k + 1
            .s$ = .base$ + "_" + string$ (.k)
        endif
    endwhile
endproc

procedure cleanUp
    if not keep_session_files
        for .f to 9
            if .f = 9
                .p$ = aliveFile$
            elsif .f = 1
                .p$ = manifestFile$
            elsif .f = 2
                .p$ = inputFile$
            elsif .f = 3
                .p$ = doneFile$
            elsif .f = 4
                .p$ = doneJson$
            elsif .f = 5
                .p$ = errorFile$
            elsif .f = 6
                .p$ = probeScript$
            elsif .f = 7
                .p$ = probeOk$
            else
                .p$ = probeMissing$
            endif
            if fileReadable (.p$)
                deleteFile: .p$
            endif
        endfor
        if sessionCreated
            # any outputs Python wrote but Praat did not import (e.g. after an error)
            .lst = Create Strings as file list: "amcLeft", sessionDir$ + "/*"
            .nl = Get number of strings
            for .i to .nl
                selectObject: .lst
                .fn$ = Get string: .i
                deleteFile: sessionDir$ + "/" + .fn$
            endfor
            removeObject: .lst
            # the now empty folder: deleteFile removes it on macOS / Linux, but on
            # Windows Praat's deleteFile cannot remove folders, so Python does it
            # (os.rmdir only ever removes an EMPTY folder)
            deleteFile: sessionDir$
            if folderExists (sessionDir$) and pythonCmd$ <> ""
                nocheck runSubprocess: pythonCmd$, "-c", "import os,sys;os.rmdir(sys.argv[1])", sessionDir$
            endif
        endif
    endif
endproc
