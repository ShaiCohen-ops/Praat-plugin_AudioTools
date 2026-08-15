# ============================================================
# Praat AudioTools - Formula Markov Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 runtime fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# MARKOV EVENT SYNTHESIS
#
#   A finite-state, first-order Markov chain selects a state for every
#   stochastic sound event. Each state maps to frequency, duration and a
#   mild amplitude tilt.
#
#   Event onsets are generated independently as a homogeneous Poisson process:
#
#       inter-onset interval ~ Exponential(Event_density)
#
#   Therefore Event_density is an actual expected events/second control and
#   event durations may overlap.
#
# TRANSITION MATRIX
#
#   Every Markov_type first defines a STRUCTURAL transition kernel P0:
#
#   1. Neighbor Persistence
#      stay = 0.50, step -1/+1 = 0.25/0.25, reflective boundaries
#
#   2. Circular Advance
#      deterministic +1 state with wraparound
#
#   3. Local Random Walk
#      steps [-2,-1,0,+1,+2] with weights [.10,.25,.30,.25,.10]
#      and reflective boundaries
#
#   4. Center Gravity
#      outside center: 0.70 toward center, 0.20 stay, 0.10 away
#      center: 0.55 stay, 0.225 to each neighbor
#
#   Transition_randomness r is then applied CONSISTENTLY to every model:
#
#       P = (1-r)*P0 + r*(1/N)
#
#   Thus r=0 preserves the structural kernel and r=1 gives a uniform jump
#   to every state. Every row is normalized and sampled directly.
#
# STATE -> SOUND
#
#   State frequency spans State_pitch_span_octaves from the lowest to the
#   highest state. State duration spans Min_event_ms..Max_event_ms.
#   Events use randomized phase and either a normalized 1+1/2+1/4 harmonic
#   source (subject to Nyquist) or a single sinusoid.
#
# v0.4.1 runtime fix:
#   - Replaced unsupported scientific$() formatting with fixed$().
#   - No Markov, DSP, preset, rendering or visualization logic changed.
#
# v0.4 reviewed:
#   - Event_density now controls a genuine Poisson onset process.
#   - Replaced ad-hoc transition code with an explicit NxN transition matrix.
#   - Transition_randomness now has one interpretable meaning in ALL 4 models.
#   - Reflective random-walk boundaries avoid the old clamp-induced edge pileup.
#   - Fixed undefined markov_type$ reporting by defining labels explicitly.
#   - State frequency span now reaches its requested octave endpoint exactly
#     (old exponent divided by N rather than N-1).
#   - Added Random_seed and reproducible Markov/event realizations.
#   - Added common Nyquist scaling of the full state-frequency ladder.
#   - Harmonic source is energy-normalized and truncates harmonics safely.
#   - Density compensation uses expected event overlap rather than 1/sqrt(rate).
#   - "Envelopes off" now keeps only a short click-safe edge taper instead of
#     beginning each event abruptly at full amplitude.
#   - Replaced repeated full-Sound 20-event Formula passes with chronological
#     0.5-s Formula(part) rendering; boundary-crossing events remain continuous.
#   - State-based stereo and rotation are now event-level equal-power panning;
#     removed left/right Hann-band filtering.
#   - Compact laptop-safe form + optional State/Synthesis details page.
#   - One combined edge fade and one optional final/common normalization.
#   - Visualization rebuilt around the Markov mechanism:
#       A theoretical transition matrix vs empirical realized matrix
#       B actual state trajectory
#       C actual state->frequency event field
#       D measured spectrogram + sampled event-frequency guides
#       transition-matrix / event-density / output QC
# ============================================================

form Formula Markov Synthesis v0.4
    optionmenu Preset 1
        option Custom (baseline values)
        option Neighbor Melodic Walk
        option Low Center-Gravity States
        option Fast Circular Pulse
        option Circular Ascending Cycle
        option Broad Random Walk
        option Center-Biased Walk
        option Sparse Neighbor Texture
        option Dense Random-Walk Cluster

    positive Duration_s 12.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    integer Number_of_states 8
    positive Event_density 5.0
    real Transition_randomness 0.30

    optionmenu Markov_type 1
        option Neighbor Persistence
        option Circular Advance
        option Local Random Walk
        option Center Gravity

    optionmenu Spatial_mode 1
        option Mono
        option State-Based Pan
        option Rotating Events

    boolean Edit_state_synthesis_details 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
state_pitch_span_octaves = 1.0
min_event_ms = 150
max_event_ms = 350
frequency_jitter_percent = 2.0
enable_harmonics = 1
enable_Hann_envelopes = 1
random_seed = 0
edge_fade_s = 0.02

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    number_of_states = 12
    event_density = 4
    base_frequency_Hz = 220
    markov_type = 1
    transition_randomness = 0.20
    state_pitch_span_octaves = 1.0
    min_event_ms = 110
    max_event_ms = 280
    frequency_jitter_percent = 1.5
    preset_name$ = "Neighbor Melodic Walk"

elsif preset = 3
    number_of_states = 5
    event_density = 2
    base_frequency_Hz = 60
    markov_type = 4
    transition_randomness = 0.08
    state_pitch_span_octaves = 0.55
    min_event_ms = 450
    max_event_ms = 1100
    frequency_jitter_percent = 0.8
    preset_name$ = "Low Center-Gravity States"

elsif preset = 4
    number_of_states = 6
    event_density = 8
    base_frequency_Hz = 150
    markov_type = 2
    transition_randomness = 0.03
    state_pitch_span_octaves = 0.70
    min_event_ms = 55
    max_event_ms = 130
    frequency_jitter_percent = 1.0
    preset_name$ = "Fast Circular Pulse"

elsif preset = 5
    number_of_states = 10
    event_density = 5
    base_frequency_Hz = 80
    markov_type = 2
    transition_randomness = 0.05
    state_pitch_span_octaves = 1.5
    min_event_ms = 120
    max_event_ms = 260
    frequency_jitter_percent = 1.2
    preset_name$ = "Circular Ascending Cycle"

elsif preset = 6
    number_of_states = 8
    event_density = 6
    base_frequency_Hz = 120
    markov_type = 3
    transition_randomness = 0.65
    state_pitch_span_octaves = 1.2
    min_event_ms = 90
    max_event_ms = 240
    frequency_jitter_percent = 4.0
    preset_name$ = "Broad Random Walk"

elsif preset = 7
    number_of_states = 9
    event_density = 4
    base_frequency_Hz = 180
    markov_type = 4
    transition_randomness = 0.22
    state_pitch_span_octaves = 0.85
    min_event_ms = 160
    max_event_ms = 360
    frequency_jitter_percent = 2.0
    preset_name$ = "Center-Biased Walk"

elsif preset = 8
    duration_s = 20
    number_of_states = 6
    event_density = 1.5
    base_frequency_Hz = 200
    markov_type = 1
    transition_randomness = 0.15
    state_pitch_span_octaves = 0.90
    min_event_ms = 250
    max_event_ms = 650
    frequency_jitter_percent = 2.0
    preset_name$ = "Sparse Neighbor Texture"

elsif preset = 9
    number_of_states = 5
    event_density = 12
    base_frequency_Hz = 100
    markov_type = 3
    transition_randomness = 0.50
    state_pitch_span_octaves = 0.45
    min_event_ms = 65
    max_event_ms = 150
    frequency_jitter_percent = 5.0
    preset_name$ = "Dense Random-Walk Cluster"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_state_synthesis_details
    beginPause: "Formula Markov Synthesis - State / Synthesis Details"
        real: "State pitch span (octaves)", state_pitch_span_octaves
        positive: "Min event duration (ms)", min_event_ms
        positive: "Max event duration (ms)", max_event_ms
        real: "Frequency jitter (percent)", frequency_jitter_percent
        boolean: "Enable 3-harmonic source", enable_harmonics
        boolean: "Enable Hann event envelopes", enable_Hann_envelopes
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Edge fade (s)", edge_fade_s
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# 1. VALIDATION / LABELS
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if number_of_states < 2 or number_of_states > 16
    exitScript: "Number of states must be between 2 and 16."
endif
if event_density <= 0 or event_density > 100
    exitScript: "Event density must be > 0 and <= 100 events/s."
endif
if transition_randomness < 0 or transition_randomness > 1
    exitScript: "Transition randomness must be between 0 and 1."
endif
if state_pitch_span_octaves < 0 or state_pitch_span_octaves > 4
    exitScript: "State pitch span must be between 0 and 4 octaves."
endif
if min_event_ms <= 0 or max_event_ms <= 0 or min_event_ms > max_event_ms
    exitScript: "Event durations must be positive and min <= max."
endif
if max_event_ms > 5000
    exitScript: "Maximum event duration is limited to 5000 ms."
endif
if frequency_jitter_percent < 0 or frequency_jitter_percent > 100
    exitScript: "Frequency jitter must be between 0 and 100 percent."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if markov_type = 1
    markov_type$ = "Neighbor Persistence"
elsif markov_type = 2
    markov_type$ = "Circular Advance"
elsif markov_type = 3
    markov_type$ = "Local Random Walk"
else
    markov_type$ = "Center Gravity"
endif

if spatial_mode = 1
    spatial$ = "Mono"
elsif spatial_mode = 2
    spatial$ = "State-Based Pan"
else
    spatial$ = "Rotating Events"
endif

safeTop = 0.45*sample_rate_Hz
expectedEvents = event_density*duration_s

if expectedEvents > 8000
    exitScript: "Expected event count exceeds 8000. Reduce density or duration."
endif

if enable_harmonics
    sourceMaxHarmonic = 3
else
    sourceMaxHarmonic = 1
endif

jitterFrac = frequency_jitter_percent/100
requestedTopFundamental = base_frequency_Hz*2^state_pitch_span_octaves*(1+jitterFrac)
maxSafeFundamental = safeTop/sourceMaxHarmonic
pitchScale = min(1,maxSafeFundamental/requestedTopFundamental)

if base_frequency_Hz*pitchScale < 20
    exitScript: "Requested pitch span/harmonics require the whole state ladder below 20 Hz. Reduce Base frequency/span or disable harmonics."
endif

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
# 2. STATE -> SOUND MAPPING
# ---------------------------------------------------------------------------
stateFreq# = zero#(number_of_states)
stateDur# = zero#(number_of_states)
stateAmp# = zero#(number_of_states)

meanStateDur = 0
minStateFreq = 1e9
maxStateFreq = 0

for state from 1 to number_of_states
    pos = (state-1)/(number_of_states-1)

    stateFreq#[state] =
        ... base_frequency_Hz*pitchScale*2^(state_pitch_span_octaves*pos)

    stateDur#[state] =
        ... (min_event_ms+(max_event_ms-min_event_ms)*pos)/1000

    # Mild amplitude tilt only; the state identity is primarily pitch/duration.
    stateAmp#[state] = 0.75+0.25*pos

    meanStateDur = meanStateDur+stateDur#[state]/number_of_states
    minStateFreq = min(minStateFreq,stateFreq#[state])
    maxStateFreq = max(maxStateFreq,stateFreq#[state])
endfor

expectedOverlap = max(1,event_density*meanStateDur)
baseEventAmp = 0.46/sqrt(expectedOverlap)

# ---------------------------------------------------------------------------
# 3. BUILD STRUCTURAL + FINAL TRANSITION MATRICES
# ---------------------------------------------------------------------------
structural## = zero##(number_of_states,number_of_states)
transition## = zero##(number_of_states,number_of_states)

if markov_type = 1
    # 0.5 stay + 0.25 to each reflected neighbor.
    for s from 1 to number_of_states
        structural##[s,s] = structural##[s,s]+0.50

        left = s-1
        if left < 1
            left = min(number_of_states,2)
        endif

        right = s+1
        if right > number_of_states
            right = max(1,number_of_states-1)
        endif

        structural##[s,left] = structural##[s,left]+0.25
        structural##[s,right] = structural##[s,right]+0.25
    endfor

elsif markov_type = 2
    # Deterministic circular +1.
    for s from 1 to number_of_states
        target = s+1
        if target > number_of_states
            target = 1
        endif
        structural##[s,target] = 1
    endfor

elsif markov_type = 3
    # Reflective local walk.
    walkStep# = {-2,-1,0,1,2}
    walkWeight# = {0.10,0.25,0.30,0.25,0.10}

    for s from 1 to number_of_states
        for k from 1 to 5
            target = s+walkStep#[k]

            while target < 1 or target > number_of_states
                if target < 1
                    target = 2-target
                elsif target > number_of_states
                    target = 2*number_of_states-target
                endif
            endwhile

            structural##[s,target] =
                ... structural##[s,target]+walkWeight#[k]
        endfor
    endfor

else
    # Center-attracting kernel.
    centerState = round((number_of_states+1)/2)

    for s from 1 to number_of_states
        if s < centerState
            toward = s+1
            away = s-1
            if away < 1
                away = min(number_of_states,2)
            endif

            structural##[s,toward] = structural##[s,toward]+0.70
            structural##[s,s] = structural##[s,s]+0.20
            structural##[s,away] = structural##[s,away]+0.10

        elsif s > centerState
            toward = s-1
            away = s+1
            if away > number_of_states
                away = max(1,number_of_states-1)
            endif

            structural##[s,toward] = structural##[s,toward]+0.70
            structural##[s,s] = structural##[s,s]+0.20
            structural##[s,away] = structural##[s,away]+0.10

        else
            structural##[s,s] = structural##[s,s]+0.55

            left = max(1,s-1)
            right = min(number_of_states,s+1)

            if left = s and right = s
                structural##[s,s] = 1
            elsif left = s
                structural##[s,right] = structural##[s,right]+0.45
            elsif right = s
                structural##[s,left] = structural##[s,left]+0.45
            else
                structural##[s,left] = structural##[s,left]+0.225
                structural##[s,right] = structural##[s,right]+0.225
            endif
        endif
    endfor
endif

# Mix every structural row with the uniform transition matrix.
maxRowError = 0
meanTransitionEntropy = 0

for s from 1 to number_of_states
    rowSum = 0

    for j from 1 to number_of_states
        transition##[s,j] =
            ... (1-transition_randomness)*structural##[s,j]
            ... + transition_randomness/number_of_states
        rowSum = rowSum+transition##[s,j]
    endfor

    maxRowError = max(maxRowError,abs(rowSum-1))

    rowEntropy = 0
    for j from 1 to number_of_states
        pp = transition##[s,j]
        if pp > 0
            rowEntropy = rowEntropy-pp*ln(pp)
        endif
    endfor

    meanTransitionEntropy =
        ... meanTransitionEntropy+rowEntropy/ln(number_of_states)/number_of_states
endfor

if maxRowError > 1e-8
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "Internal transition-matrix row normalization error."
endif

# ---------------------------------------------------------------------------
# 4. POISSON EVENT PROCESS + MATRIX SAMPLING
# ---------------------------------------------------------------------------
appendInfoLine: "Running Markov event process..."

eventCount = 0
eventClock = 0
currentState = randomInteger(1,number_of_states)

stateVisit# = zero#(number_of_states)

while eventClock < duration_s
    u = max(1e-12,randomUniform(0,1))
    eventClock = eventClock-ln(u)/event_density

    if eventClock < duration_s
        eventCount = eventCount+1

        if eventCount > 10000
            if seedWasFixed
                random_initializeSafelyAndUnpredictably ()
            endif
            exitScript: "Stochastic realization exceeded 10,000 events."
        endif

        eventTime[eventCount] = eventClock
        eventState[eventCount] = currentState
        stateVisit#[currentState] = stateVisit#[currentState]+1

        freq = stateFreq#[currentState]*
            ... (1+randomUniform(-jitterFrac,jitterFrac))
        freq = max(20,min(maxSafeFundamental,freq))
        eventFreq[eventCount] = freq

        dur = stateDur#[currentState]*randomUniform(0.82,1.18)
        dur = min(dur,duration_s-eventClock)
        dur = max(1/sample_rate_Hz,dur)
        eventDur[eventCount] = dur

        eventAmp[eventCount] =
            ... baseEventAmp*stateAmp#[currentState]*
            ... randomUniform(0.88,1.12)

        eventPhase[eventCount] = 2*pi*randomUniform(0,1)

        # Event-level equal-power position.
        if spatial_mode = 1
            eventPan[eventCount] = 0.5

        elsif spatial_mode = 2
            statePos = (currentState-1)/(number_of_states-1)
            eventPan[eventCount] = 0.05+0.90*statePos

        else
            eventPan[eventCount] =
                ... 0.5+0.46*sin(2*pi*0.10*eventClock)
        endif

        # Sample next state directly from the current matrix row.
        r = randomUniform(0,1)
        cumulative = 0
        chosen = 0
        nextState = number_of_states

        for j from 1 to number_of_states
            cumulative = cumulative+transition##[currentState,j]
            if chosen = 0 and r <= cumulative
                nextState = j
                chosen = 1
            endif
        endfor

        currentState = nextState
    endif
endwhile

if eventCount < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "This realization produced zero events. Increase duration/density or change seed."
endif

realizedDensity = eventCount/duration_s

# ---------------------------------------------------------------------------
# 5. EMPIRICAL TRANSITION MATRIX
# ---------------------------------------------------------------------------
transitionCount## = zero##(number_of_states,number_of_states)
empirical## = zero##(number_of_states,number_of_states)
outgoing# = zero#(number_of_states)

if eventCount > 1
    for ev from 1 to eventCount-1
        a = eventState[ev]
        b = eventState[ev+1]
        transitionCount##[a,b] = transitionCount##[a,b]+1
        outgoing#[a] = outgoing#[a]+1
    endfor
endif

visitedTransitionRows = 0
matrixMAE = 0

for s from 1 to number_of_states
    if outgoing#[s] > 0
        visitedTransitionRows = visitedTransitionRows+1

        for j from 1 to number_of_states
            empirical##[s,j] =
                ... transitionCount##[s,j]/outgoing#[s]
            matrixMAE =
                ... matrixMAE+abs(empirical##[s,j]-transition##[s,j])
        endfor
    endif
endfor

if visitedTransitionRows > 0
    matrixMAE =
        ... matrixMAE/(visitedTransitionRows*number_of_states)
endif

# ---------------------------------------------------------------------------
# 6. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  FORMULA MARKOV SYNTHESIS v0.4.1"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Markov model: ", markov_type$
appendInfoLine: "States: ", number_of_states
appendInfoLine: "Transition randomness: ", fixed$(transition_randomness,3)
appendInfoLine: "Mean normalized row entropy: ",
    ... fixed$(meanTransitionEntropy,3)
appendInfoLine: "Target / realized event density: ",
    ... fixed$(event_density,2), " / ", fixed$(realizedDensity,2), " events/s"
appendInfoLine: "Expected / actual events: ",
    ... fixed$(expectedEvents,1), " / ", eventCount
appendInfoLine: "State F range: ",
    ... fixed$(minStateFreq,1), "-", fixed$(maxStateFreq,1), " Hz"
appendInfoLine: "Pitch-ladder scale for sampling headroom: ",
    ... fixed$(pitchScale,4)
appendInfoLine: "Empirical transition MAE: ", fixed$(matrixMAE,4)
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 7. CHUNK-LOCAL RENDERING
# ---------------------------------------------------------------------------
appendInfoLine: "Rendering Markov events..."

chunkDuration = min(0.5,duration_s)
numChunks = ceiling(duration_s/chunkDuration)
candidateStart = 1
maxPossibleDur = 1.18*max_event_ms/1000
maxTermsInChunk = 0

if spatial_mode = 1
    outputSound = Create Sound from formula:
        ... "markov_" + uid$,1,0,duration_s,sample_rate_Hz,"0"
else
    leftSound = Create Sound from formula:
        ... "markov_left_" + uid$,1,0,duration_s,sample_rate_Hz,"0"
    rightSound = Create Sound from formula:
        ... "markov_right_" + uid$,1,0,duration_s,sample_rate_Hz,"0"
endif

for chunk from 1 to numChunks
    chunkStart = (chunk-1)*chunkDuration
    chunkEnd = min(duration_s,chunk*chunkDuration)

    while candidateStart <= eventCount and
        ... eventTime[candidateStart]+maxPossibleDur <= chunkStart
        candidateStart = candidateStart+1
    endwhile

    if spatial_mode = 1
        chunkFormula$ = "0"
    else
        leftFormula$ = "0"
        rightFormula$ = "0"
    endif

    termsInChunk = 0
    ev = candidateStart

    while ev <= eventCount and eventTime[ev] < chunkEnd
        eventEnd = eventTime[ev]+eventDur[ev]

        if eventEnd > chunkStart
            termsInChunk = termsInChunk+1
            if termsInChunk > 160
                if seedWasFixed
                    random_initializeSafelyAndUnpredictably ()
                endif
                exitScript: "More than 160 overlapping event terms in a 0.5-s chunk. Reduce density or event duration."
            endif

            eTime = eventTime[ev]
            eDur = eventDur[ev]
            eFreq = eventFreq[ev]
            eAmp = eventAmp[ev]
            ePhase = eventPhase[ev]

            clipStart = max(chunkStart,eTime)
            clipEnd = min(chunkEnd,eventEnd)

            eTime$ = fixed$(eTime,9)
            eDur$ = fixed$(eDur,9)
            eAmp$ = fixed$(eAmp,9)
            ePhase$ = fixed$(ePhase,9)

            age$ = "(x-" + eTime$ + ")"

            # Energy-normalized harmonic source, truncated at practical Nyquist.
            maxH = 1
            if enable_harmonics
                maxH = min(3,floor(safeTop/eFreq))
                maxH = max(1,maxH)
            endif

            harmonicEnergy = 1
            if maxH >= 2
                harmonicEnergy = harmonicEnergy+0.25
            endif
            if maxH >= 3
                harmonicEnergy = harmonicEnergy+0.0625
            endif

            harmonicNorm = sqrt(2)/sqrt(harmonicEnergy)
            wave$ = fixed$(harmonicNorm,8)
                ... + "*sin(2*pi*" + fixed$(eFreq,6) + "*" + age$
                ... + "+" + ePhase$ + ")"

            if maxH >= 2
                wave$ = wave$ + "+"
                    ... + fixed$(0.5*harmonicNorm,8)
                    ... + "*sin(2*pi*" + fixed$(2*eFreq,6) + "*" + age$
                    ... + "+" + fixed$(2*ePhase,9) + ")"
            endif

            if maxH >= 3
                wave$ = wave$ + "+"
                    ... + fixed$(0.25*harmonicNorm,8)
                    ... + "*sin(2*pi*" + fixed$(3*eFreq,6) + "*" + age$
                    ... + "+" + fixed$(3*ePhase,9) + ")"
            endif

            if enable_Hann_envelopes
                env$ = "(0.5-0.5*cos(2*pi*" + age$ + "/" + eDur$ + "))"
            else
                # Minimal click-safe raised-cosine edges; otherwise flat.
                edge = min(0.004,0.15*eDur)
                edge$ = fixed$(max(1e-6,edge),9)
                releaseStart$ = fixed$(max(0,eDur-edge),9)

                env$ = "(if " + age$ + "<" + edge$
                    ... + " then 0.5-0.5*cos(pi*" + age$ + "/" + edge$
                    ... + ") else if " + age$ + ">" + releaseStart$
                    ... + " then 0.5+0.5*cos(pi*(" + age$ + "-"
                    ... + releaseStart$ + ")/" + edge$
                    ... + ") else 1 fi fi)"
            endif

            core$ = eAmp$ + "*(" + wave$ + ")*" + env$
            test$ = "if x>=" + fixed$(clipStart,9)
                ... + " and x<" + fixed$(clipEnd,9)
                ... + " then " + core$ + " else 0 fi"

            if spatial_mode = 1
                chunkFormula$ = chunkFormula$+"+"+test$

            else
                pan = eventPan[ev]
                leftGain = sqrt(1-pan)
                rightGain = sqrt(pan)

                leftFormula$ = leftFormula$ + "+"
                    ... + fixed$(leftGain,9) + "*(" + test$ + ")"
                rightFormula$ = rightFormula$ + "+"
                    ... + fixed$(rightGain,9) + "*(" + test$ + ")"
            endif
        endif

        ev = ev+1
    endwhile

    maxTermsInChunk = max(maxTermsInChunk,termsInChunk)

    if spatial_mode = 1
        if termsInChunk > 0
            selectObject: outputSound
            Formula (part): chunkStart,chunkEnd,1,1,
                ... "self+(" + chunkFormula$ + ")"
        endif

    else
        if termsInChunk > 0
            selectObject: leftSound
            Formula (part): chunkStart,chunkEnd,1,1,
                ... "self+(" + leftFormula$ + ")"

            selectObject: rightSound
            Formula (part): chunkStart,chunkEnd,1,1,
                ... "self+(" + rightFormula$ + ")"
        endif
    endif
endfor

if spatial_mode > 1
    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    outputSound = selected("Sound")
    removeObject: leftSound,rightSound
endif

# ---------------------------------------------------------------------------
# 8. EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)

if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: outputSound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0,0,"None"
preNormRMS = Get root-mean-square: 0,0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_name$," ","_",0)
Rename: "markov_" + safePreset$

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 9. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 10. PLAY / FINAL INFO
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Transition-matrix max row error: ",
    ... fixed$(maxRowError,8)
appendInfoLine: "Empirical matrix MAE over visited rows: ",
    ... fixed$(matrixMAE,4)
appendInfoLine: "Max overlapping terms in any 0.5-s render chunk: ",
    ... maxTermsInChunk
appendInfoLine: "Pre-normalization peak/RMS: ",
    ... fixed$(preNormPeak,4), " / ", fixed$(preNormRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .purple$ = "{0.52,0.30,0.62}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "FORMULA MARKOV SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... markov_type$ + " | N=" + string$(number_of_states)
        ... + " | randomness=" + fixed$(transition_randomness,2)
        ... + " | target " + fixed$(event_density,1) + " events/s"
    Text: 0.5,"centre",0.20,"half",
        ... "transition matrix -> Markov state sequence -> Poisson event field -> state pitch/duration -> audio"

    # -----------------------------------------------------------------------
    # PANEL A: THEORETICAL VS EMPIRICAL TRANSITION MATRIX
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  TRANSITION MATRIX | theoretical model P vs empirical realized transitions"

    Select inner viewport: .left,.right,1.05,2.25
    Axes: 0,1,0,1
    Paint rectangle: .bg$,0,1,0,1

    .xL0 = 0.06
    .xL1 = 0.45
    .xR0 = 0.55
    .xR1 = 0.94
    .y0 = 0.10
    .y1 = 0.88
    .cw = (.xL1-.xL0)/number_of_states
    .ch = (.y1-.y0)/number_of_states

    Font size: 6
    Colour: "Black"
    Text: 0.5*(.xL0+.xL1),"centre",0.95,"half","MODEL P"
    Text: 0.5*(.xR0+.xR1),"centre",0.95,"half","REALIZED"

    for .s from 1 to number_of_states
        for .j from 1 to number_of_states
            .p = transition##[.s,.j]
            .r = 1-0.10*.p
            .g = 1-0.55*.p
            .b = 1-0.75*.p
            .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                ... + "," + fixed$(.b,3) + "}"

            .xa = .xL0+(.j-1)*.cw
            .xb = .xa+.cw
            .yb = .y1-(.s-1)*.ch
            .ya = .yb-.ch
            Paint rectangle: .col$,.xa,.xb,.ya,.yb

            .p = empirical##[.s,.j]
            .r = 1-0.72*.p
            .g = 1-0.48*.p
            .b = 1-0.12*.p
            .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                ... + "," + fixed$(.b,3) + "}"

            .xa = .xR0+(.j-1)*.cw
            .xb = .xa+.cw
            Paint rectangle: .col$,.xa,.xb,.ya,.yb
        endfor
    endfor

    # Matrix boxes.
    Colour: "{0.45,0.45,0.48}"
    Draw rectangle: .xL0,.xL1,.y0,.y1
    Draw rectangle: .xR0,.xR1,.y0,.y1

    # Sparse state labels only when they remain legible.
    Font size: 4
    Colour: "{0.35,0.35,0.37}"

    if number_of_states <= 12
        .labelStep = 1
    else
        .labelStep = 2
    endif

    for .s from 1 to number_of_states
        if ((.s-1) mod .labelStep)=0
            .yc = .y1-(.s-0.5)*.ch
            Text: .xL0-0.012,"right",.yc,"half",string$(.s)
        endif
    endfor

    Text: 0.50,"centre",0.025,"half",
        ... "rows=current state | columns=next state | empirical MAE="
        ... + fixed$(matrixMAE,3)

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL STATE TRAJECTORY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.40,2.62
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  REALIZED MARKOV TRAJECTORY | state selected at each Poisson event"

    Select inner viewport: .left,.right,2.69,3.62
    Axes: 0,duration_s,0.5,number_of_states+0.5
    Paint rectangle: .bg$,0,duration_s,0.5,number_of_states+0.5

    Colour: .grid$
    Dotted line
    for .s from 1 to number_of_states
        Draw line: 0,.s,duration_s,.s
    endfor
    Plain line

    Colour: .blue$
    Line width: 1.2
    for .ev from 1 to eventCount-1
        Draw line:
            ... eventTime[.ev],eventState[.ev],
            ... eventTime[.ev+1],eventState[.ev+1]
    endfor

    .eventStep = max(1,ceiling(eventCount/900))
    for .ev from 1 to eventCount
        if ((.ev-1) mod .eventStep)=0
            .h = (eventState[.ev]-1)/(number_of_states-1)
            .r = 0.18+0.62*.h
            .g = 0.48-0.24*.h
            .b = 0.78-0.46*.h
            .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                ... + "," + fixed$(.b,3) + "}"
            Paint circle (mm): .col$,eventTime[.ev],eventState[.ev],0.75
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: min(number_of_states,8),"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","State"

    # -----------------------------------------------------------------------
    # PANEL C: ACTUAL STATE -> FREQUENCY EVENTS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.78,4.00
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  STATE -> SOUND | actual event frequency and duration; colour follows state"

    .logLo = ln(max(20,0.90*minStateFreq*(1-jitterFrac)))
    .logHi = ln(min(safeTop,1.10*maxStateFreq*(1+jitterFrac)))
    if .logHi <= .logLo
        .logHi = .logLo+0.5
    endif

    Select inner viewport: .left,.right,4.07,5.03
    Axes: 0,duration_s,.logLo,.logHi
    Paint rectangle: .bg$,0,duration_s,.logLo,.logHi

    for .ev from 1 to eventCount
        if ((.ev-1) mod .eventStep)=0
            .h = (eventState[.ev]-1)/(number_of_states-1)
            .r = 0.18+0.62*.h
            .g = 0.48-0.24*.h
            .b = 0.78-0.46*.h
            .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                ... + "," + fixed$(.b,3) + "}"

            Colour: .col$
            Draw line:
                ... eventTime[.ev],ln(eventFreq[.ev]),
                ... min(duration_s,eventTime[.ev]+eventDur[.ev]),
                ... ln(eventFreq[.ev])
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","log frequency"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "markov_display_" + uid$
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
    # PANEL D: MODEL -> MEASURED AUDIO
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.19,5.41
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + sampled actual event fundamentals"

    .specMax = min(safeTop,max(1200,sourceMaxHarmonic*maxStateFreq*(1+jitterFrac)*1.10))
    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.48,6.52
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: .blue$
    Line width: 0.7

    .guideStep = max(1,ceiling(eventCount/220))
    for .ev from 1 to eventCount
        if ((.ev-1) mod .guideStep)=0
            Draw line:
                ... eventTime[.ev],eventFreq[.ev],
                ... min(duration_s,eventTime[.ev]+eventDur[.ev]),
                ... eventFreq[.ev]
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.72,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "MARKOV QC  |  row error " + fixed$(maxRowError,8)
        ... + "  |  empirical MAE " + fixed$(matrixMAE,3)
        ... + "  |  normalized entropy " + fixed$(meanTransitionEntropy,3)

    Text: 0.02,"left",0.58,"half",
        ... "EVENTS  |  expected " + fixed$(expectedEvents,1)
        ... + "  |  actual " + string$(eventCount)
        ... + "  |  realized " + fixed$(realizedDensity,2) + "/s"
        ... + "  |  " + seedLabel$

    Text: 0.02,"left",0.36,"half",
        ... "STATE SOUND  |  F " + fixed$(minStateFreq,0) + "-"
        ... + fixed$(maxStateFreq,0) + " Hz"
        ... + "  |  span " + fixed$(state_pitch_span_octaves,2) + " oct"
        ... + "  |  pitch scale " + fixed$(pitchScale,3)

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
