# ============================================================
# Praat AudioTools - Spectral Image Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Image Sonification
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Spectral Image Sonification
# Creates evolving harmonic spectrum based on image colors

form Spectral Image Sonification
    real duration(seconds) 5.0
    integer fs(Hz) 44100
    integer fundamentalFreq(Hz) 110
    integer maxHarmonics 16
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

redAmps## = zero##(1, ncols)
greenAmps## = zero##(1, ncols)
blueAmps## = zero##(1, ncols)

for col from 1 to ncols
    selectObject: redID
    rSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        rSum = rSum + val
    endfor
    rAvg = rSum / nrows
    redAmps##[1, col] = (rAvg - overallMin) / range
    
    selectObject: greenID
    gSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        gSum = gSum + val
    endfor
    gAvg = gSum / nrows
    greenAmps##[1, col] = (gAvg - overallMin) / range
    
    selectObject: blueID
    bSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        bSum = bSum + val
    endfor
    bAvg = bSum / nrows
    blueAmps##[1, col] = (bAvg - overallMin) / range
endfor

Create Sound from formula: "spectralSonification", 2, 0, duration, fs, "0"

for col from 1 to ncols
    tStart = (col - 1) * duration / ncols
    tEnd = col * duration / ncols
    if col = ncols
        tEnd = duration
    endif
    
    redAmp = redAmps##[1, col]
    greenAmp = greenAmps##[1, col]
    blueAmp = blueAmps##[1, col]
    
    totalAmp = (redAmp + greenAmp + blueAmp) / 3
    panPos = 0.5 + 0.3 * (redAmp - blueAmp)
    
    if totalAmp > 0.1
        soundFormula$ = "0"
        for harmonic from 1 to maxHarmonics
            freq = fundamentalFreq * harmonic
            
            if harmonic mod 3 = 1
                amp = redAmp * (1 / harmonic)
            elsif harmonic mod 3 = 2
                amp = greenAmp * (1 / harmonic)
            else
                amp = blueAmp * (1 / harmonic)
            endif
            
            if harmonic > 1
                soundFormula$ = soundFormula$ + " + "
            endif
            soundFormula$ = soundFormula$ + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
        endfor
        
        selectObject: "Sound spectralSonification"
        Formula: "if x >= tStart and x <= tEnd then (1 - panPos) * (" + soundFormula$ + ") else self fi"
        
        selectObject: "Sound spectralSonification"
        Formula: "if x >= tStart and x <= tEnd then panPos * (" + soundFormula$ + ") else self fi"
    endif
endfor

selectObject: "Sound spectralSonification"
Scale peak: 0.8
Rename: "image_spectral_sonification"
Play

removeObject: redID, greenID, blueID

echo Spectral sonification complete!