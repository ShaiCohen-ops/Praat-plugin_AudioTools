# ============================================================
# Praat AudioTools - Sidechain_Feedback_VCA.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.1 (2026) - tracking/spatial/visualization correctness fixes
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sidechain Feedback VCA - an ITERATIVE, sidechain-controlled resonant
#   texture generator. A buffer is repeatedly band-filtered, mixed back
#   into itself, soft-saturated and re-levelled; the controller's pitch
#   sets where the band sits, its intensity envelope shapes both the
#   loop gain and the output VCA, and Dry/Wet blends the controller back.
#
#   WHAT THIS IS AND IS NOT:
#   - There is no time-domain feedback. Each iteration filters the WHOLE
#     buffer, mixes it with the previous whole buffer, saturates and
#     repeats. `Iterations` is a computational axis outside audio time,
#     not laps of a signal around a physical circuit. The accurate
#     description is buffer-domain feedback resynthesis.
#   - Nothing self-oscillates from nothing. With Excitation_Source =
#     "Noise seed", the loop is explicitly seeded with noise and the
#     output is normalized, so a silent controller still yields a full
#     level ring. That is a no-input-mixer AESTHETIC, not a system
#     crossing a threshold into oscillation.
#   - The intensity envelope is mapped RELATIVE to the loudest moment in
#     the selected file, so it tracks dynamics WITHIN a file but not
#     absolute level BETWEEN files.
#
# ============================================================
# Changelog v0.6.1 (2026):
#   - FIX: pitch-tracked resonance now builds an explicit offset/clamped
#     resonance trajectory and limits per-iteration drift so carrier +
#     heterodyne low-pass bandwidth stays below Nyquist.
#   - FIX: tracking visualization now plots the actual resonance trajectory
#     (including Frequency_Offset_Hz) and iteration drift statistics include
#     that same trajectory rather than the raw mean F0.
#   - FIX: Drive = 0 is a true linear saturator bypass. All Drive values > 0
#     retain the v0.6 arctan mapping.
#   - FIX: Rotating spatial mode now downmixes the wet path to one mono
#     source and derives a true constant-power stereo pan from it. Pan phase
#     is relative to the Sound start time, not Praat's absolute x origin.
#   - SAFETY: Stereo_spread_percent is capped at 95%, with detuned centres
#     and filter edges constrained to the available 20 Hz..Nyquist region.
#   - VIS: the result overlay now draws the actual RMS envelope (not RMS*sqrt(2)).
#
# Changelog v0.6 (2026) - WHY THE OUTPUT SOUNDED BAD, AND WHAT CHANGED
#
#   Measured on a 4 s controller (five notes, 145/194/167/264/129 Hz,
#   33 dB of dynamic range), Praat 6.4.06 headless, seed 7.
#
#   1. THE LOOP HAD NO STABLE OPERATING POINT.
#      In-band gain was ~1.9 per iteration (damping 0.92 + VCA ~1.0)
#      with nothing holding the level between iterations, so the loop
#      peak ran 0.00005 -> 0.639 over 40 iterations, i.e. the character
#      was decided by an exponential in `Iterations`, not by any
#      parameter that names a character. At the Aggressive preset
#      (50 iterations) the output crest factor fell to 5.4 dB with 5.5%
#      of samples pinned near peak - a brick of arctan saturation. At
#      Gentle (30) the loop never got off the floor and `Scale peak`
#      simply amplified the seed noise. Nothing in between was reliable.
#      FIX: the loop is re-levelled to a fixed working peak after every
#      iteration, and the saturator is now a unity-slope soft clip
#      (arctan(g*u)/g) whose hardness is set by the new `Drive` control.
#      Base_Feedback and Damping_Factor now shape TIMBRE - how much of
#      each pass is band-limited - instead of secretly setting gain.
#
#   2. THE ENVELOPE WAS EXPONENTIATED, NOT APPLIED.
#      The VCA multiplied the loop once per iteration, so the audible
#      depth was vca(t)^iterations. Measured: 33 dB of controller
#      dynamics came back as 63 dB of output dynamics (1.92 dB out per
#      dB in). Quiet notes disappeared; Input_Sensitivity behaved as an
#      exponent. FIX: the in-loop modulation is now de-exponentiated -
#      the per-iteration deviation is the requested depth divided by the
#      iteration count - and the audible dynamics come from an explicit
#      post-loop VCA calibrated in dB (`Sidechain_depth_dB`). Measured on
#      the same controller, the control is now linear: 12 dB gives 0.30 dB
#      out per dB in, 24 dB gives 0.60, 36 dB gives 0.89. The default is
#      24 dB.
#
#   3. IT ANSWERED EVERY INPUT WITH THE SAME NOTE.
#      The resonance centre was the MEAN pitch of the whole file. The
#      test controller moves 145 -> 194 -> 167 -> 264 -> 129 Hz; the
#      output sat at 167-188 Hz throughout. FIX: new
#      `Resonance_Tracking` = "Follow pitch contour" replaces the fixed
#      FFT band with a heterodyne band-pass - the buffer is mixed down
#      by the instantaneous pitch phase, low-passed, and mixed back up -
#      so the resonance glides with the controller. Costs one extra
#      filter pass per iteration. "Fixed (mean F0)" keeps the old
#      behaviour.
#
#   4. THE CONTROLLER'S RHYTHM WAS INAUDIBLE.
#      The only excitation was stationary noise across the whole buffer,
#      so there were no attacks - every render was a slab of drone.
#      FIX: new `Excitation_Source` lets the controller itself excite
#      the loop ("Controller" or "Both"), which restores onsets,
#      articulation and pitch for free. "Noise seed" keeps the pure
#      no-input aesthetic.
#
#   5. THE EXCITER WAS A SEPARATE WHISTLE, NOT AIR.
#      The loop has essentially no energy above ~400 Hz; the old
#      ring-modulator at 20x the resonance dumped a band whose energy
#      above 2 kHz was ~6 orders of magnitude larger than the loop's
#      own. It sat on top of the sound instead of brightening it.
#      FIX: the exciter is now a band-limited cubic waveshaper (the
#      source is low-passed to Nyquist/3 first, so nothing folds),
#      high-passed at twice the resonance and RMS-matched to the source,
#      so High_Freq_Add is a predictable amount of harmonically
#      continuous air.
#
#   6. PRESETS WERE NOT COMPARABLE.
#      All modes peak-normalize to 0.95, but at identical peak the RMS
#      ranged 0.07 (Gentle) to 0.51 (Aggressive) - a 7x loudness spread
#      that made A/B of presets meaningless. FIX: new Output_mode
#      "Match loudness (RMS target)" normalizes to an RMS target with a
#      peak guard, and is the new default: preset RMS spread measured
#      7.09x before, 1.00x after. Preset values retuned for the new gain
#      structure, so they now differ in timbre rather than level (measured
#      spectral centroid 393 / 1338 / 2733 / 3057 Hz for Gentle / Deep
#      Iteration / Aggressive / Unstable). The Aggressive preset went from
#      a 5.4 dB crest factor with 5.5% of samples pinned near peak to
#      9.4 dB and 0.7%.
#
#   7. SPATIAL MODES. "Rotating" was two amplitude LFOs 90 degrees
#      apart, which is level pumping, not rotation (cos and sin
#      amplitudes do not sum to constant power); it is now a
#      constant-power pan. "Stereo Wide" split L=lows / R=highs on a
#      signal whose energy is all in one narrow band, which made the two
#      channels unbalanced copies; it is now a detuned twin resonance
#      (new `Stereo_spread_percent`), which decorrelates a drone the way
#      two slightly detuned circuits would.
#
#   8. Edge fades (`Fade_ms`) - the loop is steady-state from sample 0,
#      so every render used to begin and end on a discontinuity.
#
#   9. VISUALIZATION REPLACED. The block diagram and arrows are gone.
#      The figure is now five measurement panels: controller and output
#      waveforms with their RMS envelopes, the control trajectory over
#      time (pitch contour, resonance band, VCA envelope), the
#      per-iteration convergence of the loop (peak, RMS, band centre),
#      and input vs output spectra on a log axis.
#
#   COST: pitch tracking costs one extra filter pass per iteration; with
#   the lower default iteration count a 4 s stereo render measured 6.7 s
#   against 3.3 s for v0.5.x (Praat 6.4.06 headless). Use "Fixed (mean F0)"
#   for the old speed.
#
#   VERIFIED: 19 configurations (silent / 30 ms / stereo / 4-channel /
#   non-zero start time inputs, all four spatial modes, all four output
#   modes, all four presets, Iterations = 1, Dry_Wet = 1, exciter off)
#   render without error on Praat 6.4.06. Output is bit-identical on
#   6.1.38 and 6.4.06 (peak 0.83000025, rms 0.09950203); Praat 7.0 differs
#   in the fourth decimal of the peak.
#
#   BREAKING: `Allow_negative_VCA` is removed (a negative
#   Input_Sensitivity already inverts the envelope, and the new
#   formulation is a dB offset, not a signed multiplier). Three fields
#   are added to the first form, so positional `runScript:` calls from
#   v0.5.x must be updated. New first-form order is listed at the top of
#   the form block below.
#
# Changelog v0.5.1 (2026):
#   - Analog_Instability accepts 0; negative values refused explicitly.
#   - Output mode 1 normalizes again immediately after a wet-path exciter.
#   - Spatial mode "Binaural" renamed "Pseudo-Binaural (Delay/Filter)".
#   - "Slow Evolution" / "Chaotic Burst" renamed "Deep Iteration" /
#     "Unstable Burst".
#   - Output mode 3 renamed "Preserve rendered level".
#
# Changelog v0.4b / v0.4c (retained in v0.6.1):
#   - Absolute silence threshold at -150 dB holds the envelope at 0.
#   - "Use the first two channels" policy no longer crashes.
#   - Second settings dialog uses beginPause (Praat allows one form).
#   - Seed band clamped to Nyquist; effective edges reported.
#   - Resonance centre validated against 20 Hz and Nyquist.
#   - Interaural delay specified in ms, not samples.
#   - Random seed for reproducible runs.
# ============================================================

# --- First form. Positional order for runScript: -------------
#  1 Preset            2 Excitation_Source   3 Resonance_Tracking
#  4 Base_Feedback     5 Input_Sensitivity   6 Envelope_range_dB
#  7 Damping_Factor    8 Iterations          9 Drive
# 10 Frequency_Offset_Hz  11 Bandwidth_Hz   12 Analog_Instability
# 13 Sidechain_depth_dB   14 Dry_Wet        15 Exciter_position
# 16 High_Freq_Add
# -------------------------------------------------------------

form Sidechain Feedback VCA v0.6.1 (1/2) - Circuit & Resonance
    comment Select a Sound object - it CONTROLS the iterative resonant process

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Resonance
        option Aggressive Feedback
        option Deep Iteration
        option Unstable Burst

    comment === What excites the loop ===
    optionmenu Excitation_Source 3
        option Noise seed only (no-input aesthetic)
        option Controller into the loop
        option Both (noise + controller)

    comment === Where the resonance sits ===
    optionmenu Resonance_Tracking 2
        option Fixed (mean F0 of the whole file)
        option Follow pitch contour (heterodyne, ~2x slower)

    comment === Circuit Behavior ===
    positive Base_Feedback 0.8
    real Input_Sensitivity 0.5
    comment (positive = louder moments resonate more; negative inverts)
    positive Envelope_range_dB 40
    comment (dB below the loudest moment that maps to 0)
    positive Damping_Factor 0.92
    natural Iterations 24
    real Drive 0.45
    comment (0 = clean linear bypass, 1 = hard soft-clip; the loop is re-levelled each pass)

    comment === Resonance ===
    real Frequency_Offset_Hz 0.0
    positive Bandwidth_Hz 180
    real Analog_Instability 0.05

    comment === Sidechain (audible output VCA, in dB) ===
    real Sidechain_depth_dB 24.0

    comment === Dry / Wet (0 = generated iteration path, 1 = dry path only) ===
    real Dry_Wet 0.3
    optionmenu Exciter_position: 1
        option After the dry/wet mix
        option On the wet path only

    comment === Synthetic high frequencies / air (0 = off) ===
    real High_Freq_Add 0.3
endform

# NOTE: Praat allows ONE "form ... endform" block per script run, so the
# remaining settings open in a beginPause/endPause dialog below.

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object to act as the controller."
endif

original = selected("Sound")
input_Name$ = selected$("Sound")

# === Second dialog (Spatial, Output & Debug) ===
beginPause: "Sidechain Feedback VCA v0.6.1 (2/2) - Spatial, Output & Debug"
    comment: "=== Spatial Mode ==="
    optionmenu: "Spatial_Mode", 2
        option: "Mono"
        option: "Stereo Wide"
        option: "Rotating"
        option: "Pseudo-Binaural (Delay/Filter)"
    positive: "Stereo_spread_percent", "1.2"
    comment: "(Stereo Wide: detune between the left and right resonance)"
    positive: "Interaural_delay_ms", "0.68"
    comment: "(Pseudo-Binaural mode; interaural delay + asymmetric filtering, no HRTF)"
    optionmenu: "Multichannel_policy", 1
        option: "Downmix to mono, then duplicate"
        option: "Use the first two channels"
        option: "Refuse more than 2 channels"
    comment: "=== Output ==="
    optionmenu: "Output_mode", 4
        option: "Normalize each stage to 0.95 (v0.3 legacy)"
        option: "Normalize only at the end"
        option: "Preserve rendered level (output gain only)"
        option: "Match loudness (RMS target, peak-guarded)"
    real: "Target_RMS_dBFS", "-20.0"
    positive: "Output_Gain", "1.0"
    real: "Fade_ms", "15.0"
    integer: "Random_seed", "0"
    comment: "(0 or below = unpredictable; positive = reproducible)"
    boolean: "Draw_visualization", 1
    boolean: "Play_result", 1
    comment: "=== Debug (logs per-stage levels to the Info window) ==="
    boolean: "Debug", 0
clicked = endPause: "Continue", 1

selectObject: original
duration = Get total duration
sr = Get sampling frequency
n_channels = Get number of channels
xminOrig = Get start time
xmaxOrig = Get end time
srcPeak = Get absolute extremum: 0, 0, "None"
nyquist = sr / 2

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
    seedDesc$ = string$(random_seed) + " (reproducible)"
else
    random_initializeSafelyAndUnpredictably()
    seedDesc$ = "none (this run is NOT reproducible)"
endif

if dry_Wet < 0 or dry_Wet > 1
    exitScript: "Dry_Wet must be between 0 and 1 (got " + fixed$(dry_Wet, 3) + ")."
endif
if preset = 1 and analog_Instability < 0
    exitScript: "Analog_Instability must be 0 or above (got " + fixed$(analog_Instability, 4) + ")."
endif
if preset = 1 and (drive < 0 or drive > 1)
    exitScript: "Drive must be between 0 and 1 (got " + fixed$(drive, 3) + ")."
endif

# Stereo Wide is a detuned twin-resonance effect. Beyond 95% the lower
# centre approaches/ crosses DC and no longer behaves as a useful detune.
stereoSpreadWasClamped = 0
if stereo_spread_percent > 95
    stereo_spread_percent = 95
    stereoSpreadWasClamped = 1
endif

# To Intensity at a 100 Hz minimum pitch needs 6.4/100 = 64 ms of signal;
# To Pitch at a 75 Hz floor needs about 3/75 = 40 ms. Rather than abort,
# fall back to fixed control values and say so.
minPitchDur = 3 / 75
minIntensityDur = 6.4 / 100
shortFile = 0
if duration < minIntensityDur or duration < minPitchDur
    shortFile = 1
endif

if n_channels > 2 and multichannel_policy = 3
    exitScript: "The controller has " + string$(n_channels)
        ... + " channels. Choose a different Multichannel_policy, or reduce the input to mono or stereo."
endif

# ============================================================
# HELPERS
# ============================================================

# --- Synthetic high frequencies (harmonic air) ---------------
# v0.6: band-limited cubic waveshaping instead of ring modulation. The
# source is low-passed to Nyquist/3 before cubing so the third-harmonic
# products land at or below Nyquist and nothing folds; the result is
# high-passed and RMS-matched to the source, so High_Freq_Add is an
# amount rather than a level.
procedure exciter: .target
    .lpTop = nyquist / 3
    .hpLow = 2 * resonance_Center
    if .hpLow < 1200
        .hpLow = 1200
    endif
    if .hpLow > nyquist * 0.6
        .hpLow = nyquist * 0.6
    endif

    selectObject: .target
    .srcRms = Get root-mean-square: 0, 0
    Copy: "exciter_src"
    .raw = selected("Sound")
    Filter (pass Hann band): 20, .lpTop, 100
    .lp = selected("Sound")
    removeObject: .raw

    selectObject: .lp
    .lpPk = Get absolute extremum: 0, 0, "None"
    if .lpPk > 1e-9
        Scale peak: 0.9
    endif
    Formula: "self * self * self"
    Filter (pass Hann band): .hpLow, nyquist, 200
    .high = selected("Sound")
    removeObject: .lp

    selectObject: .high
    .hRms = Get root-mean-square: 0, 0
    if .hRms > 1e-9 and .srcRms > 1e-9
        Formula: "self * " + string$(.srcRms / .hRms)
    endif

    selectObject: .target
    .exc$ = string$(.high)
    .amt$ = string$(high_Freq_Add)
    Formula: "self + object[" + .exc$ + ", row, col] * " + .amt$
    removeObject: .high
    exciterDesc$ = "cubic shaper, source low-passed at " + fixed$(.lpTop, 0)
        ... + " Hz, air band above " + fixed$(.hpLow, 0) + " Hz, RMS-matched"
endproc

# --- Heterodyne band-pass that tracks the pitch contour -------
# Mix the buffer down by the instantaneous pitch phase, low-pass the
# in-phase and quadrature parts, mix back up. The result is a band-pass
# whose centre follows f0(t) - which a whole-buffer FFT filter cannot do.
procedure trackBP: .src, .fac, .cutoff
    .f$ = string$(.fac)
    .ph$ = string$(phaseSound)
    .cut = .cutoff
    if .cut < 8
        .cut = 8
    endif
    if .cut > nyquist * 0.4
        .cut = nyquist * 0.4
    endif
    .sm = .cut / 3
    if .sm < 4
        .sm = 4
    endif

    selectObject: .src
    Copy: "het_I"
    .ci = selected("Sound")
    Formula: "self * cos(" + .f$ + " * object[" + .ph$ + ", 1, col])"
    Filter (pass Hann band): 0, .cut, .sm
    .ciF = selected("Sound")
    removeObject: .ci

    selectObject: .src
    Copy: "het_Q"
    .cq = selected("Sound")
    Formula: "self * sin(" + .f$ + " * object[" + .ph$ + ", 1, col])"
    Filter (pass Hann band): 0, .cut, .sm
    .cqF = selected("Sound")
    removeObject: .cq

    selectObject: .ciF
    .q$ = string$(.cqF)
    Formula: "2 * (self * cos(" + .f$ + " * object[" + .ph$ + ", 1, col]) + object[" + .q$
        ... + ", 1, col] * sin(" + .f$ + " * object[" + .ph$ + ", 1, col]))"
    removeObject: .cqF
    trackBP.out = .ciF
