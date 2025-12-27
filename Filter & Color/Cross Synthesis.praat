# ============================================================
# Praat AudioTools - Cross Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-synthesis using LPC source-filter decomposition.
#   Combines the excitation (source) from one sound with the
#   spectral envelope (filter) from another, creating hybrid
#   timbres. Classic vocoder-like effect used in electronic
#   music and sound design.
#
# Technical approach:
#   - Extracts excitation via LPC inverse filtering (Sound 1)
#   - Extracts spectral envelope via LPC analysis (Sound 2)
#   - Applies envelope to excitation via LPC filtering
#   - Pre/de-emphasis improves high-frequency transfer
#   - Smoothed LPC order reduces envelope artifacts
#   - True stereo processing preserves spatial image
#
# Usage:
#   Select TWO Sound objects: Source (1) and Filter (2)
#   Source provides the excitation (rhythm, pitch)
#   Filter provides the spectral envelope (timbre, formants)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Cross Synthesis
    comment Select Source (1) and Filter (2) before running.
    comment Source = excitation, Filter = spectral envelope.
    optionmenu Preset: 1
        option Custom
        option Speech
        option Sustained Tones
        option Percussive
        option Vocal Formants
        option Extreme Smooth
    positive window_ms 50
    positive step_ms 5
    positive lpc_order 16
    real envelope_smoothing 0.8
    real transfer_amount 0.8
    optionmenu Duration_match: 3
        option Source length
        option Filter length
        option Shorter
        option No matching
    real dry_wet_mix 1.0
    positive scale_peak 0.95
    boolean play_after_processing 1
    boolean draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Speech"
    window_ms = 40
    step_ms = 5
    lpc_order = 16
    envelope_smoothing = 0.8
    transfer_amount = 0.8
elif preset$ = "Sustained Tones"
    window_ms = 70
    step_ms = 8
    lpc_order = 18
    envelope_smoothing = 0.85
    transfer_amount = 0.9
elif preset$ = "Percussive"
    window_ms = 30
    step_ms = 3
    lpc_order = 14
    envelope_smoothing = 0.65
    transfer_amount = 0.7
elif preset$ = "Vocal Formants"
    window_ms = 45
    step_ms = 5
    lpc_order = 20
    envelope_smoothing = 0.75
    transfer_amount = 0.85
elif preset$ = "Extreme Smooth"
    window_ms = 60
    step_ms = 7
    lpc_order = 12
    envelope_smoothing = 0.9
    transfer_amount = 0.95
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects: Source (1) and Filter (2)"
endif

sourceSound = selected("Sound", 1)
filterSound = selected("Sound", 2)

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

# ============================================================
# Constrain parameters
# ============================================================
if transfer_amount < 0
    transfer_amount = 0
elif transfer_amount > 1
    transfer_amount = 1
endif

if envelope_smoothing < 0.3
    envelope_smoothing = 0.3
elif envelope_smoothing > 0.95
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

# Generate unique ID
uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Preprocessing: Create working copies (non-destructive!)
# ============================================================
writeInfoLine: "Cross Synthesis"
appendInfoLine: "=============="
appendInfoLine: "Source: ", sourceName$, " (excitation)"
appendInfoLine: "Filter: ", filterName$, " (envelope)"
appendInfoLine: ""
appendInfoLine: "[1/5] Preprocessing..."

# Convert to mono for analysis
if sourceChannels > 1
    selectObject: sourceSound
    sourceMono = Convert to mono
else
    selectObject: sourceSound
    sourceMono = Copy: "source_mono_" + uniqueID$
endif

if filterChannels > 1
    selectObject: filterSound
    filterMono = Convert to mono
else
    selectObject: filterSound
    filterMono = Copy: "filter_mono_" + uniqueID$
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
elif duration_match = 2
    targetDur = dur2
elif duration_match = 3
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
    elif dur1 < targetDur
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
    elif dur2 < targetDur
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
    # Pre-emphasis on source
    selectObject: .sourceIn
    .sourcePre = Copy: "src_pre_" + uniqueID$
    Formula: "self - 'preEmphasis' * self[col-1]"
    
    # Pre-emphasis on filter
    selectObject: .filterIn
    .filterPre = Copy: "flt_pre_" + uniqueID$
    Formula: "self - 'preEmphasis' * self[col-1]"
    
    # Extract excitation from source via LPC inverse filtering
    selectObject: .sourcePre
    .lpcSource = To LPC (autocorrelation): lpc_order, windowSize, timeStep, 50
    
    selectObject: .sourcePre, .lpcSource
    .excitation = Filter (inverse)
    Rename: "excitation_" + uniqueID$
    
    # Extract smoothed envelope from filter
    selectObject: .filterPre
    .lpcFilter = To LPC (autocorrelation): smoothOrder, windowSize, timeStep, 50
    
    # Apply filter envelope to source excitation
    selectObject: .excitation, .lpcFilter
    .filtered = Filter: "no"
    
    # De-emphasis
    selectObject: .filtered
    Formula: "self + 'preEmphasis' * self[col-1]"
    
    # Blend with transfer amount
    if transfer_amount < 1.0
        selectObject: .sourceIn
        .drySignal = Copy: "dry_" + uniqueID$
        
        selectObject: .filtered
        Formula: "'transfer_amount' * self + (1 - 'transfer_amount') * Sound_dry_'uniqueID$'(x)"
        
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
    @crossSynthesize: sourceMono, filterMono, "cross_mono_" + uniqueID$
    crossMono = selected("Sound")
    
    # Apply dry/wet mix
    if dry_wet_mix < 1
        selectObject: sourceMono
        Rename: "orig_" + uniqueID$
        selectObject: crossMono
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_orig_'uniqueID$'(x)"
        selectObject: "Sound orig_" + uniqueID$
        Rename: "source_mono_" + uniqueID$
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
        sourceL = Copy: "srcL_" + uniqueID$
        selectObject: sourceSound
        sourceR = Copy: "srcR_" + uniqueID$
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
        filterL = Copy: "fltL_" + uniqueID$
        selectObject: filterSound
        filterR = Copy: "fltR_" + uniqueID$
    endif
    
    # Match sample rates and durations for stereo channels
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
        elif durL < targetDur
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
        elif durR < targetDur
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
        elif durL < targetDur
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
        elif durR < targetDur
            filterRlen = Lengthen (overlap-add): 75, 600, targetDur / durR
            removeObject: filterR
            filterR = filterRlen
        endif
    endif
    
    # Cross-synthesize each channel
    @crossSynthesize: sourceL, filterL, "crossL_" + uniqueID$
    crossL = selected("Sound")
    
    @crossSynthesize: sourceR, filterR, "crossR_" + uniqueID$
    crossR = selected("Sound")
    
    # Apply dry/wet to stereo
    if dry_wet_mix < 1
        selectObject: sourceL
        Rename: "origL_" + uniqueID$
        selectObject: crossL
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_origL_'uniqueID$'(x)"
        removeObject: "Sound origL_" + uniqueID$
        
        selectObject: sourceR
        Rename: "origR_" + uniqueID$
        selectObject: crossR
        Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_origR_'uniqueID$'(x)"
        removeObject: "Sound origR_" + uniqueID$
    else
        removeObject: sourceL, sourceR
    endif
    
    # Combine to stereo
    selectObject: crossL, crossR
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
    Formula: "self * 'energyFactor'"
endif

Scale peak: scale_peak
Rename: sourceName$ + "_x_" + filterName$

# Cleanup mono working copies
removeObject: sourceMono, filterMono

# ============================================================
# Visualization
# ============================================================
procedure drawVisualization
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
    
    # ========================================================
    # PANEL 1: Source spectrogram (top)
    # ========================================================
    Select outer viewport: 0, 6, 0, 2
    Select inner viewport: 0.5, 5.8, 0.3, 1.8
    
    selectObject: sourceSound
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    sourceSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Source## - " + sourceName$ + " (excitation)"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: sourceSpec
    
    # ========================================================
    # PANEL 2: Filter spectrogram (middle)
    # ========================================================
    Select outer viewport: 0, 6, 2, 4
    Select inner viewport: 0.5, 5.8, 2.3, 3.8
    
    selectObject: filterSound
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    filterSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Filter## - " + filterName$ + " (envelope)"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: filterSpec
    
    # ========================================================
    # PANEL 3: Result spectrogram (bottom)
    # ========================================================
    Select outer viewport: 0, 6, 4, 6
    Select inner viewport: 0.5, 5.8, 4.3, 5.8
    
    selectObject: finalOutput
    if maxChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "result_viz_" + uniqueID$
    endif
    
    selectObject: resultMono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Black
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Result## - Cross-synthesis (transfer: " + fixed$(transfer_amount * 100, 0) + "%)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: resultSpec, resultMono
endproc

if draw_visualization
    @drawVisualization
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
# Report
# ============================================================
appendInfoLine: ""
appendInfoLine: "=============="
appendInfoLine: "Complete!"
appendInfoLine: ""
appendInfoLine: "Output: ", sourceName$, "_x_", filterName$
appendInfoLine: "Channels: ", maxChannels, if maxChannels > 1 then " (true stereo)" else "" fi
appendInfoLine: "Duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Preset: ", preset$
appendInfoLine: "  Window: ", window_ms, " ms"
appendInfoLine: "  Step: ", step_ms, " ms"
appendInfoLine: "  LPC order: ", lpc_order, " -> smoothed: ", smoothOrder
appendInfoLine: "  Envelope smoothing: ", fixed$(envelope_smoothing, 2)
appendInfoLine: "  Transfer: ", fixed$(transfer_amount * 100, 0), "%"
appendInfoLine: "  Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Visualization in Picture window."
endif