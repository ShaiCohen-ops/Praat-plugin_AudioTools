# ============================================================
# Praat AudioTools - Spectral_Driven_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral-Driven Vibrato - analyzes the spectral character
#   of the sound (flatness and roughness) and derives vibrato
#   parameters from it. Noisy sounds get deeper vibrato,
#   complex sounds get faster vibrato. Uses delay-line modulation.
#
# Changelog v0.2:
#   - Fixed input check
#   - Fixed formula syntax
#   - Fixed power calculation (re² + im²)
#   - Fixed object references (use IDs)
#   - Added form with parameters
#   - Added presets
#   - Added visualization
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
form Spectral-Driven Vibrato
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Natural
        option Moderate Expressive
        option Strong Character
        option Fast Flutter
        option Slow Sweep
    
    comment === Analysis Range ===
    positive Min_frequency_Hz 80
    positive Max_frequency_Hz 5000
    
    comment === Depth Mapping (semitones) ===
    positive Base_depth 0.05
    positive Max_depth_add 0.15
    
    comment === Rate Mapping (Hz) ===
    positive Base_rate_Hz 4.0
    positive Max_rate_add_Hz 3.0
    positive Roughness_scale 150
    
    comment === Delay Line ===
    positive Base_delay_ms 5.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Natural
    base_depth = 0.03
    max_depth_add = 0.10
    base_rate_Hz = 5.0
    max_rate_add_Hz = 2.0
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate Expressive
    base_depth = 0.05
    max_depth_add = 0.15
    base_rate_Hz = 4.5
    max_rate_add_Hz = 3.0
    presetName$ = "Moderate"
elsif preset = 4
    # Strong Character
    base_depth = 0.08
    max_depth_add = 0.25
    base_rate_Hz = 4.0
    max_rate_add_Hz = 4.0
    presetName$ = "Strong"
elsif preset = 5
    # Fast Flutter
    base_depth = 0.04
    max_depth_add = 0.10
    base_rate_Hz = 6.0
    max_rate_add_Hz = 4.0
    roughness_scale = 200
    presetName$ = "Flutter"
elsif preset = 6
    # Slow Sweep
    base_depth = 0.10
    max_depth_add = 0.20
    base_rate_Hz = 2.5
    max_rate_add_Hz = 2.0
    presetName$ = "Slow"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral-Driven Vibrato ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# === Spectral Analysis ===
appendInfoLine: "Analyzing spectrum..."

selectObject: original
To Spectrum: "yes"
spectrum = selected("Spectrum")

# Get spectrum info
selectObject: spectrum
nBins = Get number of bins
binWidth = Get bin width

# Initialize accumulators
lnSum = 0
linearSum = 0
validBins = 0
roughnessSum = 0
roughnessBins = 0

# Store power values for visualization
maxVizBins = min(nBins, 200)
vizFreqs# = zero#(maxVizBins)
vizPower# = zero#(maxVizBins)

# Analysis loop
for bin from 1 to nBins
    freq = (bin - 1) * binWidth
    
    if freq >= min_frequency_Hz and freq <= max_frequency_Hz
        # Get real AND imaginary parts for correct power
        re = Get real value in bin: bin
        im = Get imaginary value in bin: bin
        power = re * re + im * im
        power = max(power, 1e-12)
        
        lnSum = lnSum + ln(power)
        linearSum = linearSum + power
        
        # Roughness: deviation from neighbors
        if bin > 1 and bin < nBins
            rePrev = Get real value in bin: bin-1
            imPrev = Get imaginary value in bin: bin-1
            powerPrev = rePrev*rePrev + imPrev*imPrev
            
            reNext = Get real value in bin: bin+1
            imNext = Get imaginary value in bin: bin+1
            powerNext = reNext*reNext + imNext*imNext
            
            roughnessSum = roughnessSum + abs(power - (powerPrev + powerNext)/2)
            roughnessBins = roughnessBins + 1
        endif
        
        validBins = validBins + 1
        
        # Store for visualization
        vizIdx = floor((bin - 1) / nBins * maxVizBins) + 1
        if vizIdx >= 1 and vizIdx <= maxVizBins
            vizFreqs#[vizIdx] = freq
            vizPower#[vizIdx] = 10 * log10(power + 1e-12)
        endif
    endif
endfor

# Calculate spectral features
if validBins > 0 and roughnessBins > 0
    flatness = exp(lnSum / validBins) / (linearSum / validBins)
    roughness = roughnessSum / roughnessBins
else
    removeObject: spectrum
    exitScript: "Error: Could not calculate spectral features."
endif

appendInfoLine: "Spectral flatness: ", fixed$(flatness, 4)
appendInfoLine: "Spectral roughness: ", fixed$(roughness, 6)
appendInfoLine: ""

# === Map to Vibrato Parameters ===
# Flatness (0-1) → depth
depth = base_depth + (flatness * max_depth_add)

# Roughness → rate (scaled and clamped)
roughness_scaled = min(roughness * roughness_scale, 1)
rate_hz = base_rate_Hz + (roughness_scaled * max_rate_add_Hz)

appendInfoLine: "Derived vibrato parameters:"
appendInfoLine: "  Depth: ", fixed$(depth, 3), " semitones"
appendInfoLine: "  Rate: ", fixed$(rate_hz, 2), " Hz"
appendInfoLine: ""

# Cleanup spectrum
removeObject: spectrum

# === Apply Vibrato ===
appendInfoLine: "Applying delay-line vibrato..."

selectObject: original
Copy: originalName$ + "_spectralVib"
result = selected("Sound")

# Calculate base delay in samples
base = round(base_delay_ms * sampling / 1000)

# Apply vibrato formula
Formula: ~ self[max(1, min(ncol, col + round(base * (1 + depth * sin(2*pi*rate_hz*x)))))]

# Scale
selectObject: result
Scale peak: 0.95
Rename: originalName$ + "_spectralVib_" + presetName$

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral-Driven Vibrato: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Vibrato"
    Text bottom: "yes", "Time (s)"
    
    # Spectrum visualization
    Select outer viewport: 0, 8, 2.5, 3.7
    Select inner viewport: 0.6, 7.6, 2.6, 3.6
    
    # Find power range
    minPow = vizPower#[1]
    maxPow = vizPower#[1]
    for v from 2 to maxVizBins
        if vizPower#[v] < minPow
            minPow = vizPower#[v]
        endif
        if vizPower#[v] > maxPow
            maxPow = vizPower#[v]
        endif
    endfor
    powMargin = (maxPow - minPow) * 0.1
    
    Axes: min_frequency_Hz, max_frequency_Hz, minPow - powMargin, maxPow + powMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", min_frequency_Hz, max_frequency_Hz, minPow - powMargin, maxPow + powMargin
    
    # Draw spectrum
    Colour: "{0.5, 0.5, 0.7}"
    Line width: 1
    for v from 2 to maxVizBins
        if vizFreqs#[v] > 0 and vizFreqs#[v - 1] > 0
            Draw line: vizFreqs#[v - 1], vizPower#[v - 1], vizFreqs#[v], vizPower#[v]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Spectral features display
    Select outer viewport: 0, 4, 3.9, 4.9
    Select inner viewport: 0.6, 3.8, 4.0, 4.8
    
    Axes: 0, 2, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 2, 0, 1.2
    
    # Flatness bar
    Paint rectangle: "{0.7, 0.5, 0.5}", 0.3, 0.7, 0, flatness
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 1.1, "half", "Flatness"
    Text: 0.5, "centre", -0.1, "half", fixed$(flatness, 3)
    
    # Roughness bar (scaled for display)
    roughnessDisplay = min(roughness * 100, 1)
    Paint rectangle: "{0.5, 0.5, 0.7}", 1.3, 1.7, 0, roughnessDisplay
    Text: 1.5, "centre", 1.1, "half", "Roughness"
    Text: 1.5, "centre", -0.1, "half", fixed$(roughness, 4)
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Value"
    
    # Vibrato parameters display
    Select outer viewport: 4, 8, 3.9, 4.9
    Select inner viewport: 4.4, 7.6, 4.0, 4.8
    
    maxDepthDisplay = base_depth + max_depth_add
    maxRateDisplay = base_rate_Hz + max_rate_add_Hz
    
    Axes: 0, 2, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 2, 0, 1.2
    
    # Depth bar (normalized)
    depthNorm = depth / maxDepthDisplay
    Paint rectangle: "{0.5, 0.7, 0.5}", 0.3, 0.7, 0, depthNorm
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 1.1, "half", "Depth"
    Text: 0.5, "centre", -0.1, "half", fixed$(depth, 3) + " st"
    
    # Rate bar (normalized)
    rateNorm = rate_hz / maxRateDisplay
    Paint rectangle: "{0.7, 0.6, 0.5}", 1.3, 1.7, 0, rateNorm
    Text: 1.5, "centre", 1.1, "half", "Rate"
    Text: 1.5, "centre", -0.1, "half", fixed$(rate_hz, 1) + " Hz"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Param"
    
    # Mapping arrows
    Select outer viewport: 0, 8, 5.0, 5.4
    
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0.25, "centre", 0.5, "half", "Flatness → Depth"
    Text: 0.75, "centre", 0.5, "half", "Roughness → Rate"
    
    # Stats
    Select outer viewport: 0, 8, 5.5, 5.8
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Base delay: " + fixed$(base_delay_ms, 1) + " ms | Analysis: " + fixed$(min_frequency_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) + " Hz | Valid bins: " + string$(validBins)
    
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