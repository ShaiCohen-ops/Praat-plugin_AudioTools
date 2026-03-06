# ============================================================
# Praat AudioTools - LatentRelocation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Online Latent-Event Relocation
#   (Deep Thermodynamic Recomposition)
#
#   Trains a lightweight autoencoder on-the-fly from the input audio,
#   learns a latent space, then relocates events based on latent
#   thermodynamic fields (temperature, affinity, regimes).
#   No external models, no internet, pure numpy ML.
#
#   Parameters:
#   - Learning steps:  autoencoder training iterations (20–500)
#   - Latent size:     bottleneck dimensionality (2–32)
#   - Relocation intensity: strength of event displacement (0–1)
#   - Stability bias:  anchoring strength for stable events (0–1)
#   - Novelty bias:    structural pivot role for rare events (0–1)
#   - Preserve duration: maintain original length
#   - Seed:            deterministic reproducibility
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
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

# ---- PATHS ----
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_relocation.py"
tempInput$   = pluginDir$ + "temp_latrel_input.wav"
tempCSV$     = pluginDir$ + "temp_latrel_events.csv"
tempOutput$  = pluginDir$ + "temp_latrel_output.wav"
tempStats$   = pluginDir$ + "temp_latrel_stats.txt"

# Verify Python script exists
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM ----
form Online Latent-Event Relocation v1.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Gentle lattice
        option Balanced flow
        option Volatile scatter
        option Deep recomposition
        option Novelty pivots
    comment === Autoencoder ===
    integer Learning_steps 100
    integer Latent_size 8
    comment === Relocation Controls ===
    real Relocation_intensity 0.5
    real Stability_bias 0.3
    real Novelty_bias 0.3
    comment === Output ===
    boolean Preserve_duration 1
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    learning_steps = 80
    latent_size = 6
    relocation_intensity = 0.3
    stability_bias = 0.6
    novelty_bias = 0.1
    presetName$ = "GentleLattice"
elsif preset = 3
    learning_steps = 100
    latent_size = 8
    relocation_intensity = 0.5
    stability_bias = 0.3
    novelty_bias = 0.3
    presetName$ = "BalancedFlow"
elsif preset = 4
    learning_steps = 150
    latent_size = 12
    relocation_intensity = 0.8
    stability_bias = 0.1
    novelty_bias = 0.5
    presetName$ = "VolatileScatter"
elsif preset = 5
    learning_steps = 200
    latent_size = 16
    relocation_intensity = 0.7
    stability_bias = 0.2
    novelty_bias = 0.4
    presetName$ = "DeepRecomp"
elsif preset = 6
    learning_steps = 150
    latent_size = 10
    relocation_intensity = 0.6
    stability_bias = 0.1
    novelty_bias = 0.8
    presetName$ = "NoveltyPivots"
else
    presetName$ = "Custom"
endif

# Clamp
if learning_steps < 10
    learning_steps = 10
endif
if learning_steps > 500
    learning_steps = 500
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Online Latent-Event Relocation v1.0 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Learning steps: ", learning_steps
appendInfoLine: "Latent size:    ", latent_size
appendInfoLine: "Reloc intensity:", fixed$(relocation_intensity, 2)
appendInfoLine: "Stability bias: ", fixed$(stability_bias, 2)
appendInfoLine: "Novelty bias:   ", fixed$(novelty_bias, 2)
appendInfoLine: "Preserve dur:   ", preserve_duration
appendInfoLine: "Seed:           ", seed
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Event Segmentation (Praat-side)
# ===========================================================================
# Segment audio into musically coherent events using intensity peaks,
# pitch continuity, and HNR changes. Target: 200 ms – 3 s per event.

appendInfoLine: "[1/6] Segmenting events..."

minEventDur = 0.200
maxEventDur = 3.000

# ---- Create analysis objects ----
selectObject: sound

if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

selectObject: analysisMono
pitchObj = To Pitch: 0.01, 75, 600

selectObject: analysisMono
harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0

selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"

# ---- Find intensity peaks as candidate boundaries ----
selectObject: intObj
intMatrix = Down to Matrix
intSound = To Sound (slice): 1
selectObject: intSound
ppObj = To PointProcess (extrema): 1, "yes", "no", "Sinc70"

selectObject: ppObj
nPeaks = Get number of points

# Collect peak times + add start and end
nBounds = nPeaks + 2
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

# Sort boundaries (simple insertion sort for Praat)
for i from 1 to nBounds
    for j from i + 1 to nBounds
        if bound_'j' < bound_'i'
            tmpVal = bound_'i'
            bound_'i' = bound_'j'
            bound_'j' = tmpVal
        endif
    endfor
endfor

# Remove duplicates and enforce minimum duration
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

# Ensure end is included
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

# Enforce max duration: split long segments
nEvents = 0
for i from 1 to nFinal - 1
    evStart = final_'i'
    iNext = i + 1
    evEnd = final_'iNext'
    evDur = evEnd - evStart

    if evDur > maxEventDur
        # Split into chunks
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
# Stage 2 — Extract Per-Event Features
# ===========================================================================

appendInfoLine: "[2/6] Extracting per-event features..."

# Create feature table
Create Table with column names: "eventFeatures", nEvents,
    ... "start_time end_time pitch_median pitch_stability intensity_mean attack_slope hnr_mean"
eventTable = selected("Table")

for iEv from 1 to nEvents
    t1 = evS_'iEv'
    t2 = evE_'iEv'
    tMid = (t1 + t2) / 2

    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time", t2

    # Pitch median + stability (CV of voiced pitch values)
    selectObject: pitchObj
    pMed = Get quantile: t1, t2, 0.5, "Hertz"
    pMean = Get mean: t1, t2, "Hertz"
    pStd = Get standard deviation: t1, t2, "Hertz"

    if pMed = undefined
        pMed = 0
    endif
    if pMean = undefined or pMean = 0
        pitchStab = 0
    else
        if pStd = undefined
            pStd = 0
        endif
        # Stability = 1 - CV (coefficient of variation), clamped
        pitchCV = pStd / (pMean + 0.001)
        pitchStab = 1 - min(1, pitchCV)
        if pitchStab < 0
            pitchStab = 0
        endif
    endif

    selectObject: eventTable
    Set numeric value: iEv, "pitch_median", pMed
    Set numeric value: iEv, "pitch_stability", pitchStab

    # Intensity mean + attack slope
    selectObject: intObj
    iMean = Get mean: t1, t2, "energy"
    if iMean = undefined
        iMean = 0
    endif

    # Attack slope: (peak intensity - start intensity) / time to peak
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
    Set numeric value: iEv, "attack_slope", attackSlope

    # HNR mean
    selectObject: harmObj
    hMean = Get mean: t1, t2
    if hMean = undefined
        hMean = 0
    endif

    selectObject: eventTable
    Set numeric value: iEv, "hnr_mean", hMean
endfor

# ---- Export WAV + CSV ----
appendInfoLine: "[3/6] Exporting temp files..."

selectObject: sound
Save as WAV file: tempInput$

selectObject: eventTable
Save as comma-separated file: tempCSV$

# ---- Cleanup analysis objects ----
removeObject: analysisMono, pitchObj, harmObj, intObj
removeObject: intMatrix, intSound, ppObj, eventTable

# ===========================================================================
# Stage 3–6 — Call Python
# ===========================================================================

appendInfoLine: "[4/6] Running Python engine..."
appendInfoLine: "  (Training autoencoder + relocating events)"

# ---- Robust Python detection ----
probeMarker$ = pluginDir$ + "temp_pyprobe.ok"

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

    probeCode$ = "import numpy,soundfile,scipy; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif

    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    deleteFile: tempInput$
    deleteFile: tempCSV$
    exitScript: "Cannot find a Python installation with the required packages." + newline$
        ... + "" + newline$
        ... + "Tried: python, py, py -3, python3" + newline$
        ... + "" + newline$
        ... + "Please install the packages and ensure Python is in PATH:" + newline$
        ... + "  pip install numpy soundfile scipy" + newline$
        ... + "" + newline$
        ... + "Note: scikit-learn is NOT required for this script."
endif

runSystem: pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(learning_steps)
    ... + " " + string$(latent_size)
    ... + " " + fixed$(relocation_intensity, 4)
    ... + " " + fixed$(stability_bias, 4)
    ... + " " + fixed$(novelty_bias, 4)
    ... + " " + string$(preserve_duration)
    ... + " " + string$(seed)

# ---- Verify output ----
if not fileReadable(tempOutput$)
    deleteFile: tempInput$
    deleteFile: tempCSV$
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    exitScript: "Python latent relocation engine failed." + newline$
        ... + "" + newline$
        ... + "Python command used: " + pythonCmd$ + newline$
        ... + "" + newline$
        ... + "Possible causes:" + newline$
        ... + "  - Incompatible package version" + newline$
        ... + "  - Input audio too short or empty" + newline$
        ... + "  - Too few events detected" + newline$
        ... + "" + newline$
        ... + "Run in terminal to see error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """"
endif

# ===========================================================================
# Import Result
# ===========================================================================

appendInfoLine: "[5/6] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_latent"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================

nEvStat$ = "?"
nMovedStat$ = "?"
avgDispStat$ = "?"
maxDispStat$ = "?"
crystalPct$ = "?"
fluidPct$ = "?"
gasPct$ = "?"
plasmaPct$ = "?"
finalLoss$ = "?"
initialLoss$ = "?"
meanTempStat$ = "?"
meanEvDur$ = "?"
warningStat$ = ""

# Displacement map data
nDispPts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_moved="
    nMovedStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "avg_displacement_ms="
    avgDispStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "max_displacement_ms="
    maxDispStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "crystal_pct="
    crystalPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "fluid_pct="
    fluidPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "gas_pct="
    gasPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "plasma_pct="
    plasmaPct$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_temperature="
    meanTempStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    # ── Parse displacement map data ──
    @parseStatLine: statsText$, "n_disp_pts="
    nDP$ = parseStatLine.result$
    if nDP$ <> "?"
        nDispPts = number(nDP$)
    endif
    if nDispPts > 100
        nDispPts = 100
    endif
    for iDP from 0 to nDispPts - 1
        @parseStatLine: statsText$, "dp_" + string$(iDP) + "="
        dpRaw$ = parseStatLine.result$
        dp_'iDP'_ox = 0
        dp_'iDP'_oy = 0
        dp_'iDP'_rx = 0
        dp_'iDP'_ry = 0
        dp_'iDP'_reg = 0
        if dpRaw$ <> "?"
            # Parse: ox,oy,rx,ry,regime
            remaining$ = dpRaw$
            # ox
            comma = index(remaining$, ",")
            if comma > 0
                dp_'iDP'_ox = number(left$(remaining$, comma - 1))
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
            endif
            # oy
            comma = index(remaining$, ",")
            if comma > 0
                dp_'iDP'_oy = number(left$(remaining$, comma - 1))
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
            endif
            # rx
            comma = index(remaining$, ",")
            if comma > 0
                dp_'iDP'_rx = number(left$(remaining$, comma - 1))
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
            endif
            # ry
            comma = index(remaining$, ",")
            if comma > 0
                dp_'iDP'_ry = number(left$(remaining$, comma - 1))
                remaining$ = mid$(remaining$, comma + 1, length(remaining$) - comma)
                dp_'iDP'_reg = number(remaining$)
            endif
        endif
    endfor
endif

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "[6/6] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Latent-Event Relocation##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Latent=" + string$(latent_size) + " | Seed=" + string$(seed)

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

    # Draw event boundaries on input waveform
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
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Relocated"
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
        tmpOut = selected("Sound")
    else
        Copy: "tmpOut"
        tmpOut = selected("Sound")
    endif

    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Relocated spectrogram"
    removeObject: specOut, tmpOut

    # === Regime Distribution Bar ===
    Select outer viewport: 0, 8, 5.0, 5.6
    Select inner viewport: 0.6, 7.7, 5.1, 5.5

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    # Draw stacked bar of regime percentages
    crystalW = 0
    fluidW = 0
    gasW = 0
    plasmaW = 0
    if crystalPct$ <> "?"
        crystalW = number(crystalPct$) / 100
    endif
    if fluidPct$ <> "?"
        fluidW = number(fluidPct$) / 100
    endif
    if gasPct$ <> "?"
        gasW = number(gasPct$) / 100
    endif
    if plasmaPct$ <> "?"
        plasmaW = number(plasmaPct$) / 100
    endif

    x0 = 0.05
    barH_top = 0.75
    barH_bot = 0.25

    # Crystal (blue)
    if crystalW > 0.001
        Paint rectangle: "{0.3, 0.5, 0.9}", x0, x0 + crystalW * 0.9, barH_bot, barH_top
        x0 = x0 + crystalW * 0.9
    endif
    # Fluid (green)
    if fluidW > 0.001
        Paint rectangle: "{0.3, 0.7, 0.4}", x0, x0 + fluidW * 0.9, barH_bot, barH_top
        x0 = x0 + fluidW * 0.9
    endif
    # Gas (orange)
    if gasW > 0.001
        Paint rectangle: "{0.9, 0.6, 0.2}", x0, x0 + gasW * 0.9, barH_bot, barH_top
        x0 = x0 + gasW * 0.9
    endif
    # Plasma (red)
    if plasmaW > 0.001
        Paint rectangle: "{0.85, 0.25, 0.25}", x0, x0 + plasmaW * 0.9, barH_bot, barH_top
    endif

    Font size: 6
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Regimes: Blue=Crystal | Green=Fluid | Orange=Gas | Red=Plasma"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === Latent Displacement Map ===
    Select outer viewport: 0, 8, 5.7, 7.0
    Select inner viewport: 0.6, 7.7, 5.8, 6.9

    if nDispPts > 0
        # Compute axis bounds from all displacement points
        axMinX = 0
        axMaxX = 1
        axMinY = 0
        axMaxY = 1
        gotBounds = 0
        for iDP from 0 to nDispPts - 1
            for iCoord from 1 to 2
                if iCoord = 1
                    bx = dp_'iDP'_ox
                    by = dp_'iDP'_oy
                else
                    bx = dp_'iDP'_rx
                    by = dp_'iDP'_ry
                endif
                if gotBounds = 0
                    axMinX = bx
                    axMaxX = bx
                    axMinY = by
                    axMaxY = by
                    gotBounds = 1
                else
                    if bx < axMinX
                        axMinX = bx
                    endif
                    if bx > axMaxX
                        axMaxX = bx
                    endif
                    if by < axMinY
                        axMinY = by
                    endif
                    if by > axMaxY
                        axMaxY = by
                    endif
                endif
            endfor
        endfor

        rangeX = axMaxX - axMinX
        rangeY = axMaxY - axMinY
        if rangeX < 0.01
            rangeX = 1
        endif
        if rangeY < 0.01
            rangeY = 1
        endif
        axMinX = axMinX - rangeX * 0.12
        axMaxX = axMaxX + rangeX * 0.12
        axMinY = axMinY - rangeY * 0.12
        axMaxY = axMaxY + rangeY * 0.12

        Axes: axMinX, axMaxX, axMinY, axMaxY
        Paint rectangle: "{0.97, 0.97, 0.99}", axMinX, axMaxX, axMinY, axMaxY

        # Draw displacement arrows (grey) then regime-colored dots
        Line width: 1
        Colour: "{0.75, 0.75, 0.75}"
        for iDP from 0 to nDispPts - 1
            Draw arrow: dp_'iDP'_ox, dp_'iDP'_oy, dp_'iDP'_rx, dp_'iDP'_ry
        endfor

        # Draw original positions as regime-colored circles
        for iDP from 0 to nDispPts - 1
            reg = dp_'iDP'_reg
            if reg = 0
                Paint circle (mm): "{0.3, 0.5, 0.9}", dp_'iDP'_ox, dp_'iDP'_oy, 1.4
            elsif reg = 1
                Paint circle (mm): "{0.3, 0.7, 0.4}", dp_'iDP'_ox, dp_'iDP'_oy, 1.4
            elsif reg = 2
                Paint circle (mm): "{0.9, 0.6, 0.2}", dp_'iDP'_ox, dp_'iDP'_oy, 1.4
            else
                Paint circle (mm): "{0.85, 0.25, 0.25}", dp_'iDP'_ox, dp_'iDP'_oy, 1.4
            endif
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "PC2"
        Text bottom: "yes", "PC1"
        Text top: "no", "Latent Displacement Map (arrows: original -> relocated | colour: regime)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(displacement data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 7.1, 8.0
    Select inner viewport: 0.6, 7.7, 7.15, 7.95

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.70, "half", "Events=" + nEvStat$ + " Moved=" + nMovedStat$ + " AvgDisp=" + avgDispStat$ + "ms MaxDisp=" + maxDispStat$ + "ms | AE: " + initialLoss$ + "->" + finalLoss$
    Text: 0.02, "left", 0.46, "half", "Regimes: C=" + crystalPct$ + "% F=" + fluidPct$ + "% G=" + gasPct$ + "% P=" + plasmaPct$ + "% | T=" + meanTempStat$ + " | RMS: " + fixed$(rms_orig, 4) + "->" + fixed$(rms_out, 4)
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.22, "half", "Steps=" + string$(learning_steps) + " Lat=" + string$(latent_size) + " Int=" + fixed$(relocation_intensity, 2) + " Stab=" + fixed$(stability_bias, 2) + " Nov=" + fixed$(novelty_bias, 2) + " Seed=" + string$(seed)

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.60, "left", 0.22, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
else
    appendInfoLine: "[6/6] Visualization skipped."
endif

# ===========================================================================
# Cleanup — always delete temp files
# ===========================================================================

deleteFile: tempInput$
deleteFile: tempCSV$
deleteFile: tempOutput$
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif
if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

# ===========================================================================
# Summary
# ===========================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_latent"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Relocation report:"
appendInfoLine: "  Events: ", nEvStat$, " (mean dur: ", meanEvDur$, " s)"
appendInfoLine: "  Moved: ", nMovedStat$, " | Avg displacement: ", avgDispStat$, " ms"
appendInfoLine: "  Max displacement: ", maxDispStat$, " ms"
appendInfoLine: ""
appendInfoLine: "Latent regimes:"
appendInfoLine: "  Crystal: ", crystalPct$, "% | Fluid: ", fluidPct$, "% | Gas: ", gasPct$, "% | Plasma: ", plasmaPct$, "%"
appendInfoLine: "  Mean temperature: ", meanTempStat$
appendInfoLine: ""
appendInfoLine: "Autoencoder:"
appendInfoLine: "  Loss: ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "  Steps: ", learning_steps, " | Latent: ", latent_size
appendInfoLine: ""
appendInfoLine: "RMS original:    ", fixed$(rms_orig, 6)
appendInfoLine: "RMS relocated:   ", fixed$(rms_out, 6)
appendInfoLine: "RMS ratio:       ", fixed$(rms_out / rms_orig, 3), "x"

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
