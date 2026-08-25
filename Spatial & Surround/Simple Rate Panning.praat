# ============================================================
# Praat AudioTools - Simple Rate Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 (2026)
# v0.4.2 (2026): FORMULA SYNTAX FIX ONLY - replace unsupported `elsif` in the generated Praat Formula clamp with nested if/else/fi.
# v0.4.1 (2026): Clamp the actual DSP pan position to [-1,+1] before the constant-power law; downmix any multichannel wet source to mono before panning.
# v0.4 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-panning effect with multiple waveform shapes, depth control,
#   and constant-power panning law for smooth stereo movement.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4.2:
#   - FIXED: Praat Formula expressions do not accept `elsif`; the pan clamp now uses nested if/else/fi.
#
# Changelog v0.4.1:
#   - FIXED: center + depth*modulator is clamped to [-1,+1] in the DSP, matching the visualization and preventing negative pan gains.
#   - FIXED: any input with more than one channel is downmixed to mono before the wet autopan stage.
#   - FIXED: for 3+ channel input, the dry path is also reduced safely to stereo instead of implicitly reading only channels 1-2.
#
# Changelog v0.4:
#   - FIXED: Used row instead of col to detect channel (critical bug)
#   - FIXED: Convert to mono first for proper stereo panning effect
#   - Combined L/R formulas into single pass
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
dur = Get total duration
sr = Get sampling frequency
nCh = Get number of channels

form Simple Rate Panning v0.4.2
    comment ==== Presets ====
    optionmenu Preset: 1
        option Custom
        option Slow Drift (0.25 Hz gentle)
        option Classic Autopan (1 Hz moderate)
        option Fast Tremolo (4 Hz narrow)
        option Ping Pong (2 Hz full width)
        option Subtle Movement (0.5 Hz shallow)
        option Extreme Chopper (8 Hz square)
        option Slow Triangle (0.3 Hz smooth)
        option Seasick (0.15 Hz deep)
    comment ==== Panning Parameters ====
    positive Pan_rate_Hz 1.0
    optionmenu Waveform: 1
        option Sine (smooth)
        option Triangle (linear)
        option Square (hard)
        option Sawtooth (ramp)
    real Pan_depth_percent 100
    comment Pan center: -1=left  0=center  +1=right
    real Pan_center 0.0
    real Start_phase_degrees 0
    comment ==== Output (Mix: 0=dry 100=wet) ====
    real Mix_percent 100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 2
    # Slow Drift
    pan_rate_Hz = 0.25
    waveform = 1
    pan_depth_percent = 60
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "SlowDrift"
elsif preset = 3
    # Classic Autopan
    pan_rate_Hz = 1.0
    waveform = 1
    pan_depth_percent = 80
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "ClassicAutopan"
elsif preset = 4
    # Fast Tremolo
    pan_rate_Hz = 4.0
    waveform = 1
    pan_depth_percent = 40
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "FastTremolo"
elsif preset = 5
    # Ping Pong
    pan_rate_Hz = 2.0
    waveform = 1
    pan_depth_percent = 100
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "PingPong"
elsif preset = 6
    # Subtle Movement
    pan_rate_Hz = 0.5
    waveform = 1
    pan_depth_percent = 30
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "SubtleMovement"
elsif preset = 7
    # Extreme Chopper
    pan_rate_Hz = 8.0
    waveform = 3
    pan_depth_percent = 100
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "ExtremeChopper"
elsif preset = 8
    # Slow Triangle
    pan_rate_Hz = 0.3
    waveform = 2
    pan_depth_percent = 70
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "SlowTriangle"
elsif preset = 9
    # Seasick
    pan_rate_Hz = 0.15
    waveform = 1
    pan_depth_percent = 95
    pan_center = 0.0
    start_phase_degrees = 0
    presetName$ = "Seasick"
else
    # Custom
    presetName$ = "Custom"
endif

# Clamp parameters
if pan_depth_percent < 0
    pan_depth_percent = 0
elsif pan_depth_percent > 100
    pan_depth_percent = 100
endif
depth = pan_depth_percent / 100

if pan_center < -1
    pan_center = -1
elsif pan_center > 1
    pan_center = 1
endif

if mix_percent < 0
    mix_percent = 0
elsif mix_percent > 100
    mix_percent = 100
endif
wetLevel = mix_percent / 100
dryLevel = 1 - wetLevel

# Convert phase to radians
phaseRad = start_phase_degrees * pi / 180

# Waveform name for display
if waveform = 1
    waveName$ = "Sine"
elsif waveform = 2
    waveName$ = "Triangle"
elsif waveform = 3
    waveName$ = "Square"
else
    waveName$ = "Sawtooth"
endif

writeInfoLine: "=== Simple Rate Panning v0.4.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Rate: ", fixed$(pan_rate_Hz, 2), " Hz"
appendInfoLine: "Waveform: ", waveName$
appendInfoLine: "Depth: ", fixed$(pan_depth_percent, 0), "%"
appendInfoLine: "Center: ", fixed$(pan_center, 2)
appendInfoLine: "Phase: ", fixed$(start_phase_degrees, 0), " deg"
appendInfoLine: "Mix: ", fixed$(mix_percent, 0), "%"
appendInfoLine: ""

# ============================================================
# PREPARE AUDIO
# ============================================================

# First convert to mono (sum channels) for proper autopan
selectObject: original
if nCh > 1
    monoSource = Convert to mono
    appendInfoLine: "Downmixed ", nCh, " input channels to mono for panning..."
else
    monoSource = Copy: "temp_mono"
endif

# Create stereo from mono (both channels identical)
selectObject: monoSource
result = Convert to stereo

# Keep mono for dry mix if needed
if dryLevel > 0
    selectObject: original
    if nCh = 1
        drySound = Convert to stereo
    elsif nCh = 2
        drySound = Copy: "temp_dry"
    else
        dryMono = Convert to mono
        selectObject: dryMono
        drySound = Convert to stereo
        removeObject: dryMono
    endif
endif

# ============================================================
# BUILD PANNING FORMULA
# ============================================================

# Rate and phase strings
rateStr$ = string$(pan_rate_Hz)
phaseStr$ = string$(phaseRad)
depthStr$ = string$(depth)
centerStr$ = string$(pan_center)

# Build modulator formula based on waveform
if waveform = 1
    # Sine
    modFormula$ = "sin(2*pi*" + rateStr$ + "*x + " + phaseStr$ + ")"
elsif waveform = 2
    # Triangle
    modFormula$ = "(2*abs(2*(" + rateStr$ + "*x + " + phaseStr$ + "/(2*pi) - floor(" + rateStr$ + "*x + " + phaseStr$ + "/(2*pi) + 0.5))) - 1)"
elsif waveform = 3
    # Square
    modFormula$ = "(if sin(2*pi*" + rateStr$ + "*x + " + phaseStr$ + ") >= 0 then 1 else -1 fi)"
else
    # Sawtooth
    modFormula$ = "(2*(" + rateStr$ + "*x + " + phaseStr$ + "/(2*pi) - floor(" + rateStr$ + "*x + " + phaseStr$ + "/(2*pi) + 0.5)))"
endif

# Pan position is center + depth*modulator, clamped to the legal stereo range.
# The visualization already used this clamp; v0.4.1 made the DSP identical.
panPositionFormula$ = "(" + centerStr$ + " + " + depthStr$ + "*" + modFormula$ + ")"
panClampedFormula$ = "(if " + panPositionFormula$ + " < -1 then -1 else if " + panPositionFormula$ + " > 1 then 1 else " + panPositionFormula$ + " fi fi)"

# Pan angle formula: 0.5*pi * normalized_pan_position
# normalized_pan = (pan_clamped + 1) / 2
# This gives panAngle from 0 (full left) to pi/2 (full right).
panAngleFormula$ = "0.5*pi * (0.5 + 0.5*" + panClampedFormula$ + ")"

# CRITICAL FIX: Use 'row' to detect channel, not 'col'!
# row=1 is left channel, row=2 is right channel
# Left uses cos(panAngle), Right uses sin(panAngle) for constant-power panning
panFormula$ = "if row = 1 then self * cos(" + panAngleFormula$ + ") else self * sin(" + panAngleFormula$ + ") fi"

# Apply panning in single pass
selectObject: result
appendInfoLine: "Applying panning..."
Formula: panFormula$

# ============================================================
# WET/DRY MIX
# ============================================================

if dryLevel > 0
    wetStr$ = string$(wetLevel)
    dryStr$ = string$(dryLevel)
    dryIdStr$ = string$(drySound)
    
    selectObject: result
    Formula: "self * " + wetStr$ + " + Object_" + dryIdStr$ + "[row, col] * " + dryStr$
    
    # Cleanup dry copy
    selectObject: drySound
    Remove
endif

# Rename and scale
selectObject: result
Rename: originalName$ + "_pan_" + presetName$
Scale peak: 0.99

resultName$ = selected$("Sound")

# ============================================================
# CLEANUP
# ============================================================

