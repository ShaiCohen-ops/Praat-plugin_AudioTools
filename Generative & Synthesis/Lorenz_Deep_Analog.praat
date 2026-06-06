# ============================================================
# Praat AudioTools - Lorenz_Attractor_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Lorenz attractor synthesis - the classic 3D chaotic system.
#   
#   The Lorenz equations (1963):
#     dx/dt = sigma(y - x)
#     dy/dt = x(rho - z) - y
#     dz/dt = xy - betaz
#
#   Classic parameters: sigma=10, beta=8/3, rho=28
#   
#   Audio mapping:
#     x -> pitch modulation
#     y -> amplitude modulation  
#     z -> stereo position (in stereo mode)
#
# Usage:
#   Run this script (no input sound required).
#
# Changelog v0.2:
#   - Uses all 3 dimensions, spatial modes, spectrogram panel, fade
#
# Changelog v0.3:
#   - Visualization aligned to AudioTools house style: title in its own band,
#     grey summary panel (was a plain footer), larger fonts, full-precision RGB.
#   - Replaced non-ASCII characters (Greek sigma/rho/beta, arrows, em-dash).
# ============================================================

form Lorenz Attractor Synthesis
    comment === Preset ===
    optionmenu Preset 2
        option Custom (use settings below)
        option Standard Butterfly
        option Deep Drone (slow)
        option Nervous Insect (fast)
        option Unstable Giant (high rho)
        option Gentle Spiral
    
    comment === Basic Settings ===
    positive Duration_s 15.0
    positive Base_pitch_Hz 200
    
    comment === Lorenz Parameters ===
    positive Chaos_speed 0.005
    positive Rho 28.0
    positive Sigma 10.0
    positive Beta 2.6667
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo (z-axis panning)
        option Stereo (x-y split)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"
scaleMinX = -25
scaleMaxX = 25
scaleMaxZ = 50

if preset = 2
    # Standard Butterfly
    duration_s = 15.0
    base_pitch_Hz = 200
    chaos_speed = 0.005
    rho = 28.0
    sigma = 10.0
    beta = 2.6667
    preset_name$ = "StandardButterfly"
    
elsif preset = 3
    # Deep Drone
    duration_s = 30.0
    base_pitch_Hz = 60
    chaos_speed = 0.001
    rho = 28.0
    sigma = 10.0
    beta = 2.6667
    preset_name$ = "DeepDrone"
    
elsif preset = 4
    # Nervous Insect
    duration_s = 10.0
    base_pitch_Hz = 350
    chaos_speed = 0.015
    rho = 28.0
    sigma = 10.0
    beta = 2.6667
    preset_name$ = "NervousInsect"
    
elsif preset = 5
    # Unstable Giant
    duration_s = 20.0
    base_pitch_Hz = 120
    chaos_speed = 0.004
    rho = 90.0
    sigma = 10.0
    beta = 2.6667
    scaleMinX = -50
    scaleMaxX = 50
    scaleMaxZ = 160
    preset_name$ = "UnstableGiant"
    
elsif preset = 6
    # Gentle Spiral
    duration_s = 20.0
    base_pitch_Hz = 150
    chaos_speed = 0.002
    rho = 20.0
    sigma = 10.0
    beta = 2.6667
    preset_name$ = "GentleSpiral"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
controlRate = 500
sampleRate = 44100

# === Info ===
writeInfoLine: "=== Lorenz Attractor Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Parameters: sigma=", sigma, " rho=", rho, " beta=", fixed$(beta, 4)
appendInfoLine: "Chaos speed: ", chaos_speed
appendInfoLine: "Base pitch: ", base_pitch_Hz, " Hz"
appendInfoLine: ""

# === Compute Lorenz System ===
appendInfoLine: "Computing Lorenz attractor..."

totalCtrlSamples = round(duration_s * controlRate)

# Create control-rate sounds for x, y, z
ctrlX = Create Sound from formula: "ctrl_x_" + uid$, 1, 0, duration_s, controlRate, "0"
ctrlY = Create Sound from formula: "ctrl_y_" + uid$, 1, 0, duration_s, controlRate, "0"
ctrlZ = Create Sound from formula: "ctrl_z_" + uid$, 1, 0, duration_s, controlRate, "0"

# Initial conditions
lx = 0.1
ly = 0.1
lz = 0.1

# Store for visualization
for i to totalCtrlSamples
    # Lorenz equations (Euler integration)
    dx = sigma * (ly - lx) * chaos_speed
    dy = (lx * (rho - lz) - ly) * chaos_speed
    dz = (lx * ly - beta * lz) * chaos_speed
    
    # Update state
    lx = lx + dx
    ly = ly + dy
    lz = lz + dz
    
    # Store values
    selectObject: ctrlX
    Set value at sample number: 1, i, lx
    selectObject: ctrlY
    Set value at sample number: 1, i, ly
    selectObject: ctrlZ
    Set value at sample number: 1, i, lz
endfor

# Get ranges for normalization
selectObject: ctrlX
xMin = Get minimum: 0, 0, "None"
xMax = Get maximum: 0, 0, "None"
xRange = xMax - xMin

selectObject: ctrlY
yMin = Get minimum: 0, 0, "None"
yMax = Get maximum: 0, 0, "None"
yRange = yMax - yMin

selectObject: ctrlZ
zMin = Get minimum: 0, 0, "None"
zMax = Get maximum: 0, 0, "None"
zRange = zMax - zMin

appendInfoLine: "X range: ", fixed$(xMin, 2), " to ", fixed$(xMax, 2)
appendInfoLine: "Y range: ", fixed$(yMin, 2), " to ", fixed$(yMax, 2)
appendInfoLine: "Z range: ", fixed$(zMin, 2), " to ", fixed$(zMax, 2)

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing Lorenz attractor..."
    
    Erase all
    
    # === Title (own clear band) ===
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Lorenz Attractor: " + preset_name$
    
    # === Butterfly Plot (X vs Z) ===
    Select outer viewport: 0, 4, 0.9, 4.4
    Select inner viewport: 0.7, 3.6, 1.05, 4.2
    Axes: scaleMinX, scaleMaxX, 0, scaleMaxZ
    
    # Background
    Colour: "{0.98, 0.98, 0.98}"
    Paint rectangle: "{0.98, 0.98, 0.98}", scaleMinX, scaleMaxX, 0, scaleMaxZ
    
    # Draw attractor
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1
    
    selectObject: ctrlX
    prevX = Get value at sample number: 1, 1
    selectObject: ctrlZ
    prevZ = Get value at sample number: 1, 1
    
    # Draw every 2nd point for speed
    for i from 2 to totalCtrlSamples
        if (i mod 2) = 0
            selectObject: ctrlX
            currX = Get value at sample number: 1, i
            selectObject: ctrlZ
            currZ = Get value at sample number: 1, i
            
            # Color gradient based on time
            timeRatio = i / totalCtrlSamples
            r = 0.2 + 0.5 * timeRatio
            g = 0.4 - 0.2 * timeRatio
            b = 0.8 - 0.4 * timeRatio
            Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            
            Draw line: prevX, prevZ, currX, currZ
            prevX = currX
            prevZ = currZ
        endif
    endfor
    
    # Mark final position
    Colour: "{0.90, 0.20, 0.20}"
    selectObject: ctrlX
    finalX = Get value at sample number: 1, totalCtrlSamples
    selectObject: ctrlZ
    finalZ = Get value at sample number: 1, totalCtrlSamples
    Paint circle (mm): "{0.90, 0.20, 0.20}", finalX, finalZ, 2
    
    # Box and labels
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Marks bottom every: 1, 10, "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "X (pitch)"
    Text left: "yes", "Z (position)"
endif

# === Audio Synthesis ===
appendInfoLine: ""
appendInfoLine: "Synthesizing audio..."

# Resample control signals to audio rate
selectObject: ctrlX
xAudio = Resample: sampleRate, 50
Rename: "x_audio_" + uid$

selectObject: ctrlY
yAudio = Resample: sampleRate, 50
Rename: "y_audio_" + uid$

selectObject: ctrlZ
zAudio = Resample: sampleRate, 50
Rename: "z_audio_" + uid$

# Normalize x and y to useful ranges
selectObject: xAudio
Formula: "(self - xMin) / xRange"

selectObject: yAudio
Formula: "(self - yMin) / yRange"

selectObject: zAudio
Formula: "(self - zMin) / zRange"

# Create output sound
# x modulates pitch, y modulates amplitude
outputSound = Create Sound from formula: "lorenz_" + uid$, 1, 0, duration_s, sampleRate,
    ... "0.5 * (0.3 + 0.7 * Sound_y_audio_" + uid$ + "[]) * sin(twoPi * (base_pitch_Hz * (0.5 + Sound_x_audio_" + uid$ + "[])) * x)"

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo (z-axis panning)
    appendInfoLine: "Creating z-axis stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (1 - Sound_z_audio_" + uid$ + "[])"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * Sound_z_audio_" + uid$ + "[]"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "lorenz_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Stereo (x-y split)
    appendInfoLine: "Creating x-y stereo split..."
    
    # Left channel: x-modulated
    leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sampleRate,
        ... "0.4 * (0.3 + 0.7 * Sound_y_audio_" + uid$ + "[]) * sin(twoPi * (base_pitch_Hz * (0.5 + Sound_x_audio_" + uid$ + "[])) * x)"
    
    # Right channel: y-modulated pitch, x-modulated amplitude
    rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sampleRate,
        ... "0.4 * (0.3 + 0.7 * Sound_x_audio_" + uid$ + "[]) * sin(twoPi * (base_pitch_Hz * 1.5 * (0.5 + Sound_y_audio_" + uid$ + "[])) * x)"
    
    # Fade
    selectObject: leftSound
    Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
    Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"
    
    selectObject: rightSound
    Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
    Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "lorenz_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "lorenz_" + preset_name$
endif

# === Cleanup control signals ===
removeObject: ctrlX, ctrlY, ctrlZ, xAudio, yAudio, zAudio

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Add spectrogram to visualization ===
if draw_visualization
    Select outer viewport: 4, 8, 0.9, 4.4
    Select inner viewport: 4.6, 7.7, 1.05, 4.2
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        monoSpec = selected("Sound")
    endif
    
    selectObject: monoSpec
    maxFreqSpec = base_pitch_Hz * 3
    To Spectrogram: 0.05, maxFreqSpec, 0.01, 20, "Gaussian"
    spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: monoSpec, spec
    
    Select inner viewport: 4.6, 7.7, 1.05, 4.2
    Axes: 0, duration_s, 0, maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 5, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # Summary panel (grey)
    Select outer viewport: 0, 8, 4.6, 5.0
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "sigma=" + fixed$(sigma, 1) + " rho=" + fixed$(rho, 1) + " beta=" + fixed$(beta, 3) + " | Base: " + fixed$(base_pitch_Hz, 0) + " Hz | x->pitch, y->amp, z->pan | Left: butterfly (X vs Z), Right: spectrogram"
    Font size: 10
    Colour: "Black"
endif

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