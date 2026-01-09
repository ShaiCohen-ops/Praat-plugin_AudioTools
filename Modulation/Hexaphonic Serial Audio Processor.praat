# ============================================================
# Praat AudioTools - Hexaphonic_Serial_Audio_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Serialist Amplitude Modulation Audio Effect - applies 12-tone
#   serial composition techniques to audio processing. Uses 6
#   independent tone rows for rate, depth, shape, duration, panning,
#   and speed with Prime/Inversion/Retrograde transformations.
#   Inspired by Schoenberg, Webern, and Berg.
#
# Changelog v0.2:
#   - Added input check
#   - Modern formula syntax
#   - Added visualization
#   - Fixed typos
# ============================================================

form Serialist Amplitude Modulation Effect
    comment Select a Sound object first
    comment ═══════════════════════════════════════════════
    optionmenu Preset 1
        option Custom
        option Classic Webern
        option Berg Symmetrical
        option Schoenberg Op.25
        option Chromatic Ascent
        option All-Interval
        option Pentatonic Serial
        option Whole-Tone Serial
        option Random Chaos
    comment ═══════════════════════════════════════════════
    comment PRIME ROW DEFINITIONS (values 0-11):
    sentence Mod_rate_row 0 3 7 11 2 6 9 1 5 8 4 10
    sentence Mod_depth_row 5 9 2 11 0 7 3 10 1 6 8 4
    sentence Mod_shape_row 2 8 5 0 11 3 7 1 9 4 10 6
    sentence Duration_row 6 2 9 1 11 4 8 0 7 3 10 5
    sentence Panning_row 4 8 1 10 3 7 0 11 5 9 2 6
    sentence Speed_row 6 5 7 4 8 3 9 2 10 1 11 0
    comment ═══════════════════════════════════════════════
    comment PARAMETER RANGES:
    positive Min_rate 0.5
    positive Max_rate 50
    positive Min_depth 0.05
    positive Max_depth 0.95
    positive Min_duration 0.1
    positive Max_duration 3.0
    comment ═══════════════════════════════════════════════
    boolean Perceptual_rate_scaling 1
    boolean Draw_visualization 1
    comment Shape: 0-2=sine, 3-5=triangle, 6-8=square, 9-11=sawtooth
    comment Panning: 0=left, 6=center, 11=right
    comment Speed: 0=-6 semitones, 6=original, 11=+5 semitones
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Get selected sound info BEFORE presets modify variables
soundID = selected("Sound")
soundName$ = selected$("Sound")

selectObject: soundID
duration = Get total duration
sampling_frequency = Get sampling frequency
num_channels = Get number of channels

# Apply preset values
if preset = 2
    # Classic Webern - symmetrical structure
    mod_rate_row$ = "0 11 3 8 4 7 9 2 10 1 5 6"
    mod_depth_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    mod_shape_row$ = "0 3 6 9 1 4 7 10 2 5 8 11"
    duration_row$ = "5 6 4 7 3 8 2 9 1 10 0 11"
    panning_row$ = "6 5 7 4 8 3 9 2 10 1 11 0"
    speed_row$ = "6 6 6 5 7 5 7 6 6 6 6 6"
    presetName$ = "Webern"
elsif preset = 3
    # Berg Symmetrical - palindromic tendencies
    mod_rate_row$ = "0 11 7 4 2 9 3 8 10 1 5 6"
    mod_depth_row$ = "5 10 2 7 11 1 8 4 9 0 6 3"
    mod_shape_row$ = "6 5 4 3 2 1 0 11 10 9 8 7"
    duration_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    panning_row$ = "0 2 4 6 8 10 11 9 7 5 3 1"
    speed_row$ = "6 7 5 8 4 9 3 10 2 11 1 0"
    presetName$ = "Berg"
elsif preset = 4
    # Schoenberg Op.25 - famous row
    mod_rate_row$ = "4 5 7 1 6 3 8 2 11 0 9 10"
    mod_depth_row$ = "0 6 5 11 10 4 3 9 8 2 1 7"
    mod_shape_row$ = "8 10 11 1 3 4 6 7 9 0 2 5"
    duration_row$ = "3 9 2 8 1 7 0 6 11 5 10 4"
    panning_row$ = "2 8 4 10 0 6 11 5 9 3 7 1"
    speed_row$ = "5 6 7 6 5 7 6 5 6 7 5 6"
    presetName$ = "Schoenberg"
elsif preset = 5
    # Chromatic Ascent
    mod_rate_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    mod_depth_row$ = "11 10 9 8 7 6 5 4 3 2 1 0"
    mod_shape_row$ = "0 2 4 6 8 10 1 3 5 7 9 11"
    duration_row$ = "6 7 5 8 4 9 3 10 2 11 1 0"
    panning_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    speed_row$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    presetName$ = "Chromatic"
elsif preset = 6
    # All-Interval - contains all 11 intervals
    mod_rate_row$ = "0 1 4 2 9 5 11 3 8 10 7 6"
    mod_depth_row$ = "0 3 6 9 1 4 7 10 2 5 8 11"
    mod_shape_row$ = "0 5 10 3 8 1 6 11 4 9 2 7"
    duration_row$ = "2 7 1 8 0 9 11 4 10 3 5 6"
    panning_row$ = "1 5 9 2 6 10 3 7 11 4 8 0"
    speed_row$ = "4 8 2 10 1 7 0 9 3 11 5 6"
    presetName$ = "AllInterval"
elsif preset = 7
    # Pentatonic Serial - emphasizes pentatonic intervals
    mod_rate_row$ = "0 2 4 7 9 1 3 5 8 10 6 11"
    mod_depth_row$ = "0 5 7 2 9 4 11 6 1 8 3 10"
    mod_shape_row$ = "0 7 2 9 4 11 6 1 8 3 10 5"
    duration_row$ = "1 6 3 8 5 10 7 2 9 4 11 0"
    panning_row$ = "0 7 2 9 4 11 6 1 8 3 10 5"
    speed_row$ = "6 5 7 6 5 7 6 5 7 6 5 7"
    presetName$ = "Pentatonic"
elsif preset = 8
    # Whole-Tone Serial
    mod_rate_row$ = "0 2 4 6 8 10 1 3 5 7 9 11"
    mod_depth_row$ = "1 3 5 7 9 11 0 2 4 6 8 10"
    mod_shape_row$ = "0 6 1 7 2 8 3 9 4 10 5 11"
    duration_row$ = "5 11 4 10 3 9 2 8 1 7 0 6"
    panning_row$ = "0 6 1 7 2 8 3 9 4 10 5 11"
    speed_row$ = "6 8 4 10 2 8 4 10 2 8 4 10"
    presetName$ = "WholeTone"
elsif preset = 9
    # Random Chaos - generate random rows
    mod_rate_row$ = ""
    mod_depth_row$ = ""
    mod_shape_row$ = ""
    duration_row$ = ""
    panning_row$ = ""
    speed_row$ = ""
    presetName$ = "Random"
    
    # Generate random permutations for all six rows
    for row_num from 1 to 6
        # Initialize available values
        for i from 0 to 11
            available_'i' = i
        endfor
        temp_row$ = ""
        for i from 0 to 11
            remaining = 11 - i
            pick = randomInteger(0, remaining)
            # Get value at pick position
            if pick = 0
                picked_val = available_0
            elsif pick = 1
                picked_val = available_1
            elsif pick = 2
                picked_val = available_2
            elsif pick = 3
                picked_val = available_3
            elsif pick = 4
                picked_val = available_4
            elsif pick = 5
                picked_val = available_5
            elsif pick = 6
                picked_val = available_6
            elsif pick = 7
                picked_val = available_7
            elsif pick = 8
                picked_val = available_8
            elsif pick = 9
                picked_val = available_9
            elsif pick = 10
                picked_val = available_10
            else
                picked_val = available_11
            endif
            
            temp_row$ = temp_row$ + string$(picked_val) + " "
            
            # Shift remaining values down
            for j from pick to remaining - 1
                if j = 0
                    available_0 = available_1
                elsif j = 1
                    available_1 = available_2
                elsif j = 2
                    available_2 = available_3
                elsif j = 3
                    available_3 = available_4
                elsif j = 4
                    available_4 = available_5
                elsif j = 5
                    available_5 = available_6
                elsif j = 6
                    available_6 = available_7
                elsif j = 7
                    available_7 = available_8
                elsif j = 8
                    available_8 = available_9
                elsif j = 9
                    available_9 = available_10
                elsif j = 10
                    available_10 = available_11
                endif
            endfor
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
        elsif row_num = 6
            speed_row$ = temp_row$
        endif
    endfor
