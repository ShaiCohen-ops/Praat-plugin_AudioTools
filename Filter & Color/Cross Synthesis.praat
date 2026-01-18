# ============================================================
# Praat AudioTools - Cross_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-synthesis using LPC source-filter decomposition.
#   Combines the excitation from one sound with the spectral
#   envelope from another.
#
# Changelog v0.3:
#   - Fixed preset comparison (number not string)
#   - Fixed all Formula variable interpolation
#   - Fixed object selection (ID-based)
#   - Fixed inline conditionals
#   - Added preset name to output
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects: Source (1) and Filter (2)"
endif

sourceSound = selected("Sound", 1)
filterSound = selected("Sound", 2)

form Cross Synthesis v0.3
    optionmenu Preset: 1
        option Manual
        option Speech
        option Sustained Tones
        option Percussive
        option Vocal Formants
        option Extreme Smooth
    positive Window_ms 50
    positive Step_ms 5
    positive Lpc_order 16
    real Envelope_smoothing 0.8
    real Transfer_amount 0.8
    optionmenu Duration_match: 3
        option Source length
        option Filter length
        option Shorter
        option No matching
    real Dry_wet_mix 1.0
    positive Scale_peak 0.95
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets (fixed: use number not string)
# ============================================================
if preset = 2
    # Speech
    window_ms = 40
    step_ms = 5
    lpc_order = 16
    envelope_smoothing = 0.8
    transfer_amount = 0.8
    presetName$ = "Speech"
elsif preset = 3
    # Sustained Tones
    window_ms = 70
    step_ms = 8
    lpc_order = 18
    envelope_smoothing = 0.85
    transfer_amount = 0.9
    presetName$ = "SustainedTones"
elsif preset = 4
    # Percussive
    window_ms = 30
    step_ms = 3
    lpc_order = 14
    envelope_smoothing = 0.65
    transfer_amount = 0.7
    presetName$ = "Percussive"
elsif preset = 5
    # Vocal Formants
    window_ms = 45
    step_ms = 5
    lpc_order = 20
    envelope_smoothing = 0.75
    transfer_amount = 0.85
    presetName$ = "VocalFormants"
elsif preset = 6
    # Extreme Smooth
    window_ms = 60
    step_ms = 7
    lpc_order = 12
    envelope_smoothing = 0.9
    transfer_amount = 0.95
    presetName$ = "ExtremeSmooth"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
selectObject: sourceSound
sourceName$ = selected$("Sound")
sourceDur = Get total duration
sourceSR = Get sampling frequency
sourceChannels = Get number of channels

selectObject: filterSound
filterName$ = selected$("Sound")
filterDur = Get total duration
filterSR = Get sampling frequency
filterChannels = Get number of channels

# Constrain parameters
if transfer_amount < 0
    transfer_amount = 0
elsif transfer_amount > 1
    transfer_amount = 1
endif

if envelope_smoothing < 0.3
    envelope_smoothing = 0.3
elsif envelope_smoothing > 0.95
    envelope_smoothing = 0.95
endif

windowSize = window_ms / 1000
timeStep = step_ms / 1000
preEmphasis = 0.97

# Smoothed LPC order
smoothOrder = round(lpc_order * envelope_smoothing)
if smoothOrder < 8
    smoothOrder = 8
endif

# ============================================================
# Info
# ============================================================
clearinfo
writeInfoLine: "=== Cross Synthesis v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Source: ", sourceName$, " (excitation)"
appendInfoLine: "Filter: ", filterName$, " (envelope)"
appendInfoLine: ""
appendInfoLine: "[1/5] Preprocessing..."

# ============================================================
# Preprocessing
# ============================================================
# Convert to mono for analysis
if sourceChannels > 1
    selectObject: sourceSound
    sourceMono = Convert to mono
else
    selectObject: sourceSound
    sourceMono = Copy: "source_mono"
endif

if filterChannels > 1
    selectObject: filterSound
    filterMono = Convert to mono
