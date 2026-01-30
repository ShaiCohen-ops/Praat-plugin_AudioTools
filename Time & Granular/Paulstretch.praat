# ============================================================
# Praat AudioTools - Paulstretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Paulstretch - extreme time stretching with phase randomization.
#   Creates ethereal, frozen textures by randomizing spectral phases
#   while preserving magnitude. Optional stereo output with
#   independent phase randomization per channel.
#
# Changelog v0.2:
#   - Merged mono/stereo versions
#   - Added micro-fades to eliminate clicks
#   - Increased default overlap for smoother output
#   - Added visualization
#   - Fixed Formula interpolation
# ============================================================

form Paulstretch
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Stretch (2x)
        option Classic Paulstretch (8x)
        option Extreme Stretch (16x)
        option Quick Test (4x)
    
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

# === Apply Presets ===
if preset = 2
    # Subtle Stretch
    stretch_factor = 2.0
    window_size_s = 0.25
    overlap_percent = 75
    create_stereo = 1
    stereo_phase_offset = 0.2
    preset_name$ = "Subtle"
elsif preset = 3
    # Classic Paulstretch
    stretch_factor = 8.0
    window_size_s = 0.25
    overlap_percent = 75
    create_stereo = 1
    stereo_phase_offset = 0.3
    preset_name$ = "Classic"
elsif preset = 4
    # Extreme Stretch
    stretch_factor = 16.0
    window_size_s = 0.5
    overlap_percent = 80
    create_stereo = 1
    stereo_phase_offset = 0.4
    preset_name$ = "Extreme"
elsif preset = 5
    # Quick Test
    stretch_factor = 4.0
    window_size_s = 0.15
    overlap_percent = 75
    create_stereo = 0
    stereo_phase_offset = 0.0
    preset_name$ = "QuickTest"
else
    preset_name$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
inputDuration = Get total duration
numChannels = Get number of channels

# === Convert to Mono ===
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "mono_temp"
    sourceSound = selected("Sound")
endif

# === Calculate Parameters ===
windowSamples = round(window_size_s * sampleRate)
if windowSamples mod 2 = 1
    windowSamples += 1
endif

overlapFrac = overlap_percent / 100
hopOut = window_size_s * (1 - overlapFrac)
hopIn = hopOut / stretch_factor
outputDuration = inputDuration * stretch_factor
nFrames = ceiling(outputDuration / hopOut) + 1

# Micro-fade duration for click prevention
microFadeDur = 0.003

# === Info ===
writeInfoLine: "=== Paulstretch ==="
appendInfoLine: "Preset: ", preset_name$
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

# === Process Channel Procedure ===
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
            .frame = Extract part: .extractStart, .extractEnd, "Hanning", 1.0, "no"
            
            selectObject: .frame
            .durFrame = Get total duration
            
            # Pad if needed
            if abs(.durFrame - window_size_s) > 0.00001
                .padded = Create Sound from formula: "padded", 1, 0, window_size_s, sampleRate, "0"
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
            .spectrum = To Spectrum: "yes"
            selectObject: .spectrum
            .matComplex = To Matrix
            
            selectObject: .matComplex
            .ncols = Get number of columns
            .matID = .matComplex
            
            # Phase randomization with optional scaling
            Formula: "if col = 1 or col = .ncols then self else if row = 1 then sqrt(object[.matID, 1, col]^2 + object[.matID, 2, col]^2) * cos(randomUniform(-pi, pi) * .phaseScale) else sqrt(object[.matID, 1, col]^2 + object[.matID, 2, col]^2) * sin(randomUniform(-pi, pi) * .phaseScale) fi fi"
            
            # IFFT
            selectObject: .matComplex
            .spectrumMod = To Spectrum
            selectObject: .spectrumMod
            .processed = To Sound
            
            # Window (synthesis window)
            selectObject: .processed
            Multiply by window: "Hanning"
            
            # === CLICK FIX: Apply micro-fades ===
            .procDur = Get total duration
            .fadeDur = min(microFadeDur, .procDur * 0.05)
            if .fadeDur > 0.0005
                Fade in: 0, 0, .fadeDur, "yes"
                Fade out: 0, .procDur - .fadeDur, .fadeDur, "yes"
            endif
            
            # Overlap-add
            .tOut = .iframe * hopOut
            Shift times to: "start time", .tOut
            
            selectObject: .outputID
            .tAddEnd = .tOut + window_size_s
            .procID = .processed
            .sTOut$ = fixed$(.tOut, 6)
            .sTEnd$ = fixed$(.tAddEnd, 6)
            
            Formula: "if x >= " + .sTOut$ + " and x <= " + .sTEnd$ + " then self + object(" + string$(.procID) + ", x) else self fi"
            
            removeObject: .frame, .spectrum, .matComplex, .spectrumMod, .processed
        endif
    endfor
endproc

# === Process Left/Mono Channel ===
Create Sound from formula: "output_L", 1, 0, outputDuration + window_size_s, sampleRate, "0"
outputL = selected("Sound")

if create_stereo
    @processChannel: outputL, 1.0, "LEFT"
else
    @processChannel: outputL, 1.0, "MONO"
endif

# === Process Right Channel (if stereo) ===
if create_stereo
    appendInfoLine: ""
    
    Create Sound from formula: "output_R", 1, 0, outputDuration + window_size_s, sampleRate, "0"
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

# === Finalize ===
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

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 2, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Paulstretch: " + original_name$ + " (" + preset_name$ + " " + string$(stretch_factor) + "x)"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.4, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Stretched"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    selectObject: original
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Original (s)"
    
    # Result spectrogram
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    
    # Show first portion if very long
    selectObject: result
    resDur = Get total duration
    showDur = min(10, resDur)
    
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, showDur, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Stretched (s)"
    
    # Legend
    Select outer viewport: 2, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if create_stereo
        legendText$ = "Stretch: " + string$(stretch_factor) + "x | Window: " + fixed$(window_size_s * 1000, 0) + "ms | Overlap: " + string$(overlap_percent) + "% | Stereo offset: " + fixed$(stereo_phase_offset, 2)
    else
        legendText$ = "Stretch: " + string$(stretch_factor) + "x | Window: " + fixed$(window_size_s * 1000, 0) + "ms | Overlap: " + string$(overlap_percent) + "%"
    endif
    Text: 0.5, "centre", 0.5, "half", legendText$
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result