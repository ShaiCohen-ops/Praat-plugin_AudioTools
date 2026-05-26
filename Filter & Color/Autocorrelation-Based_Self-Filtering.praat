# ============================================================
# Praat AudioTools - Autocorrelation-Based_Self-Filtering.praat
# Version: 0.6 (2025) - Fixed IR centering (lag-0 at time 0, not acDur/2)
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Autocorrelation-Based Self-Filtering v0.5
    optionmenu Preset: 1
        option Manual
        option Tight/Metallic
        option Medium/Resonant
        option Loose/Ambient
        option Extreme Resonance
        option Subtle Enhancement
    comment === Processing ===
    positive Window_duration 0.15
    positive Max_lag 0.02
    real Dry_wet_mix 0.7
    comment === Output ===
    positive Scale_peak 0.95
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets (with longer windows to avoid clicks)
# ============================================================
if preset = 2
    # Tight/Metallic
    window_duration = 0.10
    max_lag = 0.008
    dry_wet_mix = 0.8
    presetName$ = "TightMetallic"
elsif preset = 3
    # Medium/Resonant
    window_duration = 0.15
    max_lag = 0.02
    dry_wet_mix = 0.7
    presetName$ = "MediumResonant"
elsif preset = 4
    # Loose/Ambient
    window_duration = 0.25
    max_lag = 0.05
    dry_wet_mix = 0.6
    presetName$ = "LooseAmbient"
elsif preset = 5
    # Extreme Resonance
    window_duration = 0.20
    max_lag = 0.08
    dry_wet_mix = 0.9
    presetName$ = "ExtremeResonance"
elsif preset = 6
    # Subtle Enhancement
    window_duration = 0.12
    max_lag = 0.015
    dry_wet_mix = 0.4
    presetName$ = "SubtleEnhancement"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
clearinfo
writeInfoLine: "=== Autocorrelation Self-Filtering v0.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# MINIMUM WINDOW to avoid clicks (at least 100ms)
minWindow = 0.10
if window_duration < minWindow
    appendInfoLine: "Note: Window increased from ", fixed$(window_duration * 1000, 0), " ms to ", fixed$(minWindow * 1000, 0), " ms to avoid clicks"
    window_duration = minWindow
endif

if window_duration > duration / 2
    window_duration = duration / 2
endif
if max_lag > window_duration / 2
    max_lag = window_duration / 2
endif

hopDuration = window_duration / 2
numFrames = floor((duration - window_duration) / hopDuration) + 1
if numFrames < 1
    numFrames = 1
endif

appendInfoLine: "Window: ", fixed$(window_duration * 1000, 0), " ms"
appendInfoLine: "IR lag: ", fixed$(max_lag * 1000, 1), " ms"
appendInfoLine: "Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: "Frames: ", numFrames
appendInfoLine: ""

# For visualization
exampleIR = 0
exampleIRduration = 0
capturedIR = 0

# ============================================================
# Process single channel
# ============================================================
procedure processChannel: .inputSound, .outputName$
    selectObject: .inputSound
    .inputDuration = Get total duration
    .inputId$ = string$(.inputSound)
    
    # Create output buffer
    Create Sound from formula: .outputName$, 1, 0, .inputDuration, sampleRate, "0"
    .outputSound = selected("Sound")
    .outputId$ = string$(.outputSound)
    
    for iFrame from 1 to numFrames
        frameStart = (iFrame - 1) * hopDuration
        frameEnd = frameStart + window_duration
        
        if frameEnd > .inputDuration
            frameEnd = .inputDuration
        endif
        
        actualFrameDur = frameEnd - frameStart
        
        if actualFrameDur >= 0.02
            # Extract frame with Hann window
            selectObject: .inputSound
            .frameSound = Extract part: frameStart, frameEnd, "Hanning", 1, "no"
            .frameId$ = string$(.frameSound)
            
            # Compute autocorrelation
            selectObject: .frameSound
            Autocorrelate: "sum", "zero"
            .acSound = selected("Sound")
            
            # Extract IR from center
            selectObject: .acSound
            acStart = Get start time
            acEnd = Get end time
            acCenter = (acStart + acEnd) / 2

            irStart = acCenter - max_lag
            irEnd = acCenter + max_lag
            if irStart < acStart
                irStart = acStart
            endif
            if irEnd > acEnd
                irEnd = acEnd
            endif
            
            selectObject: .acSound
            Extract part: irStart, irEnd, "Hanning", 1, "no"
            .irSound = selected("Sound")
            
            # Normalize IR
            selectObject: .irSound
            irMaxVal = Get maximum: 0, 0, "None"
            if irMaxVal > 0
                irMaxVal$ = string$(irMaxVal)
                Formula: "self / " + irMaxVal$
            endif
            
            # Capture example IR (middle frame)
            if iFrame = floor(numFrames / 2) + 1 and capturedIR = 0
                selectObject: .irSound
                exampleIR = Copy: "example_IR"
                exampleIRduration = Get total duration
                capturedIR = 1
            endif
            
            # Convolve frame with its IR
            selectObject: .frameSound
            plusObject: .irSound
            Convolve: "sum", "zero"
            .convSound = selected("Sound")
            
            # Extract center portion
            selectObject: .convSound
            convDur = Get total duration
            convCenter = convDur / 2
            
            extractStart = convCenter - actualFrameDur / 2
            extractEnd = convCenter + actualFrameDur / 2
            
            if extractStart < 0
                extractStart = 0
            endif
            if extractEnd > convDur
                extractEnd = convDur
            endif
            
            Extract part: extractStart, extractEnd, "rectangular", 1, "no"
            .trimmedConv = selected("Sound")
            
            # Normalize frame
            selectObject: .trimmedConv
            frameMax = Get maximum: 0, 0, "None"
            frameMin = Get minimum: 0, 0, "None"
            frameAbsMax = max(abs(frameMax), abs(frameMin))
            if frameAbsMax > 0.001
                frameAbsMax$ = string$(frameAbsMax)
                Formula: "self / " + frameAbsMax$ + " * 0.7"
            endif
            
            .trimmedId$ = string$(.trimmedConv)
            
            # Add to output buffer
            frameStart$ = string$(frameStart)
            actualFrameDur$ = string$(actualFrameDur)
            
            selectObject: .outputSound
            Formula: "if x >= " + frameStart$ + " and x < " + frameStart$ + " + " + actualFrameDur$ + " then self + Object_" + .trimmedId$ + "(x - " + frameStart$ + ") else self endif"
            
            # Cleanup
            removeObject: .frameSound, .acSound, .irSound, .convSound, .trimmedConv
        endif
        
        if iFrame mod 10 = 0
            appendInfo: "."
        endif
    endfor
    
    # Normalize wet signal
    selectObject: .outputSound
    wetMax = Get maximum: 0, 0, "None"
    wetMin = Get minimum: 0, 0, "None"
    wetAbsMax = max(abs(wetMax), abs(wetMin))
    if wetAbsMax > 0
        wetAbsMax$ = string$(wetAbsMax)
        Formula: "self / " + wetAbsMax$
    endif
    
    # Mix with dry
    dryMix$ = string$(1 - dry_wet_mix)
    wetMix$ = string$(dry_wet_mix)
    
    selectObject: .outputSound
    Formula: dryMix$ + " * Object_" + .inputId$ + "(x) + " + wetMix$ + " * self"
    
    selectObject: .outputSound
