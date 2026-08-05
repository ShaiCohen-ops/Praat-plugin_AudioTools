# ============================================================
# Praat AudioTools - Creative_Formant_Manipulations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant manipulation using LPC source-filter decomposition.
#
#   Transparency note: LPC analysis and resynthesis is NOT transparent
#   even at neutral settings. Measured on a synthetic vowel with
#   Rotation_semitones = 0, artifact reduction off and Dry/wet = 1:
#   correlation with the input 0.905, level-matched SNR 6.58 dB. That
#   is inherent to source-filter resynthesis, not a defect, but this
#   tool always colours the sound.
#
# Improvements in v1.1:
#   - LPC order 20 (was 16) for cleaner modeling
#   - Pre-emphasis 35 Hz (was 50) for less noise
#   - Partial reversal (F1<->F3, F2<->F4) instead of full reversal
#   - Constrained scrambling (preserves energy distribution)
#   - Wider bandwidths for extreme manipulations
#
# Changelog v1.3 - Parselmouth-verified again. The v1.2 infrastructure
# work passed: relative time (correlation > 0.99999996 between the same
# signal at 0-1 s and 5-6 s), Dry/wet = 0 as true bypass (peak error
# 2.3e-13), four channels kept with their time domain, mono and
# identical-stereo output now identical, continuous Crossfade, and all
# the new validation. Two effects were still not doing what they said:
#   - REVERSAL WAS NOT A SPECTRAL FLIP. A FormantGrid filter's response
#     depends on the SET of resonances, not on which tier holds which,
#     so swapping tier labels F1<->F3 and F2<->F4 left every frequency
#     where it was. A control version that skipped the swap and applied
#     only the per-tier bandwidth multipliers matched v1.2 at
#     correlation 0.999999999, max difference 0.0000233: the effect was
#     asymmetric bandwidth broadening. Frequencies are now mirrored
#     logarithmically about [Reversal_mirror_low_hz, Max_formant_hz],
#     bandwidth is scaled by the same ratio to hold Q, and the mirrored
#     set is re-sorted ascending before it goes back into the tiers.
#   - SCRAMBLING WAS NOT RANDOM. For the same reason, permuting tiers
#     within a frame changed nothing: seed 777 against 778, and hold
#     times of 20 / 60 / 200 ms, gave sample-identical output (max
#     difference 0, correlation 1.0), and an identity mapping gave the
#     same result again. Its only audible effect was a blanket 2x
#     bandwidth widening. It now takes the whole formant set from a
#     different frame of the file, chosen at random per hold block and
#     morphed between successive choices, so the frequency set really
#     changes and seed and hold time both matter.
#   - The level match ran BEFORE artifact reduction, so the high cut
#     undid it: at 100% wet with matching on, output against input
#     measured about 0 dB at a 4500 Hz cut but -5.36 dB at 3000,
#     -52.21 dB at 2000, -56.26 dB at 1000 and -58.58 dB at 500 Hz.
#     Artifact reduction now runs first and the match is genuinely last
#     before the mix.
#   - Output_level_mode defaults to the safety ceiling, and playback
#     uses a scaled temporary copy when the peak exceeds 1.0 rather than
#     playing a clipping signal. From a 0.9-peak input, Wobble measured
#     1.590 and Vowel Morph 2.176.
#
# Changelog v1.2 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - RELATIVE TIME EVERYWHERE. Crossfade and Freezing compared absolute
#     frame times against ranges built from 0..duration, so on a Sound
#     living at 5-7 s no frame ever matched: Crossfade and Freeze output
#     were identical to plain LPC resynthesis to within 5e-15. The LFO
#     used absolute time too, so shifting the same Sound by 137 ms and
#     shifting the result back gave a correlation of only 0.702. All
#     work now happens on a copy shifted to 0 and the result is returned
#     to the source's own domain.
#   - THE ENERGY COMPENSATION DID NOTHING. "self * 3.5" followed by
#     Scale peak is exactly Scale peak: removing the multiply changed
#     the output by 4.4e-16. The Intensity matching in the mono path was
#     cancelled the same way by Scale peak: 0.99 - deleting the whole
#     Intensity calculation changed the result by 5.6e-16. Both are
#     replaced by one real RMS match against the dry channel, applied
#     once, with nothing after it to undo it.
#   - DRY/WET IS NOW A CONSISTENT RATIO. The wet signal was normalized
#     to 0.99 before mixing while the dry stayed at source level, so the
#     same 25% wet gave correlation 0.517 / 0.741 / 0.925 for input
#     peaks of 0.05 / 0.20 / 0.60. Mono and stereo also used different
#     gain paths: the same material processed both ways differed by
#     0.039 RMS at 50% wet. Both levels are natural now, the mix is a
#     true crossfade, Dry/wet = 0 is real bypass, and any output
#     normalization is optional and last.
#   - Crossfade is continuous. progress ran 0 to 1 and then snapped back
#     to 0 at each cycle boundary: F1 measured 966 Hz just before the
#     boundary at 0.667 s and 707 Hz just after, a 259 Hz jump inside
#     one frame. The trajectory is now a raised cosine, 0 -> 1 -> 0,
#     with no reset.
#   - Scrambling is reproducible and slower-moving. It re-randomized
#     every 3 ms frame with no seed, picked each track independently so
#     formants could duplicate or vanish, and five identical runs gave
#     RMS 0.029-0.050 with maximum sample jumps of 0.387-0.901. It now
#     takes an optional seed, draws a true permutation (no duplicates)
#     and holds each mapping for a settable time.
#   - Every channel is processed and kept. Any non-mono input took a
#     hard-coded two-channel branch, so 4-channel material came back as
#     2 channels with nothing said about it. This also removes the
#     duplicated stereo gain path that disagreed with the mono one.
#   - Artifact reduction is split and its high cut is a parameter. The
#     fixed stop band from max_formant_hz * 0.95 measured 23.8 dB of
#     attenuation above 5.2 kHz at default settings - a heavy low-pass,
#     not a gentle de-click. De-click and high cut are now separate
#     choices, and the de-click no longer reads self[col-1] at the first
#     sample or self[col+1] at the last.
#   - Validation: minimum duration for To LPC / To FormantPath (80 ms
#     failed, 100 ms worked), max_formant_hz x 1.22 against Nyquist
#     (To FormantPath searches four ceilings 5% apart, so the default
#     5500 Hz needs about 13.4 kHz of sample rate), positive scaling
#     factors (Scale_bandwidth < 0 was a run-time error), Dry/wet in
#     0..1, and LFO depth at most 100%.
#   - Visualization: axes follow the work copy, the formant panel scales
#     to the formants actually drawn instead of a fixed 3500 Hz, the
#     spectrograms follow Max_formant_hz instead of a fixed 5000 Hz, and
#     the two waveform panels share a Y range so gain changes show.
#   - Non-ASCII characters replaced with ASCII for console portability.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Creative Formant Manipulations v1.3
    optionmenu Preset: 1
        option Manual
        option Robot Voice
        option Chipmunk
        option Giant
        option Alien
        option Wobble
        option Vowel Morph
    optionmenu Manipulation_type: 1
        option Rotation (vowel morphing)
        option Reversal (spectral flip)
        option Scrambling (randomize)
        option Scaling (gender shift)
        option LFO Modulation
        option Crossfade (temporal blend)
        option Freezing (hold vowels)
    positive Max_formant_hz 5500
    real Rotation_semitones 3.0
    positive Scale_frequency 0.8
    positive Scale_bandwidth 1.2
    positive Lfo_rate 2.0
    positive Lfo_depth 6.0
    positive Freeze_interval 0.3
    positive Freeze_duration 0.15
    comment === Reversal ===
    positive Reversal_mirror_low_hz 200
    comment (frequencies are mirrored between this and Max_formant_hz)
    comment === Scrambling ===
    positive Scramble_hold_ms 60
    integer Random_seed 0
    comment (0 = unseeded; any other value makes the run reproducible)
    comment === Output ===
    real Dry_wet_mix 1.0
    boolean Match_input_level 1
    optionmenu Artifact_reduction: 2
        option None
        option De-click only
        option De-click + high cut
    positive High_cut_hz 5225
    optionmenu Output_level_mode: 2
        option None (natural level)
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
    manipulation_type = 7
    freeze_interval = 0.08
    freeze_duration = 0.08
    presetName$ = "Robot"
elsif preset = 3
    manipulation_type = 4
    scale_frequency = 1.4
    scale_bandwidth = 0.8
    presetName$ = "Chipmunk"
elsif preset = 4
    manipulation_type = 4
    scale_frequency = 0.7
    scale_bandwidth = 1.3
    presetName$ = "Giant"
elsif preset = 5
    manipulation_type = 2
    dry_wet_mix = 0.8
    presetName$ = "Alien"
elsif preset = 6
    manipulation_type = 5
    lfo_rate = 4.0
    lfo_depth = 8.0
    presetName$ = "Wobble"
elsif preset = 7
    manipulation_type = 6
    presetName$ = "VowelMorph"
else
    presetName$ = "Manual"
endif

# ============================================================
# Fixed analysis parameters
# ============================================================
time_step = 0.003
max_formants = 5
window_length = 0.030
lpc_order = 20
preEmphasis = 35
crossfade_cycles = 3

# ============================================================
# Setup and validation
# ============================================================
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2

# To FormantPath searches four ceilings above the middle one, 5% apart,
# so the highest ceiling it actually uses is about max_formant x 1.22.
# Checking only max_formant < Nyquist is not enough: the default
# 5500 Hz needs roughly 13.4 kHz of sample rate.
if max_formant_hz * 1.22 >= nyquist
    exitScript: "Max_formant_hz " + fixed$(max_formant_hz, 0) + " Hz needs a sample rate of " +
    ... "at least " + fixed$(max_formant_hz * 1.22 * 2, 0) + " Hz. To FormantPath searches " +
    ... "four ceilings 5% apart above the value you give, so the highest is about " +
    ... fixed$(max_formant_hz * 1.22, 0) + " Hz against a Nyquist of " + fixed$(nyquist, 0) +
    ... " Hz. Lower Max_formant_hz or resample the Sound."
endif

# LPC and FormantPath both need several analysis windows. 80 ms failed
# in testing and 100 ms worked; four windows is a safe floor.
minDur = window_length * 4
if duration < minDur
    exitScript: "Sound is too short: " + fixed$(duration * 1000, 1) + " ms. The " +
    ... fixed$(window_length * 1000, 0) + " ms LPC window needs at least " +
    ... fixed$(minDur * 1000, 0) + " ms of audio."
endif

if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1 (got " + fixed$(dry_wet_mix, 3) + ")."
endif
if lfo_depth > 100
    exitScript: "Lfo_depth is a percentage and must be at most 100 (got " +
    ... fixed$(lfo_depth, 1) + "). Above 100 the modulation factor goes negative."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(ceiling_peak, 3) + ")."
endif
if artifact_reduction = 3
    if high_cut_hz >= nyquist
        high_cut_hz = nyquist - 100
    endif
endif

if random_seed <> 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

scrambleHold = scramble_hold_ms / 1000

# Manipulation name
if manipulation_type = 1
    manipName$ = "Rotation"
elsif manipulation_type = 2
    manipName$ = "Reversal"
elsif manipulation_type = 3
    manipName$ = "Scrambling"
elsif manipulation_type = 4
    manipName$ = "Scaling"
elsif manipulation_type = 5
    manipName$ = "LFO"
elsif manipulation_type = 6
    manipName$ = "Crossfade"
else
    manipName$ = "Freeze"
endif

clearinfo
writeInfoLine: "=== Creative Formant Manipulations v1.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Effect: ", manipName$
appendInfoLine: "Input:  ", originalName$, " (", fixed$(duration, 3), " s, ",
    ... numChannels, " ch, ", sampleRate, " Hz)"
appendInfoLine: "LPC order ", lpc_order, ", pre-emphasis ", preEmphasis, " Hz"
appendInfoLine: "NOTE: LPC resynthesis is not transparent even at neutral settings."
appendInfoLine: ""

# ============================================================
# Work copy at time 0
# ============================================================
# Frame times come back in the Sound's own coordinates, while the LFO,
# Crossfade and Freeze ranges are all built from 0. v1.1 mixed the two,
# so on a Sound at 5-7 s the time-based effects simply never fired.
selectObject: sound
workSound = Copy: "cfm_work"
Shift times to: "start time", 0

if numChannels > 1
    selectObject: workSound
    soundMono = Convert to mono
else
    selectObject: workSound
    soundMono = Copy: "mono_work"
endif

# ============================================================
# STEP 1: Analyze formants (shared across channels)
# ============================================================
appendInfoLine: "[1/4] Analyzing formants..."

selectObject: soundMono
formantPath = To FormantPath (burg): time_step, max_formants, max_formant_hz,
    ... window_length, preEmphasis, 0.05, 4
formantObj = Extract Formant

selectObject: formantObj
numFrames = Get number of frames
appendInfoLine: "  Frames: ", numFrames

# Cache formant data
for i from 1 to numFrames
    selectObject: formantObj
    frameTime_'i' = Get time from frame number: i
    numFormantsInFrame_'i' = Get number of formants: i

    for f from 1 to max_formants
        formantFreq_'i'_'f' = undefined
        formantBand_'i'_'f' = undefined
        origFormantFreq_'i'_'f' = undefined
        origFormantBand_'i'_'f' = undefined
    endfor

    nf = numFormantsInFrame_'i'
    for f from 1 to nf
        ft = frameTime_'i'
        formantFreq_'i'_'f' = Get value at time: f, ft, "hertz", "Linear"
        formantBand_'i'_'f' = Get bandwidth at time: f, ft, "hertz", "Linear"
        origFormantFreq_'i'_'f' = formantFreq_'i'_'f'
        origFormantBand_'i'_'f' = formantBand_'i'_'f'
    endfor
endfor

selectObject: formantObj
formantGrid = Down to FormantGrid

# ============================================================
# STEP 2: Apply manipulation
# ============================================================
appendInfoLine: "[2/4] Applying ", manipName$, "..."

selectObject: formantGrid

# --- ROTATION ---
if manipulation_type = 1
    factor = 2 ^ (rotation_semitones / 12)
    for i from 1 to numFrames
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        for f from 1 to nf
            hz = formantFreq_'i'_'f'
            if hz <> undefined
                newHz = hz * factor
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- REVERSAL (true log mirror of the frequencies) ---
elsif manipulation_type = 2
    # A FormantGrid filter's response depends on the SET of resonances,
    # not on which tier holds which. v1.2 swapped tier LABELS
    # (F1<->F3, F2<->F4) and left every frequency exactly where it was,
    # so the only audible effect was the per-tier bandwidth multiplier:
    # a control version that skipped the swap entirely and applied only
    # those multipliers matched the v1.2 output at correlation
    # 0.999999999, max difference 0.0000233. That is asymmetric
    # bandwidth broadening, not a spectral flip.
    #
    # The frequencies themselves are mirrored now, logarithmically
    # about the band [mirror_low, max_formant]:
    #   new = exp(ln(low) + ln(high) - ln(old))
    # Bandwidth is scaled by the same ratio, which holds Q constant, and
    # the mirrored set is re-sorted ascending before it goes back into
    # the tiers.
    appendInfoLine: "  Log mirror about ", fixed$(reversal_mirror_low_hz, 0), "-",
        ... fixed$(max_formant_hz, 0), " Hz"
    logSum = ln(reversal_mirror_low_hz) + ln(max_formant_hz)

    for i from 1 to numFrames
        ft = frameTime_'i'
        nf = numFormantsInFrame_'i'

        nKeep = 0
        for f from 1 to nf
            hz = origFormantFreq_'i'_'f'
            bw = origFormantBand_'i'_'f'
            if hz <> undefined and hz > 0
                newHz = exp(logSum - ln(hz))
                if newHz > 20 and newHz < max_formant_hz
                    if bw = undefined or bw <= 0
                        bw = 100
                    endif
                    newBw = bw * (newHz / hz)
                    if newBw < 20
                        newBw = 20
                    endif
                    if newBw > 3000
                        newBw = 3000
                    endif
                    nKeep = nKeep + 1
                    sortF_'nKeep' = newHz
                    sortB_'nKeep' = newBw
                endif
            endif
        endfor

        # Insertion sort, ascending by frequency (at most 5 items).
        # Written without a compound while condition, because Praat does
        # not guarantee short-circuit evaluation and sortF_'0' would be
        # an undefined variable.
        for a from 2 to nKeep
            keyF = sortF_'a'
            keyB = sortB_'a'
            b = a - 1
            placed = 0
            while placed = 0
                if b < 1
                    placed = 1
                else
                    if sortF_'b' > keyF
                        b1 = b + 1
                        sortF_'b1' = sortF_'b'
                        sortB_'b1' = sortB_'b'
                        b = b - 1
                    else
                        placed = 1
                    endif
                endif
            endwhile
            b1 = b + 1
            sortF_'b1' = keyF
            sortB_'b1' = keyB
        endfor

        for f from 1 to nKeep
            newHz = sortF_'f'
            newBw = sortB_'f'
            Remove formant points between: f, ft - 0.0001, ft + 0.0001
            Add formant point: f, ft, newHz
            Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
            Add bandwidth point: f, ft, newBw
            formantFreq_'i'_'f' = newHz
            formantBand_'i'_'f' = newBw
        endfor
    endfor

