# ============================================================
# Praat AudioTools - Spiral_Segmentation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spiral-based temporal and pitch transformation. Divides
#   sound into segments, applies exponential duration scaling
#   and incremental pitch shifting to create a spiral trajectory
#   through time-pitch space.
#
# Concept:
#   Material returns repeatedly, but each return occurs at a
#   transformed temporal and spectral level — never identical,
#   never metrically fixed. The spiral is both a formal structure
#   and a perceptual metaphor: expansion, return, displacement.
#
# Changelog v1.1:
#   - Full xmin/xmax-safe segmentation and tier domains.
#   - Preserves the exact source channel count; mono is used for analysis only.
#   - Pitch analysis uses an adaptive 40..min(1200, 0.45*SR) range.
#   - Pitch synthesis safety is independent of analysis: 20 Hz .. 0.45*SR.
#   - Unvoiced material keeps the duration spiral and skips pitch shifting
#     instead of inventing a 150 Hz contour.
#   - Presets now define both Hz and semitone pitch-step equivalents, so
#     either Pitch_scaling mode remains meaningful.
#   - Added validation for segment count, duration multiplier, pitch steps,
#     jitter, sample rate, and extreme parameter combinations.
#   - Exact identity path when duration=1, jitter=0, and active pitch step=0.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; absolute segment boundaries and
#     spiral marker-size safety corrected.
#
# Category: Time & Granular
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

sound = selected("Sound")
name$ = selected$("Sound")

# === USER PARAMETERS ===
form Spiral Segmentation v1.1
    comment === Preset ===
    optionmenu Preset 1
        option Custom (manual settings)
        option Gentle Expansion
        option Accelerating Collapse
        option Pitch Ascent
        option Pitch Descent
        option Drunken Spiral
        option Tight Coil
        option Wide Orbit
        option Reverse Time Feel
        option Glitch Scatter
        option Meditative Stretch
        option Anxious Compression
        option Cosmic Drift
    comment === Segmentation ===
    integer Number_of_segments 12
    comment === Duration Spiral ===
    positive Duration_multiplier 1.15
    optionmenu Spiral_direction 1
        option Expanding (segments get longer)
        option Contracting (segments get shorter)
    comment === Pitch Spiral ===
    real Pitch_step_Hz 5.0
    optionmenu Pitch_direction 1
        option Rising
        option Falling
        option Alternating
    optionmenu Pitch_scaling 1
        option Hertz (additive)
        option Semitones (proportional)
    real Pitch_step_semitones 1.0
    comment === Temporal Jitter (non-metric) ===
    real Jitter_amount 0.08
    comment === Output ===
    boolean Preserve_original 1
    boolean Play_result 1
    boolean Show_visualization 1
endform

# === APPLY PRESETS ===
# Presets define both Hz and semitone step equivalents. Pitch_scaling remains
# under user control, but either mode now receives a meaningful preset value.
if preset > 1
    if preset = 2
        # Gentle Expansion
        number_of_segments = 8
        duration_multiplier = 1.12
        spiral_direction = 1
        pitch_step_Hz = 3
        pitch_step_semitones = 0.25
        pitch_direction = 1
        jitter_amount = 0.05
        presetName$ = "Gentle Expansion"
    elsif preset = 3
        # Accelerating Collapse
        number_of_segments = 16
        duration_multiplier = 1.25
        spiral_direction = 2
        pitch_step_Hz = 8
        pitch_step_semitones = 0.70
        pitch_direction = 2
        jitter_amount = 0.06
        presetName$ = "Accelerating Collapse"
    elsif preset = 4
        # Pitch Ascent
        number_of_segments = 10
        duration_multiplier = 1.05
        spiral_direction = 1
        pitch_step_Hz = 15
        pitch_step_semitones = 1.25
        pitch_direction = 1
        jitter_amount = 0.03
        presetName$ = "Pitch Ascent"
    elsif preset = 5
        # Pitch Descent
        number_of_segments = 10
        duration_multiplier = 1.05
        spiral_direction = 1
        pitch_step_Hz = 15
        pitch_step_semitones = 1.25
        pitch_direction = 2
        jitter_amount = 0.03
        presetName$ = "Pitch Descent"
    elsif preset = 6
        # Drunken Spiral
        number_of_segments = 12
        duration_multiplier = 1.18
        spiral_direction = 1
        pitch_step_Hz = 7
        pitch_step_semitones = 0.60
        pitch_direction = 3
        jitter_amount = 0.25
        presetName$ = "Drunken Spiral"
    elsif preset = 7
        # Tight Coil
        number_of_segments = 24
        duration_multiplier = 1.08
        spiral_direction = 1
        pitch_step_Hz = 2
        pitch_step_semitones = 0.17
        pitch_direction = 1
        jitter_amount = 0.02
        presetName$ = "Tight Coil"
    elsif preset = 8
        # Wide Orbit
        number_of_segments = 6
        duration_multiplier = 1.35
        spiral_direction = 1
        pitch_step_Hz = 20
        pitch_step_semitones = 1.65
        pitch_direction = 1
        jitter_amount = 0.1
        presetName$ = "Wide Orbit"
    elsif preset = 9
        # Reverse Time Feel
        number_of_segments = 12
        duration_multiplier = 1.2
        spiral_direction = 2
        pitch_step_Hz = 5
        pitch_step_semitones = 0.43
        pitch_direction = 1
        jitter_amount = 0.08
        presetName$ = "Reverse Time Feel"
    elsif preset = 10
        # Glitch Scatter
        number_of_segments = 32
        duration_multiplier = 1.1
        spiral_direction = 1
        pitch_step_Hz = 12
        pitch_step_semitones = 1.00
        pitch_direction = 3
        jitter_amount = 0.4
        presetName$ = "Glitch Scatter"
    elsif preset = 11
        # Meditative Stretch
        number_of_segments = 6
        duration_multiplier = 1.5
        spiral_direction = 1
        pitch_step_Hz = 1
        pitch_step_semitones = 0.09
        pitch_direction = 2
        jitter_amount = 0.02
        presetName$ = "Meditative Stretch"
    elsif preset = 12
        # Anxious Compression
        number_of_segments = 20
        duration_multiplier = 1.3
        spiral_direction = 2
        pitch_step_Hz = 10
        pitch_step_semitones = 0.85
        pitch_direction = 1
        jitter_amount = 0.15
        presetName$ = "Anxious Compression"
    elsif preset = 13
        # Cosmic Drift
        number_of_segments = 8
        duration_multiplier = 1.4
        spiral_direction = 1
        pitch_step_Hz = 25
        pitch_step_semitones = 2.00
        pitch_direction = 3
        jitter_amount = 0.12
        presetName$ = "Cosmic Drift"
    endif
else
    presetName$ = "Custom"
endif

# === PITCH SCALING MODE ===
if pitch_scaling = 1
    pstep = pitch_step_Hz
    pitchUnit$ = "Hz"
else
    pstep = pitch_step_semitones
    pitchUnit$ = "st"
endif

# === SETUP / VALIDATION ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  SPIRAL SEGMENTATION v1.1"
writeInfoLine: "=============================================="
appendInfoLine: ""

selectObject: sound
xmin = Get start time
xmax = Get end time
totalDuration = xmax - xmin
sampleRate = Get sampling frequency
n_channels = Get number of channels

if totalDuration <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if number_of_segments < 1 or number_of_segments > 512
    exitScript: "Number_of_segments must be between 1 and 512."
endif
if duration_multiplier < 1 or duration_multiplier > 10
    exitScript: "Duration_multiplier must be between 1 and 10."
endif
if pitch_step_Hz < 0
    exitScript: "Pitch_step_Hz must be zero or greater."
endif
if pitch_step_semitones < 0 or pitch_step_semitones > 48
    exitScript: "Pitch_step_semitones must be between 0 and 48."
endif
if jitter_amount < 0 or jitter_amount > 2
    exitScript: "Jitter_amount must be between 0 and 2."
endif
if sampleRate < 1000
    exitScript: "The source sampling frequency is too low for safe processing."
endif

segmentDuration = totalDuration / number_of_segments
if segmentDuration <= 0
    exitScript: "The requested segmentation is invalid for this Sound."
endif

duration_identity = 0
if duration_multiplier = 1 and jitter_amount = 0
    duration_identity = 1
endif

identity_mode = 0
if duration_identity and pstep = 0
    identity_mode = 1
endif

appendInfoLine: "Input: ", name$
appendInfoLine: "Duration: ", fixed$(totalDuration, 3), " s"
appendInfoLine: "Time domain: ", fixed$(xmin, 3), " .. ", fixed$(xmax, 3), " s"
appendInfoLine: "Sample rate: ", sampleRate, " Hz"
appendInfoLine: "Channels: ", n_channels
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Segments: ", number_of_segments
appendInfoLine: "  Duration multiplier: ", duration_multiplier
appendInfoLine: "  Spiral direction: ", spiral_direction$
appendInfoLine: "  Pitch step: ", pstep, " ", pitchUnit$
appendInfoLine: "  Pitch direction: ", pitch_direction$
appendInfoLine: "  Pitch scaling: ", pitch_scaling$
appendInfoLine: "  Jitter amount: ", jitter_amount
appendInfoLine: ""

# === CALCULATE SEGMENT BOUNDARIES ===
appendInfoLine: "Original segment duration: ", fixed$(segmentDuration * 1000, 1), " ms"
appendInfoLine: ""

for i from 1 to number_of_segments
    segStart[i] = xmin + (i - 1) * segmentDuration
    if i = number_of_segments
        segEnd[i] = xmax
    else
        segEnd[i] = xmin + i * segmentDuration
    endif
endfor

# === CALCULATE SPIRAL DURATION FACTORS ===
appendInfoLine: "Duration factors (spiral):"
totalStretchedDuration = 0

for i from 1 to number_of_segments
    if spiral_direction = 1
        exponent = i - 1
    else
        exponent = number_of_segments - i
    endif

    # Compute safely and cap the usable DurationTier factor at 10.
    logFactor = exponent * ln(duration_multiplier)
    if logFactor >= ln(10)
        durationFactor[i] = 10
    else
        durationFactor[i] = exp(logFactor)
    endif

    jitterOffset[i] = randomGauss(0, jitter_amount)
    durationFactorJittered[i] = durationFactor[i] * (1 + jitterOffset[i])

    if durationFactorJittered[i] < 0.1
        durationFactorJittered[i] = 0.1
    elsif durationFactorJittered[i] > 10
        durationFactorJittered[i] = 10
    endif

    stretchedDuration[i] = segmentDuration * durationFactorJittered[i]
    totalStretchedDuration += stretchedDuration[i]

    appendInfoLine: "  Segment ", i, ": factor=", fixed$(durationFactor[i], 3),
        ... " | jittered=", fixed$(durationFactorJittered[i], 3),
        ... " | dur=", fixed$(stretchedDuration[i] * 1000, 1), " ms"
endfor

appendInfoLine: ""
appendInfoLine: "Estimated output duration: ", fixed$(totalStretchedDuration, 3), " s"
appendInfoLine: "Estimated duration ratio: ", fixed$(totalStretchedDuration / totalDuration, 2), "x"
appendInfoLine: ""

# === CALCULATE PITCH SHIFTS ===
appendInfoLine: "Pitch shifts (spiral):"

for i from 1 to number_of_segments
    if pitch_direction = 1
        pitchShift[i] = pstep * (i - 1)
    elsif pitch_direction = 2
        pitchShift[i] = -pstep * (i - 1)
    else
        if (i mod 2) = 1
            pitchShift[i] = pstep * floor((i - 1) / 2)
        else
            pitchShift[i] = -pstep * floor(i / 2)
        endif
    endif

    appendInfoLine: "  Segment ", i, ": ", fixed$(pitchShift[i], 2), " ", pitchUnit$
endfor
appendInfoLine: ""

# === TRUE IDENTITY PATH ===
safetyApplied = 0
pitchAvailable = 0
timeOnlyMode = 0
analysisMono = 0
analysisManip = 0
originalPitchTier = 0
durationTier = 0
spiralPitchTier = 0

if identity_mode
    selectObject: sound
    result = Copy: name$ + "_spiral"
    finalDuration = Get total duration
    appendInfoLine: "Identity settings: exact audio copy (processing bypassed)."

else
    # === BUILD DURATION TIER ===
    Create DurationTier: "spiral_duration", xmin, xmax
    durationTier = selected("DurationTier")

    tierOffset = min(0.001, segmentDuration / 4)

    for i from 1 to number_of_segments
        selectObject: durationTier
        Add point: segStart[i] + tierOffset, durationFactorJittered[i]
        Add point: segEnd[i] - tierOffset, durationFactorJittered[i]
    endfor

    # === MONO PITCH ANALYSIS ===
    selectObject: sound
    if n_channels > 1
        analysisMono = Convert to mono
    else
        analysisMono = Copy: "SS_analysis"
    endif

    pitchFloor = 40
    pitchCeil = min(1200, 0.45 * sampleRate)

    if pitchCeil > pitchFloor
        selectObject: analysisMono
        analysisManip = To Manipulation: 0.01, pitchFloor, pitchCeil

        selectObject: analysisManip
        originalPitchTier = Extract pitch tier

        selectObject: originalPitchTier
        numPitchPoints = Get number of points
        if numPitchPoints > 0
            pitchAvailable = 1
        endif
    endif

    # === BUILD PITCH TIER WHEN VOICED MATERIAL EXISTS ===
    if pitchAvailable
        appendInfoLine: "Building source-relative spiral pitch tier..."

        Create PitchTier: "spiral_pitch", xmin, xmax
        spiralPitchTier = selected("PitchTier")

        synthFloor = 20
        synthCeil = 0.45 * sampleRate
        limitedPitchPoints = 0

        for p from 1 to numPitchPoints
            selectObject: originalPitchTier
            pointTime = Get time from index: p
            pointPitch = Get value at index: p

            segmentIndex = floor((pointTime - xmin) / segmentDuration) + 1
            if segmentIndex < 1
                segmentIndex = 1
            elsif segmentIndex > number_of_segments
                segmentIndex = number_of_segments
            endif

            if pitch_scaling = 1
                newPitch = pointPitch + pitchShift[segmentIndex]
            else
                shiftSt = pitchShift[segmentIndex]
                if shiftSt > 96
                    newPitch = synthCeil
                elsif shiftSt < -96
                    newPitch = synthFloor
                else
                    newPitch = pointPitch * 2 ^ (shiftSt / 12)
                endif
            endif

            if newPitch < synthFloor
                newPitch = synthFloor
                limitedPitchPoints += 1
            elsif newPitch > synthCeil
                newPitch = synthCeil
                limitedPitchPoints += 1
            endif

            selectObject: spiralPitchTier
            Add point: pointTime, newPitch
        endfor

        if limitedPitchPoints > 0
            appendInfoLine: "Pitch safety limits applied: ", limitedPitchPoints, " point(s)"
        endif
    else
        timeOnlyMode = 1
        appendInfoLine: "No voiced pitch detected: applying duration spiral only."
    endif

    # If no pitch is available and duration is also identity, return exact copy.
    if timeOnlyMode and duration_identity
        selectObject: sound
        result = Copy: name$ + "_spiral"
        finalDuration = Get total duration
        appendInfoLine: "No applicable transformation remained: exact audio copy."

    else
        # === RESYNTHESIZE EACH SOURCE CHANNEL ===
        appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."
        channelResults# = zero#(n_channels)

        for ch from 1 to n_channels
            selectObject: sound
            if n_channels = 1
                channelWork = Copy: "SS_ch1"
            else
                channelWork = Extract one channel: ch
                Rename: "SS_ch" + string$(ch)
            endif

            selectObject: channelWork
            manipulation = To Manipulation: 0.01, pitchFloor, pitchCeil

            selectObject: manipulation
            plusObject: durationTier
            Replace duration tier

            if pitchAvailable
                selectObject: manipulation
                plusObject: spiralPitchTier
                Replace pitch tier
            endif

            selectObject: manipulation
            channelResult = Get resynthesis (overlap-add)
            Rename: "SS_result_ch" + string$(ch)
            channelResults#[ch] = channelResult

            removeObject: manipulation, channelWork
        endfor

        if n_channels = 1
            result = channelResults#[1]
            selectObject: result
            Rename: name$ + "_spiral"
        else
            selectObject: channelResults#[1]
            result_xmin = Get start time
            result_xmax = Get end time
            result_sr = Get sampling frequency

            Create Sound from formula: "SS_result_build", n_channels,
                ... result_xmin, result_xmax, result_sr, "0"
            result = selected("Sound")

            for ch from 1 to n_channels
                selectObject: result
                Formula (part): result_xmin, result_xmax, ch, ch,
                    ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
                removeObject: channelResults#[ch]
            endfor

            selectObject: result
            Rename: name$ + "_spiral"
        endif

        selectObject: result
        finalDuration = Get total duration

        resultPeak = Get absolute extremum: 0, 0, "None"
        if resultPeak > 0.95
            Scale peak: 0.95
            safetyApplied = 1
        endif
    endif
endif

