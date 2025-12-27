# ============================================================
# Praat AudioTools - Band-Based Concatenative Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Concatenative synthesis using multi-band spectral matching.
#   Reconstructs target audio using segments from source audio,
#   selected based on spectral similarity across frequency bands.
#   Includes continuity penalty for smooth temporal transitions.
#
# Technical approach:
#   - Analyzes source and target in multiple frequency bands
#   - Computes RMS energy features with Z-score normalization
#   - Matches target frames to source using weighted distance
#   - Continuity penalty (lambda) encourages smooth trajectories
#   - Reconstructs via multi-stream overlap-add synthesis
#   - True stereo processing preserves spatial image
#
# Usage:
#   Select TWO Sound objects: Source (1) and Target (2)
#   Run this script and adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Band-Based Concatenative Synthesis
    comment Select Source (1) and Target (2) before running.
    comment Reconstructs target using spectral-matched source segments.
    optionmenu Preset: 1
        option Custom
        option Subtle Morph
        option Granular Texture
        option Spectral Match
        option Rhythmic Mosaic
        option Smooth Blend
    comment === Temporal Parameters ===
    positive window_length 0.060
    comment (grain length in seconds)
    positive hop_size 0.030
    comment (hop between grains - should divide window evenly)
    comment === Frequency Bands ===
    optionmenu Band_configuration: 2
        option 2 bands (low/high)
        option 4 bands (default)
        option 6 bands (detailed)
        option 8 bands (fine)
    comment === Matching Parameters ===
    real continuity_weight 0.3
    comment (0 = ignore continuity, 1 = strong preference for smooth path)
    positive locality_window 0.4
    comment (search range in seconds - larger = more variation)
    comment === Output ===
    real dry_wet_mix 1.0
    comment (0 = target only, 1 = full synthesis)
    positive scale_peak 0.95
    boolean play_after_processing 1
    boolean draw_visualization 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Subtle Morph"
    window_length = 0.080
    hop_size = 0.040
    continuity_weight = 0.5
    locality_window = 0.6
elif preset$ = "Granular Texture"
    window_length = 0.040
    hop_size = 0.020
    continuity_weight = 0.15
    locality_window = 0.3
elif preset$ = "Spectral Match"
    window_length = 0.050
    hop_size = 0.025
    continuity_weight = 0.35
    locality_window = 0.4
elif preset$ = "Rhythmic Mosaic"
    window_length = 0.100
    hop_size = 0.050
    continuity_weight = 0.7
    locality_window = 0.8
elif preset$ = "Smooth Blend"
    window_length = 0.120
    hop_size = 0.060
    continuity_weight = 0.6
    locality_window = 1.0
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects: Source (1) and Target (2)"
endif

source = selected("Sound", 1)
target = selected("Sound", 2)

selectObject: source
sourceName$ = selected$("Sound")
sourceDur = Get total duration
sourceSR = Get sampling frequency
sourceChannels = Get number of channels

selectObject: target
targetName$ = selected$("Sound")
targetDur = Get total duration
targetSR = Get sampling frequency
targetChannels = Get number of channels

# Validate sample rates
if sourceSR <> targetSR
    exitScript: "Sample rates must match (" + string$(sourceSR) + " vs " + string$(targetSR) + "). Please resample first."
endif

sampleRate = sourceSR
nyquist = sampleRate / 2

# ============================================================
# OLA constraint: hop must divide window evenly
# ============================================================
ratio = window_length / hop_size
intRatio = round(ratio)
if abs(ratio - intRatio) > 0.01
    hop_size = window_length / intRatio
endif
numStreams = intRatio

# ============================================================
# Set up frequency bands
# ============================================================
if band_configuration = 1
    # 2 bands
    numBands = 2
    bandLow[1] = 0
    bandHigh[1] = 1000
    bandLow[2] = 1000
    bandHigh[2] = min(10000, nyquist)
elif band_configuration = 2
    # 4 bands (default)
    numBands = 4
    bandLow[1] = 0
    bandHigh[1] = 500
    bandLow[2] = 500
    bandHigh[2] = 1500
    bandLow[3] = 1500
    bandHigh[3] = 4000
    bandLow[4] = 4000
    bandHigh[4] = min(10000, nyquist)
