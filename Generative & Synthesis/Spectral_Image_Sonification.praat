# ============================================================
# Praat AudioTools - Spectral_Image_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Pan direction matches documented mapping
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonifies an image using additive synthesis. RGB channels control
#   the amplitudes of different harmonic groups:
#   - Red → Harmonics 1, 4, 7, 10... (fundamental + every 3rd)
#   - Green → Harmonics 2, 5, 8, 11...
#   - Blue → Harmonics 3, 6, 9, 12...
#
# Usage:
#   Select a Photo object in Praat, then run this script.
#
# Changelog v0.3:
#   - Major performance optimization via smaller analysis grid
#   - Reduced harmonics and smarter synthesis
#   - Chunked time-slice approach
#
# Changelog v0.4:
#   - Stereo gains corrected so red pans left / blue pans right, as documented
#     (code previously sent red to the right).
# ============================================================

form Spectral Image Sonification (Additive)
    comment === Timing ===
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    
    comment === Synthesis ===
    positive Fundamental_Hz 110
    integer Max_harmonics 12
    
    comment === Analysis Resolution (smaller = faster) ===
    integer Analysis_columns 80
    integer Sample_rows_per_column 8
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check for Photo selection ===
nPhotos = numberOfSelected("Photo")
if nPhotos = 0
    exitScript: "Please select a Photo object first."
endif

photoID = selected("Photo")
photoName$ = selected$("Photo")

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Extract RGB Channels ===
selectObject: photoID
Extract red
redID = selected("Matrix")

selectObject: photoID
Extract green
greenID = selected("Matrix")

selectObject: photoID
Extract blue
blueID = selected("Matrix")

# === Get Image Dimensions ===
selectObject: redID
imgRows = Get number of rows
imgCols = Get number of columns

if imgCols <= 0 or imgRows <= 0
    removeObject: redID, greenID, blueID
    exitScript: "Invalid image dimensions."
endif

# === Clamp analysis resolution ===
if analysis_columns > imgCols
    analysis_columns = imgCols
endif

colStep = imgCols / analysis_columns
rowStep = imgRows / sample_rows_per_column

# === Get Global Min/Max ===
selectObject: redID
minRed = Get minimum
maxRed = Get maximum

selectObject: greenID
minGreen = Get minimum
maxGreen = Get maximum

selectObject: blueID
minBlue = Get minimum
maxBlue = Get maximum

overallMin = min(minRed, min(minGreen, minBlue))
overallMax = max(maxRed, max(maxGreen, maxBlue))
valueRange = overallMax - overallMin
if valueRange = 0
    valueRange = 1
endif

# === Info ===
writeInfoLine: "=== Spectral Image Sonification ==="
appendInfoLine: "Image: ", photoName$, " (", imgCols, " x ", imgRows, ")"
appendInfoLine: "Analysis: ", analysis_columns, " columns x ", sample_rows_per_column, " sample rows"
appendInfoLine: "Fundamental: ", fundamental_Hz, " Hz, Harmonics: ", max_harmonics
appendInfoLine: ""

# === Fast RGB Sampling (sparse row sampling) ===
appendInfoLine: "Analyzing image..."

for aCol to analysis_columns
    imgCol = round((aCol - 0.5) * colStep)
    if imgCol < 1
        imgCol = 1
    endif
    if imgCol > imgCols
        imgCol = imgCols
    endif
    
    rSum = 0
    gSum = 0
    bSum = 0
    
    # Sample only a few rows per column (much faster!)
    for sRow to sample_rows_per_column
        imgRow = round((sRow - 0.5) * rowStep)
        if imgRow < 1
            imgRow = 1
        endif
        if imgRow > imgRows
            imgRow = imgRows
        endif
        
        selectObject: redID
        rVal = Get value in cell: imgRow, imgCol
        rSum = rSum + rVal
        
        selectObject: greenID
        gVal = Get value in cell: imgRow, imgCol
        gSum = gSum + gVal
        
        selectObject: blueID
        bVal = Get value in cell: imgRow, imgCol
        bSum = bSum + bVal
    endfor
    
    redAmp[aCol] = (rSum / sample_rows_per_column - overallMin) / valueRange
    if redAmp[aCol] < 0
        redAmp[aCol] = 0
    endif
    if redAmp[aCol] > 1
        redAmp[aCol] = 1
    endif
    
    greenAmp[aCol] = (gSum / sample_rows_per_column - overallMin) / valueRange
    if greenAmp[aCol] < 0
        greenAmp[aCol] = 0
    endif
    if greenAmp[aCol] > 1
        greenAmp[aCol] = 1
    endif
    
    blueAmp[aCol] = (bSum / sample_rows_per_column - overallMin) / valueRange
    if blueAmp[aCol] < 0
        blueAmp[aCol] = 0
    endif
    if blueAmp[aCol] > 1
        blueAmp[aCol] = 1
    endif
    
    totalAmp[aCol] = (redAmp[aCol] + greenAmp[aCol] + blueAmp[aCol]) / 3
    
    # Pan: red = left, blue = right
    pan[aCol] = 0.5 + 0.3 * (redAmp[aCol] - blueAmp[aCol])
    if pan[aCol] < 0.1
        pan[aCol] = 0.1
    endif
    if pan[aCol] > 0.9
        pan[aCol] = 0.9
    endif
