# ============================================================
# Praat AudioTools - CorpusMap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.5 (2026) - Blocking launch with auto-import
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   CataRT-style Corpus Map / Interactive Player.
#
#   Picks a corpus folder, extracts acoustic descriptors for every
#   sound file (RMS, ZCR, Centroid, Bandwidth, Flatness, Rolloff,
#   13 MFCCs, Pitch), projects the corpus to 2-D via PCA, and opens
#   an interactive scatter-plot where clicking or hovering triggers
#   playback of the corresponding file.
#
#   This script BLOCKS while the GUI is open: perform, record
#   (RECORD / STOP & SAVE), then close the GUI window and the latest
#   recorded performance is imported here automatically as a Sound
#   object named "performance".
#
# Python engine: corpus_map.py
#
# Dependencies (Python):
#   pip install numpy librosa sounddevice scikit-learn pyqtgraph PySide6
#
# Changelog v2.5:
#   - Merged the record/import workflow into this single script. The
#     Python GUI is now launched BLOCKING (Praat waits for the window
#     to close) instead of detached. Any stale recording pointer is
#     cleared before launch; after the GUI closes, the latest take (if
#     any) is auto-imported as Sound "performance". No separate import
#     step is needed for the just-recorded take.
#   - Trade-off vs the previous non-blocking design: Praat is occupied
#     while the GUI is open, and only the final take is auto-imported.
#     The companion ImportPerformance.praat is still provided for
#     re-loading the latest take later, and any earlier takes remain in
#     <corpus>/_recordings for manual "Read from file".
#
# Changelog v2.4:
#   - Performance recording handoff. The launch manifest includes
#     "temp_dir" so the Python engine can write a recording pointer file.
#
# Changelog v2.2:
#   - FIXED (Windows): corpus_dir was written into the launch JSON
#     with raw backslashes from chooseDirectory$, producing invalid
#     JSON escapes (\U, \f, ...) that broke Python's json.load. The
#     path is now forward-slash normalized (corpusDirJ$).
#   - FIXED: probe command had stray double-quote literals before the
#     marker and error paths ("...\" \"\"<marker>\"..."), which the
#     shell/argv parser mis-split, so the success marker was written
#     to the wrong path and dependency detection falsely failed even
#     when everything was installed. Now: "<probe>" "<marker>" "<error>".
#   - FIXED: launch command had the same stray-quote bug before the
#     launch-JSON path, so the GUI received a garbled argument. Now:
#     "<corpus_map.py>" "<launch.json>".
#   - FIXED: the GUI was launched with 'runSystem_bg', which is not a
#     Praat command ("Unknown function"). Replaced with a portable
#     non-blocking launch: cmd /c start "" ... on Windows, trailing
#     ' &' on macOS/Linux, both via runSystem_nocheck.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-
#   Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# OS-Specific Python Discovery
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
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ============================================================
# Paths Setup
# ============================================================
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/corpus_map.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/corpus_map.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find corpus_map.py." + newline$ + "Expected at: " + pluginDir$ + "py/"
endif

# --- Pick the corpus folder ---
corpusDir$ = chooseDirectory$("Select Corpus Folder (WAV/FLAC/AIFF)")
if corpusDir$ = ""
    exitScript: "Operation cancelled."
endif

# JSON requires unified forward slashes: chooseDirectory$ returns
# backslash paths on Windows (e.g. C:\Users\...), and \U \f \c etc.
# are invalid/erroneous JSON escapes that break Python's json.load.
corpusDirJ$ = replace_regex$(corpusDir$, "\\", "/", 0)

# ============================================================
# Temp file paths
# ============================================================
launchFile$    = temporaryDirectory$ + "/temp_corpusmap_launch.json"
probeMarker$   = temporaryDirectory$ + "/temp_corpusmap_probe.ok"
probeScript$   = temporaryDirectory$ + "/temp_corpusmap_probe.py"
probeError$    = temporaryDirectory$ + "/temp_corpusmap_probe_error.txt"

# ============================================================
# Cleanup Procedure
# ============================================================
procedure cleanUpTempFiles
    if fileReadable(launchFile$)
        deleteFile: launchFile$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(probeScript$)
        deleteFile: probeScript$
    endif
    if fileReadable(probeError$)
        deleteFile: probeError$
    endif
endproc

@cleanUpTempFiles

# ============================================================
# Check Python Dependencies
# ============================================================
clearinfo
writeInfoLine: "=== Corpus Map v2.5 ==="
appendInfoLine: "Corpus folder: ", corpusDir$
appendInfoLine: "[1/2] Detecting Python and dependencies..."

# Write probe script to disk — avoids ALL shell quoting of paths.
# argv[1] = marker path  argv[2] = error-detail path
# On success  : writes 'ok' to argv[1]
# On failure  : writes a human-readable message to argv[2]
writeFile: probeScript$,
    ... "import sys" + newline$ +
    ... "marker_path = sys.argv[1]" + newline$ +
    ... "error_path  = sys.argv[2]" + newline$ +
    ... "pkgs = ['numpy','librosa','sounddevice','sklearn','pyqtgraph','PySide6']" + newline$ +
    ... "missing = []" + newline$ +
    ... "for pkg in pkgs:" + newline$ +
    ... "    try:" + newline$ +
    ... "        __import__(pkg)" + newline$ +
    ... "    except ImportError:" + newline$ +
    ... "        missing.append(pkg)" + newline$ +
    ... "    except Exception as e:" + newline$ +
    ... "        missing.append(pkg + ' (error: ' + str(e) + ')')" + newline$ +
    ... "if not missing:" + newline$ +
    ... "    open(marker_path, 'w').write('ok')" + newline$ +
    ... "else:" + newline$ +
    ... "    open(error_path, 'w').write('Missing: ' + ', '.join(missing))" + newline$

# ── Try pythonCmd$ first, then fall back to 'py' (Windows launcher) ──
# Each path is wrapped in a single pair of double-quotes, space-separated:
#   "<probe.py>" "<marker>" "<error>"
probeArgs$ = " """ + probeScript$ + """ """ + probeMarker$ + """ """ + probeError$ + """"
runSystem_nocheck: pythonCmd$ + probeArgs$

if not fileReadable(probeMarker$) and windows
    runSystem_nocheck: "py" + probeArgs$
    if fileReadable(probeMarker$)
        pythonCmd$ = "py"
    endif
endif

if not fileReadable(probeMarker$)
    # Try to surface the real reason
    diagMsg$ = "pip install numpy librosa sounddevice scikit-learn pyqtgraph PySide6"
    if fileReadable(probeError$)
        diagMsg$ = readFile$(probeError$) + newline$ + newline$ + "Run:  pip install numpy librosa sounddevice scikit-learn pyqtgraph PySide6"
    elsif windows
        diagMsg$ = "Python not found on PATH (tried 'python' and 'py')." + newline$ +
            ... "Install Python from https://python.org and tick 'Add to PATH'." + newline$ + newline$ +
            ... "Then run:  pip install numpy librosa sounddevice scikit-learn pyqtgraph PySide6"
    endif
    @cleanUpTempFiles
    exitScript: diagMsg$
endif

deleteFile: probeMarker$
deleteFile: probeScript$
appendInfoLine: "  Python found: ", pythonCmd$

# ============================================================
# Write launch file and run Python (BLOCKING)
# ============================================================
appendInfoLine: "[2/2] Launching Corpus Map GUI..."

writeFile: launchFile$,
    ... "{" + newline$ +
    ... "  ""corpus_dir"": """ + corpusDirJ$ + """," + newline$ +
    ... "  ""temp_dir"": """ + replace_regex$(temporaryDirectory$, "\\", "/", 0) + """" + newline$ +
    ... "}" + newline$

# Clear any recording pointer from a PREVIOUS session before launching,
# so that after the GUI closes we only import a take recorded THIS time.
pointerFile$ = temporaryDirectory$ + "/corpusmap_last_recording.txt"
if fileReadable(pointerFile$)
    deleteFile: pointerFile$
endif

appendInfoLine: ""
appendInfoLine: "=== GUI OPEN ==="
appendInfoLine: "Praat is waiting while you perform."
appendInfoLine: "Record in the GUI (RECORD / STOP & SAVE), then close the"
appendInfoLine: "window to return here and auto-import your latest take."

# Blocking launch: runSystem_nocheck waits for Python to exit (i.e. for
# the GUI window to close) before continuing. No 'start' / '&' here -- that
# is what makes it block. Works the same on Windows and macOS/Linux.
runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ """ + launchFile$ + """"

# ============================================================
# GUI closed -- auto-import the latest recorded performance
# ============================================================
appendInfoLine: ""
if fileReadable(pointerFile$)
    perfPath$ = readFile$(pointerFile$)
    perfPath$ = replace_regex$(perfPath$, "[\n\r\t ]+$", "", 0)
    if perfPath$ <> "" and fileReadable(perfPath$)
        Read from file: perfPath$
        perfSound = selected("Sound")
        selectObject: perfSound
        Rename: "performance"
        appendInfoLine: "=== PERFORMANCE IMPORTED ==="
        appendInfoLine: "File: ", perfPath$
        appendInfoLine: "Object: Sound performance"
    else
        appendInfoLine: "=== DONE ==="
        appendInfoLine: "A recording was flagged but the file was not found:"
        appendInfoLine: perfPath$
    endif
else
    appendInfoLine: "=== DONE ==="
    appendInfoLine: "No performance was recorded this session."
    appendInfoLine: "(In the GUI: RECORD, perform, then STOP & SAVE before closing.)"
endif
