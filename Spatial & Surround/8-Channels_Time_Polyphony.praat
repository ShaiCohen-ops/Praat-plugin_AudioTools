# ============================================================
# Praat AudioTools - 8-Channels_Time_Polyphony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# v0.6 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time Polyphony - 8 Channels.
#   Eight PSOLA copies of one source, each given its own constant
#   DURATION FACTOR, combined into a multichannel field. Output as
#   octophonic, stems, or a downmix.
#
#   Time_scale here is a DURATION factor, not a speed factor:
#       D_i = D * r_i
#   so r > 1 is longer and slower, r < 1 is shorter and faster. Note
#   this is the opposite convention to 8-channel_speed_deviations,
#   where the field is a speed factor and D_i = D / s_i. The fields
#   are named Duration_factor_N here to keep the two apart.
#
#   Each voice holds ONE constant factor for its whole length. Nothing
#   accelerates or decelerates within a voice; the drift is cumulative
#   between voices, which is a different thing.
#
# Changelog v0.6 (2026):
#   - NEW: per-voice edge fades. Each voice ended wherever PSOLA left
#     it, and if that last sample is not near zero the step to silence
#     clicks. Long voices running past the source length are correct
#     and are not truncated - D_i = D * r_i means r > 1 SHOULD outlast
#     the original - so the problem was never over-length material; it
#     was the unfaded edge at whatever length each voice reached.
#     End_fade defaults to 10 ms, Start_fade to 3 ms, both raised
#     cosine via Praat's Fade in/out rather than a linear ramp.
#     Applied to each voice immediately after resynthesis and BEFORE
#     the entry padding, the shared gain and the routing. That
#     placement is the point: with a common onset the shorter voices
#     end in the middle of the output object, so a fade applied to the
#     finished output would never reach them. Diverging can leave up to
#     eight separate hard edges scattered through the result;
#     Converging lines all eight endings up on the same sample, where
#     they add, which is where this is most audible.
#     Each fade is clamped to 10% of its own voice, so a 10 ms fade
#     does not swallow a short voice - the Glitch preset's 0.15 factor
#     on a 2 s source gives a 0.3 s voice, where the clamp caps the
#     fade at 30 ms.
#     The fades sit inside the existing time domain, so rawDur,
#     achieved factors, entry delays and the convergence arithmetic are
#     all unchanged.
#
# Changelog v0.4 (2026):
#   - FIX: the Converging and Diverging presets were swapped, and one
#     of them did nothing.
#       Old "Converging" used 0.7 ... 1.3 with a common onset. Voices
#       that start together and run at different constant rates can
#       only move apart: at a quarter through the source the spread is
#       1.50 s on a 10 s file, at half 3.00 s, at the end 6.00 s. That
#       is divergence.
#       Old "Diverging" set all eight factors to 1.0 - eight identical
#       synchronous copies, i.e. unison, with zero spread anywhere.
#     Now:
#       Diverging  - varied factors, common onset (the old Converging
#                    values, under the name that describes them).
#       Converging - the same factors with each voice delayed by
#                    Dmax - D_i, so the entries are staggered and all
#                    eight arrive at the end together. Verified: the
#                    spread runs 6.00, 4.50, 3.00, 1.50, 0.00 s and
#                    every voice ends on the same sample.
#       Unison     - all factors 1.0, named for what it is.
#     Delayed entrances are the only way to converge with constant
#     factors, so Converging now actually implements them.
#   - FIX: the input was never converted to mono. To Manipulation ran
#     on whatever was selected, so a stereo source did not reliably
#     yield eight channels. Converted first.
#   - FIX: the DurationTier was always created over 0 to originalDur
#     while the Manipulation carried the source's own time domain. A
#     Sound extracted with preserved times does not start at 0, and the
#     two domains would not line up. The working copy is normalised to
#     start at 0.
#   - FIX: no check that the duration factors are positive. The fields
#     are real, so 0 or a negative value was reachable, and a
#     DurationTier needs a positive factor. Validated, with a warning
#     for factors outside 0.25 to 4 - the Glitch preset already reaches
#     0.15, and Extreme reaches 4.0, where PSOLA quality falls off.
#   - FIX: pitch floor, ceiling and analysis step were hard-coded at
#     75 Hz, 600 Hz and 0.01 s. That suits speech and much vocal
#     material but not a bass instrument below 75 Hz or anything above
#     600 Hz, and the resynthesis quality depends directly on the pitch
#     analysis. All three are now form fields.
#   - WORDING: "each voice drifts at a different rate" implied r(t).
#     Each voice has a different CONSTANT factor; the drift between
#     voices accumulates. Stated properly.
#   - RENAME, for accuracy rather than modesty:
#       "Rhythmic Pulse" has no pulse or modulation - it is four voices
#         at 1.0 and four at 0.5, so it is named as a dual-rate field.
#       "Fast Chaos" is fixed and deterministic, with no randomness -
#         named an irregular fast field.
#       "Glitch Matrix" involves no matrix processing - kept as a
#         title, with the description saying wide mixed factors from
#         0.15 to 2.0.
#   - NEW: the number of DISTINCT duration factors is reported. Eight
#     output channels is not eight variations: the dual-rate preset has
#     2 distinct factors of 8, and Unison has 1.
#   - NEW: achieved duration factor measured as D_i / D and reported
#     against the requested one, so the report verifies PSOLA rather
#     than restating the parameter.
#   - NEW: Output_format menu, odd/even routing.
#       1  8 channels - octophonic     Ch1-Ch8
#       2  4 stereo pairs              Ch1|Ch2 Ch3|Ch4 Ch5|Ch6 Ch7|Ch8
#       3  2 quad groups               odd Ch1357, even Ch2468
#       4  4-channel fold-down         Ch1+Ch2, Ch3+Ch4, Ch5+Ch6, Ch7+Ch8
#       5  Stereo mix                  L: odd channels   R: even channels
#     Odd/even rather than Ch1-4 / Ch5-8, because these presets are
#     built by alternating: in Classic the odd channels mean 0.863 and
#     the even 1.188, where a positional split gives 1.075 against
#     0.975 - almost no separation. Dual-rate splits perfectly, 1.0
#     against 0.5. (The one preset where positional separates better is
#     Converging/Diverging, whose factors ascend rather than alternate.)
#   - NEW: shared gain across the eight voices for the stem formats;
#     the two summing formats normalise once after the sums. Format 1
#     is numerically unchanged from v0.3, which already scaled the
#     combined object once.
#   - NEW: monitoring mix for preview playback in the stem formats.
#   - FIX: the waveform panel was titled "Output 8-ch mix" but drew
#     channels 1 and 2. Renamed to channel examples, drawn from the
#     working voices so it is identical in every output format.
#
# Changelog v0.3:
#   - Visualization resized to the suite 8x8 standard, multi-panel.
# ============================================================

# === Check Input (before the form) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form Time Polyphony - 8 Channels
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Polyphony"
        option: "Slow Motion"
        option: "Irregular Fast Field (was Fast Chaos)"
        option: "Dual-Rate Field (4 at 1.0, 4 at 0.5)"
        option: "Subtle Variation"
        option: "Extreme Stretch"
        option: "Glitch Matrix (wide mixed factors 0.15-2.0)"
        option: "Diverging (varied factors, common onset)"
        option: "Converging (same factors, staggered entries)"
        option: "Unison (all factors 1.0)"

    comment === Duration factors (1.0 = normal, >1 = longer/slower) ===
    real Duration_factor_1 1.0
    real Duration_factor_2 1.15
    real Duration_factor_3 0.85
    real Duration_factor_4 1.3
    real Duration_factor_5 0.7
    real Duration_factor_6 1.1
    real Duration_factor_7 0.9
    real Duration_factor_8 1.2

    comment === Entry alignment ===
    optionmenu Alignment: 1
        option: "Common onset (voices start together, drift apart)"
        option: "Staggered entries (voices end together)"

    comment === Edge fades (applied per voice, before padding) ===
    real End_fade 0.010
    real Start_fade 0.003

    comment === PSOLA analysis ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Analysis_time_step 0.01

    comment === OUTPUT FORMAT ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 stereo pairs (Ch1|Ch2, Ch3|Ch4, Ch5|Ch6, Ch7|Ch8)"
        option: "2 quad groups (odd Ch1357, even Ch2468)"
        option: "4-channel fold-down (Ch1+Ch2, Ch3+Ch4, Ch5+Ch6, Ch7+Ch8)"
        option: "Stereo mix (L: odd channels, R: even channels)"

    comment === Output ===
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    duration_factor_1 = 1.0
    duration_factor_2 = 1.15
    duration_factor_3 = 0.85
    duration_factor_4 = 1.3
    duration_factor_5 = 0.7
    duration_factor_6 = 1.1
    duration_factor_7 = 0.9
    duration_factor_8 = 1.2
    presetName$ = "Classic"
