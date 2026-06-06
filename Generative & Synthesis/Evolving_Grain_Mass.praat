# ============================================================
# Praat AudioTools - Evolving Grain Mass.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Granular synthesis with evolving density, frequency, and
#   statistical characteristics over time.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit 
#   for Experimental Composition.
#
# Changelog v0.2:
#   - Chunked grain processing, fixed filters, density-scaled amplitude, viz
#
# Changelog v0.3:
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     0.6/7.6 inner-viewport margins, font-12 title, output waveform +
#     spectrogram panels, grey summary panel).
#   - Replaced non-ASCII arrow/dash characters with ASCII for portability.
# ============================================================

form Evolving Grain Mass
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Cloud Formation
        option Rising Mist
        option Storm Build
        option Cosmic Drift
        option Industrial Growth
        option Organic Bloom
        option Digital Cascade
        option Harmonic Evolution
        option Density Wave
        option Granular Swarm
    
    comment === Basic Settings ===
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    
    comment === Density Evolution ===
    positive Initial_density 20
    positive Final_density 60
    
    comment === Frequency Evolution ===
    real Frequency_evolution 2.0
    
    comment === Evolution Type ===
    optionmenu Evolution_type 1
        option Density Growth
        option Frequency Sweep
        option Statistical Shift
    
    comment === Grain Settings ===
    positive Min_grain_ms 20
    positive Max_grain_ms 80
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Evolution
        option Rotating Cloud
        option Wide Field
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Cloud Formation
    initial_density = 10
    final_density = 40
    base_frequency_Hz = 80
    frequency_evolution = 1.5
    evolution_type = 1
    min_grain_ms = 40
    max_grain_ms = 120
    preset_name$ = "CloudFormation"
    
elsif preset = 3
    # Rising Mist
    initial_density = 5
    final_density = 25
    base_frequency_Hz = 150
    frequency_evolution = 2.0
    evolution_type = 2
    min_grain_ms = 30
    max_grain_ms = 100
    spatial_mode = 3
    preset_name$ = "RisingMist"
    
elsif preset = 4
    # Storm Build
    duration_s = 8.0
    initial_density = 15
    final_density = 100
    base_frequency_Hz = 100
    evolution_type = 1
    min_grain_ms = 15
    max_grain_ms = 50
    spatial_mode = 2
    preset_name$ = "StormBuild"
    
elsif preset = 5
    # Cosmic Drift
    duration_s = 10.0
    initial_density = 8
    final_density = 30
    base_frequency_Hz = 60
    frequency_evolution = 3.0
    evolution_type = 2
    min_grain_ms = 60
    max_grain_ms = 150
    spatial_mode = 3
    preset_name$ = "CosmicDrift"
    
elsif preset = 6
    # Industrial Growth
    initial_density = 30
    final_density = 120
    base_frequency_Hz = 80
    evolution_type = 1
    min_grain_ms = 10
    max_grain_ms = 40
    spatial_mode = 4
    preset_name$ = "IndustrialGrowth"
    
elsif preset = 7
    # Organic Bloom
    duration_s = 8.0
    initial_density = 12
    final_density = 45
    base_frequency_Hz = 110
    evolution_type = 3
    min_grain_ms = 35
    max_grain_ms = 100
    spatial_mode = 2
    preset_name$ = "OrganicBloom"
    
elsif preset = 8
    # Digital Cascade
    initial_density = 25
    final_density = 80
    base_frequency_Hz = 200
    evolution_type = 3
    min_grain_ms = 8
    max_grain_ms = 30
    spatial_mode = 4
    preset_name$ = "DigitalCascade"
    
elsif preset = 9
    # Harmonic Evolution
    initial_density = 18
    final_density = 50
    base_frequency_Hz = 130
    frequency_evolution = 2.5
    evolution_type = 2
    min_grain_ms = 25
    max_grain_ms = 70
    preset_name$ = "HarmonicEvolution"
    
elsif preset = 10
    # Density Wave
    initial_density = 15
    final_density = 70
    base_frequency_Hz = 140
    evolution_type = 1
    min_grain_ms = 20
    max_grain_ms = 60
    spatial_mode = 2
    preset_name$ = "DensityWave"
    
elsif preset = 11
    # Granular Swarm
    initial_density = 50
    final_density = 150
    base_frequency_Hz = 160
    evolution_type = 1
    min_grain_ms = 5
    max_grain_ms = 25
    spatial_mode = 3
    preset_name$ = "GranularSwarm"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 30

# Calculate total grains
avgDensity = (initial_density + final_density) / 2
totalGrains = round(avgDensity * duration_s)

# === Info ===
writeInfoLine: "=== Evolving Grain Mass ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Density: ", initial_density, " -> ", final_density, " grains/s"
appendInfoLine: "Total grains: ", totalGrains
appendInfoLine: "Evolution: ", evolution_type$
appendInfoLine: ""

# === Pre-generate grain parameters ===
appendInfoLine: "Generating grain parameters..."

for g to totalGrains
    # Time placement depends on evolution type
    if evolution_type = 1
        # Density Growth: more grains placed later
        u = randomUniform(0, 1)
        if final_density > initial_density
            grain_time[g] = duration_s * sqrt(u)
        else
            grain_time[g] = duration_s * (1 - sqrt(1 - u))
        endif
    else
        # Random placement
        grain_time[g] = randomUniform(0, duration_s)
    endif
    
    normalizedTime = grain_time[g] / duration_s
    
    # Frequency depends on evolution type
    if evolution_type = 2
        # Frequency Sweep: exponential frequency evolution
        currentBaseFreq = base_frequency_Hz * (frequency_evolution ^ normalizedTime)
        grain_freq[g] = currentBaseFreq + 150 * randomGauss(0, 1)
        if grain_freq[g] < 30
            grain_freq[g] = 30
        endif
    elsif evolution_type = 3
        # Statistical Shift: 3 phases
        if normalizedTime < 0.33
            grain_freq[g] = base_frequency_Hz + 100 * randomGauss(0, 1)
        elsif normalizedTime < 0.66
            grain_freq[g] = base_frequency_Hz * 1.5 + 200 * randomUniform(-1, 1)
        else
            grain_freq[g] = base_frequency_Hz * 2.0 + 300 * randomUniform(-1, 1)
        endif
        if grain_freq[g] < 30
            grain_freq[g] = 30
        endif
    else
        # Density Growth: slight random variation
        grain_freq[g] = base_frequency_Hz + 200 * randomGauss(0, 1)
        if grain_freq[g] < 30
            grain_freq[g] = 30
        endif
    endif
    
    # Duration
    grain_dur[g] = (min_grain_ms + (max_grain_ms - min_grain_ms) * randomUniform(0, 1)) / 1000
    
    # Amplitude (scaled by density to prevent clipping)
    if evolution_type = 3
        if normalizedTime < 0.33
            grain_amp[g] = 0.4
        elsif normalizedTime < 0.66
            grain_amp[g] = 0.3
        else
            grain_amp[g] = 0.2
        endif
    else
        grain_amp[g] = 0.3 * (1 - normalizedTime * 0.2)
    endif
    
    # Scale by expected density at this time
    currentDensity = initial_density + (final_density - initial_density) * normalizedTime
    grain_amp[g] = grain_amp[g] / sqrt(max(10, currentDensity))
    
    # Clamp duration
    if grain_time[g] + grain_dur[g] > duration_s
        grain_dur[g] = duration_s - grain_time[g]
    endif
endfor

# Sort grains by time
appendInfoLine: "Sorting grains..."
for i to totalGrains - 1
    for j from i + 1 to totalGrains
        if grain_time[j] < grain_time[i]
            # Swap all properties
            tempTime = grain_time[i]
            tempFreq = grain_freq[i]
            tempDur = grain_dur[i]
            tempAmp = grain_amp[i]
            
            grain_time[i] = grain_time[j]
            grain_freq[i] = grain_freq[j]
            grain_dur[i] = grain_dur[j]
            grain_amp[i] = grain_amp[j]
            
            grain_time[j] = tempTime
            grain_freq[j] = tempFreq
            grain_dur[j] = tempDur
            grain_amp[j] = tempAmp
        endif
    endfor
endfor

# === Create output sound ===
outputSound = Create Sound from formula: "grains_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Synthesize grains in chunks ===
appendInfoLine: "Synthesizing grains..."

grainIndex = 1
chunkStart = 0
chunkSize = 0.5

while grainIndex <= totalGrains
    chunkEnd = chunkStart + chunkSize
    if chunkEnd > duration_s
        chunkEnd = duration_s
    endif
    
    # Build formula for grains in this time window
    chunkFormula$ = "0"
    grainsInChunk = 0
    
    while grainIndex <= totalGrains and grain_time[grainIndex] < chunkEnd and grainsInChunk < grainsPerChunk
        if grain_dur[grainIndex] > 0.005
            gTime = grain_time[grainIndex]
            gFreq = grain_freq[grainIndex]
            gDur = grain_dur[grainIndex]
            gAmp = grain_amp[grainIndex]
            
            sTime$ = fixed$(gTime, 5)
            sEnd$ = fixed$(gTime + gDur, 5)
            sAmp$ = fixed$(gAmp, 5)
            sFreq$ = fixed$(gFreq, 1)
            sDur$ = fixed$(gDur, 5)
            
            # Hanning envelope
            grainTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * x) * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
            chunkFormula$ = chunkFormula$ + grainTerm$
            
            grainsInChunk = grainsInChunk + 1
        endif
        
        grainIndex = grainIndex + 1
    endwhile
    
    # Apply chunk formula
    if chunkFormula$ <> "0"
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    # Progress
    if chunkStart mod 1 < chunkSize
        appendInfoLine: "  Time: ", fixed$(chunkStart, 1), " s (", grainsInChunk, " grains)"
    endif
    
    chunkStart = chunkEnd
endwhile

# === Apply fade ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Evolution - L fades, R grows
    appendInfoLine: "Creating stereo evolution..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.8 - 0.3 * (x / duration_s))"
    Filter (pass Hann band): 0, 3000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * (x / duration_s))"
    Filter (pass Hann band): 200, 5000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "grains_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating Cloud - accelerating rotation
    appendInfoLine: "Creating rotating cloud..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * cos(twoPi * 0.08 * x * (1 + x / duration_s)))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * sin(twoPi * 0.08 * x * (1 + x / duration_s)))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "grains_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 4
    # Wide Field - evolving stereo width
    appendInfoLine: "Creating wide field..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.3 * (x / duration_s))"
    Filter (pass Hann band): 0, 2500, 120
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.3 * (1 - x / duration_s))"
    Filter (pass Hann band): 150, 6000, 120
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "grains_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "grains_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
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
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    Erase all

    # --- Title ---
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Evolving Grain Mass: " + preset_name$ + " (" + evolution_type$ + ")"

    # --- Mono display copy ---
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
    endif

    # --- Panel 1: Output waveform ---
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: .disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"

    # --- Panel 2: Spectrogram (frequency evolution) ---
    Select outer viewport: 0, 8, 2.0, 4.6
    Select inner viewport: 0.6, 7.6, 2.1, 4.5
    selectObject: .disp
    if evolution_type = 2
        .maxFreqSpec = min(8000, base_frequency_Hz * frequency_evolution * 2)
    else
        .maxFreqSpec = min(6000, base_frequency_Hz * 4)
    endif
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    Select inner viewport: 0.6, 7.6, 2.1, 4.5
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    removeObject: .disp

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 4.7, 5.1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Density: " + fixed$(initial_density, 0) + "-" + fixed$(final_density, 0) + " grains/s | Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Grains: " + string$(totalGrains) + " | " + evolution_type$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
