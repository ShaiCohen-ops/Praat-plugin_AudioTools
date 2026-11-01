# ============================================================
# Praat AudioTools - Spectral_Anticipation.praat
# Title: Spectral Anticipation
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Category: CDP
# Version: 0.2.1 (2026)
# License: MIT License (script); bundled CDP programs retain their
#          respective licenses (LGPL-2.1-or-later).
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Anticipation that becomes resonance. For successive melodic events
#   Ei -> Ei+1, material from Ei is spectrally tuned by CDP Tune to Pitch
#   (Hz) to the F0 of the NEXT event (Focus 1, Clarity 1, fixed) and
#   sounds before Ei+1 arrives (phase A, the anticipation). Near the
#   arrival it crossfades (equal power) into a CDP Freeze sustain of the
#   same tuned material (phase B, the resonance), which stays: each
#   anticipated pitch remains as the melody moves on, and the voices
#   accumulate into a spectral cloud. After the phrase ends the whole
#   cloud decays exponentially to -60 dB over Cloud_decay_factor x the
#   phrase duration. The phrase itself is never retuned, stretched or
#   decayed. The last event has no successor and makes no anticipation.
#   Cloud_decay_factor 0 (preset Short Anticipation) = the v0.1 concept:
#   short anticipations ending at the next onset, no sustain, no tail.
#   With Output_format Multichannel it gives v0.1's samples for the same
#   events; in Stereo (v0.1 had no stereo) the same anticipations are
#   panned, so the audio differs from v0.1.
#
# Input:
#   One Sound (a monophonic melodic phrase, at least 0.35 s); optionally
#   one PointProcess of event onsets (in the Sound's own time domain).
#   F0 is always measured from the Sound. A multichannel Sound is folded
#   to mono for analysis and processing (reported). Not modified.
#
# Output:
#   Stereo (default): 2 channels; voices panned (equal power) from left
#   (earliest) to right (latest); the phrase centred in both channels.
#   Multichannel: one channel per voice (round-robin above
#   Maximum_channels), the phrase in every channel.
#   Duration = phrase x (1 + Cloud_decay_factor), in the Sound's own time
#   domain. Attenuation-only peak guard (0.95).
#
# Dependencies:
#   Praat 6.4 or newer; the CDP category of Praat AudioTools (this script
#   lives in plugin_AudioTools/CDP/: internal/cdp_engine.praat, the
#   registries, engine/windows). Processes: sp_tune_1, freeze. No Python.
#
# Changelog v0.2.1 (2026):
#   - Freeze region chosen by energy AND stability (level fluctuation and
#     spectral-centroid change within the window), not by energy alone.
#   - The sustain starts one segment length into the Freeze output, after
#     its quieter build-up (fewer overlapping repeats at the start).
#   - Anticipation -> resonance crossfade: the sustain is phase-aligned
#     (within one period of the target F0) to the end of the
#     anticipation, and the crossfade gains are normalized for the
#     measured correlation (equal power when independent, equal gain when
#     in phase). v0.2 dipped 3.5-12.6 dB inside the crossfade on the test
#     material because the two phases partly cancelled.
#   - Events keep their original numbers: a pair is made only from two
#     ADJACENT original events that both have a reliable F0 (v0.2 paired
#     across a rejected event, changing the meaning of "next").
#   - A too-short Tune to Pitch result now skips its voice cleanly; the
#     anticipation map draws each resonance only as long as it lasts;
#     Short Anticipation documented accurately (v0.1 samples only in
#     Multichannel).
#
# Changelog v0.2 (2026):
#   - Sustained resonance: CDP Freeze on the TUNED material (pitch shift
#     0, amp cut 0, gain 1, deterministic seed per voice), from its most
#     energetic interior region; only the sustained part is used.
#   - Anticipation -> resonance: equal-power crossfade (Crossfade_ms)
#     ending at the predicted onset; never two full-level copies.
#   - Accumulating cloud and one shared exponential decay (processed
#     voices only) after the phrase; short terminal fade.
#   - Presets (Custom first); Short Anticipation = the v0.1 concept.
#   - Output_format: Stereo or Multichannel, independent of the preset.
#   - Optional visualization (8-inch page): events, anticipation map,
#     cloud lanes, shared decay, rendered output, summary.
#   - Separate limits: Maximum_anticipations (event pairs processed; the
#     most prominent pitch changes are kept, in time order, each still
#     aimed at its own next event) and Maximum_channels (multichannel).
#
# Changelog v0.1 (2026):
#   - First version: next-event Tune to Pitch anticipations, no sustain.
# ============================================================

include internal/cdp_engine.praat

if numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound (optionally also one PointProcess)."
endif
if numberOfSelected ("PointProcess") > 1 or numberOfSelected () > 2
    exitScript: "Select one Sound and optionally one PointProcess only."
endif
sourceID = selected ("Sound")
sourceName$ = selected$ ("Sound")
marksID = 0
if numberOfSelected ("PointProcess") = 1
    marksID = selected ("PointProcess")
endif

form Spectral Anticipation v0.2.1
    comment Composition
    optionmenu Preset: 1
        option Custom
        option Short Anticipation
        option Transparent Future
        option Spectral Cloud
        option Dense Foreknowledge
        option Deep Suspension
        option Sparse Prophecy
    natural Maximum_anticipations 6
    positive Anticipation_fraction 0.5
    comment Event Detection
    positive Pitch_floor_Hz 140
    positive Pitch_ceiling_Hz 1500
    positive Pitch_jump_semitones 1.5
    positive Min_event_gap_s 0.20
    comment CDP Sustain
    positive Freeze_window_ms 160
    positive Freeze_delay_ms 45
    real Freeze_randomness 0.04
    positive Crossfade_ms 60
    comment Mix & Decay
    real Original_level 0.85
    real Processed_level 0.65
    real Cloud_decay_factor 1.5
    comment Output
    optionmenu Output_format: 1
        option Stereo
        option Multichannel
    natural Maximum_channels 6
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Fixed (not user controls)
tuneProcess$ = "sp_tune_1"
freezeProcess$ = "freeze"
tuneFocus = 1
tuneClarity = 1
fadeMax = 0.015
minExcerpt = 0.08
cdpMargin = 0.04

# ---------------------------------------------------------------------
# 1. PRESET (Custom = the form values)
# ---------------------------------------------------------------------
# Presets never touch the tuning (Pitch = next F0, Focus 1, Clarity 1),
# the pitch range, the freeze window/delay, the crossfade, the original
# level or the output format.
presetName$ = "Custom"
if preset = 2
    presetName$ = "Short Anticipation"
    maximum_anticipations = 6
    anticipation_fraction = 0.50
    cloud_decay_factor = 0
    processed_level = 0.65
elsif preset = 3
    presetName$ = "Transparent Future"
    maximum_anticipations = 4
    anticipation_fraction = 0.35
    cloud_decay_factor = 0.80
    processed_level = 0.40
    freeze_randomness = 0.02
elsif preset = 4
    presetName$ = "Spectral Cloud"
    maximum_anticipations = 6
    anticipation_fraction = 0.50
    cloud_decay_factor = 1.50
    processed_level = 0.65
    freeze_randomness = 0.04
elsif preset = 5
    presetName$ = "Dense Foreknowledge"
    maximum_anticipations = 10
    anticipation_fraction = 0.70
    cloud_decay_factor = 2.00
    processed_level = 0.55
    freeze_randomness = 0.06
    min_event_gap_s = 0.15
    pitch_jump_semitones = 1.2
elsif preset = 6
    presetName$ = "Deep Suspension"
    maximum_anticipations = 5
    anticipation_fraction = 0.80
    cloud_decay_factor = 2.50
    processed_level = 0.60
    freeze_randomness = 0.03
elsif preset = 7
    presetName$ = "Sparse Prophecy"
    maximum_anticipations = 3
    anticipation_fraction = 0.40
    cloud_decay_factor = 1.50
    processed_level = 0.65
    freeze_randomness = 0.02
    min_event_gap_s = 0.35
    pitch_jump_semitones = 2.5
endif
# Cloud_decay_factor 0 = no sustain and no tail (the v0.1 behaviour).
sustainOn = cloud_decay_factor > 0
stereoOut = output_format = 1

# ---------------------------------------------------------------------
# 2. VALIDATION, MONO WORKING COPY, PITCH
# ---------------------------------------------------------------------
if maximum_anticipations > 16
    exitScript: "Maximum anticipations is limited to 16."
endif
if maximum_channels > 16
    exitScript: "Maximum channels is limited to 16."
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be greater than pitch floor."
endif
if pitch_jump_semitones < 0.2
    exitScript: "Pitch jump threshold must be at least 0.2 semitones."
endif
if anticipation_fraction <= 0 or anticipation_fraction > 1
    exitScript: "Anticipation fraction must be greater than 0 and at most 1."
endif
if original_level < 0 or original_level > 1 or processed_level < 0 or processed_level > 1
    exitScript: "Original/Processed levels must be within 0..1."
endif
if cloud_decay_factor < 0 or cloud_decay_factor > 4
    exitScript: "Cloud decay factor must be within 0..4 (0 = no sustain, no tail)."
endif
if freeze_window_ms < 40 or freeze_window_ms > 600
    exitScript: "Freeze window must be between 40 and 600 ms."
endif
if freeze_randomness < 0 or freeze_randomness > 1
    exitScript: "Freeze randomness must be within 0..1."
endif
if crossfade_ms < 10 or crossfade_ms > 500
    exitScript: "Crossfade must be between 10 and 500 ms."
endif

selectObject: sourceID
srcStart = Get start time
srcDur = Get total duration
srcSR = Get sampling frequency
srcChannels = Get number of channels
if srcDur < 0.35
    exitScript: "Please select a Sound of at least 0.35 seconds."
endif
if pitch_ceiling_Hz > 0.45 * srcSR
    exitScript: "Pitch ceiling must be below 45% of the sampling frequency."
endif
tailDur = srcDur * cloud_decay_factor
outDur = srcDur + tailDur
if outDur > 180
    exitScript: "The output would last " + fixed$ (outDur, 1) + " s (limit 180 s): use a shorter phrase or a smaller Cloud decay factor."
endif

# Zero-based mono working copy; the original Sound is untouched.
selectObject: sourceID
if srcChannels = 1
    monoID = Copy: "SA_source_mono_work"
else
    monoID = Convert to mono
    Rename: "SA_source_mono_work"
endif
selectObject: monoID
Shift times to: "start time", 0
srcRMS = Get root-mean-square: 0, 0
if srcRMS <= 0
    removeObject: monoID
    exitScript: "The selected Sound is silent."
endif
selectObject: monoID
pitchID = To Pitch: 0.01, pitch_floor_Hz, pitch_ceiling_Hz

# ---------------------------------------------------------------------
# 3. EVENT ONSETS (PointProcess, or pitch jumps / voiced restarts)
# ---------------------------------------------------------------------
rawN = 0
if marksID > 0
    selectObject: marksID
    pointN = Get number of points
    for i from 1 to pointN
        selectObject: marksID
        absoluteTime = Get time from index: i
        t = absoluteTime - srcStart
        if t >= 0 and t < srcDur - 0.03 and rawN < 512
            rawN += 1
            rawT [rawN] = t
        endif
    endfor
    detection$ = "PointProcess"
else
    # Same rules as Frozen Canon: a new event is a stable voiced frame
    # (three further frames within 0.8 st) that follows an unvoiced gap
    # or jumps by Pitch_jump_semitones from the current note, at least
    # Min_event_gap_s after the previous event. Vibrato stays one event.
    selectObject: pitchID
    nFrames = Get number of frames
    referenceF = 0
    lastDetectedTime = -100
    lastVoicedTime = -100
    for j from 1 to nFrames - 3
        selectObject: pitchID
        t = Get time from frame number: j
        f = Get value in frame: j, "Hertz"
        if f <> undefined and f > 0
            f1 = Get value in frame: j + 1, "Hertz"
            f2 = Get value in frame: j + 2, "Hertz"
            f3 = Get value in frame: j + 3, "Hertz"
            stable = 0
            if f1 <> undefined and f2 <> undefined and f3 <> undefined
                if f1 > 0 and f2 > 0 and f3 > 0
                    d1 = abs (12 * ln (f1 / f) / ln (2))
                    d2 = abs (12 * ln (f2 / f) / ln (2))
                    d3 = abs (12 * ln (f3 / f) / ln (2))
                    if d1 < 0.8 and d2 < 0.8 and d3 < 0.8
                        stable = 1
                    endif
                endif
            endif
            isNew = 0
            if referenceF = 0
                isNew = 1
            elsif t - lastVoicedTime > 0.10
                isNew = 1
            elsif abs (12 * ln (f / referenceF) / ln (2)) >= pitch_jump_semitones
                isNew = 1
            endif
            if stable and isNew and t - lastDetectedTime >= min_event_gap_s and rawN < 512
                rawN += 1
                rawT [rawN] = t
                referenceF = f
                lastDetectedTime = t
            endif
            lastVoicedTime = t
        endif
    endfor
    detection$ = "automatic (pitch jumps / voiced restarts)"
endif

# ---------------------------------------------------------------------
# 4. ROBUST F0 PER EVENT (median over the stable part of the note)
# ---------------------------------------------------------------------
# The stable part skips the attack (first 60 ms, at most 25% of the
# event) and stops 30 ms before the next onset. F0 = median (0.5
# quantile) of the voiced Pitch frames there; an event needs at least
# 5 voiced frames (50 ms) or it is rejected.
writeInfoLine: "=== Spectral Anticipation v0.2.1 ===  (preset: ", presetName$, ")"
appendInfoLine: "Source: ", sourceName$, "  (", fixed$ (srcDur, 3), " s, ", srcChannels, " ch)  |  onsets: ", detection$
if srcChannels > 1
    appendInfoLine: "The ", srcChannels, "-channel Sound is folded to mono for analysis and processing."
endif
appendInfoLine: ""
appendInfoLine: "Events (times from the start of the Sound):"
selectObject: pitchID
nFrames = Get number of frames
# Events keep their ORIGINAL numbers E1..En: a rejected event keeps its
# place (evValid = 0), so "the next event" always means the next one in
# the melody, never a later one that happens to have a reliable F0.
nEv = rawN
nValid = 0
nRejected = 0
for i from 1 to rawN
    evEnd = srcDur
    if i < rawN
        evEnd = rawT [i + 1]
    endif
    evLen = evEnd - rawT [i]
    stA = rawT [i] + min (0.06, 0.25 * evLen)
    stB = evEnd - min (0.03, 0.15 * evLen)
    f0 = undefined
    nVoiced = 0
    if stB > stA
        selectObject: pitchID
        fA = Get frame number from time: stA
        fB = Get frame number from time: stB
        nVoiced = 0
        for j from max (1, ceiling (fA)) to min (nFrames, floor (fB))
            v = Get value in frame: j, "Hertz"
            if v <> undefined
                nVoiced += 1
            endif
        endfor
        f0 = Get quantile: stA, stB, 0.5, "Hertz"
    endif
    evT [i] = rawT [i]
    evStA [i] = stA
    if f0 = undefined or nVoiced < 5
        nRejected += 1
        evValid [i] = 0
        evF [i] = undefined
        appendInfoLine: "   E", i, "  onset ", fixed$ (rawT [i], 3), " s   REJECTED (", nVoiced, " voiced frames in the stable part)"
    else
        nValid += 1
        evValid [i] = 1
        evF [i] = f0
        appendInfoLine: "   E", i, "  onset ", fixed$ (rawT [i], 3), " s   F0 ", fixed$ (f0, 1), " Hz   (median of ",
            ... nVoiced, " frames, ", fixed$ (stA, 3), "-", fixed$ (stB, 3), " s)"
    endif
endfor

# ---------------------------------------------------------------------
# 5. SELECT THE EVENT PAIRS (Maximum_anticipations)
# ---------------------------------------------------------------------
# A pair is (Ei, Ei+1) of two ADJACENT original events that both have a
# reliable F0; a rejected event makes no pair on either side. If there
# are more than Maximum_anticipations pairs, the most prominent
# transitions are kept: largest pitch change in semitones, then the
# longer interval, then the earlier pair. The kept pairs stay in time
# order and each keeps its own next event as target.
nPairs = 0
nBroken = 0
for ev from 1 to nEv - 1
    if evValid [ev] and evValid [ev + 1]
        nPairs += 1
        pairSrc [nPairs] = ev
    else
        nBroken += 1
    endif
endfor
if nPairs = 0
    removeObject: pitchID, monoID
    exitScript: "Spectral Anticipation needs two ADJACENT events with a reliable F0 (" + string$ (nValid) + " of " + string$ (nEv) + " events have one). Try another Pitch range, or mark the onsets with a PointProcess."
endif
for p from 1 to nPairs
    ev = pairSrc [p]
    pairScore [p] = abs (12 * log2 (evF [ev + 1] / evF [ev])) + 0.001 * (evT [ev + 1] - evT [ev])
    pairKeep [p] = 1
endfor
nDropped = 0
if nPairs > maximum_anticipations
    for p from 1 to nPairs
        pairKeep [p] = 0
    endfor
    for k from 1 to maximum_anticipations
        best = 0
        for p from 1 to nPairs
            if not pairKeep [p]
                if best = 0
                    best = p
                elsif pairScore [p] > pairScore [best]
                    best = p
                endif
            endif
        endfor
        pairKeep [best] = 1
    endfor
    nDropped = nPairs - maximum_anticipations
endif

# ---------------------------------------------------------------------
# 6. CDP ENGINE
# ---------------------------------------------------------------------
@cdpx_init: defaultDirectory$
if cdpx_error$ <> ""
    removeObject: pitchID, monoID
    exitScript: "CDP initialization failed: " + cdpx_error$ + newline$ + "Place this script inside plugin_AudioTools/CDP/."
endif
for k from 1 to 2
    pidCheck$ = tuneProcess$
    if k = 2
        pidCheck$ = freezeProcess$
    endif
    @cdpx_findProcess: pidCheck$
    if cdpx_findProcess.row = 0
        removeObject: pitchID, monoID
        exitScript: "The CDP registry does not contain process '" + pidCheck$ + "'."
    endif
endfor

# ---------------------------------------------------------------------
# 7. VOICES: phase A (tuned anticipation) + phase B (Freeze sustain)
# ---------------------------------------------------------------------
# Phase A as v0.1: window = the last Anticipation_fraction of Ei -> Ei+1;
# the excerpt comes from the stable part of Ei (natural length kept if
# shorter) and is tuned to F0(Ei+1); it ends at the onset of Ei+1.
# Phase B: CDP Freeze on the UNFADED tuned material, frozen region = the
# most energetic interior window (edges excluded); only the sustained
# part of the Freeze output is kept, at the same gain as phase A. It
# fades in (sin) while phase A fades out (cos) over the crossfade that
# ends at the onset of Ei+1, and lasts to the end of the output.
nAnt = 0
excerptID = 0
tunedID = 0
rawID = 0
frzID = 0
appendInfoLine: ""
if nDropped > 0
    appendInfoLine: nPairs, " event pairs; Maximum_anticipations = ", maximum_anticipations, ": kept the ", maximum_anticipations,
        ... " largest pitch changes (", nDropped, " pairs omitted)."
endif
appendInfoLine: "Voices (Tune to Pitch (Hz): Pitch = next F0, Focus 1, Clarity 1", if sustainOn then "; then CDP Freeze" else "" fi, "):"
if nBroken > 0
    appendInfoLine: nBroken, " adjacent pair(s) not made: a rejected event has no reliable F0 (as source or as target)."
endif
for p from 1 to nPairs
  if pairKeep [p]
    i = pairSrc [p]
    tNext = evT [i + 1]
    interval = tNext - evT [i]
    winLen = anticipation_fraction * interval
    exA = evStA [i]
    exB = min (exA + winLen, tNext - 0.01)
    if exB - exA < minExcerpt
        appendInfoLine: "   E", i, " -> E", i + 1, "  skipped: only ", fixed$ (max (0, exB - exA) * 1000, 0), " ms of stable material"
    else
        exLen = exB - exA
        selectObject: monoID
        exPeak = Get absolute extremum: exA, exB, "None"
        exRMS = Get root-mean-square: exA + exLen * 0.25, exA + exLen * 0.75
        # CDP gets the excerpt plus up to 40 ms of margin on each side; the
        # margins are cut off again after tuning, so the phase vocoder's
        # edge bursts fall in discarded material. The margins' outer edges
        # are tapered (an abrupt cut is a click the tuning would emphasise).
        inA = max (0, exA - cdpMargin)
        inB = min (srcDur, exB + cdpMargin)
        excerptID = Extract part: inA, inB, "rectangular", 1, "no"
        inLen = inB - inA
        taper$ = fixed$ (min (0.010, inLen / 8), 9)
        Formula: "self * (if x < " + taper$ + " then 0.5 - 0.5 * cos (pi * x / " + taper$ + ")"
            ... + " else if x > " + fixed$ (inLen, 9) + " - " + taper$ + " then 0.5 - 0.5 * cos (pi * (" + fixed$ (inLen, 9) + " - x) / " + taper$ + ")"
            ... + " else 1 fi fi)"

        # Parameters by name from the registry (never by position).
        @cdpx_collectParams: tuneProcess$
        for k from 1 to cdpx_collectParams.n
            pr = cdpx_paramRow [k]
            param$ = cdpx_t2_param_id$ [pr]
            if param$ = "pitch"
                cdpx_value [k] = evF [i + 1]
            elsif param$ = "focus"
                cdpx_value [k] = tuneFocus
            elsif param$ = "clarity"
                cdpx_value [k] = tuneClarity
            else
                @cleanupAnt
                exitScript: "Unexpected parameter in Tune to Pitch (Hz): " + param$
            endif
        endfor
        cdpx_sourceID = excerptID
        cdpx_pid$ = tuneProcess$
        @cdpx_process
        if cdpx_error$ <> ""
            @cleanupAnt
            appendInfoLine: ""
            appendInfoLine: "CDP command: ", cdpx_commandLine$
            exitScript: "Tune to Pitch (Hz) failed for E" + string$ (i) + " -> E" + string$ (i + 1) + " (target " + fixed$ (evF [i + 1], 1) + " Hz):" + newline$ + cdpx_error$
        endif
        tunedID = cdpx_resultID
        removeObject: excerptID
        excerptID = 0
        # Keep only the excerpt itself (margins off; PVOC may add a few ms).
        # Smooth raised-cosine fades first; then the level: the tuned
        # material gets the excerpt's loudness (RMS over the middle half)
        # but never peaks above the excerpt itself.
        selectObject: tunedID
        tunedLen = Get total duration
        cutA = exA - inA
        useLen = min (exLen, tunedLen - cutA)
        if useLen < minExcerpt
            # CDP returned less than expected: skip this voice, cleanly.
            removeObject: tunedID
            tunedID = 0
            appendInfoLine: "   E", i, " -> E", i + 1, "  skipped: Tune to Pitch returned only ", fixed$ (max (0, tunedLen) * 1000, 0), " ms"
        else
            cutID = Extract part: cutA, cutA + useLen, "rectangular", 1, "no"
            removeObject: tunedID
            tunedID = cutID
            # v0.2: an unfaded copy of the tuned material feeds CDP Freeze.
            selectObject: tunedID
            rawID = Copy: "SA_tuned_raw"
            selectObject: tunedID
            fade = min (fadeMax, useLen / 4)
            Formula: "self * (if x < " + fixed$ (fade, 9) + " then 0.5 - 0.5 * cos (pi * x / " + fixed$ (fade, 9) + ")"
                ... + " else if x > " + fixed$ (useLen - fade, 9) + " then 0.5 - 0.5 * cos (pi * (" + fixed$ (useLen, 9) + " - x) / " + fixed$ (fade, 9) + ")"
                ... + " else 1 fi fi)"
            tunedPeak = Get absolute extremum: 0, 0, "None"
            tunedRMS = Get root-mean-square: useLen * 0.25, useLen * 0.75
            if tunedPeak = undefined or tunedPeak <= 0 or tunedRMS = undefined or tunedRMS <= 0
                @cleanupAnt
                exitScript: "Tune to Pitch (Hz) returned silence for E" + string$ (i) + " -> E" + string$ (i + 1) + "."
            endif
            antGain = min (exRMS / tunedRMS, exPeak / tunedPeak)
            Formula: "self * " + fixed$ (antGain, 9)


            nAnt += 1
            antID [nAnt] = tunedID
            antFrom [nAnt] = i
            antStart [nAnt] = tNext - useLen
            antLen [nAnt] = useLen
            antEnd [nAnt] = tNext
            antTarget [nAnt] = evF [i + 1]
            antSrcF [nAnt] = evF [i]
            antShort [nAnt] = useLen < winLen - 0.005
            antGainDb [nAnt] = 20 * log10 (antGain)
            antGainLin [nAnt] = antGain
            tunedID = 0
            susID [nAnt] = 0
            susStart [nAnt] = tNext
            susLen [nAnt] = 0
            xfLen [nAnt] = 0
            susNote$ [nAnt] = ""

            # ---- Phase B: CDP Freeze sustain ------------------------------
            if sustainOn
                @makeSustain: nAnt
            endif
            removeObject: rawID
            rawID = 0
        endif
    endif
  endif
