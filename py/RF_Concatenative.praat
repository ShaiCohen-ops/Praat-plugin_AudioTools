# ============================================================
# Praat AudioTools - RF_Concatenative.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Random Forest Concatenative Synthesis
#
#   Reads a source recording, cuts it into overlapping grains, and
#   describes each grain with a 17-dimensional timbre vector (RMS,
#   spectral centroid, spectral flatness, zero-crossing rate, MFCCs
#   1-13). Multichannel analysis uses the strongest-RMS real channel,
#   while the chosen grain indices are applied to ALL source channels
#   during resynthesis.
#
#   A multi-target Random Forest models local feature-state transitions
#   X_t -> X_{t+k}. Its prediction is blended with a synthetic target
#   trajectory in standardised corpus space, then matched against the
#   grain pool by L2 distance. OOB R^2 is reported only as an overlap-
#   biased diagnostic; OOB skill versus a persistence baseline indicates
#   whether the forest beats the trivial predictor Y=X.
#
#   The generated output has the requested duration and intentionally
#   starts at t=0. Sample rate and source channel count are preserved.
#
#   The engine is a Python script (rf_engine.py). The front end discovers
#   Python automatically, uses a compatible installed engine when present,
#   and otherwise writes its embedded copy to a unique temporary file.
#
# v0.4:
#   - Makes Repeat_penalty effective with overlapping grain pools by calibrating
#     it to corpus-scale pairwise distance instead of near-zero NN distance.
#   - Applies final edge fades after exact duration trim/pad.
#   - Uses strongest-RMS real channel for multichannel analysis.
#   - Adds repeat-scale / immediate-repeat diagnostics and shared-scale waveform QA.
#
# v0.3:
#   - Removes Python path, external-engine and temp-file runtime controls from the form.
#   - Adds five musical presets plus Custom; presets never override duration or Seed.
#   - Adds transparent Match_input_RMS after OLA, before Safety, to prevent weak output.
#   - RMS compensation is capped at +12 dB and fully reported in stats/visualization.
#
# v0.2:
#   - Preserves multichannel source grains; cancellation-safe mono analysis.
#   - Renames pitch_descent to truthful spectral_descent.
#   - Adds OOB skill versus persistence and removes the honest-R2 claim.
#   - Uses 32-bit PCM for the Praat-to-Python handoff (v0.1 used 16-bit).
#   - Removes forced 0.95 output normalization; adds Safety_peak ceiling.
#   - Uses runSubprocess so Python paths with spaces are supported.
#   - Uses unique temp files and actual output-time stats for plots.
#   - Adds optional paired spectrograms and house visualization.
#
# Requires:  python3 with numpy, scipy, librosa, scikit-learn, soundfile
#            pip install numpy scipy librosa scikit-learn soundfile
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- FORM ----
# The source is the Sound object already selected in the Objects list;
# the result comes back the same way, as a new Sound object named
# "rf_concatenative". Nothing is asked about files.
form RF_Concatenative
    optionmenu Preset: 1
        option Custom
        option Flowing Crescendo
        option Spectral Descent
        option Organic Wander
        option Tight Continuity
        option Fragmented Mosaic
    positive Target_duration_s 10.0
    comment --- Grain analysis ---
    positive Frame_length_ms 100
    positive Hop_length_ms 25
    comment --- Target trajectory ---
    optionmenu Target_trajectory_type: 1
        option crescendo_brightening
        option spectral_descent
        option random_walk
    real Trajectory_weight 0.6
    real Repeat_penalty 0.5
    comment --- Random forest ---
    natural Trees 100
    integer Max_depth 15
    natural Lookahead_k 1
    integer Seed 42
    comment --- Output ---
    boolean Match_input_RMS 1
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Show_spectrograms 0
    boolean Play_result 1
endform

# ===========================================================================
# Selected object
# ===========================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object first, then run this script again."
endif

inputSound = selected("Sound")
inputName$ = selected$("Sound")

# ---- PRESETS ---------------------------------------------------------------
# Presets shape the concatenation style only. Target duration and Seed remain
# explicit compositional controls and are never overridden here.
presetName$ = preset$
if preset = 2
    # Longer grains, moderate target pull, smooth rise in energy/brightness.
    frame_length_ms = 120
    hop_length_ms = 30
    target_trajectory_type = 1
    trajectory_weight = 0.65
    repeat_penalty = 0.60
    trees = 100
    max_depth = 15
    lookahead_k = 1
elsif preset = 3
    frame_length_ms = 100
    hop_length_ms = 25
    target_trajectory_type = 2
    trajectory_weight = 0.70
    repeat_penalty = 0.65
    trees = 100
    max_depth = 15
    lookahead_k = 1
elsif preset = 4
    # Forest-led random walk with longer grains and stronger repeat avoidance.
    frame_length_ms = 140
    hop_length_ms = 35
    target_trajectory_type = 3
    trajectory_weight = 0.45
    repeat_penalty = 0.90
    trees = 120
    max_depth = 18
    lookahead_k = 1
elsif preset = 5
    # Continuity-first: short lookahead, low target pull, moderate repeat cost.
    frame_length_ms = 80
    hop_length_ms = 20
    target_trajectory_type = 3
    trajectory_weight = 0.25
    repeat_penalty = 0.45
    trees = 150
    max_depth = 20
    lookahead_k = 1
elsif preset = 6
    # Target-led, short grains, stronger anti-repeat pressure, k=2 jumps.
    frame_length_ms = 60
    hop_length_ms = 15
    target_trajectory_type = 3
    trajectory_weight = 0.85
    repeat_penalty = 1.60
    trees = 80
    max_depth = 12
    lookahead_k = 2
endif

# ---- Trajectory token (built explicitly rather than read from the
# ---- optionmenu string variable, so the engine flag is never surprising)
if target_trajectory_type = 1
    trajectory$ = "crescendo_brightening"
elsif target_trajectory_type = 2
    trajectory$ = "spectral_descent"
else
    trajectory$ = "random_walk"
endif

# ---- CLAMP (mirrors the clamps inside rf_engine.py) ----
if target_duration_s < 0.5
    target_duration_s = 0.5
endif
if target_duration_s > 600
    target_duration_s = 600
endif
if frame_length_ms < 5
    frame_length_ms = 5
endif
if frame_length_ms > 2000
    frame_length_ms = 2000
endif
if hop_length_ms < 1
    hop_length_ms = 1
endif
if hop_length_ms > frame_length_ms
    hop_length_ms = frame_length_ms
endif
if trajectory_weight < 0
    trajectory_weight = 0
endif
if trajectory_weight > 1
    trajectory_weight = 1
endif
if repeat_penalty < 0
    repeat_penalty = 0
endif
if repeat_penalty > 10
    repeat_penalty = 10
endif
if trees > 1000
    trees = 1000
endif
if lookahead_k > 50
    lookahead_k = 50
endif
if max_depth < 0
    max_depth = 0
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

# ===========================================================================
# Python interpreter discovery (automatic; no runtime/path controls in form)
# ===========================================================================

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

# ===========================================================================
# Paths
# ===========================================================================

tempTag$ = "rfconcat_" + string$(inputSound) + "_" + string$(randomInteger(100000, 999999))
enginePath$  = temporaryDirectory$ + "/" + tempTag$ + "_engine.py"
input_file$  = temporaryDirectory$ + "/" + tempTag$ + "_input.wav"
output_file$ = temporaryDirectory$ + "/" + tempTag$ + "_output.wav"
tempStats$   = temporaryDirectory$ + "/" + tempTag$ + "_stats.txt"
tempLog$     = temporaryDirectory$ + "/" + tempTag$ + "_log.txt"
probeMarker$ = temporaryDirectory$ + "/" + tempTag$ + "_probe.ok"

# Use 32-bit PCM so the Python handoff does not quantize the selected Sound
# to the 16-bit format produced by the ordinary Save as WAV command.
selectObject: inputSound
Save as 32-bit WAV file: input_file$

wroteEngine = 0

procedure cleanUpTempFiles
    if wroteEngine and fileReadable(enginePath$)
        deleteFile: enginePath$
    endif
    if fileReadable(input_file$)
        deleteFile: input_file$
    endif
    if fileReadable(output_file$)
        deleteFile: output_file$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

# ===========================================================================
# Info header
# ===========================================================================

clearinfo
writeInfoLine:  "=== RF_Concatenative v0.4 ==="
appendInfoLine: "Input object: ", inputName$
appendInfoLine: "Preset:       ", presetName$
appendInfoLine: ""
appendInfoLine: "Target duration:  ", fixed$(target_duration_s, 2), " s"
appendInfoLine: "Grain / hop:      ", fixed$(frame_length_ms, 1), " ms / ",
    ... fixed$(hop_length_ms, 1), " ms  (",
    ... fixed$(100 * (1 - hop_length_ms / frame_length_ms), 0), "% overlap)"
appendInfoLine: "Trajectory:       ", trajectory$
appendInfoLine: "Trajectory weight:", " ", fixed$(trajectory_weight, 2)
appendInfoLine: "Repeat penalty:   ", fixed$(repeat_penalty, 2)
appendInfoLine: "Forest:           ", trees, " trees, depth ", max_depth,
    ... " (0 = unlimited), k = ", lookahead_k
appendInfoLine: "Seed:             ", seed
appendInfoLine: "RMS level match:  ", if match_input_RMS then "on" else "off" fi
appendInfoLine: "Safety peak:      ", fixed$(safety_peak, 3), " (0 = disabled)"
appendInfoLine: ""

# ===========================================================================
# Stage 1 - Detect Python dependencies
# ===========================================================================

appendInfoLine: "[1/6] Detecting Python interpreter..."

if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

probeCode$ = "import sys;open(sys.argv[1],""w"").write(""ok"")"
runSubprocess: pythonCmd$, "-c", probeCode$, probeMarker$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python interpreter could not be started." + newline$
        ... + "Interpreter tried: " + pythonCmd$
endif

deleteFile: probeMarker$
appendInfoLine: "  Interpreter: ", pythonCmd$
appendInfoLine: "  Dependencies will be verified by the engine (single import pass)"

# ===========================================================================
# Stage 2 - Put the engine on disk
# ===========================================================================

appendInfoLine: "[2/6] Preparing Python engine..."

useExternal = 0
externalPath$ = preferencesDirectory$ + "/plugin_AudioTools/py/rf_engine.py"
if not fileReadable(externalPath$)
    externalPath$ = defaultDirectory$ + "/rf_engine.py"
endif
if fileReadable(externalPath$)
    externalText$ = readFile$(externalPath$)
    if index(externalText$, "# Version: 0.4 (2026)") > 0
        enginePath$ = externalPath$
        useExternal = 1
        appendInfoLine: "  Using compatible installed rf_engine.py"
    else
        appendInfoLine: "  Installed rf_engine.py is not v0.4; using embedded engine."
    endif
endif

if not useExternal
    @writeEngine
    wroteEngine = 1
    if not fileReadable(enginePath$)
        @cleanUpTempFiles
        exitScript: "Could not write the engine to:" + newline$ + enginePath$
    endif
    appendInfoLine: "  Using embedded engine"
endif

# ===========================================================================
# Stage 3 - Run the engine
# ===========================================================================

appendInfoLine: "[3/6] Running Python engine (librosa import is slow; be patient)..."

# runSubprocess passes each argument separately, so interpreter and temp paths
# containing spaces do not require shell quoting.
if fileReadable(output_file$)
    deleteFile: output_file$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif
if fileReadable(tempLog$)
    deleteFile: tempLog$
endif

runSubprocess: pythonCmd$, enginePath$,
    ... "--input", input_file$,
    ... "--output", output_file$,
    ... "--stats", tempStats$,
    ... "--log", tempLog$,
    ... "--target-duration", fixed$(target_duration_s, 4),
    ... "--frame-ms", fixed$(frame_length_ms, 4),
    ... "--hop-ms", fixed$(hop_length_ms, 4),
    ... "--trajectory", trajectory$,
    ... "--trees", string$(trees),
    ... "--max-depth", string$(max_depth),
    ... "--lookahead", string$(lookahead_k),
    ... "--traj-weight", fixed$(trajectory_weight, 4),
    ... "--repeat-penalty", fixed$(repeat_penalty, 4),
    ... "--seed", string$(seed),
    ... "--match-input-rms", string$(match_input_RMS),
    ... "--safety-peak", fixed$(safety_peak, 6)

# ===========================================================================
# Stage 4 - Echo the engine log into the info window
# ===========================================================================

appendInfoLine: "[4/6] Engine report:"

if fileReadable(tempLog$)
    appendInfoLine: readFile$(tempLog$)
else
    appendInfoLine: "  (no log file produced)"
endif

if not fileReadable(output_file$)
    @cleanUpTempFiles
    exitScript: "The Python engine did not produce an output file."
        ... + newline$ + "Expected: " + output_file$ + newline$
        ... + "See the Engine report above for dependency or runtime errors."
endif

# ===========================================================================
# Stage 5 - Import the result
# ===========================================================================

appendInfoLine: "[5/6] Importing result into Praat..."

Read from file: output_file$
Rename: "rf_concatenative"
resultSound = selected("Sound")

selectObject: resultSound
outDur   = Get total duration
outRms   = Get root-mean-square: 0, 0
outSr    = Get sampling frequency

# ===========================================================================
# Stage 6 - Read stats
# ===========================================================================

appendInfoLine: "[6/6] Reading statistics..."

nPoolStat$     = "?"
nOutGrains$    = "?"
srStat$        = "?"
inputChStat$   = "?"
outputChStat$  = "?"
analysisStat$  = "?"
analysisChannelStat$ = "?"
frameSamp$     = "?"
hopSamp$       = "?"
overlapStat$   = "?"
inDurStat$     = "?"
outDurStat$    = "?"
featDimStat$   = "?"
trainRows$     = "?"
oobStat$       = "?"
oobSkillStat$  = "?"
trajStat$      = "?"
distinctStat$  = "?"
distinctPct$   = "?"
meanDistStat$  = "?"
nnDistStat$    = "?"
repeatScaleStat$ = "?"
immediateRepeatStat$ = "?"
inputRmsStat$   = "?"
rmsBeforeStat$ = "?"
rmsAfterMatchStat$ = "?"
rmsGainDbStat$ = "?"
rmsLimitedStat$ = "?"
peakBeforeStat$ = "?"
peakAfterStat$  = "?"
rmsStat$       = "?"
elapsedStat$   = "?"
warningStat$   = ""
nPts           = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_pool_grains="
    nPoolStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_output_grains="
    nOutGrains$ = parseStatLine.result$
    @parseStatLine: statsText$, "sample_rate="
    srStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "input_channels="
    inputChStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_channels="
    outputChStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_source="
    analysisStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_channel="
    analysisChannelStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "frame_samples="
    frameSamp$ = parseStatLine.result$
    @parseStatLine: statsText$, "hop_samples="
    hopSamp$ = parseStatLine.result$
    @parseStatLine: statsText$, "overlap_pct="
    overlapStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "input_duration="
    inDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "feature_dim="
    featDimStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rf_train_rows="
    trainRows$ = parseStatLine.result$
    @parseStatLine: statsText$, "rf_oob_r2="
    oobStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rf_oob_skill="
    oobSkillStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "trajectory="
    trajStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "distinct_grains="
    distinctStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "distinct_pct="
    distinctPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_match_dist="
    meanDistStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "median_nn_dist="
    nnDistStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "repeat_distance_scale="
    repeatScaleStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "immediate_repeat_pct="
    immediateRepeatStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "source_rms="
    inputRmsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_before_match="
    rmsBeforeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_after_match="
    rmsAfterMatchStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_match_gain_db="
    rmsGainDbStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_match_limited="
    rmsLimitedStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak_before_safety="
    peakBeforeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_peak="
    peakAfterStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "out_rms="
    rmsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "elapsed_s="
    elapsedStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "n_points="
    nPts$ = parseStatLine.result$
    if nPts$ <> "?"
        nPts = number(nPts$)
    endif
    if nPts > 500
        nPts = 500
    endif

    # --- source time of each selected grain ---
    @parseStatLine: statsText$, "src_times="
    srcRaw$ = parseStatLine.result$
    if srcRaw$ <> "?" and nPts > 0
        remaining$ = srcRaw$
        for gi from 1 to nPts
            comma = index(remaining$, ",")
            if comma > 0
                val$ = left$(remaining$, comma - 1)
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
            else
                val$ = remaining$
            endif
            srcT_'gi' = number(val$)
        endfor
    else
        nPts = 0
    endif

    # --- actual output time for each subsampled selected grain ---
    @parseStatLine: statsText$, "out_times="
    outRaw$ = parseStatLine.result$
    haveOutTimes = 0
    if outRaw$ <> "?" and nPts > 0
        haveOutTimes = 1
        remaining$ = outRaw$
        for gi from 1 to nPts
            comma = index(remaining$, ",")
            if comma > 0
                val$ = left$(remaining$, comma - 1)
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
            else
                val$ = remaining$
            endif
            outT_'gi' = number(val$)
        endfor
    endif

    # --- L2 distance between the requested state and the grain actually used ---
    @parseStatLine: statsText$, "match_dists="
    mdRaw$ = parseStatLine.result$
    haveDists = 0
    if mdRaw$ <> "?" and nPts > 0
        haveDists = 1
        remaining$ = mdRaw$
        for gi from 1 to nPts
            comma = index(remaining$, ",")
            if comma > 0
                val$ = left$(remaining$, comma - 1)
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
            else
                val$ = remaining$
            endif
            matchD_'gi' = number(val$)
        endfor
    endif
else
    haveDists = 0
    haveOutTimes = 0
    appendInfoLine: "  (stats file missing - visualization will be reduced)"
endif

if inDurStat$ = "?"
    inDur = outDur
else
    inDur = number(inDurStat$)
endif
if inDur <= 0
    inDur = 1
endif

###############################################################################
# VISUALIZATION - AudioTools house layout
###############################################################################

if draw_visualization
    analysisChannelViz = 1
    if analysisChannelStat$ <> "?"
        analysisChannelViz = round(number(analysisChannelStat$))
    endif

    # Same real channel and same amplitude scale for input/output comparison.
    selectObject: inputSound
    inputVizChCount = Get number of channels
    if analysisChannelViz < 1 or analysisChannelViz > inputVizChCount
        analysisChannelViz = 1
    endif
    if inputVizChCount > 1
        Extract one channel: analysisChannelViz
        vizInputSound = selected("Sound")
    else
        Copy: "rf_viz_input"
        vizInputSound = selected("Sound")
    endif
    inAbsViz = Get absolute extremum: 0, 0, "none"

    selectObject: resultSound
    outputVizChCount = Get number of channels
    outputAnalysisCh = min(analysisChannelViz, outputVizChCount)
    if outputVizChCount > 1
        Extract one channel: outputAnalysisCh
        vizOutputSound = selected("Sound")
    else
        Copy: "rf_viz_output"
        vizOutputSound = selected("Sound")
    endif
    outAbsViz = Get absolute extremum: 0, 0, "none"
    sharedWaveAmp = max(inAbsViz, outAbsViz)
    if sharedWaveAmp < 0.001
        sharedWaveAmp = 0.001
    endif
    sharedWaveAmp = sharedWaveAmp * 1.05
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Colour: "Black"
    Font size: 10
    Line width: 1

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Random Forest Concatenative Synthesis##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.18, "half",
        ... inputName$ + "  |  " + presetName$ + "  |  " + trajectory$
        ... + "  |  grain " + fixed$(frame_length_ms, 0) + " / hop "
        ... + fixed$(hop_length_ms, 0) + " ms  |  "
        ... + inputChStat$ + " ch -> " + outputChStat$ + " ch"

    # ---- INPUT WAVEFORM ----
    Select outer viewport: 0, 4.15, 0.78, 2.15
    Select inner viewport: 0.55, 3.95, 0.96, 2.05
    selectObject: vizInputSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -sharedWaveAmp, sharedWaveAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input  (analysis ch " + string$(analysisChannelViz) + ")"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT WAVEFORM ----
    Select outer viewport: 4.15, 8, 0.78, 2.15
    Select inner viewport: 4.50, 7.75, 0.96, 2.05
    selectObject: vizOutputSound
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, -sharedWaveAmp, sharedWaveAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (same scale)"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- GRAIN MAP ----
    Select outer viewport: 0, 8, 2.32, 4.05
    Select inner viewport: 0.55, 7.75, 2.50, 3.93
    if nPts > 0
        Axes: 0, outDur, 0, inDur
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, 0, inDur
        Colour: "{0.48, 0.35, 0.74}"
        Line width: 1
        for gi from 1 to nPts
            if haveOutTimes
                xOut = outT_'gi'
            else
                xOut = (gi - 1) * outDur / max(1, nPts - 1)
            endif
            yIn = srcT_'gi'
            if gi > 1
                prevGi = gi - 1
                if haveOutTimes
                    xPrev = outT_'prevGi'
                else
                    xPrev = (prevGi - 1) * outDur / max(1, nPts - 1)
                endif
                yPrev = srcT_'prevGi'
                Draw line: xPrev, yPrev, xOut, yIn
            endif
        endfor
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Grain map"
        Font size: 6
        Text left: "yes", "Source time (s)"
        Text bottom: "yes", "Output time (s)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.45, 0.45, 0.45}"
        Text: 0.5, "centre", 0.5, "half", "Grain-map stats unavailable"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # ---- MATCH DISTANCE ----
    Select outer viewport: 0, 8, 4.18, 5.48
    Select inner viewport: 0.55, 7.75, 4.34, 5.38
    if haveDists and nPts > 1
        mdMax = 0
        for gi from 1 to nPts
            mdMax = max(mdMax, matchD_'gi')
        endfor
        if mdMax <= 0
            mdMax = 1
        endif
        mdMax = mdMax * 1.15
        Axes: 0, outDur, 0, mdMax
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, 0, mdMax

        if nnDistStat$ <> "?"
            nnRef = number(nnDistStat$)
            if nnRef > 0 and nnRef < mdMax
                Colour: "{0.72, 0.72, 0.72}"
                Dotted line
                Draw line: 0, nnRef, outDur, nnRef
                Solid line
            endif
        endif

        Colour: "{0.48, 0.35, 0.74}"
        Line width: 1.5
        for gi from 2 to nPts
            prevI = gi - 1
            if haveOutTimes
                x0 = outT_'prevI'
                x1 = outT_'gi'
            else
                x0 = (prevI - 1) * outDur / (nPts - 1)
                x1 = (gi - 1) * outDur / (nPts - 1)
            endif
            Draw line: x0, matchD_'prevI', x1, matchD_'gi'
        endfor
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Match distance"
        Font size: 6
        Text left: "yes", "L2"
        Text bottom: "yes", "Output time (s)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.45, 0.45, 0.45}"
        Text: 0.5, "centre", 0.5, "half", "Match stats unavailable"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    if show_spectrograms
        maxSpecF = min(8000, outSr / 2)

        # ---- INPUT SPECTROGRAM ----
        Select outer viewport: 0, 4.15, 5.62, 6.72
        Select inner viewport: 0.55, 3.95, 5.76, 6.62
        selectObject: vizInputSound
        Copy: "rf_spec_in"
        specSrcSound = selected("Sound")
        To Spectrogram: 0.03, maxSpecF, 0.002, 20, "Gaussian"
        specSrc = selected("Spectrogram")
        Paint: 0, 0, 0, maxSpecF, 100, "yes", 50, 6, 0, "no"
        removeObject: specSrc, specSrcSound
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Input spectrogram"
        Font size: 6
        Text left: "yes", "Hz"

        # ---- OUTPUT SPECTROGRAM ----
        Select outer viewport: 4.15, 8, 5.62, 6.72
        Select inner viewport: 4.50, 7.75, 5.76, 6.62
        selectObject: vizOutputSound
        Copy: "rf_spec_out"
        specOutSound = selected("Sound")
        To Spectrogram: 0.03, maxSpecF, 0.002, 20, "Gaussian"
        specOut = selected("Spectrogram")
        Paint: 0, 0, 0, maxSpecF, 100, "yes", 50, 6, 0, "no"
        removeObject: specOut, specOutSound
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Output spectrogram"
        Font size: 6
        Text left: "yes", "Hz"

        summaryY0 = 6.88
        summaryY1 = 7.72
    else
        summaryY0 = 5.68
        summaryY1 = 6.52
    endif

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, summaryY0, summaryY1
    Select inner viewport: 0.55, 7.75, summaryY0 + 0.06, summaryY1 - 0.06
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
        ... "RF: " + string$(trees) + " trees  |  k " + string$(lookahead_k)
        ... + "  |  OOB R2 " + oobStat$ + "  |  skill vs persistence " + oobSkillStat$
        ... + "  |  distinct " + distinctPct$ + "%"
        ... + "  |  immediate repeats " + immediateRepeatStat$ + "%"
    Text: 0.02, "left", 0.18, "half",
        ... "trajectory " + trajStat$ + "  |  weight " + fixed$(trajectory_weight, 2)
        ... + "  |  RMS gain " + rmsGainDbStat$ + " dB"
        ... + "  |  safety " + fixed$(safety_peak, 2)
        ... + "  |  " + inDurStat$ + " s -> " + outDurStat$ + " s"
        ... + "  |  " + inputChStat$ + " ch  |  runtime " + elapsedStat$ + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizInputSound, vizOutputSound
endif

# ===========================================================================
# Cleanup
# ===========================================================================

@cleanUpTempFiles

# ===========================================================================
# Summary
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Object:   rf_concatenative"
appendInfoLine: ""
appendInfoLine: "Corpus:"
appendInfoLine: "  Grain pool:      ", nPoolStat$, " grains of ", frameSamp$,
    ... " samples (hop ", hopSamp$, ")"
appendInfoLine: "  Feature space:   ", featDimStat$, " dimensions, standardised"
appendInfoLine: "  Source duration: ", inDurStat$, " s at ", srStat$, " Hz; ", inputChStat$, " ch"
appendInfoLine: "  Analysis source: ", analysisStat$
appendInfoLine: "  Analysis channel:", " ", analysisChannelStat$
appendInfoLine: ""
appendInfoLine: "Random forest:"
appendInfoLine: "  Trained on:      ", trainRows$, " transition pairs (k = ",
    ... lookahead_k, ")"
appendInfoLine: "  OOB row R^2:     ", oobStat$, "   (diagnostic; optimistic with overlap)"
appendInfoLine: "  Skill vs persist:", " ", oobSkillStat$,
    ... "   (>0 means RF beats Y=X on OOB rows)"
appendInfoLine: ""
appendInfoLine: "Selection:"
appendInfoLine: "  Trajectory:      ", trajStat$
appendInfoLine: "  Output grains:   ", nOutGrains$
appendInfoLine: "  Distinct grains: ", distinctStat$, " (", distinctPct$, "%)"
appendInfoLine: "  Mean match L2:   ", meanDistStat$,
    ... "   (median neighbour distance = ", nnDistStat$, ")"
appendInfoLine: "  Repeat scale:    ", repeatScaleStat$,
    ... "   | immediate repeats: ", immediateRepeatStat$, "%"
appendInfoLine: ""
appendInfoLine: "Output:"
appendInfoLine: "  Duration:        ", fixed$(outDur, 2), " s at ", outSr, " Hz; ", outputChStat$, " ch"
appendInfoLine: "  Input RMS:       ", inputRmsStat$
appendInfoLine: "  OLA RMS:         ", rmsBeforeStat$
if match_input_RMS
    appendInfoLine: "  RMS match gain:  ", rmsGainDbStat$, " dB", if rmsLimitedStat$ = "1" then " (limited)" else "" fi
endif
appendInfoLine: "  RMS after match: ", rmsAfterMatchStat$
appendInfoLine: "  Peak before safety: ", peakBeforeStat$
appendInfoLine: "  Output peak:        ", peakAfterStat$
appendInfoLine: "  Final RMS:          ", rmsStat$
appendInfoLine: "  Engine runtime:  ", elapsedStat$, " s"

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningStat$
endif

selectObject: resultSound

if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

# ---------------------------------------------------------------------------
# writeEngine - streams the standalone v0.4 engine to a unique temp file.
# The embedded block is generated from rf_engine_v0.4.py and the
# regression test verifies that it is byte-identical apart from newline EOF.
# ---------------------------------------------------------------------------
procedure writeEngine
    writeFileLine: enginePath$, "#!/usr/bin/env python3"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# rf_engine.py -- Random Forest Concatenative Synthesis engine"
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# Part of Praat AudioTools plugin"
    appendFileLine: enginePath$, "# Author: Shai Cohen, Department of Music, Bar-Ilan University, Israel"
    appendFileLine: enginePath$, "# Email: shai.cohen@biu.ac.il"
    appendFileLine: enginePath$, "# Version: 0.4 (2026)"
    appendFileLine: enginePath$, "# License: MIT"
    appendFileLine: enginePath$, "# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools"
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# v0.4:"
    appendFileLine: enginePath$, "#   - Calibrates Repeat penalty to corpus-scale pairwise distance so it remains effective with heavily overlapping grains."
    appendFileLine: enginePath$, "#   - Applies edge fades after final length trimming so arbitrary target durations end cleanly."
    appendFileLine: enginePath$, "#   - Uses the strongest real source channel for multichannel analysis instead of fold-down."
    appendFileLine: enginePath$, "#   - Reports repeat-scale and immediate-repeat diagnostics."
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# v0.3:"
    appendFileLine: enginePath$, "#   - Adds optional global RMS level matching to the source after OLA and before Safety."
    appendFileLine: enginePath$, "#   - Caps upward RMS compensation at +12 dB and reports the applied gain."
    appendFileLine: enginePath$, "#   - Keeps all v0.2 multichannel, feature, RF-diagnostic and performance fixes."
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# v0.2:"
    appendFileLine: enginePath$, "#   - Preserves all source channels while analysing a cancellation-safe mono fold."
    appendFileLine: enginePath$, "#   - Reuses one STFT for centroid, flatness and MFCC extraction."
    appendFileLine: enginePath$, "#   - Adapts mel-band count to short FFTs to avoid empty mel filters."
    appendFileLine: enginePath$, "#   - Serialises single-state RF prediction for speed and deterministic tie-breaking."
    appendFileLine: enginePath$, "#   - Adds OOB skill vs persistence; raw OOB R^2 is labelled overlap-biased."
    appendFileLine: enginePath$, "#   - Renames pitch_descent to spectral_descent (legacy alias still accepted)."
    appendFileLine: enginePath$, "#   - Removes forced 0.95 peak normalisation; adds attenuation-only safety ceiling."
    appendFileLine: enginePath$, "#   - Dependency failures are written to the engine log for the Praat front end."
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# Usage (normally invoked by Praat_RF_Concatenative.praat, not by hand):"
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "#   python rf_engine.py --input in.wav --output out.wav"
    appendFileLine: enginePath$, "#                       --stats stats.txt --log log.txt"
    appendFileLine: enginePath$, "#                       --target-duration 10.0"
    appendFileLine: enginePath$, "#                       --frame-ms 100 --hop-ms 25"
    appendFileLine: enginePath$, "#                       --trajectory crescendo_brightening"
    appendFileLine: enginePath$, "#                       --trees 100 --max-depth 15 --lookahead 1"
    appendFileLine: enginePath$, "#                       --traj-weight 0.6 --repeat-penalty 0.5 --seed 42"
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# Architecture:"
    appendFileLine: enginePath$, "#   Stage 1 - Load source audio at native sample rate, preserve all channels,"
    appendFileLine: enginePath$, "#             and analyse the strongest-RMS real channel."
    appendFileLine: enginePath$, "#   Stage 2 - Window into overlapping grains and extract a 17-dimensional"
    appendFileLine: enginePath$, "#             feature vector per grain:"
    appendFileLine: enginePath$, "#               [0] RMS energy"
    appendFileLine: enginePath$, "#               [1] spectral centroid"
    appendFileLine: enginePath$, "#               [2] spectral flatness"
    appendFileLine: enginePath$, "#               [3] zero-crossing rate"
    appendFileLine: enginePath$, "#               [4..16] MFCCs 1-13 (coefficient 0 dropped: it is gain)"
    appendFileLine: enginePath$, "#             Standardise the whole pool with StandardScaler."
    appendFileLine: enginePath$, "#   Stage 3 - Train a multi-target RandomForestRegressor on transition pairs"
    appendFileLine: enginePath$, "#             X_t -> X_{t+k}. Report row-wise OOB R^2 as a diagnostic and,"
    appendFileLine: enginePath$, "#             more importantly, OOB skill relative to the persistence"
    appendFileLine: enginePath$, "#             baseline Y=X. Overlapping grains make raw OOB R^2 optimistic."
    appendFileLine: enginePath$, "#   Stage 4 - Synthesise a target trajectory of the requested duration in"
    appendFileLine: enginePath$, "#             the SAME standardised space (units are corpus SDs)."
    appendFileLine: enginePath$, "#   Stage 5 - Walk the trajectory. At every output step the forest predicts"
    appendFileLine: enginePath$, "#             the natural continuation of the current state; that prediction"
    appendFileLine: enginePath$, "#             is blended with the target and the blend is matched against"
    appendFileLine: enginePath$, "#             the grain pool by L2 distance (scipy.spatial.distance.cdist)."
    appendFileLine: enginePath$, "#   Stage 6 - Apply the chosen grain indices to every source channel,"
    appendFileLine: enginePath$, "#             Hann-window and overlap-add, divide by the accumulated window"
    appendFileLine: enginePath$, "#             envelope, optionally match global RMS to the source, then apply"
    appendFileLine: enginePath$, "#             an attenuation-only safety ceiling and write with soundfile."
    appendFileLine: enginePath$, "#   Stage 7 - Write a key=value stats file for the Praat front end."
    appendFileLine: enginePath$, "#"
    appendFileLine: enginePath$, "# ASCII-only and free of apostrophes on purpose: this file is also embedded"
    appendFileLine: enginePath$, "# verbatim inside the Praat script, where a single quote would trigger"
    appendFileLine: enginePath$, "# Praat variable interpolation."
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "import sys"
    appendFileLine: enginePath$, "import time"
    appendFileLine: enginePath$, "import argparse"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# --------------------------------------------------------------------------"
    appendFileLine: enginePath$, "# Feature layout"
    appendFileLine: enginePath$, "# --------------------------------------------------------------------------"
    appendFileLine: enginePath$, "IDX_RMS      = 0"
    appendFileLine: enginePath$, "IDX_CENTROID = 1"
    appendFileLine: enginePath$, "IDX_FLATNESS = 2"
    appendFileLine: enginePath$, "IDX_ZCR      = 3"
    appendFileLine: enginePath$, "IDX_MFCC1    = 4          # MFCCs 1-13 occupy 4..16"
    appendFileLine: enginePath$, "N_MFCC_KEPT  = 13"
    appendFileLine: enginePath$, "FEATURE_DIM  = 4 + N_MFCC_KEPT"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "N_MELS         = 40       # mel bands for the MFCC front end"
    appendFileLine: enginePath$, "MAX_TRAIN_ROWS = 20000    # cap on RF training rows (10 min at 25 ms = 24k)"
    appendFileLine: enginePath$, "MAX_PLOT_PTS   = 500      # cap on per-step series handed back to Praat"
    appendFileLine: enginePath$, "MAX_RMS_MATCH_GAIN = 4.0   # +12.04 dB guard against pathological quiet selections"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "TRAJECTORIES = [""crescendo_brightening"", ""spectral_descent"", ""random_walk""]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# --------------------------------------------------------------------------"
    appendFileLine: enginePath$, "# Logging -- everything printed also lands in a file Praat can read back"
    appendFileLine: enginePath$, "# --------------------------------------------------------------------------"
    appendFileLine: enginePath$, "class Log(object):"
    appendFileLine: enginePath$, "    def __init__(self, path):"
    appendFileLine: enginePath$, "        self.fh = None"
    appendFileLine: enginePath$, "        if path:"
    appendFileLine: enginePath$, "            try:"
    appendFileLine: enginePath$, "                self.fh = open(path, ""w"")"
    appendFileLine: enginePath$, "            except IOError:"
    appendFileLine: enginePath$, "                self.fh = None"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    def __call__(self, msg):"
    appendFileLine: enginePath$, "        print(msg)"
    appendFileLine: enginePath$, "        sys.stdout.flush()"
    appendFileLine: enginePath$, "        if self.fh is not None:"
    appendFileLine: enginePath$, "            self.fh.write(msg + chr(10))"
    appendFileLine: enginePath$, "            self.fh.flush()"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    def close(self):"
    appendFileLine: enginePath$, "        if self.fh is not None:"
    appendFileLine: enginePath$, "            self.fh.close()"
    appendFileLine: enginePath$, "            self.fh = None"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def check_dependencies(log=None):"
    appendFileLine: enginePath$, "    missing = []"
    appendFileLine: enginePath$, "    for pkg in [""numpy"", ""scipy"", ""librosa"", ""sklearn"", ""soundfile""]:"
    appendFileLine: enginePath$, "        try:"
    appendFileLine: enginePath$, "            __import__(pkg)"
    appendFileLine: enginePath$, "        except ImportError:"
    appendFileLine: enginePath$, "            missing.append(pkg)"
    appendFileLine: enginePath$, "    if missing:"
    appendFileLine: enginePath$, "        pip = [""scikit-learn"" if m == ""sklearn"" else m for m in missing]"
    appendFileLine: enginePath$, "        msg = ""ERROR: missing packages: "" + "", "".join(missing)"
    appendFileLine: enginePath$, "        install = ""Install with:  pip install "" + "" "".join(pip)"
    appendFileLine: enginePath$, "        if log is not None:"
    appendFileLine: enginePath$, "            log(msg)"
    appendFileLine: enginePath$, "            log(install)"
    appendFileLine: enginePath$, "            log.close()"
    appendFileLine: enginePath$, "        sys.stderr.write(msg + chr(10))"
    appendFileLine: enginePath$, "        sys.stderr.write(install + chr(10))"
    appendFileLine: enginePath$, "        sys.exit(1)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 1 -- Load"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def load_audio(path, log):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    import soundfile as sf"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    data, sr = sf.read(path, dtype=""float64"", always_2d=True)"
    appendFileLine: enginePath$, "    if data.shape[0] == 0:"
    appendFileLine: enginePath$, "        sys.stderr.write(""ERROR: input file decoded to zero samples."" + chr(10))"
    appendFileLine: enginePath$, "        sys.exit(1)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # Internal layout is channels x samples so one chosen grain index can be"
    appendFileLine: enginePath$, "    # applied to all channels without destroying the source spatial image."
    appendFileLine: enginePath$, "    audio = np.asarray(data.T, dtype=np.float64)"
    appendFileLine: enginePath$, "    n_channels, n_samples = audio.shape"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    if n_channels == 1:"
    appendFileLine: enginePath$, "        analysis_channel = 0"
    appendFileLine: enginePath$, "        analysis = audio[0].copy()"
    appendFileLine: enginePath$, "        analysis_source = ""channel 1 (mono input)"""
    appendFileLine: enginePath$, "    else:"
    appendFileLine: enginePath$, "        # Analyse one real channel rather than an arithmetic fold. A fold can"
    appendFileLine: enginePath$, "        # cancel or spectrally reshape correlated multichannel material. The"
    appendFileLine: enginePath$, "        # strongest-RMS channel is a stable representative while resynthesis"
    appendFileLine: enginePath$, "        # still applies every selected grain index to every source channel."
    appendFileLine: enginePath$, "        ch_rms = np.sqrt(np.mean(audio * audio, axis=1))"
    appendFileLine: enginePath$, "        analysis_channel = int(np.argmax(ch_rms))"
    appendFileLine: enginePath$, "        analysis = audio[analysis_channel].copy()"
    appendFileLine: enginePath$, "        analysis_source = ""channel %d (strongest RMS)"" % (analysis_channel + 1)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""    Loaded %.2f s at %d Hz, %d channel%s (%d samples/channel)"""
    appendFileLine: enginePath$, "        % (n_samples / float(sr), sr, n_channels,"
    appendFileLine: enginePath$, "           """" if n_channels == 1 else ""s"", n_samples))"
    appendFileLine: enginePath$, "    log(""    Analysis source: %s"" % analysis_source)"
    appendFileLine: enginePath$, "    return audio, analysis, sr, analysis_source, analysis_channel + 1"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 2 -- Grain features"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def extract_features(y, sr, frame_len, hop_len, log):"
    appendFileLine: enginePath$, "    # Build the STFT ONCE. In v0.1 centroid, flatness and MFCC each caused a"
    appendFileLine: enginePath$, "    # separate spectral front end. Passing the same S into the feature calls"
    appendFileLine: enginePath$, "    # is exactly equivalent while avoiding redundant FFT work."
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    import librosa"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n_frames = 1 + (y.size - frame_len) // hop_len"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    S = np.abs(librosa.stft("
    appendFileLine: enginePath$, "        y, n_fft=frame_len, hop_length=hop_len, win_length=frame_len,"
    appendFileLine: enginePath$, "        window=""hann"", center=False))"
    appendFileLine: enginePath$, "    freqs = librosa.fft_frequencies(sr=sr, n_fft=frame_len)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    rms = librosa.feature.rms("
    appendFileLine: enginePath$, "        y=y, frame_length=frame_len, hop_length=hop_len, center=False)[0]"
    appendFileLine: enginePath$, "    cen = librosa.feature.spectral_centroid(S=S, freq=freqs)[0]"
    appendFileLine: enginePath$, "    flt = librosa.feature.spectral_flatness(S=S)[0]"
    appendFileLine: enginePath$, "    zcr = librosa.feature.zero_crossing_rate("
    appendFileLine: enginePath$, "        y, frame_length=frame_len, hop_length=hop_len, center=False)[0]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n_mels_eff = min(N_MELS, 1 + frame_len // 2)"
    appendFileLine: enginePath$, "    mel = librosa.feature.melspectrogram("
    appendFileLine: enginePath$, "        S=S ** 2, sr=sr, n_fft=frame_len, n_mels=n_mels_eff)"
    appendFileLine: enginePath$, "    mfc = librosa.feature.mfcc("
    appendFileLine: enginePath$, "        S=librosa.power_to_db(mel), sr=sr, n_mfcc=N_MFCC_KEPT + 1)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n = min(n_frames, rms.size, cen.size, flt.size, zcr.size, mfc.shape[1])"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    F = np.zeros((n, FEATURE_DIM), dtype=np.float64)"
    appendFileLine: enginePath$, "    F[:, IDX_RMS]      = rms[:n]"
    appendFileLine: enginePath$, "    F[:, IDX_CENTROID] = cen[:n]"
    appendFileLine: enginePath$, "    F[:, IDX_FLATNESS] = flt[:n]"
    appendFileLine: enginePath$, "    F[:, IDX_ZCR]      = zcr[:n]"
    appendFileLine: enginePath$, "    F[:, IDX_MFCC1:]   = mfc[1:N_MFCC_KEPT + 1, :n].T"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    F = np.nan_to_num(F, nan=0.0, posinf=0.0, neginf=0.0)"
    appendFileLine: enginePath$, "    log(""    Grain pool: %d grains x %d features"" % (n, FEATURE_DIM))"
    appendFileLine: enginePath$, "    return F"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def scale_features(F, log):"
    appendFileLine: enginePath$, "    from sklearn.preprocessing import StandardScaler"
    appendFileLine: enginePath$, "    scaler = StandardScaler()"
    appendFileLine: enginePath$, "    Z = scaler.fit_transform(F)"
    appendFileLine: enginePath$, "    log(""    Standardised (mean 0, SD 1 per dimension)"")"
    appendFileLine: enginePath$, "    return Z, scaler"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 3 -- Random Forest transition model"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def train_forest(Z, lookahead, trees, max_depth, seed, log):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    from sklearn.ensemble import RandomForestRegressor"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n = Z.shape[0]"
    appendFileLine: enginePath$, "    X = Z[:n - lookahead]"
    appendFileLine: enginePath$, "    Y = Z[lookahead:]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n_rows = X.shape[0]"
    appendFileLine: enginePath$, "    if n_rows > MAX_TRAIN_ROWS:"
    appendFileLine: enginePath$, "        step = int(np.ceil(n_rows / float(MAX_TRAIN_ROWS)))"
    appendFileLine: enginePath$, "        X = X[::step]"
    appendFileLine: enginePath$, "        Y = Y[::step]"
    appendFileLine: enginePath$, "        log(""    Subsampled %d -> %d training rows (stride %d)"""
    appendFileLine: enginePath$, "            % (n_rows, X.shape[0], step))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # OOB rows are useful diagnostics but overlapping grains are strongly"
    appendFileLine: enginePath$, "    # autocorrelated, so OOB R^2 must not be read as independent validation."
    appendFileLine: enginePath$, "    # Skill vs persistence asks a more relevant question: does the forest beat"
    appendFileLine: enginePath$, "    # the trivial predictor that the next standardised state equals this one?"
    appendFileLine: enginePath$, "    use_oob = X.shape[0] >= 10 and trees >= 20"
    appendFileLine: enginePath$, "    rf = RandomForestRegressor("
    appendFileLine: enginePath$, "        n_estimators=trees,"
    appendFileLine: enginePath$, "        max_depth=(None if max_depth <= 0 else max_depth),"
    appendFileLine: enginePath$, "        n_jobs=-1,"
    appendFileLine: enginePath$, "        oob_score=use_oob,"
    appendFileLine: enginePath$, "        random_state=seed,"
    appendFileLine: enginePath$, "    )"
    appendFileLine: enginePath$, "    t0 = time.time()"
    appendFileLine: enginePath$, "    rf.fit(X, Y)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    oob = float(""nan"")"
    appendFileLine: enginePath$, "    oob_skill = float(""nan"")"
    appendFileLine: enginePath$, "    if use_oob:"
    appendFileLine: enginePath$, "        oob = float(getattr(rf, ""oob_score_"", float(""nan"")))"
    appendFileLine: enginePath$, "        pred = np.asarray(getattr(rf, ""oob_prediction_"", np.empty((0, 0))))"
    appendFileLine: enginePath$, "        if pred.shape == Y.shape:"
    appendFileLine: enginePath$, "            mse_rf = float(np.mean((Y - pred) ** 2))"
    appendFileLine: enginePath$, "            mse_persist = float(np.mean((Y - X) ** 2))"
    appendFileLine: enginePath$, "            if mse_persist > 1e-15:"
    appendFileLine: enginePath$, "                oob_skill = 1.0 - mse_rf / mse_persist"
    appendFileLine: enginePath$, "            elif mse_rf <= 1e-15:"
    appendFileLine: enginePath$, "                oob_skill = 0.0"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""    Fitted %d trees (depth %s) on %d rows in %.1f s"""
    appendFileLine: enginePath$, "        % (trees, ""None"" if max_depth <= 0 else str(max_depth),"
    appendFileLine: enginePath$, "           X.shape[0], time.time() - t0))"
    appendFileLine: enginePath$, "    if use_oob:"
    appendFileLine: enginePath$, "        log(""    OOB row R^2: %.4f (optimistic with overlapping grains)"" % oob)"
    appendFileLine: enginePath$, "        log(""    OOB skill vs persistence: %.4f"" % oob_skill)"
    appendFileLine: enginePath$, "    else:"
    appendFileLine: enginePath$, "        log(""    OOB diagnostics disabled (need >=20 trees and >=10 rows)"")"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # Parallel tree fitting is useful; parallel prediction on ONE state at a"
    appendFileLine: enginePath$, "    # time is much slower and can alter tie-breaking through tiny summation"
    appendFileLine: enginePath$, "    # order differences. Serial prediction is faster here and reproducible."
    appendFileLine: enginePath$, "    rf.n_jobs = 1"
    appendFileLine: enginePath$, "    return rf, X.shape[0], oob, oob_skill"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 4 -- Target trajectory (standardised space, units = corpus SDs)"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def smoothstep(t):"
    appendFileLine: enginePath$, "    return t * t * (3.0 - 2.0 * t)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def smooth_columns(T, win):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    if win < 3:"
    appendFileLine: enginePath$, "        return T"
    appendFileLine: enginePath$, "    k = np.hanning(win)"
    appendFileLine: enginePath$, "    k = k / k.sum()"
    appendFileLine: enginePath$, "    out = np.empty_like(T)"
    appendFileLine: enginePath$, "    for d in range(T.shape[1]):"
    appendFileLine: enginePath$, "        pad = np.concatenate(["
    appendFileLine: enginePath$, "            np.full(win, T[0, d]), T[:, d], np.full(win, T[-1, d])])"
    appendFileLine: enginePath$, "        out[:, d] = np.convolve(pad, k, mode=""same"")[win:win + T.shape[0]]"
    appendFileLine: enginePath$, "    return out"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def make_trajectory(kind, n_steps, seed, log):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    rng = np.random.RandomState(seed)"
    appendFileLine: enginePath$, "    T = np.zeros((n_steps, FEATURE_DIM), dtype=np.float64)"
    appendFileLine: enginePath$, "    u = smoothstep(np.linspace(0.0, 1.0, n_steps))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    if kind == ""crescendo_brightening"":"
    appendFileLine: enginePath$, "        # Quiet and dull to loud and bright. MFCC1 tracks spectral tilt and"
    appendFileLine: enginePath$, "        # falls as energy moves upward, so it is ramped the other way."
    appendFileLine: enginePath$, "        T[:, IDX_RMS]      = -1.6 + 3.2 * u"
    appendFileLine: enginePath$, "        T[:, IDX_CENTROID] = -1.4 + 3.0 * u"
    appendFileLine: enginePath$, "        T[:, IDX_ZCR]      = -1.0 + 2.2 * u"
    appendFileLine: enginePath$, "        T[:, IDX_FLATNESS] = -0.4 + 0.8 * u"
    appendFileLine: enginePath$, "        T[:, IDX_MFCC1]    = 1.0 - 2.0 * u"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    elif kind == ""spectral_descent"":"
    appendFileLine: enginePath$, "        # Falling spectral register/brightness: no explicit F0 feature is used."
    appendFileLine: enginePath$, "        T[:, IDX_CENTROID] = 1.6 - 3.2 * u"
    appendFileLine: enginePath$, "        T[:, IDX_ZCR]      = 1.4 - 2.8 * u"
    appendFileLine: enginePath$, "        T[:, IDX_MFCC1]    = -1.2 + 2.4 * u"
    appendFileLine: enginePath$, "        T[:, IDX_RMS]      = 0.6 * np.sin(np.pi * u)"
    appendFileLine: enginePath$, "        T[:, IDX_FLATNESS] = 0.3 - 0.6 * u"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    else:"
    appendFileLine: enginePath$, "        # Ornstein-Uhlenbeck walk on every dimension: mean-reverting, so the"
    appendFileLine: enginePath$, "        # target stays inside the region the corpus actually occupies."
    appendFileLine: enginePath$, "        theta, sigma = 0.06, 0.35"
    appendFileLine: enginePath$, "        x = np.zeros(FEATURE_DIM)"
    appendFileLine: enginePath$, "        for t in range(n_steps):"
    appendFileLine: enginePath$, "            x = x * (1.0 - theta) + sigma * rng.randn(FEATURE_DIM)"
    appendFileLine: enginePath$, "            T[t] = x"
    appendFileLine: enginePath$, "        T = np.clip(T, -2.2, 2.2)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    T = smooth_columns(T, 9)"
    appendFileLine: enginePath$, "    log(""    Trajectory %s: %d steps, range %.2f to %.2f SD"""
    appendFileLine: enginePath$, "        % (kind, n_steps, float(T.min()), float(T.max())))"
    appendFileLine: enginePath$, "    return T"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 5 -- Forest-guided walk through the grain pool"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def median_nn_distance(Z, seed, sample=800):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    from scipy.spatial.distance import cdist"
    appendFileLine: enginePath$, "    rng = np.random.RandomState(seed)"
    appendFileLine: enginePath$, "    n = Z.shape[0]"
    appendFileLine: enginePath$, "    idx = rng.choice(n, size=min(sample, n), replace=False)"
    appendFileLine: enginePath$, "    D = cdist(Z[idx], Z[idx])"
    appendFileLine: enginePath$, "    np.fill_diagonal(D, np.inf)"
    appendFileLine: enginePath$, "    return float(np.median(D.min(axis=1)))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def median_pair_distance(Z, seed, sample=400):"
    appendFileLine: enginePath$, "    # Repeat cost needs a corpus-scale distance, not nearest-neighbour distance."
    appendFileLine: enginePath$, "    # With overlapping grains the nearest neighbour can be almost identical,"
    appendFileLine: enginePath$, "    # collapsing the old repeat penalty to nearly zero."
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    from scipy.spatial.distance import cdist"
    appendFileLine: enginePath$, "    rng = np.random.RandomState(seed + 17)"
    appendFileLine: enginePath$, "    n = Z.shape[0]"
    appendFileLine: enginePath$, "    idx = rng.choice(n, size=min(sample, n), replace=False)"
    appendFileLine: enginePath$, "    D = cdist(Z[idx], Z[idx])"
    appendFileLine: enginePath$, "    tri = D[np.triu_indices(idx.size, 1)]"
    appendFileLine: enginePath$, "    tri = tri[np.isfinite(tri) & (tri > 1e-9)]"
    appendFileLine: enginePath$, "    if tri.size == 0:"
    appendFileLine: enginePath$, "        return 1.0"
    appendFileLine: enginePath$, "    return float(np.median(tri))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def walk_pool(rf, Z, T, traj_weight, repeat_penalty, seed, log):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    from scipy.spatial.distance import cdist"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n_pool  = Z.shape[0]"
    appendFileLine: enginePath$, "    n_steps = T.shape[0]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    nn_scale = median_nn_distance(Z, seed)"
    appendFileLine: enginePath$, "    if not np.isfinite(nn_scale) or nn_scale < 0:"
    appendFileLine: enginePath$, "        nn_scale = 0.0"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    repeat_scale = median_pair_distance(Z, seed)"
    appendFileLine: enginePath$, "    if not np.isfinite(repeat_scale) or repeat_scale <= 0:"
    appendFileLine: enginePath$, "        repeat_scale = 1.0"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # Penalty is expressed in units of the median pairwise corpus distance."
    appendFileLine: enginePath$, "    # This stays meaningful even when overlap makes adjacent grains almost"
    appendFileLine: enginePath$, "    # identical. Only the exact grain is penalised, so natural j -> j+1 source"
    appendFileLine: enginePath$, "    # continuity remains available to the forest."
    appendFileLine: enginePath$, "    hit_cost = repeat_penalty * repeat_scale"
    appendFileLine: enginePath$, "    decay    = 0.5"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    penalty = np.zeros(n_pool)"
    appendFileLine: enginePath$, "    chosen, dists = [], []"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # Seed on the grain closest to the first target point."
    appendFileLine: enginePath$, "    state_idx = int(np.argmin(cdist(T[0:1], Z)[0]))"
    appendFileLine: enginePath$, "    state = Z[state_idx]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    t0 = time.time()"
    appendFileLine: enginePath$, "    for t in range(n_steps):"
    appendFileLine: enginePath$, "        pred = rf.predict(state.reshape(1, -1))[0]"
    appendFileLine: enginePath$, "        goal = (1.0 - traj_weight) * pred + traj_weight * T[t]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "        d = cdist(goal.reshape(1, -1), Z)[0]"
    appendFileLine: enginePath$, "        j = int(np.argmin(d + penalty))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "        chosen.append(j)"
    appendFileLine: enginePath$, "        dists.append(float(d[j]))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "        penalty *= decay"
    appendFileLine: enginePath$, "        penalty[j] += hit_cost"
    appendFileLine: enginePath$, "        state = Z[j]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    chosen = np.asarray(chosen, dtype=int)"
    appendFileLine: enginePath$, "    dists = np.asarray(dists)"
    appendFileLine: enginePath$, "    immediate_repeat_pct = (100.0 * float(np.mean(chosen[1:] == chosen[:-1]))"
    appendFileLine: enginePath$, "                            if chosen.size > 1 else 0.0)"
    appendFileLine: enginePath$, "    log(""    Walked %d steps in %.1f s"" % (n_steps, time.time() - t0))"
    appendFileLine: enginePath$, "    log(""    Repeat scale %.4f; immediate repeats %.1f%%"""
    appendFileLine: enginePath$, "        % (repeat_scale, immediate_repeat_pct))"
    appendFileLine: enginePath$, "    return chosen, dists, nn_scale, repeat_scale, immediate_repeat_pct"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 6 -- Overlap-add resynthesis"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def resynthesise(audio, chosen, frame_len, hop_len, out_samples,"
    appendFileLine: enginePath$, "                 match_input_rms, safety_peak, log):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    n_channels, n_source = audio.shape"
    appendFileLine: enginePath$, "    n_steps = chosen.size"
    appendFileLine: enginePath$, "    total   = (n_steps - 1) * hop_len + frame_len"
    appendFileLine: enginePath$, "    buf = np.zeros((n_channels, total), dtype=np.float64)"
    appendFileLine: enginePath$, "    env = np.zeros(total, dtype=np.float64)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    win = np.hanning(frame_len + 1)[:frame_len]   # periodic Hann"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    for t in range(n_steps):"
    appendFileLine: enginePath$, "        s = int(chosen[t]) * hop_len"
    appendFileLine: enginePath$, "        g = audio[:, s:s + frame_len]"
    appendFileLine: enginePath$, "        if g.shape[1] < frame_len:"
    appendFileLine: enginePath$, "            g = np.pad(g, ((0, 0), (0, frame_len - g.shape[1])))"
    appendFileLine: enginePath$, "        p = t * hop_len"
    appendFileLine: enginePath$, "        buf[:, p:p + frame_len] += g * win[None, :]"
    appendFileLine: enginePath$, "        env[p:p + frame_len] += win"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # Weighted average of overlapping, potentially unrelated grains."
    appendFileLine: enginePath$, "    floor = 0.05 * float(env.max()) if env.max() > 0 else 1.0"
    appendFileLine: enginePath$, "    out = buf / np.maximum(env[None, :], floor)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    if out.shape[1] >= out_samples:"
    appendFileLine: enginePath$, "        out = out[:, :out_samples]"
    appendFileLine: enginePath$, "    else:"
    appendFileLine: enginePath$, "        out = np.pad(out, ((0, 0), (0, out_samples - out.shape[1])))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # Fade the FINAL buffer. Fading before trimming can cut off the end of the"
    appendFileLine: enginePath$, "    # fade whenever target duration is not aligned to the hop grid."
    appendFileLine: enginePath$, "    out = apply_edge_fades(out, frame_len)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    input_rms = float(np.sqrt(np.mean(audio * audio))) if audio.size else 0.0"
    appendFileLine: enginePath$, "    rms_before_match = float(np.sqrt(np.mean(out * out))) if out.size else 0.0"
    appendFileLine: enginePath$, "    rms_gain = 1.0"
    appendFileLine: enginePath$, "    rms_limited = 0"
    appendFileLine: enginePath$, "    if match_input_rms and input_rms > 1e-15 and rms_before_match > 1e-15:"
    appendFileLine: enginePath$, "        wanted = input_rms / rms_before_match"
    appendFileLine: enginePath$, "        if wanted > MAX_RMS_MATCH_GAIN:"
    appendFileLine: enginePath$, "            wanted = MAX_RMS_MATCH_GAIN"
    appendFileLine: enginePath$, "            rms_limited = 1"
    appendFileLine: enginePath$, "        rms_gain = wanted"
    appendFileLine: enginePath$, "        out = out * rms_gain"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    rms_after_match = float(np.sqrt(np.mean(out * out))) if out.size else 0.0"
    appendFileLine: enginePath$, "    peak_before = float(np.max(np.abs(out))) if out.size else 0.0"
    appendFileLine: enginePath$, "    if safety_peak > 0.0 and peak_before > safety_peak:"
    appendFileLine: enginePath$, "        out = out * (safety_peak / peak_before)"
    appendFileLine: enginePath$, "    peak_after = float(np.max(np.abs(out))) if out.size else 0.0"
    appendFileLine: enginePath$, "    output_rms = float(np.sqrt(np.mean(out * out))) if out.size else 0.0"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""    Overlap-added %d grains -> %d samples x %d ch"""
    appendFileLine: enginePath$, "        % (n_steps, out.shape[1], n_channels))"
    appendFileLine: enginePath$, "    if match_input_rms:"
    appendFileLine: enginePath$, "        gain_db = 20.0 * np.log10(max(rms_gain, 1e-15))"
    appendFileLine: enginePath$, "        log(""    RMS %.4f -> %.4f; source %.4f; level gain %+.2f dB%s"""
    appendFileLine: enginePath$, "            % (rms_before_match, rms_after_match, input_rms, gain_db,"
    appendFileLine: enginePath$, "               "" (limited)"" if rms_limited else """"))"
    appendFileLine: enginePath$, "    else:"
    appendFileLine: enginePath$, "        log(""    RMS matching disabled; output RMS %.4f"" % rms_before_match)"
    appendFileLine: enginePath$, "    log(""    Peak %.4f before safety, %.4f after"" % (peak_before, peak_after))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # soundfile expects samples x channels."
    appendFileLine: enginePath$, "    return (out.T.astype(np.float32), peak_before, peak_after, input_rms,"
    appendFileLine: enginePath$, "            rms_before_match, rms_after_match, output_rms, rms_gain, rms_limited)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def apply_edge_fades(x, frame_len):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    n = min(frame_len, x.shape[1] // 2)"
    appendFileLine: enginePath$, "    if n < 2:"
    appendFileLine: enginePath$, "        return x"
    appendFileLine: enginePath$, "    ramp = np.hanning(2 * n)[:n]"
    appendFileLine: enginePath$, "    x = x.copy()"
    appendFileLine: enginePath$, "    x[:, :n] *= ramp[None, :]"
    appendFileLine: enginePath$, "    x[:, -n:] *= ramp[::-1][None, :]"
    appendFileLine: enginePath$, "    return x"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Stage 7 -- Stats for the Praat front end"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def subsample(a, cap):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    if a.size <= cap:"
    appendFileLine: enginePath$, "        return a"
    appendFileLine: enginePath$, "    idx = np.linspace(0, a.size - 1, cap).astype(int)"
    appendFileLine: enginePath$, "    return a[idx]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def write_stats(path, args, sr, n_source_samples, n_channels,"
    appendFileLine: enginePath$, "                analysis_source, analysis_channel, F_rows, chosen, dists, out,"
    appendFileLine: enginePath$, "                peak_before, peak_after, input_rms, rms_before_match,"
    appendFileLine: enginePath$, "                rms_after_match, output_rms, rms_gain, rms_limited,"
    appendFileLine: enginePath$, "                train_rows, oob, oob_skill, nn_scale, repeat_scale,"
    appendFileLine: enginePath$, "                immediate_repeat_pct, hop_len, frame_len, elapsed, warnings):"
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    distinct = int(np.unique(chosen).size)"
    appendFileLine: enginePath$, "    if chosen.size <= MAX_PLOT_PTS:"
    appendFileLine: enginePath$, "        plot_idx = np.arange(chosen.size, dtype=int)"
    appendFileLine: enginePath$, "    else:"
    appendFileLine: enginePath$, "        plot_idx = np.linspace(0, chosen.size - 1, MAX_PLOT_PTS).astype(int)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    src_t = chosen[plot_idx].astype(np.float64) * hop_len / float(sr)"
    appendFileLine: enginePath$, "    out_t = plot_idx.astype(np.float64) * hop_len / float(sr)"
    appendFileLine: enginePath$, "    mdist = dists[plot_idx]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    with open(path, ""w"") as f:"
    appendFileLine: enginePath$, "        p = lambda s: print(s, file=f)"
    appendFileLine: enginePath$, "        p(""n_pool_grains=%d""     % F_rows)"
    appendFileLine: enginePath$, "        p(""n_output_grains=%d""   % chosen.size)"
    appendFileLine: enginePath$, "        p(""sample_rate=%d""       % sr)"
    appendFileLine: enginePath$, "        p(""input_channels=%d""    % n_channels)"
    appendFileLine: enginePath$, "        p(""output_channels=%d""   % (1 if out.ndim == 1 else out.shape[1]))"
    appendFileLine: enginePath$, "        p(""analysis_source=%s""   % analysis_source)"
    appendFileLine: enginePath$, "        p(""analysis_channel=%d""  % analysis_channel)"
    appendFileLine: enginePath$, "        p(""frame_samples=%d""     % frame_len)"
    appendFileLine: enginePath$, "        p(""hop_samples=%d""       % hop_len)"
    appendFileLine: enginePath$, "        p(""overlap_pct=%.1f""     % (100.0 * (1.0 - hop_len / float(frame_len))))"
    appendFileLine: enginePath$, "        p(""input_duration=%.3f""  % (n_source_samples / float(sr)))"
    appendFileLine: enginePath$, "        p(""output_duration=%.3f"" % (out.shape[0] / float(sr)))"
    appendFileLine: enginePath$, "        p(""feature_dim=%d""       % FEATURE_DIM)"
    appendFileLine: enginePath$, "        p(""rf_train_rows=%d""     % train_rows)"
    appendFileLine: enginePath$, "        p(""rf_oob_r2=%.4f""       % oob)"
    appendFileLine: enginePath$, "        p(""rf_oob_skill=%.4f""    % oob_skill)"
    appendFileLine: enginePath$, "        p(""trajectory=%s""        % args.trajectory)"
    appendFileLine: enginePath$, "        p(""traj_weight=%.3f""     % args.traj_weight)"
    appendFileLine: enginePath$, "        p(""repeat_penalty=%.3f""  % args.repeat_penalty)"
    appendFileLine: enginePath$, "        p(""distinct_grains=%d""   % distinct)"
    appendFileLine: enginePath$, "        p(""distinct_pct=%.1f""    % (100.0 * distinct / max(1, chosen.size)))"
    appendFileLine: enginePath$, "        p(""mean_match_dist=%.4f"" % float(np.mean(dists)))"
    appendFileLine: enginePath$, "        p(""median_nn_dist=%.4f""  % nn_scale)"
    appendFileLine: enginePath$, "        p(""repeat_distance_scale=%.4f"" % repeat_scale)"
    appendFileLine: enginePath$, "        p(""immediate_repeat_pct=%.1f"" % immediate_repeat_pct)"
    appendFileLine: enginePath$, "        p(""match_input_rms=%d""   % int(bool(args.match_input_rms)))"
    appendFileLine: enginePath$, "        p(""source_rms=%.6f""       % input_rms)"
    appendFileLine: enginePath$, "        p(""rms_before_match=%.6f"" % rms_before_match)"
    appendFileLine: enginePath$, "        p(""rms_after_match=%.6f""  % rms_after_match)"
    appendFileLine: enginePath$, "        p(""rms_match_gain=%.6f""   % rms_gain)"
    appendFileLine: enginePath$, "        p(""rms_match_gain_db=%.3f"" % (20.0 * np.log10(max(rms_gain, 1e-15))))"
    appendFileLine: enginePath$, "        p(""rms_match_limited=%d""  % rms_limited)"
    appendFileLine: enginePath$, "        p(""peak_before_safety=%.4f"" % peak_before)"
    appendFileLine: enginePath$, "        p(""output_peak=%.4f""      % peak_after)"
    appendFileLine: enginePath$, "        p(""out_rms=%.6f""          % output_rms)"
    appendFileLine: enginePath$, "        p(""elapsed_s=%.1f""       % elapsed)"
    appendFileLine: enginePath$, "        p(""n_points=%d""          % src_t.size)"
    appendFileLine: enginePath$, "        p(""src_times=%s""         % "","".join(""%.3f"" % v for v in src_t))"
    appendFileLine: enginePath$, "        p(""out_times=%s""         % "","".join(""%.3f"" % v for v in out_t))"
    appendFileLine: enginePath$, "        p(""match_dists=%s""       % "","".join(""%.3f"" % v for v in mdist))"
    appendFileLine: enginePath$, "        if warnings:"
    appendFileLine: enginePath$, "            p(""warning=%s"" % ""; "".join(warnings))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, "# Main"
    appendFileLine: enginePath$, "# =========================================================================="
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def build_parser():"
    appendFileLine: enginePath$, "    ap = argparse.ArgumentParser("
    appendFileLine: enginePath$, "        description=""Random Forest concatenative synthesis engine"")"
    appendFileLine: enginePath$, "    ap.add_argument(""--input"",  required=True)"
    appendFileLine: enginePath$, "    ap.add_argument(""--output"", required=True)"
    appendFileLine: enginePath$, "    ap.add_argument(""--stats"",  default="""")"
    appendFileLine: enginePath$, "    ap.add_argument(""--log"",    default="""")"
    appendFileLine: enginePath$, "    ap.add_argument(""--target-duration"", type=float, default=10.0)"
    appendFileLine: enginePath$, "    ap.add_argument(""--frame-ms"",        type=float, default=100.0)"
    appendFileLine: enginePath$, "    ap.add_argument(""--hop-ms"",          type=float, default=25.0)"
    appendFileLine: enginePath$, "    ap.add_argument(""--trajectory"",      default=""crescendo_brightening"")"
    appendFileLine: enginePath$, "    ap.add_argument(""--trees"",           type=int,   default=100)"
    appendFileLine: enginePath$, "    ap.add_argument(""--max-depth"",       type=int,   default=15)"
    appendFileLine: enginePath$, "    ap.add_argument(""--lookahead"",       type=int,   default=1)"
    appendFileLine: enginePath$, "    ap.add_argument(""--traj-weight"",     type=float, default=0.6)"
    appendFileLine: enginePath$, "    ap.add_argument(""--repeat-penalty"",  type=float, default=0.5)"
    appendFileLine: enginePath$, "    ap.add_argument(""--seed"",            type=int,   default=42)"
    appendFileLine: enginePath$, "    ap.add_argument(""--match-input-rms"", type=int,   default=1)"
    appendFileLine: enginePath$, "    ap.add_argument(""--safety-peak"",     type=float, default=0.99)"
    appendFileLine: enginePath$, "    return ap"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "def main():"
    appendFileLine: enginePath$, "    args = build_parser().parse_args()"
    appendFileLine: enginePath$, "    log = Log(args.log)"
    appendFileLine: enginePath$, "    check_dependencies(log)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    import numpy as np"
    appendFileLine: enginePath$, "    import soundfile as sf"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    t_start = time.time()"
    appendFileLine: enginePath$, "    warnings = []"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    # -- clamp -------------------------------------------------------------"
    appendFileLine: enginePath$, "    args.target_duration = max(0.5, min(600.0, args.target_duration))"
    appendFileLine: enginePath$, "    args.frame_ms        = max(5.0, min(2000.0, args.frame_ms))"
    appendFileLine: enginePath$, "    args.hop_ms          = max(1.0, min(args.frame_ms, args.hop_ms))"
    appendFileLine: enginePath$, "    args.trees           = max(1, min(1000, args.trees))"
    appendFileLine: enginePath$, "    args.lookahead       = max(1, min(50, args.lookahead))"
    appendFileLine: enginePath$, "    args.traj_weight     = max(0.0, min(1.0, args.traj_weight))"
    appendFileLine: enginePath$, "    args.repeat_penalty  = max(0.0, min(10.0, args.repeat_penalty))"
    appendFileLine: enginePath$, "    args.match_input_rms = 1 if args.match_input_rms else 0"
    appendFileLine: enginePath$, "    args.safety_peak     = max(0.0, min(1.0, args.safety_peak))"
    appendFileLine: enginePath$, "    if args.trajectory == ""pitch_descent"":"
    appendFileLine: enginePath$, "        warnings.append(""pitch_descent is a legacy alias; using spectral_descent"")"
    appendFileLine: enginePath$, "        args.trajectory = ""spectral_descent"""
    appendFileLine: enginePath$, "    if args.trajectory not in TRAJECTORIES:"
    appendFileLine: enginePath$, "        warnings.append(""unknown trajectory %s, using %s"""
    appendFileLine: enginePath$, "                        % (args.trajectory, TRAJECTORIES[0]))"
    appendFileLine: enginePath$, "        args.trajectory = TRAJECTORIES[0]"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""=== rf_engine.py -- Random Forest Concatenative Synthesis ==="")"
    appendFileLine: enginePath$, "    log(""  [Py 1/6] Loading audio..."")"
    appendFileLine: enginePath$, "    audio, y, sr, analysis_source, analysis_channel = load_audio(args.input, log)"
    appendFileLine: enginePath$, "    n_channels, n_source_samples = audio.shape"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    frame_len = int(round(args.frame_ms * 0.001 * sr))"
    appendFileLine: enginePath$, "    hop_len   = int(round(args.hop_ms   * 0.001 * sr))"
    appendFileLine: enginePath$, "    min_frame_for_mfcc = 2 * N_MFCC_KEPT"
    appendFileLine: enginePath$, "    if frame_len < min_frame_for_mfcc:"
    appendFileLine: enginePath$, "        warnings.append(""grain length raised from %d to %d samples so 13 MFCCs """
    appendFileLine: enginePath$, "                        ""have enough FFT bins"" % (frame_len, min_frame_for_mfcc))"
    appendFileLine: enginePath$, "        frame_len = min_frame_for_mfcc"
    appendFileLine: enginePath$, "    hop_len = max(1, min(frame_len, hop_len))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    if n_source_samples < frame_len * 4:"
    appendFileLine: enginePath$, "        sys.stderr.write(""ERROR: input is shorter than four grains """
    appendFileLine: enginePath$, "                         ""(%d samples, grain = %d)."" % (n_source_samples, frame_len) + chr(10))"
    appendFileLine: enginePath$, "        sys.exit(1)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    overlap_pct = 100.0 * (1.0 - hop_len / float(frame_len))"
    appendFileLine: enginePath$, "    log(""    Grain %d samples (%.1f ms), hop %d samples (%.1f ms), overlap %.0f%%"""
    appendFileLine: enginePath$, "        % (frame_len, 1000.0 * frame_len / sr, hop_len,"
    appendFileLine: enginePath$, "           1000.0 * hop_len / sr, overlap_pct))"
    appendFileLine: enginePath$, "    if overlap_pct < 25.0:"
    appendFileLine: enginePath$, "        # Below 25 percent the summed Hann envelope dips towards zero between"
    appendFileLine: enginePath$, "        # grains; the envelope floor in resynthesise() then leaves an audible"
    appendFileLine: enginePath$, "        # discontinuity at every grain boundary."
    appendFileLine: enginePath$, "        warnings.append(""overlap is only %.0f%%; expect clicks at grain """
    appendFileLine: enginePath$, "                        ""boundaries (hop 25%% of frame is the safe default)"""
    appendFileLine: enginePath$, "                        % overlap_pct)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""  [Py 2/6] Extracting grain features..."")"
    appendFileLine: enginePath$, "    F = extract_features(y, sr, frame_len, hop_len, log)"
    appendFileLine: enginePath$, "    if F.shape[0] <= args.lookahead + 4:"
    appendFileLine: enginePath$, "        sys.stderr.write(""ERROR: only %d grains, too few to train on."""
    appendFileLine: enginePath$, "                         % F.shape[0] + chr(10))"
    appendFileLine: enginePath$, "        sys.exit(1)"
    appendFileLine: enginePath$, "    Z, _ = scale_features(F, log)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""  [Py 3/6] Training Random Forest (%d trees, depth %d, k=%d)..."""
    appendFileLine: enginePath$, "        % (args.trees, args.max_depth, args.lookahead))"
    appendFileLine: enginePath$, "    rf, train_rows, oob, oob_skill = train_forest("
    appendFileLine: enginePath$, "        Z, args.lookahead, args.trees, args.max_depth, args.seed, log)"
    appendFileLine: enginePath$, "    if np.isfinite(oob_skill) and oob_skill < 0.0:"
    appendFileLine: enginePath$, "        warnings.append(""forest OOB skill is below persistence: the RF does """
    appendFileLine: enginePath$, "                        ""not beat Y=X on held-out bootstrap rows at k=%d"" % args.lookahead)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    out_samples = int(round(args.target_duration * sr))"
    appendFileLine: enginePath$, "    n_steps = max(1, 1 + int(np.ceil(max(0, out_samples - frame_len) / float(hop_len))))"
    appendFileLine: enginePath$, "    if n_steps * F.shape[0] > 200000000:"
    appendFileLine: enginePath$, "        warnings.append(""large search: %d output steps x %d pool grains may be slow"""
    appendFileLine: enginePath$, "                        % (n_steps, F.shape[0]))"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""  [Py 4/6] Building target trajectory..."")"
    appendFileLine: enginePath$, "    T = make_trajectory(args.trajectory, n_steps, args.seed, log)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""  [Py 5/6] Matching trajectory against the grain pool..."")"
    appendFileLine: enginePath$, "    chosen, dists, nn_scale, repeat_scale, immediate_repeat_pct = walk_pool("
    appendFileLine: enginePath$, "        rf, Z, T, args.traj_weight, args.repeat_penalty, args.seed, log)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    distinct_pct = 100.0 * np.unique(chosen).size / float(chosen.size)"
    appendFileLine: enginePath$, "    log(""    Distinct grains used: %d of %d (%.1f%%)"""
    appendFileLine: enginePath$, "        % (np.unique(chosen).size, chosen.size, distinct_pct))"
    appendFileLine: enginePath$, "    if distinct_pct < 10.0:"
    appendFileLine: enginePath$, "        warnings.append(""only %.0f%% of the selected grains are distinct; """
    appendFileLine: enginePath$, "                        ""raise Repeat penalty to reduce stuttering"" % distinct_pct)"
    appendFileLine: enginePath$, "    if args.repeat_penalty > 0 and immediate_repeat_pct > 25.0:"
    appendFileLine: enginePath$, "        warnings.append(""%.0f%% immediate grain repeats remain; raise Repeat penalty """
    appendFileLine: enginePath$, "                        ""for more variation"" % immediate_repeat_pct)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    log(""  [Py 6/6] Overlap-add resynthesis..."")"
    appendFileLine: enginePath$, "    (out, peak_before, peak_after, input_rms, rms_before_match,"
    appendFileLine: enginePath$, "     rms_after_match, output_rms, rms_gain, rms_limited) = resynthesise("
    appendFileLine: enginePath$, "        audio, chosen, frame_len, hop_len, out_samples,"
    appendFileLine: enginePath$, "        bool(args.match_input_rms), args.safety_peak, log)"
    appendFileLine: enginePath$, "    if rms_limited:"
    appendFileLine: enginePath$, "        warnings.append(""RMS level match hit the +12 dB gain cap; final RMS may remain below source"")"
    appendFileLine: enginePath$, "    sf.write(args.output, out, sr, subtype=""FLOAT"")"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    elapsed = time.time() - t_start"
    appendFileLine: enginePath$, "    if args.stats:"
    appendFileLine: enginePath$, "        write_stats(args.stats, args, sr, n_source_samples, n_channels,"
    appendFileLine: enginePath$, "                    analysis_source, analysis_channel, F.shape[0], chosen, dists, out,"
    appendFileLine: enginePath$, "                    peak_before, peak_after, input_rms, rms_before_match,"
    appendFileLine: enginePath$, "                    rms_after_match, output_rms, rms_gain, rms_limited,"
    appendFileLine: enginePath$, "                    train_rows, oob, oob_skill, nn_scale, repeat_scale,"
    appendFileLine: enginePath$, "                    immediate_repeat_pct, hop_len, frame_len, elapsed, warnings)"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "    for w in warnings:"
    appendFileLine: enginePath$, "        log(""    WARNING: "" + w)"
    appendFileLine: enginePath$, "    log(""    Output: %.2f s, %d ch, RMS %.4f, peak %.4f, %.1f s total"""
    appendFileLine: enginePath$, "        % (out.shape[0] / float(sr), n_channels, output_rms,"
    appendFileLine: enginePath$, "           float(np.max(np.abs(out))), elapsed))"
    appendFileLine: enginePath$, "    log(""OK: wrote "" + args.output)"
    appendFileLine: enginePath$, "    log.close()"
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, ""
    appendFileLine: enginePath$, "if __name__ == ""__main__"":"
    appendFileLine: enginePath$, "    main()"
endproc
