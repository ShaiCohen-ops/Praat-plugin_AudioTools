# ============================================================
# Praat AudioTools - Self_Attention_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Self-attention based audio chunk recomposer.
#   Segments audio into chunks, computes MFCC embeddings,
#   and uses a self-attention mechanism to generate a new
#   chunk ordering based on spectral similarity.
#
#   Architecture:
#   1. Segment audio (fixed-length or silence-based)
#   2. Compute MFCC embedding per chunk (mean +/- variance)
#   3. Z-score + L2 normalize embeddings
#   4. Self-attention ordering with softmax, temperature,
#      topK/topP, and configurable selection modes
#   5. Reconstruct audio with crossfades
#
# Category: Composition
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Self-Attention Recomposer v1.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Smooth Flow (sustained sounds)
        option Jumpy Mosaic (percussive)
        option Exploratory (sampling + variance)
        option Strict Permutation (greedy, no repeats)
    comment === Segmentation ===
    boolean Use_silence_segmentation 0
    positive Chunk_duration_s 0.20
    positive Min_chunk_duration_s 0.05
    comment === Attention ===
    real Temperature 1.0
    optionmenu Context_mode: 1
        option Last chunk
        option Mean of last N
        option Exponential moving average
    optionmenu Selection_mode: 1
        option Greedy (argmax)
        option Sampling
    boolean Permutation_mode 1
    integer Output_length_chunks 0
    comment === Start and Output ===
    optionmenu Start_mode: 1
        option First chunk
        option Random chunk
        option Highest energy chunk
    positive Fade_duration_s 0.01
    boolean Draw_visualization 1
endform

# Defaults for parameters removed from form
num_coefficients = 13
mfcc_window_s = 0.025
mfcc_step_s = 0.010
max_frequency_Hz = 5000
use_variance = 0
context_window = 4
ema_alpha = 0.7
top_k = 0
top_p = 0
use_centroid_pick = 0
repeat_penalty = 2.0
near_dup_penalty = 0.5
use_time_decay = 0
time_tau = 1.0
silence_threshold_dB = -25
min_silence_duration_s = 0.10

# Apply presets
if preset = 2
    # Smooth Flow
    chunk_duration_s = 0.30
    temperature = 0.5
    context_mode = 3
    ema_alpha = 0.8
    selection_mode = 1
    near_dup_penalty = 0.3
    use_time_decay = 1
    time_tau = 2.0
    permutation_mode = 1
elsif preset = 3
    # Jumpy Mosaic
    chunk_duration_s = 0.15
    temperature = 1.5
    context_mode = 1
    selection_mode = 2
    near_dup_penalty = 0.8
    permutation_mode = 1
elsif preset = 4
    # Exploratory
    chunk_duration_s = 0.20
    temperature = 1.2
    context_mode = 2
    context_window = 6
    selection_mode = 2
    use_variance = 1
    top_k = 5
    permutation_mode = 0
    output_length_chunks = 0
    repeat_penalty = 1.5
elsif preset = 5
    # Strict Permutation
    chunk_duration_s = 0.25
    temperature = 0.3
    context_mode = 1
    selection_mode = 1
    near_dup_penalty = 0.5
    permutation_mode = 1
endif

# ============================================================
# Setup
# ============================================================
selectObject: originalSound
totalDur = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

if use_variance
    embDim = num_coefficients * 2
else
    embDim = num_coefficients
endif

if temperature < 0.01
    temperature = 0.01
endif
if ema_alpha < 0.1
    ema_alpha = 0.1
endif
if ema_alpha > 0.99
    ema_alpha = 0.99
endif
if time_tau < 0.01
    time_tau = 0.01
endif

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  Self-Attention Recomposer v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$, " (", fixed$(totalDur, 2), " s, ", sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: ""

# ============================================================
# STEP 1: Create TextGrid
# ============================================================
appendInfoLine: "[1/7] Creating TextGrid..."

if use_silence_segmentation
    selectObject: originalSound
    To TextGrid (silences): 100, 0, silence_threshold_dB,
        ... min_silence_duration_s, min_chunk_duration_s, "sil", "snd"
    textGrid = selected("TextGrid")
    Rename: "auto_chunks"
    appendInfoLine: "  Method: silence-based (threshold: ", silence_threshold_dB, " dB)"
else
    selectObject: originalSound
    startTime = Get start time
    endTime = Get end time
    
    To TextGrid: "chunks", ""
    textGrid = selected("TextGrid")
    Rename: "auto_chunks"
    
    boundaryTime = startTime + chunk_duration_s
    while boundaryTime < endTime - 0.001
        Insert boundary: 1, boundaryTime
        boundaryTime = boundaryTime + chunk_duration_s
    endwhile
    
    appendInfoLine: "  Method: fixed-length (", fixed$(chunk_duration_s * 1000, 0), " ms)"
endif

selectObject: textGrid
nIntervals = Get number of intervals: 1
appendInfoLine: "  Intervals: ", nIntervals

# ============================================================
# STEP 2: Enumerate valid chunks
# ============================================================
appendInfoLine: "[2/7] Enumerating chunks..."

nChunks = 0

for i from 1 to nIntervals
    selectObject: textGrid
    iStart = Get start time of interval: 1, i
    iEnd = Get end time of interval: 1, i
    iDur = iEnd - iStart
    iLabel$ = Get label of interval: 1, i
    
    skipThis = 0
    if use_silence_segmentation and iLabel$ = "sil"
        skipThis = 1
    endif
    if iDur < min_chunk_duration_s
        skipThis = 1
    endif
    
    if skipThis = 0
        nChunks = nChunks + 1
        chunkStart_'nChunks' = iStart
        chunkEnd_'nChunks' = iEnd
        chunkDur_'nChunks' = iDur
        chunkMid_'nChunks' = (iStart + iEnd) / 2
    endif
endfor

if nChunks < 2
    exitScript: "Need at least 2 valid chunks. Found: " + string$(nChunks)
        ... + newline$ + "Try shorter chunk_duration_s or lower min_chunk_duration_s."
endif

# Determine output length
if output_length_chunks > 0
    outputLength = output_length_chunks
    permutation_mode = 0
else
    outputLength = nChunks
endif

appendInfoLine: "  Valid chunks: ", nChunks
appendInfoLine: "  Output length: ", outputLength
if permutation_mode
    appendInfoLine: "  Mode: permutation (each chunk once)"
else
    appendInfoLine: "  Mode: repeats allowed"
endif
appendInfoLine: ""

# ============================================================
# STEP 3: MFCC embeddings
# ============================================================
appendInfoLine: "[3/7] Computing MFCC embeddings..."

for i from 1 to nChunks
    selectObject: originalSound
    Extract part: chunkStart_'i', chunkEnd_'i', "rectangular", 1, "no"
    chunkSound = selected("Sound")
    
    # Mono if needed
    chCh = Get number of channels
    if chCh > 1
        chunkMono = Convert to mono
        removeObject: chunkSound
        chunkSound = chunkMono
    endif
    
    # RMS for start mode 3
    selectObject: chunkSound
    rms_'i' = Get root-mean-square: 0, 0
    
    # Check duration
    selectObject: chunkSound
    chDur = Get total duration
    
    if chDur < mfcc_window_s * 1.5
        # Too short for MFCC
        for d from 1 to embDim
            emb_'i'_'d' = 0
        endfor
        removeObject: chunkSound
    else
        selectObject: chunkSound
        To MelSpectrogram: mfcc_window_s, mfcc_step_s, 24, 100, max_frequency_Hz
        melSpec = selected("MelSpectrogram")
        
        To MFCC: num_coefficients
        mfcc = selected("MFCC")
        
        selectObject: mfcc
        nFrames = Get number of frames
        
        # Mean per coefficient
        for d from 1 to num_coefficients
            coeffSum = 0
            for fr from 1 to nFrames
                selectObject: mfcc
                val = Get value in frame: fr, d
                if val = undefined
                    val = 0
                endif
                coeffSum = coeffSum + val
            endfor
            emb_'i'_'d' = coeffSum / nFrames
        endfor
        
        # Variance if requested
        if use_variance
            for d from 1 to num_coefficients
                varSum = 0
                meanVal = emb_'i'_'d'
                for fr from 1 to nFrames
                    selectObject: mfcc
                    val = Get value in frame: fr, d
                    if val = undefined
                        val = 0
                    endif
                    varSum = varSum + (val - meanVal) * (val - meanVal)
                endfor
                vIdx = num_coefficients + d
                emb_'i'_'vIdx' = varSum / nFrames
            endfor
        endif
        
        removeObject: chunkSound, melSpec, mfcc
    endif
    
    # Progress
    if i mod 10 = 0
        appendInfoLine: "  ", i, "/", nChunks, " chunks embedded"
    endif
