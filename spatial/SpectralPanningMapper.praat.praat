# ============================================================
# Praat AudioTools - SpectralPanningMapper.praat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Spectral to Panning Positions
    comment Analyze spectral content and create dynamic panning
    positive Number_of_analysis_windows 8
    positive Panning_update_rate_(per_second) 100
    positive Base_panning_depth 0.3
    positive Flatness_panning_influence 0.7
    positive Base_motion_speed_(Hz) 0.5
    positive Roughness_motion_influence 3.0
endform

clearinfo

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

appendInfoLine: "=== SPECTRAL TO PANNING POSITIONS ==="
originalSound = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalSound
duration = Get total duration
sampling = Get sampling frequency
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"

selectObject: originalSound
numberOfChannels = Get number of channels
appendInfoLine: "Number of channels: ", numberOfChannels

if numberOfChannels = 1
    appendInfoLine: "Mono sound detected - duplicating for stereo processing"
    leftChannel = Copy: "left_" + originalName$
    rightChannel = Copy: "right_" + originalName$
else
    appendInfoLine: "Stereo sound detected - extracting channels"
    leftChannel = Extract one channel: 1
    rightChannel = Extract one channel: 1
endif

numAnalysisPoints = number_of_analysis_windows
analysisTimes# = zero#(numAnalysisPoints)
flatness# = zero#(numAnalysisPoints)
roughness# = zero#(numAnalysisPoints)

appendInfoLine: newline$, "=== ANALYZING ", numAnalysisPoints, " TIME WINDOWS ==="

for point from 1 to numAnalysisPoints
    analysisTimes#[point] = (point - 1) * duration / (numAnalysisPoints - 1)
    
    if analysisTimes#[point] < 0.1
        analysisTimes#[point] = 0.1
    endif
    if analysisTimes#[point] > duration - 0.2
        analysisTimes#[point] = duration - 0.2
    endif
    
    beginTime = analysisTimes#[point] - 0.1
    endTime = analysisTimes#[point] + 0.1
    
    if beginTime < 0
        beginTime = 0
    endif
    if endTime > duration
        endTime = duration
    endif
    
    selectObject: originalSound
    windowSound = Extract part: beginTime, endTime, "Hamming", 1, "no"
    
    selectObject: windowSound
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    
    minFreq = 80
    maxFreq = 5000
    lnSum = 0
    linearSum = 0
    validBins = 0
    roughnessSum = 0
    roughnessBins = 0
    
    selectObject: spectrum
    nBins = Get number of bins
    binWidth = Get bin width
    
    for bin from 1 to nBins
        freq = (bin - 1) * binWidth
        if freq >= minFreq and freq <= maxFreq
            amp = Get real value in bin: bin
            power = amp * amp
            power = max(power, 1e-12)
            lnSum = lnSum + ln(power)
            linearSum = linearSum + power
            
            if bin > 1 and bin < nBins
                ampPrev = Get real value in bin: bin-1
                ampNext = Get real value in bin: bin+1
                roughnessSum = roughnessSum + abs(amp - (ampPrev + ampNext)/2)
                roughnessBins = roughnessBins + 1
            endif
            
            validBins = validBins + 1
        endif
    endfor
    
    if validBins > 0 and roughnessBins > 0
        flatness#[point] = exp(lnSum / validBins) / (linearSum / validBins)
        roughness#[point] = roughnessSum / roughnessBins
    else
        flatness#[point] = 0.2
        roughness#[point] = 0.02
    endif
    
    appendInfoLine: "Window ", point, " (", fixed$(analysisTimes#[point], 2), "s) - ",
      ... "Flatness: ", fixed$(flatness#[point], 3), ", Roughness: ", fixed$(roughness#[point], 3)
    
    selectObject: windowSound, spectrum
    Remove
endfor

appendInfoLine: newline$, "=== CREATING SPECTRAL-DRIVEN PANNING ==="

selectObject: originalSound
leftIntensityTier = Create IntensityTier: "left_pan", 0, duration
rightIntensityTier = Create IntensityTier: "right_pan", 0, duration

timeStep = 1 / panning_update_rate
numGridPoints = round(duration / timeStep) + 1

appendInfoLine: "Creating ", numGridPoints, " panning points..."

currentPhase = 0
previousTime = 0

for i from 1 to numGridPoints
    currentTime = (i - 1) * timeStep
    
    segment = 1
    for p from 1 to numAnalysisPoints - 1
        if currentTime >= analysisTimes#[p] and currentTime <= analysisTimes#[p + 1]
            segment = p
            goto foundSegment
        endif
    endfor
    
    if currentTime < analysisTimes#[1]
        segment = 1
    else
        segment = numAnalysisPoints - 1
    endif
    
    label foundSegment
    
    segmentStart = analysisTimes#[segment]
    segmentEnd = analysisTimes#[segment + 1]
    
    if segmentStart = segmentEnd
        progress = 0
    else
        progress = (currentTime - segmentStart) / (segmentEnd - segmentStart)
    endif
    
    currentFlatness = flatness#[segment] + progress * (flatness#[segment + 1] - flatness#[segment])
    currentRoughness = roughness#[segment] + progress * (roughness#[segment + 1] - roughness#[segment])
    
    panningDepth = base_panning_depth + (currentFlatness * flatness_panning_influence)
    motionSpeed = base_motion_speed + (currentRoughness * roughness_motion_influence)
    
    if i > 1
        timeDelta = currentTime - previousTime
        phaseDelta = 2 * pi * motionSpeed * timeDelta
        currentPhase = currentPhase + phaseDelta
    else
        currentPhase = 0
    endif
    
    leftGain = 50 + (panningDepth * 50) * (1 + sin(currentPhase))
    rightGain = 50 + (panningDepth * 50) * (1 + cos(currentPhase))
    
    leftGain = min(max(leftGain, 10), 100)
    rightGain = min(max(rightGain, 10), 100)
    
    selectObject: leftIntensityTier
    Add point: currentTime, leftGain
    
    selectObject: rightIntensityTier
    Add point: currentTime, rightGain
    
    previousTime = currentTime
    
    if i mod 100 = 0
        appendInfoLine: "Processed ", i, "/", numGridPoints, " panning points"
    endif
endfor

appendInfoLine: newline$, "=== APPLYING SPECTRAL PANNING ==="

selectObject: leftChannel, leftIntensityTier
leftResult = Multiply: "yes"

selectObject: rightChannel, rightIntensityTier
rightResult = Multiply: "yes"

selectObject: leftResult, rightResult
finalSound = Combine to stereo
Rename: "spectral_panning_" + originalName$
Play

appendInfoLine: "Spectral panning applied successfully!"

selectObject: leftChannel, rightChannel, leftResult, rightResult, leftIntensityTier, rightIntensityTier
Remove

selectObject: finalSound
appendInfoLine: newline$, "=== COMPLETE ==="
appendInfoLine: "Final sound: ", selected$("Sound")