elif band_configuration = 3
    # 6 bands
    numBands = 6
    bandLow[1] = 0
    bandHigh[1] = 300
    bandLow[2] = 300
    bandHigh[2] = 800
    bandLow[3] = 800
    bandHigh[3] = 1500
    bandLow[4] = 1500
    bandHigh[4] = 3000
    bandLow[5] = 3000
    bandHigh[5] = 6000
    bandLow[6] = 6000
    bandHigh[6] = min(12000, nyquist)
else
    # 8 bands (fine)
    numBands = 8
    bandLow[1] = 0
    bandHigh[1] = 200
    bandLow[2] = 200
    bandHigh[2] = 400
    bandLow[3] = 400
    bandHigh[3] = 800
    bandLow[4] = 800
    bandHigh[4] = 1500
    bandLow[5] = 1500
    bandHigh[5] = 2500
    bandLow[6] = 2500
    bandHigh[6] = 4000
    bandLow[7] = 4000
    bandHigh[7] = 7000
    bandLow[8] = 7000
    bandHigh[8] = min(12000, nyquist)
endif

# Clamp bands to Nyquist
for b from 1 to numBands
    if bandHigh[b] > nyquist
        bandHigh[b] = nyquist
    endif
    if bandLow[b] >= bandHigh[b]
        bandLow[b] = bandHigh[b] - 50
        if bandLow[b] < 0
            bandLow[b] = 0
        endif
    endif
endfor

# ============================================================
# Processing parameters
# ============================================================
targetFrames = floor((targetDur - window_length) / hop_size) + 1
if targetFrames < 1
    targetFrames = 1
endif

snippetHop = hop_size / 2
sourceSnippets = floor((sourceDur - window_length) / snippetHop) + 1
if sourceSnippets < 1
    sourceSnippets = 1
endif

localityRange = max(1, round(locality_window / snippetHop))

# Generate unique ID
uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Convert to mono for analysis (process stereo separately for output)
# ============================================================
if sourceChannels > 1
    selectObject: source
    sourceMono = Convert to mono
else
    selectObject: source
    sourceMono = Copy: "source_mono_" + uniqueID$
endif

if targetChannels > 1
    selectObject: target
    targetMono = Convert to mono
else
    selectObject: target
    targetMono = Copy: "target_mono_" + uniqueID$
endif