elsif preset = 3
    duration_factor_1 = 1.5
    duration_factor_2 = 1.7
    duration_factor_3 = 1.3
    duration_factor_4 = 1.6
    duration_factor_5 = 1.4
    duration_factor_6 = 1.8
    duration_factor_7 = 1.2
    duration_factor_8 = 1.9
    presetName$ = "SlowMo"
elsif preset = 4
    duration_factor_1 = 0.5
    duration_factor_2 = 0.6
    duration_factor_3 = 0.4
    duration_factor_4 = 0.7
    duration_factor_5 = 0.3
    duration_factor_6 = 0.8
    duration_factor_7 = 0.25
    duration_factor_8 = 0.9
    presetName$ = "IrregularFast"
elsif preset = 5
    duration_factor_1 = 1.0
    duration_factor_2 = 0.5
    duration_factor_3 = 1.0
    duration_factor_4 = 0.5
    duration_factor_5 = 1.0
    duration_factor_6 = 0.5
    duration_factor_7 = 1.0
    duration_factor_8 = 0.5
    presetName$ = "DualRate"
elsif preset = 6
    duration_factor_1 = 1.0
    duration_factor_2 = 1.05
    duration_factor_3 = 0.98
    duration_factor_4 = 1.02
    duration_factor_5 = 0.95
    duration_factor_6 = 1.03
    duration_factor_7 = 0.97
    duration_factor_8 = 1.01
    presetName$ = "Subtle"
elsif preset = 7
    duration_factor_1 = 3.0
    duration_factor_2 = 2.5
    duration_factor_3 = 3.5
    duration_factor_4 = 2.0
    duration_factor_5 = 4.0
    duration_factor_6 = 2.2
    duration_factor_7 = 3.8
    duration_factor_8 = 2.7
    presetName$ = "Extreme"
elsif preset = 8
    duration_factor_1 = 0.15
    duration_factor_2 = 0.8
    duration_factor_3 = 0.3
    duration_factor_4 = 1.5
    duration_factor_5 = 0.2
    duration_factor_6 = 1.2
    duration_factor_7 = 0.4
    duration_factor_8 = 2.0
    presetName$ = "Glitch"
elsif preset = 9
    # v0.4: these are the values v0.3 called Converging. With a common
    # onset they move apart, so they are the DIVERGING set.
    duration_factor_1 = 0.7
    duration_factor_2 = 0.8
    duration_factor_3 = 0.9
    duration_factor_4 = 0.95
    duration_factor_5 = 1.05
    duration_factor_6 = 1.1
    duration_factor_7 = 1.2
    duration_factor_8 = 1.3
    alignment = 1
    presetName$ = "Diverging"
elsif preset = 10
    # v0.4: the same factors, but staggered so the voices end together.
    # This is what actually converges.
    duration_factor_1 = 0.7
    duration_factor_2 = 0.8
    duration_factor_3 = 0.9
    duration_factor_4 = 0.95
    duration_factor_5 = 1.05
    duration_factor_6 = 1.1
    duration_factor_7 = 1.2
    duration_factor_8 = 1.3
    alignment = 2
    presetName$ = "Converging"
elsif preset = 11
    # v0.4: what v0.3 called Diverging - eight identical copies.
    duration_factor_1 = 1.0
    duration_factor_2 = 1.0
    duration_factor_3 = 1.0
    duration_factor_4 = 1.0
    duration_factor_5 = 1.0
    duration_factor_6 = 1.0
    duration_factor_7 = 1.0
    duration_factor_8 = 1.0
    presetName$ = "Unison"
else
    presetName$ = "Custom"
endif

# === Guards ===
if pitch_floor >= pitch_ceiling
    exitScript: "Pitch_floor (", pitch_floor, ") must be below Pitch_ceiling (",
        ... pitch_ceiling, ")."
endif
if scale_peak <= 0 or scale_peak > 1
    scale_peak = 0.95
endif
if end_fade < 0
    end_fade = 0
endif
if start_fade < 0
    start_fade = 0
endif

scale[1] = duration_factor_1
scale[2] = duration_factor_2
scale[3] = duration_factor_3
scale[4] = duration_factor_4
scale[5] = duration_factor_5
scale[6] = duration_factor_6
scale[7] = duration_factor_7
scale[8] = duration_factor_8

# v0.4: a DurationTier needs a positive factor; the fields are real, so
# zero and negative values were reachable.
extremeCount = 0
for i from 1 to 8
    if scale[i] <= 0
        exitScript: "Duration factor ", i, " is ", scale[i],
            ... ". Every factor must be greater than 0."
    endif
    if scale[i] < 0.25 or scale[i] > 4
        extremeCount = extremeCount + 1
    endif
endfor

# Distinct factors: eight channels is not eight variations.
uniqueCount = 0
for i from 1 to 8
    isNew = 1
    for j from 1 to i - 1
        if abs(scale[i] - scale[j]) < 1e-9
            isNew = 0
        endif
    endfor
    uniqueCount = uniqueCount + isNew
endfor

# === Source: mono working copy, time domain starting at 0 ===
originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
sr = Get sampling frequency
numberOfChannels = Get number of channels
srcT0 = Get start time
srcT1 = Get end time

# v0.4: v0.3 ran To Manipulation on whatever was selected, so a stereo
# source did not reliably give eight channels.
if numberOfChannels > 1
    selectObject: originalID
    Convert to mono
    workID = selected("Sound")
else
    selectObject: originalID
    Copy: "tp_mono"
    workID = selected("Sound")
endif

# v0.4: the DurationTier was always built over 0 to originalDur while
# the Manipulation carried the source's own domain. Those disagree for
# any Sound extracted with preserved times.
selectObject: workID
workT0 = Get start time
if workT0 <> 0
    selectObject: workID
    shiftedID = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: workID
    workID = shiftedID
endif
selectObject: workID
Rename: "tp_work"
originalDur = Get total duration

if originalDur <= 0
    removeObject: workID
    exitScript: "Source has zero duration."
endif

# ============================================================
# BUILD THE EIGHT VOICES
# ============================================================
stopwatch
for i from 1 to 8
    selectObject: workID
    manip = To Manipulation: analysis_time_step, pitch_floor, pitch_ceiling

    durTier = Create DurationTier: "tp_dur", 0, originalDur
    Add point: 0, scale[i]
    Add point: originalDur, scale[i]

    selectObject: manip, durTier
    Replace duration tier

    selectObject: manip
    voice[i] = Get resynthesis (overlap-add)
    selectObject: voice[i]
    Rename: "tpVoice" + string$(i)

    removeObject: durTier, manip

    selectObject: voice[i]
    rawDur[i] = Get total duration

    # v0.4: measure what PSOLA actually produced rather than restating
    # the request.
    if originalDur > 0
        achieved[i] = rawDur[i] / originalDur
    else
        achieved[i] = scale[i]
    endif
    factorErr[i] = achieved[i] - scale[i]

    # --- v0.6: edge fades, per voice, here and nowhere else ---
    # A voice ends wherever PSOLA left it, and if that last sample is
    # not near zero the step to silence clicks. This has to happen on
    # each voice before the entry padding, the shared gain and the
    # routing: with a common onset the shorter voices end in the MIDDLE
    # of the output object, so a fade on the finished output would
    # never reach them. Diverging can therefore produce up to eight
    # separate hard edges; Converging lines all eight up on the same
    # sample, where they add.
    # The fade is inside the existing time domain, so rawDur, achieved,
    # the entry delays and the convergence arithmetic are all unchanged.
    # Praat's Fade in/out is a raised cosine (half-Hann), not a linear
    # ramp.
    fadeOutUse[i] = end_fade
    if fadeOutUse[i] > rawDur[i] * 0.1
        fadeOutUse[i] = rawDur[i] * 0.1
    endif
    fadeInUse[i] = start_fade
    if fadeInUse[i] > rawDur[i] * 0.1
        fadeInUse[i] = rawDur[i] * 0.1
    endif

    if fadeInUse[i] > 0
        selectObject: voice[i]
        Fade in: 0, 0, fadeInUse[i], "yes"
    endif
    if fadeOutUse[i] > 0
        selectObject: voice[i]
        Fade out: 0, rawDur[i], -fadeOutUse[i], "yes"
    endif
endfor
buildElapsed = stopwatch

# ============================================================
# ENTRY ALIGNMENT
# ============================================================
# Common onset: voices start together and move apart, since constant
# rates from a shared start can only diverge.
# Staggered: each voice is delayed by Dmax - D_i, so the entries fan
# out and all eight arrive at the end on the same sample. This is the
# only way constant factors can converge.

maxRaw = rawDur[1]
for i from 2 to 8
    if rawDur[i] > maxRaw
        maxRaw = rawDur[i]
    endif
endfor

staggered = 0
for i from 1 to 8
    if alignment = 2
        entryDelay[i] = maxRaw - rawDur[i]
    else
        entryDelay[i] = 0
    endif
endfor

for i from 1 to 8
    if entryDelay[i] > 1 / sr
        Create Sound from formula: "tp_pad", 1, 0, entryDelay[i], sr, "0"
        padID = selected("Sound")
        selectObject: padID, voice[i]
        Concatenate
        joinedID = selected("Sound")
        removeObject: padID, voice[i]
        voice[i] = joinedID
        selectObject: voice[i]
        Rename: "tpVoice" + string$(i)
        staggered = staggered + 1
    endif
    selectObject: voice[i]
    dur[i] = Get total duration
endfor

# ============================================================
# SHARED-GAIN NORMALISATION  (stage 1)
# ============================================================
peakAll = 0
for i from 1 to 8
    selectObject: voice[i]
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
        selectObject: voice[i]
        Formula: "self * " + sharedGain$
    endfor
endif

# ============================================================
# FORMAT LABELS
# ============================================================
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 stereo pairs"
    mapLine$ = "Ch1|Ch2   Ch3|Ch4   Ch5|Ch6   Ch7|Ch8"
elsif output_format = 3
    formatName$ = "2 quad groups (odd / even)"
    mapLine$ = "odd = Ch1 Ch3 Ch5 Ch7    even = Ch2 Ch4 Ch6 Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "1=Ch1+Ch2  2=Ch3+Ch4  3=Ch5+Ch6  4=Ch7+Ch8"
else
    formatName$ = "Stereo mix (L odd / R even)"
    mapLine$ = "L = Ch1+Ch3+Ch5+Ch7    R = Ch2+Ch4+Ch6+Ch8"
endif

needFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needFold = 1
endif

# Odd/even fold. These presets alternate rather than ascend, so odd
# against even separates the rates where a positional split does not:
# in Classic the odd voices mean 0.863 and the even 1.188, while
# Ch1-4 against Ch5-8 gives 1.075 against 0.975.
if needFold
    selectObject: voice[1], voice[3], voice[5], voice[7]
    Combine to stereo
    oddStack = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "tp_mixL"
    removeObject: oddStack

    selectObject: voice[2], voice[4], voice[6], voice[8]
    Combine to stereo
    evenStack = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "tp_mixR"
    removeObject: evenStack
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
# Voices have different durations by design. Combine to stereo pads the
# shorter ones with silence and the result runs to the longest.
stopwatch
downmixNorm = 0
monitorID = 0

if output_format = 1
    selectObject: voice[1], voice[2]
    Combine to stereo
    pair12 = selected("Sound")
    selectObject: voice[3], voice[4]
    Combine to stereo
    pair34 = selected("Sound")
    selectObject: voice[5], voice[6]
    Combine to stereo
    pair56 = selected("Sound")
    selectObject: voice[7], voice[8]
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
    Rename: originalName$ + "_8chTimePoly_" + presetName$
    outCount = 1
    outChannels = 8
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

elsif output_format = 2
    for k from 1 to 4
        selectObject: voice[2 * k - 1], voice[2 * k]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: originalName$ + "_timepoly_pair_" + string$(2 * k - 1)
            ... + string$(2 * k) + "_" + presetName$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    selectObject: voice[1], voice[3], voice[5], voice[7]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_timepoly_quad_odd_" + presetName$
    selectObject: voice[2], voice[4], voice[6], voice[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_timepoly_quad_even_" + presetName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for k from 1 to 4
        selectObject: voice[2 * k - 1], voice[2 * k]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "tp_fold" + string$(k)
        removeObject: foldPair
    endfor
    selectObject: fold[1], fold[2], fold[3], fold[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_timepoly_fold4_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_timepoly_stereo_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "tp_monitor"
    Scale peak: scale_peak
endif

if needFold
    removeObject: mixL, mixR
endif

combineElapsed = stopwatch

# v0.4: with several output objects there is no single "final"
# duration, so report the longest.
longestOut = 0
for k from 1 to outCount
    selectObject: out[k]
    thisOutDur = Get total duration
    if thisOutDur > longestOut
        longestOut = thisOutDur
    endif
endfor

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel Time Polyphony v0.6 ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(originalDur, 3), " s @ ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "PSOLA: pitch ", fixed$(pitch_floor, 0), "-", fixed$(pitch_ceiling, 0),
    ... " Hz, step ", fixed$(analysis_time_step, 4), " s"
appendInfoLine: ""

appendInfoLine: "Time_scale here is a DURATION factor: D_i = D * r_i."
appendInfoLine: "  r > 1 is longer and slower; r < 1 is shorter and faster."
appendInfoLine: "  This is the OPPOSITE convention to 8-channel_speed_deviations,"
appendInfoLine: "  where the field is a speed factor and D_i = D / s_i."
appendInfoLine: "Each voice holds ONE constant factor for its whole length. Nothing"
appendInfoLine: "accelerates within a voice; the drift accumulates between voices."
appendInfoLine: ""

if alignment = 2
    appendInfoLine: "Alignment: STAGGERED ENTRIES."
    appendInfoLine: "  Each voice is delayed by Dmax - D_i, so the entries fan out and"
    appendInfoLine: "  all eight arrive at the end together. The spread between voices"
    appendInfoLine: "  shrinks to zero: this converges."
    appendInfoLine: "  ", staggered, " voice(s) delayed; longest delay ",
        ... fixed$(maxRaw - rawDur[1], 3), " s or more."
else
    appendInfoLine: "Alignment: COMMON ONSET."
    appendInfoLine: "  All eight start together. Constant factors from a shared start"
    appendInfoLine: "  can only move apart, so the spread grows: this diverges."
endif
appendInfoLine: ""

appendInfoLine: "Voices (requested vs achieved duration factor):"
sumScale = 0
for i from 1 to 8
    sumScale = sumScale + scale[i]
    if entryDelay[i] > 1 / sr
        delayStr$ = "   entry +" + fixed$(entryDelay[i], 3) + " s"
    else
        delayStr$ = ""
    endif
    appendInfoLine: "  Ch", i, ": x", fixed$(scale[i], 4), "  ->  ",
        ... fixed$(rawDur[i], 3), " s   achieved x", fixed$(achieved[i], 4),
        ... "  (err ", fixed$(factorErr[i], 4), ")", delayStr$
endfor
appendInfoLine: "  Mean factor x", fixed$(sumScale / 8, 4)

appendInfoLine: ""
appendInfoLine: "Edge fades (raised cosine, applied per voice before padding):"
if end_fade > 0
    appendInfoLine: "  End fade ", fixed$(end_fade * 1000, 1),
        ... " ms requested, clamped to 10% of a voice where needed."
else
    appendInfoLine: "  End fade: off. Each voice ends wherever PSOLA left it, so a"
    appendInfoLine: "  non-zero last sample will click."
endif
if start_fade > 0
    appendInfoLine: "  Start fade ", fixed$(start_fade * 1000, 1), " ms."
else
    appendInfoLine: "  Start fade: off."
endif
fadeClamped = 0
for i from 1 to 8
    if fadeOutUse[i] < end_fade - 1e-12
        fadeClamped = fadeClamped + 1
    endif
endfor
if fadeClamped > 0
    appendInfoLine: "  ", fadeClamped, " short voice(s) had the end fade shortened:"
    for i from 1 to 8
        if fadeOutUse[i] < end_fade - 1e-12
            appendInfoLine: "    Ch", i, ": ", fixed$(rawDur[i], 3), " s voice -> ",
                ... fixed$(fadeOutUse[i] * 1000, 1), " ms fade"
        endif
    endfor
endif
if alignment = 2 and end_fade > 0
    appendInfoLine: "  Staggered mode lines all eight endings up on the same sample,"
    appendInfoLine: "  where the edges would otherwise add - the fade matters most here."
endif

appendInfoLine: ""
appendInfoLine: "Distinct duration factors: ", uniqueCount, " of 8"
if uniqueCount < 8
    appendInfoLine: "  Eight output channels, but only ", uniqueCount,
        ... " different variations; the rest"
    appendInfoLine: "  are duplicates of each other."
endif
if extremeCount > 0
    appendInfoLine: ""
    appendInfoLine: "  NOTE: ", extremeCount, " factor(s) outside 0.25 to 4. These run,"
    appendInfoLine: "        but PSOLA quality falls off, particularly on polyphonic,"
    appendInfoLine: "        noisy or unstably pitched material."
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
appendInfoLine: "  ", mapLine$
if output_format = 3 or output_format = 5
    oddMean = (scale[1] + scale[3] + scale[5] + scale[7]) / 4
    evenMean = (scale[2] + scale[4] + scale[6] + scale[8]) / 4
    appendInfoLine: "  odd mean factor x", fixed$(oddMean, 3),
        ... "   even mean factor x", fixed$(evenMean, 3)
endif
appendInfoLine: "Longest output-object duration: ", fixed$(longestOut, 3), " s"

appendInfoLine: ""
appendInfoLine: "Normalisation:"
if allSilent = 1
    appendInfoLine: "  All voices are silent; shared normalisation was skipped."
else
    appendInfoLine: "  Shared gain across all eight voices: x", fixed$(sharedGain, 4),
        ... " (from peak ", fixed$(peakAll, 4), ")"
endif
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif
appendInfoLine: ""
appendInfoLine: "(PSOLA ", fixed$(buildElapsed, 2), " s   combine ",
    ... fixed$(combineElapsed, 2), " s)"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all

    for ch from 1 to 8
        sf = scale[ch]
        if sf > 1.0
            intensity = (sf - 1.0) / 1.5
            if intensity > 1
                intensity = 1
            endif
            chColR[ch] = 0.22 + intensity * 0.05
            chColG[ch] = 0.45 - intensity * 0.15
            chColB[ch] = 0.78 + intensity * 0.15
            if chColB[ch] > 1
                chColB[ch] = 1
            endif
        elsif sf < 1.0
            intensity = (1.0 - sf) / 0.8
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
    minScale = scale[1]
    maxScale = scale[1]
    for ch from 2 to 8
        if dur[ch] > maxDur
            maxDur = dur[ch]
        endif
        if scale[ch] < minScale
            minScale = scale[ch]
        endif
        if scale[ch] > maxScale
            maxScale = scale[ch]
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL TIME POLYPHONY##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if alignment = 2
        alignStr$ = "staggered (converging)"
    else
        alignStr$ = "common onset (diverging)"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  Factors x" + fixed$(minScale, 2) + "-" + fixed$(maxScale, 2)
        ... + "  |  " + alignStr$
        ... + "  |  " + formatName$

    # ----------------------------------------------------------
    # PANEL A: DRIFT DIAGRAM  (left column)
    # ----------------------------------------------------------
    # Source position consumed against wall-clock output time, drawn
    # from the MEASURED durations and the entry delays, so it shows
    # whether the field converges or diverges rather than asserting it.
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.85, 4.34

    Axes: 0, maxDur * 1.04, 0, originalDur * 1.06
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxDur * 1.04, 0, originalDur * 1.06

    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    Draw line: 0, 0, originalDur, originalDur

    for ch from 1 to 8
        Colour: "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        Line width: 2
        Draw line: entryDelay[ch], 0, entryDelay[ch] + rawDur[ch], originalDur
        Font size: 6
        Text: entryDelay[ch] + rawDur[ch], "left", originalDur * 0.99, "half",
            ... " " + string$(ch)
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Output time (s)"
    Select outer viewport: 0.08, 0.52, 0.75, 4.6
    Select inner viewport: 0.08, 0.52, 0.77, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Source consumed (s)"
    Select outer viewport: 0, 4.2, 0.75, 4.6
    Select inner viewport: 0.55, 4, 0.85, 4.34
    Axes: 0, maxDur * 1.04, 0, originalDur * 1.06

    # ----------------------------------------------------------
    # PANEL B: DURATION FACTOR BARS  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48

    axMaxF = maxScale * 1.12
    if axMaxF < 1.2
        axMaxF = 1.2
    endif

    Axes: 0, axMaxF, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, axMaxF, 0.5, 8.5

    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: 1.0, 0.5, 1.0, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        colStr$ = "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        Paint rectangle: colStr$, 0, scale[ch], y - 0.38, y + 0.38
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: axMaxF * 0.015, "left", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if scale[ch] > axMaxF * 0.28
            Text: scale[ch] * 0.62, "centre", y, "half", "x" + fixed$(scale[ch], 2)
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
    Axes: 0, axMaxF, 0.5, 8.5
    Text bottom: "yes", "Duration factor  (dotted = x1, blue = longer, orange = shorter)"

    # ----------------------------------------------------------
    # PANEL C: DURATION OUTCOME AND ENTRY  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38

    Axes: 0, maxDur * 1.06, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxDur * 1.06, 0.5, 8.5

    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: originalDur, 0.5, originalDur, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        colStr$ = "{" + fixed$(chColR[ch], 2) + ", " + fixed$(chColG[ch], 2)
            ... + ", " + fixed$(chColB[ch], 2) + "}"
        # Entry delay drawn as a hollow lead-in, sound as the filled bar
        if entryDelay[ch] > 1 / sr
            Colour: "{0.80, 0.80, 0.80}"
            Draw rectangle: 0, entryDelay[ch], y - 0.30, y + 0.30
        endif
        Paint rectangle: colStr$, entryDelay[ch], entryDelay[ch] + rawDur[ch],
            ... y - 0.38, y + 0.38
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: maxDur * 0.015, "left", y, "half", "Ch" + string$(ch)
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
    Axes: 0, maxDur * 1.06, 0.5, 8.5
    Text bottom: "yes", "Entry (grey) and sounding span (s); dotted = source length"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Drift: source consumed vs output time"
    Text: 6.10, "centre", 7.30, "half", "Duration factors (upper) & spans (lower)"

    # ----------------------------------------------------------
    # PANEL D: TWO CHANNEL EXAMPLES (full width)
    # ----------------------------------------------------------
    # v0.3 titled this "Output 8-ch mix" but drew channels 1 and 2.
    # They are two of the eight voices, not a mix.
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72

    selectObject: voice[1]
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: voice[2]
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

    selectObject: voice[1]
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: voice[2]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Channel examples  (blue = Ch1 x" + fixed$(scale[1], 2)
        ... + ",  orange = Ch2 x" + fixed$(scale[2], 2)
        ... + ")  — two of eight voices"
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
        ... + "  |  Source " + fixed$(originalDur, 2) + " s"
        ... + "  |  Longest output " + fixed$(longestOut, 2) + " s"
        ... + "  |  Distinct factors " + string$(uniqueCount) + "/8"
        ... + "  |  " + alignStr$

    Text: 0.02, "left", 0.45, "half",
        ... "Factors:  "
        ... + fixed$(scale[1], 2) + "  " + fixed$(scale[2], 2)
        ... + "  " + fixed$(scale[3], 2) + "  " + fixed$(scale[4], 2)
        ... + "  " + fixed$(scale[5], 2) + "  " + fixed$(scale[6], 2)
        ... + "  " + fixed$(scale[7], 2) + "  " + fixed$(scale[8], 2)
        ... + "   [Ch1-Ch8]  |  PSOLA " + fixed$(pitch_floor, 0) + "-"
        ... + fixed$(pitch_ceiling, 0) + " Hz"
        ... + "  |  Fades " + fixed$(start_fade * 1000, 0) + "/"
        ... + fixed$(end_fade * 1000, 0) + " ms"

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
removeObject: workID
for i from 1 to 8
    removeObject: voice[i]
endfor

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel, ",
        ... fixed$(longestOut, 2), " s"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels,
        ... "-channel each, longest ", fixed$(longestOut, 2), " s"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview, L = odd voices, R = even voices."
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
