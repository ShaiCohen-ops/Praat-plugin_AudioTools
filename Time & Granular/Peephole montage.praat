# ============================================================
# Praat AudioTools - PEEPHOLE MONTAGE
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   PEEPHOLE MONTAGE
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
###############################################################################
# PEEPHOLE MONTAGE (Form-Based + Crash Proof)
#
# A. SETUP: Select 1 Sound -> Run -> Script opens editor.
# B. CREATE: Select Sound + PointProcess -> Run -> Script generates montage.
###############################################################################

form Peephole Montage Settings
    comment Window Extraction:
    positive Window_length_(s) 0.5
    boolean Asymmetric_windows 0
    positive Pre_length_(s) 0.3
    positive Post_length_(s) 0.2
    
    comment Processing:
    optionmenu Fade_type 3
        option None
        option Linear
        option Cosine (recommended)
        option Hamming
    positive Fade_duration_(s) 0.01
    
    comment Artistic Variations:
    optionmenu Montage_style 1
        option Pure peephole (baseline)
        option Context ramp (cinematic arrivals)
        option Unreliable narrator (mutations)
        option Microscope (time-stretch)
    
    comment Unreliable Narrator Options (Style 3):
    boolean UN_random_stereo_flip 1
    real UN_pitch_bias_range_(semitones) 0.5
    
    comment Microscope Options (Style 4):
    positive Microscope_time_factor 2.0
    boolean Microscope_preserve_pitch 1
    
    comment Output:
    word Output_name peephole_montage
endform

###############################################################################
# INTELLIGENT WORKFLOW DETECTOR
###############################################################################

n_sounds = numberOfSelected("Sound")
n_pps = numberOfSelected("PointProcess")

if n_sounds = 1 and n_pps = 0
    # === PHASE 1: SETUP ===
    
    sound = selected("Sound")
    sound_name$ = selected$("Sound")
    xmin = Get start time
    xmax = Get end time
    
    # Create the PointProcess
    pp = Create empty PointProcess: "peephole_marks", xmin, xmax
    
    # Open the editor
    selectObject: pp
    plusObject: sound
    View & Edit
    
    # Instructions
    writeInfoLine: "=== PHASE 1: EDITOR OPENED ==="
    appendInfoLine: "1. Mark your points in the editor (Ctrl-P)."
    appendInfoLine: "2. Go back to the Objects window."
    appendInfoLine: "3. Select BOTH the Sound AND the 'peephole_marks' object."
    appendInfoLine: "4. Run this script again."
    
    # Stop here with a message. This prevents the "Pause Form" crash.
    exitScript: "Phase 1 Complete. Mark points, select both objects, and run again."

elsif n_sounds = 1 and n_pps = 1
    # === PHASE 2: PROCESSING ===
    
    sound = selected("Sound")
    pp = selected("PointProcess")
    
    selectObject: pp
    n_points = Get number of points
    
    if n_points = 0
        exitScript: "Error: The selected PointProcess is empty. Please mark points (Ctrl-P) and try again."
    endif
    
    writeInfoLine: "=== PHASE 2: GENERATING MONTAGE ==="
    appendInfoLine: "Style: 'montage_style'"
    appendInfoLine: "Window: 'window_length's"
    appendInfoLine: "Processing 'n_points' points..."
    
    # Continue to Main Logic...

else
    # === ERROR ===
    exitScript: "SELECTION ERROR: To Start, select 1 Sound. To Finish, select 1 Sound AND 1 PointProcess."
endif

###############################################################################
# MAIN LOGIC (Runs only in Phase 2)
###############################################################################

# Get sound info
selectObject: sound
sound_name$ = selected$("Sound")
xmin = Get start time
xmax = Get end time
sample_rate = Get sampling frequency

# Array to hold extracted segments
for i to n_points
    segment_id[i] = 0
endfor

# LOOP THROUGH POINTS
for i to n_points
    selectObject: pp
    t = Get time from index: i
    
    # Determine window boundaries
    if asymmetric_windows
        t_start = t - pre_length
        t_end = t + post_length
    else
        half_window = window_length / 2
        t_start = t - half_window
        t_end = t + half_window
    endif
    
    # Clamp to sound bounds
    if t_start < xmin
        t_start = xmin
    endif
    if t_end > xmax
        t_end = xmax
    endif
    
    # Extract segment
    selectObject: sound
    segment = Extract part: t_start, t_end, "rectangular", 1, "no"
    Rename: "segment_'i'"
    segment_duration = t_end - t_start
    
    # Apply fade
    if fade_type <> 1
        if fade_type = 2
            # Linear
            Fade in: 0, 0, fade_duration, "no"
            Fade out: 0, segment_duration - fade_duration, fade_duration, "no"
        elsif fade_type = 3
            # Cosine
            Formula: "if x < fade_duration then self * (1 - cos(pi * x / fade_duration)) / 2 else if x > segment_duration - fade_duration then self * (1 - cos(pi * (segment_duration - x) / fade_duration)) / 2 else self fi fi"
        elsif fade_type = 4
            # Hamming
            Formula: "if x < fade_duration then self * (0.54 - 0.46 * cos(pi * x / fade_duration)) else if x > segment_duration - fade_duration then self * (0.54 - 0.46 * cos(pi * (segment_duration - x) / fade_duration)) / 2 else self fi fi"
        endif
    endif
    
    # Apply Styles
    if montage_style = 3
        @unreliableNarrator: segment, i, n_points
        removeObject: segment
        segment = unreliableNarrator.result
    elsif montage_style = 4
        @microscope: segment, microscope_time_factor, microscope_preserve_pitch
        removeObject: segment
        segment = microscope.result
    endif
    
    segment_id[i] = segment
endfor

# SPECIAL STYLE: Context Ramp (Style 2)
if montage_style = 2
    for i to n_points
        removeObject: segment_id[i]
        selectObject: pp
        t = Get time from index: i
        
        @analyzeContext: sound, t, window_length
        adaptive_pre = pre_length * (1 + analyzeContext.pause_before * 0.5)
        adaptive_post = post_length * (1.2 - analyzeContext.intensity * 0.4)
        
        t_start = max(xmin, t - adaptive_pre)
        t_end = min(xmax, t + adaptive_post)
        
        selectObject: sound
        segment = Extract part: t_start, t_end, "rectangular", 1, "no"
        Rename: "segment_'i'_adaptive"
        segment_duration = t_end - t_start
        
        # Apply cosine fade
        Formula: "if x < fade_duration then self * (1 - cos(pi * x / fade_duration)) / 2 else if x > segment_duration - fade_duration then self * (1 - cos(pi * (segment_duration - x) / fade_duration)) / 2 else self fi fi"
        
        segment_id[i] = segment
    endfor
endif

# CONCATENATE
for i to n_points
    if i = 1
        selectObject: segment_id[i]
    else
        plusObject: segment_id[i]
    endif
endfor

result = Concatenate
Rename: output_name$

# CLEANUP
# We leave the PointProcess alive so you can change settings and run again.
for i to n_points
    removeObject: segment_id[i]
endfor

# Play and Finish
selectObject: result
appendInfoLine: "Done! Created: 'output_name$'"
Play

###############################################################################
# PROCEDURES
###############################################################################

procedure unreliableNarrator: .seg, .index, .total
    selectObject: .seg
    .seg_copy = Copy: "mutated_'.index'"
    .seg_channels = Get number of channels
    
    if .seg_channels = 2 and UN_random_stereo_flip
        if randomInteger(1, 2) = 1
            .ch1 = Extract one channel: 1
            selectObject: .seg_copy
            .ch2 = Extract one channel: 2
            selectObject: .ch2
            plusObject: .ch1
            .swapped = Combine to stereo
            removeObject: .ch1, .ch2, .seg_copy
            .seg_copy = .swapped
        endif
    endif
    
    if UN_pitch_bias_range <> 0 and .seg_channels = 1
        bias_factor = (.index / .total) * UN_pitch_bias_range
        bias_semitones = randomUniform(-bias_factor, bias_factor)
        if abs(bias_semitones) > 0.01
            selectObject: .seg_copy
            .temp_manip = To Manipulation: 0.01, 75, 600
            .temp_tier = Extract pitch tier
            selectObject: .temp_tier
            Formula: "self * 2^(bias_semitones/12)"
            selectObject: .temp_manip
            plusObject: .temp_tier
            Replace pitch tier
            selectObject: .temp_manip
            .seg_resynth = Get resynthesis (overlap-add)
            removeObject: .temp_manip, .temp_tier, .seg_copy
            .seg_copy = .seg_resynth
        endif
    endif
    
    .result = .seg_copy
endproc

procedure microscope: .seg, .factor, .preserve_pitch
    selectObject: .seg
    .seg_channels = Get number of channels
    if .preserve_pitch
        if .seg_channels = 2
            .ch1 = Extract one channel: 1
            selectObject: .seg
            .ch2 = Extract one channel: 2
            selectObject: .ch1
            .manip1 = To Manipulation: 0.01, 75, 600
            .dur_tier1 = Extract duration tier
            .dur1 = Get total duration
            selectObject: .dur_tier1
            Add point: .dur1 / 2, .factor
            selectObject: .manip1
            plusObject: .dur_tier1
            Replace duration tier
            selectObject: .manip1
            .ch1_new = Get resynthesis (overlap-add)
            removeObject: .manip1, .dur_tier1, .ch1
            selectObject: .ch2
            .manip2 = To Manipulation: 0.01, 75, 600
            .dur_tier2 = Extract duration tier
            .dur2 = Get total duration
            selectObject: .dur_tier2
            Add point: .dur2 / 2, .factor
            selectObject: .manip2
            plusObject: .dur_tier2
            Replace duration tier
            selectObject: .manip2
            .ch2_new = Get resynthesis (overlap-add)
            removeObject: .manip2, .dur_tier2, .ch2
            selectObject: .ch1_new
            plusObject: .ch2_new
            .result = Combine to stereo
            removeObject: .ch1_new, .ch2_new
        else
            selectObject: .seg
            .manip = To Manipulation: 0.01, 75, 600
            .dur_tier = Extract duration tier
            .dur = Get total duration
            selectObject: .dur_tier
            Add point: .dur / 2, .factor
            selectObject: .manip
            plusObject: .dur_tier
            Replace duration tier
            selectObject: .manip
            .result = Get resynthesis (overlap-add)
            removeObject: .manip, .dur_tier
        endif
    else
        selectObject: .seg
        .result = To Sound (PSOLA): 75, 600, 1/.factor, 1.0
    endif
endproc

procedure analyzeContext: .snd, .time, .window_len
    selectObject: .snd
    .t_start = max(xmin, .time - .window_len)
    .t_end = min(xmax, .time + .window_len / 2)
    .window = Extract part: .t_start, .t_end, "rectangular", 1, "no"
    .intens = To Intensity: 100, 0, "yes"
    .mean_intens = Get mean: 0, 0, "dB"
    .intensity = (.mean_intens - 40) / 40
    if .intensity < 0
        .intensity = 0
    elsif .intensity > 1
        .intensity = 1
    endif
    .pre_start = max(xmin, .time - .window_len * 2)
    .pre_end = .time - .window_len / 4
    if .pre_end > .pre_start
        selectObject: .snd
        .pre_window = Extract part: .pre_start, .pre_end, "rectangular", 1, "no"
        .pre_intens = To Intensity: 100, 0, "yes"
        .pre_mean = Get mean: 0, 0, "dB"
        if .pre_mean < .mean_intens - 10
            .pause_before = 1
        else
            .pause_before = 0
        endif
        removeObject: .pre_window, .pre_intens
    else
        .pause_before = 0
    endif
    removeObject: .window, .intens
endproc