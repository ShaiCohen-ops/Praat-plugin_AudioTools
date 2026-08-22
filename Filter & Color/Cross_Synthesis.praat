# ============================================================
# Praat AudioTools - Cross_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-synthesis using LPC source-filter decomposition.
#   Combines the excitation from one sound with the spectral
#   envelope from another.
#
#   Architecture:
#   1. Preprocess: work copies at t=0, resample, duration match
#   2. LPC analysis: excitation (source) + envelope (filter)
#   3. Apply the filter envelope to the source excitation
#   4. Blend, optional level stage, restore the source time domain
#
#   Pre-emphasis is left to To LPC (50 Hz). See the v1.1 changelog.
#
#   Processes every channel.
#
# Category: Spectral
#
# Changelog v1.3 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v1.2 - Parselmouth-verified again. Everything v1.1 changed
# passed: the emphasis removal, mismatched time domains, xmin restore,
# the merged transfer control, 4-channel handling, the separated level
# modes, Envelope_detail clamping and the relocated envelope panel.
# Source = filter on speech-like material now reconstructs at
# correlation 0.950 and about 10.1 dB SNR. What was still wrong:
#   - To LPC (autocorrelation) IS NOT STABLE ON TONAL INPUT. A clean
#     1 s 220 Hz sine at 16 kHz, peak 0.2, produced 12800-13800
#     undefined samples out of 16000 in every preset, with finite
#     values reaching about 1e307. Both analyses are To LPC (burg) now:
#     the same sine gives 0 undefined samples, and speech, noise and
#     4-channel material are unaffected.
#   - Undefined output is detected and stops the run. Scale peak brings
#     the finite samples to the ceiling and leaves the undefined ones
#     undefined, so neither the safety ceiling nor the scaled playback
#     copy made such a result safe.
#   - Envelope_transfer = 0 bypasses LPC entirely. v1.1 still ran the
#     whole cross-synthesis and multiplied it by zero, and
#     0 * undefined is undefined - the problem sine returned 13370
#     undefined samples even at transfer 0.
#   - RMS and silence are measured on the multichannel work sounds, not
#     on mono folds. Anti-phase stereo cancelled in the fold: a source
#     and filter with L = s and R = -s measured 0.091694 directly and 0
#     after folding, and the script announced "the filter sound is
#     effectively silent" for two live channels. On merely dissimilar
#     channels, Match source RMS landed about 6.13 dB low.
#   - "No matching" is now "Loop filter to source length", a defined
#     policy. Warning about the undefined region did not make it
#     defined: a 2 s source with a 0.5 s filter measured RMS 0.0501 at
#     the start and 0.0183 after the filter ran out.
#   - Lpc_order is a natural number. 16.5 was accepted by the form and
#     then failed inside To LPC with "Prediction order should be a
#     whole number".
#   - New default level mode: Match source RMS + safety ceiling. RMS
#     matching guarantees nothing about the peak - a harmonic source
#     with a vowel-like filter measured a peak of 3.10 after matching,
#     which the playback copy hid while the saved object still clipped.
#   - Channel counts must match, or one side must be mono. v1.1 reused
#     the smaller object's last channel, so a stereo source against a
#     4-channel filter silently used source channels 1, 2, 2, 2.
#
# Changelog v1.1 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - THE MANUAL PRE/DE-EMPHASIS IS GONE. "self - 0.97 * self[col-1]"
#     looks like pre-emphasis but is not: Praat's Formula writes in
#     place, so self[col-1] is the value ALREADY MODIFIED and the line
#     computes y[n] = x[n] - 0.97*y[n-1], a recursive filter. On an
#     impulse it gives 1, -0.97, +0.9409, -0.9127, ... instead of
#     1, -0.97, 0, 0. The de-emphasis afterwards is recursive too, and
#     the pair does not cancel - together they approximate
#     1 / (1 - 0.97^2 z^-2), with large gain near DC and near Nyquist.
#     Measured with the same sound as both source and filter:
#     correlation 0.478 and about 1.1 dB SNR with these lines in,
#     0.953 and 10.35 dB with them removed. To LPC already applies
#     50 Hz pre-emphasis, so nothing replaces them.
#   - Both inputs are copied and shifted to 0, and the output is
#     returned to the source's time domain. Source at 5-6 s with filter
#     at 3-4 s failed outright with "Domains of Sound [5,6] and LPC
#     [3,4] should overlap", and matchDuration cut from 0 rather than
#     from the Sound's real start.
#   - Transfer_amount and Dry_wet_mix were the same control twice.
#     Expanding the two blends gives
#     output = source + Dry_wet x Transfer x (cross - source), so only
#     the product mattered: Transfer 0.5 / mix 1.0 and Transfer 1.0 /
#     mix 0.5 measured identical, maximum difference 0. They are now
#     one control, Envelope_transfer.
#   - The RMS match had no effect. It multiplied and then Scale peak
#     multiplied again, wiping it out: deleting the RMS line changed
#     the output by 1.1e-16. Output_level_mode now makes RMS matching
#     and peak normalization alternatives rather than one cancelling
#     the other, and both are optional.
#   - Envelope_transfer = 0 is real bypass. v1.0 returned the source
#     normalized to 0.95, so a 0.1-peak source came back at 0.95.
#   - A silent filter is reported. Filter: "no" ignores the filter's
#     LPC gain, so near-flat coefficients pass the source excitation
#     through and v1.0 then normalized it: a silent filter produced
#     peak 0.95 and RMS about 0.37.
#   - "No matching" with unequal durations is called out. Past the end
#     of the filter there is no LPC frame to apply and the response
#     changes abruptly: measured RMS fell from 0.23-0.43 to about 0.055
#     for the rest of the file.
#   - Every channel is processed and kept. v1.0 computed
#     max(sourceChannels, filterChannels) and then extracted exactly
#     channels 1 and 2, so 4-channel input came out as 2 channels while
#     the report still said "Channels: 4 (true stereo processing)". The
#     stereo branch also read the ORIGINAL Sounds, not the resampled,
#     duration-matched work copies.
#   - Envelope_smoothing renamed Envelope_detail, because raising it
#     raised the LPC order and made the envelope MORE detailed - the
#     opposite of what the name implied. smoothOrder is now clamped to
#     1..lpc_order; the old floor of 8 could exceed lpc_order (order 4
#     gave a filter order of 8).
#   - The LPC envelope has its own frequency-vs-dB panel. It was drawn
#     over the filter spectrogram, whose x axis is time, so the two
#     shared a viewport but not a coordinate system.
#   - Visualization draws the work copies - the sounds actually
#     analysed - and follows their time domain.
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects:"
        ... + newline$ + "  Sound 1 = Source (excitation)"
        ... + newline$ + "  Sound 2 = Filter (envelope)"
endif

sourceSound = selected("Sound", 1)
filterSound = selected("Sound", 2)

form Cross Synthesis v1.3
    comment === Preset ===
    optionmenu Preset: 1
        option Manual
        option Speech
        option Sustained Tones
        option Percussive
        option Vocal Formants
        option Extreme Smooth
    comment === LPC Parameters ===
    positive Window_ms 50
    positive Step_ms 5
    natural Lpc_order 16
    real Envelope_detail 0.8
    comment (fraction of LPC order used for the envelope: higher = more detail)
    comment === Morph Control ===
    real Envelope_transfer 0.8
    comment (0 = source unchanged, 1 = full envelope transfer)
    comment === Duration ===
    optionmenu Duration_match: 3
        option Source length
        option Filter length
        option Shorter
        option Loop filter to source length
    comment === Output ===
    optionmenu Output_level_mode: 2
        option None (natural level)
        option Match source RMS + safety ceiling
        option Match source RMS only
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.95
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    window_ms = 40
    step_ms = 5
    lpc_order = 16
    envelope_detail = 0.8
    envelope_transfer = 0.8
    presetName$ = "Speech"
elsif preset = 3
    window_ms = 70
    step_ms = 8
    lpc_order = 18
    envelope_detail = 0.85
    envelope_transfer = 0.9
    presetName$ = "SustainedTones"
elsif preset = 4
    window_ms = 30
    step_ms = 3
    lpc_order = 14
    envelope_detail = 0.65
    envelope_transfer = 0.7
    presetName$ = "Percussive"
elsif preset = 5
    window_ms = 45
    step_ms = 5
    lpc_order = 20
    envelope_detail = 0.75
    envelope_transfer = 0.85
    presetName$ = "VocalFormants"
elsif preset = 6
    window_ms = 60
    step_ms = 7
    lpc_order = 12
    envelope_detail = 0.9
    envelope_transfer = 0.95
    presetName$ = "ExtremeSmooth"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
selectObject: sourceSound
sourceName$ = selected$("Sound")
sourceDur = Get total duration
sourceXmin = Get start time
sourceSR = Get sampling frequency
sourceChannels = Get number of channels

selectObject: filterSound
filterName$ = selected$("Sound")
filterDur = Get total duration
filterSR = Get sampling frequency
filterChannels = Get number of channels

if envelope_transfer < 0
    envelope_transfer = 0
elsif envelope_transfer > 1
    envelope_transfer = 1
endif

if envelope_detail < 0.05
    envelope_detail = 0.05
elsif envelope_detail > 1
    envelope_detail = 1
endif

if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(ceiling_peak, 3) + ")."
endif

windowSize = window_ms / 1000
timeStep = step_ms / 1000

# Envelope order. v1.0 called this "smoothing" while raising it raised
# the order, i.e. produced MORE detail, and floored the result at 8 -
# which for lpc_order 4 gave a filter of order 8, higher than the
# analysis it was supposed to smooth.
smoothOrder = round(lpc_order * envelope_detail)
if smoothOrder < 1
    smoothOrder = 1
endif
if smoothOrder > lpc_order
    smoothOrder = lpc_order
endif

# Channel policy: equal counts, or mono against multichannel. v1.1
# reused the last channel of the smaller object, so a stereo source
# against a 4-channel filter silently used source channels 1, 2, 2, 2.
if sourceChannels <> filterChannels and sourceChannels <> 1 and filterChannels <> 1
    exitScript: "Source has " + string$(sourceChannels) + " channels and Filter has " +
    ... string$(filterChannels) + ". Cross-synthesis pairs them channel by channel, so the " +
    ... "counts must match, or one of the two must be mono. Otherwise the smaller object's " +
    ... "last channel would be reused for every extra channel."
endif

if sourceChannels >= filterChannels
    maxChannels = sourceChannels
else
    maxChannels = filterChannels
endif

# ============================================================
# Procedures
# ============================================================

procedure matchDuration: .soundID, .targetDur
    selectObject: .soundID
    .currentDur = Get total duration

    if .currentDur > .targetDur
        .matched = Extract part: 0, .targetDur, "rectangular", 1.0, "no"
        removeObject: .soundID
        .result = .matched
    elsif .currentDur < .targetDur
        # NOTE: Lengthen (overlap-add) is a PITCH-BASED time stretch over
        # 75-600 Hz, not a neutral length change. It can smear
        # transients and behaves unpredictably on noise and percussion.
        .ratio = .targetDur / .currentDur
        .matched = Lengthen (overlap-add): 75, 600, .ratio
        removeObject: .soundID
        .result = .matched
    else
        .result = .soundID
    endif
endproc

procedure loopToDuration: .soundID, .targetDur
    # Gives "no matching" a defined meaning. v1.1 only warned: past the
    # end of the filter there was no LPC frame to apply and the response
    # changed abruptly, measured RMS falling from 0.0501 to 0.0183 for
    # the rest of a 2 s source driven by a 0.5 s filter.
    selectObject: .soundID
    .d = Get total duration

    if .d >= .targetDur
        selectObject: .soundID
        .res = Extract part: 0, .targetDur, "rectangular", 1, "no"
        removeObject: .soundID
    else
        .n = ceiling(.targetDur / .d)
        # Concatenate follows OBJECT-LIST order, so the copies are made
        # in the order they must play.
        for .k from 1 to .n
            selectObject: .soundID
            loopPart[.k] = Copy: "loop_part"
        endfor
        selectObject: loopPart[1]
        for .k from 2 to .n
            plusObject: loopPart[.k]
        endfor
        Concatenate
        .cat = selected("Sound")
        for .k from 1 to .n
            removeObject: loopPart[.k]
        endfor
        selectObject: .cat
        .res = Extract part: 0, .targetDur, "rectangular", 1, "no"
        removeObject: .cat, .soundID
    endif
    .result = .res
endproc

procedure crossSynthesize: .sourceIn, .filterIn, .outputName$
    # No manual pre-emphasis. v1.0's "self - 0.97 * self[col-1]" was
    # recursive because Praat's Formula writes in place, and the
    # matching de-emphasis did not cancel it. To LPC applies 50 Hz
    # pre-emphasis internally, which is the whole of what is needed.

    selectObject: .sourceIn
    # Burg, not autocorrelation. On a clean 220 Hz sine at 16 kHz the
    # autocorrelation method produced 12800-13800 undefined samples out
    # of 16000 and finite values reaching about 1e307, in every preset;
    # Burg gave 0 undefined samples on the same input, and matched
    # autocorrelation's reconstruction quality on speech-like material.
    .lpcSource = To LPC (burg): lpc_order, windowSize, timeStep, 50

    selectObject: .sourceIn
    plusObject: .lpcSource
    .excitation = Filter (inverse)

    selectObject: .filterIn
    .lpcFilter = To LPC (burg): smoothOrder, windowSize, timeStep, 50

    selectObject: .excitation
    plusObject: .lpcFilter
    .filtered = Filter: "no"

    # One blend control. v1.0 had this AND an outer dry/wet, which
    # multiplied: only their product ever mattered.
    if envelope_transfer < 1
        selectObject: .filtered
        Formula: string$(envelope_transfer) + " * self + " +
            ... string$(1 - envelope_transfer) + " * object(" + string$(.sourceIn) + ", x)"
    endif

    selectObject: .filtered
    Rename: .outputName$
    .output = selected("Sound")

    removeObject: .lpcSource, .excitation, .lpcFilter
    selectObject: .output
endproc

# ============================================================
# Info
# ============================================================
clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  Cross Synthesis v1.3"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", sourceName$, " (excitation) | ", fixed$(sourceDur, 2), " s, ",
    ... sourceSR, " Hz, ", sourceChannels, " ch"
appendInfoLine: "Filter: ", filterName$, " (envelope) | ", fixed$(filterDur, 2), " s, ",
    ... filterSR, " Hz, ", filterChannels, " ch"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# STEP 1: Preprocessing on work copies at t = 0
# ============================================================
appendInfoLine: "[1/5] Preprocessing..."

# The source excitation gets filtered by an LPC built from the filter
# sound. Praat requires their time domains to overlap, so v1.0 failed
# outright on a source at 5-6 s with a filter at 3-4 s. Both are copied
# to 0 here and the source's domain is restored at the end.
selectObject: sourceSound
srcWork = Copy: "cs_src_work"
Shift times to: "start time", 0

selectObject: filterSound
fltWork = Copy: "cs_flt_work"
Shift times to: "start time", 0

# Resample to the higher of the two rates
if sourceSR >= filterSR
    targetSR = sourceSR
else
    targetSR = filterSR
endif

if sourceSR <> targetSR
    selectObject: srcWork
    tmpR = Resample: targetSR, 50
    removeObject: srcWork
    srcWork = tmpR
endif
if filterSR <> targetSR
    selectObject: fltWork
    tmpR = Resample: targetSR, 50
    removeObject: fltWork
    fltWork = tmpR
endif

suggestedOrder = round(targetSR / 1000) + 4
if lpc_order > suggestedOrder * 1.5
    appendInfoLine: "  WARNING: LPC order (", lpc_order, ") is high for SR ", targetSR,
        ... " Hz (suggested: ~", suggestedOrder, ")"
elsif lpc_order < suggestedOrder * 0.5
    appendInfoLine: "  WARNING: LPC order (", lpc_order, ") is low for SR ", targetSR,
        ... " Hz (suggested: ~", suggestedOrder, ")"
endif

appendInfoLine: "  Target SR: ", targetSR, " Hz"

# Duration matching
selectObject: srcWork
dur1 = Get total duration
selectObject: fltWork
dur2 = Get total duration

if duration_match = 1
    targetDur = dur1
    durationStrategy$ = "source length"
elsif duration_match = 2
    targetDur = dur2
    durationStrategy$ = "filter length"
elsif duration_match = 3
    if dur1 <= dur2
        targetDur = dur1
    else
        targetDur = dur2
    endif
    durationStrategy$ = "shorter"
else
    targetDur = dur1
    durationStrategy$ = "loop filter to source"
endif

if duration_match <> 4
    @matchDuration: srcWork, targetDur
    srcWork = matchDuration.result
    @matchDuration: fltWork, targetDur
    fltWork = matchDuration.result
    appendInfoLine: "  Duration matched to ", fixed$(targetDur, 3), " s (", durationStrategy$, ")"
    if dur1 <> dur2
        appendInfoLine: "    NOTE: stretching uses Lengthen (overlap-add), a pitch-based"
        appendInfoLine: "    time stretch over 75-600 Hz - not a neutral length change."
    endif
else
    # The old "No matching" left the result undefined past the end of the
    # filter. Looping the filter over the source keeps an envelope
    # defined everywhere, without time-stretching either sound.
    @loopToDuration: fltWork, targetDur
    fltWork = loopToDuration.result
    appendInfoLine: "  Output is source length (", fixed$(targetDur, 3), " s)"
    if dur2 < dur1
        appendInfoLine: "    Filter looped ", fixed$(dur1 / dur2, 2),
            ... "x to cover the source (no time stretching)"
    elsif dur2 > dur1
        appendInfoLine: "    Filter truncated to the source length"
    endif
endif

selectObject: srcWork
finalDur = Get total duration

if windowSize > finalDur / 2
    windowSize = finalDur / 2
    window_ms = windowSize * 1000
    appendInfoLine: "  WARNING: Window reduced to ", fixed$(window_ms, 1), " ms (file too short)"
endif
if windowSize < 0.005
    exitScript: "Window size too small (min 5 ms). File may be too short."
endif

# Mono references for RMS, the envelope panel and the plots
if sourceChannels > 1
    selectObject: srcWork
    sourceMono = Convert to mono
else
    selectObject: srcWork
    sourceMono = Copy: "source_mono"
endif
if filterChannels > 1
    selectObject: fltWork
    filterMono = Convert to mono
else
    selectObject: fltWork
    filterMono = Copy: "filter_mono"
endif

# Measured on the multichannel work sounds, not on mono folds. v1.1
# folded first, so anti-phase stereo cancelled: a source and filter with
# L = s and R = -s measured RMS 0.091694 directly and 0 after the fold,
# and the script announced "the filter sound is effectively silent" for
# two perfectly live channels. On merely dissimilar channels, Match
# source RMS came out about 6.13 dB below the real multichannel level.
selectObject: srcWork
sourceRMS = Get root-mean-square: 0, 0
selectObject: fltWork
filterRMS = Get root-mean-square: 0, 0

# Filter: "no" ignores the filter's LPC gain, so a near-silent filter
# yields near-flat coefficients that simply pass the source excitation
# through. v1.0 then normalized that to 0.95 and reported nothing.
if filterRMS < 0.000001
    appendInfoLine: "  WARNING: the filter sound is effectively silent (RMS ",
        ... fixed$(filterRMS, 8), ")."
    appendInfoLine: "    Its LPC coefficients will be near-flat, so the source excitation"
    appendInfoLine: "    passes through largely unshaped. Expect a bright, source-like"
    appendInfoLine: "    result rather than silence."
endif

appendInfoLine: "  Final duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: "  Envelope order: ", smoothOrder, " of ", lpc_order
appendInfoLine: ""

# ============================================================
# STEP 2-4: Cross-synthesis, every channel
# ============================================================
if envelope_transfer = 0
    appendInfoLine: "[2-4/5] Envelope transfer is 0: bypassing LPC entirely."
else
    appendInfoLine: "[2/5] Extracting source excitation..."
    appendInfoLine: "[3/5] Extracting filter envelope (order ", smoothOrder, ")..."
    appendInfoLine: "[4/5] Cross-synthesizing ", maxChannels, " channel(s)..."
endif

# v1.0 looped nothing: any multichannel input took a hard-coded
# two-channel branch that also read the ORIGINAL Sounds rather than the
# resampled, duration-matched work copies.
for ch from 1 to maxChannels
    srcCh = ch
    if srcCh > sourceChannels
        srcCh = sourceChannels
    endif
    fltCh = ch
    if fltCh > filterChannels
        fltCh = filterChannels
    endif

    if sourceChannels = 1
        selectObject: srcWork
        chSrc[ch] = Copy: "cs_src_ch"
    else
        selectObject: srcWork
        chSrc[ch] = Extract one channel: srcCh
    endif

    if filterChannels = 1
        selectObject: fltWork
        chFlt[ch] = Copy: "cs_flt_ch"
    else
        selectObject: fltWork
        chFlt[ch] = Extract one channel: fltCh
    endif

    if envelope_transfer = 0
        # Hard bypass: no LPC, no filtering. v1.1 still ran the whole
        # cross-synthesis and then multiplied it by zero, but
        # 0 * undefined is undefined, so on the problem sine even
        # Envelope_transfer = 0 returned 13370 undefined samples.
        selectObject: chSrc[ch]
        chOut[ch] = Copy: "cross_ch"
    else
        @crossSynthesize: chSrc[ch], chFlt[ch], "cross_ch"
        chOut[ch] = selected("Sound")
    endif

    # A non-finite result cannot be rescued downstream: Scale peak
    # brings the finite samples to the ceiling and leaves the undefined
    # ones undefined, so even the "safe" playback copy is not safe.
    selectObject: chOut[ch]
    chkPeak = Get absolute extremum: 0, 0, "None"
    if chkPeak = undefined or chkPeak > 1000000
        removeObject: chSrc[ch], chFlt[ch], chOut[ch]
        exitScript: "LPC analysis did not converge on channel " + string$(ch) +
        ... ": the result contains undefined or unbounded samples." + newline$ +
        ... "Try a lower Lpc_order (currently " + string$(lpc_order) + "), a longer " +
        ... "Window_ms (currently " + fixed$(window_ms, 0) + "), or a source with more " +
        ... "spectral content. Strongly tonal material is the usual cause."
    endif

    removeObject: chSrc[ch], chFlt[ch]
    appendInfo: "."
endfor
appendInfoLine: ""

if maxChannels = 1
    selectObject: chOut[1]
    finalOutput = Copy: "cs_out"
    removeObject: chOut[1]
else
    selectObject: chOut[1]
    outDurCh = Get total duration
    Create Sound from formula: "cs_out", maxChannels, 0, outDurCh, targetSR, "0"
    finalOutput = selected("Sound")
    for ch from 1 to maxChannels
        selectObject: finalOutput
        Formula (part): 0, outDurCh, ch, ch,
            ... "object[" + string$(chOut[ch]) + ", 1, col]"
    endfor
    for ch from 1 to maxChannels
        removeObject: chOut[ch]
    endfor
endif

# ============================================================
# STEP 5: Output level stage
# ============================================================
appendInfoLine: "[5/5] Output level..."

selectObject: finalOutput
pre_level_peak = Get absolute extremum: 0, 0, "None"
pre_level_rms = Get root-mean-square: 0, 0
level_gain = 1
level_action$ = "none"

# v1.0 did the RMS match and then Scale peak, and the second multiply
# erased the first: removing the RMS line changed the output by
# 1.1e-16. These are alternatives now, not a sequence.
if output_level_mode = 2 or output_level_mode = 3
    if pre_level_rms > 0.000001 and sourceRMS > 0.000001
        level_gain = sourceRMS / pre_level_rms
        selectObject: finalOutput
        Formula: "self * " + string$(level_gain)
        level_action$ = "matched to source RMS"
    else
        level_action$ = "RMS match skipped (a signal is silent)"
        if pre_level_rms <= 0.000001
            appendInfoLine: "  WARNING: output is silent - check the LPC parameters"
        endif
    endif
    if output_level_mode = 2
        # RMS matching says nothing about the peak: a harmonic source
        # with a vowel-like filter measured a peak of 3.10 after
        # matching. Attenuate only, so the match survives wherever it
        # can.
        selectObject: finalOutput
        rmsPeak = Get absolute extremum: 0, 0, "None"
        if rmsPeak > ceiling_peak and rmsPeak > 0
            Scale peak: ceiling_peak
            level_gain = level_gain * (ceiling_peak / rmsPeak)
            level_action$ = "RMS matched, then ceiling applied"
        endif
    endif
elsif output_level_mode = 4
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 5
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

selectObject: finalOutput
out_peak = Get absolute extremum: 0, 0, "None"

