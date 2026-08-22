# ============================================================
# Praat AudioTools - Stereo_Swirl_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Swirl Vibrato - a stereo/multichannel delay-line vibrato.
#   Odd and even channels use phase-offset sinusoidal delay trajectories,
#   producing complementary pitch motion and a wide swirling image.
#
#   Delay modulation uses continuous time interpolation.  This is pitch/time
#   modulation rather than literal source panning: 90 degrees means quadrature
#   modulation and 180 degrees means counter-sweeping pitch trajectories.
#   A Dry/Wet control allows pure vibrato (100%) or chorus-like mixtures.
#
# Changelog v0.4:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.3:
#   - Removed destructive pre-scaling of the selected stereo Sound.
#   - Removed forced peak normalization; Safety_peak only attenuates.
#   - Replaced future-reading rounded samples with causal fractional delay.
#   - LFO now uses local Sound time, preserving shifted-time invariance.
#   - Renamed depth as Delay_depth_percent for explicit semantics.
#   - Added true Dry/Wet; Gentle Stereo Chorus now uses a dry+wet mixture.
#   - Mono becomes stereo only when active; 2+ channels are preserved.
#     Odd channels use the left trajectory, even channels the right trajectory.
#   - Added exact Dry/Wet=0 and Depth=0 bypass and derivative-safe clamps.
#   - Corrected misleading Leslie preset name and v3.1/v0.2 version mismatch.
#   - Visualization updated to AudioTools house style.
# ============================================================

form Stereo Swirl Vibrato v0.4
    optionmenu Preset: 1
        option Custom (use settings below)
        option Gentle Stereo Chorus (90 deg subtle)
        option Wide Stereo Swirl (180 deg dramatic)
        option Slow Circular Swirl (90 deg)
        option Psychedelic Spiral (270 deg intense)
        option Subtle Width (45 deg gentle)
        option Extreme Dizzy (180 deg fast)
    comment === Delay-line vibrato ===
    real Base_delay_ms 6.0
    real Delay_depth_percent 12.0
    comment (delay excursion as percent of Base delay; 0 = no vibrato)
    real Modulation_rate_Hz 4.5
    comment === Stereo / multichannel phase ===
    real Phase_offset_degrees 90
    comment (0=locked, 90=quadrature, 180=counter-sweep, 270=reverse quadrature)
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
originalName$ = selected$("Sound")
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
if preset = 2
    base_delay_ms = 5.0
    delay_depth_percent = 10.0
    modulation_rate_Hz = 5.0
    phase_offset_degrees = 90
    dry_wet_percent = 45
    presetName$ = "GentleChorus"
elsif preset = 3
    base_delay_ms = 6.0
    delay_depth_percent = 15.0
    modulation_rate_Hz = 4.5
    phase_offset_degrees = 180
    dry_wet_percent = 100
    presetName$ = "WideSwirl"
elsif preset = 4
    base_delay_ms = 8.0
    delay_depth_percent = 18.0
    modulation_rate_Hz = 1.5
    phase_offset_degrees = 90
    dry_wet_percent = 100
    presetName$ = "SlowCircle"
elsif preset = 5
    base_delay_ms = 7.0
    delay_depth_percent = 20.0
    modulation_rate_Hz = 6.0
    phase_offset_degrees = 270
    dry_wet_percent = 100
    presetName$ = "Spiral"
elsif preset = 6
    base_delay_ms = 4.0
    delay_depth_percent = 8.0
    modulation_rate_Hz = 4.0
    phase_offset_degrees = 45
    dry_wet_percent = 35
    presetName$ = "SubtleWidth"
elsif preset = 7
    base_delay_ms = 10.0
    delay_depth_percent = 25.0
    modulation_rate_Hz = 8.0
    phase_offset_degrees = 180
    dry_wet_percent = 100
    presetName$ = "ExtremeDizzy"
else
    presetName$ = "Custom"
endif

# === Validation / clamps ===
base_delay_ms = max(0, min(50, base_delay_ms))
delay_depth_percent = max(0, min(95, delay_depth_percent))
modulation_rate_Hz = max(0, min(20, modulation_rate_Hz))
phase_offset_degrees = phase_offset_degrees - 360 * floor(phase_offset_degrees / 360)
dry_wet_percent = max(0, min(100, dry_wet_percent))
if safety_peak < 0
    safety_peak = 0
elsif safety_peak > 1
    safety_peak = 1
endif

baseDelaySec = base_delay_ms / 1000
requestedDepthRatio = delay_depth_percent / 100

# Keep instantaneous playback speed positive: |delay'(t)| <= 0.45.
# delay(t) = base * (1 + depth * sin(wt)); max |delay'| = 2*pi*f*base*depth.
if modulation_rate_Hz > 0 and baseDelaySec > 0
    maxDepthWarp = 0.45 / (2*pi*modulation_rate_Hz*baseDelaySec)
else
    maxDepthWarp = 0.95
endif
effectiveDepthRatio = min(requestedDepthRatio, min(0.95, maxDepthWarp))
depthClamped = 0
if effectiveDepthRatio < requestedDepthRatio
    depthClamped = 1
    delay_depth_percent = 100 * effectiveDepthRatio
endif

delayExcursionSec = baseDelaySec * effectiveDepthRatio
minDelaySec = baseDelaySec - delayExcursionSec
maxDelaySec = baseDelaySec + delayExcursionSec

# A positive one-sample minimum prevents out-of-domain/noncausal reads.
if effectiveDepthRatio > 0 and minDelaySec < 1/sr
    baseDelaySec = (1/sr) / max(1e-12, 1-effectiveDepthRatio)
    base_delay_ms = 1000 * baseDelaySec
    delayExcursionSec = baseDelaySec * effectiveDepthRatio
    minDelaySec = baseDelaySec - delayExcursionSec
    maxDelaySec = baseDelaySec + delayExcursionSec
endif

phaseOffsetRad = phase_offset_degrees * pi / 180
wet = dry_wet_percent / 100
warpPeak = 2*pi*modulation_rate_Hz*delayExcursionSec
if warpPeak > 0
    pitchUpCents = 1200*ln(1+warpPeak)/ln(2)
    pitchDownCents = -1200*ln(max(1e-9,1-warpPeak))/ln(2)
else
    pitchUpCents = 0
    pitchDownCents = 0
endif

# === Info ===
clearinfo
writeInfoLine: "=== Stereo Swirl Vibrato v0.4 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", channels, " | Sample rate: ", fixed$(sr, 0), " Hz"
appendInfoLine: "Model: phase-offset delay vibrato; not literal spatial panning"
appendInfoLine: ""
appendInfoLine: "Base delay: ", fixed$(1000*baseDelaySec, 3), " ms"
appendInfoLine: "Delay depth: ", fixed$(100*effectiveDepthRatio, 2), "% (+/-", fixed$(1000*delayExcursionSec, 3), " ms)"
appendInfoLine: "Rate: ", fixed$(modulation_rate_Hz, 3), " Hz"
appendInfoLine: "Phase offset: ", fixed$(phase_offset_degrees, 1), " deg"
appendInfoLine: "Approx. peak vibrato: +", fixed$(pitchUpCents, 1), " / -", fixed$(pitchDownCents, 1), " cents"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
if depthClamped
    appendInfoLine: "WARNING: Delay depth reduced to keep the time warp causal/stable."
endif
appendInfoLine: ""

# === Exact bypass ===
if wet = 0 or effectiveDepthRatio = 0 or modulation_rate_Hz = 0 or baseDelaySec = 0
    selectObject: original
    Copy: originalName$ + "_swirl_" + presetName$
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
        source = original
        sourceIsTemp = 0
    endif

    selectObject: source
    Copy: originalName$ + "_swirl_" + presetName$
    result = selected("Sound")

    globalSource = source
    globalStart = soundStart
    globalBaseDelay = baseDelaySec
    globalExcursion = delayExcursionSec
    globalRate = modulation_rate_Hz
    globalPhase = phaseOffsetRad
    globalWet = wet
    globalMaxDelay = maxDelaySec

    phaseExpr$ = "(2*pi*globalRate*(x-globalStart) + if row-2*floor(row/2)=1 then 0 else globalPhase fi)"
    delayExpr$ = "(globalBaseDelay + globalExcursion*sin(" + phaseExpr$ + "))"
    rampExpr$ = "min(1,max(0,(x-globalStart)/globalMaxDelay))"
    formula$ = "object(globalSource,x,row)*(1-globalWet*" + rampExpr$ + ") + globalWet*" + rampExpr$ + "*object(globalSource,x-" + delayExpr$ + ",row)"

    selectObject: result
    Formula: formula$

    if sourceIsTemp
        removeObject: source
    endif

    selectObject: result
    preSafetyPeak = Get absolute extremum: 0, 0, "None"
    safetyApplied = 0
    if safety_peak > 0 and preSafetyPeak > safety_peak
        Scale peak: safety_peak
        safetyApplied = 1
    endif
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
    pageHeight = 5.7
    selectObject: result
    resultChannels = Get number of channels
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak < 0.001
        resultPeak = 0.001
    endif

    Erase all

    # Title / metadata
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Stereo Swirl Vibrato v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + fixed$(modulation_rate_Hz, 2) + " Hz"
        ... + "  |  " + fixed$(delay_depth_percent, 1) + "% delay depth"
        ... + "  |  " + fixed$(phase_offset_degrees, 0) + " deg"

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

    # Delay trajectories
    Select outer viewport: 0, 4, 2.95, 4.45
    Select inner viewport: 0.55, 3.82, 3.12, 4.28
    minDelayMs = 1000*minDelaySec
    maxDelayMs = 1000*maxDelaySec
    marginMs = max(0.05, 0.08*(maxDelayMs-minDelayMs))
    Axes: 0, vizDur, minDelayMs-marginMs, maxDelayMs+marginMs
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, minDelayMs-marginMs, maxDelayMs+marginMs

    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        d1 = 1000*(baseDelaySec + delayExcursionSec*sin(2*pi*modulation_rate_Hz*t1))
        d2 = 1000*(baseDelaySec + delayExcursionSec*sin(2*pi*modulation_rate_Hz*t2))
        Draw line: t1, d1, t2, d2
    endfor
    Colour: "{0.48, 0.35, 0.74}"
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        d1 = 1000*(baseDelaySec + delayExcursionSec*sin(2*pi*modulation_rate_Hz*t1 + phaseOffsetRad))
        d2 = 1000*(baseDelaySec + delayExcursionSec*sin(2*pi*modulation_rate_Hz*t2 + phaseOffsetRad))
        Draw line: t1, d1, t2, d2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Delay trajectory"
    Text left: "yes", "ms"
    Text bottom: "yes", "Local time (s)"

    # Approximate instantaneous pitch trajectories
    Select outer viewport: 4, 8, 2.95, 4.45
    Select inner viewport: 4.35, 7.72, 3.12, 4.28
    centsMax = max(5, max(pitchUpCents, pitchDownCents)*1.12)
    Axes: 0, vizDur, -centsMax, centsMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, -centsMax, centsMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, vizDur, 0

    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1.5
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        r1 = 1 - warpPeak*cos(2*pi*modulation_rate_Hz*t1)
        r2 = 1 - warpPeak*cos(2*pi*modulation_rate_Hz*t2)
        c1 = 1200*ln(max(1e-9,r1))/ln(2)
        c2 = 1200*ln(max(1e-9,r2))/ln(2)
        Draw line: t1, c1, t2, c2
    endfor
    Colour: "{0.48, 0.35, 0.74}"
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        r1 = 1 - warpPeak*cos(2*pi*modulation_rate_Hz*t1 + phaseOffsetRad)
        r2 = 1 - warpPeak*cos(2*pi*modulation_rate_Hz*t2 + phaseOffsetRad)
        c1 = 1200*ln(max(1e-9,r1))/ln(2)
        c2 = 1200*ln(max(1e-9,r2))/ln(2)
        Draw line: t1, c1, t2, c2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Pitch trajectory"
    Text left: "yes", "cents"
    Text bottom: "yes", "Local time (s)"

    # Summary
    Select outer viewport: 0, 8, 4.65, 5.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
        ... "Base " + fixed$(1000*baseDelaySec,2) + " ms  |  Depth " + fixed$(100*effectiveDepthRatio,1) + "%  |  Rate " + fixed$(modulation_rate_Hz,2) + " Hz  |  Phase " + fixed$(phase_offset_degrees,0) + " deg"
    if wet = 0 or effectiveDepthRatio = 0 or modulation_rate_Hz = 0 or baseDelaySec = 0
        safetyStr$ = "bypass"
    elsif safety_peak = 0
        safetyStr$ = "off"
    elsif safetyApplied
        safetyStr$ = "limited to " + fixed$(safety_peak,2)
    else
        safetyStr$ = "no gain change"
    endif
    Text: 0.02, "left", 0.18, "half",
        ... "Dry/Wet " + fixed$(dry_wet_percent,0) + "%  |  " + string$(resultChannels) + " ch  |  " + fixed$(duration,2) + " s  |  Safety " + safetyStr$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Font size: 10
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final ===
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
