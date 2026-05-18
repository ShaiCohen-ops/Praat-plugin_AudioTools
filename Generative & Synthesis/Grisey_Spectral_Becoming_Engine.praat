# ============================================================
# Praat AudioTools - Grisey_Spectral_Becoming_Engine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral synthesis engine inspired by Gerard Grisey's concept
#   of "spectral becoming" (devenir spectral). v2.0 is a substantial
#   compositional upgrade that treats the spectrum as an evolving
#   organism rather than a Fourier table.
#
#   Six new compositional layers (all per Grisey's actual practice):
#
#     1. Per-partial amplitude shaping via formant-bank spectral
#        envelope. Replaces the uniform 1/n^alpha rolloff: each
#        partial is now emphasized or attenuated according to its
#        frequency's position relative to 3 user-configurable
#        formant peaks.
#
#     2. Five-stage temporal macroform (attack -> resonance ->
#        magnification -> threshold -> extinction). Replaces the
#        simple cosine fade with a piecewise envelope that traces
#        a Grisey sound-object's life cycle. Threshold stage drops
#        amplitude into the "perceptual ambiguity zone" before
#        extinction.
#
#     3. Perceptual-zone detuning families. Partials are grouped
#        into three families (low / mid / high) mapped to Grisey's
#        perceptual breakpoints:
#          - low family   -> 0-2 Hz   (fused beating / roughness)
#          - mid family   -> 4-15 Hz  (audible pulsation)
#          - high family  -> 20+ Hz   (timbral / spectral fission)
#        Each family gets a shared base detune; per-partial jitter
#        is small (correlated drift, not random scatter).
#
#     4. Spectral consequences -- difference and sum tones treated
#        as first-class chirping partials. For pairs of primary
#        partials, generates audible (1/dist^2 amp) ghost partials
#        at f_j - f_i and f_j + f_i. This is the Murail/Grisey
#        "make the psychoacoustic consequence audible" move; the
#        texture becomes a living spectral field rather than a
#        bank of oscillators.
#
#     5. Family-correlated instability (flows from #3): low family
#        stays anchored, mid family drifts as a group, high family
#        splinters. Sign of detune is family-dependent (high
#        always detunes upward, widening the spectrum).
#
#     6. Partiels preset corrected: f0 = 82.41 Hz (E2 trombone),
#        not 41.2 Hz (E1). Now uses Formant envelope (low-mid
#        formant emphasis) and difference tones (the iconic
#        bottom-up reveal of the spectrum in Partiels' opening).
#
#   References:
#     - Grisey, G. (1987). Tempus ex Machina. Contemporary Music Review.
#     - Grisey: Partiels (1975), Les Espaces Acoustiques (1974-85)
#     - Murail, T. (2005). The Revolution of Complex Sounds.
#     - Fineberg, J. (2000). Spectral Music. Contemporary Music Review.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Generative & Synthesis Systems
#
# Changelog v2.0:
#   - Six-layer musical upgrade (see Description). Audio is NOT
#     bit-identical to v1.0 -- the spectrum, temporal shape, and
#     detuning behavior have all changed substantially. This is
#     intentional: v1.0 produced a smooth chirp, v2.0 produces a
#     Grisey-like spectral organism. For v1.0 behavior, set
#     Spectral_envelope=Flat, Macroform=Simple, Spectral_consequences=Off.
#   - Partiels preset f0 changed from 41.2 Hz (E1) to 82.41 Hz (E2).
#     The entire spectrum is now an octave higher. Other Partiels-
#     specific values also retuned for the new fundamental.
#   - All Praat-side suite polish (dropped decorative form `=== ===`
#     rows, output filename now includes preset suffix, suite-styled
#     visualization with macroform overlay).
# ============================================================

# ============================================================
# FORM
# ============================================================
form Grisey - Spectral Becoming Engine v2.0
    optionmenu Preset: 2
        option Custom
        option Partiels (trombone E2, formant + difference tones)
        option Gondwana (deep drift, formants)
        option Vortex (fast dissolution)
        option Meditation (static shimmer, flat)
        option Prologue (voice-like, formants)
    positive Fundamental_Hz 82.41
    natural Number_of_partials 24
    positive Duration_s 30
    optionmenu Spectral_envelope: 2
        option Flat (1/n rolloff)
        option Formant (3 peaks)
    real Formant1_Hz 500
    real Formant2_Hz 1500
    real Formant3_Hz 2500
    optionmenu Spectral_consequences: 2
        option Off
        option Difference tones only
        option Difference + sum tones
    optionmenu Macroform: 2
        option Simple (cosine fade)
        option Grisey 5-stage
    optionmenu Temporal_curve: 3
        option Linear
        option Exponential (early change)
        option Logarithmic (late change)
    positive Inharmonicity_factor 0.05
    positive Detuning_strength 1.0
    positive Sample_rate 44100
    boolean Show_visualization 1
endform

# ============================================================
# APPLY PRESETS
# ============================================================

# Default envelope/breathing parameters
breathRate = 0.15
breathDepth = 0.12
fadeInFraction = 0.05
fadeOutFraction = 0.10

if preset = 2
    # PARTIELS (v2.0): E2 trombone, formant emphasis, difference tones
    # The iconic opening of Partiels (1975): a low brass attack reveals
    # its own harmonic content. f0 = E2 (82.41 Hz). The trombone's
    # natural formants emphasize the low-mid partials. Difference
    # tones make the spectral interference audible.
    presetName$ = "Partiels"
    fundamental_Hz = 82.41
    number_of_partials = 18
    duration_s = 30
    inharmonicity_factor = 0.04
    detuning_strength = 1.0
    spectral_envelope = 2
    formant1_Hz = 500
    formant2_Hz = 1200
    formant3_Hz = 2400
    spectral_consequences = 2
    macroform = 2
    temporal_curve = 3
    breathRate = 0.12
    breathDepth = 0.08
    fadeInFraction = 0.03
    fadeOutFraction = 0.12

elsif preset = 3
    # GONDWANA: Deep fundamental, very slow drift, formant character
    presetName$ = "Gondwana"
    fundamental_Hz = 32.7
    number_of_partials = 32
    duration_s = 45
    inharmonicity_factor = 0.08
    detuning_strength = 1.4
    spectral_envelope = 2
    formant1_Hz = 220
    formant2_Hz = 900
    formant3_Hz = 2000
    spectral_consequences = 2
    macroform = 2
    temporal_curve = 3
    breathRate = 0.08
    breathDepth = 0.15
    fadeInFraction = 0.04
    fadeOutFraction = 0.15

elsif preset = 4
    # VORTEX: Fast spectral dissolution, flat envelope, both consequences
    presetName$ = "Vortex"
    fundamental_Hz = 65.41
    number_of_partials = 20
    duration_s = 15
    inharmonicity_factor = 0.20
    detuning_strength = 1.6
    spectral_envelope = 1
    formant1_Hz = 500
    formant2_Hz = 1500
    formant3_Hz = 2500
    spectral_consequences = 3
    macroform = 2
    temporal_curve = 2
    breathRate = 0.25
    breathDepth = 0.08
    fadeInFraction = 0.02
    fadeOutFraction = 0.08

elsif preset = 5
    # MEDITATION: Static shimmer, flat envelope, simple fade
    presetName$ = "Meditation"
    fundamental_Hz = 55.0
    number_of_partials = 16
    duration_s = 60
    inharmonicity_factor = 0.01
    detuning_strength = 0.5
    spectral_envelope = 1
    formant1_Hz = 500
    formant2_Hz = 1500
    formant3_Hz = 2500
    spectral_consequences = 1
    macroform = 1
    temporal_curve = 1
    breathRate = 0.06
    breathDepth = 0.20
    fadeInFraction = 0.08
    fadeOutFraction = 0.08

elsif preset = 6
    # PROLOGUE: Voice-like, vowel-spectrum formants
    presetName$ = "Prologue"
    fundamental_Hz = 110.0
    number_of_partials = 18
    duration_s = 25
    inharmonicity_factor = 0.06
    detuning_strength = 1.1
    spectral_envelope = 2
    formant1_Hz = 700
    formant2_Hz = 1200
    formant3_Hz = 2600
    spectral_consequences = 2
    macroform = 2
    temporal_curve = 1
    breathRate = 0.18
    breathDepth = 0.14
    fadeInFraction = 0.06
    fadeOutFraction = 0.10

else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================
f0 = fundamental_Hz
nPartials = number_of_partials
duration = duration_s
inharm = inharmonicity_factor
detStrength = detuning_strength
curveType = temporal_curve
sr = sample_rate
nyquist = sr / 2

piVal = 3.14159265358979
epsilon = 1e-12

# Spectral brightness evolution (still used as a baseline rolloff
# multiplier even when Formant envelope is active)
alphaStart = 1.0
alphaEnd = 1.0 - inharm * 1.5
if alphaEnd < 0.2
    alphaEnd = 0.2
endif

# Global envelope timing (used by Simple macroform mode)
fadeInDur = duration * fadeInFraction
if fadeInDur < 0.05
    fadeInDur = 0.05
endif
if fadeInDur > 2.0
    fadeInDur = 2.0
endif

fadeOutDur = duration * fadeOutFraction
if fadeOutDur < 0.1
    fadeOutDur = 0.1
endif
if fadeOutDur > 3.0
    fadeOutDur = 3.0
endif

# Names for display
if curveType = 1
    curveName$ = "Linear"
elsif curveType = 2
    curveName$ = "Exponential"
else
    curveName$ = "Logarithmic"
endif

if spectral_envelope = 1
    envelopeName$ = "Flat (1/n)"
else
    envelopeName$ = "Formant (3 peaks)"
endif

if spectral_consequences = 1
    consequencesName$ = "Off"
elsif spectral_consequences = 2
    consequencesName$ = "Difference tones"
else
    consequencesName$ = "Difference + sum tones"
endif

if macroform = 1
    macroformName$ = "Simple cosine fade"
else
    macroformName$ = "Grisey 5-stage"
endif

# Constants for curve phase integrals
expDenom = exp(3) - 1
logDenom = 9 * ln(10)

# Family boundaries
familyLowMax = floor(nPartials / 4)
if familyLowMax < 1
    familyLowMax = 1
endif
familyMidMax = floor(2 * nPartials / 3)
if familyMidMax <= familyLowMax
    familyMidMax = familyLowMax + 1
endif

# 5-stage macroform timing (fractions of total duration)
stage1End = 0.05 * duration   ; end of attack
stage2End = 0.20 * duration   ; end of resonance
stage3End = 0.55 * duration   ; end of magnification
stage4End = 0.80 * duration   ; end of threshold
# stage5End = duration         ; end of extinction

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine: "=== Grisey - Spectral Becoming Engine v2.0 ==="
appendInfoLine: ""
appendInfoLine: "Preset:        ", presetName$
appendInfoLine: "Fundamental:   ", fixed$(f0, 2), " Hz"
appendInfoLine: "Partials:      ", nPartials
appendInfoLine: "Duration:      ", fixed$(duration, 1), " s"
appendInfoLine: "Inharmonicity: ", fixed$(inharm, 3)
appendInfoLine: "Detuning:      x", fixed$(detStrength, 2), " (family-based)"
appendInfoLine: "Envelope:      ", envelopeName$
if spectral_envelope = 2
    appendInfoLine: "  Formants:    ", fixed$(formant1_Hz, 0), " / ",
        ... fixed$(formant2_Hz, 0), " / ", fixed$(formant3_Hz, 0), " Hz"
endif
appendInfoLine: "Macroform:     ", macroformName$
appendInfoLine: "Consequences:  ", consequencesName$
appendInfoLine: "Temporal:      ", curveName$
appendInfoLine: "Brightness:    alpha ", fixed$(alphaStart, 2),
    ... " -> ", fixed$(alphaEnd, 2)
appendInfoLine: "Breathing:     ", fixed$(breathRate, 2),
    ... " Hz, depth ", fixed$(breathDepth, 2)
appendInfoLine: "Sample rate:   ", sr, " Hz"
appendInfoLine: ""

# ============================================================
# STEP 1: Compute partial parameters (with family detuning + envelope)
# ============================================================
appendInfoLine: "[1/5] Computing partial parameters..."

nSynthesized = 0
maxFreqUsed = 0

# Family detuning bases (multiplied by detStrength)
detLowBase  = 0.5 * detStrength    ; perceptual zone: fused beating
detMidBase  = 6.0 * detStrength    ; perceptual zone: audible pulsation
detHighBase = 20.0 * detStrength   ; perceptual zone: timbral / fission

for pn from 1 to nPartials
    # Harmonic frequency (start state)
    fStart = f0 * pn

    # Inharmonic frequency (end state): f0 * n^(1+inharm)
    fEnd = f0 * pn ^ (1 + inharm)

    # === FAMILY-CORRELATED DETUNING ===
    # Three perceptual families. Within each, the base detune is shared,
    # so the family drifts together (correlated instability); per-partial
    # Gaussian jitter is small.
    if pn <= familyLowMax
        family = 1
        baseDet = detLowBase
        jitter = 0.3 * detStrength
        # Random sign for low partials -- minimal effect
        if randomUniform(0, 1) < 0.5
            sgn = -1
        else
            sgn = 1
        endif
    elsif pn <= familyMidMax
        family = 2
        baseDet = detMidBase
        jitter = 1.5 * detStrength
        # Random sign for mid -- bidirectional pulsation
        if randomUniform(0, 1) < 0.5
            sgn = -1
        else
            sgn = 1
        endif
    else
        family = 3
        baseDet = detHighBase + (pn - familyMidMax) * 2 * detStrength
        jitter = 4.0 * detStrength
        # High family ALWAYS detunes upward (spectrum widens)
        sgn = 1
    endif

    detOffset = sgn * (baseDet + randomGauss(0, jitter))
    fEnd = fEnd + detOffset

    # Floor
    if fEnd < 1
        fEnd = 1
    endif

    # Nyquist check
    fMaxPartial = fEnd
    if fStart > fEnd
        fMaxPartial = fStart
    endif

    if fMaxPartial >= nyquist * 0.95
        partialActive_'pn' = 0
        appendInfoLine: "  Partial ", pn, ": SKIPPED (",
            ... fixed$(fMaxPartial, 1), " Hz >= Nyquist)"
    else
        partialActive_'pn' = 1
        nSynthesized = nSynthesized + 1

        # === SPECTRAL ENVELOPE: per-partial amplitude multiplier ===
        # Independent amplitudes, not just 1/n^alpha.
        ampStartBase = 1 / pn ^ alphaStart
        ampEndBase   = 1 / pn ^ alphaEnd

        if spectral_envelope = 1
            # Flat (1/n^alpha) — original v1.0 behavior
            specEnvStart = 1.0
            specEnvEnd = 1.0
        else
            # Formant: three Lorentzian peaks. Each partial's multiplier
            # is the max response across the three formants, capped above
            # a 0.1 floor so nothing fully disappears. Use BW = Fc/4 as a
            # rough Q ~= 4 character; produces voice/instrument-like peaks.
            bw1 = formant1_Hz / 4
            bw2 = formant2_Hz / 4
            bw3 = formant3_Hz / 4
            # Response at fStart
            r1s = bw1 * bw1 / (bw1 * bw1 + (fStart - formant1_Hz) * (fStart - formant1_Hz))
            r2s = bw2 * bw2 / (bw2 * bw2 + (fStart - formant2_Hz) * (fStart - formant2_Hz))
            r3s = bw3 * bw3 / (bw3 * bw3 + (fStart - formant3_Hz) * (fStart - formant3_Hz))
            envS = r1s
            if r2s > envS
                envS = r2s
            endif
            if r3s > envS
                envS = r3s
            endif
            if envS < 0.1
                envS = 0.1
            endif
            specEnvStart = envS
            # Response at fEnd
            r1e = bw1 * bw1 / (bw1 * bw1 + (fEnd - formant1_Hz) * (fEnd - formant1_Hz))
            r2e = bw2 * bw2 / (bw2 * bw2 + (fEnd - formant2_Hz) * (fEnd - formant2_Hz))
            r3e = bw3 * bw3 / (bw3 * bw3 + (fEnd - formant3_Hz) * (fEnd - formant3_Hz))
            envE = r1e
            if r2e > envE
                envE = r2e
            endif
            if r3e > envE
                envE = r3e
            endif
            if envE < 0.1
                envE = 0.1
            endif
            specEnvEnd = envE
        endif

        ampStart = ampStartBase * specEnvStart
        ampEnd   = ampEndBase   * specEnvEnd

        # Random initial phase
        phaseOffset = randomUniform(0, 2 * piVal)

        # Store for synthesis and visualization
        fStart_'pn' = fStart
        fEnd_'pn' = fEnd
        ampStart_'pn' = ampStart
        ampEnd_'pn' = ampEnd
        phaseOff_'pn' = phaseOffset
        family_'pn' = family

        if fEnd > maxFreqUsed
            maxFreqUsed = fEnd
        endif
        if fStart > maxFreqUsed
            maxFreqUsed = fStart
        endif

        if family = 1
            famStr$ = "low"
        elsif family = 2
            famStr$ = "mid"
        else
            famStr$ = "hi "
        endif
        appendInfoLine: "  Partial ", pn, " (", famStr$, "): ",
            ... fixed$(fStart, 1), " -> ", fixed$(fEnd, 1), " Hz",
            ... " | amp: ", fixed$(ampStart, 4), " -> ", fixed$(ampEnd, 4)
    endif
endfor

appendInfoLine: ""
appendInfoLine: "  Synthesizing ", nSynthesized, " / ", nPartials, " primary partials"
appendInfoLine: "  Frequency range: ", fixed$(f0, 1),
    ... " - ", fixed$(maxFreqUsed, 1), " Hz"

# ============================================================
# STEP 1b: Generate spectral consequences (difference + sum tones)
# ============================================================
# These are first-class chirping partials derived from pairs of primary
# partials. Track the primaries' time-varying frequencies, so the
# difference/sum tones also chirp. Limited to pairs within the first
# few partials (limits total count; the strongest psychoacoustic
# difference tones come from low-order primary pairs anyway).

nConsequences = 0
if spectral_consequences > 1
    appendInfoLine: ""
    appendInfoLine: "  Computing spectral consequences..."

    consequencePairLimit = 6
    if consequencePairLimit > nSynthesized
        consequencePairLimit = nSynthesized
    endif
    if consequencePairLimit > nPartials
        consequencePairLimit = nPartials
    endif

    consequenceIdx = 0

    for ii from 1 to consequencePairLimit
        for jj from ii + 1 to consequencePairLimit
            if partialActive_'ii' = 1 and partialActive_'jj' = 1
                # Primary partial frequencies
                fiS = fStart_'ii'
                fiE = fEnd_'ii'
                fjS = fStart_'jj'
                fjE = fEnd_'jj'
                aiS = ampStart_'ii'
                aiE = ampEnd_'ii'
                ajS = ampStart_'jj'
                ajE = ampEnd_'jj'

                # === DIFFERENCE TONE ===
                fdiffS = abs(fjS - fiS)
                fdiffE = abs(fjE - fiE)

                if fdiffS > 20 and fdiffE > 20 and fdiffS < nyquist * 0.9 and fdiffE < nyquist * 0.9
                    consequenceIdx = consequenceIdx + 1
                    nConsequences = nConsequences + 1
                    # Amplitude: psychoacoustic-style, much weaker than primaries
                    aDiffS = 0.15 * sqrt(aiS * ajS)
                    aDiffE = 0.15 * sqrt(aiE * ajE)
                    consFStart_'consequenceIdx' = fdiffS
                    consFEnd_'consequenceIdx' = fdiffE
                    consAmpStart_'consequenceIdx' = aDiffS
                    consAmpEnd_'consequenceIdx' = aDiffE
                    consPhase_'consequenceIdx' = randomUniform(0, 2 * piVal)
                    consType_'consequenceIdx'$ = "D" + string$(ii) + "-" + string$(jj)
                    appendInfoLine: "    Diff(", ii, ",", jj, "): ",
                        ... fixed$(fdiffS, 1), " -> ", fixed$(fdiffE, 1), " Hz"
                endif

                # === SUM TONE ===
                if spectral_consequences = 3
                    fsumS = fjS + fiS
                    fsumE = fjE + fiE

                    if fsumS < nyquist * 0.9 and fsumE < nyquist * 0.9
                        consequenceIdx = consequenceIdx + 1
                        nConsequences = nConsequences + 1
                        aSumS = 0.10 * sqrt(aiS * ajS)
                        aSumE = 0.10 * sqrt(aiE * ajE)
                        consFStart_'consequenceIdx' = fsumS
                        consFEnd_'consequenceIdx' = fsumE
                        consAmpStart_'consequenceIdx' = aSumS
                        consAmpEnd_'consequenceIdx' = aSumE
                        consPhase_'consequenceIdx' = randomUniform(0, 2 * piVal)
                        consType_'consequenceIdx'$ = "S" + string$(ii) + "+" + string$(jj)
                        appendInfoLine: "    Sum(", ii, ",", jj, "):  ",
                            ... fixed$(fsumS, 1), " -> ", fixed$(fsumE, 1), " Hz"
                    endif
                endif
            endif
        endfor
    endfor

    appendInfoLine: "  Generated ", nConsequences, " spectral consequences"
endif
appendInfoLine: ""

# ============================================================
# STEP 2: Additive synthesis (primaries + consequences)
# ============================================================
appendInfoLine: "[2/5] Additive synthesis..."

# Create silent accumulator
Create Sound from formula: "accumulator", 1, 0, duration, sr, "0"
accumulator = selected("Sound")

durStr$ = fixed$(duration, 8)
piStr$ = fixed$(piVal, 14)

# Procedure: synthesize one chirping partial into the accumulator.
# Given fStart, fEnd, ampStart, ampEnd, phase, curveType -> adds to accumulator.
procedure synthChirp: .fS, .fE, .aS, .aE, .ph, .label$
    .fDiff = .fE - .fS
    .aDiff = .aE - .aS

    .fsStr$ = fixed$(.fS, 8)
    .fdStr$ = fixed$(.fDiff, 8)
    .asStr$ = fixed$(.aS, 8)
    .adStr$ = fixed$(.aDiff, 8)
    .phStr$ = fixed$(.ph, 8)

    if curveType = 1
        # Linear
        .ampF$ = "(" + .asStr$ + " + " + .adStr$ + " * x / " + durStr$ + ")"
        .phaseF$ = "2 * " + piStr$ + " * (" + .fsStr$ + " * x + "
            ... + .fdStr$ + " * x * x / (2 * " + durStr$ + ")) + " + .phStr$
    elsif curveType = 2
        # Exponential
        .edStr$ = fixed$(expDenom, 8)
        .ampF$ = "(" + .asStr$ + " + " + .adStr$
            ... + " * (exp(3 * x / " + durStr$ + ") - 1) / " + .edStr$ + ")"
        .phaseF$ = "2 * " + piStr$ + " * (" + .fsStr$ + " * x + "
            ... + .fdStr$ + " / " + .edStr$ + " * (" + durStr$
            ... + " / 3 * (exp(3 * x / " + durStr$ + ") - 1) - x)) + " + .phStr$
    else
        # Logarithmic
        .ldStr$ = fixed$(logDenom, 8)
        .ln10Str$ = fixed$(ln(10), 8)
        .ampF$ = "(" + .asStr$ + " + " + .adStr$
            ... + " * ln(1 + 9 * x / " + durStr$ + ") / " + .ln10Str$ + ")"
        .phaseF$ = "2 * " + piStr$ + " * (" + .fsStr$ + " * x + "
            ... + .fdStr$ + " * " + durStr$ + " / " + .ldStr$
            ... + " * ((1 + 9 * x / " + durStr$ + ") * ln(1 + 9 * x / "
            ... + durStr$ + ") - 9 * x / " + durStr$ + ")) + " + .phStr$
    endif

    .formula$ = .ampF$ + " * sin(" + .phaseF$ + ")"

    Create Sound from formula: "partial_" + .label$, 1, 0, duration, sr, .formula$
    .partial = selected("Sound")
    selectObject: accumulator
    Formula: "self + object[" + string$(.partial) + "]"
    removeObject: .partial
endproc

# Synthesize primary partials
for pn from 1 to nPartials
    if partialActive_'pn' = 1
        @synthChirp: fStart_'pn', fEnd_'pn',
            ... ampStart_'pn', ampEnd_'pn',
            ... phaseOff_'pn', string$(pn)
        pnDiv4 = pn - floor(pn / 4) * 4
        if pnDiv4 = 0 or pn = nPartials
            appendInfoLine: "  Primary ", pn, " / ", nPartials, " done"
        endif
    endif
endfor

# Synthesize consequences (difference + sum tones)
if nConsequences > 0
    appendInfoLine: "  Synthesizing consequences..."
    for cn from 1 to nConsequences
        @synthChirp: consFStart_'cn', consFEnd_'cn',
            ... consAmpStart_'cn', consAmpEnd_'cn',
            ... consPhase_'cn', consType_'cn'$
    endfor
endif

appendInfoLine: "  Synthesis complete."
appendInfoLine: ""

# ============================================================
# STEP 3: Macroform envelope + spectral breathing
# ============================================================
appendInfoLine: "[3/5] Applying macroform and breathing..."

selectObject: accumulator

fadeInStr$ = fixed$(fadeInDur, 8)
fadeOutStart = duration - fadeOutDur
fadeOutStartStr$ = fixed$(fadeOutStart, 8)
fadeOutStr$ = fixed$(fadeOutDur, 8)

if macroform = 1
    # === SIMPLE COSINE FADE (v1.0 mode) ===
    Formula: "self * (if x < " + fadeInStr$
        ... + " then 0.5 - 0.5 * cos(" + piStr$
        ... + " * x / " + fadeInStr$ + ")"
        ... + " else (if x > " + fadeOutStartStr$
        ... + " then 0.5 + 0.5 * cos(" + piStr$
        ... + " * (x - " + fadeOutStartStr$
        ... + ") / " + fadeOutStr$ + ")"
        ... + " else 1 fi) fi)"
    appendInfoLine: "  Macroform: Simple cosine fade"
    appendInfoLine: "    Fade in:  ", fixed$(fadeInDur, 2), " s"
    appendInfoLine: "    Fade out: ", fixed$(fadeOutDur, 2), " s"
else
    # === GRISEY 5-STAGE MACROFORM ===
    # Piecewise linear envelope through 6 control points:
    #   (0,    0.00)  silence
    #   (s1,   1.10)  end of attack (slight overshoot)
    #   (s2,   1.00)  end of resonance
    #   (s3,   1.20)  end of magnification
    #   (s4,   0.40)  end of threshold (perceptual dip)
    #   (dur,  0.00)  end of extinction
    s1$ = fixed$(stage1End, 8)
    s2$ = fixed$(stage2End, 8)
    s3$ = fixed$(stage3End, 8)
    s4$ = fixed$(stage4End, 8)

    # Build nested if/then/else fi inside Formula. Each branch is a
    # linear interpolation between adjacent control points.
    macroF$ = "self * (if x < " + s1$ + " then "
        ... + "(0 + (1.10 - 0) * x / " + s1$ + ")"
        ... + " else (if x < " + s2$ + " then "
        ... + "(1.10 + (1.00 - 1.10) * (x - " + s1$ + ") / (" + s2$ + " - " + s1$ + "))"
        ... + " else (if x < " + s3$ + " then "
        ... + "(1.00 + (1.20 - 1.00) * (x - " + s2$ + ") / (" + s3$ + " - " + s2$ + "))"
        ... + " else (if x < " + s4$ + " then "
        ... + "(1.20 + (0.40 - 1.20) * (x - " + s3$ + ") / (" + s4$ + " - " + s3$ + "))"
        ... + " else (0.40 * (1 - (x - " + s4$ + ") / (" + durStr$ + " - " + s4$ + "))"
        ... + " * (1 - (x - " + s4$ + ") / (" + durStr$ + " - " + s4$ + ")))"
        ... + " fi) fi) fi) fi)"
    Formula: macroF$
    appendInfoLine: "  Macroform: Grisey 5-stage"
    appendInfoLine: "    Attack:        0.000 -> ", fixed$(stage1End, 2), " s"
    appendInfoLine: "    Resonance:     ", fixed$(stage1End, 2), " -> ", fixed$(stage2End, 2), " s"
    appendInfoLine: "    Magnification: ", fixed$(stage2End, 2), " -> ", fixed$(stage3End, 2), " s"
    appendInfoLine: "    Threshold:     ", fixed$(stage3End, 2), " -> ", fixed$(stage4End, 2), " s"
    appendInfoLine: "    Extinction:    ", fixed$(stage4End, 2), " -> ", fixed$(duration, 2), " s"
endif

# Spectral breathing (slow global AM) -- applied AFTER macroform.
brStr$ = fixed$(breathRate, 8)
bdStr$ = fixed$(breathDepth, 8)

selectObject: accumulator
Formula: "self * (1 + " + bdStr$
    ... + " * sin(2 * " + piStr$
    ... + " * " + brStr$ + " * x))"

appendInfoLine: "  Breathing: ", fixed$(breathRate, 2),
    ... " Hz, depth ", fixed$(breathDepth, 2)
appendInfoLine: ""

# ============================================================
# STEP 4: Normalize and finalize
# ============================================================
appendInfoLine: "[4/5] Finalizing..."

selectObject: accumulator
Scale peak: 0.95
# Output filename includes preset suffix
compositeName$ = "Grisey_" + presetName$ + "_" + fixed$(f0, 0) + "Hz_v2"
Rename: compositeName$
finalOutput = selected("Sound")
finalName$ = selected$("Sound")

rms_out = Get root-mean-square: 0, 0
appendInfoLine: "  Output: ", finalName$
appendInfoLine: "  RMS:    ", fixed$(rms_out, 6)
appendInfoLine: ""

# ============================================================
# STEP 5: Visualization
# ============================================================
###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar + metadata subtitle
# Panel A: Spectrogram with partial trajectories  (full width, signature)
# Panel B: Macroform envelope curve              (full width)
# Panel C: Start waveform / End waveform         (side-by-side)
# Panel D: Light-grey 3-line summary
###############################################################################

if show_visualization
    appendInfoLine: "[5/5] Visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # Spectrogram parameters
    specWindow = 0.05
    specMaxFreq = maxFreqUsed * 1.25
    if specMaxFreq > nyquist
        specMaxFreq = nyquist
    endif
    if specMaxFreq < 1000
        specMaxFreq = 1000
    endif

    # Create spectrogram
    selectObject: finalOutput
    To Spectrogram: specWindow, specMaxFreq, 0.002, 20, "Gaussian"
    specGram = selected("Spectrogram")

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##GRISEY SPECTRAL BECOMING ENGINE##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... presetName$
        ... + "  |  f0=" + fixed$(f0, 1) + " Hz"
        ... + "  |  " + string$(nSynthesized) + "+" + string$(nConsequences) + " partials"
        ... + "  |  " + envelopeName$
        ... + "  |  " + macroformName$
        ... + "  |  " + curveName$

    # ----------------------------------------------------------
    # PANEL A: SPECTROGRAM + PARTIAL TRAJECTORIES  (full width, signature)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 4.30
    Select inner viewport: 0.55, 7.72, 0.95, 4.15

    selectObject: specGram
    Paint: 0, 0, 0, specMaxFreq, 100, "yes", 50, 6, 0, "no"

    # Overlay partial trajectories color-coded by family
    Axes: 0, duration, 0, specMaxFreq
    nDrawPts = 40

    for pn from 1 to nPartials
        if partialActive_'pn' = 1
            fS = fStart_'pn'
            fE = fEnd_'pn'
            fD = fE - fS
            fam = family_'pn'

            # Family color: low=warm yellow, mid=green, high=cyan
            if fam = 1
                Colour: "{0.95, 0.85, 0.30}"
            elsif fam = 2
                Colour: "{0.40, 0.80, 0.40}"
            else
                Colour: "{0.20, 0.60, 0.90}"
            endif
            Line width: 1.2

            # Draw trajectory as connected segments
            prevT = 0
            prevF = fS

            for dp from 1 to nDrawPts
                t = dp / nDrawPts * duration
                u = t / duration

                if curveType = 1
                    cu = u
                elsif curveType = 2
                    cu = (exp(3 * u) - 1) / expDenom
                else
                    cu = ln(1 + 9 * u) / ln(10)
                endif

                freq = fS + fD * cu

                if freq <= specMaxFreq and prevF <= specMaxFreq
                    Draw line: prevT, prevF, t, freq
                endif

                prevT = t
                prevF = freq
            endfor
        endif
    endfor

    # Difference/sum tones as DASHED light lines
    if nConsequences > 0
        Colour: "{0.85, 0.50, 0.85}"
        Line width: 0.6
        Dashed line
        for cn from 1 to nConsequences
            fS = consFStart_'cn'
            fE = consFEnd_'cn'
            fD = fE - fS
            prevT = 0
            prevF = fS
            for dp from 1 to nDrawPts
                t = dp / nDrawPts * duration
                u = t / duration
                if curveType = 1
                    cu = u
                elsif curveType = 2
                    cu = (exp(3 * u) - 1) / expDenom
                else
                    cu = ln(1 + 9 * u) / ln(10)
                endif
                freq = fS + fD * cu
                if freq <= specMaxFreq and prevF <= specMaxFreq
                    Draw line: prevT, prevF, t, freq
                endif
                prevT = t
                prevF = freq
            endfor
        endfor
        Solid line
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Spectrogram + partial trajectories  (yellow=low, green=mid, cyan=high, magenta dashed=consequences)"
    Font size: 6
    Text left: "yes", "Hz"

    # ----------------------------------------------------------
    # PANEL B: MACROFORM ENVELOPE  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.40, 5.20
    Select inner viewport: 0.55, 7.72, 4.55, 5.10

    Axes: 0, duration, 0, 1.3
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.3

    if macroform = 2
        # Color-coded stages
        Colour: "{0.95, 0.70, 0.30}"   ; attack: warm
        Paint rectangle: "{0.95, 0.70, 0.30}", 0, stage1End, 0, 0.05
        Colour: "{0.85, 0.85, 0.40}"   ; resonance
        Paint rectangle: "{0.85, 0.85, 0.40}", stage1End, stage2End, 0, 0.05
        Colour: "{0.50, 0.80, 0.50}"   ; magnification
        Paint rectangle: "{0.50, 0.80, 0.50}", stage2End, stage3End, 0, 0.05
        Colour: "{0.40, 0.55, 0.85}"   ; threshold
        Paint rectangle: "{0.40, 0.55, 0.85}", stage3End, stage4End, 0, 0.05
        Colour: "{0.60, 0.40, 0.70}"   ; extinction
        Paint rectangle: "{0.60, 0.40, 0.70}", stage4End, duration, 0, 0.05

        # Stage boundary markers
        Colour: "{0.55, 0.55, 0.60}"
        Line width: 1
        Dotted line
        Draw line: stage1End, 0, stage1End, 1.3
        Draw line: stage2End, 0, stage2End, 1.3
        Draw line: stage3End, 0, stage3End, 1.3
        Draw line: stage4End, 0, stage4End, 1.3
        Solid line

        # Envelope curve (sample points)
        Colour: "{0.20, 0.40, 0.70}"
        Line width: 2
        nEnvPts = 200
        prevT = 0
        prevV = 0
        for ep from 1 to nEnvPts
            t = ep / nEnvPts * duration
            if t < stage1End
                v = (1.10 - 0) * t / stage1End
            elsif t < stage2End
                v = 1.10 + (1.00 - 1.10) * (t - stage1End) / (stage2End - stage1End)
            elsif t < stage3End
                v = 1.00 + (1.20 - 1.00) * (t - stage2End) / (stage3End - stage2End)
            elsif t < stage4End
                v = 1.20 + (0.40 - 1.20) * (t - stage3End) / (stage4End - stage3End)
            else
                quadFrac = 1 - (t - stage4End) / (duration - stage4End)
                v = 0.40 * quadFrac * quadFrac
            endif
            Draw line: prevT, prevV, t, v
            prevT = t
            prevV = v
        endfor

        # Stage labels
        Colour: "Black"
        Font size: 6
        Text: stage1End / 2, "centre", 1.20, "half", "attack"
        Text: (stage1End + stage2End) / 2, "centre", 1.20, "half", "resonance"
        Text: (stage2End + stage3End) / 2, "centre", 1.20, "half", "magnification"
        Text: (stage3End + stage4End) / 2, "centre", 1.20, "half", "threshold"
        Text: (stage4End + duration) / 2, "centre", 1.20, "half", "extinction"
    else
        # Simple fade envelope
        Colour: "{0.20, 0.40, 0.70}"
        Line width: 2
        # Fade in
        Draw line: 0, 0, fadeInDur, 1
        # Steady
        Draw line: fadeInDur, 1, duration - fadeOutDur, 1
        # Fade out
        Draw line: duration - fadeOutDur, 1, duration, 0
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Macroform envelope:  " + macroformName$
    Font size: 6
    Text left: "yes", "Level"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # WAVEFORM ZOOMS (start / end, side-by-side)
    # ----------------------------------------------------------
    zoomDur = 0.5
    if zoomDur > duration * 0.1
        zoomDur = duration * 0.1
    endif
    if zoomDur < 0.05
        zoomDur = 0.05
    endif

    # Pick representative regions (early resonance / late magnification or threshold)
    zoomStartA = stage1End + (stage2End - stage1End) * 0.3
    zoomEndA = zoomStartA + zoomDur
    zoomStartB = stage3End + (stage4End - stage3End) * 0.5
    zoomEndB = zoomStartB + zoomDur
    if zoomEndA > duration
        zoomStartA = duration - zoomDur
        zoomEndA = duration
    endif
    if zoomEndB > duration
        zoomStartB = duration - zoomDur
        zoomEndB = duration
    endif

    selectObject: finalOutput
    aMax = Get maximum: zoomStartA, zoomEndA, "Sinc70"
    aMin = Get minimum: zoomStartA, zoomEndA, "Sinc70"
    bMax = Get maximum: zoomStartB, zoomEndB, "Sinc70"
    bMin = Get minimum: zoomStartB, zoomEndB, "Sinc70"
    zoomAmp = abs(aMax)
    if abs(aMin) > zoomAmp
        zoomAmp = abs(aMin)
    endif
    if abs(bMax) > zoomAmp
        zoomAmp = abs(bMax)
    endif
    if abs(bMin) > zoomAmp
        zoomAmp = abs(bMin)
    endif
    zoomAmp = zoomAmp * 1.1
    if zoomAmp < 0.001
        zoomAmp = 0.001
    endif

    # Start zoom (left)
    Select outer viewport: 0, 4.2, 5.30, 6.10
    Select inner viewport: 0.55, 4.00, 5.42, 6.00

    selectObject: finalOutput
    Colour: "{0.30, 0.55, 0.75}"
    Draw: zoomStartA, zoomEndA, -zoomAmp, zoomAmp, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Resonance zoom  (" + fixed$(zoomStartA, 1) + "-" + fixed$(zoomEndA, 1) + " s)"
    Font size: 6
    Text left: "yes", "Amp"

    # End zoom (right)
    Select outer viewport: 4.2, 8, 5.30, 6.10
    Select inner viewport: 4.55, 7.75, 5.42, 6.00

    selectObject: finalOutput
    Colour: "{0.80, 0.40, 0.30}"
    Draw: zoomStartB, zoomEndB, -zoomAmp, zoomAmp, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Threshold zoom  (" + fixed$(zoomStartB, 1) + "-" + fixed$(zoomEndB, 1) + " s)"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 6.90
    Select inner viewport: 0.55, 7.72, 6.27, 6.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  f0=" + fixed$(f0, 1) + " Hz"
        ... + "  |  " + string$(nSynthesized) + " primaries + " + string$(nConsequences) + " consequences"
        ... + "  |  Range: " + fixed$(f0, 0) + "-" + fixed$(maxFreqUsed, 0) + " Hz"
        ... + "  |  " + curveName$ + " chirp"
        ... + "  |  Inharm: " + fixed$(inharm, 3)

    Text: 0.02, "left", 0.50, "half",
        ... "Envelope: " + envelopeName$
        ... + "  |  Macroform: " + macroformName$
        ... + "  |  Consequences: " + consequencesName$
        ... + "  |  Detune: x" + fixed$(detStrength, 2)
        ... + "  |  Families: low<=" + string$(familyLowMax) + ",  mid<=" + string$(familyMidMax) + ",  high<=" + string$(nPartials)

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + finalName$
        ... + "  |  Duration: " + fixed$(duration, 2) + " s"
        ... + "  |  RMS: " + fixed$(rms_out, 4)
        ... + "  |  SR: " + fixed$(sr / 1000, 1) + " kHz"
        ... + "  |  Breathing: " + fixed$(breathRate, 2) + " Hz, depth " + fixed$(breathDepth, 2)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: specGram

    appendInfoLine: "  Visualization complete."
    appendInfoLine: ""
endif

# ============================================================
# PLAY + SELECT
# ============================================================
selectObject: finalOutput
Play

appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: ""
appendInfoLine: "--- Compositional notes ---"
appendInfoLine: "v2.0 models Grisey's 'spectral becoming' as a living"
appendInfoLine: "spectral organism with six interacting layers:"
appendInfoLine: "  1. Formant-shaped per-partial amplitudes (not uniform 1/n)"
appendInfoLine: "  2. 5-stage macroform: attack -> resonance -> magnification"
appendInfoLine: "     -> threshold -> extinction"
appendInfoLine: "  3. Three perceptual families (low/mid/high) with shared"
appendInfoLine: "     base detuning per family (correlated drift)"
appendInfoLine: "  4. Difference + sum tones as first-class chirping partials"
appendInfoLine: "  5. Family-correlated instability: high partials widen,"
appendInfoLine: "     mid family pulsates, low family anchors"
appendInfoLine: "  6. Threshold stage dips amplitude through the perceptual"
appendInfoLine: "     ambiguity zone before extinction"
appendInfoLine: ""
appendInfoLine: "Suggested uses:"
appendInfoLine: "  - Standalone Grisey-like sound objects"
appendInfoLine: "  - Source material for further spectral processing"
appendInfoLine: "  - Cross-synthesis filter (use as spectral envelope)"
appendInfoLine: "  - Layering with acoustic recordings"

selectObject: finalOutput
