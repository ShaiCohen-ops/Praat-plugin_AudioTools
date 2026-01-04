# ============================================================
# Praat AudioTools - Multi-channel Random Slice Time-Stretcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-channel Random Slice Time-Stretcher
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ===========================================================
# Random Duration-Stretched Slices -> Multi-channel output
# Optimized v2.1: Fixed Selection Error & Hardened Logic
# ===========================================================

form Random Duration-Stretched Slices (Multi-channel output)
    positive number_of_segments 4
    real min_duration 0.5
    real max_duration 2.0
    
    comment ---- Output Options ----
    # Default is unchecked (NO)
    boolean Mix_original_channel_1 0
    
    comment ---- Duration manipulation parameters ----
    optionmenu Preset: 1
        option "Normal (1.0)"
        option "Slow (1.5)"
        option "Fast (0.67)"
        option "Double speed (0.5)"
        option "Half speed (2.0)"
endform

# Apply preset value to duration_factor
if preset = 1
    duration_factor = 1.0
elsif preset = 2
    duration_factor = 1.5
elsif preset = 3
    duration_factor = 0.67
elsif preset = 4
    duration_factor = 0.5
elsif preset = 5
    duration_factor = 2.0
endif

# --------------------------------------------
# Preconditions
# --------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")

selectObject: orig_id
total_duration = Get total duration
fs = Get sampling frequency
nchan = Get number of channels

# Validate user inputs
if min_duration <= 0 or max_duration <= 0
    exitScript: "Durations must be positive numbers."
endif
if min_duration > max_duration
    exitScript: "Minimum duration cannot be larger than maximum duration."
endif
if max_duration > total_duration
    exitScript: "Maximum duration cannot exceed the total sound duration."
endif
if duration_factor <= 0
    exitScript: "Duration factor must be > 0."
endif

# --------------------------------------------
# Calculate padding needed
# --------------------------------------------
max_stretched_duration = max_duration / duration_factor
padding_duration = max_stretched_duration
padded_duration = total_duration + padding_duration

# --------------------------------------------
# Prepare channel 1 (LEFT original) and the slice source
# --------------------------------------------
writeInfoLine: "Preparing channels..."

if nchan = 2
    # CH1 = original LEFT
    selectObject: orig_id
    left_id = Extract one channel: 1
    Rename: orig_name$ + "_CH1_LEFT_orig"
    
    # Pad left channel
    pad_left = Create Sound from formula: "pad", 1, 0, padding_duration, fs, "0"
    selectObject: left_id
    plusObject: pad_left
    left_padded = Concatenate
    removeObject: left_id, pad_left
    left_id = left_padded

    selectObject: orig_id
    right_src_id = Extract one channel: 2
    Rename: orig_name$ + "_sliceSource_RIGHT"
else
    # Mono input: duplicate for left + slice source
    selectObject: orig_id
    Copy: orig_name$ + "_CH1_LEFT_orig"
    left_id = selected("Sound")
    
    # Pad left channel
    pad_left_mono = Create Sound from formula: "pad", 1, 0, padding_duration, fs, "0"
    selectObject: left_id
    plusObject: pad_left_mono
    left_padded = Concatenate
    removeObject: left_id, pad_left_mono
    left_id = left_padded

    selectObject: orig_id
    Copy: orig_name$ + "_sliceSource_MONO"
    right_src_id = selected("Sound")
endif

# --------------------------------------------
# Procedure: Duration stretch (PSOLA)
# --------------------------------------------
procedure DurationStretchOnSelected: .dur_factor
    .local_in_id = selected("Sound")
    selectObject: .local_in_id
    .dur = Get total duration
    
    # Create manipulation object
    .manipulation = To Manipulation: 0.01, 75, 600
    
    # Create duration tier
    .durationTier = Create DurationTier: "duration", 0, .dur
    Add point: 0, .dur_factor
    Add point: .dur, .dur_factor
    
    # Replace duration tier in manipulation
    selectObject: .manipulation
    plusObject: .durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: .manipulation
    .resynthesized = Get resynthesis (overlap-add)
    
    # Normalize result
    Scale peak: 0.99
    
    # Clean up intermediate objects
    removeObject: .durationTier, .manipulation
    
    selectObject: .resynthesized
