# ============================================================
# Praat AudioTools - Concatenate_with_crossfade.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced concatenation with crossfade. Features:
#   - Chunk extraction modes (whole file / fixed / random duration)
#   - 5 crossfade types (linear, equal-power, S-curve, exp, log)
#   - 8 dynamic envelope modes (cresc, dim, swell, wave, etc.)
#   - Variable overlap modes (percentage / fixed / random)
#   - Order randomization with optional chunk-repetition
#   - 7 presets from Simple Crossfade to Granular Cloud
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.4 (2026):
#   - FIX: normalized the Exponential crossfade so fade-in is exactly
#     0 -> 1 and fade-out exactly 1 -> 0 over the overlap. The previous
#     exp(-4u) form stopped at approximately 0.0183 / 0.9817 and could
#     introduce a small boundary discontinuity when the crossfade ended.
#   - FIX: final Scale peak is now skipped for a fully silent output.
#   - FIX: Panel C now renders Random-per-segment / Terraced dynamics by
#     passing unit control signals carrying segAmp[] through the exact same
#     crossfade/overlap-add engine as the audio. The displayed curve therefore
#     includes the real crossfade blending in overlap regions instead of a
#     hard step chosen from whichever segment happened to be visited last.
#
# Changelog v1.3 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# Changelog v1.2 (structural audio-engine rewrite):
#
#   All items below were verified against real Praat behaviour using
#   synthetic constant-amplitude and stereo test signals (headless
#   Praat, `--run`), not just read from the source.
#
#   1. FIXED: double crossfade. v1.1 hand-applied a fade curve to the
#      tail of `result` and the head of `incoming`, and THEN called
#      `Concatenate with overlap`, which applies its own built-in
#      raised-cosine fade on top. Verified: crossfading two
#      constant-amplitude=1 signals with "Linear" dipped to ~0.50 at
#      the crossfade midpoint instead of staying at 1.0. v1.2 replaces
#      `Concatenate with overlap` entirely with a manual overlap-add
#      merge (`mixWithCrossfade`) built from a single `Create Sound
#      from formula` that time-samples the two already-faded buffers
#      via `object(id, time, channel)` and sums them. No implicit
#      window is ever applied. Re-verified: same test now holds at
#      1.0000 across the whole overlap for every point sampled.
#   2. FIXED: "Linear" wasn't linear. v1.1's linear branch called the
#      built-in `Fade in`/`Fade out`, which is a raised-cosine window,
#      not a straight ramp. v1.2 uses an explicit
#      `self * (x-t0)/dur` / `self * (1-(x-t0)/dur)` formula, verified
#      to be an exact straight line (see fix 1's test, which depends
#      on true linearity to sum to a flat 1.0).
#   3. FIXED: crossfade/dynamics formulas only touched channel 1.
#      Every `Formula (part): ..., 1, 1, ...` in v1.1 hard-coded the
#      channel range to a single channel. In a stereo file this left
#      the right channel with only the implicit `Concatenate with
#      overlap` window (see fix 1) and none of the selected curve, an
#      asymmetry between L/R. v1.2 queries `Get number of channels`
#      inside `applyCrossfade` and the dynamics formulas and always
#      spans `1, channels`. Verified with a stereo signal carrying
#      different constant values per channel that both channels track
#      independently and correctly through a merge.
#   4. FIXED: Random-per-segment / Terraced dynamics were multiplied
#      twice in every overlap region, because v1.1 applied `self *
#      amp` over each segment's [start, end] independently, and those
#      ranges overlap by design. v1.2 computes the per-position gain
#      table (`segAmp[]`) BEFORE the mixing loop and bakes each gain
#      into its chunk's buffer once, prior to crossfading; the
#      crossfade curve then blends between two already-correctly-
#      leveled buffers instead of ever being multiplied twice. This
#      also replaces the old ad hoc "transition zone" hack for mode 7
#      with the same crossfade engine used everywhere else. Verified:
#      pre-scaled buffers (0.4 -> 1.0) crossfade to an exact linear
#      ramp between the two gains, not a product of the two.
#   5. FIXED: no sampling-frequency check. v1.1 read the sampling
#      frequency of the first sound but never verified or converted
#      the others; `Concatenate`-family commands require matching
#      rates and mixed-rate input would fail outright. v1.2 resamples
#      any chunk whose rate differs from the first sound's rate
#      (`Resample...`) right after extraction, and reports it.
#   6. FIXED (by restricting scope, as the audit recommended): channel
#      standardization only ever handled mono<->stereo. Anything else
#      (4-channel material, mixed multichannel counts) silently
#      produced a wrong channel count while the info window falsely
#      reported "standardized". v1.2 explicitly validates that every
#      extracted chunk is mono or stereo and stops with a clear
#      `exitScript` message naming the offending file if not; the
#      mono<->stereo conversion itself is unchanged (it was correct).
#   7. FIXED: unsafe overlap-duration clamping. v1.1 clamped overlap
#      only against the incoming chunk's duration, then applied a flat
#      0.01s minimum AFTER that clamp -- so a 5ms chunk could get an
#      overlap longer than itself. v1.2's `calculateOverlap` clamps
#      against `min(0.9*incoming, 0.9*outgoing)` (both neighbours) and
#      derives the minimum as `min(0.01, capacity)`, so the floor can
#      never exceed the ceiling.
#   8. FIXED: Terraced dynamics divided by `numSteps - 1`, which is
#      zero whenever there is exactly one chunk in the whole output
#      (e.g. one Sound selected with Chunks_per_file = 1). v1.2 guards
#      this and assigns full level when there's only one step.
#   9. FIXED: chunk extraction assumed every source Sound's timebase
#      starts at 0. v1.1's `extractChunk` used `chunkStart = 0` /
#      `chunkEnd = totalDuration` in absolute time. For a source Sound
#      with a non-zero start time (e.g. itself extracted elsewhere
#      with "preserve times"), this silently requested a time range
#      outside the object's real domain. Verified: reproduced this
#      exactly against a source whose domain was [5, 8] -- the old
#      absolute-zero logic returned one second of pure digital silence
#      (RMS = 0) with no error or warning. v1.2 reads `Get start time`
#      / `Get end time` on the actual source and offsets from there.
#  10. FIXED: legend/segment-map colours could go outside Praat's
#      required 0-1 RGB range. `0.4 + 0.5*sin(...)` has range
#      [-0.1, 0.9], so a single-source run already produced a
#      slightly negative blue component, which can halt the script
#      after the audio has already been rendered. v1.2 clamps each
#      component to [0, 1].
#
#   Smaller fixes noted in the same audit:
#     - Min_chunk_duration_s / Max_chunk_duration_s and
#       Min_overlap_s / Max_overlap_s are now auto-swapped (with a
#       warning) if entered inverted, instead of silently misbehaving.
#     - Dynamics_depth_percent is clamped to [0, 100] (values above
#       100 previously flipped polarity via a negative minAmp).
#     - Scale_peak is clamped to (0, 1] (values above 1 previously
#       passed straight to `Scale peak`, inviting clipping on export).
#     - Presets 2-5 now explicitly reset Allow_repeats to 0, so a
#       manually-checked box no longer leaks into a preset that was
#       never meant to repeat chunks.
#     - "Simple Crossfade" now runs sequentially (Randomize_order = 0)
#       to match what its name promises; shuffling now starts at
#       "Smooth Collage" as the preset descriptions imply.
#     - Relabelled "Logarithmic (fast end)" -> "Logarithmic (fast
#       start)": the formula rises quickly and levels off, the same
#       qualitative shape as "Exponential (fast start)", so the old
#       label described the opposite of what the curve does.
#     - Softened "Equal-power (sqrt, no dip)" to "Equal-power (sqrt)",
#       since the no-dip property holds for uncorrelated sources, not
#       as a guarantee for every possible pair of input signals.
#
# ------------------------------------------------------------
# Changelog v1.1:
#
#   TIER 1 (Praat polish, no audio change):
#     - Dropped 7 decorative `comment === ... ===` form rows
#       (Preset / Chunk Extraction / Order / Crossfade Type /
#       Crossfade Duration / Dynamics / Output) plus 3 annotation
#       comments. Form: 30 rows -> 20 rows, fits ~20-row screen.
#     - Added colons to all 5 optionmenus (`Preset:`,
#       `Chunk_mode:`, `Crossfade_type:`, `Overlap_mode:`,
#       `Dynamics_mode:`).
#     - Visualization rewritten from custom 10-wide layout to
#       suite-styled 8-wide time-aligned stack:
#         Title bar (suite light) + metadata subtitle
#         Panel A (full width): result waveform + segment dividers
#         Panel B (full width): segment color map (time-aligned with A)
#         Panel C (full width): dynamics envelope (ALWAYS shown now,
#           even for "None" mode -- v1.0 left a gap)
#         Panel D (full width): file color legend with real names
#         Panel E (full width): light-grey 3-line summary
#       Departure from suite "side-by-side A/B" pattern: result
#       waveform and segment map share the same x-axis (time), so
#       stacking them lets the eye read top-to-bottom what each
#       chunk contributes to the audio at each moment.
#     - In-viz title: "##Concatenate with Crossfade v1.0## | ..."
#       -> "##CONCATENATE WITH CROSSFADE##" + metadata subtitle
#       (version belongs in the file header, not the canvas).
#     - Legend rewritten. v1.0 packed swatches at width 0.02 across
#       a 1-unit axis and only showed first 6 of N files; v1.1's
#       Panel D shows all N files with proper sized swatches and
#       truncated names.
#
#   TIER 2 (bug fixes, no audio change):
#     - FIXED: header clobbered by repeated `writeInfoLine`. v1.0
#       called `writeInfoLine` 7 times in the header block and
#       6 times in the settings block. Every `writeInfoLine` CLEARS
#       the info window first -- so only the LAST line of each
#       block survived. The header, version, file count, preset
#       name, and settings list were all wiped before display.
#       v1.1 calls `writeInfoLine` exactly once at the very top
#       (clearing intent), then `appendInfoLine` for every
#       subsequent line.
#     - FIXED: `chunk_mode$` undefined. Line 228 of v1.0 referenced
#       `chunk_mode$` (string) but only `chunk_mode` (integer
#       optionmenu) existed -- Praat displayed it as undefined /
#       empty. v1.1 defines `chunkModeName$` (e.g., "Whole file",
#       "Fixed (0.50s)", "Random (1.00-4.00s)") and an
#       `overlapModeName$` for the same reason.
#     - FIXED: dynamics envelope panel disappeared for "None".
#       v1.0's `if dynamics_mode > 1` skipped the entire dynamics
#       panel when None was selected, leaving a gap in the
#       visualization between the segment map and the legend.
#       v1.1 always draws Panel C, with a flat line at y=1 and
#       "None (flat envelope)" label for dynamics_mode=1.
#
#   TIER 3 (audio-changing -- intentional fixes):
#     - FIXED: Fisher-Yates shuffle was biased. v1.0 used:
#         for i to totalChunks
#             j = randomInteger(1, totalChunks)
#             swap chunkOrder[i] and chunkOrder[j]
#         endfor
#       This iterates n times (not n-1) with j drawn from 1..n
#       every iteration -- which does not produce a uniform
#       distribution over the n! permutations. Some orderings are
#       slightly more probable than 1/n!. v1.1 uses standard
#       ascending Fisher-Yates: `j = randomInteger(i, totalChunks)`
#       with `i` from 1 to totalChunks-1. Audio output for any
#       preset with randomize_order=1 will be different (different
#       chunk order) but the distribution is now uniform. Affected
#       presets: 2 SimpleCrossfade, 3 SmoothCollage, 4 RhythmicChop,
#       6 ChaosMix, 7 GranularCloud.
#     - IMPLEMENTED: `allow_repeats` form field. v1.0 had the field
#       and presets 6 ("Chaos Mix") and 7 ("Granular Cloud") set
#       it to 1, but no code ever read the value -- the field was
#       a no-op. v1.1 implements the intended semantics: when
#       randomize_order=1 AND allow_repeats=1, chunkOrder[] is
#       sampled with replacement from 1..totalChunks (same chunk
#       can appear multiple times in the output). Otherwise (the
#       default) Fisher-Yates is used as a no-repeat permutation.
#       Audio output for presets 6 and 7 is now different (the
#       same chunk may appear multiple times).
#
#       Note: allow_repeats only takes effect when randomize_order=1.
#       In sequential mode (randomize_order=0), chunkOrder stays at
#       the identity 1,2,...,n regardless of allow_repeats.
#
# Changelog v1.0:
#   - Initial release with chunk extraction modes, crossfade types,
#     dynamic envelopes, variable overlap, visualization, presets
# ============================================================

form Advanced Concatenate with Crossfade v1.4
    optionmenu Preset: 1
        option Custom (use settings below)
        option Simple Crossfade (25%)
        option Smooth Collage (random chunks, equal-power)
        option Rhythmic Chop (short fixed chunks)
        option Cinematic Swell (crescendo-diminuendo)
        option Chaos Mix (random everything)
        option Granular Cloud (tiny random chunks)
    optionmenu Chunk_mode: 1
        option Whole file (use entire sound)
        option Fixed chunk size
        option Random chunk size
    positive Fixed_chunk_duration_s 2.0
    positive Min_chunk_duration_s 0.5
    positive Max_chunk_duration_s 3.0
    natural Chunks_per_file 1
    boolean Randomize_order 1
    boolean Allow_repeats 0
    optionmenu Crossfade_type: 1
        option Linear (standard)
        option Equal-power (sqrt)
        option S-curve (cosine, smooth)
        option Exponential (fast start)
        option Logarithmic (fast start)
    optionmenu Overlap_mode: 1
        option Percentage of incoming chunk
        option Fixed duration
        option Random duration
    positive Overlap_percentage 25
    positive Fixed_overlap_s 0.5
    positive Min_overlap_s 0.1
    positive Max_overlap_s 1.0
    optionmenu Dynamics_mode: 1
        option None (flat)
        option Crescendo (fade in)
        option Diminuendo (fade out)
        option Swell (cresc-dim)
        option Inverse swell (dim-cresc)
        option Wave (sine modulation)
        option Random per segment
        option Terraced (stepped levels)
    positive Wave_cycles 2
    positive Dynamics_depth_percent 80
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === INPUT VALIDATION ===
n = numberOfSelected("Sound")
if n < 1
    exitScript: "Please select at least 1 Sound object"
endif

# Store sound IDs and get sample rate
for i to n
    sound[i] = selected("Sound", i)
endfor

selectObject: sound[1]
sr = Get sampling frequency

# === APPLY PRESETS ===
if preset = 2
    # Simple Crossfade
    chunk_mode = 1
    chunks_per_file = 1
    randomize_order = 0
    allow_repeats = 0
    crossfade_type = 1
    overlap_mode = 1
    overlap_percentage = 25
    dynamics_mode = 1
    presetName$ = "SimpleCrossfade"
elsif preset = 3
    # Smooth Collage
    chunk_mode = 3
    min_chunk_duration_s = 1.0
    max_chunk_duration_s = 4.0
    chunks_per_file = 2
    randomize_order = 1
    allow_repeats = 0
    crossfade_type = 2
    overlap_mode = 1
    overlap_percentage = 30
    dynamics_mode = 1
    presetName$ = "SmoothCollage"
elsif preset = 4
    # Rhythmic Chop
    chunk_mode = 2
    fixed_chunk_duration_s = 0.5
    chunks_per_file = 3
    randomize_order = 1
    allow_repeats = 0
    crossfade_type = 1
    overlap_mode = 2
    fixed_overlap_s = 0.05
    dynamics_mode = 1
    presetName$ = "RhythmicChop"
elsif preset = 5
    # Cinematic Swell
    chunk_mode = 1
    chunks_per_file = 1
    randomize_order = 0
    allow_repeats = 0
    crossfade_type = 3
    overlap_mode = 1
    overlap_percentage = 20
    dynamics_mode = 4
    dynamics_depth_percent = 90
    presetName$ = "CinematicSwell"
elsif preset = 6
    # Chaos Mix
    chunk_mode = 3
    min_chunk_duration_s = 0.3
    max_chunk_duration_s = 2.5
    chunks_per_file = 3
    randomize_order = 1
    allow_repeats = 1
    crossfade_type = 3
    overlap_mode = 3
    min_overlap_s = 0.05
    max_overlap_s = 0.8
    dynamics_mode = 7
    dynamics_depth_percent = 60
    presetName$ = "ChaosMix"
elsif preset = 7
    # Granular Cloud
    chunk_mode = 3
    min_chunk_duration_s = 0.05
    max_chunk_duration_s = 0.3
    chunks_per_file = 10
    randomize_order = 1
    allow_repeats = 1
    crossfade_type = 2
    overlap_mode = 1
    overlap_percentage = 50
    dynamics_mode = 6
    wave_cycles = 3
    dynamics_depth_percent = 50
    presetName$ = "GranularCloud"
else
    presetName$ = "Custom"
endif

# === VALIDATE / SANITIZE NUMERIC SETTINGS ===
# v1.2: guard against inverted ranges and out-of-range percentages that
# previously caused silent misbehaviour (negative gains, inverted
# clamps, etc. -- see changelog fixes for Dynamics_depth_percent,
# Scale_peak, Min/Max duration and overlap).
rangeWarning$ = ""

if min_chunk_duration_s > max_chunk_duration_s
    temp = min_chunk_duration_s
    min_chunk_duration_s = max_chunk_duration_s
    max_chunk_duration_s = temp
    rangeWarning$ = rangeWarning$ + "  - Min/Max chunk duration were swapped (min was greater than max)." + newline$
endif

if min_overlap_s > max_overlap_s
    temp = min_overlap_s
    min_overlap_s = max_overlap_s
    max_overlap_s = temp
    rangeWarning$ = rangeWarning$ + "  - Min/Max overlap were swapped (min was greater than max)." + newline$
endif

if dynamics_depth_percent > 100
    dynamics_depth_percent = 100
    rangeWarning$ = rangeWarning$ + "  - Dynamics_depth_percent was above 100 and has been clamped to 100." + newline$
elsif dynamics_depth_percent < 0
    dynamics_depth_percent = 0
    rangeWarning$ = rangeWarning$ + "  - Dynamics_depth_percent was negative and has been clamped to 0." + newline$
endif

if scale_peak > 1
    scale_peak = 1
    rangeWarning$ = rangeWarning$ + "  - Scale_peak was above 1 and has been clamped to 1 (avoids clipping)." + newline$
endif

# === RESOLVE NAMES FOR DISPLAY ===
# v1.1: define chunkModeName$ (fixes the chunk_mode$ undefined bug at
# line 228 of v1.0) and overlapModeName$ for full info output.
if chunk_mode = 1
    chunkModeName$ = "Whole file"
elsif chunk_mode = 2
    chunkModeName$ = "Fixed (" + fixed$(fixed_chunk_duration_s, 2) + " s)"
else
    chunkModeName$ = "Random (" + fixed$(min_chunk_duration_s, 2) + "-" + fixed$(max_chunk_duration_s, 2) + " s)"
endif

if overlap_mode = 1
    overlapModeName$ = "Percentage (" + fixed$(overlap_percentage, 0) + "%)"
elsif overlap_mode = 2
    overlapModeName$ = "Fixed (" + fixed$(fixed_overlap_s, 3) + " s)"
else
    overlapModeName$ = "Random (" + fixed$(min_overlap_s, 3) + "-" + fixed$(max_overlap_s, 3) + " s)"
endif

# Crossfade type name
if crossfade_type = 1
    crossfadeTypeName$ = "Linear"
elsif crossfade_type = 2
    crossfadeTypeName$ = "Equal-power"
elsif crossfade_type = 3
    crossfadeTypeName$ = "S-curve"
elsif crossfade_type = 4
    crossfadeTypeName$ = "Exponential"
else
    crossfadeTypeName$ = "Logarithmic"
endif

# Dynamics mode name
if dynamics_mode = 1
    dynamicsName$ = "None"
elsif dynamics_mode = 2
    dynamicsName$ = "Crescendo"
elsif dynamics_mode = 3
    dynamicsName$ = "Diminuendo"
elsif dynamics_mode = 4
    dynamicsName$ = "Swell"
elsif dynamics_mode = 5
    dynamicsName$ = "Inverse Swell"
elsif dynamics_mode = 6
    dynamicsName$ = "Wave"
elsif dynamics_mode = 7
    dynamicsName$ = "Random"
else
    dynamicsName$ = "Terraced"
endif

# === INFO HEADER ===
# v1.1: ONLY ONE writeInfoLine at the very top -- everything else uses
# appendInfoLine. v1.0 called writeInfoLine 7 times in this block and
# 6 more in the settings block, with each call clearing the info window,
# wiping the header before the user could see it.
writeInfoLine: "=== ADVANCED CONCATENATE WITH CROSSFADE v1.4 ==="
appendInfoLine: ""
appendInfoLine: "Input sounds:    ", n
appendInfoLine: "Preset:          ", presetName$
appendInfoLine: "Chunk mode:      ", chunkModeName$
appendInfoLine: "Chunks per file: ", chunks_per_file
appendInfoLine: "Randomize:       ", randomize_order, "   Allow repeats: ", allow_repeats
appendInfoLine: "Crossfade type:  ", crossfadeTypeName$
appendInfoLine: "Overlap mode:    ", overlapModeName$
appendInfoLine: "Dynamics:        ", dynamicsName$
if rangeWarning$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Settings adjusted:"
    appendInfoLine: rangeWarning$
endif
appendInfoLine: ""

# ============================================================
# PROCEDURE: Extract chunk from sound
# ============================================================
# v1.2: uses the source sound's ACTUAL start/end time instead of
# assuming it starts at 0 (see changelog fix 9). Sounds extracted
# elsewhere with "preserve times" can have a non-zero start time;
# the old absolute-zero logic could silently request a time range
# outside the object's domain and return silence with no warning.

procedure extractChunk: .sound, .mode, .fixedDur, .minDur, .maxDur
    selectObject: .sound
    .tmin = Get start time
    .tmax = Get end time
    .totalDur = .tmax - .tmin

    if .mode = 1
        # Whole file
        .chunkStart = .tmin
        .chunkEnd = .tmax
    elsif .mode = 2
        # Fixed chunk
        .chunkDur = min(.fixedDur, .totalDur)
        .maxOffset = .totalDur - .chunkDur
        if .maxOffset > 0
            .offset = randomUniform(0, .maxOffset)
        else
            .offset = 0
        endif
        .chunkStart = .tmin + .offset
        .chunkEnd = .chunkStart + .chunkDur
    else
        # Random chunk
        .chunkDur = randomUniform(.minDur, .maxDur)
        .chunkDur = min(.chunkDur, .totalDur)
        .maxOffset = .totalDur - .chunkDur
        if .maxOffset > 0
            .offset = randomUniform(0, .maxOffset)
        else
            .offset = 0
        endif
        .chunkStart = .tmin + .offset
        .chunkEnd = .chunkStart + .chunkDur
    endif

    selectObject: .sound
    .chunk = Extract part: .chunkStart, .chunkEnd, "rectangular", 1, "no"

    extractChunk.result = .chunk
    extractChunk.duration = .chunkEnd - .chunkStart
    extractChunk.start = .chunkStart
    extractChunk.end = .chunkEnd
endproc


# ============================================================
# PROCEDURE: Apply custom crossfade
# ============================================================
# v1.2: (a) Linear is now a real explicit ramp instead of Praat's
# built-in raised-cosine `Fade in`/`Fade out` (changelog fix 2).
# (b) every formula now spans ALL channels (`1, .channels`) instead
# of being hard-coded to channel 1 only (changelog fix 3).

procedure applyCrossfade: .sound, .fadeType, .duration, .direction$
    # .direction$ = "in" or "out"
    # .fadeType: 1=linear, 2=equal-power, 3=S-curve, 4=exp, 5=log

    selectObject: .sound
    .totalDur = Get total duration
    .channels = Get number of channels

    if .direction$ = "in"
        .startTime = 0
        .endTime = .duration
    else
        .startTime = .totalDur - .duration
        .endTime = .totalDur
    endif

    # Clamp times
    if .startTime < 0
        .startTime = 0
    endif
    if .endTime > .totalDur
        .endTime = .totalDur
    endif

    .fadeDur = .endTime - .startTime
    if .fadeDur < 0.001
        # Skip if too short
    else
        selectObject: .sound

        if .fadeType = 1
            # True linear ramp (explicit formula -- NOT Praat's built-in
            # Fade in/out, which is a raised-cosine window)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * ((x - .startTime) / .fadeDur)
            else
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * (1 - (x - .startTime) / .fadeDur)
            endif

        elsif .fadeType = 2
            # Equal-power (sqrt curve) - avoids a power dip at the
            # crossfade center for uncorrelated sources
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * sqrt((x - .startTime) / .fadeDur)
            else
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * sqrt(1 - (x - .startTime) / .fadeDur)
            endif

        elsif .fadeType = 3
            # S-curve (cosine) - very smooth
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * (0.5 - 0.5 * cos(pi * (x - .startTime) / .fadeDur))
            else
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * (0.5 + 0.5 * cos(pi * (x - .startTime) / .fadeDur))
            endif

        elsif .fadeType = 4
            # Exponential, normalized to exact endpoints. Let u run from 0 to 1:
            #   fadeIn  = (1-exp(-4u)) / (1-exp(-4))
            #   fadeOut = 1-fadeIn
            # This keeps the requested fast-start curvature while guaranteeing
            # 0/1 at the overlap boundaries (v1.4).
            .expEnd = exp(-4)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * ((1 - exp(-4 * (x - .startTime) / .fadeDur)) / (1 - .expEnd))
            else
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * ((exp(-4 * (x - .startTime) / .fadeDur) - .expEnd) / (1 - .expEnd))
            endif

        else
            # Logarithmic (also fast-start/slow-end in shape, but a
            # different curvature than Exponential -- see relabeling
            # in the v1.2 changelog)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * (ln(1 + 9 * (x - .startTime) / .fadeDur) / ln(10))
            else
                Formula (part): .startTime, .endTime, 1, .channels, ~ self * (1 - ln(1 + 9 * (x - .startTime) / .fadeDur) / ln(10))
            endif
        endif
    endif
endproc


# ============================================================
# PROCEDURE: Calculate overlap time
# ============================================================
# v1.2: now takes BOTH the incoming and outgoing chunk duration and
# clamps to 90% of whichever is smaller (changelog fix 7). The old
# version only checked the incoming chunk, so a short outgoing chunk
# could get an overlap that reached back past its own start. The
# minimum overlap is now `min(0.01, capacity)`, so the floor can never
# be raised above whatever ceiling was just computed (the old order of
# operations could push a clamped-down overlap back up past the chunk
# it was just clamped to fit inside).

procedure calculateOverlap: .incomingDur, .outgoingDur, .mode, .percentage, .fixedDur, .minDur, .maxDur
    if .mode = 1
        # Percentage of incoming chunk
        .requested = .incomingDur * .percentage / 100
    elsif .mode = 2
        # Fixed duration
        .requested = .fixedDur
    else
        # Random duration
        .requested = randomUniform(.minDur, .maxDur)
    endif

    # Capacity: never exceed 90% of either neighbour
    .capacity = min(0.9 * .incomingDur, 0.9 * .outgoingDur)
    if .capacity < 0
        .capacity = 0
    endif

    .time = .requested
    if .time > .capacity
        .time = .capacity
    endif

    # Minimum overlap, but never above the capacity we just enforced
    .minAllowed = min(0.01, .capacity)
    if .time < .minAllowed
        .time = .minAllowed
    endif
endproc


# ============================================================
# PROCEDURE: Mix two sounds with a crossfade (overlap-add)
# ============================================================
# v1.2 NEW: replaces the v1.1 sequence of (hand-applied fade + built-in
# `Concatenate with overlap`), which double-applied a window (changelog
# fix 1). This procedure fades the tail of .resultIn and the head of
# .incomingIn using the SAME curve (via applyCrossfade, exactly once
# each), then builds the merged sound directly with a single
# `Create Sound from formula` that time-samples both buffers with
# `object(id, time, channel)` and sums them. No other command touches
# the samples, so no implicit window is ever added on top.
#
# Both .resultIn and .incomingIn are consumed (their samples are
# modified in place by the fades); the caller is responsible for
# removing them after reading mixWithCrossfade.result.

procedure mixWithCrossfade: .resultIn, .incomingIn, .overlapTime, .fadeType
    selectObject: .resultIn
    .resultDur = Get total duration
    .channels = Get number of channels
    .sr = Get sampling frequency

    selectObject: .incomingIn
    .incomingDur = Get total duration

    @applyCrossfade: .resultIn, .fadeType, .overlapTime, "out"
    @applyCrossfade: .incomingIn, .fadeType, .overlapTime, "in"

    .totalDur = .resultDur + .incomingDur - .overlapTime
    .boundary = .resultDur - .overlapTime

    .merged = Create Sound from formula: "crossfaded_temp", .channels, 0, .totalDur, .sr,
        ... ~ (if x < .resultDur then object(.resultIn, x, row) else 0 fi)
        ... + (if x >= .boundary and x < .totalDur then object(.incomingIn, x - .boundary, row) else 0 fi)

    mixWithCrossfade.result = .merged
endproc


# ============================================================
# EXTRACT CHUNKS, CHECK SAMPLE RATE, STANDARDIZE CHANNELS
# ============================================================

appendInfoLine: "Extracting chunks..."

totalChunks = 0

for i to n
    selectObject: sound[i]
    soundName$[i] = selected$("Sound")

    for j to chunks_per_file
        totalChunks += 1

        # Extract chunk
        @extractChunk: sound[i], chunk_mode, fixed_chunk_duration_s, min_chunk_duration_s, max_chunk_duration_s
        chunk[totalChunks] = extractChunk.result

        # Store metadata
        chunkSource[totalChunks] = i

        selectObject: chunk[totalChunks]
        chunkDur[totalChunks] = Get total duration
        chunkChan[totalChunks] = Get number of channels
        chunkRate[totalChunks] = Get sampling frequency

        appendInfoLine: "  Chunk ", totalChunks, " from ", soundName$[i], " (", fixed$(chunkDur[totalChunks], 2), "s, ", chunkChan[totalChunks], "ch, ", fixed$(chunkRate[totalChunks]/1000, 1), "kHz)"
    endfor
endfor

# CHECK SAMPLING FREQUENCY - resample any chunk that doesn't match the
# first sound's rate. v1.2: `Concatenate`-family commands require a
# common sampling frequency across all inputs; v1.1 never checked this,
# so mixed-rate input would fail with no clear explanation. (fix 5)
resampledAny = 0
for i to totalChunks
    if chunkRate[i] <> sr
        if resampledAny = 0
            appendInfoLine: ""
            appendInfoLine: "Sampling frequency mismatch detected -- resampling to ", fixed$(sr/1000, 1), " kHz (from first sound)..."
        endif
        selectObject: chunk[i]
        resampledChunk = Resample: sr, 50
        removeObject: chunk[i]
        chunk[i] = resampledChunk
        chunkRate[i] = sr
        appendInfoLine: "  Resampled chunk ", i
        resampledAny = 1
    endif
endfor

