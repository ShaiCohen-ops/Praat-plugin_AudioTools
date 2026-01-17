# ============================================================
# Praat AudioTools - LZ-Inspired_Audio_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LZ-Inspired Audio Variations - applies data compression
#   concepts to audio composition. Segments audio into windows,
#   extracts features, finds similar patterns (like LZ dictionary),
#   then creates variations using the dictionary entries.
#
# Changelog v0.3:
#   - Fixed Formula variable expansion
#   - Fixed PitchTier multiplication
#   - Added preset name to output
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original_sound = selected("Sound")
sound_name$ = selected$("Sound")

form LZ Audio Variations v0.3
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Subtle Texture
        option Rhythmic Shuffle
        option Spectral Morph
        option Glitch Variations
        option Ambient Drift
    comment === Analysis ===
    optionmenu Analysis_type: 1
        option Pitch
        option Spectrum
        option Intensity
    positive Window_size_s 0.1
    positive Overlap 0.5
    comment === Similarity ===
    positive Similarity_threshold 0.8
    optionmenu Distance_metric: 1
        option Euclidean
        option Correlation
        option Cosine
    comment === Variation ===
    optionmenu Variation_method: 1
        option Pitch shift
        option Time stretch
        option Amplitude modulation
        option Spectral filter
        option Reverse
        option Granular shuffle
    real Variation_amount 0.5
    comment === Output ===
    positive Output_duration_s 10
    boolean Randomize_dictionary_order 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Texture
    analysis_type = 1
    window_size_s = 0.15
    overlap = 0.6
    similarity_threshold = 0.85
    distance_metric = 1
    variation_method = 1
    variation_amount = 0.3
    presetName$ = "SubtleTexture"
elsif preset = 3
    # Rhythmic Shuffle
    analysis_type = 3
    window_size_s = 0.08
    overlap = 0.4
    similarity_threshold = 0.75
    distance_metric = 1
    variation_method = 6
    variation_amount = 0.6
    presetName$ = "RhythmicShuffle"
elsif preset = 4
    # Spectral Morph
    analysis_type = 2
    window_size_s = 0.12
    overlap = 0.5
    similarity_threshold = 0.8
    distance_metric = 3
    variation_method = 4
    variation_amount = 0.5
    presetName$ = "SpectralMorph"
elsif preset = 5
    # Glitch Variations
    analysis_type = 2
    window_size_s = 0.05
    overlap = 0.3
    similarity_threshold = 0.7
    distance_metric = 1
    variation_method = 5
    variation_amount = 0.8
    presetName$ = "Glitch"
elsif preset = 6
    # Ambient Drift
    analysis_type = 1
    window_size_s = 0.2
    overlap = 0.7
    similarity_threshold = 0.9
    distance_metric = 2
    variation_method = 2
    variation_amount = 0.4
    presetName$ = "AmbientDrift"
else
    presetName$ = "Custom"
endif

selectObject: original_sound
sample_rate = Get sampling frequency
total_duration = Get total duration

# === Get Names for Display ===
if analysis_type = 1
    analysis_name$ = "Pitch"
elsif analysis_type = 2
    analysis_name$ = "Spectrum"
else
    analysis_name$ = "Intensity"
endif

if variation_method = 1
    variation_name$ = "PitchShift"
elsif variation_method = 2
    variation_name$ = "TimeStretch"
elsif variation_method = 3
    variation_name$ = "AM"
elsif variation_method = 4
    variation_name$ = "SpectralFilter"
elsif variation_method = 5
    variation_name$ = "Reverse"
else
    variation_name$ = "Granular"
endif

# === Info ===
clearinfo
writeInfoLine: "=== LZ-Inspired Audio Variations v0.3 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(total_duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis: ", analysis_name$
appendInfoLine: "Window: ", window_size_s, " s | Overlap: ", overlap * 100, "%"
appendInfoLine: "Similarity threshold: ", similarity_threshold
appendInfoLine: "Variation: ", variation_name$, " (", variation_amount, ")"
appendInfoLine: ""

# === Calculate Windows ===
hop_size = window_size_s * (1 - overlap)
num_windows = floor((total_duration - window_size_s) / hop_size) + 1

appendInfoLine: "Windows: ", num_windows
appendInfoLine: ""

# === STEP 1: Extract Features ===
appendInfoLine: "Extracting features..."

features = Create Table with column names: "features", num_windows, "start end index"

for i to num_windows
    start_time = (i - 1) * hop_size
    end_time = start_time + window_size_s
    
    selectObject: features
    Set numeric value: i, "start", start_time
    Set numeric value: i, "end", end_time
    Set numeric value: i, "index", i
endfor

selectObject: original_sound

if analysis_type = 1
    # PITCH ANALYSIS
    pitch = To Pitch: 0, 75, 600
    
    for i to num_windows
        selectObject: features
        start_time = Get value: i, "start"
        end_time = Get value: i, "end"
        
        selectObject: pitch
        mean_f0 = Get mean: start_time, end_time, "Hertz"
        stdev_f0 = Get standard deviation: start_time, end_time, "Hertz"
        
        selectObject: features
        if i = 1
            Append column: "mean_f0"
            Append column: "stdev_f0"
        endif
        Set numeric value: i, "mean_f0", mean_f0
        Set numeric value: i, "stdev_f0", stdev_f0
    endfor
    
elsif analysis_type = 2
    # SPECTRAL ANALYSIS
    for i to num_windows
        selectObject: features
        start_time = Get value: i, "start"
        end_time = Get value: i, "end"
        
        selectObject: original_sound
        segment = Extract part: start_time, end_time, "rectangular", 1, "no"
        spectrum = To Spectrum: "yes"
        
        cog = Get centre of gravity: 2
        stdev = Get standard deviation: 2
        
        removeObject: segment, spectrum
        
        selectObject: features
        if i = 1
            Append column: "spectral_cog"
            Append column: "spectral_stdev"
        endif
        Set numeric value: i, "spectral_cog", cog
        Set numeric value: i, "spectral_stdev", stdev
    endfor
    
else
    # INTENSITY ANALYSIS
    intensity = To Intensity: 100, 0, "yes"
    
    for i to num_windows
        selectObject: features
        start_time = Get value: i, "start"
        end_time = Get value: i, "end"
        
        selectObject: intensity
        mean_int = Get mean: start_time, end_time, "energy"
        max_int = Get maximum: start_time, end_time, "Parabolic"
        
        selectObject: features
        if i = 1
            Append column: "mean_intensity"
            Append column: "max_intensity"
        endif
        Set numeric value: i, "mean_intensity", mean_int
        Set numeric value: i, "max_intensity", max_int
    endfor
endif

# === VECTORIZATION: Load into arrays ===
appendInfoLine: "Loading features into memory..."

selectObject: features
start_times# = zero#(num_windows)
end_times# = zero#(num_windows)
original_indices# = zero#(num_windows)
feature1# = zero#(num_windows)
feature2# = zero#(num_windows)

for i to num_windows
    start_times#[i] = Get value: i, "start"
    end_times#[i] = Get value: i, "end"
    original_indices#[i] = Get value: i, "index"
    
    if analysis_type = 1
        feature1#[i] = Get value: i, "mean_f0"
        feature2#[i] = Get value: i, "stdev_f0"
    elsif analysis_type = 2
        feature1#[i] = Get value: i, "spectral_cog"
        feature2#[i] = Get value: i, "spectral_stdev"
    else
        feature1#[i] = Get value: i, "mean_intensity"
        feature2#[i] = Get value: i, "max_intensity"
    endif
endfor

# === SORT AND SWEEP ===
appendInfoLine: "Sorting for efficient comparison..."

if analysis_type = 1
    selectObject: features
    Sort rows: "mean_f0"
elsif analysis_type = 2
    selectObject: features
    Sort rows: "spectral_cog"
else
    selectObject: features
    Sort rows: "mean_intensity"
endif

# Reload sorted arrays
for i to num_windows
    selectObject: features
    original_indices#[i] = Get value: i, "index"
    
    if analysis_type = 1
        feature1#[i] = Get value: i, "mean_f0"
        feature2#[i] = Get value: i, "stdev_f0"
    elsif analysis_type = 2
        feature1#[i] = Get value: i, "spectral_cog"
        feature2#[i] = Get value: i, "spectral_stdev"
    else
        feature1#[i] = Get value: i, "mean_intensity"
        feature2#[i] = Get value: i, "max_intensity"
    endif
endfor

# === STEP 2: Build Dictionary ===
appendInfoLine: ""
appendInfoLine: "Building similarity dictionary..."

dictionary = Create Table with column names: "dictionary", 0, "window_id similar_to distance"

num_pairs = 0
comparisons_made = 0
comparisons_skipped = 0

if analysis_type = 1
    max_acceptable_diff = 600 * (1 - similarity_threshold)
elsif analysis_type = 2
    max_acceptable_diff = 5000 * (1 - similarity_threshold)
else
    max_acceptable_diff = 100 * (1 - similarity_threshold)
endif

for i to num_windows - 1
    f1_i = feature1#[i]
    f2_i = feature2#[i]
    idx_i = original_indices#[i]
    
    if f1_i <> undefined
        for j from i + 1 to num_windows
            f1_j = feature1#[j]
            f2_j = feature2#[j]
            
            if f1_j <> undefined
                idx_j = original_indices#[j]
                
                primary_diff = abs(f1_j - f1_i)
                
                if primary_diff > max_acceptable_diff
                    comparisons_skipped += (num_windows - j + 1)
                    j = num_windows + 1
                else
                    comparisons_made += 1
                    
                    if distance_metric = 1
                        dist = sqrt((f1_i - f1_j)^2 + (f2_i - f2_j)^2)
                        if analysis_type = 1
                            max_dist = 600
                        elsif analysis_type = 2
                            max_dist = 5000
                        else
                            max_dist = 100
                        endif
                        
                    elsif distance_metric = 2
                        dist = abs(f1_i - f1_j) / max(abs(f1_i), abs(f1_j) + 0.0001)
                        max_dist = 1
                        
                    else
                        dist = 1 - (min(abs(f1_i), abs(f1_j)) / (max(abs(f1_i), abs(f1_j)) + 0.0001))
                        max_dist = 1
                    endif
                    
                    similarity = 1 - (dist / max_dist)
                    
                    if similarity >= similarity_threshold
                        selectObject: dictionary
                        Append row
                        num_pairs += 1
                        Set numeric value: num_pairs, "window_id", idx_i
                        Set numeric value: num_pairs, "similar_to", idx_j
                        Set numeric value: num_pairs, "distance", dist
                    endif
                endif
            endif
        endfor
    endif
endfor

selectObject: dictionary
num_patterns = Get number of rows

appendInfoLine: "Found ", num_patterns, " similar pattern pairs"
appendInfoLine: "Comparisons: ", comparisons_made, " made, ", comparisons_skipped, " skipped"

total_possible = (num_windows * (num_windows - 1)) / 2
speedup = 1
if comparisons_made > 0
    speedup = total_possible / comparisons_made
    appendInfoLine: "Speedup: ", fixed$(speedup, 2), "x"
endif

# === STEP 3: Create Variations ===
appendInfoLine: ""
appendInfoLine: "Creating variations..."

num_output_windows = floor(output_duration_s / window_size_s)
segment_ids# = zero#(num_output_windows)
used_windows# = zero#(num_output_windows)

for out_i to num_output_windows
    if out_i mod 20 = 0
        appendInfoLine: "  ", floor(out_i / num_output_windows * 100), "%"
    endif
    
    if num_patterns > 0 and randomize_dictionary_order
        selectObject: dictionary
        random_pair = randomInteger(1, num_patterns)
        window_idx = Get value: random_pair, "window_id"
        
        if randomUniform(0, 1) > 0.5
            window_idx = Get value: random_pair, "similar_to"
        endif
    else
        window_idx = ((out_i - 1) mod num_windows) + 1
    endif
    
    used_windows#[out_i] = window_idx
    
    start_time = start_times#[window_idx]
    end_time = end_times#[window_idx]
    
    selectObject: original_sound
    segment = Extract part: start_time, end_time, "rectangular", 1, "no"
    
    varied_segment = segment
    
    if variation_method = 1
        # Pitch shift
        shift_semitones = randomGauss(0, 12 * variation_amount)
        shift_factor = 2^(shift_semitones/12)
        shiftStr$ = string$(shift_factor)
        
        selectObject: segment
        manipulation = To Manipulation: 0.01, 75, 600
        pitch_tier = Extract pitch tier
        Formula: "self * " + shiftStr$
        plusObject: manipulation
        Replace pitch tier
        selectObject: manipulation
        varied_segment = Get resynthesis (overlap-add)
        removeObject: manipulation, pitch_tier
        
    elsif variation_method = 2
        # Time stretch
        stretch_factor = 1 + randomGauss(0, variation_amount)
        stretch_factor = max(0.5, min(2, stretch_factor))
        selectObject: segment
        manipulation = To Manipulation: 0.01, 75, 600
        duration_tier = Extract duration tier
        Add point: start_time + window_size_s/2, stretch_factor
        plusObject: manipulation
        Replace duration tier
        selectObject: manipulation
        varied_segment = Get resynthesis (overlap-add)
        removeObject: manipulation, duration_tier
        
    elsif variation_method = 3
        # Amplitude modulation
        selectObject: segment
        varied_segment = Copy: "modulated"
        mod_freq = 10 * (1 + variation_amount * 10)
        varAmtStr$ = string$(variation_amount)
        modFreqStr$ = string$(mod_freq)
        Formula: "self * (1 + " + varAmtStr$ + " * sin(2*pi*" + modFreqStr$ + "*x))"
        
    elsif variation_method = 4
        # Spectral filter
        selectObject: segment
        spectrum = To Spectrum: "yes"
        cutoff = 1000 + randomUniform(-500, 500) * variation_amount
        cutoffStr$ = string$(cutoff)
        filterStr$ = string$(1 - variation_amount)
        Formula: "if x < " + cutoffStr$ + " then self * " + filterStr$ + " else self fi"
        varied_segment = To Sound
        removeObject: spectrum
        
    elsif variation_method = 5
        # Reverse
        if randomUniform(0, 1) < variation_amount
            selectObject: segment
            varied_segment = Copy: "reversed"
            Reverse
        endif
        
    else
        # Granular shuffle
        grain_size = 0.02
        num_grains = floor(window_size_s / grain_size)
        if num_grains < 1
            num_grains = 1
        endif
        grain_ids# = zero#(num_grains)
        
        selectObject: segment
        segDur = Get total duration
        
        for g to num_grains
            shuffled_idx = randomInteger(1, num_grains)
            shuffled_start = (shuffled_idx - 1) * grain_size
            shuffled_end = min(shuffled_start + grain_size, segDur)
            
            if shuffled_end > shuffled_start
                selectObject: segment
                temp_grain = Extract part: shuffled_start, shuffled_end, "Hanning", 1, "no"
                grain_ids#[g] = temp_grain
            else
                Create Sound from formula: "grain", 1, 0, 0.001, sample_rate, "0"
                grain_ids#[g] = selected("Sound")
            endif
        endfor
        
        selectObject: grain_ids#[1]
        for g from 2 to num_grains
            plusObject: grain_ids#[g]
        endfor
        varied_segment = Concatenate
        
        for g to num_grains
            removeObject: grain_ids#[g]
        endfor
    endif
    
    segment_ids#[out_i] = varied_segment
    
    if varied_segment <> segment
        removeObject: segment
    endif
endfor

# === Concatenate All Segments ===
appendInfoLine: ""
appendInfoLine: "Concatenating..."

selectObject: segment_ids#[1]
for i from 2 to num_output_windows
    plusObject: segment_ids#[i]
endfor

output = Concatenate
Rename: sound_name$ + "_LZ_" + presetName$

for i to num_output_windows
    removeObject: segment_ids#[i]
endfor

# Trim to exact duration
selectObject: output
current_duration = Get total duration
if current_duration > output_duration_s
    trimmed = Extract part: 0, output_duration_s, "rectangular", 1, "no"
    removeObject: output
    output = trimmed
    selectObject: output
    Rename: sound_name$ + "_LZ_" + presetName$
endif

selectObject: output
Scale peak: 0.95
final_duration = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "LZ Audio Variations: " + sound_name$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: original_sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: output
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "LZ Result"
    Text bottom: "yes", "Time (s)"
    
    # Dictionary usage visualization
    Select outer viewport: 0, 8, 3.3, 4.8
    Select inner viewport: 0.6, 7.6, 3.5, 4.7
    
    Axes: 0, num_output_windows, 0, num_windows
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, num_output_windows, 0, num_windows
    
    for i to num_output_windows
        srcWin = used_windows#[i]
        if srcWin > 0
            colorVal = srcWin / num_windows
            rVal$ = fixed$(0.3 + colorVal * 0.5, 2)
            gVal$ = fixed$(0.3, 2)
            bVal$ = fixed$(0.8 - colorVal * 0.5, 2)
            dotColor$ = "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}"
            Paint circle (mm): dotColor$, i, srcWin, 1.5
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text bottom: "yes", "Output window"
    
    # Feature distribution
    Select outer viewport: 0, 4, 5.0, 6.2
    Select inner viewport: 0.6, 3.8, 5.2, 6.1
    
    minF1 = undefined
    maxF1 = undefined
    for i to num_windows
        if feature1#[i] <> undefined
            if minF1 = undefined
                minF1 = feature1#[i]
                maxF1 = feature1#[i]
            else
                if feature1#[i] < minF1
                    minF1 = feature1#[i]
                endif
                if feature1#[i] > maxF1
                    maxF1 = feature1#[i]
                endif
            endif
        endif
    endfor
    
    if minF1 = undefined
        minF1 = 0
        maxF1 = 1
    endif
    
    if minF1 = maxF1
        maxF1 = minF1 + 1
    endif
    
    Axes: 0, num_windows, minF1, maxF1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, num_windows, minF1, maxF1
    
    for i to num_windows
        if feature1#[i] <> undefined
            Paint circle (mm): "{0.3, 0.5, 0.8}", i, feature1#[i], 1.2
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", analysis_name$
    Text bottom: "yes", "Window"
    
    # Dictionary stats
    Select outer viewport: 4, 8, 5.0, 6.2
    Select inner viewport: 4.4, 7.6, 5.2, 6.1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.8, "half", "Dictionary Stats"
    Font size: 8
    Text: 0.5, "centre", 0.55, "half", "Windows: " + string$(num_windows)
    Text: 0.5, "centre", 0.35, "half", "Similar pairs: " + string$(num_patterns)
    if comparisons_made > 0
        Text: 0.5, "centre", 0.15, "half", "Speedup: " + fixed$(speedup, 1) + "x"
    endif
    
    # Legend
    Select outer viewport: 0, 8, 6.3, 6.6
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Analysis: " + analysis_name$ + " | Variation: " + variation_name$ + " | Threshold: " + fixed$(similarity_threshold, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", sound_name$, "_LZ_", presetName$
appendInfoLine: "Duration: ", fixed$(final_duration, 2), " s"
appendInfoLine: "Dictionary: ", num_patterns, " pairs"

# === Cleanup ===
if analysis_type = 1
    removeObject: pitch
elsif analysis_type = 3
    removeObject: intensity
endif

removeObject: features, dictionary

# === Play ===
if play_result
    selectObject: output
    Play
endif

selectObject: output