appendInfoLine: ""
appendInfoLine: "Output: ", name$, "_spiral"
appendInfoLine: "Final duration: ", fixed$(finalDuration, 3), " s"
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === VISUALIZATION ===
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Spiral Segmentation##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", name$ + " | " + presetName$
    
    # --- Original Waveform ---
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.8, 7.8, 0.7, 1.7
    
    selectObject: sound
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Draw segment boundaries
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1
    Dotted line
    for i from 1 to number_of_segments - 1
        Draw line: segEnd[i], -1, segEnd[i], 1
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0, 0.8, 0.6, 1.8
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.4, 0.6}"
    Text: 0.95, "right", 0.5, "half", "Original"
    
    # --- Result Waveform ---
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.8, 7.8, 2.0, 3.0
    
    selectObject: result
    Colour: "{0.5, 0.7, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0, 0.8, 1.9, 3.1
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.6, 0.35}"
    Text: 0.95, "right", 0.5, "half", "Spiral"
    
    # --- Duration Factor Plot ---
    Select outer viewport: 0, 4, 3.3, 4.5
    Select inner viewport: 0.8, 3.8, 3.4, 4.4
    
    # Find max factor for scaling
    maxFactor = durationFactorJittered[1]
    for i from 2 to number_of_segments
        if durationFactorJittered[i] > maxFactor
            maxFactor = durationFactorJittered[i]
        endif
    endfor
    
    Axes: 0, number_of_segments + 1, 0, maxFactor * 1.1
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, number_of_segments + 1, 0, maxFactor * 1.1
    
    # Reference line at 1.0
    Colour: "{0.8, 0.8, 0.8}"
    Line width: 0.5
    Dotted line
    Draw line: 0, 1, number_of_segments + 1, 1
    Solid line
    
    # Draw bars
    for i from 1 to number_of_segments
        # Pure spiral (no jitter)
        Paint rectangle: "{0.6, 0.7, 0.9}", i - 0.35, i + 0.35, 0, durationFactor[i]
        
        # Jittered value (outline)
        Colour: "{0.3, 0.4, 0.7}"
        Line width: 1.5
        Draw line: i - 0.4, durationFactorJittered[i], i + 0.4, durationFactorJittered[i]
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Text left: "yes", "Duration"
    Text bottom: "yes", "Segment"
    
    # --- Pitch Shift Plot ---
    Select outer viewport: 4, 8, 3.3, 4.5
    Select inner viewport: 4.4, 7.8, 3.4, 4.4
    
    # Find range for scaling
    minPitch = pitchShift[1]
    maxPitch = pitchShift[1]
    for i from 2 to number_of_segments
        if pitchShift[i] < minPitch
            minPitch = pitchShift[i]
        endif
        if pitchShift[i] > maxPitch
            maxPitch = pitchShift[i]
        endif
    endfor
    
    pitchRange = maxPitch - minPitch
    if pitchRange < 10
        pitchRange = 10
    endif
    
    Axes: 0, number_of_segments + 1, minPitch - pitchRange * 0.1, maxPitch + pitchRange * 0.1
    
    Paint rectangle: "{0.99, 0.97, 0.97}", 0, number_of_segments + 1, minPitch - pitchRange * 0.1, maxPitch + pitchRange * 0.1
    
    # Reference line at 0
    Colour: "{0.8, 0.8, 0.8}"
    Line width: 0.5
    Dotted line
    Draw line: 0, 0, number_of_segments + 1, 0
    Solid line
    
    # Draw points and connecting line
    Colour: "{0.8, 0.5, 0.5}"
    Line width: 1.5
    for i from 2 to number_of_segments
        Draw line: i - 1, pitchShift[i - 1], i, pitchShift[i]
    endfor
    
    # Draw markers at each point (using small rectangles instead of circles)
    for i from 1 to number_of_segments
        markerSize = 0.2
        Paint rectangle: "{0.9, 0.6, 0.6}", i - markerSize, i + markerSize, pitchShift[i] - pitchRange * 0.03, pitchShift[i] + pitchRange * 0.03
        Colour: "{0.7, 0.3, 0.3}"
        Line width: 1
        Draw rectangle: i - markerSize, i + markerSize, pitchShift[i] - pitchRange * 0.03, pitchShift[i] + pitchRange * 0.03
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Text left: "yes", "Shift (" + pitchUnit$ + ")"
    Text bottom: "yes", "Segment"
    
    # --- Spiral Diagram ---
    Select outer viewport: 0, 4, 4.7, 6.5
    Select inner viewport: 0.5, 3.8, 4.8, 6.4
    
    Axes: -1.5, 1.5, -1.5, 1.5
    
    # Background
    Paint rectangle: "{0.98, 0.98, 1.0}", -1.4, 1.4, -1.4, 1.4
    
    # Draw spiral
    Colour: "{0.4, 0.5, 0.8}"
    Line width: 2
    
    # Parametric spiral: r = a + b*theta
    spiralA = 0.2
    spiralB = 0.08
    
    prevX = spiralA
    prevY = 0
    
    for t from 1 to 360 * 3
        theta = t * pi / 180
        r = spiralA + spiralB * theta
        
        if r < 1.3
            xPos = r * cos(theta)
            yPos = r * sin(theta)
            
            Draw line: prevX, prevY, xPos, yPos
            
            prevX = xPos
            prevY = yPos
        endif
    endfor
    
    # Mark segment points on spiral (using rectangles as markers)
    for i from 1 to number_of_segments
        theta = (i - 1) * 2 * pi / number_of_segments * 2.5
        r = spiralA + spiralB * theta
        
        if r < 1.3
            xPos = r * cos(theta)
            yPos = r * sin(theta)
            
            # Size by duration factor
            markerSize = min(0.16, 0.06 + 0.04 * durationFactorJittered[i])
            
            # Draw marker
            Paint rectangle: "{0.9, 0.7, 0.4}", xPos - markerSize, xPos + markerSize, yPos - markerSize, yPos + markerSize
            Colour: "{0.7, 0.4, 0.2}"
            Line width: 1
            Draw rectangle: xPos - markerSize, xPos + markerSize, yPos - markerSize, yPos + markerSize
            
            # Label
            Font size: 5
            Colour: "{0.3, 0.3, 0.4}"
            Text: xPos + 0.18, "left", yPos, "half", string$(i)
        endif
    endfor
    
    Colour: "Black"
    Line width: 0.5
    
    Font size: 7
    Text: 0, "centre", -1.4, "half", "Spiral Trajectory"
    
    # --- Parameters ---
    Select outer viewport: 4, 8, 4.7, 6.5
    Axes: 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.4}"
    
    Text: 0.1, "left", 0.9, "half", "##Parameters##"
    
    Font size: 6
    Colour: "{0.4, 0.4, 0.5}"
    
    Text: 0.1, "left", 0.75, "half", "Segments: " + string$(number_of_segments)
    Text: 0.1, "left", 0.62, "half", "Duration multiplier: " + fixed$(duration_multiplier, 2)
    Text: 0.1, "left", 0.49, "half", "Direction: " + spiral_direction$
    Text: 0.1, "left", 0.36, "half", "Pitch step: " + fixed$(pstep, 1) + " " + pitchUnit$
    Text: 0.1, "left", 0.23, "half", "Pitch direction: " + pitch_direction$
    Text: 0.1, "left", 0.10, "half", "Jitter: " + fixed$(jitter_amount, 2)
    
    Text: 0.55, "left", 0.75, "half", "##Results##"
    Text: 0.55, "left", 0.62, "half", "Original: " + fixed$(totalDuration, 2) + " s"
    Text: 0.55, "left", 0.49, "half", "Output: " + fixed$(finalDuration, 2) + " s"
    Text: 0.55, "left", 0.36, "half", "Ratio: " + fixed$(finalDuration / totalDuration, 2) + "x"
    
    # --- Time Axis ---
    Select outer viewport: 0, 8, 6.6, 6.9
    Select inner viewport: 0.8, 7.8, 6.65, 6.85
    
    maxDur = max(totalDuration, finalDuration)
    Axes: 0, maxDur, 0, 1
    
    Colour: "{0.3, 0.3, 0.35}"
    Line width: 1
    Draw line: 0, 0.5, maxDur, 0.5
    
    Font size: 6
    tickStep = 1
    if maxDur > 10
        tickStep = 2
    endif
    if maxDur > 30
        tickStep = 5
    endif
    
    t = 0
    while t <= maxDur
        Draw line: t, 0.5, t, 0.2
        Text: t, "centre", 0, "half", string$(t)
        t = t + tickStep
    endwhile
    
    Font size: 7
    Text: maxDur / 2, "centre", -0.8, "half", "Time (s)"
    
    Font size: 10
    Line width: 1
    Colour: "Black"
endif

# === CLEANUP ===
if identity_mode = 0
    if durationTier <> 0
        removeObject: durationTier
    endif
    if originalPitchTier <> 0
        removeObject: originalPitchTier
    endif
    if spiralPitchTier <> 0
        removeObject: spiralPitchTier
    endif
    if analysisManip <> 0
        removeObject: analysisManip
    endif
    if analysisMono <> 0
        removeObject: analysisMono
    endif
endif

if not preserve_original
    removeObject: sound
endif

# === OUTPUT ===
appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="

selectObject: result

if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

appendInfoLine: ""
appendInfoLine: "Done!"