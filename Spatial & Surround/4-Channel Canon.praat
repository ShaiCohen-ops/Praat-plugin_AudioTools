# ============================================================
# Praat AudioTools - 4-Channel_Canon.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   4-Channel Canon Generator - creates a musical canon effect
#   with 4 pitch-shifted voices on separate channels.
#
# Changelog v0.2:
#   - Added time delays for true canon effect
#   - Added fade in/out to prevent clicks
#   - Added presets
#   - Added visualization
#   - Proper 4-channel output
# ============================================================

form 4-Channel Canon Settings
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Canon (unison, staggered)"
        option: "Octave Stack"
        option: "Perfect Fifths"
        option: "Major Chord"
        option: "Minor Chord"
        option: "Cluster (close intervals)"
        option: "Wide Spread"
        option: "Accelerando Canon"
        option: "Reverse Canon"
    
    comment === Pitch shift (percent, + = higher, - = lower) ===
    real Shift_percent_1 0
    real Shift_percent_2 6.0
    real Shift_percent_3 12.0
    real Shift_percent_4 -5.5
    
    comment === Canon delays (seconds) ===
    real Delay_1 0.0
    real Delay_2 0.3
    real Delay_3 0.6
    real Delay_4 0.9
    
    comment === Settings ===
    positive Resample_frequency 44100
    real Fade_time 0.01
    
    comment === Output ===
    optionmenu Output_format: 1
        option: "4 channels (quadraphonic)"
        option: "2 stereo pairs"
        option: "Stereo mix (L: V1+V2, R: V3+V4)"
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Canon (unison, staggered entries)
    shift_percent_1 = 0
    shift_percent_2 = 0
    shift_percent_3 = 0
    shift_percent_4 = 0
    delay_1 = 0.0
    delay_2 = 0.5
    delay_3 = 1.0
    delay_4 = 1.5
    presetName$ = "Classic"
elsif preset = 3
    # Octave Stack (+12, 0, -12, -24 semitones)
    shift_percent_1 = 100 * (2^(12/12) - 1)
    shift_percent_2 = 0
    shift_percent_3 = 100 * (2^(-12/12) - 1)
    shift_percent_4 = 100 * (2^(-24/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    presetName$ = "Octaves"
elsif preset = 4
    # Perfect Fifths (0, +7, +14, +21 semitones)
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(7/12) - 1)
    shift_percent_3 = 100 * (2^(14/12) - 1)
    shift_percent_4 = 100 * (2^(21/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.3
    delay_3 = 0.6
    delay_4 = 0.9
    presetName$ = "Fifths"
elsif preset = 5
    # Major Chord (root, +4, +7, +12 semitones)
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(4/12) - 1)
    shift_percent_3 = 100 * (2^(7/12) - 1)
    shift_percent_4 = 100 * (2^(12/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    presetName$ = "Major"
elsif preset = 6
    # Minor Chord (root, +3, +7, +12 semitones)
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(3/12) - 1)
    shift_percent_3 = 100 * (2^(7/12) - 1)
    shift_percent_4 = 100 * (2^(12/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    presetName$ = "Minor"
elsif preset = 7
    # Cluster (0, +1, +2, +3 semitones)
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(1/12) - 1)
    shift_percent_3 = 100 * (2^(2/12) - 1)
    shift_percent_4 = 100 * (2^(3/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    presetName$ = "Cluster"
elsif preset = 8
    # Wide Spread (-12, -5, +7, +19 semitones)
    shift_percent_1 = 100 * (2^(-12/12) - 1)
    shift_percent_2 = 100 * (2^(-5/12) - 1)
    shift_percent_3 = 100 * (2^(7/12) - 1)
    shift_percent_4 = 100 * (2^(19/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.4
    delay_3 = 0.8
    delay_4 = 1.2
    presetName$ = "Wide"
elsif preset = 9
    # Accelerando Canon (same pitch, decreasing delays)
    shift_percent_1 = 0
    shift_percent_2 = 0
    shift_percent_3 = 0
    shift_percent_4 = 0
    delay_1 = 0.0
    delay_2 = 0.8
    delay_3 = 1.2
    delay_4 = 1.4
    presetName$ = "Accel"
elsif preset = 10
    # Reverse Canon (high to low, last to first)
    shift_percent_1 = 100 * (2^(12/12) - 1)
    shift_percent_2 = 100 * (2^(5/12) - 1)
    shift_percent_3 = 0
    shift_percent_4 = 100 * (2^(-7/12) - 1)
    delay_1 = 0.9
    delay_2 = 0.6
    delay_3 = 0.3
    delay_4 = 0.0
    presetName$ = "Reverse"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration

# === Create Base Mono ===
selectObject: originalID
Copy: "base_work"
baseWorkID = selected("Sound")
Convert to mono
monoID = selected("Sound")
Resample: resample_frequency, 50
Rename: "base_resampled"
baseDur = Get total duration

# Clean up intermediate objects immediately
removeObject: baseWorkID, monoID

# === Calculate shift rates ===
shift_rate_1 = resample_frequency * (1 + (shift_percent_1/100))
shift_rate_2 = resample_frequency * (1 + (shift_percent_2/100))
shift_rate_3 = resample_frequency * (1 + (shift_percent_3/100))
shift_rate_4 = resample_frequency * (1 + (shift_percent_4/100))

# === Create 4 pitched versions ===
select Sound base_resampled
Copy: "v1_work"
v1_work = selected("Sound")
Override sampling frequency: shift_rate_1
Resample: resample_frequency, 50
Rename: "voice_1"
v1_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v1_dur, -fade_time, "yes"
endif
removeObject: v1_work

select Sound base_resampled
Copy: "v2_work"
v2_work = selected("Sound")
Override sampling frequency: shift_rate_2
Resample: resample_frequency, 50
Rename: "voice_2"
v2_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v2_dur, -fade_time, "yes"
endif
removeObject: v2_work

select Sound base_resampled
Copy: "v3_work"
v3_work = selected("Sound")
Override sampling frequency: shift_rate_3
Resample: resample_frequency, 50
Rename: "voice_3"
v3_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v3_dur, -fade_time, "yes"
endif
removeObject: v3_work

select Sound base_resampled
Copy: "v4_work"
v4_work = selected("Sound")
Override sampling frequency: shift_rate_4
Resample: resample_frequency, 50
Rename: "voice_4"
v4_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v4_dur, -fade_time, "yes"
endif
removeObject: v4_work

# === Calculate output duration ===
end1 = delay_1 + v1_dur
end2 = delay_2 + v2_dur
end3 = delay_3 + v3_dur
end4 = delay_4 + v4_dur
maxEnd = max(end1, max(end2, max(end3, end4)))
outputDur = maxEnd + 0.05

# === Create 4 output channel buffers ===
Create Sound from formula: "ch1", 1, 0, outputDur, resample_frequency, "0"
ch1 = selected("Sound")
Create Sound from formula: "ch2", 1, 0, outputDur, resample_frequency, "0"
ch2 = selected("Sound")
Create Sound from formula: "ch3", 1, 0, outputDur, resample_frequency, "0"
ch3 = selected("Sound")
Create Sound from formula: "ch4", 1, 0, outputDur, resample_frequency, "0"
ch4 = selected("Sound")

# === Place each voice in its channel with delay ===
selectObject: ch1
Formula (part): delay_1, delay_1 + v1_dur, 1, 1, "Sound_voice_1(x - 'delay_1')"

selectObject: ch2
Formula (part): delay_2, delay_2 + v2_dur, 1, 1, "Sound_voice_2(x - 'delay_2')"

selectObject: ch3
Formula (part): delay_3, delay_3 + v3_dur, 1, 1, "Sound_voice_3(x - 'delay_3')"

selectObject: ch4
Formula (part): delay_4, delay_4 + v4_dur, 1, 1, "Sound_voice_4(x - 'delay_4')"

# === Combine based on output format ===
if output_format = 1
    # 4 channels (quadraphonic)
    selectObject: ch1, ch2
    Combine to stereo
    Rename: "pair_12"
    pair12 = selected("Sound")
    
    selectObject: ch3, ch4
    Combine to stereo
    Rename: "pair_34"
    pair34 = selected("Sound")
    
    # Combine both stereo pairs into 4-channel
    selectObject: pair12, pair34
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon4ch_" + presetName$
    result = selected("Sound")
    
    removeObject: pair12, pair34
    formatName$ = "4-channel"

elsif output_format = 2
    # 2 stereo pairs
    selectObject: ch1, ch2
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon_pair1_" + presetName$
    result = selected("Sound")
    
    selectObject: ch3, ch4
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon_pair2_" + presetName$
    result2 = selected("Sound")
    
    formatName$ = "2 stereo pairs"

else
    # Stereo mix (L: V1+V2, R: V3+V4)
    selectObject: ch1
    Formula: "self + Sound_ch2(x)"
    Rename: "left_mix"
    leftMix = selected("Sound")
    
    selectObject: ch3
    Formula: "self + Sound_ch4(x)"
    Rename: "right_mix"
    rightMix = selected("Sound")
    
    selectObject: leftMix, rightMix
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon_stereo_" + presetName$
    result = selected("Sound")
    
    removeObject: leftMix, rightMix
    formatName$ = "stereo mix"
endif

# === Info ===
writeInfoLine: "=== 4-Channel Canon ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Output: ", formatName$
appendInfoLine: ""

# Convert percent to semitones for display
semi1 = 12 * ln(1 + shift_percent_1/100) / ln(2)
semi2 = 12 * ln(1 + shift_percent_2/100) / ln(2)
semi3 = 12 * ln(1 + shift_percent_3/100) / ln(2)
semi4 = 12 * ln(1 + shift_percent_4/100) / ln(2)

appendInfoLine: "Voice 1 (Ch1): ", fixed$(semi1, 1), " st, delay ", fixed$(delay_1, 2), "s"
appendInfoLine: "Voice 2 (Ch2): ", fixed$(semi2, 1), " st, delay ", fixed$(delay_2, 2), "s"
appendInfoLine: "Voice 3 (Ch3): ", fixed$(semi3, 1), " st, delay ", fixed$(delay_3, 2), "s"
appendInfoLine: "Voice 4 (Ch4): ", fixed$(semi4, 1), " st, delay ", fixed$(delay_4, 2), "s"

# === Cleanup ===
select Sound base_resampled
plus Sound voice_1
plus Sound voice_2
plus Sound voice_3
plus Sound voice_4
Remove

if output_format <> 3
    selectObject: ch1, ch2, ch3, ch4
    Remove
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "4-Channel Canon: " + presetName$ + " (" + formatName$ + ") | " + originalName$
    
    # Canon diagram
    Select outer viewport: 0.5, 9.5, 0.8, 4.0
    Select inner viewport: 1.0, 9.0, 1.2, 3.7
    
    Axes: 0, outputDur, 0, 5
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, outputDur, 0, 5
    
    # Voice 1 / Channel 1
    Paint rectangle: "{0.3, 0.5, 0.8}", delay_1, delay_1 + v1_dur, 4.1, 4.9
    Colour: "Black"
    Draw rectangle: delay_1, delay_1 + v1_dur, 4.1, 4.9
    Font size: 8
    if semi1 >= 0
        Text: delay_1 + 0.05, "left", 4.5, "half", "Ch1: +" + fixed$(semi1, 0) + " st"
    else
        Text: delay_1 + 0.05, "left", 4.5, "half", "Ch1: " + fixed$(semi1, 0) + " st"
    endif
    
    # Voice 2 / Channel 2
    Paint rectangle: "{0.5, 0.7, 0.4}", delay_2, delay_2 + v2_dur, 3.1, 3.9
    Colour: "Black"
    Draw rectangle: delay_2, delay_2 + v2_dur, 3.1, 3.9
    if semi2 >= 0
        Text: delay_2 + 0.05, "left", 3.5, "half", "Ch2: +" + fixed$(semi2, 0) + " st"
    else
        Text: delay_2 + 0.05, "left", 3.5, "half", "Ch2: " + fixed$(semi2, 0) + " st"
    endif
    
    # Voice 3 / Channel 3
    Paint rectangle: "{0.8, 0.6, 0.3}", delay_3, delay_3 + v3_dur, 2.1, 2.9
    Colour: "Black"
    Draw rectangle: delay_3, delay_3 + v3_dur, 2.1, 2.9
    if semi3 >= 0
        Text: delay_3 + 0.05, "left", 2.5, "half", "Ch3: +" + fixed$(semi3, 0) + " st"
    else
        Text: delay_3 + 0.05, "left", 2.5, "half", "Ch3: " + fixed$(semi3, 0) + " st"
    endif
    
    # Voice 4 / Channel 4
    Paint rectangle: "{0.7, 0.4, 0.5}", delay_4, delay_4 + v4_dur, 1.1, 1.9
    Colour: "Black"
    Draw rectangle: delay_4, delay_4 + v4_dur, 1.1, 1.9
    if semi4 >= 0
        Text: delay_4 + 0.05, "left", 1.5, "half", "Ch4: +" + fixed$(semi4, 0) + " st"
    else
        Text: delay_4 + 0.05, "left", 1.5, "half", "Ch4: " + fixed$(semi4, 0) + " st"
    endif
    
    # Axes
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 4.2, 6.0
    Select inner viewport: 1.0, 9.0, 4.4, 5.8
    selectObject: result
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output duration: ", fixed$(outputDur, 2), "s"

if play_result
    selectObject: result
    Play
endif

selectObject: result
