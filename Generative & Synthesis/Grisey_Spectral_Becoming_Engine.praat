# ============================================================
# Praat AudioTools - Grisey_Spectral_Becoming_Engine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1.3 adaptive sum-headroom fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# SPECTRAL BECOMING ENGINE
#
# This instrument is INSPIRED by Gérard Grisey's compositional attitude:
# sound as process, harmonicity <-> inharmonicity, micro/macro temporal
# continuity, perceptual thresholds, instrumental/additive synthesis and
# continuous mutation.
#
# It is NOT a reconstruction of a Grisey score, a historical sonogram, or a
# universal "Grisey algorithm". The engine deliberately distinguishes:
#
#   HISTORICAL / AESTHETIC PRINCIPLES
#     - process and transformation rather than static sonority
#     - harmonic/inharmonic/noise continua
#     - thresholds between rhythm, beating, roughness and spectral identity
#     - the spectrum as material for large-scale form
#
#   ENGINE-SPECIFIC COMPOSITIONAL DEVICES
#     - three threshold-oriented detuning families
#     - a five-stage process envelope
#     - three optional Lorentzian spectral-emphasis peaks
#     - explicit synthesis of combination-frequency "consequences"
#
# Recent archival scholarship should also make us cautious about the common
# textbook story that the opening of Partiels is simply a transcription of a
# measured trombone sonogram. Therefore the Partiels-inspired preset below
# models a LOW-E HARMONIC FIELD and instrumental-synthesis logic; it does not
# claim to reproduce a measured trombone spectrum.
#
# ---------------------------------------------------------------------------
# CORE MODEL
#
# 1. HARMONIC -> INHARMONIC BECOMING
#
#    Primary partial n:
#
#       f_start(n)  = f0 * n
#       f_target(n) = f0 * n^(1 + inharmonicity)
#
#    A shared continuous morph control m(t) moves every partial between them.
#    Frequency is integrated into phase at AUDIO SAMPLE RATE, so arbitrary
#    process curves remain phase-continuous.
#
# 2. THRESHOLD COMPANIONS: ACTUAL BEATING / SPLITTING
#
#    Every primary partial has a weaker companion. Its frequency separation is
#    family dependent:
#
#       low family   ~  1 Hz
#       mid family   ~  8 Hz
#       high family  ~ 24 Hz
#
#    These are COMPOSITIONAL HEURISTICS, not universal psychoacoustic borders:
#    auditory thresholds depend strongly on carrier frequency, level and
#    critical-band context.
#
#    Unlike v2.0, this actually produces a PAIR of nearby components. Therefore
#    the separation can become slow beating, faster pulsation/roughness, or
#    resolvable spectral splitting instead of being merely a frequency offset
#    with no reference component.
#
# 3. FAMILY-CORRELATED INSTABILITY
#
#    Low, mid and high families each share a smooth bounded stochastic control.
#    Every companion in a family inherits the same temporal fluctuation.
#    Thus "correlated instability" now exists IN TIME rather than being a set
#    of independent one-time endpoint jitters.
#
# 4. SPECTRAL AMPLITUDE IS INDEPENDENT OF INHARMONICITY
#
#    Spectral rolloff:
#
#       A_n(t) ~ 1 / n^alpha(t)
#
#    alpha(t) moves independently between Start_rolloff_alpha and
#    End_rolloff_alpha. Inharmonicity no longer secretly controls brightness.
#
#    Optional Lorentzian emphasis is evaluated at each partial's CURRENT
#    frequency, so a moving partial can enter or leave a spectral-emphasis zone.
#
# 5. PROCESS / MACROFORM
#
#    "Five-stage becoming" is an ENGINE-SPECIFIC formal model inspired by
#    process/liminality; it is NOT presented as a documented universal Grisey
#    five-stage schema:
#
#       emergence -> stabilization -> magnification
#       -> liminal blur -> extinction
#
#    Crucially, the liminal stage now changes SPECTRAL STATE: a normalized
#    filtered-noise veil grows according to a blur control. In v2.0 the
#    so-called threshold stage was only a global amplitude dip.
#
# 6. COMBINATION-FREQUENCY EXTERNALIZATION
#
#    Optional difference / sum frequencies derived from low primary pairs are
#    synthesized explicitly. This should be understood as a COMPOSITIONAL
#    externalization of nonlinear/combination-frequency relations, not a
#    simulation of the ear physically generating those tones.
#
# 7. PARTIELS-INSPIRED LOGIC
#
#    The official Partiels program note emphasizes periodicity, harmonic
#    spectrum, instrumental synthesis, and a continuum from harmonic spectra
#    toward noise. The Partiels-inspired preset therefore prioritizes:
#
#       low-E harmonic field -> increasing inharmonicity
#       + threshold splitting + modest late noise dissolution
#
#    Combination tones are OFF by default in that preset; they are not treated
#    as the historical cause of the opening spectral reveal.
#
# v2.1.3 adaptive sum-headroom fix:
#   - Adaptive internal render-rate planning now includes the highest possible
#     explicit sum-frequency component from the low-partial pair set actually
#     used by the combination layer.
#   - Prevents valid sum components from being omitted solely because the
#     adaptive internal rate was planned from the primary field alone.
#   - No primary/companion trajectories, stochastic controls, process form,
#     noise dissolution, presets, peak protection or visualization logic changed.
#
# v2.1.2 fast render:
#   - Added adaptive INTERNAL synthesis sample rate (default on).
#   - The spectral model is rendered at the lowest rate that preserves
#     generous headroom above the requested spectral top, then sinc-resampled
#     once to the requested output sample rate.
#   - Visualization spectrogram uses a temporary bandwidth-appropriate
#     downsampled display copy instead of analysing the 44.1-kHz output.
#   - Conceptual model, trajectories, presets, threshold pairs, stochastic
#     family motion and output duration are unchanged.
#
# v2.1.1 runtime fix:
#   - Added the missing third fi in the five-stage blurExpr$ nested formula.
#   - No DSP, preset, conceptual model or visualization behavior changed.
#
# v2.1 changes:
#   - conceptual claims corrected / historic overclaims removed
#   - real threshold pairs instead of single detuned oscillators
#   - actual family-correlated random walks
#   - audio-rate phase integration for every component
#   - brightness and inharmonicity decoupled
#   - corrected early-change vs late-change curve semantics
#   - five-stage process now changes spectral blur as well as level
#   - noise dissolution creates an actual harmonic/inharmonic/noise continuum
#   - common sample-rate scaling preserves the geometry of the whole spectrum
#   - reproducible Random_seed
#   - down-only peak protection instead of unconditional normalization
#   - compact main form + two advanced pages
#   - mechanism-first visualization:
#       A primary + companion spectral trajectories
#       B actual morph / blur / macro controls
#       C actual family split trajectories
#       D measured spectrogram + primary guides
#       conceptual / DSP / output QC
#
# References guiding the conceptual review:
#   - Grisey, "Tempus ex Machina" (1987)
#   - Grisey, "La musique: le devenir des sons" / "Devenir du son"
#   - Grisey, Partiels program note
#   - Féron, research on Grisey's spectral models and sonographic sources
#   - IRCAM work-course materials on harmonicity, differential sounds and
#     rhythm/timbre perceptual continua
# ============================================================

form Spectral Becoming Engine v2.1.3
    optionmenu Preset 2
        option Custom
        option Partiels-inspired Low-E Field
        option Gondwana-inspired Deep Drift
        option Fast Spectral Dissolution
        option Static Harmonic Shimmer
        option Prologue-inspired Vowel Weighting

    positive Fundamental_Hz 82.41
    integer Number_of_partials 24
    positive Duration_s 30
    real Inharmonicity_target 0.05
    positive Threshold_split_strength 1.0

    optionmenu Temporal_curve 1
        option Linear
        option Logarithmic (early change)
        option Exponential (late change)

    optionmenu Spectral_envelope 2
        option Flat rolloff
        option Three emphasis peaks

    optionmenu Combination_layer 1
        option Off
        option Difference frequencies
        option Difference + sum frequencies

    optionmenu Process_form 2
        option Simple process
        option Five-stage becoming (inspired)

    boolean Edit_spectral_details 0
    boolean Edit_process_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
formant1_Hz = 500
formant2_Hz = 1500
formant3_Hz = 2500
formant_Q = 4.0

start_rolloff_alpha = 1.00
end_rolloff_alpha = 0.78
companion_mix = 0.20
family_instability_depth = 0.25

noise_dissolution = 0.25
respiratory_rate_Hz = 0.12
respiratory_depth = 0.08
random_seed = 0
sample_rate_Hz = 44100
adaptive_render_rate = 1

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
presetName$ = "Custom"

if preset = 2
    # PARTIELS-INSPIRED, not a trombone-sonogram reconstruction.
    fundamental_Hz = 82.41
    number_of_partials = 18
    duration_s = 30
    inharmonicity_target = 0.045
    threshold_split_strength = 0.85
    temporal_curve = 1
    spectral_envelope = 2
    combination_layer = 1
    process_form = 2

    formant1_Hz = 450
    formant2_Hz = 1050
    formant3_Hz = 2300
    formant_Q = 4.0
    start_rolloff_alpha = 1.08
    end_rolloff_alpha = 0.88
    companion_mix = 0.17
    family_instability_depth = 0.18
    noise_dissolution = 0.22
    respiratory_rate_Hz = 0.11
    respiratory_depth = 0.07

    presetName$ = "Partiels-inspired Low-E Field"

elsif preset = 3
    fundamental_Hz = 32.70
    number_of_partials = 32
    duration_s = 45
    inharmonicity_target = 0.085
    threshold_split_strength = 1.20
    temporal_curve = 3
    spectral_envelope = 2
    combination_layer = 2
    process_form = 2

    formant1_Hz = 220
    formant2_Hz = 900
    formant3_Hz = 2000
    formant_Q = 3.5
    start_rolloff_alpha = 1.00
    end_rolloff_alpha = 0.68
    companion_mix = 0.20
    family_instability_depth = 0.28
    noise_dissolution = 0.34
    respiratory_rate_Hz = 0.075
    respiratory_depth = 0.13

    presetName$ = "Gondwana-inspired Deep Drift"

elsif preset = 4
    fundamental_Hz = 65.41
    number_of_partials = 20
    duration_s = 15
    inharmonicity_target = 0.20
    threshold_split_strength = 1.65
    temporal_curve = 2
    spectral_envelope = 1
    combination_layer = 3
    process_form = 2

    formant1_Hz = 500
    formant2_Hz = 1500
    formant3_Hz = 2500
    formant_Q = 4.0
    start_rolloff_alpha = 0.95
    end_rolloff_alpha = 0.42
    companion_mix = 0.26
    family_instability_depth = 0.38
    noise_dissolution = 0.68
    respiratory_rate_Hz = 0.24
    respiratory_depth = 0.06

    presetName$ = "Fast Spectral Dissolution"

elsif preset = 5
    fundamental_Hz = 55.0
    number_of_partials = 16
    duration_s = 60
    inharmonicity_target = 0.01
    threshold_split_strength = 0.40
    temporal_curve = 1
    spectral_envelope = 1
    combination_layer = 1
    process_form = 1

    formant1_Hz = 500
    formant2_Hz = 1500
    formant3_Hz = 2500
    formant_Q = 4.0
    start_rolloff_alpha = 0.90
    end_rolloff_alpha = 0.90
    companion_mix = 0.10
    family_instability_depth = 0.12
    noise_dissolution = 0.04
    respiratory_rate_Hz = 0.055
    respiratory_depth = 0.16

    presetName$ = "Static Harmonic Shimmer"

elsif preset = 6
    fundamental_Hz = 110.0
    number_of_partials = 18
    duration_s = 25
    inharmonicity_target = 0.055
    threshold_split_strength = 0.90
    temporal_curve = 1
    spectral_envelope = 2
    combination_layer = 1
    process_form = 2

    formant1_Hz = 700
    formant2_Hz = 1200
    formant3_Hz = 2600
    formant_Q = 4.5
    start_rolloff_alpha = 1.08
    end_rolloff_alpha = 0.80
    companion_mix = 0.16
    family_instability_depth = 0.20
    noise_dissolution = 0.14
    respiratory_rate_Hz = 0.17
    respiratory_depth = 0.11

    presetName$ = "Prologue-inspired Vowel Weighting"
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE 1
# ---------------------------------------------------------------------------
if edit_spectral_details
    beginPause: "Spectral Becoming - Spectrum / Threshold Details"
        positive: "Emphasis peak 1 (Hz)", formant1_Hz
        positive: "Emphasis peak 2 (Hz)", formant2_Hz
        positive: "Emphasis peak 3 (Hz)", formant3_Hz
        positive: "Emphasis Q", formant_Q
        positive: "Start rolloff alpha", start_rolloff_alpha
        positive: "End rolloff alpha", end_rolloff_alpha
        real: "Threshold companion mix (0..0.6)", companion_mix
        real: "Family instability depth (0..0.8)", family_instability_depth
    endPause: "Continue", 1
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE 2
# ---------------------------------------------------------------------------
if edit_process_details
    beginPause: "Spectral Becoming - Process / Output Details"
        real: "Noise dissolution (0..1)", noise_dissolution
        positive: "Respiratory modulation rate (Hz)", respiratory_rate_Hz
        real: "Respiratory modulation depth (0..0.5)", respiratory_depth
        integer: "Random seed (0 = unpredictable)", random_seed
        integer: "Output sample rate (Hz)", sample_rate_Hz
        boolean: "Adaptive internal render rate", adaptive_render_rate
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------------
if fundamental_Hz <= 0
    exitScript: "Fundamental must be greater than zero."
endif
if number_of_partials < 2 or number_of_partials > 64
    exitScript: "Number of partials must be between 2 and 64."
endif
if duration_s <= 0 or duration_s > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if inharmonicity_target < 0 or inharmonicity_target > 0.60
    exitScript: "Inharmonicity target must be between 0 and 0.60."
endif
if threshold_split_strength <= 0 or threshold_split_strength > 5
    exitScript: "Threshold split strength must be > 0 and <= 5."
endif
if formant_Q <= 0 or formant_Q > 30
    exitScript: "Emphasis Q must be > 0 and <= 30."
endif
if start_rolloff_alpha <= 0 or end_rolloff_alpha <= 0
    exitScript: "Rolloff alpha values must be greater than zero."
endif
if companion_mix < 0 or companion_mix > 0.60
    exitScript: "Threshold companion mix must be between 0 and 0.60."
endif
if family_instability_depth < 0 or family_instability_depth > 0.80
    exitScript: "Family instability depth must be between 0 and 0.80."
endif
if noise_dissolution < 0 or noise_dissolution > 1
    exitScript: "Noise dissolution must be between 0 and 1."
endif
if respiratory_rate_Hz <= 0 or respiratory_rate_Hz > 5
    exitScript: "Respiratory modulation rate must be > 0 and <= 5 Hz."
endif
if respiratory_depth < 0 or respiratory_depth > 0.50
    exitScript: "Respiratory modulation depth must be between 0 and 0.50."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif

output_sr = sample_rate_Hz
duration = duration_s
nPartials = number_of_partials
inharm = inharmonicity_target
detStrength = threshold_split_strength

# Correct temporal semantics.
if temporal_curve = 1
    curveName$ = "Linear"
elsif temporal_curve = 2
    curveName$ = "Logarithmic / early change"
else
    curveName$ = "Exponential / late change"
endif

if spectral_envelope = 1
    envelopeName$ = "Flat rolloff"
else
    envelopeName$ = "Three emphasis peaks"
endif

if combination_layer = 1
    combinationName$ = "Off"
elsif combination_layer = 2
    combinationName$ = "Difference frequencies"
else
    combinationName$ = "Difference + sum frequencies"
endif

if process_form = 1
    processName$ = "Simple process"
else
    processName$ = "Five-stage becoming"
endif

# ---------------------------------------------------------------------------
# COMMON SAMPLE-RATE SCALING
# ---------------------------------------------------------------------------
familyLowMax = max(1,floor(nPartials/4))
familyMidMax = max(familyLowMax+1,floor(2*nPartials/3))
familyMidMax = min(nPartials-1,familyMidMax)

maxSplitHz = 24*detStrength*(1+family_instability_depth)
requestedTop =
    ... fundamental_Hz*nPartials^(1+inharm)+maxSplitHz

# If explicit sum-frequency consequences are enabled, adaptive render-rate
# planning must also include the highest sum that can actually be synthesized.
# The combination layer uses pairs from the first min(6,nPartials) primaries.
if combination_layer = 3
    pairLimitForTop = min(6,nPartials)

    if pairLimitForTop >= 2
        sumTopStart =
            ... fundamental_Hz*pairLimitForTop+
            ... fundamental_Hz*(pairLimitForTop-1)

        sumTopTarget =
            ... fundamental_Hz*pairLimitForTop^(1+inharm)+
            ... fundamental_Hz*(pairLimitForTop-1)^(1+inharm)

        requestedTop = max(requestedTop,max(sumTopStart,sumTopTarget))
    endif
endif

# Adaptive internal rendering:
# keep requested spectral top below ~32 percent of the internal sample rate,
# with a 16-kHz minimum for comfortable waveform resolution. The final Sound
# is resampled once to output_sr.
if adaptive_render_rate
    minimumRenderRate = 16000
    rateNeeded = 1000*ceiling((requestedTop/0.32)/1000)
    sr = min(output_sr,max(minimumRenderRate,rateNeeded))
else
    sr = output_sr
endif

safeTop = 0.45*sr
frequencyScale = min(1,safeTop/requestedTop)

effectiveF0 = fundamental_Hz*frequencyScale
effectiveFormant1 = formant1_Hz*frequencyScale
effectiveFormant2 = formant2_Hz*frequencyScale
effectiveFormant3 = formant3_Hz*frequencyScale
splitScale = frequencyScale

if effectiveF0 < 20
    exitScript: "Requested spectrum requires the common field below 20 Hz. Reduce partial count/inharmonicity/fundamental or increase sample rate."
endif

# ---------------------------------------------------------------------------
# RANDOM GENERATOR
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
# PROCESS CONTROL SOUNDS
# ---------------------------------------------------------------------------
# Shared morph m(t), 0..1.
if temporal_curve = 1
    morphExpr$ = "x/" + fixed$(duration,9)
elsif temporal_curve = 2
    # Concave log curve: large change early, smaller change late.
    morphExpr$ = "ln(1+9*x/" + fixed$(duration,9) + ")/ln(10)"
else
    # Convex exponential curve: small change early, larger change late.
    morphExpr$ = "(exp(3*x/" + fixed$(duration,9)
        ... + ")-1)/(exp(3)-1)"
endif

Create Sound from formula:
    ... "becoming_morph_" + uid$,1,0,duration,sr,morphExpr$
morphControl = selected("Sound")

# Process form control: amplitude and blur are different dimensions.
if process_form = 1
    fadeIn = min(2,max(0.03,0.05*duration))
    fadeOut = min(3,max(0.05,0.10*duration))
    fadeOutStart = duration-fadeOut

    macroExpr$ = "if x<" + fixed$(fadeIn,9)
        ... + " then 0.5-0.5*cos(pi*x/" + fixed$(fadeIn,9)
        ... + ") else if x>" + fixed$(fadeOutStart,9)
        ... + " then 0.5+0.5*cos(pi*(x-" + fixed$(fadeOutStart,9)
        ... + ")/" + fixed$(fadeOut,9) + ") else 1 fi fi"

    blurExpr$ = morphExpr$

    stage1End = fadeIn
    stage2End = 0.25*duration
    stage3End = 0.55*duration
    stage4End = fadeOutStart

else
    # ENGINE-SPECIFIC five-stage formal model:
    # emergence 0-.07; stabilization .07-.22; magnification .22-.55;
    # liminal blur .55-.82; extinction .82-1.
    stage1End = 0.07*duration
    stage2End = 0.22*duration
    stage3End = 0.55*duration
    stage4End = 0.82*duration

    s1$ = fixed$(stage1End,9)
    s2$ = fixed$(stage2End,9)
    s3$ = fixed$(stage3End,9)
    s4$ = fixed$(stage4End,9)
    dur$ = fixed$(duration,9)

    macroExpr$ = "if x<" + s1$
        ... + " then x/" + s1$
        ... + " else if x<" + s2$
        ... + " then 1-0.05*(x-" + s1$ + ")/(" + s2$ + "-" + s1$ + ")"
        ... + " else if x<" + s3$
        ... + " then 0.95+0.20*(x-" + s2$ + ")/(" + s3$ + "-" + s2$ + ")"
        ... + " else if x<" + s4$
        ... + " then 1.15-0.60*(x-" + s3$ + ")/(" + s4$ + "-" + s3$ + ")"
        ... + " else 0.55*(1-(x-" + s4$ + ")/(" + dur$ + "-" + s4$ + "))^2 fi fi fi fi"

    # Blur is a spectral-state control, not merely level:
    # zero through stabilization, modest in magnification, strong in liminal.
    blurExpr$ = "if x<" + s2$
        ... + " then 0"
        ... + " else if x<" + s3$
        ... + " then 0.25*(x-" + s2$ + ")/(" + s3$ + "-" + s2$ + ")"
        ... + " else if x<" + s4$
        ... + " then 0.25+0.75*(x-" + s3$ + ")/(" + s4$ + "-" + s3$ + ")"
        ... + " else 1 fi fi fi"
endif

Create Sound from formula:
    ... "becoming_macro_" + uid$,1,0,duration,sr,macroExpr$
macroControl = selected("Sound")

Create Sound from formula:
    ... "becoming_blur_" + uid$,1,0,duration,sr,blurExpr$
blurControl = selected("Sound")

# ---------------------------------------------------------------------------
# THREE ACTUAL FAMILY-CORRELATED INSTABILITY CONTROLS
# ---------------------------------------------------------------------------
controlRate = 80
familyRate# = {0.055,0.13,0.28}
familyControl# = zero#(3)

for fam from 1 to 3
    a = exp(-2*pi*familyRate#[fam]/controlRate)
    b = sqrt(max(0,1-a*a))*0.55

    Create Sound from formula:
        ... "family_walk_" + string$(fam) + "_" + uid$,
        ... 1,0,duration,controlRate,"0"
    raw = selected("Sound")

    Formula: "if col=1 then 0 else tanh("
        ... + fixed$(a,12) + "*self[col-1]+"
        ... + fixed$(b,12) + "*randomGauss(0,1)) fi"

    Resample: sr,50
    familyControl#[fam] = selected("Sound")
    removeObject: raw
endfor

# ---------------------------------------------------------------------------
# STATIC REFERENCE VALUES + ENERGY NORMALIZATION
# ---------------------------------------------------------------------------
fStart# = zero#(nPartials)
fTarget# = zero#(nPartials)
ampStartRef# = zero#(nPartials)
ampEndRef# = zero#(nPartials)
family# = zero#(nPartials)
splitBase# = zero#(nPartials)

sumStartEnergy = 0
sumEndEnergy = 0
maxPrimaryFreq = 0

bw1 = effectiveFormant1/formant_Q
bw2 = effectiveFormant2/formant_Q
bw3 = effectiveFormant3/formant_Q

for pn from 1 to nPartials
    fS = effectiveF0*pn
    fT = effectiveF0*pn^(1+inharm)

    fStart#[pn] = fS
    fTarget#[pn] = fT
    maxPrimaryFreq = max(maxPrimaryFreq,fT)

    if pn <= familyLowMax
        fam = 1
        splitBase#[pn] = 1.0*detStrength*splitScale
    elsif pn <= familyMidMax
        fam = 2
        splitBase#[pn] = 8.0*detStrength*splitScale
    else
        fam = 3
        splitBase#[pn] = 24.0*detStrength*splitScale
    endif
    family#[pn] = fam

    rollS = 1/pn^start_rolloff_alpha
    rollE = 1/pn^end_rolloff_alpha

    if spectral_envelope = 1
        envS = 1
        envE = 1
    else
        r1 = bw1*bw1/(bw1*bw1+(fS-effectiveFormant1)^2)
        r2 = bw2*bw2/(bw2*bw2+(fS-effectiveFormant2)^2)
        r3 = bw3*bw3/(bw3*bw3+(fS-effectiveFormant3)^2)
        envS = max(max(r1,r2),r3)
        envS = max(0.08,envS)

        r1 = bw1*bw1/(bw1*bw1+(fT-effectiveFormant1)^2)
        r2 = bw2*bw2/(bw2*bw2+(fT-effectiveFormant2)^2)
        r3 = bw3*bw3/(bw3*bw3+(fT-effectiveFormant3)^2)
        envE = max(max(r1,r2),r3)
        envE = max(0.08,envE)
    endif

    ampStartRef#[pn] = rollS*envS
    ampEndRef#[pn] = rollE*envE

    sumStartEnergy = sumStartEnergy+ampStartRef#[pn]^2
    sumEndEnergy = sumEndEnergy+ampEndRef#[pn]^2
endfor

energyReference = max(sumStartEnergy,sumEndEnergy)
globalAmpScale =
    ... 0.62/sqrt(max(1e-12,energyReference*(1+companion_mix^2)))

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  SPECTRAL BECOMING ENGINE v2.1.3"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Concept: Grisey-inspired process engine, not score reconstruction"
appendInfoLine: "Fundamental / effective: ",
    ... fixed$(fundamental_Hz,2), " / ", fixed$(effectiveF0,2), " Hz"
appendInfoLine: "Partials: ", nPartials
appendInfoLine: "Harmonic -> inharmonic target: ", fixed$(inharm,4)
appendInfoLine: "Temporal morph: ", curveName$
appendInfoLine: "Process form: ", processName$
appendInfoLine: "Spectral envelope: ", envelopeName$
appendInfoLine: "Threshold split strength: x", fixed$(detStrength,2)
appendInfoLine: "Companion mix: ", fixed$(companion_mix,3)
appendInfoLine: "Noise dissolution: ", fixed$(noise_dissolution,3)
appendInfoLine: "Combination layer: ", combinationName$
appendInfoLine: "Common frequency scale: ", fixed$(frequencyScale,5)
appendInfoLine: "Internal render / output rate: ",
    ... sr, " / ", output_sr, " Hz"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# ACCUMULATOR
# ---------------------------------------------------------------------------
Create Sound from formula:
    ... "spectral_becoming_accumulator_" + uid$,
    ... 1,0,duration,sr,"0"
accumulator = selected("Sound")

# ---------------------------------------------------------------------------
# PROCEDURE: SYNTHESIZE PRIMARY + THRESHOLD COMPANION
# ---------------------------------------------------------------------------
procedure synthPrimaryPair: .pn

    .fS = fStart#[.pn]
    .fT = fTarget#[.pn]
    .fam = family#[.pn]
    .split = splitBase#[.pn]
    .familyID = familyControl#[.fam]

    # Primary instantaneous frequency.
    .freqExpr$ = fixed$(.fS,9) + "+("
        ... + fixed$(.fT-.fS,9) + ")*object["
        ... + string$(morphControl) + ",1,col]"

    Create Sound from formula:
        ... "freq_primary_" + string$(.pn) + "_" + uid$,
        ... 1,0,duration,sr,.freqExpr$
    .freq = selected("Sound")

    # Dynamic rolloff independent of inharmonicity.
    .alphaExpr$ = "(" + fixed$(start_rolloff_alpha,9)
        ... + "+(" + fixed$(end_rolloff_alpha-start_rolloff_alpha,9)
        ... + ")*object[" + string$(morphControl) + ",1,col])"

    .rollExpr$ = "exp(-ln(" + string$(.pn) + ")*" + .alphaExpr$ + ")"

    if spectral_envelope = 1
        .specExpr$ = "1"
    else
        .fObj$ = "object[" + string$(.freq) + ",1,col]"
        .r1$ = "(" + fixed$(bw1*bw1,9) + "/("
            ... + fixed$(bw1*bw1,9) + "+(" + .fObj$ + "-"
            ... + fixed$(effectiveFormant1,9) + ")^2))"
        .r2$ = "(" + fixed$(bw2*bw2,9) + "/("
            ... + fixed$(bw2*bw2,9) + "+(" + .fObj$ + "-"
            ... + fixed$(effectiveFormant2,9) + ")^2))"
        .r3$ = "(" + fixed$(bw3*bw3,9) + "/("
            ... + fixed$(bw3*bw3,9) + "+(" + .fObj$ + "-"
            ... + fixed$(effectiveFormant3,9) + ")^2))"
        .specExpr$ = "max(0.08,max(max(" + .r1$ + "," + .r2$
            ... + ")," + .r3$ + "))"
    endif

    .ampExpr$ = fixed$(globalAmpScale,9) + "*"
        ... + .rollExpr$ + "*" + .specExpr$
        ... + "*object[" + string$(macroControl) + ",1,col]"
        ... + "*(1+" + fixed$(respiratory_depth,9)
        ... + "*sin(2*pi*" + fixed$(respiratory_rate_Hz,9) + "*x))"

    Create Sound from formula:
        ... "amp_primary_" + string$(.pn) + "_" + uid$,
        ... 1,0,duration,sr,.ampExpr$
    .amp = selected("Sound")

    # Audio-rate phase integration.
    Create Sound from formula:
        ... "primary_" + string$(.pn) + "_" + uid$,
        ... 1,0,duration,sr,"0"
    .primary = selected("Sound")

    Formula: "if col=1 then 0 else self[col-1]+2*pi*object["
        ... + string$(.freq) + ",1,col]/" + string$(sr) + " fi"

    .phase = randomUniform(0,2*pi)
    Formula: "object[" + string$(.amp) + ",1,col]*sin(self+"
        ... + fixed$(.phase,9) + ")"

    selectObject: accumulator
    Formula: "self+object[" + string$(.primary) + ",1,col]"

    # ----------------------------------------------------------
    # THRESHOLD COMPANION
    # ----------------------------------------------------------
    # Low and mid alternate upward/downward companions to avoid imposing a
    # systematic center-frequency shift. High family always splits upward.
    if .fam = 3
        .sign = 1
    else
        if (.pn mod 2)=0
            .sign = -1
        else
            .sign = 1
        endif
    endif

    .splitExpr$ = fixed$(.sign*.split,9)
        ... + "*object[" + string$(morphControl) + ",1,col]"
        ... + "*(1+" + fixed$(family_instability_depth,9)
        ... + "*object[" + string$(.familyID) + ",1,col])"

    .compFreqExpr$ = .freqExpr$ + "+(" + .splitExpr$ + ")"

    Create Sound from formula:
        ... "freq_comp_" + string$(.pn) + "_" + uid$,
        ... 1,0,duration,sr,.compFreqExpr$
    .compFreq = selected("Sound")

    Create Sound from formula:
        ... "companion_" + string$(.pn) + "_" + uid$,
        ... 1,0,duration,sr,"0"
    .comp = selected("Sound")

    Formula: "if col=1 then 0 else self[col-1]+2*pi*object["
        ... + string$(.compFreq) + ",1,col]/" + string$(sr) + " fi"

    Formula: "object[" + string$(.amp) + ",1,col]*"
        ... + fixed$(companion_mix,9)
        ... + "*(0.40+0.60*object[" + string$(morphControl)
        ... + ",1,col])*sin(self+" + fixed$(.phase,9) + ")"

    selectObject: accumulator
    Formula: "self+object[" + string$(.comp) + ",1,col]"

    removeObject: .primary,.comp,.freq,.compFreq,.amp
endproc

# ---------------------------------------------------------------------------
# PRIMARY SPECTRAL FIELD
# ---------------------------------------------------------------------------
appendInfoLine: "[1/4] Synthesizing primary + threshold-companion field..."

for pn from 1 to nPartials
    @synthPrimaryPair: pn

    if (pn mod 4)=0 or pn=nPartials
        appendInfoLine: "  Partial pair ", pn, " / ", nPartials
    endif
endfor

# ---------------------------------------------------------------------------
# PROCEDURE: SYNTHESIZE SIMPLE COMBINATION-FREQUENCY COMPONENT
# ---------------------------------------------------------------------------
procedure synthCombination: .fS,.fT,.ampScale,.label$

    if .fS > 20 and .fT > 20 and
        ... .fS < safeTop and .fT < safeTop

        .freqExpr$ = fixed$(.fS,9) + "+("
            ... + fixed$(.fT-.fS,9) + ")*object["
            ... + string$(morphControl) + ",1,col]"

        Create Sound from formula:
            ... "freq_comb_" + .label$ + "_" + uid$,
            ... 1,0,duration,sr,.freqExpr$
        .freq = selected("Sound")

        Create Sound from formula:
            ... "comb_" + .label$ + "_" + uid$,
            ... 1,0,duration,sr,"0"
        .osc = selected("Sound")

        Formula: "if col=1 then 0 else self[col-1]+2*pi*object["
            ... + string$(.freq) + ",1,col]/" + string$(sr) + " fi"

        .phase = randomUniform(0,2*pi)
        Formula: fixed$(.ampScale,9)
            ... + "*object[" + string$(macroControl) + ",1,col]"
            ... + "*(1+" + fixed$(respiratory_depth,9)
            ... + "*sin(2*pi*" + fixed$(respiratory_rate_Hz,9) + "*x))"
            ... + "*sin(self+" + fixed$(.phase,9) + ")"

        selectObject: accumulator
        Formula: "self+object[" + string$(.osc) + ",1,col]"

        removeObject: .osc,.freq
        .created = 1
    else
        .created = 0
    endif
endproc

# ---------------------------------------------------------------------------
# OPTIONAL COMBINATION-FREQUENCY EXTERNALIZATION
# ---------------------------------------------------------------------------
nConsequences = 0

if combination_layer > 1
    appendInfoLine: "[2/4] Externalizing combination-frequency relations..."

    pairLimit = min(6,nPartials)

    for ii from 1 to pairLimit
        for jj from ii+1 to pairLimit
            diffS = abs(fStart#[jj]-fStart#[ii])
            diffT = abs(fTarget#[jj]-fTarget#[ii])

            ampRef =
                ... 0.065*globalAmpScale*
                ... sqrt(ampStartRef#[ii]*ampStartRef#[jj])

            @synthCombination:
                ... diffS,diffT,ampRef,
                ... "D" + string$(ii) + "_" + string$(jj)

            if synthCombination.created
                nConsequences = nConsequences+1
            endif

            if combination_layer = 3
                sumS = fStart#[jj]+fStart#[ii]
                sumT = fTarget#[jj]+fTarget#[ii]

                ampRef =
                    ... 0.045*globalAmpScale*
                    ... sqrt(ampStartRef#[ii]*ampStartRef#[jj])

                @synthCombination:
                    ... sumS,sumT,ampRef,
                    ... "S" + string$(ii) + "_" + string$(jj)

                if synthCombination.created
                    nConsequences = nConsequences+1
                endif
            endif
        endfor
    endfor

    appendInfoLine: "  Explicit combination components: ", nConsequences
else
    appendInfoLine: "[2/4] Combination-frequency layer: off"
endif

# ---------------------------------------------------------------------------
# LATE SPECTRAL BLUR / NOISE DISSOLUTION
# ---------------------------------------------------------------------------
appendInfoLine: "[3/4] Applying spectral blur/noise continuum..."

if noise_dissolution > 0
    noiseLow = max(80,2.5*effectiveF0)
    noiseHigh = min(safeTop,max(2500,1.10*maxPrimaryFreq))

    if noiseHigh > noiseLow+100
        Create Sound from formula:
            ... "becoming_noise_" + uid$,1,0,duration,sr,
            ... "randomGauss(0,1)"
        rawNoise = selected("Sound")

        Filter (pass Hann band): noiseLow,noiseHigh,
            ... min(300,max(30,0.10*(noiseHigh-noiseLow)))
        noiseBand = selected("Sound")
        removeObject: rawNoise

        selectObject: noiseBand
        noiseRMS = Get root-mean-square: 0,0

        if noiseRMS > 1e-12
            Formula: "self/" + fixed$(noiseRMS,12)
        endif

        Formula: "self*" + fixed$(0.16*noise_dissolution,9)
            ... + "*object[" + string$(blurControl) + ",1,col]"
            ... + "*object[" + string$(macroControl) + ",1,col]"

        selectObject: accumulator
        Formula: "self+object[" + string$(noiseBand) + ",1,col]"

        removeObject: noiseBand
    endif
endif

# ---------------------------------------------------------------------------
# FINAL OUTPUT-RATE CONVERSION
# ---------------------------------------------------------------------------
if sr <> output_sr
    selectObject: accumulator
    Resample: output_sr,50
    resampledOutput = selected("Sound")
    removeObject: accumulator
    accumulator = resampledOutput
endif

# ---------------------------------------------------------------------------
# FINAL LEVEL
# ---------------------------------------------------------------------------
selectObject: accumulator
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

safePreset$ = replace$(presetName$," ","_",0)
Rename: "Spectral_Becoming_" + safePreset$
finalOutput = selected("Sound")

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0

# Randomness no longer needed after all audio has been generated.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

appendInfoLine: "[4/4] Finalized."
appendInfoLine: ""
appendInfoLine: "Primary pairs: ", nPartials
appendInfoLine: "Combination components: ", nConsequences
appendInfoLine: "Requested / internal-safe spectral top: ",
    ... fixed$(requestedTop,1), " / ", fixed$(safeTop,1), " Hz"
appendInfoLine: "Internal render / output rate: ",
    ... sr, " / ", output_sr, " Hz"
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
# CLEANUP CONTROLS AFTER VISUALIZATION
# ---------------------------------------------------------------------------
removeObject: morphControl,macroControl,blurControl
for fam from 1 to 3
    removeObject: familyControl#[fam]
endfor

# ---------------------------------------------------------------------------
# PLAY + SELECT
# ---------------------------------------------------------------------------
selectObject: finalOutput
if play_result
    Play
endif

appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: ""
appendInfoLine: "Conceptual note:"
appendInfoLine: "This engine models a spectral ATTITUDE: continuous mutation,"
appendInfoLine: "threshold relations and harmonic/inharmonic/noise becoming."
appendInfoLine: "Its five-stage process and threshold-family values are"
appendInfoLine: "compositional designs, not historical Grisey formulas."

selectObject: finalOutput


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .low$ = "{0.86,0.55,0.18}"
    .mid$ = "{0.25,0.58,0.38}"
    .high$ = "{0.18,0.43,0.72}"
    .purple$ = "{0.52,0.30,0.62}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.32
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "SPECTRAL BECOMING ENGINE | " + presetName$

    Select inner viewport: 0.35,7.65,0.36,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... string$(nPartials) + " primary+companion pairs | "
        ... + curveName$ + " | " + processName$
    Text: 0.5,"centre",0.20,"half",
        ... "harmonic field -> inharmonic morph + threshold splitting -> liminal noise blur -> extinction"

    # -----------------------------------------------------------------------
    # PANEL A: MODEL TRAJECTORIES
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.78,1.00
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  SPECTRAL BECOMING | primary trajectories + threshold-companion separation"

    .plotTop = min(safeTop,1.08*(maxPrimaryFreq+maxSplitHz*frequencyScale))
    .plotTop = max(1000,.plotTop)

    Select inner viewport: .left,.right,1.07,2.35
    Axes: 0,duration,0,.plotTop
    Paint rectangle: .bg$,0,duration,0,.plotTop

    Colour: .grid$
    Dotted line
    .gridStep = max(500,round(.plotTop/5/100)*100)
    .gf = .gridStep
    while .gf < .plotTop
        Draw line: 0,.gf,duration,.gf
        .gf = .gf+.gridStep
    endwhile
    Plain line

    .drawStep = max(1,ceiling(nPartials/24))
    .nPts = 60

    for .pn from 1 to nPartials
        if ((.pn-1) mod .drawStep)=0
            .fam = family#[.pn]

            if .fam=1
                Colour: .low$
            elsif .fam=2
                Colour: .mid$
            else
                Colour: .high$
            endif

            .fS = fStart#[.pn]
            .fT = fTarget#[.pn]

            .prevT = 0
            .prevF = .fS

            Line width: 1.1
            for .k from 1 to .nPts
                .t = .k/.nPts*duration
                .u = .t/duration

                if temporal_curve=1
                    .m = .u
                elsif temporal_curve=2
                    .m = ln(1+9*.u)/ln(10)
                else
                    .m = (exp(3*.u)-1)/(exp(3)-1)
                endif

                .f = .fS+(.fT-.fS)*.m
                Draw line: .prevT,.prevF,.t,.f
                .prevT = .t
                .prevF = .f
            endfor

            # Companion nominal separation (without the stochastic family walk)
            if .fam=3
                .sign = 1
            else
                if (.pn mod 2)=0
                    .sign = -1
                else
                    .sign = 1
                endif
            endif

            Colour: "{0.60,0.60,0.64}"
            Dashed line
            .prevT = 0
            .prevF = .fS

            for .k from 1 to .nPts
                .t = .k/.nPts*duration
                .u = .t/duration

                if temporal_curve=1
                    .m = .u
                elsif temporal_curve=2
                    .m = ln(1+9*.u)/ln(10)
                else
                    .m = (exp(3*.u)-1)/(exp(3)-1)
                endif

                .f = .fS+(.fT-.fS)*.m+
                    ... .sign*splitBase#[.pn]*.m

                Draw line: .prevT,.prevF,.t,.f
                .prevT = .t
                .prevF = .f
            endfor
            Solid line
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL PROCESS CONTROLS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.51,2.73
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  ACTUAL PROCESS CONTROLS | morph, spectral blur and macro-level trajectory"

    Select inner viewport: .left,.right,2.80,3.72
    Axes: 0,duration,0,1.25
    Paint rectangle: .bg$,0,duration,0,1.25

    selectObject: morphControl
    Colour: .high$
    Draw: 0,0,0,1.25,"no","Curve"

    selectObject: blurControl
    Colour: .purple$
    Draw: 0,0,0,1.25,"no","Curve"

    selectObject: macroControl
    Colour: .low$
    Draw: 0,0,0,1.25,"no","Curve"

    Axes: 0,duration,0,1.25
    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text: 0.02*duration,"left",1.17,"half",
        ... "blue=morph   purple=blur   orange=macro level"

    # -----------------------------------------------------------------------
    # PANEL C: ACTUAL FAMILY SPLIT TRAJECTORIES
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.88,4.10
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  THRESHOLD COMPANIONS | actual family-correlated component separation"

    .splitTop = 1.35*24*detStrength*splitScale*(1+family_instability_depth)
    .splitTop = max(4,.splitTop)

    Select inner viewport: .left,.right,4.17,5.07
    Axes: 0,duration,0,.splitTop
    Paint rectangle: .bg$,0,duration,0,.splitTop

    for .fam from 1 to 3
        if .fam=1
            .base = 1*detStrength*splitScale
            Colour: .low$
        elsif .fam=2
            .base = 8*detStrength*splitScale
            Colour: .mid$
        else
            .base = 24*detStrength*splitScale
            Colour: .high$
        endif

        Create Sound from formula:
            ... "split_viz_" + string$(.fam) + "_" + uid$,
            ... 1,0,duration,sr,
            ... fixed$(.base,9) + "*object[" + string$(morphControl)
            ... + ",1,col]*(1+" + fixed$(family_instability_depth,9)
            ... + "*object[" + string$(familyControl#[.fam]) + ",1,col])"
        .splitSound = selected("Sound")

        Draw: 0,0,0,.splitTop,"no","Curve"
        removeObject: .splitSound
    endfor

    Axes: 0,duration,0,.splitTop
    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Pair separation (Hz)"
    Font size: 5
    Text: 0.02*duration,"left",0.92*.splitTop,"half",
        ... "heuristic zones; perceptual thresholds depend on carrier frequency/context"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.23,5.45
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + selected primary trajectories"

    .specMax = min(safeTop,max(3000,1.12*maxPrimaryFreq))
    .specStep = max(0.002,duration/1200)

    # Spectrogram does not need the full output sampling rate when the plotted
    # bandwidth is only a few kHz. Analyse a temporary bandwidth-appropriate
    # copy to reduce visualization time.
    .vizRateNeeded = 1000*ceiling((.specMax/0.38)/1000)
    .vizRate = min(output_sr,max(12000,.vizRateNeeded))

    selectObject: finalOutput
    if .vizRate < output_sr
        Resample: .vizRate,30
        .vizSound = selected("Sound")
    else
        Copy: "becoming_viz_" + uid$
        .vizSound = selected("Sound")
    endif

    selectObject: .vizSound
    To Spectrogram: 0.035,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.52,6.57
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec,.vizSound

    Axes: 0,duration,0,.specMax
    .guideStep = max(1,ceiling(nPartials/10))
    Colour: "{0.25,0.55,0.82}"
    Line width: 0.7

    for .pn from 1 to nPartials
        if ((.pn-1) mod .guideStep)=0
            .fS = fStart#[.pn]
            .fT = fTarget#[.pn]
            .prevT = 0
            .prevF = .fS

            for .k from 1 to 40
                .t = .k/40*duration
                .u = .t/duration

                if temporal_curve=1
                    .m = .u
                elsif temporal_curve=2
                    .m = ln(1+9*.u)/ln(10)
                else
                    .m = (exp(3*.u)-1)/(exp(3)-1)
                endif

                .f = .fS+(.fT-.fS)*.m

                if .prevF<=.specMax and .f<=.specMax
                    Draw line: .prevT,.prevF,.t,.f
                endif

                .prevT = .t
                .prevF = .f
            endfor
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

    # -----------------------------------------------------------------------
    # QC / CONCEPT SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.78,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.78,"half",
        ... "CONCEPT  |  process / thresholds / harmonicity->inharmonicity->noise; inspired, not score reconstruction"

    Text: 0.02,"left",0.55,"half",
        ... "SPECTRUM  |  f0 " + fixed$(effectiveF0,1)
        ... + " Hz  |  " + string$(nPartials)
        ... + " pairs  |  combinations " + string$(nConsequences)
        ... + "  |  noise " + fixed$(noise_dissolution,2)

    Text: 0.02,"left",0.32,"half",
        ... "QC  |  requested top " + fixed$(requestedTop,0)
        ... + " Hz  |  render safe " + fixed$(safeTop,0)
        ... + " Hz  |  render/output " + string$(sr) + "/"
        ... + string$(output_sr) + " Hz  |  scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .levelText$ = "down-only protection applied"
    else
        .levelText$ = "level preserved"
    endif

    Text: 0.02,"left",0.09,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  pre-RMS " + fixed$(preProtectRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .levelText$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
