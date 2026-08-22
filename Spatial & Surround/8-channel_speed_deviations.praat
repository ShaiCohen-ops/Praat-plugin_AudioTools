# ============================================================
# Praat AudioTools - 8-channel_speed_deviations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# v0.5 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Speed Deviations via PSOLA.
#   Eight copies of one source, each time-stretched by its own constant
#   speed factor, so they drift apart. Output as octophonic, stems, or
#   a downmix.
#
#   Each channel holds ONE constant speed for its whole length. The
#   speed changes from channel to channel, not within a channel.
#
#   Duration is D / s, so a speed factor is not a duration percentage:
#   -15% speed is +17.65% duration, +15% speed is -13.04% duration.
#   The speed set is symmetric about 1; the durations are not.
#
# Changelog v0.5 (2026):
#   - FIX (critical): Random mode was not random. It used
#     ((seed * i * 137 + 97) mod 1000) / 1000, an arithmetic sequence
#     with a constant step, not Praat's generator. Successive channels
#     differ by the same amount every time - at seed 42 the step is
#     -0.246 for every pair - so the "random" field is a descending
#     ramp that wraps, which is audibly a fan, not a scatter. Some
#     seeds are worse: seed 0 and seed 1000 give all eight channels the
#     identical speed, seed 500 alternates between two values. Across
#     seeds 0-9999, 80 of them (0.8%) produce fewer than eight distinct
#     speeds, but the arithmetic structure affects every seed, not just
#     those. Now uses randomUniform between Random_min_speed and
#     Random_max_speed, with the generator seeded through
#     random_initializeWithSeedUnsafelyButPredictably for a positive
#     seed and random_initializeSafelyAndUnpredictably for 0, and
#     restored to unpredictable afterwards so the script does not leave
#     the generator seeded for whatever runs next.
#   - FIX: Speed_deviation_factor was only guarded as positive, so a
#     value of 1 gave channel 1 a speed of exactly 0 and anything above
#     1 gave it a negative speed - D/s is then undefined or negative and
#     the stretch is meaningless. Now bounded to 0 <= d < 1, and 0 is
#     allowed (eight channels at unison), which the positive type
#     forbade.
#   - FIX: no check that Random_min_speed < Random_max_speed, or that
#     Min_pitch < Max_pitch. Both are validated now, and a very low
#     speed factor is warned about: s = 0.1 asks PSOLA for a tenfold
#     stretch, which runs but degrades.
#   - FIX: the resample step called selected("Sound") after
#     removeObject, relying on the survivor staying selected. The id is
#     captured before the removal.
#   - FIX: the working copy was not normalised to start at t = 0. A
#     Sound extracted with preserved times does not, and the analysis
#     and the drift diagram would be displaced by xmin.
#   - RENAME: Accelerando and Decelerando described something the
#     script does not do. There is no s(t) - no channel speeds up or
#     slows down while it plays. They are a ladder of channels at
#     ascending or descending constant speeds, and are named that way.
#     Their values were also unevenly spaced: 0.70 0.80 0.90 1.00 1.10
#     1.20 1.25 1.30 steps by 0.10 five times and then 0.05 twice.
#     Now evenly spaced across 0.7 to 1.3.
#   - RENAME: sampling frequency now defaults to preserving the source
#     rate. v0.3 forced 44100 by default, resampling 48 or 96 kHz
#     material without being asked.
#   - WORDING: "Preserves pitch" is now stated as aiming to preserve
#     perceived pitch via PSOLA, which depends on the pitch analysis
#     succeeding in the given range. Polyphonic, noisy or poorly
#     tracked material will show artefacts.
#   - NEW: achieved speed is measured and reported alongside the
#     requested speed, from D_original / D_result, with the error. The
#     drift diagram is drawn from the measured durations, so it plots
#     what happened rather than what was asked for.
#   - NEW: Output_format menu, keyed to the speed ladder.
#       1  8 channels - octophonic     Ch1-Ch8
#       2  4 symmetric speed pairs     Ch1|Ch8 Ch2|Ch7 Ch3|Ch6 Ch4|Ch5
#       3  2 quad groups               Ch1-Ch4, Ch5-Ch8
#       4  4-channel fold-down         Ch1+Ch8, Ch2+Ch7, Ch3+Ch6, Ch4+Ch5
#       5  Stereo mix                  L: Ch1-Ch4   R: Ch5-Ch8
#     The pairs mirror across unison rather than taking adjacent
#     channels: in Automatic mode Ch1 and Ch8 deviate by exactly the
#     same amount in opposite directions, so each pair is one slower
#     and one faster copy and the fold-down channels beat against
#     themselves. Verified symmetric: at d = 0.15 the four pairs mean
#     exactly 1.0000 with deviations 0.1500, 0.1071, 0.0643, 0.0214.
#   - NEW: shared gain across the eight channels for the stem formats;
#     the two summing formats normalise once after the sums. v0.3 was
#     already correct here - it combined first and scaled once - and
#     format 1 is numerically unchanged.
#   - NEW: monitoring mix for preview playback in the stem formats.
#   - FIX: the waveform panel was titled "Output 8-ch mix" but drew
#     channels 1 and 2. Renamed to channel examples, and drawn from the
#     working channels so it is identical in every output format.
#
# Changelog v0.3:
#   - Visualization rewritten to the suite 8x8 standard, multi-panel.
#   - Audio pipeline unchanged from v0.2.
# ============================================================

# === Check Input (before the form) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Speed Deviations
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use mode below)"
        option: "Subtle (speed ±5%)"
        option: "Moderate (speed ±15%)"
        option: "Wide (speed ±30%)"
        option: "Extreme (speed ±50%)"
        option: "Ascending channel speeds (0.7 to 1.3)"
        option: "Descending channel speeds (1.3 to 0.7)"

    comment === MODE ===
    optionmenu Mode: 1
        option: "Automatic (using factor)"
        option: "Manual (input all values)"
        option: "Random deviation"

    comment === Automatic mode: deviation factor, 0 to below 1 ===
    real Speed_deviation_factor 0.15

    comment === Manual mode settings ===
    positive Channel_1_speed 0.85
    positive Channel_2_speed 0.88
    positive Channel_3_speed 0.91
    positive Channel_4_speed 0.94
    positive Channel_5_speed 1.06
    positive Channel_6_speed 1.09
    positive Channel_7_speed 1.12
    positive Channel_8_speed 1.15

    comment === Random mode settings (0 seed = unpredictable) ===
    positive Random_min_speed 0.80
    positive Random_max_speed 1.20
    integer Random_seed 42

    comment === Audio settings ===
    positive Min_pitch 75
    positive Max_pitch 600
    boolean Override_sampling_frequency 0
    positive Target_sampling_frequency 44100

    comment === OUTPUT FORMAT ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 symmetric speed pairs (Ch1|Ch8, Ch2|Ch7, Ch3|Ch6, Ch4|Ch5)"
        option: "2 quad groups (Ch1-Ch4 slower bank, Ch5-Ch8 faster bank)"
        option: "4-channel fold-down (Ch1+Ch8, Ch2+Ch7, Ch3+Ch6, Ch4+Ch5)"
        option: "Stereo mix (L: Ch1-Ch4, R: Ch5-Ch8)"

    comment === Output ===
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    mode = 1
    speed_deviation_factor = 0.05
    presetName$ = "Subtle"
elsif preset = 3
    mode = 1
    speed_deviation_factor = 0.15
    presetName$ = "Moderate"
elsif preset = 4
    mode = 1
    speed_deviation_factor = 0.30
    presetName$ = "Wide"
elsif preset = 5
    mode = 1
    speed_deviation_factor = 0.50
    presetName$ = "Extreme"
elsif preset = 6
    # v0.5: evenly spaced. v0.3 stepped by 0.10 five times then 0.05
    # twice, which was almost certainly not intended.
    mode = 2
    channel_1_speed = 0.7000
    channel_2_speed = 0.7857
    channel_3_speed = 0.8714
    channel_4_speed = 0.9571
    channel_5_speed = 1.0429
    channel_6_speed = 1.1286
    channel_7_speed = 1.2143
    channel_8_speed = 1.3000
    presetName$ = "Ascending"
elsif preset = 7
    mode = 2
    channel_1_speed = 1.3000
    channel_2_speed = 1.2143
    channel_3_speed = 1.1286
    channel_4_speed = 1.0429
    channel_5_speed = 0.9571
    channel_6_speed = 0.8714
    channel_7_speed = 0.7857
    channel_8_speed = 0.7000
    presetName$ = "Descending"
else
    if mode = 1
        presetName$ = "Auto"
    elsif mode = 2
        presetName$ = "Manual"
    else
        presetName$ = "Random"
    endif
endif

# === Guards ===
if min_pitch >= max_pitch
    exitScript: "Min_pitch (", min_pitch, ") must be below Max_pitch (", max_pitch, ")."
endif

# v0.5: d = 1 gives channel 1 a speed of exactly 0 and d > 1 gives it a
# negative speed, so D/s is undefined or negative. d = 0 is legal and
# useful (eight channels at unison) but the positive type forbade it.
devClamped = 0
if speed_deviation_factor < 0
    speed_deviation_factor = 0
    devClamped = 1
endif
if speed_deviation_factor > 0.95
    speed_deviation_factor = 0.95
    devClamped = 1
endif

if mode = 3 and random_min_speed >= random_max_speed
    exitScript: "Random_min_speed (", random_min_speed,
        ... ") must be below Random_max_speed (", random_max_speed, ")."
endif

if scale_peak <= 0 or scale_peak > 1
    scale_peak = 0.95
endif

# === Calculate speed factors ===
seedApplied = 0
if mode = 1
    for i from 1 to 8
        speedFactor[i] = 1 - speed_deviation_factor + ((i - 1) * (2 * speed_deviation_factor) / 7)
    endfor
elsif mode = 2
    speedFactor[1] = channel_1_speed
    speedFactor[2] = channel_2_speed
    speedFactor[3] = channel_3_speed
    speedFactor[4] = channel_4_speed
    speedFactor[5] = channel_5_speed
    speedFactor[6] = channel_6_speed
    speedFactor[7] = channel_7_speed
    speedFactor[8] = channel_8_speed
else
    # v0.5: Praat's own generator. The v0.3 formula was an arithmetic
    # sequence with a constant step, so the eight channels formed a
    # ramp rather than a scatter, and a few seeds collapsed them onto
    # one or two values.
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
        seedApplied = 1
    else
        random_initializeSafelyAndUnpredictably ()
    endif
    for i from 1 to 8
        speedFactor[i] = randomUniform(random_min_speed, random_max_speed)
    endfor
    # Leave the generator unpredictable so this script does not seed
    # whatever the user runs next.
    random_initializeSafelyAndUnpredictably ()
endif

# Validate every factor, whatever the mode produced
slowWarn = 0
for i from 1 to 8
    if speedFactor[i] <= 0
        exitScript: "Channel ", i, " has speed factor ", speedFactor[i],
            ... ", which is not positive. Duration D/s is undefined."
    endif
    if speedFactor[i] < 0.25 or speedFactor[i] > 4
        slowWarn = slowWarn + 1
    endif
endfor

# === Source, normalised to start at t = 0 ===
originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
numberOfChannels = Get number of channels
srcT0 = Get start time
srcT1 = Get end time

if numberOfChannels > 1
    selectObject: originalID
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: originalID
    Copy: "sd_mono"
    monoID = selected("Sound")
endif

# v0.5: the drift diagram and the frame arithmetic index from 0. A
# Sound extracted with preserved times does not start there.
selectObject: monoID
workT0 = Get start time
if workT0 <> 0
    selectObject: monoID
    shiftedID = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: monoID
    monoID = shiftedID
endif
selectObject: monoID
Rename: "sd_work"
original_dur = Get total duration

if original_dur <= 0
    removeObject: monoID
    exitScript: "Source has zero duration."
endif

if override_sampling_frequency
    workingSr = target_sampling_frequency
else
    workingSr = original_sr
endif

# ============================================================
# PROCESS EACH CHANNEL
# ============================================================
stopwatch
for i from 1 to 8
    sf = speedFactor[i]

    selectObject: monoID
    Copy: "sd_tmp" + string$(i)
    tempID = selected("Sound")

    # Duration is D / s, so the PSOLA stretch factor is 1 / s.
    targetDur = original_dur / sf
    durationRatio = targetDur / original_dur

    selectObject: tempID
    Lengthen (overlap-add): min_pitch, max_pitch, durationRatio
    processedID = selected("Sound")

    if override_sampling_frequency
        selectObject: processedID
        Resample: target_sampling_frequency, 50
        resampledID = selected("Sound")
        # v0.5: capture the new id BEFORE removing the old one. v0.3
        # called selected() after removeObject, relying on the survivor
        # staying selected.
        removeObject: processedID
        processedID = resampledID
    endif

    channel[i] = processedID
    selectObject: channel[i]
    Rename: "sdCh" + string$(i)
    dur[i] = Get total duration

    # v0.5: measure what actually came out. PSOLA lands close but not
    # exactly on the requested duration, and the drift diagram should
    # plot the result rather than the request.
    if dur[i] > 0
        achieved[i] = original_dur / dur[i]
    else
        achieved[i] = sf
    endif
    speedErr[i] = achieved[i] - sf
    durErr[i] = dur[i] - targetDur

    removeObject: tempID
endfor
processElapsed = stopwatch

# ============================================================
# SHARED-GAIN NORMALISATION  (stage 1)
# ============================================================
peakAll = 0
for i from 1 to 8
    selectObject: channel[i]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
allSilent = 0
if peakAll < 1e-9
    allSilent = 1
    sharedGain = 1
else
    sharedGain = scale_peak / peakAll
endif
if allSilent = 0
    sharedGain$ = fixed$(sharedGain, 10)
    for i from 1 to 8
        selectObject: channel[i]
        Formula: "self * " + sharedGain$
    endfor
endif

# ============================================================
# FORMAT LABELS
# ============================================================
# Symmetric pairs mirror across unison rather than taking adjacent
# channels. In Automatic mode Ch1 and Ch8 deviate by exactly the same
# amount in opposite directions, so each pair is one slower and one
# faster copy of the same material.
mirrorA# = { 1, 2, 3, 4 }
mirrorB# = { 8, 7, 6, 5 }

if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 symmetric speed pairs"
    mapLine$ = "Ch1|Ch8  Ch2|Ch7  Ch3|Ch6  Ch4|Ch5  (mirrored about unison)"
elsif output_format = 3
    formatName$ = "2 quad groups"
    mapLine$ = "quad 1 = Ch1-Ch4    quad 2 = Ch5-Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "1=Ch1+Ch8  2=Ch2+Ch7  3=Ch3+Ch6  4=Ch4+Ch5"
else
    formatName$ = "Stereo mix (L Ch1-4 / R Ch5-8)"
    mapLine$ = "L = Ch1+Ch2+Ch3+Ch4    R = Ch5+Ch6+Ch7+Ch8"
endif

needFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needFold = 1
endif

# Bank fold: Ch1-4 left, Ch5-8 right. In Automatic and Ascending that
# is the slower bank against the faster one; Descending reverses it.
if needFold
    selectObject: channel[1], channel[2], channel[3], channel[4]
    Combine to stereo
    bank1 = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "sd_mixL"
    removeObject: bank1

    selectObject: channel[5], channel[6], channel[7], channel[8]
    Combine to stereo
    bank2 = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "sd_mixR"
    removeObject: bank2
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
# Channels have different durations by design. Combine to stereo pads
# the shorter ones with silence and the result runs to the longest,
# which is exactly what this script wants.
stopwatch
downmixNorm = 0
monitorID = 0

if output_format = 1
    selectObject: channel[1], channel[2]
    Combine to stereo
    pair12 = selected("Sound")
    selectObject: channel[3], channel[4]
    Combine to stereo
    pair34 = selected("Sound")
    selectObject: channel[5], channel[6]
    Combine to stereo
    pair56 = selected("Sound")
    selectObject: channel[7], channel[8]
    Combine to stereo
    pair78 = selected("Sound")
    selectObject: pair12, pair34
    Combine to stereo
    quad1234 = selected("Sound")
    selectObject: pair56, pair78
    Combine to stereo
    quad5678 = selected("Sound")
    selectObject: quad1234, quad5678
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_8chSpeed_" + presetName$
    outCount = 1
    outChannels = 8
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

elsif output_format = 2
    for k from 1 to 4
        selectObject: channel[mirrorA#[k]], channel[mirrorB#[k]]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: originalName$ + "_speed_pair_" + string$(mirrorA#[k])
            ... + string$(mirrorB#[k]) + "_" + presetName$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    selectObject: channel[1], channel[2], channel[3], channel[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_speed_quad_1to4_" + presetName$
    selectObject: channel[5], channel[6], channel[7], channel[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_speed_quad_5to8_" + presetName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for k from 1 to 4
        selectObject: channel[mirrorA#[k]], channel[mirrorB#[k]]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "sd_fold" + string$(k)
        removeObject: foldPair
    endfor
    selectObject: fold[1], fold[2], fold[3], fold[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_speed_fold4_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_speed_stereo_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "sd_monitor"
    Scale peak: scale_peak
endif

if needFold
    removeObject: mixL, mixR
endif

combineElapsed = stopwatch

selectObject: out[1]
finalDur = Get total duration

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel Speed Deviations v0.5 ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(original_dur, 2), " s @ ",
    ... original_sr, " Hz)"
appendInfoLine: "Preset: ", presetName$
if mode = 1
    appendInfoLine: "Mode: Automatic, deviation factor ", fixed$(speed_deviation_factor, 3)
    if devClamped = 1
        appendInfoLine: "  NOTE: factor clamped into 0 to 0.95. At 1.0 channel 1 would"
        appendInfoLine: "        have speed 0, and above 1.0 a negative speed, so D/s"
        appendInfoLine: "        would be undefined."
    endif
elsif mode = 2
    appendInfoLine: "Mode: Manual"
else
    appendInfoLine: "Mode: Random, uniform over ", fixed$(random_min_speed, 3), " to ",
        ... fixed$(random_max_speed, 3)
    if seedApplied = 1
        appendInfoLine: "  Seed ", random_seed, " - reproducible; generator restored to"
        appendInfoLine: "  unpredictable afterwards."
    else
        appendInfoLine: "  Seed 0 - unpredictable, this run is not reproducible."
    endif
endif
if override_sampling_frequency
    appendInfoLine: "Sampling frequency: resampled to ", target_sampling_frequency, " Hz"
else
    appendInfoLine: "Sampling frequency: source rate preserved (", original_sr, " Hz)"
endif
appendInfoLine: ""

appendInfoLine: "A speed factor is not a duration percentage: duration is D / s."
appendInfoLine: "  -15% speed gives +17.65% duration; +15% speed gives -13.04%."
appendInfoLine: "  The speed set is symmetric about 1, the durations are not."
appendInfoLine: "Each channel holds ONE constant speed for its whole length; the"
appendInfoLine: "speed changes between channels, not within one."
appendInfoLine: "PSOLA aims to preserve perceived pitch while changing duration."
appendInfoLine: "  That depends on the pitch analysis succeeding between ",
    ... fixed$(min_pitch, 0), " and ", fixed$(max_pitch, 0), " Hz."
appendInfoLine: "  Polyphonic, noisy or poorly tracked material will show artefacts."
appendInfoLine: ""

appendInfoLine: "Channels (requested vs achieved):"
sumSpeed = 0
sumDur = 0
for i from 1 to 8
    pct = (speedFactor[i] - 1) * 100
    sumSpeed = sumSpeed + speedFactor[i]
    sumDur = sumDur + dur[i]
    if pct >= 0
        pctStr$ = "+" + fixed$(pct, 1) + "%"
    else
        pctStr$ = fixed$(pct, 1) + "%"
    endif
    appendInfoLine: "  Ch", i, ": ", fixed$(speedFactor[i], 4), "x (", pctStr$,
        ... ")  ->  ", fixed$(dur[i], 3), " s   achieved ",
        ... fixed$(achieved[i], 4), "x  (err ", fixed$(speedErr[i], 4), "x, ",
        ... fixed$(durErr[i] * 1000, 1), " ms)"
endfor
appendInfoLine: "  Mean speed ", fixed$(sumSpeed / 8, 4), "x   mean duration ",
    ... fixed$(sumDur / 8, 3), " s   (original ", fixed$(original_dur, 3), " s)"
appendInfoLine: "  The mean duration exceeds the original even when the mean speed"
appendInfoLine: "  is exactly 1, because 1/s is convex."
if slowWarn > 0
    appendInfoLine: ""
    appendInfoLine: "  NOTE: ", slowWarn, " channel(s) outside 0.25x to 4x. A factor of"
    appendInfoLine: "        0.1 asks PSOLA for a tenfold stretch; it runs, but the"
    appendInfoLine: "        result degrades."
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
if output_format = 2 or output_format = 4
    for k from 1 to 4
        appendInfoLine: "  Pair ", k, ": Ch", mirrorA#[k], " (",
            ... fixed$(speedFactor[mirrorA#[k]], 3), "x) + Ch", mirrorB#[k], " (",
            ... fixed$(speedFactor[mirrorB#[k]], 3), "x)   mean ",
            ... fixed$((speedFactor[mirrorA#[k]] + speedFactor[mirrorB#[k]]) / 2, 4), "x"
    endfor
else
    appendInfoLine: "  ", mapLine$
endif
appendInfoLine: "Final duration: ", fixed$(finalDur, 3),
    ... " s (runs to the slowest channel)"

appendInfoLine: ""
appendInfoLine: "Normalisation:"
if allSilent = 1
    appendInfoLine: "  All output channels are silent; shared normalisation was skipped."
else
    appendInfoLine: "  Shared gain across all eight channels: x", fixed$(sharedGain, 4),
        ... " (from peak ", fixed$(peakAll, 4), ")"
endif
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif
appendInfoLine: ""
appendInfoLine: "(processing ", fixed$(processElapsed, 2), " s   combine ",
    ... fixed$(combineElapsed, 2), " s)"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all

    for ch from 1 to 8
        sf = speedFactor[ch]
        if sf < 1.0
            intensity = (1.0 - sf) / 0.5
            if intensity > 1
                intensity = 1
            endif
            chColR[ch] = 0.22 + intensity * 0.05
            chColG[ch] = 0.45 - intensity * 0.15
            chColB[ch] = 0.78 + intensity * 0.15
            if chColB[ch] > 1
                chColB[ch] = 1
            endif
        elsif sf > 1.0
            intensity = (sf - 1.0) / 0.5
            if intensity > 1
                intensity = 1
            endif
            chColR[ch] = 0.78 + intensity * 0.15
            if chColR[ch] > 1
                chColR[ch] = 1
            endif
            chColG[ch] = 0.42 - intensity * 0.18
            if chColG[ch] < 0
                chColG[ch] = 0
            endif
            chColB[ch] = 0.24 - intensity * 0.12
            if chColB[ch] < 0
                chColB[ch] = 0
            endif
        else
            chColR[ch] = 0.45
            chColG[ch] = 0.45
            chColB[ch] = 0.45
        endif
    endfor

    maxDur = dur[1]
    minSpeed = speedFactor[1]
    maxSpeed = speedFactor[1]
    for ch from 2 to 8
        if dur[ch] > maxDur
            maxDur = dur[ch]
        endif
        if speedFactor[ch] < minSpeed
            minSpeed = speedFactor[ch]
        endif
        if speedFactor[ch] > maxSpeed
            maxSpeed = speedFactor[ch]
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPEED DEVIATIONS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if mode = 1
        modeStr$ = "Auto ±" + fixed$(speed_deviation_factor * 100, 0) + "%"
    elsif mode = 2
        modeStr$ = "Manual"
    else
        modeStr$ = "Random " + fixed$(random_min_speed, 2) + "-"
            ... + fixed$(random_max_speed, 2) + " seed " + string$(random_seed)
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$ + " / " + modeStr$
        ... + "  |  " + fixed$(original_dur, 2) + " s"
        ... + "  |  Speed " + fixed$(minSpeed, 2) + "-" + fixed$(maxSpeed, 2) + "x"
        ... + "  |  " + formatName$

    # ----------------------------------------------------------
    # PANEL A: DRIFT DIAGRAM  (left column)
    # ----------------------------------------------------------
    # v0.5: drawn from the MEASURED durations, so the slope is the
    # achieved speed rather than the requested one. The v0.3 comment
    # claimed y = t * s, which is exact only if D_i is exactly D / s.
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.85, 4.34

    Axes: 0, maxDur * 1.04, 0, original_dur * 1.04
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxDur * 1.04, 0, original_dur * 1.04

    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    Draw line: 0, 0, original_dur, original_dur

    for ch from 1 to 8
        Colour: "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        Line width: 2
        Draw line: 0, 0, dur[ch], original_dur
        Font size: 6
        Text: dur[ch], "left", original_dur * 0.985, "half", " " + string$(ch)
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Output time (s)  — slope = achieved speed"
    Select outer viewport: 0.08, 0.52, 0.75, 4.6
    Select inner viewport: 0.08, 0.52, 0.77, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Source consumed (s)"
    Select outer viewport: 0, 4.2, 0.75, 4.6
    Select inner viewport: 0.55, 4, 0.85, 4.34
    Axes: 0, maxDur * 1.04, 0, original_dur * 1.04

    # ----------------------------------------------------------
    # PANEL B: SPEED DEVIATION BARS  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48

    devMax = abs((minSpeed - 1) * 100)
    if abs((maxSpeed - 1) * 100) > devMax
        devMax = abs((maxSpeed - 1) * 100)
    endif
    if devMax < 5
        devMax = 5
    endif
    devMax = devMax * 1.18

    Axes: -devMax, devMax, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -devMax, devMax, 0.5, 8.5

    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: 0, 0.5, 0, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        pctV = (speedFactor[ch] - 1) * 100
        colStr$ = "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        if pctV >= 0
            Paint rectangle: colStr$, 0, pctV, y - 0.38, y + 0.38
        else
            Paint rectangle: colStr$, pctV, 0, y - 0.38, y + 0.38
        endif
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: -devMax * 0.97, "left", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if abs(pctV) > devMax * 0.18
            Text: pctV / 2, "centre", y, "half", fixed$(speedFactor[ch], 3) + "x"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.75, 2.70
    Select inner viewport: 4.02, 4.4, 0.77, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Ch"
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48
    Axes: -devMax, devMax, 0.5, 8.5
    Text bottom: "yes", "Speed deviation from unison (%)"

    # ----------------------------------------------------------
    # PANEL C: DURATION OUTCOME  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38

    Axes: 0, maxDur * 1.10, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxDur * 1.10, 0.5, 8.5

    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: original_dur, 0.5, original_dur, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        colStr$ = "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        Paint rectangle: colStr$, 0, dur[ch], y - 0.38, y + 0.38
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: maxDur * 0.02, "left", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if dur[ch] > maxDur * 0.30
            Text: dur[ch] * 0.6, "centre", y, "half", fixed$(dur[ch], 2) + "s"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 3.00, 4.60
    Select inner viewport: 4.02, 4.4, 3.02, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Ch"
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, maxDur * 1.10, 0.5, 8.5
    Text bottom: "yes", "Duration (s)  — dotted = original " + fixed$(original_dur, 2) + "s"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Drift: source consumed vs output time"
    Text: 6.10, "centre", 7.30, "half", "Speed deviation (upper) & duration (lower)"

    # ----------------------------------------------------------
    # PANEL D: TWO CHANNEL EXAMPLES (full width)
    # ----------------------------------------------------------
    # v0.3 titled this "Output 8-ch mix" but drew channels 1 and 2.
    # They are two of the eight variations, not a mix.
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72

    selectObject: channel[1]
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: channel[8]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Axes: 0, maxDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, maxDur, 0

    selectObject: channel[1]
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: channel[8]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Channel examples  (blue = Ch1 " + fixed$(speedFactor[1], 3)
        ... + "x,  orange = Ch8 " + fixed$(speedFactor[8], 3)
        ... + "x)  — the two ends of the pair set"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, maxDur, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 7.08
    Select inner viewport: 0.55, 7.72, 6.26, 7.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Source " + fixed$(original_dur, 2) + " s"
        ... + "  |  Output " + fixed$(finalDur, 2) + " s"
        ... + "  |  Mean speed " + fixed$(sumSpeed / 8, 3) + "x"
        ... + "  |  Mean dur " + fixed$(sumDur / 8, 2) + " s"

    Text: 0.02, "left", 0.45, "half",
        ... "Speeds:  "
        ... + fixed$(speedFactor[1], 2) + "  " + fixed$(speedFactor[2], 2)
        ... + "  " + fixed$(speedFactor[3], 2) + "  " + fixed$(speedFactor[4], 2)
        ... + "  " + fixed$(speedFactor[5], 2) + "  " + fixed$(speedFactor[6], 2)
        ... + "  " + fixed$(speedFactor[7], 2) + "  " + fixed$(speedFactor[8], 2)
        ... + "   [Ch1-Ch8]  |  PSOLA " + fixed$(min_pitch, 0) + "-"
        ... + fixed$(max_pitch, 0) + " Hz"

    Text: 0.02, "left", 0.18, "half",
        ... "Format: " + formatName$
        ... + "  |  " + string$(outCount) + objWord$
        ... + " x " + string$(outChannels) + " ch"
        ... + "  |  " + mapLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.18
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoID
for i from 1 to 8
    removeObject: channel[i]
endfor

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel, ",
        ... fixed$(finalDur, 2), " s"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels, "-channel each"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview, L = Ch1-Ch4, R = Ch5-Ch8."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

if monitorID <> 0
    removeObject: monitorID
endif

# === Select the output object(s) ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
