# ============================================================
# Praat AudioTools - Musikalisches Würfelspiel (Musical Dice Game)
# Author: Shai Cohen (improved by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
#
# Description:
#   Inspired by 18th-century Musikalisches Würfelspiel, this script
#   reorders audio segments according to a functional pattern.
#   
#   IMPORTANT: This script uses TIMBRAL FEATURES (intensity, pitch,
#   spectral brightness) as an ANALOGY to harmonic function, not actual
#   harmonic analysis. Segments are classified by acoustic character:
#   - T (Tonic-like): Dark, low, quiet
#   - P (Predominant-like): Moderate
#   - D (Dominant-like): Bright, high, loud
#   - C (Cadence-like): Very dark/resolved
#
# Improvements in v1.0:
#   - No segment repetition (each used once max)
#   - Optimized visualization with modes
#   - Clearer conceptual explanation
#   - Better presets
#   - Performance optimizations
#
# Changelog v1.1 (2026):
#   - FIX: First-unused-segment fallback loop (line 403) used
#     loop-variable mutation (seg = numberOfSegments + 1) to break
#     early. Replaced with the standard "found" flag pattern that
#     was already partially set up. Loop-var mutation is fragile
#     across Praat versions.
#   - FIX: The diminuendo Formula referenced script variables
#     (fadeStart, pieceDur, dimAmount) directly inside the Formula
#     string, which works in modern Praat but is undocumented and
#     not portable. Now uses string$() concatenation throughout.
#     Also rewrote the inline if/then/else/fi conditional as a
#     max(0, ...) expression — same envelope shape, cleaner Formula.
#   - QUALITY: Classification now uses percentile-based thresholds
#     (quartile cuts) instead of fixed z-score cutoffs (>0.5, >0,
#     >-0.5). On uniform-timbre inputs the old fixed cutoffs left
#     most segments in T/P with D/C nearly empty, which broke the
#     T-P-D-C output pattern. Quartile cuts guarantee ~25% of
#     segments in each category — pattern always fills.
#   - QUALITY: Segments with undefined pitch (unvoiced, percussion,
#     noise) no longer have a fictitious 200 Hz value injected into
#     z-scoring. The pitch term is excluded from the tension score
#     for those segments, with the weight sum re-normalized. Yields
#     more meaningful classification on percussion/noise inputs.
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Musikalisches Würfelspiel v1.1
    comment === PRESETS ===
    optionmenu Preset 1
        option Custom
        option Classical (16 segments, balanced)
        option Baroque (8 segments, pitch-focused)
        option Romantic (16 segments, expressive)
        option Minimal (4 segments, simple)
        option Dense (32 segments, complex)
    
    comment === PHRASE STRUCTURE ===
    positive Number_of_segments 16
    
    comment === FEATURE WEIGHTING ===
    positive Intensity_weight 1.0
    positive Spectral_weight 1.0
    positive Pitch_weight 0.5
    
    comment === SEGMENT SELECTION ===
    boolean Allow_segment_reuse 0
    comment (If unchecked, each segment used max once)
    
    comment === MUSICAL EXPRESSION ===
    boolean Apply_ritardando 1
    positive Ritardando_moderate 1.15
    positive Ritardando_final 1.3
    boolean Apply_diminuendo 1
    positive Diminuendo_moderate 0.6
    positive Diminuendo_final 0.4
    
    comment === VISUALIZATION ===
    optionmenu Visualization_mode 1
        option Progressive (animate each step)
        option Final only (show result)
        option None (fastest)
    
    comment === PLAYBACK ===
    boolean Play_during_processing 0
    boolean Play_final_result 1
endform

# Apply presets
if preset = 2
    # Classical
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
    # Baroque
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
    # Romantic
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
    # Minimal
    number_of_segments = 4
    intensity_weight = 1.0
    spectral_weight = 1.0
    pitch_weight = 1.0
    apply_ritardando = 0
    apply_diminuendo = 0
    presetName$ = "Minimal"
elsif preset = 6
    # Dense
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

# Validate number of segments
if number_of_segments < 4
    number_of_segments = 4
endif
if number_of_segments > 64
    number_of_segments = 64
endif

numberOfSegments = number_of_segments

# Convert to mono if needed
selectObject: soundID
numberOfChannels = Get number of channels
if numberOfChannels > 1
    selectObject: soundID
    Convert to mono
    monoSound = selected("Sound")
    soundName$ = selected$("Sound")
    convertedToMono = 1
else
    monoSound = soundID
    convertedToMono = 0
endif

# Get total duration and calculate segment duration
selectObject: monoSound
duration = Get total duration
sampleRate = Get sampling frequency
segmentDuration = duration / numberOfSegments

# Create TableOfReal to store features
Create TableOfReal: "features", numberOfSegments, 4
featuresID = selected("TableOfReal")
Set column label (index): 1, "intensity"
Set column label (index): 2, "pitch"
Set column label (index): 3, "spectral_cog"
Set column label (index): 4, "function"

clearinfo
writeInfoLine: "========================================="
writeInfoLine: "Musikalisches Würfelspiel v1.1"
writeInfoLine: "========================================="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "NOTE: This script uses timbral features"
appendInfoLine: "(intensity, pitch, brightness) as an"
appendInfoLine: "ANALOGY to functional harmony (T-P-D-C)."
appendInfoLine: "It does NOT perform harmonic analysis."
appendInfoLine: ""
appendInfoLine: "Analyzing ", numberOfSegments, " segments..."

# Extract segments and compute features
for i from 1 to numberOfSegments
    startTime = (i - 1) * segmentDuration
    endTime = i * segmentDuration
    
    # Extract segment
    selectObject: monoSound
    Extract part: startTime, endTime, "rectangular", 1, "no"
    segmentID_'i' = selected("Sound")
    Rename: "segment_" + string$(i)
    
    # Compute mean intensity
    selectObject: segmentID_'i'
    To Intensity: 75, 0, "yes"
    intensityID = selected("Intensity")
    meanIntensity = Get mean: 0, 0, "energy"
    removeObject: intensityID
    
    # Compute mean pitch
    # v1.1: track validity instead of injecting fictitious 200 Hz.
    # Segments with undefined pitch (unvoiced, percussion, noise) will
    # have the pitch term excluded from their tension-score computation
    # rather than contaminating it with a placeholder.
    selectObject: segmentID_'i'
    To Pitch: 0, 75, 600
    pitchID = selected("Pitch")
    meanPitch = Get mean: 0, 0, "Hertz"
    if meanPitch = undefined
        pitchValid_'i' = 0
        meanPitch = 0
    else
        pitchValid_'i' = 1
    endif
    removeObject: pitchID
    
    # Compute spectral centre of gravity
    selectObject: segmentID_'i'
    To Spectrum: "yes"
    spectrumID = selected("Spectrum")
    spectralCOG = Get centre of gravity: 2
    removeObject: spectrumID
    
    # Store features
    selectObject: featuresID
    Set value: i, 1, meanIntensity
    Set value: i, 2, meanPitch
    Set value: i, 3, spectralCOG
    
    appendInfo: "."
    if i mod 8 = 0
        appendInfo: " ", i
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Classifying segments by timbre..."

# Compute global means for z-score normalization.
# v1.1: pitch mean uses only segments with valid pitch (Concern 3).
# Intensity and centroid have a value for every segment.
selectObject: featuresID
totalIntensity = 0
totalPitch = 0
totalCOG = 0
nValidPitch = 0
for i from 1 to numberOfSegments
    totalIntensity += Get value: i, 1
    totalCOG += Get value: i, 3
    if pitchValid_'i' = 1
        totalPitch += Get value: i, 2
        nValidPitch += 1
    endif
endfor
meanIntensityGlobal = totalIntensity / numberOfSegments
meanCOGGlobal = totalCOG / numberOfSegments
if nValidPitch > 0
    meanPitchGlobal = totalPitch / nValidPitch
else
    meanPitchGlobal = 0
endif

# Calculate standard deviations.
# v1.1: pitch SD uses only valid-pitch segments.
sumSqIntensity = 0
sumSqPitch = 0
sumSqCOG = 0
for i from 1 to numberOfSegments
    selectObject: featuresID
    intensityVal = Get value: i, 1
    cogVal = Get value: i, 3
    sumSqIntensity += (intensityVal - meanIntensityGlobal) ^ 2
    sumSqCOG += (cogVal - meanCOGGlobal) ^ 2
    if pitchValid_'i' = 1
        pitchVal = Get value: i, 2
        sumSqPitch += (pitchVal - meanPitchGlobal) ^ 2
    endif
endfor
sdIntensity = sqrt(sumSqIntensity / numberOfSegments)
sdCOG = sqrt(sumSqCOG / numberOfSegments)
if nValidPitch > 0
    sdPitch = sqrt(sumSqPitch / nValidPitch)
else
    sdPitch = 1
endif

# Prevent division by zero
if sdIntensity = 0
    sdIntensity = 1
endif
if sdPitch = 0
    sdPitch = 1
endif
if sdCOG = 0
    sdCOG = 1
endif

# v1.1: Two-pass classification using percentile-based (quartile)
# thresholds instead of fixed z-score cutoffs (>0.5, >0, >-0.5).
# Old fixed cutoffs left D/C nearly empty on uniform-timbre inputs,
# breaking the T-P-D-C output pattern. Quartile cuts guarantee ~25%
# of segments in each category.

# Pass 1: compute and store all tension scores
tensionScores# = zero#(numberOfSegments)
for i from 1 to numberOfSegments
    selectObject: featuresID
    intensityVal = Get value: i, 1
    cogVal = Get value: i, 3

    zIntensity = (intensityVal - meanIntensityGlobal) / sdIntensity
    zCOG = (cogVal - meanCOGGlobal) / sdCOG

    # v1.1: pitch term excluded for segments with no valid pitch.
    # Weight sum is re-normalized to keep tension scores comparable
    # across mixed-validity segment sets.
    if pitchValid_'i' = 1
        pitchVal = Get value: i, 2
        zPitch = (pitchVal - meanPitchGlobal) / sdPitch
        tensionScore = (zIntensity * intensity_weight)
            ... + (zPitch * pitch_weight)
            ... + (zCOG * spectral_weight)
        totalWeight = intensity_weight + pitch_weight + spectral_weight
    else
        tensionScore = (zIntensity * intensity_weight)
            ... + (zCOG * spectral_weight)
        totalWeight = intensity_weight + spectral_weight
    endif
    if totalWeight > 0
        tensionScore = tensionScore / totalWeight
    endif
    tensionScores#[i] = tensionScore
endfor

# Pass 2: derive quartile thresholds from sorted scores.
sortedScores# = sort#(tensionScores#)
q1_idx = round(numberOfSegments * 0.25)
q2_idx = round(numberOfSegments * 0.50)
q3_idx = round(numberOfSegments * 0.75)
if q1_idx < 1
    q1_idx = 1
endif
if q2_idx < 1
    q2_idx = 1
endif
if q3_idx > numberOfSegments
    q3_idx = numberOfSegments
endif
threshold_C = sortedScores#[q1_idx]
threshold_T = sortedScores#[q2_idx]
threshold_P = sortedScores#[q3_idx]

# Pass 3: assign function by quartile.
# Top quartile (highest tension) → D (bright/dominant-like)
# Upper-mid quartile             → P (predominant-like)
# Lower-mid quartile             → T (tonic-like)
# Bottom quartile (lowest)       → C (cadence-like, very dark)
for i from 1 to numberOfSegments
    score = tensionScores#[i]
    if score > threshold_P
        functionType = 3
    elsif score > threshold_T
        functionType = 2
    elsif score > threshold_C
        functionType = 1
    else
        functionType = 4
    endif
    selectObject: featuresID
    Set value: i, 4, functionType
endfor

# Count segments in each function
selectObject: featuresID
count_T = 0
count_P = 0
count_D = 0
count_C = 0
for i from 1 to numberOfSegments
    func = Get value: i, 4
    if func = 1
        count_T += 1
    elsif func = 2
        count_P += 1
    elsif func = 3
        count_D += 1
    else
        count_C += 1
    endif
endfor

appendInfoLine: "  T (Tonic-like): ", count_T, " segments"
appendInfoLine: "  P (Predominant-like): ", count_P, " segments"
appendInfoLine: "  D (Dominant-like): ", count_D, " segments"
appendInfoLine: "  C (Cadence-like): ", count_C, " segments"

# Define output pattern (T-P-D-C repeating)
for i from 1 to numberOfSegments
    remainder = (i - 1) mod 4
    if remainder = 0
        outputPattern_'i' = 1
    elsif remainder = 1
        outputPattern_'i' = 2
    elsif remainder = 2
        outputPattern_'i' = 3
    else
        outputPattern_'i' = 4
    endif
endfor

# Initialize segment usage tracking
if allow_segment_reuse = 0
    used# = zero#(numberOfSegments)
endif

# Pre-select segments for each position
appendInfoLine: "Selecting segments (dice roll)..."

for position from 1 to numberOfSegments
    requiredFunction = outputPattern_'position'
    
    # Find all segments matching required function
    selectObject: featuresID
    matchCount = 0
    for seg from 1 to numberOfSegments
        segFunction = Get value: seg, 4
        
        # Check if segment matches function
        if segFunction = requiredFunction
            # If not allowing reuse, also check if already used
            if allow_segment_reuse = 1
                matchCount += 1
                matches_'matchCount' = seg
            else
                if used#[seg] = 0
                    matchCount += 1
                    matches_'matchCount' = seg
                endif
            endif
        endif
    endfor
    
    # Select random matching segment
    if matchCount > 0
        randomIndex = randomInteger(1, matchCount)
        chosenSegment_'position' = matches_'randomIndex'
        if allow_segment_reuse = 0
            used#[chosenSegment_'position'] = 1
        endif
    else
        # Fallback: find any unused segment (or random if allowing reuse)
        if allow_segment_reuse = 0
            # v1.1: replaced loop-var mutation early-break
            # (seg = numberOfSegments + 1) with the standard
            # found-flag pattern. Loop-var mutation works in modern
            # Praat but is fragile across versions.
            found = 0
            for seg from 1 to numberOfSegments
                if found = 0 and used#[seg] = 0
                    chosenSegment_'position' = seg
                    used#[seg] = 1
                    found = 1
                endif
            endfor
            # If all used, allow reuse
            if found = 0
                chosenSegment_'position' = randomInteger(1, numberOfSegments)
            endif
        else
            chosenSegment_'position' = randomInteger(1, numberOfSegments)
        endif
    endif
    
    # Store function label
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

appendInfoLine: "Processing with expression..."

# Calculate grid dimensions
gridSize = ceiling(sqrt(numberOfSegments))
if gridSize * (gridSize - 1) >= numberOfSegments
    gridRows = gridSize - 1
    gridCols = gridSize
else
    gridRows = gridSize
    gridCols = gridSize
endif

# Procedure to draw visualization
procedure drawVisualization: .currentStep, .total, .isComplete
    Erase all
    Select inner viewport: 0.5, 7.5, 0.5, 7.5
    
    Axes: 0, gridCols, 0, gridRows
    Colour: "Black"
    Line width: 1
    
    # Title
    if .isComplete = 1
        Text top: "yes", "Würfelspiel v1.1 Complete - " + presetName$
    else
        Text top: "yes", "Würfelspiel v1.1 - Step " + string$(.currentStep) + "/" + string$(.total)
    endif
    Text left: "yes", "Row"
    Text bottom: "yes", "Column"
    
    # Draw grid
    Colour: "Grey"
    for i from 0 to gridCols
        Draw line: i, 0, i, gridRows
    endfor
    for i from 0 to gridRows
        Draw line: 0, i, gridCols, i
    endfor
    
    # Draw cells
    for position from 1 to numberOfSegments
        row = floor((position - 1) / gridCols)
        col = (position - 1) mod gridCols
        
        x1 = col
        x2 = col + 1
        y1 = gridRows - row - 1
        y2 = gridRows - row
        xCenter = (x1 + x2) / 2
        yCenter = (y1 + y2) / 2
        
        if .isComplete = 1 or position <= .currentStep
            # Already processed
            selectedSeg = chosenSegment_'position'
            funcLabel$ = requiredLabel_'position'$
            
            # Color by function
            if funcLabel$ = "T"
                Paint circle: "Purple", xCenter, yCenter, 0.35
            elsif funcLabel$ = "P"
                Paint circle: "Cyan", xCenter, yCenter, 0.35
            elsif funcLabel$ = "D"
                Paint circle: "Magenta", xCenter, yCenter, 0.35
            else
                Paint circle: "Pink", xCenter, yCenter, 0.35
            endif
            
            # Draw text
            Colour: "White"
            if .isComplete = 0 and position = .currentStep
                Line width: 3
                Text: xCenter, "centre", yCenter + 0.15, "half", ">" + string$(selectedSeg)
                Text: xCenter, "centre", yCenter - 0.15, "half", funcLabel$
            else
                Line width: 1
                Text: xCenter, "centre", yCenter + 0.1, "half", string$(selectedSeg)
                Text: xCenter, "centre", yCenter - 0.1, "half", funcLabel$
            endif
        else
            # Not yet processed
            Colour: "Grey"
            Draw circle: xCenter, yCenter, 0.35
        endif
    endfor
    
    # Legend
    Select inner viewport: 0.5, 7.5, 7.8, 8.5
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Line width: 1
    Paint circle: "Purple", 0.05, 0.7, 0.015
    Text: 0.08, "left", 0.7, "half", "T=Tonic-like (dark)"
    Paint circle: "Cyan", 0.38, 0.7, 0.015
    Text: 0.41, "left", 0.7, "half", "P=Predominant-like"
    Paint circle: "Magenta", 0.05, 0.3, 0.015
    Text: 0.08, "left", 0.3, "half", "D=Dominant-like (bright)"
    Paint circle: "Pink", 0.38, 0.3, 0.015
    Text: 0.41, "left", 0.3, "half", "C=Cadence-like (very dark)"
    
    if .isComplete = 1
        expressionText$ = ""
        if apply_ritardando = 1 and apply_diminuendo = 1
            expressionText$ = " + rit. & dim."
        elsif apply_ritardando = 1
            expressionText$ = " + rit."
        elsif apply_diminuendo = 1
            expressionText$ = " + dim."
        endif
        Text: 0.5, "centre", 0.1, "half", "Pattern: T-P-D-C | " + soundName$ + expressionText$
    endif
endproc

# Progressive processing
for k from 1 to numberOfSegments
    # Visualization
    if visualization_mode = 1
        # Progressive
        @drawVisualization: k, numberOfSegments, 0
    endif
    
    # Process current segment
    chosenSeg = chosenSegment_'k'
    selectObject: segmentID_'chosenSeg'
    Copy: "piece_" + string$(k)
    pieceID_'k' = selected("Sound")
    
    # Apply ritardando and diminuendo at phrase endings
    if k mod 4 = 0
        selectObject: pieceID_'k'
        pieceDur = Get total duration
        
        # Determine effect strength
        if k = numberOfSegments
            ritFactor = ritardando_final
            dimAmount = diminuendo_final
        else
            ritFactor = ritardando_moderate
            dimAmount = diminuendo_moderate
        endif
        
        # Apply diminuendo
        # v1.1: was using script variables fadeStart/pieceDur/dimAmount
        # directly inside the Formula string and an inline if/then/else/fi
        # conditional. Both work in modern Praat but are fragile across
        # versions. Now uses string$() concatenation and a max(0, ...)
        # expression — same envelope shape, more portable.
        # Envelope: 1 for x < fadeStart, ramps linearly to dimAmount at x = pieceDur.
        if apply_diminuendo = 1
            selectObject: pieceID_'k'
            fadeStart = pieceDur * 0.7
            fadeStart_str$ = fixed$(fadeStart, 8)
            pieceDur_str$ = fixed$(pieceDur, 8)
            dimAmount_str$ = fixed$(dimAmount, 8)
            Formula: "self * (1 - max(0, (x - " + fadeStart_str$
                ... + ") / (" + pieceDur_str$ + " - " + fadeStart_str$
                ... + ")) * (1 - " + dimAmount_str$ + "))"
        endif
        
        # Apply ritardando
        if apply_ritardando = 1
            selectObject: pieceID_'k'
            pieceDur = Get total duration
            fadeStart = pieceDur * 0.7
            
            To Manipulation: 0.01, 75, 600
            manipID = selected("Manipulation")
            Extract duration tier
            durTierID = selected("DurationTier")
            
            Add point: 0, 1.0
            Add point: fadeStart, 1.0
            Add point: pieceDur, ritFactor
            
            selectObject: manipID
            plusObject: durTierID
            Replace duration tier
            selectObject: manipID
            Get resynthesis (overlap-add)
            ritSound = selected("Sound")
            
            removeObject: manipID, durTierID
            
            selectObject: pieceID_'k'
            Remove
            selectObject: ritSound
            Rename: "piece_" + string$(k)
            pieceID_'k' = selected("Sound")
        endif
    endif
    
    # Play current segment
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
appendInfoLine: "Concatenating..."

# Concatenate all pieces
selectObject: pieceID_1
for i from 2 to numberOfSegments
    plusObject: pieceID_'i'
endfor
Concatenate
outputSound = selected("Sound")
Rename: "wuerfelspiel_" + presetName$

# Final visualization
if visualization_mode = 1 or visualization_mode = 2
    @drawVisualization: numberOfSegments, numberOfSegments, 1
endif

# Cleanup
removeObject: featuresID
for i from 1 to numberOfSegments
    removeObject: segmentID_'i', pieceID_'i'
endfor

if convertedToMono = 1
    removeObject: monoSound
endif

selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "========================================="
appendInfoLine: "COMPLETE!"
appendInfoLine: "========================================="
appendInfoLine: "Output: wuerfelspiel_", presetName$
appendInfoLine: "Segments: ", numberOfSegments
appendInfoLine: "Weights: I=", intensity_weight, " P=", pitch_weight, " S=", spectral_weight
if allow_segment_reuse = 0
    appendInfoLine: "Each segment used max once"
else
    appendInfoLine: "Segment reuse allowed"
endif

if play_final_result = 1
    appendInfoLine: "Playing result..."
    Play
endif

appendInfoLine: ""