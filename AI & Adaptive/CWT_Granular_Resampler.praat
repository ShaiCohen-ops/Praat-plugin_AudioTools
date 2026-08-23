# ============================================================
# Praat AudioTools - CWT_Granular_Resampler.praat
# CWT-driven granular resynthesis: Sound A analyses, Sound B sounds
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
#
# CHANGELOG v1.1 -> v1.2  (all six items were found by review + measurement)
#   a. FIXED (audible): pitch-up aliased. Reading B at rate r folds
#      everything above outputNyquist/r back into the output, and the
#      source oversampling v1.1 relied on does nothing about it -
#      measured 99.92 percent of the energy at the alias, identical at
#      1x, 4x and 8x. Rendering the whole output oversampled and
#      downsampling would cost about 4x the render time. Since the rate
#      is constant per band, B is now band-limited once per half-octave
#      rate group (cutoff = outputNyquist / the group's fastest rate)
#      and each band reads its own copy. Four filter calls at the
#      default +/-24 st.
#   b. FIXED (audible): the trigger grid POINT-SAMPLED the fine CWT
#      instead of pooling it, so at Time_step_s = 5 ms against
#      Trigger_step_ms = 20 three of every four analysed columns were
#      never examined. Measured: a 5 kHz transient on a trigger centre
#      read 0 dB, the same transient 10 ms away read -36.1 dB - below
#      the default threshold, firing nothing. Each trigger cell now
#      takes the maximum over every fine cell inside it, in both axes.
#   c. FIXED: hitting Maximum_grains truncated chronologically, keeping
#      the start of A and deleting the end. The expected total is
#      deterministic, so a first pass now computes it and the cap is
#      applied as a uniform keep factor across the whole duration.
#   d. FIXED: Trigger_threshold_dB >= 0 and Position_warp <= 0 are
#      reachable from Custom and are degenerate. Praat does not raise -
#      0/0 gives undefined, comparisons against undefined take the
#      FALSE branch, and the run ended with zero grains and a
#      diagnostic blaming the density multiplier. Both are now clamped
#      with an explicit warning.
#   e. FIXED: onset jitter of +/- trigStep/2 was clamped only at the
#      low end, so a last-column grain lost up to trigStep/2 of its
#      tail off the end of the buffer. Included in the allocation.
#   f. Header corrections: Position_warp direction was stated
#      backwards; "normalised energy" is threshold-normalised dB
#      strength; a grain is not "transposed to the bin frequency";
#      levels are re the trigger-grid peak, not the global peak;
#      "Energy-weighted" is RMS-weighted; grain duration tracks 1/f
#      only until the clamps bite; pan is not magnitude-modulated.
#
# CHANGELOG v1.0 -> v1.1
#   1. The form was too tall for a laptop screen: 26 fields and 5
#      comments. It is now 10 controls. Everything else moved into
#      Texture_preset (Sparse pointillist / Balanced cloud / Dense
#      wash / Shimmer / Custom) plus two optional beginPause dialogs,
#      Edit_analysis_settings and Edit_engine_settings, each shorter
#      than the main form. The dialogs are PRE-FILLED with the values
#      the chosen preset just set, so a preset stays inspectable and
#      editable rather than being a black box, and picking Custom
#      opens both automatically.
#      Two things this relies on: every variable a dialog creates is
#      already assigned by the preset block above it, or the
#      dialog-not-opened path dies on "Unknown variable"; and under
#      "praat --run" a pause block auto-continues with whatever it was
#      pre-filled with, so batch and headless use are unaffected
#      (verified: derived parameters identical with the dialogs forced
#      open and closed).
#   2. ADDED: Play. The rendered Sound is auditioned as soon as it is
#      selected, matching the rest of the library. Guarded with
#      "nocheck" so a machine with no audio device does not abort the
#      run after the render has already succeeded.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS DOES
#   Takes TWO Sounds. Sound A is analysed with a complex Morlet
#   continuous wavelet transform; Sound B supplies the actual audio.
#   Every significant cell of |CWT(t,f)| becomes a grain read out of
#   Sound B, transposed to the frequency of the wavelet bin that fired
#   it and shortened or lengthened in proportion to that bin's wavelet
#   scale. The result carries A's time-frequency morphology and B's
#   timbre - a cross-synthesis in the concatenative rather than the
#   filter-bank sense.
#
#   Companion to CWT_Scalogram.praat, which shares the analysis core.
#
# SIGNAL PATH
#   A -> mono -> complex Morlet CWT -> |CWT(t,f)| Matrix
#     -> resampled onto a coarse trigger grid (Trigger_step_ms x
#        Trigger_bands_per_octave), converted to dB re the global peak
#     -> optional 4-neighbour local-maximum mask (ridge points only)
#     -> threshold -> grain list
#   B -> mono -> oversampled -> read by each grain at its own rate
#     -> windowed, panned, summed into the output buffer
#
# HOW EACH CWT CELL MAPS TO A GRAIN
#   time      grain onset = the cell's time, plus jitter of up to half
#             a trigger step, so a dense column does not fire as one
#             hard transient.
#   pitch     playback rate = f_k / Reference_frequency_Hz, clamped to
#             +/- Transposition_range_st semitones. NOTE what this does
#             and does not mean: the CWT bin sets the playback-rate
#             RATIO relative to a user-chosen reference; it does not
#             transpose B to the bin's frequency. With a 220 Hz tone in
#             B, reference 440 and a bin at 880, the rate is 2 and the
#             tone lands on 440 Hz, not 880. The grain also stays as
#             broadband as B is - there is no bandpass around f_k.
#   duration  d_k = Base_grain_duration_ms * fGeo / f_k, where fGeo is
#             the geometric mean of the analysed range. This is the
#             s_k proportional-to-1/f_k relation of the Morlet scale
#             itself, so d_k * f_k is constant and a grain spans a
#             comparable number of cycles of the bin that triggered it
#             - UNTIL the 3-400 ms clamps bite. At the Balanced preset
#             (80-6000 Hz, base 60 ms) everything below 104 Hz is
#             pinned at 400 ms and no longer scales.
#   density   the expected number of grains from a cell is its
#             threshold-normalised dB STRENGTH - (dB - threshold) /
#             (0 - threshold), i.e. a linear position between the
#             threshold and the trigger-grid peak - times
#             Grain_density_multiplier, with the fractional part
#             realised stochastically. This is deliberately not energy
#             and not magnitude: at a -40 dB threshold a -20 dB cell
#             scores 0.5, where its magnitude ratio is 0.1 and its
#             energy ratio 0.01. Quiet cells therefore keep far more
#             presence than a linear reconstruction would give them.
#             Note also that |CWT| acts TWICE - once on how many grains
#             a cell fires and again on each grain's level - so this is
#             a nonlinear morphology mapping, not a linear resynthesis
#             of |CWT|.
#   position  where in B the grain is read. Sequential maps the cell's
#             position along A onto the same relative position in B
#             through u^Position_warp. 1 is linear; values ABOVE 1 hold
#             the read head near the start of B (mean read position
#             0.333 of B at warp 2) and values BELOW 1 push it towards
#             the end (0.667 at warp 0.5). v1.1's header had this
#             backwards. "Energy-weighted random" draws from B's RMS
#             profile - probability proportional to RMS, not to energy,
#             which would go as RMS squared; the name is kept for the
#             form but RMS is what is weighted.
#   pan       constant-power pan from a per-grain uniform draw scaled
#             by Pan_jitter. This is pure jitter: it is NOT modulated
#             by |CWT|.
#   level     the cell's linear magnitude relative to the TRIGGER-GRID
#             peak. Both the threshold and the grain level are
#             referenced to the trigger grid's own maximum, not the
#             fine analysis grid's; resampling onto a coarser grid can
#             only lower the maximum, so referencing to the fine peak
#             would put 0 dB out of reach.
#
# IMPLEMENTATION NOTES
#   - The CWT uses the vectorised path from CWT_Scalogram v1.1: one
#     "Create Sound from formula" per frequency bin rather than a
#     per-time-step script loop, then Concatenate -> Down to Matrix ->
#     one indexed Formula to assemble the magnitude Matrix.
#   - Grains are NOT extracted, resampled and concatenated. Each grain
#     is a single "Formula (part)" on the output buffer, touching only
#     its own samples:
#         self + gain * window(x) * object(srcB, tB + rate*(x - onset))
#     That is transposition, windowing, panning and overlap-add in one
#     command. object() returns 0 outside the referenced Sound's
#     domain, so no range guard is needed. Measured 0.58 ms per grain
#     for 30 ms grains at 44.1 kHz.
#   - object(id, x) interpolates LINEARLY, which for a transposed read
#     of real audio is the weak link AT RATES NEAR 1. Sound B is
#     therefore resampled once up front: measured error against an
#     exact reference on a 5 kHz tone was -37 dB at 1x, -50 dB at 4x
#     and -79 dB at 8x. 4x is the default.
#   - Oversampling does NOT address aliasing, which is the dominant
#     problem on pitch-up: reading B at rate r moves content above
#     outputNyquist/r past the output Nyquist, where it folds back.
#     Measured on v1.1 with an 8 kHz B at rate 4, 99.92 percent of the
#     output energy sat at the 12.1 kHz alias, identically at 1x, 4x
#     and 8x oversampling. v1.2 band-limits the source once per
#     half-octave rate group instead (see ANTI-ALIASED SOURCE COPIES).
#   - Both grain windows reach exactly zero at the grain edges, so
#     overlap-add introduces no step discontinuity. The Gaussian is
#     truncated at 2.5 sigma and offset-corrected; a raw Gaussian
#     would leave a 4.4% edge discontinuity.
#
# Requires Praat 6.1 or later. Verified on 6.4.06.
#
# Usage:
#   Select exactly TWO Sound objects, then run this script. The
#   Analysis_sound field decides which of the two is A.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# References:
#   Gabor, D. (1946). Theory of communication. Journal of the IEE,
#     93(26), 429-441.
#   Roads, C. (2001). Microsound. Cambridge, MA: MIT Press.
#   Torrence, C., & Compo, G. P. (1998). A practical guide to wavelet
#     analysis. BAMS, 79(1), 61-78.
#   Truax, B. (1988). Real-time granular synthesis with a digital
#     signal processor. Computer Music Journal, 12(2), 14-26.
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly two Sound objects: an analysis source and a grain source."
endif
sndFirst = selected("Sound", 1)
sndSecond = selected("Sound", 2)
nameFirst$ = selected$("Sound", 1)
nameSecond$ = selected$("Sound", 2)

form CWT Granular Resampler v1.2
    optionmenu Analysis_sound: 1
        option First selected is A
        option Second selected is A
    optionmenu Texture_preset: 2
        option Sparse pointillist
        option Balanced cloud
        option Dense wash
        option Shimmer (high, short grains)
        option Custom (opens both settings dialogs)
    positive Base_grain_duration_ms 60
    positive Transposition_range_st 24
    optionmenu Target_sample_mode: 1
        option Sequential
        option Energy-weighted random
    real Dry_wet 1.0
    boolean Draw_trigger_map 1
    boolean Play 1
    boolean Edit_analysis_settings 0
    boolean Edit_engine_settings 0
endform

# === PRESETS ===
# Everything not in the short form above is set here and then shown,
# pre-filled, in the optional dialogs below - so a preset stays
# inspectable and editable instead of being a black box.
if texture_preset = 1
    presetName$ = "Sparse pointillist"
    minimum_frequency_Hz = 80
    maximum_frequency_Hz = 6000
    voices_per_octave = 12
    time_step_s = 0.005
    omega0_bandwidth = 6
    trigger_step_ms = 30
    trigger_bands_per_octave = 3
    trigger_threshold_dB = -20
    peak_selection = 2
    grain_density_multiplier = 1.0
    reference_frequency_Hz = 440
    position_warp = 1.0
    position_jitter_ms = 20
    grain_window = 1
    stereo_output = 1
    pan_jitter = 0.5
    output_peak = 0.95
    source_oversampling = 3
    maximum_grains = 12000
    random_seed = 0
elsif texture_preset = 3
    presetName$ = "Dense wash"
    minimum_frequency_Hz = 60
    maximum_frequency_Hz = 8000
    voices_per_octave = 16
    time_step_s = 0.004
    omega0_bandwidth = 6
    trigger_step_ms = 12
    trigger_bands_per_octave = 6
    trigger_threshold_dB = -40
    peak_selection = 1
    grain_density_multiplier = 2.5
    reference_frequency_Hz = 440
    position_warp = 1.0
    position_jitter_ms = 25
    grain_window = 2
    stereo_output = 1
    pan_jitter = 0.6
    output_peak = 0.95
    source_oversampling = 3
    maximum_grains = 20000
    random_seed = 0
elsif texture_preset = 4
    presetName$ = "Shimmer"
    minimum_frequency_Hz = 300
    maximum_frequency_Hz = 10000
    voices_per_octave = 16
    time_step_s = 0.003
    omega0_bandwidth = 6
    trigger_step_ms = 10
    trigger_bands_per_octave = 6
    trigger_threshold_dB = -36
    peak_selection = 1
    grain_density_multiplier = 2.0
    reference_frequency_Hz = 880
    position_warp = 1.0
    position_jitter_ms = 8
    grain_window = 1
    stereo_output = 1
    pan_jitter = 0.7
    output_peak = 0.95
    source_oversampling = 3
    maximum_grains = 20000
    random_seed = 0
else
    if texture_preset = 5
        presetName$ = "Custom"
        edit_analysis_settings = 1
        edit_engine_settings = 1
    else
        presetName$ = "Balanced cloud"
    endif
    minimum_frequency_Hz = 80
    maximum_frequency_Hz = 6000
    voices_per_octave = 12
    time_step_s = 0.005
    omega0_bandwidth = 6
    trigger_step_ms = 20
    trigger_bands_per_octave = 4
    trigger_threshold_dB = -32
    peak_selection = 1
    grain_density_multiplier = 1.5
    reference_frequency_Hz = 440
    position_warp = 1.0
    position_jitter_ms = 15
    grain_window = 1
    stereo_output = 1
    pan_jitter = 0.4
    output_peak = 0.95
    source_oversampling = 3
    maximum_grains = 12000
    random_seed = 0
endif

# === OPTIONAL SETTINGS DIALOGS ===
# Split in two so neither is taller than the short form itself. Under
# "praat --run" a pause block auto-continues with whatever it was
# pre-filled with, i.e. the preset's own values, so batch use is
# unaffected. Every variable these dialogs create already exists above,
# which is what makes the not-opened path safe.
if edit_analysis_settings
    beginPause: "Analysis and triggers  [" + presetName$ + "]"
        comment: "Complex Morlet CWT of Sound A"
        positive: "Minimum_frequency_Hz", string$(minimum_frequency_Hz)
        positive: "Maximum_frequency_Hz", string$(maximum_frequency_Hz)
        positive: "Voices_per_octave", string$(voices_per_octave)
        positive: "Time_step_s", string$(time_step_s)
        positive: "Omega0_bandwidth", string$(omega0_bandwidth)
        comment: "Grain trigger extraction"
        positive: "Trigger_step_ms", string$(trigger_step_ms)
        positive: "Trigger_bands_per_octave", string$(trigger_bands_per_octave)
        real: "Trigger_threshold_dB", string$(trigger_threshold_dB)
        optionmenu: "Peak_selection", peak_selection
            option: "Spectral ridge (maxima across frequency)"
            option: "Local maxima (time and frequency)"
            option: "All cells above threshold"
    .clicked = endPause: "Cancel", "Continue", 2, 1
    if .clicked = 1
        exitScript: ""
    endif
endif

if edit_engine_settings
    beginPause: "Engine and output  [" + presetName$ + "]"
        comment: "Granular engine"
        positive: "Grain_density_multiplier", string$(grain_density_multiplier)
        positive: "Reference_frequency_Hz", string$(reference_frequency_Hz)
        real: "Position_warp", string$(position_warp)
        positive: "Position_jitter_ms", string$(position_jitter_ms)
        optionmenu: "Grain_window", grain_window
            option: "Hanning"
            option: "Gaussian"
        comment: "Output"
        boolean: "Stereo_output", stereo_output
        real: "Pan_jitter", string$(pan_jitter)
        positive: "Output_peak", string$(output_peak)
        comment: "Advanced"
        optionmenu: "Source_oversampling", source_oversampling
            option: "1x (fastest)"
            option: "2x"
            option: "4x (recommended)"
            option: "8x (best)"
        natural: "Maximum_grains", string$(maximum_grains)
        integer: "Random_seed", string$(random_seed)
    .clicked = endPause: "Cancel", "Continue", 2, 1
    if .clicked = 1
        exitScript: ""
    endif
endif

omega0 = omega0_bandwidth

if analysis_sound = 2
    sndA = sndSecond
    sndB = sndFirst
    nameA$ = nameSecond$
    nameB$ = nameFirst$
else
    sndA = sndFirst
    sndB = sndSecond
    nameA$ = nameFirst$
    nameB$ = nameSecond$
endif

if source_oversampling = 1
    ovFactor = 1
elsif source_oversampling = 2
    ovFactor = 2
elsif source_oversampling = 3
    ovFactor = 4
else
    ovFactor = 8
endif

if target_sample_mode = 2
    sampleModeName$ = "Energy-weighted random"
else
    sampleModeName$ = "Sequential"
endif
if grain_window = 2
    windowName$ = "Gaussian"
else
    windowName$ = "Hanning"
endif

dry_wet = max(0, min(1, dry_wet))
pan_jitter = max(0, min(1, pan_jitter))

# v1.2 (d). Two Custom-reachable values are degenerate rather than
# merely odd. Praat does not raise on either: 0/0 yields undefined,
# every comparison against undefined takes the FALSE branch, and the
# run ends with zero grains and a diagnostic blaming the density
# multiplier - a wrong answer is worse here than an error.
# Separate flag from value: the clamped value can itself be 0, so
# "was it clamped" cannot be encoded as "is it non-zero".
thresholdClamped = 0
thresholdWas = trigger_threshold_dB
if trigger_threshold_dB >= 0
    thresholdClamped = 1
    trigger_threshold_dB = -0.5
endif
warpClamped = 0
warpWas = position_warp
if position_warp <= 0
    warpClamped = 1
    position_warp = 0.01
endif

clearinfo
runClock = stopwatch
writeInfoLine: "=== CWT Granular Resampler v1.2 ==="
appendInfoLine: "A (analysis):    ", nameA$
appendInfoLine: "B (grain source): ", nameB$
appendInfoLine: "Preset:          ", presetName$
appendInfoLine: ""

if thresholdClamped
    appendInfoLine: "WARNING: Trigger_threshold_dB must be below 0 (it is relative to the trigger-grid"
    appendInfoLine: "  peak). ", fixed$(thresholdWas, 1), " dB clamped to -0.5 dB."
endif
if warpClamped
    appendInfoLine: "WARNING: Position_warp must be positive; ", fixed$(warpWas, 2),
        ... " clamped to 0.01. (0^0 = 1 and 0^-1 = undefined, either of which corrupts"
    appendInfoLine: "  the first read position.)"
endif
if random_seed <> 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    appendInfoLine: "RNG seeded with ", random_seed, " (reproducible)."
endif

# === PREPARE SOUND A ===
selectObject: sndA
nChA = Get number of channels
if nChA > 1
    workA = Convert to mono
else
    workA = Copy: "cwt_A"
endif
Rename: "cwt_A"
samplerate = Get sampling frequency
t0 = Get start time
t1 = Get end time
durA = t1 - t0
if durA <= 0
    removeObject: workA
    exitScript: "Sound A has zero duration."
endif

# === PREPARE SOUND B ===
selectObject: sndB
nChB = Get number of channels
if nChB > 1
    monoB = Convert to mono
else
    monoB = Copy: "grain_B"
endif
Rename: "grain_B_mono"
srB = Get sampling frequency
tB0 = Get start time
tB1 = Get end time
durB = tB1 - tB0
if durB <= 0
    removeObject: workA, monoB
    exitScript: "Sound B has zero duration."
endif

# Oversample B once so that the per-grain linear interpolation in
# object(srcB, x) is reading a denser grid. See IMPLEMENTATION NOTES.
if ovFactor > 1
    selectObject: monoB
    srcB = Resample: srB * ovFactor, 50
    Rename: "grain_B_src"
else
    selectObject: monoB
    srcB = Copy: "grain_B_src"
endif

# === CWT FREQUENCY AND TIME AXES ===
nyquist = samplerate / 2
if maximum_frequency_Hz >= nyquist
    appendInfoLine: "WARNING: maximum frequency clipped from ",
        ... fixed$(maximum_frequency_Hz, 0), " to ", fixed$(0.95 * nyquist, 0),
        ... " Hz (0.95 x Nyquist of Sound A)."
    maximum_frequency_Hz = 0.95 * nyquist
endif
if minimum_frequency_Hz >= maximum_frequency_Hz
    removeObject: workA, monoB, srcB
    exitScript: "Minimum frequency must be below the maximum frequency."
endif

max_nFreq = 400
max_nTime = 20000

freq_ratio = maximum_frequency_Hz / minimum_frequency_Hz
nFreq = round(voices_per_octave * log2(freq_ratio)) + 1
nFreq = max(4, min(max_nFreq, nFreq))
for k to nFreq
    freq_'k' = minimum_frequency_Hz * freq_ratio ^ ((k - 1) / (nFreq - 1))
endfor
logFmin = log2(minimum_frequency_Hz)
logFmax = log2(maximum_frequency_Hz)
dy = (logFmax - logFmin) / (nFreq - 1)
fGeo = sqrt(minimum_frequency_Hz * maximum_frequency_Hz)

nTime = floor(durA / time_step_s) + 1
nTime = max(2, nTime)
timeTruncated = 0
if nTime > max_nTime
    appendInfoLine: "WARNING: time grid capped at ", max_nTime, " steps; only the first ",
        ... fixed$(max_nTime * time_step_s, 2), " s of Sound A is analysed."
    nTime = max_nTime
    timeTruncated = 1
endif
tEnd = t0 + (nTime - 1) * time_step_s
anaDur = tEnd - t0

appendInfoLine: "CWT grid: ", nFreq, " bins (", fixed$(minimum_frequency_Hz, 1), "-",
    ... fixed$(maximum_frequency_Hz, 1), " Hz) x ", nTime, " steps of ",
    ... fixed$(time_step_s * 1000, 2), " ms"

magMatrix = Create Matrix: "cwt_magnitude", t0, tEnd, nTime, time_step_s, t0,
    ... logFmin, logFmax, nFreq, dy, logFmin, "0"

# === PROCEDURE: morletScale ===
procedure morletScale: .f
    .s = (omega0 + sqrt(2 + omega0 ^ 2)) / (4 * pi * .f)
endproc

# === PROCEDURE: computeCWT ===
# Vectorised analysis core, identical in method to CWT_Scalogram v1.1.
procedure computeCWT
    maxMag = 0
    appendInfo: "Computing CWT"
    .magXmin = t0 - time_step_s / 2
    .magXmax = .magXmin + nTime * time_step_s

    for .k to nFreq
        .f = freq_'.k'
        @morletScale: .f
        .s = morletScale.s
        .halfDur = 5 * .s
        .halfDur = max(3 / samplerate, min(durA / 2, .halfDur))
        halfDur_'.k' = .halfDur

        kernReal = Create Sound from formula: "kernReal", 1, -.halfDur, .halfDur, samplerate,
            ... "pi^(-0.25) / sqrt('.s') * cos('omega0'*x/'.s') * exp(-(x/'.s')^2/2)"
        kernImag = Create Sound from formula: "kernImag", 1, -.halfDur, .halfDur, samplerate,
            ... "pi^(-0.25) / sqrt('.s') * sin('omega0'*x/'.s') * exp(-(x/'.s')^2/2)"

        selectObject: workA, kernReal
        convReal = Convolve: "integral", "zero"
        selectObject: workA, kernImag
        convImag = Convolve: "integral", "zero"

        # Magnitude at the native rate, by raw sample index: both
        # convolutions share one grid, so this is exact. Only the
        # smooth envelope is resampled onto the output grid below.
        selectObject: convReal
        Formula: "sqrt(self^2 + object['convImag', 1, col]^2)"

        magSnd_'.k' = Create Sound from formula: "cwt_row", 1, .magXmin, .magXmax, 1 / time_step_s,
            ... "object('convReal', x)"
        .rowMax = Get maximum: 0, 0, "None"
        if .rowMax > maxMag
            maxMag = .rowMax
        endif

        removeObject: kernReal, kernImag, convReal, convImag
        if (.k mod 20) = 0
            appendInfo: "."
        endif
    endfor

    selectObject: magSnd_1
    for .k from 2 to nFreq
        plusObject: magSnd_'.k'
    endfor
    .catSnd = Concatenate
    .catMat = Down to Matrix
    selectObject: magMatrix
    Formula: "object['.catMat', 1, (row - 1) * 'nTime' + col]"
    removeObject: .catSnd, .catMat
    for .k to nFreq
        removeObject: magSnd_'.k'
    endfor
    appendInfoLine: " done"
endproc

@computeCWT

if maxMag < 1e-9
    removeObject: workA, monoB, srcB, magMatrix
    exitScript: "Sound A has no wavelet energy in this frequency range; nothing to trigger on."
endif

# === TRIGGER GRID ===
# The analysis grid is far finer than any sensible grain rate, so the
# magnitude Matrix is resampled (bilinear, via object(id, x, y)) onto a
# coarse time-frequency grid whose cells ARE the candidate grains.
trigStep = trigger_step_ms / 1000
nTrig = max(2, floor(anaDur / trigStep) + 1)
nBand = max(2, round(trigger_bands_per_octave * log2(freq_ratio)) + 1)
trigEnd = t0 + (nTrig - 1) * trigStep
dyB = (logFmax - logFmin) / (nBand - 1)
for b to nBand
    bandFreq_'b' = minimum_frequency_Hz * freq_ratio ^ ((b - 1) / (nBand - 1))
endfor

trigDb = Create Matrix: "trigger_dB", t0, trigEnd, nTrig, trigStep, t0,
    ... logFmin, logFmax, nBand, dyB, logFmin, "0"

# v1.2 (b). v1.1 filled this by POINT-SAMPLING the fine matrix -
# object(magMatrix, x, y), bilinear at the cell centre. With
# Time_step_s = 5 ms against Trigger_step_ms = 20, three of every four
# analysed columns were never looked at, and the wavelet half-support
# at 5 kHz is under 1 ms. Measured: a 5 kHz transient landing on a
# trigger centre read 0 dB; the same transient 10 ms away read
# -36.1 dB, i.e. below the default threshold, firing nothing. A fine
# Time_step_s bought nothing downstream.
# Now each trigger cell takes the MAXIMUM of every fine cell inside it,
# in both axes. Frequency pooling is one Sound per band built with a
# dynamic max(...) over that band's fine rows; time pooling is a
# "Get maximum: t1, t2" per trigger cell.
for .b to nBand
    .yc = logFmin + (.b - 1) * dyB
    .rLo = max(1, round((.yc - dyB / 2 - logFmin) / dy) + 1)
    .rHi = min(nFreq, round((.yc + dyB / 2 - logFmin) / dy) + 1)
    if .rHi < .rLo
        .rHi = .rLo
    endif
    .expr$ = "object['magMatrix', " + string$(.rLo) + ", col]"
    for .r from .rLo + 1 to .rHi
        .expr$ = "max(" + .expr$ + ", object['magMatrix', " + string$(.r) + ", col])"
    endfor
    .poolRow = Create Sound from formula: "poolRow", 1,
        ... t0 - time_step_s / 2, t0 - time_step_s / 2 + nTime * time_step_s,
        ... 1 / time_step_s, .expr$
    for .i to nTrig
        .ta = t0 + (.i - 1.5) * trigStep
        .tb = t0 + (.i - 0.5) * trigStep
        .ta = max(t0 - time_step_s / 2, .ta)
        .tb = min(tEnd + time_step_s / 2, .tb)
        .v = Get maximum: .ta, .tb, "None"
        if .v = undefined
            .v = 0
        endif
        poolVal_'.b'_'.i' = .v
    endfor
    removeObject: .poolRow
endfor
selectObject: trigDb
for .b to nBand
    for .i to nTrig
        Set value: .b, .i, poolVal_'.b'_'.i'
    endfor
endfor
# Reference the dB scale to the TRIGGER grid's own peak, not the fine
# analysis grid's. Resampling onto a coarser grid can only lower the
# maximum, so referencing to maxMag would put 0 dB out of reach: the
# threshold would bite harder than its number suggests and the
# normalised energy that drives grain density could never reach 1.
trigMax = Get maximum
if trigMax < 1e-12
    removeObject: workA, monoB, srcB, magMatrix, trigDb
    exitScript: "The trigger grid is empty. Try a smaller Trigger_step_ms."
endif
trigHeadroom = 20 * log10(trigMax / maxMag)
Formula: "20 * log10((self + 1e-12) / ('trigMax' + 1e-12))"

# 4-neighbour local maximum, computed against an untouched copy so the
# formula never reads a cell it has already overwritten. Indices are
# clamped rather than excluded, so edge cells compare against
# themselves and survive instead of being silently dropped.
# Ridge is the default because a full 4-neighbour local maximum in BOTH
# axes is very sparse - on a 201 x 26 grid it left 48 grains over 4 s.
# Testing across frequency only keeps the partial tracks (one or a few
# cells per time column) and is the usual wavelet-ridge criterion.
if peak_selection = 1
    peakName$ = "Spectral ridge"
    trigPeak = Copy: "trigger_peaks"
    Formula: "if self >= object['trigDb', max(row-1,1), col]
        ... and self >= object['trigDb', min(row+1,nrow), col]
        ... then self else -999 fi"
elsif peak_selection = 2
    peakName$ = "Local maxima (t,f)"
    trigPeak = Copy: "trigger_peaks"
    Formula: "if self >= object['trigDb', row, max(col-1,1)]
        ... and self >= object['trigDb', row, min(col+1,ncol)]
        ... and self >= object['trigDb', max(row-1,1), col]
        ... and self >= object['trigDb', min(row+1,nrow), col]
        ... then self else -999 fi"
else
    peakName$ = "All cells"
    selectObject: trigDb
    trigPeak = Copy: "trigger_peaks"
endif

# === ENERGY-WEIGHTED POSITION TABLE ===
# Inverse-CDF lookup over Sound B's RMS profile, built once. Sampling a
# position is then a single array read per grain rather than a search.
nPosBins = 400
nInv = 1024
if target_sample_mode = 2
    selectObject: monoB
    .tot = 0
    for .i to nPosBins
        .pa = tB0 + durB * (.i - 1) / nPosBins
        .pb = tB0 + durB * .i / nPosBins
        .r = Get root-mean-square: .pa, .pb
        if .r = undefined
            .r = 0
        endif
        posRms_'.i' = .r
        .tot += .r
    endfor
    if .tot <= 0
        appendInfoLine: "WARNING: Sound B is silent; falling back to Sequential positions."
        target_sample_mode = 1
        sampleModeName$ = "Sequential (B was silent)"
    else
        .cum = 0
        .bin = 1
        for .j to nInv
            .target = .tot * (.j - 0.5) / nInv
            while .cum + posRms_'.bin' < .target and .bin < nPosBins
                .cum += posRms_'.bin'
                .bin += 1
            endwhile
            invPos_'.j' = tB0 + durB * (.bin - 0.5) / nPosBins
        endfor
    endif
endif

# === BUILD THE GRAIN LIST ===
# One pass over the coarse grid. Every cell above threshold contributes
# an expected number of grains equal to its normalised energy times the
# density multiplier; the fractional part is realised stochastically,
# which is what makes overlap density follow |CWT(t,f)|.
minGrainDur = 0.003
maxGrainDur = 0.400
nGrain = 0
nCellsOverThreshold = 0
grainsClipped = 0
sumDur = 0
sumRate = 0
minSt = 1e9
maxSt = -1e9

selectObject: trigPeak
for .b to nBand
    .f = bandFreq_'.b'
    .d = base_grain_duration_ms / 1000 * fGeo / .f
    .d = max(minGrainDur, min(maxGrainDur, .d))
    .st = 12 * log2(.f / reference_frequency_Hz)
    .st = max(-transposition_range_st, min(transposition_range_st, .st))
    .rate = 2 ^ (.st / 12)
    bandDur_'.b' = .d
    bandRate_'.b' = .rate
    bandSt_'.b' = .st
    minSt = min(minSt, .st)
    maxSt = max(maxSt, .st)
endfor

# === ANTI-ALIASED SOURCE COPIES (v1.2 (a)) ===
# Reading Sound B at rate r moves its content up by r, so anything
# above outputNyquist/r folds back into the output. Measured on v1.1
# with an 8 kHz B at rate 4: 99.92 percent of the output energy sat at
# the 12.1 kHz alias, and source oversampling made NO difference at
# 1x, 4x or 8x - oversampling fixes interpolation error, not aliasing.
# Rendering the whole output at 4x and downsampling would cost about
# 4x the render time (measured 2x render = exactly 2x). Instead: the
# playback rate is constant per band, so band-limit the SOURCE once per
# half-octave rate group, cutoff = outputNyquist / the group's fastest
# rate. Rates only reach 2^(Transposition_range_st/12), so the default
# +/-24 st needs four groups.
nyqOut = samplerate / 2
for .g to 24
    srcForGroup_'.g' = 0
