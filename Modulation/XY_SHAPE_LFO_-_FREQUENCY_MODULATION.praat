# ============================================================
# Praat AudioTools - XY_Shape_LFO_Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Constant-power pan mode
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   2D trajectory-based audio modulation using parametric curves.
#   The X and Y coordinates of shapes like circles, Lissajous figures,
#   and butterfly curves are mapped to audio parameters.
#
#   Modulation modes:
#   - Temporal Folding: X → time displacement (tape warble/scrub)
#   - Ring Modulation: X → amplitude modulation
#   - Spatio-Temporal:      X → time warp (L), Y → right-channel gate (decorrelation)
#   - Spatio-Temporal Pan:  X → time warp, Y → constant-power L↔R pan
#
# Usage:
#   Select a Sound object in Praat, then run this script.
#
# Changelog v0.3:
#   - Added Mode 4 'Spatio-Temporal Pan': warps once, then true
#     constant-power L<->R pan driven by Y (full image swing).
#   - Mode 3 relabelled to reflect what it does (L warp / R Y-gate).
#   - 'Stereo Head-Spinner' preset now uses the pan mode so it spins.
#
# Changelog v0.2:
#   - Fixed time lookup syntax: () not []
#   - Modern syntax throughout
#   - Added spectrogram visualization
#   - Added fade in/out
# ============================================================

form XY Shape LFO Modulation
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Granular Time-Scrub
        option Robotic Ring Mod
        option Stereo Head-Spinner
        option Broken Glitch Storm
        option Recursive Chaos
    
    comment === Shape ===
    optionmenu Shape_type 6
        option Circle
        option Diamond
        option Lissajous (3:4)
        option Rose Curve
        option Star (Astroid)
        option Butterfly
    
    comment === Modulation Mode ===
    optionmenu Modulation_mode 1
        option Temporal Folding (time warp)
        option Ring Modulation (AM)
        option Spatio-Temporal (warp L / Y-gate R)
        option Spatio-Temporal Pan (warp + Y pan)
    
    comment === Parameters ===
    positive Trajectory_rate_Hz 1.0
    positive Depth 0.5
    real Signal_feedback 0.0 (= 0-2, signal modulates itself)
    real Instability 0.0 (= 0-1, random jitter)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check for Sound selection ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Granular Time-Scrub
    modulation_mode = 1
    trajectory_rate_Hz = 55.0
    depth = 0.02
    signal_feedback = 0.4
    instability = 0.0
    shape_type = 5
    preset_name$ = "GranularScrub"
elsif preset = 3
    # Robotic Ring Mod
    modulation_mode = 2
    trajectory_rate_Hz = 50.0
    depth = 1.0
    signal_feedback = 0.0
    instability = 0.0
    shape_type = 3
    preset_name$ = "RoboticRingMod"
elsif preset = 4
    # Stereo Head-Spinner
    modulation_mode = 4
    trajectory_rate_Hz = 2.0
    depth = 0.5
    signal_feedback = 0.0
    instability = 0.0
    shape_type = 6
    preset_name$ = "StereoSpinner"
elsif preset = 5
    # Broken Glitch Storm
    modulation_mode = 1
    trajectory_rate_Hz = 8.0
    depth = 0.6
    signal_feedback = 0.8
    instability = 0.1
    shape_type = 2
    preset_name$ = "GlitchStorm"
elsif preset = 6
    # Recursive Chaos
    modulation_mode = 1
    trajectory_rate_Hz = 4.0
    depth = 0.8
    signal_feedback = 2.5
    instability = 0.3
    shape_type = 6
    preset_name$ = "RecursiveChaos"
endif

# === Get Input Sound Info ===
inputSound = selected("Sound")
originalName$ = selected$("Sound")
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

selectObject: inputSound
sampleRate = Get sampling frequency
duration = Get total duration
nSamples = Get number of samples

# Make a working copy
selectObject: inputSound
Copy: "source_" + uid$
sourceSound = selected("Sound")

# === Info ===
writeInfoLine: "=== XY Shape LFO Modulation ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Shape: ", shape_type
appendInfoLine: "Mode: ", modulation_mode
appendInfoLine: "Rate: ", trajectory_rate_Hz, " Hz"
appendInfoLine: "Depth: ", depth
appendInfoLine: "Feedback: ", signal_feedback
appendInfoLine: "Instability: ", instability
appendInfoLine: ""

# === Generate XY Trajectory ===
appendInfoLine: "Generating trajectory..."

# Build trajectory formulas
rate$ = string$(trajectory_rate_Hz)

if shape_type = 1
    # Circle
    xFormula$ = "sin(twoPi * " + rate$ + " * x)"
    yFormula$ = "cos(twoPi * " + rate$ + " * x)"
    shapeName$ = "Circle"
elsif shape_type = 2
    # Diamond
    xFormula$ = "(2/pi) * arcsin(sin(twoPi * " + rate$ + " * x))"
    yFormula$ = "(2/pi) * arcsin(sin(twoPi * " + rate$ + " * x + pi/2))"
    shapeName$ = "Diamond"
elsif shape_type = 3
    # Lissajous 3:4
    xFormula$ = "sin(3 * twoPi * " + rate$ + " * x)"
    yFormula$ = "sin(4 * twoPi * " + rate$ + " * x)"
    shapeName$ = "Lissajous"
elsif shape_type = 4
    # Rose curve (4 petals)
    xFormula$ = "cos(4 * twoPi * " + rate$ + " * x) * cos(twoPi * " + rate$ + " * x)"
    yFormula$ = "cos(4 * twoPi * " + rate$ + " * x) * sin(twoPi * " + rate$ + " * x)"
    shapeName$ = "Rose"
elsif shape_type = 5
    # Star (Astroid)
    xFormula$ = "(cos(twoPi * " + rate$ + " * x))^3"
    yFormula$ = "(sin(twoPi * " + rate$ + " * x))^3"
    shapeName$ = "Star"
elsif shape_type = 6
    # Butterfly curve
    xFormula$ = "sin(twoPi * " + rate$ + " * x) * (exp(cos(twoPi * " + rate$ + " * x)) - 2 * cos(4 * twoPi * " + rate$ + " * x) - (sin(twoPi * " + rate$ + " * x / 12))^5)"
    yFormula$ = "cos(twoPi * " + rate$ + " * x) * (exp(cos(twoPi * " + rate$ + " * x)) - 2 * cos(4 * twoPi * " + rate$ + " * x) - (sin(twoPi * " + rate$ + " * x / 12))^5)"
    shapeName$ = "Butterfly"
endif

# Create trajectory sounds
xTraj = Create Sound from formula: "x_traj_" + uid$, 1, 0, duration, sampleRate, xFormula$
Scale peak: 1.0

yTraj = Create Sound from formula: "y_traj_" + uid$, 1, 0, duration, sampleRate, yFormula$
Scale peak: 1.0

# === Apply Modulation ===
appendInfoLine: "Applying modulation..."

# Object names for formula references (using parentheses for time-based lookup!)
sourceName$ = "Sound_source_" + uid$
xTrajName$ = "Sound_x_traj_" + uid$
yTrajName$ = "Sound_y_traj_" + uid$

sRate$ = string$(sampleRate)
depth$ = string$(depth)
feedback$ = string$(signal_feedback)
instab$ = string$(instability)

# Feedback term: (1 + feedback * |source(x)|)
if signal_feedback > 0
    fbTerm$ = "(1 + " + feedback$ + " * abs(" + sourceName$ + "(x)))"
else
    fbTerm$ = "1"
endif

# Instability term: (1 + instability * randomGauss(0,1))
if instability > 0
    jitterTerm$ = "(1 + " + instab$ + " * randomGauss(0, 1))"
else
    jitterTerm$ = "1"
endif

# === MODE 1: TEMPORAL FOLDING ===
if modulation_mode = 1
    selectObject: sourceSound
    Copy: originalName$ + "_" + preset_name$
    outputSound = selected("Sound")
    
    # Time depth in seconds (not samples!)
    timeDepthSec = depth * 0.05
    timeDepth$ = string$(timeDepthSec)
    
    # Time offset = X(x) * depth * feedback * jitter
    # Use parentheses () for time-based lookup!
    timeOffset$ = "(" + xTrajName$ + "(x) * " + timeDepth$ + " * " + fbTerm$ + " * " + jitterTerm$ + ")"
    
    Formula: sourceName$ + "(x + " + timeOffset$ + ")"
    modeName$ = "TemporalFolding"

# === MODE 2: RING MODULATION ===
elsif modulation_mode = 2
    selectObject: sourceSound
    Copy: originalName$ + "_" + preset_name$
    outputSound = selected("Sound")
    
    # Amplitude = 1 + X(x) * depth * feedback * jitter
    ampMod$ = "(1 + " + xTrajName$ + "(x) * " + depth$ + " * " + fbTerm$ + " * " + jitterTerm$ + ")"
    
    Formula: "self * " + ampMod$
    modeName$ = "RingMod"

# === MODE 3: SPATIO-TEMPORAL ===
elsif modulation_mode = 3
    timeDepthSec = depth * 0.02
    timeDepth$ = string$(timeDepthSec)
    
    # Left channel: time warped by X
    selectObject: sourceSound
    Copy: "left_" + uid$
    leftCh = selected("Sound")
    
    timeOffset$ = "(" + xTrajName$ + "(x) * " + timeDepth$ + ")"
    Formula: sourceName$ + "(x + " + timeOffset$ + ")"
    
    # Right channel: amplitude modulated by Y
    selectObject: sourceSound
    Copy: "right_" + uid$
    rightCh = selected("Sound")
    
    Formula: "self * (0.5 + 0.5 * " + yTrajName$ + "(x))"
    
    # Combine to stereo
    selectObject: leftCh
    plusObject: rightCh
    outputSound = Combine to stereo
    Rename: originalName$ + "_" + preset_name$
    
    removeObject: leftCh, rightCh
    modeName$ = "SpatioTemporal"

