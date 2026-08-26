# ============================================================
# Praat AudioTools - Envelope_Application.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced Envelope Application with multiple envelope types,
#   curve shapes, modifiers, and comprehensive visualization.
#
# Changelog v1.5 (2026):
#   - FIX: Negative Curve_amount values are now clamped to 0 and reported;
#     0 is the explicit linear-limit case for the normalized exponential shape.
#   - FIX: ADSR visualization stage backgrounds/labels now follow Mirror. With
#     Mirror on, the displayed stages run R -> S -> D -> A in their actual
#     time-reversed positions. Any zero-level remainder outside explicitly
#     requested ADSR stage times is left neutral rather than mislabeled as R.
#
# Changelog v1.4 (2026):
#   - FIX: Peak normalization now checks for a non-zero output peak before
#     calling Scale peak; fully silent outputs are left unchanged and reported.
#   - FIX: Tremolo_depth is constrained to the documented 0-1 range, with
#     out-of-range custom values clamped and reported.
#   - FIX: Tremolo_rate_Hz must be positive and below the Sound's Nyquist
#     frequency; invalid rates now stop with a clear message instead of
#     producing an invalid/aliased control envelope.
#   - REPORTING: visualization distinguishes normalization requested/applied
#     from normalization skipped because the output was silent.
#
# Changelog v1.3 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# Changelog v1.2:
#
#   All items below were verified against real Praat behaviour
#   (headless Praat, `--run`), not just read from the source.
#
#   1. FIXED: "Exponential" silently became Linear whenever either
#      endpoint was at/near zero, because the old formula
#      (`start*(end/start)^progress`) is undefined at 0 and fell
#      back to a straight line -- exactly the two most common uses
#      of an exponential envelope (0->1 or 1->0). v1.2 always uses a
#      normalized exponential SHAPE (`(1-exp(-k*progress))/(1-exp(-k))`,
#      the same family already used by `applyCurve`) to interpolate
#      between start_level and end_level, which is well-defined at
#      either endpoint being zero.
#   2. FIXED: `Invert` used `peak_level - amp` instead of `1 - amp`.
#      `peak_level` doesn't participate in Linear, Exponential, Sine,
#      or Step at all, so e.g. a Linear 0->1 ramp with the default
#      Peak_level=1 but a lower `peak_level` value from some other
#      envelope's leftover setting inverted to the wrong range and
#      got clipped. Inversion is now `1 - amp` (the envelope's
#      declared 0-1 range), clamped to [0, 1].
#   3. FIXED: Trapezoid / ASR / Percussive / ADSR didn't fit their
#      stage times to the sound's duration. The old code zeroed only
#      the sustain/flat portion when stages didn't fit, leaving
#      Attack/Decay/Release uncompressed -- e.g. an 80ms Attack +
#      80ms Release on a 100ms sound never finished its Release and
#      ended at ~75% of peak instead of 0. v1.2 proportionally
#      compresses Attack/Decay/Release (and any explicitly-requested,
#      i.e. non-auto, Sustain) to fit inside the sound's duration
#      when their sum exceeds it, and reports the adjustment.
#   4. FIXED (wording): the form said "Times (seconds, 0=auto)" for
#      the whole group, but only Sustain=0 means auto -- Attack=0 /
#      Decay=0 / Release=0 mean an instant/skipped stage. Relabelled
#      to "Times in seconds (Sustain: 0 = auto)".
#   5. FIXED: "Step" wasn't a step. Every envelope type is sampled at
#      grid points (~500/s) and painted as piecewise-LINEAR segments
#      between them; for Step, the segment straddling the midpoint
#      got a short ramp between start_level and end_level instead of
#      an instant jump (~2ms smear at 1s duration, more for longer
#      sounds). v1.2 special-cases Step after the general grid is
#      painted: it overwrites the envelope with a single time-based
#      formula that jumps exactly at the midpoint, using the same
#      (already mirror/invert-correct) boundary levels the grid
#      already computed.
#   6. FIXED (precision): the v1.1 changelog claimed fades "reach
#      true zero", but Praat's sample grid is centered inside
#      [xmin,xmax] (first sample at xmin+0.5*dx, last at
#      xmax-0.5*dx), so a mathematically-exact ramp to 0 at t=duration
#      still lands about 1.13e-5 short of zero at 44.1kHz/1s --
#      verified directly. v1.2 explicitly forces the envelope's
#      first and last SAMPLES (via `Set value at sample number`) to
#      the exact requested boundary levels, so the actual first/last
#      audio sample is exactly right, not just approximately so.
#   7. FIXED: the ADSR visualization panel used `.sus` (a
#      procedure-local-style name) at script level, outside any
#      procedure -- undocumented/fragile even where it happens to
#      run. Renamed to a plain global, `visualSustain`.
#   8. CHANGED: `Normalize` (now `Peak_normalize_output`) defaults to
#      OFF and is more clearly named. `Scale peak` after envelope
#      multiplication re-amplifies the result back up to the target
#      peak, which silently overrides the absolute levels the
#      envelope was just asked to produce (e.g. a constant
#      Peak_level=0.5 envelope no longer actually attenuates the
#      output once normalized back up). The info header now notes
#      when it's active and that it changes absolute envelope levels.
#
#   Smaller fixes noted in the same audit:
#     - Gaussian is now normalized to reach exactly 0 at both edges
#       of the file (it previously started/ended at ~13.5% of peak,
#       since sigma=duration/4 doesn't fully decay by the edges).
#     - Percussive's release now goes through the same `applyCurve`
#       (Curve dropdown) as its attack, instead of an always-on
#       power-law tied to Curve_amount that ignored the Curve
#       selection -- so "Curve: Linear" now actually gives a linear
#       release, as the interface promises.
#     - Tremolo's `depth` is now unambiguous: 0 = constant
#       Peak_level, 1 = swings all the way down to 0 at each trough,
#       with Peak_level always reached at each peak. (The old
#       start/end-average "base", with a magic `< 0.1 -> 0.5`
#       fallback, made 50% depth actually produce a 0.25-0.75 range
#       instead of the expected ~0.5-1.0.) The envelope's control-
#       point grid is also densified for high tremolo rates so the
#       modulation itself doesn't get aliased away.
#     - `applyCurve`'s Exponential branch had an inconsistent guard
#       (`curve_amount > 0` to enter, but `.maxVal > 0.001` to
#       normalize) that left small positive Curve_amount values
#       producing tiny, un-normalized output instead of a proper
#       0->1 shape. Replaced with one consistent, much smaller
#       threshold with a linear fallback below it.
#     - Attack / Decay / Release / Sustain are now clamped to >= 0,
#       and Start/End/Peak/Sustain_level are clamped to [0, 1] (the
#       interface already claimed this range; it wasn't enforced).
#     - Every stage-time division (t/attack, etc.) is now guarded
#       against a zero-length stage, so an intentional Attack=0
#       ("instant" attack, a legitimate and common setting) no
#       longer risks a division-by-zero and instead jumps straight
#       to the post-stage level, exactly as a zero-length stage should.
#     - Smoothing is now a genuine multi-tap moving average spread
#       across the ~5ms window (evenly-spaced taps on each side,
#       edges clamped) instead of exactly two lone taps sitting at
#       the far edge of the window, which produced a crude 3-level
#       staircase around any sharp edge (e.g. Step) rather than an
#       actual smooth transition. Verified with an impulse test.
#
# ------------------------------------------------------------
# Changelog v1.1:
#   - FIXED: info header was invisible -- eight consecutive
#     writeInfoLine calls each CLEAR the Info window, so only the
#     last (empty) line survived. Header now appends.
#   - FIXED: smoothing Formula read self[col +/- k] in place:
#     self[col - k] saw already-smoothed values while
#     self[col + k] saw raw ones (asymmetric recursive smear,
#     compounding per pass). Now averages a frozen copy via
#     object[]. (Recurring pattern: in-place Formula reads of
#     self[col - k] return the value just written.)
#   - CHANGED: envelope now applied by DIRECT multiplication
#     with a piecewise-linear envelope Sound. The IntensityTier
#     path had four defects: -80 dB floor (1e-4 residual on
#     every fade-out), dB-linear interpolation warping shapes
#     between points, Cubic re-reads of a staircase envelope
#     (overshoot at each step edge), and a hidden scale-to-0.9
#     inside bare Multiply -- a unity envelope on a 0.5-peak
#     signal amplified it 1.8x. AmplitudeTier hardcodes the
#     same rescale, so tiers are out entirely. Fades now reach
#     true zero; the drawn envelope IS the applied envelope.
#
# Changelog v1.0:
#   - Unified single-form interface (compact)
#   - Added presets
#   - Added envelope modifiers (invert, mirror, smooth)
#   - Added more envelope types
#   - Added normalization option
#   - Reduced code duplication with procedures
#   - Enhanced visualization with stage labels
# ============================================================

form Envelope Application v1.5
    optionmenu Preset 1
        option Custom
        option Fade In
        option Fade Out
        option Swell (triangle)
        option Percussive
        option ADSR Pad
        option Plucked
        option Tremolo
        option Gate
    optionmenu Envelope_type 1
        option Linear
        option Exponential
        option Sine (S-curve)
        option Triangle
        option Trapezoid
        option Gaussian
        option Step
        option ASR
        option Percussive
        option ADSR
        option Tremolo
    comment === Levels (0-1) ===
    real Start_level 0.0
    real End_level 1.0
    real Peak_level 1.0
    real Sustain_level 0.7
    comment === Times in seconds (Sustain: 0 = auto) ===
    real Attack 0.02
    real Decay 0.1
    real Sustain 0
    real Release 0.2
    comment === Shape & Modulation ===
    optionmenu Curve 1
        option Linear
        option Exponential
        option Sine
    real Curve_amount 4
    real Tremolo_rate_Hz 5
    real Tremolo_depth 0.5
    comment === Modifiers ===
    boolean Invert 0
    boolean Mirror 0
    integer Smoothing 0
    comment === Output ===
    boolean Peak_normalize_output 0
    boolean Visualize 1
    boolean Play 1
endform

epsilon = 0.000001

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sr = Get sampling frequency

# === APPLY PRESETS ===
if preset = 2
    # Fade In
    envelope_type = 1
    start_level = 0
    end_level = 1
    presetName$ = "FadeIn"
elsif preset = 3
    # Fade Out
    envelope_type = 1
    start_level = 1
    end_level = 0
    presetName$ = "FadeOut"
elsif preset = 4
    # Swell
    envelope_type = 4
    peak_level = 1
    presetName$ = "Swell"
elsif preset = 5
    # Percussive
    envelope_type = 9
    attack = 0.005
    release = 0.3
    peak_level = 1
    curve = 2
    curve_amount = 4
    presetName$ = "Percussive"
elsif preset = 6
    # ADSR Pad
    envelope_type = 10
    attack = 0.3
    decay = 0.2
    sustain_level = 0.7
    sustain = 0
    release = 0.5
    peak_level = 1
    presetName$ = "Pad"
elsif preset = 7
    # Plucked
    envelope_type = 9
    attack = 0.001
    release = duration * 0.8
    peak_level = 1
    curve = 2
    curve_amount = 3
    presetName$ = "Plucked"
elsif preset = 8
    # Tremolo
    envelope_type = 11
    peak_level = 1
    tremolo_rate_Hz = 6
    tremolo_depth = 0.4
    presetName$ = "Tremolo"
elsif preset = 9
    # Gate
    envelope_type = 5
    peak_level = 1
    attack = 0.05
    release = 0.05
    presetName$ = "Gate"
else
    presetName$ = "Custom"
endif

# === VALIDATE / SANITIZE NUMERIC SETTINGS ===
# v1.2: the interface claims Start/End/Peak/Sustain_level are 0-1 and
# that Attack/Decay/Sustain/Release are non-negative, but neither was
# enforced. Out-of-range values are clamped and reported.
settingsWarning$ = ""

if start_level < 0
    start_level = 0
    settingsWarning$ = settingsWarning$ + "  - Start_level was negative and has been clamped to 0." + newline$
elsif start_level > 1
    start_level = 1
    settingsWarning$ = settingsWarning$ + "  - Start_level was above 1 and has been clamped to 1." + newline$
endif

if end_level < 0
    end_level = 0
    settingsWarning$ = settingsWarning$ + "  - End_level was negative and has been clamped to 0." + newline$
elsif end_level > 1
    end_level = 1
    settingsWarning$ = settingsWarning$ + "  - End_level was above 1 and has been clamped to 1." + newline$
endif

if peak_level < 0
    peak_level = 0
    settingsWarning$ = settingsWarning$ + "  - Peak_level was negative and has been clamped to 0." + newline$
elsif peak_level > 1
    peak_level = 1
    settingsWarning$ = settingsWarning$ + "  - Peak_level was above 1 and has been clamped to 1." + newline$
endif

if sustain_level < 0
    sustain_level = 0
    settingsWarning$ = settingsWarning$ + "  - Sustain_level was negative and has been clamped to 0." + newline$
elsif sustain_level > 1
    sustain_level = 1
    settingsWarning$ = settingsWarning$ + "  - Sustain_level was above 1 and has been clamped to 1." + newline$
endif

if attack < 0
    attack = 0
    settingsWarning$ = settingsWarning$ + "  - Attack was negative and has been clamped to 0." + newline$
endif
if decay < 0
    decay = 0
    settingsWarning$ = settingsWarning$ + "  - Decay was negative and has been clamped to 0." + newline$
endif
if sustain < 0
    sustain = 0
    settingsWarning$ = settingsWarning$ + "  - Sustain was negative and has been clamped to 0 (auto)." + newline$
endif
if release < 0
    release = 0
    settingsWarning$ = settingsWarning$ + "  - Release was negative and has been clamped to 0." + newline$
endif

# v1.5: Curve_amount is the non-negative curvature constant used by the
# normalized exponential shape. Zero is its linear-limit fallback; negative
# values previously fell through to Linear silently, so clamp and report them.
if curve_amount < 0
    curve_amount = 0
    settingsWarning$ = settingsWarning$ + "  - Curve_amount was negative and has been clamped to 0 (linear limit)." + newline$
endif

# v1.4: Tremolo-specific validation. Depth is a normalized 0-1 amount;
# rate is a physical frequency and must be representable at this sample rate.
if envelope_type = 11
    if tremolo_depth < 0
        tremolo_depth = 0
        settingsWarning$ = settingsWarning$ + "  - Tremolo_depth was below 0 and has been clamped to 0." + newline$
    elsif tremolo_depth > 1
        tremolo_depth = 1
        settingsWarning$ = settingsWarning$ + "  - Tremolo_depth was above 1 and has been clamped to 1." + newline$
    endif

    if tremolo_rate_Hz <= 0
        exitScript: "Tremolo_rate_Hz must be greater than 0 Hz."
    endif

    tremoloNyquist = sr / 2
    if tremolo_rate_Hz >= tremoloNyquist
        exitScript: "Tremolo_rate_Hz must be below Nyquist (" + fixed$(tremoloNyquist, 1) + " Hz for this Sound)."
    endif
endif

# === FIT STAGE TIMES TO SOUND DURATION ===
# v1.2: for the stage-based envelope types, proportionally compress
# Attack/Decay/Release (and an explicitly-requested, non-auto,
# Sustain) so they fit inside the sound's duration when their sum
# exceeds it. Otherwise the envelope silently never reaches its
# final stage (e.g. Release never completing) instead of always
# spanning the whole sound as its shape promises.
if envelope_type = 5 or envelope_type = 8 or envelope_type = 9 or envelope_type = 10
    if envelope_type = 10
        stageSum = attack + decay + max(0, sustain) + release
    elsif envelope_type = 8
        stageSum = attack + max(0, sustain) + release
    else
        stageSum = attack + release
    endif

    if stageSum > duration and stageSum > epsilon
        stageScale = duration / stageSum
        attack = attack * stageScale
        decay = decay * stageScale
        release = release * stageScale
        sustain = sustain * stageScale
        settingsWarning$ = settingsWarning$ + "  - Stage times (" + fixed$(stageSum, 3) + "s) exceeded the sound's duration (" + fixed$(duration, 3) + "s) -- scaled to " + fixed$(stageScale * 100, 0) + "% to fit." + newline$
    endif
endif

# === GET ENVELOPE TYPE NAME ===
if envelope_type = 1
    envName$ = "Linear"
elsif envelope_type = 2
    envName$ = "Exponential"
elsif envelope_type = 3
    envName$ = "Sine"
elsif envelope_type = 4
    envName$ = "Triangle"
elsif envelope_type = 5
    envName$ = "Trapezoid"
elsif envelope_type = 6
    envName$ = "Gaussian"
elsif envelope_type = 7
    envName$ = "Step"
elsif envelope_type = 8
    envName$ = "ASR"
elsif envelope_type = 9
    envName$ = "Percussive"
elsif envelope_type = 10
    envName$ = "ADSR"
else
    envName$ = "Tremolo"
endif

# === INFO HEADER ===
# v1.1: writeInfoLine clears the Info window on EVERY call --
# the old header (eight writeInfoLine calls) erased itself.
writeInfoLine: "=============================================="
appendInfoLine: "  ENVELOPE APPLICATION v1.5"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(duration, 3), "s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Envelope: ", envName$
if peak_normalize_output
    appendInfoLine: "Note: Peak_normalize_output is ON -- the final Scale peak"
    appendInfoLine: "  step will re-amplify the result, so the envelope's"
    appendInfoLine: "  absolute levels (e.g. a constant 0.5 envelope) will NOT"
    appendInfoLine: "  be preserved in the output's actual peak amplitude."
endif
if settingsWarning$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Settings adjusted:"
    appendInfoLine: settingsWarning$
endif
appendInfoLine: ""

# ============================================================
# PROCEDURE: Apply curve shape to linear phase (0-1)
# ============================================================
# v1.2: the Exponential branch's normalization guard used to be
# inconsistent (entry gated on curve_amount > 0, but normalization
# gated on a separate, coarser .maxVal > 0.001 threshold), which left
# small positive Curve_amount values producing tiny, un-normalized
# output. Now uses one small, consistent epsilon with a linear
# fallback below it (which is also the correct mathematical limit).

procedure applyCurve: .phase
    if curve = 1
        # Linear
        applyCurve.result = .phase
    elsif curve = 2
        # Exponential
        if curve_amount > 0.000001
            .maxVal = 1 - exp(-curve_amount)
            applyCurve.result = (1 - exp(-curve_amount * .phase)) / .maxVal
        else
            applyCurve.result = .phase
        endif
    else
        # Sine
        applyCurve.result = (1 - cos(.phase * pi)) / 2
    endif
endproc

# ============================================================
# PROCEDURE: Calculate envelope amplitude at time t
# ============================================================
# v1.2: every stage-time division (t/attack, (t-attack)/decay, etc.)
# is now guarded against a zero-length stage. Attack/Decay/Release=0
# is a legitimate "instant" setting (e.g. a hard-gated Attack), not
# an error, and should jump straight to the post-stage level instead
# of dividing by (near) zero.

procedure getEnvelopeValue: .t, .dur
    .progress = .t / .dur

    if envelope_type = 1
        # Linear
        .amp = start_level + (end_level - start_level) * .progress

    elsif envelope_type = 2
        # Exponential -- normalized shape (see applyCurve), so it is
        # well-defined even when start_level or end_level is 0.
        if curve_amount > 0.000001
            .maxVal = 1 - exp(-curve_amount)
            .shape = (1 - exp(-curve_amount * .progress)) / .maxVal
        else
            .shape = .progress
        endif
        .amp = start_level + (end_level - start_level) * .shape

    elsif envelope_type = 3
        # Sine (S-curve)
        .amp = start_level + (end_level - start_level) * (1 - cos(.progress * pi)) / 2

    elsif envelope_type = 4
        # Triangle (peak in middle)
        if .progress < 0.5
            .amp = peak_level * (.progress / 0.5)
        else
            .amp = peak_level * (1 - (.progress - 0.5) / 0.5)
        endif

    elsif envelope_type = 5
        # Trapezoid
        .flatDur = .dur - attack - release
        if .flatDur < 0
            .flatDur = 0
        endif

        if .t < attack
            if attack < epsilon
                .amp = peak_level
            else
                .phase = .t / attack
                @applyCurve: .phase
                .amp = peak_level * applyCurve.result
            endif
        elsif .t < attack + .flatDur
            .amp = peak_level
        elsif .t < attack + .flatDur + release
            if release < epsilon
                .amp = 0
            else
                .phase = (.t - attack - .flatDur) / release
                @applyCurve: .phase
                .amp = peak_level * (1 - applyCurve.result)
            endif
        else
            .amp = 0
        endif

    elsif envelope_type = 6
        # Gaussian, normalized so it reaches exactly 0 at both edges
        # of the file (the raw exp() tail was still at ~13.5% of
        # peak at the edges with sigma = duration/4).
        .center = .dur / 2
        .sigma = .dur / 4
        .raw = exp(-0.5 * ((.t - .center) / .sigma) ^ 2)
        .edgeRaw = exp(-0.5 * (.center / .sigma) ^ 2)
        if .edgeRaw < 0.999
            .amp = peak_level * (.raw - .edgeRaw) / (1 - .edgeRaw)
        else
            .amp = peak_level * .raw
        endif

    elsif envelope_type = 7
        # Step (the hard jump itself is re-rendered exactly after
        # the main grid loop, below; this value is only used to
        # supply the flat level on each side of the jump)
        .stepTime = .dur / 2
        if .t < .stepTime
            .amp = start_level
        else
            .amp = end_level
        endif

    elsif envelope_type = 8
        # ASR
        .sus = sustain
        if .sus < epsilon
            .sus = .dur - attack - release
            if .sus < 0
                .sus = 0
            endif
        endif

        if .t < attack
            if attack < epsilon
                .amp = peak_level
            else
                .phase = .t / attack
                @applyCurve: .phase
                .amp = peak_level * applyCurve.result
            endif
        elsif .t < attack + .sus
            .amp = peak_level
        elsif .t < attack + .sus + release
            if release < epsilon
                .amp = 0
            else
                .phase = (.t - attack - .sus) / release
                @applyCurve: .phase
                .amp = peak_level * (1 - applyCurve.result)
            endif
        else
            .amp = 0
        endif

    elsif envelope_type = 9
        # Percussive. v1.2: release now goes through applyCurve, the
        # same as attack, instead of an always-on power law tied to
        # Curve_amount that ignored the Curve dropdown entirely.
        .total = attack + release

        if .t < attack
            if attack < epsilon
                .amp = peak_level
            else
                .phase = .t / attack
                @applyCurve: .phase
                .amp = peak_level * applyCurve.result
            endif
        elsif .t < .total
            if release < epsilon
                .amp = 0
            else
                .phase = (.t - attack) / release
                @applyCurve: .phase
                .amp = peak_level * (1 - applyCurve.result)
            endif
        else
            .amp = 0
        endif

    elsif envelope_type = 10
        # ADSR
        .sus = sustain
        if .sus < epsilon
            .sus = .dur - attack - decay - release
            if .sus < 0
                .sus = 0
            endif
        endif
        .susAmp = sustain_level * peak_level

        if .t < attack
            if attack < epsilon
                .amp = peak_level
            else
                .phase = .t / attack
                @applyCurve: .phase
                .amp = peak_level * applyCurve.result
            endif
        elsif .t < attack + decay
            if decay < epsilon
                .amp = .susAmp
            else
                .phase = (.t - attack) / decay
                @applyCurve: .phase
                .amp = peak_level - (peak_level - .susAmp) * applyCurve.result
            endif
        elsif .t < attack + decay + .sus
            .amp = .susAmp
        elsif .t < attack + decay + .sus + release
            if release < epsilon
                .amp = 0
            else
                .phase = (.t - attack - decay - .sus) / release
                @applyCurve: .phase
                .amp = .susAmp * (1 - applyCurve.result)
            endif
        else
            .amp = 0
        endif

    else
        # Tremolo. v1.2: depth is now unambiguous -- 0 = constant
        # Peak_level, 1 = swings all the way down to 0 at each
        # trough, Peak_level is always reached at each peak.
        .lfo = 0.5 + 0.5 * sin(2 * pi * tremolo_rate_Hz * .t)
        .amp = peak_level * (1 - tremolo_depth * (1 - .lfo))
        if .amp < 0
            .amp = 0
        endif
    endif

    # Apply modifiers
    if invert
        # v1.2: invert the envelope's declared 0-1 range (1 - amp),
        # not peak_level - amp (peak_level doesn't even participate
        # in Linear/Exponential/Sine/Step, so the old formula could
        # invert into the wrong range and get clipped away).
        .amp = 1 - .amp
        if .amp < 0
            .amp = 0
        endif
        if .amp > 1
            .amp = 1
        endif
    endif

    getEnvelopeValue.result = .amp
endproc

# ============================================================
# CREATE ENVELOPE
# ============================================================

appendInfoLine: "Creating envelope..."

# Create envelope sound
numPoints = min(10000, max(200, round(duration * 500)))
if envelope_type = 11
    # Tremolo: make sure the grid resolves the modulation rate
    # itself (>=30 points per cycle), not just the ~500 Hz default
    # control-point rate, which under-represented faster tremolo.
    numPoints = max(numPoints, round(duration * tremolo_rate_Hz * 30))
    numPoints = min(numPoints, 100000)
endif
timeStep = duration / numPoints

Create Sound from formula: "envelope_temp", 1, 0, duration, sr, "0"
envelope_sound = selected("Sound")

# Fill with envelope values
for i from 0 to numPoints
    t = i * timeStep
    if t > duration
        t = duration
    endif
    
    # Handle mirror
    if mirror
        t_lookup = duration - t
    else
        t_lookup = t
    endif
    
    @getEnvelopeValue: t_lookup, duration
    envAmp[i] = getEnvelopeValue.result
    envTime[i] = i * timeStep
endfor

# Apply to envelope sound: paint piecewise-LINEAR segments
# between grid points (v1.1; was a half-step staircase, which
# only worked because the tier re-interpolated it downstream)
selectObject: envelope_sound
for i from 0 to numPoints - 1
    t1 = envTime[i]
    t2 = envTime[i + 1]
    a1 = envAmp[i]
    a2 = envAmp[i + 1]
    Formula (part): t1, t2, 1, 1, ~ a1 + (a2 - a1) * (x - t1) / (t2 - t1)
endfor

# v1.2: Step is re-rendered as a true instantaneous jump, not the
# short ramp the general piecewise-linear grid above just painted
# across whichever grid cell happens to straddle the midpoint. Reuses
# envAmp[0] / envAmp[numPoints], which already correctly reflect
# Mirror and Invert from the loop above.
if envelope_type = 7
    stepLevelA = envAmp[0]
    stepLevelB = envAmp[numPoints]
    stepBoundary = duration / 2
    selectObject: envelope_sound
    Formula: ~ if x < stepBoundary then stepLevelA else stepLevelB fi
endif

# Apply smoothing
if smoothing > 0
    appendInfoLine: "  Smoothing (", smoothing, " passes)..."

    # v1.2: a genuine multi-tap moving average spread evenly across
    # the ~5ms window (edges clamped), instead of v1.1's two lone
    # taps sitting at the far edge of the window (which produced a
    # crude 3-level staircase around any sharp edge, e.g. Step,
    # rather than an actual smooth transition).
    halfWindowSamples = max(2, round(sr * 0.005))
    tapsPerSide = min(halfWindowSamples, 15)
    tapStride = max(1, round(halfWindowSamples / tapsPerSide))

    for pass to smoothing
        selectObject: envelope_sound
        smoothSrc = Copy: "smooth_src"
        selectObject: envelope_sound
        accum = Copy: "smooth_accum"
        Formula: ~ object[smoothSrc, col]

        for k to tapsPerSide
            offset = k * tapStride
            selectObject: accum
            Formula: ~ self + (if col - offset >= 1 then object[smoothSrc, col - offset] else object[smoothSrc, 1] fi) + (if col + offset <= ncol then object[smoothSrc, col + offset] else object[smoothSrc, ncol] fi)
        endfor

        selectObject: accum
        Formula: ~ self / (2 * tapsPerSide + 1)

        selectObject: envelope_sound
        Formula: ~ object[accum, col]

        removeObject: smoothSrc, accum
    endfor
endif

# v1.2: force the envelope's first and last SAMPLES to the exact
# requested boundary levels. Praat's sample grid is centered inside
# [xmin,xmax] (first sample at xmin+0.5*dx, last at xmax-0.5*dx), so
# even a mathematically exact ramp to 0 lands a hair short of true
# zero at the actual sample positions (verified: ~1.13e-5 residual
# at 44.1kHz/1s) -- not exactly zero, despite the v1.1 changelog's
# claim. This anchors the real first/last audio sample exactly.
selectObject: envelope_sound
envNumSamples = Get number of samples
Set value at sample number: 1, 1, envAmp[0]
Set value at sample number: 1, envNumSamples, envAmp[numPoints]

# ============================================================
# APPLY ENVELOPE BY DIRECT MULTIPLICATION
# ============================================================
# v1.1: the envelope Sound (piecewise-linear, optionally
# smoothed) is multiplied in directly. The old IntensityTier
# path had four problems: a -80 dB floor (1e-4 residual on
# every fade-out), dB-linear interpolation that warped every
# shape between points, Cubic re-reads of a STAIRCASE envelope
# (overshoot at each step edge), and a hidden scale-to-0.9-peak
# baked into bare Multiply -- a unity envelope on a 0.5-peak
# signal amplified it 1.8x. (AmplitudeTier: Multiply hardcodes
# the same rescale with no way to disable it, so no tier at
# all.) Direct multiplication is exact and the drawn envelope is
# now literally the applied envelope.

appendInfoLine: "Applying envelope..."

# Clamp to [0, 1], preserving the v1.0 behaviour where the
# 0 dB cap limited gain to unity
selectObject: envelope_sound
Formula: ~ min(1, max(0, self))
envId = envelope_sound
envNx = Get number of samples

selectObject: sound
result = Copy: sound_name$ + "_" + envName$
Formula: ~ self * object[envId, min(col, envNx)]

peakNormalizationApplied = 0
if peak_normalize_output
    selectObject: result
    preNormalizePeak = Get absolute extremum: 0, 0, "Sinc70"
    if preNormalizePeak > 0
        Scale peak: 0.95
        peakNormalizationApplied = 1
    else
        appendInfoLine: "Output is silent; peak normalization skipped."
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: "Creating visualization..."
    
    Erase all
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Envelope Application v1.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + envName$ + " | " + presetName$

    # Original
    Select outer viewport: 0, 8, 0.5, 1.8
    Select inner viewport: 0.6, 7.6, 0.6, 1.6
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.2, 8, 0.5, 1.8
    Text left: "yes", "Input"
    
    # Envelope with ADSR stage colors
    Select outer viewport: 0, 8, 1.9, 3.2
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    
    Axes: 0, duration, 0, 1.1
    
    if envelope_type = 10
        # ADSR stage markers. v1.5: the stage map follows Mirror as well as
        # the envelope itself. Also leave any post-envelope zero remainder
        # neutral instead of stretching the R background to the file end.
        visualSustain = sustain
        if visualSustain < epsilon
            visualSustain = duration - attack - decay - release
            if visualSustain < 0
                visualSustain = 0
            endif
        endif

        visualStageTotal = attack + decay + visualSustain + release
        if visualStageTotal > duration
            visualStageTotal = duration
        endif
        visualIdle = duration - visualStageTotal
        if visualIdle < 0
            visualIdle = 0
        endif

        # Neutral base also represents any explicit zero-level remainder.
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.1

        Font size: 6
        if mirror = 0
            visualA0 = 0
            visualA1 = min(duration, attack)
            visualD0 = visualA1
            visualD1 = min(duration, attack + decay)
            visualS0 = visualD1
            visualS1 = min(duration, attack + decay + visualSustain)
            visualR0 = visualS1
            visualR1 = min(duration, visualStageTotal)

            if visualA1 > visualA0
                Paint rectangle: "{0.85, 0.95, 0.85}", visualA0, visualA1, 0, 1.1
                Colour: "{0.3, 0.6, 0.3}"
                Text: (visualA0 + visualA1) / 2, "centre", 1.05, "half", "A"
            endif
            if visualD1 > visualD0
                Paint rectangle: "{0.95, 0.95, 0.85}", visualD0, visualD1, 0, 1.1
                Colour: "{0.6, 0.6, 0.3}"
                Text: (visualD0 + visualD1) / 2, "centre", 1.05, "half", "D"
            endif
            if visualS1 > visualS0
                Paint rectangle: "{0.85, 0.85, 0.95}", visualS0, visualS1, 0, 1.1
                Colour: "{0.3, 0.3, 0.6}"
                Text: (visualS0 + visualS1) / 2, "centre", 1.05, "half", "S"
            endif
            if visualR1 > visualR0
                Paint rectangle: "{0.95, 0.85, 0.85}", visualR0, visualR1, 0, 1.1
                Colour: "{0.6, 0.3, 0.3}"
                Text: (visualR0 + visualR1) / 2, "centre", 1.05, "half", "R"
            endif
        else
            # Time reversal of the base ADSR: any unused zero tail becomes a
            # leading neutral interval, followed by R -> S -> D -> A.
            visualR0 = visualIdle
            visualR1 = min(duration, visualR0 + release)
            visualS0 = visualR1
            visualS1 = min(duration, visualS0 + visualSustain)
            visualD0 = visualS1
            visualD1 = min(duration, visualD0 + decay)
            visualA0 = visualD1
            visualA1 = min(duration, visualA0 + attack)

            if visualR1 > visualR0
                Paint rectangle: "{0.95, 0.85, 0.85}", visualR0, visualR1, 0, 1.1
                Colour: "{0.6, 0.3, 0.3}"
                Text: (visualR0 + visualR1) / 2, "centre", 1.05, "half", "R"
            endif
            if visualS1 > visualS0
                Paint rectangle: "{0.85, 0.85, 0.95}", visualS0, visualS1, 0, 1.1
                Colour: "{0.3, 0.3, 0.6}"
                Text: (visualS0 + visualS1) / 2, "centre", 1.05, "half", "S"
            endif
            if visualD1 > visualD0
                Paint rectangle: "{0.95, 0.95, 0.85}", visualD0, visualD1, 0, 1.1
                Colour: "{0.6, 0.6, 0.3}"
                Text: (visualD0 + visualD1) / 2, "centre", 1.05, "half", "D"
            endif
            if visualA1 > visualA0
                Paint rectangle: "{0.85, 0.95, 0.85}", visualA0, visualA1, 0, 1.1
                Colour: "{0.3, 0.6, 0.3}"
                Text: (visualA0 + visualA1) / 2, "centre", 1.05, "half", "A"
            endif
        endif
    else
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.1
    endif
    
    selectObject: envelope_sound
    Colour: "{0.8, 0.3, 0.2}"
    Line width: 2
    Draw: 0, 0, 0, 1.1, "no", "Curve"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Envelope"
    
    # Result
    Select outer viewport: 0, 8, 3.3, 4.6
    Select inner viewport: 0.6, 7.6, 3.4, 4.4
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # === Summary strip ===
    selectObject: sound
    inChViz = Get number of channels
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if peak_normalize_output
        if peakNormalizationApplied
            normViz$ = "on (0.95 peak)"
        else
            normViz$ = "requested; skipped (silent output)"
        endif
    else
        normViz$ = "off"
    endif
    if envelope_type = 10
        envDetail$ = "A " + fixed$(attack*1000, 0) + " ms | D " + fixed$(decay*1000, 0) + " ms | S " + fixed$(sustain_level*100, 0) + "\% | R " + fixed$(release*1000, 0) + " ms"
    elsif envelope_type = 11
        envDetail$ = "rate " + fixed$(tremolo_rate_Hz, 1) + " Hz | depth " + fixed$(tremolo_depth*100, 0) + "\%"
    else
        envDetail$ = "start " + fixed$(start_level, 2) + " | end " + fixed$(end_level, 2) + " | peak " + fixed$(peak_level, 2) + " | curve " + fixed$(curve_amount, 1)
    endif
    Select outer viewport: 0, 8, 4.72, 5.88
    Select inner viewport: 0.60, 7.70, 4.80, 5.80
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half", "##Input##  " + vizName$ + " | " + fixed$(duration, 3) + " s | " + fixed$(sr, 0) + " Hz | " + string$(inChViz) + " ch"
    Text: 0.02, "left", 0.50, "half", "##Envelope##  " + envName$ + " | " + presetName$ + " | " + envDetail$ + " | invert " + if invert then "on" else "off" fi + " | mirror " + if mirror then "on" else "off" fi
    Text: 0.02, "left", 0.22, "half", "##Output##  normalization " + normViz$ + " | smoothing " + string$(smoothing) + " passes | peak " + fixed$(outPeakViz, 3)
    Colour: "Black"
    Draw inner box
    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.20
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: envelope_sound
selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result
