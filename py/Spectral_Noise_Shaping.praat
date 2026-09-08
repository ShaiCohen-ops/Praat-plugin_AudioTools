# ============================================================
# Praat AudioTools - Spectral_Noise_Shaping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.4.1 (2026) - folder chooser + robust visualization summary
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

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/praat_spectral_gen.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: praat_spectral_gen.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

runTag$ = string$(randomInteger(100000, 999999))
resultWav$   = tempDir$ + "specgen_" + runTag$ + "_output.wav"
statsTxt$    = tempDir$ + "specgen_" + runTag$ + "_stats.txt"
profileCSV$  = tempDir$ + "specgen_" + runTag$ + "_profile.csv"
envelopeCSV$ = tempDir$ + "specgen_" + runTag$ + "_envelope.csv"
summaryCSV$  = tempDir$ + "specgen_" + runTag$ + "_summary.csv"
pyLog$       = tempDir$ + "specgen_" + runTag$ + "_python.log"
probePy$     = tempDir$ + "specgen_" + runTag$ + "_probe.py"
probeMarker$ = tempDir$ + "specgen_" + runTag$ + "_probe.ok"

resultWavJ$   = replace_regex$(resultWav$,    "\\", "/", 0)
statsTxtJ$    = replace_regex$(statsTxt$,     "\\", "/", 0)
profileCSVJ$  = replace_regex$(profileCSV$,   "\\", "/", 0)
envelopeCSVJ$ = replace_regex$(envelopeCSV$, "\\", "/", 0)
summaryCSVJ$  = replace_regex$(summaryCSV$,  "\\", "/", 0)
pyLogJ$       = replace_regex$(pyLog$,        "\\", "/", 0)
probePyJ$     = replace_regex$(probePy$,      "\\", "/", 0)
probeMarkerJ$ = replace_regex$(probeMarker$,  "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(resultWav$)
        deleteFile: resultWav$
    endif
    if fileReadable(statsTxt$)
        deleteFile: statsTxt$
    endif
    if fileReadable(profileCSV$)
        deleteFile: profileCSV$
    endif
    if fileReadable(envelopeCSV$)
        deleteFile: envelopeCSV$
    endif
    if fileReadable(summaryCSV$)
        deleteFile: summaryCSV$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
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
form Spectral Noise Shaping v1.4.1
    comment === INPUT ===
    comment (Leave blank to choose a folder after Apply)
    sentence Input_folder

    comment === OUTPUT ===
    positive Duration 3.0
    integer Seed 0
    comment (0 = random seed)

    comment === SPECTRAL SETTINGS ===
    integer N_fft 2048
    integer Hop_length 512
    optionmenu Chunk_preset: 2
        option 1024  —  grainy / fluttery
        option 2048  —  default / balanced
        option 4096  —  smooth / sustained
        option 8192  —  slow / washy
        option Same as N_fft
    real Variation 0.5
    comment (0 = stable corpus mean / 1 = maximum learned frame variation)

    comment === AUDIO ===
    integer Sample_rate 44100

    comment === OUTPUT OPTIONS ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- FOLDER DISCOVERY + VALIDATE ----
# Typed path wins; a blank field opens the folder chooser after Apply.
inputDirectory$ = replace_regex$(input_folder$, "^[ 	]*|[ 	]*$", "", 0)
if inputDirectory$ == ""
    inputDirectory$ = chooseFolder$: "Select audio corpus folder"
    inputDirectory$ = replace_regex$(inputDirectory$, "^[ \t]*|[ \t]*$", "", 0)
endif

if inputDirectory$ == ""
    @cleanUpTempFiles
    exitScript: "Operation cancelled. Please choose an audio corpus folder or type its path in Input_folder."
endif

if not folderExists(inputDirectory$)
    @cleanUpTempFiles
    exitScript: "Input folder not found: " + inputDirectory$
endif
if variation < 0 or variation > 1
    @cleanUpTempFiles
    exitScript: "Variation must be between 0 and 1."
endif
if n_fft < 64
    @cleanUpTempFiles
    exitScript: "N_fft must be at least 64."
endif
if hop_length < 1
    @cleanUpTempFiles
    exitScript: "Hop_length must be at least 1 sample."
endif
if sample_rate < 8000
    @cleanUpTempFiles
    exitScript: "Sample_rate must be at least 8000 Hz."
endif
if seed < 0
    @cleanUpTempFiles
    exitScript: "Seed must be 0 (random) or a positive integer."
endif

# ---- NORMALIZE RESOLVED INPUT PATH FOR PYTHON ----
inputFolderJ$ = replace_regex$(inputDirectory$, "\\", "/", 0)

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
        ... "Please decrease Hop length or choose a larger preset."
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Noise Shaping v1.4.1 ==="
appendInfoLine: "Folder:     ", inputDirectory$
appendInfoLine: "Duration:   ", fixed$(duration, 2), " s"
appendInfoLine: "Variation:  ", fixed$(variation, 2)
appendInfoLine: "Chunk size: ", string$(effective_chunk), " samples (", fixed$(1000 * effective_chunk / sample_rate, 1), " ms)"
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
cmd$ = cmd$ + " --profile_csv """ + profileCSVJ$ + """"
cmd$ = cmd$ + " --envelope_csv """ + envelopeCSVJ$ + """"
cmd$ = cmd$ + " --summary_csv """ + summaryCSVJ$ + """"

if effective_chunk <> n_fft
    cmd$ = cmd$ + " --chunk_size " + string$(effective_chunk)
endif

if seed > 0
    cmd$ = cmd$ + " --seed " + string$(seed)
endif

cmd$ = cmd$ + " 2> """ + pyLogJ$ + """"
runSystem_nocheck: cmd$

# ===========================================================================
# STAGE 2 — Verify & Import
# ===========================================================================
if not fileReadable(resultWav$)
    errText$ = ""
    if fileReadable(statsTxt$)
        errText$ = readFile$(statsTxt$)
    endif
    if fileReadable(pyLog$)
        errText$ = errText$ + newline$ + readFile$(pyLog$)
    endif
    @cleanUpTempFiles
    exitScript: "Python spectral noise shaping failed." + newline$ + newline$ + errText$
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
# VISUALIZATION — what was learned from the corpus and what was generated
###############################################################################

if draw_visualization and fileReadable(profileCSV$) and fileReadable(envelopeCSV$) and fileReadable(summaryCSV$)
    appendInfoLine: "[3/3] Creating corpus-to-result visualization..."

    profileTable = Read Table from comma-separated file: profileCSV$
    selectObject: profileTable
    nProfileRows = Get number of rows

    envelopeTable = Read Table from comma-separated file: envelopeCSV$
    selectObject: envelopeTable
    nEnvelopeRows = Get number of rows

    # Run-level metadata belongs to its own one-row table.
    summaryTable = Read Table from comma-separated file: summaryCSV$
    selectObject: summaryTable
    corpusFiles = Get value: 1, "files_used"
    corpusDurVis = Get value: 1, "corpus_duration_s"
    profileCountVis = Get value: 1, "profile_bank_size"
    corpusCentroid = Get value: 1, "corpus_centroid_hz"
    outputCentroid = Get value: 1, "output_centroid_hz"
    spectralMatch = Get value: 1, "spectral_match"
    envelopeMatch = Get value: 1, "envelope_match"

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Header band
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Spectral Noise Shaping##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.24, "half",
        ... "Corpus character -> shaped stereo noise  |  variation=" + fixed$(variation, 2)
        ... + "  |  chunk=" + string$(effective_chunk)
        ... + " (" + fixed$(1000 * effective_chunk / sample_rate, 1) + " ms)"

    # Corpus / result summary: user-facing process, not algorithm diagram
    Select outer viewport: 0, 8, 0.64, 1.42
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.965, 0.965, 0.975}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.03, "left", 0.70, "half",
        ... "##Corpus learned##  " + string$(round(corpusFiles)) + " files  |  "
        ... + fixed$(corpusDurVis, 1) + " s  |  " + string$(round(profileCountVis)) + " spectral snapshots"
    Font size: 6
    Colour: "{0.30, 0.30, 0.38}"
    Text: 0.03, "left", 0.28, "half",
        ... "Spectral centre " + fixed$(corpusCentroid, 0) + " -> " + fixed$(outputCentroid, 0) + " Hz"
        ... + "  |  spectrum match " + fixed$(100 * spectralMatch, 1) + "%"
        ... + "  |  envelope match " + fixed$(100 * envelopeMatch, 1) + "%"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Learned spectral character vs generated mean spectrum
    fMax = sample_rate / 2
    if fMax > 20000
        fMax = 20000
    endif
    fMin = 50
    xMin = log10(fMin)
    xMax = log10(fMax)
    Select outer viewport: 0, 8, 1.54, 3.44
    Select inner viewport: 0.68, 7.68, 1.68, 3.30
    Axes: xMin, xMax, 0, 1
    Paint rectangle: "{0.985, 0.985, 0.985}", xMin, xMax, 0, 1

    havePrev = 0
    for r from 1 to nProfileRows
        selectObject: profileTable
        hz = Get value: r, "frequency_hz"
        corpV = Get value: r, "corpus_mean"
        outV = Get value: r, "output_mean"
        if hz >= fMin and hz <= fMax
            xx = log10(hz)
            if havePrev = 1
                Colour: "{0.12, 0.35, 0.72}"
                Line width: 1.5
                Draw line: prevX, prevCorp, xx, corpV
                Colour: "{0.72, 0.25, 0.18}"
                Line width: 1
                Draw line: prevX, prevOut, xx, outV
            endif
            prevX = xx
            prevCorp = corpV
            prevOut = outV
            havePrev = 1
        endif
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Axes: xMin, xMax, 0, 1
    Font size: 6
    for tickI from 1 to 8
        if tickI = 1
            tickF = 50
            tickL$ = "50"
        elsif tickI = 2
            tickF = 100
            tickL$ = "100"
        elsif tickI = 3
            tickF = 200
            tickL$ = "200"
        elsif tickI = 4
            tickF = 500
            tickL$ = "500"
        elsif tickI = 5
            tickF = 1000
            tickL$ = "1k"
        elsif tickI = 6
            tickF = 2000
            tickL$ = "2k"
        elsif tickI = 7
            tickF = 5000
            tickL$ = "5k"
        else
            tickF = 10000
            tickL$ = "10k"
        endif
        if tickF <= fMax
            Text: log10(tickF), "centre", 0.025, "bottom", tickL$
        endif
    endfor
    Font size: 7
    Text left: "yes", "Norm. magnitude"
    Text top: "no", "Spectral character: corpus (blue) -> generated noise (red)"

    # Learned temporal shape vs generated stereo-energy envelope
    Select outer viewport: 0, 8, 3.56, 5.12
    Select inner viewport: 0.68, 7.68, 3.69, 4.99
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, 1, 0, 1
    havePrev = 0
    for r from 1 to nEnvelopeRows
        selectObject: envelopeTable
        tx = Get value: r, "time_norm"
        learnedV = Get value: r, "learned_envelope"
        outputV = Get value: r, "output_rms"
        if havePrev = 1
            Colour: "{0.12, 0.35, 0.72}"
            Line width: 1.5
            Draw line: prevT, prevLearn, tx, learnedV
            Colour: "{0.72, 0.25, 0.18}"
            Line width: 1
            Draw line: prevT, prevRms, tx, outputV
        endif
        prevT = tx
        prevLearn = learnedV
        prevRms = outputV
        havePrev = 1
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Axes: 0, 1, 0, 1
    Font size: 7
    Text left: "yes", "Norm. level"
    Text bottom: "yes", "Normalised time"
    Text top: "no", "Temporal shape: corpus (blue) -> generated stereo energy (red)"

    # Output waveform on explicit fixed scale
    Select outer viewport: 0, 8, 5.23, 6.62
    Select inner viewport: 0.68, 7.68, 5.35, 6.49
    selectObject: resultObj
    Colour: "{0.15, 0.50, 0.35}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Axes: 0, dur_out, -1, 1
    Font size: 7
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Generated stereo result"

    # Compact musical summary
    Select outer viewport: 0, 8, 6.74, 7.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.69, "half", "##Result##  shaped noise inherits the corpus spectrum and temporal contour"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.27, "half",
        ... "Variation " + fixed$(variation, 2)
        ... + "  |  " + fixed$(dur_out, 2) + " s stereo"
        ... + "  |  " + string$(sr_out) + " Hz"
        ... + "  |  spectrum " + fixed$(100 * spectralMatch, 1) + "%"
        ... + "  |  envelope " + fixed$(100 * envelopeMatch, 1) + "%"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: profileTable, envelopeTable, summaryTable
    Font size: 10
    Colour: "Black"
    Line width: 1
else
    appendInfoLine: "[3/3] Visualization skipped or QC summary unavailable."
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
