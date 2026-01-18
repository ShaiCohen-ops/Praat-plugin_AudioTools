# ============================================================
# Praat AudioTools - Extract_Segment.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Unified
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified segment extraction tool combining Manual, Percentage,
#   Random Single, and Random Multiple extraction methods.
#   Includes fades, attenuation, and visualization.
#
# Combines:
#   - Extract_Segment_Manual.praat
#   - Extract_Segment_Automatic.praat
#   - Extract_Segment_Random.praat
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Extract Segment v1.0
    optionmenu Preset: 1
        option Manual
        option Middle 50%
        option First Quarter
        option Last Quarter
        option Random Slice
        option Multiple Random
    comment === Extraction Method ===
    optionmenu Method: 1
        option Manual (start/end times)
        option Percentage (start/end %)
        option Random Single (fixed duration)
        option Random Multiple (variable durations)
    comment === Manual / Percentage Parameters ===
    real Start_time_or_percent 0.0
    real End_time_or_percent 1.0
    comment === Random Single Parameters ===
    real Extraction_duration 2.0
    comment === Random Multiple Parameters ===
    positive Number_of_segments 4
    real Min_duration 0.25
    real Max_duration 2.0
    comment === Processing ===
    real Fade_time 0.05
    real Attenuation_divisor 1.0
    positive Scale_peak 0.99
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    # Middle 50%
    method = 2
    start_time_or_percent = 25
    end_time_or_percent = 75
    presetName$ = "Middle50"
elsif preset = 3
    # First Quarter
    method = 2
    start_time_or_percent = 0
    end_time_or_percent = 25
    presetName$ = "FirstQuarter"
elsif preset = 4
    # Last Quarter
    method = 2
    start_time_or_percent = 75
    end_time_or_percent = 100
    presetName$ = "LastQuarter"
elsif preset = 5
    # Random Slice
    method = 3
    extraction_duration = 2.0
    presetName$ = "RandomSlice"
elsif preset = 6
    # Multiple Random
    method = 4
    number_of_segments = 4
    min_duration = 0.25
    max_duration = 2.0
    presetName$ = "MultiRandom"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
selectObject: sound
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

clearinfo
writeInfoLine: "=== Extract Segment v1.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", soundName$, " (", fixed$(totalDuration, 3), " s)"
appendInfoLine: ""

# ============================================================
# Method 1: Manual (start/end times)
# ============================================================
if method = 1
    windowStart = start_time_or_percent
    windowEnd = end_time_or_percent
    
    # Validation
    if windowStart < 0
        windowStart = 0
    endif
    if windowEnd > totalDuration
        windowEnd = totalDuration
    endif
    if windowStart >= windowEnd
        exitScript: "Start time must be less than end time."
    endif
    
    segmentDuration = windowEnd - windowStart
    methodName$ = "Manual"
    appendInfoLine: "Method: Manual (", fixed$(windowStart, 3), " - ", fixed$(windowEnd, 3), " s)"

# ============================================================
# Method 2: Percentage (start/end %)
# ============================================================
elsif method = 2
    startPercent = start_time_or_percent
    endPercent = end_time_or_percent
    
    # Validation
    if startPercent < 0
        startPercent = 0
    endif
    if endPercent > 100
        endPercent = 100
    endif
    if startPercent >= endPercent
        exitScript: "Start percentage must be less than end percentage."
    endif
    
    windowStart = totalDuration * (startPercent / 100)
    windowEnd = totalDuration * (endPercent / 100)
    segmentDuration = windowEnd - windowStart
    methodName$ = "Percentage"
    appendInfoLine: "Method: Percentage (", fixed$(startPercent, 0), "% - ", fixed$(endPercent, 0), "%)"
    appendInfoLine: "  -> ", fixed$(windowStart, 3), " - ", fixed$(windowEnd, 3), " s"

# ============================================================
# Method 3: Random Single (fixed duration)
# ============================================================
elsif method = 3
    if extraction_duration <= 0
        exitScript: "Extraction duration must be positive."
    endif
    if extraction_duration > totalDuration
        exitScript: "Extraction duration (" + fixed$(extraction_duration, 2) + " s) exceeds total duration (" + fixed$(totalDuration, 2) + " s)."
    endif
    
    maxStartTime = totalDuration - extraction_duration
    windowStart = randomUniform(0, maxStartTime)
    windowEnd = windowStart + extraction_duration
    segmentDuration = extraction_duration
    methodName$ = "RandomSingle"
    appendInfoLine: "Method: Random Single (", fixed$(extraction_duration, 2), " s)"
    appendInfoLine: "  -> ", fixed$(windowStart, 3), " - ", fixed$(windowEnd, 3), " s"

# ============================================================
# Method 4: Random Multiple (variable durations)
# ============================================================
elsif method = 4
    if min_duration <= 0 or max_duration <= 0
        exitScript: "Durations must be positive."
    endif
    if min_duration > max_duration
        exitScript: "Minimum duration cannot exceed maximum duration."
    endif
    if max_duration > totalDuration
        exitScript: "Maximum duration (" + fixed$(max_duration, 2) + " s) exceeds total duration (" + fixed$(totalDuration, 2) + " s)."
    endif
    
    methodName$ = "RandomMultiple"
    appendInfoLine: "Method: Random Multiple (", number_of_segments, " segments)"
    appendInfoLine: "  Duration range: ", fixed$(min_duration, 2), " - ", fixed$(max_duration, 2), " s"
    appendInfoLine: ""
endif

# ============================================================
# Extraction
# ============================================================
if method <= 3
    # Single segment extraction
    
    # Validate fade time
    if fade_time < 0
        fade_time = 0
    endif
    if fade_time > segmentDuration / 2
        fade_time = segmentDuration / 2
        appendInfoLine: "Note: Fade time reduced to ", fixed$(fade_time, 3), " s"
    endif
    
    # Extract
    selectObject: sound
    extracted = Extract part: windowStart, windowEnd, "rectangular", 1, "no"
    
    # Attenuation
    if attenuation_divisor > 1
        attDiv$ = string$(attenuation_divisor)
        Formula: "self / " + attDiv$
    endif
    
    # Fade in
    if fade_time > 0
        fadeTime$ = string$(fade_time)
        Formula: "self * min(1, x / " + fadeTime$ + ")"
        
        # Fade out
        Formula: "self * min(1, (xmax - x) / " + fadeTime$ + ")"
    endif
    
    # Scale
    Scale peak: scale_peak
    Rename: soundName$ + "_" + methodName$ + "_" + presetName$
    outputSound = selected("Sound")
    
    # Store for visualization
    segStart_1 = windowStart
    segEnd_1 = windowEnd
    numExtracted = 1
    
    appendInfoLine: ""
    appendInfoLine: "Extracted: ", fixed$(segmentDuration, 3), " s"
    
else
    # Multiple segment extraction (method 4)
    appendInfoLine: "Extracting segments:"
    
    for i from 1 to number_of_segments
        # Random duration
        segDur = randomUniform(min_duration, max_duration)
        
        # Random start
        maxStart = totalDuration - segDur
        segStart = randomUniform(0, maxStart)
        segEnd = segStart + segDur
        
        # Store for visualization
        segStart_'i' = segStart
        segEnd_'i' = segEnd
        segDur_'i' = segDur
        
        # Extract
        selectObject: sound
        seg = Extract part: segStart, segEnd, "rectangular", 1, "no"
        
        # Validate fade for this segment
        segFade = fade_time
        if segFade > segDur / 2
            segFade = segDur / 2
        endif
        
        # Attenuation
        if attenuation_divisor > 1
            attDiv$ = string$(attenuation_divisor)
            Formula: "self / " + attDiv$
        endif
        
        # Fades
        if segFade > 0
            segFade$ = string$(segFade)
            Formula: "self * min(1, x / " + segFade$ + ")"
            Formula: "self * min(1, (xmax - x) / " + segFade$ + ")"
        endif
        
        # Scale
        Scale peak: scale_peak
        Rename: soundName$ + "_seg" + string$(i)
        segment_'i' = selected("Sound")
        
        appendInfoLine: "  Segment ", i, ": ", fixed$(segStart, 3), " - ", fixed$(segEnd, 3), " s (", fixed$(segDur, 2), " s)"
    endfor
    
    numExtracted = number_of_segments
    
    # For output selection, use first segment
    outputSound = segment_1
