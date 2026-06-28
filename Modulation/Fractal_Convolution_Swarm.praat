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
#   self-similar textures by mixing weighted delayed copies at
#   multiple depths. Swarm mode sums the taps in parallel against
#   a preserved dry signal; Cascade mode is the original in-place
#   recursive dissolver. Ambient, granular, or dense effects.
#
# Changelog v0.3:
#   - Added Swarm (parallel) mode: weighted delayed copies of the
#     dry signal are ADDED as echoes (multi-tap delay) on top of the
#     preserved dry, so mix_amount is an echo send and the weight
#     panels are faithful. Original behaviour kept as Cascade.
#   - Guard: taps whose delay exceeds the signal are skipped
#   - Stereo placement for Swarm: Wide (spread taps by kernel) and
#     Ping-pong (bounce depth levels L/R), equal-power pan
#   - Standard header
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
    
    comment === Processing ===
    optionmenu Processing 1
        option Swarm (parallel, preserves dry)
        option Cascade (original, dissolving)
    optionmenu Stereo 3
        option Centered
        option Wide (spread taps by kernel)
        option Ping-pong (bounce by depth)
    
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

if processing = 2
    procName$ = "Cascade"
else
    procName$ = "Swarm"
endif

if stereo = 2
    stereoName$ = "Wide"
elsif stereo = 3
    stereoName$ = "Ping-pong"
else
    stereoName$ = "Centered"
endif

# === Info ===
writeInfoLine: "=== Fractal Convolution Swarm ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", procName$, " | Stereo: ", stereoName$
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

# === Working copies ===
selectObject: original
nChannels = Get number of channels
nSamples = Get number of samples

# Mono source for delay taps (named fcsdry for the Formula reference)
if nChannels = 1
    drymono = Copy: "fcsdry"
else
    drymono = Convert to mono
    Rename: "fcsdry"
endif

# Stereo result: dry passthrough now, echoes added below
if nChannels = 1
    selectObject: original
    fcsTmpL = Copy: "fcsTmpL"
    selectObject: original
    fcsTmpR = Copy: "fcsTmpR"
    selectObject: fcsTmpL, fcsTmpR
    result = Combine to stereo
    Rename: originalName$ + "_fractal"
    removeObject: fcsTmpL, fcsTmpR
else
    selectObject: original
    result = Copy: originalName$ + "_fractal"
endif

# === Apply Fractal Convolution ===
appendInfoLine: "Applying fractal convolution..."

totalOperations = fractal_depth * (2 * convolution_width)
opCount = 0
skippedCount = 0

if processing = 2
    # ---- CASCADE (original): in-place, each op reads its own output ----
    for depth from 1 to fractal_depth
        current_delay = round(base_delay * (depth_scale_factor ^ depth))
        depth_weight = 1 / sqrt(depth)
        appendInfoLine: "  Depth ", depth, "/", fractal_depth, " (delay: ", round(current_delay / sampling * 1000), " ms)"
        for kernel from -convolution_width to convolution_width
            if kernel <> 0
                opCount = opCount + 1
                kernel_weight = 1 / (1 + abs(kernel))
                total_shift = current_delay + (kernel * round(current_delay * 0.3))
                combined_weight = mix_amount * kernel_weight * depth_weight
                dry_weight = 1 - combined_weight
                selectObject: result
                Formula: ~ self * dry_weight + self[max(1, min(ncol, col + total_shift))] * combined_weight
            endif
        endfor
    endfor
else
    # ---- SWARM (parallel multi-tap delay): ADD weighted, panned delayed
    #      copies of the dry signal as echoes on top of the preserved dry.
    #      Sound_fcsdry(time) reads the mono dry by time and returns 0
    #      outside its domain, so out-of-range taps add silence.
    #      Stereo: Wide spreads taps by kernel position; Ping-pong bounces
    #      successive depth levels left/right (equal-power pan). ----
    for depth from 1 to fractal_depth
        current_delay = round(base_delay * (depth_scale_factor ^ depth))
        depth_weight = 1 / sqrt(depth)
        appendInfoLine: "  Depth ", depth, "/", fractal_depth, " (delay: ", round(current_delay / sampling * 1000), " ms)"
        for kernel from -convolution_width to convolution_width
            if kernel <> 0
                opCount = opCount + 1
                kernel_weight = 1 / (1 + abs(kernel))
                total_shift = current_delay + (kernel * round(current_delay * 0.3))
                offset = total_shift / sampling
                gain = mix_amount * kernel_weight * depth_weight
                # Stereo pan position p in [-1, 1]
                if stereo = 2
                    p = kernel / convolution_width
                elsif stereo = 3
                    if depth - 2 * floor(depth / 2) = 1
                        p = -1
                    else
                        p = 1
                    endif
                else
                    p = 0
                endif
                panAngle = (p + 1) / 2 * pi / 2
                gL = cos(panAngle)
                gR = sin(panAngle)
                # Skip taps whose delay exceeds the signal
                if abs(total_shift) < nSamples
                    selectObject: result
                    Formula: ~ self + (if row = 1 then gL else gR fi) * gain * Sound_fcsdry(x + offset)
                else
                    skippedCount = skippedCount + 1
                endif
            endif
        endfor
    endfor
endif

appendInfoLine: ""
appendInfoLine: "Operations: ", opCount
if skippedCount > 0
    appendInfoLine: "Skipped (delay > signal): ", skippedCount, " / ", totalOperations
endif

# === Scale ===
selectObject: result
Scale peak: scale_peak
Rename: originalName$ + "_fractal_" + presetName$

removeObject: drymono

# === Visualization ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Fractal Convolution Swarm##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + presetName$ + " | " + procName$ + " | " + stereoName$
    
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
    Text: 0.5, "centre", 0.5, "half", "Mode: " + procName$ + " (" + stereoName$ + ") | Depth: " + string$(fractal_depth) + " | Width: ±" + string$(convolution_width) + " | Base: " + fixed$(base_delay_ms, 1) + "ms | Scale: " + fixed$(depth_scale_factor, 2) + "× | Max delay: " + fixed$(maxDelay, 0) + "ms"
    
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
