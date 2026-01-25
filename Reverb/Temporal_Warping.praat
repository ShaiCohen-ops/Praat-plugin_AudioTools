# ============================================================
# Praat AudioTools - Temporal_Warping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Temporal warping effect with progressive time displacement.
#   Creates diffusion/smearing effects by displacing samples
#   through multiple warp stages.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Category: Time & Granular
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
original_sound$ = selected$("Sound")

form Temporal Warping Effect v1.0
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Warp
        option Medium Warp
        option Heavy Warp
        option Extreme Warp
        option Spectral Smear
        option Time Stretch Feel
    comment === Parameters ===
    positive Tail_duration_(seconds) 3.0
    positive Number_of_warp_stages 6
    positive Max_displacement_factor 0.1
    positive Warp_strength 0.3
    positive Fadeout_duration_(seconds) 1.2
    comment === Output ===
    boolean Show_visualization 1
    boolean Play_result 1
endform

# === APPLY PRESET VALUES ===
if preset = 2
    # Subtle Warp
    tail_duration = 2.0
    number_of_warp_stages = 4
    max_displacement_factor = 0.05
    warp_strength = 0.15
    fadeout_duration = 1.0
    presetName$ = "Subtle Warp"
elsif preset = 3
    # Medium Warp
    tail_duration = 3.0
    number_of_warp_stages = 6
    max_displacement_factor = 0.1
    warp_strength = 0.3
    fadeout_duration = 1.2
    presetName$ = "Medium Warp"
elsif preset = 4
    # Heavy Warp
    tail_duration = 4.0
    number_of_warp_stages = 8
    max_displacement_factor = 0.2
    warp_strength = 0.5
    fadeout_duration = 1.5
    presetName$ = "Heavy Warp"
elsif preset = 5
    # Extreme Warp
    tail_duration = 5.0
    number_of_warp_stages = 12
    max_displacement_factor = 0.35
    warp_strength = 0.7
    fadeout_duration = 2.0
    presetName$ = "Extreme Warp"
elsif preset = 6
    # Spectral Smear
    tail_duration = 4.0
    number_of_warp_stages = 16
    max_displacement_factor = 0.15
    warp_strength = 0.4
    fadeout_duration = 2.0
    presetName$ = "Spectral Smear"
elsif preset = 7
    # Time Stretch Feel
    tail_duration = 6.0
    number_of_warp_stages = 10
    max_displacement_factor = 0.25
    warp_strength = 0.6
    fadeout_duration = 2.5
    presetName$ = "Time Stretch Feel"
else
    presetName$ = "Custom"
endif

# === SETUP ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  TEMPORAL WARPING v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""

selectObject: originalSound
original_duration = Get total duration
sampling_rate = Get sampling frequency
channels = Get number of channels

appendInfoLine: "Input: ", original_sound$
appendInfoLine: "Duration: ", fixed$(original_duration, 3), " s"
appendInfoLine: "Sample rate: ", sampling_rate, " Hz"
appendInfoLine: "Channels: ", channels
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# Store warp stage data for visualization
for stage from 1 to number_of_warp_stages
    warp_factor_viz[stage] = stage / number_of_warp_stages
    time_curve_viz[stage] = sin(pi * stage / number_of_warp_stages)
    displacement_viz[stage] = max_displacement_factor * warp_factor_viz[stage] * time_curve_viz[stage]
endfor

# === CREATE EXTENDED SOUND ===
appendInfoLine: "Creating extended sound with ", tail_duration, "s tail..."

if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration, sampling_rate, "0"
endif
silentTail = selected("Sound")

selectObject: originalSound
plusObject: silentTail
Concatenate
Rename: "extended_sound"
extendedSound = selected("Sound")

# === APPLY WARPING ===
appendInfoLine: "Applying ", number_of_warp_stages, " warp stages..."
appendInfoLine: ""

selectObject: extendedSound

