# ============================================================
# Praat AudioTools - Advanced Poisson Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Poisson-process granular synthesis. Grains are placed according
#   to a Poisson process (statistically independent random times).
#   Multiple layers with different rates create rich textures.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed filter object handling
#   - Fixed nested if/fi in fade
#   - Chunked grain processing (avoids string limits)
#   - Added sample rate parameter
#   - Added visualization
#   - Modern syntax throughout
# ============================================================

form Advanced Poisson Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Standard Three Layer
        option Dense Cloud
        option Sparse Atmosphere
        option Rhythmic Pattern
        option Chaotic Texture
        option Shimmering High
        option Deep Rumble
    
    comment === Basic Settings ===
    positive Duration_s 12
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    positive Frequency_range_Hz 300
    integer Number_of_layers 3
    
    comment === Poisson Rates ===
    positive Low_rate_Hz 3
    positive High_rate_Hz 15
    
    comment === Grain Settings ===
    positive Min_grain_duration_ms 30
    positive Max_grain_duration_ms 200
    
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Three Layer Standard
        option Dense Granular
        option Sparse Atmospheric
        option Rhythmic Pulses
        option Chaotic Scatter
    
    comment === Output ===
    positive Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Randomize_parameters 1
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    duration_s = 12
    base_frequency_Hz = 100
    frequency_range_Hz = 300
    low_rate_Hz = 3
    high_rate_Hz = 15
    number_of_layers = 3
    min_grain_duration_ms = 100
    max_grain_duration_ms = 300
    synthesis_mode = 1
    spatial_mode = 1
    preset_name$ = "Standard"
elsif preset = 3
    duration_s = 10
    base_frequency_Hz = 150
    frequency_range_Hz = 400
    low_rate_Hz = 10
    high_rate_Hz = 25
    number_of_layers = 4
    min_grain_duration_ms = 30
    max_grain_duration_ms = 80
    synthesis_mode = 2
    spatial_mode = 2
    preset_name$ = "DenseCloud"
elsif preset = 4
    duration_s = 20
    base_frequency_Hz = 80
    frequency_range_Hz = 500
    low_rate_Hz = 1
    high_rate_Hz = 5
    number_of_layers = 3
    min_grain_duration_ms = 300
    max_grain_duration_ms = 800
    synthesis_mode = 3
    spatial_mode = 3
    fade_time_s = 3
    preset_name$ = "Sparse"
elsif preset = 5
    duration_s = 15
    base_frequency_Hz = 120
    frequency_range_Hz = 200
    low_rate_Hz = 5
    high_rate_Hz = 12
    number_of_layers = 4
    min_grain_duration_ms = 80
    max_grain_duration_ms = 120
    randomize_parameters = 0
    synthesis_mode = 4
    spatial_mode = 1
    preset_name$ = "Rhythmic"
elsif preset = 6
    duration_s = 12
    base_frequency_Hz = 100
    frequency_range_Hz = 600
    low_rate_Hz = 2
    high_rate_Hz = 20
    number_of_layers = 5
    min_grain_duration_ms = 50
    max_grain_duration_ms = 300
    synthesis_mode = 5
    spatial_mode = 2
    preset_name$ = "Chaotic"
elsif preset = 7
    duration_s = 10
    base_frequency_Hz = 800
    frequency_range_Hz = 1500
    low_rate_Hz = 8
    high_rate_Hz = 20
    number_of_layers = 4
    min_grain_duration_ms = 20
    max_grain_duration_ms = 60
    synthesis_mode = 2
    spatial_mode = 2
    preset_name$ = "Shimmering"
elsif preset = 8
    duration_s = 15
    base_frequency_Hz = 40
    frequency_range_Hz = 80
    low_rate_Hz = 2
    high_rate_Hz = 8
    number_of_layers = 3
    min_grain_duration_ms = 200
    max_grain_duration_ms = 500
    synthesis_mode = 3
    spatial_mode = 3
    fade_time_s = 3
    preset_name$ = "DeepRumble"
endif

# === Validation ===
if number_of_layers > 8
    number_of_layers = 8
endif
if number_of_layers < 1
    number_of_layers = 1
endif
if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 25

# === Info ===
writeInfoLine: "=== Advanced Poisson Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "poisson_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

totalGrains = 0

# === Process each layer ===
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."
    
    # Determine layer rate based on synthesis mode
    if synthesis_mode = 1
        # Three Layer Standard - rate increases with layer
        layerRate = low_rate_Hz + (high_rate_Hz - low_rate_Hz) * (layer - 1) / max(1, number_of_layers - 1)
        if randomize_parameters
            layerRate = layerRate * (0.8 + 0.4 * randomUniform(0, 1))
        endif
    elsif synthesis_mode = 2
        # Dense Granular
        layerRate = high_rate_Hz * 1.5
        if randomize_parameters
            layerRate = layerRate * (0.7 + 0.6 * randomUniform(0, 1))
        endif
    elsif synthesis_mode = 3
        # Sparse Atmospheric
        layerRate = low_rate_Hz * 0.5
        if randomize_parameters
            layerRate = layerRate * (0.6 + 0.8 * randomUniform(0, 1))
        endif
    elsif synthesis_mode = 4
        # Rhythmic Pulses
        layerRate = (low_rate_Hz + high_rate_Hz) / 2
        if randomize_parameters
            layerRate = layerRate * (0.9 + 0.2 * randomUniform(0, 1))
        endif
    elsif synthesis_mode = 5
        # Chaotic Scatter
        layerRate = low_rate_Hz + (high_rate_Hz - low_rate_Hz) * randomUniform(0, 1)
        if randomize_parameters
            layerRate = layerRate * (0.5 + randomUniform(0, 1))
        endif
    endif
    
    # Create Poisson process
    poissonProc = Create Poisson process: "poisson_" + uid$, 0, duration_s, layerRate
    numPoints = Get number of points
    
    appendInfoLine: "  Rate: ", fixed$(layerRate, 1), " Hz, Grains: ", numPoints
    totalGrains = totalGrains + numPoints
    
    # --- Process grains in chunks to avoid huge formula strings ---
    chunkStart = 1
    
    while chunkStart <= numPoints
        chunkEnd = min(chunkStart + grainsPerChunk - 1, numPoints)
        
        # Build formula for this chunk
        chunkFormula$ = "0"
        
        for pt from chunkStart to chunkEnd
            selectObject: poissonProc
            pointTime = Get time from index: pt
            
            # Determine grain parameters based on synthesis mode
            if synthesis_mode = 1
                # Standard
                grainFreq = base_frequency_Hz + frequency_range_Hz * randomUniform(0, 1)
                grainDur = (min_grain_duration_ms + (max_grain_duration_ms - min_grain_duration_ms) * randomUniform(0, 1)) / 1000
                grainAmp = 1.5 / number_of_layers
            elsif synthesis_mode = 2
                # Dense Granular
                grainFreq = base_frequency_Hz * (0.5 + layer * 0.3) + frequency_range_Hz * randomUniform(0, 1)
                grainDur = (min_grain_duration_ms + (max_grain_duration_ms - min_grain_duration_ms) * randomUniform(0, 1)) / 1000
                grainAmp = 1.2 / number_of_layers
            elsif synthesis_mode = 3
                # Sparse Atmospheric
                grainFreq = base_frequency_Hz * (0.3 + layer * 0.4) + frequency_range_Hz * 0.5 * randomUniform(0, 1)
                grainDur = (min_grain_duration_ms + (max_grain_duration_ms - min_grain_duration_ms) * randomUniform(0, 1)) / 1000
                grainAmp = 2.0 / number_of_layers
            elsif synthesis_mode = 4
                # Rhythmic Pulses
                grainFreq = base_frequency_Hz * layer + frequency_range_Hz * 0.3 * randomUniform(0, 1)
                grainDur = (min_grain_duration_ms + (max_grain_duration_ms - min_grain_duration_ms) * randomUniform(0, 1)) / 1000
                grainAmp = 1.8 / number_of_layers
            elsif synthesis_mode = 5
                # Chaotic Scatter
                grainFreq = base_frequency_Hz * (0.5 + 2 * randomUniform(0, 1)) + frequency_range_Hz * randomUniform(0, 1)
                grainDur = (min_grain_duration_ms + (max_grain_duration_ms - min_grain_duration_ms) * randomUniform(0, 1)) / 1000
                grainAmp = 1.5 / number_of_layers
            endif
            
            # Clamp grain duration
            if pointTime + grainDur > duration_s
                grainDur = duration_s - pointTime
            endif
            
            if grainDur > 0.005
                # Build grain term with Hanning envelope
                sTime$ = fixed$(pointTime, 6)
                sEnd$ = fixed$(pointTime + grainDur, 6)
                sAmp$ = fixed$(grainAmp, 6)
                sFreq$ = fixed$(grainFreq, 2)
                sDur$ = fixed$(grainDur, 6)
                
                grainTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * (x - " + sTime$ + ")) * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
                chunkFormula$ = chunkFormula$ + grainTerm$
            endif
        endfor
        
        # Apply chunk formula to output
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
        
        chunkStart = chunkEnd + 1
    endwhile
    
    # Cleanup
    removeObject: poissonProc
endfor

appendInfoLine: ""
appendInfoLine: "Total grains: ", totalGrains

# === Apply Fade ===
appendInfoLine: "Applying envelope..."
selectObject: outputSound
Formula: "if x < fade_time_s then self * (x / fade_time_s) else self fi"
fadeOutStart = duration_s - fade_time_s
Formula: "if x > fadeOutStart then self * ((duration_s - x) / fade_time_s) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, 4000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 200, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "poisson_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.25 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.25 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "poisson_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "poisson_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSpectrogram: duration_s
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

# ==============================================================================
# Procedure: drawSpectrogram
# ==============================================================================
procedure drawSpectrogram: .duration
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text top: "no", "Poisson Synthesis: " + preset_name$ + " (" + synthesis_mode$ + ")"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 0.6, 4.5
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    
    # Get mono version for spectrogram
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoForSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_for_spec"
        .monoForSpec = selected("Sound")
    endif
    
    selectObject: .monoForSpec
    .maxFreqSpec = min(8000, max(2000, base_frequency_Hz + frequency_range_Hz * 2))
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoForSpec, .spec
    
    # Axis labels
    Select outer viewport: 0, .leftMargin, 0.6, 4.5
    Colour: "Black"
    Font size: 10
    Text: 0.5, "centre", 0.5, "half", "Hz"
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    Axes: 0, .duration, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 4.6, 5.0
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Rate: " + fixed$(low_rate_Hz, 1) + "-" + fixed$(high_rate_Hz, 1) + " Hz | Grains: " + string$(totalGrains) + " | Layers: " + string$(number_of_layers)
    Text top: "no", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc