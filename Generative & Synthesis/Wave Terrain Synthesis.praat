# ============================================================
# Praat AudioTools - Wave Terrain Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave Terrain Synthesis
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Wave Terrain Synthesis

form Wave Terrain Synthesis
    comment Preset (overrides manual settings if selected)
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
    comment Manual Settings (if Custom preset selected)
    positive Duration 1.0
    positive Sample_rate 22500
    comment Terrain Settings
    positive Terrain_size 128
    optionmenu Terrain_type 1
        option Sine product
        option Chebyshev
        option Random
        option Fractal
        option Spiral
    real Terrain_scale 1.0
    comment Trajectory Settings
    positive X_frequency 220
    positive Y_frequency 330
    real X_phase 0
    real Y_phase 90
    optionmenu X_trajectory 1
        option Sine
        option Triangle
        option Saw
        option Square
    optionmenu Y_trajectory 1
        option Sine
        option Triangle
        option Saw
        option Square
    real X_amplitude 0.8
    real Y_amplitude 0.8
    real X_offset 0.5
    real Y_offset 0.5
    comment Modulation
    real X_freq_mod 0
    real Y_freq_mod 0
    real Mod_depth 0.5
    comment Output
    positive Output_gain 0.5
endform

# Apply presets
if preset = 2
    terrain_type = 1
    terrain_scale = 1.0
    x_frequency = 220
    y_frequency = 330
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.9
    y_amplitude = 0.9
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 0
    y_freq_mod = 0
    terrain_size = 128
elsif preset = 3
    terrain_type = 2
    terrain_scale = 1.0
    x_frequency = 165
    y_frequency = 247
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.7
    y_amplitude = 0.7
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 0
    y_freq_mod = 0
    terrain_size = 128
elsif preset = 4
    terrain_type = 4
    terrain_scale = 1.5
    x_frequency = 110
    y_frequency = 165
    x_trajectory = 2
    y_trajectory = 3
    x_amplitude = 0.95
    y_amplitude = 0.95
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 2.3
    y_freq_mod = 3.7
    mod_depth = 0.3
    terrain_size = 96
elsif preset = 5
    terrain_type = 5
    terrain_scale = 2.0
    x_frequency = 130
    y_frequency = 195
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.85
    y_amplitude = 0.85
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 0.5
    y_freq_mod = 0.7
    mod_depth = 0.4
    terrain_size = 128
elsif preset = 6
    terrain_type = 1
    terrain_scale = 2.0
    x_frequency = 440
    y_frequency = 660
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.6
    y_amplitude = 0.6
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 6.5
    y_freq_mod = 9.8
    mod_depth = 0.7
    terrain_size = 96
elsif preset = 7
    terrain_type = 3
    terrain_scale = 1.0
    x_frequency = 82.4
    y_frequency = 123.6
    x_trajectory = 4
    y_trajectory = 2
    x_amplitude = 0.9
    y_amplitude = 0.9
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 0.2
    y_freq_mod = 0.3
    mod_depth = 0.6
    terrain_size = 128
elsif preset = 8
    terrain_type = 1
    terrain_scale = 3.0
    x_frequency = 8
    y_frequency = 440
    x_trajectory = 4
    y_trajectory = 1
    x_amplitude = 0.8
    y_amplitude = 0.5
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 0
    y_freq_mod = 0
    terrain_size = 128
elsif preset = 9
    terrain_type = 1
    terrain_scale = 0.5
    x_frequency = 55
    y_frequency = 82.5
    x_trajectory = 1
    y_trajectory = 1
    x_amplitude = 0.95
    y_amplitude = 0.95
    x_offset = 0.5
    y_offset = 0.5
    x_freq_mod = 0.1
    y_freq_mod = 0.15
    mod_depth = 0.2
    terrain_size = 96
endif

# Ensure integer
tsize = round(terrain_size)

# Create terrain
writeInfoLine: "Creating ", tsize, "x", tsize, " terrain..."
terrain = Create Matrix: "terrain", 1, tsize, tsize, 1, 1, 1, tsize, tsize, 1, 1, "0"

# Fill terrain manually
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
    selectObject: temp_terrain
    Remove
    selectObject: terrain
endif

max_val = Get maximum
min_val = Get minimum
Formula: "(self - min_val) / (max_val - min_val) * 2 - 1"

# Visualize terrain
selectObject: terrain
Erase all
Select inner viewport: 1, 6, 1, 4
Paint image: 0, 0, 0, 0, -1, 1
Draw inner box
Text top: "yes", "Wave Terrain: " + terrain_type$
Marks left every: 1, 0.5, "yes", "yes", "no"
Marks bottom every: 1, 0.5, "yes", "yes", "no"

selectObject: terrain
Select inner viewport: 1, 6, 4.5, 7.5
Draw one contour: 0, 0, 0, 0, -0.75
Draw one contour: 0, 0, 0, 0, -0.5
Draw one contour: 0, 0, 0, 0, -0.25
Draw one contour: 0, 0, 0, 0, 0
Draw one contour: 0, 0, 0, 0, 0.25
Draw one contour: 0, 0, 0, 0, 0.5
Draw one contour: 0, 0, 0, 0, 0.75
Draw inner box
Text top: "yes", "Contour Map"

# Create time base
samples = duration * sample_rate
sound_dummy = Create Sound from formula: "dummy", 1, 0, duration, sample_rate, "0"

# Create X trajectory
selectObject: sound_dummy
x_traj = Copy: "x_traj"
if x_trajectory = 1
    Formula: "x_amplitude * sin(2*pi*x_frequency*x + x_phase*pi/180) + x_offset"
elsif x_trajectory = 2
    Formula: "x_amplitude * (2*abs(2*((x*x_frequency) mod 1) - 1) - 1) + x_offset"
elsif x_trajectory = 3
    Formula: "x_amplitude * (2*((x*x_frequency) mod 1) - 1) + x_offset"
elsif x_trajectory = 4
    Formula: "x_amplitude * (if ((x*x_frequency) mod 1) < 0.5 then 1 else -1 fi) + x_offset"
endif

if x_freq_mod > 0
    selectObject: x_traj
    Formula: "self * (1 + mod_depth * sin(2*pi*x_freq_mod*x)) + x_offset"
endif

selectObject: x_traj
Formula: "max(0, min(1, self))"
Formula: "round(self * (tsize - 1) + 1)"

# Create Y trajectory
selectObject: sound_dummy
y_traj = Copy: "y_traj"
if y_trajectory = 1
    Formula: "y_amplitude * sin(2*pi*y_frequency*x + y_phase*pi/180) + y_offset"
elsif y_trajectory = 2
    Formula: "y_amplitude * (2*abs(2*((x*y_frequency) mod 1) - 1) - 1) + y_offset"
elsif y_trajectory = 3
    Formula: "y_amplitude * (2*((x*y_frequency) mod 1) - 1) + y_offset"
elsif y_trajectory = 4
    Formula: "y_amplitude * (if ((x*y_frequency) mod 1) < 0.5 then 1 else -1 fi) + y_offset"
endif

if y_freq_mod > 0
    selectObject: y_traj
    Formula: "self * (1 + mod_depth * sin(2*pi*y_freq_mod*x)) + y_offset"
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

# GENERATE AUDIO
writeInfoLine: "Generating wave terrain audio..."
appendInfoLine: "Samples: ", samples

progress_step = max(1, floor(samples / 20))

for i from 1 to samples
    selectObject: x_matrix
    x_idx = Get value in cell: 1, i
    selectObject: y_matrix
    y_idx = Get value in cell: 1, i
    
    x_idx = max(1, min(tsize, x_idx))
    y_idx = max(1, min(tsize, y_idx))
    
    selectObject: terrain
    val = Get value in cell: y_idx, x_idx
    
    selectObject: output
    Set value at sample number: 1, i, val * output_gain
    
    if i mod progress_step = 0
        percent = floor(i / samples * 100)
        appendInfoLine: "Progress: ", percent, "%"
    endif
endfor

# Cleanup
selectObject: sound_dummy, x_traj, y_traj, x_matrix, y_matrix, terrain
Remove

# Finalize
selectObject: output
Scale peak: 0.99

# Report
writeInfoLine: "Wave terrain synthesis complete!"
appendInfoLine: "Duration: ", duration, " s"
appendInfoLine: "Terrain: ", tsize, "x", tsize
appendInfoLine: "X: ", x_frequency, " Hz (", x_trajectory$, ")"
appendInfoLine: "Y: ", y_frequency, " Hz (", y_trajectory$, ")"

# Play the result
selectObject: output
Play