# ============================================================
# Praat AudioTools - LZ-Inspired_Audio_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026) - real Lempel-Ziv parsing
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# WHAT THIS SCRIPT DOES
#   The source is quantized into a stream of symbols, that stream is
#   parsed by Lempel-Ziv into a dictionary of variable-length PHRASES,
#   and the output is generated from that dictionary. Every phrase is a
#   run of consecutive source windows, so a phrase renders as one
#   contiguous extract of audio.
#
# Changelog v0.8 (2026):
#
#   THE MODEL CHANGED. v0.7 and earlier did not encode anything with
#   Lempel-Ziv. They built an all-pairs feature-distance sweep and kept
#   the pairs under a threshold - an undirected similarity graph over
#   windows, with no symbols, no sequential parse, no phrases and no
#   dictionary in the LZ sense. Renaming it (v0.4, v0.7) described the
#   gap accurately but did not close it. v0.8 closes it.
#
#   1 - NEW: symbolization (the step that was missing). Lempel-Ziv
#     needs a STRING; continuous feature vectors are not one. Each
#     window's (feature1, feature2) pair is min-max normalized and
#     vector-quantized by k-means (k-means++ seeding, Lloyd iteration,
#     empty-cluster re-seeding) into Alphabet_size codewords. Clusters
#     are then renumbered by ascending feature1 centroid so symbol
#     order is interpretable. Windows with no defined feature - the
#     unvoiced ones Pitch analysis produces - get their own symbol
#     rather than being dropped, so the stream stays contiguous and
#     silence becomes part of the grammar instead of a hole in it.
#
#   2 - NEW: LZ78 incremental parse. The symbol stream is parsed left
#     to right against a trie: each new phrase is the longest phrase
#     already in the dictionary plus one new symbol. Stored per node:
#     parent, symbol, depth, traversal count and the window index of
#     its first occurrence. Node depth IS phrase length in windows, and
#     first-occurrence + depth maps every phrase back to a contiguous
#     stretch of source audio. This is the dictionary; it is directed,
#     sequential, and prefix-closed.
#
#   3 - NEW: real LZ measures reported. Phrase count c(n) is the
#     Lempel-Ziv complexity of the symbolized source; normalized
#     complexity c(n)*log_A(n)/n approaches 1 for a random stream and
#     falls toward 0 for a repetitive one. Symbol entropy and a
#     first-order coded-size estimate are reported alongside. These are
#     properties of the piece, not of the renderer.
#
#   4 - REPLACED: Random / Chain / Hybrid are gone. They were walks on
#     the old similarity graph and have no meaning here. Three
#     generation modes, all derived from the parse:
#       Parse and substitute - replay the source's own LZ token stream
#         and swap phrases for other dictionary entries of the SAME
#         DEPTH at rate Novelty. At Novelty 0 this is a straight decode
#         of the encoding, so it doubles as a correctness test: the
#         output should be the source, window for window.
#       Incremental parsing - variable-order Markov continuation over
#         the LZ78 trie, sampling children by traversal count and
#         escaping to the root at rate Novelty. This is the
#         Dubnov / Assayag incremental-parsing method used for machine
#         improvisation; it is LZ78 read as a predictor.
#       LZ77 copy and deviate - the classic sliding-window form. Find
#         the longest match of the recent OUTPUT inside the source
#         symbol stream, copy forward from there for up to
#         Max_copy_windows windows, then emit one literal that breaks
#         the match. Tokens are (offset, length, literal) triples.
#         Ties in match length are broken at random, which is what
#         makes it recombine rather than replay.
#
#   5 - AUDIBLE: segments are contiguous again. A phrase of depth d
#     covers d consecutive windows and is extracted in ONE call, so
#     there are no internal joins inside a phrase. v0.7 crossfaded
#     every window boundary; v0.8 crossfades only at phrase
#     boundaries, and those fall where the parse says the material
#     actually changes. Measured on a 6 s test source at the stock
#     settings: 119 segments for 200 windows of output.
#
#   11 - THE CROSSFADE IS NOW THE ANALYSIS OVERLAP, not a fixed 2 ms.
#     Found by testing, and it was a real error, not a refinement.
#     Phrases tile the WINDOW-INDEX stream with a stride of one hop,
#     but a phrase of L windows spans window_size + (L-1)*hop of
#     AUDIO. Butt-joining those with a 2 ms crossfade advances the
#     output by roughly one hop too much per phrase. Overlapping the
#     joins by overlap*window_size makes the two agree exactly:
#       runDur - xfade = w + (L-1)w(1-ov) - w*ov = L*w(1-ov) = L*hop
#     i.e. ordinary overlap-add. Verified on 6.4.06 that Praat's
#     Concatenate with overlap is amplitude-complementary, so a
#     20-segment chain at 70% overlap reconstructs its source to 2e-13
#     - a large crossfade is safe and correct here. Time stretch can
#     still shorten a segment below the crossfade; that case is capped
#     and reported rather than aborting.
#
#   12 - FIX: windows are quantized to WHOLE SAMPLES. A 0.025 s hop at
#     44100 is 1102.5 samples, so alternate window boundaries land on
#     opposite sub-sample phases and Extract part rounds. Measured 4
#     samples of accumulated drift over 6 s - every window still
#     correlating 1.0000 at its own lag, but the whole file sliding.
#     Integer-sample boundaries fall midway between sample centres,
#     where Extract part is exact. The adjustment is reported when it
#     changes the requested values.
#
#   13 - The incremental-parsing walk uses BACKOFF, not a carried node
#     pointer. A raw LZ78 trie is mostly leaves, so a walk that simply
#     advances hits a dead end almost every step and falls to the
#     root: measured 146 root-falls in 193 tokens at Novelty 0.35,
#     which is first-order behaviour wearing a variable-order name.
#     v0.8 re-descends from the root along the last k output symbols
#     and drops the oldest symbol until it finds a node with
#     continuations. Escapes then match Novelty (122/324 = 0.38 at
#     0.35) and the mean order actually used is reported, so the claim
#     "variable order" is checkable rather than asserted.
#
#   VERIFICATION. Preset "Faithful Re-decode" sets Novelty 0 and
#   variation None, which replays the parse in order and should return
#   the source. Measured on a 6 s test file, Praat 6.4.06 headless:
#   r = 0.9952 against the source excluding the 5 ms edge fades, zero
#   global lag, and exactly one 50 ms window anywhere in the file
#   deviating by more than 0.05 - the faded head. Before fixes 11 and
#   12 the same test gave r = 0.04. If a future change breaks the
#   encoding, this preset is where it will show.
#
#   6 - REMOVED: Similarity_threshold, Distance_metric, Min_separation_s.
#     All three were properties of the pairwise sweep. The separation
#     rule in particular is no longer needed: overlapping windows now
#     yield repeated symbols, which the parse absorbs by EXTENDING a
#     phrase. Redundancy that used to corrupt the dictionary now
#     shortens the encoding, which is the correct behaviour.
#
#   7 - REMOVED: the feature Table sort. The sort existed only to prune
#     the O(n^2) sweep, and it was the direct cause of the v0.6
#     CRITICAL 1 index-aliasing bug (sorted rows indexed by original
#     window number). With no sweep there is no sort and no second set
#     of arrays to keep in step. One indexing scheme, original window
#     order, everywhere.
#
#   8 - FIX: stereo input. To Manipulation, To Spectrum and mono
#     Concatenate all fail on a multi-channel Sound, so v0.7 crashed on
#     any stereo source depending on the variation method. The input is
#     converted to mono up front and the conversion is reported.
#
#   9 - FIX: PSOLA guard. To Manipulation refuses a Sound shorter than
#     3 / pitch-floor = 40 ms at floor 75. Pitch shift and Time stretch
#     on a 50 ms window (the Glitch preset's setting) therefore aborted
#     the script. Short segments now pass through unvaried and the
#     count of skipped segments is reported.
#
#   10 - NEW: variation method "None", for hearing the parse itself.
#
#   Kept from v0.6 / v0.7: the exact-duration trim-or-pad, the single
#   pair of edge fades on the finished output (no double envelope), the
#   granular-shuffle fixes, seeding, input validation, and the 8-inch
#   page convention.
#
# Changelog v0.7 (2026):
#   - Visualization standardization only.
# Changelog v0.6 (2026):
#   - CRITICAL: chosen window and rendered audio were different windows
#     (sorted/original index aliasing). CRITICAL: double envelope at
#     every join. Plus exact output duration, honest metric names,
#     O(n) pair allocation, temporal-separation rule, granular-shuffle
#     fixes, seeding and input validation.
# Changelog v0.5 / v0.4 / v0.3:
#   - Click removal at joins, spectral-lowpass direction and trimming,
#     granular amount actually used, array-based dictionary, output
#     modes, formula-expansion and PitchTier fixes.
# ============================================================

