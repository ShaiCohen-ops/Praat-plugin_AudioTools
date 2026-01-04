# ============================================================
# Praat AudioTools - Brownian_Motion_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brownian Motion Texture Generator - creates granular textures
#   using random walk (Brownian motion) for both temporal placement
#   and stereo panning. Unlike simple random scatter, Brownian motion
#   creates cumulative drift patterns.
#
# Changelog v0.2:
#   - Optimized using sorted concatenation
#   - Added visualization showing Brownian paths
#   - Added play option
# ============================================================

form Brownian Motion Texture
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Dense Cloud
        option Sparse Field
        option Wild Drift
        option Subtle Shimmer
        option Rhythmic Pulse
        option Frozen Moment
    
    comment === Grain Parameters ===
    positive Grain_duration_s 0.05
    positive Output_duration_s 10.0
    positive Density_grains_per_sec 20
    
    comment === Temporal Brownian Motion ===
    positive Time_step_size_s 0.1
    real Time_drift 0.0
    
    comment === Spatial Brownian Motion (Stereo) ===
    boolean Enable_spatial_brownian 1
    positive Spatial_step_size 0.15
    real Spatial_drift 0.0
    
    comment === Options ===
    positive Amplitude_scaling 0.7
    boolean Random_grain_positions 1
    positive Fade_duration_s 0.005
    positive Fade_out_s 2.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    grain_duration_s = 0.03
    output_duration_s = 8.0
    density_grains_per_sec = 40
    time_step_size_s = 0.08
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.2
    spatial_drift = 0.0
    amplitude_scaling = 0.5
    random_grain_positions = 1
    fade_duration_s = 0.003
    fade_out_s = 2.0
elsif preset = 3
    grain_duration_s = 0.15
    output_duration_s = 15.0
    density_grains_per_sec = 8
    time_step_size_s = 0.2
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.1
    spatial_drift = 0.0
    amplitude_scaling = 0.8
    random_grain_positions = 1
    fade_duration_s = 0.01
    fade_out_s = 3.0
elsif preset = 4
    grain_duration_s = 0.06
    output_duration_s = 12.0
    density_grains_per_sec = 25
    time_step_size_s = 0.25
    time_drift = 0.02
    enable_spatial_brownian = 1
    spatial_step_size = 0.3
    spatial_drift = 0.01
    amplitude_scaling = 0.6
    random_grain_positions = 1
    fade_duration_s = 0.005
    fade_out_s = 2.5
elsif preset = 5
    grain_duration_s = 0.04
    output_duration_s = 10.0
    density_grains_per_sec = 30
    time_step_size_s = 0.05
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.08
    spatial_drift = 0.0
    amplitude_scaling = 0.6
    random_grain_positions = 1
    fade_duration_s = 0.004
    fade_out_s = 2.0
elsif preset = 6
    grain_duration_s = 0.08
    output_duration_s = 10.0
    density_grains_per_sec = 15
    time_step_size_s = 0.02
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.25
    spatial_drift = 0.0
    amplitude_scaling = 0.75
    random_grain_positions = 0
    fade_duration_s = 0.006
    fade_out_s = 1.5
elsif preset = 7
    grain_duration_s = 0.4
    output_duration_s = 20.0
    density_grains_per_sec = 6
    time_step_size_s = 0.15
    time_drift = 0.0
    enable_spatial_brownian = 1
    spatial_step_size = 0.12
    spatial_drift = 0.0
    amplitude_scaling = 0.85
    random_grain_positions = 1
    fade_duration_s = 0.015
    fade_out_s = 4.0
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
input_name$ = selected$("Sound")

# === Convert to Mono (ensures consistent channel count) ===
selectObject: original
Convert to mono
source = selected("Sound")

selectObject: source
input_duration = Get total duration
sampleRate = Get sampling frequency

# === Validate ===
if input_duration < grain_duration_s
    removeObject: source
    exitScript: "Input sound shorter than grain duration"
endif

# === Calculate Parameters ===
totalGrains = round(density_grains_per_sec * output_duration_s)
if totalGrains > 500
    totalGrains = 500
endif

# === Info ===
writeInfoLine: "=== Brownian Motion Texture Generator ==="
appendInfoLine: "Source: ", input_name$, " (", fixed$(input_duration, 2), " s)"
appendInfoLine: "Output: ", output_duration_s, " s | Grains: ", totalGrains
appendInfoLine: "Temporal step: ", time_step_size_s, " | Spatial step: ", spatial_step_size
appendInfoLine: ""

# === Calculate Brownian Paths ===
appendInfoLine: "Calculating Brownian paths..."

time_offset = 0
pan_position = 0.5

for i to totalGrains
    # Temporal Brownian
    base_time = (i - 1) / density_grains_per_sec
    time_step = randomGauss(time_drift, time_step_size_s)
    time_offset = time_offset + time_step
    
    grainOutTime[i] = base_time + time_offset
    if grainOutTime[i] < 0
        grainOutTime[i] = 0
    endif
    if grainOutTime[i] > output_duration_s - grain_duration_s
        grainOutTime[i] = output_duration_s - grain_duration_s
    endif
    
    # Spatial Brownian
    if enable_spatial_brownian
        spatial_step = randomGauss(spatial_drift, spatial_step_size)
        pan_position = pan_position + spatial_step
        if pan_position < 0
            pan_position = 0
        endif
        if pan_position > 1
            pan_position = 1
        endif
    else
        pan_position = 0.5
    endif
    grainPan[i] = pan_position
    
    # Source position
    if random_grain_positions
        grainSrcTime[i] = randomUniform(0, input_duration - grain_duration_s)
    else
        grainSrcTime[i] = (i / totalGrains) * (input_duration - grain_duration_s)
    endif
endfor

# === Sort Grains by Output Time ===
appendInfoLine: "Sorting grains..."

for i to totalGrains - 1
    for j from i + 1 to totalGrains
        if grainOutTime[j] < grainOutTime[i]
            tempTime = grainOutTime[i]
            grainOutTime[i] = grainOutTime[j]
            grainOutTime[j] = tempTime
            
            tempPan = grainPan[i]
            grainPan[i] = grainPan[j]
            grainPan[j] = tempPan
            
            tempSrc = grainSrcTime[i]
            grainSrcTime[i] = grainSrcTime[j]
            grainSrcTime[j] = tempSrc
        endif
    endfor
endfor

# === Generate Grains with Silence Gaps ===
appendInfoLine: "Generating grain sequence..."

currentTime = 0
grainObjects# = zero#(totalGrains * 2 + 1)
objCount = 0

for i to totalGrains
    # Add silence gap if needed (STEREO)
    gapDur = grainOutTime[i] - currentTime
    if gapDur > 0.001
        silenceL = Create Sound from formula: "gapL", 1, 0, gapDur, sampleRate, "0"
        silenceR = Create Sound from formula: "gapR", 1, 0, gapDur, sampleRate, "0"
        selectObject: silenceL, silenceR
        Combine to stereo
        silence = selected("Sound")
        removeObject: silenceL, silenceR
        
        objCount += 1
        grainObjects#[objCount] = silence
        currentTime = currentTime + gapDur
    endif
    
    # Extract grain from mono source
    selectObject: source
    Extract part: grainSrcTime[i], grainSrcTime[i] + grain_duration_s, "Hanning", 1, 0
    grainMono = selected("Sound")
    
    # Apply fade and scaling
    grainDur = Get total duration
    if fade_duration_s > 0 and fade_duration_s < grainDur / 2
        Fade in: 0, 0, fade_duration_s, "yes"
        Fade out: 0, grainDur - fade_duration_s, fade_duration_s, "yes"
    endif
    Formula: "self * amplitude_scaling"
    
    # Calculate stereo gains
    pan = grainPan[i]
    gainL = sqrt(1 - pan)
    gainR = sqrt(pan)
    
    # Create left channel
    selectObject: grainMono
    Copy: "grainL"
    grainL = selected("Sound")
    Formula: "self * " + string$(gainL)
    
    # Create right channel
    selectObject: grainMono
    Copy: "grainR"
    grainR = selected("Sound")
    Formula: "self * " + string$(gainR)
    
    # Combine to stereo
    selectObject: grainL, grainR
    Combine to stereo
    grainStereo = selected("Sound")
    
    removeObject: grainMono, grainL, grainR
    
    objCount += 1
    grainObjects#[objCount] = grainStereo
    currentTime = grainOutTime[i] + grainDur
    
    if i mod 50 = 0
        appendInfoLine: "  ", i, "/", totalGrains
    endif
endfor

# Add final silence if needed (STEREO)
if currentTime < output_duration_s
    finalGap = output_duration_s - currentTime
    if finalGap > 0.001
        silenceL = Create Sound from formula: "gapL", 1, 0, finalGap, sampleRate, "0"
        silenceR = Create Sound from formula: "gapR", 1, 0, finalGap, sampleRate, "0"
        selectObject: silenceL, silenceR
        Combine to stereo
        silence = selected("Sound")
        removeObject: silenceL, silenceR
        
        objCount += 1
        grainObjects#[objCount] = silence
    endif
endif

# === Concatenate All ===
appendInfoLine: "Concatenating ", objCount, " objects..."

if objCount > 0
    selectObject: grainObjects#[1]
    for i from 2 to objCount
        plusObject: grainObjects#[i]
    endfor
    Concatenate
    output = selected("Sound")
    
    for i to objCount
        removeObject: grainObjects#[i]
    endfor
else
    silenceL = Create Sound from formula: "emptyL", 1, 0, output_duration_s, sampleRate, "0"
    silenceR = Create Sound from formula: "emptyR", 1, 0, output_duration_s, sampleRate, "0"
    selectObject: silenceL, silenceR
    Combine to stereo
    output = selected("Sound")
    removeObject: silenceL, silenceR
endif

Rename: input_name$ + "_brownian"

# === Apply Fade Out ===
if fade_out_s > 0
    selectObject: output
    outDur = Get total duration
    if fade_out_s < outDur
        Fade out: 0, outDur - fade_out_s, fade_out_s, "yes"
    endif
endif

# === Normalize ===
selectObject: output
Scale peak: 0.95

# === Cleanup source ===
removeObject: source

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Brownian Motion: " + input_name$
    
    # Output waveform
    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.6, 7.6, 1.0, 2.4
    selectObject: output
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Temporal Brownian path
    Select outer viewport: 0, 4, 2.7, 4.3
    Select inner viewport: 0.6, 3.8, 2.9, 4.2
    Axes: 1, totalGrains, 0, output_duration_s
    
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 1, totalGrains, 0, output_duration_s
    
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 1, 0, totalGrains, output_duration_s
    Solid line
    
    Colour: "{0.8, 0.3, 0.3}"
    for i from 2 to totalGrains
        Draw line: i-1, grainOutTime[i-1], i, grainOutTime[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Time"
    Text bottom: "yes", "Grain #"
    
    # Spatial Brownian path
    Select outer viewport: 4, 8, 2.7, 4.3
    Select inner viewport: 4.4, 7.6, 2.9, 4.2
    Axes: 1, totalGrains, 0, 1
    
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 1, totalGrains, 0, 1
    
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 1, 0.5, totalGrains, 0.5
    Solid line
    
    Colour: "{0.3, 0.6, 0.3}"
    for i from 2 to totalGrains
        Draw line: i-1, grainPan[i-1], i, grainPan[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan L-R"
    Text bottom: "yes", "Grain #"
    
    # Legend
    Select outer viewport: 0, 8, 4.4, 4.7
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Grains: " + string$(totalGrains) + " | Time step: " + fixed$(time_step_size_s, 2) + "s | Pan step: " + fixed$(spatial_step_size, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: output
    Play
endif

selectObject: output