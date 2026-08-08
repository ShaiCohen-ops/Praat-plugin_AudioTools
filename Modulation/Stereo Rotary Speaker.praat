# ============================================================
# Praat AudioTools - Stereo_Rotary_Speaker.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Leslie-inspired single-rotor stereo speaker model.
#   A rotating virtual source creates two coupled effects:
#     1. directional amplitude modulation (tremolo);
#     2. continuous fractional-delay modulation (Doppler).
#   Left/right microphone angles are represented as a phase offset.
#
#   This is intentionally a single-rotor creative model, not a full
#   electromechanical Leslie cabinet simulation with separate horn/drum,
#   crossover, acceleration constants, cabinet radiation and room acoustics.
#
# Changelog v0.3:
#   - Replaced rounded sample delay with continuous time-interpolated delay.
#   - LFO uses local Sound time, so shifted Sounds give the same result.
#   - Transition preset now really accelerates from chorale to tremolo speed.
#   - Doppler control is now explicit delay excursion in milliseconds.
#   - Mono becomes stereo only when the effect is active; 2+ channels preserved.
#     Odd channels use the left trajectory, even channels the right trajectory.
#   - Added exact 0% Dry/Wet and zero-modulation bypass.
#   - Removed forced peak normalization; Safety_peak only attenuates.
#   - Added causal/derivative-safe Doppler clamps and updated Info.
#   - Visualization updated to AudioTools house style.
# ============================================================

form Stereo Rotary Speaker v0.3
    optionmenu Preset: 1
        option Custom (use settings below)
        option Chorale (Slow / Hymn)
        option Tremolo (Fast / Rock)
        option Transition (Ramping Up)
        option Wide Stereo Spin
        option Broken Cabinet (Wobbly)
    comment === Rotation ===
    real Rotation_speed_Hz 6.8
    comment (constant speed for Custom; Transition preset ramps 0.8 -> 6.8 Hz)
    comment === Rotor modulation ===
    real Doppler_delay_depth_ms 0.60
    comment (continuous path-delay excursion; 0 disables Doppler)
    real Tremolo_depth 0.50
    comment (0 = none, 1 = full attenuation at the rear)
    comment === Stereo image ===
    real Stereo_width_deg 140
    comment (phase angle between odd/even channel trajectories)
    comment === Output ===
    real Dry_wet_percent 100
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
soundStart = Get start time
soundEnd = Get end time
channels = Get number of channels

if duration <= 0
    exitScript: "Sound has zero duration."
endif

# === Presets ===
transitionMode = 0
transitionStartHz = 0.8
transitionEndHz = 6.8

if preset = 2
    rotation_speed_Hz = 0.8
    doppler_delay_depth_ms = 0.40
    tremolo_depth = 0.30
    stereo_width_deg = 120
    presetName$ = "Chorale"
elsif preset = 3
    rotation_speed_Hz = 6.8
    doppler_delay_depth_ms = 0.60
    tremolo_depth = 0.50
    stereo_width_deg = 160
    presetName$ = "Tremolo"
elsif preset = 4
    transitionMode = 1
    transitionStartHz = 0.8
    transitionEndHz = 6.8
    rotation_speed_Hz = transitionEndHz
    doppler_delay_depth_ms = 0.75
    tremolo_depth = 0.40
    stereo_width_deg = 180
    presetName$ = "Transition"
elsif preset = 5
    rotation_speed_Hz = 2.5
    doppler_delay_depth_ms = 0.50
    tremolo_depth = 0.70
    stereo_width_deg = 180
    presetName$ = "WideSpin"
elsif preset = 6
    rotation_speed_Hz = 9.0
    doppler_delay_depth_ms = 1.25
    tremolo_depth = 0.60
    stereo_width_deg = 45
    presetName$ = "Broken"
else
    presetName$ = "Custom"
endif

# === Validation / clamps ===
rotation_speed_Hz = max(0, min(20, rotation_speed_Hz))
doppler_delay_depth_ms = max(0, min(10, doppler_delay_depth_ms))
tremolo_depth = max(0, min(1, tremolo_depth))
stereo_width_deg = max(0, min(180, stereo_width_deg))
dry_wet_percent = max(0, min(100, dry_wet_percent))
if safety_peak < 0
    safety_peak = 0
elsif safety_peak > 1
    safety_peak = 1
endif

if transitionMode
    maxSpeedHz = max(transitionStartHz, transitionEndHz)
else
    maxSpeedHz = rotation_speed_Hz
endif

# Limit the time-warp derivative to |d'(t)| <= 0.45.
# This keeps playback direction positive and avoids extreme Doppler warps.
requestedDopplerSec = doppler_delay_depth_ms / 1000
if maxSpeedHz > 0
    maxSafeDopplerSec = 0.45 / (2 * pi * maxSpeedHz)
else
    maxSafeDopplerSec = 0.010
endif
dopplerSec = min(requestedDopplerSec, maxSafeDopplerSec)
dopplerClamped = 0
if dopplerSec < requestedDopplerSec
    dopplerClamped = 1
    doppler_delay_depth_ms = dopplerSec * 1000
endif

widthRad = stereo_width_deg * pi / 180
wet = dry_wet_percent / 100

# Minimal positive baseline keeps the variable delay causal.
if dopplerSec > 0
    baseDelaySec = dopplerSec + 1 / sr
    maxDelaySec = baseDelaySec + dopplerSec
else
    baseDelaySec = 0
    maxDelaySec = 0
endif

# Approximate peak pitch excursion produced by the delay derivative.
warpPeak = 2 * pi * maxSpeedHz * dopplerSec
if warpPeak > 0
    pitchUpCents = 1200 * ln(1 + warpPeak) / ln(2)
    pitchDownCents = -1200 * ln(max(1e-9, 1 - warpPeak)) / ln(2)
else
    pitchUpCents = 0
    pitchDownCents = 0
endif

# === Info ===
clearinfo
writeInfoLine: "=== Stereo Rotary Speaker v0.3 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Model: Leslie-inspired single rotor (not separate horn + drum)"
appendInfoLine: "Channels: ", channels, " | Sample rate: ", fixed$(sr, 0), " Hz"
appendInfoLine: ""
if transitionMode
    appendInfoLine: "Rotation: ", fixed$(transitionStartHz, 2), " -> ", fixed$(transitionEndHz, 2), " Hz (linear acceleration)"
else
    appendInfoLine: "Rotation: ", fixed$(rotation_speed_Hz, 2), " Hz (", fixed$(rotation_speed_Hz * 60, 0), " RPM)"
endif
appendInfoLine: "Doppler delay excursion: ", fixed$(1000 * dopplerSec, 3), " ms"
appendInfoLine: "Approx. peak Doppler: +", fixed$(pitchUpCents, 1), " / -", fixed$(pitchDownCents, 1), " cents"
appendInfoLine: "Tremolo depth: ", fixed$(100 * tremolo_depth, 1), "%"
appendInfoLine: "Stereo phase width: ", fixed$(stereo_width_deg, 1), " deg"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
if dopplerClamped
    appendInfoLine: "WARNING: Doppler delay was reduced to keep the time warp causal/stable."
endif
appendInfoLine: ""

# === Exact bypass ===
if wet = 0 or (dopplerSec = 0 and tremolo_depth = 0)
    selectObject: original
    Copy: original_name$ + "_rotary_" + presetName$
    result = selected("Sound")
    appendInfoLine: "Exact bypass: no processing or safety gain change applied."
else
    # Mono is duplicated only for an active stereo effect.
    if channels = 1
        selectObject: original
        Convert to stereo
        source = selected("Sound")
        sourceIsTemp = 1
    else
        selectObject: original
        Copy: original_name$ + "_rotary_source"
        source = selected("Sound")
        sourceIsTemp = 1
    endif

    selectObject: source
    Copy: original_name$ + "_rotary_" + presetName$
    result = selected("Sound")

    # Variables used by the vectorized Sound formula.
    globalSource = source
    globalStart = soundStart
    globalDuration = duration
    globalWidth = widthRad
    globalDoppler = dopplerSec
    globalBaseDelay = baseDelaySec
    globalMaxDelay = maxDelaySec
    globalTremolo = tremolo_depth
    globalWet = wet

    if transitionMode
        globalSpeed0 = transitionStartHz
        globalSpeed1 = transitionEndHz

        # phase(t) is the integral of a linear speed ramp.
        phaseExpr$ = "(2*pi*(globalSpeed0*(x-globalStart) + 0.5*(globalSpeed1-globalSpeed0)/globalDuration*(x-globalStart)^2) + if row-2*floor(row/2)=1 then 0 else globalWidth fi)"
    else
        globalSpeed = rotation_speed_Hz
        phaseExpr$ = "(2*pi*globalSpeed*(x-globalStart) + if row-2*floor(row/2)=1 then 0 else globalWidth fi)"
    endif

    gainExpr$ = "(1 - globalTremolo*0.5*(1-cos(" + phaseExpr$ + ")))"

    if dopplerSec > 0
        # Closest approach (phase=0) has maximum level and minimum path delay.
        delayExpr$ = "(globalBaseDelay - globalDoppler*cos(" + phaseExpr$ + "))"
        rampExpr$ = "min(1,max(0,(x-globalStart)/globalMaxDelay))"
        formula$ = "object(globalSource,x,row)*(1-globalWet*" + rampExpr$ + ") + globalWet*" + rampExpr$ + "*" + gainExpr$ + "*object(globalSource,x-" + delayExpr$ + ",row)"
    else
        formula$ = "(1-globalWet)*object(globalSource,x,row) + globalWet*" + gainExpr$ + "*object(globalSource,x,row)"
    endif

    selectObject: result
    Formula: formula$

    if sourceIsTemp
        removeObject: source
    endif

    # Safety ceiling: attenuation only, never amplification.
    selectObject: result
    preSafetyPeak = Get absolute extremum: 0, 0, "None"
    safetyApplied = 0
    if safety_peak > 0 and preSafetyPeak > safety_peak
        Scale peak: safety_peak
        safetyApplied = 1
    endif
    selectObject: result
    postSafetyPeak = Get absolute extremum: 0, 0, "None"

    appendInfoLine: "Peak before safety: ", fixed$(preSafetyPeak, 6)
    if safetyApplied
        appendInfoLine: "Safety attenuated output to ", fixed$(safety_peak, 3)
    else
        appendInfoLine: "Safety: no gain change"
    endif
    appendInfoLine: "Output peak: ", fixed$(postSafetyPeak, 6)
endif

# === Visualization ===
if draw_visualization
    selectObject: result
    resultChannels = Get number of channels
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak < 0.001
        resultPeak = 0.001
    endif

    Erase all

    # Title / metadata
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Stereo Rotary Speaker##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if transitionMode
        speedStr$ = fixed$(transitionStartHz, 1) + " -> " + fixed$(transitionEndHz, 1) + " Hz"
    else
        speedStr$ = fixed$(rotation_speed_Hz, 2) + " Hz"
    endif
    Text: 0.5, "centre", -1.30, "half",
        ... original_name$ + "  |  " + presetName$
        ... + "  |  " + speedStr$
        ... + "  |  " + fixed$(doppler_delay_depth_ms, 2) + " ms Doppler"
        ... + "  |  " + fixed$(100*tremolo_depth, 0) + "% tremolo"

    # Input waveform
    Select outer viewport: 0, 8, 0.65, 1.65
    Select inner viewport: 0.55, 7.72, 0.78, 1.53
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.75, 2.75
    Select inner viewport: 0.55, 7.72, 1.88, 2.63
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, -1.1*resultPeak, 1.1*resultPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Text bottom: "yes", "Time (s)"

    vizDur = min(2, duration)
    nPoints = 300

    # Tremolo trajectories
    Select outer viewport: 0, 4, 2.95, 4.45
    Select inner viewport: 0.55, 3.82, 3.12, 4.28
    Axes: 0, vizDur, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, 0, 1.05

    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        if transitionMode
            ph1 = 2*pi*(transitionStartHz*t1 + 0.5*(transitionEndHz-transitionStartHz)/duration*t1^2)
            ph2 = 2*pi*(transitionStartHz*t2 + 0.5*(transitionEndHz-transitionStartHz)/duration*t2^2)
        else
            ph1 = 2*pi*rotation_speed_Hz*t1
            ph2 = 2*pi*rotation_speed_Hz*t2
        endif
        g1 = 1 - tremolo_depth*0.5*(1-cos(ph1))
        g2 = 1 - tremolo_depth*0.5*(1-cos(ph2))
        Draw line: t1, g1, t2, g2
    endfor

    Colour: "{0.48, 0.35, 0.74}"
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        if transitionMode
            ph1 = 2*pi*(transitionStartHz*t1 + 0.5*(transitionEndHz-transitionStartHz)/duration*t1^2) + widthRad
            ph2 = 2*pi*(transitionStartHz*t2 + 0.5*(transitionEndHz-transitionStartHz)/duration*t2^2) + widthRad
        else
            ph1 = 2*pi*rotation_speed_Hz*t1 + widthRad
            ph2 = 2*pi*rotation_speed_Hz*t2 + widthRad
        endif
        g1 = 1 - tremolo_depth*0.5*(1-cos(ph1))
        g2 = 1 - tremolo_depth*0.5*(1-cos(ph2))
        Draw line: t1, g1, t2, g2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Amplitude trajectory"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Local time (s)"

    # Doppler delay trajectories
    Select outer viewport: 4, 8, 2.95, 4.45
    Select inner viewport: 4.35, 7.72, 3.12, 4.28
    if dopplerSec > 0
        minDelayMs = 1000*(baseDelaySec-dopplerSec)
        maxDelayMs = 1000*(baseDelaySec+dopplerSec)
    else
        minDelayMs = 0
        maxDelayMs = 1
    endif
    Axes: 0, vizDur, minDelayMs-0.05, maxDelayMs+0.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, minDelayMs-0.05, maxDelayMs+0.05

    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        if transitionMode
            ph1 = 2*pi*(transitionStartHz*t1 + 0.5*(transitionEndHz-transitionStartHz)/duration*t1^2)
            ph2 = 2*pi*(transitionStartHz*t2 + 0.5*(transitionEndHz-transitionStartHz)/duration*t2^2)
        else
            ph1 = 2*pi*rotation_speed_Hz*t1
            ph2 = 2*pi*rotation_speed_Hz*t2
        endif
        d1 = 1000*(baseDelaySec-dopplerSec*cos(ph1))
        d2 = 1000*(baseDelaySec-dopplerSec*cos(ph2))
        Draw line: t1, d1, t2, d2
    endfor

    Colour: "{0.48, 0.35, 0.74}"
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        if transitionMode
            ph1 = 2*pi*(transitionStartHz*t1 + 0.5*(transitionEndHz-transitionStartHz)/duration*t1^2) + widthRad
            ph2 = 2*pi*(transitionStartHz*t2 + 0.5*(transitionEndHz-transitionStartHz)/duration*t2^2) + widthRad
        else
            ph1 = 2*pi*rotation_speed_Hz*t1 + widthRad
            ph2 = 2*pi*rotation_speed_Hz*t2 + widthRad
        endif
        d1 = 1000*(baseDelaySec-dopplerSec*cos(ph1))
        d2 = 1000*(baseDelaySec-dopplerSec*cos(ph2))
        Draw line: t1, d1, t2, d2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Doppler path delay"
    Text left: "yes", "ms"
    Text bottom: "yes", "Local time (s)"

    # Summary
    Select outer viewport: 0, 8, 4.65, 5.45
    Select inner viewport: 0.55, 7.72, 4.77, 5.33
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
        ... "Speed " + speedStr$
        ... + "  |  Doppler " + fixed$(doppler_delay_depth_ms, 2) + " ms"
        ... + "  |  Tremolo " + fixed$(100*tremolo_depth, 0) + "%"
        ... + "  |  Width " + fixed$(stereo_width_deg, 0) + " deg"
    Text: 0.02, "left", 0.18, "half",
        ... "Dry/Wet " + fixed$(dry_wet_percent, 0) + "%"
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  " + string$(resultChannels) + " ch"
        ... + "  |  Safety " + fixed$(safety_peak, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
