# ============================================================
# Praat AudioTools - Non-Linear_Frequency_Folding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax, added visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Non-linear frequency folding - wraps frequencies around
#   a folding point and modulates with sine/cosine pattern.
#   Creates "knotted" spectral textures.
# ============================================================

form Non-Linear Frequency Folding v0.2
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Tight Knots
        option Loose Knots
        option High Preservation
        option Fast Modulation
        option Metallic
        option Subtle Fold
    
    comment === OPTIMIZATION ===
    boolean Use_downsampling 1
    positive Processing_sample_rate 22050
    boolean Use_chunking 1
    positive Chunk_duration 10
    
    comment === FOLDING PARAMETERS ===
    boolean Fast_fourier 1
    positive Low_freq_threshold 100
    positive Folding_period 1000
    positive Sine_modulation_divisor 300
    positive Cosine_modulation_divisor 150
    
    comment === OUTPUT ===
    positive Scale_peak 0.88
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===================================================================
# PRESETS
# ===================================================================

if preset = 2
    # Tight Knots
    folding_period = 500
    presetName$ = "TightKnots"
elsif preset = 3
    # Loose Knots
    folding_period = 2000
    presetName$ = "LooseKnots"
elsif preset = 4
    # High Preservation
    low_freq_threshold = 500
    presetName$ = "HighPreserve"
elsif preset = 5
    # Fast Modulation
    sine_modulation_divisor = 150
    cosine_modulation_divisor = 75
    presetName$ = "FastMod"
elsif preset = 6
    # Metallic
    folding_period = 300
    sine_modulation_divisor = 100
    cosine_modulation_divisor = 50
    presetName$ = "Metallic"
elsif preset = 7
    # Subtle Fold
    folding_period = 1500
    low_freq_threshold = 300
    sine_modulation_divisor = 500
    cosine_modulation_divisor = 250
    presetName$ = "SubtleFold"
else
    presetName$ = "Custom"
endif

# ===================================================================
# SETUP
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
original_sr = Get sampling frequency
original_duration = Get total duration
num_channels = Get number of channels

clearinfo
writeInfoLine: "=== Non-Linear Frequency Folding v0.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 1), " s"
appendInfoLine: "Sample rate: ", original_sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Folding period: ", folding_period
appendInfoLine: "Low freq threshold: ", low_freq_threshold
appendInfoLine: ""

# ===================================================================
# CONVERT TO MONO
# ===================================================================

workingID = originalID
converted_to_mono = 0
if num_channels > 1
    selectObject: originalID
    monoID = Convert to mono
    workingID = monoID
    converted_to_mono = 1
    appendInfoLine: "Converted to mono"
endif

# ===================================================================
# DOWNSAMPLE IF REQUESTED
# ===================================================================

selectObject: workingID
current_sr = Get sampling frequency
did_downsample = 0

if use_downsampling and processing_sample_rate < current_sr
    appendInfo: "Downsampling to ", processing_sample_rate, " Hz..."
    downsampledID = Resample: processing_sample_rate, 50
    workingID = downsampledID
    did_downsample = 1
    appendInfoLine: " done"
    current_sr = processing_sample_rate
else
    appendInfoLine: "Processing at original rate"
endif

# ===================================================================
# BUILD FORMULA ONCE
# ===================================================================

formula$ = "if col < " + string$(low_freq_threshold) + 
... " then self[1, col] " +
... "else self[1, abs(col - 2 * round(col / " + string$(folding_period) + ") * " + string$(folding_period) + ")] " +
... "* (sin(col / " + string$(sine_modulation_divisor) + ") + cos(col / " + string$(cosine_modulation_divisor) + ")) ^ 2 endif"

# ===================================================================
# PROCESS (WITH OR WITHOUT CHUNKING)
# ===================================================================

selectObject: workingID
total_duration = Get total duration

if use_chunking and total_duration > chunk_duration
    # CHUNKED PROCESSING
    num_chunks = ceiling(total_duration / chunk_duration)
    appendInfoLine: "Processing ", num_chunks, " chunks of ", chunk_duration, "s"
    
    for i to num_chunks
        chunk_start = (i - 1) * chunk_duration
        chunk_end = chunk_start + chunk_duration
        
        if chunk_end > total_duration
            chunk_end = total_duration
        endif
        
        appendInfo: "  Chunk ", i, "/", num_chunks, "..."
        
        # Extract chunk
        selectObject: workingID
        chunkID = Extract part: chunk_start, chunk_end, "rectangular", 1.0, "no"
        
        # Process chunk
        To Spectrum: fast_fourier
        specID = selected("Spectrum")
        Formula: formula$
        
        To Sound
        processedChunk = selected("Sound")
        
        # Store
        chunk'i' = processedChunk
        
        removeObject: chunkID, specID
        appendInfoLine: " done"
    endfor
    
    # Concatenate chunks
    appendInfo: "Concatenating chunks..."
    
    # Get the sampling rate from first chunk
    selectObject: chunk1
    target_sr = Get sampling frequency
    
    # Ensure all chunks have same sampling rate
    for i to num_chunks
        selectObject: chunk'i'
        chunk_sr = Get sampling frequency
        if chunk_sr <> target_sr
            resampledChunkID = Resample: target_sr, 50
            removeObject: chunk'i'
            chunk'i' = resampledChunkID
        endif
    endfor
    
    # Now concatenate
    selectObject: chunk1
    for i from 2 to num_chunks
        plusObject: chunk'i'
    endfor
    processedID = Concatenate
    
    # Cleanup chunks
    for i to num_chunks
        removeObject: chunk'i'
    endfor
    
    appendInfoLine: " done"
    
else
    # WHOLE FILE PROCESSING
    appendInfo: "Processing spectrum..."
    selectObject: workingID
    To Spectrum: fast_fourier
    specID = selected("Spectrum")
    Formula: formula$
    
    To Sound
    processedID = selected("Sound")
    
    removeObject: specID
    appendInfoLine: " done"
endif

# ===================================================================
# RESAMPLE BACK TO ORIGINAL IF NEEDED
# ===================================================================

selectObject: processedID
if did_downsample
    appendInfo: "Resampling to ", original_sr, " Hz..."
    resampledID = Resample: original_sr, 50
    removeObject: processedID
    processedID = resampledID
    appendInfoLine: " done"
endif

# ===================================================================
# FINALIZE
# ===================================================================

selectObject: processedID
outName$ = originalName$ + "_freqFold_" + presetName$
Rename: outName$
Scale peak: scale_peak

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Frequency Folding: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: processedID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Frequency Folded"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: processedID
    resSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Folded Spectrogram"
    removeObject: resSpecID
    
    # Folding pattern visualization
    Select outer viewport: 0, 8, 4.0, 5.4
    Select inner viewport: 0.6, 7.6, 4.2, 5.2
    
    maxFreq = 5000
    Axes: 0, maxFreq, 0, maxFreq
    
    # Draw folding mapping
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    
    step = 50
    prevF = 0
    # Low freq: identity mapping
    if low_freq_threshold > 0
        Draw line: 0, 0, low_freq_threshold, low_freq_threshold
        prevF = low_freq_threshold
    endif
    
    # Folded region
    f = low_freq_threshold + step
    while f <= maxFreq
        # Folding formula: abs(f - 2 * round(f / period) * period)
        folded = abs(f - 2 * round(f / folding_period) * folding_period)
        if folded < 0
            folded = 0
        endif
        if folded > maxFreq
            folded = maxFreq
        endif
        Draw line: prevF, abs(prevF - 2 * round(prevF / folding_period) * folding_period), f, folded
        prevF = f
        f = f + step
    endwhile
    
    # Mark folding period
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 1
    Dotted line
    p = folding_period
    while p < maxFreq
        Draw line: p, 0, p, maxFreq
        p = p + folding_period
    endwhile
    Solid line
    
    # Mark low freq threshold
    Colour: "{0.2, 0.7, 0.4}"
    Draw line: low_freq_threshold, 0, low_freq_threshold, maxFreq
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text top: "no", "Frequency Folding Map (green=threshold, gray=folding periods)"
    Text left: "yes", "Output (Hz)"
    Text bottom: "yes", "Input Frequency (Hz)"
    
    # Info panel
    Select outer viewport: 0, 8, 5.5, 6.1
    Select inner viewport: 0.5, 7.7, 5.55, 6.05
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Folding: " + string$(folding_period) + " Hz"
    Text: 0.22, "left", 0.5, "half", "Threshold: " + string$(low_freq_threshold) + " Hz"
    Text: 0.45, "left", 0.5, "half", "Sin div: " + string$(sine_modulation_divisor)
    Text: 0.65, "left", 0.5, "half", "Cos div: " + string$(cosine_modulation_divisor)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ===================================================================
# CLEANUP
# ===================================================================

if converted_to_mono
    removeObject: monoID
endif
if did_downsample
    removeObject: downsampledID
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", outName$

selectObject: originalID
plusObject: processedID

if play_result
    selectObject: processedID
    Play
endif