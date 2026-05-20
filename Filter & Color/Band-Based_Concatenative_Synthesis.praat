# ============================================================
# Praat AudioTools - Band-Based_Concatenative_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Concatenative synthesis using multi-band spectral matching.
#   Reconstructs target audio using segments from source audio.
#   Matching runs on a mono fold-down; synthesis is per-channel
#   so the source's stereo image is preserved.
#
# Changelog v0.4:
#   TIER 1 (polish, audio bit-identical):
#     - Dropped 4 decorative `comment === ... ===` form rows
#       (Temporal Parameters / Frequency Bands / Matching
#       Parameters / Output).
#     - Visualization rewritten from custom 6x6 (2 panels) to
#       suite 8x8:
#         Title bar (suite light) + metadata subtitle
#         Match trajectory  (full width, signature)
#         Match cost over time (full width)
#         Output waveform   (full width)
#         Light-grey 3-line summary (suite standard)
#       The two original panels (match trajectory, match cost)
#       are preserved in content; the output waveform panel and
#       summary bar are new.
#
#   TIER 2 (correctness, audio change only in the affected paths):
#     - FIXED: stereo dry/wet mix collapsed the dry signal to a
#       single channel. v0.3 line 596 used
#         dryWet * self + dryAmount * Object_<targetMix>(x)
#       The `Object_id(x)` time-interpolation function's channel
#       behavior for a multichannel referenced object is
#       version-dependent (may use channel 1 or the channel mean
#       rather than the channel currently being computed). So on
#       stereo output the dry (target) component could be folded
#       to mono and added to both channels. v0.4 uses the
#       explicit index form `object[<targetMix>, row, col]`, which
#       is unambiguous and per-channel. finalOutput and targetMix
#       are sample-aligned by construction (both targetDur at the
#       same sample rate, both starting at t=0), so index access
#       is exact -- no interpolation needed. Only affects runs
#       with dry_wet_mix < 1 on stereo material; the default
#       dry_wet_mix = 1.0 skips this block entirely, so default
#       output is bit-identical to v0.3.
#     - PORTABILITY: the grain-placement Formula terminator
#       `endif` (v0.3 line 508) changed to `fi`. `fi` is the
#       canonical Praat *Formula* conditional terminator;
#       `endif` is the script-level block terminator. Both happen
#       to work in current Praat 6.x Formula strings, but `fi` is
#       the portable form. No behavior change.
#
#   Variable indirection (var_'i'_'b' pseudo-arrays) left as-is;
#   modernizing to matrices is a separate refactor.
#
# Changelog v0.3:
#   - Fixed preset comparison (number not string)
#   - Fixed all array syntax for Praat compatibility
#   - Fixed Formula variable interpolation
#   - Added preset name to output
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects: Source (1) and Target (2)"
endif

source = selected("Sound", 1)
target = selected("Sound", 2)

form Band-Based Concatenative Synthesis v0.4
    optionmenu Preset: 1
        option Manual
        option Subtle Morph
        option Granular Texture
        option Spectral Match
        option Rhythmic Mosaic
        option Smooth Blend
    positive Window_length 0.060
    positive Hop_size 0.030
    optionmenu Band_configuration: 2
        option 2 bands (low/high)
        option 4 bands (default)
        option 6 bands (detailed)
        option 8 bands (fine)
    real Continuity_weight 0.3
    positive Locality_window 0.4
    real Dry_wet_mix 1.0
    positive Scale_peak 0.95
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets (fixed: use number not string)
# ============================================================
if preset = 2
    window_length = 0.080
    hop_size = 0.040
    continuity_weight = 0.5
    locality_window = 0.6
    presetName$ = "SubtleMorph"
elsif preset = 3
    window_length = 0.040
    hop_size = 0.020
    continuity_weight = 0.15
    locality_window = 0.3
    presetName$ = "GranularTexture"
elsif preset = 4
    window_length = 0.050
    hop_size = 0.025
    continuity_weight = 0.35
    locality_window = 0.4
    presetName$ = "SpectralMatch"
elsif preset = 5
    window_length = 0.100
    hop_size = 0.050
    continuity_weight = 0.7
    locality_window = 0.8
    presetName$ = "RhythmicMosaic"
elsif preset = 6
    window_length = 0.120
    hop_size = 0.060
    continuity_weight = 0.6
    locality_window = 1.0
    presetName$ = "SmoothBlend"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
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

if sourceSR <> targetSR
    exitScript: "Sample rates must match (" + string$(sourceSR) + " vs " + string$(targetSR) + ")"
endif

sampleRate = sourceSR
nyquist = sampleRate / 2

# OLA constraint
ratio = window_length / hop_size
intRatio = round(ratio)
if abs(ratio - intRatio) > 0.01
    hop_size = window_length / intRatio
endif
numStreams = intRatio

# ============================================================
# Set up frequency bands (fixed: Praat array syntax)
# ============================================================
if band_configuration = 1
    numBands = 2
    bandLow_1 = 0
    bandHigh_1 = 1000
    bandLow_2 = 1000
    bandHigh_2 = min(10000, nyquist)
elsif band_configuration = 2
    numBands = 4
    bandLow_1 = 0
    bandHigh_1 = 500
    bandLow_2 = 500
    bandHigh_2 = 1500
    bandLow_3 = 1500
    bandHigh_3 = 4000
    bandLow_4 = 4000
    bandHigh_4 = min(10000, nyquist)
elsif band_configuration = 3
    numBands = 6
    bandLow_1 = 0
    bandHigh_1 = 300
    bandLow_2 = 300
    bandHigh_2 = 800
    bandLow_3 = 800
    bandHigh_3 = 1500
    bandLow_4 = 1500
    bandHigh_4 = 3000
    bandLow_5 = 3000
    bandHigh_5 = 6000
    bandLow_6 = 6000
    bandHigh_6 = min(12000, nyquist)
else
    numBands = 8
    bandLow_1 = 0
    bandHigh_1 = 200
    bandLow_2 = 200
    bandHigh_2 = 400
    bandLow_3 = 400
    bandHigh_3 = 800
    bandLow_4 = 800
    bandHigh_4 = 1500
    bandLow_5 = 1500
    bandHigh_5 = 2500
    bandLow_6 = 2500
    bandHigh_6 = 4000
    bandLow_7 = 4000
    bandHigh_7 = 7000
    bandLow_8 = 7000
    bandHigh_8 = min(12000, nyquist)
endif

# Clamp bands to Nyquist
for b from 1 to numBands
    bHigh = bandHigh_'b'
    bLow = bandLow_'b'
    if bHigh > nyquist
        bandHigh_'b' = nyquist
    endif
    if bLow >= bandHigh_'b'
        bandLow_'b' = bandHigh_'b' - 50
        if bandLow_'b' < 0
            bandLow_'b' = 0
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

# ============================================================
# Convert to mono for analysis
# ============================================================
clearinfo
writeInfoLine: "=== Band-Based Concatenative Synthesis v0.4 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Source: ", sourceName$, " (", fixed$(sourceDur, 2), " s)"
appendInfoLine: "Target: ", targetName$, " (", fixed$(targetDur, 2), " s)"
appendInfoLine: ""

if sourceChannels > 1
    selectObject: source
    sourceMono = Convert to mono
else
    selectObject: source
    sourceMono = Copy: "source_mono"
endif

if targetChannels > 1
    selectObject: target
    targetMono = Convert to mono
else
    selectObject: target
    targetMono = Copy: "target_mono"
endif

# ============================================================
# ANALYSIS: Extract band features
# ============================================================
appendInfoLine: "Analyzing target (", targetFrames, " frames)..."

# Create target band filters
for b from 1 to numBands
    bLow = bandLow_'b'
    bHigh = bandHigh_'b'
    selectObject: targetMono
    Filter (pass Hann band): bLow, bHigh, 100
    targetBand_'b' = selected("Sound")
endfor

# Extract target features
for k from 1 to targetFrames
    tStart = (k - 1) * hop_size
    tEnd = tStart + window_length
    if tEnd > targetDur
        tEnd = targetDur
    endif
    for b from 1 to numBands
        selectObject: targetBand_'b'
        rms = Get root-mean-square: tStart, tEnd
        if rms > 0
            targetFeature_'k'_'b' = ln(rms + 1e-10)
        else
            targetFeature_'k'_'b' = -23
        endif
    endfor
endfor

# Cleanup target band filters
for b from 1 to numBands
    removeObject: targetBand_'b'
endfor

appendInfoLine: "Analyzing source (", sourceSnippets, " snippets)..."

# Create source band filters
for b from 1 to numBands
    bLow = bandLow_'b'
    bHigh = bandHigh_'b'
    selectObject: sourceMono
    Filter (pass Hann band): bLow, bHigh, 100
    sourceBand_'b' = selected("Sound")
endfor

# Extract source features
for j from 1 to sourceSnippets
    sStart = (j - 1) * snippetHop
    sEnd = sStart + window_length
    if sEnd > sourceDur
        sEnd = sourceDur
    endif
    for b from 1 to numBands
        selectObject: sourceBand_'b'
        rms = Get root-mean-square: sStart, sEnd
        if rms > 0
            sourceFeature_'j'_'b' = ln(rms + 1e-10)
        else
            sourceFeature_'j'_'b' = -23
        endif
    endfor
endfor

# Cleanup source band filters
for b from 1 to numBands
    removeObject: sourceBand_'b'
endfor

# ============================================================
# Z-SCORE NORMALIZATION
# ============================================================
for b from 1 to numBands
    # Compute mean
    sum = 0
    for j from 1 to sourceSnippets
        sum = sum + sourceFeature_'j'_'b'
    endfor
    bandMean_'b' = sum / sourceSnippets
    
    # Compute std
    varSum = 0
    bMean = bandMean_'b'
    for j from 1 to sourceSnippets
        diff = sourceFeature_'j'_'b' - bMean
        varSum = varSum + diff * diff
    endfor
    bandStd_'b' = sqrt(varSum / sourceSnippets)
    if bandStd_'b' < 1e-6
        bandStd_'b' = 1
    endif
endfor

# Normalize source features
for j from 1 to sourceSnippets
    for b from 1 to numBands
        bMean = bandMean_'b'
        bStd = bandStd_'b'
        val = sourceFeature_'j'_'b'
        sourceFeature_'j'_'b' = (val - bMean) / bStd
    endfor
endfor

# Normalize target features
for k from 1 to targetFrames
    for b from 1 to numBands
        bMean = bandMean_'b'
        bStd = bandStd_'b'
        val = targetFeature_'k'_'b'
        targetFeature_'k'_'b' = (val - bMean) / bStd
    endfor
endfor

# ============================================================
# COMPUTE LAMBDA
# ============================================================
sampleSize = min(100, targetFrames * 2)
for s from 1 to sampleSize
    kSamp = randomInteger(1, targetFrames)
    jSamp = randomInteger(1, sourceSnippets)
    distSum = 0
    for b from 1 to numBands
        tFeat = targetFeature_'kSamp'_'b'
        sFeat = sourceFeature_'jSamp'_'b'
        diff = tFeat - sFeat
        distSum = distSum + diff * diff
    endfor
    sampleDist_'s' = sqrt(distSum)
endfor

# Simple sort for median
for i from 1 to sampleSize - 1
    for jj from 1 to sampleSize - i
        jj1 = jj + 1
        d1 = sampleDist_'jj'
        d2 = sampleDist_'jj1'
        if d1 > d2
            sampleDist_'jj' = d2
            sampleDist_'jj1' = d1
        endif
    endfor
endfor
medIdx = floor(sampleSize / 2) + 1
medianDist = sampleDist_'medIdx'
lambda = continuity_weight * medianDist

# ============================================================
# MATCHING
# ============================================================
appendInfoLine: "Matching frames..."

prevMatch = 1
totalMatchDist = 0

for k from 1 to targetFrames
    bestJ = 1
    bestCost = 1e10
    
    if k = 1
        jMin = 1
        jMax = sourceSnippets
    else
        jMin = max(1, prevMatch - localityRange)
        jMax = min(sourceSnippets, prevMatch + localityRange)
    endif
    
    for j from jMin to jMax
        distSum = 0
        for b from 1 to numBands
            tFeat = targetFeature_'k'_'b'
            sFeat = sourceFeature_'j'_'b'
            diff = tFeat - sFeat
            distSum = distSum + diff * diff
        endfor
        dist = sqrt(distSum)
        
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
    
    match_'k' = bestJ
    matchDist_'k' = bestCost
    totalMatchDist = totalMatchDist + bestCost
    prevMatch = bestJ
