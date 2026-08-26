# ============================================================
# Praat AudioTools - Wave_Shaper_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - DC-safe Chebyshev, oversampled wet path, validation/reporting fixes
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave Shaper Distortion - comprehensive waveshaping toolkit
#   with 12 different transfer function algorithms and 5
#   processing modes. From subtle saturation to extreme folding.
#   Includes frequency-split, asymmetric, multi-stage, and
#   stereo M/S processing options.
#
# Algorithms:
#   1. Hyperbolic Tangent (soft clip)
#   2. Sine Fold (warm harmonics)
#   3. Arc Tangent (smooth saturation)
#   4. Polynomial (gentle curve)
#   5. Absolute Value (rectifier)
#   6. Square Law (fuzzy)
#   7. Chebyshev (harmonic control)
#   8. Sigmoid (tube-like)
#   9. Exponential Saturator
#   10. Bitcrush (lo-fi)
#   11. Single Wave Wrap
#   12. Diode Ladder (analog asymmetric)
#
# Changelog v0.5 (2026):
#   - Chebyshev shape is DC-safe: the weighted polynomial is shifted so
#     f(0)=0 instead of turning silence into a -0.2 DC signal.
#   - Added wet-path oversampling (4x default; 1=off; 2x refused; 3-8x
#     supported) with band-limited downsampling before dry/wet mixing.
#   - Mix_percent now accepts the full 0-100 range and rejects extrapolation.
#   - Renamed Exponential Fold to Exponential Saturator and implemented the
#     same transfer function in an overflow-resistant algebraic form.
#   - Renamed Wave Wrap (circular) to Single Wave Wrap; the algorithm itself
#     remains the original one-fold mapping.
#   - Stereo Wide now refuses >2-channel input explicitly; mono still falls
#     back to Standard, while the other modes preserve arbitrary channels.
#   - Added silent-output normalization guard, final peak reporting/warning,
#     shared waveform scales, and oversampling/final-peak visualization data.
#
# Changelog v0.4 (2026):
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
# Changelog v0.3:
#   - Removed a duplicated input-check block and a duplicated
#     section comment (copy-paste artifacts).
#   - Stereo Wide (M/S): free the extracted left/right channels
#     after Combine to stereo (they were leaking into the object list).
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed selection syntax (use object IDs)
#   - Fixed formula syntax (string building)
#   - Fixed procedure call syntax (@)
#   - Fixed frequency split high band filter
#   - Fixed M/S stereo mode
#   - Added visualization
#   - Added info output
# ============================================================

form Wave Shaper Distortion v0.5
    comment Select a Sound object first
    
    comment === Waveshaping Algorithm ===
    choice Shape 1
        option 1. Hyperbolic Tangent (soft)
        option 2. Sine Fold (warm)
        option 3. Arc Tangent (smooth)
        option 4. Polynomial (aggressive)
        option 5. Absolute Value (digital)
        option 6. Square Law (fuzzy)
        option 7. Chebyshev (harmonic)
        option 8. Sigmoid (tube-like)
        option 9. Exponential Saturator
        option 10. Bitcrush (lo-fi)
        option 11. Single Wave Wrap
        option 12. Diode Ladder (analog)
    
    comment === Parameters ===
    positive Drive 2.0
    real Mix_percent 80
    
    integer Oversample 4
    comment (1 = off; 2 is disabled; 3-8 supported)
    
    comment === Processing Mode ===
    optionmenu Mode 1
        option Standard
        option Frequency Split (800 Hz)
        option Asymmetric (+/- different)
        option Multi-Stage (3x cascade)
        option Stereo Wide (M/S)
    
    comment === Output ===
    boolean Normalize 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
xminOrig = Get start time
xmaxOrig = Get end time
srcPeak = Get absolute extremum: 0, 0, "None"
numChannels = Get number of channels
if mix_percent < 0 or mix_percent > 100
    exitScript: "Mix_percent must be between 0 and 100 (got " + fixed$(mix_percent, 2) + ")."
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
    osNote$ = "Oversample " + string$(oversampleReq) + " is outside 1-8; running at " + string$(oversample) + "."
