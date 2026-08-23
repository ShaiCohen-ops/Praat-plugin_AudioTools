# ============================================================
# Praat AudioTools - Spectral_Freeze_&_Glitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.1 (2026)
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
# Changelog v0.6.1:
#   - VISUAL QA ONLY: preserve the existing three-part Picture concept.
#   - Display-safe source name (underscores no longer become subscripts).
#   - Source/Glitched waveforms now share one amplitude scale.
#   - Added numeric time/index marks and replaced markup-sensitive "Freeze #".
#   - Added left/right Picture margin so side labels are not clipped.
#
# Changelog v0.6:
#   - API COMPATIBILITY: public form is byte-for-byte unchanged.
#     Output naming remains <source>_glitch.
#   - FIX: each freeze point now reads from a pre-pass snapshot. v0.5 read
#     the first repeat directly from result while modifying it; later repeats
#     then re-read the already-tapered first repeat and applied the taper a
#     second time. All repeats now use one truly frozen source grain.
#   - FIX: non-zero Sound start times are handled correctly in RMS analysis
#     and visualization coordinates; audio sample indexing remains unchanged.
#   - FIX: 1-based sample bounds are now valid for very short files and for
#     extreme custom duration/divisor values. Freeze zones and their source
#     repeat segments are guaranteed to stay inside the Sound.
#   - FIX: loop taper reaches exactly zero at both grain edges (when enabled)
#     instead of leaving a small residual on the last sample.
#   - SAFE NORMALIZATION: Scale_peak is skipped for digital silence.
#   - HARDENING: reversed min/max length factors are rejected; practical
#     freeze-point limit prevents accidental thousands of whole-file passes.
#   - VISUALIZATION: normalized title axes; length colour is RGB-safe.
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
sourceStart = Get start time
sourceEnd = Get end time
numChannels = Get number of channels

# === Internal Guards (public form unchanged) ===
if freeze_length_min_factor > freeze_length_max_factor
    exitScript: "Freeze_length_min_factor must be <= Freeze_length_max_factor."
endif
if freeze_points > 5000
    exitScript: "Freeze_points must not exceed 5000."
endif

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
if freezeDuration < 1
    freezeDuration = 1
endif

# Precompute legal freeze-length range in samples.
minLenGlobal = floor(freezeDuration * freeze_length_min_factor)
maxLenGlobal = floor(freezeDuration * freeze_length_max_factor)
if minLenGlobal < 1
    minLenGlobal = 1
endif
if maxLenGlobal < minLenGlobal
    maxLenGlobal = minLenGlobal
endif
if minLenGlobal > totalSamples
    minLenGlobal = totalSamples
endif
if maxLenGlobal > totalSamples
    maxLenGlobal = totalSamples
endif

# === Overall level reference for silence avoidance ===
selectObject: original
overallRMS = Get root-mean-square: sourceStart, sourceEnd
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
    # Pick a complete freeze zone first, then choose a legal 1-based source
    # position that keeps the whole zone inside the Sound.
    freezeLength = randomInteger(minLenGlobal, maxLenGlobal)
    repeatSegment = floor(freezeLength / freeze_repeat_divisor)
    if repeatSegment < 1
        repeatSegment = 1
    endif
    if repeatSegment > freezeLength
        repeatSegment = freezeLength
    endif

    safeMaxPos = totalSamples - freezeLength + 1
    minPos = freezeDuration
    maxPos = totalSamples - freezeDuration + 1
    if minPos < 1
        minPos = 1
    endif
    if maxPos > safeMaxPos
        maxPos = safeMaxPos
    endif
    if minPos > safeMaxPos or maxPos < minPos
        minPos = 1
        maxPos = safeMaxPos
    endif

    # Pick a freeze whose loop-source region is not silent (re-roll position
    # only; length/repeat structure stays fixed for this freeze point).
    attempt = 0
    foundLoud = 0
    repeat
        attempt += 1
        freezePos = randomInteger(minPos, maxPos)
        if avoid_silence = 1
            t1 = sourceStart + (freezePos - 1) / sampleRate
            t2 = sourceStart + (freezePos - 1 + repeatSegment) / sampleRate
            if t2 > sourceEnd
                t2 = sourceEnd
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
        freezePositions#[point] = (freezePos - 1) / sampleRate
        freezeLengths#[point] = freezeLength / sampleRate
        appendInfoLine: "  Point ", point, ": pos=", fixed$(freezePositions#[point], 3), "s len=", fixed$(freezeLengths#[point] * 1000, 1), "ms"
        
        # Clamp taper to this repeated grain. Two samples are required to
        # define an exact 0..1 raised-cosine edge.
        locSmooth = smoothSamples
        if locSmooth > floor(repeatSegment / 2)
            locSmooth = floor(repeatSegment / 2)
        endif
        doSmooth = smooth_loop_wraps
        if locSmooth < 2
            doSmooth = 0
        endif

        # Snapshot BEFORE modifying this freeze point. Every repeat reads the
        # same frozen grain instead of recursively re-reading the tapered
        # first repeat from result. Channel row is preserved.
        selectObject: result
        Copy: "glitch_snapshot"
        snapshot = selected("Sound")

        selectObject: result
        Formula: ~ if col >= freezePos and col < freezePos + freezeLength
            ... then object[snapshot, row, freezePos + ((col - freezePos) mod repeatSegment)] * ( if doSmooth = 0 then 1 else if ((col - freezePos) mod repeatSegment) < locSmooth then (0.5 - 0.5 * cos(pi * ((col - freezePos) mod repeatSegment) / (locSmooth - 1))) else if ((col - freezePos) mod repeatSegment) >= repeatSegment - locSmooth then (0.5 - 0.5 * cos(pi * (repeatSegment - 1 - ((col - freezePos) mod repeatSegment)) / (locSmooth - 1))) else 1 fi fi fi )
            ... else self fi

        removeObject: snapshot
        
        # Add amplitude-modulation artifacts (time-domain, whole-file; compounds per point)
        Formula: ~ self * (1 + artifact_amplitude * sin(2 * pi * point * col / totalSamples))
    endif
endfor

appliedCount = sum(freezeApplied#)

# === Scale Peak ===
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: scale_peak
endif

# === Visualization ===
if draw_visualization
    Erase all

    # Display-only text sanitization: Praat treats underscores as subscript markup.
    displayName$ = replace$(original_name$, "_", " ", 0)

    # Shared waveform amplitude scale so Source and Glitched heights are comparable.
    selectObject: original
    sourceDisplayPeak = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: result
    resultDisplayPeak = Get absolute extremum: 0, 0, "Sinc70"
    displayPeak = sourceDisplayPeak
    if resultDisplayPeak > displayPeak
        displayPeak = resultDisplayPeak
    endif
    if displayPeak <= 0
        displayPeak = 1
    endif
    displayPeak *= 1.05
    
    # Title
    Select outer viewport: 0.35, 7.75, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Spectral Freeze & Glitch: " + displayName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0.25, 7.85, 0.6, 2.0
    Select inner viewport: 0.88, 7.62, 0.7, 1.9
    selectObject: original
    Colour: "{0.68, 0.68, 0.68}"
    Draw: 0, 0, -displayPeak, displayPeak, "no", "Curve"
    # Stereo Sound: Draw can leave Praat in a per-channel subviewport.
    # Re-select the declared inner viewport before axes/labels so side text
    # is anchored to the panel itself, not to the last stereo channel.
    Select outer viewport: 0.25, 7.85, 0.6, 2.0
    Select inner viewport: 0.88, 7.62, 0.7, 1.9
    Axes: 0, duration, -displayPeak, displayPeak
    Colour: "Black"
    Draw inner box
    # Independent vertical side label: X is decoupled from the graph viewport.
    Select outer viewport: 0.28, 0.78, 0.70, 1.90
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "half", "Times", 8, "90", "Original"
    
    # Result waveform with freeze markers
    Select outer viewport: 0.25, 7.85, 2.1, 3.5
    Select inner viewport: 0.88, 7.62, 2.2, 3.4
    
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
    Colour: "{0.60, 0.40, 0.50}"
    Draw: 0, 0, -displayPeak, displayPeak, "no", "Curve"
    
    # Freeze position lines on top
    Axes: 0, duration, -1, 1
    Colour: "{0.9, 0.3, 0.3}"
    for p to freeze_points
        if freezeApplied#[p] = 1
            pos = freezePositions#[p]
            Draw line: pos, -0.9, pos, 0.9
        endif
    endfor
    
    # Reset after stereo drawing/overlays for the same reason as Source above.
    Select outer viewport: 0.25, 7.85, 2.1, 3.5
    Select inner viewport: 0.88, 7.62, 2.2, 3.4
    Axes: 0, duration, -displayPeak, displayPeak
    Colour: "Black"
    Draw inner box
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"

    # Independent vertical side label: same physical X strip as Original.
    Select outer viewport: 0.28, 0.78, 2.20, 3.40
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "half", "Times", 8, "90", "Glitched"

    # Legend stays independent above the data region.
    Select outer viewport: 0.88, 7.62, 2.02, 2.18
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.78, 0.28, 0.38}"
    Text: 1, "right", 0.5, "half", "rose bands = freeze zones"
    
    # Freeze position scatter plot
    Select outer viewport: 0.25, 7.85, 3.7, 5.1
    Select inner viewport: 0.88, 7.62, 3.9, 5.0
    
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
            r = min(1, max(0, 0.5 + 0.3 * lenNorm))
            g = 0.3
            b = 0.5
            barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            
            Paint rectangle: barColor$, pos, pos + len, p - 0.4, p + 0.4
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Marks bottom: 5, "yes", "yes", "no"
    # Integer-only index references; automatic marks produced fractional freeze numbers.
    midFreeze = round(freeze_points / 2)
    if midFreeze < 1
        midFreeze = 1
    endif
    One mark left: 1, "yes", "yes", "no", "1"
    if midFreeze > 1 and midFreeze < freeze_points
        One mark left: midFreeze, "yes", "yes", "no", string$(midFreeze)
    endif
    if freeze_points > 1
        One mark left: freeze_points, "yes", "yes", "no", string$(freeze_points)
    endif
    Font size: 7
    Text left: "yes", "Freeze index"
    Text bottom: "yes", "Position in source (s)"
    
    # Stats
    Select outer viewport: 0.35, 7.75, 5.3, 5.6
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