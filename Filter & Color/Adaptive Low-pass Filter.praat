# ============================================================
# Praat AudioTools - Adaptive Low-pass Filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-varying low-pass filter using overlap-add spectral processing.
#   The cutoff frequency sweeps linearly from start to end over the
#   sound's duration, creating a dynamic filtering effect.
#   Includes resonance control for emphasis at cutoff frequency.
#   True stereo processing preserves spatial image.
#   Optional visualization of filter trajectory and response curves.
#
# Technical approach:
#   - Divides sound into overlapping Hann-windowed frames
#   - Applies spectral low-pass filter to each frame at interpolated cutoff
#   - Optional resonance peak at cutoff frequency (Gaussian boost)
#   - Reconstructs via overlap-add synthesis (50% overlap, Hann window)
#   - Processes L/R channels independently for true stereo
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Adaptive Low-Pass Filter
    comment Time-varying low-pass filter with frequency sweep.
    comment Uses overlap-add spectral processing.
    optionmenu Preset: 1
        option Default
        option Gentle Sweep
        option Sharp Transition
        option Narrow Band
        option Opening Filter
        option Closing Filter
        option Resonant Sweep
        option Acid Bass
        option Underwater
    comment === Filter sweep parameters ===
    positive start_cutoff_frequency 200
    comment (starting cutoff frequency in Hz)
    positive end_cutoff_frequency 2000
    comment (ending cutoff frequency in Hz)
    comment === Filter character ===
    real resonance 0.0
    comment (resonance: 0=none, 0.5=moderate, 1.0=strong, >1=self-oscillation)
    positive resonance_bandwidth 100
    comment (width of resonance peak in Hz)
    positive filter_smoothing 100
    comment (filter roll-off transition width in Hz)
    comment === Processing parameters ===
    positive frame_duration 0.05
    comment (analysis frame duration in seconds)
    comment === Output options ===
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean draw_filter_response 1
    comment (draw filter trajectory and response curves)
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Gentle Sweep"
    start_cutoff_frequency = 300
    end_cutoff_frequency = 1500
    filter_smoothing = 150
    resonance = 0.2
    resonance_bandwidth = 120
elif preset$ = "Sharp Transition"
    start_cutoff_frequency = 100
    end_cutoff_frequency = 3000
    filter_smoothing = 50
    resonance = 0.3
    resonance_bandwidth = 80
elif preset$ = "Narrow Band"
    start_cutoff_frequency = 400
    end_cutoff_frequency = 800
    filter_smoothing = 80
    resonance = 0.5
    resonance_bandwidth = 60
elif preset$ = "Opening Filter"
    start_cutoff_frequency = 150
    end_cutoff_frequency = 8000
    filter_smoothing = 100
    resonance = 0.4
    resonance_bandwidth = 100
elif preset$ = "Closing Filter"
    start_cutoff_frequency = 8000
    end_cutoff_frequency = 150
    filter_smoothing = 100
    resonance = 0.4
    resonance_bandwidth = 100
elif preset$ = "Resonant Sweep"
    start_cutoff_frequency = 200
    end_cutoff_frequency = 4000
    filter_smoothing = 80
    resonance = 0.8
    resonance_bandwidth = 60
elif preset$ = "Acid Bass"
    start_cutoff_frequency = 150
    end_cutoff_frequency = 3000
    filter_smoothing = 40
    resonance = 1.2
    resonance_bandwidth = 40
elif preset$ = "Underwater"
    start_cutoff_frequency = 800
    end_cutoff_frequency = 300
    filter_smoothing = 200
    resonance = 0.3
    resonance_bandwidth = 150
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Validate frequency parameters
if start_cutoff_frequency >= nyquist
    exitScript: "Start cutoff (" + string$(start_cutoff_frequency) + " Hz) must be below Nyquist (" + string$(nyquist) + " Hz)."