endfor
if nAnt = 0
    removeObject: pitchID, monoID
    exitScript: "No anticipation could be rendered: the events are too close for the stable material needed (" + fixed$ (minExcerpt * 1000, 0) + " ms)."
endif
nSus = 0
for k from 1 to nAnt
    if susID [k] <> 0
        nSus += 1
    endif
endfor

# ---------------------------------------------------------------------
# 8. ROUTING AND MIX OF THE PROCESSED VOICES
# ---------------------------------------------------------------------
# One working Sound for all processed voices (2 channels for stereo,
# N for multichannel); voices are written into it directly.
# Stereo: voice k at pan -1 (earliest) ... +1 (latest), equal power.
# Multichannel: voice k -> channel ((k - 1) mod N) + 1.
if stereoOut
    nCh = 2
else
    nCh = min (nAnt, maximum_channels)
endif
wetID = Create Sound from formula: "SA_cloud_work", nCh, 0, outDur, srcSR, "0"
for k from 1 to nAnt
    if stereoOut
        antPan [k] = 0
        if nAnt > 1
            antPan [k] = -1 + 2 * (k - 1) / (nAnt - 1)
        endif
        panAngle = (antPan [k] + 1) * pi / 4
        g1 = processed_level * cos (panAngle)
        g2 = processed_level * sin (panAngle)
        r1 = 1
        r2 = 2
    else
        antCh [k] = ((k - 1) mod nCh) + 1
        g1 = processed_level
        g2 = processed_level
        r1 = antCh [k]
        r2 = antCh [k]
    endif
    a = antID [k]
    st = antStart [k]
    tN = antEnd [k]
    xf = xfLen [k]
    xr = 0
    if susID [k] <> 0
        xr = xfR [k]
    endif
    selectObject: wetID
    # Phase A, and (if sustained) the crossfade into phase B. Gains are
    # cos and sin normalized by sqrt (1 + 2 r cos sin), r = the measured
    # correlation after alignment: equal power when r = 0 (independent),
    # equal gain when r = 1 (in phase); no bump, no dip in between.
    if susID [k] = 0
        Formula (part): st, min (outDur, st + antLen [k]), r1, r2,
            ... "self + (if row = r1 then g1 else g2 fi) * object (a, x - st)"
    else
        Formula (part): st, min (outDur, st + antLen [k]), r1, r2,
            ... "self + (if row = r1 then g1 else g2 fi) * object (a, x - st) * (if x > tN - xf then cos (pi / 2 * (x - (tN - xf)) / xf) / sqrt (1 + 2 * xr * cos (pi / 2 * (x - (tN - xf)) / xf) * sin (pi / 2 * (x - (tN - xf)) / xf)) else 1 fi)"
        sID = susID [k]
        s0 = susStart [k]
        Formula (part): s0, min (outDur, s0 + susLen [k]), r1, r2,
            ... "self + (if row = r1 then g1 else g2 fi) * object (sID, x - s0) * (if x < tN then sin (pi / 2 * (x - s0) / xf) / sqrt (1 + 2 * xr * cos (pi / 2 * (x - s0) / xf) * sin (pi / 2 * (x - s0) / xf)) else 1 fi)"
    endif
endfor

# ---------------------------------------------------------------------
# 9. SHARED CLOUD DECAY (processed voices only)
# ---------------------------------------------------------------------
# Constant until the phrase ends, then one exponential to -60 dB at the
# end of the output, then a short terminal fade to the last sample.
endFade = 0
if tailDur > 0
    selectObject: wetID
    srcDur$ = fixed$ (srcDur, 9)
    tailDur$ = fixed$ (tailDur, 9)
    Formula (part): srcDur, outDur, 1, nCh,
        ... "self * exp(-6.907755278982137 * (x - " + srcDur$ + ") / " + tailDur$ + ")"
    endFade = min (0.020, tailDur / 10)
    outDur$ = fixed$ (outDur, 9)
    endFade$ = fixed$ (endFade, 9)
    Formula (part): outDur - endFade, outDur, 1, nCh,
        ... "self * (0.5 + 0.5*cos(pi*(x - (" + outDur$ + " - " + endFade$ + "))/" + endFade$ + "))"
endif

# ---------------------------------------------------------------------
# 10. THE ORIGINAL PHRASE (stereo: centred once; multichannel: every
#     channel), untouched in pitch, timing and contour
# ---------------------------------------------------------------------
monoID$ = string$ (monoID)
selectObject: wetID
Formula (part): 0, srcDur, 1, nCh,
    ... "self + " + fixed$ (original_level, 9) + " * object (" + monoID$ + ", x)"

# ---------------------------------------------------------------------
# 11. REPORT, PEAK GUARD, NAME
# ---------------------------------------------------------------------
for k from 1 to nAnt
    if stereoOut
        @panName: antPan [k]
        where$ = "pan " + panName$
    else
        where$ = "channel " + string$ (antCh [k])
    endif
    appendInfoLine: "   V", k, ": E", antFrom [k], " (", fixed$ (evT [antFrom [k]], 3), " s, ", fixed$ (antSrcF [k], 1), " Hz) -> E",
        ... antFrom [k] + 1, " ", fixed$ (antTarget [k], 1), " Hz   anticipation ", fixed$ (antStart [k], 3), " s"
    if susID [k] <> 0
        appendInfoLine: "        resonance from ", fixed$ (susStart [k], 3), " s (crossfade ", fixed$ (xfLen [k] * 1000, 0), " ms), ",
            ... fixed$ (susLen [k], 2), " s   ", where$, "   gain ", fixed$ (antGainDb [k], 1), " dB (resonance ",
            ... if susMatchDb [k] >= 0 then "+" else "" fi, fixed$ (susMatchDb [k], 1), " dB)", susNote$ [k]
        appendInfoLine: "        freeze window ", fixed$ (frzA [k] * 1000, 0), "-", fixed$ (frzB [k] * 1000, 0), " ms of the tuned excerpt (instability ",
            ... fixed$ (frzScore [k], 2), ")   alignment ", fixed$ (xfShift [k] * 1000, 2), " ms, crossfade correlation ", fixed$ (xfR [k], 2)
    else
        appendInfoLine: "        ends at ", fixed$ (antEnd [k], 3), " s, no sustain", susNote$ [k], "   ", where$, "   gain ", fixed$ (antGainDb [k], 1), " dB"
    endif
endfor

selectObject: wetID
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 0.95
    Scale peak: 0.95
endif
Shift times to: "start time", srcStart
if stereoOut
    Rename: sourceName$ + "_SpectralAnticipation_ST"
else
    Rename: sourceName$ + "_SpectralAnticipation_MC"
endif
finalName$ = selected$ ("Sound")

appendInfoLine: ""
if not stereoOut
    if nAnt > nCh
        appendInfoLine: "Routing: ", nAnt, " voices on ", nCh, " channels, round-robin (Maximum_channels = ", maximum_channels, ")."
    else
        appendInfoLine: "Routing: one channel per voice."
    endif
endif
if nRejected > 0
    appendInfoLine: nRejected, " onset(s) rejected: no reliable F0."
endif
appendInfoLine: "Output: ", finalName$, "  (", nCh, " channels, ", fixed$ (outDur, 3), " s = phrase ", fixed$ (srcDur, 3),
    ... " s + cloud ", fixed$ (tailDur, 3), " s; ", nSus, " of ", nAnt, " voices sustained)"
if outPeak > 0.95
    appendInfoLine: "Peak guard: mix peak ", fixed$ (outPeak, 3), " scaled to 0.95 (phrase and cloud together)."
endif

# ---------------------------------------------------------------------
# 12. VISUALIZATION (optional; reads the finished Sound only)
# ---------------------------------------------------------------------
if draw_visualization
    @drawAnticipation
endif

# ---------------------------------------------------------------------
# 13. CLEANUP, SELECTION, PLAYBACK
# ---------------------------------------------------------------------
for k from 1 to nAnt
    removeObject: antID [k]
    if susID [k] <> 0
        removeObject: susID [k]
    endif
endfor
removeObject: pitchID, monoID
if not stereoOut
    appendInfoLine: "Multichannel playback depends on the audio interface and Praat configuration."
endif
selectObject: wetID
if play_result
    Play
endif
selectObject: wetID

# =====================================================================
# PROCEDURES
# =====================================================================

# Phase B for voice .k: CDP Freeze of the unfaded tuned material rawID.
procedure makeSustain: .k
    selectObject: rawID
    .len = Get total duration
    .margin = max (0.02, 0.12 * .len)
    .win = min (freeze_window_ms / 1000, .len - 2 * .margin)
    if .win < 0.04
        susNote$ [.k] = "  (sustain skipped: tuned excerpt " + fixed$ (.len * 1000, 0) + " ms is too short to freeze)"
    else
        # Freeze region: energy AND stability. Nine interior candidates;
        # those with at least half the loudest candidate's RMS qualify;
        # of these, the most stable wins: least level fluctuation (s.d. of
        # 20-ms RMS in dB) plus half the change of spectral centre of
        # gravity between the window's two halves (in semitones). The
        # tuned material's own pitch is NOT measured: after Clarity 1
        # tuning a pitch track is not reliable enough to rank windows.
        .nC = 9
        .maxR = 0
        for .c from 1 to .nC
            .ca [.c] = .margin + (.len - 2 * .margin - .win) * (.c - 1) / (.nC - 1)
            selectObject: rawID
            .cr [.c] = Get root-mean-square: .ca [.c], .ca [.c] + .win
            if .cr [.c] = undefined
                .cr [.c] = 0
            endif
            .maxR = max (.maxR, .cr [.c])
        endfor
        .best = .ca [1]
        .bestScore = 1e9
        .nFr = max (2, floor (.win / 0.02))
        for .c from 1 to .nC
            if .cr [.c] >= 0.5 * .maxR and .cr [.c] > 0
                selectObject: rawID
                .sum = 0
                .sum2 = 0
                .nOk = 0
                for .f from 1 to .nFr
                    .fr = Get root-mean-square: .ca [.c] + (.f - 1) * .win / .nFr, .ca [.c] + .f * .win / .nFr
                    if .fr <> undefined and .fr > 0
                        .db = 20 * log10 (.fr)
                        .sum += .db
                        .sum2 += .db * .db
                        .nOk += 1
                    endif
                endfor
                .sd = 99
                if .nOk >= 2
                    .sd = sqrt (max (0, (.sum2 - .sum * .sum / .nOk) / (.nOk - 1)))
                endif
                .h1 = Extract part: .ca [.c], .ca [.c] + .win / 2, "rectangular", 1, "no"
                .sp1 = To Spectrum: "yes"
                .g1 = Get centre of gravity: 2
                removeObject: .h1, .sp1
                selectObject: rawID
                .h2 = Extract part: .ca [.c] + .win / 2, .ca [.c] + .win, "rectangular", 1, "no"
                .sp2 = To Spectrum: "yes"
                .g2 = Get centre of gravity: 2
                removeObject: .h2, .sp2
                .dc = 99
                if .g1 <> undefined and .g2 <> undefined and .g1 > 0 and .g2 > 0
                    .dc = abs (12 * log2 (.g2 / .g1))
                endif
                .score = .sd + 0.5 * .dc
                if .score < .bestScore
                    .bestScore = .score
                    .best = .ca [.c]
                endif
            endif
        endfor
        .fs = .best
        .fe = .best + .win
        frzScore [.k] = .bestScore
        .xf = min (crossfade_ms / 1000, 0.5 * antLen [.k])
        .s0 = antEnd [.k] - .xf
        .need = outDur - .s0
        .delay = max (0.001, min (freeze_delay_ms / 1000, 0.65 * .win))
        # Freeze builds its sound from overlapping repeats of the segment:
        # its first segment length is quieter (fewer overlaps). The
        # sustain is taken from one segment length later (steady state).
        .skip = .win
        .outdur = max (2.5, .fs + .skip + .need + (.len - .fe) + 0.5)
        @cdpx_collectParams: freezeProcess$
        for .j from 1 to cdpx_collectParams.n
            .pr = cdpx_paramRow [.j]
            .param$ = cdpx_t2_param_id$ [.pr]
            if .param$ = "outdur"
                cdpx_value [.j] = .outdur
            elsif .param$ = "delay"
                cdpx_value [.j] = .delay
            elsif .param$ = "rand"
                cdpx_value [.j] = freeze_randomness
            elsif .param$ = "pshift"
                cdpx_value [.j] = 0
            elsif .param$ = "ampcut"
                cdpx_value [.j] = 0
            elsif .param$ = "fstart"
                cdpx_value [.j] = .fs
            elsif .param$ = "fend"
                cdpx_value [.j] = .fe
            elsif .param$ = "gain"
                cdpx_value [.j] = 1
            elsif .param$ = "seed"
                cdpx_value [.j] = 200 + antFrom [.k]
            else
                @cleanupAnt
                exitScript: "Unexpected parameter in CDP Freeze: " + .param$
            endif
            @cdpx_checkValue: .pr, cdpx_value [.j]
            if cdpx_checkValue.msg$ <> ""
                @cleanupAnt
                exitScript: "CDP Freeze parameter " + .param$ + " for V" + string$ (.k) + ": " + cdpx_checkValue.msg$
            endif
        endfor
        cdpx_sourceID = rawID
        cdpx_pid$ = freezeProcess$
        @cdpx_process
        if cdpx_error$ <> ""
            @cleanupAnt
            appendInfoLine: ""
            appendInfoLine: "CDP command: ", cdpx_commandLine$
            exitScript: "CDP Freeze failed for V" + string$ (.k) + " (E" + string$ (antFrom [.k]) + " -> E" + string$ (antFrom [.k] + 1) + "):" + newline$ + cdpx_error$
        endif
        frzID = cdpx_resultID
        # Keep only the sustained part: from the frozen-region start up to
        # where the input's unfrozen tail begins.
        selectObject: frzID
        .frzLen = Get total duration
        .avail = .frzLen - .fs - .skip - (.len - .fe)
        .use = min (.need, .avail)
        if .use < .xf + 0.05
            susNote$ [.k] = "  (sustain skipped: Freeze returned only " + fixed$ (max (0, .avail), 2) + " s)"
            removeObject: frzID
            frzID = 0
        else
            .partID = Extract part: .fs + .skip, .fs + .skip + .use, "rectangular", 1, "no"
            removeObject: frzID
            frzID = 0
            selectObject: .partID
            .peak = Get absolute extremum: 0, 0, "None"
            if .peak = undefined or .peak <= 0
                removeObject: .partID
                @cleanupAnt
                exitScript: "CDP Freeze returned silence for V" + string$ (.k) + "."
            endif
            # Same gain as phase A, plus a bounded continuity correction
            # (+/- 12 dB): the 150 ms of sustain after the crossfade are
            # matched to the 150 ms of phase A before it, so the crossfade
            # carries no level step. Never a boost of near-silent material.
            .rS = Get root-mean-square: .xf, .xf + min (0.15, .use - .xf)
            selectObject: antID [.k]
            .rA = Get root-mean-square: max (0, antLen [.k] - .xf - 0.15), antLen [.k] - .xf
            .match = 1
            if .rS <> undefined and .rS > 0 and .rA <> undefined and .rA > 0
                .match = min (4, max (0.25, .rA / (.rS * antGainLin [.k])))
            endif
            selectObject: .partID
            Formula: "self * " + fixed$ (antGainLin [.k] * .match, 9)
            susMatchDb [.k] = 20 * log10 (.match)
            # Phase alignment: both phases carry the same tuned harmonics,
            # so their relative phase decides whether the crossfade adds
            # or cancels. Search one period of the target F0 for the start
            # offset of the sustain that best matches the end of phase A
            # (normalized correlation), trim the sustain by it, and keep
            # the correlation r for the crossfade gains (section 8).
            .fadeA = min (fadeMax, antLen [.k] / 4)
            .lenC = .xf - .fadeA
            .bestTau = 0
            .bestCorr = 0
            if .lenC >= 0.01 and .use > 1 / antTarget [.k] + .lenC + 0.05
                selectObject: antID [.k]
                .aSeg = Extract part: antLen [.k] - .xf, antLen [.k] - .fadeA, "rectangular", 1, "no"
                .aN = Get number of samples
                .aRms = Get root-mean-square: 0, 0
                .tper = 1 / antTarget [.k]
                .bestCorr = -2
                for .q from 0 to 39
                    .tau = .tper * .q / 40
                    selectObject: .partID
                    .bSeg = Extract part: .tau, .tau + .lenC, "rectangular", 1, "no"
                    .bRms = Get root-mean-square: 0, 0
                    selectObject: .aSeg
                    .prod = Copy: "prod"
                    Formula: "if col <= " + string$ (.aN) + " then self * object [" + string$ (.bSeg) + ", col] else 0 fi"
                    .mAB = Get mean: 0, 0, 0
                    removeObject: .prod, .bSeg
                    .corr = 0
                    if .aRms > 0 and .bRms <> undefined and .bRms > 0
                        .corr = .mAB / (.aRms * .bRms)
                    endif
                    if .corr > .bestCorr
                        .bestCorr = .corr
                        .bestTau = .tau
                    endif
                endfor
                removeObject: .aSeg
                if .bestTau > 0
                    selectObject: .partID
                    .alID = Extract part: .bestTau, .use, "rectangular", 1, "no"
                    removeObject: .partID
                    .partID = .alID
                    .use = .use - .bestTau
                endif
            endif
            xfR [.k] = min (1, max (0, .bestCorr))
            xfShift [.k] = .bestTau
            susID [.k] = .partID
            susStart [.k] = .s0
            susLen [.k] = .use
            xfLen [.k] = .xf
            frzA [.k] = .fs
            frzB [.k] = .fe
            if .use < .need - 0.01
                susNote$ [.k] = "  (Freeze gave " + fixed$ (.use, 2) + " of " + fixed$ (.need, 2) + " s)"
            endif
        endif
    endif
endproc

# Remove everything made so far when processing fails.
procedure cleanupAnt
    for .k from 1 to nAnt
        removeObject: antID [.k]
        if susID [.k] <> 0
            removeObject: susID [.k]
        endif
    endfor
    if excerptID <> 0
        removeObject: excerptID
    endif
    if tunedID <> 0
        removeObject: tunedID
    endif
    if rawID <> 0
        removeObject: rawID
    endif
    if frzID <> 0
        removeObject: frzID
    endif
    removeObject: pitchID, monoID
endproc

# ---------------------------------------------------------------------
# Visualization (8-inch page, Praat AudioTools style). Everything drawn
# is measured or computed in this run; the output Sound is only read.
# ---------------------------------------------------------------------
procedure drawAnticipation
    .bgCol$ = "{0.97, 0.97, 0.99}"
    .gridCol$ = "{0.74, 0.74, 0.80}"
    .axisCol$ = "{0.20, 0.20, 0.28}"
    .dimCol$ = "{0.45, 0.45, 0.55}"
    .srcCol$ = "{0.55, 0.55, 0.55}"
    .melCol$ = "{0.30, 0.30, 0.34}"
    .origBar$ = "{0.80, 0.80, 0.82}"
    .panelBg$ = "{0.94, 0.94, 0.94}"
    .vL = 0.60
    .vR = 7.70
    .railX = -0.065
    .pageHeight = 8.00

    selectObject: wetID
    .outPeak = Get absolute extremum: 0, 0, "None"
    .outCh = Get number of channels
    .outLen = Get total duration
    selectObject: monoID
    .srcPeak = Get absolute extremum: 0, 0, "None"
    if .srcPeak < 0.001
        .srcPeak = 0.001
    endif
    @vizSafe: sourceName$
    .name$ = vizSafe$
    @niceStep: srcDur, 8
    .stepA = niceStep
    @niceStep: outDur, 10
    .stepT = niceStep
    .pl$ = "s"
    if nAnt = 1
        .pl$ = ""
    endif
    if stereoOut
        .fmt$ = "stereo"
    else
        .fmt$ = string$ (.outCh) + "-channel"
    endif
    # which valid events are the source of a rendered voice
    for .e from 1 to nEv
        .isSrc [.e] = 0
    endfor
    for .k from 1 to nAnt
        .isSrc [antFrom [.k]] = .k
    endfor

    Erase all
    Line width: 1
    Colour: "Black"
    Solid line

    # ---- Title -----------------------------------------------------------
    Font size: 12
    Select inner viewport: .vL, .vR, 0.12, 0.32
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Spectral Anticipation v0.2.1##"
    Font size: 7
    Select inner viewport: .vL, .vR, 0.34, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.5, "half", .name$ + "  |  " + presetName$ + "  |  " + string$ (nAnt) + " voice" + .pl$
        ... + " (" + string$ (nSus) + " sustained)  |  " + .fmt$ + "  |  phrase " + fixed$ (srcDur, 2) + " s + cloud " + fixed$ (tailDur, 2) + " s"

    # ---- Panel A: phrase and events -------------------------------------
    .aT = 0.80
    .aB = 1.55
    .aTop = .srcPeak * 1.95
    .aBot = -.srcPeak * 1.10
    Font size: 6
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, .aBot, .aTop
    Paint rectangle: .bgCol$, 0, srcDur, .aBot, .aTop
    selectObject: monoID
    Colour: .srcCol$
    Draw: 0, srcDur, .aBot, .aTop, "no", "Curve"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, .aBot, .aTop
    for .e from 1 to nEv
        if .isSrc [.e] > 0
            @voiceCol: .isSrc [.e], 0
            Colour: voiceCol$
            Line width: 1.5
        else
            Colour: .melCol$
            Line width: 1
        endif
        Draw line: evT [.e], .aBot, evT [.e], .srcPeak * 1.15
        Line width: 1
        if evValid [.e]
            .lab$ = "E" + string$ (.e) + " " + fixed$ (evF [.e], 0) + " Hz"
        else
            .lab$ = "E" + string$ (.e) + " rejected"
            Colour: .gridCol$
        endif
        .rows = 2
        if nEv > 10
            .rows = 3
        endif
        .y = .srcPeak * (1.25 + 0.22 * ((.e - 1) mod .rows))
        if evT [.e] > 0.85 * srcDur
            Text: evT [.e], "right", .y, "half", .lab$ + " "
        else
            Text: evT [.e], "left", .y, "half", " " + .lab$
        endif
    endfor
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, srcDur, .aBot, .aTop
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepA, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Phrase"
    Select inner viewport: .vL, .vR, .aT, .aB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    .extra$ = ""
    if nRejected > 0
        .extra$ = "; " + string$ (nRejected) + " onset(s) rejected (no reliable F0)"
    endif
    Text top: "no", "##Phrase and events## (s) - " + string$ (nEv) + " events with median F0, onsets: " + detection$ + ";"
        ... + " coloured: source of a voice" + .extra$

    # ---- Panel B: anticipation map (pitch over phrase time) ------------
    .bT = 1.85
    .bB = 3.05
    .fLo = 1e9
    .fHi = 0
    for .e from 1 to nEv
        if evValid [.e]
            .fLo = min (.fLo, evF [.e])
            .fHi = max (.fHi, evF [.e])
        endif
    endfor
    .yLo = 12 * log2 (.fLo / 440) + 69 - 2
    .yHi = 12 * log2 (.fHi / 440) + 69 + 3
    Font size: 6
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, srcDur, .yLo, .yHi
    Paint rectangle: .bgCol$, 0, srcDur, .yLo, .yHi
    # the melody as measured: each valid event at its F0 until the next onset
    for .e from 1 to nEv
        if evValid [.e]
            .m = 12 * log2 (evF [.e] / 440) + 69
            .eEnd = srcDur
            if .e < nEv
                .eEnd = evT [.e + 1]
            endif
            Paint rectangle: .origBar$, evT [.e], .eEnd, .m - 0.18, .m + 0.18
        endif
    endfor
    for .k from 1 to nAnt
        .mS = 12 * log2 (antSrcF [.k] / 440) + 69
        .mT = 12 * log2 (antTarget [.k] / 440) + 69
        @voiceCol: .k, 0
        .col$ = voiceCol$
        @voiceCol: .k, 0.55
        .lt$ = voiceCol$
        # anticipatory interval at the TARGET pitch
        Paint rectangle: .col$, antStart [.k], antEnd [.k], .mT - 0.30, .mT + 0.30
        # resonance continues at the target pitch (light) to the phrase end
        if susID [.k] <> 0
            .rEnd = min (srcDur, susStart [.k] + susLen [.k] + xfShift [.k])
            if .rEnd > antEnd [.k]
                Paint rectangle: .lt$, antEnd [.k], .rEnd, .mT - 0.12, .mT + 0.12
            endif
        endif
        # link: from the source note to its anticipation
        Colour: .col$
        Dotted line
        Draw line: antStart [.k], .mS, antStart [.k], .mT
        Solid line
        # transition point (arrival of the predicted note)
        Draw line: antEnd [.k], .mT - 0.7, antEnd [.k], .mT + 0.7
        .lab$ = "E" + string$ (antFrom [.k]) + "\-> F0(E" + string$ (antFrom [.k] + 1) + ") " + fixed$ (antTarget [.k], 0) + " Hz"
        if antStart [.k] < 0.2 * srcDur
            Text: antEnd [.k], "left", .mT + 0.55, "half", " " + .lab$
        else
            Text: antStart [.k], "right", .mT + 0.55, "half", .lab$ + " "
        endif
    endfor
    # the melody on top, so resonances at the same pitch do not hide it
    Colour: .melCol$
    Line width: 2
    for .e from 1 to nEv
        if evValid [.e]
            .m = 12 * log2 (evF [.e] / 440) + 69
            .eEnd = srcDur
            if .e < nEv
                .eEnd = evT [.e + 1]
            endif
            Draw line: evT [.e], .m, .eEnd, .m
        endif
    endfor
    Line width: 1
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, srcDur, .yLo, .yHi
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepA, "yes", "yes", "no"
    # pitch ticks at the measured F0s, skipping any within a semitone
    # of one already drawn (labels would overlap)
    .nMk = 0
    for .e from 1 to nEv
      if evValid [.e]
        .m = 12 * log2 (evF [.e] / 440) + 69
        .near = 0
        for .q from 1 to .nMk
            if abs (.mk [.q] - .m) < 1.2
                .near = 1
            endif
        endfor
        if not .near
            .nMk += 1
            .mk [.nMk] = .m
            One mark left: .m, "no", "yes", "no", fixed$ (evF [.e], 0)
        endif
      endif
    endfor
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Pitch (Hz)"
    Select inner viewport: .vL, .vR, .bT, .bB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Anticipation map## (s, log pitch) - dark line: the melody at its F0; colour: material of Ei tuned to F0(Ei+1),"
        ... + " dotted from its source note; tick: arrival = start of the resonance (light)"

    # ---- Panel C: the cloud, one lane per voice -------------------------
    .cT = 3.35
    .cB = 4.65
    Font size: 6
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, outDur, 0, nAnt
    Paint rectangle: .bgCol$, 0, outDur, 0, nAnt
    for .k from 1 to nAnt
        .yb = nAnt - .k
        @voiceCol: .k, 0
        .col$ = voiceCol$
        @voiceCol: .k, 0.45
        .mid$ = voiceCol$
        @voiceCol: .k, 0.75
        .lt$ = voiceCol$
        Paint rectangle: .origBar$, 0, srcDur, .yb + 0.10, .yb + 0.22
        Paint rectangle: .col$, antStart [.k], antEnd [.k], .yb + 0.30, .yb + 0.90
        if susID [.k] <> 0
            .sEnd = min (outDur, susStart [.k] + susLen [.k])
            if srcDur > antEnd [.k]
                Paint rectangle: .mid$, antEnd [.k], min (srcDur, .sEnd), .yb + 0.38, .yb + 0.82
            endif
            if .sEnd > srcDur
                Paint rectangle: .lt$, max (srcDur, antEnd [.k]), .sEnd, .yb + 0.38, .yb + 0.82
            endif
            Colour: "Black"
            Draw line: susStart [.k], .yb + 0.25, susStart [.k], .yb + 0.95
        endif
    endfor
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, outDur, 0, nAnt
    Colour: .axisCol$
    Dashed line
    Draw line: srcDur, 0, srcDur, nAnt
    Solid line
    .labStep = 1
    if nAnt > 10
        .labStep = 2
    endif
    for .k from 1 to nAnt
        if (.k - 1) mod .labStep = 0
            @voiceCol: .k, 0
            Colour: voiceCol$
            if stereoOut
                @panName: antPan [.k]
                .w$ = panName$
            else
                .w$ = "ch" + string$ (antCh [.k])
            endif
            Text: -outDur * 0.004, "right", nAnt - .k + 0.6, "half", "V" + string$ (.k) + " " + .w$
        endif
    endfor
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, outDur, 0, nAnt
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepT, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Voices"
    Select inner viewport: .vL, .vR, .cT, .cB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    .where$ = "channel"
    if stereoOut
        .where$ = "pan position"
    endif
    Text top: "no", "##Spectral cloud## (s) - per voice (" + .where$ + "): dark = anticipation, tick = crossfade into Freeze,"
        ... + " medium = resonance, light = shared decay; grey: phrase; dashed: phrase end"

    # ---- Panel D: shared decay -------------------------------------------
    .dT = 4.95
    .dB = 5.50
    .dbLo = -72
    .dbHi = 6
    Font size: 6
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, outDur, .dbLo, .dbHi
    Paint rectangle: .bgCol$, 0, outDur, .dbLo, .dbHi
    Colour: .gridCol$
    for .q to 3
        Draw line: 0, -20 * .q, outDur, -20 * .q
    endfor
    Paint rectangle: .origBar$, 0, srcDur, 2, 4.5
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.5
    if tailDur > 0
        .tPrev = 0
        .dPrev = 0
        for .q from 1 to 400
            .t = outDur * .q / 400
            .g = 1
            if .t > srcDur
                .g = exp (-6.907755278982137 * (.t - srcDur) / tailDur)
            endif
            if .t > outDur - endFade
                .g = .g * (0.5 + 0.5 * cos (pi * (.t - (outDur - endFade)) / endFade))
            endif
            if .g > 0
                .d = max (.dbLo, 20 * log10 (.g))
            else
                .d = .dbLo
            endif
            Draw line: .tPrev, .dPrev, .t, .d
            .tPrev = .t
            .dPrev = .d
        endfor
        Line width: 1
        Colour: .axisCol$
        Dashed line
        Draw line: srcDur, .dbLo, srcDur, .dbHi
        Solid line
        Text: srcDur, "right", -40, "half", "decay starts " + fixed$ (srcDur, 2) + " s "
        Text: outDur, "right", -28, "half", "-60 dB at " + fixed$ (outDur, 2) + " s "
    else
        Draw line: 0, 0, outDur, 0
        Line width: 1
        Colour: .axisCol$
        Text: outDur / 2, "centre", -35, "half", "no cloud tail (Cloud decay factor 0): no decay applied"
    endif
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, outDur, .dbLo, .dbHi
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepT, "yes", "yes", "no"
    Marks left every: 1, 30, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Gain (dB)"
    Select inner viewport: .vL, .vR, .dT, .dB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Shared decay## (s, dB) - processed voices only (the phrase, grey, is not decayed): exp over "
        ... + fixed$ (tailDur, 2) + " s (x" + fixed$ (cloud_decay_factor, 2) + "), final " + fixed$ (endFade * 1000, 0) + " ms fade"

    # ---- Panel E: rendered output ----------------------------------------
    .eT = 5.80
    .eB = 7.15
    .amp = .outPeak * 1.05
    if .amp <= 0
        .amp = 1
    endif
    .laneH = (.eB - .eT) / .outCh
    .t0 = srcStart
    Font size: 6
    Select inner viewport: .vL, .vR, .eT, .eB
    Axes: 0, outDur, 0, 1
    Paint rectangle: .bgCol$, 0, outDur, 0, 1
    for .c to .outCh
        .lt = .eT + (.c - 1) * .laneH
        Select inner viewport: .vL, .vR, .lt, .lt + .laneH
        Axes: .t0, .t0 + outDur, -.amp, .amp
        selectObject: wetID
        .ex = Extract one channel: .c
        if stereoOut
            @lrCol: .c
            Colour: lrCol$
        else
            @voiceCol: .c, 0
            Colour: voiceCol$
        endif
        Draw: .t0, .t0 + outDur, -.amp, .amp, "no", "Curve"
        removeObject: .ex
        Colour: .gridCol$
        if .c > 1
            Draw line: .t0, .amp, .t0 + outDur, .amp
        endif
        if stereoOut
            @lrCol: .c
            Colour: lrCol$
            Text: .t0 - outDur * 0.004, "right", 0, "half", mid$ ("LR", .c, 1)
        elsif (.c - 1) mod .labStep = 0
            @voiceCol: .c, 0
            Colour: voiceCol$
            Text: .t0 - outDur * 0.004, "right", 0, "half", "ch" + string$ (.c)
        endif
    endfor
    Select inner viewport: .vL, .vR, .eT, .eB
    Axes: 0, outDur, 0, 1
    Colour: .axisCol$
    Dashed line
    Draw line: srcDur, 0, srcDur, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .stepT, "yes", "yes", "no"
    Select inner viewport: .vL, .vR, .eT, .eB
    Axes: 0, 1, 0, 1
    Colour: .dimCol$
    Text special: .railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Output"
    Select inner viewport: .vL, .vR, .eT, .eB
    Axes: 0, 1, 0, 1
    Colour: .axisCol$
    Text top: "no", "##Output## (s from the start of the Sound) - the rendered " + .fmt$ + " Sound, one amplitude scale (+/-"
        ... + fixed$ (.amp, 2) + ")"

    # ---- Summary strip ----------------------------------------------------
    .sT = 7.40
    .sB = 7.92
    Font size: 6
    Select inner viewport: .vL, .vR, .sT, .sB
    Axes: 0, 1, 0, 1
    Paint rectangle: .panelBg$, 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.015, "left", 0.78, "half", "##Input##  " + .name$ + "  |  " + fixed$ (srcDur, 3) + " s, " + string$ (srcChannels)
        ... + " ch  |  onsets: " + detection$ + "  |  " + string$ (nEv) + " events, " + string$ (nValid) + " with reliable F0 (" + string$ (nRejected) + " rejected)"
    Text: 0.015, "left", 0.50, "half", "##Voices##  " + presetName$ + "  |  " + string$ (nAnt) + " anticipation" + .pl$
        ... + " of " + string$ (nPairs) + " pairs (max " + string$ (maximum_anticipations) + ")  |  " + string$ (nSus)
        ... + " sustained by Freeze  |  fraction " + fixed$ (anticipation_fraction, 2) + ", crossfade " + fixed$ (crossfade_ms, 0) + " ms"
    Text: 0.015, "left", 0.22, "half", "##Output##  " + .fmt$ + " (" + string$ (.outCh) + " ch)  |  decay x" + fixed$ (cloud_decay_factor, 2)
        ... + " = " + fixed$ (tailDur, 2) + " s  |  total " + fixed$ (.outLen, 2) + " s  |  final peak " + fixed$ (.outPeak, 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, .pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endproc

# Voice colour: twelve distinguishable hues, darker after twelve.
# .tint 0 = full colour, 0.55 = light tint (mixed with white).
procedure voiceCol: .i, .tint
    .h = ((.i - 1) mod 12) + 1
    .shade = 1
    if .i > 12
        .shade = 0.70
    endif
    .r# = {0.20, 0.85, 0.16, 0.55, 0.80, 0.20, 0.55, 0.90, 0.35, 0.65, 0.10, 0.70}
    .g# = {0.45, 0.45, 0.58, 0.30, 0.30, 0.60, 0.35, 0.70, 0.35, 0.55, 0.35, 0.20}
    .b# = {0.75, 0.15, 0.30, 0.70, 0.45, 0.65, 0.20, 0.10, 0.60, 0.25, 0.45, 0.20}
    .r = .r# [.h] * .shade
    .g = .g# [.h] * .shade
    .b = .b# [.h] * .shade
    .r = .r + (1 - .r) * .tint
    .g = .g + (1 - .g) * .tint
    .b = .b + (1 - .b) * .tint
    voiceCol$ = "{" + fixed$ (.r, 3) + ", " + fixed$ (.g, 3) + ", " + fixed$ (.b, 3) + "}"
endproc

# Stereo position -1..+1 as a short label: L, R, C or a signed number.
procedure panName: .p
    if .p <= -0.999
        panName$ = "L"
    elsif .p >= 0.999
        panName$ = "R"
    elsif abs (.p) < 0.001
        panName$ = "C"
    else
        panName$ = fixed$ (.p, 2)
    endif
endproc

# Neutral colours for the stereo output lanes (1 = L, 2 = R).
procedure lrCol: .i
    if .i = 1
        lrCol$ = "{0.20, 0.40, 0.80}"
    else
        lrCol$ = "{0.80, 0.35, 0.20}"
    endif
endproc

# Snap an axis step to 1 / 2 / 5 x 10^k.
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .pw = 10 ^ floor (log10 (.raw))
    .nm = .raw / .pw
    if .nm < 1.5
        niceStep = 1 * .pw
    elsif .nm < 3.5
        niceStep = 2 * .pw
    elsif .nm < 7.5
        niceStep = 5 * .pw
    else
        niceStep = 10 * .pw
    endif
endproc

# Escape Picture-window markup in names (underscore pass last).
procedure vizSafe: .s$
    vizSafe$ = replace$ (.s$, "#", "\# ", 0)
    vizSafe$ = replace$ (vizSafe$, "%", "\% ", 0)
    vizSafe$ = replace$ (vizSafe$, "^", "\^ ", 0)
    vizSafe$ = replace$ (vizSafe$, "_", "\_ ", 0)
endproc