else
    presetName$ = "Custom"
endif

# Parse prime rows into arrays
@parseRow: mod_rate_row$
for i from 1 to 12
    rate_prime_'i' = parseRow.values_'i'
endfor

@parseRow: mod_depth_row$
for i from 1 to 12
    depth_prime_'i' = parseRow.values_'i'
endfor

@parseRow: mod_shape_row$
for i from 1 to 12
    shape_prime_'i' = parseRow.values_'i'
endfor

@parseRow: duration_row$
for i from 1 to 12
    dur_prime_'i' = parseRow.values_'i'
endfor

@parseRow: panning_row$
for i from 1 to 12
    pan_prime_'i' = parseRow.values_'i'
endfor

@parseRow: speed_row$
for i from 1 to 12
    speed_prime_'i' = parseRow.values_'i'
endfor

# Generate transformations for all rows
for i from 1 to 12
    # Inversion: 0→11, 1→10, etc.
    rate_inversion_'i' = 11 - rate_prime_'i'
    depth_inversion_'i' = 11 - depth_prime_'i'
    shape_inversion_'i' = 11 - shape_prime_'i'
    dur_inversion_'i' = 11 - dur_prime_'i'
    pan_inversion_'i' = 11 - pan_prime_'i'
    speed_inversion_'i' = 11 - speed_prime_'i'
    
    # Retrograde: reverse order
    j = 13 - i
    rate_retrograde_'i' = rate_prime_'j'
    depth_retrograde_'i' = depth_prime_'j'
    shape_retrograde_'i' = shape_prime_'j'
    dur_retrograde_'i' = dur_prime_'j'
    pan_retrograde_'i' = pan_prime_'j'
    speed_retrograde_'i' = speed_prime_'j'
    
    # Retrograde-Inversion: reverse + invert
    rate_ri_'i' = 11 - rate_prime_'j'
    depth_ri_'i' = 11 - depth_prime_'j'
    shape_ri_'i' = 11 - shape_prime_'j'
    dur_ri_'i' = 11 - dur_prime_'j'
    pan_ri_'i' = 11 - pan_prime_'j'
    speed_ri_'i' = 11 - speed_prime_'j'
endfor

writeInfoLine: "═══════════════════════════════════════════"
appendInfoLine: "Serialist Amplitude Modulation Processing"
appendInfoLine: "═══════════════════════════════════════════"
appendInfoLine: "Sound: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Perceptual rate scaling: ", perceptual_rate_scaling
appendInfoLine: ""
appendInfoLine: "PRIME ROWS:"
appendInfoLine: "Rate:     ", mod_rate_row$
appendInfoLine: "Depth:    ", mod_depth_row$
appendInfoLine: "Shape:    ", mod_shape_row$
appendInfoLine: "Duration: ", duration_row$
appendInfoLine: "Panning:  ", panning_row$
appendInfoLine: "Speed:    ", speed_row$
appendInfoLine: ""
appendInfoLine: "CROSS-COUPLING STRUCTURE:"
appendInfoLine: "Section A: rate=P,  depth=P,  shape=P,  dur=P,  pan=P,  speed=P"
appendInfoLine: "Section B: rate=I,  depth=R,  shape=P,  dur=I,  pan=R,  speed=I"
appendInfoLine: "Section C: rate=R,  depth=P,  shape=I,  dur=R,  pan=I,  speed=R"
appendInfoLine: "Section D: rate=RI, depth=I,  shape=R,  dur=RI, pan=P,  speed=RI"
appendInfoLine: ""

# Arrays to store segment info for visualization
maxSegments = 50
vizSegmentStart# = zero#(maxSegments)
vizSegmentEnd# = zero#(maxSegments)
vizSegmentRate# = zero#(maxSegments)
vizSegmentDepth# = zero#(maxSegments)
vizSegmentShape# = zero#(maxSegments)
vizSegmentPan# = zero#(maxSegments)
vizSegmentSection# = zero#(maxSegments)

# Array to store all processed segments
segment_count = 0
current_time = 0

