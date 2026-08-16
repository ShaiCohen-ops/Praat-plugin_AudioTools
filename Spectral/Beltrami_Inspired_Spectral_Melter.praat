# ============================================================
# Praat AudioTools - Beltrami_Inspired_Spectral_Melter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.5.2 (2026)
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
# Changelog v2.5.2 (2026) -- form / control flow only, DSP untouched:
#   - Compact main form now exposes only preset, stereo character, render mode,
#     details, visualization, and playback. Technical analysis/diffusion controls
#     no longer obscure the musical workflow.
#   - Preset values are applied BEFORE Edit details opens, so the details dialog
#     shows the exact values that will be rendered and can override them knowingly.
#   - Effect strength and wet/dry are the first fields in Edit details because
#     they are the most musically consequential continuous controls; analysis and
#     numerical diffusion parameters follow beneath them.
#   - Void Chasm no longer silently overrides the main-form stereo choice. Its
#     default is unchanged (stereo, widest offset), but mono/narrower choices now
#     remain under explicit user control.
#
# Changelog v2.5.1 (2026) -- visualization only, DSP untouched:
#   - The figure now MEASURES and states the thing it was implicitly showing:
#     what fraction of the resynthesis target has been pushed to the dynamic
#     floor by the contrast expansion. On Deep Terrain (effect_strength 4.0)
#     it is about 85%. That is why the third terrain reads as sparse speckle
#     and why the orange target curve in panel C lies on the floor across most
#     of the band: the expansion is close to binarising the spectrum. It is
#     the effect working, not the picture failing, and the figure now says so
#     instead of leaving it to look like a rendering fault.
#   - Panel A: each terrain gained a time axis; the third is relabelled
#     "TARGET dB (after strength xN)" rather than "TARGET magnitude", since
#     all three are painted on one dB scale and calling one of them magnitude
#     invited the reader to think the scales differed.
#   - Panel B left: the conductance curve had no x scale at all, so kappa and
#     the mean gradient were marked against nothing. It now carries gradient
#     magnitude in dB per cell, with the unit folded into the caption because
#     a Text bottom label collides with the caption strip beneath the panel.
#   - Panel C and panel D gained the marks they lacked; D's lower stave alone
#     carries the time axis so the two waveform boxes do not collide.
#   - Title block: the stereo phase law was drawn as a second Text in the same
#     strip and drifted into panel A's heading. Each line now has its own
#     anchored viewport.
#   - Plot panels shortened slightly so their new bottom marks clear the
#     caption strips that sit under each panel in this layout.
#
# Changelog v2.5 (2026):
#   - FIX (audible/transient accuracy): resynthesis now maps OLA time and FFT
#     frequency to the ACTUAL Spectrogram/Matrix sample grid (x1/dx/y1/dy).
#     v2.4 assumed x1=0 and dy=requested Freq_resolution_Hz; Praat
#     spectrograms generally start later than 0 and use a nearby but not
#     identical dy. The old mapping therefore anticipated spectral changes
#     by roughly one analysis-window centre offset and increasingly selected
#     the wrong frequency row toward the top of the band.
#   - FIX: wet stereo normalization is joint before dry/wet mixing; random
#     peak differences no longer alter the intended L/R level relationship.
#   - FIX: final peak scaling now happens after edge fades AND any return to
#     the original sample rate, so removable edge spikes and resampling
#     overshoot cannot leave the musical body too quiet or exceed the ceiling.
#   - FIX: Wet_dry_mix and Stereo_phase_offset accept the documented 0 value
#     and are validated to 0..1. Added optional Random_seed for reproducible
#     stereo phase realizations.
#   - ROBUSTNESS: clear validation for too-short sources / degenerate terrain
#     grids and duration-safe final fades.
#   - DOCUMENTATION: effect_strength is described as contrast expansion around
#     the per-frame mean AMPLITUDE (not energy preservation); the positivity
#     clamp can change that mean by design.
#   - VIZ: process-first display: original/diffused/target terrains, the actual
#     Perona-Malik-like conductance law, a measured frequency slice through the
#     frame with greatest terrain change, and final output verification.
#
# Changelog v2.4 (2026):
#   - FIX: Stereo_phase_offset was statistically a DEAD KNOB. Both
#     channels drew fully independent per-frame random phases, and
#     the offset merely scaled a uniform(-pi,pi) draw -- scaled
#     uniform phase mod 2pi is still ~uniform, so offset 0 did NOT
#     correlate the channels and 0.3 vs 1.5 were indistinguishable
#     (maximum width always). v2.4: phase = shared per-frame SEEDED
#     base + offset-scaled independent component (seeded RNG drives
#     Formula draws reproducibly -- verified on 6.4.42). Offset 0 =
#     identical channels, 1 = fully independent, which is exactly
#     the old sound in distribution -- presets and the form default
#     moved to 1.0 so nothing changes audibly until you turn it.
#   - FIX: the Nyquist-clamp notice printed before writeInfoLine
#     and was erased by the header.
#   - FIX: the final trim threshold (50 ms) let short-window
#     presets (Transient Glass, 46 ms pow2 window) keep a silent
#     tail; now 1 ms.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only negative-offset form is the margin-compression
#     collision geometry).
#   - AUDIT: verified correct as written -- the frozen-source
#     explicit diffusion scheme (stable, dt clamped), both
#     gradient passes, the exaggeration stage, the mono
#     phase-preserving shaping (Fix B), the Hann^2 OLA norm WITH
#     floored correction, the v2.3 bin rolloff, and the
#     early-frame pad/placement double-clamp (the two clamps
#     cancel; content lands at the correct absolute time).
#
# Changelog v2.3:
#   - Roll off FFT bins above max_frequency_Hz (was clamping them to
#     the top analyzed bin, adding a spurious high shelf / stereo hiss
#     in Full Quality mode)
#   - Reevaluate_edges option: true Perona-Malik conductance recomputed
#     from the current terrain each iteration (default off = v2.2 static)
#
# ============================================================

form Beltrami Inspired Spectral Melter v2.5.2
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
    comment (Preset supplies analysis, diffusion, strength, and wet/dry defaults.)

    comment === Spatial character ===
    boolean   Create_stereo          1
    real      Stereo_phase_offset    1.0
    comment (0 = identical channels ... 1 = fully independent/widest)

    comment === Render ===
    optionmenu Speed_mode: 1
        option Full quality (original sr)
        option Balanced (22 kHz)
        option Fast (11 kHz)
    boolean   Edit_details           0
    boolean   Draw_visualization     1
    boolean   Play_result            1
endform

# ============================================================
#  PRESETS
# ============================================================

# Defaults for Custom, and starting values for preset loading.
# Edit details is opened only AFTER presets are applied, so these variables are
# always defined and the dialog displays the values that will actually render.
window_size_ms     = 40.0
time_step_ms       = 10.0
max_frequency_Hz   = 6000.0
freq_resolution_Hz = 100.0
dynamic_floor_dB   = -80
iterations         = 6
time_diffusion      = 0.15
freq_diffusion      = 0.12
ridge_sensitivity  = 1.8
edge_preservation  = 1.0
reevaluate_edges   = 0
effect_strength    = 3.0
wet_dry_mix        = 0.85
random_seed        = 0

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
    # The shipped main-form default is stereo with phase offset 1.0, so the
    #   traditional Void Chasm sound stays widest by default; unlike v2.5.1,
    #   an explicit mono/narrower user choice is no longer overwritten here.
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
    preset_name$        = "Void Chasm"

else
    preset_name$ = "Custom"
endif

# ============================================================
#  OPTIONAL DETAILS -- values shown AFTER preset loading
# ============================================================

if edit_details
    beginPause: "Beltrami Spectral Melter v2.5.2 - Details"
        positive: "Effect strength", effect_strength
        real: "Wet/dry mix (0..1)", wet_dry_mix
        positive: "Window size (ms)", window_size_ms
        positive: "Time step (ms)", time_step_ms
        positive: "Max frequency (Hz)", max_frequency_Hz
        positive: "Frequency resolution (Hz)", freq_resolution_Hz
        integer: "Dynamic floor (dB, below 0)", dynamic_floor_dB
        integer: "Diffusion iterations", iterations
        positive: "Time diffusion", time_diffusion
        positive: "Frequency diffusion", freq_diffusion
        positive: "Ridge sensitivity", ridge_sensitivity
        positive: "Edge preservation", edge_preservation
        boolean: "Reevaluate edges each iteration", reevaluate_edges
        integer: "Random seed (0 = new realization)", random_seed
    endPause: "Render", 1
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

# User-facing controls whose musical meaning depends on a bounded range.
if wet_dry_mix < 0 or wet_dry_mix > 1
    exitScript: "Wet/dry mix must be between 0 and 1."
endif
if stereo_phase_offset < 0 or stereo_phase_offset > 1
    exitScript: "Stereo phase offset must be between 0 and 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (random) or a positive integer."
endif
if dynamic_floor_dB >= 0
    exitScript: "Dynamic floor must be below 0 dB."
endif

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

# A Gaussian Spectrogram needs enough signal around its analysis frames.
# Do not silently shrink the requested window because that changes the
# musical character of the preset; fail clearly instead.
if sourceDur < 2 * windowLength
    exitScript: "The selected sound is too short for this analysis window. Use a shorter Window size or a longer sound."
endif

if fRes <= 0
    exitScript: "Frequency resolution must be greater than 0 Hz."
endif

# Fix 2: Nyquist safety clamp.
# Presets (e.g. Void Chasm 12 kHz) can exceed the working Nyquist
# in Balanced / Fast speed modes, causing silent mis-binning.
nyquist = workingSR / 2
nyquistClampNote$ = ""
if max_frequency_Hz > nyquist - fRes
    max_frequency_Hz = nyquist - fRes
    nyquistClampNote$ = "[Nyquist clamp] max_frequency_Hz -> "
        ... + fixed$(max_frequency_Hz, 0) + " Hz"
endif
if max_frequency_Hz <= fRes
    exitScript: "Max frequency must leave room for at least two analyzed frequency rows after Nyquist limiting."
endif

selectObject: source
spectrogram = To Spectrogram: windowLength, max_frequency_Hz,
    ... timeStep, fRes, "Gaussian"

selectObject: spectrogram
nFrames = Get number of frames
nBins   = round(max_frequency_Hz / fRes)
; Fix 3: this estimate is used only for the early info-print below.
; The authoritative nBins is read from the actual Matrix after To Matrix.

writeInfoLine:  "=== BeltramiInspired Spectral Melter v2.5.2 ==="
appendInfoLine: "Preset  : ", preset_name$
appendInfoLine: "Source  : ", originalName$, " (", fixed$(inputDur, 2), " s)"
appendInfoLine: "Speed   : ", speedStr$
appendInfoLine: "Window  : ", fixed$(windowLength*1000, 1), " ms (",
    ... windowSamples, " samples, pow2)"
appendInfoLine: "Frames  : ", nFrames, "   Bins: ", nBins
appendInfoLine: "Iters   : ", iterations
if nyquistClampNote$ <> ""
    appendInfoLine: nyquistClampNote$
endif
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

# Authoritative grid from the REAL Matrix. Praat chooses a sampled
# spectrogram grid whose first sample and frequency spacing are not in
# general x1=0 / dy=requested Freq_resolution_Hz. These coordinates are
# therefore used later for every time/frequency lookup in resynthesis.
selectObject: logEnergy
nFrames = Get number of columns
nBins   = Get number of rows
if nFrames < 2 or nBins < 2
    exitScript: "Analysis produced a degenerate spectral terrain. Increase duration/max frequency or use finer resolution."
endif
specT1 = Get x of column: 1
specT2 = Get x of column: 2
specDt = specT2 - specT1
specF1 = Get y of row: 1
specF2 = Get y of row: 2
specDf = specF2 - specF1
specFTop = specF1 + (nBins - 1) * specDf

selectObject: logEnergy
dFloor = dynFloor
Formula: "if self > 0 then max(10*log10(self), dFloor) else dFloor fi"

# Keep process-state copies only when the figure is requested. They never
# enter the audio path.
if draw_visualization
    selectObject: logEnergy
    terrainOriginal = Copy: "terrain_original_" + uid$
endif

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

# Measured initial ridge field for QC/visualization.
selectObject: gradMag
gradMean0 = Get mean: 0, 0, 0, 0
gradMax0 = Get maximum

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

if draw_visualization
    selectObject: diffused
    terrainDiffused = Copy: "terrain_diffused_" + uid$
endif

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
#  Before the positivity clamp this preserves the per-frame ARITHMETIC
#  mean amplitude, not energy. Strong expansion can drive valleys below
#  zero; clamping them to zero is a deliberate musical nonlinearity and
#  can therefore raise the post-clamp mean.
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

if draw_visualization
    # Actual target-magnitude terrain used by resynthesis, expressed in dB.
    selectObject: diffAmp
    terrainTarget = Copy: "terrain_target_" + uid$
    selectObject: terrainTarget
    Formula: "if self > 1e-12 then 20*log10(self) else dFloor fi"
endif

# ============================================================
#  7.  OVERLAP-ADD RESYNTHESIS
#
#  Procedure olaChannel: .outSnd, .normSnd, .extraScale, .chanSeedOff, .chanName$
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
#         row 1: shared base phase + optional channel difference term
#       new_real = diffMag * cos(randPhase)    [row 1]
#       new_imag = diffMag * sin(randPhase)    [row 2]
#       DC (col=1) and Nyquist (col=.ncols) preserved.
#       Phase is RANDOMISED, independently per channel
#       (same mechanism as Paulstretch stereo_phase_offset).
#
#  e) IFFT -> Hann window -> micro-fades -> Formula (part) OLA
#
#  Caller sets up channels:
#    MONO:   one phase-preserving call -> sound_wet
#    STEREO: L uses the shared base field; R adds a phase-difference
#            term scaled by Stereo_phase_offset, then channels combine.
# ============================================================

appendInfoLine: "[4/4] Overlap-add resynthesis..."

# Per-run base for frame phase seeds. 0 keeps run-to-run variety; a
# positive user seed makes the complete stereo phase realization repeatable.
if random_seed > 0
    phaseSeedBase = random_seed
else
    phaseSeedBase = randomInteger(1, 1000000)
endif

overlapFrac  = 0.75
hopTime      = windowLength * (1 - overlapFrac)
nOlaFrames   = ceiling(sourceDur / hopTime) + 2
microFadeDur = 0.003

# Aliases used inside the procedure as outer-scope globals
daID = diffAmp
nFrm = nFrames
nBns = nBins
wSR  = workingSR
sT1  = specT1
sDt  = specDt
sF1  = specF1
sDf  = specDf
sFTop = specFTop

progressStep = max(1, round(nOlaFrames / 20))

procedure olaChannel: .outSnd, .normSnd, .extraScale, .chanSeedOff, .chanName$
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
            .fIdx = max(1, min(nFrm, round((.tIn - sT1) / sDt) + 1))

            # --- d) Build shaped complex matrix ---
            selectObject: .matCx
            Copy: "shaped_" + uid$
            .shapedMat = selected("Matrix")

            if create_stereo
                # === STEREO: Paulstretch stereo_phase_offset pattern ===
                # Precompute one random phase per FFT bin (column).
                # Both channels share the same base phase field for a frame.
                # The R call adds an independent phase-difference term scaled
                # by Stereo_phase_offset, so 0 is dual mono and 1 is widest.
                # Shared seeded base (identical across channels
                # for the same frame) + offset-scaled independent
                # component (channel-distinct seed). offset 0 = dual
                # mono; 1 = fully independent (the old sound).
                random_initializeWithSeedUnsafelyButPredictably: phaseSeedBase + .iframe
                selectObject: .matCx
                Copy: "phases_" + uid$
                .phasesMat = selected("Matrix")
                .pmID = .phasesMat
                selectObject: .phasesMat
                Formula: "if row = 1 then randomUniform(-pi, pi) else self fi"
                if .extraScale > 0
                    random_initializeWithSeedUnsafelyButPredictably: phaseSeedBase + .iframe + .chanSeedOff
                    Formula: "if row = 1 then self + randomUniform(-pi, pi) * .extraScale else self fi"
                endif

                # new_real = diffMag * cos(randPhase)
                # new_imag = diffMag * sin(randPhase)
                # DC (col=1) and Nyquist (col=.ncols) preserved.
                selectObject: .shapedMat
                Formula: "if col=1 or col=.ncols then self else if ((col-1)*wSR/2/(.ncols-1)) > sFTop + sDf/2 then 0 else if row=1 then object[daID,max(1,min(nBns,round((((col-1)*wSR/2/(.ncols-1))-sF1)/sDf)+1)),.fIdx]*cos(object[.pmID,1,col]) else object[daID,max(1,min(nBns,round((((col-1)*wSR/2/(.ncols-1))-sF1)/sDf)+1)),.fIdx]*sin(object[.pmID,1,col]) fi fi fi"

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
                Formula: "if col=1 or col=.ncols then self else if ((col-1)*wSR/2/(.ncols-1)) > sFTop + sDf/2 then 0 else if object[.magsID,1,col]>0 then object[.mcID,row,col]/object[.magsID,1,col]*object[daID,max(1,min(nBns,round((((col-1)*wSR/2/(.ncols-1))-sF1)/sDf)+1)),.fIdx] else 0 fi fi fi"

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
    @olaChannel: sound_wet_L, norm_L, 0, 0, "LEFT"
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
    @olaChannel: sound_wet_R, norm_R, stereo_phase_offset, 500009, "RIGHT"
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
    @olaChannel: sound_wet, norm_wet, 0, 0, "MONO"
    # Fix 4: normalise mono channel
    normWID = norm_wet
    selectObject: sound_wet
    Formula: "if object[normWID,1,col] > 0.001 then self / object[normWID,1,col] else 0 fi"
    removeObject: norm_wet
endif

removeObject: diffAmp
random_initializeSafelyAndUnpredictably()

# ============================================================
#  8.  WET / DRY MIX + FINALIZE
# ============================================================

wet      = wet_dry_mix
dry      = 1 - wet_dry_mix
outName$ = originalName$ + "_BeltramiInspired_" + preset_name$

if create_stereo
    # Joint wet scaling preserves the L/R relationship created by the phase
    # field. Independent peak normalization made random peak statistics alter
    # the stereo balance from run to run.
    selectObject: sound_wet_L
    wetPeakL = Get absolute extremum: 0, 0, "None"
    selectObject: sound_wet_R
    wetPeakR = Get absolute extremum: 0, 0, "None"
    wetPeakMax = max(wetPeakL, wetPeakR)
    if wetPeakMax > 1e-12
        wetJointScale = 0.99 / wetPeakMax
        selectObject: sound_wet_L
        Formula: "self * wetJointScale"
        selectObject: sound_wet_R
        Formula: "self * wetJointScale"
    endif
    wetLID = sound_wet_L
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
if outDur > sourceDur + 0.001
    currentName$ = selected$("Sound")
    Extract part: 0, sourceDur, "rectangular", 1, "no"
    trimmed = selected("Sound")
    Rename: currentName$
    removeObject: sound_out
    sound_out = trimmed
endif

# Final polish (works on mono and stereo alike). Keep fades proportional on
# short but valid sounds so their start/end coordinates never go negative.
selectObject: sound_out
finalFadeIn = min(0.01, sourceDur / 4)
finalFadeOut = min(0.02, sourceDur / 4)
if finalFadeIn > 0
    Fade in: 0, 0, finalFadeIn, "yes"
endif
if finalFadeOut > 0
    Fade out: 0, sourceDur-finalFadeOut, finalFadeOut, "yes"
endif
# Upsample back to original SR if needed. Final peak normalization is done
# after this step because band-limited resampling can create inter-sample/sample
# overshoot relative to the low-rate render.

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

# Final output ceiling after all processing, fades, and resampling.
selectObject: sound_out
Scale peak: 0.95

# ============================================================
#  9.  VISUALIZATION
# ============================================================

processingTime = stopwatch - startTime