endif
if end_cutoff_frequency >= nyquist
    exitScript: "End cutoff (" + string$(end_cutoff_frequency) + " Hz) must be below Nyquist (" + string$(nyquist) + " Hz)."
endif

# ============================================================
# Processing parameters
# ============================================================
hopDuration = frame_duration / 2
numFrames = floor((duration - frame_duration) / hopDuration) + 1
if numFrames < 1
    numFrames = 1
endif

# Generate unique ID for temp objects
uniqueID$ = string$(randomInteger(10000, 99999))
tempFrameName$ = "tmp_frame_" + uniqueID$
tempSumName$ = "tmp_sum_" + uniqueID$

# ============================================================
# Procedure: Draw filter visualization
# ============================================================
procedure drawFilterVisualization
    Erase all
    
    minFreqDisplay = 20
    maxFreqDisplay = min(nyquist, 20000)
    freqRange = maxFreqDisplay - minFreqDisplay
    
    # Smart tick intervals
    if freqRange > 10000
        freqTickInterval = 5000
    elsif freqRange > 5000
        freqTickInterval = 2000
    elsif freqRange > 2000
        freqTickInterval = 1000
    else
        freqTickInterval = 500
    endif
    
    if duration > 10
        timeTickInterval = 2
    elsif duration > 5
        timeTickInterval = 1
    elsif duration > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # ========================================================
    # PANEL 1: Cutoff trajectory over time (top)
    # ========================================================
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.8, 5.8, 0.5, 2.6
    
    Axes: 0, duration, minFreqDisplay, maxFreqDisplay
    
    # Shaded passband region
    Colour: "{0.85, 0.92, 1}"
    numDrawPoints = 100
    for iPoint from 1 to numDrawPoints
        t1 = (iPoint - 1) * duration / numDrawPoints
        t2 = iPoint * duration / numDrawPoints
        progress1 = t1 / duration
        cutoff1 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress1
        Paint rectangle: "{0.85, 0.92, 1}", t1, t2, minFreqDisplay, cutoff1
    endfor
    
    # Cutoff line
    Red
    Line width: 2
    for iPoint from 1 to numDrawPoints - 1
        t1 = (iPoint - 1) * duration / numDrawPoints
        t2 = iPoint * duration / numDrawPoints
        progress1 = t1 / duration
        progress2 = t2 / duration
        cutoff1 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress1
        cutoff2 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress2
        Draw line: t1, cutoff1, t2, cutoff2
    endfor
    
    # Resonance bandwidth
    if resonance > 0
        Colour: "{1, 0.7, 0.7}"
        Line width: 1
        Dotted line
        for iPoint from 1 to numDrawPoints - 1
            t1 = (iPoint - 1) * duration / numDrawPoints
            t2 = iPoint * duration / numDrawPoints
            progress1 = t1 / duration
            progress2 = t2 / duration
            cutoff1 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress1
            cutoff2 = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress2
            resHigh1 = cutoff1 + resonance_bandwidth / 2
            resHigh2 = cutoff2 + resonance_bandwidth / 2
            resLow1 = cutoff1 - resonance_bandwidth / 2
            resLow2 = cutoff2 - resonance_bandwidth / 2
            Draw line: t1, resHigh1, t2, resHigh2
            Draw line: t1, resLow1, t2, resLow2
        endfor
        Solid line
    endif
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "##Cutoff Trajectory## - " + originalName$
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, freqTickInterval, "yes", "yes", "no"
    
    # ========================================================
    # PANEL 2: Filter response curves (bottom)
    # ========================================================
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.8, 5.8, 3.5, 5.6
    
    maxGain = 1.2 + resonance
    if maxGain < 1.5
        maxGain = 1.5
    endif
    
    if maxGain > 2
        gainTickInterval = 0.5
    else
        gainTickInterval = 0.25
    endif
    
    Axes: minFreqDisplay, maxFreqDisplay, 0, maxGain
    
    # Unity gain reference
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: minFreqDisplay, 1, maxFreqDisplay, 1
    Solid line
    
    # Filter response at 5 time points
    numCurves = 5
    for iCurve from 1 to numCurves
        if numCurves > 1
            t = (iCurve - 1) * duration / (numCurves - 1)
        else
            t = 0
        endif
        progress = t / duration
        currentCutoff = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress
        
        if iCurve = 1
            Colour: "{0, 0, 0.8}"
        elsif iCurve = 2
            Colour: "{0, 0.6, 0.8}"
        elsif iCurve = 3
            Colour: "{0, 0.7, 0}"
        elsif iCurve = 4
            Colour: "{0.9, 0.6, 0}"
        else
            Colour: "{0.9, 0, 0}"
        endif
        
        Line width: 2
        
        lowBound = currentCutoff - (filter_smoothing / 2)
        highBound = currentCutoff + (filter_smoothing / 2)
        if lowBound < minFreqDisplay
            lowBound = minFreqDisplay
        endif
        if highBound > maxFreqDisplay
            highBound = maxFreqDisplay
        endif
        
        numFreqPoints = 200
        for iFreq from 1 to numFreqPoints - 1
            f1 = minFreqDisplay + (iFreq - 1) * (maxFreqDisplay - minFreqDisplay) / numFreqPoints
            f2 = minFreqDisplay + iFreq * (maxFreqDisplay - minFreqDisplay) / numFreqPoints
            
            if f1 < lowBound
                gain1 = 1
            elsif f1 > highBound
                gain1 = 0
            else
                gain1 = 0.5 * (1 + cos(pi * (f1 - lowBound) / (highBound - lowBound)))
            endif
            
            if resonance > 0
                gain1 = gain1 * (1 + resonance * exp(-((f1 - currentCutoff) / resonance_bandwidth)^2))
            endif
            
            if f2 < lowBound
                gain2 = 1
            elsif f2 > highBound
                gain2 = 0
            else
                gain2 = 0.5 * (1 + cos(pi * (f2 - lowBound) / (highBound - lowBound)))
            endif
            
            if resonance > 0
                gain2 = gain2 * (1 + resonance * exp(-((f2 - currentCutoff) / resonance_bandwidth)^2))
            endif
            
            Draw line: f1, gain1, f2, gain2
        endfor
    endfor
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Gain"
    Text top: "no", "##Filter Response## (blue=0%, cyan=25%, green=50%, orange=75%, red=100%)"
    
    Marks bottom every: 1, freqTickInterval, "yes", "yes", "no"
    Marks left every: 1, gainTickInterval, "yes", "yes", "no"