endfor

appendInfoLine: "  Embedding dim: ", embDim
appendInfoLine: ""

# ============================================================
# STEP 4: Normalize embeddings
# ============================================================
appendInfoLine: "[4/7] Normalizing embeddings..."

# Z-score per dimension
for d from 1 to embDim
    dimMean = 0
    for i from 1 to nChunks
        dimMean = dimMean + emb_'i'_'d'
    endfor
    dimMean = dimMean / nChunks
    
    dimVar = 0
    for i from 1 to nChunks
        diff = emb_'i'_'d' - dimMean
        dimVar = dimVar + diff * diff
    endfor
    dimVar = dimVar / nChunks
    dimStd = sqrt(dimVar)
    if dimStd < 1e-10
        dimStd = 1e-10
    endif
    
    for i from 1 to nChunks
        emb_'i'_'d' = (emb_'i'_'d' - dimMean) / dimStd
    endfor
endfor

# L2 normalize per chunk
for i from 1 to nChunks
    l2norm = 0
    for d from 1 to embDim
        l2norm = l2norm + emb_'i'_'d' * emb_'i'_'d'
    endfor
    l2norm = sqrt(l2norm)
    if l2norm < 1e-10
        l2norm = 1e-10
    endif
    for d from 1 to embDim
        emb_'i'_'d' = emb_'i'_'d' / l2norm
    endfor
endfor

appendInfoLine: "  Z-score + L2 normalization complete"
appendInfoLine: ""

# ============================================================
# STEP 5: Self-attention ordering
# ============================================================
appendInfoLine: "[5/7] Self-attention ordering..."

# Initialize tracking arrays
for i from 1 to nChunks
    unused_'i' = 1
    useCount_'i' = 0
endfor

# Choose starting chunk
if start_mode = 2
    currentIdx = randomInteger(1, nChunks)
elsif start_mode = 3
    bestRMS = rms_1
    currentIdx = 1
    for i from 2 to nChunks
        if rms_'i' > bestRMS
            bestRMS = rms_'i'
            currentIdx = i
        endif
    endfor
else
    currentIdx = 1
endif

order_1 = currentIdx
unused_'currentIdx' = 0
useCount_'currentIdx' = useCount_'currentIdx' + 1
consecSim_1 = 0

# Initialize query
for d from 1 to embDim
    query_'d' = emb_'currentIdx'_'d'
endfor

totalEntropy = 0
totalConsecSim = 0

# Main attention loop
for t from 2 to outputLength
    
    # Compute attention scores
    for i from 1 to nChunks
        score_'i' = 0
        for d from 1 to embDim
            score_'i' = score_'i' + query_'d' * emb_'i'_'d'
        endfor
        
        # Time decay
        if use_time_decay
            timeDist = chunkMid_'i' - chunkMid_'currentIdx'
            if timeDist < 0
                timeDist = -timeDist
            endif
            score_'i' = score_'i' - timeDist / time_tau
        endif
        
        # Permutation: mask used chunks
        if permutation_mode
            if unused_'i' = 0
                score_'i' = -999
            endif
        else
            score_'i' = score_'i' - repeat_penalty * useCount_'i'
        endif
        
        # Near-duplicate penalty
        nearDupSim = 0
        for d from 1 to embDim
            nearDupSim = nearDupSim + emb_'currentIdx'_'d' * emb_'i'_'d'
        endfor
        score_'i' = score_'i' - near_dup_penalty * nearDupSim
    endfor
    
    # TopK filtering
    if top_k > 0 and top_k < nChunks
        for kk from 1 to nChunks
            topkFlag_'kk' = 0
        endfor
        for kk from 1 to top_k
            bestVal = -99999
            bestKidx = 1
            for i from 1 to nChunks
                if topkFlag_'i' = 0 and score_'i' > bestVal
                    bestVal = score_'i'
                    bestKidx = i
                endif
            endfor
            topkFlag_'bestKidx' = 1
        endfor
        for i from 1 to nChunks
            if topkFlag_'i' = 0
                score_'i' = -999
            endif
        endfor
    endif
    
    # Stable softmax with temperature
    maxScore = -99999
    for i from 1 to nChunks
        if score_'i' > maxScore
            maxScore = score_'i'
        endif
    endfor
    
    sumExp = 0
    for i from 1 to nChunks
        weight_'i' = exp((score_'i' - maxScore) / temperature)
        sumExp = sumExp + weight_'i'
    endfor
    if sumExp < 1e-30
        sumExp = 1e-30
    endif
    for i from 1 to nChunks
        weight_'i' = weight_'i' / sumExp
    endfor
    
    # TopP (nucleus) filtering
    if top_p > 0 and top_p < 1
        for i from 1 to nChunks
            topPflag_'i' = 0
        endfor
        cumProb = 0
        tpDone = 0
        while tpDone = 0
            bestVal = -1
            bestPidx = 1
            for i from 1 to nChunks
                if topPflag_'i' = 0 and weight_'i' > bestVal
                    bestVal = weight_'i'
                    bestPidx = i
                endif
            endfor
            topPflag_'bestPidx' = 1
            cumProb = cumProb + weight_'bestPidx'
            if cumProb >= top_p
                tpDone = 1
            endif
            if bestVal <= 0
                tpDone = 1
            endif
        endwhile
        
        newSum = 0
        for i from 1 to nChunks
            if topPflag_'i' = 0
                weight_'i' = 0
            endif
            newSum = newSum + weight_'i'
        endfor
        if newSum > 1e-30
            for i from 1 to nChunks
                weight_'i' = weight_'i' / newSum
            endfor
        endif
    endif
    
    # Entropy for diagnostics
    stepEntropy = 0
    for i from 1 to nChunks
        if weight_'i' > 1e-10
            stepEntropy = stepEntropy - weight_'i' * ln(weight_'i')
        endif
    endfor
    totalEntropy = totalEntropy + stepEntropy
    
    # Selection
    chosenIdx = 1
    
    if use_centroid_pick
        for d from 1 to embDim
            centroid_'d' = 0
            for i from 1 to nChunks
                centroid_'d' = centroid_'d' + weight_'i' * emb_'i'_'d'
            endfor
        endfor
        bestDot = -99999
        for i from 1 to nChunks
            if weight_'i' > 1e-10
                dotVal = 0
                for d from 1 to embDim
                    dotVal = dotVal + centroid_'d' * emb_'i'_'d'
                endfor
                if dotVal > bestDot
                    bestDot = dotVal
                    chosenIdx = i
                endif
            endif
        endfor
    elsif selection_mode = 1
        bestWeight = -1
        for i from 1 to nChunks
            if weight_'i' > bestWeight
                bestWeight = weight_'i'
                chosenIdx = i
            endif
        endfor
    else
        r = randomUniform(0, 1)
        cumSum = 0
        found = 0
        for i from 1 to nChunks
            if found = 0
                cumSum = cumSum + weight_'i'
                if cumSum >= r
                    chosenIdx = i
                    found = 1
                endif
            endif
        endfor
    endif
    
    # Record
    order_'t' = chosenIdx
    unused_'chosenIdx' = 0
    useCount_'chosenIdx' = useCount_'chosenIdx' + 1
    
    # Consecutive similarity
    pci = order_'t' - 1
    # Fix: get previous order entry
    prevT = t - 1
    pci = order_'prevT'
    consecSim = 0
    for d from 1 to embDim
        consecSim = consecSim + emb_'chosenIdx'_'d' * emb_'pci'_'d'
    endfor
    consecSim_'t' = consecSim
    totalConsecSim = totalConsecSim + consecSim
    
    # Update state
    currentIdx = chosenIdx
    
    # Update query
    if context_mode = 1
        for d from 1 to embDim
            query_'d' = emb_'chosenIdx'_'d'
        endfor
    elsif context_mode = 2
        ctxStart = t - context_window + 1
        if ctxStart < 1
            ctxStart = 1
        endif
        ctxCount = t - ctxStart + 1
        for d from 1 to embDim
            query_'d' = 0
        endfor
        for ct from ctxStart to t
            ctIdx = order_'ct'
            for d from 1 to embDim
                ev = emb_'ctIdx'_'d'
                query_'d' = query_'d' + ev
            endfor
        endfor
        for d from 1 to embDim
            query_'d' = query_'d' / ctxCount
        endfor
    else
        for d from 1 to embDim
            query_'d' = ema_alpha * emb_'chosenIdx'_'d' + (1 - ema_alpha) * query_'d'
        endfor
    endif
    
    # Progress
    if t mod 20 = 0
        appendInfoLine: "  Step ", t, "/", outputLength
    endif
endfor

appendInfoLine: "  Ordering complete"
appendInfoLine: ""

# ============================================================
# STEP 6: Audio reconstruction
# ============================================================
appendInfoLine: "[6/7] Reconstructing audio..."

for t from 1 to outputLength
    idx = order_'t'
    selectObject: originalSound
    Extract part: chunkStart_'idx', chunkEnd_'idx', "rectangular", 1, "no"
    chunkSnd_'t' = selected("Sound")
    
    selectObject: chunkSnd_'t'
    chkDur = Get total duration
    fadeDur = fade_duration_s
    if fadeDur > chkDur / 2
        fadeDur = chkDur / 2
    endif
    
    # Fade in
    Formula: "if x - xmin < fadeDur then self * ((x - xmin) / fadeDur) else self fi"
    
    # Fade out
    Formula: "if xmax - x < fadeDur then self * ((xmax - x) / fadeDur) else self fi"
endfor

# Concatenate all
selectObject: chunkSnd_1
for t from 2 to outputLength
    plusObject: chunkSnd_'t'
endfor
Concatenate
finalOutput = selected("Sound")
Rename: "attn_variation"

# Remove temp chunks
for t from 1 to outputLength
    removeObject: chunkSnd_'t'
endfor

selectObject: finalOutput
outputDur = Get total duration

appendInfoLine: "  Output: ", fixed$(outputDur, 2), " s"
appendInfoLine: ""

# ============================================================
# STEP 7: Diagnostics
# ============================================================
appendInfoLine: "[7/7] Diagnostics..."

if outputLength > 1
    avgConsecSim = totalConsecSim / (outputLength - 1)
    avgEntropy = totalEntropy / (outputLength - 1)
else
    avgConsecSim = 0
    avgEntropy = 0
endif

appendInfoLine: "  Avg consecutive similarity: ", fixed$(avgConsecSim, 4)
appendInfoLine: "  Avg attention entropy: ", fixed$(avgEntropy, 4)
appendInfoLine: ""

# Print order
orderStr$ = ""
for t from 1 to outputLength
    idx = order_'t'
    orderStr$ = orderStr$ + string$(idx)
    if t < outputLength
        orderStr$ = orderStr$ + "->"
    endif
    # Wrap long lines
    if t mod 20 = 0 and t < outputLength
        appendInfoLine: "  ", orderStr$
        orderStr$ = ""
    endif
endfor
if orderStr$ <> ""
    appendInfoLine: "  ", orderStr$
endif

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half",
        ... "##Self-Attention Recomposer v1.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half",
        ... originalName$ + " | " + string$(nChunks) + " chunks | T=" + fixed$(temperature, 2)
    
    # === ORIGINAL WAVEFORM + CHUNK BOUNDARIES ===
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.6, 7.7, 0.7, 1.6
    selectObject: originalSound
    Colour: "{0.5, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "{0.8, 0.3, 0.3}"
    Dotted line
    for i from 2 to nChunks
        cs = chunkStart_'i'
        Draw line: cs, -0.9, cs, 0.9
    endfor
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text top: "no", "Original (" + string$(nChunks) + " chunks)"
    
    # === CHUNK ORDER PLOT ===
    Select outer viewport: 0, 8, 1.8, 3.4
    Select inner viewport: 0.6, 7.7, 1.9, 3.3
    Axes: 1, outputLength, 0, nChunks + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 1, outputLength, 0, nChunks + 1
    
    # Path lines
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 1.5
    for t from 1 to outputLength - 1
        tNext = t + 1
        idx1 = order_'t'
        idx2 = order_'tNext'
        Draw line: t, idx1, tNext, idx2
    endfor
    Line width: 1
    
    # Dots
    Colour: "{0.8, 0.3, 0.3}"
    for t from 1 to outputLength
        idx = order_'t'
        Paint circle (mm): "{0.8, 0.3, 0.3}", t, idx, 1.2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Chunk #"
    Text bottom: "yes", "Step"
    Text top: "no", "Attention Order Path"
    
    # === CONSECUTIVE SIMILARITY ===
    Select outer viewport: 0, 8, 3.5, 4.7
    Select inner viewport: 0.6, 7.7, 3.6, 4.6
    
    # Find range
    if outputLength > 2
        minSim = consecSim_2
        maxSim = consecSim_2
        for t from 3 to outputLength
            if consecSim_'t' < minSim
                minSim = consecSim_'t'
            endif
            if consecSim_'t' > maxSim
                maxSim = consecSim_'t'
            endif
        endfor
        simRange = maxSim - minSim
        if simRange < 0.01
            simRange = 0.01
        endif
        
        Axes: 2, outputLength, minSim - simRange * 0.1, maxSim + simRange * 0.1
        Paint rectangle: "{0.97, 0.97, 0.97}",
            ... 2, outputLength, minSim - simRange * 0.1, maxSim + simRange * 0.1
        
        # Similarity line
        Colour: "{0.2, 0.6, 0.4}"
        Line width: 1.5
        for t from 2 to outputLength - 1
            tNext = t + 1
            Draw line: t, consecSim_'t', tNext, consecSim_'tNext'
        endfor
        Line width: 1
        
        # Average line
        Colour: "{0.7, 0.7, 0.7}"
        Dotted line
        Draw line: 2, avgConsecSim, outputLength, avgConsecSim
        Solid line
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Sim"
    Text top: "no", "Consecutive Similarity (avg: " + fixed$(avgConsecSim, 3) + ")"
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 4.8, 5.8
    Select inner viewport: 0.6, 7.7, 4.9, 5.7
    selectObject: finalOutput
    Colour: "{0.4, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output: attn_variation (" + fixed$(outputDur, 2) + " s)"
    
    # === STATS PANEL ===
    Select outer viewport: 0, 8, 5.9, 6.7
    Select inner viewport: 0.6, 7.7, 6.0, 6.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Recomposer Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    
    if context_mode = 1
        ctxLabel$ = "Last chunk"
    elsif context_mode = 2
        ctxLabel$ = "Mean-" + string$(context_window)
    else
        ctxLabel$ = "EMA-" + fixed$(ema_alpha, 1)
    endif
    
    if selection_mode = 1
        selLabel$ = "Greedy"
    else
        selLabel$ = "Sampling"
    endif
    
    Text: 0.02, "left", 0.62, "half",
        ... string$(nChunks) + " chunks -> " + string$(outputLength)
        ... + " steps | MFCC dim: " + string$(embDim) + " | T=" + fixed$(temperature, 2)
    Text: 0.02, "left", 0.38, "half",
        ... "Context: " + ctxLabel$ + " | Select: " + selLabel$
        ... + " | NearDup: " + fixed$(near_dup_penalty, 1)
        ... + " | Entropy: " + fixed$(avgEntropy, 2)
    Text: 0.02, "left", 0.15, "half",
        ... "AvgSim: " + fixed$(avgConsecSim, 3)
        ... + " | TopK: " + string$(top_k) + " | TopP: " + fixed$(top_p, 1)
        ... + " | Fade: " + fixed$(fade_duration_s * 1000, 0) + "ms"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 6.75, 7.1
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.5, 0.5, 0.6}"
    Draw line: 0.05, 0.5, 0.09, 0.5
    Colour: "Black"
    Text: 0.10, "left", 0.5, "half", "Original"
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 1.5
    Draw line: 0.25, 0.5, 0.29, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.30, "left", 0.5, "half", "Order path"
    Colour: "{0.2, 0.6, 0.4}"
    Draw line: 0.48, 0.5, 0.52, 0.5
    Colour: "Black"
    Text: 0.53, "left", 0.5, "half", "Similarity"
    Colour: "{0.4, 0.6, 0.4}"
    Draw line: 0.70, 0.5, 0.74, 0.5
    Colour: "Black"
    Text: 0.75, "left", 0.5, "half", "Output"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Final selection
# ============================================================
removeObject: textGrid

selectObject: finalOutput
Play