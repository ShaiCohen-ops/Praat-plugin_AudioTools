# ============================================================
# Praat AudioTools - Photo Brightness-Controlled Pitch Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Photo Brightness-Controlled Pitch Sonification
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Photo Brightness-Controlled Pitch Sonification
# Image brightness controls pitch, colors control stereo position

form Brightness-Controlled Pitch Sonification
    real duration(seconds) 3.0
    integer fs(Hz) 44100
    integer minPitch(Hz) 100
    integer maxPitch(Hz) 1000
endform

photoID = selected("Photo")
if photoID = 0
    exitScript: "Select a Photo object first."
endif

selectObject: photoID
Extract red
redID = selected("Matrix")
if redID = 0
    exitScript: "Failed to extract red channel as Matrix."
endif

selectObject: photoID
Extract green
greenID = selected("Matrix")
if greenID = 0
    exitScript: "Failed to extract green channel as Matrix."
endif

selectObject: photoID
Extract blue
blueID = selected("Matrix")
if blueID = 0
    exitScript: "Failed to extract blue channel as Matrix."
endif

selectObject: redID
nrows = Get number of rows
ncols = Get number of columns

if ncols <= 0
    exitScript: "Invalid number of columns in image (ncols <= 0)."
endif

selectObject: redID
minRed = 1e9
maxRed = -1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val < minRed
            minRed = val
        endif
        if val > maxRed
            maxRed = val
        endif
    endfor
endfor

selectObject: greenID
minGreen = 1e9
maxGreen = -1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val < minGreen
            minGreen = val
        endif
        if val > maxGreen
            maxGreen = val
        endif
    endfor
endfor

selectObject: blueID
minBlue = 1e9
maxBlue = -1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val < minBlue
            minBlue = val
        endif
        if val > maxBlue
            maxBlue = val
        endif
    endfor
endfor

overallMin = minRed
if minGreen < overallMin
    overallMin = minGreen
endif
if minBlue < overallMin
    overallMin = minBlue
endif

overallMax = maxRed
if maxGreen > overallMax
    overallMax = maxGreen
endif
if maxBlue > overallMax
    overallMax = maxBlue
endif

range = overallMax - overallMin
if range = 0
    range = 1
endif

brightness## = zero##(1, ncols)
pan## = zero##(1, ncols)

for col from 1 to ncols
    selectObject: redID
    rSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        rSum = rSum + val
    endfor
    rAvg = rSum / nrows
    rNorm = (rAvg - overallMin) / range
    
    selectObject: greenID
    gSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        gSum = gSum + val
    endfor
    gAvg = gSum / nrows
    gNorm = (gAvg - overallMin) / range
    
    selectObject: blueID
    bSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        bSum = bSum + val
    endfor
    bAvg = bSum / nrows
    bNorm = (bAvg - overallMin) / range
    
    brightness##[1, col] = (rNorm + gNorm + bNorm) / 3
    pan##[1, col] = 0.5 + 0.5 * (rNorm - bNorm)
endfor

Create Sound from formula: "pitchSonification", 2, 0, duration, fs, "0"

for col from 1 to ncols
    colIndex = col
    tStart = (col - 1) * duration / ncols
    tEnd = col * duration / ncols
    if col = ncols
        tEnd = duration
    endif
    
    brightnessVal = brightness##[1, colIndex]
    panVal = pan##[1, colIndex]
    
    freq = minPitch + brightnessVal * (maxPitch - minPitch)
    
    selectObject: "Sound pitchSonification"
    Formula: "if x >= tStart and x <= tEnd then (1 - panVal) * sin(2*pi*freq*x) else self fi"
    
    selectObject: "Sound pitchSonification"
    Formula: "if x >= tStart and x <= tEnd then panVal * sin(2*pi*freq*x) else self fi"
endfor

selectObject: "Sound pitchSonification"
Scale peak: 0.8
Rename: "image_pitch_sonification"
Play

removeObject: redID, greenID, blueID

echo Brightness-controlled pitch sonification complete!