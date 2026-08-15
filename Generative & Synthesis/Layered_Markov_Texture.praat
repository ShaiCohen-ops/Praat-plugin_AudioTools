# ============================================================
# Praat AudioTools - Layered_Markov_Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 conceptual + DSP review (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# LAYERED MARKOV TEXTURE
#
# CONCEPTUAL MODEL
# ----------------
# This engine is a coupled collection of finite-state stochastic processes.
# Each layer has:
#
#   - its own Poisson event clock
#   - its own state count
#   - its own transition mobility / jump probability / directional bias
#   - its own frequency anchor
#
# Events from all layers are generated in GLOBAL chronological order. When an
# event occurs, the active layer emits its current state and then selects its
# next state. With Cross_layer_influence enabled, the transition direction is
# biased toward the current normalized mean state of the OTHER layers:
#
#     local chain state ----\
#                            > coupled transition decision
#     ensemble mean state --/
#
# Cross-layer influence therefore changes the MARKOV STRUCTURE itself. It is
# not post-hoc FM or an audio effect.
#
# EVENT TIMING
# ------------
# "Event rate per layer" is a genuine expected Poisson rate:
#
#     Delta t ~ Exponential(lambda)
#
# Event duration is independent of inter-onset interval, so events may overlap
# within a layer and across layers. This separates density from articulation.
#
# STATE -> SOUND
# --------------
# Every layer has a moving frequency anchor. The Markov state distributes
# frequency symmetrically in log-frequency around that anchor:
#
#     f = anchor(t) * 2^(span * (statePosition - 0.5))
#
# The state also changes event duration, level and second-harmonic weight.
#
# LAYER LAYOUT
# ------------
# Geometric:
#     anchor_l = f0 * spacing^(l-1)
#
# Harmonic:
#     anchor_l = f0 * l
#
# LAYER MOTION
# ------------
# Stationary:
#     start anchor = end anchor
#
# Converging:
#     each log-frequency anchor moves toward the ensemble log-frequency centre
#
# Diverging:
#     each anchor moves away from that centre
#
# Therefore the Converging / Diverging presets now describe an actual temporal
# process, unlike v0.3 where all anchors were static.
#
# COMPLEXITY
# ----------
# Complexity is now restricted to the transition process:
# higher values increase state mobility and long-distance jumps.
# It no longer silently lengthens event durations and thereby changes density.
#
# v0.4 changes
# ------------
#   - genuine layer-specific transition kernels
#   - genuine cross-layer state coupling
#   - genuine Poisson event rate per layer
#   - global chronological scheduler; no O(N^2) event sort
#   - Harmonic Stack uses f_l = l*f0 rather than octave spacing
#   - Converging / Diverging presets now move frequency anchors in time
#   - state pitch mapping is log-symmetric around each layer anchor
#   - complexity affects transition entropy/mobility, not event duration
#   - independent event duration permits real within-layer overlap
#   - added reproducible Random_seed
#   - common frequency scaling preserves the complete layered geometry
#   - event-level equal-power stereo; removed complementary spectral filtering
#   - rotating mode is layer/event spatial motion, not amplitude-imbalanced mono
#   - one short common edge fade
#   - one optional DOWN-ONLY final peak protector
#   - visualization rebuilt around the mechanism:
#       A actual normalized state trajectory by layer
#       B actual event field on log-frequency axis
#       C expected vs empirical layer mobility + coupling disagreement
#       D measured spectrogram + sampled actual event guides
#       density / transition / sampling / level QC
# ============================================================

form Layered Markov Texture v0.4
    optionmenu Preset 1
        option Custom
        option Sparse Independent Layers
        option Dense Coupled Weave
        option Harmonic Layer Stack
        option Wide Geometric Spread
        option Converging Layer Field
        option Diverging Layer Field

    positive Duration_s 10.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 80

    integer Number_of_layers 3
    optionmenu Layer_layout 1
        option Geometric
        option Harmonic
    real Layer_spacing 1.5
    optionmenu Layer_motion 1
        option Stationary
        option Converging
        option Diverging

    positive Event_rate_per_layer_Hz 3.0
    real Complexity 1.0
    boolean Cross_layer_influence 1

    optionmenu Spatial_mode 1
        option Mono
        option Layer Spread
        option Rotating Layers

    boolean Edit_markov_texture_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
