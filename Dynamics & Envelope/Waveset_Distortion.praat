# ============================================================
# Praat AudioTools - Waveset_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True waveset distortion based on CDP concepts.
#   Wavesets = segments between zero-crossings.
#
#   v1.0 rewrites the pipeline:
#   - Zero-crossing detection via To PointProcess (zeroes) (C-level)
#   - Each waveset extracted via Extract part (C-level)
#   - Processing via Sound-level operations (Reverse, Formula)
#   - Assembly via batched Concatenate
#   - Zero per-sample scripting loops
#
#   v1.1 adds CDP distort_shuf behaviour:
#   - Randomize mode now supports GROUP-based shuffle (CDP DISTORTS_CYCLECNT
#     / DISTORTS_DMNCNT concept): wavesets are first partitioned into groups
#     of <group_size>, then the groups themselves are shuffled (Fisher-Yates),
#     preserving local micro-structure while scrambling macro-order.
#   - Group size 1 reproduces the original individual-waveset shuffle.
#   - Repeat decay factor is now an explicit user parameter.
#
#   v1.2 adds CDP distort_del behaviour (two new types):
#   - Keep Strongest: wavesets are grouped in windows of <group_size>;
#     within each group only the single waveset with the highest energy
#     (sum of absolute sample values — matching CDP's DISTDEL_CYCLEVAL
#     accumulation) is kept; the rest are discarded. Produces a sparse,
#     percussive thinning effect.
#   - Delete Weakest: same grouping, but only the quietest waveset is
#     removed and all others are kept. Produces subtle noise-reduction /
#     cleaning at the waveset level.
#   Both modes measure loudness the way CDP does: sum |sample| over the
#   full waveset. (v1.2 and v1.3 used Get energy, which is sum x^2 and
#   ranks differently; corrected in v1.4.)
#
#   v1.4 fixes what a runtime review found:
#   - Multichannel input is now an explicit choice, and it is reported.
#     v1.3 folded every stereo file to mono SILENTLY, so the output was
#     always 1 channel with no mention of it, and anti-phase material
#     (L = s, R = -s) cancelled to silence and died with "Not enough
#     zero crossings found." Folding stays the default so existing
#     workflows keep running, but it now prints what it did and falls
#     back to channel 1 when the fold cancels. "Use channel 1 only" and
#     "Stop" are the other options. Waveset segmentation is a mono
#     operation either way - zero crossings of one channel are not zero
#     crossings of another - so the output is always single-channel.
#   - The material before the first crossing and after the last is kept.
#     v1.3 processed only the span between them and discarded the rest:
#     Reverse on a 50 ms 80 Hz sine returned 24.99 ms, and a file of
#     100 ms silence + 400 ms tone came back starting with the tone at
#     time 0. Preserve_length did not put it back; it padded the end.
#   - Telescope's fallback path ran at all. "Get number of points - 1"
#     was parsed as a command name and aborted the script on noise, on
#     40 Hz and 70 Hz sines, and on anything unpitched in 75-600 Hz;
#     the same branch also removed telePitch twice.
#   - Compress no longer depends on the sampling rate. The virtual rate
#     was capped at 96 kHz, so at 96 kHz a x2 compress did almost
#     nothing and at 192 kHz it STRETCHED (200 ms -> 391 ms). It now
#     resamples down and overrides back, which needs no high rate.
#   - Keep/Delete rank by sum |x| as CDP does, not by Get energy
#     (sum x^2). The two disagree: [1,0,0,0] beats [0.4,0.4,0.4] on
#     energy and loses on CDP's measure.
#   - Peak normalization is now a choice, default a safety ceiling that
#     only attenuates. v1.3 always ran Scale peak, so a file peaking at
#     0.01 came out at 0.95, about +39.6 dB.
#   - Repeat_decay renamed Repeat_level_multiplier, since values above 1
#     grow rather than decay, and mode-dependent validation added.
#   - Telescope reports pitch periods rather than zero-crossing
#     wavesets, and Amount is shown only for the modes that read it.
#
#   v1.5, after the follow-up review confirmed the v1.4 fixes:
#   - Telescope is no longer gated behind zero crossings. v1.4 always ran
#     To PointProcess (zeroes) first and exited on "Not enough zero
#     crossings found" before the pitch detector was ever reached, so a
#     plainly pitched 0.5 + 0.2*sin(2*pi*220t) - periodic, but never
#     crossing zero - was rejected. Telescope now tries pitch first and
#     only falls back to zero crossings, failing only if both come up
#     short.
#   - Modes 1-9 accept 2 crossings, which already bound one complete
#     waveset. v1.4 demanded 3.
#   - The fallback is reported as what it is. v1.4 printed "N pitch
#     periods" even when those N were zero-crossing wavesets.
#   - Skip, Reverse, Randomize and Amplitude change no durations, so
#     their output length is now matched to the source exactly. Extract
#     and concatenate rounded each boundary to the sample grid and the
#     error accumulated (1 s in, 1.000204 s out - nine samples).
#   - The menu entry is "Pitch-Synchronous Telescope (CDP-inspired)":
#     the main path uses pitch-synchronous boundaries, which is not what
#     CDP's distort_tel does, though the fallback path is CDP-style.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Waveset processing is mono: see Multichannel_handling.
# ============================================================

form Waveset Distortion v1.5
    optionmenu Preset: 1
        option Custom
        option Waveset Repeat (stutter)
        option Waveset Skip (gaps)
        option Waveset Reverse
        option Waveset Stretch
        option Waveset Compress
        option Waveset Shuffle (individual)
        option Waveset Shuffle (groups, CDP)
        option Waveset Amplitude
        option Keep Strongest (CDP)
        option Delete Weakest (CDP)
        option Pitch-Synchronous Telescope (CDP-inspired)
    comment === Input ===
    optionmenu Multichannel_handling: 1
        option Fold to mono
        option Use channel 1 only
        option Stop (refuse multichannel input)
    comment (waveset boundaries are per-channel: output is always mono)
    comment === Parameters ===
    optionmenu Type: 1
        option Repeat
        option Skip
        option Reverse
        option Stretch
        option Compress
        option Randomize
        option Amplitude
        option Keep Strongest
        option Delete Weakest
        option Pitch-Sync Telescope
    positive Amount 2.0
    comment --- Repeat only ---
    positive Repeat_level_multiplier 0.8
    comment (per repetition: 1 = no change, below 1 decays, above 1 grows)
    comment --- Randomize / Keep-Delete / Telescope: group size ---
    positive Group_size 4
    comment --- Telescope only ---
    optionmenu Telescope_mode: 1
        option Longest cycle (CDP default)
        option Mean cycle length
    boolean Preserve_length 0
    comment (matches total seconds only: trims the tail if long, pads if short)
    boolean Keep_head_and_tail 1
    comment (material before the first and after the last zero crossing)
    comment === Output ===
    optionmenu Output_level_mode: 2
        option None (leave level as processed)
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === PRESETS ===
presetName$ = "Custom"

if preset = 2
    type = 1
    amount = 2.0
    presetName$ = "WavesetRepeat"
elsif preset = 3
    type = 2
    amount = 2.0
    presetName$ = "WavesetSkip"
elsif preset = 4
    type = 3
    amount = 1.0
    presetName$ = "WavesetReverse"
elsif preset = 5
    type = 4
    amount = 2.0
    presetName$ = "WavesetStretch"
elsif preset = 6
    type = 5
    amount = 2.0
    presetName$ = "WavesetCompress"
elsif preset = 7
    type = 6
    amount = 1.0
    group_size = 1
    presetName$ = "WavesetShuffleIndividual"
elsif preset = 8
    type = 6
    amount = 1.0
    group_size = 4
    presetName$ = "WavesetShuffleGroups"
elsif preset = 9
    type = 7
    amount = 2.0
    presetName$ = "WavesetAmplitude"
elsif preset = 10
    type = 8
    amount = 1.0
    group_size = 4
    presetName$ = "KeepStrongest"
elsif preset = 11
    type = 9
    amount = 1.0
    group_size = 4
    presetName$ = "DeleteWeakest"
elsif preset = 12
    type = 10
    amount = 1.0
    group_size = 4
    telescope_mode = 1
    presetName$ = "Telescope"
endif

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
original_duration = Get total duration
sampling_rate = Get sampling frequency
numChannels = Get number of channels

if original_duration < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# Clamp group_size (need at least 2 for energy modes to be meaningful,
# but allow 1 for individual waveset shuffle)
groupSz = round(group_size)
if groupSz < 1
    groupSz = 1
endif
if (type = 8 or type = 9 or type = 10) and groupSz < 2
    groupSz = 2
endif

# --- Mode-dependent validation ---
# Amount means something different in every mode, so it is checked per mode.
if type = 1
    repeatCount = round(amount)
    if repeatCount < 1
        exitScript: "Repeat needs Amount of at least 1 (got " + fixed$(amount, 2) +
        ... "). Amount is a copy count and is rounded: 2.5 gives 3 copies."
    endif
    if repeatCount > 64
        exitScript: "Repeat count of " + string$(repeatCount) +
        ... " is beyond the practical limit of 64 copies per waveset."
    endif
elsif type = 2
    if amount < 1
        exitScript: "Skip needs Amount of at least 1 (got " + fixed$(amount, 2) +
        ... "). The silencing probability is 1 / Amount, so anything below 1 " +
        ... "silences every waveset."
    endif
elsif type = 4 or type = 5
    if amount <= 0 or amount > 100
        exitScript: "Stretch/Compress needs Amount greater than 0 and at most 100 (got " +
        ... fixed$(amount, 3) + ")."
    endif
elsif type = 7
    if amount <= 0
        exitScript: "Amplitude needs Amount greater than 0 (got " + fixed$(amount, 3) +
        ... "); alternate wavesets are scaled by Amount and by 1 / Amount."
    endif
endif

if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(ceiling_peak, 3) + ")."
endif

# Does this mode actually read Amount?
usesAmount = 1
if type = 3 or type = 6 or type = 8 or type = 9 or type = 10
    usesAmount = 0
endif

maxWavesets = 100000

# Type name
if type = 1
    typeName$ = "Repeat"
elsif type = 2
    typeName$ = "Skip"
elsif type = 3
    typeName$ = "Reverse"
elsif type = 4
    typeName$ = "Stretch"
elsif type = 5
    typeName$ = "Compress"
elsif type = 6
    if groupSz > 1
        typeName$ = "Randomize (groups=" + string$(groupSz) + ")"
    else
        typeName$ = "Randomize"
    endif
elsif type = 8
    typeName$ = "Keep Strongest (group=" + string$(groupSz) + ")"
elsif type = 9
    typeName$ = "Delete Weakest (group=" + string$(groupSz) + ")"
elsif type = 10
    if telescope_mode = 1
        teleModeName$ = "longest"
    else
        teleModeName$ = "mean"
    endif
    typeName$ = "Pitch-Sync Telescope (group=" + string$(groupSz) + ", " + teleModeName$ + ")"
else
    typeName$ = "Amplitude"
endif

clearinfo
writeInfoLine: "=== Waveset Distortion v1.5 ==="
appendInfoLine: "Input: ", soundName$, " (", fixed$(original_duration, 2), " s, ",
    ... sampling_rate, " Hz)"
appendInfoLine: "Preset: ", presetName$
if usesAmount
    appendInfoLine: "Type: ", typeName$, "  Amount: ", fixed$(amount, 1)
else
    appendInfoLine: "Type: ", typeName$, "  (Amount is not used by this mode)"
endif
if type = 1
    appendInfoLine: "Repeat level multiplier: ", fixed$(repeat_level_multiplier, 2)
endif
if type = 6 and groupSz > 1
    appendInfoLine: "Group size: ", groupSz, " wavesets per group (CDP distort_shuf)"
endif
if type = 8 or type = 9
    appendInfoLine: "Group size: ", groupSz, " wavesets per group (CDP distort_del)"
endif
if type = 10
    appendInfoLine: "Group size: ", groupSz, " wavesets per group (CDP distort_tel)"
    appendInfoLine: "Ref length: ", teleModeName$
endif
appendInfoLine: ""

startTime = stopwatch

# ============================================================
# STEP 1: FIND ZERO CROSSINGS (C-level)
# ============================================================

appendInfoLine: "[1/3] Finding zero crossings..."

# Waveset segmentation is a mono operation: a zero crossing in one
# channel is not a zero crossing in another, so there is no shared set of
# boundaries for a multichannel file. v1.3 folded silently, which threw
# away the spatial image and, on anti-phase material, the signal itself.
selectObject: sound
srcPeak = Get absolute extremum: 0, 0, "None"

if numChannels > 1
    if multichannel_handling = 3
        exitScript: "This Sound has " + string$(numChannels) + " channels, and " +
        ... "Multichannel_handling is set to Stop." + newline$ + newline$ +
        ... "Waveset processing is defined on a single channel: a zero crossing in one " +
        ... "channel is not one in another, so there is no shared set of boundaries. " +
        ... "Set Multichannel_handling to ""Fold to mono"" or ""Use channel 1 only"", or " +
        ... "process each channel separately and recombine them yourself."
    elsif multichannel_handling = 1
        selectObject: sound
        monoWork = Convert to mono
        selectObject: monoWork
        foldPeak = Get absolute extremum: 0, 0, "None"
        if foldPeak < 0.1 * srcPeak
            # Channels are largely out of phase and cancelled each other.
            appendInfoLine: "  WARNING: folding to mono cancelled the signal (fold peak ",
            ... fixed$(foldPeak, 5), " against source peak ", fixed$(srcPeak, 5), ")."
            appendInfoLine: "           Using channel 1 instead."
            removeObject: monoWork
            selectObject: sound
            monoWork = Extract one channel: 1
            channelNote$ = "channel 1 (fold cancelled)"
        else
            channelNote$ = "folded to mono"
        endif
    else
        selectObject: sound
        monoWork = Extract one channel: 1
        channelNote$ = "channel 1 only"
    endif
    appendInfoLine: "  Multichannel input (", numChannels, " ch): ", channelNote$
else
    selectObject: sound
    monoWork = Copy: "mono_work"
    channelNote$ = "mono"
endif

selectObject: monoWork
srcStart = Get start time
srcEnd = Get end time

# --- Boundary detection ---
# Telescope segments on PITCH periods, so it tries the pitch detector
# FIRST and only falls back to zero crossings. v1.4 always ran the
# zero-crossing pass up front and exited on "Not enough zero crossings
# found" before Telescope ever reached To Pitch: a clearly pitched
# 0.5 + 0.2*sin(2*pi*220t) never crosses zero and was rejected outright.
ppZeroes = 0
n_crossings = 0
n_wavesets = 0
telescopeUsedFallback = 0
telePitch = 0
telePP = 0
telePP_use = 0
n_periods = 0

if type = 10
    appendInfoLine: "  Detecting pitch periods..."
    selectObject: monoWork
    telePitch = To Pitch: 0.01, 75, 600
    selectObject: telePitch
    plusObject: monoWork
    telePP = To PointProcess (cc)
    selectObject: telePP
    n_pulses = Get number of points

    if n_pulses >= groupSz + 1
        telePP_use = telePP
        n_periods = n_pulses - 1
        appendInfoLine: "  Pitch periods: ", n_periods
    else
        appendInfoLine: "  Not enough pitched periods for telescope (", n_pulses, " pulses)."
        appendInfoLine: "  Falling back to zero-crossing wavesets."
        selectObject: monoWork
        ppZeroes = To PointProcess (zeroes): 1, "yes", "no"
        selectObject: ppZeroes
        n_crossings = Get number of points
        if n_crossings < 2
            removeObject: telePitch, telePP, ppZeroes, monoWork
            exitScript: "Telescope found neither enough pitch periods (" + string$(n_pulses) +
            ... " pulses, needs " + string$(groupSz + 1) + ") nor enough zero crossings (" +
            ... string$(n_crossings) + ", needs 2)."
        endif
        telePP_use = ppZeroes
        n_periods = n_crossings - 1
        telescopeUsedFallback = 1
        appendInfoLine: "  Zero-crossing wavesets: ", n_periods
    endif
    n_boundaries = n_periods + 1
    segCountForCheck = n_periods
else
    selectObject: monoWork
    ppZeroes = To PointProcess (zeroes): 1, "yes", "no"
    selectObject: ppZeroes
    n_crossings = Get number of points

    # Two crossings already bound one complete waveset; v1.4 demanded three.
    if n_crossings < 2
        removeObject: ppZeroes, monoWork
        exitScript: "Not enough zero crossings found (" + string$(n_crossings) +
        ... "; at least 2 are needed to bound one waveset)."
    endif

    n_wavesets = n_crossings - 1
    appendInfoLine: "  Crossings: ", n_crossings, " (", n_wavesets, " wavesets)"
    boundaryPP = ppZeroes
    n_boundaries = n_crossings
    segCountForCheck = n_wavesets
endif

if segCountForCheck > maxWavesets
    if ppZeroes <> 0
        removeObject: ppZeroes
    endif
    if telePitch <> 0
        removeObject: telePitch, telePP
    endif
    removeObject: monoWork
    exitScript: "This Sound has " + string$(segCountForCheck) + " segments, beyond the limit of " +
    ... string$(maxWavesets) + ". Use a shorter selection."
endif

if type = 10
    boundaryPP = telePP_use
endif

# ============================================================
# HEAD AND TAIL
# ============================================================
# Everything before the first boundary and after the last one, cut from
# whichever PointProcess this run actually segments on. v1.3 dropped
# both: Reverse on a 50 ms 80 Hz sine returned 24.99 ms, and a file that
# opened with silence came back opening with the tone.
selectObject: boundaryPP
firstCross = Get time from index: 1
lastCross = Get time from index: n_boundaries

headDur = firstCross - srcStart
tailDur = srcEnd - lastCross
headWS = 0
tailWS = 0

if keep_head_and_tail
    if headDur > 0.5 / sampling_rate
        selectObject: monoWork
        Extract part: srcStart, firstCross, "rectangular", 1, "no"
        headWS = selected("Sound")
        Rename: "ws_head"
    endif
    if tailDur > 0.5 / sampling_rate
        selectObject: monoWork
        Extract part: lastCross, srcEnd, "rectangular", 1, "no"
        tailWS = selected("Sound")
        Rename: "ws_tail"
    endif
    appendInfoLine: "  Head kept: ", fixed$(headDur * 1000, 2), " ms | Tail kept: ",
    ... fixed$(tailDur * 1000, 2), " ms"
else
    appendInfoLine: "  Head/tail discarded: ", fixed$((headDur + tailDur) * 1000, 2),
    ... " ms of the source is dropped (Keep_head_and_tail is off)"
endif

# ============================================================
# TYPE 10: TELESCOPE (CDP distort_tel) — separate code path
# ============================================================
#
# CDP's telescope collapses N consecutive wavesets into one:
#   1. Collect a group of N wavesets
#   2. Find reference length (longest or mean cycle)
#   3. For each output sample at proportional position ratio:
#        sum each waveset's value at that same ratio, then average
#   4. Output 1 averaged waveform per group
#
# This is time compression with timbral smoothing — N cycles become
# one "consensus" waveform.  Transients vanish, noise drops by sqrt(N),
# pitch is preserved.  Sounds focused, crystallised, telescoped.
#
# In Praat, we extract each waveset, time-stretch it to the reference
# length via the SR override trick, then average column-by-column.
# This avoids the object[id, col_vs_time] ambiguity in Praat formulas.
#
# NOTE: Telescope uses PITCH-SYNCHRONOUS boundaries (not raw zero
# crossings) so that each waveset is one complete pitch period.
# This produces meaningful averaging — N similar wavecycles merge
# into a consensus waveform — rather than sub-cycle fragment averaging.

if type = 10
    appendInfoLine: "[2/3] Telescoping (group=", groupSz, ", ref=", teleModeName$, ")..."

    # Boundaries were resolved in STEP 1 (pitch first, zero crossings as
    # fallback), and the head and tail were cut from whichever of the two
    # this run is segmenting on.


    n_full_groups = floor(n_periods / groupSz)
    remainder = n_periods - n_full_groups * groupSz

    batchSize = 100
    batchCount = 0
    resultParts = 0

    for gIdx from 1 to n_full_groups
        groupStart = (gIdx - 1) * groupSz + 1

        # Collect period boundaries and durations
        refDur = 0
        sumDur = 0
        for m from 1 to groupSz
            pp = groupStart + m - 1
            selectObject: telePP_use
            grpT1[m] = Get time from index: pp
            grpT2[m] = Get time from index: pp + 1
            grpDur[m] = grpT2[m] - grpT1[m]
            sumDur = sumDur + grpDur[m]
            if grpDur[m] > refDur
                refDur = grpDur[m]
            endif
        endfor

        if telescope_mode = 2
            refDur = sumDur / groupSz
        endif

        if refDur < 2 / sampling_rate
            refDur = 2 / sampling_rate
        endif

        # ---- Extract each waveset and resample to refDur ----
        # CDP's indexed_value reads each waveset at proportional
        # position ratio.  We achieve this by time-stretching each
        # waveset to refDur using the SR override trick, then
        # averaging column-by-column.
        for m from 1 to groupSz
            selectObject: monoWork
            Extract part: grpT1[m], grpT2[m], "rectangular", 1, "no"
            grpWS[m] = selected("Sound")

            # Time-stretch to refDur using SR override
            selectObject: grpWS[m]
            wsDur = Get total duration
            if abs(wsDur - refDur) > 0.5 / sampling_rate
                fakeSR = max(100, round(sampling_rate * wsDur / refDur))
                Override sampling frequency: fakeSR
                Resample: sampling_rate, 50
                stretched = selected("Sound")
                removeObject: grpWS[m]
                grpWS[m] = stretched
            endif
        endfor

        # Average all normalised wavesets (column-by-column)
        selectObject: grpWS[1]
        Copy: "tele"
        teleWS = selected("Sound")
        for m from 2 to groupSz
            selectObject: teleWS
            Formula: "self + object[" + string$(grpWS[m]) + ", col]"
        endfor
        selectObject: teleWS
        Formula: "self / " + string$(groupSz)

        # Cleanup individual wavesets
        for m from 1 to groupSz
            removeObject: grpWS[m]
        endfor

        # Accumulate into batch
        batchCount = batchCount + 1
        batchWS[batchCount] = teleWS

        if batchCount >= batchSize or gIdx = n_full_groups
            selectObject: batchWS[1]
            for b from 2 to batchCount
                plusObject: batchWS[b]
            endfor
            if batchCount > 1
                Concatenate
                batchResult = selected("Sound")
                for b from 1 to batchCount
                    removeObject: batchWS[b]
                endfor
            else
                batchResult = batchWS[1]
            endif
            resultParts = resultParts + 1
            resultPart[resultParts] = batchResult
            batchCount = 0
        endif

        if gIdx mod 200 = 0 or gIdx = n_full_groups
            appendInfoLine: "  Group ", gIdx, " / ", n_full_groups
        endif
    endfor

    # Handle remainder periods (pass through unmodified)
    if remainder > 0
        for m from 1 to remainder
            pp = n_full_groups * groupSz + m
            selectObject: telePP_use
            t1 = Get time from index: pp
            t2 = Get time from index: pp + 1
            selectObject: monoWork
            Extract part: t1, t2, "rectangular", 1, "no"
            remWS = selected("Sound")
            batchCount = batchCount + 1
            batchWS[batchCount] = remWS
        endfor
        selectObject: batchWS[1]
        for b from 2 to batchCount
            plusObject: batchWS[b]
        endfor
        if batchCount > 1
            Concatenate
            batchResult = selected("Sound")
            for b from 1 to batchCount
                removeObject: batchWS[b]
            endfor
        else
            batchResult = batchWS[1]
        endif
        resultParts = resultParts + 1
        resultPart[resultParts] = batchResult
    endif

    # Final concatenation of batches
    if resultParts > 1
        selectObject: resultPart[1]
        for rp from 2 to resultParts
            plusObject: resultPart[rp]
        endfor
        Concatenate
        result = selected("Sound")
        for rp from 1 to resultParts
            removeObject: resultPart[rp]
        endfor
    else
        result = resultPart[1]
    endif

    # Cleanup telescope objects (single site, both paths).
    # ppZeroes only exists when the pitch detector came up short.
    removeObject: telePitch, telePP
    if ppZeroes <> 0
        removeObject: ppZeroes
    endif

else

# ============================================================
# TYPES 1-9: EXISTING PROCESSING
# ============================================================

# STEP 2: MEASURE WAVESET ENERGIES (types 8 and 9 only)

if type = 8 or type = 9
    appendInfoLine: "  Measuring waveset loudness (CDP sum |x|)..."
    # CDP's DISTDEL_CYCLEVAL accumulates absolute sample magnitudes, i.e.
    # sum |x|. v1.3 used Get energy, which is sum x^2 - a different
    # ranking, not a monotone proxy: [1, 0, 0, 0] wins on energy (1.0 vs
    # 0.48) and loses on CDP's measure (1.0 vs 1.2) against
    # [0.4, 0.4, 0.4].
    # One rectified copy serves every waveset, so no per-waveset Extract
    # is needed: mean |x| over the span, times the span, is proportional
    # to the sum.
    selectObject: monoWork
    absWork = Copy: "abs_work"
    Formula: "abs(self)"

    for ws from 1 to n_wavesets
        selectObject: ppZeroes
        t1 = Get time from index: ws
        t2 = Get time from index: ws + 1
        selectObject: absWork
        wsMeanAbs = Get mean: t1, t2
        if wsMeanAbs = undefined
            wsMeanAbs = 0
        endif
        wsEnergy[ws] = wsMeanAbs * (t2 - t1)
    endfor

    removeObject: absWork
endif

# ============================================================
# STEP 3: BUILD PLAYBACK ORDER (shuffle types)
# ============================================================

appendInfoLine: "[2/3] Processing (", typeName$, ")..."

# Initialise sequential order (identity permutation)
for ws from 1 to n_wavesets
    wsOrder[ws] = ws
endfor

if type = 6
    if groupSz = 1
        # Individual waveset shuffle
        # Ascending Fisher-Yates (Praat can't do descending for-loops)
        for ws from 1 to n_wavesets - 1
            j = randomInteger(ws, n_wavesets)
            tmp = wsOrder[ws]
            wsOrder[ws] = wsOrder[j]
            wsOrder[j] = tmp
        endfor
    else
        # CDP group-based shuffle (distort_shuf / do_shuffle)
        n_groups = floor(n_wavesets / groupSz)
        remainder = n_wavesets - n_groups * groupSz
        for g from 1 to n_groups
            groupOrder[g] = g
        endfor
        # Ascending Fisher-Yates on group indices
        for g from 1 to n_groups - 1
            j = randomInteger(g, n_groups)
            tmp = groupOrder[g]
            groupOrder[g] = groupOrder[j]
            groupOrder[j] = tmp
        endfor
        outIdx = 0
        for g from 1 to n_groups
            srcGroup = groupOrder[g]
            for m from 1 to groupSz
                outIdx = outIdx + 1
                wsOrder[outIdx] = (srcGroup - 1) * groupSz + m
            endfor
        endfor
        # Tail remainder: append unshuffled (CDP behaviour)
        for m from 1 to remainder
            outIdx = outIdx + 1
            wsOrder[outIdx] = n_groups * groupSz + m
        endfor
    endif
endif

# ============================================================
# STEP 4: BUILD INCLUDE/EXCLUDE MAP (types 8 and 9)
# ============================================================
#
# Mirrors CDP's get_loudest_cycle / get_quietest_cycle + do_cycle_loud /
# do_cycle_quiet logic: scan each group of <groupSz> wavesets, identify
# the loudest or quietest by energy, then mark which to keep.
# Remainder wavesets (tail group) are always kept unchanged.

if type = 8 or type = 9
    # Default: include all
    for ws from 1 to n_wavesets
        wsInclude[ws] = 1
    endfor

    n_full_groups = floor(n_wavesets / groupSz)

    for g from 0 to n_full_groups - 1
        groupStart = g * groupSz + 1      
		# 1-based
        groupEnd   = groupStart + groupSz - 1

        loudestWS  = groupStart
        quietestWS = groupStart
        for ws from groupStart to groupEnd
            if wsEnergy[ws] > wsEnergy[loudestWS]
                loudestWS = ws
            endif
            if wsEnergy[ws] < wsEnergy[quietestWS]
                quietestWS = ws
            endif
        endfor

        if type = 8
            # KEEP_STRONGEST: discard all but the loudest
            for ws from groupStart to groupEnd
                if ws <> loudestWS
                    wsInclude[ws] = 0
                endif
            endfor
        elsif type = 9
            # DELETE_WEAKEST: discard only the quietest
            wsInclude[quietestWS] = 0
        endif
    endfor
endif

# ============================================================
# STEP 5: EXTRACT, PROCESS, AND BATCH-CONCATENATE WAVESETS
# ============================================================

batchSize = 100
batchCount = 0
resultParts = 0

for wsIdx from 1 to n_wavesets
    if type = 6
        ws = wsOrder[wsIdx]
    else
        ws = wsIdx
    endif

    # Skip excluded wavesets (types 8 and 9)
    if (type = 8 or type = 9) and wsInclude[ws] = 0
        goto nextWaveset
    endif

    # Get waveset boundaries
    selectObject: ppZeroes
    t1 = Get time from index: ws
    t2 = Get time from index: ws + 1

    # Extract waveset (C-level)
    selectObject: monoWork
    Extract part: t1, t2, "rectangular", 1, "no"
    wsSound = selected("Sound")

    # ---- Per-type processing ----

    if type = 1
        # REPEAT with user-controlled exponential decay
        reps = round(amount) - 1
        if reps > 0
            selectObject: wsSound
            Copy: "ws_rep"
            wsRepeated = selected("Sound")
            for r from 1 to reps
                selectObject: wsSound
                Copy: "ws_copy"
                repCopy = selected("Sound")
                decay = repeat_level_multiplier ^ r
                Formula: "self * " + fixed$(decay, 6)
                selectObject: wsRepeated
                plusObject: repCopy
                Concatenate
                newRep = selected("Sound")
                removeObject: wsRepeated, repCopy
                wsRepeated = newRep
            endfor
            removeObject: wsSound
            wsSound = wsRepeated
        endif

    elsif type = 2
        # SKIP
        if randomUniform(0, 1) < (1 / amount)
            selectObject: wsSound
            Formula: "0"
        endif

    elsif type = 3
        # REVERSE
        selectObject: wsSound
        Reverse

    elsif type = 4
        # STRETCH (SR override)
        selectObject: wsSound
        wsSR = Get sampling frequency
        newSR = max(100, round(wsSR / amount))
        Override sampling frequency: newSR
        Resample: wsSR, 50
        wsNew = selected("Sound")
        removeObject: wsSound
        selectObject: wsNew
        Override sampling frequency: wsSR
        wsSound = wsNew

    elsif type = 5
        # COMPRESS. Resample DOWN to sr / amount, then override the rate
        # back to sr: the sample count drops by the factor and the
        # duration follows, with no virtual rate involved.
        # v1.3 overrode UP to sr * amount and clamped that at 96 kHz, so
        # the achieved factor was 96000 / sr whenever sr * amount passed
        # the cap: at 96 kHz a x2 compress did nothing, and at 192 kHz it
        # stretched (200 ms became 391 ms).
        selectObject: wsSound
        wsSR = Get sampling frequency
        lowSR = max(100, wsSR / amount)
        Resample: lowSR, 50
        wsNew = selected("Sound")
        removeObject: wsSound
        selectObject: wsNew
        Override sampling frequency: wsSR
        wsSound = wsNew

    elsif type = 6
        # RANDOMIZE — order already resolved in wsOrder[], nothing extra needed

    elsif type = 7
        # AMPLITUDE alternating
        selectObject: wsSound
        if wsIdx mod 2 = 1
            Formula: "self * " + fixed$(amount, 4)
        else
            Formula: "self * " + fixed$(1 / amount, 4)
        endif

    # types 8 (Keep Strongest) and 9 (Delete Weakest):
    # waveset is already selected and included as-is; no further processing.

    endif

    # Accumulate into batch
    batchCount = batchCount + 1
    batchWS[batchCount] = wsSound

    if batchCount >= batchSize or wsIdx = n_wavesets
        selectObject: batchWS[1]
        for b from 2 to batchCount
            plusObject: batchWS[b]
        endfor
        if batchCount > 1
            Concatenate
            batchResult = selected("Sound")
            for b from 1 to batchCount
                removeObject: batchWS[b]
            endfor
        else
            batchResult = batchWS[1]
        endif
        resultParts = resultParts + 1
        resultPart[resultParts] = batchResult
        batchCount = 0
    endif

    if wsIdx mod 500 = 0 or wsIdx = n_wavesets
        appendInfoLine: "  Waveset ", wsIdx, " / ", n_wavesets
    endif

    label nextWaveset
endfor

# Flush any remaining batch (if last wavesets were excluded by goto)
if batchCount > 0
    selectObject: batchWS[1]
    for b from 2 to batchCount
        plusObject: batchWS[b]
    endfor
    if batchCount > 1
        Concatenate
        batchResult = selected("Sound")
        for b from 1 to batchCount
            removeObject: batchWS[b]
        endfor
    else
        batchResult = batchWS[1]
    endif
    resultParts = resultParts + 1
    resultPart[resultParts] = batchResult
    batchCount = 0
endif

# Final concatenation of batches
if resultParts > 1
    selectObject: resultPart[1]
    for rp from 2 to resultParts
        plusObject: resultPart[rp]
    endfor
    Concatenate
    result = selected("Sound")
    for rp from 1 to resultParts
        removeObject: resultPart[rp]
    endfor
else
    result = resultPart[1]
endif

removeObject: ppZeroes

endif
# ============================================================
# end of type=10 / types 1-9 branch
# ============================================================

# ============================================================
# REATTACH HEAD AND TAIL
# ============================================================
# Concatenate follows OBJECT-LIST order, not selection order, so the
# three segments are re-created here in the order they must play. The
# originals were made before processing and would otherwise sort ahead
# of the processed middle.

if keep_head_and_tail and (headWS <> 0 or tailWS <> 0)
    segCount = 0
    if headWS <> 0
        selectObject: headWS
        segCount = segCount + 1
        seg[segCount] = Copy: "seg_1_head"
    endif
    selectObject: result
    segCount = segCount + 1
    seg[segCount] = Copy: "seg_2_mid"
    if tailWS <> 0
        selectObject: tailWS
        segCount = segCount + 1
        seg[segCount] = Copy: "seg_3_tail"
    endif

    selectObject: seg[1]
    for sgi from 2 to segCount
        plusObject: seg[sgi]
    endfor
    Concatenate
    rejoined = selected("Sound")
    for sgi from 1 to segCount
        removeObject: seg[sgi]
    endfor
    removeObject: result
    result = rejoined
endif

if headWS <> 0
    removeObject: headWS
endif
if tailWS <> 0
    removeObject: tailWS
endif
removeObject: monoWork

# ============================================================
# EXACT LENGTH FOR TIME-PRESERVING MODES
# ============================================================
# Skip, Reverse, Randomize and Amplitude all reuse every waveset and
# change no durations, so the output should equal the source exactly.
# Extracting and re-concatenating rounds each boundary to the sample
# grid, which accumulated a few samples of drift (1.000204 s from a 1 s
# source, i.e. nine samples). Enforce the match rather than leaving it.
timePreserving = 0
if type = 2 or type = 3 or type = 6 or type = 7
    timePreserving = 1
endif

lengthEnforced = 0
if timePreserving and keep_head_and_tail and not preserve_length
    selectObject: result
    resDur = Get total duration
    driftSamples = round((resDur - original_duration) * sampling_rate)
    if abs(driftSamples) > 0
        if resDur > original_duration
            Extract part: 0, original_duration, "rectangular", 1, "no"
            trimmed = selected("Sound")
            removeObject: result
            result = trimmed
        else
            padDur = original_duration - resDur
            Create Sound from formula: "pad", 1, 0, padDur, sampling_rate, "0"
            padSound = selected("Sound")
            selectObject: result
            plusObject: padSound
            Concatenate
            padded = selected("Sound")
            removeObject: result, padSound
            result = padded
        endif
        lengthEnforced = driftSamples
    endif
endif

# ============================================================
# PRESERVE LENGTH (optional)
# ============================================================

if preserve_length
    selectObject: result
    resDur = Get total duration
    if resDur > original_duration
        Extract part: 0, original_duration, "rectangular", 1, "no"
        trimmed = selected("Sound")
        removeObject: result
        result = trimmed
    elsif resDur < original_duration - 0.001
        padDur = original_duration - resDur
        Create Sound from formula: "pad", 1, 0, padDur, sampling_rate, "0"
        padSound = selected("Sound")
        selectObject: result
        plusObject: padSound
        Concatenate
        padded = selected("Sound")
        removeObject: result, padSound
        result = padded
    endif
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: result
pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

if output_level_mode = 2
    # Attenuate only if above the ceiling; a quiet file stays quiet.
    # v1.3 always ran Scale peak, so a source peaking at 0.01 came out
    # at 0.95 - about +39.6 dB of gain for a process that does not
    # inherently change level.
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

Rename: soundName$ + "_WSD_" + presetName$
resultID = selected("Sound")
resultDur = Get total duration
out_peak = Get absolute extremum: 0, 0, "None"

processingTime = stopwatch

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "[3/3] Drawing..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Waveset Distortion##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if usesAmount
        titleAmount$ = " x" + fixed$(amount, 1)
    else
        titleAmount$ = ""
    endif
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$ + "  |  " + presetName$
        ... + "  |  " + typeName$ + titleAmount$

    Select outer viewport: 0, 8, 0.52, 1.52
    Select inner viewport: 0.55, 7.65, 0.57, 1.47
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn"
        vizIn = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    if numChannels > 1
        Text top: "no", "Input channel 1 of " + string$(numChannels) + "  (processed as " +
        ... channelNote$ + ")"
    endif

    Select outer viewport: 0, 8, 1.56, 2.56
    Select inner viewport: 0.55, 7.65, 1.61, 2.51
    selectObject: resultID
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 4.1, 2.64, 4.04
    Select inner viewport: 0.55, 3.85, 2.74, 3.94
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizSpecIn = selected("Sound")
    else
        Copy: "vizSpecIn"
        vizSpecIn = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig, vizSpecIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original"

    Select outer viewport: 4.1, 8, 2.64, 4.04
    Select inner viewport: 4.40, 7.65, 2.74, 3.94
    selectObject: resultID
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Waveset distortion"

    Select outer viewport: 0, 8, 4.14, 4.84
    Select inner viewport: 0.55, 7.65, 4.20, 4.78
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    if usesAmount
        amountStr$ = "  |  Amount: " + fixed$(amount, 1)
    else
        amountStr$ = "  |  Amount: n/a"
    endif
    if type = 10
        if telescopeUsedFallback
            segStr$ = "  |  ZC wavesets: " + string$(n_periods) + " (fallback)"
        else
            segStr$ = "  |  Periods: " + string$(n_periods)
        endif
    else
        segStr$ = "  |  Wavesets: " + string$(n_wavesets)
    endif
    if output_level_mode = 1
        levelStr$ = "none"
    elsif output_level_mode = 2
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2) + " (" + level_action$ + ")"
    else
        levelStr$ = "normalized to " + fixed$(ceiling_peak, 2)
    endif
    Text: 0.02, "left", 0.42, "half",
        ... "Type: " + typeName$
        ... + amountStr$
        ... + segStr$
        ... + "  |  In: " + fixed$(original_duration, 2) + "s"
        ... + "  ->  Out: " + fixed$(resultDur, 2) + "s"
        ... + "  |  Ch: " + channelNote$
        ... + "  |  Level: " + levelStr$
        ... + "  |  Time: " + fixed$(processingTime, 1) + "s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if type = 10
    # v1.3 printed the zero-crossing waveset count here even though
    # Telescope had segmented on pitch periods; v1.4 then called the
    # fallback's zero-crossing wavesets "pitch periods". Report what was
    # actually used.
    if telescopeUsedFallback
        appendInfoLine: "Segments: ", n_periods, " zero-crossing wavesets (Telescope fallback)"
    else
        appendInfoLine: "Segments: ", n_periods, " pitch periods (Telescope)"
    endif
else
    appendInfoLine: "Wavesets: ", n_wavesets
endif
if keep_head_and_tail
    appendInfoLine: "Head/tail: ", fixed$(headDur * 1000, 2), " ms + ",
    ... fixed$(tailDur * 1000, 2), " ms restored around the processed span"
endif
if lengthEnforced <> 0
    appendInfoLine: "Length matched to the source (this mode does not change time):",
    ... " corrected ", lengthEnforced, " sample(s) of extract/concatenate drift"
endif
if preserve_length
    appendInfoLine: "Preserve length: on - total seconds match the source, but the"
    appendInfoLine: "  material inside is not realigned (long output is trimmed at the"
    appendInfoLine: "  end, short output is padded with silence at the end)"
endif
appendInfoLine: "Peak before output stage: ", fixed$(pre_level_peak, 4)
if output_level_mode = 1
    appendInfoLine: "Output stage: none"
elsif output_level_mode = 2
    appendInfoLine: "Output stage: safety ceiling ", fixed$(ceiling_peak, 2), " - ", level_action$
else
    appendInfoLine: "Output stage: peak normalize to ", fixed$(ceiling_peak, 2),
    ... " (x", fixed$(level_gain, 4), ")"
endif
if output_level_mode <> 3 and out_peak > 1
    appendInfoLine: "WARNING: output peak exceeds 1.0 and will clip when saved to integer PCM."
endif
appendInfoLine: "In: ", fixed$(original_duration, 2), "s -> Out: ", fixed$(resultDur, 2), "s"
appendInfoLine: "Time: ", fixed$(processingTime, 1), " s"
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID
