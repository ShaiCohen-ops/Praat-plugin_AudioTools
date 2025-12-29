# ============================================================
# Praat AudioTools - Percussive Image Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Percussive Image Sonification
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Percussive Image Sonification
# Creates audible rhythmic clicks with multiple frequency components

form Enhanced Percussive Image Sonification
    real duration(seconds) 4.0
    integer fs(Hz) 44100
    real minClickInterval 0.08
    real maxClickInterval 0.3
    real clickDuration 0.05
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

Create Sound from formula: "percussiveSonification", 2, 0, duration, fs, "0"

currentTime = 0
col = 1

while currentTime < duration
    brightnessVal = brightness##[1, col]
    panVal = pan##[1, col]
    
    clickInterval = maxClickInterval - brightnessVal * (maxClickInterval - minClickInterval)
    clickVolume = brightnessVal * 1.2
    
    tStart = currentTime
    tEnd = currentTime + clickDuration
    
    if tEnd > duration
        tEnd = duration
    endif
    
    baseFreq = 800 + brightnessVal * 1200
    midFreq = baseFreq * 2.5
    highFreq = baseFreq * 4
    
    selectObject: "Sound percussiveSonification"
    Formula: "if x >= tStart and x <= tEnd then (1 - panVal) * ((1 - cos(2*pi*(x-tStart)/clickDuration)) * 0.5) * clickVolume * (0.6*sin(2*pi*'baseFreq'*(x-tStart)) + 0.3*sin(2*pi*'midFreq'*(x-tStart)) + 0.1*sin(2*pi*'highFreq'*(x-tStart))) else self fi"
    
    selectObject: "Sound percussiveSonification"
    Formula: "if x >= tStart and x <= tEnd then panVal * ((1 - cos(2*pi*(x-tStart)/clickDuration)) * 0.5) * clickVolume * (0.6*sin(2*pi*'baseFreq'*(x-tStart)) + 0.3*sin(2*pi*'midFreq'*(x-tStart)) + 0.1*sin(2*pi*'highFreq'*(x-tStart))) else self fi"
    
    currentTime = currentTime + clickInterval
    col = col + 1
    if col > ncols
        col = 1
    endif
endwhile

selectObject: "Sound percussiveSonification"
Scale peak: 0.9
Rename: "image_percussive_sonification"
Play

removeObject: redID, greenID, blueID

echo Enhanced percussive sonification complete!