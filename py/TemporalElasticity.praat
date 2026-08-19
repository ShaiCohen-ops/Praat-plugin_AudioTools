# ============================================================
# Praat AudioTools - TemporalElasticity.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2.1 (2026) - Windows console compatibility hotfix
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Temporal Elasticity — Latent Time Warping Engine
#
#   Segments a Sound into events, extracts acoustic features,
#   and calls a Python engine that learns a latent space and
#   builds a temporal field to warp event durations.
#   Reconstruction is via PSOLA, resampling, or placement.
#
# Dependencies (Python):
#   pip install numpy soundfile
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

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
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/latent_time_warp.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_time_warp.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_time_warp.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)
runToken$ = string$(sound) + "_" + string$(randomInteger(100000, 999999))
tempBase$ = "temp_te_" + runToken$
patchPrefix$ = tempBase$ + "_patch_"

eventsCSV$    = tempDir$ + tempBase$ + "_events.csv"
durationsCSV$ = tempDir$ + tempBase$ + "_durations.csv"
statsTxt$     = tempDir$ + tempBase$ + "_stats.txt"
probePy$      = tempDir$ + tempBase$ + "_probe.py"
probeMarker$  = tempDir$ + tempBase$ + "_probe.ok"
logTxt$       = tempDir$ + tempBase$ + "_python.log"

pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
durationsCSVJ$ = replace_regex$(durationsCSV$, "\\", "/", 0)
statsTxtJ$     = replace_regex$(statsTxt$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
logTxtJ$       = replace_regex$(logTxt$, "\\", "/", 0)
tempDirJ$      = replace_regex$(tempDir$, "\\", "/", 0)

nEvents = 0

procedure cleanUpTempFiles
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(durationsCSV$)
        deleteFile: durationsCSV$
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
    if fileReadable(logTxt$)
        deleteFile: logTxt$
    endif
    if nEvents > 0
        for .iPatch from 0 to nEvents - 1
            .patchPath$ = tempDir$ + patchPrefix$ + string$(.iPatch) + ".wav"
            if fileReadable(.patchPath$)
                deleteFile: .patchPath$
            endif
        endfor
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Temporal Elasticity v1.2.1
    comment ── Preset ───────────────────────────────────────────────────
    optionmenu Preset: 1
        option Custom
        option Gentle warp
        option Rhythmic stretch
        option Gravitational pull
        option Turbulent scatter
        option Time inversion
        option Spectral drift
        option Deep mutation
        option Relativistic

    comment ── Segmentation ──────────────────────────────────────────────
    positive Silence_threshold_(dB) 25.0
    positive Min_event_duration_(s) 0.05
    positive Min_silence_duration_(s) 0.03

    comment ── Latent space ──────────────────────────────────────────────
    integer Latent_dimensions 4
    integer Training_iterations 120
    optionmenu Latent_method: 1
        option ae
        option pca
    integer Random_seed 42

    comment ── Temporal field ────────────────────────────────────────────
    optionmenu Field_mode: 1
        option gravitational
        option inversion
        option turbulence
        option gradient
        option relativistic
    real Amplitude 0.8
    positive Sigma 1.0
    integer Clusters 3

    comment ── Duration rules ────────────────────────────────────────────
    optionmenu Extra_rules: 1
        option none
        option short_stretch
        option long_compress
        option harmonic_compress
        option noisy_dilate

    comment ── Reconstruction ────────────────────────────────────────────
    optionmenu Reconstruction_method: 1
        option PSOLA
        option resampling
        option placement_only

    comment ── Output ────────────────────────────────────────────────────
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    silence_threshold    = 20.0
    min_event_duration   = 0.04
    min_silence_duration = 0.03
    latent_dimensions    = 4
    training_iterations  = 80
    latent_method        = 1
    random_seed          = 42
    field_mode           = 1
    amplitude            = 0.3
    sigma                = 1.5
    clusters             = 3
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "GentleWarp"
elsif preset = 3
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    latent_dimensions    = 4
    training_iterations  = 100
    latent_method        = 2
    random_seed          = 7
    field_mode           = 4
    amplitude            = 0.6
    sigma                = 1.0
    clusters             = 4
    extra_rules          = 2
    reconstruction_method = 2
    presetName$ = "RhythmicStretch"
elsif preset = 4
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    latent_dimensions    = 6
    training_iterations  = 150
    latent_method        = 1
    random_seed          = 42
    field_mode           = 1
    amplitude            = 1.2
    sigma                = 0.8
    clusters             = 4
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "GravitationalPull"
elsif preset = 5
    silence_threshold    = 20.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    latent_dimensions    = 8
    training_iterations  = 120
    latent_method        = 1
    random_seed          = 99
    field_mode           = 3
    amplitude            = 1.0
    sigma                = 0.6
    clusters             = 5
    extra_rules          = 5
    reconstruction_method = 3
    presetName$ = "TurbulentScatter"
elsif preset = 6
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    latent_dimensions    = 4
    training_iterations  = 120
    latent_method        = 1
    random_seed          = 42
    field_mode           = 2
    amplitude            = 1.0
    sigma                = 1.0
    clusters             = 3
    extra_rules          = 3
    reconstruction_method = 1
    presetName$ = "TimeInversion"
elsif preset = 7
    silence_threshold    = 30.0
    min_event_duration   = 0.08
    min_silence_duration = 0.05
    latent_dimensions    = 6
    training_iterations  = 100
    latent_method        = 2
    random_seed          = 13
    field_mode           = 4
    amplitude            = 0.7
    sigma                = 1.2
    clusters             = 3
    extra_rules          = 4
    reconstruction_method = 2
    presetName$ = "SpectralDrift"
elsif preset = 8
    silence_threshold    = 15.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    latent_dimensions    = 12
    training_iterations  = 200
    latent_method        = 1
    random_seed          = 42
    field_mode           = 1
    amplitude            = 1.8
    sigma                = 0.5
    clusters             = 6
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "DeepMutation"
elsif preset = 9
    silence_threshold    = 20.0
    min_event_duration   = 0.04
    min_silence_duration = 0.02
    latent_dimensions    = 6
    training_iterations  = 150
    latent_method        = 1
    random_seed          = 42
    field_mode           = 5
    amplitude            = 1.2
    sigma                = 1.0
    clusters             = 4
    extra_rules          = 1
    reconstruction_method = 1
    presetName$ = "Relativistic"
else
    presetName$ = "Custom"
endif

# ---- VALIDATE USER CONTROLS ----
latent_dimensions = max(2, min(16, latent_dimensions))
training_iterations = max(20, min(400, training_iterations))
amplitude = max(0, min(3, amplitude))
sigma = max(0.1, min(5, sigma))
clusters = max(1, min(8, clusters))

# ---- MAP OPTION MENUS TO STRINGS ----
if field_mode = 1
    modeStr$ = "gravitational"
elsif field_mode = 2
    modeStr$ = "inversion"
elsif field_mode = 3
    modeStr$ = "turbulence"
elsif field_mode = 4
    modeStr$ = "gradient"
else
    modeStr$ = "relativistic"
endif

if latent_method = 1
    methodStr$ = "ae"
else
    methodStr$ = "pca"
endif

if extra_rules = 1
    rulesStr$ = "none"
elsif extra_rules = 2
    rulesStr$ = "short_stretch"
elsif extra_rules = 3
    rulesStr$ = "long_compress"
elsif extra_rules = 4
    rulesStr$ = "harmonic_compress"
else
    rulesStr$ = "noisy_dilate"
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Temporal Elasticity v1.2.1 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Mode:    ", modeStr$, "  Method: ", methodStr$
appendInfoLine: "Rules:   ", rulesStr$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz"
appendInfoLine: ""

# ===========================================================================
# Stage 0 — Early Python Dependency Probe
# ===========================================================================
appendInfoLine: "[0/5] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

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
        iCand = nCandidates + 1 ; Break early
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 1 — Segment into events
# ===========================================================================
appendInfoLine: "[1/5] Segmenting events..."

# Use the strongest REAL channel for segmentation. Arithmetic fold-down can
# cancel anti-phase stereo and create false silence boundaries.
analysisChannel = 1
bestChannelRms = -1
if nChannels > 1
    for iCh from 1 to nChannels
        selectObject: sound
        chTmp = Extract one channel: iCh
        selectObject: chTmp
        chRms = Get root-mean-square: 0, 0
        if chRms > bestChannelRms
            bestChannelRms = chRms
            analysisChannel = iCh
        endif
        removeObject: chTmp
    endfor
    selectObject: sound
    Extract one channel: analysisChannel
    analysisSound = selected("Sound")
else
    selectObject: sound
    Copy: "te_analysis"
    analysisSound = selected("Sound")
endif
appendInfoLine: "  Analysis channel: ", analysisChannel

selectObject: analysisSound
tg = To TextGrid (silences): 100, 0, -silence_threshold, min_silence_duration,
    ... min_event_duration, "silent", "sounding"

nInt    = Get number of intervals: 1
nEvents = 0

for iInt from 1 to nInt
    selectObject: tg
    lab$ = Get label of interval: 1, iInt
    if lab$ = "sounding"
        evS = Get start time of interval: 1, iInt
        evE = Get end time of interval:   1, iInt
        if evE - evS >= min_event_duration
            nEvents = nEvents + 1
            evStart_'nEvents' = evS
            evEnd_'nEvents'   = evE
        endif
    endif
endfor

removeObject: tg
appendInfoLine: "  Events: ", nEvents

if nEvents < 2
    appendInfoLine: "  Warning: fewer than 2 events — using 0.25 s fallback grid"
    nEvents = 0
    t = 0
    while t < dur - 0.001
        tEnd = min(t + 0.25, dur)
        if tEnd - t >= 0.02
            nEvents = nEvents + 1
            evStart_'nEvents' = t
            evEnd_'nEvents'   = tEnd
        endif
        t = t + 0.25
    endwhile
endif
if nEvents < 1
    removeObject: analysisSound
    @cleanUpTempFiles
    exitScript: "No usable events were found in the selected Sound."
endif

# ===========================================================================
# Stage 2 — Feature extraction → events CSV
# ===========================================================================
appendInfoLine: "[2/5] Extracting features..."

writeFileLine: eventsCSV$,
    ... "event_index,start_time,end_time,duration,rms,spectral_centroid,spectral_flatness,zero_crossing_rate,patch_file"

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'
    patchFile$ = patchPrefix$ + string$(iEv - 1) + ".wav"
    patchPath$ = tempDir$ + patchFile$

    # Export the ORIGINAL multichannel event. Python chooses the strongest
    # event channel for its 24-D analysis, preserving anti-phase material.
    selectObject: sound
    patchPart = Extract part: t1, t2, "rectangular", 1, "no"
    selectObject: patchPart
    Save as WAV file: patchPath$
    removeObject: patchPart
    if not fileReadable(patchPath$)
        removeObject: analysisSound
        @cleanUpTempFiles
        exitScript: "Could not export analysis patch: " + patchPath$
    endif

    # Lightweight CSV fallback descriptors come from the same representative
    # channel used for segmentation. Full features are extracted from patches.
    selectObject: analysisSound
    part = Extract part: t1, t2, "rectangular", 1, "no"
    selectObject: part
    rmsVal = Get root-mean-square: 0, 0
    spec = To Spectrum: "yes"
    centroid = Get centre of gravity: 2
    if centroid = undefined
        centroid = 0
    endif
    removeObject: spec, part

    appendFileLine: eventsCSV$,
        ... string$(iEv - 1) + "," +
        ... fixed$(t1, 6) + "," +
        ... fixed$(t2, 6) + "," +
        ... fixed$(t2 - t1, 6) + "," +
        ... fixed$(rmsVal, 6) + "," +
        ... fixed$(centroid / (sr / 2 + 1), 6) + ",0.5,0," + patchFile$
endfor
removeObject: analysisSound

appendInfoLine: "  Wrote: ", eventsCSV$
appendInfoLine: "  Audio patches: ", nEvents

# ===========================================================================
# Stage 3 — Call Python engine
# ===========================================================================
appendInfoLine: "[3/5] Running Python engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScriptJ$ + """"
    ... + " """ + eventsCSVJ$ + """"
    ... + " """ + durationsCSVJ$ + """"
    ... + " """ + statsTxtJ$ + """"
    ... + " --z_dim "         + string$(latent_dimensions)
    ... + " --n_iter "        + string$(training_iterations)
    ... + " --latent_method " + methodStr$
    ... + " --seed "          + string$(random_seed)
    ... + " --mode "          + modeStr$
    ... + " --amplitude "     + string$(amplitude)
    ... + " --sigma "         + string$(sigma)
    ... + " --n_clusters "    + string$(clusters)
    ... + " --extra_rules "   + rulesStr$
    ... + " --patch_dir """ + tempDirJ$ + """"

runSystem_nocheck: pythonCall$ + " > """ + logTxtJ$ + """ 2>&1"

if not fileReadable(durationsCSV$)
    errMsg$ = "Python engine failed — durations CSV not found."
    if fileReadable(logTxt$)
        errMsg$ = errMsg$ + newline$ + newline$ + readFile$(logTxt$)
    endif
    @cleanUpTempFiles
    exitScript: errMsg$
endif

# ===========================================================================
# Stage 4 — Read durations + reconstruct
# ===========================================================================
appendInfoLine: "[4/5] Reconstructing..."

Read Table from comma-separated file: durationsCSV$
durTable = selected("Table")
nRows    = Get number of rows

for i from 1 to nRows
    startArr[i]   = Get value: i, "start_time"
    origDurArr[i] = Get value: i, "original_duration"
    scaleArr[i]   = Get value: i, "time_scale"
    newDurArr[i]  = Get value: i, "new_duration"
    z0Arr[i]      = Get value: i, "latent_z0"
    z1Arr[i]      = Get value: i, "latent_z1"
endfor
removeObject: durTable

output_name$ = soundName$ + "_te"

if reconstruction_method = 1
    # PSOLA
    nParts = 0
    for i from 1 to nRows
        st = startArr[i]
        od = origDurArr[i]
        nd = newDurArr[i]
        selectObject: sound
        part  = Extract part: st, st + od, "rectangular", 1, "no"
        selectObject: part
        manip = To Manipulation: 0.01, 75, 600
        selectObject: manip
        durTier = Extract duration tier
        selectObject: durTier
        Add point: od / 2, nd / (od + 1e-9)
        plusObject: manip
        Replace duration tier
        selectObject: manip
        resyn = Get resynthesis (overlap-add)
        removeObject: manip, durTier, part
        nParts = nParts + 1
        partArr[nParts] = resyn
    endfor
    selectObject: partArr[1]
    for i from 2 to nParts
        plusObject: partArr[i]
    endfor
    outputSound = Concatenate
    Rename: output_name$
    for i from 1 to nParts
        removeObject: partArr[i]
    endfor

elsif reconstruction_method = 2
    # Resampling — change duration by resampling to shifted SR, then back to original SR
    nParts = 0
    for i from 1 to nRows
        st = startArr[i]
        od = origDurArr[i]
        nd = newDurArr[i]
        selectObject: sound
        part     = Extract part: st, st + od, "rectangular", 1, "no"
        # Varispeed reconstruction: reinterpret the existing samples at a
        # shifted sampling frequency (this changes duration/pitch), THEN
        # sinc-resample to the original SR while preserving that new duration.
        warpSr = max(1000, min(192000, sr * od / (nd + 1e-9)))
        selectObject: part
        Override sampling frequency: warpSr
        normalized = Resample: sr, 50
        removeObject: part
        nParts = nParts + 1
        partArr[nParts] = normalized
    endfor
    selectObject: partArr[1]
    for i from 2 to nParts
        plusObject: partArr[i]
    endfor
    outputSound = Concatenate
    Rename: output_name$
    for i from 1 to nParts
        removeObject: partArr[i]
    endfor

else
    # Placement only: preserve event samples (no stretch). Each event occupies
    # exactly its requested temporal slot: truncate if the slot is shorter, or
    # append multichannel silence if it is longer.
    nParts = 0
    for i from 1 to nRows
        od = origDurArr[i]
        nd = newDurArr[i]
        keepDur = min(od, nd)
        selectObject: sound
        part = Extract part: startArr[i], startArr[i] + keepDur, "rectangular", 1, "no"
        nParts = nParts + 1
        partArr[nParts] = part
        gap = nd - keepDur
        if gap > 0.001
            silence = Create Sound from formula: "te_gap", nChannels, 0, gap, sr, "0"
            nParts = nParts + 1
            partArr[nParts] = silence
        endif
    endfor
    selectObject: partArr[1]
    for i from 2 to nParts
        plusObject: partArr[i]
    endfor
    outputSound = Concatenate
    Rename: output_name$
    for i from 1 to nParts
        removeObject: partArr[i]
    endfor
endif

# Measure what Praat actually rendered (PSOLA can differ slightly from the
# purely planned sum; placement and varispeed should match closely).
selectObject: outputSound
measuredOutputDur = Get total duration

# ---- Read stats ----
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

nEvStat$       = "?"
zDimStat$      = "?"
methodStat$    = "?"
modeStat$      = "?"
rulesStat$     = "?"
lossInitStat$  = "?"
lossFinalStat$ = "?"
comprStat$     = "?"
origDurStat$   = "?"
newDurStat$    = "?"
scaleMinStat$  = "?"
scaleMaxStat$  = "?"
scaleMeanStat$ = "?"
entrStat$      = "?"

if fileReadable(statsTxt$)
    statsText$ = readFile$(statsTxt$)
    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "z_dim="
    zDimStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "latent_method="
    methodStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "field_mode="
    modeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "extra_rules="
    rulesStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "latent_loss_initial="
    lossInitStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "latent_loss_final="
    lossFinalStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "compression_ratio="
    comprStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "orig_total_dur="
    origDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "new_total_dur="
    newDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "scale_min="
    scaleMinStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "scale_max="
    scaleMaxStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "scale_mean="
    scaleMeanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "scale_entropy="
    entrStat$ = parseStatLine.result$
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    # Representative real channels for fair before/after comparison.
    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisChannel
        vizOrig = selected("Sound")
    else
        Copy: "te_viz_orig"
        vizOrig = selected("Sound")
    endif

    selectObject: outputSound
    nOutChannels = Get number of channels
    outAnalysisChannel = 1
    if nOutChannels > 1
        outBestRms = -1
        for iCh from 1 to nOutChannels
            selectObject: outputSound
            outChTmp = Extract one channel: iCh
            selectObject: outChTmp
            outChRms = Get root-mean-square: 0, 0
            if outChRms > outBestRms
                outBestRms = outChRms
                outAnalysisChannel = iCh
            endif
            removeObject: outChTmp
        endfor
        selectObject: outputSound
        Extract one channel: outAnalysisChannel
        vizOut = selected("Sound")
    else
        selectObject: outputSound
        Copy: "te_viz_out"
        vizOut = selected("Sound")
    endif

    selectObject: vizOrig
    origVizPeak = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: vizOut
    outVizPeak = Get absolute extremum: 0, 0, "Sinc70"
    sharedVizPeak = max(origVizPeak, outVizPeak) * 1.05 + 1e-6

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Temporal Elasticity — Latent Time Warping##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.16, "half", soundName$ + " | " + presetName$ + " | " + modeStr$ + " | " + methodStat$ + " | z=" + zDimStat$

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.65, 1.35
    selectObject: vizOrig
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, -sharedVizPeak, sharedVizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.45, 2.15
    selectObject: vizOut
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, -sharedVizPeak, sharedVizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Warped"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(measuredOutputDur, 2) + " s measured  (planned event sum: " + newDurStat$ + " s)"

    # === Latent map (actual mechanism) ===
    Select outer viewport: 0, 8, 2.3, 3.65
    Select inner viewport: 0.6, 7.7, 2.4, 3.55
    z0min = z0Arr[1]
    z0max = z0Arr[1]
    z1min = z1Arr[1]
    z1max = z1Arr[1]
    for i from 2 to nRows
        z0min = min(z0min, z0Arr[i])
        z0max = max(z0max, z0Arr[i])
        z1min = min(z1min, z1Arr[i])
        z1max = max(z1max, z1Arr[i])
    endfor
    z0range = z0max - z0min
    z1range = z1max - z1min
    if z0range < 1e-6
        z0range = 1
    endif
    if z1range < 1e-6
        z1range = 1
    endif
    z0lo = z0min - 0.10 * z0range
    z0hi = z0max + 0.10 * z0range
    z1lo = z1min - 0.12 * z1range
    z1hi = z1max + 0.12 * z1range
    Axes: z0lo, z0hi, z1lo, z1hi
    Paint rectangle: "{0.96, 0.96, 0.98}", z0lo, z0hi, z1lo, z1hi
    Colour: "{0.70, 0.70, 0.76}"
    for i from 1 to nRows - 1
        Draw line: z0Arr[i], z1Arr[i], z0Arr[i + 1], z1Arr[i + 1]
    endfor
    for i from 1 to nRows
        Select inner viewport: 0.6, 7.7, 2.4, 3.55
        Axes: z0lo, z0hi, z1lo, z1hi
        if scaleArr[i] < 0.98
            pointCol$ = "{0.20,0.42,0.88}"
        elsif scaleArr[i] > 1.02
            pointCol$ = "{0.88,0.30,0.22}"
        else
            pointCol$ = "{0.45,0.45,0.50}"
        endif
        Paint circle: pointCol$, z0Arr[i], z1Arr[i], 0.11
    endfor
    Select inner viewport: 0.6, 7.7, 2.4, 3.55
    Axes: z0lo, z0hi, z1lo, z1hi
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "latent z1"
    Text bottom: "yes", "latent z0"
    Text top: "no", "Latent trajectory — effective scale: blue compress · red stretch"

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 3.65, 5.0
    Select inner viewport: 0.6, 7.7, 3.75, 4.90
    vizFmax = min(8000, sr / 2 - 1)
    selectObject: vizOut
    To Spectrogram: 0.005, vizFmax, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, vizFmax, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Warped spectrogram (auto-levelled; representative output channel)"
    removeObject: specOut

    # === Scale per event bar chart ===
    Select outer viewport: 0, 8, 5.1, 6.4
    Select inner viewport: 0.6, 7.7, 5.2, 6.3

    smin = scaleArr[1]
    smax = scaleArr[1]
    for i from 2 to nRows
        if scaleArr[i] < smin
            smin = scaleArr[i]
        endif
        if scaleArr[i] > smax
            smax = scaleArr[i]
        endif
    endfor

    scaleTop = max(1.10, smax * 1.15 + 0.05)
    Axes: 0, nRows + 1, 0, scaleTop
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nRows + 1, 0, scaleTop
    for i from 1 to nRows
        if scaleArr[i] < 0.98
            barCol$ = "{0.20,0.42,0.88}"
        elsif scaleArr[i] > 1.02
            barCol$ = "{0.88,0.30,0.22}"
        else
            barCol$ = "{0.45,0.45,0.50}"
        endif
        Paint rectangle: barCol$, i - 0.4, i + 0.4, 0, scaleArr[i]
    endfor
    Line width: 2
    Colour: "{0.8, 0.2, 0.2}"
    Draw line: 0, 1.0, nRows + 1, 1.0
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Time scale"
    Text bottom: "yes", "Event index"
    Text top: "no", "Scale per event  (blue=compress · red=stretch · line=1.0)"

    # === Summary panel ===
    Select outer viewport: 0, 8, 6.5, 7.5
    Select inner viewport: 0.6, 7.7, 6.6, 7.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Run statistics##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.60, "half",
        ... "Events: " + nEvStat$ +
        ... " | Latent: " + methodStat$ + " z=" + zDimStat$ +
        ... " | Loss: " + lossInitStat$ + " → " + lossFinalStat$
    Text: 0.02, "left", 0.38, "half",
        ... "Field: " + modeStat$ +
        ... " | Rules: " + rulesStat$ +
        ... " | Scale: [" + scaleMinStat$ + ", " + scaleMaxStat$ + "]  mean=" + scaleMeanStat$
    Text: 0.02, "left", 0.16, "half",
        ... "Event-sum: " + origDurStat$ + " s → " + newDurStat$ + " s | Rendered: " + fixed$(measuredOutputDur, 2) + " s" +
        ... " | Ratio: " + comprStat$ +
        ... " | Entropy: " + entrStat$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    removeObject: vizOrig, vizOut
else
    appendInfoLine: "[5/5] Visualization skipped."
endif

# ---- FINAL CLEANUP ----
@cleanUpTempFiles

# ---- Summary ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", output_name$
appendInfoLine: "Preset:    ", presetName$
appendInfoLine: "Events:    ", nEvStat$, " | Latent: ", methodStat$, " z=", zDimStat$
appendInfoLine: "Field:     ", modeStat$, " | Rules: ", rulesStat$
appendInfoLine: "Loss:      ", lossInitStat$, " → ", lossFinalStat$
appendInfoLine: "Duration:  event sum ", origDurStat$, " s → ", newDurStat$, " s; rendered ", fixed$(measuredOutputDur, 3), " s"
appendInfoLine: "Scale:     [", scaleMinStat$, ", ", scaleMaxStat$, "]  mean=", scaleMeanStat$

selectObject: outputSound

if play_result
    Play
endif