endproc

procedure dbg: .lbl$
    if debug
        .pk = Get absolute extremum: 0, 0, "None"
        .ns = Get number of samples
        .nc = Get number of channels
        if .pk = undefined
            appendInfoLine: "  [DBG] ", .lbl$, ": *** UNDEFINED / NaN *** (samples=", .ns, ", channels=", .nc, ")"
        else
            appendInfoLine: "  [DBG] ", .lbl$, ": peak=", fixed$(.pk, 4), "  samples=", .ns, "  channels=", .nc
        endif
    endif
endproc

# Escape a machine-generated string for the Picture window.
procedure viz: .s$
    .t$ = replace$(.s$, "\", "\bs", 0)
    .t$ = replace$(.t$, "_", "\_ ", 0)
    .t$ = replace$(.t$, "#", "\# ", 0)
    .t$ = replace$(.t$, "%", "\% ", 0)
    .t$ = replace$(.t$, "^", "\^ ", 0)
    viz.out$ = .t$
endproc

# ============================================================
# PRESETS
# ============================================================
# Retuned for the v0.6 gain structure: with the loop re-levelled every
# pass, Iterations is a shaping depth rather than an exponent, so the
# counts are lower and Drive carries the aggression.
if preset = 2
    base_Feedback = 0.50
    input_Sensitivity = 0.30
    damping_Factor = 0.90
    iterations = 18
    bandwidth_Hz = 260
    analog_Instability = 0.03
    drive = 0.25
    presetName$ = "Gentle"
elsif preset = 3
    base_Feedback = 0.95
    input_Sensitivity = 0.70
    damping_Factor = 0.80
    iterations = 30
    bandwidth_Hz = 120
    analog_Instability = 0.08
    drive = 0.70
    presetName$ = "Aggressive"
elsif preset = 4
    base_Feedback = 0.75
    input_Sensitivity = 0.40
    damping_Factor = 0.95
    iterations = 60
    bandwidth_Hz = 300
    analog_Instability = 0.02
    drive = 0.35
    presetName$ = "DeepIteration"
elsif preset = 5
    base_Feedback = 0.95
    input_Sensitivity = 0.90
    damping_Factor = 0.75
    iterations = 26
    bandwidth_Hz = 90
    analog_Instability = 0.18
    drive = 0.85
    presetName$ = "UnstableBurst"
else
    presetName$ = "Custom"
endif

if drive < 0
    drive = 0
endif
if drive > 1
    drive = 1
endif

writeInfoLine: "=== Sidechain Feedback VCA v0.6.1 ==="
appendInfoLine: "Controller: ", input_Name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$, "  |  Excitation: ", excitation_Source$
appendInfoLine: "Resonance: ", resonance_Tracking$
if stereoSpreadWasClamped
    appendInfoLine: "NOTE: Stereo_spread_percent was capped at 95% for a valid detuned-twin resonance."
endif
appendInfoLine: ""

# ============================================================
# FEATURE EXTRACTION
# ============================================================

appendInfoLine: "Extracting control features..."

# --- A. Pitch: centre frequency, spread, and (optionally) contour ---
f0Sound = 0
phaseSound = 0
trackingFreqSound = 0
pitchSpreadLow = 0
pitchSpreadHigh = 0

if shortFile
    mean_Pitch = 100
    pitchSpreadLow = 100
    pitchSpreadHigh = 100
    appendInfoLine: "  Controller is ", fixed$(duration * 1000, 1),
        ... " ms - too short for pitch analysis. Using 100 Hz."
else
    selectObject: original
    if n_channels > 1
        Convert to mono
        tempMono = selected("Sound")
        To Pitch: 0.0, 75, 600
        pitch = selected("Pitch")
        removeObject: tempMono
    else
        To Pitch: 0.0, 75, 600
        pitch = selected("Pitch")
    endif

    selectObject: pitch
    mean_Pitch = Get mean: 0, 0, "Hertz"
    pitchSpreadLow = Get quantile: 0, 0, 0.10, "Hertz"
    pitchSpreadHigh = Get quantile: 0, 0, 0.90, "Hertz"

    if mean_Pitch = undefined
        mean_Pitch = 100
        appendInfoLine: "  No pitch detected. Defaulting resonance to 100 Hz."
    else
        appendInfoLine: "  Mean F0 ", fixed$(mean_Pitch, 1), " Hz  |  10-90% spread ",
            ... fixed$(pitchSpreadLow, 1), " - ", fixed$(pitchSpreadHigh, 1), " Hz"
    endif
    if pitchSpreadLow = undefined
        pitchSpreadLow = mean_Pitch
    endif
    if pitchSpreadHigh = undefined
        pitchSpreadHigh = mean_Pitch
    endif

    # Contour as a Sound at the audio rate, for the tracking filter and
    # for the figure. Interpolate fills unvoiced frames; the guards below
    # replace anything the interpolation and the resampler leave behind.
    selectObject: pitch
    Interpolate
    pitchInterp = selected("Pitch")
    Smooth: 10
    pitchSmooth = selected("Pitch")
    To Matrix
    pitchMatrix = selected("Matrix")
    To Sound
    f0Raw = selected("Sound")
    mp$ = string$(mean_Pitch)
    # Unvoiced frames arrive as 0. Substituting the file mean makes the
    # resonance leap to the global average the moment a note dies away, so
    # the last valid value is held forward instead (an in-place formula
    # reads the value the same pass has already written, which is exactly
    # what a sample-and-hold wants); only a leading gap falls back to mean.
    Formula: "if self < 60 or self = undefined then 0 else self fi"
    Formula: "if self = 0 and col > 1 then self[col-1] else self fi"
    Formula: "if self = 0 then " + mp$ + " else self fi"
    Resample: sr, 50
    f0Sound = selected("Sound")
    removeObject: pitchInterp, pitchSmooth, pitchMatrix, f0Raw
    removeObject: pitch

    selectObject: f0Sound
    f0Cap = nyquist * 0.40
    Formula: "if self < 60 or self = undefined then " + mp$ + " else self fi"
    Formula: "if self > " + string$(f0Cap) + " then " + string$(f0Cap) + " else self fi"
    # Resampling can still ring a few samples at the very edges.
    if duration > 0.2
        headV = Get value at time: 1, xminOrig + 0.05, "Linear"
        tailV = Get value at time: 1, xmaxOrig - 0.05, "Linear"
        if headV = undefined
            headV = mean_Pitch
        endif
        if tailV = undefined
            tailV = mean_Pitch
        endif
        Formula (part): xminOrig, xminOrig + 0.02, 1, 1, string$(headV)
        Formula (part): xmaxOrig - 0.02, xmaxOrig, 1, 1, string$(tailV)
    endif
endif

# --- B. Intensity: the sidechain envelope, mapped to 0..1 ------------
# The dB values are mapped across a window ending at the file's loudest
# moment and reaching Envelope_range_dB below it: silence lands at 0, the
# loudest moment at 1, monotonic in level throughout.
if shortFile
    appendInfoLine: "  Controller too short for intensity analysis. Envelope held at 1 (no modulation)."
    Create Sound from formula: "env_flat", 1, xminOrig, xmaxOrig, sr, "1"
    envSound = selected("Sound")
    envDesc$ = "constant 1 (file too short to analyse)"
else
    # v0.6: map dB -> 0..1 on the LOW-RATE intensity signal and resample
    # afterwards. v0.5 resampled first, and the dB signal swings from about
    # +95 dB on a note to -300 dB in the gaps, so the resampler rang wildly
    # across those steps and the clamp turned the ringing into an envelope
    # that flickered between 0 and 1 several times per note.
    selectObject: original
    To Intensity: 100, 0, "yes"
    intensity = selected("Intensity")
    Down to Matrix
    matrix = selected("Matrix")
    To Sound
    controlRaw = selected("Sound")
    removeObject: intensity, matrix

    selectObject: controlRaw
    maxDb = Get maximum: 0, 0, "None"

    silenceFloorDb = -150
    if maxDb < silenceFloorDb
        Formula: ~ 0
        envDesc$ = "controller is silent (peak intensity " + fixed$(maxDb, 1) + " dB) - envelope held at 0"
        appendInfoLine: "  Intensity envelope: ", envDesc$
    else
        floorDb = maxDb - envelope_range_dB
        spanDb = maxDb - floorDb
        if spanDb < 1
            spanDb = 1
        endif
        Formula: "(self - " + string$(floorDb) + ") / " + string$(spanDb)
        Formula: ~ if self < 0 then 0 else (if self > 1 then 1 else self fi) fi
        envDesc$ = "dB mapped over " + fixed$(floorDb, 1) + " to " + fixed$(maxDb, 1)
            ... + " dB -> 0..1 (relative to this file's loudest moment)"
        appendInfoLine: "  Intensity envelope: ", envDesc$
    endif

    selectObject: controlRaw
    Resample: sr, 50
    envSound = selected("Sound")
    removeObject: controlRaw
    selectObject: envSound
    Formula: ~ if self < 0 then 0 else (if self > 1 then 1 else self fi) fi
endif

selectObject: envSound
@dbg: "envSound (0..1)"

appendInfoLine: ""

# ============================================================
# CONTROL SIGNALS
# ============================================================
# v0.6: two separate, calibrated control paths.
#
#   loopVca  - what the envelope does INSIDE the loop. The old code
#              multiplied once per iteration, so the audible depth was
#              vca^iterations. The per-iteration deviation is now the
#              requested depth divided by the iteration count, so the
#              accumulated modulation is what was asked for.
#   outVca   - what the envelope does to the OUTPUT, in dB. This is the
#              part you actually hear as a sidechain.

loopDepthDb = input_Sensitivity * 30
perIterDb = loopDepthDb / iterations

selectObject: envSound
Copy: "loop_vca"
loopVcaM = selected("Sound")
Formula: "10 ^ ((self - 1) * " + string$(perIterDb) + " / 20)"
Convert to stereo
loopVca = selected("Sound")
removeObject: loopVcaM

selectObject: envSound
Copy: "out_vca"
outVcaM = selected("Sound")
Formula: "10 ^ ((self - 1) * " + string$(sidechain_depth_dB) + " / 20)"
Convert to stereo
outVca = selected("Sound")
removeObject: outVcaM

if debug
    selectObject: loopVca
    lvMin = Get minimum: 0, 0, "None"
    lvMax = Get maximum: 0, 0, "None"
    appendInfoLine: "  [DBG] loopVca per-iteration range ", fixed$(lvMin, 5), " - ", fixed$(lvMax, 5),
        ... "  (", fixed$(loopDepthDb, 1), " dB accumulated over ", iterations, " iterations)"
endif

# ============================================================
# RESONANCE CENTRE
# ============================================================

resonance_Center = mean_Pitch + frequency_Offset_Hz

if resonance_Center <= 20
    exitScript: "The resonance centre works out to " + fixed$(resonance_Center, 1)
        ... + " Hz (mean pitch " + fixed$(mean_Pitch, 1) + " + offset " + fixed$(frequency_Offset_Hz, 1)
        ... + "). It must be above 20 Hz - below that the band filter passes nothing."
endif
if resonance_Center >= nyquist
    exitScript: "The resonance centre works out to " + fixed$(resonance_Center, 1)
        ... + " Hz, at or above the Nyquist frequency (" + fixed$(nyquist, 1) + " Hz)."
endif
if resonance_Center + bandwidth_Hz >= nyquist
    appendInfoLine: "  NOTE: the resonance band reaches ", fixed$(resonance_Center + bandwidth_Hz, 1),
        ... " Hz, past Nyquist (", fixed$(nyquist, 1), " Hz) - the upper part is unavailable."
endif

tracking = 0
if resonance_Tracking = 2 and not shortFile and f0Sound <> 0
    tracking = 1
endif
if resonance_Tracking = 2 and tracking = 0
    appendInfoLine: "  NOTE: pitch tracking requested but no usable contour - falling back to a fixed band."
endif

# Build the ACTUAL tracked resonance trajectory before integrating phase.
# This trajectory includes Frequency_Offset_Hz and is clamped below Nyquist.
# Per-iteration drift receives an additional bandwidth-aware cap below.
if tracking
    selectObject: f0Sound
    Copy: "resonance_track"
    trackingFreqSound = selected("Sound")
    if frequency_Offset_Hz <> 0
        Formula: "self + " + string$(frequency_Offset_Hz)
    endif
    trackingBaseCap = nyquist - 20
    if trackingBaseCap < 30
        trackingBaseCap = nyquist * 0.8
    endif
    Formula: "if self < 30 then 30 else (if self > " + string$(trackingBaseCap) + " then " + string$(trackingBaseCap) + " else self fi) fi"
    trackingBaseMin = Get minimum: 0, 0, "None"
    trackingBaseMax = Get maximum: 0, 0, "None"
    trackingBaseMean = Get mean: "All", 0, 0
    if trackingBaseMean = undefined
        trackingBaseMean = resonance_Center
    endif

    selectObject: trackingFreqSound
    Copy: "phase_track"
    phaseSound = selected("Sound")
    Formula: "self / " + string$(sr)
    Formula: "self + if col > 1 then self[col-1] else 0 fi"
    Formula: "2 * pi * self"
endif

if tracking
    appendInfoLine: "Resonance: following pitch contour after offset/clamp (", fixed$(trackingBaseMin, 1), " - ",
        ... fixed$(trackingBaseMax, 1), " Hz), band width ", fixed$(bandwidth_Hz, 0), " Hz"
else
    appendInfoLine: "Resonance: fixed at ", fixed$(resonance_Center, 1), " Hz, band width ",
        ... fixed$(bandwidth_Hz, 0), " Hz"
endif

# ============================================================
# EXCITATION
# ============================================================
# v0.6: the loop can be excited by noise (the no-input aesthetic), by
# the controller itself (which restores onsets, rhythm and pitch), or by
# both. Absolute levels here no longer matter - the loop is re-levelled
# after every iteration - so each source is simply scaled to 0.5.

appendInfoLine: "Building excitation (", excitation_Source$, ")..."

# Seed band, used for the noise excitation and reported either way.
# In tracking mode use the same offset/clamped resonance trajectory that
# drives the heterodyne filter, not the raw controller pitch quantiles.
if tracking
    seedLow = trackingBaseMin - bandwidth_Hz
    seedHigh = trackingBaseMax + bandwidth_Hz
else
    seedLow = resonance_Center - bandwidth_Hz
    seedHigh = resonance_Center + bandwidth_Hz
endif
if seedLow < 20
    seedLow = 20
endif
if seedHigh > nyquist
    seedHigh = nyquist
endif

useNoise = 0
useCtrl = 0
if excitation_Source = 1
    useNoise = 1
elsif excitation_Source = 2
    useCtrl = 1
else
    useNoise = 1
    useCtrl = 1
endif

excNoise = 0
excCtrl = 0

if useNoise
    Create Sound from formula: "temp_noise", 1, xminOrig, xmaxOrig, sr, "randomGauss(0, 0.1)"
    noiseSeed = selected("Sound")
    Filter (pass Hann band): seedLow, seedHigh, 20
    noiseBand = selected("Sound")
    removeObject: noiseSeed
    selectObject: noiseBand
    # v0.6: when the controller also excites the loop, a flat noise bed
    # would fill every gap and flatten the dynamics the sidechain is
    # supposed to create, so the seed follows the envelope too.
    if useCtrl
        Formula: "self * (0.3 + 0.7 * object[" + string$(envSound) + ", 1, col])"
    endif
    nbPk = Get absolute extremum: 0, 0, "None"
    if nbPk > 1e-9
        Scale peak: 0.5
    endif
    Copy: "temp_noise_L"
    noiseL = selected("Sound")
    selectObject: noiseBand
    Copy: "temp_noise_R"
    noiseR = selected("Sound")
    selectObject: noiseL, noiseR
    Combine to stereo
    excNoise = selected("Sound")
    removeObject: noiseBand, noiseL, noiseR
    appendInfoLine: "  Noise seed band (effective): ", fixed$(seedLow, 1), " - ", fixed$(seedHigh, 1), " Hz"
endif

if useCtrl
    selectObject: original
    Copy: "temp_ctrl_exc"
    ctrlExcRaw = selected("Sound")
    ctrlCh = Get number of channels
    if ctrlCh <> 2
        Convert to mono
        ctrlExcMono = selected("Sound")
        Convert to stereo
        excCtrl = selected("Sound")
        removeObject: ctrlExcRaw, ctrlExcMono
    else
        excCtrl = ctrlExcRaw
    endif
    selectObject: excCtrl
    ceRms = Get absolute extremum: 0, 0, "None"
    if ceRms > 1e-9
        Scale peak: 0.5
    endif
    appendInfoLine: "  Controller feeds the loop (onsets and pitch enter the circuit)"
endif

if useNoise and useCtrl
    selectObject: excNoise
    Formula: "self * 0.5 + object[" + string$(excCtrl) + ", row, col] * 0.5"
    stereoLoop = excNoise
    removeObject: excCtrl
elsif useNoise
    stereoLoop = excNoise
else
    stereoLoop = excCtrl
endif

selectObject: stereoLoop
slPk = Get absolute extremum: 0, 0, "None"
if slPk > 1e-9
    Scale peak: 0.5
endif
@dbg: "excitation buffer"

# ============================================================
# BUFFER ITERATION CORE
# ============================================================
# v0.6 gain structure:
#   u  = loop*damping + band(loop)*feedback*loopVca(t)
#   y  = u                       when Drive = 0 (true linear bypass)
#      or arctan(g*u)/g           when Drive > 0, unity slope at 0
#   y  = re-levelled to loopTarget
# The re-levelling is the whole point: without it the in-band gain was
# ~1.9 per pass and the character was an exponential in Iterations.

loopTarget = 0.6
gShape = 0.25 + drive * 6.0
g$ = string$(gShape)
damp$ = string$(damping_Factor)
fb$ = string$(base_Feedback)
lv$ = string$(loopVca)

appendInfoLine: ""
trackingDriftClampCount = 0
if drive = 0
    appendInfoLine: "Running ", iterations, " iterations (drive 0.00, linear saturator bypass)..."
else
    appendInfoLine: "Running ", iterations, " iterations (drive ", fixed$(drive, 2),
        ... ", soft-clip ceiling ", fixed$(pi / (2 * gShape), 3), ")..."
endif

for i from 1 to iterations
    if i mod 10 = 0
        appendInfoLine: "  Iteration ", i, "/", iterations
    endif

    # --- band for this pass -------------------------------
    width_drift = bandwidth_Hz * analog_Instability
    current_width = bandwidth_Hz + randomGauss(0, width_drift)
    if current_width < 10
        current_width = 10
    endif

    if tracking
        driftFac = 1 + randomGauss(0, analog_Instability * 0.25)
        if driftFac < 0.5
            driftFac = 0.5
        endif
        if driftFac > 2.0
            driftFac = 2.0
        endif

        # trackBP low-passes the down-mixed signal before moving it back up.
        # Keep the highest tracked carrier plus that low-pass width below
        # Nyquist, otherwise a high F0/offset/drift combination can fold.
        trackCut = current_width / 2
        if trackCut < 8
            trackCut = 8
        endif
        if trackCut > nyquist * 0.4
            trackCut = nyquist * 0.4
        endif
        maxTrackedCarrier = nyquist - trackCut - 1
        maxSafeDriftFac = maxTrackedCarrier / trackingBaseMax
        if maxSafeDriftFac < 0.5
            maxSafeDriftFac = 0.5
        endif
        if driftFac > maxSafeDriftFac
            driftFac = maxSafeDriftFac
            trackingDriftClampCount = trackingDriftClampCount + 1
        endif

        @trackBP: stereoLoop, driftFac, trackCut
        filteredSignal = trackBP.out
        bandCentre_'i' = trackingBaseMean * driftFac
    else
        drift_hz = resonance_Center * analog_Instability
        current_freq = resonance_Center + randomGauss(0, drift_hz)
        if current_freq < 50
            current_freq = 50
        endif
        if current_freq > nyquist - 50
            current_freq = nyquist - 50
        endif
        lowEdge = current_freq - (current_width / 2)
        highEdge = current_freq + (current_width / 2)
        if lowEdge < 20
            lowEdge = 20
        endif
        if highEdge > nyquist
            highEdge = nyquist
        endif
        selectObject: stereoLoop
        Filter (pass Hann band): lowEdge, highEdge, 20
        filteredSignal = selected("Sound")
        bandCentre_'i' = current_freq
    endif

    # --- mix, optional soft clip, re-level ----------------
    selectObject: stereoLoop
    f$ = string$(filteredSignal)
    if drive = 0
        Formula: "(self * " + damp$ + ") + (object[" + f$
            ... + ", row, col] * " + fb$ + " * object[" + lv$ + ", row, col])"
    else
        Formula: "arctan(" + g$ + " * ((self * " + damp$ + ") + (object[" + f$
            ... + ", row, col] * " + fb$ + " * object[" + lv$ + ", row, col]))) / " + g$
    endif
    removeObject: filteredSignal

    selectObject: stereoLoop
    itPeak_'i' = Get absolute extremum: 0, 0, "None"
    itRms_'i' = Get root-mean-square: 0, 0
    if itPeak_'i' = undefined
        exitScript: "The loop went undefined at iteration " + string$(i)
            ... + ". Lower Drive or Base_Feedback and try again."
    endif
    if itPeak_'i' > 1e-9
        Scale peak: loopTarget
    endif

    if debug and (i <= 2 or i mod 10 = 0 or i = iterations)
        appendInfoLine: "  [DBG] iter ", i, ": pre-level peak=", fixed$(itPeak_'i', 5),
            ... "  rms=", fixed$(itRms_'i', 5), "  band centre=", fixed$(bandCentre_'i', 1), " Hz"
    endif
endfor

if tracking
    removeObject: phaseSound
endif
removeObject: loopVca

appendInfoLine: ""

# ============================================================
# SIDECHAIN VCA (the audible one)
# ============================================================

selectObject: stereoLoop
Formula: "self * object[" + string$(outVca) + ", row, col]"
removeObject: outVca
@dbg: "after sidechain VCA"
appendInfoLine: "Sidechain VCA applied: ", fixed$(sidechain_depth_dB, 1), " dB of envelope depth"

# ============================================================
# SPATIAL POST-PROCESSING
# ============================================================

appendInfoLine: "Applying spatial mode: ", spatial_Mode$, "..."

selectObject: stereoLoop
nChLoop = Get number of channels
if nChLoop = 1
    Convert to stereo
    newStereo = selected("Sound")
    removeObject: stereoLoop
    stereoLoop = newStereo
endif

if spatial_Mode$ = "Mono"
    selectObject: stereoLoop
    Convert to mono
    result = selected("Sound")
    Rename: input_Name$ + "_feedback_" + presetName$
    removeObject: stereoLoop

else
    selectObject: stereoLoop
    Extract all channels
    chL = selected("Sound", 1)
    chR = selected("Sound", 2)

    if spatial_Mode$ = "Stereo Wide"
        # v0.6: detuned twin resonance. The old version gave L the lows
        # and R the highs, which on a narrow-band signal produced two
        # unbalanced copies of the same thing. Two slightly detuned
        # resonances decorrelate a drone the way two circuits would.
        det = stereo_spread_percent / 100
        lc = resonance_Center * (1 - det)
        rc = resonance_Center * (1 + det)
        if lc < 20
            lc = 20
        endif
        if rc < 20
            rc = 20
        endif
        if lc > nyquist - 1
            lc = nyquist - 1
        endif
        if rc > nyquist - 1
            rc = nyquist - 1
        endif
        halfW = bandwidth_Hz
        lLo = lc - halfW
        lHi = lc + halfW
        rLo = rc - halfW
        rHi = rc + halfW
        if lLo < 20
            lLo = 20
        endif
        if rLo < 20
            rLo = 20
        endif
        if lHi > nyquist
            lHi = nyquist
        endif
        if rHi > nyquist
            rHi = nyquist
        endif

        selectObject: chL
        Filter (pass Hann band): lLo, lHi, 60
        lRes = selected("Sound")
        selectObject: chL
        Copy: "wideL"
        chL_filtered = selected("Sound")
        Formula: "self * 0.6 + object[" + string$(lRes) + ", row, col] * 0.8"
        removeObject: lRes

        selectObject: chR
        Filter (pass Hann band): rLo, rHi, 60
        rRes = selected("Sound")
        selectObject: chR
        Copy: "wideR"
        chR_filtered = selected("Sound")
        Formula: "self * 0.6 + object[" + string$(rRes) + ", row, col] * 0.8"
        removeObject: rRes

    elsif spatial_Mode$ = "Rotating"
        # v0.6.1: derive both pan channels from ONE mono wet source. Only
        # then does cos^2(theta)+sin^2(theta)=1 describe constant power.
        # Use time relative to xmin so the same samples rotate identically
        # even when the Praat Sound has a non-zero absolute start time.
        rotation_rate = 0.2
        rot$ = string$(rotation_rate)
        x0$ = string$(xminOrig)
        selectObject: stereoLoop
        Convert to mono
        rotMono = selected("Sound")

        selectObject: rotMono
        Copy: "temp_chL_rot"
        chL_filtered = selected("Sound")
        Formula: "self * cos(pi/4 + (pi/4) * sin(2*pi*" + rot$ + "*(x - " + x0$ + ")))"

        selectObject: rotMono
        Copy: "temp_chR_rot"
        chR_filtered = selected("Sound")
        Formula: "self * sin(pi/4 + (pi/4) * sin(2*pi*" + rot$ + "*(x - " + x0$ + ")))"
        removeObject: rotMono

    elsif spatial_Mode$ = "Pseudo-Binaural (Delay/Filter)"
        binLTop = 3000
        if binLTop > nyquist
            binLTop = nyquist
        endif
        binRTop = 6000
        if binRTop > nyquist
            binRTop = nyquist
        endif
        selectObject: chL
        Filter (pass Hann band): 50, binLTop, 80
        chL_filtered = selected("Sound")

        selectObject: chR
        Copy: "temp_chR_src"
        chR_src = selected("Sound")
        delaySamples = round(interaural_delay_ms / 1000 * sr)
        if delaySamples < 1
            delaySamples = 1
        endif
        ds$ = string$(delaySamples)
        src$ = string$(chR_src)
        selectObject: chR
        Formula: "if col > " + ds$ + " then object[" + src$ + ", 1, col - " + ds$ + "] else 0 fi"
        removeObject: chR_src
        Filter (pass Hann band): 200, binRTop, 80
        chR_filtered = selected("Sound")
    endif

    selectObject: chL_filtered, chR_filtered
    Combine to stereo
    result = selected("Sound")
    Rename: input_Name$ + "_feedback_" + presetName$
    removeObject: chL_filtered, chR_filtered, chL, chR, stereoLoop
endif

selectObject: result
@dbg: "result (wet) before scale"
wetPeakRaw = Get absolute extremum: 0, 0, "None"

if output_mode = 1
    if wetPeakRaw > 1e-9
        Scale peak: 0.95
    endif
endif

# Exciter on the wet path, if requested (so Dry_Wet = 1 stays a bypass)
exciterDesc$ = "off"
if high_Freq_Add > 0 and exciter_position = 2
    @exciter: result
    appendInfoLine: "Added synthetic highs to the wet path (", exciterDesc$, ")"
    if output_mode = 1
        selectObject: result
        wetExcPk = Get absolute extremum: 0, 0, "None"
        if wetExcPk > 1e-9
            Scale peak: 0.95
        endif
    endif
endif

# ============================================================
# DRY / WET MIX
# ============================================================

if dry_Wet > 0
    selectObject: result
    nChResult = Get number of channels

    selectObject: original
    Copy: "dry_signal"
    drySig = selected("Sound")
    nChDry = Get number of channels

    if nChDry <> nChResult
        selectObject: drySig
        if nChResult = 1
            Convert to mono
            dryConv = selected("Sound")
        elsif nChDry > 2 and multichannel_policy = 2
            selectObject: drySig
            Extract one channel: 1
            dryC1 = selected("Sound")
            selectObject: drySig
            Extract one channel: 2
            dryC2 = selected("Sound")
            selectObject: dryC1, dryC2
            Combine to stereo
            dryConv = selected("Sound")
            removeObject: dryC1, dryC2
        elsif nChDry > 2
            selectObject: drySig
            Convert to mono
            dryMonoTmp = selected("Sound")
            Convert to stereo
            dryConv = selected("Sound")
            removeObject: dryMonoTmp
        else
            Convert to stereo
            dryConv = selected("Sound")
        endif
        removeObject: drySig
        drySig = dryConv
    endif

    if output_mode = 1
        selectObject: drySig
        dryPk = Get absolute extremum: 0, 0, "None"
        if dryPk > 1e-9
            Scale peak: 0.95
        endif
    endif

    selectObject: result
    Formula: "self * " + string$(1 - dry_Wet) + " + object[" + string$(drySig)
        ... + ", row, col] * " + string$(dry_Wet)
    removeObject: drySig

    if output_mode = 1
        selectObject: result
        mixPk = Get absolute extremum: 0, 0, "None"
        if mixPk > 1e-9
            Scale peak: 0.95
        endif
    endif
    appendInfoLine: "Mixed dry/wet: ", fixed$((1-dry_Wet)*100, 0), "% iteration path / ",
        ... fixed$(dry_Wet*100, 0), "% dry path"
endif

if high_Freq_Add > 0 and exciter_position = 1
    @exciter: result
    appendInfoLine: "Added synthetic highs after the mix (", exciterDesc$, ")"
    if dry_Wet >= 1
        appendInfoLine: "  NOTE: Dry_Wet is 1 but the exciter runs after the mix. Use Exciter_position 2 for a bypass."
    endif
    if output_mode = 1
        selectObject: result
        excPk = Get absolute extremum: 0, 0, "None"
        if excPk > 1e-9
            Scale peak: 0.95
        endif
    endif
endif

# ============================================================
# FINAL OUTPUT STAGE
# ============================================================

selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
preRms = Get root-mean-square: 0, 0

if output_mode = 2
    if prePeak > 1e-9
        Scale peak: 0.95
        outDesc$ = "normalized once at the end"
    else
        outDesc$ = "silent - normalization skipped"
    endif
elsif output_mode = 3
    outDesc$ = "rendered level preserved"
elsif output_mode = 4
    # v0.6: peak normalization made the presets incomparable - at an
    # identical peak of 0.95 their RMS spanned 7x. Match RMS instead,
    # then pull back if that would clip.
    targetRms = 10 ^ (target_RMS_dBFS / 20)
    if preRms > 1e-9
        Formula: "self * " + string$(targetRms / preRms)
        selectObject: result
        pk2 = Get absolute extremum: 0, 0, "None"
        if pk2 > 0.98
            Scale peak: 0.98
            outDesc$ = "RMS target " + fixed$(target_RMS_dBFS, 1) + " dBFS (peak-guarded to 0.98)"
        else
            outDesc$ = "RMS matched to " + fixed$(target_RMS_dBFS, 1) + " dBFS"
        endif
    else
        outDesc$ = "silent - RMS matching skipped"
    endif
else
    outDesc$ = "normalized at each stage (v0.3 legacy)"
endif

# Edge fades. The loop is steady-state from the first sample, so without
# these every render begins and ends on a discontinuity.
if fade_ms > 0
    fadeSec = fade_ms / 1000
    if fadeSec > duration / 3
        fadeSec = duration / 3
    endif
    selectObject: result
    nChFade = Get number of channels
    Formula (part): xminOrig, xminOrig + fadeSec, 1, nChFade,
        ... "self * (0.5 - 0.5 * cos(pi * (x - " + string$(xminOrig) + ") / " + string$(fadeSec) + "))"
    Formula (part): xmaxOrig - fadeSec, xmaxOrig, 1, nChFade,
        ... "self * (0.5 - 0.5 * cos(pi * (" + string$(xmaxOrig) + " - x) / " + string$(fadeSec) + "))"
endif

if output_Gain <> 1.0
    selectObject: result
    Formula: "self * " + string$(output_Gain)
endif

selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
finalRms = Get root-mean-square: 0, 0
finalCh = Get number of channels
finalStart = Get start time
finalEnd = Get end time

# ============================================================
# REPORT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== Parameters ==="
appendInfoLine: "Sample rate: ", fixed$(sr, 0), " Hz (Nyquist ", fixed$(nyquist, 1), " Hz)"
appendInfoLine: "Excitation: ", excitation_Source$
appendInfoLine: "Resonance mode: ", resonance_Tracking$
appendInfoLine: "Base feedback: ", fixed$(base_Feedback, 3), "  |  Damping: ", fixed$(damping_Factor, 3),
    ... "  |  Drive: ", fixed$(drive, 3)
appendInfoLine: "Iterations: ", iterations, "  |  loop re-levelled to ", fixed$(loopTarget, 2), " each pass"
appendInfoLine: "VCA envelope: ", envDesc$
appendInfoLine: "In-loop depth: ", fixed$(loopDepthDb, 1), " dB accumulated (",
    ... fixed$(perIterDb, 3), " dB per iteration)"
appendInfoLine: "Sidechain depth: ", fixed$(sidechain_depth_dB, 1), " dB (post-loop VCA)"
appendInfoLine: "Resonance: ", fixed$(resonance_Center, 1), " Hz  |  Bandwidth: ", fixed$(bandwidth_Hz, 1), " Hz"
if tracking
    appendInfoLine: "Tracked resonance base range: ", fixed$(trackingBaseMin, 1), " - ", fixed$(trackingBaseMax, 1),
        ... " Hz  |  Nyquist drift clamps: ", trackingDriftClampCount
endif
appendInfoLine: "Analog instability: ", fixed$(analog_Instability, 3), " (drift between iterations)"
appendInfoLine: "Dry/Wet: ", fixed$(dry_Wet, 3), "  |  High freq add: ", fixed$(high_Freq_Add, 3),
    ... "  |  Exciter: ", exciterDesc$
appendInfoLine: "Spatial mode: ", spatial_Mode$
if spatial_Mode$ = "Stereo Wide"
    appendInfoLine: "  Detune: ", fixed$(stereo_spread_percent, 2), "% (effective centres ", fixed$(lc, 1),
        ... " / ", fixed$(rc, 1), " Hz)"
endif
if spatial_Mode$ = "Pseudo-Binaural (Delay/Filter)"
    appendInfoLine: "  Interaural delay: ", fixed$(interaural_delay_ms, 3), " ms (",
        ... round(interaural_delay_ms / 1000 * sr), " samples)"
endif
if n_channels > 2
    if multichannel_policy = 2
        mcDesc$ = "use the first two channels"
    elsif multichannel_policy = 3
        mcDesc$ = "refuse more than 2 channels"
    else
        mcDesc$ = "downmix to mono, then duplicate"
    endif
    appendInfoLine: "Multichannel policy: input had ", n_channels, " channels -> ", mcDesc$
endif
appendInfoLine: "Random seed: ", seedDesc$
appendInfoLine: "Output mode: ", outDesc$, "  |  Output gain: ", fixed$(output_Gain, 3),
    ... "  |  Fades: ", fixed$(fade_ms, 1), " ms"
appendInfoLine: "Source peak: ", fixed$(srcPeak, 4), "  |  Wet peak before scaling: ", fixed$(wetPeakRaw, 4)
appendInfoLine: "Output: ", fixed$(finalEnd - finalStart, 3), " s, ", finalCh, " ch, peak ",
    ... fixed$(finalPeak, 4), ", rms ", fixed$(finalRms, 4), " (", fixed$(20*log10(finalRms + 1e-12), 1), " dBFS)"
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - it will clip on playback or export."
endif

# ============================================================
# VISUALIZATION
# ============================================================
# v0.6: the block diagram is gone. Every panel now plots something that
# was measured during this run.

if draw_visualization
    pageWidth = 8
    pageHeight = 7.85
    labelX = -0.035
    vpL = 0.60
    vpR = 7.70

    # ------------------------------------------------------------
    # Measure everything the figure plots. Nothing here is a diagram:
    # every curve is a quantity taken from this run.
    # ------------------------------------------------------------
    nEnv = 320

    # Mono copies, used for both the waveform panels and the spectra.
    # (Sound Draw stacks the channels of a stereo object inside the
    # viewport, which would put the overlays at the wrong height.)
    selectObject: original
    Copy: "viz_in"
    vizIn = selected("Sound")
    nc = Get number of channels
    if nc > 1
        Convert to mono
        tmp = selected("Sound")
        removeObject: vizIn
        vizIn = tmp
    endif
    selectObject: result
    Copy: "viz_out"
    vizOut = selected("Sound")
    nc = Get number of channels
    if nc > 1
        Convert to mono
        tmp = selected("Sound")
        removeObject: vizOut
        vizOut = tmp
    endif

    selectObject: vizIn
    ctrlPk = Get absolute extremum: 0, 0, "None"
    if ctrlPk <= 0 or ctrlPk = undefined
        ctrlPk = 1
    endif
    selectObject: vizOut
    outPk = Get absolute extremum: 0, 0, "None"
    if outPk <= 0 or outPk = undefined
        outPk = 1
    endif

    winSec = duration / nEnv
    ctrlEnvMax = 1e-12
    outEnvMax = 1e-12
    for k from 1 to nEnv
        tA = xminOrig + (k - 1) * winSec
        tB = tA + winSec
        tMid_'k' = tA + winSec / 2
        selectObject: vizIn
        v = Get root-mean-square: tA, tB
        if v = undefined
            v = 0
        endif
        ctrlEnvV_'k' = v
        if v > ctrlEnvMax
            ctrlEnvMax = v
        endif
        selectObject: vizOut
        v = Get root-mean-square: tA, tB
        if v = undefined
            v = 0
        endif
        outEnvV_'k' = v
        if v > outEnvMax
            outEnvMax = v
        endif
        selectObject: envSound
        v = Get value at time: 1, tMid_'k', "Linear"
        if v = undefined
            v = 0
        endif
        vcaEnvV_'k' = v
        if tracking and trackingFreqSound <> 0
            selectObject: trackingFreqSound
            v = Get value at time: 1, tMid_'k', "Linear"
            if v = undefined
                v = trackingBaseMean
            endif
        else
            # In fixed mode the actual resonance trajectory is constant; do
            # not plot the raw controller F0 as though the filter followed it.
            v = resonance_Center
        endif
        f0V_'k' = v
    endfor
    if ctrlEnvMax < 1e-12
        ctrlEnvMax = 1
    endif
    if outEnvMax < 1e-12
        outEnvMax = 1
    endif

    # Frequency window for the control-trajectory panel.
    fLoPlot = mean_Pitch
    fHiPlot = mean_Pitch
    for k from 1 to nEnv
        if f0V_'k' < fLoPlot
            fLoPlot = f0V_'k'
        endif
        if f0V_'k' > fHiPlot
            fHiPlot = f0V_'k'
        endif
    endfor
    fLoPlot = fLoPlot - bandwidth_Hz / 2
    fHiPlot = fHiPlot + bandwidth_Hz / 2
    if fLoPlot < 0
        fLoPlot = 0
    endif
    if fHiPlot - fLoPlot < 40
        fHiPlot = fLoPlot + 40
    endif
    fPad = (fHiPlot - fLoPlot) * 0.10
    fLoPlot = fLoPlot - fPad
    fHiPlot = fHiPlot + fPad
    if fLoPlot < 0
        fLoPlot = 0
    endif

    # Iteration trajectory ranges.
    itPkMax = 1e-12
    itRmsMax = 1e-12
    bcLo = bandCentre_1
    bcHi = bandCentre_1
    for k from 1 to iterations
        if itPeak_'k' > itPkMax
            itPkMax = itPeak_'k'
        endif
        if itRms_'k' > itRmsMax
            itRmsMax = itRms_'k'
        endif
        if bandCentre_'k' < bcLo
            bcLo = bandCentre_'k'
        endif
        if bandCentre_'k' > bcHi
            bcHi = bandCentre_'k'
        endif
    endfor
    if itPkMax < 1e-12
        itPkMax = 1
    endif
    if itRmsMax < 1e-12
        itRmsMax = 1
    endif
    if bcHi - bcLo < 10
        bcHi = bcLo + 10
    endif

    # Spectra: power density averaged over log-spaced bands, so a noisy
    # spectrum is readable and the axis can be logarithmic.
    nBands = 130
    specLo = 40
    specHi = nyquist * 0.95
    minBw = 2 / duration

    selectObject: vizIn
    To Spectrum: "yes"
    specIn = selected("Spectrum")
    selectObject: vizOut
    To Spectrum: "yes"
    specOut = selected("Spectrum")

    specMax = -1000
    for k from 1 to nBands
        fc = specLo * (specHi / specLo) ^ ((k - 0.5) / nBands)
        halfB = fc * ((specHi / specLo) ^ (0.5 / nBands) - 1)
        if halfB < minBw
            halfB = minBw
        endif
        f1 = fc - halfB
        f2 = fc + halfB
        if f1 < 1
            f1 = 1
        endif
        specF_'k' = fc
        selectObject: specIn
        d = Get band density: f1, f2
        if d = undefined or d <= 0
            d = 1e-14
        endif
        specInV_'k' = 10 * log10(d)
        selectObject: specOut
        d = Get band density: f1, f2
        if d = undefined or d <= 0
            d = 1e-14
        endif
        specOutV_'k' = 10 * log10(d)
        if specInV_'k' > specMax
            specMax = specInV_'k'
        endif
        if specOutV_'k' > specMax
            specMax = specOutV_'k'
        endif
    endfor
    specMin = specMax - 75
    removeObject: specIn, specOut

    # Round time-axis step (a raw duration/5 prints labels like 0.657).
    tStepRaw = duration / 5
    tExp = 10 ^ floor(log10(tStepRaw))
    tMant = tStepRaw / tExp
    if tMant < 1.5
        tStep = tExp
    elsif tMant < 3.5
        tStep = 2 * tExp
    elsif tMant < 7.5
        tStep = 5 * tExp
    else
        tStep = 10 * tExp
    endif

    itStep = 5
    if iterations > 40
        itStep = 10
    endif
    if iterations <= 12
        itStep = 2
    endif

    # ------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------
    Erase all
    Line width: 1
    Solid line
    Colour: "Black"
    @viz: input_Name$
    vizName$ = viz.out$
    if tracking
        trackShort$ = "pitch-tracked"
    else
        trackShort$ = "fixed " + fixed$(resonance_Center, 0) + " Hz"
    endif

    # ---------- Title ----------
    Font size: 12
    Select inner viewport: vpL, vpR, 0.02, 0.44
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Sidechain Feedback VCA v0.6.1##"
    Font size: 7
    Select inner viewport: vpL, vpR, 0.02, 0.44
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half", vizName$ + " | " + presetName$ + " | " + trackShort$
        ... + " | " + string$(iterations) + " iterations | drive " + fixed$(drive, 2)
        ... + " | sidechain " + fixed$(sidechain_depth_dB, 0) + " dB"

    # ---------- Panel 1: controller waveform + VCA envelope ----------
    Font size: 6
    Select inner viewport: vpL, vpR, 0.60, 1.38
    Axes: xminOrig, xmaxOrig, -ctrlPk, ctrlPk
    Paint rectangle: "{0.975, 0.975, 0.975}", xminOrig, xmaxOrig, -ctrlPk, ctrlPk

    Select inner viewport: vpL, vpR, 0.60, 1.38
    selectObject: vizIn
    Colour: "{0.62, 0.62, 0.62}"
    Line width: 1
    Draw: xminOrig, xmaxOrig, -ctrlPk, ctrlPk, "no", "Curve"

    Select inner viewport: vpL, vpR, 0.60, 1.38
    Axes: xminOrig, xmaxOrig, 0, 1
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 2
    for k from 2 to nEnv
        kp = k - 1
        Draw line: tMid_'kp', vcaEnvV_'kp', tMid_'k', vcaEnvV_'k'
    endfor

    Line width: 1
    Colour: "Black"
    Select inner viewport: vpL, vpR, 0.60, 1.38
    Axes: xminOrig, xmaxOrig, -ctrlPk, ctrlPk
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"
    Select inner viewport: vpL, vpR, 0.60, 1.38
    Axes: 0, 1, 0, 1
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Controller"
    Colour: "{0.20, 0.40, 0.80}"
    Text: 0.988, "right", 0.93, "half", "sidechain envelope 0-1"
    Colour: "Black"

    # ---------- Panel 2: result waveform + its RMS envelope ----------
    Font size: 6
    Select inner viewport: vpL, vpR, 1.52, 2.30
    Axes: xminOrig, xmaxOrig, -outPk, outPk
    Paint rectangle: "{0.975, 0.975, 0.975}", xminOrig, xmaxOrig, -outPk, outPk

    Select inner viewport: vpL, vpR, 1.52, 2.30
    selectObject: vizOut
    Colour: "{0.68, 0.62, 0.76}"
    Line width: 1
    Draw: xminOrig, xmaxOrig, -outPk, outPk, "no", "Curve"

    Select inner viewport: vpL, vpR, 1.52, 2.30
    Axes: xminOrig, xmaxOrig, -outPk, outPk
    Colour: "{0.45, 0.20, 0.60}"
    Line width: 2
    for k from 2 to nEnv
        kp = k - 1
        Draw line: tMid_'kp', outEnvV_'kp', tMid_'k', outEnvV_'k'
        Draw line: tMid_'kp', -outEnvV_'kp', tMid_'k', -outEnvV_'k'
    endfor

    Line width: 1
    Colour: "Black"
    Select inner viewport: vpL, vpR, 1.52, 2.30
    Axes: xminOrig, xmaxOrig, -outPk, outPk
    Draw inner box
    Marks bottom every: 1, tStep, "no", "yes", "no"
    Select inner viewport: vpL, vpR, 1.52, 2.30
    Axes: 0, 1, 0, 1
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Result"
    Colour: "{0.45, 0.20, 0.60}"
    Text: 0.988, "right", 0.93, "half", "output RMS envelope"
    Colour: "Black"

    # ---------- Panel 3: where the resonance sat, moment by moment ----------
    Font size: 6
    Select inner viewport: vpL, vpR, 2.44, 3.34
    Axes: xminOrig, xmaxOrig, fLoPlot, fHiPlot
    Paint rectangle: "{0.975, 0.975, 0.975}", xminOrig, xmaxOrig, fLoPlot, fHiPlot

    Select inner viewport: vpL, vpR, 2.44, 3.34
    Axes: xminOrig, xmaxOrig, fLoPlot, fHiPlot
    for k from 2 to nEnv
        kp = k - 1
        if tracking
            cA = f0V_'kp'
        else
            cA = resonance_Center
        endif
        yA1 = cA - bandwidth_Hz / 2
        yA2 = cA + bandwidth_Hz / 2
        if yA1 < fLoPlot
            yA1 = fLoPlot
        endif
        if yA2 > fHiPlot
            yA2 = fHiPlot
        endif
        if yA2 > yA1
            Paint rectangle: "{0.83, 0.91, 0.85}", tMid_'kp', tMid_'k', yA1, yA2
        endif
    endfor

    Select inner viewport: vpL, vpR, 2.44, 3.34
    Axes: xminOrig, xmaxOrig, fLoPlot, fHiPlot
    Colour: "{0.15, 0.55, 0.35}"
    Line width: 2
    for k from 2 to nEnv
        kp = k - 1
        yA = f0V_'kp'
        yB = f0V_'k'
        if yA < fLoPlot
            yA = fLoPlot
        endif
        if yA > fHiPlot
            yA = fHiPlot
        endif
        if yB < fLoPlot
            yB = fLoPlot
        endif
        if yB > fHiPlot
            yB = fHiPlot
        endif
        Draw line: tMid_'kp', yA, tMid_'k', yB
    endfor

    if not tracking
        Select inner viewport: vpL, vpR, 2.44, 3.34
        Axes: xminOrig, xmaxOrig, fLoPlot, fHiPlot
        Colour: "{0.80, 0.35, 0.20}"
        Line width: 2
        Dashed line
        rcClip = resonance_Center
        if rcClip < fLoPlot
            rcClip = fLoPlot
        endif
        if rcClip > fHiPlot
            rcClip = fHiPlot
        endif
        Draw line: xminOrig, rcClip, xmaxOrig, rcClip
        Solid line
    endif

    Line width: 1
    Colour: "Black"
    Select inner viewport: vpL, vpR, 2.44, 3.34
    Axes: xminOrig, xmaxOrig, fLoPlot, fHiPlot
    Draw inner box
    fSpan = fHiPlot - fLoPlot
    if fSpan > 800
        fStep = 200
    elsif fSpan > 400
        fStep = 100
    elsif fSpan > 200
        fStep = 50
    elsif fSpan > 80
        fStep = 20
    else
        fStep = 10
    endif
    Marks left every: 1, fStep, "yes", "yes", "no"
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"

    Select inner viewport: vpL, vpR, 2.44, 3.34
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.15, 0.55, 0.35}"
    if tracking
        Text: 0.012, "left", 0.93, "half", "base resonance = F0 + offset; iteration drift below"
    else
        Text: 0.012, "left", 0.93, "half", "fixed resonance = mean F0 + offset (band shaded)"
    endif
    Colour: "Black"
    Select inner viewport: vpL, vpR, 2.44, 3.34
    Axes: 0, 1, 0, 1
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Resonance (Hz)"

    # ---------- Panel 4: how the loop settled, pass by pass ----------
    Font size: 6
    Select inner viewport: vpL, vpR, 3.92, 4.82
    if iterations > 1
        itXmax = iterations
    else
        itXmax = 2
    endif
    Axes: 1, itXmax, 0, 1.30
    Paint rectangle: "{0.975, 0.975, 0.975}", 1, itXmax, 0, 1.30

    Select inner viewport: vpL, vpR, 3.92, 4.82
    Axes: 1, itXmax, 0, 1.30
    Colour: "{0.80, 0.35, 0.20}"
    Line width: 2
    for k from 2 to iterations
        kp = k - 1
        Draw line: kp, itPeak_'kp' / itPkMax, k, itPeak_'k' / itPkMax
    endfor

    Select inner viewport: vpL, vpR, 3.92, 4.82
    Axes: 1, itXmax, 0, 1.30
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 2
    for k from 2 to iterations
        kp = k - 1
        Draw line: kp, itRms_'kp' / itRmsMax, k, itRms_'k' / itRmsMax
    endfor

    Select inner viewport: vpL, vpR, 3.92, 4.82
    Axes: 1, itXmax, 0, 1.30
    Colour: "{0.15, 0.55, 0.35}"
    Line width: 1
    for k from 2 to iterations
        kp = k - 1
        yA = (bandCentre_'kp' - bcLo) / (bcHi - bcLo) * 0.24 + 0.03
        yB = (bandCentre_'k' - bcLo) / (bcHi - bcLo) * 0.24 + 0.03
        Draw line: kp, yA, k, yB
    endfor

    # A single-pass run has no line to draw; mark the one measurement.
    if iterations = 1
        Select inner viewport: vpL, vpR, 3.92, 4.82
        Axes: 1, itXmax, 0, 1.30
        Colour: "{0.80, 0.35, 0.20}"
        Paint circle: "{0.80, 0.35, 0.20}", 1, itPeak_1 / itPkMax, 0.02
        Colour: "{0.20, 0.40, 0.80}"
        Paint circle: "{0.20, 0.40, 0.80}", 1, itRms_1 / itRmsMax, 0.02
    endif

    Line width: 1
    Colour: "Black"
    Select inner viewport: vpL, vpR, 3.92, 4.82
    Axes: 1, itXmax, 0, 1.30
    Draw inner box
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Marks bottom every: 1, itStep, "yes", "yes", "no"
    Text bottom: "yes", "Iteration"

    Select inner viewport: vpL, vpR, 3.92, 4.82
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.80, 0.35, 0.20}"
    Text: 0.012, "left", 0.94, "half", "loop peak before re-levelling"
    Colour: "{0.20, 0.40, 0.80}"
    Text: 0.40, "left", 0.94, "half", "loop RMS"
    Colour: "{0.15, 0.55, 0.35}"
    Text: 0.988, "right", 0.94, "half", "band centre drift " + fixed$(bcLo, 0) + "-" + fixed$(bcHi, 0) + " Hz"
    Colour: "Black"
    Select inner viewport: vpL, vpR, 3.92, 4.82
    Axes: 0, 1, 0, 1
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Normalized"

    # ---------- Panel 5: spectrum, before and after ----------
    Font size: 6
    Select inner viewport: vpL, vpR, 5.40, 6.30
    Axes: log10(specLo), log10(specHi), specMin, specMax
    Paint rectangle: "{0.975, 0.975, 0.975}", log10(specLo), log10(specHi), specMin, specMax

    Select inner viewport: vpL, vpR, 5.40, 6.30
    Axes: log10(specLo), log10(specHi), specMin, specMax
    Colour: "{0.62, 0.62, 0.62}"
    Line width: 1
    for k from 2 to nBands
        kp = k - 1
        yA = specInV_'kp'
        yB = specInV_'k'
        if yA < specMin
            yA = specMin
        endif
        if yB < specMin
            yB = specMin
        endif
        Draw line: log10(specF_'kp'), yA, log10(specF_'k'), yB
    endfor

    Select inner viewport: vpL, vpR, 5.40, 6.30
    Axes: log10(specLo), log10(specHi), specMin, specMax
    Colour: "{0.45, 0.20, 0.60}"
    Line width: 2
    for k from 2 to nBands
        kp = k - 1
        yA = specOutV_'kp'
        yB = specOutV_'k'
        if yA < specMin
            yA = specMin
        endif
        if yB < specMin
            yB = specMin
        endif
        Draw line: log10(specF_'kp'), yA, log10(specF_'k'), yB
    endfor

    Line width: 1
    Colour: "Black"
    Select inner viewport: vpL, vpR, 5.40, 6.30
    Axes: log10(specLo), log10(specHi), specMin, specMax
    Draw inner box
    Marks left every: 1, 15, "yes", "yes", "no"
    One mark bottom: log10(50), "no", "yes", "no", "50"
    One mark bottom: log10(100), "no", "yes", "no", "100"
    One mark bottom: log10(250), "no", "yes", "no", "250"
    One mark bottom: log10(500), "no", "yes", "no", "500"
    One mark bottom: log10(1000), "no", "yes", "no", "1k"
    One mark bottom: log10(2500), "no", "yes", "no", "2.5k"
    One mark bottom: log10(5000), "no", "yes", "no", "5k"
    One mark bottom: log10(10000), "no", "yes", "no", "10k"
    Text bottom: "yes", "Frequency (Hz, log)"

    Select inner viewport: vpL, vpR, 5.40, 6.30
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.62, 0.62, 0.62}"
    Text: 0.012, "left", 0.94, "half", "controller"
    Colour: "{0.45, 0.20, 0.60}"
    Text: 0.14, "left", 0.94, "half", "result"
    Colour: "Black"
    Select inner viewport: vpL, vpR, 5.40, 6.30
    Axes: 0, 1, 0, 1
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Power (dB/Hz)"

    # ---------- Summary strip ----------
    Font size: 6
    Select inner viewport: vpL, vpR, 6.88, 7.78
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Select inner viewport: vpL, vpR, 6.88, 7.78
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    @viz: excitation_Source$
    excShort$ = viz.out$
    @viz: spatial_Mode$
    spatShort$ = viz.out$
    @viz: outDesc$
    outShort$ = viz.out$
    summary1$ = "##Input##  " + vizName$ + " | " + fixed$(duration, 2) + " s | peak "
        ... + fixed$(srcPeak, 3) + " | mean F0 " + fixed$(mean_Pitch, 1) + " Hz | preset " + presetName$
    summary2$ = "##Circuit##  " + excShort$ + " | " + trackShort$ + " | feedback "
        ... + fixed$(base_Feedback, 2) + " | damping " + fixed$(damping_Factor, 2) + " | drive "
        ... + fixed$(drive, 2) + " | " + string$(iterations) + " passes | band "
        ... + fixed$(bandwidth_Hz, 0) + " Hz"
    summary3$ = "##Sidechain##  " + fixed$(sidechain_depth_dB, 1) + " dB output VCA | "
        ... + fixed$(loopDepthDb, 1) + " dB in-loop | dry/wet " + fixed$(dry_Wet, 2) + " | air "
        ... + fixed$(high_Freq_Add, 2)
    summary4$ = "##Output##  " + string$(finalCh) + " ch | " + spatShort$ + " | peak "
        ... + fixed$(finalPeak, 3) + " | rms " + fixed$(20 * log10(finalRms + 1e-12), 1) + " dBFS | " + outShort$
    Text: 0.02, "left", 0.83, "half", summary1$
    Text: 0.02, "left", 0.60, "half", summary2$
    Text: 0.02, "left", 0.37, "half", summary3$
    Text: 0.02, "left", 0.14, "half", summary4$
    Colour: "Black"
    Select inner viewport: vpL, vpR, 6.88, 7.78
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: vizIn, vizOut

    # Restore the full page so Picture export / clipboard gets everything.
    Font size: 10
    Select outer viewport: 0, pageWidth, 0, pageHeight
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: envSound
if trackingFreqSound <> 0
    removeObject: trackingFreqSound
endif
if f0Sound <> 0
    removeObject: f0Sound
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="
selectObject: result
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result
