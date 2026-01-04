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
# PEEPHOLE MONTAGE
# 
# Extract windows around marked points and concatenate them into a montage.
# Creates a jump-cut collage / highlight reel from selected moments.
#
# Workflow:
# 1. Select a Sound
# 2. Run script → creates PointProcess, opens editor
# 3. Add points at moments of interest (Ctrl-P or Cmd-P)
# 4. Click Continue
# 5. Script extracts windows and concatenates
#
# Artistic variations available via form options
###############################################################################

form Peephole Montage
    comment Window extraction:
    positive Window_length_(s) 0.5
    boolean Asymmetric_windows 0
    positive Pre_length_(s) 0.3
    positive Post_length_(s) 0.2
    
    comment Anti-click processing:
    optionmenu Fade_type 3
        option None
        option Linear
        option Cosine (recommended)
        option Hamming
    positive Fade_duration_(s) 0.01
    
    comment Artistic variations:
    optionmenu Montage_style 1
        option Pure peephole (baseline jump-cuts)
        option Context ramp (cinematic arrivals)
        option Unreliable narrator (subtle mutations)
        option Microscope (time-stretch each window)
    
    comment Unreliable narrator options (style 3):
    boolean UN_random_stereo_flip 1
    real UN_pitch_bias_range_(semitones) 0.5
    
    comment Microscope options (style 4):
    positive Microscope_time_factor 2.0
    boolean Microscope_preserve_pitch 1
    
    comment Output:
    word Output_name peephole_montage
endform

###############################################################################
# PART 1: SETUP AND POINT COLLECTION
###############################################################################

# Check selection
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Get sound info
sound = selected("Sound")
sound_name$ = selected$("Sound")
xmin = Get start time
xmax = Get end time
duration = xmax - xmin
sample_rate = Get sampling frequency
nchannels = Get number of channels

# Create empty PointProcess with sound's time domain
pp = Create empty PointProcess: "peephole_marks", xmin, xmax

# Open editor for user to mark points
writeInfoLine: "=== PEEPHOLE MONTAGE ==="
appendInfoLine: "Sound: 'sound_name$'"
appendInfoLine: "Duration: 'duration:3' s"
appendInfoLine: "Channels: 'nchannels'"
appendInfoLine: ""
appendInfoLine: "Add points at moments you want to extract."
appendInfoLine: "Use Ctrl-P (or Cmd-P) to add points at cursor position."
appendInfoLine: "Click Continue when ready..."

# Pause for user input
selectObject: pp
View & Edit
beginPause: "Mark peephole moments"
    comment: "Add points in the PointProcess editor (Ctrl-P or Cmd-P)."
    comment: "Then click Continue to create the montage."
endPause: "Continue", 1

# Get marked points
selectObject: pp
n_points = Get number of points

if n_points = 0
    removeObject: pp
    exitScript: "No points marked. Please run again and add at least one point."
endif

appendInfoLine: ""
appendInfoLine: "Processing 'n_points' marked moments..."

###############################################################################
# PART 2: EXTRACT WINDOWS AROUND EACH POINT
###############################################################################

# Array to hold extracted segments
for i to n_points
    segment_id[i] = 0
endfor

selectObject: sound

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
    
    # Apply fade to avoid clicks
    if fade_type <> 1
        # Determine fade parameters
        fade_samples = round(fade_duration * sample_rate)
        segment_samples = Get number of samples
        
        if fade_samples * 2 < segment_samples
            if fade_type = 2
                # Linear fade
                Fade in: 0, 0, fade_duration, "no"
                Fade out: 0, segment_duration - fade_duration, fade_duration, "no"
            elsif fade_type = 3
                # Cosine fade
                Formula: "if x < fade_duration then self * (1 - cos(pi * x / fade_duration)) / 2 else if x > segment_duration - fade_duration then self * (1 - cos(pi * (segment_duration - x) / fade_duration)) / 2 else self fi fi"
            elsif fade_type = 4
                # Hamming window on edges
                Formula: "if x < fade_duration then self * (0.54 - 0.46 * cos(pi * x / fade_duration)) else if x > segment_duration - fade_duration then self * (0.54 - 0.46 * cos(pi * (segment_duration - x) / fade_duration)) / 2 else self fi fi"
            endif
        endif
    endif
    
    # Apply artistic variations based on style
    if montage_style = 3
        # UNRELIABLE NARRATOR: subtle mutations
        @unreliableNarrator: segment, i, n_points
        removeObject: segment
        segment = unreliableNarrator.result
    elsif montage_style = 4
        # MICROSCOPE: time-stretch
        @microscope: segment, microscope_time_factor, microscope_preserve_pitch
        removeObject: segment
        segment = microscope.result
    endif
    
    # Verify channel count
    selectObject: segment
    seg_ch = Get number of channels
    appendInfoLine: "  Point 'i': t='t:3's, window=['t_start:3', 't_end:3'], channels='seg_ch'"
    
    segment_id[i] = segment
endfor

###############################################################################
# PART 3: SPECIAL HANDLING FOR CONTEXT RAMP STYLE
###############################################################################

if montage_style = 2
    # CONTEXT RAMP: variable-length windows based on local context
    appendInfoLine: ""
    appendInfoLine: "Applying context ramp (cinematic arrivals)..."
    
    # Re-extract with variable pre/post based on local intensity
    for i to n_points
        # Remove old segment
        removeObject: segment_id[i]
        
        selectObject: pp
        t = Get time from index: i
        
        # Analyze local context
        @analyzeContext: sound, t, window_length
        local_intensity = analyzeContext.intensity
        local_pause = analyzeContext.pause_before
        
        # Adaptive pre-length: longer if following a pause
        adaptive_pre = pre_length * (1 + local_pause * 0.5)
        # Adaptive post-length: shorter if high intensity
        adaptive_post = post_length * (1.2 - local_intensity * 0.4)
        
        t_start = max(xmin, t - adaptive_pre)
        t_end = min(xmax, t + adaptive_post)
        
        selectObject: sound
        segment = Extract part: t_start, t_end, "rectangular", 1, "no"
        Rename: "segment_'i'_adaptive"
        segment_duration = t_end - t_start
        
        # Apply cosine fade
        Formula: "if x < fade_duration then self * (1 - cos(pi * x / fade_duration)) / 2 else if x > segment_duration - fade_duration then self * (1 - cos(pi * (segment_duration - x) / fade_duration)) / 2 else self fi fi"
        
        segment_id[i] = segment
        
        appendInfoLine: "  Point 'i': adaptive window ['t_start:3', 't_end:3'] (pre='adaptive_pre:3', post='adaptive_post:3')"
    endfor
endif

###############################################################################
# PART 4: CONCATENATE SEGMENTS
###############################################################################

appendInfoLine: ""
appendInfoLine: "Concatenating 'n_points' segments..."

# Select all segments
for i to n_points
    if i = 1
        selectObject: segment_id[i]
    else
        plusObject: segment_id[i]
    endif
endfor

# Concatenate
result = Concatenate
Rename: output_name$

# Get montage info
montage_duration = Get total duration
compression_ratio = duration / montage_duration

appendInfoLine: ""
appendInfoLine: "=== MONTAGE COMPLETE ==="
appendInfoLine: "Original duration: 'duration:3' s"
appendInfoLine: "Montage duration: 'montage_duration:3' s"
appendInfoLine: "Compression ratio: 'compression_ratio:2'x"
appendInfoLine: ""
appendInfoLine: "Output: 'output_name$'"

###############################################################################
# CLEANUP
###############################################################################

# Remove PointProcess
removeObject: pp

# Remove all segments
for i to n_points
    removeObject: segment_id[i]
endfor

# Play result
selectObject: result
appendInfoLine: ""
appendInfoLine: "Playing result..."
Play

# Select original sound + result for final selection
selectObject: sound
plusObject: result

appendInfoLine: "Cleanup complete. Kept: 'sound_name$', 'output_name$'"

###############################################################################
# PROCEDURES
###############################################################################

procedure unreliableNarrator: .seg, .index, .total
    # Apply subtle, rule-based mutations to each segment
    # Creates an "unreliable memory" effect
    
    selectObject: .seg
    .seg_copy = Copy: "mutated_'.index'"
    
    # Check the actual number of channels in THIS segment
    selectObject: .seg_copy
    .seg_channels = Get number of channels
    
    # Random stereo flip (only if THIS segment is stereo)
    if .seg_channels = 2 and uN_random_stereo_flip
        if randomInteger(1, 2) = 1
            # Extract channels and swap
            selectObject: .seg_copy
            .ch1 = Extract one channel: 1
            selectObject: .seg_copy
            .ch2 = Extract one channel: 2
            # Combine in reverse order
            selectObject: .ch2
            plusObject: .ch1
            .swapped = Combine to stereo
            removeObject: .ch1, .ch2, .seg_copy
            .seg_copy = .swapped
        endif
    endif
    
    # Pitch bias (progressive or random) - ONLY FOR MONO
    if uN_pitch_bias_range <> 0 and .seg_channels = 1
        # Bias increases with index (memory gets more distorted)
        bias_factor = (.index / .total) * uN_pitch_bias_range
        bias_semitones = randomUniform(-bias_factor, bias_factor)
        
        if abs(bias_semitones) > 0.01
            selectObject: .seg_copy
            .temp_manip = To Manipulation: 0.01, 75, 600
            .temp_tier = Extract pitch tier
            selectObject: .temp_tier
            Formula: "self * 2^(bias_semitones/12)"
            # Now replace the modified tier back into the manipulation
            selectObject: .temp_manip
            plusObject: .temp_tier
            Replace pitch tier
            # Resynthesize
            selectObject: .temp_manip
            .seg_resynth = Get resynthesis (overlap-add)
            # Cleanup
            removeObject: .temp_manip, .temp_tier, .seg_copy
            .seg_copy = .seg_resynth
        endif
    endif
    
    # For stereo with pitch bias, process channels separately
    if uN_pitch_bias_range <> 0 and .seg_channels = 2
        bias_factor = (.index / .total) * uN_pitch_bias_range
        bias_semitones = randomUniform(-bias_factor, bias_factor)
        
        if abs(bias_semitones) > 0.01
            # Extract channels
            selectObject: .seg_copy
            .ch1 = Extract one channel: 1
            selectObject: .seg_copy
            .ch2 = Extract one channel: 2
            
            # Process channel 1
            selectObject: .ch1
            .manip1 = To Manipulation: 0.01, 75, 600
            .tier1 = Extract pitch tier
            selectObject: .tier1
            Formula: "self * 2^(bias_semitones/12)"
            selectObject: .manip1
            plusObject: .tier1
            Replace pitch tier
            selectObject: .manip1
            .ch1_new = Get resynthesis (overlap-add)
            removeObject: .manip1, .tier1, .ch1
            
            # Process channel 2
            selectObject: .ch2
            .manip2 = To Manipulation: 0.01, 75, 600
            .tier2 = Extract pitch tier
            selectObject: .tier2
            Formula: "self * 2^(bias_semitones/12)"
            selectObject: .manip2
            plusObject: .tier2
            Replace pitch tier
            selectObject: .manip2
            .ch2_new = Get resynthesis (overlap-add)
            removeObject: .manip2, .tier2, .ch2
            
            # Combine back to stereo
            selectObject: .ch1_new
            plusObject: .ch2_new
            .stereo_new = Combine to stereo
            removeObject: .ch1_new, .ch2_new, .seg_copy
            .seg_copy = .stereo_new
        endif
    endif
    
    .result = .seg_copy
endproc

procedure microscope: .seg, .factor, .preserve_pitch
    # Time-stretch the segment (like examining under a microscope)
    
    selectObject: .seg
    .seg_channels = Get number of channels
    
    if .preserve_pitch
        # Manipulation only works on mono - process stereo channels separately
        if .seg_channels = 2
            # Extract channels
            selectObject: .seg
            .ch1 = Extract one channel: 1
            selectObject: .seg
            .ch2 = Extract one channel: 2
            
            # Process channel 1
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
            
            # Process channel 2
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
            
            # Combine to stereo
            selectObject: .ch1_new
            plusObject: .ch2_new
            .result = Combine to stereo
            removeObject: .ch1_new, .ch2_new
        else
            # Mono processing
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
        # Simple PSOLA
        selectObject: .seg
        .result = To Sound (PSOLA): 75, 600, 1/.factor, 1.0
    endif
endproc

procedure analyzeContext: .snd, .time, .window_len
    # Analyze local acoustic context around a time point
    # Returns normalized intensity and pause detection
    
    selectObject: .snd
    
    # Extract analysis window
    .t_start = max(xmin, .time - .window_len)
    .t_end = min(xmax, .time + .window_len / 2)
    .window = Extract part: .t_start, .t_end, "rectangular", 1, "no"
    
    # Get intensity
    .intens = To Intensity: 100, 0, "yes"
    .mean_intens = Get mean: 0, 0, "dB"
    
    # Normalize to 0-1 range (assuming typical speech/music range 40-80 dB)
    .intensity = (.mean_intens - 40) / 40
    if .intensity < 0
        .intensity = 0
    elsif .intensity > 1
        .intensity = 1
    endif
    
    # Detect pause before (simple energy-based)
    .pre_start = max(xmin, .time - .window_len * 2)
    .pre_end = .time - .window_len / 4
    
    if .pre_end > .pre_start
        selectObject: .snd
        .pre_window = Extract part: .pre_start, .pre_end, "rectangular", 1, "no"
        .pre_intens = To Intensity: 100, 0, "yes"
        .pre_mean = Get mean: 0, 0, "dB"
        
        # Pause if pre-context is significantly quieter
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