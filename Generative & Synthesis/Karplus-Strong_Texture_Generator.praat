# ============================================================
# Praat AudioTools - Karplus-Strong_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# KARPLUS-STRONG TEXTURE GENERATOR
#
# A two-level design:
#
#   LEVEL 1 - PLUCKED-STRING RESONATOR
#   ----------------------------------
#   Each note is a Karplus-Strong / digital-waveguide-like feedback loop.
#   The loop uses two independent ingredients:
#
#     a) brightness loss filter
#          B(z) = (1-S) + S z^-1
#          S = 0.5*(1-Brightness)
#
#        Brightness=0 -> canonical two-point average (S=.5)
#        Brightness=1 -> no additional averaging loss (S=0)
#
#     b) fractional-delay interpolator
#          F(z) = (1-r) + r z^-1
#
#   Cascading these gives a compact 3-tap loop recurrence:
#
#     y[n] = rho * (a0*y[n-N] + a1*y[n-N-1] + a2*y[n-N-2])
#
#     a0 = (1-S)(1-r)
#     a1 = (1-S)r + S(1-r)
#     a2 = Sr
#
#   where rho=Damping. N and r are chosen so the LOW-FREQUENCY phase
#   delay N+r+S equals Fs/f0. This decouples tuning compensation from the
#   brightness control much better than v0.3, where changing Brightness also
#   changed the effective pitch.
#
#   This is an efficient extended KS approximation. It does NOT claim to be a
#   complete physical string model: stiffness/dispersion, body resonances,
#   pickup position and nonlinear bridge coupling are not simulated.
#
#   The excitation is a seeded white-noise section inside the initial delay
#   buffer. Excitation_fill=1 is closest to the classic full random buffer;
#   smaller values create a more localized/windowed excitation. This parameter
#   is therefore described as BUFFER FILL, not as literal pluck position.
#
#   LEVEL 2 - TEXTURE SCHEDULER
#   ---------------------------
#   Unlike v0.3, the presets labelled stream/strum/cascade/drone/cloud now
#   genuinely generate multiple KS events. Texture_mode controls the schedule:
#
#     Single Pluck
#     Regular Re-plucks
#     Poisson Pluck Stream
#     Strummed Cluster
#     Ascending Cascade
#     Re-excited Drone
#
#   Event tails are estimated from the fundamental loop decay and capped by
#   Max_tail_s. Mixing gain is compensated from the ACTUAL scheduled overlap.
#
# v0.4 reviewed:
#   - true texture/event layer instead of misleading single-pluck presets
#   - mechanism-faithful preset names
#   - fractional-delay compensation separated from brightness filter
#   - pitch no longer uses round(Fs/f) blindly
#   - one recursive Formula pass per KS voice (left-to-right Praat Formula)
#     instead of hundreds of delay-period Formula(part) passes
#   - classic full-buffer excitation available as Excitation_fill=1
#   - explicit Random_seed and reproducible event/excitation generation
#   - real regular / Poisson / strum / cascade / drone schedules
#   - event-level equal-power stereo spread
#   - correlated detuned stereo uses one shared excitation per event
#   - micro-delay stereo reads from the original mono voice, not in-place self
#   - fixed object access syntax and Combine-to-stereo assignment pattern
#   - validation for stability, delay length and frequency headroom
#   - one final down-only peak protector; no unconditional normalization
#   - visualization shows the algorithm rather than only decoration:
#       A actual scheduled event field
#       B loop gain per round trip for the first event
#       C measured first-event decay vs theoretical f0 / 5th-partial decay
#       D measured output spectrogram + actual event-fundamental guides
#       bottom tuning / overlap / level / process QC
#
# Conceptual references:
#   Karplus & Strong (1983), Digital Synthesis of Plucked-String and Drum Timbres
#   Jaffe & Smith (1983), Extensions of the Karplus-Strong Plucked-String Algorithm
# ============================================================

