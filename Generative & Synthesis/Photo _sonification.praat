# ============================================================
# Praat AudioTools - Photo_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonifies an image by mapping RGB channels to frequency bands:
#   - Red → Low frequencies (warm = bass)
#   - Green → Mid frequencies
#   - Blue → High frequencies (cool = treble)
#   - Brightness → Amplitude
#   - Red-Blue balance → Stereo pan
#
# Usage:
#   Select a Photo object in Praat, then run this script.
#
# Changelog v0.3:
#   - Added image downsampling for fast processing
#   - Fixed object cleanup bug
# ============================================================

form Photo Sonification (RGB to Frequency)
    comment === Timing ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    
    comment === Analysis Resolution ===
    integer Analysis_columns 200 (= time slices, 50-500)
    integer Analysis_rows 100 (= vertical samples, 20-200)
    
    comment === Frequency Bands ===
    integer Low_band_min_Hz 100
    integer Low_band_max_Hz 800
    integer Mid_band_min_Hz 800
    integer Mid_band_max_Hz 3000
    integer High_band_min_Hz 3000
    integer High_band_max_Hz 9000
    
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

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Extract RGB Channels ===
selectObject: photoID
photoName$ = selected$("Photo")

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

# === Clamp analysis resolution to image size ===
if analysis_columns > imgCols
    analysis_columns = imgCols
endif
if analysis_rows > imgRows
    analysis_rows = imgRows
endif

colStep = imgCols / analysis_columns
rowStep = imgRows / analysis_rows

# === Info ===
writeInfoLine: "=== Photo Sonification (RGB → Frequency) ==="
appendInfoLine: "Image: ", photoName$
appendInfoLine: "Original size: ", imgCols, " x ", imgRows, " pixels"
appendInfoLine: "Analysis resolution: ", analysis_columns, " x ", analysis_rows
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: ""

# === Get Min/Max ===
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

# === Compute Downsampled Column Statistics ===
appendInfoLine: "Computing column statistics..."

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
    
    for aRow to analysis_rows
        imgRow = round((aRow - 0.5) * rowStep)
        if imgRow < 1
            imgRow = 1
        endif
        if imgRow > imgRows
            imgRow = imgRows
        endif
        
        selectObject: redID
        .rVal = Get value in cell: imgRow, imgCol
        rSum = rSum + .rVal
        
        selectObject: greenID
        .gVal = Get value in cell: imgRow, imgCol
        gSum = gSum + .gVal
        
        selectObject: blueID
        .bVal = Get value in cell: imgRow, imgCol
        bSum = bSum + .bVal
    endfor
    
    rAvg = rSum / analysis_rows
    gAvg = gSum / analysis_rows
    bAvg = bSum / analysis_rows
    
    rNorm[aCol] = (rAvg - overallMin) / valueRange
    rNorm[aCol] = max(0, min(1, rNorm[aCol]))
    
    gNorm[aCol] = (gAvg - overallMin) / valueRange
    gNorm[aCol] = max(0, min(1, gNorm[aCol]))
    
    bNorm[aCol] = (bAvg - overallMin) / valueRange
    bNorm[aCol] = max(0, min(1, bNorm[aCol]))
    
    ampCol[aCol] = (rNorm[aCol] + gNorm[aCol] + bNorm[aCol]) / 3
    
    panCol[aCol] = 0.5 + 0.5 * (rNorm[aCol] - bNorm[aCol])
    panCol[aCol] = max(0, min(1, panCol[aCol]))
    
    if aCol mod 50 = 0
        appendInfoLine: "  Column ", aCol, "/", analysis_columns
    endif
endfor

# === Create Base Noise ===
appendInfoLine: "Creating filtered noise bands..."

baseNoise = Create Sound from formula: "base_" + uid$, 1, 0, duration_s, sample_rate_Hz, "randomUniform(-1, 1)"

# === Create Filtered Noise Bands ===
selectObject: baseNoise
Filter (pass Hann band): low_band_min_Hz, low_band_max_Hz, 100
lowNoise = selected("Sound")
Rename: "low_" + uid$

selectObject: baseNoise
Filter (pass Hann band): mid_band_min_Hz, mid_band_max_Hz, 100
midNoise = selected("Sound")
Rename: "mid_" + uid$

selectObject: baseNoise
Filter (pass Hann band): high_band_min_Hz, high_band_max_Hz, 100
highNoise = selected("Sound")
Rename: "high_" + uid$

removeObject: baseNoise

# === Create Envelope Sounds ===
appendInfoLine: "Creating modulation envelopes..."

redEnv = Create Sound from formula: "redEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
greenEnv = Create Sound from formula: "greenEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
blueEnv = Create Sound from formula: "blueEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
ampEnv = Create Sound from formula: "ampEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
panEnv = Create Sound from formula: "panEnv_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

chunkDuration = duration_s / analysis_columns

