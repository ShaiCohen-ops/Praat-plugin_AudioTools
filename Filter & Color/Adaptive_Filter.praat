# ============================================================
# Praat AudioTools - Adaptive_Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Filter - Time-varying filter with sweeping cutoff.
#   Supports lowpass, highpass, and bandpass modes with optional
#   resonance. Uses high-quality FFT overlap-add processing.
#   Creates filter sweeps, builds, and spectral motion effects.
#
# Features:
#   - Filter types: Lowpass, Highpass, Bandpass
#   - Sweep curves: Linear, Exponential, Logarithmic, S-Curve
#   - Resonance with adjustable bandwidth
#   - Full stereo support
#   - Quality modes for speed/quality tradeoff
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Adaptive Filter
    optionmenu Preset: 1
        option Custom
        option Rising Lowpass (dark to bright)
        option Falling Lowpass (bright to dark)
        option Opening Highpass
        option Closing Highpass
        option Bandpass Sweep Up
        option Bandpass Sweep Down
        option Resonant Sweep
        option Acid Bass
        option Underwater
        option Telephone Effect
        option S-Curve Sweep
    comment === Filter Type ===
    optionmenu Filter_type: 1
        option Lowpass
        option Highpass
        option Bandpass
    comment === Frequency Sweep ===
    positive Start_frequency_(Hz) 200
    positive End_frequency_(Hz) 4000
    optionmenu Sweep_curve: 1
        option Linear
        option Exponential
        option Logarithmic
        option S-Curve (smooth)
    comment === Bandpass Width ===
    positive Bandwidth_(Hz) 500
    comment === Resonance ===
    real Resonance 0.0
    positive Resonance_bandwidth_(Hz) 100
    comment === Quality ===
    optionmenu Quality_mode: 2
        option Draft (fast, 80ms windows)
        option Standard (balanced, 40ms windows)
        option High (slow, 20ms windows)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Rising Lowpass
    filter_type = 1
    start_frequency = 200
    end_frequency = 8000
    sweep_curve = 2
    resonance = 0.2
    resonance_bandwidth = 120
    preset$ = "Rising Lowpass"
elsif preset = 3
    # Falling Lowpass
    filter_type = 1
    start_frequency = 8000
    end_frequency = 300
    sweep_curve = 3
    resonance = 0.2
    resonance_bandwidth = 120
    preset$ = "Falling Lowpass"
elsif preset = 4
    # Opening Highpass
    filter_type = 2
    start_frequency = 200
    end_frequency = 2000
    sweep_curve = 1
    resonance = 0.3
    resonance_bandwidth = 100
    preset$ = "Opening Highpass"
elsif preset = 5
    # Closing Highpass
    filter_type = 2
    start_frequency = 3000
    end_frequency = 100
    sweep_curve = 1
    resonance = 0.3
    resonance_bandwidth = 100
    preset$ = "Closing Highpass"
elsif preset = 6
    # Bandpass Sweep Up
    filter_type = 3
    start_frequency = 300
    end_frequency = 3000
    bandwidth = 400
    sweep_curve = 1
    resonance = 0.0
    preset$ = "Bandpass Sweep Up"
elsif preset = 7
    # Bandpass Sweep Down
    filter_type = 3
    start_frequency = 4000
    end_frequency = 400
    bandwidth = 500
    sweep_curve = 1
    resonance = 0.0
    preset$ = "Bandpass Sweep Down"
elsif preset = 8
    # Resonant Sweep
    filter_type = 1
    start_frequency = 200
    end_frequency = 4000
    sweep_curve = 1
    resonance = 0.8
    resonance_bandwidth = 60
    preset$ = "Resonant Sweep"
elsif preset = 9
    # Acid Bass
    filter_type = 1
    start_frequency = 150
    end_frequency = 3000
    sweep_curve = 2
    resonance = 1.2
    resonance_bandwidth = 40
    preset$ = "Acid Bass"
elsif preset = 10
    # Underwater
    filter_type = 1
    start_frequency = 800
    end_frequency = 300
    sweep_curve = 4
    resonance = 0.3
    resonance_bandwidth = 150
    preset$ = "Underwater"
elsif preset = 11
    # Telephone Effect
    filter_type = 3
    start_frequency = 800
    end_frequency = 800
    bandwidth = 2600
    sweep_curve = 1
    resonance = 0.0
    preset$ = "Telephone"
elsif preset = 12
    # S-Curve Sweep
    filter_type = 1
    start_frequency = 200
    end_frequency = 6000
    sweep_curve = 4
    resonance = 0.4
    resonance_bandwidth = 80
    preset$ = "S-Curve Sweep"
else
    preset$ = "Custom"
endif

# Get filter type name
if filter_type = 1
    filterType$ = "Lowpass"
elsif filter_type = 2
    filterType$ = "Highpass"
else
    filterType$ = "Bandpass"
endif

# Get sweep curve name
if sweep_curve = 1
    curve$ = "Linear"
elsif sweep_curve = 2
    curve$ = "Exponential"
elsif sweep_curve = 3
    curve$ = "Logarithmic"
else
    curve$ = "S-Curve"
endif

# Set window size based on quality
if quality_mode = 1
    window_size_s = 0.08
    quality$ = "Draft"
elsif quality_mode = 2
    window_size_s = 0.04
    quality$ = "Standard"
else
    window_size_s = 0.02
    quality$ = "High"
endif

# ============================================================
# SETUP
# ============================================================
clearinfo
writeInfoLine: "=== Adaptive Filter v1.0 ==="
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Filter: ", filterType$, " | Curve: ", curve$, " | Quality: ", quality$
appendInfoLine: "Sweep: ", round(start_frequency), " -> ", round(end_frequency), " Hz"
if filter_type = 3
    appendInfoLine: "Bandwidth: ", round(bandwidth), " Hz"
endif
if resonance > 0
    appendInfoLine: "Resonance: ", fixed$(resonance, 1), " (BW: ", round(resonance_bandwidth), " Hz)"
endif
appendInfoLine: ""

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Validate frequencies
if start_frequency >= nyquist
    start_frequency = nyquist - 100
endif
if end_frequency >= nyquist
    end_frequency = nyquist - 100
endif

if duration < 0.05
    exitScript: "Sound too short (minimum 0.05 seconds)."
endif

# Pre-calculate sweep parameters
freqRange = end_frequency - start_frequency
logStart = ln(max(start_frequency, 1))
logEnd = ln(max(end_frequency, 1))
logRange = logEnd - logStart

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1.5, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Adaptive Filter## | " + preset$ + " | " + filterType$
    
    # === FILTER SWEEP DISPLAY ===
    Select outer viewport: 0, 8, 0.6, 3.5
    Select inner viewport: 0.8, 7.5, 0.8, 3.2
    
    minFreqDisplay = 20
    maxFreqDisplay = min(nyquist, 12000)
    
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay
    
    # Draw shaded passband region
    nPts = 80
    for i from 1 to nPts
        t1 = (i - 1) * duration / nPts
        t2 = i * duration / nPts
        tNorm = (i - 0.5) / nPts
        
        # Calculate sweep position
        if sweep_curve = 1
            sweepPos = tNorm
        elsif sweep_curve = 2
            sweepPos = tNorm * tNorm
        elsif sweep_curve = 3
            sweepPos = sqrt(tNorm)
        else
            sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
        endif
        
        # Calculate cutoff frequency
        if sweep_curve = 3 and logRange <> 0
            cutoff = exp(logStart + sweepPos * logRange)
        else
            cutoff = start_frequency + sweepPos * freqRange
        endif
        
        # Draw passband based on filter type
        if filter_type = 1
            # Lowpass: shade below cutoff
            Paint rectangle: "{0.85, 0.92, 1.0}", t1, t2, minFreqDisplay, min(cutoff, maxFreqDisplay)
        elsif filter_type = 2
            # Highpass: shade above cutoff
            Paint rectangle: "{0.85, 0.92, 1.0}", t1, t2, max(cutoff, minFreqDisplay), maxFreqDisplay
        else
            # Bandpass: shade around cutoff
            lowEdge = max(minFreqDisplay, cutoff - bandwidth / 2)
            highEdge = min(maxFreqDisplay, cutoff + bandwidth / 2)
            Paint rectangle: "{0.85, 0.92, 1.0}", t1, t2, lowEdge, highEdge
        endif
    endfor
    
    # Draw cutoff frequency line
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 2
    
    prevTime = 0
    if sweep_curve = 3 and logRange <> 0
        prevFreq = exp(logStart)
    else
        prevFreq = start_frequency
    endif
    
    step = duration / 100
    plotTime = step
    while plotTime <= duration
        tNorm = plotTime / duration
        
        if sweep_curve = 1
            sweepPos = tNorm
        elsif sweep_curve = 2
            sweepPos = tNorm * tNorm
        elsif sweep_curve = 3
            sweepPos = sqrt(tNorm)
        else
            sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
        endif
        
        if sweep_curve = 3 and logRange <> 0
            cutoff = exp(logStart + sweepPos * logRange)
        else
            cutoff = start_frequency + sweepPos * freqRange
        endif
        
        Draw line: prevTime, prevFreq, plotTime, cutoff
        
        prevTime = plotTime
        prevFreq = cutoff
        plotTime = plotTime + step
    endwhile
    
    # For bandpass, draw bandwidth edges
    if filter_type = 3
        Colour: "{0.6, 0.6, 0.9}"
        Line width: 1
        Dotted line
        
        prevTime = 0
        if sweep_curve = 3 and logRange <> 0
            prevFreq = exp(logStart)
        else
            prevFreq = start_frequency
        endif
        
        plotTime = step
        while plotTime <= duration
            tNorm = plotTime / duration
            
            if sweep_curve = 1
                sweepPos = tNorm
            elsif sweep_curve = 2
                sweepPos = tNorm * tNorm
            elsif sweep_curve = 3
                sweepPos = sqrt(tNorm)
            else
                sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
            endif
            
            if sweep_curve = 3 and logRange <> 0
                cutoff = exp(logStart + sweepPos * logRange)
            else
                cutoff = start_frequency + sweepPos * freqRange
            endif
            
            # Lower edge
            lowEdge = max(minFreqDisplay, cutoff - bandwidth / 2)
            prevLow = max(minFreqDisplay, prevFreq - bandwidth / 2)
            Draw line: prevTime, prevLow, plotTime, lowEdge
            
            # Upper edge
            highEdge = min(maxFreqDisplay, cutoff + bandwidth / 2)
            prevHigh = min(maxFreqDisplay, prevFreq + bandwidth / 2)
            Draw line: prevTime, prevHigh, plotTime, highEdge
            
            prevTime = plotTime
            prevFreq = cutoff
            plotTime = plotTime + step
        endwhile
        
        Solid line
    endif
    
    # Resonance indicator
    if resonance > 0
        Colour: "{0.9, 0.6, 0.2}"
        Font size: 8
        Text: duration * 0.95, "right", maxFreqDisplay * 0.95, "half", "Q=" + fixed$(resonance, 1)
    endif
    
    # Axes and labels
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Frequency markers
    Colour: "{0.2, 0.2, 0.8}"
    Font size: 9
    Text: 0.02, "left", start_frequency, "half", string$(round(start_frequency)) + " Hz"
    Text: duration * 0.98, "right", end_frequency, "half", string$(round(end_frequency)) + " Hz"
    
    # Info box
    Select outer viewport: 0, 8, 3.6, 4.1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    infoText$ = "Curve: " + curve$ + " | Quality: " + quality$ + " | Duration: " + fixed$(duration, 2) + "s"
    if filter_type = 3
        infoText$ = infoText$ + " | BW: " + string$(round(bandwidth)) + " Hz"
    endif
    Text: 1.5, "centre", 0.5, "half", infoText$
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# PROCESSING
# ============================================================
overlap = 0.5
hopDur = window_size_s * overlap
nSegs = floor((duration - window_size_s) / hopDur) + 1
if nSegs < 1
    window_size_s = duration
    hopDur = duration
    nSegs = 1
endif

appendInfoLine: "Processing ", nSegs, " segments..."

# ------------------------------------------------------------
# PROCEDURE: Process one channel
# ------------------------------------------------------------
procedure processChannel: .inputSound
    selectObject: .inputSound
    .dur = Get total duration
    .sr = Get sampling frequency
    
    Create Sound from formula: "output_buffer", 1, 0, .dur, .sr, "0"
    .output = selected("Sound")
    .outputId$ = string$(.output)
    
    for seg from 1 to nSegs
        # Time & Progress
        segStart = (seg - 1) * hopDur
        segEnd = segStart + window_size_s
        segMid = (segStart + segEnd) / 2
        tNorm = segMid / .dur
        if tNorm > 1
            tNorm = 1
        endif
        
        # Calculate sweep position
        if sweep_curve = 1
            sweepPos = tNorm
        elsif sweep_curve = 2
            sweepPos = tNorm * tNorm
        elsif sweep_curve = 3
            sweepPos = sqrt(tNorm)
        else
            sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
        endif
        
        # Calculate cutoff frequency
        if sweep_curve = 3 and logRange <> 0
            cutoff = exp(logStart + sweepPos * logRange)
        else
            cutoff = start_frequency + sweepPos * freqRange
        endif
        
        # Clamp to valid range
        cutoff = max(20, min(nyquist - 100, cutoff))
        
        # Calculate filter bounds with smooth rolloff
        smoothing = max(50, cutoff * 0.15)
        
        if filter_type = 1
            # Lowpass
            lowBound = cutoff - smoothing
            highBound = cutoff + smoothing
            if lowBound < 0
                lowBound = 0
            endif
            if highBound > nyquist
                highBound = nyquist
            endif
        elsif filter_type = 2
            # Highpass
            lowBound = cutoff - smoothing
            highBound = cutoff + smoothing
            if lowBound < 0
                lowBound = 0
            endif
            if highBound > nyquist
                highBound = nyquist
            endif
        else
            # Bandpass
            bpLow = cutoff - bandwidth / 2
            bpHigh = cutoff + bandwidth / 2
            lowBound = bpLow - smoothing
            highBound = bpHigh + smoothing
            if lowBound < 0
                lowBound = 0
            endif
            if highBound > nyquist
                highBound = nyquist
            endif
        endif
        
        # Extract segment & convert to spectrum
        selectObject: .inputSound
        .seg = Extract part: segStart, segEnd, "Hanning", 1, "no"
        .spec = To Spectrum: "yes"
        
        # Apply filter in frequency domain
        selectObject: .spec
        
        if filter_type = 1
            # === LOWPASS ===
            low$ = string$(lowBound)
            high$ = string$(highBound)
            
            if resonance <= 0
                # Simple lowpass with smooth rolloff
                Formula: "if x < " + low$ + " then self else if x > " + high$ + " then 0 else self * 0.5 * (1 + cos(pi * (x - " + low$ + ") / (" + high$ + " - " + low$ + "))) endif endif"
            else
                # Lowpass with resonance peak at cutoff
                cut$ = string$(cutoff)
                res$ = string$(resonance)
                bw$ = string$(resonance_bandwidth)
                Formula: "if x > " + high$ + " then 0 else if x < " + low$ + " then self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) else self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) * 0.5 * (1 + cos(pi * (x - " + low$ + ") / (" + high$ + " - " + low$ + "))) endif endif"
            endif
            
        elsif filter_type = 2
            # === HIGHPASS ===
            low$ = string$(lowBound)
            high$ = string$(highBound)
            
            if resonance <= 0
                # Simple highpass with smooth rolloff
                Formula: "if x > " + high$ + " then self else if x < " + low$ + " then 0 else self * 0.5 * (1 - cos(pi * (x - " + low$ + ") / (" + high$ + " - " + low$ + "))) endif endif"
            else
                # Highpass with resonance peak at cutoff
                cut$ = string$(cutoff)
                res$ = string$(resonance)
                bw$ = string$(resonance_bandwidth)
                Formula: "if x < " + low$ + " then 0 else if x > " + high$ + " then self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) else self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) * 0.5 * (1 - cos(pi * (x - " + low$ + ") / (" + high$ + " - " + low$ + "))) endif endif"
            endif
            
        else
            # === BANDPASS ===
            bpLow$ = string$(bpLow)
            bpHigh$ = string$(bpHigh)
            lowB$ = string$(lowBound)
            highB$ = string$(highBound)
            smooth$ = string$(smoothing)
            
            if resonance <= 0
                # Bandpass with smooth edges
                Formula: "if x < " + lowB$ + " then 0 else if x > " + highB$ + " then 0 else if x < " + bpLow$ + " then self * 0.5 * (1 - cos(pi * (x - " + lowB$ + ") / " + smooth$ + ")) else if x > " + bpHigh$ + " then self * 0.5 * (1 + cos(pi * (x - " + bpHigh$ + ") / " + smooth$ + ")) else self endif endif endif endif"
            else
                # Bandpass with resonance at center
                cut$ = string$(cutoff)
                res$ = string$(resonance)
                bw$ = string$(resonance_bandwidth)
                Formula: "if x < " + lowB$ + " then 0 else if x > " + highB$ + " then 0 else if x < " + bpLow$ + " then self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) * 0.5 * (1 - cos(pi * (x - " + lowB$ + ") / " + smooth$ + ")) else if x > " + bpHigh$ + " then self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) * 0.5 * (1 + cos(pi * (x - " + bpHigh$ + ") / " + smooth$ + ")) else self * (1 + " + res$ + " * exp(-((x - " + cut$ + ")/" + bw$ + ")^2)) endif endif endif endif"
            endif
        endif
        
        # Convert back to sound
        To Sound
        .segFilt = selected("Sound")
        removeObject: .seg, .spec
        
        # Mix into output buffer (overlap-add)
        # Formula (part) restricts evaluation to [segStart, segEnd] only,
        # avoiding the O(n_total) scan that full Formula requires.
        # col-indexed access avoids time-domain interpolation overhead.
        selectObject: .segFilt
        .segNs = Get number of samples
        selectObject: .output
        .s1 = Get sample number from time: segStart
        if .s1 < 1
            .s1 = 1
        endif
        .s2 = .s1 + .segNs - 1
        .outNs = Get number of samples
        if .s2 > .outNs
            .s2 = .outNs
        endif
        .off = .s1 - 1
        Formula (part): segStart, segEnd, 1, 1,
            ... "self + object[" + string$(.segFilt) + ", col - " + string$(.off) + "]"
        
        removeObject: .segFilt
        
        # Progress indicator
        if seg mod 50 = 0
            appendInfo: "."
        endif
    endfor
    
    selectObject: .output
endproc

# ============================================================
# MAIN PROCESSING
# ============================================================
if numChannels = 1
    selectObject: sound
    inputMono = Copy: "input_mono"
    @processChannel: inputMono
    finalOutput = selected("Sound")
    removeObject: inputMono
else
    selectObject: sound
    Extract one channel: 1
    inputL = selected("Sound")
    selectObject: sound
    Extract one channel: 2
    inputR = selected("Sound")
    
    appendInfo: "L"
    @processChannel: inputL
    outputL = selected("Sound")
    appendInfoLine: ""
    
    appendInfo: "R"
    @processChannel: inputR
    outputR = selected("Sound")
    appendInfoLine: ""
    
    removeObject: inputL, inputR
    selectObject: outputL
    plusObject: outputR
    Combine to stereo
    finalOutput = selected("Sound")
    removeObject: outputL, outputR
endif

appendInfoLine: "Done."

# ============================================================
# FINALIZE
# ============================================================
selectObject: finalOutput
Scale peak: scale_peak
Rename: originalName$ + "_" + filterType$ + "_" + quality$

finalName$ = selected$("Sound")

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Filter: ", filterType$
appendInfoLine: "Sweep: ", round(start_frequency), " -> ", round(end_frequency), " Hz (", curve$, ")"

if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    selectObject: finalOutput
    Play
endif

selectObject: sound