form Karplus-Strong Texture Generator v0.4
    optionmenu Preset 1
        option Custom
        option Canonical Single Pluck
        option Warm Re-pluck Stream
        option Ascending String Cascade
        option Long Metallic Pluck
        option Re-excited Low Drone
        option Bright Short Pluck
        option Detuned Shimmer Pair
        option Prepared Detuned Cluster
        option Sparse Resonant Cloud

    positive Duration_s 6.0
    integer Sample_rate_Hz 44100
    positive Base_pitch_Hz 220

    optionmenu Texture_mode 1
        option Single Pluck
        option Regular Re-plucks
        option Poisson Pluck Stream
        option Strummed Cluster
        option Ascending Cascade
        option Re-excited Drone

    real Damping 0.996
    real Brightness 0.35
    real Excitation_fill 1.0

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Event Spread
        option Stereo Detuned Pair
        option Stereo Micro-Delay

    boolean Edit_texture_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
event_rate_Hz = 2.0
voice_count = 7
pitch_span_semitones = 12.0
pitch_jitter_cents = 4.0
strum_span_ms = 180
max_tail_s = 6.0
detune_cents = 7.0
micro_delay_ms = 8.0
random_seed = 0

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    duration_s = 4
    base_pitch_Hz = 220
    texture_mode = 1
    damping = 0.996
    brightness = 0.0
    excitation_fill = 1.0
    spatial_mode = 1
    max_tail_s = 4
    preset_name$ = "Canonical Single Pluck"

elsif preset = 3
    duration_s = 10
    base_pitch_Hz = 110
    texture_mode = 2
    damping = 0.995
    brightness = 0.35
    excitation_fill = 0.90
    event_rate_Hz = 1.8
    pitch_jitter_cents = 5
    spatial_mode = 2
    max_tail_s = 4.5
    preset_name$ = "Warm Re-pluck Stream"

elsif preset = 4
    duration_s = 9
    base_pitch_Hz = 220
    texture_mode = 5
    damping = 0.9975
    brightness = 0.28
    excitation_fill = 1.0
    voice_count = 10
    pitch_span_semitones = 19
    event_rate_Hz = 1.5
    pitch_jitter_cents = 2
    spatial_mode = 2
    max_tail_s = 5
    preset_name$ = "Ascending String Cascade"

elsif preset = 5
    duration_s = 6
    base_pitch_Hz = 330
    texture_mode = 1
    damping = 0.9993
    brightness = 0.84
    excitation_fill = 0.70
    spatial_mode = 1
    max_tail_s = 6
    preset_name$ = "Long Metallic Pluck"

elsif preset = 6
    duration_s = 14
    base_pitch_Hz = 130
    texture_mode = 6
    damping = 0.9982
    brightness = 0.32
    excitation_fill = 0.85
    event_rate_Hz = 0.72
    pitch_jitter_cents = 2.5
    spatial_mode = 3
    detune_cents = 3.5
    max_tail_s = 7
    preset_name$ = "Re-excited Low Drone"

elsif preset = 7
    duration_s = 3
    base_pitch_Hz = 294
    texture_mode = 1
    damping = 0.990
    brightness = 0.92
    excitation_fill = 0.75
    spatial_mode = 1
    max_tail_s = 3
    preset_name$ = "Bright Short Pluck"

elsif preset = 8
    duration_s = 8
    base_pitch_Hz = 392
    texture_mode = 1
    damping = 0.9985
    brightness = 0.42
    excitation_fill = 1.0
    spatial_mode = 3
    detune_cents = 8.6
    max_tail_s = 8
    preset_name$ = "Detuned Shimmer Pair"

elsif preset = 9
    duration_s = 8
    base_pitch_Hz = 185
    texture_mode = 4
    damping = 0.994
    brightness = 0.55
    excitation_fill = 0.62
    voice_count = 8
    pitch_span_semitones = 9
    strum_span_ms = 260
    pitch_jitter_cents = 8
    spatial_mode = 2
    max_tail_s = 5
    preset_name$ = "Prepared Detuned Cluster"

elsif preset = 10
    duration_s = 18
    base_pitch_Hz = 261
    texture_mode = 3
    damping = 0.9997
    brightness = 0.22
    excitation_fill = 1.0
    event_rate_Hz = 0.42
    pitch_span_semitones = 7
    pitch_jitter_cents = 14
    spatial_mode = 4
    micro_delay_ms = 11
    max_tail_s = 8
    preset_name$ = "Sparse Resonant Cloud"
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_texture_details
    beginPause: "Karplus-Strong Texture - Scheduler / Spatial Details"
        positive: "Event rate (events/s)", event_rate_Hz
        integer: "Voice/event count", voice_count
        real: "Pitch span (semitones)", pitch_span_semitones
        real: "Pitch jitter (cents)", pitch_jitter_cents
        real: "Strum span (ms)", strum_span_ms
        positive: "Maximum event tail (s)", max_tail_s
        real: "Stereo detune (cents)", detune_cents
        real: "Micro-delay (ms)", micro_delay_ms
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# VALIDATION / LABELS
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if base_pitch_Hz < 20
    exitScript: "Base pitch must be at least 20 Hz."