endif
if oversample = 2
    exitScript: "Oversample = 2 is disabled - the 2x round trip shifts phase with frequency on Praat 6.1.38. Use 1 (off), or 3 and above; 4 is the default."
endif

if mode = 5 and numChannels > 2
    exitScript: "Stereo Wide (M/S) requires mono or stereo input. This Sound has " + string$(numChannels) + " channels. Use another mode to preserve all channels."
endif

if numChannels = 2
    is_stereo = 1
else
    is_stereo = 0
endif

# === Get Shape and Mode Names ===
@getShapeName: shape
@getModeName: mode

# === Info ===
writeInfoLine: "=== Wave Shaper Distortion v0.5 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Shape: ", shape_name$
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Drive: ", drive
appendInfoLine: "Mix: ", mix_percent, "%"
appendInfoLine: "Oversampling: ", oversample, "x"
if osNote$ <> ""
    appendInfoLine: "  NOTE: ", osNote$
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: "processing_temp"
proc_sound = selected("Sound")

# Oversample the wet path before nonlinear processing. The dry source remains
# at the original rate and is mixed only after the processed path returns.
if oversample > 1
    selectObject: proc_sound
    Resample: sr * oversample, 50
    upsampled = selected("Sound")
    removeObject: proc_sound
    proc_sound = upsampled
endif

# Convert drive to string for formulas
drive_str$ = string$(drive)

# ====== MODE-SPECIFIC PROCESSING ======

if mode = 1
    # === STANDARD MODE ===
    appendInfoLine: "  Mode: Standard"
    selectObject: proc_sound
    Formula: "self * " + drive_str$
    @applyWaveShaping: proc_sound, shape

elsif mode = 2
    # === FREQUENCY SPLIT MODE ===
    appendInfoLine: "  Mode: Frequency Split (800 Hz)"
    freq_split = 800
    selectObject: proc_sound
    Filter (pass Hann band): 20, freq_split, 100
    low_band = selected("Sound")
    selectObject: proc_sound
    Filter (pass Hann band): freq_split, sr/2, 100
    high_band = selected("Sound")
    selectObject: low_band
    Formula: "self * " + drive_str$
    @applyWaveShaping: low_band, shape
    drive_high_str$ = string$(drive * 1.5)
    selectObject: high_band
    Formula: "self * " + drive_high_str$
    @applyWaveShaping: high_band, shape
    low_str$ = string$(low_band)
    high_str$ = string$(high_band)
    selectObject: proc_sound
    Formula: "object[" + low_str$ + "] + object[" + high_str$ + "]"
    removeObject: low_band, high_band

elsif mode = 3
    appendInfoLine: "  Mode: Asymmetric"
    selectObject: proc_sound
    Formula: "self * " + drive_str$
    @applyWaveShaping: proc_sound, shape
    Formula: ~ if self > 0 then self * 1.3 else self * 0.8 fi

elsif mode = 4
    appendInfoLine: "  Mode: Multi-Stage (3 cascaded)"
    stage_drive = drive ^ (1/3)
    stage_drive_str$ = string$(stage_drive)
    selectObject: proc_sound
    for stage from 1 to 3
        appendInfoLine: "    Stage ", stage, "/3..."
        Formula: "self * " + stage_drive_str$
        @applyWaveShaping: proc_sound, shape
    endfor

elsif mode = 5
    appendInfoLine: "  Mode: Stereo Wide (M/S)"
    if is_stereo
        selectObject: proc_sound
        Extract one channel: 1
        left_ch = selected("Sound")
        selectObject: proc_sound
        Extract one channel: 2
        right_ch = selected("Sound")
        left_str$ = string$(left_ch)
        right_str$ = string$(right_ch)
        selectObject: left_ch
        Copy: "mid_temp"
        mid_signal = selected("Sound")
        Formula: "(object[" + left_str$ + "] + object[" + right_str$ + "]) / 2"
        Formula: "self * " + drive_str$
        @applyWaveShaping: mid_signal, shape
        selectObject: left_ch
        Copy: "side_temp"
        side_signal = selected("Sound")
        Formula: "(object[" + left_str$ + "] - object[" + right_str$ + "]) / 2"
        drive_side_str$ = string$(drive * 1.5)
        Formula: "self * " + drive_side_str$
        @applyWaveShaping: side_signal, shape
        mid_str$ = string$(mid_signal)
        side_str$ = string$(side_signal)
        selectObject: left_ch
        Formula: "object[" + mid_str$ + "] + object[" + side_str$ + "]"
        selectObject: right_ch
        Formula: "object[" + mid_str$ + "] - object[" + side_str$ + "]"
        selectObject: left_ch, right_ch
        Combine to stereo
        new_stereo = selected("Sound")
        removeObject: proc_sound, mid_signal, side_signal, left_ch, right_ch
        proc_sound = new_stereo
    else
        appendInfoLine: "    (Mono input - Stereo Wide falls back to Standard)"
        selectObject: proc_sound
        Formula: "self * " + drive_str$
        @applyWaveShaping: proc_sound, shape
    endif
endif

# Return the wet path to the source sample rate before dry/wet mixing.
if oversample > 1
    selectObject: proc_sound
    Resample: sr, 50
    downsampled = selected("Sound")
    removeObject: proc_sound
    proc_sound = downsampled
    # Restore the exact source time domain/length after the two rate conversions.
    selectObject: proc_sound
    Extract part: xminOrig, xmaxOrig, "rectangular", 1, "yes"
    trimmed = selected("Sound")
    removeObject: proc_sound
    proc_sound = trimmed
endif

if mix_percent < 100
    appendInfoLine: "Mixing dry/wet (", mix_percent, "% wet)..."
    wet_level = mix_percent / 100
    dry_level = 1 - wet_level
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    orig_str$ = string$(original)
    selectObject: proc_sound
    Formula: "(self * " + wet_str$ + ") + (object[" + orig_str$ + "] * " + dry_str$ + ")"
endif

if normalize
    selectObject: proc_sound
    preNormPeak = Get absolute extremum: 0, 0, "None"
    if preNormPeak > 1e-9
        Scale peak: 0.95
        normDesc$ = "normalized to 0.95"
    else
        normDesc$ = "near-silent; normalization skipped"
    endif
else
    normDesc$ = "off"
endif

selectObject: proc_sound
Rename: original_name$ + "_" + shape_name$ + "_" + mode_name$
result = selected("Sound")
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    if normalize
        normalizeDesc$ = "on"
    else
        normalizeDesc$ = "off"
    endif
    pageHeight = 7.25
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(original_name$, "_", "\_ ", 0)
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Wave Shaper Distortion v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + shape_name$ + " | " + mode_name$ + " | drive " + fixed$(drive, 2) + " | mix " + fixed$(mix_percent, 0) + "\% | OS " + string$(oversample) + "x"
    
    # Original and result waveforms use one shared amplitude scale.
    sharedAmp = max(srcPeak, finalPeak) * 1.10
    if sharedAmp < 0.001
        sharedAmp = 0.001
    endif

    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.60, 7.70, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.60, 7.70, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Shaped"
    Text bottom: "yes", "Time (s)"
    
    zoomDur = min(0.02, duration)
    zoomStart = xminOrig
    zoomEnd = xminOrig + zoomDur
    selectObject: original
    srcZoomPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    selectObject: result
    outZoomPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    zoomAmp = max(srcZoomPeak, outZoomPeak) * 1.10
    if zoomAmp < 0.001
        zoomAmp = 0.001
    endif
    Select outer viewport: 0, 4, 2.7, 3.8
    Select inner viewport: 0.60, 3.85, 2.8, 3.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: zoomStart, zoomEnd, -zoomAmp, zoomAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Orig (zoom)"
    Select outer viewport: 4, 8, 2.7, 3.8
    Select inner viewport: 4.45, 7.70, 2.8, 3.7
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: zoomStart, zoomEnd, -zoomAmp, zoomAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Shaped (zoom)"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 0, 4, 4.0, 5.5
    Select inner viewport: 0.60, 3.85, 4.1, 5.4

    # This is the nominal memoryless waveshaper y=f(drive*x). Frequency
    # splitting, M/S routing, asymmetric post-gain, multi-stage routing,
    # dry/wet mixing, oversampling/downsampling and normalization are mode/file
    # dependent and are therefore stated explicitly rather than folded into a
    # misleading curve.
    nPoints = 300
    transferYLim = 1.5
    for p from 1 to nPoints
        tx = -1.2 + (p - 1) / (nPoints - 1) * 2.4
        tin = tx * drive
        @computeShape: tin, shape
        ty = result_value
        if abs(ty) * 1.10 > transferYLim
            transferYLim = abs(ty) * 1.10
        endif
    endfor

    Axes: -1.5, 1.5, -transferYLim, transferYLim
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.5, 1.5, -transferYLim, transferYLim
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -transferYLim, 0, transferYLim
    Dotted line
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    Colour: "{0.55, 0.35, 0.70}"
    Line width: 2
    for p from 2 to nPoints
        x1 = -1.2 + (p - 2) / nPoints * 2.4
        x2 = -1.2 + (p - 1) / nPoints * 2.4
        in1 = x1 * drive
        in2 = x2 * drive
        @computeShape: in1, shape
        y1 = result_value
        @computeShape: in2, shape
        y2 = result_value
        Draw line: x1, y1, x2, y2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output (+/-" + fixed$(transferYLim, 2) + ")"
    Text bottom: "yes", "Input"
    Text top: "no", "Nominal waveshaper y=f(drive*x) | routing / OS / mix / normalize excluded"
    
    Select outer viewport: 4, 8, 4.0, 5.5
    Select inner viewport: 4.45, 7.70, 4.1, 5.4
    Axes: 0, 4, 0, 12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 4, 0, 12
    Font size: 6
    algorithms$[1] = "1. Tanh (soft)"
    algorithms$[2] = "2. Sine Fold"
    algorithms$[3] = "3. Arctan"
    algorithms$[4] = "4. Polynomial"
    algorithms$[5] = "5. Abs (rectify)"
    algorithms$[6] = "6. Square Law"
    algorithms$[7] = "7. Chebyshev"
    algorithms$[8] = "8. Sigmoid"
    algorithms$[9] = "9. Exp Saturator"
    algorithms$[10] = "10. Bitcrush"
    algorithms$[11] = "11. Single Wrap"
    algorithms$[12] = "12. Diode"
    for i from 1 to 12
        yPos = 12 - i + 0.5
        if i = shape
            Colour: "{0.6, 0.5, 0.7}"
            Paint rectangle: "{0.85, 0.8, 0.9}", 0.1, 3.9, yPos - 0.4, yPos + 0.4
            Colour: "Black"
            Text: 0.2, "left", yPos, "half", "► " + algorithms$[i]
        else
            Colour: "{0.5, 0.5, 0.5}"
            Text: 0.2, "left", yPos, "half", algorithms$[i]
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0, 8, 5.6, 6.0
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Drive: " + fixed$(drive, 1) + " | Mix: " + fixed$(mix_percent, 0) + "% | Mode: " + mode_name$ + " | OS: " + string$(oversample) + "x | Normalize: " + if normalize then "ON" else "OFF" fi
    Font size: 7
    Colour: "Black"

    # === Summary strip ===
    Select outer viewport: 0, 8, 6.15, 7.20
    Select inner viewport: 0.60, 7.70, 6.23, 7.12
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizName$ + " | " + fixed$(duration, 2) + " s | " + string$(numChannels) + " ch | shape " + shape_name$
    summary2$ = "##Shaping##  drive " + fixed$(drive, 2) + " | mode " + mode_name$ + " | wet mix " + fixed$(mix_percent, 0) + "\% | oversample " + string$(oversample) + "x"
    summary3$ = "##Output##  " + normDesc$ + " | final peak " + fixed$(finalPeak, 3) + " | waveform and nominal transfer shown"
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
appendInfoLine: "Output: ", fixed$(duration, 3), " s, ", numChannels, " ch, peak ", fixed$(finalPeak, 4)
appendInfoLine: "Output action: ", normDesc$
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - above 1.0 it may clip on playback or export."
endif
if play_result
    selectObject: result
    Play
endif
selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

procedure applyWaveShaping: .sound, .shape
    selectObject: .sound
    if .shape = 1
        Formula: ~ tanh(self * 1.5) / 1.5
    elsif .shape = 2
        Formula: ~ sin(self * 2.5) * 0.85
    elsif .shape = 3
        Formula: ~ 2 * arctan(self * 1.8) / pi
    elsif .shape = 4
        Formula: ~ self - (self * self * self) * 0.33
    elsif .shape = 5
        Formula: ~ abs(self)
    elsif .shape = 6
        Formula: ~ self * abs(self) * 0.8
    elsif .shape = 7
        Formula: ~ self * 0.7 + (2 * self * self - 1) * 0.2 + (4 * self^3 - 3 * self) * 0.1 + 0.2
    elsif .shape = 8
        Formula: ~ (2 / (1 + exp(-self * 2))) - 1
    elsif .shape = 9
        Formula: ~ if self >= 0 then (1 - exp(-2*self)) / (1 + exp(-2*self) + 0.1*exp(-self)) else -(1 - exp(2*self)) / (1 + exp(2*self) + 0.1*exp(self)) fi
    elsif .shape = 10
        Formula: ~ floor(self * 16 + 0.5) / 16
    elsif .shape = 11
        Formula: ~ if abs(self) > 1 then -self / abs(self) * (2 - abs(self)) else self fi
    elsif .shape = 12
        Formula: ~ if self > 0 then (1 - exp(-self * 2)) * 0.5 else (exp(self * 2) - 1) * 0.3 fi
    endif
endproc

procedure computeShape: .input, .shape
    if .shape = 1
        result_value = tanh(.input * 1.5) / 1.5
    elsif .shape = 2
        result_value = sin(.input * 2.5) * 0.85
    elsif .shape = 3
        result_value = 2 * arctan(.input * 1.8) / pi
    elsif .shape = 4
        result_value = .input - (.input * .input * .input) * 0.33
    elsif .shape = 5
        result_value = abs(.input)
    elsif .shape = 6
        result_value = .input * abs(.input) * 0.8
    elsif .shape = 7
        result_value = .input * 0.7 + (2 * .input * .input - 1) * 0.2 + (4 * .input^3 - 3 * .input) * 0.1 + 0.2
    elsif .shape = 8
        result_value = (2 / (1 + exp(-.input * 2))) - 1
    elsif .shape = 9
        if .input >= 0
            result_value = (1 - exp(-2*.input)) / (1 + exp(-2*.input) + 0.1*exp(-.input))
        else
            result_value = -(1 - exp(2*.input)) / (1 + exp(2*.input) + 0.1*exp(.input))
        endif
    elsif .shape = 10
        result_value = floor(.input * 16 + 0.5) / 16
    elsif .shape = 11
        if abs(.input) > 1
            result_value = -.input / abs(.input) * (2 - abs(.input))
        else
            result_value = .input
        endif
    elsif .shape = 12
        if .input > 0
            result_value = (1 - exp(-.input * 2)) * 0.5
        else
            result_value = (exp(.input * 2) - 1) * 0.3
        endif
    endif
endproc

procedure getShapeName: .shape
    if .shape = 1
        shape_name$ = "Tanh"
    elsif .shape = 2
        shape_name$ = "SineFold"
    elsif .shape = 3
        shape_name$ = "Arctan"
    elsif .shape = 4
        shape_name$ = "Polynomial"
    elsif .shape = 5
        shape_name$ = "Abs"
    elsif .shape = 6
        shape_name$ = "SquareLaw"
    elsif .shape = 7
        shape_name$ = "Chebyshev"
    elsif .shape = 8
        shape_name$ = "Sigmoid"
    elsif .shape = 9
        shape_name$ = "ExpSaturator"
    elsif .shape = 10
        shape_name$ = "Bitcrush"
    elsif .shape = 11
        shape_name$ = "SingleWaveWrap"
    elsif .shape = 12
        shape_name$ = "DiodeLadder"
    endif
endproc

procedure getModeName: .mode
    if .mode = 1
        mode_name$ = "Standard"
    elsif .mode = 2
        mode_name$ = "FreqSplit"
    elsif .mode = 3
        mode_name$ = "Asymmetric"
    elsif .mode = 4
        mode_name$ = "MultiStage"
    elsif .mode = 5
        mode_name$ = "StereoWide"
    endif
endproc