endproc

# ============================================================
# Visualization
# ============================================================
procedure drawVisualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Autocorrelation Self-Filtering: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.75, 1.7
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.05, 3.0
    selectObject: finalOutput
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Example IR
    if exampleIR <> 0
        Select outer viewport: 0, 4, 3.3, 5.0
        Select inner viewport: 0.6, 3.6, 3.5, 4.9
        
        selectObject: exampleIR
        irMax = Get maximum: 0, 0, "None"
        irMin = Get minimum: 0, 0, "None"
        irAbsMax = max(abs(irMax), abs(irMin))
        if irAbsMax = 0
            irAbsMax = 1
        endif
        
        Colour: "{0.2, 0.6, 0.3}"
        Draw: 0, 0, -irAbsMax * 1.1, irAbsMax * 1.1, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "IR"
        Text bottom: "yes", "Lag (s)"
        Text top: "no", "Example Autocorrelation IR"
    endif
    
    # Stats
    Select outer viewport: 4, 8, 3.3, 5.0
    Select inner viewport: 4.4, 7.6, 3.5, 4.9
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.1, "left", 0.85, "half", "Window: " + fixed$(window_duration * 1000, 0) + " ms"
    Text: 0.1, "left", 0.65, "half", "IR lag: " + fixed$(max_lag * 1000, 1) + " ms"
    Text: 0.1, "left", 0.45, "half", "Dry/wet: " + fixed$(dry_wet_mix * 100, 0) + "%"
    Text: 0.1, "left", 0.25, "half", "Frames: " + string$(numFrames)
    
    Colour: "Black"
    Draw inner box
    Font size: 10
endproc

# ============================================================
# Main processing
# ============================================================
appendInfoLine: "Processing"

if numChannels = 1
    selectObject: sound
    inputMono = Copy: "input_mono"
    @processChannel: inputMono, "output_mono"
    outputMono = selected("Sound")
    
    selectObject: outputMono
    Scale peak: scale_peak
    Rename: originalName$ + "_autocorr_" + presetName$
    finalOutput = selected("Sound")
    
    removeObject: inputMono

else
    selectObject: sound
    Extract one channel: 1
    inputLeft = selected("Sound")
    
    selectObject: sound
    Extract one channel: 2
    inputRight = selected("Sound")
    
    appendInfo: "L"
    @processChannel: inputLeft, "output_L"
    outputLeft = selected("Sound")
    
    appendInfoLine: ""
    appendInfo: "R"
    @processChannel: inputRight, "output_R"
    outputRight = selected("Sound")
    
    selectObject: outputLeft
    plusObject: outputRight
    Combine to stereo
    finalOutput = selected("Sound")
    
    Scale peak: scale_peak
    Rename: originalName$ + "_autocorr_" + presetName$
    
    removeObject: inputLeft, inputRight, outputLeft, outputRight
endif

appendInfoLine: " done"

# Visualization
if draw_visualization
    @drawVisualization
endif

# Cleanup
if exampleIR <> 0
    removeObject: exampleIR
endif

# Output
selectObject: sound
plusObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput