# ============================================================
# Praat AudioTools - Total_Serialism_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Total Serialism Machine - applies serial techniques to audio
#   composition. Uses a series (12-tone row or custom) to control
#   duration, source position, pitch, gain, and pan. Supports
#   inversion, retrograde, and rotation transformations.
#
# Changelog v0.2:
#   - Fixed Formula interpolation
#   - Fixed undefined preset$ variable
#   - Added visualization
# ============================================================

# ============================================================================
# CHECK INPUT
# ============================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

input_sound = selected("Sound")
input_name$ = selected$("Sound")
selectObject: input_sound
input_duration = Get total duration
input_sr = Get sampling frequency

# ============================================================================
# FORM LOOP
# ============================================================================

continue = 1
while continue

beginPause: "Total Serialism Machine"
    comment: "═══════════ PRESETS ═══════════"
    optionMenu: "preset", 1
        option: "Custom (manual settings)"
        option: "Pointillism (Webern-style)"
        option: "Moment Form (discrete blocks)"
        option: "Granular Texture (micro-events)"
        option: "Transformational (extreme ranges)"
        option: "Statistical Field (dense cloud)"
    comment: ""
    comment: "═══════════ SERIES ═══════════"
    integer: "series_length", 12
    optionMenu: "series_type", 3
        option: "Arithmetic (1..N)"
        option: "Permutation (custom)"
        option: "12-tone row (classic)"
    sentence: "series_values", "0,10,7,11,3,8,1,9,2,5,6,4"
    comment: ""
    comment: "═══════════ TRANSFORMATIONS ═══════════"
    boolean: "use_inversion", 0
    boolean: "use_retrograde", 0
    integer: "rotation", 0
    comment: ""
    comment: "═══════════ STRUCTURE ═══════════"
    integer: "num_events", 30
    positive: "min_event_ms", 200
    positive: "max_event_ms", 600
    positive: "gap_between_events_ms", 50
    comment: ""
    comment: "═══════════ PITCH RANGE ═══════════"
    integer: "min_pitch_cents", -200
    integer: "max_pitch_cents", 200
    comment: ""
    comment: "═══════════ OUTPUT ═══════════"
    boolean: "draw_visualization", 1
clicked = endPause: "Cancel", "Apply", "OK", 2

if clicked = 1
    # Cancel
    continue = 0
    exitScript()
elsif clicked = 2
    # Apply - process but keep form open
    continue = 1
elsif clicked = 3
    # OK - process and close
    continue = 0
endif

# ============================================================================
# GET PRESET NAME
# ============================================================================

if preset = 1
    preset$ = "Custom"
elsif preset = 2
    preset$ = "Pointillism"
elsif preset = 3
    preset$ = "Moment Form"
elsif preset = 4
    preset$ = "Granular"
elsif preset = 5
    preset$ = "Transformational"
else
    preset$ = "Statistical Field"
endif

# ============================================================================
# APPLY PRESETS
# ============================================================================

if preset = 2
    # Pointillism (Webern-style): sparse, short events, wide pitch range
    num_events = 24
    min_event_ms = 80
    max_event_ms = 250
    gap_between_events_ms = 150
    min_pitch_cents = -400
    max_pitch_cents = 400
    
elsif preset = 3
    # Moment Form: discrete blocks, moderate density
    num_events = 20
    min_event_ms = 300
    max_event_ms = 800
    gap_between_events_ms = 200
    min_pitch_cents = -300
    max_pitch_cents = 300
    
elsif preset = 4
    # Granular Texture: many micro-events
    num_events = 60
    min_event_ms = 50
    max_event_ms = 150
    gap_between_events_ms = 20
    min_pitch_cents = -200
    max_pitch_cents = 200
    
elsif preset = 5
    # Transformational: extreme parameter ranges
    num_events = 40
    min_event_ms = 100
    max_event_ms = 700
    gap_between_events_ms = 80
    min_pitch_cents = -600
    max_pitch_cents = 600
    use_inversion = 1
    use_retrograde = 1
    
elsif preset = 6
    # Statistical Field: dense overlapping cloud
    num_events = 80
    min_event_ms = 150
    max_event_ms = 500
    gap_between_events_ms = 10
    min_pitch_cents = -300
    max_pitch_cents = 300
endif

min_event_s = min_event_ms / 1000
max_event_s = max_event_ms / 1000
gap_s = gap_between_events_ms / 1000

# ============================================================================
# BUILD SERIES
# ============================================================================

@createSeries: series_type, series_length, series_values$
@applySerialTransformations: use_inversion, use_retrograde, rotation
@normalizeSeries

writeInfoLine: "=== Total Serialism Machine ==="
appendInfoLine: "Source: ", input_name$
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Series length: ", series_length
appendInfoLine: "Events: ", num_events
appendInfoLine: ""

# Show series
appendInfoLine: "Series: "
for i to series_length
    appendInfo: fixed$(normalized_series[i], 2)
    if i < series_length
        appendInfo: ", "
    endif
endfor
appendInfoLine: ""
appendInfoLine: ""

# ============================================================================
# GENERATE AND SORT EVENTS
# ============================================================================

for i to num_events
    series_i = ((i - 1) mod series_length) + 1
    norm_val = normalized_series[series_i]
    
    event_time[i] = norm_val
    event_index[i] = i
endfor

# Sort events by time
for i to num_events - 1
    for j from i + 1 to num_events
        if event_time[event_index[j]] < event_time[event_index[i]]
            temp = event_index[i]
            event_index[i] = event_index[j]
            event_index[j] = temp
        endif
    endfor
endfor

# ============================================================================
# STORE EVENT PARAMETERS FOR VISUALIZATION
# ============================================================================

for pos to num_events
    event_pitch[pos] = 0
    event_pan[pos] = 0.5
    event_dur_store[pos] = 0
endfor

# ============================================================================
# CREATE EVENTS IN TIME ORDER
# ============================================================================

appendInfoLine: "Processing events..."

for pos to num_events
    i = event_index[pos]
    
    series_i = ((i - 1) mod series_length) + 1
    norm_val = normalized_series[series_i]
    
    # PARAMETER 1: Event duration
    dur_series_i = ((i + 1 - 1) mod series_length) + 1
    dur_norm = normalized_series[dur_series_i]
    event_dur = min_event_s + dur_norm * (max_event_s - min_event_s)
    
    # PARAMETER 2: Source position
    source_series_i = ((i + 3 - 1) mod series_length) + 1
    source_norm = normalized_series[source_series_i]
    max_source_start = input_duration - event_dur
    if max_source_start < 0
        max_source_start = 0
    endif
    source_pos = source_norm * max_source_start
    
    # PARAMETER 3: Pitch shift
    pitch_series_i = ((i + 4 - 1) mod series_length) + 1
    pitch_norm = normalized_series[pitch_series_i]
    pitch_cents = min_pitch_cents + pitch_norm * (max_pitch_cents - min_pitch_cents)
    
    # PARAMETER 4: Gain
    gain_series_i = ((i + 6 - 1) mod series_length) + 1
    gain_norm = normalized_series[gain_series_i]
    gain_db = -12 + gain_norm * 12
    gain_linear = 10^(gain_db / 20)
    
    # PARAMETER 5: Pan position
    pan_series_i = ((i * 2 - 1) mod series_length) + 1
    pan_pos = normalized_series[pan_series_i]
    
    # Store for visualization
    event_pitch[pos] = pitch_cents
    event_pan[pos] = pan_pos
    event_dur_store[pos] = event_dur * 1000
    
    if pos mod 10 = 1 or pos = num_events
        appendInfoLine: "  Event ", pos, "/", num_events, ": pitch=", fixed$(pitch_cents, 0), "¢  pan=", fixed$(pan_pos, 2)
    endif
    
    # Extract segment
    selectObject: input_sound
    segment = Extract part: source_pos, source_pos + event_dur, "rectangular", 1, "no"
    
    # Convert to mono
    selectObject: segment
    n_ch = Get number of channels
    if n_ch = 2
        mono = Convert to mono
        removeObject: segment
        segment = mono
    endif
    
    # Apply gain
    selectObject: segment
    Formula: ~ self * gain_linear
    
    # Pitch shift
    if abs(pitch_cents) > 1
        pitch_ratio = 2^(pitch_cents / 1200)
        selectObject: segment
        new_sr = input_sr * pitch_ratio
        Override sampling frequency: new_sr
        resampled = Resample: input_sr, 50
        removeObject: segment
        segment = resampled
    endif
    
    # Fade
    selectObject: segment
    seg_dur = Get total duration
    fade = 0.005
    Formula: ~ self * (if x < fade then x / fade else (if x > seg_dur - fade then (seg_dur - x) / fade else 1 fi) fi)
    
    # STEREO PANNING
    left_gain = sqrt(1 - pan_pos)
    right_gain = sqrt(pan_pos)
    
    selectObject: segment
    stereo = Convert to stereo
    removeObject: segment
    segment = stereo
    
    selectObject: segment
    Formula (part): 0, 0, 1, 1, ~ self * left_gain
    Formula (part): 0, 0, 2, 2, ~ self * right_gain
    
    # Store segment
    segment_obj[pos] = segment