selectObject: monoSource
Remove

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Simple Rate Panning: " + presetName$ + " (" + waveName$ + " @ " + fixed$(pan_rate_Hz, 2) + " Hz)" + " | v0.4.2"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.5, 1.7
    Select inner viewport: 0.60, 7.70, 0.65, 1.55
    selectObject: original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 0.5, 1.7
    Select inner viewport: 0.08, 0.52, 0.52, 1.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Original"
    Select outer viewport: 0, 8, 0.5, 1.7
    Select inner viewport: 0.60, 7.70, 0.65, 1.55
    
    # Result waveform
    Select outer viewport: 0, 8, 1.7, 2.9
    Select inner viewport: 0.60, 7.70, 1.85, 2.75
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 1.7, 2.9
    Select inner viewport: 0.08, 0.52, 1.72, 2.88
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Panned"
    Select outer viewport: 0, 8, 1.7, 2.9
    Select inner viewport: 0.60, 7.70, 1.85, 2.75
    Text bottom: "yes", "Time (s)"
    
    # Pan modulator visualization
    Select outer viewport: 0, 8, 3.1, 4.6
    Select inner viewport: 0.60, 7.70, 3.25, 4.45
    
    Axes: 0, dur, -1.2, 1.2
    
    # Background
    Colour: "{0.97, 0.97, 0.97}"
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -1.2, 1.2
    
    # Center line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, dur, 0
    
    # Pan center line
    if pan_center <> 0
        Colour: "{0.9, 0.8, 0.8}"
        Dotted line
        Draw line: 0, pan_center, dur, pan_center
        Solid line
    endif
    
    # L/R labels
    Font size: 6
    Colour: "{0.6, 0.6, 0.6}"
    Text: dur * 0.01, "left", -1.0, "half", "L"
    Text: dur * 0.01, "left", 1.0, "half", "R"
    
    # Draw pan trajectory
    Colour: "{0.2, 0.6, 0.4}"
    Line width: 2
    
    numDrawPoints = 500
    if numDrawPoints > dur * 1000
        numDrawPoints = round(dur * 1000)
    endif
    if numDrawPoints < 100
        numDrawPoints = 100
    endif
    
    for i from 2 to numDrawPoints
        t1 = (i - 2) / (numDrawPoints - 1) * dur
        t2 = (i - 1) / (numDrawPoints - 1) * dur
        
        # Calculate modulator value
        if waveform = 1
            # Sine
            mod1 = sin(2 * pi * pan_rate_Hz * t1 + phaseRad)
            mod2 = sin(2 * pi * pan_rate_Hz * t2 + phaseRad)
        elsif waveform = 2
            # Triangle
            phase1 = pan_rate_Hz * t1 + phaseRad / (2 * pi)
            phase2 = pan_rate_Hz * t2 + phaseRad / (2 * pi)
            mod1 = 2 * abs(2 * (phase1 - floor(phase1 + 0.5))) - 1
            mod2 = 2 * abs(2 * (phase2 - floor(phase2 + 0.5))) - 1
        elsif waveform = 3
            # Square
            if sin(2 * pi * pan_rate_Hz * t1 + phaseRad) >= 0
                mod1 = 1
            else
                mod1 = -1
            endif
            if sin(2 * pi * pan_rate_Hz * t2 + phaseRad) >= 0
                mod2 = 1
            else
                mod2 = -1
            endif
        else
            # Sawtooth
            phase1 = pan_rate_Hz * t1 + phaseRad / (2 * pi)
            phase2 = pan_rate_Hz * t2 + phaseRad / (2 * pi)
            mod1 = 2 * (phase1 - floor(phase1 + 0.5))
            mod2 = 2 * (phase2 - floor(phase2 + 0.5))
        endif
        
        # Apply depth and center
        pan1 = pan_center + depth * mod1
        pan2 = pan_center + depth * mod2
        
        # Clamp
        if pan1 < -1
            pan1 = -1
        elsif pan1 > 1
            pan1 = 1
        endif
        if pan2 < -1
            pan2 = -1
        elsif pan2 > 1
            pan2 = 1
        endif
        
        Draw line: t1, pan1, t2, pan2
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 3.1, 4.6
    Select inner viewport: 0.08, 0.52, 3.12, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Pan"
    Select outer viewport: 0, 8, 3.1, 4.6
    Select inner viewport: 0.60, 7.70, 3.25, 4.45
    Axes: 0, dur, -1.2, 1.2
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Pan Position (L=-1, R=+1)"
    
    # === SUMMARY ===
    Select outer viewport: 0, 8, 4.75, 5.55
    Select inner viewport: 0.60, 7.70, 4.82, 5.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.76, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.02, "left", 0.46, "half", presetName$ + " | " + waveName$ + " | Rate " + fixed$(pan_rate_Hz, 2) + " Hz | Depth " + fixed$(pan_depth_percent, 0) + "\%  "
    Text: 0.02, "left", 0.18, "half", "Center " + fixed$(pan_center, 2) + " | Phase " + fixed$(start_phase_degrees, 0) + " deg | Mix " + fixed$(mix_percent, 0) + "\%  | Duration " + fixed$(dur, 2) + " s"
    Select inner viewport: 0.60, 7.70, 4.82, 5.48
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0, 8, 0, 5.65
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Original: ", originalName$
appendInfoLine: "Result: ", resultName$
appendInfoLine: ""

if play_result
    selectObject: result
    Play
endif
