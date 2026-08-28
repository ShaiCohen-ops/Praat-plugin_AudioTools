# ============================================================
# Praat AudioTools - Random_Walk_Rhythm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generates a quantized percussive pulse stream whose FREQUENCY follows a
#   bounded random walk on a linear-Hz lattice. Timing is deterministic:
#   Tempo x Steps_per_beat defines the rhythmic grid. At each transition a
#   categorical draw requests up, down, or hold; requests that point outside
#   the frequency lattice are reflected inward instead of being clamped.
#
#   Each event uses a local-phase sine, exponential decay, and cosine closure.
#   Spatial modes are mono, true event-alternating stereo ping-pong,
#   constant-power rotating panorama, and dual-band AM.
#
# Visualization is mechanism-first:
#   A. categorical walk decisions and boundary reflections,
#   B. bounded frequency-state trajectory,
#   C. timing/event kernel + selected spatial mapping,
#   D. measured output waveform(s), followed by QC.
#
# Changelog v0.4:
#   - Clarified that the random walk controls frequency, not event timing.
#   - Added probability validation and explicit hold probability.
#   - Replaced clamp-induced edge sticking with reflected lattice steps.
#   - Reset oscillator phase at each event and added exact cosine closure.
#   - Uses ceiling(Duration / stepDuration), so no unintended silent tail.
#   - Stereo Ping-Pong now alternates events between L/R instead of merely
#     filtering identical synchronous channels.
#   - Rotating panorama now uses constant-power panning.
#   - Renamed misleading Binaural Rhythm mode to Dual-Band AM.
#   - Added optional deterministic seed, frequency bounds, event fill,
#     decay, rotation speed, output peak, and sample rate on a Details page.
#   - Rebuilt visualization around the generating mechanism and used
#     independent Picture viewports for all title/text/QC strips.
#
# Changelog v0.4.1:
#   - Added a 12,000-event runtime guard for extreme custom timing grids.
# ============================================================

# ============================================================
# COMPACT FORM
# ============================================================
form Random Walk Rhythm v0.4.1
    optionmenu Preset 1
        option Custom
        option Gentle Bounce
        option Chaotic Dance
        option Steady Climb
        option Falling Steps
        option Pulsing Heart
        option Nervous Ticks
        option Ocean Waves
        option Machine Pulse

    positive Duration_s 6.0
    positive Tempo_bpm 120
    integer Steps_per_beat 4

    positive Base_frequency_Hz 180
    positive Frequency_step_Hz 50
    real Probability_up 0.4
    real Probability_down 0.4

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Ping-Pong
        option Rotating Panorama
        option Dual-Band AM

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS / OPTIONAL DETAILS
# ============================================================
sample_rate_Hz = 44100
min_frequency_Hz = 80
max_frequency_Hz = 1500
event_fill = 0.8
decay_rate = 15
rotation_cycles_per_beat = 0.5
output_peak = 0.9
random_seed = 0

if edit_details
    beginPause: "Random Walk Rhythm - Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        positive: "Minimum frequency (Hz)", min_frequency_Hz
        positive: "Maximum frequency (Hz)", max_frequency_Hz
        real: "Event fill of grid step (0..1]", event_fill
        positive: "Exponential decay rate", decay_rate
        positive: "Rotation cycles per beat", rotation_cycles_per_beat
        real: "Output peak (0..1]", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ============================================================
# PRESETS
# ============================================================
preset_name$ = "Custom"

if preset = 2
    tempo_bpm = 90
    steps_per_beat = 2
    base_frequency_Hz = 150
    frequency_step_Hz = 30
    probability_up = 0.5
    probability_down = 0.3
    preset_name$ = "GentleBounce"
elsif preset = 3
    tempo_bpm = 160
    steps_per_beat = 8
    base_frequency_Hz = 200
    frequency_step_Hz = 80
    probability_up = 0.4
    probability_down = 0.4
    preset_name$ = "ChaoticDance"
elsif preset = 4
    tempo_bpm = 100
    steps_per_beat = 4
    base_frequency_Hz = 120
    frequency_step_Hz = 40
    probability_up = 0.6
    probability_down = 0.2
    preset_name$ = "SteadyClimb"
elsif preset = 5
    tempo_bpm = 80
    steps_per_beat = 4
    base_frequency_Hz = 200
    frequency_step_Hz = 60
    probability_up = 0.3
    probability_down = 0.5
    preset_name$ = "FallingSteps"
elsif preset = 6
    tempo_bpm = 60
    steps_per_beat = 2
    base_frequency_Hz = 100
    frequency_step_Hz = 20
    probability_up = 0.4
    probability_down = 0.4
    preset_name$ = "PulsingHeart"
elsif preset = 7
    tempo_bpm = 140
    steps_per_beat = 16
    base_frequency_Hz = 180
    frequency_step_Hz = 100
    probability_up = 0.45
    probability_down = 0.45
    preset_name$ = "NervousTicks"
elsif preset = 8
    tempo_bpm = 70
    steps_per_beat = 3
    base_frequency_Hz = 130
    frequency_step_Hz = 25
    probability_up = 0.5
    probability_down = 0.3
    preset_name$ = "OceanWaves"
elsif preset = 9
    tempo_bpm = 110
    steps_per_beat = 4
    base_frequency_Hz = 160
    frequency_step_Hz = 35
    probability_up = 0.4
    probability_down = 0.4
    preset_name$ = "MachinePulse"
endif

# ============================================================
# VALIDATION AND DERIVED PARAMETERS
# ============================================================
if sample_rate_Hz < 1000
    exitScript: "Sample rate must be at least 1000 Hz."
endif
if steps_per_beat < 1
    exitScript: "Steps per beat must be at least 1."
endif
if probability_up < 0 or probability_up > 1
    exitScript: "Probability up must be between 0 and 1."
endif
if probability_down < 0 or probability_down > 1
    exitScript: "Probability down must be between 0 and 1."
endif
if probability_up + probability_down > 1
    exitScript: "Probability up + probability down must not exceed 1."
endif
if min_frequency_Hz >= max_frequency_Hz
    exitScript: "Minimum frequency must be lower than maximum frequency."
endif
if base_frequency_Hz < min_frequency_Hz or base_frequency_Hz > max_frequency_Hz
    exitScript: "Base frequency must lie inside the selected frequency bounds."
endif
if event_fill <= 0 or event_fill > 1
    exitScript: "Event fill must be greater than 0 and at most 1."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and at most 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (unpredictable) or a positive integer."
endif

beatsPerSecond = tempo_bpm / 60
beatDuration = 1 / beatsPerSecond
stepDuration = beatDuration / steps_per_beat
eventDuration = stepDuration * event_fill
totalSteps = ceiling(duration_s / stepDuration)
if totalSteps < 1
    totalSteps = 1
endif
maxEvents = 12000
if totalSteps > maxEvents
    exitScript: "Timing grid would create " + string$(totalSteps) + " events; the safety limit is " + string$(maxEvents) + ". Reduce Duration, Tempo, or Steps per beat."
endif
if eventDuration * sample_rate_Hz < 8
    exitScript: "Event duration is too short for the selected sample rate (need at least 8 samples per event)."
endif

hold_probability = 1 - probability_up - probability_down
nyquist = sample_rate_Hz / 2

# Build the reachable linear-Hz lattice around the requested base frequency.
minIndex = ceiling((min_frequency_Hz - base_frequency_Hz) / frequency_step_Hz)
maxIndex = floor((max_frequency_Hz - base_frequency_Hz) / frequency_step_Hz)
if maxIndex <= minIndex
    exitScript: "Frequency step is too large for the selected base frequency and bounds; fewer than two lattice states are reachable."
endif
latticeMinFreq = base_frequency_Hz + minIndex * frequency_step_Hz
latticeMaxFreq = base_frequency_Hz + maxIndex * frequency_step_Hz
if latticeMaxFreq >= 0.95 * nyquist
    exitScript: "Highest reachable frequency (" + fixed$(latticeMaxFreq, 2) + " Hz) must be below 95% of Nyquist (" + fixed$(0.95 * nyquist, 2) + " Hz)."
endif

# Spatial mode names.
if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "PingPong"
elsif spatial_mode = 3
    spatial_name$ = "Rotating"
else
    spatial_name$ = "DualBandAM"
endif

# ============================================================
# RANDOM WALK ON FREQUENCY LATTICE
# ============================================================
uid$ = string$(randomInteger(10000, 99999))
stepsPerChunk = 20

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

currentIndex = 0
requestedUpCount = 0
requestedDownCount = 0
holdCount = 0
appliedUpCount = 0
appliedDownCount = 0
reflectionCount = 0

for st to totalSteps
    stepTime[st] = (st - 1) * stepDuration
    stepIndex[st] = currentIndex
    stepFreq[st] = base_frequency_Hz + currentIndex * frequency_step_Hz

    requestedDirection[st] = 0
    appliedDirection[st] = 0
    reflectedStep[st] = 0

    if st < totalSteps
        r = randomUniform(0, 1)
        if r < probability_up
            requestedDirection[st] = 1
            requestedUpCount = requestedUpCount + 1
        elsif r < probability_up + probability_down
            requestedDirection[st] = -1
            requestedDownCount = requestedDownCount + 1
        else
            requestedDirection[st] = 0
            holdCount = holdCount + 1
        endif

        if requestedDirection[st] = 1
            if currentIndex < maxIndex
                currentIndex = currentIndex + 1
                appliedDirection[st] = 1
                appliedUpCount = appliedUpCount + 1
            else
                # Reflect an outward request inward; do not clamp/hold.
                currentIndex = currentIndex - 1
                appliedDirection[st] = -1
                reflectedStep[st] = 1
                reflectionCount = reflectionCount + 1
                appliedDownCount = appliedDownCount + 1
            endif
        elsif requestedDirection[st] = -1
            if currentIndex > minIndex
                currentIndex = currentIndex - 1
                appliedDirection[st] = -1
                appliedDownCount = appliedDownCount + 1
            else
                currentIndex = currentIndex + 1
                appliedDirection[st] = 1
                reflectedStep[st] = 1
                reflectionCount = reflectionCount + 1
                appliedUpCount = appliedUpCount + 1
            endif
        endif
    endif
endfor

if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

transitionCount = max(0, totalSteps - 1)
if transitionCount > 0
    realizedUpRequest = requestedUpCount / transitionCount
    realizedDownRequest = requestedDownCount / transitionCount
    realizedHold = holdCount / transitionCount
    realizedMove = (requestedUpCount + requestedDownCount) / transitionCount
else
    realizedUpRequest = 0
    realizedDownRequest = 0
    realizedHold = 0
    realizedMove = 0
endif

minRealFreq = stepFreq[1]
maxRealFreq = stepFreq[1]
for st from 2 to totalSteps
    if stepFreq[st] < minRealFreq
        minRealFreq = stepFreq[st]
    endif
    if stepFreq[st] > maxRealFreq
        maxRealFreq = stepFreq[st]
    endif
endfor

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== Random Walk Rhythm v0.4.1 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Timing grid: ", tempo_bpm, " BPM x ", steps_per_beat, " steps/beat = ", fixed$(stepDuration, 5), " s/step"
appendInfoLine: "Events: ", totalSteps, " | event fill: ", fixed$(event_fill, 3), " | event duration: ", fixed$(eventDuration, 5), " s"
appendInfoLine: "Frequency lattice: ", fixed$(latticeMinFreq, 2), "..", fixed$(latticeMaxFreq, 2), " Hz in ", fixed$(frequency_step_Hz, 2), " Hz steps"
appendInfoLine: "Realized frequency range: ", fixed$(minRealFreq, 2), "..", fixed$(maxRealFreq, 2), " Hz"
appendInfoLine: "Target P(up/down/hold): ", fixed$(probability_up, 3), "/", fixed$(probability_down, 3), "/", fixed$(hold_probability, 3)
appendInfoLine: "Realized requested P(up/down/hold): ", fixed$(realizedUpRequest, 3), "/", fixed$(realizedDownRequest, 3), "/", fixed$(realizedHold, 3)
appendInfoLine: "Boundary reflections: ", reflectionCount
appendInfoLine: "Spatial mode: ", spatial_name$
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed: unpredictable"
endif
appendInfoLine: ""

# ============================================================
# SYNTHESIS: LOCAL-PHASE PERCUSSIVE EVENTS
# ============================================================
monoSound = Create Sound from formula: "mono_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
nChunks = ceiling(totalSteps / stepsPerChunk)

for chunk to nChunks
    startStep = (chunk - 1) * stepsPerChunk + 1
    endStep = min(chunk * stepsPerChunk, totalSteps)
    chunkFormula$ = ""

    for st from startStep to endStep
        t = stepTime[st]
        d = min(eventDuration, duration_s - t)

        if d * sample_rate_Hz >= 2
            t$ = fixed$(t, 9)
            d$ = fixed$(d, 9)
            f$ = fixed$(stepFreq[st], 6)
            decay$ = fixed$(decay_rate, 6)

            # tau = x-t. Local phase starts at zero. Exponential decay gives
            # the percussive shape; the half-cosine closure guarantees an
            # exact zero at the event boundary.
            term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then sin(2*pi*" + f$ + "*(x-" + t$ + ")) * exp(-" + decay$ + "*(x-" + t$ + ")/" + d$ + ") * (1+cos(pi*(x-" + t$ + ")/" + d$ + "))/2 else 0 fi"

            if chunkFormula$ = ""
                chunkFormula$ = term$
            else
                chunkFormula$ = chunkFormula$ + " + " + term$
            endif
        endif
    endfor

    if chunkFormula$ <> ""
        selectObject: monoSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
endfor

# ============================================================
# SPATIALIZATION
# ============================================================
if spatial_mode = 1
    selectObject: monoSound
    outputSound = monoSound
    Rename: "walk_rhythm_" + preset_name$

elsif spatial_mode = 2
    # True ping-pong: alternate complete events between L and R. Because the
    # event duration never exceeds one grid step, the grid index is an exact
    # routing key and does not cut overlapping events.
    stepDur$ = fixed$(stepDuration, 12)

    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * if floor(x/" + stepDur$ + ") - 2*floor(floor(x/" + stepDur$ + ")/2) = 0 then 1 else 0 fi"

    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * if floor(x/" + stepDur$ + ") - 2*floor(floor(x/" + stepDur$ + ")/2) = 1 then 1 else 0 fi"

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "walk_rhythm_" + preset_name$ + "_pingpong"
    removeObject: leftSound, rightSound, monoSound

elsif spatial_mode = 3
    # Constant-power panorama. One complete L->R->L excursion occupies
    # 1/rotation_cycles_per_beat beats.
    rotationRate = beatsPerSecond * rotation_cycles_per_beat
    rotRate$ = fixed$(rotationRate, 9)

    selectObject: monoSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * cos(pi/4 * (1 + sin(2*pi*" + rotRate$ + "*x)))"

    selectObject: monoSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sin(pi/4 * (1 + sin(2*pi*" + rotRate$ + "*x)))"

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "walk_rhythm_" + preset_name$ + "_rotating"
    removeObject: leftSound, rightSound, monoSound

else
    # Legacy "Binaural Rhythm" was not a binaural-beat generator; it was the
    # same pulse stream processed differently in the two channels. Keep that
    # useful process, but name it accurately as dual-band AM.
    leftLow = 80
    leftHigh = min(2500, 0.90 * nyquist)
    rightLow = 120
    rightHigh = min(4000, 0.90 * nyquist)

    selectObject: monoSound
    Copy: "left_" + uid$
    leftRaw = selected("Sound")
    Filter (pass Hann band): leftLow, leftHigh, 80
    leftSound = selected("Sound")
    Formula: "self * (0.8 + 0.1 * sin(2*pi*0.3*x))"
    removeObject: leftRaw

    selectObject: monoSound
    Copy: "right_" + uid$
    rightRaw = selected("Sound")
    Filter (pass Hann band): rightLow, rightHigh, 80
    rightSound = selected("Sound")
    Formula: "self * (0.7 + 0.2 * cos(2*pi*0.4*x))"
    removeObject: rightRaw

    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "walk_rhythm_" + preset_name$ + "_dualband"
    removeObject: leftSound, rightSound, monoSound
endif

# One final level operation. Event kernels already have smooth boundaries.
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0
if preNormPeak > 0
    Scale peak: output_peak
endif
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

appendInfoLine: "Output pre-normalization peak/RMS: ", fixed$(preNormPeak, 4), " / ", fixed$(preNormRMS, 4)
appendInfoLine: "Output final peak/RMS: ", fixed$(finalPeak, 4), " / ", fixed$(finalRMS, 4)

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    Erase all

    # Every title/text strip selects its own INNER viewport. Praat Picture
    # retains viewport state, so this prevents inherited axes/text collisions.

    # ---------------- Title strip ----------------
    Select outer viewport: 0, 8, 0.04, 0.34
    Select inner viewport: 0.20, 7.80, 0.06, 0.31
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Random Walk Rhythm: " + preset_name$

    # ---------------- Process strip ----------------
    Select outer viewport: 0, 8, 0.36, 0.62
    Select inner viewport: 0.25, 7.75, 0.39, 0.59
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.50, "half", "categorical up/down/hold  ->  reflect at bounds  ->  frequency lattice  ->  fixed timing grid  ->  decaying pulse  ->  spatial map  ->  sum"

    # ---------------- Panel A title ----------------
    Select outer viewport: 0, 8, 0.68, 0.88
    Select inner viewport: 0.10, 7.90, 0.70, 0.86
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "A  Walk decisions: requested direction; reflected requests cross to the opposite applied step"

    # ---------------- Panel A: categorical decisions ----------------
    Select outer viewport: 0, 8, 0.90, 2.18
    Select inner viewport: 0.78, 7.62, 1.00, 1.98
    Axes: 0, duration_s, -1.45, 1.45
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, -1.45, 1.45
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0, 0, duration_s, 0

    if transitionCount > 0
        for .st to transitionCount
            .tx = stepTime[.st] + stepDuration
            if .tx > duration_s
                .tx = duration_s
            endif
            .req = requestedDirection[.st]
            .app = appliedDirection[.st]

            if .req = 0
                Paint circle (mm): "{0.45, 0.45, 0.45}", .tx, 0, 1.15
            else
                Colour: "{0.70, 0.70, 0.70}"
                Draw line: .tx, 0, .tx, .req
                Paint circle (mm): "{0.70, 0.70, 0.70}", .tx, .req, 0.95

                if .app > 0
                    Colour: "{0.18, 0.48, 0.76}"
                else
                    Colour: "{0.78, 0.38, 0.20}"
                endif

                if reflectedStep[.st] = 1
                    Line width: 1.5
                    Draw line: .tx, .req, .tx, .app
                    Line width: 1
                endif
                Paint circle (mm): "{0.25, 0.25, 0.25}", .tx, .app, 1.10
            endif
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 1.00, 1.98
    Axes: 0, duration_s, -1.45, 1.45
    Font size: 8
    Marks left every: 1, 1, "yes", "yes", "no"
    Marks bottom every: 1, max(stepDuration, duration_s / 6), "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Direction"
    Text bottom: "yes", "Transition time (s)"

    # ---------------- Panel B title ----------------
    Select outer viewport: 0, 8, 2.30, 2.50
    Select inner viewport: 0.10, 7.90, 2.32, 2.48
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "B  Frequency state: fixed Hz step on a bounded lattice; reflection prevents clamp-induced edge holds"

    # ---------------- Panel B: frequency trajectory ----------------
    Select outer viewport: 0, 8, 2.52, 3.74
    Select inner viewport: 0.78, 7.62, 2.62, 3.54
    .ypad = max(10, 0.05 * (latticeMaxFreq - latticeMinFreq))
    .ymin = latticeMinFreq - .ypad
    .ymax = latticeMaxFreq + .ypad
    Axes: 0, duration_s, .ymin, .ymax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, .ymin, .ymax

    Colour: "{0.78, 0.78, 0.78}"
    Dotted line
    Draw line: 0, latticeMinFreq, duration_s, latticeMinFreq
    Draw line: 0, latticeMaxFreq, duration_s, latticeMaxFreq
    Colour: "{0.60, 0.60, 0.60}"
    Draw line: 0, base_frequency_Hz, duration_s, base_frequency_Hz
    Solid line

    Colour: "{0.18, 0.48, 0.76}"
    Line width: 1.5
    for .st to totalSteps
        .t1 = stepTime[.st]
        .t2 = min(duration_s, .t1 + stepDuration)
        Draw line: .t1, stepFreq[.st], .t2, stepFreq[.st]
        if .st < totalSteps
            Draw line: .t2, stepFreq[.st], .t2, stepFreq[.st + 1]
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 2.62, 3.54
    Axes: 0, duration_s, .ymin, .ymax
    Font size: 8
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, max(stepDuration, duration_s / 6), "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # ---------------- Panel C title ----------------
    Select outer viewport: 0, 8, 3.86, 4.06
    Select inner viewport: 0.10, 7.90, 3.88, 4.04
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "C  Event timing/kernel and selected spatial mapping"

    # ---------------- Panel C-left: grid step + event envelope ----------------
    Select outer viewport: 0, 4.0, 4.08, 5.36
    Select inner viewport: 0.78, 3.75, 4.18, 5.16
    Axes: 0, stepDuration, 0, 1.05
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, stepDuration, 0, 1.05
    Colour: "{0.88, 0.88, 0.88}"
    Paint rectangle: "{0.88, 0.88, 0.88}", eventDuration, stepDuration, 0, 1.05

    .segments = 180
    .prevT = 0
    .prevEnv = 1
    Colour: "{0.18, 0.48, 0.76}"
    Line width: 1.5
    for .k from 1 to .segments
        .kt = .k * eventDuration / .segments
        .env = exp(-decay_rate * .kt / eventDuration) * (1 + cos(pi * .kt / eventDuration)) / 2
        Draw line: .prevT, .prevEnv, .kt, .env
        .prevT = .kt
        .prevEnv = .env
    endfor
    Line width: 1
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: eventDuration, 0, eventDuration, 1.05
    Solid line

    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 3.75, 4.18, 5.16
    Axes: 0, stepDuration, 0, 1.05
    Font size: 8
    Marks bottom: 3, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Local grid-step time (s)"
    Text left: "yes", "Event envelope"

    # ---------------- Panel C-right: spatial gain map ----------------
    Select outer viewport: 4.0, 8, 4.08, 5.36
    Select inner viewport: 4.28, 7.62, 4.18, 5.16
    .spaceDur = min(duration_s, max(2 * stepDuration, 4 / beatsPerSecond))
    Axes: 0, .spaceDur, 0, 1.08
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, .spaceDur, 0, 1.08

    if spatial_mode = 1
        Colour: "{0.18, 0.48, 0.76}"
        Line width: 1.5
        Draw line: 0, 1, .spaceDur, 1
        Line width: 1
    elsif spatial_mode = 2
        .showSteps = min(totalSteps, floor(.spaceDur / stepDuration) + 1)
        for .st to .showSteps
            .tx = stepTime[.st]
            if .tx <= .spaceDur
                if .st - 2 * floor(.st / 2) = 1
                    Colour: "{0.18, 0.48, 0.76}"
                    Draw line: .tx, 0, .tx, 1
                    Paint circle (mm): "{0.18, 0.48, 0.76}", .tx, 1, 1.1
                    Paint circle (mm): "{0.78, 0.38, 0.20}", .tx, 0, 0.8
                else
                    Colour: "{0.78, 0.38, 0.20}"
                    Draw line: .tx, 0, .tx, 1
                    Paint circle (mm): "{0.78, 0.38, 0.20}", .tx, 1, 1.1
                    Paint circle (mm): "{0.18, 0.48, 0.76}", .tx, 0, 0.8
                endif
            endif
        endfor
    elsif spatial_mode = 3
        .segments2 = 180
        .prevT2 = 0
        .p0 = 0.5 + 0.5 * sin(0)
        .prevL = cos(pi/2 * .p0)
        .prevR = sin(pi/2 * .p0)
        for .k from 1 to .segments2
            .kt2 = .k * .spaceDur / .segments2
            .pan = 0.5 + 0.5 * sin(2 * pi * beatsPerSecond * rotation_cycles_per_beat * .kt2)
            .gL = cos(pi/2 * .pan)
            .gR = sin(pi/2 * .pan)
            Colour: "{0.18, 0.48, 0.76}"
            Draw line: .prevT2, .prevL, .kt2, .gL
            Colour: "{0.78, 0.38, 0.20}"
            Draw line: .prevT2, .prevR, .kt2, .gR
            .prevT2 = .kt2
            .prevL = .gL
            .prevR = .gR
        endfor
    else
        .segments2 = 180
        .prevT2 = 0
        .prevL = 0.8
        .prevR = 0.9
        for .k from 1 to .segments2
            .kt2 = .k * .spaceDur / .segments2
            .gL = 0.8 + 0.1 * sin(2*pi*0.3*.kt2)
            .gR = 0.7 + 0.2 * cos(2*pi*0.4*.kt2)
            Colour: "{0.18, 0.48, 0.76}"
            Draw line: .prevT2, .prevL, .kt2, .gL
            Colour: "{0.78, 0.38, 0.20}"
            Draw line: .prevT2, .prevR, .kt2, .gR
            .prevT2 = .kt2
            .prevL = .gL
            .prevR = .gR
        endfor
    endif

    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.28, 7.62, 4.18, 5.16
    Axes: 0, .spaceDur, 0, 1.08
    Font size: 8
    Marks bottom: 4, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Channel gain"

    # Formula / interpretation strip for Panel C.
    Select outer viewport: 0, 8, 5.38, 5.54
    Select inner viewport: 0.22, 7.78, 5.40, 5.52
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    if spatial_mode = 1
        .spaceText$ = "mono"
    elsif spatial_mode = 2
        .spaceText$ = "ping-pong: odd events -> L, even events -> R"
    elsif spatial_mode = 3
        .spaceText$ = "constant-power pan: gL^2 + gR^2 = 1"
    else
        .spaceText$ = "dual-band AM: L 80.." + fixed$(leftHigh,0) + " Hz; R 120.." + fixed$(rightHigh,0) + " Hz"
    endif
    Text: 0.5, "centre", 0.50, "half", "event: sin(2*pi*f*tau) * exp(-a*tau/D) * (1+cos(pi*tau/D))/2   |   " + .spaceText$

    # ---------------- Panel D title ----------------
    Select outer viewport: 0, 8, 5.64, 5.84
    Select inner viewport: 0.10, 7.90, 5.66, 5.82
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "D  Measured output (verification only)"

    selectObject: outputSound
    .nCh = Get number of channels

    if .nCh = 1
        Select outer viewport: 0, 8, 5.86, 6.92
        Select inner viewport: 0.78, 7.62, 5.96, 6.72
        Axes: 0, duration_s, -1, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, -1, 1
        selectObject: outputSound
        Colour: "{0.18, 0.48, 0.76}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        Select inner viewport: 0.78, 7.62, 5.96, 6.72
        Axes: 0, duration_s, -1, 1
        Colour: "Black"
        Draw inner box
        Select inner viewport: 0.78, 7.62, 5.96, 6.72
        Axes: 0, duration_s, -1, 1
        Font size: 8
        Marks left: 3, "yes", "yes", "no"
        Marks bottom every: 1, max(stepDuration, duration_s / 6), "yes", "yes", "no"
        Font size: 9
        Text left: "yes", "Amplitude"
        Text bottom: "yes", "Time (s)"
    else
        # Stereo: show channels separately to avoid cancellation/overlay ambiguity.
        Select outer viewport: 0, 8, 5.86, 6.38
        Select inner viewport: 0.78, 7.62, 5.92, 6.28
        Axes: 0, duration_s, -1, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, -1, 1
        selectObject: outputSound
        Extract one channel: 1
        .leftViz = selected("Sound")
        Colour: "{0.18, 0.48, 0.76}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        removeObject: .leftViz
        Select inner viewport: 0.78, 7.62, 5.92, 6.28
        Axes: 0, duration_s, -1, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "L"

        Select outer viewport: 0, 8, 6.40, 6.92
        Select inner viewport: 0.78, 7.62, 6.46, 6.82
        Axes: 0, duration_s, -1, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, -1, 1
        selectObject: outputSound
        Extract one channel: 2
        .rightViz = selected("Sound")
        Colour: "{0.78, 0.38, 0.20}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        removeObject: .rightViz
        Select inner viewport: 0.78, 7.62, 6.46, 6.82
        Axes: 0, duration_s, -1, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "R"
        Marks bottom every: 1, max(stepDuration, duration_s / 6), "yes", "yes", "no"
        Font size: 8
        Text bottom: "yes", "Time (s)"
    endif

    # ---------------- QC summary bar ----------------
    Select outer viewport: 0, 8, 7.08, 7.88
    Select inner viewport: 0.18, 7.82, 7.11, 7.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.18, 7.82, 7.11, 7.85
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.69, "half", "GRID  " + fixed$(tempo_bpm,1) + " BPM | step " + fixed$(1000*stepDuration,1) + " ms | fill " + fixed$(event_fill,2) + " | N " + string$(totalSteps)
    Text: 0.34, "left", 0.69, "half", "DRAW p  up/down/hold " + fixed$(probability_up,2) + "/" + fixed$(probability_down,2) + "/" + fixed$(hold_probability,2)
    Text: 0.68, "left", 0.69, "half", "REAL p  " + fixed$(realizedUpRequest,2) + "/" + fixed$(realizedDownRequest,2) + "/" + fixed$(realizedHold,2) + " | refl " + string$(reflectionCount)
    Text: 0.02, "left", 0.25, "half", "FREQ  lattice " + fixed$(latticeMinFreq,0) + ".." + fixed$(latticeMaxFreq,0) + " | used " + fixed$(minRealFreq,0) + ".." + fixed$(maxRealFreq,0) + " Hz"
    Text: 0.34, "left", 0.25, "half", "KERNEL  D " + fixed$(1000*eventDuration,1) + " ms | decay " + fixed$(decay_rate,1) + " | local phase"
    Text: 0.68, "left", 0.25, "half", "OUT  " + spatial_name$ + " | peak/RMS " + fixed$(finalPeak,3) + "/" + fixed$(finalRMS,3)

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
