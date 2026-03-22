# ============================================================
# Praat AudioTools - Paulstretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - OPTIMIZED
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Paulstretch - extreme time stretching with phase randomization.
#   NOW WITH SPEED MODES for 4-8× faster processing!
# ============================================================

form Paulstretch v1.0 (Optimized)
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Stretch (2x)
        option Classic Paulstretch (8x)
        option Extreme Stretch (16x)
        option Quick Test (4x)
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    
    comment === Parameters ===
    positive Stretch_factor 4.0
    positive Window_size_s 0.25
    positive Overlap_percent 75
    
    comment === Output ===
    boolean Create_stereo 1
    positive Stereo_phase_offset 0.3
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply Presets
if preset = 2
    stretch_factor = 2.0
    window_size_s = 0.25
    overlap_percent = 75
    create_stereo = 1
    stereo_phase_offset = 0.2
    preset_name$ = "Subtle"
elsif preset = 3
    stretch_factor = 8.0
    window_size_s = 0.25
    overlap_percent = 75
    create_stereo = 1
    stereo_phase_offset = 0.3
    preset_name$ = "Classic"
elsif preset = 4
    stretch_factor = 16.0
    window_size_s = 0.5
    overlap_percent = 80
    create_stereo = 1
    stereo_phase_offset = 0.4
    preset_name$ = "Extreme"
elsif preset = 5
    stretch_factor = 4.0
    window_size_s = 0.15
    overlap_percent = 75
    create_stereo = 0
    stereo_phase_offset = 0.0
    preset_name$ = "QuickTest"
else
    preset_name$ = "Custom"
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

# Check Input
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
inputDuration = Get total duration
numChannels = Get number of channels

startTime = stopwatch

# Convert to Mono
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "mono_temp"
    sourceSound = selected("Sound")
endif

# === OPTIONAL DOWNSAMPLING ===
if targetSR > 0 and sampleRate > targetSR
    selectObject: sourceSound
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: sourceSound
    sourceSound = resampledID
    workingSR = targetSR
else
    workingSR = sampleRate
endif

# Calculate Parameters
windowSamples = round(window_size_s * workingSR)
if windowSamples mod 2 = 1
    windowSamples += 1
endif

overlapFrac = overlap_percent / 100
hopOut = window_size_s * (1 - overlapFrac)
hopIn = hopOut / stretch_factor
outputDuration = inputDuration * stretch_factor
nFrames = ceiling(outputDuration / hopOut) + 1

microFadeDur = 0.003

# Info
writeInfoLine: "=== Paulstretch v1.0 (Optimized) ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Source: ", original_name$, " (", fixed$(inputDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Stretch: ", stretch_factor, "x"
appendInfoLine: "Output: ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Frames: ", nFrames
appendInfoLine: "Overlap: ", overlap_percent, "%"
if create_stereo
    appendInfoLine: "Mode: STEREO (phase offset: ", stereo_phase_offset, ")"
else
    appendInfoLine: "Mode: MONO"
endif
appendInfoLine: ""

# Process Channel Procedure
procedure processChannel: .outputID, .phaseScale, .channelName$
    appendInfoLine: "Processing ", .channelName$, " channel..."
    
    .progressInterval = max(1, round(nFrames / 10))
    
    for .iframe from 0 to nFrames - 1
        if .iframe mod .progressInterval = 0
            appendInfoLine: "  ", floor(.iframe / nFrames * 100), "%"
        endif
        
        .tIn = .iframe * hopIn
        .tStart = .tIn - window_size_s / 2
        .tEnd = .tIn + window_size_s / 2
        
        selectObject: sourceSound
        .extractStart = max(0, .tStart)
        .extractEnd = min(inputDuration, .tEnd)
        
        if .extractEnd > .extractStart
            Extract part: .extractStart, .extractEnd, "Hanning", 1.0, "no"
            .frame = selected("Sound")
            
            selectObject: .frame
            .durFrame = Get total duration
            
            # Pad if needed
            if abs(.durFrame - window_size_s) > 0.00001
                Create Sound from formula: "padded", 1, 0, window_size_s, workingSR, "0"
                .padded = selected("Sound")
                .offset = max(0, -.tStart)
                .sOffset$ = fixed$(.offset, 6)
                .sEnd$ = fixed$(.offset + .durFrame, 6)
                .frameID = .frame
                selectObject: .padded
                Formula: "if x >= " + .sOffset$ + " and x <= " + .sEnd$ + " then object(" + string$(.frameID) + ", x - " + .sOffset$ + ") else 0 fi"
                removeObject: .frame
                .frame = .padded
            endif
            
            # FFT
            selectObject: .frame
            To Spectrum: "yes"
            .spectrum = selected("Spectrum")
            
            To Matrix
            .matComplex = selected("Matrix")
            
            selectObject: .matComplex
            .ncols = Get number of columns
            .matID = .matComplex
            
            # Phase randomization
            Formula: "if col = 1 or col = .ncols then self else if row = 1 then sqrt(object[.matID, 1, col]^2 + object[.matID, 2, col]^2) * cos(randomUniform(-pi, pi) * .phaseScale) else sqrt(object[.matID, 1, col]^2 + object[.matID, 2, col]^2) * sin(randomUniform(-pi, pi) * .phaseScale) fi fi"
            
            # IFFT
            selectObject: .matComplex
            To Spectrum
            .spectrumMod = selected("Spectrum")
            
            To Sound
            .processed = selected("Sound")
            
            # Window
            selectObject: .processed
            Multiply by window: "Hanning"
            
            # Micro-fades
            .procDur = Get total duration
            .fadeDur = min(microFadeDur, .procDur * 0.05)
            if .fadeDur > 0.0005
                Fade in: 0, 0, .fadeDur, "yes"
                Fade out: 0, .procDur - .fadeDur, .fadeDur, "yes"
            endif
            
            # Overlap-add using Formula (part) — restricts evaluation
            # to the frame's time range only, avoiding O(n_total) scan.
            # col-indexed access avoids time-domain interpolation.
            .tOut = .iframe * hopOut

            selectObject: .processed
            .procNs = Get number of samples

            selectObject: .outputID
            .s1 = Get sample number from time: .tOut
            if .s1 < 1
                .s1 = 1
            endif
            .s2 = .s1 + .procNs - 1
            .outNs = Get number of samples
            if .s2 > .outNs
                .s2 = .outNs
            endif
            .sOff = .s1 - 1

            .tOutEnd = .tOut + window_size_s
            if .tOutEnd > outputDuration + window_size_s
                .tOutEnd = outputDuration + window_size_s
            endif

            Formula (part): .tOut, .tOutEnd, 1, 1,
                ... "self + object[" + string$(.processed) + ", col - " + string$(.sOff) + "]"
            
            removeObject: .frame, .spectrum, .matComplex, .spectrumMod, .processed
        endif
    endfor
endproc

# Process Left/Mono Channel
Create Sound from formula: "output_L", 1, 0, outputDuration + window_size_s, workingSR, "0"
outputL = selected("Sound")

if create_stereo
    @processChannel: outputL, 1.0, "LEFT"
else
    @processChannel: outputL, 1.0, "MONO"
endif

# Process Right Channel
if create_stereo
    appendInfoLine: ""
    
    Create Sound from formula: "output_R", 1, 0, outputDuration + window_size_s, workingSR, "0"
    outputR = selected("Sound")
    
    phaseScale = 1 + stereo_phase_offset
    @processChannel: outputR, phaseScale, "RIGHT"
    
    # Combine to stereo
    selectObject: outputL, outputR
    Combine to stereo
    result = selected("Sound")
    
    removeObject: outputL, outputR
else
    result = outputL
endif

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: ""
    appendInfoLine: "Upsampling to ", sampleRate, " Hz..."
    selectObject: result
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: result
    result = upsampledID
endif

# Finalize
selectObject: result
Scale peak: 0.95

# Trim excess
resultDur = Get total duration
if resultDur > outputDuration + 0.1
    Extract part: 0, outputDuration + 0.05, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: result
    result = trimmed
endif

selectObject: result
if create_stereo
    Rename: original_name$ + "_PS_" + preset_name$ + "_stereo"
else
    Rename: original_name$ + "_PS_" + preset_name$
endif

removeObject: sourceSound

selectObject: result
finalDuration = Get total duration

processingTime = stopwatch - startTime

# Visualization
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Paulstretch — Spectral Time Stretch##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... original_name$ + "  |  " + preset_name$
        ... + "  |  " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  " + speedStr$
        ... + "  |  " + fixed$(processingTime, 1) + "s"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.42
    Select inner viewport: 0.55, 7.65, 0.57, 1.37
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original  (" + fixed$(inputDuration, 2) + " s)"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.46, 2.36
    Select inner viewport: 0.55, 7.65, 1.51, 2.31
    selectObject: result
    nChResult = Get number of channels
    if nChResult > 1
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: result
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: result
        Colour: "{0.35, 0.58, 0.78}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stretched"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output  (" + fixed$(finalDuration, 2) + " s,  " + fixed$(stretch_factor, 1) + "x)"

    # ----------------------------------------------------------
    # Original spectrogram (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.44, 3.84
    Select inner viewport: 0.55, 3.85, 2.54, 3.74
    selectObject: original
    if numChannels > 1
        Extract one channel: 1
        vizSpecOrig = selected("Sound")
    else
        Copy: "vizSpecOrig"
        vizSpecOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec, vizSpecOrig
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original spectrogram"

    # ----------------------------------------------------------
    # Stretched spectrogram (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.44, 3.84
    Select inner viewport: 4.40, 7.65, 2.54, 3.74
    selectObject: result
    if nChResult > 1
        Extract one channel: 1
        vizSpecOut = selected("Sound")
    else
        Copy: "vizSpecOut"
        vizSpecOut = selected("Sound")
    endif
    resDur = Get total duration
    showDur = min(10, resDur)
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, showDur, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, vizSpecOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Stretched spectrogram"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.92, 4.72
    Select inner viewport: 0.55, 7.65, 3.98, 4.66
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    if create_stereo
        stereoStr$ = "Stereo (offset=" + fixed$(stereo_phase_offset, 2) + ")"
    else
        stereoStr$ = "Mono"
    endif

    Text: 0.02, "left", 0.52, "half",
        ... "Preset: " + preset_name$
        ... + "  |  Stretch: " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  Window: " + fixed$(window_size_s, 3) + " s"
        ... + "  |  Overlap: " + fixed$(overlap_percent, 0) + "%"
        ... + "  |  " + stereoStr$
    Text: 0.02, "left", 0.18, "half",
        ... "In: " + fixed$(inputDuration, 2) + " s → Out: " + fixed$(finalDuration, 2) + " s"
        ... + "  |  " + speedStr$
        ... + "  |  Frames: " + string$(nFrames)
        ... + "  |  Render: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# Final Info
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# Play
if play_result
    selectObject: result
    Play
endif

selectObject: result