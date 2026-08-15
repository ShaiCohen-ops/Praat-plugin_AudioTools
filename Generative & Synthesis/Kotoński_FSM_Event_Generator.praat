# ============================================================
# Praat AudioTools - Kotonski_FSM_Event_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 conceptual + DSP review (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# KOTONSKI-INSPIRED FINITE-STATE EVENT GENERATOR
#
# CONCEPTUAL SCOPE
# ----------------
# This is NOT a reconstruction of Wlodzimierz Kotonski's compositional method.
# It is an engine-specific finite-state event controller informed by three
# historically documented strategies in his electroacoustic work:
#
#   1. Study on One Cymbal Stroke / Concrete Etude (1959)
#      One recorded cymbal source was transformed and organized within a
#      rigorously planned parameter structure. Published descriptions discuss
#      systematic filtering/transposition and serially organized parameter
#      scales. This engine cannot recreate that concrete source process, so its
#      "Etude-inspired" preset uses an explicit synthetic 11-level parameter
#      grid as a STRUCTURAL ANALOGY only.
#
#   2. Microstructures (1963)
#      Recorded impacts on glass, wood and metal were cut into small fragments,
#      arranged in chance sequences and made into loops/layers. The present
#      preset does not imitate those recordings; it uses short synthetic
#      tone/noise/metallic fragments and overlapping montage as an abstraction
#      of fragment organization.
#
#   3. Aela (1970)
#      Aela is an aleatoric electronic framework / "family of electronic
#      pieces". Its material is described as simple tones drawn from an
#      arithmetic frequency scale with 25-Hz spacing. The Aela-inspired preset
#      therefore uses ONLY sine tones, quantized to a 25-Hz grid, inside an
#      aleatoric state graph. It does not claim to reproduce a specific Aela
#      realization.
#
# FINITE-STATE MODEL
# ------------------
# Four engine states control event duration, onset interval, register and
# material tendency:
#
#   State 1  Sparse points
#   State 2  Sustained bands
#   State 3  Micro-fragments
#   State 4  Dense field
#
# A state is retained for State_hold_events, then a transition is chosen by one
# of four explicit controllers:
#
#   Cycle
#   Palindrome
#   Adjacent aleatoric
#   Directed aleatoric graph
#
# This is therefore a finite-state EVENT CONTROLLER. The two aleatoric modes
# are finite-state stochastic processes rather than deterministic automata.
#
# TEMPORAL MODEL
# --------------
# Event onset interval (IOI) and event duration are independent. Therefore
# events may overlap. The raw event realization is finally scaled ONCE so that
# the latest event end coincides with Duration_s. This preserves the relative
# overlap structure while guaranteeing exact requested duration.
#
# AUDIO MATERIAL
# --------------
#   Tone              sine event
#   Noise band        local white-noise fragment through Hann pass-band filter
#   Metallic transient three inharmonic decaying sinusoids
#   Mixed             stochastic selection among the above
#
# v1.5 changes
# ------------
#   - Removed misleading "Aela I-V" labels.
#   - Added historically grounded Etude-, Microstructures- and Aela-inspired
#     presets while clearly distinguishing analogy from reconstruction.
#   - Replaced the scheduled four-quartile "FSM" with explicit state memory and
#     transition rules.
#   - Removed the broken Hybrid mode (v1.4's Hybrid executed only event-based
#     transitions).
#   - Aela-inspired mode now uses pure sine tones on a genuine 25-Hz grid.
#   - Etude-inspired mode uses independent 11-level pitch/duration/amplitude
#     grids + six articulation classes as an engine-specific serial analogy.
#   - Event IOI is independent of duration, so dense states can actually overlap.
#   - Added Random_seed and reproducible state/event/noise realization.
#   - Log-frequency mapping with strict range clamps; no negative center
#     frequencies or out-of-range tone frequencies.
#   - Common frequency scaling for general presets; Aela preserves 25-Hz spacing
#     and truncates the upper grid at the safe sampling limit instead.
#   - Safe attack/release for short events.
#   - Efficient rendering: tones/metallic events render directly into the local
#     master region; noise events use only a local-duration temporary Sound.
#     No event Sound extends from time zero to its absolute end time.
#   - Optional event-level equal-power stereo.
#   - Density/overlap energy compensation.
#   - Global amplitude preserved; final peak protection is down-only.
#   - Visualization rebuilt around the mechanism:
#       A realized state trajectory
#       B actual log-frequency event field
#       C empirical state-transition decision matrix
#       D measured spectrogram + event guides
#       conceptual / overlap / sampling / output QC
#   - Removed the unverified painter/color quotation from the output.
#
# Historical references used for this review:
#   Polish Music Information Centre / POLMIC
#   MoMA post: Polish Radio Experimental Studio score archive
#   Map of Polish Composers
#   UNT Music Library metadata for Microstructures
# ============================================================

