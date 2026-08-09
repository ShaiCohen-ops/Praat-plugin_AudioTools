# ============================================================
# Praat AudioTools - Beat-Synced_ZigZag.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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
# Changelog v0.4:
#   DSP / timing / correctness:
#   - FIXED Tail mode concatenation order. Praat concatenates selected
#     Sounds in Object-list order, not selection order. The head is now
#     created before processed segments so output order is guaranteed:
#       head -> zigzag segments -> trailing remainder.
#   - FIXED 6/8 timing. BPM is treated as quarter-note BPM throughout;
#     therefore one 6/8 bar contains 3 quarter-note units, not 6.
#   - Tail mode is now beat/subdivision-synced: processing starts at the
#     first subdivision boundary at or after the midpoint.
#   - Renamed misleading "Auto-detect from duration" to "Fit bars to
#     duration": this mode derives tempo from duration + declared bar count;
#     it does not detect beats from audio content.
#   - Added minimum segment-duration and maximum segment-count guards.
#   - FIXED reversed-segment count in Info/visualization for odd counts
#     (odd-numbered segments are reversed, so count is ceiling(N/2)).
#   - Visualization title/legend/key now set explicit normalized Axes so
#     text placement cannot inherit stale axes from another panel.
#   - Trailing-duration arithmetic is clamped against floating-point drift.
#
# Changelog v0.3:
#   - Fix: trailing partial segment was silently dropped, shortening the
#     result. Now preserved (appended un-reversed) by default via toggle.
#   - Fix: visualization marked segment boundaries with lines but the
#     legend named regions; now shades reversed/forward regions as a strip.
#   - Removed a dead colour assignment in the viz marker block.
#
# Changelog v0.2:
#   - Added presets
#   - Added visualization
#   - Added play option
#   - Improved info output
# ============================================================

form Beat-Synced ZigZag v0.4
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
        option Tail only (quantized from midpoint)
    
    comment === Musical Timing ===
    optionmenu Bpm_mode 1
        option Fit bars to duration
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
    boolean Keep_trailing_audio 1
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

# === Determine Quarter-note Units Per Bar ===
# BPM is quarter-note BPM for all signatures. A 6/8 bar is therefore
# 3 quarter-note units long (six eighth notes), not 6 quarter notes.
if time_signature = 1
    quarter_notes_per_bar = 4
    timeSig$ = "4/4"
elsif time_signature = 2
    quarter_notes_per_bar = 3
    timeSig$ = "3/4"
elsif time_signature = 3
    quarter_notes_per_bar = 3
    timeSig$ = "6/8"
elsif time_signature = 4
    quarter_notes_per_bar = 5
    timeSig$ = "5/4"
endif

# === Calculate BPM ===
if bpm_mode = 1
    # Fit the declared number of bars exactly to the Sound duration.
    total_quarter_notes = number_of_bars * quarter_notes_per_bar
    bpm = (total_quarter_notes / dur) * 60
    bpmSource$ = "fit-to-duration"
else
    bpm = manual_bpm
    bpmSource$ = "manual"
endif

# === Calculate Segment Duration ===
quarter_dur = 60 / bpm

if subdivision = 1
    seg_dur = quarter_dur * quarter_notes_per_bar
    subdiv_name$ = "bars"
elsif subdivision = 2
    seg_dur = quarter_dur
    subdiv_name$ = "beats"
elsif subdivision = 3
    seg_dur = quarter_dur / 2
    subdiv_name$ = "8ths"
elsif subdivision = 4
    seg_dur = quarter_dur / 4
    subdiv_name$ = "16ths"
elsif subdivision = 5
    seg_dur = quarter_dur / 8
    subdiv_name$ = "32nds"
endif

# === Validate Derived Timing ===
minSegmentDur = 2 / sampleRate
if seg_dur < minSegmentDur
    exitScript: "Subdivision is shorter than two samples at this sampling rate. Lower the BPM or use a larger subdivision."
endif

# === Info ===
writeInfoLine: "=== Beat-Synced ZigZag ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "BPM (quarter-note): ", fixed$(bpm, 1), " (", bpmSource$, ") | Time sig: ", timeSig$
appendInfoLine: "Subdivision: ", subdiv_name$, " (", fixed$(seg_dur * 1000, 1), " ms)"
appendInfoLine: ""

# === Determine Processing Range ===
if mode = 1
    # Whole sound: grid begins at the Sound start.
    process_offset = 0
    process_start = start
    num_segs = floor(dur / seg_dur + 0.000000000001)
    appendInfoLine: "Mode: Whole sound"
else
    # Tail only: quantize the midpoint forward to the next subdivision
    # boundary on the grid anchored at the Sound start.
    midpoint_offset = dur / 2
    grid_index = ceiling(midpoint_offset / seg_dur - 0.000000000001)
    process_offset = min(dur, grid_index * seg_dur)
    process_start = start + process_offset
    num_segs = floor((dur - process_offset) / seg_dur + 0.000000000001)
    appendInfoLine: "Mode: Tail only (quantized start ", fixed$(process_offset, 3), " s)"
endif

if num_segs < 1
    exitScript: "No complete subdivision fits in the selected processing range"
endif
if num_segs > 10000
    exitScript: "This setting would create more than 10000 segments. Lower the BPM or use a larger subdivision."
endif

reversed_count = ceiling(num_segs / 2)
appendInfoLine: "Segments: ", num_segs, " (", reversed_count, " reversed)"

# === Extract Head First (required for Praat concatenation order) ===
# Sounds: Concatenate uses Object-list order, not selection order.
# Creating the head before the processed segments guarantees that Tail mode
# produces: head -> segment[1..N] -> optional trailing remainder.
if mode = 2
    selectObject: sound
    head = Extract part: start, process_start, "rectangular", 1, "no"
endif

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

# === Extract Trailing Remainder (preserve audio) ===
has_tail = 0
covered_end = process_start + num_segs * seg_dur
tail_duration = max(0, endTime - covered_end)
tail_samples = round(tail_duration * sampleRate)
if keep_trailing_audio and tail_samples >= 2
    selectObject: sound
    tailSeg = Extract part: covered_end, endTime, "rectangular", 1, "no"
    has_tail = 1
    appendInfoLine: "Trailing remainder kept: ", fixed$(tail_duration * 1000, 1), " ms (forward)"
elsif tail_samples >= 2
    appendInfoLine: "Trailing remainder dropped: ", fixed$(tail_duration * 1000, 1), " ms"
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

if has_tail
    plusObject: tailSeg
endif

result = Concatenate
Rename: sound_name$ + "_zigzag_" + subdiv_name$

# === Cleanup Segments ===
if mode = 2
    removeObject: head
endif
if has_tail
    removeObject: tailSeg
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
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.5, "half", "ZigZag: " + sound_name$ + " (" + subdiv_name$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.6, 7.6, 1.0, 2.4
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark reversed/forward segment regions as a bottom strip
    Axes: 0, dur, -1, 1
    for i to num_segs
        rseg_start = process_start + (i - 1) * seg_dur - start
        rseg_end = rseg_start + seg_dur
        if rseg_end > dur
            rseg_end = dur
        endif
        if i mod 2 = 1
            Paint rectangle: {1, 0.55, 0.55}, rseg_start, rseg_end, -1.0, -0.80
        else
            Paint rectangle: {0.55, 0.8, 0.55}, rseg_start, rseg_end, -1.0, -0.80
        endif
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
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.5, "half", "BPM: " + fixed$(bpm, 0) + " | " + subdiv_name$ + " | " + string$(num_segs) + " segments (" + string$(reversed_count) + " reversed)"
    
    # Direction key
    Select outer viewport: 0, 8, 4.8, 5.1
    Axes: 0, 1, 0, 1
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