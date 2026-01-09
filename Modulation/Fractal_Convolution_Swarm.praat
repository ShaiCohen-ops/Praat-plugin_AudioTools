# ============================================================
# Praat AudioTools - Fractal_Convolution_Swarm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fractal Convolution Swarm - multi-scale delay processing
#   with exponentially increasing time scales. Creates complex,
#   self-similar textures by convolving at multiple depths with
#   weighted kernels. Produces ambient, granular, or dense effects.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Added visualization
#   - Better description
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency

# === Form ===
form Fractal Convolution Swarm
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Texture
        option Ambient Swarm
        option Dense Cloud
        option Granular Dispersion
        option Extreme Fractal
        option Gentle Shimmer
    
    comment === Fractal Parameters ===
    natural Fractal_depth 5
    natural Convolution_width 3
    
    comment === Scaling ===
    positive Base_delay_ms 5.0
    positive Depth_scale_factor 1.6
    positive Mix_amount 0.3
    
    comment === Output ===
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Texture
    fractal_depth = 3
    convolution_width = 2
    base_delay_ms = 3.0
    depth_scale_factor = 1.4
    mix_amount = 0.2
    presetName$ = "Subtle"
elsif preset = 3
    # Ambient Swarm
    fractal_depth = 5
    convolution_width = 3
    base_delay_ms = 5.0
    depth_scale_factor = 1.6
    mix_amount = 0.3
    presetName$ = "Ambient"
elsif preset = 4
    # Dense Cloud
    fractal_depth = 6
    convolution_width = 4
    base_delay_ms = 7.0
    depth_scale_factor = 1.8
    mix_amount = 0.4
    presetName$ = "Dense"
elsif preset = 5
    # Granular Dispersion
    fractal_depth = 7
    convolution_width = 5
    base_delay_ms = 8.0
    depth_scale_factor = 2.0
    mix_amount = 0.45
    presetName$ = "Granular"
elsif preset = 6
    # Extreme Fractal
    fractal_depth = 8
    convolution_width = 6
    base_delay_ms = 10.0
    depth_scale_factor = 2.2
    mix_amount = 0.5
    presetName$ = "Extreme"
elsif preset = 7
    # Gentle Shimmer
    fractal_depth = 4
    convolution_width = 2
    base_delay_ms = 2.5
    depth_scale_factor = 1.3
    mix_amount = 0.15
    presetName$ = "Shimmer"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Fractal Convolution Swarm ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Fractal depth: ", fractal_depth
appendInfoLine: "Convolution width: ±", convolution_width
appendInfoLine: "Base delay: ", base_delay_ms, " ms"
appendInfoLine: "Scale factor: ", depth_scale_factor
appendInfoLine: "Mix: ", mix_amount
appendInfoLine: ""

# Calculate base delay in samples
base_delay = round(base_delay_ms * sampling / 1000)

# Store delay structure for visualization
delayTimes# = zero#(fractal_depth)
depthWeights# = zero#(fractal_depth)

for d from 1 to fractal_depth
    delayTimes#[d] = base_delay_ms * (depth_scale_factor ^ d)
    depthWeights#[d] = 1 / sqrt(d)
endfor

# === Create Working Copy ===
selectObject: original
Copy: originalName$ + "_fractal"
result = selected("Sound")

# === Apply Fractal Convolution ===
appendInfoLine: "Applying fractal convolution..."

totalOperations = fractal_depth * (2 * convolution_width)
opCount = 0

for depth from 1 to fractal_depth
    # Calculate delay for this depth level
    current_delay = round(base_delay * (depth_scale_factor ^ depth))
    
    # Weight decreases with depth
    depth_weight = 1 / sqrt(depth)
    
    appendInfoLine: "  Depth ", depth, "/", fractal_depth, " (delay: ", round(current_delay / sampling * 1000), " ms)"
    
    # Apply convolution kernel at multiple offsets
    for kernel from -convolution_width to convolution_width
        if kernel <> 0
            opCount = opCount + 1
            
            # Center-weighted kernel
            kernel_weight = 1 / (1 + abs(kernel))
            
            # Total shift includes kernel offset
            total_shift = current_delay + (kernel * round(current_delay * 0.3))
            
            # Combined weight
            combined_weight = mix_amount * kernel_weight * depth_weight
            dry_weight = 1 - combined_weight
            
            # Mix delayed signal
            selectObject: result
            Formula: ~ self * dry_weight + self[max(1, min(ncol, col + total_shift))] * combined_weight
        endif
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Operations: ", opCount

# === Scale ===
selectObject: result
Scale peak: scale_peak
Rename: originalName$ + "_fractal_" + presetName$

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Fractal Convolution Swarm: " + originalName$ + " (" + presetName$ + ")"
    
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
    Text left: "yes", "Fractal"
    Text bottom: "yes", "Time (s)"
    
    # Fractal delay structure
    Select outer viewport: 0, 4, 2.7, 4.2
    Select inner viewport: 0.6, 3.8, 2.9, 4.1
    
    maxDelay = delayTimes#[fractal_depth]
    Axes: 0, fractal_depth + 1, 0, maxDelay * 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, fractal_depth + 1, 0, maxDelay * 1.1
    
    # Draw delay bars (exponential growth)
    for d from 1 to fractal_depth
        # Color gradient from light to dark
        colorVal = 0.4 + (d - 1) / fractal_depth * 0.3
        Colour: "{" + fixed$(colorVal, 2) + ", " + fixed$(0.5, 2) + ", " + fixed$(0.7, 2) + "}"
        Paint rectangle: "{" + fixed$(colorVal, 2) + ", " + fixed$(0.5, 2) + ", " + fixed$(0.7, 2) + "}", d - 0.35, d + 0.35, 0, delayTimes#[d]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Depth"
    
    # Depth weights
    Select outer viewport: 4, 8, 2.7, 4.2
    Select inner viewport: 4.4, 7.6, 2.9, 4.1
    
    Axes: 0, fractal_depth + 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, fractal_depth + 1, 0, 1.1
    
    # Draw weight bars
    for d from 1 to fractal_depth
        Colour: "{0.5, 0.7, 0.5}"
        Paint rectangle: "{0.5, 0.7, 0.5}", d - 0.35, d + 0.35, 0, depthWeights#[d]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Weight"
    Text bottom: "yes", "Depth"
    
    # Kernel visualization
    Select outer viewport: 0, 8, 4.4, 5.2
    Select inner viewport: 0.6, 7.6, 4.5, 5.1
    
    kernelSize = 2 * convolution_width + 1
    Axes: -convolution_width - 1, convolution_width + 1, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", -convolution_width - 1, convolution_width + 1, 0, 1.1
    
    # Draw kernel weights
    for k from -convolution_width to convolution_width
        if k = 0
            # Center (original signal)
            kWeight = 1
            Paint rectangle: "{0.7, 0.7, 0.7}", k - 0.35, k + 0.35, 0, kWeight
        else
            kWeight = 1 / (1 + abs(k))
            Paint rectangle: "{0.7, 0.5, 0.6}", k - 0.35, k + 0.35, 0, kWeight
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Kernel"
    Text bottom: "yes", "Offset (center = original)"
    
    # Stats
    Select outer viewport: 0, 8, 5.3, 5.6
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Depth: " + string$(fractal_depth) + " | Width: ±" + string$(convolution_width) + " | Base: " + fixed$(base_delay_ms, 1) + "ms | Scale: " + fixed$(depth_scale_factor, 2) + "× | Max delay: " + fixed$(maxDelay, 0) + "ms"
    
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
