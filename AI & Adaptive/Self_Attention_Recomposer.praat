# ============================================================
# Praat AudioTools - Self_Attention_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
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
#   5. Reconstruct audio (fade-separated concatenation or
#      overlap crossfade, selectable)
#
# Category: Composition
#
# Changelog v1.3:
#
#   VISUALIZATION STANDARDIZATION ONLY (audio/DSP unchanged):
#     - Adopted the Praat AudioTools 8-inch page/grid convention with
#       explicit inner viewports and the standard 0.60-inch margins.
#     - Standardized title/subtitle hierarchy, typography, neutral
#       panel/summary colours, reference lines, and panel spacing.
#     - Aligned the two headline panels to an exact 4/4 split with a
#       wider central gutter for safe right-panel labels.
#     - Escaped underscores in Sound/object names before drawing text.
#     - Rebuilt the summary as three run-in suite-standard lines.
#     - Restores the full-page viewport at the end so Picture export
#       and clipboard operations capture the complete visualization.
#
# Changelog v1.2:
#
#   AUDIO-CHANGING FIXES:
#     - FIXED (stereo): chunk fades were applied with a hardcoded
#       channel range of `1, 1`, so on stereo input only the left
#       channel was faded. The right channel kept its rectangular
#       cut - clicks at every join and a momentary stereo-image
#       asymmetry. Fades now run over `1, numChannels`.
#     - FIXED (permutation): `Output_length_chunks > 0` silently set
#       `permutation_mode = 0` for ANY positive value, including
#       values well below nChunks. Asking for 20 of 100 chunks
#       without repeats returned repeats. Permutation is now only
#       dropped when the requested length exceeds the usable pool,
#       and that is reported.
#     - FIXED (permutation): "used" chunks were masked by setting
#       score = -999 and then passed through the softmax anyway.
#       Temperature is an unbounded `real` clamped only from below,
#       so the mask leaks: at T=1000 a used chunk carries ~15.5%
#       of the probability mass and Sampling mode repeats it.
#       Eligibility is now separate from score - ineligible chunks
#       get weight 0 exactly and normalization runs over the
#       eligible set only. TopK narrows eligibility instead of
#       writing -999 scores. All three selection paths (centroid,
#       greedy, sampling) check eligibility, and sampling falls
#       back to the last eligible chunk instead of index 1 on a
#       floating-point shortfall.
#     - FIXED (short chunks): a chunk shorter than 1.5 MFCC windows
#       got an all-zero embedding, which the per-dimension z-score
#       then turned into the specific direction [-mean/std, ...]
#       and L2 scaled to unit length. "No information" became an
#       artificial timbre with a definite position, shared by every
#       short chunk, so they attracted each other. The enumeration
#       minimum is now raised to the MFCC minimum, undefined MFCC
#       frames are skipped rather than counted as 0, chunks with no
#       analysable frames are excluded from the pool, and z-score
#       statistics are taken over valid embeddings only.
#
#   NEW CONTROLS (defaults preserve v1.1 behaviour):
#     - Random_seed: the script has two random pathways (Random
#       start chunk, Sampling selection) but v1.1 never seeded the
#       RNG and offered no seed field - the v1.1 changelog claimed
#       "bit-identical for the same seed" with no way to set one.
#       Seed 0 = unpredictable, as before.
#     - Chunk_join: v1.1 called the reconstruction "crossfades",
#       but it faded each chunk to zero at both ends and butt-joined
#       them - chunk A -> silence -> chunk B, with an amplitude dip
#       at every boundary and a per-chunk envelope. Default keeps
#       that (now named honestly as fade-separated concatenation);
#       option 2 does a real overlap crossfade.
#     - Renormalize_query: Mean and EMA queries were not L2
#       renormalized after update, so query LENGTH varied with the
#       coherence of recent history and the same Temperature gave a
#       sharper or flatter softmax depending on context. Preserved
#       by default (context disagreement raising exploration is a
#       reasonable musical behaviour); the option makes Temperature
#       mean the same thing at every step.
#
#   INTERFACE HONESTY:
#     - Temperature has no effect on Greedy ordering, because
#       argmax(softmax(s / T)) = argmax(s) for every T > 0. It only
#       moves the reported weights and entropy. Two presets
#       (Smooth Flow 0.5, Strict Permutation 0.3) are Greedy, so
#       their temperature values never reached the audio. The form
#       now says so and the info window repeats it at runtime.
#
#   NAMING:
#     - The mechanism is a query-updated MFCC similarity retrieval,
#       not a Transformer layer: no learned Q/K/V projections, no
#       chunk-by-chunk attention matrix, no value aggregation, no
#       multi-head. "Self-attention" is kept as compositional
#       language; for research presentation the accurate phrase is
#       self-attention-inspired autoregressive MFCC retrieval.
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
#   v1.1 audio was bit-identical to v1.0 (the sampling/random
#   pathways were unchanged) - though neither version let the user
#   set the seed that claim depends on. v1.2 does.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Self-Attention Recomposer v1.3
    optionmenu Preset: 1
        option Custom
        option Smooth Flow (sustained sounds)
        option Jumpy Mosaic (percussive)
        option Exploratory (sampling + variance)
        option Strict Permutation (greedy, no repeats)
    boolean Use_silence_segmentation 0
    positive Chunk_duration_s 0.20
    positive Min_chunk_duration_s 0.05
    comment Temperature affects Sampling mode only (Greedy is argmax-invariant)
    real Temperature 1.0
    optionmenu Context_mode: 1
        option Last chunk
        option Mean of last N
        option Exponential moving average
    boolean Renormalize_query 0
    optionmenu Selection_mode: 1
        option Greedy (argmax)
        option Sampling
    boolean Permutation_mode 1
    integer Output_length_chunks 0
    optionmenu Start_mode: 1
        option First chunk
        option Random chunk
        option Highest energy chunk
    optionmenu Chunk_join: 1
        option Fade-separated concatenation (v1.0/v1.1)
        option Crossfade (overlap-add)
    positive Fade_duration_s 0.01
    integer Random_seed 0
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

