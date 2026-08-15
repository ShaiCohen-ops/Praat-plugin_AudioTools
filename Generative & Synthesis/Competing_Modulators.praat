# ============================================================
# Praat AudioTools - Competing Modulators.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multiple sinusoidal modulators compete inside a bounded
#   instantaneous-frequency control signal for each carrier voice.
#
#   For voice v:
#
#     m_v(t) =
#       [ sin(2*pi*f1*t)
#       + 0.75 sin(2*pi*f2*t)
#       + 0.40 sin(2*pi*f3*t) ] / 2.15
#
#     f_v(t) = fc_v * [1 + d * m_v(t)]
#
#     phi_v[n] = phi_v[n-1] + 2*pi*f_v[n]/Fs
#
#     y_v[n] = A_v sin(phi_v[n])
#
#   where:
#       f1 = modulator_base_rate * voice
#       f2 = f1 * modulator_spread
#       f3 = f1 * (1 + 0.01*voice)
#
#   Because the weighted modulator sum is normalized by 2.15,
#   m_v is bounded to [-1,1]. Modulation_intensity therefore means
#   maximum fractional instantaneous-frequency deviation d in [0,1].
#
# v0.4 reviewed:
#   - Replaced phase modulation mislabeled as FM with genuine bounded FM:
#     instantaneous frequency -> audio-rate phase integration -> oscillator.
#   - Renamed Beating_rate_Hz to Modulator_base_rate_Hz; the old parameter
#     was not itself a beating frequency.
#   - "Gentle Chaos" renamed "Gentle Interference": no chaotic system is
#     present in this script; the texture is deterministic multi-rate FM.
#   - Normalized competing-modulator weights so Modulation_intensity has a
#     clear meaning and cannot silently scale with three summed modulators.
#   - Voice amplitudes are energy-normalized across Number_of_voices rather
#     than falling as 1/N and being hidden by final normalization.
#   - Added practical Nyquist/sideband-headroom protection for carrier and
#     modulator rates.
#   - Rebuilt spatial modes at VOICE level:
#       Stereo Voices  = voices distributed across the stereo field
#       Rotating Field = equal-power moving voice pans
#       Wide Field     = fixed near-edge equal-power positions
#       Ping Pong      = equal-power alternating moving pans
#     Removed post-mix complementary EQ / spectral splitting.
#   - ADSR is now one piecewise envelope rather than four full-Sound passes.
#   - One combined edge fade; one optional final/common normalization.
#   - Removed dynamic Sound_'name$' formula access; object IDs are used.
#   - Visualization rebuilt around the actual mechanism:
#       A representative competing modulators + weighted sum
#       B actual instantaneous-frequency trajectories for all voices
#       C measured spectrogram + model frequency guides
#       D measured representative-channel waveform
#       compact mechanism/QC summary
# ============================================================

form Competing Modulators v0.4
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Interference
        option Metallic Clash
        option Organic Swarm
        option Digital Warble
        option Harmonic Battle
        option Alien Chorus
        option Glitchy Modulation
        option Rhythmic Conflict
        option Spectral War
        option Liquid Modulation
        option Crystal Resonance
        option Deep Interference

    comment === Basic Settings ===
    positive Duration_s 8.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    integer Number_of_voices 4

    comment === Competing Modulators ===
    real Modulation_intensity 0.5
    positive Modulator_spread 1.5
    positive Modulator_base_rate_Hz 2.0

    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Fade
        option Reverse
        option Tremolo
        option Swell
        option ADSR

    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Voices
        option Rotating Field
        option Wide Field
        option Ping Pong
    real Edge_fade_s 0.02
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    base_frequency_Hz = 100
    modulation_intensity = 0.30
    number_of_voices = 3
    modulator_spread = 1.20
    modulator_base_rate_Hz = 1.5
    envelope_type = 6
    spatial_mode = 1
    preset_name$ = "Gentle Interference"

elsif preset = 3
    base_frequency_Hz = 180
    modulation_intensity = 0.80
    number_of_voices = 5
    modulator_spread = 2.00
    modulator_base_rate_Hz = 5.0
    envelope_type = 2
    spatial_mode = 4
    preset_name$ = "Metallic Clash"

elsif preset = 4
    base_frequency_Hz = 80
    modulation_intensity = 0.40
    number_of_voices = 6
    modulator_spread = 1.10
    modulator_base_rate_Hz = 0.5
    envelope_type = 5
    spatial_mode = 3
    preset_name$ = "Organic Swarm"

elsif preset = 5
    base_frequency_Hz = 200
    modulation_intensity = 0.70
    number_of_voices = 4
    modulator_spread = 1.80
    modulator_base_rate_Hz = 8.0
    envelope_type = 1
    spatial_mode = 5
    preset_name$ = "Digital Warble"

elsif preset = 6
    base_frequency_Hz = 150
    modulation_intensity = 0.60
    number_of_voices = 4
    modulator_spread = 2.00
    modulator_base_rate_Hz = 3.0
    envelope_type = 7
    spatial_mode = 2
    preset_name$ = "Harmonic Battle"

elsif preset = 7
    base_frequency_Hz = 140
    modulation_intensity = 0.90
    number_of_voices = 5
    modulator_spread = 1.618
    modulator_base_rate_Hz = 4.0
    envelope_type = 5
    spatial_mode = 3
    preset_name$ = "Alien Chorus"

elsif preset = 8
    base_frequency_Hz = 220
    modulation_intensity = 1.00
    number_of_voices = 3
    modulator_spread = 3.00
    modulator_base_rate_Hz = 12.0
    envelope_type = 1
    spatial_mode = 5
    preset_name$ = "Glitchy Modulation"

elsif preset = 9
    base_frequency_Hz = 110
    modulation_intensity = 0.50
    number_of_voices = 4
    modulator_spread = 1.50
    modulator_base_rate_Hz = 6.0
    envelope_type = 1
    spatial_mode = 5
    preset_name$ = "Rhythmic Conflict"

elsif preset = 10
    base_frequency_Hz = 160
    modulation_intensity = 0.80
    number_of_voices = 6
    modulator_spread = 2.50
    modulator_base_rate_Hz = 7.0
    envelope_type = 3
    spatial_mode = 4
    preset_name$ = "Spectral War"

elsif preset = 11
    base_frequency_Hz = 70
    modulation_intensity = 0.40
    number_of_voices = 3
    modulator_spread = 1.30
    modulator_base_rate_Hz = 0.3
    envelope_type = 6
    spatial_mode = 3
    preset_name$ = "Liquid Modulation"

elsif preset = 12
    base_frequency_Hz = 440
    modulation_intensity = 0.50
    number_of_voices = 5
    modulator_spread = 1.50
    modulator_base_rate_Hz = 2.0
    envelope_type = 2
    spatial_mode = 2
    preset_name$ = "Crystal Resonance"

elsif preset = 13
    duration_s = 12
    base_frequency_Hz = 55
    modulation_intensity = 0.60
    number_of_voices = 4
    modulator_spread = 1.20
    modulator_base_rate_Hz = 0.2
    envelope_type = 3
    spatial_mode = 3
    preset_name$ = "Deep Interference"
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
if number_of_voices < 2 or number_of_voices > 8
    exitScript: "Number of voices must be between 2 and 8."
endif
if modulation_intensity < 0 or modulation_intensity > 1
    exitScript: "Modulation intensity must be between 0 and 1."
endif
if modulator_spread <= 0 or modulator_spread > 8
    exitScript: "Modulator spread must be > 0 and <= 8."
endif
if modulator_base_rate_Hz <= 0
    exitScript: "Modulator base rate must be greater than zero."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if envelope_type = 1
    envelopeLabel$ = "No Envelope"
elsif envelope_type = 2
    envelopeLabel$ = "Percussive"
elsif envelope_type = 3
    envelopeLabel$ = "Slow Fade"
elsif envelope_type = 4
    envelopeLabel$ = "Reverse"
elsif envelope_type = 5
    envelopeLabel$ = "Tremolo"
elsif envelope_type = 6
    envelopeLabel$ = "Swell"
else
    envelopeLabel$ = "ADSR"
endif

if spatial_mode = 1
    spatialLabel$ = "Mono"
elsif spatial_mode = 2
    spatialLabel$ = "Stereo Voices"
elsif spatial_mode = 3
    spatialLabel$ = "Rotating Field"
elsif spatial_mode = 4
    spatialLabel$ = "Wide Field"
else
    spatialLabel$ = "Ping Pong"
endif

twoPi = 2 * pi
modWeightSum = 2.15
safeTop = 0.45 * sample_rate_Hz
uid$ = string$(randomInteger(10000, 99999))

# ---------------------------------------------------------------------------
# 2. PRACTICAL NYQUIST / SIDEBAND HEADROOM
# ---------------------------------------------------------------------------
# FM has theoretically infinite sidebands. This is a practical synthesis guard,
# not a claim of exact finite bandwidth: reserve about four times the fastest
# modulator frequency above the largest instantaneous carrier excursion.
maxModRatio = number_of_voices * max(modulator_spread, 1 + 0.01 * number_of_voices)
maxModFrequency = modulator_base_rate_Hz * maxModRatio

modRateAdjusted = 0
maxAllowedModFrequency = safeTop / 8
if maxModFrequency > maxAllowedModFrequency
    modulator_base_rate_Hz = maxAllowedModFrequency / maxModRatio
    maxModFrequency = modulator_base_rate_Hz * maxModRatio
    modRateAdjusted = 1
endif

carrierFactor = 1 + 0.10 * (number_of_voices - 1)
availableCarrierTop = safeTop - 4 * maxModFrequency
if availableCarrierTop < 40
    availableCarrierTop = 40
endif

maxSafeBase = availableCarrierTop / (carrierFactor * (1 + modulation_intensity))
baseAdjusted = 0
if base_frequency_Hz > maxSafeBase
    base_frequency_Hz = maxSafeBase
    baseAdjusted = 1
endif

if base_frequency_Hz < 20
    exitScript: "Requested modulation rates/spread leave too little Nyquist headroom. Reduce modulator rate or spread."
endif

minCarrier = base_frequency_Hz
maxCarrier = base_frequency_Hz * carrierFactor
freqBoundMin = minCarrier * (1 - modulation_intensity)
freqBoundMax = maxCarrier * (1 + modulation_intensity)
occupiedTopEstimate = freqBoundMax + 4 * maxModFrequency

# Voice-energy normalization.
weightEnergy = 0
for voice to number_of_voices
    weightEnergy = weightEnergy + 1 / voice
endfor
voiceNorm = sqrt(weightEnergy)

# Store the exact per-voice model parameters for visualization/QC.
for voice to number_of_voices
    voiceCarrier[voice] = base_frequency_Hz * (1 + (voice - 1) * 0.10)
    voiceMod1[voice] = modulator_base_rate_Hz * voice
    voiceMod2[voice] = voiceMod1[voice] * modulator_spread
    voiceMod3[voice] = voiceMod1[voice] * (1 + 0.01 * voice)
    voiceAmplitude[voice] = 0.65 * (1 / sqrt(voice)) / voiceNorm
endfor

# ---------------------------------------------------------------------------
# 3. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  COMPETING MODULATORS v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s, 3), " s"
appendInfoLine: "Voices: ", number_of_voices
appendInfoLine: "Carrier range: ", fixed$(minCarrier,1), "-", fixed$(maxCarrier,1), " Hz"
appendInfoLine: "FM depth: +/-", fixed$(100*modulation_intensity,1), "% of each carrier"
appendInfoLine: "Modulator base rate: ", fixed$(modulator_base_rate_Hz,3), " Hz"
appendInfoLine: "Fastest modulator: ", fixed$(maxModFrequency,2), " Hz"
appendInfoLine: "Envelope: ", envelopeLabel$
appendInfoLine: "Spatial: ", spatialLabel$
if modRateAdjusted
    appendInfoLine: "Modulator base rate reduced automatically for sampling headroom."
endif
if baseAdjusted
    appendInfoLine: "Base frequency reduced automatically for FM/Nyquist headroom."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 4. OUTPUT CANVAS
# ---------------------------------------------------------------------------
if spatial_mode = 1
    Create Sound from formula: "competing_mix_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    monoMix = selected("Sound")
else
    Create Sound from formula: "competing_left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    leftMix = selected("Sound")
    Create Sound from formula: "competing_right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    rightMix = selected("Sound")
endif

# ---------------------------------------------------------------------------
# 5. GENERATE TRUE BOUNDED-FM VOICES
# ---------------------------------------------------------------------------
appendInfoLine: "Generating ", number_of_voices, " competing-FM voices..."

for voice to number_of_voices
    carrierFreq = voiceCarrier[voice]
    mod1Freq = voiceMod1[voice]
    mod2Freq = voiceMod2[voice]
    mod3Freq = voiceMod3[voice]
    voiceAmp = voiceAmplitude[voice]
    voicePhase0 = twoPi * (voice - 1) / number_of_voices

    # Integrate the actual instantaneous frequency at AUDIO rate.
    phaseSound = Create Sound from formula: "phase_" + uid$ + "_" + string$(voice),
        ... 1, 0, duration_s, sample_rate_Hz, "0"

    selectObject: phaseSound
    phaseFormula$ = "if col = 1 then voicePhase0 + twoPi*carrierFreq*(1 + modulation_intensity*((sin(twoPi*mod1Freq*x) + 0.75*sin(twoPi*mod2Freq*x) + 0.40*sin(twoPi*mod3Freq*x))/modWeightSum))/sample_rate_Hz else self[col-1] + twoPi*carrierFreq*(1 + modulation_intensity*((sin(twoPi*mod1Freq*x) + 0.75*sin(twoPi*mod2Freq*x) + 0.40*sin(twoPi*mod3Freq*x))/modWeightSum))/sample_rate_Hz fi"
    Formula: phaseFormula$

    voiceSound = Create Sound from formula: "voice_" + uid$ + "_" + string$(voice),
        ... 1, 0, duration_s, sample_rate_Hz,
        ... "voiceAmp * sin(object[phaseSound,1,col])"

    removeObject: phaseSound

    # ---- Voice-level spatialization ---------------------------------------
    if spatial_mode = 1
        selectObject: monoMix
        Formula: "self + object[voiceSound,1,col]"

    elsif spatial_mode = 2
        # Distribute voices evenly across the field.
        pan = (voice - 1) / (number_of_voices - 1)
        leftGain = cos(0.5 * pi * pan)
        rightGain = sin(0.5 * pi * pan)

        selectObject: leftMix
        Formula: "self + leftGain * object[voiceSound,1,col]"
        selectObject: rightMix
        Formula: "self + rightGain * object[voiceSound,1,col]"

    elsif spatial_mode = 3
        # Equal-power slow rotation; voicePhase0 staggers the voices.
        rotationRate = 0.15

        selectObject: leftMix
        Formula: "self + object[voiceSound,1,col] * sqrt(0.5*(1 - sin(twoPi*rotationRate*x + voicePhase0)))"
        selectObject: rightMix
        Formula: "self + object[voiceSound,1,col] * sqrt(0.5*(1 + sin(twoPi*rotationRate*x + voicePhase0)))"

    elsif spatial_mode = 4
        # Fixed wide field: near-edge positions, but never hard one-channel-only.
        if number_of_voices > 1
            pan = 0.05 + 0.90 * (voice - 1) / (number_of_voices - 1)
        else
            pan = 0.5
        endif
        leftGain = cos(0.5 * pi * pan)
        rightGain = sin(0.5 * pi * pan)

        selectObject: leftMix
        Formula: "self + leftGain * object[voiceSound,1,col]"
        selectObject: rightMix
        Formula: "self + rightGain * object[voiceSound,1,col]"

    else
        # Smooth equal-power ping-pong. Adjacent voices start in opposition.
        panRate = 2.5
        pingPhase = pi * (voice - 1)

        selectObject: leftMix
        Formula: "self + object[voiceSound,1,col] * sqrt(0.5*(1 - sin(twoPi*panRate*x + pingPhase)))"
        selectObject: rightMix
        Formula: "self + object[voiceSound,1,col] * sqrt(0.5*(1 + sin(twoPi*panRate*x + pingPhase)))"
    endif

    removeObject: voiceSound
