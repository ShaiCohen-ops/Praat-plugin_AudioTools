# ============================================================
# Praat AudioTools - Spectral-Driven Intensity Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modulation or vibrato-based processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

clearinfo

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

appendInfoLine: "=== SPECTRAL TO INTENSITY MODULATION ==="
originalSound = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalSound
duration = Get total duration
sampling = Get sampling frequency
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"

numAnalysisPoints = 8
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
            re = Get real value in bin: bin
            im = Get imaginary value in bin: bin
            power = re*re + im*im
            power = max(power, 1e-12)
            
            lnSum = lnSum + ln(power)
            linearSum = linearSum + power
            
            if bin > 1 and bin < nBins
                rePrev = Get real value in bin: bin-1
                imPrev = Get imaginary value in bin: bin-1
                powerPrev = rePrev*rePrev + imPrev*imPrev
                
                reNext = Get real value in bin: bin+1
                imNext = Get imaginary value in bin: bin+1
                powerNext = reNext*reNext + imNext*imNext
                
                roughnessSum = roughnessSum + abs(power - (powerPrev + powerNext)/2)
                roughnessBins = roughnessBins + 1
            endif
            
            validBins = validBins + 1
        endif
    endfor
    
    if validBins > 0 and roughnessBins > 0
        flatness#[point] = exp(lnSum / validBins) / (linearSum / validBins)
        roughness#[point] = roughnessSum / roughnessBins
    else
        flatness#[point] = 0.5
        roughness#[point] = 0.02
    endif
    
    appendInfoLine: "Window ", point, " (", fixed$(analysisTimes#[point], 2), "s) - ",
      ... "Flatness: ", fixed$(flatness#[point], 3), ", Roughness: ", fixed$(roughness#[point], 3)
    
    selectObject: windowSound, spectrum
    Remove
endfor

appendInfoLine: newline$, "=== CREATING SPECTRAL-DRIVEN INTENSITY MODULATION ==="

selectObject: originalSound
workingSound = Copy: "working_" + originalName$

intensityTier = Create IntensityTier: "spectral_intensity", 0, duration

timeStep = 0.01
numGridPoints = round(duration / timeStep) + 1

appendInfoLine: "Creating ", numGridPoints, " intensity points..."

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
    
    intensityDepth = 20 + (currentFlatness * 30)
    modulationSpeed = 1.0 + (currentRoughness * 4.0)
    
    if currentFlatness < 0.3 and currentRoughness < 0.02
        intensityDepth = intensityDepth * 0.3
        modulationSpeed = modulationSpeed * 0.7
    endif
    
    if i > 1
        timeDelta = currentTime - previousTime
        phaseDelta = 2 * pi * modulationSpeed * timeDelta
        currentPhase = currentPhase + phaseDelta
    else
        currentPhase = 0
    endif
    
    intensityVariation = intensityDepth * sin(currentPhase)
    currentIntensity = 70 + intensityVariation
    
    currentIntensity = min(max(currentIntensity, 40), 100)
    
    selectObject: intensityTier
    Add point: currentTime, currentIntensity
    
    previousTime = currentTime
    
    if i mod 100 = 0
        appendInfoLine: "Processed ", i, "/", numGridPoints, " intensity points"
    endif
endfor

appendInfoLine: newline$, "=== APPLYING SPECTRAL INTENSITY MODULATION ==="

selectObject: workingSound, intensityTier
finalSound = Multiply: "yes"
Rename: "spectral_intensity_mod_" + originalName$

appendInfoLine: "Spectral intensity modulation applied successfully!"

selectObject: workingSound, intensityTier
Remove

selectObject: finalSound
appendInfoLine: newline$, "=== COMPLETE ==="
appendInfoLine: "Final sound: ", selected$("Sound")

appendInfoLine: newline$, "=== INTENSITY MODULATION PARAMETER RANGES ==="
appendInfoLine: "Intensity depth: 20-50 dB (higher = more volume variation)"
appendInfoLine: "Modulation speed: 1.0-5.0 Hz (higher = faster volume changes)"
appendInfoLine: "Pattern: Sine wave modulation (smooth volume oscillations)"