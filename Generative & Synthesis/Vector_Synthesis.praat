# ============================================================
# Praat AudioTools - Vector Synthesis (Prophet VS Style)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - With Presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Vector Synthesis (Prophet VS Style)
#
# Usage:
#   Run this script (no input sound required).
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Added presets for common polyrhythmic patterns
#   - Simplified visualization (removed waveform panel)
# ============================================================

form Vector Synthesis Parameters
    comment === Mode ===
    boolean Melody_demo 0
    comment (If checked, plays a test melody)
    
    comment === Vector Path ===
    optionmenu Path_type: 1
        option Circle
        option Ellipse
        option Lissajous (3:2)
        option Figure-8
        option Spiral In
        option Spiral Out
        option Square Path
        option Star
        option Infinity Loop
        option Butterfly
        option Rose Curve
        option Chaotic Attractor
    positive Path_speed 0.5
    comment (Path_speed: cycles per second)
    
    comment === Single Note Parameters ===
    positive Duration_s 6.0
    positive Frequency_Hz 110
    
    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Show_trail 1
    comment (Show gradient trail effect)
    boolean Play_result 1
endform

sampling_rate = 44100
twoPi = 2 * pi

writeInfoLine: "=== VECTOR SYNTHESIS ==="
appendInfoLine: "Path: ", path_type$
appendInfoLine: ""

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

if melody_demo
    appendInfoLine: "Generating melody demo (bass register)..."
    
    # Bass melody: E2, G2, A2, C3, A2, G2, E2, D2
    @makeSynthNote: 82.41, 0.5
    id1 = selected("Sound")
    
    @makeSynthNote: 98.00, 0.5
    id2 = selected("Sound")
    
    @makeSynthNote: 110.00, 0.5
    id3 = selected("Sound")
    
    @makeSynthNote: 130.81, 0.7
    id4 = selected("Sound")
    
    @makeSynthNote: 110.00, 0.5
    id5 = selected("Sound")
    
    @makeSynthNote: 98.00, 0.5
    id6 = selected("Sound")
    
    @makeSynthNote: 82.41, 0.5
    id7 = selected("Sound")
    
    @makeSynthNote: 73.42, 0.9
    id8 = selected("Sound")
    
    # Concatenate
    selectObject: id1, id2, id3, id4, id5, id6, id7, id8
    Concatenate
    sound = selected("Sound")
    Rename: "VectorSynth_Melody"
    
    removeObject: id1, id2, id3, id4, id5, id6, id7, id8
    
    selectObject: sound
    total_duration = Get total duration
else
    # Single note
    @makeSynthNote: frequency_Hz, duration_s
    sound = selected("Sound")
    Rename: "VectorSynth"
    total_duration = duration_s
endif

# Normalize
selectObject: sound
Scale peak: 0.95

# Visualization
if draw_visualization
    @drawVisualization: total_duration
endif

# Playback
if play_result
    selectObject: sound
    Play
endif

selectObject: sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: makeSynthNote - Generate one note
# ==============================================================================
procedure makeSynthNote: .freq, .dur
    
    path_cycles_local = path_speed * .dur
    
    # === Generate Four Oscillators ===
    
    # Oscillator A: Sawtooth
    Create Sound from formula: "OscA", 1, 0, .dur, sampling_rate, 
        ... "2 * (x * .freq - floor(x * .freq + 0.5))"
    
    # Oscillator B: Square
    Create Sound from formula: "OscB", 1, 0, .dur, sampling_rate,
        ... "if x * .freq mod 1 < 0.5 then 1 else -1 fi"
    
    # Oscillator C: Triangle
    Create Sound from formula: "OscC", 1, 0, .dur, sampling_rate,
        ... "4 * abs((x * .freq mod 1) - 0.5) - 1"
    
    # Oscillator D: Sine
    Create Sound from formula: "OscD", 1, 0, .dur, sampling_rate,
        ... "sin(twoPi * .freq * x)"
    
    # === Generate Vector Path ===
    
    # X-Coordinate
    Create Sound from formula: "VectorX", 1, 0, .dur, sampling_rate, "0"
    if path_type$ = "Circle"
        Formula: "0.5 + 0.4 * cos(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Ellipse"
        Formula: "0.5 + 0.45 * cos(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Lissajous (3:2)"
        Formula: "0.5 + 0.4 * sin(3 * twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Figure-8"
        Formula: "0.5 + 0.4 * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Spiral In"
        Formula: "0.5 + 0.45 * (1 - x/.dur) * cos(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Spiral Out"
        Formula: "0.5 + 0.45 * (x/.dur) * cos(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Square Path"
        Formula: "0.5 + 0.4 * ((floor(4 * path_cycles_local * x / .dur) mod 4 < 2) * 2 - 1)"
    elsif path_type$ = "Star"
        Formula: "0.5 + 0.4 * (0.5 + 0.5 * cos(10 * pi * path_cycles_local * x / .dur)) * cos(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Infinity Loop"
        Formula: "0.5 + 0.35 * cos(twoPi * path_cycles_local * x / .dur) / (1 + sin(twoPi * path_cycles_local * x / .dur)^2)"
    elsif path_type$ = "Butterfly"
        Formula: "0.5 + 0.35 * sin(twoPi * path_cycles_local * x / .dur) * (exp(cos(twoPi * path_cycles_local * x / .dur)) - 2 * cos(4 * twoPi * path_cycles_local * x / .dur)) / 5"
    elsif path_type$ = "Rose Curve"
        Formula: "0.5 + 0.4 * cos(5 * twoPi * path_cycles_local * x / .dur) * cos(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Chaotic Attractor"
        Formula: "0.5 + 0.3 * sin(twoPi * path_cycles_local * x / .dur) * cos(3.7 * twoPi * path_cycles_local * x / .dur)"
    endif
    
    # Y-Coordinate
    Create Sound from formula: "VectorY", 1, 0, .dur, sampling_rate, "0"
    if path_type$ = "Circle"
        Formula: "0.5 + 0.4 * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Ellipse"
        Formula: "0.5 + 0.3 * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Lissajous (3:2)"
        Formula: "0.5 + 0.4 * sin(2 * twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Figure-8"
        Formula: "0.5 + 0.4 * sin(4 * pi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Spiral In"
        Formula: "0.5 + 0.45 * (1 - x/.dur) * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Spiral Out"
        Formula: "0.5 + 0.45 * (x/.dur) * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Square Path"
        Formula: "0.5 + 0.4 * ((floor(4 * path_cycles_local * x / .dur + 1) mod 4 < 2) * 2 - 1)"
    elsif path_type$ = "Star"
        Formula: "0.5 + 0.4 * (0.5 + 0.5 * cos(10 * pi * path_cycles_local * x / .dur)) * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Infinity Loop"
        Formula: "0.5 + 0.35 * sin(twoPi * path_cycles_local * x / .dur) * cos(twoPi * path_cycles_local * x / .dur) / (1 + sin(twoPi * path_cycles_local * x / .dur)^2)"
    elsif path_type$ = "Butterfly"
        Formula: "0.5 + 0.35 * cos(twoPi * path_cycles_local * x / .dur) * (exp(cos(twoPi * path_cycles_local * x / .dur)) - 2 * cos(4 * twoPi * path_cycles_local * x / .dur)) / 5"
    elsif path_type$ = "Rose Curve"
        Formula: "0.5 + 0.4 * cos(5 * twoPi * path_cycles_local * x / .dur) * sin(twoPi * path_cycles_local * x / .dur)"
    elsif path_type$ = "Chaotic Attractor"
        Formula: "0.5 + 0.3 * cos(twoPi * path_cycles_local * x / .dur) * sin(2.3 * twoPi * path_cycles_local * x / .dur)"
    endif
    
    # === Vector Mixing (Bilinear Interpolation) ===
    
    Create Sound from formula: "VectorSynth_temp", 1, 0, .dur, sampling_rate, "0"
    
    Formula: "
    ... (1 - Sound_VectorX[]) * (1 - Sound_VectorY[]) * Sound_OscA[] +
    ...      Sound_VectorX[]  * (1 - Sound_VectorY[]) * Sound_OscB[] +
    ... (1 - Sound_VectorX[]) * Sound_VectorY[]  * Sound_OscC[] +
    ...      Sound_VectorX[]  * Sound_VectorY[]  * Sound_OscD[]
    ... "
    
    # Fade in/out
    Fade in: 0, 0, 0.005, "yes"
    Fade out: 0, .dur - 0.01, 0.01, "yes"
    
    .result = selected("Sound")
    
    # Cleanup
    removeObject: "Sound OscA", "Sound OscB", "Sound OscC", "Sound OscD"
    removeObject: "Sound VectorX", "Sound VectorY"
    
    selectObject: .result
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization: .totalDur
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Vector Synthesis: " + path_type$
    
    # === Vector Space ===
    Select outer viewport: 0, 7, 0.7, 7.7
    Select inner viewport: 0.8, 6.2, 1.2, 7.2
    
    Axes: 0, 1, 0, 1
    
    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 0.5
    Dotted line
    for .i from 1 to 4
        Draw line: .i/5, 0, .i/5, 1
        Draw line: 0, .i/5, 1, .i/5
    endfor
    Solid line
    
    # Boundary
    Colour: "Black"
    Line width: 2
    Draw line: 0, 0, 1, 0
    Draw line: 1, 0, 1, 1
    Draw line: 1, 1, 0, 1
    Draw line: 0, 1, 0, 0
    
    # Corner nodes
    for .corner from 1 to 4
        if .corner = 1
            .cx = 0
            .cy = 0
            .col$ = "{0.2, 0.4, 0.8}"
            .label$ = "SAW"
        elsif .corner = 2
            .cx = 1
            .cy = 0
            .col$ = "{0.8, 0.3, 0.2}"
            .label$ = "SQR"
        elsif .corner = 3
            .cx = 0
            .cy = 1
            .col$ = "{0.3, 0.7, 0.3}"
            .label$ = "TRI"
        else
            .cx = 1
            .cy = 1
            .col$ = "{0.7, 0.2, 0.7}"
            .label$ = "SIN"
        endif
        
        Colour: .col$
        Paint circle (mm): .col$, .cx, .cy, 3
        Colour: "White"
        Paint circle (mm): "White", .cx, .cy, 1.2
        
        Colour: "Black"
        Font size: 9
        Text: .cx, "centre", .cy - 0.08, "top", .label$
    endfor
    
    # Draw vector path
    .steps = 800
    .safeDur = .totalDur - (1.0 / sampling_rate)
    
    if show_trail
        # Gradient trail
        for .i from 1 to .steps
            .t1 = (.i - 1) * (.totalDur / .steps)
            .t2 = .i * (.totalDur / .steps)
            
            if .t2 > .safeDur
                .t2 = .safeDur
            endif
            
            # Calculate path coordinates based on selected preset
            @getPathCoords: .t1, .totalDur
            .x1 = getPathCoords.x
            .y1 = getPathCoords.y
            
            @getPathCoords: .t2, .totalDur
            .x2 = getPathCoords.x
            .y2 = getPathCoords.y
            
            .intensity = .i / .steps
            .red = 0.9 * .intensity + 0.1
            .green = 0.1
            .blue = 0.9 * (1 - .intensity) + 0.1
            
            .lineWidth = 1.5 + 1.2 * .intensity
            
            Colour: "{" + string$(.red) + ", " + string$(.green) + ", " + string$(.blue) + "}"
            Line width: .lineWidth
            
            if .x1 <> undefined and .x2 <> undefined
                Draw line: .x1, .y1, .x2, .y2
            endif
        endfor
    else
        # Solid path
        Colour: "{0.9, 0.1, 0.3}"
        Line width: 2.5
        
        for .i from 1 to .steps
            .t1 = (.i - 1) * (.totalDur / .steps)
            .t2 = .i * (.totalDur / .steps)
            
            if .t2 > .safeDur
                .t2 = .safeDur
            endif
            
            @getPathCoords: .t1, .totalDur
            .x1 = getPathCoords.x
            .y1 = getPathCoords.y
            
            @getPathCoords: .t2, .totalDur
            .x2 = getPathCoords.x
            .y2 = getPathCoords.y
            
            if .x1 <> undefined and .x2 <> undefined
                Draw line: .x1, .y1, .x2, .y2
            endif
        endfor
    endif
    
    # Start/End markers
    @getPathCoords: 0, .totalDur
    .x_start = getPathCoords.x
    .y_start = getPathCoords.y
    
    Colour: "{0.0, 0.8, 0.0}"
    Paint circle (mm): "{0.0, 0.8, 0.0}", .x_start, .y_start, 2.5
    Colour: "White"
    Paint circle (mm): "White", .x_start, .y_start, 1
    
    # Legend
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", -0.08, "bottom", "Duration: " + fixed$(.totalDur, 1) + " s  •  Speed: " + string$(path_speed) + " cycles/s"
    
    Colour: "Black"
    Font size: 10
    Line width: 1
