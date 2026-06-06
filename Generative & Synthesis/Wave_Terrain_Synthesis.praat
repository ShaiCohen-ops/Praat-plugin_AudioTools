# ============================================================
# Praat AudioTools - Wave_Terrain_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave Terrain Synthesis - a classic computer music technique.
#   Creates a 2D surface (terrain) and traces X/Y trajectories
#   across it. The terrain height at each point becomes the
#   audio sample value, creating complex timbres from simple
#   geometric relationships.
#
#   Technique pioneered by Mitsuhashi (1982) and Roads.
#
# Usage:
#   Run this script (no input required).
#   Select a preset or customize terrain/trajectory settings.
#
# Changelog v0.2:
#   - Added play option, improved info output
#
# Changelog v0.3:
#   - Replaced the per-sample terrain-lookup loop (Get/Set + selectObject every
#     sample) with a single vectorized Formula gather. Bit-identical output,
#     vastly faster (verified max sample difference = 0).
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, terrain surface + contour + output waveform + spectrogram,
#     grey summary, larger fonts). Added a Draw_visualization toggle.
#   - Removed the over-dense matrix-index tick marks on the terrain-surface
#     panel (they smeared into the margin); the panel now matches the contour map.
#   - Replaced the non-ASCII multiplication sign.
# ============================================================

form Wave Terrain Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use manual settings below)
        option Classic Sine Terrain
        option Metallic Chebyshev
        option Chaotic Fractal
        option Spiral Galaxy
        option FM Complex
        option Alien Landscape
        option Rhythmic Pulses
        option Smooth Ambient
    
    comment === Duration & Sample Rate ===
    positive Duration_s 3.0
    positive Sample_rate_Hz 22050
    
    comment === Terrain Settings ===
    integer Terrain_size 128
    optionmenu Terrain_type 1
        option Sine product
        option Chebyshev
        option Random
        option Fractal
        option Spiral
    real Terrain_scale 1.0
    
    comment === X Trajectory ===
    positive X_frequency_Hz 220
    optionmenu X_trajectory 1
        option Sine
        option Triangle
        option Saw
        option Square
    real X_amplitude 0.8
    real X_phase_deg 0
    real X_offset 0.5
    real X_freq_mod_Hz 0
    
    comment === Y Trajectory ===
    positive Y_frequency_Hz 330
    optionmenu Y_trajectory 1
        option Sine
        option Triangle
        option Saw
        option Square
    real Y_amplitude 0.8
    real Y_phase_deg 90
    real Y_offset 0.5
    real Y_freq_mod_Hz 0
    
    comment === Modulation & Output ===
    real Mod_depth 0.5
    positive Output_gain 0.5
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 2
    terrain_type = 1
    terrain_scale = 1.0
    x_frequency_Hz = 220
    y_frequency_Hz = 330
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.9
    y_amplitude = 0.9
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 0
    y_freq_mod_Hz = 0
    terrain_size = 128
elsif preset = 3
    terrain_type = 2
    terrain_scale = 1.0
    x_frequency_Hz = 165
    y_frequency_Hz = 247
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.7
    y_amplitude = 0.7
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 0
    y_freq_mod_Hz = 0
    terrain_size = 128
elsif preset = 4
    terrain_type = 4
    terrain_scale = 1.5
    x_frequency_Hz = 110
    y_frequency_Hz = 165
    x_trajectory = 2
    y_trajectory = 3
    x_amplitude = 0.95
    y_amplitude = 0.95
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 2.3
    y_freq_mod_Hz = 3.7
    mod_depth = 0.3
    terrain_size = 96
elsif preset = 5
    terrain_type = 5
    terrain_scale = 2.0
    x_frequency_Hz = 130
    y_frequency_Hz = 195
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.85
    y_amplitude = 0.85
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 0.5
    y_freq_mod_Hz = 0.7
    mod_depth = 0.4
    terrain_size = 128
elsif preset = 6
    terrain_type = 1
    terrain_scale = 2.0
    x_frequency_Hz = 440
    y_frequency_Hz = 660
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.6
    y_amplitude = 0.6
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 6.5
    y_freq_mod_Hz = 9.8
    mod_depth = 0.7
    terrain_size = 96
elsif preset = 7
    terrain_type = 3
    terrain_scale = 1.0
    x_frequency_Hz = 82.4
    y_frequency_Hz = 123.6
    x_trajectory = 4
    y_trajectory = 2
    x_amplitude = 0.9
    y_amplitude = 0.9
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 0.2
    y_freq_mod_Hz = 0.3
    mod_depth = 0.6
    terrain_size = 128
elsif preset = 8
    terrain_type = 1
    terrain_scale = 3.0
    x_frequency_Hz = 8
    y_frequency_Hz = 440
    x_trajectory = 4
    y_trajectory = 1
    x_amplitude = 0.8
    y_amplitude = 0.5
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 0
    y_freq_mod_Hz = 0
    terrain_size = 128
elsif preset = 9
    terrain_type = 1
    terrain_scale = 0.5
    x_frequency_Hz = 55
    y_frequency_Hz = 82.5
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.95
    y_amplitude = 0.95
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod_Hz = 0.1
    y_freq_mod_Hz = 0.15
    mod_depth = 0.2
    terrain_size = 96
endif

# Ensure integer
tsize = round(terrain_size)

# === Info ===
writeInfoLine: "=== Wave Terrain Synthesis ==="
appendInfoLine: "Terrain: ", terrain_type$, " (", tsize, "x", tsize, ")"
appendInfoLine: "X trajectory: ", x_trajectory$, " @ ", x_frequency_Hz, " Hz"
appendInfoLine: "Y trajectory: ", y_trajectory$, " @ ", y_frequency_Hz, " Hz"
appendInfoLine: ""

# Create terrain
appendInfoLine: "Creating terrain..."
terrain = Create Matrix: "terrain", 1, tsize, tsize, 1, 1, 1, tsize, tsize, 1, 1, "0"

# Fill terrain
for i from 1 to tsize
    for j from 1 to tsize
        nx = (j - 1) / (tsize - 1)
        ny = (i - 1) / (tsize - 1)
        
        if terrain_type = 1
            val = sin(2*pi*nx*4*terrain_scale) * sin(2*pi*ny*4*terrain_scale)
        elsif terrain_type = 2
            val = (2*nx-1)^3 * (2*ny-1)^2 - (2*nx-1)^2 * (2*ny-1)^3
        elsif terrain_type = 3
            val = randomGauss(0, 1)
        elsif terrain_type = 4
            val = sin(2*pi*nx*2*terrain_scale) * sin(2*pi*ny*2*terrain_scale) + 0.5 * sin(2*pi*nx*4*terrain_scale) * sin(2*pi*ny*4*terrain_scale) + 0.25 * sin(2*pi*nx*8*terrain_scale) * sin(2*pi*ny*8*terrain_scale)
        elsif terrain_type = 5
            dist = sqrt((nx-0.5)^2 + (ny-0.5)^2)
            angle = arctan2(ny-0.5, nx-0.5)
            val = sin(2*pi*dist*10*terrain_scale + angle)
        endif
        
        Set value: i, j, val
    endfor
endfor

# Simple smoothing for random terrain
if terrain_type = 3
    temp_terrain = Copy: "temp"
    selectObject: terrain
    for i from 2 to tsize-1
        for j from 2 to tsize-1
            selectObject: temp_terrain
            v1 = Get value in cell: i-1, j
            v2 = Get value in cell: i+1, j
            v3 = Get value in cell: i, j-1
            v4 = Get value in cell: i, j+1
            v5 = Get value in cell: i, j
            avg = (v1 + v2 + v3 + v4 + v5) / 5
            selectObject: terrain
            Set value: i, j, avg
        endfor
    endfor
    removeObject: temp_terrain
    selectObject: terrain
endif

max_val = Get maximum
min_val = Get minimum
Formula: "(self - min_val) / (max_val - min_val) * 2 - 1"

# Create time base
samples = duration_s * sample_rate_Hz
sound_dummy = Create Sound from formula: "dummy", 1, 0, duration_s, sample_rate_Hz, "0"

# Create X trajectory
selectObject: sound_dummy
x_traj = Copy: "x_traj"
if x_trajectory = 1
    Formula: "x_amplitude * sin(2*pi*x_frequency_Hz*x + x_phase_deg*pi/180) + x_offset"
elsif x_trajectory = 2
    Formula: "x_amplitude * (2*abs(2*((x*x_frequency_Hz) mod 1) - 1) - 1) + x_offset"
elsif x_trajectory = 3
    Formula: "x_amplitude * (2*((x*x_frequency_Hz) mod 1) - 1) + x_offset"
elsif x_trajectory = 4
    Formula: "x_amplitude * (if ((x*x_frequency_Hz) mod 1) < 0.5 then 1 else -1 fi) + x_offset"
endif

if x_freq_mod_Hz > 0
    selectObject: x_traj
    Formula: "self * (1 + mod_depth * sin(2*pi*x_freq_mod_Hz*x)) + x_offset"
endif

selectObject: x_traj
Formula: "max(0, min(1, self))"
Formula: "round(self * (tsize - 1) + 1)"

# Create Y trajectory
selectObject: sound_dummy
y_traj = Copy: "y_traj"
if y_trajectory = 1
    Formula: "y_amplitude * sin(2*pi*y_frequency_Hz*x + y_phase_deg*pi/180) + y_offset"
elsif y_trajectory = 2
    Formula: "y_amplitude * (2*abs(2*((x*y_frequency_Hz) mod 1) - 1) - 1) + y_offset"
elsif y_trajectory = 3
    Formula: "y_amplitude * (2*((x*y_frequency_Hz) mod 1) - 1) + y_offset"
elsif y_trajectory = 4
    Formula: "y_amplitude * (if ((x*y_frequency_Hz) mod 1) < 0.5 then 1 else -1 fi) + y_offset"
endif

if y_freq_mod_Hz > 0
    selectObject: y_traj
    Formula: "self * (1 + mod_depth * sin(2*pi*y_freq_mod_Hz*x)) + y_offset"
endif

selectObject: y_traj
Formula: "max(0, min(1, self))"
Formula: "round(self * (tsize - 1) + 1)"

# Create output sound
selectObject: sound_dummy
output = Copy: "waveTerrain"

# Convert trajectories to matrices
selectObject: x_traj
x_matrix = Down to Matrix
selectObject: y_traj
y_matrix = Down to Matrix

# Generate audio: vectorized terrain lookup (one Formula gather instead of a
# per-sample Get/Set + selectObject loop). For each sample the X/Y trajectory
# matrices give the terrain indices, and the terrain height is read directly.
# Bit-identical to the old loop, but vastly faster.
appendInfoLine: "Generating audio (", samples, " samples)..."

selectObject: output
Formula: "object[terrain, max(1, min(tsize, object[y_matrix, 1, col])), max(1, min(tsize, object[x_matrix, 1, col]))] * output_gain"

# Finalize
selectObject: output
Scale peak: 0.95
Rename: "waveTerrain_" + terrain_type$
outputSound = selected("Sound")

# Visualization (terrain and trajectory matrices still alive)
if draw_visualization
    @drawVisualization
endif

# Cleanup
removeObject: sound_dummy, x_traj, y_traj, x_matrix, y_matrix, terrain

# Report
appendInfoLine: ""
appendInfoLine: "=== Done ==="
selectObject: outputSound
appendInfoLine: "Created: ", selected$("Sound")

# Play
if play_result
    selectObject: outputSound
    Play
endif

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Wave Terrain Synthesis: " + terrain_type$

    # --- Panel 1: Terrain surface ---
    Select outer viewport: 0, 4, 0.9, 3.4
    Select inner viewport: 0.7, 3.7, 1.05, 3.3
    selectObject: terrain
    Paint image: 0, 0, 0, 0, -1, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text bottom: "yes", "Terrain surface"

    # --- Panel 2: Contour map ---
    Select outer viewport: 4, 8, 0.9, 3.4
    Select inner viewport: 4.5, 7.5, 1.05, 3.3
    selectObject: terrain
    Draw one contour: 0, 0, 0, 0, -0.75
    Draw one contour: 0, 0, 0, 0, -0.5
    Draw one contour: 0, 0, 0, 0, -0.25
    Draw one contour: 0, 0, 0, 0, 0
    Draw one contour: 0, 0, 0, 0, 0.25
    Draw one contour: 0, 0, 0, 0, 0.5
    Draw one contour: 0, 0, 0, 0, 0.75
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text bottom: "yes", "Contour map"

    # --- Panel 3: Output waveform ---
    Select outer viewport: 0, 8, 3.6, 4.6
    Select inner viewport: 0.75, 7.6, 3.75, 4.5
    selectObject: outputSound
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text left: "yes", "Output"

    # --- Panel 4: Spectrogram ---
    Select outer viewport: 0, 8, 4.8, 6.3
    Select inner viewport: 0.75, 7.6, 4.95, 6.2
    selectObject: outputSound
    Copy: "ts_temp"
    .tmp = selected("Sound")
    To Spectrogram: 0.01, 8000, 0.002, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .tmp, .spec
    Select inner viewport: 0.75, 7.6, 4.95, 6.2
    Axes: 0, duration_s, 0, 8000
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 0.2, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 6.4, 6.8
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", terrain_type$ + " terrain (" + string$(tsize) + "x" + string$(tsize) + ") | X: " + x_trajectory$ + " @ " + fixed$(x_frequency_Hz, 0) + " Hz | Y: " + y_trajectory$ + " @ " + fixed$(y_frequency_Hz, 0) + " Hz"
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc