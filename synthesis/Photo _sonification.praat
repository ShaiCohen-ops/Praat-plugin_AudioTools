# ============================================================
# Praat AudioTools - Photo _sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Photo _sonification
#
# Usage:
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Select a Photo in the Objects list, then run.
# Builds a stereo noise whose color (low/mid/high), amplitude, and pan
# follow the image's RGB column averages across time.

# WARNING: This process can have long runtime on long files or high sampling frequencies.

############################
# FORM CONTROLS
############################

form Image Sonification Settings
    comment WARNING: This process can have long runtime on long files or high sampling frequencies.
    real duration(seconds) 3.0 
    integer fs(Hz) 44100  
    
    comment Low-frequency band (Red channel)
    integer lowF1(Hz) 100 
    integer lowF2(Hz) 800 
    
    comment Mid-frequency band (Green channel)
    integer midF1(Hz) 800 
    integer midF2(Hz) 3000 
    
    comment High-frequency band (Blue channel)
    integer highF1(Hz) 3000 
    integer highF2(Hz) 9000 
endform

############################
# USER SETTINGS (from form)
############################
# duration = 3.0      ; seconds
# fs = 44100          ; Hz

# ; Frequency bands for the three colorized noises
# lowF1  = 100
# lowF2  = 800
# midF1  = 800
# midF2  = 3000
# highF1 = 3000
# highF2 = 9000

############################
# 0) Get the selected Photo
############################
photoID = selected("Photo")
if photoID = 0
    exitScript: "Select a Photo object first (Objects window)."
endif

############################################
# 1) Extract R/G/B matrices
############################################
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

# Get matrix dimensions
selectObject: redID
nrows = Get number of rows
ncols = Get number of columns

if ncols <= 0
    exitScript: "Invalid number of columns in image (ncols <= 0)."
endif

# Compute global min for red
selectObject: redID
minRed = 1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val < minRed
            minRed = val
        endif
    endfor
endfor

# Compute global max for red
selectObject: redID
maxRed = -1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val > maxRed
            maxRed = val
        endif
    endfor
endfor

# Compute global min for green
selectObject: greenID
minGreen = 1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val < minGreen
            minGreen = val
        endif
    endfor
endfor

# Compute global max for green
selectObject: greenID
maxGreen = -1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val > maxGreen
            maxGreen = val
        endif
    endfor
endfor

# Compute global min for blue
selectObject: blueID
minBlue = 1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val < minBlue
            minBlue = val
        endif
    endfor
endfor

# Compute global max for blue
selectObject: blueID
maxBlue = -1e9
for irow from 1 to nrows
    for icol from 1 to ncols
        val = Get value in cell: irow, icol
        if val > maxBlue
            maxBlue = val
        endif
    endfor
endfor

# Global overall min and max across all channels
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

# Precompute normalized column averages as matrix variables
rNorms## = zero##(1, ncols)
gNorms## = zero##(1, ncols)
bNorms## = zero##(1, ncols)
ampPerCol## = zero##(1, ncols)
panPerCol## = zero##(1, ncols)

for col from 1 to ncols
    selectObject: redID
    rSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        rSum = rSum + val
    endfor
    rAvg = rSum / nrows
    rNorm = (rAvg - overallMin) / range
    rNorm = max(0, min(1, rNorm))
    rNorms##[1, col] = rNorm
    
    selectObject: greenID
    gSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        gSum = gSum + val
    endfor
    gAvg = gSum / nrows
    gNorm = (gAvg - overallMin) / range
    gNorm = max(0, min(1, gNorm))
    gNorms##[1, col] = gNorm
    
    selectObject: blueID
    bSum = 0
    for row from 1 to nrows
        val = Get value in cell: row, col
        bSum = bSum + val
    endfor
    bAvg = bSum / nrows
    bNorm = (bAvg - overallMin) / range
    bNorm = max(0, min(1, bNorm))
    bNorms##[1, col] = bNorm
    
    amp = (rNorm + gNorm + bNorm) / 3
    pan = 0.5 + 0.5 * (rNorm - bNorm)
    pan = max(0, min(1, pan))
    ampPerCol##[1, col] = amp
    panPerCol##[1, col] = pan
endfor

############################################
# 2) Create separate sounds and combine
############################################
nsamples = round(duration * fs)

# Create base noise
Create Sound from formula: "baseNoise", 1, 0, duration, fs, "randomUniform(-1, 1)"

selectObject: "Sound baseNoise"
Copy: "noiseLowBase"
Filter (pass Hann band): lowF1, lowF2, 100
Rename: "noiseLow"

selectObject: "Sound baseNoise"
Copy: "noiseMidBase"
Filter (pass Hann band): midF1, midF2, 100
Rename: "noiseMid"

selectObject: "Sound baseNoise"
Copy: "noiseHighBase"
Filter (pass Hann band): highF1, highF2, 100
Rename: "noiseHigh"

# Create empty envelope Sounds
Create Sound from formula: "redEnv", 1, 0, duration, fs, "0"
Create Sound from formula: "greenEnv", 1, 0, duration, fs, "0"
Create Sound from formula: "blueEnv", 1, 0, duration, fs, "0"
Create Sound from formula: "ampEnv", 1, 0, duration, fs, "0"
Create Sound from formula: "panEnv", 1, 0, duration, fs, "0"

# Populate envelopes in chunks
chunkDuration = duration / ncols
for col from 1 to ncols
    colIndex = col
    tStart = (col - 1) * chunkDuration
    tEnd = col * chunkDuration
    if col = ncols
        tEnd = duration
    endif
    rNorm = rNorms##[1, colIndex]
    selectObject: "Sound redEnv"
    Formula: "if x >= tStart and x <= tEnd then rNorm else self fi"
    
    gNorm = gNorms##[1, colIndex]
    selectObject: "Sound greenEnv"
    Formula: "if x >= tStart and x <= tEnd then gNorm else self fi"
    
    bNorm = bNorms##[1, colIndex]
    selectObject: "Sound blueEnv"
    Formula: "if x >= tStart and x <= tEnd then bNorm else self fi"
    
    amp = ampPerCol##[1, colIndex]
    selectObject: "Sound ampEnv"
    Formula: "if x >= tStart and x <= tEnd then amp else self fi"
    
    pan = panPerCol##[1, colIndex]
    selectObject: "Sound panEnv"
    Formula: "if x >= tStart and x <= tEnd then pan else self fi"
endfor

# Modulate noises with color envelopes
selectObject: "Sound noiseLow"
Copy: "lowModulated"
lowModID = selected("Sound")
plusObject: "Sound redEnv"
Formula: "self * Sound_redEnv[]"

selectObject: "Sound noiseMid"
Copy: "midModulated"
midModID = selected("Sound")
plusObject: "Sound greenEnv"
Formula: "self * Sound_greenEnv[]"

selectObject: "Sound noiseHigh"
Copy: "highModulated"
highModID = selected("Sound")
plusObject: "Sound blueEnv"
Formula: "self * Sound_blueEnv[]"

# Combine modulated bands to mono
selectObject: lowModID
plusObject: midModID
Combine to stereo
stereo1ID = selected("Sound")
Convert to mono
combinedTempID = selected("Sound")
Rename: "combinedTemp"

selectObject: combinedTempID
plusObject: highModID
Combine to stereo
stereo2ID = selected("Sound")
Convert to mono
combinedBandsID = selected("Sound")
Rename: "combinedBands"

# Apply amplitude envelope
selectObject: combinedBandsID
Copy: "amplifiedMono"
amplifiedMonoID = selected("Sound")
plusObject: "Sound ampEnv"
Formula: "self * Sound_ampEnv[]"

# Create gain envelopes for panning (constant power)
selectObject: "Sound panEnv"
Copy: "gainRightEnv"
gainRightID = selected("Sound")
Formula: "sqrt(self)"

selectObject: "Sound panEnv"
Copy: "gainLeftEnv"
gainLeftID = selected("Sound")
Formula: "sqrt(1 - self)"

# Apply panning
selectObject: amplifiedMonoID
Copy: "pannedLeft"
pannedLeftID = selected("Sound")
plusObject: gainLeftID
Formula: "self * Sound_gainLeftEnv[]"

selectObject: amplifiedMonoID
Copy: "pannedRight"
pannedRightID = selected("Sound")
plusObject: gainRightID
Formula: "self * Sound_gainRightEnv[]"

# Combine to stereo
selectObject: pannedLeftID
plusObject: pannedRightID
Combine to stereo
finalStereoID = selected("Sound")
Rename: "finalStereo"

selectObject: finalStereoID
Scale peak: 0.99
Play

############################################
# 3) Clean up
############################################
# Remove matrix objects
removeObject: redID
removeObject: greenID
removeObject: blueID

# Remove base and filtered noises
removeObject: "Sound baseNoise"
removeObject: "Sound noiseLowBase"
removeObject: "Sound noiseMidBase"
removeObject: "Sound noiseHighBase"
removeObject: "Sound noiseLow"
removeObject: "Sound noiseMid"
removeObject: "Sound noiseHigh"

# Remove envelope sounds
removeObject: "Sound redEnv"
removeObject: "Sound greenEnv"
removeObject: "Sound blueEnv"
removeObject: "Sound ampEnv"
removeObject: "Sound panEnv"

# Remove modulated sounds
removeObject: lowModID
removeObject: midModID
removeObject: highModID

# Remove stereo intermediate objects
removeObject: stereo1ID
removeObject: combinedTempID
removeObject: stereo2ID
removeObject: combinedBandsID

# Remove amplitude and panning objects
removeObject: amplifiedMonoID
removeObject: gainLeftID
removeObject: gainRightID
removeObject: pannedLeftID
removeObject: pannedRightID

# Rename final output
selectObject: finalStereoID
Rename: "imageSonification"
echo Sonification complete! Play "imageSonification" to hear the result.
echo Low freq ~ Red, Mid ~ Green, High ~ Blue; Amp = avg RGB; Pan = Red-Blue diff.