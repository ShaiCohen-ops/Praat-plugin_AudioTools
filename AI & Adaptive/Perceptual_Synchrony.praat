# ============================================================
# Praat AudioTools - Perceptual_Synchrony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perceptual Synchrony over Physical Asynchrony v2.2
#   
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects."
endif

soundA = selected("Sound", 1)
soundB = selected("Sound", 2)
nameA$ = selected$("Sound", 1)
nameB$ = selected$("Sound", 2)

form Perceptual Synchrony Pipeline v2.2
    comment === Analysis ===
    positive Frame_step_ms 10
    positive Min_gesture_duration_ms 80
    positive Max_gesture_duration_ms 2000
    real Gesture_threshold 0.12
    comment === Clustering ===
    optionmenu Clustering_mode 3
        option Local window (temporal proximity)
        option Structural role (normalized position)
        option Both (hybrid)
    positive Perceptual_window_ms 500
    real Min_confidence 0.35
    integer Max_clusters_per_gesture 2
    comment === Effect Intensity ===
    optionmenu Effect_preset 2
        option Subtle
        option Moderate
        option Aggressive
        option Extreme
    comment === Output ===
    boolean Play_result 1
endform

# === APPLY EFFECT PRESET ===
if effect_preset = 1
    # Subtle
    anchorBoostDB = 4.0
    anchorStampDB = 1.5
    outsideTiltDB = 1.0
    anchorWidth = 0.25
    outsideWidth = 0.4
    attackMs = 20
    releaseMs = 80
elsif effect_preset = 2
    # Moderate
    anchorBoostDB = 8.0
    anchorStampDB = 3.0
    outsideTiltDB = 2.0
    anchorWidth = 0.15
    outsideWidth = 0.45
    attackMs = 15
    releaseMs = 100
elsif effect_preset = 3
    # Aggressive
    anchorBoostDB = 12.0
    anchorStampDB = 5.0
    outsideTiltDB = 3.0
    anchorWidth = 0.05
    outsideWidth = 0.5
    attackMs = 10
    releaseMs = 120
else
    # Extreme
    anchorBoostDB = 15.0
    anchorStampDB = 6.0
    outsideTiltDB = 4.0
    anchorWidth = 0.02
    outsideWidth = 0.55
    attackMs = 8
    releaseMs = 150
endif

# === SETUP ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  PERCEPTUAL SYNCHRONY v2.2"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Sound A: ", nameA$
appendInfoLine: "Sound B: ", nameB$

selectObject: soundA
durationA = Get total duration
sampleRateA = Get sampling frequency

selectObject: soundB
durationB = Get total duration
sampleRateB = Get sampling frequency

appendInfoLine: "Duration A: ", fixed$(durationA, 3), " s"
appendInfoLine: "Duration B: ", fixed$(durationB, 3), " s"
appendInfoLine: "Effect preset: ", effect_preset$
appendInfoLine: ""

frameStep = frame_step_ms / 1000
minGestureDur = min_gesture_duration_ms / 1000
maxGestureDur = max_gesture_duration_ms / 1000
perceptualWindow = perceptual_window_ms / 1000

# ============================================================
# FEATURE EXTRACTION
# ============================================================

appendInfoLine: "Extracting features..."

# --- SOUND A ---
selectObject: soundA
intensityA = To Intensity: 75, frameStep, "yes"

selectObject: soundA
spectrogramA = To Spectrogram: 0.025, 5000, frameStep, 20, "Gaussian"

numFramesA = floor(durationA / frameStep)

for i from 1 to numFramesA
    tA = (i - 0.5) * frameStep
    if tA > durationA
        tA = durationA - 0.001
    endif
    
    selectObject: intensityA
    intensityValA[i] = Get value at time: tA, "Cubic"
    if intensityValA[i] = undefined
        intensityValA[i] = 0
    endif
    
    selectObject: spectrogramA
    totalPower = 0
    weightedSum = 0
    lowPower = 0
    highPower = 0
    freq = 100
    while freq <= 5000
        power = Get power at: tA, freq
        if power <> undefined and power > 0
            totalPower = totalPower + power
            weightedSum = weightedSum + freq * power
            if freq <= 1000
                lowPower = lowPower + power
            elsif freq >= 2000
                highPower = highPower + power
            endif
        endif
        freq = freq + 100
    endwhile
    
    if totalPower > 0
        centroidA[i] = weightedSum / totalPower
    else
        centroidA[i] = 1000
    endif
    
    if lowPower > 0
        spectralSlopeA[i] = highPower / lowPower
    else
        spectralSlopeA[i] = 0
    endif
    
    timeA[i] = tA
endfor

# --- SOUND B ---
selectObject: soundB
intensityB = To Intensity: 75, frameStep, "yes"

selectObject: soundB
spectrogramB = To Spectrogram: 0.025, 5000, frameStep, 20, "Gaussian"

numFramesB = floor(durationB / frameStep)

for i from 1 to numFramesB
    tB = (i - 0.5) * frameStep
    if tB > durationB
        tB = durationB - 0.001
    endif
    
    selectObject: intensityB
    intensityValB[i] = Get value at time: tB, "Cubic"
    if intensityValB[i] = undefined
        intensityValB[i] = 0
    endif
    
    selectObject: spectrogramB
    totalPower = 0
    weightedSum = 0
    lowPower = 0
    highPower = 0
    freq = 100
    while freq <= 5000
        power = Get power at: tB, freq
        if power <> undefined and power > 0
            totalPower = totalPower + power
            weightedSum = weightedSum + freq * power
            if freq <= 1000
                lowPower = lowPower + power
            elsif freq >= 2000
                highPower = highPower + power
            endif
        endif
        freq = freq + 100
    endwhile
    
    if totalPower > 0
        centroidB[i] = weightedSum / totalPower
    else
        centroidB[i] = 1000
    endif
    
    if lowPower > 0
        spectralSlopeB[i] = highPower / lowPower
    else
        spectralSlopeB[i] = 0
    endif
    
    timeB[i] = tB
endfor

appendInfoLine: "  A: ", numFramesA, " frames | B: ", numFramesB, " frames"

# ============================================================
# CONSISTENT PERCENTILE NORMALIZATION (30 bins, all features)
# ============================================================

appendInfoLine: "Normalizing (30-bin percentile)..."

numBins = 30
targetPct = 0.95

# --- PROCEDURE: Compute percentile ---
# We'll do this inline for each feature

# === INTENSITY A ===
minValA_int = intensityValA[1]
maxValA_int = intensityValA[1]
for i from 2 to numFramesA
    if intensityValA[i] < minValA_int
        minValA_int = intensityValA[i]
    endif
    if intensityValA[i] > maxValA_int
        maxValA_int = intensityValA[i]
    endif
endfor
rangeA_int = maxValA_int - minValA_int + 0.001

for b from 1 to numBins
    histA_int[b] = 0
endfor
for i from 1 to numFramesA
    binIdx = floor((intensityValA[i] - minValA_int) / rangeA_int * numBins) + 1
    if binIdx > numBins
        binIdx = numBins
    endif
    if binIdx < 1
        binIdx = 1
    endif
    histA_int[binIdx] = histA_int[binIdx] + 1
endfor

cumSum = 0
target95A = numFramesA * targetPct
pct95_binA_int = numBins
for b from 1 to numBins
    cumSum = cumSum + histA_int[b]
    if cumSum >= target95A and pct95_binA_int = numBins
        pct95_binA_int = b
    endif
endfor
pct95A_int = minValA_int + (pct95_binA_int / numBins) * rangeA_int
if pct95A_int - minValA_int < 0.001
    pct95A_int = minValA_int + 0.001
endif

# === CENTROID A ===
minValA_cent = centroidA[1]
maxValA_cent = centroidA[1]
for i from 2 to numFramesA
    if centroidA[i] < minValA_cent
        minValA_cent = centroidA[i]
    endif
    if centroidA[i] > maxValA_cent
        maxValA_cent = centroidA[i]
    endif
endfor
rangeA_cent = maxValA_cent - minValA_cent + 0.001

for b from 1 to numBins
    histA_cent[b] = 0
endfor
for i from 1 to numFramesA
    binIdx = floor((centroidA[i] - minValA_cent) / rangeA_cent * numBins) + 1
    if binIdx > numBins
        binIdx = numBins
    endif
    if binIdx < 1
        binIdx = 1
    endif
    histA_cent[binIdx] = histA_cent[binIdx] + 1
endfor

cumSum = 0
pct95_binA_cent = numBins
for b from 1 to numBins
    cumSum = cumSum + histA_cent[b]
    if cumSum >= target95A and pct95_binA_cent = numBins
        pct95_binA_cent = b
    endif
endfor
pct95A_cent = minValA_cent + (pct95_binA_cent / numBins) * rangeA_cent
if pct95A_cent - minValA_cent < 0.001
    pct95A_cent = minValA_cent + 0.001
endif

# === SLOPE A ===
minValA_slope = spectralSlopeA[1]
maxValA_slope = spectralSlopeA[1]
for i from 2 to numFramesA
    if spectralSlopeA[i] < minValA_slope
        minValA_slope = spectralSlopeA[i]
    endif
    if spectralSlopeA[i] > maxValA_slope
        maxValA_slope = spectralSlopeA[i]
    endif
endfor
rangeA_slope = maxValA_slope - minValA_slope + 0.001

for b from 1 to numBins
    histA_slope[b] = 0
endfor
for i from 1 to numFramesA
    binIdx = floor((spectralSlopeA[i] - minValA_slope) / rangeA_slope * numBins) + 1
    if binIdx > numBins
        binIdx = numBins
    endif
    if binIdx < 1
        binIdx = 1
    endif
    histA_slope[binIdx] = histA_slope[binIdx] + 1
endfor

cumSum = 0
pct95_binA_slope = numBins
for b from 1 to numBins
    cumSum = cumSum + histA_slope[b]
    if cumSum >= target95A and pct95_binA_slope = numBins
        pct95_binA_slope = b
    endif
endfor
pct95A_slope = minValA_slope + (pct95_binA_slope / numBins) * rangeA_slope
if pct95A_slope - minValA_slope < 0.0001
    pct95A_slope = minValA_slope + 0.0001
endif

# === INTENSITY B ===
minValB_int = intensityValB[1]
maxValB_int = intensityValB[1]
for i from 2 to numFramesB
    if intensityValB[i] < minValB_int
        minValB_int = intensityValB[i]
    endif
    if intensityValB[i] > maxValB_int
        maxValB_int = intensityValB[i]
    endif
endfor
rangeB_int = maxValB_int - minValB_int + 0.001

for b from 1 to numBins
    histB_int[b] = 0
endfor
for i from 1 to numFramesB
    binIdx = floor((intensityValB[i] - minValB_int) / rangeB_int * numBins) + 1
    if binIdx > numBins
        binIdx = numBins
    endif
    if binIdx < 1
        binIdx = 1
    endif
    histB_int[binIdx] = histB_int[binIdx] + 1
endfor

cumSum = 0
target95B = numFramesB * targetPct
pct95_binB_int = numBins
for b from 1 to numBins
    cumSum = cumSum + histB_int[b]
    if cumSum >= target95B and pct95_binB_int = numBins
        pct95_binB_int = b
    endif
endfor
pct95B_int = minValB_int + (pct95_binB_int / numBins) * rangeB_int
if pct95B_int - minValB_int < 0.001
    pct95B_int = minValB_int + 0.001
endif

# === CENTROID B ===
minValB_cent = centroidB[1]
maxValB_cent = centroidB[1]
for i from 2 to numFramesB
    if centroidB[i] < minValB_cent
        minValB_cent = centroidB[i]
    endif
    if centroidB[i] > maxValB_cent
        maxValB_cent = centroidB[i]
    endif
endfor
rangeB_cent = maxValB_cent - minValB_cent + 0.001

for b from 1 to numBins
    histB_cent[b] = 0
endfor
for i from 1 to numFramesB
    binIdx = floor((centroidB[i] - minValB_cent) / rangeB_cent * numBins) + 1
    if binIdx > numBins
        binIdx = numBins
    endif
    if binIdx < 1
        binIdx = 1
    endif
    histB_cent[binIdx] = histB_cent[binIdx] + 1
endfor

cumSum = 0
pct95_binB_cent = numBins
for b from 1 to numBins
    cumSum = cumSum + histB_cent[b]
    if cumSum >= target95B and pct95_binB_cent = numBins
        pct95_binB_cent = b
    endif
endfor
pct95B_cent = minValB_cent + (pct95_binB_cent / numBins) * rangeB_cent
if pct95B_cent - minValB_cent < 0.001
    pct95B_cent = minValB_cent + 0.001
endif

# === SLOPE B ===
minValB_slope = spectralSlopeB[1]
maxValB_slope = spectralSlopeB[1]
for i from 2 to numFramesB
    if spectralSlopeB[i] < minValB_slope
        minValB_slope = spectralSlopeB[i]
    endif
    if spectralSlopeB[i] > maxValB_slope
        maxValB_slope = spectralSlopeB[i]
    endif
endfor
rangeB_slope = maxValB_slope - minValB_slope + 0.001

for b from 1 to numBins
    histB_slope[b] = 0
endfor
for i from 1 to numFramesB
    binIdx = floor((spectralSlopeB[i] - minValB_slope) / rangeB_slope * numBins) + 1
    if binIdx > numBins
        binIdx = numBins
    endif
    if binIdx < 1
        binIdx = 1
    endif
    histB_slope[binIdx] = histB_slope[binIdx] + 1
endfor

cumSum = 0
pct95_binB_slope = numBins
for b from 1 to numBins
    cumSum = cumSum + histB_slope[b]
    if cumSum >= target95B and pct95_binB_slope = numBins
        pct95_binB_slope = b
    endif
endfor
pct95B_slope = minValB_slope + (pct95_binB_slope / numBins) * rangeB_slope
if pct95B_slope - minValB_slope < 0.0001
    pct95B_slope = minValB_slope + 0.0001
endif

# === NORMALIZE ALL ===
for i from 1 to numFramesA
    normIntA[i] = (intensityValA[i] - minValA_int) / (pct95A_int - minValA_int)
    if normIntA[i] > 1
        normIntA[i] = 1
    endif
    if normIntA[i] < 0
        normIntA[i] = 0
    endif
    
    normCentA[i] = (centroidA[i] - minValA_cent) / (pct95A_cent - minValA_cent)
    if normCentA[i] > 1
        normCentA[i] = 1
    endif
    if normCentA[i] < 0
        normCentA[i] = 0
    endif
    
    normSlopeA[i] = (spectralSlopeA[i] - minValA_slope) / (pct95A_slope - minValA_slope)
    if normSlopeA[i] > 1
        normSlopeA[i] = 1
    endif
    if normSlopeA[i] < 0
        normSlopeA[i] = 0
    endif
endfor

for i from 1 to numFramesB
    normIntB[i] = (intensityValB[i] - minValB_int) / (pct95B_int - minValB_int)
    if normIntB[i] > 1
        normIntB[i] = 1
    endif
    if normIntB[i] < 0
        normIntB[i] = 0
    endif
    
    normCentB[i] = (centroidB[i] - minValB_cent) / (pct95B_cent - minValB_cent)
    if normCentB[i] > 1
        normCentB[i] = 1
    endif
    if normCentB[i] < 0
        normCentB[i] = 0
    endif
    
    normSlopeB[i] = (spectralSlopeB[i] - minValB_slope) / (pct95B_slope - minValB_slope)
    if normSlopeB[i] > 1
        normSlopeB[i] = 1
    endif
    if normSlopeB[i] < 0
        normSlopeB[i] = 0
    endif
endfor

# Derivatives
for i from 2 to numFramesA
    dIntA[i] = normIntA[i] - normIntA[i-1]
    dCentA[i] = normCentA[i] - normCentA[i-1]
    dSlopeA[i] = normSlopeA[i] - normSlopeA[i-1]
endfor
dIntA[1] = 0
dCentA[1] = 0
dSlopeA[1] = 0

for i from 2 to numFramesB
    dIntB[i] = normIntB[i] - normIntB[i-1]
    dCentB[i] = normCentB[i] - normCentB[i-1]
    dSlopeB[i] = normSlopeB[i] - normSlopeB[i-1]
endfor
dIntB[1] = 0
dCentB[1] = 0
dSlopeB[1] = 0

# ============================================================
# GESTURE DETECTION
# ============================================================

appendInfoLine: "Detecting gestures..."

minGestureFrames = floor(minGestureDur / frameStep)
maxGestureFrames = floor(maxGestureDur / frameStep)

# --- SOUND A ---
numGesturesA = 0
inGesture = 0
gestureStart = 0

for i from 2 to numFramesA
    totalChange = abs(dCentA[i]) + abs(dIntA[i]) + abs(dSlopeA[i])
    
    if inGesture = 0
        if totalChange > gesture_threshold
            inGesture = 1
            gestureStart = i
        endif
    else
        gestureDuration = i - gestureStart
        
        if totalChange < gesture_threshold * 0.5 or gestureDuration >= maxGestureFrames or i = numFramesA
            if gestureDuration >= minGestureFrames
                numGesturesA += 1
                gestureEnd = i
                
                gestureA_start[numGesturesA] = timeA[gestureStart]
                gestureA_end[numGesturesA] = timeA[gestureEnd]
                gestureA_duration[numGesturesA] = gestureA_end[numGesturesA] - gestureA_start[numGesturesA]
                gestureA_normPos[numGesturesA] = (gestureA_start[numGesturesA] + gestureA_end[numGesturesA]) / 2 / durationA
                
                # Shape analysis
                accumCent = 0
                accumInt = 0
                accumSlope = 0
                risingCent = 0
                fallingCent = 0
                risingInt = 0
                fallingInt = 0
                covarFrames = 0
                totalFrames = gestureEnd - gestureStart + 1
                
                maxIntFrame = gestureStart
                maxIntVal = normIntA[gestureStart]
                minIntBefore = normIntA[gestureStart]
                
                for j from gestureStart to gestureEnd
                    accumCent = accumCent + dCentA[j]
                    accumInt = accumInt + dIntA[j]
                    accumSlope = accumSlope + dSlopeA[j]
                    
                    if dCentA[j] > 0.01
                        risingCent += 1
                    elsif dCentA[j] < -0.01
                        fallingCent += 1
                    endif
                    if dIntA[j] > 0.01
                        risingInt += 1
                    elsif dIntA[j] < -0.01
                        fallingInt += 1
                    endif
                    
                    if (dCentA[j] > 0.005 and dSlopeA[j] > 0.005) or (dCentA[j] < -0.005 and dSlopeA[j] < -0.005)
                        covarFrames += 1
                    endif
                    
                    if normIntA[j] > maxIntVal
                        maxIntVal = normIntA[j]
                        maxIntFrame = j
                    endif
                    if j < maxIntFrame and normIntA[j] < minIntBefore
                        minIntBefore = normIntA[j]
                    endif
                endfor
                
                minIntAfter = normIntA[gestureEnd]
                for j from maxIntFrame to gestureEnd
                    if normIntA[j] < minIntAfter
                        minIntAfter = normIntA[j]
                    endif
                endfor
                
                gestureA_centChange[numGesturesA] = accumCent
                gestureA_intChange[numGesturesA] = accumInt
                gestureA_slopeChange[numGesturesA] = accumSlope
                gestureA_centMonotonic[numGesturesA] = max(risingCent, fallingCent) / (totalFrames + 0.001)
                gestureA_intMonotonic[numGesturesA] = max(risingInt, fallingInt) / (totalFrames + 0.001)
                
                if risingCent > fallingCent
                    gestureA_centDirection[numGesturesA] = 1
                else
                    gestureA_centDirection[numGesturesA] = -1
                endif
                if risingInt > fallingInt
                    gestureA_intDirection[numGesturesA] = 1
                else
                    gestureA_intDirection[numGesturesA] = -1
                endif
                
                gestureA_covariation[numGesturesA] = covarFrames / (totalFrames + 0.001)
                
                risePhase = maxIntFrame - gestureStart
                fallPhase = gestureEnd - maxIntFrame
                peakContrast = maxIntVal - max(minIntBefore, minIntAfter)
                
                if risePhase >= 2 and fallPhase >= 2 and peakContrast > 0.15
                    gestureA_peakness[numGesturesA] = peakContrast
                else
                    gestureA_peakness[numGesturesA] = 0
                endif
                
                gestureA_salience[numGesturesA] = sqrt(accumCent^2 + accumInt^2 + accumSlope^2)
            endif
            
            inGesture = 0
        endif
    endif
endfor

# --- SOUND B (same) ---
numGesturesB = 0
inGesture = 0
gestureStart = 0

for i from 2 to numFramesB
    totalChange = abs(dCentB[i]) + abs(dIntB[i]) + abs(dSlopeB[i])
    
    if inGesture = 0
        if totalChange > gesture_threshold
            inGesture = 1
            gestureStart = i
        endif
    else
        gestureDuration = i - gestureStart
        
        if totalChange < gesture_threshold * 0.5 or gestureDuration >= maxGestureFrames or i = numFramesB
            if gestureDuration >= minGestureFrames
                numGesturesB += 1
                gestureEnd = i
                
                gestureB_start[numGesturesB] = timeB[gestureStart]
                gestureB_end[numGesturesB] = timeB[gestureEnd]
                gestureB_duration[numGesturesB] = gestureB_end[numGesturesB] - gestureB_start[numGesturesB]
                gestureB_normPos[numGesturesB] = (gestureB_start[numGesturesB] + gestureB_end[numGesturesB]) / 2 / durationB
                
                accumCent = 0
                accumInt = 0
                accumSlope = 0
                risingCent = 0
                fallingCent = 0
                risingInt = 0
                fallingInt = 0
                covarFrames = 0
                totalFrames = gestureEnd - gestureStart + 1
                
                maxIntFrame = gestureStart
                maxIntVal = normIntB[gestureStart]
                minIntBefore = normIntB[gestureStart]
                
                for j from gestureStart to gestureEnd
                    accumCent = accumCent + dCentB[j]
                    accumInt = accumInt + dIntB[j]
                    accumSlope = accumSlope + dSlopeB[j]
                    
                    if dCentB[j] > 0.01
                        risingCent += 1
                    elsif dCentB[j] < -0.01
                        fallingCent += 1
                    endif
                    if dIntB[j] > 0.01
                        risingInt += 1
                    elsif dIntB[j] < -0.01
                        fallingInt += 1
                    endif
                    
                    if (dCentB[j] > 0.005 and dSlopeB[j] > 0.005) or (dCentB[j] < -0.005 and dSlopeB[j] < -0.005)
                        covarFrames += 1
                    endif
                    
                    if normIntB[j] > maxIntVal
                        maxIntVal = normIntB[j]
                        maxIntFrame = j
                    endif
                    if j < maxIntFrame and normIntB[j] < minIntBefore
                        minIntBefore = normIntB[j]
                    endif
                endfor
                
                minIntAfter = normIntB[gestureEnd]
                for j from maxIntFrame to gestureEnd
                    if normIntB[j] < minIntAfter
                        minIntAfter = normIntB[j]
                    endif
                endfor
                
                gestureB_centChange[numGesturesB] = accumCent
                gestureB_intChange[numGesturesB] = accumInt
                gestureB_slopeChange[numGesturesB] = accumSlope
                gestureB_centMonotonic[numGesturesB] = max(risingCent, fallingCent) / (totalFrames + 0.001)
                gestureB_intMonotonic[numGesturesB] = max(risingInt, fallingInt) / (totalFrames + 0.001)
                
                if risingCent > fallingCent
                    gestureB_centDirection[numGesturesB] = 1
                else
                    gestureB_centDirection[numGesturesB] = -1
                endif
                if risingInt > fallingInt
                    gestureB_intDirection[numGesturesB] = 1
                else
                    gestureB_intDirection[numGesturesB] = -1
                endif
                
                gestureB_covariation[numGesturesB] = covarFrames / (totalFrames + 0.001)
                
                risePhase = maxIntFrame - gestureStart
                fallPhase = gestureEnd - maxIntFrame
                peakContrast = maxIntVal - max(minIntBefore, minIntAfter)
                
                if risePhase >= 2 and fallPhase >= 2 and peakContrast > 0.15
                    gestureB_peakness[numGesturesB] = peakContrast
                else
                    gestureB_peakness[numGesturesB] = 0
                endif
                
                gestureB_salience[numGesturesB] = sqrt(accumCent^2 + accumInt^2 + accumSlope^2)
            endif
            
            inGesture = 0
        endif
    endif
endfor

appendInfoLine: "  A: ", numGesturesA, " gestures | B: ", numGesturesB, " gestures"

# ============================================================
# ANCHOR TAGGING (weighted)
# ============================================================

appendInfoLine: "Tagging gestures..."

# Weights
w_BRIGHT_RISE = 1.0
w_BRIGHT_FALL = 1.0
w_NOISE_BLOOM = 1.2
w_SPECTRAL_DROP = 1.2
w_ACCENT_PEAK = 1.5
w_INTENSITY_SWELL = 0.8
w_SMOOTH_ARC = 0.5

# Thresholds
brightThresh = 0.2
noiseThresh = 0.12
dropThresh = -0.2
swellThresh = 0.15
monotonThresh = 0.65
covarThresh = 0.4

# --- TAG A ---
for g from 1 to numGesturesA
    gestureA_tag_BR[g] = 0
    gestureA_tag_BF[g] = 0
    gestureA_tag_NB[g] = 0
    gestureA_tag_SD[g] = 0
    gestureA_tag_AP[g] = 0
    gestureA_tag_IS[g] = 0
    gestureA_tag_SA[g] = 0
    
    if gestureA_centChange[g] > brightThresh and gestureA_centMonotonic[g] > monotonThresh
        gestureA_tag_BR[g] = 1
    endif
    if gestureA_centChange[g] < -brightThresh and gestureA_centMonotonic[g] > monotonThresh
        gestureA_tag_BF[g] = 1
    endif
    if gestureA_centChange[g] > noiseThresh and gestureA_slopeChange[g] > noiseThresh and gestureA_covariation[g] > covarThresh
        gestureA_tag_NB[g] = 1
    endif
    if gestureA_centChange[g] < dropThresh and gestureA_slopeChange[g] < dropThresh and gestureA_covariation[g] > covarThresh
        gestureA_tag_SD[g] = 1
    endif
    if gestureA_peakness[g] > 0.15
        gestureA_tag_AP[g] = 1
    endif
    if gestureA_intChange[g] > swellThresh and gestureA_intMonotonic[g] > monotonThresh
        gestureA_tag_IS[g] = 1
    endif
    if gestureA_centMonotonic[g] > 0.8
        gestureA_tag_SA[g] = 1
    endif
    
    gestureA_weightedTags[g] = gestureA_tag_BR[g]*w_BRIGHT_RISE + gestureA_tag_BF[g]*w_BRIGHT_FALL + gestureA_tag_NB[g]*w_NOISE_BLOOM + gestureA_tag_SD[g]*w_SPECTRAL_DROP + gestureA_tag_AP[g]*w_ACCENT_PEAK + gestureA_tag_IS[g]*w_INTENSITY_SWELL + gestureA_tag_SA[g]*w_SMOOTH_ARC
    gestureA_tagCount[g] = gestureA_tag_BR[g] + gestureA_tag_BF[g] + gestureA_tag_NB[g] + gestureA_tag_SD[g] + gestureA_tag_AP[g] + gestureA_tag_IS[g] + gestureA_tag_SA[g]
endfor

# --- TAG B ---
for g from 1 to numGesturesB
    gestureB_tag_BR[g] = 0
    gestureB_tag_BF[g] = 0
    gestureB_tag_NB[g] = 0
    gestureB_tag_SD[g] = 0
    gestureB_tag_AP[g] = 0
    gestureB_tag_IS[g] = 0
    gestureB_tag_SA[g] = 0
    
    if gestureB_centChange[g] > brightThresh and gestureB_centMonotonic[g] > monotonThresh
        gestureB_tag_BR[g] = 1
    endif
    if gestureB_centChange[g] < -brightThresh and gestureB_centMonotonic[g] > monotonThresh
        gestureB_tag_BF[g] = 1
    endif
    if gestureB_centChange[g] > noiseThresh and gestureB_slopeChange[g] > noiseThresh and gestureB_covariation[g] > covarThresh
        gestureB_tag_NB[g] = 1
    endif
    if gestureB_centChange[g] < dropThresh and gestureB_slopeChange[g] < dropThresh and gestureB_covariation[g] > covarThresh
        gestureB_tag_SD[g] = 1
    endif
    if gestureB_peakness[g] > 0.15
        gestureB_tag_AP[g] = 1
    endif
    if gestureB_intChange[g] > swellThresh and gestureB_intMonotonic[g] > monotonThresh
        gestureB_tag_IS[g] = 1
    endif
    if gestureB_centMonotonic[g] > 0.8
        gestureB_tag_SA[g] = 1
    endif
    
    gestureB_weightedTags[g] = gestureB_tag_BR[g]*w_BRIGHT_RISE + gestureB_tag_BF[g]*w_BRIGHT_FALL + gestureB_tag_NB[g]*w_NOISE_BLOOM + gestureB_tag_SD[g]*w_SPECTRAL_DROP + gestureB_tag_AP[g]*w_ACCENT_PEAK + gestureB_tag_IS[g]*w_INTENSITY_SWELL + gestureB_tag_SA[g]*w_SMOOTH_ARC
    gestureB_tagCount[g] = gestureB_tag_BR[g] + gestureB_tag_BF[g] + gestureB_tag_NB[g] + gestureB_tag_SD[g] + gestureB_tag_AP[g] + gestureB_tag_IS[g] + gestureB_tag_SA[g]
endfor

# ============================================================
# CLUSTERING (collect candidates)
# ============================================================

appendInfoLine: "Finding clusters..."

globalDuration = max(durationA, durationB)
numCandidates = 0

for g from 1 to numGesturesA
    gestureA_clusterCount[g] = 0
endfor
for g from 1 to numGesturesB
    gestureB_clusterCount[g] = 0
endfor

