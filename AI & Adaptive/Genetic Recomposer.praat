# ============================================================
# Praat AudioTools - Genetic_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Enhanced visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Genetic Algorithm Segment Recombination - Evolves optimal
#   parameters for audio segmentation, reordering, and recombination.
#
# Changelog v1.0:
#   - Added fitness history plot
#   - Added genome parameter visualization
#   - Added segment timeline
#   - Added spectrogram comparison
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
soundName$ = selected$("Sound")

form GA Segment Recombination v1.0
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
###############################################################################

if preset = 2
    effect_strength = 3
    pop_size = 8
    generations = 8
    fitness_stride = 4
    max_crossfade_ms = 8
    max_silence_prob = 0.15
    presetName$ = "SubtleTexture"
elsif preset = 3
    effect_strength = 5
    pop_size = 12
    generations = 12
    fitness_stride = 3
    max_crossfade_ms = 12
    max_silence_prob = 0.20
    presetName$ = "GranularShimmer"
elsif preset = 4
    effect_strength = 8
    pop_size = 10
    generations = 10
    fitness_stride = 2
    max_crossfade_ms = 3
    max_silence_prob = 0.45
    presetName$ = "GlitchStutter"
elsif preset = 5
    effect_strength = 10
    min_seg_ms = 10
    max_seg_ms = 80
    pop_size = 15
    generations = 15
    fitness_stride = 2
    max_crossfade_ms = 2
    max_silence_prob = 0.50
    presetName$ = "ExtremeFrag"
elsif preset = 6
    effect_strength = 6
    min_seg_ms = 50
    max_seg_ms = 250
    pop_size = 12
    generations = 12
    fitness_stride = 2
    max_crossfade_ms = 10
    max_silence_prob = 0.30
    presetName$ = "RhythmicLoops"
else
    presetName$ = "Custom"
endif

###############################################################################
# INTERNAL PARAMETERS
###############################################################################

mutation_rate = 0.30
elite_count = 2
verbose = 0

min_silence_ms = 10
max_silence_ms = 80

rhythm_weight = 1.0
continuity_weight = 0.8
novelty_weight = 1.0

###############################################################################
# STRENGTH MAPPING
###############################################################################

if effect_strength < 1
    effect_strength = 1
elsif effect_strength > 10
    effect_strength = 10
endif

strength = (effect_strength - 1) / 9

eff_min_seg_ms = max(10, min_seg_ms - 8 * effect_strength)
eff_max_seg_ms = max(eff_min_seg_ms + 10, max_seg_ms - 10 * effect_strength)

eff_reorder_min = 0.10 + 0.05 * effect_strength
eff_reorder_max = 0.30 + 0.07 * effect_strength
if eff_reorder_max > 1
    eff_reorder_max = 1
endif

eff_silence_prob = max_silence_prob * (0.5 + 0.08 * effect_strength)
if eff_silence_prob > 0.6
    eff_silence_prob = 0.6
endif

eff_max_crossfade_ms = max_crossfade_ms - 0.4 * effect_strength
if eff_max_crossfade_ms < 1
    eff_max_crossfade_ms = 1
endif

###############################################################################
# INITIALIZATION
###############################################################################

selectObject: inputSound
inputDuration = Get total duration
inputSampleRate = Get sampling frequency
inputChannels = Get number of channels

randomSeed = round(randomUniform(1, 100000))
for i to randomSeed mod 100
    dummy = randomUniform(0, 1)
endfor

clearinfo
writeInfoLine: "=== GA Segment Recombination v1.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Strength: ", effect_strength, " | Pop: ", pop_size, " | Gen: ", generations
appendInfoLine: "Eff seg(ms): ", fixed$(eff_min_seg_ms, 1), "-", fixed$(eff_max_seg_ms, 1)
appendInfoLine: ""

###############################################################################
# GENOME INITIALIZATION
###############################################################################

for ind to pop_size
    segMinMs_'ind' = randomUniform(eff_min_seg_ms, eff_max_seg_ms * 0.6)
    segMaxMs_'ind' = randomUniform(segMinMs_'ind' + 10, eff_max_seg_ms)
    segBias_'ind' = randomUniform(-0.8, 0.8)
    reorderProb_'ind' = randomUniform(eff_reorder_min, eff_reorder_max)
    crossfadeMs_'ind' = randomUniform(0, eff_max_crossfade_ms)
    silenceProb_'ind' = randomUniform(0, eff_silence_prob)
    silenceMin_'ind' = randomUniform(min_silence_ms, max_silence_ms * 0.5)
    silenceMax_'ind' = randomUniform(silenceMin_'ind', max_silence_ms)
    fitness_'ind' = 0
endfor

# Arrays for fitness history
fitnessHistory# = zero#(generations)

###############################################################################
# EVOLUTION LOOP
###############################################################################

bestFitness = -100000
bestInd = 1

for gen to generations
    appendInfoLine: "Generation ", gen, "/", generations, "..."
    
    selectObject: inputSound
    
    doRhythm = 0
    if fitness_stride < 1
        doRhythm = 1
    elsif gen mod fitness_stride = 0
        doRhythm = 1
    endif
    
    for ind to pop_size
        @synthesizeCandidate: ind
        candidateSound = synthesizeCandidate.result
        
        @calculateFitnessFAST: candidateSound, doRhythm
        fitness_'ind' = calculateFitnessFAST.score
        
        selectObject: candidateSound
        nocheck Remove
    endfor
    
    # Find best
    genBestFitness = -100000
    for ind to pop_size
        if fitness_'ind' > genBestFitness
            genBestFitness = fitness_'ind'
        endif
        if fitness_'ind' > bestFitness
            bestFitness = fitness_'ind'
            bestInd = ind
        endif
    endfor
    
    fitnessHistory#[gen] = genBestFitness
    
    appendInfoLine: "  Best fitness: ", fixed$(genBestFitness, 3)
    
    if gen < generations
        @evolvePopulation
    endif
endfor

###############################################################################
# FINAL OUTPUT
###############################################################################

appendInfoLine: ""
appendInfoLine: "Generating final output..."

@synthesizeCandidate: bestInd
finalSound = synthesizeCandidate.result
selectObject: finalSound
Rename: "GA_Recombine_" + presetName$

# Store best genome values for visualization
bestSegMin = segMinMs_'bestInd'
bestSegMax = segMaxMs_'bestInd'
bestBias = segBias_'bestInd'
bestReorder = reorderProb_'bestInd'
bestXfade = crossfadeMs_'bestInd'
bestSilProb = silenceProb_'bestInd'
bestSilMin = silenceMin_'bestInd'
bestSilMax = silenceMax_'bestInd'

###############################################################################
# VISUALIZATION
###############################################################################

if draw_visualization
    appendInfoLine: "Creating visualization..."
    
    Erase all
    Select outer viewport: 0, 8, 0, 8
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##GA Segment Recomposer##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.2, "centre", -1.0, "half", soundName$ + " | " + presetName$ + " | Strength: " + string$(effect_strength)
    
    # === Original Waveform ===
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
    
    # === Result Waveform ===
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
    
    selectObject: finalSound
    resultDur = Get total duration
    Text top: "no", fixed$(resultDur, 2) + " s"
    
    # === Fitness History ===
    Select outer viewport: 0, 4, 2.3, 3.8
    Select inner viewport: 0.6, 3.7, 2.5, 3.7
    
    # Find fitness range
    minFit = fitnessHistory#[1]
    maxFit = fitnessHistory#[1]
    for g from 2 to generations
        if fitnessHistory#[g] < minFit
            minFit = fitnessHistory#[g]
        endif
        if fitnessHistory#[g] > maxFit
            maxFit = fitnessHistory#[g]
        endif
    endfor
    
    fitRange = maxFit - minFit
    if fitRange < 0.1
        fitRange = 0.1
    endif
    minFit = minFit - fitRange * 0.1
    maxFit = maxFit + fitRange * 0.1
    
    Axes: 0, generations + 1, minFit, maxFit
    Paint rectangle: "{0.97, 0.98, 0.97}", 0, generations + 1, minFit, maxFit
    
    # Draw fitness line
    Colour: "{0.3, 0.6, 0.4}"
    Line width: 2
    for g from 2 to generations
        Draw line: g - 1, fitnessHistory#[g-1], g, fitnessHistory#[g]
    endfor
    Line width: 1
    
    # Mark points
    for g from 1 to generations
        Paint circle: "{0.3, 0.6, 0.4}", g, fitnessHistory#[g], 0.15
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Fitness"
    Text bottom: "yes", "Generation"
    Text top: "no", "Evolution Progress"
    
    # === Genome Parameters (Bar Chart) ===
    Select outer viewport: 4, 8, 2.3, 3.8
    Select inner viewport: 4.4, 7.7, 2.5, 3.7
    
    Axes: 0, 8, 0, 1.1
    Paint rectangle: "{0.98, 0.97, 0.97}", 0, 8, 0, 1.1
    
    # Normalize parameters for display
    param1 = (bestSegMin - eff_min_seg_ms) / (eff_max_seg_ms - eff_min_seg_ms + 0.001)
    param2 = (bestSegMax - eff_min_seg_ms) / (eff_max_seg_ms - eff_min_seg_ms + 0.001)
    param3 = (bestBias + 1) / 2
    param4 = bestReorder
    param5 = bestXfade / (eff_max_crossfade_ms + 0.001)
    param6 = bestSilProb / (eff_silence_prob + 0.001)
    param7 = (bestSilMin - min_silence_ms) / (max_silence_ms - min_silence_ms + 0.001)
    param8 = (bestSilMax - min_silence_ms) / (max_silence_ms - min_silence_ms + 0.001)
    
    # Clamp
    param1 = max(0, min(1, param1))
    param2 = max(0, min(1, param2))
    param3 = max(0, min(1, param3))
    param4 = max(0, min(1, param4))
    param5 = max(0, min(1, param5))
    param6 = max(0, min(1, param6))
    param7 = max(0, min(1, param7))
    param8 = max(0, min(1, param8))
    
    # Draw bars
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
    Text bottom: "yes", "Min Max Bias Reord Xfade Sil% SilMin SilMax"
    Text top: "no", "Evolved Genome (8 genes)"
    
    # === Spectrogram Comparison ===
    Select outer viewport: 0, 4, 3.9, 5.4
    Select inner viewport: 0.6, 3.7, 4.1, 5.3
    
    selectObject: inputSound
    To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Original"
    
    removeObject: specOrig
    
    Select outer viewport: 4, 8, 3.9, 5.4
    Select inner viewport: 4.4, 7.7, 4.1, 5.3
    
    selectObject: finalSound
    To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    specResult = selected("Spectrogram")
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "GA Result"
    
    removeObject: specResult
    
    # === Summary Panel ===
    Select outer viewport: 0, 8, 5.5, 6.3
    Axes: 0, 1, 0, 1
    
    Paint rectangle: "{0.95, 0.97, 0.95}", 0, 1, 0, 1
    
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.75, "half", "##Best Genome (Gen " + string$(generations) + ")##"
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.4}"
    
    Text: 0.12, "centre", 0.35, "half", "Seg: " + fixed$(bestSegMin, 0) + "-" + fixed$(bestSegMax, 0) + "ms"
    Text: 0.32, "centre", 0.35, "half", "Bias: " + fixed$(bestBias, 2)
    Text: 0.50, "centre", 0.35, "half", "Reorder: " + fixed$(bestReorder * 100, 0) + "%"
    Text: 0.68, "centre", 0.35, "half", "Xfade: " + fixed$(bestXfade, 1) + "ms"
    Text: 0.88, "centre", 0.35, "half", "Fitness: " + fixed$(bestFitness, 3)
    
    Font size: 10
    Colour: "Black"
endif

###############################################################################
# PLAYBACK
###############################################################################

selectObject: finalSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: GA_Recombine_", presetName$
appendInfoLine: "Best fitness: ", fixed$(bestFitness, 3)

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
    
    for .s to .numSegs
        segOrder_'.s' = .s
    endfor
    
    if .reorder > 0
        .limit = floor(.numSegs * .reorder)
        if .limit < 1
            .limit = 1
        endif
        for .i to .limit
            .s1 = randomInteger(1, .numSegs)
            .range = max(2, floor(.numSegs * 0.25))
            .negRange = 0 - .range
            .s2 = .s1 + randomInteger(.negRange, .range)
            .s2 = max(1, min(.numSegs, .s2))
            .temp = segOrder_'.s1'
            segOrder_'.s1' = segOrder_'.s2'
            segOrder_'.s2' = .temp
        endfor
    endif
    
    .currentTime = 0
    .outputParts = 0
    .minSegDur = max(0.001, 2 / inputSampleRate)
    
    for .s to .numSegs
        .idx = segOrder_'.s'
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
            .currentTime += .dur
        endif
        
        if .s < .numSegs and randomUniform(0, 1) < .silProb
            .silDur = randomUniform(.silMin, .silMax)
            Create Sound from formula: "silence", inputChannels, 0, .silDur, inputSampleRate, "0"
            .silence = selected("Sound")
            
            .outputParts += 1
            outputPart_'.outputParts' = .silence
            partDuration_'.outputParts' = .silDur
            .currentTime += .silDur
        endif
        
        if .currentTime >= target_duration_s
            .s = .numSegs + 1
        endif
    endfor
    
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
endproc