endfor

# Count unique matches
for j from 1 to sourceSnippets
    matchUsed_'j' = 0
endfor
for k from 1 to targetFrames
    mIdx = match_'k'
    matchUsed_'mIdx' = 1
endfor
uniqueMatches = 0
for j from 1 to sourceSnippets
    uniqueMatches = uniqueMatches + matchUsed_'j'
endfor

avgMatchDist = totalMatchDist / targetFrames
coveragePercent = (uniqueMatches / sourceSnippets) * 100

# ============================================================
# Synthesis Procedure
# ============================================================
procedure synthesizeChannel: .sourceSound, .outputName$
    selectObject: .sourceSound
    .sDur = Get total duration
    
    # Create window
    winLen$ = string$(window_length)
    Create Sound from formula: "synth_window", 1, 0, window_length, sampleRate, "0.5 * (1 - cos(2 * pi * x / " + winLen$ + "))"
    .winSound = selected("Sound")
    .winId$ = string$(.winSound)
    
    # Create output
    Create Sound from formula: .outputName$, 1, 0, targetDur, sampleRate, "0"
    .outputSound = selected("Sound")
    .outputId$ = string$(.outputSound)
    
    for k from 1 to targetFrames
        j = match_'k'
        grainStart = (j - 1) * snippetHop
        grainEnd = grainStart + window_length
        
        if grainEnd > .sDur
            grainEnd = .sDur
        endif
        
        actualGrainDur = grainEnd - grainStart
        
        if actualGrainDur > 0.001
            selectObject: .sourceSound
            .grain = Extract part: grainStart, grainEnd, "rectangular", 1, "no"
            .grainId$ = string$(.grain)
            
            # Pad if necessary
            selectObject: .grain
            .gDur = Get total duration
            if .gDur < window_length - 0.001
                paddingDur = window_length - .gDur
                Create Sound from formula: "padding", 1, 0, paddingDur, sampleRate, "0"
                .padSound = selected("Sound")
                selectObject: .grain
                plusObject: .padSound
                .paddedGrain = Concatenate
                removeObject: .grain, .padSound
                .grain = .paddedGrain
                .grainId$ = string$(.grain)
            endif
            
            # Apply window
            selectObject: .grain
            Formula: "self * Object_" + .winId$ + "(x)"
            
            # Add to output
            outputStart = (k - 1) * hop_size
            outputStart$ = string$(outputStart)
            winLen$ = string$(window_length)
            
            selectObject: .outputSound
            Formula: "if x >= " + outputStart$ + " and x < " + outputStart$ + " + " + winLen$ + " then self + Object_" + .grainId$ + "(x - " + outputStart$ + ") else self fi"
            
            removeObject: .grain
        endif
        
        if k mod 50 = 0
            appendInfo: "."
        endif
    endfor
    
    removeObject: .winSound
    selectObject: .outputSound
endproc

# ============================================================
# SYNTHESIS
# ============================================================
appendInfoLine: ""
appendInfoLine: "Synthesizing..."

maxChannels = max(sourceChannels, targetChannels)

if maxChannels = 1
    @synthesizeChannel: sourceMono, "output_mono"
    finalOutput = selected("Sound")
else
    if sourceChannels > 1
        selectObject: source
        Extract one channel: 1
        sourceL = selected("Sound")
        selectObject: source
        Extract one channel: 2
        sourceR = selected("Sound")
    else
        selectObject: source
        sourceL = Copy: "sourceL"
        selectObject: source
        sourceR = Copy: "sourceR"
    endif
    
    appendInfo: "L"
    @synthesizeChannel: sourceL, "output_L"
    outputL = selected("Sound")
    
    appendInfoLine: ""
    appendInfo: "R"
    @synthesizeChannel: sourceR, "output_R"
    outputR = selected("Sound")
    
    selectObject: outputL
    plusObject: outputR
    Combine to stereo
    finalOutput = selected("Sound")
    
    removeObject: sourceL, sourceR, outputL, outputR
endif

appendInfoLine: " done"

# ============================================================
# Dry/wet mix
# ============================================================
if dry_wet_mix < 1
    if maxChannels = 1
        selectObject: targetMono
        targetMixId$ = string$(targetMono)
    else
        if targetChannels > 1
            selectObject: target
            targetMix = Copy: "target_mix"
        else
            selectObject: target
            targetL = Copy: "targetL"
            selectObject: target
            targetR = Copy: "targetR"
            selectObject: targetL
            plusObject: targetR
            Combine to stereo
            targetMix = selected("Sound")
            removeObject: targetL, targetR
        endif
        targetMixId$ = string$(targetMix)
    endif
    
    dryWet$ = string$(dry_wet_mix)
    dryAmount$ = string$(1 - dry_wet_mix)
    
    # v0.4: explicit per-channel index access. v0.3 used
    # Object_<id>(x) (time interpolation), whose channel behavior
    # for a multichannel referenced object is version-dependent
    # (could fold the dry signal to mono on stereo output).
    # finalOutput and targetMix are sample-aligned by construction
    # (same duration, sample rate, and t=0 origin), so object[id,
    # row, col] is exact and per-channel.
    selectObject: finalOutput
    Formula: dryWet$ + " * self + " + dryAmount$ + " * object[" + targetMixId$ + ", row, col]"
    
    if maxChannels > 1
        removeObject: targetMix
    endif
endif

# ============================================================
# Finalize
# ============================================================
selectObject: finalOutput
Scale peak: scale_peak
Rename: sourceName$ + "_concat_" + targetName$ + "_" + presetName$

removeObject: sourceMono, targetMono

# ============================================================
# Visualization
# ============================================================
###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Match trajectory       (full width, signature)
# Panel B: Match cost over time    (full width)
# Panel C: Output waveform         (full width)
# Panel D: Light-grey 3-line summary
###############################################################################
procedure drawVisualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line
    
    if targetDur > 10
        timeTickInterval = 2
    elsif targetDur > 5
        timeTickInterval = 1
    elsif targetDur > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BAND-BASED CONCATENATIVE SYNTHESIS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... sourceName$ + " -> " + targetName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(numBands) + " bands"
        ... + "  |  win " + fixed$(window_length * 1000, 0) + " ms / hop " + fixed$(hop_size * 1000, 0) + " ms"
        ... + "  |  " + string$(targetFrames) + " frames"
    
    # ----------------------------------------------------------
    # PANEL A: MATCH TRAJECTORY  (full width, signature)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 3.05
    Select inner viewport: 0.70, 7.72, 0.95, 2.90
    
    Axes: 0, targetDur, 0, sourceDur
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, targetDur, 0, sourceDur
    
    # Diagonal reference (where target time = source time)
    Colour: "{0.82, 0.82, 0.86}"
    minDur = min(targetDur, sourceDur)
    Draw line: 0, 0, minDur, minDur
    
    # Match trajectory line
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 2
    for k from 1 to targetFrames - 1
        tTime1 = (k - 1) * hop_size
        tTime2 = k * hop_size
        m1 = match_'k'
        k1 = k + 1
        m2 = match_'k1'
        sTime1 = (m1 - 1) * snippetHop
        sTime2 = (m2 - 1) * snippetHop
        Draw line: tTime1, sTime1, tTime2, sTime2
    endfor
    
    # Match points (small crosses)
    Colour: "{0.80, 0.25, 0.25}"
    Line width: 1
    pointSize = min(targetDur, sourceDur) * 0.008
    for k from 1 to targetFrames
        tTime = (k - 1) * hop_size
        mIdx = match_'k'
        sTime = (mIdx - 1) * snippetHop
        Draw line: tTime - pointSize, sTime, tTime + pointSize, sTime
        Draw line: tTime, sTime - pointSize, tTime, sTime + pointSize
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Match trajectory  (grey diagonal = identity; blue = source position chosen per target frame)"
    Text left: "yes", "Source time (s)"
    Text bottom: "yes", "Target time (s)"
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
    
    # ----------------------------------------------------------
    # PANEL B: MATCH COST OVER TIME  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.15, 4.45
    Select inner viewport: 0.70, 7.72, 3.30, 4.38
    
    maxDist = 0
    for k from 1 to targetFrames
        d = matchDist_'k'
        if d > maxDist
            maxDist = d
        endif
    endfor
    if maxDist < 0.1
        maxDist = 0.1
    endif
    
    Axes: 0, targetDur, 0, maxDist * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, targetDur, 0, maxDist * 1.1
    
    # Average reference line
    Colour: "{0.70, 0.70, 0.72}"
    Dotted line
    Draw line: 0, avgMatchDist, targetDur, avgMatchDist
    Solid line
    
    # Cost curve
    Colour: "{0.20, 0.60, 0.35}"
    Line width: 2
    for k from 1 to targetFrames - 1
        tTime1 = (k - 1) * hop_size
        tTime2 = k * hop_size
        d1 = matchDist_'k'
        k1 = k + 1
        d2 = matchDist_'k1'
        Draw line: tTime1, d1, tTime2, d2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Match cost per frame  (dotted = mean " + fixed$(avgMatchDist, 2) + ")"
    Text left: "yes", "Cost"
    Text bottom: "yes", "Target time (s)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    if maxDist > 2
        distTickInterval = 1
    elsif maxDist > 1
        distTickInterval = 0.5
    else
        distTickInterval = 0.2
    endif
    Marks left every: 1, distTickInterval, "yes", "yes", "no"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.55, 5.55
    Select inner viewport: 0.70, 7.72, 4.70, 5.48
    
    # Mono fold-down for a clean single trace
    selectObject: finalOutput
    vizNumCh = Get number of channels
    if vizNumCh > 1
        vizWave = Convert to mono
    else
        vizWave = Copy: "viz_wave"
    endif
    selectObject: vizWave
    vizPeak = Get absolute extremum: 0, 0, "None"
    if vizPeak < 0.001
        vizPeak = 0.001
    endif
    vizAmp = vizPeak * 1.15
    
    Axes: 0, targetDur, -vizAmp, vizAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, targetDur, -vizAmp, vizAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, targetDur, 0
    
    selectObject: vizWave
    Colour: "{0.25, 0.40, 0.65}"
    Line width: 1
    Draw: 0, targetDur, -vizAmp, vizAmp, "no", "Curve"
    removeObject: vizWave
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.30
    Select inner viewport: 0.70, 7.72, 5.68, 6.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if dry_wet_mix < 1
        mixStr$ = fixed$(dry_wet_mix * 100, 0) + "% wet / " + fixed$((1 - dry_wet_mix) * 100, 0) + "% dry"
    else
        mixStr$ = "100% wet"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.78, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sourceName$ + " -> " + targetName$
        ... + "  |  " + string$(numBands) + " bands"
        ... + "  |  win " + fixed$(window_length * 1000, 0) + " ms, hop " + fixed$(hop_size * 1000, 0) + " ms"
        ... + "  |  continuity " + fixed$(continuity_weight, 2)
        ... + "  |  locality " + fixed$(locality_window, 1) + " s"
    
    Text: 0.02, "left", 0.30, "half",
        ... "Target frames: " + string$(targetFrames)
        ... + "  |  Source snippets: " + string$(sourceSnippets)
        ... + "  |  Unique matches: " + string$(uniqueMatches) + " (" + fixed$(coveragePercent, 1) + "% coverage)"
        ... + "  |  Avg cost: " + fixed$(avgMatchDist, 3)
        ... + "  |  Mix: " + mixStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc

if draw_visualization
    @drawVisualization
endif

# ============================================================
# Output
# ============================================================
selectObject: source
plusObject: target
plusObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: ""
appendInfoLine: "Stats:"
appendInfoLine: "  Target frames: ", targetFrames
appendInfoLine: "  Source snippets: ", sourceSnippets
appendInfoLine: "  Unique matches: ", uniqueMatches, " (", fixed$(coveragePercent, 1), "% coverage)"
appendInfoLine: "  Avg match cost: ", fixed$(avgMatchDist, 3)

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput