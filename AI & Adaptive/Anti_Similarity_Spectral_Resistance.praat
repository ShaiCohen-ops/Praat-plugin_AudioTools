# ============================================================
# Praat AudioTools - Anti_Similarity_Spectral_Resistance.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Anti-Similarity — Spectral Resistance Engine (AI category).
#   Pure Praat; offline; no external programs.
#
#   The more spectrally stable a region is, the more strongly the engine
#   intervenes; where the spectrum changes, it steps back.
#
#   1. ANALYSIS (once, on the mono sum, shared by all channels so the
#      stereo image is preserved). Spectrogram (Gaussian window; Praat's
#      physical window is twice the nominal length) -> Matrix of POWER
#      spectral density P(f,t) (quadratic, not amplitude). Frame-to-frame
#      distance D(t), selectable:
#        Log-spectral   P pooled into 1/6-octave bands, floored 20 dB
#                       below the frame's mean band power, 10 log10; RMS
#                       over bands of the change, with the frame's mean
#                       log level removed (loudness alone does not count
#                       as change)                           [dB]
#        Euclidean      || a_t - a_{t-1} || with a = sqrt(P) scaled to unit
#                       L2 norm per frame                    [0 .. 1.41]
#        Spectral flux  sum of max(0, a_t - a_{t-1}) with a = sqrt(P)
#                       scaled to unit L1 norm per frame     [0 .. 1]
#      Silence: frames more than "Silence threshold" below the loudest
#      frame are silent; a distance touching a silent frame is not used,
#      and silence never counts as stability (control 0).
#   2. CONTROL. Robust normalisation by the 10th / 90th percentile of the
#      valid distances: dn = clip((D - q10)/(q90 - q10)); stability
#      s = 1 - dn. If q90 - q10 is negligible (nearly constant curve), an
#      absolute scale is used instead (4 dB / 0.4 / 0.2) and reported.
#      u = clip(sensitivity x (s - threshold) / (1 - threshold));
#      contrast: c = u^g / (u^g + (1-u)^g) (g = 1 linear, > 1 more decisive);
#      persistence: a build-up memory that rises slowly in stable regions;
#      output = min (instant control, build-up), so transients release at
#      once; optional release time keeps the build-up across short
#      interruptions; symmetric moving-average smoothing.
#      c (0..1) x Effect intensity drives every stage, at audio rate.
#   3. TRANSFORMATION (modes):
#      A Stability-weighted spectral carving
#                              the spectrum that persists in stable regions
#                              (stability-weighted, level-normalised long-
#                              term spectrum, relative to its own 1/3-octave
#                              average) is carved away: a zero-phase filter
#                              cuts what stands out and lifts what is
#                              missing; output = crossfade dry -> carved by
#                              c(t). ONE static filter for the whole file:
#                              only its amount varies in time; it is not
#                              re-derived from the spectrum at each moment.
#      B Temporal fragmentation  windowed overlap-add grain engine (hop =
#                              crossfade, grain = 2 hops, sin^2/cos^2
#                              windows that sum exactly to 1). In stable
#                              regions the read pointer loops a just-played
#                              fragment (length shrinks as stability grows),
#                              optionally backwards, then returns to the
#                              present; an optional bounded, causal memory
#                              stream mixes in material up to "Temporal
#                              displacement" earlier. Duration is preserved.
#                              With c = 0 the engine reproduces the input
#                              exactly.
#      C Spectral instability  six complementary bands (Hann band filters
#                              from one spectrum per channel; they sum back
#                              to the input exactly) receive slow, seeded,
#                              independent gain drifts whose depth follows
#                              c(t); per-frame power normalisation. No noise
#                              is added. This is time-varying band
#                              weighting, not a phase-vocoder freeze.
#      D Hybrid resistance     B, then A, then C, all driven by the same c.
#   4. Dry/wet mix, peak protection (never normalisation upwards; rare
#      isolated overs get a soft knee above 0.9 instead). The
#      engine keeps level by construction (B: windows sum to 1; A: moment-
#      by-moment make-up gain; C: per-frame power normalisation); no
#      final loudness matching is applied. The RMS change is reported.
#
# Changelog v1.3 (review fixes):
#   - Peak protection ceiling = max (0.999, source peak): a result no
#     hotter than its input is never touched, so wet/dry 0 % and
#     intensity 0 return the source exactly even if it peaks above 0.999.
#   - Reports how much the sound actually changed: RMS of (output -
#     input) relative to the input, overall and where the control is
#     above 0.5, next to the control statistics.
#   - Memory stream diagnostics: planned fragments vs the share of time
#     the memory is mixed in audibly (gain >= 0.25), and its mean share.
#   - Summary panel: stage notes on two lines (no truncation in mode D).
#   - Soft-knee report counts both the overs that triggered it and the
#     samples it actually reshapes (everything above 0.9 x ceiling).
# Changelog v1.2 (real-recording fixes; found on a sung voice clip):
#   - BUG: the q10 / q90 normalisation passed an UNSORTED vector to
#     Praat's quantile (), which expects sorted data, so the range was
#     two arbitrary order statistics. On real recordings this collapsed
#     the control to ~0 for every preset (mean 0.0002-0.006 on a 5 s sung
#     clip; Radical Difference made 1 loop). Now sorted first.
#   - Log-spectral distance on 1/6-octave bands with a floor 20 dB below
#     the frame's mean band power (was: per FFT bin, absolute floor).
#     Per-bin log values on real recordings are dominated by low-level
#     bins (noise, codec holes, gaps between harmonics) that jitter every
#     frame; a held vowel scored nearly as "changing" as a consonant. Now
#     vowels read stable and consonants read as change.
#   - Persistence is a build-up memory: output = min (instant control,
#     build-up), so transients still release at once; new "Persistence
#     release (ms)" lets the build-up survive short interruptions instead
#     of being reset (0 = previous behaviour). Anti-Drone: persistence
#     1.0 s (was 1.5), release 150 ms.
#   - Low-intervention diagnostic in the Info window and the figure when
#     the mean control is below 0.05.
#   - Peak protection: rare isolated overs (< 0.1 % of samples, < +6 dB)
#     get a soft knee above 0.9 on those samples only, instead of turning
#     the whole result down; otherwise global attenuation as before.
# Changelog v1.1 (review fixes):
#   - Mode A renamed "Stability-weighted spectral carving" and documented
#     as what it is: ONE static filter whose amount follows c(t).
#   - Mode A level: the carved signal is level-matched to its input moment
#     by moment (ratio of 20 Hz power envelopes, one gain for both
#     channels, clipped to +-12 dB) instead of by global RMS. Stable
#     regions lost up to 7 dB in v1.0; now within about 1 dB.
#   - Bin pooling no longer builds an nbP x nb aggregator matrix (could
#     reach gigabytes at high sample rates / long windows); rows are
#     summed in place, one offset per pass.
#   - New analysis-grid guard, predicted before the Spectrogram is made
#     (FFT bin size and Praat's minimum time step included); refuses
#     grids above 25 million cells with advice.
#   - Grain engine: explicit read-range check of every grain (main and
#     memory stream, both span ends) before rendering; a violation is an
#     error, never a silent zero read.
#   - Seeding written in function form, random_initialize...(seed).
#   - Summary reports the output RMS change against the input.
#   - Grain formula: the memory read is inside an explicit branch, so
#     grains without memory never evaluate it.
# Changelog v1.0:
#   - First release.
#
# Requires: Praat 6.3+ (vector/matrix functions). Nothing else.
# ============================================================

version$ = "1.3"

# ---- INPUT ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound."
endif
srcOrig = selected ("Sound")
srcName$ = selected$ ("Sound")

# ============================================================
# FORM (short; details in the dialogs that follow)
# ============================================================
form: "Anti-Similarity — Spectral Resistance v1.3"
    optionmenu: "Preset", 1
        option: "Fragile Continuity"
        option: "Stasis Fracture"
        option: "Spectral Rebellion"
        option: "Memory Corruption"
        option: "Anti-Drone"
        option: "Radical Difference"
        option: "Custom"
    optionmenu: "Processing mode", 1
        option: "From preset"
        option: "A  Stability-weighted spectral carving"
        option: "B  Temporal fragmentation"
        option: "C  Spectral instability"
        option: "D  Hybrid resistance"
    real: "Effect intensity (%)", "100"
    real: "Wet dry mix (%)", "100"
    integer: "Random seed", "1"
    boolean: "Show details", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

# ============================================================
# PRESETS — each sets every processing parameter
# ============================================================
procedure applyPreset: .p
    # shared defaults
    winMs = 30
    stepMs = 10
    maxFreq = 5000
    freqStep = 20
    metric = 1
    sensitivity = 1.0
    contrast = 1.5
    smoothMs = 150
    persistS = 0
    releaseMs = 0
    silenceDb = -50
    threshold = 0.3
    fragMinMs = 40
    fragMaxMs = 200
    repStrength = 0
    displaceMs = 0
    interference = 0
    reverseProb = 0
    xfadeMs = 8
    resDepth = 0
    instDepth = 0
    instRate = 0.7
    if .p = 1
        # Fragile Continuity: gentle drifting band balance on sustained material
        presetMode = 3
        instDepth = 5
        instRate = 0.4
        threshold = 0.35
        contrast = 1.0
        smoothMs = 300
    elsif .p = 2
        # Stasis Fracture: stable regions break into short loops
        presetMode = 2
        repStrength = 0.9
        fragMinMs = 18
        fragMaxMs = 110
        reverseProb = 0.25
        xfadeMs = 5
        threshold = 0.35
        contrast = 2.0
        smoothMs = 80
    elsif .p = 3
        # Spectral Rebellion: carving + strong timbral drift, light fracture
        presetMode = 4
        resDepth = 24
        instDepth = 10
        instRate = 1.8
        repStrength = 0.2
        fragMinMs = 30
        fragMaxMs = 90
        threshold = 0.25
        contrast = 1.5
    elsif .p = 4
        # Memory Corruption: earlier moments (<= 1.5 s back) leak into the present
        presetMode = 2
        displaceMs = 1500
        interference = 0.75
        repStrength = 0.3
        fragMinMs = 80
        fragMaxMs = 400
        xfadeMs = 12
        threshold = 0.25
        contrast = 1.2
        smoothMs = 250
    elsif .p = 5
        # Anti-Drone: intervention builds up the longer a region stays
        # stable (persistence), transients release it at once
        presetMode = 4
        threshold = 0.4
        sensitivity = 1.5
        contrast = 2.5
        persistS = 1.0
        releaseMs = 150
        smoothMs = 300
        resDepth = 24
        instDepth = 8
        instRate = 0.5
        repStrength = 0.5
        fragMinMs = 150
        fragMaxMs = 500
        xfadeMs = 15
    elsif .p = 6
        # Radical Difference: everything, decisively
        presetMode = 4
        threshold = 0.1
        sensitivity = 2.0
        contrast = 0.7
        smoothMs = 60
        repStrength = 1.0
        fragMinMs = 10
        fragMaxMs = 60
        displaceMs = 800
        interference = 0.5
        reverseProb = 0.5
        xfadeMs = 4
        resDepth = 24
        instDepth = 12
        instRate = 3.0
    else
        # Custom starts from a hybrid with moderate settings
        presetMode = 4
        resDepth = 12
        instDepth = 6
        repStrength = 0.5
        displaceMs = 400
        interference = 0.3
        reverseProb = 0.2
    endif
endproc

@applyPreset: preset
presetName$ = preset$
mode = presetMode
if processing_mode > 1
    mode = processing_mode - 1
endif
intens = effect_intensity / 100
mix = wet_dry_mix / 100
seed = random_seed

# ============================================================
# DETAIL DIALOGS (pre-filled with the preset; Custom forces them open)
# ============================================================
if show_details or preset = 7
    beginPause: "Anti-Similarity — analysis and adaptive behaviour"
        comment: "Spectral analysis"
        positive: "Analysis window (ms)", string$ (winMs)
        positive: "Analysis step (ms)", string$ (stepMs)
        positive: "Maximum frequency (Hz)", string$ (maxFreq)
        positive: "Frequency step (Hz)", string$ (freqStep)
        optionMenu: "Distance method", metric
            option: "Log-spectral difference"
            option: "Normalized Euclidean"
            option: "Spectral flux"
        comment: "Adaptive behaviour"
        positive: "Stability sensitivity", string$ (sensitivity)
        real: "Stability threshold (0-1)", string$ (threshold)
        positive: "Response contrast", string$ (contrast)
        real: "Control smoothing (ms)", string$ (smoothMs)
        real: "Persistence build up (s)", string$ (persistS)
        real: "Persistence release (ms)", string$ (releaseMs)
        real: "Silence threshold (dB)", string$ (silenceDb)
    endPause: "Continue", 1
    winMs = analysis_window
    stepMs = analysis_step
    maxFreq = maximum_frequency
    freqStep = frequency_step
    metric = distance_method
    sensitivity = stability_sensitivity
    threshold = stability_threshold
    contrast = response_contrast
    smoothMs = control_smoothing
    persistS = persistence_build_up
    releaseMs = persistence_release
    silenceDb = silence_threshold
    beginPause: "Anti-Similarity — temporal and spectral processing"
        comment: "Temporal (modes B, D)"
        positive: "Minimum fragment (ms)", string$ (fragMinMs)
        positive: "Maximum fragment (ms)", string$ (fragMaxMs)
        real: "Fragment repetition (0-1)", string$ (repStrength)
        real: "Reverse probability (0-1)", string$ (reverseProb)
        real: "Temporal displacement (ms)", string$ (displaceMs)
        real: "Memory interference (0-1)", string$ (interference)
        positive: "Crossfade (ms)", string$ (xfadeMs)
        comment: "Spectral (A: carving; C: instability; D: both)"
        real: "Carving depth (dB)", string$ (resDepth)
        real: "Instability depth (dB)", string$ (instDepth)
        positive: "Instability rate (Hz)", string$ (instRate)
    endPause: "Continue", 1
    fragMinMs = minimum_fragment
    fragMaxMs = maximum_fragment
    repStrength = fragment_repetition
    reverseProb = reverse_probability
    displaceMs = temporal_displacement
    interference = memory_interference
    xfadeMs = crossfade
    resDepth = carving_depth
    instDepth = instability_depth
    instRate = instability_rate
endif
# ---- end of detail dialogs ----

# ============================================================
# VALIDATION
# ============================================================
selectObject: srcOrig
fs = Get sampling frequency
nCh = Get number of channels
dur = Get total duration
srcStart = Get start time
nS = Get number of samples
srcRms = Get root-mean-square: 0, 0
srcPeak = Get absolute extremum: 0, 0, "None"
nyq = fs / 2
if nCh > 2
    exitScript: "Only mono and stereo Sounds are supported (this one has " + string$ (nCh) + " channels)."
endif
if srcRms = undefined or srcRms < 1e-9
    exitScript: "The Sound is silent: there is no spectrum to resist."
endif
if effect_intensity < 0 or effect_intensity > 200
    exitScript: "Effect intensity must be between 0 and 200 %."
endif
if wet_dry_mix < 0 or wet_dry_mix > 100
    exitScript: "Wet dry mix must be between 0 and 100 %."
endif
if winMs < 5 or winMs > 200 or stepMs < 2 or stepMs > 100
    exitScript: "Analysis window must be 5-200 ms and analysis step 2-100 ms."
endif
if stepMs > winMs
    exitScript: "The analysis step must not be longer than the analysis window."
endif
if maxFreq < 500
    exitScript: "Maximum frequency must be at least 500 Hz."
endif
maxFreqUsed = min (maxFreq, 0.95 * nyq)
if dur < max (0.25, 4 * winMs / 1000)
    exitScript: "The Sound is too short (" + fixed$ (dur, 3) + " s); it needs at least " + fixed$ (max (0.25, 4 * winMs / 1000), 2) + " s for a meaningful stability curve."
endif
if threshold < 0 or threshold >= 1
    exitScript: "Stability threshold must be in 0 .. 0.99."
endif
if sensitivity < 0.1 or sensitivity > 10 or contrast < 0.2 or contrast > 10
    exitScript: "Stability sensitivity must be 0.1-10 and response contrast 0.2-10."
endif
if smoothMs < 0 or smoothMs > 5000 or persistS < 0 or persistS > 30 or releaseMs < 0 or releaseMs > 5000
    exitScript: "Control smoothing must be 0-5000 ms, persistence 0-30 s and persistence release 0-5000 ms."
endif
if silenceDb > -10 or silenceDb < -120
    exitScript: "Silence threshold must be between -120 and -10 dB (relative to the loudest frame)."
endif
if fragMinMs < 2 or fragMaxMs < fragMinMs or fragMaxMs > 4000
    exitScript: "Fragments: 2 ms <= minimum <= maximum <= 4000 ms."
endif
if repStrength < 0 or repStrength > 1 or reverseProb < 0 or reverseProb > 1 or interference < 0 or interference > 1
    exitScript: "Repetition, reverse probability and memory interference must be in 0 .. 1."
endif
if displaceMs < 0 or displaceMs > 10000
    exitScript: "Temporal displacement must be 0-10000 ms."
