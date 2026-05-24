# ============================================================
# Praat AudioTools - Beltrami_Inspired_Spectral_Melter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Beltrami-inspired anisotropic diffusion spectral processor.
#
#   The spectrogram is treated as a 3-D acoustic terrain:
#     X = time frame,  Y = frequency bin,  Z = log energy.
#   Anisotropic diffusion (Perona-Malik / Beltrami-inspired)
#   flows freely across smooth spectral plains and is blocked
#   at ridges (attacks, formant edges, note boundaries).
#   The diffused matrix encodes a reshaped spectral terrain.
#
# Changelog v2.3:
#   - Roll off FFT bins above max_frequency_Hz (was clamping them to
#     the top analyzed bin, adding a spurious high shelf / stereo hiss
#     in Full Quality mode)
#   - Reevaluate_edges option: true Perona-Malik conductance recomputed
#     from the current terrain each iteration (default off = v2.2 static)
#
# ============================================================

form Beltrami Inspired Spectral Melter v2.3
    comment Select a Sound object first.

    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Shimmer Haze
        option Deep Terrain
        option Edge Freeze
        option Fog of War
        option Formant Cloud
        option Transient Glass
        option Void Chasm

    comment === Analysis ===
    positive  Window_size_ms        40.0
    positive  Time_step_ms          10.0
    positive  Max_frequency_Hz    6000.0
    positive  Freq_resolution_Hz   100.0
    integer   Dynamic_floor_dB      -80

    comment === Diffusion ===
    integer   Iterations              6
    positive  Time_diffusion         0.15
    positive  Freq_diffusion         0.12
    positive  Ridge_sensitivity      1.8
    positive  Edge_preservation      1.0
    boolean   Reevaluate_edges        0

    comment === Effect ===
    positive  Effect_strength        3.0
    positive  Wet_dry_mix            0.85

    comment === Stereo (Paulstretch pattern) ===
    boolean   Create_stereo          1
    positive  Stereo_phase_offset    0.3

    comment === Output ===
    optionmenu Speed_mode: 1
        option Full quality (original sr)
        option Balanced (22 kHz)
        option Fast (11 kHz)
    boolean   Draw_visualization     1
    boolean   Play_result            1
endform

# ============================================================
#  PRESETS
# ============================================================

if preset = 2
    window_size_ms     = 40
    time_step_ms       = 10
    max_frequency_Hz   = 6000
    freq_resolution_Hz = 80
    dynamic_floor_dB   = -80
    iterations         = 8
    time_diffusion     = 0.20
    freq_diffusion     = 0.05
    ridge_sensitivity  = 2.5
    edge_preservation  = 1.2
    effect_strength    = 2.5
    wet_dry_mix        = 0.80
    preset_name$       = "Shimmer Haze"

elsif preset = 3
    window_size_ms     = 60
    time_step_ms       = 15
    max_frequency_Hz   = 5000
    freq_resolution_Hz = 100
    dynamic_floor_dB   = -70
    iterations         = 12
    time_diffusion     = 0.20
    freq_diffusion     = 0.18
    ridge_sensitivity  = 1.2
    edge_preservation  = 0.8
    effect_strength    = 4.0
    wet_dry_mix        = 0.90
    preset_name$       = "Deep Terrain"

elsif preset = 4
    window_size_ms     = 30
    time_step_ms       = 8
    max_frequency_Hz   = 7000
    freq_resolution_Hz = 70
    dynamic_floor_dB   = -80
    iterations         = 5
    time_diffusion     = 0.10
    freq_diffusion     = 0.08
    ridge_sensitivity  = 3.5
    edge_preservation  = 2.0
    effect_strength    = 2.0
    wet_dry_mix        = 0.70
    preset_name$       = "Edge Freeze"

elsif preset = 5
    window_size_ms     = 50
    time_step_ms       = 12
    max_frequency_Hz   = 5000
    freq_resolution_Hz = 120
    dynamic_floor_dB   = -75
    iterations         = 10
    time_diffusion     = 0.12
    freq_diffusion     = 0.22
    ridge_sensitivity  = 1.5
    edge_preservation  = 0.9
    effect_strength    = 4.0
    wet_dry_mix        = 0.88
    preset_name$       = "Fog of War"

elsif preset = 6
    window_size_ms     = 35
    time_step_ms       = 8
    max_frequency_Hz   = 5000
    freq_resolution_Hz = 50
    dynamic_floor_dB   = -80
    iterations         = 7
    time_diffusion     = 0.18
    freq_diffusion     = 0.06
    ridge_sensitivity  = 2.0
    edge_preservation  = 1.5
    effect_strength    = 3.0
    wet_dry_mix        = 0.75
    preset_name$       = "Formant Cloud"

