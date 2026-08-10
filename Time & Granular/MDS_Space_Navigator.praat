# ============================================================
# Praat AudioTools - MDS Space Navigator
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   MDS Space Navigator
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Choose preset or enter custom shift amounts.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis—Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
#
# Changelog v0.3 (2026):
#   - COMPATIBILITY: the complete form/API is unchanged byte-for-byte.
#     Parameter names, order, types and defaults remain exactly v0.2.
#   - CRITICAL: fixed reordered-audio assembly. Praat concatenates selected
#     Sounds in Object-list order, not selection order. Because extracted
#     segments were older than the growing final Sound, the next word could
#     be prepended. v0.3 copies each next segment after the accumulator before
#     concatenating, guaranteeing the requested sequence.
#   - Multi-channel preservation: mono conversion is analysis-only. Rendered
#     segments are extracted from the original Sound and silence gaps use the
#     original channel count. Mono input remains mono; stereo and N-channel
#     input remain N-channel.
#   - Number_of_MFCC_Coefficients now actually controls Sound: To MFCC; v0.2
#     hard-coded 12 despite exposing this parameter.
#   - Added an explicit exactly-one-Sound selection guard.
#   - Degenerate all-zero distance matrices get a tiny deterministic MDS-only
#     tie-break geometry so the visualization/order stage can still run; raw
#     feature distances and nearest-neighbour decisions remain unchanged.
#   - Output duration accounting and visualization boundaries remain based on
#     the exact segment durations plus the requested inter-word silences.
#
# Formant, Pitch, or MFCC Word Similarity with AUTO SEGMENTATION + CONCATENATION
# Select only a Sound - script will auto-segment and reorder by similarity
# MDS Audio Chain

# ===== PARAMETERS =====
form Audio Word Sorting
    comment === SEGMENTATION ===
    positive Silence_threshold_dB 25
    positive Minimum_silent_interval_s 0.1
    positive Minimum_sounding_interval_s 0.1
    
    comment === ANALYSIS METHOD ===
    optionmenu Similarity_metric 1
        option Formants (Vowel Quality)
        option Pitch (F0)
        option MFCC (Timbre/Spectral Shape)
    
    comment --- Formant Params ---
    positive Max_formant_Hz 5500
    positive Number_of_formants 5
    
    comment --- MFCC Params ---
    positive Number_of_MFCC_Coefficients 12
    
    comment === CONCATENATION ===
    optionmenu Ordering 1
        option Nearest neighbor chain (most similar next)
        option MDS Dimension 1 (low to high)
        option Original order
    positive Silence_between_words_s 0.1
    boolean Play_result 1
endform

# ===== CHECK SELECTION AND CREATE ANALYSIS COPY =====
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original_sound = selected("Sound")
original_sound_name$ = selected$("Sound")

writeInfoLine: "Checking audio format..."

# Convert to mono for ANALYSIS only; rendering uses original_sound.
selectObject: original_sound
n_channels = Get number of channels

if n_channels > 1
    appendInfoLine: "Creating mono analysis copy from ", n_channels, " channels (render stays multichannel)..."
    sound = Convert to mono
    sound_name$ = selected$("Sound")
else
    appendInfoLine: "Audio is already mono"
    sound = original_sound
    sound_name$ = original_sound_name$
endif

sample_rate = Get sampling frequency

# ===== AUTO-SEGMENTATION =====
appendInfoLine: newline$, "Auto-segmenting sound into words..."

# Create intensity object
selectObject: sound
intensity = To Intensity: 100, 0, "yes"

# Detect silences and create TextGrid
selectObject: intensity
textgrid = To TextGrid (silences): -silence_threshold_dB, minimum_silent_interval_s, minimum_sounding_interval_s, "silent", "sounding"

# Count and label sounding intervals
selectObject: textgrid
n_intervals = Get number of intervals: 1

appendInfoLine: "Found ", n_intervals, " intervals (using -", silence_threshold_dB, " dB threshold)"

# Collect non-silent intervals
n_words = 0
for i to n_intervals
    label$ = Get label of interval: 1, i
    if label$ = "sounding"
        n_words += 1
        # Relabel as word_1, word_2, etc.
        Set interval text: 1, i, "word_" + string$(n_words)
        
        word_label$[n_words] = "word_" + string$(n_words)
        word_start[n_words] = Get start point: 1, i
        word_end[n_words] = Get end point: 1, i
        appendInfoLine: "  ", word_label$[n_words], ": ", fixed$(word_start[n_words], 3), "-", fixed$(word_end[n_words], 3), "s"
    endif
endfor

if n_words < 2
    removeObject: intensity, textgrid
    if sound != original_sound
        removeObject: sound
    endif
    exitScript: "Need at least 2 word segments! Found: ", n_words
endif

appendInfoLine: newline$, "Segmented into ", n_words, " words"
appendInfoLine: "Render channels: ", n_channels

# ==========================================
# ===== FEATURE EXTRACTION & DISTANCE ======
# ==========================================

# Initialize distance matrix
for i to n_words
    for j to n_words
        dist[i,j] = 0
    endfor
endfor

if similarity_metric = 1
    # ===== FORMANTS =====
    appendInfoLine: newline$, "Analyzing Formants..."
    selectObject: sound
    formant_obj = To Formant (burg): 0, number_of_formants, max_formant_Hz, 0.025, 50
    
    for i to n_words
        selectObject: formant_obj
        t_mid = (word_start[i] + word_end[i]) / 2
        f1[i] = Get value at time: 1, t_mid, "hertz", "Linear"
        f2[i] = Get value at time: 2, t_mid, "hertz", "Linear"
        
        # Handle undefined
        if f1[i] = undefined
            f1[i] = 0
        endif
        if f2[i] = undefined
            f2[i] = 0
        endif
        appendInfoLine: "  Word ", i, ": F1=", fixed$(f1[i],0), " F2=", fixed$(f2[i],0)
    endfor
    
    # Calc Distance (Euclidean F1/F2)
    for i to n_words
        for j to n_words
            dist[i,j] = sqrt((f1[i]-f1[j])^2 + (f2[i]-f2[j])^2)
        endfor
    endfor
    removeObject: formant_obj

elsif similarity_metric = 2
    # ===== PITCH =====
    appendInfoLine: newline$, "Analyzing Pitch..."
    selectObject: sound
    pitch_obj = To Pitch: 0.0, 75, 600
    
    for i to n_words
        selectObject: pitch_obj
        p_val[i] = Get mean: word_start[i], word_end[i], "Hertz"
        if p_val[i] = undefined
            p_val[i] = 0
        endif
        appendInfoLine: "  Word ", i, ": Pitch=", fixed$(p_val[i], 1), " Hz"
    endfor
    
    # Calc Distance (Absolute Difference)
    for i to n_words
        for j to n_words
            dist[i,j] = abs(p_val[i] - p_val[j])
        endfor
    endfor
    removeObject: pitch_obj

elsif similarity_metric = 3
    # ===== MFCC =====
    appendInfoLine: newline$, "Analyzing MFCCs..."
    
    # We must extract segments individually to get clean mean MFCC vectors
    for i to n_words
        selectObject: sound
        tmp_part = Extract part: word_start[i], word_end[i], "rectangular", 1, "no"
        
        # Calculate MFCC for this word
        tmp_mfcc = To MFCC: number_of_MFCC_Coefficients, 0.015, 0.005, 100, 100, 0
        
        # Convert to TableOfReal: "no" means DO NOT include frame numbers
        tmp_table = To TableOfReal: "no"
        
        # Get mean for each coefficient (c1 to cN)
        for c from 1 to number_of_MFCC_Coefficients
            # Use specific command for TableOfReal column statistics
            mfcc_val[i, c] = Get column mean (index): c
        endfor
        
        removeObject: tmp_part, tmp_mfcc, tmp_table
        appendInfoLine: "  Word ", i, " analyzed."
    endfor

    # Calc Distance (Euclidean over MFCC vector)
    appendInfoLine: "Computing vector distances..."
    for i to n_words
        for j to n_words
            sum_sq = 0
            for c from 1 to number_of_MFCC_Coefficients
                diff = mfcc_val[i, c] - mfcc_val[j, c]
                sum_sq += diff^2
            endfor
            dist[i,j] = sqrt(sum_sq)
        endfor
    endfor
endif

# ===== CREATE DISTANCE MATRIX OBJECT =====
# Detect the fully-degenerate case (e.g. every Pitch value undefined -> 0).
# Monotone MDS has no geometry to recover from an all-zero dissimilarity
# matrix, so only the MDS copy receives a tiny deterministic tie-break.
maxRawDistance = 0
for i to n_words
    for j to n_words
        if dist[i,j] > maxRawDistance
            maxRawDistance = dist[i,j]
        endif
    endfor
endfor
mdsTieBreak = 0
if maxRawDistance <= 1e-12
    mdsTieBreak = 1
    appendInfoLine: "All feature distances are tied; using deterministic MDS-only tie-break geometry."
endif

tableofreal = Create TableOfReal: "distances", n_words, n_words
for i to n_words
    Set row label (index): i, word_label$[i]
    Set column label (index): i, word_label$[i]
    for j to n_words
        mdsValue = dist[i,j]
        if mdsTieBreak and i <> j
            mdsValue = abs(i - j) * 1e-6
        endif
        Set value: i, j, mdsValue
    endfor
endfor

dissimilarity = To Dissimilarity

# ===== PERFORM MDS =====
appendInfoLine: newline$, "Running MDS..."
selectObject: dissimilarity
config = To Configuration (monotone mds): 2, "Primary approach", 1e-05, 50, 1

selectObject: config
for i to n_words
    mds1[i] = Get value: i, 1
    mds2[i] = Get value: i, 2
endfor

# Metric name for display
if similarity_metric = 1
    metricName$ = "Formants (F1/F2)"
elsif similarity_metric = 2
    metricName$ = "Pitch (F0)"
else
    metricName$ = "MFCC (Timbre)"
endif

# Ordering name for display
if ordering = 1
    orderName$ = "Nearest Neighbor"
elsif ordering = 2
    orderName$ = "MDS Dim 1"
else
    orderName$ = "Original"
endif

# ===== DETERMINE ORDERING =====
if ordering = 1
    # Nearest neighbor chain
    order[1] = 1
    used[1] = 1
    for i from 2 to n_words
        used[i] = 0
    endfor
    
    for pos from 2 to n_words
        current = order[pos-1]
        min_dist = 999999999
        next_word = 0
        
        for candidate to n_words
            if used[candidate] = 0
                d = dist[current, candidate]
                if d < min_dist
                    min_dist = d
                    next_word = candidate
                endif
            endif
        endfor
        order[pos] = next_word
        used[next_word] = 1
    endfor
elsif ordering = 2
    # MDS Sort
    for i to n_words
        order[i] = i
    endfor
    # Bubble sort
    for i to n_words - 1
        for j from i + 1 to n_words
            if mds1[order[j]] < mds1[order[i]]
                temp = order[i]
                order[i] = order[j]
                order[j] = temp
            endif
        endfor
    endfor
else
    # Original
    for i to n_words
        order[i] = i
    endfor
endif

# ===== EXTRACT & CONCATENATE =====
appendInfoLine: newline$, "Reordering and concatenating..."

# Extract all segments to objects
for pos to n_words
    word_idx = order[pos]
    selectObject: original_sound
    segment_obj[pos] = Extract part: word_start[word_idx], word_end[word_idx], "rectangular", 1, "no"
endfor

# Start concatenation
selectObject: segment_obj[1]
final_sound = Copy: original_sound_name$ + "_reordered"

for pos from 2 to n_words
    # Create silence with the ORIGINAL channel count. It is created after the
    # accumulator, so Object-list order is final_sound -> silence_temp.
    silence_temp = Create Sound from formula: "silence_temp", n_channels, 0, silence_between_words_s, sample_rate, "0"
    
    selectObject: final_sound, silence_temp
    old_chain = final_sound
    final_sound = Concatenate
    removeObject: old_chain, silence_temp
    
    # segment_obj[pos] is older than the growing accumulator. Praat ignores
    # selection order when concatenating, so make a fresh copy AFTER
    # final_sound; this guarantees final_sound -> next_segment.
    selectObject: segment_obj[pos]
    next_segment = Copy: "join_word_" + string$(pos)
    selectObject: final_sound, next_segment
    old_chain = final_sound
    final_sound = Concatenate
    removeObject: old_chain, next_segment
endfor

selectObject: final_sound
Rename: original_sound_name$ + "_reordered"

# ===== VISUALIZATION =====
Erase all
Select outer viewport: 0, 8, 0, 8

# ----------------------------------------------------------
# Title
# ----------------------------------------------------------
Select outer viewport: 0, 8, 0, 0.65
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.65, "half", "##MDS Space Navigator##"
Font size: 7
Colour: "{0.35, 0.35, 0.52}"
Text: 0.5, "centre", -0.25, "half",
    ... original_sound_name$
    ... + "  |  " + metricName$
    ... + "  |  " + orderName$
    ... + "  |  " + string$(n_words) + " segments"

# ----------------------------------------------------------
# Panel A: MDS scatter plot (left)
# ----------------------------------------------------------
Select outer viewport: 0, 4.5, 0.75, 4.35
Select inner viewport: 0.55, 4.20, 0.90, 4.20
Axes: 0, 1, 0, 1
Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

# Find MDS coordinate ranges for scaling
mdsMinX = mds1[1]
mdsMaxX = mds1[1]
mdsMinY = mds2[1]
mdsMaxY = mds2[1]
for i from 2 to n_words
    if mds1[i] < mdsMinX
        mdsMinX = mds1[i]
    endif
    if mds1[i] > mdsMaxX
        mdsMaxX = mds1[i]
    endif
    if mds2[i] < mdsMinY
        mdsMinY = mds2[i]
    endif
    if mds2[i] > mdsMaxY
        mdsMaxY = mds2[i]
    endif
endfor

# Add 15% padding
mdsRangeX = mdsMaxX - mdsMinX
mdsRangeY = mdsMaxY - mdsMinY
if mdsRangeX < 0.001
    mdsRangeX = 1
endif
if mdsRangeY < 0.001
    mdsRangeY = 1
endif
padX = mdsRangeX * 0.15
padY = mdsRangeY * 0.15

Axes: mdsMinX - padX, mdsMaxX + padX, mdsMinY - padY, mdsMaxY + padY

# Draw crosshairs
Colour: "{0.85, 0.85, 0.85}"
midX = (mdsMinX + mdsMaxX) / 2
midY = (mdsMinY + mdsMaxY) / 2
Draw line: mdsMinX - padX, midY, mdsMaxX + padX, midY
Draw line: midX, mdsMinY - padY, midX, mdsMaxY + padY

# Draw nearest-neighbor path (connecting lines in order)
if ordering = 1
    Line width: 1
    Colour: "{0.75, 0.75, 0.85}"
    for pos from 2 to n_words
        w1 = order[pos - 1]
        w2 = order[pos]
        Draw line: mds1[w1], mds2[w1], mds1[w2], mds2[w2]
    endfor
endif

# Draw dots — color gradient by ordering position (blue→red)
for pos from 1 to n_words
    w = order[pos]
    frac = (pos - 1) / max(1, n_words - 1)

    # Blue→Red gradient
    rr = frac
    gg = 0.25
    bb = 1 - frac

    # Dot size scaled by segment duration
    segDur = word_end[w] - word_start[w]
    dotSize = 2.5 + segDur * 8
    if dotSize > 6
        dotSize = 6
    endif

    Paint circle (mm): "{" + fixed$(rr, 2) + ", " + fixed$(gg, 2) + ", " + fixed$(bb, 2) + "}", mds1[w], mds2[w], dotSize

    # Label
    Font size: 5
    Colour: "{0.20, 0.20, 0.20}"
    Text: mds1[w], "left", mds2[w] + mdsRangeY * 0.04, "half", string$(w)
endfor

Line width: 1
Colour: "Black"
Draw inner box
Font size: 7
Text top: "no", "MDS similarity map  (blue=first → red=last)"
Font size: 6
Text bottom: "yes", "Dimension 1"
Text left: "yes", "Dim 2"

# ----------------------------------------------------------
# Panel B: Parameters + distance matrix summary (right, upper)
# ----------------------------------------------------------
Select outer viewport: 4.5, 8, 0.75, 2.50
Select inner viewport: 4.75, 7.65, 0.90, 2.38
Axes: 0, 1, 0, 1
Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

Font size: 7
Colour: "Black"
Text: 0.05, "left", 0.90, "half", "##Parameters##"

Font size: 6
Colour: "{0.30, 0.30, 0.30}"
Text: 0.05, "left", 0.74, "half", "Metric:   " + metricName$
Text: 0.05, "left", 0.60, "half", "Ordering: " + orderName$
Text: 0.05, "left", 0.46, "half", "Segments: " + string$(n_words)
Text: 0.05, "left", 0.32, "half", "Gap:      " + fixed$(silence_between_words_s * 1000, 0) + " ms"

# Find min/max distance for display
dMin = 999999
dMax = 0
for i from 1 to n_words
    for j from 1 to n_words
        if i <> j
            if dist[i, j] < dMin
                dMin = dist[i, j]
            endif
            if dist[i, j] > dMax
                dMax = dist[i, j]
            endif
        endif
    endfor
endfor
Text: 0.05, "left", 0.18, "half", "Dist range: " + fixed$(dMin, 1) + " – " + fixed$(dMax, 1)

Colour: "Black"
Draw rectangle: 0, 1, 0, 1

# ----------------------------------------------------------
# Panel C: Ordering sequence (right, lower)
# ----------------------------------------------------------
Select outer viewport: 4.5, 8, 2.55, 4.35
Select inner viewport: 4.75, 7.65, 2.68, 4.22
Axes: 0, 1, 0, 1
Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

Font size: 7
Colour: "Black"
Text: 0.05, "left", 0.94, "half", "##Sequence##"

Font size: 5
Colour: "{0.30, 0.30, 0.30}"

# Show ordering as a compact list (up to 20 entries)
nShow = min(n_words, 20)
for pos from 1 to nShow
    w = order[pos]
    yPos = 0.86 - (pos - 1) * (0.78 / max(1, nShow))
    segDur = word_end[w] - word_start[w]

    frac = (pos - 1) / max(1, n_words - 1)
    rr = frac
    bb = 1 - frac

    # Color swatch
    Paint rectangle: "{" + fixed$(rr, 2) + ", 0.25, " + fixed$(bb, 2) + "}", 0.02, 0.06, yPos - 0.015, yPos + 0.015

    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.08, "left", yPos, "half", string$(pos) + ". w" + string$(w) + "  (" + fixed$(segDur * 1000, 0) + " ms)"
endfor

if n_words > 20
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.08, "left", 0.04, "half", "... +" + string$(n_words - 20) + " more"
endif

Colour: "Black"
Draw rectangle: 0, 1, 0, 1

# ----------------------------------------------------------
# Panel D: Reordered output waveform (full width)
# ----------------------------------------------------------
Select outer viewport: 0, 8, 4.45, 5.75
Select inner viewport: 0.55, 7.65, 4.55, 5.68
selectObject: final_sound
outDur = Get total duration
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak < 0.001
    outPeak = 0.001
endif
Axes: 0, outDur, -outPeak * 1.1, outPeak * 1.1
Colour: "{0.15, 0.50, 0.35}"
Draw: 0, 0, -outPeak * 1.1, outPeak * 1.1, "no", "Curve"

# Draw segment boundary lines
Colour: "{0.80, 0.30, 0.30}"
Dotted line
accumDur = 0
for pos from 1 to n_words - 1
    w = order[pos]
    segDur = word_end[w] - word_start[w]
    accumDur = accumDur + segDur + silence_between_words_s
    if accumDur < outDur
        Draw line: accumDur, -outPeak * 1.05, accumDur, outPeak * 1.05
    endif
endfor
Solid line

Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Amp"
Text bottom: "yes", "Time (s)"
Text top: "no", "Reordered output  (red lines = segment boundaries)"

# ----------------------------------------------------------
# Summary bar
# ----------------------------------------------------------
Select outer viewport: 0, 8, 5.85, 6.45
Select inner viewport: 0.55, 7.65, 5.90, 6.38
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

Font size: 7
Colour: "Black"
Text: 0.02, "left", 0.72, "half", "##" + original_sound_name$ + "_reordered##"

Font size: 6
Colour: "{0.30, 0.30, 0.30}"
Text: 0.02, "left", 0.28, "half",
    ... metricName$
    ... + "  |  " + orderName$
    ... + "  |  " + string$(n_words) + " segs"
    ... + "  |  gap=" + fixed$(silence_between_words_s * 1000, 0) + "ms"
    ... + "  |  out=" + fixed$(outDur, 2) + "s"
    ... + "  |  dist=" + fixed$(dMin, 1) + "–" + fixed$(dMax, 1)

Colour: "Black"
Draw rectangle: 0, 1, 0, 1

# Reset
Font size: 10
Colour: "Black"
Line width: 1

# ===== CLEANUP =====
appendInfoLine: newline$, "Cleaning up..."
removeObject: intensity, textgrid, config, dissimilarity, tableofreal
for i to n_words
    removeObject: segment_obj[i]
endfor
if sound != original_sound
    removeObject: sound
endif

# ===== PLAY & SELECT =====
selectObject: final_sound
if play_result
    Play
endif

