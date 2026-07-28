# ============================================================
# Praat AudioTools - LZ-Inspired_Audio_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026) - Correct window mapping, single envelope, exact duration
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.6 (2026):
#
#   NOTE: audio is NOT comparable to v0.5. Until now the renderer was
#   playing different windows from the ones the dictionary chose.
#
#   CRITICAL 1 - the chosen window and the rendered audio were not the
#     same window. The feature Table was sorted by feature1 for the
#     sweep, and start_times#/end_times# were then RELOADED in sorted
#     order - but the dictionary stored ORIGINAL window indices, and
#     the renderer indexed the sorted time arrays with them. Measured
#     on a 6 s source at the defaults: all 119 windows changed position
#     under the sort, and 63 of 63 rendered segments - 100% - played a
#     different window from the one selected. Sorted row 17 held
#     original window 86, so choosing window 17 rendered 4.250 s
#     instead of 0.800 s. Every similarity fix from v0.4 and v0.5 was
#     therefore inaudible, and Panel B plotted one window's links over
#     another window's coordinates.
#     Confirmed by correlating the rendered head against the audio of
#     the window the dictionary actually chose: v0.5 selected window 68
#     (true start 3.350 s), rendered 5.550 s, and correlated -0.070 -
#     unrelated material. v0.6 selects window 98, renders 4.850 s, and
#     correlates 1.00000.
#     v0.6 keeps two separate sets of arrays: startByOrig#/endByOrig#
#     indexed by original window number, and sortedF1#/sortedF2#/
#     sortedOrig# used only by the sweep. Nothing overwrites the first
#     set.
#
#   CRITICAL 2 - every join carried two envelopes. v0.5 added 2 ms
#     raised-cosine fades to each segment AND then joined with
#     Concatenate with overlap, which applies its own crossfade over
#     the same samples. The per-segment fades are gone; Praat's
#     crossfade handles the internal joins and a single fade is applied
#     to the head and tail of the finished output.
#
#   3 - The output now reaches the requested duration in every mode.
#     v0.5 assumed each segment stayed window_size_s long, which Time
#     stretch (0.5x to 2x) and Granular shuffle (which dropped the
#     remainder past the last whole 20 ms grain) both break. Segments
#     are now generated until the accumulated duration passes the
#     target, and the result is trimmed - or padded, if the material
#     genuinely runs out - to land exactly.
#
#   4 - "Correlation" and "Cosine" were neither. Both reduced to
#     (max - min) / max on absolute values, so they ranked almost
#     identically and threw away sign - which matters for the negative
#     values intensity analysis produces. Renamed to what they compute:
#     Mean relative difference and Mean magnitude-ratio difference.
#     Implementing a real cosine would need the two features treated as
#     one vector on comparable scales; that is a larger change and is
#     not smuggled in here.
#
#   5 - Pair storage is no longer allocated at O(n^2). v0.5 allocated
#     num_windows*(num_windows-1)/2 slots in each of three arrays
#     before finding a single pair: 10,000 windows would have demanded
#     roughly 50 million slots per array, three times over, before the
#     loop began. The sweep now runs twice - once to count, once to
#     fill exactly the space needed. Measured at the defaults: 2778
#     pairs against 7021 slots previously reserved.
#
#   6 - Minimum temporal separation. Nothing stopped windows 20 and 21
#     from pairing even though at 70% overlap they share 70% of their
#     samples, so the "dictionary of recurring patterns" filled up with
#     trivially adjacent matches. Measured on the Ambient Drift preset:
#     44 of 222 pairs, 19.8%, overlapped in time. Min_separation_s
#     defaults to the window size, which admits only non-overlapping
#     pairs; set it to 0 for the old behaviour.
#
#   7 - Granular shuffle. Two problems. (a) amount = 0 was documented
#     as identity but still cut the segment into Hann-windowed 20 ms
#     grains and butt-joined them, putting a dip every 20 ms; the
#     segment is now copied through untouched at 0. (b) Displacement
#     was drawn then CLAMPED to [1, num_grains], which piles a large
#     share of high-amount draws onto the first and last grain. The
#     source index is now drawn uniformly from the valid range around
#     each grain. The trailing partial grain is also kept rather than
#     discarded.
#
#   8 - Random_seed added (0 = unpredictable); the generator is
#     returned to its safe state at the end.
#
#   9 - Input validation for overlap, threshold, amount, window size
#     and duration, with the adjustments reported rather than silent.
#
#   10 - Pitch mode reports how many windows were excluded for having
#     no defined F0, and says so plainly when the dictionary ends up
#     empty because of it. (A voiced-fraction feature would serve
#     percussive material better; that is a model change, not a fix,
#     and is left for a later pass.)
#
# Changelog v0.5 (2026):
#   - FIX (audible): output segments were rectangular and plain-
#     Concatenated -- a discontinuity CLICK at every segment
#     boundary, on every preset. v0.5 applies 2 ms raised-cosine
#     edge fades to each varied segment and joins with
#     Concatenate-with-overlap (2 ms crossfades). (v0.6: the
#     per-segment fades were the double-envelope bug above.)
#   - FIX: Correlation and Cosine read feature1 alone; both metrics
#     now average per-feature relative distances over both.
#   - FIX: Spectrum analysis used a hardcoded 5000 Hz scale for
#     similarity/pruning; now sample_rate / 2.
#   - FIX: the time-stretch duration-tier point now sits at the
#     segment's own midpoint.
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

form Feature-Similarity Audio Variations v0.6
    optionmenu Preset: 1
        option Custom
        option Subtle Texture
        option Rhythmic Shuffle
        option Spectral Morph
        option Glitch Variations
        option Ambient Drift
    optionmenu Analysis_type: 1
        option Pitch
        option Spectrum
        option Intensity
    positive Window_size_s 0.1
    real Overlap 0.5
    positive Similarity_threshold 0.8
    optionmenu Distance_metric: 1
        option Euclidean
        option Mean relative difference
        option Mean magnitude-ratio difference
    real Min_separation_s -1
    optionmenu Variation_method: 1
        option Pitch shift
        option Time stretch
        option Amplitude modulation
        option Spectral lowpass
        option Reverse
        option Granular shuffle
    real Variation_amount 0.5
    positive Output_duration_s 10
    optionmenu Output_mode: 3
        option Random (incoherent scatter)
        option Chain (follow similarity links)
        option Hybrid (chain ~3, then jump)
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Min_separation_s: minimum distance in time between the two windows of
# a dictionary pair. -1 means "one window length", which admits only
# pairs that do not overlap at all. 0 restores the v0.5 behaviour, where
# adjacent windows sharing most of their samples counted as recurrences.

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

# ============================================================
# VALIDATION  (v0.6 fix 9)
# ============================================================
warnLines$ = ""

if overlap < 0
    overlap = 0
    warnLines$ = warnLines$ + "  ! Overlap < 0 -> 0" + newline$
endif
if overlap > 0.95
    overlap = 0.95
    warnLines$ = warnLines$ + "  ! Overlap >= 1 gives a zero or negative hop -> capped at 0.95" + newline$
endif
if similarity_threshold <= 0
    similarity_threshold = 0.01
    warnLines$ = warnLines$ + "  ! Similarity_threshold <= 0 -> 0.01" + newline$
endif
if similarity_threshold > 1
    similarity_threshold = 1
    warnLines$ = warnLines$ + "  ! Similarity_threshold > 1 -> 1" + newline$
endif
if variation_amount < 0
    variation_amount = 0
    warnLines$ = warnLines$ + "  ! Variation_amount < 0 (negative sd / gain) -> 0" + newline$
endif
if variation_amount > 1
    variation_amount = 1
    warnLines$ = warnLines$ + "  ! Variation_amount > 1 -> 1" + newline$
endif
if window_size_s < 0.01
    window_size_s = 0.01
    warnLines$ = warnLines$ + "  ! Window_size below 10 ms -> 10 ms" + newline$
endif
if output_duration_s <= 0
    output_duration_s = 1
    warnLines$ = warnLines$ + "  ! Output_duration_s <= 0 -> 1 s" + newline$
endif

# -1 means one window length: only non-overlapping windows may pair
if min_separation_s < 0
    min_separation_s = window_size_s
endif

# v0.6 fix 8: reproducibility. v0.5 had no seed at all, though window
# choice, chain steps, pitch shift, stretch, reverse and grain
# displacement are all random.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

# === Info ===
clearinfo
writeInfoLine: "=== Feature-Similarity Audio Variations v0.6 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(total_duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis: ", analysis_name$
appendInfoLine: "Window: ", window_size_s, " s | Overlap: ", overlap * 100, "%"
appendInfoLine: "Similarity threshold: ", similarity_threshold
appendInfoLine: "Variation: ", variation_name$, " (amount=", variation_amount, ")"
appendInfoLine: "Output mode: ", output_mode_name$
appendInfoLine: "Seed: ", seedLabel$
appendInfoLine: "Min pair separation: ", fixed$(min_separation_s * 1000, 1), " ms"
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
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

# v0.6 CRITICAL 1: TWO separate sets of arrays.
#   startByOrig#/endByOrig#  - indexed by ORIGINAL window number, and
#                              never touched by the sort. The renderer
#                              and the visualization use only these.
#   sortedF1#/sortedF2#/sortedOrig# - feature-sorted, used only by the
#                              sweep.
# v0.5 had one set, reloaded in sorted order after the sort, while the
# dictionary went on storing original indices - so the renderer looked
# up sorted row N for original window N. Measured at the defaults: all
# 119 windows moved under the sort and 63 of 63 rendered segments
# played the wrong window.
selectObject: features
startByOrig# = zero#(num_windows)
endByOrig# = zero#(num_windows)
featOrig1# = zero#(num_windows)
featOrig2# = zero#(num_windows)

for i to num_windows
    selectObject: features
    oi = Get value: i, "index"
    startByOrig#[oi] = Get value: i, "start"
    endByOrig#[oi] = Get value: i, "end"

    if analysis_type = 1
        featOrig1#[oi] = Get value: i, "mean_f0"
        featOrig2#[oi] = Get value: i, "stdev_f0"
    elsif analysis_type = 2
        featOrig1#[oi] = Get value: i, "spectral_cog"
        featOrig2#[oi] = Get value: i, "spectral_stdev"
    else
        featOrig1#[oi] = Get value: i, "mean_intensity"
        featOrig2#[oi] = Get value: i, "max_intensity"
    endif
endfor

# v0.6 fix 10: report what Pitch mode had to discard.
if analysis_type = 1
    nUnvoiced = 0
    for w to num_windows
        if featOrig1#[w] = undefined
            nUnvoiced += 1
        endif
    endfor
    if nUnvoiced > 0
        appendInfoLine: "  ", nUnvoiced, "/", num_windows,
            ... " windows have no defined F0 and cannot enter the dictionary"
    endif
    if nUnvoiced = num_windows
        appendInfoLine: "  ! No window is voiced: the similarity mechanism"
        appendInfoLine: "    cannot run and output falls back to sequential order."
        appendInfoLine: "    Try Spectrum or Intensity analysis for this material."
    endif
endif

# Legacy names kept for the visualization, which reads by original index
start_times# = startByOrig#
end_times# = endByOrig#
feature1# = featOrig1#
feature2# = featOrig2#

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

# Sorted views - these exist ONLY for the sweep
sortedOrig# = zero#(num_windows)
sortedF1# = zero#(num_windows)
sortedF2# = zero#(num_windows)
sortedStart# = zero#(num_windows)

for i to num_windows
    selectObject: features
    sortedOrig#[i] = Get value: i, "index"
    sortedStart#[i] = Get value: i, "start"

    if analysis_type = 1
        sortedF1#[i] = Get value: i, "mean_f0"
        sortedF2#[i] = Get value: i, "stdev_f0"
    elsif analysis_type = 2
        sortedF1#[i] = Get value: i, "spectral_cog"
        sortedF2#[i] = Get value: i, "spectral_stdev"
    else
        sortedF1#[i] = Get value: i, "mean_intensity"
        sortedF2#[i] = Get value: i, "max_intensity"
    endif
endfor

# === STEP 2: Build Dictionary  (arrays + Table for viz) ===
appendInfoLine: ""
appendInfoLine: "Building similarity dictionary..."

# Empty Table kept for visualization compatibility — populated at end
dictionary = Create Table with column names: "dictionary", 0, "window_id similar_to distance"

# v0.6 fix 5: the sweep runs TWICE - pass 1 counts, pass 2 fills arrays
# sized exactly. v0.5 allocated num_windows*(num_windows-1)/2 slots in
# each of three arrays before finding a single pair, so 10,000 windows
# would have demanded ~50 million slots per array up front. Measured at
# the defaults: 2778 pairs actually found against 7021 slots reserved.
num_pairs = 0
comparisons_made = 0
comparisons_skipped = 0
rejectedNear = 0

if analysis_type = 1
    max_acceptable_diff = 600 * (1 - similarity_threshold)
    max_dist_global = 600
elsif analysis_type = 2
    # v0.5: spectral CoG ranges to Nyquist, not 5000 Hz
    max_dist_global = sample_rate / 2
    max_acceptable_diff = max_dist_global * (1 - similarity_threshold)
else
    max_acceptable_diff = 100 * (1 - similarity_threshold)
    max_dist_global = 100
endif

# metrics 2/3 average per-feature relative distances, so the feature1
# term alone may reach twice the threshold while the average passes
if distance_metric <> 1
    max_acceptable_diff = max_acceptable_diff * 2
endif

stopwatch

for pass to 2
    if pass = 2
        # exact allocation, now that the count is known
        allocPairs = num_pairs
        if allocPairs < 1
            allocPairs = 1
        endif
        pairLeft# = zero# (allocPairs)
        pairRight# = zero# (allocPairs)
        pairDist# = zero# (allocPairs)
        num_pairs = 0
    endif

    for i to num_windows - 1
        f1_i = sortedF1#[i]
        f2_i = sortedF2#[i]
        idx_i = sortedOrig#[i]

        if f1_i <> undefined
            j = i + 1
            innerActive = 1
            while j <= num_windows and innerActive = 1
                f1_j = sortedF1#[j]
                f2_j = sortedF2#[j]

                if f1_j <> undefined
                    idx_j = sortedOrig#[j]

                    primary_diff = abs(f1_j - f1_i)

                    if primary_diff > max_acceptable_diff
                        if pass = 1
                            comparisons_skipped += (num_windows - j + 1)
                        endif
                        innerActive = 0
                    else
                        if pass = 1
                            comparisons_made += 1
                        endif

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
                            # v0.6 fix 4: mean RELATIVE difference. v0.5
                            # called this "Correlation"; it is not one -
                            # no covariance is computed anywhere, and the
                            # abs() discards sign, which matters for the
                            # negative values intensity analysis yields.
                            d1rel = abs(f1_i - f1_j) / max(abs(f1_i), abs(f1_j) + 0.0001)
                            if f2ok
                                d2rel = abs(f2_i - f2_j) / max(abs(f2_i), abs(f2_j) + 0.0001)
                                dist = 0.5 * (d1rel + d2rel)
                            else
                                dist = d1rel
                            endif
                            max_dist = 1
                        else
                            # v0.6 fix 4: mean MAGNITUDE-RATIO difference.
                            # v0.5 called this "Cosine"; for positive
                            # values it reduces to (max-min)/max, the same
                            # ordering as metric 2. A real cosine needs the
                            # features treated as one vector on comparable
                            # scales.
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
                            # v0.6 fix 6: windows that overlap in time are
                            # not recurrences. At 70% overlap two adjacent
                            # windows share 70% of their samples and match
                            # trivially - measured 19.8% of the Ambient
                            # Drift dictionary before this filter.
                            sepOK = 1
                            if min_separation_s > 0
                                if abs(idx_i - idx_j) * hop_size < min_separation_s
                                    sepOK = 0
                                endif
                            endif
                            if sepOK
                                num_pairs += 1
                                if pass = 2
                                    pairLeft#[num_pairs] = idx_i
                                    pairRight#[num_pairs] = idx_j
                                    pairDist#[num_pairs] = dist
                                endif
                            elsif pass = 1
                                rejectedNear += 1
                            endif
                        endif
                    endif
                endif
                j += 1
            endwhile
        endif
    endfor
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
if rejectedNear > 0
    appendInfoLine: "  (", rejectedNear,
        ... " above-threshold pairs rejected as overlapping in time)"
endif
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
# v0.6 fix 3: v0.5 assumed each segment stayed window_size_s long,
# which Time stretch (0.5x-2x) and Granular shuffle both break, so the
# output could stop short with no way to notice. The cap below is only
# an upper bound; the loop stops once the accumulated duration passes
# the target, and the result is trimmed - or padded - to land exactly.
num_output_windows = ceiling(output_duration_s / effAdvance) + 1
if num_output_windows < 1
    num_output_windows = 1
endif
maxOutputWindows = num_output_windows * 4 + 16
accumDur = 0
nSegs = 0

segment_ids# = zero#(maxOutputWindows)
used_windows# = zero#(maxOutputWindows)

# Chain-mode state
chainCurrent = 0
chainStepsRemaining = 0

for out_i to maxOutputWindows
  if accumDur < output_duration_s + xfadeSec
    if out_i mod 20 = 0
        appendInfoLine: "  ", floor(min(100, 100 * accumDur / output_duration_s)), "%"
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
    
    # v0.6 CRITICAL 1: indexed by ORIGINAL window number, in arrays the
    # sort never touched.
    start_time = startByOrig#[window_idx]
    end_time = endByOrig#[window_idx]
    
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
        # Granular shuffle
        # v0.6 fix 7a: amount = 0 is now genuinely identity. v0.5
        # documented it that way but still cut the segment into
        # Hann-windowed 20 ms grains and butt-joined them, so the
        # "identity" setting put an amplitude dip every 20 ms.
        if variation_amount <= 0.0001
            selectObject: segment
            varied_segment = Copy: "granular_identity"
        else
            grain_size = 0.02
            num_grains = floor(seg_dur / grain_size)
            # v0.6 fix 7c: keep the trailing partial grain. v0.5 dropped
            # everything past the last whole grain, so a 150 ms segment
            # came back 140 ms - one more reason the output ran short.
            remainder = seg_dur - num_grains * grain_size
            hasRemainder = 0
            if remainder > 0.0005
                hasRemainder = 1
                num_grains += 1
            endif
            if num_grains < 1
                num_grains = 1
            endif

            maxShift = round(num_grains * variation_amount)
            if maxShift < 1
                maxShift = 1
            endif

            grain_ids# = zero#(num_grains)

            for g to num_grains
                # v0.6 fix 7b: draw uniformly from the valid range around
                # this grain. v0.5 drew a displacement and then CLAMPED
                # it into [1, num_grains], which piles a large share of
                # high-amount draws onto the first and last grain - not a
                # shuffle but jittered resampling with edge build-up.
                lowIdx = g - maxShift
                if lowIdx < 1
                    lowIdx = 1
                endif
                highIdx = g + maxShift
                if highIdx > num_grains
                    highIdx = num_grains
                endif
                shuffled_idx = randomInteger(lowIdx, highIdx)

                shuffled_start = (shuffled_idx - 1) * grain_size
                shuffled_end = min(shuffled_start + grain_size, seg_dur)

                if shuffled_end - shuffled_start > 0.0005
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
            if num_grains >= 2
                varied_segment = Concatenate
            else
                varied_segment = Copy: "single_grain"
            endif

            for g to num_grains
                removeObject: grain_ids#[g]
            endfor
        endif
    endif
    
    # v0.6 CRITICAL 2: NO per-segment fades. v0.5 applied a 2 ms
    # raised-cosine fade to each end AND then joined with
    # Concatenate with overlap, which applies its own crossfade over
    # exactly those samples - two envelopes at every boundary. Praat's
    # crossfade handles the internal joins; the head and tail of the
    # finished output are faded once, after assembly.
    selectObject: varied_segment
    vsDur = Get total duration

    nSegs += 1
    segment_ids#[nSegs] = varied_segment
    used_windows#[nSegs] = window_idx
    accumDur += vsDur - xfadeSec

    if varied_segment <> segment
        removeObject: segment
    endif
  endif
endfor

num_output_windows = nSegs

# === Concatenate All Segments ===
appendInfoLine: ""
appendInfoLine: "Concatenating ", num_output_windows, " segments..."

selectObject: segment_ids#[1]
for i from 2 to num_output_windows
    plusObject: segment_ids#[i]
endfor

if num_output_windows >= 2
    output = Concatenate with overlap: xfadeSec
else
    output = Copy: "single"
endif
Rename: sound_name$ + "_LZ_" + presetName$

for i to num_output_windows
    removeObject: segment_ids#[i]
endfor

# v0.6 fix 3: land the requested duration exactly, in BOTH directions.
# v0.5 trimmed an overshoot but silently accepted an undershoot, which
# Time stretch and Granular shuffle could both produce.
selectObject: output
current_duration = Get total duration
if current_duration > output_duration_s
    selectObject: output
    trimmed = Extract part: 0, output_duration_s, "rectangular", 1, "no"
    removeObject: output
    output = trimmed
elsif current_duration < output_duration_s - 0.0005
    appendInfoLine: "  Material ran short (", fixed$(current_duration, 3),
        ... " s); padding to the requested ", fixed$(output_duration_s, 3), " s"
    Create Sound from formula: "lz_pad", 1, 0,
        ... output_duration_s - current_duration, sample_rate, "0"
    padSnd = selected("Sound")
    selectObject: output
    plusObject: padSnd
    joined = Concatenate
    removeObject: output, padSnd
    output = joined
endif
selectObject: output
Rename: sound_name$ + "_LZ_" + presetName$

# v0.6 CRITICAL 2 / fix 3: one fade at each end of the finished sound.
# The trim can land mid-segment at a non-zero amplitude.
selectObject: output
finalDurNow = Get total duration
edgeFade = 0.005
if edgeFade > finalDurNow * 0.1
    edgeFade = finalDurNow * 0.1
endif
if edgeFade > 0.0002
    efs$ = fixed$(edgeFade, 8)
    selectObject: output
    Formula: "if x - xmin < " + efs$ + " then self * ((x - xmin) / " + efs$ + ") else self fi"
    selectObject: output
    Formula: "if xmax - x < " + efs$ + " then self * ((xmax - x) / " + efs$ + ") else self fi"
endif

selectObject: output
Scale peak: 0.95
final_duration = Get total duration
final_peak = Get absolute extremum: 0, 0, "None"

# v0.6 fix 8: all random draws are done.
random_initializeSafelyAndUnpredictably ()

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
