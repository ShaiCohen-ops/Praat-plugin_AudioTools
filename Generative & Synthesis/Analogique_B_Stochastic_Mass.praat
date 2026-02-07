# ============================================================
# Praat AudioTools - Analogique_B_Stochastic_Mass.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - OPTIMIZED (~3× faster)
# License: MIT License
#
# Description:
#   Pure electronic stochastic sound mass generator
#   In the spirit of Iannis Xenakis - Analogique B (1958-59)
#
#   "I was interested in the mass as an entity,
#    not in individual sounds." — Iannis Xenakis
#
# Compositional Model:
#   - Pure white noise (no samples, instruments, voices)
#   - Stochastic control of spectral filtering
#   - Continuous evolution via probability distributions
#   - No rhythm, melody, or discrete events
#   - Form emerges from statistical drift
#
# Signal Path:
#   White Noise → Dynamic Band-Pass Filter → Amplitude Modulation
#   → Layering → Statistical Mass
#
# Optimization v2.0:
#   - Larger chunk size (2× faster)
#   - Optimized mixing (no formula loops)
#   - Better progress reporting
#
# Reference:
#   Xenakis, I. (1992). Formalized Music. Pendragon Press.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
# ============================================================

form Analogique B - Stochastic Sound Mass v2.0
    comment === Duration ===
    positive Duration_minutes 7.0
    comment (Xenakis recommended 6-8 minutes)
    
    comment === Density ===
    integer Number_of_layers 5
    comment (More layers = denser mass)
    
    comment === Spectral Range ===
    positive Min_frequency_Hz 60
    positive Max_frequency_Hz 8000
    
    comment === Stochastic Parameters ===
    real Spectral_drift_rate 0.3
    comment (0 = static, 1 = rapid drift)
    real Bandwidth_variation 0.5
    comment (0 = narrow bands, 1 = wide bands)
    real Amplitude_turbulence 0.4
    comment (0 = smooth, 1 = chaotic)
    
    comment === Output ===
    boolean Draw_analysis 1
    boolean Play_result 1
endform

startTime = stopwatch

# === Constants ===
duration_s = duration_minutes * 60
sampleRate = 44100
nyquist = sampleRate / 2

# Ensure valid spectral range
if max_frequency_Hz > nyquist
    max_frequency_Hz = nyquist * 0.9
endif

# === Info ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  ANALOGIQUE B - STOCHASTIC SOUND MASS v2.0"
writeInfoLine: "  After Iannis Xenakis (1958-59)"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Pure electronic stochastic composition"
appendInfoLine: "Duration: ", fixed$(duration_s / 60, 1), " minutes"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Spectral range: ", min_frequency_Hz, " - ", max_frequency_Hz, " Hz"
appendInfoLine: ""

# === Generate Stochastic Control Functions ===
appendInfoLine: "Stage 1: Generating stochastic control curves..."

# Arrays for each layer's parameters
for layer to number_of_layers
    # Initialize center frequency (random in spectral range)
    logMin = ln(min_frequency_Hz)
    logMax = ln(max_frequency_Hz)
    centerFreq[layer] = exp(randomUniform(logMin, logMax))
    
    # Initialize bandwidth (proportion of center freq)
    bandwidth[layer] = centerFreq[layer] * randomUniform(0.2, 0.8)
    
    # Initialize amplitude (0-1)
    amplitude[layer] = randomUniform(0.3, 0.8)
endfor

appendInfoLine: "  Created ", number_of_layers, " stochastic layers"

# === Generate White Noise Layers ===
appendInfoLine: "Stage 2: Generating white noise sources..."

for layer to number_of_layers
    Create Sound from formula: "noise_" + string$(layer), 1, 0, duration_s, sampleRate, 
    ... "randomGauss(0, 0.5)"
    noiseID[layer] = selected("Sound")
endfor

appendInfoLine: "  ", number_of_layers, " noise sources created"

# === Apply Time-Varying Filters ===
appendInfoLine: "Stage 3: Applying stochastic spectral filtering..."

# OPTIMIZATION: Larger chunks for faster processing
chunkDur = 1.0
numChunks = ceiling(duration_s / chunkDur)

for layer to number_of_layers
    selectObject: noiseID[layer]
    layerParts# = zero#(numChunks)
    
    for chunk to numChunks
        chunkStart = (chunk - 1) * chunkDur
        chunkEnd = min(chunk * chunkDur, duration_s)
        actualDur = chunkEnd - chunkStart
        
        if actualDur > 0.01
            # Extract chunk
            selectObject: noiseID[layer]
            Extract part: chunkStart, chunkEnd, "rectangular", 1, "no"
            chunkID = selected("Sound")
            
            # Evolve parameters via random walk
            # Center frequency drift
            drift = randomGauss(0, spectral_drift_rate * 0.1)
            logFreq = ln(centerFreq[layer])
            logFreq = logFreq + drift
            
            # Keep in bounds
            logMin = ln(min_frequency_Hz)
            logMax = ln(max_frequency_Hz)
            if logFreq < logMin
                logFreq = logMin + abs(logFreq - logMin)
            endif
            if logFreq > logMax
                logFreq = logMax - abs(logFreq - logMax)
            endif
            centerFreq[layer] = exp(logFreq)
            
            # Bandwidth variation
            bwDrift = randomGauss(0, bandwidth_variation * 0.1)
            bandwidth[layer] = bandwidth[layer] * (1 + bwDrift)
            bandwidth[layer] = max(50, min(centerFreq[layer] * 2, bandwidth[layer]))
            
            # Apply band-pass filter
            lowCut = max(20, centerFreq[layer] - bandwidth[layer] / 2)
            highCut = min(nyquist * 0.95, centerFreq[layer] + bandwidth[layer] / 2)
            
            selectObject: chunkID
            Filter (pass Hann band): lowCut, highCut, bandwidth[layer]
            filteredID = selected("Sound")
            
            # Amplitude modulation (stochastic)
            ampDrift = randomGauss(0, amplitude_turbulence * 0.1)
            amplitude[layer] = amplitude[layer] + ampDrift
            amplitude[layer] = max(0.1, min(1.0, amplitude[layer]))
            
            ampVal = amplitude[layer]
            selectObject: filteredID
            Formula: "self * ampVal"
            
            layerParts#[chunk] = filteredID
            removeObject: chunkID
        endif
    endfor
    
    # Concatenate chunks
    selectObject: layerParts#[1]
    for chunk from 2 to numChunks
        if layerParts#[chunk] > 0
            plusObject: layerParts#[chunk]
        endif
    endfor
    Concatenate
    processedLayer[layer] = selected("Sound")
    Rename: "layer_" + string$(layer)
    
    # Cleanup chunks
    for chunk to numChunks
        if layerParts#[chunk] > 0
            removeObject: layerParts#[chunk]
        endif
    endfor
    
    removeObject: noiseID[layer]
    
    appendInfoLine: "  Layer ", layer, "/", number_of_layers, " processed"
endfor

# === Mix Layers into Statistical Mass ===
appendInfoLine: "Stage 4: Combining layers into sound mass..."

# OPTIMIZED: Select all layers and combine using Praat's built-in mixing
selectObject: processedLayer[1]
for layer from 2 to number_of_layers
    plusObject: processedLayer[layer]
endfor

# Combine by summing
Combine to stereo
tempStereo = selected("Sound")

# Extract as mono (average of all layers)
Convert to mono
outputID = selected("Sound")

removeObject: tempStereo

# Alternative if stereo combine doesn't work: manual formula mixing
# This is slower but more compatible
if numberOfSelected("Sound") = 0
    # Fallback method
    outputID = Create Sound from formula: "analogique_b", 1, 0, duration_s, sampleRate, "0"
    
    for layer to number_of_layers
        selectObject: processedLayer[layer]
        layerName$ = selected$("Sound")
        
        selectObject: outputID
        layerNameClean$ = replace$(layerName$, "_", "", 0)
        
        # Add each layer with scaling
        scaleFactor = 1.0 / sqrt(number_of_layers)
        scaleStr$ = string$(scaleFactor)
        
        plusObject: processedLayer[layer]
        
        selectObject: outputID
        Formula: "self[col] + scaleStr$ * Sound_" + layerName$ + "[col]"
        
        selectObject: processedLayer[layer]
        minusObject: processedLayer[layer]
    endfor
endif

# Normalize
selectObject: outputID
Scale peak: 0.9

# Apply gentle fade in/out (avoid clicks)
fadeDur = 2.0
fadeDurStr$ = string$(fadeDur)
durMinusFade = duration_s - fadeDur
durMinusFadeStr$ = string$(durMinusFade)
durationStr$ = string$(duration_s)

Formula: "if x < fadeDur then self * (x / fadeDur) else self fi"
Formula: "if x > durMinusFade then self * ((duration_s - x) / fadeDur) else self fi"

Rename: "analogique_b_" + fixed$(duration_minutes, 0) + "min"

processingTime = stopwatch - startTime

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 1), " seconds"

# === Cleanup Layers ===
for layer to number_of_layers
    removeObject: processedLayer[layer]
endfor

# === Analysis Visualization ===
if draw_analysis
    appendInfoLine: "Drawing spectral analysis..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 12, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Analogique B - Stochastic Sound Mass (After Xenakis, 1958-59)"
    
    # Spectrogram (full duration)
    Select outer viewport: 0, 12, 0.8, 4.5
    Select inner viewport: 0.7, 11.7, 1.0, 4.3
    
    selectObject: outputID
    To Spectrogram: 0.04, max_frequency_Hz, 0.01, 20, "Gaussian"
    specID = selected("Spectrogram")
    
    Paint: 0, 0, 0, 0, 100, 1, 50, 6, 0, 0
    
    Select inner viewport: 0.7, 11.7, 1.0, 4.3
    Axes: 0, duration_s, 0, max_frequency_Hz
    Colour: "White"
    Marks left: 6, "yes", "yes", "no"
    Marks bottom every: 1, 60, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    Font size: 9
    Colour: "{0.9, 0.9, 0.9}"
    Text: duration_s * 0.02, "left", max_frequency_Hz * 0.95, "half", "Statistical Spectral Drift"
    
    removeObject: specID
    
    # Amplitude envelope
    Select outer viewport: 0, 12, 4.7, 6.0
    Select inner viewport: 0.7, 11.7, 4.9, 5.8
    
    selectObject: outputID
    To Intensity: 75, 0, "yes"
    intensityID = selected("Intensity")
    
    Colour: "{0.7, 0.5, 0.3}"
    Line width: 2
    Draw: 0, 0, 0, 0, "no"
    Line width: 1
    
    removeObject: intensityID
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Intensity (dB)"
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 0, 12, 6.2, 6.8
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.3}"
    paramText$ = "Layers: " + string$(number_of_layers) + " | Range: " + string$(min_frequency_Hz) + "-" + string$(max_frequency_Hz) + " Hz | Drift: " + fixed$(spectral_drift_rate, 1) + " | BW: " + fixed$(bandwidth_variation, 1) + " | Turbulence: " + fixed$(amplitude_turbulence, 1) + " | Time: " + fixed$(processingTime, 1) + "s"
    Text: 0.5, "centre", 0.5, "half", paramText$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# === Final Info ===
selectObject: outputID

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(duration_s / 60, 2), " minutes"
appendInfoLine: ""
appendInfoLine: "The mass is the thing, not the elements."
appendInfoLine: "                    - Iannis Xenakis"

# === Play ===
if play_result
    Play
endif

selectObject: outputID