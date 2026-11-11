# ============================================================
# Praat AudioTools - Onset-Based Oscillator Bank
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.7 (2026) - original sample rate only; Dry/Wet (%) independent
#          of presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Onset-triggered resonator bank. Detects onsets from Intensity-rise
#   candidates, refines their timing, extracts pitch, and synthesizes
#   harmonic bursts with attack/decay envelopes. Each valid-pitch onset
#   triggers a multi-partial oscillator
#   with detuning, brightness control, and waveshaping.
#
# Features:
#   - Intensity-based onset detection with configurable threshold
#   - Autocorrelation pitch extraction with value/mean/median fallbacks
#   - Harmonic oscillator bank (1-32 partials) with detuning
#   - Attack + exponential-decay envelopes with randomization
#   - Cubic waveshaping for brightness, with Nyquist-safe 3rd harmonic
#   - Velocity sensitivity (onset strength -> burst amplitude)
#   - Comprehensive visualization: onsets, valid pitches, bursts
#   - 6 presets from gentle to dense
#
# Categories: Resynthesis, Pitch-Based Effects, Creative Effects
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.7 (2026):
#   - Speed_mode removed: analysis and synthesis always run at the
#     original sample rate (= v2.6 "Full Quality"). Downsampling changed
#     the analysed signal, the pitch decisions and the highest partials,
#     not only the processing time.
#   - Dry_wet_(%) 0-100, default 100 (synthesis only), is the user's value
#     in every preset and pitch mode: presets no longer set it (they used
#     to force 70/100/80/100/90/100 %). 0 % = the source exactly, 100 % =
#     the synthesis exactly, anything between = a linear mix (the old
#     <= 1 % / >= 99 % shortcuts are gone).
#   - Presets still set the character of the synthesis (partials, spread,
#     decay, brightness, attack, waveshaping) and their onset settings;
#     pitch estimation, stagger and synthesis are unchanged.
#
# Changelog v2.6 (2026):
#   - Pitch_estimation replaces the Octave_diagnostics checkbox:
#       1 Legacy v2.3 (default; the v2.3 estimate, nothing else)
#       2 Legacy v2.3 + octave diagnostics (report only, as v2.5)
#       3 Context-aware, unpitched events skipped
#       4 Context-aware, unpitched events take the nearest pitch
#   - Why: v2.3 reads the pitch at the onset, 20 ms into a segment whose
#     first pitch frame lies ~30 ms in, so the read is undefined and the
#     MEAN of the segment is used: one octave-low or noise frame (e.g.
#     1573 Hz among 155-169 Hz) moves the result; a short segment over a
#     note transition can lock onto the sub-octave (flute 327 -> 162 Hz).
#   - Context-aware: one continuous pitch track of the whole sound (Praat
#     standard settings: path search across frames, octave-jump cost 0.35),
#     so each frame is chosen with its neighbours in view. The onset still
#     fixes WHEN the burst starts; the pitch is taken from the frames
#     15 ms after the onset up to the next onset (at most 200 ms): the
#     largest group of frames within +/-3 semitones of each other, and its
#     median. Fewer than 3 agreeing voiced frames (~45 ms) = no stable
#     periodicity: the event is "unpitched" (consonant, noise) and is
#     skipped (3) or rendered at the pitch of the nearest pitched event (4).
#     No spectral octave rule changes any pitch.
#   - Info: per-event table with the v2.3 estimate beside the new one;
#     figure: the continuous track in grey behind the event pitches.
#
# Changelog v2.5 (2026):
#   Built on v2.3 (the unreleased v2.4 robust-pitch draft is withdrawn).
#   Onset detection, pitch extraction, presets and synthesis are the v2.3
#   code. With the new controls at their defaults the output is the v2.3
#   output, sample for sample (same random state).
#   - Pitch_floor_(Hz) 50 (v2.3 value) and Pitch_ceiling_(Hz) 0 = automatic,
#     i.e. the v2.3 ceiling: working sample rate / 4, at most 4 kHz.
#     A ceiling entered by hand may go up to sample rate / 4.
#   - Attack_stagger_(ms), default 0 = off, and Attack_stagger_mode
#     (random uniform, random Gaussian-like, ascending, descending
#     spectral): each partial (with its waveshaping 3rd harmonic) may start
#     up to that many ms after the onset. Presets never set or override it.
#     All v2.3 random draws happen first, in the v2.3 order; the entrance
#     delays come afterwards, so changing the stagger does not change
#     frequencies, attacks, decays or amplitudes. A delayed partial is
#     silent until its entrance and starts at zero phase, so the entrance
#     is continuous. The burst is lengthened by the largest delay.
#   - Random_seed: 0 = v2.3 behaviour (unseeded); > 0 makes a run
#     repeatable, with a separate stream for the stagger.
#   - Octave_diagnostics (report only): a spectrum of each event, gated by
#     the spectrum just before the onset, is checked for evidence that the
#     detected pitch is an octave (or other integer multiple) off, or that
#     the event is not a single harmonic series. The result is printed per
#     event and marked in the pitch panel; nothing is corrected or skipped.
#   - Fix: an onset in the last ~60 ms made To Pitch stop the script
#     (segment shorter than three periods of the floor); the floor is now
#     raised for such a short segment only.
#   - Summary/figure: stagger, seed and diagnostics shown; output name no
#     longer printed with subscripts.
#
# Changelog v2.3 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v2.2:
#   - Locally refines Intensity onset candidates with short RMS windows.
#   - Uses a 0-based mono analysis copy; restores the original start time.
#   - Preserves arbitrary channel counts (wet bank is identical per channel).
#   - Removes the fixed 500-onset limit.
#   - Pitch ceiling follows the working sample rate up to 4 kHz.
#   - Expands cubic waveshaping analytically and suppresses aliased 3rd harmonics.
#   - Peak safety only attenuates; it never boosts quiet output.
#   - Adds parameter clamps and correct stopwatch timing.
#
# Changelog v2.1:
#
#   PRAAT-SIDE POLISH (no audio change):
#     - Dropped 5 decorative `comment === ... ===` form rows
#       (PRESETS / Onset Detection / Oscillators / Performance /
#       Output). Form: 20 rows -> 15 rows. All optionmenus already
#       had colons.
#     - Title font 14 -> 12 in visualization (suite standard).
#     - Visualization rewritten from custom 5-panel layout to
#       suite 8x8 standard:
#         Title bar (suite light) + metadata subtitle
#         Panel A (left, headline): original waveform + onsets
#         Panel B (right, headline): processed output waveform
#         Panel C: detected pitches per onset
#         Panel D: onset velocities (with valid-pitch coloring)
#         Panel E: light-grey summary stats bar (suite standard)
#
#   SMALL FIXES (no audio change):
#     - Final selection: now selects the output Sound at end
#       (v2.0 selected the original sound, inconsistent with the
#       rest of the suite which ends on the generated output).
#     - Consolidated `numChan` (line 189 of v2.0) and `numChannels`
#       (line 447) into a single `numChan` variable. Both held the
#       same value (channel count of the original sound) and were
#       used in different sections; now there is one variable.
#
#   Audio output is bit-identical to v2.0 for any given input,
#   preset, and random seed state.
# ============================================================

form Onset-Based Oscillator Bank v2.7
    optionmenu Preset: 1
        option Custom
        option Gentle Resonance
        option Percussive Bells
        option Ethereal Pad
        option Metallic Shimmer
        option Natural Pluck
        option Dense Cluster
    positive Onset_threshold_(dB) 1.5
    positive Min_intensity_(dB) 35.0
    positive Min_interval_(s) 0.1
    positive Pitch_floor_(Hz) 50
    real Pitch_ceiling_(Hz,_0_=_auto) 0
    optionmenu Pitch_estimation: 1
        option Legacy v2.3
        option Legacy v2.3 + octave diagnostics (report only)
        option Context-aware, unpitched events skipped
        option Context-aware, unpitched events use nearest pitch
    boolean Velocity_sensitive 1
    integer Num_partials 12
    positive Partial_spread_(percent) 0.5
    positive Decay_(s) 1.5
    real Brightness 0.7
    real Attack_stagger_(ms) 0
    optionmenu Attack_stagger_mode: 1
        option Random uniform
        option Random Gaussian-like
        option Ascending spectral (low first)
        option Descending spectral (high first)
    integer Random_seed_(0_=_unseeded) 0
    positive Tail_duration_(s) 2.0
    positive Fadeout_duration_(s) 0.5
    real Dry_wet_(%) 100
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET DEFINITIONS
# ============================================================
attackBase = 0.005
attackRandom = 0.01
decayRandom = 0.5
ampRandom = 0.3
waveshapeAmt = 0.2
decayTime = decay

if preset = 2
    # Gentle Resonance
    onset_threshold = 2.0
    min_intensity = 35.0
    min_interval = 0.15
    num_partials = 8
    partial_spread = 0.3
    decayTime = 2.0
    brightness = 0.5
    attackBase = 0.01
    waveshapeAmt = 0.1
    presetName$ = "GentleResonance"
elsif preset = 3
    # Percussive Bells
    onset_threshold = 1.5
    min_intensity = 40.0
    min_interval = 0.08
    num_partials = 15
    partial_spread = 0.8
    decayTime = 1.0
    brightness = 0.9
    attackBase = 0.002
    waveshapeAmt = 0.3
    presetName$ = "PercussiveBells"
elsif preset = 4
    # Ethereal Pad
    onset_threshold = 2.5
    min_intensity = 30.0
    min_interval = 0.2
    num_partials = 20
    partial_spread = 0.2
    decayTime = 3.5
    brightness = 0.6
    attackBase = 0.05
    waveshapeAmt = 0.15
    presetName$ = "EtherealPad"
elsif preset = 5
    # Metallic Shimmer
    onset_threshold = 1.2
    min_intensity = 35.0
    min_interval = 0.1
    num_partials = 18
    partial_spread = 1.0
    decayTime = 1.2
    brightness = 1.0
    attackBase = 0.003
    waveshapeAmt = 0.4
    presetName$ = "MetallicShimmer"
elsif preset = 6
    # Natural Pluck
    onset_threshold = 1.5
    min_intensity = 35.0
    min_interval = 0.12
    num_partials = 6
    partial_spread = 0.4
    decayTime = 0.8
    brightness = 0.7
    attackBase = 0.001
    waveshapeAmt = 0.15
    presetName$ = "NaturalPluck"
elsif preset = 7
    # Dense Cluster
    onset_threshold = 1.0
    min_intensity = 32.0
    min_interval = 0.05
    num_partials = 25
    partial_spread = 1.2
    decayTime = 1.8
    brightness = 0.8
    attackBase = 0.008
    waveshapeAmt = 0.25
    presetName$ = "DenseCluster"
else
    presetName$ = "Custom"
endif

# Always the original sample rate (Speed_mode removed in v2.7).
targetSR = 0

timerReset = stopwatch

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
name$ = selected$("Sound")
totalDur = Get total duration
origSR = Get sampling frequency
origStart = Get start time
nOrigSamples = Get number of samples
numChan = Get number of channels

if totalDur < 0.1
    exitScript: "Sound too short (min 0.1s)."
endif

# Keep public parameters inside the documented/safe operating range.
if num_partials < 1
    num_partials = 1
elsif num_partials > 32
    num_partials = 32
endif
if brightness < 0
    brightness = 0
elsif brightness > 1
    brightness = 1
endif
if partial_spread > 5
    partial_spread = 5
endif
# Dry/Wet is the user's value in every preset: 0 % = source, 100 % = synthesis.
if dry_wet < 0
    dry_wet = 0
elsif dry_wet > 100
    dry_wet = 100
endif
dry_wet_mix = dry_wet / 100
if attack_stagger < 0 or attack_stagger > 100
    exitScript: "Attack_stagger must be between 0 and 100 ms."
endif
if random_seed < 0
    exitScript: "Random_seed must be 0 (unseeded) or a positive integer."
endif
if pitch_floor < 25
    exitScript: "Pitch_floor must be at least 25 Hz."
endif
if pitch_ceiling < 0
    exitScript: "Pitch_ceiling must be 0 (automatic) or a frequency in Hz."
endif
staggerSec = attack_stagger / 1000
octave_diagnostics = (pitch_estimation = 2)
contextPitch = (pitch_estimation >= 3)

writeInfoLine: "=== Onset-Based Oscillator Bank v2.7 ==="
appendInfoLine: "Input:    ", name$
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Rate:     ", origSR, " Hz (original)"
appendInfoLine: "Dry/Wet:  ", fixed$(dry_wet, 1), " % wet"
appendInfoLine: ""

workingSound = sound
workingSR = origSR

selectObject: workingSound
sampleRate = Get sampling frequency
nyquistFreq = sampleRate / 2

# Analysis is always mono and 0-based, so detected times do not depend
# on the original Sound object's xmin.
selectObject: workingSound
if numChan > 1
    analysisSound = Convert to mono
else
    analysisSound = Copy: "onset_analysis"
endif
selectObject: analysisSound
Shift times to: "start time", 0

pitchCeiling = min(4000, sampleRate / 4)
if pitchCeiling < 200
    pitchCeiling = 200
endif
ceilingNote$ = "automatic (v2.3)"
if pitch_ceiling > 0
    pitchCeiling = min(pitch_ceiling, sampleRate / 4)
    ceilingNote$ = "as entered"
    if pitchCeiling < pitch_ceiling
        ceilingNote$ = "limited to sample rate / 4"
    endif
endif
pitchFloor = pitch_floor
if pitchCeiling < 2 * pitchFloor
    if workingSound <> sound
        removeObject: workingSound
    endif
    removeObject: analysisSound
    exitScript: "Pitch_ceiling (" + fixed$(pitchCeiling, 0) + " Hz at this sample rate) must be at least twice Pitch_floor."
endif

# ============================================================
# ONSET DETECTION
# ============================================================
appendInfo: "Stage 1: Detecting onsets... "

selectObject: analysisSound
intensityObj = To Intensity: 50, 0, "yes"

selectObject: intensityObj
numFrames = Get number of frames

# At most one accepted onset per Intensity frame: no fixed event cap.
onset_times# = zero#(numFrames)
onset_velocities# = zero#(numFrames)
numOnsets = 0
lastOnset = -1

for iFrame from 3 to numFrames - 1
    selectObject: intensityObj
    frameTime = Get time from frame number: iFrame
    currInt = Get value in frame: iFrame
    prev2Int = Get value in frame: iFrame - 2
    
    if currInt <> undefined and prev2Int <> undefined
        intDiff = (currInt - prev2Int) / 2
        if intDiff > onset_threshold and currInt > min_intensity
            # The symmetric Intensity window sees sharp attacks early.
            # Refine each candidate by locating the strongest short-RMS rise.
            candidateTime = frameTime
            refinedTime = candidateTime
            bestRise = 0
            refineStart = max(0.005, candidateTime)
            refineEnd = min(totalDur - 0.005, candidateTime + 0.080)
            tref = refineStart
            while tref <= refineEnd
                selectObject: analysisSound
                rmsPre = Get root-mean-square: tref - 0.005, tref
                rmsPost = Get root-mean-square: tref, tref + 0.005
                riseScore = rmsPost - rmsPre
                if riseScore > bestRise
                    bestRise = riseScore
                    refinedTime = tref
                endif
                tref = tref + 0.002
            endwhile

            if refinedTime - lastOnset > min_interval
                numOnsets += 1
                onset_times#[numOnsets] = refinedTime

                # Velocity is a normalized Intensity-rise score.
                velocity = (intDiff - onset_threshold) / 10
                velocity = min(1, max(0.3, velocity))
                onset_velocities#[numOnsets] = velocity

                lastOnset = refinedTime
            endif
        endif
    endif
endfor

removeObject: intensityObj

if numOnsets = 0
    if workingSound <> sound
        removeObject: workingSound
    endif
    exitScript: "No onsets found. Try lowering threshold."
endif

appendInfoLine: numOnsets, " onsets"

# ============================================================
# PITCH EXTRACTION
# ============================================================
appendInfo: "Stage 2: Extracting pitches... "

onset_pitches# = zero#(numOnsets)

for onsetIdx from 1 to numOnsets
    onsetTime = onset_times#[onsetIdx]
    
    selectObject: analysisSound
    segStart = max(0, onsetTime - 0.02)
    segEnd = min(onsetTime + 0.12, totalDur)
    
    if segEnd - segStart > 0.03
        Extract part: segStart, segEnd, "rectangular", 1, "no"
        segment = selected("Sound")
        
        # To Pitch needs three periods of the floor; raise it for a
        # short segment at the end of the sound only.
        floorUse = max(pitchFloor, 3.05 / (segEnd - segStart))
        To Pitch (ac): 0, floorUse, 15, "no", 0.01, 0.5, 0.01, 0.2, 0.1, pitchCeiling
        pitchObj = selected("Pitch")
        
        relTime = onsetTime - segStart
        detectedPitch = Get value at time: relTime, "Hertz", "Linear"
        
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get mean: 0, 0, "Hertz"
        endif
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get quantile: 0, 0, 0.5, "Hertz"
        endif
        
        removeObject: segment, pitchObj
        
        # Store valid pitch
        if detectedPitch <> undefined and detectedPitch >= pitchFloor and detectedPitch <= pitchCeiling
            onset_pitches#[onsetIdx] = detectedPitch
        else
            onset_pitches#[onsetIdx] = 0
        endif
    else
        onset_pitches#[onsetIdx] = 0
    endif
endfor

appendInfoLine: "done"

# ============================================================
# CONTEXT-AWARE EVENT PITCH (Pitch_estimation 3 and 4)
# The onset times are not changed; only the frequency of each burst.
# ============================================================
legacy_pitches# = onset_pitches#
ctxVoiced# = zero#(numOnsets)
ctxFrames# = zero#(numOnsets)
ctxSpread# = zero#(numOnsets)
ctxFrom# = zero#(numOnsets)
nUnpitched = 0
nChanged = 0
trackPitch = 0
if contextPitch
    appendInfo: "Stage 2b: Context-aware event pitch... "
    selectObject: analysisSound
    floorTrack = max(pitchFloor, 3.05 / totalDur)
    trackPitch = To Pitch (ac): 0, floorTrack, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling
    nTrack = Get number of frames
    for onsetIdx from 1 to numOnsets
        t0 = onset_times#[onsetIdx]
        tEnd = t0 + 0.2
        if onsetIdx < numOnsets
            tEnd = min(tEnd, onset_times#[onsetIdx + 1])
        endif
        # at least ~3 frames, even when the next onset follows closely
        tEnd = min(max(tEnd, t0 + 0.06), totalDur)
        selectObject: trackPitch
        fA = Get frame number from time: t0 + 0.015
        fA = max(1, ceiling(fA))
        fB = Get frame number from time: tEnd
        fB = min(nTrack, floor(fB))
        nFr = 0
        nV = 0
        for fr from fA to fB
            nFr += 1
            fv = Get value in frame: fr, "Hertz"
            if fv <> undefined
                nV += 1
                lfv[nV] = log2(fv)
            endif
        endfor
        ctxFrames#[onsetIdx] = nFr
        ctxVoiced#[onsetIdx] = nV
        newPitch = 0
        if nV >= 3
            # largest group of frames within +/-3 semitones, then its median
            best = 1
            bestN = 0
            for i from 1 to nV
                cnt = 0
                for j from 1 to nV
                    if abs(lfv[i] - lfv[j]) <= 0.25
                        cnt += 1
                    endif
                endfor
                if cnt > bestN
                    bestN = cnt
                    best = i
                endif
            endfor
            grp# = zero#(bestN)
            k = 0
            for j from 1 to nV
                if abs(lfv[j] - lfv[best]) <= 0.25
                    k += 1
                    grp#[k] = lfv[j]
                endif
            endfor
            srt# = sort#(grp#)
            if bestN mod 2 = 1
                med = srt#[(bestN + 1) / 2]
            else
                med = (srt#[bestN / 2] + srt#[bestN / 2 + 1]) / 2
            endif
            # a stable periodicity needs at least 3 agreeing frames (~45 ms)
            if bestN >= 3
                newPitch = 2 ^ med
                ctxSpread#[onsetIdx] = 1200 * (srt#[bestN] - srt#[1])
            endif
        endif
        onset_pitches#[onsetIdx] = newPitch
        if newPitch = 0
            nUnpitched += 1
        endif
    endfor
    # Pitch_estimation 4: an unpitched event takes the pitch of the
    # nearest pitched event (earlier one on a tie)
    if pitch_estimation = 4
        tmp# = onset_pitches#
        for onsetIdx from 1 to numOnsets
            if tmp#[onsetIdx] = 0
                bestD = 1e9
                for j from 1 to numOnsets
                    if tmp#[j] > 0
                        d = abs(onset_times#[j] - onset_times#[onsetIdx])
                        if d < bestD
                            bestD = d
                            ctxFrom#[onsetIdx] = j
                        endif
                    endif
                endfor
                if ctxFrom#[onsetIdx] > 0
                    onset_pitches#[onsetIdx] = tmp#[ctxFrom#[onsetIdx]]
                endif
            endif
        endfor
    endif
    for onsetIdx from 1 to numOnsets
        if onset_pitches#[onsetIdx] > 0 and legacy_pitches#[onsetIdx] > 0
            if abs(1200 * log2(onset_pitches#[onsetIdx] / legacy_pitches#[onsetIdx])) > 50
                nChanged += 1
            endif
        elsif onset_pitches#[onsetIdx] <> legacy_pitches#[onsetIdx]
            nChanged += 1
        endif
    endfor
    appendInfoLine: "done (", numOnsets - nUnpitched, " pitched, ", nUnpitched, " unpitched)"
endif

# ============================================================
# OCTAVE DIAGNOSTICS (report only: nothing below changes the sound)
# ============================================================
diagKind# = zero#(numOnsets)
diagAlt# = zero#(numOnsets)
diagNote$# = empty$#(numOnsets)
nSuspect = 0
nNotSingle = 0
if octave_diagnostics
    appendInfo: "Stage 2b: Octave diagnostics (report only)... "
    for onsetIdx from 1 to numOnsets
        if onset_pitches#[onsetIdx] > 0
            tPrevD = -1
            tNextD = totalDur
            if onsetIdx > 1
                tPrevD = onset_times#[onsetIdx - 1]
            endif
            if onsetIdx < numOnsets
                tNextD = onset_times#[onsetIdx + 1]
            endif
            @octaveCheck: onset_times#[onsetIdx], tNextD, tPrevD, onset_pitches#[onsetIdx]
            diagKind#[onsetIdx] = octaveCheck.kind
            diagAlt#[onsetIdx] = octaveCheck.alt
            diagNote$#[onsetIdx] = octaveCheck.note$
            if octaveCheck.kind = 1 or octaveCheck.kind = 2
                nSuspect += 1
            elsif octaveCheck.kind = 4
                nNotSingle += 1
            endif
        endif
    endfor
    appendInfoLine: "done"
endif

# ============================================================
# SYNTHESIZE OSCILLATOR BANK (OPTIMIZED)
# ============================================================
appendInfo: "Stage 3: Synthesizing bursts... "

# Random seed: 0 = v2.3 behaviour (the generator is not touched).
seedUsed = random_seed
if seedUsed > 0
    random_initializeWithSeedUnsafelyButPredictably (seedUsed)
endif

# Add tail space for burst decay (and for the latest partial entrance).
totalDurWithTail = totalDur + tail_duration + staggerSec

wetSignal = Create Sound from formula: "wet", numChan, 0, totalDurWithTail, sampleRate, "0"

maxBurstDur = attackBase + attackRandom + (decayTime + decayRandom) * 4
maxBurstDur = min(maxBurstDur, 5)

# ---- Phase 1: every v2.3 random draw, in the v2.3 order ----
pMax = 32
pf# = zero#(numOnsets * pMax)
pAtt# = zero#(numOnsets * pMax)
pDec# = zero#(numOnsets * pMax)
pAmp# = zero#(numOnsets * pMax)
pOk# = zero#(numOnsets * pMax)
pDel# = zero#(numOnsets * pMax)
evParts# = zero#(numOnsets)
evRender# = zero#(numOnsets)
for onsetIdx from 1 to numOnsets
    detectedPitch = onset_pitches#[onsetIdx]
    if detectedPitch > 0
        onsetTime = onset_times#[onsetIdx]
        velocity = onset_velocities#[onsetIdx]
        if velocity_sensitive
            ampScale = velocity
        else
            ampScale = 1.0
        endif
        # v2.3 draw condition (burst length without stagger)
        burstEnd = min(onsetTime + maxBurstDur, totalDurWithTail - staggerSec)
        burstDur = burstEnd - onsetTime
        if burstDur > 0.01
            evRender#[onsetIdx] = 1
            maxPartial = min(num_partials, floor(nyquistFreq * 0.9 / detectedPitch))
            evParts#[onsetIdx] = maxPartial
            for partialNum from 1 to maxPartial
                kk = (onsetIdx - 1) * pMax + partialNum
                partialFreq = detectedPitch * partialNum * (1 + randomUniform(-0.01, 0.01) * partial_spread)
                pf#[kk] = partialFreq
                if partialFreq < nyquistFreq * 0.95
                    attackTime = attackBase + randomUniform(0, attackRandom)
                    decayVal = decayTime + randomUniform(-decayRandom, decayRandom)
                    decayVal = max(decayVal, 0.05)
                    ampVal = (0.1 / sqrt(partialNum)) * (brightness ^ (partialNum - 1)) * ampScale
                    ampVal = ampVal * (1 + randomUniform(-ampRandom, ampRandom))
                    pAtt#[kk] = attackTime
                    pDec#[kk] = decayVal
                    pAmp#[kk] = ampVal
                    pOk#[kk] = 1
                endif
            endfor
        endif
    endif
endfor

# ---- Phase 2: partial entrance delays, on their own random stream ----
if staggerSec > 0
    if seedUsed > 0
        random_initializeWithSeedUnsafelyButPredictably (seedUsed + 104729)
    endif
    for onsetIdx from 1 to numOnsets
        if evRender#[onsetIdx] = 1
            nP = evParts#[onsetIdx]
            # rank of each partial by its actual (detuned) frequency
            nOk = 0
            for k from 1 to nP
                if pOk#[(onsetIdx - 1) * pMax + k] = 1
                    nOk += 1
                endif
            endfor
            for k from 1 to nP
                kk = (onsetIdx - 1) * pMax + k
                if pOk#[kk] = 1
                    if attack_stagger_mode = 1
                        pDel#[kk] = staggerSec * randomUniform(0, 1)
                    elsif attack_stagger_mode = 2
                        pDel#[kk] = staggerSec * (randomUniform(0, 1) + randomUniform(0, 1) + randomUniform(0, 1)) / 3
                    else
                        rk = 0
                        for k2 from 1 to nP
                            kk2 = (onsetIdx - 1) * pMax + k2
                            if pOk#[kk2] = 1 and pf#[kk2] < pf#[kk]
                                rk += 1
                            endif
                        endfor
                        if nOk > 1
                            if attack_stagger_mode = 3
                                pDel#[kk] = staggerSec * rk / (nOk - 1)
                            else
                                pDel#[kk] = staggerSec * (nOk - 1 - rk) / (nOk - 1)
                            endif
                        endif
                    endif
                endif
            endfor
        endif
    endfor
endif

# ---- Phase 3: render, one combined formula per burst ----
validOnsets = 0
repEvent = 0
repParts = 0
for onsetIdx from 1 to numOnsets
    if evRender#[onsetIdx] = 1
        validOnsets += 1
        onsetTime = onset_times#[onsetIdx]
        nP = evParts#[onsetIdx]
        maxDel = 0
        for k from 1 to nP
            maxDel = max(maxDel, pDel#[(onsetIdx - 1) * pMax + k])
        endfor
        burstEnd = min(onsetTime + maxBurstDur + maxDel, totalDurWithTail)
        burstDur = burstEnd - onsetTime
        if nP > repParts
            repParts = nP
            repEvent = onsetIdx
        endif

        formula$ = "0"
        for partialNum from 1 to nP
            kk = (onsetIdx - 1) * pMax + partialNum
            if pOk#[kk] = 1
                partialFreq = pf#[kk]
                attackTime = pAtt#[kk]
                decayVal = pDec#[kk]
                ampVal = pAmp#[kk]

                wsBlend = waveshapeAmt * brightness
                ampClean = ampVal * (1 - wsBlend)
                ampWS = ampVal * wsBlend

                attStr$ = fixed$(attackTime, 6)
                decStr$ = fixed$(decayVal, 6)
                freqStr$ = fixed$(partialFreq, 3)

                if pDel#[kk] = 0
                    # v2.3 formula, unchanged
                    tl$ = "x"
                    env$ = "(if x<" + attStr$ + " then x/" + attStr$ + " else exp(-(x-" + attStr$ + ")/" + decStr$ + ") fi)"
                else
                    # local time of a delayed partial: silent before its
                    # entrance, then the same attack and decay; the phase
                    # also starts at its entrance (sin(0) = 0)
                    tl$ = "(x-" + fixed$(pDel#[kk], 6) + ")"
                    env$ = "(if " + tl$ + "<0 then 0 else if " + tl$ + "<" + attStr$ + " then " + tl$ + "/" + attStr$
                        ... + " else exp(-(" + tl$ + "-" + attStr$ + ")/" + decStr$ + ") fi fi)"
                endif

                # sin^3(theta) = 3/4 sin(theta) - 1/4 sin(3 theta).
                fundAmp = ampClean + 0.75 * ampWS
                if fundAmp > 0.001
                    ampStr$ = fixed$(fundAmp, 6)
                    formula$ = formula$ + "+" + ampStr$ + "*sin(2*pi*" + freqStr$ + "*" + tl$ + ")*" + env$
                endif

                thirdAmp = -0.25 * ampWS
                thirdFreq = 3 * partialFreq
                if abs(thirdAmp) > 0.001 and thirdFreq < nyquistFreq * 0.95
                    thirdAmpStr$ = fixed$(thirdAmp, 6)
                    thirdFreqStr$ = fixed$(thirdFreq, 3)
                    formula$ = formula$ + "+" + thirdAmpStr$ + "*sin(2*pi*" + thirdFreqStr$ + "*" + tl$ + ")*" + env$
                endif
            endif
        endfor

        burstSound = Create Sound from formula: "burst", 1, 0, burstDur, sampleRate, formula$

        onsetStr$ = fixed$(onsetTime, 8)
        selectObject: wetSignal
        Formula (part): onsetTime, burstEnd, 1, numChan, "self + Sound_burst(x - " + onsetStr$ + ")"

        removeObject: burstSound
    endif

    if onsetIdx mod 10 = 0
        appendInfo: "."
    endif
endfor

if seedUsed > 0
    # Leave Praat's random generator unpredictable for other scripts.
    random_initializeSafelyAndUnpredictably ()
endif

appendInfoLine: " ", validOnsets, " bursts"
if validOnsets = 0
    appendInfoLine: "  NOTE: onsets were detected, but none had a valid pitch; wet output is silent."
endif

# ============================================================
# MIX AND FINALIZE
# ============================================================
appendInfo: "Stage 4: Mixing... "

# Apply fadeout to wet signal. Clamp it so a large user value cannot
# start the fade before time zero.
fadeDurEffective = min(fadeout_duration, totalDurWithTail)
if fadeDurEffective > 0
    selectObject: wetSignal
    fadeStart = totalDurWithTail - fadeDurEffective
    Formula (part): fadeStart, totalDurWithTail, 1, numChan,
    ... "self * (1 - (x - " + fixed$(fadeStart, 6) + ") / " + fixed$(fadeDurEffective, 6) + ")"
endif

finalSR = sampleRate

# Get wet signal name
selectObject: wetSignal
wetName$ = selected$("Sound")

# Get original sound name for formula
selectObject: sound
origName$ = selected$("Sound")

# Create extended output (original + tail) at time 0. Copy the dry
# path by sample index so a non-zero original xmin cannot break lookup.
soundIdStr$ = string$(sound)
output = Create Sound from formula: name$ + "_resonated_" + presetName$,
    ... numChan, 0, totalDurWithTail, finalSR,
    ... "if col <= 'nOrigSamples:0' then object[" + soundIdStr$ + ", row, col] else 0 fi"

# Apply mix. The synthesized wet bank is identical in each channel;
# the dry path retains each original channel independently.
selectObject: wetSignal
nWetSamples = Get number of samples
wetIdStr$ = string$(wetSignal)

selectObject: output
if dry_wet_mix = 1
    Formula: "if col <= 'nWetSamples:0' then object[" + wetIdStr$ + ", row, col] else 0 fi"
elsif dry_wet_mix = 0
    # Exact dry path (plus tail silence): do not normalize.
else
    wetStr$ = fixed$(dry_wet_mix, 6)
    dryStr$ = fixed$(1 - dry_wet_mix, 6)
    Formula: "self * " + dryStr$ + " + (if col <= 'nWetSamples:0' then object[" + wetIdStr$ + ", row, col] else 0 fi) * " + wetStr$
endif

# Safety attenuation only: never boost a quiet result.
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
safetyScaled = 0
if dry_wet_mix > 0 and peakBeforeSafety > 0.99
    Scale peak: 0.99
    safetyScaled = 1
endif

# stopwatch returns elapsed time since its previous invocation.
processingTime = stopwatch

# Get output stats for visualization / summary
selectObject: output
outDur = Get total duration
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "done"
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Valid onsets:    ", validOnsets, " / ", numOnsets
appendInfoLine: "Tail duration:   ", fixed$(tail_duration, 2), " seconds"
appendInfoLine: "Output RMS:      ", fixed$(rms_out, 6)
appendInfoLine: "Pitch range:     ", fixed$(pitchFloor, 0), "-", fixed$(pitchCeiling, 0), " Hz (ceiling ", ceilingNote$, ")"
if staggerSec > 0
    stName$ = "random uniform"
    if attack_stagger_mode = 2
        stName$ = "random Gaussian-like"
    elsif attack_stagger_mode = 3
        stName$ = "ascending spectral"
    elsif attack_stagger_mode = 4
        stName$ = "descending spectral"
    endif
    appendInfoLine: "Attack stagger:  ", fixed$(attack_stagger, 1), " ms, ", stName$
else
    stName$ = ""
    appendInfoLine: "Attack stagger:  off (v2.3 synthesis)"
endif
if seedUsed > 0
    appendInfoLine: "Random seed:     ", seedUsed, " (stagger stream ", seedUsed + 104729, ")"
else
    appendInfoLine: "Random seed:     unseeded (as v2.3)"
endif
if contextPitch
    appendInfoLine: "Pitch estimation: context-aware (" + (if pitch_estimation = 3 then "unpitched events skipped" else "unpitched events use nearest pitch" fi) + ")"
    appendInfoLine: ""
    appendInfoLine: "Event pitch (onset time unchanged; frames from onset + 15 ms to the next onset, max 200 ms):"
    appendInfoLine: "     #   time s   v2.3 Hz   used Hz   voiced/frames  spread c   note"
    for i from 1 to numOnsets
        @padL: string$(i), 6
        c1$ = padL$
        @padL: fixed$(onset_times#[i], 3), 9
        c2$ = padL$
        @padL: if legacy_pitches#[i] > 0 then fixed$(legacy_pitches#[i], 1) else "-" fi, 10
        c3$ = padL$
        @padL: if onset_pitches#[i] > 0 then fixed$(onset_pitches#[i], 1) else "-" fi, 10
        c4$ = padL$
        @padL: string$(ctxVoiced#[i]) + "/" + string$(ctxFrames#[i]), 15
        c5$ = padL$
        @padL: if ctxVoiced#[i] >= 2 and ctxSpread#[i] > 0 then fixed$(ctxSpread#[i], 0) else "" fi, 11
        c6$ = padL$
        nt$ = ""
        if ctxFrom#[i] > 0
            nt$ = "unpitched; uses event " + string$(ctxFrom#[i])
        elsif onset_pitches#[i] = 0
            nt$ = "unpitched; skipped"
        elsif legacy_pitches#[i] > 0
            if abs(1200 * log2(onset_pitches#[i] / legacy_pitches#[i])) > 50
                nt$ = "differs from v2.3 by " + fixed$(1200 * log2(onset_pitches#[i] / legacy_pitches#[i]), 0) + " c"
            endif
        endif
        appendInfoLine: c1$, c2$, c3$, c4$, c5$, c6$, "   ", nt$
    endfor
    appendInfoLine: "  ", nChanged, " event(s) differ from v2.3 by more than 50 cents or in pitched/unpitched status."
endif
if octave_diagnostics
    appendInfoLine: ""
    appendInfoLine: "Octave diagnostics (report only - the detected pitch is always used):"
    appendInfoLine: "     #   time s   pitch Hz   check"
    for i from 1 to numOnsets
        if onset_pitches#[i] > 0
            @padL: string$(i), 6
            c1$ = padL$
            @padL: fixed$(onset_times#[i], 3), 9
            c2$ = padL$
            @padL: fixed$(onset_pitches#[i], 1), 11
            appendInfoLine: c1$, c2$, padL$, "   ", diagNote$#[i]
        endif
    endfor
    appendInfoLine: "  ", nSuspect, " octave suspicion(s), ", nNotSingle, " event(s) not a single harmonic series."
    appendInfoLine: "  Evidence is spectral and heuristic; it can be wrong, especially for chords,"
    appendInfoLine: "  bells and noisy attacks, where one f0 may not describe the event at all."
endif

###############################################################################
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: Original waveform + onset markers  (left, headline)
# Panel B: Processed output waveform          (right, headline)
# Panel C: Detected pitches per onset
# Panel D: Onset velocities
# Panel E: light-grey summary stats bar
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Find pitch range across all valid onsets (used in Panel C)
    minPitch = 5000
    maxPitch = 0
    numValidPitches = 0
    for i to numOnsets
        if onset_pitches#[i] > 0
            numValidPitches += 1
            if onset_pitches#[i] < minPitch
                minPitch = onset_pitches#[i]
            endif
            if onset_pitches#[i] > maxPitch
                maxPitch = onset_pitches#[i]
            endif
        endif
    endfor

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    suiteVizName$ = replace$(origName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Onset-Based Oscillator Bank v2.7##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    selectObject: analysisSound
    Colour: "{0.65, 0.65, 0.65}"
    Draw: 0, totalDur, 0, 0, "no", "Curve"

    # Mark onsets: red = valid pitch, grey = no pitch
    maxAmp = Get maximum: 0, 0, "None"
    minAmp = Get minimum: 0, 0, "None"
    Line width: 1
    for i to numOnsets
        if onset_pitches#[i] > 0
            Colour: "{0.85, 0.30, 0.30}"
        else
            Colour: "{0.55, 0.55, 0.60}"
        endif
        Draw line: onset_times#[i], minAmp, onset_times#[i], maxAmp
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL B: PROCESSED OUTPUT WAVEFORM  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    selectObject: output
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES  (above A and B)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Original  +  onsets  (red = valid pitch,  grey = no pitch)"
    Text: 6.10, "centre", 7.30, "half",
        ... "Output  (" + fixed$(outDur, 2) + " s)"

    # ----------------------------------------------------------
    # PANEL C: DETECTED PITCHES  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.86, 5.48

    if numValidPitches > 0 and maxPitch > minPitch
        yLo = minPitch * 0.9
        yHi = maxPitch * 1.1
    else
        yLo = 0
        yHi = 1000
    endif

    Axes: 0, totalDur, yLo, yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, yLo, yHi

    # context-aware: the continuous track (grey) and, where it differs by
    # more than 50 cents, the v2.3 estimate (small grey cross)
    if contextPitch
        selectObject: trackPitch
        for fr from 1 to nTrack
            fv = Get value in frame: fr, "Hertz"
            if fv <> undefined
                if fv >= yLo and fv <= yHi
                    tf = Get time from frame number: fr
                    Paint circle (mm): "{0.72, 0.72, 0.75}", tf, fv, 0.25
                endif
            endif
        endfor
        Colour: "{0.55, 0.55, 0.60}"
        Line width: 1
        for i to numOnsets
            if legacy_pitches#[i] >= yLo and legacy_pitches#[i] <= yHi
                if onset_pitches#[i] = 0 or abs(1200 * log2(max(onset_pitches#[i], 1) / legacy_pitches#[i])) > 50
                    dx = totalDur * 0.004
                    dy = (yHi - yLo) * 0.04
                    Draw line: onset_times#[i] - dx, legacy_pitches#[i] - dy, onset_times#[i] + dx, legacy_pitches#[i] + dy
                    Draw line: onset_times#[i] - dx, legacy_pitches#[i] + dy, onset_times#[i] + dx, legacy_pitches#[i] - dy
                endif
            endif
        endfor
    endif

    Colour: "{0.30, 0.60, 0.30}"
    Line width: 1
    for i to numOnsets
        if onset_pitches#[i] > 0
            Draw circle: onset_times#[i], onset_pitches#[i], 0.02
        endif
    endfor
    # report-only octave suspicions: label next to the (unchanged) pitch
    if octave_diagnostics
        Font size: 6
        for i to numOnsets
            if onset_pitches#[i] > 0 and diagKind#[i] > 0
                if diagKind#[i] = 1 or diagKind#[i] = 2
                    Colour: "{0.85, 0.45, 0.10}"
                    rt = diagAlt#[i] / onset_pitches#[i]
                    if rt > 1
                        lab$ = "x" + fixed$(rt, 0) + "?"
                    else
                        lab$ = "/" + fixed$(1 / rt, 0) + "?"
                    endif
                elsif diagKind#[i] = 3
                    Colour: "{0.60, 0.60, 0.65}"
                    lab$ = "(/" + fixed$(onset_pitches#[i] / diagAlt#[i], 0) + "?)"
                elsif diagKind#[i] = 4
                    Colour: "{0.55, 0.30, 0.55}"
                    lab$ = "mix?"
                else
                    # inconclusive: no label
                    lab$ = ""
                endif
                if lab$ <> ""
                    Text: onset_times#[i], "centre", onset_pitches#[i] + (yHi - yLo) * 0.07, "bottom", lab$
                endif
            endif
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no",
        ... "Detected pitches per onset  ("
        ... + string$(numValidPitches) + " of " + string$(numOnsets) + " onsets,  "
        ... + fixed$(minPitch, 1) + "-" + fixed$(maxPitch, 1) + " Hz)"
        ... + (if octave_diagnostics then "  -  report only: x2? /2? octave suspicion, mix? not one series" else "" fi)
        ... + (if contextPitch then "  -  grey: continuous track, x: v2.3 estimate where it differs" else "" fi)
    Text left: "yes", "Hz"

    # ----------------------------------------------------------
    # PANEL D: ONSET VELOCITIES  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, totalDur, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, 0, 1.1

    # Reference dashed line at velocity = 1.0
    Colour: "{0.78, 0.78, 0.82}"
    Line width: 1
    Dotted line
    Draw line: 0, 1, totalDur, 1
    Solid line

    # Draw velocity stems: valid pitch = orange, no pitch = grey
    Line width: 2
    for i to numOnsets
        if onset_pitches#[i] > 0
            Colour: "{0.78, 0.42, 0.22}"
        else
            Colour: "{0.55, 0.55, 0.60}"
        endif
        Draw line: onset_times#[i], 0, onset_times#[i], onset_velocities#[i]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Onset velocities  (orange = valid pitch,  grey = no pitch)"
    Text left: "yes", "Level"

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
        ... + "  Onsets: " + string$(validOnsets) + " valid / " + string$(numOnsets) + " detected"
        ... + "  |  Partials: " + string$(num_partials)
        ... + "  |  Spread: " + fixed$(partial_spread, 2) + "%"
        ... + "  |  Decay: " + fixed$(decayTime, 2) + " s"

    Text: 0.02, "left", 0.50, "half",
        ... "Threshold: " + fixed$(onset_threshold, 2) + " dB"
        ... + "  |  Min interval: " + fixed$(min_interval, 3) + " s"
        ... + "  |  Brightness: " + fixed$(brightness, 2)
        ... + "  |  Dry/Wet: " + fixed$(dry_wet, 0) + " % wet"
        ... + "  |  Tail: " + fixed$(tail_duration, 1) + " s"
        ... + "  |  Pitch: " + fixed$(pitchFloor, 0) + "-" + fixed$(pitchCeiling, 0) + " Hz"
        ... + "  |  Stagger: " + (if staggerSec > 0 then fixed$(attack_stagger, 0) + " ms " + stName$ else "off" fi)

    Text: 0.02, "left", 0.18, "half",
        ... "Rate: " + string$(origSR) + " Hz"
        ... + "  |  Time: " + fixed$(processingTime, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)
        ... + "  |  Safety scale: " + string$(safetyScaled)
        ... + "  |  Seed: " + (if seedUsed > 0 then string$(seedUsed) else "unseeded" fi)
        ... + "  |  Estimation: " + (if contextPitch then "context-aware, " + string$(nUnpitched) + " unpitched" else "v2.3" fi)
        ... + (if octave_diagnostics then "  |  Suspicions: " + string$(nSuspect) + ", mixtures: " + string$(nNotSingle) else "" fi)
        ... + "  |  Output: " + replace$(name$ + "_resonated_" + presetName$, "_", "\_ ", 0)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: wetSignal, analysisSound
if trackPitch > 0
    removeObject: trackPitch
endif

if workingSound <> sound
    removeObject: workingSound
endif

# Restore the input Sound's absolute time domain only after visualization,
# which uses a normalized 0..duration axis.
selectObject: output
if origStart <> 0
    Shift times by: origStart
endif

if play_result
    Play
endif

selectObject: output

# ============================================================
# OCTAVE CHECK (diagnostic only)
# Spectrum of the event (onset + 5 ms to the next onset, at most 150 ms),
# gated by the spectrum just before the onset, tested against the
# detected pitch F:
#   kind 0  consistent: F's harmonic series explains the new peaks
#   kind 1  suspect too low: every harmonic present (at least two) is a
#           multiple of g >= 2
#   kind 2  suspect too high: clear components at (h - j/m) F, m = 2 or 3,
#           only if F itself sounds, F/m >= Pitch_floor, and the F/m
#           series explains the new peaks
#   kind 3  weak evidence for F/2 or F/3 (reported, not counted)
#   kind 4  not a single harmonic series (>= 25 % of strong new peaks
#           are not harmonics of F): chord, bell or noise
#   kind 5  inconclusive: no partial of F rose, one partial only, or the
#           region is too short
# ============================================================
procedure octaveCheck: .t, .tNext, .tPrev, .f
    octaveCheck.kind = 5
    octaveCheck.alt = 0
    octaveCheck.note$ = "not checked (region too short)"
    .r1 = .t + 0.005
    .r2 = min(.t + 0.15, .tNext, totalDur)
    .len = .r2 - .r1
    if .len >= max(0.03, 2 / .f)
        selectObject: analysisSound
        .win = Extract part: .r1, .r2, "Hanning", 1, "no"
        .spc = To Spectrum: "yes"
        .lt = To Ltas (1-to-1)
        preLt = 0
        preCorr = 0
        .p2 = .t - 0.003
        .p1 = max(.tPrev + 0.01, .t - 0.15, 0)
        if .p2 - .p1 >= 0.03
            selectObject: analysisSound
            .pw = Extract part: .p1, .p2, "Hanning", 1, "no"
            .ps = To Spectrum: "yes"
            preLt = To Ltas (1-to-1)
            removeObject: .pw, .ps
            preCorr = 10 * log10(.len / (.p2 - .p1))
        endif
        .fmaxA = min(nyquistFreq * 0.9, max(5000, 4.5 * .f))
        selectObject: .lt
        .lmax = Get maximum: pitchFloor * 0.5, .fmaxA, "None"
        .df = 2 / .len
        @harmonics: .lt, .f, .lmax, .fmaxA, .df
        .nPres = harmonics.nPres
        .gcd = harmonics.gcd
        .fund = harmonics.fund
        @unexplained: .lt, .f, .lmax, .fmaxA, .df
        .unexp = unexplained.frac
        .downAlt = 0
        .weakAlt = 0
        .m = 2
        while .m <= 3 and .downAlt = 0
            if .f / .m >= pitchFloor
                @subHarmonics: .lt, .f, .m, .lmax, .fmaxA, .df
                if subHarmonics.n >= 2 or (subHarmonics.n >= 1 and subHarmonics.strong = 1)
                    .downAlt = .f / .m
                elsif subHarmonics.n + subHarmonics.nWeak >= 1 and .weakAlt = 0
                    .weakAlt = .f / .m
                endif
            endif
            .m += 1
        endwhile
        if .nPres = 0
            octaveCheck.kind = 5
            octaveCheck.note$ = "inconclusive: no harmonic of " + fixed$(.f, 1) + " Hz rose at this onset"
        elsif .gcd >= 2 and .nPres = 1
            octaveCheck.kind = 5
            octaveCheck.note$ = "inconclusive (only harmonic " + string$(.gcd) + " of " + fixed$(.f, 1) + " Hz found)"
        elsif .gcd >= 2
            octaveCheck.kind = 1
            octaveCheck.alt = .f * .gcd
            octaveCheck.note$ = "suspect x" + string$(.gcd) + " = " + fixed$(octaveCheck.alt, 1) + " Hz (all " + string$(.nPres) + " partials found are multiples of " + string$(.gcd) + ")"
        else
            # A lower f0 is only suggested when F itself sounds (otherwise
            # going lower just adds another missing fundamental) and when
            # the lower series explains the new peaks.
            .downOk = 0
            if .fund = 1 and .downAlt > 0
                @unexplained: .lt, .downAlt, .lmax, .fmaxA, .df
                if unexplained.frac < 0.25
                    .downOk = 1
                endif
            endif
            if .downOk = 1
                octaveCheck.kind = 2
                octaveCheck.alt = .downAlt
                octaveCheck.note$ = "suspect /" + fixed$(.f / .downAlt, 0) + " = " + fixed$(.downAlt, 1) + " Hz (components between the harmonics)"
            elsif .unexp >= 0.25
                octaveCheck.kind = 4
                octaveCheck.note$ = "not a single harmonic series (" + fixed$(100 * .unexp, 0) + " % of strong new peaks off the series): chord, bell or noise"
            elsif .fund = 0
                octaveCheck.kind = 0
                octaveCheck.note$ = "no energy at " + fixed$(.f, 1) + " Hz: missing fundamental or a chord (" + string$(.nPres) + " harmonics)"
            elsif .weakAlt > 0
                octaveCheck.kind = 3
                octaveCheck.alt = .weakAlt
                octaveCheck.note$ = "consistent; weak components also fit " + fixed$(.weakAlt, 1) + " Hz"
            else
                octaveCheck.kind = 0
                octaveCheck.note$ = "consistent (" + string$(.nPres) + " partial(s) incl. fundamental)"
            endif
        endif
        removeObject: .win, .spc, .lt
        if preLt > 0
            removeObject: preLt
            preLt = 0
        endif
    endif
endproc

# Spectral peak level within +/-tol of f; prominence against the lower
# side valleys at f - w and f + w.
procedure peakAt: .lt, .fq, .tol, .w
    selectObject: .lt
    peakAt.p = Get maximum: .fq - .tol, .fq + .tol, "None"
    .vl = Get minimum: .fq - .w, .fq - .w / 3, "None"
    .vr = Get minimum: .fq + .w / 3, .fq + .w, "None"
    if peakAt.p = undefined
        peakAt.p = -300
    endif
    if .vl = undefined
        .vl = peakAt.p
    endif
    if .vr = undefined
        .vr = peakAt.p
    endif
    peakAt.prom = peakAt.p - max(.vl, .vr)
    # not new at this onset -> not evidence
    if preLt > 0
        selectObject: preLt
        .pre = Get maximum: .fq - .tol, .fq + .tol, "None"
        if .pre <> undefined
            if peakAt.p - (.pre + preCorr) < 3
                peakAt.prom = -1
            endif
        endif
    endif
endproc

# Harmonics h*C (h = 1..hmax): presence = within 35 dB of the strongest
# component and at least 6 dB above both neighbouring valleys.
procedure harmonics: .lt, .cf, .lmax, .fmaxA, .df
    harmonics.nPres = 0
    harmonics.nOdd = 0
    harmonics.nEven = 0
    harmonics.fund = 0
    harmonics.hp = 1
    .np2 = 0
    .g = 0
    .hmax = min(16, floor(.fmaxA / .cf))
    for .h from 1 to .hmax
        .tol = max(0.03 * .h * .cf, .df)
        @peakAt: .lt, .h * .cf, .tol, 0.5 * .cf
        if peakAt.p >= .lmax - 35 and peakAt.prom >= 6
            harmonics.nPres += 1
            harmonics.hp = .h
            # running greatest common divisor of the present harmonic numbers
            .a = .g
            .b = .h
            while .b > 0
                .r = .a mod .b
                .a = .b
                .b = .r
            endwhile
            .g = .a
            if .h = 1
                harmonics.fund = 1
            else
                .np2 += 1
            endif
            if .h mod 2 = 1
                harmonics.nOdd += 1
            else
                harmonics.nEven += 1
            endif
        endif
    endfor
    harmonics.gcd = .g
    harmonics.cov2 = 0
    if harmonics.hp >= 2
        harmonics.cov2 = .np2 / (harmonics.hp - 1)
    endif
endproc

# Components between the harmonics of C at the positions where the
# harmonics of C/m (m = 2 or 3) would lie, i.e. (h - j/m) * C. Their presence
# means the true fundamental is C/m. Strong: within 35 dB of the maximum,
# 6 dB above the neighbouring valleys (one alone counts if within 30 dB).
# Weak: within 45 dB - reported as an octave ambiguity, not acted upon.
procedure subHarmonics: .lt, .cf, .m, .lmax, .fmaxA, .df
    subHarmonics.n = 0
    subHarmonics.strong = 0
    subHarmonics.nWeak = 0
    subHarmonics.weakLev = -300
    subHarmonics.midLev = -300
    .hmax = min(16, floor(.fmaxA / .cf))
    for .h from 1 to .hmax
        for .j from 1 to .m - 1
            .fq = (.h - .j / .m) * .cf
            .tol = max(0.03 * .fq, .df)
            @peakAt: .lt, .fq, .tol, 0.8 * .cf / .m
            if peakAt.prom >= 6
                if peakAt.p >= .lmax - 35
                    subHarmonics.n += 1
                    subHarmonics.midLev = max(subHarmonics.midLev, peakAt.p)
                    if peakAt.p >= .lmax - 30
                        subHarmonics.strong = 1
                    endif
                elsif peakAt.p >= .lmax - 45
                    subHarmonics.nWeak += 1
                    subHarmonics.weakLev = max(subHarmonics.weakLev, peakAt.p)
                endif
            endif
        endfor
    endfor
endproc

# Share of strong spectral peaks (within 20 dB of the maximum) that are not
# harmonics of C.
procedure unexplained: .lt, .cf, .lmax, .fmaxA, .df
    selectObject: .lt
    .tier = To SpectrumTier (peaks)
    .tab = Down to Table
    .pc$ = Get column label: 3
    .fc$ = Get column label: 2
    .strongT = Extract rows where column (number): .pc$, "greater than or equal to", .lmax - 20
    .np = Get number of rows
    .nStrong = 0
    .nOff = 0
    for .i from 1 to .np
        selectObject: .strongT
        .fq = Get value: .i, .fc$
        .isNew = 1
        if preLt > 0
            selectObject: preLt
            .tl = max(0.03 * .fq, .df)
            .pre = Get maximum: .fq - .tl, .fq + .tl, "None"
            selectObject: .strongT
            .lvq = Get value: .i, .pc$
            if .pre <> undefined
                if .lvq - (.pre + preCorr) < 3
                    .isNew = 0
                endif
            endif
        endif
        if .fq >= pitch_floor * 0.5 and .fq <= .fmaxA and .isNew = 1
            .nStrong += 1
            .hh = round(.fq / .cf)
            .tol = max(0.03 * .fq, .df)
            if .hh < 1 or abs(.fq - .hh * .cf) > .tol
                .nOff += 1
            endif
        endif
    endfor
    removeObject: .tier, .tab, .strongT
    unexplained.frac = 0
    if .nStrong > 0
        unexplained.frac = .nOff / .nStrong
    endif
endproc

procedure padL: .s$, .w
    padL$ = .s$
    while length(padL$) < .w
        padL$ = " " + padL$
    endwhile
endproc