endproc

# --------------------------------------------
# Build one full-length channel per slice
# --------------------------------------------
chan_ids# = zero# (number_of_segments)

# CRITICAL FIX: Get the duration of the source ONCE before the loop
selectObject: right_src_id
total_src_dur = Get total duration

for i to number_of_segments
    # Calculate random window based on the pre-calculated duration
    seg_len = randomUniform(min_duration, max_duration)
    max_start = total_src_dur - seg_len
    win_start = randomUniform(0, max_start)
    win_end   = win_start + seg_len
    
    writeInfoLine: "Slice ", i, ": processing ", fixed$(seg_len, 3), "s segment..."

    # 1. Extract raw segment
    selectObject: right_src_id
    seg_id = Extract part: win_start, win_end, "rectangular", 1, "no"
    
    # 2. Duration Stretch
    @DurationStretchOnSelected: duration_factor
    stretched_id = selected("Sound")
    Rename: "stretched_" + string$(i)
    
    # 3. Calculate Placement
    selectObject: stretched_id
    stretched_dur = Get total duration
    
    original_center = win_start + (seg_len / 2)
    target_start = original_center - (stretched_dur / 2)
    
    if target_start < 0
        target_start = 0
    endif
    
    # 4. Create Channel and Place Audio (FAST METHOD)
    Create Sound from formula: "CH" + string$(i+1), 1, 0, padded_duration, fs, "0"
    channel_id = selected("Sound")
    
    # Shift stretched piece to target time
    selectObject: stretched_id
    Shift times to: "start time", target_start
    
    # Prepare strings for formula
    str_id$ = string$(stretched_id)
    t_start$ = fixed$(target_start, 6)
    t_end$ = fixed$(target_start + stretched_dur, 6)
    
    # Inject into channel using Formula (Instant)
    selectObject: channel_id
    Formula: "if x >= " + t_start$ + " and x <= " + t_end$ + " then self + object(" + str_id$ + ", x) else self fi"
    
    chan_ids#[i] = channel_id
    
    # Cleanup per-iteration objects
    removeObject: seg_id, stretched_id
endfor

# --------------------------------------------
# Combine (Fixed for TRUE Multi-channel)
# --------------------------------------------
appendInfoLine: "Combining channels..."

# 1. Determine Output Channels
out_chans = number_of_segments
if mix_original_channel_1
    out_chans = out_chans + 1
endif

# 2. Create Master Sound container
Create Sound from formula: "MultiChannel_Output", out_chans, 0, padded_duration, fs, "0"
master_id = selected("Sound")

# 3. Fill channels loop
for i_ch from 1 to out_chans
    selectObject: master_id
    
    src_id = 0
    
    if mix_original_channel_1
        # If mixing: Ch1 is Left, Ch2 is Slice 1, etc.
        if i_ch = 1
            src_id = left_id
        else
            src_id = chan_ids#[i_ch - 1]
        endif
    else
        # If NOT mixing: Ch1 is Slice 1, Ch2 is Slice 2, etc.
        src_id = chan_ids#[i_ch]
    endif
    
    # Use Vectorized Copy
    src_str$ = string$(src_id)
    Formula: "if row = " + string$(i_ch) + " then object(" + src_str$ + ", x) else self fi"
endfor

# Finalize
selectObject: master_id
Rename: orig_name$ + "_MultiChannel_DurStretch_" + string$(out_chans) + "ch"
Scale peak: 0.99

# Cleanup
removeObject: left_id, right_src_id
for i to number_of_segments
    removeObject: chan_ids#[i]
endfor

appendInfoLine: "Done!"
Play