# CHECK CHANNEL COUNTS - v1.2 officially supports mono and stereo only
# (fix 6). Anything else previously produced a wrong channel count
# while claiming success; now it stops with a clear message.
for i to totalChunks
    if chunkChan[i] <> 1 and chunkChan[i] <> 2
        exitScript: "Chunk ", i, " (from ", soundName$[chunkSource[i]], ") has ", chunkChan[i],
            ... " channels. This script only supports mono or stereo sounds."
    endif
endfor

# STANDARDIZE CHANNELS - Convert all to match first chunk (mono<->stereo only)
selectObject: chunk[1]
targetChannels = Get number of channels

appendInfoLine: ""
appendInfoLine: "Standardizing channels to ", targetChannels, "..."

for i from 2 to totalChunks
    selectObject: chunk[i]
    currentChannels = Get number of channels

    if currentChannels <> targetChannels
        if targetChannels = 1
            # Convert to mono
            Convert to mono
            monoChunk = selected("Sound")
            removeObject: chunk[i]
            chunk[i] = monoChunk
            appendInfoLine: "  Converted chunk ", i, " to mono"
        elsif currentChannels = 1
            # Convert mono to stereo by duplicating
            Copy: "temp"
            tempChunk = selected("Sound")
            selectObject: chunk[i]
            plusObject: tempChunk
            Combine to stereo
            stereoChunk = selected("Sound")
            removeObject: chunk[i], tempChunk
            chunk[i] = stereoChunk
            appendInfoLine: "  Converted chunk ", i, " to stereo"
        endif
    endif
endfor

appendInfoLine: "  All chunks standardized to ", targetChannels, " channel(s)"

# ============================================================
# DETERMINE PLAYBACK ORDER
# ============================================================
# (unchanged from v1.1 -- Fisher-Yates shuffle and allow_repeats were
# already verified correct in that pass)

# Initialize identity order (used directly when randomize_order=0)
for i to totalChunks
    chunkOrder[i] = i
endfor

if randomize_order
    if allow_repeats
        # Sample with replacement: each slot independently picks from 1..N
        appendInfoLine: "Order: random WITH repeats"
        for i to totalChunks
            chunkOrder[i] = randomInteger(1, totalChunks)
        endfor
    else
        # Standard ascending Fisher-Yates: for i = 1..n-1, pick j in [i, n]
        # and swap.
        appendInfoLine: "Order: random, no repeats (Fisher-Yates)"
        for i from 1 to totalChunks - 1
            j = randomInteger(i, totalChunks)
            temp = chunkOrder[i]
            chunkOrder[i] = chunkOrder[j]
            chunkOrder[j] = temp
        endfor
    endif
else
    appendInfoLine: "Order: sequential (extraction order)"
endif

# ============================================================
# PRE-COMPUTE PER-POSITION GAIN FOR RANDOM / TERRACED DYNAMICS
# ============================================================
# v1.2 NEW: for dynamics_mode 7 (Random per segment) and 8 (Terraced),
# the target gain for each OUTPUT POSITION is now computed here, before
# any mixing happens, and applied to each chunk's buffer exactly once
# in the mixing loop below (see changelog fix 4). This replaces the
# v1.1 approach of multiplying `self * amp` over each segment's time
# range AFTER concatenation, which double-multiplied every overlap
# region because those ranges overlap by design.

if dynamics_mode = 7 or dynamics_mode = 8
    depth = dynamics_depth_percent / 100
    minAmp = 1 - depth

    if dynamics_mode = 7
        # Random per segment
        for seg to totalChunks
            segAmp[seg] = randomUniform(minAmp, 1)
        endfor
    else
        # Terraced (stepped levels)
        numSteps = min(totalChunks, 5)
        for seg to totalChunks
            stepNum = ((seg - 1) mod numSteps) + 1
            if numSteps > 1
                segAmp[seg] = minAmp + (1 - minAmp) * (stepNum - 1) / (numSteps - 1)
            else
                # Only one step possible (e.g. a single chunk total) --
                # avoids the numSteps-1 = 0 division in v1.1.
                segAmp[seg] = 1
            endif
        endfor
    endif
endif

# ============================================================
# CONCATENATE WITH CROSSFADE
# ============================================================

appendInfoLine: ""
appendInfoLine: "Concatenating with crossfade..."

# Start with first chunk
firstIdx = chunkOrder[1]
selectObject: chunk[firstIdx]
result = Copy: "crossfaded_temp"

dynamicsViz = 0
if dynamics_mode = 7 or dynamics_mode = 8
    selectObject: result
    Formula: ~ self * segAmp[1]

    if draw_visualization
        # v1.4: build a one-channel control signal in parallel with the audio.
        # Each chunk contributes its segAmp[] value and is merged with the exact
        # same crossfade type / overlap as the real sound, so Panel C can show the
        # actual combined gain coefficients through overlap regions.
        dynamicsViz = Create Sound from formula: "dynamics_viz", 1, 0, chunkDur[firstIdx], sr, string$(segAmp[1])
    endif
endif

# Track segment positions for dynamics / visualization
segmentStart[1] = 0
segmentEnd[1] = chunkDur[firstIdx]
segmentDur[1] = chunkDur[firstIdx]

totalOverlapTime = 0

for i from 2 to totalChunks
    currentIdx = chunkOrder[i]
    currentDur = chunkDur[currentIdx]
    previousIdx = chunkOrder[i - 1]
    outgoingDur = chunkDur[previousIdx]

    # Calculate overlap time (clamped against BOTH neighbours -- fix 7)
    @calculateOverlap: currentDur, outgoingDur, overlap_mode, overlap_percentage, fixed_overlap_s, min_overlap_s, max_overlap_s
    overlapTime = calculateOverlap.time

    totalOverlapTime = totalOverlapTime + overlapTime

    # Copy incoming chunk (fresh copy so chunk[currentIdx] stays intact,
    # which matters when allow_repeats lets us revisit the same chunk).
    selectObject: chunk[currentIdx]
    incoming = Copy: "temp_incoming"

    # Bake in this position's target gain BEFORE crossfading, so the
    # overlap region blends between two already-correctly-leveled
    # buffers instead of being multiplied twice (fix 4).
    if dynamics_mode = 7 or dynamics_mode = 8
        selectObject: incoming
        Formula: ~ self * segAmp[i]
    endif

    selectObject: result
    result_duration = Get total duration

    # Merge via manual overlap-add (fix 1 + fix 2 + fix 3) instead of
    # fade + `Concatenate with overlap`.
    @mixWithCrossfade: result, incoming, overlapTime, crossfade_type
    new_result = mixWithCrossfade.result

    if (dynamics_mode = 7 or dynamics_mode = 8) and draw_visualization
        dynIncoming = Create Sound from formula: "dynamics_incoming", 1, 0, currentDur, sr, string$(segAmp[i])
        @mixWithCrossfade: dynamicsViz, dynIncoming, overlapTime, crossfade_type
        newDynamicsViz = mixWithCrossfade.result
        removeObject: dynamicsViz, dynIncoming
        dynamicsViz = newDynamicsViz
        Rename: "dynamics_viz"
    endif

    # Track segment position
    segmentStart[i] = result_duration - overlapTime
    selectObject: new_result
    segmentEnd[i] = Get total duration
    segmentDur[i] = segmentEnd[i] - segmentStart[i]

    # Clean up
    removeObject: result, incoming
    result = new_result

    appendInfoLine: "  Added chunk ", i, "/", totalChunks, " (overlap: ", fixed$(overlapTime, 3), "s)"
endfor

selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "Concatenation complete"
appendInfoLine: "  Total duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "  Total overlap:  ", fixed$(totalOverlapTime, 2), " s"

# ============================================================
# APPLY DYNAMICS ENVELOPE
# ============================================================
# v1.2: modes 7 (Random) and 8 (Terraced) are now baked in already
# (see pre-compute block above and the mixing loop), so this section
# only needs to handle the continuous, whole-signal envelopes
# (Crescendo / Diminuendo / Swell / Inverse swell / Wave). Those were
# already correct in v1.1 -- each is a single Formula applied once
# across the entire result, with no overlapping ranges -- but now also
# spans all channels (fix 3) instead of channel 1 only.

if dynamics_mode > 1 and dynamics_mode < 7
    appendInfoLine: ""
    appendInfoLine: "Applying dynamics: ", dynamicsName$, "..."

    selectObject: result
    channels = Get number of channels
    depth = dynamics_depth_percent / 100
    minAmp = 1 - depth

    if dynamics_mode = 2
        # Crescendo (fade in over entire duration)
        Formula: ~ self * (minAmp + (1 - minAmp) * x / finalDuration)

    elsif dynamics_mode = 3
        # Diminuendo (fade out over entire duration)
        Formula: ~ self * (1 - (1 - minAmp) * x / finalDuration)

    elsif dynamics_mode = 4
        # Swell (crescendo to middle, then diminuendo)
        Formula: ~ self * (minAmp + (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1)))

    elsif dynamics_mode = 5
        # Inverse swell (diminuendo to middle, then crescendo)
        Formula: ~ self * (1 - (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1)))

    elsif dynamics_mode = 6
        # Wave (sine modulation)
        Formula: ~ self * (minAmp + (1 - minAmp) * (0.5 + 0.5 * sin(2 * pi * wave_cycles * x / finalDuration - pi/2)))
    endif

    appendInfoLine: "  Dynamics applied (depth: ", fixed$(dynamics_depth_percent, 0), "%)"
elsif dynamics_mode = 7 or dynamics_mode = 8
    appendInfoLine: ""
    appendInfoLine: "  Dynamics (", dynamicsName$, ") already applied during mixing (depth: ", fixed$(dynamics_depth_percent, 0), "%)"
endif

# ============================================================
# FINAL PROCESSING
# ============================================================

selectObject: result
preScalePeak = Get absolute extremum: 0, 0, "Sinc70"
if preScalePeak > 0
    Scale peak: scale_peak
else
    appendInfoLine: "Output is silent; final peak scaling skipped."
endif
compositeName$ = "concat_crossfade_" + presetName$
Rename: compositeName$

# Get output stats for summary
selectObject: result
rms_out = Get root-mean-square: 0, 0

###############################################################################
# VISUALIZATION  (8-wide time-aligned stack with suite styling)
# Title
# Panel A: result waveform + segment dividers
# Panel B: segment color map (time-aligned with A)
# Panel C: dynamics envelope (ALWAYS shown now, even for "None")
# Panel D: file color legend with real names
# Panel E: light-grey 3-line summary bar
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."

    Erase all
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Concatenate with Crossfade v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", presetName$ + " | " + string$(n) + " files | " + string$(totalChunks) + " chunks | " + crossfadeTypeName$ + " | " + dynamicsName$

    # PANEL A: RESULT WAVEFORM + SEGMENT DIVIDERS  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 3.10
    Select inner viewport: 0.55, 7.72, 0.90, 2.95

    selectObject: result
    Colour: "{0.30, 0.50, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Segment dividers (vertical dashed lines at each segment start except the first)
    Colour: "{0.80, 0.30, 0.30}"
    Line width: 1
    Dashed line
    for seg from 2 to totalChunks
        xPos = segmentStart[seg]
        Draw line: xPos, -1, xPos, 1
    endfor
    Solid line

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Result waveform with segment boundaries  (" + fixed$(finalDuration, 2) + " s,  " + string$(totalChunks) + " chunks)"
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL B: SEGMENT COLOR MAP  (full width, time-aligned with A)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.18, 4.10
    Select inner viewport: 0.55, 7.72, 3.28, 4.02

    Axes: 0, finalDuration, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDuration, 0, 1

    for seg to totalChunks
        sStart = segmentStart[seg]
        sEnd = segmentEnd[seg]
        sourceIdx = chunkSource[chunkOrder[seg]]

        # Color based on source file (hue = (i-1)/n, no wrap collision)
        # v1.2: clamped to [0,1] -- the raw sin-based formula has range
        # [-0.1, 0.9], which could already go negative with a single
        # source and halt the script after the audio had rendered (fix 10).
        hue = (sourceIdx - 1) / n
        r = min(1, max(0, 0.4 + 0.5 * sin(2 * pi * hue)))
        g = min(1, max(0, 0.4 + 0.5 * sin(2 * pi * hue + 2 * pi / 3)))
        b = min(1, max(0, 0.4 + 0.5 * sin(2 * pi * hue + 4 * pi / 3)))

        colour$ = "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}"
        Paint rectangle: colour$, sStart, sEnd, 0.1, 0.9

        # Segment number (only if segment is wide enough to fit text)
        if sEnd - sStart > finalDuration * 0.03
            Colour: "White"
            Font size: 6
            midX = (sStart + sEnd) / 2
            Text: midX, "centre", 0.5, "half", string$(seg)
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Segment map  (color = source file,  number = playback order)"
    Text left: "yes", "Source"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL C: DYNAMICS ENVELOPE  (full width, ALWAYS shown)
    # ----------------------------------------------------------
    # v1.1: always drawn -- even for dynamics_mode=1 ("None") we
    # show a flat line at y=1 so the layout doesn't gap.
    Select outer viewport: 0, 8, 4.18, 5.30
    Select inner viewport: 0.55, 7.72, 4.30, 5.20

    dynYmax = 1.3
    if dynamics_mode = 7 or dynamics_mode = 8
        selectObject: dynamicsViz
        dynVizMax = Get maximum: 0, 0, "None"
        if dynVizMax * 1.08 > dynYmax
            dynYmax = dynVizMax * 1.08
        endif
    endif

    Axes: 0, finalDuration, 0, dynYmax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDuration, 0, dynYmax

    # Unity reference dashed
    Colour: "{0.65, 0.65, 0.70}"
    Line width: 1
    Dotted line
    Draw line: 0, 1, finalDuration, 1
    Solid line

    if dynamics_mode = 7 or dynamics_mode = 8
        # v1.4: this control signal was assembled with the same overlap-add
        # crossfades as the audio, so transitions show the real blended gain
        # coefficients rather than hard segment steps. Equal-power fades may
        # legitimately rise above 1 because the two amplitude weights sum to
        # more than unity in the overlap.
        selectObject: dynamicsViz
        Colour: "{0.80, 0.42, 0.22}"
        Line width: 2
        Draw: 0, finalDuration, 0, dynYmax, "no", "Curve"
        envelopeLabel$ = dynamicsName$ + "  (crossfade-blended; depth: " + fixed$(dynamics_depth_percent, 0) + "%)"

    elsif dynamics_mode > 1
        # Continuous whole-output dynamics modes.
        Colour: "{0.80, 0.42, 0.22}"
        Line width: 2

        minAmp = 1 - dynamics_depth_percent / 100
        numPoints = 200
        step = finalDuration / numPoints

        prevX = 0
        if dynamics_mode = 2
            prevY = minAmp
        elsif dynamics_mode = 3
            prevY = 1
        elsif dynamics_mode = 4
            prevY = minAmp
        elsif dynamics_mode = 5
            prevY = 1
        elsif dynamics_mode = 6
            prevY = minAmp
        else
            prevY = 1
        endif

        for pt from 1 to numPoints
            x = pt * step

            if dynamics_mode = 2
                y = minAmp + (1 - minAmp) * x / finalDuration
            elsif dynamics_mode = 3
                y = 1 - (1 - minAmp) * x / finalDuration
            elsif dynamics_mode = 4
                y = minAmp + (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1))
            elsif dynamics_mode = 5
                y = 1 - (1 - minAmp) * (1 - abs(2 * x / finalDuration - 1))
            elsif dynamics_mode = 6
                y = minAmp + (1 - minAmp) * (0.5 + 0.5 * sin(2 * pi * wave_cycles * x / finalDuration - pi/2))
            else
                y = 1
            endif

            Draw line: prevX, prevY, x, y
            prevX = x
            prevY = y
        endfor

        envelopeLabel$ = dynamicsName$ + "  (depth: " + fixed$(dynamics_depth_percent, 0) + "%)"
    else
        # None: draw a flat line at y=1
        Colour: "{0.55, 0.55, 0.62}"
        Line width: 2
        Draw line: 0, 1, finalDuration, 1
        envelopeLabel$ = "None  (flat envelope)"
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Dynamics envelope:  " + envelopeLabel$
    Text left: "yes", "Level"

    # ----------------------------------------------------------
    # PANEL D: FILE COLOR LEGEND  (full width, all N files)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.38, 6.30
    Select inner viewport: 0.55, 7.72, 5.50, 6.22

    Axes: 0, n, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, n, 0, 1

    for i to n
        hue = (i - 1) / n
        # v1.2: clamped to [0,1] -- see Panel B note above (fix 10).
        r = min(1, max(0, 0.4 + 0.5 * sin(2 * pi * hue)))
        g = min(1, max(0, 0.4 + 0.5 * sin(2 * pi * hue + 2 * pi / 3)))
        b = min(1, max(0, 0.4 + 0.5 * sin(2 * pi * hue + 4 * pi / 3)))
        colour$ = "{" + fixed$(r, 2) + "," + fixed$(g, 2) + "," + fixed$(b, 2) + "}"

        # Color swatch
        Paint rectangle: colour$, i - 0.9, i - 0.4, 0.55, 0.85

        # File name, truncated to fit
        rawName$ = soundName$[i]
        if length(rawName$) > 14
            displayName$ = left$(rawName$, 12) + ".."
        else
            displayName$ = rawName$
        endif

        Colour: "Black"
        Font size: 6
        Text: i - 0.65, "centre", 0.30, "half", displayName$
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "File color legend  (" + string$(n) + " sources)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.38, 7.10
    Select inner viewport: 0.55, 7.72, 6.45, 7.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    # Compose the randomization status line
    if randomize_order
        if allow_repeats
            orderInfo$ = "Random with repeats"
        else
            orderInfo$ = "Random, no repeats"
        endif
    else
        orderInfo$ = "Sequential"
    endif

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + string$(n) + " files,  " + string$(chunks_per_file) + " chunks per file  =  " + string$(totalChunks) + " total chunks"
        ... + "  |  Order: " + orderInfo$

    Text: 0.02, "left", 0.50, "half",
        ... "Chunks: " + chunkModeName$
        ... + "  |  Crossfade: " + crossfadeTypeName$
        ... + "  |  Overlap: " + overlapModeName$
        ... + "  |  Dynamics: " + dynamicsName$

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Duration: " + fixed$(finalDuration, 2) + " s"
        ... + "  |  Total overlap: " + fixed$(totalOverlapTime, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)
        ... + "  |  SR: " + fixed$(sr / 1000, 1) + " kHz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore complete page for Picture export / clipboard.
    pageHeight = 7.25
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# CLEANUP
# ============================================================

for i to totalChunks
    removeObject: chunk[i]
endfor

if dynamicsViz <> 0
    removeObject: dynamicsViz
endif

selectObject: result

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:        ", compositeName$
appendInfoLine: "Duration:      ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Chunks:        ", totalChunks
appendInfoLine: "Total overlap: ", fixed$(totalOverlapTime, 2), " s"
appendInfoLine: "Out RMS:       ", fixed$(rms_out, 6)
appendInfoLine: ""

if play_result
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result
