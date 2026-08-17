# ============================================================
# Praat AudioTools - Musikalisches Würfelspiel (Musical Dice Game)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.2 (2026)
# License: MIT License
#
# Description:
#   A timbre-guided audio dice game. The source is divided into equal
#   time slices. Each slice receives a composite "tension" score from
#   intensity, log-pitch (when voiced), and spectral centre of gravity.
#   Slices are rank-balanced into four game roles:
#      T = tonic-like, P = predominant-like,
#      D = dominant-like, C = cadence-like.
#   These labels are an acoustic/compositional analogy. They are NOT
#   harmonic analysis and do not identify tonal function.
#
#   The output follows a T-P-D-C role cycle (with a final C forced for
#   incomplete cycles), while a dice-like random choice selects among
#   source slices assigned to each role.
#
# Changelog v1.2:
#   - Phase-safe multichannel workflow: analysis uses the strongest source
#     channel, while output slices preserve ALL original channels.
#   - Fixed anti-phase stereo cancellation caused by Convert to mono.
#   - Replaced quartile-threshold classification with exact rank-balanced
#     role allocation matched to the number of output T/P/D/C slots.
#     Ties are broken by the game RNG, so identical material is not
#     falsely claimed to contain acoustic distinctions.
#   - Added Random seed (0 = unpredictable; nonzero = reproducible).
#   - Pitch feature is normalized in semitone/log-frequency space rather
#     than linear Hz; unvoiced slices still exclude pitch locally.
#   - Custom feature weights may now be zero; all-zero weighting is rejected.
#   - Custom expression parameters are validated (ritardando >= 1,
#     diminuendo in 0..1).
#   - Very short slices are prevented by reducing the requested slice count
#     when necessary; inputs shorter than 0.24 s are rejected.
#   - Cadential expression follows the actual C-role positions, including
#     a forced final C for non-multiples of four.
#   - Stereo/multichannel ritardando is processed channel-by-channel and
#     recombined, preserving channel count instead of folding to mono.
#   - Uses a 5 ms overlap when concatenating to reduce hard-cut clicks.
#   - Visualization now shows measured source tension/roles and the actual
#     source-to-output permutation instead of a decorative role grid only.
# ============================================================

# ---- INPUT ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
originalSoundName$ = selected$("Sound")

# ---- FORM ----
form Musikalisches Würfelspiel v1.2
    comment === PRESETS ===
    optionmenu Preset 1
        option Custom
        option Classical (16 segments, balanced)
        option Baroque (8 segments, pitch-focused)
        option Romantic (16 segments, expressive)
        option Minimal (4 segments, simple)
        option Dense (32 segments, complex)

    comment === SOURCE SLICING / DICE ===
    natural Number_of_segments 16
    integer Random_seed 0
    boolean Allow_segment_reuse 0

    comment === FEATURE WEIGHTING ===
    real Intensity_weight 1.0
    real Spectral_weight 1.0
    real Pitch_weight 0.5

    comment === CADENTIAL EXPRESSION ===
    boolean Apply_ritardando 1
    real Ritardando_moderate 1.15
    real Ritardando_final 1.3
    boolean Apply_diminuendo 1
    real Diminuendo_moderate 0.6
    real Diminuendo_final 0.4

    comment === VISUALIZATION ===
    optionmenu Visualization_mode 1
        option Progressive (animate each step)
        option Final only (show result)
        option None (fastest)

    comment === PLAYBACK ===
    boolean Play_during_processing 0
    boolean Play_final_result 1
endform

# ---- PRESETS ----
if preset = 2
    number_of_segments = 16
    intensity_weight = 1.0
    spectral_weight = 1.0
    pitch_weight = 0.5
    apply_ritardando = 1
    ritardando_moderate = 1.15
    ritardando_final = 1.3
    apply_diminuendo = 1
    diminuendo_moderate = 0.6
    diminuendo_final = 0.4
    presetName$ = "Classical"
elsif preset = 3
    number_of_segments = 8
    intensity_weight = 0.5
    spectral_weight = 0.8
    pitch_weight = 1.5
    apply_ritardando = 1
    ritardando_moderate = 1.1
    ritardando_final = 1.2
    apply_diminuendo = 0
    presetName$ = "Baroque"
elsif preset = 4
    number_of_segments = 16
    intensity_weight = 1.5
    spectral_weight = 1.2
    pitch_weight = 0.8
    apply_ritardando = 1
    ritardando_moderate = 1.25
    ritardando_final = 1.5
    apply_diminuendo = 1
    diminuendo_moderate = 0.5
    diminuendo_final = 0.3
    presetName$ = "Romantic"
elsif preset = 5
    number_of_segments = 4
    intensity_weight = 1.0
    spectral_weight = 1.0
    pitch_weight = 1.0
    apply_ritardando = 0
    apply_diminuendo = 0
    presetName$ = "Minimal"
elsif preset = 6
    number_of_segments = 32
    intensity_weight = 1.0
    spectral_weight = 1.5
    pitch_weight = 0.5
    apply_ritardando = 1
    ritardando_moderate = 1.1
    ritardando_final = 1.2
    apply_diminuendo = 1
    diminuendo_moderate = 0.7
    diminuendo_final = 0.5
    presetName$ = "Dense"
else
    presetName$ = "Custom"
endif

# ---- VALIDATION ----
if number_of_segments < 4
    number_of_segments = 4
endif
if number_of_segments > 64
    number_of_segments = 64
endif

if intensity_weight < 0
    intensity_weight = 0
endif
if spectral_weight < 0
    spectral_weight = 0
endif
if pitch_weight < 0
    pitch_weight = 0
endif
if intensity_weight + spectral_weight + pitch_weight <= 0
    exitScript: "At least one feature weight must be greater than zero."
endif

if ritardando_moderate < 1
    ritardando_moderate = 1
endif
if ritardando_final < 1
    ritardando_final = 1
endif
if ritardando_moderate > 3
    ritardando_moderate = 3
endif
if ritardando_final > 3
    ritardando_final = 3
endif

if diminuendo_moderate < 0
    diminuendo_moderate = 0
endif
if diminuendo_moderate > 1
    diminuendo_moderate = 1
endif
if diminuendo_final < 0
    diminuendo_final = 0
endif
if diminuendo_final > 1
    diminuendo_final = 1
endif

if random_seed = 0
    random_initializeSafelyAndUnpredictably()
    seedLabel$ = "random"
else
    if random_seed < 0
        random_seed = -random_seed
    endif
    random_initializeWithSeedUnsafelyButPredictably(random_seed)
    seedLabel$ = string$(random_seed)
endif

# ---- SOURCE PROPERTIES / PHASE-SAFE ANALYSIS CHANNEL ----
selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency
numberOfChannels = Get number of channels

minimumSliceDuration = 0.100
if duration < 4 * minimumSliceDuration
    exitScript: "The selected Sound is too short for four reliable analysis slices." + newline$
        ... + "Please use at least 0.40 seconds of audio."
endif

requestedSegments = number_of_segments
maxSegmentsByDuration = floor(duration / minimumSliceDuration)
if maxSegmentsByDuration < 4
    maxSegmentsByDuration = 4
endif
if number_of_segments > maxSegmentsByDuration
    number_of_segments = maxSegmentsByDuration
endif
numberOfSegments = number_of_segments
segmentDuration = duration / numberOfSegments

analysisChannel = 1
analysisSound = soundID
analysisSoundIsCopy = 0

if numberOfChannels > 1
    bestRMS = -1
    for ch from 1 to numberOfChannels
        selectObject: soundID
        Extract one channel: ch
        probeChannel = selected("Sound")
        rmsCh = Get root-mean-square: 0, 0
        if rmsCh > bestRMS
            bestRMS = rmsCh
            analysisChannel = ch
        endif
        removeObject: probeChannel
    endfor

    selectObject: soundID
    Extract one channel: analysisChannel
    Rename: "wuerfel_analysis"
    analysisSound = selected("Sound")
    analysisSoundIsCopy = 1
endif

# ---- OUTPUT ROLE PATTERN ----
# Normal cycle T-P-D-C. If the requested slice count does not complete a
# four-slot phrase, force the final position to C so the game still closes.
need_T = 0
need_P = 0
need_D = 0
need_C = 0
for position from 1 to numberOfSegments
    remainder = (position - 1) mod 4
    if remainder = 0
        outputPattern_'position' = 1
    elsif remainder = 1
        outputPattern_'position' = 2
    elsif remainder = 2
        outputPattern_'position' = 3
    else
        outputPattern_'position' = 4
    endif
endfor
if numberOfSegments mod 4 <> 0
    outputPattern_'numberOfSegments' = 4
endif

for position from 1 to numberOfSegments
    role = outputPattern_'position'
    if role = 1
        need_T = need_T + 1
    elsif role = 2
        need_P = need_P + 1
    elsif role = 3
        need_D = need_D + 1
    else
        need_C = need_C + 1
    endif
endfor

# ---- FEATURE TABLE ----
Create TableOfReal: "wuerfel_features", numberOfSegments, 4
featuresID = selected("TableOfReal")
Set column label (index): 1, "intensity_db"
Set column label (index): 2, "pitch_st"
Set column label (index): 3, "spectral_cog"
Set column label (index): 4, "role"

clearinfo
writeInfoLine: "========================================="
writeInfoLine: "Musikalisches Würfelspiel v1.2"
writeInfoLine: "========================================="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Source: ", originalSoundName$
appendInfoLine: "Channels preserved: ", numberOfChannels
if numberOfChannels > 1
    appendInfoLine: "Analysis channel: ", analysisChannel, " (strongest RMS)"
endif
appendInfoLine: "Seed: ", seedLabel$
if requestedSegments <> numberOfSegments
    appendInfoLine: "Requested ", requestedSegments, " slices; reduced to ", numberOfSegments,
        ... " to keep each analysis slice >= ", fixed$(minimumSliceDuration, 3), " s."
endif
appendInfoLine: ""
appendInfoLine: "NOTE: T/P/D/C are timbral game roles, not harmonic analysis."
appendInfoLine: "Analyzing ", numberOfSegments, " equal-time source slices..."

# ---- EXTRACT SOURCE SLICES + FEATURES ----
for i from 1 to numberOfSegments
    startTime = (i - 1) * segmentDuration
    if i = numberOfSegments
        endTime = duration
    else
        endTime = i * segmentDuration
    endif

    # Preserve original channels in the material that will be recomposed.
    selectObject: soundID
    Extract part: startTime, endTime, "rectangular", 1, "no"
    segmentID_'i' = selected("Sound")
    Rename: "wuerfel_segment_" + string$(i)

    # Analyze only the representative channel, never a phase-cancelling fold-down.
    selectObject: analysisSound
    Extract part: startTime, endTime, "rectangular", 1, "no"
    analysisSegment = selected("Sound")

    # Intensity
    To Intensity: 75, 0, "yes"
    intensityID = selected("Intensity")
    meanIntensity = Get mean: 0, 0, "energy"
    if meanIntensity = undefined
        meanIntensity = -300
    endif
    removeObject: intensityID

    # Pitch: use log-frequency/semitone space for normalization.
    selectObject: analysisSegment
    To Pitch: 0, 75, 600
    pitchID = selected("Pitch")
    meanPitchHz = Get mean: 0, 0, "Hertz"
    if meanPitchHz = undefined or meanPitchHz <= 0
        pitchValid_'i' = 0
        pitchFeature = 0
    else
        pitchValid_'i' = 1
        pitchFeature = 12 * ln(meanPitchHz / 100) / ln(2)
    endif
    removeObject: pitchID

    # Spectral centre of gravity
    selectObject: analysisSegment
    To Spectrum: "yes"
    spectrumID = selected("Spectrum")
    spectralCOG = Get centre of gravity: 2
    if spectralCOG = undefined
        spectralCOG = 0
    endif
    removeObject: spectrumID
    removeObject: analysisSegment

    selectObject: featuresID
    Set value: i, 1, meanIntensity
    Set value: i, 2, pitchFeature
    Set value: i, 3, spectralCOG

    appendInfo: "."
    if i mod 8 = 0
        appendInfo: " ", i
    endif
endfor
appendInfoLine: ""

# ---- GLOBAL NORMALIZATION ----
selectObject: featuresID
totalIntensity = 0
totalPitch = 0
totalCOG = 0
nValidPitch = 0
for i from 1 to numberOfSegments
    thisIntensity = Get value: i, 1
    thisCOG = Get value: i, 3
    totalIntensity = totalIntensity + thisIntensity
    totalCOG = totalCOG + thisCOG
    if pitchValid_'i' = 1
        thisPitch = Get value: i, 2
        totalPitch = totalPitch + thisPitch
        nValidPitch = nValidPitch + 1
    endif
endfor

meanIntensityGlobal = totalIntensity / numberOfSegments
meanCOGGlobal = totalCOG / numberOfSegments
if nValidPitch > 0
    meanPitchGlobal = totalPitch / nValidPitch
else
    meanPitchGlobal = 0
endif

sumSqIntensity = 0
sumSqPitch = 0
sumSqCOG = 0
for i from 1 to numberOfSegments
    selectObject: featuresID
    intensityVal = Get value: i, 1
    cogVal = Get value: i, 3
    sumSqIntensity = sumSqIntensity + (intensityVal - meanIntensityGlobal)^2
    sumSqCOG = sumSqCOG + (cogVal - meanCOGGlobal)^2
    if pitchValid_'i' = 1
        pitchVal = Get value: i, 2
        sumSqPitch = sumSqPitch + (pitchVal - meanPitchGlobal)^2
    endif
endfor

sdIntensity = sqrt(sumSqIntensity / numberOfSegments)
sdCOG = sqrt(sumSqCOG / numberOfSegments)
if nValidPitch > 0
    sdPitch = sqrt(sumSqPitch / nValidPitch)
else
    sdPitch = 1
endif
if sdIntensity < 1e-12
    sdIntensity = 1
endif
if sdCOG < 1e-12
    sdCOG = 1
endif
if sdPitch < 1e-12
    sdPitch = 1
endif

# ---- COMPOSITE TENSION SCORES ----
tensionScores# = zero#(numberOfSegments)
tieKeys# = zero#(numberOfSegments)
for i from 1 to numberOfSegments
    selectObject: featuresID
    intensityVal = Get value: i, 1
    cogVal = Get value: i, 3
    zIntensity = (intensityVal - meanIntensityGlobal) / sdIntensity
    zCOG = (cogVal - meanCOGGlobal) / sdCOG

    if pitchValid_'i' = 1
        pitchVal = Get value: i, 2
        zPitch = (pitchVal - meanPitchGlobal) / sdPitch
        numerator = zIntensity * intensity_weight
            ... + zPitch * pitch_weight
            ... + zCOG * spectral_weight
        denominator = intensity_weight + pitch_weight + spectral_weight
    else
        numerator = zIntensity * intensity_weight
            ... + zCOG * spectral_weight
        denominator = intensity_weight + spectral_weight
    endif

    # If a slice is unvoiced and the user selected pitch-only weighting,
    # it has no usable weighted feature. Give it a neutral score.
    if denominator > 0
        tensionScore = numerator / denominator
    else
        tensionScore = 0
    endif
    tensionScores#[i] = tensionScore
    tieKeys#[i] = randomUniform(0, 1)
endfor

# ---- EXACT ROLE ALLOCATION BY RANK ----
# Rank slices from lowest to highest tension. Role pool sizes are taken from
# the actual output role pattern, so without reuse there is always a
# one-to-one role-matched permutation. Equal scores use the dice RNG as the
# tie breaker rather than pretending there is an acoustic distinction.
rankedSegments# = zero#(numberOfSegments)
rankUsed# = zero#(numberOfSegments)
for rank from 1 to numberOfSegments
    bestSeg = 0
    bestScore = 0
    bestTie = 0
    for i from 1 to numberOfSegments
        if rankUsed#[i] = 0
            thisScore = tensionScores#[i]
            thisTie = tieKeys#[i]
            if bestSeg = 0
                bestSeg = i
                bestScore = thisScore
                bestTie = thisTie
            elsif thisScore < bestScore
                bestSeg = i
                bestScore = thisScore
                bestTie = thisTie
            elsif abs(thisScore - bestScore) <= 1e-12 and thisTie < bestTie
                bestSeg = i
                bestScore = thisScore
                bestTie = thisTie
            endif
        endif
    endfor
    rankedSegments#[rank] = bestSeg
    rankUsed#[bestSeg] = 1
endfor

for rank from 1 to numberOfSegments
    seg = rankedSegments#[rank]
    if rank <= need_C
        functionType = 4
    elsif rank <= need_C + need_T
        functionType = 1
    elsif rank <= need_C + need_T + need_P
        functionType = 2
    else
        functionType = 3
    endif
    selectObject: featuresID
    Set value: seg, 4, functionType
endfor

appendInfoLine: "Role pools matched to output slots:"
appendInfoLine: "  T: ", need_T, "   P: ", need_P, "   D: ", need_D, "   C: ", need_C

# Visualization score range
scoreMin = tensionScores#[1]
scoreMax = tensionScores#[1]
for i from 2 to numberOfSegments
    if tensionScores#[i] < scoreMin
        scoreMin = tensionScores#[i]
    endif
    if tensionScores#[i] > scoreMax
        scoreMax = tensionScores#[i]
    endif
endfor
scoreRange = scoreMax - scoreMin
if scoreRange < 0.2
    scoreRange = 0.2
endif
scoreYmin = scoreMin - 0.12 * scoreRange
scoreYmax = scoreMax + 0.12 * scoreRange

# ---- DICE SELECTION ----
if allow_segment_reuse = 0
    used# = zero#(numberOfSegments)
endif

fallbackCount = 0
appendInfoLine: "Rolling the dice..."
for position from 1 to numberOfSegments
    requiredFunction = outputPattern_'position'
    selectObject: featuresID
    matchCount = 0
    for seg from 1 to numberOfSegments
        segFunction = Get value: seg, 4
        if segFunction = requiredFunction
            if allow_segment_reuse = 1
                matchCount = matchCount + 1
                matches_'matchCount' = seg
            elsif used#[seg] = 0
                matchCount = matchCount + 1
                matches_'matchCount' = seg
            endif
        endif
    endfor

    if matchCount > 0
        randomIndex = randomInteger(1, matchCount)
        chosenSegment_'position' = matches_'randomIndex'
        if allow_segment_reuse = 0
            used#[chosenSegment_'position'] = 1
        endif
    else
        # This should be unreachable with rank-balanced pools; retain a safe
        # fallback so a future edit cannot leave an uninitialized choice.
        fallbackCount = fallbackCount + 1
        found = 0
        if allow_segment_reuse = 0
            for seg from 1 to numberOfSegments
                if found = 0 and used#[seg] = 0
                    chosenSegment_'position' = seg
                    used#[seg] = 1
                    found = 1
                endif
            endfor
        endif
        if found = 0
            chosenSegment_'position' = randomInteger(1, numberOfSegments)
        endif
    endif

    if requiredFunction = 1
        requiredLabel_'position'$ = "T"
    elsif requiredFunction = 2
        requiredLabel_'position'$ = "P"
    elsif requiredFunction = 3
        requiredLabel_'position'$ = "D"
    else
        requiredLabel_'position'$ = "C"
    endif
endfor

if fallbackCount > 0
    appendInfoLine: "WARNING: ", fallbackCount, " role-selection fallback(s) occurred."
endif

# ---- VISUALIZATION ----
procedure setRoleColour: .role
    if .role = 1
        Colour: "{0.22,0.42,0.72}"
    elsif .role = 2
        Colour: "{0.25,0.58,0.48}"
    elsif .role = 3
        Colour: "{0.78,0.34,0.28}"
    else
        Colour: "{0.38,0.38,0.42}"
    endif
endproc

procedure drawVisualization: .currentStep, .total, .isComplete
    Erase all

    # Title
    Select outer viewport: 0.4, 7.6, 0.04, 0.34
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "##Musikalisches Würfelspiel##"

    # Process strip
    Select outer viewport: 0.5, 7.5, 0.38, 0.78
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.35,0.35,0.38}"
    Text: 0.5, "centre", 0.55, "half",
        ... "equal slices  ->  I + log-pitch + spectral COG  ->  tension rank  ->  T/P/D/C pools  ->  dice permutation"

    # Left title strip
    Select outer viewport: 0.55, 3.85, 0.82, 1.08
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Source: measured composite tension and assigned role"

    # Left panel
    Select inner viewport: 0.65, 3.75, 1.12, 4.30
    Axes: 0.5, numberOfSegments + 0.5, scoreYmin, scoreYmax
    Colour: "{0.85,0.85,0.85}"
    if scoreYmin < 0 and scoreYmax > 0
        Draw line: 0.5, 0, numberOfSegments + 0.5, 0
    endif
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Source slice"
    Text left: "yes", "Composite tension"
    if numberOfSegments <= 16
        for i from 1 to numberOfSegments
            One mark bottom: i, "yes", "yes", "no", string$(i)
        endfor
    endif
    for i from 1 to numberOfSegments
        selectObject: featuresID
        role = Get value: i, 4
        if role = 1
            Paint circle (mm): "{0.22,0.42,0.72}", i, tensionScores#[i], 2.0
        elsif role = 2
            Paint circle (mm): "{0.25,0.58,0.48}", i, tensionScores#[i], 2.0
        elsif role = 3
            Paint circle (mm): "{0.78,0.34,0.28}", i, tensionScores#[i], 2.0
        else
            Paint circle (mm): "{0.38,0.38,0.42}", i, tensionScores#[i], 2.0
        endif
        @setRoleColour: role
        dX = 0.10
        dY = scoreRange * 0.025
        Draw line: i - dX, tensionScores#[i] - dY, i + dX, tensionScores#[i] + dY
        Draw line: i - dX, tensionScores#[i] + dY, i + dX, tensionScores#[i] - dY
    endfor

    # Right title strip
    Select outer viewport: 4.15, 7.55, 0.82, 1.08
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    if .isComplete = 1
        Text: 0.5, "centre", 0.5, "half", "Output permutation (complete)"
    else
        Text: 0.5, "centre", 0.5, "half",
            ... "Output permutation - step " + string$(.currentStep) + "/" + string$(.total)
    endif

    # Right panel
    Select inner viewport: 4.28, 7.45, 1.12, 4.30
    Axes: 0.5, numberOfSegments + 0.5, 0.5, numberOfSegments + 0.5
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Output position"
    Text left: "yes", "Source slice"
    if numberOfSegments <= 16
        for i from 1 to numberOfSegments
            One mark bottom: i, "yes", "yes", "no", string$(i)
            One mark left: i, "yes", "yes", "no", string$(i)
        endfor
    endif

    lastPos = 0
    lastSeg = 0
    for position from 1 to numberOfSegments
        if .isComplete = 1 or position <= .currentStep
            seg = chosenSegment_'position'
            role = outputPattern_'position'
            if lastPos > 0
                Colour: "{0.72,0.72,0.74}"
                Draw line: lastPos, lastSeg, position, seg
            endif
            @setRoleColour: role
            d = 0.18
            Draw line: position - d, seg - d, position + d, seg + d
            Draw line: position - d, seg + d, position + d, seg - d
            lastPos = position
            lastSeg = seg
        endif
    endfor

    # Footer / legend (two strips, separated from axis captions)
    Select outer viewport: 0.5, 7.5, 4.68, 4.95
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.22,0.42,0.72}"
    Text: 0.02, "left", 0.5, "half", "T"
    Colour: "{0.25,0.58,0.48}"
    Text: 0.07, "left", 0.5, "half", "P"
    Colour: "{0.78,0.34,0.28}"
    Text: 0.12, "left", 0.5, "half", "D"
    Colour: "{0.38,0.38,0.42}"
    Text: 0.17, "left", 0.5, "half", "C"
    Colour: "Black"
    summary$ = "roles " + string$(need_T) + "/" + string$(need_P) + "/" + string$(need_D) + "/" + string$(need_C)
        ... + "  |  seed " + seedLabel$ + "  |  analysis ch " + string$(analysisChannel)
        ... + "  |  5 ms joins"
    Text: 0.26, "left", 0.5, "half", summary$

    Select outer viewport: 0.5, 7.5, 4.98, 5.24
    Axes: 0, 1, 0, 1
    Font size: 6.3
    Colour: "{0.30,0.30,0.32}"
    Text: 0.5, "centre", 0.5, "half",
        ... "T/P/D/C are compositional timbre roles; they are not detected harmonic functions."
endproc

# ---- BUILD OUTPUT PIECES ----
appendInfoLine: "Processing selected slices..."
for k from 1 to numberOfSegments
    if visualization_mode = 1
        @drawVisualization: k, numberOfSegments, 0
    endif

    chosenSeg = chosenSegment_'k'
    selectObject: segmentID_'chosenSeg'
    Copy: "wuerfel_piece_" + string$(k)
    pieceID_'k' = selected("Sound")

    # Expression is applied to actual C-role slots, not merely every fourth index.
    if outputPattern_'k' = 4
        selectObject: pieceID_'k'
        pieceDur = Get total duration

        if k = numberOfSegments
            ritFactor = ritardando_final
            dimAmount = diminuendo_final
        else
            ritFactor = ritardando_moderate
            dimAmount = diminuendo_moderate
        endif

        # Diminuendo: last 30% ramps from 1 to dimAmount.
        if apply_diminuendo = 1 and dimAmount < 1
            fadeStart = pieceDur * 0.7
            fadeStart_str$ = fixed$(fadeStart, 9)
            pieceDur_str$ = fixed$(pieceDur, 9)
            dimAmount_str$ = fixed$(dimAmount, 9)
            selectObject: pieceID_'k'
            Formula: "self * (1 - max(0, (x - " + fadeStart_str$
                ... + ") / (" + pieceDur_str$ + " - " + fadeStart_str$
                ... + ")) * (1 - " + dimAmount_str$ + "))"
        endif

        # Ritardando: process every channel independently with the same
        # duration-tier law, then reconstruct the original channel count.
        if apply_ritardando = 1 and ritFactor > 1
            selectObject: pieceID_'k'
            pieceChannels = Get number of channels

            for ch from 1 to pieceChannels
                selectObject: pieceID_'k'
                Extract one channel: ch
                monoPiece = selected("Sound")

                To Manipulation: 0.01, 75, 600
                manipID = selected("Manipulation")
                Extract duration tier
                durTierID = selected("DurationTier")
                Add point: 0, 1.0
                Add point: pieceDur * 0.7, 1.0
                Add point: pieceDur, ritFactor

                selectObject: manipID
                plusObject: durTierID
                Replace duration tier
                selectObject: manipID
                Get resynthesis (overlap-add)
                ritChID_'ch' = selected("Sound")

                removeObject: manipID, durTierID, monoPiece
            endfor

            selectObject: ritChID_1
            stretchedDur = Get total duration
            stretchedSR = Get sampling frequency

            if pieceChannels = 1
                selectObject: pieceID_'k'
                Remove
                selectObject: ritChID_1
                Rename: "wuerfel_piece_" + string$(k)
                pieceID_'k' = selected("Sound")
            else
                # Build a nested formula because Praat formulas support
                # if/then/else/fi, not script-style elsif.
                lastID = ritChID_'pieceChannels'
                combineFormula$ = "object[" + string$(lastID) + ",1,col]"
                if pieceChannels > 1
                    for offset from 1 to pieceChannels - 1
                        ch = pieceChannels - offset
                        thisID = ritChID_'ch'
                        combineFormula$ = "if row = " + string$(ch)
                            ... + " then object[" + string$(thisID) + ",1,col]"
                            ... + " else " + combineFormula$ + " fi"
                    endfor
                endif

                Create Sound from formula: "wuerfel_piece_" + string$(k),
                    ... pieceChannels, 0, stretchedDur, stretchedSR, combineFormula$
                rebuiltPiece = selected("Sound")

                selectObject: pieceID_'k'
                Remove
                for ch from 1 to pieceChannels
                    removeObject: ritChID_'ch'
                endfor
                selectObject: rebuiltPiece
                pieceID_'k' = selected("Sound")
            endif
        endif
    endif

    if play_during_processing = 1
        selectObject: pieceID_'k'
        Play
    endif

    appendInfo: "."
    if k mod 8 = 0
        appendInfo: " ", k
    endif
endfor
appendInfoLine: ""

# ---- CONCATENATE WITH SHORT OVERLAP ----
appendInfoLine: "Concatenating with 5 ms joins..."
selectObject: pieceID_1
for i from 2 to numberOfSegments
    plusObject: pieceID_'i'
endfor
joinOverlap = 0.005
if joinOverlap > segmentDuration * 0.10
    joinOverlap = segmentDuration * 0.10
endif
Concatenate with overlap: joinOverlap
outputSound = selected("Sound")
Rename: "wuerfelspiel_" + presetName$

# ---- FINAL VISUALIZATION ----
if visualization_mode = 1 or visualization_mode = 2
    @drawVisualization: numberOfSegments, numberOfSegments, 1
endif

# ---- CLEANUP ----
removeObject: featuresID
for i from 1 to numberOfSegments
    removeObject: segmentID_'i', pieceID_'i'
endfor
if analysisSoundIsCopy = 1
    removeObject: analysisSound
endif

selectObject: outputSound
outputChannels = Get number of channels
outputDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "========================================="
appendInfoLine: "COMPLETE"
appendInfoLine: "========================================="
appendInfoLine: "Output: wuerfelspiel_", presetName$
appendInfoLine: "Slices: ", numberOfSegments
appendInfoLine: "Channels: ", outputChannels, " (input ", numberOfChannels, ")"
appendInfoLine: "Duration: ", fixed$(outputDuration, 3), " s"
appendInfoLine: "Weights I/S/P: ", intensity_weight, " / ", spectral_weight, " / ", pitch_weight
appendInfoLine: "Role slots T/P/D/C: ", need_T, "/", need_P, "/", need_D, "/", need_C
appendInfoLine: "Selection fallbacks: ", fallbackCount
if allow_segment_reuse = 0
    appendInfoLine: "Source use: permutation (no reuse)"
else
    appendInfoLine: "Source use: reuse allowed"
endif

if play_final_result = 1
    appendInfoLine: "Playing result..."
    Play
endif