endif
if xfadeMs < 1 or xfadeMs > 100
    exitScript: "Crossfade must be 1-100 ms."
endif
if resDepth < 0 or resDepth > 40 or instDepth < 0 or instDepth > 24
    exitScript: "Carving depth must be 0-40 dB and instability depth 0-24 dB."
endif
if instRate < 0.02 or instRate > 20
    exitScript: "Instability rate must be 0.02-20 Hz."
endif
# memory guard: the largest stage (C: six band copies + work copies)
memEst = 8 * nS * nCh * 12
if memEst > 3e9
    exitScript: "This Sound is too large for the in-memory engine (about " + fixed$ (memEst / 1e9, 1) + " GB needed; limit 3 GB). Process it in sections."
endif
# analysis-grid guard, predicted BEFORE the Spectrogram is made (Praat's
# Gaussian window is physically 2 x nominal; the bin spacing is the FFT
# bin, or a whole multiple of it when the frequency step is larger). The
# Spectrogram, its Matrix and the vector copy each hold this many cells;
# bin pooling below then reduces the working grid to <= 4 million.
nsW = floor (2 * winMs / 1000 * fs)
nFft = 2 ^ ceiling (log2 (max (2, nsW)))
fftBin = fs / nFft
dFest = max (1, floor (freqStep / fftBin)) * fftBin
nbEst = floor (maxFreqUsed / dFest) + 1
# Praat raises the time step to at least window / (8 sqrt(pi)) (its
# oversampling limit), so the effective step is used here
nfEst = floor (dur / max (stepMs / 1000, winMs / 1000 / (8 * sqrt (pi)))) + 1
if nbEst * nfEst > 2.5e7
    exitScript: "The analysis grid would be too large (about " + fixed$ (nbEst * nfEst / 1e6, 0) + " million cells; limit 25 million). Raise the Analysis step, lower the Maximum frequency or the Analysis window, or raise the Frequency step."
endif

# ============================================================
# WORKING COPIES (the original is never modified)
# ============================================================
selectObject: srcOrig
src = Copy: "as_src"
Shift times to: "start time", 0
if nCh = 2
    anaSnd = Convert to mono
else
    anaSnd = Copy: "as_ana"
endif

# ============================================================
# 1. SPECTRAL ANALYSIS (once)
# ============================================================
selectObject: anaSnd
spg = To Spectrogram: winMs / 1000, maxFreqUsed, stepMs / 1000, freqStep, "Gaussian"
pMat = To Matrix
removeObject: spg, anaSnd
selectObject: pMat
nb = Get number of rows
nf = Get number of columns
t1 = Get x of column: 1
dt = Get column distance
y1 = Get y of row: 1
binHz = Get row distance
# drop the DC row (row 1 at 0 Hz) from the distances when present
rowLo = 1
if y1 < binHz / 2
    rowLo = 2
endif
if nf < 4
    removeObject: pMat, src
    exitScript: "Too few analysis frames (" + string$ (nf) + "); use a longer Sound or a shorter step."
endif
p## = Get all values
# long recordings: pool adjacent frequency bins (sum of power) so the grid
# stays <= 4 million cells; Praat's Spectrogram always uses the FFT bin
# spacing, so this is done here. Reported.
poolG = 1
nbOrig = nb
if nb * nf > 4e6
    poolG = ceiling (nb * nf / 4e6)
    nbP = floor (nb / poolG)
    if nbP < 16
        removeObject: pMat, src
        exitScript: "The recording is too long for the analysis grid (" + string$ (nf) + " frames); raise the Analysis step."
    endif
    # sum groups of poolG adjacent rows, one row offset per pass: no
    # auxiliary matrix (v1.0 built an nbP x nb aggregator, which could
    # reach gigabytes at high sample rates with long windows)
    removeObject: pMat
    pMat = Create simple Matrix: "as_pool", nbP, nf, "0"
    for zq to poolG
        Formula: "self + p## [(row - 1) * poolG + zq, col]"
    endfor
    p## = Get all values
    y1 = y1 + (poolG - 1) / 2 * binHz
    binHz = binHz * poolG
    nb = nbP
    rowLo = 1
endif
eFrame# = columnSums# (p##)
eMax = max (eFrame#)
floorP = eMax / nb * 1e-10
silent# = zero# (nf)
for zf to nf
    if 10 * log10 ((eFrame# [zf] + 1e-300) / eMax) < silenceDb
        silent# [zf] = 1
    endif
endfor

# ---- frame-to-frame distance (out-of-place matrices; no in-place neighbour reads) ----
procedure frameVector: .name$
    # 1 x nf matrix holding a per-frame vector, for use inside formulas
    .m = Create simple Matrix: .name$, 1, nf, "0"
    Formula: "vecTmp# [col]"
endproc

if metric = 1
    metricName$ = "log-spectral difference (1/6-octave bands, dB, frame level removed)"
    # Pool the power bins into 1/6-octave bands (from 50 Hz; a band is at
    # least one bin wide) and floor each frame 20 dB below its own mean band
    # power. Per-bin log differences on real recordings are dominated by
    # low-level bins (noise floor, codec holes, gaps between harmonics)
    # that jitter by several dB every frame, which makes a held vowel look
    # as "changing" as a consonant run; pooling and the relative floor
    # keep the measure on the parts of the spectrum one actually hears.
    bandLo# = zero# (200)
    bandHi# = zero# (200)
    nBandD = 0
    rNext = rowLo
    fEdge = 50
    while rNext <= nb and nBandD < 200
        fEdge = fEdge * 2 ^ (1 / 6)
        rEnd = min (nb, max (rNext, floor ((fEdge - y1) / binHz + 0.5)))
        if fEdge >= maxFreqUsed
            rEnd = nb
        endif
        nBandD = nBandD + 1
        bandLo# [nBandD] = rNext
        bandHi# [nBandD] = rEnd
        rNext = rEnd + 1
    endwhile
    if rNext <= nb
        bandHi# [nBandD] = nb
    endif
    gAgg## = zero## (nBandD, nb)
    for zb to nBandD
        for zq from bandLo# [zb] to bandHi# [zb]
            gAgg## [zb, zq] = 1
        endfor
    endfor
    bP## = mul## (gAgg##, p##)
    gAgg## = zero## (1, 1)
    bFl# = columnSums# (bP##) / nBandD * 0.01 + floorP
    lgM = Create simple Matrix: "as_log", nBandD, nf, "10 * log10 (bP## [row, col] + bFl# [col])"
    lg## = Get all values
    bP## = zero## (1, 1)
    meanLog# = columnSums# (lg##) / nBandD
    dM = Create simple Matrix: "as_diff", nBandD, nf, "if col = 1 then 0 else (lg## [row, col] - meanLog# [col]) - (lg## [row, col - 1] - meanLog# [col - 1]) fi"
    q## = Get all values
    dist# = sqrt# (columnSums# (q## * q##) / nBandD)
    q## = zero## (1, 1)
    lg## = zero## (1, 1)
    removeObject: lgM, dM
    absRef = 4
elsif metric = 2
    metricName$ = "normalized Euclidean (unit-L2 magnitude spectra)"
    vecTmp# = sqrt# (eFrame# + nb * floorP)
    @frameVector: "as_norm"
    nrmM = frameVector.m
    dM = Create simple Matrix: "as_diff", nb, nf, "if col = 1 or row < rowLo then 0 else sqrt (object [pMat, row, col] + floorP) / object [nrmM, 1, col] - sqrt (object [pMat, row, col - 1] + floorP) / object [nrmM, 1, col - 1] fi"
    q## = Get all values
    dist# = sqrt# (columnSums# (q## * q##))
    removeObject: nrmM, dM
    absRef = 0.4
else
    metricName$ = "spectral flux (unit-L1 magnitude spectra, positive changes)"
    selectObject: pMat
    am = Copy: "as_amp"
    Formula: "sqrt (self + floorP)"
    a## = Get all values
    vecTmp# = columnSums# (a##)
    @frameVector: "as_l1"
    l1M = frameVector.m
    dM = Create simple Matrix: "as_diff", nb, nf, "if col = 1 or row < rowLo then 0 else max (0, object [am, row, col] / object [l1M, 1, col] - object [am, row, col - 1] / object [l1M, 1, col - 1]) fi"
    q## = Get all values
    dist# = columnSums# (q##)
    removeObject: am, l1M, dM
    absRef = 0.2
endif
dist# [1] = dist# [2]

# ---- valid distances (both frames non-silent) ----
valid# = zero# (nf)
nValid = 0
for zf to nf
    zp = max (1, zf - 1)
    if silent# [zf] = 0 and silent# [zp] = 0
        valid# [zf] = 1
        nValid = nValid + 1
    endif
endfor
if nValid < 3
    removeObject: pMat, src
    exitScript: "Fewer than 3 non-silent analysis frames: raise the Silence threshold (e.g. -70 dB) or use louder material."
endif
vals# = zero# (nValid)
zi = 0
for zf to nf
    if valid# [zf]
        zi = zi + 1
        vals# [zi] = dist# [zf]
    endif
endfor
# Praat's quantile () expects a SORTED vector (v1.1 passed it unsorted, so
# q10 / q90 were arbitrary order statistics)
vals# = sort# (vals#)
q10 = quantile (vals#, 0.10)
q90 = quantile (vals#, 0.90)
fallback = 0
if q90 - q10 < 0.05 * absRef
    fallback = 1
endif

# ============================================================
# 2. CONTROL CURVE (frame rate)
# ============================================================
stab# = zero# (nf)
craw# = zero# (nf)
for zf to nf
    if valid# [zf]
        if fallback
            dn = min (1, max (0, dist# [zf] / absRef))
        else
            dn = min (1, max (0, (dist# [zf] - q10) / (q90 - q10)))
        endif
        stab# [zf] = 1 - dn
        u = min (1, max (0, sensitivity * (stab# [zf] - threshold) / (1 - threshold)))
        if u > 0 and u < 1
            craw# [zf] = u ^ contrast / (u ^ contrast + (1 - u) ^ contrast)
        else
            craw# [zf] = u
        endif
    endif
endfor
# persistence: a build-up memory that rises slowly while the region is
# stable. Output = min (instant control, build-up), so a transient (instant
# control ~0) still releases the effect AT ONCE. With "Persistence
# release" > 0 the build-up memory itself decays with that time constant
# instead of being reset, so a short interruption (a consonant between two
# held vowels) does not throw away the build-up: the next stable stretch
# resumes from it. Release 0 = v1.0 behaviour (reset on every change).
cpers# = craw#
if persistS > 0
    alphaP = 1 - exp (-dt / persistS)
    alphaR = 1
    if releaseMs > 0
        alphaR = 1 - exp (-dt / (releaseMs / 1000))
    endif
    pv = 0
    for zf to nf
        if craw# [zf] > pv
            pv = pv + (craw# [zf] - pv) * alphaP
        else
            pv = pv + (craw# [zf] - pv) * alphaR
        endif
        cpers# [zf] = min (craw# [zf], pv)
    endfor
endif
# symmetric moving average (zero lag)
ctl# = cpers#
halfK = round (smoothMs / 1000 / dt / 2)
if halfK >= 1
    cs# = zero# (nf + 1)
    for zf to nf
        cs# [zf + 1] = cs# [zf] + cpers# [zf]
    endfor
    for zf to nf
        za = max (1, zf - halfK)
        zb = min (nf, zf + halfK)
        ctl# [zf] = (cs# [zb + 1] - cs# [za]) / (zb - za + 1)
    endfor
endif
# silence protection after smoothing too: no intervention inside silence
for zf to nf
    if silent# [zf]
        ctl# [zf] = 0
    endif
endfor
meanCtl = mean (ctl#)
nHigh = 0
for zf to nf
    if ctl# [zf] > 0.5
        nHigh = nHigh + 1
    endif
endfor

# control as a Sound at frame rate; lookups are clamped between the first
# and last frame (time-based lookup interpolates toward 0 outside them)
vecTmp# = ctl#
ctlSnd = Create Sound from formula: "as_ctl", 1, t1 - dt / 2, t1 - dt / 2 + nf * dt, 1 / dt, "vecTmp# [col]"
xc0 = t1
xc1 = t1 + (nf - 1) * dt
cAt$ = "(intens * object (ctlSnd, min (max (x, xc0), xc1)))"

procedure ctlAt: .t
    .zf = max (1, min (nf, round ((.t - t1) / dt) + 1))
    .c = intens * ctl# [.zf]
endproc

# ============================================================
# 3. TRANSFORMATION STAGES
# ============================================================
stageNote$ = ""
cur = src

# ---- spectral helpers (one forward spectrum per channel) ----
procedure exactLength: .long, .name$
    # trims an inverse-FFT result to exactly nS samples starting at 0
    exLong = .long
    .out = Create Sound from formula: .name$, 1, 0, nS / fs, fs, "object [exLong, 1, col]"
    removeObject: .long
endproc

procedure combineChannels: .name$
    # chan_1 (and chan_2) -> one Sound with nCh channels
    if nCh = 1
        .out = chan_1
        selectObject: .out
        Rename: .name$
    else
        .out = Create Sound from formula: .name$, 2, 0, nS / fs, fs, "if row = 1 then object [chan_1, 1, col] else object [chan_2, 1, col] fi"
        removeObject: chan_1, chan_2
    endif
endproc

# ---------------- B: temporal fragmentation ----------------
procedure stageFragment
    hH = max (2, round (xfadeMs / 1000 * fs))
    nG = ceiling (nS / hH) + 2
    lMinG = max (1, round (fragMinMs / 1000 * fs / hH))
    lMaxG = max (lMinG, round (fragMaxMs / 1000 * fs / hH))
    memN = round (displaceMs / 1000 * fs)
    a# = zero# (nG + 1)
    dir# = zero# (nG + 1)
    md# = zero# (nG + 1)
    mg# = zero# (nG + 1)
    random_initializeWithSeedUnsafelyButPredictably (seed)
    inLoop = 0
    nLoops = 0
    nRev = 0
    nMem = 0
    memLeft = 0
    memD = 0
    for zk from 0 to nG
        tk = (zk - 1) * hH + 1
        @ctlAt: (tk - 1 + hH) / fs
        ck = min (1, ctlAt.c)
        if inLoop and ck < 0.05
            inLoop = 0
        endif
        if inLoop = 0 and zk >= 1 and repStrength > 0 and ck > 0.05
            qEnter = min (1, repStrength * ck * hH / (lMinG * hH))
            if randomUniform (0, 1) < qEnter
                lenG = max (lMinG, min (lMaxG, round (lMaxG - (lMaxG - lMinG) * min (1, ck))))
                lStart = tk - lenG * hH
                if lStart >= 1 + 2 * hH
                    inLoop = 1
                    loopPos = 0
                    reps = 1 + floor (repStrength * ck * 3 + randomUniform (0, 1))
                    loopTotal = lenG * reps
                    loopDir = 1
                    if randomUniform (0, 1) < reverseProb * ck
                        loopDir = -1
                        nRev = nRev + 1
                    endif
                    nLoops = nLoops + 1
                endif
            endif
        endif
        if inLoop
            zi = loopPos mod lenG
            if loopDir = 1
                a# [zk + 1] = lStart + zi * hH
            else
                a# [zk + 1] = lStart + lenG * hH - 1 - zi * hH
            endif
            dir# [zk + 1] = loopDir
            loopPos = loopPos + 1
            if loopPos >= loopTotal
                inLoop = 0
            endif
        else
            a# [zk + 1] = tk
            dir# [zk + 1] = 1
        endif
        # bounded causal memory stream
        if memN > 0 and interference > 0
            if memLeft <= 0
                memLeft = round (randomUniform (lMinG, lMaxG))
                # jump back by a random part of the history that exists here
                memAvail = min (memN, max (0, tk - 1 - 4 * hH))
                memD = - round (randomUniform (0.15, 1) * memAvail)
                if memD < 0
                    nMem = nMem + 1
                endif
            endif
            memLeft = memLeft - 1
            # a grain whose memory read would fall before the start gets no
            # memory (v0 clamped it to the start and re-read one spot = buzz)
            if memD < 0 and a# [zk + 1] + memD >= 1 + 2 * hH
                md# [zk + 1] = memD
                mg# [zk + 1] = min (1, interference * ck)
            endif
        endif
    endfor
    random_initializeSafelyAndUnpredictably ()
    # explicit read-range check: for every grain, the source samples it
    # reads for output samples 1..nS (both ends of its span, main and
    # memory stream) must lie in 1..nS. The planner guarantees this; the
    # check makes a violation an error instead of a silent zero read.
    nBad = 0
    for zk from 0 to nG
        tk = (zk - 1) * hH + 1
        jLo = max (0, 1 - tk)
        jHi = min (2 * hH - 1, nS - tk)
        if jHi >= jLo
            r1 = a# [zk + 1] + dir# [zk + 1] * jLo
            r2 = a# [zk + 1] + dir# [zk + 1] * jHi
            if min (r1, r2) < 1 or max (r1, r2) > nS
                nBad = nBad + 1
            endif
            if mg# [zk + 1] > 0
                if min (r1, r2) + md# [zk + 1] < 1 or max (r1, r2) + md# [zk + 1] > nS
                    nBad = nBad + 1
                endif
            endif
        endif
    endfor
    if nBad > 0
        removeObject: src, pMat, ctlSnd
        if cur <> src
            removeObject: cur
        endif
        exitScript: "Internal error: " + string$ (nBad) + " grains would read outside the recording. Please report this with the file and settings."
    endif
    planA# = a#
    planD# = dir#
    planM# = md#
    planG# = mg#
    plan = Create simple Matrix: "as_plan", 4, nG + 1, "if row = 1 then planA# [col] else if row = 2 then planD# [col] else if row = 3 then planM# [col] else planG# [col] fi fi fi"
    useMem = max (mg#) > 0
    # output sample col: grain k = floor((col-1)/hH)+1 rises, grain k-1 falls
    k$ = "(floor ((col - 1) / hH) + 2)"
    km$ = "(floor ((col - 1) / hH) + 1)"
    m$ = "(col - 1 - floor ((col - 1) / hH) * hH)"
    @grainExpr: k$, m$
    rise$ = grainExpr.e$
    @grainExpr: km$, "(" + m$ + " + hH)"
    fall$ = grainExpr.e$
    phi$ = "(pi * " + m$ + " / (2 * hH))"
    fragIn = cur
    fragOut = Create Sound from formula: "as_frag", nCh, 0, nS / fs, fs, "sin (" + phi$ + ") ^ 2 * " + rise$ + " + cos (" + phi$ + ") ^ 2 * " + fall$
    removeObject: plan
    if cur <> src
        removeObject: cur
    endif
    cur = fragOut
    stageNote$ = stageNote$ + "B: " + string$ (nLoops) + " loops (" + string$ (nRev) + " reversed), hop " + fixed$ (hH / fs * 1000, 1) + " ms, fragments " + fixed$ (fragMinMs, 0) + "-" + fixed$ (fragMaxMs, 0) + " ms"
    if useMem
        nMemOn = 0
        for zk to nG + 1
            if mg# [zk] >= 0.25
                nMemOn = nMemOn + 1
            endif
        endfor
        stageNote$ = stageNote$ + ", memory " + string$ (nMem) + " planned (<= " + fixed$ (displaceMs, 0) + " ms back), audible " + fixed$ (100 * nMemOn / (nG + 1), 0) + "% of time, share " + fixed$ (100 * sum (mg#) / (nG + 1), 0) + "%"
    endif
    stageNote$ = stageNote$ + newline$
endproc

# grain read expression for plan column .kc$ at grain offset .j$
# (main stream, plus the memory stream when it is in use)
procedure grainExpr: .kc$, .j$
    .main$ = "object [fragIn, row, object [plan, 1, " + .kc$ + "] + object [plan, 2, " + .kc$ + "] * " + .j$ + "]"
    if useMem
        .mem$ = "object [fragIn, row, object [plan, 1, " + .kc$ + "] + object [plan, 3, " + .kc$ + "] + object [plan, 2, " + .kc$ + "] * " + .j$ + "]"
        # explicit branch: a grain without memory never evaluates the
        # memory read (its offset is 0 anyway, so the index would equal the
        # main read, but the formula no longer depends on that)
        .e$ = "(if object [plan, 4, " + .kc$ + "] > 0 then sqrt (1 - object [plan, 4, " + .kc$ + "]) * " + .main$ + " + sqrt (object [plan, 4, " + .kc$ + "]) * " + .mem$ + " else " + .main$ + " fi)"
    else
        .e$ = .main$
    endif
endproc

# ---------------- A: stability-weighted spectral carving ----------------
procedure stageResist
    # stability-weighted, level-normalised long-term spectrum
    w# = zero# (nf)
    for zf to nf
        if valid# [zf]
            w# [zf] = ctl# [zf] / (eFrame# [zf] + nb * floorP)
        endif
    endfor
    wSum = sum (w#)
    lt# = mul# (p##, w#)
    nBins = nb
    gain# = zero# (nBins)
    maxCut = 0
    maxBoost = 0
    if wSum > 1e-12 and sum (ctl#) > 0.01
        ltDb# = zero# (nBins)
        for zb to nBins
            ltDb# [zb] = 10 * log10 (lt# [zb] / wSum + 1e-30)
        endfor
        # relative to its own 1/3-octave running mean
        for zb from rowLo to nBins
            fC = y1 + (zb - 1) * binHz
            fA = max (y1 + (rowLo - 1) * binHz, fC / 2 ^ (1 / 6))
            fB = fC * 2 ^ (1 / 6)
            zA = max (rowLo, round ((fA - y1) / binHz) + 1)
            zB = min (nBins, max (zA, round ((fB - y1) / binHz) + 1))
            s = 0
            for zq from zA to zB
                s = s + ltDb# [zq]
            endfor
            excess = ltDb# [zb] - s / (zB - zA + 1)
            g = - resDepth / 12 * excess
            g = min (resDepth / 2, max (- resDepth, g))
            gain# [zb] = g
            maxCut = min (maxCut, g)
            maxBoost = max (maxBoost, g)
        endfor
        resNote$ = "carving filter " + fixed$ (maxCut, 1) + " .. +" + fixed$ (maxBoost, 1) + " dB below " + fixed$ (maxFreqUsed, 0) + " Hz"
    else
        resNote$ = "no stable region found: carving filter flat"
    endif
    resGain# = gain#
    # gain lookup over frequency (Sound used as a curve: x = Hz); 0 dB above
    vecTmp# = gain#
    lut = Create Sound from formula: "as_lut", 1, y1 - binHz / 2, y1 - binHz / 2 + nBins * binHz, 1 / binHz, "vecTmp# [col]"
    lutF0 = y1
    lutF1 = y1 + (nBins - 1) * binHz
    for zc to nCh
        selectObject: cur
        tmpCh = Extract one channel: zc
        tmpSp = To Spectrum: "yes"
        Formula: "if x > lutF1 + binHz then self else self * 10 ^ (object (lut, min (max (x, lutF0), lutF1)) / 20) fi"
        tmpLong = To Sound
        removeObject: tmpCh, tmpSp
        @exactLength: tmpLong, "as_resch"
        chan_'zc' = exactLength.out
    endfor
    removeObject: lut
    @combineChannels: "as_carved"
    carved = combineChannels.out
    # carved copy level-matched to its input moment by moment: a make-up
    # gain from the ratio of the two short-term power envelopes (sum over
    # channels, so one gain for both: stereo image kept), low-passed at
    # 20 Hz (about 50 ms) and clipped to +-12 dB. v1.0 matched only the
    # global RMS, so stable regions, where the cut is deepest, came out up
    # to 7 dB quieter.
    resIn = cur
    wE = Create Sound from formula: "as_we", 2, 0, nS / fs, fs, "if row = 1 then object [resIn, 1, col] ^ 2 else object [carved, 1, col] ^ 2 fi"
    if nCh = 2
        Formula: "self + if row = 1 then object [resIn, 2, col] ^ 2 else object [carved, 2, col] ^ 2 fi"
    endif
    wS = Filter (pass Hann band): 0, 20, 10
    removeObject: wE
    eFl = Get absolute extremum: 0, 0, "None"
    eFl = max (1e-20, eFl * 1e-8)
    gain$ = "min (4, max (0.25, sqrt (max (object [wS, 1, col], eFl) / max (object [wS, 2, col], eFl))))"
    resOut = Create Sound from formula: "as_res", nCh, 0, nS / fs, fs, "(1 - min (1, " + cAt$ + ")) * object [resIn, row, col] + min (1, " + cAt$ + ") * " + gain$ + " * object [carved, row, col]"
    removeObject: carved, wS
    if cur <> src
        removeObject: cur
    endif
    cur = resOut
    stageNote$ = stageNote$ + "A: " + resNote$ + newline$
endproc

# ---------------- C: spectral instability ----------------
procedure stageInstab
    nBand = 6
    fTop = min (maxFreqUsed, 0.9 * nyq)
    bandSm = 40
    for zi to nBand
        bandLo_'zi' = 0
        bandHi_'zi' = 0
        if zi > 1
            bandLo_'zi' = 150 * (fTop / 150) ^ ((zi - 2) / (nBand - 2))
        endif
        if zi < nBand
            bandHi_'zi' = 150 * (fTop / 150) ^ ((zi - 1) / (nBand - 2))
        endif
    endfor
    # bands from ONE forward spectrum per channel; complementary Hann bands
    for zc to nCh
        selectObject: cur
        tmpCh = Extract one channel: zc
        tmpSp = To Spectrum: "yes"
        removeObject: tmpCh
        for zi to nBand
            selectObject: tmpSp
            tmpB = Copy: "as_bsp"
            Filter (pass Hann band): bandLo_'zi', bandHi_'zi', bandSm
            tmpLong = To Sound
            removeObject: tmpB
            @exactLength: tmpLong, "as_bch"
            bch_'zi'_'zc' = exactLength.out
        endfor
        removeObject: tmpSp
    endfor
    for zi to nBand
        for zc to nCh
            chan_'zc' = bch_'zi'_'zc'
        endfor
        @combineChannels: "as_band"
        band_'zi' = combineChannels.out
        selectObject: band_'zi'
        bandE_'zi' = Get root-mean-square: 0, 0
        bandE_'zi' = bandE_'zi' ^ 2
    endfor
    eTot = 0
    for zi to nBand
        eTot = eTot + bandE_'zi'
    endfor
    eTot = max (eTot, 1e-30)
    # slow seeded drifts m_i(t): three sinusoids per band, unit RMS
    random_initializeWithSeedUnsafelyButPredictably (seed + 7)
    for zi to nBand
        for zq to 3
            mf_'zi'_'zq' = instRate * randomUniform (0.5, 1.5)
            mp_'zi'_'zq' = randomUniform (0, 2 * pi)
        endfor
    endfor
    random_initializeSafelyAndUnpredictably ()
    gainsM## = zero## (nBand, nf)
    for zf to nf
        tf = t1 + (zf - 1) * dt
        cf = intens * ctl# [zf]
        norm = 0
        for zi to nBand
            mm = (sin (2 * pi * mf_'zi'_1 * tf + mp_'zi'_1) + sin (2 * pi * mf_'zi'_2 * tf + mp_'zi'_2) + sin (2 * pi * mf_'zi'_3 * tf + mp_'zi'_3)) / sqrt (1.5)
            gl = 10 ^ (instDepth * cf * mm / 20)
            gainsM## [zi, zf] = gl
            norm = norm + bandE_'zi' * gl * gl
        endfor
        norm = sqrt (norm / eTot)
        for zi to nBand
            gainsM## [zi, zf] = gainsM## [zi, zf] / norm
        endfor
    endfor
    instGains## = gainsM##
    gainSnd = Create Sound from formula: "as_bgain", nBand, t1 - dt / 2, t1 - dt / 2 + nf * dt, 1 / dt, "gainsM## [row, col]"
    sum$ = ""
    for zi to nBand
        if zi > 1
            sum$ = sum$ + " + "
        endif
        sum$ = sum$ + "object [" + string$ (band_'zi') + ", row, col] * object (gainSnd, min (max (x, xc0), xc1), " + string$ (zi) + ")"
    endfor
    instOut = Create Sound from formula: "as_inst", nCh, 0, nS / fs, fs, sum$
    for zi to nBand
        removeObject: band_'zi'
    endfor
    removeObject: gainSnd
    if cur <> src
        removeObject: cur
    endif
    cur = instOut
    stageNote$ = stageNote$ + "C: " + string$ (nBand) + " bands, drift +-" + fixed$ (instDepth, 1) + " dB at ~" + fixed$ (instRate, 2) + " Hz" + newline$
endproc

fragDone = 0
resDone = 0
instDone = 0
stopwatch
if mode = 2 or mode = 4
    if repStrength > 0 or (displaceMs > 0 and interference > 0)
        @stageFragment
        fragDone = 1
    else
        stageNote$ = stageNote$ + "B: inactive (repetition 0 and no memory stream)" + newline$
    endif
endif
if mode = 1 or mode = 4
    if resDepth > 0
        @stageResist
        resDone = 1
    else
        stageNote$ = stageNote$ + "A: inactive (carving depth 0)" + newline$
    endif
endif
if mode = 3 or mode = 4
    if instDepth > 0
        @stageInstab
        instDone = 1
    else
        stageNote$ = stageNote$ + "C: inactive (instability depth 0)" + newline$
    endif
endif
procTime = stopwatch

# ============================================================
# 4. MIX AND LEVEL
# ============================================================
wet = cur
outName$ = srcName$ + "_antisimilar"
out = Create Sound from formula: outName$, nCh, 0, nS / fs, fs, "(1 - mix) * object [src, row, col] + mix * object [wet, row, col]"
if wet <> src
    removeObject: wet
endif
peakRaw = Get absolute extremum: 0, 0, "None"
levelNote$ = "not needed"
# ceiling: 0.999, or the source's own peak if that is higher. Protection
# never touches a result that is no hotter than the input, so wet/dry 0 %
# (and intensity 0) return the source sample for sample even when the
# source itself peaks above 0.999 (v1.2 would have altered it).
ceilP = max (0.999, srcPeak)
# (1e-6 tolerance: the band split / OLA reconstruct the input to ~1e-9,
# which must not count as an over)
if peakRaw > ceilP * (1 + 1e-6)
    # how many samples are over? (a few isolated peaks should not turn the
    # whole result down: v1.1 lost 3.9 dB on one stray sample)
    selectObject: out
    ovr = Copy: "as_ovr"
    Formula: "abs (self) > ceilP"
    fracOver = Get mean: 0, 0, 0
    removeObject: ovr
    selectObject: out
    if fracOver < 1e-3 and peakRaw < 2 * ceilP
        # rare peaks: soft knee above 0.9 x ceiling on those samples only
        # (tanh towards the ceiling); everything below is untouched
        kneeP = 0.9 * ceilP
        kneeR = 0.099 * ceilP
        # count what the knee will actually reshape (every sample above
        # 0.9 x ceiling), not only the overs that triggered it
        ovr = Copy: "as_ovr"
        Formula: "abs (self) > kneeP"
        fracKnee = Get mean: 0, 0, 0
        removeObject: ovr
        selectObject: out
        Formula: "if abs (self) <= kneeP then self else (if self > 0 then 1 else -1 fi) * (kneeP + kneeR * tanh ((abs (self) - kneeP) / kneeR)) fi"
        levelNote$ = "soft knee: " + string$ (round (fracOver * nS * nCh)) + " overs (max " + fixed$ (20 * log10 (peakRaw), 1) + " dBFS), " + string$ (round (fracKnee * nS * nCh)) + " samples reshaped above " + fixed$ (20 * log10 (kneeP), 1) + " dBFS"
    else
        Formula: "self * ceilP / peakRaw"
        levelNote$ = "attenuated " + fixed$ (20 * log10 (ceilP / peakRaw), 1) + " dB to avoid clipping"
    endif
endif
# how much the sound actually changed (not just how high the control was):
# RMS of (output - input) relative to the input RMS, whole file and in the
# frames where the control is above 0.5
selectObject: out
# rows: 1 diff^2, 2 src^2, 3 diff^2 where c > 0.5, 4 src^2 where c > 0.5
# (summed over channels)
mask$ = "(object (ctlSnd, min (max (x, xc0), xc1)) > 0.5)"
dfS = Create Sound from formula: "as_diff", 4, 0, nS / fs, fs, "0"
for zc to nCh
    Formula: "self + if row = 1 or row = 3 then (object [out, " + string$ (zc) + ", col] - object [src, " + string$ (zc) + ", col]) ^ 2 else object [src, " + string$ (zc) + ", col] ^ 2 fi * if row >= 3 then " + mask$ + " else 1 fi"
endfor
eD = Get mean: 1, 0, 0
eS = Get mean: 2, 0, 0
eDh = Get mean: 3, 0, 0
eSh = Get mean: 4, 0, 0
removeObject: dfS
diffDb = round (100 * log10 (max (eD, 1e-30) / max (eS, 1e-30))) / 10
diffHiDb = undefined
if eSh > 1e-30
    diffHiDb = round (100 * log10 (max (eDh, 1e-30) / eSh)) / 10
endif
selectObject: out
Shift times to: "start time", srcStart
outRms = Get root-mean-square: 0, 0
outPeak = Get absolute extremum: 0, 0, "None"
outN = Get number of samples

# ============================================================
# REPORT
# ============================================================
modeName$ = "A Stability-weighted spectral carving"
if mode = 2
    modeName$ = "B Temporal fragmentation"
elsif mode = 3
    modeName$ = "C Spectral instability"
elsif mode = 4
    modeName$ = "D Hybrid resistance (B -> A -> C)"
endif
chTxt$ = "mono"
if nCh = 2
    chTxt$ = "stereo (one shared control curve from the mono sum)"
endif
writeInfoLine: "=== Anti-Similarity — Spectral Resistance v", version$, " ==="
appendInfoLine: "Source:      ", srcName$, "  (", fixed$ (dur, 3), " s, ", fs, " Hz, ", chTxt$, ")"
appendInfoLine: "Preset:      ", presetName$, "   mode ", modeName$, "   intensity ", fixed$ (effect_intensity, 0), " %, mix ", fixed$ (wet_dry_mix, 0), " %, seed ", seed
appendInfoLine: "Analysis:    ", nf, " frames x ", nb, " bins (", fixed$ (binHz, 2), " Hz, up to ", fixed$ (maxFreqUsed, 0), " Hz); window ", fixed$ (winMs, 0), " ms Gaussian (physical ", fixed$ (2 * winMs, 0), " ms), step ", fixed$ (dt * 1000, 1), " ms"
if poolG > 1
    appendInfoLine: "             long recording: ", nbOrig, " FFT bins pooled in groups of ", poolG, " to keep the grid at 4 million cells"
endif
appendInfoLine: "Distance:    ", metricName$
appendInfoLine: "             ", nValid, " valid frames, ", nf - nValid, " touching silence (below ", fixed$ (silenceDb, 0), " dB)"
if fallback
    appendInfoLine: "             nearly constant distance curve: absolute scale (", fixed$ (absRef, 2), ") used instead of percentiles"
else
    appendInfoLine: "             robust range q10 ", fixed$ (q10, 4), " .. q90 ", fixed$ (q90, 4)
endif
appendInfoLine: "Control:     threshold ", fixed$ (threshold, 2), ", sensitivity ", fixed$ (sensitivity, 2), ", contrast ", fixed$ (contrast, 2), ", persistence ", fixed$ (persistS, 1), " s (release ", fixed$ (releaseMs, 0), " ms), smoothing ", fixed$ (smoothMs, 0), " ms"
appendInfoLine: "             mean control ", fixed$ (meanCtl, 3), "; frames above 0.5: ", fixed$ (100 * nHigh / nf, 1), " %"
if meanCtl < 0.05
    appendInfoLine: "             LOW INTERVENTION: this material is rarely stable enough for these settings. Lower the Stability threshold, raise the Sensitivity, or shorten the Persistence; or choose a preset that reacts faster."
endif
appendInfoLine: "Stages:"
appendInfo: stageNote$
appendInfoLine: "Output:      ", outName$, "  ", outN, " samples (input ", nS, "), ", fs, " Hz, ", nCh, " ch; peak protection ", levelNote$
hiTxt$ = "no frames with control above 0.5"
if diffHiDb <> undefined
    hiTxt$ = fixed$ (diffHiDb, 1) + " dB where the control is above 0.5"
endif
if diffDb < -200
    appendInfoLine: "Change:      none: the output equals the input (difference below -200 dB)"
else
    appendInfoLine: "Change:      difference (output - input) ", fixed$ (diffDb, 1), " dB re input RMS overall; ", hiTxt$
    if levelNote$ <> "not needed"
        appendInfoLine: "             (includes the peak protection above)"
    endif
endif
appendInfoLine: "             (waveform difference, a rough guide: about -40 dB or lower is subtle; time-domain modes (loops, memory) read near 0 to +3 dB even when the source stays recognisable, because shifted material does not cancel)"
appendInfoLine: "             peak ", fixed$ (20 * log10 (max (outPeak, 1e-12)), 2), " dBFS, RMS ", fixed$ (20 * log10 (max (outRms, 1e-12)), 2), " dBFS (input ", fixed$ (20 * log10 (srcRms), 2), "); processing ", fixed$ (procTime, 1), " s"

if draw_visualisation
    @drawFigure
endif
removeObject: src, pMat, ctlSnd
selectObject: out
if play_result
    Play
endif

# ============================================================
# FIGURE (every curve is the data used for processing)
# ============================================================
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor (log10 (.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure sanitize: .s$
    .s$ = replace$ (.s$, "\", "\bs", 0)
    .s$ = replace$ (.s$, "_", "\_ ", 0)
    .s$ = replace$ (.s$, "%", "\% ", 0)
    .s$ = replace$ (.s$, "#", "\# ", 0)
    .s$ = replace$ (.s$, "^", "\^ ", 0)
    .out$ = .s$
endproc

procedure paintSpec: .snd, .y0, .y1, .setScale, .title$
    selectObject: .snd
    .mono = Convert to mono
    Shift times to: "start time", 0
    .spec = To Spectrogram: 0.02, maxFreqUsed, max (0.002, dur / 900), 20, "Gaussian"
    if .setScale
        .mat = To Matrix
        .pm = Get maximum
        removeObject: .mat
        figMaxDb = 10 * log10 (max (.pm, 1e-30) / 4e-10)
    endif
    selectObject: .spec
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Paint: 0, 0, 0, maxFreqUsed, figMaxDb, "no", 60, 6, 0, "no"
    removeObject: .spec, .mono
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, 0, maxFreqUsed
    Colour: "Black"
    Text top: "no", .title$
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, 0, maxFreqUsed
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @niceStep: maxFreqUsed, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
endproc

procedure shadeSilence: .y0, .y1, .ylo, .yhi
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, .ylo, .yhi
    for zf to nf
        if silent# [zf]
            .ta = max (0, t1 + (zf - 1.5) * dt)
            .tb = min (dur, t1 + (zf - 0.5) * dt)
            Paint rectangle: "{0.90, 0.90, 0.92}", .ta, .tb, .ylo, .yhi
        endif
    endfor
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    .a0 = 0.90
    .a1 = 2.05
    .b0 = 2.40
    .b1 = 3.30
    .c0 = 3.65
    .c1 = 4.55
    .d0 = 4.90
    .d1 = 6.25
    .e0 = 6.60
    .e1 = 7.75
    .s0 = 8.30
    .s1 = 9.30
    .canvasH = 9.40
    .step = max (1, floor (nf / 1200))

    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Anti-Similarity — " + presetName$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    @sanitize: srcName$ + "   |   " + modeName$ + "   |   intensity " + fixed$ (effect_intensity, 0) + "%, mix " + fixed$ (wet_dry_mix, 0) + "%   |   seed " + string$ (seed)
    Text: 0.5, "centre", 0.18, "half", sanitize.out$

    # 1. input spectrogram
    Font size: 7
    @paintSpec: src, .a0, .a1, 1, "##Input## — spectrogram (shared dB scale with the output)"
    @railLabel: .a0, .a1, "Freq (Hz)"

    # 2. spectral distance
    .dTop = q90 * 1.6
    if fallback
        .dTop = absRef * 1.6
    endif
    .dTop = max (.dTop, max (dist#) * 0.01, 1e-9)
    @shadeSilence: .b0, .b1, 0, .dTop
    Select inner viewport: 0.6, 7.7, .b0, .b1
    Axes: 0, dur, 0, .dTop
    Colour: "{0.85, 0.35, 0.15}"
    Line width: 1.2
    for zf from 1 + .step to nf
        if (zf - 1) mod .step = 0
            zp = zf - .step
            if valid# [zf] and valid# [zp]
                Draw line: t1 + (zp - 1) * dt, min (.dTop, dist# [zp]), t1 + (zf - 1) * dt, min (.dTop, dist# [zf])
            endif
        endif
    endfor
    Line width: 1
    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    if fallback
        Draw line: 0, absRef, dur, absRef
    else
        Draw line: 0, q10, dur, q10
        Draw line: 0, q90, dur, q90
    endif
    Solid line
    Select inner viewport: 0.6, 7.7, .b0, .b1
    Axes: 0, dur, 0, .dTop
    Colour: "Black"
    if fallback
        Text top: "no", "##Spectral distance## — absolute scale (dotted); grey: silence"
    else
        Text top: "no", "##Spectral distance## (frame to frame) — dotted: q10 / q90 normalisation range; grey: silence"
    endif
    Select inner viewport: 0.6, 7.7, .b0, .b1
    Axes: 0, dur, 0, .dTop
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @niceStep: .dTop, 3
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: .b0, .b1, "Distance"

    # 3. stability and control
    @shadeSilence: .c0, .c1, 0, 1.05
    Select inner viewport: 0.6, 7.7, .c0, .c1
    Axes: 0, dur, 0, 1.05
    Colour: "{0.70, 0.70, 0.74}"
    for zf from 1 + .step to nf
        if (zf - 1) mod .step = 0
            zp = zf - .step
            Draw line: t1 + (zp - 1) * dt, stab# [zp], t1 + (zf - 1) * dt, stab# [zf]
        endif
    endfor
    Colour: "{0.45, 0.45, 0.45}"
    Dotted line
    Draw line: 0, threshold, dur, threshold
    Solid line
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.8
    for zf from 1 + .step to nf
        if (zf - 1) mod .step = 0
            zp = zf - .step
            Draw line: t1 + (zp - 1) * dt, ctl# [zp], t1 + (zf - 1) * dt, ctl# [zf]
        endif
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, .c0, .c1
    Axes: 0, dur, 0, 1.05
    Colour: "Black"
    Text top: "no", "##Resistance control## — grey: stability 1 - distance; dotted: threshold; blue: control after contrast, persistence, smoothing"
    Select inner viewport: 0.6, 7.7, .c0, .c1
    Axes: 0, dur, 0, 1.05
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    @railLabel: .c0, .c1, "Control"

    # 4. mode panel
    if fragDone
        @panelGrains: .d0, .d1
    elsif resDone
        @panelCarve: .d0, .d1
    elsif instDone
        @panelBands: .d0, .d1
    else
        Select inner viewport: 0.6, 7.7, .d0, .d1
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Text: 0.5, "centre", 0.5, "half", "No processing stage active (all depths 0)"
        Draw inner box
    endif

    # 5. output spectrogram
    @sanitize: outName$
    @paintSpec: out, .e0, .e1, 0, "##Output## — " + sanitize.out$ + " (input dB scale)"
    Select inner viewport: 0.6, 7.7, .e0, .e1
    Axes: 0, dur, 0, maxFreqUsed
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: .e0, .e1, "Freq (Hz)"

    # summary
    Font size: 7
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    lowTxt$ = ""
    if meanCtl < 0.05
        lowTxt$ = "   LOW INTERVENTION (see Info)"
    endif
    @sanitize: "Distance: " + metricName$ + "; " + string$ (nValid) + " valid frames; mean control " + fixed$ (meanCtl, 2) + ", " + fixed$ (100 * nHigh / nf, 0) + "% of frames above 0.5" + lowTxt$
    Text: 0.012, "left", 0.72, "half", sanitize.out$
    # stage notes on two lines: the first stage, then the others
    .l$ = stageNote$
    if right$ (.l$, 1) = newline$
        .l$ = left$ (.l$, length (.l$) - 1)
    endif
    .l2$ = ""
    .nl = index (.l$, newline$)
    if .nl > 0
        .l2$ = mid$ (.l$, .nl + 1, length (.l$) - .nl)
        .l$ = left$ (.l$, .nl - 1)
    endif
    .l2$ = replace$ (.l2$, newline$, "   |   ", 0)
    if length (.l$) > 212
        .l$ = left$ (.l$, 209) + "..."
    endif
    if length (.l2$) > 212
        .l2$ = left$ (.l2$, 209) + "..."
    endif
    @sanitize: .l$
    Text: 0.012, "left", 0.57, "half", sanitize.out$
    if .l2$ <> ""
        @sanitize: .l2$
        Text: 0.012, "left", 0.42, "half", sanitize.out$
    endif
    @sanitize: "Control: threshold " + fixed$ (threshold, 2) + ", sensitivity " + fixed$ (sensitivity, 2) + ", contrast " + fixed$ (contrast, 2) + ", persistence " + fixed$ (persistS, 1) + " s / " + fixed$ (releaseMs, 0) + " ms, smoothing " + fixed$ (smoothMs, 0) + " ms; " + chTxt$
    Text: 0.012, "left", 0.27, "half", sanitize.out$
    chgTxt$ = fixed$ (diffDb, 1) + " dB"
    if diffDb < -200
        chgTxt$ = "none"
    endif
    @sanitize: "Output " + string$ (outN) + " samples = input, " + string$ (fs) + " Hz; peak " + fixed$ (20 * log10 (max (outPeak, 1e-12)), 1) + " dBFS; RMS " + fixed$ (20 * log10 (max (outRms, 1e-12) / srcRms), 1) + " dB vs input; change " + chgTxt$ + "; peak protection " + levelNote$
    Text: 0.012, "left", 0.12, "half", sanitize.out$
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, .canvasH
endproc

procedure panelGrains: .y0, .y1
    # read offset = source position read - output time (ms): 0 = unchanged;
    # a loop is a falling sawtooth (reverse: rising), memory reads sit lower
    .lo = -20
    for zk to nG
        .lo = min (.lo, (planA# [zk + 1] - ((zk - 1) * hH + 1)) / fs * 1000)
        if useMem
            if planG# [zk + 1] > 0.02
                .lo = min (.lo, (planA# [zk + 1] + planM# [zk + 1] - ((zk - 1) * hH + 1)) / fs * 1000)
            endif
        endif
    endfor
    .lo = .lo * 1.08
    .hi = max (20, -.lo * 0.06)
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, .lo, .hi
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur, .lo, .hi
    Colour: "{0.70, 0.70, 0.74}"
    Draw line: 0, 0, dur, 0
    .gs = max (1, floor (nG / 3000))
    if useMem
        for zk from 1 to nG
            if zk mod .gs = 0 and planG# [zk + 1] > 0.02
                .tk = ((zk - 1) * hH) / fs
                .off = (planA# [zk + 1] + planM# [zk + 1] - ((zk - 1) * hH + 1)) / fs * 1000
                Paint circle (mm): "{0.85, 0.35, 0.15}", .tk, .off, 0.2 + 0.5 * planG# [zk + 1]
            endif
        endfor
    endif
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.3
    for zk from 1 + .gs to nG
        if zk mod .gs = 0
            .zp = zk - .gs
            .oa = (planA# [.zp + 1] - ((.zp - 1) * hH + 1)) / fs * 1000
            .ob = (planA# [zk + 1] - ((zk - 1) * hH + 1)) / fs * 1000
            Draw line: ((.zp - 1) * hH) / fs, .oa, ((zk - 1) * hH) / fs, .ob
        endif
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, .lo, .hi
    Colour: "Black"
    .t$ = "##Fragmentation map## — read offset (blue): 0 = unchanged; loops fall back and jump forward"
    if useMem
        .t$ = .t$ + "; orange: memory stream (size = interference)"
    endif
    Text top: "no", .t$
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, .lo, .hi
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @niceStep: .hi - .lo, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: .y0, .y1, "Offset (ms)"
endproc

procedure panelCarve: .y0, .y1
    # the carving filter actually applied (dB over frequency)
    .gLo = min (-3, min (resGain#) - 1)
    .gHi = max (3, max (resGain#) + 1)
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, maxFreqUsed, .gLo, .gHi
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, maxFreqUsed, .gLo, .gHi
    Colour: "{0.82, 0.82, 0.86}"
    Draw line: 0, 0, maxFreqUsed, 0
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.5
    for zb from rowLo + 1 to nb
        Draw line: y1 + (zb - 2) * binHz, resGain# [zb - 1], y1 + (zb - 1) * binHz, resGain# [zb]
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, maxFreqUsed, .gLo, .gHi
    Colour: "Black"
    Text top: "no", "##Carving filter## — gain applied where the spectrum persists (fully at control 1, crossfaded below)"
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, maxFreqUsed, .gLo, .gHi
    Draw inner box
    @niceStep: maxFreqUsed, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: .gHi - .gLo, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Frequency (Hz)"
    @railLabel: .y0, .y1, "Gain (dB)"
endproc

procedure panelBands: .y0, .y1
    # band gains over time (dB), as applied
    .lim = max (1, instDepth * intens * 1.2)
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, -.lim, .lim
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur, -.lim, .lim
    Colour: "{0.82, 0.82, 0.86}"
    Draw line: 0, 0, dur, 0
    .step = max (1, floor (nf / 900))
    for zi to 6
        .col$ = "{0.20, 0.40, 0.80}"
        if zi = 2
            .col$ = "{0.15, 0.60, 0.35}"
        elsif zi = 3
            .col$ = "{0.85, 0.65, 0.10}"
        elsif zi = 4
            .col$ = "{0.85, 0.35, 0.15}"
        elsif zi = 5
            .col$ = "{0.75, 0.20, 0.45}"
        elsif zi = 6
            .col$ = "{0.45, 0.45, 0.45}"
        endif
        Colour: .col$
        for zf from 1 + .step to nf
            if (zf - 1) mod .step = 0
                zp = zf - .step
                Draw line: t1 + (zp - 1) * dt, max (-.lim, min (.lim, 20 * log10 (instGains## [zi, zp]))), t1 + (zf - 1) * dt, max (-.lim, min (.lim, 20 * log10 (instGains## [zi, zf])))
            endif
        endfor
    endfor
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, -.lim, .lim
    Colour: "Black"
    Text top: "no", "##Band gains## — six complementary bands, low (blue) to high (grey); drift depth follows the control"
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, dur, -.lim, .lim
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @niceStep: 2 * .lim, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: .y0, .y1, "Gain (dB)"
endproc
