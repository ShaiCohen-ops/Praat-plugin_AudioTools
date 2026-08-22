# ============================================================
# Praat AudioTools - Dynamic_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic Distortion — applies tanh saturation where the drive
#   amount is modulated by the input signal's amplitude contour.
#   With positive Base_Drive and Sensitivity, loud sections get
#   more distortion and quiet sections stay cleaner.
#
#   Pipeline:
#     1. Build amplitude contour: rectify (abs), then either
#        zero-phase smoothing at Response_Speed_Hz (default) or a
#        causal attack/release follower
#     2. Per-sample drive = base_Drive + envelope * sensitivity
#     3. Output = tanh(input * drive) * output_Gain
#     4. Output level stage
#
#   NOTE on the default contour: Praat's "Filter (pass Hann band)"
#   is a frequency-domain, zero-phase filter, so it is ACAUSAL -
#   the drive starts rising BEFORE a transient (measured on a
#   synthetic onset: ~23 ms early at 15 Hz, ~17 ms at 20 Hz,
#   ~5.6 ms at 50 Hz, ~3.2 ms at 80 Hz). Response_Speed_Hz is a
#   smoothing cutoff, not an attack/release time, and the result
#   does not behave like a pedal or a compressor's follower. That
#   is a defensible choice for an offline tool and remains the
#   default; Envelope_mode 2 gives a causal follower instead.
#
#   Stereo input is collapsed to mono before processing — this
#   script produces a mono output regardless of input channels.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with
#     explicit inner viewports, standard title/subtitle, suite
#     typography, neutral panel backgrounds, summary strip and
#     full-page Picture export viewport.
#   - Preserved the script-specific nonlinear/diagnostic panels;
#     the visualization remains a direct explanation of the
#     transformation rather than a generic replacement plot.
#
# Changelog v0.4b:
#   - FIXED: Response_Speed_Hz was validated unconditionally, so a
#     valid causal run was blocked by a parameter the causal path
#     never reads (Envelope_mode 2 with Response_Speed_Hz 0 aborted
#     the script). Each mode is now checked only for what it uses.
#   - FIXED: driveMax_calc / driveMin_calc assumed Sensitivity >= 0.
#     With the negative Sensitivity the script explicitly supports,
#     envMax gives the LOWEST drive and envMin the highest, so the
#     two were swapped - the drive panel could get yLo_drive above
#     yHi_drive and invert its axis, and the "Drive range" caption
#     read backwards. Now ordered by value.
#   - FIXED: the Base_Drive < 0 note divided by Sensitivity without
#     checking it, and Sensitivity 0 is legal - Base_Drive -0.5 with
#     Sensitivity 0 crashed while building the Info text, before any
#     audio was touched. Guarded, and the script now also reports
#     whether the zero crossing falls inside the envelope range
#     actually observed rather than just naming the level.
#   - FIXED: Panel D was missed in the v0.4 xmin sweep - it still
#     ran 0..finalDur while every other panel used the Sound's real
#     domain, so on a Sound starting at 12.4 s it drew an empty
#     window.
#   - The normalization note said Output_Gain "does not affect the
#     result in this mode". True of its magnitude only: a negative
#     gain still inverts the output. Reworded.
#
# Changelog v0.4:
#   - Output_level replaces the unconditional `Scale peak: 0.95`.
#     Output_Gain is a constant scalar applied after tanh, so
#     normalizing the peak divides it straight back out:
#     0.95*g*f(x) / max|g*f(x)| = 0.95*f(x) / max|f(x)| for every
#     non-zero g. The presets' gains of 0.8, 0.9 and 1.0 could not
#     affect the result at all, and in Manual mode a positive gain
#     only mattered before the step that erased it. Preserve /
#     conditional limiter / normalize, with normalize the default
#     so v0.3 renders are reproducible, and the normalize path now
#     says outright that it nullifies the gain.
#   - Added a silent-output guard. Output_Gain = 0, or a silent
#     source, gave a peak of 0 that v0.3 still handed to
#     Scale peak.
#   - NEW Envelope_mode. The default contour is zero-phase and
#     therefore acausal (see the note above); a causal one-pole
#     attack/release follower is now available. Its recursion uses
#     Praat's in-place left-to-right Formula evaluation, where
#     self[row, col-1] is the previous OUTPUT - normally a hazard,
#     here the mechanism.
#   - NEW Clamp_envelope_to_zero. The rectified signal is
#     non-negative, but a filter with an oscillating impulse
#     response does not preserve that: measured envelope minima
#     were -0.012 at 15 Hz, -0.022 at 20 Hz, -0.045 at 50 Hz and
#     -0.051 at 80 Hz. With positive Sensitivity that pushes the
#     drive BELOW Base_Drive, so the old form label "minimum drive
#     when quiet" was not guaranteed; it now reads "nominal drive
#     at zero envelope", and the clamp restores the floor for
#     those who want it.
#   - FIXED: the transfer curves were clamped to +/-1.15 in VALUE,
#     which the audio never does - Output_Gain is an unbounded
#     `real`, so a manual gain of 3 gave audio near +/-3 against a
#     flat plateau on the panel. Extent measured in a pre-pass,
#     Y axis sized to fit, curves carry the render's level scaling,
#     and the panel title states which stage it shows.
#   - FIXED: every panel drew 0..duration, assuming the Sound's
#     time domain starts at 0. A Sound extracted with times
#     preserved sits at xmin..xmin+duration, so the panels were
#     drawing an empty or wrong window. All axes, reference lines
#     and labels now follow the real domain.
#   - RENAMED preset "Gated Crunch" -> "Polarity-Crossing Crunch",
#     and removed the comment claiming a negative base drive "acts
#     like a gate/expander". It does not gate: at zero envelope the
#     drive is -0.5, so quiet material is attenuated AND
#     polarity-inverted rather than silenced, and the signal
#     vanishes only at the single envelope level 0.05 where the
#     drive crosses zero. Output object name changes from
#     _DynDist_GatedCrunch to _DynDist_PolarityCrossing.
#   - Added validation (Response_Speed_Hz above 0 and below
#     Nyquist; positive attack/release) and notes for the sign
#     cases - negative Sensitivity inverts the dynamics, negative
#     Base_Drive inverts quiet passages, negative or zero
#     Output_Gain inverts or silences the output. All still
#     allowed; none silent any more.
#   - The envelope read is written as object[id, 1, col], the
#     documented three-index sample accessor, rather than the
#     two-argument shorthand.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. Speed matches v0.2.
#   - Architectural cleanup: replaced v0.2's "stereo container"
#     trick (audio in row 1, envelope in row 2 of a single Sound,
#     formula reads object[container, 2, col] from the same object
#     it's modifying) with explicit cross-Sound reference to a
#     separate envelope object. Same audio result; safer pattern
#     that doesn't depend on Praat's row-iteration order. Also
#     removes one Convert-to-mono call (v0.2 did it twice).
#   - Form syntax modernized: optionmenu uses colon.
#   - Removed dead code (unused Get start time / Get end time).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): transfer function with two
#         overlaid curves — quiet (gray, base drive) and loud
#         (red, base + sens*0.5 drive). The visual fingerprint
#         of "what this script does."
#       Panel B (right, headline): envelope + computed drive
#         over time, color-coded
#       Panel C: original vs result waveform (overlaid, gray
#         original + red result)
#       Panel D: output waveform (full file)
#       Panel E: summary stats bar
#   - Header documents the mono-collapse behavior (input goes
#     through Convert to mono regardless of channel count).
# Changelog v0.2:
#   - Fixed object reference (use ID instead of name)
#   - Added drive curve visualization
#   - Improved info output
# ============================================================

# === Form ===
form Dynamic Distortion v0.5
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Manual (use settings below)
        option Touch Sensitive Drive
        option Drum Pumper
        option Polarity-Crossing Crunch
        option Expressive Lead

    comment === Envelope Follower ===
    real Base_Drive 1.0
    comment (nominal drive at zero envelope)
    real Sensitivity 5.0
    comment (how much envelope adds to drive)
    real Response_Speed_Hz 20.0
    comment (zero-phase mode: smoothing cutoff)
    optionmenu Envelope_mode: 1
        option Zero-phase smoothing (v0.2/v0.3, acausal)
        option Causal attack/release follower
    real Attack_ms 5.0
    real Release_ms 50.0
    comment (causal mode only)
    boolean Clamp_envelope_to_zero 0

    comment === Output ===
    real Output_Gain 0.9
    optionmenu Output_level: 3
        option Preserve shaped level
        option Conditional limiter to 0.95
        option Normalize peak to 0.95
    
    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# v0.4 (item 8): every panel drew 0..duration, but a Sound's start time
# is an independent property that merely defaults to 0 - a Sound
# extracted with times preserved can sit at 12..12+duration, in which
# case the panels were drawing a window that holds no data. The real
# domain is captured and used throughout.
xminOrig = Get start time
xmaxOrig = Get end time

# === Handle Presets ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "TouchSensitive"
    base_Drive = 0.8
    sensitivity = 3.0
    response_Speed_Hz = 15.0
    output_Gain = 0.9
elsif preset = 3
    presetName$ = "DrumPumper"
    base_Drive = 1.0
    sensitivity = 8.0
    response_Speed_Hz = 50.0
    output_Gain = 0.8
elsif preset = 4
    # v0.4 (item 5): was "Gated Crunch" / "GatedCrunch", commented as
    # acting "like a gate/expander". It does not gate. With base -0.5 and
    # sensitivity 10 the drive is -0.5 at zero envelope - the signal is
    # not silenced, it is attenuated AND polarity-inverted - and it
    # passes through zero only at envelope 0.05, which is the one level
    # where anything vanishes. Above that the drive is positive and
    # rising. That is a dynamic drive with a null point and a polarity
    # flip below it, so it is named for that.
    presetName$ = "PolarityCrossing"
    base_Drive = -0.5 
    sensitivity = 10.0
    response_Speed_Hz = 80.0
    output_Gain = 1.0
elsif preset = 5
    presetName$ = "ExpressiveLead"
    base_Drive = 1.2
    sensitivity = 4.0
    response_Speed_Hz = 10.0
    output_Gain = 0.9
endif

# v0.4 (item 6): none of the four shaping fields were validated, and
# Response_Speed_Hz feeds a filter directly. These are checks, then
# notes - negative values stay legal as experimental territory, but they
# no longer contradict the header's "loud sections get more distortion"
# in silence.
# v0.4b (item 1): these ran unconditionally, so a perfectly valid causal
# run was blocked by a Response_Speed_Hz the causal path never reads.
# Each mode is now checked only for the parameters it actually uses.
if envelope_mode = 1
    if response_Speed_Hz <= 0
        exitScript: "Response_Speed_Hz must be above 0."
    endif
    if response_Speed_Hz >= sr / 2
        exitScript: "Response_Speed_Hz (" + fixed$(response_Speed_Hz, 1)
            ... + ") must be below the Nyquist frequency (" + fixed$(sr / 2, 1) + ")."
    endif
else
    if attack_ms <= 0 or release_ms <= 0
        exitScript: "Attack and release times must be above 0."
    endif
endif

if envelope_mode = 2
    envShort$ = "causal " + fixed$(attack_ms, 0) + "/" + fixed$(release_ms, 0) + " ms"
else
    envShort$ = "zero-phase " + fixed$(response_Speed_Hz, 0) + " Hz"
endif

if envelope_mode = 2
    envDesc$ = "causal attack/release (" + fixed$(attack_ms, 1) + " / " + fixed$(release_ms, 1) + " ms)"
else
    envDesc$ = "zero-phase smoothing at " + fixed$(response_Speed_Hz, 1) + " Hz (acausal)"
endif

# === Info ===
writeInfoLine: "=== Dynamic Distortion v0.5 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch, starts at ", fixed$(xminOrig, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Base drive: ", fixed$(base_Drive, 2)
appendInfoLine: "Sensitivity: ", fixed$(sensitivity, 2)
appendInfoLine: "Envelope: ", envDesc$
appendInfoLine: "Output gain: ", fixed$(output_Gain, 2)

if sensitivity < 0
    appendInfoLine: "  NOTE: negative Sensitivity inverts the dynamics - louder input LOWERS the drive, and the drive can pass through zero and go negative (polarity inversion)."
endif
if base_Drive < 0
    # v0.4b (item 3): this divided by Sensitivity unconditionally, and
    # Sensitivity = 0 is a legal value - so Base_Drive -0.5 with
    # Sensitivity 0 crashed while BUILDING THE INFO TEXT, before any
    # audio was touched. Whether the crossing point is actually reached
    # is reported later, once the envelope range is known.
    if sensitivity <> 0
        zeroCrossEnv = -base_Drive / sensitivity
        appendInfoLine: "  NOTE: negative Base_Drive means quiet passages are polarity-inverted rather than left clean; the drive passes through zero at envelope ", fixed$(zeroCrossEnv, 4), "."
    else
        zeroCrossEnv = undefined
        appendInfoLine: "  NOTE: negative Base_Drive with Sensitivity 0 applies a constant polarity inversion - the drive never crosses zero."
    endif
else
    zeroCrossEnv = undefined
endif
if output_Gain < 0
    appendInfoLine: "  NOTE: negative Output_Gain inverts the whole output."
endif
if output_Gain = 0
    appendInfoLine: "  NOTE: Output_Gain is 0 - the result will be silent."
endif
if envelope_mode = 1
    appendInfoLine: "  NOTE: zero-phase smoothing is ACAUSAL - the drive begins rising BEFORE a transient (roughly 17 ms at 20 Hz, 3 ms at 80 Hz)."
endif
appendInfoLine: ""

# === Step 1: Mono copy of original ===
appendInfoLine: "Building envelope follower..."

selectObject: original
mono = Convert to mono
Rename: "DynDist_mono"
monoID = selected("Sound")

# === Step 2: Envelope ===
selectObject: monoID
env_temp = Copy: "DynDist_envelope_temp"
Formula: ~ abs(self)

# v0.4 (item 3): "Filter (pass Hann band)" is a frequency-domain filter
# with zero phase and a symmetric impulse response, so it is ACAUSAL -
# energy from a transient spreads backwards in time and the drive starts
# rising before the event that caused it. Measured on a synthetic
# transient, the envelope reaches 10% of its peak 23 ms before the onset
# at 15 Hz, 17 ms at 20 Hz, 5.6 ms at 50 Hz and 3.2 ms at 80 Hz. That is
# audible pre-distortion, and it means Response_Speed_Hz is a smoothing
# cutoff rather than an attack/release time - the script does not behave
# like a pedal or a compressor's follower. It is a legitimate choice for
# an offline tool, so it stays the default, but it is now named
# accurately and a causal alternative is offered.
if envelope_mode = 2
    # Causal one-pole follower with separate attack and release.
    # This relies on Praat's in-place Formula evaluating columns left to
    # right, so self[col - 1] is the PREVIOUS OUTPUT, already written
    # this pass - the recursion the follower needs. (Elsewhere that
    # backward read is a hazard; here it is the mechanism.)
    aAtt = exp(-1 / (sr * attack_ms / 1000))
    aRel = exp(-1 / (sr * release_ms / 1000))
    aAtt$ = string$(aAtt)
    aRel$ = string$(aRel)
    selectObject: env_temp
    Formula: "if col = 1 then self else"
        ... + " (if self > self[row, col - 1]"
        ... + " then " + aAtt$ + " * self[row, col - 1] + (1 - " + aAtt$ + ") * self"
        ... + " else " + aRel$ + " * self[row, col - 1] + (1 - " + aRel$ + ") * self fi) fi"
    Rename: "DynDist_envelope"
    envelope = env_temp
    envelopeID = selected("Sound")
else
    # Low-pass filter to smooth the envelope (zero-phase)
    envelope = Filter (pass Hann band): 0, response_Speed_Hz, 20
    Rename: "DynDist_envelope"
    envelopeID = selected("Sound")
    removeObject: env_temp
endif

# v0.4 (item 4): the rectified signal is non-negative, but a
# frequency-domain filter with an oscillating impulse response does not
# preserve that - ringing around sharp changes drives the envelope
# NEGATIVE. Measured minima: -0.012 at 15 Hz, -0.022 at 20 Hz, -0.045 at
# 50 Hz, -0.051 at 80 Hz. With positive Sensitivity that makes the
# computed drive fall BELOW Base_Drive, so the form's old label
# "minimum drive when quiet" was not guaranteed. The label now says
# "nominal drive at zero envelope"; this option removes the undershoot
# for those who want the floor to hold.
if clamp_envelope_to_zero
    selectObject: envelopeID
    Formula: ~ max(self, 0)
    clampDesc$ = "clamped to >= 0"
else
    clampDesc$ = "raw (may ring negative)"
endif

# === Step 3: Apply Dynamic Distortion ===
# v0.3 uses an explicit cross-Sound reference instead of v0.2's
# "stereo container with row-1/row-2 trick." Same math, safer code.
appendInfoLine: "Applying dynamic distortion..."

selectObject: monoID
Copy: origName$ + "_DynDist_" + presetName$
result = selected("Sound")

# Build formula string with object ID reference
envelopeIDStr$ = string$(envelopeID)
b_str$ = string$(base_Drive)
s_str$ = string$(sensitivity)
g_str$ = string$(output_Gain)

selectObject: result
# Formula: tanh(self * (base + envelope * sensitivity)) * output_gain
# Where envelope is read sample-by-sample from the envelope Sound.
# v0.4: the documented sample accessor for a Sound is
# object[id, row, col]; the envelope is mono, so row 1 is stated
# explicitly rather than relying on the two-argument shorthand.
Formula: "tanh(self * (" + b_str$ + " + object[" + envelopeIDStr$ + ", 1, col] * " + s_str$ + ")) * " + g_str$

# === Step 4: Output level ===
# v0.4 (item 1): v0.3 always ran `Scale peak: 0.95`. Output_Gain is a
# constant scalar applied after tanh, so normalizing the peak divides it
# straight back out: 0.95 * g*f(x) / max|g*f(x)| = 0.95 * f(x) /
# max|f(x)| for every non-zero g. The four presets set gains of 0.8, 0.9
# and 1.0 that could not affect the result at all, and in Manual mode a
# positive gain only mattered before a step that erased it. Normalize
# stays the default so v0.3 renders are reproducible.
# (item 7): a silent result is reachable - Output_Gain 0, or a silent
# source - and v0.3 called Scale peak on it regardless.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "Peak before output stage: ", fixed$(prePeak, 4)

levelScale = 1
if output_level = 1
    levelDesc$ = "preserved"
    if prePeak > 1.0
        appendInfoLine: "  WARNING: peak is ", fixed$(prePeak, 3), " - above 1.0 it will clip on playback or export."
    endif
elsif output_level = 2
    if prePeak > 0.95
        selectObject: result
        Scale peak: 0.95
        levelScale = 0.95 / prePeak
        levelDesc$ = "limited to 0.95"
    else
        levelDesc$ = "unchanged"
    endif
else
    if prePeak > 0
        selectObject: result
        Scale peak: 0.95
        levelScale = 0.95 / prePeak
        levelDesc$ = "normalized to 0.95"
        appendInfoLine: "  NOTE: peak normalization removes the MAGNITUDE of Output_Gain; a negative gain still inverts the output."
    else
        levelDesc$ = "silent output - normalization skipped"
    endif
endif
appendInfoLine: "Output level: ", levelDesc$

# v0.4 (item 2): with normalization active the mapping from a sample
# value to a final amplitude depends on the whole file's peak, so no
# x-only curve can describe it. The curve now carries levelScale, and
# the title says which stage it represents.
if levelScale <> 1
    curveTitle$ = "Transfer (gray=quiet, red=loud, incl. level stage)"
else
    curveTitle$ = "Transfer function (gray=quiet, red=loud)"
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Get envelope range (kept alive for viz; cleaned up after)
selectObject: envelopeID
envMax = Get maximum: 0, 0, "Parabolic"
envMin = Get minimum: 0, 0, "Parabolic"

# Compute drive range from envelope range
# v0.4b (item 2): these assumed Sensitivity >= 0, so with the negative
# Sensitivity the script explicitly supports, envMax produces the LOWEST
# drive and envMin the highest - the two names were swapped. That fed the
# drive panel, where yLo_drive could end up above yHi_drive and invert
# the axis, and the "Drive range" caption reported the bounds backwards.
# Ordered by value now.
driveAtEnvMin = base_Drive + envMin * sensitivity
driveAtEnvMax = base_Drive + envMax * sensitivity
driveMin_calc = min(driveAtEnvMin, driveAtEnvMax)
driveMax_calc = max(driveAtEnvMin, driveAtEnvMax)

# v0.4b (item 3): the crossing point printed earlier is only meaningful
# if the envelope actually reaches it. Now that envMin and envMax are
# known, say whether it does.
if zeroCrossEnv <> undefined
    if zeroCrossEnv >= envMin and zeroCrossEnv <= envMax
        appendInfoLine: "Drive crosses zero within the envelope range (", fixed$(envMin, 4), " to ", fixed$(envMax, 4), ") - polarity flips during the file."
    else
        appendInfoLine: "Drive does NOT cross zero: the crossing sits at envelope ", fixed$(zeroCrossEnv, 4), ", outside the range ", fixed$(envMin, 4), " to ", fixed$(envMax, 4), "."
    endif
endif
appendInfoLine: "Drive range: ", fixed$(driveMin_calc, 3), " to ", fixed$(driveMax_calc, 3)

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    pageHeight = 8.0
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(origName$, "_", "\_ ", 0)
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Dynamic Distortion v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  Base: " + fixed$(base_Drive, 2)
        ... + "  |  Sens: " + fixed$(sensitivity, 2)
        ... + "  |  Env: " + envShort$
        ... + "  |  Drive range: " + fixed$(driveMin_calc, 1) + "-" + fixed$(driveMax_calc, 1)
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION WITH DRIVE OVERLAYS  (left, headline)
    # The defining diagnostic for this script.
    # Two tanh curves overlaid: quiet (low drive, gray) vs loud
    # (high drive, red). Shows the touch-sensitive character.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    # Compute representative drives for "quiet" and "loud" using
    # actual envelope min/max scaled by sensitivity
    driveLow_disp = base_Drive + envMin * sensitivity
    driveHigh_disp = base_Drive + envMax * sensitivity
    
    # For visualization: no clamping of the drive values, so a negative
    # base drive shows as an inverted curve — real behaviour, not hidden.
    #
    # v0.4 (item 2): the curves used to be clamped to +/-1.15 in VALUE,
    # which the audio never does. Output_Gain is an unbounded `real`, so
    # a manual gain of 3 produced audio reaching nearly +/-3 against a
    # flat plateau on the panel. The clamp is gone, the extent is
    # measured in a pre-pass, and the curves carry levelScale — the
    # render's actual peak scaling — so the panel describes the finished
    # output rather than the pre-normalization function.
    nPoints = 200
    
    yLimT = 1.2
    for p from 0 to nPoints
        xs = -1.0 + (p / nPoints) * 2.0
        yLo = tanh(xs * driveLow_disp) * output_Gain * levelScale
        yHi = tanh(xs * driveHigh_disp) * output_Gain * levelScale
        if abs(yLo) * 1.15 > yLimT
            yLimT = abs(yLo) * 1.15
        endif
        if abs(yHi) * 1.15 > yLimT
            yLimT = abs(yHi) * 1.15
        endif
    endfor
    
    Axes: -1.2, 1.2, -yLimT, yLimT
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -yLimT, yLimT
    
    # Grid + identity reference
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -yLimT, 0, yLimT
    
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Low drive curve (quiet sections — gray, behind)
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1.5
    prev_x = -1.0
    prev_y = tanh(prev_x * driveLow_disp) * output_Gain * levelScale
    for p from 1 to nPoints
        curr_x = -1.0 + (p / nPoints) * 2.0
        curr_y = tanh(curr_x * driveLow_disp) * output_Gain * levelScale
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    
    # High drive curve (loud sections — red, on top)
    Colour: "{0.80, 0.30, 0.30}"
    Line width: 2
    prev_x = -1.0
    prev_y = tanh(prev_x * driveHigh_disp) * output_Gain * levelScale
    for p from 1 to nPoints
        curr_x = -1.0 + (p / nPoints) * 2.0
        curr_y = tanh(curr_x * driveHigh_disp) * output_Gain * levelScale
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1
    
    # Legend
    Font size: 6
    Colour: "{0.55, 0.55, 0.55}"
    Text: -1.15, "left", yLimT * 0.92, "half", "gray = quiet (drive " + fixed$(driveLow_disp, 1) + ")"
    Colour: "{0.80, 0.30, 0.30}"
    Text: -1.15, "left", yLimT * 0.83, "half", "red = loud (drive " + fixed$(driveHigh_disp, 1) + ")"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: ENVELOPE + COMPUTED DRIVE  (right, headline-height)
    # Top half: envelope (rectified + low-passed input)
    # Bottom half: computed drive value at each sample
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    # We split the panel vertically: top 50% = envelope, bottom 50% = drive
    # Use a single Axes call covering [-1, +1] vertically with envelope
    # mapped to [0, 0.5] and drive mapped to [-0.5, -1] approximately.
    # Simpler: use two sequential Select inner viewport calls.
    
    # ---- Sub-panel B1: Envelope (top half) ----
    Select outer viewport: 4, 8, 0.75, 2.65
    Select inner viewport: 4.45, 7.70, 0.95, 2.55
    
    selectObject: envelopeID
    envViz_max = envMax * 1.15
    if envViz_max < 0.001
        envViz_max = 0.001
    endif
    
    Axes: xminOrig, xmaxOrig, 0, envViz_max
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, 0, envViz_max
    
    Colour: "{0.30, 0.65, 0.40}"
    Line width: 1.3
    Draw: 0, 0, 0, envViz_max, "no", "Curve"
    Line width: 1
    
    # Min/max reference lines
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: xminOrig, envMax, xmaxOrig, envMax
    Draw line: xminOrig, envMin, xmaxOrig, envMin
    Solid line
    Font size: 6
    Colour: "{0.55, 0.30, 0.55}"
    Text: xminOrig + duration * 0.99, "right", envMax, "bottom", " max " + fixed$(envMax, 3)
    Text: xminOrig + duration * 0.99, "right", envMin, "top", " min " + fixed$(envMin, 3)
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Envelope"
    
    # ---- Sub-panel B2: Computed Drive (bottom half) ----
    Select outer viewport: 4, 8, 2.70, 4.60
    Select inner viewport: 4.45, 7.70, 2.85, 4.40
    
    # Compute drive range with padding for display
    drivePad = (driveMax_calc - driveMin_calc) * 0.10
    if drivePad < 0.1
        drivePad = 0.1
    endif
    yLo_drive = driveMin_calc - drivePad
    yHi_drive = driveMax_calc + drivePad
    
    Axes: xminOrig, xmaxOrig, yLo_drive, yHi_drive
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, yLo_drive, yHi_drive
    
    # Zero line if visible
    if yLo_drive < 0 and yHi_drive > 0
        Colour: "{0.65, 0.65, 0.65}"
        Dotted line
        Draw line: xminOrig, 0, xmaxOrig, 0
        Solid line
    endif
    
    # base_Drive reference line
    if base_Drive >= yLo_drive and base_Drive <= yHi_drive
        Colour: "{0.78, 0.65, 0.78}"
        Dotted line
        Draw line: xminOrig, base_Drive, xmaxOrig, base_Drive
        Solid line
        Font size: 6
        Colour: "{0.55, 0.30, 0.55}"
        Text: xminOrig + duration * 0.01, "left", base_Drive, "bottom", " base " + fixed$(base_Drive, 2)
    endif
    
    # Build drive display Sound (in-place from envelope)
    # We compute drive = base + env * sens by copying envelope and applying formula
    selectObject: envelopeID
    driveDisp = Copy: "DynDist_driveDisp_temp"
    Formula: ~ base_Drive + self * sensitivity
    
    Colour: "{0.78, 0.50, 0.30}"
    Line width: 1.3
    Draw: 0, 0, yLo_drive, yHi_drive, "no", "Curve"
    Line width: 1
    
    removeObject: driveDisp
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Drive"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", curveTitle$
    Text: 6.10, "centre", 7.30, "half", "Envelope (upper) & computed drive (lower)"
    
    # ----------------------------------------------------------
    # PANEL C: ORIGINAL VS RESULT (overlay)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    selectObject: original
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    cmpMax = origPeak
    if resPeak > cmpMax
        cmpMax = resPeak
    endif
    if cmpMax < 0.001
        cmpMax = 0.001
    endif
    cAmpViz = cmpMax * 1.15
    
    Axes: xminOrig, xmaxOrig, -cAmpViz, cAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, -cAmpViz, cAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: xminOrig, 0, xmaxOrig, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        cOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: xminOrig, xmaxOrig, -cAmpViz, cAmpViz, "no", "Curve"
        removeObject: cOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: xminOrig, xmaxOrig, -cAmpViz, cAmpViz, "no", "Curve"
    endif
    
    # Result (red, on top)
    selectObject: result
    Colour: "{0.78, 0.30, 0.30}"
    Line width: 1.3
    Draw: xminOrig, xmaxOrig, -cAmpViz, cAmpViz, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original (gray) vs Dynamic Distortion (red)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file, mono)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    # v0.4b (item 4): this panel was missed in the v0.4 sweep - it still
    # ran 0..finalDur while every other panel had moved to the Sound's
    # real domain, so on a Sound starting at 12.4 s it drew an empty
    # window. (`Draw: 0, 0, ...` is Praat's "whole object" shorthand and
    # was fine, but the axis around it was not.)
    Axes: xminOrig, xmaxOrig, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: xminOrig, 0, xmaxOrig, 0
    
    selectObject: result
    Colour: "{0.20, 0.55, 0.55}"
    Line width: 1
    Draw: xminOrig, xmaxOrig, -ampViz, ampViz, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output (mono)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.60, 7.70, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + vizName$
        ... + "  |  Base: " + fixed$(base_Drive, 2)
        ... + "  |  Sens: " + fixed$(sensitivity, 2)
        ... + "  |  Env: " + envShort$
        ... + "  |  Level: " + levelDesc$
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Envelope: " + fixed$(envMin, 3) + "-" + fixed$(envMax, 3)
        ... + "  |  Drive range: " + fixed$(driveMin_calc, 2) + "-" + fixed$(driveMax_calc, 2)
        ... + "  |  Note: input collapsed to mono"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Line width: 1

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Cleanup ===
removeObject: monoID, envelopeID

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: "Drive range: ", fixed$(driveMin_calc, 2), " - ", fixed$(driveMax_calc, 2)

if play_result
    selectObject: result
    Play
endif

selectObject: result