procedure calculateFitnessFAST: .sound, .doRhythm
    selectObject: .sound
    .dur = Get total duration
    
    .mean = Get mean: 0, 0
    .sd = Get standard deviation: 0, 0
    .rms = Get root-mean-square: 0, 0
    
    .ratio = .sd / (.rms + 1e-12)
    .continuityScore = max(0, 1.0 - .ratio)
    
    .dcRatio = abs(.mean) / (.rms + 1e-12)
    .noveltyScore = max(0, 1.0 - .dcRatio)
    
    if .rms < 1e-6
        .continuityScore = 0
        .noveltyScore = 0
    endif
    
    .rhythmScore = 0.5
    if .doRhythm = 1
        .pitchFloor = 100
        .minDur = 6.4 / .pitchFloor
        if .dur < .minDur
            .rhythmScore = 0
        else
            .tg = To TextGrid (silences): .pitchFloor, 0, -25, 0.1, 0.05, "silent", "sounding"
            .numEvents = Get number of intervals: 1
            .numEvents = .numEvents / 2
            removeObject: .tg
            
            .eventRate = .numEvents / .dur
            if .eventRate < 2
                .rhythmScore = .eventRate / 2
            elsif .eventRate > 10
                .rhythmScore = max(0, 1.0 - (.eventRate - 10) / 10)
            else
                .rhythmScore = 1.0
            endif
        endif
    endif
    
    calculateFitnessFAST.score = rhythm_weight * .rhythmScore + continuity_weight * .continuityScore + novelty_weight * .noveltyScore
endproc


procedure evolvePopulation
    for .i to pop_size - 1
        for .j from .i + 1 to pop_size
            if fitness_'.i' < fitness_'.j'
                .temp = fitness_'.i'
                fitness_'.i' = fitness_'.j'
                fitness_'.j' = .temp
                @swapGenes: .i, .j
            endif
        endfor
    endfor
    
    for .child from elite_count + 1 to pop_size
        .p1 = randomInteger(1, floor(pop_size / 2))
        .p2 = randomInteger(1, floor(pop_size / 2))
        .blend = randomUniform(0, 1)
        .invBlend = 1 - .blend
        
        segMinMs_'.child' = .blend * segMinMs_'.p1' + .invBlend * segMinMs_'.p2'
        segMaxMs_'.child' = .blend * segMaxMs_'.p1' + .invBlend * segMaxMs_'.p2'
        segBias_'.child' = .blend * segBias_'.p1' + .invBlend * segBias_'.p2'
        reorderProb_'.child' = .blend * reorderProb_'.p1' + .invBlend * reorderProb_'.p2'
        crossfadeMs_'.child' = .blend * crossfadeMs_'.p1' + .invBlend * crossfadeMs_'.p2'
        silenceProb_'.child' = .blend * silenceProb_'.p1' + .invBlend * silenceProb_'.p2'
        silenceMin_'.child' = .blend * silenceMin_'.p1' + .invBlend * silenceMin_'.p2'
        silenceMax_'.child' = .blend * silenceMax_'.p1' + .invBlend * silenceMax_'.p2'
        
        if randomUniform(0, 1) < mutation_rate
            segMinMs_'.child' = segMinMs_'.child' + randomGauss(0, (max_seg_ms - min_seg_ms) * 0.12)
            segMinMs_'.child' = max(10, min(eff_max_seg_ms * 0.7, segMinMs_'.child'))
        endif
        if randomUniform(0, 1) < mutation_rate
            reorderProb_'.child' = reorderProb_'.child' + randomGauss(0, 0.25)
            reorderProb_'.child' = max(0, min(1, reorderProb_'.child'))
        endif
        if randomUniform(0, 1) < mutation_rate
            crossfadeMs_'.child' = crossfadeMs_'.child' + randomGauss(0, 3)
            crossfadeMs_'.child' = max(0, min(eff_max_crossfade_ms, crossfadeMs_'.child'))
        endif
        if randomUniform(0, 1) < mutation_rate
            silenceProb_'.child' = silenceProb_'.child' + randomGauss(0, 0.20)
            silenceProb_'.child' = max(0, min(eff_silence_prob, silenceProb_'.child'))
        endif
    endfor
endproc


procedure swapGenes: .a, .b
    .t = segMinMs_'.a'
    segMinMs_'.a' = segMinMs_'.b'
    segMinMs_'.b' = .t
    
    .t = segMaxMs_'.a'
    segMaxMs_'.a' = segMaxMs_'.b'
    segMaxMs_'.b' = .t
    
    .t = segBias_'.a'
    segBias_'.a' = segBias_'.b'
    segBias_'.b' = .t
    
    .t = reorderProb_'.a'
    reorderProb_'.a' = reorderProb_'.b'
    reorderProb_'.b' = .t
    
    .t = crossfadeMs_'.a'
    crossfadeMs_'.a' = crossfadeMs_'.b'
    crossfadeMs_'.b' = .t
    
    .t = silenceProb_'.a'
    silenceProb_'.a' = silenceProb_'.b'
    silenceProb_'.b' = .t
    
    .t = silenceMin_'.a'
    silenceMin_'.a' = silenceMin_'.b'
    silenceMin_'.b' = .t
    
    .t = silenceMax_'.a'
    silenceMax_'.a' = silenceMax_'.b'
    silenceMax_'.b' = .t
endproc