endfor

# ---------------------------------------------------------------------------
# 6. BUILD FINAL MONO/STEREO SOUND
# ---------------------------------------------------------------------------
if spatial_mode = 1
    outputSound = monoMix
else
    selectObject: leftMix
    plusObject: rightMix
    Combine to stereo
    outputSound = selected("Sound")
    removeObject: leftMix, rightMix
endif

# ---------------------------------------------------------------------------
# 7. GLOBAL ENVELOPE
# ---------------------------------------------------------------------------
selectObject: outputSound

if envelope_type = 2
    # Percussive.
    Formula: "self * exp(-3*x)"

elsif envelope_type = 3
    # Slow Fade.
    Formula: "self * exp(-0.2*x)"

elsif envelope_type = 4
    # Reverse / crescendo.
    Formula: "self * (x/duration_s)"

elsif envelope_type = 5
    # Tremolo.
    tremRate = 5 + modulation_intensity * 10
    Formula: "self * (0.6 + 0.4*sin(twoPi*tremRate*x))"

elsif envelope_type = 6
    # Swell.
    attackTime = max(0.01, duration_s * 0.30)
    Formula: "self * min(1, x/attackTime)"

elsif envelope_type = 7
    # One-pass ADSR.
    attack = min(0.05, 0.10 * duration_s)
    decay = min(0.20, 0.15 * duration_s)
    sustain = 0.60
    releaseDur = min(0.50, 0.20 * duration_s)
    releaseStart = max(attack + decay, duration_s - releaseDur)

    adsrFormula$ = "self * if x < attack then x/attack else if x < attack+decay then 1-(1-sustain)*((x-attack)/decay) else if x < releaseStart then sustain else sustain*max(0,(duration_s-x)/(duration_s-releaseStart)) fi fi fi"
    Formula: adsrFormula$
endif

# Edge protection is independent of the musical envelope.
actualFade = min(edge_fade_s, 0.20 * duration_s)
if actualFade > 0
    fadeOutStart = duration_s - actualFade
    selectObject: outputSound
    Formula: "if x < actualFade then self*(x/actualFade) else if x > fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

# ---------------------------------------------------------------------------
# 8. FINAL LEVEL / METRICS
# ---------------------------------------------------------------------------
if normalize_output
    selectObject: outputSound
    preNormPeak = Get absolute extremum: 0, 0, "None"
    if preNormPeak > 0
        Scale peak: 0.90
    endif
endif

safePreset$ = replace$(preset_name$, " ", "_", 0)
selectObject: outputSound
Rename: "competing_" + safePreset$

selectObject: outputSound
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
finalChannels = Get number of channels
finalDuration = Get total duration

if normalize_output = 0 and finalPeak > 0.99
    appendInfoLine: "WARNING: raw output peak exceeds 0.99; normalization is disabled."
endif

# ---------------------------------------------------------------------------
# 9. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 10. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Peak: ", fixed$(finalPeak,4)
appendInfoLine: "RMS: ", fixed$(finalRMS,4)
appendInfoLine: "Channels: ", finalChannels
appendInfoLine: "Practical occupied-top estimate: ", fixed$(occupiedTopEstimate,1), " Hz"
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
    .orange$ = "{0.75,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .dark$ = "{0.18,0.18,0.20}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.05, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "COMPETING MODULATORS | " + preset_name$

    Select inner viewport: 0.35, 7.65, 0.37, 0.67
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.68, "half",
        ... string$(number_of_voices) + " voices | carriers "
        ... + fixed$(minCarrier,0) + "-" + fixed$(maxCarrier,0) + " Hz | FM depth +/-"
        ... + fixed$(100*modulation_intensity,0) + "% | " + spatialLabel$
    Text: 0.5, "centre", 0.20, "half",
        ... "three competing sinusoidal controls -> bounded instantaneous frequency -> audio-rate phase integral -> voice sum"

    # Plotting rate for exact analytic control curves.
    .guideRate = min(sample_rate_Hz, max(200, 20 * maxModFrequency))

    # -----------------------------------------------------------------------
    # PANEL A: REPRESENTATIVE COMPETING MODULATORS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.76, 0.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "A  COMPETING MODULATORS | representative voice 1; black = normalized weighted sum"

    .m1$ = fixed$(voiceMod1[1],9)
    .m2$ = fixed$(voiceMod2[1],9)
    .m3$ = fixed$(voiceMod3[1],9)

    .mod1 = Create Sound from formula: "cm_m1_" + uid$, 1, 0, duration_s, .guideRate,
        ... "sin(2*pi*" + .m1$ + "*x)"
    .mod2 = Create Sound from formula: "cm_m2_" + uid$, 1, 0, duration_s, .guideRate,
        ... "sin(2*pi*" + .m2$ + "*x)"
    .mod3 = Create Sound from formula: "cm_m3_" + uid$, 1, 0, duration_s, .guideRate,
        ... "sin(2*pi*" + .m3$ + "*x)"
    .modSum = Create Sound from formula: "cm_msum_" + uid$, 1, 0, duration_s, .guideRate,
        ... "(sin(2*pi*" + .m1$ + "*x)+0.75*sin(2*pi*" + .m2$ + "*x)+0.40*sin(2*pi*" + .m3$ + "*x))/2.15"

    Select inner viewport: .left, .right, 1.05, 2.04
    Axes: 0, duration_s, -1.05, 1.05
    Paint rectangle: .bg$, 0, duration_s, -1.05, 1.05
    Colour: .grid$
    Dotted line
    Draw line: 0, 0, duration_s, 0
    Plain line

    selectObject: .mod1
    Colour: .blue$
    Draw: 0, 0, -1.05, 1.05, "no", "Curve"
    selectObject: .mod2
    Colour: .orange$
    Draw: 0, 0, -1.05, 1.05, "no", "Curve"
    selectObject: .mod3
    Colour: .green$
    Draw: 0, 0, -1.05, 1.05, "no", "Curve"

    selectObject: .modSum
    Colour: .dark$
    Line width: 1.6
    Draw: 0, 0, -1.05, 1.05, "no", "Curve"
    Line width: 1

    removeObject: .mod1, .mod2, .mod3, .modSum

    Axes: 0, duration_s, -1.05, 1.05
    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Control"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL INSTANTANEOUS-FREQUENCY MODEL
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.21, 2.43
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "B  ACTUAL INSTANTANEOUS FREQUENCY | all carrier voices"

    .fLo = max(0, freqBoundMin - max(10, 0.06*(freqBoundMax-freqBoundMin)))
    .fHi = min(safeTop, freqBoundMax + max(10, 0.06*(freqBoundMax-freqBoundMin)))
    if .fHi <= .fLo
        .fHi = .fLo + 20
    endif

    Select inner viewport: .left, .right, 2.50, 3.50
    Axes: 0, duration_s, .fLo, .fHi
    Paint rectangle: .bg$, 0, duration_s, .fLo, .fHi
    Colour: .grid$
    Dotted line
    for .v to number_of_voices
        Draw line: 0, voiceCarrier[.v], duration_s, voiceCarrier[.v]
    endfor
    Plain line

    for .v to number_of_voices
        .fc$ = fixed$(voiceCarrier[.v],9)
        .m1$ = fixed$(voiceMod1[.v],9)
        .m2$ = fixed$(voiceMod2[.v],9)
        .m3$ = fixed$(voiceMod3[.v],9)
        .depth$ = fixed$(modulation_intensity,9)

        .guideFormula$ = .fc$ + "*(1+" + .depth$ + "*((sin(2*pi*" + .m1$
            ... + "*x)+0.75*sin(2*pi*" + .m2$ + "*x)+0.40*sin(2*pi*" + .m3$ + "*x))/2.15))"

        .guide = Create Sound from formula: "cm_fg_" + uid$ + "_" + string$(.v),
            ... 1, 0, duration_s, .guideRate, .guideFormula$

        if (.v mod 3) = 1
            Colour: .blue$
        elsif (.v mod 3) = 2
            Colour: .orange$
        else
            Colour: .green$
        endif

        selectObject: .guide
        Draw: 0, 0, .fLo, .fHi, "no", "Curve"
        removeObject: .guide
    endfor

    Axes: 0, duration_s, .fLo, .fHi
    Colour: "Black"
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "cm_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0, 0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL C: MODEL -> MEASUREMENT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 3.67, 3.89
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + sampled frequency guides"

    .specMax = min(safeTop, max(1000, min(10000, occupiedTopEstimate * 1.15)))
    .specStep = max(0.002, duration_s / 1100)

    selectObject: .disp
    To Spectrogram: 0.025, .specMax, .specStep, 20, "Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left, .right, 3.96, 5.05
    selectObject: .spec
    Paint: 0, 0, 0, .specMax, 100, 1, 50, 6, 0, 0
    removeObject: .spec

    Axes: 0, duration_s, 0, .specMax
    Line width: 0.8

    for .v to number_of_voices
        .fc$ = fixed$(voiceCarrier[.v],9)
        .m1$ = fixed$(voiceMod1[.v],9)
        .m2$ = fixed$(voiceMod2[.v],9)
        .m3$ = fixed$(voiceMod3[.v],9)
        .depth$ = fixed$(modulation_intensity,9)

        .guideFormula$ = .fc$ + "*(1+" + .depth$ + "*((sin(2*pi*" + .m1$
            ... + "*x)+0.75*sin(2*pi*" + .m2$ + "*x)+0.40*sin(2*pi*" + .m3$ + "*x))/2.15))"

        .guide = Create Sound from formula: "cm_sg_" + uid$ + "_" + string$(.v),
            ... 1, 0, duration_s, .guideRate, .guideFormula$

        if (.v mod 3) = 1
            Colour: .blue$
        elsif (.v mod 3) = 2
            Colour: .orange$
        else
            Colour: .green$
        endif

        selectObject: .guide
        Draw: 0, 0, 0, .specMax, "no", "Curve"
        removeObject: .guide
    endfor

    Axes: 0, duration_s, 0, .specMax
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 5.22, 5.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "D  MEASURED OUTPUT | representative channel"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0, 0, "None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05 * .wavePeak

    Select inner viewport: .left, .right, 5.51, 6.27
    Axes: 0, duration_s, -.waveY, .waveY
    Paint rectangle: .bg$, 0, duration_s, -.waveY, .waveY
    selectObject: .disp
    Colour: .orange$
    Draw: 0, 0, -.waveY, .waveY, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # MECHANISM / QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50, 7.50, 6.50, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02, "left", 0.79, "half",
        ... "MODEL  |  m=(m1+0.75*m2+0.40*m3)/2.15  ->  f(t)=fc[1+d*m(t)]  ->  phase integral"

    Text: 0.02, "left", 0.55, "half",
        ... "CONTROL  |  carriers " + fixed$(minCarrier,0) + "-" + fixed$(maxCarrier,0) + " Hz"
        ... + "  |  modulators " + fixed$(voiceMod1[1],2) + "-" + fixed$(maxModFrequency,2) + " Hz"
        ... + "  |  depth +/-" + fixed$(100*modulation_intensity,0) + "%"

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02, "left", 0.31, "half",
        ... "OUTPUT  |  peak " + fixed$(finalPeak,3)
        ... + "  |  RMS " + fixed$(finalRMS,4)
        ... + "  |  " + spatialLabel$
        ... + "  |  " + envelopeLabel$
        ... + "  |  " + .norm$

    Text: 0.02, "left", 0.10, "half",
        ... "QC  |  practical occupied-top estimate " + fixed$(occupiedTopEstimate,0) + " Hz"
        ... + "  |  Fs " + string$(sample_rate_Hz) + " Hz"

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
