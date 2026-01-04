# ============================================================
# Praat AudioTools - Spectral_Echo_Cascade.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Echo Cascade - creates cascading echoes with
#   Fibonacci-based delay timing and spectral coloring.
#   The Fibonacci progression creates more natural, organic
#   echo patterns than linear or geometric delays.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added bounds checking
#   - Fixed Formula interpolation
#   - Added tail for echo decay
#   - Added visualization
#   - Fixed stereo/mono compatibility
# ============================================================

form Spectral Echo Cascade
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Gentle Echoes
        option Dense Cluster
        option Long Tails
        option Custom
    
    comment === Cascade ===
    natural Cascade_levels 6
    positive Decay_rate 0.75
    positive Delay_base 5
    
    comment === Spectral Coloring ===
    positive Coloring_center 0.5
    positive Coloring_depth 0.5
    
    comment === Output ===
    positive Scale_peak 0.88
    positive Tail_duration_s 2.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    cascade_levels = 6
    decay_rate = 0.75
    delay_base = 5
    coloring_center = 0.5
    coloring_depth = 0.5
    tail_duration_s = 2.0
elsif preset = 2
    # Gentle Echoes
    cascade_levels = 4
    decay_rate = 0.85
    delay_base = 7
    coloring_center = 0.45
    coloring_depth = 0.35
    tail_duration_s = 3.0
elsif preset = 3
    # Dense Cluster
    cascade_levels = 8
    decay_rate = 0.7
    delay_base = 4
    coloring_center = 0.55
    coloring_depth = 0.65
    tail_duration_s = 1.5
elsif preset = 4
    # Long Tails
    cascade_levels = 7
    decay_rate = 0.9
    delay_base = 9
    coloring_center = 0.5
    coloring_depth = 0.4
    tail_duration_s = 4.0
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Gentle"
elsif preset = 3
    presetName$ = "Dense"
elsif preset = 4
    presetName$ = "Long Tails"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral Echo Cascade ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Levels: ", cascade_levels
appendInfoLine: "Decay: ", decay_rate
appendInfoLine: "Coloring: center=", coloring_center, " depth=", coloring_depth
appendInfoLine: "Tail: ", tail_duration_s, " s"
appendInfoLine: ""

# === Convert to Mono ===
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
    appendInfoLine: "Converted to mono for processing"
else
    Copy: "source_temp"
    sourceSound = selected("Sound")
endif

# === Create Silence Tail ===
silence = Create Sound from formula: "tail", 1, 0, tail_duration_s, sampleRate, "0"

# === Concatenate Source + Tail ===
selectObject: sourceSound, silence
Concatenate
result = selected("Sound")
Rename: original_name$ + "_fibonacci_echo"

removeObject: sourceSound, silence

# Get new total samples (with tail)
selectObject: result
totalSamples = Get number of samples

appendInfoLine: "Added ", fixed$(tail_duration_s, 2), "s tail for echo decay"
appendInfoLine: ""

# === Store Fibonacci/Delay Info for Visualization ===
fibValues# = zero#(cascade_levels)
delayMs# = zero#(cascade_levels)
decayValues# = zero#(cascade_levels)

# === Main Cascade Processing Loop ===
appendInfoLine: "Processing cascade levels..."

fibPrev = 1
fibCurrent = 1

for level from 1 to cascade_levels
    selectObject: result
    
    # Fibonacci progression
    if level > 1
        fibNext = fibPrev + fibCurrent
        fibPrev = fibCurrent
        fibCurrent = fibNext
    endif
    
    fibValues#[level] = fibCurrent
    
    # Calculate delay
    delayShift = round(totalSamples / (delay_base + fibCurrent))
    delayMs#[level] = (delayShift / sampleRate) * 1000
    
    # Calculate decay
    currentDecay = decay_rate ^ level
    decayValues#[level] = currentDecay
    
    # Spectral coloring parameters
    colorCenter = coloring_center
    colorDepth = coloring_depth
    
    appendInfoLine: "  Level ", level, ": fib=", fibCurrent, " delay=", fixed$(delayMs#[level], 1), "ms decay=", fixed$(currentDecay, 3)
    
    # Multi-tap delay with spectral coloring and bounds checking
    Formula: ~ if col - delayShift >= 1 
        ... then self + self[col - delayShift] * currentDecay * (colorCenter + colorDepth * cos(level * 2 * pi * col / totalSamples))
        ... else self fi
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Echo Cascade: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.5, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Echo"
    Text bottom: "yes", "Time (s)"
    
    # Mark original end / tail start
    selectObject: result
    resDur = Get total duration
    Axes: 0, resDur, -1, 1
    Colour: "{0.8, 0.4, 0.4}"
    Dotted line
    Draw line: duration, -1, duration, 1
    Solid line
    Font size: 6
    Text: duration + 0.05, "left", 0.8, "half", "tail"
    
    # Fibonacci delay structure
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    
    # Find max delay for scaling
    maxDelay = delayMs#[1]
    for lv from 2 to cascade_levels
        if delayMs#[lv] > maxDelay
            maxDelay = delayMs#[lv]
        endif
    endfor
    
    Axes: 0, cascade_levels + 1, 0, maxDelay * 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, cascade_levels + 1, 0, maxDelay * 1.1
    
    # Draw delay bars
    for lv from 1 to cascade_levels
        # Color by decay
        intensity = decayValues#[lv]
        barColor$ = "{" + fixed$(0.3 + 0.5 * intensity, 2) + ", " + fixed$(0.5 + 0.3 * intensity, 2) + ", " + fixed$(0.7, 2) + "}"
        Paint rectangle: barColor$, lv - 0.35, lv + 0.35, 0, delayMs#[lv]
        
        # Label with Fibonacci number
        Colour: "Black"
        Font size: 6
        Text: lv, "centre", delayMs#[lv] + maxDelay * 0.05, "bottom", string$(fibValues#[lv])
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Level (Fibonacci)"
    
    # Decay curve
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    
    Axes: 0, cascade_levels + 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, cascade_levels + 1, 0, 1.1
    
    # Draw decay curve
    Colour: "{0.7, 0.4, 0.4}"
    Line width: 2
    for lv from 1 to cascade_levels
        Paint circle (mm): "{0.7, 0.4, 0.4}", lv, decayValues#[lv], 1.5
        if lv > 1
            Draw line: lv - 1, decayValues#[lv - 1], lv, decayValues#[lv]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Decay"
    Text bottom: "yes", "Level"
    
    # Legend
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Levels: " + string$(cascade_levels) + " | Decay: " + fixed$(decay_rate, 2) + " | Fibonacci: 1→" + string$(fibValues#[cascade_levels]) + " | Tail: " + fixed$(tail_duration_s, 1) + "s"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s (includes ", fixed$(tail_duration_s, 2), "s tail)"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result