# ============================================================
# Praat AudioTools - Chaotic Granular Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic Granular Synthesis - generates evolving textures using
#   chaos theory (Logistic Map, Henon Map, Lorenz System) to control
#   grain parameters. Creates complex, non-repeating sonic textures.
#
# Usage:
#   Run this script directly (no input sound needed).
#   Adjust parameters via the form dialog.
#
# Changelog v1.0:
#   - Added comprehensive 4-panel visualization
#   - Added chaos trajectory display
#   - Added grain distribution plot
#   - Fixed clicks at chunk boundaries (envelope adjustment + crossfade)
#   - Improved info output
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.1:
#   - Fixed normalization: the Normalize_output toggle was collected but never
#     used, and only the Stereo path scaled its output, so Mono renders came out
#     unnormalised (quiet, level depending on density/layers). Normalization is
#     now a single post-spatial step that respects the toggle for both Mono and
#     Stereo.
#   - Visualization polished to the AudioTools house style (title band at font
#     14, grey {0.94} summary panel, larger panel fonts, full-precision RGB).
#   - Replaced the non-ASCII en-dash.
# ============================================================

# Advanced Chaotic Granular Synthesis (Ultra-Fast - Grain Limit Per Chunk)

form Advanced Chaotic Granular Synthesis System
    optionmenu Preset: 1
        option Custom (use settings below)
        option Logistic Sparse
        option Henon Texture
        option Lorenz Atmospheric
    
    comment === Custom Settings ===
    positive Duration_(sec) 10
    positive Base_frequency_(Hz) 120
    positive Grain_density_(grains/sec) 8
    integer Number_of_layers 3
    boolean Randomize_parameters 1
    positive Fade_time_(sec) 2
    optionmenu Synthesis_mode: 1
        option Logistic Map
        option Henon Map
        option Lorenz System
    optionmenu Spatial_mode: 1
        option Mono
        option Stereo Wide
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_after 1
endform

# Apply presets
if preset = 2
    duration = 10
    base_frequency = 120
    grain_density = 8
    number_of_layers = 3
    randomize_parameters = 1
    synthesis_mode = 1
    preset_name$ = "Logistic Sparse"
elsif preset = 3
    duration = 12
    base_frequency = 100
    grain_density = 6
    number_of_layers = 4
    randomize_parameters = 1
    synthesis_mode = 2
    spatial_mode = 2
    preset_name$ = "Henon Texture"
elsif preset = 4
    duration = 15
    base_frequency = 80
    grain_density = 5
    number_of_layers = 3
    randomize_parameters = 1
    synthesis_mode = 3
    preset_name$ = "Lorenz Atmospheric"
else
    preset_name$ = "Custom"
endif

# Get synthesis mode name
if synthesis_mode = 1
    mode$ = "Logistic Map"
elsif synthesis_mode = 2
    mode$ = "Henon Map"
else
    mode$ = "Lorenz System"
endif

# Get spatial mode name
if spatial_mode = 1
    spatial$ = "Mono"
else
    spatial$ = "Stereo Wide"
endif

if number_of_layers > 8
    number_of_layers = 8
endif

writeInfoLine: "=== Chaotic Granular Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Mode: ", mode$
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: ""

sample_rate = 44100
chunk_duration = 2.0
num_chunks = ceiling(duration / chunk_duration)

# Crossfade duration between chunks to eliminate clicks
chunk_crossfade = 0.01

# Conservative amplitude
base_amp_scale = 0.3 / number_of_layers

# Max grains per chunk to keep formula manageable
max_grains_per_chunk = 30

# Minimum grain duration (grains shorter than this are skipped)
min_grain_dur = 0.02

# Storage for visualization (collect grain data from all layers)
viz_grain_count = 0
max_viz_grains = 500

# Storage for chaos trajectory visualization
max_chaos_points = 200
for cp from 1 to max_chaos_points
    chaos_traj_x[cp] = 0
    chaos_traj_y[cp] = 0
endfor

total_grains_all = 0

# ====== PROCESS EACH LAYER ======
for layer from 1 to number_of_layers
    appendInfo: "Layer ", layer, "/", number_of_layers, "..."
    
    # Initialize chaos parameters
    if synthesis_mode = 1
        # Logistic Map
        if randomize_parameters
            r = 3.5 + 0.4 * randomUniform(0, 1)
            layer_density = grain_density * (0.7 + 0.6 * randomUniform(0, 1))
        else
            r = 3.7
            layer_density = grain_density
        endif
        chaos_x = 0.5
        
    elsif synthesis_mode = 2
        # Henon Map - FIXED WITH BOUNDS CHECKING
        if randomize_parameters
            a = 1.2 + 0.4 * randomUniform(0, 1)
            b = 0.2 + 0.2 * randomUniform(0, 1)
            layer_density = grain_density * (0.8 + 0.4 * randomUniform(0, 1))
        else
            a = 1.4
            b = 0.3
            layer_density = grain_density
        endif
        chaos_x = 0.1
        chaos_y = 0.1
        
    else
        # Lorenz System
        if randomize_parameters
            sigma = 8 + 4 * randomUniform(0, 1)
            layer_density = grain_density * (0.75 + 0.5 * randomUniform(0, 1))
        else
            sigma = 10
            layer_density = grain_density
        endif
        chaos_x = 0.1
        chaos_y = 0.0
        chaos_z = 0.0
        dt = 0.01
    endif
    
    total_grains = round(duration * layer_density)
    total_grains_all = total_grains_all + total_grains
    
    # Pre-generate all grain parameters
    for grain to total_grains
        grain_time[grain] = randomUniform(0, duration - 0.2)
        grain_dur[grain] = 0.08 + 0.15 * randomUniform(0, 1)
        
        # Evolve chaos and calculate frequency
        if synthesis_mode = 1
            chaos_x = r * chaos_x * (1 - chaos_x)
            grain_freq[grain] = base_frequency * (0.3 + 1.4 * chaos_x) * (1 + (layer - 1) * 0.2)
            
            # Store chaos trajectory (first layer only for clarity)
            if layer = 1 and grain <= max_chaos_points
                chaos_traj_x[grain] = grain
                chaos_traj_y[grain] = chaos_x
            endif
            
        elsif synthesis_mode = 2
            # Henon Map with bounds checking
            new_x = 1 - a * chaos_x * chaos_x + chaos_y
            chaos_y = b * chaos_x
            chaos_x = new_x
            
            # CRITICAL FIX: Bound chaos_x to prevent divergence
            if chaos_x > 2.0
                chaos_x = 2.0
            elsif chaos_x < -2.0
                chaos_x = -2.0
            endif
            
            # Map to positive frequency multiplier (0.5 to 1.5)
            freq_mult = 0.5 + 0.5 * (chaos_x + 2.0) / 4.0
            grain_freq[grain] = base_frequency * freq_mult * (1 + (layer - 1) * 0.25)
            
            # Safety check: ensure frequency is reasonable
            if grain_freq[grain] < 20
                grain_freq[grain] = 20
            elsif grain_freq[grain] > 5000
                grain_freq[grain] = 5000
            endif
            
            # Store chaos trajectory (first layer only)
            if layer = 1 and grain <= max_chaos_points
                chaos_traj_x[grain] = chaos_x
                chaos_traj_y[grain] = chaos_y
            endif
            
        else
            # Lorenz System
            dx = sigma * (chaos_y - chaos_x) * dt
            dy = (chaos_x * (28 - chaos_z) - chaos_y) * dt
            dz = (chaos_x * chaos_y - 2.667 * chaos_z) * dt
            chaos_x = chaos_x + dx
            chaos_y = chaos_y + dy
            chaos_z = chaos_z + dz
            grain_freq[grain] = base_frequency * (0.5 + 0.5 * (chaos_x / 20 + 0.5)) * (1 + (layer - 1) * 0.3)
            
            # Store chaos trajectory (first layer only)
            if layer = 1 and grain <= max_chaos_points
                chaos_traj_x[grain] = chaos_x
                chaos_traj_y[grain] = chaos_y
            endif
        endif
        
        grain_amp[grain] = base_amp_scale
        
        if grain_time[grain] + grain_dur[grain] > duration
            grain_dur[grain] = duration - grain_time[grain]
        endif
        
        # Store for visualization (sample from all layers)
        if viz_grain_count < max_viz_grains
            viz_grain_count = viz_grain_count + 1
            viz_time[viz_grain_count] = grain_time[grain]
            viz_freq[viz_grain_count] = grain_freq[grain]
            viz_layer[viz_grain_count] = layer
        endif
    endfor
    
    # Create chunks
    for chunk from 1 to num_chunks
        chunk_start = (chunk - 1) * chunk_duration
        chunk_end = min(chunk * chunk_duration, duration)
        actual_chunk_dur = chunk_end - chunk_start
        
        chunk_formula$ = "0"
        grains_added = 0
        
        # Add grains - LIMIT TO max_grains_per_chunk
        for grain to total_grains
            if grains_added >= max_grains_per_chunk
                # Skip remaining grains in this chunk
                grain = total_grains
            elsif grain_time[grain] >= chunk_start and grain_time[grain] < chunk_end and grain_dur[grain] > 0.01
                local_time = grain_time[grain] - chunk_start
                local_end = local_time + grain_dur[grain]
                actual_grain_dur = grain_dur[grain]
                
                # FIX: Clamp to chunk boundaries AND adjust envelope duration
                if local_end > actual_chunk_dur
                    local_end = actual_chunk_dur
                    actual_grain_dur = local_end - local_time
                endif
                
                # Only add if remaining duration is meaningful (prevents clicks from tiny grains)
                if actual_grain_dur >= min_grain_dur
                    s_start$ = fixed$(local_time, 4)
                    s_end$ = fixed$(local_end, 4)
                    s_amp$ = fixed$(grain_amp[grain], 4)
                    s_freq$ = fixed$(grain_freq[grain], 1)
                    s_dur$ = fixed$(actual_grain_dur, 4)
                    
                    # FIX: Hanning envelope uses ACTUAL (possibly truncated) duration
                    hann$ = "(1-cos(2*pi*(x-" + s_start$ + ")/" + s_dur$ + "))/2"
                    term$ = "+if x>=" + s_start$ + " and x<" + s_end$ + " then " + s_amp$ + "*sin(2*pi*" + s_freq$ + "*x)*" + hann$ + " else 0 fi"
                    
                    chunk_formula$ = chunk_formula$ + term$
                    grains_added = grains_added + 1
                endif
            endif
        endfor
        
        if chunk_formula$ <> "0"
            Create Sound from formula: "L'layer'C'chunk'", 1, 0, actual_chunk_dur, sample_rate, chunk_formula$
        else
            Create Sound from formula: "L'layer'C'chunk'", 1, 0, actual_chunk_dur, sample_rate, "0"
        endif
    endfor
    
    # FIX: Concatenate chunks WITH CROSSFADE to eliminate any remaining clicks
    if num_chunks = 1
        selectObject: "Sound L" + string$(layer) + "C1"
        layer_sound = Copy: "layer_" + string$(layer)
    else
        selectObject: "Sound L" + string$(layer) + "C1"
        for chunk from 2 to num_chunks
            plusObject: "Sound L" + string$(layer) + "C" + string$(chunk)
        endfor
        
        Concatenate with overlap: chunk_crossfade
        layer_sound = selected("Sound")
        Rename: "layer_" + string$(layer)
    endif
    
    # Cleanup chunk sounds
    for chunk from 1 to num_chunks
        removeObject: "Sound L" + string$(layer) + "C" + string$(chunk)
    endfor
    
    appendInfoLine: " ", total_grains, " grains"
endfor

# Mix layers
appendInfo: "Mixing..."
selectObject: "Sound layer_1"
final_id = Copy: "chaotic_mix"

for layer from 2 to number_of_layers
    selectObject: "Sound layer_" + string$(layer)
    layer_id = selected("Sound")
    selectObject: final_id
    Formula: "self+object(" + string$(layer_id) + ",x)"
endfor

for layer from 1 to number_of_layers
    removeObject: "Sound layer_" + string$(layer)
endfor
appendInfoLine: " done"

# Fade in/out
if fade_time > 0
    selectObject: final_id
    actual_dur = Get total duration
    s_fade$ = fixed$(fade_time, 6)
    s_dur$ = fixed$(actual_dur, 6)
    Formula: "if x<" + s_fade$ + " then self*(x/" + s_fade$ + ") else if x>" + s_dur$ + "-" + s_fade$ + " then self*((" + s_dur$ + "-x)/" + s_fade$ + ") else self fi fi"
endif

# Spatial processing
selectObject: final_id
if spatial_mode = 1
    Rename: "chaotic_" + preset_name$
else
    # === IMPROVED STEREO WIDE ===
    
    # Method: Decorrelation + complementary EQ + micro-delay
    
    # 1. Create two copies
    selectObject: final_id
    Copy: "L_temp"
    left_id = selected("Sound")
    
    selectObject: final_id
    Copy: "R_temp"
    right_id = selected("Sound")
    
    # 2. Apply complementary EQ (subtle, overlapping ranges)
    # Left: slight low emphasis
    selectObject: left_id
    Filter (pass Hann band): 0, 6000, 100
    left_filt = selected("Sound")
    removeObject: left_id
    left_id = left_filt
    
    # Right: slight high emphasis  
    selectObject: right_id
    Filter (pass Hann band): 100, 10000, 100
    right_filt = selected("Sound")
    removeObject: right_id
    right_id = right_filt
    
    # 3. Add micro-delay to right channel (Haas effect for width)
    selectObject: right_id
    right_dur = Get total duration
    
    # Create tiny silence (8ms delay)
    Create Sound from formula: "delay", 1, 0, 0.008, sample_rate, "0"
    delay_id = selected("Sound")
    
    # Prepend delay to right channel
    selectObject: delay_id
    plusObject: right_id
    Concatenate
    right_delayed = selected("Sound")
    removeObject: delay_id, right_id
    right_id = right_delayed
    
    # 4. Trim right to match left duration (remove delay from end)
    selectObject: left_id
    left_dur = Get total duration
    
    selectObject: right_id
    Extract part: 0, left_dur, "rectangular", 1, "no"
    right_trimmed = selected("Sound")
    removeObject: right_id
    right_id = right_trimmed
    
    # 5. Add slight decorrelation noise to differentiate channels
    selectObject: left_id
    Formula: "self + randomGauss(0, 0.001)"
    
    selectObject: right_id
    Formula: "self + randomGauss(0, 0.001)"
    
    # 6. Combine to stereo
    selectObject: left_id
    plusObject: right_id
    stereo_id = Combine to stereo
    Rename: "chaotic_" + preset_name$
    
    removeObject: final_id, left_id, right_id
    final_id = stereo_id
endif

# Normalize (mono and stereo), respecting the toggle
if normalize_output
    selectObject: final_id
    Scale peak: 0.9
endif

final_name$ = selected$("Sound")
final_dur = Get total duration

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0.1, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Chaotic Granular Synthesis## | " + preset_name$ + " | " + mode$
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.8, 7.6, 0.8, 1.8
    
    selectObject: final_id
    Colour: "{0.30, 0.50, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 9
    Select outer viewport: 0.15, 8, 0.6, 2.0
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # === GRAIN DISTRIBUTION (Time vs Frequency, colored by layer) ===
    Select outer viewport: 0, 4, 2.2, 4.0
    Select inner viewport: 0.8, 3.6, 2.4, 3.8
    
    # Find frequency range
    min_freq_viz = 10000
    max_freq_viz = 0
    for g from 1 to viz_grain_count
        if viz_freq[g] < min_freq_viz
            min_freq_viz = viz_freq[g]
        endif
        if viz_freq[g] > max_freq_viz
            max_freq_viz = viz_freq[g]
        endif
    endfor
    
    if max_freq_viz <= min_freq_viz
        min_freq_viz = 50
        max_freq_viz = 500
    endif
    
    freq_margin = (max_freq_viz - min_freq_viz) * 0.1
    min_freq_viz = min_freq_viz - freq_margin
    max_freq_viz = max_freq_viz + freq_margin
    
    Axes: 0, duration, min_freq_viz, max_freq_viz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, min_freq_viz, max_freq_viz
    
    # Draw grains colored by layer
    for g from 1 to viz_grain_count
        lay = viz_layer[g]
        
        # Color gradient by layer (blue -> green -> red)
        if number_of_layers > 1
            hue = (lay - 1) / (number_of_layers - 1)
        else
            hue = 0.5
        endif
        
        red = hue
        green = 0.4 + 0.3 * (1 - abs(hue - 0.5) * 2)
        blue = 1 - hue
        
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$, viz_time[g], viz_freq[g], 0.6
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 0, 4, 2.05, 2.2
    Font size: 8
    Colour: "{0.40, 0.40, 0.40}"
    Text: 2.0, "centre", 0.5, "half", "Grain Distribution (color = layer)"
    
    # === CHAOS ATTRACTOR / TRAJECTORY ===
    Select outer viewport: 4, 8, 2.2, 4.0
    Select inner viewport: 4.8, 7.6, 2.4, 3.8
    
    # Find range for chaos plot
    min_cx = 1e9
    max_cx = -1e9
    min_cy = 1e9
    max_cy = -1e9
    
    points_to_plot = min(total_grains_all / number_of_layers, max_chaos_points)
    if points_to_plot < 10
        points_to_plot = 10
    endif
    
    for cp from 1 to points_to_plot
        if chaos_traj_x[cp] < min_cx
            min_cx = chaos_traj_x[cp]
        endif
        if chaos_traj_x[cp] > max_cx
            max_cx = chaos_traj_x[cp]
        endif
        if chaos_traj_y[cp] < min_cy
            min_cy = chaos_traj_y[cp]
        endif
        if chaos_traj_y[cp] > max_cy
            max_cy = chaos_traj_y[cp]
        endif
    endfor
    
    # Add margins
    cx_range = max_cx - min_cx
    cy_range = max_cy - min_cy
    if cx_range < 0.01
        cx_range = 1
    endif
    if cy_range < 0.01
        cy_range = 1
    endif
    
    min_cx = min_cx - cx_range * 0.1
    max_cx = max_cx + cx_range * 0.1
    min_cy = min_cy - cy_range * 0.1
    max_cy = max_cy + cy_range * 0.1
    
    Axes: min_cx, max_cx, min_cy, max_cy
    Paint rectangle: "{0.97, 0.97, 0.97}", min_cx, max_cx, min_cy, max_cy
    
    # Draw chaos trajectory
    Colour: "{0.20, 0.50, 0.80}"
    for cp from 2 to points_to_plot
        # Fade color from blue to red over trajectory
        prog = (cp - 1) / (points_to_plot - 1)
        red = prog
        green = 0.3
        blue = 1 - prog
        
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$, chaos_traj_x[cp], chaos_traj_y[cp], 0.5
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 9
    
    # Axis labels depend on chaos type
    if synthesis_mode = 1
        Text left: "yes", "x(n)"
        Text bottom: "yes", "Iteration"
    elsif synthesis_mode = 2
        Text left: "yes", "y"
        Text bottom: "yes", "x"
    else
        Text left: "yes", "y"
        Text bottom: "yes", "x"
    endif
    
    Select outer viewport: 4, 8, 2.05, 2.2
    Font size: 8
    Colour: "{0.40, 0.40, 0.40}"
    Text: 6.0, "centre", 0.5, "half", "Chaos Trajectory (" + mode$ + ")"
    
    # === SUMMARY PANEL (grey) ===
    Select outer viewport: 0, 8, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Duration: " + fixed$(final_dur, 1) + "s | Layers: " + string$(number_of_layers) + " | Grains: " + string$(total_grains_all) + " | Base freq: " + string$(base_frequency) + " Hz | Spatial: " + spatial$
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_dur, 1), " s"
appendInfoLine: "Total grains: ", total_grains_all
appendInfoLine: "Spatial: ", spatial$

if play_after
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    selectObject: final_id
    Play
endif

selectObject: final_id