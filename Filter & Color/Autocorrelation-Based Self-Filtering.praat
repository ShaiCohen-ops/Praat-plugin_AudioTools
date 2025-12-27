# ============================================================
# Praat AudioTools - Autocorrelation-Based Self-Filtering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-varying self-convolution using autocorrelation-derived impulse responses.
#   Each frame is convolved with its own autocorrelation function, creating
#   self-reinforcing resonances based on the signal's inherent periodicities.
#   This produces effects ranging from metallic coloration to ambient resonance.
#
# Technical approach:
#   - Divides sound into overlapping Hann-windowed frames
#   - Computes autocorrelation of each frame
#   - Extracts center portion as impulse response (IR)
#   - Convolves frame with its own IR
#   - Reconstructs via overlap-add synthesis
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

form Autocorrelation-Based Self-Filtering
    comment Self-convolution using autocorrelation-derived impulse responses.
    optionmenu Preset: 1
        option Default
        option Tight/Metallic
        option Medium/Resonant
        option Loose/Ambient
        option Extreme Resonance
        option Subtle Enhancement
        option Custom
    comment === Processing parameters ===
    positive window_duration 0.1
    comment (analysis window in seconds)
    positive max_lag 0.02
    comment (IR length in seconds - larger = more reverberant)
    comment === Effect intensity ===
    real dry_wet_mix 0.7
    comment (0 = dry, 1 = full effect)
    comment === Output options ===
    positive scale_peak 0.95
    boolean play_after_processing 1
    boolean draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Tight/Metallic"
    window_duration = 0.05
    max_lag = 0.008
    dry_wet_mix = 0.8
elif preset$ = "Medium/Resonant"
    window_duration = 0.1
    max_lag = 0.02
    dry_wet_mix = 0.7
elif preset$ = "Loose/Ambient"
    window_duration = 0.2
    max_lag = 0.05
    dry_wet_mix = 0.6
elif preset$ = "Extreme Resonance"
    window_duration = 0.15
    max_lag = 0.08
    dry_wet_mix = 0.9
elif preset$ = "Subtle Enhancement"
    window_duration = 0.08
    max_lag = 0.015
    dry_wet_mix = 0.4
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

# Validate parameters
if window_duration > duration / 2
    window_duration = duration / 2
endif

if max_lag > window_duration / 2
    max_lag = window_duration / 2
endif

# ============================================================
# Processing parameters
# ============================================================
hopDuration = window_duration / 2
numFrames = floor((duration - window_duration) / hopDuration) + 1
if numFrames < 1
    numFrames = 1
endif

# Generate unique ID for temp objects
uniqueID$ = string$(randomInteger(10000, 99999))
tempFrameName$ = "tmp_frame_" + uniqueID$
tempConvName$ = "tmp_conv_" + uniqueID$

# Variables for visualization (store one example IR)
exampleIR = 0
exampleIRduration = 0
captureExampleIR = 1

