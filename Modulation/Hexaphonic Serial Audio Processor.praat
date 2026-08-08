# ============================================================
# Praat AudioTools - Hexaphonic Serial Audio Processor
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Six-row serial control processor for amplitude modulation, source
#   segment duration, stereo panning, and tape-speed transposition.
#   "Hexaphonic" refers to six independent 12-value control rows
#   (rate, depth, shape, duration, pan, speed), not six audio channels.
#
#   The source is intentionally collapsed to mono before serial
#   spatialization; the processor therefore always creates stereo output.
#
# Serial transformations:
#   P  = prime row
#   I  = complement inversion (11 - value)
#   R  = retrograde
#   RI = retrograde of the complement inversion
#
# Changelog v0.3:
#   - Fixed tape-speed sign: 0=-6 st, 6=0 st, 11=+5 st.
#   - Fixed non-zero input start times by processing a zero-based copy.
#   - Explicit mono source -> stereo serial panning semantics.
#   - Exact center pan at row value 6 with equal-power gains.
#   - Strict validation of control sequences (12 integers 0..11).
#   - Random preset can be reproduced with Random_seed.
#   - Repeats the 48-event serial cycle until the whole source is used.
#   - Visualization timeline follows actual output time after speed changes.
#   - Added attenuation-only Safety_peak and optional playback.
#   - Updated visualization to the AudioTools text/layout standard.
# ============================================================

form Hexaphonic Serial Audio Processor
    optionmenu Preset: 1
        option Custom
        option Classic Webern
        option Berg Symmetrical
        option Schoenberg Op.25
        option Chromatic Ascent
        option All-Interval
        option Pentatonic Serial
        option Whole-Tone Serial
        option Random Permutations
    comment === Six prime control sequences (12 integers 0..11) ===
    sentence Mod_rate_row 0 3 7 11 2 6 9 1 5 8 4 10
    sentence Mod_depth_row 5 9 2 11 0 7 3 10 1 6 8 4
    sentence Mod_shape_row 2 8 5 0 11 3 7 1 9 4 10 6
    sentence Duration_row 6 2 9 1 11 4 8 0 7 3 10 5
    sentence Panning_row 4 8 1 10 3 7 0 11 5 9 2 6
    sentence Speed_row 6 5 7 4 8 3 9 2 10 1 11 0
    comment === Parameter ranges ===
    positive Min_rate 0.5
    positive Max_rate 50
    positive Min_depth 0.05
    positive Max_depth 0.95
    positive Min_duration 0.1
    positive Max_duration 3.0
    boolean Perceptual_rate_scaling 1
    comment === Random preset ===
    integer Random_seed 0
    comment (0 = unpredictable; nonzero = reproducible Random Permutations)
    comment === Output ===
    real Safety_peak 0.99
    comment (0 disables; otherwise attenuation only)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")
selectObject: soundID
duration = Get total duration
sampling_frequency = Get sampling frequency
num_channels = Get number of channels
source_start = Get start time

if duration <= 0
    exitScript: "The selected Sound has no duration."
endif
if min_rate > max_rate
    exitScript: "Min_rate must be <= Max_rate."
endif
if min_depth > max_depth
    exitScript: "Min_depth must be <= Max_depth."
endif
if min_depth < 0 or max_depth > 1
    exitScript: "Depth range must stay within 0..1."
endif
if min_duration > max_duration
    exitScript: "Min_duration must be <= Max_duration."
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    mod_rate_row$ = "0 11 3 8 4 7 9 2 10 1 5 6"
    mod_depth_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    mod_shape_row$ = "0 3 6 9 1 4 7 10 2 5 8 11"
    duration_row$ = "5 6 4 7 3 8 2 9 1 10 0 11"
    panning_row$ = "6 5 7 4 8 3 9 2 10 1 11 0"
    speed_row$ = "6 6 6 5 7 5 7 6 6 6 6 6"
    presetName$ = "Webern"
elsif preset = 3
    mod_rate_row$ = "0 11 7 4 2 9 3 8 10 1 5 6"
    mod_depth_row$ = "5 10 2 7 11 1 8 4 9 0 6 3"
    mod_shape_row$ = "6 5 4 3 2 1 0 11 10 9 8 7"
    duration_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    panning_row$ = "0 2 4 6 8 10 11 9 7 5 3 1"
    speed_row$ = "6 7 5 8 4 9 3 10 2 11 1 0"
    presetName$ = "Berg"
elsif preset = 4
    mod_rate_row$ = "4 5 7 1 6 3 8 2 11 0 9 10"
    mod_depth_row$ = "0 6 5 11 10 4 3 9 8 2 1 7"
    mod_shape_row$ = "8 10 11 1 3 4 6 7 9 0 2 5"
    duration_row$ = "3 9 2 8 1 7 0 6 11 5 10 4"
    panning_row$ = "2 8 4 10 0 6 11 5 9 3 7 1"
    speed_row$ = "5 6 7 6 5 7 6 5 6 7 5 6"
    presetName$ = "Schoenberg"
elsif preset = 5
    mod_rate_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    mod_depth_row$ = "11 10 9 8 7 6 5 4 3 2 1 0"
    mod_shape_row$ = "0 2 4 6 8 10 1 3 5 7 9 11"
    duration_row$ = "6 7 5 8 4 9 3 10 2 11 1 0"
    panning_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    speed_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    presetName$ = "Chromatic"
elsif preset = 6
    mod_rate_row$ = "0 1 4 2 9 5 11 3 8 10 7 6"
    mod_depth_row$ = "0 3 6 9 1 4 7 10 2 5 8 11"
    mod_shape_row$ = "0 5 10 3 8 1 6 11 4 9 2 7"
    duration_row$ = "2 7 1 8 0 9 11 4 10 3 5 6"
    panning_row$ = "1 5 9 2 6 10 3 7 11 4 8 0"
    speed_row$ = "4 8 2 10 1 7 0 9 3 11 5 6"
    presetName$ = "AllInterval"
elsif preset = 7
    mod_rate_row$ = "0 2 4 7 9 1 3 5 8 10 6 11"
    mod_depth_row$ = "0 5 7 2 9 4 11 6 1 8 3 10"
    mod_shape_row$ = "0 7 2 9 4 11 6 1 8 3 10 5"
    duration_row$ = "1 6 3 8 5 10 7 2 9 4 11 0"
    panning_row$ = "0 7 2 9 4 11 6 1 8 3 10 5"
    speed_row$ = "6 5 7 6 5 7 6 5 7 6 5 7"
    presetName$ = "Pentatonic"
elsif preset = 8
    mod_rate_row$ = "0 2 4 6 8 10 1 3 5 7 9 11"
    mod_depth_row$ = "1 3 5 7 9 11 0 2 4 6 8 10"
    mod_shape_row$ = "0 6 1 7 2 8 3 9 4 10 5 11"
    duration_row$ = "5 11 4 10 3 9 2 8 1 7 0 6"
    panning_row$ = "0 6 1 7 2 8 3 9 4 10 5 11"
    speed_row$ = "6 8 4 10 2 8 4 10 2 8 4 10"
    presetName$ = "WholeTone"
elsif preset = 9
    presetName$ = "Random"
    if random_seed <> 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
    endif

    mod_rate_row$ = ""
    mod_depth_row$ = ""
    mod_shape_row$ = ""
    duration_row$ = ""
    panning_row$ = ""
    speed_row$ = ""

    for row_num from 1 to 6
        available# = {0,1,2,3,4,5,6,7,8,9,10,11}
        temp_row$ = ""
        remaining = 12
        for i from 1 to 12
            pick = randomInteger (1, remaining)
            picked_val = available#[pick]
            temp_row$ = temp_row$ + string$(picked_val)
            if i < 12
                temp_row$ = temp_row$ + " "
            endif
            for j from pick to remaining - 1
                available#[j] = available#[j + 1]
            endfor
            remaining = remaining - 1
        endfor
        if row_num = 1
            mod_rate_row$ = temp_row$
        elsif row_num = 2
            mod_depth_row$ = temp_row$
        elsif row_num = 3
            mod_shape_row$ = temp_row$
        elsif row_num = 4
            duration_row$ = temp_row$
        elsif row_num = 5
            panning_row$ = temp_row$
        else
            speed_row$ = temp_row$
        endif
    endfor

    if random_seed <> 0
        random_initializeSafelyAndUnpredictably ()
    endif
else
    presetName$ = "Custom"
endif

# ============================================================
# PARSE + STRICT ROW VALIDATION
# ============================================================
@parseAndValidate: mod_rate_row$, "Rate"
for i from 1 to 12
    rate_prime_'i' = parseAndValidate.values_'i'
endfor

@parseAndValidate: mod_depth_row$, "Depth"
for i from 1 to 12
    depth_prime_'i' = parseAndValidate.values_'i'
endfor

@parseAndValidate: mod_shape_row$, "Shape"
for i from 1 to 12
    shape_prime_'i' = parseAndValidate.values_'i'
endfor

@parseAndValidate: duration_row$, "Duration"
for i from 1 to 12
    dur_prime_'i' = parseAndValidate.values_'i'
endfor

@parseAndValidate: panning_row$, "Panning"
for i from 1 to 12
    pan_prime_'i' = parseAndValidate.values_'i'
endfor

@parseAndValidate: speed_row$, "Speed"
for i from 1 to 12
    speed_prime_'i' = parseAndValidate.values_'i'
endfor

# Complement inversion / retrograde forms
for i from 1 to 12
    j = 13 - i

    rate_inversion_'i' = 11 - rate_prime_'i'
    depth_inversion_'i' = 11 - depth_prime_'i'
    shape_inversion_'i' = 11 - shape_prime_'i'
    dur_inversion_'i' = 11 - dur_prime_'i'
    pan_inversion_'i' = 11 - pan_prime_'i'
    speed_inversion_'i' = 11 - speed_prime_'i'

    rate_retrograde_'i' = rate_prime_'j'
    depth_retrograde_'i' = depth_prime_'j'
    shape_retrograde_'i' = shape_prime_'j'
    dur_retrograde_'i' = dur_prime_'j'
    pan_retrograde_'i' = pan_prime_'j'
    speed_retrograde_'i' = speed_prime_'j'

    rate_ri_'i' = 11 - rate_prime_'j'
    depth_ri_'i' = 11 - depth_prime_'j'
    shape_ri_'i' = 11 - shape_prime_'j'
    dur_ri_'i' = 11 - dur_prime_'j'
    pan_ri_'i' = 11 - pan_prime_'j'
    speed_ri_'i' = 11 - speed_prime_'j'
endfor

# ============================================================
# PREPARE ZERO-BASED MONO SOURCE
# ============================================================
selectObject: soundID
inputPeak = Get absolute extremum: 0, 0, "None"
monoFallback = 0
if num_channels > 1
    sourceMono = Convert to mono
    selectObject: sourceMono
    monoPeak = Get absolute extremum: 0, 0, "None"
    if inputPeak > 0 and monoPeak < inputPeak * 0.000001
        removeObject: sourceMono
        selectObject: soundID
        sourceMono = Extract one channel: 1
        monoFallback = 1
    endif
else
    sourceMono = Copy: "serialSource"
endif
selectObject: sourceMono
Shift times by: -source_start
Rename: "serialSource"

writeInfoLine: "=== Hexaphonic Serial Audio Processor v0.3 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input channels: ", num_channels, " -> stereo serial output"
if monoFallback
    appendInfoLine: "Mono source: channel 1 fallback (downmix cancellation detected)"
else
    appendInfoLine: "Mono source: channel average"
endif
appendInfoLine: "Sample rate: ", sampling_frequency, " Hz"
appendInfoLine: "Transform I: complement inversion (11 - value)"
if preset = 9
    if random_seed = 0
        appendInfoLine: "Random seed: unpredictable"
    else
        appendInfoLine: "Random seed: ", random_seed
    endif
endif
appendInfoLine: ""
appendInfoLine: "Rows:"
appendInfoLine: "Rate:     ", mod_rate_row$
appendInfoLine: "Depth:    ", mod_depth_row$
appendInfoLine: "Shape:    ", mod_shape_row$
appendInfoLine: "Duration: ", duration_row$
appendInfoLine: "Panning:  ", panning_row$
appendInfoLine: "Speed:    ", speed_row$
appendInfoLine: ""

# ============================================================
# PROCESS SERIAL EVENTS
# ============================================================
maxVizSegments = 200
vizStart# = zero#(maxVizSegments)
vizEnd# = zero#(maxVizSegments)
vizRate# = zero#(maxVizSegments)
vizDepth# = zero#(maxVizSegments)
vizShape# = zero#(maxVizSegments)
vizPan# = zero#(maxVizSegments)
vizSpeed# = zero#(maxVizSegments)
vizSection# = zero#(maxVizSegments)

segment_count = 0
source_time = 0
output_time = 0
serial_cycle = 1

label serialCycle
if source_time < duration
    appendInfoLine: "Serial cycle ", serial_cycle

    # Section A: P-P-P-P-P-P
    for step from 1 to 12
        if source_time >= duration
            goto doneProcessing
        endif
        rate_val = rate_prime_'step'
        depth_val = depth_prime_'step'
        shape_val = shape_prime_'step'
        dur_val = dur_prime_'step'
        pan_val = pan_prime_'step'
        speed_val = speed_prime_'step'
        section_val = 1
        @doEvent
    endfor

    # Section B: I-R-P-I-R-I
    for step from 1 to 12
        if source_time >= duration
            goto doneProcessing
        endif
        rate_val = rate_inversion_'step'
        depth_val = depth_retrograde_'step'
        shape_val = shape_prime_'step'
        dur_val = dur_inversion_'step'
        pan_val = pan_retrograde_'step'
        speed_val = speed_inversion_'step'
        section_val = 2
        @doEvent
    endfor

    # Section C: R-P-I-R-I-R
    for step from 1 to 12
        if source_time >= duration
            goto doneProcessing
        endif
        rate_val = rate_retrograde_'step'
        depth_val = depth_prime_'step'
        shape_val = shape_inversion_'step'
        dur_val = dur_retrograde_'step'
        pan_val = pan_inversion_'step'
        speed_val = speed_retrograde_'step'
        section_val = 3
        @doEvent
    endfor

    # Section D: RI-I-R-RI-P-RI
    for step from 1 to 12
        if source_time >= duration
            goto doneProcessing
        endif
        rate_val = rate_ri_'step'
        depth_val = depth_inversion_'step'
        shape_val = shape_retrograde_'step'
        dur_val = dur_ri_'step'
        pan_val = pan_prime_'step'
        speed_val = speed_ri_'step'
        section_val = 4
        @doEvent
    endfor

    serial_cycle = serial_cycle + 1
    goto serialCycle
endif

label doneProcessing

if segment_count = 0
    removeObject: sourceMono
    exitScript: "No serial segments were created."
endif

# Concatenate processed stereo events
selectObject: segment_1
for i from 2 to segment_count
    plusObject: segment_'i'
endfor
outputID = Concatenate
Rename: soundName$ + "_serialist_" + presetName$
if source_start <> 0
    Shift times by: source_start
endif

for i from 1 to segment_count
    removeObject: segment_'i'
endfor
removeObject: sourceMono

# Safety attenuation only
selectObject: outputID
peakBefore = Get absolute extremum: 0, 0, "None"
safetyGain = 1
if safety_peak > 0 and peakBefore > safety_peak
    safetyGain = safety_peak / peakBefore
    Formula: ~ self * safetyGain
endif
outputDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Source consumed: ", fixed$(source_time, 3), " / ", fixed$(duration, 3), " s"
appendInfoLine: "Output duration: ", fixed$(outputDuration, 3), " s"
appendInfoLine: "Segments: ", segment_count, " | serial cycles: ", serial_cycle
appendInfoLine: "Peak before safety: ", fixed$(peakBefore, 6)
appendInfoLine: "Output peak: ", fixed$(peakBefore * safetyGain, 6)

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    selectObject: soundID
    if num_channels > 1
        vizInput = Convert to mono
    else
        vizInput = Copy: "vizInput"
    endif

    selectObject: outputID
    vizOutput = Convert to mono

    Erase all

    # Title
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Hexaphonic Serial Audio Processor##"

    # Metadata subtitle
    Select outer viewport: 0, 8, 0.38, 0.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35,0.35,0.52}"
    Text: 0.5, "centre", 0.5, "half", soundName$ + " | " + presetName$ + " | six-row serial control"

    # Input waveform
    Select outer viewport: 0, 8, 0.65, 1.38
    Select inner viewport: 0.65, 7.6, 0.74, 1.28
    selectObject: vizInput
    Colour: "{0.55,0.55,0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.45, 2.18
    Select inner viewport: 0.65, 7.6, 1.54, 2.08
    selectObject: vizOutput
    Colour: "{0.22,0.45,0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Actual output-time event timeline
    Select outer viewport: 0, 8, 2.32, 3.12
    Select inner viewport: 0.65, 7.6, 2.41, 3.02
    Axes: 0, outputDuration, 0, 1
    Paint rectangle: "{0.97,0.97,0.97}", 0, outputDuration, 0, 1

    vizCount = min(segment_count, maxVizSegments)
    for s from 1 to vizCount
        sec = vizSection#[s]
        if sec = 1
            Colour: "{0.35,0.45,0.75}"
        elsif sec = 2
            Colour: "{0.47,0.36,0.72}"
        elsif sec = 3
            Colour: "{0.55,0.55,0.68}"
        else
            Colour: "{0.38,0.50,0.62}"
        endif
        Draw line: vizStart#[s], 0.08, vizStart#[s], 0.92
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Events"
    Text bottom: "yes", "Output time (s)"

    # Prime rate row
    Select outer viewport: 0, 4, 3.28, 4.18
    Select inner viewport: 0.65, 3.75, 3.37, 4.08
    Axes: 0.5, 12.5, -0.5, 11.5
    Paint rectangle: "{0.97,0.97,0.97}", 0.5, 12.5, -0.5, 11.5
    Colour: "{0.22,0.45,0.80}"
    for i from 1 to 12
        Draw circle: i, rate_prime_'i', 0.10
        if i < 12
            j = i + 1
            Draw line: i, rate_prime_'i', j, rate_prime_'j'
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Rate row"
    Text bottom: "yes", "Step"

    # Prime pan row
    Select outer viewport: 4, 8, 3.28, 4.18
    Select inner viewport: 4.55, 7.6, 3.37, 4.08
    Axes: 0.5, 12.5, -0.5, 11.5
    Paint rectangle: "{0.97,0.97,0.97}", 0.5, 12.5, -0.5, 11.5
    Colour: "{0.47,0.36,0.72}"
    for i from 1 to 12
        Draw circle: i, pan_prime_'i', 0.10
        if i < 12
            j = i + 1
            Draw line: i, pan_prime_'i', j, pan_prime_'j'
        endif
    endfor
    Colour: "{0.70,0.70,0.70}"
    Dotted line
    Draw line: 0.5, 6, 12.5, 6
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan row"
    Text bottom: "yes", "Step"

    # Summary
    Select outer viewport: 0, 8, 4.36, 5.08
    Select inner viewport: 0.45, 7.7, 4.43, 5.01
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Segments: " + string$(segment_count) + " | Output: " + fixed$(outputDuration, 2) + " s | Rate: " + fixed$(min_rate, 1) + "-" + fixed$(max_rate, 1) + " Hz | Depth: " + fixed$(min_depth, 2) + "-" + fixed$(max_depth, 2)
    Text: 0.02, "left", 0.20, "half", "Duration row: " + fixed$(min_duration, 2) + "-" + fixed$(max_duration, 2) + " s | Speed: -6..+5 st | Safety: " + fixed$(safety_peak, 2) + " | Stereo output"

    removeObject: vizInput, vizOutput

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

if play_result
    selectObject: outputID
    Play
endif

selectObject: outputID

# ============================================================
# PROCEDURES
# ============================================================

procedure parseAndValidate: .row_string$, .label$
    .length = 0
    .remaining$ = .row_string$ + " "
    while index(.remaining$, " ") > 0
        .space_pos = index(.remaining$, " ")
        .value$ = left$(.remaining$, .space_pos - 1)
        if .value$ <> ""
            .length = .length + 1
            if .length <= 12
                .values_'.length' = number(.value$)
            endif
        endif
        .remaining$ = right$(.remaining$, length(.remaining$) - .space_pos)
    endwhile

    if .length <> 12
        exitScript: .label$ + " row must contain exactly 12 values."
    endif

    for .i from 1 to 12
        .v = .values_'.i'
        if .v = undefined or .v <> round(.v) or .v < 0 or .v > 11
            exitScript: .label$ + " row values must be integers from 0 to 11."
        endif
    endfor
endproc

procedure doEvent
    step_dur = min_duration + (dur_val / 11) * (max_duration - min_duration)
    remaining_duration = duration - source_time
    if remaining_duration < 1 / sampling_frequency
        source_time = duration
        step_dur = 0
    elsif step_dur > remaining_duration
        step_dur = remaining_duration
    endif

    if step_dur >= 1 / sampling_frequency
        @processSegment: sourceMono, source_time, source_time + step_dur, rate_val, depth_val, shape_val, pan_val, speed_val

        segment_count = segment_count + 1
        if segment_count > 5000
            exitScript: "More than 5000 serial events would be required. Increase Min_duration."
        endif
        segment_'segment_count' = processSegment.result

        if segment_count <= maxVizSegments
            vizStart#[segment_count] = output_time
            vizEnd#[segment_count] = output_time + processSegment.outputDuration
            vizRate#[segment_count] = rate_val
            vizDepth#[segment_count] = depth_val
            vizShape#[segment_count] = shape_val
            vizPan#[segment_count] = pan_val
            vizSpeed#[segment_count] = speed_val
            vizSection#[segment_count] = section_val
        endif

        source_time = source_time + step_dur
        output_time = output_time + processSegment.outputDuration
    endif
endproc

procedure processSegment: .soundID, .start_time, .end_time, .rate_index, .depth_index, .shape_index, .pan_index, .speed_index
    if perceptual_rate_scaling
        .rate_ratio = .rate_index / 11
        .mod_rate = min_rate * (max_rate / min_rate) ^ .rate_ratio
    else
        .mod_rate = min_rate + (.rate_index / 11) * (max_rate - min_rate)
    endif
    .mod_depth = min_depth + (.depth_index / 11) * (max_depth - min_depth)

    selectObject: .soundID
    .segmentID = Extract part: .start_time, .end_time, "rectangular", 1, "no"

    # Correct tape-speed mapping:
    # speed index 0=-6 st, 6=0 st, 11=+5 st.
    .speed_semitones = .speed_index - 6
    .speed_factor = 2 ^ (.speed_semitones / 12)

    if abs(.speed_factor - 1) > 0.000001
        selectObject: .segmentID
        Override sampling frequency: sampling_frequency * .speed_factor
        .resampledID = Resample: sampling_frequency, 50
        removeObject: .segmentID
        .segmentID = .resampledID
    endif

    # Apply AM on the mono serial source.
    selectObject: .segmentID
    if .shape_index <= 2
        Formula: ~ self * (1 + .mod_depth * sin(2*pi*.mod_rate*x))
    elsif .shape_index <= 5
        Formula: ~ self * (1 + .mod_depth * (1 - 4*abs(round(.mod_rate*x) - .mod_rate*x)))
    elsif .shape_index <= 8
        Formula: ~ self * (1 + .mod_depth * if (.mod_rate*x - floor(.mod_rate*x)) < 0.5 then 1 else -1 fi)
    else
        Formula: ~ self * (1 + .mod_depth * (2*((.mod_rate*x) - floor(.mod_rate*x)) - 1))
    endif

    # Panning row: exact center at index 6; equal-power gains.
    if .pan_index <= 6
        .pan01 = 0.5 * .pan_index / 6
    else
        .pan01 = 0.5 + 0.5 * (.pan_index - 6) / 5
    endif
    .left_gain = cos(0.5*pi*.pan01)
    .right_gain = sin(0.5*pi*.pan01)

    selectObject: .segmentID
    .leftID = Copy: "serialL"
    Formula: ~ self * .left_gain

    selectObject: .segmentID
    .rightID = Copy: "serialR"
    Formula: ~ self * .right_gain

    selectObject: .leftID
    plusObject: .rightID
    .pannedID = Combine to stereo

    selectObject: .pannedID
    .outputDuration = Get total duration

    removeObject: .leftID, .rightID, .segmentID
    .result = .pannedID
endproc
