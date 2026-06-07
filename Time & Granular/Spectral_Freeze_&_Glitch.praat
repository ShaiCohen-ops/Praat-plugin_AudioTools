# ============================================================
# Praat AudioTools - Spectral_Freeze_&_Glitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Buffer-stutter freeze & glitch (TIME-DOMAIN, not spectral): loops
#   small sample segments at random positions to create stutter/freeze
#   glitches, then applies time-domain amplitude modulation as a
#   corruption artifact. Despite the "Spectral" name, no FFT/spectral
#   processing is performed. Creates CD-skip, buffer-glitch, and broken
#   playback effects.
#
# Changelog v0.5:
#   - Loop-wrap declick: a short raised-cosine taper (Smoothing_ms,
#     default 2 ms) is applied to the start/end of each repeated grain
#     so the periodic loop-wrap discontinuities don't click. No overlap-
#     add is possible in a single Formula pass, so the taper fades each
#     grain edge to zero (a small dip at the loop rate, not a click).
#     Taper auto-clamps to repeatSegment/2; disabled when too short.
#     Toggle Smooth_loop_wraps. Window exit is intentionally left as-is.
#
# Changelog v0.4:
#   - Silence avoidance: freeze positions whose loop-source region is
#     silent (RMS below a fraction of the source's overall RMS) are
#     re-rolled, up to Max_position_attempts; if none found, the point
#     is skipped rather than looping silence. Toggle Avoid_silence.
#     Set Avoid_silence = 0 to reproduce v0.3 behaviour exactly.
#
# Changelog v0.3:
#   - Description corrected: this is a time-domain buffer stutter + AM,
#     not spectral processing (name kept for continuity).
#   - Viz fix: freeze-zone rectangles were painted OVER the result
#     waveform and position lines, hiding the regions of interest. Now
#     drawn as a background band first; waveform and lines render on top.
#   - Removed a dead Colour set before Paint rectangle.
#   - Reset axes explicitly for legend/stats text.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed Formula interpolation
#   - Added visualization
#   - Store freeze positions for display
# ============================================================

form Spectral Freeze and Glitch
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Short Bursts
        option Long Freeze
        option Artifact Storm
        option Custom
    
    comment === Freeze Parameters ===
    natural Freeze_points 12
    positive Freeze_duration_divisor 25
    positive Freeze_length_min_factor 0.5
    positive Freeze_length_max_factor 1.5
    positive Freeze_repeat_divisor 3
    
    comment === Artifacts ===
    positive Artifact_amplitude 0.1
    
    comment === Loop Smoothing ===
    boolean Smooth_loop_wraps 1
    positive Smoothing_ms 2
    
    comment === Silence Avoidance ===
    boolean Avoid_silence 1
    positive Silence_rms_factor 0.15
    natural Max_position_attempts 20
    
    comment === Output ===
    positive Scale_peak 0.91
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    freeze_points = 12
    freeze_duration_divisor = 25
    freeze_length_min_factor = 0.5
    freeze_length_max_factor = 1.5
    freeze_repeat_divisor = 3
    artifact_amplitude = 0.1
elsif preset = 2
    # Short Bursts
    freeze_points = 8
    freeze_duration_divisor = 15
    freeze_length_min_factor = 0.3
    freeze_length_max_factor = 1.0
    freeze_repeat_divisor = 2
    artifact_amplitude = 0.05
elsif preset = 3
    # Long Freeze
    freeze_points = 16
    freeze_duration_divisor = 40
    freeze_length_min_factor = 0.8
    freeze_length_max_factor = 2.0
    freeze_repeat_divisor = 4
    artifact_amplitude = 0.12
elsif preset = 4
    # Artifact Storm
    freeze_points = 20
    freeze_duration_divisor = 20
    freeze_length_min_factor = 0.4
    freeze_length_max_factor = 1.6
    freeze_repeat_divisor = 2
    artifact_amplitude = 0.25
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Short Bursts"
elsif preset = 3
    presetName$ = "Long Freeze"
elsif preset = 4
    presetName$ = "Artifact Storm"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Spectral Freeze & Glitch ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Freeze points: ", freeze_points
appendInfoLine: "Artifact amplitude: ", artifact_amplitude
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_glitch"
result = selected("Sound")

# === Calculate Base Freeze Duration ===
freezeDuration = floor(totalSamples / freeze_duration_divisor)

# === Overall level reference for silence avoidance ===
selectObject: original
overallRMS = Get root-mean-square: 0, duration
if overallRMS = undefined or overallRMS <= 0
    overallRMS = 0.0001
endif
silenceThreshold = silence_rms_factor * overallRMS

# === Loop-smoothing taper width (samples) ===
smoothSamples = round(smoothing_ms / 1000 * sampleRate)
if smoothSamples < 1
    smoothSamples = 1
endif

# === Store Freeze Positions for Visualization ===
freezePositions# = zero#(freeze_points)
freezeLengths# = zero#(freeze_points)
freezeApplied# = zero#(freeze_points)

# === Main Freeze Processing Loop ===
appendInfoLine: "Processing freeze points..."

for point from 1 to freeze_points
    # Position / length bounds
    minPos = floor(freezeDuration)
    maxPos = totalSamples - floor(freezeDuration)
    if maxPos <= minPos
        maxPos = minPos + 1
    endif
    minLen = floor(freezeDuration * freeze_length_min_factor)
    maxLen = floor(freezeDuration * freeze_length_max_factor)
    if minLen < 1
        minLen = 1
    endif
    if maxLen <= minLen
        maxLen = minLen + 1
    endif
    
    # Pick a freeze whose loop-source region is not silent (re-roll if it is)
    attempt = 0
    foundLoud = 0
    repeat
        attempt += 1
        freezePos = randomInteger(minPos, maxPos)
        freezeLength = randomInteger(minLen, maxLen)
        repeatSegment = floor(freezeLength / freeze_repeat_divisor)
        if repeatSegment < 1
            repeatSegment = 1
        endif
        if avoid_silence = 1
            t1 = freezePos / sampleRate
            t2 = (freezePos + repeatSegment) / sampleRate
            if t2 > duration
                t2 = duration
            endif
            selectObject: original
            segRMS = Get root-mean-square: t1, t2
            if segRMS = undefined
                segRMS = 0
            endif
            if segRMS >= silenceThreshold
                foundLoud = 1
            endif
        else
            foundLoud = 1
        endif
    until (foundLoud = 1) or (attempt >= max_position_attempts)
    
    if (avoid_silence = 1) and (foundLoud = 0)
        # No non-silent region found; skip this point rather than loop silence
        freezeApplied#[point] = 0
        freezePositions#[point] = -1
        freezeLengths#[point] = 0
        appendInfoLine: "  Point ", point, ": skipped (no non-silent region)"
    else
        freezeApplied#[point] = 1
        freezePositions#[point] = freezePos / sampleRate
        freezeLengths#[point] = freezeLength / sampleRate
        appendInfoLine: "  Point ", point, ": pos=", fixed$(freezePositions#[point], 3), "s len=", fixed$(freezeLengths#[point] * 1000, 1), "ms"
        
        # Clamp taper to this grain (need >=1 sample, at most half the grain)
        locSmooth = smoothSamples
        if locSmooth > floor(repeatSegment / 2)
            locSmooth = floor(repeatSegment / 2)
        endif
        doSmooth = smooth_loop_wraps
        if locSmooth < 1
            locSmooth = 1
            doSmooth = 0
        endif
        
        # Freeze and repeat segment (stutter), with raised-cosine taper on
        # each grain's edges to declick the loop-wrap boundaries
        selectObject: result
        Formula: ~ if col >= freezePos and col < freezePos + freezeLength 
            ... then self[freezePos + ((col - freezePos) mod repeatSegment)] * ( if doSmooth = 0 then 1 else if ((col - freezePos) mod repeatSegment) < locSmooth then (0.5 - 0.5 * cos(pi * ((col - freezePos) mod repeatSegment) / locSmooth)) else if ((col - freezePos) mod repeatSegment) >= repeatSegment - locSmooth then (0.5 - 0.5 * cos(pi * (repeatSegment - ((col - freezePos) mod repeatSegment)) / locSmooth)) else 1 fi fi fi ) 
            ... else self fi
        
        # Add amplitude-modulation artifacts (time-domain, whole-file; compounds per point)
        Formula: ~ self * (1 + artifact_amplitude * sin(2 * pi * point * col / totalSamples))
    endif
endfor

appliedCount = sum(freezeApplied#)

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Freeze & Glitch: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform with freeze markers
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    
    # Freeze zones as background bands first (so the waveform shows on top)
    Axes: 0, duration, -1, 1
    for p to freeze_points
        if freezeApplied#[p] = 1
            pos = freezePositions#[p]
            len = freezeLengths#[p]
            Paint rectangle: "{0.92, 0.82, 0.85}", pos, pos + len, -0.95, 0.95
        endif
    endfor
    
    # Glitched waveform on top of the zones
    selectObject: result
    Colour: "{0.6, 0.4, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Freeze position lines on top
    Axes: 0, duration, -1, 1
    Colour: "{0.9, 0.3, 0.3}"
    for p to freeze_points
        if freezeApplied#[p] = 1
            pos = freezePositions#[p]
            Draw line: pos, -0.9, pos, 0.9
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Glitched"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.9, 0.3, 0.3}"
    Text: 0.02, "left", 0.97, "half", "Freeze zones"
    
    # Freeze position scatter plot
    Select outer viewport: 0, 8, 3.7, 5.1
    Select inner viewport: 0.6, 7.6, 3.9, 5.0
    
    Axes: 0, duration, 0, freeze_points + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, freeze_points + 1
    
    # Draw freeze zones as horizontal bars
    for p to freeze_points
        if freezeApplied#[p] = 1
            pos = freezePositions#[p]
            len = freezeLengths#[p]
            
            # Color intensity by length
            avgLen = (freeze_length_min_factor + freeze_length_max_factor) / 2
            lenNorm = (freezeLengths#[p] * sampleRate / freezeDuration) / avgLen
            r = 0.5 + 0.3 * lenNorm
            g = 0.3
            b = 0.5
            barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            
            Paint rectangle: barColor$, pos, pos + len, p - 0.4, p + 0.4
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freeze #"
    Text bottom: "yes", "Position in source (s)"
    
    # Stats
    Select outer viewport: 0, 8, 5.3, 5.6
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Freeze points: " + string$(appliedCount) + "/" + string$(freeze_points) + " applied | Artifact: " + fixed$(artifact_amplitude, 2) + " | Repeat divisor: " + string$(freeze_repeat_divisor)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Freeze points applied: ", appliedCount, " / ", freeze_points
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result