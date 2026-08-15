# ============================================================
# Praat AudioTools - AM Additive Synthesis Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Additive synthesis with multiple spectral configurations
#   and amplitude modulation envelopes.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed ADSR if/fi, smooth gate/stutter, random bursts, presets, spatial, viz
#
# Changelog v0.3:
#   - Fixed preset texture/envelope labels: presets set the numeric texture_type
#     and envelope_type but left texture_type$ / envelope_type$ at the form
#     default, so every preset reported "Harmonic Series / No Envelope" in the
#     info window, plot title, and footer regardless of the actual synthesis.
#     Each preset now sets both strings to match.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced the non-ASCII en-dash.
#
# Changelog v0.4:
#   - Added a Melody_demo mode (ported from the FM Texture Generator): plays a
#     major arpeggio (root-3rd-5th-octave and back) with the selected preset
#     instead of a single sustained tone. Note generation refactored into a
#     makeAMNote procedure; the amplitude envelope is applied per note (so
#     Percussive/ADSR/etc. shape each note rather than the whole sequence).
#
# Changelog v0.5.1:
#   - Rebuilt the oscillator core around a reusable spectral blueprint so random
#     textures retain the same instrument identity throughout Melody_demo.
#   - Corrected Rising Partials / Shepard-like glide phase laws so the requested
#     instantaneous-frequency trajectory does not grow spuriously with time.
#   - Replaced the old time-growing "Chaotic Swarm" formula with bounded
#     sinusoidal phase modulation and renamed it Modulated Swarm.
#   - Added Nyquist-aware partial skipping / sweep-depth reduction, spectral
#     energy normalization, reproducible Random_seed, and safe RNG restoration.
#   - Fixed ADSR overlap on short melody notes, click-prone Smooth Gate, and
#     pseudo-stutter / random-burst envelopes.
#   - Replaced spectral-split "Stereo Wide" with a short decorrelation delay and
#     made Rotating stereo equal-power.
#   - Visualization now uses actual output duration, measured waveform and
#     spectrogram, the realized root-note spectral blueprint, model overlays,
#     QC metrics, and the AudioTools title/data/summary viewport layout.
# ============================================================

form AM Additive Synthesis Generator
    comment === Demo Mode ===
    boolean Melody_demo 0
    comment (If checked, plays a major arpeggio with the selected preset)
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Warm Pad
        option Bright Organ
        option Bell Tone
        option Shimmer
        option Bass Drone
        option Ethereal Choir
        option Plucked String
        option Sci-Fi Sweep
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    positive Fundamental_Hz 220
    integer Num_partials 8
    
    comment === Texture Type ===
    optionmenu Texture_type 1
        option Harmonic Series
        option Odd Harmonics
        option Even Harmonics
        option Inharmonic Cluster
        option Golden Bells
        option Octave Stack
        option Fifth Stack
        option Shepard-like Glide
        option Spectral Comb
        option Random Cloud
        option Detuned Unison
        option Harmonic Decay
        option Rising Partials
        option Filtered Spectrum
        option Modulated Swarm
    
    comment === Modulation ===
    real Detune 0.1
    real Chaos 0.3
    integer Random_seed 0
    
    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Fade
        option Smooth Gate
        option Reverse
        option Tremolo
        option Swell
        option ADSR
        option Smooth Stutter
        option Random Bursts
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Warm Pad
    duration_s = 5
    fundamental_Hz = 110
    num_partials = 6
    texture_type = 1
    detune = 0.05
    chaos = 0.1
    envelope_type = 7
    spatial_mode = 2
    texture_type$ = "Harmonic Series"
    envelope_type$ = "Swell"
    preset_name$ = "WarmPad"
elsif preset = 3
    # Bright Organ
    duration_s = 3
    fundamental_Hz = 220
    num_partials = 10
    texture_type = 2
    detune = 0.02
    chaos = 0.05
    envelope_type = 1
    spatial_mode = 2
    texture_type$ = "Odd Harmonics"
    envelope_type$ = "No Envelope"
    preset_name$ = "BrightOrgan"
elsif preset = 4
    # Bell Tone
    duration_s = 4
    fundamental_Hz = 440
    num_partials = 8
    texture_type = 5
    detune = 0.08
    chaos = 0.2
    envelope_type = 2
    spatial_mode = 3
    texture_type$ = "Golden Bells"
    envelope_type$ = "Percussive"
    preset_name$ = "BellTone"
elsif preset = 5
    # Shimmer
    duration_s = 5
    fundamental_Hz = 330
    num_partials = 12
    texture_type = 11
    detune = 0.15
    chaos = 0.3
    envelope_type = 6
    spatial_mode = 3
    texture_type$ = "Detuned Unison"
    envelope_type$ = "Tremolo"
    preset_name$ = "Shimmer"
elsif preset = 6
    # Bass Drone
    duration_s = 8
    fundamental_Hz = 55
    num_partials = 6
    texture_type = 1
    detune = 0.03
    chaos = 0.1
    envelope_type = 3
    spatial_mode = 2
    texture_type$ = "Harmonic Series"
    envelope_type$ = "Slow Fade"
    preset_name$ = "BassDrone"
elsif preset = 7
    # Ethereal Choir
    duration_s = 6
    fundamental_Hz = 180
    num_partials = 8
    texture_type = 14
    detune = 0.1
    chaos = 0.4
    envelope_type = 7
    spatial_mode = 3
    texture_type$ = "Filtered Spectrum"
    envelope_type$ = "Swell"
    preset_name$ = "EtherealChoir"
elsif preset = 8
    # Plucked String
    duration_s = 2
    fundamental_Hz = 196
    num_partials = 10
    texture_type = 12
    detune = 0.02
    chaos = 0.15
    envelope_type = 2
    spatial_mode = 1
    texture_type$ = "Harmonic Decay"
    envelope_type$ = "Percussive"
    preset_name$ = "PluckedString"
elsif preset = 9
    # Sci-Fi Sweep
    duration_s = 4
    fundamental_Hz = 150
    num_partials = 10
    texture_type = 13
    detune = 0.1
    chaos = 0.5
    envelope_type = 5
    spatial_mode = 3
    texture_type$ = "Rising Partials"
    envelope_type$ = "Reverse"
    preset_name$ = "SciFiSweep"
endif


# === Validation ===
if num_partials > 32
    num_partials = 32
endif
if num_partials < 1
    num_partials = 1
endif
if sample_rate_Hz < 1000
    exitScript: "Sample rate must be at least 1000 Hz."
endif
if duration_s < 0.05
    duration_s = 0.05
endif
if detune < 0
    detune = 0
endif
if detune > 1
    detune = 1
endif
if chaos < 0
    chaos = 0
endif
if chaos > 1
    chaos = 1
endif
if random_seed < 0
    random_seed = 0
endif

# === Constants / reproducibility ===
twoPi = 2 * pi
phi = (1 + sqrt(5)) / 2
safeNyquist = 0.45 * sample_rate_Hz

if fundamental_Hz >= safeNyquist
    exitScript: "Fundamental must be below 45 percent of the sample rate."
endif

# Keep object naming independent of the research seed.
random_initializeSafelyAndUnpredictably ()
uid$ = string$(randomInteger(10000, 99999))

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
endif

# === Build ONE spectral blueprint ===
# Random spectral configurations are drawn once and reused by every melody note.
# This preserves instrument identity across the arpeggio.
blueprintMaxAmp = 0
ratioCorrections = 0

for partial to num_partials
    if texture_type = 1
        spectralRatio[partial] = partial
        spectralAmp[partial] = 1 / partial

    elsif texture_type = 2
        harmonic = 2 * partial - 1
        spectralRatio[partial] = harmonic
        spectralAmp[partial] = 1 / harmonic

    elsif texture_type = 3
        harmonic = 2 * partial
        spectralRatio[partial] = harmonic
        spectralAmp[partial] = 1 / harmonic

    elsif texture_type = 4
        spectralRatio[partial] = partial + chaos * randomGauss(0, 0.5)
        if spectralRatio[partial] < 0.1
            spectralRatio[partial] = 0.1
            ratioCorrections += 1
        endif
        spectralAmp[partial] = 1 / partial

    elsif texture_type = 5
        spectralRatio[partial] = phi ^ (partial - 1)
        spectralAmp[partial] = 1 / (2 ^ (partial - 1))

    elsif texture_type = 6
        spectralRatio[partial] = 2 ^ (partial - 1)
        spectralAmp[partial] = 1 / (2 ^ (partial - 1))

    elsif texture_type = 7
        spectralRatio[partial] = 1.5 ^ (partial - 1)
        spectralAmp[partial] = 1 / (1.5 ^ (partial - 1))

    elsif texture_type = 8
        # Shepard-like octave stack with a Gaussian spectral envelope.
        spectralRatio[partial] = 2 ^ (partial - 1)
        shepardCentre = (num_partials + 1) / 2
        shepardSpread = max(1, num_partials / 4)
        spectralAmp[partial] = exp(-0.5 * ((partial - shepardCentre) / shepardSpread) ^ 2)

    elsif texture_type = 9
        spacing = 2 + chaos * 3
        spectralRatio[partial] = 1 + spacing * (partial - 1)
        spectralAmp[partial] = 1 / (1 + partial * 0.2)

    elsif texture_type = 10
        spectralRatio[partial] = randomUniform(0.5, 4)
        spectralAmp[partial] = randomUniform(0.3, 1) / num_partials

    elsif texture_type = 11
        centred = (partial - (num_partials + 1) / 2) / max(1, num_partials - 1)
        spectralRatio[partial] = 1 + detune * centred
        spectralAmp[partial] = 1 / num_partials

    elsif texture_type = 12
        spectralRatio[partial] = partial
        spectralAmp[partial] = 1 / partial

    elsif texture_type = 13
        spectralRatio[partial] = partial
        spectralAmp[partial] = 1 / partial

    elsif texture_type = 14
        centre = (num_partials + 1) / 2
        spectralRatio[partial] = partial
        spectralAmp[partial] = (1 / partial) * exp(-((partial - centre) ^ 2) / (2 * (chaos * 5 + 1) ^ 2))

    else
        # Modulated Swarm: harmonic centres with stochastic spectral weights.
        spectralRatio[partial] = partial
        spectralAmp[partial] = 1 / (partial + abs(chaos * randomGauss(0, 2)))
    endif

    if spectralAmp[partial] > blueprintMaxAmp
        blueprintMaxAmp = spectralAmp[partial]
    endif
endfor

# === Global QC counters ===
totalComponents = 0
skippedComponents = 0
aaAdjustments = 0
realizedMinFreq = safeNyquist
realizedMaxFreq = 0
noteCounter = 0
visMaxAmp = 0

# === Info ===
writeInfoLine: "=== AM Additive Synthesis Generator ==="
appendInfoLine: "Preset: ", preset_name$
if melody_demo
    appendInfoLine: "Mode: melody demo (major arpeggio)"
else
    appendInfoLine: "Mode: single note"
    appendInfoLine: "Requested duration: ", duration_s, " s"
endif
appendInfoLine: "Fundamental: ", fundamental_Hz, " Hz"
appendInfoLine: "Partials requested: ", num_partials
appendInfoLine: "Texture: ", texture_type$
appendInfoLine: "Envelope: ", envelope_type$
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed
else
    appendInfoLine: "Random seed: unpredictable"
endif
appendInfoLine: ""

# === Generate: single note or melody arpeggio ===
if melody_demo
    appendInfoLine: "Generating melody demo (major arpeggio)..."
    nNotes = 8
    noteRatio[1] = 1.0
    noteRatio[2] = 1.25
    noteRatio[3] = 1.5
    noteRatio[4] = 2.0
    noteRatio[5] = 1.5
    noteRatio[6] = 1.25
    noteRatio[7] = 1.0
    noteRatio[8] = 0.5

    noteDur[1] = 0.4
    noteDur[2] = 0.4
    noteDur[3] = 0.4
    noteDur[4] = 0.6
    noteDur[5] = 0.4
    noteDur[6] = 0.4
    noteDur[7] = 0.4
    noteDur[8] = 0.8

    runningTime = 0
    for n to nNotes
        noteStart[n] = runningTime
        @makeAMNote: fundamental_Hz * noteRatio[n], noteDur[n]
        noteId[n] = selected("Sound")
        runningTime += noteDur[n]
        noteEnd[n] = runningTime
    endfor

    selectObject: noteId[1]
    for n from 2 to nNotes
        plusObject: noteId[n]
    endfor
    Concatenate
    outputSound = selected("Sound")

    for n to nNotes
        removeObject: noteId[n]
    endfor
else
    nNotes = 1
    noteRatio[1] = 1
    noteDur[1] = duration_s
    noteStart[1] = 0
    noteEnd[1] = duration_s
    @makeAMNote: fundamental_Hz, duration_s
    outputSound = selected("Sound")
endif

# Restore the global RNG as soon as synthesis randomness is finished.
random_initializeSafelyAndUnpredictably ()

if totalComponents = 0
    removeObject: outputSound
    exitScript: "No partials remained below the anti-alias limit. Lower the fundamental or raise the sample rate."
endif

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width by short decorrelation delay..."

    wideDelay = 0.007

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "object(outputSound, x - wideDelay, 1)"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "additive_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating equal-power rotating stereo..."

    rotateHz = 0.2

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * sqrt(0.5 - 0.5 * sin(twoPi * rotateHz * x))"

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sqrt(0.5 + 0.5 * sin(twoPi * rotateHz * x))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "additive_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "additive_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.95
endif

# === Measured output QC ===
selectObject: outputSound
outputDuration = Get total duration
outputPeak = Get absolute extremum: 0, 0, "none"
outputRms = Get root-mean-square: 0, 0
outputChannels = Get number of channels

appendInfoLine: "Output duration: ", fixed$(outputDuration, 3), " s"
appendInfoLine: "Rendered components: ", totalComponents
appendInfoLine: "Skipped above anti-alias limit: ", skippedComponents
appendInfoLine: "Sweep/FM anti-alias reductions: ", aaAdjustments
appendInfoLine: "Realized frequency range: ", fixed$(realizedMinFreq, 1), " - ", fixed$(realizedMaxFreq, 1), " Hz"
appendInfoLine: "Peak: ", fixed$(outputPeak, 4), " | RMS: ", fixed$(outputRms, 4)

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSynthesisQC: outputDuration
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")


# ==============================================================================
# Procedure: makeAMNote - build one additive note at .freq over .dur
# ==============================================================================
procedure makeAMNote: .freq, .dur

    noteCounter += 1
    .note = Create Sound from formula: "amnote_" + uid$, 1, 0, .dur, sample_rate_Hz, "0"
    .energySum = 0
    .renderedThisNote = 0

    for partial to num_partials
        .baseFreq = .freq * spectralRatio[partial]
        .amp = spectralAmp[partial]
        .render = 1
        .minFreq = .baseFreq
        .maxFreq = .baseFreq
        .endFreq = .baseFreq
        # Initialize branch-specific locals on every partial. Praat conditions
        # should not rely on short-circuit evaluation of an undefined local.
        .octavesTotal = 0

        if .baseFreq < 20 or .baseFreq >= safeNyquist
            .render = 0
        endif

        if .render = 1 and texture_type = 8
            # Shepard-like octave glide: exponential pitch trajectory.
            .octavesTotal = 0.25 + 0.75 * chaos
            .desiredEnd = .baseFreq * (2 ^ .octavesTotal)
            if .desiredEnd > safeNyquist
                .octavesTotal = ln(safeNyquist / .baseFreq) / ln(2)
                aaAdjustments += 1
            endif
            if .octavesTotal < 0
                .octavesTotal = 0
            endif
            .endFreq = .baseFreq * (2 ^ .octavesTotal)
            .maxFreq = .endFreq

        elsif .render = 1 and texture_type = 13
            # Linear rising partials. Correct phase has one-half in the chirp term.
            .riseRate = chaos * 0.5
            .allowedRise = (safeNyquist / .baseFreq - 1) / .dur
            if .riseRate > .allowedRise
                .riseRate = max(0, .allowedRise)
                aaAdjustments += 1
            endif
            .endFreq = .baseFreq * (1 + .riseRate * .dur)
            .maxFreq = .endFreq

        elsif .render = 1 and texture_type = 15
            # Bounded sinusoidal FM expressed as phase modulation.  Reserve
            # roughly one modulator-frequency of spectral headroom (Carson-like
            # practical guard) rather than checking carrier deviation alone.
            .desiredFmHz = partial * 10
            .fmHz = min(.desiredFmHz, max(1, 0.25 * (safeNyquist - .baseFreq)))
            if .fmHz < .desiredFmHz
                aaAdjustments += 1
            endif
            .desiredDev = chaos * .baseFreq
            .maxDev = min(0.8 * .baseFreq, max(0, safeNyquist - .baseFreq - .fmHz))
            .devHz = min(.desiredDev, .maxDev)
            if .devHz < .desiredDev
                aaAdjustments += 1
            endif
            .beta = .devHz / .fmHz
            if .devHz > 0
                .minFreq = max(0, .baseFreq - .devHz - .fmHz)
                .maxFreq = .baseFreq + .devHz + .fmHz
            endif
        endif

        if .render = 1
            selectObject: .note

            if texture_type = 8
                if .octavesTotal > 0
                    .octRate = .octavesTotal / .dur
                    .phaseDenom = .octRate * ln(2)
                    Formula: "self + .amp * sin(twoPi * .baseFreq * ((2 ^ (.octRate * x)) - 1) / .phaseDenom)"
                else
                    Formula: "self + .amp * sin(twoPi * .baseFreq * x)"
                endif
            elsif texture_type = 12
                .decayRate = partial * 0.5
                Formula: "self + .amp * sin(twoPi * .baseFreq * x) * exp(-x * .decayRate)"
            elsif texture_type = 13
                Formula: "self + .amp * sin(twoPi * .baseFreq * (x + 0.5 * .riseRate * x ^ 2))"
            elsif texture_type = 15
                Formula: "self + .amp * sin(twoPi * .baseFreq * x + .beta * sin(twoPi * .fmHz * x))"
            else
                Formula: "self + .amp * sin(twoPi * .baseFreq * x)"
            endif

            .energySum += .amp ^ 2
            .renderedThisNote += 1
            totalComponents += 1

            if .minFreq < realizedMinFreq
                realizedMinFreq = .minFreq
            endif
            if .maxFreq > realizedMaxFreq
                realizedMaxFreq = .maxFreq
            endif

            if partial = 1
                noteFundStart[noteCounter] = .baseFreq
                noteFundEnd[noteCounter] = .endFreq
            endif

            if noteCounter = 1
                visRendered[partial] = 1
                visStartFreq[partial] = .baseFreq
                visEndFreq[partial] = .endFreq
                visMinFreq[partial] = .minFreq
                visMaxFreq[partial] = .maxFreq
                visAmp[partial] = .amp
                if .amp > visMaxAmp
                    visMaxAmp = .amp
                endif
            endif
        else
            skippedComponents += 1
            if partial = 1
                noteFundStart[noteCounter] = 0
                noteFundEnd[noteCounter] = 0
            endif
            if noteCounter = 1
                visRendered[partial] = 0
            endif
        endif
    endfor

    if .renderedThisNote > 0 and .energySum > 0
        # Equalize expected additive energy without changing the spectral shape.
        .spectralGain = 1 / sqrt(.energySum)
        selectObject: .note
        Formula: "self * .spectralGain"
    endif

    # === Apply amplitude envelope ===
    selectObject: .note

    if envelope_type = 2
        # Percussive
        Formula: "self * exp(-x * 5)"

    elsif envelope_type = 3
        # Slow Fade
        Formula: "self * exp(-x * 0.3)"

    elsif envelope_type = 4
        # Smooth Gate: zero-valued half-cycle with raised-sine on/off edges.
        .gatePeriod = 0.1 + chaos * 0.3
        Formula: "if (x / .gatePeriod - floor(x / .gatePeriod)) < 0.5 then self * sin(twoPi * (x / .gatePeriod - floor(x / .gatePeriod))) ^ 2 else 0 fi"

    elsif envelope_type = 5
        # Reverse (fade in)
        Formula: "self * (x / .dur)"

    elsif envelope_type = 6
        # Tremolo
        .tremRate = 5 + chaos * 15
        .tremDepth = 0.3 + chaos * 0.5
        Formula: "self * (1 - .tremDepth + .tremDepth * (0.5 + 0.5 * sin(twoPi * .tremRate * x)))"

    elsif envelope_type = 7
        # Swell; cap attack so short melody notes still reach sustain.
        .attackTime = min(0.3 + chaos * 0.5, 0.7 * .dur)
        Formula: "self * min(1, x / .attackTime)"

    elsif envelope_type = 8
        # ADSR in ONE envelope expression. Segment lengths are scaled when a
        # short melody note cannot fit the nominal attack+decay+release.
        .attack = min(0.01, 0.15 * .dur)
        .decay = min(0.1 + chaos * 0.2, 0.3 * .dur)
        .release = min(0.3, 0.3 * .dur)
        .sumSegments = .attack + .decay + .release
        if .sumSegments > 0.9 * .dur
            .segScale = 0.9 * .dur / .sumSegments
            .attack *= .segScale
            .decay *= .segScale
            .release *= .segScale
        endif
        .sustain = 0.5 + chaos * 0.3
        .decayEnd = .attack + .decay
        .releaseStart = .dur - .release
        Formula: "if x < .attack then self * (x / .attack) else if x < .decayEnd then self * (1 - (1 - .sustain) * ((x - .attack) / .decay)) else if x < .releaseStart then self * .sustain else self * .sustain * max(0, 1 - (x - .releaseStart) / .release) fi fi fi"

    elsif envelope_type = 9
        # Smooth Stutter: 60 percent duty cycle with zero-valued, clickless gaps.
        .stutterRate = 10 + chaos * 30
        Formula: "if (x * .stutterRate - floor(x * .stutterRate)) < 0.6 then self * sin(pi * (x * .stutterRate - floor(x * .stutterRate)) / 0.6) ^ 2 else 0 fi"

    elsif envelope_type = 10
        # Random Bursts: smooth Gaussian AM events on a control envelope.
        .burstDensity = 5 + chaos * 20
        .burstSigma = 0.012 + 0.018 * (1 - chaos)
        .burstControlRate = min(1000, max(200, sample_rate_Hz / 20))
        .burstEnv = Create Sound from formula: "burst_" + uid$, 1, 0, .dur, .burstControlRate, "0"
        .numBursts = max(1, floor(.dur * .burstDensity))

        for b to .numBursts
            .burstTime = randomUniform(0, .dur)
            selectObject: .burstEnv
            Formula: "self + exp(-0.5 * ((x - .burstTime) / .burstSigma) ^ 2)"
        endfor

        selectObject: .burstEnv
        .burstPeak = Get absolute extremum: 0, 0, "none"
        if .burstPeak > 0
            Formula: "self / .burstPeak"
        endif
        .burstEnvAudio = Resample: sample_rate_Hz, 50

        selectObject: .note
        Formula: "self * object(.burstEnvAudio, x, 1)"

        removeObject: .burstEnv, .burstEnvAudio
    endif

    # === Short safety fade ===
    .fadeTime = min(0.01, 0.2 * .dur)
    selectObject: .note
    Formula: "if x < .fadeTime then self * (x / .fadeTime) else self fi"
    Formula: "if x > .dur - .fadeTime then self * max(0, (.dur - x) / .fadeTime) else self fi"

    .sound = selected("Sound")
endproc


# ==============================================================================
# Procedure: drawSynthesisQC
# ==============================================================================
procedure drawSynthesisQC: .duration

    .blue$ = "{0.15, 0.42, 0.68}"
    .rust$ = "{0.68, 0.34, 0.22}"
    .grey$ = "{0.42, 0.42, 0.46}"
    .light$ = "{0.965, 0.965, 0.972}"

    # Choose a representative channel without phase-cancelling fold-down.
    selectObject: outputSound
    .channels = Get number of channels
    if .channels > 1
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0, 0

        if .rightRms > .leftRms
            .disp = .rightDisp
            removeObject: .leftDisp
            .dispLabel$ = "R"
        else
            .disp = .leftDisp
            removeObject: .rightDisp
            .dispLabel$ = "L"
        endif
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
        .dispLabel$ = "mono"
    endif

    selectObject: .disp
    .dispPeak = Get absolute extremum: 0, 0, "none"
    .waveY = max(0.001, 1.08 * .dispPeak)

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line
    Line width: 1

    # ---- Header ----
    Select inner viewport: 0.35, 7.65, 0.10, 0.52
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "AM Additive Synthesis - mechanism and QC"

    Select inner viewport: 0.35, 7.65, 0.53, 0.86
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: .grey$
    .mode$ = "single"
    if melody_demo
        .mode$ = "melody"
    endif
    Text: 0.5, "centre", 0.55, "half", "Preset " + preset_name$ + "  |  " + texture_type$ + "  |  " + envelope_type$ + "  |  " + .mode$

    # ---- Panel A title ----
    Select inner viewport: 0.72, 7.60, 0.95, 1.14
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "A. Measured output waveform | channel " + .dispLabel$

    # ---- Panel A data ----
    Select inner viewport: 0.78, 7.58, 1.17, 2.35
    selectObject: .disp
    Colour: .blue$
    Draw: 0, .duration, -.waveY, .waveY, "no", "Curve"
    Select inner viewport: 0.78, 7.58, 1.17, 2.35
    Axes: 0, .duration, -.waveY, .waveY
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"

    # ---- Panel B title ----
    Select inner viewport: 0.72, 7.60, 2.62, 2.81
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "B. Realized root-note spectral blueprint | log frequency"

    # ---- Panel B data ----
    .plotMinHz = max(20, min(fundamental_Hz * 0.4, realizedMinFreq))
    .plotMaxHz = min(safeNyquist, max(fundamental_Hz * 2, realizedMaxFreq))
    if .plotMaxHz <= .plotMinHz
        .plotMaxHz = min(safeNyquist, .plotMinHz * 2)
    endif
    .logMin = ln(.plotMinHz) / ln(10)
    .logMax = ln(.plotMaxHz) / ln(10)

    Select inner viewport: 0.78, 7.58, 2.84, 4.08
    Axes: .logMin, .logMax, 0, 1.08
    Colour: .light$
    Paint rectangle: .light$, .logMin, .logMax, 0, 1.08
    Colour: "Black"
    Draw inner box
    Font size: 7
    One mark left: 0, "yes", "yes", "no", "0"
    One mark left: 0.5, "yes", "yes", "no", "0.5"
    One mark left: 1, "yes", "yes", "no", "1"

    if 50 >= .plotMinHz and 50 <= .plotMaxHz
        One mark bottom: ln(50) / ln(10), "no", "yes", "no", "50"
    endif
    if 100 >= .plotMinHz and 100 <= .plotMaxHz
        One mark bottom: ln(100) / ln(10), "no", "yes", "no", "100"
    endif
    if 200 >= .plotMinHz and 200 <= .plotMaxHz
        One mark bottom: ln(200) / ln(10), "no", "yes", "no", "200"
    endif
    if 500 >= .plotMinHz and 500 <= .plotMaxHz
        One mark bottom: ln(500) / ln(10), "no", "yes", "no", "500"
    endif
    if 1000 >= .plotMinHz and 1000 <= .plotMaxHz
        One mark bottom: ln(1000) / ln(10), "no", "yes", "no", "1k"
    endif
    if 2000 >= .plotMinHz and 2000 <= .plotMaxHz
        One mark bottom: ln(2000) / ln(10), "no", "yes", "no", "2k"
    endif
    if 5000 >= .plotMinHz and 5000 <= .plotMaxHz
        One mark bottom: ln(5000) / ln(10), "no", "yes", "no", "5k"
    endif
    if 10000 >= .plotMinHz and 10000 <= .plotMaxHz
        One mark bottom: ln(10000) / ln(10), "no", "yes", "no", "10k"
    endif

    if visMaxAmp <= 0
        visMaxAmp = 1
    endif
    for partial to num_partials
        if visRendered[partial] = 1
            .normAmp = visAmp[partial] / visMaxAmp
            .xStem = ln(max(.plotMinHz, visStartFreq[partial])) / ln(10)
            .spanLoHz = max(.plotMinHz, visMinFreq[partial])
            .spanHiHz = min(.plotMaxHz, visMaxFreq[partial])
            .xSpanLo = ln(.spanLoHz) / ln(10)
            .xSpanHi = ln(.spanHiHz) / ln(10)
            if visStartFreq[partial] >= .plotMinHz and visStartFreq[partial] <= .plotMaxHz
                Colour: .blue$
                Line width: 1.5
                Draw line: .xStem, 0, .xStem, .normAmp
                if .spanHiHz > .spanLoHz * 1.005
                    Colour: .rust$
                    Line width: 1
                    Draw line: .xSpanLo, .normAmp, .xSpanHi, .normAmp
                endif
            endif
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Font size: 8
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Relative weight"

    # ---- Panel C title ----
    Select inner viewport: 0.72, 7.60, 4.36, 4.55
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0, "left", 0.5, "half", "C. Measured spectrogram + first-component model guide"

    # ---- Panel C measured spectrogram ----
    .maxFreqSpec = min(safeNyquist, max(500, min(8000, realizedMaxFreq * 1.15)))
    selectObject: .disp
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: 0.78, 7.58, 4.58, 6.28
    selectObject: .spec
    Paint: 0, .duration, 0, .maxFreqSpec, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    Select inner viewport: 0.78, 7.58, 4.58, 6.28
    Axes: 0, .duration, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # Model overlay: one guide per note, based on the first rendered component.
    Colour: .rust$
    Line width: 1.5
    for n to nNotes
        if noteFundStart[n] > 0
            Draw line: noteStart[n], noteFundStart[n], noteEnd[n], noteFundEnd[n]
        endif
    endfor
    Line width: 1

    # ---- Bottom mechanism / QC dashboard ----
    Select inner viewport: 0.45, 7.55, 6.58, 7.82
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.945, 0.945, 0.952}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.78, "half", "SPECTRAL BLUEPRINT  ->  sum of oscillators  ->  AM envelope  ->  spatial render"
    Font size: 7
    Colour: .grey$
    Text: 0.5, "centre", 0.56, "half", "y(t) = E(t) * sum a(k) sin(phi(k,t))"

    .seed$ = "new"
    if random_seed > 0
        .seed$ = string$(random_seed)
    endif
    .range$ = fixed$(realizedMinFreq, 0) + "-" + fixed$(realizedMaxFreq, 0) + " Hz"
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.31, "half", "Range " + .range$ + "  |  rendered " + string$(totalComponents) + "  |  skipped " + string$(skippedComponents) + "  |  AA reductions " + string$(aaAdjustments)
    Text: 0.5, "centre", 0.12, "half", "Peak " + fixed$(outputPeak, 3) + "  |  RMS " + fixed$(outputRms, 3) + "  |  duration " + fixed$(.duration, 2) + " s  |  seed " + .seed$

    removeObject: .disp
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
