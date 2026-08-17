# ============================================================
# Praat AudioTools Plugin
# Script:      SPEAR_Fast_Resynthesis.praat
# Author:      Shai Cohen
# Version:     0.7 (2026) - Praat launcher + Fast Python GUI
# License:     MIT License
#
# Architecture follows AudioTools Arranger:
#   Praat -> JSON manifest -> Python GUI/DSP -> WAV + done signal -> Praat.
# Run with zero or one selected Sound. With one Sound, the GUI offers it as
# an analysis source; with no Sound, open SDIF/SPEAR directly in the GUI.
# ============================================================

# ---- Selection: zero or one Sound is allowed ----
nSounds = numberOfSelected("Sound")
if nSounds > 1
    exitScript: "Select at most one Sound object, or select none to open SDIF/SPEAR in the GUI."
endif

praatSoundFile$ = ""
praatSoundName$ = ""
defaultSR = 44100
if nSounds = 1
    praatSound = selected("Sound")
    praatSoundName$ = selected$("Sound")
    defaultSR = Get sampling frequency
endif

# ---- OS-specific Python discovery (same pattern as Arranger) ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
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

# ---- Locate py/spear_fast_gui.py robustly ----
pythonScript$ = preferencesDirectory$ + "/plugin_AudioTools/py/spear_fast_gui.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/py/spear_fast_gui.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/../py/spear_fast_gui.py"
endif
if windows and not fileReadable(pythonScript$)
    oldPlugin$ = environment$("USERPROFILE") + "/Praat/plugin_AudioTools"
    pythonScript$ = oldPlugin$ + "/py/spear_fast_gui.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/spear_fast_gui.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find spear_fast_gui.py." + newline$ +
    ... "Expected it in plugin_AudioTools/py/ or next to this launcher."
endif

# ---- Handshake files ----
manifestFile$ = temporaryDirectory$ + "/temp_spear_fast_manifest.json"
doneFile$     = temporaryDirectory$ + "/temp_spear_fast_done.json"
resultFile$   = temporaryDirectory$ + "/temp_spear_fast_result.wav"
errorFile$    = temporaryDirectory$ + "/temp_spear_fast_error.txt"
reportFile$   = temporaryDirectory$ + "/temp_spear_fast_report.txt"
nameFile$     = temporaryDirectory$ + "/temp_spear_fast_name.txt"
probeOkFile$  = temporaryDirectory$ + "/temp_spear_fast_probe.ok"
stateFile$    = preferencesDirectory$ + "/apps/AudioTools/spear_fast_state.json"
if nSounds = 1
    praatSoundFile$ = temporaryDirectory$ + "/temp_spear_fast_praat_source.wav"
endif

# JSON paths use forward slashes on every OS.
manifestJ$ = replace_regex$(manifestFile$, "\\", "/", 0)
doneJ$     = replace_regex$(doneFile$,     "\\", "/", 0)
resultJ$   = replace_regex$(resultFile$,   "\\", "/", 0)
errorJ$    = replace_regex$(errorFile$,    "\\", "/", 0)
reportJ$   = replace_regex$(reportFile$,   "\\", "/", 0)
nameJ$     = replace_regex$(nameFile$,     "\\", "/", 0)
stateJ$    = replace_regex$(stateFile$,    "\\", "/", 0)
probeJ$    = replace_regex$(probeOkFile$,  "\\", "/", 0)
praatSoundJ$ = replace_regex$(praatSoundFile$, "\\", "/", 0)

procedure cleanUpTempFiles
    if fileReadable(manifestFile$)
        deleteFile: manifestFile$
    endif
    if fileReadable(doneFile$)
        deleteFile: doneFile$
    endif
    if fileReadable(resultFile$)
        deleteFile: resultFile$
    endif
    if fileReadable(errorFile$)
        deleteFile: errorFile$
    endif
    if fileReadable(reportFile$)
        deleteFile: reportFile$
    endif
    if fileReadable(nameFile$)
        deleteFile: nameFile$
    endif
    if fileReadable(probeOkFile$)
        deleteFile: probeOkFile$
    endif
    if praatSoundFile$ <> "" and fileReadable(praatSoundFile$)
        deleteFile: praatSoundFile$
    endif
endproc

@cleanUpTempFiles

# ---- Validate Python GUI + DSP dependencies ----
probeCmd$ = pythonCmd$ + " -c ""import tkinter, numpy; open('""" + probeJ$ + """', 'w').write('OK')"""
runSystem_nocheck: probeCmd$
if not fileReadable(probeOkFile$)
    exitScript: "SPEAR Fast requires Python with tkinter + numpy." + newline$ +
    ... "Python command: " + pythonCmd$
endif
deleteFile: probeOkFile$

# ---- Export optional selected Praat Sound ----
if nSounds = 1
    selectObject: praatSound
    Save as WAV file: praatSoundFile$
endif

safeSoundName$ = replace_regex$(praatSoundName$, """", "'", 0)

# ---- Manifest ----
nl$ = newline$
manifest$ = "{" + nl$
manifest$ = manifest$ + "  ""result_file"": """ + resultJ$ + """," + nl$
manifest$ = manifest$ + "  ""done_file"": """ + doneJ$ + """," + nl$
manifest$ = manifest$ + "  ""error_file"": """ + errorJ$ + """," + nl$
manifest$ = manifest$ + "  ""report_file"": """ + reportJ$ + """," + nl$
manifest$ = manifest$ + "  ""name_file"": """ + nameJ$ + """," + nl$
manifest$ = manifest$ + "  ""state_file"": """ + stateJ$ + """," + nl$
manifest$ = manifest$ + "  ""praat_sound_file"": """ + praatSoundJ$ + """," + nl$
manifest$ = manifest$ + "  ""praat_sound_name"": """ + safeSoundName$ + """," + nl$
manifest$ = manifest$ + "  ""default_sample_rate"": " + string$(defaultSR) + nl$
manifest$ = manifest$ + "}"
writeFile: manifestFile$, manifest$

# ---- Launch GUI; Praat waits and resumes after Render/Cancel ----
clearinfo
appendInfoLine: "=== SPEAR Fast Resynthesis 0.7 ==="
appendInfoLine: "Python: ", pythonCmd$
appendInfoLine: "GUI:    ", pythonScript$
if nSounds = 1
    appendInfoLine: "Praat source available: ", praatSoundName$
else
    appendInfoLine: "Praat source: none (open SDIF/SPEAR in GUI)"
endif
appendInfoLine: ""
appendInfoLine: "Opening SPEAR Fast GUI..."

runSystem_nocheck: pythonCmd$ + " """ + pythonScript$ + """ """ + manifestFile$ + """"

# ---- Error / cancel ----
if fileReadable(errorFile$)
    errMsg$ = readFile$(errorFile$)
    appendInfoLine: "--- Python Error ---"
    appendInfoLine: errMsg$
    appendInfoLine: "--------------------"
    @cleanUpTempFiles
    exitScript: "SPEAR Fast Python engine crashed; see Praat Info."
endif

if not fileReadable(doneFile$)
    appendInfoLine: "Cancelled."
    @cleanUpTempFiles
    exitScript: "SPEAR Fast cancelled."
endif

if not fileReadable(resultFile$)
    @cleanUpTempFiles
    exitScript: "Python reported completion but no rendered WAV was found."
endif

# ---- Import rendered WAV back into Praat ----
resultSound = Read from file: resultFile$
sourceBase$ = "spear_fast"
if fileReadable(nameFile$)
    sourceBase$ = readFile$(nameFile$)
    sourceBase$ = replace_regex$(sourceBase$, "[^A-Za-z0-9_-]", "_", 0)
endif
Rename: sourceBase$ + "_fast"

# Read report before cleanup.
report$ = ""
if fileReadable(reportFile$)
    report$ = readFile$(reportFile$)
endif

@cleanUpTempFiles

selectObject: resultSound
durOut = Get total duration
srOut = Get sampling frequency
rmsOut = Get root-mean-square: 0, 0

appendInfoLine: ""
appendInfoLine: "=== FAST RENDER RETURNED TO PRAAT ==="
if report$ <> ""
    appendInfoLine: report$
endif
appendInfoLine: "Praat object: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(durOut, 3), " s"
appendInfoLine: "SR:       ", srOut, " Hz"
appendInfoLine: "RMS:      ", fixed$(rmsOut, 6)
appendInfoLine: "Done."

selectObject: resultSound
Play
