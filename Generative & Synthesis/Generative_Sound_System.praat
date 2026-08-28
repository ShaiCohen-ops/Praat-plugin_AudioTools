# ============================================================
# Praat AudioTools - Generative Sound System.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 range fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Six distinct generative synthesis processes sharing one compact interface.
#
#   1. Harmonic Drift
#      Harmonic layers whose instantaneous frequencies are driven by
#      independent bounded stochastic drift controls. Phase is integrated
#      at audio sample rate.
#
#   2. Granular Cloud
#      Genuine Poisson-distributed Hann grains. Each layer has an independent
#      stochastic event rate, grain frequency jitter, duration and phase.
#
#   3. Chaotic FM
#      Logistic-map control signals are resampled to audio rate and mapped to
#      bounded instantaneous carrier frequency. Audio phase is then integrated
#      sample by sample. This is true frequency modulation by a chaotic control,
#      not a sinusoidal phase formula merely labelled "chaos".
#
#   4. Spectral Morph
#      A shared noise source is split into fixed spectral bands. A coherent
#      moving focus crossfades among the bands, producing an actual time-varying
#      spectral weighting rather than amplitude-modulating a fixed filter.
#
#   5. Rhythmic Pulse
#      Each layer generates a jittered, probabilistically thinned pulse train.
#      Every event has its own onset, duration and phase.
#
#   6. Subtractive Noise
#      Independent noise bands are shaped by independent bounded stochastic
#      amplitude controls. Evolution_rate controls the control-process speed.
#
# Spatial modes operate at LAYER level:
#   Mono
#   Layer Spread       - fixed equal-power positions
#   Rotating Layers    - moving equal-power positions with layer phase offsets
#   Micro-Delay Stereo - spectrum-preserving short right-channel delays
#
# v0.4.1 range fix:
#   - Clamped resampled bounded control signals before downstream mapping:
#       Harmonic Drift [-1,1], Chaotic FM [0,1], Subtractive Noise [-1,1].
#     This prevents sinc-resampling overshoot from exceeding the documented
#     drift/FM/gain ranges. No synthesis topology or preset logic changed.
#
# v0.4 reviewed:
#   - Granular Cloud is now genuinely granular; the old version was periodic AM.
#   - FM Chaos is now driven by a logistic map and audio-rate phase integration.
#   - Spectral Morph now morphs spectral-band weights instead of only changing
#     pre-filter amplitude.
#   - Subtractive Noise now has independent stochastic band evolution.
#   - Harmonic Drift now changes instantaneous frequency rather than using a
#     fixed-frequency carrier with nested sinusoidal phase modulation.
#   - Rhythmic Pulse now has an explicit event schedule with jitter/omissions.
#   - Evolution_rate now has a documented, active role in every mode.
#   - Added reproducible Random_seed.
#   - Added mode-dependent common frequency scaling for sampling headroom.
#   - Layer summation uses object IDs, not dynamically constructed Sound names.
#   - Removed repeated per-layer normalization; one optional final normalization.
#   - Global fade is applied once and is clamped to half the output duration.
#   - Replaced post-mix pseudo-spatial processing with layer-level equal-power
#     panning or spectrum-preserving micro-delay stereo.
#   - Removed "Binaural" label because the old complementary filtering did not
#     implement a binaural/HRTF model.
#   - Compact laptop-safe main form + optional Generative Details page.
#   - Visualization rebuilt around actual mechanism:
#       A generative control/event realization
#       B actual layer/event frequency architecture
#       C measured spectrogram + mode-relevant guides
#       D representative measured output waveform
#       process / bandwidth / randomness / level QC
# ============================================================

form Generative Sound System v0.4.1
    optionmenu Synthesis_mode 1
        option Harmonic Drift
        option Granular Cloud
        option Chaotic FM
        option Spectral Morph
        option Rhythmic Pulse
        option Subtractive Noise

    positive Duration_s 10
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 110
    integer Number_of_layers 4
    positive Evolution_rate 0.5

    optionmenu Spatial_mode 1
        option Mono
        option Layer Spread
        option Rotating Layers
        option Micro-Delay Stereo

    real Fade_time_s 1.0
    boolean Edit_generative_details 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
random_seed = 0
drift_depth_percent = 3.0
grain_density_scale = 1.0
grain_pitch_jitter_octaves = 0.20
chaotic_FM_depth_fraction = 0.28
spectral_span_octaves = 3.0
noise_bandwidth_octaves = 0.65
pulse_jitter_percent = 18.0
pulse_omission_probability = 0.12

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_generative_details
    beginPause: "Generative Sound System - Generative Details"
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Harmonic drift depth (percent)", drift_depth_percent
        positive: "Granular density scale", grain_density_scale
        real: "Grain pitch jitter (octaves)", grain_pitch_jitter_octaves
        real: "Chaotic FM depth fraction", chaotic_FM_depth_fraction
        real: "Spectral span (octaves)", spectral_span_octaves
        positive: "Noise-band width (octaves)", noise_bandwidth_octaves
        real: "Pulse timing jitter (percent)", pulse_jitter_percent
        real: "Pulse omission probability", pulse_omission_probability
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
if number_of_layers < 1 or number_of_layers > 16
    exitScript: "Number of layers must be between 1 and 16."
