# ============================================================
# Praat AudioTools - Musikalisches_Wuerfelspiel_Audio_Game.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) 
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Musikalisches Würfelspiel (Musical Dice Game) - An 18th-century
#   composition technique where segments are randomly reordered
#   according to functional harmonic patterns (T-P-D-C).
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed select -> selectObject syntax
#   - Fixed == -> = operator
#   - Fixed array syntax for Praat compatibility
#   - Fixed plus -> plusObject syntax
#   - Fixed string interpolation in Text commands
#   - Fixed Formula variable scope
#   - Added input validation
#   - Added presets
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Musikalisches Wuerfelspiel v0.2
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Classical (16 segments balanced)
        option Baroque (8 segments pitch-focused)
        option Romantic (16 segments expressive)
        option Minimal (4 segments simple)
        option Dense (32 segments complex)
    comment === Phrase Structure ===
    positive Number_of_segments 16
    comment === Feature Weighting ===
    positive Intensity_weight 1.0
    positive Spectral_weight 1.0
    positive Pitch_weight 0.5
    comment === Musical Expression ===
    boolean Apply_ritardando 1
    positive Ritardando_moderate 1.15
    positive Ritardando_final 1.3
    boolean Apply_diminuendo 1
    positive Diminuendo_moderate 0.6
    positive Diminuendo_final 0.4
    comment === Playback ===
    boolean Play_during_processing 1
    boolean Play_final_result 1
    positive Visualization_delay 0.05
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
appendInfoLine: "Musikalisches Würfelspiel v0.2"
appendInfoLine: "========================================="
appendInfoLine: "Preset: ", presetName$
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
    selectObject: segmentID_'i'
    To Pitch: 0, 75, 600
    pitchID = selected("Pitch")
    meanPitch = Get mean: 0, 0, "Hertz"
    if meanPitch = undefined
        meanPitch = 200
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
    if i mod 4 = 0
        appendInfo: " ", i
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Classifying segments..."

# Compute global means for z-score normalization
selectObject: featuresID
totalIntensity = 0
totalPitch = 0
totalCOG = 0
for i from 1 to numberOfSegments
    totalIntensity += Get value: i, 1
    totalPitch += Get value: i, 2
    totalCOG += Get value: i, 3
endfor
meanIntensityGlobal = totalIntensity / numberOfSegments
meanPitchGlobal = totalPitch / numberOfSegments
meanCOGGlobal = totalCOG / numberOfSegments

# Calculate standard deviations
sumSqIntensity = 0
sumSqPitch = 0
sumSqCOG = 0
for i from 1 to numberOfSegments
    selectObject: featuresID
    intensityVal = Get value: i, 1
    pitchVal = Get value: i, 2
    cogVal = Get value: i, 3
    sumSqIntensity += (intensityVal - meanIntensityGlobal) ^ 2
    sumSqPitch += (pitchVal - meanPitchGlobal) ^ 2
    sumSqCOG += (cogVal - meanCOGGlobal) ^ 2
endfor
sdIntensity = sqrt(sumSqIntensity / numberOfSegments)
sdPitch = sqrt(sumSqPitch / numberOfSegments)
sdCOG = sqrt(sumSqCOG / numberOfSegments)

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

# Classify segments into functional roles
# 1=T (tonic), 2=P (predominant), 3=D (dominant), 4=C (cadence)
for i from 1 to numberOfSegments
    selectObject: featuresID
    intensityVal = Get value: i, 1
    pitchVal = Get value: i, 2
    cogVal = Get value: i, 3
    
    # Calculate z-scores
    zIntensity = (intensityVal - meanIntensityGlobal) / sdIntensity
    zPitch = (pitchVal - meanPitchGlobal) / sdPitch
    zCOG = (cogVal - meanCOGGlobal) / sdCOG
    
    # Compute weighted tension score
    tensionScore = (zIntensity * intensity_weight) + (zPitch * pitch_weight) + (zCOG * spectral_weight)
    totalWeight = intensity_weight + pitch_weight + spectral_weight
    tensionScore = tensionScore / totalWeight
    
    # Map tension to functional roles
    if tensionScore > 0.5
        functionType = 3
    elsif tensionScore > 0
        functionType = 2
    elsif tensionScore > -0.5
        functionType = 1
    else
        functionType = 4
    endif
    
    Set value: i, 4, functionType
endfor

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

# Pre-select segments for each position
for position from 1 to numberOfSegments
    requiredFunction = outputPattern_'position'
    
    # Find all segments matching required function
    selectObject: featuresID
    matchCount = 0
    for seg from 1 to numberOfSegments
        segFunction = Get value: seg, 4
        if segFunction = requiredFunction
            matchCount += 1
            matches_'matchCount' = seg
        endif
    endfor
    
    # Select random matching segment (or random fallback)
    if matchCount > 0
        randomIndex = randomInteger(1, matchCount)
        chosenSegment_'position' = matches_'randomIndex'
    else
        chosenSegment_'position' = randomInteger(1, numberOfSegments)
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

# Progressive processing with visualization
for k from 1 to numberOfSegments
    # Draw visualization
    Erase all
    Select inner viewport: 0.5, 7.5, 0.5, 7.5
    
    Axes: 0, gridCols, 0, gridRows
    Colour: "Black"
    Line width: 1
    
    # Title
    Text top: "yes", "Würfelspiel Reordering - Step " + string$(k) + "/" + string$(numberOfSegments)
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
        
        if position <= k
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
            if position = k
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
    Text: 0.08, "left", 0.7, "half", "T=Tonic"
    Paint circle: "Cyan", 0.3, 0.7, 0.015
    Text: 0.33, "left", 0.7, "half", "P=Predominant"
    Paint circle: "Magenta", 0.6, 0.7, 0.015
    Text: 0.63, "left", 0.7, "half", "D=Dominant"
    Paint circle: "Pink", 0.05, 0.3, 0.015
    Text: 0.08, "left", 0.3, "half", "C=Cadence"
    
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
        if apply_diminuendo = 1
            selectObject: pieceID_'k'
            fadeStart = pieceDur * 0.7
            fadeStartStr$ = string$(fadeStart)
            pieceDurStr$ = string$(pieceDur)
            dimAmountStr$ = string$(dimAmount)
            Formula: "if x < " + fadeStartStr$ + " then self else self * (1 - (x - " + fadeStartStr$ + ")/(" + pieceDurStr$ + " - " + fadeStartStr$ + ") * (1 - " + dimAmountStr$ + ")) fi"
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
    
    if play_during_processing = 0
        sleep: visualization_delay
    endif
    
    appendInfo: "."
    if k mod 4 = 0
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
Erase all
Select inner viewport: 0.5, 7.5, 0.5, 7.5

Axes: 0, gridCols, 0, gridRows
Colour: "Black"
Line width: 1

Text top: "yes", "Würfelspiel Complete - " + presetName$
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

# Draw all cells
for position from 1 to numberOfSegments
    row = floor((position - 1) / gridCols)
    col = (position - 1) mod gridCols
    
    x1 = col
    x2 = col + 1
    y1 = gridRows - row - 1
    y2 = gridRows - row
    xCenter = (x1 + x2) / 2
    yCenter = (y1 + y2) / 2
    
    selectedSeg = chosenSegment_'position'
    funcLabel$ = requiredLabel_'position'$
    
    if funcLabel$ = "T"
        Paint circle: "Purple", xCenter, yCenter, 0.35
    elsif funcLabel$ = "P"
        Paint circle: "Cyan", xCenter, yCenter, 0.35
    elsif funcLabel$ = "D"
        Paint circle: "Magenta", xCenter, yCenter, 0.35
    else
        Paint circle: "Pink", xCenter, yCenter, 0.35
    endif
    
    Colour: "White"
    Line width: 2
    Text: xCenter, "centre", yCenter + 0.1, "half", string$(selectedSeg)
    Text: xCenter, "centre", yCenter - 0.1, "half", funcLabel$
endfor

# Legend
Select inner viewport: 0.5, 7.5, 7.8, 8.5
Axes: 0, 1, 0, 1
Colour: "Black"
Line width: 1
Paint circle: "Purple", 0.05, 0.7, 0.015
Text: 0.08, "left", 0.7, "half", "T=Tonic"
Paint circle: "Cyan", 0.3, 0.7, 0.015
Text: 0.33, "left", 0.7, "half", "P=Predominant"
Paint circle: "Magenta", 0.6, 0.7, 0.015
Text: 0.63, "left", 0.7, "half", "D=Dominant"
Paint circle: "Pink", 0.05, 0.3, 0.015
Text: 0.08, "left", 0.3, "half", "C=Cadence"

# Summary
expressionText$ = ""
if apply_ritardando = 1 and apply_diminuendo = 1
    expressionText$ = " + rit. & dim."
elsif apply_ritardando = 1
    expressionText$ = " + rit."
elsif apply_diminuendo = 1
    expressionText$ = " + dim."
endif
Text: 0.5, "centre", 0.5, "half", "T-P-D-C | " + soundName$ + expressionText$

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

if play_final_result = 1
    appendInfoLine: "Playing result..."
    Play
endif

appendInfoLine: ""