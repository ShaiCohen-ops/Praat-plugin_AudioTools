# ============================================================
# Praat AudioTools - Percussive_Image_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Converts an image to percussive sound by scanning columns
#   left-to-right and generating clicks based on pixel data.
#
#   Sonification mapping:
#   - Column position → Time (left-to-right scan)
#   - Brightness (avg RGB) → Click rate (bright = faster)
#   - Brightness → Pitch (bright = higher, 800-2000 Hz)
#   - Brightness → Volume (bright = louder)
#   - Red-Blue balance → Stereo pan (red=left, blue=right)
#
# Usage:
#   Select a Photo object in Praat, then run this script.
#
# Changelog v0.2:
#   - Fixed stereo panning (was broken)
#   - Fixed click volume bug (earlier clicks were attenuated)
#   - Optimized min/max using built-in commands
#   - Added visualization
#   - Modern syntax
# ============================================================

form Percussive Image Sonification
    comment === Timing ===
    positive Duration_s 4.0
    integer Sample_rate_Hz 44100
    
    comment === Click Parameters ===
    positive Min_click_interval_s 0.08
    positive Max_click_interval_s 0.3
    positive Click_duration_s 0.05
    
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

# === Info ===
writeInfoLine: "=== Percussive Image Sonification ==="
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Click interval: ", min_click_interval_s, " - ", max_click_interval_s, " s"
appendInfoLine: ""

# === Extract RGB Channels ===
appendInfoLine: "Extracting color channels..."

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
nrows = Get number of rows
ncols = Get number of columns

appendInfoLine: "Image size: ", ncols, " x ", nrows, " pixels"

if ncols <= 0 or nrows <= 0
    removeObject: redID, greenID, blueID
    exitScript: "Invalid image dimensions."
endif

# === Get Min/Max Using Built-in Commands (FAST) ===
appendInfoLine: "Analyzing brightness range..."

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

appendInfoLine: "Value range: ", fixed$(overallMin, 2), " to ", fixed$(overallMax, 2)

# === Compute Per-Column Brightness and Pan ===
appendInfoLine: "Computing column statistics..."

for col to ncols
    # Red channel column average
    selectObject: redID
    rSum = 0
    for row to nrows
        .val = Get value in cell: row, col
        rSum = rSum + .val
    endfor
    rAvg = rSum / nrows
    rNorm = (rAvg - overallMin) / valueRange
    
    # Green channel column average
    selectObject: greenID
    gSum = 0
    for row to nrows
        .val = Get value in cell: row, col
        gSum = gSum + .val
    endfor
    gAvg = gSum / nrows
    gNorm = (gAvg - overallMin) / valueRange
    
    # Blue channel column average
    selectObject: blueID
    bSum = 0
    for row to nrows
        .val = Get value in cell: row, col
        bSum = bSum + .val
    endfor
    bAvg = bSum / nrows
    bNorm = (bAvg - overallMin) / valueRange
    
    # Store brightness and pan
    brightness[col] = (rNorm + gNorm + bNorm) / 3
    pan[col] = 0.5 + 0.5 * (rNorm - bNorm)
    pan[col] = max(0, min(1, pan[col]))
    
    if col mod 50 = 0
        appendInfoLine: "  Column ", col, "/", ncols
    endif
endfor

# === Create Stereo Output Sound ===
appendInfoLine: ""
appendInfoLine: "Generating clicks..."

leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Generate Clicks ===
currentTime = 0
col = 1
clickCount = 0

while currentTime < duration_s
    brightnessVal = brightness[col]
    panVal = pan[col]
    
    # Map brightness to parameters
    clickInterval = max_click_interval_s - brightnessVal * (max_click_interval_s - min_click_interval_s)
    clickVolume = 0.3 + brightnessVal * 0.7
    
    # Frequencies based on brightness
    baseFreq = 800 + brightnessVal * 1200
    midFreq = baseFreq * 2.5
    highFreq = baseFreq * 4
    
    tStart = currentTime
    
    # Build click formula
    sStart$ = fixed$(tStart, 6)
    sDur$ = fixed$(click_duration_s, 6)
    sBase$ = fixed$(baseFreq, 1)
    sMid$ = fixed$(midFreq, 1)
    sHigh$ = fixed$(highFreq, 1)
    
    # Envelope: raised cosine (Hann window)
    envPart$ = "((1 - cos(twoPi * (x - " + sStart$ + ") / " + sDur$ + ")) * 0.5)"
    
    # Click: sum of 3 harmonics
    tonePart$ = "(0.6 * sin(twoPi * " + sBase$ + " * (x - " + sStart$ + ")) + 0.3 * sin(twoPi * " + sMid$ + " * (x - " + sStart$ + ")) + 0.1 * sin(twoPi * " + sHigh$ + " * (x - " + sStart$ + ")))"
    
    # Click formula - NO self here, just returns the click or 0
    clickFormula$ = "if x >= " + sStart$ + " and x < " + sStart$ + " + " + sDur$ + " then " + envPart$ + " * " + tonePart$ + " else 0 fi"
    
    # Apply to LEFT channel: self + volume * click
    leftVol = (1 - panVal) * clickVolume
    selectObject: leftSound
    Formula: "self + " + fixed$(leftVol, 4) + " * (" + clickFormula$ + ")"
    
    # Apply to RIGHT channel: self + volume * click
    rightVol = panVal * clickVolume
    selectObject: rightSound
    Formula: "self + " + fixed$(rightVol, 4) + " * (" + clickFormula$ + ")"
    
    clickCount = clickCount + 1
    currentTime = currentTime + clickInterval
    col = col + 1
    if col > ncols
        col = 1
    endif
endwhile

appendInfoLine: "Generated ", clickCount, " clicks"

# === Combine to Stereo ===
selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "sonification_" + uid$

removeObject: leftSound, rightSound

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Cleanup ===
removeObject: redID, greenID, blueID

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
    Text: 0.5, "centre", 0.7, "half", "Percussive Image Sonification"
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", photoName$ + " | " + string$(ncols) + "x" + string$(nrows) + " | " + string$(clickCount) + " clicks"
    
    # === Brightness Profile ===
    Select outer viewport: 0, 7, 0.8, 2.3
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 0.9, 2.2
    Axes: 0, ncols, 0, 1
    
    # Draw brightness curve
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 1
    for .c from 2 to ncols
        Draw line: .c - 1, brightness[.c - 1], .c, brightness[.c]
    endfor
    
    # Draw pan curve
    Colour: "{0.8, 0.3, 0.3}"
    for .c from 2 to ncols
        Draw line: .c - 1, pan[.c - 1], .c, pan[.c]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Value"
    Text bottom: "yes", "Column (black=brightness, red=pan)"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 2.5, 5.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 2.6, 4.9
    
    selectObject: outputSound
    Extract one channel: 1
    .monoSpec = selected("Sound")
    
    selectObject: .monoSpec
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 2.6, 4.9
    Axes: 0, duration_s, 0, 5000
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Mapping Legend ===
    Select outer viewport: 0, 7, 5.1, 5.6
    Select inner viewport: 0, 7, 5.1, 5.6
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", "Brightness -> click rate + pitch + volume | Red-Blue -> stereo pan"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc