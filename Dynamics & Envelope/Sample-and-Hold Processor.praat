# ============================================================
# Praat AudioTools - Sample-and-Hold Processor.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sample-and-Hold Audio Processor
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# Praat AudioTools - Sample-and-Hold Processor.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Modified
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sample-and-Hold Audio Processor
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Modifications (v0.3):
#   - Fixed pitch-gated mode: analyzes full sound once, queries per segment
#   - Optimized median calculation: uses TableOfReal instead of bubble sort
#   - Added visual output: gate pattern overlaid on amplitude envelope
#   - Compact form layout
# ============================================================

form Sample-and-Hold Processor
    optionmenu control_type 1
        option Binary (alternating)
        option Intensity-based
        option Amplitude Modulation
        option Pitch-gated
        option Custom Pattern
        option Spectral Centroid Gate
    positive sample_period 0.02
    real gate_threshold 0.5
    comment Mode parameters: intensity(dB,0=auto) / mod(Hz,depth) / pitch(Hz) / centroid(Hz)
    real intensity_threshold 50
    real mod_frequency 2
    real mod_depth 1.0
    real pitch_threshold 100
    real centroid_threshold 1000
    sentence pattern 1 0 1 1 0 1 0 1
    real mute_amplitude 0.0
    boolean draw_visualization 1
    boolean show_info 1
endform

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")
duration = Get total duration
sample_rate = Get sampling frequency
num_channels = Get number of channels
num_intervals = ceiling(duration / sample_period)

# === INFO HEADER ===
if show_info
    writeInfoLine: "Sample-and-Hold Processor v0.3"
    appendInfoLine: "=============================="
    appendInfoLine: "Input: ", sound_name$, " (", fixed$(duration, 3), "s, ", num_intervals, " intervals)"
    appendInfoLine: ""
endif

# === PARSE CUSTOM PATTERN ===
pattern_length = 0
if control_type = 5
    pattern$ = replace_regex$(pattern$, "^[ \t]+|[ \t]+$", "", 0)
    if length(pattern$) = 0
        exitScript: "ERROR: Custom pattern is empty."
    endif
    pattern$ = pattern$ + " "
    @countPatternValues: pattern$
    pattern_length = countPatternValues.count
    if pattern_length = 0
        exitScript: "ERROR: No valid pattern values found."
    endif
endif

# === PRE-ANALYSIS FOR INTENSIVE MODES ===

# Intensity: auto-threshold via TableOfReal
if control_type = 2 and intensity_threshold = 0
    selectObject: sound
    Create TableOfReal: "int_vals", num_intervals, 1
    table_id = selected("TableOfReal")
    
    for i from 1 to num_intervals
        t_start = (i - 1) * sample_period
        t_end = min(t_start + sample_period, duration)
        selectObject: sound
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        int_val = Get intensity (dB)
        if int_val = undefined
            int_val = -100
        endif
        selectObject: table_id
        Set value: i, 1, int_val
        removeObject: temp_seg
    endfor
    
    selectObject: table_id
    Sort by column: 1, 0
    median_idx = max(1, floor(num_intervals / 2))
    intensity_threshold = Get value: median_idx, 1
    
    if show_info
        appendInfoLine: "Auto intensity threshold: ", fixed$(intensity_threshold, 1), " dB (median)"
    endif
    removeObject: table_id
endif

# Pitch: analyze FULL sound once (avoids short-segment pitch floor issue)
if control_type = 4
    selectObject: sound
    To Pitch: 0.01, 75, 600
    pitch_object = selected("Pitch")
    if show_info
        appendInfoLine: "Pitch analysis: floor=75Hz, ceiling=600Hz, threshold=", pitch_threshold, "Hz"
    endif
endif

# === COPY OUTPUT SOUND ===
selectObject: sound
output_sound = Copy: sound_name$ + "_SH"

# === STORAGE FOR VISUALIZATION ===
for i from 0 to num_intervals - 1
    control_values[i] = 0
endfor

pass_count = 0
mute_count = 0

# === MAIN PROCESSING LOOP ===
for i from 0 to num_intervals - 1
    t_start = i * sample_period
    t_end = min(t_start + sample_period, duration)
    t_mid = (t_start + t_end) / 2
    
    selectObject: sound
    
    if control_type = 1
        # Binary alternating
        control_value = if i mod 2 = 0 then 1 else 0 fi
        
    elsif control_type = 2
        # Intensity-based
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        int_val = Get intensity (dB)
        if int_val = undefined
            int_val = -100
        endif
        control_value = if int_val > intensity_threshold then 1 else 0 fi
        removeObject: temp_seg
        
    elsif control_type = 3
        # Amplitude modulation
        phase = 2 * pi * mod_frequency * t_start
        sine_val = (sin(phase) + 1) / 2
        control_value = 1 - (mod_depth * (1 - sine_val))
        
    elsif control_type = 4
        # Pitch-gated (query pre-computed pitch object)
        selectObject: pitch_object
        pitch_val = Get value at time: t_mid, "Hertz", "linear"
        control_value = if pitch_val <> undefined and pitch_val > pitch_threshold then 1 else 0 fi
        
    elsif control_type = 5
        # Custom pattern
        pattern_idx = (i mod pattern_length) + 1
        @getPatternValue: pattern$, pattern_idx
        control_value = getPatternValue.value
        
    elsif control_type = 6
        # Spectral centroid
        Extract part: t_start, t_end, "rectangular", 1, "no"
        temp_seg = selected("Sound")
        To Spectrum: "yes"
        spectrum = selected("Spectrum")
        centroid = Get centre of gravity: 2
        control_value = if centroid <> undefined and centroid > centroid_threshold then 1 else 0 fi
        removeObject: spectrum, temp_seg
    endif
    
    control_values[i] = control_value
    
    # Statistics (skip for continuous AM)
    if control_type <> 3
        if control_value >= gate_threshold
            pass_count += 1
        else
            mute_count += 1
        endif
    endif
    
    # Apply to output
    selectObject: output_sound
    if control_type = 3
        amp_mult = control_value
    else
        amp_mult = if control_value >= gate_threshold then 1 else mute_amplitude fi
    endif
    Formula (part): t_start, t_end, 1, num_channels, "self * " + string$(amp_mult)
endfor

# === CLEANUP PRE-ANALYSIS OBJECTS ===
if control_type = 4
    removeObject: pitch_object
endif

# === STATISTICS ===
if show_info and control_type <> 3
    appendInfoLine: ""
    appendInfoLine: "Results: ", pass_count, " passed (", fixed$(100*pass_count/num_intervals, 1), "%), ",
    ... mute_count, " muted (", fixed$(100*mute_count/num_intervals, 1), "%)"
    
    if pass_count = num_intervals
        appendInfoLine: "WARNING: All segments passed - try adjusting threshold"
    elsif mute_count = num_intervals
        appendInfoLine: "WARNING: All segments muted - try adjusting threshold"
    endif
endif

# === VISUALIZATION ===
if draw_visualization
    Erase all
    
    # TOP: Original
    Select outer viewport: 0, 7, 0, 2.2
    selectObject: sound
    Draw: 0, 0, 0, 0, "no", "Curve"
    Text top: "yes", "Original: " + sound_name$
    
    # MIDDLE: Gate signal
    Select outer viewport: 0, 7, 2.2, 4
    Create Sound from formula: "gate", 1, 0, duration, 1000, "0"
    gate_sound = selected("Sound")
    
    for i from 0 to num_intervals - 1
        t_start = i * sample_period
        t_end = min(t_start + sample_period, duration)
        if control_type = 3
            gate_val = control_values[i]
        else
            gate_val = if control_values[i] >= gate_threshold then 1 else 0 fi
        endif
        Formula (part): t_start, t_end, 1, 1, string$(gate_val)
    endfor
    
    Draw: 0, 0, -0.1, 1.1, "no", "Curve"
    Text top: "yes", "Gate Signal"
    Marks left every: 1, 1, "yes", "yes", "no"
    removeObject: gate_sound
    
    # BOTTOM: Output
    Select outer viewport: 0, 7, 4, 6.2
    selectObject: output_sound
    Draw: 0, 0, 0, 0, "no", "Curve"
    Text top: "yes", "Output: " + sound_name$ + "_SH"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 0, 7, 0, 6.2
endif

# === FINALIZE ===
selectObject: output_sound

if show_info
    appendInfoLine: ""
    appendInfoLine: "Done! Output: ", sound_name$, "_SH"
endif

Play

# ============================================================
# PROCEDURES
# ============================================================

procedure countPatternValues: .pattern$
    .count = 0
    .temp$ = .pattern$
    repeat
        .space_pos = index_regex(.temp$, "[ \t]+")
        if .space_pos > 0
            .count += 1
            .temp$ = right$(.temp$, length(.temp$) - .space_pos)
            .temp$ = replace_regex$(.temp$, "^[ \t]+", "", 0)
        endif
    until .space_pos = 0 or length(.temp$) = 0
endproc

procedure getPatternValue: .pattern$, .index
    .current = 0
    .temp$ = .pattern$
    repeat
        .space_pos = index_regex(.temp$, "[ \t]+")
        if .space_pos > 0
            .current += 1
            .val_str$ = left$(.temp$, .space_pos - 1)
            if .current = .index
                .value = number(.val_str$)
                goto FOUND
            endif
            .temp$ = right$(.temp$, length(.temp$) - .space_pos)
            .temp$ = replace_regex$(.temp$, "^[ \t]+", "", 0)
        endif
    until .space_pos = 0
    .value = 0
    label FOUND
endproc