else
    selectObject: filterSound
    filterMono = Copy: "filter_mono"
endif

# Resample to match if needed
selectObject: sourceMono
sr1 = Get sampling frequency
selectObject: filterMono
sr2 = Get sampling frequency

targetSR = max(sr1, sr2)

if sr1 <> targetSR
    selectObject: sourceMono
    sourceResampled = Resample: targetSR, 50
    removeObject: sourceMono
    sourceMono = sourceResampled
endif

if sr2 <> targetSR
    selectObject: filterMono
    filterResampled = Resample: targetSR, 50
    removeObject: filterMono
    filterMono = filterResampled
endif

# Duration matching
selectObject: sourceMono
dur1 = Get total duration
selectObject: filterMono
dur2 = Get total duration

if duration_match = 1
    targetDur = dur1
elsif duration_match = 2
    targetDur = dur2
elsif duration_match = 3
    targetDur = min(dur1, dur2)
else
    targetDur = dur1
endif

if duration_match <> 4
    if dur1 > targetDur
        selectObject: sourceMono
        sourceExtract = Extract part: 0, targetDur, "rectangular", 1.0, "no"
        removeObject: sourceMono
        sourceMono = sourceExtract
    elsif dur1 < targetDur
        selectObject: sourceMono
        sourceLengthen = Lengthen (overlap-add): 75, 600, targetDur / dur1
        removeObject: sourceMono
        sourceMono = sourceLengthen
    endif
    
    if dur2 > targetDur
        selectObject: filterMono
        filterExtract = Extract part: 0, targetDur, "rectangular", 1.0, "no"
        removeObject: filterMono
        filterMono = filterExtract
    elsif dur2 < targetDur
        selectObject: filterMono
        filterLengthen = Lengthen (overlap-add): 75, 600, targetDur / dur2
        removeObject: filterMono
        filterMono = filterLengthen
    endif
endif

# Get final duration
selectObject: sourceMono
finalDur = Get total duration

# Store source RMS for normalization
selectObject: sourceMono
sourceRMS = Get root-mean-square: 0, 0

# ============================================================
# Procedure: Cross-synthesize mono channel
# ============================================================
procedure crossSynthesize: .sourceIn, .filterIn, .outputName$
    # Pre-emphasis on source (fixed Formula syntax)
    preEmph$ = string$(preEmphasis)
    
    selectObject: .sourceIn
    .sourcePre = Copy: "src_pre"
    Formula: "self - " + preEmph$ + " * self[col-1]"
    
    # Pre-emphasis on filter
    selectObject: .filterIn
    .filterPre = Copy: "flt_pre"
    Formula: "self - " + preEmph$ + " * self[col-1]"
    
    # Extract excitation from source via LPC inverse filtering
    selectObject: .sourcePre
    .lpcSource = To LPC (autocorrelation): lpc_order, windowSize, timeStep, 50
    
    selectObject: .sourcePre
    plusObject: .lpcSource
    .excitation = Filter (inverse)
    
    # Extract smoothed envelope from filter
    selectObject: .filterPre
    .lpcFilter = To LPC (autocorrelation): smoothOrder, windowSize, timeStep, 50
    
    # Apply filter envelope to source excitation
    selectObject: .excitation
    plusObject: .lpcFilter
    .filtered = Filter: "no"
    
    # De-emphasis
    selectObject: .filtered
    Formula: "self + " + preEmph$ + " * self[col-1]"
    
    # Blend with transfer amount
    if transfer_amount < 1.0
        selectObject: .sourceIn
        .drySignal = Copy: "dry_signal"
        .dryId$ = string$(.drySignal)
        
        transfer$ = string$(transfer_amount)
        dryAmount$ = string$(1 - transfer_amount)
        
        selectObject: .filtered
        Formula: transfer$ + " * self + " + dryAmount$ + " * Object_" + .dryId$ + "(x)"
        
        removeObject: .drySignal
    endif
    
    # Rename output
    selectObject: .filtered
    Rename: .outputName$
    .output = selected("Sound")
    
    # Cleanup
    removeObject: .sourcePre, .filterPre, .lpcSource, .excitation, .lpcFilter
    
    selectObject: .output
