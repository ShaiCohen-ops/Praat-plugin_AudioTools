# ============================================================
# Praat AudioTools - LatentSTFTDecoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4.1 (2026) - Musically focused two-layer interface with independent Processing/STFT profiles
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Latent STFT Decoder
#
#   Trains a compact MLP Beta-VAE on downsampled log-magnitude STFT
#   patches extracted from event-segmented audio, then navigates the
#   latent space to synthesise new audio via decoded magnitude shapes.
#
#   Waveform reconstruction modes:
#     borrow     — decoded magnitude shaped by a K-neighbour complex-STFT
#                  mixture (phase comes from the real-event mixture)
#     griffinlim — iterative Griffin-Lim phase reconstruction
#
#   Latent navigation modes:
#     interpolate  — smooth cyclic interpolation through event latents
#     random_walk  — seeded walk from a real event, with occasional jumps
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

# Praat 7+: allow script file/Python operations when trust is required.
if praatVersion >= 7000
    askForTrust()
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_stft_decoder.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_stft_decoder.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_stft_decoder.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_stftdec_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_stftdec_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_stftdec_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_stftdec_stats.txt"

# ---- MAIN FORM  (musical decisions only) ----
form Latent STFT Decoder v1.4.1
    optionmenu Processing_character: 2
        option Fast
        option Balanced
        option Deep
        option Custom
    optionmenu STFT_character: 3
        option Micro / Grain
        option Transient
        option Balanced
        option Spectral
        option Sustained
        option Custom
    optionmenu Navigation: 1
        option Interpolate
        option Random walk
        option Drift
    optionmenu Phase_reconstruction: 1
        option Borrowed event phase
        option Griffin-Lim
    real Duration_(0_=_original) 0
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# PROFILE DEFAULTS
# The main form chooses musical character. Numerical DSP/ML parameters stay
# hidden unless Custom/Edit details is requested.
# ---------------------------------------------------------------------------

# Common defaults (also starting values for Custom)
latent_size  = 8
beta         = 0.5
epochs       = 30
vae_freq     = 32
vae_frames   = 16
n_fft        = 512
hop_length   = 128
patch_frames = 32
k_neighbors  = 4
step_size    = 0.30
temperature  = 0.25
p_jump       = 0.05
visit_weight = 2.0
visit_decay  = 0.92
normalize_mode = 3
seed         = 42

# Praat always supplies a concrete target duration; Python derives the actual
# navigation step count from duration and the rendered STFT-segment geometry.
nav_steps = 30

# ---- PROCESSING CHARACTER  (VAE capacity/training only) ----
if processing_character = 1
    # Same VAE-side values as the former Quick preset.
    latent_size = 6
    beta        = 0.5
    epochs      = 15
    vae_freq    = 16
    vae_frames  = 8
    processingName$ = "Fast"
elsif processing_character = 2
    # Same VAE-side values as the former Standard preset.
    latent_size = 8
    beta        = 0.5
    epochs      = 30
    vae_freq    = 32
    vae_frames  = 16
    processingName$ = "Balanced"
elsif processing_character = 3
    # Same VAE-side values as the former High quality preset.
    latent_size = 16
    beta        = 0.5
    epochs      = 60
    vae_freq    = 48
    vae_frames  = 24
    processingName$ = "Deep"
else
    processingName$ = "Custom"
endif

# ---- STFT CHARACTER  (time/frequency behaviour only) ----
if sTFT_character = 1
    # Former Quick STFT geometry: short context, fast temporal renewal.
    n_fft        = 256
    hop_length   = 64
    patch_frames = 16
    stftName$    = "Micro/Grain"
elsif sTFT_character = 2
    # Same fine FFT/hop as Micro, but twice the temporal context.
    n_fft        = 256
    hop_length   = 64
    patch_frames = 32
    stftName$    = "Transient"
elsif sTFT_character = 3
    # Former Standard STFT geometry.
    n_fft        = 512
    hop_length   = 128
    patch_frames = 32
    stftName$    = "Balanced"
elsif sTFT_character = 4
    # Former High quality STFT geometry: larger spectral window/context.
    n_fft        = 1024
    hop_length   = 256
    patch_frames = 64
    stftName$    = "Spectral"
elsif sTFT_character = 5
    # Same large FFT/context as Spectral, denser overlap for smoother sustain.
    n_fft        = 1024
    hop_length   = 128
    patch_frames = 64
    stftName$    = "Sustained"
else
    stftName$    = "Custom"
endif

# ---- MAP MUSICAL MENUS ----
# navigation: 1=interpolate 2=random_walk 3=drift
nav_mode = navigation

# phase_reconstruction: 1=borrow 2=griffinlim
phase_mode = phase_reconstruction

# ---- OPTIONAL DETAILS ----
# Custom profiles automatically open details; otherwise the second window is
# skipped unless explicitly requested.
openDetails = edit_details
if processing_character = 4 or sTFT_character = 6
    openDetails = 1
endif

if openDetails
    beginPause: "Details - Latent STFT Decoder"
        comment: "---- Learning / VAE ----"
        integer: "Latent_size", latent_size
        real: "Beta_(KL_weight)", beta
        integer: "Epochs", epochs
        integer: "Vae_freq", vae_freq
        integer: "Vae_frames", vae_frames
        comment: "---- STFT geometry ----"
        integer: "N_fft", n_fft
        integer: "Hop_length", hop_length
        integer: "Patch_frames", patch_frames
        comment: "---- Reconstruction / source continuity ----"
        integer: "K_neighbors", k_neighbors
        real: "Visit_weight", visit_weight
        real: "Visit_decay", visit_decay
        comment: "---- Motion (Random walk / Drift only) ----"
        real: "Step_size", step_size
        real: "Temperature", temperature
        real: "P_jump", p_jump
        comment: "---- Output / reproducibility ----"
        choice: "Normalize_mode", normalize_mode
            option: "none"
            option: "peak"
            option: "rms"
        integer: "Seed", seed
    clicked = endPause: "Cancel", "Render", 2
    if clicked = 1
        exitScript
    endif
endif


# ---- CLAMP VALUES ----
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif
if epochs < 5
    epochs = 5
endif
if epochs > 500
    epochs = 500
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
writeInfoLine:  "=== Latent STFT Decoder v1.4.1 ==="
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Processing:  ", processingName$
appendInfoLine: "STFT char.:  ", stftName$
appendInfoLine: ""
appendInfoLine: "Latent size: ", latent_size
appendInfoLine: "Beta (KL):   ", fixed$(beta, 3)
appendInfoLine: "Epochs:      ", epochs
appendInfoLine: "Duration:    ", if duration > 0 then fixed$(duration, 1) else "original" fi
appendInfoLine: "Seed:        ", seed
appendInfoLine: ""
appendInfoLine: "STFT: n_fft=", n_fft, "  hop=", hop_length, "  patch_frames=", patch_frames
appendInfoLine: "Nav:  mode=", navModeStr$, "  steps=auto from duration/STFT",
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

# Event times exported to Python are relative to the file start (0..duration).
# Shift only the analysis copy so non-zero Sound xmin cannot offset boundaries.
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

probeMarker$  = temporaryDirectory$ + "/temp_stftdec_pyprobe.ok"
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif

    exitScript: "Python dependency probe failed." + newline$
        ... + "Python command: " + pythonCmd$ + newline$
        ... + "Required packages: numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 4 — Call Python
# ===========================================================================

appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  VAE: latent=", latent_size, "  epochs=", epochs,
    ... "  beta=", fixed$(beta, 3)
appendInfoLine: "  STFT: n_fft=", n_fft, "  hop=", hop_length,
    ... "  frames=", patch_frames
appendInfoLine: "  Nav: ", navModeStr$, "  steps=auto from duration/STFT"

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

# Remove any stale output/stats from a PREVIOUS run before calling Python.
# These temps live in the plugin folder (not the OS temp dir), so a stale
# file survives reboots. Without this, a crashed run after a prior success
# would leave the old output in place and the fileReadable() check below
# would pass on stale data - silently importing a previous result as new.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

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
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Latent STFT Decoder v1.4.1##"
    Font size: 8
    Colour: "{0.34,0.38,0.48}"
    subtitleStr$ = soundName$ + " | " + processingName$ + " / " + stftName$
        ... + " | " + navModeStr$ + " | latent=" + string$(latent_size)
        ... + " | n_fft=" + string$(n_fft)
    Text: 0.5, "centre", 0.30, "half", subtitleStr$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    selectObject: sound
    Colour: "{0.36,0.39,0.45}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    Axes: 0, dur, -1, 1
    Colour: "{0.55,0.65,0.82}"
    Line width: 1
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
    Colour: "{0.20,0.40,0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Decoded"
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
    Text top: "no", "Decoded magnitude + reconstructed phase (channel 1)"
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
        Paint rectangle: "{0.955,0.965,0.985}", axMinX, axMaxX, axMinY, axMaxY

        # Event positions as small axis-aware squares (safe across viewports).
        markDX = (axMaxX - axMinX) * 0.008
        markDY = (axMaxY - axMinY) * 0.012
        for iEP from 0 to nSEvPts - 1
            Paint rectangle: "{0.70,0.73,0.79}", sep_'iEP'_x - markDX, sep_'iEP'_x + markDX, sep_'iEP'_y - markDY, sep_'iEP'_y + markDY
        endfor

        # Trajectory path
        Colour: "{0.20,0.40,0.75}"
        Line width: 2
        for iTP from 1 to nSTrajPts - 1
            iPrev = iTP - 1
            Draw line: stp_'iPrev'_x, stp_'iPrev'_y, stp_'iTP'_x, stp_'iTP'_y
        endfor
        Line width: 1

        # Start/end markers: blue start, slate-violet end.
        if nSTrajPts > 0
            bigDX = markDX * 1.8
            bigDY = markDY * 1.8
            Paint rectangle: "{0.20,0.40,0.75}", stp_0_x - bigDX, stp_0_x + bigDX, stp_0_y - bigDY, stp_0_y + bigDY
            iLast = nSTrajPts - 1
            Paint rectangle: "{0.46,0.39,0.64}", stp_'iLast'_x - bigDX, stp_'iLast'_x + bigDX, stp_'iLast'_y - bigDY, stp_'iLast'_y + bigDY
        endif

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "PC2"
        Text bottom: "yes", "PC1"
        Text top: "no", "Measured latent trajectory | blue=start, violet=end"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.955,0.965,0.985}", 0, 1, 0, 1
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
    Paint rectangle: "{0.945,0.955,0.975}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "events -> STFT log-mag -> MLP beta-VAE -> latent path -> decoded magnitude + phase -> iSTFT"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.76, "half",
        ... navModeStat$ + " " + nStepsStat$ + " steps | "
        ... + phaseModeStat$ + " | Events=" + nEvStat$
        ... + " | Dur: " + fixed$(dur, 2) + "s->" + outDurStat$ + "s"
    Colour: "{0.20,0.40,0.75}"
    Text: 0.02, "left", 0.58, "half",
        ... "STFT: fft=" + nFftStat$ + " hop=" + hopStat$
        ... + " frames=" + patchFStat$ + " bins=" + freqBinsStat$
        ... + " | Norm=" + normModeStat$
        ... + " | RMS: " + rmsInputStat$ + "->" + rmsOutputStat$
    Colour: "{0.46,0.39,0.64}"
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
appendInfoLine: "Output:     ", soundName$, "_stftdec (dual mono)"
appendInfoLine: "Processing: ", processingName$
appendInfoLine: "STFT char.: ", stftName$
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