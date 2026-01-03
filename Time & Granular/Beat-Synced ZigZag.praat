# ============================================================
# Praat AudioTools - Beat-Synced_ZigZag.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Beat-Synced ZigZag effect - reverses alternating time segments
#   synced to musical tempo. Creates rhythmic stuttering, tape-style
#   effects, and temporal disorientation. Segments can be bars,
#   beats, or subdivisions (8ths, 16ths, 32nds).
#
# Effect:
#   Original: [A→][B→][C→][D→]
#   ZigZag:   [←A][B→][←C][D→]
#
# Changelog v0.2:
#   - Added presets
#   - Added visualization
#   - Added play option
#   - Improved info output
# ============================================================

form Beat-Synced ZigZag
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Beat Stutter (quarter notes)
        option Fast Glitch (16ths)
        option Ultra Glitch (32nds)
        option Bar Flip (whole bars)
        option Eighth Note Bounce
        option Tail Only (from midpoint)
    
    comment === Processing Mode ===
    optionmenu Mode 1
        option Whole sound
        option Tail only (from midpoint)
    
    comment === Musical Timing ===
    optionmenu Bpm_mode 1
        option Auto-detect from duration
        option Manual BPM
    positive Number_of_bars 4
    positive Manual_bpm 120
    
    optionmenu Time_signature 1
        option 4/4
        option 3/4
        option 6/8
        option 5/4
    
    comment === Subdivision ===
    optionmenu Subdivision 2
        option Bars (whole bars)
        option Beats (quarter notes)
        option Eighth notes
        option Sixteenth notes
        option Thirty-second notes
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Beat Stutter
    mode = 1
    subdivision = 2
elsif preset = 3
    # Fast Glitch (16ths)
    mode = 1
    subdivision = 4
elsif preset = 4
    # Ultra Glitch (32nds)
    mode = 1
    subdivision = 5
elsif preset = 5
    # Bar Flip
    mode = 1
    subdivision = 1
elsif preset = 6
    # Eighth Note Bounce
    mode = 1
    subdivision = 3
elsif preset = 7
    # Tail Only
    mode = 2
    subdivision = 2
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
dur = Get total duration
start = Get start time
endTime = Get end time
sampleRate = Get sampling frequency

# === Determine Beats Per Bar ===
if time_signature = 1
    beats_per_bar = 4
    timeSig$ = "4/4"
elsif time_signature = 2
    beats_per_bar = 3
    timeSig$ = "3/4"
elsif time_signature = 3
    beats_per_bar = 6
    timeSig$ = "6/8"
elsif time_signature = 4
    beats_per_bar = 5
    timeSig$ = "5/4"
endif

# === Calculate BPM ===
if bpm_mode = 1
    # Auto-detect from duration
    total_beats = number_of_bars * beats_per_bar
    bpm = (total_beats / dur) * 60
    bpmSource$ = "auto"
else
    bpm = manual_bpm
    bpmSource$ = "manual"
endif

# === Calculate Segment Duration ===
beat_dur = 60 / bpm

if subdivision = 1
    seg_dur = beat_dur * beats_per_bar
    subdiv_name$ = "bars"
elsif subdivision = 2
    seg_dur = beat_dur
    subdiv_name$ = "beats"
elsif subdivision = 3
    seg_dur = beat_dur / 2
    subdiv_name$ = "8ths"
elsif subdivision = 4
    seg_dur = beat_dur / 4
    subdiv_name$ = "16ths"
elsif subdivision = 5
    seg_dur = beat_dur / 8
    subdiv_name$ = "32nds"
endif

# === Info ===
writeInfoLine: "=== Beat-Synced ZigZag ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "BPM: ", fixed$(bpm, 1), " (", bpmSource$, ") | Time sig: ", timeSig$
appendInfoLine: "Subdivision: ", subdiv_name$, " (", fixed$(seg_dur * 1000, 1), " ms)"
appendInfoLine: ""

# === Determine Processing Range ===
if mode = 1
    # Whole sound
    process_start = start
    num_segs = floor(dur / seg_dur)
    appendInfoLine: "Mode: Whole sound"
else
    # Tail only (from midpoint)
    process_start = start + (dur / 2)
    num_segs = floor((endTime - process_start) / seg_dur)
    appendInfoLine: "Mode: Tail only (from ", fixed$(process_start, 2), " s)"
endif

if num_segs < 1
    exitScript: "Segment duration too long for this sound"
endif

appendInfoLine: "Segments: ", num_segs, " (", floor(num_segs / 2), " reversed)"

# === Extract and Process Segments ===
appendInfoLine: ""
appendInfoLine: "Processing segments..."

for i to num_segs
    seg_start = process_start + (i - 1) * seg_dur
    seg_end = seg_start + seg_dur
    
    if seg_end > endTime
        seg_end = endTime
    endif
    
    selectObject: sound
    segment[i] = Extract part: seg_start, seg_end, "rectangular", 1, "no"
    
    # Reverse odd-numbered segments
    if i mod 2 = 1
        Reverse
    endif
endfor

# === Extract Head (for tail mode) ===
if mode = 2
    selectObject: sound
    head = Extract part: start, process_start, "rectangular", 1, "no"
endif

# === Concatenate ===
if mode = 1
    selectObject: segment[1]
    for i from 2 to num_segs
        plusObject: segment[i]
    endfor
else
    selectObject: head
    for i to num_segs
        plusObject: segment[i]
    endfor
endif

result = Concatenate
Rename: sound_name$ + "_zigzag_" + subdiv_name$

# === Cleanup Segments ===
if mode = 2
    removeObject: head
endif
for i to num_segs
    removeObject: segment[i]
endfor

# === Get Result Info ===
selectObject: result
resultDur = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "ZigZag: " + sound_name$ + " (" + subdiv_name$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.6, 7.6, 1.0, 2.4
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark segments on original
    Colour: "{0.8, 0.3, 0.3}"
    Axes: 0, dur, -1, 1
    for i to num_segs
        seg_start = process_start + (i - 1) * seg_dur - start
        if i mod 2 = 1
            # Reversed segment - mark with red
            Colour: "{1, 0.3, 0.3}"
        else
            Colour: "{0.3, 0.7, 0.3}"
        endif
        Draw line: seg_start, -0.9, seg_start, 0.9
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.6, 4.2
    Select inner viewport: 0.6, 7.6, 2.7, 4.1
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "ZigZag"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 4.4, 4.8
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "BPM: " + fixed$(bpm, 0) + " | " + subdiv_name$ + " | " + string$(num_segs) + " segments (" + string$(floor(num_segs/2)) + " reversed)"
    
    # Direction key
    Select outer viewport: 0, 8, 4.8, 5.1
    Colour: "{1, 0.3, 0.3}"
    Text: 0.3, "centre", 0.5, "half", "■ Reversed"
    Colour: "{0.3, 0.7, 0.3}"
    Text: 0.7, "centre", 0.5, "half", "■ Forward"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result