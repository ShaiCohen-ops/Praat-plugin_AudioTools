# ============================================================
# Praat AudioTools - Gestural_Accumulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Gestural Accumulator - algorithmic composition engine that
#   transforms a single sound into an evolving perceptual canon
#   by rigorously budgeting dissimilarity across timbral color
#   and gestural motion. Creates variants with pitch/formant/
#   duration shifts, then selects a path through timbral space
#   following a dissimilarity budget schedule.
#
# Changelog v0.5.1 (2026) -- visualization uniformity pass; no change
# to variant generation, feature space, path selection or synthesis:
#   - FIX: "Transition #" printed as "Transition". In Praat drawn text
#     "#" is the bold marker: it bolds the character after it and
#     prints nothing itself, so a trailing "#" vanishes entirely (and
#     mid-string, "item #3" renders as "item" + bold 3). Now "\# ".
#   - FIX: the last overlap bar was drawn through the panel's right
#     frame. Bars span i - 0.4 to i + 0.4 for i up to sel_count, so the
#     final one reached sel_count + 0.4 while the axis stopped at
#     sel_count, and Praat does not clip to the inner viewport. The
#     axis now carries half a step of margin at each end.
#   - FIX: Sound names were drawn raw and Praat reads "_" as a
#     subscript marker. "a_vox" printed as "a(sub v)ox", and the
#     composite name "a_vox_canon_Custom" lost both underscores in the
#     summary strip. Escaped for display only.
#   - FIX: drawing ended inside the summary strip, so Save as PNG and
#     Copy to clipboard exported that strip alone (2361 x 314 px)
#     rather than the page. Drawing now ends on the full page, and the
#     opening Select outer viewport declares the real height (6.40 in)
#     instead of 8.
#   - Panels C/D's bottom axis labels sat 0.10 in below their frames
#     with panel E's caption 0.35 in further on; the two lines read as
#     one block. Vertical margins are now 0.15 in above a panel with a
#     top caption and 0.30 in below one with a bottom label. Page
#     height is unchanged at 6.40 in.
#   - Half-width geometry regularized: outer splits 0/4.2 and 4.2/8
#     become 0/4 and 4/8; inner viewports 0.55/4.00 and 4.55/7.75
#     become the standard 0.60/3.85 and 4.45/7.70. Full-width panels
#     move from 0.55/7.72 to 0.60/7.70.
#   - Fonts: five panels labelled their axes at 6 while captioning at
#     7 in the same panel; axis labels are now 7 throughout.
#   - Colours: the reference cross and inactive variant dots move from
#     {0.78, 0.78, 0.82} to the standard grid grey {0.80, 0.80, 0.80};
#     summary text {0.28, 0.28, 0.28} -> {0.25, 0.25, 0.35}; subtitle
#     {0.35, 0.35, 0.52} -> {0.35, 0.35, 0.50}. Hues otherwise
#     unchanged, pending the palette decision.
#   - File converted from CRLF to LF, the convention everywhere else
#     in the category.
#
# Changelog v0.5.0:
#
#   NOTE: audio is NOT comparable to v0.4.2. The feature space,
#   the path selection and the audio ordering were all wrong;
#   every fix below changes the output.
#
#   CRITICAL 1 - MFCC feature extraction was collapsing to 2 dims.
#     `Get mean: d, d, 1, n_cols` on a Matrix takes WORLD-COORDINATE
#     ranges, and Praat treats an equal-bounds range as "all". Probe
#     on 6.4.42 with a 3x4 matrix of known values: rows are 102.5 /
#     202.5 / 302.5, but `Get mean: d, d, 1, 4` returned 202.5 (the
#     grand mean) for every d. So f_i_1 ... f_i_13 were all the same
#     number, and with motion on, f_i_14 ... f_i_26 likewise. The
#     "13/26-dimensional timbre space" was at most 2-dimensional.
#     v0.5.0 uses `Get all values in row: d` -> vector, then
#     mean() / stdev() on that vector.
#
#   CRITICAL 2 - the canon played backwards.
#     `Sounds: Concatenate with overlap` follows the OBJECT LIST
#     order, not the selectObject/plusObject order. `Copy: "Result"`
#     puts Result at the bottom of the list while every variant was
#     created earlier and sits above it, so each pass produced
#     next + Result. Probe confirmed: with A above B in the list,
#     `selectObject: B / plusObject: A` yields A-then-B audio.
#     Consequence: the rendered path was the reverse of the plotted
#     path, so Accelerate sounded like Decelerate and vice versa.
#     v0.5.0 makes a fresh Copy of the next variant AFTER Result so
#     the list order matches the intended order.
#
#   CRITICAL 3 - the random seed did nothing.
#     `randomseed = random_seed` only created a numeric variable.
#     Probe: two identical assignments gave different draws.
#     v0.5.0 calls random_initializeWithSeedUnsafelyButPredictably
#     and restores random_initializeSafelyAndUnpredictably once the
#     variant family is built.
#
#   4 - Pacing schedule was off by one. progress = s / K aimed the
#     first of K-1 transitions at 1/K of the budget. Now
#     progress = (s-1)/(K-1), so schedule[1] = 0 and
#     schedule[K] = target_budget. K = 1 handled separately.
#
#   5 - Anchor. New `Anchor_is_source`: variant 1 is now the
#     untransformed source (0 st, ratio 1.0, factor 1.0), so
#     Skip_first has a real meaning - start the path at the source
#     but do not sound it. Budget is now reported twice:
#     conceptual (includes the source transition) and audible.
#
#   6 - Motion measure. Standard deviation is dispersion, not
#     motion. New `Motion_measure`: mean absolute frame-to-frame
#     MFCC difference (default) or the old per-coefficient SD,
#     now honestly labelled temporal dispersion.
#
#   7 - Feature standardization. Each of the 13/26 dimensions is
#     z-scored across the variant family before the Euclidean
#     distance, so large-scale coefficients no longer dominate.
#
#   8 - Budget is now in median-distance units. All pairwise
#     distances are divided by the median pairwise distance, so a
#     budget of 6.0 means roughly six typical transitions
#     regardless of input file, dimension count or ranges.
#     Defaults and presets rescaled accordingly (was 40-120 raw).
#
#   9 - Floors on the median distance and on rel_dist, so a
#     degenerate variant family cannot divide by zero.
#
#   10 - Multichannel. >2 channels no longer silently dropped:
#     all channels are transformed with the same parameters and
#     recombined (Combine to stereo accepts N sounds -> N channels,
#     verified on a 4-channel probe).
#
#   11 - Validation: Formant_shift_range clamped to [0, 0.95],
#     1 + Time_stretch clamped to 3, N_variants / K_steps are now
#     `natural`, K_steps clamped to N_variants.
#
#   12 - New `Overlap_span`: overlap may be limited by the whole
#     accumulated composite (multi-layer smearing, the old and
#     still default behaviour) or by the previous variant only
#     (strict pairwise transitions).
#
# Changelog v0.4.2:
#
#   TIER 1 (polish, audio bit-identical):
#     - Dropped 6 decorative `comment === ... ===` form rows
#       (Preset / Style / Structural Form / Overlap Rhetoric /
#       Parameters / Timbre & Motion / Output). Form: 20 rows
#       -> 14 rows.
#     - Added missing colons to all 3 optionmenus (Preset:,
#       Pacing_curve:, Overlap_mode:). Suite convention.
#     - Added presetName$ (short form, no special chars) for
#       output filename: `<input>_canon` -> `<input>_canon_<preset>`
#       so different presets produce distinct Praat object names.
#     - Visualization rewritten from custom 8x5.5 layout to suite
#       8x8:
#         Title bar (suite light) + metadata subtitle
#         Original / Canon waveform (side-by-side, headline)
#         Dissimilarity trajectory / Variant transform scatter
#           (side-by-side, signature)
#         Overlap analysis  (full width, bar chart)
#         Light-grey 3-line summary  (suite standard)
#
#   TIER 2 (real bugs, audio bit-identical):
#     - FIXED: pacing_curve$ and overlap_mode$ strings desynced
#       from numeric values after preset override. v0.4.1 had
#       presets that reassigned the NUMERIC pacing_curve and
#       overlap_mode but never updated the matching $ strings
#       (which are set by the form to the user's original choice).
#       Result: the info log and viz could display "Pacing: Linear"
#       while running with numeric pacing_curve = 2 (Accelerate)
#       under a preset. Cosmetic-only bug (audio was correct;
#       display was wrong). v0.4.2 rebuilds pacing_curve$ and
#       overlap_mode$ as SHORT strings from the final numeric
#       values immediately after the preset block.
#     - FIXED: legend panel text was drawn at unpredictable outer
#       y positions. v0.4.1 lines 651-657 set the legend's outer
#       viewport but never set Axes, so it inherited
#       `Axes: 1, sel_count, 0, max_overlap * 1.1` from the
#       overlap-analysis panel above. The Text() calls used x=1.0
#       and y=0.3 / y=-2.7 in those inherited axes, sending the
#       second text far below the legend strip (typically outer
#       y > 5.5, off the panel). v0.4.2 sets explicit
#       `Axes: 0, 1, 0, 1` before any Text() in the summary panel.
#     - FIXED: Skip-First viz edge case. v0.4.1 gated the overlap
#       analysis viz on `if sel_count > 1`, but when skip_first=1
#       and sel_count=2, start_pos=2 so the inner loop
#       `for i from start_pos+1 to sel_count` = `for 3 to 2`
#       doesn't execute (silent no-op per Praat for-loop rules),
#       leaving max_overlap at 0 and producing
#       `Axes: 1, 2, 0, 0` (degenerate y-range). v0.4.2 gates on
#       `if sel_count > start_pos` so the panel only renders
#       when there's at least one transition to display.
#
#   Audio output is bit-identical to v0.4.1 for the same seed.
#
# Changelog v0.4.1:
#   - FIXED: Variable substitution syntax error in visualization
#   - FIXED: Array index out of bounds when 'Skip First' is active
#   - FIXED: Praat crash caused by overlapping short sounds > 100%
#
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form Gestural Accumulator v0.5.1
    optionmenu Preset: 1
        option Custom
        option Smooth Drift (Hide Ruptures)
        option Violent Rupture (Expose Ruptures)
        option Nervous Energy (High Motion / Glitch)
    optionmenu Pacing_curve: 1
        option Linear (Steady accumulation)
        option Accelerate (Slow start -> Rush to finish)
        option Decelerate (Explosive start -> Stabilize)
    optionmenu Overlap_mode: 1
        option Hide Ruptures (Big Diff = Long Fade)
        option Expose Ruptures (Big Diff = Hard Cut)
    optionmenu Overlap_span: 1
        option Accumulated composite (multi-layer smear)
        option Previous variant only (strict pairwise)
    natural N_variants 30
    natural K_steps 8
    positive Target_budget 6.0
    boolean Track_motion_variance 1
    optionmenu Motion_measure: 1
        option Delta-MFCC (frame-to-frame motion)
        option Temporal dispersion (per-coefficient SD)
    positive Pitch_range_st 2.0
    positive Time_stretch 0.15
    real Formant_shift_range 0.15
    positive Random_seed 1987
    boolean Anchor_is_source 1
    boolean Skip_first 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Target_budget is in MEDIAN-DISTANCE units (v0.5.0), not raw MFCC
# units. 6.0 means "accumulate about six typical transitions".

# ==============================================================================
# 1. PRESETS
# ==============================================================================
# v0.5.0: budgets restated in median-distance units. The old raw
# values (40 / 120 / 80) were in unnormalized MFCC units and meant
# nothing across different input files.
if preset = 2
    # Smooth Drift
    pacing_curve = 1
    overlap_mode = 1
    track_motion_variance = 0
    pitch_range_st = 0.5
    target_budget = 4.0
elsif preset = 3
    # Violent Rupture
    pacing_curve = 2
    overlap_mode = 2
    track_motion_variance = 1
    pitch_range_st = 12.0
    target_budget = 12.0
elsif preset = 4
    # Nervous Energy
    pacing_curve = 3
    overlap_mode = 2
    track_motion_variance = 1
    pitch_range_st = 3.0
    time_stretch = 0.5
    target_budget = 8.0
endif

# v0.4.2 Tier 1: short preset name for output filename + viz.
# (v0.4.1 only had preset$ which is the form's full multi-word
# string with special chars; not ideal for filenames.)
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "SmoothDrift"
elsif preset = 3
    presetName$ = "ViolentRupture"
else
    presetName$ = "NervousEnergy"
endif

# v0.4.2 Tier 2 fix: rebuild pacing_curve$ and overlap_mode$ from
# the FINAL numeric values. v0.4.1 left these as the form's
# original strings, so after a preset override the displayed name
# could disagree with the actual numeric used during synthesis.
# Cosmetic-only bug (audio was correct), but the info log and viz
# stat panel showed wrong labels under presets 2-4.
if pacing_curve = 1
    pacing_curve$ = "Linear"
elsif pacing_curve = 2
    pacing_curve$ = "Accelerate"
else
    pacing_curve$ = "Decelerate"
endif

if overlap_mode = 1
    overlap_mode$ = "Hide ruptures"
else
    overlap_mode$ = "Expose ruptures"
endif

if overlap_span = 1
    overlap_span$ = "Composite"
else
    overlap_span$ = "Pairwise"
endif

if motion_measure = 1
    motion_measure$ = "Delta-MFCC"
else
    motion_measure$ = "Dispersion (SD)"
endif

# ==============================================================================
# 1b. PARAMETER VALIDATION  (v0.5.0)
# ==============================================================================
warn_lines$ = ""

# Formant ratio must stay strictly positive: f_shift is drawn from
# 1 +/- formant_shift_range, so a range >= 1 can produce ratio <= 0.
if formant_shift_range < 0
    formant_shift_range = 0
    warn_lines$ = warn_lines$ + "  ! Formant_shift_range < 0 -> clamped to 0" + newline$
endif
if formant_shift_range > 0.95
    formant_shift_range = 0.95
    warn_lines$ = warn_lines$ + "  ! Formant_shift_range > 0.95 -> clamped (ratio must stay > 0)" + newline$
endif

# Change gender is documented as unreliable above a duration factor
# of 3. It does not error above that, but quality degrades.
if 1 + time_stretch > 3
    time_stretch = 2.0
    warn_lines$ = warn_lines$ + "  ! Time_stretch clamped so 1 + stretch <= 3 (Change gender limit)" + newline$
endif

# Variants are never reused, so the path cannot be longer than the family.
if k_steps > n_variants
    k_steps = n_variants
    warn_lines$ = warn_lines$ + "  ! K_steps > N_variants -> clamped to " + string$(n_variants) + newline$
endif

# ==============================================================================
# 2. SETUP (Stereo-Aware)
# ==============================================================================
# v0.5.0 CRITICAL 3: v0.4.2 had `randomseed = random_seed`, which
# only created a numeric variable and never touched the generator,
# so the reported seed described nothing. Praat needs the explicit
# call below; the generator is returned to its safe unpredictable
# state once the variant family has been drawn.
random_initializeWithSeedUnsafelyButPredictably (random_seed)

user_original_id = selected("Sound")
user_name$ = selected$("Sound")
n_channels_orig = Get number of channels

# Create WORK COPY (Stereo if original is stereo)
selectObject: user_original_id
Copy: "Work_Copy_Base"
work_id = selected("Sound")

# Store original duration for viz
selectObject: user_original_id
original_duration = Get total duration

# Create a MONO version strictly for Pitch Analysis
if n_channels_orig > 1
    Convert to mono
    analysis_id = selected("Sound")
else
    Copy: "Analysis_Temp"
    analysis_id = selected("Sound")
endif

selectObject: analysis_id
noprogress To Pitch: 0.0, 75, 600
base_pitch = Get quantile: 0.0, 0.0, 0.5, "Hertz"
removeObject: selected("Pitch")
removeObject: analysis_id

if base_pitch = undefined or base_pitch < 50
    base_pitch = 150
endif

writeInfoLine: "=== Gestural Accumulator v0.5.0: ", preset$, " ==="
appendInfoLine: "Original: ", user_name$
appendInfoLine: "Channels: ", n_channels_orig
appendInfoLine: "Base pitch: ", fixed$(base_pitch, 1), " Hz"
appendInfoLine: "Seed: ", random_seed, " (generator actually initialized)"
if warn_lines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Parameter adjustments:"
    appendInfo: warn_lines$
endif
appendInfoLine: ""
if anchor_is_source
    appendInfoLine: "Generating ", n_variants, " variants (variant 1 = untransformed source)..."
else
    appendInfoLine: "Generating ", n_variants, " variants..."
endif

# ==============================================================================
# 3. GENERATE VARIANTS (With Physics Safety)
# ==============================================================================
selectObject: work_id
current_dur = Get total duration

for i from 1 to n_variants
    # 1. Calculate Target Parameters
    # v0.5.0 fix 5: variant 1 is the untransformed source when
    # Anchor_is_source is on, so the path has a real origin and
    # Skip_first means "start at the source but don't sound it".
    is_anchor = 0
    if anchor_is_source and i = 1
        is_anchor = 1
        st_shift = 0
        f_shift = 1.0
        dur_factor = 1.0
    else
        st_shift = randomUniform(-pitch_range_st, pitch_range_st)
        f_shift = randomUniform(1.0 - formant_shift_range, 1.0 + formant_shift_range)

        # 2. DURATION PHYSICS (The Crash Fix)
        min_stretch = 1.0 - time_stretch
        if min_stretch < 0.1
            min_stretch = 0.1
        endif
        dur_factor = randomUniform(min_stretch, 1.0 + time_stretch)

        # SAFETY: Ensure resulting duration is at least 0.064s (Praat Limit)
        projected_dur = current_dur * dur_factor
        if projected_dur < 0.064
             dur_factor = 0.07 / current_dur
        endif
    endif

    target_pitch = base_pitch * (2 ^ (st_shift / 12))

    # Store transform params for viz
    variant_pitch_shift[i] = st_shift
    variant_formant_shift[i] = f_shift
    variant_duration_factor[i] = dur_factor

    # 3. Process
    selectObject: work_id
    if is_anchor
        # Untouched source - no Change gender pass at all
        Copy: "Variant_source"
        v_id'i' = selected("Sound")
    elsif n_channels_orig > 1
        # v0.5.0 fix 10: process EVERY channel, not just the first
        # two. v0.4.2 read only selected("Sound",1) and (,2), so with
        # 4-channel input channels 3-4 were dropped from the output
        # and also leaked into the object list on every iteration.
        Extract all channels
        for c from 1 to n_channels_orig
            ch'c' = selected("Sound", c)
        endfor
        for c from 1 to n_channels_orig
            selectObject: ch'c'
            nowarn noprogress Change gender: 75, 600, f_shift, target_pitch, 1.0, dur_factor
            vch'c' = selected("Sound")
        endfor
        selectObject: vch1
        for c from 2 to n_channels_orig
            plusObject: vch'c'
        endfor
        # Combine to stereo accepts N sounds and yields N channels
        Combine to stereo
        v_id'i' = selected("Sound")
        for c from 1 to n_channels_orig
            removeObject: ch'c'
            removeObject: vch'c'
        endfor
    else
        # MONO PATH
        nowarn noprogress Change gender: 75, 600, f_shift, target_pitch, 1.0, dur_factor
        v_id'i' = selected("Sound")
    endif

    selectObject: v_id'i'
    Scale peak: 0.9
endfor

# v0.5.0 CRITICAL 3: all random draws are done; hand the generator
# back to its safe unpredictable state.
random_initializeSafelyAndUnpredictably ()

appendInfoLine: "  Variants created"

# ==============================================================================
# 4. FEATURE EXTRACTION (Safety Wrapped)
# ==============================================================================
appendInfoLine: "Analyzing timbral features..."
base_dim = 13
if track_motion_variance
    total_dim = 26
else
    total_dim = 13
endif

for i from 1 to n_variants
    selectObject: v_id'i'
    
    # Temp mono for analysis
    if n_channels_orig > 1
        Convert to mono
        analyze_obj = selected("Sound")
    else
        Copy: "Temp_Analyze"
        analyze_obj = selected("Sound")
    endif
    
    # CRASH PROTECTION: Check duration before MFCC
    dur_check = Get total duration
    
    if dur_check > 0.025
        nocheck nowarn noprogress To MFCC: base_dim, 0.015, 0.005, 100.0, 100.0, 8000
        
        if numberOfSelected("MFCC") = 1
            mfcc_id = selected("MFCC")
            To Matrix
            mat_id = selected("Matrix")
            n_cols = Get number of columns
            
            # 1. Per-coefficient means
            # v0.5.0 CRITICAL 1: v0.4.2 used
            #   Get mean: d, d, 1, n_cols
            # which takes WORLD-COORDINATE ranges, and Praat reads an
            # equal-bounds range as "the whole extent". Verified on
            # 6.4.42: a 3x4 matrix with true row means 102.5/202.5/
            # 302.5 returned 202.5 (the grand mean) for every d. All
            # 13 mean features were therefore the same number, and
            # the "13/26-dimensional space" was really 2-dimensional.
            for d from 1 to base_dim
                row# = Get all values in row: d
                f'i'_'d' = mean(row#)
            endfor

            # 2. Motion / dispersion (With Safety Check)
            if track_motion_variance
                if n_cols > 1
                    for d from 1 to base_dim
                        row# = Get all values in row: d
                        idx = base_dim + d
                        if motion_measure = 1
                            # v0.5.0 fix 6: mean absolute frame-to-frame
                            # difference. SD describes spread, not motion:
                            # a slow glide and a fast alternation between
                            # the same two colours share an SD.
                            acc = 0
                            for c from 2 to n_cols
                                acc += abs(row#[c] - row#[c - 1])
                            endfor
                            f'i'_'idx' = acc / (n_cols - 1)
                        else
                            # Legacy measure, now honestly named:
                            # MFCC temporal dispersion.
                            f'i'_'idx' = stdev(row#)
                        endif
                    endfor
                else
                    for d from 1 to base_dim
                        idx = base_dim + d
                        f'i'_'idx' = 0
                    endfor
                endif
            endif
            removeObject: mfcc_id, mat_id
        else
            for d from 1 to total_dim
                f'i'_'d' = 0
            endfor
        endif
    else
        for d from 1 to total_dim
            f'i'_'d' = 0
        endfor
    endif
    
    removeObject: analyze_obj
endfor

appendInfoLine: "  Feature extraction complete"

# ==============================================================================
# 4b. FEATURE STANDARDIZATION  (v0.5.0 fix 7)
# ==============================================================================
# MFCC coefficients live on very different scales, and the motion
# features are on a different scale again. Without z-scoring, a
# couple of large dimensions dominate the Euclidean distance and
# the remaining dimensions contribute almost nothing.
if n_variants > 1
    for d from 1 to total_dim
        sum_d = 0
        for i from 1 to n_variants
            sum_d += f'i'_'d'
        endfor
        mu_d = sum_d / n_variants

        ss_d = 0
        for i from 1 to n_variants
            dev = f'i'_'d' - mu_d
            ss_d += dev * dev
        endfor
        sd_d = sqrt(ss_d / (n_variants - 1))

        # A constant dimension carries no information; leave it at 0.
        if sd_d < 1e-9
            sd_d = 1
        endif

        for i from 1 to n_variants
            f'i'_'d' = (f'i'_'d' - mu_d) / sd_d
        endfor
    endfor
endif

# Distance Matrix & Median
appendInfoLine: "Calculating pairwise distances..."
count = 0
for i from 1 to n_variants
    for j from i to n_variants
        if i = j
            d'i'_'j' = 0
        else
            s = 0
            for d from 1 to total_dim
                diff = f'i'_'d' - f'j'_'d'
                s += diff * diff
            endfor
            dist = sqrt(s)
            d'i'_'j' = dist
            d'j'_'i' = dist
            count += 1
            dist_list_'count' = dist
        endif
    endfor
endfor

# Bubble sort for Median
for i from 1 to count-1
    for j from i+1 to count
        if dist_list_'j' < dist_list_'i'
            temp = dist_list_'i'
            dist_list_'i' = dist_list_'j'
            dist_list_'j' = temp
        endif
    endfor
endfor
if count > 0
    mid_idx = round(count / 2)
    if mid_idx < 1
        mid_idx = 1
    endif
    global_median_dist = dist_list_'mid_idx'
else
    global_median_dist = 1.0
endif

# v0.5.0 fix 9: an all-identical variant family (or a failed feature
# extraction) gives a zero median, which then divides into rel_dist
# and into the Expose-mode factor.
degenerate_space = 0
if global_median_dist < 1e-9
    degenerate_space = 1
    global_median_dist = 1e-9
endif

appendInfoLine: "  Median pairwise distance (raw): ", fixed$(global_median_dist, 4)
if degenerate_space
    appendInfoLine: "  ! WARNING: variants are effectively identical in feature"
    appendInfoLine: "    space. The path and the overlap rhetoric are meaningless"
    appendInfoLine: "    for this input. Widen the transform ranges."
endif

# v0.5.0 fix 8: express every distance in units of the median
# pairwise distance, so the budget means the same thing across
# different inputs, dimension counts and transform ranges. After
# this rescale the median distance is 1.0 by construction and
# Target_budget reads as "about N typical transitions".
for i from 1 to n_variants
    for j from 1 to n_variants
        d'i'_'j' = d'i'_'j' / global_median_dist
    endfor
endfor

appendInfoLine: "  Distances normalized: budget is in median-distance units"

# ==============================================================================
# 5. BUDGET-AS-SCHEDULE SELECTION
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Selecting path through variant space..."
appendInfoLine: "  Pacing: ", pacing_curve$
appendInfoLine: "  Target budget: ", target_budget

# v0.5.0 fix 4: the first state is chosen at cumulative distance 0,
# so K steps contain K-1 transitions. v0.4.2 used progress = s / K,
# which aimed the FIRST transition at 1/K of the budget (15.0 of 60
# with K = 8) instead of 1/(K-1) (8.57). Now schedule[1] = 0 and
# schedule[K] = target_budget exactly.
if k_steps > 1
    for s from 1 to k_steps
        progress = (s - 1) / (k_steps - 1)
        if pacing_curve = 1
            # Linear
            sched_accum_'s' = target_budget * progress
        elsif pacing_curve = 2
            # Accelerate
            sched_accum_'s' = target_budget * (progress^2)
        elsif pacing_curve = 3
            # Decelerate
            sched_accum_'s' = target_budget * sqrt(progress)
        endif
    endfor
else
    sched_accum_1 = 0
endif

curr = 1
used'curr' = 1
sel_idx_1 = 1
sel_count = 1
current_accum = 0

for step from 2 to k_steps
    ideal_total = sched_accum_'step'
    needed_step = ideal_total - current_accum
    
    if needed_step < 0.1
        needed_step = 0.1
    endif
    
    best_cand = 0
    best_score = 1000000
    
    for cand from 1 to n_variants
        is_used = 0
        if variableExists("used"+string$(cand))
            is_used = used'cand'
        endif
        
        if is_used = 0
            dist = d'curr'_'cand'
            score = abs(dist - needed_step)
            if score < best_score
                best_score = score
                best_cand = cand
            endif
        endif
    endfor
    
    if best_cand = 0
        goto FINISH
    endif
    
    sel_count += 1
    sel_idx_'sel_count' = best_cand
    used'best_cand' = 1
    
    actual_dist = d'curr'_'best_cand'
    sel_dist_'sel_count' = actual_dist
    current_accum += actual_dist
    curr = best_cand
endfor
label FINISH

appendInfoLine: "  Selected ", sel_count, " variants of ", k_steps, " requested"
appendInfoLine: "  Conceptual budget: ", fixed$(current_accum, 2), " / ",
    ... fixed$(target_budget, 2), " median-distance units"
if sel_count < k_steps
    appendInfoLine: "  ! Path ended early: no unused variant remained."
endif

# ==============================================================================
# 6. ASSEMBLY (Stereo-Ready)
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Assembling canon..."

start_pos = 1
if skip_first and sel_count > 1
    start_pos = 2
endif

id = sel_idx_'start_pos'
selectObject: v_id'id'
Copy: "Result"
result_id = selected("Sound")
prev_variant_dur = Get total duration

# v0.5.0 fix 5: the budget the listener actually hears is not the
# budget the path accumulated. With Skip_first the transition into
# the first sounded variant is counted by the selector but never
# rendered, so report both figures.
audible_accum = 0

# Track overlaps for visualization
for i from start_pos+1 to sel_count
    next_idx = sel_idx_'i'
    selectObject: v_id'next_idx'
    next_dur = Get total duration

    step_dist = sel_dist_'i'
    audible_accum += step_dist

    # Distances are already in median units (median = 1.0), so
    # rel_dist is the step distance itself. Floor it so a degenerate
    # family cannot blow up the Expose-mode division.
    rel_dist = step_dist
    if rel_dist < 0.01
        rel_dist = 0.01
    endif

    # Rhetoric Logic
    if overlap_mode = 1
        # Hide: Big distance = long fade
        factor = rel_dist * 0.4 
        if factor > 0.9
            factor = 0.9
        endif
        if factor < 0.1
            factor = 0.1
        endif
    elsif overlap_mode = 2
        # Expose: Big distance = hard cut
        factor = 0.6 / rel_dist
        if factor > 0.9
            factor = 0.9
        endif
        if factor < 0.05
            factor = 0.05
        endif
    endif

    overlap_sec = next_dur * factor

    # === CRASH FIX: Protect against impossible overlap ===
    selectObject: result_id
    current_canon_dur = Get total duration

    # v0.5.0 fix 12: which sound bounds the overlap is a
    # compositional choice, not just a safety limit. Bounding by the
    # whole accumulated composite lets a long overlap reach back
    # across several earlier layers (the "accumulator" reading);
    # bounding by the previous variant keeps every transition a
    # strict two-sound crossfade.
    if overlap_span = 1
        span_dur = current_canon_dur
    else
        span_dur = prev_variant_dur
    endif

    # Cap overlap to 95% of the shortest involved sound segment
    limit_dur = min(span_dur, next_dur)

    if overlap_sec > limit_dur * 0.95
        overlap_sec = limit_dur * 0.95
    endif
    # ===================================================

    overlap_duration[i] = overlap_sec
    overlap_factor[i] = factor

    # v0.5.0 CRITICAL 2: `Concatenate with overlap` splices in OBJECT
    # LIST order, not selection order. Result is a Copy and therefore
    # sits at the BOTTOM of the list, while every variant was created
    # earlier and sits above it - so v0.4.2 produced next + Result on
    # every pass and rendered the whole path backwards. Copying the
    # next variant here places it below Result and restores the
    # intended order.
    selectObject: v_id'next_idx'
    Copy: "Next_Segment"
    next_copy = selected("Sound")

    selectObject: result_id
    plusObject: next_copy
    Concatenate with overlap: overlap_sec
    temp = selected("Sound")
    removeObject: result_id
    removeObject: next_copy
    result_id = temp
    prev_variant_dur = next_dur
endfor

appendInfoLine: "  Audible budget: ", fixed$(audible_accum, 2),
    ... " of ", fixed$(current_accum, 2), " conceptual units"
if skip_first and sel_count > 1
    appendInfoLine: "    (Skip_first: the transition into the first sounded"
    appendInfoLine: "     variant is part of the path but not of the audio)"
endif

selectObject: result_id
# v0.4.2: output filename now includes preset.
compositeName$ = user_name$ + "_canon_" + presetName$
Rename: compositeName$
final_name$ = selected$("Sound")

# Get final duration
final_duration = Get total duration

# ==============================================================================
# 7. VISUALIZATION
# ==============================================================================

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Original waveform              (left half, headline)
# Panel B: Canon waveform                 (right half, headline)
# Panel C: Dissimilarity trajectory       (left half, signature)
# Panel D: Variant transform scatter      (right half, signature)
# Panel E: Overlap analysis bars          (full width)
# Panel F: Light-grey 3-line summary      (suite standard)
###############################################################################

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 6.40
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    # v0.5.1: Praat reads "_" in drawn text as a subscript marker, so
    # "a_vox" printed as "a(sub v)ox" and the composite object name
    # "a_vox_canon_Custom" lost both underscores. Escape for display
    # only; the objects themselves are untouched.
    vizUserName$ = replace$(user_name$, "_", "\_ ", 0)
    vizCompositeName$ = replace$(compositeName$, "_", "\_ ", 0)

    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##GESTURAL ACCUMULATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizUserName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(n_variants) + " variants -> " + string$(sel_count) + " sel"
        ... + "  |  Pacing: " + pacing_curve$
        ... + "  |  Overlap: " + overlap_mode$ + " / " + overlap_span$

    # ----------------------------------------------------------
    # PANEL A (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.62, 2.10
    Select inner viewport: 0.60, 3.85, 0.77, 2.05

    selectObject: user_original_id
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform  (" + fixed$(original_duration, 2) + " s)"
    Font size: 7
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B (right): CANON WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.62, 2.10
    Select inner viewport: 4.45, 7.70, 0.77, 2.05

    selectObject: result_id
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Canon result  (" + fixed$(final_duration, 2) + " s,  " + fixed$(final_duration / original_duration, 1) + "x)"
    Font size: 7
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (left): DISSIMILARITY TRAJECTORY
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 2.20, 4.25
    Select inner viewport: 0.60, 3.85, 2.35, 3.95

    # Scale axis to the larger of (current_accum, max scheduled value)
    max_accum = current_accum
    for s from 1 to k_steps
        if sched_accum_'s' > max_accum
            max_accum = sched_accum_'s'
        endif
    endfor
    max_accum = max_accum * 1.1
    if max_accum < 0.01
        max_accum = 0.01
    endif

    Axes: 0, sel_count, 0, max_accum
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, sel_count, 0, max_accum

    # Target schedule (dotted grey)
    Colour: "{0.65, 0.65, 0.70}"
    Dotted line
    prev_sched = 0
    for s from 1 to k_steps
        if s <= sel_count
            Draw line: s - 1, prev_sched, s, sched_accum_'s'
            prev_sched = sched_accum_'s'
        endif
    endfor
    Solid line

    # Actual trajectory (red)
    Colour: "{0.90, 0.30, 0.30}"
    Line width: 2
    accum = 0
    Draw line: 0, 0, 1, 0
    for s from 2 to sel_count
        prev_accum = accum
        accum = accum + sel_dist_'s'
        Draw line: s - 1, prev_accum, s, accum
    endfor
    Line width: 1

    # Dots at each step
    accum = 0
    for s from 1 to sel_count
        if s > 1
            accum = accum + sel_dist_'s'
        endif
        Paint circle (mm): "{0.20, 0.50, 0.80}", s, accum, 1.0
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Dissimilarity trajectory  (grey dotted = target schedule)"
    Font size: 7
    Text left: "yes", "Cumulative (median units)"
    Text bottom: "yes", "Step"

    # ----------------------------------------------------------
    # PANEL D (right): VARIANT TRANSFORM SCATTER
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 2.20, 4.25
    Select inner viewport: 4.45, 7.70, 2.35, 3.95

    Axes: -pitch_range_st, pitch_range_st, 1.0 - formant_shift_range, 1.0 + formant_shift_range
    Paint rectangle: "{0.97, 0.97, 0.97}",
        ... -pitch_range_st, pitch_range_st, 1.0 - formant_shift_range, 1.0 + formant_shift_range

    # Reference cross (faint)
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: -pitch_range_st, 1.0, pitch_range_st, 1.0
    Draw line: 0, 1.0 - formant_shift_range, 0, 1.0 + formant_shift_range
    Solid line

    # All variants in grey
    for i to n_variants
        Paint circle (mm): "{0.80, 0.80, 0.80}",
            ... variant_pitch_shift[i], variant_formant_shift[i], 0.6
    endfor

    # Selected path connections (dotted, light)
    for s from 2 to sel_count
        prev_s = s - 1
        prev_idx = sel_idx_'prev_s'
        idx = sel_idx_'s'
        Colour: "{0.55, 0.55, 0.60}"
        Dotted line
        Draw line: variant_pitch_shift[prev_idx], variant_formant_shift[prev_idx],
            ... variant_pitch_shift[idx], variant_formant_shift[idx]
        Solid line
    endfor

    # Selected path dots (colored by sequence position)
    for s from 1 to sel_count
        idx = sel_idx_'s'
        hue = (s - 1) / max(sel_count - 1, 1)
        red = 0.20 + hue * 0.70
        green = 0.50
        blue = 0.90 - hue * 0.70
        dotColor$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
        Paint circle (mm): dotColor$,
            ... variant_pitch_shift[idx], variant_formant_shift[idx], 1.4
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Variant space  (grey = all, blue->red = selected path)"
    Font size: 7
    Text left: "yes", "Formant"
    Text bottom: "yes", "Pitch shift (st)"

    # ----------------------------------------------------------
    # PANEL E: OVERLAP ANALYSIS  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.35, 5.60
    Select inner viewport: 0.60, 7.70, 4.50, 5.30

    # v0.4.2 fix: gate on sel_count > start_pos (not sel_count > 1).
    # v0.4.1 had `if sel_count > 1` which entered the block when
    # skip_first=1 and sel_count=2 (start_pos=2), but the inner
    # loop `for i from start_pos+1 to sel_count` was a no-op and
    # max_overlap stayed at 0, producing Axes: 1, 2, 0, 0.
    if sel_count > start_pos
        max_overlap = 0
        for i from start_pos + 1 to sel_count
            if overlap_duration[i] > max_overlap
                max_overlap = overlap_duration[i]
            endif
        endfor
        if max_overlap < 0.001
            max_overlap = 0.001
        endif

        # v0.5.1: bars span i - 0.4 to i + 0.4 for i in
        # start_pos+1 .. sel_count, so the last bar reached
        # sel_count + 0.4 while the axis stopped at sel_count and
        # Praat does not clip -- the final bar was drawn straight
        # through the panel's right frame. Half a step of margin on
        # each side frames every bar.
        Axes: start_pos + 0.5, sel_count + 0.5, 0, max_overlap * 1.1
        Paint rectangle: "{0.97, 0.97, 0.97}",
            ... start_pos + 0.5, sel_count + 0.5, 0, max_overlap * 1.1

        for i from start_pos + 1 to sel_count
            norm = overlap_duration[i] / max(max_overlap, 0.001)
            if overlap_mode = 1
                # Hide: long = smooth (blue)
                barColor$ = "{" + fixed$(0.30 * (1 - norm), 2) + ", "
                    ... + fixed$(0.50, 2) + ", "
                    ... + fixed$(0.90 - 0.30 * (1 - norm), 2) + "}"
            else
                # Expose: short = harsh (red)
                barColor$ = "{" + fixed$(0.90 - 0.60 * norm, 2) + ", "
                    ... + fixed$(0.30 + 0.30 * norm, 2) + ", "
                    ... + fixed$(0.30 * norm, 2) + "}"
            endif
            Paint rectangle: barColor$, i - 0.4, i + 0.4, 0, overlap_duration[i]
        endfor

        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Transition overlaps  (color encodes overlap magnitude per " + overlap_mode$ + ")"
        Font size: 7
        Text left: "yes", "Overlap (s)"
        Text bottom: "yes", "Transition \# "
    else
        # Not enough transitions to plot
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.55, 0.55, 0.60}"
        Text: 0.5, "centre", 0.5, "half",
            ... "(no transitions to display: sel_count=" + string$(sel_count)
            ... + ", start_pos=" + string$(start_pos) + ")"
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Transition overlaps"
    endif

    # ----------------------------------------------------------
    # PANEL F: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    # v0.4.2 fix: explicit Axes: 0, 1, 0, 1 BEFORE any Text().
    # v0.4.1 inherited Axes from the panel above and placed text
    # at unpredictable outer y positions.
    Select outer viewport: 0, 8, 5.70, 6.40
    Select inner viewport: 0.60, 7.70, 5.75, 6.35
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"

    if track_motion_variance
        motionLabel$ = motion_measure$
    else
        motionLabel$ = "Off"
    endif

    if anchor_is_source
        anchorLabel$ = "source"
    else
        anchorLabel$ = "random"
    endif

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + vizUserName$
        ... + "  |  Variants: " + string$(n_variants) + " -> Selected: " + string$(sel_count)
        ... + "  |  Budget concept/audible/target: " + fixed$(current_accum, 2)
        ... + " / " + fixed$(audible_accum, 2) + " / " + fixed$(target_budget, 2)
        ... + " median units"

    Text: 0.02, "left", 0.50, "half",
        ... "Pacing: " + pacing_curve$
        ... + "  |  Overlap: " + overlap_mode$ + " / " + overlap_span$
        ... + "  |  Motion: " + motionLabel$
        ... + "  |  Pitch: +/-" + fixed$(pitch_range_st, 1) + " st"
        ... + "  |  Formant: +/-" + fixed$(formant_shift_range, 2)

    Text: 0.02, "left", 0.18, "half",
        ... "Obj: " + vizCompositeName$
        ... + "  |  Dur: " + fixed$(final_duration, 2) + " s ("
        ... + fixed$(final_duration / original_duration, 2) + "x)"
        ... + "  |  Med dist: " + fixed$(global_median_dist, 3)
        ... + "  |  Seed: " + string$(random_seed)
        ... + "  |  Anchor: " + anchorLabel$
        ... + "  |  Skip1st: " + string$(skip_first)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the full page as the last drawing action, so Save as PNG /
    # Copy to clipboard capture the whole figure rather than cropping to
    # the summary strip.
    Select outer viewport: 0, 8, 0, 6.40
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ==============================================================================
# 8. CLEANUP AND FINALIZE
# ==============================================================================

# Cleanup
for i from 1 to n_variants
    removeObject: v_id'i'
endfor
removeObject: work_id

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_duration, 2), " s (original: ", fixed$(original_duration, 2), " s)"
appendInfoLine: "Expansion factor: ", fixed$(final_duration / original_duration, 2), "x"

# === Play ===
if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    selectObject: result_id
    Play
endif

selectObject: result_id