endif

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Extract Segment: " + soundName$ + " [" + presetName$ + "]"
    
    # Original waveform with extraction zones
    Select outer viewport: 0, 8, 0.6, 2.8
    Select inner viewport: 0.6, 7.6, 0.8, 2.6
    
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Get amplitude range for shading
    selectObject: sound
    maxAmp = Get maximum: 0, 0, "None"
    minAmp = Get minimum: 0, 0, "None"
    
    Axes: 0, totalDuration, minAmp * 1.1, maxAmp * 1.1
    
    # Shade extraction zones
    if method <= 3
        # Single extraction
        Paint rectangle: "{0.8, 0.9, 1.0}", segStart_1, segEnd_1, minAmp * 1.1, maxAmp * 1.1
        
        # Redraw waveform on top
        selectObject: sound
        Colour: "{0.5, 0.5, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        # Highlight extracted portion
        Colour: "{0.2, 0.4, 0.8}"
        Line width: 2
        Draw: segStart_1, segEnd_1, 0, 0, "no", "Curve"
        Line width: 1
    else
        # Multiple extractions - different colors
        for i from 1 to numExtracted
            sStart = segStart_'i'
            sEnd = segEnd_'i'
            
            # Cycle through colors - use explicit color for Paint rectangle
            if i mod 4 = 1
                Paint rectangle: "{0.8, 0.9, 1.0}", sStart, sEnd, minAmp * 1.1, maxAmp * 1.1
            elsif i mod 4 = 2
                Paint rectangle: "{0.9, 1.0, 0.8}", sStart, sEnd, minAmp * 1.1, maxAmp * 1.1
            elsif i mod 4 = 3
                Paint rectangle: "{1.0, 0.9, 0.8}", sStart, sEnd, minAmp * 1.1, maxAmp * 1.1
            else
                Paint rectangle: "{0.9, 0.8, 1.0}", sStart, sEnd, minAmp * 1.1, maxAmp * 1.1
            endif
        endfor
        
        # Redraw waveform
        selectObject: sound
        Colour: "{0.4, 0.4, 0.4}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original with extraction zone(s)"
    
    # Extracted waveform(s)
    if method <= 3
        # Single extracted
        Select outer viewport: 0, 8, 3.0, 4.8
        Select inner viewport: 0.6, 7.6, 3.2, 4.6
        
        selectObject: outputSound
        Colour: "{0.2, 0.5, 0.8}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Amplitude"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Extracted: " + fixed$(segmentDuration, 3) + " s"
    else
        # Multiple segments - show first few
        showCount = min(3, numExtracted)
        panelHeight = 1.5 / showCount
        
        for i from 1 to showCount
            yTop = 3.0 + (i - 1) * panelHeight
            yBot = yTop + panelHeight - 0.1
            
            Select outer viewport: 0, 8, yTop, yBot
            Select inner viewport: 0.6, 7.6, yTop + 0.1, yBot - 0.05
            
            selectObject: segment_'i'
            
            if i mod 4 = 1
                Colour: "{0.2, 0.4, 0.8}"
            elsif i mod 4 = 2
                Colour: "{0.3, 0.6, 0.3}"
            elsif i mod 4 = 3
                Colour: "{0.8, 0.5, 0.2}"
            else
                Colour: "{0.6, 0.3, 0.7}"
            endif
            
            Draw: 0, 0, 0, 0, "no", "Curve"
            Colour: "Black"
            Draw inner box
            Font size: 7
            sDur = segDur_'i'
            Text top: "no", "Seg " + string$(i) + " (" + fixed$(sDur, 2) + " s)"
        endfor
        
        if numExtracted > 3
            Select outer viewport: 0, 8, 4.5, 4.8
            Font size: 8
            Colour: "{0.4, 0.4, 0.4}"
            Text: 0.5, "centre", 0.5, "half", "... and " + string$(numExtracted - 3) + " more segment(s)"
        endif
    endif
    
    # Stats panel
    Select outer viewport: 0, 8, 5.0, 5.8
    Select inner viewport: 0.6, 7.6, 5.1, 5.7
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.05, "left", 0.7, "half", "Method: " + methodName$
    Text: 0.05, "left", 0.3, "half", "Segments: " + string$(numExtracted)
    Text: 0.5, "left", 0.7, "half", "Fade: " + fixed$(fade_time * 1000, 0) + " ms"
    Text: 0.5, "left", 0.3, "half", "Atten: /" + fixed$(attenuation_divisor, 1)
    
    Colour: "Black"
    Draw inner box
    Font size: 10
endif

# ============================================================
# Output
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="

if method <= 3
    selectObject: sound
    plusObject: outputSound
    appendInfoLine: "Output: ", selected$("Sound")
else
    selectObject: sound
    for i from 1 to numExtracted
        plusObject: segment_'i'
    endfor
    appendInfoLine: "Created ", numExtracted, " segments"
endif

if play_result
    if method <= 3
        selectObject: outputSound
        Play
    else
        selectObject: segment_1
        Play
    endif
endif

if method <= 3
    selectObject: outputSound
else
    selectObject: segment_1
endif