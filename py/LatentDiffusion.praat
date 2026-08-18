# ============================================================
# Praat AudioTools - LatentDiffusion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1.1 (2026) - compatibility/edge-case fixes only
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent Diffusion Resynthesis  -  Morph-Chain Generator
#
#   Encodes audio events into a low-dimensional latent space via
#   an on-the-fly autoencoder, discovers K acoustic identity clusters
#   (k-means++), then runs a temperature-annealed diffusion loop that
#   transforms a maximally-corrupted (noisy) seed vector back toward
#   its cluster identity.  Output is a Morph-Chain: one continuous
#   audio sequence per cluster, evolving from static / noise-like
#   texture into a recognisable instrument identity.
#
#   Anti-loop mechanisms (v1.1):
#     - Stochastic top-K event selection (Boltzmann-weighted)
#     - Tabu penalty (size=5, penalty=4x) for recent events
#     - Latent Jitter floor: T_end never falls below 0.05
#     - No identical-Z padding on early convergence
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# Praat 7.0+ requires explicit full trust before file writes/system calls.
# Guarded so Praat 6.x follows the original path unchanged.
if praatVersion >= 7000
    askForTrust()
endif

# ---- OS-Specific Python Discovery ----
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
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_diffusion.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_diffusion.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_diffusion.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$  = temporaryDirectory$ + "/temp_latdiff_input.wav"
tempCSV$    = temporaryDirectory$ + "/temp_latdiff_events.csv"
tempOutput$ = temporaryDirectory$ + "/temp_latdiff_output.wav"
tempStats$  = temporaryDirectory$ + "/temp_latdiff_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_latdiff_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Latent Diffusion Resynthesis v1.1.1
    optionmenu Preset: 1
        option Custom
        option Gentle crystallisation
        option Stochastic melt
        option Deep freeze
        option Plasma burst
        option Slow diffusion
        option Multi-identity
    integer Latent_size 8
    integer Learning_steps 100
    integer Number_of_clusters 3
    integer Diffusion_steps 30
    real    Entropy_threshold 1.0
    real    Temperature_start 2.0
    real    Temperature_end 0.1
    real    Denoising_strength 0.6
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    latent_size = 8
    learning_steps = 100
    number_of_clusters = 3
    diffusion_steps = 25
    entropy_threshold = 1.2
    temperature_start = 1.0
    temperature_end = 0.06
    denoising_strength = 0.5
    presetName$ = "GentleCrystallisation"
elsif preset = 3
    latent_size = 8
    learning_steps = 100
    number_of_clusters = 3
    diffusion_steps = 40
    entropy_threshold = 0.6
    temperature_start = 3.0
    temperature_end = 0.30
    denoising_strength = 0.3
    presetName$ = "StochasticMelt"
elsif preset = 4
    latent_size = 10
    learning_steps = 150
    number_of_clusters = 3
    diffusion_steps = 50
    entropy_threshold = 0.5
    temperature_start = 2.5
    temperature_end = 0.05
    denoising_strength = 0.8
    presetName$ = "DeepFreeze"
elsif preset = 5
    latent_size = 8
    learning_steps = 80
    number_of_clusters = 4
    diffusion_steps = 15
    entropy_threshold = 2.0
    temperature_start = 4.0
    temperature_end = 0.50
    denoising_strength = 0.9
    presetName$ = "PlasmaBurst"
elsif preset = 6
    latent_size = 12
    learning_steps = 150
    number_of_clusters = 3
    diffusion_steps = 80
    entropy_threshold = 0.8
    temperature_start = 1.5
    temperature_end = 0.08
    denoising_strength = 0.5
    presetName$ = "SlowDiffusion"
elsif preset = 7
    latent_size = 12
    learning_steps = 150
    number_of_clusters = 6
    diffusion_steps = 35
    entropy_threshold = 1.0
    temperature_start = 2.0
    temperature_end = 0.10
    denoising_strength = 0.6
    presetName$ = "MultiIdentity"
else
    presetName$ = "Custom"
endif

# ---- CLAMP ----
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif
if learning_steps < 10
    learning_steps = 10
endif
if learning_steps > 500
    learning_steps = 500
endif
if number_of_clusters < 2
    number_of_clusters = 2
endif
if number_of_clusters > 8
    number_of_clusters = 8
endif
if diffusion_steps < 5
    diffusion_steps = 5
endif
if diffusion_steps > 100
    diffusion_steps = 100
endif
if entropy_threshold < 0
    entropy_threshold = 0
endif
if temperature_start < 0.1
    temperature_start = 0.1
endif
if temperature_start > 10
    temperature_start = 10
endif
if temperature_end < 0.01
    temperature_end = 0.01
endif
if temperature_end > temperature_start
    temperature_end = temperature_start
endif
if denoising_strength < 0
    denoising_strength = 0
endif
if denoising_strength > 1
    denoising_strength = 1
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Latent Diffusion Resynthesis v1.1.1 ==="
appendInfoLine: "Input:   ", soundName$
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: ""
appendInfoLine: "Latent size:         ", latent_size
appendInfoLine: "Learning steps:      ", learning_steps
appendInfoLine: "Clusters:            ", number_of_clusters
appendInfoLine: "Diffusion steps:     ", diffusion_steps
appendInfoLine: "Entropy threshold:   ", entropy_threshold
appendInfoLine: "Temperature:         ", temperature_start, " -> ", temperature_end
appendInfoLine: "Denoising strength:  ", denoising_strength
appendInfoLine: "Seed:                ", seed
appendInfoLine: ""

# ---- ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Event Segmentation  (intensity-peak method)
# ===========================================================================
appendInfoLine: "[2/5] Segmenting events..."

minEventDur = 0.200
maxEventDur = 3.000

selectObject: sound
if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

# WAV sample indices are relative to the start of the file.  Work on a
# zero-based analysis copy so event times remain correct for Sounds whose
# xmin is not zero.  This changes only time coordinates, never samples.
selectObject: analysisMono
Shift times to: "start time", 0

selectObject: analysisMono
pitchObj = To Pitch: 0.01, 75, 600

selectObject: analysisMono
harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0

selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"

selectObject: intObj
intMatrix = Down to Matrix
intSound = To Sound (slice): 1
selectObject: intSound
ppObj = To PointProcess (extrema): 1, "yes", "no", "Sinc70"

selectObject: ppObj
nPeaks = Get number of points

bound_1 = 0
bound_2 = dur
iBound = 3
for iPeak from 1 to nPeaks
    selectObject: ppObj
    peakT = Get time from index: iPeak
    bound_'iBound' = peakT
    iBound = iBound + 1
endfor
nBounds = iBound - 1

for i from 1 to nBounds
    for j from i + 1 to nBounds
        if bound_'j' < bound_'i'
            tmpVal = bound_'i'
            bound_'i' = bound_'j'
            bound_'j' = tmpVal
        endif
    endfor
endfor

nFinal = 0
prevT = -1
for i from 1 to nBounds
    thisT = bound_'i'
    if thisT - prevT >= minEventDur
        nFinal = nFinal + 1
        final_'nFinal' = thisT
        prevT = thisT
    endif
endfor

if nFinal > 0
    lastFinal = final_'nFinal'
    if dur - lastFinal > 0.050
        nFinal = nFinal + 1
        final_'nFinal' = dur
    else
        final_'nFinal' = dur
    endif
else
    nFinal = 2
    final_1 = 0
    final_2 = dur
endif

nEvents = 0
for i from 1 to nFinal - 1
    evStart = final_'i'
    iNext = i + 1
    evEnd = final_'iNext'
    evDur = evEnd - evStart

    if evDur > maxEventDur
        nChunks = ceiling(evDur / maxEventDur)
        chunkDur = evDur / nChunks
        for iChunk from 0 to nChunks - 1
            nEvents = nEvents + 1
            evS_'nEvents' = evStart + iChunk * chunkDur
            if iChunk = nChunks - 1
                evE_'nEvents' = evEnd
            else
                evE_'nEvents' = evStart + (iChunk + 1) * chunkDur
            endif
        endfor
    elsif evDur >= minEventDur
        nEvents = nEvents + 1
        evS_'nEvents' = evStart
        evE_'nEvents' = evEnd
    endif
endfor

if nEvents < 2
    nEvents = 1
    evS_1 = 0
    evE_1 = dur
endif

appendInfoLine: "  Found ", nEvents, " events"

# ===========================================================================
# Stage 3 — Feature Extraction + Export
# ===========================================================================
appendInfoLine: "[3/5] Extracting features..."

Create Table with column names: "eventFeatures", nEvents, "start_time end_time label pitch_stability intensity_mean attack_slope hnr_mean"
eventTable = selected("Table")

for iEv from 1 to nEvents
    t1   = evS_'iEv'
    t2   = evE_'iEv'
    tMid = (t1 + t2) / 2

    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time",   t2
    Set string value:  iEv, "label", "ev" + string$(iEv)

    selectObject: pitchObj
    pMean = Get mean: t1, t2, "Hertz"
    pStd  = Get standard deviation: t1, t2, "Hertz"
    if pMean = undefined or pMean = 0
        pitchStab = 0
    else
        if pStd = undefined
            pStd = 0
        endif
        pitchCV   = pStd / (pMean + 0.001)
        pitchStab = 1 - min(1, pitchCV)
        if pitchStab < 0
            pitchStab = 0
        endif
    endif
    selectObject: eventTable
    Set numeric value: iEv, "pitch_stability", pitchStab

    selectObject: intObj
    iMean = Get mean: t1, t2, "energy"
    if iMean = undefined
        iMean = 0
    endif
    iStart = Get value at time: t1, "Cubic"
    if iStart = undefined
        iStart = 0
    endif
    iPeak = Get maximum: t1, t2, "Parabolic"
    if iPeak = undefined
        iPeak = iStart
    endif
    tPeak = Get time of maximum: t1, t2, "Parabolic"
    if tPeak = undefined
        tPeak = tMid
    endif
    attackTime = tPeak - t1
    if attackTime > 0.001
        attackSlope = (iPeak - iStart) / attackTime
    else
        attackSlope = 0
    endif
    selectObject: eventTable
    Set numeric value: iEv, "intensity_mean", iMean
    Set numeric value: iEv, "attack_slope",   attackSlope

    selectObject: harmObj
    hMean = Get mean: t1, t2
    if hMean = undefined
        hMean = 0
    endif
    selectObject: eventTable
    Set numeric value: iEv, "hnr_mean", hMean
endfor

appendInfoLine: "  Exporting temp files..."
selectObject: sound
Save as WAV file: tempInput$
selectObject: eventTable
Save as comma-separated file: tempCSV$

removeObject: analysisMono, pitchObj, harmObj, intObj
removeObject: intMatrix, intSound, ppObj, eventTable

# ===========================================================================
# Stage 4 — Call Python Engine
# ===========================================================================
appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  (AE training + k-means++ + diffusion chains)"

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(latent_size)
    ... + " " + string$(learning_steps)
    ... + " " + string$(number_of_clusters)
    ... + " " + string$(diffusion_steps)
    ... + " " + fixed$(entropy_threshold, 6)
    ... + " " + fixed$(temperature_start, 6)
    ... + " " + fixed$(temperature_end, 6)
    ... + " " + fixed$(denoising_strength, 6)
    ... + " " + string$(seed)

# Remove any stale output/stats from a PREVIOUS run before calling Python.
# The temp filenames are fixed, so without this a crashed run would leave
# the old files in place and the fileReadable() check below would pass on
# stale data - silently importing a previous result as if it were new.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python diffusion engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Import Result
# ===========================================================================
appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_diffusion"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================
nEvStat$        = "?"
nClustersStat$  = "?"
nChainsStat$    = "?"
diffStepsStat$  = "?"
outDurStat$     = "?"
finalLoss$      = "?"
initialLoss$    = "?"
earlyStops$     = "?"
latentSpread$   = "?"
meanEvDur$      = "?"
warningStat$    = ""

for ki from 0 to 7
    clEvStat_'ki'$ = "?"
    clPctStat_'ki'$ = "?"
    clRadStat_'ki'$ = "?"
endfor

for ki from 0 to 7
    chainNCE_'ki' = 0
endfor

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_clusters="
    nClustersStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_chains="
    nChainsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "diffusion_steps="
    diffStepsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "early_stops="
    earlyStops$ = parseStatLine.result$
    @parseStatLine: statsText$, "latent_spread="
    latentSpread$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    for ki from 0 to 7
        @parseStatLine: statsText$, "cluster_" + string$(ki) + "_events="
        clEvStat_'ki'$ = parseStatLine.result$
        @parseStatLine: statsText$, "cluster_" + string$(ki) + "_pct="
        clPctStat_'ki'$ = parseStatLine.result$
        @parseStatLine: statsText$, "cluster_" + string$(ki) + "_radius="
        clRadStat_'ki'$ = parseStatLine.result$
    endfor

    for ki from 0 to number_of_clusters - 1
        @parseStatLine: statsText$, "chain_" + string$(ki) + "_n_ce="
        nCE$ = parseStatLine.result$
        chainNCE_'ki' = 0
        if nCE$ <> "?"
            chainNCE_'ki' = number(nCE$)
        endif
        if chainNCE_'ki' > 101
            chainNCE_'ki' = 101
        endif

        @parseStatLine: statsText$, "chain_" + string$(ki) + "_ce_vals="
        ceRaw$ = parseStatLine.result$
        if ceRaw$ <> "?" and chainNCE_'ki' > 0
            remaining$ = ceRaw$
            for ceIdx from 0 to chainNCE_'ki' - 1
                comma = index(remaining$, ",")
                if comma > 0
                    val$ = left$(remaining$, comma - 1)
                    remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
                else
                    val$ = remaining$
                endif
                chainCE_'ki'_'ceIdx' = number(val$)
            endfor
        else
            for ceIdx from 0 to chainNCE_'ki' - 1
                chainCE_'ki'_'ceIdx' = 0
            endfor
        endif
    endfor
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Latent Diffusion — Morph-Chain Generator##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Clusters=" + nClustersStat$ + " | T: " + fixed$(temperature_start, 2) + "->" + fixed$(temperature_end, 2)

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1
    Axes: 0, dur, -1, 1
    for iEv from 1 to nEvents
        evBound = evS_'iEv'
        if evBound > 0 and evBound < dur
            Draw line: evBound, -0.9, evBound, 0.9
        endif
    endfor
    Text top: "no", string$(nEvents) + " events | " + fixed$(dur, 2) + " s"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: resultSound
    Colour: "{0.25, 0.35, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Diffused"
    Text bottom: "yes", "Time (s)"

    # === Original Spectrogram ===
    Select outer viewport: 0, 8, 2.5, 3.7
    Select inner viewport: 0.6, 7.7, 2.6, 3.6
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # === Output Spectrogram ===
    Select outer viewport: 0, 8, 3.7, 4.9
    Select inner viewport: 0.6, 7.7, 3.8, 4.8
    selectObject: resultSound
    if nChannels > 1
        Extract one channel: 1
        tmpDiff = selected("Sound")
    else
        Copy: "tmpDiff"
        tmpDiff = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specDiff = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Diffused spectrogram (Morph-Chain)"
    removeObject: specDiff, tmpDiff

    # === Diffusion Panel (Temperature Annealing + Cluster Bars) ===
    Select outer viewport: 0, 8, 5.0, 5.85
    Select inner viewport: 0.6, 7.7, 5.05, 5.80

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.97}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.94, "half", "Diffusion:"
    Select inner viewport: 0.6, 7.7, 5.05, 5.80
    Axes: 0, 1, 0, 1

    barLeft  = 0.02
    barRight = 0.60
    barBot   = 0.52
    barTop   = 0.72
    segW = (barRight - barLeft) / 10
    Paint rectangle: "{0.95, 0.55, 0.10}", barLeft + 0*segW, barLeft + 1*segW, barBot, barTop
    Paint rectangle: "{0.90, 0.50, 0.15}", barLeft + 1*segW, barLeft + 2*segW, barBot, barTop
    Paint rectangle: "{0.80, 0.45, 0.22}", barLeft + 2*segW, barLeft + 3*segW, barBot, barTop
    Paint rectangle: "{0.70, 0.42, 0.33}", barLeft + 3*segW, barLeft + 4*segW, barBot, barTop
    Paint rectangle: "{0.57, 0.40, 0.45}", barLeft + 4*segW, barLeft + 5*segW, barBot, barTop
    Paint rectangle: "{0.45, 0.38, 0.57}", barLeft + 5*segW, barLeft + 6*segW, barBot, barTop
    Paint rectangle: "{0.35, 0.36, 0.65}", barLeft + 6*segW, barLeft + 7*segW, barBot, barTop
    Paint rectangle: "{0.27, 0.33, 0.73}", barLeft + 7*segW, barLeft + 8*segW, barBot, barTop
    Paint rectangle: "{0.20, 0.31, 0.78}", barLeft + 8*segW, barLeft + 9*segW, barBot, barTop
    Paint rectangle: "{0.15, 0.30, 0.80}", barLeft + 9*segW, barRight,          barBot, barTop
    
    Font size: 5
    Colour: "Black"
    Text: barLeft,  "left",  barBot - 0.10, "half", "T=" + fixed$(temperature_start, 2)
    Text: barRight, "right", barBot - 0.10, "half", "T=" + fixed$(temperature_end, 2)
    Text: (barLeft + barRight) / 2, "centre", barBot - 0.10, "half", "Annealing schedule"
    Select inner viewport: 0.6, 7.7, 5.05, 5.80
    Axes: 0, 1, 0, 1
    Draw rectangle: barLeft, barRight, barBot, barTop

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"

    clBarLeft  = 0.64
    clBarRight = 0.97
    clBarBot   = 0.10
    clBarTop   = 0.88
    nCl = number_of_clusters
    clW = (clBarRight - clBarLeft) / nCl

    clCol0$ = "{0.25, 0.45, 0.85}"
    clCol1$ = "{0.85, 0.35, 0.25}"
    clCol2$ = "{0.25, 0.75, 0.45}"
    clCol3$ = "{0.75, 0.25, 0.75}"
    clCol4$ = "{0.85, 0.65, 0.15}"
    clCol5$ = "{0.25, 0.65, 0.85}"
    clCol6$ = "{0.65, 0.15, 0.35}"
    clCol7$ = "{0.45, 0.45, 0.25}"

    for ki from 0 to nCl - 1
        Select inner viewport: 0.6, 7.7, 5.05, 5.80
        Axes: 0, 1, 0, 1
        pctStr$ = clPctStat_'ki'$
        if pctStr$ = "?"
            pctVal = 0
        else
            pctVal = number(pctStr$)
        endif
        barH = clBarBot + (clBarTop - clBarBot) * pctVal / 100.0
        xL   = clBarLeft + ki * clW + clW * 0.12
        xR   = xL + clW * 0.76
        col$ = clCol'ki'$
        Paint rectangle: col$, xL, xR, clBarBot, barH
        Axes: 0, 1, 0, 1
        Font size: 5
        Colour: "Black"
        Text: (xL + xR) / 2, "centre", clBarBot - 0.09, "half", string$(ki)
    endfor
    Colour: "Black"
    Font size: 5
    Text: (clBarLeft + clBarRight) / 2, "centre", clBarTop + 0.07, "half", "Clusters (\% events)"

    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.36, "half", "Steps=" + diffStepsStat$ + " | Chains=" + nChainsStat$ + " | Early-stops=" + earlyStops$ + " | Strength=" + fixed$(denoising_strength, 2)
    Text: 0.02, "left", 0.16, "half", "Latent spread=" + latentSpread$ + " | Events=" + nEvStat$ + " | Mean dur=" + meanEvDur$ + "s"

    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 5.05, 5.80
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1

    # === Morph-Chain Convergence Curves ===
    Select outer viewport: 0, 8, 5.95, 6.85
    Select inner viewport: 0.6, 7.7, 6.05, 6.75

    ceMaxStep = 1
    ceMaxVal  = 1
    ceMinVal  = 0
    hasCEData = 0
    for ki from 0 to number_of_clusters - 1
        nCE = chainNCE_'ki'
        if nCE > 1
            hasCEData = 1
            if nCE - 1 > ceMaxStep
                ceMaxStep = nCE - 1
            endif
            for ceIdx from 0 to nCE - 1
                ceVal = chainCE_'ki'_'ceIdx'
                if ceVal > ceMaxVal
                    ceMaxVal = ceVal
                endif
            endfor
        endif
    endfor
    ceMaxVal = ceMaxVal * 1.1

    if hasCEData
        Axes: 0, ceMaxStep, 0, ceMaxVal
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, ceMaxStep, 0, ceMaxVal

        if entropy_threshold > 0 and entropy_threshold < ceMaxVal
            Colour: "{0.7, 0.7, 0.7}"
            Line width: 1
            Dotted line
            Draw line: 0, entropy_threshold, ceMaxStep, entropy_threshold
            Font size: 4
            Colour: "{0.5, 0.5, 0.5}"
            Text: ceMaxStep * 0.98, "right", entropy_threshold + ceMaxVal * 0.03, "half", "threshold"
            Solid line
        endif

        for ki from 0 to number_of_clusters - 1
            nCE = chainNCE_'ki'
            if nCE > 1
                Colour: clCol'ki'$
                Line width: 2
                for ceIdx from 1 to nCE - 1
                    prevIdx = ceIdx - 1
                    x0 = prevIdx
                    x1 = ceIdx
                    y0 = chainCE_'ki'_'prevIdx'
                    y1 = chainCE_'ki'_'ceIdx'
                    Draw line: x0, y0, x1, y1
                endfor
                Line width: 1
            endif
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "CE"
        Text bottom: "yes", "Diffusion step"
        Text top: "no", "Morph-Chain Convergence (cross-entropy per step)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(convergence data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.95, 8.0
    Select inner viewport: 0.6, 7.7, 7.05, 7.90

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.72, "half", "Preset: " + presetName$ + " | Clusters=" + nClustersStat$ + " | Steps=" + diffStepsStat$ + " | Seed=" + string$(seed)
    Text: 0.02, "left", 0.52, "half", "AE loss: " + initialLoss$ + " -> " + finalLoss$ + " | Latent=" + string$(latent_size) + " | LR steps=" + string$(learning_steps)
    Text: 0.02, "left", 0.32, "half", "Duration: " + fixed$(dur, 2) + "s -> " + outDurStat$ + "s | RMS: " + fixed$(rms_orig, 4) + " -> " + fixed$(rms_out, 4)
    Text: 0.02, "left", 0.12, "half", "T: " + fixed$(temperature_start, 2) + " -> " + fixed$(temperature_end, 2) + " | Denoising=" + fixed$(denoising_strength, 2) + " | Early-stops=" + earlyStops$

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.02, "half", "Warning: " + warningStat$
    endif

    Colour: "Black"
    Select inner viewport: 0.6, 7.7, 7.05, 7.90
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
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
appendInfoLine: "Output: ", soundName$, "_diffusion"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Diffusion:"
appendInfoLine: "  Events:          ", nEvStat$
appendInfoLine: "  Clusters:        ", nClustersStat$
appendInfoLine: "  Morph chains:    ", nChainsStat$, "  (noisy -> refined per cluster)"
appendInfoLine: "  Diffusion steps: ", diffStepsStat$
appendInfoLine: "  Early stops:     ", earlyStops$
appendInfoLine: "  Latent spread:   ", latentSpread$
appendInfoLine: ""

for ki from 0 to number_of_clusters - 1
    appendInfoLine: "  Cluster ", ki, ":  ", clEvStat_'ki'$, " events (", clPctStat_'ki'$, "%)  radius=", clRadStat_'ki'$
endfor

appendInfoLine: ""
appendInfoLine: "Autoencoder:"
appendInfoLine: "  Loss: ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "  Latent size: ", latent_size, "  |  Steps: ", learning_steps
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s  ->  ", outDurStat$, " s"
appendInfoLine: "RMS:      ", fixed$(rms_orig, 4), "  ->  ", fixed$(rms_out, 4)
appendInfoLine: "Mean event duration: ", meanEvDur$, " s"

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