for aCol to analysis_columns
    tStart = (aCol - 1) * chunkDuration
    tEnd = aCol * chunkDuration
    if aCol = analysis_columns
        tEnd = duration_s
    endif
    
    sStart$ = fixed$(tStart, 6)
    sEnd$ = fixed$(tEnd, 6)
    
    rVal$ = fixed$(rNorm[aCol], 4)
    selectObject: redEnv
    Formula: "if x >= " + sStart$ + " and x < " + sEnd$ + " then " + rVal$ + " else self fi"
    
    gVal$ = fixed$(gNorm[aCol], 4)
    selectObject: greenEnv
    Formula: "if x >= " + sStart$ + " and x < " + sEnd$ + " then " + gVal$ + " else self fi"
    
    bVal$ = fixed$(bNorm[aCol], 4)
    selectObject: blueEnv
    Formula: "if x >= " + sStart$ + " and x < " + sEnd$ + " then " + bVal$ + " else self fi"
    
    aVal$ = fixed$(ampCol[aCol], 4)
    selectObject: ampEnv
    Formula: "if x >= " + sStart$ + " and x < " + sEnd$ + " then " + aVal$ + " else self fi"
    
    pVal$ = fixed$(panCol[aCol], 4)
    selectObject: panEnv
    Formula: "if x >= " + sStart$ + " and x < " + sEnd$ + " then " + pVal$ + " else self fi"
endfor

# === Modulate Noise Bands ===
appendInfoLine: "Modulating noise bands..."

redEnvName$ = "Sound_redEnv_" + uid$
greenEnvName$ = "Sound_greenEnv_" + uid$
blueEnvName$ = "Sound_blueEnv_" + uid$
ampEnvName$ = "Sound_ampEnv_" + uid$
panEnvName$ = "Sound_panEnv_" + uid$

selectObject: lowNoise
Formula: "self * " + redEnvName$ + "[]"

selectObject: midNoise
Formula: "self * " + greenEnvName$ + "[]"

selectObject: highNoise
Formula: "self * " + blueEnvName$ + "[]"

# === Combine Bands ===
appendInfoLine: "Combining frequency bands..."

lowName$ = "Sound_low_" + uid$
midName$ = "Sound_mid_" + uid$
highName$ = "Sound_high_" + uid$

combinedMono = Create Sound from formula: "combined_" + uid$, 1, 0, duration_s, sample_rate_Hz, lowName$ + "[] + " + midName$ + "[] + " + highName$ + "[]"

combinedName$ = "Sound_combined_" + uid$
selectObject: combinedMono
Formula: "self * " + ampEnvName$ + "[]"

# === Create Stereo with Panning ===
appendInfoLine: "Applying stereo panning..."

leftCh = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "sqrt(max(0, 1 - " + panEnvName$ + "[])) * " + combinedName$ + "[]"

rightCh = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "sqrt(max(0, " + panEnvName$ + "[])) * " + combinedName$ + "[]"

selectObject: leftCh
plusObject: rightCh
outputSound = Combine to stereo
Rename: "sonification_" + photoName$

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Cleanup ===
appendInfoLine: "Cleaning up..."

removeObject: redID, greenID, blueID
removeObject: lowNoise, midNoise, highNoise
removeObject: redEnv, greenEnv, blueEnv, ampEnv, panEnv
removeObject: combinedMono, leftCh, rightCh

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
    Text: 0.5, "centre", 0.7, "half", "Photo Sonification — " + photoName$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", string$(imgCols) + "x" + string$(imgRows) + " -> " + string$(analysis_columns) + " time slices"
    
    # === RGB Profiles ===
    Select outer viewport: 0, 7, 0.8, 2.5
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 0.9, 2.4
    Axes: 0, analysis_columns, 0, 1
    
    Line width: 1
    
    Colour: "{0.9, 0.2, 0.2}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, rNorm[.c - 1], .c, rNorm[.c]
    endfor
    
    Colour: "{0.2, 0.8, 0.2}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, gNorm[.c - 1], .c, gNorm[.c]
    endfor
    
    Colour: "{0.2, 0.2, 0.9}"
    for .c from 2 to analysis_columns
        Draw line: .c - 1, bNorm[.c - 1], .c, bNorm[.c]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "RGB"
    Text bottom: "yes", "Column (R=low, G=mid, B=high)"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 2.7, 5.2
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 2.8, 5.1
    
    selectObject: outputSound
    Extract one channel: 1
    .monoSpec = selected("Sound")
    
    selectObject: .monoSpec
    .maxFreq = high_band_max_Hz + 1000
    To Spectrogram: 0.02, .maxFreq, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 2.8, 5.1
    Axes: 0, duration_s, 0, .maxFreq
    
    Colour: "{1, 0.5, 0.5}"
    Dotted line
    Draw line: 0, low_band_max_Hz, duration_s, low_band_max_Hz
    
    Colour: "{0.5, 1, 0.5}"
    Draw line: 0, mid_band_max_Hz, duration_s, mid_band_max_Hz
    Solid line
    
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 5.3, 5.7
    Select inner viewport: 0, 7, 5.3, 5.7
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "R->Low | G->Mid | B->High | Brightness->Volume | R-B->Pan"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc