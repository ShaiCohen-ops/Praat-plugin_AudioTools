# ============================================================
# Praat AudioTools - Panning Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026) - Visualization frame alignment fix
# v0.4.1 (2026): VISUALIZATION ONLY - restore panel drawing frame after L/C/R labels; DSP unchanged.
# v0.4 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic stereo panning with various motion patterns.
#   Uses IntensityTier automation for smooth panning curves.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed critical bug (Convert to mono before selection)
#   - Modern selectObject: syntax throughout
#   - Removed duplicated formula code
#   - Added proper presets
#   - Added visualization of panning curves
#   - Added play_result toggle
#   - Improved random walk with actual randomness
#   - Better parameter organization
#   - Proper output naming
# ============================================================

clearinfo

# ============================================================
# FORM
# ============================================================

form Panning Variations
    comment ─────────────────────────────────────────
    comment Panning Pattern
    optionmenu Panning_pattern: 1
        option Linear Sweep (L → R)
        option Linear Sweep (R → L)
        option Circular Rotation
        option Figure-8 Pattern
        option Ping-Pong (bounce)
        option Random Walk
        option Spiral (expanding)
        option Spiral (contracting)
        option Tremolo (both channels)
        option Static Position
    comment ─────────────────────────────────────────
    comment Motion Parameters
    positive Motion_speed_(Hz) 1.0
    positive Number_of_cycles 2.0
    comment ─────────────────────────────────────────
    comment Pan Range
    real Min_pan 0.0
    comment (0 = full left, 0.5 = center, 1 = full right)
    real Max_pan 1.0
    real Static_position 0.5
    comment ─────────────────────────────────────────
    comment Output
    positive Curve_resolution 200
    boolean Use_constant_power 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
nChan = Get number of channels

# Clamp pan range
if min_pan < 0
    min_pan = 0
endif
if max_pan > 1
    max_pan = 1
endif
if min_pan > max_pan
    temp = min_pan
    min_pan = max_pan
    max_pan = temp
endif

panRange = max_pan - min_pan

# Pattern names
if panning_pattern = 1
    patternName$ = "SweepLR"
elsif panning_pattern = 2
    patternName$ = "SweepRL"
elsif panning_pattern = 3
    patternName$ = "Circular"
elsif panning_pattern = 4
    patternName$ = "Figure8"
elsif panning_pattern = 5
    patternName$ = "PingPong"
elsif panning_pattern = 6
    patternName$ = "Random"
elsif panning_pattern = 7
    patternName$ = "SpiralOut"
elsif panning_pattern = 8
    patternName$ = "SpiralIn"
elsif panning_pattern = 9
    patternName$ = "Tremolo"
else
    patternName$ = "Static"
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Panning Variations v0.4.1"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "Input channels: ", nChan
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: "Speed: ", motion_speed, " Hz"
appendInfoLine: "Cycles: ", number_of_cycles
appendInfoLine: "Pan range: ", fixed$(min_pan, 2), " - ", fixed$(max_pan, 2)
appendInfoLine: "Constant power: ", if use_constant_power then "ON" else "OFF" fi
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# CONVERT TO MONO SOURCE
# ============================================================

selectObject: original
if nChan > 1
    monoSound = Convert to mono
else
    monoSound = Copy: "mono_temp"
endif

# ============================================================
# CREATE PANNING CURVE
# ============================================================

# Store pan values for visualization
for i from 0 to curve_resolution
    panCurve[i] = 0.5
endfor

# Calculate motion frequency based on cycles and duration
if panning_pattern <= 8 and panning_pattern <> 1 and panning_pattern <> 2
    # For cyclic patterns, use cycles parameter
    motionFreq = number_of_cycles / duration
else
    motionFreq = motion_speed
endif

# ============================================================
# CREATE INTENSITY TIERS
# ============================================================

leftTier = Create IntensityTier: "left_pan", 0, duration
rightTier = Create IntensityTier: "right_pan", 0, duration

# Seed random generator for random walk
randomSeed = round(randomUniform(1, 10000))

# ============================================================
# GENERATE PANNING AUTOMATION
# ============================================================

appendInfoLine: "Generating panning curve..."

# Random walk state
if panning_pattern = 6
    walkPos = 0.5
    walkVel = 0
endif

for i from 0 to curve_resolution
    time = i * duration / curve_resolution
    t_norm = time / duration
    
    # Calculate pan position (0 = left, 1 = right)
    if panning_pattern = 1
        # Linear Sweep L → R
        pan = t_norm
        
    elsif panning_pattern = 2
        # Linear Sweep R → L
        pan = 1 - t_norm
        
    elsif panning_pattern = 3
        # Circular Rotation (sine wave)
        pan = 0.5 + 0.5 * sin(2 * pi * motionFreq * time)
        
    elsif panning_pattern = 4
        # Figure-8 (double frequency creates figure-8 in 2D space)
        pan = 0.5 + 0.5 * sin(4 * pi * motionFreq * time)
        
    elsif panning_pattern = 5
        # Ping-Pong (triangle wave)
        phase = (motionFreq * time) mod 1
        if phase < 0.5
            pan = phase * 2
        else
            pan = 2 - phase * 2
        endif
        
    elsif panning_pattern = 6
        # Random Walk (Brownian motion simulation)
        if i > 0
            # Add random acceleration
            walkVel = walkVel + randomGauss(0, 0.1)
            # Damping
            walkVel = walkVel * 0.95
            # Update position
            walkPos = walkPos + walkVel * (duration / curve_resolution)
            # Bounce off edges
            if walkPos < 0
                walkPos = -walkPos
                walkVel = -walkVel * 0.5
            elsif walkPos > 1
                walkPos = 2 - walkPos
                walkVel = -walkVel * 0.5
            endif
        endif
        pan = walkPos
        
    elsif panning_pattern = 7
        # Spiral Out (increasing amplitude rotation)
        envelope = t_norm
        pan = 0.5 + 0.5 * envelope * sin(2 * pi * motionFreq * time)
        
    elsif panning_pattern = 8
        # Spiral In (decreasing amplitude rotation)
        envelope = 1 - t_norm
        pan = 0.5 + 0.5 * envelope * sin(2 * pi * motionFreq * time)
        
    elsif panning_pattern = 9
        # Tremolo (both channels modulated together)
        pan = 0.5
        
    else
        # Static Position
        pan = static_position
    endif
    
    # Apply pan range
    pan = min_pan + pan * panRange
    
    # Clamp
    if pan < 0
        pan = 0
    elsif pan > 1
        pan = 1
    endif
    
    # Store for visualization
    panCurve[i] = pan
    
    # Calculate L/R gains
    if use_constant_power
        # Constant power panning: L = cos(θ), R = sin(θ)
        angle = pan * pi / 2
        gainL = cos(angle)
        gainR = sin(angle)
    else
        # Linear panning
        gainL = 1 - pan
        gainR = pan
    endif
    
    # For tremolo, modulate both channels equally
    if panning_pattern = 9
        tremolo = 0.5 + 0.5 * sin(2 * pi * motionFreq * time)
        gainL = tremolo
        gainR = tremolo
    endif
    
    # Convert to dB (IntensityTier uses dB)
    # Avoid log(0) by using small minimum
    if gainL < 0.001
        gainL = 0.001
    endif
    if gainR < 0.001
        gainR = 0.001
    endif
    
    # Convert linear gain to dB (reference = 1.0 = ~70 dB in IntensityTier convention)
    leftDb = 70 + 20 * log10(gainL)
    rightDb = 70 + 20 * log10(gainR)
    
    # Add points to IntensityTiers
    selectObject: leftTier
    Add point: time, leftDb
    
    selectObject: rightTier
    Add point: time, rightDb
endfor

# ============================================================
# APPLY PANNING TO AUDIO
# ============================================================

appendInfoLine: "Applying panning..."

# Create left channel
selectObject: monoSound
leftChannel = Copy: "left_ch"

# Create right channel
selectObject: monoSound
rightChannel = Copy: "right_ch"

# Multiply with IntensityTiers
selectObject: leftChannel
plusObject: leftTier
leftResult = Multiply: "yes"

selectObject: rightChannel
plusObject: rightTier
rightResult = Multiply: "yes"

# Combine to stereo
selectObject: leftResult
plusObject: rightResult
result = Combine to stereo
selectObject: result
Rename: originalName$ + "_pan_" + patternName$

# Scale output
selectObject: result
Scale peak: 0.99

# ============================================================
# CLEANUP
# ============================================================

removeObject: monoSound, leftChannel, rightChannel, leftResult, rightResult, leftTier, rightTier

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # === Title ===
    Select outer viewport: 0, 8, 0.1, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Panning Variations: " + originalName$ + " (" + patternName$ + ")" + " | v0.4.1"

    # === Panning Curve ===
    Select outer viewport: 0, 8, 0.6, 2.1
    Select inner viewport: 0.6, 7.7, 0.7, 1.95
    Axes: 0, duration, -0.1, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -0.1, 1.1
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    Draw line: 0, 0, duration, 0
    Draw line: 0, 0.5, duration, 0.5
    Draw line: 0, 1, duration, 1
    Paint rectangle: "{0.95, 0.95, 0.9}", 0, duration, min_pan, max_pan
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: -duration * 0.02, "right", 0, "half", "L"
    Text: -duration * 0.02, "right", 0.5, "half", "C"
    Text: -duration * 0.02, "right", 1, "half", "R"

    # Restore the data drawing frame after text labels.
    Select outer viewport: 0, 8, 0.6, 2.1
    Select inner viewport: 0.6, 7.7, 0.7, 1.95
    Axes: 0, duration, -0.1, 1.1
    Colour: "{0.3, 0.5, 0.7}"
    Line width: 2
    for i from 1 to curve_resolution
        t1 = (i - 1) * duration / curve_resolution
        t2 = i * duration / curve_resolution
        p1 = panCurve[i - 1]
        p2 = panCurve[i]
        Draw line: t1, p1, t2, p2
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.08, 0.52, 0.6, 2.1
    Select inner viewport: 0.08, 0.52, 0.62, 2.08
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Pan Position"
    Select outer viewport: 0, 8, 0.6, 2.1
    Select inner viewport: 0.6, 7.7, 0.7, 1.95
    Axes: 0, duration, -0.1, 1.1

    # === L/R Gain Curves ===
    Select outer viewport: 0, 8, 2.1, 3.6
    Select inner viewport: 0.6, 7.7, 2.25, 3.45
    Axes: 0, duration, -0.1, 1.25
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -0.1, 1.25
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    Draw line: 0, 0, duration, 0
    Draw line: 0, 1, duration, 1
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    for i from 1 to curve_resolution
        t1 = (i - 1) * duration / curve_resolution
        t2 = i * duration / curve_resolution
        p1 = panCurve[i - 1]
        p2 = panCurve[i]
        if use_constant_power
            g1 = cos(p1 * pi / 2)
            g2 = cos(p2 * pi / 2)
        else
            g1 = 1 - p1
            g2 = 1 - p2
        endif
        Draw line: t1, g1, t2, g2
    endfor
    Colour: "{0.8, 0.5, 0.3}"
    for i from 1 to curve_resolution
        t1 = (i - 1) * duration / curve_resolution
        t2 = i * duration / curve_resolution
        p1 = panCurve[i - 1]
        p2 = panCurve[i]
        if use_constant_power
            g1 = sin(p1 * pi / 2)
            g2 = sin(p2 * pi / 2)
        else
            g1 = p1
            g2 = p2
        endif
        Draw line: t1, g1, t2, g2
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.08, 0.52, 2.1, 3.6
    Select inner viewport: 0.08, 0.52, 2.12, 3.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 0, 8, 2.1, 3.6
    Select inner viewport: 0.6, 7.7, 2.25, 3.45
    Axes: 0, duration, -0.1, 1.25
    Font size: 7
    Colour: "{0.3, 0.5, 0.8}"
    Text: duration * 0.80, "left", 1.13, "half", "Left"
    Colour: "{0.8, 0.5, 0.3}"
    Text: duration * 0.90, "left", 1.13, "half", "Right"

    # === Waveform Preview ===
    Select outer viewport: 0, 8, 3.65, 5.0
    Select inner viewport: 0.6, 7.7, 3.75, 4.85
    selectObject: result
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.08, 0.52, 3.65, 5
    Select inner viewport: 0.08, 0.52, 3.67, 4.98
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 3.65, 5
    Select inner viewport: 0.6, 7.7, 3.75, 4.85

    # === SUMMARY ===
    Select outer viewport: 0, 8, 5.10, 5.90
    Select inner viewport: 0.60, 7.70, 5.17, 5.83
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.76, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.02, "left", 0.46, "half", patternName$ + " | Speed " + fixed$(motionFreq, 2) + " Hz | Range " + fixed$(min_pan, 2) + "-" + fixed$(max_pan, 2)
    Text: 0.02, "left", 0.18, "half", "Cycles " + fixed$(number_of_cycles, 2) + " | Constant power " + if use_constant_power then "ON" else "OFF" fi + " | Duration " + fixed$(duration, 2) + " s"
    Select inner viewport: 0.60, 7.70, 5.17, 5.83
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0, 8, 0, 6.00
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PANNING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result
