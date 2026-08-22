# ============================================================
# Praat AudioTools - Autocorrelation-Based_Self-Filtering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.3 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Description:
#   Self-filtering using time-varying frame autocorrelation kernels.
#   Implements normalized autocorrelation color tails, true dry/wet crossfade,
#   automatic RMS makeup gain matching, and Spatial Stereo Decorrelation.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Validation Error: Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Autocorrelation-Based Self-Filtering v1.3
    optionmenu Preset: 1
        option Manual
        option Tight/Metallic
        option Medium/Resonant
        option Loose/Ambient
        option Extreme Resonance
        option Subtle Enhancement
    comment === Processing Parameters ===
    positive Window_duration 0.15
    positive Max_lag 0.02
    positive Resonance_gain 1.15
    real Dry_wet_mix 0.55
    comment === Stereo Spatialization ===
    boolean Spatial_stereo_widening 1
    comment === Gain & Loudness Control ===
    boolean Match_RMS_to_input 1
    positive Max_makeup_gain_dB 6.0
    boolean Peak_normalize_output 0
    positive Scale_peak 0.95
    comment === Display & Playback ===
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Apply Presets
# ============================================================
if preset = 2
    # Tight/Metallic
    window_duration = 0.10
    max_lag = 0.008
    resonance_gain = 1.30
    dry_wet_mix = 0.55
    presetName$ = "TightMetallic"
elsif preset = 3
    # Medium/Resonant
    window_duration = 0.15
    max_lag = 0.020
    resonance_gain = 1.15
    dry_wet_mix = 0.55
    presetName$ = "MediumResonant"
elsif preset = 4
    # Loose/Ambient
    window_duration = 0.25
    max_lag = 0.050
    resonance_gain = 0.95
    dry_wet_mix = 0.50
    presetName$ = "LooseAmbient"
elsif preset = 5
    # Extreme Resonance
    window_duration = 0.20
    max_lag = 0.080
    resonance_gain = 2.20
    dry_wet_mix = 0.70
    presetName$ = "ExtremeResonance"
elsif preset = 6
    # Subtle Enhancement
    window_duration = 0.12
    max_lag = 0.015
    resonance_gain = 0.60
    dry_wet_mix = 0.40
    presetName$ = "SubtleEnhancement"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup & Parameter Validation
# ============================================================
clearinfo
writeInfoLine: "=== Autocorrelation Self-Filtering v1.3 (Stereo Spatialization) ==="
appendInfoLine: "Preset:          ", presetName$
appendInfoLine: "Input:           ", originalName$
appendInfoLine: ""

selectObject: sound
origXmin = Get start time
origXmax = Get end time
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
origRms = Get root-mean-square: 0, 0

# Sanity checks
if dry_wet_mix < 0.0 or dry_wet_mix > 1.0
    exitScript: "Validation Error: Dry/Wet mix must be between 0.0 and 1.0."
endif

if peak_normalize_output and scale_peak > 1.0
    exitScript: "Validation Error: Scale peak must be <= 1.0 to prevent clipping."
endif

minWindow = 0.04
if window_duration < minWindow
    appendInfoLine: "Note: Window increased from ", fixed$(window_duration * 1000, 0), " ms to ", fixed$(minWindow * 1000, 0), " ms for stability."
    window_duration = minWindow
endif

if duration < window_duration
    exitScript: "Validation Error: Input sound duration (", fixed$(duration, 3), "s) is shorter than window duration."
endif

if max_lag > window_duration / 2
    max_lag = window_duration / 2
    appendInfoLine: "Note: Max lag clamped to half window duration (", fixed$(max_lag * 1000, 1), " ms)."
endif

hopDuration = window_duration / 2
padTime = window_duration
numFrames = ceiling((duration + padTime) / hopDuration)

appendInfoLine: "Duration:        ", fixed$(duration, 3), " s"
appendInfoLine: "Window:          ", fixed$(window_duration * 1000, 0), " ms"
appendInfoLine: "Base Max Lag:    ", fixed$(max_lag * 1000, 1), " ms"
appendInfoLine: "Resonance Gain:  ", fixed$(resonance_gain, 2)
appendInfoLine: "Dry/Wet Mix:     ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: "Stereo Widening: ", if spatial_stereo_widening then "Enabled" else "Disabled" endif
appendInfoLine: "Input Channels:  ", numChannels
appendInfoLine: "Frames:          ", numFrames
appendInfoLine: ""

exampleIR = 0
capturedIR = 0

# ============================================================
# Procedure: Process Single Channel with Per-Channel Lag
# ============================================================
procedure processSingleChannel: .chanSound, .outChanName$, .lagVal
    selectObject: .chanSound
    .cDur = Get total duration
    .chanId$ = string$(.chanSound)
    
    # 1. Create Padded Work Copy
    .paddedSound = Create Sound from formula: "padded_input", 1, 0, .cDur + 2 * padTime, sampleRate, "0"
    Formula (part): padTime, padTime + .cDur, 1, 1, "Object_" + .chanId$ + "(x - padTime)"
    
    # 2. Create Accumulation Buffers
    .wetBuffer = Create Sound from formula: "wet_buffer", 1, 0, .cDur + 2 * padTime, sampleRate, "0"
    .normBuffer = Create Sound from formula: "norm_buffer", 1, 0, .cDur + 2 * padTime, sampleRate, "0"
    
    # 3. Process Overlapping Frames
    for iFrame from 1 to numFrames
        frameStart = (iFrame - 1) * hopDuration
        frameEnd = frameStart + window_duration
        
        # Extract frame slice
        selectObject: .paddedSound
        .frameSound = Extract part: frameStart, frameEnd, "Hanning", 1, "no"
        
        # Remove DC Offset per frame
        selectObject: .frameSound
        .frameMean = Get mean: 1, 0, 0
        Formula: "self - " + string$(.frameMean)
        
        # Compute Autocorrelation
        Autocorrelate: "sum", "zero"
        .acSound = selected("Sound")
        
        # Extract IR centered around zero-lag using .lagVal
        acStart = Get start time
        acEnd = Get end time
        acCenter = (acStart + acEnd) / 2
        
        irStart = acCenter - .lagVal
        irEnd = acCenter + .lagVal
        
        selectObject: .acSound
        .irSound = Extract part: irStart, irEnd, "Hanning", 1, "no"
        
        # --- SPECTRAL PEAK NORMALIZATION ---
        
        # A. Find exact discrete zero-lag sample index
        selectObject: .irSound
        .exactSample = Get sample number from time: .lagVal
        .zeroLagSample = round(.exactSample)
        
        # B. Zero out center sample to isolate pure color tail
        Formula: "if col = " + string$(.zeroLagSample) + " then 0 else self endif"
        
        # C. Compute Spectral Peak magnitude max_f |H_colour(f)|
        selectObject: .irSound
        .specObj = To Spectrum: "yes"
        .specMat = To Matrix
        
        Formula: "if row = 1 then sqrt(self[1, col]^2 + self[2, col]^2) else 0 endif"
        
        .specSound = To Sound
        .specPeak = Get maximum: 0, 0, "None"
        removeObject: .specObj, .specMat, .specSound
        
        # D. Normalize color tail by (Spectral Peak * sampleRate)
        selectObject: .irSound
        .normDivisor = .specPeak * sampleRate
        if .normDivisor > 1e-9
            Formula: "self / " + string$(.normDivisor)
        endif
        
        # E. Scale Color Tail by Resonance Gain
        Formula: string$(resonance_gain) + " * self"
        
        # Capture middle frame IR for visualization
        if iFrame = floor(numFrames / 2) + 1 and capturedIR = 0
            selectObject: .irSound
            exampleIR = Copy: "example_IR"
            Shift times by: -.lagVal
            capturedIR = 1
        endif
        
        # Convolve frame with pure Normalized Color IR
        selectObject: .frameSound
        plusObject: .irSound
        Convolve: "sum", "zero"
        .convSound = selected("Sound")
        
        # Trim convolution output to exact window duration
        convDur = Get total duration
        convCenter = convDur / 2
        extStart = convCenter - window_duration / 2
        extEnd = convCenter + window_duration / 2
        
        selectObject: .convSound
        .trimmedConv = Extract part: extStart, extEnd, "Hanning", 1, "no"
        
        # Accumulate into buffers using LOCALIZED Formula (part)
        .trimmedId$ = string$(.trimmedConv)
        selectObject: .wetBuffer
        Formula (part): frameStart, frameEnd, 1, 1, "self + Object_" + .trimmedId$ + "(x - " + string$(frameStart) + ")"
        
        selectObject: .normBuffer
        Formula (part): frameStart, frameEnd, 1, 1, "self + (0.5 * (1 - cos(2 * pi * (x - " + string$(frameStart) + ") / " + string$(window_duration) + ")))^2"
        
        # Cleanup frame objects
        removeObject: .frameSound, .acSound, .irSound, .convSound, .trimmedConv
    endfor
    
    # 4. Normalize Wet Buffer by Window Weights
    selectObject: .wetBuffer
    .normId$ = string$(.normBuffer)
    Formula: "if Object_" + .normId$ + "(x) > 1e-6 then self / Object_" + .normId$ + "(x) else 0 endif"
    
    # 5. Extract exact unpadded duration
    selectObject: .wetBuffer
    .wetTrimmed = Extract part: padTime, padTime + .cDur, "rectangular", 1, "no"
    
    # 6. Apply True Dry/Wet Linear Crossfade
    .wetTrimmedId$ = string$(.wetTrimmed)
    
    .finalChan = Create Sound from formula: .outChanName$, 1, 0, .cDur, sampleRate, 
        ... string$(1.0 - dry_wet_mix) + " * Object_" + .chanId$ + "(x) + " + string$(dry_wet_mix) + " * Object_" + .wetTrimmedId$ + "(x)"
    
    # Cleanup channel working buffers
    removeObject: .paddedSound, .wetBuffer, .normBuffer, .wetTrimmed
endproc

# ============================================================
# Main Processing Logic (Stereo Spatialization Routing)
# ============================================================
appendInfoLine: "Processing audio..."

selectObject: sound
workCopy = Copy: "work_copy"
Shift times to: "start time", 0

if numChannels = 1 and spatial_stereo_widening
    # --- MONO TO STEREO SPATIAL WIDENING ---
    selectObject: workCopy
    chanInput[1] = Extract one channel: 1
    chanInput[2] = Copy: "chan_2_copy"
    
    # Channel 1 (Left): Standard Lag
    lagCh1 = max_lag
    # Channel 2 (Right): Decorrelated Lag (+12%)
    lagCh2 = min(window_duration / 2, max_lag * 1.12)
    
    @processSingleChannel: chanInput[1], "proc_chan_1", lagCh1
    chanOutput[1] = selected("Sound")
    
    @processSingleChannel: chanInput[2], "proc_chan_2", lagCh2
    chanOutput[2] = selected("Sound")
    
    outChannels = 2

elsif numChannels = 2 and spatial_stereo_widening
    # --- STEREO INPUT WIDENING ---
    for iChan from 1 to 2
        selectObject: workCopy
        Extract one channel: iChan
        chanInput[iChan] = selected("Sound")
    endfor
    
    lagCh1 = max_lag
    lagCh2 = min(window_duration / 2, max_lag * 1.08)
    
    @processSingleChannel: chanInput[1], "proc_chan_1", lagCh1
    chanOutput[1] = selected("Sound")
    
    @processSingleChannel: chanInput[2], "proc_chan_2", lagCh2
    chanOutput[2] = selected("Sound")
    
    outChannels = 2

else
    # --- STANDARD MULTI-CHANNEL / MONO PROCESSING ---
    for iChan from 1 to numChannels
        selectObject: workCopy
        Extract one channel: iChan
        chanInput[iChan] = selected("Sound")
        
        @processSingleChannel: chanInput[iChan], "proc_chan_" + string$(iChan), max_lag
        chanOutput[iChan] = selected("Sound")
    endfor
    outChannels = numChannels
endif

# Recombine Channels
if outChannels = 1
    selectObject: chanOutput[1]
    finalOutput = Copy: originalName$ + "_autocorr_" + presetName$
else
    selectObject: chanOutput[1]
    for iChan from 2 to outChannels
        plusObject: chanOutput[iChan]
    endfor
    Combine to stereo
    finalOutput = selected("Sound")
    Rename: originalName$ + "_autocorr_" + presetName$
endif

# Restore original time bounds
selectObject: finalOutput
Shift times to: "start time", origXmin

# ============================================================
# Automatic RMS Makeup Gain (Equal-Loudness Alignment)
# ============================================================
selectObject: finalOutput
rawOutRms = Get root-mean-square: 0, 0

appliedMakeupDb = 0.0
if match_RMS_to_input and rawOutRms > 1e-6 and origRms > 1e-6
    targetGainRatio = origRms / rawOutRms
    rawGainDb = 20 * log10(targetGainRatio)
    
    clampedGainDb = min(rawGainDb, max_makeup_gain_dB)
    appliedGainScale = 10^(clampedGainDb / 20)
    appliedMakeupDb = clampedGainDb
    
    selectObject: finalOutput
    Formula: "self * " + string$(appliedGainScale)
    
    appendInfoLine: "RMS Matching Applied:"
    appendInfoLine: "  Input RMS:    ", fixed$(origRms, 4)
    appendInfoLine: "  Raw Out RMS:  ", fixed$(rawOutRms, 4), " (", fixed$(20 * log10(max(1e-6, rawOutRms)), 2), " dB)"
    appendInfoLine: "  Makeup Gain:  +", fixed$(appliedMakeupDb, 2), " dB"
    appendInfoLine: ""
endif

# Optional Output Peak Scaling
if peak_normalize_output
    selectObject: finalOutput
    Scale peak: scale_peak
    appendInfoLine: "Output Peak Normalized to: ", fixed$(scale_peak, 2)
endif

# Clean up channel arrays and work copy
removeObject: workCopy
for iChan from 1 to outChannels
    removeObject: chanInput[iChan], chanOutput[iChan]
endfor

# ============================================================
# Visualization Procedure
# ============================================================
procedure drawVisualization
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    
    # 1. Measure Individual Sound Peaks
    selectObject: sound
    origMax = Get maximum: 0, 0, "None"
    origMin = Get minimum: 0, 0, "None"
    origAbs = max(abs(origMax), abs(origMin)) * 1.1
    if origAbs = 0
        origAbs = 1.0
    endif
    
    selectObject: finalOutput
    outMax = Get maximum: 0, 0, "None"
    outMin = Get minimum: 0, 0, "None"
    outAbs = max(abs(outMax), abs(outMin)) * 1.1
    if outAbs = 0
        outAbs = 1.0
    endif
    
    # 2. Main Title
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Autocorrelation-Based Self-Filtering v1.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.5, 1.7
    Select inner viewport: 0.8, 7.6, 0.65, 1.6
    selectObject: sound
    Colour: "{0.4, 0.4, 0.4}"
    Draw: origXmin, origXmax, -origAbs, origAbs, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original (pk:" + fixed$(origAbs / 1.1, 2) + ")"
    
    # 4. Output Waveform
    Select outer viewport: 0, 8, 1.8, 3.0
    Select inner viewport: 0.8, 7.6, 1.95, 2.9
    selectObject: finalOutput
    Colour: "{0.2, 0.4, 0.7}"
    Draw: origXmin, origXmax, -outAbs, outAbs, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output (pk:" + fixed$(outAbs / 1.1, 2) + ")"
    Text bottom: "yes", "Time (s)"
    
    # 5. IR Plot
    if exampleIR <> 0
        Select outer viewport: 0, 4, 3.2, 5.0
        Select inner viewport: 0.8, 3.6, 3.4, 4.8
        
        selectObject: exampleIR
        irM = Get maximum: 0, 0, "None"
        irMn = Get minimum: 0, 0, "None"
        irAbs = max(abs(irM), abs(irMn)) * 1.1
        if irAbs = 0
            irAbs = 1.0
        endif
        
        Colour: "{0.2, 0.6, 0.3}"
        Draw: -max_lag, max_lag, -irAbs, irAbs, "no", "Curve"
        
        Colour: "{0.8, 0.2, 0.2}"
        Dotted line
        Draw line: 0, -irAbs, 0, irAbs
        Solid line
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "IR Gain"
        Text bottom: "yes", "Lag (s)"
        Text top: "no", "Example Color Kernel"
    endif
    
    # 6. Parameters & Stats Summary
    Select outer viewport: 4, 8, 3.2, 5.0
    Select inner viewport: 4.4, 7.6, 3.4, 4.8
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.2, 0.2, 0.2}"
    Text: 0.08, "left", 0.84, "half", "Window duration: " + fixed$(window_duration * 1000, 0) + " ms"
    Text: 0.08, "left", 0.70, "half", "Max lag limit:    " + fixed$(max_lag * 1000, 1) + " ms"
    Text: 0.08, "left", 0.56, "half", "Resonance gain:  " + fixed$(resonance_gain, 2)
    Text: 0.08, "left", 0.42, "half", "Dry/Wet mixture:  " + fixed$(dry_wet_mix * 100, 0) + "%"
    Text: 0.08, "left", 0.28, "half", "RMS Makeup Gain:  +" + fixed$(appliedMakeupDb, 2) + " dB"
    Text: 0.08, "left", 0.14, "half", "Output Channels: " + string$(outChannels)
    
    Colour: "Black"
    Draw inner box
    Font size: 10
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endproc

if draw_visualization
    @drawVisualization
endif

if exampleIR <> 0
    removeObject: exampleIR
endif

# ============================================================
# Safety Check & Playback
# ============================================================
selectObject: finalOutput
finalOutputName$ = selected$("Sound")

outMaxVal = Get maximum: 0, 0, "None"
outMinVal = Get minimum: 0, 0, "None"
outPeakAbs = max(abs(outMaxVal), abs(outMinVal))
finalRms = Get root-mean-square: 0, 0

appendInfoLine: "Done!"
appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: " Output sound: ", finalOutputName$
appendInfoLine: " Channels:     ", outChannels
appendInfoLine: " Duration:     ", fixed$(duration, 3), " s"
appendInfoLine: " Peak Level:   ", fixed$(outPeakAbs, 3), " (", fixed$(20 * log10(max(1e-6, outPeakAbs)), 2), " dBFS)"
appendInfoLine: " RMS Level:    ", fixed$(finalRms, 4), " (", fixed$(20 * log10(max(1e-6, finalRms)), 2), " dBFS)"
appendInfoLine: "============================================"

if outPeakAbs > 1.0
    appendInfoLine: "⚠️ WARNING: Output peak exceeds 0 dBFS (" + fixed$(20 * log10(outPeakAbs), 2) + " dBFS)!"
    if play_after_processing
        appendInfoLine: "-> Applying temporary safety attenuation (scaling to 0.99) for playback."
        selectObject: finalOutput
        tempPlayCopy = Copy: "temp_play_safety"
        Scale peak: 0.99
        Play
        removeObject: tempPlayCopy
    endif
else
    if play_after_processing
        selectObject: finalOutput
        Play
    endif
endif

selectObject: finalOutput