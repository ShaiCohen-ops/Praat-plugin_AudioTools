# ============================================================
# Praat AudioTools - Dynamic Stochastic Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic Stochastic Synthesis with evolving grain density
#   and frequency. Inspired by Xenakis's GENDYN technique.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed filters, grain limiting, fade in/out, added visualization
#
# Changelog v0.3:
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced non-ASCII characters (arrows in the info line and plot footer,
#     superscript two in a comment, en-dash).
#
# Changelog v0.4:
#   - Fixed grain time distribution: the inverse-transform sampling used a power
#     law (t = T*u^(d0/d1)) that concentrated nearly all grains at the end and
#     left the start silent (the output began with dead air before any sound,
#     and initial_density was never realised). Replaced with the correct
#     inverse-CDF for a linear density, so grains now appear from the start at
#     initial_density and grow to final_density as intended.
# ============================================================

form Dynamic Stochastic Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Bloom
        option Storm Build
        option Cosmic Drift
        option Digital Cascade
        option Organic Growth
        option Harmonic Swarm
        option Metallic Storm
        option Whisper Cloud
    
    comment === Basic Settings ===
    positive Duration_s 6.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    
    comment === Density Evolution ===
    positive Initial_density 30
    positive Final_density 150
    real Frequency_evolution 1.0
    
    comment === Grain Settings ===
    positive Min_grain_duration_ms 20
    positive Max_grain_duration_ms 80
    
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
    # Gentle Bloom
    base_frequency_Hz = 80
    initial_density = 15
    final_density = 60
    frequency_evolution = 0.5
    min_grain_duration_ms = 30
    max_grain_duration_ms = 100
    preset_name$ = "GentleBloom"
elsif preset = 3
    # Storm Build
    base_frequency_Hz = 100
    initial_density = 20
    final_density = 200
    frequency_evolution = 1.2
    min_grain_duration_ms = 10
    max_grain_duration_ms = 50
    preset_name$ = "StormBuild"
elsif preset = 4
    # Cosmic Drift
    duration_s = 10
    base_frequency_Hz = 60
    initial_density = 10
    final_density = 80
    frequency_evolution = 2.0
    min_grain_duration_ms = 50
    max_grain_duration_ms = 150
    spatial_mode = 3
    preset_name$ = "CosmicDrift"
elsif preset = 5
    # Digital Cascade
    base_frequency_Hz = 180
    initial_density = 40
    final_density = 180
    frequency_evolution = 1.5
    min_grain_duration_ms = 10
    max_grain_duration_ms = 40
    spatial_mode = 4
    preset_name$ = "DigitalCascade"
elsif preset = 6
    # Organic Growth
    duration_s = 8
    base_frequency_Hz = 90
    initial_density = 25
    final_density = 100
    frequency_evolution = 0.8
    min_grain_duration_ms = 25
    max_grain_duration_ms = 90
    spatial_mode = 2
    preset_name$ = "OrganicGrowth"
elsif preset = 7
    # Harmonic Swarm
    base_frequency_Hz = 110
    initial_density = 35
    final_density = 120
    frequency_evolution = 1.0
    min_grain_duration_ms = 20
    max_grain_duration_ms = 60
    preset_name$ = "HarmonicSwarm"
elsif preset = 8
    # Metallic Storm
    base_frequency_Hz = 200
    initial_density = 50
    final_density = 250
    frequency_evolution = 1.8
    min_grain_duration_ms = 8
    max_grain_duration_ms = 30
    spatial_mode = 4
    preset_name$ = "MetallicStorm"
elsif preset = 9
    # Whisper Cloud
    duration_s = 10
    base_frequency_Hz = 70
    initial_density = 8
    final_density = 40
    frequency_evolution = 0.3
    min_grain_duration_ms = 40
    max_grain_duration_ms = 120
    spatial_mode = 3
    preset_name$ = "WhisperCloud"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 35

# Calculate total grains
avgDensity = (initial_density + final_density) / 2
totalGrains = round(avgDensity * duration_s)

# === Info ===
writeInfoLine: "=== Dynamic Stochastic Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Density: ", initial_density, " -> ", final_density, " grains/s"
appendInfoLine: "Total grains: ", totalGrains
appendInfoLine: ""

# === Pre-generate grain parameters ===
appendInfoLine: "Generating grain parameters..."

for g to totalGrains
    # Time distribution weighted by density evolution
    # Higher density at end means more grains placed later
    # Use inverse transform sampling for proper distribution
    u = randomUniform(0, 1)
    
    # Linear density: d(t) = d0 + (d1-d0)*t/T
    # CDF: F(t) = (d0*t + (d1-d0)*t^2/(2T)) / (avg*T)
    # For simplicity, use weighted random
    # Inverse-transform sampling for a LINEAR density d(t) = d0 + (d1-d0)*t/T.
    # The cumulative grain count is quadratic in t, so invert that quadratic.
    # (The previous t = T*u^(d0/d1) was a power law that starved the start,
    #  emptying the first part of the sound regardless of initial_density.)
    if abs(final_density - initial_density) < 0.001
        t = duration_s * u
    else
        discriminant = initial_density ^ 2 + (final_density - initial_density) * u * (initial_density + final_density)
        if discriminant < 0
            discriminant = 0
        endif
        t = duration_s * (-initial_density + sqrt(discriminant)) / (final_density - initial_density)
    endif
    
    normalizedTime = t / duration_s
    
    # Current frequency (evolving)
    currentFreq = base_frequency_Hz * (2 ^ (frequency_evolution * normalizedTime))
    
    # Grain parameters with randomization
    grain_time[g] = t
    grain_freq[g] = currentFreq * (0.8 + 0.4 * randomUniform(0, 1))
    grain_dur[g] = (min_grain_duration_ms + (max_grain_duration_ms - min_grain_duration_ms) * randomUniform(0, 1)) / 1000
    
    # Amplitude decreases over time (natural decay feel)
    grain_amp[g] = 0.15 * (1 - normalizedTime ^ 0.6)
    
    # Clamp duration
    if grain_time[g] + grain_dur[g] > duration_s
        grain_dur[g] = duration_s - grain_time[g]
    endif
endfor

# Sort grains by time for efficient chunking
appendInfoLine: "Sorting grains..."
for i to totalGrains - 1
    for j from i + 1 to totalGrains
        if grain_time[j] < grain_time[i]
            # Swap
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
outputSound = Create Sound from formula: "stochastic_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Process grains in chunks ===
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
            
            # Sine envelope (half-sine = Hanning-like)
            grainTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * x) * sin(pi * (x - " + sTime$ + ") / " + sDur$ + ") else 0 fi"
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
    # Stereo Evolution - L fades out, R fades in
    appendInfoLine: "Creating stereo evolution..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.8 - 0.3 * (x / duration_s))"
    Filter (pass Hann band): 0, 3500, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * (x / duration_s))"
    Filter (pass Hann band): 100, 6000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "stochastic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating Cloud - accelerating rotation
    appendInfoLine: "Creating rotating cloud..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * cos(twoPi * 0.1 * x * (1 + x / duration_s)))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.4 * sin(twoPi * 0.1 * x * (1 + x / duration_s)))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "stochastic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 4
    # Wide Field - extreme frequency separation with evolution
    appendInfoLine: "Creating wide field..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.7 - 0.2 * (x / duration_s))"
    Filter (pass Hann band): 0, 2000, 120
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.3 * (x / duration_s))"
    Filter (pass Hann band): 200, 7000, 120
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "stochastic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "stochastic_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSpectrogram
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
procedure drawSpectrogram

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Dynamic Stochastic Synthesis: " + preset_name$

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

    # --- Panel 1: Waveform ---
    Select outer viewport: 0, 8, 0.9, 2.4
    Select inner viewport: 0.75, 7.6, 1.05, 2.3
    selectObject: .disp
    Colour: "{0.20, 0.45, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 10
    Text left: "yes", "Output"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 2.6, 4.9
    Select inner viewport: 0.75, 7.6, 2.75, 4.8
    selectObject: .disp
    .maxFreqSpec = min(8000, base_frequency_Hz * (2 ^ frequency_evolution) * 2)
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec
    removeObject: .disp

    Select inner viewport: 0.75, 7.6, 2.75, 4.8
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    if spatial_mode = 2
        .spatial$ = "Stereo Evolution"
    elsif spatial_mode = 3
        .spatial$ = "Rotating Cloud"
    elsif spatial_mode = 4
        .spatial$ = "Wide Field"
    else
        .spatial$ = "Mono"
    endif
    Select outer viewport: 0, 8, 5.0, 5.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "Density: " + fixed$(initial_density, 0) + "-" + fixed$(final_density, 0) + " grains/s | Freq evo: " + fixed$(frequency_evolution, 1) + " | Grains: " + string$(totalGrains) + " | " + .spatial$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc