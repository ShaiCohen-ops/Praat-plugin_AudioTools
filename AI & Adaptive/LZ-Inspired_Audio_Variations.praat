# ============================================================
# Praat AudioTools - LZ-Inspired_Audio_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Feature-Similarity Audio Variations (LZ-inspired). Despite the
#   filename, this is NOT Lempel-Ziv compression. It uses a
#   feature-based nearest-neighbor approach: each input window is
#   characterized by a small feature vector (e.g. mean F0, stdev F0
#   for pitch analysis), and the script builds a dictionary of
#   above-threshold-similar window pairs. The output concatenates
#   variations of windows drawn from that dictionary.
#
#   The "LZ" connection is conceptual: a dictionary of recurring
#   patterns. The actual algorithm is content-based concatenation
#   with optional per-segment audio variation.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5 (2026):
#   - FIX (audible): output segments were rectangular and plain-
#     Concatenated -- a discontinuity CLICK at every segment
#     boundary, on every preset. v0.5 applies 2 ms raised-cosine
#     edge fades to each varied segment and joins with
#     Concatenate-with-overlap (2 ms crossfades). The output window
#     count gains headroom for the crossfade shrink; the existing
#     trim still lands the exact target duration. (The Hann-grain
#     dips INSIDE Granular shuffle are left as-is: that amplitude
#     texture is the granular aesthetic; the top-level clicks were
#     not.)
#   - FIX: the v0.4 claim that "the similarity check now uses both
#     features" was only true for the Euclidean metric. Correlation
#     and Cosine read feature1 alone, so AmbientDrift (Correlation)
#     kept exactly the vibrato-blind false positives v0.4 said it
#     fixed. Both metrics now average per-feature relative
#     distances over feature1 AND feature2. The sorted-sweep prune
#     stays valid: rel-diff <= (1-thr) on the average still implies
#     |f1 diff| <= (1-thr) * max_dist_global... no -- the f1 term
#     alone can exceed (1-thr) while the average passes, so the
#     prune bound is DOUBLED for metrics 2/3 (still a large
#     speedup, never drops a valid pair).
#   - FIX: Spectrum analysis used a hardcoded 5000 Hz scale for
#     similarity/pruning, but spectral CoG ranges to Nyquist --
#     bright material was over-pruned and similarity mis-scaled.
#     Now sample_rate / 2.
#   - FIX: the time-stretch duration-tier point was placed at
#     ORIGINAL-time coordinates on a tier whose domain starts at 0
#     (the segment is extracted rebased). It worked only through
#     RealTier constant extrapolation; the point now sits at the
#     segment's own midpoint.
#   - VIZ: title bar uses an explicit inner viewport (outer-only
#     form risks the margin-compression text collision).
#
# Changelog v0.4:
#   - Fix (Spectral filter, variation method 4): two bugs.
#     (a) v0.3 attenuated frequencies BELOW the cutoff
#     (high-pass), even though "Spectral filter" with a
#     "cutoff" parameter implies low-pass. Renamed option
#     to "Spectral lowpass" and inverted the comparison.
#     (b) `varied_segment = To Sound` on a Spectrum returns
#     a Sound padded to the next power of 2 above 2x duration.
#     v0.3 didn't trim back, producing segments that were
#     ~2x as long as expected and concatenating into a
#     wrong-length output. Fixed with Extract part to the
#     original segment duration.
#   - Fix (Granular shuffle, variation method 6): v0.3's
#     `variation_amount` was ignored — every run produced the
#     same character of shuffle. v0.4 uses variation_amount
#     to control the maximum displacement of each grain from
#     its original position (0 = no displacement, identity;
#     1 = unrestricted shuffle). Now the parameter does
#     what its name implies.
#   - Speed: dictionary now stored as parallel arrays
#     (pairLeft#, pairRight#, pairDist#) instead of a Praat
#     Table with Append row + Set value per pair. The Table
#     is still built for visualization compatibility, but the
#     output loop uses arrays. ~10-50x speedup on dictionary
#     construction and lookup.
#   - Sweep now uses feature2 as a secondary acceptance check.
#     v0.3 sorted by feature1 and pruned only on feature1 distance,
#     so two windows with identical mean-F0 but very different
#     vibrato (stdev_F0) were reported as similar. v0.4 still
#     sorts by feature1 (preserving the O(n log n) advantage),
#     but the similarity check now uses both features in the
#     distance calculation as before — and the early-termination
#     comparison properly accounts for feature2's potential
#     contribution. False positives caused by stdev mismatch
#     are now correctly excluded.
#   - NEW: Output_mode form parameter. Three options:
#       Random   - v0.3 behavior (random pick from dictionary)
#       Chain    - follow similarity chains for cohesion
#       Hybrid   - default. Chain for ~3 windows, then jump.
#     Hybrid produces audibly recurring patterns without
#     getting stuck in dead-end loops on sparse dictionaries.
#   - Visualization rewritten to suite 8x8 standard with title
#     bar + metadata subtitle, aligned panel titles, and a
#     proper summary stats bar.
#   - Header description rewrites the LZ framing honestly:
#     this is feature-similarity-driven concatenation, not
#     Lempel-Ziv compression. Filename unchanged.
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

form Feature-Similarity Audio Variations (LZ-inspired)
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
        option Spectral lowpass
        option Reverse
        option Granular shuffle
    real Variation_amount 0.5
    comment === Output ===
    positive Output_duration_s 10
    optionmenu Output_mode: 3
        option Random (incoherent scatter)
        option Chain (follow similarity links)
        option Hybrid (chain ~3, then jump)
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
    output_mode = 3
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
    output_mode = 3
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
    output_mode = 2
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
    output_mode = 1
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
    output_mode = 2
    presetName$ = "AmbientDrift"
else
    presetName$ = "Custom"
endif

selectObject: original_sound
sample_rate = Get sampling frequency
total_duration = Get total duration

# === Resolve display names ===
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
    variation_name$ = "Lowpass"
elsif variation_method = 5
    variation_name$ = "Reverse"
else
    variation_name$ = "Granular"
endif

if output_mode = 1
    output_mode_name$ = "Random"
elsif output_mode = 2
    output_mode_name$ = "Chain"
else
    output_mode_name$ = "Hybrid"
endif

# === Info ===
clearinfo
writeInfoLine: "=== Feature-Similarity Audio Variations v0.5 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(total_duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis: ", analysis_name$
appendInfoLine: "Window: ", window_size_s, " s | Overlap: ", overlap * 100, "%"
appendInfoLine: "Similarity threshold: ", similarity_threshold
appendInfoLine: "Variation: ", variation_name$, " (amount=", variation_amount, ")"
appendInfoLine: "Output mode: ", output_mode_name$
appendInfoLine: ""

# === Calculate Windows ===
hop_size = window_size_s * (1 - overlap)
num_windows = floor((total_duration - window_size_s) / hop_size) + 1

if num_windows < 2
    exitScript: "Source too short for the chosen window/overlap settings."
endif

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

# === Load features into arrays ===
appendInfoLine: "Loading features..."

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

# === Sort by feature1 for sweep pruning ===
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
    start_times#[i] = Get value: i, "start"
    end_times#[i] = Get value: i, "end"
    
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

# === STEP 2: Build Dictionary  (arrays + Table for viz) ===
appendInfoLine: ""
appendInfoLine: "Building similarity dictionary..."

# Empty Table kept for visualization compatibility — populated at end
dictionary = Create Table with column names: "dictionary", 0, "window_id similar_to distance"

# Pre-allocate arrays. Worst case is num_windows^2/2 pairs but typical
# threshold use produces far fewer; we resize semantics by tracking count.
maxPairs = num_windows * (num_windows - 1) / 2
if maxPairs < 1
    maxPairs = 1
endif
pairLeft# = zero# (maxPairs)
pairRight# = zero# (maxPairs)
pairDist# = zero# (maxPairs)

num_pairs = 0
comparisons_made = 0
comparisons_skipped = 0

if analysis_type = 1
    max_acceptable_diff = 600 * (1 - similarity_threshold)
    max_dist_global = 600
elsif analysis_type = 2
    # v0.5: spectral CoG ranges to Nyquist, not 5000 Hz -- the old
    # hardcoded scale over-pruned bright material and mis-scaled
    # similarity
    max_dist_global = sample_rate / 2
    max_acceptable_diff = max_dist_global * (1 - similarity_threshold)
else
    max_acceptable_diff = 100 * (1 - similarity_threshold)
    max_dist_global = 100
endif

# v0.5: metrics 2/3 average per-feature RELATIVE distances, so the
# feature1 term alone may reach twice the threshold while the average
# still qualifies -- the sorted-sweep prune bound doubles (still a
# large speedup; never drops a valid pair).
if distance_metric <> 1
    max_acceptable_diff = max_acceptable_diff * 2
endif

stopwatch

for i to num_windows - 1
    f1_i = feature1#[i]
    f2_i = feature2#[i]
    idx_i = original_indices#[i]
    
    if f1_i <> undefined
        j = i + 1
        innerActive = 1
        while j <= num_windows and innerActive = 1
            f1_j = feature1#[j]
            f2_j = feature2#[j]
            
            if f1_j <> undefined
                idx_j = original_indices#[j]
                
                primary_diff = abs(f1_j - f1_i)
                
                if primary_diff > max_acceptable_diff
                    # Sorted order means any further j can only have
                    # larger primary_diff. Skip rest of inner loop.
                    comparisons_skipped += (num_windows - j + 1)
                    innerActive = 0
                else
                    comparisons_made += 1
                    
                    # v0.5: all three metrics use BOTH features (v0.4
                    # only fixed Euclidean; Correlation/Cosine stayed
                    # feature1-only). Windows with undefined feature2
                    # (e.g. pitch stdev over <2 voiced frames) fall
                    # back to the feature1-only form instead of
                    # silently failing the comparison.
                    f2ok = 1
                    if f2_i = undefined or f2_j = undefined
                        f2ok = 0
                    endif
                    
                    if distance_metric = 1
                        # Euclidean
                        if f2ok
                            dist = sqrt((f1_i - f1_j)^2 + (f2_i - f2_j)^2)
                        else
                            dist = abs(f1_i - f1_j)
                        endif
                        max_dist = max_dist_global
                    elsif distance_metric = 2
                        # Correlation-style normalized difference,
                        # averaged over both features
                        d1rel = abs(f1_i - f1_j) / max(abs(f1_i), abs(f1_j) + 0.0001)
                        if f2ok
                            d2rel = abs(f2_i - f2_j) / max(abs(f2_i), abs(f2_j) + 0.0001)
                            dist = 0.5 * (d1rel + d2rel)
                        else
                            dist = d1rel
                        endif
                        max_dist = 1
                    else
                        # Cosine-style, averaged over both features
                        d1rel = 1 - (min(abs(f1_i), abs(f1_j)) / (max(abs(f1_i), abs(f1_j)) + 0.0001))
                        if f2ok
                            d2rel = 1 - (min(abs(f2_i), abs(f2_j)) / (max(abs(f2_i), abs(f2_j)) + 0.0001))
                            dist = 0.5 * (d1rel + d2rel)
                        else
                            dist = d1rel
                        endif
                        max_dist = 1
                    endif
                    
                    similarity = 1 - (dist / max_dist)
                    
                    if similarity >= similarity_threshold
                        num_pairs += 1
                        if num_pairs <= maxPairs
                            pairLeft#[num_pairs] = idx_i
                            pairRight#[num_pairs] = idx_j
                            pairDist#[num_pairs] = dist
                        endif
                    endif
                endif
            endif
            j += 1
        endwhile
    endif
endfor

dictBuildTime = stopwatch
appendInfoLine: "  Dictionary built in ", fixed$(dictBuildTime, 3), " s"

# Populate the visualization Table (one-shot, after array building)
selectObject: dictionary
for p to num_pairs
    Append row
    Set numeric value: p, "window_id", pairLeft#[p]
    Set numeric value: p, "similar_to", pairRight#[p]
    Set numeric value: p, "distance", pairDist#[p]
endfor

appendInfoLine: "Found ", num_pairs, " similar pattern pairs"
appendInfoLine: "Comparisons: ", comparisons_made, " made, ", comparisons_skipped, " skipped"

total_possible = (num_windows * (num_windows - 1)) / 2
speedup = 1
if comparisons_made > 0
    speedup = total_possible / comparisons_made
    appendInfoLine: "Pruning speedup: ", fixed$(speedup, 2), "x vs naive O(n^2)"
endif

# ============================================================
# Build "neighbor list" for chain mode
# windowNeighborCount#[w] = how many similar partners window w has
# windowNeighbor#[w][k]  = the k-th partner of window w
# ============================================================
windowNeighborCount# = zero# (num_windows)

# First pass: count neighbors per window
for p to num_pairs
    pL = pairLeft#[p]
    pR = pairRight#[p]
    if pL >= 1 and pL <= num_windows
        windowNeighborCount#[pL] = windowNeighborCount#[pL] + 1
    endif
    if pR >= 1 and pR <= num_windows
        windowNeighborCount#[pR] = windowNeighborCount#[pR] + 1
    endif
endfor

# Find max neighbor count to allocate the inner array
maxNeighbors = 1
for w to num_windows
    if windowNeighborCount#[w] > maxNeighbors
        maxNeighbors = windowNeighborCount#[w]
    endif
endfor

# Allocate a flat 1D array as a 2D table: windowNeighbor[w, k] at index (w-1)*maxNeighbors + k
totalNeighborSlots = num_windows * maxNeighbors
windowNeighbor# = zero# (totalNeighborSlots)
windowNeighborFill# = zero# (num_windows)

for p to num_pairs
    pL = pairLeft#[p]
    pR = pairRight#[p]
    if pL >= 1 and pL <= num_windows
        windowNeighborFill#[pL] = windowNeighborFill#[pL] + 1
        slotL = (pL - 1) * maxNeighbors + windowNeighborFill#[pL]
        windowNeighbor#[slotL] = pR
    endif
    if pR >= 1 and pR <= num_windows
        windowNeighborFill#[pR] = windowNeighborFill#[pR] + 1
        slotR = (pR - 1) * maxNeighbors + windowNeighborFill#[pR]
        windowNeighbor#[slotR] = pL
    endif
endfor

# === STEP 3: Generate Output ===
appendInfoLine: ""
appendInfoLine: "Creating variations..."

# v0.5: headroom for the 2 ms crossfade shrink at every join;
# the trim below lands the exact target
xfadeSec = 0.002
effAdvance = window_size_s - xfadeSec
if effAdvance < 0.005
    effAdvance = 0.005
endif
num_output_windows = ceiling(output_duration_s / effAdvance) + 1
if num_output_windows < 1
    num_output_windows = 1
endif

segment_ids# = zero#(num_output_windows)
used_windows# = zero#(num_output_windows)

# Chain-mode state
chainCurrent = 0
chainStepsRemaining = 0

for out_i to num_output_windows
    if out_i mod 20 = 0
        appendInfoLine: "  ", floor(out_i / num_output_windows * 100), "%"
    endif
    
    # ---- Pick window_idx based on output_mode ----
    if num_pairs = 0
        # No similar pairs found — fall back to sequential pick
        window_idx = ((out_i - 1) mod num_windows) + 1
    elsif output_mode = 1
        # RANDOM (v0.3 behavior)
        random_pair = randomInteger(1, num_pairs)
        if randomUniform(0, 1) > 0.5
            window_idx = pairLeft#[random_pair]
        else
            window_idx = pairRight#[random_pair]
        endif
    elsif output_mode = 2 or output_mode = 3
        # CHAIN or HYBRID
        # Both follow similarity links; HYBRID resets chain after ~3 steps
        if chainCurrent = 0 or windowNeighborCount#[chainCurrent] = 0 or chainStepsRemaining = 0
            # Start new chain: random pick from any window with neighbors
            chainAttempts = 0
            done = 0
            while done = 0 and chainAttempts < 20
                candidate = randomInteger(1, num_windows)
                if windowNeighborCount#[candidate] > 0
                    chainCurrent = candidate
                    done = 1
                endif
                chainAttempts = chainAttempts + 1
            endwhile
            if done = 0
                # Couldn't find any window with neighbors — fall back
                chainCurrent = randomInteger(1, num_windows)
            endif
            if output_mode = 3
                # Hybrid: chain length 2-4 random
                chainStepsRemaining = randomInteger(2, 4)
            else
                # Pure chain: long chain
                chainStepsRemaining = num_output_windows
            endif
            window_idx = chainCurrent
        else
            # Step within current chain — pick a random neighbor
            nC = windowNeighborCount#[chainCurrent]
            if nC > 0
                pickK = randomInteger(1, nC)
                slot = (chainCurrent - 1) * maxNeighbors + pickK
                next_w = windowNeighbor#[slot]
                window_idx = next_w
                chainCurrent = next_w
                chainStepsRemaining = chainStepsRemaining - 1
            else
                # No neighbors (shouldn't happen given check above)
                window_idx = chainCurrent
                chainStepsRemaining = 0
            endif
        endif
    endif
    
    if window_idx < 1
        window_idx = 1
    endif
    if window_idx > num_windows
        window_idx = num_windows
    endif
    
    used_windows#[out_i] = window_idx
    
    start_time = start_times#[window_idx]
    end_time = end_times#[window_idx]
    
    selectObject: original_sound
    segment = Extract part: start_time, end_time, "rectangular", 1, "no"
    
    selectObject: segment
    seg_dur = Get total duration
    
    varied_segment = segment
    
    # ---- Apply variation ----
    if variation_method = 1
        # Pitch shift (PSOLA)
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
        # v0.5: the segment is extracted rebased to 0, so the tier
        # point belongs at the SEGMENT midpoint (the old original-
        # time coordinate worked only via constant extrapolation)
        Add point: seg_dur / 2, stretch_factor
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
        # SPECTRAL LOWPASS (FIXED v0.4)
        # v0.3 attenuated below cutoff (high-pass) and didn't trim
        # the To Sound output. v0.4 attenuates above cutoff (true
        # low-pass) and trims to original segment duration.
        selectObject: segment
        spectrum = To Spectrum: "yes"
        cutoff = 1000 + randomUniform(-500, 500) * variation_amount
        cutoffStr$ = string$(cutoff)
        attenStr$ = string$(1 - variation_amount)
        # Attenuate frequencies ABOVE cutoff (proper lowpass)
        Formula: "if x > " + cutoffStr$ + " then self * " + attenStr$ + " else self fi"
        sound_padded = To Sound
        # Trim back to original segment duration (v0.3 bug fix)
        selectObject: sound_padded
        varied_segment = Extract part: 0, seg_dur, "rectangular", 1, "no"
        removeObject: spectrum, sound_padded
    
    elsif variation_method = 5
        # Reverse
        if randomUniform(0, 1) < variation_amount
            selectObject: segment
            varied_segment = Copy: "reversed"
            Reverse
        endif
    
    else
        # Granular shuffle (FIXED v0.4)
        # v0.3 ignored variation_amount entirely.
        # v0.4 uses variation_amount as the maximum displacement of
        # each grain from its original position. 0 = identity (every
        # grain stays in place). 1 = unrestricted shuffle.
        grain_size = 0.02
        num_grains = floor(seg_dur / grain_size)
        if num_grains < 1
            num_grains = 1
        endif
        
        # Maximum displacement in grains
        maxShift = round(num_grains * variation_amount)
        if maxShift < 0
            maxShift = 0
        endif
        
        grain_ids# = zero#(num_grains)
        
        for g to num_grains
            # Choose source grain index, displaced by up to ±maxShift
            if maxShift = 0
                shuffled_idx = g
            else
                displacement = randomInteger(-maxShift, maxShift)
                shuffled_idx = g + displacement
                if shuffled_idx < 1
                    shuffled_idx = 1
                endif
                if shuffled_idx > num_grains
                    shuffled_idx = num_grains
                endif
            endif
            shuffled_start = (shuffled_idx - 1) * grain_size
            shuffled_end = min(shuffled_start + grain_size, seg_dur)
            
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
    
    # v0.5: 2 ms raised-cosine edge fades so the crossfaded joins
    # are click-free (segments were rectangular and butt-joined:
    # a discontinuity at every boundary)
    selectObject: varied_segment
    vsDur = Get total duration
    if vsDur > 3 * xfadeSec
        Fade in: 0, 0, xfadeSec, "yes"
        Fade out: 0, vsDur, -xfadeSec, "yes"
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

# v0.5: crossfaded join (was plain Concatenate -- clicks)
output = Concatenate with overlap: xfadeSec
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
final_peak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##FEATURE-SIMILARITY AUDIO VARIATIONS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... sound_name$
        ... + "  |  " + presetName$
        ... + "  |  Analysis: " + analysis_name$
        ... + "  |  " + string$(num_pairs) + " pairs"
        ... + "  |  " + variation_name$
        ... + "  |  " + output_mode_name$
    
    # ----------------------------------------------------------
    # PANEL A: DICTIONARY USAGE  (left, headline)
    # X = output window position (chronological)
    # Y = source window index (where each output came from)
    # Color: chain-vs-jump indicator if mode = chain/hybrid
    # Reveals the recurrence pattern of the output.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, num_output_windows + 1, 0, num_windows + 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, num_output_windows + 1, 0, num_windows + 1
    
    # Light grid every ~num_windows/8
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    grid_step = round(num_windows / 8)
    if grid_step < 1
        grid_step = 1
    endif
    yg = grid_step
    while yg <= num_windows
        Draw line: 0, yg, num_output_windows + 1, yg
        yg = yg + grid_step
    endwhile
    
    # Connecting lines between consecutive output windows (shows chain structure)
    if output_mode = 2 or output_mode = 3
        Colour: "{0.85, 0.78, 0.55}"
        Line width: 1
        for o from 2 to num_output_windows
            prev = used_windows#[o - 1]
            curr = used_windows#[o]
            if prev > 0 and curr > 0
                Draw line: o - 1, prev, o, curr
            endif
        endfor
    endif
    
    # Source window markers
    for i to num_output_windows
        srcWin = used_windows#[i]
        if srcWin > 0
            colorVal = srcWin / num_windows
            cR = 0.30 + colorVal * 0.55
            cG = 0.40 - abs(colorVal - 0.5) * 0.20
            cB = 0.85 - colorVal * 0.55
            if cG < 0
                cG = 0
            endif
            if cB < 0
                cB = 0
            endif
            rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
            Paint circle (mm): rgb$, i, srcWin, 1.4
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Source window"
    Text bottom: "yes", "Output window  (line = chain link)"
    
    # ----------------------------------------------------------
    # PANEL B: FEATURE DISTRIBUTION  (right, upper)
    # Per-window feature1 values, with similar-pairs marked.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
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
    
    fPad = (maxF1 - minF1) * 0.08
    
    Axes: 0, num_windows + 1, minF1 - fPad, maxF1 + fPad
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, num_windows + 1, minF1 - fPad, maxF1 + fPad
    
    # Plot pairs as light lines connecting the pair partners
    if num_pairs > 0 and num_pairs < 200
        Colour: "{0.85, 0.85, 0.55}"
        Line width: 1
        for p to num_pairs
            pL = pairLeft#[p]
            pR = pairRight#[p]
            if pL >= 1 and pL <= num_windows and pR >= 1 and pR <= num_windows
                if feature1#[pL] <> undefined and feature1#[pR] <> undefined
                    Draw line: pL, feature1#[pL], pR, feature1#[pR]
                endif
            endif
        endfor
    endif
    
    # Per-window feature dots, sized by neighbor count (busier = bigger)
    for i to num_windows
        if feature1#[i] <> undefined
            nC = windowNeighborCount#[i]
            mm = 1.0 + nC / max(1, maxNeighbors) * 2.0
            # Color: hot windows (many neighbors) = red, cold = blue
            ratio = nC / max(1, maxNeighbors)
            cR = 0.30 + ratio * 0.55
            cG = 0.40
            cB = 0.78 - ratio * 0.55
            if cB < 0
                cB = 0
            endif
            rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
            Paint circle (mm): rgb$, i, feature1#[i], mm
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", analysis_name$
    Text bottom: "yes", "Window  (size = #neighbors)"
    
    # ----------------------------------------------------------
    # PANEL C: NEIGHBOR-COUNT HISTOGRAM  (right, lower)
    # Distribution of "how many similar windows does this one have"
    # — characterizes the dictionary's connectivity.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    # Build histogram of windowNeighborCount values
    histMaxBin = maxNeighbors
    if histMaxBin < 4
        histMaxBin = 4
    endif
    if histMaxBin > 32
        histMaxBin = 32
    endif
    histN# = zero# (histMaxBin + 1)
    for w to num_windows
        nC = windowNeighborCount#[w]
        if nC > histMaxBin
            nC = histMaxBin
        endif
        histN#[nC + 1] = histN#[nC + 1] + 1
    endfor
    
    histPeak = 1
    for b to histMaxBin + 1
        if histN#[b] > histPeak
            histPeak = histN#[b]
        endif
    endfor
    
    Axes: -0.5, histMaxBin + 0.5, 0, histPeak * 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", -0.5, histMaxBin + 0.5, 0, histPeak * 1.15
    
    # Bars
    for b to histMaxBin + 1
        nC = b - 1
        if histN#[b] > 0
            ratio = nC / max(1, maxNeighbors)
            cR = 0.30 + ratio * 0.55
            cG = 0.40
            cB = 0.78 - ratio * 0.55
            if cB < 0
                cB = 0
            endif
            rgb$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
            Paint rectangle: rgb$, nC - 0.4, nC + 0.4, 0, histN#[b]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Count"
    Text bottom: "yes", "# neighbors per window"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Dictionary usage  (which output came from which source)"
    Text: 6.10, "centre", 7.30, "half", "Feature distribution (upper) & neighbor histogram (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: output
    nResultCh = Get number of channels
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: 0, final_duration, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, final_duration, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, final_duration, 0
    
    selectObject: output
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        selectObject: output
        Extract one channel: 2
        vCh2 = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh2
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh > 1
        Text top: "no", "Output  (blue=L  orange=R)"
    else
        Text top: "no", "Output (mono)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sound_name$
        ... + "  |  Windows: " + string$(num_windows)
        ... + "  |  Pairs: " + string$(num_pairs)
        ... + "  |  Threshold: " + fixed$(similarity_threshold, 2)
        ... + "  |  Pruning: " + fixed$(speedup, 1) + "x"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Window: " + fixed$(window_size_s, 3) + "s, " + fixed$(overlap * 100, 0) + "% overlap"
        ... + "  |  Variation: " + variation_name$ + " (" + fixed$(variation_amount, 2) + ")"
        ... + "  |  Output mode: " + output_mode_name$
        ... + "  |  Out: " + fixed$(final_duration, 2) + " s, peak " + fixed$(final_peak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: output
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(final_duration, 2), " s"
appendInfoLine: "Dictionary: ", num_pairs, " pairs"

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