elsif preset = 7
    window_size_ms     = 25
    time_step_ms       = 6
    max_frequency_Hz   = 8000
    freq_resolution_Hz = 80
    dynamic_floor_dB   = -80
    iterations         = 6
    time_diffusion     = 0.22
    freq_diffusion     = 0.04
    ridge_sensitivity  = 4.0
    edge_preservation  = 2.5
    effect_strength    = 3.5
    wet_dry_mix        = 0.82
    preset_name$       = "Transient Glass"

elsif preset = 8
    # Void Chasm -----------------------------------------------
    # 100 ms window: very long frame, captures broad spectral
    #   shape per snapshot.
    # 40 ms timestep: sparse temporal coverage — only ~25 frames
    #   per second, so each diffusion iteration bridges large
    #   time gaps, producing long spectral memory.
    # max 12000 Hz: full upper-mid and presence range.
    # 18 iterations, dt=0.24/0.20: maximum allowed diffusion
    #   per step; after 18 passes the terrain is deeply smeared.
    # kappa_eff = 2.5 / 1.5 ≈ 1.67: Fix 1 corrected formula (division);
    #   still a moderate-to-large kappa that allows diffusion to flow
    #   freely across moderate gradients.
    # effect_strength 8.0: extreme exaggeration of the diffused
    #   terrain; spectral peaks soar, valleys drop to zero.
    # wet_dry_mix 1.0: pure wet signal, no dry bleed.
    # create_stereo = 1, stereo_phase_offset = 0.5: L and R
    #   channels get independent random phases; R phase drawn
    #   from 1.5× wider range than L.
    window_size_ms      = 100
    time_step_ms        = 40
    max_frequency_Hz    = 12000
    freq_resolution_Hz  = 150
    dynamic_floor_dB    = -80
    iterations          = 18
    time_diffusion      = 0.24
    freq_diffusion      = 0.20
    ridge_sensitivity   = 2.5
    edge_preservation   = 1.5
    effect_strength     = 8.0
    wet_dry_mix         = 1.0
    create_stereo       = 1
    stereo_phase_offset = 0.5
    preset_name$        = "Void Chasm"

else
    preset_name$ = "Custom"
endif

# ============================================================
#  SPEED MODE
# ============================================================

if speed_mode = 1
    targetSR  = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR  = 22050
    speedStr$ = "Balanced (22 kHz)"
else
    targetSR  = 11025
    speedStr$ = "Fast (11 kHz)"
endif

# ============================================================
#  1.  INPUT
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original      = selected("Sound")
originalName$ = selected$("Sound")
uid$          = string$(randomInteger(10000, 99999))
startTime     = stopwatch

selectObject: original
nChannels  = Get number of channels
inputDur   = Get total duration
originalSR = Get sampling frequency

if nChannels > 1
    selectObject: original
    Convert to mono
    source = selected("Sound")
else
    selectObject: original
    Copy: "src_" + uid$
    source = selected("Sound")
endif
selectObject: source
Rename: "src_" + uid$

if targetSR > 0 and originalSR > targetSR
    selectObject: source
    Resample: targetSR, 50
    resampled = selected("Sound")
    removeObject: source
    source    = resampled
    workingSR = targetSR
else
    workingSR = originalSR
endif

selectObject: source
sourceDur = Get total duration

# ============================================================
#  2.  ANALYSIS PARAMETERS + pow2 WINDOW (Paulstretch Fix A)
# ============================================================

windowLength   = window_size_ms   / 1000
timeStep       = time_step_ms     / 1000
fRes           = freq_resolution_Hz
dynFloor       = dynamic_floor_dB

requestedSamp = round(windowLength * workingSR)
windowSamples = 1
while windowSamples < requestedSamp
    windowSamples = windowSamples * 2
endwhile
windowLength = windowSamples / workingSR

# Fix 2: Nyquist safety clamp.
# Presets (e.g. Void Chasm 12 kHz) can exceed the working Nyquist
# in Balanced / Fast speed modes, causing silent mis-binning.
nyquist = workingSR / 2
if max_frequency_Hz > nyquist - fRes
    max_frequency_Hz = nyquist - fRes
    appendInfoLine: "  [Nyquist clamp] max_frequency_Hz -> ",
        ... fixed$(max_frequency_Hz, 0), " Hz"
endif

selectObject: source
spectrogram = To Spectrogram: windowLength, max_frequency_Hz,
    ... timeStep, fRes, "Gaussian"

selectObject: spectrogram
nFrames = Get number of frames
nBins   = round(max_frequency_Hz / fRes)
; Fix 3: this estimate is used only for the early info-print below.
; The authoritative nBins is read from the actual Matrix after To Matrix.

writeInfoLine:  "=== BeltramiInspired Spectral Melter v2.3 ==="
appendInfoLine: "Preset  : ", preset_name$
appendInfoLine: "Source  : ", originalName$, " (", fixed$(inputDur, 2), " s)"
appendInfoLine: "Speed   : ", speedStr$
appendInfoLine: "Window  : ", fixed$(windowLength*1000, 1), " ms (",
    ... windowSamples, " samples, pow2)"
appendInfoLine: "Frames  : ", nFrames, "   Bins: ", nBins
appendInfoLine: "Iters   : ", iterations
if create_stereo
    appendInfoLine: "Stereo  : YES (phase offset: ", stereo_phase_offset, ")"
else
    appendInfoLine: "Stereo  : NO (mono)"
endif
appendInfoLine: ""

# ============================================================
#  3.  LOG-ENERGY MATRIX  (C-level Spectrogram -> Matrix)
# ============================================================

appendInfoLine: "[1/4] Log-energy matrix..."

selectObject: spectrogram
logEnergy = To Matrix
Rename: "logEnergy_" + uid$
removeObject: spectrogram

# Fix 3: authoritative nBins from real matrix dimensions.
# Replaces the estimate above; prevents off-by-one mis-indexing in
# gradMag, meanAmp, and all object[daID, bin, frame] lookups.
selectObject: logEnergy
nFrames = Get number of columns
nBins   = Get number of rows

selectObject: logEnergy
dFloor = dynFloor
Formula: "if self > 0 then max(10*log10(self), dFloor) else dFloor fi"

# ============================================================
#  4.  GRADIENT MAGNITUDE  (two vectorised Formula passes)
# ============================================================

appendInfoLine: "[2/4] Gradient map..."

leID = logEnergy

gradMag = Create Matrix: "gradMag_" + uid$,
    ... 1, nFrames, nFrames, 1, 1,
    ... 1, nBins,   nBins,   1, 1, "0"

selectObject: gradMag
Formula: "if col>1 and col<nFrames then ((object[leID,row,col+1]-object[leID,row,col-1])/2)^2 else if col=1 then (object[leID,row,2]-object[leID,row,1])^2 else (object[leID,row,nFrames]-object[leID,row,nFrames-1])^2 fi fi"

gradF = Copy: "gradF_" + uid$
selectObject: gradF
Formula: "if row>1 and row<nBins then ((object[leID,row+1,col]-object[leID,row-1,col])/2)^2 else if row=1 then (object[leID,2,col]-object[leID,1,col])^2 else (object[leID,nBins,col]-object[leID,nBins-1,col])^2 fi fi"

gfID = gradF
selectObject: gradMag
Formula: "sqrt(self + object[gfID,row,col])"
removeObject: gradF

# ============================================================
#  5.  ANISOTROPIC DIFFUSION
#  1 Copy + 1 single-line Formula per iteration.
#  All four fluxes merged into one expression.
# ============================================================

appendInfoLine: "[3/4] Anisotropic diffusion..."

dt_t = time_diffusion
dt_f = freq_diffusion
if dt_t > 0.24
    dt_t = 0.24
endif
if dt_f > 0.24
    dt_f = 0.24
endif
kappa_eff = ridge_sensitivity / edge_preservation
; Fix 1: division so higher Edge_preservation = stronger ridge protection.

reevaluateEdges = reevaluate_edges
if reevaluateEdges
    condStr$ = "per-iteration (true PM)"
else
    condStr$ = "static"
endif

selectObject: logEnergy
diffused = Copy: "diffused_" + uid$
gmID = gradMag

for iter from 1 to iterations
    diffID = diffused
    if reevaluateEdges
        # True Perona-Malik: re-evaluate conductance from the CURRENT
        # diffused terrain each iteration (edges dissolve as it flows).
        selectObject: gradMag
        Formula: "if col>1 and col<nFrames then ((object[diffID,row,col+1]-object[diffID,row,col-1])/2)^2 else if col=1 then (object[diffID,row,2]-object[diffID,row,1])^2 else (object[diffID,row,nFrames]-object[diffID,row,nFrames-1])^2 fi fi"
        gradFt = Copy: "gradFt_" + uid$
        selectObject: gradFt
        Formula: "if row>1 and row<nBins then ((object[diffID,row+1,col]-object[diffID,row-1,col])/2)^2 else if row=1 then (object[diffID,2,col]-object[diffID,1,col])^2 else (object[diffID,nBins,col]-object[diffID,nBins-1,col])^2 fi fi"
        gradFtID = gradFt
        selectObject: gradMag
        Formula: "sqrt(self + object[gradFtID,row,col])"
        removeObject: gradFt
    endif
    selectObject: diffused
    tempMat = Copy: "temp_" + uid$
    selectObject: tempMat
    Formula: "object[diffID,row,col] + dt_t*((if col<nFrames then exp(-(((object[gmID,row,col]+object[gmID,row,col+1])/2)/kappa_eff)^2)*(object[diffID,row,col+1]-object[diffID,row,col]) else 0 fi)+(if col>1 then exp(-(((object[gmID,row,col]+object[gmID,row,col-1])/2)/kappa_eff)^2)*(object[diffID,row,col-1]-object[diffID,row,col]) else 0 fi)) + dt_f*((if row<nBins then exp(-(((object[gmID,row,col]+object[gmID,row+1,col])/2)/kappa_eff)^2)*(object[diffID,row+1,col]-object[diffID,row,col]) else 0 fi)+(if row>1 then exp(-(((object[gmID,row,col]+object[gmID,row-1,col])/2)/kappa_eff)^2)*(object[diffID,row-1,col]-object[diffID,row,col]) else 0 fi))"
    removeObject: diffused
    diffused = tempMat
    appendInfoLine: "  iter ", iter, "/", iterations
endfor

removeObject: gradMag

# ============================================================
#  6.  BUILD DIFFUSED AMPLITUDE MATRIX
#
#  diffAmp(bin, frm) = linear amplitude derived from the
#  diffused log-energy terrain, exaggerated by effect_strength
#  to make spectral changes perceptually strong.
#
#  The exaggeration works around the per-bin MEAN amplitude:
#    mean_amp(frm) = average amplitude across bins for frame
#    deviation     = diffused_amp - mean_amp
#    exaggerated   = mean_amp + deviation * effect_strength
#
#  effect_strength = 1: exact diffused shape (may be subtle)
#  effect_strength = 3: deviations tripled (clearly audible)
#  effect_strength = 8: extreme spectral sculpting (Void Chasm)
#
#  This preserves the average energy per frame while pushing
#  spectral peaks higher and valleys lower — exactly what
#  makes the diffused terrain shape audible.
# ============================================================

efStr = effect_strength

# Convert diffused dB -> linear amplitude
selectObject: diffused
diffAmp = Copy: "diffAmp_" + uid$
selectObject: diffAmp
Formula: "10^(self/20)"
removeObject: diffused, logEnergy

# Per-frame mean amplitude: accumulate into 1-row matrix
diffAmpID = diffAmp
meanAmp = Create Matrix: "meanAmp_" + uid$,
    ... 1, nFrames, nFrames, 1, 1,
    ... 1, 1,       1,       1, 1, "0"

for bin from 1 to nBins
    selectObject: meanAmp
    Formula: "self + object[diffAmpID, bin, col]"
endfor
selectObject: meanAmp
Formula: "self / nBins"

# Exaggerate: new_amp = mean + (diffAmp - mean) * effect_strength
maID = meanAmp
selectObject: diffAmp
Formula: "object[maID,1,col] + (self - object[maID,1,col]) * efStr"

# Clamp to positive (exaggeration can push low bins below 0)
selectObject: diffAmp
Formula: "max(0, self)"
removeObject: meanAmp

# ============================================================
#  7.  OVERLAP-ADD RESYNTHESIS
#
#  Procedure olaChannel: .outSnd, .phaseScale, .chanName$
#  --------------------------------------------------------
#  Modelled directly on Paulstretch v1.1 procedure structure.
#
#  For each OLA frame:
#  a) Extract + pad to pow2 windowLength (Fix A)
#  b) FFT -> complex Matrix (2 rows: real / imag)
#  c) Diffused frame index lookup from diffAmp (daID)
#  d) Build shaped complex:
#
#     MONO (create_stereo = 0):
#       Compute original magnitude -> aux magsMat (Fix B)
#       new = orig_complex * (diffMag / orig_mag)
#       Phase is PRESERVED from the source frame.
#
#     STEREO (create_stereo = 1):
#       Precompute random phases into phasesMat:
#         row 1: randomUniform(-pi, pi) * .phaseScale
#       new_real = diffMag * cos(randPhase)    [row 1]
#       new_imag = diffMag * sin(randPhase)    [row 2]
#       DC (col=1) and Nyquist (col=.ncols) preserved.
#       Phase is RANDOMISED, independently per channel
#       (same mechanism as Paulstretch stereo_phase_offset).
#
#  e) IFFT -> Hann window -> micro-fades -> Formula (part) OLA
#
#  Caller sets up channels:
#    MONO:   one call  with phaseScale=1.0  -> sound_wet
#    STEREO: two calls L(1.0) + R(1+offset) -> sound_wet_L/R
#            then Combine to stereo
# ============================================================

appendInfoLine: "[4/4] Overlap-add resynthesis..."

overlapFrac  = 0.75
hopTime      = windowLength * (1 - overlapFrac)
nOlaFrames   = ceiling(sourceDur / hopTime) + 2
microFadeDur = 0.003

# Aliases used inside the procedure as outer-scope globals
daID = diffAmp
tStp = timeStep
nFrm = nFrames
nBns = nBins
fRs  = fRes
wSR  = workingSR

progressStep = max(1, round(nOlaFrames / 20))

procedure olaChannel: .outSnd, .normSnd, .phaseScale, .chanName$
    ; Fix 4: .normSnd accumulates synthesis-Hann² per frame for OLA
    ; normalisation. After the loop the caller divides out / norm.
    appendInfoLine: "  Channel: ", .chanName$

    for .iframe from 0 to nOlaFrames - 1

        if .iframe mod progressStep = 0
            appendInfoLine: "    ", floor(.iframe/nOlaFrames*100), "%"
        endif

        .tIn    = .iframe * hopTime
        .tStart = .tIn - windowLength/2
        .tEnd   = .tIn + windowLength/2
        if .tStart < 0
            .tStart = 0
        endif
        if .tEnd > sourceDur
            .tEnd = sourceDur
        endif

        if .tEnd - .tStart >= 0.005

            # --- a) Extract + Hann window + pad to windowLength ---
            selectObject: source
            Extract part: .tStart, .tEnd, "Hanning", 1, "no"
            .frame    = selected("Sound")
            selectObject: .frame
            .frameDur = Get total duration

            if abs(.frameDur - windowLength) > 0.00001
                Create Sound from formula: "pad_" + uid$, 1, 0,
                    ... windowLength, workingSR, "0"
                .padded = selected("Sound")
                .offs   = max(0, -.tStart + .tIn - windowLength/2)
                .frmID  = .frame
                selectObject: .padded
                Formula: "if x>=.offs and x<=.offs+.frameDur then object(.frmID, x-.offs) else 0 fi"
                removeObject: .frame
                .frame = .padded
            endif

            # --- b) FFT ---
            selectObject: .frame
            To Spectrum: "yes"
            .spectrum = selected("Spectrum")
            To Matrix
            .matCx = selected("Matrix")
            selectObject: .matCx
            .ncols = Get number of columns
            .mcID  = .matCx

            # --- c) Diffused frame index ---
            .fIdx = max(1, min(nFrm, round(.tIn / tStp + 0.5)))

            # --- d) Build shaped complex matrix ---
            selectObject: .matCx
            Copy: "shaped_" + uid$
            .shapedMat = selected("Matrix")

            if create_stereo
                # === STEREO: Paulstretch stereo_phase_offset pattern ===
                # Precompute one random phase per FFT bin (column).
                # .phaseScale differentiates L (1.0) from R (1+offset).
                # Both channels share daID but have independent draws
                # from randomUniform, so their spectrograms decorrelate.
                selectObject: .matCx
                Copy: "phases_" + uid$
                .phasesMat = selected("Matrix")
                .pmID = .phasesMat
                selectObject: .phasesMat
                Formula: "if row = 1 then randomUniform(-pi, pi) * .phaseScale else self fi"

                # new_real = diffMag * cos(randPhase)
                # new_imag = diffMag * sin(randPhase)
                # DC (col=1) and Nyquist (col=.ncols) preserved.
                selectObject: .shapedMat
                Formula: "if col=1 or col=.ncols then self else if round((col-1)*wSR/2/(.ncols-1)/fRs) > nBns then 0 else if row=1 then object[daID,max(1,min(nBns,round((col-1)*wSR/2/(.ncols-1)/fRs))),.fIdx]*cos(object[.pmID,1,col]) else object[daID,max(1,min(nBns,round((col-1)*wSR/2/(.ncols-1)/fRs))),.fIdx]*sin(object[.pmID,1,col]) fi fi fi"

                removeObject: .phasesMat

            else
                # === MONO: keep original phase (v2.0 behaviour) ===
                # Original magnitudes -> aux matrix (Fix B: prevents
                # in-place corruption of the real/imag rows).
                selectObject: .matCx
                Copy: "mags_" + uid$
                .magsMat = selected("Matrix")
                selectObject: .magsMat
                Formula: "if row=1 then sqrt(object[.mcID,1,col]^2 + object[.mcID,2,col]^2) else 0 fi"
                .magsID = .magsMat

                # new = orig_complex * (diffMag / orig_mag)
                # = rotate magnitude to diffMag while keeping phase.
                selectObject: .shapedMat
                Formula: "if col=1 or col=.ncols then self else if round((col-1)*wSR/2/(.ncols-1)/fRs) > nBns then 0 else if object[.magsID,1,col]>0 then object[.mcID,row,col]/object[.magsID,1,col]*object[daID,max(1,min(nBns,round((col-1)*wSR/2/(.ncols-1)/fRs))),.fIdx] else 0 fi fi fi"

                removeObject: .magsMat
            endif

            # --- e) IFFT -> Hann -> micro-fades -> OLA ---
            selectObject: .shapedMat
            To Spectrum
            .specMod = selected("Spectrum")
            To Sound
            .processed = selected("Sound")
            selectObject: .processed
            Multiply by window: "Hanning"

            .procDur = Get total duration
            .fadeDur = min(microFadeDur, .procDur * 0.05)
            if .fadeDur > 0.0005
                Fade in:  0, 0,                  .fadeDur, "yes"
                Fade out: 0, .procDur - .fadeDur, .fadeDur, "yes"
            endif

            .tOut    = .tIn - windowLength/2
            if .tOut < 0
                .tOut = 0
            endif
            .tOutEnd = .tOut + windowLength
            if .tOutEnd > sourceDur + windowLength
                .tOutEnd = sourceDur + windowLength
            endif

            .procNs = Get number of samples
            selectObject: .outSnd
            .outS1 = Get sample number from time: .tOut
            if .outS1 < 1
                .outS1 = 1
            endif
            .sOff = .outS1 - 1

            Formula (part): .tOut, .tOutEnd, 1, 1,
                ... "self + object[" + string$(.processed) + ", col - " + string$(.sOff) + "]"

            # Fix 4: accumulate synthesis Hann² into the norm buffer.
            # norm(t) = sum_of_windows(t)^2; used after OLA to divide
            # out / norm so double-Hann double-Hann coloration cancels.
            Create Sound from formula: "normFrm_" + uid$, 1, 0,
                ... windowLength, workingSR,
                ... "(0.5 - 0.5*cos(2*pi*x/windowLength))^2"
            .normFrm = selected("Sound")
            selectObject: .normSnd
            Formula (part): .tOut, .tOutEnd, 1, 1,
                ... "self + object[" + string$(.normFrm) + ", col - " + string$(.sOff) + "]"
            removeObject: .normFrm

            removeObject: .frame, .spectrum, .matCx, .shapedMat, .specMod, .processed

        endif
    endfor
endproc

# --- Create output buffer(s) and run OLA ---

if create_stereo
    appendInfoLine: "  Stereo mode: L + R with independent phase seeds..."

    Create Sound from formula: "wet_L_" + uid$, 1, 0,
        ... sourceDur + windowLength, workingSR, "0"
    sound_wet_L = selected("Sound")
    Create Sound from formula: "norm_L_" + uid$, 1, 0,
        ... sourceDur + windowLength, workingSR, "0"
    norm_L = selected("Sound")
    @olaChannel: sound_wet_L, norm_L, 1.0, "LEFT"
    # Fix 4: normalise L channel by accumulated Hann² sum
    normLID = norm_L
    selectObject: sound_wet_L
    Formula: "if object[normLID,1,col] > 0.001 then self / object[normLID,1,col] else 0 fi"
    removeObject: norm_L

    Create Sound from formula: "wet_R_" + uid$, 1, 0,
        ... sourceDur + windowLength, workingSR, "0"
    sound_wet_R = selected("Sound")
    Create Sound from formula: "norm_R_" + uid$, 1, 0,
        ... sourceDur + windowLength, workingSR, "0"
    norm_R = selected("Sound")
    phaseScaleR = 1.0 + stereo_phase_offset
    @olaChannel: sound_wet_R, norm_R, phaseScaleR, "RIGHT"
    # Fix 4: normalise R channel
    normRID = norm_R
    selectObject: sound_wet_R
    Formula: "if object[normRID,1,col] > 0.001 then self / object[normRID,1,col] else 0 fi"
    removeObject: norm_R

else
    appendInfoLine: "  Mono mode..."

    Create Sound from formula: "wet_" + uid$, 1, 0,
        ... sourceDur + windowLength, workingSR, "0"
    sound_wet = selected("Sound")
    Create Sound from formula: "norm_" + uid$, 1, 0,
        ... sourceDur + windowLength, workingSR, "0"
    norm_wet = selected("Sound")
    @olaChannel: sound_wet, norm_wet, 1.0, "MONO"
    # Fix 4: normalise mono channel
    normWID = norm_wet
    selectObject: sound_wet
    Formula: "if object[normWID,1,col] > 0.001 then self / object[normWID,1,col] else 0 fi"
    removeObject: norm_wet
endif

removeObject: diffAmp

# ============================================================
#  8.  WET / DRY MIX + FINALIZE
# ============================================================

wet      = wet_dry_mix
dry      = 1 - wet_dry_mix
outName$ = originalName$ + "_BeltramiInspired_" + preset_name$

if create_stereo
    selectObject: sound_wet_L
    Scale peak: 0.99
    wetLID = sound_wet_L

    selectObject: sound_wet_R
    Scale peak: 0.99
    wetRID = sound_wet_R

    # Mix wet/dry for L channel
    selectObject: source
    out_L = Copy: "outL_" + uid$
    selectObject: out_L
    if wet >= 0.999
        Formula: "object[wetLID, 1, col]"
    else
        Formula: "self*dry + object[wetLID, 1, col]*wet"
    endif

    # Mix wet/dry for R channel
    selectObject: source
    out_R = Copy: "outR_" + uid$
    selectObject: out_R
    if wet >= 0.999
        Formula: "object[wetRID, 1, col]"
    else
        Formula: "self*dry + object[wetRID, 1, col]*wet"
    endif

    # Combine to stereo
    selectObject: out_L, out_R
    Combine to stereo
    sound_out = selected("Sound")
    Rename: outName$ + "_stereo"

    removeObject: out_L, out_R, sound_wet_L, sound_wet_R

else
    selectObject: sound_wet
    Scale peak: 0.99
    wetID = sound_wet

    selectObject: source
    sound_out = Copy: outName$
    selectObject: sound_out
    if wet >= 0.999
        Formula: "object[wetID, 1, col]"
    else
        Formula: "self*dry + object[wetID, 1, col]*wet"
    endif

    removeObject: sound_wet
endif

# Trim to sourceDur if the buffer overran
selectObject: sound_out
outDur = Get total duration
if outDur > sourceDur + 0.05
    currentName$ = selected$("Sound")
    Extract part: 0, sourceDur, "rectangular", 1, "no"
    trimmed = selected("Sound")
    Rename: currentName$
    removeObject: sound_out
    sound_out = trimmed
endif

# Final polish (works on mono and stereo alike)
selectObject: sound_out
Scale peak: 0.95
Fade in:  0, 0,              0.01, "yes"
Fade out: 0, sourceDur-0.02, 0.02, "yes"

# Upsample back to original SR if needed
if targetSR > 0 and originalSR > targetSR
    selectObject: sound_out
    currentName$ = selected$("Sound")
    Resample: originalSR, 50
    upsampled = selected("Sound")
    Rename: currentName$
    removeObject: sound_out
    sound_out = upsampled
endif

# ============================================================
#  9.  VISUALIZATION
# ============================================================

processingTime = stopwatch - startTime

if draw_visualization
    Erase all

    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half",
        ... "##BeltramiInspired Spectral Melter — " + preset_name$ + "##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.15, "half",
        ... originalName$ + "  |  iters:" + string$(iterations)
        ... + "  κ=" + fixed$(kappa_eff, 2)
        ... + "  dt_t=" + fixed$(dt_t, 2)
        ... + "  dt_f=" + fixed$(dt_f, 2)
        ... + "  str=" + fixed$(efStr, 1)
        ... + "  wet=" + fixed$(wet, 2)
        ... + "  " + fixed$(processingTime, 1) + "s"

    Select outer viewport: 0, 8, 0.52, 1.42
    Select inner viewport: 0.55, 7.65, 0.57, 1.37
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", originalName$ + "  (" + fixed$(inputDur, 2) + " s)"

    # Output waveform — stereo draws L (blue) + R (orange)
    Select outer viewport: 0, 8, 1.46, 2.36
    Select inner viewport: 0.55, 7.65, 1.51, 2.31
    selectObject: sound_out
    nChOut = Get number of channels
    if nChOut > 1
        Extract one channel: 1
        vizOutL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: sound_out
        Extract one channel: 2
        vizOutR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizOutL, vizOutR
    else
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Beltrami-inspired"
    Text bottom: "yes", "Time (s)"
    if nChOut > 1
        Text top: "no", "Output — " + preset_name$ + "  (stereo)"
    else
        Text top: "no", "Output — " + preset_name$
    endif

    Select outer viewport: 0, 4.1, 2.44, 3.84
    Select inner viewport: 0.55, 3.85, 2.54, 3.74
    selectObject: original
    nChOrig = Get number of channels
    if nChOrig > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn_" + uid$
        vizIn = selected("Sound")
    endif
    To Spectrogram: 0.03, max_frequency_Hz, 0.01, 20, "Gaussian"
    vizSpecIn = selected("Spectrogram")
    Paint: 0, 0, 0, max_frequency_Hz, 100, "yes", 50, 6, 0, "no"
    removeObject: vizSpecIn, vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original spectrogram"

    Select outer viewport: 4.1, 8, 2.44, 3.84
    Select inner viewport: 4.40, 7.65, 2.54, 3.74
    selectObject: sound_out
    if nChOut > 1
        Extract one channel: 1
        vizOut = selected("Sound")
    else
        Copy: "vizOut_" + uid$
        vizOut = selected("Sound")
    endif
    To Spectrogram: 0.03, max_frequency_Hz, 0.01, 20, "Gaussian"
    vizSpecOut = selected("Spectrogram")
    Paint: 0, 0, 0, max_frequency_Hz, 100, "yes", 50, 6, 0, "no"
    removeObject: vizSpecOut, vizOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "BeltramiInspired — " + preset_name$

    Select outer viewport: 0, 8, 3.92, 4.72
    Select inner viewport: 0.55, 7.65, 3.98, 4.66
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    if create_stereo
        stereoStr$ = "Stereo (offset=" + fixed$(stereo_phase_offset, 2) + ")"
    else
        stereoStr$ = "Mono"
    endif
    Text: 0.02, "left", 0.52, "half",
        ... "Preset: " + preset_name$
        ... + "  |  Iterations: " + string$(iterations)
        ... + "  |  κ=" + fixed$(kappa_eff, 2)
        ... + "  |  dt_t=" + fixed$(dt_t, 3)
        ... + "  dt_f=" + fixed$(dt_f, 3)
        ... + "  |  Effect strength: " + fixed$(efStr, 1)
        ... + "  |  Window: " + fixed$(windowLength*1000, 1) + " ms"
        ... + "  |  " + stereoStr$
    Text: 0.02, "left", 0.18, "half",
        ... "Frames: " + string$(nFrames) + "  Bins: " + string$(nBins)
        ... + "  |  Wet: " + fixed$(wet, 2)
        ... + "  |  " + speedStr$
        ... + "  |  Render: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Line width: 1
endif

# ============================================================
#  10.  CLEANUP
# ============================================================

removeObject: source

selectObject: sound_out

appendInfoLine: ""
appendInfoLine: "==========================================="
appendInfoLine: " BELTRAMI INSPIRED SPECTRAL MELTER v2.3 — Done"
appendInfoLine: "==========================================="
appendInfoLine: "Preset    : ", preset_name$
appendInfoLine: "Input     : ", originalName$, " (", fixed$(inputDur, 2), " s)"
appendInfoLine: "Window    : ", fixed$(windowLength*1000, 1), " ms (", windowSamples, " smp)"
appendInfoLine: "Frames    : ", nFrames, "   Bins: ", nBins
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Conduct.  : ", condStr$
appendInfoLine: "kappa     : ", kappa_eff
appendInfoLine: "dt_t      : ", dt_t, "   dt_f: ", dt_f
appendInfoLine: "Strength  : ", efStr
appendInfoLine: "Wet/Dry   : ", wet, " / ", dry
if create_stereo
    appendInfoLine: "Stereo    : YES (phase offset: ", stereo_phase_offset, ")"
else
    appendInfoLine: "Stereo    : NO (mono)"
endif
appendInfoLine: "Render    : ", fixed$(processingTime, 1), " s"
appendInfoLine: "Output    : ", selected$("Sound")
appendInfoLine: "-------------------------------------------"
appendInfoLine: "Beltrami-INSPIRED anisotropic diffusion."
appendInfoLine: "Not a full Laplace-Beltrami PDE solver."
appendInfoLine: "==========================================="

if play_result
    selectObject: sound_out
    Play
endif

selectObject: sound_out
