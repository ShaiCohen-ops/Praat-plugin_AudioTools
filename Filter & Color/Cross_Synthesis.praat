# ============================================================
# Praat AudioTools - Cross_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-synthesis using LPC source-filter decomposition.
#   Combines the excitation from one sound with the spectral
#   envelope from another.
#
#   Architecture:
#   1. Preprocess: mono, resample, duration match
#   2. Pre-emphasis on both sounds
#   3. LPC analysis: extract excitation (source) + envelope (filter)
#   4. Apply filter envelope to source excitation
#   5. De-emphasis, blend, normalize
#
#   Supports stereo (per-channel processing).
#
# Category: Spectral
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects:"
        ... + newline$ + "  Sound 1 = Source (excitation)"
        ... + newline$ + "  Sound 2 = Filter (envelope)"
endif

sourceSound = selected("Sound", 1)
filterSound = selected("Sound", 2)

form Cross Synthesis v1.0
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Speech
        option Sustained Tones
        option Percussive
        option Vocal Formants
        option Extreme Smooth
    comment === LPC Parameters ===
    positive Window_ms 50
    positive Step_ms 5
    positive Lpc_order 16
    real Envelope_smoothing 0.8
    comment === Morph Control ===
    real Transfer_amount 0.8
    real Dry_wet_mix 1.0
    comment === Duration ===
    optionmenu Duration_match: 3
        option Source length
        option Filter length
        option Shorter
        option No matching
    comment === Output ===
    positive Scale_peak 0.95
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    window_ms = 40
    step_ms = 5
    lpc_order = 16
    envelope_smoothing = 0.8
    transfer_amount = 0.8
    presetName$ = "Speech"
elsif preset = 3
    window_ms = 70
    step_ms = 8
    lpc_order = 18
    envelope_smoothing = 0.85
    transfer_amount = 0.9
    presetName$ = "SustainedTones"
elsif preset = 4
    window_ms = 30
    step_ms = 3
    lpc_order = 14
    envelope_smoothing = 0.65
    transfer_amount = 0.7
    presetName$ = "Percussive"
elsif preset = 5
    window_ms = 45
    step_ms = 5
    lpc_order = 20
    envelope_smoothing = 0.75
    transfer_amount = 0.85
    presetName$ = "VocalFormants"
elsif preset = 6
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

if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

windowSize = window_ms / 1000
timeStep = step_ms / 1000
preEmphasis = 0.97

# Smoothed LPC order
smoothOrder = round(lpc_order * envelope_smoothing)
if smoothOrder < 8
    smoothOrder = 8
endif

if sourceChannels >= filterChannels
    maxChannels = sourceChannels
else
    maxChannels = filterChannels
endif

# ============================================================
# Procedures (defined before use)
# ============================================================

procedure matchDuration: .soundID, .targetDur
    selectObject: .soundID
    .currentDur = Get total duration
    
    if .currentDur > .targetDur
        .matched = Extract part: 0, .targetDur, "rectangular", 1.0, "no"
        removeObject: .soundID
        .result = .matched
    elsif .currentDur < .targetDur
        .ratio = .targetDur / .currentDur
        .matched = Lengthen (overlap-add): 75, 600, .ratio
        removeObject: .soundID
        .result = .matched
    else
        .result = .soundID
    endif
endproc

procedure resampleIfNeeded: .soundID, .targetSR
    selectObject: .soundID
    .currentSR = Get sampling frequency
    
    if .currentSR <> .targetSR
        .resampled = Resample: .targetSR, 50
        removeObject: .soundID
        .result = .resampled
    else
        .result = .soundID
    endif
endproc

procedure crossSynthesize: .sourceIn, .filterIn, .outputName$
    preEmph$ = string$(preEmphasis)
    
    # Pre-emphasis on source
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
        
        transfer$ = string$(transfer_amount)
        dryAmount$ = string$(1 - transfer_amount)
        
        dryObj = .drySignal
        selectObject: .filtered
        Formula: transfer$ + " * self + " + dryAmount$ + " * object[dryObj]"
        
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
# Info
# ============================================================
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  Cross Synthesis v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", sourceName$, " (excitation) | ", fixed$(sourceDur, 2), " s, ", sourceSR, " Hz, ", sourceChannels, " ch"
appendInfoLine: "Filter: ", filterName$, " (envelope) | ", fixed$(filterDur, 2), " s, ", filterSR, " Hz, ", filterChannels, " ch"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# STEP 1: Preprocessing
# ============================================================
appendInfoLine: "[1/5] Preprocessing..."

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

# Resample to match
selectObject: sourceMono
sr1 = Get sampling frequency
selectObject: filterMono
sr2 = Get sampling frequency

if sr1 >= sr2
    targetSR = sr1
else
    targetSR = sr2
endif

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

# Check LPC order against sample rate
suggestedOrder = round(targetSR / 1000) + 4
if lpc_order > suggestedOrder * 1.5
    appendInfoLine: "  WARNING: LPC order (", lpc_order, ") is high for SR ", targetSR, " Hz (suggested: ~", suggestedOrder, ")"
elsif lpc_order < suggestedOrder * 0.5
    appendInfoLine: "  WARNING: LPC order (", lpc_order, ") is low for SR ", targetSR, " Hz (suggested: ~", suggestedOrder, ")"
endif

appendInfoLine: "  Target SR: ", targetSR, " Hz"

# Duration matching
selectObject: sourceMono
dur1 = Get total duration
selectObject: filterMono
dur2 = Get total duration

if duration_match = 1
    targetDur = dur1
    durationStrategy$ = "source length"
elsif duration_match = 2
    targetDur = dur2
    durationStrategy$ = "filter length"
elsif duration_match = 3
    if dur1 <= dur2
        targetDur = dur1
    else
        targetDur = dur2
    endif
    durationStrategy$ = "shorter"
else
    targetDur = 0
    durationStrategy$ = "no matching"
endif

if duration_match <> 4
    @matchDuration: sourceMono, targetDur
    sourceMono = matchDuration.result
    
    @matchDuration: filterMono, targetDur
    filterMono = matchDuration.result
    
    appendInfoLine: "  Duration matched to ", fixed$(targetDur, 3), " s (", durationStrategy$, ")"
endif

# Get final duration
selectObject: sourceMono
finalDur = Get total duration

# Validate window size
if windowSize > finalDur / 2
    windowSize = finalDur / 2
    window_ms = windowSize * 1000
    appendInfoLine: "  WARNING: Window reduced to ", fixed$(window_ms, 1), " ms (file too short)"
endif

if windowSize < 0.005
    exitScript: "Window size too small (min 5 ms). File may be too short."
endif

# Store source RMS for normalization
selectObject: sourceMono
sourceRMS = Get root-mean-square: 0, 0

appendInfoLine: "  Final duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: ""

# ============================================================
# STEP 2-4: Cross-synthesis
# ============================================================
appendInfoLine: "[2/5] Extracting source excitation..."
appendInfoLine: "[3/5] Extracting filter envelope (order ", smoothOrder, ")..."
appendInfoLine: "[4/5] Cross-synthesizing..."

if maxChannels = 1
    # --- Mono processing ---
    @crossSynthesize: sourceMono, filterMono, "cross_mono"
    crossMono = selected("Sound")
    
    # Apply dry/wet mix
    if dry_wet_mix < 1
        dryWet$ = string$(dry_wet_mix)
        dryAmount$ = string$(1 - dry_wet_mix)
        
        sourceObj = sourceMono
        selectObject: crossMono
        Formula: dryWet$ + " * self + " + dryAmount$ + " * object[sourceObj]"
    endif
    
    selectObject: crossMono
    finalOutput = selected("Sound")
