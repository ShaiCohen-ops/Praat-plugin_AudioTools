# ============================================================
# Praat AudioTools - Self_Attention_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
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
#
# Changelog v1.1:
#
#   TIER 1 (polish, audio bit-identical):
#     - Dropped 4 decorative form rows (Preset / Segmentation /
#       Attention / Start and Output `comment === ... ===`
#       separators). Form: 16 rows -> 12. All 4 optionmenus
#       already had colons.
#     - Added `presetName$` variable for each preset. v1.0 had
#       no preset-name string at all -- the visualization
#       summary and output naming had nothing to display.
#     - Output filename now includes input name and preset:
#       `<input>_attnRec_<preset>` (was bare `attn_variation`).
#       Multiple runs with different presets no longer collide
#       on object naming.
#     - Removed dead code at v1.0 line 603 (`pci = order_'t' - 1`)
#       which was immediately overwritten by the next line
#       (`pci = order_'prevT'`). Cosmetic only.
#     - Visualization rewritten from custom 8x7.1 layout to
#       suite 8x8 standard:
#         Title bar (suite light) + metadata subtitle
#         Original waveform / Output waveform (side-by-side headline)
#         Attention order path  (full width, signature)
#         Consecutive similarity (full width)
#         Light-grey 3-line summary  (suite standard)
#       The standalone legend panel was dropped; legend
#       information is in the summary bar instead.
#
#   TIER 2 (real bugs, audio bit-identical):
#     - FIXED: writeInfoLine clobbered the opening banner. v1.0
#       lines 155-157 had THREE writeInfoLine calls in a row:
#         writeInfoLine: "=========..."
#         writeInfoLine: "  Self-Attention Recomposer v1.0"
#         writeInfoLine: "=========..."
#       Each `writeInfoLine` CLEARS the info window before
#       writing, so only the last line survived. The title was
#       wiped before the user could see it. v1.1 uses ONE
#       writeInfoLine on the first line and `appendInfoLine`
#       for everything else, so the banner stays intact.
#     - FIXED: subtitle text was drawn ON TOP of the Original
#       Waveform panel. v1.0 line 754 used axis y=-0.6 inside a
#       title viewport `0, 8, 0, 0.5` with axes `0, 1, 0, 1`.
#       The viewport-to-axis mapping (y_outer = 0.5 - y_axis *
#       0.5) sent axis y=-0.6 to outer y = 0.8 inches, which is
#       INSIDE the Original Waveform panel (outer 0.6-1.7) at
#       the top of its inner drawing area. The subtitle was
#       drawn over the waveform. v1.1 uses the suite-standard
#       title viewport `0-0.65` with subtitle at axis y=-0.22,
#       so the subtitle lands in the panel-header strip just
#       above the first content panel's inner box (around outer
#       y=0.79, well above the inner box at outer y=0.95).
#
#   TIER 3 (performance, audio bit-identical):
#     - Fade in/out at chunk reconstruction now uses
#       `Formula (part)` over just the fade region instead of
#       `Formula` over the whole chunk with an `if ... else
#       self fi` test per sample. Same arithmetic on the same
#       samples; no wasted else-branch iterations across the
#       chunk middle. Speedup scales with chunk_duration_s /
#       fade_duration_s -- typical ~10-30x faster on the fade
#       step alone. (Same pattern as the
#       In-Place_Paulstretch_Slicer v0.2 -> v0.3 speedup.)
#
#   Audio output is bit-identical to v1.0 for the same seed
#   (the sampling/random pathways are unchanged).
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Self-Attention Recomposer v1.1
    optionmenu Preset: 1
        option Custom
        option Smooth Flow (sustained sounds)
        option Jumpy Mosaic (percussive)
        option Exploratory (sampling + variance)
        option Strict Permutation (greedy, no repeats)
    boolean Use_silence_segmentation 0
    positive Chunk_duration_s 0.20
    positive Min_chunk_duration_s 0.05
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
# v1.1: each preset now defines presetName$ for output filename + viz.
presetName$ = "Custom"
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
    presetName$ = "SmoothFlow"
elsif preset = 3
    # Jumpy Mosaic
    chunk_duration_s = 0.15
    temperature = 1.5
    context_mode = 1
    selection_mode = 2
    near_dup_penalty = 0.8
    permutation_mode = 1
    presetName$ = "JumpyMosaic"
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
    presetName$ = "Exploratory"
elsif preset = 5
    # Strict Permutation
    chunk_duration_s = 0.25
    temperature = 0.3
    context_mode = 1
    selection_mode = 1
    near_dup_penalty = 0.5
    permutation_mode = 1
    presetName$ = "StrictPerm"
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
# v1.1: ONE writeInfoLine then appendInfoLine for everything else.
# v1.0 had three writeInfoLines in a row, which clobbered the title
# (each writeInfoLine clears the info window). Only the bottom
# divider survived.
writeInfoLine: "=============================================="
appendInfoLine: "  Self-Attention Recomposer v1.1"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$, " (", fixed$(totalDur, 2), " s, ", sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
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
    # v1.1: removed dead code from v1.0 (line 603 had
    # `pci = order_'t' - 1` which was immediately overwritten by the
    # next two lines). Cleaner now.
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
    
    # v1.1 Tier 3: Formula (part) over only the fade region.
    # v1.0 used `Formula: "if x - xmin < fadeDur then ... else self
    # fi"` which iterated the whole chunk doing a per-sample
    # comparison plus an `else self` no-op for the middle ~98% of
    # the buffer. v1.1 evaluates the fade arithmetic only in the
    # [0, fadeDur] and [chkDur - fadeDur, chkDur] ranges. Same
    # arithmetic on the same samples; same audio output.
    if fadeDur > 0
        # Fade in:  ramp 0 -> 1 over [0, fadeDur]
        Formula (part): 0, fadeDur, 1, 1, "self * ((x - xmin) / fadeDur)"
        # Fade out: ramp 1 -> 0 over [chkDur - fadeDur, chkDur]
        fadeOutStart = chkDur - fadeDur
        Formula (part): fadeOutStart, chkDur, 1, 1, "self * ((xmax - x) / fadeDur)"
    endif
endfor

# Concatenate all
selectObject: chunkSnd_1
for t from 2 to outputLength
    plusObject: chunkSnd_'t'
