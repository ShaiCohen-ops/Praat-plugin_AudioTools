# ============================================================
# Praat AudioTools - Kotonski_FSM_Event_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6.1 frequency-grid/visual-range fix (2026)
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
# v1.6.1 frequency-grid / visual-range fix:
#   - Aela-inspired upper frequency boundary is now quantized downward to the
#     25-Hz grid, so sampling-headroom truncation cannot create a non-grid tone.
#   - Visualization frequency bounds now use effective_min_Hz/effective_max_Hz
#     after any common sampling-headroom scaling, so low scaled events are not
#     clipped out of the realization score.
#   - Header, form and Info version labels synchronized to v1.6.1.
#   - No state-transition logic, event realization, rendering, spatialization,
#     density compensation, peak protection or score-layout logic changed.
#
# v1.6 changes (visualization only; the audio path is unchanged)
# ------------
#   - Figure is now a SCORE PAGE and nothing else: no transition matrix, no
#     spectrogram, no QC block. Every system shares ONE time axis, so a
#     vertical cut through the page reads as a single event across every
#     parameter. The realization data that a score carries in its head-block
#     (event count, duration, density, material tally, controller, seed) sits
#     under the title; the rest is in the key.
#   - Figure recast as a PARTYTURA REALIZACYJNA. The Etiuda score was published
#     by PWM in 1963 as a realization score, and the documented method is a set
#     of parameter SCALES: the cymbal stroke was filtered into six bands of
#     different widths and transposed to eleven heights, with eleven-step
#     scales ordering length and eleven ordering dynamics, and six scales
#     differentiating articulation.
#   - NEW PANEL I, TABLICE SKAL: the four scales drawn as ruled tables, one
#     mark per event at its level. The engine's 11/11/11/6 grid was previously
#     invisible in the figure although it is the whole basis of the Etude
#     preset; the serial rotations (steps of 7, 3, 5 and 5) now read directly
#     as diagonal lattices. For presets with no grid the realized values are
#     binned to the same levels and the heading says so.
#   - COLOUR CONVENTION, applied consistently: INK for what is modelled on the
#     documented method (the parameter tables), COLOUR for what this engine
#     invented and Kotonski did not use (the four finite-state classes). The
#     eye can therefore separate the analogy from the machinery, which is the
#     distinction the conceptual scope above insists on.
#   - The event field is no longer drawn on a near-black ground with sub-pixel
#     dots and hairlines, which rendered as an almost empty rectangle with no
#     readable frequency labels. It is now light, with events as filled bars
#     of guaranteed minimum width and proper log-frequency marks.
#   - State plan and transition matrix placed side by side, with each matrix
#     row carrying its sample count: at hold 11 over 121 events there are only
#     ten transitions, so a cell reading 1.00 rests on n=2 or n=3.
#   - Serial grid indices are now logged (pitchIdx#, durIdx#, ampIdx#, ioiIdx#)
#     so the score can show the scales themselves, not only their consequences.
#   - Every text label is drawn from its own anchored viewport: a second Text
#     in the same strip lands displaced, because Text leaves the drawing frame
#     on the outer viewport.
#
# Historical sources for the parameter scales: Polish Radio Experimental Studio
# documentation via Unearthing the Music; PWM score publication data (1963,
# 16 pages, Polish/English/German, issued with a 7-inch disc); POLMIC.
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

form Kotonski-Inspired State-Event Generator v1.6.1
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
    effective_max_Hz = 25*floor(min(frequency_max_Hz,safeTop)/25)
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
# Serial grid positions, logged so the realization score can show the scales
# themselves rather than only their audible consequences.
pitchIdx# = zero#(n_events)
durIdx# = zero#(n_events)
ampIdx# = zero#(n_events)
ioiIdx# = zero#(n_events)

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
writeInfoLine: "  KOTONSKI-INSPIRED STATE-EVENT GENERATOR v1.6.1"
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
        pitchIdx#[i] = pitchIndex
        durIdx#[i] = durIndex
        ampIdx#[i] = ampIndex
        ioiIdx#[i] = ((2*(i-1)+3) mod 11)+1

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
        pitchIdx#[i] = 0
        durIdx#[i] = 0
        ampIdx#[i] = 0
        ioiIdx#[i] = 0

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
# ===========================================================================
# VISUALIZATION: PARTYTURA REALIZACYJNA
#
# One score page, not an analysis sheet. Every system shares a single time
# axis, as the systems of a realization score do, so a vertical cut through
# the page reads as one event: where it sits, how long, how loud, how
# articulated. The documented Etiuda method is a set of parameter SCALES --
# the cymbal stroke filtered into six bands of different widths and
# transposed to eleven heights, with eleven-step scales ordering length and
# eleven ordering dynamics, and six differentiating articulation -- so the
# scales are score content and appear as ruled systems, not as a side panel.
#
# COLOUR CONVENTION, used for one reason only:
#   INK    = modelled on the documented historical method (the scale systems)
#   COLOUR = this engine's own finite-state machinery, which Kotonski did
#            not use (the montage and the state ribbon)
# ===========================================================================
procedure drawVisualization

    .lo = 1.18
    .hi = 7.70
    .ink$ = "{0.13,0.13,0.15}"
    .paper$ = "{0.995,0.993,0.987}"
    .grid$ = "{0.86,0.86,0.88}"
    .faint$ = "{0.45,0.45,0.50}"
    .s1$ = "{0.18,0.55,0.75}"
    .s2$ = "{0.28,0.62,0.36}"
    .s3$ = "{0.84,0.62,0.18}"
    .s4$ = "{0.78,0.34,0.20}"

    .logLo = ln(max(20, 0.85 * effective_min_Hz))
    .logHi = ln(min(safeTop, 1.15 * effective_max_Hz))
    if .logHi <= .logLo
        .logHi = .logLo + 1
    endif

    if total_dur <= 12
        .tTick = 2
    elsif total_dur <= 45
        .tTick = 5
    elsif total_dur <= 120
        .tTick = 20
    else
        .tTick = 60
    endif

    # Marks are given real extent so they survive at screen resolution, not
    # only in a 300-dpi export.
    .mw = max(total_dur / 420, total_dur / 420)

    if serial_grid_mode
        .src$ = "serial grid as generated"
    else
        .src$ = "realized values binned to the same levels; this preset uses no grid"
    endif

    .dMinR = 1e30
    .dMaxR = -1e30
    .aMinR = 1e30
    .aMaxR = -1e30
    .fMinR = 1e30
    .fMaxR = -1e30
    for .i to n_events
        .dMinR = min(.dMinR, dur#[.i])
        .dMaxR = max(.dMaxR, dur#[.i])
        .aMinR = min(.aMinR, amp#[.i])
        .aMaxR = max(.aMaxR, amp#[.i])
        .fMinR = min(.fMinR, freq#[.i])
        .fMaxR = max(.fMaxR, freq#[.i])
    endfor
    if .dMaxR <= .dMinR
        .dMaxR = .dMinR + 1e-6
    endif
    if .aMaxR <= .aMinR
        .aMaxR = .aMinR + 1e-6
    endif
    if .fMaxR <= .fMinR
        .fMaxR = .fMinR + 1e-6
    endif

    tblP# = zero#(n_events)
    tblD# = zero#(n_events)
    tblA# = zero#(n_events)
    for .i to n_events
        if serial_grid_mode
            tblP#[.i] = pitchIdx#[.i]
            tblD#[.i] = durIdx#[.i]
            tblA#[.i] = ampIdx#[.i]
        else
            tblP#[.i] = 1 + floor(10.999 * (ln(freq#[.i]) - ln(.fMinR))
                ... / (ln(.fMaxR) - ln(.fMinR)))
            tblD#[.i] = 1 + floor(10.999 * (dur#[.i] - .dMinR) / (.dMaxR - .dMinR))
            tblA#[.i] = 1 + floor(10.999 * (amp#[.i] - .aMinR) / (.aMaxR - .aMinR))
        endif
        tblP#[.i] = max(1, min(11, tblP#[.i]))
        tblD#[.i] = max(1, min(11, tblD#[.i]))
        tblA#[.i] = max(1, min(11, tblA#[.i]))
    endfor

    Erase all
    Solid line
    Line width: 1

    # ============================ HEAD ============================
    Select inner viewport: 0.60, 7.70, 0.08, 0.36
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##PARTYTURA REALIZACYJNA##"

    Select inner viewport: 0.60, 7.70, 0.38, 0.54
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30,0.30,0.42}"
    Text: 0.5, "centre", 0.5, "half", preset_name$

    # Realization data, as a score's head-block rather than a QC panel.
    Select inner viewport: 0.60, 7.70, 0.58, 0.74
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 0.5, "centre", 0.5, "half",
        ... string$(n_events) + " zdarzeń / events   ·   "
        ... + fixed$(total_dur, 1) + " s   ·   "
        ... + fixed$(realizedDensity, 2) + " /s   ·   "
        ... + "ton/szum/metal " + string$(toneCount) + "/" + string$(noiseCount)
        ... + "/" + string$(metalCount) + "   ·   "
        ... + transition_name$ + ", hold " + string$(state_hold_events)
        ... + "   ·   " + spatial_name$ + "   ·   " + seedLabel$

    # ============================ MONTAGE ============================
    Select inner viewport: 0.60, 7.70, 0.94, 1.10
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##MONTAŻ##"

    Select inner viewport: 0.60, 7.70, 0.94, 1.10
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "bar height = bandwidth of a noise band; colour = state class"

    Select inner viewport: .lo, .hi, 1.16, 3.20
    Axes: 0, total_dur, .logLo, .logHi
    Paint rectangle: .paper$, 0, total_dur, .logLo, .logHi

    Select inner viewport: .lo, .hi, 1.16, 3.20
    Axes: 0, total_dur, .logLo, .logHi
    Colour: .grid$
    Line width: 1
    .tick# = {50, 100, 200, 500, 1000, 2000, 5000, 10000}
    for .k to 8
        .ff = .tick#[.k]
        if ln(.ff) >= .logLo and ln(.ff) <= .logHi
            Draw line: 0, ln(.ff), total_dur, ln(.ff)
        endif
    endfor

    Select inner viewport: .lo, .hi, 1.16, 3.20
    Axes: 0, total_dur, .logLo, .logHi
    for .i to n_events
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
        .t0 = startTime#[.i]
        .t1 = min(total_dur, .t0 + dur#[.i])
        if .t1 - .t0 < .mw
            .t1 = .t0 + .mw
        endif
        .f = freq#[.i]
        if .t0 < total_dur and ln(.f) > .logLo and ln(.f) < .logHi
            if type#[.i] = 2
                .flo = max(exp(.logLo), .f - bandwidth#[.i] / 2)
                .fhi = min(exp(.logHi), .f + bandwidth#[.i] / 2)
                if .fhi > .flo
                    Paint rectangle: .col$, .t0, .t1, ln(.flo), ln(.fhi)
                endif
            else
                .h = 0.010 * (.logHi - .logLo)
                Paint rectangle: .col$, .t0, .t1, ln(.f) - .h, ln(.f) + .h
            endif
        endif
    endfor

    Select inner viewport: .lo, .hi, 1.16, 3.20
    Axes: 0, total_dur, .logLo, .logHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    for .k to 8
        .ff = .tick#[.k]
        if ln(.ff) >= .logLo and ln(.ff) <= .logHi
            if .ff >= 1000
                .lab$ = fixed$(.ff / 1000, 0) + "k"
            else
                .lab$ = fixed$(.ff, 0)
            endif
            One mark left: ln(.ff), "no", "yes", "no", .lab$
        endif
    endfor
    Font size: 6
    Text left: "yes", "Hz"

    # ==================== THE FOUR SCALE SYSTEMS ====================
    # Plotted against TIME, not event number, so a vertical cut through the
    # page reads as one event across every parameter.
    for .sys to 4
        if .sys = 1
            .y0 = 3.40
            .y1 = 3.90
            .nLev = 11
            .name$ = "WYSOKOŚĆ"
        elsif .sys = 2
            .y0 = 4.04
            .y1 = 4.54
            .nLev = 11
            .name$ = "DŁUGOŚĆ"
        elsif .sys = 3
            .y0 = 4.68
            .y1 = 5.18
            .nLev = 11
            .name$ = "DYNAMIKA"
        else
            .y0 = 5.32
            .y1 = 5.74
            .nLev = 6
            .name$ = "ARTYKUL."
        endif

        Select inner viewport: .lo, .hi, .y0, .y1
        Axes: 0, total_dur, 0.5, .nLev + 0.5
        Paint rectangle: .paper$, 0, total_dur, 0.5, .nLev + 1.9

        Select inner viewport: .lo, .hi, .y0, .y1
        Axes: 0, total_dur, 0.5, .nLev + 0.5
        Colour: .grid$
        Line width: 1
        for .r to .nLev
            Draw line: 0, .r, total_dur, .r
        endfor

        Select inner viewport: .lo, .hi, .y0, .y1
        Axes: 0, total_dur, 0.5, .nLev + 0.5
        for .i to n_events
            if .sys = 1
                .lev = tblP#[.i]
            elsif .sys = 2
                .lev = tblD#[.i]
            elsif .sys = 3
                .lev = tblA#[.i]
            else
                .lev = articulation#[.i]
            endif
            .t0 = startTime#[.i]
            if .lev >= 1 and .lev <= .nLev and .t0 < total_dur
                Paint rectangle: .ink$, .t0, min(total_dur, .t0 + .mw),
                    ... .lev - 0.34, .lev + 0.34
            endif
        endfor

        Select inner viewport: .lo, .hi, .y0, .y1
        Axes: 0, total_dur, 0.5, .nLev + 0.5
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 4
        One mark left: 1, "no", "yes", "no", "1"
        if .nLev = 11
            One mark left: 11, "no", "yes", "no", "11"
        else
            One mark left: 6, "no", "yes", "no", "6"
        endif
        Font size: 5
        Text left: "yes", .name$
    endfor

    # ==================== STATE RIBBON + TIME RULER ====================
    Select inner viewport: .lo, .hi, 5.88, 6.06
    Axes: 0, total_dur, 0, 1
    Paint rectangle: .paper$, 0, total_dur, 0, 1

    Select inner viewport: .lo, .hi, 5.88, 6.06
    Axes: 0, total_dur, 0, 1
    for .i to n_events
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
        .t0 = startTime#[.i]
        if .i < n_events
            .t1 = startTime#[.i + 1]
        else
            .t1 = total_dur
        endif
        if .t1 > .t0 and .t0 < total_dur
            Paint rectangle: .col$, .t0, min(total_dur, .t1), 0.12, 0.88
        endif
    endfor

    Select inner viewport: .lo, .hi, 5.88, 6.06
    Axes: 0, total_dur, 0, 1
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Text left: "yes", "STAN"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "czas / time (s)"

    # ============================ KEY ============================
    Select inner viewport: 0.60, 7.70, 6.62, 6.78
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##OBJAŚNIENIA / KEY##"

    Select inner viewport: 0.60, 7.70, 6.62, 6.78
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "WYSOKOŚĆ height · DŁUGOŚĆ length · DYNAMIKA dynamics · ARTYKUL. articulation   |   " + .src$

    Select inner viewport: 1.18, 4.60, 6.84, 7.14
    Axes: 0, 4, 0, 1
    for .st to 4
        if .st = 1
            .col$ = .s1$
            .lab$ = "punkty / points"
        elsif .st = 2
            .col$ = .s2$
            .lab$ = "pasma / bands"
        elsif .st = 3
            .col$ = .s3$
            .lab$ = "fragmenty / micro"
        else
            .col$ = .s4$
            .lab$ = "pole / dense"
        endif
        Paint rectangle: .col$, .st - 1 + 0.02, .st - 1 + 0.20, 0.30, 0.78
        Colour: .ink$
        Line width: 1
        Draw rectangle: .st - 1 + 0.02, .st - 1 + 0.20, 0.30, 0.78
        Font size: 5
        Colour: "Black"
        Text: .st - 1 + 0.25, "left", 0.54, "half", "S" + string$(.st)
        Font size: 4
        Colour: .faint$
        Text: .st - 1 + 0.25, "left", 0.16, "half", .lab$
    endfor

    if serial_grid_mode
        .concept$ = "analogia do Etiudy: syntetyczna siatka jedenastostopniowa — NIE rekonstrukcja procesu konkretnego"
        .conceptEn$ = "Etiuda analogy: a synthetic eleven-level grid, not a reconstruction of the concrete-source process"
    elsif microstructure_mode
        .concept$ = "analogia do Mikrostruktur: montaż nakładających się fragmentów syntetycznych"
        .conceptEn$ = "Mikrostruktury analogy: overlapping synthetic fragments, not the glass/wood/metal recordings"
    elsif aela_mode
        .concept$ = "analogia do Aeli: tony sinusoidalne na siatce 25 Hz"
        .conceptEn$ = "Aela analogy: sine tones on a preserved 25-Hz grid"
    else
        .concept$ = "pole zdarzeń sterowane automatem skończonym"
        .conceptEn$ = "engine-specific finite-state event field"
    endif

    Select inner viewport: 4.70, 7.70, 6.86, 7.02
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.30,0.30,0.35}"
    Text: 1.0, "right", 0.5, "half",
        ... "tusz = metoda udokumentowana   ·   kolor = automat tego programu"

    Select inner viewport: 4.70, 7.70, 7.04, 7.20
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "ink = the documented method   ·   colour = this engine's own controller"

    Select inner viewport: 0.60, 7.70, 7.34, 7.50
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.30,0.30,0.35}"
    Text: 0.0, "left", 0.5, "half", .concept$

    Select inner viewport: 0.60, 7.70, 7.52, 7.68
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 0.0, "left", 0.5, "half", .conceptEn$

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