endfor

# ============================================================================
# CONCATENATE ALL EVENTS
# ============================================================================

appendInfoLine: ""
appendInfoLine: "Concatenating..."

# Start with first segment
selectObject: segment_obj[1]
result = Copy: "serialist_result"

# Concatenate remaining segments with gaps
for pos from 2 to num_events
    # Create stereo silence gap
    Create Sound from formula: "gap", 2, 0, gap_s, input_sr, "0"
    gap = selected("Sound")
    
    # Append gap
    selectObject: result, gap
    old_result = result
    result = Concatenate
    removeObject: old_result, gap
    
    # Append next segment
    selectObject: result, segment_obj[pos]
    old_result = result
    result = Concatenate
    removeObject: old_result
endfor

# Cleanup segments
for i to num_events
    removeObject: segment_obj[i]
endfor

# ============================================================================
# FINALIZE
# ============================================================================

selectObject: result
Scale peak: 0.99
Rename: input_name$ + "_serial_" + preset$

final_dur = Get total duration

# ============================================================================
# VISUALIZATION
# ============================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Total Serialism: " + input_name$ + " (" + preset$ + ")"
    
    # Result waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: result
    Colour: "{0.5, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Series visualization
    Select outer viewport: 0, 4, 2.2, 3.6
    Select inner viewport: 0.6, 3.8, 2.4, 3.5
    
    Axes: 0, series_length + 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, series_length + 1, 0, 1.1
    
    for s to series_length
        barColor$ = "{0.4, 0.6, 0.8}"
        Paint rectangle: barColor$, s - 0.35, s + 0.35, 0, normalized_series[s]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Value"
    Text bottom: "yes", "Series position"
    
    # Pitch distribution
    Select outer viewport: 4, 8, 2.2, 3.6
    Select inner viewport: 4.4, 7.6, 2.4, 3.5
    
    maxPitch = max_pitch_cents
    minPitch = min_pitch_cents
    pitchRange = maxPitch - minPitch
    if pitchRange = 0
        pitchRange = 1
    endif
    
    Axes: 0, num_events + 1, minPitch - 50, maxPitch + 50
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, num_events + 1, minPitch - 50, maxPitch + 50
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, num_events + 1, 0
    Solid line
    
    # Draw pitch points
    Colour: "{0.7, 0.4, 0.4}"
    for ev to num_events
        Paint circle (mm): "{0.7, 0.4, 0.4}", ev, event_pitch[ev], 1
        if ev > 1
            Draw line: ev - 1, event_pitch[ev - 1], ev, event_pitch[ev]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (¢)"
    Text bottom: "yes", "Event #"
    
    # Pan distribution
    Select outer viewport: 0, 4, 3.8, 5.2
    Select inner viewport: 0.6, 3.8, 4.0, 5.1
    
    Axes: 0, num_events + 1, -0.1, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, num_events + 1, -0.1, 1.1
    
    # Center line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0.5, num_events + 1, 0.5
    Solid line
    
    # Draw pan points
    for ev to num_events
        # Color: left=blue, right=red
        panVal = event_pan[ev]
        r = panVal
        b = 1 - panVal
        panColor$ = "{" + fixed$(r, 2) + ", 0.3, " + fixed$(b, 2) + "}"
        Paint circle (mm): panColor$, ev, panVal, 1.2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan (L-R)"
    Text bottom: "yes", "Event #"
    
    # Duration distribution
    Select outer viewport: 4, 8, 3.8, 5.2
    Select inner viewport: 4.4, 7.6, 4.0, 5.1
    
    Axes: 0, num_events + 1, 0, max_event_ms * 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, num_events + 1, 0, max_event_ms * 1.1
    
    for ev to num_events
        barColor$ = "{0.5, 0.7, 0.5}"
        Paint rectangle: barColor$, ev - 0.3, ev + 0.3, 0, event_dur_store[ev]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dur (ms)"
    Text bottom: "yes", "Event #"

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(final_dur, 2), " s"
appendInfoLine: ""
appendInfoLine: "Playing..."

selectObject: result
Play

selectObject: result

# End of while loop
endwhile

# ============================================================================
# PROCEDURES
# ============================================================================

procedure createSeries: .type, .length, .values$
    for .i to .length
        base_series[.i] = .i
    endfor
    
    if .type = 1
        # Arithmetic: 1, 2, 3, ..., N
        for .i to .length
            base_series[.i] = .i
        endfor
    elsif .type = 2
        # Permutation: parse user values
        @parseSeriesValues: .values$, .length
    elsif .type = 3
        # 12-tone row (classic example)
        if .length = 12
            base_series[1] = 0
            base_series[2] = 10
            base_series[3] = 7
            base_series[4] = 11
            base_series[5] = 3
            base_series[6] = 8
            base_series[7] = 1
            base_series[8] = 9
            base_series[9] = 2
            base_series[10] = 5
            base_series[11] = 6
            base_series[12] = 4
        else
            for .i to .length
                base_series[.i] = .i
            endfor
        endif
    endif
endproc

procedure parseSeriesValues: .values$, .length
    .count = 0
    .remaining$ = .values$ + ","
    
    while length(.remaining$) > 0 and .count < .length
        .comma_pos = index(.remaining$, ",")
        if .comma_pos > 0
            .count += 1
            .value$ = left$(.remaining$, .comma_pos - 1)
            .value$ = replace$(.value$, " ", "", 0)
            
            if .value$ <> ""
                base_series[.count] = number(.value$)
            else
                base_series[.count] = .count
            endif
            
            .remaining$ = right$(.remaining$, length(.remaining$) - .comma_pos)
        else
            .remaining$ = ""
        endif
    endwhile
    
    for .i from .count + 1 to .length
        base_series[.i] = .i
    endfor
endproc

procedure applySerialTransformations: .invert, .retro, .rotate
    for .i to series_length
        working_series[.i] = base_series[.i]
    endfor
    
    if .invert
        .min = working_series[1]
        .max = working_series[1]
        for .i from 2 to series_length
            if working_series[.i] < .min
                .min = working_series[.i]
            endif
            if working_series[.i] > .max
                .max = working_series[.i]
            endif
        endfor
        
        for .i to series_length
            working_series[.i] = .min + .max - working_series[.i]
        endfor
    endif
    
    if .retro
        for .i to series_length
            temp_series[.i] = working_series[series_length - .i + 1]
        endfor
        for .i to series_length
            working_series[.i] = temp_series[.i]
        endfor
    endif
    
    .rot = .rotate mod series_length
    if .rot <> 0
        for .i to series_length
            .source_i = ((.i - 1 - .rot) mod series_length) + 1
            if .source_i < 1
                .source_i += series_length
            endif
            temp_series[.i] = working_series[.source_i]
        endfor
        for .i to series_length
            working_series[.i] = temp_series[.i]
        endfor
    endif
    
    for .i to series_length
        base_series[.i] = working_series[.i]
    endfor
endproc

procedure normalizeSeries
    .min = base_series[1]
    .max = base_series[1]
    
    for .i from 2 to series_length
        if base_series[.i] < .min
            .min = base_series[.i]
        endif
        if base_series[.i] > .max
            .max = base_series[.i]
        endif
    endfor
    
    .range = .max - .min
    if .range = 0
        .range = 1
    endif
    
    for .i to series_length
        normalized_series[.i] = (base_series[.i] - .min) / .range
    endfor
endproc