# ============================================================
# ANALYSIS: Extract band features
# ============================================================
writeInfoLine: "Band-Based Concatenative Synthesis"
appendInfoLine: "=================================="
appendInfoLine: "Source: ", sourceName$, " (", fixed$(sourceDur, 2), " s)"
appendInfoLine: "Target: ", targetName$, " (", fixed$(targetDur, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Analyzing target (", targetFrames, " frames)..."

# Analyze target
for b from 1 to numBands
    selectObject: targetMono
    targetBand[b] = Filter (pass Hann band): bandLow[b], bandHigh[b], 100
endfor

for k from 1 to targetFrames
    tStart = (k - 1) * hop_size
    tEnd = tStart + window_length
    if tEnd > targetDur
        tEnd = targetDur
    endif
    for b from 1 to numBands
        selectObject: targetBand[b]
        rms = Get root-mean-square: tStart, tEnd
        if rms > 0
            targetFeature[k, b] = ln(rms + 1e-10)
        else
            targetFeature[k, b] = -23
        endif
    endfor
endfor

# Cleanup target band filters
for b from 1 to numBands
    removeObject: targetBand[b]
endfor

appendInfoLine: "Analyzing source (", sourceSnippets, " snippets)..."

# Analyze source
for b from 1 to numBands
    selectObject: sourceMono
    sourceBand[b] = Filter (pass Hann band): bandLow[b], bandHigh[b], 100
endfor

for j from 1 to sourceSnippets
    sStart = (j - 1) * snippetHop
    sEnd = sStart + window_length
    if sEnd > sourceDur
        sEnd = sourceDur
    endif
    for b from 1 to numBands
        selectObject: sourceBand[b]
        rms = Get root-mean-square: sStart, sEnd
        if rms > 0
            sourceFeature[j, b] = ln(rms + 1e-10)
        else
            sourceFeature[j, b] = -23
        endif
    endfor
endfor

# Cleanup source band filters
for b from 1 to numBands
    removeObject: sourceBand[b]
endfor

# ============================================================
# Z-SCORE NORMALIZATION
# ============================================================
for b from 1 to numBands
    # Compute mean
    sum = 0
    for j from 1 to sourceSnippets
        sum += sourceFeature[j, b]
    endfor
    bandMean[b] = sum / sourceSnippets
    
    # Compute std
    varSum = 0
    for j from 1 to sourceSnippets
        diff = sourceFeature[j, b] - bandMean[b]
        varSum += diff * diff
    endfor
    bandStd[b] = sqrt(varSum / sourceSnippets)
    if bandStd[b] < 1e-6
        bandStd[b] = 1
    endif
endfor

# Normalize source features
for j from 1 to sourceSnippets
    for b from 1 to numBands
        sourceFeature[j, b] = (sourceFeature[j, b] - bandMean[b]) / bandStd[b]
    endfor
endfor

# Normalize target features
for k from 1 to targetFrames
    for b from 1 to numBands
        targetFeature[k, b] = (targetFeature[k, b] - bandMean[b]) / bandStd[b]
    endfor
endfor

# ============================================================
# COMPUTE LAMBDA (continuity weight scaling)
# ============================================================
sampleSize = min(100, targetFrames * 2)
for s from 1 to sampleSize
    kSamp = randomInteger(1, targetFrames)
    jSamp = randomInteger(1, sourceSnippets)
    distSum = 0
    for b from 1 to numBands
        diff = targetFeature[kSamp, b] - sourceFeature[jSamp, b]
        distSum += diff * diff
    endfor
    sampleDist[s] = sqrt(distSum)
endfor

# Simple median via sorting
for i from 1 to sampleSize - 1
    for j from 1 to sampleSize - i
        if sampleDist[j] > sampleDist[j + 1]
            temp = sampleDist[j]
            sampleDist[j] = sampleDist[j + 1]
            sampleDist[j + 1] = temp
        endif
    endfor
endfor
medianDist = sampleDist[floor(sampleSize / 2) + 1]
lambda = continuity_weight * medianDist

# ============================================================
# MATCHING: Find best source snippet for each target frame
# ============================================================
appendInfoLine: "Matching frames..."

prevMatch = 1
totalMatchDist = 0
uniqueMatches = 0

for k from 1 to targetFrames
    bestJ = 1
    bestCost = 1e10
    
    # Define search range
    if k = 1
        jMin = 1
        jMax = sourceSnippets
    else
        jMin = max(1, prevMatch - localityRange)
        jMax = min(sourceSnippets, prevMatch + localityRange)
    endif
    
    # Search for best match
    for j from jMin to jMax
        # Compute spectral distance
        distSum = 0
        for b from 1 to numBands
            diff = targetFeature[k, b] - sourceFeature[j, b]
            distSum += diff * diff
        endfor
        dist = sqrt(distSum)
        
        # Add continuity penalty
        if k = 1
            cost = dist
        else
            posJ = (j - 1) * snippetHop
            posPrev = (prevMatch - 1) * snippetHop
            timeJump = abs((posJ - posPrev) - hop_size)
            cost = dist + lambda * timeJump
        endif
        
        if cost < bestCost
            bestCost = cost
            bestJ = j
        endif
    endfor
    
    match[k] = bestJ
    matchDist[k] = bestCost
    totalMatchDist += bestCost
    prevMatch = bestJ
endfor

# Count unique matches
for j from 1 to sourceSnippets
    matchUsed[j] = 0
endfor
for k from 1 to targetFrames
    matchUsed[match[k]] = 1
endfor
for j from 1 to sourceSnippets
    uniqueMatches += matchUsed[j]
endfor

avgMatchDist = totalMatchDist / targetFrames
coveragePercent = (uniqueMatches / sourceSnippets) * 100

# ============================================================
# Procedure: Synthesize one channel
# ============================================================
procedure synthesizeChannel: .sourceSound, .outputName$
    selectObject: .sourceSound
    .sDur = Get total duration
    
    # Create master window
    Create Sound from formula: "win_" + uniqueID$, 1, 0, window_length, sampleRate, "0.5 * (1 - cos(2 * pi * x / 'window_length'))"
    .winSound = selected("Sound")
    
    # Create output sound matching target duration
    Create Sound from formula: .outputName$, 1, 0, targetDur, sampleRate, "0"
    .outputSound = selected("Sound")
    
    # Process each target frame
    for k from 1 to targetFrames
        j = match[k]
        grainStart = (j - 1) * snippetHop
        grainEnd = grainStart + window_length
        
        if grainEnd > .sDur
            grainEnd = .sDur
        endif
        
        actualGrainDur = grainEnd - grainStart
        
        if actualGrainDur > 0.001
            # Extract grain from source
            selectObject: .sourceSound
            .grain = Extract part: grainStart, grainEnd, "rectangular", 1, "no"
            
            # Pad if necessary
            selectObject: .grain
            .gDur = Get total duration
            if .gDur < window_length - 0.001
                # Pad with silence
                paddingDur = window_length - .gDur
                Create Sound from formula: "pad_" + uniqueID$, 1, 0, paddingDur, sampleRate, "0"
                .padSound = selected("Sound")
                selectObject: .grain, .padSound
                .paddedGrain = Concatenate
                removeObject: .grain, .padSound
                .grain = .paddedGrain
            endif
            
            # Apply window
            selectObject: .grain
            Formula: "self * Sound_win_'uniqueID$'(x)"
            Rename: "grain_" + uniqueID$
            
            # Add to output at correct position
            outputStart = (k - 1) * hop_size
            
            selectObject: .outputSound
            Formula: "if x >= 'outputStart' and x < 'outputStart' + 'window_length' then self + Sound_grain_'uniqueID$'(x - 'outputStart') else self endif"
            
            removeObject: .grain
        endif
    endfor
    
    removeObject: .winSound
    selectObject: .outputSound
endproc

# ============================================================
# SYNTHESIS
# ============================================================
appendInfoLine: "Synthesizing..."

# Process based on channel configuration
maxChannels = max(sourceChannels, targetChannels)

if maxChannels = 1
    # Mono processing
    @synthesizeChannel: sourceMono, "output_mono_" + uniqueID$
    finalOutput = selected("Sound")
else
    # Stereo processing
    if sourceChannels > 1
        selectObject: source
        Extract one channel: 1
        sourceL = selected("Sound")
        selectObject: source
        Extract one channel: 2
        sourceR = selected("Sound")
    else
        selectObject: source
        sourceL = Copy: "sourceL_" + uniqueID$
        selectObject: source
        sourceR = Copy: "sourceR_" + uniqueID$
    endif
    
    @synthesizeChannel: sourceL, "output_L_" + uniqueID$
    outputL = selected("Sound")
    
    @synthesizeChannel: sourceR, "output_R_" + uniqueID$
    outputR = selected("Sound")
    
    selectObject: outputL, outputR
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: sourceL, sourceR, outputL, outputR
endif

# ============================================================
# Apply dry/wet mix with target
# ============================================================
if dry_wet_mix < 1
    # Need to mix with target
    if maxChannels = 1
        selectObject: targetMono
        Rename: "target_mix_" + uniqueID$
    else
        if targetChannels > 1
            selectObject: target
            targetMix = Copy: "target_mix_" + uniqueID$
        else
            # Duplicate mono to stereo
            selectObject: target
            targetL = Copy: "targetL_" + uniqueID$
            selectObject: target
            targetR = Copy: "targetR_" + uniqueID$
            selectObject: targetL, targetR
            Combine to stereo
            targetMix = selected("Sound")
            removeObject: targetL, targetR
        endif
        Rename: "target_mix_" + uniqueID$
    endif
    
    selectObject: finalOutput
    Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_target_mix_'uniqueID$'(x)"
    
    selectObject: "Sound target_mix_" + uniqueID$
    Remove
endif

# ============================================================
# Finalize output
# ============================================================
selectObject: finalOutput
Scale peak: scale_peak
Rename: sourceName$ + "_concat_" + targetName$

# Cleanup analysis mono copies
removeObject: sourceMono, targetMono

# ============================================================
# Visualization
# ============================================================
procedure drawVisualization
    Erase all
    
    # Smart tick intervals
    if targetDur > 10
        timeTickInterval = 2
    elsif targetDur > 5
        timeTickInterval = 1
    elsif targetDur > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # ========================================================
    # PANEL 1: Match trajectory (top)
    # ========================================================
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.7, 5.8, 0.5, 2.6
    
    Axes: 0, targetDur, 0, sourceDur
    
    # Draw diagonal reference (perfect time alignment)
    Colour: "{0.85, 0.85, 0.85}"
    minDur = min(targetDur, sourceDur)
    Draw line: 0, 0, minDur, minDur
    
    # Draw match trajectory as connected line
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    
    for k from 1 to targetFrames - 1
        tTime1 = (k - 1) * hop_size
        tTime2 = k * hop_size
        sTime1 = (match[k] - 1) * snippetHop
        sTime2 = (match[k + 1] - 1) * snippetHop
        Draw line: tTime1, sTime1, tTime2, sTime2
    endfor
    
    # Draw match points as small crosses
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 1
    pointSize = min(targetDur, sourceDur) * 0.008
    
    for k from 1 to targetFrames
        tTime = (k - 1) * hop_size
        sTime = (match[k] - 1) * snippetHop
        # Draw small cross
        Draw line: tTime - pointSize, sTime, tTime + pointSize, sTime
        Draw line: tTime, sTime - pointSize, tTime, sTime + pointSize
    endfor
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Target time (s)"
    Text left: "yes", "Source time (s)"
    Text top: "no", "##Match Trajectory## - " + sourceName$ + " -> " + targetName$
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    if sourceDur > 10
        sourceTickInterval = 2
    elsif sourceDur > 5
        sourceTickInterval = 1
    elsif sourceDur > 2
        sourceTickInterval = 0.5
    else
        sourceTickInterval = 0.25
    endif
    Marks left every: 1, sourceTickInterval, "yes", "yes", "no"
    
    # ========================================================
    # PANEL 2: Match distance over time (bottom)
    # ========================================================
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.7, 5.8, 3.5, 5.6
    
    # Find max distance for scaling
    maxDist = 0
    for k from 1 to targetFrames
        if matchDist[k] > maxDist
            maxDist = matchDist[k]
        endif
    endfor
    if maxDist < 0.1
        maxDist = 0.1
    endif
    
    Axes: 0, targetDur, 0, maxDist * 1.1
    
    # Draw average line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, avgMatchDist, targetDur, avgMatchDist
    Solid line
    
    # Draw distance curve
    Colour: "{0.2, 0.6, 0.3}"
    Line width: 2
    
    for k from 1 to targetFrames - 1
        tTime1 = (k - 1) * hop_size
        tTime2 = k * hop_size
        Draw line: tTime1, matchDist[k], tTime2, matchDist[k + 1]
    endfor
    
    Line width: 1
    Black
    
    Draw inner box
    Text bottom: "yes", "Target time (s)"
    Text left: "yes", "Match cost"
    Text top: "no", "##Match Quality## (avg: " + fixed$(avgMatchDist, 2) + ", coverage: " + fixed$(coveragePercent, 0) + "%)"
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    if maxDist > 2
        distTickInterval = 1
    elsif maxDist > 1
        distTickInterval = 0.5
    else
        distTickInterval = 0.2
    endif
    Marks left every: 1, distTickInterval, "yes", "yes", "no"
endproc

if draw_visualization
    @drawVisualization
endif

# ============================================================
# Select final output
# ============================================================
selectObject: finalOutput

# ============================================================
# Play if requested
# ============================================================
if play_after_processing
    Play
endif

# ============================================================
# Report completion
# ============================================================
appendInfoLine: ""
appendInfoLine: "=================================="
appendInfoLine: "Synthesis complete!"
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Preset: ", preset$
appendInfoLine: "  Window: ", fixed$(window_length * 1000, 1), " ms"
appendInfoLine: "  Hop: ", fixed$(hop_size * 1000, 1), " ms"
appendInfoLine: "  Bands: ", numBands
appendInfoLine: "  Continuity: ", fixed$(continuity_weight, 2)
appendInfoLine: "  Locality: ", fixed$(locality_window, 2), " s"
appendInfoLine: "  Dry/wet: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: ""
appendInfoLine: "Statistics:"
appendInfoLine: "  Target frames: ", targetFrames
appendInfoLine: "  Source snippets: ", sourceSnippets
appendInfoLine: "  Unique matches: ", uniqueMatches, " (", fixed$(coveragePercent, 1), "% coverage)"
appendInfoLine: "  Avg match cost: ", fixed$(avgMatchDist, 3)
appendInfoLine: "  Lambda: ", fixed$(lambda, 3)
appendInfoLine: ""
appendInfoLine: "Output: ", sourceName$, "_concat_", targetName$
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Visualization in Picture window."
endif