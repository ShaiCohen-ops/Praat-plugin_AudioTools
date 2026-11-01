# ============================================================
# Praat AudioTools - Spectral_Noise_Shaping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5.1 (2026) - replay timeline, hard profile cap, full presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral noise shaping generator (random-phase spectral
#   resynthesis). Analyses a folder of audio files, learns an
#   ORDERED bank of spectral shapes plus their temporal envelopes,
#   then rebuilds sound from white-noise phases. The Generation mode
#   decides how the learned bank becomes musical time:
#     Random cloud          - v1.4 behaviour (random frame blends)
#     Markov spectral walk  - first-order stochastic walk over the
#                             corpus's observed transitions, plus
#                             similarity jumps (no full transition matrix)
#     Morphological replay  - ordered, time-stretched traversal
#     Spectral migration    - path ordered by centroid / flatness
#     Spectral counterpoint - independent L/R walks, adjustable coupling
#
# Changelog 1.5.1 (fix release, no new modes):
#   - FIX: Replay walks each file's full timeline, so silences keep their
#     length and place; speed is exact under frame decimation and padding;
#     single-frame files no longer crash
#   - FIX: Max profiles is a hard cap (per-file budgets); a corpus with
#     more files than the cap is refused with a clear message
#   - FIX: Texture presets now set Variation and Continuity as well as the
#     analysis grid; "Manual" uses the form fields. The Advanced dialog
#     shows the effective values and always wins
#   - FIX: Counterpoint path fidelity measured per channel, plus L/R
#     centroid correlation; QC metrics carry validity flags (no -1 sentinel)
#   - Python is called with runSubprocess (no shell; stderr via --log_file)
#
# Changelog 1.5.0:
#   - FIX: spectrum QC used a fixed 2048 window, so 4096/8192 presets
#     reported falsely low matches; it now uses the analysis pipeline
#   - NEW: Temporal structure metric (slow-scale spectral movement,
#     output / corpus) and path fidelity (intended vs realised centroid)
#   - NEW: Texture presets replace the chunk-size menu
#   - NEW: Spectral continuity, Envelope mode, Corpus weighting
#   - FIX: success requires Python's done marker, not just a WAV
#   - FIX: files streamed one at a time; profile bank capped
#     (order-preserving decimation); stereo sources power-averaged
#   - FFT / hop / sample rate moved to the Advanced dialog
#   - v1.4.1 sound: mode Random cloud, continuity 0, weighting By duration
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
trajCSV$     = tempDir$ + "specgen_" + runTag$ + "_trajectory.csv"
summaryCSV$  = tempDir$ + "specgen_" + runTag$ + "_summary.csv"
doneFile$    = tempDir$ + "specgen_" + runTag$ + "_done.ok"
pyLog$       = tempDir$ + "specgen_" + runTag$ + "_python.log"
probePy$     = tempDir$ + "specgen_" + runTag$ + "_probe.py"
probeMarker$ = tempDir$ + "specgen_" + runTag$ + "_probe.ok"

resultWavJ$   = replace_regex$(resultWav$,   "\\", "/", 0)
statsTxtJ$    = replace_regex$(statsTxt$,    "\\", "/", 0)
profileCSVJ$  = replace_regex$(profileCSV$,  "\\", "/", 0)
envelopeCSVJ$ = replace_regex$(envelopeCSV$, "\\", "/", 0)
trajCSVJ$     = replace_regex$(trajCSV$,     "\\", "/", 0)
summaryCSVJ$  = replace_regex$(summaryCSV$,  "\\", "/", 0)
doneFileJ$    = replace_regex$(doneFile$,    "\\", "/", 0)
pyLogJ$       = replace_regex$(pyLog$,       "\\", "/", 0)
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
    if fileReadable(profileCSV$)
        deleteFile: profileCSV$
    endif
    if fileReadable(envelopeCSV$)
        deleteFile: envelopeCSV$
    endif
    if fileReadable(trajCSV$)
        deleteFile: trajCSV$
    endif
    if fileReadable(summaryCSV$)
        deleteFile: summaryCSV$
    endif
    if fileReadable(doneFile$)
        deleteFile: doneFile$
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

# ---- PERCENT / N.A. LABEL FOR PICTURE TEXT ----
procedure pctLabel: .v
    if .v < 0
        .s$ = "n/a"
    else
        .s$ = fixed$(100 * .v, 1) + "\% "
    endif
endproc

@cleanUpTempFiles

# ===========================================================================
# STAGE 0 — Python Probe (file-based, runs before form)
# ===========================================================================

# Each candidate is an executable plus one flag ("-u" = unbuffered, harmless;
# "-3" selects Python 3 through the Windows py launcher).
if windows
    nCandidates = 4
    candidate1$ = "python"
    candFlag1$ = "-u"
    candidate2$ = "py"
    candFlag2$ = "-u"
    candidate3$ = "py"
    candFlag3$ = "-3"
    candidate4$ = "python3"
    candFlag4$ = "-u"
else
    nCandidates = 3
    candidate1$ = "python3"
    candFlag1$ = "-u"
    candidate2$ = "python"
    candFlag2$ = "-u"
    candidate3$ = "py"
    candFlag3$ = "-u"
    candidate4$ = ""
    candFlag4$ = ""
endif

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, scipy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

pythonCmd$ = ""
pythonFlag$ = ""
for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
        tryFlag$ = candFlag1$
    elsif iCand = 2
        tryCmd$ = candidate2$
        tryFlag$ = candFlag2$
    elsif iCand = 3
        tryCmd$ = candidate3$
        tryFlag$ = candFlag3$
    else
        tryCmd$ = candidate4$
        tryFlag$ = candFlag4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    nocheck runSubprocess: tryCmd$, tryFlag$, probePyJ$

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        pythonFlag$ = tryFlag$
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
form Spectral Noise Shaping v1.5.1
    comment Corpus folder (leave blank to choose after Apply)
    sentence Input_folder
    optionmenu Generation_mode: 2
        option Random cloud (v1.4 classic)
        option Markov spectral walk
        option Morphological replay
        option Spectral migration — rising
        option Spectral migration — falling
        option Spectral migration — arch
        option Spectral migration — valley
        option Spectral counterpoint
    optionmenu Texture_preset: 1
        option Manual (fields below, grid 2048 / 512)
        option Stable portrait
        option Granular flutter
        option Diffuse cloud
        option Slow wash
    positive Duration 3.0
    integer Seed 0
    real Variation 0.7
    real Spectral_continuity 0.75
    comment (Manual only: presets set their own; Advanced shows and overrides all)
    optionmenu Envelope: 1
        option Auto (follow trajectory in Replay)
        option Learned mean
        option Follow trajectory
        option Flat
    optionmenu Corpus_weighting: 1
        option Equal per file
        option By duration (v1.4)
    boolean Show_advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- RESOLVE TEXTURE PRESET ----
# A named preset is a complete snapshot (grid + Variation + Continuity) and
# replaces the two form fields; Manual uses the form fields. Starting values
# to be judged by ear, not listening-tested settings.
if texture_preset = 2
    chunk_size = 4096
    hop_length = 512
    variation = 0.10
    spectral_continuity = 0.95
elsif texture_preset = 3
    chunk_size = 1024
    hop_length = 256
    variation = 0.85
    spectral_continuity = 0.20
elsif texture_preset = 4
    chunk_size = 2048
    hop_length = 512
    variation = 0.70
    spectral_continuity = 0.50
elsif texture_preset = 5
    chunk_size = 8192
    hop_length = 1024
    variation = 0.25
    spectral_continuity = 0.95
else
    chunk_size = 2048
    hop_length = 512
endif
n_fft = chunk_size
presetChunk = chunk_size
presetHop = hop_length
presetVariation = variation
presetContinuity = spectral_continuity

# Advanced defaults (initialised before any pause, so every build has them)
sample_rate = 44100
max_profiles = 20000
replay_stretch = 0
migration_feature = 1
stereo_coupling = 0.3

# ---- ADVANCED DIALOG (pre-filled with the preset, Standards restores it) ----
if show_advanced_settings
    advClicked = 2
    while advClicked = 2
        beginPause: "Spectral Noise Shaping — Advanced"
            comment: "Effective values (from the preset or the form); edits here win"
            real: "Variation", string$(variation)
            real: "Spectral continuity", string$(spectral_continuity)
            comment: "Analysis / synthesis grid (chunk: power of 2, at least 2 x hop)"
            integer: "N fft", string$(n_fft)
            integer: "Chunk size", string$(chunk_size)
            integer: "Hop length", string$(hop_length)
            integer: "Sample rate", string$(sample_rate)
            integer: "Max profiles", string$(max_profiles)
            comment: "Mode options"
            real: "Replay stretch", string$(replay_stretch)
            comment: "(Replay: 0 = fit one source file to Duration; 2 = half speed)"
            optionMenu: "Migration feature", migration_feature
                option: "Centroid (dark - bright)"
                option: "Flatness (tonal - noisy)"
            real: "Stereo coupling", string$(stereo_coupling)
            comment: "(Counterpoint: 0 = independent L/R, 1 = locked)"
        advClicked = endPause: "Cancel", "Standards", "OK", 3, 1
        if advClicked = 2
            chunk_size = presetChunk
            hop_length = presetHop
            n_fft = presetChunk
            variation = presetVariation
            spectral_continuity = presetContinuity
            sample_rate = 44100
            max_profiles = 20000
            replay_stretch = 0
            migration_feature = 1
            stereo_coupling = 0.3
        endif
    endwhile
    if advClicked = 1
        @cleanUpTempFiles
        exitScript: "Cancelled."
    endif
endif

# ---- FOLDER DISCOVERY + VALIDATE ----
inputDirectory$ = replace_regex$(input_folder$, "^[ \t]*|[ \t]*$", "", 0)
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
if spectral_continuity < 0 or spectral_continuity > 1
    @cleanUpTempFiles
    exitScript: "Spectral continuity must be between 0 and 1."
endif
if seed < 0
    @cleanUpTempFiles
    exitScript: "Seed must be 0 (random) or a positive integer."
endif
if n_fft < 64
    @cleanUpTempFiles
    exitScript: "N fft must be at least 64."
endif
if hop_length < 1
    @cleanUpTempFiles
    exitScript: "Hop length must be at least 1 sample."
endif
if chunk_size < 64 or 2 ^ round(log2(chunk_size)) <> chunk_size
    @cleanUpTempFiles
    exitScript: "Chunk size must be a power of 2 (512, 1024, 2048, 4096, 8192...)."
endif
if chunk_size < 2 * hop_length
    @cleanUpTempFiles
    exitScript: "Chunk size (" + string$(chunk_size) + ") must be at least 2 x Hop length ("
        ... + string$(2 * hop_length) + ")."
endif
if sample_rate < 8000
    @cleanUpTempFiles
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if max_profiles < 100
    @cleanUpTempFiles
    exitScript: "Max profiles must be at least 100."
endif
if stereo_coupling < 0 or stereo_coupling > 1
    @cleanUpTempFiles
    exitScript: "Stereo coupling must be between 0 and 1."
endif
if replay_stretch < 0
    @cleanUpTempFiles
    exitScript: "Replay stretch must be 0 (auto) or positive."
endif

inputFolderJ$ = replace_regex$(inputDirectory$, "\\", "/", 0)

# ---- RESOLVE MODE ----
migDir$ = "rising"
if generation_mode = 1
    mode$ = "random"
    modeLabel$ = "Random cloud"
elsif generation_mode = 2
    mode$ = "walk"
    modeLabel$ = "Markov spectral walk"
elsif generation_mode = 3
    mode$ = "replay"
    modeLabel$ = "Morphological replay"
elsif generation_mode = 8
    mode$ = "counterpoint"
    modeLabel$ = "Spectral counterpoint"
else
    mode$ = "migration"
    if generation_mode = 5
        migDir$ = "falling"
    elsif generation_mode = 6
        migDir$ = "arch"
    elsif generation_mode = 7
        migDir$ = "valley"
    endif
    if migration_feature = 1
        migFeat$ = "centroid"
    else
        migFeat$ = "flatness"
    endif
    modeLabel$ = "Spectral migration (" + migFeat$ + ", " + migDir$ + ")"
endif
if migration_feature = 1
    migFeat$ = "centroid"
else
    migFeat$ = "flatness"
endif

if envelope = 1
    env$ = "auto"
elsif envelope = 2
    env$ = "learned"
elsif envelope = 3
    env$ = "trajectory"
else
    env$ = "flat"
endif
if corpus_weighting = 1
    weight$ = "equal"
else
    weight$ = "duration"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Noise Shaping v1.5.1 ==="
appendInfoLine: "Folder:      ", inputDirectory$
appendInfoLine: "Mode:        ", modeLabel$
appendInfoLine: "Texture:     ", texture_preset$
appendInfoLine: "Duration:    ", fixed$(duration, 2), " s"
if texture_preset = 1
    valSource$ = "form fields"
else
    valSource$ = "preset"
endif
if show_advanced_settings
    valSource$ = valSource$ + ", reviewed in Advanced"
endif
appendInfoLine: "Variation:   ", fixed$(variation, 2), "   Continuity: ", fixed$(spectral_continuity, 2), "   (", valSource$, ")"
appendInfoLine: "Chunk / hop: ", string$(chunk_size), " / ", string$(hop_length), " (", fixed$(1000 * chunk_size / sample_rate, 1), " ms)"
appendInfoLine: "Envelope:    ", env$, "   Weighting: ", weight$
appendInfoLine: "Python:      ", pythonCmd$, " ", pythonFlag$
appendInfoLine: ""

# ===========================================================================
# STAGE 1 — Run Python
# ===========================================================================
appendInfoLine: "[1/3] Running spectral noise shaping engine..."

# No shell: program and arguments are passed separately, so paths with
# spaces or quotes need no escaping. Seed 0 is passed as-is (= random).
nocheck runSubprocess: pythonCmd$, pythonFlag$, pythonScriptJ$,
    ... inputFolderJ$, resultWavJ$, statsTxtJ$,
    ... "--mode", mode$,
    ... "--duration", string$(duration),
    ... "--sr", string$(sample_rate),
    ... "--n_fft", string$(n_fft),
    ... "--chunk_size", string$(chunk_size),
    ... "--hop_length", string$(hop_length),
    ... "--variation", string$(variation),
    ... "--continuity", string$(spectral_continuity),
    ... "--envelope", env$,
    ... "--weighting", weight$,
    ... "--max_profiles", string$(max_profiles),
    ... "--replay_stretch", string$(replay_stretch),
    ... "--migration_feature", migFeat$,
    ... "--migration_direction", migDir$,
    ... "--coupling", string$(stereo_coupling),
    ... "--seed", string$(seed),
    ... "--profile_csv", profileCSVJ$,
    ... "--envelope_csv", envelopeCSVJ$,
    ... "--trajectory_csv", trajCSVJ$,
    ... "--summary_csv", summaryCSVJ$,
    ... "--done_file", doneFileJ$,
    ... "--log_file", pyLogJ$

# ===========================================================================
# STAGE 2 — Verify (explicit done marker) & Import
# ===========================================================================
if not fileReadable(doneFile$) or not fileReadable(resultWav$)
    errText$ = ""
    if fileReadable(statsTxt$)
        errText$ = readFile$(statsTxt$)
    endif
    if fileReadable(pyLog$)
        errText$ = errText$ + newline$ + readFile$(pyLog$)
    endif
    @cleanUpTempFiles
    exitScript: "Python spectral noise shaping did not complete." + newline$ + newline$ + errText$
endif

appendInfoLine: "[2/3] Importing result..."

Read from file: resultWav$
resultObj = selected("Sound")
Rename: "spectral_noise_shaped_" + mode$

selectObject: resultObj
dur_out = Get total duration
sr_out  = Get sampling frequency

appendInfoLine: "  Output: ", fixed$(dur_out, 2), " s  SR: ", string$(sr_out), " Hz"

if fileReadable(statsTxt$)
    appendInfoLine: ""
    appendInfoLine: readFile$(statsTxt$)
endif

###############################################################################
# VISUALIZATION — what was learned, how it moved, what was generated
###############################################################################

haveQC = fileReadable(profileCSV$) and fileReadable(envelopeCSV$) and fileReadable(trajCSV$) and fileReadable(summaryCSV$)

if draw_visualization and haveQC
    appendInfoLine: "[3/3] Creating corpus-to-result visualization..."

    profileTable = Read Table from comma-separated file: profileCSV$
    nProfileRows = Get number of rows
    envelopeTable = Read Table from comma-separated file: envelopeCSV$
    nEnvelopeRows = Get number of rows
    trajTable = Read Table from comma-separated file: trajCSV$
    nTrajRows = Get number of rows
    summaryTable = Read Table from comma-separated file: summaryCSV$
    corpusFiles   = Get value: 1, "files_used"
    corpusDurVis  = Get value: 1, "corpus_duration_s"
    profileCount  = Get value: 1, "profile_bank_size"
    profileStride = Get value: 1, "profile_stride"
    corpusCentroid = Get value: 1, "corpus_centroid_hz"
    outputCentroid = Get value: 1, "output_centroid_hz"
    spectralSim   = Get value: 1, "spectral_similarity"
    envelopeSim   = Get value: 1, "envelope_similarity"
    temporalStr   = Get value: 1, "temporal_structure"
    temporalOK    = Get value: 1, "temporal_structure_valid"
    pathFid       = Get value: 1, "path_fidelity_r"
    pathOK        = Get value: 1, "path_fidelity_r_valid"
    pathFidR      = Get value: 1, "path_fidelity_r_right"
    pathROK       = Get value: 1, "path_fidelity_r_right_valid"
    lrCorr        = Get value: 1, "lr_centroid_correlation"
    lrOK          = Get value: 1, "lr_centroid_correlation_valid"
    replayStretchVis = Get value: 1, "replay_stretch"
    replayOK      = Get value: 1, "replay_stretch_valid"
    specOK        = Get value: 1, "spectral_similarity_valid"
    envOK         = Get value: 1, "envelope_similarity_valid"

    specLab$ = "n/a"
    if specOK = 1
        @pctLabel: spectralSim
        specLab$ = pctLabel.s$
    endif
    envLab$ = "n/a"
    if envOK = 1
        @pctLabel: envelopeSim
        envLab$ = pctLabel.s$
    endif
    tempLab$ = "n/a"
    if temporalOK = 1
        # fixed$ ignores the precision for tiny values (prints 0.0003)
        if temporalStr < 0.005
            tempLab$ = "0.00"
        else
            tempLab$ = fixed$(temporalStr, 2)
        endif
    endif
    pathLab$ = "n/a"
    if pathOK = 1
        pathLab$ = fixed$(pathFid, 2)
    endif
    if mode$ = "counterpoint"
        pathRLab$ = "n/a"
        if pathROK = 1
            pathRLab$ = fixed$(pathFidR, 2)
        endif
        lrLab$ = "n/a"
        if lrOK = 1
            lrLab$ = fixed$(lrCorr, 2)
        endif
        pathLab$ = "L " + pathLab$ + " / R " + pathRLab$ + "  |  L-R centroid r = " + lrLab$
    endif

    colCorpus$ = "{0.12, 0.35, 0.72}"
    colOutput$ = "{0.72, 0.25, 0.18}"
    colPanel$  = "{0.985, 0.985, 0.985}"

    Erase all
    Line width: 1
    Colour: "Black"

    # ---- Title strip ----
    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.10, 0.50
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.72, "half", "##Spectral Noise Shaping##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.10, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.18, "half",
        ... modeLabel$ + "  |  variation " + fixed$(variation, 2)
        ... + "  |  continuity " + fixed$(spectral_continuity, 2)
        ... + "  |  chunk " + string$(chunk_size) + " / hop " + string$(hop_length)
        ... + " (" + fixed$(1000 * chunk_size / sample_rate, 1) + " ms)"
    Colour: "Black"

    # ---- Corpus band ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.65, 1.20
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.965, 0.965, 0.975}", 0, 1, 0, 1
    Text: 0.015, "left", 0.70, "half",
        ... "##Corpus learned##  " + string$(round(corpusFiles)) + " file(s)  |  "
        ... + fixed$(corpusDurVis, 1) + " s  |  " + string$(round(profileCount))
        ... + " ordered spectral frames (stride " + string$(round(profileStride)) + ")  |  weighting " + weight$
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.65, 1.20
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.38}"
    Text: 0.015, "left", 0.27, "half",
        ... "Spectral similarity " + specLab$ + " |  envelope similarity " + envLab$
        ... + " |  temporal structure " + tempLab$ + " (1 = moves like the corpus, 0 = static)"
        ... + "  |  path fidelity r: " + pathLab$
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 0.65, 1.20
    Axes: 0, 1, 0, 1
    Draw inner box

    # ---- Spectrum panel ----
    fMax = sample_rate / 2
    if fMax > 20000
        fMax = 20000
    endif
    fMin = 50
    xMin = log10(fMin)
    xMax = log10(fMax)
    Font size: 7
    Select inner viewport: 0.6, 7.7, 1.55, 2.85
    Axes: xMin, xMax, 0, 1.05
    Paint rectangle: colPanel$, xMin, xMax, 0, 1.05
    havePrev = 0
    for r from 1 to nProfileRows
        selectObject: profileTable
        hz = Get value: r, "frequency_hz"
        corpV = Get value: r, "corpus_mean"
        outV = Get value: r, "output_mean"
        if hz >= fMin and hz <= fMax
            xx = log10(hz)
            if havePrev = 1
                Colour: colCorpus$
                Line width: 1.5
                Draw line: prevX, prevCorp, xx, corpV
                Colour: colOutput$
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
    Select inner viewport: 0.6, 7.7, 1.55, 2.85
    Axes: xMin, xMax, 0, 1.05
    Draw inner box
    Select inner viewport: 0.6, 7.7, 1.55, 2.85
    Axes: xMin, xMax, 0, 1.05
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
            One mark bottom: log10(tickF), "no", "yes", "no", tickL$
        endif
    endfor
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Norm. magnitude"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "##Spectral character##   corpus mean (blue) → generated noise (red)"

    # ---- Envelope panel ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 3.55, 4.45
    Axes: 0, 1, 0, 1.08
    Paint rectangle: colPanel$, 0, 1, 0, 1.08
    havePrev = 0
    for r from 1 to nEnvelopeRows
        selectObject: envelopeTable
        tx = Get value: r, "time_norm"
        targV = Get value: r, "target_envelope"
        outputV = Get value: r, "output_rms"
        if havePrev = 1
            Colour: colCorpus$
            Line width: 1.5
            Draw line: prevT, prevTarg, tx, targV
            Colour: colOutput$
            Line width: 1
            Draw line: prevT, prevRms, tx, outputV
        endif
        prevT = tx
        prevTarg = targV
        prevRms = outputV
        havePrev = 1
    endfor
    Colour: "Black"
    Line width: 1
    Select inner viewport: 0.6, 7.7, 3.55, 4.45
    Axes: 0, 1, 0, 1.08
    Draw inner box
    Select inner viewport: 0.6, 7.7, 3.55, 4.45
    Axes: 0, 1, 0, 1.08
    Font size: 6
    Marks bottom every: 1, 0.25, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Norm. level"
    Text bottom: "yes", "Normalised time"
    Text top: "no", "##Temporal shape##   target envelope (" + env$ + ", blue) → generated stereo energy (red)"

    # ---- Trajectory panel: intended vs realised spectral centroid ----
    trajMin = 1e9
    trajMax = -1e9
    for r from 1 to nTrajRows
        selectObject: trajTable
        act = Get value: r, "active"
        if act = 1
            a = Get value: r, "intended_centroid_hz"
            b = Get value: r, "output_centroid_hz"
            ar = Get value: r, "intended_r_hz"
            br = Get value: r, "output_r_hz"
            trajMin = min(trajMin, a, b, ar, br)
            trajMax = max(trajMax, a, b, ar, br)
        endif
    endfor
    if trajMax <= trajMin
        trajMin = 0
        trajMax = 1000
    endif
    trajPad = 0.08 * (trajMax - trajMin)
    if trajPad < 20
        trajPad = 20
    endif
    yLo = max(0, trajMin - trajPad)
    yHi = trajMax + trajPad
    Font size: 7
    Select inner viewport: 0.6, 7.7, 5.15, 6.15
    Axes: 0, dur_out, yLo, yHi
    Paint rectangle: colPanel$, 0, dur_out, yLo, yHi
    havePrev = 0
    for r from 1 to nTrajRows
        selectObject: trajTable
        tx = Get value: r, "time_s"
        act = Get value: r, "active"
        a = Get value: r, "intended_centroid_hz"
        b = Get value: r, "output_centroid_hz"
        ar = Get value: r, "intended_r_hz"
        br = Get value: r, "output_r_hz"
        if act = 1 and tx >= 0 and tx <= dur_out
            if havePrev = 1
                if mode$ = "counterpoint"
                    Colour: "{0.45, 0.70, 0.95}"
                    Line width: 1.5
                    Draw line: prevT, prevAr, tx, ar
                    Colour: "{0.95, 0.60, 0.35}"
                    Line width: 1
                    Draw line: prevT, prevBr, tx, br
                endif
                Colour: colCorpus$
                Line width: 1.5
                Draw line: prevT, prevA, tx, a
                Colour: colOutput$
                Line width: 1
                Draw line: prevT, prevB, tx, b
            endif
            prevT = tx
            prevA = a
            prevB = b
            prevAr = ar
            prevBr = br
            havePrev = 1
        else
            havePrev = 0
        endif
    endfor
    Colour: "Black"
    Line width: 1
    Select inner viewport: 0.6, 7.7, 5.15, 6.15
    Axes: 0, dur_out, yLo, yHi
    Draw inner box
    Select inner viewport: 0.6, 7.7, 5.15, 6.15
    Axes: 0, dur_out, yLo, yHi
    # round tick steps (1/2/5 x 10^k)
    yStep = 10 ^ floor(log10((yHi - yLo) / 3))
    if (yHi - yLo) / yStep > 15
        yStep = yStep * 5
    elsif (yHi - yLo) / yStep > 7
        yStep = yStep * 2
    endif
    tStep = 10 ^ floor(log10(dur_out / 4))
    if dur_out / tStep > 15
        tStep = tStep * 5
    elsif dur_out / tStep > 7
        tStep = tStep * 2
    endif
    Font size: 6
    Marks left every: 1, yStep, "yes", "yes", "no"
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Centroid (Hz)"
    Text bottom: "yes", "Time (s)"
    if mode$ = "counterpoint"
        trajCap$ = "##Spectral trajectory##   L: intended (blue) → realised (red)   R: intended (light blue) → realised (orange)"
    else
        trajCap$ = "##Spectral trajectory##   intended path (blue) → realised output centroid (red)"
    endif
    Text top: "no", trajCap$

    # ---- Waveform panel (fixed -1..1: output is normalised to peak 0.9) ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 6.85, 7.55
    selectObject: resultObj
    Colour: "{0.15, 0.50, 0.35}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 6.85, 7.55
    Axes: 0, dur_out, -1, 1
    Draw inner box
    Select inner viewport: 0.6, 7.7, 6.85, 7.55
    Axes: 0, dur_out, -1, 1
    Font size: 6
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text top: "no", "##Generated stereo result##"

    # ---- Summary panel ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 8.15, 8.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Text: 0.015, "left", 0.70, "half",
        ... "##Result##  " + modeLabel$ + "  |  " + fixed$(dur_out, 2) + " s stereo  |  "
        ... + string$(sr_out) + " Hz  |  " + texture_preset$
    Font size: 6
    Select inner viewport: 0.6, 7.7, 8.15, 8.75
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    summary2$ = "Spectral centre " + fixed$(corpusCentroid, 0) + " → " + fixed$(outputCentroid, 0) + " Hz"
        ... + "  |  spectrum " + specLab$ + " |  envelope " + envLab$
        ... + " |  temporal structure " + tempLab$
    if mode$ = "replay" and replayOK = 1
        summary2$ = summary2$ + "  |  stretch x" + fixed$(replayStretchVis, 2)
    endif
    if seed > 0
        summary2$ = summary2$ + "  |  seed " + string$(seed)
    endif
    Text: 0.015, "left", 0.27, "half", summary2$
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 8.15, 8.75
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: profileTable, envelopeTable, trajTable, summaryTable
    Font size: 10
    Colour: "Black"
    Line width: 1
    Select outer viewport: 0, 8, 0, 8.9
else
    appendInfoLine: "[3/3] Visualization skipped or QC files unavailable."
endif

# ===========================================================================
# CLEANUP & SUMMARY
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: spectral_noise_shaped_", mode$
appendInfoLine: "Duration: ", fixed$(dur_out, 2), " s  SR: ", string$(sr_out), " Hz"
appendInfoLine: "FFT: ", string$(n_fft), "  Chunk: ", string$(chunk_size), "  Hop: ", string$(hop_length)
appendInfoLine: "Variation: ", fixed$(variation, 2), "  Continuity: ", fixed$(spectral_continuity, 2), "  Seed: ", string$(seed)

selectObject: resultObj

if play_result
    Play
endif