# Section A: Prime for all
appendInfoLine: "Section A: PRIME (P-P-P-P-P-P)"
for step from 1 to 12
    rate_val = rate_prime_'step'
    depth_val = depth_prime_'step'
    shape_val = shape_prime_'step'
    dur_val = dur_prime_'step'
    pan_val = pan_prime_'step'
    speed_val = speed_prime_'step'
    
    step_dur = min_duration + (dur_val / 11) * (max_duration - min_duration)
    
    if current_time + step_dur > duration
        step_dur = duration - current_time
    endif
    
    if step_dur > 0.01
        @processSegment: soundID, current_time, current_time + step_dur, rate_val, depth_val, shape_val, pan_val, speed_val
        segment_count = segment_count + 1
        segment_'segment_count' = processSegment.result
        
        # Store for visualization
        if segment_count <= maxSegments
            vizSegmentStart#[segment_count] = current_time
            vizSegmentEnd#[segment_count] = current_time + step_dur
            vizSegmentRate#[segment_count] = rate_val
            vizSegmentDepth#[segment_count] = depth_val
            vizSegmentShape#[segment_count] = shape_val
            vizSegmentPan#[segment_count] = pan_val
            vizSegmentSection#[segment_count] = 1
        endif
        
        appendInfoLine: "  Step ", step, ": r=", rate_val, " d=", depth_val, " sh=", shape_val, " dur=", fixed$(step_dur, 2), " pan=", pan_val, " sp=", speed_val
        current_time = current_time + step_dur
    endif
    
    if current_time >= duration
        goto doneProcessing
    endif
endfor

# Section B: Cross-coupled (I-R-P-I-R-I)
appendInfoLine: ""
appendInfoLine: "Section B: CROSS-COUPLED (I-R-P-I-R-I)"
for step from 1 to 12
    rate_val = rate_inversion_'step'
    depth_val = depth_retrograde_'step'
    shape_val = shape_prime_'step'
    dur_val = dur_inversion_'step'
    pan_val = pan_retrograde_'step'
    speed_val = speed_inversion_'step'
    
    step_dur = min_duration + (dur_val / 11) * (max_duration - min_duration)
    
    if current_time + step_dur > duration
        step_dur = duration - current_time
    endif
    
    if step_dur > 0.01
        @processSegment: soundID, current_time, current_time + step_dur, rate_val, depth_val, shape_val, pan_val, speed_val
        segment_count = segment_count + 1
        segment_'segment_count' = processSegment.result
        
        if segment_count <= maxSegments
            vizSegmentStart#[segment_count] = current_time
            vizSegmentEnd#[segment_count] = current_time + step_dur
            vizSegmentRate#[segment_count] = rate_val
            vizSegmentDepth#[segment_count] = depth_val
            vizSegmentShape#[segment_count] = shape_val
            vizSegmentPan#[segment_count] = pan_val
            vizSegmentSection#[segment_count] = 2
        endif
        
        appendInfoLine: "  Step ", step, ": r=", rate_val, " d=", depth_val, " sh=", shape_val, " dur=", fixed$(step_dur, 2), " pan=", pan_val, " sp=", speed_val
        current_time = current_time + step_dur
    endif
    
    if current_time >= duration
        goto doneProcessing
    endif
endfor

# Section C: Cross-coupled (R-P-I-R-I-R)
appendInfoLine: ""
appendInfoLine: "Section C: CROSS-COUPLED (R-P-I-R-I-R)"
for step from 1 to 12
    rate_val = rate_retrograde_'step'
    depth_val = depth_prime_'step'
    shape_val = shape_inversion_'step'
    dur_val = dur_retrograde_'step'
    pan_val = pan_inversion_'step'
    speed_val = speed_retrograde_'step'
    
    step_dur = min_duration + (dur_val / 11) * (max_duration - min_duration)
    
    if current_time + step_dur > duration
        step_dur = duration - current_time
    endif
    
    if step_dur > 0.01
        @processSegment: soundID, current_time, current_time + step_dur, rate_val, depth_val, shape_val, pan_val, speed_val
        segment_count = segment_count + 1
        segment_'segment_count' = processSegment.result
        
        if segment_count <= maxSegments
            vizSegmentStart#[segment_count] = current_time
            vizSegmentEnd#[segment_count] = current_time + step_dur
            vizSegmentRate#[segment_count] = rate_val
            vizSegmentDepth#[segment_count] = depth_val
            vizSegmentShape#[segment_count] = shape_val
            vizSegmentPan#[segment_count] = pan_val
            vizSegmentSection#[segment_count] = 3
        endif
        
        appendInfoLine: "  Step ", step, ": r=", rate_val, " d=", depth_val, " sh=", shape_val, " dur=", fixed$(step_dur, 2), " pan=", pan_val, " sp=", speed_val
        current_time = current_time + step_dur
    endif
    
    if current_time >= duration
        goto doneProcessing
    endif
endfor

# Section D: Cross-coupled (RI-I-R-RI-P-RI)
appendInfoLine: ""
appendInfoLine: "Section D: CROSS-COUPLED (RI-I-R-RI-P-RI)"
for step from 1 to 12
    rate_val = rate_ri_'step'
    depth_val = depth_inversion_'step'
    shape_val = shape_retrograde_'step'
    dur_val = dur_ri_'step'
    pan_val = pan_prime_'step'
    speed_val = speed_ri_'step'
    
    step_dur = min_duration + (dur_val / 11) * (max_duration - min_duration)
    
    if current_time + step_dur > duration
        step_dur = duration - current_time
    endif
    
    if step_dur > 0.01
        @processSegment: soundID, current_time, current_time + step_dur, rate_val, depth_val, shape_val, pan_val, speed_val
        segment_count = segment_count + 1
        segment_'segment_count' = processSegment.result
        
        if segment_count <= maxSegments
            vizSegmentStart#[segment_count] = current_time
            vizSegmentEnd#[segment_count] = current_time + step_dur
            vizSegmentRate#[segment_count] = rate_val
            vizSegmentDepth#[segment_count] = depth_val
            vizSegmentShape#[segment_count] = shape_val
            vizSegmentPan#[segment_count] = pan_val
            vizSegmentSection#[segment_count] = 4
        endif
        
        appendInfoLine: "  Step ", step, ": r=", rate_val, " d=", depth_val, " sh=", shape_val, " dur=", fixed$(step_dur, 2), " pan=", pan_val, " sp=", speed_val
        current_time = current_time + step_dur
    endif
    
    if current_time >= duration
        goto doneProcessing
    endif
endfor

label doneProcessing

# Concatenate all segments
appendInfoLine: ""
appendInfoLine: "Concatenating ", segment_count, " segments..."

if segment_count > 0
    selectObject: segment_1
    for i from 2 to segment_count
        plusObject: segment_'i'
    endfor
    outputID = Concatenate
    Rename: soundName$ + "_serialist_" + presetName$
    
    # CLEANUP: Remove all segment objects
    appendInfoLine: "Cleaning up ", segment_count, " intermediate segments..."
    for i from 1 to segment_count
        removeObject: segment_'i'
    endfor
else
    exitScript: "No segments were created. Audio may be too short."
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Serialist AM: " + soundName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.3
    Select inner viewport: 0.6, 7.6, 0.7, 1.2
    selectObject: soundID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.4, 2.1
    Select inner viewport: 0.6, 7.6, 1.5, 2.0
    selectObject: outputID
    Colour: "{0.5, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Serialist"
    Text bottom: "yes", "Time (s)"
    
    # Segment timeline with sections color-coded
    Select outer viewport: 0, 8, 2.3, 3.3
    Select inner viewport: 0.6, 7.6, 2.4, 3.2
    
    processedTime = current_time
    if processedTime < duration
        processedTime = duration
    endif
    
    Axes: 0, processedTime, -0.5, 4.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, processedTime, -0.5, 4.5
    
    # Draw segments
    vizCount = min(segment_count, maxSegments)
    for s from 1 to vizCount
        sec = vizSegmentSection#[s]
        
        # Color by section
        if sec = 1
            Paint rectangle: "{0.7, 0.5, 0.5}", vizSegmentStart#[s], vizSegmentEnd#[s], 0, 1
        elsif sec = 2
            Paint rectangle: "{0.5, 0.7, 0.5}", vizSegmentStart#[s], vizSegmentEnd#[s], 0, 1
        elsif sec = 3
            Paint rectangle: "{0.5, 0.5, 0.7}", vizSegmentStart#[s], vizSegmentEnd#[s], 0, 1
        else
            Paint rectangle: "{0.7, 0.6, 0.5}", vizSegmentStart#[s], vizSegmentEnd#[s], 0, 1
        endif
    endfor
    
    # Section labels
    Colour: "Black"
    Font size: 5
    Text: 0.02, "left", 3.8, "half", "A=Prime"
    Text: 0.15, "left", 3.8, "half", "B=I-R-P"
    Text: 0.28, "left", 3.8, "half", "C=R-P-I"
    Text: 0.41, "left", 3.8, "half", "D=RI-I-R"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Sections"
    Text bottom: "yes", "Time (s)"
    
    # Prime row visualization (Rate row as example)
    Select outer viewport: 0, 4, 3.5, 4.5
    Select inner viewport: 0.6, 3.8, 3.6, 4.4
    
    Axes: 0, 13, -0.5, 11.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 13, -0.5, 11.5
    
    # Draw rate row values as bars
    for i from 1 to 12
        val = rate_prime_'i'
        Paint rectangle: "{0.7, 0.5, 0.5}", i - 0.4, i + 0.4, 0, val
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Rate Row (P)"
    Text bottom: "yes", "Step"
    
    # Depth row
    Select outer viewport: 4, 8, 3.5, 4.5
    Select inner viewport: 4.4, 7.6, 3.6, 4.4
    
    Axes: 0, 13, -0.5, 11.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 13, -0.5, 11.5
    
    for i from 1 to 12
        val = depth_prime_'i'
        Paint rectangle: "{0.5, 0.7, 0.5}", i - 0.4, i + 0.4, 0, val
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Depth Row (P)"
    Text bottom: "yes", "Step"
    
    # Shape and Panning rows
    Select outer viewport: 0, 4, 4.6, 5.4
    Select inner viewport: 0.6, 3.8, 4.7, 5.3
    
    Axes: 0, 13, -0.5, 11.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 13, -0.5, 11.5
    
    for i from 1 to 12
        val = shape_prime_'i'
        # Color by shape type
        if val <= 2
            Paint rectangle: "{0.6, 0.6, 0.8}", i - 0.4, i + 0.4, 0, val
        elsif val <= 5
            Paint rectangle: "{0.6, 0.8, 0.6}", i - 0.4, i + 0.4, 0, val
        elsif val <= 8
            Paint rectangle: "{0.8, 0.6, 0.6}", i - 0.4, i + 0.4, 0, val
        else
            Paint rectangle: "{0.8, 0.8, 0.6}", i - 0.4, i + 0.4, 0, val
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Shape (P)"
    
    # Panning row
    Select outer viewport: 4, 8, 4.6, 5.4
    Select inner viewport: 4.4, 7.6, 4.7, 5.3
    
    Axes: 0, 13, -0.5, 11.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 13, -0.5, 11.5
    
    # Center line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 5.5, 13, 5.5
    Solid line
    
    for i from 1 to 12
        val = pan_prime_'i'
        Paint rectangle: "{0.7, 0.6, 0.8}", i - 0.4, i + 0.4, 5.5, val
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Pan (P)"
    
    # Stats
    Select outer viewport: 0, 8, 5.5, 5.8
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Segments: " + string$(segment_count) + " | Rate: " + fixed$(min_rate, 1) + "-" + fixed$(max_rate, 0) + " Hz | Depth: " + fixed$(min_depth, 2) + "-" + fixed$(max_depth, 2) + " | Dur: " + fixed$(min_duration, 1) + "-" + fixed$(max_duration, 1) + "s"
    
    Font size: 10
    Colour: "Black"
endif

appendInfoLine: ""
appendInfoLine: "═══════════════════════════════════════════"
appendInfoLine: "Processing complete!"
appendInfoLine: "═══════════════════════════════════════════"
appendInfoLine: "Original: '", soundName$, "'"
appendInfoLine: "Result:   '", soundName$, "_serialist_", presetName$, "'"
appendInfoLine: "Total processed time: ", fixed$(current_time, 3), " / ", fixed$(duration, 3), " s"
appendInfoLine: "Segments created: ", segment_count
appendInfoLine: ""
appendInfoLine: "Playing result..."
appendInfoLine: "═══════════════════════════════════════════"

# Select and play result
selectObject: outputID
Play


# ═══════════════════════════════════════════════════
# PROCEDURES
# ═══════════════════════════════════════════════════

procedure parseRow: .row_string$
    # Parse space-separated row into numbered variables
    .length = 0
    .remaining$ = .row_string$ + " "
    while index(.remaining$, " ") > 0
        .space_pos = index(.remaining$, " ")
        .value$ = left$(.remaining$, .space_pos - 1)
        if .value$ <> ""
            .length = .length + 1
            .values_'.length' = number(.value$)
        endif
        .remaining$ = right$(.remaining$, length(.remaining$) - .space_pos)
    endwhile
    
    # Ensure we have 12 values
    while .length < 12
        .length = .length + 1
        .values_'.length' = 0
    endwhile
endproc

procedure processSegment: .soundID, .start_time, .end_time, .rate_index, .depth_index, .shape_index, .pan_index, .speed_index
    # Map serial indices (0-11) to parameter values
    
    # PERCEPTUAL RATE SCALING: logarithmic instead of linear
    if perceptual_rate_scaling
        .rate_ratio = .rate_index / 11
        .mod_rate = min_rate * (max_rate / min_rate) ^ .rate_ratio
    else
        .mod_rate = min_rate + (.rate_index / 11) * (max_rate - min_rate)
    endif
    
    .mod_depth = min_depth + (.depth_index / 11) * (max_depth - min_depth)
    
    # Panning: 0=left, 11=right
    .pan_position = .pan_index / 11
    
    # Extract segment
    selectObject: .soundID
    .segmentID = Extract part: .start_time, .end_time, "rectangular", 1, "no"
    .seg_duration = Get total duration
    .num_channels = Get number of channels
    
    # PLAYBACK SPEED (Resampling) - do this BEFORE AM processing
    selectObject: .segmentID
    .speed_semitones = .speed_index - 6
    .speed_factor = 2 ^ (.speed_semitones / 12)
    .target_hz = sampling_frequency * .speed_factor
    
    if abs(.speed_factor - 1.0) > 0.01
        selectObject: .segmentID
        Resample: .target_hz, 50
        .resampledID = selected("Sound")
        removeObject: .segmentID
        .segmentID = .resampledID
        
        selectObject: .segmentID
        Override sampling frequency: sampling_frequency
        Resample: sampling_frequency, 50
        .finalResampledID = selected("Sound")
        removeObject: .segmentID
        .segmentID = .finalResampledID
    endif
    
    # Determine modulator shape
    if .shape_index <= 2
        .shape$ = "sine"
    elsif .shape_index <= 5
        .shape$ = "triangle"
    elsif .shape_index <= 8
        .shape$ = "square"
    else
        .shape$ = "sawtooth"
    endif
    
    # Apply AM to each channel
    for .ch from 1 to .num_channels
        selectObject: .segmentID
        .channelID = Extract one channel: .ch
        
        # Apply modulation based on shape
        if .shape$ = "sine"
            Formula: ~ self * (1 + .mod_depth * sin(2 * pi * .mod_rate * x))
        elsif .shape$ = "triangle"
            Formula: ~ self * (1 + .mod_depth * (1 - 4 * abs(round(.mod_rate * x) - .mod_rate * x)))
        elsif .shape$ = "square"
            Formula: ~ self * (1 + .mod_depth * if (.mod_rate * x - floor(.mod_rate * x)) < 0.5 then 1 else -1 fi)
        elsif .shape$ = "sawtooth"
            Formula: ~ self * (1 + .mod_depth * (2 * ((.mod_rate * x) - floor(.mod_rate * x)) - 1))
        endif
        
        .processedChannel = selected("Sound")
        
        if .ch = 1
            .processedID = .processedChannel
        else
            # Combine channels
            selectObject: .processedID, .processedChannel
            .combinedID = Combine to stereo
            removeObject: .processedID, .processedChannel
            .processedID = .combinedID
        endif
    endfor
    
    # Apply PANNING to stereo output
    selectObject: .processedID
    .current_channels = Get number of channels
    
    # Convert to stereo if mono
    if .current_channels = 1
        selectObject: .processedID
        Convert to stereo
        .stereoID = selected("Sound")
        removeObject: .processedID
        .processedID = .stereoID
    endif
    
    # Apply panning
    .left_gain = 1 - .pan_position
    .right_gain = .pan_position
    
    selectObject: .processedID
    .leftChannel = Extract one channel: 1
    Formula: ~ self * .left_gain
    
    selectObject: .processedID
    .rightChannel = Extract one channel: 2
    Formula: ~ self * .right_gain
    
    # Recombine into stereo
    selectObject: .leftChannel, .rightChannel
    .pannedID = Combine to stereo
    
    # Clean up
    removeObject: .leftChannel, .rightChannel, .processedID, .segmentID
    
    .result = .pannedID
endproc