# ============================================================
# Praat AudioTools - LatentSTFTDecoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Unified Cross-Platform Version
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent STFT Decoder
#
#   Trains a convolutional Beta-VAE on log-magnitude STFT patches
#   extracted from event-segmented audio, then navigates the latent
#   space to synthesise new audio via decoded STFT patches.
#
#   Waveform reconstruction modes:
#     borrow     — phase borrowed from nearest real event (default)
#     griffinlim — iterative Griffin-Lim phase reconstruction
#
#   Latent navigation modes:
#     interpolate  — smooth cyclic interpolation through event latents
#     random_walk  — random walk around the latent mean
#     drift        — directed coherent drift with momentum
#
# Dependencies (Python):
#     pip install numpy scipy soundfile
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

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_stft_decoder.py"
tempInput$    = pluginDir$ + "temp_stftdec_input.wav"
tempCSV$      = pluginDir$ + "temp_stftdec_events.csv"
tempOutput$   = pluginDir$ + "temp_stftdec_output.wav"
tempStats$    = pluginDir$ + "temp_stftdec_stats.txt"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$
        ... + "Please verify AudioTools installation."
endif

# ---- FORM  (window 1 - core + VAE + STFT) ----
form Latent STFT Decoder v1.1
    optionmenu Preset: 1
        option Custom
        option Quick (small, fast)
        option Standard
        option High quality
    integer Latent_size 8
    real Duration_(0_=_original) 0
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
    comment __ VAE Training ________________________________________________
    real Beta_(KL_weight) 0.5
    integer Epochs 30
    integer Batch_size 8
    comment __ STFT Settings ________________________________________________
    integer N_fft 512
    integer Hop_length 128
    integer Patch_frames 32
endform

# ---- ADVANCED PARAMETERS  (window 2 - VAE grid + nav + output) ----
beginPause: "Advanced Parameters - Latent STFT Decoder"
    comment: "---- Preset override (overrides window 1 if changed) ----"
    choice: "Preset2", 1
        option: "keep window 1 preset"
        option: "Quick (small, fast)"
        option: "Standard"
        option: "High quality"
    comment: "---- VAE Grid  (smaller = faster; 32x16 is default) ----"
    integer: "Vae_freq", 32
    integer: "Vae_frames", 16
    comment: "---- Latent Navigation ----"
    choice: "Nav_mode", 1
        option: "interpolate"
        option: "random_walk"
        option: "drift"
    integer: "Nav_steps", 30
    integer: "K_neighbors", 4
    real: "Step_size", 0.30
    real: "Temperature", 0.25
    real: "P_jump", 0.05
    real: "Visit_weight", 2.0
    real: "Visit_decay", 0.92
    comment: "---- Output Settings ----"
    choice: "Normalize_mode", 3
        option: "none"
        option: "peak"
        option: "rms"
    choice: "Phase_mode", 1
        option: "borrow"
        option: "griffinlim"
clicked = endPause: "Cancel", "OK", 2
if clicked = 1
    exitScript
endif

# If window 2 preset was changed, it overrides window 1
# preset2: 1=keep  2=Quick  3=Standard  4=HighQuality
if preset2 > 1
    preset = preset2
endif

# ---- PRESET APPLICATION ----
if preset = 2
    # Quick: tiny VAE grid, few epochs, small STFT — fastest option
    latent_size  = 6
    epochs       = 15
    n_fft        = 256
    hop_length   = 64
    patch_frames = 16
    vae_freq     = 16
    vae_frames   = 8
    nav_steps    = 20
    presetName$  = "Quick"
elsif preset = 3
    # Standard: balanced speed/quality
    latent_size  = 8
    epochs       = 30
    n_fft        = 512
    hop_length   = 128
    patch_frames = 32
    vae_freq     = 32
    vae_frames   = 16
    nav_steps    = 30
    presetName$  = "Standard"
elsif preset = 4
    # High quality: larger VAE grid, more epochs
    latent_size  = 16
    epochs       = 60
    n_fft        = 1024
    hop_length   = 256
    patch_frames = 64
    vae_freq     = 48
    vae_frames   = 24
    nav_steps    = 50
    presetName$  = "HighQuality"