endproc

# ============================================================
# Main processing
# ============================================================
appendInfoLine: "[2/5] Extracting source excitation..."
appendInfoLine: "[3/5] Extracting filter envelope (order ", smoothOrder, ")..."
appendInfoLine: "[4/5] Cross-synthesizing..."

maxChannels = max(sourceChannels, filterChannels)

if maxChannels = 1
    # Mono processing
    @crossSynthesize: sourceMono, filterMono, "cross_mono"
    crossMono = selected("Sound")
    
    # Apply dry/wet mix
    if dry_wet_mix < 1
        sourceMonoId$ = string$(sourceMono)
        dryWet$ = string$(dry_wet_mix)
        dryAmount$ = string$(1 - dry_wet_mix)
        
        selectObject: crossMono
        Formula: dryWet$ + " * self + " + dryAmount$ + " * Object_" + sourceMonoId$ + "(x)"
    endif
    
    selectObject: crossMono
    finalOutput = selected("Sound")
else
    # Stereo processing
    # Extract channels from source
    if sourceChannels > 1
        selectObject: sourceSound
        Extract one channel: 1
        sourceL = selected("Sound")
        selectObject: sourceSound
        Extract one channel: 2
        sourceR = selected("Sound")
    else
        selectObject: sourceSound
        sourceL = Copy: "srcL"
        selectObject: sourceSound
        sourceR = Copy: "srcR"
    endif
    
    # Extract channels from filter
    if filterChannels > 1
        selectObject: filterSound
        Extract one channel: 1
        filterL = selected("Sound")
        selectObject: filterSound
        Extract one channel: 2
        filterR = selected("Sound")
    else
        selectObject: filterSound
        filterL = Copy: "fltL"
        selectObject: filterSound
        filterR = Copy: "fltR"
    endif
    
    # Match sample rates for stereo channels
    selectObject: sourceL
    srL = Get sampling frequency
    if srL <> targetSR
        sourceLrs = Resample: targetSR, 50
        removeObject: sourceL
        sourceL = sourceLrs
    endif
    
    selectObject: sourceR
    srR = Get sampling frequency
    if srR <> targetSR
        sourceRrs = Resample: targetSR, 50
        removeObject: sourceR
        sourceR = sourceRrs
    endif
    
    selectObject: filterL
    srL = Get sampling frequency
    if srL <> targetSR
        filterLrs = Resample: targetSR, 50
        removeObject: filterL
        filterL = filterLrs
    endif
    
    selectObject: filterR
    srR = Get sampling frequency
    if srR <> targetSR
        filterRrs = Resample: targetSR, 50
        removeObject: filterR
        filterR = filterRrs
    endif
    
    # Duration matching for stereo
    if duration_match <> 4
        selectObject: sourceL
        durL = Get total duration
        if durL > targetDur
            sourceLext = Extract part: 0, targetDur, "rectangular", 1.0, "no"
            removeObject: sourceL
            sourceL = sourceLext
        elsif durL < targetDur
            sourceLlen = Lengthen (overlap-add): 75, 600, targetDur / durL
            removeObject: sourceL
            sourceL = sourceLlen
        endif
        
        selectObject: sourceR
        durR = Get total duration
        if durR > targetDur
            sourceRext = Extract part: 0, targetDur, "rectangular", 1.0, "no"
            removeObject: sourceR
            sourceR = sourceRext
        elsif durR < targetDur
            sourceRlen = Lengthen (overlap-add): 75, 600, targetDur / durR
            removeObject: sourceR
            sourceR = sourceRlen
        endif
        
        selectObject: filterL
        durL = Get total duration
        if durL > targetDur
            filterLext = Extract part: 0, targetDur, "rectangular", 1.0, "no"
            removeObject: filterL
            filterL = filterLext
        elsif durL < targetDur
            filterLlen = Lengthen (overlap-add): 75, 600, targetDur / durL
            removeObject: filterL
            filterL = filterLlen
        endif
        
        selectObject: filterR
        durR = Get total duration
        if durR > targetDur
            filterRext = Extract part: 0, targetDur, "rectangular", 1.0, "no"
            removeObject: filterR
            filterR = filterRext
        elsif durR < targetDur
            filterRlen = Lengthen (overlap-add): 75, 600, targetDur / durR
            removeObject: filterR
            filterR = filterRlen
        endif
    endif
    
    # Cross-synthesize each channel
    @crossSynthesize: sourceL, filterL, "crossL"
    crossL = selected("Sound")
    
    @crossSynthesize: sourceR, filterR, "crossR"
    crossR = selected("Sound")
    
    # Apply dry/wet to stereo
    if dry_wet_mix < 1
        sourceLid$ = string$(sourceL)
        sourceRid$ = string$(sourceR)
        dryWet$ = string$(dry_wet_mix)
        dryAmount$ = string$(1 - dry_wet_mix)
        
        selectObject: crossL
        Formula: dryWet$ + " * self + " + dryAmount$ + " * Object_" + sourceLid$ + "(x)"
        
        selectObject: crossR
        Formula: dryWet$ + " * self + " + dryAmount$ + " * Object_" + sourceRid$ + "(x)"
    endif
    
    removeObject: sourceL, sourceR
    
    # Combine to stereo
    selectObject: crossL
    plusObject: crossR
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: crossL, crossR, filterL, filterR
endif

# ============================================================
# Normalize output
# ============================================================
appendInfoLine: "[5/5] Normalizing..."

selectObject: finalOutput
currentRMS = Get root-mean-square: 0, 0
if currentRMS > 0.000001 and sourceRMS > 0.000001
    energyFactor = sourceRMS / currentRMS
    energyFactor$ = string$(energyFactor)
    Formula: "self * " + energyFactor$
endif

Scale peak: scale_peak
Rename: sourceName$ + "_x_" + filterName$ + "_" + presetName$

# Cleanup mono working copies
removeObject: sourceMono, filterMono

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    Erase all
    
    if finalDur > 10
        timeTickInterval = 2
    elsif finalDur > 5
        timeTickInterval = 1
    elsif finalDur > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # PANEL 1: Source spectrogram
    Select outer viewport: 0, 6, 0, 2
    Select inner viewport: 0.5, 5.8, 0.3, 1.8
    
    selectObject: sourceSound
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    sourceSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Source - " + sourceName$ + " (excitation)"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: sourceSpec
    
    # PANEL 2: Filter spectrogram
    Select outer viewport: 0, 6, 2, 4
    Select inner viewport: 0.5, 5.8, 2.3, 3.8
    
    selectObject: filterSound
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    filterSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Filter - " + filterName$ + " (envelope)"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: filterSpec
    
    # PANEL 3: Result spectrogram
    Select outer viewport: 0, 6, 4, 6
    Select inner viewport: 0.5, 5.8, 4.3, 5.8
    
    selectObject: finalOutput
    if maxChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "result_viz"
    endif
    
    selectObject: resultMono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Result [" + presetName$ + "] (transfer: " + fixed$(transfer_amount * 100, 0) + "%)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: resultSpec, resultMono
endif

# ============================================================
# Output
# ============================================================
selectObject: sourceSound
plusObject: filterSound
plusObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", maxChannels

if maxChannels > 1
    appendInfoLine: "  (true stereo processing)"
endif

appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Window: ", window_ms, " ms"
appendInfoLine: "  LPC order: ", lpc_order, " -> smoothed: ", smoothOrder
appendInfoLine: "  Transfer: ", fixed$(transfer_amount * 100, 0), "%"
appendInfoLine: "  Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput