# ============================================================
# Praat AudioTools - TemporalElasticity.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_time_warp.py"
eventsCSV$    = pluginDir$ + "temp_te_events.csv"
durationsCSV$ = pluginDir$ + "temp_te_durations.csv"
statsTxt$     = pluginDir$ + "temp_te_stats.txt"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM ----
form Temporal Elasticity v1.0
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
    positive Amplitude 0.8
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
    # Gentle warp — subtle gravitational pull, short events, low amplitude
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
    # Rhythmic stretch — equal-grid feel, short_stretch rules, gradient field
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
    # Gravitational pull — strong cluster wells, PSOLA, ae latent
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
    # Turbulent scatter — stochastic fluctuations, noisy_dilate, placement
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
    # Time inversion — dense regions compressed, sparse stretched
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
    # Spectral drift — gradient along latent axis, harmonic compress
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
    # Deep mutation — large latent, high amplitude, strong AE, PSOLA
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
    # Relativistic — latent velocity drives Lorentz time dilation
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
writeInfoLine:  "=== Temporal Elasticity v1.0 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Mode:    ", modeStr$, "  Method: ", methodStr$
appendInfoLine: "Rules:   ", rulesStr$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz"
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Segment into events
# ===========================================================================

appendInfoLine: "[1/5] Segmenting events..."

selectObject: sound
if nChannels > 1
    Extract one channel: 1
    monoSound = selected("Sound")
else
    Copy: "te_mono"
    monoSound = selected("Sound")
endif

selectObject: monoSound
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

removeObject: tg, monoSound
appendInfoLine: "  Events: ", nEvents

if nEvents < 2
    appendInfoLine: "  Warning: fewer than 2 events — using 0.25 s grid"
    nEvents = 0
    t = 0
    while t + 0.25 <= dur
        nEvents = nEvents + 1
        evStart_'nEvents' = t
        evEnd_'nEvents'   = t + 0.25
        t = t + 0.25
    endwhile
endif

# ===========================================================================
# Stage 2 — Feature extraction → events CSV
# ===========================================================================

appendInfoLine: "[2/5] Extracting features..."

deleteFile: eventsCSV$
writeFileLine: eventsCSV$,
    ... "event_index,start_time,end_time,duration,rms,spectral_centroid,patch_file"

for iEv from 1 to nEvents
    t1 = evStart_'iEv'
    t2 = evEnd_'iEv'

    selectObject: sound
    part = Extract part: t1, t2, "rectangular", 1, "no"

    selectObject: part
    rmsVal = Get root-mean-square: 0, 0

    spec     = To Spectrum: "yes"
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
        ... fixed$(centroid / (sr / 2 + 1), 6) + ","
endfor

appendInfoLine: "  Wrote: ", eventsCSV$

# ===========================================================================
# Stage 3 — Detect Python
# ===========================================================================

appendInfoLine: "[3/5] Detecting Python..."

probeMarker$ = pluginDir$ + "temp_te_pyprobe.ok"
probeScript$ = pluginDir$ + "temp_te_pyprobe.py"
writeFileLine: probeScript$, "import numpy, soundfile, sys"
appendFileLine: probeScript$, "open(sys.argv[1], 'w').close()"

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
    nocheck runSystem: tryCmd$ + " """ + probeScript$ + """ """ + probeMarker$ + """"
    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

deleteFile: probeScript$

if pythonCmd$ = ""
    deleteFile: eventsCSV$
    exitScript: "Cannot find Python with numpy + soundfile." + newline$
        ... + "Install with:  pip install numpy soundfile"
endif

# ===========================================================================
# Stage 4 — Call Python engine
# ===========================================================================

appendInfoLine: "[4/5] Running Python engine..."

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + eventsCSV$ + """"
    ... + " """ + durationsCSV$ + """"
    ... + " """ + statsTxt$ + """"
    ... + " --z_dim "         + string$(latent_dimensions)
    ... + " --n_iter "        + string$(training_iterations)
    ... + " --latent_method " + methodStr$
    ... + " --seed "          + string$(random_seed)
    ... + " --mode "          + modeStr$
    ... + " --amplitude "     + string$(amplitude)
    ... + " --sigma "         + string$(sigma)
    ... + " --n_clusters "    + string$(clusters)
    ... + " --extra_rules "   + rulesStr$
    ... + " --cleanup"

if not fileReadable(durationsCSV$)
    deleteFile: eventsCSV$
    exitScript: "Python engine failed — durations CSV not found." + newline$
        ... + "Run manually to see error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """"
endif

# ===========================================================================
# Stage 5 — Read durations + reconstruct
# ===========================================================================

appendInfoLine: "[5/5] Reconstructing..."

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
        # Resample to a shifted SR so playback at original SR gives new duration
        warpSr   = max(1000, min(192000, sr * od / (nd + 1e-9)))
        selectObject: part
        warped   = Resample: warpSr, 50
        removeObject: part
        # Resample back to original SR so all parts match for Concatenate
        selectObject: warped
        normalized = Resample: sr, 50
        removeObject: warped
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
    # Placement only — events placed at new durations, gaps filled with silence
    nParts = 0
    for i from 1 to nRows
        selectObject: sound
        part = Extract part: startArr[i], startArr[i] + origDurArr[i], "rectangular", 1, "no"
        # Convert to mono so all parts and silences match
        if nChannels > 1
            selectObject: part
            partMono = Convert to mono
            removeObject: part
            part = partMono
        endif
        nParts = nParts + 1
        partArr[nParts] = part
        # If new duration is longer than original, append a silence gap
        gap = newDurArr[i] - origDurArr[i]
        if gap > 0.001
            silence = Create Sound from formula: "gap", 1, 0, gap, sr, "0"
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
    @parseStatLine: statsText$, "latent_method="
    methodStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "field_mode="
    modeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "extra_rules="
    rulesStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "vae_loss_initial="
    lossInitStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "vae_loss_final="
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

# ---- Cleanup temp files ----
deleteFile: eventsCSV$
deleteFile: durationsCSV$
deleteFile: statsTxt$

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

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
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | " + modeStr$ + " | " + methodStr$ + " | z=" + string$(latent_dimensions)

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.65, 1.35
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(dur, 2) + " s"

    # === Output waveform ===
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.45, 2.15
    selectObject: outputSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Warped"
    Text bottom: "yes", "Time (s)"
    Text top: "no", newDurStat$ + " s  (ratio: " + comprStat$ + ")"

    # === Original spectrogram ===
    Select outer viewport: 0, 8, 2.3, 3.65
    Select inner viewport: 0.6, 7.7, 2.4, 3.55
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 3.65, 5.0
    Select inner viewport: 0.6, 7.7, 3.75, 4.90
    selectObject: outputSound
    Copy: "tmpOut"
    tmpOut = selected("Sound")
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Warped spectrogram"
    removeObject: specOut, tmpOut

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

    Axes: 0, nRows + 1, 0, smax * 1.15 + 0.05
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, nRows + 1, 0, smax * 1.15 + 0.05
    for i from 1 to nRows
        t = (scaleArr[i] - smin) / (smax - smin + 1e-9)
        if t < 0.5
            r_c = t * 2
            g_c = t * 2
            b_c = 1
        else
            r_c = 1
            g_c = 2 * (1 - t)
            b_c = 2 * (1 - t)
        endif
        Paint rectangle: "{" + string$(r_c) + "," + string$(g_c) + "," + string$(b_c) + "}", i - 0.4, i + 0.4, 0, scaleArr[i]
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
        ... " | Latent: " + methodStat$ + " z=" + string$(latent_dimensions) +
        ... " | Loss: " + lossInitStat$ + " → " + lossFinalStat$
    Text: 0.02, "left", 0.38, "half",
        ... "Field: " + modeStat$ +
        ... " | Rules: " + rulesStat$ +
        ... " | Scale: [" + scaleMinStat$ + ", " + scaleMaxStat$ + "]  mean=" + scaleMeanStat$
    Text: 0.02, "left", 0.16, "half",
        ... "Duration: " + origDurStat$ + " s → " + newDurStat$ + " s" +
        ... " | Ratio: " + comprStat$ +
        ... " | Entropy: " + entrStat$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "Visualization skipped."
endif

# ---- Summary ----
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", output_name$
appendInfoLine: "Preset:    ", presetName$
appendInfoLine: "Events:    ", nEvStat$
appendInfoLine: "Field:     ", modeStat$, " | Rules: ", rulesStat$
appendInfoLine: "Loss:      ", lossInitStat$, " → ", lossFinalStat$
appendInfoLine: "Duration:  ", origDurStat$, " s → ", newDurStat$, " s  (ratio: ", comprStat$, ")"
appendInfoLine: "Scale:     [", scaleMinStat$, ", ", scaleMaxStat$, "]  mean=", scaleMeanStat$

selectObject: outputSound

if play_result
    Play
endif
