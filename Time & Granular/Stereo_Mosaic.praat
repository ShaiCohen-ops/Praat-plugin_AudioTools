# ============================================================
# Praat AudioTools - Stereo_Mosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Mosaic - creates stereo composites from multiple
#   selected Sound objects by partitioning each file into
#   regions and distributing them to L/R channels with
#   extensive creative control over extraction, timing,
#   spectral content, and spatial positioning.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#
#   TIER 1 (Praat polish, no audio change):
#     - Dropped 4 decorative `comment === ... ===` form rows
#       (PRESET / BASIC / CREATIVE / OUTPUT). Form: 15 rows -> 11.
#       Kept the "Select 2+ Sound objects first" instruction.
#     - Added colons to `optionmenu Preset` and
#       `optionmenu Channel_strategy` for suite consistency.
#     - Visualization rewritten from custom 10-wide layout to
#       suite 8x8 standard:
#         Title bar (suite light) + metadata subtitle
#         Panel A (left, headline): Left channel region map
#         Panel B (right, headline): Right channel region map
#         Panel C: Output stereo waveform
#         Panel D: File color legend with real file names
#         Panel E: light-grey summary stats bar
#     - Fixed color hue wrap-around: v0.3 used
#       hue = (i-1) / (N-1), giving first and last files identical
#       colors (sin period 1). v0.4 uses hue = (i-1) / N -- range
#       0 .. (N-1)/N -- no two files collide. Same fix as
#       Segment_Mixer v0.3.
#     - Replaced unicode multiplication sign `x` with plain `x` in
#       title Text (per the suite gotcha library, non-ASCII glyphs
#       in Praat Text() are unpredictable across platforms).
#     - Output filename: `mosaic_<N>f_<R>r` ->
#       `mosaic_<N>f_<R>r_<preset>_<strategy>` so multiple runs
#       with different settings don't silently overwrite. Added
#       `presetName$` to every preset block (v0.3 didn't define it).
#     - Param / stats text positioning bug: v0.3 set
#       `Select outer viewport: 0, 10, 4.3, 4.9` for the param
#       summary but never set fresh `Axes:` -- it inherited the
#       right-channel map's `Axes: 0, maxRegionsPerChannel, 0, N+1`,
#       so x-positions 0.5 and 1.5 ended up at the far left edge
#       instead of centered. Replaced by suite-standard Panel E
#       with explicit `Axes: 0, 1, 0, 1`.
#
#   TIER 2 (correctness, audio change for Spectral Dance preset):
#     - SWAPPED FILTER CALLS (audio change). In v0.3,
#       `left_highpass_Hz` was used as
#         Filter (pass Hann band): 0, left_highpass_Hz, 100
#       which Praat interprets as "pass 0 .. left_highpass_Hz Hz" =
#       LOWPASS at that cutoff. And `left_lowpass_Hz` was used as
#         Filter (pass Hann band): left_lowpass_Hz, 0, 100
#       which is "pass left_lowpass_Hz .. infinity" = HIGHPASS.
#       The variable names were inverted vs. the filter behavior.
#       Affected preset 4 "Spectral Dance" (left_highpass_Hz = 300,
#       right_lowpass_Hz = 4000): actual v0.3 behavior was "left
#       keep only < 300 Hz, right keep only > 4000 Hz" -- an extreme
#       split with a 300 Hz to 4 kHz gap on each side. The intended
#       behavior (and what the variable names suggest) is a
#       complementary HPF / LPF stereo spread: left passes ABOVE
#       300 Hz, right passes BELOW 4 kHz. v0.4 fixes the filter
#       calls to match the variable names; Spectral Dance now
#       produces the intended musical effect.
#       Other presets do not set these filter variables to nonzero
#       values, so they are bit-identical to v0.3.
#
#     - `continue` replaced with `goto skipRegion` + `label
#       skipRegion`. Praat does not document `continue` as a valid
#       keyword for loops; behavior was version-dependent. The
#       `goto` jumps to a label just before the inner-loop `endfor`,
#       so the for loop's mechanism continues normally with the
#       next iteration. This matters only for the edge case where
#       a region has zero or negative duration (region_end clamped
#       to file boundary leaves no content) -- in the common case
#       where all regions have positive duration, no behavior
#       change.
#
# Changelog v0.3:
#   - Added region overlap and gap control, random time offset,
#     pitch shift range, per-channel filters, pan jitter, stereo
#     width, cross-channel bleed, region duration variation,
#     tempo scaling, controllable reverse and amplitude variation
#   - Fixed hardcoded sample rate (auto-detection)
#   - Compact form with presets
# ============================================================