# ============================================================
# Visualization  (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    vizDuration = finalDur
    if vizDuration > 12
        vizDuration = 12
    endif
    maxFreqDisplay = min(5000, targetSR / 2)

    # === TITLE ===
    suiteVizName$ = replace$(sourceName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Cross Synthesis v1.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4, 0.6, 1.5
    Select inner viewport: 0.6, 3.7, 0.7, 1.4
    selectObject: sourceMono
    Colour: "{0.30, 0.50, 0.80}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Src"
    Text top: "no", sourceName$ + " (excitation, as analysed)"

    # === FILTER WAVEFORM ===
    Select outer viewport: 4, 8, 0.6, 1.5
    Select inner viewport: 4.4, 7.7, 0.7, 1.4
    selectObject: filterMono
    Colour: "{0.80, 0.40, 0.30}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Flt"
    Text top: "no", filterName$ + " (envelope, as analysed)"

    # === SOURCE SPECTROGRAM ===
    Select outer viewport: 0, 4, 1.6, 3.0
    Select inner viewport: 0.6, 3.7, 1.7, 2.9
    selectObject: sourceMono
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specSource = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Source spectrogram"
    removeObject: specSource

    # === FILTER SPECTROGRAM ===
    Select outer viewport: 4, 8, 1.6, 3.0
    Select inner viewport: 4.4, 7.7, 1.7, 2.9
    selectObject: filterMono
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specFilter = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Filter spectrogram"
    removeObject: specFilter

    # === LPC ENVELOPE: ITS OWN FREQUENCY-vs-dB PANEL ===
    # v1.0 drew this Spectrum on top of the filter spectrogram, whose x
    # axis is TIME. The two shared a viewport but not a coordinate
    # system, so the curve meant nothing where it sat.
    Select outer viewport: 0, 8, 3.1, 4.3
    Select inner viewport: 0.6, 7.7, 3.2, 4.2

    selectObject: filterMono
    midTime = finalDur / 2
    filterLPC = To LPC (burg): smoothOrder, windowSize, timeStep, 50
    selectObject: filterLPC
    lpcSlice = To Spectrum (slice): midTime, 20, 0, 50

    selectObject: lpcSlice
    Colour: "{1.00, 0.80, 0.20}"
    Line width: 2
    Draw: 0, maxFreqDisplay, 0, 80, "yes"
    Line width: 1
    removeObject: filterLPC, lpcSlice

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Filter LPC envelope at " + fixed$(midTime, 2) +
        ... " s (order " + string$(smoothOrder) + ")"

    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 4.4, 5.3
    Select inner viewport: 0.6, 7.7, 4.5, 5.2
    selectObject: finalOutput
    resultChannels = Get number of channels
    if resultChannels > 1
        resultVizSound = Convert to mono
    else
        resultVizSound = Copy: "result_viz"
    endif

    selectObject: resultVizSound
    Colour: "{0.40, 0.60, 0.40}"
    Draw: 0, vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Out"
    Text top: "no", "Result"

    # === OUTPUT SPECTROGRAM ===
    Select outer viewport: 0, 8, 5.4, 6.6
    Select inner viewport: 0.6, 7.7, 5.5, 6.5
    selectObject: resultVizSound
    To Spectrogram: 0.005, maxFreqDisplay, 0.002, 20, "Gaussian"
    specResult = selected("Spectrogram")
    Paint: 0, vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result spectrogram"
    removeObject: specResult, resultVizSound

    # === SUMMARY ===
    Select outer viewport: 0, 8, 6.7, 7.6
    Select inner viewport: 0.6, 7.7, 6.8, 7.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if output_level_mode = 1
        levelStr$ = "natural"
    elsif output_level_mode = 2 or output_level_mode = 3
        levelStr$ = "source RMS (x" + fixed$(level_gain, 3) + ")"
    elsif output_level_mode = 4
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2) + " (" + level_action$ + ")"
    else
        levelStr$ = "normalized to " + fixed$(ceiling_peak, 2)
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Cross Synthesis Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.60, "half",
        ... "Source: " + sourceName$ + " (" + fixed$(sourceDur, 2) + "s)"
        ... + "  |  Filter: " + filterName$ + " (" + fixed$(filterDur, 2) + "s)"
        ... + "  |  Out: " + fixed$(finalDur, 2) + "s"
        ... + "  |  Duration: " + durationStrategy$
        ... + "  |  SR: " + string$(targetSR) + " Hz"
    Text: 0.02, "left", 0.36, "half",
        ... "LPC: " + string$(lpc_order) + " -> envelope " + string$(smoothOrder)
        ... + "  |  Window: " + fixed$(window_ms, 0) + " ms"
        ... + "  |  Step: " + fixed$(step_ms, 0) + " ms"
        ... + "  |  Transfer: " + fixed$(envelope_transfer * 100, 0) + "%"
        ... + "  |  Preset: " + presetName$
    Text: 0.02, "left", 0.12, "half",
        ... "Peak before level stage: " + fixed$(pre_level_peak, 3)
        ... + "  |  Peak out: " + fixed$(out_peak, 3)
        ... + "  |  Level: " + levelStr$
        ... + "  |  Channels: " + string$(maxChannels)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: finalOutput
if sourceXmin <> 0
    Shift times to: "start time", sourceXmin
endif
Rename: sourceName$ + "_x_" + filterName$ + "_" + presetName$
outputName$ = selected$("Sound")

removeObject: sourceMono, filterMono, srcWork, fltWork

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", outputName$
appendInfoLine: "Channels: ", maxChannels, " (all processed)"
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Window: ", window_ms, " ms | Step: ", step_ms, " ms"
appendInfoLine: "  LPC order: ", lpc_order, " -> envelope order: ", smoothOrder
appendInfoLine: "  Envelope transfer: ", fixed$(envelope_transfer * 100, 0), "%"
appendInfoLine: "  Duration: ", durationStrategy$
appendInfoLine: ""
appendInfoLine: "  Peak before level stage: ", fixed$(pre_level_peak, 4)
appendInfoLine: "  Output stage: ", level_action$
if output_level_mode <> 5 and out_peak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

if play_after_processing
    if out_peak > 1
        # Play a scaled copy rather than a clipping one; the Sound
        # object keeps its own level.
        appendInfoLine: "Playing a scaled copy (peak ", fixed$(out_peak, 3), " exceeds 1.0)..."
        selectObject: finalOutput
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        selectObject: finalOutput
        Play
    endif
endif

selectObject: finalOutput