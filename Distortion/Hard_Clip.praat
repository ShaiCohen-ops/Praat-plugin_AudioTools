# ============================================================
# Praat AudioTools - Hard Clip (Variable Knee)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - knee range guard, peak reporting, derived plot axes
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Applies hard clipping with a configurable "Soft Knee".
#   - Below (Threshold - Knee): Linear
#   - Between (Threshold +/- Knee): Smooth Quadratic Curve
#   - Above (Threshold + Knee): Hard Clamp
#
#   The linear zone is linear but NOT 1:1 as v0.2 claimed: the input is
#   pre-multiplied by Drive and the output post-multiplied by
#   Output_Gain, so the source-to-output slope there is
#   Drive * Output_Gain. It is 1:1 only when that product is 1.
#
#   Knee_half_width is a HALF-width: the knee spans Threshold +/- it, so
#   the total transition region is twice the number entered. It must not
#   exceed Threshold - above that the quadratic goes negative around
#   zero and inverts the polarity of quiet samples, which the script now
#   refuses.
#
#   Note that Output_Gain here is a real level control - unlike several
#   other scripts in this suite there is no forced normalization, so
#   Output_level defaults to Preserve.
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - FIXED (the knee could invert polarity): nothing prevented
#     Knee_half_width exceeding Threshold, and above that the
#     quadratic knee breaks down. At |in| = 0 it evaluates to
#     T - (T+K)^2/(4K) = -(K-T)^2/(4K), which is negative - at
#     T = 0.5, K = 1.0 the magnitude at zero is -0.0625, so the
#     sign-restore step flipped small positive samples negative and
#     small negative samples positive, while a sample of exactly
#     zero jumped back to zero because sign_restore is 0 there.
#     Polarity inversion plus a discontinuity around silence, worst
#     on the quietest material. All five presets are inside the
#     legal range; only Manual was exposed. Now refused outright
#     rather than clamped, so the sound never changes silently.
#   - NEW: Knee_half_width = 0 gives an exact hard clamp. v0.2
#     forced it up to 0.001, so the thing "Brickwall Limiter"
#     describes could not actually be requested.
#   - NEW Output_level and Peak_target, plus peak measurement. The
#     plateau after clipping is Threshold, so the ceiling is
#     Threshold * |Gain| - Threshold 0.8 with Gain 2 gives +/-1.6,
#     past full scale with no measurement or warning in v0.2.
#     Preserve is the default, because Output_Gain is a genuine
#     level control here and forcing normalization would erase it.
#   - FIXED: the LTAS panel compared the raw original with the
#     fully processed result, so what it showed as "harmonic
#     generation" also carried every level change. With Drive 2 and
#     the signal below the knee the transfer is just y = 2x - the
#     red trace sits ~6 dB high with no harmonics created; a low
#     Output_Gain can put it below the grey while harmonics ARE
#     being generated. Spectrum_reference now matches peaks by
#     default.
#   - FIXED: the transfer panel used a single limit, threshold*1.5,
#     for both axes. The transition points in SOURCE terms are
#     (T-K)/|Drive| and (T+K)/|Drive| and the ceiling is T*|Gain|,
#     so with Threshold 0.8, Knee 0.1, Drive 0.1 the plateau starts
#     at x = 9 against a panel ending near 1.2 - no clipping
#     visible - and with Threshold 0.5, Gain 4 the +/-2 ceiling ran
#     off a +/-1 axis. Derived separately now, and the curve
#     carries the render's level scaling.
#   - FIXED: the plot loop had no zero branch for the sign restore
#     while the initial point did, so at x = 0 - which an even step
#     count lands on exactly - the curve used +1 where the Formula
#     uses 0.
#   - CORRECTED "Linear (1:1)": the slope is Drive * Output_Gain,
#     now stated and reported.
#   - RENAMED Knee_Width to Knee_half_width. The knee spans
#     Threshold +/- it, so entering 0.2 gave a 0.4-wide region.
#   - Parameter clamping is reported instead of silent (an
#     Oversample of 20 ran as 8 with no mention), and Peak_target
#     is capped at 1.0.
#   - The report was two lines - filename and preset. It now covers
#     drive, threshold, knee, gain, effective oversampling, source
#     peak, predicted ceiling, pre-stage peak, level action,
#     measured peak, and the sign cases for Drive and Output_Gain.
# ============================================================

# === Form ===
form Hard Clip (Variable Knee) v0.3
    comment Select a Preset (overrides sliders below)
    optionmenu Preset: 1
        option Manual (Use settings below)
        option Brickwall Limiter
        option Soft Clipper
        option Hard Distortion
        option Subtle Glue
        option Fuzz Face (Low Thresh)

    comment Parameters
    real Drive 1.0
    real Threshold 0.5
    real Knee_half_width 0.2
    comment (knee spans Threshold +/- this, so total width is 2x; 0 = exact hard clip)
    real Output_Gain 0.9
    
    comment Anti-aliasing (oversample factor; clipping aliases without it)
    integer Oversample 4

    comment Output
    optionmenu Output_level: 1
        option Preserve shaped level (v0.2)
        option Conditional limiter to target
        option Normalize to target
    positive Peak_target 0.95

    comment Visualization
    boolean Draw_visualization 1
    optionmenu Spectrum_reference: 1
        option Matched peak (isolates harmonics)
        option Absolute rendered levels
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# === Handle Presets ===
# Praat automatically makes form variables lowercase (Preset -> preset)
presetName$ = "Manual"

if preset = 2
    presetName$ = "Brickwall Limiter"
    drive = 1.2
    threshold = 0.8
    knee_half_width = 0.05
    output_Gain = 0.95
elsif preset = 3
    presetName$ = "Soft Clipper"
    drive = 2.0
    threshold = 0.6
    knee_half_width = 0.4
    output_Gain = 0.8
elsif preset = 4
    presetName$ = "Hard Distortion"
    drive = 5.0
    threshold = 0.4
    knee_half_width = 0.01
    output_Gain = 0.6
elsif preset = 5
    presetName$ = "Subtle Glue"
    drive = 1.0
    threshold = 0.7
    knee_half_width = 0.5
    output_Gain = 1.0
elsif preset = 6
    presetName$ = "Fuzz Face (Low Thresh)"
    drive = 8.0
    threshold = 0.1
    knee_half_width = 0.1
    output_Gain = 0.5
endif

# === Validation ===
# v0.3 (item 8): v0.2 silently rewrote out-of-range values - a requested
# Oversample of 20 ran as 8, a Knee of 0 became 0.001 - and told the user
# nothing. Every adjustment is now either refused or reported.
clampNotes$ = ""

if threshold < 0.01
    clampNotes$ = clampNotes$ + "  NOTE: Threshold raised from " + fixed$(threshold, 4) + " to 0.01 (minimum)." + newline$
    threshold = 0.01
endif
if threshold > 1
    clampNotes$ = clampNotes$ + "  NOTE: Threshold of " + fixed$(threshold, 3) + " is above full scale; the clipper will not engage on normal material." + newline$
endif

# v0.3 CRITICAL (item 1): nothing stopped Knee_half_width exceeding
# Threshold, and above that the quadratic knee breaks down completely.
# At |in| = 0 the knee evaluates to T - (T+K)^2/(4K) = -(K-T)^2/(4K),
# which is NEGATIVE - so with T = 0.5 and K = 1.0 the magnitude at zero
# is -0.0625, the sign-restore step then flips small positive samples
# negative and small negative samples positive, and a sample of exactly
# zero jumps back to zero because sign_restore is 0 there. The result is
# polarity inversion plus a discontinuity around silence: the opposite
# of soft clipping, and worst on the quietest material. All five presets
# are inside the legal range; only Manual was exposed. Refused rather
# than silently clamped, since clamping would change the sound without
# the user knowing which knee they actually got.
if knee_half_width < 0
    exitScript: "Knee half-width cannot be negative."
endif
if knee_half_width > threshold
    exitScript: "Knee half-width (" + fixed$(knee_half_width, 4)
        ... + ") must not exceed Threshold (" + fixed$(threshold, 4)
        ... + "). Above that the knee formula goes negative around zero and inverts the polarity of quiet samples."
endif

# v0.3: Knee = 0 is now a real option. v0.2 forced it up to 0.001, so an
# exact hard clamp - the thing "Brickwall Limiter" describes - could not
# be requested at all.
if knee_half_width = 0
    exactClip = 1
    kneeDesc$ = "exact hard clip (no knee)"
else
    exactClip = 0
    kneeDesc$ = "quadratic soft knee, +/-" + fixed$(knee_half_width, 4) + " (total width " + fixed$(2 * knee_half_width, 4) + ")"
endif

# Get original object details
original = selected("Sound")
origName$ = selected$("Sound")
selectObject: original
xmin = Get start time
xmax = Get end time
sampling_rate = Get sampling frequency
inputChannels = Get number of channels
srcPeak = Get absolute extremum: 0, 0, "None"

oversampleReq = oversample
if oversample < 1
    oversample = 1
endif
if oversample > 8
    oversample = 8
endif
if oversample <> oversampleReq
    clampNotes$ = clampNotes$ + "  NOTE: Oversample of " + string$(oversampleReq)
        ... + " is outside the supported range 1-8; running at " + string$(oversample) + "." + newline$
endif
if oversample > 1
    oversampleDesc$ = " (clipping at " + string$(sampling_rate * oversample) + " Hz, then band-limited back)"
else
    oversampleDesc$ = " (no oversampling - the clipper will alias)"
endif

if peak_target > 1
    exitScript: "Peak_target must not exceed 1.0 (it is a full-scale target)."
endif

# === Process Audio ===
# Work on a copy. If oversampling, the clipping nonlinearity is applied at a
# higher sample rate, then resampled back - Praat's downsampling resampler
# band-limits, removing the harmonics that would otherwise fold back as aliasing.
selectObject: original
work = Copy: "Clip_work"
if oversample > 1
    selectObject: work
    upsamp = Resample: sampling_rate * oversample, 50
    removeObject: work
    work = upsamp
endif

# -----------------------------------------------------------------------
# ROBUST FORMULA GENERATION (Boolean Math)
# All variables here must start with lowercase to avoid syntax errors
# -----------------------------------------------------------------------

# 1. Define Constants (String representations)
t_str$ = string$(threshold)
k_str$ = string$(knee_half_width)
t_minus_k$ = string$(threshold - knee_half_width)
t_plus_k$ = string$(threshold + knee_half_width)
drive_str$ = string$(drive)

# 2. Input Definition
# We calculate Input and Absolute Input
in$ = "(self * " + drive_str$ + ")"
absIn$ = "abs(" + in$ + ")"

# 3. Zone Logic (Boolean Switches)
# Returns 1 if true, 0 if false
# Using lowercase variable names for the strings
is_linear$ = "(" + absIn$ + " <= " + t_minus_k$ + ")"
is_flat$   = "(" + absIn$ + " >= " + t_plus_k$ + ")"
is_knee$   = "((" + absIn$ + " > " + t_minus_k$ + ") * (" + absIn$ + " < " + t_plus_k$ + "))"

# 4. Zone Math
# Linear Zone: Just pass the absolute input
val_linear$ = absIn$

# Flat Zone: Clamp to Threshold
val_flat$   = t_str$

# Knee Zone: Quadratic Bezier Curve
# Formula: T - ( (T+K - AbsIn)^2 / (4K) )
numerator$ = "(" + t_plus_k$ + " - " + absIn$ + ")^2"
denominator$ = "(4 * " + k_str$ + ")"
val_knee$   = "(" + t_str$ + " - (" + numerator$ + " / " + denominator$ + "))"

# 5. Combine Logic
# sum = (isLinear * valLin) + (isFlat * valFlat) + (isKnee * valKnee)
combined_abs$ = "( (" + is_linear$ + " * " + val_linear$ + ") + (" + is_flat$ + " * " + val_flat$ + ") + (" + is_knee$ + " * " + val_knee$ + ") )"

# v0.3: exact hard clip when the knee is zero. The three-zone boolean sum
# above divides by 4K, so it cannot be used at K = 0.
if exactClip
    combined_abs$ = "min(" + absIn$ + ", " + t_str$ + ")"
endif

# 6. Restore Sign and Apply Gain
# sign(x) is approximated by ((x>0) - (x<0)) to be version-safe
sign_restore$ = "((" + in$ + ">0) - (" + in$ + "<0))"
final_formula$ = combined_abs$ + " * " + sign_restore$ + " * " + string$(output_Gain)

# Apply the transfer function (at the oversampled rate if enabled)
selectObject: work
Formula: final_formula$

# Resample back to the original rate (anti-aliased) and name the result
if oversample > 1
    selectObject: work
    downsamp = Resample: sampling_rate, 50
    removeObject: work
    work = downsamp
endif
result = work
selectObject: result
Rename: origName$ + "_Clip_" + replace$(presetName$, " ", "", 0)

# === Output level ===
# v0.3 (item 2): v0.2 applied Output_Gain and stopped. The plateau after
# clipping is Threshold, so the output ceiling is Threshold * |Gain| -
# with Threshold 0.8 and Gain 2 that is +/-1.6, well past full scale,
# with no limiter, no measurement and no warning. Unlike several other
# scripts in this suite there is no forced normalization here, which is
# right: Output_Gain genuinely controls the level. So Preserve stays the
# default and only a peak guard is added.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
predictedCeiling = threshold * abs(output_Gain)

levelScale = 1
if output_level = 1
    levelDesc$ = "preserved"
elsif output_level = 2
    if prePeak > peak_target
        selectObject: result
        Scale peak: peak_target
        levelScale = peak_target / prePeak
        levelDesc$ = "limited to " + fixed$(peak_target, 2)
    else
        levelDesc$ = "unchanged (below target)"
    endif
else
    if prePeak > 0
        selectObject: result
        Scale peak: peak_target
        levelScale = peak_target / prePeak
        levelDesc$ = "normalized to " + fixed$(peak_target, 2)
    else
        levelDesc$ = "silent output - scaling skipped"
    endif
endif

selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration

# === Report ===
# v0.3 (item 9): v0.2's entire report was two lines - the file name and
# the preset. For a distortion tool the numbers below are what let you
# verify a preset or reproduce a result.
writeInfoLine: "=== Hard Clip (Variable Knee) v0.3 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(xmax - xmin, 2), " s, ", inputChannels, " ch, peak ", fixed$(srcPeak, 4), ")"
appendInfoLine: "Preset: ", presetName$
if clampNotes$ <> ""
    appendInfoLine: clampNotes$
endif
appendInfoLine: ""
appendInfoLine: "Drive: ", fixed$(drive, 3)
appendInfoLine: "Threshold: ", fixed$(threshold, 4)
appendInfoLine: "Knee: ", kneeDesc$
appendInfoLine: "Output gain: ", fixed$(output_Gain, 3)
appendInfoLine: "Oversampling: ", oversample, "x", oversampleDesc$
appendInfoLine: ""

# v0.3 (item 6): the header said the region below Threshold - Knee is
# "Linear (1:1)". It is linear, but not 1:1 - the input is pre-multiplied
# by Drive and the output post-multiplied by Output_Gain, so the
# source-to-output slope there is Drive * Output_Gain.
if oversample > 1
    curveTitle$ = "Static clipping curve (waveshaper only, before anti-alias filtering)"
else
    curveTitle$ = "Static clipping curve"
endif

appendInfoLine: "Linear-zone slope (source to output): ", fixed$(drive * output_Gain, 4)
appendInfoLine: "Predicted ceiling (Threshold * |Gain|): ", fixed$(predictedCeiling, 4)
appendInfoLine: "Peak before output stage: ", fixed$(prePeak, 4)
appendInfoLine: "Output level: ", levelDesc$
appendInfoLine: "Measured output peak: ", fixed$(finalPeak, 4)
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - above 1.0 it will clip on playback or export."
endif
if output_Gain < 0
    appendInfoLine: "  NOTE: negative Output_Gain inverts the polarity of the whole output."
endif
if output_Gain = 0
    appendInfoLine: "  NOTE: Output_Gain is 0 - the result is silent."
endif
if drive = 0
    appendInfoLine: "  NOTE: Drive is 0 - the input is discarded and the output is silent."
endif
appendInfoLine: ""

# === Visualization ===
if draw_visualization
    Erase all
    
    # 1. Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 8, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 4, "centre", 0.5, "half", "Hard Clip (Knee): " + origName$
    
    # 2. Original Waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # 3. Distorted Waveform
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Clipped"
    Text bottom: "yes", "Time (s)"
    
    # 4. Transfer Function (Knee Visualizer)
    Select outer viewport: 0, 8, 2.9, 5.0
    Select inner viewport: 0.6, 7.6, 3.1, 4.8
    
    # Determine axes
    # v0.3 (item 4): v0.2 used one limit, threshold * 1.5 (floored at 1),
    # for BOTH axes. But the transition points in terms of the SOURCE
    # input are (T-K)/|Drive| and (T+K)/|Drive|, and the Y ceiling is
    # T*|Gain| - neither of which follows Threshold alone. With
    # Threshold 0.8, Knee 0.1 and Drive 0.1 the plateau starts at x = 9
    # while the panel ended near +/-1.2, so no clipping was visible at
    # all; with Threshold 0.5 and Gain 4 the ceiling is +/-2 against a
    # +/-1 Y axis, so the curve ran off the top. The two axes are now
    # derived separately.
    if abs(drive) > 0.0001
        xLimit = (threshold + knee_half_width) / abs(drive) * 1.3
    else
        xLimit = 1.2
    endif
    if xLimit < 1.0
        xLimit = 1.0
    endif
    
    yLimit = threshold * abs(output_Gain) * levelScale * 1.3
    if yLimit < 1.0
        yLimit = 1.0
    endif
    
    Axes: -xLimit, xLimit, -yLimit, yLimit
    Paint rectangle: "{0.95, 0.95, 0.95}", -xLimit, xLimit, -yLimit, yLimit
    
    # Reference Grid
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: -xLimit, 0, xLimit, 0
    Draw line: 0, -yLimit, 0, yLimit
    Draw line: -xLimit, -xLimit, xLimit, xLimit
    
    # Draw Threshold Lines
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: -xLimit, threshold * output_Gain * levelScale, xLimit, threshold * output_Gain * levelScale
    Draw line: -xLimit, -threshold * output_Gain * levelScale, xLimit, -threshold * output_Gain * levelScale
    Solid line
    
    # Calculate and Draw Curve
    Colour: "{0.2, 0.5, 0.2}"
    Line width: 2.5
    
    steps = 200
    prev_x = -xLimit
    
    # Initial point calc
    val_in = prev_x * drive
    abs_v = abs(val_in)
    
    if exactClip
        y_abs = min(abs_v, threshold)
    elsif abs_v <= (threshold - knee_half_width)
        y_abs = abs_v
    elsif abs_v >= (threshold + knee_half_width)
        y_abs = threshold
    else
        # Knee Math
        y_abs = threshold - ((threshold + knee_half_width - abs_v)^2) / (4 * knee_half_width)
    endif
    
    sign_v = -1
    if val_in > 0
        sign_v = 1
    endif
    if val_in = 0
        sign_v = 0
    endif
    
    prev_y = y_abs * sign_v * output_Gain * levelScale

    # Plot Loop
    for i from 1 to steps
        curr_x = -xLimit + (i * (2 * xLimit / steps))
        
        val_in = curr_x * drive
        abs_v = abs(val_in)
        
        if exactClip
            y_abs = min(abs_v, threshold)
        elsif abs_v <= (threshold - knee_half_width)
            y_abs = abs_v
        elsif abs_v >= (threshold + knee_half_width)
            y_abs = threshold
        else
            y_abs = threshold - ((threshold + knee_half_width - abs_v)^2) / (4 * knee_half_width)
        endif
        
        # v0.3: match the audio's sign restore exactly, including the
        # zero case. The v0.2 loop had no zero branch (the initial point
        # did), so at curr_x = 0 - which an even step count lands on
        # precisely - the curve used sign +1 where the Formula uses 0.
        sign_v = 1
        if val_in < 0
            sign_v = -1
        endif
        if val_in = 0
            sign_v = 0
        endif
        
        curr_y = y_abs * sign_v * output_Gain * levelScale
        
        Draw line: prev_x, prev_y, curr_x, curr_y
        
        prev_x = curr_x
        prev_y = curr_y
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Input Amplitude"
    Text left: "yes", "Output Amplitude"
    # v0.3 (item 5): with oversampling, the final samples also pass
    # through a band-limiting resample, whose output depends on
    # NEIGHBOURING samples - so no single static curve describes the
    # whole chain. This panel is the waveshaping stage only.
    Font size: 7
    Text top: "no", curveTitle$
    
    # 5. Spectrum (harmonic generation: original vs clipped)
    Select outer viewport: 0, 8, 5.1, 6.8
    Select inner viewport: 0.6, 7.6, 5.3, 6.6

    specMaxFreq = sampling_rate / 2
    if specMaxFreq > 12000
        specMaxFreq = 12000
    endif

    # v0.3 (item 3): v0.2 took the LTAS of the raw original and of the
    # fully processed result, so the panel labelled "harmonic generation"
    # also carried every level change in the chain. With Drive 2 and the
    # whole signal below the knee the transfer is just y = 2x, and the
    # red trace sits ~6 dB above the grey with no harmonics created at
    # all; a low Output_Gain can equally put it BELOW the grey while
    # harmonics are being generated. Both sides are now normalized to a
    # common peak for the comparison, unless absolute levels are asked
    # for.
    selectObject: original
    ltasSrcO = Copy: "HC_ltas_src_orig"
    selectObject: result
    ltasSrcR = Copy: "HC_ltas_src_res"
    
    if spectrum_reference = 1
        selectObject: ltasSrcO
        oPk = Get absolute extremum: 0, 0, "None"
        if oPk > 0
            Scale peak: 0.95
        endif
        selectObject: ltasSrcR
        rPk = Get absolute extremum: 0, 0, "None"
        if rPk > 0
            Scale peak: 0.95
        endif
        specRefLabel$ = "matched peak"
    else
        specRefLabel$ = "absolute levels"
    endif
    
    selectObject: ltasSrcO
    ltasOrig = To Ltas: 40
    selectObject: ltasSrcR
    ltasClip = To Ltas: 40
    removeObject: ltasSrcO, ltasSrcR

    selectObject: ltasClip
    topDb = Get maximum: 0, specMaxFreq, "none"
    selectObject: ltasOrig
    topDbO = Get maximum: 0, specMaxFreq, "none"
    if topDbO > topDb
        topDb = topDbO
    endif
    topDb = ceiling(topDb / 10) * 10
    botDb = topDb - 70

    selectObject: ltasOrig
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, specMaxFreq, botDb, topDb, "no"
    selectObject: ltasClip
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, specMaxFreq, botDb, topDb, "no"

    Colour: "Black"
    Draw inner box
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Frequency (Hz)  -  grey: original, red: clipped  (" + specRefLabel$ + ")"
    Text left: "yes", "dB"

    removeObject: ltasOrig, ltasClip

    # 6. Stats
    Select outer viewport: 0, 8, 6.85, 7.15
    Axes: 0, 8, 0, 1
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 4, "centre", 0.5, "half", "Preset: " + presetName$
    Select outer viewport: 0, 8, 7.15, 7.45
    Axes: 0, 8, 0, 1
    Text: 4, "centre", 0.5, "half", "Thresh: " + fixed$(threshold, 3) + " | Knee: +/-" + fixed$(knee_half_width, 3)
        ... + " | Drive: " + fixed$(drive, 2) + " | Gain: " + fixed$(output_Gain, 2)
        ... + " | " + string$(oversample) + "x OS | peak " + fixed$(finalPeak, 3)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result
if play_result
    Play
endif

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Preset: ", presetName$