endfor

appendInfoLine: "Analysis complete."

# === Synthesize Directly (chunked by time slices) ===
appendInfoLine: "Synthesizing..."

leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

sliceDuration = duration_s / analysis_columns
columnsPerChunk = 10

nChunks = ceiling(analysis_columns / columnsPerChunk)

for chunk to nChunks
    startCol = (chunk - 1) * columnsPerChunk + 1
    endCol = min(chunk * columnsPerChunk, analysis_columns)
    
    leftFormula$ = ""
    rightFormula$ = ""
    
    for aCol from startCol to endCol
        tStart = (aCol - 1) * sliceDuration
        tEnd = aCol * sliceDuration
        
        # Skip quiet columns
        if totalAmp[aCol] < 0.05
            goto nextColumn
        endif
        
        tStart$ = fixed$(tStart, 6)
        tEnd$ = fixed$(tEnd, 6)
        
        # Build harmonic sum for this column
        harmonicSum$ = ""
        for h to max_harmonics
            freq = fundamental_Hz * h
            freq$ = fixed$(freq, 1)
            
            # RGB -> harmonic assignment (1,4,7->R; 2,5,8->G; 3,6,9->B)
            colorIdx = ((h - 1) mod 3) + 1
            if colorIdx = 1
                hAmp = redAmp[aCol] / h
            elsif colorIdx = 2
                hAmp = greenAmp[aCol] / h
            else
                hAmp = blueAmp[aCol] / h
            endif
            
            hAmp = hAmp * totalAmp[aCol] * 0.5
            
            if hAmp > 0.001
                hAmp$ = fixed$(hAmp, 5)
                if harmonicSum$ = ""
                    harmonicSum$ = hAmp$ + "*sin(twoPi*" + freq$ + "*x)"
                else
                    harmonicSum$ = harmonicSum$ + "+" + hAmp$ + "*sin(twoPi*" + freq$ + "*x)"
                endif
            endif
        endfor
        
        if harmonicSum$ <> ""
            # Half-sine envelope for smooth transitions
            envFormula$ = "sin(pi*(x-" + tStart$ + ")/" + fixed$(sliceDuration, 6) + ")"
            
            leftGain = sqrt(pan[aCol])
            rightGain = sqrt(1 - pan[aCol])
            leftGain$ = fixed$(leftGain, 4)
            rightGain$ = fixed$(rightGain, 4)
            
            sliceL$ = "if x>=" + tStart$ + " and x<" + tEnd$ + " then " + leftGain$ + "*" + envFormula$ + "*(" + harmonicSum$ + ") else 0 fi"
            sliceR$ = "if x>=" + tStart$ + " and x<" + tEnd$ + " then " + rightGain$ + "*" + envFormula$ + "*(" + harmonicSum$ + ") else 0 fi"
            
            if leftFormula$ = ""
                leftFormula$ = sliceL$
                rightFormula$ = sliceR$
            else
                leftFormula$ = leftFormula$ + " + " + sliceL$
                rightFormula$ = rightFormula$ + " + " + sliceR$
            endif
        endif
        
        label nextColumn
    endfor
    
    if leftFormula$ <> ""
        selectObject: leftSound
        Formula: "self + (" + leftFormula$ + ")"
        
        selectObject: rightSound
        Formula: "self + (" + rightFormula$ + ")"
    endif
    
    appendInfoLine: "  Chunk ", chunk, "/", nChunks
endfor

# === Combine to Stereo ===
selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "spectral_" + photoName$

removeObject: leftSound, rightSound

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.03 then self * (x / 0.03) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Cleanup ===
removeObject: redID, greenID, blueID

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Spectral Image Sonification — " + photoName$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "F0=" + string$(fundamental_Hz) + " Hz | " + string$(max_harmonics) + " harmonics"
    
    # === RGB Profiles ===
    Select outer viewport: 0, 7, 0.9, 2.5
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 1.0, 2.4
    Axes: 0, analysis_columns, 0, 1
    
    # Red
    Colour: "{0.9, 0.2, 0.2}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, redAmp[.c - 1], .c, redAmp[.c]
    endfor
    
    # Green
    Colour: "{0.2, 0.8, 0.2}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, greenAmp[.c - 1], .c, greenAmp[.c]
    endfor
    
    # Blue
    Colour: "{0.2, 0.2, 0.9}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, blueAmp[.c - 1], .c, blueAmp[.c]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "RGB"
    Text bottom: "yes", "Column"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 2.7, 5.2
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 2.8, 5.1
    
    selectObject: outputSound
    Extract one channel: 1
    .monoSpec = selected("Sound")
    
    .maxFreq = fundamental_Hz * (max_harmonics + 2)
    selectObject: .monoSpec
    To Spectrogram: 0.03, .maxFreq, 0.01, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 2.8, 5.1
    Axes: 0, duration_s, 0, .maxFreq
    
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc