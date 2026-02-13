# ============================================================
# Praat AudioTools - Genetic_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2025) - BUGFIX: Target duration now works
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# BUGFIX: Script now properly loops through segment pool to reach target duration
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
soundName$ = selected$("Sound")

form GA Segment Recombination v1.1
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
    fitness_stride = 3
    max_crossfade_ms = 8
    max_silence_prob = 0.10
    presetName$ = "RhythmicLoops"
else
    presetName$ = "Custom"
endif

###############################################################################
# SETUP
###############################################################################

clearinfo
writeInfoLine: "=== GA Segment Recomposer v1.1 (BUGFIX) ==="
writeInfoLine: "Input: ", soundName$
writeInfoLine: "Target duration: ", target_duration_s, " s"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: "Effect strength: ", effect_strength, "/10"
appendInfoLine: ""

selectObject: inputSound
inputDuration = Get total duration
inputSampleRate = Get sampling frequency
inputChannels = Get number of channels

appendInfoLine: "Original duration: ", fixed$(inputDuration, 2), " s"
appendInfoLine: "Sample rate: ", inputSampleRate, " Hz"
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

fitnessHistory# = zero#(generations)
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

bestSegMin = segMinMs_'bestInd'
bestSegMax = segMaxMs_'bestInd'
bestBias = segBias_'bestInd'
bestReorder = reorderProb_'bestInd'
bestXfade = crossfadeMs_'bestInd'
bestSilProb = silenceProb_'bestInd'
bestSilMin = silenceMin_'bestInd'
bestSilMax = silenceMax_'bestInd'

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
    
    Colour: "{0.3, 0.6, 0.4}"
    Line width: 2
    for g from 2 to generations
        Draw line: g - 1, fitnessHistory#[g-1], g, fitnessHistory#[g]
    endfor
    Line width: 1
    
    for g from 1 to generations
        Paint circle: "{0.3, 0.6, 0.4}", g, fitnessHistory#[g], 0.15
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Fitness"
    Text bottom: "yes", "Generation"
    Text top: "no", "Evolution Progress"
    
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
    
    Select outer viewport: 0, 8, 3.9, 5.4
    Select inner viewport: 0.6, 7.7, 4.0, 5.3
    
    selectObject: inputSound
    if inputChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"
    
    removeObject: origSpec, tmpOrig
    
    Select outer viewport: 0, 8, 5.4, 6.9
    Select inner viewport: 0.6, 7.7, 5.5, 6.8
    
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
    Text top: "no", "Result Spectrogram"
    
    removeObject: finalSpec, tmpFinal
    
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.7, 7.1, 7.9
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    
    Text: 0.05, "left", 0.75, "half", "Best Genome Details:"
    Font size: 6
    Text: 0.05, "left", 0.55, "half", "Seg: " + fixed$(bestSegMin, 1) + "-" + fixed$(bestSegMax, 1) + " ms | Bias: " + fixed$(bestBias, 2)
    Text: 0.05, "left", 0.35, "half", "Reorder: " + fixed$(bestReorder * 100, 0) + "% | Xfade: " + fixed$(bestXfade, 1) + " ms"
    Text: 0.05, "left", 0.15, "half", "Silence: " + fixed$(bestSilProb * 100, 0) + "% prob, " + fixed$(bestSilMin, 0) + "-" + fixed$(bestSilMax, 0) + " ms"
    
    Font size: 7
    Text: 0.65, "left", 0.75, "half", "Evolution Stats:"
    Font size: 6
    Text: 0.65, "left", 0.55, "half", "Population: " + string$(pop_size) + " | Generations: " + string$(generations)
    Text: 0.65, "left", 0.35, "half", "Best Fitness: " + fixed$(bestFitness, 3)
    Text: 0.65, "left", 0.15, "half", "Target Duration: " + fixed$(target_duration_s, 1) + " s | Actual: " + fixed$(finalDuration, 2) + " s"
    
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
        .pitchCeiling = 600
        
        To Pitch (cc): 0, .pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, .pitchCeiling
        .pitchObj = selected("Pitch")
        
        .numVoiced = Count voiced frames
        .numFrames = Get number of frames
        
        if .numFrames > 0
            .voicedRatio = .numVoiced / .numFrames
        else
            .voicedRatio = 0
        endif
        
        .rhythmScore = max(0, min(1, .voicedRatio * 1.5))
        
        removeObject: .pitchObj
    endif
    
    .score = 0.4 * .continuityScore + 0.3 * .noveltyScore + 0.3 * .rhythmScore
    
    calculateFitnessFAST.score = .score
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