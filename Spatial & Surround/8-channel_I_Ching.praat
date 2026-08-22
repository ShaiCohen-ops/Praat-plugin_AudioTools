# ============================================================
# Praat AudioTools - 8-channel_I_Ching.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# v0.5.1 (2026): RUNTIME VISUAL QA - summary row collision fixed; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-channel I Ching: Form & Speed
#   Six coin-throw lines per channel decide slice reversals; the same
#   six lines read as a binary code decide a speed factor. Each channel
#   receives an independently generated hexagram, so eight variations
#   of one source are produced. Output as octophonic, stems, or a
#   downmix.
#
# Changelog v0.5.1 (2026):
#   The chance mechanism is corrected before the output work, because
#   several of the Cage options did not do what their names promised.
#
#   - FIX (critical): Random_seed did nothing. v0.3 only printed that a
#     seed had been "requested (for documentation purposes)" and never
#     touched the generator, so a stated seed gave no reproducibility
#     at all. Praat provides
#     random_initializeWithSeedUnsafelyButPredictably, which is now
#     called when a seed is given, and
#     random_initializeSafelyAndUnpredictably when it is 0.
#   - FIX: "Hex #0-63" was presented as if it were a hexagram number.
#     No hexagram is numbered 0; the canonical numbering is 1-64 in
#     King Wen order and is unrelated to the binary value of the lines.
#     The script now shows both: the King Wen number from a verified
#     64-entry table, and the binary code that actually drives the
#     speed. The report states plainly that speed comes from the binary
#     code, not from the hexagram's identity - line 6 moves the code by
#     32 and line 1 by 1, which is a property of base-2 encoding and
#     not of the I Ching.
#   - FIX: "Each channel gets a unique hexagram" was untrue. The eight
#     throws are independent, so the chance that all eight differ is
#     only 63.4%; about 36.6% of runs repeat at least one hexagram.
#     Reworded to "independently generated", and repeats are now
#     reported rather than hidden.
#   - FIX: the 4'33" silence gate was not a channel decision and had
#     almost nothing to do with the hexagram. It measured the peak
#     amplitude of the recombined channel, but reversing slices and
#     reordering them does not change a peak, so without pitch or
#     bracket processing all eight channels shared one peak and the
#     gate silenced all of them or none. Silence is now decided by its
#     own six-line throw per channel against a probability, which is a
#     chance operation in the spirit of the piece rather than a level
#     measurement.
#   - FIX: "Indeterminate pitch inversion" was neither indeterminate
#     nor an inversion - every Yin slice got the same fixed -0.5. It is
#     renamed to a pitch shift on Yin slices, and the depth is now
#     drawn from a fresh six-line throw per slice, so it really is
#     indeterminate. It is still a shift, not an inversion about an
#     axis: a true inversion needs a PitchTier manipulation rather than
#     a uniform PSOLA shift, and the option no longer claims otherwise.
#   - FIX: slices were cut with rectangular windows and butt-joined, so
#     every boundary could carry a discontinuity - worst after a
#     reversal, where the two sides of a joint are unrelated. A short
#     crossfade via Concatenate with overlap is now applied, so the
#     clicks in the result are not mistaken for chance decisions.
#   - FIX: variable slice count was not uniform. n = 4 + round(8h/63)
#     gave 4 and 12 four throws each and every inner value eight, so
#     the extremes were half as likely. One of the 64 states is now
#     rejected and the remaining 63 split into nine bins of exactly 7,
#     which is uniform and is itself a legitimate chance operation.
#   - FIX: the speed clamp destroyed uniformity. With Chaos the mapping
#     reaches 0 and everything below 0.1 was clamped, so codes 0, 1, 2
#     and 3 all produced exactly 0.1 - four of 64 states piled on one
#     value. The legal speed range is now computed first and the 64
#     codes are mapped uniformly onto it, so all 64 stay distinct.
#   - FIX: Slow Drift and Fast Drift were labelled 20% bias but set
#     0.15. Labels corrected to 15%; the values are unchanged so the
#     sound is unchanged. The report also prints the true speed range,
#     which for both drift presets crosses 1.0 - Slow Drift spans
#     0.65 to 1.05 and so includes faster results.
#   - FIX: Time bracket mode does not produce time brackets. It jitters
#     the boundaries of the source slices, which yields omissions,
#     overlaps of content and uneven lengths, but the slices are then
#     butt-joined, so there are no entry or exit windows, no silences
#     between events and no timeline. Renamed to jittered slice
#     boundaries; the homage is kept, the claim is not.
#   - FIX: the speed panel axis was fixed at 0 to 1.5 while Chaos
#     reaches 2.0, so the longest bars ran off the panel. The axis is
#     now derived from the largest speed factor actually produced.
#   - FIX: the waveform panel extracted channels 1 and 2 from the
#     8-channel result and called them L and R of a "stereo mix". They
#     are the first two variations, not a stereo image. It now draws
#     them from the working channels and labels them as examples.
#   - FIX: several stages read selected("Sound") immediately after
#     removeObject, which relies on the surviving object staying
#     selected. Object ids are now captured before the removal.
#   - FIX: channels have different durations by design, since each is
#     lengthened by its own speed factor. They are now explicitly
#     zero-padded to the longest before any Combine to stereo, rather
#     than depending on how Praat treats unequal inputs.
#   - FIX: input validation - Min_pitch below Max_pitch, non-negative
#     deviation, bounded jitter and probability, and a source whose
#     time domain does not start at 0.
#   - NEW: Output_format menu, functional routing since there is no
#     speaker geometry here.
#       1  8 channels - octophonic
#       2  4 stereo pairs        Ch1|Ch2 Ch3|Ch4 Ch5|Ch6 Ch7|Ch8
#       3  2 quad groups         Ch1-Ch4, Ch5-Ch8
#       4  4-channel fold-down   Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8
#       5  Stereo mix            L: odd channels   R: even channels
#     Odd/even is preferred to Ch1-4 / Ch5-8 for the stereo mix because
#     it splits each consecutive pair across the sides and spreads the
#     chance variation more evenly.
#   - NEW: shared gain across the eight channels for the stem formats;
#     the two summing formats sum first and normalise the finished
#     object once. Reported as two distinct stages.
#   - NEW: monitoring mix (L odd, R even) used for preview playback in
#     the stem formats, where playing the first stem alone would be a
#     quarter or a half of the result.
#
# Changelog v0.3:
#   - Resized visualization from 12x8 to 8x8 to match suite standard
#   - Multi-panel layout; Cage-inspired options added
# ============================================================

# === Check Input (before the form) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-channel I Ching Form & Speed
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Subtle (5% deviation)"
        option: "Moderate (20% deviation)"
        option: "Extreme (50% deviation)"
        option: "Chaos (100% deviation)"
        option: "Slow Drift (15% slower bias)"
        option: "Fast Drift (15% faster bias)"
        option: "Micro-variations (2% deviation)"

    comment === I Ching Configuration ===
    real Deviation_range 0.20
    real Speed_bias 0.0

    comment === Random seed (0 = unpredictable, >0 = reproducible) ===
    integer Random_seed 0

    comment === Audio Settings ===
    positive Min_pitch 75
    positive Max_pitch 600
    boolean Override_sampling_frequency 1
    positive Target_sampling_frequency 44100
    positive Slice_crossfade 0.005

    comment === Cage-inspired Options ===
    boolean Silence_by_chance_4_33 0
    real Silence_probability 0.05
    boolean Jittered_slice_boundaries 0
    real Boundary_jitter 0.15
    boolean Indeterminate_pitch_shift 0
    real Pitch_shift_centre -0.5
    real Pitch_shift_spread 0.4
    boolean Variable_slice_count 0

    comment === OUTPUT FORMAT ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 stereo pairs (Ch1|Ch2, Ch3|Ch4, Ch5|Ch6, Ch7|Ch8)"
        option: "2 quad groups (Ch1-Ch4, Ch5-Ch8)"
        option: "4-channel fold-down (Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8)"
        option: "Stereo mix (L: odd channels, R: even channels)"

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    deviation_range = 0.05
    speed_bias = 0.0
    presetName$ = "Subtle"
elsif preset = 3
    deviation_range = 0.20
    speed_bias = 0.0
    presetName$ = "Moderate"
elsif preset = 4
    deviation_range = 0.50
    speed_bias = 0.0
    presetName$ = "Extreme"
elsif preset = 5
    deviation_range = 1.00
    speed_bias = 0.0
    presetName$ = "Chaos"
elsif preset = 6
    deviation_range = 0.20
    speed_bias = -0.15
    presetName$ = "SlowDrift"
elsif preset = 7
    deviation_range = 0.20
    speed_bias = 0.15
    presetName$ = "FastDrift"
elsif preset = 8
    deviation_range = 0.02
    speed_bias = 0.0
    presetName$ = "Micro"
else
    presetName$ = "Custom"
endif

# === v0.5: actually seed the generator ===
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedApplied = 1
else
    random_initializeSafelyAndUnpredictably ()
    seedApplied = 0
endif

# === Input validation ===
if min_pitch >= max_pitch
    exitScript: "Min_pitch (", min_pitch, ") must be below Max_pitch (", max_pitch, ")."
endif
if deviation_range < 0
    deviation_range = 0
endif
if boundary_jitter < 0
    boundary_jitter = 0
endif
if boundary_jitter > 0.45
    boundary_jitter = 0.45
endif
if silence_probability < 0
    silence_probability = 0
endif
if silence_probability > 1
    silence_probability = 1
endif
if pitch_shift_spread < 0
    pitch_shift_spread = 0
endif

# Legal speed range, computed before the mapping rather than clamped
# after it, so that all 64 codes stay distinct.
sMin = 1 + speed_bias - deviation_range
sMax = 1 + speed_bias + deviation_range
if sMin < 0.1
    sMin = 0.1
endif
if sMax > 4.0
    sMax = 4.0
endif
if sMax < sMin + 0.001
    sMax = sMin + 0.001
endif

# === King Wen lookup, indexed by the binary line code 0-63 ===
# code = line1*1 + line2*2 + line3*4 + line4*8 + line5*16 + line6*32,
# lines counted from the bottom. Verified: all 64 entries distinct and
# covering 1-64.
kingWen[0] = 2
kingWen[1] = 24
kingWen[2] = 7
kingWen[3] = 19
kingWen[4] = 15
kingWen[5] = 36
kingWen[6] = 46
kingWen[7] = 11
kingWen[8] = 16
kingWen[9] = 51
kingWen[10] = 40
kingWen[11] = 54
kingWen[12] = 62
kingWen[13] = 55
kingWen[14] = 32
kingWen[15] = 34
kingWen[16] = 8
kingWen[17] = 3
kingWen[18] = 29
kingWen[19] = 60
kingWen[20] = 39
kingWen[21] = 63
kingWen[22] = 48
kingWen[23] = 5
kingWen[24] = 45
kingWen[25] = 17
kingWen[26] = 47
kingWen[27] = 58
kingWen[28] = 31
kingWen[29] = 49
kingWen[30] = 28
kingWen[31] = 43
kingWen[32] = 23
kingWen[33] = 27
kingWen[34] = 4
kingWen[35] = 41
kingWen[36] = 52
kingWen[37] = 22
kingWen[38] = 18
kingWen[39] = 26
kingWen[40] = 35
kingWen[41] = 21
kingWen[42] = 64
kingWen[43] = 38
kingWen[44] = 56
kingWen[45] = 30
kingWen[46] = 50
kingWen[47] = 14
kingWen[48] = 20
kingWen[49] = 42
kingWen[50] = 59
kingWen[51] = 61
kingWen[52] = 53
kingWen[53] = 37
kingWen[54] = 57
kingWen[55] = 9
kingWen[56] = 12
kingWen[57] = 25
kingWen[58] = 6
kingWen[59] = 10
kingWen[60] = 33
kingWen[61] = 13
kingWen[62] = 44
kingWen[63] = 1

# === Source ===
originalSound = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalSound
original_freq = Get sampling frequency
srcT0 = Get start time
srcT1 = Get end time

# v0.5: slice times are computed from 0. A Praat Sound need not start
# at 0 - anything extracted with preserved times does not - and every
# slice boundary would then be displaced by xmin.
ownWork = 0
if srcT0 <> 0
    selectObject: originalSound
    workSound = Extract part: srcT0, srcT1, "rectangular", 1.0, "no"
    Rename: "ic_work"
    ownWork = 1
else
    workSound = originalSound
endif
selectObject: workSound
original_dur = Get total duration

# === Per-channel state ===
for ch from 1 to 8
    hexValue[ch] = 0
    kingWenNo[ch] = 0
    speedFactor[ch] = 1.0
    yinCount[ch] = 0
    sliceCount[ch] = 6
    isSilent[ch] = 0
    silenceThrow[ch] = 0
endfor

# ============================================================
# MAIN LOOP - EIGHT INDEPENDENT CHANNELS
# ============================================================

for ch from 1 to 8

    # --- 1. HEXAGRAM: six coin throws, bottom line first ---
    for k from 1 to 6
        line[k] = randomInteger(0, 1)
    endfor

    hex_value = line[1] + line[2]*2 + line[3]*4 + line[4]*8 + line[5]*16 + line[6]*32
    hexValue[ch] = hex_value
    kingWenNo[ch] = kingWen[hex_value]

    # v0.5: uniform map onto the legal range. v0.3 mapped onto
    # [1+b-d, 1+b+d] and then clamped at 0.1, which piled several codes
    # onto one speed whenever the range reached below 0.1.
    speed_factor = sMin + (sMax - sMin) * (hex_value / 63)
    speedFactor[ch] = speed_factor

    yinCount[ch] = 0
    for k from 1 to 6
        if line[k] = 0
            yinCount[ch] = yinCount[ch] + 1
        endif
    endfor

    # --- 2. SLICE COUNT: uniform over 4..12 ---
    # One of the 64 states is rejected so the remaining 63 divide into
    # nine bins of exactly 7. v0.3's round(8h/63) gave 4 and 12 half the
    # weight of every inner value.
    if variable_slice_count
        hex2 = randomInteger(0, 63)
        rejects = 0
        while hex2 = 63 and rejects < 32
            hex2 = randomInteger(0, 63)
            rejects = rejects + 1
        endwhile
        if hex2 > 62
            hex2 = 62
        endif
        sliceCount[ch] = 4 + (hex2 div 7)
    else
        sliceCount[ch] = 6
    endif

    # --- 3. SLICING AND RECOMBINATION ---
    nSlices = sliceCount[ch]
    validSliceCount = 0
    shortestSlice = original_dur

    for s from 1 to nSlices
        startTime = (s - 1) * (original_dur / nSlices)
        endTime = s * (original_dur / nSlices)

        # Cage homage: jittered slice boundaries. This is not a time
        # bracket system - the slices are still joined end to end - but
        # it does give omissions, overlapped content and uneven lengths.
        if jittered_slice_boundaries
            jitterRange = (original_dur / nSlices) * boundary_jitter
            startTime = startTime + randomUniform(-jitterRange, jitterRange)
            endTime = endTime + randomUniform(-jitterRange, jitterRange)
            if startTime < 0
                startTime = 0
            endif
            if endTime > original_dur
                endTime = original_dur
            endif
            if startTime >= endTime
                endTime = startTime + 0.001
            endif
        endif

        if endTime > original_dur
            endTime = original_dur
        endif

        if endTime - startTime > 0.001
            selectObject: workSound
            Extract part: startTime, endTime, "rectangular", 1.0, "no"
            currentSliceID = selected("Sound")

            # Six line states cycled across the slices. This is one to
            # one only when nSlices = 6; otherwise lines repeat or the
            # top ones go unused, which the report states.
            lineIdx = ((s - 1) mod 6) + 1

            if line[lineIdx] = 0
                selectObject: currentSliceID
                Reverse

                # v0.5: depth drawn per slice, so the operation really
                # is indeterminate. It is a shift, not an inversion.
                if indeterminate_pitch_shift
                    hexP = randomInteger(0, 63)
                    shiftVal = pitch_shift_centre + pitch_shift_spread * (2 * (hexP / 63) - 1)
                    selectObject: currentSliceID
                    Shift pitch (PSOLA): min_pitch, max_pitch, shiftVal
                    shiftedID = selected("Sound")
                    if shiftedID <> currentSliceID
                        removeObject: currentSliceID
                        currentSliceID = shiftedID
                    endif
                endif
            endif

            selectObject: currentSliceID
            thisSliceDur = Get total duration
            if thisSliceDur < shortestSlice
                shortestSlice = thisSliceDur
            endif

            validSliceCount += 1
            sliceID[validSliceCount] = currentSliceID
        endif
    endfor

    if validSliceCount > 0
        selectObject: sliceID[1]
        for k from 2 to validSliceCount
            plusObject: sliceID[k]
        endfor

        # v0.5: short crossfade. Rectangular cuts butt-joined produce a
        # discontinuity at every boundary, worst after a reversal.
        ovl = slice_crossfade
        if ovl > shortestSlice * 0.4
            ovl = shortestSlice * 0.4
        endif
        if validSliceCount > 1 and ovl > 0
            Concatenate with overlap: ovl
        else
            Concatenate
        endif
        recombinedSound = selected("Sound")

        for k from 1 to validSliceCount
            removeObject: sliceID[k]
        endfor
    else
        selectObject: workSound
        Copy: "fallback"
        recombinedSound = selected("Sound")
    endif

    # --- 4. MONO ---
    # v0.5: capture the new id before removing the old one instead of
    # calling selected() after removeObject.
    selectObject: recombinedSound
    nChans = Get number of channels
    if nChans > 1
        Convert to mono
        monoTmp = selected("Sound")
        removeObject: recombinedSound
        recombinedSound = monoTmp
    endif

    # --- 5. SILENCE BY CHANCE (4'33" homage) ---
    # v0.5: its own six-line throw per channel. v0.3 measured the peak
    # amplitude of the recombined channel, which reversal and reordering
    # do not change, so all eight channels shared one peak and the gate
    # silenced everything or nothing.
    if silence_by_chance_4_33
        hexS = randomInteger(0, 63)
        silenceThrow[ch] = hexS
        if (hexS / 63) <= silence_probability
            isSilent[ch] = 1
            selectObject: recombinedSound
            dur_rc = Get total duration
            sr_rc = Get sampling frequency
            removeObject: recombinedSound
            Create Sound from formula: "silence_ch" + string$(ch), 1, 0, dur_rc, sr_rc, "0"
            recombinedSound = selected("Sound")
        endif
    endif

    # --- 6. SPEED AND RESAMPLE ---
    selectObject: recombinedSound
    dur_current = Get total duration
    Lengthen (overlap-add): min_pitch, max_pitch, 1 / speed_factor
    speedSound = selected("Sound")
    removeObject: recombinedSound

    selectObject: speedSound
    if override_sampling_frequency
        Resample: target_sampling_frequency, 50
    else
        Resample: original_freq, 50
    endif
    resampled = selected("Sound")
    removeObject: speedSound

    final_channels[ch] = resampled
    selectObject: resampled
    Rename: "icCh" + string$(ch)
endfor

if ownWork = 1
    removeObject: workSound
endif

# ============================================================
# PAD TO A COMMON DURATION
# ============================================================
# Each channel is lengthened by its own speed factor, so the eight
# differ in length by design. v0.5.1 pads them explicitly rather than
# relying on how Combine to stereo treats unequal inputs.

maxDur = 0
for ch from 1 to 8
    selectObject: final_channels[ch]
    chDur[ch] = Get total duration
    chSr = Get sampling frequency
    if chDur[ch] > maxDur
        maxDur = chDur[ch]
    endif
endfor

padded = 0
for ch from 1 to 8
    padDur = maxDur - chDur[ch]
    if padDur > 1 / chSr
        Create Sound from formula: "icpad", 1, 0, padDur, chSr, "0"
        padID = selected("Sound")
        selectObject: final_channels[ch], padID
        Concatenate
        joinedID = selected("Sound")
        removeObject: final_channels[ch], padID
        final_channels[ch] = joinedID
        selectObject: joinedID
        Rename: "icCh" + string$(ch)
        padded = padded + 1
    endif
endfor

# ============================================================
# SHARED-GAIN NORMALISATION  (stage 1)
# ============================================================
peakAll = 0
for ch from 1 to 8
    selectObject: final_channels[ch]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
if peakAll < 1e-9
    peakAll = 1e-9
endif
sharedGain = 0.95 / peakAll
sharedGain$ = fixed$(sharedGain, 10)
for ch from 1 to 8
    selectObject: final_channels[ch]
    Formula: "self * " + sharedGain$
endfor

# ============================================================
# ODD / EVEN FOLD  (stereo format, and the stem preview)
# ============================================================
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 stereo pairs"
    mapLine$ = "Ch1|Ch2   Ch3|Ch4   Ch5|Ch6   Ch7|Ch8"
elsif output_format = 3
    formatName$ = "2 quad groups"
    mapLine$ = "quad 1 = Ch1-Ch4    quad 2 = Ch5-Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "1=Ch1+Ch5  2=Ch2+Ch6  3=Ch3+Ch7  4=Ch4+Ch8"
else
    formatName$ = "Stereo mix (L odd / R even)"
    mapLine$ = "L = Ch1+Ch3+Ch5+Ch7    R = Ch2+Ch4+Ch6+Ch8"
