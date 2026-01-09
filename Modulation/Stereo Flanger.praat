# ============================================================
# Praat AudioTools - Stereo_Flanger.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Flanger - sweeping comb filter effect with support
#   for negative feedback (hollow/metallic sound). Similar to
#   phaser but typically more metallic and jet-like. Stereo
#   phase offset creates wide, swirling spatial movement.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax (use string building)
#   - Added bounds checking
#   - Added visualization
#   - Added info output
# ============================================================

form Stereo Flanger
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Classic 80s Flanger
        option Slow Jet (High Feedback)
        option Liquid Metal (Negative FB)
        option Deep Throat (Long Delay)
        option Through-Zero (Simulated)
        option Subtle Stereo Widener
    
    comment === LFO Settings ===
    positive Rate_Hz 0.3
    positive Depth_ms 2.0
    positive Base_delay_ms 3.0
    
    comment === Stereo Image ===
    positive Stereo_Phase_Offset_deg 180
    comment (180=counter-sweep, 0=mono)
    
    comment === Mix & Feedback ===
    real Feedback 0.7
    comment (negative = hollow/metallic)
    positive Dry_Wet_Mix 0.5
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
channels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Classic 80s Flanger
    rate_Hz = 0.5
    depth_ms = 1.5
    base_delay_ms = 2.0
    stereo_Phase_Offset_deg = 90
    feedback = 0.6
    dry_Wet_Mix = 0.5
    presetName$ = "Classic80s"
elsif preset = 3
    # Slow Jet (High Feedback)
    rate_Hz = 0.15
    depth_ms = 2.5
    base_delay_ms = 3.0
    stereo_Phase_Offset_deg = 180
    feedback = 0.85
    dry_Wet_Mix = 0.5
    presetName$ = "SlowJet"
elsif preset = 4
    # Liquid Metal (Negative Feedback)
    rate_Hz = 3.0
    depth_ms = 0.5
    base_delay_ms = 1.0
    stereo_Phase_Offset_deg = 180
    feedback = -0.7
    dry_Wet_Mix = 0.6
    presetName$ = "LiquidMetal"
elsif preset = 5
    # Deep Throat (Long Delay)
    rate_Hz = 0.4
    depth_ms = 4.0
    base_delay_ms = 8.0
    stereo_Phase_Offset_deg = 45
    feedback = 0.5
    dry_Wet_Mix = 0.5
    presetName$ = "DeepThroat"
elsif preset = 6
    # Through-Zero (Simulated)
    rate_Hz = 0.2
    depth_ms = 0.9
    base_delay_ms = 1.0
    stereo_Phase_Offset_deg = 180
    feedback = 0.4
    dry_Wet_Mix = 0.7
    presetName$ = "ThroughZero"
elsif preset = 7
    # Subtle Stereo Widener
    rate_Hz = 0.1
    depth_ms = 1.0
    base_delay_ms = 5.0
    stereo_Phase_Offset_deg = 180
    feedback = 0.1
    dry_Wet_Mix = 0.4
    presetName$ = "Widener"
else
    presetName$ = "Custom"
endif

# Convert stereo phase to radians
phase_rad = stereo_Phase_Offset_deg * pi / 180

# Calculate samples
base_samp = round(base_delay_ms * sr / 1000)
mod_samp = round(depth_ms * sr / 1000)

# Feedback type label
if feedback >= 0
    fbType$ = "positive"
else
    fbType$ = "negative"
endif

# === Info ===
writeInfoLine: "=== Stereo Flanger ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Rate: ", rate_Hz, " Hz"
appendInfoLine: "Depth: ", depth_ms, " ms"
appendInfoLine: "Base delay: ", base_delay_ms, " ms"
appendInfoLine: "Stereo offset: ", stereo_Phase_Offset_deg, "°"
appendInfoLine: "Feedback: ", feedback, " (", fbType$, ")"
appendInfoLine: "Dry/Wet: ", dry_Wet_Mix
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

# Convert to stereo if mono
if channels = 1
    appendInfoLine: "Converting mono to stereo..."
    selectObject: original
    Convert to stereo
    stereoSource = selected("Sound")
else
    selectObject: original
    Copy: "stereo_temp"
    stereoSource = selected("Sound")
endif

# Create output
appendInfoLine: "Applying flanger..."

selectObject: stereoSource
Copy: name$ + "_flanger_" + presetName$
result = selected("Sound")

# Build formula strings
source_str$ = string$(stereoSource)
base_str$ = string$(base_samp)
mod_str$ = string$(mod_samp)
rate_str$ = string$(rate_Hz)
phase_str$ = string$(phase_rad)
fb_str$ = string$(feedback)
wet_str$ = string$(dry_Wet_Mix)
dry_str$ = string$(1 - dry_Wet_Mix)

# Delay calculation with bounds
delay_calc$ = "max(1, min(ncol, col - round(" + base_str$ + " + " + mod_str$ + " * sin(2*pi*" + rate_str$ + "*x + (row-1)*" + phase_str$ + "))))"

# 1. Apply Feedback Layer (first reflection approximation)
if feedback <> 0
    Formula: "self + " + fb_str$ + " * object[" + source_str$ + ", row, " + delay_calc$ + "]"
endif

# 2. Apply Main Flange Mix
Formula: "" + dry_str$ + " * self + " + wet_str$ + " * self[row, " + delay_calc$ + "]"

# Cleanup
removeObject: stereoSource

# Scale output
selectObject: result
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Flanger: " + name$ + " (" + presetName$ + ")"
    
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
    
    # Result L channel
    Select outer viewport: 0, 4, 1.5, 2.3
    Select inner viewport: 0.5, 3.8, 1.6, 2.2
    selectObject: result
    Extract one channel: 1
    resultL = selected("Sound")
    Colour: "{0.5, 0.7, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Left"
    
    # Result R channel
    Select outer viewport: 4, 8, 1.5, 2.3
    Select inner viewport: 4.4, 7.6, 1.6, 2.2
    selectObject: result
    Extract one channel: 2
    resultR = selected("Sound")
    Colour: "{0.8, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Right"
    Text bottom: "yes", "Time (s)"
    
    removeObject: resultL, resultR
    
    # LFO sweep curves
    Select outer viewport: 0, 8, 2.5, 3.6
    Select inner viewport: 0.6, 7.6, 2.6, 3.5
    
    vizDur = min(3, duration)
    nPoints = 400
    
    # Calculate delay range for display
    minDelay = base_delay_ms - depth_ms
    maxDelay = base_delay_ms + depth_ms
    
    Axes: 0, vizDur, minDelay - 0.5, maxDelay + 0.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, vizDur, minDelay - 0.5, maxDelay + 0.5
    
    # Center line
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, base_delay_ms, vizDur, base_delay_ms
    Solid line
    
    # Left sweep (blue)
    Colour: "{0.5, 0.7, 0.8}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        d1 = base_delay_ms + depth_ms * sin(2*pi*rate_Hz*t1)
        d2 = base_delay_ms + depth_ms * sin(2*pi*rate_Hz*t2)
        Draw line: t1, d1, t2, d2
    endfor
    
    # Right sweep (orange)
    Colour: "{0.8, 0.6, 0.5}"
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * vizDur
        t2 = (p - 1) / nPoints * vizDur
        d1 = base_delay_ms + depth_ms * sin(2*pi*rate_Hz*t1 + phase_rad)
        d2 = base_delay_ms + depth_ms * sin(2*pi*rate_Hz*t2 + phase_rad)
        Draw line: t1, d1, t2, d2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Time (s)"
    
    # Feedback comparison (positive vs negative)
    Select outer viewport: 0, 4, 3.8, 5.0
    Select inner viewport: 0.6, 3.8, 3.9, 4.9
    
    Axes: 0, 5000, -25, 10
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 5000, -25, 10
    
    # Zero dB line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, 5000, 0
    
    # Draw comb filter with current feedback
    if feedback >= 0
        Colour: "{0.5, 0.7, 0.5}"
    else
        Colour: "{0.7, 0.5, 0.5}"
    endif
    Line width: 1.5
    
    nFreq = 200
    absFb = abs(feedback)
    for f from 2 to nFreq
        freq1 = (f - 2) / nFreq * 5000
        freq2 = (f - 1) / nFreq * 5000
        
        phase1 = 2 * pi * freq1 * (base_delay_ms / 1000)
        phase2 = 2 * pi * freq2 * (base_delay_ms / 1000)
        
        if feedback >= 0
            # Positive feedback: peaks at cos = 1
            gain1 = 1 + absFb * cos(phase1)
            gain2 = 1 + absFb * cos(phase2)
        else
            # Negative feedback: peaks at cos = -1 (inverted)
            gain1 = 1 - absFb * cos(phase1)
            gain2 = 1 - absFb * cos(phase2)
        endif
        
        if gain1 < 0.05
            gain1 = 0.05
        endif
        if gain2 < 0.05
            gain2 = 0.05
        endif
        
        db1 = 10 * ln(gain1) / ln(10)
        db2 = 10 * ln(gain2) / ln(10)
        
        if db1 < -25
            db1 = -25
        endif
        if db2 < -25
            db2 = -25
        endif
        
        Draw line: freq1, db1, freq2, db2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "dB"
    Text bottom: "yes", "Freq (Hz)"
    
    if feedback >= 0
        Text: 2500, "centre", 8, "half", "Positive FB (resonant)"
    else
        Text: 2500, "centre", 8, "half", "Negative FB (hollow)"
    endif
    
    # Parameters
    Select outer viewport: 4, 8, 3.8, 5.0
    Select inner viewport: 4.4, 7.6, 3.9, 4.9
    
    Axes: 0, 4, 0, 6
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 6
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.2, "left", 5.5, "half", "Rate: " + fixed$(rate_Hz, 2) + " Hz"
    Text: 0.2, "left", 4.7, "half", "Depth: " + fixed$(depth_ms, 1) + " ms"
    Text: 0.2, "left", 3.9, "half", "Base: " + fixed$(base_delay_ms, 1) + " ms"
    Text: 0.2, "left", 3.1, "half", "Stereo: " + fixed$(stereo_Phase_Offset_deg, 0) + "°"
    
    if feedback >= 0
        Colour: "{0.4, 0.6, 0.4}"
    else
        Colour: "{0.6, 0.4, 0.4}"
    endif
    Text: 0.2, "left", 2.3, "half", "Feedback: " + fixed$(feedback, 2) + " (" + fbType$ + ")"
    
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.2, "left", 1.5, "half", "Dry/Wet: " + fixed$(dry_Wet_Mix, 2)
    
    Colour: "Black"
    Draw inner box
    
    # Legend
    Select outer viewport: 0, 8, 5.1, 5.5
    Font size: 6
    Colour: "{0.5, 0.7, 0.8}"
    Text: 0.3, "left", 0.5, "half", "■ Left"
    Colour: "{0.8, 0.6, 0.5}"
    Text: 0.45, "left", 0.5, "half", "■ Right (+" + fixed$(stereo_Phase_Offset_deg, 0) + "°)"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result