else
    presetName$  = "Custom"
endif

# ---- CLAMP VALUES ----
if latent_size < 2
    latent_size = 2
endif
if latent_size > 64
    latent_size = 64
endif
if epochs < 5
    epochs = 5
endif
if epochs > 500
    epochs = 500
endif
if batch_size < 1
    batch_size = 1
endif
if batch_size > 64
    batch_size = 64
endif
if n_fft < 64
    n_fft = 64
endif
if hop_length < 1
    hop_length = 1
endif
if hop_length > n_fft
    hop_length = n_fft / 2
endif
if patch_frames < 4
    patch_frames = 4
endif
if patch_frames > 256
    patch_frames = 256
endif
if nav_steps < 4
    nav_steps = 4
endif
if nav_steps > 1000
    nav_steps = 1000
endif
if k_neighbors < 1
    k_neighbors = 1
endif
if k_neighbors > 10
    k_neighbors = 10
endif
if p_jump < 0
    p_jump = 0
endif
if p_jump > 1
    p_jump = 1
endif
if visit_weight < 0
    visit_weight = 0
endif
if visit_decay < 0
    visit_decay = 0
endif
if visit_decay > 1
    visit_decay = 1
endif
if vae_freq < 4
    vae_freq = 4
endif
if vae_freq > 128
    vae_freq = 128
endif
if vae_frames < 4
    vae_frames = 4
endif
if vae_frames > 128
    vae_frames = 128
endif
if step_size < 0
    step_size = 0
endif
if step_size > 5
    step_size = 5
endif
if temperature < 0
    temperature = 0
endif
if temperature > 5
    temperature = 5
endif
if beta < 0
    beta = 0
endif

# ---- MAP OPTION MENUS TO STRINGS ----

# nav_mode: 1=interpolate 2=random_walk 3=drift
if nav_mode = 1
    navModeStr$ = "interpolate"
elsif nav_mode = 2
    navModeStr$ = "random_walk"
else
    navModeStr$ = "drift"
endif

# normalize_mode: 1=none 2=peak 3=rms
if normalize_mode = 1
    normModeStr$ = "none"
elsif normalize_mode = 2
    normModeStr$ = "peak"
else
    normModeStr$ = "rms"
endif

# phase_mode: 1=borrow 2=griffinlim
if phase_mode = 1
    phaseModeStr$ = "borrow"
else
    phaseModeStr$ = "griffinlim"
endif

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels

if duration <= 0
    duration = dur
endif

# ---- INFO HEADER ----
clearinfo
writeInfoLine:  "=== Latent STFT Decoder v1.1 ==="
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Preset:      ", presetName$
appendInfoLine: ""
appendInfoLine: "Latent size: ", latent_size
appendInfoLine: "Beta (KL):   ", fixed$(beta, 3)
appendInfoLine: "Epochs:      ", epochs
appendInfoLine: "Duration:    ", if duration > 0 then fixed$(duration, 1) else "original" fi
appendInfoLine: "Seed:        ", seed
appendInfoLine: ""
appendInfoLine: "STFT: n_fft=", n_fft, "  hop=", hop_length, "  patch_frames=", patch_frames
appendInfoLine: "Nav:  mode=",  navModeStr$, "  steps=", nav_steps,
    ... "  step_size=", fixed$(step_size, 3), "  temp=", fixed$(temperature, 3)
appendInfoLine: "Phase: ", phaseModeStr$, "  Normalize: ", normModeStr$
appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Ch: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Event Segmentation
# (Intensity-peak based, identical approach to LatentBarycentric)
# ===========================================================================

appendInfoLine: "[1/5] Segmenting events..."

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

selectObject: analysisMono
pitchObj = To Pitch: 0.01, 75, 600

selectObject: analysisMono
harmObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0

selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"

selectObject: intObj
intMatrix = Down to Matrix
intSound  = To Sound (slice): 1
selectObject: intSound
ppObj = To PointProcess (extrema): 1, "yes", "no", "Sinc70"

selectObject: ppObj
nPeaks = Get number of points

bound_1 = 0
bound_2 = dur
iBound  = 3
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
            tmpVal    = bound_'i'
            bound_'i' = bound_'j'
            bound_'j' = tmpVal
        endif
    endfor
endfor

nFinal = 0
prevT  = -1
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
    iNext   = i + 1
    evEnd   = final_'iNext'
    evDur   = evEnd - evStart

    if evDur > maxEventDur
        nChunks  = ceiling(evDur / maxEventDur)
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
# Stage 2 — Extract Features + Export
# ===========================================================================

appendInfoLine: "[2/5] Extracting features + exporting temp files..."

Create Table with column names: "eventFeatures", nEvents,
    ... "start_time end_time label pitch_stability intensity_mean hnr_mean"
eventTable = selected("Table")

for iEv from 1 to nEvents
    t1 = evS_'iEv'
    t2 = evE_'iEv'

    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time",   t2
    Set string value:  iEv, "label",      "ev" + string$(iEv)

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
    selectObject: eventTable
    Set numeric value: iEv, "intensity_mean", iMean

    selectObject: harmObj
    hMean = Get mean: t1, t2
    if hMean = undefined
        hMean = 0
    endif
    selectObject: eventTable
    Set numeric value: iEv, "hnr_mean", hMean
endfor

selectObject: sound
Save as WAV file: tempInput$

selectObject: eventTable
Save as comma-separated file: tempCSV$

removeObject: analysisMono, pitchObj, harmObj, intObj
removeObject: intMatrix, intSound, ppObj, eventTable

# ===========================================================================
# Stage 3 — Python Detection
# ===========================================================================

appendInfoLine: "[3/5] Detecting Python..."

probeMarker$ = pluginDir$ + "temp_stftdec_pyprobe.ok"

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

    probeCode$ = "import numpy,scipy,soundfile; open(r'" + probeMarker$ + "','w').write('ok')"
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
    exitScript: "Cannot find Python with required packages." + newline$
        ... + "  pip install numpy scipy soundfile"
endif

# ===========================================================================
# Stage 4 — Call Python
# ===========================================================================

appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  VAE: latent=", latent_size, "  epochs=", epochs,
    ... "  beta=", fixed$(beta, 3)
appendInfoLine: "  STFT: n_fft=", n_fft, "  hop=", hop_length,
    ... "  frames=", patch_frames
