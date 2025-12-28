# ============================================================
# Praat AudioTools - Non-Linear Frequency Folding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# Non-Linear Frequency Folding 
# ============================================================

form Non-Linear Frequency Folding
    comment === PRESETS ===
    optionmenu preset: 1
        option Default
        option Tight Knots
        option Loose Knots
        option High Preservation
        option Fast Modulation
    
    comment === OPTIMIZATION ===
    boolean use_downsampling 1
    positive processing_sample_rate 22050
    comment (Lower = faster, 22050 Hz recommended)
    
    boolean use_chunking 1
    positive chunk_duration 10
    comment (Process in N-second chunks, smaller = faster)
    
    comment === FOLDING PARAMETERS ===
    boolean fast_fourier yes
    positive low_freq_threshold 100
    positive folding_period 1000
    positive sine_modulation_divisor 300
    positive cosine_modulation_divisor 150
    
    comment === OUTPUT ===
    positive scale_peak 0.88
    boolean play_after_processing 1
endform

# ===================================================================
# PRESETS
# ===================================================================

if preset = 2
    folding_period = 500
elsif preset = 3
    folding_period = 2000
elsif preset = 4
    low_freq_threshold = 500
elsif preset = 5
    sine_modulation_divisor = 150
    cosine_modulation_divisor = 75
endif

# ===================================================================
# SETUP
# ===================================================================

if numberOfSelected("Sound") <> 1
    exit Please select exactly ONE Sound object first.
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
original_sr = Get sampling frequency
original_duration = Get total duration
num_channels = Get number of channels

writeInfoLine: "=== NON-LINEAR FREQUENCY FOLDING ==="
appendInfoLine: "Duration: ", fixed$(original_duration, 1), " s"
appendInfoLine: "Original rate: ", original_sr, " Hz"

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
    appendInfoLine: "✓ Converted to mono"
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
    appendInfoLine: "→ Processing at original rate"
endif

# ===================================================================
# BUILD FORMULA ONCE
# ===================================================================

formula$ = "if col < " + string$(low_freq_threshold) + 
... " then self[1, col] " +
... "else self[1, abs(col - 2 * round(col / " + string$(folding_period) + ") * " + string$(folding_period) + ")] " +
... "* (sin(col / " + string$(sine_modulation_divisor) + ") + cos(col / " + string$(cosine_modulation_divisor) + ")) ^ 2 fi"

# ===================================================================
# PROCESS (WITH OR WITHOUT CHUNKING)
# ===================================================================

selectObject: workingID
total_duration = Get total duration

if use_chunking and total_duration > chunk_duration
    # CHUNKED PROCESSING
    num_chunks = ceiling(total_duration / chunk_duration)
    appendInfoLine: "✓ Processing ", num_chunks, " chunks of ", chunk_duration, "s"
    
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
    appendInfo: "✓ Concatenating chunks..."
    
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
outName$ = originalName$ + "_spectral_knots"
Rename: outName$
Scale peak: scale_peak

# Cleanup
if converted_to_mono
    removeObject: monoID
endif
if did_downsample
    removeObject: downsampledID
endif

appendInfoLine: ""
appendInfoLine: "✓ Output: ", outName$
appendInfoLine: "=== COMPLETE ==="

selectObject: processedID

if play_after_processing
    Play
endif