# ============================================================
# Praat AudioTools - Vector Synthesis (Prophet VS-inspired)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Four-source vector synthesis using bilinear interpolation.
#   A 2-D path controls the amplitudes of SAW / SQR / TRI / SIN sources.
#
# v0.5 review changes:
#   - Process-oriented visualization: XY path -> bilinear weights -> sources -> output.
#   - Fixed Square Path: continuous motion along edges instead of corner jumps.
#   - Melody Demo now uses one continuous global vector path across all notes.
#   - PolyBLEP correction for saw and square discontinuities to reduce aliasing.
#   - Renamed "Chaotic Attractor" to "Quasi-Chaotic Curve" (deterministic trigonometric path).
#   - Compact main form; sample rate, output peak and trail moved to Edit details.
#   - Explicit validation and QC; separate viewports for titles/text/data.
# ============================================================

form Vector Synthesis
    comment === Mode and vector path ===
    optionmenu Synthesis_mode: 1
        option Single note
        option Melody demo
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
        option Quasi-Chaotic Curve
    real Path_speed_cycles_per_s 0.5

    comment === Single-note controls ===
    positive Duration_s 6.0
    positive Frequency_Hz 110

    comment === Output ===
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

sample_rate_Hz = 44100
output_peak = 0.95
show_trail = 1
if edit_details
    beginPause: "Vector Synthesis - details"
        positive: "Sample rate Hz", sample_rate_Hz
        positive: "Output peak", output_peak
        boolean: "Show trail", show_trail
    endPause: "OK", 1
endif

sampling_rate = sample_rate_Hz
path_speed = path_speed_cycles_per_s
twoPi = 2 * pi

# === Validation ===
if path_speed < 0
    exitScript: "Path speed must be zero or positive."
endif
if sampling_rate < 2000
    exitScript: "Sample rate is too low for this synthesizer."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in the interval (0, 1]."
endif
if synthesis_mode$ = "Single note"
    if frequency_Hz >= 0.45 * sampling_rate
        exitScript: "Frequency is too close to Nyquist for the oscillator set. Increase sample rate or lower Frequency."
    endif
endif

writeInfoLine: "=== VECTOR SYNTHESIS ==="
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: "Path: ", path_type$
appendInfoLine: "Path speed: ", fixed$(path_speed, 3), " cycles/s"
appendInfoLine: ""

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

if synthesis_mode$ = "Melody demo"
    appendInfoLine: "Generating melody demo with a continuous global vector path..."

    # Bass melody: E2, G2, A2, C3, A2, G2, E2, D2
    total_duration = 4.6
    .offset = 0

    @makeSynthNote: 82.41, 0.5, .offset, total_duration
    id1 = selected("Sound")
    .offset = .offset + 0.5

    @makeSynthNote: 98.00, 0.5, .offset, total_duration
    id2 = selected("Sound")
    .offset = .offset + 0.5

    @makeSynthNote: 110.00, 0.5, .offset, total_duration
    id3 = selected("Sound")
    .offset = .offset + 0.5

    @makeSynthNote: 130.81, 0.7, .offset, total_duration
    id4 = selected("Sound")
    .offset = .offset + 0.7

    @makeSynthNote: 110.00, 0.5, .offset, total_duration
    id5 = selected("Sound")
    .offset = .offset + 0.5

    @makeSynthNote: 98.00, 0.5, .offset, total_duration
    id6 = selected("Sound")
    .offset = .offset + 0.5

    @makeSynthNote: 82.41, 0.5, .offset, total_duration
    id7 = selected("Sound")
    .offset = .offset + 0.5

    @makeSynthNote: 73.42, 0.9, .offset, total_duration
    id8 = selected("Sound")

    selectObject: id1, id2, id3, id4, id5, id6, id7, id8
    Concatenate
    sound = selected("Sound")
    Rename: "VectorSynth_Melody"

    removeObject: id1, id2, id3, id4, id5, id6, id7, id8
else
    total_duration = duration_s
    @makeSynthNote: frequency_Hz, duration_s, 0, total_duration
    sound = selected("Sound")
    Rename: "VectorSynth"
endif

selectObject: sound
Subtract mean
Scale peak: output_peak

output_max_sample = Get maximum: 0, 0, "None"
output_min_sample = Get minimum: 0, 0, "None"
output_peak_measured = max(abs(output_max_sample), abs(output_min_sample))
output_rms = Get root-mean-square: 0, 0

if draw_visualization
    @drawVisualization: total_duration
endif

if play_result
    selectObject: sound
    Play
endif

selectObject: sound
appendInfoLine: ""
appendInfoLine: "Output peak: ", fixed$(output_peak_measured, 4), "   RMS: ", fixed$(output_rms, 4)
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: makeSynthNote
# Vector time is GLOBAL (.offset + local x), oscillator phase is local to each note.
# ==============================================================================
procedure makeSynthNote: .freq, .dur, .offset, .pieceDur
    if .freq >= 0.45 * sampling_rate
        exitScript: "A melody frequency is too close to Nyquist for the oscillator set."
    endif

    .dt = .freq / sampling_rate

    # === Four source oscillators ===
    # A: rising saw with PolyBLEP correction at the wrap discontinuity.
    Create Sound from formula: "OscA", 1, 0, .dur, sampling_rate,
        ... "2*(((x*.freq+0.5) mod 1))-1 - (if ((x*.freq+0.5) mod 1) < .dt then 2*((x*.freq+0.5) mod 1)/.dt - (((x*.freq+0.5) mod 1)/.dt)^2 - 1 else if ((x*.freq+0.5) mod 1) > 1-.dt then ((((x*.freq+0.5) mod 1)-1)/.dt)^2 + 2*(((x*.freq+0.5) mod 1)-1)/.dt + 1 else 0 fi fi)"

    # B: square with PolyBLEP correction at both discontinuities.
    Create Sound from formula: "OscB", 1, 0, .dur, sampling_rate,
        ... "(if ((x*.freq) mod 1) < 0.5 then 1 else -1 fi) + (if ((x*.freq) mod 1) < .dt then 2*((x*.freq) mod 1)/.dt - (((x*.freq) mod 1)/.dt)^2 - 1 else if ((x*.freq) mod 1) > 1-.dt then ((((x*.freq) mod 1)-1)/.dt)^2 + 2*(((x*.freq) mod 1)-1)/.dt + 1 else 0 fi fi) - (if ((((x*.freq) mod 1)+0.5) mod 1) < .dt then 2*((((x*.freq) mod 1)+0.5) mod 1)/.dt - (((((x*.freq) mod 1)+0.5) mod 1)/.dt)^2 - 1 else if ((((x*.freq) mod 1)+0.5) mod 1) > 1-.dt then ((((((x*.freq) mod 1)+0.5) mod 1)-1)/.dt)^2 + 2*(((((x*.freq) mod 1)+0.5) mod 1)-1)/.dt + 1 else 0 fi fi)"

    # C: triangle (harmonics decay as 1/h^2, hence much less alias-prone).
    Create Sound from formula: "OscC", 1, 0, .dur, sampling_rate,
        ... "4 * abs(((x * .freq) mod 1) - 0.5) - 1"

    # D: sine.
    Create Sound from formula: "OscD", 1, 0, .dur, sampling_rate,
        ... "sin(twoPi * .freq * x)"

    # === Global vector path controls ===
    Create Sound from formula: "VectorX", 1, 0, .dur, sampling_rate, "0"
    if path_type$ = "Circle"
        Formula: "0.5 + 0.4 * cos(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Ellipse"
        Formula: "0.5 + 0.45 * cos(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Lissajous (3:2)"
        Formula: "0.5 + 0.4 * sin(3 * twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Figure-8"
        Formula: "0.5 + 0.4 * sin(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Spiral In"
        Formula: "0.5 + 0.45 * (1 - (.offset + x)/.pieceDur) * cos(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Spiral Out"
        Formula: "0.5 + 0.45 * ((.offset + x)/.pieceDur) * cos(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Square Path"
        Formula: "if ((path_speed*(.offset+x)) mod 1) < 0.25 then 0.1 + 3.2*((path_speed*(.offset+x)) mod 1) else if ((path_speed*(.offset+x)) mod 1) < 0.5 then 0.9 else if ((path_speed*(.offset+x)) mod 1) < 0.75 then 0.9 - 3.2*(((path_speed*(.offset+x)) mod 1)-0.5) else 0.1 fi fi fi"
    elsif path_type$ = "Star"
        Formula: "0.5 + 0.4 * (0.5 + 0.5*cos(10*pi*path_speed*(.offset+x))) * cos(twoPi*path_speed*(.offset+x))"
    elsif path_type$ = "Infinity Loop"
        Formula: "0.5 + 0.35*cos(twoPi*path_speed*(.offset+x)) / (1 + sin(twoPi*path_speed*(.offset+x))^2)"
    elsif path_type$ = "Butterfly"
        Formula: "0.5 + 0.35*sin(twoPi*path_speed*(.offset+x)) * (exp(cos(twoPi*path_speed*(.offset+x))) - 2*cos(4*twoPi*path_speed*(.offset+x))) / 5"
    elsif path_type$ = "Rose Curve"
        Formula: "0.5 + 0.4*cos(5*twoPi*path_speed*(.offset+x))*cos(twoPi*path_speed*(.offset+x))"
    elsif path_type$ = "Quasi-Chaotic Curve" or path_type$ = "Chaotic Attractor"
        Formula: "0.5 + 0.3*sin(twoPi*path_speed*(.offset+x))*cos(3.7*twoPi*path_speed*(.offset+x))"
    endif

    Create Sound from formula: "VectorY", 1, 0, .dur, sampling_rate, "0"
    if path_type$ = "Circle"
        Formula: "0.5 + 0.4 * sin(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Ellipse"
        Formula: "0.5 + 0.3 * sin(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Lissajous (3:2)"
        Formula: "0.5 + 0.4 * sin(2 * twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Figure-8"
        Formula: "0.5 + 0.4 * sin(2 * twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Spiral In"
        Formula: "0.5 + 0.45 * (1 - (.offset + x)/.pieceDur) * sin(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Spiral Out"
        Formula: "0.5 + 0.45 * ((.offset + x)/.pieceDur) * sin(twoPi * path_speed * (.offset + x))"
    elsif path_type$ = "Square Path"
        Formula: "if ((path_speed*(.offset+x)) mod 1) < 0.25 then 0.1 else if ((path_speed*(.offset+x)) mod 1) < 0.5 then 0.1 + 3.2*(((path_speed*(.offset+x)) mod 1)-0.25) else if ((path_speed*(.offset+x)) mod 1) < 0.75 then 0.9 else 0.9 - 3.2*(((path_speed*(.offset+x)) mod 1)-0.75) fi fi fi"
    elsif path_type$ = "Star"
        Formula: "0.5 + 0.4 * (0.5 + 0.5*cos(10*pi*path_speed*(.offset+x))) * sin(twoPi*path_speed*(.offset+x))"
    elsif path_type$ = "Infinity Loop"
        Formula: "0.5 + 0.35*sin(twoPi*path_speed*(.offset+x))*cos(twoPi*path_speed*(.offset+x)) / (1 + sin(twoPi*path_speed*(.offset+x))^2)"
    elsif path_type$ = "Butterfly"
        Formula: "0.5 + 0.35*cos(twoPi*path_speed*(.offset+x)) * (exp(cos(twoPi*path_speed*(.offset+x))) - 2*cos(4*twoPi*path_speed*(.offset+x))) / 5"
    elsif path_type$ = "Rose Curve"
        Formula: "0.5 + 0.4*cos(5*twoPi*path_speed*(.offset+x))*sin(twoPi*path_speed*(.offset+x))"
    elsif path_type$ = "Quasi-Chaotic Curve" or path_type$ = "Chaotic Attractor"
        Formula: "0.5 + 0.3*cos(twoPi*path_speed*(.offset+x))*sin(2.3*twoPi*path_speed*(.offset+x))"
    endif

    # === Bilinear interpolation ===
    # wA=(1-x)(1-y), wB=x(1-y), wC=(1-x)y, wD=xy; weights sum to 1.
    Create Sound from formula: "VectorSynth_temp", 1, 0, .dur, sampling_rate, "0"
    Formula: "(1-Sound_VectorX[])*(1-Sound_VectorY[])*Sound_OscA[] + Sound_VectorX[]*(1-Sound_VectorY[])*Sound_OscB[] + (1-Sound_VectorX[])*Sound_VectorY[]*Sound_OscC[] + Sound_VectorX[]*Sound_VectorY[]*Sound_OscD[]"

    # Smooth note edges; these are articulation fades, not part of vector interpolation.
    .fadeIn = min(0.005, .dur/4)
    .fadeOut = min(0.010, .dur/4)
    Fade in: 0, 0, .fadeIn, "yes"
    Fade out: 0, .dur - .fadeOut, .fadeOut, "yes"

    .result = selected("Sound")
    removeObject: "Sound OscA", "Sound OscB", "Sound OscC", "Sound OscD", "Sound VectorX", "Sound VectorY"
    selectObject: .result
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization: .totalDur
    Erase all

    # ---------- Header ----------
    Select outer viewport: 0, 8, 0.0, 0.42
    Select inner viewport: 0.35, 7.65, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.60, "half", "##Vector Synthesis##  |  " + path_type$

    Select outer viewport: 0, 8, 0.43, 0.78
    Select inner viewport: 0.35, 7.65, 0.46, 0.74
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.35, 0.35, 0.43}"
    Text: 0.5, "centre", 0.55, "half", "2-D path  ->  bilinear weights  ->  SAW / SQR / TRI / SIN  ->  weighted sum  ->  output"

    # ---------- Panel A title ----------
    Select outer viewport: 0.15, 4.05, 0.82, 1.12
    Select inner viewport: 0.25, 3.95, 0.85, 1.08
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "##A  Vector trajectory in oscillator space##"

    # ---------- Panel A data ----------
    Select outer viewport: 0.15, 4.05, 1.14, 4.70
    Select inner viewport: 0.62, 3.72, 1.35, 4.48
    Axes: 0, 1, 0, 1

    Colour: "{0.90, 0.90, 0.90}"
    Line width: 0.6
    Dotted line
    for .i from 1 to 4
        Draw line: .i/5, 0, .i/5, 1
        Draw line: 0, .i/5, 1, .i/5
    endfor
    Solid line
    Colour: "Black"
    Line width: 1
    Draw inner box

    # Corner source nodes.
    Colour: "{0.20, 0.42, 0.82}"
    Paint circle (mm): "{0.20, 0.42, 0.82}", 0, 0, 2.5
    Colour: "{0.82, 0.30, 0.20}"
    Paint circle (mm): "{0.82, 0.30, 0.20}", 1, 0, 2.5
    Colour: "{0.28, 0.68, 0.32}"
    Paint circle (mm): "{0.28, 0.68, 0.32}", 0, 1, 2.5
    Colour: "{0.68, 0.24, 0.70}"
    Paint circle (mm): "{0.68, 0.24, 0.70}", 1, 1, 2.5

    # Re-select data world before labels/trajectory.
    Select inner viewport: 0.62, 3.72, 1.35, 4.48
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.05, "bottom", "A  SAW"
    Text: 0.98, "right", 0.05, "bottom", "B  SQR"
    Text: 0.02, "left", 0.95, "top", "C  TRI"
    Text: 0.98, "right", 0.95, "top", "D  SIN"

    .steps = 600
    .sumA = 0
    .sumB = 0
    .sumC = 0
    .sumD = 0
    .maxWeightError = 0
    .minX = 1e30
    .maxX = -1e30
    .minY = 1e30
    .maxY = -1e30

    for .i from 1 to .steps
        .t1 = (.i - 1) * .totalDur / .steps
        .t2 = .i * .totalDur / .steps
        @getPathCoords: .t1, .totalDur
        .x1 = getPathCoords.x
        .y1 = getPathCoords.y
        @getPathCoords: .t2, .totalDur
        .x2 = getPathCoords.x
        .y2 = getPathCoords.y

        if show_trail
            .q = .i / .steps
            .r = 0.12 + 0.76 * .q
            .g = 0.16
            .b = 0.88 - 0.68 * .q
            Colour: "{" + fixed$(.r, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(.b, 3) + "}"
            Line width: 1.2 + 1.0*.q
        else
            Colour: "{0.32, 0.18, 0.66}"
            Line width: 2
        endif
        Draw line: .x1, .y1, .x2, .y2

        .wA = (1-.x1)*(1-.y1)
        .wB = .x1*(1-.y1)
        .wC = (1-.x1)*.y1
        .wD = .x1*.y1
        .sumA = .sumA + .wA
        .sumB = .sumB + .wB
        .sumC = .sumC + .wC
        .sumD = .sumD + .wD
        .err = abs(.wA+.wB+.wC+.wD-1)
        if .err > .maxWeightError
            .maxWeightError = .err
        endif
        if .x1 < .minX
            .minX = .x1
        endif
        if .x1 > .maxX
            .maxX = .x1
        endif
        if .y1 < .minY
            .minY = .y1
        endif
        if .y1 > .maxY
            .maxY = .y1
        endif
    endfor

    @getPathCoords: 0, .totalDur
    Colour: "{0.05, 0.65, 0.15}"
    Paint circle (mm): "{0.05, 0.65, 0.15}", getPathCoords.x, getPathCoords.y, 2.2
    @getPathCoords: .totalDur, .totalDur
    Colour: "Black"
    Draw circle (mm): getPathCoords.x, getPathCoords.y, 2.0

    # ---------- Panel B title ----------
    Select outer viewport: 4.10, 7.85, 0.82, 1.12
    Select inner viewport: 4.20, 7.75, 0.85, 1.08
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "##B  Bilinear source weights##"

    # ---------- Panel B data ----------
    Select outer viewport: 4.10, 7.85, 1.14, 4.70
    Select inner viewport: 4.55, 7.68, 1.35, 4.48
    Axes: 0, .totalDur, 0, 1
    Colour: "{0.93, 0.93, 0.93}"
    Line width: 0.5
    Dotted line
    Draw line: 0, 0.25, .totalDur, 0.25
    Draw line: 0, 0.50, .totalDur, 0.50
    Draw line: 0, 0.75, .totalDur, 0.75
    Solid line
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks bottom: 4, "yes", "yes", "no"
    Marks left: 4, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Weight"

    # Weight trajectories.
    for .i from 1 to 500
        .t1 = (.i-1)*.totalDur/500
        .t2 = .i*.totalDur/500
        @getPathCoords: .t1, .totalDur
        .xa = getPathCoords.x
        .ya = getPathCoords.y
        @getPathCoords: .t2, .totalDur
        .xb = getPathCoords.x
        .yb = getPathCoords.y

        .a1=(1-.xa)*(1-.ya)
        .b1=.xa*(1-.ya)
        .c1=(1-.xa)*.ya
        .d1=.xa*.ya
        .a2=(1-.xb)*(1-.yb)
        .b2=.xb*(1-.yb)
        .c2=(1-.xb)*.yb
        .d2=.xb*.yb

        Colour: "{0.20, 0.42, 0.82}"
        Line width: 1.2
        Draw line: .t1, .a1, .t2, .a2
        Colour: "{0.82, 0.30, 0.20}"
        Draw line: .t1, .b1, .t2, .b2
        Colour: "{0.28, 0.68, 0.32}"
        Draw line: .t1, .c1, .t2, .c2
        Colour: "{0.68, 0.24, 0.70}"
        Draw line: .t1, .d1, .t2, .d2
    endfor

    Select inner viewport: 4.55, 7.68, 1.35, 4.48
    Axes: 0, .totalDur, 0, 1
    Font size: 7
    Colour: "{0.20, 0.42, 0.82}"
    Text: 0.03*.totalDur, "left", 0.94, "half", "A"
    Colour: "{0.82, 0.30, 0.20}"
    Text: 0.12*.totalDur, "left", 0.94, "half", "B"
    Colour: "{0.28, 0.68, 0.32}"
    Text: 0.21*.totalDur, "left", 0.94, "half", "C"
    Colour: "{0.68, 0.24, 0.70}"
    Text: 0.30*.totalDur, "left", 0.94, "half", "D"

    # Melody note boundaries clarify that the path does NOT restart.
    if synthesis_mode$ = "Melody demo"
        Dotted line
        Colour: "{0.55, 0.55, 0.55}"
        .bt = 0.5
        Draw line: .bt, 0, .bt, 1
        .bt = 1.0
        Draw line: .bt, 0, .bt, 1
        .bt = 1.5
        Draw line: .bt, 0, .bt, 1
        .bt = 2.2
        Draw line: .bt, 0, .bt, 1
        .bt = 2.7
        Draw line: .bt, 0, .bt, 1
        .bt = 3.2
        Draw line: .bt, 0, .bt, 1
        .bt = 3.7
        Draw line: .bt, 0, .bt, 1
        Solid line
    endif

    # ---------- Panel C title ----------
    Select outer viewport: 0.15, 4.05, 4.75, 5.04
    Select inner viewport: 0.25, 3.95, 4.78, 5.00
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "##C  Corner source waveforms##"

    # ---------- Panel C data ----------
    Select outer viewport: 0.15, 4.05, 5.06, 6.62
    Select inner viewport: 0.60, 3.78, 5.18, 6.50
    Axes: 0, 1, 0, 4
    Colour: "Black"
    Line width: 1
    Draw inner box

    if synthesis_mode$ = "Melody demo"
        .displayFreq = 82.41
    else
        .displayFreq = frequency_Hz
    endif
    .displayDt = .displayFreq / sampling_rate

    # Row centres: A=3.5, B=2.5, C=1.5, D=0.5.
    for .i from 1 to 160
        .p1 = (.i-1)/160
        .p2 = .i/160
        if .p2 >= 1
            .p2 = 0.999999
        endif
        @getOscValues: .p1, .displayDt
        .a1=getOscValues.a
        .b1=getOscValues.b
        .c1=getOscValues.c
        .d1=getOscValues.d
        @getOscValues: .p2, .displayDt
        .a2=getOscValues.a
        .b2=getOscValues.b
        .c2=getOscValues.c
        .d2=getOscValues.d

        Colour: "{0.20, 0.42, 0.82}"
        Line width: 1.1
        Draw line: .p1, 3.5+0.32*.a1, .p2, 3.5+0.32*.a2
        Colour: "{0.82, 0.30, 0.20}"
        Draw line: .p1, 2.5+0.32*.b1, .p2, 2.5+0.32*.b2
        Colour: "{0.28, 0.68, 0.32}"
        Draw line: .p1, 1.5+0.32*.c1, .p2, 1.5+0.32*.c2
        Colour: "{0.68, 0.24, 0.70}"
        Draw line: .p1, 0.5+0.32*.d1, .p2, 0.5+0.32*.d2
    endfor

    Select inner viewport: 0.60, 3.78, 5.18, 6.50
    Axes: 0, 1, 0, 4
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 3.83, "half", "A SAW"
    Text: 0.02, "left", 2.83, "half", "B SQR"
    Text: 0.02, "left", 1.83, "half", "C TRI"
    Text: 0.02, "left", 0.83, "half", "D SIN"
    Text: 0.98, "right", 0.12, "half", "one normalized period"

    # ---------- Panel D title ----------
    Select outer viewport: 4.10, 7.85, 4.75, 5.04
    Select inner viewport: 4.20, 7.75, 4.78, 5.00
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "##D  Measured output##"

    # ---------- Panel D data ----------
    Select outer viewport: 4.10, 7.85, 5.06, 6.62
    Select inner viewport: 4.55, 7.68, 5.18, 6.50
    selectObject: sound
    Draw: 0, .totalDur, -1.05*output_peak, 1.05*output_peak, "no", "curve"
    Select inner viewport: 4.55, 7.68, 5.18, 6.50
    Axes: 0, .totalDur, -1.05*output_peak, 1.05*output_peak
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks bottom: 4, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Marks left: 2, "yes", "yes", "no"

    # ---------- QC summary ----------
    .meanA = .sumA/.steps
    .meanB = .sumB/.steps
    .meanC = .sumC/.steps
    .meanD = .sumD/.steps

    Select outer viewport: 0.15, 7.85, 6.72, 7.92
    Select inner viewport: 0.35, 7.65, 6.78, 7.86
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.945, 0.945, 0.945}", 0, 1, 0, 1
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0.333, 0.08, 0.333, 0.92
    Draw line: 0.666, 0.08, 0.666, 0.92
    Draw line: 0.02, 0.50, 0.98, 0.50

    Font size: 7.5
    Colour: "Black"
    Text: 0.02, "left", 0.74, "half", "Path  " + path_type$ + "  |  " + fixed$(path_speed,2) + " cyc/s"
    Text: 0.35, "left", 0.74, "half", "XY range  x=" + fixed$(.minX,2) + ".." + fixed$(.maxX,2) + "  y=" + fixed$(.minY,2) + ".." + fixed$(.maxY,2)
    Text: 0.68, "left", 0.74, "half", "Weight-sum error  " + fixed$(.maxWeightError,12)

    Text: 0.02, "left", 0.26, "half", "Mean weights  A " + fixed$(.meanA,2) + "  B " + fixed$(.meanB,2)
    Text: 0.35, "left", 0.26, "half", "Mean weights  C " + fixed$(.meanC,2) + "  D " + fixed$(.meanD,2)
    Text: 0.68, "left", 0.26, "half", "Output  peak " + fixed$(output_peak_measured,3) + "  RMS " + fixed$(output_rms,3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Line width: 1
    Colour: "Black"
endproc

# ==============================================================================
# Procedure: getPathCoords
# Exact analytic counterpart of the control-Sound formulas above.
# ==============================================================================
procedure getPathCoords: .t, .dur
    .phase = path_speed * .t

    if path_type$ = "Circle"
        .x = 0.5 + 0.4*cos(twoPi*.phase)
        .y = 0.5 + 0.4*sin(twoPi*.phase)
    elsif path_type$ = "Ellipse"
        .x = 0.5 + 0.45*cos(twoPi*.phase)
        .y = 0.5 + 0.30*sin(twoPi*.phase)
    elsif path_type$ = "Lissajous (3:2)"
        .x = 0.5 + 0.4*sin(3*twoPi*.phase)
        .y = 0.5 + 0.4*sin(2*twoPi*.phase)
    elsif path_type$ = "Figure-8"
        .x = 0.5 + 0.4*sin(twoPi*.phase)
        .y = 0.5 + 0.4*sin(2*twoPi*.phase)
    elsif path_type$ = "Spiral In"
        .progress = .t/.dur
        .x = 0.5 + 0.45*(1-.progress)*cos(twoPi*.phase)
        .y = 0.5 + 0.45*(1-.progress)*sin(twoPi*.phase)
    elsif path_type$ = "Spiral Out"
        .progress = .t/.dur
        .x = 0.5 + 0.45*.progress*cos(twoPi*.phase)
        .y = 0.5 + 0.45*.progress*sin(twoPi*.phase)
    elsif path_type$ = "Square Path"
        .p = .phase mod 1
        if .p < 0.25
            .x = 0.1 + 3.2*.p
            .y = 0.1
        elsif .p < 0.5
            .x = 0.9
            .y = 0.1 + 3.2*(.p-0.25)
        elsif .p < 0.75
            .x = 0.9 - 3.2*(.p-0.5)
            .y = 0.9
        else
            .x = 0.1
            .y = 0.9 - 3.2*(.p-0.75)
        endif
    elsif path_type$ = "Star"
        .radius = 0.5 + 0.5*cos(10*pi*.phase)
        .x = 0.5 + 0.4*.radius*cos(twoPi*.phase)
        .y = 0.5 + 0.4*.radius*sin(twoPi*.phase)
    elsif path_type$ = "Infinity Loop"
        .denom = 1 + sin(twoPi*.phase)^2
        .x = 0.5 + 0.35*cos(twoPi*.phase)/.denom
        .y = 0.5 + 0.35*sin(twoPi*.phase)*cos(twoPi*.phase)/.denom
    elsif path_type$ = "Butterfly"
        .scale = (exp(cos(twoPi*.phase)) - 2*cos(4*twoPi*.phase))/5
        .x = 0.5 + 0.35*sin(twoPi*.phase)*.scale
        .y = 0.5 + 0.35*cos(twoPi*.phase)*.scale
    elsif path_type$ = "Rose Curve"
        .radius = cos(5*twoPi*.phase)
        .x = 0.5 + 0.4*.radius*cos(twoPi*.phase)
        .y = 0.5 + 0.4*.radius*sin(twoPi*.phase)
    elsif path_type$ = "Quasi-Chaotic Curve" or path_type$ = "Chaotic Attractor"
        .x = 0.5 + 0.3*sin(twoPi*.phase)*cos(3.7*twoPi*.phase)
        .y = 0.5 + 0.3*cos(twoPi*.phase)*sin(2.3*twoPi*.phase)
    endif
endproc

# ==============================================================================
# Procedure: getOscValues
# One-period values for the same four source definitions used by the engine.
# ==============================================================================
procedure getOscValues: .p, .dt
    .pSaw = (.p + 0.5) mod 1
    @polyBlep: .pSaw, .dt
    .blepSaw = polyBlep.value
    @polyBlep: .p, .dt
    .blep1 = polyBlep.value
    .pHalf = (.p + 0.5) mod 1
    @polyBlep: .pHalf, .dt
    .blep2 = polyBlep.value

    .a = 2*.pSaw - 1 - .blepSaw
    if .p < 0.5
        .sq = 1
    else
        .sq = -1
    endif
    .b = .sq + .blep1 - .blep2
    .c = 4*abs(.p-0.5)-1
    .d = sin(twoPi*.p)
endproc

procedure polyBlep: .p, .dt
    if .dt <= 0
        .value = 0
    elsif .p < .dt
        .u = .p/.dt
        .value = 2*.u - .u^2 - 1
    elsif .p > 1-.dt
        .u = (.p-1)/.dt
        .value = .u^2 + 2*.u + 1
    else
        .value = 0
    endif
endproc
