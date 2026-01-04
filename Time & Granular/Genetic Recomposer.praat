# ============================================================
# Praat AudioTools - Genetic Recomposer
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   GA SEGMENT RECOMBINATION ORGANISM
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

###############################################################################
# GA SEGMENT RECOMBINATION ORGANISM 
###############################################################################

form GA Segment Recombination Organism
    comment === Quick Start Presets ===
    optionmenu preset 1
        option Custom (use settings below)
        option Subtle Texture
        option Granular Shimmer
        option Glitch / Stutter
        option Extreme Fragmentation
        option Rhythmic Loops
    
    comment === Output ===
    positive target_duration_s 8.0

    comment === Effect strength (1 subtle .. 10 extreme) ===
    positive effect_strength 6

    comment === Quality / Speed ===
    positive pop_size 10
    positive generations 10
    positive fitness_stride 3

    comment === Segmentation (ms) ===
    positive min_seg_ms 20
    positive max_seg_ms 180

    comment === Texture ===
    positive max_crossfade_ms 6
    real max_silence_prob 0.25

    comment === Playback ===
    boolean play_result 1
endform

###############################################################################
# APPLY PRESET
###############################################################################

if preset = 2
    # Subtle Texture - gentle granulation
    effect_strength = 3
    pop_size = 8
    generations = 8
    fitness_stride = 4
    max_crossfade_ms = 8
    max_silence_prob = 0.15
elsif preset = 3
    # Granular Shimmer - smooth granular with crossfades
    effect_strength = 5
    pop_size = 12
    generations = 12
    fitness_stride = 3
    max_crossfade_ms = 12
    max_silence_prob = 0.20
elsif preset = 4
    # Glitch / Stutter - aggressive cuts and silences
    effect_strength = 8
    pop_size = 10
    generations = 10
    fitness_stride = 2
    max_crossfade_ms = 3
    max_silence_prob = 0.45
elsif preset = 5
    # Extreme Fragmentation - maximum chaos
    effect_strength = 10
    min_seg_ms = 10
    max_seg_ms = 80
    pop_size = 15
    generations = 15
    fitness_stride = 2
    max_crossfade_ms = 2
    max_silence_prob = 0.50
elsif preset = 6
    # Rhythmic Loops - longer segments, more musical
    effect_strength = 6
    min_seg_ms = 50
    max_seg_ms = 250
    pop_size = 12
    generations = 12
    fitness_stride = 2
    max_crossfade_ms = 10
    max_silence_prob = 0.30
endif
# If preset = 1 (Custom), use form values as-is

###############################################################################
# INTERNAL PARAMETERS (HIDDEN)
###############################################################################
mutation_rate = 0.30
elite_count = 2
random_seed = -1
verbose = 0

# Reorder bounds (we will bias based on strength)
min_reorder_prob = 0.0
max_reorder_prob = 1.0

min_silence_ms = 10
max_silence_ms = 80

rhythm_weight = 1.0
continuity_weight = 0.8
novelty_weight = 1.0

###############################################################################
# STRENGTH MAPPING
###############################################################################
# Clamp strength
if effect_strength < 1
    effect_strength = 1
elsif effect_strength > 10
    effect_strength = 10
endif

# Normalize 0..1
strength = (effect_strength - 1) / 9

# Stronger => shorter segments and more chaos
eff_min_seg_ms = max(10, min_seg_ms - 8 * effect_strength)
eff_max_seg_ms = max(eff_min_seg_ms + 10, max_seg_ms - 10 * effect_strength)

# Stronger => more reorder probability
eff_reorder_min = 0.10 + 0.05 * effect_strength
eff_reorder_max = 0.30 + 0.07 * effect_strength
if eff_reorder_max > 1
    eff_reorder_max = 1
endif

# Stronger => more silence insertion
eff_silence_prob = max_silence_prob * (0.5 + 0.08 * effect_strength)
if eff_silence_prob > 0.6
    eff_silence_prob = 0.6
endif

# Stronger => smaller crossfade (more "edgy")
eff_max_crossfade_ms = max_crossfade_ms - 0.4 * effect_strength
if eff_max_crossfade_ms < 1
    eff_max_crossfade_ms = 1
endif

###############################################################################
# INITIALIZATION
###############################################################################

if numberOfSelected("Sound") != 1
    exitScript: "Please select exactly ONE Sound object."
endif

inputSound = selected("Sound")
selectObject: inputSound
soundName$ = selected$("Sound")
inputDuration = Get total duration
inputSampleRate = Get sampling frequency
inputChannels = Get number of channels

if random_seed > 0
    randomSeed = random_seed
else
    randomSeed = randomUniform(1, 2147483647)
endif

for i to randomSeed mod 100
    dummy = randomUniform(0, 1)
endfor

# Display preset name
presetName$ = "Custom"
if preset = 2
    presetName$ = "Subtle Texture"
elsif preset = 3
    presetName$ = "Granular Shimmer"
elsif preset = 4
    presetName$ = "Glitch/Stutter"
elsif preset = 5
    presetName$ = "Extreme Fragmentation"
elsif preset = 6
    presetName$ = "Rhythmic Loops"
endif

writeInfoLine: "=== GA Recombination (Preset: ", presetName$, ") ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Strength: ", effect_strength, " | Pop: ", pop_size, " | Gen: ", generations
appendInfoLine: "Eff seg(ms): ", fixed$(eff_min_seg_ms, 1), " - ", fixed$(eff_max_seg_ms, 1), " | Eff silence p: ", fixed$(eff_silence_prob, 2)

###############################################################################
# GENOME INITIALIZATION
###############################################################################

for ind to pop_size
    # segment bounds (biased by strength)
    segMinMs_'ind' = randomUniform(eff_min_seg_ms, eff_max_seg_ms * 0.6)
    segMaxMs_'ind' = randomUniform(segMinMs_'ind' + 10, eff_max_seg_ms)

    # bias (keep moderate)
    segBias_'ind' = randomUniform(-0.8, 0.8)

    # reorder probability (strength-biased)
    reorderProb_'ind' = randomUniform(eff_reorder_min, eff_reorder_max)

    # crossfade (smaller at higher strength)
    crossfadeMs_'ind' = randomUniform(0, eff_max_crossfade_ms)

    # silence probability (strength-biased)
    silenceProb_'ind' = randomUniform(0, eff_silence_prob)
    silenceMin_'ind' = randomUniform(min_silence_ms, max_silence_ms * 0.5)
    silenceMax_'ind' = randomUniform(silenceMin_'ind', max_silence_ms)

    fitness_'ind' = 0
endfor

###############################################################################
# EVOLUTION LOOP
###############################################################################

for gen to generations
    if verbose or gen mod 1 = 0
        appendInfoLine: "Generation ", gen, "/", generations, "..."
    endif
    
    nocheck selectObject: inputSound
    
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
        
        nocheck selectObject: candidateSound
        Remove
    endfor
    
    bestFitness = -100000
    bestInd = 1
    for ind to pop_size
        if fitness_'ind' > bestFitness
            bestFitness = fitness_'ind'
            bestInd = ind
        endif
    endfor
    
    if verbose or gen mod 1 = 0
        appendInfoLine: "  Best fitness: ", fixed$(bestFitness, 3)
    endif
    
    if gen < generations
        @evolvePopulation
    endif
endfor

###############################################################################
# FINAL OUTPUT
###############################################################################

appendInfoLine: "Done! Best fitness: ", fixed$(bestFitness, 3)
appendInfoLine: "Generating final output..."

@synthesizeCandidate: bestInd
finalSound = synthesizeCandidate.result
selectObject: finalSound
Rename: "GA_Recombine_best"

if play_result
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
            .s2 = max(1, min(.numSegs, .s1 + randomInteger(-'.range', .range)))
            .temp = segOrder_'.s1'
            segOrder_'.s1' = segOrder_'.s2'
            segOrder_'.s2' = .temp
        endfor
    endif
    
    .currentTime = 0
    .outputParts = 0
    
    # Calculate minimum segment duration (at least 2 samples or 1ms)
    .minSegDur = max(0.001, 2 / inputSampleRate)
    
    for .s to .numSegs
        .idx = segOrder_'.s'
        .segStart = segStart_'.idx'
        .segEnd = segEnd_'.idx'
        .segDur = .segEnd - .segStart
        
        # Skip segments that are too short to extract
        if .segDur >= .minSegDur
            nocheck selectObject: inputSound
            
            Extract part: .segStart, .segEnd, "rectangular", 1, "no"
            .segment = selected()
            
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
            .silence = selected()
            
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
            nocheck selectObject: outputPart_1
            for .p from 2 to .outputParts
                nocheck plusObject: outputPart_'.p'
            endfor
            
            # Find minimum part duration for safe crossfade
            .minPartDur = partDuration_1
            for .p from 2 to .outputParts
                if partDuration_'.p' < .minPartDur
                    .minPartDur = partDuration_'.p'
                endif
            endfor
            
            # Ensure crossfade doesn't exceed half of shortest segment
            .safeXfade = .xfade
            if .safeXfade > (.minPartDur / 2 - 0.0005)
                .safeXfade = .minPartDur / 2 - 0.0005
            endif
            
            # Concatenate with or without overlap
            if .safeXfade > 0.001
                Concatenate with overlap: .safeXfade
            else
                Concatenate
            endif
            
            .result = selected()
            
            # Cleanup parts (simplified - Concatenate already removed them)
            for .p to .outputParts
                nocheck selectObject: outputPart_'.p'
                Remove
            endfor
        endif
        
        # Trim to target duration if needed
        selectObject: .result
        .actualDur = Get total duration
        if .actualDur > target_duration_s
            Extract part: 0, target_duration_s, "rectangular", 1, "no"
            .trimmed = selected()
            nocheck selectObject: .result
            Remove
            .result = .trimmed
        endif
        
        # Normalize
        selectObject: .result
        Scale peak: 0.95
    else
        # Fallback: create silence
        selectObject: inputSound
        Create Sound from formula: "empty", inputChannels, 0, target_duration_s, inputSampleRate, "0"
        .result = selected()
    endif
    
    synthesizeCandidate.result = .result
endproc


procedure calculateFitnessFAST: .sound, .doRhythm
    selectObject: .sound
    .dur = Get total duration
    
    # Fast proxy metrics from waveform statistics
    .mean = Get mean: 0, 0
    .sd = Get standard deviation: 0, 0
    .rms = Get root-mean-square: 0, 0
    
    # Continuity proxy: lower SD/RMS ratio = more consistent
    .ratio = .sd / (.rms + 1e-12)
    .continuityScore = max(0, 1.0 - .ratio)
    
    # Novelty proxy: DC ratio (lower = more varied)
    .dcRatio = abs(.mean) / (.rms + 1e-12)
    .noveltyScore = max(0, 1.0 - .dcRatio)
    
    # Safety: if sound is silent, penalize
    if .rms < 1e-6
        .continuityScore = 0
        .noveltyScore = 0
    endif
    
    # Rhythm score (expensive, only computed periodically)
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
            selectObject: .tg
            Remove
            
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
    
    # Combine weighted fitness
    calculateFitnessFAST.score = rhythm_weight * .rhythmScore + continuity_weight * .continuityScore + novelty_weight * .noveltyScore
endproc


procedure evolvePopulation
    # Sort population by fitness (bubble sort)
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
    
    # Generate new children via crossover and mutation
    for .child from elite_count + 1 to pop_size
        # Tournament selection
        .p1 = randomInteger(1, floor(pop_size / 2))
        .p2 = randomInteger(1, floor(pop_size / 2))
        .blend = randomUniform(0, 1)
        
        # Crossover (blend genes)
        segMinMs_'.child' = .blend * segMinMs_'.p1' + (1-.blend)*segMinMs_'.p2'
        segMaxMs_'.child' = .blend * segMaxMs_'.p1' + (1-.blend)*segMaxMs_'.p2'
        segBias_'.child' = .blend * segBias_'.p1' + (1-.blend)*segBias_'.p2'
        reorderProb_'.child' = .blend * reorderProb_'.p1' + (1-.blend)*reorderProb_'.p2'
        crossfadeMs_'.child' = .blend * crossfadeMs_'.p1' + (1-.blend)*crossfadeMs_'.p2'
        silenceProb_'.child' = .blend * silenceProb_'.p1' + (1-.blend)*silenceProb_'.p2'
        silenceMin_'.child' = .blend * silenceMin_'.p1' + (1-.blend)*silenceMin_'.p2'
        silenceMax_'.child' = .blend * silenceMax_'.p1' + (1-.blend)*silenceMax_'.p2'
        
        # Mutation
        if randomUniform(0,1) < mutation_rate
            segMinMs_'.child' += randomGauss(0, (max_seg_ms-min_seg_ms)*0.12)
            segMinMs_'.child' = max(10, min(eff_max_seg_ms*0.7, segMinMs_'.child'))
        endif
        if randomUniform(0,1) < mutation_rate
            reorderProb_'.child' += randomGauss(0, 0.25)
            reorderProb_'.child' = max(0, min(1, reorderProb_'.child'))
        endif
        if randomUniform(0,1) < mutation_rate
            crossfadeMs_'.child' += randomGauss(0, 3)
            crossfadeMs_'.child' = max(0, min(eff_max_crossfade_ms, crossfadeMs_'.child'))
        endif
        if randomUniform(0,1) < mutation_rate
            silenceProb_'.child' += randomGauss(0, 0.20)
            silenceProb_'.child' = max(0, min(eff_silence_prob, silenceProb_'.child'))
        endif
    endfor
endproc


procedure swapGenes: .a, .b
    # Helper to swap all genes between two individuals
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
# === Visualization ===
Erase all

# Title
Select outer viewport: 0, 8, 0.2, 0.6
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "GA Recomposer: " + soundName$ + " (" + presetName$ + ")"

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
Text: 0.5, "centre", 0.5, "half", "Best: SegMs=" + fixed$(segMinMs_'bestInd', 0) + "-" + fixed$(segMaxMs_'bestInd', 0) + " | Reorder=" + fixed$(reorderProb_'bestInd'*100, 0) + "% | Silence=" + fixed$(silenceProb_'bestInd'*100, 0) + "% | Fitness=" + fixed$(bestFitness, 3)

Font size: 10
Colour: "Black"