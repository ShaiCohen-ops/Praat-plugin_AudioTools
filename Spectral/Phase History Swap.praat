# ============================================================
# Praat AudioTools - Phase_History_Swap.praat
# Author: Shai Cohen
# Version: 1.0 (2025) - OPTIMIZED for extreme splits
# License: MIT License
#
# Description:
#   Phase vocoder effect - NOW FAST even at extreme splits!
#   Speed modes: 2-10× faster for 10%/90% splits
# ============================================================

form Phase History Swap v1.0 (Optimized)
    optionmenu Preset: 1
        option Custom
        option Subtle Swap (50%)
        option Early Swap (30%)
        option Late Swap (70%)
        option Extreme Early (20%)
        option Extreme Late (80%)
        option Ghost Echo (10%)
        option Time Smear (90%)
        option Wide Stereo (50% + 5%)
        option Narrow Focus (50% + 0.5%)
        option Asymmetric (40% + 3%)
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    comment === Custom Settings ===
    positive Split_at_percent 50
    positive Stereo_offset_percent 1.0
    comment (Left = Split, Right = Split + Offset)
    comment === Tail & Fade ===
    positive Tail_duration_seconds 0.5
    comment (Extra time for natural decay)
    positive Fade_out_seconds 0.3
    comment (Fade to zero at the end)
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 2
    split_at_percent = 50
    stereo_offset_percent = 1.0
    presetName$ = "Subtle"
elsif preset = 3
    split_at_percent = 30
    stereo_offset_percent = 1.5
    presetName$ = "Early"
elsif preset = 4
    split_at_percent = 70
    stereo_offset_percent = 1.5
    presetName$ = "Late"
elsif preset = 5
    split_at_percent = 20
    stereo_offset_percent = 2.0
    presetName$ = "ExtremeEarly"
elsif preset = 6
    split_at_percent = 80
    stereo_offset_percent = 2.0
    presetName$ = "ExtremeLate"
elsif preset = 7
    split_at_percent = 10
    stereo_offset_percent = 3.0
    presetName$ = "Ghost"
elsif preset = 8
    split_at_percent = 90
    stereo_offset_percent = 2.0
    presetName$ = "Smear"
elsif preset = 9
    split_at_percent = 50
    stereo_offset_percent = 5.0
    presetName$ = "WideStereo"
elsif preset = 10
    split_at_percent = 50
    stereo_offset_percent = 0.5
    presetName$ = "Narrow"
elsif preset = 11
    split_at_percent = 40
    stereo_offset_percent = 3.0
    presetName$ = "Asymmetric"
else
    presetName$ = "Custom"
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
numChannels = Get number of channels
orig_sr = Get sampling frequency
orig_dur = Get total duration

startTime = stopwatch

clearinfo
writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║    PHASE HISTORY SWAP v1.0 (Optimized for Extreme Splits)   ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Duration: ", fixed$(orig_dur, 2), " s"
appendInfoLine: "Tail: ", fixed$(tail_duration_seconds, 2), " s"
appendInfoLine: "Fade: ", fixed$(fade_out_seconds, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Left split: ", split_at_percent, "%"
appendInfoLine: "Right split: ", split_at_percent + stereo_offset_percent, "%"
appendInfoLine: ""

# Prepare mono source
if numChannels > 1
    selectObject: originalID
    Convert to mono
    workingID = selected("Sound")
else
    selectObject: originalID
    Copy: "working"
    workingID = selected("Sound")
endif

# === OPTIONAL DOWNSAMPLING ===
if targetSR > 0 and orig_sr > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz..."
    selectObject: workingID
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: workingID
    workingID = resampledID
    workingSR = targetSR
else
    workingSR = orig_sr
endif

# Process LEFT channel
appendInfo: "Processing left channel..."
@FastPhaseSwap: workingID, split_at_percent, workingSR, tail_duration_seconds
leftID = selected("Sound")
appendInfoLine: " done"

# Process RIGHT channel
offset_split = split_at_percent + stereo_offset_percent
offset_split = max(1, min(99, offset_split))

appendInfo: "Processing right channel..."
@FastPhaseSwap: workingID, offset_split, workingSR, tail_duration_seconds
rightID = selected("Sound")
appendInfoLine: " done"

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and orig_sr > targetSR
    appendInfoLine: "[SPEED] Upsampling to ", orig_sr, " Hz..."
    
    selectObject: leftID
    Resample: orig_sr, 50
    leftID_up = selected("Sound")
    removeObject: leftID
    leftID = leftID_up
    
    selectObject: rightID
    Resample: orig_sr, 50
    rightID_up = selected("Sound")
    removeObject: rightID
    rightID = rightID_up
endif

# Match durations
selectObject: leftID
leftDur = Get total duration
selectObject: rightID
rightDur = Get total duration

maxDur = max(leftDur, rightDur)

# Pad shorter to match
if leftDur < maxDur
    selectObject: leftID
    Create Sound from formula: "pad", 1, 0, maxDur - leftDur, orig_sr, "0"
    silencePad = selected("Sound")
    selectObject: leftID, silencePad
    Concatenate
    leftID_new = selected("Sound")
    removeObject: leftID, silencePad
    leftID = leftID_new
endif

if rightDur < maxDur
    selectObject: rightID
    Create Sound from formula: "pad", 1, 0, maxDur - rightDur, orig_sr, "0"
    silencePad = selected("Sound")
    selectObject: rightID, silencePad
    Concatenate
    rightID_new = selected("Sound")
    removeObject: rightID, silencePad
    rightID = rightID_new
endif

# Combine to stereo
selectObject: leftID
plusObject: rightID
Combine to stereo
resultID = selected("Sound")
Rename: originalName$ + "_phaseswap_" + presetName$

# Apply fadeout to zero at the END
if fade_out_seconds > 0
    selectObject: resultID
    curr_dur = Get total duration
    
    fade_start = curr_dur - fade_out_seconds
    
    if fade_start < 0
        fade_start = 0
    endif
    
    actual_fade = curr_dur - fade_start
    
    s_start$ = fixed$(fade_start, 6)
    s_dur$ = fixed$(actual_fade, 6)
    
    Formula: "if x > " + s_start$ + " then self * 0.5 * (1 + cos(pi * (x - " + s_start$ + ") / " + s_dur$ + ")) else self endif"
endif

# Finalize
selectObject: resultID
Scale peak: scale_peak

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phase History Swap: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark fade start
    selectObject: resultID
    result_dur = Get total duration
    fade_start_mark = result_dur - fade_out_seconds
    if fade_start_mark > 0
        Colour: "{0.9, 0.7, 0.3}"
        Line width: 1
        Draw line: fade_start_mark, -1, fade_start_mark, 1
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Phase Swapped (orange = fade)"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: originalID
    To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    origSpecID = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    # Mark split point
    split_time = orig_dur * (split_at_percent / 100)
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 2
    Draw line: split_time, 0, split_time, 5000
    Line width: 1
    
    Font size: 8
    Colour: "Black"
    Text top: "no", "Original (red = split)"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: resultID
    To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    resSpecID = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    if fade_start_mark > 0
        Colour: "{0.9, 0.7, 0.3}"
        Line width: 2
        Draw line: fade_start_mark, 0, fade_start_mark, 5000
        Line width: 1
    endif
    
    Font size: 8
    Colour: "Black"
    Text top: "no", "Phase Swapped (orange = fade)"
    removeObject: resSpecID
    
    # Phase swap diagram
    Select outer viewport: 0, 8, 4.0, 5.2
    Select inner viewport: 0.6, 7.6, 4.15, 5.05
    
    Axes: 0, 1, 0, 1
    
    split_ratio = split_at_percent / 100
    
    # Early segment
    Paint rectangle: "{0.8, 0.9, 0.8}", 0, split_ratio, 0.55, 0.95
    Colour: "{0.2, 0.5, 0.2}"
    Draw rectangle: 0, split_ratio, 0.55, 0.95
    
    # Late segment
    Paint rectangle: "{0.9, 0.85, 0.8}", split_ratio, 1, 0.55, 0.95
    Colour: "{0.6, 0.4, 0.2}"
    Draw rectangle: split_ratio, 1, 0.55, 0.95
    
    # Result + tail
    result_ratio = 0.7
    Paint rectangle: "{0.8, 0.85, 0.95}", 0, result_ratio, 0.05, 0.45
    Colour: "{0.2, 0.4, 0.7}"
    Draw rectangle: 0, result_ratio, 0.05, 0.45
    
    Paint rectangle: "{0.95, 0.9, 0.85}", result_ratio, 1, 0.05, 0.45
    Colour: "{0.8, 0.6, 0.3}"
    Draw rectangle: result_ratio, 1, 0.05, 0.45
    
    # Labels
    Font size: 9
    Colour: "Black"
    Text: split_ratio / 2, "centre", 0.75, "half", "EARLY"
    Text: split_ratio / 2, "centre", 0.65, "half", "(Phase)"
    Text: (1 + split_ratio) / 2, "centre", 0.75, "half", "LATE"
    Text: (1 + split_ratio) / 2, "centre", 0.65, "half", "(Magnitude)"
    Text: result_ratio / 2, "centre", 0.25, "half", "OUTPUT"
    Text: (1 + result_ratio) / 2, "centre", 0.25, "half", "TAIL+FADE"
    
    Colour: "{0.5, 0.5, 0.5}"
    Draw arrow: 0.5, 0.52, 0.5, 0.48
    
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Phase Swap Process"
    
    # Info panel
    Select outer viewport: 0, 8, 5.3, 5.9
    Select inner viewport: 0.5, 7.7, 5.35, 5.85
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Split L: " + fixed$(split_at_percent, 1) + "%"
    Text: 0.22, "left", 0.5, "half", "Split R: " + fixed$(split_at_percent + stereo_offset_percent, 1) + "%"
    Text: 0.45, "left", 0.5, "half", speedStr$
    Text: 0.65, "left", 0.5, "half", "Time: " + fixed$(processingTime, 2) + "s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# Cleanup
removeObject: workingID, leftID, rightID

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                      COMPLETE                                ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", originalName$, "_phaseswap_", presetName$

selectObject: originalID
plusObject: resultID

if play_result
    selectObject: resultID
    Play
endif

# =======================================================
# PROCEDURE: Phase Swap with Tail
# =======================================================
procedure FastPhaseSwap: .src_id, .split_pct, .target_sr, .tail_dur
    selectObject: .src_id
    .tot_dur = Get total duration
    .split_time = .tot_dur * (.split_pct / 100)
    .late_dur = .tot_dur - .split_time
    
    # Split into early and late
    selectObject: .src_id
    Extract part: 0, .split_time, "rectangular", 1, "no"
    .early = selected("Sound")
    
    selectObject: .src_id
    Extract part: .split_time, .tot_dur, "rectangular", 1, "no"
    .late = selected("Sound")
    
    # Convert early to matrix (for phase)
    selectObject: .early
    To Spectrum: "yes"
    .spec_e = selected("Spectrum")
    To Matrix
    .mat_e = selected("Matrix")
    .id_e = .mat_e
    .nc_e = Get number of columns
    removeObject: .early, .spec_e
    
    # Convert late to matrix (for magnitude)
    selectObject: .late
    To Spectrum: "yes"
    .spec_l = selected("Spectrum")
    To Matrix
    .mat_l = selected("Matrix")
    .id_l = .mat_l
    removeObject: .late, .spec_l
    
    # Frequency alignment ratio
    .dur_ratio = .split_time / .late_dur
    
    # Build formula strings
    .s_ratio$ = fixed$(.dur_ratio, 10)
    .s_nc_e$ = fixed$(.nc_e, 0)
    .s_id_e$ = fixed$(.id_e, 0)
    
    # Column mapping with clamping
    .c_raw$ = "round(col * " + .s_ratio$ + ")"
    .c_safe$ = "(if " + .c_raw$ + " < 1 then 1 else (if " + .c_raw$ + " > " + .s_nc_e$ + " then " + .s_nc_e$ + " else " + .c_raw$ + " endif) endif)"
    
    # Lookup early real/imag
    .early_re$ = "object[" + .s_id_e$ + ", 1, " + .c_safe$ + "]"
    .early_im$ = "object[" + .s_id_e$ + ", 2, " + .c_safe$ + "]"
    
    # Phase from early, magnitude from self (late)
    .target_phase$ = "arctan2(" + .early_im$ + ", " + .early_re$ + ")"
    .self_mag$ = "sqrt(self[1,col]^2 + self[2,col]^2)"
    
    # Apply: magnitude * cos/sin(phase)
    selectObject: .mat_l
    Formula: "if row = 1 then " + .self_mag$ + " * cos(" + .target_phase$ + ") else " + .self_mag$ + " * sin(" + .target_phase$ + ") endif"
    
    # Reconstruct
    To Spectrum
    .spec_out = selected("Spectrum")
    To Sound
    .snd_out = selected("Sound")
    
    # Fix sample rate if needed
    selectObject: .snd_out
    .actual_sr = Get sampling frequency
    if .actual_sr <> .target_sr
        Resample: .target_sr, 50
        .resampled = selected("Sound")
        removeObject: .snd_out
        .snd_out = .resampled
    endif
    
    # Preserve tail
    selectObject: .snd_out
    .actual_dur = Get total duration
    .target_dur = .late_dur + .tail_dur
    
    if .actual_dur > .target_dur
        Extract part: 0, .target_dur, "rectangular", 1, "no"
        .final_id = selected("Sound")
        removeObject: .snd_out
    else
        .final_id = .snd_out
    endif
    
    # Cleanup
    removeObject: .mat_e, .mat_l, .spec_out
    
    selectObject: .final_id
endproc