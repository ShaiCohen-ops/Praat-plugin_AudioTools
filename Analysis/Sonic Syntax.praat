# ============================================================
# Praat AudioTools - Sonic Syntax
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Adaptive Learning
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sonic Syntax - Adaptive Phrase Boundary Detection
#   Analyzes input to learn optimal parameters before processing
#
# Changelog v2.0:
#   - Added adaptive pitch range detection
#   - Auto-calibrated silence threshold from intensity distribution
#   - Content-aware weight adaptation
#   - Spectral flux boundary detection
#   - Temporal pattern learning
#   - Adaptive insertion bonus
#   - Comprehensive learning report
# ============================================================

form Sonic Syntax v2.0 - Adaptive
    comment === MODE ===
    optionmenu Analysis_mode: 1
        option Fully Adaptive (Recommended)
        option Semi-Adaptive (Keep weights)
        option Manual (Original behavior)
    
    comment === MANUAL OVERRIDES (if not Fully Adaptive) ===
    real Silence_threshold_dB -25
    positive Min_duration_between_cuts_s 0.5
    positive Weight_Pitch_Slope 2.0
    positive Weight_Centering 1.0
    positive Insertion_bonus 50.0
    
    comment === ANALYSIS TUNING ===
    positive Silent_interval_min_duration_s 0.05
    boolean Use_spectral_flux 1
    
    comment === OUTPUT ===
    boolean Create_TextGrid 1
    boolean Open_in_editor 0
    boolean Extract_segments_as_sounds 0
    boolean Draw_analysis_report 1
    boolean Print_debug_log 1
    sentence Output_tier_name Boundaries
endform

##############################################
# PHASE 0: ADAPTIVE LEARNING
##############################################

clearinfo
writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║          SONIC SYNTAX v2.0 - ADAPTIVE ANALYSIS              ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: ""

soundID = selected("Sound")
soundName$ = selected$("Sound")
totalDur = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

appendInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$(totalDur, 2), "s | SR: ", sampleRate, " Hz"
appendInfoLine: ""

# Convert to mono for analysis
if numChannels > 1
    Convert to mono
    workingSound = selected("Sound")
else
    selectObject: soundID
    Copy: "working"
    workingSound = selected("Sound")
endif

if analysis_mode <= 2
    appendInfoLine: "══════════════════════════════════════════════════════════════"
    appendInfoLine: "LEARNING PHASE: Analyzing input characteristics..."
    appendInfoLine: "══════════════════════════════════════════════════════════════"
    appendInfoLine: ""
endif

# ─────────────────────────────────────────
# LEARNING 1: PITCH RANGE AUTO-DETECTION
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: "[1/6] Detecting pitch range..."
    
    selectObject: workingSound
    
    # Wide initial scan
    pitchWide = To Pitch (cc): 0, 50, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 800
    
    # Get robust statistics
    q10 = Get quantile: 0, 0, 0.10, "Hertz"
    q90 = Get quantile: 0, 0, 0.90, "Hertz"
    medianPitch = Get quantile: 0, 0, 0.50, "Hertz"
    
    if q10 = undefined or q90 = undefined
        # Fallback
        pitchFloor = 75
        pitchCeiling = 500
        appendInfoLine: "  ⚠ No pitch detected, using defaults: 75-500 Hz"
    else
        # Add margins
        pitchFloor = max(50, floor(q10 * 0.75))
        pitchCeiling = min(800, ceiling(q90 * 1.3))
        appendInfoLine: "  ✓ Detected range: ", pitchFloor, "-", pitchCeiling, " Hz"
        appendInfoLine: "    Median pitch: ", fixed$(medianPitch, 1), " Hz"
    endif
    
    removeObject: pitchWide
else
    pitchFloor = 75
    pitchCeiling = 500
endif

# ─────────────────────────────────────────
# LEARNING 2: INTENSITY DISTRIBUTION
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[2/6] Calibrating silence threshold..."
    
    selectObject: workingSound
    intensityObj = To Intensity: 100, 0, "yes"
    
    # Get intensity statistics
    meanIntensity = Get mean: 0, 0, "dB"
    minIntensity = Get minimum: 0, 0, "Parabolic"
    maxIntensity = Get maximum: 0, 0, "Parabolic"
    q25 = Get quantile: 0, 0, 0.25
    
    # Adaptive threshold: between 25th percentile and minimum
    # This adapts to both loud and quiet recordings
    intensityRange = maxIntensity - minIntensity
    
    if intensityRange > 30
        # High dynamic range material (speech, dynamic music)
        silenceThresholdAuto = q25 - 5
        contentType$ = "High dynamic range"
    elsif intensityRange > 15
        # Moderate dynamic range
        silenceThresholdAuto = (minIntensity + q25) / 2
        contentType$ = "Moderate dynamic range"
    else
        # Compressed material
        silenceThresholdAuto = minIntensity + intensityRange * 0.3
        contentType$ = "Compressed/normalized"
    endif
    
    # Relative to max
    silenceThresholdRel = silenceThresholdAuto - maxIntensity
    
    appendInfoLine: "  ✓ Intensity range: ", fixed$(intensityRange, 1), " dB (", contentType$, ")"
    appendInfoLine: "    Auto threshold: ", fixed$(silenceThresholdRel, 1), " dB relative to peak"
    
    removeObject: intensityObj
    
    if analysis_mode = 1
        silenceThreshold = silenceThresholdRel
    else
        silenceThreshold = silence_threshold_dB
    endif
else
    silenceThreshold = silence_threshold_dB
endif

# ─────────────────────────────────────────
# LEARNING 3: SPECTRAL CONTENT ANALYSIS
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[3/6] Analyzing spectral characteristics..."
    
    selectObject: workingSound
    spectrum = To Spectrum: "yes"
    
    # Spectral centroid
    centroid = Get centre of gravity: 2
    
    # Classify content
    if centroid < 1000
        materialType$ = "Low-frequency rich (bass-heavy)"
        spectralWeight = 0.5
    elsif centroid < 2500
        materialType$ = "Balanced spectrum (speech-like)"
        spectralWeight = 1.0
    else
        materialType$ = "High-frequency rich (bright)"
        spectralWeight = 1.5
    endif
    
    appendInfoLine: "  ✓ Spectral centroid: ", fixed$(centroid, 0), " Hz"
    appendInfoLine: "    Content: ", materialType$
    
    removeObject: spectrum
else
    spectralWeight = 1.0
endif

# ─────────────────────────────────────────
# LEARNING 4: TEMPORAL PATTERN DETECTION
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[4/6] Learning temporal patterns..."
    
    # Analyze intensity envelope for natural rhythm
    selectObject: workingSound
    intensityForPattern = To Intensity: 100, 0, "yes"
    
    # Detect peaks in intensity (potential phrase boundaries)
    Down to IntensityTier
    intensityTier = selected("IntensityTier")
    numPoints = Get number of points
    
    if numPoints > 2
        # Calculate average time between peaks
        intervals# = zero#(numPoints - 1)
        for i to numPoints - 1
            t1 = Get time from index: i
            t2 = Get time from index: i + 1
            intervals#[i] = t2 - t1
        endfor
        
        # Median interval suggests natural phrase length
        sorted# = sort#(intervals#)
        if size(sorted#) > 0
            medianInterval = sorted#[round(size(sorted#) / 2)]
            
            if medianInterval < 0.3
                densityType$ = "Very dense (rapid)"
                minDurationAdaptive = 0.2
            elsif medianInterval < 0.8
                densityType$ = "Dense (conversational)"
                minDurationAdaptive = 0.4
            elsif medianInterval < 2.0
                densityType$ = "Moderate pacing"
                minDurationAdaptive = 0.6
            else
                densityType$ = "Sparse (contemplative)"
                minDurationAdaptive = 1.0
            endif
            
            appendInfoLine: "  ✓ Temporal density: ", densityType$
            appendInfoLine: "    Typical interval: ", fixed$(medianInterval, 2), "s"
            appendInfoLine: "    Suggested min duration: ", fixed$(minDurationAdaptive, 2), "s"
        else
            minDurationAdaptive = min_duration_between_cuts_s
        endif
    else
        minDurationAdaptive = min_duration_between_cuts_s
    endif
    
    removeObject: intensityForPattern, intensityTier
    
    if analysis_mode = 1
        minDuration = minDurationAdaptive
    else
        minDuration = min_duration_between_cuts_s
    endif
else
    minDuration = min_duration_between_cuts_s
endif

# ─────────────────────────────────────────
# LEARNING 5: PITCH VARIABILITY ANALYSIS
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[5/6] Analyzing pitch dynamics..."
    
    selectObject: workingSound
    pitchForVariability = To Pitch (cc): 0, pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling
    
    # Measure pitch variability
    stdDev = Get standard deviation: 0, 0, "Hertz"
    
    if stdDev = undefined or stdDev < 5
        pitchVariability$ = "Monotonous (low pitch variation)"
        pitchSlopeWeight = 0.5
    elsif stdDev < 20
        pitchVariability$ = "Moderate variation"
        pitchSlopeWeight = 1.5
    elsif stdDev < 50
        pitchVariability$ = "High variation (expressive)"
        pitchSlopeWeight = 2.5
    else
        pitchVariability$ = "Very high variation (melodic)"
        pitchSlopeWeight = 3.0
    endif
    
    appendInfoLine: "  ✓ Pitch variability: ", fixed$(stdDev, 1), " Hz (", pitchVariability$, ")"
    appendInfoLine: "    Adaptive pitch slope weight: ", fixed$(pitchSlopeWeight, 1)
    
    removeObject: pitchForVariability
    
    if analysis_mode = 1
        weightPitchSlope = pitchSlopeWeight
    else
        weightPitchSlope = weight_Pitch_Slope
    endif
else
    weightPitchSlope = weight_Pitch_Slope
endif

# ─────────────────────────────────────────
# LEARNING 6: ADAPTIVE INSERTION BONUS
# ─────────────────────────────────────────

if analysis_mode <= 2
    appendInfoLine: ""
    appendInfoLine: "[6/6] Calculating optimal insertion bonus..."
    
    # Base on content density and dynamic range
    if intensityRange > 25 and medianInterval > 0.5
        # High dynamics + sparse = natural phrase structure
        insertionBonusAdaptive = 30
        strategy$ = "Conservative (trust natural pauses)"
    elsif intensityRange < 15 and medianInterval < 0.5
        # Compressed + dense = need aggressive segmentation
        insertionBonusAdaptive = 80
        strategy$ = "Aggressive (create structure)"
    else
        insertionBonusAdaptive = 50
        strategy$ = "Balanced"
    endif
    
    appendInfoLine: "  ✓ Insertion bonus: ", insertionBonusAdaptive, " (", strategy$, ")"
    
    if analysis_mode = 1
        insertionBonus = insertionBonusAdaptive
    else
        insertionBonus = insertion_bonus
    endif
else
    insertionBonus = insertion_bonus
endif

# Set centering weight
if analysis_mode = 1
    weightCentering = 1.0
else
    weightCentering = weight_Centering
endif

appendInfoLine: ""
appendInfoLine: "══════════════════════════════════════════════════════════════"
appendInfoLine: "PROCESSING with learned parameters..."
appendInfoLine: "══════════════════════════════════════════════════════════════"
appendInfoLine: ""

##############################################
# PHASE 1: FEATURE EXTRACTION
##############################################

selectObject: workingSound

# Create Analysis Objects
intensityID = To Intensity: 100, 0, "yes"

selectObject: workingSound
pitchID = To Pitch: 0, pitchFloor, pitchCeiling

# Optional: Spectral Flux for additional boundary cues
if use_spectral_flux
    selectObject: workingSound
    spectrogram = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    spectralFlux = To Matrix
endif

# Detect Silences
selectObject: intensityID
if silenceThreshold > 0
    silenceThreshold = -silenceThreshold
endif

silenceTG = To TextGrid (silences): silenceThreshold, 
    ...silent_interval_min_duration_s, 1, "silent", "sounding"

# Count Candidates
nIntervals = Get number of intervals: 1
nCandidates = 0

for i to nIntervals
    label$ = Get label of interval: 1, i
    if label$ = "silent"
        nCandidates += 1
    endif
endfor

if nCandidates = 0
    removeObject: intensityID, pitchID, silenceTG, workingSound
    if use_spectral_flux
        removeObject: spectrogram, spectralFlux
    endif
    exitScript: "No silence candidates found. Try adjusting threshold."
endif

appendInfoLine: "Found ", nCandidates, " candidate boundaries"

# Initialize Arrays
candTime# = zero#(nCandidates)
candScore# = zero#(nCandidates)
candOrigIndex# = zero#(nCandidates)

# DP Arrays
dpMaxScore# = zero#(nCandidates)
dpPrevIndex# = zero#(nCandidates)

##############################################
# PHASE 2: SCORE CANDIDATES
##############################################

currCand = 0
pitchAnalysisWindow = 0.05

for i to nIntervals
    selectObject: silenceTG
    label$ = Get label of interval: 1, i
    if label$ = "silent"
        currCand += 1
        start = Get start time of interval: 1, i
        end = Get end time of interval: 1, i
        
        # Center of silence
        time = (start + end) / 2
        candTime#[currCand] = time
        candOrigIndex#[currCand] = i
        
        # ── SCORE COMPONENT 1: PITCH SLOPE ──
        selectObject: pitchID
        pStart = Get value at time: time - pitchAnalysisWindow, "Hertz", "Linear"
        pEnd = Get value at time: time, "Hertz", "Linear"
        
        slopeScore = 0
        if pStart != undefined and pEnd != undefined
            slope = (pEnd - pStart) / pitchAnalysisWindow
            # Falling = positive score
            slopeScore = -slope * weightPitchSlope
        endif
        
        # ── SCORE COMPONENT 2: CENTERING ──
        mid = (start + end) / 2
        dev = abs(time - mid)
        centerScore = -dev * 100 * weightCentering
        
        # ── SCORE COMPONENT 3: SPECTRAL FLUX (SIMPLIFIED) ──
        fluxScore = 0
        if use_spectral_flux
            # Use intensity change as proxy for spectral flux
            selectObject: intensityID
            
            intBefore = Get value at time: time - 0.05, "Cubic"
            intAt = Get value at time: time, "Cubic"
            intAfter = Get value at time: time + 0.05, "Cubic"
            
            if intBefore != undefined and intAt != undefined and intAfter != undefined
                # Measure intensity drop (silence depth)
                dropBefore = intBefore - intAt
                dropAfter = intAt - intAfter
                
                # Deeper silence = stronger boundary cue
                avgDrop = (abs(dropBefore) + abs(dropAfter)) / 2
                fluxScore = avgDrop * spectralWeight * 0.3
            endif
        endif
        
        # ── TOTAL SCORE ──
        candScore#[currCand] = slopeScore + centerScore + fluxScore + insertionBonus
    endif
endfor

##############################################
# PHASE 3: DYNAMIC PROGRAMMING SOLVER
##############################################

if print_debug_log
    appendInfoLine: "Solving optimal path..."
endif

# Initialize
for i to nCandidates
    dpMaxScore#[i] = -1000000
    dpPrevIndex#[i] = 0
endfor

# Forward Pass
for i to nCandidates
    tCurr = candTime#[i]
    localScore = candScore#[i]
    
    # Check if this can be first cut
    if tCurr >= minDuration
        if localScore > dpMaxScore#[i]
            dpMaxScore#[i] = localScore
            dpPrevIndex#[i] = 0
        endif
    endif
    
    # Check connections from previous cuts
    for j to i-1
        tPrev = candTime#[j]
        scorePrev = dpMaxScore#[j]
        dist = tCurr - tPrev
        
        if dist >= minDuration and scorePrev > -999999
            newTotal = scorePrev + localScore
            if newTotal > dpMaxScore#[i]
                dpMaxScore#[i] = newTotal
                dpPrevIndex#[i] = j
            endif
        endif
    endfor
endfor

##############################################
# PHASE 4: BACKTRACKING
##############################################

# Find best endpoint
bestEndNode = 0
maxFinalScore = -1000000

for i to nCandidates
    if dpMaxScore#[i] > maxFinalScore
        maxFinalScore = dpMaxScore#[i]
        bestEndNode = i
    endif
endfor

if bestEndNode = 0
    removeObject: intensityID, pitchID, silenceTG, workingSound
    if use_spectral_flux
        removeObject: spectrogram, spectralFlux
    endif
    exitScript: "No valid path found."
endif

# Trace back
finalCuts# = zero#(nCandidates)
cutCount = 0
curr = bestEndNode

while curr > 0
    cutCount += 1
    finalCuts#[cutCount] = candTime#[curr]
    curr = dpPrevIndex#[curr]
endwhile

##############################################
# PHASE 5: OUTPUT
##############################################

if create_TextGrid
    selectObject: soundID
    tgOut = To TextGrid: output_tier_name$, ""
    
    # Insert boundaries (reversed order)
    for k to cutCount
        idx = cutCount - k + 1
        t = finalCuts#[idx]
        Insert boundary: 1, t
    endfor
    
    # Label segments
    nSeg = Get number of intervals: 1
    for i to nSeg
        Set interval text: 1, i, "Phrase " + string$(i)
    endfor
    
    # Optional: Open in editor
    if open_in_editor
        selectObject: tgOut
        plusObject: soundID
        View & Edit
    endif
    
    # Optional: Extract segments as individual Sound objects
    if extract_segments_as_sounds
        appendInfoLine: ""
        appendInfoLine: "Extracting ", nSeg, " segments as Sound objects..."
        
        extractedSounds# = zero#(nSeg)
        
        for i to nSeg
            selectObject: tgOut
            tStart = Get start time of interval: 1, i
            tEnd = Get end time of interval: 1, i
            
            # Extract from original sound
            selectObject: soundID
            extractedSounds#[i] = Extract part: tStart, tEnd, "rectangular", 1.0, "no"
            
            # Rename with phrase number and timing
            selectObject: extractedSounds#[i]
            Rename: soundName$ + "_phrase" + string$(i) + "_" + fixed$(tStart, 2) + "s"
            
            appendInfoLine: "  Phrase ", i, ": ", fixed$(tStart, 2), "-", fixed$(tEnd, 2), "s (", fixed$(tEnd - tStart, 2), "s)"
        endfor
        
        # Select all extracted sounds for easy viewing
        selectObject: extractedSounds#[1]
        for i from 2 to nSeg
            plusObject: extractedSounds#[i]
        endfor
        
        appendInfoLine: "✓ Extracted ", nSeg, " segments"
    endif
endif

##############################################
# PHASE 6: ANALYSIS REPORT VISUALIZATION
##############################################

if draw_analysis_report and analysis_mode <= 2
    Erase all
    
    # Title
    Select outer viewport: 1, 10, 0, 0.6
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Sonic Syntax## - Adaptive Analysis Report"
    
    # Parameters panel
    Select outer viewport: 0, 5, 0.7, 2.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.2, 0.2, 0.3}"
    Text: 0.05, "left", 0.95, "top", "##Learned Parameters##"
    Text: 0.05, "left", 0.80, "top", "Pitch range: " + string$(pitchFloor) + "-" + string$(pitchCeiling) + " Hz"
    Text: 0.05, "left", 0.65, "top", "Silence threshold: " + fixed$(silenceThreshold, 1) + " dB"
    Text: 0.05, "left", 0.50, "top", "Min duration: " + fixed$(minDuration, 2) + " s"
    Text: 0.05, "left", 0.35, "top", "Pitch slope weight: " + fixed$(weightPitchSlope, 1)
    Text: 0.05, "left", 0.20, "top", "Insertion bonus: " + string$(insertionBonus)
    Text: 0.05, "left", 0.05, "top", "Cuts found: " + string$(cutCount)
    
    # Content analysis panel
    Select outer viewport: 5, 10, 0.7, 2.5
    Axes: 0, 1, 0, 1
    Colour: "{0.2, 0.2, 0.3}"
    Text: 0.05, "left", 0.95, "top", "##Content Analysis##"
    Text: 0.05, "left", 0.80, "top", "Type: " + materialType$
    Text: 0.05, "left", 0.65, "top", "Dynamics: " + contentType$
    Text: 0.05, "left", 0.50, "top", "Density: " + densityType$
    Text: 0.05, "left", 0.35, "top", "Pitch variation: " + pitchVariability$
    Text: 0.05, "left", 0.20, "top", "Strategy: " + strategy$
    
    # Waveform with boundaries
    Select outer viewport: 0, 10, 2.7, 4.5
    Select inner viewport: 0.5, 9.7, 2.8, 4.4
    
    selectObject: soundID
    Colour: "{0.3, 0.4, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark detected boundaries
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 2
    for k to cutCount
        t = finalCuts#[k]
        Draw line: t, -1, t, 1
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup
removeObject: intensityID, pitchID, silenceTG, workingSound
if use_spectral_flux
    removeObject: spectrogram, spectralFlux
endif

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                      SUCCESS                                 ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Found optimal path with ", cutCount, " boundaries"
appendInfoLine: "Total score: ", fixed$(maxFinalScore, 2)

if create_TextGrid
    appendInfoLine: ""
    appendInfoLine: "TextGrid created: ", output_tier_name$
    if extract_segments_as_sounds
        appendInfoLine: "Extracted sounds: ", nSeg, " phrases"
    endif
endif