# === MODE 4: SPATIO-TEMPORAL PAN (constant-power) ===
elsif modulation_mode = 4
    timeDepthSec = depth * 0.02
    timeDepth$ = string$(timeDepthSec)

    # Warp the signal once; both channels share the same warped content
    selectObject: sourceSound
    Copy: "warp_" + uid$
    warpCh = selected("Sound")
    timeOffset$ = "(" + xTrajName$ + "(x) * " + timeDepth$ + " * " + fbTerm$ + " * " + jitterTerm$ + ")"
    Formula: sourceName$ + "(x + " + timeOffset$ + ")"

    # Constant-power pan: theta = (pi/4)(1 + Y), Y in [-1,1] -> theta in [0, pi/2]
    # Y=-1 -> full left, Y=0 -> centre, Y=+1 -> full right; cos^2 + sin^2 = 1
    selectObject: warpCh
    Copy: "left_" + uid$
    leftCh = selected("Sound")
    Formula: "self * cos(pi/4 * (1 + " + yTrajName$ + "(x)))"

    selectObject: warpCh
    Copy: "right_" + uid$
    rightCh = selected("Sound")
    Formula: "self * sin(pi/4 * (1 + " + yTrajName$ + "(x)))"

    selectObject: leftCh
    plusObject: rightCh
    outputSound = Combine to stereo
    Rename: originalName$ + "_" + preset_name$

    removeObject: warpCh, leftCh, rightCh
    modeName$ = "SpatioTemporalPan"
endif

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.01 then self * (x / 0.01) else self fi"
Formula: "if x > duration - 0.02 then self * ((duration - x) / 0.02) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Cleanup ===
removeObject: sourceSound, xTraj, yTraj

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "XY Shape LFO — " + preset_name$ + " (" + shapeName$ + ")"
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "Rate: " + fixed$(trajectory_rate_Hz, 1) + " Hz | Depth: " + fixed$(depth, 2) + " | Mode: " + modeName$
    
    # === XY Trajectory Plot ===
    Select outer viewport: 0, 3.5, 0.8, 4.0
    Select inner viewport: 0.3, 3.2, 0.9, 3.9
    Axes: -1.3, 1.3, -1.3, 1.3
    
    # Background
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.3, 1.3, -1.3, 1.3
    
    # Axes
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -1.2, 0, 1.2
    
    # Draw trajectory
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    
    .nPoints = 500
    for .i from 2 to .nPoints
        .t1 = (.i - 2) / (.nPoints - 1) * duration
        .t2 = (.i - 1) / (.nPoints - 1) * duration
        
        .s1 = round(.t1 * sampleRate) + 1
        .s2 = round(.t2 * sampleRate) + 1
        if .s1 < 1
            .s1 = 1
        endif
        if .s2 > nSamples
            .s2 = nSamples
        endif
        
        selectObject: xTraj
        .x1 = Get value at sample number: 1, .s1
        .x2 = Get value at sample number: 1, .s2
        
        selectObject: yTraj
        .y1 = Get value at sample number: 1, .s1
        .y2 = Get value at sample number: 1, .s2
        
        # Color by Y value for spatio-temporal mode
        if modulation_mode = 3 or modulation_mode = 4
            if .y1 > 0
                Colour: "{0.2, 0.7, 0.3}"
            else
                Colour: "{0.8, 0.3, 0.2}"
            endif
        endif
        
        Draw line: .x1, .y1, .x2, .y2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text bottom: "yes", "X (time mod)"
    Text left: "yes", "Y (pan/AM)"
    
    # === Spectrogram ===
    Select outer viewport: 3.5, 7, 0.8, 4.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 3.8, 6.8, 0.9, 3.9
    
    # Get mono for spectrogram
    selectObject: outputSound
    .nCh = Get number of channels
    if .nCh > 1
        Extract one channel: 1
        .specSound = selected("Sound")
    else
        Copy: "temp_spec"
        .specSound = selected("Sound")
    endif
    
    selectObject: .specSound
    .spec = To Spectrogram: 0.01, 5000, 0.005, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .specSound, .spec
    
    Select inner viewport: 3.8, 6.8, 0.9, 3.9
    Axes: 0, duration, 0, 5000
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 4.1, 4.5
    Select inner viewport: 0, 7, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Left: XY trajectory shape | Right: Output spectrogram"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc