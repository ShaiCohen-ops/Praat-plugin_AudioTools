# ============================================================
# Praat AudioTools - TimeVaryingSpectralVibrato.praat
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

appendInfoLine: "=== TIME-DEPENDENT SPECTRAL VIBRATO ==="
originalSound = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalSound
duration = Get total duration
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"

selectObject: originalSound
To Pitch: 0, 75, 600
pitchObject = selected("Pitch")

numAnalysisPoints = 8
analysisTimes# = zero#(numAnalysisPoints)
depths# = zero#(numAnalysisPoints)
rates# = zero#(numAnalysisPoints)

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
        flatness = exp(lnSum / validBins) / (linearSum / validBins)
        roughness = roughnessSum / roughnessBins
    else
        flatness = 0.2
        roughness = 0.02
    endif
    
    depths#[point] = 0.1 + (flatness * 0.2)
    roughness_scaled = min(roughness * 50, 1)
    rates#[point] = 4.0 + (roughness_scaled * 1.5)
    
    appendInfoLine: "Window ", point, " (", fixed$(analysisTimes#[point], 2), "s) - ",
      ... "Flatness: ", fixed$(flatness, 3), ", Depth: ", fixed$(depths#[point], 3), ", Rate: ", fixed$(rates#[point], 2)
    
    selectObject: windowSound, spectrum
    Remove
endfor

appendInfoLine: newline$, "=== APPLYING TIME-DEPENDENT VIBRATO ==="

selectObject: originalSound
To Manipulation: 0.01, 75, 600
manipulation = selected("Manipulation")

selectObject: manipulation
Extract pitch tier
originalPitchTier = selected("PitchTier")

vibratoPitchTier = Create PitchTier: "time_varying_vibrato", 0, duration

timeStep = 0.01
numGridPoints = round(duration / timeStep) + 1

appendInfoLine: "Creating ", numGridPoints, " uniform grid points..."

currentPhase = 0
previousTime = 0
previousRate = rates#[1]

for i from 1 to numGridPoints
    currentTime = (i - 1) * timeStep
    
    selectObject: originalPitchTier
    originalFreq = Get value at time: currentTime
    
    if originalFreq > 0
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
        
        currentDepth = depths#[segment] + progress * (depths#[segment + 1] - depths#[segment])
        currentRate = rates#[segment] + progress * (rates#[segment + 1] - rates#[segment])
        
        if i > 1
            timeDelta = currentTime - previousTime
            averageRate = (previousRate + currentRate) / 2
            phaseDelta = 2 * pi * averageRate * timeDelta
            currentPhase = currentPhase + phaseDelta
        else
            currentPhase = 0
        endif
        
        semitoneVariation = currentDepth * sin(currentPhase)
        freqMultiplier = 2^(semitoneVariation / 12)
        newFreq = originalFreq * freqMultiplier
        
        selectObject: vibratoPitchTier
        Add point: currentTime, newFreq
        
        previousTime = currentTime
        previousRate = currentRate
    endif
    
    if i mod 100 = 0
        appendInfoLine: "Processed ", i, "/", numGridPoints, " grid points"
    endif
endfor

selectObject: manipulation
plusObject: vibratoPitchTier
Replace pitch tier

selectObject: manipulation
finalSound = Get resynthesis (overlap-add)
Rename: "time_varying_vibrato_" + originalName$

appendInfoLine: newline$, "Time-dependent vibrato applied successfully!"
appendInfoLine: "Final sound: ", selected$("Sound")

appendInfoLine: newline$, "=== VIBRATO EVOLUTION ==="
for point from 1 to numAnalysisPoints
    appendInfoLine: "Time ", fixed$(analysisTimes#[point], 2), "s - ",
      ... "Depth: ", fixed$(depths#[point], 3), " st, Rate: ", fixed$(rates#[point], 2), " Hz"
endfor
Play

selectObject: pitchObject, manipulation, originalPitchTier, vibratoPitchTier
Remove

selectObject: finalSound
appendInfoLine: newline$, "=== COMPLETE ==="