form Stereo Mosaic v0.4
    comment Select 2+ Sound objects first
    optionmenu Preset: 1
        option Custom
        option Classic Ping Pong
        option Glitchy Scatter
        option Spectral Dance
        option Wide Stereo Field
        option Dense Overlap
        option Minimal Sparse
    positive Regions_per_file 4
    optionmenu Channel_strategy: 1
        option Alternating regions
        option Left first / Right second
        option Random split
        option Reverse order
        option Inside out
        option Spiral pattern
    real Overlap_percent 0
    real Gap_ms 0
    real Pitch_shift_semitones 0
    real Reverse_percent 0
    real Stereo_width_percent 100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Ping Pong
    regions_per_file = 4
    channel_strategy = 1
    overlap_percent = 0
    gap_ms = 0
    pitch_shift_semitones = 0
    reverse_percent = 0
    stereo_width_percent = 100
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    random_time_offset_percent = 0
    duration_variation_percent = 0
    tempo_scale_min = 100
    tempo_scale_max = 100
    pitch_shift_min_semitones = 0
    pitch_shift_max_semitones = 0
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 0
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 100
    amplitude_variation_max = 100
    presetName$ = "ClassicPingPong"
elsif preset = 3
    # Glitchy Scatter
    regions_per_file = 8
    channel_strategy = 3
    overlap_percent = 0
    gap_ms = 50
    pitch_shift_semitones = 6
    reverse_percent = 40
    stereo_width_percent = 150
    fade_time_s = 0.02
    attenuation_divisor = 1.3
    random_time_offset_percent = 20
    duration_variation_percent = 30
    tempo_scale_min = 70
    tempo_scale_max = 150
    pitch_shift_min_semitones = -5
    pitch_shift_max_semitones = 7
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 30
    cross_channel_bleed_percent = 10
    amplitude_variation_min = 60
    amplitude_variation_max = 140
    presetName$ = "GlitchyScatter"
elsif preset = 4
    # Spectral Dance
    regions_per_file = 6
    channel_strategy = 6
    overlap_percent = 15
    gap_ms = 0
    pitch_shift_semitones = 5
    reverse_percent = 0
    stereo_width_percent = 130
    fade_time_s = 0.04
    attenuation_divisor = 1.1
    random_time_offset_percent = 10
    duration_variation_percent = 0
    tempo_scale_min = 90
    tempo_scale_max = 110
    pitch_shift_min_semitones = -7
    pitch_shift_max_semitones = 5
    left_highpass_Hz = 300
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 4000
    pan_jitter_percent = 20
    cross_channel_bleed_percent = 5
    amplitude_variation_min = 80
    amplitude_variation_max = 120
    presetName$ = "SpectralDance"
elsif preset = 5
    # Wide Stereo Field
    regions_per_file = 5
    channel_strategy = 1
    overlap_percent = 10
    gap_ms = 0
    pitch_shift_semitones = 0
    reverse_percent = 0
    stereo_width_percent = 180
    fade_time_s = 0.06
    attenuation_divisor = 1.0
    random_time_offset_percent = 0
    duration_variation_percent = 0
    tempo_scale_min = 100
    tempo_scale_max = 100
    pitch_shift_min_semitones = 0
    pitch_shift_max_semitones = 0
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 50
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 100
    amplitude_variation_max = 100
    presetName$ = "WideStereoField"
elsif preset = 6
    # Dense Overlap
    regions_per_file = 12
    channel_strategy = 3
    overlap_percent = 40
    gap_ms = 0
    pitch_shift_semitones = 3
    reverse_percent = 25
    stereo_width_percent = 120
    fade_time_s = 0.03
    attenuation_divisor = 1.4
    random_time_offset_percent = 15
    duration_variation_percent = 20
    tempo_scale_min = 85
    tempo_scale_max = 115
    pitch_shift_min_semitones = -3
    pitch_shift_max_semitones = 3
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 40
    cross_channel_bleed_percent = 15
    amplitude_variation_min = 70
    amplitude_variation_max = 130
    presetName$ = "DenseOverlap"
elsif preset = 7
    # Minimal Sparse
    regions_per_file = 3
    channel_strategy = 2
    overlap_percent = 0
    gap_ms = 300
    pitch_shift_semitones = 0
    reverse_percent = 10
    stereo_width_percent = 100
    fade_time_s = 0.08
    attenuation_divisor = 1.0
    random_time_offset_percent = 5
    duration_variation_percent = 10
    tempo_scale_min = 95
    tempo_scale_max = 105
    pitch_shift_min_semitones = 0
    pitch_shift_max_semitones = 0
    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 10
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 90
    amplitude_variation_max = 110
    presetName$ = "MinimalSparse"
else
    # Custom - use form values, set hidden params to defaults
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    random_time_offset_percent = 0
    duration_variation_percent = 0
    tempo_scale_min = 100
    tempo_scale_max = 100

    # Expand simple pitch_shift_semitones to min/max range
    if pitch_shift_semitones > 0
        pitch_shift_min_semitones = -pitch_shift_semitones
        pitch_shift_max_semitones = pitch_shift_semitones
    else
        pitch_shift_min_semitones = 0
        pitch_shift_max_semitones = 0
    endif

    left_highpass_Hz = 0
    right_highpass_Hz = 0
    left_lowpass_Hz = 0
    right_lowpass_Hz = 0
    pan_jitter_percent = 0
    cross_channel_bleed_percent = 0
    amplitude_variation_min = 100
    amplitude_variation_max = 100
    presetName$ = "Custom"
endif

# Clamp overlap to valid range
region_overlap_percent = overlap_percent
if region_overlap_percent < 0
    region_overlap_percent = 0
endif
if region_overlap_percent > 50
    region_overlap_percent = 50
endif

gap_between_regions_ms = gap_ms

# === Input Validation ===
numberOfSelectedSounds = numberOfSelected("Sound")

if numberOfSelectedSounds = 0
    exitScript: "Please select some Sound objects first."
endif
if numberOfSelectedSounds < 2
    exitScript: "Please select at least two Sound objects."
endif
if fade_time_s < 0
    exitScript: "Fade time cannot be negative."
endif
if regions_per_file < 1
    exitScript: "Regions per file must be at least 1."
endif

# === Get Strategy Name ===
if channel_strategy = 1
    strategyName$ = "Alternating"
elsif channel_strategy = 2
    strategyName$ = "Split"
elsif channel_strategy = 3
    strategyName$ = "Random"
elsif channel_strategy = 4
    strategyName$ = "Reverse"
elsif channel_strategy = 5
    strategyName$ = "Inside-out"
else
    strategyName$ = "Spiral"
endif

# === Info ===
writeInfoLine: "=== Stereo Mosaic v0.4 ==="
appendInfoLine: "Files:    ", numberOfSelectedSounds
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Regions:  ", regions_per_file, " per file"
appendInfoLine: "Strategy: ", strategyName$
appendInfoLine: ""

# === Store Original Selection and Detect Sample Rate ===
originalSounds# = selected#("Sound")
soundNames$# = empty$#(numberOfSelectedSounds)
maxSR = 0

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    soundNames$#[i] = selected$("Sound")
    thisSR = Get sampling frequency
    if thisSR > maxSR
        maxSR = thisSR
    endif
endfor

appendInfoLine: "Sample rate: ", maxSR, " Hz"
appendInfoLine: ""

# === Convert All to Mono and Resample ===
monoSounds# = zero#(numberOfSelectedSounds)

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    thisSR = Get sampling frequency
    numChannels = Get number of channels

    Copy: "mono_work_" + string$(i)
    workID = selected("Sound")

    # Resample if needed
    if thisSR <> maxSR
        Resample: maxSR, 50
        removeObject: workID
        workID = selected("Sound")
    endif

    # Convert to mono
    if numChannels > 1
        Convert to mono
        monoID = selected("Sound")
        removeObject: workID
        monoSounds#[i] = monoID
    else
        monoSounds#[i] = workID
    endif
endfor

# === Create Initial Buffers ===
Create Sound from formula: "temp_left", 1, 0, 0.01, maxSR, "0"
leftID = selected("Sound")

Create Sound from formula: "temp_right", 1, 0, 0.01, maxSR, "0"
rightID = selected("Sound")

# === Store Region Assignments for Visualization ===
totalRegions = numberOfSelectedSounds * regions_per_file
regionFile# = zero#(totalRegions)
regionIndex# = zero#(totalRegions)
regionChannel# = zero#(totalRegions)
regionReversed# = zero#(totalRegions)
regionPitchShift# = zero#(totalRegions)
regionIdx = 0

leftCount = 0
rightCount = 0

# === Main Processing Loop ===
appendInfoLine: "Processing files..."

for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    soundName$ = selected$("Sound")
    total_duration = Get total duration

    # Random time offset
    if random_time_offset_percent > 0
        maxOffset = total_duration * random_time_offset_percent / 100
        timeOffset = randomUniform(0, maxOffset)
    else
        timeOffset = 0
    endif

    # Calculate overlap
    overlapFactor = 1 - (region_overlap_percent / 100)
    if overlapFactor < 0.5
        overlapFactor = 0.5
    endif

    # Effective step size with overlap
    step_duration = (total_duration - timeOffset) / (regions_per_file * overlapFactor - (1 - overlapFactor))
    region_duration = step_duration

    appendInfoLine: "  File ", i, ": ", regions_per_file, " regions x ", fixed$(region_duration * 1000, 0), "ms"
    if timeOffset > 0
        appendInfoLine: "    Offset: +", fixed$(timeOffset * 1000, 0), "ms"
    endif

    for region to regions_per_file
        # Calculate region boundaries with overlap
        regionStart = timeOffset + (region - 1) * step_duration * overlapFactor
        regionEnd = regionStart + region_duration

        # Duration variation
        if duration_variation_percent > 0
            durationMult = 1 + randomUniform(-duration_variation_percent/100, duration_variation_percent/100)
            regionDurVaried = region_duration * durationMult
            regionEnd = regionStart + regionDurVaried
        endif

        # Clip to file boundaries
        if regionStart < 0
            regionStart = 0
        endif
        if regionEnd > total_duration
            regionEnd = total_duration
        endif

        # v0.4: replaced `continue` (not a documented Praat keyword) with
        # goto skipRegion. The label is placed just before the inner-loop
        # endfor, so the for-loop mechanism continues normally with the
        # next iteration. Common case (positive-duration region) is
        # unaffected.
        if regionEnd <= regionStart
            goto skipRegion
        endif

        selectObject: monoSounds#[i]
        Extract part: regionStart, regionEnd, "rectangular", 1, "no"
        regionSeg = selected("Sound")

        # === TEMPORAL PROCESSING ===

        # Tempo scaling
        if tempo_scale_min <> 100 or tempo_scale_max <> 100
            tempoScale = randomUniform(tempo_scale_min, tempo_scale_max) / 100
            if abs(tempoScale - 1.0) > 0.01
                selectObject: regionSeg
                Lengthen (overlap-add): 75, 600, tempoScale
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
        endif

        # Determine channel based on strategy
        if channel_strategy = 1
            # Alternating
            if region mod 2 = 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 2
            # Left first half, Right second half
            if region <= regions_per_file / 2
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 3
            # Random
            if randomUniform(0, 1) < 0.5
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        elsif channel_strategy = 4
            # Reverse order right
            if region mod 2 = 1
                isLeftChannel = 0
            else
                isLeftChannel = 1
            endif
        elsif channel_strategy = 5
            # Inside out
            midpoint = (regions_per_file + 1) / 2
            distanceFromMid = abs(region - midpoint)
            if floor(distanceFromMid) mod 2 = 0
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        else
            # Spiral (golden ratio)
            spiralValue = (i * 1.618 + region) mod 2
            if spiralValue < 1
                isLeftChannel = 1
            else
                isLeftChannel = 0
            endif
        endif

        # Pan jitter (soft L/R)
        if pan_jitter_percent > 0
            jitterAmount = pan_jitter_percent / 100
            panShift = randomUniform(-jitterAmount, jitterAmount)

            if isLeftChannel = 1
                # Left channel with jitter
                if panShift > 0
                    # Shift toward center/right
                    if randomUniform(0, 1) < panShift
                        isLeftChannel = 0
                    endif
                endif
            else
                # Right channel with jitter
                if panShift < 0
                    # Shift toward center/left
                    if randomUniform(0, 1) < abs(panShift)
                        isLeftChannel = 1
                    endif
                endif
            endif
        endif

        # Store for visualization
        regionIdx += 1
        regionFile#[regionIdx] = i
        regionIndex#[regionIdx] = region
        regionChannel#[regionIdx] = isLeftChannel

        # === SPECTRAL PROCESSING ===

        # Pitch shifting
        pitchShift = 0
        if pitch_shift_min_semitones <> 0 or pitch_shift_max_semitones <> 0
            pitchShift = randomUniform(pitch_shift_min_semitones, pitch_shift_max_semitones)
            if abs(pitchShift) > 0.1
                selectObject: regionSeg
                pitchManip = To Manipulation: 0.01, 75, 600
                pitchTier = Extract pitch tier

                selectObject: pitchTier
                pitchFactor = 2^(pitchShift/12)
                pitchFactorStr$ = string$(pitchFactor)
                Formula: "self * " + pitchFactorStr$

                selectObject: pitchManip
                plusObject: pitchTier
                Replace pitch tier

                selectObject: pitchManip
                Get resynthesis (overlap-add)
                newSeg = selected("Sound")

                removeObject: regionSeg, pitchManip, pitchTier
                regionSeg = newSeg
            endif
        endif
        regionPitchShift#[regionIdx] = pitchShift

        # Channel-specific filtering
        # v0.4: filter calls fixed so variable names match behavior.
        # v0.3 had `Filter (pass Hann band): 0, X, 100` for highpass
        # (which is actually a lowpass at X) and the inverse for lowpass.
        # v0.4 uses:
        #   HPF at X Hz: Filter (pass Hann band): X, 0, 100  (X .. inf)
        #   LPF at X Hz: Filter (pass Hann band): 0, X, 100  (0 .. X)
        selectObject: regionSeg
        if isLeftChannel = 1
            if left_highpass_Hz > 0
                Filter (pass Hann band): left_highpass_Hz, 0, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
            if left_lowpass_Hz > 0
                selectObject: regionSeg
                Filter (pass Hann band): 0, left_lowpass_Hz, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
        else
            if right_highpass_Hz > 0
                Filter (pass Hann band): right_highpass_Hz, 0, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
            if right_lowpass_Hz > 0
                selectObject: regionSeg
                Filter (pass Hann band): 0, right_lowpass_Hz, 100
                newSeg = selected("Sound")
                removeObject: regionSeg
                regionSeg = newSeg
            endif
        endif

        # Optional reverse
        selectObject: regionSeg
        wasReversed = 0
        if reverse_percent > 0
            if randomUniform(0, 100) < reverse_percent
                Reverse
                wasReversed = 1
            endif
        endif
        regionReversed#[regionIdx] = wasReversed

        # === AMPLITUDE PROCESSING ===

        # Amplitude variation
        if amplitude_variation_min <> 100 or amplitude_variation_max <> 100
            ampMult = randomUniform(amplitude_variation_min, amplitude_variation_max) / 100
            Scale peak: ampMult * 0.95
        endif

        # Apply fades and attenuation
        segDur = Get total duration
        if segDur > 2 * fade_time_s
            attStr$ = string$(attenuation_divisor)
            Formula: "self / " + attStr$
            fadeStr$ = string$(fade_time_s)
            Formula: "self * min(1, x / " + fadeStr$ + ")"
            Formula: "self * min(1, (xmax - x) / " + fadeStr$ + ")"
        else
            attStr$ = string$(attenuation_divisor)
            Formula: "self / " + attStr$
        endif

        # Add to appropriate channel
        if isLeftChannel = 1
            selectObject: leftID, regionSeg
            Concatenate
            newLeft = selected("Sound")
            removeObject: leftID
            leftID = newLeft
            Rename: "temp_left"
            leftCount += 1
        else
            selectObject: rightID, regionSeg
            Concatenate
            newRight = selected("Sound")
            removeObject: rightID
            rightID = newRight
            Rename: "temp_right"
            rightCount += 1
        endif

        removeObject: regionSeg

        # Add gap if specified
        if gap_between_regions_ms > 0
            gapDur = gap_between_regions_ms / 1000
            gap = Create Sound from formula: "gap", 1, 0, gapDur, maxSR, "0"

            if isLeftChannel = 1
                selectObject: leftID, gap
                Concatenate
                newLeft = selected("Sound")
                removeObject: leftID
                leftID = newLeft
                Rename: "temp_left"
            else
                selectObject: rightID, gap
                Concatenate
                newRight = selected("Sound")
                removeObject: rightID
                rightID = newRight
                Rename: "temp_right"
            endif

            removeObject: gap
        endif

        # v0.4: target of the `goto skipRegion` jump for zero-duration regions.
        label skipRegion
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Left channel:  ", leftCount, " regions"
appendInfoLine: "Right channel: ", rightCount, " regions"

# === Equalize Channel Lengths ===
selectObject: leftID
leftDur = Get total duration

selectObject: rightID
rightDur = Get total duration

# Pad shorter channel with silence
if leftDur > rightDur
    silenceDur = leftDur - rightDur
    silence = Create Sound from formula: "pad", 1, 0, silenceDur, maxSR, "0"
    selectObject: rightID, silence
    Concatenate
    newRight = selected("Sound")
    removeObject: rightID, silence
    rightID = newRight
    Rename: "temp_right"
elsif rightDur > leftDur
    silenceDur = rightDur - leftDur
    silence = Create Sound from formula: "pad", 1, 0, silenceDur, maxSR, "0"
    selectObject: leftID, silence
    Concatenate
    newLeft = selected("Sound")
    removeObject: leftID, silence
    leftID = newLeft
    Rename: "temp_left"
endif

# === Stereo Width Processing ===
if stereo_width_percent <> 100
    widthFactor = stereo_width_percent / 100

    selectObject: leftID
    leftCopy = Copy: "left_width"

    selectObject: rightID
    rightCopy = Copy: "right_width"

    # M/S processing
    selectObject: leftID
    rightStr$ = string$(rightCopy)
    Formula: "(self + object[" + rightStr$ + "]) / 2 + ((self - object[" + rightStr$ + "]) / 2) * " + string$(widthFactor)

    selectObject: rightID
    leftStr$ = string$(leftCopy)
    Formula: "(self + object[" + leftStr$ + "]) / 2 - ((object[" + leftStr$ + "] - self) / 2) * " + string$(widthFactor)

    removeObject: leftCopy, rightCopy
endif

# === Cross-Channel Bleed ===
if cross_channel_bleed_percent > 0
    bleedAmount = cross_channel_bleed_percent / 100

    selectObject: leftID
    Copy: "left_for_bleed"
    leftCopy = selected("Sound")

    selectObject: rightID
    Copy: "right_for_bleed"
    rightCopy = selected("Sound")

    # Add bleed from right to left
    selectObject: leftID
    rightStr$ = string$(rightCopy)
    bleedStr$ = string$(bleedAmount)
    Formula: "self + " + bleedStr$ + " * object[" + rightStr$ + "]"

    # Add bleed from left to right
    selectObject: rightID
    leftStr$ = string$(leftCopy)
    Formula: "self + " + bleedStr$ + " * object[" + leftStr$ + "]"

    removeObject: leftCopy, rightCopy
endif

# === Finalize ===
selectObject: leftID
Scale peak: 0.99

selectObject: rightID
Scale peak: 0.99

selectObject: leftID, rightID
Combine to stereo
result = selected("Sound")

# v0.4: output filename now includes preset + strategy suffix.
compositeName$ = "mosaic_" + string$(numberOfSelectedSounds) + "f_"
    ... + string$(regions_per_file) + "r_"
    ... + presetName$ + "_" + strategyName$
Rename: compositeName$

selectObject: result
outputDuration = Get total duration
rms_out = Get root-mean-square: 0, 0

# === Cleanup of working buffers (keep result + soundNames$#) ===
removeObject: leftID, rightID

for i to numberOfSelectedSounds
    if monoSounds#[i] > 0
        removeObject: monoSounds#[i]
    endif
endfor

###############################################################################
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: Left channel region map   (left, headline)
# Panel B: Right channel region map  (right, headline)
# Panel C: Output stereo waveform
# Panel D: File color legend with names
# Panel E: light-grey summary stats bar
###############################################################################

if draw_visualization
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
    Text: 0.5, "centre", 0.68, "half", "##STEREO MOSAIC##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... string$(numberOfSelectedSounds) + " files x " + string$(regions_per_file) + " regions"
        ... + "  |  " + presetName$
        ... + "  |  " + strategyName$
        ... + "  |  Overlap " + fixed$(region_overlap_percent, 0) + "%"
        ... + "  |  Width " + fixed$(stereo_width_percent, 0) + "%"

    maxRegionsPerChannel = max(leftCount, rightCount)
    if maxRegionsPerChannel < 1
        maxRegionsPerChannel = 1
    endif

    # ----------------------------------------------------------
    # PANEL A: LEFT CHANNEL REGION MAP  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    Axes: 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1
    Paint rectangle: "{0.90, 0.95, 1.00}", 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1

    leftPos = 0
    for r to regionIdx
        if regionChannel#[r] = 1
            leftPos += 1
            fileIdx = regionFile#[r]

            # v0.4: hue ranges 0..(N-1)/N instead of 0..1, so no wrap.
            hue = (fileIdx - 1) / numberOfSelectedSounds
            red = 0.3 + 0.5 * sin(hue * 2 * pi)
            grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"

            Paint rectangle: barColor$, leftPos - 0.9, leftPos - 0.1, fileIdx - 0.4, fileIdx + 0.4
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "File #"
    Text bottom: "yes", "Region position"

    # ----------------------------------------------------------
    # PANEL B: RIGHT CHANNEL REGION MAP  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1
    Paint rectangle: "{1.00, 0.95, 0.90}", 0, maxRegionsPerChannel, 0, numberOfSelectedSounds + 1

    rightPos = 0
    for r to regionIdx
        if regionChannel#[r] = 0
            rightPos += 1
            fileIdx = regionFile#[r]

            hue = (fileIdx - 1) / numberOfSelectedSounds
            red = 0.3 + 0.5 * sin(hue * 2 * pi)
            grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"

            Paint rectangle: barColor$, rightPos - 0.9, rightPos - 0.1, fileIdx - 0.4, fileIdx + 0.4
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "File #"
    Text bottom: "yes", "Region position"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES  (above A and B)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Left channel  (" + string$(leftCount) + " regions)"
    Text: 6.10, "centre", 7.30, "half",
        ... "Right channel  (" + string$(rightCount) + " regions)"

    # ----------------------------------------------------------
    # PANEL C: OUTPUT STEREO WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    selectObject: result
    Colour: "{0.30, 0.50, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output stereo waveform  (" + fixed$(outputDuration, 2) + " s)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: FILE COLOR LEGEND  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, numberOfSelectedSounds, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numberOfSelectedSounds, 0, 1

    for i to numberOfSelectedSounds
        hue = (i - 1) / numberOfSelectedSounds
        red = 0.3 + 0.5 * sin(hue * 2 * pi)
        grn = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
        blu = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
        barColor$ = "{" + fixed$(red, 2) + ", " + fixed$(grn, 2) + ", " + fixed$(blu, 2) + "}"

        # Color swatch
        Paint rectangle: barColor$, i - 0.9, i - 0.4, 0.55, 0.85

        # Actual file name, truncated if needed
        rawName$ = soundNames$#[i]
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
    Text top: "no", "File color legend"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + string$(numberOfSelectedSounds) + " files x " + string$(regions_per_file) + " regions"
        ... + "  =  " + string$(regionIdx) + " regions  (L:" + string$(leftCount) + "  R:" + string$(rightCount) + ")"
        ... + "  |  Strategy: " + strategyName$

    Text: 0.02, "left", 0.50, "half",
        ... "Overlap: " + fixed$(region_overlap_percent, 0) + "%"
        ... + "  |  Gap: " + fixed$(gap_between_regions_ms, 0) + " ms"
        ... + "  |  Reverse: " + fixed$(reverse_percent, 0) + "%"
        ... + "  |  Width: " + fixed$(stereo_width_percent, 0) + "%"
        ... + "  |  Bleed: " + fixed$(cross_channel_bleed_percent, 0) + "%"

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Duration: " + fixed$(outputDuration, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)
        ... + "  |  SR: " + fixed$(maxSR / 1000, 1) + " kHz"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created:  ", compositeName$
appendInfoLine: "Duration: ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Regions:  ", regionIdx, " (L:", leftCount, " R:", rightCount, ")"
appendInfoLine: "Out RMS:  ", fixed$(rms_out, 6)
appendInfoLine: ""
appendInfoLine: "Processing applied:"
if region_overlap_percent > 0
    appendInfoLine: "  - Region overlap: ", region_overlap_percent, "%"
endif
if gap_between_regions_ms > 0
    appendInfoLine: "  - Gaps: ", gap_between_regions_ms, " ms"
endif
if pitch_shift_min_semitones <> 0 or pitch_shift_max_semitones <> 0
    appendInfoLine: "  - Pitch shift: ", pitch_shift_min_semitones, " to +", pitch_shift_max_semitones, " semitones"
endif
if reverse_percent > 0
    appendInfoLine: "  - Reverse probability: ", reverse_percent, "%"
endif
if stereo_width_percent <> 100
    appendInfoLine: "  - Stereo width: ", stereo_width_percent, "%"
endif
if cross_channel_bleed_percent > 0
    appendInfoLine: "  - Cross-channel bleed: ", cross_channel_bleed_percent, "%"
endif
if left_highpass_Hz > 0 or right_highpass_Hz > 0 or left_lowpass_Hz > 0 or right_lowpass_Hz > 0
    appendInfoLine: "  - Per-channel filters: L-HPF=", left_highpass_Hz, " L-LPF=", left_lowpass_Hz, " R-HPF=", right_highpass_Hz, " R-LPF=", right_lowpass_Hz, " Hz"
endif

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