# === LOCAL WINDOW ===
if clustering_mode = 1 or clustering_mode = 3
    windowStart = 0
    while windowStart < globalDuration
        windowEnd = windowStart + perceptualWindow
        
        for gA from 1 to numGesturesA
            if gestureA_tagCount[gA] > 0
                midA = (gestureA_start[gA] + gestureA_end[gA]) / 2
                
                if midA >= windowStart and midA < windowEnd
                    for gB from 1 to numGesturesB
                        if gestureB_tagCount[gB] > 0
                            midB = (gestureB_start[gB] + gestureB_end[gB]) / 2
                            
                            if midB >= windowStart and midB < windowEnd
                                # Weighted overlap
                                wOverlap = 0
                                if gestureA_tag_BR[gA] = 1 and gestureB_tag_BR[gB] = 1
                                    wOverlap += w_BRIGHT_RISE
                                endif
                                if gestureA_tag_BF[gA] = 1 and gestureB_tag_BF[gB] = 1
                                    wOverlap += w_BRIGHT_FALL
                                endif
                                if gestureA_tag_NB[gA] = 1 and gestureB_tag_NB[gB] = 1
                                    wOverlap += w_NOISE_BLOOM
                                endif
                                if gestureA_tag_SD[gA] = 1 and gestureB_tag_SD[gB] = 1
                                    wOverlap += w_SPECTRAL_DROP
                                endif
                                if gestureA_tag_AP[gA] = 1 and gestureB_tag_AP[gB] = 1
                                    wOverlap += w_ACCENT_PEAK
                                endif
                                if gestureA_tag_IS[gA] = 1 and gestureB_tag_IS[gB] = 1
                                    wOverlap += w_INTENSITY_SWELL
                                endif
                                if gestureA_tag_SA[gA] = 1 and gestureB_tag_SA[gB] = 1
                                    wOverlap += w_SMOOTH_ARC
                                endif
                                
                                if wOverlap > 0
                                    totalW = gestureA_weightedTags[gA] + gestureB_weightedTags[gB]
                                    tagScore = wOverlap / (totalW - wOverlap + 0.001)
                                    
                                    # Shape similarity
                                    shapeScore = 0
                                    if gestureA_centDirection[gA] = gestureB_centDirection[gB]
                                        shapeScore += 0.3
                                    endif
                                    if gestureA_intDirection[gA] = gestureB_intDirection[gB]
                                        shapeScore += 0.3
                                    endif
                                    shapeScore += 0.2 * (1 - abs(gestureA_centMonotonic[gA] - gestureB_centMonotonic[gB]))
                                    shapeScore += 0.2 * (1 - abs(gestureA_covariation[gA] - gestureB_covariation[gB]))
                                    
                                    # Salience
                                    maxSal = max(gestureA_salience[gA], gestureB_salience[gB])
                                    minSal = min(gestureA_salience[gA], gestureB_salience[gB])
                                    if maxSal > 0
                                        salienceScore = minSal / maxSal
                                    else
                                        salienceScore = 1
                                    endif
                                    
                                    # Duration
                                    maxD = max(gestureA_duration[gA], gestureB_duration[gB])
                                    minD = min(gestureA_duration[gA], gestureB_duration[gB])
                                    if maxD > 0
                                        durScore = minD / maxD
                                    else
                                        durScore = 1
                                    endif
                                    
                                    confidence = 0.30*tagScore + 0.30*shapeScore + 0.20*salienceScore + 0.20*durScore
                                    
                                    if confidence >= min_confidence
                                        numCandidates += 1
                                        cand_gA[numCandidates] = gA
                                        cand_gB[numCandidates] = gB
                                        cand_conf[numCandidates] = confidence
                                        cand_mode$[numCandidates] = "LOCAL"
                                        cand_wOverlap[numCandidates] = wOverlap
                                        cand_shapeScore[numCandidates] = shapeScore
                                    endif
                                endif
                            endif
                        endif
                    endfor
                endif
            endif
        endfor
        
        windowStart += perceptualWindow * 0.5
    endwhile
endif

# === STRUCTURAL (normalized position, weighted overlap) ===
if clustering_mode = 2 or clustering_mode = 3
    posTol = 0.15
    
    for gA from 1 to numGesturesA
        if gestureA_tagCount[gA] > 0
            for gB from 1 to numGesturesB
                if gestureB_tagCount[gB] > 0
                    posDiff = abs(gestureA_normPos[gA] - gestureB_normPos[gB])
                    
                    if posDiff < posTol
                        # Weighted overlap (same as local)
                        wOverlap = 0
                        if gestureA_tag_BR[gA] = 1 and gestureB_tag_BR[gB] = 1
                            wOverlap += w_BRIGHT_RISE
                        endif
                        if gestureA_tag_BF[gA] = 1 and gestureB_tag_BF[gB] = 1
                            wOverlap += w_BRIGHT_FALL
                        endif
                        if gestureA_tag_NB[gA] = 1 and gestureB_tag_NB[gB] = 1
                            wOverlap += w_NOISE_BLOOM
                        endif
                        if gestureA_tag_SD[gA] = 1 and gestureB_tag_SD[gB] = 1
                            wOverlap += w_SPECTRAL_DROP
                        endif
                        if gestureA_tag_AP[gA] = 1 and gestureB_tag_AP[gB] = 1
                            wOverlap += w_ACCENT_PEAK
                        endif
                        if gestureA_tag_IS[gA] = 1 and gestureB_tag_IS[gB] = 1
                            wOverlap += w_INTENSITY_SWELL
                        endif
                        
                        if wOverlap > 0.5
                            shapeScore = 0
                            if gestureA_centDirection[gA] = gestureB_centDirection[gB]
                                shapeScore += 0.4
                            endif
                            if gestureA_intDirection[gA] = gestureB_intDirection[gB]
                                shapeScore += 0.4
                            endif
                            shapeScore += 0.2 * (1 - abs(gestureA_centMonotonic[gA] - gestureB_centMonotonic[gB]))
                            
                            maxSal = max(gestureA_salience[gA], gestureB_salience[gB])
                            minSal = min(gestureA_salience[gA], gestureB_salience[gB])
                            if maxSal > 0
                                salienceScore = minSal / maxSal
                            else
                                salienceScore = 1
                            endif
                            
                            posScore = 1 - posDiff / posTol
                            
                            confidence = 0.35*shapeScore + 0.30*salienceScore + 0.35*posScore
                            
                            if confidence >= min_confidence * 0.9
                                numCandidates += 1
                                cand_gA[numCandidates] = gA
                                cand_gB[numCandidates] = gB
                                cand_conf[numCandidates] = confidence
                                cand_mode$[numCandidates] = "STRUCT"
                                cand_wOverlap[numCandidates] = wOverlap
                                cand_shapeScore[numCandidates] = shapeScore
                            endif
                        endif
                    endif
                endif
            endfor
        endif
    endfor
endif

appendInfoLine: "  Candidates: ", numCandidates

# ============================================================
# BEST-MATCH SELECTION (greedy by confidence)
# ============================================================

appendInfoLine: "Selecting best matches..."

for i from 1 to numCandidates
    cand_selected[i] = 0
endfor

numClusters = 0
confCutoff = min_confidence + 0.05

for pass from 1 to numCandidates
    bestIdx = 0
    bestConf = -1
    
    for i from 1 to numCandidates
        if cand_selected[i] = 0 and cand_conf[i] > bestConf
            gA = cand_gA[i]
            gB = cand_gB[i]
            
            if gestureA_clusterCount[gA] < max_clusters_per_gesture and gestureB_clusterCount[gB] < max_clusters_per_gesture
                bestIdx = i
                bestConf = cand_conf[i]
            endif
        endif
    endfor
    
    if bestIdx > 0 and bestConf >= confCutoff
        cand_selected[bestIdx] = 1
        numClusters += 1
        
        gA = cand_gA[bestIdx]
        gB = cand_gB[bestIdx]
        
        cluster_gA[numClusters] = gA
        cluster_gB[numClusters] = gB
        cluster_conf[numClusters] = cand_conf[bestIdx]
        cluster_mode$[numClusters] = cand_mode$[bestIdx]
        cluster_wOverlap[numClusters] = cand_wOverlap[bestIdx]
        cluster_shapeScore[numClusters] = cand_shapeScore[bestIdx]
        
        gestureA_clusterCount[gA] += 1
        gestureB_clusterCount[gB] += 1
        
        # Build tag string
        tags$ = ""
        if gestureA_tag_AP[gA] = 1 and gestureB_tag_AP[gB] = 1
            tags$ = tags$ + "PEAK "
        endif
        if gestureA_tag_BR[gA] = 1 and gestureB_tag_BR[gB] = 1
            tags$ = tags$ + "RISE "
        endif
        if gestureA_tag_BF[gA] = 1 and gestureB_tag_BF[gB] = 1
            tags$ = tags$ + "FALL "
        endif
        if gestureA_tag_NB[gA] = 1 and gestureB_tag_NB[gB] = 1
            tags$ = tags$ + "BLOOM "
        endif
        if gestureA_tag_SD[gA] = 1 and gestureB_tag_SD[gB] = 1
            tags$ = tags$ + "DROP "
        endif
        
        appendInfoLine: "  #", numClusters, " [", cluster_mode$[numClusters], "] A", gA, "<->B", gB, " conf:", fixed$(cluster_conf[numClusters], 2), " | tags: ", tags$, "| shape:", fixed$(cluster_shapeScore[numClusters], 2)
    else
        pass = numCandidates
    endif
endfor

appendInfoLine: ""
appendInfoLine: "  TOTAL CLUSTERS: ", numClusters
appendInfoLine: ""

# ============================================================
# RESYNTHESIS (dramatic perceptual binding)
# ============================================================

appendInfoLine: "Creating output with dramatic binding..."

selectObject: soundA
srA = Get sampling frequency
durA = Get total duration

selectObject: soundB
srB = Get sampling frequency
durB = Get total duration

# Resample if needed
if srA <> srB
    selectObject: soundB
    soundB_rs = Resample: srA, 50
else
    selectObject: soundB
    soundB_rs = Copy: "B_rs"
endif

minDur = min(durA, durB)

selectObject: soundA
Extract part: 0, minDur, "rectangular", 1, "no"
partA = selected("Sound")

selectObject: soundB_rs
Extract part: 0, minDur, "rectangular", 1, "no"
partB = selected("Sound")

removeObject: soundB_rs

# Convert envelope params
attackSec = attackMs / 1000
releaseSec = releaseMs / 1000

# Create anchor mask for A and B (for spatial/timbral processing)
Create Sound from formula: "maskA", 1, 0, minDur, srA, "0"
maskA = selected("Sound")

Create Sound from formula: "maskB", 1, 0, minDur, srA, "0"
maskB = selected("Sound")

# === APPLY CLUSTER EFFECTS ===
if numClusters > 0
    appendInfoLine: "  Applying ", numClusters, " cluster effects..."
    
    boostLin = 10 ^ (anchorBoostDB / 20)
    stampLin = 10 ^ (anchorStampDB / 20)
    
    for c from 1 to numClusters
        gA = cluster_gA[c]
        gB = cluster_gB[c]
        conf = cluster_conf[c]
        
        # Nonlinear confidence (conf^2)
        confScaled = conf * conf
        
        effectBoost = 1 + (boostLin - 1) * confScaled
        effectStamp = 1 + (stampLin - 1) * confScaled
        
        startA = gestureA_start[gA]
        endA = gestureA_end[gA]
        startB = gestureB_start[gB]
        endB = gestureB_end[gB]
        
        if startA < 0
            startA = 0
        endif
        if endA > minDur
            endA = minDur
        endif
        if startB < 0
            startB = 0
        endif
        if endB > minDur
            endB = minDur
        endif
        
        durA_gest = endA - startA
        durB_gest = endB - startB
        
        # === SHAPED ENVELOPE (attack/peak/release) ===
        # Using nested if (Praat doesn't support elsif in formulas)
        if durA_gest > 0
            selectObject: partA
            Formula (part): startA, endA, 1, 1, ~ self * (if (x - startA) < attackSec then (1 + (effectBoost - 1) * ((x - startA) / attackSec)) else (if (endA - x) < releaseSec then (1 + (effectBoost - 1) * ((endA - x) / releaseSec)) else effectBoost fi) fi)
            
            # Mark anchor mask
            selectObject: maskA
            Formula (part): startA, endA, 1, 1, ~ 1
        endif
        
        if durB_gest > 0
            selectObject: partB
            Formula (part): startB, endB, 1, 1, ~ self * (if (x - startB) < attackSec then (1 + (effectBoost - 1) * ((x - startB) / attackSec)) else (if (endB - x) < releaseSec then (1 + (effectBoost - 1) * ((endB - x) / releaseSec)) else effectBoost fi) fi)
            
            selectObject: maskB
            Formula (part): startB, endB, 1, 1, ~ 1
        endif
        
        appendInfoLine: "    Cluster ", c, ": boost=", fixed$(effectBoost, 2), "x (conf^2=", fixed$(confScaled, 3), ")"
    endfor
endif

# === SHARED TIMBRAL STAMP ON ANCHORS (2-4kHz emphasis) ===
appendInfoLine: "  Applying shared timbral stamp on anchors..."

# Create filtered versions for stamp
selectObject: partA
filteredA = Filter (pass Hann band): 2000, 4500, 500
selectObject: filteredA
Scale peak: 0.5
Rename: "filtA_stamp"

selectObject: partB
filteredB = Filter (pass Hann band): 2000, 4500, 500
selectObject: filteredB
Scale peak: 0.5
Rename: "filtB_stamp"

stampGain = 10 ^ (anchorStampDB / 20) - 1

# Mix stamp into anchors only (using mask)
selectObject: partA
Formula: ~ self + object[filteredA] * object[maskA] * stampGain

selectObject: partB
Formula: ~ self + object[filteredB] * object[maskB] * stampGain

removeObject: filteredA, filteredB

# === DIFFERENTIAL TILT OUTSIDE ANCHORS ===
appendInfoLine: "  Applying differential tilt outside anchors..."

tiltGain = 10 ^ (outsideTiltDB / 20)

# A brighter outside anchors, B darker
selectObject: partA
Formula: ~ self * (if object[maskA] < 0.5 then (1 + (tiltGain - 1) * 0.3) else 1 fi)

selectObject: partB
Formula: ~ self * (if object[maskB] < 0.5 then (1 / (1 + (tiltGain - 1) * 0.3)) else 1 fi)

# === NORMALIZE ===
selectObject: partA
Scale peak: 0.75

selectObject: partB
Scale peak: 0.75

# === CREATE STEREO WITH DYNAMIC WIDTH ===
appendInfoLine: "  Creating stereo mix with dynamic width..."

# Create panning envelopes based on masks
# Inside anchors: narrow (anchorWidth)
# Outside anchors: wide (outsideWidth)

Create Sound from formula: "panEnvA", 1, 0, minDur, srA, ~ outsideWidth - (outsideWidth - anchorWidth) * object[maskA]
panEnvA = selected("Sound")

Create Sound from formula: "panEnvB", 1, 0, minDur, srA, ~ outsideWidth - (outsideWidth - anchorWidth) * object[maskB]
panEnvB = selected("Sound")

# Left channel
Create Sound from formula: "LEFT", 1, 0, minDur, srA, "0"
leftCh = selected("Sound")
selectObject: leftCh
Formula: ~ object[partA] * (0.5 + object[panEnvA]) + object[partB] * (0.5 - object[panEnvB])

# Right channel
Create Sound from formula: "RIGHT", 1, 0, minDur, srA, "0"
rightCh = selected("Sound")
selectObject: rightCh
Formula: ~ object[partA] * (0.5 - object[panEnvA]) + object[partB] * (0.5 + object[panEnvB])

# Combine
selectObject: leftCh
plusObject: rightCh
stereoMix = Combine to stereo
Rename: "PerceptualMix_" + nameA$ + "_" + nameB$
Scale peak: 0.95

# Cleanup
removeObject: partA, partB, maskA, maskB, panEnvA, panEnvB, leftCh, rightCh
removeObject: intensityA, spectrogramA, intensityB, spectrogramB

# ============================================================
# VISUALIZATION
# ============================================================

appendInfoLine: "Creating visualization..."

Erase all

# --- TITLE ---
Select outer viewport: 0, 8, 0, 0.5
Font size: 11
Colour: "Black"
Text: 0.5, "centre", 0.5, "half", "##Perceptual Synchrony v2.2## | " + nameA$ + " + " + nameB$ + " | Clusters: " + string$(numClusters) + " | Preset: " + effect_preset$

# --- SOUND A: FEATURES + GESTURES ---
Select outer viewport: 0, 8, 0.6, 1.8
Select inner viewport: 1.0, 7.8, 0.7, 1.7

Axes: 0, durationA, 0, 1

# Background
Colour: "{0.96, 0.97, 1.0}"
Paint rectangle: "{0.96, 0.97, 1.0}", 0, durationA, 0, 1

# Grid
Colour: "{0.9, 0.91, 0.94}"
Line width: 0.5
for t from 1 to floor(durationA)
    Draw line: t, 0, t, 1
endfor

# Draw centroid
Colour: "{0.2, 0.5, 0.8}"
Line width: 1.5
for i from 2 to numFramesA
    Draw line: timeA[i-1], normCentA[i-1], timeA[i], normCentA[i]
endfor

# Draw intensity
Colour: "{0.8, 0.4, 0.2}"
Line width: 1
for i from 2 to numFramesA
    Draw line: timeA[i-1], normIntA[i-1], timeA[i], normIntA[i]
endfor

# Mark gestures with color-coded tags
for g from 1 to numGesturesA
    if gestureA_tagCount[g] > 0
        # Color by most diagnostic tag
        if gestureA_tag_AP[g] = 1
            colour$ = "{0.9, 0.25, 0.25}"
        elsif gestureA_tag_NB[g] = 1
            colour$ = "{0.9, 0.7, 0.15}"
        elsif gestureA_tag_BR[g] = 1
            colour$ = "{0.2, 0.75, 0.3}"
        elsif gestureA_tag_BF[g] = 1
            colour$ = "{0.3, 0.55, 0.8}"
        elsif gestureA_tag_SD[g] = 1
            colour$ = "{0.6, 0.3, 0.7}"
        elsif gestureA_tag_IS[g] = 1
            colour$ = "{0.5, 0.8, 0.5}"
        else
            colour$ = "{0.7, 0.7, 0.7}"
        endif
        
        Paint rectangle: colour$, gestureA_start[g], gestureA_end[g], 0.92, 1.0
        
        # Mark if clustered
        if gestureA_clusterCount[g] > 0
            Colour: "Black"
            Line width: 2
            Draw line: gestureA_start[g], 0.91, gestureA_end[g], 0.91
        endif
    endif
endfor

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 8
Select outer viewport: 0, 1.0, 0.6, 1.8
Axes: 0, 1, 0, 1
Colour: "{0.2, 0.3, 0.5}"
Text: 0.95, "right", 0.6, "half", "Sound A"
Font size: 6
Colour: "{0.5, 0.5, 0.55}"
Text: 0.95, "right", 0.35, "half", string$(numGesturesA) + " gest"

# --- SOUND B: FEATURES + GESTURES ---
Select outer viewport: 0, 8, 1.9, 3.1
Select inner viewport: 1.0, 7.8, 2.0, 3.0

Axes: 0, durationB, 0, 1

Colour: "{0.97, 0.96, 1.0}"
Paint rectangle: "{0.97, 0.96, 1.0}", 0, durationB, 0, 1

Colour: "{0.9, 0.9, 0.93}"
Line width: 0.5
for t from 1 to floor(durationB)
    Draw line: t, 0, t, 1
endfor

Colour: "{0.5, 0.2, 0.7}"
Line width: 1.5
for i from 2 to numFramesB
    Draw line: timeB[i-1], normCentB[i-1], timeB[i], normCentB[i]
endfor

Colour: "{0.8, 0.4, 0.2}"
Line width: 1
for i from 2 to numFramesB
    Draw line: timeB[i-1], normIntB[i-1], timeB[i], normIntB[i]
endfor

for g from 1 to numGesturesB
    if gestureB_tagCount[g] > 0
        if gestureB_tag_AP[g] = 1
            colour$ = "{0.9, 0.25, 0.25}"
        elsif gestureB_tag_NB[g] = 1
            colour$ = "{0.9, 0.7, 0.15}"
        elsif gestureB_tag_BR[g] = 1
            colour$ = "{0.2, 0.75, 0.3}"
        elsif gestureB_tag_BF[g] = 1
            colour$ = "{0.3, 0.55, 0.8}"
        elsif gestureB_tag_SD[g] = 1
            colour$ = "{0.6, 0.3, 0.7}"
        elsif gestureB_tag_IS[g] = 1
            colour$ = "{0.5, 0.8, 0.5}"
        else
            colour$ = "{0.7, 0.7, 0.7}"
        endif
        
        Paint rectangle: colour$, gestureB_start[g], gestureB_end[g], 0.92, 1.0
        
        if gestureB_clusterCount[g] > 0
            Colour: "Black"
            Line width: 2
            Draw line: gestureB_start[g], 0.91, gestureB_end[g], 0.91
        endif
    endif
endfor

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 8
Select outer viewport: 0, 1.0, 1.9, 3.1
Axes: 0, 1, 0, 1
Colour: "{0.4, 0.2, 0.5}"
Text: 0.95, "right", 0.6, "half", "Sound B"
Font size: 6
Colour: "{0.5, 0.5, 0.55}"
Text: 0.95, "right", 0.35, "half", string$(numGesturesB) + " gest"

# --- CLUSTER CONNECTIONS ---
Select outer viewport: 0, 8, 3.2, 4.4
Select inner viewport: 1.0, 7.8, 3.3, 4.3

globalDur = max(durationA, durationB)
Axes: 0, globalDur, 0, 2

Colour: "{0.98, 0.98, 0.99}"
Paint rectangle: "{0.98, 0.98, 0.99}", 0, globalDur, 0, 2

# A timeline at top
Colour: "{0.3, 0.5, 0.8}"
Line width: 2
Draw line: 0, 1.75, durationA, 1.75

# B timeline at bottom
Colour: "{0.5, 0.3, 0.7}"
Draw line: 0, 0.25, durationB, 0.25

# Cluster connections (width by confidence)
for c from 1 to numClusters
    gA = cluster_gA[c]
    gB = cluster_gB[c]
    conf = cluster_conf[c]
    
    midA = (gestureA_start[gA] + gestureA_end[gA]) / 2
    midB = (gestureB_start[gB] + gestureB_end[gB]) / 2
    
    # Line width by confidence
    lineW = 0.5 + conf * 3
    
    # Color by mode
    if cluster_mode$[c] = "LOCAL"
        Colour: "{0.2, 0.7, 0.35}"
    else
        Colour: "{0.85, 0.5, 0.2}"
    endif
    
    Line width: lineW
    Draw line: midA, 1.75, midB, 0.25
    
    # Cluster number
    Font size: 5
    Colour: "{0.3, 0.3, 0.3}"
    Text: (midA + midB) / 2, "centre", 1.0, "half", string$(c)
endfor

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 8
Select outer viewport: 0, 1.0, 3.2, 4.4
Axes: 0, 1, 0, 1
Colour: "{0.3, 0.3, 0.35}"
Text: 0.95, "right", 0.6, "half", "Clusters"
Font size: 6
Colour: "{0.5, 0.5, 0.55}"
Text: 0.95, "right", 0.35, "half", string$(numClusters) + " links"

# --- ANCHOR REGIONS (combined mask) ---
Select outer viewport: 0, 8, 4.5, 5.3
Select inner viewport: 1.0, 7.8, 4.6, 5.2

Axes: 0, minDur, 0, 1

Colour: "{0.98, 0.98, 0.98}"
Paint rectangle: "{0.98, 0.98, 0.98}", 0, minDur, 0, 1

# Draw anchor regions for A (top half)
Colour: "{0.3, 0.6, 0.9}"
for c from 1 to numClusters
    gA = cluster_gA[c]
    startA = gestureA_start[gA]
    endA = gestureA_end[gA]
    if startA < 0
        startA = 0
    endif
    if endA > minDur
        endA = minDur
    endif
    if endA > startA
        Paint rectangle: "{0.3, 0.6, 0.9}", startA, endA, 0.55, 0.95
    endif
endfor

# Draw anchor regions for B (bottom half)
Colour: "{0.6, 0.3, 0.8}"
for c from 1 to numClusters
    gB = cluster_gB[c]
    startB = gestureB_start[gB]
    endB = gestureB_end[gB]
    if startB < 0
        startB = 0
    endif
    if endB > minDur
        endB = minDur
    endif
    if endB > startB
        Paint rectangle: "{0.6, 0.3, 0.8}", startB, endB, 0.05, 0.45
    endif
endfor

# Separator
Colour: "{0.7, 0.7, 0.7}"
Line width: 0.5
Dotted line
Draw line: 0, 0.5, minDur, 0.5
Solid line

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 8
Select outer viewport: 0, 1.0, 4.5, 5.3
Axes: 0, 1, 0, 1
Colour: "{0.3, 0.3, 0.35}"
Text: 0.95, "right", 0.7, "half", "Anchors"
Font size: 5
Colour: "{0.3, 0.6, 0.9}"
Text: 0.95, "right", 0.45, "half", "A regions"
Colour: "{0.6, 0.3, 0.8}"
Text: 0.95, "right", 0.2, "half", "B regions"

# --- STEREO WIDTH ENVELOPE ---
Select outer viewport: 0, 8, 5.4, 6.2
Select inner viewport: 1.0, 7.8, 5.5, 6.1

Axes: 0, minDur, 0, 1

Colour: "{0.98, 0.99, 0.98}"
Paint rectangle: "{0.98, 0.99, 0.98}", 0, minDur, 0, 1

# Draw width envelope
# Outside anchors: outsideWidth, inside anchors: anchorWidth
# Normalized: 0 = anchorWidth, 1 = outsideWidth

Colour: "{0.2, 0.6, 0.4}"
Line width: 2

# Calculate envelope based on clusters
prevWidth = outsideWidth
prevT = 0

for c from 1 to numClusters
    gA = cluster_gA[c]
    startA = gestureA_start[gA]
    endA = gestureA_end[gA]
    if startA < 0
        startA = 0
    endif
    if endA > minDur
        endA = minDur
    endif
    
    # Draw line to start of anchor (wide)
    if startA > prevT
        widthNorm = (outsideWidth - anchorWidth) / (outsideWidth + 0.001)
        Draw line: prevT, widthNorm, startA, widthNorm
    endif
    
    # Draw anchor region (narrow)
    anchorNorm = 0.1
    Draw line: startA, anchorNorm, endA, anchorNorm
    
    prevT = endA
endfor

# Final segment
if prevT < minDur
    widthNorm = (outsideWidth - anchorWidth) / (outsideWidth + 0.001)
    Draw line: prevT, widthNorm, minDur, widthNorm
endif

# Reference lines
Colour: "{0.85, 0.85, 0.85}"
Line width: 0.5
Dotted line
Draw line: 0, 0.5, minDur, 0.5
Solid line

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 8
Select outer viewport: 0, 1.0, 5.4, 6.2
Axes: 0, 1, 0, 1
Colour: "{0.2, 0.5, 0.4}"
Text: 0.95, "right", 0.6, "half", "Stereo"
Font size: 5
Colour: "{0.5, 0.5, 0.55}"
Text: 0.95, "right", 0.35, "half", "width"

# --- LEGEND & PARAMETERS ---
Select outer viewport: 0, 8, 6.3, 7.2
Axes: 0, 1, 0, 1

# Tag legend (left side)
Font size: 6
Colour: "{0.9, 0.25, 0.25}"
Paint rectangle: "{0.9, 0.25, 0.25}", 0.02, 0.05, 0.7, 0.9
Colour: "Black"
Text: 0.06, "left", 0.8, "half", "PEAK"

Colour: "{0.9, 0.7, 0.15}"
Paint rectangle: "{0.9, 0.7, 0.15}", 0.12, 0.15, 0.7, 0.9
Text: 0.16, "left", 0.8, "half", "BLOOM"

Colour: "{0.2, 0.75, 0.3}"
Paint rectangle: "{0.2, 0.75, 0.3}", 0.24, 0.27, 0.7, 0.9
Text: 0.28, "left", 0.8, "half", "RISE"

Colour: "{0.3, 0.55, 0.8}"
Paint rectangle: "{0.3, 0.55, 0.8}", 0.35, 0.38, 0.7, 0.9
Text: 0.39, "left", 0.8, "half", "FALL"

Colour: "{0.6, 0.3, 0.7}"
Paint rectangle: "{0.6, 0.3, 0.7}", 0.46, 0.49, 0.7, 0.9
Text: 0.50, "left", 0.8, "half", "DROP"

# Cluster mode legend
Colour: "{0.2, 0.7, 0.35}"
Text: 0.02, "left", 0.45, "half", "— LOCAL cluster"
Colour: "{0.85, 0.5, 0.2}"
Text: 0.18, "left", 0.45, "half", "— STRUCT cluster"
Colour: "Black"
Line width: 2
Draw line: 0.35, 0.45, 0.38, 0.45
Font size: 5
Text: 0.39, "left", 0.45, "half", "= clustered gesture"

# Parameters (right side)
Font size: 5
Colour: "{0.4, 0.4, 0.45}"
Text: 0.58, "left", 0.85, "half", "Anchor boost: +" + string$(anchorBoostDB) + " dB"
Text: 0.58, "left", 0.65, "half", "Timbral stamp: +" + string$(anchorStampDB) + " dB (2-4kHz)"
Text: 0.58, "left", 0.45, "half", "Outside tilt: ±" + string$(outsideTiltDB) + " dB"
Text: 0.58, "left", 0.25, "half", "Stereo: anchor=" + fixed$(anchorWidth, 2) + " / outside=" + fixed$(outsideWidth, 2)

Text: 0.82, "left", 0.85, "half", "Attack: " + string$(attackMs) + " ms"
Text: 0.82, "left", 0.65, "half", "Release: " + string$(releaseSec * 1000) + " ms"
Text: 0.82, "left", 0.45, "half", "Window: " + string$(perceptual_window_ms) + " ms"
Text: 0.82, "left", 0.25, "half", "Min conf: " + fixed$(min_confidence, 2)

# Time axis at bottom
Select outer viewport: 0, 8, 7.2, 7.5
Select inner viewport: 1.0, 7.8, 7.25, 7.45

Axes: 0, globalDur, 0, 1

Colour: "{0.3, 0.3, 0.35}"
Line width: 1
Draw line: 0, 0.9, globalDur, 0.9

# Ticks
Font size: 6
tickStep = 1
if globalDur > 10
    tickStep = 2
endif
if globalDur > 30
    tickStep = 5
endif

t = 0
while t <= globalDur
    Draw line: t, 0.9, t, 0.5
    Text: t, "centre", 0.15, "half", string$(t)
    t = t + tickStep
endwhile

Font size: 7
Text: globalDur / 2, "centre", -0.5, "half", "Time (s)"

Font size: 10
Line width: 1
Colour: "Black"

appendInfoLine: "  Visualization complete"

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  Gestures: A=", numGesturesA, " B=", numGesturesB
appendInfoLine: "  Clusters: ", numClusters
appendInfoLine: ""
appendInfoLine: "  Effect preset: ", effect_preset$
appendInfoLine: "    Anchor boost: +", anchorBoostDB, " dB"
appendInfoLine: "    Timbral stamp: +", anchorStampDB, " dB (2-4kHz)"
appendInfoLine: "    Outside tilt: ±", outsideTiltDB, " dB"
appendInfoLine: "    Anchor width: ", anchorWidth
appendInfoLine: "    Outside width: ", outsideWidth
appendInfoLine: ""
appendInfoLine: "  Output: PerceptualMix_", nameA$, "_", nameB$
appendInfoLine: ""

selectObject: stereoMix

if play_result
    appendInfoLine: "Playing..."
    Play
endif

appendInfoLine: "Done!"