endif

needFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needFold = 1
endif

if needFold
    selectObject: final_channels[1], final_channels[3], final_channels[5], final_channels[7]
    Combine to stereo
    oddStack = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "ic_mixL"
    removeObject: oddStack

    selectObject: final_channels[2], final_channels[4], final_channels[6], final_channels[8]
    Combine to stereo
    evenStack = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "ic_mixR"
    removeObject: evenStack
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
downmixNorm = 0
monitorID = 0

if output_format = 1
    selectObject: final_channels[1], final_channels[2], final_channels[3], final_channels[4],
        ... final_channels[5], final_channels[6], final_channels[7], final_channels[8]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_8chIChing_" + presetName$
    outCount = 1
    outChannels = 8

elsif output_format = 2
    for k from 1 to 4
        selectObject: final_channels[2 * k - 1], final_channels[2 * k]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: originalName$ + "_iching_pair_" + string$(2 * k - 1)
            ... + string$(2 * k) + "_" + presetName$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    selectObject: final_channels[1], final_channels[2], final_channels[3], final_channels[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_iching_quad_1to4_" + presetName$
    selectObject: final_channels[5], final_channels[6], final_channels[7], final_channels[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_iching_quad_5to8_" + presetName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for k from 1 to 4
        selectObject: final_channels[k], final_channels[k + 4]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "ic_fold" + string$(k)
        removeObject: foldPair
    endfor
    selectObject: fold[1], fold[2], fold[3], fold[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_iching_fold4_" + presetName$
    Scale peak: 0.95
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_iching_stereo_" + presetName$
    Scale peak: 0.95
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "ic_monitor"
    Scale peak: 0.95
endif

if needFold
    removeObject: mixL, mixR
endif

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel I Ching: Form & Speed ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(original_dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Deviation: +/-", fixed$(deviation_range * 100, 0), "%   bias: ",
    ... fixed$(speed_bias * 100, 0), "%"
appendInfoLine: "Speed range actually used: ", fixed$(sMin, 3), " to ", fixed$(sMax, 3), "x"
if sMin < 1 and sMax > 1
    appendInfoLine: "  (the range crosses 1.0, so this setting yields both slower and"
    appendInfoLine: "   faster channels regardless of the bias direction)"
endif
if seedApplied = 1
    appendInfoLine: "Random seed: ", random_seed, " - generator seeded, run is reproducible"
else
    appendInfoLine: "Random seed: 0 - generator unpredictable, run is not reproducible"
endif
appendInfoLine: ""

appendInfoLine: "Hexagram results (independently thrown per channel):"
for ch from 1 to 8
    appendInfoLine: "  Ch", ch, ": King Wen ", kingWenNo[ch], "   binary code ", hexValue[ch],
        ... "   ", fixed$(speedFactor[ch], 3), "x   Yin ", yinCount[ch], "/6   slices ",
        ... sliceCount[ch]
endfor

dupFound = 0
for a from 1 to 7
    for b from a + 1 to 8
        if hexValue[a] = hexValue[b]
            dupFound = dupFound + 1
        endif
    endfor
endfor
if dupFound > 0
    appendInfoLine: "  NOTE: ", dupFound, " repeated hexagram pair(s). The eight throws are"
    appendInfoLine: "        independent, so about 36.6% of runs repeat at least one."
endif

appendInfoLine: ""
appendInfoLine: "Speed comes from the BINARY CODE of the six lines, not from the"
appendInfoLine: "hexagram's identity: line 6 moves the code by 32 and line 1 by 1."
appendInfoLine: "That weighting is a property of base-2 encoding, not of the I Ching."
if variable_slice_count
    appendInfoLine: "Slice counts vary, so the six line states are cycled across the"
    appendInfoLine: "slices; the one-to-one line/slice relation holds only at 6 slices."
endif
if silence_by_chance_4_33
    silentCount = 0
    for ch from 1 to 8
        if isSilent[ch] = 1
            silentCount = silentCount + 1
        endif
    endfor
    probStates = 0
    for h from 0 to 63
        if (h / 63) <= silence_probability
            probStates = probStates + 1
        endif
    endfor
    appendInfoLine: ""
    appendInfoLine: "4'33 silence: separate six-line throw per channel."
    appendInfoLine: "  threshold ", fixed$(silence_probability, 3), " -> ", probStates,
        ... " of 64 states = ", fixed$(probStates / 64 * 100, 1), "% per channel"
    appendInfoLine: "  channels silenced this run: ", silentCount, " of 8"
    for ch from 1 to 8
        if isSilent[ch] = 1
            appendInfoLine: "    Ch", ch, " silent (silence throw ", silenceThrow[ch], ")"
        endif
    endfor
endif
if indeterminate_pitch_shift
    appendInfoLine: ""
    appendInfoLine: "Pitch shift on Yin slices: depth drawn per slice over ",
        ... fixed$(pitch_shift_centre - pitch_shift_spread, 2), " to ",
        ... fixed$(pitch_shift_centre + pitch_shift_spread, 2)
    appendInfoLine: "  This is a shift, not an inversion about an axis."
endif
if jittered_slice_boundaries
    appendInfoLine: ""
    appendInfoLine: "Jittered slice boundaries: +/-", fixed$(boundary_jitter * 100, 0),
        ... "% of a slice. Gives omissions, overlapped content and uneven"
    appendInfoLine: "  lengths - not entry/exit windows or silences between events."
endif
if padded > 0
    appendInfoLine: ""
    appendInfoLine: padded, " channel(s) zero-padded to the longest (", fixed$(maxDur, 2), " s)"
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
appendInfoLine: "  ", mapLine$
appendInfoLine: ""
appendInfoLine: "Normalisation:"
appendInfoLine: "  Shared gain across all eight channels: x", fixed$(sharedGain, 4),
    ... " (from peak ", fixed$(peakAll, 4), ")"
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak 0.950"
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
# The working channels are still alive here, so Panel D draws them
# directly and is identical in all five output formats.

if draw_visualization

    Erase all

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL I CHING: Form & Speed v0.5.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Speed " + fixed$(sMin, 2) + "-" + fixed$(sMax, 2) + "x"
        ... + "  |  Format: " + formatName$

    # ----------------------------------------------------------
    # PANEL A: HEXAGRAM GRID  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.85, 4.34

    Axes: 0, 10, 0, 10
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 10, 0, 10

    for ch from 1 to 8

        hv = hexValue[ch]
        dline[1] = hv mod 2
        dline[2] = (hv div 2) mod 2
        dline[3] = (hv div 4) mod 2
        dline[4] = (hv div 8) mod 2
        dline[5] = (hv div 16) mod 2
        dline[6] = (hv div 32) mod 2

        if ch <= 4
            xCenter = 1.25 + (ch - 1) * 2.3
            yBase = 5.8
        else
            xCenter = 1.25 + (ch - 5) * 2.3
            yBase = 1.8
        endif

        # v0.5: King Wen number and binary code shown separately, so the
        # code that drives the speed is not mistaken for the hexagram.
        Font size: 6
        Colour: "Black"
        Text: xCenter, "centre", yBase - 0.45, "half",
            ... "Ch" + string$(ch) + "  KW" + string$(kingWenNo[ch])
        Font size: 6
        Colour: "{0.40, 0.40, 0.40}"
        Text: xCenter, "centre", yBase - 0.85, "half",
            ... "code " + string$(hexValue[ch]) + "  " + fixed$(speedFactor[ch], 2) + "x"
        if isSilent[ch] = 1
            Colour: "{0.70, 0.25, 0.20}"
            Text: xCenter, "centre", yBase - 1.22, "half", "SILENT"
        endif

        Line width: 3
        for k from 1 to 6
            lineY = yBase + (k - 1) * 0.45
            if dline[k] = 1
                Colour: "{0.25, 0.50, 0.72}"
                Draw line: xCenter - 0.85, lineY, xCenter + 0.85, lineY
            else
                Colour: "{0.72, 0.35, 0.30}"
                Draw line: xCenter - 0.85, lineY, xCenter - 0.18, lineY
                Draw line: xCenter + 0.18, lineY, xCenter + 0.85, lineY
            endif
        endfor
        Line width: 1
        Colour: "Black"
    endfor

    Draw inner box

    # ----------------------------------------------------------
    # PANEL B: SPEED FACTOR BARS  (right column, upper)
    # ----------------------------------------------------------
    # v0.5: the axis follows the speeds actually produced. A fixed
    # 0..1.5 cut off Chaos, which reaches 2.0.
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48

    axMaxSpeed = sMax * 1.12
    if axMaxSpeed < 1.2
        axMaxSpeed = 1.2
    endif

    Axes: 0, axMaxSpeed, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, axMaxSpeed, 0.5, 8.5

    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 1.0, 0.5, 1.0, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        yLo = y - 0.38
        yHi = y + 0.38
        sf = speedFactor[ch]

        if isSilent[ch] = 1
            Paint rectangle: "{0.62, 0.62, 0.62}", 0, sf, yLo, yHi
        elsif sf > 1.0
            Paint rectangle: "{0.30, 0.58, 0.80}", 0, sf, yLo, yHi
        else
            Paint rectangle: "{0.80, 0.45, 0.25}", 0, sf, yLo, yHi
        endif

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: -axMaxSpeed * 0.015, "right", y, "half", "Ch" + string$(ch)
        Text: axMaxSpeed * 0.98, "right", y, "half", fixed$(sf, 2) + "x"
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
    Axes: 0, axMaxSpeed, 0.5, 8.5
    Text bottom: "yes", "Speed factor  (blue = faster, orange = slower, grey = silent)"

    # ----------------------------------------------------------
    # PANEL C: YIN/YANG BALANCE  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38

    Axes: 0, 6, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 6, 0.5, 8.5

    for ch from 1 to 8
        y = 9 - ch
        yLo = y - 0.38
        yHi = y + 0.38
        yc = yinCount[ch]
        yangCount = 6 - yc

        Paint rectangle: "{0.72, 0.35, 0.30}", 0, yc, yLo, yHi
        Paint rectangle: "{0.25, 0.50, 0.72}", yc, 6, yLo, yHi

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: -0.15, "right", y, "half", "Ch" + string$(ch)
        if yc > 0
            Colour: "White"
            Text: yc / 2, "centre", y, "half", string$(yc)
        endif
        if yangCount > 0
            Colour: "White"
            Text: yc + yangCount / 2, "centre", y, "half", string$(yangCount)
        endif
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 3, 0.5, 3, 8.5
    Solid line

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
    Axes: 0, 6, 0.5, 8.5
    Text bottom: "yes", "Lines: Yin (red, reversed) | Yang (blue)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Hexagram grid  (blue = Yang,  red = Yin)"
    Text: 6.10, "centre", 7.30, "half", "Speed factors (upper) & Yin/Yang balance (lower)"

    # ----------------------------------------------------------
    # PANEL D: TWO CHANNEL EXAMPLES (full width)
    # ----------------------------------------------------------
    # v0.5: these are two of the eight variations, drawn from the
    # working channels. They are not the L and R of a stereo mix, which
    # is what v0.3 called them.
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72

    selectObject: final_channels[1]
    outDurViz = Get total duration
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: final_channels[2]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: final_channels[1]
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: final_channels[2]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Channel examples  (blue = Ch1,  orange = Ch2)  — two of eight variations"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
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
        ... + "  |  Dev: ±" + fixed$(deviation_range * 100, 0) + "%"
        ... + "  |  Bias: " + fixed$(speed_bias * 100, 0) + "%"
        ... + "  |  Speed " + fixed$(sMin, 2) + "-" + fixed$(sMax, 2) + "x"
        ... + "  |  Seed: " + string$(random_seed)

    cageFlags$ = ""
    if silence_by_chance_4_33
        cageFlags$ = cageFlags$ + "  4'33-chance p=" + fixed$(silence_probability, 2)
    endif
    if jittered_slice_boundaries
        cageFlags$ = cageFlags$ + "  SliceJitter±" + fixed$(boundary_jitter * 100, 0) + "%"
    endif
    if indeterminate_pitch_shift
        cageFlags$ = cageFlags$ + "  PitchShift(indet.)"
    endif
    if variable_slice_count
        cageFlags$ = cageFlags$ + "  VarSlices"
    endif
    if slice_crossfade > 0
        cageFlags$ = cageFlags$ + "  Xfade=" + fixed$(slice_crossfade * 1000, 0) + "ms"
    endif
    if cageFlags$ = ""
        cageFlags$ = "  (no Cage extensions active)"
    endif

    Text: 0.02, "left", 0.45, "half", "Cage extensions:" + cageFlags$

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
for ch from 1 to 8
    removeObject: final_channels[ch]
endfor

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels, "-channel each"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview, L = odd channels, R = even channels."
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
