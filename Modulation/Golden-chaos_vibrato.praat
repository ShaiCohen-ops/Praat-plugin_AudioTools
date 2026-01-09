# ============================================================
# Praat AudioTools - Golden_Chaos_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Golden-Chaos Vibrato - uses irrational numbers (π, e, φ)
#   to create non-repeating modulation patterns. The ratios
#   of these constants are irrational, so the combined wave
#   never exactly repeats, creating organic, evolving vibrato.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Fixed object reference (use ID instead of name)
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency

# === Form ===
form Golden-Chaos Vibrato
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Golden Shimmer (Phi driven)
        option Euler's Wobble (e driven)
        option Pi Cycle (Pi driven)
        option Mathematical Chaos (Full Mix)
        option Subtle Irregularity
        option Deep Math Texture
    
    comment === Delay Parameters ===
    positive Base_delay_ms 6.0
    positive Modulation_depth 0.14
    
    comment === Modulation Rates ===
    positive Rate1_hz 3.14159
    comment (Pi)
    positive Rate2_hz 2.71828
    comment (Euler e)
    positive Rate3_hz 1.61803
    comment (Golden Ratio Phi)
    
    comment === Mixing ===
    positive Rate2_mix 0.6
    positive Rate3_mix 0.4
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Golden Shimmer
    base_delay_ms = 5.0
    modulation_depth = 0.08
    rate1_hz = 1.618
    rate2_hz = 3.236
    rate3_hz = 0.618
    rate2_mix = 0.3
    rate3_mix = 0.5
    presetName$ = "Golden"
elsif preset = 3
    # Euler's Wobble
    base_delay_ms = 7.0
    modulation_depth = 0.15
    rate1_hz = 2.718
    rate2_hz = 5.436
    rate3_hz = 1.0
    rate2_mix = 0.8
    rate3_mix = 0.2
    presetName$ = "Euler"
elsif preset = 4
    # Pi Cycle
    base_delay_ms = 6.0
    modulation_depth = 0.12
    rate1_hz = 3.14159
    rate2_hz = 6.28318
    rate3_hz = 1.57079
    rate2_mix = 0.2
    rate3_mix = 0.1
    presetName$ = "Pi"
elsif preset = 5
    # Mathematical Chaos
    base_delay_ms = 8.0
    modulation_depth = 0.20
    rate1_hz = 3.14159
    rate2_hz = 2.71828
    rate3_hz = 1.61803
    rate2_mix = 1.0
    rate3_mix = 1.0
    presetName$ = "Chaos"
elsif preset = 6
    # Subtle Irregularity
    base_delay_ms = 4.0
    modulation_depth = 0.05
    rate1_hz = 3.14159
    rate2_hz = 2.71828
    rate3_hz = 1.61803
    rate2_mix = 0.5
    rate3_mix = 0.5
    presetName$ = "Subtle"
elsif preset = 7
    # Deep Math Texture
    base_delay_ms = 12.0
    modulation_depth = 0.25
    rate1_hz = 0.314
    rate2_hz = 0.271
    rate3_hz = 0.161
    rate2_mix = 0.7
    rate3_mix = 0.7
    presetName$ = "Deep"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Golden-Chaos Vibrato ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Base delay: ", base_delay_ms, " ms"
appendInfoLine: "Depth: ", modulation_depth
appendInfoLine: ""
appendInfoLine: "Rate 1 (π): ", rate1_hz, " Hz"
appendInfoLine: "Rate 2 (e): ", rate2_hz, " Hz × ", rate2_mix
appendInfoLine: "Rate 3 (φ): ", rate3_hz, " Hz × ", rate3_mix
appendInfoLine: ""

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# === Process ===
appendInfoLine: "Applying golden-chaos vibrato..."

selectObject: original
Copy: original_name$ + "_golden_chaos"
result = selected("Sound")

# Apply nested modulation formula using object reference
Formula: ~ object[original, row, max(1, min(ncol, col - round(base * (1 + modulation_depth * sin(2*pi*rate1_hz*x + rate2_mix*sin(2*pi*rate2_hz*x) + rate3_mix*sin(2*pi*rate3_hz*x))))))]

# Scale
selectObject: result
Scale peak: scale_peak
Rename: original_name$ + "_chaos_" + presetName$

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Golden-Chaos Vibrato: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.8, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Chaos"
    Text bottom: "yes", "Time (s)"
    
    # Individual modulation waves
    Select outer viewport: 0, 8, 2.5, 3.5
    Select inner viewport: 0.6, 7.6, 2.6, 3.4
    
    # Show ~3 seconds or full duration
    modDisplayDur = min(3, duration)
    
    Axes: 0, modDisplayDur, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, -1.5, 1.5
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, modDisplayDur, 0
    Solid line
    
    nModPoints = 300
    
    # Rate 1 (Pi) - Red
    Colour: "{0.8, 0.4, 0.4}"
    for mp from 2 to nModPoints
        t1 = (mp - 2) / nModPoints * modDisplayDur
        t2 = (mp - 1) / nModPoints * modDisplayDur
        y1 = sin(2 * pi * rate1_hz * t1)
        y2 = sin(2 * pi * rate1_hz * t2)
        Draw line: t1, y1, t2, y2
    endfor
    
    # Rate 2 (Euler) - Green
    Colour: "{0.4, 0.7, 0.4}"
    for mp from 2 to nModPoints
        t1 = (mp - 2) / nModPoints * modDisplayDur
        t2 = (mp - 1) / nModPoints * modDisplayDur
        y1 = rate2_mix * sin(2 * pi * rate2_hz * t1)
        y2 = rate2_mix * sin(2 * pi * rate2_hz * t2)
        Draw line: t1, y1, t2, y2
    endfor
    
    # Rate 3 (Phi) - Blue
    Colour: "{0.4, 0.4, 0.8}"
    for mp from 2 to nModPoints
        t1 = (mp - 2) / nModPoints * modDisplayDur
        t2 = (mp - 1) / nModPoints * modDisplayDur
        y1 = rate3_mix * sin(2 * pi * rate3_hz * t1)
        y2 = rate3_mix * sin(2 * pi * rate3_hz * t2)
        Draw line: t1, y1, t2, y2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Waves"
    
    # Legend
    Font size: 5
    Colour: "{0.8, 0.4, 0.4}"
    Text: 0.02, "left", 1.3, "half", "π"
    Colour: "{0.4, 0.7, 0.4}"
    Text: 0.06, "left", 1.3, "half", "e"
    Colour: "{0.4, 0.4, 0.8}"
    Text: 0.10, "left", 1.3, "half", "φ"
    
    # Combined modulation
    Select outer viewport: 0, 8, 3.7, 4.7
    Select inner viewport: 0.6, 7.6, 3.8, 4.6
    
    Axes: 0, modDisplayDur, -1.5, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, modDisplayDur, -1.5, 1.5
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, modDisplayDur, 0
    Solid line
    
    # Combined wave
    Colour: "{0.8, 0.6, 0.4}"
    Line width: 1.5
    for mp from 2 to nModPoints
        t1 = (mp - 2) / nModPoints * modDisplayDur
        t2 = (mp - 1) / nModPoints * modDisplayDur
        y1 = sin(2*pi*rate1_hz*t1 + rate2_mix*sin(2*pi*rate2_hz*t1) + rate3_mix*sin(2*pi*rate3_hz*t1))
        y2 = sin(2*pi*rate1_hz*t2 + rate2_mix*sin(2*pi*rate2_hz*t2) + rate3_mix*sin(2*pi*rate3_hz*t2))
        Draw line: t1, y1, t2, y2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Combined"
    Text bottom: "yes", "Time (s)"
    
    # Constants display
    Select outer viewport: 0, 8, 4.9, 5.3
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "π = 3.14159... | e = 2.71828... | φ = 1.61803... | Ratios are irrational → never repeats"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result