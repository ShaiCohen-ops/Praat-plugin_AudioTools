# ============================================================
# Praat AudioTools - VanDerPol_Tube_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Van der Pol Tube Distortion - a parameterized cubic fold
#   waveshaper inspired by the Lienard form associated with the
#   Van der Pol oscillator, with an optional monotonic peak-hold
#   mode and a final hard clamp.
#
#   WHAT IT IS (v0.4 correction). v0.3 stated that
#       y = x - mu * x^3/3
#   IS, up to sign, the Lienard characteristic of
#       x'' - mu(1 - x^2)x' + x = 0
#   and that this "is not an approximation of the tube equation".
#   Both claims were too strong.
#
#   For that equation f(x) = mu(x^2 - 1), so F(x) = mu(x^3/3 - x)
#   and -F(x) = mu*x - mu*x^3/3 = mu*(x - x^3/3). The parameter
#   scales the WHOLE characteristic, linear term included. The code
#   scaled only the cubic term, so the two agree ONLY at mu = 1;
#   elsewhere the parameter moves the fold and inversion points
#   rather than scaling the curve. It is therefore a cubic
#   curvature control, and is now named Cubic_amount.
#   Characteristic 2 gives the properly scaled Van der Pol form.
#
#   Historically, van der Pol expanded the triode's anode-current
#   characteristic about an operating point, and under a symmetry
#   assumption the quadratic term drops out leaving linear and
#   cubic terms. That is a simplified LOCAL model of one triode's
#   curve, not a universal or exact tube I-V law, so "the historical
#   tube nonlinearity the equation was built from" overstates it.
#
#   WHAT THE STRONG PRESETS ACTUALLY SOUND LIKE. The final hard
#   clamp is described below as a safety net, but on the two
#   strongest presets it is a primary shaping element: with a 0.8
#   sine, 68.0% of Aggressive Drive's samples and 85.7% of Fold-back
#   Extreme's sit exactly at +/-0.999. The chain there is cubic fold
#   followed by extensive HARD CLIPPING.
#
#   THE tanh BRANCH IS INAUDIBLE IN EVERY PRESET. It engages above
#   |cubic| = 3 and returns 3*tanh(cubic), which near the threshold
#   is about 2.985 - so at any Output_Gain above roughly 0.335 the
#   result is already past the hard clamp. All five presets use
#   0.4 to 0.98. Verified: output is bit-identical with the branch
#   removed, even on Fold-back Extreme where 81.4% of the input
#   range enters it. Limiter 2 removes it, which also removes a
#   small discontinuity it creates in Manual at low gain.
#
#   ODD HARMONICS. The curve is odd, f(-x) = -f(x), and that gives
#   odd harmonics ONLY for an input that is periodic and centred on
#   zero. A DC offset or asymmetry produces even harmonics too:
#   measured on a 1 kHz sine, the 2nd harmonic sits below -308 dB
#   with no DC and at -9.70 dB with a DC offset of 0.2.
#
#   ALIASING. The fold, the peak-hold corner and the clamp all
#   generate harmonics without limit. Measured alias at 14.1 kHz
#   from a 10 kHz sine: -38.3 dB on Subtle, -11.4 dB on Classic
#   Monotonic, about -9.7 dB on the two strongest presets.
#   Oversample defaults to 4.
#
#   The cubic peaks at |x*Drive| = 1/sqrt(cubicEff), then FOLDS
#   BACK, crosses zero at |x*Drive| = sqrt(3/cubicEff), and INVERTS.
#   Two presets stay monotonic at full-scale input (Subtle, Gentle
#   Warmth); the other three are WAVEFOLDERS in authentic mode.
#   Classic Saturation inverts above input 0.69 and nearly
#   annihilates the fundamental of a hot sine - so its name
#   describes the monotonic Character, not the default one.
#
#   Pipeline:
#     1. Multiply by Drive
#     2. Waveshaper (per Character and Characteristic)
#     3. Multiply by Output_Gain
#     4. Final hard clamp to +/- 0.999
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4b (2026):
#   All three blockers below are v0.4 regressions.
#   - FIXED: the hard clamp ran BEFORE the downsample, so the
#     anti-alias filter's ringing pushed the result back over the
#     ceiling and the promised "final hard clamp to +/-0.999" was
#     not delivered. On a 0.8 sine at 4x the output reached 1.0008
#     (Manual, drive 3), 1.0040 (Aggressive) and 1.0078 (Fold-back
#     Extreme) in local testing, and 1.0231 / 1.0527 / 1.0913 with
#     Praat's own resampler, with 33.6% and 42.2% of final samples
#     above 1 on the two strongest presets. There are now two
#     stages: a SHAPING clamp before the downsample and a final
#     SAFETY clamp after the re-trim, reported separately.
#   - FIXED: the clip fraction was measured on the finished output,
#     after downsampling, which is a different quantity from what
#     the clamp shaped - the filter pulls flat-topped samples back
#     below the threshold and creates new ones near it. Measured
#     67.9% true against 66.2% reported locally, and 67.8% against
#     34.5% with Praat's resampler. The probe now runs immediately
#     before the clamp, at the processing rate.
#   - FIXED: the Monotonic plateau in the transfer panel omitted the
#     curveLin factor that the audio applies, so under
#     Characteristic 2 the drawn plateau was wrong by exactly
#     1/Cubic_amount - at amount 0.2 the panel showed 0.6667 against
#     an audio plateau of 0.1333, five times too high.
#   - Cubic_amount = 0 is now refused. v0.4 refused only negatives
#     while the summary claimed <= 0, and zero behaved differently
#     per characteristic: linear gain under Characteristic 1, total
#     SILENCE under Characteristic 2. The note claiming "a linear
#     gain stage" was wrong for one of them and, being written with
#     appendInfoLine before writeInfoLine, was erased before it
#     could be read anyway.
#   - The undefined-sample check now uses a dedicated probe. Testing
#     `finalPeak = undefined` does not work: a constructed case
#     reported a peak of 0 with half the Sound NaN and no warning.
#   - Version strings updated (form title, Info header, panel title -
#     all three still said v0.3), "Mu" replaced with "Cubic amount"
#     in the panels, and the "Safety net / Threshold: 3.0" display
#     now appears only when the tanh branch is actually in the
#     signal path (it is absent entirely in Monotonic).
#   - The multichannel legend string was computed in v0.4 but never
#     used; Panel C still said "blue=L orange=R" on 4-channel input.
#   - Removed a duplicated input-selection check, and the form and
#     report now state that Limiter has no effect in Monotonic.
#
# Changelog v0.4 (2026):
#   - CORRECTED the central mathematical and historical claims; see
#     the description. Mu renamed Cubic_amount, and Characteristic 2
#     offers the properly scaled Van der Pol form.
#   - NEW Oversample (default 4); v0.3 never read the sample rate.
#   - NEW Limiter option. The tanh branch cannot affect any preset -
#     verified bit-identical output with it removed - and it creates
#     a small discontinuity in Manual at low gain (about 0.00148 at
#     Drive 10, amount 0.01, gain 0.1).
#   - Cubic_amount <= 0 is now handled explicitly. A negative value
#     made the authentic curve expansive with no fold, while the
#     monotonic branch ignored it entirely so 0, -0.1 and -1 all
#     gave identical LINEAR output - and the report still said
#     "pure cubic below full scale".
#   - FIXED: the transfer panel clamped the drawn curve at +/-1.45
#     while the audio clamps at +/-0.999, so the curve ran past the
#     ceiling lines the same panel draws at +/-1. At Classic
#     Authentic, x = 0.95: pre-clamp -1.78, audio -0.999, drawn
#     -1.45. The curve now clamps where the audio does, and the tanh
#     guides are drawn only when that branch is actually visible.
#   - The output object name now includes the Character (_Fold or
#     _Monotonic); v0.3 gave both the same name.
#   - The report adds sample rate, oversampling, the characteristic
#     in use, source peak, pre-clamp peak, the PROPORTION of samples
#     the hard clamp shaped, and an undefined-sample warning.
#   - The waveform legend no longer says "blue=L orange=R" on files
#     with more than two channels.
#   - "identical DSP to v0.1" removed - it was true only of the
#     authentic Character; monotonic mode is new DSP.
#
# Changelog v0.3 (2026):
#   - Description rewritten: the cubic is the Liénard
#     characteristic -- van der Pol's own triode curve -- not a
#     "restoring-force approximation"; and the old claims of
#     guaranteed monotonicity / no inversion were FALSE (the tanh
#     guard engages only after the fold; measured: Classic
#     Saturation inverts above input 0.69, ramp out(0.95) =
#     -0.999).
#   - Character menu: "authentic fold" (v0.2 curve, verified
#     bit-identical) vs "monotonic tube" (peak-hold cubic soft
#     clip, truly monotonic).
#   - The curve-character diagnostic now reports the actual fold
#     and inversion onset inputs instead of only tanh engagement
#     (which mislabeled folding presets "pure cubic").
#   - VIZ: title strip explicit inner viewport; the transfer
#     panel draws the selected Character's true curve.
#
# Changelog v0.2:
#   - NEW: Preset menu (Manual + 5 curated presets, from subtle
#     coloration to extreme tanh-limited fold-back).
#   - NEW: Suite-standard 8x8 visualization: Panel A = transfer
#     function (headline), Panel B = parameter report, Panel C =
#     output waveform, Panel D = summary bar.
#   - NEW: Draw_visualization and Play_result toggles.
#   - Header, form layout and variable casing aligned with the
#     Praat AudioTools house style.
#   - Audio pipeline UNCHANGED from v0.1: bit-identical output for
#     the same Drive / Mu / Output_Gain values.
# Changelog v0.1:
#   - Initial release: cubic Van der Pol waveshaper with tanh
#     safety-clip fallback, Drive / Mu / Output_Gain controls,
#     native mono/stereo handling via per-channel Formula.
# ============================================================

form Van der Pol Tube Distortion v0.4b
    comment Select a Preset (overrides sliders below)
    optionmenu Preset: 1
        option Manual (Use settings below)
        option Subtle Coloration
        option Gentle Tube Warmth
        option Classic Tube Saturation
        option Aggressive Drive
        option Fold-back Extreme

    optionmenu Character: 1
        option authentic fold (the original curve)
        option monotonic tube (peak-hold soft clip)
    optionmenu Characteristic: 1
        option Cubic: z - amount*z^3/3 (v0.2/v0.3)
        option Van der Pol scaled: amount*(z - z^3/3)

    comment Manual Parameters
    positive Drive 3.0
    real Cubic_amount 1.0
    comment (v0.3 called this Mu; see the header - it is not the oscillator's mu)
    real Output_Gain 1.0
    integer Oversample 4
    comment (1 = off; the fold and clamp alias badly without it. 2 is disabled)

    comment Output
    optionmenu Limiter: 1
        option tanh soft limit above 3, then hard clamp (v0.2/v0.3)
        option hard clamp only
    comment (Limiter applies to the fold Character only)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# v0.4: the same 2x round-trip resampling defect measured elsewhere in this
# suite on Praat 6.1.38 (correlation with the source 0.99937 at 1 kHz,
# 0.93723 at 10 kHz, 0.75681 at 20 kHz). 3x and above measured clean.
oversampleReq = oversample
if oversample < 1
    oversample = 1
endif
if oversample > 8
    oversample = 8
endif
osNote$ = ""
if oversample <> oversampleReq
    osNote$ = "  NOTE: Oversample " + string$(oversampleReq) + " is outside 1-8; running at " + string$(oversample) + "." + newline$
endif
if oversample = 2
    exitScript: "Oversample = 2 is disabled - the 2x round trip shifts phase with frequency on Praat 6.1.38. Use 1 (off), or 3 and above; 4 is the default."
endif

# === Handle Presets ===
presetName$ = "Manual"

if preset = 2
    presetName$ = "Subtle"
    drive = 1.05
    cubic_amount = 0.2
    output_Gain = 0.98
elsif preset = 3
    presetName$ = "GentleWarmth"
    drive = 1.2
    cubic_amount = 0.5
    output_Gain = 0.95
elsif preset = 4
    presetName$ = "ClassicSaturation"
    drive = 2.5
    cubic_amount = 1.0
    output_Gain = 0.85
elsif preset = 5
    presetName$ = "Aggressive"
    drive = 5.0
    cubic_amount = 1.5
    output_Gain = 0.6
elsif preset = 6
    presetName$ = "FoldbackExtreme"
    drive = 9.0
    cubic_amount = 3.0
    output_Gain = 0.4
endif

# === Get original details ===
original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
inputDur = Get total duration
inputCh = Get number of channels
sr = Get sampling frequency
xminOrig = Get start time
xmaxOrig = Get end time
srcPeak = Get absolute extremum: 0, 0, "None"

# v0.4 (item 8): the two Characters produce completely different effects but
# v0.3 gave them the same object name, so two runs were indistinguishable in
# the object list. The suffix is part of the name now.
if character = 2
    charSuffix$ = "_Monotonic"
else
    charSuffix$ = "_Fold"
endif

# A fixed ceiling above which the raw cubic is replaced by a tanh soft clip.
# v0.4: v0.3's comment here claimed this stops the waveform inverting. It
# does not - inversion happens at |x*Drive| = sqrt(3/cubicEff), long before
# |cubic| reaches 3 - and the header already said so, so the code and the
# header contradicted each other. In practice the branch is invisible in
# every preset anyway (see the header).
safetyThreshold = 3

# v0.4 CRITICAL: the header claimed y = x - mu*x^3/3 IS the Lienard
# characteristic of x'' - mu(1-x^2)x' + x = 0. It is not, except at mu = 1.
# For that equation f(x) = mu(x^2 - 1), so F(x) = mu(x^3/3 - x) and
# -F(x) = mu*x - mu*x^3/3 = mu*(x - x^3/3): mu scales the WHOLE
# characteristic, linear term included. The code scaled only the cubic term,
# which moves the fold and inversion points instead - so the parameter is a
# cubic curvature control, not the oscillator's mu. Renamed Cubic_amount, and
# Characteristic 2 offers the properly scaled Van der Pol form for anyone who
# wants the actual identity (it changes the sound, hence not the default).
if characteristic = 2
    curveLin = cubic_amount
    curveCub = cubic_amount
    charDesc$ = "Van der Pol scaled: " + fixed$(cubic_amount, 3) + " * (z - z^3/3)"
else
    curveLin = 1
    curveCub = cubic_amount
    charDesc$ = "cubic: z - " + fixed$(cubic_amount, 3) + " * z^3/3"
endif

# cubicEff is what the fold/peak-hold geometry depends on: the ratio of the
# cubic coefficient to the linear one.
if curveLin <> 0
    cubicEff = curveCub / curveLin
else
    cubicEff = 0
endif

# v0.4: Cubic_amount <= 0 was accepted and behaved inconsistently. In
# authentic fold a negative value gives an EXPANSIVE monotonic curve with no
# fold at all; in monotonic tube the branch was skipped entirely so 0, -0.1
# and -1 all produced identical LINEAR output - while the report still said
# "pure cubic below full scale", which was simply false.
# v0.4b: v0.4 refused only NEGATIVE values while the summary claimed <= 0 was
# refused, and zero behaved differently in each characteristic - linear gain
# under Characteristic 1, total SILENCE under Characteristic 2 (0*(z - z^3/3)
# = 0) - while the note claimed "a linear gain stage" in both. The note was
# also written with appendInfoLine before writeInfoLine, so it was erased
# before it could be read. Zero is now refused outright, which is the one
# behaviour that is the same under both characteristics.
if cubic_amount <= 0
    exitScript: "Cubic_amount must be greater than 0. A negative value makes the curve expansive rather than folding (and the monotonic mode ignores it entirely), and zero gives a linear gain stage under Characteristic 1 but total silence under Characteristic 2."
endif

# === Info ===
writeInfoLine: "=== Van der Pol Tube Distortion v0.4b ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(inputDur, 2), " s, ", inputCh, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sample rate: ", fixed$(sr, 0), " Hz  |  Oversampling: ", oversample, "x"
appendInfoLine: "Drive: ", fixed$(drive, 2), " | Cubic_amount: ", fixed$(cubic_amount, 2), " | Output_Gain: ", fixed$(output_Gain, 2)
appendInfoLine: "Characteristic: ", charDesc$
if character = 2
    appendInfoLine: "Character: monotonic tube (peak-hold). Limiter has no effect here - the tanh branch is not in this formula."
else
    if limiter = 1
        appendInfoLine: "Character: authentic fold. Limiter: tanh above ", fixed$(safetyThreshold, 1), ", then clamp (masked by the clamp at any Output_Gain above about 0.335)"
    else
        appendInfoLine: "Character: authentic fold. Limiter: hard clamp only"
    endif
endif
appendInfoLine: "Source peak: ", fixed$(srcPeak, 4)
if osNote$ <> ""
    appendInfoLine: osNote$
endif
appendInfoLine: ""

# ============================================================
# APPLY WAVE SHAPING
# ============================================================

appendInfoLine: "Applying Van der Pol waveshaping..."

# --- Duplicate the sound so the original is left untouched -------
# Copy: also assigns the final "..._VdP_Dist" name directly.
selectObject: original
result = Copy: originalName$ + "_VdP_" + presetName$ + charSuffix$

# --- Apply the waveshaper to every sample, every channel ---------
# Formula... runs per channel automatically, so this works
# unchanged on mono, stereo, or multi-channel sounds.
# v0.4: the fold, the peak-hold corner and the hard clamp all generate
# harmonics without limit, and v0.3 never read the sample rate. Measured
# alias at 14.1 kHz from a 10 kHz sine: -38.3 dB on Subtle but -11.4 dB on
# Classic Monotonic and about -9.7 dB on the two strongest presets. The
# shaping now runs at an elevated rate and is band-limited on the way back.
if oversample > 1
    selectObject: result
    Resample: sr * oversample, 50
    upsampled = selected("Sound")
    removeObject: result
    result = upsampled
endif

lin$ = string$(curveLin)
cub$ = string$(curveCub)

selectObject: result
if character = 1
    # authentic fold: the v0.2 curve, generalized to the selected
    # characteristic (identical to v0.3 when Characteristic = 1)
    if limiter = 1
        Formula: "if abs(" + lin$ + "*(self*drive) - " + cub$ + "*((self*drive)^3)/3) > " + string$(safetyThreshold)
            ... + " then tanh(" + lin$ + "*(self*drive) - " + cub$ + "*((self*drive)^3)/3) * " + string$(safetyThreshold)
            ... + " else " + lin$ + "*(self*drive) - " + cub$ + "*((self*drive)^3)/3 fi"
    else
        Formula: "" + lin$ + "*(self*drive) - " + cub$ + "*((self*drive)^3)/3"
    endif
else
    # monotonic tube: hold the cubic's peak beyond |x*drive| = 1/sqrt(cubicEff)
    if cubicEff > 0
        foldPoint = 1 / sqrt(cubicEff)
        peakHold = curveLin * (2/3) / sqrt(cubicEff)
        Formula: "if abs(self*drive) > " + string$(foldPoint)
            ... + " then (if self > 0 then " + string$(peakHold) + " else " + string$(-peakHold) + " fi)"
            ... + " else " + lin$ + "*(self*drive) - " + cub$ + "*((self*drive)^3)/3 fi"
    else
        Formula: "" + lin$ + "*(self*drive)"
    endif
endif

# --- Output gain compensation -------------------------------------
Formula: ~ self * output_Gain

selectObject: result
preClampPeak = Get absolute extremum: 0, 0, "None"

# v0.4b (blocker 2): the clip fraction has to be measured HERE, before the
# clamp and while still at the elevated rate. v0.4 measured it on the
# finished output, after downsampling, which is a different quantity - the
# filter pulls flat-topped samples back below the threshold and creates new
# ones near it. Measured on Aggressive: 67.9% truly clamped against 66.2%
# reported; on Fold-back Extreme, 85.8% against 82.5%. (The reviewer's Praat
# figures were 67.8/34.5 and 85.9/43.1 - the discrepancy is larger with
# Praat's own resampler.)
selectObject: result
Copy: "vdp_clip_probe"
clipProbe = selected("Sound")
Formula: ~ if abs(self) > 0.999 then 1 else 0 fi
clipFraction = Get mean: 0, 0, 0
removeObject: clipProbe
selectObject: result

# --- Shaping clamp -------------------------------------------------
# v0.4b: named a SHAPING clamp, because that is what it is at these
# settings, and because it is no longer the last thing that happens.
Formula: ~ if self > 0.999 then 0.999 else if self < -0.999 then -0.999 else self fi fi

if oversample > 1
    selectObject: result
    Resample: sr, 50
    downsampled = selected("Sound")
    removeObject: result
    result = downsampled
    # Two rate conversions can round to a different sample count; restore the
    # source's exact domain and length.
    selectObject: result
    Extract part: xminOrig, xmaxOrig, "rectangular", 1, "yes"
    trimmed = selected("Sound")
    removeObject: result
    result = trimmed
    selectObject: result
    Rename: originalName$ + "_VdP_" + presetName$ + charSuffix$
endif

# --- Final safety clamp, AFTER downsampling ------------------------
# v0.4b (blocker 1): v0.4 applied the clamp before the downsample, so the
# anti-alias filter's ringing then pushed the result back over the ceiling -
# the header promised a "final hard clamp to +/-0.999" that the file did not
# deliver. Measured overshoot past 1.0 on a 0.8 sine at 4x, with output
# reaching 1.0008 (Manual, drive 3), 1.0040 (Aggressive) and 1.0078
# (Fold-back Extreme); the reviewer measured 1.0231, 1.0527 and 1.0913 with
# Praat's own resampler, with 33.6% and 42.2% of the final samples above 1
# on the two strongest presets. A second clamp after the re-trim restores
# the guarantee. It can reintroduce a little aliasing, which is the price of
# an actual ceiling; the two clamps are reported separately.
selectObject: result
postDownPeak = Get absolute extremum: 0, 0, "None"

Copy: "vdp_safety_probe"
safetyProbe = selected("Sound")
Formula: ~ if abs(self) > 0.999 then 1 else 0 fi
safetyFraction = Get mean: 0, 0, 0
removeObject: safetyProbe

selectObject: result
Formula: ~ if self > 0.999 then 0.999 else if self < -0.999 then -0.999 else self fi fi

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# v0.4b (item 5): v0.4 tested `finalPeak = undefined`, but Get absolute
# extremum can return a finite number while some samples are undefined - a
# constructed case gave a reported peak of 0 with half the Sound NaN and no
# warning at all. A dedicated probe counts them.
selectObject: result
Copy: "vdp_nan_probe"
nanProbe = selected("Sound")
Formula: ~ if self = undefined then 1 else 0 fi
nanFraction = Get mean: 0, 0, 0
removeObject: nanProbe
selectObject: result

if nanFraction > 0
    appendInfoLine: "  WARNING: ", fixed$(nanFraction * 100, 2), "% of the output samples are undefined. Extreme Drive / Cubic_amount combinations overflow before the limiter."
endif

appendInfoLine: ""
appendInfoLine: "Peak before the shaping clamp: ", fixed$(preClampPeak, 4)
appendInfoLine: "Samples shaped by the shaping clamp: ", fixed$(clipFraction * 100, 1), "% (measured at the processing rate, before the clamp)"
if clipFraction > 0.2
    appendInfoLine: "  NOTE: at these settings the clamp is a primary shaping element, not a safety net."
endif
if oversample > 1
    appendInfoLine: "Peak after downsampling, before the final clamp: ", fixed$(postDownPeak, 4)
    if safetyFraction > 0
        appendInfoLine: "  Caught by the final safety clamp: ", fixed$(safetyFraction * 100, 2), "% (anti-alias ringing overshoot)"
    endif
endif
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
appendInfoLine: ""

if nResultCh = 1
    chanLegend$ = "(mono)"
elsif nResultCh = 2
    chanLegend$ = "(blue=ch1  orange=ch2)"
else
    chanLegend$ = "(channels 1-2 of " + string$(nResultCh) + " shown)"
endif

# Diagnostic (v0.3): where does the curve fold and invert, in
# INPUT units? Fold onset = 1/(sqrt(cubicEff)*drive); inversion onset
# = sqrt(3/mu)/drive. Reported honestly per Character.
if cubicEff > 0
    foldOnset = 1 / (sqrt(cubicEff) * drive)
    invOnset = sqrt(3 / cubicEff) / drive
else
    foldOnset = 1e9
    invOnset = 1e9
endif
if character = 2
    if foldOnset >= 1
        character$ = "monotonic tube: pure cubic below full scale"
    else
        character$ = "monotonic tube: peak-hold above x = " + fixed$(foldOnset, 2)
    endif
else
    if foldOnset >= 1
        character$ = "warm: no folding below full scale"
    elsif invOnset >= 1
        character$ = "folds above x = " + fixed$(foldOnset, 2) + " (no inversion below full scale)"
    else
        character$ = "folds above x = " + fixed$(foldOnset, 2) + ", INVERTS above x = " + fixed$(invOnset, 2)
    endif
endif

appendInfoLine: "Curve character: ", character$
appendInfoLine: ""

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##VAN DER POL CUBIC WAVESHAPER v0.4b##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Cubic: " + fixed$(cubic_amount, 2)
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)

    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic for any waveshaper.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5

    # Grid: zero axes
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5

    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.5, -1.5, 1.5, 1.5
    Solid line
    Font size: 5
    Text: -1.45, "left", -1.40, "half", "y = x"

    # Digital ceiling (final hard clamp at +/- 0.999)
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: -1.5, 1, 1.5, 1
    Draw line: -1.5, -1, 1.5, -1
    Solid line
    Font size: 5
    Colour: "{0.55, 0.30, 0.55}"
    Text: -1.45, "left", 1, "bottom", " ceiling"
    Text: -1.45, "left", -1, "top", " -ceiling"

    # Approximate tanh safety-clip zone (safetyThreshold * output_Gain)
    safetyY = safetyThreshold * output_Gain
    # v0.4 (item 2): these guides are drawn only when the tanh branch can
    # actually be seen. With any Output_Gain above about 0.335 the branch
    # output (3*tanh(3) = 2.985) is already past the hard clamp, so every
    # preset masks it entirely - verified bit-identical output with the
    # branch removed.
    if limiter = 1 and safetyY < 0.999
        Colour: "{0.55, 0.78, 0.55}"
        Dotted line
        Draw line: -1.5, safetyY, 1.5, safetyY
        Draw line: -1.5, -safetyY, 1.5, -safetyY
        Solid line
        Font size: 5
        Colour: "{0.30, 0.55, 0.30}"
        Text: -1.45, "left", safetyY, "bottom", " tanh safety"
        Text: -1.45, "left", -safetyY, "top", " -tanh safety"
    endif

    # Draw the actual transfer function (matches the audio Formula
    # chain exactly: cubic + tanh fallback, then output gain, then
    # hard clamp).
    Colour: "{0.80, 0.40, 0.40}"
    Line width: 2
    nPoints = 200

    prev_x = -1.5
    prev_driven = prev_x * drive
    prev_cubic = curveLin * prev_driven - curveCub * (prev_driven^3) / 3
    if character = 2 and cubicEff > 0 and abs(prev_driven) > 1/sqrt(cubicEff)
        prev_y = curveLin * (2/3) / sqrt(cubicEff)
        if prev_driven < 0
            prev_y = -prev_y
        endif
    elsif abs(prev_cubic) > safetyThreshold and character = 1 and limiter = 1
        prev_y = tanh(prev_cubic) * safetyThreshold
    else
        prev_y = prev_cubic
    endif
    prev_y = prev_y * output_Gain
    # v0.4 (item 7): v0.3 clamped the DRAWN curve at +/-1.45 while the audio
    # clamps at +/-0.999, so the panel showed the curve running well past the
    # digital-ceiling lines it draws at +/-1 - at Classic Authentic with
    # x = 0.95 the pre-clamp value is about -1.78, the audio produces -0.999,
    # and v0.3 drew -1.45. The curve now clamps exactly where the audio does.
    if prev_y > 0.999
        prev_y = 0.999
    endif
    if prev_y < -0.999
        prev_y = -0.999
    endif

    for i from 1 to nPoints
        curr_x = -1.5 + (i / nPoints) * 3.0
        driven = curr_x * drive
        cubic = curveLin * driven - curveCub * (driven^3) / 3
        if character = 2 and cubicEff > 0 and abs(driven) > 1/sqrt(cubicEff)
            curr_y = curveLin * (2/3) / sqrt(cubicEff)
            if driven < 0
                curr_y = -curr_y
            endif
        elsif abs(cubic) > safetyThreshold and character = 1 and limiter = 1
            curr_y = tanh(cubic) * safetyThreshold
        else
            curr_y = cubic
        endif
        curr_y = curr_y * output_Gain
        if curr_y > 0.999
            curr_y = 0.999
        endif
        if curr_y < -0.999
            curr_y = -0.999
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"

    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    # Section: Waveshaping
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Waveshaping parameters:"

    Font size: 11
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.84, "half", "Drive:    " + fixed$(drive, 2)
    Text: 0.10, "left", 0.76, "half", "Cubic amt: " + fixed$(cubic_amount, 2)

    # Section: Safety
    # v0.4b: v0.4 displayed "Safety net / Threshold: 3.0" unconditionally,
    # including when Limiter was set to hard-clamp-only and when Character
    # was Monotonic - where the tanh branch does not exist in the formula at
    # all. Shown only when it is actually in the signal path.
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.65, "half", "Limiting:"

    Font size: 11
    Colour: "{0.40, 0.55, 0.78}"
    if limiter = 1 and character = 1
        Text: 0.10, "left", 0.56, "half", "tanh above " + fixed$(safetyThreshold, 1) + ", then clamp"
    else
        Text: 0.10, "left", 0.56, "half", "hard clamp only"
    endif

    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.48, "half", "(" + character$ + ")"

    # Section: Output
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.36, "half", "Output:"

    Font size: 11
    Colour: "{0.40, 0.65, 0.40}"
    Text: 0.10, "left", 0.27, "half", "Gain:     " + fixed$(output_Gain, 2)

    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.19, "half", "Hard clamp +/- 0.999 (final safety net)"

    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Transfer function (input -> output)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"

    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15

    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0

    selectObject: result
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1

        if nResultCh >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  " + chanLegend$
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Cubic: " + fixed$(cubic_amount, 2)
        ... + "  |  Out gain: " + fixed$(output_Gain, 2)

    Text: 0.02, "left", 0.28, "half",
        ... "Safety threshold: " + fixed$(safetyThreshold, 1)
        ... + "  |  " + character$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final ===
selectObject: result

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