endfor
nFilters = 0
for .b to nBand
    .rate = bandRate_'.b'
    if .rate <= 1
        bandSrc_'.b' = srcB
    else
        # half-octave grouping: group g covers rates up to 2^(g/2)
        .g = max(1, min(24, ceiling(2 * log2(.rate))))
        if srcForGroup_'.g' = 0
            .cut = nyqOut / 2 ^ (.g / 2)
            if .cut >= nyqOut * 0.999
                srcForGroup_'.g' = srcB
            else
                selectObject: srcB
                srcForGroup_'.g' = Filter (pass Hann band): 0, .cut, 50
                Rename: "srcB_lp" + string$(.g)
                nFilters += 1
                filterCut_'.g' = .cut
            endif
        endif
        bandSrc_'.b' = srcForGroup_'.g'
    endif
endfor
if nFilters > 0
    appendInfoLine: "Anti-aliasing: ", nFilters, " band-limited copies of B (fastest rate ",
        ... fixed$(2 ^ (transposition_range_st / 12), 2), "x, lowest cutoff ",
        ... fixed$(nyqOut / 2 ^ (transposition_range_st / 12), 0), " Hz)."
endif

# v1.2 (c). v1.1 scanned chronologically and simply stopped adding
# grains at Maximum_grains, so breaching the cap did not thin the piece
# evenly - it kept the beginning of A intact and deleted the end
# outright. The expected total is deterministic (it does not depend on
# the per-cell coin flips), so a cheap first pass lets the cap be
# applied as a uniform keep factor across the whole duration instead.
# The anti-alias block above changed the object selection.
selectObject: trigPeak
sumExpected = 0
for .i to nTrig
    for .b to nBand
        .db = Get value in cell: .b, .i
        if .db >= trigger_threshold_dB
            sumExpected += (.db - trigger_threshold_dB) / (0 - trigger_threshold_dB)
        endif
    endfor
endfor
sumExpected *= grain_density_multiplier
densityScale = 1
if sumExpected > maximum_grains
    densityScale = maximum_grains / sumExpected
    appendInfoLine: "NOTE: ", fixed$(sumExpected, 0), " grains expected, cap is ", maximum_grains,
        ... ". Thinning uniformly by ", fixed$(100 * densityScale, 1),
        ... " percent rather than truncating the end of A."
endif

for .i to nTrig
    .tc = t0 + (.i - 1) * trigStep
    for .b to nBand
        .db = Get value in cell: .b, .i
        if .db >= trigger_threshold_dB
            nCellsOverThreshold += 1
            .e = (.db - trigger_threshold_dB) / (0 - trigger_threshold_dB)
            .e = max(0, min(1, .e))
            .expected = .e * grain_density_multiplier * densityScale
            .nRep = floor(.expected)
            if randomUniform(0, 1) < .expected - .nRep
                .nRep += 1
            endif
            for .rep to .nRep
                if nGrain >= maximum_grains
                    grainsClipped = 1
                else
                    nGrain += 1
                    .d = bandDur_'.b'
                    .rate = bandRate_'.b'
                    .onset = .tc + randomUniform(-trigStep / 2, trigStep / 2)
                    .onset = max(t0, .onset)

                    # Where in B to read. dRead is how much of B one
                    # grain consumes once transposed.
                    .dRead = .d * .rate
                    .room = max(0, durB - .dRead)
                    if target_sample_mode = 2
                        .jj = max(1, min(nInv, ceiling(randomUniform(0, 1) * nInv)))
                        .pos = invPos_'.jj' - tB0
                    else
                        .u = (.tc - t0) / anaDur
                        .u = max(0, min(1, .u)) ^ position_warp
                        .pos = .u * .room
                    endif
                    .pos += randomUniform(-position_jitter_ms / 1000, position_jitter_ms / 1000)
                    .pos = tB0 + max(0, min(.room, .pos))

                    .pan = randomUniform(-1, 1) * pan_jitter

                    grainT_'nGrain' = .onset
                    grainD_'nGrain' = .d
                    grainR_'nGrain' = .rate
                    grainP_'nGrain' = .pos
                    grainA_'nGrain' = 10 ^ (.db / 20)
                    grainPan_'nGrain' = .pan
                    grainBand_'nGrain' = .b
                    grainSrc_'nGrain' = bandSrc_'.b'
                    sumDur += .d
                    sumRate += .rate
                endif
            endfor
        endif
    endfor
endfor

if nGrain = 0
    removeObject: workA, monoB, srcB, magMatrix, trigDb, trigPeak
    # Distinguish the two ways this can happen: nothing passed the
    # threshold, or cells passed but the stochastic density rounded
    # every one of them down to zero grains.
    if nCellsOverThreshold = 0
        exitScript: "No trigger cell reached " + fixed$(trigger_threshold_dB, 1) +
            ... " dB. Lower Trigger_threshold_dB, loosen Peak_selection, or widen the frequency range."
    else
        exitScript: string$(nCellsOverThreshold) + " cell(s) passed the threshold but "
            ... + "Grain_density_multiplier (" + fixed$(grain_density_multiplier, 2) + ") "
            ... + "rounded every one down to zero grains. Raise it, or lower the threshold "
            ... + "so more cells contribute."
    endif
endif
if grainsClipped
    appendInfoLine: "WARNING: grain list truncated at Maximum_grains = ", maximum_grains,
        ... ". Raise the cap, raise the threshold, or lower the density multiplier."
endif
appendInfoLine: "Triggers: ", nGrain, " grains from ", nCellsOverThreshold,
    ... " of ", nTrig * nBand, " trigger cells (", peakName$, ")"

# A grain reads d*rate seconds of B. If B is shorter than that, the
# read runs off the end and object() returns 0 there, so the grain
# fades into silence rather than erroring - worth saying out loud.
meanRead = 0
for g to nGrain
    meanRead += grainD_'g' * grainR_'g'
endfor
meanRead /= nGrain
if durB < meanRead
    appendInfoLine: "WARNING: Sound B (", fixed$(durB, 3), " s) is shorter than the mean grain read length (",
        ... fixed$(meanRead, 3), " s). Grains will run past its end and tail into silence."
    appendInfoLine: "  Shorten Base_grain_duration_ms or use a longer Sound B."
endif

# === RENDER THE GRAIN CLOUD ===
# One "Formula (part)" per grain: transposition, window, pan and
# overlap-add in a single command over only that grain's own samples.
if stereo_output
    nCh = 2
else
    nCh = 1
endif
# v1.2 (e). Onset jitter is +/- trigStep/2 and was clamped only at the
# low end, so a last-column grain could end trigStep/2 past the buffer
# and lose its tail. Include the jitter in the allocation.
outDur = anaDur + maxGrainDur + trigStep / 2
outSnd = Create Sound from formula: "granular_" + nameA$ + "_x_" + nameB$, nCh,
    ... t0, t0 + outDur, samplerate, "0"

# Gaussian truncated at 2.5 sigma, offset so the edges are exactly 0.
gaussEdge = exp(-0.5 * 2.5 ^ 2)

appendInfo: "Rendering grains"
for g to nGrain
    .ts = grainT_'g'
    .d = grainD_'g'
    .te = .ts + .d
    .rate = grainR_'g'
    .pos = grainP_'g'
    .amp = grainA_'g'
    .pan = grainPan_'g'
    .sid = grainSrc_'g'

    if nCh = 2
        .gL = cos((.pan + 1) * pi / 4) * .amp
        .gR = sin((.pan + 1) * pi / 4) * .amp
        .gain$ = "(if row = 1 then '.gL' else '.gR' fi)"
    else
        .gL = .amp
        .gain$ = "'.gL'"
    endif

    if grain_window = 2
        .sig = .d / 5
        .mid = .ts + .d / 2
        .win$ = "max(0, (exp(-0.5*((x-'.mid')/'.sig')^2) - 'gaussEdge') / (1 - 'gaussEdge'))"
    else
        .win$ = "0.5*(1 - cos(2*pi*(x-'.ts')/'.d'))"
    endif

    selectObject: outSnd
    Formula (part): .ts, .te, 1, nCh,
        ... "self + " + .gain$ + " * " + .win$ + " * object('.sid', '.pos' + '.rate'*(x - '.ts'))"

    if (g mod 500) = 0
        appendInfo: "."
    endif
endfor
appendInfoLine: " done"

selectObject: outSnd
wetPeak = Get maximum: 0, 0, "None"
wetMin = Get minimum: 0, 0, "None"
wetPeak = max(wetPeak, -wetMin)
wetRms = Get root-mean-square: 0, 0

# === DRY / WET ===
# "Dry" is Sound A: the output shares A's time axis, B's does not.
if dry_wet < 1
    selectObject: workA
    dryPeak = Get maximum: 0, 0, "None"
    dryMin = Get minimum: 0, 0, "None"
    dryPeak = max(1e-9, max(dryPeak, -dryMin))
    .wetScale = dry_wet
    .dryScale = (1 - dry_wet) * max(1e-9, wetPeak) / dryPeak
    selectObject: outSnd
    Formula: "'.wetScale' * self + '.dryScale' * object('workA', x)"
endif

selectObject: outSnd
Scale peak: output_peak

# === REPORT HELPERS ===
procedure pad: .txt$, .w, .side$
    .out$ = .txt$
    while length(.out$) < .w
        if .side$ = "right"
            .out$ = " " + .out$
        else
            .out$ = .out$ + " "
        endif
    endwhile
    .s$ = .out$
endproc

# fixed$ returns "0" (not "0.0") for exact zero and overrides the
# requested precision for very small numbers, both of which wreck a
# column-aligned report. Round first, build the zero case by hand.
procedure fx: .v, .d
    if .v = undefined
        .s$ = "n/a"
    else
        .r = round(.v * 10 ^ .d) / 10 ^ .d
        if .r = 0
            .s$ = "0"
            if .d > 0
                .s$ = "0."
                for .i to .d
                    .s$ = .s$ + "0"
                endfor
            endif
        else
            .s$ = fixed$(.r, .d)
        endif
    endif
endproc

# === VISUALIZATION ===
procedure drawMap
    Erase all
    .canvasH = 6.98

    # --- Title strip ---
    Select inner viewport: 0.6, 7.7, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##CWT Granular Resampler##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... "A = " + replace$(nameA$, "_", "\_ ", 0) + "   |   B = " + replace$(nameB$, "_", "\_ ", 0)
        ... + "   |   " + string$(nGrain) + " grains"
        ... + "   |   " + sampleModeName$
        ... + "   |   " + windowName$ + " window"
        ... + "   |   " + presetName$

    # --- Panel 1: scalogram in dB with the grain triggers on top ---
    Select outer viewport: 0, 8, 0.58, 4.62
    Select inner viewport: 0.75, 7.70, 0.65, 4.10
    Axes: t0, tEnd, logFmin, logFmax
    selectObject: dbMatrix
    Paint image: t0, tEnd, logFmin, logFmax, trigger_threshold_dB - 12, 0

    Select inner viewport: 0.75, 7.70, 0.65, 4.10
    Axes: t0, tEnd, logFmin, logFmax
    # Praat has no "for ... step"; walk a counter instead.
    .stride = max(1, ceiling(nGrain / 6000))
    .nDots = floor((nGrain - 1) / .stride) + 1
    for .n to .nDots
        .g = 1 + (.n - 1) * .stride
        .rad = 0.25 + 0.55 * grainA_'.g'
        .bb = grainBand_'.g'
        @hotForAmp: grainA_'.g'
        Paint circle (mm): hotForAmp.col$, grainT_'.g', logFmin + (.bb - 1) * dyB, .rad
    endfor

    Select inner viewport: 0.75, 7.70, 0.65, 4.10
    Axes: t0, tEnd, logFmin, logFmax
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.75, 7.70, 0.65, 4.10
    Axes: t0, tEnd, logFmin, logFmax
    Font size: 7
    freqTicks# = { 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 }
    for .k to size(freqTicks#)
        .ft = freqTicks#[.k]
        if .ft >= minimum_frequency_Hz and .ft <= maximum_frequency_Hz
            if .ft >= 1000
                .flab$ = fixed$(.ft / 1000, 0) + "k"
            else
                .flab$ = fixed$(.ft, 0)
            endif
            One mark left: log2(.ft), "no", "yes", "no", .flab$
        endif
    endfor
    @niceStep: anaDur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text left: "yes", "Analysis frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # --- Panel 2: rendered output ---
    Select outer viewport: 0, 8, 4.68, 6.30
    Select inner viewport: 0.75, 7.70, 4.75, 5.78
    selectObject: outSnd
    .pk = Get maximum: 0, 0, "None"
    .mn = Get minimum: 0, 0, "None"
    .lim = max(1e-6, max(.pk, -.mn)) * 1.08
    Axes: t0, t0 + outDur, -.lim, .lim
    Colour: "{0.20, 0.40, 0.80}"
    selectObject: outSnd
    Draw: t0, t0 + outDur, -.lim, .lim, "no", "curve"

    # Praat's Sound "Draw:" STACKS the channels of a stereo Sound in
    # the panel, so a zero line and an amplitude scale in the panel's
    # own -lim..lim coordinates would sit in the wrong place on both
    # traces. Frame and time axis only.
    Select inner viewport: 0.75, 7.70, 4.75, 5.78
    Axes: t0, t0 + outDur, -.lim, .lim
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.75, 7.70, 4.75, 5.78
    Axes: t0, t0 + outDur, -.lim, .lim
    Font size: 7
    @niceStep: outDur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    if nCh = 2
        .olab$ = "Output (L / R)"
    else
        .olab$ = "Output"
    endif
    Text left: "no", .olab$
    Text bottom: "yes", "Time (s)"
    @fx: max(.pk, -.mn), 3
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: t0 + outDur - 0.01 * outDur, "right", 0.94 * .lim, "top", "peak " + fx.s$

    # --- Summary strip ---
    Select inner viewport: 0.6, 7.7, 6.41, 6.94
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    @fx: meanDur * 1000, 1
    .md$ = fx.s$
    @fx: overlap, 2
    .ov$ = fx.s$
    Text: 0.02, "left", 0.72, "half",
        ... "##Grains##  " + string$(nGrain) + "   mean duration " + .md$ + " ms"
        ... + "   mean overlap " + .ov$ + "x"
        ... + "   density x" + fixed$(grain_density_multiplier, 2)
        ... + "   threshold " + fixed$(trigger_threshold_dB, 1) + " dB"
        ... + "   " + peakName$
        ... + "   " + windowName$
    @fx: minSt, 1
    .a$ = fx.s$
    @fx: maxSt, 1
    Text: 0.02, "left", 0.28, "half",
        ... "##Mapping##  transposition " + .a$ + " to " + fx.s$ + " st"
        ... + " (ref " + fixed$(reference_frequency_Hz, 0) + " Hz)"
        ... + "   position " + sampleModeName$
        ... + "   warp " + fixed$(position_warp, 2)
        ... + "   pan jitter " + fixed$(pan_jitter, 2)
        ... + "   dry/wet " + fixed$(100 * dry_wet, 0) + "\%  "
    Select inner viewport: 0.6, 7.7, 6.41, 6.94
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, .canvasH
    Font size: 10
    Colour: "Black"
endproc

procedure hotForAmp: .v
    .v = max(0, min(1, .v))
    .col$ = "{" + fixed$(0.55 + 0.45 * .v, 3) + "," + fixed$(0.30 * (1 - .v), 3) + ",0.100}"
endproc

procedure niceStep: .range, .targetTicks
    .raw = .range / .targetTicks
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

meanDur = sumDur / nGrain
meanRate = sumRate / nGrain
overlap = sumDur / outDur

if draw_trigger_map
    selectObject: magMatrix
    dbMatrix = Copy: "cwt_dB"
    Formula: "20 * log10((self + 1e-12) / ('maxMag' + 1e-12))"
    @drawMap
    removeObject: dbMatrix
endif

# === REPORT ===
elapsed = stopwatch

appendInfoLine: ""
appendInfoLine: "--- GRAIN DISTRIBUTION BY OCTAVE ---"
@pad: "Octave (Hz)", 20, "left"
h$ = pad.s$
@pad: "grains", 9, "right"
h$ = h$ + pad.s$
@pad: "share", 9, "right"
h$ = h$ + pad.s$
@pad: "dur (ms)", 11, "right"
h$ = h$ + pad.s$
@pad: "transp (st)", 13, "right"
h$ = h$ + pad.s$
appendInfoLine: h$
appendInfoLine: "------------------------------------------------------------"

nOct = max(1, round(log2(freq_ratio)))
for o to nOct
    fLo = minimum_frequency_Hz * freq_ratio ^ ((o - 1) / nOct)
    fHi = minimum_frequency_Hz * freq_ratio ^ (o / nOct)
    cnt = 0
    dsum = 0
    stMin = 1e9
    stMax = -1e9
    for g to nGrain
        b = grainBand_'g'
        f = bandFreq_'b'
        if (f >= fLo and f < fHi) or (o = nOct and f = fHi)
            cnt += 1
            dsum += grainD_'g'
            stMin = min(stMin, bandSt_'b')
            stMax = max(stMax, bandSt_'b')
        endif
    endfor
    if cnt > 0
        @fx: fLo, 0
        lo$ = fx.s$
        @fx: fHi, 0
        @pad: lo$ + " - " + fx.s$, 20, "left"
        r$ = pad.s$
        @pad: string$(cnt), 9, "right"
        r$ = r$ + pad.s$
        @fx: 100 * cnt / nGrain, 1
        @pad: fx.s$ + "%", 9, "right"
        r$ = r$ + pad.s$
        @fx: 1000 * dsum / cnt, 1
        @pad: fx.s$, 11, "right"
        r$ = r$ + pad.s$
        @fx: stMin, 1
        s1$ = fx.s$
        @fx: stMax, 1
        @pad: s1$ + " to " + fx.s$, 13, "right"
        r$ = r$ + pad.s$
        appendInfoLine: r$
    endif
endfor
appendInfoLine: "------------------------------------------------------------"

w = 26
appendInfoLine: ""
appendInfoLine: "--- SYNTHESIS ---"
@fx: meanDur * 1000, 1
v$ = fx.s$
@pad: "Mean grain duration", w, "left"
appendInfoLine: pad.s$, v$, " ms"
@fx: overlap, 2
@pad: "Mean overlap", w, "left"
appendInfoLine: pad.s$, fx.s$, "x  (summed grain time / output time)"
@fx: nGrain / outDur, 1
@pad: "Mean grain rate", w, "left"
appendInfoLine: pad.s$, fx.s$, " grains/s"
@fx: minSt, 1
v$ = fx.s$
@fx: maxSt, 1
@pad: "Transposition span", w, "left"
appendInfoLine: pad.s$, v$, " to ", fx.s$, " st (ref ", fixed$(reference_frequency_Hz, 0), " Hz)"
@fx: meanRate, 3
@pad: "Mean playback rate", w, "left"
appendInfoLine: pad.s$, fx.s$, "x"
@fx: wetPeak, 4
v$ = fx.s$
@fx: wetRms, 4
@pad: "Wet peak / RMS", w, "left"
appendInfoLine: pad.s$, v$, " / ", fx.s$, " before scaling to ", fixed$(output_peak, 2)
@fx: durB, 2
@pad: "Sound B consumed", w, "left"
appendInfoLine: pad.s$, sampleModeName$, " over ", fx.s$, " s at ", ovFactor, "x oversampling"

appendInfoLine: ""
appendInfoLine: "--- COST ---"
@pad: "CWT grid", w, "left"
appendInfoLine: pad.s$, nFreq, " bins x ", nTime, " steps = ", nFreq * nTime, " cells"
@pad: "Trigger grid", w, "left"
appendInfoLine: pad.s$, nBand, " bands x ", nTrig, " steps = ", nBand * nTrig, " cells (",
    ... peakName$, ")"
@fx: trigHeadroom, 2
@pad: "Trigger-grid headroom", w, "left"
appendInfoLine: pad.s$, fx.s$, " dB below the fine-grid peak (dB are re the trigger grid)"
@fx: elapsed, 2
@pad: "Elapsed", w, "left"
appendInfoLine: pad.s$, fx.s$, " s"

# === CLEANUP ===
removeObject: workA, monoB, magMatrix, trigDb, trigPeak
for g to 24
    if srcForGroup_'g' <> 0 and srcForGroup_'g' <> srcB
        removeObject: srcForGroup_'g'
    endif
endfor
removeObject: srcB
selectObject: outSnd

if play
    # nocheck: a machine with no audio device should not abort the run
    # after the render has already succeeded.
    nocheck Play
endif

appendInfoLine: ""
appendInfoLine: "Done. Output Sound is selected in the Objects list."
