# ============================================================
# Praat AudioTools - Climax_Profile_Matcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Climax Profile Matcher - analyzes a Source sound to detect
#   "climax" sections (regions of peak intensity, high pitch,
#   bright spectral tilt, and strong harmonicity), then modifies
#   a Target sound to match those climax characteristics.
#
#   Pipeline:
#   1. Frame-by-frame analysis of Source: intensity, pitch,
#      spectral centroid, harmonicity
#   2. Detect climax regions via percentile thresholds
#   3. Extract climax acoustic profile (avg intensity, pitch,
#      pitch range, centroid, LTAS, formants F1-F3)
#   4. Analyze Target globally for same descriptors
#   5. Compute acoustic deltas and apply transformations:
#      intensity envelope matching, pitch shifting, spectral
#      tilt correction, LTAS-based EQ, harmonicity shaping
#   6. Multi-panel visualization
#
#   Output: one new Sound object named
#   "Target_matched_to_Source_Climax"
#
# Category: AI & Adaptive
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects." + newline$ + "Sound 1 = Source, Sound 2 = Target."
endif

sourceSound = selected("Sound", 1)
targetSound = selected("Sound", 2)
sourceName$ = selected$("Sound", 1)
targetName$ = selected$("Sound", 2)

form Climax Profile Matcher
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Subtle Match (gentle transfer)
        option Full Transfer (strong matching)
        option Spectral Focus (tilt + EQ only)
        option Broadcast Match (loudness + brightness)
    comment === Analysis ===
    positive Frame_step_ms 15
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    positive Max_formant_Hz 5500
    comment === Climax Detection Thresholds ===
    positive Intensity_percentile 87
    positive Pitch_upper_percent 25
    real Brightness_threshold 0.6
    real Harmonicity_threshold 0.5
    positive Min_climax_duration_ms 200
    comment === Transfer Weights (0..1) ===
    real Intensity_transfer 0.8
    real Spectral_tilt_transfer 0.6
    real Eq_transfer 0.5
    real Harmonicity_transfer 0.3
    comment === Processing ===
    positive Processing_chunk_s 30
    positive Crossfade_ms 20
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================================
# Apply Presets
# ============================================================

if preset = 2
    # Subtle Match
    intensity_transfer = 0.4
    spectral_tilt_transfer = 0.3
    eq_transfer = 0.25
    harmonicity_transfer = 0.15
    presetName$ = "SubtleMatch"
elsif preset = 3
    # Full Transfer
    intensity_transfer = 0.9
    spectral_tilt_transfer = 0.8
    eq_transfer = 0.7
    harmonicity_transfer = 0.5
    presetName$ = "FullTransfer"
elsif preset = 4
    # Spectral Focus
    intensity_transfer = 0.2
    spectral_tilt_transfer = 0.9
    eq_transfer = 0.85
    harmonicity_transfer = 0.4
    presetName$ = "SpectralFocus"
elsif preset = 5
    # Broadcast Match
    intensity_transfer = 0.9
    spectral_tilt_transfer = 0.7
    eq_transfer = 0.6
    harmonicity_transfer = 0.3
    presetName$ = "BroadcastMatch"
else
    presetName$ = "Custom"
endif

# Clamp weights
# Clamp weights
if intensity_transfer > 1
    intensity_transfer = 1
elsif intensity_transfer < 0
    intensity_transfer = 0
endif

if spectral_tilt_transfer > 1
    spectral_tilt_transfer = 1
elsif spectral_tilt_transfer < 0
    spectral_tilt_transfer = 0
endif

if eq_transfer > 1
    eq_transfer = 1
elsif eq_transfer < 0
    eq_transfer = 0
endif

if harmonicity_transfer > 1
    harmonicity_transfer = 1
elsif harmonicity_transfer < 0
    harmonicity_transfer = 0
endif

# ============================================================
# Global Parameters
# ============================================================

frameStep = frame_step_ms / 1000
crossfade_s = crossfade_ms / 1000
minClimaxDur = min_climax_duration_ms / 1000

selectObject: sourceSound
srcDuration = Get total duration
srcChannels = Get number of channels
srcSR = Get sampling frequency

selectObject: targetSound
tgtDuration = Get total duration
tgtChannels = Get number of channels
tgtSR = Get sampling frequency

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  Climax Profile Matcher v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", sourceName$, " (", fixed$(srcDuration, 2), " s, ", srcSR, " Hz, ", srcChannels, " ch)"
appendInfoLine: "Target: ", targetName$, " (", fixed$(tgtDuration, 2), " s, ", tgtSR, " Hz, ", tgtChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# Prepare mono copies for analysis
# ============================================================

selectObject: sourceSound
if srcChannels > 1
    srcMono = Convert to mono
else
    srcMono = Copy: "src_mono"
endif

selectObject: targetSound
if tgtChannels > 1
    tgtMono = Convert to mono
else
    tgtMono = Copy: "tgt_mono"
endif

# ============================================================
# STEP 1: ANALYZE SOURCE (frame-by-frame)
# ============================================================
appendInfoLine: "[1/7] Analyzing Source..."

srcNumFrames = floor((srcDuration - frameStep) / frameStep)
if srcNumFrames < 10
    exitScript: "Source too short for analysis."
endif

# --- Create analysis objects ---
selectObject: srcMono
srcIntensityObj = To Intensity: 70, frameStep, "yes"

selectObject: srcMono
srcPitchObj = To Pitch: frameStep, pitch_floor_Hz, pitch_ceiling_Hz

selectObject: srcMono
srcHarmonicityObj = To Harmonicity (cc): frameStep, pitch_floor_Hz, 0.1, 1.0

selectObject: srcMono
srcFormantObj = To Formant (burg): frameStep, 5, max_formant_Hz, 0.025, 50

selectObject: srcMono
srcSpectrogramObj = To Spectrogram: 0.025, 8000, frameStep, 20, "Gaussian"

# --- Extract features per frame ---
srcTime# = zero# (srcNumFrames)
srcIntensity# = zero# (srcNumFrames)
srcPitch# = zero# (srcNumFrames)
srcHNR# = zero# (srcNumFrames)
srcCentroid# = zero# (srcNumFrames)
srcF1# = zero# (srcNumFrames)
srcF2# = zero# (srcNumFrames)
srcF3# = zero# (srcNumFrames)

for i from 1 to srcNumFrames
    t = (i - 0.5) * frameStep
    if t > srcDuration
        t = srcDuration - 0.001
    endif
    srcTime#[i] = t
    
    # Intensity
    selectObject: srcIntensityObj
    val = Get value at time: t, "Cubic"
    srcIntensity#[i] = if val <> undefined then val else 0 fi
    
    # Pitch
    selectObject: srcPitchObj
    p = Get value at time: t, "Hertz", "Linear"
    srcPitch#[i] = if p <> undefined then p else 0 fi
    
    # Harmonicity
    selectObject: srcHarmonicityObj
    h = Get value at time: t, "Cubic"
    srcHNR#[i] = if h <> undefined then h else 0 fi
    
    # Formants
    selectObject: srcFormantObj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    srcF1#[i] = if f1 <> undefined then f1 else 0 fi
    srcF2#[i] = if f2 <> undefined then f2 else 0 fi
    srcF3#[i] = if f3 <> undefined then f3 else 0 fi
    
    # Spectral centroid (from spectrogram)
    selectObject: srcSpectrogramObj
    totalPower = 0
    weightedSum = 0
    freq = 100
    while freq <= 8000
        pw = Get power at: t, freq
        if pw <> undefined and pw > 0
            totalPower = totalPower + pw
            weightedSum = weightedSum + freq * pw
        endif
        freq = freq + 200
    endwhile
    if totalPower > 0
        srcCentroid#[i] = weightedSum / totalPower
    else
        srcCentroid#[i] = 1000
    endif
endfor

appendInfoLine: "  Extracted ", srcNumFrames, " frames"

# ============================================================
# STEP 2: DETECT CLIMAX REGIONS
# ============================================================
appendInfoLine: "[2/7] Detecting climax regions..."

# --- Compute percentiles for thresholding ---

# Sort intensity values to find percentile
# (Use histogram-based approach for efficiency with long files)
procedure findPercentile: .values#, .n, .pct, .result
    # Find min/max
    .min = .values#[1]
    .max = .values#[1]
    for .i from 2 to .n
        if .values#[.i] > 0
            if .values#[.i] < .min or .min = 0
                .min = .values#[.i]
            endif
            if .values#[.i] > .max
                .max = .values#[.i]
            endif
        endif
    endfor
    .range = .max - .min
    if .range < 0.001
        .result = .min
    else
        # Histogram with 200 bins
        .nBins = 200
        for .b from 1 to .nBins
            histBin_'.b' = 0
        endfor
        .nValid = 0
        for .i from 1 to .n
            if .values#[.i] > 0
                .bin = floor((.values#[.i] - .min) / .range * (.nBins - 1)) + 1
                .bin = max(1, min(.nBins, .bin))
                histBin_'.bin' = histBin_'.bin' + 1
                .nValid = .nValid + 1
            endif
        endfor
        
        .target = floor(.nValid * .pct / 100)
        .cumul = 0
        .result = .max
        for .b from 1 to .nBins
            .cumul = .cumul + histBin_'.b'
            if .cumul >= .target
                .result = .min + (.b - 0.5) / .nBins * .range
                .b = .nBins + 1
            endif
        endfor
    endif
endproc

# Intensity threshold
@findPercentile: srcIntensity#, srcNumFrames, intensity_percentile, 0
intThreshold = findPercentile.result
appendInfoLine: "  Intensity threshold (P", intensity_percentile, "): ", fixed$(intThreshold, 1), " dB"

# Pitch threshold (upper N%)
# First find voiced pitch range
pitchMin = 9999
pitchMax = 0
nVoiced = 0
for i from 1 to srcNumFrames
    if srcPitch#[i] > 0
        nVoiced = nVoiced + 1
        if srcPitch#[i] < pitchMin
            pitchMin = srcPitch#[i]
        endif
        if srcPitch#[i] > pitchMax
            pitchMax = srcPitch#[i]
        endif
    endif
endfor
if pitchMax = 0
    pitchMax = 300
    pitchMin = 100
endif
pitchThreshold = pitchMax - (pitchMax - pitchMin) * pitch_upper_percent / 100
appendInfoLine: "  Pitch range: ", fixed$(pitchMin, 0), " - ", fixed$(pitchMax, 0), " Hz, threshold: ", fixed$(pitchThreshold, 0), " Hz"

# Normalize centroid and HNR for thresholding
centroidMin = 99999
centroidMax = 0
hnrMin = 99999
hnrMax = 0
for i from 1 to srcNumFrames
    if srcCentroid#[i] > centroidMax
        centroidMax = srcCentroid#[i]
    endif
    if srcCentroid#[i] < centroidMin
        centroidMin = srcCentroid#[i]
    endif
    if srcHNR#[i] > hnrMax
        hnrMax = srcHNR#[i]
    endif
    if srcHNR#[i] < hnrMin and srcHNR#[i] > -200
        hnrMin = srcHNR#[i]
    endif
endfor
centroidRange = centroidMax - centroidMin + 0.001
hnrRange = hnrMax - hnrMin + 0.001

# --- Scan for climax frames ---
# A frame is "climax-eligible" if it meets multiple criteria
climaxScore# = zero# (srcNumFrames)

for i from 1 to srcNumFrames
    score = 0
    
    # Intensity above percentile
    if srcIntensity#[i] >= intThreshold
        score = score + 1
    endif
    
    # Pitch in upper range (only if voiced)
    if srcPitch#[i] >= pitchThreshold
        score = score + 1
    endif
    
    # Brightness (normalized centroid above threshold)
    normCent = (srcCentroid#[i] - centroidMin) / centroidRange
    if normCent >= brightness_threshold
        score = score + 1
    endif
    
    # Harmonicity above threshold (normalized)
    normHNR = (srcHNR#[i] - hnrMin) / hnrRange
    if normHNR >= harmonicity_threshold
        score = score + 1
    endif
    
    climaxScore#[i] = score
endfor

# --- Segment climax regions (need >= 3 of 4 criteria met) ---
minClimaxFrames = max(1, floor(minClimaxDur / frameStep))
climaxMinScore = 3

numClimax = 0
inClimax = 0
climaxStart = 0

for i from 1 to srcNumFrames
    if climaxScore#[i] >= climaxMinScore
        if inClimax = 0
            climaxStart = i
            inClimax = 1
        endif
    else
        if inClimax = 1
            climaxLen = i - climaxStart
            if climaxLen >= minClimaxFrames
                numClimax = numClimax + 1
                clxStartFrame_'numClimax' = climaxStart
                clxEndFrame_'numClimax' = i - 1
                clxStartTime_'numClimax' = srcTime#[climaxStart]
                clxEndTime_'numClimax' = srcTime#[i - 1]
            endif
            inClimax = 0
        endif
    endif
endfor
# Final segment
if inClimax = 1
    climaxLen = srcNumFrames - climaxStart + 1
    if climaxLen >= minClimaxFrames
        numClimax = numClimax + 1
        clxStartFrame_'numClimax' = climaxStart
        clxEndFrame_'numClimax' = srcNumFrames
        clxStartTime_'numClimax' = srcTime#[climaxStart]
        clxEndTime_'numClimax' = srcTime#[srcNumFrames]
    endif
endif

appendInfoLine: "  Detected ", numClimax, " climax regions:"
for c from 1 to numClimax
    dur_c = clxEndTime_'c' - clxStartTime_'c'
    appendInfoLine: "    Climax ", c, ": ", fixed$(clxStartTime_'c', 3), " - ", fixed$(clxEndTime_'c', 3), " s (", fixed$(dur_c, 3), " s)"
endfor

# Fallback: if no climaxes found, use top 10% intensity frames
if numClimax = 0
    appendInfoLine: "  WARNING: No climaxes detected. Using top-intensity fallback."
    @findPercentile: srcIntensity#, srcNumFrames, 90, 0
    fallbackThreshold = findPercentile.result
    
    inClimax = 0
    for i from 1 to srcNumFrames
        if srcIntensity#[i] >= fallbackThreshold
            if inClimax = 0
                climaxStart = i
                inClimax = 1
            endif
        else
            if inClimax = 1
                numClimax = numClimax + 1
                clxStartFrame_'numClimax' = climaxStart
                clxEndFrame_'numClimax' = i - 1
                clxStartTime_'numClimax' = srcTime#[climaxStart]
                clxEndTime_'numClimax' = srcTime#[i - 1]
                inClimax = 0
            endif
        endif
    endfor
    if inClimax = 1
        numClimax = numClimax + 1
        clxStartFrame_'numClimax' = climaxStart
        clxEndFrame_'numClimax' = srcNumFrames
        clxStartTime_'numClimax' = srcTime#[climaxStart]
        clxEndTime_'numClimax' = srcTime#[srcNumFrames]
    endif
    appendInfoLine: "  Fallback found ", numClimax, " regions"
endif

if numClimax = 0
    appendInfoLine: "  No climax regions found even with fallback — output will be unmodified."
endif

# ============================================================
# STEP 3: COMPUTE CLIMAX ACOUSTIC PROFILE
# ============================================================
appendInfoLine: ""
appendInfoLine: "[3/7] Computing climax profile..."

clxAvgIntensity = 0
clxAvgPitch = 0
clxPitchMin = 9999
clxPitchMax = 0
clxAvgCentroid = 0
clxAvgHNR = 0
clxAvgF1 = 0
clxAvgF2 = 0
clxAvgF3 = 0
clxTotalFrames = 0

for c from 1 to numClimax
    sf = clxStartFrame_'c'
    ef = clxEndFrame_'c'
    for i from sf to ef
        clxTotalFrames = clxTotalFrames + 1
        clxAvgIntensity = clxAvgIntensity + srcIntensity#[i]
        clxAvgCentroid = clxAvgCentroid + srcCentroid#[i]
        clxAvgHNR = clxAvgHNR + srcHNR#[i]
        
        if srcPitch#[i] > 0
            clxAvgPitch = clxAvgPitch + srcPitch#[i]
            if srcPitch#[i] < clxPitchMin
                clxPitchMin = srcPitch#[i]
            endif
            if srcPitch#[i] > clxPitchMax
                clxPitchMax = srcPitch#[i]
            endif
        endif
        
        if srcF1#[i] > 0
            clxAvgF1 = clxAvgF1 + srcF1#[i]
        endif
        if srcF2#[i] > 0
            clxAvgF2 = clxAvgF2 + srcF2#[i]
        endif
        if srcF3#[i] > 0
            clxAvgF3 = clxAvgF3 + srcF3#[i]
        endif
    endfor
endfor

if clxTotalFrames > 0
    clxAvgIntensity = clxAvgIntensity / clxTotalFrames
    clxAvgCentroid = clxAvgCentroid / clxTotalFrames
    clxAvgHNR = clxAvgHNR / clxTotalFrames
    clxAvgF1 = clxAvgF1 / clxTotalFrames
    clxAvgF2 = clxAvgF2 / clxTotalFrames
    clxAvgF3 = clxAvgF3 / clxTotalFrames
endif

# Count voiced climax frames for pitch average
clxVoicedCount = 0
for c from 1 to numClimax
    sf = clxStartFrame_'c'
    ef = clxEndFrame_'c'
    for i from sf to ef
        if srcPitch#[i] > 0
            clxVoicedCount = clxVoicedCount + 1
        endif
    endfor
endfor
if clxVoicedCount > 0
    clxAvgPitch = clxAvgPitch / clxVoicedCount
endif

clxPitchRange = clxPitchMax - clxPitchMin
if clxPitchMin = 9999
    clxPitchMin = 0
    clxPitchRange = 0
endif

# --- Compute Source climax LTAS ---
# Extract and concatenate all climax segments for LTAS
if numClimax > 0
    selectObject: srcMono
    Extract part: clxStartTime_1, clxEndTime_1, "rectangular", 1, "no"
    clxConcat = selected("Sound")
    
    if numClimax > 1
        for c from 2 to numClimax
            selectObject: srcMono
            Extract part: clxStartTime_'c', clxEndTime_'c', "rectangular", 1, "no"
            clxPart = selected("Sound")
            
            selectObject: clxConcat, clxPart
            Concatenate
            temp = selected("Sound")
            removeObject: clxConcat, clxPart
            clxConcat = temp
        endfor
    endif
    
    selectObject: clxConcat
    srcClimaxLTAS = To Ltas: 100
    removeObject: clxConcat
else
    # Fallback: use entire source
    selectObject: srcMono
    srcClimaxLTAS = To Ltas: 100
endif

appendInfoLine: "  Climax Profile:"
appendInfoLine: "    Intensity: ", fixed$(clxAvgIntensity, 1), " dB"
appendInfoLine: "    Pitch: ", fixed$(clxAvgPitch, 1), " Hz (range: ", fixed$(clxPitchMin, 0), "-", fixed$(clxPitchMax, 0), " Hz)"
appendInfoLine: "    Centroid: ", fixed$(clxAvgCentroid, 0), " Hz"
appendInfoLine: "    HNR: ", fixed$(clxAvgHNR, 1), " dB"
appendInfoLine: "    Formants: F1=", fixed$(clxAvgF1, 0), " F2=", fixed$(clxAvgF2, 0), " F3=", fixed$(clxAvgF3, 0), " Hz"

# ============================================================
# STEP 4: ANALYZE TARGET (global descriptors)
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/7] Analyzing Target..."

tgtNumFrames = floor((tgtDuration - frameStep) / frameStep)
if tgtNumFrames < 10
    exitScript: "Target too short for analysis."
endif

# Create analysis objects
selectObject: tgtMono
tgtIntensityObj = To Intensity: 70, frameStep, "yes"

selectObject: tgtMono
tgtPitchObj = To Pitch: frameStep, pitch_floor_Hz, pitch_ceiling_Hz

selectObject: tgtMono
tgtHarmonicityObj = To Harmonicity (cc): frameStep, pitch_floor_Hz, 0.1, 1.0

selectObject: tgtMono
tgtFormantObj = To Formant (burg): frameStep, 5, max_formant_Hz, 0.025, 50

selectObject: tgtMono
tgtSpectrogramObj = To Spectrogram: 0.025, 8000, frameStep, 20, "Gaussian"

# Extract frame-by-frame features
tgtTime# = zero# (tgtNumFrames)
tgtIntensity# = zero# (tgtNumFrames)
tgtPitch# = zero# (tgtNumFrames)
tgtHNR# = zero# (tgtNumFrames)
tgtCentroid# = zero# (tgtNumFrames)

tgtSumInt = 0
tgtSumPitch = 0
tgtSumCentroid = 0
tgtSumHNR = 0
tgtSumF1 = 0
tgtSumF2 = 0
tgtSumF3 = 0
tgtVoicedCount = 0
tgtFormantCount = 0

for i from 1 to tgtNumFrames
    t = (i - 0.5) * frameStep
    if t > tgtDuration
        t = tgtDuration - 0.001
    endif
    tgtTime#[i] = t
    
    selectObject: tgtIntensityObj
    val = Get value at time: t, "Cubic"
    tgtIntensity#[i] = if val <> undefined then val else 0 fi
    tgtSumInt = tgtSumInt + tgtIntensity#[i]
    
    selectObject: tgtPitchObj
    p = Get value at time: t, "Hertz", "Linear"
    tgtPitch#[i] = if p <> undefined then p else 0 fi
    if tgtPitch#[i] > 0
        tgtSumPitch = tgtSumPitch + tgtPitch#[i]
        tgtVoicedCount = tgtVoicedCount + 1
    endif
    
    selectObject: tgtHarmonicityObj
    h = Get value at time: t, "Cubic"
    tgtHNR#[i] = if h <> undefined then h else 0 fi
    tgtSumHNR = tgtSumHNR + tgtHNR#[i]
    
    selectObject: tgtFormantObj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    if f1 <> undefined and f1 > 0
        tgtSumF1 = tgtSumF1 + f1
        tgtSumF2 = tgtSumF2 + (if f2 <> undefined then f2 else 0 fi)
        tgtSumF3 = tgtSumF3 + (if f3 <> undefined then f3 else 0 fi)
        tgtFormantCount = tgtFormantCount + 1
    endif
    
    selectObject: tgtSpectrogramObj
    totalPower = 0
    weightedSum = 0
    freq = 100
    while freq <= 8000
        pw = Get power at: t, freq
        if pw <> undefined and pw > 0
            totalPower = totalPower + pw
            weightedSum = weightedSum + freq * pw
        endif
        freq = freq + 200
    endwhile
    if totalPower > 0
        tgtCentroid#[i] = weightedSum / totalPower
    else
        tgtCentroid#[i] = 1000
    endif
    tgtSumCentroid = tgtSumCentroid + tgtCentroid#[i]
endfor

# Compute target averages
tgtAvgIntensity = tgtSumInt / tgtNumFrames
tgtAvgPitch = if tgtVoicedCount > 0 then tgtSumPitch / tgtVoicedCount else 150 fi
tgtAvgCentroid = tgtSumCentroid / tgtNumFrames
tgtAvgHNR = tgtSumHNR / tgtNumFrames
tgtAvgF1 = if tgtFormantCount > 0 then tgtSumF1 / tgtFormantCount else 500 fi
tgtAvgF2 = if tgtFormantCount > 0 then tgtSumF2 / tgtFormantCount else 1500 fi
tgtAvgF3 = if tgtFormantCount > 0 then tgtSumF3 / tgtFormantCount else 2500 fi

# Target pitch range
tgtPitchMin = 9999
tgtPitchMax = 0
for i from 1 to tgtNumFrames
    if tgtPitch#[i] > 0
        if tgtPitch#[i] < tgtPitchMin
            tgtPitchMin = tgtPitch#[i]
        endif
        if tgtPitch#[i] > tgtPitchMax
            tgtPitchMax = tgtPitch#[i]
        endif
    endif
endfor
if tgtPitchMin = 9999
    tgtPitchMin = 100
    tgtPitchMax = 200
endif
tgtPitchRange = tgtPitchMax - tgtPitchMin

# Target LTAS
selectObject: tgtMono
tgtLTAS = To Ltas: 100

appendInfoLine: "  Target Profile:"
appendInfoLine: "    Intensity: ", fixed$(tgtAvgIntensity, 1), " dB"
appendInfoLine: "    Pitch: ", fixed$(tgtAvgPitch, 1), " Hz (range: ", fixed$(tgtPitchMin, 0), "-", fixed$(tgtPitchMax, 0), " Hz)"
appendInfoLine: "    Centroid: ", fixed$(tgtAvgCentroid, 0), " Hz"
appendInfoLine: "    HNR: ", fixed$(tgtAvgHNR, 1), " dB"
appendInfoLine: "    Formants: F1=", fixed$(tgtAvgF1, 0), " F2=", fixed$(tgtAvgF2, 0), " F3=", fixed$(tgtAvgF3, 0), " Hz"

# ============================================================
# STEP 5: COMPUTE DELTAS
# ============================================================
appendInfoLine: ""
appendInfoLine: "[5/7] Computing acoustic deltas..."

deltaIntensity_dB = clxAvgIntensity - tgtAvgIntensity
deltaPitch_Hz = clxAvgPitch - tgtAvgPitch
deltaPitchRange = clxPitchRange - tgtPitchRange
deltaCentroid_Hz = clxAvgCentroid - tgtAvgCentroid
deltaHNR_dB = clxAvgHNR - tgtAvgHNR
deltaF1 = clxAvgF1 - tgtAvgF1
deltaF2 = clxAvgF2 - tgtAvgF2
deltaF3 = clxAvgF3 - tgtAvgF3

# Pitch shift in semitones
if tgtAvgPitch > 0 and clxAvgPitch > 0
    pitchShift_st = 12 * ln(clxAvgPitch / tgtAvgPitch) / ln(2)
else
    pitchShift_st = 0
endif

# Spectral tilt direction: positive = brighter climax
if deltaCentroid_Hz > 0
    tiltDirection$ = "brighter"
else
    tiltDirection$ = "darker"
endif

# LTAS difference (sample at key bands)
selectObject: srcClimaxLTAS
srcLTAS_250 = Get value at frequency: 250, "Nearest"
srcLTAS_500 = Get value at frequency: 500, "Nearest"
srcLTAS_1k = Get value at frequency: 1000, "Nearest"
srcLTAS_2k = Get value at frequency: 2000, "Nearest"
srcLTAS_4k = Get value at frequency: 4000, "Nearest"
srcLTAS_8k = Get value at frequency: 8000, "Nearest"

selectObject: tgtLTAS
tgtLTAS_250 = Get value at frequency: 250, "Nearest"
tgtLTAS_500 = Get value at frequency: 500, "Nearest"
tgtLTAS_1k = Get value at frequency: 1000, "Nearest"
tgtLTAS_2k = Get value at frequency: 2000, "Nearest"
tgtLTAS_4k = Get value at frequency: 4000, "Nearest"
tgtLTAS_8k = Get value at frequency: 8000, "Nearest"

dLTAS_250 = srcLTAS_250 - tgtLTAS_250
dLTAS_500 = srcLTAS_500 - tgtLTAS_500
dLTAS_1k = srcLTAS_1k - tgtLTAS_1k
dLTAS_2k = srcLTAS_2k - tgtLTAS_2k
dLTAS_4k = srcLTAS_4k - tgtLTAS_4k
dLTAS_8k = srcLTAS_8k - tgtLTAS_8k

appendInfoLine: "  Deltas (Source climax - Target):"
appendInfoLine: "    Intensity: ", fixed$(deltaIntensity_dB, 1), " dB"
appendInfoLine: "    Pitch: ", fixed$(deltaPitch_Hz, 1), " Hz (", fixed$(pitchShift_st, 2), " st)"
appendInfoLine: "    Centroid: ", fixed$(deltaCentroid_Hz, 0), " Hz (", tiltDirection$, ")"
appendInfoLine: "    HNR: ", fixed$(deltaHNR_dB, 1), " dB"
appendInfoLine: "    LTAS diffs: 250=", fixed$(dLTAS_250, 1), " 500=", fixed$(dLTAS_500, 1), " 1k=", fixed$(dLTAS_1k, 1), " 2k=", fixed$(dLTAS_2k, 1), " 4k=", fixed$(dLTAS_4k, 1), " 8k=", fixed$(dLTAS_8k, 1)

# ============================================================
# STEP 6: APPLY TRANSFORMATIONS TO TARGET
# ============================================================
appendInfoLine: ""
appendInfoLine: "[6/7] Applying transformations..."

# Start with a copy of the target
selectObject: targetSound
result = Copy: "working"

# --- 6A: INTENSITY MATCHING ---
if intensity_transfer > 0 and abs(deltaIntensity_dB) > 0.5
    appliedIntDB = deltaIntensity_dB * intensity_transfer
    
    selectObject: result
    Scale intensity: clxAvgIntensity * intensity_transfer + tgtAvgIntensity * (1 - intensity_transfer)
    
    appendInfoLine: "  [A] Intensity: applied ", fixed$(appliedIntDB, 1), " dB shift"
else
    appendInfoLine: "  [A] Intensity: no change needed"
endif

appendInfoLine: "  [B] Pitch: disabled (preserves formant structure)"

# --- 6C: SPECTRAL TILT CORRECTION ---
if spectral_tilt_transfer > 0 and abs(deltaCentroid_Hz) > 50
    # Apply bandpass emphasis to shift spectral center of gravity
    selectObject: result
    
    if deltaCentroid_Hz > 0
        # Need to brighten: boost high band
        emphLow = 500 + (1 - spectral_tilt_transfer) * 1500
        emphHigh = min(12000, 5000 + spectral_tilt_transfer * 7000)
        
        # Create blended version: partial filter application
        selectObject: result
        resultCopy = Copy: "tilt_dry"
        
        selectObject: result
        Filter (pass Hann band): emphLow, emphHigh, 300
        tiltWet = selected("Sound")
        
        # Blend: keep (1-w) dry + w wet
        blendW = spectral_tilt_transfer * 0.5
        selectObject: resultCopy
        Formula: "self * (1 - blendW)"
        selectObject: tiltWet
        Formula: "self * blendW"
        
        # Sum into resultCopy
        selectObject: resultCopy
        tiltDryName$ = selected$("Sound")
        selectObject: tiltWet
        tiltWetName$ = selected$("Sound")
        selectObject: resultCopy
        Formula: "self + Sound_'tiltWetName$'(x)"
        
        removeObject: tiltWet, result
        result = resultCopy
        
        appendInfoLine: "  [C] Spectral tilt: brightened (emphasis ", fixed$(emphLow, 0), "-", fixed$(emphHigh, 0), " Hz)"
    else
        # Need to darken: emphasize low band
        emphLow = max(80, 100 * (1 - spectral_tilt_transfer))
        emphHigh = 3000 - spectral_tilt_transfer * 1500
        
        selectObject: result
        resultCopy = Copy: "tilt_dry"
        
        selectObject: result
        Filter (pass Hann band): emphLow, emphHigh, 300
        tiltWet = selected("Sound")
        
        blendW = spectral_tilt_transfer * 0.5
        selectObject: resultCopy
        Formula: "self * (1 - blendW)"
        selectObject: tiltWet
        Formula: "self * blendW"
        
        selectObject: resultCopy
        tiltDryName$ = selected$("Sound")
        selectObject: tiltWet
        tiltWetName$ = selected$("Sound")
        selectObject: resultCopy
        Formula: "self + Sound_'tiltWetName$'(x)"
        
        removeObject: tiltWet, result
        result = resultCopy
        
        appendInfoLine: "  [C] Spectral tilt: darkened (emphasis ", fixed$(emphLow, 0), "-", fixed$(emphHigh, 0), " Hz)"
    endif
    
    selectObject: result
    Scale peak: 0.99
else
    appendInfoLine: "  [C] Spectral tilt: no change needed"
endif

# --- 6D: LTAS-BASED EQ SHAPING ---
if eq_transfer > 0
    selectObject: result
    
    # Determine which bands need boosting/cutting
    # Apply gentle emphasis via additive filtered layers
    
    # Find the band with the largest positive delta (needs boost)
    maxBand = 0
    maxDelta = 0
    if abs(dLTAS_250) > maxDelta
        maxDelta = abs(dLTAS_250)
        maxBand = 250
    endif
    if abs(dLTAS_1k) > maxDelta
        maxDelta = abs(dLTAS_1k)
        maxBand = 1000
    endif
    if abs(dLTAS_2k) > maxDelta
        maxDelta = abs(dLTAS_2k)
        maxBand = 2000
    endif
    if abs(dLTAS_4k) > maxDelta
        maxDelta = abs(dLTAS_4k)
        maxBand = 4000
    endif
    
    if maxBand > 0 and maxDelta > 2
        # Apply targeted bandpass boost/cut
        selectObject: result
        bandwidth = max(200, maxBand * 0.5)
        lowFreq = max(80, maxBand - bandwidth)
        highFreq = min(12000, maxBand + bandwidth)
        
        resultCopy = Copy: "eq_dry"
        
        selectObject: result
        Filter (pass Hann band): lowFreq, highFreq, bandwidth * 0.3
        eqBand = selected("Sound")
        
        # Scale the filtered band by delta magnitude and weight
        eqGain = eq_transfer * maxDelta / 40
        eqGain = max(-0.4, min(0.4, eqGain))
        
        selectObject: eqBand
        Formula: "self * eqGain"
        
        # Add to dry copy
        selectObject: eqBand
        eqBandName$ = selected$("Sound")
        selectObject: resultCopy
        Formula: "self + Sound_'eqBandName$'(x)"
        
        removeObject: eqBand, result
        result = resultCopy
        selectObject: result
        Scale peak: 0.99
        
        appendInfoLine: "  [D] EQ: boosted ", maxBand, " Hz band by ", fixed$(eqGain * 100, 1), "%"
    else
        appendInfoLine: "  [D] EQ: differences too small, skipped"
    endif
else
    appendInfoLine: "  [D] EQ: disabled"
endif

# --- 6E: HARMONICITY SHAPING ---
if harmonicity_transfer > 0 and deltaHNR_dB > 1
    # Increase harmonicity: mild low-pass to reduce noise, plus gentle saturation
    selectObject: result
    
    # Gentle high-frequency attenuation to reduce noisiness
    cutoff = 8000 + (1 - harmonicity_transfer) * 4000
    
    resultCopy = Copy: "hnr_dry"
    
    selectObject: result
    Filter (pass Hann band): 20, cutoff, 500
    harmFiltered = selected("Sound")
    
    # Mix: (1-w) dry + w filtered
    harmW = harmonicity_transfer * 0.3
    selectObject: resultCopy
    Formula: "self * (1 - harmW)"
    selectObject: harmFiltered
    Formula: "self * harmW"
    
    selectObject: harmFiltered
    hfName$ = selected$("Sound")
    selectObject: resultCopy
    Formula: "self + Sound_'hfName$'(x)"
    
    removeObject: harmFiltered, result
    result = resultCopy
    
    # Mild soft saturation to increase harmonics
    selectObject: result
    satAmount = harmonicity_transfer * 0.3
    Formula: "self * (1 - satAmount) + tanh(self * 3) / 3 * satAmount"
    
    Scale peak: 0.99
    appendInfoLine: "  [E] Harmonicity: +", fixed$(deltaHNR_dB * harmonicity_transfer, 1), " dB (filtered + mild saturation)"
elsif harmonicity_transfer > 0 and deltaHNR_dB < -1
    # Decrease harmonicity: add subtle noise
    selectObject: result
    noiseAmount = harmonicity_transfer * abs(deltaHNR_dB) / 40
    noiseAmount = min(0.15, noiseAmount)
    Formula: "self * (1 - noiseAmount) + randomGauss(0, 0.1) * noiseAmount"
    Scale peak: 0.99
    appendInfoLine: "  [E] Harmonicity: reduced (added ", fixed$(noiseAmount * 100, 1), "% noise)"
else
    appendInfoLine: "  [E] Harmonicity: no change needed"
endif

# --- Final output ---
selectObject: result
Rename: "Target_matched_to_Source_Climax"
Scale peak: 0.99
finalOutput = selected("Sound")
outputDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "  Output: Target_matched_to_Source_Climax (", fixed$(outputDuration, 2), " s)"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[7/7] Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Climax Profile Matcher##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.6, "half", sourceName$ + " → " + targetName$ + " | " + presetName$ + " | " + string$(numClimax) + " climax regions"
    
    # === SOURCE WAVEFORM WITH CLIMAX HIGHLIGHTS ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.7, 1.45
    
    Axes: 0, srcDuration, -1, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDuration, -1, 1
    
    # Highlight climax regions
    for c from 1 to numClimax
        Paint rectangle: "{1.0, 0.88, 0.82}", clxStartTime_'c', clxEndTime_'c', -1, 1
    endfor
    
    selectObject: srcMono
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text top: "no", sourceName$ + " | " + fixed$(srcDuration, 2) + " s | " + string$(numClimax) + " climax(es)"
    
    # === SOURCE TENSION FEATURES ===
    Select outer viewport: 0, 8, 1.6, 2.9
    Select inner viewport: 0.6, 7.7, 1.7, 2.8
    
    Axes: 0, srcDuration, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, srcDuration, 0, 1.1
    
    # Highlight climax regions
    for c from 1 to numClimax
        Paint rectangle: "{1.0, 0.88, 0.82}", clxStartTime_'c', clxEndTime_'c', 0, 1.1
    endfor
    
    # Normalize features for display
    # Intensity
    Colour: "{0.9, 0.5, 0.3}"
    Line width: 1
    for i from 2 to srcNumFrames
        i1 = max(0, min(1, (srcIntensity#[i-1] - 30) / 60))
        i2 = max(0, min(1, (srcIntensity#[i] - 30) / 60))
        Draw line: srcTime#[i-1], i1, srcTime#[i], i2
    endfor
    
    # Pitch (normalized)
    Colour: "{0.3, 0.6, 0.8}"
    for i from 2 to srcNumFrames
        if srcPitch#[i-1] > 0 and srcPitch#[i] > 0
            p1 = max(0, min(1, (srcPitch#[i-1] - pitchMin) / (pitchMax - pitchMin + 1)))
            p2 = max(0, min(1, (srcPitch#[i] - pitchMin) / (pitchMax - pitchMin + 1)))
            Draw line: srcTime#[i-1], p1, srcTime#[i], p2
        endif
    endfor
    
    # HNR (normalized)
    Colour: "{0.5, 0.7, 0.4}"
    for i from 2 to srcNumFrames
        h1 = max(0, min(1, (srcHNR#[i-1] - hnrMin) / hnrRange))
        h2 = max(0, min(1, (srcHNR#[i] - hnrMin) / hnrRange))
        Draw line: srcTime#[i-1], h1, srcTime#[i], h2
    endfor
    
    # Climax score (bold)
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 2
    for i from 2 to srcNumFrames
        Draw line: srcTime#[i-1], climaxScore#[i-1] / 4, srcTime#[i], climaxScore#[i] / 4
    endfor
    Line width: 1
    
    # Threshold line
    Colour: "{0.8, 0.2, 0.2}"
    Dotted line
    Draw line: 0, climaxMinScore / 4, srcDuration, climaxMinScore / 4
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Norm. (0–1)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Source Features & Climax Detection"
    
    # === LTAS COMPARISON ===
    Select outer viewport: 0, 4, 3.0, 4.3
    Select inner viewport: 0.6, 3.7, 3.1, 4.2
    
    selectObject: srcClimaxLTAS
    Colour: "{0.9, 0.4, 0.3}"
    Line width: 1.5
    Draw: 0, 8000, -20, 40, "no", "Curve"
    
    selectObject: tgtLTAS
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 8000, -20, 40, "no", "Curve"
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB/Hz"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "LTAS: Source Climax vs Target"
    
    # === ACOUSTIC PROFILE COMPARISON (bar chart) ===
    Select outer viewport: 4, 8, 3.0, 4.3
    Select inner viewport: 4.4, 7.7, 3.1, 4.2
    
    Axes: 0, 6, 0, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 6, 0, 1.15
    
    barW = 0.35
    
    # Normalize values for display (relative to max)
    maxDisp = max(max(clxAvgIntensity, tgtAvgIntensity), 1)
    maxDispP = max(max(clxAvgPitch, tgtAvgPitch), 1)
    maxDispC = max(max(clxAvgCentroid, tgtAvgCentroid), 1)
    maxDispH = max(max(abs(clxAvgHNR), abs(tgtAvgHNR)), 1)
    maxDispF = max(max(clxAvgF1, tgtAvgF1), 1)
    
    # Intensity pair
    Paint rectangle: "{0.9, 0.5, 0.3}", 0.5 - barW, 0.5, 0, clxAvgIntensity / maxDisp
    Paint rectangle: "{0.3, 0.5, 0.8}", 0.5, 0.5 + barW, 0, tgtAvgIntensity / maxDisp
    
    # Pitch pair
    Paint rectangle: "{0.9, 0.5, 0.3}", 1.5 - barW, 1.5, 0, clxAvgPitch / maxDispP
    Paint rectangle: "{0.3, 0.5, 0.8}", 1.5, 1.5 + barW, 0, tgtAvgPitch / maxDispP
    
    # Centroid pair
    Paint rectangle: "{0.9, 0.5, 0.3}", 2.5 - barW, 2.5, 0, clxAvgCentroid / maxDispC
    Paint rectangle: "{0.3, 0.5, 0.8}", 2.5, 2.5 + barW, 0, tgtAvgCentroid / maxDispC
    
    # HNR pair
    clxHnrNorm = max(0, clxAvgHNR) / maxDispH
    tgtHnrNorm = max(0, tgtAvgHNR) / maxDispH
    Paint rectangle: "{0.9, 0.5, 0.3}", 3.5 - barW, 3.5, 0, clxHnrNorm
    Paint rectangle: "{0.3, 0.5, 0.8}", 3.5, 3.5 + barW, 0, tgtHnrNorm
    
    # F1 pair
    Paint rectangle: "{0.9, 0.5, 0.3}", 4.5 - barW, 4.5, 0, clxAvgF1 / maxDispF
    Paint rectangle: "{0.3, 0.5, 0.8}", 4.5, 4.5 + barW, 0, tgtAvgF1 / maxDispF
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", -0.06, "half", "Int"
    Text: 1.5, "centre", -0.06, "half", "Pitch"
    Text: 2.5, "centre", -0.06, "half", "Cent"
    Text: 3.5, "centre", -0.06, "half", "HNR"
    Text: 4.5, "centre", -0.06, "half", "F1"
    
    Font size: 6
    Colour: "Black"
    Text top: "no", "Acoustic Profiles"
    
    # === ORIGINAL TARGET SPECTROGRAM ===
    Select outer viewport: 0, 4, 4.4, 5.5
    Select inner viewport: 0.6, 3.7, 4.5, 5.4
    
    selectObject: tgtMono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    tgtSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Target (original)"
    
    removeObject: tgtSpec
    
    # === RESULT SPECTROGRAM ===
    Select outer viewport: 4, 8, 4.4, 5.5
    Select inner viewport: 4.4, 7.7, 4.5, 5.4
    
    selectObject: finalOutput
    if tgtChannels > 1
        Extract one channel: 1
        vizOut = selected("Sound")
    else
        vizOut = Copy: "viz_out"
    endif
    
    selectObject: vizOut
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    outSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Target (matched)"
    
    removeObject: outSpec, vizOut
    
    # === STATS PANEL ===
    Select outer viewport: 0, 8, 5.6, 6.7
    Select inner viewport: 0.6, 7.7, 5.7, 6.6
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Transfer Summary##"
    
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    
    Text: 0.02, "left", 0.72, "half", "Intensity: d=" + fixed$(deltaIntensity_dB, 1) + " dB (w=" + fixed$(intensity_transfer, 2) + ") | Pitch shift: disabled"
    Text: 0.02, "left", 0.55, "half", "Centroid: d=" + fixed$(deltaCentroid_Hz, 0) + " Hz (" + tiltDirection$ + ", w=" + fixed$(spectral_tilt_transfer, 2) + ") | HNR: d=" + fixed$(deltaHNR_dB, 1) + " dB (w=" + fixed$(harmonicity_transfer, 2) + ")"
    Text: 0.02, "left", 0.38, "half", "EQ (w=" + fixed$(eq_transfer, 2) + "): 250=" + fixed$(dLTAS_250, 1) + " 1k=" + fixed$(dLTAS_1k, 1) + " 2k=" + fixed$(dLTAS_2k, 1) + " 4k=" + fixed$(dLTAS_4k, 1) + " 8k=" + fixed$(dLTAS_8k, 1) + " dB"
    Text: 0.02, "left", 0.21, "half", "Climax F1=" + fixed$(clxAvgF1, 0) + " F2=" + fixed$(clxAvgF2, 0) + " F3=" + fixed$(clxAvgF3, 0) + " | Target F1=" + fixed$(tgtAvgF1, 0) + " F2=" + fixed$(tgtAvgF2, 0) + " F3=" + fixed$(tgtAvgF3, 0)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 6.75, 7.1
    Axes: 0, 1, 0, 1
    Font size: 6
    
    Colour: "{0.9, 0.5, 0.3}"
    Draw line: 0.02, 0.5, 0.06, 0.5
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Intensity"
    
    Colour: "{0.3, 0.6, 0.8}"
    Draw line: 0.16, 0.5, 0.20, 0.5
    Colour: "Black"
    Text: 0.21, "left", 0.5, "half", "Pitch"
    
    Colour: "{0.5, 0.7, 0.4}"
    Draw line: 0.28, 0.5, 0.32, 0.5
    Colour: "Black"
    Text: 0.33, "left", 0.5, "half", "HNR"
    
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 2
    Draw line: 0.40, 0.5, 0.44, 0.5
    Line width: 1
    Colour: "Black"
    Text: 0.45, "left", 0.5, "half", "Climax score"
    
    Paint rectangle: "{1.0, 0.88, 0.82}", 0.58, 0.61, 0.3, 0.7
    Text: 0.62, "left", 0.5, "half", "Climax region"
    
    Paint rectangle: "{0.9, 0.5, 0.3}", 0.77, 0.80, 0.3, 0.7
    Text: 0.81, "left", 0.5, "half", "Src"
    Paint rectangle: "{0.3, 0.5, 0.8}", 0.86, 0.89, 0.3, 0.7
    Text: 0.90, "left", 0.5, "half", "Tgt"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: srcMono, tgtMono
removeObject: srcIntensityObj, srcPitchObj, srcHarmonicityObj, srcFormantObj, srcSpectrogramObj
removeObject: tgtIntensityObj, tgtPitchObj, tgtHarmonicityObj, tgtFormantObj, tgtSpectrogramObj
removeObject: srcClimaxLTAS, tgtLTAS

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="

if play_output
    Play
endif
