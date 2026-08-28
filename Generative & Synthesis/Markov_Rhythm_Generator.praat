# ============================================================
# Praat AudioTools - Markov_Rhythm_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.2 transition-softmax stability fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# MARKOV RHYTHM GENERATOR
#
# CONCEPTUAL MODEL
# ----------------
# A Markov state is a CYCLIC BINARY RHYTHM TEMPLATE (a rhythm necklace).
# The chain changes state once per completed template cycle, not once per beat.
# Tempo therefore has a musically explicit meaning:
#
#       step_duration = beat_duration / steps_per_beat
#       cycle_duration = pattern_length * step_duration
#
# In v0.4 every 4-, 6-, 7- or 8-bit pattern was compressed into ONE beat.
# This made the pattern length silently change the subdivision density and made
# the clave / Euclidean labels metrically misleading.
#
# MARKOV GRAMMAR
# --------------
# All eight states in a preset use the same pattern length. Transition weights
# are computed from normalized Hamming distance between the binary templates:
#
#       d(i,j) = mismatching_steps / pattern_length
#       q(i,j) proportional to exp(-d(i,j)/temperature),  i != j
#       P(i,i) = persistence
#       P(i,j) = (1-persistence)*q(i,j),            i != j
#
# Thus State_persistence is the EXACT theoretical self-transition probability,
# while temperature controls only how the remaining probability is distributed
# among alternative rhythm templates. Lower temperature favors rhythmically
# similar successors; higher temperature explores more distant templates. The
# chain therefore has an explicit rhythm-space topology rather than one
# identical 40/30/30 transition rule for every state.
#
# RHYTHM / TIMING
# ---------------
# Each template onset is rendered on the shared pulse grid. State onset count
# is energy-compensated approximately by sqrt(mean_onsets/onsets_in_state), so
# denser states do not become louder merely because they contain more attacks.
# Metric downbeats receive a small accent.
#
# Swing is implemented as a TIMING transformation, not by calling arbitrary
# six-step strings "swing": with a 2-step beat grid the offbeat moves from
# 1/2 beat toward 2/3 beat by Swing_amount.
#
# TRUE RHYTHMIC CANON
# -------------------
# v0.4 generated an independent Markov chain for each "canon" voice. That is
# not a canon. v0.5 generates ONE base Markov realization and copies its exact
# onset/state sequence to delayed voices. The voices may use fixed register
# transpositions and equal-power spatial positions, so this is a rhythmic canon
# (with optional registral imitation), not several unrelated chains.
#
# PRESET SCOPE
# ------------
# "Clave / Timeline Geometry" is a small analytical family informed by binary
# timeline representations; it is not labelled an "authentic Latin clave"
# synthesis. The Son template used here is 1001001000101000.
#
# "Euclidean E(5,8) Rotations" uses E(5,8) = 10110110 up to cyclic rotation.
# Toussaint identifies E(5,8) with the Cuban cinquillo family. The preset uses
# the rotations as Markov states; it does not claim every rotation has the same
# metrical function in performance practice.
#
# CLAVE-LIKE SOUND
# ----------------
# The sound remains intentionally synthetic: three decaying resonant components
# at f, 2.76f and 4f. "Wood character" controls only the inharmonic 2.76f mode.
# This is a compact woody-click model, not a physical model of actual claves.
# Common frequency scaling protects ALL components and canon transpositions from
# Nyquist violation.
#
# v0.5.2 transition-softmax stability fix
# -----------------------------------------
#   - Hamming-distance transition weights now use a row-wise shifted
#     exponential: exp(-(d-d_min)/temperature). This is algebraically
#     equivalent after normalization, but guarantees that at least the
#     nearest alternative successor has weight 1 and prevents an all-zero
#     row through floating-point underflow at very small positive temperatures.
#   - No rhythm templates, persistence semantics, timing, swing, canon,
#     synthesis, spatialization, level handling or visualization changed.
#
# v0.5.1 canon-delay fix
# ----------------------
#   - Canon delay is specified in BEATS, not seconds.
#   - Physical delay is derived after preset tempo is known:
#         canonDelaySeconds = Canon_delay_beats * 60 / Tempo_bpm
#   - The rhythmic imitation therefore preserves its metric relation when
#     tempo changes.
#
# v0.5 changes
# ------------
#   - Markov states are explicit cyclic rhythm templates on a shared metric grid
#   - state changes occur per template cycle, not per beat
#   - true 8x8 transition matrix from rhythmic Hamming similarity
#   - independent persistence and transition temperature controls
#   - empirical transition matrix / state visits measured from realization
#   - Random_seed for reproducible state sequence
#   - Swing Feel uses actual offbeat timing displacement
#   - Euclidean 5/8 preset corrected to rotations of genuine E(5,8)
#   - Latin Clave renamed to Clave / Timeline Geometry; no authenticity claim
#   - Polyrhythmic renamed to 3:4 Composite Grid (single composite necklace)
#   - canon voices reuse the SAME delayed Markov rhythm realization
#   - exact requested base duration; canon tail extends only by explicit delay
#   - removed O(N^2) pulse sorting (not needed for local additive rendering)
#   - efficient Formula(part) rendering over pulse-local regions only
#   - state-density and total-overlap energy compensation
#   - equal-power stereo for canon voices
#   - common Nyquist headroom including 4th-resonance component
#   - one short edge fade; final peak protection is down-only
#   - visualization now shows actual realized states/onsets plus model matrix
#
# Mathematical / rhythm references:
#   Godfried T. Toussaint, The Geometry of Musical Rhythm (2013/2019).
#   Godfried T. Toussaint, "The Euclidean Algorithm Generates Traditional
#   Musical Rhythms" (Bridges, 2005).
# ============================================================

form Markov Rhythm Generator v0.5.2
    optionmenu Preset 1
        option Custom
        option Simple March
        option Complex Funk
        option Techno Grid
        option Swing Feel
        option Broken Beat
        option Clave / Timeline Geometry
        option 3:4 Composite Grid
        option Euclidean E(5,8) Rotations

    positive Duration_s 12.0
    integer Sample_rate_Hz 44100
    positive Tempo_bpm 120

    positive Base_frequency_Hz 1800
    positive Decay_rate 60
    real Wood_character 0.4

    optionmenu Canon_mode 1
        option No Canon
        option Canon 2 voices
        option Canon 3 voices
    positive Canon_delay_beats 1.0

    boolean Edit_markov_rhythm_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
steps_per_beat = 4
transition_temperature = 0.24
state_persistence = 0.42
swing_amount = 0.0
metric_accent = 0.18
master_amplitude = 0.58
edge_fade_s = 0.015
random_seed = 0

preset_name$ = "Custom"

# ---------------------------------------------------------------------------
# PRESETS + EIGHT RHYTHM STATES
# Every state inside one preset has the SAME pattern length.
# ---------------------------------------------------------------------------
if preset = 2
    tempo_bpm = 100
    base_frequency_Hz = 1500
    decay_rate = 50
    wood_character = 0.30
    steps_per_beat = 2
    transition_temperature = 0.18
    state_persistence = 0.55
    preset_name$ = "Simple March"

    rhythmPattern$[1] = "10001000"
    rhythmPattern$[2] = "10001010"
    rhythmPattern$[3] = "10101000"
    rhythmPattern$[4] = "10011000"
    rhythmPattern$[5] = "10001001"
    rhythmPattern$[6] = "10101010"
    rhythmPattern$[7] = "11001000"
    rhythmPattern$[8] = "10011010"

elsif preset = 3
    tempo_bpm = 110
    base_frequency_Hz = 2000
    decay_rate = 70
    wood_character = 0.50
    steps_per_beat = 4
    transition_temperature = 0.28
    state_persistence = 0.30
    preset_name$ = "Complex Funk"

    rhythmPattern$[1] = "1000101010001010"
    rhythmPattern$[2] = "1001001010010010"
    rhythmPattern$[3] = "1010001010100100"
    rhythmPattern$[4] = "1001100010100100"
    rhythmPattern$[5] = "1010010010011010"
    rhythmPattern$[6] = "1100001010010100"
    rhythmPattern$[7] = "1001011010001001"
    rhythmPattern$[8] = "1011001010010010"

elsif preset = 4
    tempo_bpm = 130
    base_frequency_Hz = 1200
    decay_rate = 80
    wood_character = 0.20
    steps_per_beat = 4
    transition_temperature = 0.22
    state_persistence = 0.45
    preset_name$ = "Techno Grid"

    rhythmPattern$[1] = "1000100010001000"
    rhythmPattern$[2] = "1000101010001000"
    rhythmPattern$[3] = "1000100010101000"
    rhythmPattern$[4] = "1010100010001010"
    rhythmPattern$[5] = "1001100010011000"
    rhythmPattern$[6] = "1010101010001000"
    rhythmPattern$[7] = "1000101010101000"
    rhythmPattern$[8] = "1010101010101010"

elsif preset = 5
    tempo_bpm = 90
    base_frequency_Hz = 1600
    decay_rate = 55
    wood_character = 0.40
    steps_per_beat = 2
    transition_temperature = 0.22
    state_persistence = 0.38
    swing_amount = 0.92
    preset_name$ = "Swing Feel"

    rhythmPattern$[1] = "10101010"
    rhythmPattern$[2] = "10100010"
    rhythmPattern$[3] = "10001010"
    rhythmPattern$[4] = "10101000"
    rhythmPattern$[5] = "10001000"
    rhythmPattern$[6] = "10100000"
    rhythmPattern$[7] = "10000010"
    rhythmPattern$[8] = "11101010"

elsif preset = 6
    tempo_bpm = 140
    base_frequency_Hz = 1900
    decay_rate = 65
    wood_character = 0.50
    steps_per_beat = 4
    transition_temperature = 0.36
    state_persistence = 0.25
    preset_name$ = "Broken Beat"

    rhythmPattern$[1] = "1010001010010100"
    rhythmPattern$[2] = "1001010010100010"
    rhythmPattern$[3] = "1100001010010010"
    rhythmPattern$[4] = "1011010000101000"
    rhythmPattern$[5] = "1001101001000010"
    rhythmPattern$[6] = "1110000100101000"
    rhythmPattern$[7] = "1010110000010010"
    rhythmPattern$[8] = "1100100010010100"

elsif preset = 7
    tempo_bpm = 120
    base_frequency_Hz = 2200
    decay_rate = 75
    wood_character = 0.60
    steps_per_beat = 4
    transition_temperature = 0.18
    state_persistence = 0.40
    preset_name$ = "Clave Timeline Geometry"

    # Six binary timeline patterns documented in Toussaint's comparative work,
    # plus the half-cycle Son rotation and one further Son phase rotation.
    rhythmPattern$[1] = "1001001000101000"
    rhythmPattern$[2] = "1000101000101000"
    rhythmPattern$[3] = "1001000100101000"
    rhythmPattern$[4] = "1001001000100100"
    rhythmPattern$[5] = "1001001000110000"
    rhythmPattern$[6] = "1001001000100010"
    rhythmPattern$[7] = "0010100010010010"
    rhythmPattern$[8] = "0100010010010001"

elsif preset = 8
    tempo_bpm = 100
    base_frequency_Hz = 1700
    decay_rate = 60
    wood_character = 0.40
    steps_per_beat = 3
    transition_temperature = 0.30
    state_persistence = 0.35
    preset_name$ = "3-4 Composite Grid"

    # 12-step composite grid = union of a 3-pulse cycle (steps 1,5,9)
    # and a 4-pulse cycle (steps 1,4,7,10), plus cyclic phase rotations.
    rhythmPattern$[1] = "100110101100"
    rhythmPattern$[2] = "001101011001"
    rhythmPattern$[3] = "011010110010"
    rhythmPattern$[4] = "110101100100"
    rhythmPattern$[5] = "101011001001"
    rhythmPattern$[6] = "010110010011"
    rhythmPattern$[7] = "101100100110"
    rhythmPattern$[8] = "011001001101"

elsif preset = 9
    tempo_bpm = 110
    base_frequency_Hz = 1800
    decay_rate = 65
    wood_character = 0.50
    steps_per_beat = 2
    transition_temperature = 0.16
    state_persistence = 0.30
    preset_name$ = "Euclidean E(5,8) Rotations"

    # E(5,8)=10110110 up to cyclic rotation.
    rhythmPattern$[1] = "10110110"
    rhythmPattern$[2] = "01101101"
    rhythmPattern$[3] = "11011010"
    rhythmPattern$[4] = "10110101"
    rhythmPattern$[5] = "01101011"
    rhythmPattern$[6] = "11010110"
    rhythmPattern$[7] = "10101101"
    rhythmPattern$[8] = "01011011"

else
    preset_name$ = "Custom"
    rhythmPattern$[1] = "10001000"
    rhythmPattern$[2] = "10101000"
    rhythmPattern$[3] = "10001010"
    rhythmPattern$[4] = "10100010"
    rhythmPattern$[5] = "10010010"
    rhythmPattern$[6] = "10101010"
    rhythmPattern$[7] = "11001010"
    rhythmPattern$[8] = "10110100"
endif

rhythmStates = 8

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_markov_rhythm_details
    beginPause: "Markov Rhythm Generator - Markov / Timing Details"
        integer: "Steps per beat", steps_per_beat
        real: "Transition temperature", transition_temperature
        real: "State persistence", state_persistence
        real: "Swing amount", swing_amount
        real: "Metric accent", metric_accent
        real: "Master amplitude", master_amplitude
        real: "Edge fade (s)", edge_fade_s
        integer: "Random seed", random_seed
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if tempo_bpm < 20 or tempo_bpm > 400
    exitScript: "Tempo must be between 20 and 400 BPM."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if decay_rate <= 0 or decay_rate > 1000
    exitScript: "Decay rate must be > 0 and <= 1000."
endif
if wood_character < 0 or wood_character > 1
    exitScript: "Wood character must be between 0 and 1."
endif
if canon_delay_beats <= 0 or canon_delay_beats > 32
    exitScript: "Canon delay must be > 0 and <= 32 beats."
endif
if steps_per_beat < 1 or steps_per_beat > 16
    exitScript: "Grid steps per beat must be between 1 and 16."
endif
if transition_temperature <= 0 or transition_temperature > 5
    exitScript: "Transition temperature must be > 0 and <= 5."
endif
if state_persistence < 0 or state_persistence > 1
    exitScript: "State persistence must be between 0 and 1."
endif
if swing_amount < 0 or swing_amount > 1
    exitScript: "Swing amount must be between 0 and 1."
endif
if swing_amount > 0 and steps_per_beat <> 2
    exitScript: "Swing timing currently requires exactly 2 grid steps per beat."
endif
if metric_accent < 0 or metric_accent > 1
    exitScript: "Metric accent must be between 0 and 1."
endif
if master_amplitude <= 0 or master_amplitude > 2
    exitScript: "Master amplitude must be > 0 and <= 2."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

patternLength = length(rhythmPattern$[1])
if patternLength < 2
    exitScript: "Rhythm patterns must contain at least two binary steps."
endif

for state from 1 to rhythmStates
    if length(rhythmPattern$[state]) <> patternLength
        exitScript: "All Markov rhythm states must have the same pattern length."
    endif

    for pos from 1 to patternLength
        ch$ = mid$(rhythmPattern$[state],pos,1)
        if ch$ <> "0" and ch$ <> "1"
            exitScript: "Rhythm templates may contain only 0 and 1."
        endif
    endfor
endfor

sr = sample_rate_Hz
safeTop = 0.45*sr
beatsPerSecond = tempo_bpm/60
beatDuration = 1/beatsPerSecond
stepDuration = beatDuration/steps_per_beat
cycleDuration = patternLength*stepDuration

# Canon delay is a MUSICAL interval. Convert to physical time only after the
# preset/custom tempo is known.
canonDelaySeconds = canon_delay_beats*beatDuration
canonDelaySteps = canon_delay_beats*steps_per_beat

if canon_mode = 1
    canonVoices = 1
elsif canon_mode = 2
    canonVoices = 2
else
    canonVoices = 3
endif

if canonVoices > 1
    totalDuration = duration_s+(canonVoices-1)*canonDelaySeconds
    channelCount = 2
    maxVoiceMultiplier = 1.25
else
    totalDuration = duration_s
    channelCount = 1
    maxVoiceMultiplier = 1
endif

# All synthetic resonances must stay below safeTop; the highest ratio is 4f.
frequencyScale = min(1,safeTop/(4*maxVoiceMultiplier*base_frequency_Hz))
effectiveBase = base_frequency_Hz*frequencyScale

if effectiveBase < 80
    exitScript: "Nyquist protection would move the woody resonator below 80 Hz. Reduce Base frequency or sample at a higher rate."
endif

pulseDuration = min(0.14,max(0.025,6/decay_rate))
woodRatio = 2.76
clickRatio = 4.0

# ---------------------------------------------------------------------------
# RANDOMNESS
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# STATE ONSET COUNTS + HAMMING-DISTANCE TRANSITION MATRIX
# ---------------------------------------------------------------------------
onsetCount# = zero#(rhythmStates)
meanOnsets = 0

for state from 1 to rhythmStates
    hits = 0
    for pos from 1 to patternLength
        if mid$(rhythmPattern$[state],pos,1) = "1"
            hits = hits+1
        endif
    endfor

    if hits < 1
        exitScript: "Every rhythm state must contain at least one onset."
    endif

    onsetCount#[state] = hits
    meanOnsets = meanOnsets+hits/rhythmStates
endfor

transitionP## = zero##(rhythmStates,rhythmStates)
hamming## = zero##(rhythmStates,rhythmStates)

for i from 1 to rhythmStates
    # First measure the complete row and find its nearest alternative state.
    # Subtracting this minimum distance in the exponential leaves normalized
    # probabilities unchanged but prevents all alternative weights underflowing
    # to zero when Transition temperature is very small.
    minAlternativeDistance = 1e30

    for j from 1 to rhythmStates
        mismatches = 0
        for pos from 1 to patternLength
            if mid$(rhythmPattern$[i],pos,1) <> mid$(rhythmPattern$[j],pos,1)
                mismatches = mismatches+1
            endif
        endfor

        distance = mismatches/patternLength
        hamming##[i,j] = distance

        if i <> j
            minAlternativeDistance = min(minAlternativeDistance,distance)
        endif
    endfor

    alternativeWeight = 0

    for j from 1 to rhythmStates
        if i <> j
            distance = hamming##[i,j]
            weight = exp(-(distance-minAlternativeDistance)/transition_temperature)
            transitionP##[i,j] = weight
            alternativeWeight = alternativeWeight+weight
        endif
    endfor

    transitionP##[i,i] = state_persistence

    if state_persistence < 1
        for j from 1 to rhythmStates
            if j <> i
                transitionP##[i,j] =
                    ... (1-state_persistence)*
                    ... transitionP##[i,j]/alternativeWeight
            endif
        endfor
    else
        for j from 1 to rhythmStates
            if j <> i
                transitionP##[i,j] = 0
            endif
        endfor
    endif
endfor

# ---------------------------------------------------------------------------
# PROCEDURE: DRAW NEXT MARKOV STATE
# ---------------------------------------------------------------------------
procedure chooseNextState: .current
    .u = randomUniform(0,1)
    .cumulative = 0
    .result = rhythmStates
    .chosen = 0

    for .j from 1 to rhythmStates
        if .chosen = 0
            .cumulative = .cumulative+transitionP##[.current,.j]
            if .u <= .cumulative
                .result = .j
                .chosen = 1
            endif
        endif
    endfor
endproc

# ---------------------------------------------------------------------------
# BASE MARKOV REALIZATION
# ---------------------------------------------------------------------------
basePulseCount = 0
cycleCount = 0
cycleStart = 0
currentState = randomInteger(1,rhythmStates)

stateVisits# = zero#(rhythmStates)
transitionCount## = zero##(rhythmStates,rhythmStates)
realizedDistanceSum = 0
transitionDecisions = 0

while cycleStart < duration_s
    cycleCount = cycleCount+1
    cycleState[cycleCount] = currentState
    cycleTime[cycleCount] = cycleStart
    stateVisits#[currentState] = stateVisits#[currentState]+1

    pattern$ = rhythmPattern$[currentState]
    stateGain = sqrt(meanOnsets/onsetCount#[currentState])

    for step from 1 to patternLength
        if mid$(pattern$,step,1) = "1"
            onset = cycleStart+(step-1)*stepDuration

            # With a 2-step beat grid, shift the second subdivision from 1/2
            # beat toward 2/3 beat. swing_amount=1 adds beatDuration/6.
            if swing_amount > 0 and ((step-1) mod 2)=1
                onset = onset+swing_amount*beatDuration/6
            endif

            if onset < duration_s
                basePulseCount = basePulseCount+1
                basePulseTime[basePulseCount] = onset
                basePulseState[basePulseCount] = currentState
                basePulseStep[basePulseCount] = step

                beatGridPos = (step-1) mod steps_per_beat
                if beatGridPos = 0
                    accent = 1+metric_accent
                else
                    accent = 1
                endif

                basePulseAmp[basePulseCount] = stateGain*accent
            endif
        endif
    endfor

    nextCycleStart = cycleStart+cycleDuration

    if nextCycleStart < duration_s
        oldState = currentState
        @chooseNextState: currentState
        currentState = chooseNextState.result
        transitionCount##[oldState,currentState] = transitionCount##[oldState,currentState]+1
        realizedDistanceSum = realizedDistanceSum+hamming##[oldState,currentState]
        transitionDecisions = transitionDecisions+1
    endif

    cycleStart = nextCycleStart
endwhile

if basePulseCount < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "The realized rhythm contains no pulses."
endif

# ---------------------------------------------------------------------------
# EMPIRICAL MARKOV DIAGNOSTICS
# ---------------------------------------------------------------------------
empiricalP## = zero##(rhythmStates,rhythmStates)
realizedSelfTransitions = 0
mostVisitedState = 1

for i from 1 to rhythmStates
    if stateVisits#[i] > stateVisits#[mostVisitedState]
        mostVisitedState = i
    endif

    rowTotal = 0
    for j from 1 to rhythmStates
        rowTotal = rowTotal+transitionCount##[i,j]
    endfor

    if rowTotal > 0
        for j from 1 to rhythmStates
            empiricalP##[i,j] = transitionCount##[i,j]/rowTotal
        endfor
    endif

    realizedSelfTransitions = realizedSelfTransitions+transitionCount##[i,i]
endfor

if transitionDecisions > 0
    empiricalPersistence = realizedSelfTransitions/transitionDecisions
    meanRealizedDistance = realizedDistanceSum/transitionDecisions
else
    empiricalPersistence = 0
    meanRealizedDistance = 0
endif

initialState = cycleState[1]
finalState = cycleState[cycleCount]

fewTransitions = 0
if transitionDecisions < 4
    fewTransitions = 1
endif

# ---------------------------------------------------------------------------
# CANON / OUTPUT EVENT COUNT + ENERGY COMPENSATION
# ---------------------------------------------------------------------------
totalPulses = basePulseCount*canonVoices
if totalPulses > 12000
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "Realization exceeds 12000 rendered pulses. Reduce duration, tempo, grid density or canon voices."
endif

sumPulseDur = totalPulses*pulseDuration
overlapLoad = sumPulseDur/totalDuration
overlapGain = 1/sqrt(max(1,overlapLoad))

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  MARKOV RHYTHM GENERATOR v0.5.2"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Tempo: ", fixed$(tempo_bpm,2), " BPM"
appendInfoLine: "Grid: ", steps_per_beat, " steps/beat"
appendInfoLine: "Pattern length: ", patternLength, " steps"
appendInfoLine: "Cycle duration: ", fixed$(cycleDuration,4), " s"
appendInfoLine: "Base cycles / pulses: ", cycleCount, " / ", basePulseCount
appendInfoLine: "Transition temperature: ", fixed$(transition_temperature,3)
appendInfoLine: "Theoretical self-transition probability: ", fixed$(state_persistence,3)
appendInfoLine: "Empirical self-transition rate: ", fixed$(empiricalPersistence,3)
appendInfoLine: "Mean realized Hamming distance: ", fixed$(meanRealizedDistance,3)
if fewTransitions
    appendInfoLine: "QC: fewer than 4 Markov decisions; increase Duration for a more informative chain realization."
endif
appendInfoLine: "Swing amount: ", fixed$(swing_amount,3)
appendInfoLine: "Canon voices: ", canonVoices
appendInfoLine: "Canon delay: ", fixed$(canon_delay_beats,3), " beat(s) = ", fixed$(canonDelaySeconds,4), " s at current tempo"
appendInfoLine: "Canon delay in grid steps: ", fixed$(canonDelaySteps,3)
appendInfoLine: "Total rendered pulses: ", totalPulses
appendInfoLine: "Overlap load: ", fixed$(overlapLoad,3)
appendInfoLine: "Overlap gain: ", fixed$(overlapGain,3)
appendInfoLine: "Base frequency requested/effective: ", fixed$(base_frequency_Hz,1), " / ", fixed$(effectiveBase,1), " Hz"
appendInfoLine: "Frequency scale: ", fixed$(frequencyScale,5)
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# OUTPUT BUFFER
# ---------------------------------------------------------------------------
outputSound = Create Sound from formula:
    ... "MarkovRhythm_" + uid$,channelCount,0,totalDuration,sr,"0"

# ---------------------------------------------------------------------------
# LOCAL PULSE RENDERING
# ---------------------------------------------------------------------------
sourcePeakBound = 0.70+0.42*wood_character+0.18
sourceNorm = 1/sourcePeakBound

for voice from 1 to canonVoices
    voiceDelay = (voice-1)*canonDelaySeconds

    if voice = 1
        voiceMultiplier = 1
    elsif voice = 2
        voiceMultiplier = 1.25
    else
        voiceMultiplier = 0.80
    endif

    voiceFreq = effectiveBase*voiceMultiplier

    if canonVoices = 1
        voicePan = 0.5
    else
        voicePan = (voice-1)/(canonVoices-1)
    endif

    if channelCount = 2
        gL = sqrt(1-voicePan)
        gR = sqrt(voicePan)
    endif

    for p from 1 to basePulseCount
        onset = voiceDelay+basePulseTime[p]
        pend = min(totalDuration,onset+pulseDuration)

        if pend > onset
            age$ = "(x-" + fixed$(onset,9) + ")"
            amp = master_amplitude*overlapGain*basePulseAmp[p]

            wave$ = fixed$(sourceNorm*0.70,9)
                ... + "*exp(-" + fixed$(decay_rate,6)
                ... + "*" + age$ + ")*sin(2*pi*"
                ... + fixed$(voiceFreq,6) + "*" + age$ + ")"
                ... + "+" + fixed$(sourceNorm*0.42*wood_character,9)
                ... + "*exp(-" + fixed$(1.45*decay_rate,6)
                ... + "*" + age$ + ")*sin(2*pi*"
                ... + fixed$(voiceFreq*woodRatio,6) + "*" + age$ + ")"
                ... + "+" + fixed$(sourceNorm*0.18,9)
                ... + "*exp(-" + fixed$(3.5*decay_rate,6)
                ... + "*" + age$ + ")*sin(2*pi*"
                ... + fixed$(voiceFreq*clickRatio,6) + "*" + age$ + ")"

            selectObject: outputSound

            if channelCount = 1
                Formula (part): onset,pend,1,1,
                    ... "self+" + fixed$(amp,9) + "*(" + wave$ + ")"
            else
                Formula (part): onset,pend,1,2,
                    ... "self+if row=1 then " + fixed$(amp*gL,9)
                    ... + "*(" + wave$ + ") else " + fixed$(amp*gR,9)
                    ... + "*(" + wave$ + ") fi"
            endif
        endif
    endfor
endfor

# ---------------------------------------------------------------------------
# SHORT COMMON EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.10*totalDuration)

if actualFade > 0
    fadeOutStart = totalDuration-actualFade
    selectObject: outputSound
    Formula:
        ... "if x<actualFade then self*(x/actualFade)"
        ... + " else if x>fadeOutStart then self*((totalDuration-x)/actualFade)"
        ... + " else self fi fi"
endif

selectObject: outputSound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

Rename: "MarkovRhythm_" + replace$(preset_name$," ","_",0)
outputSound = selected("Sound")
finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

appendInfoLine: "Pre-protection peak/RMS: ", fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ", fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

selectObject: outputSound
if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# VISUALIZATION HELPER: ONE ACTUAL RHYTHM NECKLACE
# ===========================================================================
procedure drawNecklace: .state,.xLeft,.xRight,.label$
    Select inner viewport: .xLeft,.xRight,1.10,2.48
    Axes: -1.25,1.25,-1.25,1.25

    Colour: "{0.86,0.86,0.88}"
    Line width: 1
    Draw circle: 0,0,0.88

    .pattern$ = rhythmPattern$[.state]
    .len = length(.pattern$)
    .onsetN = 0

    for .q from 1 to .len
        .angle = 2*pi*(.q-1)/.len-pi/2
        .px = 0.88*cos(.angle)
        .py = 0.88*sin(.angle)

        if mid$(.pattern$,.q,1) = "1"
            .onsetN = .onsetN+1
            .onsetAngle[.onsetN] = .angle
            Paint circle (mm): "{0.74,0.32,0.12}",.px,.py,1.45
        else
            Paint circle (mm): "{0.72,0.72,0.74}",.px,.py,0.78
        endif
    endfor

    if .onsetN > 1
        Colour: "{0.82,0.50,0.22}"
        Line width: 1.4
        for .q from 1 to .onsetN
            .next = .q+1
            if .next > .onsetN
                .next = 1
            endif
            Draw line:
                ... 0.64*cos(.onsetAngle[.q]),0.64*sin(.onsetAngle[.q]),
                ... 0.64*cos(.onsetAngle[.next]),0.64*sin(.onsetAngle[.next])
        endfor
    endif

    Colour: "Black"
    Font size: 5
    Text: 0,"centre",-1.10,"half",
        ... .label$ + " S" + string$(.state) + "  " + .pattern$
    Line width: 1
endproc


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.83,0.83,0.85}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.84,0.42,0.16}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "MARKOV RHYTHM GENERATOR | " + preset_name$

    Select inner viewport: 0.35,7.65,0.38,0.72
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... string$(patternLength) + "-step necklaces | "
        ... + string$(steps_per_beat) + " steps/beat | cycle "
        ... + fixed$(cycleDuration,3) + " s | " + string$(cycleCount) + " realized cycles"
    Text: 0.5,"centre",0.18,"half",
        ... "rhythm Hamming geometry -> Markov transition -> realized onset grid -> delayed rhythmic canon"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL STATES AS NECKLACES
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.82,1.02
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "A  ACTUAL RHYTHM NECKLACES | initial, most-visited and final states"

    @drawNecklace: initialState,0.45,2.75,"initial"
    @drawNecklace: mostVisitedState,2.85,5.15,"most visited"
    @drawNecklace: finalState,5.25,7.55,"final"

    # -----------------------------------------------------------------------
    # PANEL B TITLE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.60,2.80
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "B  MARKOV MODEL / REALIZATION | expected transition matrix and actual cycle states"

    # -----------------------------------------------------------------------
    # PANEL B LEFT: EXPECTED TRANSITION MATRIX
    # -----------------------------------------------------------------------
    Select inner viewport: 0.65,3.55,2.88,4.18
    Axes: 0,1,0,1
    Paint rectangle: .bg$,0,1,0,1

    .mx0 = 0.18
    .mx1 = 0.94
    .my0 = 0.10
    .my1 = 0.92
    .cw = (.mx1-.mx0)/rhythmStates
    .ch = (.my1-.my0)/rhythmStates

    for .i from 1 to rhythmStates
        for .j from 1 to rhythmStates
            .p = transitionP##[.i,.j]
            .gray = 0.98-0.68*min(1,4*.p)
            .col$ = "{" + fixed$(.gray,3) + "," + fixed$(.gray,3) + "," + fixed$(1-0.35*min(1,4*.p),3) + "}"
            .xa = .mx0+(.j-1)*.cw
            .xb = .xa+.cw
            .yb = .my1-(.i-1)*.ch
            .ya = .yb-.ch
            Paint rectangle: .col$,.xa,.xb,.ya,.yb
        endfor
    endfor

    Colour: "{0.42,0.42,0.45}"
    Draw rectangle: .mx0,.mx1,.my0,.my1
    Font size: 4
    Colour: "Black"
    for .i from 1 to rhythmStates
        .yc = .my1-(.i-0.5)*.ch
        .xc = .mx0+(.i-0.5)*.cw
        Text: .mx0-0.02,"right",.yc,"half",string$(.i)
        Text: .xc,"centre",.my0-0.035,"half",string$(.i)
    endfor
    Text: 0.56,"centre",0.02,"half","expected P(next state | current state)"

    # -----------------------------------------------------------------------
    # PANEL B RIGHT: ACTUAL STATE TIMELINE
    # -----------------------------------------------------------------------
    Select inner viewport: 3.85,7.55,2.88,4.18
    Axes: 0,duration_s,0.5,rhythmStates+0.5
    Paint rectangle: .bg$,0,duration_s,0.5,rhythmStates+0.5

    Colour: .grid$
    Dotted line
    for .s from 1 to rhythmStates
        Draw line: 0,.s,duration_s,.s
    endfor
    Plain line

    for .c from 1 to cycleCount
        .st = cycleState[.c]
        .ct = cycleTime[.c]
        .ce = min(duration_s,.ct+cycleDuration)
        Colour: .blue$
        Draw line: .ct,.st,.ce,.st
        Paint circle (mm): .blue$,.ct,.st,0.85

        if .c < cycleCount
            Draw line: .ce,.st,.ce,cycleState[.c+1]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 4,"yes","yes","no"
    Marks left every: 1,1,"yes","yes","no"
    Font size: 5
    Text left: "yes","State"

    # -----------------------------------------------------------------------
    # PANEL C: ACTUAL ONSET RASTER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,4.34,4.54
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "C  ACTUAL ONSET RASTER | same realization delayed by " + fixed$(canon_delay_beats,2) + " beat(s) per voice"

    Select inner viewport: 0.82,7.52,4.61,5.48
    Axes: 0,totalDuration,0.5,canonVoices+0.5
    Paint rectangle: .bg$,0,totalDuration,0.5,canonVoices+0.5

    for .voice from 1 to canonVoices
        .delay = (.voice-1)*canonDelaySeconds
        .h = (.voice-1)/max(1,canonVoices-1)
        .r = 0.18+0.60*.h
        .g = 0.46-0.18*.h
        .b = 0.76-0.46*.h
        .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"

        for .p from 1 to basePulseCount
            .tt = .delay+basePulseTime[.p]
            Paint circle (mm): .col$,.tt,.voice,0.62
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Marks left every: 1,1,"yes","yes","no"
    Font size: 5
    Text left: "yes","Voice"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "markov_rhythm_display"
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0,0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.62,5.82
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "D  SOUND MODEL -> MEASUREMENT | measured spectrogram + resonator guides"

    .specMax = min(safeTop,max(5000,1.08*effectiveBase*maxVoiceMultiplier*clickRatio))
    .specStep = max(0.002,totalDuration/1200)

    selectObject: .disp
    To Spectrogram: 0.012,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: 0.82,7.52,5.89,6.82
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,totalDuration,0,.specMax
    Colour: "{0.15,0.55,0.82}"
    Line width: 0.7

    for .voice from 1 to canonVoices
        if .voice = 1
            .vm = 1
        elsif .voice = 2
            .vm = 1.25
        else
            .vm = 0.80
        endif
        .vf = effectiveBase*.vm

        if .vf <= .specMax
            Draw line: 0,.vf,totalDuration,.vf
        endif
        if .vf*woodRatio <= .specMax
            Draw line: 0,.vf*woodRatio,totalDuration,.vf*woodRatio
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,7.00,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1
    Font size: 5.5
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.77,"half",
        ... "MARKOV  |  cycles " + string$(cycleCount)
        ... + "  |  self P model/actual " + fixed$(state_persistence,2)
        ... + "/" + fixed$(empiricalPersistence,2)
        ... + "  |  mean Hamming jump " + fixed$(meanRealizedDistance,3)

    Text: 0.02,"left",0.52,"half",
        ... "RHYTHM  |  base hits " + string$(basePulseCount)
        ... + "  |  canon hits " + string$(totalPulses)
        ... + "  |  delay " + fixed$(canon_delay_beats,2) + " beat(s)"
        ... + "  |  overlap load " + fixed$(overlapLoad,2)
        ... + "  |  swing " + fixed$(swing_amount,2)

    Text: 0.02,"left",0.27,"half",
        ... "SPECTRUM  |  base " + fixed$(effectiveBase,0)
        ... + " Hz  |  wood 2.76x  |  click 4x  |  Nyquist scale "
        ... + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.07,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  RMS " + fixed$(preProtectRMS,4)
        ... + "  |  " + .level$ + "  |  " + seedLabel$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1
    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
