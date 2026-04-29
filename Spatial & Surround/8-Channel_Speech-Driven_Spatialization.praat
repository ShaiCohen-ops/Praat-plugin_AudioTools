# ============================================================
# Praat AudioTools - 8-Channel_Speech-Driven_Spatialization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Speech-Driven 8-Channel Spatialization
#   Maps pitch to azimuth angle and intensity to distance.
#   Uses constant-power panning between adjacent speakers.
#
# Changelog v0.3:
#   - Fixed: adjacent-speaker selection failed near 0°/360°
#     wrap-around. v0.2 compared targetAngle to nearest's
#     angle in raw value; this broke when target and nearest
#     were on opposite sides of the wrap. Example: target 350°
#     would correctly identify Ch2 (0°) as nearest, then
#     incorrectly pick Ch3 (45°) as adjacent instead of Ch1
#     (315°), and the pan formula sent 100% of audio to the
#     wrong speaker.
#     Fixed by computing a SIGNED angular delta in (-180°, 180°]
#     from nearest to target, then picking adjacent ±1 in the
#     speaker array based on the sign of that delta. Pan
#     position is now computed from angular DISTANCES, not
#     raw angle subtraction, so wrap-around can't corrupt it.
#   - Fixed: zipper noise from sample-and-hold gain. v0.2's
#     per-sample Formula did `round(x / frameShift)` to look
#     up gain per output sample, producing 100 step-discontinuities
#     per second per channel.
#     Replaced with AmplitudeTier multiplication: one tier per
#     channel with frame-rate breakpoints, multiplied into the
#     audio by Praat's native linear-interpolating Multiply.
#     Smooth envelopes, no zippers, also faster than the
#     per-sample Formula.
#   - Default ambient_level lowered from 0.05 to 0.01. The old
#     default sent 5% of every voice frame to all six non-active
#     speakers, smearing localization. 0.01 keeps the ambient
#     bed audible without defeating the spatialization.
#   - Visualization rewritten to suite 8x8 standard
#     (matching 22.2 Stem Renderer, 8-ch I Ching, 8-ch Movements,
#     4-ch Canon, 8-ch Spectral Shift, 8-ch Speed Deviations).
#     Multi-panel layout:
#       Panel A: Octagon speaker map with movement trajectory.
#                Speaker positions COMPUTED from speakerAngles#
#                (was hardcoded coordinate by coordinate).
#       Panel B: Pitch contour over time, with floor/ceiling
#                and angle mapping reference.
#       Panel C: Intensity contour over time, with min/max
#                gain mapping shown.
#       Panel D: Output waveform (Ch1 blue, Ch2 orange).
#       Panel E: Summary stats bar (grey, framed).
#   - Code cleanup: dynamic-name pattern gain'ch'# / channel'ch'
#     replaced with proper 2D matrix gainCh## and 1D array
#     channel[ch]. Mostly stylistic; same behavior, easier to
#     read and to extend.
# Changelog v0.2:
#   - Added form with presets, input validation, viz, play option
# ============================================================

form 8-Channel Speech-Driven Spatialization
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Full Range (pitch: 75-600 Hz)"
        option: "Voice Range (pitch: 100-300 Hz)"
        option: "Narrow Range (pitch: 150-250 Hz)"
        option: "Extended Range (pitch: 50-800 Hz)"
        option: "Inverted (high=back, low=front)"
    
    comment === Pitch mapping ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    real Low_pitch_angle 225
    real High_pitch_angle 45
    
    comment === Intensity mapping ===
    real Min_distance_gain 0.2
    real Max_distance_gain 1.0
    real Ambient_level 0.01
    
    comment === Analysis ===
    positive Time_step 0.01
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    pitch_floor = 75
    pitch_ceiling = 600
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "FullRange"
elsif preset = 3
    pitch_floor = 100
    pitch_ceiling = 300
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "VoiceRange"
elsif preset = 4
    pitch_floor = 150
    pitch_ceiling = 250
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "NarrowRange"
elsif preset = 5
    pitch_floor = 50
    pitch_ceiling = 800
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "ExtendedRange"
elsif preset = 6
    pitch_floor = 75
    pitch_ceiling = 600
    low_pitch_angle = 45
    high_pitch_angle = 225
    presetName$ = "Inverted"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

writeInfoLine: "=== 8-Channel Speech-Driven Spatialization v0.3 ==="
appendInfoLine: "Source: ", soundName$, "  (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# === Convert to mono if stereo ===
numberOfChannels = Get number of channels
if numberOfChannels > 1
    selectObject: sound
    monoSound = Convert to mono
else
    selectObject: sound
    monoSound = Copy: soundName$ + "_mono"
endif

# === Extract features ===
appendInfoLine: "Extracting pitch..."
selectObject: monoSound
pitch = To Pitch: time_step, pitch_floor, pitch_ceiling

appendInfoLine: "Extracting intensity..."
selectObject: monoSound
intensity = To Intensity: 100, time_step, "yes"

# Get feature ranges for normalization
selectObject: pitch
pitchMean = Get mean: 0, 0, "Hertz"
pitchMin = Get minimum: 0, 0, "Hertz", "Parabolic"
pitchMax = Get maximum: 0, 0, "Hertz", "Parabolic"

selectObject: intensity
intensityMean = Get mean: 0, 0
intensityMin = Get minimum: 0, 0, "Parabolic"
intensityMax = Get maximum: 0, 0, "Parabolic"

appendInfoLine: "Pitch range: ", fixed$(pitchMin, 1), " - ", fixed$(pitchMax, 1), " Hz"
appendInfoLine: "Intensity range: ", fixed$(intensityMin, 1), " - ", fixed$(intensityMax, 1), " dB"
appendInfoLine: ""

# === Speaker layout ===
speakerAngles# = { 315, 0, 45, 90, 135, 180, 225, 270 }

# === Frame schedule ===
frameShift = time_step
numberOfFrames = floor(duration / frameShift)
appendInfoLine: "Frames: ", numberOfFrames

# === Storage ===
# Per-channel per-frame gain (8 x N matrix)
gainCh## = zero## (8, numberOfFrames)

# Per-frame traces for visualization
pitchTrace# = zero# (numberOfFrames)
intensityTrace# = zero# (numberOfFrames)
angleTrace# = zero# (numberOfFrames)
distGainTrace# = zero# (numberOfFrames)

# ============================================================
# ANALYSIS LOOP — compute per-frame gains
# ============================================================
appendInfoLine: "Computing pan gains per frame..."
lastPitchValue = pitchMean
stopwatch

for frame from 1 to numberOfFrames
    t = frame * frameShift
    
    # --- Sample pitch ---
    selectObject: pitch
    pitchValue = Get value at time: t, "Hertz", "linear"
    if pitchValue = undefined
        pitchValue = lastPitchValue
    else
        lastPitchValue = pitchValue
    endif
    pitchTrace#[frame] = pitchValue
    
    # --- Sample intensity ---
    selectObject: intensity
    intensityValue = Get value at time: t, "Linear"
    if intensityValue = undefined
        intensityValue = intensityMean
    endif
    intensityTrace#[frame] = intensityValue
    
    # --- Normalize ---
    if pitchMin < pitchMax
        pitchNorm = (pitchValue - pitchMin) / (pitchMax - pitchMin)
    else
        pitchNorm = 0.5
    endif
    pitchNorm = max(0, min(1, pitchNorm))
    
    if intensityMin < intensityMax
        intensityNorm = (intensityValue - intensityMin) / (intensityMax - intensityMin)
    else
        intensityNorm = 0.5
    endif
    intensityNorm = max(0, min(1, intensityNorm))
    
    # --- Map pitch -> azimuth angle ---
    angleRange = high_pitch_angle - low_pitch_angle
    if angleRange < 0
        angleRange = angleRange + 360
    endif
    targetAngle = low_pitch_angle + pitchNorm * angleRange
    while targetAngle >= 360
        targetAngle = targetAngle - 360
    endwhile
    while targetAngle < 0
        targetAngle = targetAngle + 360
    endwhile
    angleTrace#[frame] = targetAngle
    
    # --- Map intensity -> distance gain ---
    distanceGain = min_distance_gain + intensityNorm * (max_distance_gain - min_distance_gain)
    distGainTrace#[frame] = distanceGain
    
    # --- Find nearest speaker (smallest angular distance) ---
    minAngleDiff = 360
    nearestSpeaker = 1
    for sp from 1 to 8
        ad = abs(targetAngle - speakerAngles#[sp])
        if ad > 180
            ad = 360 - ad
        endif
        if ad < minAngleDiff
            minAngleDiff = ad
            nearestSpeaker = sp
        endif
    endfor
    
    # --- Find adjacent speaker (FIXED in v0.3) ---
    # Compute SIGNED angular delta in (-180, 180] from nearest to target.
    # Speaker array is in clockwise order (each +1 index = +45°), so
    # positive delta -> next index, negative delta -> previous index.
    delta = targetAngle - speakerAngles#[nearestSpeaker]
    while delta > 180
        delta = delta - 360
    endwhile
    while delta <= -180
        delta = delta + 360
    endwhile
    
    if delta >= 0
        adjacentSpeaker = nearestSpeaker + 1
        if adjacentSpeaker > 8
            adjacentSpeaker = 1
        endif
    else
        adjacentSpeaker = nearestSpeaker - 1
        if adjacentSpeaker < 1
            adjacentSpeaker = 8
        endif
    endif
    
    # --- Pan position from angular DISTANCES (FIXED in v0.3) ---
    # Both d_main and d_total computed as wrap-aware angular distances,
    # so the pan ratio is correct regardless of where on the ring the
    # source is.
    d_main = abs(delta)
    delta_sp = speakerAngles#[adjacentSpeaker] - speakerAngles#[nearestSpeaker]
    while delta_sp > 180
        delta_sp = delta_sp - 360
    endwhile
    while delta_sp <= -180
        delta_sp = delta_sp + 360
    endwhile
    d_total = abs(delta_sp)
    
    if d_total < 0.001
        panPosition = 0
    else
        panPosition = d_main / d_total
    endif
    panPosition = max(0, min(1, panPosition))
    
    # --- Constant-power panning ---
    gain_main     = sqrt(1 - panPosition) * distanceGain
    gain_adjacent = sqrt(panPosition)     * distanceGain
    
    # --- Fill gain matrix for this frame ---
    for ch from 1 to 8
        if ch = nearestSpeaker
            gainCh##[ch, frame] = gain_main
        elsif ch = adjacentSpeaker
            gainCh##[ch, frame] = gain_adjacent
        else
            gainCh##[ch, frame] = distanceGain * ambient_level
        endif
    endfor
endfor

analysisElapsed = stopwatch
appendInfoLine: "  (analysis: ", fixed$(analysisElapsed, 2), " s)"
appendInfoLine: ""

# ============================================================
# APPLY GAINS via AmplitudeTier multiplication
# (replaces per-sample Formula sample-and-hold from v0.2)
# ============================================================
appendInfoLine: "Building gain envelopes (AmplitudeTier per channel)..."
stopwatch

for ch from 1 to 8
    # Build the tier for this channel
    Create AmplitudeTier: "ampTier_" + string$(ch), 0, duration
    ampTier = selected("AmplitudeTier")
    
    # Anchor at t=0 with frame-1 value (extends left of first analysis point)
    Add point: 0, gainCh##[ch, 1]
    
    for f from 1 to numberOfFrames
        Add point: f * frameShift, gainCh##[ch, f]
    endfor
    
    # Multiply mono source by tier — Praat interpolates linearly between
    # tier points, producing a smooth gain envelope at audio rate
    selectObject: monoSound
    plusObject: ampTier
    Multiply
    channel[ch] = selected("Sound")
    Rename: "channel_" + string$(ch)
    
    removeObject: ampTier
endfor

gainElapsed = stopwatch
appendInfoLine: "  (gain envelopes: ", fixed$(gainElapsed, 2), " s)"
appendInfoLine: ""

# ============================================================
# COMBINE 8 channels -> multichannel
# ============================================================
appendInfoLine: "Combining channels..."
selectObject: channel[1]
for ch from 2 to 8
    plusObject: channel[ch]
endfor
multichannel = Combine to stereo
Scale peak: 0.95
Rename: soundName$ + "_8chSpatial_" + presetName$

# ============================================================
# Cleanup analysis objects (keep multichannel result)
# ============================================================
removeObject: pitch, intensity, monoSound
for ch from 1 to 8
    removeObject: channel[ch]
endfor

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all
    
    # ------- Per-channel speaker colours (used in Panel A) --------
    # Cool-to-warm palette around the ring. Speaker colours are FIXED;
    # this is a layout chart, not a value chart.
    spkColR#  = { 0.30, 0.45, 0.78, 0.85, 0.78, 0.55, 0.30, 0.20 }
    spkColG#  = { 0.55, 0.70, 0.55, 0.40, 0.30, 0.30, 0.30, 0.45 }
    spkColB#  = { 0.85, 0.55, 0.30, 0.25, 0.30, 0.55, 0.75, 0.80 }
    
    # ------- Build subsampled trace for trajectory drawing --------
    # Cap to ~500 segments to keep drawing fast on long files.
    maxTraj = 500
    if numberOfFrames < maxTraj
        trajN = numberOfFrames
    else
        trajN = maxTraj
    endif
    trajX# = zero# (trajN)
    trajY# = zero# (trajN)
    trajT# = zero# (trajN)
    trajRadius = 0.55
    for k from 1 to trajN
        # Sample evenly across the recording
        srcIdx = round((k - 1) / max(1, trajN - 1) * (numberOfFrames - 1)) + 1
        if srcIdx < 1
            srcIdx = 1
        endif
        if srcIdx > numberOfFrames
            srcIdx = numberOfFrames
        endif
        ang = angleTrace#[srcIdx] * pi / 180
        trajX#[k] = trajRadius * sin(ang)
        trajY#[k] = trajRadius * cos(ang)
        trajT#[k] = (srcIdx - 1) * frameShift
    endfor
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPEECH-DRIVEN SPATIALIZATION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  Pitch: " + fixed$(pitch_floor, 0) + "-" + fixed$(pitch_ceiling, 0) + " Hz"
        ... + "  |  Map: " + fixed$(low_pitch_angle, 0) + "° -> " + fixed$(high_pitch_angle, 0) + "°"
    
    # ----------------------------------------------------------
    # PANEL A: OCTAGON SPEAKER MAP + TRAJECTORY  (left)
    # Speakers placed using speakerAngles# (computed, not hardcoded).
    # Trajectory is a colour-graded line from start (warm) to end (cool).
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 0.85, 4.50
    
    Axes: -1.45, 1.45, -1.45, 1.45
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.45, 1.45, -1.45, 1.45
    
    # Concentric guide rings
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    rGuide# = { 0.30, 0.55, 0.80, 1.05 }
    for r from 1 to 4
        rg = rGuide#[r]
        prevX = rg
        prevY = 0
        for k from 1 to 64
            a = 2 * pi * k / 64
            cx = rg * cos(a)
            cy = rg * sin(a)
            Draw line: prevX, prevY, cx, cy
            prevX = cx
            prevY = cy
        endfor
    endfor
    
    # Crosshairs
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: -1.35, 0, 1.35, 0
    Draw line: 0, -1.35, 0, 1.35
    Solid line
    
    # --- Speaker positions (computed from speakerAngles#) ---
    # Praat is y-up. Compass: angle 0° = +y (front), 90° = +x (right).
    rSpk = 1.15
    for sp from 1 to 8
        a = speakerAngles#[sp] * pi / 180
        spkX[sp] = rSpk * sin(a)
        spkY[sp] = rSpk * cos(a)
    endfor
    
    # Octagon outline
    Colour: "{0.78, 0.78, 0.82}"
    Line width: 1
    for sp from 1 to 8
        sp2 = (sp mod 8) + 1
        Draw line: spkX[sp], spkY[sp], spkX[sp2], spkY[sp2]
    endfor
    
    # --- Trajectory (under speakers but over crosshairs) ---
    # Warm (red) at start, cool (blue) at end. Linear interpolation in RGB.
    Line width: 1.5
    if trajN > 1
        for k from 2 to trajN
            progress = (k - 1) / (trajN - 1)
            tr = 0.85 - 0.65 * progress
            tg = 0.20 + 0.20 * progress
            tb = 0.20 + 0.65 * progress
            Colour: "{" + fixed$(tr, 2) + ", " + fixed$(tg, 2) + ", " + fixed$(tb, 2) + "}"
            Draw line: trajX#[k - 1], trajY#[k - 1], trajX#[k], trajY#[k]
        endfor
    endif
    Line width: 1
    
    # --- Speakers on top ---
    for sp from 1 to 8
        rgb$ = "{" + fixed$(spkColR#[sp], 2) + ", " + fixed$(spkColG#[sp], 2) + ", " + fixed$(spkColB#[sp], 2) + "}"
        Paint circle (mm): rgb$, spkX[sp], spkY[sp], 4.5
        Colour: "White"
        Font size: 7
        Text: spkX[sp], "centre", spkY[sp], "half", string$(sp)
    endfor
    
    # Listener
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 3
    Colour: "{0.15, 0.45, 0.18}"
    Font size: 5
    Text: 0, "centre", -0.20, "half", "L"
    
    # Cardinal labels
    Font size: 6
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0, "centre", 1.40, "half", "Front (0°)"
    Text: 0, "centre", -1.40, "half", "Back (180°)"
    Text: -1.40, "right", 0, "half", "L"
    Text: 1.40, "left", 0, "half", "R"
    
    # Trajectory legend (start/end markers)
    if trajN > 1
        Paint circle (mm): "{0.85, 0.20, 0.20}", trajX#[1], trajY#[1], 1.8
        Paint circle (mm): "{0.20, 0.40, 0.85}", trajX#[trajN], trajY#[trajN], 1.8
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: PITCH CONTOUR  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92
    
    pLo = pitch_floor * 0.92
    pHi = pitch_ceiling * 1.08
    Axes: 0, duration, pLo, pHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, pLo, pHi
    
    # Horizontal grid every 100 Hz
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    pg = ceiling(pLo / 100) * 100
    while pg <= pHi
        Draw line: 0, pg, duration, pg
        pg = pg + 100
    endwhile
    
    # Pitch_floor and pitch_ceiling reference lines
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Line width: 1.5
    Draw line: 0, pitch_floor, duration, pitch_floor
    Draw line: 0, pitch_ceiling, duration, pitch_ceiling
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: duration * 0.99, "right", pitch_floor, "bottom", "floor " + fixed$(pitch_floor, 0) + " Hz"
    Text: duration * 0.99, "right", pitch_ceiling, "top", "ceiling " + fixed$(pitch_ceiling, 0) + " Hz"
    
    # Pitch curve (subsample to ~600 segments max)
    maxPitchSeg = 600
    if numberOfFrames < maxPitchSeg
        pStep = 1
    else
        pStep = floor(numberOfFrames / maxPitchSeg)
    endif
    
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 1.2
    prevT = -1
    prevP = -1
    f = 1
    while f <= numberOfFrames
        t = (f - 1) * frameShift
        p = pitchTrace#[f]
        if p > 0 and prevT >= 0 and prevP > 0
            Draw line: prevT, prevP, t, p
        endif
        prevT = t
        prevP = p
        f = f + pStep
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL C: INTENSITY CONTOUR  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52
    
    iLo = intensityMin - 5
    iHi = intensityMax + 5
    if iHi - iLo < 10
        iHi = iLo + 10
    endif
    
    Axes: 0, duration, iLo, iHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, iLo, iHi
    
    # Horizontal grid every 10 dB
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    ig = ceiling(iLo / 10) * 10
    while ig <= iHi
        Draw line: 0, ig, duration, ig
        ig = ig + 10
    endwhile
    
    # Min/max intensity reference
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Line width: 1.5
    Draw line: 0, intensityMin, duration, intensityMin
    Draw line: 0, intensityMax, duration, intensityMax
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.45, 0.45, 0.45}"
    Text: duration * 0.99, "right", intensityMin, "bottom",
        ... "min " + fixed$(intensityMin, 1) + " dB -> gain " + fixed$(min_distance_gain, 2)
    Text: duration * 0.99, "right", intensityMax, "top",
        ... "max " + fixed$(intensityMax, 1) + " dB -> gain " + fixed$(max_distance_gain, 2)
    
    # Intensity curve
    maxIntSeg = 600
    if numberOfFrames < maxIntSeg
        iStep = 1
    else
        iStep = floor(numberOfFrames / maxIntSeg)
    endif
    
    Colour: "{0.78, 0.45, 0.30}"
    Line width: 1.2
    prevT = -1
    prevI = -1
    f = 1
    while f <= numberOfFrames
        t = (f - 1) * frameShift
        ic = intensityTrace#[f]
        if prevT >= 0
            Draw line: prevT, prevI, t, ic
        endif
        prevT = t
        prevI = ic
        f = f + iStep
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Intensity (dB)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Speaker map + trajectory  (red = start, blue = end)"
    Text: 6.10, "centre", 7.30, "half", "Pitch (upper, drives angle) & intensity (lower, drives gain)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: multichannel
    outDurViz = Get total duration
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0
    
    selectObject: multichannel
    nResultCh = Get number of channels
    if nResultCh >= 1
        Extract one channel: 1
        vizCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vizCh1
    endif
    if nResultCh >= 2
        selectObject: multichannel
        Extract one channel: 2
        vizCh2 = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vizCh2
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (blue = Ch1 / Front-Left,  orange = Ch2 / Front)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + soundName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  Pitch range: " + fixed$(pitch_floor, 0) + "-" + fixed$(pitch_ceiling, 0) + " Hz"
        ... + "  |  Pitch -> Angle: " + fixed$(low_pitch_angle, 0) + "° -> " + fixed$(high_pitch_angle, 0) + "°"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Distance gain: " + fixed$(min_distance_gain, 2) + " - " + fixed$(max_distance_gain, 2)
        ... + "  |  Ambient bed: " + fixed$(ambient_level, 3)
        ... + "  |  Time step: " + fixed$(time_step * 1000, 1) + " ms"
        ... + "  |  Frames: " + string$(numberOfFrames)
        ... + "  |  Layout: octagon (Ch1=315° FL, Ch2=0° F, ..., Ch8=270° L)"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Channel layout:"
appendInfoLine: "  1: Front Left (315°)"
appendInfoLine: "  2: Front Center (0°)"
appendInfoLine: "  3: Front Right (45°)"
appendInfoLine: "  4: Side Right (90°)"
appendInfoLine: "  5: Back Right (135°)"
appendInfoLine: "  6: Back Center (180°)"
appendInfoLine: "  7: Back Left (225°)"
appendInfoLine: "  8: Side Left (270°)"

if play_result
    selectObject: multichannel
    Play
endif

selectObject: multichannel
