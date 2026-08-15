# ============================================================
# Praat AudioTools - Convolution Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 preset refinement (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Discrete convolution synthesis:
#
#       excitation[n] * impulse_response[n] -> resonant output
#
#   The source and impulse response are both normalized to unit discrete L2
#   energy before convolution. A one-sample unit impulse therefore reproduces
#   the normalized IR exactly under Praat's "sum" convolution convention.
#
#   The resonant IR contains three damped modes:
#       f1                 decay d
#       f2                 decay 1.5d
#       1.5*f1             decay 2d, with gentle AM at Modulation_rate
#
#   IR duration follows the slowest exponential down to approximately -60 dB:
#       T60_amp = ln(1000) / decay_rate
#   capped only by the requested output duration.
#
# v0.4.1 preset refinement:
#   - Replaced instrument/object claims with mechanism-faithful preset names.
#   - Retuned presets to occupy more distinct frequency, decay, excitation,
#     envelope and spatial regions while leaving the DSP architecture intact.
#   - No convolution, normalization, visualization or object-access changes.
#
# v0.4 reviewed:
#   - Replaced the old 1-ms rectangular "Impulse" with a true one-sample
#     unit digital impulse.
#   - Source duration now matches the excitation itself (1 sample / 10 ms /
#     20 ms / 50 ms), instead of allocating a full-duration mostly-zero Sound.
#   - Source and IR are normalized to unit discrete L2 energy before convolution.
#   - Kept Convolve: "sum", "zero": this is the appropriate discrete FIR
#     convention when a unit pulse should reproduce the filter/IR.
#   - IR duration is derived from the decay rate to approximately -60 dB,
#     rather than being hard-capped at 1 second.
#   - Exact requested output duration is created by sample-index copying from
#     the convolution result, padding with zeros or trimming without time-axis
#     interpolation.
#   - Added Random_seed for Noise Burst reproducibility.
#   - Added practical Nyquist protection for all resonant modes and AM sidebands.
#   - "Reverse" envelope is now a real reverse/crescendo envelope rather than
#     reversing the entire convolved waveform.
#   - ADSR rewritten as one piecewise envelope pass.
#   - Edge fade combined into one Formula.
#   - Stereo Wide is a short decorrelation delay, not complementary spectral EQ.
#   - Rotating stereo uses equal-power panning.
#   - One optional final/common normalization only.
#   - Visualization rebuilt as:
#       A actual excitation
#       B actual normalized impulse response
#       C measured output spectrogram + resonance guides
#       D measured representative-channel waveform
#       process equation + source/IR/output QC
# ============================================================

form Convolution Synthesis v0.4.1
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Bright Metallic Ring
        option Deep Resonant Ring
        option High Glassy Ring
        option Short Noisy Resonance
        option Low Impact Resonance
        option Droplet Resonance
        option Hollow Pop
        option Inharmonic Chime
        option Dense High Burst
        option Rising Resonant Tone
        option Long Low Noise Decay

    comment === Basic Settings ===
    positive Duration_s 1.0
    integer Sample_rate_Hz 44100

    comment === Resonant IR ===
    positive Frequency_1_Hz 800
    positive Frequency_2_Hz 1200
    positive Decay_rate 20
    positive Modulation_rate_Hz 2

    comment === Excitation ===
    optionmenu Source_type 1
        option Impulse
        option Short Burst
        option Noise Burst
        option Tone Burst
    integer Random_seed 0

    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Decay
        option Reverse Envelope
        option Tremolo
        option Swell
        option ADSR

    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    real Edge_fade_s 0.005
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
# Preset names describe sonic morphology that this three-mode convolution
# engine can actually guarantee. They intentionally avoid instrument/object
# labels such as "snare", "thunder" or "crystal shatter", because those would
# imply dedicated physical/source models that are not present here.
preset_name$ = "Custom"

if preset = 2
    # Bright, moderately long inharmonic metallic ringing.
    duration_s = 1.5
    frequency_1_Hz = 760
    frequency_2_Hz = 1230
    decay_rate = 12
    modulation_rate_Hz = 4
    source_type = 3
    envelope_type = 1
    spatial_mode = 1
    preset_name$ = "Bright Metallic Ring"

elsif preset = 3
    # Low resonant body with a clearly longer decay.
    duration_s = 3.5
    frequency_1_Hz = 90
    frequency_2_Hz = 170
    decay_rate = 3.5
    modulation_rate_Hz = 0.7
    source_type = 3
    envelope_type = 1
    spatial_mode = 1
    preset_name$ = "Deep Resonant Ring"

elsif preset = 4
    # High-frequency, clean, glass-like ringing without claiming a glass model.
    duration_s = 1.2
    frequency_1_Hz = 1550
    frequency_2_Hz = 2570
    decay_rate = 18
    modulation_rate_Hz = 7
    source_type = 1
    envelope_type = 1
    spatial_mode = 2
    preset_name$ = "High Glassy Ring"

elsif preset = 5
    # Noise excitation with a very short resonant tail.
    duration_s = 0.6
    frequency_1_Hz = 220
    frequency_2_Hz = 3600
    decay_rate = 70
    modulation_rate_Hz = 10
    source_type = 3
    envelope_type = 2
    spatial_mode = 1
    preset_name$ = "Short Noisy Resonance"

elsif preset = 6
    # Sparse low-frequency impact response.
    duration_s = 0.7
    frequency_1_Hz = 55
    frequency_2_Hz = 95
    decay_rate = 30
    modulation_rate_Hz = 1.5
    source_type = 1
    envelope_type = 2
    spatial_mode = 1
    preset_name$ = "Low Impact Resonance"

elsif preset = 7
    # Compact high resonant droplet-like event.
    duration_s = 0.55
    frequency_1_Hz = 720
    frequency_2_Hz = 1450
    decay_rate = 45
    modulation_rate_Hz = 24
    source_type = 1
    envelope_type = 1
    spatial_mode = 2
    preset_name$ = "Droplet Resonance"

elsif preset = 8
    # Very short hollow resonant pop.
    duration_s = 0.35
    frequency_1_Hz = 320
    frequency_2_Hz = 650
    decay_rate = 90
    modulation_rate_Hz = 18
    source_type = 1
    envelope_type = 2
    spatial_mode = 1
    preset_name$ = "Hollow Pop"

elsif preset = 9
    # Bright inharmonic ringing with short deterministic excitation.
    duration_s = 1.4
    frequency_1_Hz = 900
    frequency_2_Hz = 1450
    decay_rate = 14
    modulation_rate_Hz = 3
    source_type = 2
    envelope_type = 1
    spatial_mode = 3
    preset_name$ = "Inharmonic Chime"

elsif preset = 10
    # Broadband high-frequency transient followed by a compact resonant tail.
    duration_s = 0.9
    frequency_1_Hz = 1850
    frequency_2_Hz = 4300
    decay_rate = 85
    modulation_rate_Hz = 32
    source_type = 3
    envelope_type = 2
    spatial_mode = 2
    preset_name$ = "Dense High Burst"

elsif preset = 11
    # Tone excitation plus reverse/crescendo output envelope.
    duration_s = 0.8
    frequency_1_Hz = 350
    frequency_2_Hz = 1800
    decay_rate = 40
    modulation_rate_Hz = 28
    source_type = 4
    envelope_type = 4
    spatial_mode = 2
    preset_name$ = "Rising Resonant Tone"

elsif preset = 12
    # Long low-frequency noisy response; descriptive rather than "Thunder".
    duration_s = 4.0
    frequency_1_Hz = 50
    frequency_2_Hz = 120
    decay_rate = 2.5
    modulation_rate_Hz = 0.3
    source_type = 3
    envelope_type = 3
    spatial_mode = 2
    preset_name$ = "Long Low Noise Decay"
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
if frequency_1_Hz <= 0 or frequency_2_Hz <= 0
    exitScript: "Resonance frequencies must be greater than zero."
endif
if decay_rate <= 0
    exitScript: "Decay rate must be greater than zero."
endif
if modulation_rate_Hz < 0
    exitScript: "Modulation rate cannot be negative."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if source_type = 1
    source_type$ = "Impulse"
elsif source_type = 2
    source_type$ = "Short Burst"
elsif source_type = 3
    source_type$ = "Noise Burst"
else
    source_type$ = "Tone Burst"
endif

if envelope_type = 1
    envelopeLabel$ = "None"
elsif envelope_type = 2
    envelopeLabel$ = "Percussive"
elsif envelope_type = 3
    envelopeLabel$ = "Slow Decay"
elsif envelope_type = 4
    envelopeLabel$ = "Reverse Envelope"
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
    spatialLabel$ = "Stereo Wide"
else
    spatialLabel$ = "Rotating"
endif

twoPi = 2 * pi
sqrtTwo = sqrt(2)
safeTop = 0.45 * sample_rate_Hz
uid$ = string$(randomInteger(10000, 99999))

# ---------------------------------------------------------------------------
# 2. PRACTICAL NYQUIST PROTECTION
# ---------------------------------------------------------------------------
# Third IR mode is 1.5*f1 and is amplitude-modulated. Reserve several
# modulation-rate sidebands as practical headroom.
mode3Frequency = 1.5 * frequency_1_Hz
nominalTop = max(frequency_2_Hz, mode3Frequency + 4 * modulation_rate_Hz)

frequencyScale = 1
if nominalTop > safeTop
    frequencyScale = safeTop / nominalTop
    frequency_1_Hz = frequency_1_Hz * frequencyScale
    frequency_2_Hz = frequency_2_Hz * frequencyScale
    modulation_rate_Hz = modulation_rate_Hz * frequencyScale
    mode3Frequency = 1.5 * frequency_1_Hz
endif

# ---------------------------------------------------------------------------
# 3. SOURCE / IR DURATIONS
# ---------------------------------------------------------------------------
if source_type = 1
    sourceDuration = 1 / sample_rate_Hz
elsif source_type = 2
    sourceDuration = min(duration_s, 0.010)
elsif source_type = 3
    sourceDuration = min(duration_s, 0.020)
else
    sourceDuration = min(duration_s, 0.050)
endif

# Slowest mode exp(-d*t) reaches 0.001 at ln(1000)/d.
irT60 = ln(1000) / decay_rate
irDuration = min(duration_s, max(4 / sample_rate_Hz, irT60))

# ---------------------------------------------------------------------------
# 4. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  CONVOLUTION SYNTHESIS v0.4.1"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s,3), " s"
appendInfoLine: "Excitation: ", source_type$
appendInfoLine: "IR modes: ", fixed$(frequency_1_Hz,1), " / ",
    ... fixed$(frequency_2_Hz,1), " / ", fixed$(mode3Frequency,1), " Hz"
appendInfoLine: "Decay rate: ", fixed$(decay_rate,3), " 1/s"
appendInfoLine: "IR duration: ", fixed$(irDuration,4), " s (~-60 dB of slowest exponential)"
appendInfoLine: "Envelope: ", envelopeLabel$
appendInfoLine: "Spatial: ", spatialLabel$
if frequencyScale < 1
    appendInfoLine: "Resonance/modulation frequencies scaled by ",
        ... fixed$(frequencyScale,4), " for Nyquist safety."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 5. CREATE ACTUAL EXCITATION
# ---------------------------------------------------------------------------
appendInfoLine: "Creating excitation..."

seedWasFixed = 0
if source_type = 3 and random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
endif

if source_type = 1
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, sourceDuration, sample_rate_Hz,
        ... "if col = 1 then 1 else 0 fi"

elsif source_type = 2
    burstFreq = min(1000, 0.5 * safeTop)
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, sourceDuration, sample_rate_Hz,
        ... "sin(twoPi*burstFreq*x) * 0.5*(1-cos(twoPi*x/sourceDuration))"

elsif source_type = 3
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, sourceDuration, sample_rate_Hz,
        ... "randomGauss(0,1) * 0.5*(1-cos(twoPi*x/sourceDuration))"

else
    sourceSound = Create Sound from formula: "source_" + uid$, 1, 0, sourceDuration, sample_rate_Hz,
        ... "sin(twoPi*frequency_1_Hz*x) * 0.5*(1-cos(twoPi*x/sourceDuration))"
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# Normalize source to unit DISCRETE L2 energy.
selectObject: sourceSound
sourceRMSBefore = Get root-mean-square: 0, 0
sourceSamples = Get number of samples
sourceL2 = sourceRMSBefore * sqrt(sourceSamples)
if sourceL2 <= 0
    exitScript: "Excitation has zero energy."
endif
Formula: "self / sourceL2"
sourcePeak = Get absolute extremum: 0, 0, "None"

# ---------------------------------------------------------------------------
# 6. CREATE ACTUAL IMPULSE RESPONSE
# ---------------------------------------------------------------------------
appendInfoLine: "Creating impulse response..."

irFormula$ = "sin(twoPi*frequency_1_Hz*x)*exp(-decay_rate*x)"
irFormula$ = irFormula$ + " + 0.7*sin(twoPi*frequency_2_Hz*x + 0.17)*exp(-1.5*decay_rate*x)"
irFormula$ = irFormula$ + " + 0.4*sin(twoPi*mode3Frequency*x + 0.31)*exp(-2*decay_rate*x)*(0.75 + 0.25*sin(twoPi*modulation_rate_Hz*x))"

irSound = Create Sound from formula: "ir_" + uid$, 1, 0, irDuration, sample_rate_Hz, irFormula$

# Normalize IR to unit DISCRETE L2 energy.
selectObject: irSound
irRMSBefore = Get root-mean-square: 0, 0
irSamples = Get number of samples
irL2 = irRMSBefore * sqrt(irSamples)
if irL2 <= 0
    exitScript: "Impulse response has zero energy."
endif
Formula: "self / irL2"
irPeak = Get absolute extremum: 0, 0, "None"
irRMS = Get root-mean-square: 0, 0

# ---------------------------------------------------------------------------
# 7. CONVOLVE
# ---------------------------------------------------------------------------
appendInfoLine: "Convolving with discrete sum / zero outside domain..."

selectObject: sourceSound
plusObject: irSound
rawConv = Convolve: "sum", "zero"

selectObject: rawConv
rawConvSamples = Get number of samples

# Exact requested duration, with sample-index copy: trim or zero-pad.
outputSound = Create Sound from formula: "conv_exact_" + uid$, 1, 0, duration_s, sample_rate_Hz,
    ... "if col <= rawConvSamples then object[rawConv,1,col] else 0 fi"

removeObject: rawConv

# ---------------------------------------------------------------------------
# 8. MUSICAL OUTPUT ENVELOPE
# ---------------------------------------------------------------------------
selectObject: outputSound

if envelope_type = 2
    Formula: "self * exp(-8*x)"

elsif envelope_type = 3
    Formula: "self * exp(-1.5*x)"

elsif envelope_type = 4
    # A real reverse envelope / crescendo; do not reverse the waveform.
    Formula: "self * (x/duration_s)"

elsif envelope_type = 5
    tremRate = 8
    tremDepth = 0.4
    Formula: "self * (1 - tremDepth + tremDepth*(0.5 + 0.5*sin(twoPi*tremRate*x)))"

elsif envelope_type = 6
    attackTime = max(0.005, 0.30 * duration_s)
    Formula: "self * min(1, x/attackTime)"

elsif envelope_type = 7
    attack = min(0.010, 0.10 * duration_s)
    decay = min(0.100, 0.20 * duration_s)
    sustain = 0.60
    releaseDur = min(0.200, 0.20 * duration_s)
    releaseStart = max(attack + decay, duration_s - releaseDur)

    adsrFormula$ = "self * if x < attack then x/attack else if x < attack+decay then 1-(1-sustain)*((x-attack)/decay) else if x < releaseStart then sustain else sustain*max(0,(duration_s-x)/(duration_s-releaseStart)) fi fi fi"
    Formula: adsrFormula$
endif

# ---------------------------------------------------------------------------
# 9. EDGE FADE
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s, 0.20 * duration_s)
if actualFade > 0
    fadeOutStart = duration_s - actualFade
    selectObject: outputSound
    Formula: "if x < actualFade then self*(x/actualFade) else if x > fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

# ---------------------------------------------------------------------------
# 10. SPATIAL PROCESSING
# ---------------------------------------------------------------------------
if spatial_mode = 2
    appendInfoLine: "Spatializing: short-delay stereo decorrelation..."
    monoID = outputSound
    wideDelay = min(0.008, 0.02 * duration_s)

    selectObject: monoID
    Copy: "conv_left_" + uid$
    leftSound = selected("Sound")
    Formula: "self / sqrtTwo"

    selectObject: monoID
    Copy: "conv_right_" + uid$
    rightSound = selected("Sound")
    Formula: "object(monoID, x-wideDelay, 1) / sqrtTwo"

    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    stereoSound = selected("Sound")

    removeObject: monoID, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Spatializing: equal-power rotation..."
    monoID = outputSound
    rotationRate = 0.35

    selectObject: monoID
    Copy: "conv_left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * sqrt(0.5*(1-sin(twoPi*rotationRate*x)))"

    selectObject: monoID
    Copy: "conv_right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sqrt(0.5*(1+sin(twoPi*rotationRate*x)))"

    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    stereoSound = selected("Sound")

    removeObject: monoID, leftSound, rightSound
    outputSound = stereoSound
endif

# ---------------------------------------------------------------------------
# 11. FINAL LEVEL / METRICS
# ---------------------------------------------------------------------------
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_name$, " ", "_", 0)
selectObject: outputSound
Rename: "convolution_" + safePreset$

finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
finalChannels = Get number of channels
finalDuration = Get total duration

if normalize_output = 0 and finalPeak > 0.99
    appendInfoLine: "WARNING: raw peak exceeds 0.99; normalization is disabled."
endif

# ---------------------------------------------------------------------------
# 12. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# Source and IR were deliberately retained for the figure.
removeObject: sourceSound, irSound

# ---------------------------------------------------------------------------
# 13. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Source discrete L2 energy: 1.000 (normalized)"
appendInfoLine: "IR discrete L2 energy: 1.000 (normalized)"
appendInfoLine: "Pre-normalization output peak: ", fixed$(preNormPeak,4)
appendInfoLine: "Final peak: ", fixed$(finalPeak,4), " | RMS: ", fixed$(finalRMS,4)
appendInfoLine: "Channels: ", finalChannels
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
    .sourceColour$ = "{0.22,0.48,0.72}"
    .irColour$ = "{0.24,0.58,0.38}"
    .outputColour$ = "{0.76,0.38,0.18}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.05, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "CONVOLUTION SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35, 7.65, 0.37, 0.67
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.68, "half",
        ... source_type$ + " x resonant IR | modes "
        ... + fixed$(frequency_1_Hz,0) + ", " + fixed$(frequency_2_Hz,0) + ", "
        ... + fixed$(mode3Frequency,0) + " Hz | decay " + fixed$(decay_rate,2) + " 1/s"
    Text: 0.5, "centre", 0.20, "half",
        ... "unit-energy excitation -> unit-energy impulse response -> discrete convolution -> envelope -> spatial render"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL EXCITATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.76, 0.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "A  EXCITATION | actual unit-energy source"

    selectObject: sourceSound
    .sourcePeak = Get absolute extremum: 0, 0, "None"
    if .sourcePeak < 0.001
        .sourcePeak = 0.001
    endif
    .sourceY = 1.05 * .sourcePeak

    Select inner viewport: .left, .right, 1.05, 1.92
    Axes: 0, sourceDuration, -.sourceY, .sourceY
    Paint rectangle: .bg$, 0, sourceDuration, -.sourceY, .sourceY
    selectObject: sourceSound
    Colour: .sourceColour$
    Draw: 0, 0, -.sourceY, .sourceY, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 4, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Amplitude"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL IR
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.08, 2.30
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "B  IMPULSE RESPONSE | actual normalized resonator; T60 derived from decay"

    selectObject: irSound
    .irPeak = Get absolute extremum: 0, 0, "None"
    if .irPeak < 0.001
        .irPeak = 0.001
    endif
    .irY = 1.05 * .irPeak

    Select inner viewport: .left, .right, 2.37, 3.33
    Axes: 0, irDuration, -.irY, .irY
    Paint rectangle: .bg$, 0, irDuration, -.irY, .irY
    selectObject: irSound
    Colour: .irColour$
    Draw: 0, 0, -.irY, .irY, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Amplitude"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "conv_display_" + uid$
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
    Select inner viewport: 0.35, 7.65, 3.49, 3.71
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "C  MODEL -> MEASUREMENT | output spectrogram with nominal IR-mode guides"

    .specMax = min(safeTop, max(1000, 1.35 * max(frequency_2_Hz, mode3Frequency + modulation_rate_Hz)))
    .specStep = max(0.002, duration_s / 1100)

    selectObject: .disp
    To Spectrogram: 0.025, .specMax, .specStep, 20, "Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left, .right, 3.78, 4.95
    selectObject: .spec
    Paint: 0, 0, 0, .specMax, 100, 1, 50, 6, 0, 0
    removeObject: .spec

    Axes: 0, duration_s, 0, .specMax
    Dotted line
    Line width: 1

    Colour: .sourceColour$
    if frequency_1_Hz <= .specMax
        Draw line: 0, frequency_1_Hz, duration_s, frequency_1_Hz
    endif
    Colour: .irColour$
    if frequency_2_Hz <= .specMax
        Draw line: 0, frequency_2_Hz, duration_s, frequency_2_Hz
    endif
    Colour: .outputColour$
    if mode3Frequency <= .specMax
        Draw line: 0, mode3Frequency, duration_s, mode3Frequency
    endif
    Plain line

    Colour: "Black"
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 5.11, 5.33
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

    Select inner viewport: .left, .right, 5.40, 6.18
    Axes: 0, duration_s, -.waveY, .waveY
    Paint rectangle: .bg$, 0, duration_s, -.waveY, .waveY
    selectObject: .disp
    Colour: .outputColour$
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
    # MECHANISM / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50, 7.50, 6.42, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02, "left", 0.81, "half",
        ... "MODEL  |  y[n] = sum_k source[k] * h[n-k]  |  Praat scaling: sum / zero"

    Text: 0.02, "left", 0.59, "half",
        ... "SOURCE  |  " + source_type$ + "  |  duration " + fixed$(sourceDuration*1000,2)
        ... + " ms  |  discrete L2 1.000"

    Text: 0.02, "left", 0.38, "half",
        ... "IR  |  T60 " + fixed$(irT60,3) + " s  |  rendered " + fixed$(irDuration,3)
        ... + " s  |  modes " + fixed$(frequency_1_Hz,0) + "/"
        ... + fixed$(frequency_2_Hz,0) + "/" + fixed$(mode3Frequency,0) + " Hz"

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02, "left", 0.17, "half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  peak " + fixed$(finalPeak,3)
        ... + "  |  RMS " + fixed$(finalRMS,4)
        ... + "  |  " + spatialLabel$ + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
