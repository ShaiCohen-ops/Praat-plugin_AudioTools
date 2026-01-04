# ============================================================
# Praat AudioTools - MDS Space Navigator
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
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

# ===== CHECK SELECTION AND CONVERT TO MONO =====
original_sound = selected("Sound")
original_sound_name$ = selected$("Sound")

writeInfoLine: "Checking audio format..."

# Convert to mono if needed
selectObject: original_sound
n_channels = Get number of channels

if n_channels > 1
    appendInfoLine: "Converting from ", n_channels, " channels to mono..."
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
        tmp_mfcc = To MFCC: 12, 0.015, 0.005, 100, 100, 0
        
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
tableofreal = Create TableOfReal: "distances", n_words, n_words
for i to n_words
    Set row label (index): i, word_label$[i]
    Set column label (index): i, word_label$[i]
    for j to n_words
        Set value: i, j, dist[i,j]
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
endfor

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
    selectObject: sound
    segment_obj[pos] = Extract part: word_start[word_idx], word_end[word_idx], "rectangular", 1, "no"
endfor

# Start concatenation
selectObject: segment_obj[1]
final_sound = Copy: original_sound_name$ + "_reordered"

for pos from 2 to n_words
    # Create silence
    silence_temp = Create Sound from formula: "silence_temp", 1, 0, silence_between_words_s, sample_rate, "0"
    
    # Append Silence
    selectObject: final_sound
    plusObject: silence_temp
    old_chain = final_sound
    final_sound = Concatenate
    removeObject: old_chain, silence_temp
    
    # Append Next Word
    selectObject: final_sound
    plusObject: segment_obj[pos]
    old_chain = final_sound
    final_sound = Concatenate
    removeObject: old_chain
endfor

selectObject: final_sound
Rename: original_sound_name$ + "_reordered"

# ===== VISUALIZATION =====
selectObject: config
Erase all
Select outer viewport: 0, 6, 0, 6
Draw: 1, 2, 0, 0, 0, 0, 12, "yes", "+", "yes"
Text top: "yes", "MDS Similarity Map"

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
if play_result
    selectObject: final_sound
    Play
endif

