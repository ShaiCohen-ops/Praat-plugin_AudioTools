# ============================================================
# Praat AudioTools - Voice_Quality_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025)
# License: MIT License
#
# Description:
#   Sonification of voice quality metrics (jitter/shimmer) through
#   time-varying spectral filtering. Maps temporal instabilities
#   to dynamic filter bank parameters for creative timbral control.
#
# Method:
#   1. Analyzes jitter (F0 perturbation) and shimmer (amplitude perturbation)
#   2. Normalizes metrics across analysis windows
#   3. Maps normalized values to bandpass filter frequencies:
#      - Jitter → F1-band center (280-900 Hz)
#      - Shimmer → F2-band center (900-2500 Hz)
#   4. Applies time-varying dual-band filtering
#
# Note: This is data-to-sound mapping (sonification), not formant synthesis.
#       For true formant manipulation, see Creative_Formant_Manipulations.praat
# ============================================================

form Jitter-Shimmer Formant Mapper
    optionmenu Preset: 1
        option Custom
        option Subtle Variation
        option Moderate Effect
        option Extreme Mapping
        option Reverse Mapping
    comment === Analysis ===
    integer Num_windows 8
    positive Window_size_(s) 0.2
    comment === Formant Mapping ===
    real Jitter_to_F1_scale 0.15
    real Shimmer_to_F2_scale 0.12
    comment (higher = more effect from jitter/shimmer)
    comment === Formant Ranges ===
    positive F1_low_(Hz) 280
    positive F1_high_(Hz) 900
    positive F2_low_(Hz) 900
    positive F2_high_(Hz) 2500
    comment === Output ===
    boolean Draw_analysis 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Subtle Variation
    num_windows = 6
    window_size = 0.25
    jitter_to_F1_scale = 0.08
    shimmer_to_F2_scale = 0.06
elsif preset = 3
    # Moderate Effect
    num_windows = 8
    window_size = 0.2
    jitter_to_F1_scale = 0.15
    shimmer_to_F2_scale = 0.12
elsif preset = 4
    # Extreme Mapping
    num_windows = 12
    window_size = 0.15
    jitter_to_F1_scale = 0.3
    shimmer_to_F2_scale = 0.25
elsif preset = 5
    # Reverse Mapping (shimmer->F1, jitter->F2)
    num_windows = 8
    window_size = 0.2
    jitter_to_F1_scale = -0.15
    shimmer_to_F2_scale = -0.12
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency

if duration < window_size * 2
    exitScript: "Sound is too short for analysis (min " + fixed$(window_size * 2, 2) + "s)."
endif

# Adjust num_windows if sound is short
maxWindows = floor(duration / (window_size * 0.5))
if num_windows > maxWindows
    num_windows = max(2, maxWindows)
endif

writeInfoLine: "=== Jitter-Shimmer Formant Mapper ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Windows: ", num_windows
appendInfoLine: ""

# ============================================================
# ANALYZE JITTER/SHIMMER IN WINDOWS
# ============================================================
# Arrays for analysis results
for w to num_windows
    analysisTime[w] = 0
    jitterVal[w] = 0
    shimmerVal[w] = 0
endfor

appendInfoLine: "Analyzing voice quality..."

for window from 1 to num_windows
    # Calculate window position
    if num_windows > 1
        windowStart = (window - 1) * (duration - window_size) / (num_windows - 1)
    else
        windowStart = (duration - window_size) / 2
    endif
    
    # Clamp to valid range
    windowStart = max(0.01, windowStart)
    windowStart = min(duration - window_size - 0.01, windowStart)
    windowEnd = windowStart + window_size
    
    analysisTime[window] = windowStart + window_size / 2
    
    # Extract window
    selectObject: originalID
    windowSound = Extract part: windowStart, windowEnd, "Hamming", 1, "no"
    
    # Create pitch object
    selectObject: windowSound
    pitchObj = To Pitch (cc): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
    
    # Create point process
    selectObject: windowSound
    plusObject: pitchObj
    pointProc = To PointProcess (cc)
    
    # Check if we have enough pulses
    selectObject: pointProc
    numPulses = Get number of points
    
    if numPulses >= 3
        # Get voice report
        selectObject: windowSound
        plusObject: pitchObj
        plusObject: pointProc
        voiceReport$ = Voice report: 0, 0, 75, 600, 1.3, 1.6, 0.03, 0.45
        
        # Parse jitter (local) - look for the line and extract number
        jitterPos = index(voiceReport$, "Jitter (local):")
        if jitterPos > 0
            afterJitter$ = mid$(voiceReport$, jitterPos + 16, 20)
            pctPos = index(afterJitter$, "%")
            if pctPos > 0
                numStr$ = left$(afterJitter$, pctPos - 1)
                jitterVal[window] = number(numStr$)
            endif
        endif
        
        # Find shimmer line
        shimmerPos = index(voiceReport$, "Shimmer (local):")
        if shimmerPos > 0
            afterShimmer$ = mid$(voiceReport$, shimmerPos + 17, 20)
            pctPos = index(afterShimmer$, "%")
            if pctPos > 0
                numStr$ = left$(afterShimmer$, pctPos - 1)
                shimmerVal[window] = number(numStr$)
            endif
        endif
        
        # Handle undefined values
        if jitterVal[window] = undefined or jitterVal[window] < 0
            jitterVal[window] = 0.5
        endif
        if shimmerVal[window] = undefined or shimmerVal[window] < 0
            shimmerVal[window] = 3.0
        endif
    else
        # Default values for unvoiced/sparse regions
        jitterVal[window] = 0.5
        shimmerVal[window] = 3.0
    endif
    
    appendInfoLine: "  Window ", window, ": t=", fixed$(analysisTime[window], 2), 
    ... "s, jitter=", fixed$(jitterVal[window], 2), "%, shimmer=", fixed$(shimmerVal[window], 2), "%"
    
    # Cleanup window objects
    removeObject: windowSound, pitchObj, pointProc
endfor

# ============================================================
# NORMALIZE JITTER/SHIMMER VALUES
# ============================================================
minJitter = jitterVal[1]
maxJitter = jitterVal[1]
minShimmer = shimmerVal[1]
maxShimmer = shimmerVal[1]

for w from 2 to num_windows
    if jitterVal[w] < minJitter
        minJitter = jitterVal[w]
    endif
    if jitterVal[w] > maxJitter
        maxJitter = jitterVal[w]
    endif
    if shimmerVal[w] < minShimmer
        minShimmer = shimmerVal[w]
    endif
    if shimmerVal[w] > maxShimmer
        maxShimmer = shimmerVal[w]
    endif
endfor

# Normalize to 0-1 range
for w to num_windows
    if maxJitter > minJitter
        jitterNorm[w] = (jitterVal[w] - minJitter) / (maxJitter - minJitter)
    else
        jitterNorm[w] = 0.5
    endif
    if maxShimmer > minShimmer
        shimmerNorm[w] = (shimmerVal[w] - minShimmer) / (maxShimmer - minShimmer)
    else
        shimmerNorm[w] = 0.5
    endif
endfor

# ============================================================
# DRAW ANALYSIS
# ============================================================
if draw_analysis
    Erase all
    Select outer viewport: 0, 6, 0, 4.5
    Axes: 0, duration, -0.1, 1.2
    
    Colour: "Black"
    Draw inner box
    
    # Grid
    Colour: "{0.8,0.8,0.8}"
    Draw line: 0, 0.5, duration, 0.5
    
    # Draw jitter curve (Blue)
    Colour: "Blue"
    Line width: 2
    
    for w from 1 to num_windows - 1
        Draw line: analysisTime[w], jitterNorm[w], analysisTime[w+1], jitterNorm[w+1]
    endfor
    
    # Draw jitter points
    for w to num_windows
        Draw circle: analysisTime[w], jitterNorm[w], 0.015 * duration
    endfor
    
    # Draw shimmer curve (Red)
    Colour: "Red"
    
    for w from 1 to num_windows - 1
        Draw line: analysisTime[w], shimmerNorm[w], analysisTime[w+1], shimmerNorm[w+1]
    endfor
    
    # Draw shimmer points
    for w to num_windows
        Draw circle: analysisTime[w], shimmerNorm[w], 0.015 * duration
    endfor
    
    # Labels
    Colour: "Black"
    Font size: 12
    Text: duration / 2, "Centre", 1.15, "Half", "Jitter/Shimmer Analysis -> Formant Mapping"
    
    Font size: 10
    Text: duration / 2, "Centre", -0.07, "Half", "Time (s)"
    
    # Legend
    Font size: 9
    Colour: "Blue"
    Text: duration * 0.85, "Centre", 1.05, "Half", "Jitter -> F1"
    Colour: "Red"
    Text: duration * 0.85, "Centre", 0.95, "Half", "Shimmer -> F2"
    
    # Axis marks
    Colour: "Black"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    
    Line width: 1
endif

# ============================================================
# PROCESS SEGMENTS WITH FORMANT MAPPING
# ============================================================
appendInfoLine: ""
appendInfoLine: "Processing segments..."

# Create output sound (silence)
outputSound = Create Sound from formula: "output", 1, 0, duration, sampleRate, "0"

for window from 1 to num_windows
    # Calculate segment boundaries (midpoints between analysis times)
    if window = 1
        segStart = 0
    else
        segStart = (analysisTime[window-1] + analysisTime[window]) / 2
    endif
    
    if window = num_windows
        segEnd = duration
    else
        segEnd = (analysisTime[window] + analysisTime[window+1]) / 2
    endif
    
    # Calculate formant shifts based on jitter/shimmer
    f1Shift = 1.0 + (jitterNorm[window] - 0.5) * jitter_to_F1_scale * 2
    f2Shift = 1.0 + (shimmerNorm[window] - 0.5) * shimmer_to_F2_scale * 2
    
    # Calculate filter frequencies
    f1Low = f1_low * f1Shift
    f1High = f1_high * f1Shift
    f2Low = f2_low * f2Shift
    f2High = f2_high * f2Shift
    
    # Extract segment
    selectObject: originalID
    segSound = Extract part: segStart, segEnd, "Rectangular", 1, "no"
    
    # Apply F1 filter
    selectObject: segSound
    f1Filtered = Filter (pass Hann band): f1Low, f1High, 100
    
    # Apply F2 filter to original segment
    selectObject: segSound
    f2Filtered = Filter (pass Hann band): f2Low, f2High, 100
    
    # Mix F1 and F2 bands
    selectObject: f1Filtered
    plusObject: f2Filtered
    stereoMix = Combine to stereo
    
    selectObject: stereoMix
    monoMix = Convert to mono
    
    # Rename to predictable name for Formula reference
    selectObject: monoMix
    Rename: "seg"
    
    # Scale segment
    Scale peak: 0.9
    
    # Add to output using Formula
    segStartStr$ = fixed$(segStart, 8)
    selectObject: outputSound
    Formula (part): segStart, segEnd, 1, 1, "self + Sound_seg(x - " + segStartStr$ + ")"
    
    # Cleanup segment objects
    removeObject: segSound, f1Filtered, f2Filtered, stereoMix, monoMix
endfor

# ============================================================
# FINALIZE
# ============================================================
selectObject: outputSound
Rename: originalName$ + "_jitshim"

# Normalize
Scale peak: 0.95

# ============================================================
# INFO OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Jitter range: ", fixed$(minJitter, 2), " - ", fixed$(maxJitter, 2), "%"
appendInfoLine: "Shimmer range: ", fixed$(minShimmer, 2), " - ", fixed$(maxShimmer, 2), "%"

if play_result
    selectObject: outputSound
    Play
endif