endif
if damping <= 0 or damping >= 1
    exitScript: "Damping must be greater than 0 and strictly less than 1."
endif
if brightness < 0 or brightness > 1
    exitScript: "Brightness must be between 0 and 1."
endif
if excitation_fill <= 0 or excitation_fill > 1
    exitScript: "Excitation fill must be > 0 and <= 1."
endif
if event_rate_Hz <= 0 or event_rate_Hz > 40
    exitScript: "Event rate must be > 0 and <= 40 events/s."
endif
if voice_count < 1 or voice_count > 32
    exitScript: "Voice/event count must be between 1 and 32."
endif
if pitch_span_semitones < 0 or pitch_span_semitones > 48
    exitScript: "Pitch span must be between 0 and 48 semitones."
endif
if abs(pitch_jitter_cents) > 200
    exitScript: "Pitch jitter must not exceed 200 cents."
endif
if strum_span_ms < 0 or strum_span_ms > 5000
    exitScript: "Strum span must be between 0 and 5000 ms."
endif
if max_tail_s <= 0 or max_tail_s > 30
    exitScript: "Maximum event tail must be > 0 and <= 30 seconds."
endif
if abs(detune_cents) > 100
    exitScript: "Stereo detune must not exceed 100 cents."
endif
if micro_delay_ms < 0 or micro_delay_ms > 40
    exitScript: "Micro-delay must be between 0 and 40 ms."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if texture_mode = 1
    texture_name$ = "Single Pluck"
elsif texture_mode = 2
    texture_name$ = "Regular Re-plucks"
elsif texture_mode = 3
    texture_name$ = "Poisson Pluck Stream"
elsif texture_mode = 4
    texture_name$ = "Strummed Cluster"
elsif texture_mode = 5
    texture_name$ = "Ascending Cascade"
else
    texture_name$ = "Re-excited Drone"
endif

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "Stereo Event Spread"
elsif spatial_mode = 3
    spatial_name$ = "Stereo Detuned Pair"
else
    spatial_name$ = "Stereo Micro-Delay"
endif

sr = sample_rate_Hz
safeTop = 0.20*sr
uid$ = string$(randomInteger(10000,99999))

# Conservative maximum scheduled pitch.
if texture_mode = 4 or texture_mode = 5
    maxScheduledPitch = base_pitch_Hz*2^(0.5*pitch_span_semitones/12)
else
    maxScheduledPitch = base_pitch_Hz*2^(abs(pitch_jitter_cents)/1200)
endif
if spatial_mode = 3
    maxScheduledPitch = maxScheduledPitch*2^(abs(detune_cents)/1200)
endif

if maxScheduledPitch > safeTop
    exitScript: "Highest scheduled pitch exceeds 0.20*sample rate. Reduce pitch/span/detune or increase sample rate."
endif

# ---------------------------------------------------------------------------
# RANDOMNESS
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seed_label$ = "seed " + string$(random_seed)
else
    seed_label$ = "seed random"
endif

# ---------------------------------------------------------------------------
# LOOP MODEL HELPER
# ---------------------------------------------------------------------------
procedure computeLoop: .pitchHz
    .s = 0.5*(1-brightness)
    .desiredDelay = sample_rate_Hz/.pitchHz

    # Low-frequency phase delay of brightness filter is approximately S.
    # Put the remaining fractional delay into an independent linear
    # interpolator, so brightness does not silently retune the note.
    .n = floor(.desiredDelay-.s)
    .frac = .desiredDelay-.s-.n

    if .n < 3
        exitScript: "Pitch is too high for a stable/meaningful KS delay at this sample rate."
    endif

    .a0 = (1-.s)*(1-.frac)
    .a1 = (1-.s)*.frac+.s*(1-.frac)
    .a2 = .s*.frac

    # Fundamental and 5th-partial theoretical loop decay.
    .w1 = 2*pi*.pitchHz/sample_rate_Hz
    .mB1 = sqrt(((1-.s)+.s*cos(.w1))^2+(.s*sin(.w1))^2)
    .mF1 = sqrt(((1-.frac)+.frac*cos(.w1))^2+(.frac*sin(.w1))^2)
    .g1 = damping*.mB1*.mF1
    .decay1 = .pitchHz*20*log10(max(1e-12,.g1))

    .f5 = min(5*.pitchHz,0.45*sample_rate_Hz)
    .w5 = 2*pi*.f5/sample_rate_Hz
    .mB5 = sqrt(((1-.s)+.s*cos(.w5))^2+(.s*sin(.w5))^2)
    .mF5 = sqrt(((1-.frac)+.frac*cos(.w5))^2+(.frac*sin(.w5))^2)
    .g5 = damping*.mB5*.mF5
    .decay5 = .pitchHz*20*log10(max(1e-12,.g5))

    if .decay1 < -0.000001
        .t60 = -60/.decay1
    else
        .t60 = 999
    endif
endproc

# ---------------------------------------------------------------------------
# SCHEDULE ACTUAL EVENTS
# ---------------------------------------------------------------------------
eventCount = 0

if texture_mode = 1
    eventCount = 1
    eventOnset[1] = 0
    eventPitch[1] = base_pitch_Hz
    eventWeight[1] = 1

elsif texture_mode = 2
    t = 0
    while t < duration_s and eventCount < 64
        eventCount = eventCount+1
        eventOnset[eventCount] = t
        eventPitch[eventCount] = base_pitch_Hz*
            ... 2^(randomUniform(-pitch_jitter_cents,pitch_jitter_cents)/1200)
        eventWeight[eventCount] = randomUniform(0.88,1.08)
        t = t+1/event_rate_Hz
    endwhile

elsif texture_mode = 3
    t = 0
    while t < duration_s and eventCount < 64
        u = max(1e-12,randomUniform(0,1))
        t = t-ln(u)/event_rate_Hz
        if t < duration_s
            eventCount = eventCount+1
            eventOnset[eventCount] = t
            # Cloud uses both jitter and the requested pitch span.
            spread = 0.5*pitch_span_semitones
            eventPitch[eventCount] = base_pitch_Hz*
                ... 2^(randomUniform(-spread,spread)/12)*
                ... 2^(randomUniform(-pitch_jitter_cents,pitch_jitter_cents)/1200)
            eventWeight[eventCount] = randomUniform(0.78,1.10)
        endif
    endwhile

elsif texture_mode = 4
    eventCount = voice_count
    for ev from 1 to eventCount
        if eventCount = 1
            pos = 0.5
        else
            pos = (ev-1)/(eventCount-1)
        endif
        eventOnset[ev] = (strum_span_ms/1000)*pos
        semis = (pos-0.5)*pitch_span_semitones
        eventPitch[ev] = base_pitch_Hz*2^(semis/12)*
            ... 2^(randomUniform(-pitch_jitter_cents,pitch_jitter_cents)/1200)
        eventWeight[ev] = 0.90+0.10*sin(pi*pos)
    endfor

elsif texture_mode = 5
    eventCount = voice_count
    cascadeSpan = min(0.78*duration_s,max(0.5,(voice_count-1)/event_rate_Hz))
    for ev from 1 to eventCount
        if eventCount = 1
            pos = 0.5
        else
            pos = (ev-1)/(eventCount-1)
        endif
        eventOnset[ev] = cascadeSpan*pos
        semis = (pos-0.5)*pitch_span_semitones
        eventPitch[ev] = base_pitch_Hz*2^(semis/12)*
            ... 2^(randomUniform(-pitch_jitter_cents,pitch_jitter_cents)/1200)
        eventWeight[ev] = 0.82+0.18*pos
    endfor

else
    t = 0
    while t < duration_s and eventCount < 64
        eventCount = eventCount+1
        eventOnset[eventCount] = t
        eventPitch[eventCount] = base_pitch_Hz*
            ... 2^(randomUniform(-pitch_jitter_cents,pitch_jitter_cents)/1200)
        eventWeight[eventCount] = randomUniform(0.72,1.0)
        t = t+1/event_rate_Hz
    endwhile
endif

if eventCount < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "No events were scheduled."
endif

# Event-tail estimate and overlap compensation.
sumTail = 0
minEventPitch = 1e9
maxEventPitch = 0

for ev from 1 to eventCount
    @computeLoop: eventPitch[ev]
    remaining = duration_s-eventOnset[ev]
    eventTail[ev] = min(remaining,max(0.20,min(max_tail_s,1.05*computeLoop.t60)))
    sumTail = sumTail+eventTail[ev]
    minEventPitch = min(minEventPitch,eventPitch[ev])
    maxEventPitch = max(maxEventPitch,eventPitch[ev])
endfor

meanOverlap = sumTail/duration_s
eventMixGain = 0.72/sqrt(max(1,meanOverlap))

# First-event model values for info + visualization.
@computeLoop: eventPitch[1]
firstDelayN = computeLoop.n
firstFrac = computeLoop.frac
firstS = computeLoop.s
firstA0 = computeLoop.a0
firstA1 = computeLoop.a1
firstA2 = computeLoop.a2
firstDecay = computeLoop.decay1
firstDecay5 = computeLoop.decay5
firstT60 = computeLoop.t60

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  KARPLUS-STRONG TEXTURE GENERATOR v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Texture: ", texture_name$
appendInfoLine: "Events: ", eventCount
appendInfoLine: "Pitch range: ", fixed$(minEventPitch,2), " - ", fixed$(maxEventPitch,2), " Hz"
appendInfoLine: "Damping / brightness: ", fixed$(damping,5), " / ", fixed$(brightness,3)
appendInfoLine: "Excitation buffer fill: ", fixed$(excitation_fill,3)
appendInfoLine: "First event delay: N=", firstDelayN,
    ... " + frac ", fixed$(firstFrac,5), " + filter delay ~", fixed$(firstS,3)
appendInfoLine: "First-event nominal period samples: ", fixed$(sample_rate_Hz/eventPitch[1],5)
appendInfoLine: "First-event theoretical T60(f0): ", fixed$(firstT60,2), " s"
appendInfoLine: "Actual scheduled mean overlap: ", fixed$(meanOverlap,3)
appendInfoLine: "Overlap compensation gain: ", fixed$(eventMixGain,4)
appendInfoLine: "Spatial: ", spatial_name$
appendInfoLine: "Randomness: ", seed_label$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# OUTPUT ACCUMULATOR
# ---------------------------------------------------------------------------
if spatial_mode = 1
    outputSound = Create Sound from formula:
        ... "ks_texture_" + uid$,1,0,duration_s,sample_rate_Hz,"0"
else
    outputSound = Create Sound from formula:
        ... "ks_texture_" + uid$,2,0,duration_s,sample_rate_Hz,"0"
endif

# ---------------------------------------------------------------------------
# ONE-PASS RECURSIVE KS VOICE
# ---------------------------------------------------------------------------
procedure synthKS: .name$,.pitchHz,.voiceDur,.seedID
    @computeLoop: .pitchHz

    .n = computeLoop.n
    .frac = computeLoop.frac
    .a0 = computeLoop.a0
    .a1 = computeLoop.a1
    .a2 = computeLoop.a2
    .seedN = max(1,round(excitation_fill*.n))

    .out = Create Sound from formula:
        ... .name$,1,0,.voiceDur,sample_rate_Hz,"0"

    if .seedID > 0
        .noiseExpr$ = "object[" + string$(.seedID) + ",1,col]"
    else
        .noiseExpr$ = "randomGauss(0,0.42)"
    endif

    selectObject: .out
    Formula: "if col<=" + string$(.seedN)
        ... + " then " + .noiseExpr$
        ... + " else if col<=" + string$(.n+2)
        ... + " then 0 else " + fixed$(damping,12) + "*("
        ... + fixed$(.a0,12) + "*self[col-" + string$(.n) + "]+"
        ... + fixed$(.a1,12) + "*self[col-" + string$(.n+1) + "]+"
        ... + fixed$(.a2,12) + "*self[col-" + string$(.n+2) + "]) fi fi"

    # Only a very short edge taper. It prevents a hard truncation without
    # imposing a musical envelope on the modeled decay.
    .edge = min(0.008,0.10*.voiceDur)
    if .edge > 0
        .edgeStart = .voiceDur-.edge
        Formula: "if x>" + fixed$(.edgeStart,9)
            ... + " then self*(0.5+0.5*cos(pi*(x-"
            ... + fixed$(.edgeStart,9) + ")/" + fixed$(.edge,9)
            ... + ")) else self fi"
    endif
endproc

# ---------------------------------------------------------------------------
# RENDER / MIX EVENTS
# ---------------------------------------------------------------------------
appendInfoLine: "Rendering one-pass recursive KS events..."
stopwatch
vizVoice = 0

for ev from 1 to eventCount
    onset = eventOnset[ev]
    pitchNow = eventPitch[ev]
    tail = eventTail[ev]
    weight = eventWeight[ev]

    if tail > 1/sample_rate_Hz
        if spatial_mode = 3
            # Correlated detuned pair: one short shared excitation buffer.
            rightPitch = pitchNow*2^(detune_cents/1200)
            @computeLoop: pitchNow
            nL = computeLoop.n
            @computeLoop: rightPitch
            nR = computeLoop.n
            seedSamples = max(nL,nR)+2
            seedDur = seedSamples/sample_rate_Hz

            seedID = Create Sound from formula:
                ... "ks_seed_" + uid$ + "_" + string$(ev),
                ... 1,0,seedDur,sample_rate_Hz,"randomGauss(0,0.42)"

            @synthKS: "ks_L_" + uid$ + "_" + string$(ev),pitchNow,tail,seedID
            leftID = synthKS.out
            @synthKS: "ks_R_" + uid$ + "_" + string$(ev),rightPitch,tail,seedID
            rightID = synthKS.out

            if ev = 1
                selectObject: leftID
                Copy: "ks_first_event_" + uid$
                vizVoice = selected("Sound")
            endif

            t1 = min(duration_s,onset+tail)
            gain = eventMixGain*weight*sqrt(0.5)
            selectObject: outputSound
            Formula (part): onset,t1,1,2,
                ... "self+if row=1 then " + fixed$(gain,9)
                ... + "*object(" + string$(leftID) + ",x-"
                ... + fixed$(onset,9) + ",1) else " + fixed$(gain,9)
                ... + "*object(" + string$(rightID) + ",x-"
                ... + fixed$(onset,9) + ",1) fi"

            removeObject: leftID,rightID,seedID

        else
            @synthKS: "ks_voice_" + uid$ + "_" + string$(ev),pitchNow,tail,0
            voiceID = synthKS.out

            if ev = 1
                selectObject: voiceID
                Copy: "ks_first_event_" + uid$
                vizVoice = selected("Sound")
            endif

            if spatial_mode = 1
                t1 = min(duration_s,onset+tail)
                gain = eventMixGain*weight
                selectObject: outputSound
                Formula (part): onset,t1,1,1,
                    ... "self+" + fixed$(gain,9) + "*object("
                    ... + string$(voiceID) + ",x-" + fixed$(onset,9) + ",1)"

            elsif spatial_mode = 2
                if eventCount = 1
                    pan = 0.5
                else
                    pan = 0.05+0.90*(ev-1)/(eventCount-1)
                endif
                gL = eventMixGain*weight*sqrt(1-pan)
                gR = eventMixGain*weight*sqrt(pan)
                t1 = min(duration_s,onset+tail)

                selectObject: outputSound
                Formula (part): onset,t1,1,2,
                    ... "self+if row=1 then " + fixed$(gL,9)
                    ... + "*object(" + string$(voiceID) + ",x-"
                    ... + fixed$(onset,9) + ",1) else " + fixed$(gR,9)
                    ... + "*object(" + string$(voiceID) + ",x-"
                    ... + fixed$(onset,9) + ",1) fi"

            else
                delaySec = micro_delay_ms/1000
                g = eventMixGain*weight*sqrt(0.5)
                t1 = min(duration_s,onset+tail+delaySec)

                selectObject: outputSound
                Formula (part): onset,t1,1,2,
                    ... "self+if row=1 then " + fixed$(g,9)
                    ... + "*object(" + string$(voiceID) + ",x-"
                    ... + fixed$(onset,9) + ",1) else " + fixed$(g,9)
                    ... + "*object(" + string$(voiceID) + ",x-"
                    ... + fixed$(onset+delaySec,9) + ",1) fi"
            endif

            removeObject: voiceID
        endif
    endif
endfor

synthElapsed = stopwatch
appendInfoLine: "Synthesis time: ", fixed$(synthElapsed,3), " s"

# ---------------------------------------------------------------------------
# FINAL LEVEL
# ---------------------------------------------------------------------------
selectObject: outputSound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

safeName$ = replace$(preset_name$," ","_",0)
Rename: "KS_Texture_" + safeName$
outputSound = selected("Sound")
finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

if vizVoice > 0
    removeObject: vizVoice
endif

# ---------------------------------------------------------------------------
# PLAY / FINAL INFO
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Pre-protection peak/RMS: ", fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ", fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization
    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.80,0.42,0.20}"
    .purple$ = "{0.52,0.30,0.62}"
    .green$ = "{0.24,0.58,0.38}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half","KARPLUS-STRONG TEXTURE GENERATOR | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... texture_name$ + " | " + string$(eventCount) + " events | " + spatial_name$
    Text: 0.5,"centre",0.20,"half",
        ... "noise seed -> fractional-delay + brightness loop -> modeled decay -> event scheduler -> spatial mix"

    # -----------------------------------------------------------------------
    # A: ACTUAL EVENT FIELD
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.78,1.00
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  ACTUAL TEXTURE SCHEDULE | onset, pitch and rendered tail of every KS event"

    .logLo = ln(max(20,0.90*minEventPitch))
    .logHi = ln(min(safeTop,1.10*maxEventPitch))
    if .logHi <= .logLo
        .logHi = .logLo+0.5
    endif

    Select inner viewport: .left,.right,1.07,2.12
    Axes: 0,duration_s,.logLo,.logHi
    Paint rectangle: .bg$,0,duration_s,.logLo,.logHi

    for .ev from 1 to eventCount
        .h = (.ev-1)/max(1,eventCount-1)
        .r = 0.18+0.58*.h
        .g = 0.50-0.20*.h
        .b = 0.78-0.42*.h
        .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"
        Colour: .col$
        Draw line: eventOnset[.ev],ln(eventPitch[.ev]),
            ... min(duration_s,eventOnset[.ev]+eventTail[.ev]),ln(eventPitch[.ev])
        Paint circle (mm): .col$,eventOnset[.ev],ln(eventPitch[.ev]),0.8
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","log pitch"

    # -----------------------------------------------------------------------
    # B: LOOP GAIN VS FREQUENCY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.28,2.50
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  FEEDBACK LOOP | theoretical gain per round trip for first event"

    .fMax = min(0.45*sample_rate_Hz,max(3000,10*eventPitch[1]))
    .dbMin = -36

    Select inner viewport: .left,.right,2.57,3.48
    Axes: 0,.fMax,.dbMin,1
    Paint rectangle: .bg$,0,.fMax,.dbMin,1

    Colour: .grid$
    Dotted line
    .dbGrid = -30
    while .dbGrid <= 0
        Draw line: 0,.dbGrid,.fMax,.dbGrid
        .dbGrid = .dbGrid+10
    endwhile
    Plain line

    Colour: .purple$
    Line width: 1.5
    .prevF = 0
    .prevDb = 20*log10(damping)
    for .k from 1 to 160
        .f = .k/160*.fMax
        .w = 2*pi*.f/sample_rate_Hz
        .mB = sqrt(((1-firstS)+firstS*cos(.w))^2+(firstS*sin(.w))^2)
        .mF = sqrt(((1-firstFrac)+firstFrac*cos(.w))^2+(firstFrac*sin(.w))^2)
        .g = damping*.mB*.mF
        .db = max(.dbMin,20*log10(max(1e-12,.g)))
        Draw line: .prevF,.prevDb,.f,.db
        .prevF = .f
        .prevDb = .db
    endfor
    Line width: 1

    Colour: .orange$
    Dotted line
    .h = 1
    while .h*eventPitch[1] < .fMax and .h <= 12
        Draw line: .h*eventPitch[1],.dbMin,.h*eventPitch[1],1
        .h = .h+1
    endwhile
    Plain line

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Loop gain (dB/pass)"

    # -----------------------------------------------------------------------
    # C: FIRST-EVENT MEASURED DECAY VS MODE THEORY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.64,3.86
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  FIRST EVENT DECAY | measured RMS vs theoretical fundamental / 5th-partial loss"

    .dbFloor = -60
    .vDur = eventTail[1]
    .nWin = max(8,min(140,round(.vDur/0.04)))
    .hop = .vDur/.nWin
    .rmsMax = 1e-9
    .rmsT# = zero#(.nWin)
    .rmsV# = zero#(.nWin)

    selectObject: vizVoice
    for .k from 1 to .nWin
        .t0 = (.k-1)*.hop
        .t1 = min(.vDur,.t0+max(0.025,.hop))
        .rv = Get root-mean-square: .t0,.t1
        if .rv = undefined or .rv < 0
            .rv = 0
        endif
        .rmsT#[.k] = 0.5*(.t0+.t1)
        .rmsV#[.k] = .rv
        .rmsMax = max(.rmsMax,.rv)
    endfor

    Select inner viewport: .left,.right,3.93,4.91
    Axes: 0,.vDur,.dbFloor,3
    Paint rectangle: .bg$,0,.vDur,.dbFloor,3

    Colour: .grid$
    Dotted line
    .dbGrid = -50
    while .dbGrid <= 0
        Draw line: 0,.dbGrid,.vDur,.dbGrid
        .dbGrid = .dbGrid+10
    endwhile
    Plain line

    Colour: .orange$
    Line width: 1.5
    .havePrev = 0
    for .k from 1 to .nWin
        if .rmsV#[.k] > 1e-9
            .db = max(.dbFloor,20*log10(.rmsV#[.k]/.rmsMax))
        else
            .db = .dbFloor
        endif
        if .havePrev
            Draw line: .prevT,.prevDb,.rmsT#[.k],.db
        endif
        .prevT = .rmsT#[.k]
        .prevDb = .db
        .havePrev = 1
    endfor
    Line width: 1

    Colour: .blue$
    Dotted line
    Draw line: 0,0,.vDur,max(.dbFloor,firstDecay*.vDur)
    Colour: .green$
    Draw line: 0,0,.vDur,max(.dbFloor,firstDecay5*.vDur)
    Plain line

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text: 0.02*.vDur,"left",-5,"half","orange=measured  blue=f0 theory  green=5th theory"

    # -----------------------------------------------------------------------
    # D: MEASURED OUTPUT SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.07,5.29
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  TEXTURE -> MEASUREMENT | output spectrogram + actual event fundamentals"

    if finalChannels = 1
        selectObject: outputSound
        Copy: "ks_display_" + uid$
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

    .specMax = min(0.45*sample_rate_Hz,max(3000,7*maxEventPitch))
    .specStep = max(0.002,duration_s/1200)
    selectObject: .disp
    To Spectrogram: 0.03,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.36,6.45
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: .blue$
    Line width: 0.7
    .guideStep = max(1,ceiling(eventCount/180))
    for .ev from 1 to eventCount
        if ((.ev-1) mod .guideStep)=0 and eventPitch[.ev] <= .specMax
            Draw line: eventOnset[.ev],eventPitch[.ev],
                ... min(duration_s,eventOnset[.ev]+eventTail[.ev]),eventPitch[.ev]
        endif
    endfor
    Line width: 1
    Colour: "Black"
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
    Select inner viewport: 0.50,7.50,6.70,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1
    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "LOOP  |  N=" + string$(firstDelayN)
        ... + "  frac=" + fixed$(firstFrac,4)
        ... + "  S=" + fixed$(firstS,3)
        ... + "  coeffs=" + fixed$(firstA0,3) + "/" + fixed$(firstA1,3) + "/" + fixed$(firstA2,3)

    Text: 0.02,"left",0.58,"half",
        ... "DECAY  |  f0 " + fixed$(firstDecay,2) + " dB/s"
        ... + "  |  5th " + fixed$(firstDecay5,2) + " dB/s"
        ... + "  |  T60(f0) " + fixed$(firstT60,2) + " s"

    Text: 0.02,"left",0.36,"half",
        ... "TEXTURE  |  events " + string$(eventCount)
        ... + "  |  mean overlap " + fixed$(meanOverlap,2)
        ... + "  |  gain " + fixed$(eventMixGain,3)
        ... + "  |  " + seed_label$

    if protectionApplied
        .level$ = "down-only protection"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  RMS " + fixed$(finalRMS,4)
        ... + "  |  synth " + fixed$(synthElapsed,2) + " s  |  " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1
    Colour: "Black"
    Font size: 10
endproc
