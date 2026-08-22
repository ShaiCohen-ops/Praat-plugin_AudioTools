# ============================================================
# Praat AudioTools - Convolve_Stereo_Fibonacci.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026) - Multichannel/domain hardening
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Fibonacci Convolution - creates impulse response
#   with tap times based on Fibonacci sequence. The sequence's
#   natural growth pattern creates dense early reflections
#   that become sparser over time (like real room acoustics).
#   L and R channels use different Fibonacci seeds and jitter
#   for natural stereo decorrelation.
#
# Changelog v0.4:
#   - Public form/defaults and output naming are unchanged.
#   - Added a private zero-based work copy so non-zero source xmin
#     does not shift convolution/trim timing.
#   - Fixed 3+ channel input: build an N-channel Fibonacci IR by
#     alternating the existing L/R IRs across channels. Mono and stereo
#     retain the original v0.3 stereo behavior.
#   - Dry extension now matches the actual output channel count.
#   - Pulse_period is sanitized internally as integer interpolation depth
#     for PointProcess: To Sound (pulse train); public field names stay
#     unchanged for caller compatibility.
#   - Added a practical 256-impulse ceiling for pathological Custom input.
#   - Safe IR normalization skips silent pulse trains.
#   - Convolution trim uses the actual N+M-1 result duration.
#   - Final peak handling is a safety ceiling only; Wet=0% preserves the
#     dry signal level instead of forcibly boosting it to 0.95.
#   - Explicit row/column dry reads preserve multichannel routing.
#
# Changelog v0.3:
#   - Visualization: title and bottom parameter line now set their own Axes
#     so they center correctly (the parameter line no longer clips off the
#     left edge, which happened because it inherited the tap panel's axes).
#
# Changelog v0.2:
#   - Fixed selection syntax (object IDs)
#   - Fixed cleanup (proper object tracking)
#   - Added wet/dry mix control
#   - Added visualization showing Fibonacci pattern
#   - Removed unnecessary resample step
# ============================================================

form Stereo Fibonacci Convolution
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Fibonacci
        option Medium Fibonacci
        option Heavy Fibonacci
        option Extreme Fibonacci
    
    comment === Duration ===
    positive IR_duration_s 1.5
    natural Number_of_impulses 12
    
    comment === Left Channel ===
    positive Left_fib_start_1 1
    positive Left_fib_start_2 1
    positive Left_scale_divisor 100.0
    positive Left_jitter_s 0.010
    
    comment === Right Channel ===
    positive Right_fib_start_1 2
    positive Right_fib_start_2 3
    positive Right_scale_divisor 120.0
    positive Right_jitter_s 0.020
    
    comment === Pulse Parameters ===
    positive Pulse_amplitude 1.0
    positive Pulse_width 0.05
    positive Pulse_period 2000
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Keep_IR 0
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
originalDur = Get total duration
sr = Get sampling frequency
numChans = Get number of channels

# Private zero-based processing copy; the caller's original Sound is untouched.
selectObject: original
workSource = Copy: "fibonacci_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 2
    # Subtle Fibonacci
    iR_duration_s = 1.2
    number_of_impulses = 8
    left_fib_start_1 = 1
    left_fib_start_2 = 1
    left_scale_divisor = 120.0
    left_jitter_s = 0.005
    right_fib_start_1 = 1
    right_fib_start_2 = 2
    right_scale_divisor = 140.0
    right_jitter_s = 0.008
    pulse_width = 0.04
    pulse_period = 2200
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Fibonacci
    iR_duration_s = 1.5
    number_of_impulses = 12
    left_fib_start_1 = 1
    left_fib_start_2 = 1
    left_scale_divisor = 100.0
    left_jitter_s = 0.010
    right_fib_start_1 = 2
    right_fib_start_2 = 3
    right_scale_divisor = 120.0
    right_jitter_s = 0.020
    pulse_width = 0.05
    pulse_period = 2000
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Fibonacci
    iR_duration_s = 2.0
    number_of_impulses = 16
    left_fib_start_1 = 1
    left_fib_start_2 = 2
    left_scale_divisor = 85.0
    left_jitter_s = 0.018
    right_fib_start_1 = 3
    right_fib_start_2 = 5
    right_scale_divisor = 100.0
    right_jitter_s = 0.035
    pulse_width = 0.06
    pulse_period = 1800
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Fibonacci
    iR_duration_s = 3.0
    number_of_impulses = 20
    left_fib_start_1 = 2
    left_fib_start_2 = 3
    left_scale_divisor = 70.0
    left_jitter_s = 0.030
    right_fib_start_1 = 5
    right_fib_start_2 = 8
    right_scale_divisor = 85.0
    right_jitter_s = 0.050
    pulse_width = 0.08
    pulse_period = 1600
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Internal guards; built-in presets are already within these limits.
if number_of_impulses > 256
    number_of_impulses = 256
endif

minIRDuration = 4 / sr
if iR_duration_s < minIRDuration
    iR_duration_s = minIRDuration
endif

# PointProcess: To Sound (pulse train) expects an integer interpolation depth.
pulseInterpolationDepth = round(pulse_period)
if pulseInterpolationDepth < 1
    pulseInterpolationDepth = 1
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Pre-calculate Fibonacci sequences for info and visualization
fib1_L = left_fib_start_1
fib2_L = left_fib_start_2
fib1_R = right_fib_start_1
fib2_R = right_fib_start_2

for i from 1 to number_of_impulses
    fibL[i] = fib1_L
    fibR[i] = fib1_R
    tapL[i] = (fib1_L / left_scale_divisor) * iR_duration_s
    tapR[i] = (fib1_R / right_scale_divisor) * iR_duration_s
    
    fibTemp = fib1_L + fib2_L
    fib1_L = fib2_L
    fib2_L = fibTemp
    
    fibTemp = fib1_R + fib2_R
    fib1_R = fib2_R
    fib2_R = fibTemp
endfor

# === Info ===
writeInfoLine: "=== Stereo Fibonacci Convolution ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Left channel: seeds(", left_fib_start_1, ",", left_fib_start_2, ") scale=", left_scale_divisor, " jitter=", fixed$(left_jitter_s * 1000, 1), "ms"
appendInfoLine: "Right channel: seeds(", right_fib_start_1, ",", right_fib_start_2, ") scale=", right_scale_divisor, " jitter=", fixed$(right_jitter_s * 1000, 1), "ms"
appendInfoLine: "IR duration: ", fixed$(iR_duration_s, 3), " s"
appendInfoLine: "Pulse-train adaptation: factor=", fixed$(pulse_amplitude, 3),
    ... " time=", fixed$(pulse_width, 4), " s  depth=", pulseInterpolationDepth
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Fibonacci tap times (no jitter):"
appendInfoLine: "  #   Fib(L) → Time(L)   Fib(R) → Time(R)"
for i from 1 to min(number_of_impulses, 10)
    appendInfoLine: "  ", i, ":  ", fibL[i], " → ", fixed$(tapL[i] * 1000, 1), "ms    ", fibR[i], " → ", fixed$(tapR[i] * 1000, 1), "ms"
endfor
if number_of_impulses > 10
    appendInfoLine: "  ... (", number_of_impulses - 10, " more)"
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# === CREATE LEFT POINT PROCESS ===
appendInfoLine: "  Creating left Fibonacci pattern..."

Create empty PointProcess: "pp_left", 0, iR_duration_s
ppLeft = selected("PointProcess")

fib1 = left_fib_start_1
fib2 = left_fib_start_2
leftPoints = 0

for i from 1 to number_of_impulses
    t = (fib1 / left_scale_divisor) * iR_duration_s + randomGauss(0, left_jitter_s)
    if t > 0 and t < iR_duration_s
        selectObject: ppLeft
        Add point: t
        leftPoints = leftPoints + 1
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

appendInfoLine: "    Added ", leftPoints, " points"

# === CREATE RIGHT POINT PROCESS ===
appendInfoLine: "  Creating right Fibonacci pattern..."

Create empty PointProcess: "pp_right", 0, iR_duration_s
ppRight = selected("PointProcess")

fib1 = right_fib_start_1
fib2 = right_fib_start_2
rightPoints = 0

for i from 1 to number_of_impulses
    t = (fib1 / right_scale_divisor) * iR_duration_s + randomGauss(0, right_jitter_s)
    if t > 0 and t < iR_duration_s
        selectObject: ppRight
        Add point: t
        rightPoints = rightPoints + 1
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

appendInfoLine: "    Added ", rightPoints, " points"

# === CONVERT TO PULSE TRAINS ===
appendInfoLine: "  Converting to pulse trains..."

selectObject: ppLeft
To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulseInterpolationDepth
irLeft = selected("Sound")
selectObject: irLeft
irLeftPeak = Get absolute extremum: 0, 0, "None"
if irLeftPeak > 0
    Scale peak: 0.9
endif

selectObject: ppRight
To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulseInterpolationDepth
irRight = selected("Sound")
selectObject: irRight
irRightPeak = Get absolute extremum: 0, 0, "None"
if irRightPeak > 0
    Scale peak: 0.9
endif

# === BUILD OUTPUT IR ===
# If both convolution operands are multichannel Praat requires equal channel
# counts. Mono/stereo keep the original stereo IR; 3+ channels alternate L/R.
if numChans <= 2
    selectObject: irLeft, irRight
    Combine to stereo
    irStereo = selected("Sound")
    irOutputChannels = 2
else
    for channelIndex from 1 to numChans
        if channelIndex mod 2 = 1
            selectObject: irLeft
        else
            selectObject: irRight
        endif
        irChanID[channelIndex] = Copy: "fib_ir_ch_" + string$(channelIndex)
    endfor

    selectObject: irChanID[1]
    for channelIndex from 2 to numChans
        plusObject: irChanID[channelIndex]
    endfor
    Combine to stereo
    irStereo = selected("Sound")
    irOutputChannels = numChans

    for channelIndex from 1 to numChans
        removeObject: irChanID[channelIndex]
    endfor
endif

# === CONVOLVE ===
appendInfoLine: "  Convolving..."

selectObject: workSource, irStereo
Convolve: "sum", "zero"
wetSound = selected("Sound")

# Discrete convolution contains N + M - 1 samples.
selectObject: wetSound
wetAvailableDur = Get total duration
totalDur = min(originalDur + iR_duration_s, wetAvailableDur)
Extract part: 0, totalDur, "rectangular", 1, "no"
wetTrimmed = selected("Sound")
removeObject: wetSound

# === APPLY WET/DRY MIX ===
if dry_level > 0
    appendInfoLine: "  Mixing wet/dry..."
    
    # Match the dry path to the convolution output channel count.
    if numChans = 1
        # Mono source + stereo IR produces stereo output.
        selectObject: workSource
        Copy: "dry_L"
        dryL = selected("Sound")
        selectObject: workSource
        Copy: "dry_R"
        dryR = selected("Sound")
        selectObject: dryL, dryR
        Combine to stereo
        dryStereo = selected("Sound")
        removeObject: dryL, dryR
        dryOutputChannels = 2
    else
        # Stereo and 3+ channel inputs preserve their channel count.
        selectObject: workSource
        Copy: "dry_multichannel"
        dryStereo = selected("Sound")
        dryOutputChannels = numChans
    endif

    # Extend dry signal
    Create Sound from formula: "silence_ext", dryOutputChannels, 0, iR_duration_s, sr, "0"
    silenceExt = selected("Sound")
    
    selectObject: dryStereo, silenceExt
    Concatenate
    dryFull = selected("Sound")
    removeObject: silenceExt, dryStereo
    
    # Mix
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_full_str$ = string$(dryFull)
    
    selectObject: wetTrimmed
    Formula: "self * " + wet_str$ + " + object[" + dry_full_str$ + ", row, col] * " + dry_str$
    
    removeObject: dryFull
endif

selectObject: wetTrimmed
resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > 0.95
    Scale peak: 0.95
endif
Rename: originalName$ + "_fibonacci_" + presetName$
result = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Fibonacci: " + originalName$ + " (" + presetName$ + ")" + " | v0.5.1"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.7, 1.3
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    Axes: 0, 1, 0, 1
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Wet " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    
    # Fibonacci tap pattern
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.60, 7.70, 2.6, 3.9
    
    Axes: 0, iR_duration_s, -0.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, iR_duration_s, -0.2, 1.2
    
    # Draw Left taps (green, top)
    Colour: "{0.4, 0.7, 0.4}"
    Line width: 2
    for i from 1 to number_of_impulses
        t = tapL[i]
        if t > 0 and t < iR_duration_s
            Draw line: t, 0.55, t, 1.0
            Paint circle: "{0.4, 0.7, 0.4}", t, 1.0, 0.012 * iR_duration_s
        endif
    endfor
    
    # Draw Right taps (blue, bottom)
    Colour: "{0.4, 0.4, 0.7}"
    for i from 1 to number_of_impulses
        t = tapR[i]
        if t > 0 and t < iR_duration_s
            Draw line: t, 0.0, t, 0.45
            Paint circle: "{0.4, 0.4, 0.7}", t, 0.0, 0.012 * iR_duration_s
        endif
    endfor
    Line width: 1
    
    # Center line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, iR_duration_s, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.6, 3.9
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "IR Taps"
    Select inner viewport: 0.60, 7.70, 2.6, 3.9
    Axes: 0, iR_duration_s, -0.2, 1.2
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.4, 0.7, 0.4}"
    Text: iR_duration_s * 0.88, "centre", 1.1, "half", "Left"
    Colour: "{0.4, 0.4, 0.7}"
    Text: iR_duration_s * 0.88, "centre", -0.1, "half", "Right"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "L: seeds(" + string$(left_fib_start_1) + "," + string$(left_fib_start_2) + ") | R: seeds(" + string$(right_fib_start_1) + "," + string$(right_fib_start_2) + ") | Impulses: " + string$(number_of_impulses) + " | Jitter L/R: " + fixed$(left_jitter_s * 1000, 0) + "/" + fixed$(right_jitter_s * 1000, 0) + "ms"
    
    Font size: 10
    Colour: "Black"

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, 4.60, 5.60
    Select inner viewport: 0.60, 7.70, 4.67, 5.53
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "IR law: independent left/right Fibonacci tap sequences"
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Stereo timing divergence is encoded by scale and jitter, not decoration"

    # Restore full-page viewport before leaving visualization.
    Select inner viewport: 0.60, 7.70, 4.67, 5.53
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 5.70
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Cleanup ===
if keep_IR
    selectObject: irStereo
    Rename: "IR_fibonacci_" + presetName$
else
    removeObject: irStereo
endif

removeObject: ppLeft, ppRight, irLeft, irRight
removeObject: workSource

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
if keep_IR
    appendInfoLine: "IR kept: IR_fibonacci_", presetName$
endif

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
