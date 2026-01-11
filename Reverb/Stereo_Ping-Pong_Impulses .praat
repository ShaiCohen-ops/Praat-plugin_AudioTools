# ============================================================
# Praat AudioTools - Stereo_Ping_Pong_Impulses.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Ping-Pong Impulses - convolution-based alternating
#   L/R delay effect. Creates two impulse trains with offset
#   timing, converts to pulse trains, and convolves with input.
#   Different from formula-based ping-pong: uses convolution
#   for cleaner, more rhythmic character.
#
# Changelog v0.2:
#   - Fixed name-based references (all ID-based)
#   - Added wet/dry mix control
#   - Added visualization
#   - Better preset names
# ============================================================

form Stereo Ping-Pong Impulses
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Default (balanced)
        option Tight Ping-Pong
        option Wide and Slow
        option Rapid Micro-Taps
        option Offbeat Start
        option Custom (use settings below)
    
    comment === Timing ===
    positive Duration_s 1.6
    positive Step_interval_s 0.22
    positive Jitter_s 0.01
    positive Initial_delay_s 0.10
    
    comment === Pulse Parameters ===
    positive Pulse_width_s 0.03
    positive Pulse_period 2000
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    duration_s = 1.6
    step_interval_s = 0.22
    jitter_s = 0.01
    initial_delay_s = 0.10
    pulse_width_s = 0.03
    pulse_period = 2000
    presetName$ = "Default"
elsif preset = 2
    # Tight Ping-Pong
    duration_s = 1.0
    step_interval_s = 0.15
    jitter_s = 0.005
    initial_delay_s = 0.08
    pulse_width_s = 0.02
    pulse_period = 1500
    presetName$ = "Tight"
elsif preset = 3
    # Wide and Slow
    duration_s = 2.5
    step_interval_s = 0.35
    jitter_s = 0.012
    initial_delay_s = 0.12
    pulse_width_s = 0.04
    pulse_period = 2600
    presetName$ = "Wide"
elsif preset = 4
    # Rapid Micro-Taps
    duration_s = 1.2
    step_interval_s = 0.08
    jitter_s = 0.003
    initial_delay_s = 0.05
    pulse_width_s = 0.015
    pulse_period = 1200
    presetName$ = "Rapid"
elsif preset = 5
    # Offbeat Start
    duration_s = 1.8
    step_interval_s = 0.22
    jitter_s = 0.02
    initial_delay_s = 0.17
    pulse_width_s = 0.03
    pulse_period = 2000
    presetName$ = "Offbeat"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Count impulses for visualization
numLeftImp = 0
numRightImp = 0
t = initial_delay_s
while t < duration_s
    numLeftImp = numLeftImp + 1
    leftTime[numLeftImp] = t
    t = t + 2 * step_interval_s
endwhile

t = initial_delay_s + step_interval_s
while t < duration_s
    numRightImp = numRightImp + 1
    rightTime[numRightImp] = t
    t = t + 2 * step_interval_s
endwhile

# === Info ===
writeInfoLine: "=== Stereo Ping-Pong Impulses ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "IR duration: ", duration_s, " s"
appendInfoLine: "Step interval: ", step_interval_s * 1000, " ms"
appendInfoLine: "Initial delay: ", initial_delay_s * 1000, " ms"
appendInfoLine: "Jitter: ±", jitter_s * 1000, " ms"
appendInfoLine: "Left impulses: ", numLeftImp
appendInfoLine: "Right impulses: ", numRightImp
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# Convert to mono for processing
selectObject: original
if numChannels = 2
    Convert to mono
    monoSource = selected("Sound")
else
    Copy: "mono_source"
    monoSource = selected("Sound")
endif

# === Build Left PointProcess ===
Create empty PointProcess: "pp_left", 0, duration_s
ppLeft = selected("PointProcess")

t = initial_delay_s
while t < duration_s
    u = t + randomUniform(-jitter_s, jitter_s)
    if u > 0 and u < duration_s
        selectObject: ppLeft
        Add point: u
    endif
    t = t + 2 * step_interval_s