# v1.2 (item 7): the script has two random pathways - Random start chunk
# (randomInteger) and Sampling selection mode (randomUniform) - but v1.1
# never seeded the RNG and the form had no seed field, so the changelog
# claim "bit-identical for the same seed" was not something the user
# could actually exercise. Seed 0 = unpredictable (previous behaviour).
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
else
    random_initializeSafelyAndUnpredictably()
endif

# v1.2 (item 6): a chunk shorter than 1.5 MFCC windows cannot be
# analysed, and v1.1 gave it an all-zero embedding. That zero vector then
# went through the per-dimension z-score, which turned "no information"
# into the specific direction [-mean1/std1, -mean2/std2, ...], and L2
# normalization scaled it to unit length - an artificial timbre with a
# definite position in the space. Every too-short chunk got the SAME
# artificial vector, so they attracted each other strongly. The
# enumeration minimum is now raised to the MFCC minimum so such chunks
# never enter the pool.
mfccMinDur = mfcc_window_s * 1.5
minChunkEff = min_chunk_duration_s
if minChunkEff < mfccMinDur
    minChunkEff = mfccMinDur
endif

clearinfo
# v1.1: ONE writeInfoLine then appendInfoLine for everything else.
# v1.0 had three writeInfoLines in a row, which clobbered the title
# (each writeInfoLine clears the info window). Only the bottom
# divider survived.
writeInfoLine: "=============================================="
appendInfoLine: "  Self-Attention Recomposer v1.3"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", originalName$, " (", fixed$(totalDur, 2), " s, ", sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed: none (unpredictable)"
endif
if minChunkEff > min_chunk_duration_s
    appendInfoLine: "Min chunk duration raised to ", fixed$(minChunkEff * 1000, 1), " ms (MFCC analysis minimum)"
endif
appendInfoLine: ""

# ============================================================
# STEP 1: Create TextGrid
# ============================================================
appendInfoLine: "[1/7] Creating TextGrid..."

if use_silence_segmentation
    selectObject: originalSound
    To TextGrid (silences): 100, 0, silence_threshold_dB,
        ... min_silence_duration_s, minChunkEff, "sil", "snd"
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
    if iDur < minChunkEff
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

# Output length is decided after STEP 3, once embedding validity is known.
appendInfoLine: "  Valid chunks: ", nChunks
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
    
    if chDur < mfccMinDur
        # Should be unreachable now that enumeration enforces minChunkEff,
        # kept as a guard. Marked invalid rather than given a zero vector.
        embValid_'i' = 0
        for d from 1 to embDim
            emb_'i'_'d' = 0
        endfor
        removeObject: chunkSound
    else
        embValid_'i' = 1
        selectObject: chunkSound
        To MelSpectrogram: mfcc_window_s, mfcc_step_s, 24, 100, max_frequency_Hz
        melSpec = selected("MelSpectrogram")
        
        To MFCC: num_coefficients
        mfcc = selected("MFCC")
        
        selectObject: mfcc
        nFrames = Get number of frames
        
        # Mean per coefficient
        # v1.2 (item 6): an undefined frame value used to be replaced by 0
        # and averaged in, which is not "no data" - it drags the mean
        # toward zero in the RAW MFCC domain, and the later z-score turns
        # that into a definite direction. Undefined frames are now skipped
        # and the mean taken over the defined ones.
        nDefined = 0
        for d from 1 to num_coefficients
            coeffSum = 0
            nValid = 0
            for fr from 1 to nFrames
                selectObject: mfcc
                val = Get value in frame: fr, d
                if val <> undefined
                    coeffSum = coeffSum + val
                    nValid = nValid + 1
                endif
            endfor
            if nValid > 0
                emb_'i'_'d' = coeffSum / nValid
                nDefined = nDefined + 1
            else
                emb_'i'_'d' = 0
            endif
        endfor
        
        if nDefined = 0
            embValid_'i' = 0
        endif
        
        # Variance if requested
        if use_variance
            for d from 1 to num_coefficients
                varSum = 0
                nValid = 0
                meanVal = emb_'i'_'d'
                for fr from 1 to nFrames
                    selectObject: mfcc
                    val = Get value in frame: fr, d
                    if val <> undefined
                        varSum = varSum + (val - meanVal) * (val - meanVal)
                        nValid = nValid + 1
                    endif
                endfor
                vIdx = num_coefficients + d
                if nValid > 0
                    emb_'i'_'vIdx' = varSum / nValid
                else
                    emb_'i'_'vIdx' = 0
                endif
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

nUsable = 0
for i from 1 to nChunks
    if embValid_'i' = 1
        nUsable = nUsable + 1
    endif
endfor
if nUsable < nChunks
    appendInfoLine: "  WARNING: ", nChunks - nUsable, " chunk(s) had no analysable MFCC frames and are excluded"
endif
if nUsable < 2
    exitScript: "Need at least 2 chunks with valid MFCC embeddings. Found: " + string$(nUsable)
endif

# ------------------------------------------------------------
# Determine output length
# ------------------------------------------------------------
# v1.2 (item 3): v1.1 set `permutation_mode = 0` for ANY positive
# Output_length_chunks, so asking for 20 chunks out of 100 in permutation
# mode silently became "repeats allowed" - and so did asking for exactly
# nChunks. A shorter output is a PARTIAL permutation, which is perfectly
# well defined. Permutation is now only dropped when the request cannot
# be honoured (output longer than the usable pool), and that is reported.
if output_length_chunks > 0
    outputLength = output_length_chunks
    if permutation_mode and outputLength > nUsable
        permutation_mode = 0
        appendInfoLine: "  NOTE: output length ", outputLength, " exceeds ", nUsable, " usable chunks - permutation disabled, repeats allowed"
    endif
else
    outputLength = nUsable
endif

appendInfoLine: "  Output length: ", outputLength
if permutation_mode
    if outputLength < nUsable
        appendInfoLine: "  Mode: partial permutation (", outputLength, " of ", nUsable, ", each chunk at most once)"
    else
        appendInfoLine: "  Mode: permutation (each chunk once)"
    endif
else
    appendInfoLine: "  Mode: repeats allowed"
endif
appendInfoLine: ""

# ============================================================
# STEP 4: Normalize embeddings
# ============================================================
appendInfoLine: "[4/7] Normalizing embeddings..."

# Z-score per dimension
# v1.2: statistics are taken over VALID embeddings only, so an excluded
# chunk cannot shift the mean or inflate the standard deviation.
for d from 1 to embDim
    dimMean = 0
    for i from 1 to nChunks
        if embValid_'i' = 1
            dimMean = dimMean + emb_'i'_'d'
        endif
    endfor
    dimMean = dimMean / nUsable
    
    dimVar = 0
    for i from 1 to nChunks
        if embValid_'i' = 1
            diff = emb_'i'_'d' - dimMean
            dimVar = dimVar + diff * diff
        endif
    endfor
    dimVar = dimVar / nUsable
    dimStd = sqrt(dimVar)
    if dimStd < 1e-10
        dimStd = 1e-10
    endif
    
    for i from 1 to nChunks
        if embValid_'i' = 1
            emb_'i'_'d' = (emb_'i'_'d' - dimMean) / dimStd
        endif
    endfor
endfor

# L2 normalize per chunk
for i from 1 to nChunks
    if embValid_'i' = 1
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
    endif
endfor

appendInfoLine: "  Z-score + L2 normalization complete"
appendInfoLine: ""

# ============================================================
# STEP 5: Self-attention ordering
# ============================================================
appendInfoLine: "[5/7] Self-attention ordering..."

# v1.2 (item 5): argmax(softmax(s / T)) = argmax(s) for every T > 0, so
# Temperature cannot change the ORDER in Greedy mode - only the reported
# weights and entropy. Two presets (Smooth Flow 0.5, Strict Permutation
# 0.3) are Greedy, and their temperature values do not affect the audio.
# Said out loud rather than left as a silent no-op control.
if selection_mode = 1 and use_centroid_pick = 0
    appendInfoLine: "  Note: Greedy mode - Temperature (", fixed$(temperature, 2), ") affects reported weights/entropy only, not the ordering."
endif

# Initialize tracking arrays
for i from 1 to nChunks
    unused_'i' = 1
    useCount_'i' = 0
endfor

# Choose starting chunk (valid embeddings only)
firstValid = 0
for i from 1 to nChunks
    if embValid_'i' = 1
        if firstValid = 0
            firstValid = i
        endif
    endif
endfor

if start_mode = 2
    startPick = randomInteger(1, nUsable)
    seen = 0
    currentIdx = firstValid
    for i from 1 to nChunks
        if embValid_'i' = 1
            seen = seen + 1
            if seen = startPick
                currentIdx = i
            endif
        endif
    endfor
elsif start_mode = 3
    bestRMS = -1
    currentIdx = firstValid
    for i from 1 to nChunks
        if embValid_'i' = 1
            if rms_'i' > bestRMS
                bestRMS = rms_'i'
                currentIdx = i
            endif
        endif
    endfor
else
    currentIdx = firstValid
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
    
    # ------------------------------------------------------------
    # Eligibility (hard mask)
    # ------------------------------------------------------------
    # v1.2 (item 4): v1.1 expressed "this chunk may not be used" as a
    # score of -999 and then fed it through the softmax anyway. That is a
    # soft mask: the relative weight of a used chunk is exp(-1000/T), and
    # Temperature is an unbounded `real` field clamped only from below.
    # At T=100 the leak is ~2e-5 per step; at T=1000 it is ~0.155, so in
    # Sampling mode a "permutation" could repeat a chunk 15% of the time.
    # Eligibility is now separate from score: ineligible chunks get
    # weight 0 exactly, and normalization runs over the eligible set only.
    nEligible = 0
    lastEligible = 0
    for i from 1 to nChunks
        eligible_'i' = 1
        if embValid_'i' = 0
            eligible_'i' = 0
        endif
        if permutation_mode
            if unused_'i' = 0
                eligible_'i' = 0
            endif
        endif
        if eligible_'i' = 1
            nEligible = nEligible + 1
            lastEligible = i
        endif
    endfor
    
    if nEligible = 0
        exitScript: "No eligible chunks remain at step " + string$(t)
            ... + ". This should not happen - please report."
    endif
    
    # Compute attention scores (eligible chunks only)
    for i from 1 to nChunks
        score_'i' = 0
        if eligible_'i' = 1
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
            
            # Repeat penalty (only meaningful when repeats are allowed)
            if permutation_mode = 0
                score_'i' = score_'i' - repeat_penalty * useCount_'i'
            endif
            
            # Near-duplicate penalty
            nearDupSim = 0
            for d from 1 to embDim
                nearDupSim = nearDupSim + emb_'currentIdx'_'d' * emb_'i'_'d'
            endfor
            score_'i' = score_'i' - near_dup_penalty * nearDupSim
        endif
    endfor
    
    # TopK filtering - now narrows ELIGIBILITY, not the score
    if top_k > 0 and top_k < nEligible
        for kk from 1 to nChunks
            topkFlag_'kk' = 0
        endfor
        for kk from 1 to top_k
            bestVal = -1e30
            bestKidx = 0
            for i from 1 to nChunks
                if eligible_'i' = 1
                    if topkFlag_'i' = 0 and score_'i' > bestVal
                        bestVal = score_'i'
                        bestKidx = i
                    endif
                endif
            endfor
            if bestKidx > 0
                topkFlag_'bestKidx' = 1
            endif
        endfor
        nEligible = 0
        lastEligible = 0
        for i from 1 to nChunks
            if topkFlag_'i' = 0
                eligible_'i' = 0
            endif
            if eligible_'i' = 1
                nEligible = nEligible + 1
                lastEligible = i
            endif
        endfor
    endif
    
    # Stable softmax with temperature, over eligible chunks only
    maxScore = -1e30
    for i from 1 to nChunks
        if eligible_'i' = 1
            if score_'i' > maxScore
                maxScore = score_'i'
            endif
        endif
    endfor
    
    sumExp = 0
    for i from 1 to nChunks
        if eligible_'i' = 1
            weight_'i' = exp((score_'i' - maxScore) / temperature)
        else
            weight_'i' = 0
        endif
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
    chosenIdx = lastEligible
    
    if use_centroid_pick
        for d from 1 to embDim
            centroid_'d' = 0
            for i from 1 to nChunks
                centroid_'d' = centroid_'d' + weight_'i' * emb_'i'_'d'
            endfor
        endfor
        bestDot = -1e30
        for i from 1 to nChunks
            if eligible_'i' = 1 and weight_'i' > 1e-10
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
            if eligible_'i' = 1
                if weight_'i' > bestWeight
                    bestWeight = weight_'i'
                    chosenIdx = i
                endif
            endif
        endfor
    else
        r = randomUniform(0, 1)
        cumSum = 0
        found = 0
        for i from 1 to nChunks
            if found = 0 and eligible_'i' = 1
                cumSum = cumSum + weight_'i'
                if cumSum >= r
                    chosenIdx = i
                    found = 1
                endif
            endif
        endfor
        # Floating-point shortfall: fall back to the last eligible chunk
        # rather than to index 1, which may not be eligible at all.
        if found = 0
            chosenIdx = lastEligible
        endif
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
    
    # v1.2 (item 8): chunk embeddings are unit length, but a Mean or EMA
    # query is not renormalized after the update, so its LENGTH varies
    # with how coherent the recent history is - a coherent history gives a
    # long query and a sharper softmax, a scattered one gives a short
    # query and a flatter softmax. That coupling is arguably a musical
    # feature (context disagreement raises exploration on its own), so it
    # is preserved by default. Turn Renormalize_query on to make
    # Temperature mean the same thing at every step.
    if renormalize_query and context_mode <> 1
        qnorm = 0
        for d from 1 to embDim
            qnorm = qnorm + query_'d' * query_'d'
        endfor
        qnorm = sqrt(qnorm)
        if qnorm > 1e-10
            for d from 1 to embDim
                query_'d' = query_'d' / qnorm
            endfor
        endif
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
    #
    # v1.2 (item 1): the channel range was hardcoded `1, 1`, so on
    # STEREO input only the left channel was faded while the right
    # channel kept the rectangular cut - clicks on the right, and a
    # momentary stereo-image asymmetry at every join. It now runs over
    # all channels of the extracted chunk. This was the most serious
    # acoustic defect in v1.1.
    # In Crossfade join mode the per-chunk fades are skipped entirely,
    # because Concatenate with overlap supplies its own crossfade and
    # applying both would fade twice.
    if fadeDur > 0 and chunk_join = 1
        # Fade in:  ramp 0 -> 1 over [0, fadeDur]
        Formula (part): 0, fadeDur, 1, numChannels, "self * ((x - xmin) / fadeDur)"
        # Fade out: ramp 1 -> 0 over [chkDur - fadeDur, chkDur]
        fadeOutStart = chkDur - fadeDur
        Formula (part): fadeOutStart, chkDur, 1, numChannels, "self * ((xmax - x) / fadeDur)"
    endif
endfor

# Concatenate all
# v1.2 (item 2): v1.1 described this step as "crossfades", but each chunk
# was faded to zero at both ends and the chunks were then butt-joined
# with a plain Concatenate - no overlap, no summing across the boundary.
# The transition was chunk A -> silence -> chunk B, which produces an
# amplitude dip at every join and gives every chunk its own envelope
# (audible as gating on sustained material; with Jumpy Mosaic's 150 ms
# chunks and 10 ms fades, ~13% of each chunk is envelope). That can be a
# wanted aesthetic, so it is kept as the default rather than replaced.
# Chunk_join = 2 performs a real overlap crossfade instead.
selectObject: chunkSnd_1
for t from 2 to outputLength
    plusObject: chunkSnd_'t'
endfor

if chunk_join = 2 and outputLength >= 2
    # Overlap must be shorter than the shortest chunk in the sequence.
    minOutChunk = 1e30
    for t from 1 to outputLength
        idx = order_'t'
        if chunkDur_'idx' < minOutChunk
            minOutChunk = chunkDur_'idx'
        endif
    endfor
    joinOverlap = fade_duration_s
    if joinOverlap > minOutChunk * 0.45
        joinOverlap = minOutChunk * 0.45
    endif
    Concatenate with overlap: joinOverlap
    joinDesc$ = "crossfade, " + fixed$(joinOverlap * 1000, 1) + " ms overlap"
else
    Concatenate
    joinDesc$ = "fade-separated concatenation"
endif
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

appendInfoLine: "  Output: ", fixed$(outputDur, 2), " s (", joinDesc$, ")"
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
# VISUALIZATION  (Praat AudioTools suite standard)
# Header + two headline waveforms + full-width signature plots + summary strip
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    pageHeight = 6.65
    Erase all
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # Text-safe object names for Praat graphics markup.
    vizOriginalName$ = replace$(originalName$, "_", "\_ ", 0)
    vizCompositeName$ = replace$(compositeName$, "_", "\_ ", 0)

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

    if permutation_mode
        if outputLength < nUsable
            modeLabel$ = "Partial permutation"
        else
            modeLabel$ = "Permutation"
        endif
    else
        modeLabel$ = "Repeats allowed"
    endif

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Self-Attention Recomposer v1.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizOriginalName$ + " | " + presetName$ + " | " + string$(nChunks) + " chunks -> " + string$(outputLength) + " steps | T=" + fixed$(temperature, 2) + " | " + ctxLabel$ + " / " + selLabel$

    # === Panel A: Original waveform + chunk boundaries ===
    Select outer viewport: 0, 4, 0.66, 2.08
    Select inner viewport: 0.60, 3.85, 0.86, 1.84

    selectObject: originalSound
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "{0.75, 0.45, 0.35}"
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
    Text top: "no", "Original waveform | " + string$(nChunks) + " chunks"
    Text left: "yes", "Amplitude"
    Text bottom: "no", "Time (s)"

    # === Panel B: Output waveform ===
    Select outer viewport: 4, 8, 0.66, 2.08
    Select inner viewport: 4.45, 7.70, 0.86, 1.84

    selectObject: finalOutput
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform | " + fixed$(outputDur, 2) + " s"
    Text left: "yes", "Amplitude"
    Text bottom: "no", "Time (s)"

    # === Panel C: Attention order path ===
    Select outer viewport: 0, 8, 2.22, 4.14
    Select inner viewport: 0.60, 7.70, 2.43, 3.86

    Axes: 1, outputLength, 0, nChunks + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 1, outputLength, 0, nChunks + 1

    Colour: "{0.80, 0.80, 0.80}"
    Line width: 0.5
    for gi from 1 to nChunks
        Draw line: 1, gi, outputLength, gi
    endfor

    Colour: "{0.25, 0.45, 0.75}"
    Line width: 1.5
    for t from 1 to outputLength - 1
        tNext = t + 1
        idx1 = order_'t'
        idx2 = order_'tNext'
        Draw line: t, idx1, tNext, idx2
    endfor
    Line width: 1

    for t from 1 to outputLength
        idx = order_'t'
        Paint circle (mm): "{0.75, 0.35, 0.30}", t, idx, 1.4
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Attention order path | y = source chunk, x = output step"
    Text left: "yes", "Chunk"
    Text bottom: "no", "Step"

    # === Panel D: Consecutive similarity ===
    Select outer viewport: 0, 8, 4.30, 5.56
    Select inner viewport: 0.60, 7.70, 4.51, 5.27

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
        simYmin = minSim - simRange * 0.1
        simYmax = maxSim + simRange * 0.1

        Axes: 2, outputLength, simYmin, simYmax
        Paint rectangle: "{0.97, 0.97, 0.97}", 2, outputLength, simYmin, simYmax

        Colour: "{0.80, 0.80, 0.80}"
        Dotted line
        Draw line: 2, avgConsecSim, outputLength, avgConsecSim
        Solid line

        Colour: "{0.25, 0.55, 0.40}"
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
        Colour: "{0.35, 0.35, 0.50}"
        Text: 0.5, "centre", 0.5, "half", "Not enough steps for a similarity trace"
    endif

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Consecutive similarity | mean = " + fixed$(avgConsecSim, 3)
    Text left: "yes", "Similarity"
    Text bottom: "no", "Step"

    # === Summary strip ===
    Select outer viewport: 0, 8, 5.80, 6.60
    Select inner viewport: 0.60, 7.70, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Input##  " + vizOriginalName$ + " | " + string$(nChunks) + " chunks | MFCC dim " + string$(embDim) + " | " + modeLabel$
    summary2$ = "##Attention##  " + ctxLabel$ + " | " + selLabel$ + " | T=" + fixed$(temperature, 2) + " | TopK " + string$(top_k) + " | TopP " + fixed$(top_p, 2) + " | entropy " + fixed$(avgEntropy, 2)
    summary3$ = "##Output##  " + vizCompositeName$ + " | " + fixed$(outputDur, 2) + " s | AvgSim " + fixed$(avgConsecSim, 3) + " | " + joinDesc$ + " | fade " + fixed$(fade_duration_s * 1000, 0) + " ms | " + fixed$(sampleRate / 1000, 1) + " kHz"
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore full-page viewport so export/clipboard captures the whole figure.
    Select outer viewport: 0, 8, 0, pageHeight
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