endproc

# ============================================================
# Procedure: Process single channel with adaptive LPF
# ============================================================
procedure processChannel: .inputSound, .outputName$
    selectObject: .inputSound
    
    Create Sound from formula: .outputName$, 1, 0, duration, sampleRate, "0"
    .outputSound = selected("Sound")
    
    for iFrame from 1 to numFrames
        frameStart = (iFrame - 1) * hopDuration
        frameEnd = frameStart + frame_duration
        
        if frameEnd > duration
            frameEnd = duration
        endif
        
        frameMid = (frameStart + frameEnd) / 2
        
        progress = frameMid / duration
        if progress > 1
            progress = 1
        endif
        currentCutoff = start_cutoff_frequency + (end_cutoff_frequency - start_cutoff_frequency) * progress
        
        selectObject: .inputSound
        .frameSound = Extract part: frameStart, frameEnd, "Hanning", 1, "no"
        
        selectObject: .frameSound
        actualFrameDur = Get total duration
        
        To Spectrum: "yes"
        .frameSpectrum = selected("Spectrum")
        
        lowBound = currentCutoff - (filter_smoothing / 2)
        highBound = currentCutoff + (filter_smoothing / 2)
        if lowBound < 0
            lowBound = 0
        endif
        if highBound > nyquist
            highBound = nyquist
        endif
        
        selectObject: .frameSpectrum
        if resonance > 0
            Formula: "if x > 'highBound' then 0 else if x < 'lowBound' then self * (1 + 'resonance' * exp(-((x - 'currentCutoff')/'resonance_bandwidth')^2)) else self * (1 + 'resonance' * exp(-((x - 'currentCutoff')/'resonance_bandwidth')^2)) * 0.5 * (1 + cos(pi * (x - 'lowBound') / ('highBound' - 'lowBound'))) endif endif"
        else
            Formula: "if x < 'lowBound' then self else if x > 'highBound' then 0 else self * 0.5 * (1 + cos(pi * (x - 'lowBound') / ('highBound' - 'lowBound'))) endif endif"
        endif
        
        To Sound
        .filteredFrame = selected("Sound")
        Rename: tempFrameName$
        
        overlapEnd = frameStart + actualFrameDur
        if overlapEnd > duration
            overlapEnd = duration
        endif
        
        selectObject: .outputSound
        .outputPart = Extract part: frameStart, overlapEnd, "rectangular", 1, "no"
        
        Formula: "self + Sound_'tempFrameName$'(x)"
        Rename: tempSumName$
        
        selectObject: .outputSound
        Formula: "if x >= 'frameStart' and x < 'overlapEnd' then Sound_'tempSumName$'(x - 'frameStart') else self endif"
        
        removeObject: .frameSound, .frameSpectrum, .filteredFrame
        selectObject: "Sound " + tempSumName$
        Remove
    endfor
    
    selectObject: .outputSound
endproc

# ============================================================
# Draw visualization (before processing)
# ============================================================
if draw_filter_response
    @drawFilterVisualization
endif

# ============================================================
# Main processing: Handle mono or stereo
# ============================================================
if numChannels = 1
    selectObject: sound
    inputMono = Copy: "input_mono_" + uniqueID$
    @processChannel: inputMono, "output_mono_" + uniqueID$
    outputMono = selected("Sound")
    
    selectObject: outputMono
    Scale peak: scale_peak
    Rename: originalName$ + "_adaptive_LPF"
    finalOutput = selected("Sound")
    
    removeObject: inputMono

else
    selectObject: sound
    Extract one channel: 1
    inputLeft = selected("Sound")
    Rename: "input_L_" + uniqueID$
    
    selectObject: sound
    Extract one channel: 2
    inputRight = selected("Sound")
    Rename: "input_R_" + uniqueID$
    
    @processChannel: inputLeft, "output_L_" + uniqueID$
    outputLeft = selected("Sound")
    
    @processChannel: inputRight, "output_R_" + uniqueID$
    outputRight = selected("Sound")
    
    selectObject: outputLeft, outputRight
    Combine to stereo
    finalOutput = selected("Sound")
    
    Scale peak: scale_peak
    Rename: originalName$ + "_adaptive_LPF"
    
    removeObject: inputLeft, inputRight, outputLeft, outputRight
endif

# ============================================================
# Select final output
# ============================================================
selectObject: finalOutput

# ============================================================
# Play if requested
# ============================================================
if play_after_processing
    Play
endif

# ============================================================
# Report completion
# ============================================================
writeInfoLine: "Adaptive Low-Pass Filter completed."
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Output: ", originalName$, "_adaptive_LPF"
appendInfoLine: "Channels: ", numChannels, if numChannels > 1 then " (true stereo)" else "" fi
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Cutoff: ", fixed$(start_cutoff_frequency, 0), " -> ", fixed$(end_cutoff_frequency, 0), " Hz"
appendInfoLine: "Resonance: ", fixed$(resonance, 2)
appendInfoLine: "Frames: ", numFrames
if draw_filter_response
    appendInfoLine: ""
    appendInfoLine: "Visualization in Picture window."
endif