state_pitch_span_octaves = 0.72
mean_event_duration_s = 0.18
event_duration_spread = 0.35
frequency_jitter_percent = 1.5
coupling_strength = 0.35
layer_motion_depth = 0.70
rotation_rate_Hz = 0.08
edge_fade_s = 0.06
random_seed = 0

preset_name$ = "Custom"

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
if preset = 2
    duration_s = 14
    number_of_layers = 2
    layer_layout = 1
    layer_spacing = 2.0
    layer_motion = 1
    event_rate_per_layer_Hz = 1.5
    complexity = 0.45
    cross_layer_influence = 0

    state_pitch_span_octaves = 0.55
    mean_event_duration_s = 0.22
    coupling_strength = 0
    preset_name$ = "Sparse Independent Layers"

elsif preset = 3
    duration_s = 12
    number_of_layers = 4
    layer_layout = 1
    layer_spacing = 1.34
    layer_motion = 1
    event_rate_per_layer_Hz = 5.0
    complexity = 1.55
    cross_layer_influence = 1

    state_pitch_span_octaves = 0.82
    mean_event_duration_s = 0.20
    coupling_strength = 0.48
    preset_name$ = "Dense Coupled Weave"

elsif preset = 4
    duration_s = 14
    base_frequency_Hz = 55
    number_of_layers = 5
    layer_layout = 2
    layer_spacing = 1.5
    layer_motion = 1
    event_rate_per_layer_Hz = 3.0
    complexity = 0.80
    cross_layer_influence = 1

    state_pitch_span_octaves = 0.42
    mean_event_duration_s = 0.20
    coupling_strength = 0.28
    preset_name$ = "Harmonic Layer Stack"

elsif preset = 5
    duration_s = 12
    number_of_layers = 3
    layer_layout = 1
    layer_spacing = 3.0
    layer_motion = 1
    event_rate_per_layer_Hz = 2.5
    complexity = 1.0
    cross_layer_influence = 0

    state_pitch_span_octaves = 0.62
    mean_event_duration_s = 0.17
    preset_name$ = "Wide Geometric Spread"

elsif preset = 6
    duration_s = 14
    base_frequency_Hz = 100
    number_of_layers = 4
    layer_layout = 1
    layer_spacing = 1.75
    layer_motion = 2
    event_rate_per_layer_Hz = 4.0
    complexity = 1.20
    cross_layer_influence = 1

    state_pitch_span_octaves = 0.58
    mean_event_duration_s = 0.18
    coupling_strength = 0.42
    layer_motion_depth = 0.82
    preset_name$ = "Converging Layer Field"

elsif preset = 7
    duration_s = 14
    base_frequency_Hz = 95
    number_of_layers = 4
    layer_layout = 1
    layer_spacing = 1.48
    layer_motion = 3
    event_rate_per_layer_Hz = 2.8
    complexity = 0.85
    cross_layer_influence = 1

    state_pitch_span_octaves = 0.68
    mean_event_duration_s = 0.19
    coupling_strength = 0.30
    layer_motion_depth = 0.75
    preset_name$ = "Diverging Layer Field"
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_markov_texture_details
    beginPause: "Layered Markov Texture - Markov / Texture Details"
        real: "State pitch span (octaves)", state_pitch_span_octaves
        positive: "Mean event duration (s)", mean_event_duration_s
        real: "Event duration spread (0..0.9)", event_duration_spread
        real: "Frequency jitter (percent)", frequency_jitter_percent
        real: "Cross-layer coupling strength (0..1)", coupling_strength
        real: "Layer motion depth (0..1)", layer_motion_depth
        positive: "Rotation rate (Hz)", rotation_rate_Hz
        real: "Edge fade (s)", edge_fade_s
        integer: "Random seed (0 = unpredictable)", random_seed
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
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if number_of_layers < 1 or number_of_layers > 8
    exitScript: "Number of layers must be between 1 and 8."
endif
if layer_spacing < 1 or layer_spacing > 6
    exitScript: "Layer spacing must be between 1 and 6."
endif
if event_rate_per_layer_Hz <= 0 or event_rate_per_layer_Hz > 60
    exitScript: "Event rate per layer must be > 0 and <= 60 events/s."
endif
if complexity < 0 or complexity > 3
    exitScript: "Complexity must be between 0 and 3."
endif
if state_pitch_span_octaves < 0 or state_pitch_span_octaves > 3
    exitScript: "State pitch span must be between 0 and 3 octaves."
endif
if mean_event_duration_s <= 0 or mean_event_duration_s > 5
    exitScript: "Mean event duration must be > 0 and <= 5 seconds."
endif
if event_duration_spread < 0 or event_duration_spread > 0.9
    exitScript: "Event duration spread must be between 0 and 0.9."
endif
if frequency_jitter_percent < 0 or frequency_jitter_percent > 50
    exitScript: "Frequency jitter must be between 0 and 50 percent."
endif
if coupling_strength < 0 or coupling_strength > 1
    exitScript: "Coupling strength must be between 0 and 1."
endif
if layer_motion_depth < 0 or layer_motion_depth > 1
    exitScript: "Layer motion depth must be between 0 and 1."
endif
if rotation_rate_Hz <= 0 or rotation_rate_Hz > 5
    exitScript: "Rotation rate must be > 0 and <= 5 Hz."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

expectedEvents = duration_s*event_rate_per_layer_Hz*number_of_layers
if expectedEvents > 7000
    exitScript: "Expected event count exceeds 7000. Reduce duration, layers or event rate."
endif

if layer_layout = 1
    layout_name$ = "Geometric"
else
    layout_name$ = "Harmonic"
endif

if layer_motion = 1
    motion_name$ = "Stationary"
elsif layer_motion = 2
    motion_name$ = "Converging"
else
    motion_name$ = "Diverging"
endif

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "Layer Spread"
else
    spatial_name$ = "Rotating Layers"
endif

sr = sample_rate_Hz
safeTop = 0.45*sr
jitterFrac = frequency_jitter_percent/100

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
# LAYER-SPECIFIC PARAMETERS
# ---------------------------------------------------------------------------
numStates# = zero#(number_of_layers)
anchorStart# = zero#(number_of_layers)
anchorEnd# = zero#(number_of_layers)
mobility# = zero#(number_of_layers)
jumpProb# = zero#(number_of_layers)
upBias# = zero#(number_of_layers)
currentState# = zero#(number_of_layers)
nextTime# = zero#(number_of_layers)
layerEventCount# = zero#(number_of_layers)
layerTransitionCount# = zero#(number_of_layers)
layerChangeCount# = zero#(number_of_layers)
layerJumpCount# = zero#(number_of_layers)

logAnchorMean = 0

for layer from 1 to number_of_layers
    numStates#[layer] = 4+layer

    if layer_layout = 1
        anchorStart#[layer] =
            ... base_frequency_Hz*layer_spacing^(layer-1)
    else
        anchorStart#[layer] = base_frequency_Hz*layer
    endif

    logAnchorMean =
        ... logAnchorMean+ln(anchorStart#[layer])/number_of_layers
endfor

commonAnchor = exp(logAnchorMean)

for layer from 1 to number_of_layers
    if layer_motion = 1
        anchorEnd#[layer] = anchorStart#[layer]

    elsif layer_motion = 2
        anchorEnd#[layer] =
            ... exp(logAnchorMean+
            ... (1-layer_motion_depth)*
            ... (ln(anchorStart#[layer])-logAnchorMean))

    else
        anchorEnd#[layer] =
            ... exp(logAnchorMean+
            ... (1+layer_motion_depth)*
            ... (ln(anchorStart#[layer])-logAnchorMean))
    endif

    if number_of_layers = 1
        layerPos = 0.5
    else
        layerPos = (layer-1)/(number_of_layers-1)
    endif

    complexityNorm = complexity/(1+complexity)

    mobility#[layer] =
        ... min(0.82,max(0.10,
        ... 0.16+0.46*complexityNorm+0.08*layerPos))

    jumpProb#[layer] =
        ... min(0.20,max(0,
        ... 0.015+0.13*complexityNorm+0.025*layerPos))

    if jumpProb#[layer] > mobility#[layer]-0.04
        jumpProb#[layer] = max(0,mobility#[layer]-0.04)
    endif

    # Low layers have a slight downward tendency; high layers a slight upward
    # tendency. Coupling can override this at each transition.
    upBias#[layer] = 0.35+0.30*layerPos
endfor

# ---------------------------------------------------------------------------
# COMMON FREQUENCY HEADROOM SCALE
# ---------------------------------------------------------------------------
requestedTopFundamental = 0
requestedBottomFundamental = 1e12

for layer from 1 to number_of_layers
    layerTopAnchor = max(anchorStart#[layer],anchorEnd#[layer])
    layerBottomAnchor = min(anchorStart#[layer],anchorEnd#[layer])

    requestedTopFundamental =
        ... max(requestedTopFundamental,
        ... layerTopAnchor*2^(0.5*state_pitch_span_octaves)*
        ... (1+jitterFrac))

    requestedBottomFundamental =
        ... min(requestedBottomFundamental,
        ... layerBottomAnchor*2^(-0.5*state_pitch_span_octaves)*
        ... max(0.01,1-jitterFrac))
endfor

# Reserve headroom for the optional second harmonic.
frequencyScale = min(1,(safeTop/2)/requestedTopFundamental)

for layer from 1 to number_of_layers
    anchorStart#[layer] = anchorStart#[layer]*frequencyScale
    anchorEnd#[layer] = anchorEnd#[layer]*frequencyScale
endfor

effectiveBottom = requestedBottomFundamental*frequencyScale

if effectiveBottom < 20
    exitScript: "Requested layer geometry requires the lowest state below 20 Hz. Reduce span/spacing/layers or raise Base frequency."
endif

# ---------------------------------------------------------------------------
# INITIAL MARKOV / POISSON STATES
# ---------------------------------------------------------------------------
for layer from 1 to number_of_layers
    currentState#[layer] = randomInteger(1,numStates#[layer])

    u = max(1e-12,randomUniform(0,1))
    nextTime#[layer] =
        ... -ln(u)/event_rate_per_layer_Hz
endfor

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LAYERED MARKOV TEXTURE v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Layout / motion: ", layout_name$, " / ", motion_name$
appendInfoLine: "Target event rate per layer: ",
    ... fixed$(event_rate_per_layer_Hz,2), " events/s"
appendInfoLine: "Expected total events: ", fixed$(expectedEvents,1)
appendInfoLine: "Complexity: ", fixed$(complexity,3)
appendInfoLine: "Cross-layer influence: ", cross_layer_influence
appendInfoLine: "Coupling strength: ", fixed$(coupling_strength,3)
appendInfoLine: "State pitch span: ",
    ... fixed$(state_pitch_span_octaves,3), " octaves"
appendInfoLine: "Common frequency scale: ", fixed$(frequencyScale,5)
appendInfoLine: "Spatial mode: ", spatial_name$
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# GLOBAL CHRONOLOGICAL EVENT SCHEDULER
# ---------------------------------------------------------------------------
eventCount = 0
continueScheduling = 1
couplingDistanceSum = 0
couplingObservationCount = 0

while continueScheduling
    activeLayer = 0
    eventTimeNow = duration_s+1

    for layer from 1 to number_of_layers
        if nextTime#[layer] < eventTimeNow
            eventTimeNow = nextTime#[layer]
            activeLayer = layer
        endif
    endfor

    if activeLayer = 0 or eventTimeNow >= duration_s
        continueScheduling = 0

    else
        eventCount = eventCount+1

        if eventCount > 10000
            if seedWasFixed
                random_initializeSafelyAndUnpredictably ()
            endif
            exitScript: "Stochastic realization exceeded 10000 events."
        endif

        layer = activeLayer
        nStates = numStates#[layer]
        state = currentState#[layer]

        eventTime[eventCount] = eventTimeNow
        eventLayer[eventCount] = layer
        eventState[eventCount] = state
        layerEventCount#[layer] = layerEventCount#[layer]+1

        if nStates > 1
            statePos = (state-1)/(nStates-1)
        else
            statePos = 0.5
        endif

        timeNorm = eventTimeNow/duration_s
        anchorNow =
            ... exp(ln(anchorStart#[layer])+
            ... timeNorm*(ln(anchorEnd#[layer])-ln(anchorStart#[layer])))

        eventFreq[eventCount] =
            ... anchorNow*
            ... 2^(state_pitch_span_octaves*(statePos-0.5))*
            ... (1+randomUniform(-jitterFrac,jitterFrac))

        eventFreq[eventCount] =
            ... max(20,min(safeTop/2,eventFreq[eventCount]))

        stateDurFactor = 0.65+0.70*statePos
        eventDur[eventCount] =
            ... mean_event_duration_s*stateDurFactor*
            ... randomUniform(1-event_duration_spread,
            ... 1+event_duration_spread)

        eventDur[eventCount] =
            ... max(2/sr,min(eventDur[eventCount],
            ... duration_s-eventTimeNow))

        eventAmp[eventCount] =
            ... (0.72+0.28*statePos)*randomUniform(0.88,1.12)

        eventBrightness[eventCount] = 0.12+0.42*statePos
        eventPhase[eventCount] = 2*pi*randomUniform(0,1)

        # ------------------------------------------------------
        # EVENT-LEVEL SPATIAL POSITION
        # ------------------------------------------------------
        if spatial_mode = 1
            eventPan[eventCount] = 0.5

        elsif spatial_mode = 2
            if number_of_layers = 1
                eventPan[eventCount] = 0.5
            else
                eventPan[eventCount] =
                    ... 0.05+0.90*(layer-1)/(number_of_layers-1)
            endif

        else
            layerPhase =
                ... 2*pi*(layer-1)/number_of_layers
            eventPan[eventCount] =
                ... 0.5+0.46*sin(2*pi*rotation_rate_Hz*
                ... eventTimeNow+layerPhase)
        endif

        # ------------------------------------------------------
        # TRUE CROSS-LAYER STATE INFLUENCE
        # ------------------------------------------------------
        currentNorm =
            ... (state-1)/(nStates-1)

        if number_of_layers > 1
            ensembleSum = 0
            ensembleCount = 0

            for other from 1 to number_of_layers
                if other <> layer
                    otherNorm =
                        ... (currentState#[other]-1)/
                        ... (numStates#[other]-1)
                    ensembleSum = ensembleSum+otherNorm
                    ensembleCount = ensembleCount+1
                endif
            endfor

            ensembleMean = ensembleSum/ensembleCount
            couplingDistanceSum =
                ... couplingDistanceSum+
                ... abs(currentNorm-ensembleMean)
            couplingObservationCount =
                ... couplingObservationCount+1

        else
            ensembleMean = currentNorm
        endif

        bias = upBias#[layer]

        if cross_layer_influence and number_of_layers > 1
            bias =
                ... bias+coupling_strength*
                ... (ensembleMean-currentNorm)
        endif

        bias = max(0.08,min(0.92,bias))

        mobilityNow = mobility#[layer]
        jumpNow = jumpProb#[layer]
        neighborNow = mobilityNow-jumpNow

        pPrev = neighborNow*(1-bias)
        pNext = neighborNow*bias
        pStay = 1-mobilityNow

        r = randomUniform(0,1)
        oldState = state
        didJump = 0

        if r < pStay
            newState = state

        elsif r < pStay+pPrev
            newState = state-1
            if newState < 1
                newState = min(nStates,2)
            endif

        elsif r < pStay+pPrev+pNext
            newState = state+1
            if newState > nStates
                newState = max(1,nStates-1)
            endif

        else
            # Jump explicitly excludes the current state.
            jumpIndex = randomInteger(1,nStates-1)
            if jumpIndex >= state
                jumpIndex = jumpIndex+1
            endif
            newState = jumpIndex
            didJump = 1
        endif

        layerTransitionCount#[layer] =
            ... layerTransitionCount#[layer]+1

        if newState <> oldState
            layerChangeCount#[layer] =
                ... layerChangeCount#[layer]+1
        endif

        if didJump
            layerJumpCount#[layer] =
                ... layerJumpCount#[layer]+1
        endif

        currentState#[layer] = newState

        # Schedule next event for this layer using a genuine Poisson clock.
        u = max(1e-12,randomUniform(0,1))
        nextTime#[layer] =
            ... eventTimeNow-ln(u)/event_rate_per_layer_Hz
    endif
endwhile

if eventCount < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "This realization produced no events. Increase duration/event rate or change seed."
endif

# ---------------------------------------------------------------------------
# REALIZATION QC / ENERGY COMPENSATION
# ---------------------------------------------------------------------------
totalEventDuration = 0
minActualFreq = 1e12
maxActualFreq = 0

for ev from 1 to eventCount
    totalEventDuration =
        ... totalEventDuration+eventDur[ev]
    minActualFreq =
        ... min(minActualFreq,eventFreq[ev])
    maxActualFreq =
        ... max(maxActualFreq,eventFreq[ev])
endfor

overlapLoad = totalEventDuration/duration_s
eventGain = 0.48/sqrt(max(1,overlapLoad))
realizedTotalRate = eventCount/duration_s

if couplingObservationCount > 0
    meanStateDisagreement =
        ... couplingDistanceSum/couplingObservationCount
else
    meanStateDisagreement = 0
endif

empiricalMobility# = zero#(number_of_layers)
empiricalJump# = zero#(number_of_layers)
realizedLayerRate# = zero#(number_of_layers)

for layer from 1 to number_of_layers
    realizedLayerRate#[layer] =
        ... layerEventCount#[layer]/duration_s

    if layerTransitionCount#[layer] > 0
        empiricalMobility#[layer] =
            ... layerChangeCount#[layer]/
            ... layerTransitionCount#[layer]

        empiricalJump#[layer] =
            ... layerJumpCount#[layer]/
            ... layerTransitionCount#[layer]
    endif
endfor

appendInfoLine: "Actual total events: ", eventCount
appendInfoLine: "Actual total event rate: ",
    ... fixed$(realizedTotalRate,2), " events/s"
appendInfoLine: "Overlap load (sum event durations / duration): ",
    ... fixed$(overlapLoad,3)
appendInfoLine: "Event gain after overlap compensation: ",
    ... fixed$(eventGain,4)
appendInfoLine: "Mean normalized state disagreement: ",
    ... fixed$(meanStateDisagreement,4)
appendInfoLine: ""

for layer from 1 to number_of_layers
    appendInfoLine: "Layer ", layer,
        ... ": states=", numStates#[layer],
        ... "  rate=", fixed$(realizedLayerRate#[layer],2),
        ... "  expected mobility=", fixed$(mobility#[layer],3),
        ... "  empirical=", fixed$(empiricalMobility#[layer],3)
endfor

# ---------------------------------------------------------------------------
# OUTPUT BUFFER
# ---------------------------------------------------------------------------
if spatial_mode = 1
    channelCount = 1
else
    channelCount = 2
endif

outputSound = Create Sound from formula:
    ... "layered_markov_" + uid$,
    ... channelCount,0,duration_s,sr,"0"

# ---------------------------------------------------------------------------
# EVENT RENDER
# ---------------------------------------------------------------------------
appendInfoLine: ""
appendInfoLine: "Rendering events..."

for ev from 1 to eventCount
    t0 = eventTime[ev]
    td = eventDur[ev]
    t1 = min(duration_s,t0+td)

    if t1 > t0
        age$ = "(x-" + fixed$(t0,9) + ")"
        dur$ = fixed$(td,9)
        f = eventFreq[ev]
        h2 = eventBrightness[ev]

        # Approximate RMS normalization of 1 + h2 second-harmonic source.
        sourceNorm = sqrt(2)/sqrt(1+h2*h2)

        wave$ = fixed$(sourceNorm,9)
            ... + "*sin(2*pi*" + fixed$(f,6)
            ... + "*" + age$ + "+"
            ... + fixed$(eventPhase[ev],9) + ")"

        if 2*f <= safeTop
            wave$ = "(" + wave$ + "+"
                ... + fixed$(sourceNorm*h2,9)
                ... + "*sin(2*pi*" + fixed$(2*f,6)
                ... + "*" + age$ + "+"
                ... + fixed$(2*eventPhase[ev],9) + "))"
        endif

        env$ =
            ... "(0.5-0.5*cos(2*pi*" + age$
            ... + "/" + dur$ + "))"

        amp =
            ... eventGain*eventAmp[ev]

        selectObject: outputSound

        if channelCount = 1
            Formula (part): t0,t1,1,1,
                ... "self+" + fixed$(amp,9)
                ... + "*(" + wave$ + ")*" + env$

        else
            pan = eventPan[ev]
            gL = sqrt(max(0,1-pan))
            gR = sqrt(max(0,pan))

            Formula (part): t0,t1,1,2,
                ... "self+if row=1 then "
                ... + fixed$(amp*gL,9)
                ... + "*(" + wave$ + ")*" + env$
                ... + " else "
                ... + fixed$(amp*gR,9)
                ... + "*(" + wave$ + ")*" + env$ + " fi"
        endif
    endif
endfor

# ---------------------------------------------------------------------------
# COMMON EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)

if actualFade > 0
    fadeOutStart = duration_s-actualFade

    selectObject: outputSound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

safePreset$ = replace$(preset_name$," ","_",0)
Rename: "Layered_Markov_" + safePreset$
outputSound = selected("Sound")

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

appendInfoLine: ""
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# PLAY
# ---------------------------------------------------------------------------
selectObject: outputSound
if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.82
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.78,0.42,0.18}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "LAYERED MARKOV TEXTURE | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.68
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... string$(number_of_layers) + " layers | "
        ... + layout_name$ + " / " + motion_name$
        ... + " | target " + fixed$(event_rate_per_layer_Hz,2)
        ... + " events/s/layer"
    if cross_layer_influence
        .couplingLabel$ =
            ... "coupled state decisions, strength "
            ... + fixed$(coupling_strength,2)
    else
        .couplingLabel$ = "independent state decisions"
    endif
    Text: 0.5,"centre",0.20,"half",
        ... "Poisson clocks -> layer-specific Markov kernels -> "
        ... + .couplingLabel$ + " -> event field"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL STATE REALIZATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.78,1.00
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  REALIZED MARKOV STATES | normalized state position inside each layer lane"

    Select inner viewport: .left,.right,1.07,2.14
    Axes: 0,duration_s,0.5,number_of_layers+0.5
    Paint rectangle: .bg$,0,duration_s,0.5,number_of_layers+0.5

    Colour: .grid$
    Dotted line
    for .layer from 1 to number_of_layers
        Draw line: 0,.layer,duration_s,.layer
    endfor
    Plain line

    .eventStep = max(1,ceiling(eventCount/1800))

    for .ev from 1 to eventCount
        if ((.ev-1) mod .eventStep)=0
            .layer = eventLayer[.ev]
            .n = numStates#[.layer]
            .stateNorm =
                ... (eventState[.ev]-1)/(.n-1)

            .y = .layer-0.30+0.60*.stateNorm

            .h = (.layer-1)/max(1,number_of_layers-1)
            .r = 0.18+0.62*.h
            .g = 0.53-0.25*.h
            .b = 0.80-0.47*.h
            .col$ = "{" + fixed$(.r,3) + ","
                ... + fixed$(.g,3) + "," + fixed$(.b,3) + "}"

            Paint circle (mm): .col$,
                ... eventTime[.ev],.y,0.75
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: min(number_of_layers,8),"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Layer"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL EVENT-FREQUENCY FIELD
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.30,2.52
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  ACTUAL EVENT FIELD | onset, duration and frequency from the coupled realization"

    .logLo = ln(max(20,0.88*minActualFreq))
    .logHi = ln(min(safeTop,max(600,1.12*maxActualFreq)))
    if .logHi <= .logLo
        .logHi = .logLo+0.5
    endif

    Select inner viewport: .left,.right,2.59,3.62
    Axes: 0,duration_s,.logLo,.logHi
    Paint rectangle: "{0.055,0.055,0.065}",
        ... 0,duration_s,.logLo,.logHi

    for .ev from 1 to eventCount
        if ((.ev-1) mod .eventStep)=0
            .layer = eventLayer[.ev]
            .h = (.layer-1)/max(1,number_of_layers-1)
            .r = 0.18+0.62*.h
            .g = 0.53-0.25*.h
            .b = 0.80-0.47*.h
            .col$ = "{" + fixed$(.r,3) + ","
                ... + fixed$(.g,3) + "," + fixed$(.b,3) + "}"

            Colour: .col$
            Draw line:
                ... eventTime[.ev],ln(eventFreq[.ev]),
                ... min(duration_s,eventTime[.ev]+eventDur[.ev]),
                ... ln(eventFreq[.ev])
        endif
    endfor

    Colour: "White"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"

    Font size: 5
    .tick# = {50,100,200,500,1000,2000,5000,10000}
    for .k from 1 to 8
        .ff = .tick#[.k]

        if .ff >= exp(.logLo) and .ff <= exp(.logHi)
            Colour: "{0.55,0.55,0.58}"
            Draw line:
                ... 0,ln(.ff),0.012*duration_s,ln(.ff)

            Colour: "White"
            if .ff >= 1000
                .lab$ = fixed$(.ff/1000,0) + "k"
            else
                .lab$ = fixed$(.ff,0)
            endif
            Text: -0.012*duration_s,"right",
                ... ln(.ff),"half",.lab$
        endif
    endfor

    # -----------------------------------------------------------------------
    # PANEL C: TRANSITION / COUPLING DIAGNOSTICS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.78,4.00
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  LAYER TRANSITIONS | expected mobility vs empirical state changes"

    Select inner viewport: .left,.right,4.07,5.02
    Axes: 0.5,number_of_layers+0.5,0,1
    Paint rectangle: .bg$,
        ... 0.5,number_of_layers+0.5,0,1

    Colour: .grid$
    Dotted line
    Draw line: 0.5,0.25,number_of_layers+0.5,0.25
    Draw line: 0.5,0.50,number_of_layers+0.5,0.50
    Draw line: 0.5,0.75,number_of_layers+0.5,0.75
    Plain line

    for .layer from 1 to number_of_layers
        Colour: .blue$
        Draw line:
            ... .layer-0.15,mobility#[.layer],
            ... .layer+0.15,mobility#[.layer]

        Colour: .orange$
        Paint circle (mm): .orange$,
            ... .layer,empiricalMobility#[.layer],1.0
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 5,"yes","yes","no"
    Marks bottom every: 1,1,"yes","yes","no"
    Font size: 6
    Text left: "yes","Transition probability"
    Font size: 5
    Text: 0.65,"left",0.93,"half",
        ... "blue = expected mobility   orange = empirical state change"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "layered_markov_display_" + uid$
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
    Select inner viewport: 0.35,7.65,5.18,5.40
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + sampled event guides"

    .specMax = min(safeTop,max(1800,2.15*maxActualFreq))
    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.47,6.50
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: "{0.18,0.54,0.82}"
    Line width: 0.7

    .guideStep = max(1,ceiling(eventCount/220))
    for .ev from 1 to eventCount
        if ((.ev-1) mod .guideStep)=0 and
            ... eventFreq[.ev] <= .specMax

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
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.72,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.79,"half",
        ... "EVENTS  |  expected " + fixed$(expectedEvents,1)
        ... + "  |  actual " + string$(eventCount)
        ... + "  |  total rate " + fixed$(realizedTotalRate,2) + "/s"
        ... + "  |  overlap load " + fixed$(overlapLoad,2)

    if cross_layer_influence and number_of_layers > 1
        .couplingText$ =
            ... "active; mean state disagreement "
            ... + fixed$(meanStateDisagreement,3)
    else
        .couplingText$ = "off"
    endif

    Text: 0.02,"left",0.57,"half",
        ... "MARKOV  |  complexity " + fixed$(complexity,2)
        ... + "  |  coupling " + .couplingText$

    Text: 0.02,"left",0.35,"half",
        ... "SPECTRUM  |  actual F " + fixed$(minActualFreq,0)
        ... + "-" + fixed$(maxActualFreq,0) + " Hz"
        ... + "  |  layout " + layout_name$
        ... + "  |  motion " + motion_name$
        ... + "  |  scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.13,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  pre-RMS " + fixed$(preProtectRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
