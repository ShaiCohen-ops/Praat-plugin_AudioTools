# ============================================================
# Praat AudioTools - Concatenate_with_crossfade.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
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

form Advanced Concatenate with Crossfade v1.1
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
        option Equal-power (sqrt, no dip)
        option S-curve (cosine, smooth)
        option Exponential (fast start)
        option Logarithmic (fast end)
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
    randomize_order = 1
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
writeInfoLine: "=== ADVANCED CONCATENATE WITH CROSSFADE v1.1 ==="
appendInfoLine: ""
appendInfoLine: "Input sounds:    ", n
appendInfoLine: "Preset:          ", presetName$
appendInfoLine: "Chunk mode:      ", chunkModeName$
appendInfoLine: "Chunks per file: ", chunks_per_file
appendInfoLine: "Randomize:       ", randomize_order, "   Allow repeats: ", allow_repeats
appendInfoLine: "Crossfade type:  ", crossfadeTypeName$
appendInfoLine: "Overlap mode:    ", overlapModeName$
appendInfoLine: "Dynamics:        ", dynamicsName$
appendInfoLine: ""

# ============================================================
# PROCEDURE: Extract chunk from sound
# ============================================================

procedure extractChunk: .sound, .mode, .fixedDur, .minDur, .maxDur
    selectObject: .sound
    .totalDur = Get total duration

    if .mode = 1
        # Whole file
        .chunkStart = 0
        .chunkEnd = .totalDur
    elsif .mode = 2
        # Fixed chunk
        .chunkDur = min(.fixedDur, .totalDur)
        .maxStart = .totalDur - .chunkDur
        if .maxStart > 0
            .chunkStart = randomUniform(0, .maxStart)
        else
            .chunkStart = 0
        endif
        .chunkEnd = .chunkStart + .chunkDur
    else
        # Random chunk
        .chunkDur = randomUniform(.minDur, .maxDur)
        .chunkDur = min(.chunkDur, .totalDur)
        .maxStart = .totalDur - .chunkDur
        if .maxStart > 0
            .chunkStart = randomUniform(0, .maxStart)
        else
            .chunkStart = 0
        endif
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

procedure applyCrossfade: .sound, .fadeType, .duration, .direction$
    # .direction$ = "in" or "out"
    # .fadeType: 1=linear, 2=equal-power, 3=S-curve, 4=exp, 5=log

    selectObject: .sound
    .totalDur = Get total duration
    .sr = Get sampling frequency

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
            # Linear fade (Praat's built-in)
            if .direction$ = "in"
                Fade in: 0, .startTime, .fadeDur, "yes"
            else
                Fade out: 0, .startTime, .fadeDur, "yes"
            endif

        elsif .fadeType = 2
            # Equal-power (sqrt curve) - prevents volume dip at crossfade center
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * sqrt((x - .startTime) / .fadeDur)
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * sqrt(1 - (x - .startTime) / .fadeDur)
            endif

        elsif .fadeType = 3
            # S-curve (cosine) - very smooth
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (0.5 - 0.5 * cos(pi * (x - .startTime) / .fadeDur))
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (0.5 + 0.5 * cos(pi * (x - .startTime) / .fadeDur))
            endif

        elsif .fadeType = 4
            # Exponential (fast start for fade-in, fast end for fade-out)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (1 - exp(-4 * (x - .startTime) / .fadeDur))
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * exp(-4 * (x - .startTime) / .fadeDur)
            endif

        else
            # Logarithmic (slow start for fade-in, slow end for fade-out)
            if .direction$ = "in"
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (ln(1 + 9 * (x - .startTime) / .fadeDur) / ln(10))
            else
                Formula (part): .startTime, .endTime, 1, 1, ~ self * (1 - ln(1 + 9 * (x - .startTime) / .fadeDur) / ln(10))
            endif
        endif
    endif
endproc


# ============================================================
# PROCEDURE: Calculate overlap time
# ============================================================

procedure calculateOverlap: .chunkDuration, .mode, .percentage, .fixedDur, .minDur, .maxDur
    if .mode = 1
        # Percentage of incoming chunk
        calculateOverlap.time = .chunkDuration * .percentage / 100
    elsif .mode = 2
        # Fixed duration
        calculateOverlap.time = .fixedDur
    else
        # Random duration
        calculateOverlap.time = randomUniform(.minDur, .maxDur)
    endif

    # Ensure overlap doesn't exceed chunk duration
    if calculateOverlap.time > .chunkDuration * 0.9
        calculateOverlap.time = .chunkDuration * 0.9
    endif

    # Minimum overlap
    if calculateOverlap.time < 0.01
        calculateOverlap.time = 0.01
    endif
endproc


# ============================================================
# EXTRACT CHUNKS WITH CHANNEL STANDARDIZATION
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

        appendInfoLine: "  Chunk ", totalChunks, " from ", soundName$[i], " (", fixed$(chunkDur[totalChunks], 2), "s, ", chunkChan[totalChunks], "ch)"
    endfor
endfor

# STANDARDIZE CHANNELS - Convert all to match first chunk
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
# v1.1: two changes here.
#  (a) Fisher-Yates shuffle fixed to be uniform (was biased in v1.0).
#  (b) `allow_repeats` form field is now implemented. When
#      randomize_order=1 AND allow_repeats=1, chunkOrder is sampled
#      WITH replacement -- same chunk can appear multiple times.
#      Otherwise the order is a no-repeat random permutation.

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
        # and swap. v1.0 used `j = randomInteger(1, totalChunks)` for all
        # iterations, which is non-uniform.
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
# CONCATENATE WITH CROSSFADE
# ============================================================

appendInfoLine: ""
appendInfoLine: "Concatenating with crossfade..."

# Start with first chunk
firstIdx = chunkOrder[1]
selectObject: chunk[firstIdx]
result = Copy: "crossfaded_temp"

# Track segment positions for dynamics
segmentStart[1] = 0
segmentEnd[1] = chunkDur[firstIdx]
segmentDur[1] = chunkDur[firstIdx]

totalOverlapTime = 0

for i from 2 to totalChunks
    currentIdx = chunkOrder[i]
    currentDur = chunkDur[currentIdx]

    # Calculate overlap time
    @calculateOverlap: currentDur, overlap_mode, overlap_percentage, fixed_overlap_s, min_overlap_s, max_overlap_s
    overlapTime = calculateOverlap.time

    totalOverlapTime = totalOverlapTime + overlapTime

    # Copy incoming chunk (fresh copy so chunk[currentIdx] stays intact,
    # which matters when allow_repeats lets us revisit the same chunk).
    selectObject: chunk[currentIdx]
    incoming = Copy: "temp_incoming"

    # Apply fade out to result (end of current result)
    selectObject: result
    result_duration = Get total duration
    @applyCrossfade: result, crossfade_type, overlapTime, "out"

    # Apply fade in to incoming (start of incoming)
    selectObject: incoming
    @applyCrossfade: incoming, crossfade_type, overlapTime, "in"

    # Concatenate with overlap
    selectObject: result
    plusObject: incoming
    new_result = Concatenate with overlap: overlapTime

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

if dynamics_mode > 1
    appendInfoLine: ""
    appendInfoLine: "Applying dynamics: ", dynamicsName$, "..."

    selectObject: result
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

    elsif dynamics_mode = 7
        # Random per segment
        for seg to totalChunks
            segAmp[seg] = randomUniform(minAmp, 1)
        endfor

        # Apply per-segment amplitude with small crossfade between segments
        for seg to totalChunks
            sStart = segmentStart[seg]
            sEnd = segmentEnd[seg]
            amp = segAmp[seg]

            if seg < totalChunks
                # Fade to next segment's amplitude
                nextAmp = segAmp[seg + 1]
                fadeZone = min(0.1, (sEnd - sStart) * 0.2)

                selectObject: result
                # Main segment
                if sEnd - fadeZone > sStart
                    Formula (part): sStart, sEnd - fadeZone, 1, 1, ~ self * amp
                endif
                # Transition zone
                Formula (part): sEnd - fadeZone, sEnd, 1, 1, ~ self * (amp + (nextAmp - amp) * (x - (sEnd - fadeZone)) / fadeZone)
            else
                selectObject: result
                Formula (part): sStart, sEnd, 1, 1, ~ self * amp
            endif
        endfor

    elsif dynamics_mode = 8
        # Terraced (stepped levels)
        numSteps = min(totalChunks, 5)
        for seg to totalChunks
            stepNum = ((seg - 1) mod numSteps) + 1
            segAmp[seg] = minAmp + (1 - minAmp) * (stepNum - 1) / (numSteps - 1)
        endfor

        for seg to totalChunks
            sStart = segmentStart[seg]
            sEnd = segmentEnd[seg]
            amp = segAmp[seg]

            selectObject: result
            Formula (part): sStart, sEnd, 1, 1, ~ self * amp
        endfor
    endif

    appendInfoLine: "  Dynamics applied (depth: ", fixed$(dynamics_depth_percent, 0), "%)"
endif

# ============================================================
# FINAL PROCESSING
# ============================================================

selectObject: result
Scale peak: scale_peak
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
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##CONCATENATE WITH CROSSFADE##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... presetName$
        ... + "  |  " + string$(n) + " files, " + string$(totalChunks) + " chunks"
        ... + "  |  " + chunkModeName$
        ... + "  |  " + crossfadeTypeName$ + " crossfade"
        ... + "  |  " + dynamicsName$ + " dynamics"

    # ----------------------------------------------------------
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
        hue = (sourceIdx - 1) / n
        r = 0.4 + 0.5 * sin(2 * pi * hue)
        g = 0.4 + 0.5 * sin(2 * pi * hue + 2 * pi / 3)
        b = 0.4 + 0.5 * sin(2 * pi * hue + 4 * pi / 3)

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

    Axes: 0, finalDuration, 0, 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDuration, 0, 1.2

    # Unity reference dashed
    Colour: "{0.65, 0.65, 0.70}"
    Line width: 1
    Dotted line
    Draw line: 0, 1, finalDuration, 1
    Solid line

    if dynamics_mode > 1
        # Draw the curve
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
        elsif dynamics_mode = 7 or dynamics_mode = 8
            prevY = segAmp[1]
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
            elsif dynamics_mode = 7 or dynamics_mode = 8
                # Find which segment this point falls into
                y = 1
                for seg to totalChunks
                    if x >= segmentStart[seg] and x <= segmentEnd[seg]
                        y = segAmp[seg]
                    endif
                endfor
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
        r = 0.4 + 0.5 * sin(2 * pi * hue)
        g = 0.4 + 0.5 * sin(2 * pi * hue + 2 * pi / 3)
        b = 0.4 + 0.5 * sin(2 * pi * hue + 4 * pi / 3)
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
endif

# ============================================================
# CLEANUP
# ============================================================

for i to totalChunks
    removeObject: chunk[i]
endfor

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
