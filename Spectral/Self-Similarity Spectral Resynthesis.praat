# ============================================================
# Praat AudioTools - Self-Similarity Spectral Resynthesis.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analysis-resynthesis effect that reshapes audio based on spectral 
#   self-similarity. Extracts MFCC features, computes a self-similarity 
#   matrix (SSM), and applies dynamic amplitude envelopes driven by 
#   similarity scores. Creates radical transformations from glitchy 
#   gating to ghostly echoes.
#
# Features:
#   - 5 creative modes: Standard boost, Novelty extraction, Diagonal 
#     recurrence, Hard quantization, Self-mosaic frame substitution
#   - Self-similarity matrix (SSM) computation from MFCCs
#   - Similarity-driven gain mapping with contrast curves
#   - 5 spatial modes: Mono, Preserve Stereo, Wide, Rotating, Mid-Side
#   - Speed optimization modes (8/16 kHz downsampling for 4-8x speedup)
#   - Real-time visualization: SSM heatmap, gain curves, waveforms
#   - Presets: Glitch Gating, Ghost Remix, Brutal Novelty, Spectral 
#     Mosaic, Chaotic Tremolo
#
# Categories: 
#   Analysis & Feature Extraction, Spectral Processing, Experimental
#
# Usage:
#   Select a Sound object and run. Adjust similarity threshold to control
#   effect intensity. Lower thresholds = more radical transformations.
#   Try "Brutal Novelty" for extreme glitch effects or "Ghost Remix" 
#   for subtle spectral enhancement.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Self-Similarity Resynthesis v2.2
    comment === CREATIVE MODE ===
    optionmenu Creative_mode: 1
        option Standard (Similarity Boost)
        option Inverted (Novelty Extractor)
        option Diagonal Recurrence
        option Hard Quantized (3 levels)
        option Self-Mosaic (Frame Substitution)
    
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Glitch Gating
        option Ghost Remix
        option Brutal Novelty
        option Spectral Mosaic
        option Chaotic Tremolo
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 16 kHz)
        option Fast (downsample to 8 kHz)
    
    comment === Analysis Parameters ===
    positive Time_step_(s) 0.01
    positive Analysis_frame_length_(s) 0.03
    positive Number_of_MFCCs 8
    
    comment === Self-Similarity ===
    positive Similarity_threshold 0.5
    
    comment === Spectral Masking ===
    positive Contrast_power 4.0
    positive High_similarity_boost_(dB) 12
    real Low_similarity_attenuation_(dB) -24
    natural Mask_smoothing_frames 3
    
    comment === Experimental Controls ===
    real Add_chaos_(0-1) 0.1
    boolean Hard_threshold_gate 0
    real Gate_threshold_(0-1) 0.5
    
    comment === Spatial Processing ===
    optionmenu Spatial_mode: 2
        option Mono (convert to mono)
        option Preserve Stereo (same envelope both channels)
        option Stereo Wide (filtered L/R)
        option Rotating (panning effect)
        option Mid-Side (process center only)
    
    comment === Output ===
    real Output_gain_(dB) 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset$ = "Glitch Gating"
    creative_mode = 2
    time_step = 0.005
    analysis_frame_length = 0.02
    number_of_MFCCs = 6
    similarity_threshold = 0.6
    contrast_power = 6.0
    mask_smoothing_frames = 1
    hard_threshold_gate = 1
    gate_threshold = 0.6
    high_similarity_boost = 18
    low_similarity_attenuation = -36
    add_chaos = 0.05
    presetName$ = "GlitchGating"
elsif preset$ = "Ghost Remix"
    creative_mode = 1
    time_step = 0.008
    analysis_frame_length = 0.025
    similarity_threshold = 0.4
    contrast_power = 3.0
    mask_smoothing_frames = 5
    high_similarity_boost = 15
    low_similarity_attenuation = -20
    presetName$ = "GhostRemix"
elsif preset$ = "Brutal Novelty"
    creative_mode = 2
    time_step = 0.005
    analysis_frame_length = 0.02
    number_of_MFCCs = 5
    similarity_threshold = 0.3
    contrast_power = 8.0
    mask_smoothing_frames = 0
    hard_threshold_gate = 1
    gate_threshold = 0.7
    high_similarity_boost = 24
    low_similarity_attenuation = -48
    presetName$ = "BrutalNovelty"
elsif preset$ = "Spectral Mosaic"
    creative_mode = 5
    time_step = 0.02
    analysis_frame_length = 0.05
    similarity_threshold = 0.4
    presetName$ = "SpectralMosaic"
elsif preset$ = "Chaotic Tremolo"
    creative_mode = 4
    time_step = 0.003
    analysis_frame_length = 0.015
    number_of_MFCCs = 4
    contrast_power = 10.0
    mask_smoothing_frames = 0
    hard_threshold_gate = 1
    gate_threshold = 0.5
    add_chaos = 0.25
    high_similarity_boost = 20
    low_similarity_attenuation = -40
    presetName$ = "ChaoticTremolo"
else
    presetName$ = "Custom"
endif

# ============================================================
# SPEED MODE
# ============================================================
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 16000
    speedStr$ = "Balanced"
else
    targetSR = 8000
    speedStr$ = "Fast"
endif

startTime = stopwatch

clearinfo
writeInfoLine: "=== Self-Similarity Resynthesis v2.2 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Mode: ", creative_mode$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Spatial: ", spatial_mode$
appendInfoLine: ""

# ============================================================
# STEREO HANDLING
# ============================================================
selectObject: originalID
num_channels = Get number of channels
origSR = Get sampling frequency
origDur = Get total duration

appendInfoLine: "Channels: ", num_channels

# For analysis: always use mono
analysisID = originalID
if num_channels > 1
    selectObject: originalID
    Convert to mono
    analysisID = selected("Sound")
    wasStereo = 1
else
    wasStereo = 0
endif

# Downsample analysis copy
workingID = analysisID
if targetSR > 0 and origSR > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: analysisID
    Resample: targetSR, 50
    workingID = selected("Sound")
endif

selectObject: workingID
duration = Get total duration
sr = Get sampling frequency

# ============================================================
# STAGE 1: EXTRACT FEATURES
# ============================================================
appendInfo: "Stage 1: MFCCs... "
selectObject: workingID
To MFCC: number_of_MFCCs, analysis_frame_length, time_step, 100, 100, 0
mfccID = selected("MFCC")

To Matrix
featureID = selected("Matrix")

actual_frames = Get number of columns
actual_coeffs = Get number of rows

removeObject: mfccID

appendInfoLine: actual_frames, " frames"

# ============================================================
# STAGE 2: NORMALIZE FEATURES
# ============================================================
appendInfo: "Stage 2: Normalizing... "
selectObject: featureID
Transpose
transposeID = selected("Matrix")

for row to actual_frames
    norm = 0
    for col to actual_coeffs
        val = Get value in cell: row, col
        norm = norm + val * val
    endfor
    
    if norm > 0.00001
        norm = sqrt(norm)
        for col to actual_coeffs
            val = Get value in cell: row, col
            Set value: row, col, val / norm
        endfor
    endif
endfor

Transpose
normalizedID = selected("Matrix")
removeObject: featureID, transposeID
appendInfoLine: "done"

# ============================================================
# STAGE 3: COMPUTE SSM
# ============================================================
appendInfo: "Stage 3: SSM (sampling)... "

Create simple Matrix: "SSM", actual_frames, actual_frames, "0"
ssmID = selected("Matrix")

row = 1
while row <= actual_frames
    col = row
    while col <= actual_frames
        dot = 0
        selectObject: normalizedID
        for c from 1 to actual_coeffs
            val_row = Get value in cell: c, row
            val_col = Get value in cell: c, col
            dot = dot + val_row * val_col
        endfor
        
        selectObject: ssmID
        Set value: row, col, dot
        Set value: col, row, dot
        
        col = col + 5
    endwhile
    row = row + 5
    
    if row mod 50 = 0
        appendInfo: "."
    endif
endwhile

appendInfoLine: " done"

# ============================================================
# STAGE 4: SCORING
# ============================================================
appendInfo: "Stage 4: Scoring... "

Create simple Matrix: "Scores", actual_frames, 1, "0"
scoreID = selected("Matrix")

for row from 1 to actual_frames
    sum = 0
    count = 0
    
    selectObject: ssmID
    col = 1
    while col <= actual_frames
        if row <> col
            val = Get value in cell: row, col
            if val > similarity_threshold
                sum = sum + val
                count = count + 1
            endif
        endif
        col = col + 10
    endwhile
    
    score = 0
    if count > 0
        score = sum / count
    endif
    
    # Apply creative mode
    if creative_mode = 2
        score = 1 - score
    elsif creative_mode = 3
        selectObject: ssmID
        diag_sum = 0
        diag_count = 0
        for offset from 1 to 10
            if row + offset <= actual_frames
                val_forward = Get value in cell: row, row + offset
                diag_sum = diag_sum + val_forward
                diag_count = diag_count + 1
            endif
            if row - offset >= 1
                val_backward = Get value in cell: row, row - offset
                diag_sum = diag_sum + val_backward
                diag_count = diag_count + 1
            endif
        endfor
        if diag_count > 0
            score = score * 0.5 + (diag_sum / diag_count) * 0.5
        endif
    endif
    
    selectObject: scoreID
    Set value: row, 1, score
endfor

appendInfoLine: "done"

# ============================================================
# STAGE 5: SMOOTHING
# ============================================================
appendInfo: "Stage 5: Smoothing... "

if mask_smoothing_frames > 0
    Create simple Matrix: "Smoothed", actual_frames, 1, "0"
    smoothID = selected("Matrix")
    
    half = floor(mask_smoothing_frames / 2)
    
    for row from 1 to actual_frames
        start = max(1, row - half)
        end = min(actual_frames, row + half)
        sum = 0
        count = 0
        
        selectObject: scoreID
        for i from start to end
            val = Get value in cell: i, 1
            sum = sum + val
            count = count + 1
        endfor
        
        selectObject: smoothID
        Set value: row, 1, sum / count
    endfor
    
    removeObject: scoreID
    scoreID = smoothID
else
    smoothID = scoreID
endif

appendInfoLine: "done"

# ============================================================
# STAGE 6: GAIN MAPPING
# ============================================================
appendInfo: "Stage 6: Gain... "

selectObject: scoreID
s_min = Get minimum
s_max = Get maximum
if s_max = s_min
    s_max = s_min + 0.0001
endif

Create simple Matrix: "Gain", actual_frames, 1, "0"
gainID = selected("Matrix")

selectObject: gainID
for row from 1 to actual_frames
    selectObject: scoreID
    raw = Get value in cell: row, 1
    
    if add_chaos > 0
        noise = randomUniform(-1, 1) * add_chaos
        raw = raw + noise
        raw = max(s_min, min(s_max, raw))
    endif
    
    norm = (raw - s_min) / (s_max - s_min)
    
    if hard_threshold_gate
        if norm < gate_threshold
            norm = 0
        else
            norm = 1
        endif
    endif
    
    if creative_mode = 4
        norm = floor(norm * 3) / 3
    endif
    
    curved = norm ^ contrast_power
    gain_db = low_similarity_attenuation + curved * (high_similarity_boost - low_similarity_attenuation)
    
    selectObject: gainID
    Set value: row, 1, gain_db
endfor

appendInfoLine: "done"

# ============================================================
# STAGE 7: RESYNTHESIS (OPTIMIZED - FIXED)
# ============================================================
appendInfo: "Stage 7: Resynthesis... "

if creative_mode = 5
    # Self-Mosaic mode
    selectObject: workingID
    Create Sound from formula: "Mosaic", 1, 0, duration, sr, "0"
    outID = selected("Sound")
    
    frame_samples = round(time_step * sr)
    
    frame = 1
    while frame < actual_frames
        selectObject: ssmID
        best_sim = -1
        best_frame = frame
        
        other = 1
        while other <= actual_frames
            if abs(other - frame) > 5
                val = Get value in cell: frame, other
                if val > best_sim
                    best_sim = val
                    best_frame = other
                endif
            endif
            other = other + 5
        endwhile
        
        source_start = round((best_frame - 1) * time_step * sr) + 1
        target_start = round((frame - 1) * time_step * sr) + 1
        
        selectObject: workingID
        numSamples = Get number of samples
        for s from 1 to frame_samples
            if source_start + s <= numSamples and target_start + s <= numSamples
                val = Get value at sample number: 1, source_start + s
                selectObject: outID
                Set value at sample number: 1, target_start + s, val * 0.7
                selectObject: workingID
            endif
        endfor
        
        frame = frame + 1
    endwhile
    
    if targetSR > 0 and origSR > targetSR
        selectObject: outID
        Resample: origSR, 50
        upsampledID = selected("Sound")
        removeObject: outID
        outID = upsampledID
    endif
    
else
    # === FAST ENVELOPE CREATION ===
    # Use ORIGINAL duration, not downsampled duration!
    envRate = 100
    envDuration = origDur  
	# <-- CHANGED from 'duration'
    envFrames = round(envDuration * envRate)
    
    Create Sound from formula: "Envelope", 1, 0, envDuration, envRate, "0"
    envSound = selected("Sound")
    
    # Fill envelope
    selectObject: envSound
    for i from 1 to envFrames
        t = (i - 0.5) / envRate
        frameIdx = round(t / time_step) + 1
        frameIdx = max(1, min(actual_frames, frameIdx))
        
        selectObject: gainID
        db = Get value in cell: frameIdx, 1
        lin = 10 ^ (db / 20)
        
        selectObject: envSound
        Set value at sample number: 1, i, lin
    endfor
    
    # Resample envelope to ORIGINAL sample rate
    selectObject: envSound
    Resample: origSR, 50  
	# <-- CHANGED from 'sr'
    envResampled = selected("Sound")
    selectObject: envResampled
    envName$ = selected$("Sound")
    removeObject: envSound
    
    # Prepare source sound
    if targetSR > 0 and origSR > targetSR
        selectObject: originalID
        Resample: origSR, 50
        sourceSound = selected("Sound")
    else
        selectObject: originalID
        Copy: "source"
        sourceSound = selected("Sound")
    endif
    
    # === SPATIAL PROCESSING (OPTIMIZED) ===
    
    if spatial_mode = 1
        # MONO
        appendInfo: " [mono]... "
        
        selectObject: sourceSound
        if num_channels > 1
            Convert to mono
            monoSource = selected("Sound")
            removeObject: sourceSound
            sourceSound = monoSource
        endif
        
        selectObject: sourceSound
        Formula: "self * Sound_'envName$'[]"
        outID = selected("Sound")
        
        removeObject: envResampled
        
    elsif spatial_mode = 2
        # PRESERVE STEREO
        appendInfo: " [preserve stereo]... "
        
        selectObject: sourceSound
        Formula: "self * Sound_'envName$'[]"
        outID = selected("Sound")
        
        removeObject: envResampled
        
    elsif spatial_mode = 3
        # STEREO WIDE
        appendInfo: " [stereo wide]... "
        
        if wasStereo
            selectObject: sourceSound
            Extract left channel
            leftSource = selected("Sound")
            
            selectObject: sourceSound
            Extract right channel
            rightSource = selected("Sound")
        else
            selectObject: sourceSound
            Copy: "left"
            leftSource = selected("Sound")
            
            selectObject: sourceSound
            Copy: "right"
            rightSource = selected("Sound")
        endif
        
        # Left: boost low-mid
        selectObject: leftSource
        Formula: "self * Sound_'envName$'[] * (1 + 0.3 * exp(-x * 5))"
        leftProcessed = selected("Sound")
        
        # Right: boost high-mid  
        selectObject: rightSource
        Formula: "self * Sound_'envName$'[] * (1 + 0.3 * (1 - exp(-x * 5)))"
        rightProcessed = selected("Sound")
        
        selectObject: leftProcessed
        plusObject: rightProcessed
        Combine to stereo
        outID = selected("Sound")
        
        removeObject: sourceSound, leftSource, rightSource, envResampled
        
    elsif spatial_mode = 4
        # ROTATING
        appendInfo: " [rotating]... "
        
        if wasStereo
            selectObject: sourceSound
            Convert to mono
            monoSource = selected("Sound")
            removeObject: sourceSound
        else
            monoSource = sourceSound
        endif
        
        selectObject: monoSource
        Copy: "temp"
        tempSound = selected("Sound")
        
        selectObject: tempSound
        Formula: "self * Sound_'envName$'[]"
        
        selectObject: tempSound
        Copy: "left"
        leftSound = selected("Sound")
        Formula: "self * (0.6 + 0.4 * cos(2 * pi * 0.2 * x))"
        
        selectObject: tempSound
        Copy: "right"
        rightSound = selected("Sound")
        Formula: "self * (0.6 + 0.4 * sin(2 * pi * 0.2 * x))"
        
        selectObject: leftSound
        plusObject: rightSound
        Combine to stereo
        outID = selected("Sound")
        
        removeObject: monoSource, tempSound, leftSound, rightSound, envResampled
        
    elsif spatial_mode = 5
        # MID-SIDE
        appendInfo: " [mid-side]... "
        
        if wasStereo
            selectObject: sourceSound
            Copy: "working"
            workingCopy = selected("Sound")
            
            # Apply envelope weighted by channel
            selectObject: workingCopy
            Formula: "self * (0.5 + 0.5 * Sound_'envName$'[])"
            
            outID = workingCopy
            removeObject: sourceSound
        else
            selectObject: sourceSound
            Formula: "self * Sound_'envName$'[]"
            outID = selected("Sound")
        endif
        
        removeObject: envResampled
    endif
