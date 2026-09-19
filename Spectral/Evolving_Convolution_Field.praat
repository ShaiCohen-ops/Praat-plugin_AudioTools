# ============================================================
# Praat AudioTools - Evolving Convolution Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Select ONE Sound and run the script. A synthetic artistic IR is generated
#   as a FAMILY OF MUTATING GENERATIONS rather than as a room response.
#   Each generation is delayed, shaped, spectrally mutated and spatially
#   displaced. Convolution therefore creates an event-relative temporal field:
#   attacks and gestures bloom into successive transformed descendants.
#
#   This is intentionally not a room/reverb model. Delayed IR generations are
#   compositional objects. Their spacing, survival, mutation and stereo
#   trajectories are designed to enrich and destabilize the source material.
#
# Changelog v0.7:
#   - STEREO MATERIAL MEMORY: left and right now recall related but non-identical
#     descendants. Each side receives its own source-position offset, micro-delay,
#     varispeed deviation, fragment duration, gain perturbation and occasional
#     side-specific reversal. The two channels still share the same generation
#     and source-memory stream, so the result remains one family of material
#     rather than two unrelated granular clouds.
#   - New Advanced control: Memory stereo divergence (0..1). At 0 the v0.6
#     memory behavior is recovered; spatial width still places the shared shard.
#     At higher values the two sides increasingly disagree in time and material.
#
# Changelog v0.6:
#   - MATERIAL MEMORY layer (main form, 0..1, 0 = off = v0.5.1). After the
#     adaptive contour, surviving IR generations spawn short, recognisable
#     source fragments into the wet field. The fragments inherit the existing
#     generation plan: delay, survival, pan, reversal, frequency tendency and
#     mutation. Later generations become shorter and more unstable, so source
#     gestures progressively erode from memory into shards rather than another
#     reverberant wash.
#   - Fragment anchors are source-aware: each memory stream searches several
#     candidates in its own source-time zone and keeps the locally strongest
#     RMS gesture. Every surviving generation then recalls that same gesture,
#     creating a true temporal descendant trail without a fixed onset detector.
#   - Varispeed and reverse are applied directly to source fragments; the
#     memory branch deliberately bypasses the adaptive contour and is not
#     reconvolved, preserving recognisable temporal identity against the more
#     abstract convolution field.
#   - Character presets now define fragment duration, density, erosion, pitch
#     mutation, reverse probability, delay scaling and temporal jitter. The
#     Advanced dialog can override these parameters.
#   - Visualization/reporting include Material Memory amount and realised
#     fragment count.
#
# Changelog v0.5.1:
#   - Adaptive contour: the source memory H now keeps decaying during source
#     pauses. In v0.5 it froze, so the harmony before a pause was still
#     "remembered" when the source came back. Negligible at the default
#     250 ms memory (<= 0.4 dB, measured C major -> 1.5 s pause -> F# major);
#     with a 3 s memory, v0.5 left the old C tail untouched for the first
#     200 ms after the pause, v0.5.1 takes 3 dB off it.
#
# Changelog v0.5:
#   - ADAPTIVE CONTOUR layer (main form, -1..1, 0 = off = v0.4). The wet field
#     is analysed frame by frame against the dry source (pure-Praat STFT,
#     ~170 ms frames, Hann for analysis, sine for resynthesis, 50% overlap)
#     and masked by harmonic similarity:
#       > 0 keeps wet components the source currently shares and fades the
#           ones it has left behind, so the field follows the harmony;
#       < 0 does the opposite: the wet keeps only what the source lacks and
#           fills the spectral holes around it.
#     Pitch-class mode compares octave-equivalent chroma (40 Hz - 5 kHz, the
#     rest is untouched); Spectral mode compares half-semitone bands up to
#     Nyquist. The same real gain is applied to L and R, so pan and coherence
#     from the IR field are preserved. Source memory (30 dB release) and
#     lookahead are in the Advanced dialog; in source pauses the gains relax
#     back to 1, so endings ring freely. Offline processing allows
#     lookahead, which a real-time plugin cannot do.
#   - New visualization strip: contour attenuation over time (dark = removed).
#   - Normalize output moved to the Advanced dialog (form height unchanged).
#
# Changelog v0.4:
#   DSP fixes
#   - IR duration is capped (Advanced: Max IR duration, default 8 s). When the
#     spacing/curvature/generations request exceeds it, spacing is rescaled to
#     fit and the Info window says so. v0.3 could request hours of IR.
#   - Linear chirps replaced by saturating glides. v0.3 bounded each chirp for
#     one kernel duration but let it run to the end of the IR, so upward
#     chirps crossed Nyquist and downward chirps passed through 0 Hz. Glides
#     now start at the v0.3 rate, reach the v0.3 target at one kernel
#     duration, and asymptote inside 28 Hz .. 0.44*fs.
#   - Every generation is synthesized in its own short buffer and every mode
#     is written with Formula (part) over onset .. onset + 7 tau (-61 dB)
#     instead of a whole-kernel Formula per mode.
#   New timbral controls
#   - Survival shape: Decay (v0.3), Swell, Arch, Intermittent, Reverse bloom.
#   - Reversed generations (Advanced: Reverse probability; Reverse bloom
#     reverses every generation after the first).
#   New spatial controls
#   - Spatial mode: Generation pan (v0.3), Spectral prism, Dichotic comb,
#     Partial scatter. Modes 2-4 pan each partial on its own; Spectral spread
#     blends partial pan against the generation trajectory.
#   - Explicit interchannel coherence trajectory (Advanced: Coherence start /
#     end, -1..1). Sets the L/R phase offset of every partial, the polarity
#     of R micro-impulses and the independent share of R dust. Spatial width
#     scales it: width 0 is always mono-coherent.
#   - Motion depth: each generation glides toward the next one's position
#     while it rings.
#   - Dry pan: the dry signal no longer has to sit in the centre.
#   Interface / visualization
#   - Spacing curvature and Keep kernels moved to an optional Advanced dialog,
#     pre-filled from the preset. Keep it closed for batch/headless use.
#   - Right panel shows every partial (position, colour = frequency), the
#     generation trajectory and the MEASURED L/R coherence per generation.
#   - Left panel marks reversed generations.
#   - Info window reports output L/R correlation and mono fold-down loss.
#   - Fixed drawing-frame bugs from v0.3 (font change after viewport
#     selection, world-coordinate labels after Draw inner box, far axis
#     labels on panels without marks).
#   Presets now carry spread/coherence/reverse/motion values, so Metallic
#   Fracture, Panoramic Orbit and Unstable Matter differ from v0.3 even in
#   Generation pan / Decay mode. The random sequence differs from v0.3, so a
#   fixed seed does not reproduce a v0.3 render.
#
# Notes:
#   - Multichannel input is intentionally collapsed to mono before processing.
#   - The original Sound is never modified.
#   - The final wet signal is RMS-matched to the source before Wet/Dry mixing.
#   - Negative coherence is audible as width but cancels in a mono fold-down;
#     the Info window reports how much.
# ============================================================

# ---------------------------------------------------------------------------
# 0. SOURCE CHECK
# ---------------------------------------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound before running Evolving Convolution Field."
endif

source = selected("Sound")
sourceName$ = selected$("Sound")

selectObject: source
sourceChannels = Get number of channels
sampleRate = Get sampling frequency
sourcePeak = Get absolute extremum: 0, 0, "None"

if sourcePeak <= 0
    exitScript: "The selected Sound is silent."
endif
if sampleRate < 8000
    exitScript: "The selected Sound must have a sampling frequency of at least 8000 Hz."
endif

# ---------------------------------------------------------------------------
# 1. USER CONTROLS
# ---------------------------------------------------------------------------
form Evolving Convolution Field v0.7
    comment === Character / mix ===
    optionmenu character 1
        option Glass Bloom
        option Metallic Fracture
        option Spectral Dust
        option Alien Resonator
        option Panoramic Orbit
        option Unstable Matter
    real transformation_amount 0.92
    real wet_mix 0.72
    real spatial_width 0.88
    real adaptive_contour 0.5
    real material_memory 0.34

    comment === IR generations ===
    integer ir_generations 8
    real generation_spacing_ms 32
    real generation_decay 0.78
    real generational_mutation 0.68

    comment === Field ===
    optionmenu trajectory 3
        option Expanding Field
        option Alternating Wings
        option Spiral Orbit
        option Fracture Cascade
        option Chaotic Drift
    optionmenu spatial_mode 1
        option Generation pan
        option Spectral prism
        option Dichotic comb
        option Partial scatter
    optionmenu survival_shape 1
        option Decay
        option Swell
        option Arch
        option Intermittent
        option Reverse bloom

    comment === Output ===
    integer random_seed 0
    boolean advanced_options 0
    boolean draw_visualization 1
    boolean play_result 1
endform

if transformation_amount < 0 or transformation_amount > 1
    exitScript: "Transformation amount must be between 0 and 1."
endif
if wet_mix < 0 or wet_mix > 1
    exitScript: "Wet mix must be between 0 and 1."
endif
if spatial_width < 0 or spatial_width > 1
    exitScript: "Spatial width must be between 0 and 1."
endif
if material_memory < 0 or material_memory > 1
    exitScript: "Material memory must be between 0 and 1."
endif
if ir_generations < 1 or ir_generations > 32
    exitScript: "IR generations must be between 1 and 32."
endif
if generation_spacing_ms < 0 or generation_spacing_ms > 500
    exitScript: "Generation spacing must be between 0 and 500 ms."
endif
if generation_decay <= 0 or generation_decay > 1
    exitScript: "Generation decay must be greater than 0 and no greater than 1."
endif
if generational_mutation < 0 or generational_mutation > 1
    exitScript: "Generational mutation must be between 0 and 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

# ---------------------------------------------------------------------------
# 2. PRESET DEFINITIONS
#    The first block is the DNA of generation 0; later generations mutate it.
#    The second block pre-fills the Advanced dialog.
# ---------------------------------------------------------------------------
if character = 1
    characterName$ = "Glass_Bloom"
    baseKernelDuration = 0.090
    nModes = 24
    baseFrequency = 170
    inharmonicity = 1.18
    spectralExponent = 0.12
    modalGain = 0.70
    modalDecay = 0.060
    onsetSpread = 0.012
    chirpAmount = 0.18
    pulseCount = 22
    pulseGain = 0.55
    dustGain = 0.020
    trajectoryRate = 0.77
    spectral_spread = 0.70
    coherence_start = 0.90
    coherence_end = 0.30
    reverse_probability = 0
    motion_depth = 0
    memory_fragment_ms = 240
    memory_fragments_per_generation = 1
    memory_erosion = 0.55
    memory_pitch_mutation = 0.35
    memory_reverse_probability = 0.05
    memory_delay_scale = 1.40
    memory_jitter_ms = 24
    memory_energy_factor = 0.38
    memory_stereo_divergence = 0.46

elsif character = 2
    characterName$ = "Metallic_Fracture"
    baseKernelDuration = 0.060
    nModes = 20
    baseFrequency = 210
    inharmonicity = 1.31
    spectralExponent = 0.20
    modalGain = 0.62
    modalDecay = 0.040
    onsetSpread = 0.010
    chirpAmount = 0.48
    pulseCount = 34
    pulseGain = 0.82
    dustGain = 0.015
    trajectoryRate = 1.21
    spectral_spread = 0.85
    coherence_start = 0.80
    coherence_end = -0.20
    reverse_probability = 0.20
    motion_depth = 0
    memory_fragment_ms = 78
    memory_fragments_per_generation = 3
    memory_erosion = 0.78
    memory_pitch_mutation = 0.90
    memory_reverse_probability = 0.45
    memory_delay_scale = 1.15
    memory_jitter_ms = 20
    memory_energy_factor = 0.43
    memory_stereo_divergence = 0.88

elsif character = 3
    characterName$ = "Spectral_Dust"
    baseKernelDuration = 0.035
    nModes = 14
    baseFrequency = 460
    inharmonicity = 1.24
    spectralExponent = 0.26
    modalGain = 0.38
    modalDecay = 0.022
    onsetSpread = 0.007
    chirpAmount = 0.30
    pulseCount = 42
    pulseGain = 0.72
    dustGain = 0.065
    trajectoryRate = 1.67
    spectral_spread = 1.00
    coherence_start = 0.60
    coherence_end = 0.00
    reverse_probability = 0
    motion_depth = 0
    memory_fragment_ms = 38
    memory_fragments_per_generation = 4
    memory_erosion = 0.84
    memory_pitch_mutation = 0.65
    memory_reverse_probability = 0.16
    memory_delay_scale = 0.95
    memory_jitter_ms = 38
    memory_energy_factor = 0.34
    memory_stereo_divergence = 0.92

elsif character = 4
    characterName$ = "Alien_Resonator"
    baseKernelDuration = 0.135
    nModes = 30
    baseFrequency = 92
    inharmonicity = 1.095
    spectralExponent = -0.02
    modalGain = 0.84
    modalDecay = 0.105
    onsetSpread = 0.022
    chirpAmount = 0.12
    pulseCount = 14
    pulseGain = 0.38
    dustGain = 0.010
    trajectoryRate = 0.43
    spectral_spread = 0.60
    coherence_start = 0.95
    coherence_end = 0.50
    reverse_probability = 0
    motion_depth = 0.30
    memory_fragment_ms = 320
    memory_fragments_per_generation = 1
    memory_erosion = 0.42
    memory_pitch_mutation = 0.50
    memory_reverse_probability = 0.18
    memory_delay_scale = 1.80
    memory_jitter_ms = 42
    memory_energy_factor = 0.37
    memory_stereo_divergence = 0.58

elsif character = 5
    characterName$ = "Panoramic_Orbit"
    baseKernelDuration = 0.080
    nModes = 22
    baseFrequency = 145
    inharmonicity = 1.23
    spectralExponent = 0.14
    modalGain = 0.65
    modalDecay = 0.060
    onsetSpread = 0.016
    chirpAmount = 0.25
    pulseCount = 28
    pulseGain = 0.65
    dustGain = 0.020
    trajectoryRate = 1.03
    spectral_spread = 0.50
    coherence_start = 0.90
    coherence_end = 0.10
    reverse_probability = 0
    motion_depth = 0.70
    memory_fragment_ms = 125
    memory_fragments_per_generation = 2
    memory_erosion = 0.58
    memory_pitch_mutation = 0.48
    memory_reverse_probability = 0.12
    memory_delay_scale = 1.35
    memory_jitter_ms = 30
    memory_energy_factor = 0.40
    memory_stereo_divergence = 0.84

else
    characterName$ = "Unstable_Matter"
    baseKernelDuration = 0.110
    nModes = 32
    baseFrequency = 66
    inharmonicity = 1.37
    spectralExponent = 0.18
    modalGain = 0.75
    modalDecay = 0.080
    onsetSpread = 0.030
    chirpAmount = 0.58
    pulseCount = 38
    pulseGain = 0.72
    dustGain = 0.045
    trajectoryRate = 1.41
    spectral_spread = 0.80
    coherence_start = 0.70
    coherence_end = -0.50
    reverse_probability = 0.30
    motion_depth = 0.40
    memory_fragment_ms = 165
    memory_fragments_per_generation = 3
    memory_erosion = 0.90
    memory_pitch_mutation = 1.00
    memory_reverse_probability = 0.52
    memory_delay_scale = 1.25
    memory_jitter_ms = 72
    memory_energy_factor = 0.48
    memory_stereo_divergence = 1.00
endif

characterDisplay$ = replace$(characterName$, "_", " ", 0)

# Advanced defaults shared by every preset.
spacing_curvature = 1.25
dry_pan = 0
max_IR_duration = 8
keep_kernels = 0
normalize_output = 1
contour_mode = 1
contour_memory_ms = 250
contour_lookahead_ms = 0

# ---------------------------------------------------------------------------
# 2B. OPTIONAL ADVANCED DIALOG
#     Every field is initialised above, so builds that auto-continue a pause
#     without assigning its fields still run. Leave it closed for batch use:
#     Praat 6.4.63 / 7.0 end a headless script silently at beginPause.
# ---------------------------------------------------------------------------
if advanced_options
    advancedClicked = 2
    beginPause: "Evolving Convolution Field - advanced"
        comment: "Pre-filled from the " + characterDisplay$ + " preset."
        real: "Spacing curvature", string$(spacing_curvature)
        real: "Spectral spread", string$(spectral_spread)
        real: "Coherence start", string$(coherence_start)
        real: "Coherence end", string$(coherence_end)
        real: "Reverse probability", string$(reverse_probability)
        real: "Motion depth", string$(motion_depth)
        real: "Dry pan", string$(dry_pan)
        real: "Max IR duration", string$(max_IR_duration)
        boolean: "Keep kernels", keep_kernels
        boolean: "Normalize output", normalize_output
        comment: "Adaptive contour"
        choice: "Contour mode", contour_mode
            option: "Pitch class"
            option: "Spectral"
        real: "Contour memory ms", string$(contour_memory_ms)
        real: "Contour lookahead ms", string$(contour_lookahead_ms)
        comment: "Material memory"
        real: "Memory fragment ms", string$(memory_fragment_ms)
        integer: "Memory fragments per generation", string$(memory_fragments_per_generation)
        real: "Memory erosion", string$(memory_erosion)
        real: "Memory pitch mutation", string$(memory_pitch_mutation)
        real: "Memory reverse probability", string$(memory_reverse_probability)
        real: "Memory delay scale", string$(memory_delay_scale)
        real: "Memory jitter ms", string$(memory_jitter_ms)
        real: "Memory stereo divergence", string$(memory_stereo_divergence)
    advancedClicked = endPause: "Cancel", "OK", 2, 1
    if advancedClicked = 1
        exitScript: "Cancelled."
    endif
endif

if spacing_curvature < 0.25 or spacing_curvature > 3
    exitScript: "Spacing curvature must be between 0.25 and 3."
endif
if spectral_spread < 0 or spectral_spread > 1
    exitScript: "Spectral spread must be between 0 and 1."
endif
if coherence_start < -1 or coherence_start > 1 or coherence_end < -1 or coherence_end > 1
    exitScript: "Coherence start and end must be between -1 and 1."
endif
if reverse_probability < 0 or reverse_probability > 1
    exitScript: "Reverse probability must be between 0 and 1."
endif
if motion_depth < 0 or motion_depth > 1
    exitScript: "Motion depth must be between 0 and 1."
endif
if dry_pan < -1 or dry_pan > 1
    exitScript: "Dry pan must be between -1 and 1."
endif
if adaptive_contour < -1 or adaptive_contour > 1
    exitScript: "Adaptive contour must be between -1 and 1 (0 = off)."
endif
if contour_memory_ms < 10 or contour_memory_ms > 5000
    exitScript: "Contour memory must be between 10 and 5000 ms."
endif
if contour_lookahead_ms < 0 or contour_lookahead_ms > 1000
    exitScript: "Contour lookahead must be between 0 and 1000 ms."
endif
if max_IR_duration < 0.5 or max_IR_duration > 30
    exitScript: "Max IR duration must be between 0.5 and 30 s."
endif
if memory_fragment_ms < 10 or memory_fragment_ms > 600
    exitScript: "Memory fragment length must be between 10 and 600 ms."
endif
if memory_fragments_per_generation < 1 or memory_fragments_per_generation > 8
    exitScript: "Memory fragments per generation must be between 1 and 8."
endif
if memory_erosion < 0 or memory_erosion > 0.98
    exitScript: "Memory erosion must be between 0 and 0.98."
endif
if memory_pitch_mutation < 0 or memory_pitch_mutation > 2
    exitScript: "Memory pitch mutation must be between 0 and 2."
endif
if memory_reverse_probability < 0 or memory_reverse_probability > 1
    exitScript: "Memory reverse probability must be between 0 and 1."
endif
if memory_delay_scale < 0.25 or memory_delay_scale > 3
    exitScript: "Memory delay scale must be between 0.25 and 3."
endif
if memory_jitter_ms < 0 or memory_jitter_ms > 250
    exitScript: "Memory jitter must be between 0 and 250 ms."
endif
if memory_stereo_divergence < 0 or memory_stereo_divergence > 1
    exitScript: "Memory stereo divergence must be between 0 and 1."
endif

amount = transformation_amount
wet = wet_mix
width = spatial_width
generations = ir_generations
spacingSeconds = generation_spacing_ms / 1000
mutation = generational_mutation
memory = material_memory
memoryFragmentSeconds = memory_fragment_ms / 1000
memoryJitterSeconds = memory_jitter_ms / 1000
memoryStereoDivergence = memory_stereo_divergence
safeTop = 0.44 * sampleRate
lowGuard = 28
twoPi = 2 * pi
glideTime = baseKernelDuration
motionTime = baseKernelDuration
goldenAngle = 2.399963229728653
uid$ = string$(randomInteger(10000, 99999))

if spatial_mode = 1
    spreadUsed = 0
else
    spreadUsed = spectral_spread
endif

# Prism range spans the preset's own partial series (m = 1 .. nModes), so
# the spectrum is spread over the whole stereo field rather than bunched
# toward the side where most partials of a stretched series sit.
prismLow = max(lowGuard, 0.8 * baseFrequency)
prismHigh = max(prismLow * 2, min(safeTop, 1.25 * baseFrequency * (nModes ^ inharmonicity)))
prismLogRange = ln(prismHigh / prismLow)

# Strongest nominal partial amplitude anywhere in the field (survival <= 1).
modeReference = amount * modalGain * 1.26 * max(1, nModes ^ spectralExponent) / sqrt(nModes)
modeReference = max(modeReference, 1e-9)

# ---------------------------------------------------------------------------
# 3. RANDOM STATE
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
endif

# ---------------------------------------------------------------------------
# 4. PREPARE A MONO, ZERO-BASED PROCESSING SOURCE
# ---------------------------------------------------------------------------
selectObject: source
if sourceChannels = 1
    Copy: "ecf_source_temp_" + uid$
    sourceMonoTemp = selected("Sound")
else
    Convert to mono
    sourceMonoTemp = selected("Sound")
    Rename: "ecf_source_temp_" + uid$

    # Defensive fallback for strong antiphase cancellation.
    selectObject: sourceMonoTemp
    monoPeak = Get absolute extremum: 0, 0, "None"
    if monoPeak < 0.01 * sourcePeak
        removeObject: sourceMonoTemp
        selectObject: source
        Extract one channel: 1
        sourceMonoTemp = selected("Sound")
        Rename: "ecf_source_temp_" + uid$
    endif
endif

selectObject: sourceMonoTemp
sourceSamples = Get number of samples
sourceRMS = Get root-mean-square: 0, 0
sourceDuration = sourceSamples / sampleRate

sourceProc = Create Sound from formula: "ecf_source_" + uid$, 1, 0, sourceDuration, sampleRate,
    ... "object[sourceMonoTemp,1,col]"
removeObject: sourceMonoTemp

# ---------------------------------------------------------------------------
# 5. IR DURATION WITH A HARD CAP
# ---------------------------------------------------------------------------
tailRoom = baseKernelDuration * (1.35 + 0.45 * mutation)
if generations = 1
    lastOffset = 0
else
    lastOffset = spacingSeconds * ((generations - 1) ^ spacing_curvature)
endif

spacingWasCapped = 0
requestedIRDuration = lastOffset + tailRoom
if requestedIRDuration > max_IR_duration
    spacingSeconds = spacingSeconds * (max_IR_duration - tailRoom) / lastOffset
    lastOffset = max_IR_duration - tailRoom
    spacingWasCapped = 1
endif
effectiveSpacingMs = spacingSeconds * 1000

irDuration = max(lastOffset + tailRoom, 2 / sampleRate)

identityAmplitude = 1 - amount
broadbandAnchor = 0.018 * amount

kernelL = Create Sound from formula: "ecf_IR_L_" + uid$, 1, 0, irDuration, sampleRate,
    ... "if col = 1 then identityAmplitude + broadbandAnchor else 0 fi"
kernelR = Create Sound from formula: "ecf_IR_R_" + uid$, 1, 0, irDuration, sampleRate,
    ... "if col = 1 then identityAmplitude + broadbandAnchor else 0 fi"
# ---------------------------------------------------------------------------
# 6. GENERATION PLAN
#    Timing, survival, trajectory, reversal and coherence are fixed here for
#    every generation before any synthesis, so each generation can glide
#    toward the next one's position. A fixed number of random draws per
#    generation keeps the sequence stable when options change.
# ---------------------------------------------------------------------------
generationOffset# = zero#(generations)
generationAmplitude# = zero#(generations)
generationPanRaw# = zero#(generations)
generationPan# = zero#(generations)
generationMutation# = zero#(generations)
generationFreqScale# = zero#(generations)
generationChirpScale# = zero#(generations)
generationReversed# = zero#(generations)
generationCoherence# = zero#(generations)
generationMeasuredCoh# = zero#(generations)

chaoticState = randomUniform(0.17, 0.83)
aliveIndex = 0
deadRun = 0

for g from 0 to generations - 1
    gi = g + 1
    if generations = 1
        progress = 0
    else
        progress = g / (generations - 1)
    endif
    mutationProgress = mutation * progress

    # Sample-aligned onset so generation buffers add into the kernel exactly.
    generationOffset#[gi] = round(spacingSeconds * (g ^ spacing_curvature) * sampleRate) / sampleRate
    generationMutation#[gi] = mutationProgress

    # 6A. Trajectory (panPosition -1..+1 before width) and spectral coupling.
    draw1 = randomUniform(-1, 1)
    draw2 = randomUniform(-1, 1)
    draw3 = randomUniform(0, 1)
    if trajectory = 1
        if g = 0
            panPosition = 0
        elsif g mod 2 = 0
            panPosition = progress
        else
            panPosition = -progress
        endif
        frequencyScale = exp(0.52 * mutationProgress * progress)
        chirpScale = 1 + 0.80 * mutationProgress
    elsif trajectory = 2
        if g = 0
            panPosition = 0
        elsif g mod 2 = 0
            panPosition = 0.35 + 0.65 * progress
        else
            panPosition = -(0.35 + 0.65 * progress)
        endif
        frequencyScale = exp(0.30 * mutationProgress * panPosition)
        chirpScale = 1 + 1.15 * mutationProgress
    elsif trajectory = 3
        angle = g * goldenAngle
        panPosition = sin(angle)
        frequencyScale = exp(0.45 * mutationProgress * cos(angle))
        chirpScale = 1 + 0.70 * mutationProgress * (1 + sin(angle))
    elsif trajectory = 4
        panPosition = draw1
        frequencyScale = exp(0.70 * draw2 * mutationProgress)
        chirpScale = 1 + (0.2 + 1.6 * draw3) * mutationProgress
    else
        chaoticState = 3.89 * chaoticState * (1 - chaoticState)
        panPosition = 2 * chaoticState - 1
        frequencyScale = exp((chaoticState - 0.5) * 1.25 * mutationProgress)
        chirpScale = 1 + (0.35 + 1.5 * chaoticState) * mutationProgress
    endif
    generationPanRaw#[gi] = panPosition
    generationPan#[gi] = width * panPosition
    generationFreqScale#[gi] = frequencyScale
    generationChirpScale#[gi] = chirpScale

    # 6B. Survival shape.
    aliveDraw = randomUniform(0, 1)
    reverseDraw = randomUniform(0, 1)
    if survival_shape = 1 or survival_shape = 5
        survival = generation_decay ^ g
    elsif survival_shape = 2
        survival = generation_decay ^ (generations - 1 - g)
    elsif survival_shape = 3
        survival = generation_decay ^ abs(2 * g - (generations - 1))
    else
        # Intermittent: generations die and resurrect; energy only drains
        # across generations that actually sound. No gap longer than two.
        alive = 1
        if g > 0 and aliveDraw < 0.40 and deadRun < 2
            alive = 0
        endif
        if alive
            survival = generation_decay ^ aliveIndex
            aliveIndex = aliveIndex + 1
            deadRun = 0
        else
            survival = 0
            deadRun = deadRun + 1
        endif
    endif
    generationAmplitude#[gi] = survival

    # 6C. Reversal. Generation 0 keeps the attack anchor.
    reversed = 0
    if g > 0
        if survival_shape = 5 or reverseDraw < reverse_probability
            reversed = 1
        endif
    endif
    generationReversed#[gi] = reversed

    # 6D. Coherence target; width scales the departure from full coherence.
    targetCoherence = coherence_start + (coherence_end - coherence_start) * progress
    generationCoherence#[gi] = 1 - width * (1 - targetCoherence)
endfor

# ---------------------------------------------------------------------------
# 7. SYNTHESIZE EACH GENERATION IN ITS OWN BUFFER
# ---------------------------------------------------------------------------
maxPartials = generations * nModes
partialTime# = zero#(maxPartials)
partialPan# = zero#(maxPartials)
partialLogPos# = zero#(maxPartials)
partialAmp# = zero#(maxPartials)
nPartialsViz = 0

activeModesTotal = 0
activePulsesTotal = 0
reversedTotal = 0
silentTotal = 0

for g from 0 to generations - 1
    gi = g + 1
    mutationProgress = generationMutation#[gi]
    generationAmplitude = generationAmplitude#[gi]
    offsetTime = generationOffset#[gi]
    reversed = generationReversed#[gi]
    cohGen = generationCoherence#[gi]
    phaseOffset = arccos(max(-1, min(1, cohGen)))

    # Motion: glide toward the next generation's position (last: mirror).
    panRawStart = generationPanRaw#[gi]
    if gi < generations
        panRawTarget = generationPanRaw#[gi + 1]
    else
        panRawTarget = -panRawStart
    endif
    panRawEnd = panRawStart + motion_depth * (panRawTarget - panRawStart)

    # Structural draws happen for silent generations too (stable sequence).
    generationInharmonicity = inharmonicity + randomUniform(-0.11, 0.11) * mutationProgress
    generationDecayScale = exp(randomUniform(-0.65, 0.55) * mutationProgress)
    generationOnsetScale = 1 + randomUniform(-0.45, 1.10) * mutationProgress
    localGenerationDuration = baseKernelDuration * (0.70 + 0.65 * randomUniform(0, 1))

    if generationAmplitude <= 0
        silentTotal = silentTotal + 1
    else
        remaining = irDuration - offsetTime
        if reversed
            generationLength = min(remaining, tailRoom)
            reversedTotal = reversedTotal + 1
        else
            generationLength = remaining
        endif
        generationLength = max(generationLength, 4 / sampleRate)

        genL = Create Sound from formula: "ecf_genL_" + uid$, 1, 0, generationLength, sampleRate, "0"
        genR = Create Sound from formula: "ecf_genR_" + uid$, 1, 0, generationLength, sampleRate, "0"
        selectObject: genL
        nGenSamples = Get number of samples

        # -------------------------------------------------------
        # 7A. MUTATING RESONANT PARTIALS WITH SATURATING GLIDES
        # -------------------------------------------------------
        for m to nModes
            nominalFrequency = baseFrequency * (m ^ generationInharmonicity) * generationFreqScale#[gi]
            nominalFrequency = nominalFrequency * exp(randomUniform(-0.24, 0.24) * mutationProgress)

            ampDraw = randomUniform(0.74, 1.26)
            onsetDraw = randomUniform(0, 1)
            attackDraw = randomUniform(0, 1)
            tauDraw = randomUniform(0.55, 1.40)
            phaseCenter = randomUniform(-pi, pi)
            phaseSignDraw = randomUniform(0, 1)
            detuneDraw = randomUniform(-0.018, 0.018)
            glideSignDraw = randomUniform(0, 1)
            ampRDraw = randomUniform(-0.22, 0.22)
            scatterDraw = randomUniform(-1, 1)

            if nominalFrequency > lowGuard and nominalFrequency < safeTop
                modeAmplitude = amount * modalGain * generationAmplitude
                modeAmplitude = modeAmplitude * (m ^ spectralExponent) / sqrt(nModes) * ampDraw

                onset = onsetSpread * generationOnsetScale * onsetDraw
                attack = 0.00008 + (0.0012 + 0.0010 * mutationProgress - 0.00008) * attackDraw
                tau = modalDecay * generationDecayScale * tauDraw
                # Render until the partial is 66 dB under the strongest nominal
                # partial of the whole field (never longer than 7 tau = -61 dB
                # of its own peak). Weak late partials therefore stop early.
                ringTaus = min(7, ln(max(1e-12, modeAmplitude) / (0.0005 * modeReference)))
                windowEnd = min(generationLength, onset + ringTaus * tau)

                if windowEnd > onset + 2 / sampleRate
                    activeModesTotal = activeModesTotal + 1

                    # Coherence: interchannel correlation of a partial = cos(phase offset).
                    phaseSign = if phaseSignDraw < 0.5 then -1 else 1 fi
                    phaseL = phaseCenter - 0.5 * phaseSign * phaseOffset
                    phaseR = phaseCenter + 0.5 * phaseSign * phaseOffset

                    stereoDetune = width * mutationProgress * detuneDraw
                    frequencyL = nominalFrequency * (1 - 0.5 * stereoDetune)
                    frequencyR = nominalFrequency * (1 + 0.5 * stereoDetune)

                    # Saturating glide f(t) = f0 + glide * (1 - exp(-t/T)).
                    # Same frequency as the v0.3 chirp at t = T, bounded forever.
                    desiredSweep = generationChirpScale#[gi] * chirpAmount * nominalFrequency / (1 - exp(-1))
                    if glideSignDraw < 0.5
                        glide = -min(desiredSweep, 0.95 * (min(frequencyL, frequencyR) - lowGuard))
                    else
                        glide = min(desiredSweep, 0.95 * (safeTop - max(frequencyL, frequencyR)))
                    endif

                    # Partial position.
                    logPos = max(0, min(1, ln(nominalFrequency / prismLow) / prismLogRange))
                    if spatial_mode = 2
                        partialPan = 2 * logPos - 1
                    elsif spatial_mode = 3
                        partialPan = if m mod 2 = 1 then -1 else 1 fi
                        if g mod 2 = 1
                            partialPan = -partialPan
                        endif
                    elsif spatial_mode = 4
                        partialPan = scatterDraw
                    else
                        partialPan = 0
                    endif
                    panStart = width * ((1 - spreadUsed) * panRawStart + spreadUsed * partialPan)
                    panEnd = width * ((1 - spreadUsed) * panRawEnd + spreadUsed * partialPan)
                    panDelta = panEnd - panStart

                    ampL = modeAmplitude
                    ampR = modeAmplitude * (1 + width * mutationProgress * ampRDraw)

                    if abs(panDelta) < 1e-9
                        gainL = sqrt(0.5 * (1 - panStart))
                        gainR = sqrt(0.5 * (1 + panStart))
                        selectObject: genL
                        Formula (part): onset, windowEnd, 1, 1,
                            ... "self + ampL * gainL * (1-exp(-(x-onset)/attack)) * exp(-(x-onset)/tau) * sin(twoPi*(frequencyL*(x-onset) + glide*((x-onset) - glideTime*(1-exp(-(x-onset)/glideTime)))) + phaseL)"
                        selectObject: genR
                        Formula (part): onset, windowEnd, 1, 1,
                            ... "self + ampR * gainR * (1-exp(-(x-onset)/attack)) * exp(-(x-onset)/tau) * sin(twoPi*(frequencyR*(x-onset) + glide*((x-onset) - glideTime*(1-exp(-(x-onset)/glideTime)))) + phaseR)"
                    else
                        selectObject: genL
                        Formula (part): onset, windowEnd, 1, 1,
                            ... "self + ampL * sqrt(0.5*(1 - (panStart + panDelta*(1-exp(-(x-onset)/motionTime))))) * (1-exp(-(x-onset)/attack)) * exp(-(x-onset)/tau) * sin(twoPi*(frequencyL*(x-onset) + glide*((x-onset) - glideTime*(1-exp(-(x-onset)/glideTime)))) + phaseL)"
                        selectObject: genR
                        Formula (part): onset, windowEnd, 1, 1,
                            ... "self + ampR * sqrt(0.5*(1 + (panStart + panDelta*(1-exp(-(x-onset)/motionTime))))) * (1-exp(-(x-onset)/attack)) * exp(-(x-onset)/tau) * sin(twoPi*(frequencyR*(x-onset) + glide*((x-onset) - glideTime*(1-exp(-(x-onset)/glideTime)))) + phaseR)"
                    endif

                    # Visualization record (reversed partials land at the far end).
                    nPartialsViz = nPartialsViz + 1
                    if reversed
                        partialTime#[nPartialsViz] = offsetTime + generationLength - onset
                    else
                        partialTime#[nPartialsViz] = offsetTime + onset
                    endif
                    partialPan#[nPartialsViz] = panStart + 0.5 * panDelta
                    partialLogPos#[nPartialsViz] = logPos
                    partialAmp#[nPartialsViz] = modeAmplitude
                endif
            endif
        endfor

        # -------------------------------------------------------
        # 7B. GENERATIONAL MICRO-IMPULSE CLOUD (broadband: generation pan)
        # -------------------------------------------------------
        pulsesThisGeneration = max(4, round(pulseCount / sqrt(generations)))
        maxStereoJitterSamples = round(width * mutationProgress * 0.0045 * sampleRate)

        for p to pulsesThisGeneration
            u = randomUniform(0, 1)
            shapeDraw = randomUniform(0, 1)
            jitterDraw = randomUniform(-1, 1)
            signDraw = randomUniform(0, 1)
            levelDraw = randomUniform(0.25, 1.0)
            gainRDraw = randomUniform(-0.35, 0.35)
            polarityDraw = randomUniform(0, 1)

            pulseTime = localGenerationDuration * (u ^ (1.2 + 1.2 * shapeDraw))
            pulseSampleL = min(nGenSamples, max(1, 1 + floor(pulseTime * sampleRate)))
            jitter = round(maxStereoJitterSamples * jitterDraw)
            pulseSampleR = min(nGenSamples, max(1, pulseSampleL + jitter))

            pulseSign = if signDraw < 0.5 then -1 else 1 fi
            pulseAmplitude = amount * pulseGain * generationAmplitude * pulseSign
            pulseAmplitude = pulseAmplitude * exp(-2.2 * pulseTime / max(0.001, localGenerationDuration)) * levelDraw

            pulsePan = width * (panRawStart + (panRawEnd - panRawStart) * (1 - exp(-pulseTime / motionTime)))
            pulseAmpL = pulseAmplitude * sqrt(0.5 * (1 - pulsePan))
            pulseAmpR = pulseAmplitude * sqrt(0.5 * (1 + pulsePan)) * (1 + width * mutationProgress * gainRDraw)
            # Polarity flip with probability (1 - c)/2 gives expected correlation c.
            if polarityDraw < 0.5 * (1 - cohGen)
                pulseAmpR = -pulseAmpR
            endif

            selectObject: genL
            oldPulse = Get value at sample number: 1, pulseSampleL
            Set value at sample number: 1, pulseSampleL, oldPulse + pulseAmpL
            selectObject: genR
            oldPulse = Get value at sample number: 1, pulseSampleR
            Set value at sample number: 1, pulseSampleR, oldPulse + pulseAmpR
            activePulsesTotal = activePulsesTotal + 1
        endfor

        # -------------------------------------------------------
        # 7C. BROADBAND DUST DESCENDANT
        #     R = c * shared + sqrt(1 - c^2) * independent.
        # -------------------------------------------------------
        dustDuration = max(2 / sampleRate, min(baseKernelDuration, generationLength))
        dustShared = Create Sound from formula: "ecf_dustA_" + uid$, 1, 0, dustDuration, sampleRate,
            ... "amount * dustGain * generationAmplitude * exp(-3.2*x/baseKernelDuration) * randomGauss(0,1)"
        dustOwn = Create Sound from formula: "ecf_dustB_" + uid$, 1, 0, dustDuration, sampleRate,
            ... "amount * dustGain * generationAmplitude * exp(-3.2*x/baseKernelDuration) * randomGauss(0,1)"
        dustDivergence = width * mutationProgress * randomUniform(-0.28, 0.28)
        dustOwnShare = sqrt(max(0, 1 - cohGen ^ 2))

        selectObject: genL
        Formula (part): 0, dustDuration, 1, 1,
            ... "self + (1 - dustDivergence) * sqrt(0.5*(1 - width*(panRawStart + (panRawEnd-panRawStart)*(1-exp(-x/motionTime))))) * object(dustShared, x)"
        selectObject: genR
        Formula (part): 0, dustDuration, 1, 1,
            ... "self + (1 + dustDivergence) * sqrt(0.5*(1 + width*(panRawStart + (panRawEnd-panRawStart)*(1-exp(-x/motionTime))))) * (cohGen * object(dustShared, x) + dustOwnShare * object(dustOwn, x))"
        removeObject: dustShared, dustOwn

        # -------------------------------------------------------
        # 7D. REVERSAL: taper the truncated tail, then turn the generation
        #     around so it swells into its own attack.
        # -------------------------------------------------------
        if reversed
            taper = 0.15 * generationLength
            taperStart = generationLength - taper
            selectObject: genL
            Formula (part): taperStart, generationLength, 1, 1, "self * 0.5 * (1 + cos(pi * (x - taperStart) / taper))"
            Reverse
            selectObject: genR
            Formula (part): taperStart, generationLength, 1, 1, "self * 0.5 * (1 + cos(pi * (x - taperStart) / taper))"
            Reverse
        endif

        # -------------------------------------------------------
        # 7E. ADD THE GENERATION INTO THE KERNEL AT ITS ONSET
        # -------------------------------------------------------
        selectObject: kernelL
        Formula (part): offsetTime, offsetTime + generationLength, 1, 1, "self + object(genL, x - offsetTime)"
        selectObject: kernelR
        Formula (part): offsetTime, offsetTime + generationLength, 1, 1, "self + object(genR, x - offsetTime)"
        removeObject: genL, genR
    endif
endfor

# ---------------------------------------------------------------------------
# 8. MEASURED COHERENCE PER GENERATION WINDOW
#    Integral of L*R = (E[L+R] - E[L-R]) / 4. Windows run from each onset to
#    the next distinct onset, so overlapping tails are included - this is
#    what the listener gets, not the target.
# ---------------------------------------------------------------------------
kernelSum = Create Sound from formula: "ecf_ksum_" + uid$, 1, 0, irDuration, sampleRate,
    ... "object[kernelL,1,col] + object[kernelR,1,col]"
kernelDiff = Create Sound from formula: "ecf_kdiff_" + uid$, 1, 0, irDuration, sampleRate,
    ... "object[kernelL,1,col] - object[kernelR,1,col]"

for gi to generations
    generationMeasuredCoh#[gi] = undefined
    if generationAmplitude#[gi] > 0
        windowStart = generationOffset#[gi]
        windowStop = irDuration
        for gj from gi + 1 to generations
            if generationOffset#[gj] > windowStart + 0.005 and generationOffset#[gj] < windowStop
                windowStop = generationOffset#[gj]
            endif
        endfor
        if generationReversed#[gi]
            windowStop = min(irDuration, max(windowStop, windowStart + tailRoom))
        endif
        windowStop = max(windowStop, min(irDuration, windowStart + 0.01))
        if windowStop > windowStart + 2 / sampleRate
            selectObject: kernelL
            energyL = Get energy: windowStart, windowStop
            selectObject: kernelR
            energyR = Get energy: windowStart, windowStop
            selectObject: kernelSum
            energySum = Get energy: windowStart, windowStop
            selectObject: kernelDiff
            energyDiff = Get energy: windowStart, windowStop
            if energyL > 0 and energyR > 0
                generationMeasuredCoh#[gi] = 0.25 * (energySum - energyDiff) / sqrt(energyL * energyR)
            endif
        endif
    endif
endfor
removeObject: kernelSum, kernelDiff

# Down-only IR protection. Relative generational structure is preserved.
selectObject: kernelL
peakL = Get absolute extremum: 0, 0, "None"
selectObject: kernelR
peakR = Get absolute extremum: 0, 0, "None"
maxIRPeak = max(peakL, peakR)
if maxIRPeak > 0.95
    irProtection = 0.95 / maxIRPeak
    selectObject: kernelL
    Formula: "self * irProtection"
    selectObject: kernelR
    Formula: "self * irProtection"
endif

# ---------------------------------------------------------------------------
# 9. CONVOLVE
# ---------------------------------------------------------------------------
selectObject: sourceProc
plusObject: kernelL
Convolve: "sum", "zero"
wetL = selected("Sound")
Rename: "ecf_wet_L_" + uid$

selectObject: sourceProc
plusObject: kernelR
Convolve: "sum", "zero"
wetR = selected("Sound")
Rename: "ecf_wet_R_" + uid$

# Shared RMS matching preserves the L/R energy relationship.
selectObject: wetL
wetRMSL = Get root-mean-square: 0, 0
selectObject: wetR
wetRMSR = Get root-mean-square: 0, 0
wetStereoRMS = sqrt(0.5 * (wetRMSL^2 + wetRMSR^2))

if wetStereoRMS > 0 and sourceRMS > 0
    wetLevelScale = min(12, sourceRMS / wetStereoRMS)
    selectObject: wetL
    Formula: "self * wetLevelScale"
    selectObject: wetR
    Formula: "self * wetLevelScale"
endif

# ---------------------------------------------------------------------------
# 9B. ADAPTIVE CONTOUR
#     Frame-by-frame harmonic comparison of the wet field with the dry source.
#     Frames are ~170 ms (8192 samples at 44.1/48 kHz, hop 50%), long enough
#     to separate semitones down to ~150 Hz.
#     ANALYSIS (Hann window): FFT power of the dry source and of wet L and R
#     is gathered into classes k - 12 pitch classes, or half-semitone bands -
#     with nearest-class weights, so a partial does not leak into the class
#     next door. Per class:
#       H_k = source power, held with a release of 30 dB per Memory time
#       W_k = wet power (mean of L and R)
#       sim_k = min(1, 1.5 * sqrt( (H_k / sum H) / (W_k / sum W) ))
#     i.e. the SHAPES of the two distributions are compared, so the overall
#     wet/dry level difference does not matter.
#       gain_k = 1 - a*(1 - sim_k)  for a > 0   (follow the source)
#       gain_k = 1 - |a|*sim_k      for a < 0   (fill what the source lacks)
#     PROCESSING (sine window, sine^2 at 50% sums to 1): class gains are
#     spread back to FFT bins with linear (partition-of-unity) weights and
#     applied identically to wet L and R, so the IR field's pan and coherence
#     are untouched. Bins outside the analysed range keep gain 1. In frames
#     where the source is ~20 dB under its average level the gains relax
#     back toward 1 at the Memory rate, so pauses and endings let the field
#     ring - only harmonic change is contoured.
# ---------------------------------------------------------------------------
contourActive = 0
contourFrames = 0
contourFramesHeld = 0
contourWetChangeDB = 0
if adaptive_contour <> 0
    contourActive = 1
    frameSamples = 2 ^ round(log2(0.17 * sampleRate))
    hopSamples = frameSamples / 2
    frameDuration = frameSamples / sampleRate
    hopDuration = hopSamples / sampleRate
    lookSamples = round(contour_lookahead_ms / 1000 * sampleRate)
    selectObject: wetL
    nWet = Get number of samples
    wetDuration = nWet / sampleRate
    energyWetBeforeL = Get energy: 0, 0
    selectObject: wetR
    energyWetBeforeR = Get energy: 0, 0
    energyWetBefore = energyWetBeforeL + energyWetBeforeR
    nBinsC = frameSamples / 2 + 1
    binHz = sampleRate / frameSamples

    contourLow = 40
    if contour_mode = 1
        nClasses = 12
        contourHigh = min(5000, safeTop)
    else
        nClasses = ceiling(24 * log2((0.5 * sampleRate) / contourLow)) + 1
        contourHigh = 0.5 * sampleRate
    endif
    # membA## : analysis, nearest class only (triangular, 0 at the midpoint)
    # memb##  : synthesis, linear split between the two nearest classes
    membA## = zero##(nBinsC, nClasses)
    memb## = zero##(nBinsC, nClasses)
    membSum## = zero##(1, nBinsC)
    for j to nBinsC
        f = (j - 1) * binHz
        if f >= contourLow and f <= contourHigh
            if contour_mode = 1
                position = 12 * log2(f / 16.351597831287414)
                position = position - 12 * floor(position / 12)
            else
                position = 24 * log2(f / contourLow)
            endif
            k0 = floor(position)
            frac = position - k0
            kNear = round(position)
            distance = abs(position - kNear)
            if contour_mode = 1
                k1 = k0 + 1
                if k1 >= 12
                    k1 = 0
                endif
                if kNear >= 12
                    kNear = 0
                endif
                memb##[j, k0 + 1] = 1 - frac
                memb##[j, k1 + 1] = frac
                membSum##[1, j] = 1
                membA##[j, kNear + 1] = 1 - 2 * distance
            else
                memb##[j, k0 + 1] = 1 - frac
                membSum##[1, j] = 1 - frac
                if k0 + 2 <= nClasses
                    memb##[j, k0 + 2] = frac
                    membSum##[1, j] = 1
                endif
                if kNear + 1 <= nClasses
                    membA##[j, kNear + 1] = 1 - 2 * distance
                endif
            endif
        endif
    endfor
    membT## = transpose##(memb##)

    holdC## = zero##(1, nClasses)
    gainC## = zero##(1, nClasses)
    for k to nClasses
        gainC##[1, k] = 1
    endfor
    # Memory = time for a pitch the source has left to fall 30 dB in H.
    releaseFactor = 10 ^ (-3 * hopDuration / (contour_memory_ms / 1000))
    gainSmoothing = exp(-hopDuration / 0.06)
    # Hann-window frame energy of a source at its average level is about
    # 0.375 * RMS^2 * frameDuration; "silence" is 20 dB under that.
    silenceEnergy = 0.01 * 0.375 * sourceRMS ^ 2 * frameDuration

    contourFrames = ceiling((nWet + hopSamples) / hopSamples)
    contourHistory## = zero##(nClasses, contourFrames)

    contourOutL = Create Sound from formula: "ecf_cL_" + uid$, 1, 0, wetDuration, sampleRate, "0"
    contourOutR = Create Sound from formula: "ecf_cR_" + uid$, 1, 0, wetDuration, sampleRate, "0"

    for fr to contourFrames
        frameOffset = (fr - 2) * hopSamples
        dryOffset = frameOffset + lookSamples

        # --- analysis (Hann) ---
        analysisD = Create Sound from formula: "ecf_aD", 1, 0, frameDuration, sampleRate,
            ... "if col + dryOffset >= 1 and col + dryOffset <= sourceSamples then object[sourceProc, 1, col + dryOffset] * 0.5 * (1 - cos(2 * pi * (col - 0.5) / frameSamples)) else 0 fi"
        frameDryEnergy = Get energy: 0, 0
        if frameDryEnergy > silenceEnergy
            spectrumAD = To Spectrum: "yes"
            analysisL = Create Sound from formula: "ecf_aL", 1, 0, frameDuration, sampleRate,
                ... "if col + frameOffset >= 1 and col + frameOffset <= nWet then object[wetL, 1, col + frameOffset] * 0.5 * (1 - cos(2 * pi * (col - 0.5) / frameSamples)) else 0 fi"
            spectrumAL = To Spectrum: "yes"
            analysisR = Create Sound from formula: "ecf_aR", 1, 0, frameDuration, sampleRate,
                ... "if col + frameOffset >= 1 and col + frameOffset <= nWet then object[wetR, 1, col + frameOffset] * 0.5 * (1 - cos(2 * pi * (col - 0.5) / frameSamples)) else 0 fi"
            spectrumAR = To Spectrum: "yes"

            powerObject = Create simple Matrix: "ecf_px", 1, nBinsC, "object[spectrumAD, 1, col]^2 + object[spectrumAD, 2, col]^2"
            sourcePower## = Get all values
            removeObject: powerObject
            powerObject = Create simple Matrix: "ecf_pw", 1, nBinsC,
                ... "0.5 * (object[spectrumAL, 1, col]^2 + object[spectrumAL, 2, col]^2 + object[spectrumAR, 1, col]^2 + object[spectrumAR, 2, col]^2)"
            wetPower## = Get all values
            removeObject: powerObject, analysisL, spectrumAL, analysisR, spectrumAR, spectrumAD
            sourceClass## = mul##(sourcePower##, membA##)
            wetClass## = mul##(wetPower##, membA##)

            holdTotal = 0
            wetTotal = 0
            for k to nClasses
                holdC##[1, k] = max(sourceClass##[1, k], holdC##[1, k] * releaseFactor)
                holdTotal = holdTotal + holdC##[1, k]
                wetTotal = wetTotal + wetClass##[1, k]
            endfor
            if holdTotal > 0 and wetTotal > 0
                for k to nClasses
                    wetShare = wetClass##[1, k] / wetTotal
                    # A class the wet field does not occupy is left alone.
                    targetGain = 1
                    if wetShare > 1e-9
                        similarity = min(1, 1.5 * sqrt((holdC##[1, k] / holdTotal) / wetShare))
                        if adaptive_contour > 0
                            targetGain = 1 - adaptive_contour * (1 - similarity)
                        else
                            targetGain = 1 + adaptive_contour * similarity
                        endif
                    endif
                    gainC##[1, k] = gainSmoothing * gainC##[1, k] + (1 - gainSmoothing) * targetGain
                endfor
            endif
        else
            # Source (near) silent: nothing to compare against. The harmonic
            # memory keeps decaying (it must not freeze across a pause), and
            # every gain relaxes back toward 1 at the same rate.
            contourFramesHeld = contourFramesHeld + 1
            for k to nClasses
                holdC##[1, k] = holdC##[1, k] * releaseFactor
                gainC##[1, k] = 1 - (1 - gainC##[1, k]) * releaseFactor
            endfor
        endif
        removeObject: analysisD

        for k to nClasses
            contourHistory##[k, fr] = gainC##[1, k]
        endfor

        # --- processing (sine window) ---
        binGain## = mul##(gainC##, membT##)
        frameL = Create Sound from formula: "ecf_fL", 1, 0, frameDuration, sampleRate,
            ... "if col + frameOffset >= 1 and col + frameOffset <= nWet then object[wetL, 1, col + frameOffset] * sin(pi * (col - 0.5) / frameSamples) else 0 fi"
        spectrumL = To Spectrum: "yes"
        Formula: "self * (binGain##[1, col] + 1 - membSum##[1, col])"
        resynthL = To Sound
        frameR = Create Sound from formula: "ecf_fR", 1, 0, frameDuration, sampleRate,
            ... "if col + frameOffset >= 1 and col + frameOffset <= nWet then object[wetR, 1, col + frameOffset] * sin(pi * (col - 0.5) / frameSamples) else 0 fi"
        spectrumR = To Spectrum: "yes"
        Formula: "self * (binGain##[1, col] + 1 - membSum##[1, col])"
        resynthR = To Sound

        partFrom = max(0, frameOffset / sampleRate)
        partTo = min(wetDuration, (frameOffset + frameSamples) / sampleRate)
        if partTo > partFrom
            selectObject: contourOutL
            Formula (part): partFrom, partTo, 1, 1,
                ... "self + object[resynthL, 1, col - frameOffset] * sin(pi * (col - frameOffset - 0.5) / frameSamples)"
            selectObject: contourOutR
            Formula (part): partFrom, partTo, 1, 1,
                ... "self + object[resynthR, 1, col - frameOffset] * sin(pi * (col - frameOffset - 0.5) / frameSamples)"
        endif
        removeObject: frameL, spectrumL, frameR, spectrumR, resynthL, resynthR
    endfor

    removeObject: wetL, wetR
    wetL = contourOutL
    wetR = contourOutR
    selectObject: wetL
    Rename: "ecf_wet_L_" + uid$
    energyWetAfterL = Get energy: 0, 0
    selectObject: wetR
    Rename: "ecf_wet_R_" + uid$
    energyWetAfterR = Get energy: 0, 0
    energyWetAfter = energyWetAfterL + energyWetAfterR
    if energyWetBefore > 0 and energyWetAfter > 0
        contourWetChangeDB = 10 * log10(energyWetAfter / energyWetBefore)
    endif
endif

# ---------------------------------------------------------------------------
# 9C. MATERIAL MEMORY
#     A separate temporal-memory branch made from recognisable fragments of
#     the dry source. It enters AFTER the adaptive contour on purpose: a
#     delayed shard remembers the harmony/material that produced it instead
#     of being forced to follow the source's current spectrum. The fragments
#     are not reconvolved. They inherit the IR generation plan but preserve
#     source identity through direct varispeed/reverse playback.
# ---------------------------------------------------------------------------
memoryActive = 0
memoryFragmentsRendered = 0
memoryFragmentsPlanned = 0
memoryBranchRMS = 0
memoryBranchPeak = 0
memoryBranchScale = 0
memoryMaxDelay = 0

if memory > 0 and generations > 1
    activeMemoryGenerations = 0
    for gi from 2 to generations
        if generationAmplitude#[gi] > 0
            activeMemoryGenerations = activeMemoryGenerations + 1
        endif
    endfor
    memoryFragmentsPlanned = activeMemoryGenerations * memory_fragments_per_generation

    if memoryFragmentsPlanned > 0
        selectObject: wetL
        memoryWetSamples = Get number of samples
        memoryWetDuration = Get total duration
        memoryL = Create Sound from formula: "ecf_memory_L_" + uid$, 1, 0, memoryWetDuration, sampleRate, "0"
        memoryR = Create Sound from formula: "ecf_memory_R_" + uid$, 1, 0, memoryWetDuration, sampleRate, "0"

        memoryTime# = zero#(memoryFragmentsPlanned)
        memoryLength# = zero#(memoryFragmentsPlanned)
        memoryPan# = zero#(memoryFragmentsPlanned)
        memoryGeneration# = zero#(memoryFragmentsPlanned)
        memoryReverse# = zero#(memoryFragmentsPlanned)
        memoryEventIndex = 0

        # Source-aware anchor streams. Each stream chooses one locally strong
        # source gesture, then every surviving generation recalls that SAME
        # gesture later in time. This creates an actual descendant trail:
        # recognisable memory -> transformed fragment -> eroded shard.
        memoryAnchor# = zero#(memory_fragments_per_generation)
        memoryAnchorRMS# = zero#(memory_fragments_per_generation)
        maxAnchorLength = max(4 / sampleRate, min(0.45 * sourceDuration, 1.30 * memoryFragmentSeconds))
        for mf to memory_fragments_per_generation
            zoneStart = (mf - 1) / memory_fragments_per_generation * sourceDuration
            zoneEnd = mf / memory_fragments_per_generation * sourceDuration
            zoneWidth = max(4 / sampleRate, zoneEnd - zoneStart)
            probeDuration = min(maxAnchorLength, max(0.008, 0.70 * zoneWidth))
            probeDuration = min(probeDuration, sourceDuration)
            candidateLo = max(0, min(sourceDuration - maxAnchorLength, zoneStart))
            candidateHi = min(sourceDuration - maxAnchorLength, max(candidateLo, zoneEnd - probeDuration))
            bestAnchorStart = candidateLo
            bestAnchorRMS = -1
            for candidateTrial to 5
                if candidateHi > candidateLo + 1 / sampleRate
                    candidateStart = randomUniform(candidateLo, candidateHi)
                else
                    candidateStart = candidateLo
                endif
                selectObject: sourceProc
                candidateRMS = Get root-mean-square: candidateStart, min(sourceDuration, candidateStart + probeDuration)
                if candidateRMS > bestAnchorRMS
                    bestAnchorRMS = candidateRMS
                    bestAnchorStart = candidateStart
                endif
            endfor
            memoryAnchor#[mf] = bestAnchorStart
            memoryAnchorRMS#[mf] = bestAnchorRMS
        endfor

        for gi from 2 to generations
            if generationAmplitude#[gi] > 0
                if generations = 1
                    memoryProgress = 0
                else
                    memoryProgress = (gi - 1) / (generations - 1)
                endif
                memoryMutation = generationMutation#[gi]

                for mf to memory_fragments_per_generation
                    memoryEventIndex = memoryEventIndex + 1

                    # Later generations progressively erode into shorter shards.
                    lengthDraw = randomUniform(0.72, 1.28)
                    erosionFactor = max(0.15, 1 - memory_erosion * memoryProgress)
                    sourceFragLength = memoryFragmentSeconds * erosionFactor * lengthDraw
                    sourceFragLength = max(4 / sampleRate, min(0.45 * sourceDuration, sourceFragLength))

                    # Recall the same source anchor across generations, with
                    # a small mutation-scaled source-position wander.
                    anchorStart = memoryAnchor#[mf]
                    sourcePositionJitter = randomUniform(-0.12, 0.12) * memoryFragmentSeconds * memoryMutation
                    bestStart = max(0, min(sourceDuration - sourceFragLength, anchorStart + sourcePositionJitter))
                    bestRMS = memoryAnchorRMS#[mf]

                    # Inherit the generation's spectral tendency as a shared
                    # varispeed centre. The stereo descendants then diverge around
                    # that centre rather than duplicating one monophonic shard.
                    frequencyTendency = max(1e-6, generationFreqScale#[gi])
                    rateCentre = exp(memory_pitch_mutation * ln(frequencyTendency)
                        ... + randomUniform(-0.28, 0.28) * memoryMutation * memory_pitch_mutation)
                    rateCentre = max(0.55, min(1.85, rateCentre))

                    # Event-relative memory: the descendant occurs after the
                    # source material that generated it. This is the shared
                    # family onset; L/R receive small independent offsets below.
                    baseMemoryDelay = max(0.045, memory_delay_scale * generationOffset#[gi])
                    baseMemoryDelay = min(0.92 * irDuration, baseMemoryDelay)
                    delayJitter = randomUniform(-memoryJitterSeconds, memoryJitterSeconds) * (0.35 + 0.65 * memoryMutation)
                    memoryDelay = max(0.015, baseMemoryDelay + delayJitter)
                    fragmentOnset = bestStart + memoryDelay
                    memoryMaxDelay = max(memoryMaxDelay, memoryDelay)

                    # Stereo divergence is coupled to Spatial width: width 0
                    # remains mono-compatible. Mutation lets later descendants
                    # disagree more strongly than early, recognisable memories.
                    stereoDiv = width * memoryStereoDivergence * (0.30 + 0.70 * memoryMutation)
                    sideSourceRange = 0.28 * sourceFragLength * stereoDiv
                    sideDelayRange = stereoDiv * (0.006 + 0.40 * memoryJitterSeconds)
                    sideRateRange = stereoDiv * (0.025 + 0.12 * memory_pitch_mutation)

                    # Related source positions: same anchor stream, different
                    # nearby pieces of that gesture in L and R.
                    bestStartL = max(0, min(sourceDuration - sourceFragLength,
                        ... bestStart + randomUniform(-sideSourceRange, sideSourceRange)))
                    bestStartR = max(0, min(sourceDuration - sourceFragLength,
                        ... bestStart + randomUniform(-sideSourceRange, sideSourceRange)))

                    # Independent micro-varispeed around the shared generational
                    # tendency. This creates slow beating / spectral disagreement
                    # without turning the channels into unrelated material.
                    rateL = rateCentre * exp(randomUniform(-sideRateRange, sideRateRange))
                    rateR = rateCentre * exp(randomUniform(-sideRateRange, sideRateRange))
                    rateL = max(0.50, min(1.95, rateL))
                    rateR = max(0.50, min(1.95, rateR))
                    fragmentDurationL = sourceFragLength / rateL
                    fragmentDurationR = sourceFragLength / rateR

                    # Independent channel onsets around the same memory event.
                    fragmentOnsetL = max(bestStartL + 0.004,
                        ... fragmentOnset + randomUniform(-sideDelayRange, sideDelayRange))
                    fragmentOnsetR = max(bestStartR + 0.004,
                        ... fragmentOnset + randomUniform(-sideDelayRange, sideDelayRange))

                    if fragmentOnsetL < memoryWetDuration - 4 / sampleRate
                        fragmentDurationL = min(fragmentDurationL, memoryWetDuration - fragmentOnsetL - 2 / sampleRate)
                    else
                        fragmentDurationL = 0
                    endif
                    if fragmentOnsetR < memoryWetDuration - 4 / sampleRate
                        fragmentDurationR = min(fragmentDurationR, memoryWetDuration - fragmentOnsetR - 2 / sampleRate)
                    else
                        fragmentDurationR = 0
                    endif

                    if fragmentDurationL > 4 / sampleRate and fragmentDurationR > 4 / sampleRate and bestRMS > 0
                        # Reversal is still generation-related, but one side can
                        # break away at high divergence. A structurally reversed
                        # IR generation keeps both descendants reversed.
                        reverseProbability = memory_reverse_probability * (0.35 + 0.65 * memoryMutation)
                        if generationReversed#[gi]
                            reverseFragmentL = 1
                            reverseFragmentR = 1
                        else
                            reverseFragmentL = if randomUniform(0, 1) < reverseProbability then 1 else 0 fi
                            reverseFragmentR = reverseFragmentL
                            if randomUniform(0, 1) < 0.55 * stereoDiv * reverseProbability
                                reverseFragmentR = 1 - reverseFragmentR
                            endif
                        endif

                        sourceEndL = bestStartL + sourceFragLength
                        sourceEndR = bestStartR + sourceFragLength
                        if reverseFragmentL
                            fragmentL = Create Sound from formula: "ecf_memory_fragment_L_" + uid$, 1, 0, fragmentDurationL, sampleRate,
                                ... "object(sourceProc, sourceEndL - x * rateL) * (sin(pi * x / fragmentDurationL) ^ 0.82)"
                        else
                            fragmentL = Create Sound from formula: "ecf_memory_fragment_L_" + uid$, 1, 0, fragmentDurationL, sampleRate,
                                ... "object(sourceProc, bestStartL + x * rateL) * (sin(pi * x / fragmentDurationL) ^ 0.82)"
                        endif
                        if reverseFragmentR
                            fragmentR = Create Sound from formula: "ecf_memory_fragment_R_" + uid$, 1, 0, fragmentDurationR, sampleRate,
                                ... "object(sourceProc, sourceEndR - x * rateR) * (sin(pi * x / fragmentDurationR) ^ 0.82)"
                        else
                            fragmentR = Create Sound from formula: "ecf_memory_fragment_R_" + uid$, 1, 0, fragmentDurationR, sampleRate,
                                ... "object(sourceProc, bestStartR + x * rateR) * (sin(pi * x / fragmentDurationR) ^ 0.82)"
                        endif

                        # The generation still owns the event's broad spatial
                        # location. Independent channel gain perturbations and
                        # distinct content create an internal stereo life inside
                        # that location, instead of simple amplitude panning.
                        fragmentGain = generationAmplitude#[gi] * randomUniform(0.62, 1.24)
                        fragmentPan = generationPan#[gi] + width * memoryMutation * randomUniform(-0.20, 0.20)
                        fragmentPan = max(-1, min(1, fragmentPan))
                        sideGainL = exp(randomUniform(-0.16, 0.16) * stereoDiv)
                        sideGainR = exp(randomUniform(-0.16, 0.16) * stereoDiv)
                        fragmentGainL = fragmentGain * sqrt(0.5 * (1 - fragmentPan)) * sideGainL
                        fragmentGainR = fragmentGain * sqrt(0.5 * (1 + fragmentPan)) * sideGainR

                        selectObject: memoryL
                        Formula (part): fragmentOnsetL, fragmentOnsetL + fragmentDurationL, 1, 1,
                            ... "self + fragmentGainL * object(fragmentL, x - fragmentOnsetL)"
                        selectObject: memoryR
                        Formula (part): fragmentOnsetR, fragmentOnsetR + fragmentDurationR, 1, 1,
                            ... "self + fragmentGainR * object(fragmentR, x - fragmentOnsetR)"
                        removeObject: fragmentL, fragmentR

                        memoryFragmentsRendered = memoryFragmentsRendered + 1
                        memoryTime#[memoryFragmentsRendered] = 0.5 * (fragmentOnsetL + fragmentOnsetR)
                        memoryLength#[memoryFragmentsRendered] = 0.5 * (fragmentDurationL + fragmentDurationR)
                        memoryPan#[memoryFragmentsRendered] = fragmentPan
                        memoryGeneration#[memoryFragmentsRendered] = gi
                        memoryReverse#[memoryFragmentsRendered] = max(reverseFragmentL, reverseFragmentR)
                    endif
                    endif
                endfor
            endif
        endfor

        # Normalize ONLY the memory branch to a preset-relative RMS target.
        # This is not final-output normalization: Material memory remains a
        # meaningful energy control and the convolution branch is untouched.
        if memoryFragmentsRendered > 0
            selectObject: memoryL
            memoryRMSL = Get root-mean-square: 0, 0
            memoryPeakL = Get absolute extremum: 0, 0, "None"
            selectObject: memoryR
            memoryRMSR = Get root-mean-square: 0, 0
            memoryPeakR = Get absolute extremum: 0, 0, "None"
            memoryRawRMS = sqrt(0.5 * (memoryRMSL^2 + memoryRMSR^2))
            memoryRawPeak = max(memoryPeakL, memoryPeakR)
            targetMemoryRMS = sourceRMS * memory * memory_energy_factor
            if memoryRawRMS > 0
                memoryBranchScale = targetMemoryRMS / memoryRawRMS
                if memoryRawPeak > 0
                    memoryBranchScale = min(memoryBranchScale, 0.80 / memoryRawPeak)
                endif
                memoryBranchRMS = memoryRawRMS * memoryBranchScale
                memoryBranchPeak = memoryRawPeak * memoryBranchScale

                selectObject: wetL
                Formula: "self + memoryBranchScale * object[memoryL, 1, col]"
                selectObject: wetR
                Formula: "self + memoryBranchScale * object[memoryR, 1, col]"
                memoryActive = 1
            endif
        endif
        removeObject: memoryL, memoryR
    endif
endif

# ---------------------------------------------------------------------------
# 10. WET / DRY MIX
#     Dry is unprocessed and placed by Dry pan (0 = centre, v0.3 level).
# ---------------------------------------------------------------------------
dryGainL = sqrt(1 - dry_pan)
dryGainR = sqrt(1 + dry_pan)
selectObject: wetL
Formula: "wet*self + (1-wet)*dryGainL*(if col <= sourceSamples then object[sourceProc,1,col] else 0 fi)"
selectObject: wetR
Formula: "wet*self + (1-wet)*dryGainR*(if col <= sourceSamples then object[sourceProc,1,col] else 0 fi)"

# ---------------------------------------------------------------------------
# 11. STEREO OUTPUT + STEREO MEASUREMENTS
# ---------------------------------------------------------------------------
selectObject: wetL
energyOutL = Get energy: 0, 0
selectObject: wetR
energyOutR = Get energy: 0, 0
selectObject: wetL
outDuration = Get total duration
outSum = Create Sound from formula: "ecf_osum_" + uid$, 1, 0, outDuration, sampleRate,
    ... "object[wetL,1,col] + object[wetR,1,col]"
energyOutSum = Get energy: 0, 0
outDiff = Create Sound from formula: "ecf_odiff_" + uid$, 1, 0, outDuration, sampleRate,
    ... "object[wetL,1,col] - object[wetR,1,col]"
energyOutDiff = Get energy: 0, 0
removeObject: outSum, outDiff

outputCorrelation = undefined
monoFoldLossDB = undefined
if energyOutL > 0 and energyOutR > 0
    outputCorrelation = 0.25 * (energyOutSum - energyOutDiff) / sqrt(energyOutL * energyOutR)
    if energyOutSum > 0
        monoFoldLossDB = 10 * log10(energyOutSum / (2 * (energyOutL + energyOutR)))
    endif
endif

selectObject: wetL
plusObject: wetR
Combine to stereo
outputSound = selected("Sound")
Rename: sourceName$ + "_EvolvingConv_" + characterName$

selectObject: outputSound
if normalize_output
    outputPeak = Get absolute extremum: 0, 0, "None"
    if outputPeak > 0.95
        Scale peak: 0.95
    endif
endif

finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
outputDuration = Get total duration

trajectoryName$ = trajectory$
contourModeName$ = if contour_mode = 1 then "pitch class" else "spectral" fi
spatialName$ = spatial_mode$
survivalName$ = survival_shape$

# ---------------------------------------------------------------------------
# 12. VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
#     Per panel: Font size -> Select inner viewport -> Axes -> data ->
#     re-select + Axes -> Draw inner box -> captions.
# ---------------------------------------------------------------------------
if draw_visualization
    Erase all
    ys = 0
    if contourActive
        ys = 1.30
    endif
    Font size: 12
    Select outer viewport: 0, 8, 0, 6.80 + ys

    sourceDisplay$ = replace$(sourceName$, "_", "\_ ", 0)

    selectObject: outputSound
    vizOutput = Convert to mono
    Rename: "ecf_viz_output_" + uid$

    selectObject: sourceProc
    vizSourcePeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizOutput
    vizOutputPeak = Get absolute extremum: 0, 0, "None"
    sharedVizAmp = max(0.01, max(vizSourcePeak, vizOutputPeak)) * 1.12

    # Title block.
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Evolving Convolution Field v0.7##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... sourceDisplay$ + " | " + characterDisplay$ + " | " + trajectoryName$
        ... + " | " + spatialName$ + " | " + survivalName$ + " | " + string$(generations) + " generations"
        ... + " | contour " + fixed$(adaptive_contour, 2)

    # Source waveform.
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.67, 1.35
    Axes: 0, sourceDuration, -sharedVizAmp, sharedVizAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, sourceDuration, -sharedVizAmp, sharedVizAmp
    selectObject: sourceProc
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, sourceDuration, -sharedVizAmp, sharedVizAmp, "no", "Curve"
    Select inner viewport: 0.60, 7.70, 0.67, 1.35
    Axes: 0, sourceDuration, -sharedVizAmp, sharedVizAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, sourceDuration, 0
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.60, 7.70, 0.67, 1.35
    Axes: 0, sourceDuration, -sharedVizAmp, sharedVizAmp
    Text left: "no", "Source"

    # Processed output waveform.
    Select inner viewport: 0.60, 7.70, 1.52, 2.20
    Axes: 0, outputDuration, -sharedVizAmp, sharedVizAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, -sharedVizAmp, sharedVizAmp
    selectObject: vizOutput
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, outputDuration, -sharedVizAmp, sharedVizAmp, "no", "Curve"
    Select inner viewport: 0.60, 7.70, 1.52, 2.20
    Axes: 0, outputDuration, -sharedVizAmp, sharedVizAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outputDuration, 0
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.60, 7.70, 1.52, 2.20
    Axes: 0, outputDuration, -sharedVizAmp, sharedVizAmp
    Text left: "no", "Output"
    Text bottom: "no", "Time (s)  0 - " + fixed$(outputDuration, 2)

    # -----------------------------------------------------------------------
    # ADAPTIVE CONTOUR STRIP: attenuation per class over time (dark = removed).
    # -----------------------------------------------------------------------
    if contourActive
        contourViz = Create Matrix: "ecf_contour_viz_" + uid$,
            ... -0.5 * hopDuration, (contourFrames - 0.5) * hopDuration, contourFrames, hopDuration, 0,
            ... 0.5, nClasses + 0.5, nClasses, 1, 1,
            ... "min(20, -20 * log10(max(0.001, contourHistory##[row, col])))"
        Font size: 6
        Select inner viewport: 0.60, 7.70, 2.72, 3.72
        Axes: 0, outputDuration, 0.5, nClasses + 0.5
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, outputDuration, 0.5, nClasses + 0.5
        selectObject: contourViz
        Paint image: 0, min(outputDuration, (contourFrames - 0.5) * hopDuration), 0.5, nClasses + 0.5, 0, 20
        removeObject: contourViz
        Select inner viewport: 0.60, 7.70, 2.72, 3.72
        Axes: 0, outputDuration, 0.5, nClasses + 0.5
        Colour: "Black"
        if contour_mode = 1
            # Whole-tone labels every second row (# needs the "\# " escape).
            One mark left: 1, "no", "yes", "no", "C"
            One mark left: 3, "no", "yes", "no", "D"
            One mark left: 5, "no", "yes", "no", "E"
            One mark left: 7, "no", "yes", "no", "F\# "
            One mark left: 9, "no", "yes", "no", "G\# "
            One mark left: 11, "no", "yes", "no", "A\# "
        else
            for markIndex to 3
                markHz = 100 * 10 ^ (markIndex - 1)
                markRow = 24 * log2(markHz / contourLow) + 1
                if markRow <= nClasses
                    One mark left: markRow, "no", "yes", "no", string$(markHz)
                endif
            endfor
        endif
        Select inner viewport: 0.60, 7.70, 2.72, 3.72
        Axes: 0, outputDuration, 0.5, nClasses + 0.5
        Draw inner box
        Font size: 7
        Select inner viewport: 0.60, 7.70, 2.72, 3.72
        Axes: 0, outputDuration, 0.5, nClasses + 0.5
        contourCaption$ = "Adaptive contour " + fixed$(adaptive_contour, 2) + " - " + contourModeName$
            ... + " - attenuation 0 to 20 dB (dark = removed)"
        Text top: "no", contourCaption$
    endif

    # -----------------------------------------------------------------------
    # LEFT PROCESS PANEL: survival, mutation, reversed generations.
    # -----------------------------------------------------------------------
    Font size: 6
    Select inner viewport: 0.62, 3.78, 2.72 + ys, 3.79 + ys
    Axes: 0.5, generations + 0.5, -0.16, 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0.5, generations + 0.5, -0.16, 1.12
    Colour: "{0.86, 0.86, 0.86}"
    Draw line: 0.5, 0, generations + 0.5, 0
    Dotted line
    Draw line: 0.5, 0.5, generations + 0.5, 0.5
    Draw line: 0.5, 1.0, generations + 0.5, 1.0
    Solid line

    # Reversed generations: shaded columns behind the curves.
    for genViz to generations
        if generationReversed#[genViz] and generationAmplitude#[genViz] > 0
            Paint rectangle: "{0.93, 0.86, 0.86}", genViz - 0.42, genViz + 0.42, 0, 1.12
        endif
    endfor

    Colour: "{0.45, 0.45, 0.45}"
    for genViz to generations
        Draw line: genViz, -0.03, genViz, 0
        if generations <= 12 or genViz = 1 or genViz = generations or genViz mod 2 = 0
            Text: genViz, "centre", -0.095, "half", string$(genViz)
        endif
    endfor

    Line width: 2
    Colour: "{0.80, 0.60, 0.20}"
    if generations > 1
        for genViz from 2 to generations
            Draw line: genViz - 1, generationAmplitude#[genViz - 1], genViz, generationAmplitude#[genViz]
        endfor
    endif
    Colour: "{0.25, 0.45, 0.75}"
    if generations > 1
        for genViz from 2 to generations
            Draw line: genViz - 1, generationMutation#[genViz - 1], genViz, generationMutation#[genViz]
        endfor
    endif
    Line width: 1

    # Direct labels placed before the frame is disturbed.
    Colour: "{0.80, 0.60, 0.20}"
    Text: generations + 0.45, "right", 1.07, "half", "survival " + fixed$(generationAmplitude#[generations], 2)
    Colour: "{0.25, 0.45, 0.75}"
    Text: generations + 0.45, "right", 0.95, "half", "mutation " + fixed$(generationMutation#[generations], 2)
    if reversedTotal > 0
        Colour: "{0.62, 0.35, 0.35}"
        Text: 0.55, "left", 1.07, "half", "shaded = reversed"
    endif

    Colour: "Black"
    Select inner viewport: 0.62, 3.78, 2.72 + ys, 3.79 + ys
    Axes: 0.5, generations + 0.5, -0.16, 1.12
    Draw inner box
    Font size: 7
    Select inner viewport: 0.62, 3.78, 2.72 + ys, 3.79 + ys
    Axes: 0.5, generations + 0.5, -0.16, 1.12
    Text top: "no", "Generational evolution"
    Text left: "no", "Relative amount"
    Text bottom: "no", "IR generation"

    # -----------------------------------------------------------------------
    # RIGHT PROCESS PANEL: partial field, generation pan, measured coherence.
    # -----------------------------------------------------------------------
    vizMaxMs = max(1, irDuration * 1000)
    Font size: 6
    Select inner viewport: 4.47, 7.67, 2.72 + ys, 3.79 + ys
    Axes: 0, vizMaxMs, -1.12, 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizMaxMs, -1.12, 1.12
    Colour: "{0.86, 0.86, 0.86}"
    Dotted line
    Draw line: 0, 0, vizMaxMs, 0
    Draw line: 0, -1, vizMaxMs, -1
    Draw line: 0, 1, vizMaxMs, 1
    Solid line

    # Partials: colour runs lowest {0.20, 0.40, 0.80} -> highest {0.85, 0.45, 0.15}
    # drawn partial; dot size follows partial amplitude.
    maxPartialAmp = 0
    minLog = 1
    maxLog = 0
    for k to nPartialsViz
        maxPartialAmp = max(maxPartialAmp, partialAmp#[k])
        minLog = min(minLog, partialLogPos#[k])
        maxLog = max(maxLog, partialLogPos#[k])
    endfor
    logSpan = max(1e-6, maxLog - minLog)
    for k to nPartialsViz
        lp = (partialLogPos#[k] - minLog) / logSpan
        colourR = 0.20 + 0.65 * lp
        colourG = 0.40 + 0.05 * lp
        colourB = 0.80 - 0.65 * lp
        dotRadius = 0.25 + 0.55 * sqrt(partialAmp#[k] / max(1e-12, maxPartialAmp))
        Paint circle (mm): "{" + fixed$(colourR, 2) + ", " + fixed$(colourG, 2) + ", " + fixed$(colourB, 2) + "}",
            ... min(vizMaxMs, partialTime#[k] * 1000), partialPan#[k], dotRadius
    endfor

    # Generation trajectory (onset positions).
    Colour: "{0.35, 0.60, 0.40}"
    Line width: 2
    if generations > 1
        for genViz from 2 to generations
            Draw line: generationOffset#[genViz - 1] * 1000, generationPan#[genViz - 1],
                ... generationOffset#[genViz] * 1000, generationPan#[genViz]
        endfor
    endif

    # Measured coherence per generation window.
    Colour: "{0.55, 0.30, 0.60}"
    previousCohValid = 0
    for genViz to generations
        thisCoh = generationMeasuredCoh#[genViz]
        if thisCoh <> undefined
            thisTimeMs = generationOffset#[genViz] * 1000
            if previousCohValid
                Draw line: previousTimeMs, previousCoh, thisTimeMs, thisCoh
            endif
            Paint circle (mm): "{0.55, 0.30, 0.60}", thisTimeMs, thisCoh, 0.60
            previousTimeMs = thisTimeMs
            previousCoh = thisCoh
            previousCohValid = 1
        endif
    endfor
    Line width: 1

    Colour: "{0.35, 0.60, 0.40}"
    Text: vizMaxMs * 0.99, "right", -0.93, "half", "generation pan"
    Colour: "{0.55, 0.30, 0.60}"
    Text: vizMaxMs * 0.99, "right", 0.93, "half", "measured L/R coherence"

    Colour: "Black"
    Select inner viewport: 4.47, 7.67, 2.72 + ys, 3.79 + ys
    Axes: 0, vizMaxMs, -1.12, 1.12
    Draw inner box
    Font size: 7
    Select inner viewport: 4.47, 7.67, 2.72 + ys, 3.79 + ys
    Axes: 0, vizMaxMs, -1.12, 1.12
    Text top: "no", "Partial field, trajectory and coherence"
    Text left: "no", "Pan  L - C - R  /  coherence"
    Text bottom: "no", "IR time (ms)  0 - " + fixed$(vizMaxMs, 0)

    # -----------------------------------------------------------------------
    # L/R IR PANELS
    # -----------------------------------------------------------------------
    selectObject: kernelL
    irPeakVizL = Get absolute extremum: 0, 0, "None"
    selectObject: kernelR
    irPeakVizR = Get absolute extremum: 0, 0, "None"
    irSharedAmp = max(0.001, max(irPeakVizL, irPeakVizR)) * 1.10

    Font size: 7
    Select inner viewport: 0.62, 3.78, 4.32 + ys, 5.30 + ys
    Axes: 0, irDuration, -irSharedAmp, irSharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, irDuration, -irSharedAmp, irSharedAmp
    selectObject: kernelL
    Colour: "{0.45, 0.55, 0.72}"
    Draw: 0, irDuration, -irSharedAmp, irSharedAmp, "no", "Curve"
    Select inner viewport: 0.62, 3.78, 4.32 + ys, 5.30 + ys
    Axes: 0, irDuration, -irSharedAmp, irSharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, irDuration, 0
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.62, 3.78, 4.32 + ys, 5.30 + ys
    Axes: 0, irDuration, -irSharedAmp, irSharedAmp
    Text top: "no", "Generated IR - Left"
    Text left: "no", "Amplitude"
    Text bottom: "no", "Time (s)  0 - " + fixed$(irDuration, 3)

    Select inner viewport: 4.47, 7.67, 4.32 + ys, 5.30 + ys
    Axes: 0, irDuration, -irSharedAmp, irSharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, irDuration, -irSharedAmp, irSharedAmp
    selectObject: kernelR
    Colour: "{0.68, 0.48, 0.48}"
    Draw: 0, irDuration, -irSharedAmp, irSharedAmp, "no", "Curve"
    Select inner viewport: 4.47, 7.67, 4.32 + ys, 5.30 + ys
    Axes: 0, irDuration, -irSharedAmp, irSharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, irDuration, 0
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.47, 7.67, 4.32 + ys, 5.30 + ys
    Axes: 0, irDuration, -irSharedAmp, irSharedAmp
    Text top: "no", "Generated IR - Right"
    Text left: "no", "Amplitude"
    Text bottom: "no", "Time (s)  0 - " + fixed$(irDuration, 3)

    # Summary strip.
    Font size: 6
    Select inner viewport: 0.60, 7.70, 5.82 + ys, 6.56 + ys
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    spacingNote$ = ""
    if spacingWasCapped
        spacingNote$ = " (capped)"
    endif
    Text: 0.02, "left", 0.80, "half",
        ... "##" + characterDisplay$ + "##  | " + string$(generations) + " generations"
        ... + " | spacing " + fixed$(effectiveSpacingMs, 1) + " ms" + spacingNote$
        ... + " | curvature " + fixed$(spacing_curvature, 2)
        ... + " | decay " + fixed$(generation_decay, 2) + " | " + survivalName$
        ... + " | reversed " + string$(reversedTotal) + " | silent " + string$(silentTotal)
    Text: 0.02, "left", 0.50, "half",
        ... "Transformation " + fixed$(amount, 2) + " | Wet " + fixed$(wet, 2)
        ... + " | memory " + fixed$(memory, 2) + " / " + string$(memoryFragmentsRendered) + " fragments"
        ... + " | width " + fixed$(width, 2) + " | mutation " + fixed$(mutation, 2)
        ... + " | " + spatialName$ + " spread " + fixed$(spreadUsed, 2)
        ... + " | motion " + fixed$(motion_depth, 2) + " | dry pan " + fixed$(dry_pan, 2)
    cohNote$ = "coherence target " + fixed$(coherence_start, 2) + " to " + fixed$(coherence_end, 2)
    if outputCorrelation <> undefined
        cohNote$ = cohNote$ + " | output L/R correlation " + fixed$(outputCorrelation, 2)
    endif
    if monoFoldLossDB <> undefined
        cohNote$ = cohNote$ + " | mono fold-down " + fixed$(monoFoldLossDB, 1) + " dB"
    endif
    if contourActive
        cohNote$ = cohNote$ + " | contour " + fixed$(adaptive_contour, 2) + " " + contourModeName$
            ... + " wet " + fixed$(contourWetChangeDB, 1) + " dB"
    endif
    Text: 0.02, "left", 0.20, "half",
        ... cohNote$ + " | IR " + fixed$(irDuration * 1000, 0) + " ms"
    Select inner viewport: 0.60, 7.70, 5.82 + ys, 6.56 + ys
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    removeObject: vizOutput

    # Full-canvas selection for reliable Save as PNG/EPS and clipboard export.
    Select outer viewport: 0, 8, 0, 6.80 + ys
endif

# ---------------------------------------------------------------------------
# 13. CLEANUP / OPTIONAL KERNEL RETENTION
# ---------------------------------------------------------------------------
removeObject: wetL, wetR, sourceProc

if keep_kernels
    selectObject: kernelL
    Rename: sourceName$ + "_IR_Field_L_" + characterName$
    selectObject: kernelR
    Rename: sourceName$ + "_IR_Field_R_" + characterName$
else
    removeObject: kernelL, kernelR
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 14. REPORT / PLAY / FINAL SELECTION
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "================================================"
writeInfoLine: "  EVOLVING CONVOLUTION FIELD v0.7"
writeInfoLine: "================================================"
appendInfoLine: "Source: ", sourceName$
appendInfoLine: "Character: ", characterDisplay$
appendInfoLine: "Trajectory: ", trajectoryName$
appendInfoLine: "Spatial mode: ", spatialName$, " (spread ", fixed$(spreadUsed, 2), ")"
appendInfoLine: "Survival shape: ", survivalName$
appendInfoLine: "Transformation amount: ", fixed$(amount, 2)
appendInfoLine: "Wet mix: ", fixed$(wet, 2), " | dry pan ", fixed$(dry_pan, 2)
if memoryActive
    appendInfoLine: "Material memory: ", fixed$(memory, 2), " | stereo divergence ", fixed$(memoryStereoDivergence, 2), " | fragments ", memoryFragmentsRendered,
        ... " / ", memoryFragmentsPlanned, " | branch RMS ", fixed$(memoryBranchRMS, 4),
        ... " | peak ", fixed$(memoryBranchPeak, 4), " | max delay ", fixed$(memoryMaxDelay * 1000, 0), " ms"
    appendInfoLine: "  fragment base ", fixed$(memory_fragment_ms, 0), " ms | per generation ", memory_fragments_per_generation,
        ... " | erosion ", fixed$(memory_erosion, 2), " | pitch mutation ", fixed$(memory_pitch_mutation, 2),
        ... " | reverse ", fixed$(memory_reverse_probability, 2)
else
    appendInfoLine: "Material memory: off"
endif
appendInfoLine: "Spatial width: ", fixed$(width, 2)
appendInfoLine: "IR generations: ", generations, " (reversed ", reversedTotal, ", silent ", silentTotal, ")"
if spacingWasCapped
    appendInfoLine: "Generation spacing: ", fixed$(effectiveSpacingMs, 2), " ms - CAPPED from ",
        ... fixed$(generation_spacing_ms, 1), " ms (requested IR ", fixed$(requestedIRDuration, 2),
        ... " s > max ", fixed$(max_IR_duration, 1), " s)"
else
    appendInfoLine: "Generation spacing: ", fixed$(effectiveSpacingMs, 1), " ms"
endif
appendInfoLine: "Spacing curvature: ", fixed$(spacing_curvature, 2)
appendInfoLine: "Generation decay: ", fixed$(generation_decay, 2)
appendInfoLine: "Generational mutation: ", fixed$(mutation, 2)
appendInfoLine: "Motion depth: ", fixed$(motion_depth, 2)
appendInfoLine: "Coherence target: ", fixed$(coherence_start, 2), " -> ", fixed$(coherence_end, 2),
    ... " (effective at width ", fixed$(width, 2), ": ", fixed$(generationCoherence#[1], 2), " -> ",
    ... fixed$(generationCoherence#[generations], 2), ")"
measuredLine$ = "Measured L/R coherence per generation:"
for gi to generations
    if generationMeasuredCoh#[gi] = undefined
        measuredLine$ = measuredLine$ + " --"
    else
        measuredLine$ = measuredLine$ + " " + fixed$(generationMeasuredCoh#[gi], 2)
    endif
endfor
appendInfoLine: measuredLine$
if contourActive
    appendInfoLine: "Adaptive contour: ", fixed$(adaptive_contour, 2), " (", contourModeName$,
        ... ", memory ", fixed$(contour_memory_ms, 0), " ms, lookahead ", fixed$(contour_lookahead_ms, 0), " ms)"
    appendInfoLine: "  frames ", contourFrames, " (", fixed$(frameSamples / sampleRate * 1000, 0), " ms), source-silent ",
        ... contourFramesHeld, ", wet energy change ", fixed$(contourWetChangeDB, 2), " dB"
else
    appendInfoLine: "Adaptive contour: off"
endif
appendInfoLine: "Generated IR duration: ", fixed$(irDuration, 3), " s"
appendInfoLine: "Active resonant components: ", activeModesTotal
appendInfoLine: "Broadband micro-impulses: ", activePulsesTotal
appendInfoLine: "Output: stereo"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: "RMS: ", fixed$(finalRMS, 4)
if outputCorrelation <> undefined
    appendInfoLine: "Output L/R correlation: ", fixed$(outputCorrelation, 3)
endif
if monoFoldLossDB <> undefined
    appendInfoLine: "Mono fold-down: ", fixed$(monoFoldLossDB, 2), " dB (0 = coherent, -3 = uncorrelated)"
endif
if sourceChannels > 1
    appendInfoLine: "Input handling: multichannel source collapsed to mono; the IR field rebuilt the stereo image."
endif
if keep_kernels
    appendInfoLine: "Generated L/R IR fields were kept for inspection."
endif
appendInfoLine: "================================================"

selectObject: outputSound
if play_result
    Play
endif

selectObject: outputSound