# === Check Input ===
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original_input = selected ("Sound")
sound_name$ = selected$ ("Sound")

form Lempel-Ziv Audio Variations v0.8
    optionmenu Preset: 1
        option Custom
        option Subtle Texture
        option Rhythmic Shuffle
        option Spectral Morph
        option Glitch Variations
        option Ambient Drift
        option Faithful Re-decode (test)
    optionmenu Analysis_type: 1
        option Pitch
        option Spectrum
        option Intensity
    positive Window_size_s 0.1
    real Overlap 0.5
    integer Alphabet_size 12
    optionmenu Generation_mode: 2
        option Parse and substitute (LZ78 re-decode)
        option Incremental parsing (LZ78 continuation)
        option LZ77 copy and deviate
    real Novelty 0.35
    integer Max_copy_windows 8
    optionmenu Variation_method: 1
        option Pitch shift
        option Time stretch
        option Amplitude modulation
        option Spectral lowpass
        option Reverse
        option Granular shuffle
        option None
    real Variation_amount 0.5
    positive Output_duration_s 10
    integer Random_seed 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Novelty is the single "how far from the source" control:
#   mode 1 - probability that a phrase is replaced by another
#            dictionary phrase of the same length
#   mode 2 - probability of escaping to the root of the trie, i.e.
#            abandoning the current context and starting a new phrase
#   mode 3 - probability of emitting a literal that breaks the copy
# Novelty 0 in mode 1 decodes the source; use it to verify the encoding.

# === Apply Presets ===
if preset = 2
    # Subtle Texture
    analysis_type = 1
    window_size_s = 0.15
    overlap = 0.6
    alphabet_size = 10
    generation_mode = 2
    novelty = 0.25
    max_copy_windows = 8
    variation_method = 1
    variation_amount = 0.3
    presetName$ = "SubtleTexture"
elsif preset = 3
    # Rhythmic Shuffle
    analysis_type = 3
    window_size_s = 0.08
    overlap = 0.4
    alphabet_size = 8
    generation_mode = 3
    novelty = 0.45
    max_copy_windows = 6
    variation_method = 6
    variation_amount = 0.6
    presetName$ = "RhythmicShuffle"
elsif preset = 4
    # Spectral Morph
    analysis_type = 2
    window_size_s = 0.12
    overlap = 0.5
    alphabet_size = 14
    generation_mode = 1
    novelty = 0.5
    max_copy_windows = 8
    variation_method = 4
    variation_amount = 0.5
    presetName$ = "SpectralMorph"
elsif preset = 5
    # Glitch Variations
    analysis_type = 2
    window_size_s = 0.05
    overlap = 0.3
    alphabet_size = 16
    generation_mode = 3
    novelty = 0.8
    max_copy_windows = 4
    variation_method = 5
    variation_amount = 0.8
    presetName$ = "Glitch"
elsif preset = 6
    # Ambient Drift
    analysis_type = 1
    window_size_s = 0.2
    overlap = 0.7
    alphabet_size = 8
    generation_mode = 2
    novelty = 0.15
    max_copy_windows = 12
    variation_method = 2
    variation_amount = 0.4
    presetName$ = "AmbientDrift"
elsif preset = 7
    # Faithful Re-decode - decodes the LZ encoding with no substitution
    # and no variation. The output should be the source. This preset
    # exists to make the encoding falsifiable by ear.
    analysis_type = 2
    window_size_s = 0.05
    overlap = 0.5
    alphabet_size = 20
    generation_mode = 1
    novelty = 0
    max_copy_windows = 8
    variation_method = 7
    variation_amount = 0
    presetName$ = "Redecode"
else
    presetName$ = "Custom"
endif

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
elsif variation_method = 6
    variation_name$ = "Granular"
else
    variation_name$ = "None"
endif

if generation_mode = 1
    mode_name$ = "Parse+substitute"
    mode_long$ = "LZ78 parse, phrase substitution"
elsif generation_mode = 2
    mode_name$ = "Incremental parsing"
    mode_long$ = "LZ78 trie continuation, variable order"
else
    mode_name$ = "LZ77 copy+deviate"
    mode_long$ = "LZ77 sliding window, offset/length/literal"
endif

# ============================================================
# VALIDATION
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
if novelty < 0
    novelty = 0
    warnLines$ = warnLines$ + "  ! Novelty < 0 -> 0" + newline$
endif
if novelty > 1
    novelty = 1
    warnLines$ = warnLines$ + "  ! Novelty > 1 -> 1" + newline$
endif
if variation_amount < 0
    variation_amount = 0
    warnLines$ = warnLines$ + "  ! Variation_amount < 0 -> 0" + newline$
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
if alphabet_size < 2
    alphabet_size = 2
    warnLines$ = warnLines$ + "  ! Alphabet_size < 2 -> 2" + newline$
endif
if alphabet_size > 64
    alphabet_size = 64
    warnLines$ = warnLines$ + "  ! Alphabet_size > 64 -> 64 (LZ needs recurrence; a large alphabet prevents it)" + newline$
endif
if max_copy_windows < 1
    max_copy_windows = 1
    warnLines$ = warnLines$ + "  ! Max_copy_windows < 1 -> 1" + newline$
endif

# v0.6 fix 8: reproducibility.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$ (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

# ============================================================
# v0.8 fix 8: mono. To Manipulation / To Spectrum / Concatenate all
# fail on a multi-channel Sound.
# ============================================================
selectObject: original_input
nInputCh = Get number of channels
madeMono = 0
if nInputCh > 1
    original_sound = Convert to mono
    Rename: sound_name$ + "_mono"
    madeMono = 1
else
    original_sound = original_input
endif

selectObject: original_sound
sample_rate = Get sampling frequency
total_duration = Get total duration

# === Info ===
clearinfo
writeInfoLine: "=== Lempel-Ziv Audio Variations v0.8 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$ (total_duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Analysis: ", analysis_name$
appendInfoLine: "Window: ", window_size_s, " s | Overlap: ", overlap * 100, "%"
appendInfoLine: "Alphabet: ", alphabet_size, " codewords requested"
appendInfoLine: "Generation: ", mode_name$, " (", mode_long$, ")"
appendInfoLine: "Novelty: ", novelty
appendInfoLine: "Variation: ", variation_name$, " (amount=", variation_amount, ")"
appendInfoLine: "Seed: ", seedLabel$
if madeMono
    appendInfoLine: ""
    appendInfoLine: "  Input had ", nInputCh, " channels; converted to mono for analysis and rendering."
endif
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
appendInfoLine: ""

# === Calculate Windows ===
# v0.8: quantize the window and hop to WHOLE SAMPLES. With a
# fractional hop (0.025 s at 44100 = 1102.5 samples) every second
# window boundary lands on the opposite sub-sample phase, Extract part
# rounds, and the error accumulates - measured 4 samples of drift over
# 6 s before this change, with every window still correlating 1.0000 at
# its own lag. Integer-sample boundaries fall midway between sample
# centres, where Extract part is exact, so the tiling is exact too.
win_samples = round (window_size_s * sample_rate)
if win_samples < 4
    win_samples = 4
endif
hop_samples = round (window_size_s * (1 - overlap) * sample_rate)
if hop_samples < 1
    hop_samples = 1
endif
if hop_samples > win_samples
    hop_samples = win_samples
endif
quantWarn$ = ""
if abs (win_samples / sample_rate - window_size_s) > 1e-9
    quantWarn$ = "  Window quantized to " + fixed$ (1000 * win_samples / sample_rate, 4) + " ms (" + string$ (win_samples) + " samples)"
endif
window_size_s = win_samples / sample_rate
hop_size = hop_samples / sample_rate
overlap = 1 - hop_samples / win_samples

num_windows = floor ((total_duration - window_size_s) / hop_size) + 1

if num_windows < 4
    exitScript: "Source too short for the chosen window/overlap settings (need at least 4 windows to parse)."
endif

appendInfoLine: "Windows: ", num_windows
if quantWarn$ <> ""
    appendInfoLine: quantWarn$, ", hop ", hop_samples,
        ... " samples, effective overlap ", fixed$ (overlap, 4)
endif

# ============================================================
# STEP 1: Extract features  (unchanged from v0.7)
# ============================================================
appendInfoLine: ""
appendInfoLine: "Extracting features..."

startByOrig# = zero# (num_windows)
endByOrig# = zero# (num_windows)
featOrig1# = zero# (num_windows)
featOrig2# = zero# (num_windows)

for i to num_windows
    startByOrig# [i] = (i - 1) * hop_size
    endByOrig# [i] = (i - 1) * hop_size + window_size_s
endfor

selectObject: original_sound

if analysis_type = 1
    pitch = To Pitch: 0, 75, 600
    for i to num_windows
        selectObject: pitch
        featOrig1# [i] = Get mean: startByOrig# [i], endByOrig# [i], "Hertz"
        featOrig2# [i] = Get standard deviation: startByOrig# [i], endByOrig# [i], "Hertz"
    endfor
elsif analysis_type = 2
    for i to num_windows
        selectObject: original_sound
        segment = Extract part: startByOrig# [i], endByOrig# [i], "rectangular", 1, "no"
        spectrum = To Spectrum: "yes"
        featOrig1# [i] = Get centre of gravity: 2
        featOrig2# [i] = Get standard deviation: 2
        removeObject: segment, spectrum
    endfor
else
    intensity = To Intensity: 100, 0, "yes"
    for i to num_windows
        selectObject: intensity
        featOrig1# [i] = Get mean: startByOrig# [i], endByOrig# [i], "energy"
        featOrig2# [i] = Get maximum: startByOrig# [i], endByOrig# [i], "Parabolic"
    endfor
endif

# v0.8 fix 7: no Table, no sort, one indexing scheme. The v0.6 CRITICAL 1
# aliasing bug was only possible because two differently-ordered views of
# the same windows existed at once. There is now one.
feature1# = featOrig1#
feature2# = featOrig2#

nUndefWin = 0
for w to num_windows
    if featOrig1# [w] = undefined
        nUndefWin = nUndefWin + 1
    endif
endfor
if nUndefWin > 0
    appendInfoLine: "  ", nUndefWin, "/", num_windows,
        ... " windows have no defined ", analysis_name$, " value -> assigned their own symbol"
endif
if nUndefWin >= num_windows - 2
    exitScript: "Almost no window has a defined " + analysis_name$ + " value. Try Spectrum or Intensity analysis for this material."
endif

# ============================================================
# STEP 2 (NEW): Symbolize - vector-quantize the windows
# This is the step that turns the signal into a STRING. Without it
# there is nothing for Lempel-Ziv to parse.
# ============================================================
appendInfoLine: ""
appendInfoLine: "Quantizing windows into a symbol alphabet..."

stopwatch

isValid# = zero# (num_windows)
validCount = 0
for w to num_windows
    if featOrig1# [w] <> undefined
        isValid# [w] = 1
        validCount = validCount + 1
    endif
endfor

# min-max normalization over defined values only
minA = undefined
maxA = undefined
minB = undefined
maxB = undefined
for w to num_windows
    if isValid# [w] = 1
        v = featOrig1# [w]
        if minA = undefined
            minA = v
            maxA = v
        else
            if v < minA
                minA = v
            endif
            if v > maxA
                maxA = v
            endif
        endif
        u = featOrig2# [w]
        if u <> undefined
            if minB = undefined
                minB = u
                maxB = u
            else
                if u < minB
                    minB = u
                endif
                if u > maxB
                    maxB = u
                endif
            endif
        endif
    endif
endfor
if maxA - minA < 1e-12
    maxA = minA + 1
endif
if minB = undefined
    minB = 0
    maxB = 1
endif
if maxB - minB < 1e-12
    maxB = minB + 1
endif

vIdx# = zero# (validCount)
vx# = zero# (validCount)
vy# = zero# (validCount)
vn = 0
for w to num_windows
    if isValid# [w] = 1
        vn = vn + 1
        vIdx# [vn] = w
        vx# [vn] = (featOrig1# [w] - minA) / (maxA - minA)
        if featOrig2# [w] = undefined
            vy# [vn] = 0.5
        else
            vy# [vn] = (featOrig2# [w] - minB) / (maxB - minB)
        endif
    endif
endfor

kClusters = alphabet_size
if kClusters > validCount
    kClusters = validCount
endif
if kClusters < 2
    kClusters = 2
endif

# --- k-means++ seeding ---
cx# = zero# (kClusters)
cy# = zero# (kClusters)
d2# = zero# (validCount)

firstPick = randomInteger (1, validCount)
cx# [1] = vx# [firstPick]
cy# [1] = vy# [firstPick]
for i to validCount
    d2# [i] = (vx# [i] - cx# [1]) ^ 2 + (vy# [i] - cy# [1]) ^ 2
endfor

for c from 2 to kClusters
    totD = 0
    for i to validCount
        totD = totD + d2# [i]
    endfor
    if totD <= 0
        pick = randomInteger (1, validCount)
    else
        target = randomUniform (0, totD)
        acc = 0
        pick = validCount
        found = 0
        for i to validCount
            if found = 0
                acc = acc + d2# [i]
                if acc >= target
                    pick = i
                    found = 1
                endif
            endif
        endfor
    endif
    cx# [c] = vx# [pick]
    cy# [c] = vy# [pick]
    for i to validCount
        dd = (vx# [i] - cx# [c]) ^ 2 + (vy# [i] - cy# [c]) ^ 2
        if dd < d2# [i]
            d2# [i] = dd
        endif
    endfor
endfor

# --- Lloyd iteration ---
assign# = zero# (validCount)
kmIters = 0
kmChanged = 1
while kmChanged = 1 and kmIters < 40
    kmChanged = 0
    kmIters = kmIters + 1

    for i to validCount
        bestC = 1
        bestD = (vx# [i] - cx# [1]) ^ 2 + (vy# [i] - cy# [1]) ^ 2
        for c from 2 to kClusters
            dd = (vx# [i] - cx# [c]) ^ 2 + (vy# [i] - cy# [c]) ^ 2
            if dd < bestD
                bestD = dd
                bestC = c
            endif
        endfor
        if assign# [i] <> bestC
            assign# [i] = bestC
            kmChanged = 1
        endif
    endfor

    sumX# = zero# (kClusters)
    sumY# = zero# (kClusters)
    cnt# = zero# (kClusters)
    for i to validCount
        a = assign# [i]
        sumX# [a] = sumX# [a] + vx# [i]
        sumY# [a] = sumY# [a] + vy# [i]
        cnt# [a] = cnt# [a] + 1
    endfor
    for c to kClusters
        if cnt# [c] > 0
            cx# [c] = sumX# [c] / cnt# [c]
            cy# [c] = sumY# [c] / cnt# [c]
        else
            # empty cluster: re-seed at the point worst served by its own centre
            farI = 1
            farD = -1
            for i to validCount
                a = assign# [i]
                dd = (vx# [i] - cx# [a]) ^ 2 + (vy# [i] - cy# [a]) ^ 2
                if dd > farD
                    farD = dd
                    farI = i
                endif
            endfor
            cx# [c] = vx# [farI]
            cy# [c] = vy# [farI]
            kmChanged = 1
        endif
    endfor
endwhile

# --- renumber clusters by ascending feature1 centroid ---
rankOf# = zero# (kClusters)
taken# = zero# (kClusters)
for r to kClusters
    bestC = 0
    bestV = 0
    for c to kClusters
        if taken# [c] = 0
            if bestC = 0 or cx# [c] < bestV
                bestC = c
                bestV = cx# [c]
            endif
        endif
    endfor
    taken# [bestC] = 1
    rankOf# [bestC] = r
endfor
ordCx# = zero# (kClusters)
ordCy# = zero# (kClusters)
for c to kClusters
    ordCx# [rankOf# [c]] = cx# [c]
    ordCy# [rankOf# [c]] = cy# [c]
endfor

symbol# = zero# (num_windows)
for i to validCount
    symbol# [vIdx# [i]] = rankOf# [assign# [i]]
endfor

if nUndefWin > 0
    alphabet = kClusters + 1
    undefSymbol = alphabet
    for w to num_windows
        if isValid# [w] = 0
            symbol# [w] = undefSymbol
        endif
    endfor
else
    alphabet = kClusters
    undefSymbol = 0
endif

# --- symbol statistics + occurrence lists ---
symCount# = zero# (alphabet)
for w to num_windows
    s = symbol# [w]
    symCount# [s] = symCount# [s] + 1
endfor

symEntropy = 0
symUsed = 0
for s to alphabet
    if symCount# [s] > 0
        symUsed = symUsed + 1
        p = symCount# [s] / num_windows
        symEntropy = symEntropy - p * log2 (p)
    endif
endfor

symStart# = zero# (alphabet)
accS = 0
for s to alphabet
    symStart# [s] = accS
    accS = accS + symCount# [s]
endfor
symWin# = zero# (num_windows)
symFill# = zero# (alphabet)
for w to num_windows
    s = symbol# [w]
    symFill# [s] = symFill# [s] + 1
    symWin# [symStart# [s] + symFill# [s]] = w
endfor

vqTime = stopwatch
extraSym = 0
if nUndefWin > 0
    extraSym = 1
endif
if extraSym = 1
    appendInfoLine: "  ", kClusters, " codewords + 1 undefined symbol -> alphabet ", alphabet
else
    appendInfoLine: "  ", kClusters, " codewords -> alphabet ", alphabet
endif
appendInfoLine: "  k-means converged in ", kmIters, " iterations (", fixed$ (vqTime, 3), " s)"
appendInfoLine: "  Symbols actually used: ", symUsed, "/", alphabet,
    ... " | entropy ", fixed$ (symEntropy, 3), " bits (max ", fixed$ (log2 (alphabet), 3), ")"

# ============================================================
# STEP 3 (NEW): LZ78 incremental parse
#
# Walk the symbol stream left to right. At each step follow the trie as
# far as it goes, then add ONE new node for the symbol that broke the
# match. That node is a new dictionary phrase. Node depth = phrase
# length in windows; nodeFirstWin = where the phrase first occurred, so
# (firstWin, depth) is a contiguous stretch of source audio.
# ============================================================
appendInfoLine: ""
appendInfoLine: "Parsing the symbol stream with LZ78..."

stopwatch

maxNodes = num_windows + 2
nodeParent# = zero# (maxNodes)
nodeSymbol# = zero# (maxNodes)
nodeDepth# = zero# (maxNodes)
nodeCount# = zero# (maxNodes)
nodeFirstWin# = zero# (maxNodes)
childOf# = zero# (maxNodes * alphabet)

nNodes = 1
nodeParent# [1] = 0
nodeSymbol# [1] = 0
nodeDepth# [1] = 0
nodeCount# [1] = 0
nodeFirstWin# [1] = 1

maxPhrases = num_windows + 1
phraseNode# = zero# (maxPhrases)
phraseStart# = zero# (maxPhrases)
phraseLen# = zero# (maxPhrases)
nPhrases = 0

t = 1
while t <= num_windows
    curNode = 1
    startT = t
    scanning = 1
    while scanning = 1
        if t > num_windows
            scanning = 0
        else
            ch = childOf# [(curNode - 1) * alphabet + symbol# [t]]
            if ch > 0
                curNode = ch
                nodeCount# [curNode] = nodeCount# [curNode] + 1
                t = t + 1
            else
                scanning = 0
            endif
        endif
    endwhile

    if t <= num_windows
        nNodes = nNodes + 1
        newNode = nNodes
        childOf# [(curNode - 1) * alphabet + symbol# [t]] = newNode
        nodeParent# [newNode] = curNode
        nodeSymbol# [newNode] = symbol# [t]
        nodeDepth# [newNode] = nodeDepth# [curNode] + 1
        nodeCount# [newNode] = 1
        nodeFirstWin# [newNode] = startT
        nPhrases = nPhrases + 1
        phraseNode# [nPhrases] = newNode
        phraseStart# [nPhrases] = startT
        phraseLen# [nPhrases] = nodeDepth# [newNode]
        t = t + 1
    else
        # stream ended inside an existing phrase: emit that node
        if curNode > 1
            nPhrases = nPhrases + 1
            phraseNode# [nPhrases] = curNode
            phraseStart# [nPhrases] = startT
            phraseLen# [nPhrases] = num_windows - startT + 1
        endif
    endif
endwhile

parseTime = stopwatch

# --- LZ measures ---
lzComplexity = nPhrases
lzNorm = undefined
if alphabet > 1 and num_windows > 1
    lzNorm = lzComplexity * (ln (num_windows) / ln (alphabet)) / num_windows
endif
maxPhraseLen = 0
sumPhraseLen = 0
for p to nPhrases
    if phraseLen# [p] > maxPhraseLen
        maxPhraseLen = phraseLen# [p]
    endif
    sumPhraseLen = sumPhraseLen + phraseLen# [p]
endfor
meanPhraseLen = 0
if nPhrases > 0
    meanPhraseLen = sumPhraseLen / nPhrases
endif

bitsRaw = num_windows * log2 (alphabet)
bitsLZ = nPhrases * (log2 (max (2, nPhrases)) + log2 (alphabet))
codeRatio = undefined
if bitsLZ > 0
    codeRatio = bitsRaw / bitsLZ
endif

appendInfoLine: "  ", nPhrases, " phrases parsed in ", fixed$ (parseTime, 3), " s"
appendInfoLine: "  Phrase length: mean ", fixed$ (meanPhraseLen, 2),
    ... " windows, longest ", maxPhraseLen
appendInfoLine: "  Trie nodes: ", nNodes
appendInfoLine: "  Lempel-Ziv complexity c(n) = ", lzComplexity
if lzNorm <> undefined
    appendInfoLine: "  Normalized complexity c(n)*log_A(n)/n = ", fixed$ (lzNorm, 4),
        ... "  (-> 1 random, -> 0 repetitive)"
endif
if codeRatio <> undefined
    appendInfoLine: "  Coded-size estimate: ", fixed$ (bitsLZ, 0), " vs ", fixed$ (bitsRaw, 0),
        ... " bits (", fixed$ (codeRatio, 2), "x)"
endif

# --- depth lists, for same-length phrase substitution in mode 1 ---
maxDepth = 1
for n from 2 to nNodes
    if nodeDepth# [n] > maxDepth
        maxDepth = nodeDepth# [n]
    endif
endfor
depthCount# = zero# (maxDepth)
for n from 2 to nNodes
    d = nodeDepth# [n]
    depthCount# [d] = depthCount# [d] + 1
endfor
depthStart# = zero# (maxDepth)
accD = 0
for d to maxDepth
    depthStart# [d] = accD
    accD = accD + depthCount# [d]
endfor
if accD < 1
    accD = 1
endif
depthNodes# = zero# (accD)
depthFill# = zero# (maxDepth)
for n from 2 to nNodes
    d = nodeDepth# [n]
    depthFill# [d] = depthFill# [d] + 1
    depthNodes# [depthStart# [d] + depthFill# [d]] = n
endfor

# ============================================================
# STEP 4 (NEW): Generate a token stream from the parse
#
# Every mode emits RUNS: (source window, length in windows). A run is a
# contiguous stretch of the source, so it is extracted in one call and
# has no internal splices. Only run boundaries are crossfaded.
# ============================================================
appendInfoLine: ""
appendInfoLine: "Generating from the dictionary (", mode_name$, ")..."

# v0.8: the crossfade is the ANALYSIS OVERLAP, not an arbitrary 2 ms.
# Phrases tile the window-index stream with a stride of one hop, so a
# phrase of L windows must ADVANCE the output by L*hop - but it spans
# window_size + (L-1)*hop of audio. Overlapping the joins by
# overlap*window_size makes the two agree exactly:
#   runDur - xfade = w + (L-1)*w*(1-ov) - w*ov = L*w*(1-ov) = L*hop
# which is ordinary overlap-add, and is what makes a novelty-0 decode
# reconstruct the source instead of drifting one hop per phrase.
xfadeSec = overlap * window_size_s
if xfadeSec < 0.002
    xfadeSec = 0.002
endif
effAdvance = hop_size
if effAdvance < 0.002
    effAdvance = 0.002
endif

maxRuns = ceiling (output_duration_s / effAdvance) * 2 + 32
if maxRuns > 20000
    maxRuns = 20000
endif
maxHist = maxRuns * max_copy_windows + 8
if maxHist > 200000
    maxHist = 200000
endif
ctxMax = 8

runSrc# = zero# (maxRuns)
runLen# = zero# (maxRuns)
runKind# = zero# (maxRuns)
runInfo# = zero# (maxRuns)
outSym# = zero# (maxHist)

nRuns = 0
estDur = 0
histLen = 0
lastWin = 0
parsePos = 0
ipNode = 1
nSubst = 0
nEscape = 0
nLiteral = 0
sumOrder = 0
nOrder = 0
# estDur now tracks the EXACT advance (len * hop), so the only reason
# to over-generate is a variation that shortens segments. Time stretch
# can reach 0.5x; nothing else changes duration. Over-generating 2.5x
# for every method cost 10.7 s of LZ77 search on a 2987-window source
# and threw 60% of it away.
if variation_method = 2
    genMargin = 2.3
else
    genMargin = 1.12
endif
targetEst = output_duration_s * genMargin + window_size_s

procedure emitRun: .src, .len, .kind, .info
    if .src < 1
        .src = 1
    endif
    if .src > num_windows
        .src = num_windows
    endif
    if .src + .len - 1 > num_windows
        .len = num_windows - .src + 1
    endif
    if .len < 1
        .len = 1
    endif
    nRuns = nRuns + 1
    runSrc# [nRuns] = .src
    runLen# [nRuns] = .len
    runKind# [nRuns] = .kind
    runInfo# [nRuns] = .info
    estDur = estDur + .len * hop_size
    for .k to .len
        if histLen < maxHist
            histLen = histLen + 1
            outSym# [histLen] = symbol# [.src + .k - 1]
        endif
    endfor
    lastWin = .src + .len - 1
endproc

stopwatch

genActive = 1
while genActive = 1
    if nRuns >= maxRuns - 2 or estDur >= targetEst
        genActive = 0
    else

        # ------------------------------------------------------------
        if generation_mode = 1
            # PARSE AND SUBSTITUTE
            # Replay the source's own LZ token stream. With probability
            # Novelty, swap the phrase for another dictionary entry of
            # the SAME DEPTH - same number of windows, different audio.
            parsePos = parsePos + 1
            if parsePos > nPhrases
                parsePos = 1
            endif
            baseNode = phraseNode# [parsePos]
            srcW = phraseStart# [parsePos]
            lenW = phraseLen# [parsePos]
            kind = 0
            info = baseNode

            dd = nodeDepth# [baseNode]
            if dd < 1
                dd = 1
            endif
            if novelty > 0 and dd <= maxDepth
                if randomUniform (0, 1) < novelty and depthCount# [dd] > 1
                    tries = 0
                    okPick = 0
                    while okPick = 0 and tries < 12
                        cand = depthNodes# [depthStart# [dd] + randomInteger (1, depthCount# [dd])]
                        if cand <> baseNode and cand > 1
                            srcW = nodeFirstWin# [cand]
                            lenW = nodeDepth# [cand]
                            kind = 1
                            info = cand
                            okPick = 1
                            nSubst = nSubst + 1
                        endif
                        tries = tries + 1
                    endwhile
                endif
            endif
            @emitRun: srcW, lenW, kind, info

        # ------------------------------------------------------------
        elsif generation_mode = 2
            # INCREMENTAL PARSING (LZ78 read as a variable-order model)
            # Sample a child of the current trie node in proportion to
            # how often the parse traversed it; escape to the root at
            # rate Novelty, or whenever the context runs out of
            # continuations. Consecutive symbols that happen to be
            # consecutive in the source are merged into one run, so
            # long verbatim copies emerge from the walk rather than
            # being imposed on it.
            # Context selection by BACKOFF, not by carrying a node
            # pointer. A raw LZ78 trie is mostly leaves, so a walk that
            # simply advances hits a dead end almost every step and
            # falls back to the root - which collapses the model to
            # first order and makes Novelty meaningless. Instead:
            # re-descend from the root along the last ctxDepth output
            # symbols, and if that node has no continuations, drop the
            # oldest symbol and try again. The order actually used is
            # whatever the dictionary can support at this point, which
            # is what "variable order" means.
            escaped = 0
            ctxDepth = ctxMax
            if ctxDepth > histLen
                ctxDepth = histLen
            endif
            if novelty > 0
                if randomUniform (0, 1) < novelty
                    ctxDepth = 0
                    escaped = 1
                endif
            endif

            ipNode = 1
            totW = 0
            searching = 1
            while searching = 1
                nTry = 1
                okDesc = 1
                for k to ctxDepth
                    if okDesc = 1
                        ch = childOf# [(nTry - 1) * alphabet + outSym# [histLen - ctxDepth + k]]
                        if ch > 0
                            nTry = ch
                        else
                            okDesc = 0
                        endif
                    endif
                endfor
                if okDesc = 1
                    totW = 0
                    for sy to alphabet
                        ch = childOf# [(nTry - 1) * alphabet + sy]
                        if ch > 0
                            totW = totW + nodeCount# [ch]
                        endif
                    endfor
                    if totW > 0
                        ipNode = nTry
                        searching = 0
                    endif
                endif
                if searching = 1
                    if ctxDepth <= 0
                        searching = 0
                        ipNode = 1
                        totW = 0
                        for sy to alphabet
                            ch = childOf# [(ipNode - 1) * alphabet + sy]
                            if ch > 0
                                totW = totW + nodeCount# [ch]
                            endif
                        endfor
                    else
                        ctxDepth = ctxDepth - 1
                    endif
                endif
            endwhile
            sumOrder = sumOrder + ctxDepth
            nOrder = nOrder + 1

            chosenChild = 0
            if totW > 0
                target = randomUniform (0, totW)
                acc = 0
                for sy to alphabet
                    if chosenChild = 0
                        ch = childOf# [(ipNode - 1) * alphabet + sy]
                        if ch > 0
                            acc = acc + nodeCount# [ch]
                            if acc >= target
                                chosenChild = ch
                            endif
                        endif
                    endif
                endfor
            endif

            if chosenChild = 0
                wantSym = symbol# [randomInteger (1, num_windows)]
                escaped = 1
            else
                wantSym = nodeSymbol# [chosenChild]
            endif
            if escaped = 1
                nEscape = nEscape + 1
            endif

            srcW = 0
            if lastWin > 0 and lastWin < num_windows
                if symbol# [lastWin + 1] = wantSym
                    srcW = lastWin + 1
                endif
            endif
            if srcW = 0
                if symCount# [wantSym] > 0
                    srcW = symWin# [symStart# [wantSym] + randomInteger (1, symCount# [wantSym])]
                else
                    srcW = randomInteger (1, num_windows)
                endif
            endif

            merged = 0
            if nRuns > 0 and escaped = 0
                if srcW = runSrc# [nRuns] + runLen# [nRuns] and runLen# [nRuns] < max_copy_windows
                    runLen# [nRuns] = runLen# [nRuns] + 1
                    estDur = estDur + hop_size
                    if histLen < maxHist
                        histLen = histLen + 1
                        outSym# [histLen] = symbol# [srcW]
                    endif
                    lastWin = srcW
                    merged = 1
                endif
            endif
            if merged = 0
                @emitRun: srcW, 1, escaped, ctxDepth
            endif

        # ------------------------------------------------------------
        else
            # LZ77 COPY AND DEVIATE
            # Longest match of the recent OUTPUT inside the source
            # symbol stream, then copy forward from just after it.
            # Candidates are restricted to occurrences of the last
            # output symbol, so the search is O(n/A * ctx) rather than
            # O(n * ctx). Ties are broken at random: that is where the
            # recombination comes from.
            matchLen = 0
            q = 0
            if histLen = 0
                q = randomInteger (1, num_windows)
            else
                lastSym = outSym# [histLen]
                nc = symCount# [lastSym]
                bestLen = 0
                nBest = 0
                for c to nc
                    p = symWin# [symStart# [lastSym] + c]
                    if p < num_windows
                        ml = 1
                        cont = 1
                        while cont = 1
                            if ml >= ctxMax or ml >= histLen or p - ml < 1
                                cont = 0
                            else
                                if symbol# [p - ml] = outSym# [histLen - ml]
                                    ml = ml + 1
                                else
                                    cont = 0
                                endif
                            endif
                        endwhile
                        if ml > bestLen
                            bestLen = ml
                            nBest = 1
                        elsif ml = bestLen
                            nBest = nBest + 1
                        endif
                    endif
                endfor

                if nBest = 0
                    q = randomInteger (1, num_windows)
                else
                    pickN = randomInteger (1, nBest)
                    seen = 0
                    for c to nc
                        if q = 0
                            p = symWin# [symStart# [lastSym] + c]
                            if p < num_windows
                                ml = 1
                                cont = 1
                                while cont = 1
                                    if ml >= ctxMax or ml >= histLen or p - ml < 1
                                        cont = 0
                                    else
                                        if symbol# [p - ml] = outSym# [histLen - ml]
                                            ml = ml + 1
                                        else
                                            cont = 0
                                        endif
                                    endif
                                endwhile
                                if ml = bestLen
                                    seen = seen + 1
                                    if seen = pickN
                                        q = p + 1
                                        matchLen = bestLen
                                    endif
                                endif
                            endif
                        endif
                    endfor
                    if q = 0
                        q = randomInteger (1, num_windows)
                    endif
                endif
            endif

            lenW = randomInteger (1, max_copy_windows)
            if q + lenW - 1 > num_windows
                lenW = num_windows - q + 1
            endif
            if lenW < 1
                lenW = 1
            endif
            @emitRun: q, lenW, 0, matchLen

            # the literal that breaks the match
            if novelty > 0 and nRuns < maxRuns - 1
                if randomUniform (0, 1) < novelty
                    nextW = q + lenW
                    litW = randomInteger (1, num_windows)
                    if nextW <= num_windows
                        litTries = 0
                        while symbol# [litW] = symbol# [nextW] and litTries < 12
                            litW = randomInteger (1, num_windows)
                            litTries = litTries + 1
                        endwhile
                    endif
                    nLiteral = nLiteral + 1
                    @emitRun: litW, 1, 1, 0
                endif
            endif
        endif

    endif
endwhile

genTime = stopwatch
appendInfoLine: "  ", nRuns, " tokens generated in ", fixed$ (genTime, 3), " s"
if generation_mode = 1
    appendInfoLine: "  Phrases substituted: ", nSubst, "/", nRuns
elsif generation_mode = 2
    meanOrder = 0
    if nOrder > 0
        meanOrder = sumOrder / nOrder
    endif
    appendInfoLine: "  Forced escapes: ", nEscape, "/", nOrder,
        ... " steps | mean context order actually used: ", fixed$ (meanOrder, 2)
else
    appendInfoLine: "  Literals emitted: ", nLiteral, "/", nRuns
endif

# ============================================================
# STEP 5: Render
# ============================================================
appendInfoLine: ""
appendInfoLine: "Rendering..."

segment_ids# = zero# (maxRuns)
usedSrc# = zero# (maxRuns)
usedLen# = zero# (maxRuns)
usedKind# = zero# (maxRuns)
nSegs = 0
accumDur = 0
minSegDur = 0
psolaSkipped = 0
minPsolaDur = 3 / 75

for r to nRuns
  if accumDur < output_duration_s + xfadeSec
    w0 = runSrc# [r]
    lenW = runLen# [r]
    if w0 + lenW - 1 > num_windows
        lenW = num_windows - w0 + 1
    endif
    start_time = startByOrig# [w0]
    end_time = endByOrig# [w0 + lenW - 1]

    selectObject: original_sound
    segment = Extract part: start_time, end_time, "rectangular", 1, "no"
    selectObject: segment
    seg_dur = Get total duration

    varied_segment = segment

    if variation_method = 1
        # Pitch shift (PSOLA)
        # v0.8 fix 9: To Manipulation refuses a Sound shorter than
        # 3/pitchFloor. A 50 ms window at floor 75 aborted v0.7.
        if seg_dur >= minPsolaDur
            shift_semitones = randomGauss (0, 12 * variation_amount)
            shift_factor = 2 ^ (shift_semitones / 12)
            shiftStr$ = string$ (shift_factor)
            selectObject: segment
            manipulation = To Manipulation: 0.01, 75, 600
            pitch_tier = Extract pitch tier
            Formula: "self * " + shiftStr$
            plusObject: manipulation
            Replace pitch tier
            selectObject: manipulation
            varied_segment = Get resynthesis (overlap-add)
            removeObject: manipulation, pitch_tier
        else
            psolaSkipped = psolaSkipped + 1
        endif

    elsif variation_method = 2
        # Time stretch
        if seg_dur >= minPsolaDur
            stretch_factor = 1 + randomGauss (0, variation_amount)
            stretch_factor = max (0.5, min (2, stretch_factor))
            selectObject: segment
            manipulation = To Manipulation: 0.01, 75, 600
            duration_tier = Extract duration tier
            Add point: seg_dur / 2, stretch_factor
            plusObject: manipulation
            Replace duration tier
            selectObject: manipulation
            varied_segment = Get resynthesis (overlap-add)
            removeObject: manipulation, duration_tier
        else
            psolaSkipped = psolaSkipped + 1
        endif

    elsif variation_method = 3
        # Amplitude modulation
        selectObject: segment
        varied_segment = Copy: "modulated"
        mod_freq = 10 * (1 + variation_amount * 10)
        varAmtStr$ = string$ (variation_amount)
        modFreqStr$ = string$ (mod_freq)
        Formula: "self * (1 + " + varAmtStr$ + " * sin(2*pi*" + modFreqStr$ + "*x))"

    elsif variation_method = 4
        # Spectral lowpass
        selectObject: segment
        spectrum = To Spectrum: "yes"
        cutoff = 1000 + randomUniform (-500, 500) * variation_amount
        cutoffStr$ = string$ (cutoff)
        attenStr$ = string$ (1 - variation_amount)
        Formula: "if x > " + cutoffStr$ + " then self * " + attenStr$ + " else self fi"
        sound_padded = To Sound
        selectObject: sound_padded
        varied_segment = Extract part: 0, seg_dur, "rectangular", 1, "no"
        removeObject: spectrum, sound_padded

    elsif variation_method = 5
        # Reverse
        if randomUniform (0, 1) < variation_amount
            selectObject: segment
            varied_segment = Copy: "reversed"
            Reverse
        endif

    elsif variation_method = 6
        # Granular shuffle
        if variation_amount <= 0.0001
            selectObject: segment
            varied_segment = Copy: "granular_identity"
        else
            grain_size = 0.02
            num_grains = floor (seg_dur / grain_size)
            remainder = seg_dur - num_grains * grain_size
            if remainder > 0.0005
                num_grains = num_grains + 1
            endif
            if num_grains < 1
                num_grains = 1
            endif

            maxShift = round (num_grains * variation_amount)
            if maxShift < 1
                maxShift = 1
            endif

            grain_ids# = zero# (num_grains)
            for g to num_grains
                lowIdx = g - maxShift
                if lowIdx < 1
                    lowIdx = 1
                endif
                highIdx = g + maxShift
                if highIdx > num_grains
                    highIdx = num_grains
                endif
                shuffled_idx = randomInteger (lowIdx, highIdx)
                shuffled_start = (shuffled_idx - 1) * grain_size
                shuffled_end = min (shuffled_start + grain_size, seg_dur)
                if shuffled_end - shuffled_start > 0.0005
                    selectObject: segment
                    temp_grain = Extract part: shuffled_start, shuffled_end, "Hanning", 1, "no"
                    grain_ids# [g] = temp_grain
                else
                    Create Sound from formula: "grain", 1, 0, 0.001, sample_rate, "0"
                    grain_ids# [g] = selected ("Sound")
                endif
            endfor

            selectObject: grain_ids# [1]
            for g from 2 to num_grains
                plusObject: grain_ids# [g]
            endfor
            if num_grains >= 2
                varied_segment = Concatenate
            else
                varied_segment = Copy: "single_grain"
            endif
            for g to num_grains
                removeObject: grain_ids# [g]
            endfor
        endif
    endif
    # variation_method = 7 (None): the extracted run passes through

    selectObject: varied_segment
    vsDur = Get total duration

    nSegs = nSegs + 1
    segment_ids# [nSegs] = varied_segment
    usedSrc# [nSegs] = w0
    usedLen# [nSegs] = lenW
    usedKind# [nSegs] = runKind# [r]
    accumDur = accumDur + vsDur - xfadeSec
    if nSegs = 1 or vsDur < minSegDur
        minSegDur = vsDur
    endif

    if varied_segment <> segment
        removeObject: segment
    endif
  endif
endfor

if psolaSkipped > 0
    appendInfoLine: "  ", psolaSkipped, " segments shorter than ",
        ... fixed$ (1000 * minPsolaDur, 0), " ms passed through unvaried (PSOLA minimum)"
endif

# === Concatenate ===
# Concatenate with overlap needs a crossfade shorter than every
# segment. Measured on 6.4.06: Praat's crossfade is amplitude-
# complementary and a 20-segment chain at 70% overlap reconstructs the
# original to 2e-13, so a large crossfade is safe and correct - the cap
# below exists only for Time stretch, which can halve a segment. When
# it fires the tiling is no longer exact and the trim absorbs it.
xfadeUsed = xfadeSec
if nSegs > 0 and xfadeUsed > 0.9 * minSegDur
    xfadeUsed = 0.9 * minSegDur
    appendInfoLine: "  Crossfade capped at ", fixed$ (1000 * xfadeUsed, 1),
        ... " ms by the shortest segment (", fixed$ (1000 * minSegDur, 1), " ms)"
endif
appendInfoLine: "  Joining ", nSegs, " segments (", nSegs - 1, " crossfades of ",
    ... fixed$ (1000 * xfadeUsed, 1), " ms)..."

selectObject: segment_ids# [1]
for i from 2 to nSegs
    plusObject: segment_ids# [i]
endfor

if nSegs >= 2
    output = Concatenate with overlap: xfadeUsed
else
    output = Copy: "single"
endif
Rename: sound_name$ + "_LZ_" + presetName$

for i to nSegs
    removeObject: segment_ids# [i]
endfor

# exact duration, both directions
selectObject: output
current_duration = Get total duration
if current_duration > output_duration_s
    selectObject: output
    trimmed = Extract part: 0, output_duration_s, "rectangular", 1, "no"
    removeObject: output
    output = trimmed
elsif current_duration < output_duration_s - 0.0005
    appendInfoLine: "  Material ran short (", fixed$ (current_duration, 3),
        ... " s); padding to the requested ", fixed$ (output_duration_s, 3), " s"
    Create Sound from formula: "lz_pad", 1, 0,
        ... output_duration_s - current_duration, sample_rate, "0"
    padSnd = selected ("Sound")
    selectObject: output
    plusObject: padSnd
    joined = Concatenate
    removeObject: output, padSnd
    output = joined
endif
selectObject: output
Rename: sound_name$ + "_LZ_" + presetName$

# one fade at each end of the finished sound
selectObject: output
finalDurNow = Get total duration
edgeFade = 0.005
if edgeFade > finalDurNow * 0.1
    edgeFade = finalDurNow * 0.1
endif
if edgeFade > 0.0002
    efs$ = fixed$ (edgeFade, 8)
    selectObject: output
    Formula: "if x - xmin < " + efs$ + " then self * ((x - xmin) / " + efs$ + ") else self fi"
    selectObject: output
    Formula: "if xmax - x < " + efs$ + " then self * ((xmax - x) / " + efs$ + ") else self fi"
endif

selectObject: output
Scale peak: 0.95
final_duration = Get total duration
final_peak = Get absolute extremum: 0, 0, "None"

random_initializeSafelyAndUnpredictably ()

# ============================================================
# VISUALIZATION
# Panels follow the parse, not a similarity graph:
#   A - the symbol stream with the LZ phrase boundaries on it
#   B - phrase length against phrase index (the LZ growth curve)
#   C - phrase-length distribution
#   D - the generated token stream mapped back to source windows
#   E - the rendered output
# ============================================================

procedure symColour: .s
    if undefSymbol > 0 and .s = undefSymbol
        .rgb$ = "{0.62, 0.62, 0.66}"
    else
        .tt = 0
        if kClusters > 1
            .tt = (.s - 1) / (kClusters - 1)
        endif
        .r = 0.22 + .tt * 0.62
        .g = 0.52 - .tt * 0.16
        .b = 0.78 - .tt * 0.54
        if .g < 0
            .g = 0
        endif
        if .b < 0
            .b = 0
        endif
        .rgb$ = "{" + fixed$ (.r, 3) + ", " + fixed$ (.g, 3) + ", " + fixed$ (.b, 3) + "}"
    endif
endproc

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    selectObject: output
    nResultCh = Get number of channels
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15

    vizName$ = replace$ (sound_name$, "_", "\_ ", 0)

    pageHeight = 9.10
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Lempel-Ziv Audio Variations v0.8##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + analysis_name$ + " analysis | " + mode_long$ + " | " + variation_name$

    # === A: symbol stream + LZ phrase parse ===
    Select outer viewport: 0, 8, 0.72, 2.60
    Select inner viewport: 0.60, 7.70, 1.02, 2.36
    Axes: 0.5, num_windows + 0.5, 0.3, alphabet + 0.7
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, num_windows + 0.5, 0.3, alphabet + 0.7

    # alternating bands = LZ phrases
    if nPhrases <= 600
        for p to nPhrases
            if p mod 2 = 0
                pStart = phraseStart# [p] - 0.5
                pEnd = phraseStart# [p] + phraseLen# [p] - 0.5
                Paint rectangle: "{0.912, 0.918, 0.936}", pStart, pEnd, 0.3, alphabet + 0.7
            endif
        endfor
    endif

    Select inner viewport: 0.60, 7.70, 1.02, 2.36
    Axes: 0.5, num_windows + 0.5, 0.3, alphabet + 0.7

    # symbols
    cellW = 0.4
    if num_windows > 800
        cellW = num_windows / 2000
    endif
    if num_windows <= 1200
        for w to num_windows
            @symColour: symbol# [w]
            Paint rectangle: symColour.rgb$, w - cellW, w + cellW, symbol# [w] - 0.36, symbol# [w] + 0.36
        endfor
    else
        Line width: 1
        Colour: "{0.28, 0.45, 0.72}"
        for w from 2 to num_windows
            Draw line: w - 1, symbol# [w - 1], w, symbol# [w]
        endfor
    endif

    # phrase boundaries
    if nPhrases <= 600
        Line width: 1
        Colour: "{0.45, 0.45, 0.55}"
        for p to nPhrases
            bX = phraseStart# [p] - 0.5
            Draw line: bX, 0.3, bX, alphabet + 0.7
        endfor
    endif

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Symbol"
    Text bottom: "no", "Source window"
    Text top: "no", "Symbol Stream and LZ78 Parse | vertical rules and shaded bands are phrase boundaries"

    # === B: phrase length against phrase index ===
    Select outer viewport: 0, 4, 2.60, 4.30
    Select inner viewport: 0.60, 3.85, 2.86, 4.06
    growTop = maxPhraseLen + 1
    if growTop < 2
        growTop = 2
    endif
    Axes: 0, nPhrases + 1, 0, growTop
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nPhrases + 1, 0, growTop

    if nPhrases <= 800
        barW = 0.42
        if nPhrases > 200
            barW = nPhrases / 500
        endif
        for p to nPhrases
            Paint rectangle: "{0.30, 0.48, 0.74}", p - barW, p + barW, 0, phraseLen# [p]
        endfor
    else
        Colour: "{0.30, 0.48, 0.74}"
        for p from 2 to nPhrases
            Draw line: p - 1, phraseLen# [p - 1], p, phraseLen# [p]
        endfor
    endif

    Select inner viewport: 0.60, 3.85, 2.86, 4.06
    Axes: 0, nPhrases + 1, 0, growTop
    Line width: 1
    Colour: "{0.80, 0.35, 0.20}"
    Dashed line
    Draw line: 0, meanPhraseLen, nPhrases + 1, meanPhraseLen
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Phrase length"
    Text bottom: "no", "Phrase index"
    Text top: "no", "LZ78 Growth | dashed = mean " + fixed$ (meanPhraseLen, 2) + " windows"

    # === C: phrase-length distribution ===
    Select outer viewport: 4, 8, 2.60, 4.30
    Select inner viewport: 4.45, 7.70, 2.86, 4.06

    lenHistMax = maxPhraseLen
    if lenHistMax < 2
        lenHistMax = 2
    endif
    if lenHistMax > 40
        lenHistMax = 40
    endif
    lenHist# = zero# (lenHistMax)
    for p to nPhrases
        lv = phraseLen# [p]
        if lv < 1
            lv = 1
        endif
        if lv > lenHistMax
            lv = lenHistMax
        endif
        lenHist# [lv] = lenHist# [lv] + 1
    endfor
    lenPeak = 1
    for b to lenHistMax
        if lenHist# [b] > lenPeak
            lenPeak = lenHist# [b]
        endif
    endfor

    Axes: 0.5, lenHistMax + 0.5, 0, lenPeak * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, lenHistMax + 0.5, 0, lenPeak * 1.15
    for b to lenHistMax
        if lenHist# [b] > 0
            ratio = (b - 1) / max (1, lenHistMax - 1)
            cR = 0.25 + ratio * 0.55
            cG = 0.48 - ratio * 0.14
            cB = 0.76 - ratio * 0.50
            if cB < 0
                cB = 0
            endif
            rgb$ = "{" + fixed$ (cR, 3) + ", " + fixed$ (cG, 3) + ", " + fixed$ (cB, 3) + "}"
            Paint rectangle: rgb$, b - 0.4, b + 0.4, 0, lenHist# [b]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Phrases"
    Text bottom: "no", "Phrase length (windows)"
    Text top: "no", "Dictionary Profile | phrase-length distribution"

    # === D: generated token stream -> source windows ===
    Select outer viewport: 0, 8, 4.30, 6.20
    Select inner viewport: 0.60, 7.70, 4.56, 5.96
    Axes: 0, nSegs + 1, 0, num_windows + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nSegs + 1, 0, num_windows + 1

    Colour: "{0.84, 0.84, 0.84}"
    Dotted line
    grid_step = round (num_windows / 8)
    if grid_step < 1
        grid_step = 1
    endif
    yg = grid_step
    while yg <= num_windows
        Draw line: 0, yg, nSegs + 1, yg
        yg = yg + grid_step
    endwhile
    Solid line

    # trajectory first, tokens on top (grid/connector under the data)
    Line width: 1
    Colour: "{0.72, 0.76, 0.84}"
    for i from 2 to nSegs
        yA = usedSrc# [i - 1] + (usedLen# [i - 1] - 1) / 2
        yB = usedSrc# [i] + (usedLen# [i] - 1) / 2
        Draw line: i - 1, yA, i, yB
    endfor

    # every token gets real vertical extent, so a one-window token is
    # still a visible bar rather than a sub-pixel dot
    minBar = num_windows / 90
    if minBar < 0.6
        minBar = 0.6
    endif
    Line width: 3
    if nSegs > 300
        Line width: 2
    endif
    if nSegs > 900
        Line width: 1
    endif
    for i to nSegs
        y0 = usedSrc# [i]
        y1 = usedSrc# [i] + usedLen# [i] - 1
        if y1 - y0 < minBar
            yMid = (y0 + y1) / 2
            y0 = yMid - minBar / 2
            y1 = yMid + minBar / 2
        endif
        if usedKind# [i] = 0
            Colour: "{0.22, 0.42, 0.74}"
        else
            Colour: "{0.88, 0.52, 0.12}"
        endif
        Draw line: i, y0, i, y1
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Source window"
    Text bottom: "no", "Output token"
    if generation_mode = 1
        Text top: "no", "Token Stream | bar = one phrase, its length = phrase depth | amber = substituted phrase"
    elsif generation_mode = 2
        Text top: "no", "Token Stream | bar = a contiguous run of the trie walk | amber = escape to root"
    else
        Text top: "no", "Token Stream | bar = one LZ77 copy (offset, length) | amber = literal"
    endif

    # === E: rendered output ===
    Select outer viewport: 0, 8, 6.20, 7.55
    Select inner viewport: 0.60, 7.70, 6.42, 7.22
    Axes: 0, final_duration, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, final_duration, -ampViz, ampViz

    selectObject: output
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Select inner viewport: 0.60, 7.70, 6.42, 7.22
    Axes: 0, final_duration, -ampViz, ampViz
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, final_duration, 0

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "no", "Amp"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Rendered Output | " + fixed$ (final_duration, 2) + " s | " + string$ (nSegs) + " segments joined by " + fixed$ (1000 * xfadeUsed, 0) + " ms overlap-add"

    # === Summary strip ===
    Select outer viewport: 0, 8, 7.60, 9.05
    Select inner viewport: 0.60, 7.70, 7.70, 8.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if lzNorm = undefined
        lzNormStr$ = "n/a"
    else
        lzNormStr$ = fixed$ (lzNorm, 4)
    endif
    if codeRatio = undefined
        codeStr$ = "n/a"
    else
        codeStr$ = fixed$ (codeRatio, 2) + "x"
    endif
    summary1$ = "##Symbolization##  " + string$ (num_windows) + " windows | alphabet " + string$ (alphabet) + " (" + string$ (symUsed) + " used) | entropy " + fixed$ (symEntropy, 2) + " of " + fixed$ (log2 (alphabet), 2) + " bits | window " + fixed$ (window_size_s, 3) + " s | overlap " + fixed$ (overlap, 2)
    summary2$ = "##LZ78 parse##  " + string$ (nPhrases) + " phrases | mean " + fixed$ (meanPhraseLen, 2) + " longest " + string$ (maxPhraseLen) + " windows | c(n) " + string$ (lzComplexity) + " | normalized " + lzNormStr$ + " | coded size " + codeStr$
    summary3$ = "##Generation & output##  " + mode_long$ + " | novelty " + fixed$ (novelty, 2) + " | max copy " + string$ (max_copy_windows) + " | " + string$ (nRuns) + " tokens | " + variation_name$ + " amount " + fixed$ (variation_amount, 2) + " | " + fixed$ (final_duration, 2) + " s | peak " + fixed$ (final_peak, 3) + " | seed " + seedLabel$
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore the complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: output
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$ ("Sound")
appendInfoLine: "Duration: ", fixed$ (final_duration, 2), " s"
appendInfoLine: "Dictionary: ", nPhrases, " LZ78 phrases over an alphabet of ", alphabet

# === Cleanup ===
if analysis_type = 1
    removeObject: pitch
elsif analysis_type = 3
    removeObject: intensity
endif
if madeMono
    removeObject: original_sound
endif

# === Play ===
if play_result
    selectObject: output
    Play
endif

selectObject: output
