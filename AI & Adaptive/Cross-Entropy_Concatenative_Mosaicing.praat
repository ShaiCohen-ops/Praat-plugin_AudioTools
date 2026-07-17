# ============================================================
# Praat AudioTools - CrossEntropy_Concatenative_Mosaicing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2026)
#
#   v1.2 (2026):
#   - ADDED Stereo_mode "best + runner-up": the matching loop
#     already ranks every palette frame per slot; L takes the
#     best match, R the second-best (two-minimum tracking, no
#     extra search cost). Both channels track Q; the L/R
#     correlation follows match AMBIGUITY -- many near-equal
#     candidates widen the image, one dominant candidate narrows
#     it toward mono. Chains are crossfade-concatenated
#     separately and combined; stereo palettes are mixed to mono
#     per chain so the output is always true 2-channel in this
#     mode. "Single mosaic" preserves v1.1 behavior exactly.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-Entropy Concatenative Mosaicing.
#
#   Sound P (source palette) is sliced into equal-length frames and
#   each frame's magnitude spectrum is downsampled into nBins bands
#   and normalized into a probability density function (PDF).
#   Sound Q (target template) is sliced the same way. For every Q
#   frame, the script searches the entire P library and selects the
#   frame whose PDF minimizes the cross-entropy
#     H(P_frame, Q_j) = -sum_x P_frame(x) * log2(Q_j(x) + eps)
#   against Q_j's PDF. The winning P-frame's raw audio is extracted
#   and the frames are concatenated in Q's temporal order, producing
#   a resequencing of P's timbral material that tracks Q's spectral
#   progression.
#
#   Complexity: O(numFramesQ * numFramesP * nBins) for the matching
#   stage. Keep Number_of_bins modest (60-100) for long sounds or
#   fine frame sizes; the Micro Grain preset trades bins for time
#   resolution accordingly.
#
#   v1.1 (2026):
#   - FIX (musical, structural): the divergence direction was
#     REVERSED -- v1.0 minimized H(P_i, Q_j) = -sum P_i log2(Q_j),
#     which is won by whichever palette frame concentrates its
#     mass on Q's single biggest bin. For speech/music that bin
#     is almost always the lowest band, so ONE bass-heavy P-frame
#     swept nearly every slot (observed: 9/185 frames used, max
#     reuse 156x, flat resynthesis centroid). v1.1 minimizes
#     H(Q_j, P_i) = KL(Q_j || P_i) + const: the frame that best
#     EXPLAINS the whole target spectrum, with every uncovered
#     bin costing ~-log2(eps) bits.
#   - ADDED musicality terms (both zeroable): Continuity_bits
#     rewards choosing the palette frame that FOLLOWS the
#     previous choice (source-order runs -> coherent phrases);
#     Variety_bits penalizes re-choosing the immediately previous
#     frame (no stuck notes). Presets carry tuned values.
#   - FIX (clicks): frames were rectangular butt-joints -- one
#     click per frame boundary. Now crossfaded concatenation
#     (min(5 ms, frame/4)).
#   - Presets re-voiced toward longer frames (Standard now
#     100 ms) per listening; Custom default frame 0.1 s.
#   - SPEED: the O(Q*P*bins) matching loop now uses vectorized
#     inner products (inner/row#, probe-verified on 6.4.42).
#   - VIZ: the title was drawn at y = -1.7 inside a 0..1 axis --
#     it escaped its strip and landed on the first panel row;
#     panel rows sat 0.05 in apart so every bottom label struck
#     the next row's title. House title geometry, real inter-row
#     gaps, heavier trace lines.
#
#   v1.0:
#   - Core cross-entropy matching engine (Steps A/B/C) per spec.
#   - ADDED: preset system (5 presets + Custom).
#   - ADDED: metadata header, suite-standard 8-wide visualization
#     (reordering map, entropy trace, P-frame usage, centroid
#     overlay, dual PDF heatmaps, summary strip).
#   - Strict cleanup: no per-frame objects survive the run; only
#     the two inputs and Mosaiced_Output remain in the list.
# ============================================================

####################################################################
# INPUT VALIDATION
####################################################################

if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly two Sound objects (Sound P and Sound Q) before running this script."
endif

soundP_id = selected("Sound", 1)
soundQ_id = selected("Sound", 2)

selectObject: soundP_id
nameP$ = selected$("Sound")
srP = Get sampling frequency
durP = Get total duration

selectObject: soundQ_id
nameQ$ = selected$("Sound")
srQ = Get sampling frequency
durQ = Get total duration

if srP <> srQ
    exitScript: "Sound P (", srP, " Hz) and Sound Q (", srQ, " Hz) must share the same sampling rate."
endif

####################################################################
# FORM
####################################################################

form Cross-Entropy Concatenative Mosaicing v1.2
    comment === Preset Selection ===
    optionmenu Preset 1
        option Custom
        option Fine Detail (30 ms, 120 bins)
        option Standard (100 ms, 100 bins)
        option Coarse Texture (150 ms, 60 bins)
        option Micro Grain (15 ms, 80 bins)
        option Spectral Precision (100 ms, 200 bins)
    comment === Frame & Spectral Analysis ===
    positive Frame_duration_s 0.1
    natural Number_of_bins 100
    real Epsilon 1e-12
    comment === Musicality (0 = pure per-frame argmin) ===
    real Continuity_bits 0.4
    real Variety_bits 0.8
    comment === Output ===
    optionmenu Stereo_mode 1
        option Single mosaic (best match only)
        option Stereo: best (L) + runner-up (R)
    boolean Draw_visualization 1
    boolean Show_info 1
    boolean Play_result 1
endform

####################################################################
# APPLY PRESETS
####################################################################

if preset = 2
    # Fine Detail
    frame_duration_s = 0.03
    number_of_bins = 120
    continuity_bits = 0.3
    variety_bits = 0.8
    presetName$ = "FineDetail"
elsif preset = 3
    # Standard
    frame_duration_s = 0.10
    number_of_bins = 100
    continuity_bits = 0.4
    variety_bits = 0.8
    presetName$ = "Standard"
elsif preset = 4
    # Coarse Texture
    frame_duration_s = 0.15
    number_of_bins = 60
    continuity_bits = 0.3
    variety_bits = 0.6
    presetName$ = "CoarseTexture"
elsif preset = 5
    # Micro Grain
    frame_duration_s = 0.015
    number_of_bins = 80
    continuity_bits = 0.5
    variety_bits = 1.2
    presetName$ = "MicroGrain"
elsif preset = 6
    # Spectral Precision
    frame_duration_s = 0.10
    number_of_bins = 200
    continuity_bits = 0.2
    variety_bits = 0.6
    presetName$ = "SpectralPrecision"
else
    presetName$ = "Custom"
endif
if continuity_bits < 0
    continuity_bits = 0
endif
if variety_bits < 0
    variety_bits = 0
endif

####################################################################
# PARAMETER VALIDATION
####################################################################

frameDur = frame_duration_s
nBins = number_of_bins
eps = epsilon

numFramesP = floor(durP / frameDur)
numFramesQ = floor(durQ / frameDur)

if numFramesP < 1 or numFramesQ < 1
    exitScript: "Frame_duration_s is too long for the duration of one or both selected sounds."
endif

nyquist = srP / 2
binWidth = nyquist / nBins

clearinfo
writeInfoLine: "=== Cross-Entropy Concatenative Mosaicing v1.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sound P (source palette): """, nameP$, """  — ", numFramesP, " frames"
appendInfoLine: "Sound Q (target template): """, nameQ$, """  — ", numFramesQ, " frames"
appendInfoLine: "Frame duration: ", frameDur, " s   |   Spectral bins: ", nBins
appendInfoLine: ""

####################################################################
# STEP A - PRE-ANALYZE SOUND P (build PDF library)
####################################################################

appendInfoLine: "Step A: analyzing spectral PDFs of Sound P..."
pdfP## = zero##(numFramesP, nBins)

for i to numFramesP
    t1 = (i - 1) * frameDur
    t2 = t1 + frameDur

    selectObject: soundP_id
    Extract part: t1, t2, "rectangular", 1, "no"
    frameSnd = selected("Sound")
    To Spectrum: "yes"
    frameSpec = selected("Spectrum")

    rowSum = 0
    for b to nBins
        loF = (b - 1) * binWidth
        hiF = b * binWidth
        bandEnergy = Get band energy: loF, hiF
        if bandEnergy < 0
            bandEnergy = 0
        endif
        pdfP##[i, b] = bandEnergy
        rowSum += bandEnergy
    endfor

    if rowSum <= 0
        rowSum = eps
    endif
    for b to nBins
        pdfP##[i, b] = pdfP##[i, b] / rowSum
    endfor

    # Strict memory cleanup - remove temp Sound/Spectrum immediately
    removeObject: frameSnd, frameSpec

    if show_info and (i mod 20 = 0 or i = numFramesP)
        appendInfoLine: "  ...analyzed ", i, " / ", numFramesP, " P-frames"
    endif
endfor

# v1.1: precompute the log-PDF library once -- the matching loop
# then needs a single vectorized inner product per (Q, P) pair
logP## = zero##(numFramesP, nBins)
for i to numFramesP
    for b to nBins
        logP##[i, b] = log2(pdfP##[i, b] + eps)
    endfor
endfor

appendInfoLine: "Step A complete: ", numFramesP, " PDFs stored in memory."
appendInfoLine: ""

####################################################################
# STEP B - TARGET MATCHING LOOP
####################################################################

appendInfoLine: "Step B: matching Sound Q frames against the Sound P library..."

# Per-Q-frame bookkeeping, kept for both resynthesis and viz:
bestFrameIDs#  = zero#(numFramesQ)   
# Object ID of the winning P-slice
secondFrameIDs# = zero#(numFramesQ)
# Object ID of the runner-up slice (stereo mode)
# Object ID of the extracted winning P-slice
matchIndexP#   = zero#(numFramesQ)   
# Which P-frame index won
secondIndexP#  = zero#(numFramesQ)
# Runner-up P-frame index (stereo mode: right channel)
# Which P-frame index (1..numFramesP) won
bestH#         = zero#(numFramesQ)   
# The winning (minimum) cross-entropy value
qPdf##         = zero##(numFramesQ, nBins)  
# Q's own PDF per frame (for viz heatmap)
matchedPdf##   = zero##(numFramesQ, nBins)  
# PDF of the P-frame that was chosen

prevBest = 0
for j to numFramesQ
    qt1 = (j - 1) * frameDur
    qt2 = qt1 + frameDur

    selectObject: soundQ_id
    Extract part: qt1, qt2, "rectangular", 1, "no"
    qFrameSnd = selected("Sound")
    To Spectrum: "yes"
    qFrameSpec = selected("Spectrum")

    pdfQ# = zero#(nBins)
    qSum = 0
    for b to nBins
        loF = (b - 1) * binWidth
        hiF = b * binWidth
        bandEnergy = Get band energy: loF, hiF
        if bandEnergy < 0
            bandEnergy = 0
        endif
        pdfQ#[b] = bandEnergy
        qSum += bandEnergy
    endfor
    if qSum <= 0
        qSum = eps
    endif
    for b to nBins
        pdfQ#[b] = pdfQ#[b] / qSum
        qPdf##[j, b] = pdfQ#[b]
    endfor

    # Q-frame temp objects no longer needed once its PDF is extracted
    removeObject: qFrameSnd, qFrameSpec

    # Search the entire P library for the minimum cross-entropy match
    # v1.1: minimize H(Q_j, P_i) = KL(Q_j || P_i) + const -- the
    # palette frame that best EXPLAINS the target spectrum. (The
    # old reversed direction was won by whichever frame piled its
    # mass on Q's biggest bin: one bass frame swept the output.)
    # Continuity favours source-order runs; Variety blocks
    # stuck-note repetition. Vectorized: one inner() per pair.
    bestI = 1
    bestHval = 1e308
    secondI = 1
    secondHval = 1e308
    for i to numFramesP
        h = -inner(pdfQ#, row#(logP##, i))
        if i = prevBest
            h += variety_bits
        elsif i = prevBest + 1
            h -= continuity_bits
        endif
        if h < bestHval
            secondHval = bestHval
            secondI = bestI
            bestHval = h
            bestI = i
        elsif h < secondHval
            secondHval = h
            secondI = i
        endif
    endfor
    prevBest = bestI
    if numFramesP = 1
        secondI = bestI
    endif
    secondIndexP#[j] = secondI

    matchIndexP#[j] = bestI
    bestH#[j] = bestHval
    for b to nBins
        matchedPdf##[j, b] = pdfP##[bestI, b]
    endfor

    # Extract the winning raw audio slice from Sound P and keep its ID
    pt1 = (bestI - 1) * frameDur
    pt2 = pt1 + frameDur
    selectObject: soundP_id
    Extract part: pt1, pt2, "rectangular", 1, "no"
    bestFrameIDs#[j] = selected("Sound")
    if stereo_mode = 2
        st1 = (secondI - 1) * frameDur
        st2 = st1 + frameDur
        selectObject: soundP_id
        Extract part: st1, st2, "rectangular", 1, "no"
        secondFrameIDs#[j] = selected("Sound")
    endif

    if show_info and (j mod 20 = 0 or j = numFramesQ)
        appendInfoLine: "  ...matched Q-frame ", j, " / ", numFramesQ,
        ... "  (best P-frame = ", bestI, ", H = ", fixed$(bestHval, 4), ")"
    endif
endfor

appendInfoLine: "Step B complete: ", numFramesQ, " matches found."
appendInfoLine: ""

####################################################################
# STEP C - RESYNTHESIS
####################################################################

appendInfoLine: "Step C: concatenating ", numFramesQ, " reordered frames..."

# v1.1: crossfaded joins -- rectangular butt-joints clicked at
# every frame boundary
xfadeDur = min(0.005, frameDur / 4)

selectObject: bestFrameIDs#[1]
for j from 2 to numFramesQ
    plusObject: bestFrameIDs#[j]
endfor
if numFramesQ > 1
    Concatenate with overlap: xfadeDur
else
    Concatenate
endif
chainL = selected("Sound")

if stereo_mode = 2
    # v1.2: right channel = runner-up chain
    selectObject: secondFrameIDs#[1]
    for j from 2 to numFramesQ
        plusObject: secondFrameIDs#[j]
    endfor
    if numFramesQ > 1
        Concatenate with overlap: xfadeDur
    else
        Concatenate
    endif
    chainR = selected("Sound")
    
    # chains from a stereo palette are stereo -- mix each to mono
    # so the combined output is true 2-channel L/R
    selectObject: chainL
    chCk = Get number of channels
    if chCk > 1
        mL = Convert to mono
        removeObject: chainL
        chainL = mL
        selectObject: chainR
        mR = Convert to mono
        removeObject: chainR
        chainR = mR
    endif
    selectObject: chainL
    plusObject: chainR
    Combine to stereo
    Rename: "Mosaiced_Output"
    output_sound = selected("Sound")
    removeObject: chainL, chainR
else
    selectObject: chainL
    Rename: "Mosaiced_Output"
    output_sound = selected("Sound")
endif

# Remove every individual extracted frame Sound - leaves only the
# two original inputs and Mosaiced_Output.
for j to numFramesQ
    removeObject: bestFrameIDs#[j]
    if stereo_mode = 2
        removeObject: secondFrameIDs#[j]
    endif
endfor

selectObject: output_sound

####################################################################
# VISUALIZATION
####################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    # --- Derived viz quantities -------------------------------------
    # Spectral centroid per frame (Hz), computed from the stored PDFs.
    # Used to show whether the resynthesis tracks Q's brightness curve.
    qCentroid# = zero#(numFramesQ)
    matchedCentroid# = zero#(numFramesQ)
    for j to numFramesQ
        cQ = 0
        cM = 0
        for b to nBins
            binFreq = (b - 0.5) * binWidth
            cQ += qPdf##[j, b] * binFreq
            cM += matchedPdf##[j, b] * binFreq
        endfor
        qCentroid#[j] = cQ
        matchedCentroid#[j] = cM
    endfor
    maxCentroid = max(max(qCentroid#), max(matchedCentroid#))
    if maxCentroid <= 0
        maxCentroid = nyquist
    endif

    # P-frame usage histogram (how many times each P-frame was chosen)
    usageCount# = zero#(numFramesP)
    for j to numFramesQ
        idx = matchIndexP#[j]
        usageCount#[idx] += 1
    endfor
    maxUsage = max(usageCount#)
    if maxUsage < 1
        maxUsage = 1
    endif

    # Entropy trace range
    maxH = max(bestH#)
    if maxH <= 0
        maxH = 1
    endif

    # Heatmap downsampling strides (keep rendering fast on long sounds)
    maxVizCols = 80
    maxVizRows = 50
    strideJ = ceiling(numFramesQ / maxVizCols)
    if strideJ < 1
        strideJ = 1
    endif
    strideB = ceiling(nBins / maxVizRows)
    if strideB < 1
        strideB = 1
    endif

    totalDur = numFramesQ * frameDur

    # === TITLE ===
    # v1.1: explicit inner viewport + in-range y (the old y=-1.7
    # escaped the strip and landed on the first panel row)
    Select outer viewport: 0, 8, 0, 0.45
    Select inner viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half",
        ... "##Cross-Entropy Concatenative Mosaicing v1.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.24, "half",
        ... nameP$ + " -> " + nameQ$
        ... + " | " + presetName$
        ... + " | " + string$(numFramesP) + " P-frames, " + string$(numFramesQ) + " Q-frames"
        ... + " | frame " + fixed$(frameDur * 1000, 0) + " ms, bins " + string$(nBins)

    # === PANEL: REORDERING MAP ===
    Select outer viewport: 0, 4, 0.55, 2.10
    Select inner viewport: 0.7, 3.85, 0.67, 1.97

    Axes: 0, numFramesQ, 0, numFramesP
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numFramesQ, 0, numFramesP

    # Identity-mapping reference (Q-frame j == P-frame j), for scale
    Colour: "{0.85, 0.85, 0.85}"
    diagEnd = min(numFramesQ, numFramesP)
    Draw line: 0, 0, diagEnd, diagEnd

    if stereo_mode = 2
        Colour: "{0.9, 0.7, 0.4}"
        for j from 1 to numFramesQ - 1
            Draw line: j - 1, secondIndexP#[j], j, secondIndexP#[j + 1]
        endfor
    endif
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 1.5
    for j from 1 to numFramesQ - 1
        Draw line: j - 1, matchIndexP#[j], j, matchIndexP#[j + 1]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "P-frame index"
    if stereo_mode = 2
        Text top: "no", "Reordering map (blue = L/best, amber = R/runner-up)"
    else
        Text top: "no", "Reordering map (which P-slice fills each Q-slot)"
    endif
    Text bottom: "yes", "Q-frame index"

    # === PANEL: CROSS-ENTROPY MATCH QUALITY ===
    Select outer viewport: 4, 8, 0.55, 2.10
    Select inner viewport: 4.3, 7.7, 0.67, 1.97

    Axes: 0, numFramesQ, 0, maxH * 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numFramesQ, 0, maxH * 1.05

    Colour: "{0.8, 0.2, 0.4}"
    Line width: 1.5
    for j from 1 to numFramesQ - 1
        Draw line: j - 1, bestH#[j], j, bestH#[j + 1]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "H (bits)"
    Text top: "no", "Match quality (lower = better fit)"
    Text bottom: "yes", "Q-frame index"

    # === PANEL: P-FRAME USAGE HISTOGRAM ===
    Select outer viewport: 0, 4, 2.45, 4.00
    Select inner viewport: 0.7, 3.85, 2.57, 3.87

    Axes: 0, numFramesP, 0, maxUsage * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numFramesP, 0, maxUsage * 1.15

    Colour: "{0.2, 0.8, 0.4}"
    for i to numFramesP
        if usageCount#[i] > 0
            Paint rectangle: "{0.2, 0.8, 0.4}", i - 1, i, 0, usageCount#[i]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Times used"
    Text top: "no", "P-frame usage (palette coverage)"
    Text bottom: "yes", "P-frame index"

    # === PANEL: SPECTRAL CENTROID OVERLAY ===
    Select outer viewport: 4, 8, 2.45, 4.00
    Select inner viewport: 4.3, 7.7, 2.57, 3.87

    Axes: 0, totalDur, 0, maxCentroid / 1000 * 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, 0, maxCentroid / 1000 * 1.05

    Colour: "{0.6, 0.6, 0.6}"
    Line width: 1.5
    for j from 1 to numFramesQ - 1
        Draw line: (j - 1) * frameDur, qCentroid#[j] / 1000, j * frameDur, qCentroid#[j + 1] / 1000
    endfor
    Colour: "{0.8, 0.6, 0.2}"
    for j from 1 to numFramesQ - 1
        Draw line: (j - 1) * frameDur, matchedCentroid#[j] / 1000, j * frameDur, matchedCentroid#[j + 1] / 1000
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Centroid (kHz)"
    Text top: "no", "Spectral centroid: target vs. resynthesis"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Colour: "{0.6, 0.6, 0.6}"
    Text: totalDur * 0.02, "left", maxCentroid / 1000 * 0.95, "half", "Q (target)"
    Colour: "{0.8, 0.6, 0.2}"
    Text: totalDur * 0.02, "left", maxCentroid / 1000 * 0.86, "half", "P (resynthesis)"

    # === PANEL: Q TARGET PDF HEATMAP ===
    Select outer viewport: 0, 4, 4.35, 6.55
    Select inner viewport: 0.7, 3.85, 4.47, 6.42

    Axes: 0, numFramesQ, 0, nBins
    j = 1
    while j <= numFramesQ
        b = 1
        while b <= nBins
            v = qPdf##[j, b]
            g = 1 - min(v * 12, 1)
            colour$ = "{" + string$(g) + "," + string$(g * 0.7 + 0.3) + "," + string$(g)+ "}"
            jEnd = min(j + strideJ - 1, numFramesQ)
            bEnd = min(b + strideB - 1, nBins)
            Paint rectangle: colour$, j - 1, jEnd, b - 1, bEnd
            b += strideB
        endwhile
        j += strideJ
    endwhile

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Bin"
    Text top: "no", "Target PDF (Sound Q spectral progression)"
    Text bottom: "yes", "Q-frame index"

    # === PANEL: RECONSTRUCTED PDF HEATMAP ===
    Select outer viewport: 4, 8, 4.35, 6.55
    Select inner viewport: 4.3, 7.7, 4.47, 6.42

    Axes: 0, numFramesQ, 0, nBins
    j = 1
    while j <= numFramesQ
        b = 1
        while b <= nBins
            v = matchedPdf##[j, b]
            g = 1 - min(v * 12, 1)
            colour$ = "{" + string$(g) + "," + string$(g) + "," + string$(g * 0.7 + 0.3) + "}"
            jEnd = min(j + strideJ - 1, numFramesQ)
            bEnd = min(b + strideB - 1, nBins)
            Paint rectangle: colour$, j - 1, jEnd, b - 1, bEnd
            b += strideB
        endwhile
        j += strideJ
    endwhile

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Bin"
    Text top: "no", "Resynthesized PDF (chosen P-slices)"
    Text bottom: "yes", "Q-frame index"

    # === SUMMARY STRIP ===
    Select outer viewport: 0, 8, 6.90, 7.60
    Select inner viewport: 0.6, 7.7, 6.95, 7.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    meanH = 0
    for j to numFramesQ
        meanH += bestH#[j]
    endfor
    meanH = meanH / numFramesQ
    uniqueUsed = 0
    for i to numFramesP
        if usageCount#[i] > 0
            uniqueUsed += 1
        endif
    endfor
    coveragePct = 100 * uniqueUsed / numFramesP

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half",
        ... "##Analysis##  P=" + string$(numFramesP) + " frames"
        ... + "  Q=" + string$(numFramesQ) + " frames"
        ... + "  bins=" + string$(nBins)
        ... + "  mean H=" + fixed$(meanH, 3) + " bits"
    Text: 0.02, "left", 0.48, "half",
        ... "##Palette coverage##  " + string$(uniqueUsed) + " / " + string$(numFramesP)
        ... + " P-frames used (" + fixed$(coveragePct, 1) + "%)"
        ... + "  max reuse=" + string$(maxUsage) + "x"
    Text: 0.02, "left", 0.18, "half",
        ... "##Output##  " + fixed$(totalDur, 2) + " s"
        ... + "  preset=" + presetName$
        ... + "  frame=" + fixed$(frameDur * 1000, 0) + " ms"
        ... + "  continuity=" + fixed$(continuity_bits, 2)
        ... + "  variety=" + fixed$(variety_bits, 2)
        ... + "  |  KL(Q||P) matching"
        ... + (if stereo_mode = 2 then "  |  stereo: best+runner-up" else "" fi)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete!"
endif

####################################################################
# FINAL REPORT
####################################################################

selectObject: output_sound

if show_info
    dur = Get total duration
    n_ch = Get number of channels
    appendInfoLine: ""
    appendInfoLine: "=== Complete ==="
    appendInfoLine: "Output: ", selected$("Sound")
    appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
    appendInfoLine: "Channels: ", n_ch
    appendInfoLine: "Frames processed and reordered: ", numFramesQ
endif

if play_result
    Play
endif