# ============================================================
# Praat AudioTools - Genetic_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Genetic algorithm that evolves segment-recombination parameters
#   to produce a target-length recomposition of an input sound.
#   Each genome encodes 8 parameters controlling segmentation grain,
#   bias toward short/long segments, reorder probability, crossfade,
#   and silence insertion. Fitness rewards a preset-dependent
#   combination of onset density, spectral similarity to input, and
#   envelope regularity.
#
# Changelog v1.2 (2026):
#   - FIX: Best-ever tracking used to store genome INDEX only, which
#     aliased to a different genome after evolution. Now snapshots
#     all 8 parameter values so the final render reproduces the true
#     best-ever candidate, not whatever sits at that slot last.
#   - FIX: Fitness function was dominated by a near-constant term
#     (sd/rms ratio is always ~1 for any audio; mean/rms is always
#     ~0 for AC-coupled audio) plus a voiced-frame term that
#     penalised exactly the aesthetics most presets aimed for
#     (glitch, fragmentation). Replaced with three measurable
#     quantities — onset density, spectral similarity to input,
#     envelope regularity — combined with preset-specific weights.
#   - FIX: Added elitism. The best-ever genome is forced into the
#     next generation, preventing loss through tournament selection.
#   - VIZ: Added segmentation panel showing input waveform with
#     segment boundaries as ticks, plus a playback-order strip
#     showing which original-time each output chunk came from.
#   - VIZ: Fitness curve now shows min/mean/max per generation,
#     not just the best, so population convergence is visible.
#   - DOC: Preset-to-fitness-weight mapping documented inline.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
soundName$ = selected$("Sound")

form GA Segment Recombination v1.2
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Subtle Texture
        option Granular Shimmer
        option Glitch / Stutter
        option Extreme Fragmentation
        option Rhythmic Loops
    comment === Output ===
    positive Target_duration_s 8.0
    comment === Effect Strength (1-10) ===
    positive Effect_strength 6
    comment === Quality / Speed ===
    positive Pop_size 10
    positive Generations 10
    positive Fitness_stride 3
    comment === Segmentation (ms) ===
    positive Min_seg_ms 20
    positive Max_seg_ms 180
    comment === Texture ===
    positive Max_crossfade_ms 6
    real Max_silence_prob 0.25
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

###############################################################################
# APPLY PRESET
#
# Each preset also specifies how the GA's fitness should weight the three
# measurable quantities:
#   w_onset    — reward outputs with high onset density (sharp intensity
#                jumps per second). Good for glitch/fragmentation aesthetics.
#   w_spectral — reward outputs whose spectrum resembles the input's. Good
#                for subtle/coherent aesthetics.
#   w_regular  — reward outputs with high envelope autocorrelation (i.e.,
#                repeating rhythmic patterns). Good for loop aesthetics.
# The weights sum to 1 and drive what the GA actually selects for.
###############################################################################

if preset = 2
    # SubtleTexture: gentle, keep the input's spectral character.
    effect_strength = 3
    pop_size = 8
    generations = 8
    fitness_stride = 4
    max_crossfade_ms = 8
    max_silence_prob = 0.15
    presetName$ = "SubtleTexture"
    w_onset = 0.10
    w_spectral = 0.70
    w_regular = 0.20
elsif preset = 3
    # GranularShimmer: spectral activity + some onset structure.
    effect_strength = 5
    pop_size = 12
    generations = 12
    fitness_stride = 3
    max_crossfade_ms = 12
    max_silence_prob = 0.20
    presetName$ = "GranularShimmer"
    w_onset = 0.35
    w_spectral = 0.40
    w_regular = 0.25
elsif preset = 4
    # GlitchStutter: maximum onset density, minimal coherence constraint.
    effect_strength = 8
    pop_size = 10
    generations = 10
    fitness_stride = 2
    max_crossfade_ms = 3
    max_silence_prob = 0.45
    presetName$ = "GlitchStutter"
    w_onset = 0.70
    w_spectral = 0.10
    w_regular = 0.20
elsif preset = 5
    # ExtremeFrag: all-in on fragmentation.
    effect_strength = 10
    min_seg_ms = 10
    max_seg_ms = 80
    pop_size = 15
    generations = 15
    fitness_stride = 2
    max_crossfade_ms = 2
    max_silence_prob = 0.50
    presetName$ = "ExtremeFrag"
    w_onset = 0.80
    w_spectral = 0.05
    w_regular = 0.15
elsif preset = 6
    # RhythmicLoops: strong repetition, moderate onsets.
    effect_strength = 6
    min_seg_ms = 50
    max_seg_ms = 250
    pop_size = 12
    generations = 12
    fitness_stride = 3
    max_crossfade_ms = 8
    max_silence_prob = 0.10
    presetName$ = "RhythmicLoops"
    w_onset = 0.25
    w_spectral = 0.25
    w_regular = 0.50
else
    presetName$ = "Custom"
    w_onset = 0.34
    w_spectral = 0.33
    w_regular = 0.33
endif

###############################################################################
# SETUP
###############################################################################

clearinfo
writeInfoLine: "=== GA Segment Recomposer v1.2 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Target duration: ", target_duration_s, " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Effect strength: ", effect_strength, "/10"
appendInfoLine: "Fitness weights: onset=", fixed$(w_onset, 2),
    ... " spectral=", fixed$(w_spectral, 2),
    ... " regular=", fixed$(w_regular, 2)
appendInfoLine: ""

selectObject: inputSound
inputDuration = Get total duration
inputSampleRate = Get sampling frequency
inputChannels = Get number of channels

appendInfoLine: "Original duration: ", fixed$(inputDuration, 2), " s"
appendInfoLine: "Sample rate: ", inputSampleRate, " Hz"
appendInfoLine: ""

###############################################################################
# COMPUTE REFERENCE FEATURES OF INPUT (once, reused for fitness)
#
# spectralSim fitness component compares a candidate's spectral centroid
# and spread to the INPUT's. We compute the input's reference values
# here, once, rather than per-fitness-call.
###############################################################################

selectObject: inputSound
inputForRefFeats = Copy: "input_feats_tmp"
# Convert to mono for feature consistency
if inputChannels > 1
    refMono = Convert to mono
    removeObject: inputForRefFeats
else
    refMono = inputForRefFeats
endif

selectObject: refMono
refSpec = To Spectrum: "yes"
refCentroid = Get centre of gravity: 2
refSpread = Get standard deviation: 2
removeObject: refSpec

# Reference intensity envelope for onset-density scaling
selectObject: refMono
refIntensity = To Intensity: 100, 0, "yes"
refIntMean = Get mean: 0, 0, "dB"
refIntMin = Get minimum: 0, 0, "Parabolic"
refIntMax = Get maximum: 0, 0, "Parabolic"
removeObject: refIntensity
removeObject: refMono

appendInfoLine: "Input reference features:"
appendInfoLine: "  Spectral centroid: ", fixed$(refCentroid, 1), " Hz"
appendInfoLine: "  Spectral spread: ", fixed$(refSpread, 1), " Hz"
appendInfoLine: "  Intensity: mean=", fixed$(refIntMean, 1),
    ... " min=", fixed$(refIntMin, 1), " max=", fixed$(refIntMax, 1), " dB"
appendInfoLine: ""

###############################################################################
# EFFECT STRENGTH SCALING
###############################################################################

strength_factor = effect_strength / 10.0

eff_min_seg_ms = min_seg_ms * (1 - strength_factor * 0.3)
eff_max_seg_ms = max_seg_ms * (1 + strength_factor * 0.3)
eff_max_crossfade_ms = max_crossfade_ms * (1 + strength_factor * 0.5)
eff_silence_prob = max_silence_prob * strength_factor

min_silence_ms = 5
max_silence_ms = 80

appendInfoLine: "Effective parameters:"
appendInfoLine: "  Segment range: ", fixed$(eff_min_seg_ms, 1), " - ", fixed$(eff_max_seg_ms, 1), " ms"
appendInfoLine: "  Crossfade: 0 - ", fixed$(eff_max_crossfade_ms, 1), " ms"
appendInfoLine: "  Silence prob: 0 - ", fixed$(eff_silence_prob, 3)
appendInfoLine: ""

###############################################################################
# INITIALIZE POPULATION
###############################################################################

appendInfoLine: "Initializing population (", pop_size, " individuals)..."

for ind to pop_size
    segMinMs_'ind' = randomUniform(eff_min_seg_ms, eff_max_seg_ms * 0.4)
    segMaxMs_'ind' = randomUniform(max(segMinMs_'ind' + 10, eff_max_seg_ms * 0.6), eff_max_seg_ms)
    segBias_'ind' = randomUniform(-0.8, 0.8)
    reorderProb_'ind' = randomUniform(0, 1)
    crossfadeMs_'ind' = randomUniform(0, eff_max_crossfade_ms)
    silenceProb_'ind' = randomUniform(0, eff_silence_prob)
    silenceMin_'ind' = randomUniform(min_silence_ms, max_silence_ms * 0.5)
    silenceMax_'ind' = randomUniform(max(silenceMin_'ind' + 5, max_silence_ms * 0.5), max_silence_ms)
endfor

###############################################################################
# EVOLUTION
###############################################################################

appendInfoLine: "Evolving over ", generations, " generations..."
appendInfoLine: ""

fitnessHistMax# = zero#(generations)
fitnessHistMean# = zero#(generations)
fitnessHistMin# = zero#(generations)
bestFitness = -100000
bestInd = 1

# Snapshot of the best genome's parameter VALUES (not index), so the
# final render reproduces the true best-ever candidate. Previous
# versions stored only the index, which aliased to a different genome
# after evolution.
bestGenomeSegMin = 0
bestGenomeSegMax = 0
bestGenomeBias = 0
bestGenomeReorder = 0
bestGenomeXfade = 0
bestGenomeSilProb = 0
bestGenomeSilMin = 0
bestGenomeSilMax = 0

for gen to generations
    appendInfoLine: "Generation ", gen, "/", generations, "..."

    selectObject: inputSound

    doExpensive = 0
    if fitness_stride < 1
        doExpensive = 1
    elsif gen mod fitness_stride = 0
        doExpensive = 1
    endif

    for ind to pop_size
        @synthesizeCandidate: ind
        candidateSound = synthesizeCandidate.result

        @calculateFitnessFAST: candidateSound, doExpensive
        fitness_'ind' = calculateFitnessFAST.score

        selectObject: candidateSound
        nocheck Remove
    endfor

    # Per-generation min/mean/max + update best-ever with genome snapshot.
    genBestFitness = -100000
    genMinFitness = 100000
    genSumFitness = 0
    for ind to pop_size
        .f = fitness_'ind'
        genSumFitness = genSumFitness + .f
        if .f > genBestFitness
            genBestFitness = .f
        endif
        if .f < genMinFitness
            genMinFitness = .f
        endif
        if .f > bestFitness
            bestFitness = .f
            bestInd = ind
            # Snapshot the winning genome's 8 parameter values. This
            # is the key fix over v1.1: subsequent evolution cannot
            # overwrite these.
            bestGenomeSegMin   = segMinMs_'ind'
            bestGenomeSegMax   = segMaxMs_'ind'
            bestGenomeBias     = segBias_'ind'
            bestGenomeReorder  = reorderProb_'ind'
            bestGenomeXfade    = crossfadeMs_'ind'
            bestGenomeSilProb  = silenceProb_'ind'
            bestGenomeSilMin   = silenceMin_'ind'
            bestGenomeSilMax   = silenceMax_'ind'
        endif
    endfor

    fitnessHistMax#[gen]  = genBestFitness
    fitnessHistMean#[gen] = genSumFitness / pop_size
    fitnessHistMin#[gen]  = genMinFitness

    appendInfoLine: "  Max: ", fixed$(genBestFitness, 3),
        ... "  Mean: ", fixed$(genSumFitness / pop_size, 3),
        ... "  Min: ", fixed$(genMinFitness, 3)

    if gen < generations
        @evolvePopulation
        # Elitism: force the best-ever genome into slot 1 of the new
        # population. This prevents the best genome from being lost
        # through tournament selection + mutation.
        segMinMs_1   = bestGenomeSegMin
        segMaxMs_1   = bestGenomeSegMax
        segBias_1    = bestGenomeBias
        reorderProb_1 = bestGenomeReorder
        crossfadeMs_1 = bestGenomeXfade
        silenceProb_1 = bestGenomeSilProb
        silenceMin_1 = bestGenomeSilMin
        silenceMax_1 = bestGenomeSilMax
    endif
endfor

###############################################################################
# FINAL OUTPUT
#
# v1.2 FIX: synthesise using the snapshotted best-ever genome, not
# whatever currently sits at index `bestInd` (which may have been
# overwritten by later evolution). We force the best values into
# slot 1 and synthesise from there.
###############################################################################

appendInfoLine: ""
appendInfoLine: "Generating final output..."

segMinMs_1   = bestGenomeSegMin
segMaxMs_1   = bestGenomeSegMax
segBias_1    = bestGenomeBias
reorderProb_1 = bestGenomeReorder
crossfadeMs_1 = bestGenomeXfade
silenceProb_1 = bestGenomeSilProb
silenceMin_1 = bestGenomeSilMin
silenceMax_1 = bestGenomeSilMax

@synthesizeCandidate: 1
finalSound = synthesizeCandidate.result
finalNumSegs = synthesizeCandidate.numSegs
finalOutputParts = synthesizeCandidate.outputParts
selectObject: finalSound
Rename: "GA_Recombine_" + presetName$

bestSegMin  = bestGenomeSegMin
bestSegMax  = bestGenomeSegMax
bestBias    = bestGenomeBias
bestReorder = bestGenomeReorder
bestXfade   = bestGenomeXfade
bestSilProb = bestGenomeSilProb
bestSilMin  = bestGenomeSilMin
bestSilMax  = bestGenomeSilMax

selectObject: finalSound
finalDuration = Get total duration
appendInfoLine: "Final duration: ", fixed$(finalDuration, 2), " s (target was ", target_duration_s, " s)"

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##GA Segment Recomposer v1.1##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + presetName$ + " | Strength: " + string$(effect_strength)
    
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.7, 0.7, 1.35
    selectObject: inputSound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(inputDuration, 2) + " s"
    
    Select outer viewport: 0, 8, 1.4, 2.2
    Select inner viewport: 0.6, 7.7, 1.5, 2.15
    selectObject: finalSound
    Colour: "{0.3, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "GA Result"
    Text bottom: "yes", "Time (s)"
    Text top: "no", fixed$(finalDuration, 2) + " s (target: " + fixed$(target_duration_s, 1) + "s)"
    
    Select outer viewport: 0, 4, 2.3, 3.8
    Select inner viewport: 0.6, 3.7, 2.5, 3.7

    # Find overall fitness extent across min and max histories.
    minFit = fitnessHistMin#[1]
    maxFit = fitnessHistMax#[1]
    for g from 2 to generations
        if fitnessHistMin#[g] < minFit
            minFit = fitnessHistMin#[g]
        endif
        if fitnessHistMax#[g] > maxFit
            maxFit = fitnessHistMax#[g]
        endif
    endfor

    fitRange = maxFit - minFit
    if fitRange < 0.1
        fitRange = 0.1
    endif
    minFit = minFit - fitRange * 0.08
    maxFit = maxFit + fitRange * 0.08

    Axes: 0, generations + 1, minFit, maxFit
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, generations + 1, minFit, maxFit

    # Shaded band between min and max (population spread).
    # Drawn as a series of thin vertical rectangles at each generation
    # tick since Praat has no native shaded-band primitive.
    for g from 1 to generations
        Paint rectangle: "{0.85, 0.92, 0.85}",
            ... g - 0.4, g + 0.4,
            ... fitnessHistMin#[g], fitnessHistMax#[g]
    endfor

    # Min line
    Colour: "{0.60, 0.50, 0.40}"
    Line width: 1
    for g from 2 to generations
        Draw line: g - 1, fitnessHistMin#[g - 1], g, fitnessHistMin#[g]
    endfor

    # Mean line
    Colour: "{0.40, 0.55, 0.40}"
    Line width: 1.5
    for g from 2 to generations
        Draw line: g - 1, fitnessHistMean#[g - 1], g, fitnessHistMean#[g]
    endfor

    # Max line (best per generation) — drawn last so it sits on top
    Colour: "{0.20, 0.60, 0.25}"
    Line width: 2
    for g from 2 to generations
        Draw line: g - 1, fitnessHistMax#[g - 1], g, fitnessHistMax#[g]
    endfor
    for g from 1 to generations
        Paint circle: "{0.20, 0.60, 0.25}", g, fitnessHistMax#[g], 0.12
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Fitness"
    Text bottom: "yes", "Generation"
    Text top: "no", "Evolution: green=max, olive=mean, brown=min, shaded=spread"
    
    Select outer viewport: 4, 8, 2.3, 3.8
    Select inner viewport: 4.4, 7.7, 2.5, 3.7
    
    Axes: 0, 8, 0, 1.1
    Paint rectangle: "{0.98, 0.97, 0.97}", 0, 8, 0, 1.1
    
    param1 = (bestSegMin - eff_min_seg_ms) / (eff_max_seg_ms - eff_min_seg_ms + 0.001)
    param2 = (bestSegMax - eff_min_seg_ms) / (eff_max_seg_ms - eff_min_seg_ms + 0.001)
    param3 = (bestBias + 1) / 2
    param4 = bestReorder
    param5 = bestXfade / (eff_max_crossfade_ms + 0.001)
    param6 = bestSilProb / (eff_silence_prob + 0.001)
    param7 = (bestSilMin - min_silence_ms) / (max_silence_ms - min_silence_ms + 0.001)
    param8 = (bestSilMax - min_silence_ms) / (max_silence_ms - min_silence_ms + 0.001)
    
    param1 = max(0, min(1, param1))
    param2 = max(0, min(1, param2))
    param3 = max(0, min(1, param3))
    param4 = max(0, min(1, param4))
    param5 = max(0, min(1, param5))
    param6 = max(0, min(1, param6))
    param7 = max(0, min(1, param7))
    param8 = max(0, min(1, param8))
    
    barW = 0.7
    
    Paint rectangle: "{0.5, 0.7, 0.5}", 0.5 - barW/2, 0.5 + barW/2, 0, param1
    Paint rectangle: "{0.5, 0.7, 0.5}", 1.5 - barW/2, 1.5 + barW/2, 0, param2
    Paint rectangle: "{0.6, 0.6, 0.7}", 2.5 - barW/2, 2.5 + barW/2, 0, param3
    Paint rectangle: "{0.7, 0.5, 0.5}", 3.5 - barW/2, 3.5 + barW/2, 0, param4
    Paint rectangle: "{0.6, 0.7, 0.6}", 4.5 - barW/2, 4.5 + barW/2, 0, param5
    Paint rectangle: "{0.7, 0.6, 0.5}", 5.5 - barW/2, 5.5 + barW/2, 0, param6
    Paint rectangle: "{0.5, 0.6, 0.7}", 6.5 - barW/2, 6.5 + barW/2, 0, param7
    Paint rectangle: "{0.5, 0.6, 0.7}", 7.5 - barW/2, 7.5 + barW/2, 0, param8
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", -0.08, "half", "SegMin"
    Text: 1.5, "centre", -0.08, "half", "SegMax"
    Text: 2.5, "centre", -0.08, "half", "Bias"
    Text: 3.5, "centre", -0.08, "half", "Reorder"
    Text: 4.5, "centre", -0.08, "half", "Xfade"
    Text: 5.5, "centre", -0.08, "half", "SilProb"
    Text: 6.5, "centre", -0.08, "half", "SilMin"
    Text: 7.5, "centre", -0.08, "half", "SilMax"
    
    Font size: 6
    Text left: "yes", "Normalized"
    Text top: "no", "Best Genome Parameters"
    
    # ========================================================
    # Segmentation panel: input waveform with segment boundaries
    # marked. Reused segments (those that appear in the output) are
    # highlighted in green; unused segments stay grey.
    # ========================================================
    Select outer viewport: 0, 8, 3.9, 5.15
    Select inner viewport: 0.6, 7.7, 4.0, 5.05

    selectObject: inputSound
    Colour: "{0.65, 0.65, 0.65}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Determine which segment indices were used in the output.
    # Up to finalNumSegs distinct indices possible; we mark a
    # usage count per segment by scanning the outputPart kinds.
    # We scan segIdx from 1..finalNumSegs for cleanliness.
    segUsed# = zero#(finalNumSegs)
    for .p from 1 to finalOutputParts
        if partKind_'.p' = 1
            .si = partSegIdx_'.p'
            if .si >= 1 and .si <= finalNumSegs
                segUsed#[.si] = segUsed#[.si] + 1
            endif
        endif
    endfor

    Axes: 0, inputDuration, -1, 1

    # Shade each segment by its usage count. Grey for 0, green
    # (darker for higher count) for 1+.
    for .s from 1 to finalNumSegs
        .st = segStart_'.s'
        .en = segEnd_'.s'
        .count = segUsed#[.s]
        if .count = 0
            # Skip — waveform shows grey behind anyway.
        else
            # Green with intensity scaling on usage (cap at 4).
            .cap = .count
            if .cap > 4
                .cap = 4
            endif
            .alpha = 0.25 + 0.15 * .cap
            if .alpha > 0.85
                .alpha = 0.85
            endif
            .rC = 0.55 - 0.35 * (.alpha - 0.25) / 0.6
            .gC = 0.85 - 0.15 * (.alpha - 0.25) / 0.6
            .bC = 0.55 - 0.30 * (.alpha - 0.25) / 0.6
            Paint rectangle: "{" + fixed$(.rC, 2) + "," + fixed$(.gC, 2)
                ... + "," + fixed$(.bC, 2) + "}",
                ... .st, .en, -1.0, -0.85
            Paint rectangle: "{" + fixed$(.rC, 2) + "," + fixed$(.gC, 2)
                ... + "," + fixed$(.bC, 2) + "}",
                ... .st, .en, 0.85, 1.0
        endif
    endfor

    # Thin vertical ticks at each segment boundary
    Colour: "{0.45, 0.45, 0.50}"
    Line width: 0.6
    for .s from 1 to finalNumSegs
        .bT = segStart_'.s'
        Draw line: .bT, -0.95, .bT, 0.95
    endfor
    Line width: 1

    # Redraw waveform on top so it's visible against the shading
    selectObject: inputSound
    Colour: "{0.25, 0.35, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Segment pool ("
        ... + string$(finalNumSegs) + " segments; green = reused in output)"

    # ========================================================
    # Playback-order strip: output time on x, input time on y.
    # Each segment in the output is drawn as a thick line from
    # (outputTime, sourceStart) to (outputTime + duration,
    # sourceStart + duration). Silences are flat lines at y = -1
    # for visibility.
    # ========================================================
    Select outer viewport: 0, 8, 5.20, 6.40
    Select inner viewport: 0.6, 7.7, 5.30, 6.30

    Axes: 0, target_duration_s, -0.1, inputDuration
    Paint rectangle: "{0.98, 0.98, 0.96}",
        ... 0, target_duration_s, -0.1, inputDuration

    # Diagonal reference line (what a pure copy would look like)
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, 0, target_duration_s,
        ... min(target_duration_s, inputDuration)
    Solid line

    for .p from 1 to finalOutputParts
        .ot = partOutputStart_'.p'
        .od = partDuration_'.p'
        if partKind_'.p' = 1
            .ss = partSourceStart_'.p'
            Colour: "{0.20, 0.55, 0.30}"
            Line width: 1.8
            Draw line: .ot, .ss, .ot + .od, .ss + .od
        else
            # Silence marker
            Colour: "{0.80, 0.55, 0.25}"
            Line width: 1.0
            Draw line: .ot, -0.05, .ot + .od, -0.05
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source time"
    Text bottom: "yes", "Output time (s)"
    Text top: "no", "Playback map: green = where each output chunk came from; orange = silence"

    # ========================================================
    # Output spectrogram (kept; useful reference)
    # ========================================================
    Select outer viewport: 0, 8, 6.45, 7.55
    Select inner viewport: 0.6, 7.7, 6.55, 7.45

    selectObject: finalSound
    if inputChannels > 1
        Extract one channel: 1
        tmpFinal = selected("Sound")
    else
        Copy: "tmpFinal"
        tmpFinal = selected("Sound")
    endif

    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    finalSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result spectrogram"

    removeObject: finalSpec, tmpFinal
    
    Select outer viewport: 0, 8, 7.60, 8.00
    Select inner viewport: 0.6, 7.7, 7.63, 7.98

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.75, "half",
        ... "##Best genome##   Seg: " + fixed$(bestSegMin, 1)
        ... + "-" + fixed$(bestSegMax, 1) + " ms"
        ... + "   |   Bias: " + fixed$(bestBias, 2)
        ... + "   |   Reorder: " + fixed$(bestReorder * 100, 0) + "%"
        ... + "   |   Xfade: " + fixed$(bestXfade, 1) + " ms"
        ... + "   |   Silence: " + fixed$(bestSilProb * 100, 0)
        ... + "%, " + fixed$(bestSilMin, 0) + "-" + fixed$(bestSilMax, 0) + " ms"
    Text: 0.02, "left", 0.30, "half",
        ... "##Evolution##   Pop: " + string$(pop_size)
        ... + "   Gens: " + string$(generations)
        ... + "   Best fitness: " + fixed$(bestFitness, 3)
        ... + "   Weights: onset=" + fixed$(w_onset, 2)
        ... + " spec=" + fixed$(w_spectral, 2)
        ... + " reg=" + fixed$(w_regular, 2)
        ... + "   Target/Actual: " + fixed$(target_duration_s, 1)
        ... + "/" + fixed$(finalDuration, 2) + " s"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
endif

appendInfoLine: ""
appendInfoLine: "=== Complete ==="

selectObject: finalSound
if play_result
    appendInfoLine: "Playing..."
    Play
endif

###############################################################################
# PROCEDURES
###############################################################################

procedure synthesizeCandidate: .ind
    .segMin = segMinMs_'.ind' / 1000
    .segMax = segMaxMs_'.ind' / 1000
    .bias = segBias_'.ind'
    .reorder = reorderProb_'.ind'
    .xfade = crossfadeMs_'.ind' / 1000
    .silProb = silenceProb_'.ind'
    .silMin = silenceMin_'.ind' / 1000
    .silMax = silenceMax_'.ind' / 1000
    
    # === PHASE 1: Create segment pool from input ===
    .time = 0
    .numSegs = 0
    while .time < inputDuration
        .rand = randomUniform(0, 1)
        if .bias < 0
            .rand = .rand ^ (1 - .bias)
        elsif .bias > 0
            .rand = 1 - (1 - .rand) ^ (1 + .bias)
        endif
        .segDur = .segMin + .rand * (.segMax - .segMin)
        .numSegs += 1
        segStart_'.numSegs' = .time
        segEnd_'.numSegs' = min(.time + .segDur, inputDuration)
        .time = segEnd_'.numSegs'
    endwhile
    
    # === PHASE 2: Build output by drawing from segment pool ===
    .currentTime = 0
    .outputParts = 0
    .minSegDur = max(0.001, 2 / inputSampleRate)
    .lastUsedIdx = randomInteger(1, .numSegs)
    
    # Keep looping until we hit target duration
    while .currentTime < target_duration_s
        # Pick a segment from the pool
        if randomUniform(0, 1) < .reorder
            # Random selection
            .idx = randomInteger(1, .numSegs)
        else
            # Sequential-ish: pick from nearby range
            .range = max(2, floor(.numSegs * 0.3))
            .offset = randomInteger(-.range, .range)
            .idx = .lastUsedIdx + .offset
            .idx = max(1, min(.numSegs, .idx))
        endif
        
        .lastUsedIdx = .idx
        
        .segStart = segStart_'.idx'
        .segEnd = segEnd_'.idx'
        .segDur = .segEnd - .segStart
        
        if .segDur >= .minSegDur
            selectObject: inputSound
            Extract part: .segStart, .segEnd, "rectangular", 1, "no"
            .segment = selected("Sound")
            
            .dur = Get total duration
            if .dur > 0.005
                Formula: "if x < 0.002 then self * x / 0.002 else if x > xmax - 0.002 then self * (xmax - x) / 0.002 else self fi fi"
            endif
            
            .outputParts += 1
            outputPart_'.outputParts' = .segment
            partDuration_'.outputParts' = .dur
            # v1.2: record the SOURCE time and the OUTPUT time of this
            # part. Used by the visualization to draw the playback-
            # order strip and highlight which input segments were
            # reused. partKind: 1 = segment, 0 = silence.
            partSourceStart_'.outputParts' = .segStart
            partOutputStart_'.outputParts' = .currentTime
            partKind_'.outputParts' = 1
            partSegIdx_'.outputParts' = .idx
            .currentTime += .dur
        endif
        
        # Add silence with probability
        if .currentTime < target_duration_s and randomUniform(0, 1) < .silProb
            .silDur = randomUniform(.silMin, .silMax)
            
            # Don't overshoot target
            if .currentTime + .silDur > target_duration_s
                .silDur = target_duration_s - .currentTime
            endif
            
            if .silDur > 0.001
                Create Sound from formula: "silence", inputChannels, 0, .silDur, inputSampleRate, "0"
                .silence = selected("Sound")
                
                .outputParts += 1
                outputPart_'.outputParts' = .silence
                partDuration_'.outputParts' = .silDur
                partSourceStart_'.outputParts' = -1
                partOutputStart_'.outputParts' = .currentTime
                partKind_'.outputParts' = 0
                partSegIdx_'.outputParts' = 0
                .currentTime += .silDur
            endif
        endif
    endwhile
    
    # === PHASE 3: Concatenate all parts ===
    if .outputParts > 0
        if .outputParts = 1
            .result = outputPart_1
        else
            .minPartDur = partDuration_1
            for .p from 2 to .outputParts
                if partDuration_'.p' < .minPartDur
                    .minPartDur = partDuration_'.p'
                endif
            endfor
            
            .safeXfade = .xfade
            if .safeXfade > (.minPartDur / 2 - 0.0005)
                .safeXfade = .minPartDur / 2 - 0.0005
            endif
            if .safeXfade < 0
                .safeXfade = 0
            endif
            
            selectObject: outputPart_1
            for .p from 2 to .outputParts
                plusObject: outputPart_'.p'
            endfor
            
            if .safeXfade > 0.001
                Concatenate with overlap: .safeXfade
            else
                Concatenate
            endif
            .result = selected("Sound")
            
            for .p to .outputParts
                nocheck removeObject: outputPart_'.p'
            endfor
        endif
        
        # Trim to exact target duration if exceeded
        selectObject: .result
        .actualDur = Get total duration
        if .actualDur > target_duration_s
            Extract part: 0, target_duration_s, "rectangular", 1, "no"
            .trimmed = selected("Sound")
            removeObject: .result
            .result = .trimmed
        endif
        
        selectObject: .result
        Scale peak: 0.95
    else
        Create Sound from formula: "empty", inputChannels, 0, target_duration_s, inputSampleRate, "0"
        .result = selected("Sound")
    endif
    
    synthesizeCandidate.result = .result
    # v1.2: publish pool size and output-part count to the caller so
    # the visualization can iterate over the segments and playback
    # order. The segStart_N / segEnd_N / partSourceStart_N / etc.
    # families are already global by construction.
    synthesizeCandidate.numSegs = .numSegs
    synthesizeCandidate.outputParts = .outputParts
endproc

procedure calculateFitnessFAST: .sound, .doExpensive
    # Three measurable components:
    #   .onsetScore    — count of sharp intensity jumps per second,
    #                    normalised. High on glitchy/fragmented outputs.
    #   .spectralSim   — 1 - distance(candidate spectral (centroid,
    #                    spread) from input's). Higher = more
    #                    input-like spectral distribution.
    #   .regularScore  — intensity-envelope autocorrelation at a lag
    #                    matching the genome's typical segment length.
    #                    High = repeating rhythmic pattern.
    # The final score is the preset-specified weighted sum. All three
    # components are in [0, 1] (clipped), so the fitness is in [0, 1].
    #
    # .doExpensive (1/0) gates onset + regularity, which need an
    # Intensity object and are not free. When 0, those components
    # fall back to 0.5 (neutral). Used for coarse GA passes to save
    # time; set fitness_stride = 1 to disable.

    selectObject: .sound
    .dur = Get total duration
    .rms = Get root-mean-square: 0, 0

    .onsetScore = 0.5
    .spectralSim = 0.5
    .regularScore = 0.5
    .usable = 1

    # Degenerate outputs (silent / near-silent) fail all components.
    if .rms < 1e-6 or .dur < 0.1
        .usable = 0
        .onsetScore = 0
        .spectralSim = 0
        .regularScore = 0
    endif

    if .usable = 1
        # -- Component 1: spectral similarity to input ----------
        selectObject: .sound
        if inputChannels > 1
            .cMono = Convert to mono
        else
            .cMono = Copy: "cand_mono_tmp"
        endif

        selectObject: .cMono
        .cSpec = To Spectrum: "yes"
        .candCentroid = Get centre of gravity: 2
        .candSpread = Get standard deviation: 2
        removeObject: .cSpec

        .dCent = 0
        if refCentroid > 1
            .dCent = abs(.candCentroid - refCentroid) / refCentroid
        endif
        .dSpread = 0
        if refSpread > 1
            .dSpread = abs(.candSpread - refSpread) / refSpread
        endif
        .specDist = (.dCent + .dSpread) / 2
        if .specDist > 1
            .specDist = 1
        endif
        .spectralSim = 1 - .specDist

        # -- Components 2 and 3: onset density + regularity -----
        if .doExpensive = 1
            selectObject: .cMono
            .cInt = To Intensity: 100, 0, "yes"
            .nFr = Get number of frames
            .dt = Get time step

            if .nFr > 4
                .noiseFloor = refIntMin + 3
                .onsetThresh = 3.5
                .prevVal = Get value in frame: 1
                .onsetCount = 0
                for .f from 2 to .nFr
                    .v = Get value in frame: .f
                    if .v > .noiseFloor and (.v - .prevVal) >= .onsetThresh
                        .onsetCount = .onsetCount + 1
                    endif
                    .prevVal = .v
                endfor
                .onsetRate = .onsetCount / .dur

                # 8 onsets/sec saturates to 1.0
                .onsetScore = .onsetRate / 8.0
                if .onsetScore > 1
                    .onsetScore = 1
                endif

                # Regularity: autocorrelation at several candidate
                # lags, keep the best. Read values into a vector once.
                envVals# = zero#(.nFr)
                for .f from 1 to .nFr
                    envVals#[.f] = Get value in frame: .f
                endfor
                .envMean = 0
                for .f from 1 to .nFr
                    .envMean = .envMean + envVals#[.f]
                endfor
                .envMean = .envMean / .nFr

                .bestACF = 0
                .lagsToTry# = {0.15, 0.25, 0.4, 0.6, 0.9, 1.3}
                for .l from 1 to size(.lagsToTry#)
                    .lagS = .lagsToTry#[.l]
                    .lagF = round(.lagS / .dt)
                    if .lagF >= 2 and .lagF < .nFr - 2
                        .num = 0
                        .den = 0
                        for .f from 1 to .nFr - .lagF
                            .a = envVals#[.f] - .envMean
                            .b = envVals#[.f + .lagF] - .envMean
                            .num = .num + .a * .b
                            .den = .den + .a * .a
                        endfor
                        if .den > 1e-9
                            .acf = .num / .den
                            if .acf > .bestACF
                                .bestACF = .acf
                            endif
                        endif
                    endif
                endfor
                .regularScore = .bestACF
                if .regularScore < 0
                    .regularScore = 0
                endif
                if .regularScore > 1
                    .regularScore = 1
                endif
            endif

            removeObject: .cInt
        endif

        removeObject: .cMono
    endif

    .score = w_onset * .onsetScore
        ... + w_spectral * .spectralSim
        ... + w_regular * .regularScore

    calculateFitnessFAST.score = .score
    calculateFitnessFAST.onsetScore = .onsetScore
    calculateFitnessFAST.spectralSim = .spectralSim
    calculateFitnessFAST.regularScore = .regularScore
endproc

procedure evolvePopulation
    for .i to pop_size
        parent1 = randomInteger(1, pop_size)
        parent2 = randomInteger(1, pop_size)
        
        if fitness_'parent1' > fitness_'parent2'
            .parent = parent1
        else
            .parent = parent2
        endif
        
        newSegMinMs_'.i' = segMinMs_'.parent'
        newSegMaxMs_'.i' = segMaxMs_'.parent'
        newSegBias_'.i' = segBias_'.parent'
        newReorderProb_'.i' = reorderProb_'.parent'
        newCrossfadeMs_'.i' = crossfadeMs_'.parent'
        newSilenceProb_'.i' = silenceProb_'.parent'
        newSilenceMin_'.i' = silenceMin_'.parent'
        newSilenceMax_'.i' = silenceMax_'.parent'
    endfor
    
    .mutRate = 0.15
    
    for .i to pop_size
        if randomUniform(0, 1) < .mutRate
            newSegMinMs_'.i' = max(eff_min_seg_ms, min(eff_max_seg_ms * 0.4, newSegMinMs_'.i' + randomGauss(0, 10)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSegMaxMs_'.i' = max(newSegMinMs_'.i' + 10, min(eff_max_seg_ms, newSegMaxMs_'.i' + randomGauss(0, 15)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSegBias_'.i' = max(-0.8, min(0.8, newSegBias_'.i' + randomGauss(0, 0.2)))
        endif
        if randomUniform(0, 1) < .mutRate
            newReorderProb_'.i' = max(0, min(1, newReorderProb_'.i' + randomGauss(0, 0.15)))
        endif
        if randomUniform(0, 1) < .mutRate
            newCrossfadeMs_'.i' = max(0, min(eff_max_crossfade_ms, newCrossfadeMs_'.i' + randomGauss(0, 2)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSilenceProb_'.i' = max(0, min(eff_silence_prob, newSilenceProb_'.i' + randomGauss(0, 0.05)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSilenceMin_'.i' = max(min_silence_ms, min(max_silence_ms * 0.5, newSilenceMin_'.i' + randomGauss(0, 8)))
        endif
        if randomUniform(0, 1) < .mutRate
            newSilenceMax_'.i' = max(newSilenceMin_'.i' + 5, min(max_silence_ms, newSilenceMax_'.i' + randomGauss(0, 10)))
        endif
    endfor
    
    for .i to pop_size
        segMinMs_'.i' = newSegMinMs_'.i'
        segMaxMs_'.i' = newSegMaxMs_'.i'
        segBias_'.i' = newSegBias_'.i'
        reorderProb_'.i' = newReorderProb_'.i'
        crossfadeMs_'.i' = newCrossfadeMs_'.i'
        silenceProb_'.i' = newSilenceProb_'.i'
        silenceMin_'.i' = newSilenceMin_'.i'
        silenceMax_'.i' = newSilenceMax_'.i'
    endfor
endproc