endif

selectObject: outID
Rename: originalName$ + "_similarity_" + presetName$

appendInfoLine: "done"

# ============================================================
# FINALIZE
# ============================================================
selectObject: outID

if normalize_output
    Scale peak: 0.95
endif

if output_gain <> 0
    Scale: 10 ^ (output_gain / 20)
endif

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing..."
    
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    stereoLabel$ = ""
    if wasStereo or spatial_mode > 2
        stereoLabel$ = " [STEREO]"
    endif
    Text: 0.5, "centre", 0.5, "half", "Self-Similarity: " + originalName$ + stereoLabel$ + " [" + creative_mode$ + "]"
    
    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.5, 3.7, 0.7, 1.4
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.5, 7.7, 0.7, 1.4
    selectObject: outID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Processed"
    
    Select outer viewport: 0, 4, 1.7, 3.7
    Select inner viewport: 0.5, 3.7, 1.8, 3.6
    
    Axes: 0, actual_frames, 0, actual_frames
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actual_frames, 0, actual_frames
    
    selectObject: ssmID
    cell_size = 20
    
    row = 1
    while row <= actual_frames
        col = 1
        while col <= actual_frames
            val = Get value in cell: row, col
            gray = 1 - val
            gray = max(0, min(1, gray))
            Paint rectangle: "{" + fixed$(gray, 2) + ", " + fixed$(gray, 2) + ", " + fixed$(gray, 2) + "}", row, row + cell_size, col, col + cell_size
            col = col + cell_size
        endwhile
        row = row + cell_size
    endwhile
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Self-Similarity Matrix"
    Text left: "yes", "Frame"
    Text bottom: "yes", "Frame"
    
    Select outer viewport: 4, 8, 1.7, 3.7
    Select inner viewport: 4.5, 7.7, 1.8, 3.6
    
    selectObject: scoreID
    minS = Get minimum
    maxS = Get maximum
    
    Axes: 0, actual_frames, minS * 1.1, maxS * 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actual_frames, minS * 1.1, maxS * 1.1
    
    Colour: "{0.6, 0.3, 0.7}"
    Line width: 2
    
    frame = 1
    while frame < actual_frames
        val1 = Get value in cell: frame, 1
        next_frame = frame + 5
        if next_frame > actual_frames
            next_frame = actual_frames
        endif
        val2 = Get value in cell: next_frame, 1
        Draw line: frame, val1, next_frame, val2
        frame = next_frame
    endwhile
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Similarity Scores"
    Text left: "yes", "Score"
    Text bottom: "yes", "Frame"
    
    Select outer viewport: 0, 8, 3.9, 4.4
    Select inner viewport: 0.5, 7.7, 3.95, 4.35
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", speedStr$ + " | " + spatial_mode$ + " | Time: " + fixed$(processingTime, 2) + "s | Frames: " + string$(actual_frames)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: normalizedID, ssmID, scoreID, gainID

if analysisID <> originalID
    removeObject: analysisID
endif
if workingID <> analysisID
    removeObject: workingID
endif

selectObject: outID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    selectObject: outID
    Play
endif

selectObject: originalID
