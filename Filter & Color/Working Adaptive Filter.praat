# ============================================================
# Praat AudioTools - Adaptive Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#   Time-varying filter with sweeping cutoff frequency.
#   Creates lowpass, highpass, or bandpass filters whose
#   cutoff frequency changes over time - useful for filter
#   sweeps, builds, and spectral motion effects.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Adaptive Filter
    optionmenu Preset: 1
        option Custom
        option Rising Lowpass (dark to bright)
        option Falling Lowpass (bright to dark)
        option Opening Bandpass
        option Closing Bandpass
        option Slow Sweep
        option Fast Sweep
        option Telephone Effect
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
        option S-Curve
    comment === Bandpass Only ===
    positive Bandwidth_(Hz) 500
    comment === Quality ===
    integer Num_segments 30
    positive Rolloff_smoothness 100
    comment === Output ===
    boolean Draw_response 1
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
    num_segments = 40
elsif preset = 3
    # Falling Lowpass
    filter_type = 1
    start_frequency = 8000
    end_frequency = 300
    sweep_curve = 3
    num_segments = 40
elsif preset = 4
    # Opening Bandpass
    filter_type = 3
    start_frequency = 500
    end_frequency = 3000
    bandwidth = 200
    sweep_curve = 1
    num_segments = 35
elsif preset = 5
    # Closing Bandpass
    filter_type = 3
    start_frequency = 3000
    end_frequency = 400
    bandwidth = 300
    sweep_curve = 1
    num_segments = 35
elsif preset = 6
    # Slow Sweep
    filter_type = 1
    start_frequency = 300
    end_frequency = 5000
    sweep_curve = 4
    num_segments = 25
elsif preset = 7
    # Fast Sweep
    filter_type = 1
    start_frequency = 200
    end_frequency = 6000
    sweep_curve = 1
    num_segments = 60
elsif preset = 8
    # Telephone Effect
    filter_type = 3
    start_frequency = 400
    end_frequency = 3400
    bandwidth = 3000
    sweep_curve = 1
    num_segments = 20
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Validate frequencies
start_frequency = min(start_frequency, nyquist * 0.9)
end_frequency = min(end_frequency, nyquist * 0.9)

if duration < 0.05
    exitScript: "Sound too short (min 0.05s)."
endif

# Ensure reasonable segment count
segmentDur = duration / num_segments
if segmentDur < 0.01
    num_segments = floor(duration / 0.01)
    segmentDur = duration / num_segments
endif

writeInfoLine: "=== Adaptive Filter ==="
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Segments: ", num_segments
appendInfoLine: "Frequency: ", round(start_frequency), " -> ", round(end_frequency), " Hz"
appendInfoLine: ""

# Filter type names
filterNames$[1] = "Lowpass"
filterNames$[2] = "Highpass"
filterNames$[3] = "Bandpass"

curveNames$[1] = "Linear"
curveNames$[2] = "Exponential"
curveNames$[3] = "Logarithmic"
curveNames$[4] = "S-Curve"

# ============================================================
# DRAW FILTER SWEEP
# ============================================================
if draw_response
    Erase all
    Select outer viewport: 0, 6, 0, 4.5
    
    maxFreqDisplay = min(nyquist, max(start_frequency, end_frequency) * 1.5)
    maxFreqDisplay = min(maxFreqDisplay, 10000)
    
    Axes: 0, duration, 0, maxFreqDisplay
    
    Colour: "Black"
    Draw inner box
    
    # Grid
    Colour: "{0.8,0.8,0.8}"
    
    gridF = 1000
    while gridF < maxFreqDisplay
        Draw line: 0, gridF, duration, gridF
        gridF = gridF + 1000
    endwhile
    
    # Draw cutoff frequency sweep
    Colour: "Blue"
    Line width: 2
    
    step = duration / 200
    plotTime = 0
    
    # Calculate first point
    freqRange = end_frequency - start_frequency
    logStart = ln(max(start_frequency, 1))
    logEnd = ln(max(end_frequency, 1))
    logRange = logEnd - logStart
    
    # First point
    tNorm = 0
    if sweep_curve = 1
        sweepPos = tNorm
    elsif sweep_curve = 2
        sweepPos = tNorm * tNorm
    elsif sweep_curve = 3
        sweepPos = sqrt(tNorm)
    elsif sweep_curve = 4
        sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
    endif
    
    if sweep_curve = 3 and logRange <> 0
        prevFreq = exp(logStart + sweepPos * logRange)
    else
        prevFreq = start_frequency + sweepPos * freqRange
    endif
    prevTime = 0
    
    plotTime = step
    while plotTime <= duration
        tNorm = plotTime / duration
        
        if sweep_curve = 1
            sweepPos = tNorm
        elsif sweep_curve = 2
            sweepPos = tNorm * tNorm
        elsif sweep_curve = 3
            sweepPos = sqrt(tNorm)
        elsif sweep_curve = 4
            sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
        endif
        
        if sweep_curve = 3 and logRange <> 0
            cutoffFreq = exp(logStart + sweepPos * logRange)
        else
            cutoffFreq = start_frequency + sweepPos * freqRange
        endif
        
        Draw line: prevTime, prevFreq, plotTime, cutoffFreq
        
        # For bandpass, also draw bandwidth edges
        if filter_type = 3
            Colour: "{0.7,0.7,1.0}"
            Line width: 1
            Draw line: prevTime, max(0, prevFreq - bandwidth/2), plotTime, max(0, cutoffFreq - bandwidth/2)
            Draw line: prevTime, prevFreq + bandwidth/2, plotTime, cutoffFreq + bandwidth/2
            Colour: "Blue"
            Line width: 2
        endif
        
        prevTime = plotTime
        prevFreq = cutoffFreq
        plotTime = plotTime + step
    endwhile
    
    # Labels
    Colour: "Black"
    Font size: 12
    Text: duration / 2, "Centre", maxFreqDisplay * 1.08, "Half", "Adaptive " + filterNames$[filter_type] + " Filter"
    
    Font size: 10
    Text: duration / 2, "Centre", -maxFreqDisplay * 0.08, "Half", "Time (s)"
    
    # Info
    Colour: "{0.4,0.4,0.4}"
    Font size: 9
    Text: duration * 0.15, "Centre", maxFreqDisplay * 0.95, "Half", "Curve: " + curveNames$[sweep_curve]
    Text: duration * 0.15, "Centre", maxFreqDisplay * 0.88, "Half", "Segments: " + string$(num_segments)
    
    # Axis marks
    Colour: "Black"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    Line width: 1
endif

# ============================================================
# PREPARE SOURCE
# ============================================================
selectObject: originalID
if numChannels > 1
    monoSource = Convert to mono
else
    monoSource = Copy: "source"
endif

# ============================================================
# PROCESS ADAPTIVE FILTER
# ============================================================
appendInfoLine: "Processing..."

# Create output sound
outputSound = Create Sound from formula: "output", 1, 0, duration, sampleRate, "0"

# Pre-calculate frequency range for sweep
freqRange = end_frequency - start_frequency
logStart = ln(max(start_frequency, 1))
logEnd = ln(max(end_frequency, 1))
logRange = logEnd - logStart

for seg from 1 to num_segments
    # Segment boundaries
    segStart = (seg - 1) * segmentDur
    segEnd = seg * segmentDur
    segMid = (segStart + segEnd) / 2
    
    # Calculate normalized time position
    tNorm = segMid / duration
    
    # Apply sweep curve
    if sweep_curve = 1
        sweepPos = tNorm
    elsif sweep_curve = 2
        sweepPos = tNorm * tNorm
    elsif sweep_curve = 3
        sweepPos = sqrt(tNorm)
    elsif sweep_curve = 4
        sweepPos = 0.5 - 0.5 * cos(pi * tNorm)
    endif
    
    # Calculate cutoff frequency
    if sweep_curve = 3 and logRange <> 0
        cutoffFreq = exp(logStart + sweepPos * logRange)
    else
        cutoffFreq = start_frequency + sweepPos * freqRange
    endif
    
    # Clamp to valid range
    cutoffFreq = max(20, min(nyquist - 100, cutoffFreq))
    
    # Extract segment with overlap for crossfade
    overlapDur = min(0.005, segmentDur * 0.1)
    extractStart = max(0, segStart - overlapDur)
    extractEnd = min(duration, segEnd + overlapDur)
    
    selectObject: monoSource
    segSound = Extract part: extractStart, extractEnd, "Hanning", 1, "no"
    
    # Apply filter based on type
    selectObject: segSound
    
    if filter_type = 1
        # Lowpass
        filtered = Filter (pass Hann band): 0, cutoffFreq, rolloff_smoothness
    elsif filter_type = 2
        # Highpass
        filtered = Filter (pass Hann band): cutoffFreq, nyquist - 50, rolloff_smoothness
    elsif filter_type = 3
        # Bandpass
        lowBound = max(20, cutoffFreq - bandwidth / 2)
        highBound = min(nyquist - 50, cutoffFreq + bandwidth / 2)
        if highBound <= lowBound
            highBound = lowBound + 100
        endif
        filtered = Filter (pass Hann band): lowBound, highBound, rolloff_smoothness
    endif
    
    # Rename for formula reference
    selectObject: filtered
    Rename: "seg"
    
    # Add to output
    offsetInExtract = segStart - extractStart
    segStartStr$ = fixed$(segStart, 8)
    offsetStr$ = fixed$(offsetInExtract, 8)
    
    selectObject: outputSound
    Formula (part): segStart, segEnd, 1, 1, "self + Sound_seg(x - " + segStartStr$ + " + " + offsetStr$ + ")"
    
    # Cleanup
    removeObject: segSound, filtered
    
    # Progress
    if seg mod 10 = 0
        appendInfoLine: "  ", seg, "/", num_segments
    endif
endfor

# ============================================================
# FINALIZE
# ============================================================
appendInfoLine: "Finalizing..."

selectObject: outputSound
Rename: originalName$ + "_adaptive"

# Normalize
Scale peak: 0.95

# Cleanup
removeObject: monoSource

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Filter: ", filterNames$[filter_type]
appendInfoLine: "Sweep: ", round(start_frequency), " -> ", round(end_frequency), " Hz"
appendInfoLine: "Curve: ", curveNames$[sweep_curve]

if play_result
    selectObject: outputSound
    Play
endif