form Kotonski-Inspired State-Event Generator v1.5
    optionmenu Preset 1
        option Etude-inspired Serial Parameter Field
        option Microstructures-inspired Fragment Montage
        option Aela-inspired 25-Hz Sine Field
        option Sparse Point Field
        option Dense Mixed State Field
        option Custom Finite-State Field

    positive Duration_s 40
    integer Sample_rate_Hz 44100
    integer Num_events 140
    real Global_amplitude 0.60

    optionmenu Transition_logic 1
        option Cycle
        option Palindrome
        option Adjacent aleatoric
        option Directed aleatoric graph

    integer State_hold_events 8

    optionmenu Spatial_mode 1
        option Mono
        option Event Spread
        option State Positions

    boolean Edit_state_sound_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
frequency_min_Hz = 100
frequency_max_Hz = 8000
density_multiplier = 1.0
attack_ms = 6
release_ms = 10
noise_bandwidth_Hz = 900
random_seed = 0

# material code: 1 tone, 2 noise band, 3 metallic transient, 4 mixed
state1_type = 1
state2_type = 2
state3_type = 3
state4_type = 4

# internal preset flags
serial_grid_mode = 0
microstructure_mode = 0
aela_mode = 0

preset_name$ = "Custom Finite-State Field"

# ---------------------------------------------------------------------------
# PRESET OVERRIDES
# ---------------------------------------------------------------------------
if preset = 1
    duration_s = 32
    num_events = 121
    global_amplitude = 0.58
    transition_logic = 1
    state_hold_events = 11

    frequency_min_Hz = 120
    frequency_max_Hz = 6500
    density_multiplier = 0.92
    attack_ms = 4
    release_ms = 10
    noise_bandwidth_Hz = 700

    state1_type = 4
    state2_type = 4
    state3_type = 4
    state4_type = 4

    serial_grid_mode = 1
    preset_name$ = "Etude-inspired Serial Parameter Field"

elsif preset = 2
    duration_s = 36
    num_events = 260
    global_amplitude = 0.52
    transition_logic = 3
    state_hold_events = 3

    frequency_min_Hz = 100
    frequency_max_Hz = 9000
    density_multiplier = 0.55
    attack_ms = 2
    release_ms = 8
    noise_bandwidth_Hz = 1500

    state1_type = 3
    state2_type = 2
    state3_type = 4
    state4_type = 4

    microstructure_mode = 1
    preset_name$ = "Microstructures-inspired Fragment Montage"

elsif preset = 3
    duration_s = 36
    num_events = 190
    global_amplitude = 0.50
    transition_logic = 4
    state_hold_events = 1

    frequency_min_Hz = 25
    frequency_max_Hz = 10000
    density_multiplier = 0.90
    attack_ms = 4
    release_ms = 12
    noise_bandwidth_Hz = 500

    state1_type = 1
    state2_type = 1
    state3_type = 1
    state4_type = 1

    aela_mode = 1
    preset_name$ = "Aela-inspired 25-Hz Sine Field"

elsif preset = 4
    duration_s = 50
    num_events = 90
    global_amplitude = 0.56
    transition_logic = 1
    state_hold_events = 12

    frequency_min_Hz = 700
    frequency_max_Hz = 6500
    density_multiplier = 1.25
    attack_ms = 3
    release_ms = 6
    noise_bandwidth_Hz = 500

    state1_type = 1
    state2_type = 1
    state3_type = 3
    state4_type = 4

    preset_name$ = "Sparse Point Field"

elsif preset = 5
    duration_s = 34
    num_events = 320
    global_amplitude = 0.46
    transition_logic = 3
    state_hold_events = 2

    frequency_min_Hz = 180
    frequency_max_Hz = 8500
    density_multiplier = 0.46
    attack_ms = 2
    release_ms = 6
    noise_bandwidth_Hz = 1200

    state1_type = 4
    state2_type = 2
    state3_type = 4
    state4_type = 4

    preset_name$ = "Dense Mixed State Field"

else
    preset_name$ = "Custom Finite-State Field"
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_state_sound_details
    beginPause: "Kotonski-Inspired Generator - State / Sound Details"
        positive: "Frequency minimum (Hz)", frequency_min_Hz
        positive: "Frequency maximum (Hz)", frequency_max_Hz
        positive: "IOI density multiplier", density_multiplier
        positive: "Attack (ms)", attack_ms
        positive: "Release (ms)", release_ms
        positive: "Nominal noise bandwidth (Hz)", noise_bandwidth_Hz
        integer: "Random seed (0 = unpredictable)", random_seed
        integer: "State 1 material (1 tone, 2 noise, 3 metallic, 4 mixed)", state1_type
        integer: "State 2 material (1 tone, 2 noise, 3 metallic, 4 mixed)", state2_type
        integer: "State 3 material (1 tone, 2 noise, 3 metallic, 4 mixed)", state3_type
        integer: "State 4 material (1 tone, 2 noise, 3 metallic, 4 mixed)", state4_type
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
if num_events < 2 or num_events > 4000
    exitScript: "Number of events must be between 2 and 4000."