endproc

# ==============================================================================
# Procedure: getPathCoords - Calculate X,Y for current time and preset
# ==============================================================================
procedure getPathCoords: .t, .dur
    .phase = path_speed * .t
    
    if path_type$ = "Circle"
        .x = 0.5 + 0.4 * cos(twoPi * .phase)
        .y = 0.5 + 0.4 * sin(twoPi * .phase)
    elsif path_type$ = "Ellipse"
        .x = 0.5 + 0.45 * cos(twoPi * .phase)
        .y = 0.5 + 0.3 * sin(twoPi * .phase)
    elsif path_type$ = "Lissajous (3:2)"
        .x = 0.5 + 0.4 * sin(3 * twoPi * .phase)
        .y = 0.5 + 0.4 * sin(2 * twoPi * .phase)
    elsif path_type$ = "Figure-8"
        .x = 0.5 + 0.4 * sin(twoPi * .phase)
        .y = 0.5 + 0.4 * sin(4 * pi * .phase)
    elsif path_type$ = "Spiral In"
        .progress = .t / .dur
        .x = 0.5 + 0.45 * (1 - .progress) * cos(twoPi * .phase)
        .y = 0.5 + 0.45 * (1 - .progress) * sin(twoPi * .phase)
    elsif path_type$ = "Spiral Out"
        .progress = .t / .dur
        .x = 0.5 + 0.45 * .progress * cos(twoPi * .phase)
        .y = 0.5 + 0.45 * .progress * sin(twoPi * .phase)
    elsif path_type$ = "Square Path"
        .quadrant = floor(4 * .phase) mod 4
        if .quadrant = 0
            .x = 0.9
            .y = 0.1
        elsif .quadrant = 1
            .x = 0.9
            .y = 0.9
        elsif .quadrant = 2
            .x = 0.1
            .y = 0.9
        else
            .x = 0.1
            .y = 0.1
        endif
    elsif path_type$ = "Star"
        .radius = 0.5 + 0.5 * cos(10 * pi * .phase)
        .x = 0.5 + 0.4 * .radius * cos(twoPi * .phase)
        .y = 0.5 + 0.4 * .radius * sin(twoPi * .phase)
    elsif path_type$ = "Infinity Loop"
        .denom = 1 + sin(twoPi * .phase)^2
        .x = 0.5 + 0.35 * cos(twoPi * .phase) / .denom
        .y = 0.5 + 0.35 * sin(twoPi * .phase) * cos(twoPi * .phase) / .denom
    elsif path_type$ = "Butterfly"
        .scale = (exp(cos(twoPi * .phase)) - 2 * cos(4 * twoPi * .phase)) / 5
        .x = 0.5 + 0.35 * sin(twoPi * .phase) * .scale
        .y = 0.5 + 0.35 * cos(twoPi * .phase) * .scale
    elsif path_type$ = "Rose Curve"
        .radius = cos(5 * twoPi * .phase)
        .x = 0.5 + 0.4 * .radius * cos(twoPi * .phase)
        .y = 0.5 + 0.4 * .radius * sin(twoPi * .phase)
    elsif path_type$ = "Chaotic Attractor"
        .x = 0.5 + 0.3 * sin(twoPi * .phase) * cos(3.7 * twoPi * .phase)
        .y = 0.5 + 0.3 * cos(twoPi * .phase) * sin(2.3 * twoPi * .phase)
    endif
endproc