endwhile

# === Build Right PointProcess ===
Create empty PointProcess: "pp_right", 0, duration_s
ppRight = selected("PointProcess")

t = initial_delay_s + step_interval_s
while t < duration_s
    u = t + randomUniform(-jitter_s, jitter_s)
    if u > 0 and u < duration_s
        selectObject: ppRight
        Add point: u
    endif
    t = t + 2 * step_interval_s
endwhile

# === Convert to Pulse Trains ===
selectObject: ppLeft
To Sound (pulse train): sr, 1, pulse_width_s, pulse_period
impLeft = selected("Sound")
Scale peak: 0.99

selectObject: ppRight
To Sound (pulse train): sr, 1, pulse_width_s, pulse_period
impRight = selected("Sound")
Scale peak: 0.99

# === Convolve ===
appendInfoLine: "  Convolving left..."
selectObject: monoSource, impLeft
Convolve: "sum", "zero"
resLeft = selected("Sound")
Scale peak: 0.95

appendInfoLine: "  Convolving right..."
selectObject: monoSource, impRight
Convolve: "sum", "zero"
resRight = selected("Sound")
Scale peak: 0.95

# === Apply Wet/Dry ===
if dry_level > 0
    # Extend mono source to match convolved length
    selectObject: resLeft
    wetDur = Get total duration
    
    selectObject: monoSource
    dryDur = Get total duration
    
    if dryDur < wetDur
        Create Sound from formula: "sil_pad", 1, 0, wetDur - dryDur, sr, "0"
        silPad = selected("Sound")
        selectObject: monoSource, silPad
        Concatenate
        dryExt = selected("Sound")
        removeObject: silPad
    else
        selectObject: monoSource
        Copy: "dry_ext"
        dryExt = selected("Sound")
    endif
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dryExt)
    
    selectObject: resLeft
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
    
    selectObject: resRight
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
    
    removeObject: dryExt
endif

# === Combine to Stereo ===
selectObject: resLeft, resRight
Combine to stereo
result = selected("Sound")
Rename: originalName$ + "_pingpong_" + presetName$
Scale peak: 0.98

# === Cleanup ===
removeObject: monoSource, ppLeft, ppRight, impLeft, impRight, resLeft, resRight

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Ping-Pong Impulses: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform (show stereo)
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.8}"
    Draw: 0, originalDur + duration_s * 0.5, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Ping-Pong " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Impulse pattern diagram
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    Axes: 0, duration_s, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration_s, -1.2, 1.2
    
    # Center line
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, duration_s, 0
    
    # Left impulses (top)
    Colour: "{0.5, 0.7, 0.9}"
    for i from 1 to numLeftImp
        t = leftTime[i]
        Draw line: t, 0, t, 0.8
        Paint circle (mm): "{0.5, 0.7, 0.9}", t, 0.8, 1.5
    endfor
    
    # Right impulses (bottom)
    Colour: "{0.9, 0.6, 0.5}"
    for i from 1 to numRightImp
        t = rightTime[i]
        Draw line: t, 0, t, -0.8
        Paint circle (mm): "{0.9, 0.6, 0.5}", t, -0.8, 1.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "L ← → R"
    Text bottom: "yes", "Time (s)"
    
    # Labels
    Font size: 5
    Colour: "{0.5, 0.7, 0.9}"
    Text: duration_s * 0.9, "centre", 1.0, "half", "LEFT (" + string$(numLeftImp) + ")"
    Colour: "{0.9, 0.6, 0.5}"
    Text: duration_s * 0.9, "centre", -1.0, "half", "RIGHT (" + string$(numRightImp) + ")"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "IR: " + fixed$(duration_s, 1) + "s | Step: " + fixed$(step_interval_s * 1000, 0) + "ms | Jitter: ±" + fixed$(jitter_s * 1000, 1) + "ms | Pulse: " + fixed$(pulse_width_s * 1000, 0) + "ms"
    
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