appendInfoLine: "  Nav: ", navModeStr$, "  steps=", nav_steps

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$  + """"
    ... + " """ + tempCSV$    + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$  + """"
    ... + " --latent_size "   + string$(latent_size)
    ... + " --beta "          + fixed$(beta, 4)
    ... + " --epochs "        + string$(epochs)
    ... + " --n_fft "         + string$(n_fft)
    ... + " --hop_length "    + string$(hop_length)
    ... + " --patch_frames "  + string$(patch_frames)
    ... + " --duration "      + fixed$(duration, 4)
    ... + " --phase_mode "    + phaseModeStr$
    ... + " --normalize_mode " + normModeStr$
    ... + " --seed "          + string$(seed)
    ... + " --nav_mode "      + navModeStr$
    ... + " --nav_steps "     + string$(nav_steps)
    ... + " --k_neighbors "   + string$(k_neighbors)
    ... + " --p_jump "        + fixed$(p_jump, 4)
    ... + " --visit_weight "  + fixed$(visit_weight, 4)
    ... + " --visit_decay "   + fixed$(visit_decay, 4)
    ... + " --step_size "     + fixed$(step_size, 4)
    ... + " --temperature "   + fixed$(temperature, 4)
    ... + " --vae_freq "      + string$(vae_freq)
    ... + " --vae_frames "    + string$(vae_frames)
    ... + " --cleanup"

runSystem: pythonCall$

if not fileReadable(tempOutput$)
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    exitScript: "Python STFT decoder engine failed." + newline$
        ... + "Run in terminal to see error:" + newline$
        ... + "  " + pythonCmd$ + " """ + pythonScript$ + """"
endif

# ===========================================================================
# Stage 5 — Import Result
# ===========================================================================

appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_stftdec"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

# ---- Read Stats ----
nEvStat$        = "?"
nStepsStat$     = "?"
navModeStat$    = "?"
phaseModeStat$  = "?"
latentStat$     = "?"
betaStat$       = "?"
epochsStat$     = "?"
nFftStat$       = "?"
hopStat$        = "?"
patchFStat$     = "?"
freqBinsStat$   = "?"
outDurStat$     = "?"
normModeStat$   = "?"
rmsInputStat$   = "?"
rmsOutputStat$  = "?"
finalLoss$      = "?"
initialLoss$    = "?"
warningStat$    = ""

# Trajectory data
nSEvPts = 0
nSTrajPts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "n_steps="
    nStepsStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "nav_mode="
    navModeStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "phase_mode="
    phaseModeStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "latent_size="
    latentStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "beta="
    betaStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "epochs="
    epochsStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "n_fft="
    nFftStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "hop_length="
    hopStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "patch_frames="
    patchFStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "freq_bins="
    freqBinsStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "rms_input="
    rmsInputStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "rms_output="
    rmsOutputStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$

    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$

    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$

    # ── Parse trajectory data ──
    @parseStatLine: statsText$, "n_ev_pts="
    nSEP$ = parseStatLine.result$
    if nSEP$ <> "?"
        nSEvPts = number(nSEP$)
    endif
    if nSEvPts > 200
        nSEvPts = 200
    endif
    for iEP from 0 to nSEvPts - 1
        @parseStatLine: statsText$, "sev_" + string$(iEP) + "="
        epRaw$ = parseStatLine.result$
        sep_'iEP'_x = 0
        sep_'iEP'_y = 0
        if epRaw$ <> "?"
            comma = index(epRaw$, ",")
            if comma > 0
                sep_'iEP'_x = number(left$(epRaw$, comma - 1))
                sep_'iEP'_y = number(mid$(epRaw$, comma + 1, length(epRaw$) - comma))
            endif
        endif
    endfor

    @parseStatLine: statsText$, "n_traj_pts="
    nSTP$ = parseStatLine.result$
    if nSTP$ <> "?"
        nSTrajPts = number(nSTP$)
    endif
    if nSTrajPts > 200
        nSTrajPts = 200
    endif
    for iTP from 0 to nSTrajPts - 1
        @parseStatLine: statsText$, "str_" + string$(iTP) + "="
        tpRaw$ = parseStatLine.result$
        stp_'iTP'_x = 0
        stp_'iTP'_y = 0
        if tpRaw$ <> "?"
            comma = index(tpRaw$, ",")
            if comma > 0
                stp_'iTP'_x = number(left$(tpRaw$, comma - 1))
                stp_'iTP'_y = number(mid$(tpRaw$, comma + 1, length(tpRaw$) - comma))
            endif
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
    Text: 0.5, "centre", 0.6, "half", "##Latent STFT Decoder##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    subtitleStr$ = soundName$ + " | " + presetName$
        ... + " | " + navModeStr$ + " | latent=" + string$(latent_size)
        ... + " | n_fft=" + string$(n_fft)
    Text: 0.5, "centre", -1.2, "half", subtitleStr$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
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
    Select outer viewport: 0, 8, 1.45, 2.35
    Select inner viewport: 0.6, 7.7, 1.50, 2.30
    selectObject: resultSound
    Colour: "{0.2, 0.55, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "STFT dec"
    Text bottom: "yes", "Time (s)"

    # === Input Spectrogram ===
    Select outer viewport: 0, 8, 2.45, 3.65
    Select inner viewport: 0.6, 7.7, 2.50, 3.60
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
    Select outer viewport: 0, 8, 3.65, 4.85
    Select inner viewport: 0.6, 7.7, 3.70, 4.80
    selectObject: resultSound
    Extract one channel: 1
    tmpOut = selected("Sound")
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "STFT-decoded output spectrogram (L channel)"
    removeObject: specOut, tmpOut

    # === Latent Navigation Trajectory ===
    Select outer viewport: 0, 8, 4.95, 6.35
    Select inner viewport: 0.6, 7.7, 5.00, 6.30

    if nSTrajPts > 1 or nSEvPts > 0
        # Compute axis bounds
        axMinX = 0
        axMaxX = 1
        axMinY = 0
        axMaxY = 1
        gotBounds = 0
        for iB from 0 to nSEvPts - 1
            bx = sep_'iB'_x
            by = sep_'iB'_y
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
        for iB from 0 to nSTrajPts - 1
            bx = stp_'iB'_x
            by = stp_'iB'_y
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

        rangeX = axMaxX - axMinX
        rangeY = axMaxY - axMinY
        if rangeX < 0.01
            rangeX = 1
        endif
        if rangeY < 0.01
            rangeY = 1
        endif
        axMinX = axMinX - rangeX * 0.1
        axMaxX = axMaxX + rangeX * 0.1
        axMinY = axMinY - rangeY * 0.1
        axMaxY = axMaxY + rangeY * 0.1

        Axes: axMinX, axMaxX, axMinY, axMaxY
        Paint rectangle: "{0.97, 0.97, 0.99}", axMinX, axMaxX, axMinY, axMaxY

        # Event positions as grey circles
        for iEP from 0 to nSEvPts - 1
            Paint circle (mm): "{0.75, 0.75, 0.75}", sep_'iEP'_x, sep_'iEP'_y, 1.2
        endfor

        # Trajectory path
        Colour: "{0.2, 0.55, 0.75}"
        Line width: 2
        for iTP from 1 to nSTrajPts - 1
            iPrev = iTP - 1
            Draw line: stp_'iPrev'_x, stp_'iPrev'_y, stp_'iTP'_x, stp_'iTP'_y
        endfor
        Line width: 1

        # Start/end markers
        if nSTrajPts > 0
            Paint circle (mm): "{0.2, 0.7, 0.3}", stp_0_x, stp_0_y, 2.0
            iLast = nSTrajPts - 1
            Paint circle (mm): "{0.8, 0.2, 0.2}", stp_'iLast'_x, stp_'iLast'_y, 2.0
        endif

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "PC2"
        Text bottom: "yes", "PC1"
        Text top: "no", "Latent trajectory (" + navModeStat$ + " " + nStepsStat$ + " steps) — ##S##=start ##E##=end"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(trajectory data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.45, 8.0
    Select inner viewport: 0.6, 7.7, 6.50, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.76, "half",
        ... navModeStat$ + " " + nStepsStat$ + " steps | "
        ... + phaseModeStat$ + " | Events=" + nEvStat$
        ... + " | Dur: " + fixed$(dur, 2) + "s->" + outDurStat$ + "s"
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.02, "left", 0.58, "half",
        ... "STFT: fft=" + nFftStat$ + " hop=" + hopStat$
        ... + " frames=" + patchFStat$ + " bins=" + freqBinsStat$
        ... + " | Norm=" + normModeStat$
        ... + " | RMS: " + rmsInputStat$ + "->" + rmsOutputStat$
    Colour: "{0.6, 0.3, 0.7}"
    Text: 0.02, "left", 0.40, "half",
        ... "VAE: lat=" + latentStat$ + " beta=" + betaStat$
        ... + " ep=" + epochsStat$
        ... + " | Loss: " + initialLoss$ + "->" + finalLoss$
        ... + " | Seed=" + string$(seed)

    if warningStat$ <> "?" and warningStat$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.22, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup
# Python deleted tempInput$ and tempCSV$ via --cleanup.
# Praat deletes tempOutput$ (already imported) and tempStats$.
# ===========================================================================

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
appendInfoLine: "Output:     ", soundName$, "_stftdec (stereo)"
appendInfoLine: "Preset:     ", presetName$
appendInfoLine: ""
appendInfoLine: "Events:     ", nEvStat$
appendInfoLine: "Nav steps:  ", nStepsStat$, " | mode: ", navModeStat$
appendInfoLine: "Phase:      ", phaseModeStat$
appendInfoLine: "VAE loss:   ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "Latent:     ", latentStat$, " | beta: ", betaStat$, " | epochs: ", epochsStat$
appendInfoLine: "STFT:       n_fft=", nFftStat$, "  hop=", hopStat$,
    ... "  frames=", patchFStat$, "  freq_bins=", freqBinsStat$
appendInfoLine: "Duration:   ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "Normalize:  ", normModeStat$, " | RMS: ", rmsInputStat$, " -> ", rmsOutputStat$

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