if draw_visualization
    # ------------------------------------------------------------
    # Measurements used by the figure. The visualization reads the
    # actual process matrices saved above; it never feeds the audio path.
    # ------------------------------------------------------------
    origTerrainID = terrainOriginal
    diffTerrainID = terrainDiffused
    targetTerrainID = terrainTarget

    selectObject: terrainOriginal
    terrainHi0 = Get maximum
    selectObject: terrainDiffused
    terrainHi1 = Get maximum
    selectObject: terrainTarget
    terrainHi2 = Get maximum
    terrainHi = max(terrainHi0, max(terrainHi1, terrainHi2))
    terrainLo = dynFloor
    if terrainHi <= terrainLo + 1
        terrainHi = terrainLo + 1
    endif

    # Find the frame where the final target terrain differs most from the
    # source terrain (mean absolute dB difference across frequency).
    changeMat = Create Matrix: "terrain_change_" + uid$,
        ... 1, nFrames, nFrames, 1, 1,
        ... 1, 1, 1, 1, 1, "0"
    for bin from 1 to nBins
        selectObject: changeMat
        Formula: "self + abs(object[" + string$(targetTerrainID) + "," + string$(bin) + ",col] - object[" + string$(origTerrainID) + "," + string$(bin) + ",col])"
    endfor
    selectObject: changeMat
    Formula: "self / nBins"
    changeFrame = 1
    changeScore = -1
    for frm from 1 to nFrames
        selectObject: changeMat
        vChange = Get value in cell: 1, frm
        if vChange > changeScore
            changeScore = vChange
            changeFrame = frm
        endif
    endfor
    removeObject: changeMat
    changeTime = specT1 + (changeFrame - 1) * specDt

    # Find the frequency with the largest source -> target dB change in
    # that measured frame. This is printed under Panel C so the panel states
    # the transformation it was drawn to show.
    maxDeltaDb = -1
    maxDeltaHz = specF1
    maxDeltaOrig = 0
    maxDeltaTarget = 0
    for bin from 1 to nBins
        selectObject: terrainOriginal
        oDb = Get value in cell: bin, changeFrame
        selectObject: terrainTarget
        tDb = Get value in cell: bin, changeFrame
        dDb = abs(tDb - oDb)
        if dDb > maxDeltaDb
            maxDeltaDb = dDb
            maxDeltaHz = specF1 + (bin - 1) * specDf
            maxDeltaOrig = oDb
            maxDeltaTarget = tDb
        endif
    endfor

    # Final output channels and common amplitude scale.
    selectObject: sound_out
    nChOut = Get number of channels
    if nChOut > 1
        vizOutL = Extract one channel: 1
        Rename: "viz_out_L_" + uid$
        selectObject: sound_out
        vizOutR = Extract one channel: 2
        Rename: "viz_out_R_" + uid$
    else
        selectObject: sound_out
        vizOutL = Copy: "viz_out_mono_" + uid$
        vizOutR = 0
    endif
    selectObject: vizOutL
    peakOutL = Get absolute extremum: 0, 0, "None"
    rmsOutL = Get root-mean-square: 0, 0
    if nChOut > 1
        selectObject: vizOutR
        peakOutR = Get absolute extremum: 0, 0, "None"
        rmsOutR = Get root-mean-square: 0, 0
    else
        peakOutR = peakOutL
        rmsOutR = rmsOutL
    endif
    vizPeak = max(peakOutL, peakOutR)
    if vizPeak < 1e-9
        vizPeak = 1
    else
        vizPeak = 1.05 * vizPeak
    endif

    # Manual frequency tick spacing for readable 2.0k / 4.0k labels.
    if specFTop <= 5000
        freqTick = 1000
    elsif specFTop <= 10000
        freqTick = 2000
    else
        freqTick = 4000
    endif

    Erase all

    # ---------------- Header ----------------
    Select outer viewport: 0, 8, 0, 0.38
    Select inner viewport: 0, 8, 0, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half",
        ... "Beltrami-Inspired Spectral Melter v2.5.2 — " + preset_name$

    # How much of the resynthesis target has been pushed to the dynamic floor.
    # At high effect_strength the contrast expansion is close to binarising the
    # spectrum, and the third terrain then reads as speckle. That is the effect
    # working, not the picture failing, so the figure states the number.
    selectObject: terrainTarget
    floorProbe = Copy: "floor_probe_" + uid$
    Formula: "if self <= " + fixed$(terrainLo + 1, 4) + " then 1 else 0 fi"
    floorSum = Get sum
    nRowT = Get number of rows
    nColT = Get number of columns
    removeObject: floorProbe
    if nRowT * nColT > 0
        floorFrac = 100 * floorSum / (nRowT * nColT)
    else
        floorFrac = 0
    endif

    Select outer viewport: 0, 8, 0.39, 0.70
    Select inner viewport: 0, 8, 0.39, 0.62
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34, 0.34, 0.42}"
    process$ = "Sound -> Gaussian spectrogram -> log-energy terrain -> edge-aware diffusion -> contrast expansion -> phase resynthesis -> OLA -> wet/dry"
    Text: 0.5, "centre", 0.5, "half", process$

    Select inner viewport: 0, 8, 0.62, 0.76
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34, 0.34, 0.42}"
    if create_stereo
        Text: 0.5, "centre", 0.5, "half",
            ... "stereo phase law: phi_L=phi0 ; phi_R=phi0 + U(-pi*offset, +pi*offset)  |  offset=" + fixed$(stereo_phase_offset, 2)
    else
        Text: 0.5, "centre", 0.5, "half", "mono resynthesis preserves source-frame phase"
    endif

    procedure beltStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    # ---------------- A title ----------------
    Select outer viewport: 0, 8, 0.80, 1.00
    Select inner viewport: 0, 8, 0.80, 1.00
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  Spectral terrain: source -> diffusion -> actual resynthesis target"

    # Three process-state terrains with one shared dB scale.
    # A1 source
    Select outer viewport: 0, 2.67, 1.00, 2.48
    Select inner viewport: 0.48, 2.55, 1.10, 2.20
    selectObject: terrainOriginal
    Paint cells: 0, 0, 0, max_frequency_Hz, terrainLo, terrainHi
    Select inner viewport: 0.48, 2.55, 1.10, 2.20
    Axes: 0, sourceDur, 0, max_frequency_Hz
    Colour: "Black"
    Draw inner box
    Font size: 5
    @beltStep: sourceDur, 4
    Marks bottom every: 1, beltStep.step, "yes", "yes", "no"
    Font size: 5
    nFTicks = floor(max_frequency_Hz / freqTick)
    for q from 0 to nFTicks
        fMark = q * freqTick
        if fMark >= 1000
            fLab$ = fixed$(fMark/1000, 1) + "k"
        else
            fLab$ = fixed$(fMark, 0)
        endif
        One mark left: fMark, "no", "yes", "no", fLab$
    endfor

    # A2 diffused
    Select outer viewport: 2.67, 5.34, 1.00, 2.48
    Select inner viewport: 2.80, 5.22, 1.10, 2.20
    selectObject: terrainDiffused
    Paint cells: 0, 0, 0, max_frequency_Hz, terrainLo, terrainHi
    Select inner viewport: 2.80, 5.22, 1.10, 2.20
    Axes: 0, sourceDur, 0, max_frequency_Hz
    Colour: "Black"
    Draw inner box
    Font size: 5
    @beltStep: sourceDur, 4
    Marks bottom every: 1, beltStep.step, "yes", "yes", "no"

    # A3 target after contrast expansion / positivity clamp
    Select outer viewport: 5.34, 8, 1.00, 2.48
    Select inner viewport: 5.47, 7.86, 1.10, 2.20
    selectObject: terrainTarget
    Paint cells: 0, 0, 0, max_frequency_Hz, terrainLo, terrainHi
    Select inner viewport: 5.47, 7.86, 1.10, 2.20
    Axes: 0, sourceDur, 0, max_frequency_Hz
    Colour: "Black"
    Draw inner box
    Font size: 5
    @beltStep: sourceDur, 4
    Marks bottom every: 1, beltStep.step, "yes", "yes", "no"

    # Labels are in a separate strip so Paint cells / boxes cannot disturb them.
    Select outer viewport: 0, 8, 2.48, 2.68
    Select inner viewport: 0, 8, 2.48, 2.68
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.34}"
    Text: 0.17, "centre", 0.72, "half", "SOURCE log energy"
    Text: 0.50, "centre", 0.72, "half", "DIFFUSED log energy"
    Text: 0.83, "centre", 0.72, "half", "TARGET dB (after strength x"
        ... + fixed$(effect_strength, 1) + ")"
    Text: 0.5, "centre", 0.14, "half",
        ... "one dB scale " + fixed$(terrainLo,0) + ".." + fixed$(terrainHi,0)
        ... + " for all three  |  time in seconds  |  frequency 0.."
        ... + fixed$(max_frequency_Hz/1000,1) + "k Hz, marks at left"
        ... + "  |  contrast expansion puts " + fixed$(floorFrac, 0)
        ... + "\%  of the target at the floor"

    # ---------------- B title ----------------
    Select outer viewport: 0, 8, 2.74, 2.94
    Select inner viewport: 0, 8, 2.74, 2.94
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  Edge-aware diffusion law and finite-difference flow"

    # B-left: conductance law c(g)=exp(-(g/kappa)^2)
    Select outer viewport: 0, 4.10, 2.96, 4.02
    Select inner viewport: 0.58, 3.92, 3.04, 3.76
    gMaxPlot = max(3*kappa_eff, min(gradMax0, 6*kappa_eff))
    if gMaxPlot <= 0
        gMaxPlot = 1
    endif
    Axes: 0, gMaxPlot, 0, 1.05
    Paint rectangle: "{0.975,0.975,0.978}", 0, gMaxPlot, 0, 1.05
    Colour: "{0.25,0.48,0.78}"
    Line width: 2
    nCurve = 160
    for q from 1 to nCurve
        g0 = gMaxPlot * (q-1)/nCurve
        g1 = gMaxPlot * q/nCurve
        c0 = exp(-(g0/kappa_eff)^2)
        c1 = exp(-(g1/kappa_eff)^2)
        Draw line: g0, c0, g1, c1
    endfor
    Line width: 1
    Dashed line
    Colour: "{0.75,0.30,0.25}"
    if kappa_eff <= gMaxPlot
        Draw line: kappa_eff, 0, kappa_eff, 1.0
    endif
    Colour: "{0.25,0.60,0.38}"
    if gradMean0 <= gMaxPlot
        Draw line: gradMean0, 0, gradMean0, 1.0
    endif
    Solid line
    Select inner viewport: 0.58, 3.92, 3.04, 3.76
    Axes: 0, gMaxPlot, 0, 1.05
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, 0.25, "yes", "yes", "no"
    @beltStep: gMaxPlot, 5
    Marks bottom every: 1, beltStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "conductance c(g)"
    Font size: 5
    Colour: "{0.75,0.30,0.25}"
    Text: min(kappa_eff,0.96*gMaxPlot), "centre", 0.12, "half", "kappa"
    Colour: "{0.25,0.60,0.38}"
    if gradMean0 <= gMaxPlot
        Text: gradMean0, "centre", 0.92, "half", "mean g"
    endif

    # B-right: stencil that directly embodies the update law.
    Select outer viewport: 4.10, 8, 2.96, 4.02
    Select inner viewport: 4.35, 7.78, 3.04, 3.76
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975,0.975,0.978}", 0, 1, 0, 1
    Colour: "{0.86,0.86,0.88}"
    Line width: 1
    Draw line: 0.50,0.50,0.20,0.50
    Draw line: 0.50,0.50,0.80,0.50
    Draw line: 0.50,0.50,0.50,0.18
    Draw line: 0.50,0.50,0.50,0.82
    Colour: "{0.25,0.48,0.78}"
    Paint circle (mm): "{0.25,0.48,0.78}", 0.50,0.50, 2.0
    # Paint circle disturbs the frame: restore before labels.
    Select inner viewport: 4.35, 7.78, 3.04, 3.76
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "Black"
    Text: 0.50,"centre",0.50,"half","E"
    Text: 0.18,"centre",0.50,"half","t-"
    Text: 0.82,"centre",0.50,"half","t+"
    Text: 0.50,"centre",0.15,"half","f-"
    Text: 0.50,"centre",0.85,"half","f+"
    Font size: 5
    Colour: "{0.32,0.32,0.38}"
    Text: 0.50,"centre",0.67,"half","dt_f * c(g) * DeltaE"
    Text: 0.50,"centre",0.33,"half","dt_f * c(g) * DeltaE"
    Text: 0.31,"centre",0.57,"half","dt_t"
    Text: 0.69,"centre",0.57,"half","dt_t"
    Colour: "Black"
    Draw rectangle: 0,1,0,1

    Select outer viewport: 0, 8, 4.02, 4.20
    Select inner viewport: 0, 8, 4.02, 4.20
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.25,"centre",0.5,"half","g in dB per cell | c(g)=exp(-(g/kappa)^2) | kappa=" + fixed$(kappa_eff,2) + " | initial mean g=" + fixed$(gradMean0,2)
    Text: 0.75,"centre",0.5,"half","E_next = E + time-flow + frequency-flow | dt_t=" + fixed$(dt_t,2) + " | dt_f=" + fixed$(dt_f,2)

    # ---------------- C title ----------------
    Select outer viewport: 0, 8, 4.26, 4.46
    Select inner viewport: 0, 8, 4.26, 4.46
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  Measured spectral slice at the frame of greatest terrain change"

    # C data: original / diffused / target dB at one actual Matrix frame.
    Select outer viewport: 0, 8, 4.48, 5.54
    Select inner viewport: 0.68, 7.72, 4.56, 5.28
    Axes: 0, specFTop, terrainLo, terrainHi
    Paint rectangle: "{0.975,0.975,0.978}", 0, specFTop, terrainLo, terrainHi
    for bin from 1 to nBins - 1
        f0 = specF1 + (bin - 1) * specDf
        f1 = specF1 + bin * specDf
        selectObject: terrainOriginal
        o0 = Get value in cell: bin, changeFrame
        o1 = Get value in cell: bin+1, changeFrame
        selectObject: terrainDiffused
        d0 = Get value in cell: bin, changeFrame
        d1 = Get value in cell: bin+1, changeFrame
        selectObject: terrainTarget
        t0 = Get value in cell: bin, changeFrame
        t1 = Get value in cell: bin+1, changeFrame
        Colour: "{0.58,0.58,0.60}"
        Line width: 1
        Draw line: f0,o0,f1,o1
        Colour: "{0.25,0.50,0.80}"
        Draw line: f0,d0,f1,d1
        Colour: "{0.80,0.38,0.24}"
        Line width: 1.5
        Draw line: f0,t0,f1,t1
    endfor
    Line width: 1
    Select inner viewport: 0.68, 7.72, 4.56, 5.28
    Axes: 0, specFTop, terrainLo, terrainHi
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, 20, "yes", "yes", "no"
    nFTicksC = floor(specFTop / freqTick)
    for q from 0 to nFTicksC
        fMark = q * freqTick
        if fMark >= 1000
            fLab$ = fixed$(fMark/1000,1) + "k"
        else
            fLab$ = fixed$(fMark,0)
        endif
        One mark bottom: fMark, "no", "yes", "no", fLab$
    endfor
    Font size: 6
    Text left: "yes", "dB"
    Font size: 5
    Colour: "{0.58,0.58,0.60}"
    Text: 0.02*specFTop,"left",terrainHi-0.08*(terrainHi-terrainLo),"half","gray source"
    Colour: "{0.25,0.50,0.80}"
    Text: 0.26*specFTop,"left",terrainHi-0.08*(terrainHi-terrainLo),"half","blue diffused"
    Colour: "{0.80,0.38,0.24}"
    Text: 0.52*specFTop,"left",terrainHi-0.08*(terrainHi-terrainLo),"half","orange target"

    Select outer viewport: 0, 8, 5.54, 5.74
    Select inner viewport: 0, 8, 5.54, 5.74
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5,"centre",0.5,"half",
        ... "the orange target sits ON the floor wherever the expansion annihilated it  |  "
        ... + "frame t=" + fixed$(changeTime,3) + " s | largest source->target change at "
        ... + fixed$(maxDeltaHz/1000,2) + "k Hz: " + fixed$(maxDeltaOrig,1) + " -> " + fixed$(maxDeltaTarget,1)
        ... + " dB (|Delta|=" + fixed$(maxDeltaDb,1) + " dB)"

    # ---------------- D title ----------------
    Select outer viewport: 0, 8, 5.80, 6.00
    Select inner viewport: 0, 8, 5.80, 6.00
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","D  Measured final output (shared amplitude scale)"

    if nChOut > 1
        # L
        Select outer viewport: 0, 8, 6.02, 6.42
        Select inner viewport: 0.66, 7.72, 6.05, 6.38
        selectObject: vizOutL
        Colour: "{0.25,0.50,0.80}"
        Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
        Select inner viewport: 0.66, 7.72, 6.05, 6.38
        Axes: 0, sourceDur, -vizPeak, vizPeak
        Colour: "Black"
        Draw inner box
        Font size: 5
        @beltStep: vizPeak, 2
        Marks left every: 1, beltStep.step, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "L"
        # R
        Select outer viewport: 0, 8, 6.42, 6.82
        Select inner viewport: 0.66, 7.72, 6.45, 6.78
        selectObject: vizOutR
        Colour: "{0.80,0.42,0.24}"
        Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
        Select inner viewport: 0.66, 7.72, 6.45, 6.78
        Axes: 0, sourceDur, -vizPeak, vizPeak
        Colour: "Black"
        Draw inner box
        Font size: 5
        @beltStep: vizPeak, 2
        Marks left every: 1, beltStep.step, "yes", "yes", "no"
        @beltStep: sourceDur, 6
        Marks bottom every: 1, beltStep.step, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "R"
        Text bottom: "yes", "time (s)"
    else
        Select outer viewport: 0, 8, 6.02, 6.82
        Select inner viewport: 0.66, 7.72, 6.08, 6.76
        selectObject: vizOutL
        Colour: "{0.25,0.50,0.80}"
        Draw: 0, 0, -vizPeak, vizPeak, "no", "Curve"
        Select inner viewport: 0.66, 7.72, 6.08, 6.76
        Axes: 0, sourceDur, -vizPeak, vizPeak
        Colour: "Black"
        Draw inner box
        Font size: 5
        @beltStep: vizPeak, 2
        Marks left every: 1, beltStep.step, "yes", "yes", "no"
        @beltStep: sourceDur, 6
        Marks bottom every: 1, beltStep.step, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "mono"
        Text bottom: "yes", "time (s)"
    endif

    # ---------------- QC strip ----------------
    Select outer viewport: 0, 8, 6.88, 7.52
    Select inner viewport: 0.15, 7.85, 6.91, 7.49
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.965,0.965,0.97}", 0,3,0,2
    Colour: "{0.82,0.82,0.84}"
    Draw line: 1,0,1,2
    Draw line: 2,0,2,2
    Draw line: 0,1,3,1
    Colour: "Black"
    Draw rectangle: 0,3,0,2
    Font size: 5.5
    Text: 0.05,"left",1.55,"half","grid: dt=" + fixed$(specDt*1000,1) + " ms | df=" + fixed$(specDf,1) + " Hz"
    Text: 1.05,"left",1.55,"half","diffusion: k=" + fixed$(kappa_eff,2) + " | " + string$(iterations) + " iter | " + condStr$
    Text: 2.05,"left",1.55,"half","gradient: mean " + fixed$(gradMean0,2) + " | max " + fixed$(gradMax0,2)
    Text: 0.05,"left",0.55,"half","strength " + fixed$(efStr,1) + " | wet " + fixed$(wet,2) + " | " + speedStr$
    if create_stereo
        seedStr$ = if random_seed > 0 then string$(random_seed) else "random" fi
        Text: 1.05,"left",0.55,"half","stereo offset " + fixed$(stereo_phase_offset,2) + " | seed " + seedStr$
        Text: 2.05,"left",0.55,"half","peak L/R " + fixed$(peakOutL,3) + "/" + fixed$(peakOutR,3) + " | RMS " + fixed$(rmsOutL,3) + "/" + fixed$(rmsOutR,3)
    else
        Text: 1.05,"left",0.55,"half","mono phase-preserving resynthesis"
        Text: 2.05,"left",0.55,"half","peak " + fixed$(peakOutL,3) + " | RMS " + fixed$(rmsOutL,3) + " | render " + fixed$(processingTime,1) + " s"
    endif

    # Viz-only objects.
    if nChOut > 1
        removeObject: vizOutL, vizOutR
    else
        removeObject: vizOutL
    endif
    removeObject: terrainOriginal, terrainDiffused, terrainTarget
endif

# ============================================================
#  10.  CLEANUP
# ============================================================

removeObject: source

selectObject: sound_out

appendInfoLine: ""
appendInfoLine: "==========================================="
appendInfoLine: " BELTRAMI INSPIRED SPECTRAL MELTER v2.5.2 — Done"
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