# ============================================================
# Procedure: Draw visualization
# ============================================================
procedure drawVisualization
    Erase all
    
    # Smart tick intervals
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
    # PANEL 1: Processing diagram (top)
    # ========================================================
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.5, 5.8, 0.4, 2.7
    
    Axes: 0, duration, 0, 1
    
    # Draw window positions
    Colour: "{0.85, 0.92, 1}"
    for iFrame from 1 to numFrames
        frameStart = (iFrame - 1) * hopDuration
        frameEnd = frameStart + window_duration
        if frameEnd > duration
            frameEnd = duration
        endif
        
        # Alternate shading for overlapping windows
        if iFrame mod 2 = 1
            Paint rectangle: "{0.85, 0.92, 1}", frameStart, frameEnd, 0.1, 0.9
        else
            Paint rectangle: "{0.92, 0.85, 1}", frameStart, frameEnd, 0.1, 0.9
        endif
    endfor
    
    # Draw frame boundaries
    Colour: "{0.4, 0.4, 0.8}"
    Line width: 1
    for iFrame from 1 to numFrames
        frameStart = (iFrame - 1) * hopDuration
        frameEnd = frameStart + window_duration
        if frameEnd > duration
            frameEnd = duration
        endif
        Dotted line
        Draw line: frameStart, 0.1, frameStart, 0.9
        Solid line
    endfor
    
    # Draw hop indicators
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    for iFrame from 1 to min(numFrames, 20)
        frameStart = (iFrame - 1) * hopDuration
        frameMid = frameStart + window_duration / 2
        if frameMid < duration
            Draw line: frameMid - 0.01 * duration, 0.5, frameMid + 0.01 * duration, 0.5
            Draw line: frameMid, 0.45, frameMid, 0.55
        endif
    endfor
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", ""
    Text top: "no", "##Analysis Windows## (50% overlap) - " + originalName$
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    # Add info text
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.02, "Left", 0.15, "Half", "Frames: " + string$(numFrames)
    Text: 0.25, "Left", 0.15, "Half", "Window: " + fixed$(window_duration * 1000, 0) + " ms"
    Text: 0.5, "Left", 0.15, "Half", "Hop: " + fixed$(hopDuration * 1000, 0) + " ms"
    Text: 0.75, "Left", 0.15, "Half", "IR lag: " + fixed$(max_lag * 1000, 1) + " ms"
    Font size: 12
    
    # ========================================================
    # PANEL 2: Example autocorrelation IR (bottom)
    # ========================================================
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.5, 5.8, 3.4, 5.7
    
    if exampleIR <> 0
        selectObject: exampleIR
        irSamples = Get number of samples
        irMax = Get maximum: 0, 0, "None"
        irMin = Get minimum: 0, 0, "None"
        irAbsMax = max(abs(irMax), abs(irMin))
        
        if irAbsMax = 0
            irAbsMax = 1
        endif
        
        yMax = irAbsMax * 1.1
        yMin = -yMax * 0.3
        
        Axes: 0, exampleIRduration * 1000, yMin, yMax
        
        # Draw zero line
        Colour: "{0.7, 0.7, 0.7}"
        Dotted line
        Draw line: 0, 0, exampleIRduration * 1000, 0
        Solid line
        
        # Draw IR waveform
        Colour: "{0.2, 0.5, 0.2}"
        Line width: 2
        
        numDrawPoints = min(irSamples, 500)
        for iPoint from 1 to numDrawPoints - 1
            sample1 = floor((iPoint - 1) * irSamples / numDrawPoints) + 1
            sample2 = floor(iPoint * irSamples / numDrawPoints) + 1
            
            if sample1 > irSamples
                sample1 = irSamples
            endif
            if sample2 > irSamples
                sample2 = irSamples
            endif
            
            selectObject: exampleIR
            val1 = Get value at sample number: 1, sample1
            val2 = Get value at sample number: 1, sample2
            
            t1 = (sample1 - 1) / sampleRate * 1000
            t2 = (sample2 - 1) / sampleRate * 1000
            
            Draw line: t1, val1, t2, val2
        endfor
        
        Line width: 1
        Black
        
        Draw inner box
        Text bottom: "yes", "Lag (ms)"
        Text left: "yes", "Amplitude"
        Text top: "no", "##Example Autocorrelation IR## (from middle frame)"
        
        # Smart tick intervals for IR
        if exampleIRduration * 1000 > 50
            irTickInterval = 20
        elsif exampleIRduration * 1000 > 20
            irTickInterval = 10
        else
            irTickInterval = 5
        endif
        
        Marks bottom every: 1, irTickInterval, "yes", "yes", "no"
        Marks left every: 1, irAbsMax / 2, "yes", "yes", "no"
    else
        Axes: 0, 1, 0, 1
        Text: 0.5, "Centre", 0.5, "Half", "(IR visualization will appear after processing)"
    endif
endproc

# ============================================================
# Procedure: Process single channel
# ============================================================
procedure processChannel: .inputSound, .outputName$
    selectObject: .inputSound
    .inputDuration = Get total duration
    
    # Create output sound (initially silent)
    Create Sound from formula: .outputName$, 1, 0, .inputDuration, sampleRate, "0"
    .outputSound = selected("Sound")
    
    # Also keep a copy of input for dry/wet mix
    selectObject: .inputSound
    .drySound = Copy: "dry_temp_" + uniqueID$
    
    for iFrame from 1 to numFrames
        frameStart = (iFrame - 1) * hopDuration
        frameEnd = frameStart + window_duration
        
        if frameEnd > .inputDuration
            frameEnd = .inputDuration
        endif
        
        actualFrameDur = frameEnd - frameStart
        
        # Skip if too short
        if actualFrameDur < 0.02
            # Skip
        else
            # Extract frame with Hann window
            selectObject: .inputSound
            .frameSound = Extract part: frameStart, frameEnd, "Hanning", 1, "no"
            
            # Compute autocorrelation
            selectObject: .frameSound
            Autocorrelate: "sum", "zero"
            .acSound = selected("Sound")
            
            # Get autocorrelation center
            selectObject: .acSound
            acDur = Get total duration
            acCenter = acDur / 2
            
            # Extract IR from center (±maxLag)
            irStart = acCenter - max_lag
            irEnd = acCenter + max_lag
            if irStart < 0
                irStart = 0
            endif
            if irEnd > acDur
                irEnd = acDur
            endif
            
            selectObject: .acSound
            Extract part: irStart, irEnd, "Hanning", 1, "no"
            .irSound = selected("Sound")
            
            # Normalize IR
            selectObject: .irSound
            irMax = Get maximum: 0, 0, "None"
            if irMax > 0
                Formula: "self / 'irMax'"
            endif
            
            # Store example IR for visualization (middle frame, first channel only)
            if iFrame = floor(numFrames / 2) + 1 and captureExampleIR = 1
                selectObject: .irSound
                exampleIR = Copy: "example_IR_" + uniqueID$
                exampleIRduration = Get total duration
                captureExampleIR = 0
            endif
            
            # Convolve frame with its own IR
            selectObject: .frameSound, .irSound
            Convolve: "sum", "zero"
            .convSound = selected("Sound")
            
            # Normalize convolution result
            selectObject: .convSound
            convMax = Get maximum: 0, 0, "None"
            convMin = Get minimum: 0, 0, "None"
            convAbsMax = max(abs(convMax), abs(convMin))
            if convAbsMax > 0
                Formula: "self / 'convAbsMax' * 0.7"
            endif
            
            # Extract center portion (same length as original frame)
            selectObject: .convSound
            convDur = Get total duration
            convCenter = convDur / 2
            
            extractStart = convCenter - actualFrameDur / 2
            extractEnd = convCenter + actualFrameDur / 2
            
            Extract part: extractStart, extractEnd, "rectangular", 1, "no"
            .trimmedConv = selected("Sound")
            Rename: tempConvName$
            
            # Overlap-add to output
            selectObject: .outputSound
            Formula: "if x >= 'frameStart' and x < 'frameStart' + 'actualFrameDur' then self + Sound_'tempConvName$'(x - 'frameStart') else self endif"
            
            # Cleanup
            removeObject: .frameSound, .acSound, .irSound, .convSound, .trimmedConv
        endif
    endfor
    
    # Apply dry/wet mix
    selectObject: .outputSound
    
    # Normalize wet signal first
    wetMax = Get maximum: 0, 0, "None"
    wetMin = Get minimum: 0, 0, "None"
    wetAbsMax = max(abs(wetMax), abs(wetMin))
    if wetAbsMax > 0
        Formula: "self / 'wetAbsMax'"
    endif
    
    # Mix with dry
    selectObject: .drySound
    Rename: "dry_mix_temp"
    
    selectObject: .outputSound
    Formula: "(1 - 'dry_wet_mix') * Sound_dry_mix_temp(x) + 'dry_wet_mix' * self"
    
    # Cleanup dry copy
    selectObject: "Sound dry_mix_temp"
    Remove
    
    selectObject: .outputSound
endproc

# ============================================================
# Main processing: Handle mono or stereo
# ============================================================
if numChannels = 1
    # Mono processing
    selectObject: sound
    inputMono = Copy: "input_mono_" + uniqueID$
    @processChannel: inputMono, "output_mono_" + uniqueID$
    outputMono = selected("Sound")
    
    selectObject: outputMono
    Scale peak: scale_peak
    Rename: originalName$ + "_autocorr"
    finalOutput = selected("Sound")
    
    removeObject: inputMono

else
    # True stereo processing
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
    
    # Combine to stereo
    selectObject: outputLeft, outputRight
    Combine to stereo
    finalOutput = selected("Sound")
    
    Scale peak: scale_peak
    Rename: originalName$ + "_autocorr"
    
    removeObject: inputLeft, inputRight, outputLeft, outputRight
endif

# ============================================================
# Draw visualization (after processing, so we have example IR)
# ============================================================
if draw_visualization
    @drawVisualization
endif

# ============================================================
# Cleanup example IR
# ============================================================
if exampleIR <> 0
    removeObject: exampleIR
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
writeInfoLine: "Autocorrelation-Based Self-Filtering completed."
appendInfoLine: "========================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Output: ", originalName$, "_autocorr"
appendInfoLine: "Channels: ", numChannels, if numChannels > 1 then " (true stereo)" else "" fi
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Preset: ", preset$
appendInfoLine: "  Window: ", fixed$(window_duration * 1000, 1), " ms"
appendInfoLine: "  Hop: ", fixed$(hopDuration * 1000, 1), " ms"
appendInfoLine: "  IR lag: ", fixed$(max_lag * 1000, 1), " ms"
appendInfoLine: "  Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: "  Frames: ", numFrames
appendInfoLine: ""
appendInfoLine: "Effect character:"
if max_lag < 0.01
    appendInfoLine: "  -> Tight/Metallic (short IR)"
elsif max_lag < 0.03
    appendInfoLine: "  -> Medium/Resonant"
elsif max_lag < 0.06
    appendInfoLine: "  -> Loose/Ambient"
else
    appendInfoLine: "  -> Extreme Resonance (long IR)"
endif
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Visualization in Picture window."
endif
appendInfoLine: ""
appendInfoLine: "========================================"