endif
if global_amplitude <= 0 or global_amplitude > 2
    exitScript: "Global amplitude must be > 0 and <= 2."
endif
if state_hold_events < 1 or state_hold_events > num_events
    exitScript: "State hold events must be >= 1 and <= number of events."
endif
if frequency_min_Hz <= 0 or frequency_max_Hz <= frequency_min_Hz
    exitScript: "Frequency range must satisfy 0 < minimum < maximum."
endif
if density_multiplier <= 0 or density_multiplier > 10
    exitScript: "IOI density multiplier must be > 0 and <= 10."
endif
if attack_ms <= 0 or release_ms <= 0
    exitScript: "Attack and release must be greater than zero."
endif
if noise_bandwidth_Hz <= 0
    exitScript: "Noise bandwidth must be greater than zero."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

for s from 1 to 4
    if s = 1
        tt = state1_type
    elsif s = 2
        tt = state2_type
    elsif s = 3
        tt = state3_type
    else
        tt = state4_type
    endif

    if tt < 1 or tt > 4
        exitScript: "Every state material code must be 1, 2, 3 or 4."
    endif
endfor

if transition_logic = 1
    transition_name$ = "Cycle"
elsif transition_logic = 2
    transition_name$ = "Palindrome"
elsif transition_logic = 3
    transition_name$ = "Adjacent aleatoric"
else
    transition_name$ = "Directed aleatoric graph"
endif

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "Event Spread"
else
    spatial_name$ = "State Positions"
endif

sr = sample_rate_Hz
safeTop = 0.45*sr
n_events = num_events
total_dur = duration_s
global_amp = global_amplitude
attack_t = attack_ms/1000
release_t = release_ms/1000

# ---------------------------------------------------------------------------
# FREQUENCY SAFETY
# ---------------------------------------------------------------------------
frequency_scale = 1

if aela_mode
    effective_min_Hz = max(25,frequency_min_Hz)
    effective_max_Hz = min(frequency_max_Hz,safeTop)
    if effective_max_Hz < 50
        exitScript: "Sample rate is too low for the requested Aela-inspired grid."
    endif
else
    frequency_scale = min(1,safeTop/frequency_max_Hz)
    effective_min_Hz = frequency_min_Hz*frequency_scale
    effective_max_Hz = frequency_max_Hz*frequency_scale

    if effective_min_Hz < 20
        exitScript: "Sampling-headroom scaling would move the lower frequency below 20 Hz."
    endif
endif

# Metallic transient contains ratios up to 2.13.
metalSafeTop = safeTop/2.13

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
# EVENT ARRAYS / STATE DATA
# ---------------------------------------------------------------------------
startTime# = zero#(n_events)
dur# = zero#(n_events)
ioi# = zero#(n_events)
amp# = zero#(n_events)
type# = zero#(n_events)
freq# = zero#(n_events)
bandwidth# = zero#(n_events)
state# = zero#(n_events)
pan# = zero#(n_events)
articulation# = zero#(n_events)

stateType# = zero#(4)
stateType#[1] = state1_type
stateType#[2] = state2_type
stateType#[3] = state3_type
stateType#[4] = state4_type

stateCount# = zero#(4)
transitionCount## = zero##(4,4)
transitionDecisionCount = 0

# ---------------------------------------------------------------------------
# PROCEDURE: MATERIAL TYPE
# ---------------------------------------------------------------------------
procedure chooseMaterial: .preference
    if .preference = 1
        .result = 1
    elsif .preference = 2
        .result = 2
    elsif .preference = 3
        .result = 3
    else
        .r = randomUniform(0,1)
        if .r < 0.44
            .result = 1
        elsif .r < 0.78
            .result = 2
        else
            .result = 3
        endif
    endif
endproc

# ---------------------------------------------------------------------------
# PROCEDURE: NEXT STATE
# ---------------------------------------------------------------------------
procedure chooseNextState: .logic,.current,.direction

    .next = .current
    .newDirection = .direction

    if .logic = 1
        .next = .current+1
        if .next > 4
            .next = 1
        endif

    elsif .logic = 2
        .next = .current+.direction

        if .next >= 4
            .next = 4
            .newDirection = -1
        elsif .next <= 1
            .next = 1
            .newDirection = 1
        endif

    elsif .logic = 3
        .r = randomUniform(0,1)

        if .r < 0.30
            .next = .current

        elsif .r < 0.65
            .next = .current-1
            if .next < 1
                .next = 2
            endif

        else
            .next = .current+1
            if .next > 4
                .next = 3
            endif
        endif

    else
        # Directed graph:
        # state 1 -> 1/2/3/4 = .20/.50/.20/.10
        # state 2 ->             .20/.20/.45/.15
        # state 3 ->             .15/.25/.20/.40
        # state 4 ->             .45/.15/.20/.20
        .r = randomUniform(0,1)

        if .current = 1
            if .r < 0.20
                .next = 1
            elsif .r < 0.70
                .next = 2
            elsif .r < 0.90
                .next = 3
            else
                .next = 4
            endif

        elsif .current = 2
            if .r < 0.20
                .next = 1
            elsif .r < 0.40
                .next = 2
            elsif .r < 0.85
                .next = 3
            else
                .next = 4
            endif

        elsif .current = 3
            if .r < 0.15
                .next = 1
            elsif .r < 0.40
                .next = 2
            elsif .r < 0.60
                .next = 3
            else
                .next = 4
            endif

        else
            if .r < 0.45
                .next = 1
            elsif .r < 0.60
                .next = 2
            elsif .r < 0.80
                .next = 3
            else
                .next = 4
            endif
        endif
    endif
endproc

# ---------------------------------------------------------------------------
# EVENT REALIZATION
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  KOTONSKI-INSPIRED STATE-EVENT GENERATOR v1.5"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Scope: finite-state study / historical analogy, NOT reconstruction"
appendInfoLine: "Duration: ", fixed$(total_dur,2), " s"
appendInfoLine: "Events: ", n_events
appendInfoLine: "Transition controller: ", transition_name$
appendInfoLine: "State hold: ", state_hold_events, " event(s)"
appendInfoLine: "Spatial mode: ", spatial_name$
appendInfoLine: "Frequency range used: ",
    ... fixed$(effective_min_Hz,1), " - ",
    ... fixed$(effective_max_Hz,1), " Hz"
if aela_mode
    appendInfoLine: "Aela-inspired grid: 25-Hz arithmetic spacing preserved"
else
    appendInfoLine: "Common frequency scale: ", fixed$(frequency_scale,5)
endif
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""
appendInfoLine: "Generating event/state realization..."

current_state = 1
state_direction = 1
events_in_state = 0
rawTime = 0
rawLatestEnd = 0

for i from 1 to n_events

    state#[i] = current_state
    stateCount#[current_state] = stateCount#[current_state]+1

    # ----------------------------------------------------------
    # STATE CHARACTER
    # ----------------------------------------------------------
    if current_state = 1
        dMin = 0.018
        dMax = 0.070
        ioiMin = 0.18
        ioiMax = 0.55
        regCenter = 0.78
        regSpread = 0.18
        ampMin = 0.38
        ampMax = 0.72

    elsif current_state = 2
        dMin = 0.12
        dMax = 0.35
        ioiMin = 0.09
        ioiMax = 0.24
        regCenter = 0.26
        regSpread = 0.23
        ampMin = 0.42
        ampMax = 0.80

    elsif current_state = 3
        dMin = 0.012
        dMax = 0.050
        ioiMin = 0.025
        ioiMax = 0.095
        regCenter = 0.68
        regSpread = 0.28
        ampMin = 0.30
        ampMax = 0.64

    else
        dMin = 0.080
        dMax = 0.240
        ioiMin = 0.030
        ioiMax = 0.110
        regCenter = 0.46
        regSpread = 0.45
        ampMin = 0.36
        ampMax = 0.76
    endif

    # ----------------------------------------------------------
    # ENGINE-SPECIFIC SERIAL PARAMETER ANALOGY
    # ----------------------------------------------------------
    if serial_grid_mode
        pitchIndex = ((7*(i-1)) mod 11)+1
        durIndex = ((3*(i-1)+2) mod 11)+1
        ampIndex = ((5*(i-1)+4) mod 11)+1
        articulationIndex = ((5*(i-1)) mod 6)+1

        pos = (pitchIndex-1)/10
        dur#[i] = dMin+(dMax-dMin)*(durIndex-1)/10
        amp#[i] = ampMin+(ampMax-ampMin)*(ampIndex-1)/10
        articulation#[i] = articulationIndex

        # Six articulation classes are mapped to three synthetic source classes
        # plus envelope tendency. This is an engine analogy, not Kotoński's
        # historical articulation table.
        if articulationIndex <= 2
            type#[i] = 1
        elsif articulationIndex <= 4
            type#[i] = 2
        else
            type#[i] = 3
        endif

        ioi#[i] =
            ... density_multiplier*(ioiMin+(ioiMax-ioiMin)*
            ... (((2*(i-1)+3) mod 11)/10))

    else
        pos = regCenter+randomUniform(-regSpread,regSpread)
        pos = max(0,min(1,pos))

        dur#[i] = randomUniform(dMin,dMax)
        ioi#[i] = density_multiplier*randomUniform(ioiMin,ioiMax)
        amp#[i] = randomUniform(ampMin,ampMax)
        articulation#[i] = randomInteger(1,6)

        if aela_mode
            type#[i] = 1
        else
            @chooseMaterial: stateType#[current_state]
            type#[i] = chooseMaterial.result
        endif
    endif

    # Microstructures-inspired montage: shorten selected fragments and increase
    # overlap variability, while retaining the same explicit state controller.
    if microstructure_mode
        if randomUniform(0,1) < 0.45
            dur#[i] = dur#[i]*randomUniform(0.35,0.75)
        endif
        ioi#[i] = ioi#[i]*randomUniform(0.55,1.15)
    endif

    # ----------------------------------------------------------
    # FREQUENCY
    # ----------------------------------------------------------
    if aela_mode
        rawF =
            ... effective_min_Hz*
            ... (effective_max_Hz/effective_min_Hz)^pos
        f = 25*round(rawF/25)
        f = max(25,min(effective_max_Hz,f))

    else
        f =
            ... effective_min_Hz*
            ... (effective_max_Hz/effective_min_Hz)^pos
        f = max(effective_min_Hz,min(effective_max_Hz,f))
    endif

    if type#[i] = 3
        f = min(f,metalSafeTop)
    endif

    freq#[i] = f

    bwFactor = randomUniform(0.65,1.35)
    bandwidth#[i] = noise_bandwidth_Hz*bwFactor

    # ----------------------------------------------------------
    # SPATIAL POSITION
    # ----------------------------------------------------------
    if spatial_mode = 1
        pan#[i] = 0.5

    elsif spatial_mode = 2
        pan#[i] = randomUniform(0.04,0.96)

    else
        if current_state = 1
            pan#[i] = 0.08
        elsif current_state = 2
            pan#[i] = 0.36
        elsif current_state = 3
            pan#[i] = 0.64
        else
            pan#[i] = 0.92
        endif
    endif

    startTime#[i] = rawTime
    rawLatestEnd = max(rawLatestEnd,rawTime+dur#[i])

    if i < n_events
        rawTime = rawTime+ioi#[i]
    endif

    # ----------------------------------------------------------
    # STATE DECISION
    # ----------------------------------------------------------
    events_in_state = events_in_state+1

    if events_in_state >= state_hold_events and i < n_events
        oldState = current_state

        @chooseNextState:
            ... transition_logic,current_state,state_direction

        current_state = chooseNextState.next
        state_direction = chooseNextState.newDirection
        transitionCount##[oldState,current_state] =
            ... transitionCount##[oldState,current_state]+1
        transitionDecisionCount = transitionDecisionCount+1
        events_in_state = 0
    endif
endfor

# ---------------------------------------------------------------------------
# EXACT-DURATION TIME NORMALIZATION
# ---------------------------------------------------------------------------
if rawLatestEnd <= 0
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "Internal timing realization is invalid."
endif

timeScale = total_dur/rawLatestEnd
totalEventDur = 0

for i from 1 to n_events
    startTime#[i] = startTime#[i]*timeScale
    dur#[i] = dur#[i]*timeScale
    ioi#[i] = ioi#[i]*timeScale
    totalEventDur = totalEventDur+dur#[i]
endfor

overlapLoad = totalEventDur/total_dur
densityGain = 1/sqrt(max(1,overlapLoad))
realizedDensity = n_events/total_dur

# ---------------------------------------------------------------------------
# TRANSITION STATISTICS
# ---------------------------------------------------------------------------
empiricalTransition## = zero##(4,4)

for s from 1 to 4
    rowTotal = 0
    for j from 1 to 4
        rowTotal = rowTotal+transitionCount##[s,j]
    endfor

    if rowTotal > 0
        for j from 1 to 4
            empiricalTransition##[s,j] =
                ... transitionCount##[s,j]/rowTotal
        endfor
    endif
endfor

toneCount = 0
noiseCount = 0
metalCount = 0
minActualFreq = 1e12
maxActualFreq = 0

for i from 1 to n_events
    if type#[i] = 1
        toneCount = toneCount+1
    elsif type#[i] = 2
        noiseCount = noiseCount+1
    else
        metalCount = metalCount+1
    endif

    minActualFreq = min(minActualFreq,freq#[i])
    maxActualFreq = max(maxActualFreq,freq#[i])
endfor

appendInfoLine: "Realized density: ",
    ... fixed$(realizedDensity,2), " events/s"
appendInfoLine: "Overlap load (sum durations / duration): ",
    ... fixed$(overlapLoad,3)
appendInfoLine: "Density compensation gain: ", fixed$(densityGain,3)
appendInfoLine: "Time normalization scale: ", fixed$(timeScale,4)
appendInfoLine: "Transition decisions: ", transitionDecisionCount
appendInfoLine: "Material counts - tone/noise/metallic: ",
    ... toneCount, " / ", noiseCount, " / ", metalCount
appendInfoLine: ""

# ---------------------------------------------------------------------------
# AUDIO MASTER
# ---------------------------------------------------------------------------
if spatial_mode = 1
    channelCount = 1
else
    channelCount = 2
endif

master = Create Sound from formula:
    ... "Kotonski_state_field_" + uid$,
    ... channelCount,0,total_dur,sr,"0"

renderStart = stopwatch

# ---------------------------------------------------------------------------
# AUDIO RENDER
# ---------------------------------------------------------------------------
for i from 1 to n_events

    t0 = startTime#[i]
    td = dur#[i]
    t1 = min(total_dur,t0+td)

    if t1 > t0
        age$ = "(x-" + fixed$(t0,9) + ")"
        dur$ = fixed$(td,9)

        thisAttack = min(attack_t,0.45*td)
        thisRelease = min(release_t,0.45*td)

        attack$ = fixed$(max(1/sr,thisAttack),9)
        release$ = fixed$(max(1/sr,thisRelease),9)
        releaseStart$ = fixed$(max(0,td-thisRelease),9)

        env$ = "(if " + age$ + "<" + attack$
            ... + " then 0.5-0.5*cos(pi*" + age$ + "/" + attack$
            ... + ") else if " + age$ + ">" + releaseStart$
            ... + " then 0.5+0.5*cos(pi*(" + age$ + "-"
            ... + releaseStart$ + ")/" + release$
            ... + ") else 1 fi fi)"

        eventAmp = global_amp*densityGain*amp#[i]
        pan = pan#[i]

        if channelCount = 1
            leftGain = 1
            rightGain = 1
        else
            leftGain = sqrt(1-pan)
            rightGain = sqrt(pan)
        endif

        # ------------------------------------------------------
        # TONE
        # ------------------------------------------------------
        if type#[i] = 1
            phase = 2*pi*randomUniform(0,1)
            wave$ = "sin(2*pi*" + fixed$(freq#[i],6)
                ... + "*" + age$ + "+" + fixed$(phase,9) + ")"

            selectObject: master

            if channelCount = 1
                Formula (part): t0,t1,1,1,
                    ... "self+" + fixed$(eventAmp,9)
                    ... + "*" + wave$ + "*" + env$
            else
                Formula (part): t0,t1,1,2,
                    ... "self+if row=1 then "
                    ... + fixed$(eventAmp*leftGain,9)
                    ... + "*" + wave$ + "*" + env$
                    ... + " else "
                    ... + fixed$(eventAmp*rightGain,9)
                    ... + "*" + wave$ + "*" + env$ + " fi"
            endif

        # ------------------------------------------------------
        # NOISE BAND
        # ------------------------------------------------------
        elsif type#[i] = 2
            noiseLocal = Create Sound from formula:
                ... "noise_fragment_" + uid$ + "_" + string$(i),
                ... 1,0,td,sr,"randomGauss(0,1)"

            center = freq#[i]
            bw = bandwidth#[i]
            lowCut = max(20,center-bw/2)
            highCut = min(safeTop,center+bw/2)

            if highCut <= lowCut+20
                highCut = min(safeTop,lowCut+50)
            endif

            selectObject: noiseLocal
            smoothHz = min(200,max(10,0.15*(highCut-lowCut)))
            Filter (pass Hann band): lowCut,highCut,smoothHz
            noiseFiltered = selected("Sound")
            removeObject: noiseLocal

            selectObject: noiseFiltered
            nrms = Get root-mean-square: 0,0
            if nrms > 1e-12
                Formula: "self/" + fixed$(nrms,12)
            endif

            selectObject: master
            source$ = "object(" + string$(noiseFiltered)
                ... + "," + age$ + ",1)"

            if channelCount = 1
                Formula (part): t0,t1,1,1,
                    ... "self+" + fixed$(0.50*eventAmp,9)
                    ... + "*" + source$ + "*" + env$
            else
                Formula (part): t0,t1,1,2,
                    ... "self+if row=1 then "
                    ... + fixed$(0.50*eventAmp*leftGain,9)
                    ... + "*" + source$ + "*" + env$
                    ... + " else "
                    ... + fixed$(0.50*eventAmp*rightGain,9)
                    ... + "*" + source$ + "*" + env$ + " fi"
            endif

            removeObject: noiseFiltered

        # ------------------------------------------------------
        # METALLIC TRANSIENT
        # ------------------------------------------------------
        else
            phase = 2*pi*randomUniform(0,1)
            f1 = freq#[i]
            f2 = min(safeTop,1.47*f1)
            f3 = min(safeTop,2.13*f1)

            wave$ = "(sin(2*pi*" + fixed$(f1,6)
                ... + "*" + age$ + "+" + fixed$(phase,9) + ")"
                ... + "+0.45*sin(2*pi*" + fixed$(f2,6)
                ... + "*" + age$ + "+" + fixed$(1.3*phase,9) + ")"
                ... + "+0.28*sin(2*pi*" + fixed$(f3,6)
                ... + "*" + age$ + "+" + fixed$(1.7*phase,9) + "))"
                ... + "*exp(-4*" + age$ + "/" + dur$ + ")"

            selectObject: master

            if channelCount = 1
                Formula (part): t0,t1,1,1,
                    ... "self+" + fixed$(0.70*eventAmp,9)
                    ... + "*" + wave$ + "*" + env$
            else
                Formula (part): t0,t1,1,2,
                    ... "self+if row=1 then "
                    ... + fixed$(0.70*eventAmp*leftGain,9)
                    ... + "*" + wave$ + "*" + env$
                    ... + " else "
                    ... + fixed$(0.70*eventAmp*rightGain,9)
                    ... + "*" + wave$ + "*" + env$ + " fi"
            endif
        endif
    endif
endfor

# ---------------------------------------------------------------------------
# FINAL OUTPUT LEVEL
# ---------------------------------------------------------------------------
selectObject: master

preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

safePreset$ = replace$(preset_name$," ","_",0)
Rename: "Kotonski_StateEvent_" + safePreset$
master = selected("Sound")

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalDuration = Get total duration
renderTime = stopwatch-renderStart

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

appendInfoLine: "=== AUDIO RENDER COMPLETE ==="
appendInfoLine: "Render time: ", fixed$(renderTime,2), " s"
appendInfoLine: "Output duration: ", fixed$(finalDuration,4), " s"
appendInfoLine: "Actual center-frequency range: ",
    ... fixed$(minActualFreq,1), " - ", fixed$(maxActualFreq,1), " Hz"
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied
appendInfoLine: ""

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# PLAY
# ---------------------------------------------------------------------------
selectObject: master
if play_result
    Play
endif

selectObject: master


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.82
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"
    .s1$ = "{0.18,0.67,0.82}"
    .s2$ = "{0.30,0.72,0.38}"
    .s3$ = "{0.88,0.68,0.18}"
    .s4$ = "{0.88,0.39,0.17}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "KOTONSKI-INSPIRED STATE-EVENT GENERATOR | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.68
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... transition_name$ + " | hold "
        ... + string$(state_hold_events) + " event(s) | "
        ... + string$(n_events) + " events | " + spatial_name$
    Text: 0.5,"centre",0.20,"half",
        ... "state controller -> event material/register/IOI -> overlap montage -> measured audio"

    # -----------------------------------------------------------------------
    # PANEL A: REALIZED STATE TRAJECTORY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.78,1.00
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  REALIZED STATE TRAJECTORY | finite-state memory and transition decisions"

    Select inner viewport: .left,.right,1.07,2.03
    Axes: 0,total_dur,0.5,4.5
    Paint rectangle: .bg$,0,total_dur,0.5,4.5

    Colour: .grid$
    Dotted line
    for .s from 1 to 4
        Draw line: 0,.s,total_dur,.s
    endfor
    Plain line

    for .i from 1 to n_events
        .st = state#[.i]

        if .st = 1
            .col$ = .s1$
        elsif .st = 2
            .col$ = .s2$
        elsif .st = 3
            .col$ = .s3$
        else
            .col$ = .s4$
        endif

        Colour: .col$
        Paint circle (mm): .col$,startTime#[.i],.st,0.80

        if .i < n_events
            if state#[.i+1] <> .st
                Line width: 1.0
                Draw line:
                    ... startTime#[.i],.st,
                    ... startTime#[.i+1],state#[.i+1]
            endif
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1,1,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","State"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL EVENT FIELD ON LOG FREQUENCY AXIS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.18,2.40
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  ACTUAL EVENT FIELD | tone, noise-band and metallic fragments on log-frequency axis"

    .logLo = ln(max(20,0.90*minActualFreq))
    .logHi = ln(min(safeTop,max(1000,1.15*maxActualFreq)))
    if .logHi <= .logLo
        .logHi = .logLo+0.5
    endif

    Select inner viewport: .left,.right,2.47,3.50
    Axes: 0,total_dur,.logLo,.logHi
    Paint rectangle: "{0.055,0.055,0.065}",0,total_dur,.logLo,.logHi

    .eventStep = max(1,ceiling(n_events/1400))

    for .i from 1 to n_events
        if ((.i-1) mod .eventStep)=0
            .st = state#[.i]

            if .st = 1
                .col$ = .s1$
            elsif .st = 2
                .col$ = .s2$
            elsif .st = 3
                .col$ = .s3$
            else
                .col$ = .s4$
            endif

            Colour: .col$
            .t0 = startTime#[.i]
            .t1 = min(total_dur,.t0+dur#[.i])
            .f = freq#[.i]

            if type#[.i] = 1
                Draw line: .t0,ln(.f),.t1,ln(.f)

            elsif type#[.i] = 2
                .lo = max(20,.f-bandwidth#[.i]/2)
                .hi = min(safeTop,.f+bandwidth#[.i]/2)
                .lo = max(exp(.logLo),.lo)
                .hi = min(exp(.logHi),.hi)

                if .hi > .lo
                    Draw line: .t0,ln(.lo),.t0,ln(.hi)
                    Draw line: .t0,ln(.f),.t1,ln(.f)
                endif

            else
                Paint circle (mm): .col$,.t0,ln(.f),0.95
                Draw line: .t0,ln(.f),.t1,ln(.f)
            endif
        endif
    endfor

    Colour: "White"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"

    # Manual log-frequency labels.
    Font size: 5
    .tick# = {50,100,200,500,1000,2000,5000,10000}
    for .k from 1 to 8
        .ff = .tick#[.k]
        if .ff >= exp(.logLo) and .ff <= exp(.logHi)
            Colour: "{0.55,0.55,0.58}"
            Draw line: 0,ln(.ff),0.012*total_dur,ln(.ff)
            Colour: "White"

            if .ff >= 1000
                .lab$ = fixed$(.ff/1000,0) + "k"
            else
                .lab$ = fixed$(.ff,0)
            endif

            Text: -0.012*total_dur,"right",ln(.ff),"half",.lab$
        endif
    endfor

    # -----------------------------------------------------------------------
    # PANEL C: EMPIRICAL TRANSITION DECISION MATRIX
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.66,3.88
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  STATE-TRANSITION DECISIONS | empirical probability per decision point"

    Select inner viewport: 1.70,6.65,3.95,5.00
    Axes: 0,1,0,1
    Paint rectangle: .bg$,0,1,0,1

    .x0 = 0.18
    .x1 = 0.82
    .y0 = 0.10
    .y1 = 0.90
    .cw = (.x1-.x0)/4
    .ch = (.y1-.y0)/4

    for .s from 1 to 4
        for .j from 1 to 4
            .p = empiricalTransition##[.s,.j]
            .r = 1-0.72*.p
            .g = 1-0.45*.p
            .b = 1-0.10*.p
            .col$ = "{" + fixed$(.r,3) + ","
                ... + fixed$(.g,3) + "," + fixed$(.b,3) + "}"

            .xa = .x0+(.j-1)*.cw
            .xb = .xa+.cw
            .yb = .y1-(.s-1)*.ch
            .ya = .yb-.ch
            Paint rectangle: .col$,.xa,.xb,.ya,.yb

            Font size: 5
            Colour: "Black"
            Text: 0.5*(.xa+.xb),"centre",
                ... 0.5*(.ya+.yb),"half",fixed$(.p,2)
        endfor
    endfor

    Colour: "{0.45,0.45,0.48}"
    Draw rectangle: .x0,.x1,.y0,.y1
    Font size: 5
    Colour: "Black"

    for .s from 1 to 4
        .yc = .y1-(.s-0.5)*.ch
        .xc = .x0+(.s-0.5)*.cw
        Text: .x0-0.03,"right",.yc,"half","S" + string$(.s)
        Text: .xc,"centre",.y0-0.04,"half","S" + string$(.s)
    endfor

    Text: 0.5,"centre",0.02,"half",
        ... "rows=current state   columns=next state   decisions="
        ... + string$(transitionDecisionCount)

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if channelCount = 1
        selectObject: master
        Copy: "kotonski_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: master
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: master
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
    Select inner viewport: 0.35,7.65,5.16,5.38
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + sampled event-center guides"

    .specMax = min(safeTop,max(2500,1.20*maxActualFreq))
    .specStep = max(0.002,total_dur/1200)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.45,6.50
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,total_dur,0,.specMax
    Colour: "{0.18,0.54,0.82}"
    Line width: 0.7

    .guideStep = max(1,ceiling(n_events/220))
    for .i from 1 to n_events
        if ((.i-1) mod .guideStep)=0 and freq#[.i] <= .specMax
            Draw line:
                ... startTime#[.i],freq#[.i],
                ... min(total_dur,startTime#[.i]+dur#[.i]),freq#[.i]
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

    if serial_grid_mode
        .concept$ = "Etude analogy: synthetic 11-level parameter grid; not concrete-source reconstruction"
    elsif microstructure_mode
        .concept$ = "Microstructures analogy: overlapping synthetic fragment montage; not glass/wood/metal source reconstruction"
    elsif aela_mode
        .concept$ = "Aela analogy: pure sine events on preserved 25-Hz grid inside aleatoric state graph"
    else
        .concept$ = "engine-specific finite-state electronic event field"
    endif

    Text: 0.02,"left",0.79,"half",
        ... "CONCEPT  |  " + .concept$

    Text: 0.02,"left",0.57,"half",
        ... "EVENTS  |  tone/noise/metal "
        ... + string$(toneCount) + "/" + string$(noiseCount)
        ... + "/" + string$(metalCount)
        ... + "  |  density " + fixed$(realizedDensity,2) + "/s"
        ... + "  |  overlap load " + fixed$(overlapLoad,2)

    if aela_mode
        .samplingText$ = "25-Hz grid upper limit " + fixed$(effective_max_Hz,0)
            ... + " Hz"
    else
        .samplingText$ = "frequency scale " + fixed$(frequency_scale,4)
    endif

    Text: 0.02,"left",0.35,"half",
        ... "SAMPLING  |  safe top " + fixed$(safeTop,0)
        ... + " Hz  |  " + .samplingText$
        ... + "  |  " + seedLabel$

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
