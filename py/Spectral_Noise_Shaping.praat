# ============================================================
# Praat AudioTools - Spectral_Noise_Shaping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral noise shaping generator. Analyses a folder of
#   audio files, learns their spectral profile and temporal
#   envelope, then generates new audio by shaping white noise
#   to match. No neural networks — finishes in seconds.
#
# Dependencies:
#   Python 3 with numpy, scipy, soundfile
# ============================================================

# ---- PATHS ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/praat_spectral_gen.py"
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

resultWav$   = tempDir$ + "specgen_output.wav"
statsTxt$    = tempDir$ + "specgen_stats.txt"
probePy$     = tempDir$ + "specgen_probe.py"
probeMarker$ = tempDir$ + "specgen_probe.ok"

resultWavJ$   = replace_regex$(resultWav$,   "\\", "/", 0)
statsTxtJ$    = replace_regex$(statsTxt$,    "\\", "/", 0)
probePyJ$     = replace_regex$(probePy$,     "\\", "/", 0)
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(resultWav$)
        deleteFile: resultWav$
    endif
    if fileReadable(statsTxt$)
        deleteFile: statsTxt$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ===========================================================================
# STAGE 0 — Python Probe (file-based, runs before form)
# ===========================================================================

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

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

pythonCmd$ = ""
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

    runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python with numpy, scipy and soundfile." + newline$
        ... + "Install Python 3 and run:  pip install numpy scipy soundfile"
endif

# ---- FORM ----
form Spectral Noise Shaping v1.2
    comment === INPUT ===
    sentence Input_folder D:\sounds\corpus
    comment (folder containing audio files to analyse)

    comment === OUTPUT ===
    positive Duration 3.0
    integer Seed 0
    comment (0 = random seed)

    comment === SPECTRAL SETTINGS ===
    integer N_fft 2048
    integer Hop_length 512
    optionmenu Chunk_preset: 3
        option 1024  —  ~23 ms  (grainy / fluttery)
        option 2048  —  ~46 ms  (default / balanced)
        option 4096  —  ~93 ms  (smooth / sustained)
        option 8192  —  ~186 ms (slow / washy)
        option Same as N_fft
    real Variation 0.5
    comment (0 = pure mean spectrum / 1 = max variation)

    comment === AUDIO ===
    integer Sample_rate 44100

    comment === OUTPUT OPTIONS ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- VALIDATE ----
if not folderExists(input_folder$)
    @cleanUpTempFiles
    exitScript: "Input folder not found: " + input_folder$
endif

# ---- NORMALIZE USER-TYPED INPUT PATH ----
inputFolderJ$ = replace_regex$(input_folder$, "\\", "/", 0)

# ---- RESOLVE CHUNK PRESET ----
if chunk_preset = 1
    effective_chunk = 1024
elsif chunk_preset = 2
    effective_chunk = 2048
elsif chunk_preset = 3
    effective_chunk = 4096
elsif chunk_preset = 4
    effective_chunk = 8192
else
    effective_chunk = n_fft
endif

if effective_chunk < 2 * hop_length
    @cleanUpTempFiles
    exitScript: "Chunk size (" + string$(effective_chunk) + ") is smaller " +
        ... "than 2 x Hop length (" + string$(2 * hop_length) + "). " +
        ... "Please increase Hop length or choose a larger preset."
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Noise Shaping v1.2 ==="
appendInfoLine: "Folder:     ", input_folder$
appendInfoLine: "Duration:   ", fixed$(duration, 2), " s"
appendInfoLine: "Variation:  ", fixed$(variation, 2)
appendInfoLine: "Chunk size: ", string$(effective_chunk), " samples"
appendInfoLine: "Python:     ", pythonCmd$
appendInfoLine: ""

# ===========================================================================
# STAGE 1 — Run Python
# ===========================================================================
appendInfoLine: "[1/3] Running spectral noise shaping engine..."

cmd$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
cmd$ = cmd$ + " """ + inputFolderJ$ + """"
cmd$ = cmd$ + " """ + resultWavJ$   + """"
cmd$ = cmd$ + " """ + statsTxtJ$    + """"
cmd$ = cmd$ + " --duration "   + string$(duration)
cmd$ = cmd$ + " --sr "         + string$(sample_rate)
cmd$ = cmd$ + " --n_fft "      + string$(n_fft)
cmd$ = cmd$ + " --hop_length " + string$(hop_length)
cmd$ = cmd$ + " --variation "  + string$(variation)

if effective_chunk <> n_fft
    cmd$ = cmd$ + " --chunk_size " + string$(effective_chunk)
endif

if seed > 0
    cmd$ = cmd$ + " --seed " + string$(seed)
endif

runSystem_nocheck: cmd$

# ===========================================================================
# STAGE 2 — Verify & Import
# ===========================================================================
if not fileReadable(resultWav$)
    if fileReadable(statsTxt$)
        appendInfoLine: ""
        appendInfoLine: readFile$(statsTxt$)
    endif
    @cleanUpTempFiles
    exitScript: "Python spectral noise shaping failed." + newline$
        ... + "Possible causes:" + newline$
        ... + "  - numpy, scipy or soundfile not installed" + newline$
        ... + "  - No readable audio files found in the input folder" + newline$
        ... + "  - Python not found in PATH" + newline$
        ... + "Check the terminal/console for Python error messages."
endif

appendInfoLine: "[2/3] Importing result..."

Read from file: resultWav$
resultObj = selected("Sound")
Rename: "spectral_noise_shaped"

selectObject: resultObj
dur_out = Get total duration
sr_out  = Get sampling frequency

appendInfoLine: "  Output: ", fixed$(dur_out, 2), " s  SR: ", string$(sr_out), " Hz"

if fileReadable(statsTxt$)
    appendInfoLine: ""
    appendInfoLine: readFile$(statsTxt$)
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[3/3] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Spectral Noise Shaping##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... "variation=" + fixed$(variation, 2)
        ... + "  |  fft=" + string$(n_fft)
        ... + "  |  chunk=" + string$(effective_chunk)
        ... + "  |  dur=" + fixed$(dur_out, 2) + "s"
        ... + "  |  seed=" + string$(seed)

    # === Waveform ===
    Select outer viewport: 0, 8, 0.70, 2.30
    Select inner viewport: 0.55, 7.65, 0.78, 2.22
    selectObject: resultObj
    Colour: "{0.15, 0.50, 0.35}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Generated waveform"

    # === Spectrogram ===
    Select outer viewport: 0, 8, 2.40, 4.60
    Select inner viewport: 0.55, 7.65, 2.50, 4.50
    selectObject: resultObj
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specObj = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specObj
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Spectrogram"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 4.70, 5.30
    Select inner viewport: 0.55, 7.65, 4.76, 5.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##spectral_noise_shaped##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.28, "half",
        ... "Duration: " + fixed$(dur_out, 2) + "s"
        ... + "  SR: " + string$(sr_out) + " Hz"
        ... + "  FFT: " + string$(n_fft)
        ... + "  Chunk: " + string$(effective_chunk)
        ... + "  Hop: " + string$(hop_length)
        ... + "  Var: " + fixed$(variation, 2)
        ... + "  Seed: " + string$(seed)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
else
    appendInfoLine: "[3/3] Visualization skipped."
endif

# ===========================================================================
# CLEANUP & SUMMARY
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: spectral_noise_shaped"
appendInfoLine: "Duration: ", fixed$(dur_out, 2), " s  SR: ", string$(sr_out), " Hz"
appendInfoLine: "FFT: ", string$(n_fft), "  Chunk: ", string$(effective_chunk), "  Hop: ", string$(hop_length)
appendInfoLine: "Variation: ", fixed$(variation, 2), "  Seed: ", string$(seed)

selectObject: resultObj

if play_result
    Play
endif