if channels = 2
    # Process stereo
    Extract one channel: 1
    Rename: "left_channel"
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    Rename: "right_channel"
    rightChannel = selected("Sound")
    
    # Process LEFT channel
    selectObject: leftChannel
    Copy: "soundObj_left"
    soundObjLeft = selected("Sound")
    
    warp_stages = number_of_warp_stages
    a = Get number of samples
    
    appendInfoLine: "Processing LEFT channel:"
    for stage from 1 to warp_stages
        warp_factor = stage / warp_stages
        max_displacement = a * max_displacement_factor * warp_factor
        time_curve = sin(pi * stage / warp_stages)
        displacement = round(max_displacement * randomUniform(0.3, 1.0) * time_curve)
        
        Formula: "self * (1 - warp_factor * 0.1) + warp_factor * warp_strength * (if (col + displacement) > 0 and (col + displacement) <= ncol then self[col + displacement] - self[col] else 0 fi)"
        
        appendInfoLine: "  Stage ", stage, ": disp=", displacement, " samples (", fixed$(displacement / sampling_rate * 1000, 1), " ms)"
    endfor
    
    Scale peak: 0.99
    
    # Process RIGHT channel (slightly different parameters for stereo width)
    selectObject: rightChannel
    Copy: "soundObj_right"
    soundObjRight = selected("Sound")
    
    a = Get number of samples
    
    appendInfoLine: ""
    appendInfoLine: "Processing RIGHT channel:"
    for stage from 1 to warp_stages
        warp_factor = stage / warp_stages
        max_displacement = a * max_displacement_factor * 1.1 * warp_factor
        time_curve = sin(pi * (stage + 0.5) / warp_stages)
        displacement = round(max_displacement * randomUniform(0.25, 0.95) * time_curve)
        
        Formula: "self * (1 - warp_factor * 0.12) + warp_factor * (warp_strength * 0.93) * (if (col + displacement) > 0 and (col + displacement) <= ncol then self[col + displacement] - self[col] else 0 fi)"
        
        appendInfoLine: "  Stage ", stage, ": disp=", displacement, " samples (", fixed$(displacement / sampling_rate * 1000, 1), " ms)"
    endfor
    
    Scale peak: 0.99
    
    # Combine to stereo
    selectObject: soundObjLeft
    plusObject: soundObjRight
    Combine to stereo
    Rename: "temporal_warping_stereo"
    resultSound = selected("Sound")
    
    removeObject: soundObjLeft, soundObjRight
    
else
    # Process mono
    Copy: "soundObj"
    soundObj = selected("Sound")
    
    warp_stages = number_of_warp_stages
    a = Get number of samples
    
    appendInfoLine: "Processing MONO channel:"
    for stage from 1 to warp_stages
        warp_factor = stage / warp_stages
        max_displacement = a * max_displacement_factor * warp_factor
        time_curve = sin(pi * stage / warp_stages)
        displacement = round(max_displacement * randomUniform(0.3, 1.0) * time_curve)
        
        Formula: "self * (1 - warp_factor * 0.1) + warp_factor * warp_strength * (if (col + displacement) > 0 and (col + displacement) <= ncol then self[col + displacement] - self[col] else 0 fi)"
        
        appendInfoLine: "  Stage ", stage, ": disp=", displacement, " samples (", fixed$(displacement / sampling_rate * 1000, 1), " ms)"
    endfor
    
    Scale peak: 0.99
    Convert to stereo
    Rename: "temporal_warping_stereo"
    resultSound = selected("Sound")
    
    removeObject: soundObj
endif

# === APPLY FADEOUT ===
appendInfoLine: ""
appendInfoLine: "Applying fadeout (", fadeout_duration, "s)..."

selectObject: resultSound
total_duration = Get total duration
fade_start = total_duration - fadeout_duration

Formula: "if x > fade_start then self * (0.5 + 0.5 * cos(pi * (x - fade_start) / fadeout_duration)) else self fi"

# === CLEANUP TEMPORARY OBJECTS ===
removeObject: silentTail, extendedSound
if channels = 2
    removeObject: leftChannel, rightChannel
endif

# ============================================================
# VISUALIZATION
# ============================================================

if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # Calculate display duration (show first portion if very long)
    viz_duration = original_duration + tail_duration
    if viz_duration > 20
        viz_duration = 20
    endif
    
    # --- TITLE ---
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Temporal Warping## | " + original_sound$ + " | " + presetName$
    
    # --- ORIGINAL WAVEFORM ---
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.8, 7.8, 0.7, 1.6
    
    selectObject: originalSound
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, original_duration, 0, 0, "no", "Curve"
    
    # Mark original end
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 1
    Dotted line
    Draw line: original_duration, -1, original_duration, 1
    Solid line
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, 0.6, 1.7
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.4, 0.6}"
    Text: 0.95, "right", 0.6, "half", "Original"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.3, "half", fixed$(original_duration, 2) + "s"
    
    # --- WARPED WAVEFORM ---
    Select outer viewport: 0, 8, 1.8, 2.9
    Select inner viewport: 0.8, 7.8, 1.9, 2.8
    
    selectObject: resultSound
    Colour: "{0.5, 0.7, 0.4}"
    Draw: 0, viz_duration, 0, 0, "no", "Curve"
    
    # Mark original end and fade start
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 1
    Dotted line
    Draw line: original_duration, -1, original_duration, 1
    
    Colour: "{0.6, 0.6, 0.8}"
    Draw line: fade_start, -1, fade_start, 1
    Solid line
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, 1.8, 2.9
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.6, 0.35}"
    Text: 0.95, "right", 0.6, "half", "Warped"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.3, "half", fixed$(total_duration, 2) + "s"
    
    # --- SPECTROGRAMS COMPARISON ---
    Select outer viewport: 0, 4, 3.0, 4.5
    Select inner viewport: 0.8, 3.8, 3.1, 4.4
    
    selectObject: originalSound
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    spectrogramOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Select outer viewport: 0, 0.8, 3.0, 4.5
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.4, 0.55}"
    Text: 0.95, "right", 0.6, "half", "Original"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.3, "half", "Spectrum"
    
    Select outer viewport: 4, 8, 3.0, 4.5
    Select inner viewport: 4.4, 7.8, 3.1, 4.4
    
    selectObject: resultSound
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    spectrogramResult = selected("Spectrogram")
    Paint: 0, viz_duration, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Select outer viewport: 4, 4.4, 3.0, 4.5
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.55, 0.4}"
    Text: 0.95, "right", 0.6, "half", "Warped"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.3, "half", "Spectrum"
    
    removeObject: spectrogramOrig, spectrogramResult
    
    # --- WARP STAGES PLOT ---
    Select outer viewport: 0, 4, 4.6, 5.8
    Select inner viewport: 0.8, 3.8, 4.7, 5.7
    
    Axes: 0, number_of_warp_stages + 1, 0, 1.2
    
    # Background
    Paint rectangle: "{0.97, 0.98, 0.99}", 0, number_of_warp_stages + 1, 0, 1.2
    
    # Draw time curve (sine envelope)
    Colour: "{0.7, 0.8, 0.9}"
    Line width: 2
    for stage from 1 to number_of_warp_stages
        if stage > 1
            Draw line: stage - 1, time_curve_viz[stage - 1], stage, time_curve_viz[stage]
        endif
    endfor
    
    # Draw displacement factors as bars
    for stage from 1 to number_of_warp_stages
        barHeight = displacement_viz[stage] / max_displacement_factor
        
        # Color gradient based on stage
        r = 0.3 + 0.5 * (stage / number_of_warp_stages)
        g = 0.6 - 0.3 * (stage / number_of_warp_stages)
        b = 0.8 - 0.4 * (stage / number_of_warp_stages)
        
        Paint rectangle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", stage - 0.35, stage + 0.35, 0, barHeight
        
        Colour: "{0.3, 0.3, 0.4}"
        Line width: 0.5
        Draw rectangle: stage - 0.35, stage + 0.35, 0, barHeight
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Text bottom: "yes", "Warp Stage"
    Text left: "yes", "Displacement"
    
    Font size: 7
    Select outer viewport: 0, 0.8, 4.6, 5.8
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.5, 0.7}"
    Text: 0.95, "right", 0.5, "half", "Stages"
    
    # --- FADEOUT ENVELOPE ---
    Select outer viewport: 4, 8, 4.6, 5.8
    Select inner viewport: 4.4, 7.8, 4.7, 5.7
    
    Axes: 0, total_duration, 0, 1.1
    
    Paint rectangle: "{0.98, 0.97, 0.98}", 0, total_duration, 0, 1.1
    
    # Draw envelope
    Colour: "{0.6, 0.4, 0.7}"
    Line width: 2
    
    numPoints = 100
    for i from 1 to numPoints
        t = (i - 1) * total_duration / (numPoints - 1)
        
        if t > fade_start
            env = 0.5 + 0.5 * cos(pi * (t - fade_start) / fadeout_duration)
        else
            env = 1.0
        endif
        
        if i > 1
            Draw line: prevT, prevEnv, t, env
        endif
        
        prevT = t
        prevEnv = env
    endfor
    
    # Mark fade start
    Colour: "{0.8, 0.6, 0.6}"
    Line width: 1
    Dotted line
    Draw line: fade_start, 0, fade_start, 1.1
    Solid line
    
    Font size: 5
    Colour: "{0.6, 0.4, 0.4}"
    Text: fade_start, "centre", 1.05, "half", "Fade"
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"
    
    Font size: 7
    Select outer viewport: 4, 4.4, 4.6, 5.8
    Axes: 0, 1, 0, 1
    Colour: "{0.5, 0.35, 0.6}"
    Text: 0.95, "right", 0.5, "half", "Fadeout"
    
    # --- PARAMETERS & LEGEND ---
    Select outer viewport: 0, 8, 5.9, 6.7
    Axes: 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.4}"
    
    # Parameters
    Text: 0.02, "left", 0.8, "half", "##Parameters##"
    Font size: 5
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.55, "half", "Tail: " + fixed$(tail_duration, 1) + "s"
    Text: 0.12, "left", 0.55, "half", "Stages: " + string$(number_of_warp_stages)
    Text: 0.23, "left", 0.55, "half", "Disp: " + fixed$(max_displacement_factor, 2)
    Text: 0.34, "left", 0.55, "half", "Strength: " + fixed$(warp_strength, 2)
    Text: 0.47, "left", 0.55, "half", "Fadeout: " + fixed$(fadeout_duration, 1) + "s"
    
    # Legend
    Font size: 6
    Colour: "{0.3, 0.3, 0.4}"
    Text: 0.62, "left", 0.8, "half", "##Legend##"
    
    Font size: 5
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 1
    Dotted line
    Draw line: 0.62, 0.55, 0.66, 0.55
    Solid line
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.67, "left", 0.55, "half", "Original end"
    
    Colour: "{0.6, 0.6, 0.8}"
    Dotted line
    Draw line: 0.80, 0.55, 0.84, 0.55
    Solid line
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.85, "left", 0.55, "half", "Fade start"
    
    # Info
    Text: 0.02, "left", 0.2, "half", "Max displacement: " + fixed$(max_displacement_factor * original_duration * 1000, 0) + " ms"
    Text: 0.30, "left", 0.2, "half", "Output duration: " + fixed$(total_duration, 2) + "s (" + fixed$((total_duration / original_duration - 1) * 100, 0) + "% longer)"
    
    # --- TIME AXIS ---
    Select outer viewport: 0, 8, 6.7, 7.0
    Select inner viewport: 0.8, 7.8, 6.75, 6.95
    
    Axes: 0, viz_duration, 0, 1
    
    Colour: "{0.3, 0.3, 0.4}"
    Line width: 1
    Draw line: 0, 0.7, viz_duration, 0.7
    
    Font size: 5
    tickStep = 1
    if viz_duration > 10
        tickStep = 2
    endif
    if viz_duration > 20
        tickStep = 5
    endif
    
    t = 0
    while t <= viz_duration
        Draw line: t, 0.7, t, 0.3
        Text: t, "centre", 0.1, "half", string$(t)
        t = t + tickStep
    endwhile
    
    Font size: 6
    Text: viz_duration / 2, "centre", -0.5, "half", "Time (s)"
    
    Font size: 10
    Line width: 1
    Colour: "Black"
    
    appendInfoLine: "  Visualization complete"
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  Input duration: ", fixed$(original_duration, 3), " s"
appendInfoLine: "  Output duration: ", fixed$(total_duration, 3), " s"
appendInfoLine: "  Added tail: ", fixed$(tail_duration, 1), " s"
appendInfoLine: ""
appendInfoLine: "  Output: temporal_warping_stereo"
appendInfoLine: ""

selectObject: resultSound

if play_result
    appendInfoLine: "Playing..."
    Play
endif

appendInfoLine: "Done!"