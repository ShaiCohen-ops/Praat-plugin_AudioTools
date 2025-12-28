# ============================================================
# Praat AudioTools - Phase History Swap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   Phase vocoder effect - swaps phase information between
#   different time segments of the audio. Takes the magnitude
#   (loudness) from one portion and the phase (timing) from
#   another, creating frozen, smeared, or ghostly textures.
#   Stereo width is created by using slightly different split
#   points for left and right channels.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Phase History Swap
    optionmenu Preset: 1
        option Custom
        option Subtle Swap (50% split)
        option Early Swap (30% split)
        option Late Swap (70% split)
        option Extreme Early (20% split)
        option Extreme Late (80% split)
        option Ghost Echo (10% split)
        option Time Smear (90% split)
        option Wide Stereo (50% + 5% offset)
        option Narrow Focus (50% + 0.5% offset)
        option Asymmetric (40% + 3% offset)
    comment === Custom Settings ===
    positive split_at_percent 50
    positive stereo_offset_percent 1.0
    comment (Left = Split, Right = Split + Offset)
    positive fade_out_seconds 0.5
    comment === Output ===
    positive scale_peak 0.95
    boolean play_result 1
endform

# Apply presets
if preset = 2
    split_at_percent = 50
    stereo_offset_percent = 1.0
    preset_name$ = "Subtle"
elsif preset = 3
    split_at_percent = 30
    stereo_offset_percent = 1.5
    preset_name$ = "Early"
elsif preset = 4
    split_at_percent = 70
    stereo_offset_percent = 1.5
    preset_name$ = "Late"
elsif preset = 5
    split_at_percent = 20
    stereo_offset_percent = 2.0
    preset_name$ = "ExtremeEarly"
elsif preset = 6
    split_at_percent = 80
    stereo_offset_percent = 2.0
    preset_name$ = "ExtremeLate"
elsif preset = 7
    split_at_percent = 10
    stereo_offset_percent = 3.0
    preset_name$ = "Ghost"
elsif preset = 8
    split_at_percent = 90
    stereo_offset_percent = 2.0
    preset_name$ = "Smear"
elsif preset = 9
    split_at_percent = 50
    stereo_offset_percent = 5.0
    preset_name$ = "WideStereo"
elsif preset = 10
    split_at_percent = 50
    stereo_offset_percent = 0.5
    preset_name$ = "Narrow"
elsif preset = 11
    split_at_percent = 40
    stereo_offset_percent = 3.0
    preset_name$ = "Asymmetric"
else
    preset_name$ = "Custom"
endif

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound
n_channels = Get number of channels
orig_sr = Get sampling frequency
orig_dur = Get total duration

writeInfoLine: "=== Phase History Swap ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Left split: ", split_at_percent, "%"
appendInfoLine: "Right split: ", split_at_percent + stereo_offset_percent, "%"
appendInfoLine: ""

# Prepare mono source
if n_channels > 1
    selectObject: sound
    working_sound = Convert to mono
else
    selectObject: sound
    working_sound = Copy: "working"
endif

# Process LEFT channel (base split)
appendInfoLine: "Processing left channel..."
@FastPhaseSwap: working_sound, split_at_percent, orig_sr
left_result = selected("Sound")

# Process RIGHT channel (split + offset)
offset_split = split_at_percent + stereo_offset_percent
if offset_split >= 99
    offset_split = 99
endif
if offset_split <= 1
    offset_split = 1
endif

appendInfoLine: "Processing right channel..."
@FastPhaseSwap: working_sound, offset_split, orig_sr
right_result = selected("Sound")

# Combine to stereo
selectObject: left_result
plusObject: right_result
stereo_final = Combine to stereo
Rename: sound_name$ + "_phaseswap"

# Apply fadeout
if fade_out_seconds > 0
    selectObject: stereo_final
    curr_dur = Get total duration
    actual_fade = min(fade_out_seconds, curr_dur)
    t_fade_start = curr_dur - actual_fade
    
    s_start$ = fixed$(t_fade_start, 6)
    s_dur$ = fixed$(actual_fade, 6)
    
    Formula: "if x > " + s_start$ + " then self * 0.5 * (1 + cos(pi * (x - " + s_start$ + ") / " + s_dur$ + ")) else self fi"
endif

# Finalize
selectObject: stereo_final
Scale peak: scale_peak

# Cleanup
removeObject: working_sound, left_result, right_result

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: stereo_final
if play_result
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
    .c_safe$ = "(if " + .c_raw$ + " < 1 then 1 else (if " + .c_raw$ + " > " + .s_nc_e$ + " then " + .s_nc_e$ + " else " + .c_raw$ + " fi) fi)"
    
    # Lookup early real/imag
    .early_re$ = "object[" + .s_id_e$ + ", 1, " + .c_safe$ + "]"
    .early_im$ = "object[" + .s_id_e$ + ", 2, " + .c_safe$ + "]"
    
    # Phase from early, magnitude from self (late)
    .target_phase$ = "arctan2(" + .early_im$ + ", " + .early_re$ + ")"
    .self_mag$ = "sqrt(self[1,col]^2 + self[2,col]^2)"
    
    # Apply: magnitude * cos/sin(phase)
    selectObject: .mat_l
    Formula: "if row = 1 then " + .self_mag$ + " * cos(" + .target_phase$ + ") else " + .self_mag$ + " * sin(" + .target_phase$ + ") fi"
    
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