endif
if evolution_rate <= 0 or evolution_rate > 20
    exitScript: "Evolution rate must be > 0 and <= 20."
endif
if fade_time_s < 0
    exitScript: "Fade time cannot be negative."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if drift_depth_percent < 0 or drift_depth_percent > 30
    exitScript: "Drift depth must be between 0 and 30 percent."
endif
if grain_density_scale <= 0 or grain_density_scale > 10
    exitScript: "Granular density scale must be > 0 and <= 10."
endif
if grain_pitch_jitter_octaves < 0 or grain_pitch_jitter_octaves > 2
    exitScript: "Grain pitch jitter must be between 0 and 2 octaves."
endif
if chaotic_FM_depth_fraction < 0 or chaotic_FM_depth_fraction > 0.90
    exitScript: "Chaotic FM depth fraction must be between 0 and 0.90."
endif
if spectral_span_octaves < 0 or spectral_span_octaves > 8
    exitScript: "Spectral span must be between 0 and 8 octaves."
endif
if noise_bandwidth_octaves <= 0 or noise_bandwidth_octaves > 4
    exitScript: "Noise-band width must be > 0 and <= 4 octaves."
endif
if pulse_jitter_percent < 0 or pulse_jitter_percent > 95
    exitScript: "Pulse timing jitter must be between 0 and 95 percent."
endif
if pulse_omission_probability < 0 or pulse_omission_probability > 0.95
    exitScript: "Pulse omission probability must be between 0 and 0.95."
endif

if synthesis_mode = 1
    mode_name$ = "Harmonic Drift"
elsif synthesis_mode = 2
    mode_name$ = "Granular Cloud"
elsif synthesis_mode = 3
    mode_name$ = "Chaotic FM"
elsif synthesis_mode = 4
    mode_name$ = "Spectral Morph"
elsif synthesis_mode = 5
    mode_name$ = "Rhythmic Pulse"
else
    mode_name$ = "Subtractive Noise"
endif

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "Layer Spread"
elsif spatial_mode = 3
    spatial_name$ = "Rotating Layers"
else
    spatial_name$ = "Micro-Delay Stereo"
endif

safeTop = 0.45*sample_rate_Hz
twoPi = 2*pi
uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# 2. MODE-DEPENDENT FREQUENCY HEADROOM
# ---------------------------------------------------------------------------
if synthesis_mode = 1
    requestedTop = base_frequency_Hz*number_of_layers*
        ... (1+drift_depth_percent/100)

elsif synthesis_mode = 2
    topCenter = base_frequency_Hz*(1+0.30*(number_of_layers-1))
    requestedTop = topCenter*2^grain_pitch_jitter_octaves

elsif synthesis_mode = 3
    topCarrier = base_frequency_Hz*(1+0.25*(number_of_layers-1))
    requestedTop = topCarrier*(1+chaotic_FM_depth_fraction)

elsif synthesis_mode = 4 or synthesis_mode = 6
    topCenter = base_frequency_Hz*2^spectral_span_octaves
    requestedTop = topCenter*2^(0.5*noise_bandwidth_octaves)

else
    requestedTop = base_frequency_Hz*(1+0.50*(number_of_layers-1))
endif

frequencyScale = min(1,safeTop/max(1,requestedTop))

if base_frequency_Hz*frequencyScale < 20
    exitScript: "Requested mode/layer settings require the common base below 20 Hz. Reduce frequency span/layers or Base frequency."
endif

effectiveBase = base_frequency_Hz*frequencyScale
actualFade = min(fade_time_s,0.5*duration_s)

# ---------------------------------------------------------------------------
# 3. RANDOMNESS
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# ---------------------------------------------------------------------------
# 4. OUTPUT BUFFER / SHARED VISUALIZATION STATE
# ---------------------------------------------------------------------------
if spatial_mode = 1
    outputSound = Create Sound from formula:
        ... "gen_" + uid$,1,0,duration_s,sample_rate_Hz,"0"
else
    outputSound = Create Sound from formula:
        ... "gen_" + uid$,2,0,duration_s,sample_rate_Hz,"0"
endif

layerFreq# = zero#(number_of_layers)
layerRate# = zero#(number_of_layers)

eventCount = 0
vizControl = 0
vizControlLabel$ = ""
vizControlYMin = 0
vizControlYMax = 1
maxTermsInChunk = 0
generationCount = 0

# ---------------------------------------------------------------------------
# 5. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  GENERATIVE SOUND SYSTEM v0.4.1"
writeInfoLine: "=============================================="
appendInfoLine: "Mode: ", mode_name$
appendInfoLine: "Duration: ", fixed$(duration_s,2), " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Base / effective base: ",
    ... fixed$(base_frequency_Hz,2), " / ", fixed$(effectiveBase,2), " Hz"
appendInfoLine: "Evolution rate: ", fixed$(evolution_rate,3)
appendInfoLine: "Spatial: ", spatial_name$
appendInfoLine: "Randomness: ", seedLabel$
if frequencyScale < 0.999999
    appendInfoLine: "Common frequency scale applied for sampling headroom: ",
        ... fixed$(frequencyScale,5)
endif
appendInfoLine: ""

# ===========================================================================
# MODE 1: HARMONIC DRIFT
# ===========================================================================
if synthesis_mode = 1
    appendInfoLine: "Generating bounded stochastic harmonic drifts..."

    controlRate = max(20,min(200,40*evolution_rate))
    driftDepth = drift_depth_percent/100

    for layer from 1 to number_of_layers
        nominal = effectiveBase*layer
        layerFreq#[layer] = nominal
        layerRate#[layer] = evolution_rate*(0.70+0.12*layer)

        # Ornstein-Uhlenbeck-like bounded drift driver at control rate.
        a = exp(-2*pi*layerRate#[layer]/controlRate)
        b = sqrt(max(0,1-a*a))*0.55

        driftRaw = Create Sound from formula:
            ... "drift_raw_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,controlRate,"0"
        selectObject: driftRaw
        Formula: "if col=1 then 0 else tanh(" + fixed$(a,9)
            ... + "*self[col-1]+" + fixed$(b,9)
            ... + "*randomGauss(0,1)) fi"

        Resample: sample_rate_Hz,50
        driftAudio = selected("Sound")
        removeObject: driftRaw

        selectObject: driftAudio
        Formula: "if self < -1 then -1 else if self > 1 then 1 else self fi fi"
        Formula: fixed$(nominal,9) + "*(1+" + fixed$(driftDepth,9)
            ... + "*self)"
        freqControl = selected("Sound")

        if layer = 1
            selectObject: freqControl
            Copy: "viz_control_" + uid$
            vizControl = selected("Sound")
            vizControlLabel$ = "Layer-1 instantaneous frequency (Hz)"
            vizControlYMin = nominal*(1-driftDepth)*0.98
            vizControlYMax = nominal*(1+driftDepth)*1.02
        endif

        phaseSound = Create Sound from formula:
            ... "drift_layer_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,sample_rate_Hz,"0"
        selectObject: phaseSound
        Formula: "if col=1 then 0 else self[col-1]+2*pi*object["
            ... + string$(freqControl) + ",1,col]/"
            ... + string$(sample_rate_Hz) + " fi"

        layerAmp = 1/sqrt(layer)
        Formula: "sin(self)*" + fixed$(layerAmp,9)

        layerSound = selected("Sound")
        @addLayer: layerSound,layer
        removeObject: layerSound,freqControl
    endfor

# ===========================================================================
# MODE 2: GRANULAR CLOUD
# ===========================================================================
elsif synthesis_mode = 2
    appendInfoLine: "Generating genuine Poisson grain cloud..."

    # First generate all per-layer schedules; each layer occupies a contiguous
    # range in the event arrays so rendering can stay efficient.
    for layer from 1 to number_of_layers
        layer_event_start[layer] = eventCount+1

        center = effectiveBase*(1+0.30*(layer-1))
        density = grain_density_scale*(8+3*layer)*(0.5+evolution_rate)
        density = min(120,density)
        layerFreq#[layer] = center
        layerRate#[layer] = density

        t = 0
        while t < duration_s
            u = max(1e-12,randomUniform(0,1))
            t = t-ln(u)/density

            if t < duration_s
                eventCount = eventCount+1
                if eventCount > 9000
                    exitScript: "Granular realization exceeded 9000 events. Reduce duration, layers or density scale."
                endif

                event_time[eventCount] = t
                event_layer[eventCount] = layer
                event_freq[eventCount] = center*
                    ... 2^randomUniform(-grain_pitch_jitter_octaves,
                    ... grain_pitch_jitter_octaves)

                gd = randomUniform(0.025,0.11)
                event_dur[eventCount] = min(gd,duration_s-t)
                event_phase[eventCount] = 2*pi*randomUniform(0,1)
            endif
        endwhile

        layer_event_end[layer] = eventCount
    endfor

    expectedOverlap = 0
    for layer from 1 to number_of_layers
        expectedOverlap = expectedOverlap+
            ... layerRate#[layer]*0.0675/number_of_layers
    endfor
    grainAmp = 0.55/sqrt(max(1,expectedOverlap))

    # Render one layer at a time in local 0.5-s chunks.
    for layer from 1 to number_of_layers
        layerSound = Create Sound from formula:
            ... "grain_layer_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,sample_rate_Hz,"0"

        chunkDur = min(0.5,duration_s)
        numChunks = ceiling(duration_s/chunkDur)
        startIndex = layer_event_start[layer]

        for chunk from 1 to numChunks
            c0 = (chunk-1)*chunkDur
            c1 = min(duration_s,chunk*chunkDur)
            formula$ = "0"
            terms = 0

            ev = startIndex
            while ev <= layer_event_end[layer] and
                ... event_time[ev]+0.11 <= c0
                ev = ev+1
            endwhile
            startIndex = ev

            while ev <= layer_event_end[layer] and event_time[ev] < c1
                eEnd = event_time[ev]+event_dur[ev]

                if eEnd > c0
                    terms = terms+1
                    maxTermsInChunk = max(maxTermsInChunk,terms)

                    eTime$ = fixed$(event_time[ev],9)
                    eDur$ = fixed$(event_dur[ev],9)
                    eFreq$ = fixed$(event_freq[ev],6)
                    ePhase$ = fixed$(event_phase[ev],9)
                    age$ = "(x-" + eTime$ + ")"

                    formula$ = formula$ + "+if x>="
                        ... + fixed$(max(c0,event_time[ev]),9)
                        ... + " and x<" + fixed$(min(c1,eEnd),9)
                        ... + " then " + fixed$(grainAmp,9)
                        ... + "*sin(2*pi*" + eFreq$ + "*" + age$
                        ... + "+" + ePhase$ + ")"
                        ... + "*(0.5-0.5*cos(2*pi*" + age$
                        ... + "/" + eDur$ + ")) else 0 fi"
                endif
                ev = ev+1
            endwhile

            if terms > 0
                selectObject: layerSound
                Formula (part): c0,c1,1,1,"self+(" + formula$ + ")"
            endif
        endfor

        @addLayer: layerSound,layer
        removeObject: layerSound
    endfor

# ===========================================================================
# MODE 3: CHAOTIC FM
# ===========================================================================
elsif synthesis_mode = 3
    appendInfoLine: "Generating logistic-map chaotic FM..."

    controlRate = max(120,min(1200,200*(0.5+evolution_rate)))
    fmDepth = chaotic_FM_depth_fraction

    for layer from 1 to number_of_layers
        carrier = effectiveBase*(1+0.25*(layer-1))
        layerFreq#[layer] = carrier

        # Keep r inside a robust chaotic regime while allowing Evolution_rate
        # to move toward stronger mixing.
        rChaos = min(3.99,3.82+0.10*min(1,evolution_rate/2)+0.003*layer)
        layerRate#[layer] = rChaos
        x0 = randomUniform(0.13,0.87)

        chaosRaw = Create Sound from formula:
            ... "chaos_raw_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,controlRate,"0"
        selectObject: chaosRaw
        Formula: "if col=1 then " + fixed$(x0,12)
            ... + " else " + fixed$(rChaos,9)
            ... + "*self[col-1]*(1-self[col-1]) fi"

        Resample: sample_rate_Hz,50
        chaosAudio = selected("Sound")
        removeObject: chaosRaw

        selectObject: chaosAudio
        Formula: "if self < 0 then 0 else if self > 1 then 1 else self fi fi"
        Formula: fixed$(carrier,9) + "*(1+" + fixed$(fmDepth,9)
            ... + "*(2*self-1))"
        freqControl = selected("Sound")

        if layer = 1
            selectObject: freqControl
            Copy: "viz_control_" + uid$
            vizControl = selected("Sound")
            vizControlLabel$ = "Layer-1 instantaneous frequency (Hz)"
            vizControlYMin = carrier*(1-fmDepth)*0.98
            vizControlYMax = carrier*(1+fmDepth)*1.02
        endif

        phaseSound = Create Sound from formula:
            ... "chaos_layer_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,sample_rate_Hz,"0"
        selectObject: phaseSound
        Formula: "if col=1 then 0 else self[col-1]+2*pi*object["
            ... + string$(freqControl) + ",1,col]/"
            ... + string$(sample_rate_Hz) + " fi"

        layerAmp = 1/sqrt(number_of_layers)
        Formula: "sin(self)*" + fixed$(layerAmp,9)

        layerSound = selected("Sound")
        @addLayer: layerSound,layer
        removeObject: layerSound,freqControl
    endfor

# ===========================================================================
# MODE 4: SPECTRAL MORPH
# ===========================================================================
elsif synthesis_mode = 4
    appendInfoLine: "Generating coherent moving spectral focus..."

    noiseBase = Create Sound from formula:
        ... "morph_noise_" + uid$,1,0,duration_s,sample_rate_Hz,
        ... "randomGauss(0,1)"

    if number_of_layers = 1
        morphWidth = 1
    else
        morphWidth = max(1/(number_of_layers-1),0.18)
    endif

    for layer from 1 to number_of_layers
        if number_of_layers = 1
            pos = 0.5
        else
            pos = (layer-1)/(number_of_layers-1)
        endif

        center = effectiveBase*2^(spectral_span_octaves*pos)
        layerFreq#[layer] = center
        layerRate#[layer] = evolution_rate

        low = max(20,center/2^(0.5*noise_bandwidth_octaves))
        high = min(safeTop,center*2^(0.5*noise_bandwidth_octaves))
        smoothHz = max(10,min(250,0.12*(high-low)))

        selectObject: noiseBase
        Copy: "morph_band_" + uid$ + "_" + string$(layer)
        temp = selected("Sound")
        Filter (pass Hann band): low,high,smoothHz
        band = selected("Sound")
        removeObject: temp

        selectObject: band
        if number_of_layers > 1
            phaseOffset = 0.15*sin(layer*1.37)
            morphExpr$ = "(0.5+0.5*sin(2*pi*"
                ... + fixed$(evolution_rate,6) + "*x+"
                ... + fixed$(phaseOffset,9) + "))"
            Formula: "self*exp(-0.5*((" + fixed$(pos,9)
                ... + "-" + morphExpr$ + ")/"
                ... + fixed$(morphWidth,9) + ")^2)"
        endif

        @addLayer: band,layer
        removeObject: band
    endfor

    removeObject: noiseBase

# ===========================================================================
# MODE 5: RHYTHMIC PULSE
# ===========================================================================
elsif synthesis_mode = 5
    appendInfoLine: "Generating jittered probabilistic pulse layers..."

    jitterFrac = pulse_jitter_percent/100

    for layer from 1 to number_of_layers
        layer_event_start[layer] = eventCount+1

        pulseFreq = effectiveBase*(1+0.50*(layer-1))
        rhythmRate = max(0.10,evolution_rate*(0.75+0.30*layer))
        nominalIOI = 1/rhythmRate

        layerFreq#[layer] = pulseFreq
        layerRate#[layer] = rhythmRate

        t = randomUniform(0,nominalIOI)

        while t < duration_s
            if randomUniform(0,1) >= pulse_omission_probability
                eventCount = eventCount+1
                if eventCount > 9000
                    exitScript: "Rhythmic realization exceeded 9000 events."
                endif

                event_time[eventCount] = t
                event_layer[eventCount] = layer
                event_freq[eventCount] = pulseFreq
                event_dur[eventCount] =
                    ... min(duration_s-t,min(0.16,0.30*nominalIOI))
                event_phase[eventCount] = 2*pi*randomUniform(0,1)
            endif

            step = nominalIOI*
                ... (1+randomUniform(-jitterFrac,jitterFrac))
            t = t+max(0.02,step)
        endwhile

        layer_event_end[layer] = eventCount
    endfor

    pulseAmp = 0.75/sqrt(number_of_layers)

    for layer from 1 to number_of_layers
        layerSound = Create Sound from formula:
            ... "pulse_layer_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,sample_rate_Hz,"0"

        if layer_event_end[layer] >= layer_event_start[layer]
            for ev from layer_event_start[layer] to layer_event_end[layer]
                eTime = event_time[ev]
                eDur = event_dur[ev]
                eEnd = eTime+eDur
                eTime$ = fixed$(eTime,9)
                eDur$ = fixed$(eDur,9)
                age$ = "(x-" + eTime$ + ")"

                selectObject: layerSound
                Formula (part): eTime,eEnd,1,1,
                    ... "self+" + fixed$(pulseAmp,9)
                    ... + "*sin(2*pi*" + fixed$(event_freq[ev],6)
                    ... + "*" + age$ + "+"
                    ... + fixed$(event_phase[ev],9) + ")"
                    ... + "*(0.5-0.5*cos(2*pi*" + age$
                    ... + "/" + eDur$ + "))"
            endfor
        endif

        @addLayer: layerSound,layer
        removeObject: layerSound
    endfor

# ===========================================================================
# MODE 6: SUBTRACTIVE NOISE
# ===========================================================================
else
    appendInfoLine: "Generating independently evolving subtractive-noise bands..."

    controlRate = max(20,min(200,35*evolution_rate))

    for layer from 1 to number_of_layers
        if number_of_layers = 1
            pos = 0.5
        else
            pos = (layer-1)/(number_of_layers-1)
        endif

        center = effectiveBase*2^(spectral_span_octaves*pos)
        layerFreq#[layer] = center
        layerRate#[layer] = evolution_rate*(0.65+0.11*layer)

        low = max(20,center/2^(0.5*noise_bandwidth_octaves))
        high = min(safeTop,center*2^(0.5*noise_bandwidth_octaves))
        smoothHz = max(10,min(250,0.12*(high-low)))

        noise = Create Sound from formula:
            ... "noise_band_src_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,sample_rate_Hz,
            ... "randomGauss(0,1)"

        selectObject: noise
        Filter (pass Hann band): low,high,smoothHz
        band = selected("Sound")
        removeObject: noise

        a = exp(-2*pi*layerRate#[layer]/controlRate)
        b = sqrt(max(0,1-a*a))*0.60

        ampRaw = Create Sound from formula:
            ... "noise_amp_raw_" + uid$ + "_" + string$(layer),
            ... 1,0,duration_s,controlRate,"0"
        selectObject: ampRaw
        Formula: "if col=1 then 0 else tanh(" + fixed$(a,9)
            ... + "*self[col-1]+" + fixed$(b,9)
            ... + "*randomGauss(0,1)) fi"

        Resample: sample_rate_Hz,50
        ampControl = selected("Sound")
        removeObject: ampRaw

        selectObject: ampControl
        Formula: "if self < -1 then -1 else if self > 1 then 1 else self fi fi"
        Formula: "0.18+0.82*(0.5+0.5*self)"

        if layer = 1
            selectObject: ampControl
            Copy: "viz_control_" + uid$
            vizControl = selected("Sound")
            vizControlLabel$ = "Layer-1 stochastic band gain"
            vizControlYMin = 0
            vizControlYMax = 1.05
        endif

        selectObject: band
        Formula: "self*object[" + string$(ampControl) + ",1,col]"

        @addLayer: band,layer
        removeObject: band,ampControl
    endfor
endif

# ---------------------------------------------------------------------------
# 6. RESTORE RANDOM GENERATOR AFTER ALL STOCHASTIC AUDIO IS RENDERED
# ---------------------------------------------------------------------------
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 7. GLOBAL FADE + FINAL LEVEL
# ---------------------------------------------------------------------------
selectObject: outputSound

if actualFade > 0
    fadeOutStart = duration_s-actualFade
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

preNormPeak = Get absolute extremum: 0,0,"None"
preNormRMS = Get root-mean-square: 0,0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safeMode$ = replace$(mode_name$," ","_",0)
Rename: "generative_" + safeMode$

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

# ---------------------------------------------------------------------------
# 8. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

if vizControl > 0
    removeObject: vizControl
endif

# ---------------------------------------------------------------------------
# 9. PLAY / FINAL INFO
# ---------------------------------------------------------------------------
selectObject: outputSound

appendInfoLine: ""
if eventCount > 0
    appendInfoLine: "Generated events: ", eventCount
endif
if maxTermsInChunk > 0
    appendInfoLine: "Maximum grain terms in a 0.5-s chunk: ", maxTermsInChunk
endif
appendInfoLine: "Requested spectral top / safe top: ",
    ... fixed$(requestedTop,1), " / ", fixed$(safeTop,1), " Hz"
appendInfoLine: "Frequency scale: ", fixed$(frequencyScale,5)
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
# PROCEDURE: addLayer
# Layer-level spatialization + energy-aware summation.
# ===========================================================================
procedure addLayer: .layerID,.layerNum

    .mixNorm = sqrt(number_of_layers)

    if spatial_mode = 1
        selectObject: outputSound
        Formula: "self+object[" + string$(.layerID)
            ... + ",1,col]/" + fixed$(.mixNorm,9)

    elsif spatial_mode = 2
        if number_of_layers = 1
            .pan = 0.5
        else
            .pan = 0.05+0.90*(.layerNum-1)/(number_of_layers-1)
        endif

        .leftGain = sqrt(1-.pan)/.mixNorm
        .rightGain = sqrt(.pan)/.mixNorm

        selectObject: outputSound
        Formula: "if row=1 then self+" + fixed$(.leftGain,9)
            ... + "*object[" + string$(.layerID)
            ... + ",1,col] else self+" + fixed$(.rightGain,9)
            ... + "*object[" + string$(.layerID) + ",1,col] fi"

    elsif spatial_mode = 3
        .phase = 2*pi*(.layerNum-1)/number_of_layers
        .phase$ = fixed$(.phase,9)
        .rate = 0.06+0.025*evolution_rate

        .pan$ = "(0.5+0.46*sin(2*pi*" + fixed$(.rate,7)
            ... + "*x+" + .phase$ + "))"

        selectObject: outputSound
        Formula: "if row=1 then self+sqrt(1-" + .pan$
            ... + ")*object[" + string$(.layerID)
            ... + ",1,col]/" + fixed$(.mixNorm,9)
            ... + " else self+sqrt(" + .pan$
            ... + ")*object[" + string$(.layerID)
            ... + ",1,col]/" + fixed$(.mixNorm,9) + " fi"

    else
        # Spectrum-preserving micro-delay; no complementary filtering.
        .delay = (0.00025+0.00012*.layerNum)
        .gain = sqrt(0.5)/.mixNorm

        selectObject: outputSound
        Formula: "if row=1 then self+" + fixed$(.gain,9)
            ... + "*object[" + string$(.layerID)
            ... + ",1,col] else self+" + fixed$(.gain,9)
            ... + "*object(" + string$(.layerID) + ",x-"
            ... + fixed$(.delay,9) + ",1) fi"
    endif
endproc


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
    .green$ = "{0.25,0.58,0.38}"
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
        ... "GENERATIVE SOUND SYSTEM | " + mode_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... string$(number_of_layers) + " layers | evolution "
        ... + fixed$(evolution_rate,2) + " | " + spatial_name$
        ... + " | " + seedLabel$

    if synthesis_mode = 1
        .process$ = "bounded stochastic frequency drift -> audio-rate phase integration -> harmonic layer field"
    elsif synthesis_mode = 2
        .process$ = "Poisson event times -> randomized Hann grains -> layered cloud"
    elsif synthesis_mode = 3
        .process$ = "logistic map -> instantaneous frequency -> audio-rate phase integration"
    elsif synthesis_mode = 4
        .process$ = "noise -> fixed band bank -> coherent moving spectral focus"
    elsif synthesis_mode = 5
        .process$ = "jittered/omitted pulse schedule -> Hann events -> rhythmic layer field"
    else
        .process$ = "independent noise bands -> stochastic gain walks -> subtractive texture"
    endif

    Text: 0.5,"centre",0.20,"half",.process$

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL GENERATIVE CONTROL / EVENT REALIZATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"

    if synthesis_mode = 2 or synthesis_mode = 5
        Text: 0.5,"centre",0.52,"half",
            ... "A  ACTUAL EVENT REALIZATION | onset + duration by layer"

        Select inner viewport: .left,.right,1.05,2.02
        Axes: 0,duration_s,0.5,number_of_layers+0.5
        Paint rectangle: .bg$,0,duration_s,0.5,number_of_layers+0.5

        Colour: .grid$
        Dotted line
        for .layer from 1 to number_of_layers
            Draw line: 0,.layer,duration_s,.layer
        endfor
        Plain line

        .eventStep = max(1,ceiling(eventCount/1600))
        for .ev from 1 to eventCount
            if ((.ev-1) mod .eventStep)=0
                .h = (event_layer[.ev]-1)/max(1,number_of_layers-1)
                .r = 0.18+0.60*.h
                .g = 0.50-0.22*.h
                .b = 0.78-0.45*.h
                .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                    ... + "," + fixed$(.b,3) + "}"
                Colour: .col$

                Draw line:
                    ... event_time[.ev],event_layer[.ev],
                    ... min(duration_s,event_time[.ev]+event_dur[.ev]),
                    ... event_layer[.ev]
            endif
        endfor

        Colour: "Black"
        Draw inner box
        Marks left: min(number_of_layers,8),"yes","yes","no"
        Marks bottom: 5,"yes","yes","no"
        Font size: 6
        Text left: "yes","Layer"

    elsif synthesis_mode = 4
        Text: 0.5,"centre",0.52,"half",
            ... "A  GENERATIVE CONTROL | coherent spectral-focus position"

        .focus = Create Sound from formula:
            ... "viz_focus_" + uid$,1,0,duration_s,200,
            ... "0.5+0.5*sin(2*pi*evolution_rate*x)"

        Select inner viewport: .left,.right,1.05,2.02
        Axes: 0,duration_s,0,1
        Paint rectangle: .bg$,0,duration_s,0,1

        selectObject: .focus
        Colour: .purple$
        Draw: 0,0,0,1,"no","Curve"
        removeObject: .focus

        Colour: "Black"
        Draw inner box
        Marks left: 3,"yes","yes","no"
        Marks bottom: 5,"yes","yes","no"
        Font size: 6
        Text left: "yes","Band position"

    else
        Text: 0.5,"centre",0.52,"half",
            ... "A  ACTUAL GENERATIVE CONTROL | " + vizControlLabel$

        Select inner viewport: .left,.right,1.05,2.02
        Axes: 0,duration_s,vizControlYMin,vizControlYMax
        Paint rectangle: .bg$,0,duration_s,vizControlYMin,vizControlYMax

        selectObject: vizControl
        Colour: .purple$
        Draw: 0,0,vizControlYMin,vizControlYMax,"no","Curve"

        Colour: "Black"
        Draw inner box
        Marks left: 4,"yes","yes","no"
        Marks bottom: 5,"yes","yes","no"
        Font size: 6
        Text left: "yes",vizControlLabel$
    endif

    # -----------------------------------------------------------------------
    # PANEL B: FREQUENCY ARCHITECTURE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.18,2.40
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"

    if synthesis_mode = 2 or synthesis_mode = 5
        Text: 0.5,"centre",0.52,"half",
            ... "B  ACTUAL EVENT FREQUENCIES | each segment is a rendered event"

        .fMin = 1e9
        .fMax = 0
        for .ev from 1 to eventCount
            .fMin = min(.fMin,event_freq[.ev])
            .fMax = max(.fMax,event_freq[.ev])
        endfor
    else
        Text: 0.5,"centre",0.52,"half",
            ... "B  LAYER FREQUENCY ARCHITECTURE | nominal carrier/band centers"

        .fMin = layerFreq#[1]
        .fMax = layerFreq#[1]
        for .layer from 1 to number_of_layers
            .fMin = min(.fMin,layerFreq#[.layer])
            .fMax = max(.fMax,layerFreq#[.layer])
        endfor
    endif

    .logLo = ln(max(20,0.88*.fMin))
    .logHi = ln(min(safeTop,1.12*.fMax))
    if .logHi <= .logLo
        .logHi = .logLo+0.5
    endif

    Select inner viewport: .left,.right,2.47,3.43
    Axes: 0,duration_s,.logLo,.logHi
    Paint rectangle: .bg$,0,duration_s,.logLo,.logHi

    if synthesis_mode = 2 or synthesis_mode = 5
        .eventStep = max(1,ceiling(eventCount/1400))

        for .ev from 1 to eventCount
            if ((.ev-1) mod .eventStep)=0
                .h = (event_layer[.ev]-1)/max(1,number_of_layers-1)
                .r = 0.18+0.60*.h
                .g = 0.50-0.22*.h
                .b = 0.78-0.45*.h
                .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                    ... + "," + fixed$(.b,3) + "}"
                Colour: .col$

                Draw line:
                    ... event_time[.ev],ln(event_freq[.ev]),
                    ... min(duration_s,event_time[.ev]+event_dur[.ev]),
                    ... ln(event_freq[.ev])
            endif
        endfor

    else
        for .layer from 1 to number_of_layers
            .h = (.layer-1)/max(1,number_of_layers-1)
            .r = 0.18+0.60*.h
            .g = 0.50-0.22*.h
            .b = 0.78-0.45*.h
            .col$ = "{" + fixed$(.r,3) + "," + fixed$(.g,3)
                ... + "," + fixed$(.b,3) + "}"
            Colour: .col$
            Draw line: 0,ln(layerFreq#[.layer]),
                ... duration_s,ln(layerFreq#[.layer])
        endfor
    endif

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
        Copy: "gen_display_" + uid$
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
    # PANEL C: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.59,3.81
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + nominal/event guides"

    .specMax = min(safeTop,max(1200,1.45*.fMax))
    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,3.88,5.02
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: .blue$
    Line width: 0.7

    if synthesis_mode = 2 or synthesis_mode = 5
        .guideStep = max(1,ceiling(eventCount/220))
        for .ev from 1 to eventCount
            if ((.ev-1) mod .guideStep)=0 and event_freq[.ev] <= .specMax
                Draw line:
                    ... event_time[.ev],event_freq[.ev],
                    ... min(duration_s,event_time[.ev]+event_dur[.ev]),
                    ... event_freq[.ev]
            endif
        endfor
    else
        for .layer from 1 to number_of_layers
            if layerFreq#[.layer] <= .specMax
                Draw line: 0,layerFreq#[.layer],
                    ... duration_s,layerFreq#[.layer]
            endif
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.18,5.40
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MEASURED OUTPUT | representative channel after layer-level spatial mix"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0,0,"None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05*.wavePeak

    Select inner viewport: .left,.right,5.47,6.22
    Axes: 0,duration_s,-.waveY,.waveY
    Paint rectangle: .bg$,0,duration_s,-.waveY,.waveY
    selectObject: .disp
    Colour: .orange$
    Draw: 0,0,-.waveY,.waveY,"no","Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Amplitude"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.48,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.81,"half",
        ... "PROCESS  |  " + .process$

    if eventCount > 0
        .eventText$ = "events " + string$(eventCount)
    else
        .eventText$ = "continuous control"
    endif

    Text: 0.02,"left",0.60,"half",
        ... "GENERATION  |  " + .eventText$
        ... + "  |  evolution " + fixed$(evolution_rate,3)
        ... + "  |  " + seedLabel$

    Text: 0.02,"left",0.39,"half",
        ... "BANDWIDTH QC  |  requested top " + fixed$(requestedTop,0)
        ... + " Hz  |  safe top " + fixed$(safeTop,0)
        ... + " Hz  |  scale " + fixed$(frequencyScale,4)

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.18,"half",
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
