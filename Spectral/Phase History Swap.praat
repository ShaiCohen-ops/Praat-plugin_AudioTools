# ============================================================
# Praat AudioTools - Phase_History_Swap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025) - Fixed syntax, added visualization
# License: MIT License
#
# Description:
#   Phase vocoder effect - swaps phase information between
#   different time segments. Takes magnitude from one portion
#   and phase from another, creating ghostly textures.
# ============================================================

form Phase History Swap v0.3
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
    comment === Custom Settings ===
    positive Split_at_percent 50
    positive Stereo_offset_percent 1.0
    comment (Left = Split, Right = Split + Offset)
    positive Fade_out_seconds 0.5
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

clearinfo
writeInfoLine: "=== Phase History Swap v0.3 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(orig_dur, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Left split: ", split_at_percent, "%"
appendInfoLine: "Right split: ", split_at_percent + stereo_offset_percent, "%"
appendInfoLine: ""

# Prepare mono source
if numChannels > 1
    selectObject: originalID
    workingID = Convert to mono
else
    selectObject: originalID
    workingID = Copy: "working"
endif

# Process LEFT channel (base split)
appendInfo: "Processing left channel..."
@FastPhaseSwap: workingID, split_at_percent, orig_sr
leftID = selected("Sound")
appendInfoLine: " done"

# Process RIGHT channel (split + offset)
offset_split = split_at_percent + stereo_offset_percent
if offset_split >= 99
    offset_split = 99
endif
if offset_split <= 1
    offset_split = 1
endif

appendInfo: "Processing right channel..."
@FastPhaseSwap: workingID, offset_split, orig_sr
rightID = selected("Sound")
appendInfoLine: " done"

# Combine to stereo
selectObject: leftID
plusObject: rightID
resultID = Combine to stereo
Rename: originalName$ + "_phaseswap_" + presetName$

# Apply fadeout
if fade_out_seconds > 0
    selectObject: resultID
    curr_dur = Get total duration
    actual_fade = min(fade_out_seconds, curr_dur)
    t_fade_start = curr_dur - actual_fade
    
    s_start$ = fixed$(t_fade_start, 6)
    s_dur$ = fixed$(actual_fade, 6)
    
    Formula: "if x > " + s_start$ + " then self * 0.5 * (1 + cos(pi * (x - " + s_start$ + ") / " + s_dur$ + ")) else self endif"
endif

# Finalize
selectObject: resultID
Scale peak: scale_peak

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
    Colour: "Black"
    Draw inner box
    Text top: "no", "Phase Swapped (stereo)"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    # Mark split point
    split_time = orig_dur * (split_at_percent / 100)
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 2
    Draw line: split_time, 0, split_time, 5000
    Line width: 1
    
    Font size: 8
    Colour: "Black"
    Text top: "no", "Original (red line = split point)"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: resultID
    resSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Phase Swapped Spectrogram"
    removeObject: resSpecID
    
    # Phase swap diagram
    Select outer viewport: 0, 8, 4.0, 5.2
    Select inner viewport: 0.6, 7.6, 4.15, 5.05
    
    Axes: 0, 1, 0, 1
    
    # Draw early/late segments
    split_ratio = split_at_percent / 100
    
    # Early segment (phase source)
    Paint rectangle: "{0.8, 0.9, 0.8}", 0, split_ratio, 0.55, 0.95
    Colour: "{0.2, 0.5, 0.2}"
    Draw rectangle: 0, split_ratio, 0.55, 0.95
    
    # Late segment (magnitude source)
    Paint rectangle: "{0.9, 0.85, 0.8}", split_ratio, 1, 0.55, 0.95
    Colour: "{0.6, 0.4, 0.2}"
    Draw rectangle: split_ratio, 1, 0.55, 0.95
    
    # Result segment
    Paint rectangle: "{0.8, 0.85, 0.95}", 0, 1 - split_ratio, 0.05, 0.45
    Colour: "{0.2, 0.4, 0.7}"
    Draw rectangle: 0, 1 - split_ratio, 0.05, 0.45
    
    # Labels
    Font size: 9
    Colour: "Black"
    Text: split_ratio / 2, "centre", 0.75, "half", "EARLY"
    Text: split_ratio / 2, "centre", 0.65, "half", "(Phase)"
    Text: (1 + split_ratio) / 2, "centre", 0.75, "half", "LATE"
    Text: (1 + split_ratio) / 2, "centre", 0.65, "half", "(Magnitude)"
    Text: (1 - split_ratio) / 2, "centre", 0.25, "half", "OUTPUT"
    Text: (1 - split_ratio) / 2, "centre", 0.15, "half", "(Late mag + Early phase)"
    
    # Arrow
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
    Text: 0.45, "left", 0.5, "half", "Offset: " + fixed$(stereo_offset_percent, 1) + "%"
    Text: 0.65, "left", 0.5, "half", "Fade: " + fixed$(fade_out_seconds, 2) + "s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# Cleanup
removeObject: workingID, leftID, rightID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", originalName$, "_phaseswap_", presetName$

selectObject: originalID
plusObject: resultID

if play_result
    selectObject: resultID
    Play
endif

# =======================================================
# PROCEDURE: Phase Swap via Matrix Processing
# =======================================================
procedure FastPhaseSwap: .src_id, .split_pct, .target_sr
    selectObject: .src_id
    .tot_dur = Get total duration
    .split_time = .tot_dur * (.split_pct / 100)
    .late_dur = .tot_dur - .split_time
    
    # Split into early and late portions
    .early = Extract part: 0, .split_time, "rectangular", 1, "no"
    selectObject: .src_id
    .late = Extract part: .split_time, .tot_dur, "rectangular", 1, "no"
    
    # Convert early to matrix (for phase extraction)
    selectObject: .early
    .spec_e = To Spectrum: "yes"
    .mat_e = To Matrix
    .id_e = .mat_e
    .nc_e = Get number of columns
    removeObject: .early, .spec_e
    
    # Convert late to matrix (for magnitude + phase replacement)
    selectObject: .late
    .spec_l = To Spectrum: "yes"
    .mat_l = To Matrix
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
    .spec_out = To Spectrum
    .snd_out = To Sound
    
    # Fix sample rate if needed
    selectObject: .snd_out
    .actual_sr = Get sampling frequency
    if .actual_sr <> .target_sr
        Resample: .target_sr, 50
        .resampled = selected("Sound")
        removeObject: .snd_out
        .snd_out = .resampled
    endif
    
    # Trim to exact duration
    selectObject: .snd_out
    Extract part: 0, .late_dur, "rectangular", 1, "no"
    .final_id = selected("Sound")
    
    # Cleanup
    removeObject: .mat_e, .mat_l, .spec_out, .snd_out
    
    selectObject: .final_id
endproc