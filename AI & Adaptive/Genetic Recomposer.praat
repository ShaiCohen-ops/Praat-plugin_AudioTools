# ============================================================
# Praat AudioTools - Genetic_Recomposer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Genetic Algorithm Segment Recombination - Evolves optimal
#   parameters for audio segmentation, reordering, and recombination.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed != to <> operator
#   - Fixed negative variable interpolation
#   - Fixed cleanup after concatenation
#   - Fixed Text command string building
#   - Added input validation
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

inputSound = selected("Sound")
soundName$ = selected$("Sound")

form GA Segment Recombination v0.2
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
    comment === Playback ===
    boolean Play_result 1
endform

###############################################################################
# APPLY PRESET
###############################################################################

if preset = 2
    # Subtle Texture
    effect_strength = 3
    pop_size = 8
    generations = 8
    fitness_stride = 4
    max_crossfade_ms = 8
    max_silence_prob = 0.15
    presetName$ = "SubtleTexture"
elsif preset = 3
    # Granular Shimmer
    effect_strength = 5
    pop_size = 12
    generations = 12
    fitness_stride = 3
    max_crossfade_ms = 12
    max_silence_prob = 0.20
    presetName$ = "GranularShimmer"
elsif preset = 4
    # Glitch / Stutter
    effect_strength = 8
    pop_size = 10
    generations = 10
    fitness_stride = 2
    max_crossfade_ms = 3
    max_silence_prob = 0.45
    presetName$ = "GlitchStutter"
elsif preset = 5
    # Extreme Fragmentation
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
    # Rhythmic Loops
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

# Seed RNG
randomSeed = round(randomUniform(1, 100000))
for i to randomSeed mod 100
    dummy = randomUniform(0, 1)
endfor

clearinfo
writeInfoLine: "=== GA Segment Recombination v0.2 ==="
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
    for ind to pop_size
        if fitness_'ind' > bestFitness
            bestFitness = fitness_'ind'
            bestInd = ind
        endif
    endfor
    
    appendInfoLine: "  Best fitness: ", fixed$(bestFitness, 3)
    
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

###############################################################################
# VISUALIZATION
###############################################################################

Erase all

# Title
Select outer viewport: 0, 8, 0.2, 0.6
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "GA Recomposer: " + soundName$ + " [" + presetName$ + "]"

# Original waveform
Select outer viewport: 0, 8, 0.8, 2.2
Select inner viewport: 0.6, 7.6, 0.9, 2.1
selectObject: inputSound
Colour: "{0.6, 0.6, 0.6}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 8
Text left: "yes", "Original"

# Result waveform
Select outer viewport: 0, 8, 2.3, 3.7
Select inner viewport: 0.6, 7.6, 2.4, 3.6
selectObject: finalSound
Colour: "{0.2, 0.5, 0.7}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Text left: "yes", "GA Result"
Text bottom: "yes", "Time (s)"

# Best genome info
Select outer viewport: 0, 8, 3.9, 4.4
Font size: 8
Colour: "{0.4, 0.4, 0.4}"

bestSegMin = segMinMs_'bestInd'
bestSegMax = segMaxMs_'bestInd'
bestReorder = reorderProb_'bestInd' * 100
bestSilence = silenceProb_'bestInd' * 100
infoText$ = "Best: Seg=" + fixed$(bestSegMin, 0) + "-" + fixed$(bestSegMax, 0) + "ms | Reorder=" + fixed$(bestReorder, 0) + "% | Silence=" + fixed$(bestSilence, 0) + "% | Fitness=" + fixed$(bestFitness, 3)
Text: 0.5, "centre", 0.5, "half", infoText$

Font size: 10
Colour: "Black"

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
    
    # Segment the input
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
    
    # Initialize order
    for .s to .numSegs
        segOrder_'.s' = .s
    endfor
    
    # Reorder segments
    if .reorder > 0
        .limit = floor(.numSegs * .reorder)
        if .limit < 1
            .limit = 1
        endif
        for .i to .limit
            .s1 = randomInteger(1, .numSegs)
            .range = max(2, floor(.numSegs * 0.25))
            .negRange = -.range
            .s2 = .s1 + randomInteger(.negRange, .range)
            .s2 = max(1, min(.numSegs, .s2))
            .temp = segOrder_'.s1'
            segOrder_'.s1' = segOrder_'.s2'
            segOrder_'.s2' = .temp
        endfor
    endif
    
    # Build output
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
        
        # Insert silence
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
    
    # Concatenate
    if .outputParts > 0
        if .outputParts = 1
            .result = outputPart_1
        else
            # Find minimum part duration
            .minPartDur = partDuration_1
            for .p from 2 to .outputParts
                if partDuration_'.p' < .minPartDur
                    .minPartDur = partDuration_'.p'
                endif
            endfor
            
            # Safe crossfade
            .safeXfade = .xfade
            if .safeXfade > (.minPartDur / 2 - 0.0005)
                .safeXfade = .minPartDur / 2 - 0.0005
            endif
            if .safeXfade < 0
                .safeXfade = 0
            endif
            
            # Select all parts
            selectObject: outputPart_1
            for .p from 2 to .outputParts
                plusObject: outputPart_'.p'
            endfor
            
            # Concatenate
            if .safeXfade > 0.001
                Concatenate with overlap: .safeXfade
            else
                Concatenate
            endif
            .result = selected("Sound")
            
            # Cleanup parts
            for .p to .outputParts
                nocheck removeObject: outputPart_'.p'
            endfor
        endif
        
        # Trim to target
        selectObject: .result
        .actualDur = Get total duration
        if .actualDur > target_duration_s
            Extract part: 0, target_duration_s, "rectangular", 1, "no"
            .trimmed = selected("Sound")
            removeObject: .result
            .result = .trimmed
        endif
        
        # Normalize
        selectObject: .result
        Scale peak: 0.95
    else
        # Fallback
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
    
    # Continuity proxy
    .ratio = .sd / (.rms + 1e-12)
    .continuityScore = max(0, 1.0 - .ratio)
    
    # Novelty proxy
    .dcRatio = abs(.mean) / (.rms + 1e-12)
    .noveltyScore = max(0, 1.0 - .dcRatio)
    
    if .rms < 1e-6
        .continuityScore = 0
        .noveltyScore = 0
    endif
    
    # Rhythm score
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
    # Sort by fitness (bubble sort)
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
    
    # Generate children
    for .child from elite_count + 1 to pop_size
        .p1 = randomInteger(1, floor(pop_size / 2))
        .p2 = randomInteger(1, floor(pop_size / 2))
        .blend = randomUniform(0, 1)
        .invBlend = 1 - .blend
        
        # Crossover
        segMinMs_'.child' = .blend * segMinMs_'.p1' + .invBlend * segMinMs_'.p2'
        segMaxMs_'.child' = .blend * segMaxMs_'.p1' + .invBlend * segMaxMs_'.p2'
        segBias_'.child' = .blend * segBias_'.p1' + .invBlend * segBias_'.p2'
        reorderProb_'.child' = .blend * reorderProb_'.p1' + .invBlend * reorderProb_'.p2'
        crossfadeMs_'.child' = .blend * crossfadeMs_'.p1' + .invBlend * crossfadeMs_'.p2'
        silenceProb_'.child' = .blend * silenceProb_'.p1' + .invBlend * silenceProb_'.p2'
        silenceMin_'.child' = .blend * silenceMin_'.p1' + .invBlend * silenceMin_'.p2'
        silenceMax_'.child' = .blend * silenceMax_'.p1' + .invBlend * silenceMax_'.p2'
        
        # Mutation
        if randomUniform(0, 1) < mutation_rate
            segMinMs_'.child' += randomGauss(0, (max_seg_ms - min_seg_ms) * 0.12)
            segMinMs_'.child' = max(10, min(eff_max_seg_ms * 0.7, segMinMs_'.child'))
        endif
        if randomUniform(0, 1) < mutation_rate
            reorderProb_'.child' += randomGauss(0, 0.25)
            reorderProb_'.child' = max(0, min(1, reorderProb_'.child'))
        endif
        if randomUniform(0, 1) < mutation_rate
            crossfadeMs_'.child' += randomGauss(0, 3)
            crossfadeMs_'.child' = max(0, min(eff_max_crossfade_ms, crossfadeMs_'.child'))
        endif
        if randomUniform(0, 1) < mutation_rate
            silenceProb_'.child' += randomGauss(0, 0.20)
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