# --- SCRAMBLING (random vowel mosaic across TIME) ---
elsif manipulation_type = 3
    # v1.2 permuted the tier order within a frame, which for the same
    # reason as Reversal changed nothing: seed 777 against 778, and hold
    # times of 20 / 60 / 200 ms, all produced sample-identical output
    # (max difference 0, correlation 1.0), and replacing the permutation
    # with an identity mapping changed nothing either. Its only audible
    # effect was the blanket 2x bandwidth widening.
    #
    # Scrambling now takes the whole formant set from a DIFFERENT frame
    # of the file, chosen at random per hold block, and morphs between
    # successive choices so the tracks do not jump. The frequency set
    # genuinely changes, so seed and hold time both matter.
    if random_seed <> 0
        appendInfoLine: "  Seed: ", random_seed, " (reproducible)"
    else
        appendInfoLine: "  Unseeded: successive runs will differ"
    endif
    appendInfoLine: "  Donor frame held ", fixed$(scramble_hold_ms, 0), " ms"

    blendDur = min(scrambleHold * 0.5, 0.03)
    prevDonor = 1
    curDonor = 1
    blockStart = 0
    nextRegen = -1
    blockCount = 0

    for i from 1 to numFrames
        ft = frameTime_'i'
        nf = numFormantsInFrame_'i'

        if ft >= nextRegen
            prevDonor = curDonor
            curDonor = randomInteger(1, numFrames)
            blockStart = ft
            nextRegen = ft + scrambleHold
            blockCount = blockCount + 1
        endif

        if blendDur > 0
            p = (ft - blockStart) / blendDur
            if p > 1
                p = 1
            endif
        else
            p = 1
        endif
        w = 0.5 - 0.5 * cos(pi * p)

        for f from 1 to nf
            aF = origFormantFreq_'prevDonor'_'f'
            bF = origFormantFreq_'curDonor'_'f'
            aB = origFormantBand_'prevDonor'_'f'
            bB = origFormantBand_'curDonor'_'f'
            if aF = undefined
                aF = bF
                aB = bB
            endif
            if bF = undefined
                bF = aF
                bB = aB
            endif
            if aF <> undefined and bF <> undefined
                newHz = aF + w * (bF - aF)
                if aB = undefined or bB = undefined
                    newBw = 100
                else
                    newBw = aB + w * (bB - aB)
                endif
                if newBw < 20
                    newBw = 20
                endif
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                    Add bandwidth point: f, ft, newBw
                    formantFreq_'i'_'f' = newHz
                    formantBand_'i'_'f' = newBw
                endif
            endif
        endfor
    endfor
    appendInfoLine: "  ", blockCount, " donor frames over the file"

# --- SCALING ---
elsif manipulation_type = 4
    for i from 1 to numFrames
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        for f from 1 to nf
            hz = formantFreq_'i'_'f'
            bw = formantBand_'i'_'f'
            if hz <> undefined
                newHz = hz * scale_frequency
                newBw = bw * scale_bandwidth
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    Remove bandwidth points between: f, ft - 0.0001, ft + 0.0001
                    Add bandwidth point: f, ft, newBw
                    formantFreq_'i'_'f' = newHz
                    formantBand_'i'_'f' = newBw
                endif
            endif
        endfor
    endfor

# --- LFO MODULATION ---
elsif manipulation_type = 5
    for i from 1 to numFrames
        nf = numFormantsInFrame_'i'
        ft = frameTime_'i'
        # ft is relative to the start of the Sound, so the LFO phase no
        # longer depends on where the Sound sits on the timeline.
        modFactor = 1 + (lfo_depth / 100) * sin(2 * pi * lfo_rate * ft)
        for f from 1 to nf
            hz = formantFreq_'i'_'f'
            if hz <> undefined
                newHz = hz * modFactor
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- CROSSFADE ---
elsif manipulation_type = 6
    # Raised cosine, 0 -> 1 -> 0 per cycle, so the trajectory is
    # continuous across cycle boundaries. v1.1 ramped 0 to 1 and snapped
    # back: F1 measured 966 Hz just before the boundary at 0.667 s and
    # 707 Hz just after, a 259 Hz jump inside a single frame.
    cycleDur = duration / crossfade_cycles
    for i from 1 to numFrames
        ft = frameTime_'i'
        phase = ft / cycleDur
        progress = 0.5 - 0.5 * cos(2 * pi * phase)

        nf = numFormantsInFrame_'i'
        for f from 1 to nf
            origHz = origFormantFreq_'i'_'f'
            if f < max_formants
                targetF = f + 1
                if targetF <= nf
                    targetHz = origFormantFreq_'i'_'targetF'
                else
                    targetHz = origHz
                endif
            else
                targetHz = origHz
            endif

            if origHz <> undefined and targetHz <> undefined
                newHz = origHz + progress * (targetHz - origHz)
                if newHz > 0 and newHz < max_formant_hz
                    Remove formant points between: f, ft - 0.0001, ft + 0.0001
                    Add formant point: f, ft, newHz
                    formantFreq_'i'_'f' = newHz
                endif
            endif
        endfor
    endfor

# --- FREEZING ---
elsif manipulation_type = 7
    currTime = 0
    while currTime < duration
        freezeTime = currTime + freeze_duration / 2

        freezeIdx = 0
        minDist = 99999
        for i from 1 to numFrames
            ft = frameTime_'i'
            dist = abs(ft - freezeTime)
            if dist < minDist
                minDist = dist
                freezeIdx = i
            endif
        endfor

        if freezeIdx > 0
            nfFreeze = numFormantsInFrame_'freezeIdx'
            for k from 1 to numFrames
                ft = frameTime_'k'
                if ft >= currTime and ft < currTime + freeze_duration
                    for f from 1 to max_formants
                        if f <= nfFreeze
                            hzFreeze = origFormantFreq_'freezeIdx'_'f'
                            if hzFreeze <> undefined
                                Remove formant points between: f, ft - 0.0001, ft + 0.0001
                                Add formant point: f, ft, hzFreeze
                                formantFreq_'k'_'f' = hzFreeze
                            endif
                        endif
                    endfor
                endif
            endfor
        endif

        currTime = currTime + freeze_interval
    endwhile
endif

# ============================================================
# STEP 3: Resynthesize every channel through the same grid
# ============================================================
# One gain path for mono and multichannel alike. v1.1 had two, which
# disagreed: the same material processed as mono and as identical
# stereo differed by 0.039 RMS at 50% wet.
appendInfoLine: "[3/4] Resynthesizing ", numChannels, " channel(s)..."

gridId$ = string$(formantGrid)

for ch from 1 to numChannels
    if numChannels = 1
        selectObject: workSound
        dryCh[ch] = Copy: "dry_ch"
    else
        selectObject: workSound
        dryCh[ch] = Extract one channel: ch
    endif

    selectObject: dryCh[ch]
    lpcCh = To LPC (burg): lpc_order, window_length, time_step, preEmphasis
    selectObject: dryCh[ch]
    plusObject: lpcCh
    srcCh = Filter (inverse)

    selectObject: srcCh
    plusObject: formantGrid
    wetCh[ch] = Filter
    removeObject: lpcCh, srcCh

    # --- Artifact reduction FIRST ---
    # v1.2 matched the level and then filtered, so the high cut undid
    # the match: with Match_input_level on and 100% wet, output level
    # against input measured about 0 dB at a 4500 Hz cut but -5.36 dB at
    # 3000, -52.21 dB at 2000, -56.26 dB at 1000 and -58.58 dB at
    # 500 Hz. Anything that changes the level has to run before the
    # thing that measures it.
    if artifact_reduction > 1
        selectObject: wetCh[ch]
        nSampCh = Get number of samples
        if artifact_reduction = 3
            selectObject: wetCh[ch]
            hiCut = Filter (stop Hann band): high_cut_hz, nyquist, 100
            removeObject: wetCh[ch]
            wetCh[ch] = hiCut
            selectObject: wetCh[ch]
            nSampCh = Get number of samples
        endif
        # De-click over the interior only: v1.1 read self[col-1] at the
        # first sample and self[col+1] at the last.
        if nSampCh > 2
            selectObject: wetCh[ch]
            Formula (part): 1.5 / sampleRate, (nSampCh - 1.5) / sampleRate, 1, 1,
                ... "if abs(self - self[col-1]) > 0.5 then (self[col-1] + self[col+1]) / 2 else self fi"
        endif
    endif

    # --- Real level match, applied once, with nothing after it ---
    # v1.1 multiplied by a constant 3.5 and then ran Scale peak, which
    # is exactly Scale peak: removing the multiply changed the output by
    # 4.4e-16. The Intensity match was cancelled the same way.
    if match_input_level
        selectObject: dryCh[ch]
        dryRms = Get root-mean-square: 0, 0
        selectObject: wetCh[ch]
        wetRms = Get root-mean-square: 0, 0
        if wetRms > 0 and dryRms > 0
            matchGain = dryRms / wetRms
            # Clamp to +/- 24 dB so a near-silent resynthesis cannot
            # explode
            if matchGain > 15.849
                matchGain = 15.849
            endif
            if matchGain < 0.0631
                matchGain = 0.0631
            endif
            selectObject: wetCh[ch]
            Formula: "self * " + string$(matchGain)
            if ch = 1
                appendInfoLine: "  Level match ch1: x", fixed$(matchGain, 4),
                    ... " (", fixed$(20 * log10(matchGain), 1), " dB)"
                if matchGain > 15.8 or matchGain < 0.064
                    appendInfoLine: "    (clamped at +/- 24 dB)"
                endif
            endif
        endif
    endif

    # --- Dry/wet, both at natural level ---
    if dry_wet_mix < 1
        selectObject: wetCh[ch]
        Formula: string$(dry_wet_mix) + " * self + " + string$(1 - dry_wet_mix) +
            ... " * object(" + string$(dryCh[ch]) + ", x)"
    endif
endfor

# --- Assemble ---
if numChannels = 1
    selectObject: wetCh[1]
    finalOutput = Copy: "cfm_out"
    removeObject: wetCh[1]
else
    selectObject: wetCh[1]
    outDurCh = Get total duration
    Create Sound from formula: "cfm_out", numChannels, 0, outDurCh, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to numChannels
        selectObject: finalOutput
        Formula (part): 0, outDurCh, ch, ch,
            ... "object[" + string$(wetCh[ch]) + ", 1, col]"
    endfor
    for ch from 1 to numChannels
        removeObject: wetCh[ch]
    endfor
endif

for ch from 1 to numChannels
    removeObject: dryCh[ch]
endfor

# ============================================================
# STEP 4: Output level stage (optional, and last)
# ============================================================
appendInfoLine: "[4/4] Finalizing..."

selectObject: finalOutput
pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

if output_level_mode = 2
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

selectObject: finalOutput
out_peak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    # Shared Y range for the two waveform panels, so a level change is
    # visible instead of being auto-scaled away.
    selectObject: workSound
    origPeakViz = Get absolute extremum: 0, 0, "None"
    vizMax = max(origPeakViz, out_peak)
    if vizMax < 0.001
        vizMax = 0.001
    endif
    vizAmp = vizMax * 1.15

    # Highest formant actually drawn, so shifted formants stay on screen
    drawMaxFreq = 3500
    for i from 1 to numFrames
        for f from 1 to 3
            fq = formantFreq_'i'_'f'
            if fq <> undefined and fq > drawMaxFreq
                drawMaxFreq = fq
            endif
            fq = origFormantFreq_'i'_'f'
            if fq <> undefined and fq > drawMaxFreq
                drawMaxFreq = fq
            endif
        endfor
    endfor
    drawMaxFreq = min(drawMaxFreq * 1.05, max_formant_hz)

    specCeil = min(nyquist, max(5000, max_formant_hz))

    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Creative Formant Manipulations##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.2, "half",
        ... originalName$ + "  |  " + presetName$ + "  |  " + manipName$
        ... + "  |  dry/wet " + fixed$(dry_wet_mix, 2)
        ... + "  |  " + string$(numChannels) + " ch"

    # Original waveform
    Select outer viewport: 0, 4, 0.6, 2.0
    Select inner viewport: 0.6, 3.7, 0.7, 1.95
    selectObject: workSound
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Waveform (shared scale)"

    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 2.0
    Select inner viewport: 4.4, 7.7, 0.7, 1.95
    selectObject: finalOutput
    Colour: "{0.30, 0.70, 0.50}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Processed"
    Text bottom: "yes", "Time (s)"

    # FORMANT TRAJECTORIES
    Select outer viewport: 0, 8, 2.1, 4.0
    Select inner viewport: 0.6, 7.7, 2.2, 3.95

    Axes: 0, duration, 0, drawMaxFreq
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, drawMaxFreq

    Colour: "{0.70, 0.70, 0.70}"
    Dotted line
    for f from 1 to 3
        for i from 1 to numFrames - 1
            i_next = i + 1
            t1 = frameTime_'i'
            t2 = frameTime_'i_next'
            freq1 = origFormantFreq_'i'_'f'
            freq2 = origFormantFreq_'i_next'_'f'
            if freq1 <> undefined and freq2 <> undefined
                Draw line: t1, freq1, t2, freq2
            endif
        endfor
    endfor
    Solid line

    formant_colors$# = {"{0.30, 0.60, 0.90}", "{0.90, 0.50, 0.30}", "{0.30, 0.80, 0.50}"}
    for f from 1 to 3
        Colour: formant_colors$#[f]
        Line width: 2
        for i from 1 to numFrames - 1
            i_next = i + 1
            t1 = frameTime_'i'
            t2 = frameTime_'i_next'
            freq1 = formantFreq_'i'_'f'
            freq2 = formantFreq_'i_next'_'f'
            if freq1 <> undefined and freq2 <> undefined
                Draw line: t1, freq1, t2, freq2
            endif
        endfor
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Formant trajectories (grey = original, colour = modified)"
    Text bottom: "yes", "Time (s)"

    Font size: 5
    Colour: "{0.30, 0.60, 0.90}"
    Text: duration * 0.95, "right", drawMaxFreq * 0.15, "half", "F1"
    Colour: "{0.90, 0.50, 0.30}"
    Text: duration * 0.95, "right", drawMaxFreq * 0.45, "half", "F2"
    Colour: "{0.30, 0.80, 0.50}"
    Text: duration * 0.95, "right", drawMaxFreq * 0.72, "half", "F3"

    # Original spectrogram
    Select outer viewport: 0, 4, 4.1, 6.0
    Select inner viewport: 0.6, 3.7, 4.2, 5.95

    selectObject: workSound
    if numChannels > 1
        spec_source = Extract one channel: 1
    else
        spec_source = Copy: "spec_source"
    endif
    To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    orig_spec = selected("Spectrogram")
    Paint: 0, 0, 0, specCeil, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original spectrogram (to " + fixed$(specCeil, 0) + " Hz)"

    removeObject: orig_spec, spec_source

    # Processed spectrogram
    Select outer viewport: 4, 8, 4.1, 6.0
    Select inner viewport: 4.4, 7.7, 4.2, 5.95

    selectObject: finalOutput
    if numChannels > 1
        spec_proc = Extract one channel: 1
    else
        spec_proc = Copy: "spec_proc"
    endif
    To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    proc_spec = selected("Spectrogram")
    Paint: 0, 0, 0, specCeil, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Processed spectrogram (to " + fixed$(specCeil, 0) + " Hz)"

    removeObject: proc_spec, spec_proc

    # Summary panel
    Select outer viewport: 0, 8, 6.1, 7.0
    Select inner viewport: 0.6, 7.7, 6.2, 6.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if artifact_reduction = 1
        artStr$ = "none"
    elsif artifact_reduction = 2
        artStr$ = "de-click"
    else
        artStr$ = "de-click + high cut " + fixed$(high_cut_hz, 0) + " Hz"
    endif
    if output_level_mode = 1
        levelStr$ = "natural"
    elsif output_level_mode = 2
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2) + " (" + level_action$ + ")"
    else
        levelStr$ = "normalized to " + fixed$(ceiling_peak, 2)
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.85, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.58, "half",
        ... "Effect: " + manipName$
        ... + "  |  Frames: " + string$(numFrames)
        ... + "  |  LPC order: " + string$(lpc_order)
        ... + "  |  Pre-emphasis: " + string$(preEmphasis) + " Hz"
        ... + "  |  Max formant: " + fixed$(max_formant_hz, 0) + " Hz"
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
    Text: 0.02, "left", 0.28, "half",
        ... "Dry/wet: " + fixed$(dry_wet_mix, 2)
        ... + "  |  Level match: " + string$(match_input_level)
        ... + "  |  Artifacts: " + artStr$
        ... + "  |  Peak in: " + fixed$(origPeakViz, 3)
        ... + "  |  Peak out: " + fixed$(out_peak, 3)
        ... + "  |  Output: " + levelStr$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: finalOutput
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_" + manipName$ + "_" + presetName$
finalName$ = selected$("Sound")

removeObject: soundMono, formantPath, formantObj, formantGrid, workSound

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "  Peak before output stage: ", fixed$(pre_level_peak, 4)
if output_level_mode = 1
    appendInfoLine: "  Output stage: none (natural level)"
elsif output_level_mode = 2
    appendInfoLine: "  Output stage: safety ceiling ", fixed$(ceiling_peak, 2), " - ", level_action$
else
    appendInfoLine: "  Output stage: peak normalize to ", fixed$(ceiling_peak, 2),
        ... " (x", fixed$(level_gain, 4), ")"
    appendInfoLine: "  NOTE: this makes Dry/wet a level-dependent ratio again."
endif
if output_level_mode <> 3 and out_peak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

if play_after_processing
    if out_peak > 1
        # Play a scaled copy rather than a clipping one. With the output
        # stage off, Wobble and Vowel Morph measured peaks of 1.590 and
        # 2.176 from a 0.9-peak input; the file itself is left untouched.
        appendInfoLine: "Playing a scaled copy (peak ", fixed$(out_peak, 3),
            ... " exceeds 1.0; the Sound object keeps its level)..."
        selectObject: finalOutput
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        appendInfoLine: "Playing result..."
        selectObject: finalOutput
        Play
    endif
endif

selectObject: finalOutput
