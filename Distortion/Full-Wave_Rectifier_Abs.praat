# ============================================================
# Praat AudioTools - Full-Wave_Rectifier_Abs.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026) - Interface/documentation alignment
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Full-Wave Rectifier — applies abs() to the input, flipping
#   negative samples to positive. The output is characteristically
#   buzzy and aggressive.
#
#   For a SYMMETRIC PERIODIC input, where x(t + T/2) = -x(t), the
#   rectified signal repeats at twice the rate and the spectrum
#   becomes DC plus strong even harmonics (2f, 4f, 6f...). That is
#   the textbook case and it is where "doubles the fundamental"
#   comes from. It does not generalise: a signal that never goes
#   below zero is unchanged, one with a DC offset is not
#   half-wave symmetric, complex material produces intermodulation
#   rather than a clean even series, and noise has no single
#   fundamental to double. Expect broad nonlinear enrichment on
#   real material.
#
#   NOTE on DC: abs() makes every sample non-negative, so any
#   non-silent output carries a large positive mean - for a sine at
#   peak A it is 2A/pi, i.e. 63.7% of the amplitude range at any
#   level. Dc_handling decides whether that stays.
#
#   Stereo input is processed per-channel — both channels
#   rectified independently. Output preserves the input's
#   channel count.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5.1 (2026):
#   - RENAMED preset labels to Target 0.95 / 0.80 / 1.00 so the
#     form matches the target-based preset behavior and object names.
#   - RENAMED Scale_peak -> Target_peak.
#   - RENAMED Preserve source level -> Preserve shaped level.
#   - RENAMED Conditional limiter -> Attenuate to target only if peak > target;
#     DSP is unchanged (global peak scaling only when needed).
#   - FIXED: Preserve mode no longer displays Target_peak as if active
#     in the parameter panel or final Info report.
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
#   - FIXED (ordering): Target_peak was validated BEFORE the presets
#     were applied, so a stale manual value of 1.5 aborted the
#     script even when the chosen preset was about to replace it
#     with 0.95. Validated after the presets, and only when a mode
#     actually consults it.
#   - FIXED: the transfer curve carried levelScale but NOT the
#     mean-removal shift, so under Dc_handling = "Remove final mean"
#     it drew a V rising from the origin while the audio produced
#     (|x| - meanRaw) * levelScale - a V whose vertex sits BELOW
#     zero, with roughly the quieter half of the output negative.
#     The shift is applied, the axis is computed from both ends of
#     the curve and its vertex instead of being pinned at -0.3, and
#     the title names both stages.
#   - FIXED: the parameter panel and the summary bar still asserted
#     "Doubles perceived fundamental" and "doubles fundamental +
#     even harmonics" unconditionally - contradicting the header
#     and Info text that v0.4 had just qualified. Both now name the
#     symmetric-periodic condition.
#   - RENAMED the presets again. v0.4's Standard / Reduced /
#     Full-scale LEVEL promised an output level, but Target_peak is
#     only consulted by the limiter and normalize modes: under
#     Output_level = Preserve all three produce identical audio and
#     differ only in the object name. They are now Target 0.95 /
#     0.80 / 1.00, and the script says when the target goes unused.
#     Object names change to _rectified_Target095 etc.
#
# Changelog v0.4:
#   - FIXED (the spectrum panel was not isolating rectification):
#     it compared the UNSCALED original against the NORMALIZED
#     result, so what it showed was harmonic change plus a global
#     gain change. With a source peak of 0.1 and a 0.95 target that
#     gain alone is +19.6 dB - nearly the whole visible difference,
#     presented as the harmonic effect of abs(). Both sides are now
#     built from signals at a matched peak, with the rectified side
#     taken BEFORE the output level stage; Spectrum_reference can
#     select absolute levels instead.
#   - FIXED: the transfer panel drew y = |x| while the audio went
#     on through peak scaling, so for a quiet source the real
#     mapping was (target/P)*|x| - a much steeper V than shown. The
#     curve carries the run's level scaling, the axis follows it,
#     and the title states which stage it represents.
#   - FIXED: every time panel drew from 0, assuming the Sound's
#     domain starts there. On a Sound extracted with times
#     preserved the zoom panel was querying 0..0.02 s, a window
#     holding none of its data. All axes and queries now use the
#     real domain.
#   - FIXED: the parameter panel showed Target_peak, the TARGET,
#     labelled "Peak". It now shows the measured output peak with
#     the target alongside.
#   - NEW Dc_handling. abs() makes every sample non-negative, so
#     any non-silent output carries a large positive mean - 2A/pi
#     for a sine at peak A, which is 63.7% of the amplitude range
#     at every level. That consumes headroom, dominates the low end
#     of the spectrum panel, and makes splices jump. It is a real
#     part of full-wave rectification and stays the default;
#     removing the mean leaves the even harmonics intact. The mean
#     is now measured and reported either way.
#   - Output_level replaces the unconditional Scale peak, with a
#     silent-input guard. Normalize remains the default.
#   - Target_peak is capped at 1.0; as `positive` it accepted 1.5 or
#     4.0 as normalization targets.
#   - RENAMED the presets Default / Soft / Maximum ->
#     Standard level / Reduced level / Full-scale level. They never
#     changed the rectification, which is always y = |x|; "Soft"
#     was the same waveshaping at a lower peak. Output object names
#     change accordingly (_rectified_StandardLevel etc).
#   - CORRECTED the "doubles the perceived fundamental / even
#     harmonics" claim, which holds for symmetric periodic input
#     and not in general - an already-positive signal is unchanged,
#     a DC-offset one is not half-wave symmetric, complex material
#     intermodulates, and noise has no fundamental to double.
#   - The waveform legend no longer says "blue=L orange=R" on files
#     with more than two channels.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters: Formula: ~ abs(self) +
#     Scale peak.
#   - Form syntax modernized: optionmenu uses colon.
#   - Show_spectrum is now an opt-in form toggle (default OFF).
#     v0.2 always computed `To Spectrum: yes` on both original
#     and rectified for the visualization spectrum panel — that
#     can be a couple of seconds on long files. Default OFF
#     means the script runs in milliseconds. Turn ON when you
#     want to see the harmonic enrichment (which is the whole
#     point of rectification, so worth seeing occasionally).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): abs() transfer function
#       Panel B (right, headline): spectrum comparison if
#         Show_spectrum=ON, else parameter report
#       Panel C: zoom overlay (original gray + rectified green)
#         showing the negative-half flip directly
#       Panel D: output waveform (full file, L/R distinguished)
#       Panel E: summary stats bar
# Changelog v0.2:
#   - Fixed input check
#   - Added visualization
#   - Added info output
# ============================================================

form Full-Wave Rectifier v0.5.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Target 0.95
        option Target 0.80
        option Target 1.00
        option Custom (use settings below)
    
    comment === DC handling ===
    optionmenu Dc_handling: 1
        option Raw rectification (v0.2/v0.3)
        option Remove final mean
    
    comment === Output ===
    optionmenu Output_level: 3
        option Preserve shaped level
        option Attenuate to target only if peak > target
        option Normalize to target
    positive Target_peak 0.95
    boolean Show_spectrum 0
    comment (ON shows harmonic enrichment, but adds analysis time)
    optionmenu Spectrum_reference: 1
        option Match levels (isolates harmonic change)
        option Absolute levels (as rendered)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# v0.4 (item 3): every panel drew from 0, but a Sound's start time is an
# independent property that merely defaults to 0 - a Sound extracted with
# times preserved sits at xmin..xmin+duration, and the zoom panel was
# querying 0..0.02 s, a window containing none of its data.
xminOrig = Get start time
xmaxOrig = Get end time

# === Apply Presets ===
# v0.4 (item 8): these were named Default / Soft / Maximum, which implies
# they change the rectification. They do not - the shaping is always
# y = |x|, and the only difference is the peak target, so "Soft" was not
# a gentler rectifier but the same waveshaping at a lower level.
# v0.4b: the v0.4 names (Standard / Reduced / Full-scale LEVEL) went too
# far the other way - they promise an output level, but Target_peak is
# only consulted by the limiter and normalize modes. Under
# Output_level = Preserve all three presets produce identical audio and
# differ only in the object name. They are now named for the target they
# set, and the script says when that target goes unused.
if preset = 1
    target_peak = 0.95
    presetName$ = "Target095"
elsif preset = 2
    target_peak = 0.8
    presetName$ = "Target080"
elsif preset = 3
    target_peak = 1.0
    presetName$ = "Target100"
else
    presetName$ = "Custom"
endif

# v0.4b (item 1): this ran BEFORE the presets, so a stale manual
# Target_peak of 1.5 aborted the script even when the chosen preset was
# about to replace it with 0.95. Validated after the presets, and only
# when a mode actually uses the value.
if output_level <> 1
    if target_peak > 1
        exitScript: "Target_peak must not exceed 1.0 (it is a full-scale target)."
    endif
endif

# === Info ===
writeInfoLine: "=== Full-Wave Rectifier v0.5.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch, starts at ", fixed$(xminOrig, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Effect: y = |x|  (negative -> positive)"

# v0.4 (item 8): v0.3 stated flatly that rectification "doubles the
# perceived fundamental" and gives "even harmonics (2f, 4f, 6f...)".
# That holds for a symmetric periodic signal, where x(t + T/2) = -x(t)
# so |x| repeats at twice the rate. It does NOT hold generally: a signal
# already non-negative is unchanged, one with a DC offset is not
# half-wave symmetric, complex material produces intermodulation rather
# than a clean even-harmonic series, and noise has no single fundamental
# to double.
appendInfoLine: "Result: for symmetric periodic input, the repetition rate doubles (DC + strong even harmonics)."
appendInfoLine: "        Complex or already-positive material gets broader nonlinear enrichment instead."
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Applying rectification..."

selectObject: original
Copy: originalName$ + "_rectified_" + presetName$
result = selected("Sound")

selectObject: result
Formula: ~ abs(self)

meanRaw = Get mean: 0, 0, 0
appendInfoLine: "  Mean after abs(): ", fixed$(meanRaw, 4), " (DC component)"

# v0.4 (item 6): abs() makes every sample non-negative, so any non-silent
# result carries a large positive mean. For a sine at peak A the mean is
# 2A/pi - 63.7% of the amplitude range, whatever the level. That DC eats
# headroom, dominates the 0 Hz end of the spectrum panel, and makes
# splices jump. It is a genuine part of full-wave rectification and so
# stays the default, but removing it leaves the even harmonics intact.
if dc_handling = 2
    selectObject: result
    Subtract mean
    meanAfter = Get mean: 0, 0, 0
    dcDesc$ = "mean removed"
    appendInfoLine: "  Mean after removal: ", fixed$(meanAfter, 6)
else
    dcDesc$ = "raw (DC retained)"
endif

# v0.4 (item 1): the spectrum panel compared the UNSCALED original with
# the NORMALIZED result, so the difference it showed was harmonic change
# plus a global gain change. With a source peak of 0.1 and a 0.95 target
# that gain alone is +19.6 dB - nearly the whole visible difference,
# attributed to rectification. A copy is taken here, before the output
# level stage, so the comparison can be made at matched levels.
selectObject: result
specSource = Copy: "FWR_spec_source"

# === Output level ===
# v0.4 (item 7): v0.3 always ran Scale peak, which made all three presets
# level controls over an unchanging waveshaper and lifted any quiet
# source to the target. Normalize stays the default so v0.3 renders are
# reproducible.
# (item 5): a silent input gives a peak of 0, which v0.3 handed to
# Scale peak regardless.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "  Peak before output stage: ", fixed$(prePeak, 4)

levelScale = 1
if output_level = 1
    levelDesc$ = "preserved"
    if preset < 4
        appendInfoLine: "  NOTE: Output_level is Preserve, so the preset's target of ", fixed$(target_peak, 2), " is not used - all three presets give identical audio in this mode."
    endif
elsif output_level = 2
    if prePeak > target_peak
        selectObject: result
        Scale peak: target_peak
        levelScale = target_peak / prePeak
        levelDesc$ = "attenuated to " + fixed$(target_peak, 2)
    else
        levelDesc$ = "unchanged"
    endif
else
    if prePeak > 0
        selectObject: result
        Scale peak: target_peak
        levelScale = target_peak / prePeak
        levelDesc$ = "normalized to " + fixed$(target_peak, 2)
    else
        levelDesc$ = "silent input - peak scaling skipped"
    endif
endif
appendInfoLine: "  Output level: ", levelDesc$

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
finalMean = Get mean: 0, 0, 0
nResultCh = Get number of channels
appendInfoLine: "  Measured output peak: ", fixed$(finalPeak, 4), " | mean: ", fixed$(finalMean, 4)

# Vertical extent and title for the transfer panel.
# v0.4b (item 2): the curve carried levelScale but NOT the mean-removal
# shift, so under Dc_handling = "Remove final mean" it drew a V rising
# from the origin while the audio actually produced
# (|x| - meanRaw) * levelScale - a V whose vertex sits BELOW zero, with
# roughly the quieter half of the output negative. The shift is applied
# here, and the axis is computed from both ends of the curve and its
# vertex rather than being pinned at -0.3.
if dc_handling = 2
    curveShift = meanRaw
else
    curveShift = 0
endif
curveVertex = (0 - curveShift) * levelScale
curveEnd = (1 - curveShift) * levelScale

yHiV = curveEnd * 1.2
if yHiV < 1.2
    yHiV = 1.2
endif
yLoV = curveVertex * 1.2
if yLoV > -0.3
    yLoV = -0.3
endif
# kept for any code still reading the old single-bound name
yLimV = yHiV

if dc_handling = 2 and levelScale <> 1
    curveTitle$ = "Rectification incl. mean removal + level scaling"
elsif dc_handling = 2
    curveTitle$ = "Rectification incl. mean removal"
elsif levelScale <> 1
    curveTitle$ = "Rectification incl. this render's level scaling"
else
    curveTitle$ = "Static rectification function (V-shape)"
endif

# v0.4 (item 9): processing covers every channel, but the waveform panel
# draws only the first two.
if input_n_channels = 1
    chanLegend$ = "(mono)"
elsif input_n_channels = 2
    chanLegend$ = "(blue=ch1  orange=ch2)"
else
    chanLegend$ = "(first 2 of " + string$(input_n_channels) + " channels shown)"
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    pageHeight = 8.0
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(originalName$, "_", "\_ ", 0)
    Erase all
    
    # ----------------------------------------------------------
    # Compute spectra ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrum
        appendInfoLine: "Computing spectra for visualization..."
        
        # v0.4 (item 1): both sides are now built from signals at a
        # matched peak, so the panel shows the harmonic change rather
        # than the harmonic change plus the normalization gain. The
        # rectified side comes from specSource, the copy taken BEFORE
        # the output level stage. Choose "Absolute levels" to see the
        # rendered levels instead.
        selectObject: original
        if input_n_channels > 1
            specSrcOrig = Convert to mono
        else
            selectObject: original
            specSrcOrig = Copy: "specSrcOrig"
        endif
        
        selectObject: specSource
        if nResultCh > 1
            specSrcRes = Convert to mono
        else
            selectObject: specSource
            specSrcRes = Copy: "specSrcRes"
        endif
        
        if spectrum_reference = 1
            selectObject: specSrcOrig
            oPk = Get absolute extremum: 0, 0, "None"
            if oPk > 0
                Scale peak: 0.95
            endif
            selectObject: specSrcRes
            rPk = Get absolute extremum: 0, 0, "None"
            if rPk > 0
                Scale peak: 0.95
            endif
            specRefDesc$ = "matched levels"
        else
            # As rendered: the original stays as it is, the rectified
            # side carries the run's actual level scaling.
            if levelScale <> 1
                selectObject: specSrcRes
                Formula: ~ self * levelScale
            endif
            specRefDesc$ = "absolute levels"
        endif
        
        selectObject: specSrcOrig
        specOrig = To Spectrum: "yes"
        Rename: "specOrig"
        specOrigID = selected("Spectrum")
        removeObject: specSrcOrig
        
        selectObject: specSrcRes
        specRect = To Spectrum: "yes"
        Rename: "specRect"
        specRectID = selected("Spectrum")
        removeObject: specSrcRes
    else
        specRefDesc$ = ""
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Full-Wave Rectifier v0.5.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  Level: " + levelDesc$
        ... + "  |  DC: " + dcDesc$
        ... + "  |  Effect: y = |x|"
        ... + "  |  " + string$(input_n_channels) + " ch input -> " + string$(nResultCh) + " ch output"
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # The defining diagnostic. y = |x| is a V-shape.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    Axes: -1.2, 1.2, yLoV, yHiV
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, yLoV, yHiV
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, yLoV, 0, yHiV
    
    # Linear y=x reference (positive side) — what NO rectification would look like
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: 0, 0, 1, 1
    Draw line: -1, -1, 0, 0
    Solid line
    
    # The abs() transfer function — V shape
    # v0.4 (item 2): the V was drawn as y = |x| while the audio went on
    # through the output level stage, so with a quiet source normalized
    # to 0.95 the real mapping was (0.95/P)*|x| - a far steeper V than
    # the one shown. The curve now carries the run's actual level
    # scaling, and the panel title says which stage it represents.
    Colour: "{0.40, 0.65, 0.45}"
    Line width: 2.5
    # Negative half: flipped to positive
    Draw line: -1, curveEnd, 0, curveVertex
    # Positive half: unchanged
    Draw line: 0, curveVertex, 1, curveEnd
    Line width: 1
    
    # Annotations
    Font size: 6
    Colour: "{0.30, 0.55, 0.30}"
    Text: -0.5, "centre", (0.5 - curveShift) * levelScale, "half", " |x| "
    Text: 0.5, "centre", (0.5 - curveShift) * levelScale, "half", " x "
    
    # Identity reference label
    Font size: 6
    Colour: "{0.55, 0.55, 0.55}"
    Text: -0.95, "left", -0.20, "half", "(dotted = identity)"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: SPECTRUM COMPARISON or PARAMETER REPORT  (right)
    # Conditional on Show_spectrum form toggle.
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    if show_spectrum
        # ==== SPECTRUM COMPARISON ====
        maxFreqDisplay = sr / 2
        if maxFreqDisplay > 5000
            maxFreqDisplay = 5000
        endif
        
        Axes: 0, maxFreqDisplay, 0, 80
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxFreqDisplay, 0, 80
        
        # Light frequency gridlines (every 1 kHz)
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        gridF = 1000
        while gridF < maxFreqDisplay
            Draw line: gridF, 0, gridF, 80
            Font size: 6
            Colour: "{0.55, 0.55, 0.55}"
            if gridF < 1000
                Text: gridF, "centre", 3, "half", string$(gridF)
            else
                Text: gridF, "centre", 3, "half", fixed$(gridF / 1000, 0) + "k"
            endif
            Colour: "{0.88, 0.88, 0.92}"
            gridF = gridF + 1000
        endwhile
        
        # Original spectrum (gray, behind)
        selectObject: specOrigID
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1.2
        Draw: 0, maxFreqDisplay, 0, 80, "no"
        
        # Rectified spectrum (green, on top)
        selectObject: specRectID
        Colour: "{0.40, 0.65, 0.45}"
        Line width: 1.5
        Draw: 0, maxFreqDisplay, 0, 80, "no"
        Line width: 1
        
        # Legend
        Font size: 6
        Colour: "{0.55, 0.55, 0.55}"
        Text: maxFreqDisplay * 0.99, "right", 73, "half", "gray = original "
        Colour: "{0.40, 0.65, 0.45}"
        Text: maxFreqDisplay * 0.99, "right", 65, "half", "green = rectified "
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Power (dB)"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # ==== PARAMETER REPORT ====
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.92, "half", "Operation:"
        
        Font size: 7
        Colour: "{0.40, 0.65, 0.45}"
        Text: 0.10, "left", 0.82, "half", "y = |x|"
        
        Font size: 7
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.74, "half", "(absolute value, sample-by-sample)"
        
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.62, "half", "Output:"
        
        Font size: 7
        Colour: "{0.30, 0.45, 0.78}"
        if output_level = 1
            Text: 0.10, "left", 0.54, "half", "Peak:    " + fixed$(finalPeak, 3)
        else
            Text: 0.10, "left", 0.54, "half", "Peak:    " + fixed$(finalPeak, 3) + " (target " + fixed$(target_peak, 2) + ")"
        endif
        Text: 0.10, "left", 0.46, "half", "Channels: " + string$(nResultCh)
        Text: 0.10, "left", 0.38, "half", "Duration: " + fixed$(finalDur, 2) + " s"
        
        Font size: 7
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.27, "half", "Spectral effect:"
        
        Font size: 7
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.19, "half", "Symmetric periodic in: 2x rate,"
        Text: 0.10, "left", 0.12, "half", "DC + even harmonics"
        Text: 0.10, "left", 0.05, "half", "Complex in: broad enrichment"
        
        Font size: 6
        Colour: "{0.78, 0.50, 0.30}"
        Text: 0.05, "left", 0.03, "half", "(Show_spectrum = ON to see this)"
        
        Colour: "Black"
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", curveTitle$
    if show_spectrum
        Text: 6.10, "centre", 7.30, "half", "Spectrum: original vs rectified"
    else
        Text: 6.10, "centre", 7.30, "half", "Operation summary"
    endif
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (full width, first 20 ms)
    # Original (gray) + rectified (green) overlaid.
    # The visual signature of full-wave rectification: the
    # below-zero portion of the original is reflected upward.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    # v0.4 (item 3): this queried and drew 0..zoomDur, i.e. it assumed
    # the time domain starts at 0. On a Sound extracted with times
    # preserved that window holds no data at all.
    zoomDur = 0.02
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: original
    zoomStart = xminOrig
    zoomEnd = xminOrig + zoomDur
    origPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    selectObject: result
    resPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: zoomStart, zoomEnd, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", zoomStart, zoomEnd, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: zoomStart, 0, zoomEnd, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Rectified (green, on top)
    selectObject: result
    if nResultCh > 1
        Extract one channel: 1
        zRes = selected("Sound")
        Colour: "{0.40, 0.65, 0.45}"
        Line width: 1.3
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zRes
    else
        Colour: "{0.40, 0.65, 0.45}"
        Line width: 1.3
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, green = rectified)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: xminOrig, xmaxOrig, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", xminOrig, xmaxOrig, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: xminOrig, 0, xmaxOrig, 0
    
    selectObject: result
    if nResultCh = 1
        Colour: "{0.40, 0.65, 0.45}"
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
        Text top: "no", "Output (full file)  " + chanLegend$
    else
        Text top: "no", "Output (full file, mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.60, 7.70, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if show_spectrum
        spectrumStr$ = "shown"
    else
        spectrumStr$ = "off (Show_spectrum = ON to see)"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + vizName$
        ... + "  |  Operation: y = |x|"
        ... + "  |  Level: " + levelDesc$
        ... + "  |  DC: " + dcDesc$
        ... + "  |  Channels: " + string$(input_n_channels) + " -> " + string$(nResultCh)
    
    Text: 0.02, "left", 0.28, "half",
        ... "Spectrum panel: " + spectrumStr$
        ... + "  |  Effect: 2x rate + even harmonics (symmetric periodic input only)"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectrum objects if computed
    if show_spectrum
        removeObject: specOrigID, specRectID
    endif

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# v0.4: the pre-level-stage copy used for the spectrum comparison is
# removed here, so it is cleaned up whether or not the visualization ran.
removeObject: specSource

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
if output_level = 1
    appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
else
    appendInfoLine: "Peak: ", fixed$(finalPeak, 4), " (target ", fixed$(target_peak, 3), ")"
endif
appendInfoLine: "Mean (DC): ", fixed$(finalMean, 4), "  [", dcDesc$, "]"

if play_result
    selectObject: result
    Play
endif

selectObject: result