else
    # --- Stereo processing ---
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
    
    # Resample stereo channels
    @resampleIfNeeded: sourceL, targetSR
    sourceL = resampleIfNeeded.result
    
    @resampleIfNeeded: sourceR, targetSR
    sourceR = resampleIfNeeded.result
    
    @resampleIfNeeded: filterL, targetSR
    filterL = resampleIfNeeded.result
    
    @resampleIfNeeded: filterR, targetSR
    filterR = resampleIfNeeded.result
    
    # Duration matching for stereo
    if duration_match <> 4
        @matchDuration: sourceL, targetDur
        sourceL = matchDuration.result
        
        @matchDuration: sourceR, targetDur
        sourceR = matchDuration.result
        
        @matchDuration: filterL, targetDur
        filterL = matchDuration.result
        
        @matchDuration: filterR, targetDur
        filterR = matchDuration.result
    endif
    
    # Cross-synthesize each channel
    @crossSynthesize: sourceL, filterL, "crossL"
    crossL = selected("Sound")
    
    @crossSynthesize: sourceR, filterR, "crossR"
    crossR = selected("Sound")
    
    # Apply dry/wet to stereo
    if dry_wet_mix < 1
        dryWet$ = string$(dry_wet_mix)
        dryAmount$ = string$(1 - dry_wet_mix)
        
        sourceLobj = sourceL
        selectObject: crossL
        Formula: dryWet$ + " * self + " + dryAmount$ + " * object[sourceLobj]"
        
        sourceRobj = sourceR
        selectObject: crossR
        Formula: dryWet$ + " * self + " + dryAmount$ + " * object[sourceRobj]"
    endif
    
    # Combine to stereo
    selectObject: crossL
    plusObject: crossR
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: crossL, crossR
    removeObject: sourceL, sourceR, filterL, filterR
endif

# ============================================================
# STEP 5: Normalize output
# ============================================================
appendInfoLine: "[5/5] Normalizing..."

selectObject: finalOutput
currentRMS = Get root-mean-square: 0, 0

if currentRMS > 0.000001 and sourceRMS > 0.000001
    energyFactor = sourceRMS / currentRMS
    energyFactor$ = string$(energyFactor)
    Formula: "self * " + energyFactor$
    appendInfoLine: "  Energy matched to source (x", fixed$(energyFactor, 2), ")"
else
    if currentRMS < 0.000001
        appendInfoLine: "  WARNING: Output is silent - check LPC parameters"
    endif
endif

Scale peak: scale_peak
Rename: sourceName$ + "_x_" + filterName$ + "_" + presetName$
outputName$ = selected$("Sound")

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    vizDuration = finalDur
    if vizDuration > 12
        vizDuration = 12
    endif
    maxFreqDisplay = 5000
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Cross Synthesis v1.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half", sourceName$ + " (excite) x " + filterName$ + " (env) | " + presetName$
    
    # === SOURCE WAVEFORM ===
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.6, 3.7, 0.7, 1.4
    selectObject: sourceSound
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Src"
    Text top: "no", sourceName$ + " (excitation)"
    
    # === FILTER WAVEFORM ===
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.4, 7.7, 0.7, 1.4
    selectObject: filterSound
    Colour: "{0.8, 0.4, 0.3}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Flt"
    Text top: "no", filterName$ + " (envelope)"
    
    # === SOURCE SPECTROGRAM ===
    Select outer viewport: 0, 4, 1.6, 3.0
    Select inner viewport: 0.6, 3.7, 1.7, 2.9
    selectObject: sourceSound
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specSource = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Source Spectrogram"
    removeObject: specSource
    
    # === FILTER SPECTROGRAM + LPC ENVELOPE OVERLAY ===
    Select outer viewport: 4, 8, 1.6, 3.0
    Select inner viewport: 4.4, 7.7, 1.7, 2.9
    selectObject: filterSound
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specFilter = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    
    ## Overlay LPC spectral envelope at midpoint
    selectObject: filterMono
    midTime = finalDur / 2
    filterLPC = To LPC (autocorrelation): smoothOrder, windowSize, timeStep, 50
    selectObject: filterLPC
    lpcSlice = To Spectrum (slice): midTime, 20, 0, 50
    
    Colour: "{1.0, 0.8, 0.2}"
    Line width: 2
    selectObject: lpcSlice
    Draw: 0, maxFreqDisplay, 0, 80, "no"
    Line width: 1
    removeObject: filterLPC, lpcSlice
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Filter Spectrogram + LPC Envelope"
    removeObject: specFilter
    
    # === TRANSFER AMOUNT BAR ===
    Select outer viewport: 0, 8, 3.1, 3.6
    Select inner viewport: 0.6, 7.7, 3.2, 3.5
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    # Background bar
    Paint rectangle: "{0.85, 0.85, 0.9}", 0.15, 0.85, 0.25, 0.75
    
    # Fill bar
    barEnd = 0.15 + 0.7 * transfer_amount
    Paint rectangle: "{0.4, 0.6, 0.85}", 0.15, barEnd, 0.25, 0.75
    
    # Dry/wet indicator
    dryWetEnd = 0.15 + 0.7 * dry_wet_mix
    Colour: "{0.2, 0.7, 0.4}"
    Line width: 2
    Draw line: dryWetEnd, 0.15, dryWetEnd, 0.85
    Line width: 1
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    Text: 0.02, "left", 0.5, "half", "Transfer:"
    Text: 0.88, "left", 0.5, "half", fixed$(transfer_amount * 100, 0) + "%"
    
    Colour: "{0.2, 0.7, 0.4}"
    Text: dryWetEnd, "centre", -0.3, "half", "wet " + fixed$(dry_wet_mix * 100, 0) + "%"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 3.7, 4.6
    Select inner viewport: 0.6, 7.7, 3.8, 4.5
    selectObject: finalOutput
    
    resultChannels = Get number of channels
    if resultChannels > 1
        resultVizSound = Convert to mono
    else
        resultVizSound = Copy: "result_viz"
    endif
    
    selectObject: resultVizSound
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out"
    Text top: "no", "Result: " + outputName$
    
    # === OUTPUT SPECTROGRAM ===
    Select outer viewport: 0, 8, 4.7, 6.1
    Select inner viewport: 0.6, 7.7, 4.8, 6.0
    selectObject: resultVizSound
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specResult = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result Spectrogram"
    removeObject: specResult, resultVizSound
    
    # === STATS PANEL ===
    Select outer viewport: 0, 8, 6.2, 7.0
    Select inner viewport: 0.6, 7.7, 6.3, 6.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Cross Synthesis Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    Text: 0.02, "left", 0.62, "half", "Source: " + sourceName$ + " (" + fixed$(sourceDur, 2) + "s) | Filter: " + filterName$ + " (" + fixed$(filterDur, 2) + "s) | Out: " + fixed$(finalDur, 2) + "s"
    Text: 0.02, "left", 0.38, "half", "LPC: " + string$(lpc_order) + " -> " + string$(smoothOrder) + " | Window: " + fixed$(window_ms, 0) + "ms | Step: " + fixed$(step_ms, 0) + "ms | SR: " + string$(targetSR) + " Hz"
    Text: 0.02, "left", 0.15, "half", "Transfer: " + fixed$(transfer_amount * 100, 0) + "% | Dry/Wet: " + fixed$(dry_wet_mix * 100, 0) + "% | Duration: " + durationStrategy$ + " | Preset: " + presetName$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 7.05, 7.4
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: 0.05, 0.5, 0.09, 0.5
    Colour: "Black"
    Text: 0.10, "left", 0.5, "half", "Source"
    Colour: "{0.8, 0.4, 0.3}"
    Draw line: 0.25, 0.5, 0.29, 0.5
    Colour: "Black"
    Text: 0.30, "left", 0.5, "half", "Filter"
    Colour: "{0.4, 0.6, 0.4}"
    Draw line: 0.45, 0.5, 0.49, 0.5
    Colour: "Black"
    Text: 0.50, "left", 0.5, "half", "Result"
    Colour: "{1.0, 0.8, 0.2}"
    Line width: 2
    Draw line: 0.65, 0.5, 0.69, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.70, "left", 0.5, "half", "LPC Envelope"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Cleanup
# ============================================================
removeObject: sourceMono, filterMono

selectObject: sourceSound
plusObject: filterSound
plusObject: finalOutput

# ============================================================
# Output
# ============================================================
appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", outputName$
appendInfoLine: "Channels: ", maxChannels
if maxChannels > 1
    appendInfoLine: "  (true stereo processing)"
endif
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Window: ", window_ms, " ms | Step: ", step_ms, " ms"
appendInfoLine: "  LPC order: ", lpc_order, " -> smoothed: ", smoothOrder
appendInfoLine: "  Transfer: ", fixed$(transfer_amount * 100, 0), "%"
appendInfoLine: "  Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: "  Duration: ", durationStrategy$

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput
