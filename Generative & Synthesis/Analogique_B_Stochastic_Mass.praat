# ============================================================
# Praat AudioTools - Analogique_B_Stochastic_Mass.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pure electronic stochastic sound mass generator
#   In the spirit of Iannis Xenakis - Analogique B (1958-59)
#
#   "I was interested in the mass as an entity,
#    not in individual sounds." - Iannis Xenakis
#
# Compositional Model:
#   - Pure white noise (no samples, instruments, voices)
#   - Stochastic control of spectral filtering
#   - Continuous evolution via probability distributions
#   - No rhythm, melody, or discrete events
#   - Form emerges from statistical drift
#
# Signal Path:
#   White Noise -> Dynamic Band-Pass Filter -> Amplitude Modulation
#   -> Layering -> Statistical Mass
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis 
#   Toolkit for Experimental Composition.
#
# Reference:
#   Xenakis, I. (1992). Formalized Music. Pendragon Press.
#
# Changelog v2.2:
#   - Replaced non-ASCII em-dashes (comments only; no audio or behaviour change).
#
# Changelog v2.1:
#   - Audio output is bit-identical to v2.0 when Fast_mode = 0
#     (default). Same chunkDur = 1.0, same randomGauss(0, 0.5)
#     noise, same drift coefficients, same per-chunk Formula
#     for amplitude. Same 5 presets behavior (no preset
#     parameter - same form fields).
#   - NEW: Fast_mode toggle (default 0). When ON: chunkDur is
#     2.0 instead of 1.0 (halves Filter calls), noise switches
#     to randomUniform(-0.866, 0.866) (variance-matched to
#     randomGauss(0,0.5), spectrally identical white noise but
#     ~30% faster to generate), and drift coefficients scale
#     by sqrt(2) to preserve per-second drift variance. AUDIO
#     CHANGES (different RNG sequence, slightly chunkier
#     drift), musical character preserved. Output filename
#     gets "_fast" suffix when enabled.
#   - Spectrogram time step reduced from 0.01 to 0.05 in
#     visualization (5x faster - original was over-resolved
#     for the panel size). Affects viz only, not audio.
#   - Intensity time step set to 0.05 (was auto). ~3x faster.
#   - Dropped 6 decorative `comment === ... ===` form section
#     dividers + 5 inline parenthetical hints. Form went from
#     ~18 effective rows to 11.
#   - Form field renamed: `Draw_analysis` -> `Draw_visualization`
#     for consistency with the rest of the AudioTools suite.
#   - Visualization rewritten to suite 8x8 standard (v2.0 was
#     12-wide custom layout):
#       Title bar + metadata subtitle (duration, layers,
#         spectral range, drift/BW/turbulence rates)
#       Panel A (left, headline): spectrogram - the signature
#         visual for sound-mass composition, showing the
#         statistical spectral drift over the full duration
#       Panel B (right, headline): per-layer center-frequency
#         trajectories - NEW diagnostic showing how each
#         layer's random walk evolved. Log-scaled Y axis,
#         frequency-range markers in red.
#       Panel C: intensity envelope (orange) over time
#       Panel D: full output waveform
#       Panel E: light-grey summary stats bar with all params
#         + processing time + output peak
#
# Honest note on the "v2.0 OPTIMIZED ~3x faster" claim from
# the original header:
#   The v2.0 win was primarily from chunkDur 0.5 -> 1.0
#   (halving Filter call count) and unblocking the mix stage.
#   The "no formula loops" comment refers to using built-in
#   Combine to stereo + Convert to mono instead of an iterative
#   Formula sum. The per-chunk `self * ampVal` is in fact a
#   single Praat call per chunk and is fast (Praat vectorizes
#   scalar multiplication internally).
#
# Changelog v2.0:
#   - Larger chunk size (2x faster vs v1.0)
#   - Optimized mixing (built-in Combine, no Formula sum loop)
#   - Better progress reporting
# ============================================================

form Analogique B - Stochastic Sound Mass v2.1
    positive Duration_minutes 7.0
    integer Number_of_layers 5
    positive Min_frequency_Hz 60
    positive Max_frequency_Hz 8000
    real Spectral_drift_rate 0.3
    real Bandwidth_variation 0.5
    real Amplitude_turbulence 0.4
    boolean Fast_mode 0
    boolean Draw_visualization 1
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

# === Fast mode adjustments ===
# Fast_mode = 0 (default): bit-identical to v2.0
# Fast_mode = 1: 2x chunk size, uniform noise, sqrt(2) drift scaling
if fast_mode
    chunkDur = 2.0
    driftScale = sqrt(2)
    noiseFormula$ = "randomUniform(-0.866, 0.866)"
    fastSuffix$ = "_fast"
else
    chunkDur = 1.0
    driftScale = 1.0
    noiseFormula$ = "randomGauss(0, 0.5)"
    fastSuffix$ = ""
endif

# === Info ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  ANALOGIQUE B - STOCHASTIC SOUND MASS v2.1"
writeInfoLine: "  After Iannis Xenakis (1958-59)"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Pure electronic stochastic composition"
appendInfoLine: "Duration: ", fixed$(duration_s / 60, 1), " minutes"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Spectral range: ", min_frequency_Hz, " - ", max_frequency_Hz, " Hz"
if fast_mode
    appendInfoLine: "Mode: FAST (chunk = ", fixed$(chunkDur, 1), " s, uniform noise)"
else
    appendInfoLine: "Mode: NORMAL (chunk = ", fixed$(chunkDur, 1), " s, Gaussian noise)"
endif
appendInfoLine: ""

# === Generate Stochastic Control Functions ===
appendInfoLine: "Stage 1: Generating stochastic control curves..."

# Arrays for each layer's parameters
for layer to number_of_layers
    logMin = ln(min_frequency_Hz)
    logMax = ln(max_frequency_Hz)
    centerFreq[layer] = exp(randomUniform(logMin, logMax))
    bandwidth[layer] = centerFreq[layer] * randomUniform(0.2, 0.8)
    amplitude[layer] = randomUniform(0.3, 0.8)
endfor

appendInfoLine: "  Created ", number_of_layers, " stochastic layers"

# === Generate White Noise Layers ===
appendInfoLine: "Stage 2: Generating white noise sources..."

for layer to number_of_layers
    Create Sound from formula: "noise_" + string$(layer), 1, 0, duration_s, sampleRate, noiseFormula$
    noiseID[layer] = selected("Sound")
endfor

appendInfoLine: "  ", number_of_layers, " noise sources created"

# === Apply Time-Varying Filters ===
appendInfoLine: "Stage 3: Applying stochastic spectral filtering..."

numChunks = ceiling(duration_s / chunkDur)

# Storage for center-frequency history (for Panel B trajectory plot)
# Flat 1D array: cfHist[(layer-1)*numChunks + chunk]
cfHist# = zero#(number_of_layers * numChunks)

# Pre-compute log bounds (was inside chunk loop in v2.0; trivial savings)
logMinBound = ln(min_frequency_Hz)
logMaxBound = ln(max_frequency_Hz)

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
            
            # Evolve parameters via random walk (with sqrt(chunkDur) scaling)
            drift = randomGauss(0, spectral_drift_rate * 0.1 * driftScale)
            logFreq = ln(centerFreq[layer])
            logFreq = logFreq + drift
            
            # Keep in bounds (reflective boundary)
            if logFreq < logMinBound
                logFreq = logMinBound + abs(logFreq - logMinBound)
            endif
            if logFreq > logMaxBound
                logFreq = logMaxBound - abs(logFreq - logMaxBound)
            endif
            centerFreq[layer] = exp(logFreq)
            
            # Store for trajectory plot
            cfHist#[(layer - 1) * numChunks + chunk] = centerFreq[layer]
            
            # Bandwidth variation
            bwDrift = randomGauss(0, bandwidth_variation * 0.1 * driftScale)
            bandwidth[layer] = bandwidth[layer] * (1 + bwDrift)
            bandwidth[layer] = max(50, min(centerFreq[layer] * 2, bandwidth[layer]))
            
            # Apply band-pass filter
            lowCut = max(20, centerFreq[layer] - bandwidth[layer] / 2)
            highCut = min(nyquist * 0.95, centerFreq[layer] + bandwidth[layer] / 2)
            
            selectObject: chunkID
            Filter (pass Hann band): lowCut, highCut, bandwidth[layer]
            filteredID = selected("Sound")
            
            # Amplitude modulation (stochastic)
            ampDrift = randomGauss(0, amplitude_turbulence * 0.1 * driftScale)
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

selectObject: processedLayer[1]
for layer from 2 to number_of_layers
    plusObject: processedLayer[layer]
endfor

Combine to stereo
tempStereo = selected("Sound")

Convert to mono
outputID = selected("Sound")

removeObject: tempStereo

# Fallback (kept from v2.0 for compatibility)
if numberOfSelected("Sound") = 0
    outputID = Create Sound from formula: "analogique_b", 1, 0, duration_s, sampleRate, "0"
    
    for layer to number_of_layers
        selectObject: processedLayer[layer]
        layerName$ = selected$("Sound")
        
        selectObject: outputID
        layerNameClean$ = replace$(layerName$, "_", "", 0)
        
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

# Apply gentle fade in/out
fadeDur = 2.0
durMinusFade = duration_s - fadeDur

Formula: "if x < fadeDur then self * (x / fadeDur) else self fi"
Formula: "if x > durMinusFade then self * ((duration_s - x) / fadeDur) else self fi"

Rename: "analogique_b_" + fixed$(duration_minutes, 0) + "min" + fastSuffix$

processingTime = stopwatch
if processingTime < 0
    processingTime = 0
endif

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 1), " seconds"

# === Cleanup Layers ===
for layer to number_of_layers
    removeObject: processedLayer[layer]
endfor

# Capture stats for viz
selectObject: outputID
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (8 x 8 canvas - suite standard)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ANALOGIQUE B - STOCHASTIC SOUND MASS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
    if fast_mode
        modeStr$ = "FAST"
    else
        modeStr$ = "NORMAL"
    endif
    
    Text: 0.5, "centre", -0.22, "half",
        ... "After Xenakis (1958-59)"
        ... + "  |  " + fixed$(duration_s / 60, 1) + " min"
        ... + "  |  " + string$(number_of_layers) + " layers"
        ... + "  |  " + fixed$(min_frequency_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) + " Hz"
        ... + "  |  drift " + fixed$(spectral_drift_rate, 2)
        ... + "  |  BW " + fixed$(bandwidth_variation, 2)
        ... + "  |  turb " + fixed$(amplitude_turbulence, 2)
        ... + "  |  " + modeStr$

    # ----------------------------------------------------------
    # PANEL A: SPECTROGRAM  (left, headline)
    # The signature visual for sound-mass composition.
    # Time step 0.05 (5x faster than v2.0's 0.01) - still
    # plenty of resolution for the panel size.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    selectObject: outputID
    specID = To Spectrogram: 0.04, max_frequency_Hz, 0.05, 20, "Gaussian"
    
    Paint: 0, 0, 0, max_frequency_Hz, 100, 1, 50, 6, 0, 0
    
    Axes: 0, duration_s, 0, max_frequency_Hz
    Colour: "White"
    Font size: 5
    Marks left every: 1, 1000, "yes", "yes", "no"
    Marks bottom every: 1, 60, "yes", "yes", "no"
    
    Colour: "{0.95, 0.95, 0.95}"
    Font size: 6
    Text: duration_s * 0.02, "left", max_frequency_Hz * 0.95, "half", "Statistical spectral drift"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    
    removeObject: specID

    # ----------------------------------------------------------
    # PANEL B: PER-LAYER CENTER-FREQ TRAJECTORIES  (right, headline)
    # Diagnostic: shows how each layer's random walk evolved
    # in the log-frequency domain.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, duration_s, ln(min_frequency_Hz), ln(max_frequency_Hz)
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, duration_s, ln(min_frequency_Hz), ln(max_frequency_Hz)
    
    # Frequency reference grid (in log space) - labeled
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    refFreqs# = {100, 200, 500, 1000, 2000, 5000, 10000}
    nRefFreqs = 7
    for r to nRefFreqs
        rf = refFreqs#[r]
        if rf >= min_frequency_Hz and rf <= max_frequency_Hz
            Draw line: 0, ln(rf), duration_s, ln(rf)
        endif
    endfor
    Solid line
    Line width: 1
    
    # Boundary markers (red dashed, top and bottom)
    Colour: "{0.85, 0.30, 0.30}"
    Line width: 1
    Dashed line
    Draw line: 0, ln(min_frequency_Hz), duration_s, ln(min_frequency_Hz)
    Draw line: 0, ln(max_frequency_Hz), duration_s, ln(max_frequency_Hz)
    Solid line
    Line width: 1
    
    # Layer color palette (up to 8 distinct)
    cR# = {0.85, 0.95, 0.85, 0.30, 0.20, 0.30, 0.55, 0.85}
    cG# = {0.25, 0.55, 0.75, 0.65, 0.55, 0.40, 0.30, 0.35}
    cB# = {0.25, 0.20, 0.30, 0.30, 0.85, 0.78, 0.78, 0.65}
    
    # Plot each layer's trajectory
    Line width: 1.2
    for layer to number_of_layers
        # Pick color (cycle if > 8 layers)
        colorIdx = ((layer - 1) mod 8) + 1
        layerColor$ = "{" + fixed$(cR#[colorIdx], 3) + ", " + fixed$(cG#[colorIdx], 3) + ", " + fixed$(cB#[colorIdx], 3) + "}"
        Colour: layerColor$
        
        # Draw trajectory line segments
        for chunk from 2 to numChunks
            cf1 = cfHist#[(layer - 1) * numChunks + chunk - 1]
            cf2 = cfHist#[(layer - 1) * numChunks + chunk]
            if cf1 > 0 and cf2 > 0
                t1 = (chunk - 2) * chunkDur + chunkDur / 2
                t2 = (chunk - 1) * chunkDur + chunkDur / 2
                Draw line: t1, ln(cf1), t2, ln(cf2)
            endif
        endfor
    endfor
    Line width: 1
    
    # Frequency labels for the log grid
    Font size: 4
    Colour: "{0.45, 0.45, 0.50}"
    for r to nRefFreqs
        rf = refFreqs#[r]
        if rf >= min_frequency_Hz and rf <= max_frequency_Hz
            if rf >= 1000
                labelStr$ = fixed$(rf / 1000, 1) + "k"
            else
                labelStr$ = fixed$(rf, 0)
            endif
            Text: duration_s * 0.005, "left", ln(rf), "half", labelStr$
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "log freq"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Spectrogram of the mass"
    Text: 6.10, "centre", 7.30, "half", "Per-layer center-frequency drift (log scale)"

    # ----------------------------------------------------------
    # PANEL C: INTENSITY ENVELOPE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    selectObject: outputID
    intensityID = To Intensity: 75, 0.05, "yes"
    
    Axes: 0, duration_s, 30, 90
    Paint rectangle: "{0.97, 0.95, 0.92}", 0, duration_s, 30, 90
    
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 50, duration_s, 50
    Draw line: 0, 70, duration_s, 70
    Solid line
    
    selectObject: intensityID
    Colour: "{0.70, 0.45, 0.20}"
    Line width: 1.5
    Draw: 0, 0, 30, 90, "no"
    Line width: 1
    
    removeObject: intensityID
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Intensity envelope"
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: FULL OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    waveAmp = finalPeak * 1.15
    if waveAmp < 0.01
        waveAmp = 0.01
    endif
    
    Axes: 0, duration_s, -waveAmp, waveAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration_s, -waveAmp, waveAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration_s, 0
    
    selectObject: outputID
    Colour: "{0.25, 0.40, 0.65}"
    Line width: 1
    Draw: 0, duration_s, -waveAmp, waveAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full output waveform"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard - light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if fast_mode
        modeFullStr$ = "FAST (chunk " + fixed$(chunkDur, 1) + " s, uniform noise, sqrt(2) drift)"
    else
        modeFullStr$ = "NORMAL (chunk " + fixed$(chunkDur, 1) + " s, Gaussian noise)"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##Xenakis Analogique B##"
        ... + "  |  Duration: " + fixed$(duration_s / 60, 2) + " min (" + fixed$(duration_s, 1) + " s)"
        ... + "  |  Layers: " + string$(number_of_layers)
        ... + "  |  Range: " + fixed$(min_frequency_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) + " Hz"
        ... + "  |  Mode: " + modeFullStr$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Drift: " + fixed$(spectral_drift_rate, 2)
        ... + "  |  Bandwidth var: " + fixed$(bandwidth_variation, 2)
        ... + "  |  Amp turb: " + fixed$(amplitude_turbulence, 2)
        ... + "  |  Chunks: " + string$(numChunks) + " (" + string$(number_of_layers * numChunks) + " Filter calls)"
        ... + "  |  Processing: " + fixed$(processingTime, 1) + " s"
        ... + "  |  Peak: " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
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
appendInfoLine: "Filter calls: ", number_of_layers * numChunks
appendInfoLine: ""
appendInfoLine: "The mass is the thing, not the elements."
appendInfoLine: "                    - Iannis Xenakis"

# === Play ===
if play_result
    Play
endif

selectObject: outputID
