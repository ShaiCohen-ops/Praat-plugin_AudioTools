# ============================================================
# Praat AudioTools - Time_Varying_Spectral_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-Varying Spectral Vibrato - creates vibrato where both
#   rate and depth can evolve over time. Uses chirp phase
#   integration for smooth rate transitions (no discontinuities).
#   Great for expressive vocal effects, engine sounds, etc.
#
# Changelog v0.2:
#   - Fixed input check
#   - Removed rename hack
#   - Added visualization
#   - Added output scaling
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency

# === Form ===
form Time-Varying Spectral Vibrato
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Ramp Up (Accelerating)
        option Slow Down (Decelerating)
        option Swell (Fade-In Depth)
        option Fade Out (Dying Wobble)
        option Nervous Shiver (Fast & Shallow)
        option Opera Finale (Wide & Slowing)
    
    comment === Rate Evolution (Hz) ===
    positive Start_Rate_Hz 4.0
    positive End_Rate_Hz 8.0
    
    comment === Depth Evolution (Semitones) ===
    positive Start_Depth_ST 0.1
    positive End_Depth_ST 0.1
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Ramp Up (Accelerating)
    start_Rate_Hz = 2.0
    end_Rate_Hz = 10.0
    start_Depth_ST = 0.2
    end_Depth_ST = 0.2
    presetName$ = "RampUp"
elsif preset = 3
    # Slow Down (Engine failure)
    start_Rate_Hz = 12.0
    end_Rate_Hz = 0.5
    start_Depth_ST = 0.3
    end_Depth_ST = 0.5
    presetName$ = "SlowDown"
elsif preset = 4
    # Swell (Fade-In)
    start_Rate_Hz = 5.0
    end_Rate_Hz = 5.0
    start_Depth_ST = 0.0
    end_Depth_ST = 1.0
    presetName$ = "Swell"
elsif preset = 5
    # Fade Out (Calming down)
    start_Rate_Hz = 6.0
    end_Rate_Hz = 3.0
    start_Depth_ST = 0.5
    end_Depth_ST = 0.0
    presetName$ = "FadeOut"
elsif preset = 6
    # Nervous Shiver
    start_Rate_Hz = 8.0
    end_Rate_Hz = 12.0
    start_Depth_ST = 0.1
    end_Depth_ST = 0.1
    presetName$ = "Shiver"
elsif preset = 7
    # Opera Finale
    start_Rate_Hz = 5.5
    end_Rate_Hz = 4.0
    start_Depth_ST = 0.3
    end_Depth_ST = 1.5
    presetName$ = "Opera"
else
    presetName$ = "Custom"
endif

# Calculate slopes
rate_slope = (end_Rate_Hz - start_Rate_Hz) / duration
depth_slope = (end_Depth_ST - start_Depth_ST) / duration

# === Info ===
writeInfoLine: "=== Time-Varying Spectral Vibrato ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Rate: ", start_Rate_Hz, " → ", end_Rate_Hz, " Hz"
appendInfoLine: "Depth: ", start_Depth_ST, " → ", end_Depth_ST, " semitones"
appendInfoLine: "Rate slope: ", fixed$(rate_slope, 2), " Hz/s"
appendInfoLine: "Depth slope: ", fixed$(depth_slope, 3), " st/s"
appendInfoLine: ""

# ============================================================
# PSOLA ANALYSIS
# ============================================================

appendInfoLine: "Creating manipulation object..."

selectObject: original
To Manipulation: 0.01, 75, 600
manip = selected("Manipulation")

# Extract PitchTier
Extract pitch tier
pitchTier = selected("PitchTier")

# ============================================================
# APPLY TIME-VARYING VIBRATO
# ============================================================

appendInfoLine: "Applying time-varying vibrato..."

# The chirp formula for proper phase continuity:
# Phase = Integral of instantaneous frequency
#       = 2π × (start_rate × t + 0.5 × rate_slope × t²)
#
# Depth interpolation: start_depth + depth_slope × t
# Pitch ratio: 2^(semitones/12)

selectObject: pitchTier
Formula: "self * 2 ^ ((start_Depth_ST + depth_slope * x) * sin(2*pi * (start_Rate_Hz * x + 0.5 * rate_slope * x^2)) / 12)"

# ============================================================
# RESYNTHESIS
# ============================================================

appendInfoLine: "Resynthesizing..."

selectObject: manip
plusObject: pitchTier
Replace pitch tier

selectObject: manip
Get resynthesis (overlap-add)
result = selected("Sound")
Rename: original_name$ + "_timeVib_" + presetName$

# Scale output
Scale peak: 0.95

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Time-Varying Vibrato: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Vibrato"
    Text bottom: "yes", "Time (s)"
    
    # Rate evolution
    Select outer viewport: 0, 4, 2.7, 3.7
    Select inner viewport: 0.6, 3.8, 2.8, 3.6
    
    maxRate = max(start_Rate_Hz, end_Rate_Hz) * 1.1
    minRate = min(start_Rate_Hz, end_Rate_Hz) * 0.9
    if minRate < 0.1
        minRate = 0
    endif
    
    Axes: 0, duration, minRate, maxRate
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minRate, maxRate
    
    # Draw rate line
    Colour: "{0.5, 0.5, 0.7}"
    Line width: 2
    Draw line: 0, start_Rate_Hz, duration, end_Rate_Hz
    Line width: 1
    
    # Start/end markers
    Paint circle: "{0.5, 0.5, 0.7}", 0, start_Rate_Hz, 0.05
    Paint circle: "{0.5, 0.5, 0.7}", duration, end_Rate_Hz, 0.05
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Rate (Hz)"
    Text bottom: "yes", "Time"
    
    # Depth evolution
    Select outer viewport: 4, 8, 2.7, 3.7
    Select inner viewport: 4.4, 7.6, 2.8, 3.6
    
    maxDepth = max(start_Depth_ST, end_Depth_ST) * 1.2
    if maxDepth < 0.1
        maxDepth = 0.5
    endif
    
    Axes: 0, duration, 0, maxDepth
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, maxDepth
    
    # Draw depth line
    Colour: "{0.7, 0.5, 0.5}"
    Line width: 2
    Draw line: 0, start_Depth_ST, duration, end_Depth_ST
    Line width: 1
    
    # Start/end markers
    Paint circle: "{0.7, 0.5, 0.5}", 0, start_Depth_ST, 0.05
    Paint circle: "{0.7, 0.5, 0.5}", duration, end_Depth_ST, 0.05
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Depth (st)"
    Text bottom: "yes", "Time"
    
    # Vibrato waveform (pitch deviation over time)
    Select outer viewport: 0, 8, 3.9, 5.0
    Select inner viewport: 0.6, 7.6, 4.0, 4.9
    
    maxDev = max(start_Depth_ST, end_Depth_ST) * 1.2
    if maxDev < 0.1
        maxDev = 0.5
    endif
    
    Axes: 0, duration, -maxDev, maxDev
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, -maxDev, maxDev
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    
    # Draw vibrato modulation
    Colour: "{0.5, 0.6, 0.7}"
    Line width: 1.5
    nPoints = 500
    for p from 2 to nPoints
        t1 = (p - 2) / nPoints * duration
        t2 = (p - 1) / nPoints * duration
        
        # Calculate instantaneous values
        depth1 = start_Depth_ST + depth_slope * t1
        depth2 = start_Depth_ST + depth_slope * t2
        
        # Chirp phase
        phase1 = 2 * pi * (start_Rate_Hz * t1 + 0.5 * rate_slope * t1^2)
        phase2 = 2 * pi * (start_Rate_Hz * t2 + 0.5 * rate_slope * t2^2)
        
        dev1 = depth1 * sin(phase1)
        dev2 = depth2 * sin(phase2)
        
        Draw line: t1, dev1, t2, dev2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pitch (st)"
    Text bottom: "yes", "Time (s)"
    
    # Formula explanation
    Select outer viewport: 0, 8, 5.2, 5.6
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.6, "half", "Formula: pitch × 2^(depth(t) × sin(phase(t)) / 12)"
    Text: 0.5, "centre", 0.2, "half", "phase(t) = 2π × (start_rate × t + 0.5 × rate_slope × t²)  [chirp integral]"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: manip, pitchTier

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