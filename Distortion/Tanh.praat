# ============================================================
# Praat AudioTools - Tanh_Soft_Clip.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tanh Soft Clipping - a static saturation curve, y = tanh(kx),
#   often used as a simplified tube/tape-INSPIRED waveshaper. It
#   compresses peaks smoothly rather than hard-clipping them.
#
#   WHAT IT IS NOT (v0.4 correction): v0.3 called this "classic
#   tube/tape-style saturation". The algorithm is a memoryless,
#   symmetric, odd waveshaper and nothing else. On a symmetric sine
#   it produces essentially only ODD harmonics - measured at drive 8,
#   the 2nd and 4th sit below -300 dB while the 3rd is -10.5 dB and
#   the 5th -15.8 dB. There is no bias or asymmetry, no deliberate
#   even-harmonic content, no hysteresis, no memory, no attack or
#   release, no frequency-dependent saturation, no head bump, no
#   high-frequency loss, no transformer behaviour and no tape
#   compression. The preset names likewise select DRIVE LEVELS, not
#   different models - "Tape Style" and "Warm Saturation" were
#   aesthetic labels on the same curve, and have been renamed.
#
#   ALIASING: tanh generates odd harmonics without limit, so without
#   oversampling everything above Nyquist folds back audibly.
#   Measured on a 10 kHz sine at amplitude 0.8 with drive 8 and no
#   oversampling: the alias of the 3rd harmonic landed at 14.1 kHz
#   only 10.5 dB below the fundamental, and the 5th at 5.9 kHz,
#   15.8 dB down. Oversample defaults to 4.
#
#   SATURATION AMOUNT DEPENDS ON INPUT LEVEL. With output
#   normalization on, the drive setting alone does not determine how
#   distorted the result sounds - the source's absolute level does.
#   Measured THD at drive 8: input 0.001 gives 0.001%, 0.1 gives
#   4.4%, 0.5 gives 28.9%, 1.0 gives 37.2%, and all of them come out
#   at the same peak. Input_reference 2 normalizes first so the
#   drive setting means the same thing across sources.
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
#   - FIXED (the inert claim was wrong): Output_level was described as
#     cancelled by normalization. That is true only at Dry_Wet = 1.
#     With any dry signal it sets the RATIO between the wet and dry
#     branches BEFORE the mix, and a final peak normalization cannot
#     undo a change of ratio - at Dry_Wet 0.5, levels of 0.1, 0.7 and
#     2.0 all reached peak 0.95 but differed by up to 0.123 per
#     sample. Renamed Wet_level, and a genuine post-policy makeup
#     gain (Output_gain) is now a separate control that survives
#     every mode. The chain is: tanh -> Wet_level -> dry/wet mix ->
#     output policy -> Output_gain.
#   - FIXED (the transfer panel): v0.4's attempt to draw the FINAL
#     mapping was wrong three ways. Normalization happens AFTER the
#     branches are summed, so the dry branch needed the same factor
#     (drawn 0.4449 against an actual 0.5248 at drive 4 / wet 0.8 /
#     Dry_Wet 0.5 / x = 0.1); Input_reference multiplies before tanh
#     and was ignored entirely (drawn 0.2660 against an actual 0.6993
#     at x = 0.05, drive 8, wet 0.7); and with oversampling a
#     sample's output depends on its neighbours, so no static
#     y = f(x) exists at all - downsampling ringing can push the peak
#     past 1 even though tanh alone is bounded below it. The panel is
#     now the NOMINAL WET WAVESHAPER, which IS a static function,
#     includes the input-reference gain, and lists on the panel what
#     it excludes.
#   - Oversample = 2 is now REFUSED rather than warned about, on the
#     same measurements as Multiband_Distortion: correlation with the
#     source 0.99937 at 1 kHz, 0.93723 at 10 kHz, 0.75681 at 20 kHz.
#     A warning does not prevent the tainted render, and partial
#     Dry/Wet makes it worse by summing shifted wet with unshifted
#     dry.
#   - Silence_floor is exposed and reported. At 1e-9 it is a
#     NUMERICAL-ZERO guard, not a musical one, and it is a hard edge:
#     1.0000e-9 passes untouched while 1.0001e-9 is lifted to the
#     target. Raise it for an audible-level guard, or use "Normalize
#     only if above target", which has no such edge.
#   - The three Drive Comparison loops still ended at x = 0.99; only
#     the main transfer curve was fixed in v0.4.
#   - The half-slope markers follow the effective drive (including
#     input-reference gain) and are labelled as belonging to the WET
#     curve - with partial Dry/Wet the combined slope is wet + dry,
#     so the marked point is not half-slope of the audible result
#     (about 55.4% at Dry_Wet 0.5).
#   - The Dry_Wet form comment notes that 0 returns the dry path at
#     the ORIGINAL level only in Preserve mode.
#   - "input is silent" reworded - a peak of 1e-9 is not silence.
#   - Removed a duplicated input-selection check.
#
# Changelog v0.4:
#   - FIXED: `Scale peak` ran with no check on what it was scaling.
#     Exact silence was safe (Praat leaves an all-zero Sound alone),
#     but any non-zero peak was lifted to the target: inputs peaking
#     at 1e-15, 1e-12, 1e-9, 1e-6 and 0.01 ALL came out at 0.95, so
#     a noise floor or a numerically tiny residue became a
#     near-full-scale signal - and this was the default setting.
#     Output_mode now offers preserve / normalize / normalize-only-
#     above-target, with a near-silence guard on the normalizing path.
#   - NEW Oversample (default 4). v0.3 read the sample rate and never
#     used it; see the aliasing note above.
#   - NEW Input_reference. See the note above on saturation amount
#     following the source level rather than the drive setting.
#   - NEW Dry_Wet, useful at high drive where the wet path approaches
#     a square wave.
#   - RENAMED the presets. Every one uses the same curve and differs
#     in drive and wet level. [v0.4b: v0.4 said the wet level was
#     cancelled and so the presets differed ONLY in drive. That holds
#     at Dry_Wet 1; with any dry signal the wet level sets the
#     branch ratio and does survive. See v0.4b.] Measured THD on a 0.2 sine: drive
#     2 gives 1.2%, 4 gives 4.4%, 8 gives 12.7%, 15 gives 24%, so
#     labelling drive 8 "balanced/moderate" was well off. Object
#     names change (_tanh_Gentle, _tanh_Medium, _tanh_Strong,
#     _tanh_VeryStrong, _tanh_Heavy).
#   - FIXED: the transfer panel drew tanh(x*drive)*output_level while
#     normalization scaled every sample again by a file-dependent
#     factor, so a curve topping out at 0.7 sat under an output
#     reaching 0.95. [v0.4b: the v0.4 attempt to draw the FINAL
#     mapping was itself wrong and has been replaced by an explicitly
#     nominal curve - see v0.4b.]
#   - FIXED: the zoom panels drew 0..zoomDur, assuming the time
#     domain starts at 0.
#   - FIXED: the saturation markers sat at 0.5/drive, where the tanh
#     argument is 0.5 and the output 0.462 - not a threshold in any
#     standard sense. They now mark where the curve's SLOPE has
#     halved, at arccosh(sqrt(2))/drive = 0.8814/drive.
#   - FIXED: the transfer loop's last point was 0.99 rather than 1.0
#     (it ran 2..nPoints over a denominator of nPoints).
#   - Scale_peak is capped at 1.0; a value of 2 produced a final peak
#     of 2.0. The final peak is reported and warned about above 1.
#   - The report now covers sample rate and Nyquist, channels, the
#     time domain, source peak, peak after waveshaping, peak before
#     the output stage, the normalization factor actually applied,
#     the final peak, and the linked multichannel peak policy.
#   - The Drive Comparison panel is labelled as bare tanh shapes with
#     no level controls applied.
#
# Changelog v0.3:
#   - Added "Apply scale peak" toggle (default ON = identical to v0.2).
#     With Scale peak always on, output_level was a uniform post-gain that
#     normalization cancelled out (audibly inert). Turn the toggle OFF to
#     let drive + output_level set the actual level.
#   - Viz: set world axes explicitly before the title text (#32 standard)
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax
#   - Added visualization
#   - Added info output
# ============================================================

form Tanh Soft Clipping v0.5
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset: 1
        option Gentle (drive 2.5)
        option Medium (drive 4)
        option Strong (drive 6)
        option Very strong (drive 8)
        option Heavy (drive 12)
        option Custom (use settings below)

    comment === Saturation ===
    positive Drive_amount 8
    comment (2-2.5 gentle, 4 medium, 6-8 strong, 12-15 heavy)
    positive Wet_level 0.7
    comment (saturated path level, applied BEFORE the dry/wet mix)
    optionmenu Input_reference: 1
        option Use the source level (v0.2/v0.3)
        option Normalize input peak before drive
    integer Oversample 4
    comment (1 = off; tanh aliases badly without it. 2 is disabled)

    comment === Output ===
    optionmenu Output_mode: 1
        option Normalize to target (v0.2/v0.3)
        option Preserve formula level
        option Normalize only if above target
    positive Scale_peak 0.95
    positive Output_gain 1.0
    positive Silence_floor 1e-9
    comment (numerical guard: peaks at or below this are not normalized)
    real Dry_Wet 1.0
    comment (1 = all processed; 0 = dry path, at the original LEVEL only in Preserve mode)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# v0.4 (item 10): Scale_peak and Output_level are `positive` with no ceiling,
# so a Scale_peak of 2 produced a final peak of 2.0 - fine inside Praat, but
# it clips on export or playback. The target is capped; Output_level stays
# free (it is a makeup gain) and the final peak is reported and warned about.
if scale_peak > 1
    exitScript: "Scale_peak must not exceed 1.0 (it is a full-scale target). Use Output_gain for makeup gain."
endif
if dry_Wet < 0 or dry_Wet > 1
    exitScript: "Dry_Wet must be between 0 and 1 (got " + fixed$(dry_Wet, 3) + ")."
endif

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
# v0.4b: 2x is refused, not warned about. The 2x round trip was measured
# twice on Praat 6.1.38 to shift phase with frequency - correlation with the
# source 0.99937 at 1 kHz, 0.93723 at 10 kHz, 0.75681 at 20 kHz - and at
# partial Dry/Wet the shifted wet sums with unshifted dry and comb-filters
# the highs. A warning does not prevent the tainted render. 3x and above
# measured clean (aliases at -129 dB or lower). Delete this block if the
# behaviour is confirmed fixed on the Praat version you target.
if oversample = 2
    exitScript: "Oversample = 2 is disabled. The 2x round trip shifts phase with frequency "
        ... + "(correlation with the source: 0.99937 at 1 kHz, 0.93723 at 10 kHz, 0.75681 at 20 kHz on "
        ... + "Praat 6.1.38), which comb-filters the high end at partial Dry/Wet. Use 1 (off), or 3 and "
        ... + "above - 4 is the default and measured clean."
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels
xminOrig = Get start time
xmaxOrig = Get end time
srcPeak = Get absolute extremum: 0, 0, "None"

# === Apply Presets ===
# v0.4 (items 4 and 5): the old names promised character ("balanced",
# "Warm Saturation", "Tape Style") but every preset differs ONLY in drive -
# the algorithm is the same memoryless tanh curve throughout - and their
# output_level values are cancelled entirely whenever normalization is on,
# which was the default. Measured THD on a 0.2-amplitude sine: drive 2 gives
# 1.2%, 4 gives 4.4%, 8 gives 12.7%, 15 gives 24%. Calling drive 8
# "balanced/moderate" was well off. The presets are now named for the drive
# they set, and output_level is kept (it matters in Preserve mode).
if preset = 1
    drive_amount = 2.5
    wet_level = 0.85
    presetName$ = "Gentle"
elsif preset = 2
    drive_amount = 4
    wet_level = 0.8
    presetName$ = "Medium"
elsif preset = 3
    drive_amount = 6
    wet_level = 0.75
    presetName$ = "Strong"
elsif preset = 4
    drive_amount = 8
    wet_level = 0.7
    presetName$ = "VeryStrong"
elsif preset = 5
    drive_amount = 12
    wet_level = 0.6
    presetName$ = "Heavy"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Tanh Soft Clipping v0.5 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", nChannels, " ch, ", fixed$(xminOrig, 3), "-", fixed$(xmaxOrig, 3), " s, peak ", fixed$(srcPeak, 4), ")"
appendInfoLine: "Sample rate: ", fixed$(sr, 0), " Hz (Nyquist ", fixed$(sr / 2, 1), " Hz)"
appendInfoLine: "Preset: ", presetName$
if osNote$ <> ""
    appendInfoLine: osNote$
endif
appendInfoLine: ""
appendInfoLine: "Drive: ", fixed$(drive_amount, 2)
appendInfoLine: "Wet level: ", fixed$(wet_level, 3), " (scales the saturated path before the mix)"
appendInfoLine: "Output gain: ", fixed$(output_gain, 3), " (after the output policy)"
appendInfoLine: "Oversampling: ", oversample, "x"
appendInfoLine: "Dry/Wet: ", fixed$(dry_Wet, 3)
appendInfoLine: ""
appendInfoLine: "Chain: tanh(x * drive) * wet_level -> dry/wet mix -> output policy -> output gain"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Applying soft clipping..."

selectObject: original
Copy: originalName$ + "_tanh_" + presetName$
result = selected("Sound")

# v0.4 (item 3): with normalization on, the saturation AMOUNT is set by the
# source's absolute level, not by the preset. Measured THD at drive 8 on a
# 200 Hz sine: input 0.001 gives 0.001%, 0.01 gives 0.05%, 0.1 gives 4.4%,
# 0.5 gives 28.9%, 1.0 gives 37.2% - and every one of them comes out at the
# same peak, so a quiet file sounds loud and clean while a hot one sounds
# equally loud and heavily distorted. Normalizing the input first makes the
# drive setting mean the same thing across sources. Off by default, since it
# changes v0.3 renders.
if input_reference = 2
    selectObject: result
    inPk = Get absolute extremum: 0, 0, "None"
    if inPk > silence_floor
        Scale peak: 0.95
        inRefGain = 0.95 / inPk
        inRefDesc$ = "input normalized to 0.95 before drive (was " + fixed$(inPk, 4) + ", gain x" + fixed$(inRefGain, 3) + ")"
    else
        inRefGain = 1
        inRefDesc$ = "input peak " + fixed$(inPk, 12) + " is at or below the guard threshold - normalization skipped"
    endif
else
    inRefGain = 1
    inRefDesc$ = "source level used as-is"
endif

# v0.4 CRITICAL (item 2): v0.3 read the sample rate and never used it. tanh
# generates a series of odd harmonics, and with no oversampling everything
# above Nyquist folds straight back into the audible band. Measured on a
# 10 kHz sine at amplitude 0.8 with drive 8: the alias of the 3rd harmonic
# (30 kHz) landed at 14.1 kHz only 10.5 dB below the fundamental, and the
# alias of the 5th (50 kHz) at 5.9 kHz, 15.8 dB down. Those are not residues.
# The waveshaping now runs at an elevated rate and is band-limited on the way
# back down.
if oversample > 1
    selectObject: result
    upRate = sr * oversample
    Resample: upRate, 50
    upsampled = selected("Sound")
    removeObject: result
    result = upsampled
endif

# Apply soft clipping: tanh(x * drive) * output_level
drive_str$ = string$(drive_amount)
level_str$ = string$(wet_level)

selectObject: result
Formula: "tanh(self * " + drive_str$ + ") * " + level_str$

if oversample > 1
    selectObject: result
    Resample: sr, 50
    downsampled = selected("Sound")
    removeObject: result
    result = downsampled
    # Two rate conversions can round to a different sample count; restore the
    # original length and time domain so the output lines up with the source.
    selectObject: result
    Extract part: xminOrig, xmaxOrig, "rectangular", 1, "yes"
    trimmed = selected("Sound")
    removeObject: result
    result = trimmed
endif

selectObject: result
Rename: originalName$ + "_tanh_" + presetName$
postShapePeak = Get absolute extremum: 0, 0, "None"

# v0.4 (item "dry/wet"): parallel blend, useful at high drive where the wet
# path approaches a square wave.
if dry_Wet < 1
    selectObject: result
    dryRef$ = string$(original)
    wet$ = string$(dry_Wet)
    dry$ = string$(1 - dry_Wet)
    Formula: "self * " + wet$ + " + object[" + dryRef$ + ", row, col] * " + dry$
endif

# === Output stage ===
# v0.4 CRITICAL (item 1): v0.3 ran `Scale peak` with no check on the level it
# was scaling. Exact silence was safe because Praat leaves an all-zero Sound
# alone, but ANY non-zero peak was lifted to the target: measured, inputs
# peaking at 1e-15, 1e-12, 1e-9, 1e-6 and 0.01 ALL produced 0.95. A noise
# floor or a numerically tiny residue became a near-full-scale signal, and
# this was the default setting.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"

normFactor = 1
if output_mode = 2
    outDesc$ = "preserved (drive + wet_level set the level)"
elsif output_mode = 3
    if prePeak > scale_peak
        Scale peak: scale_peak
        normFactor = scale_peak / prePeak
        outDesc$ = "normalized to " + fixed$(scale_peak, 2) + " (was " + fixed$(prePeak, 4) + ")"
    else
        outDesc$ = "unchanged, already below " + fixed$(scale_peak, 2)
    endif
else
    # v0.4b: the threshold is a NUMERICAL-ZERO guard, not a musical
    # near-silence one - it is a hard edge, so a peak of 1.0000e-9 passes
    # through untouched while 1.0001e-9 is lifted to the target. That is a
    # jump of nearly a billion at the boundary. It is exposed and reported
    # rather than hidden at 1e-9 in the code; raise it if you want an
    # audible-level guard, and note that "Normalize only if above target" has
    # no such edge at all.
    if prePeak > silence_floor
        Scale peak: scale_peak
        normFactor = scale_peak / prePeak
        outDesc$ = "normalized to " + fixed$(scale_peak, 2)
    else
        outDesc$ = "peak " + fixed$(prePeak, 12) + " is at or below the guard threshold (" + fixed$(silence_floor, 12) + ") - normalization skipped"
    endif
endif

# v0.4b (blocker 1): v0.4 called this parameter Output_level and the menu
# claimed it was "inert" under normalization. That is true ONLY at
# Dry_Wet = 1. With any dry signal it sets the RATIO between the wet and dry
# branches before the mix, and a final peak normalization cannot undo a
# change of ratio - measured at Dry_Wet 0.5, levels of 0.1, 0.7 and 2.0 all
# reached peak 0.95 but differed by up to 0.123 per sample. It is therefore
# the wet-path level, and is named that now. A genuine post-policy makeup
# gain is a separate control, so it survives every mode.
if output_gain <> 1.0
    selectObject: result
    og$ = string$(output_gain)
    Formula: "self * " + og$
endif

selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "Input reference: ", inRefDesc$
appendInfoLine: "Peak after waveshaping: ", fixed$(postShapePeak, 4)
appendInfoLine: "Peak before output stage: ", fixed$(prePeak, 4)
appendInfoLine: "Output stage: ", outDesc$
if normFactor <> 1
    appendInfoLine: "  Normalization factor applied: ", fixed$(normFactor, 4)
endif
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
if finalPeak > 1.0
    appendInfoLine: "  WARNING: final peak is ", fixed$(finalPeak, 3), " - above 1.0 it will clip on playback or export."
endif
if nChannels > 1
    appendInfoLine: "Note: peak normalization uses one peak for the whole object (linked across channels), preserving the stereo balance."
endif
appendInfoLine: ""

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    pageHeight = 6.65
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(originalName$, "_", "\_ ", 0)

    if output_mode = 1
        outputModeDesc$ = "normalize to target"
    elsif output_mode = 2
        outputModeDesc$ = "preserve formula level"
    else
        outputModeDesc$ = "normalize only above target"
    endif

    # What the nominal curve does NOT include, stated on the panel itself.
    panelNote$ = "excludes: "
    if dry_Wet < 1
        panelNote$ = panelNote$ + "dry mix " + fixed$((1 - dry_Wet) * 100, 0) + "%, "
    endif
    if normFactor <> 1
        panelNote$ = panelNote$ + "norm x" + fixed$(normFactor, 3) + ", "
    endif
    if output_gain <> 1
        panelNote$ = panelNote$ + "out gain x" + fixed$(output_gain, 2) + ", "
    endif
    if oversample > 1
        panelNote$ = panelNote$ + string$(oversample) + "x filters, "
    endif
    if panelNote$ = "excludes: "
        panelNote$ = "this IS the full chain at these settings"
    else
        panelNote$ = panelNote$ + "(shown as numbers, not drawable)"
    endif

    # v0.4b (blocker 2): v0.4 tried to draw the FINAL mapping and could not
    # do so correctly, for three separate reasons:
    #   - normalization happens AFTER the dry and wet branches are summed, so
    #     the dry branch needed the same factor. v0.4 scaled only the wet, and
    #     at drive 4 / wet 0.8 / Dry_Wet 0.5 / normalize 0.95 the drawn value
    #     at x = 0.1 was 0.4449 against an actual 0.5248.
    #   - Input_reference 2 multiplies the signal before tanh, which the curve
    #     ignored entirely: at x = 0.05, drive 8, wet 0.7 the real wet mapping
    #     is 0.6993 and v0.4 drew 0.2660.
    #   - with oversampling the chain includes a resampling filter, tanh, and
    #     an anti-alias filter, so a sample's output depends on its NEIGHBOURS
    #     and there is no static y = f(x) at all. Downsampling ringing can
    #     push the peak past 1 even though tanh alone is bounded below it.
    # The panel is therefore the NOMINAL WET WAVESHAPER, which is a genuine
    # static function, and says so. Dry/wet, normalization and the filters are
    # reported as numbers instead of being folded into a curve that cannot
    # represent them.
    if input_reference = 2 and inRefGain <> 1
        curveTitle$ = "Nominal wet: " + fixed$(wet_level, 2) + " * tanh(" + fixed$(drive_amount * inRefGain, 1) + "x)"
    else
        curveTitle$ = "Nominal wet: " + fixed$(wet_level, 2) + " * tanh(" + fixed$(drive_amount, 1) + "x)"
    endif

    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Tanh Soft Clipping v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | drive " + fixed$(drive_amount, 2) + " | dry/wet " + fixed$(dry_Wet, 2) + " | oversample " + string$(oversample) + "x"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.60, 7.70, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.60, 7.70, 1.7, 2.4
    selectObject: result
    Colour: "{0.7, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Soft Clipped"
    Text bottom: "yes", "Time (s)"
    
    # Zoomed comparison
    # v0.4 (item 8): the zoom drew 0..zoomDur, assuming the Sound's domain
    # starts at 0. On a Sound starting at 2.5 s that window holds no data.
    zoomDur = min(0.02, duration)
    zoomStart = xminOrig
    zoomEnd = xminOrig + zoomDur
    
    Select outer viewport: 0, 4, 2.7, 3.8
    Select inner viewport: 0.60, 3.85, 2.8, 3.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: zoomStart, zoomEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig (zoom)"
    
    Select outer viewport: 4, 8, 2.7, 3.8
    Select inner viewport: 4.45, 7.70, 2.8, 3.7
    selectObject: result
    Colour: "{0.7, 0.6, 0.5}"
    Draw: zoomStart, zoomEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Clipped (zoom)"
    Text bottom: "yes", "Time (s)"
    
    # Transfer function
    Select outer viewport: 0, 4, 4.0, 5.4
    Select inner viewport: 0.60, 3.85, 4.1, 5.3

    nPoints = 200
    curveDrive = drive_amount * inRefGain
    curveScale = wet_level
    yLimT = 1.2
    for p from 0 to nPoints
        xs = -1.0 + p / nPoints * 2.0
        ys = tanh(xs * curveDrive) * curveScale
        if abs(ys) * 1.15 > yLimT
            yLimT = abs(ys) * 1.15
        endif
    endfor

    Axes: -1.2, 1.2, -yLimT, yLimT
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -yLimT, yLimT
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -yLimT, 0, yLimT
    
    # Linear reference (dotted)
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # Draw tanh transfer function
    # v0.4 (item 7): v0.3 drew tanh(x*drive)*output_level, but with
    # normalization on that is not the final mapping - every sample is
    # additionally scaled by a factor derived from the whole file's peak, so
    # a curve topping out at 0.7 sat under an output that reached 0.95.
    # (also: the loop ran p from 2 to nPoints with a denominator of nPoints,
    # so the last point was 0.99 rather than 1.0. Fixed here and, in v0.4b,
    # in the three Drive Comparison loops as well.)
    Colour: "{0.7, 0.6, 0.5}"
    Line width: 2
    for p from 1 to nPoints
        x1 = -1.0 + (p - 1) / nPoints * 2.0
        x2 = -1.0 + p / nPoints * 2.0
        y1 = tanh(x1 * curveDrive) * curveScale
        y2 = tanh(x2 * curveDrive) * curveScale
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1

    # v0.4 (item 9): v0.3 drew markers at 0.5/drive, the input where the tanh
    # argument reaches 0.5 - tanh(0.5) = 0.462, which is not a saturation
    # threshold in any standard sense. The markers now sit where the curve's
    # SLOPE has fallen to half its value at the origin, which is a defined
    # point: d/dx tanh(kx) = k*sech^2(kx), so the slope halves at
    # kx = arccosh(sqrt(2)) = 0.8814.
    # v0.4b (minor 2): the half-slope point belongs to the tanh curve alone.
    # With partial Dry/Wet the combined slope is wet + dry, so the marked
    # point is not half-slope of what you hear (measured about 55.4% at
    # Dry_Wet 0.5). Labelled as the WET curve's point, and it now follows the
    # effective drive including any input-reference gain.
    Colour: "{0.8, 0.7, 0.6}"
    satPoint = 0.8814 / curveDrive
    if satPoint < 1
        Dotted line
        Draw line: satPoint, -yLimT, satPoint, yLimT
        Draw line: -satPoint, -yLimT, -satPoint, yLimT
        Solid line
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", yLimT * 0.93, "half", curveTitle$
    Font size: 6
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0, "centre", -yLimT * 0.80, "half", "wet half-slope at |x| = " + fixed$(satPoint, 3)
    Text: 0, "centre", -yLimT * 0.92, "half", panelNote$
    Font size: 6
    Colour: "Black"

    # Drive comparison
    Select outer viewport: 4, 8, 4.0, 5.4
    Select inner viewport: 4.45, 7.70, 4.1, 5.3
    
    Axes: -1.2, 1.2, -1.2, 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -1.2, 1.2
    
    # Grid
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    Dotted line
    Draw line: -1, -1, 1, 1
    Solid line
    
    # v0.4 (minor): these are the bare tanh shapes at three drive settings -
    # no output_level, no normalization, no dry blend. Labelled as such so the
    # panel is not read as showing this run's output.
    # Draw different drive levels for comparison
    Line width: 1.5
    
    # Low drive (2)
    Colour: "{0.6, 0.8, 0.6}"
    for p from 1 to nPoints
        x1 = -1.0 + (p - 1) / nPoints * 2.0
        x2 = -1.0 + p / nPoints * 2.0
        y1 = tanh(x1 * 2)
        y2 = tanh(x2 * 2)
        Draw line: x1, y1, x2, y2
    endfor
    
    # Medium drive (8)
    Colour: "{0.6, 0.6, 0.8}"
    for p from 1 to nPoints
        x1 = -1.0 + (p - 1) / nPoints * 2.0
        x2 = -1.0 + p / nPoints * 2.0
        y1 = tanh(x1 * 8)
        y2 = tanh(x2 * 8)
        Draw line: x1, y1, x2, y2
    endfor
    
    # High drive (15)
    Colour: "{0.8, 0.6, 0.6}"
    for p from 1 to nPoints
        x1 = -1.0 + (p - 1) / nPoints * 2.0
        x2 = -1.0 + p / nPoints * 2.0
        y1 = tanh(x1 * 15)
        y2 = tanh(x2 * 15)
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    Text: 0, "centre", 1.35, "half", "Drive Comparison (bare tanh; no level controls)"
    
    # Legend
    Font size: 6
    Colour: "{0.6, 0.8, 0.6}"
    Text: -1.0, "left", -0.9, "half", "Drive 2"
    Colour: "{0.6, 0.6, 0.8}"
    Text: -1.0, "left", -1.05, "half", "Drive 8"
    Colour: "{0.8, 0.6, 0.6}"
    Text: -1.0, "left", -1.2, "half", "Drive 15"
    
    Font size: 7
    Colour: "Black"

    # === Summary strip ===
    Select outer viewport: 0, 8, 5.55, 6.60
    Select inner viewport: 0.60, 7.70, 5.63, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizName$ + " | " + fixed$(duration, 2) + " s | " + string$(nChannels) + " ch | source peak " + fixed$(srcPeak, 3) + " | preset " + presetName$
    summary2$ = "##Waveshaper##  y=tanh(kx) | drive " + fixed$(drive_amount, 2) + " | wet level " + fixed$(wet_level, 2) + " | dry/wet " + fixed$(dry_Wet, 2) + " | oversample " + string$(oversample) + "x"
    summary3$ = "##Output##  " + outputModeDesc$ + " | output gain " + fixed$(output_gain, 2) + " | final peak " + fixed$(finalPeak, 3)
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