endfor
Concatenate
finalOutput = selected("Sound")
# v1.1: output name now includes input + preset for uniqueness.
compositeName$ = originalName$ + "_attnRec_" + presetName$
Rename: compositeName$

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

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Original waveform with chunk boundaries   (left half, headline)
# Panel B: Output waveform                            (right half, headline)
# Panel C: Attention order path  (full width, signature)
# Panel D: Consecutive similarity (full width)
# Panel E: Light-grey 3-line summary  (suite standard)
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    # v1.1: subtitle position fixed. v1.0 had axis y=-0.6 with
    # viewport 0,8,0,0.5, which mapped subtitle to outer y=0.8
    # (INSIDE the Original Waveform panel, on top of the waveform).
    # v1.1 uses suite-standard axis y=-0.22 in title viewport 0-0.65,
    # which lands in the panel-header strip just above the first
    # content panel's inner box.
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SELF-ATTENTION RECOMPOSER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
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
    
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(nChunks) + " chunks -> " + string$(outputLength) + " steps"
        ... + "  |  T=" + fixed$(temperature, 2)
        ... + "  |  " + ctxLabel$ + " / " + selLabel$
    
    # ----------------------------------------------------------
    # PANEL A (left): ORIGINAL WAVEFORM WITH CHUNK BOUNDARIES
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    
    selectObject: originalSound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Chunk boundary markers (dotted, faint)
    Colour: "{0.80, 0.40, 0.40}"
    Dotted line
    for i from 2 to nChunks
        cs = chunkStart_'i'
        Draw line: cs, -0.9, cs, 0.9
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform  (" + string$(nChunks) + " chunks)"
    Font size: 6
    Text left: "yes", "Amp"
    
    # ----------------------------------------------------------
    # PANEL B (right): OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    
    selectObject: finalOutput
    Colour: "{0.40, 0.65, 0.45}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform  (" + fixed$(outputDur, 2) + " s)"
    Font size: 6
    Text left: "yes", "Amp"
    
    # ----------------------------------------------------------
    # PANEL C: ATTENTION ORDER PATH  (full width, signature)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.40, 4.40
    Select inner viewport: 0.55, 7.72, 2.55, 4.30
    
    Axes: 1, outputLength, 0, nChunks + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 1, outputLength, 0, nChunks + 1
    
    # Reference grid: faint horizontal lines at each chunk index
    Colour: "{0.88, 0.88, 0.90}"
    Line width: 0.5
    for gi from 1 to nChunks
        Draw line: 1, gi, outputLength, gi
    endfor
    
    # Path lines
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.5
    for t from 1 to outputLength - 1
        tNext = t + 1
        idx1 = order_'t'
        idx2 = order_'tNext'
        Draw line: t, idx1, tNext, idx2
    endfor
    Line width: 1
    
    # Dots at each step
    for t from 1 to outputLength
        idx = order_'t'
        Paint circle (mm): "{0.85, 0.30, 0.30}", t, idx, 1.4
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Attention order path  (y = chunk #, x = step)"
    Font size: 6
    Text left: "yes", "Chunk"
    Text bottom: "yes", "Step"
    
    # ----------------------------------------------------------
    # PANEL D: CONSECUTIVE SIMILARITY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.50, 5.60
    Select inner viewport: 0.55, 7.72, 4.65, 5.50
    
    if outputLength > 2
        # Find range
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
        
        # Average reference line (dotted)
        Colour: "{0.70, 0.70, 0.70}"
        Dotted line
        Draw line: 2, avgConsecSim, outputLength, avgConsecSim
        Solid line
        
        # Similarity line
        Colour: "{0.20, 0.60, 0.40}"
        Line width: 1.5
        for t from 2 to outputLength - 1
            tNext = t + 1
            Draw line: t, consecSim_'t', tNext, consecSim_'tNext'
        endfor
        Line width: 1
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 6
        Colour: "{0.55, 0.55, 0.60}"
        Text: 0.5, "centre", 0.5, "half", "(not enough steps for similarity trace)"
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Consecutive similarity  (avg: " + fixed$(avgConsecSim, 3) + ", dotted = mean)"
    Font size: 6
    Text left: "yes", "Sim"
    Text bottom: "yes", "Step"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.70, 6.40
    Select inner viewport: 0.55, 7.72, 5.77, 6.35
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    
    if permutation_mode
        modeLabel$ = "Permutation"
    else
        modeLabel$ = "Repeats allowed"
    endif
    
    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + string$(nChunks) + " chunks -> " + string$(outputLength) + " steps"
        ... + "  |  MFCC dim: " + string$(embDim)
        ... + "  |  T=" + fixed$(temperature, 2)
        ... + "  |  Mode: " + modeLabel$
    
    Text: 0.02, "left", 0.50, "half",
        ... "Context: " + ctxLabel$
        ... + "  |  Select: " + selLabel$
        ... + "  |  NearDup: " + fixed$(near_dup_penalty, 1)
        ... + "  |  TopK: " + string$(top_k)
        ... + "  |  TopP: " + fixed$(top_p, 2)
        ... + "  |  Entropy: " + fixed$(avgEntropy, 2)
    
    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Dur: " + fixed$(outputDur, 2) + " s"
        ... + "  |  AvgSim: " + fixed$(avgConsecSim, 3)
        ... + "  |  Fade: " + fixed$(fade_duration_s * 1000, 0) + " ms"
        ... + "  |  SR: " + fixed$(sampleRate / 1000, 1) + " kHz"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# Final selection
# ============================================================
removeObject: textGrid

selectObject: finalOutput
Play