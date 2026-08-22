# ============================================================
# Praat AudioTools - Dual_Mode_Tremolo_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dual-mode tremolo with two distinct amplitude-modulation styles:
#   Adaptive mode varies tremolo depth from a smoothed RMS-like signal
#   envelope; Strong mode uses a full-depth rectified-sine pulse.
#
# Changelog v0.4:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.3:
#   - Adaptive mode now follows a smoothed amplitude envelope instead of
#     instantaneous abs(sample), avoiding waveform-dependent distortion.
#   - Strong mode rate now equals the audible pulse rate (|sin| no longer
#     doubles the requested modulation rate).
#   - LFO phase is referenced to local sound time, so shifted Sounds produce
#     the same modulation trajectory.
#   - Removed unconditional peak normalization; added Dry/Wet and attenuation-
#     only Safety_peak.
#   - Preserves sample rate, start time, duration, and all channels.
#   - Streamlined processing and updated visualization to AudioTools house style.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound$ = selected$("Sound")

selectObject: original
duration = Get total duration
fs = Get sampling frequency
numChannels = Get number of channels
startTime = Get start time
nyquist = fs / 2

# === Form ===
form Dual-Mode Tremolo Generator v0.4
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Classic Tremolo
        option Subtle Shimmer
        option Helicopter Pulse
        option Slow Pulse
        option Fast Flutter
        option Dynamic Swell

    comment === Mode ===
    choice Mode 1
        button Adaptive (envelope-following depth)
        button Strong (rectified-sine pulse)

    comment === Rate ===
    positive Modulation_rate_hz 5

    comment === Adaptive Mode Settings ===
    real Max_modulation_depth 0.7
    real Signal_sensitivity 0.5
    real Sensitivity_offset 0.5
    positive Envelope_smoothing_ms 20
    comment (depth control = offset + sensitivity * smoothed RMS amplitude)

    comment === Mix / Output ===
    real Wet_dry_percent 100
    real Safety_peak 0.99
    comment (Safety_peak 0 disables; otherwise attenuation only)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    mode = 1
    modulation_rate_hz = 6
    max_modulation_depth = 0.5
    signal_sensitivity = 0.3
    sensitivity_offset = 0.6
    envelope_smoothing_ms = 20
    presetName$ = "Classic Tremolo"
elsif preset = 3
    mode = 1
    modulation_rate_hz = 8
    max_modulation_depth = 0.25
    signal_sensitivity = 0.2
    sensitivity_offset = 0.7
    envelope_smoothing_ms = 25
    presetName$ = "Subtle Shimmer"
elsif preset = 4
    mode = 2
    modulation_rate_hz = 12
    presetName$ = "Helicopter Pulse"
elsif preset = 5
    mode = 2
    modulation_rate_hz = 2
    presetName$ = "Slow Pulse"
elsif preset = 6
    mode = 1
    modulation_rate_hz = 15
    max_modulation_depth = 0.6
    signal_sensitivity = 0.4
    sensitivity_offset = 0.5
    envelope_smoothing_ms = 15
    presetName$ = "Fast Flutter"
elsif preset = 7
    mode = 1
    modulation_rate_hz = 3
    max_modulation_depth = 0.8
    signal_sensitivity = 0.7
    sensitivity_offset = 0.3
    envelope_smoothing_ms = 35
    presetName$ = "Dynamic Swell"
else
    presetName$ = "Custom"
endif

if mode = 1
    modeName$ = "Adaptive"
else
    modeName$ = "Strong"
endif

# === Validate / Clamp ===
max_modulation_depth = min(1, max(0, max_modulation_depth))
signal_sensitivity = max(0, signal_sensitivity)
sensitivity_offset = max(0, sensitivity_offset)
wet_dry_percent = min(100, max(0, wet_dry_percent))
safety_peak = min(1, max(0, safety_peak))
wetAmt = wet_dry_percent / 100
dryAmt = 1 - wetAmt

writeInfoLine: "=== Dual-Mode Tremolo Generator v0.4 ==="
appendInfoLine: "Source: ", sound$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Rate: ", fixed$(modulation_rate_hz, 2), " Hz"
if mode = 1
    appendInfoLine: "Max depth: ", fixed$(max_modulation_depth, 3)
    appendInfoLine: "Sensitivity / offset: ", fixed$(signal_sensitivity, 3), " / ", fixed$(sensitivity_offset, 3)
    appendInfoLine: "Envelope smoothing: ", fixed$(envelope_smoothing_ms, 1), " ms"
else
    appendInfoLine: "Strong pulse: full-depth rectified sine"
endif
appendInfoLine: "Dry/Wet: ", fixed$(wet_dry_percent, 1), "%"
appendInfoLine: ""

# === Exact dry bypass ===
if wetAmt = 0
    selectObject: original
    result = Copy: sound$ + "_tremolo_" + presetName$
    appendInfoLine: "Dry bypass: exact copy."
else
    selectObject: original
    result = Copy: sound$ + "_tremolo_work"

    startStr$ = fixed$(startTime, 12)
    rateStr$ = fixed$(modulation_rate_hz, 12)

    if mode = 1
        appendInfoLine: "Applying adaptive envelope-following tremolo..."

        # Build an RMS-like multichannel-safe envelope:
        # square each channel -> average power across channels -> zero-phase
        # low-pass -> sqrt. This avoids anti-phase cancellation and avoids
        # instantaneous waveform-dependent depth modulation.
        selectObject: original
        powerSound = Copy: "tremolo_power"
        Formula: "self^2"
        if numChannels > 1
            selectObject: powerSound
            powerMono = Convert to mono
            removeObject: powerSound
        else
            powerMono = powerSound
        endif

        tau = envelope_smoothing_ms / 1000
        envCutoff = 1 / (2 * pi * tau)
        envCutoff = min(envCutoff, nyquist * 0.20)
        envCutoff = max(envCutoff, 1)
        envSmoothHz = min(envCutoff, max(1, nyquist * 0.02))

        selectObject: powerMono
        envFiltered = Filter (pass Hann band): 0, envCutoff, envSmoothHz
        removeObject: powerMono
        selectObject: envFiltered
        Formula: "sqrt(max(self, 0))"
        Rename: "tremolo_env"

        depthStr$ = fixed$(max_modulation_depth, 12)
        sensStr$ = fixed$(signal_sensitivity, 12)
        offsetStr$ = fixed$(sensitivity_offset, 12)

        selectObject: result
        Formula: "self * (1 - " + depthStr$ +
        ... " * min(1, max(0, " + offsetStr$ + " + " + sensStr$ +
        ... " * object[" + string$(envFiltered) + ", 1, col]))" +
        ... " * (1 + sin(2*pi*" + rateStr$ + "*(x-" + startStr$ + ")))/2)"

        removeObject: envFiltered
    else
        appendInfoLine: "Applying strong rectified-sine pulse..."
        # abs(sin(pi*f*t)) has an audible pulse rate of f Hz.
        selectObject: result
        Formula: "self * abs(sin(pi*" + rateStr$ + "*(x-" + startStr$ + ")))"
    endif

    # Linear dry/wet mix, channel by channel.
    if wetAmt < 1
        wetStr$ = fixed$(wetAmt, 12)
        dryStr$ = fixed$(dryAmt, 12)
        selectObject: result
        Formula: "self * " + wetStr$ + " + object[" + string$(original) + ", row, col] * " + dryStr$
    endif

    selectObject: result
    Rename: sound$ + "_tremolo_" + presetName$

    # Safety ceiling: attenuation only, never normalization/boost.
    if safety_peak > 0
        currentPeak = Get absolute extremum: 0, 0, "None"
        if currentPeak > safety_peak
            safetyFactor = safety_peak / currentPeak
            Multiply: safetyFactor
            appendInfoLine: "Safety attenuation: x", fixed$(safetyFactor, 6)
        else
            appendInfoLine: "Safety attenuation: none"
        endif
    else
        appendInfoLine: "Safety attenuation: disabled"
    endif
endif

# === Visualization ===
if draw_visualization
    pageHeight = 4.9
    # Display mono copies only; DSP output itself remains multichannel.
    selectObject: original
    if numChannels > 1
        visInput = Convert to mono
    else
        visInput = Copy: "visInput"
    endif

    selectObject: result
    if numChannels > 1
        visOutput = Convert to mono
    else
        visOutput = Copy: "visOutput"
    endif

    Erase all

    # Title
    Select outer viewport: 0, 8, 0.05, 0.40
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "##Dual-Mode Tremolo Generator v0.4##"

    # Metadata subtitle
    Select outer viewport: 0, 8, 0.40, 0.62
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35,0.35,0.52}"
    Text: 0.5, "centre", 0.52, "half", sound$ + " | " + presetName$ + " | " + modeName$

    # Input waveform
    Select outer viewport: 0, 8, 0.70, 1.55
    Select inner viewport: 0.65, 7.60, 0.80, 1.45
    selectObject: visInput
    Colour: "{0.55,0.55,0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.65, 2.50
    Select inner viewport: 0.65, 7.60, 1.75, 2.40
    selectObject: visOutput
    Colour: "{0.22,0.45,0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Modulation shape
    Select outer viewport: 0, 8, 2.65, 3.70
    Select inner viewport: 0.65, 7.60, 2.78, 3.58
    lfoDisplayDur = min(3 / modulation_rate_hz, duration)
    Axes: 0, lfoDisplayDur, -0.05, 1.05
    Paint rectangle: "{0.97,0.97,0.97}", 0, lfoDisplayDur, -0.05, 1.05

    Colour: "{0.50,0.35,0.74}"
    Line width: 2
    nLfoPoints = 240
    prevT = 0
    if mode = 1
        prevY = (1 + sin(0)) / 2
    else
        prevY = abs(sin(0))
    endif
    for lp from 2 to nLfoPoints
        plotT = (lp - 1) / (nLfoPoints - 1) * lfoDisplayDur
        if mode = 1
            plotY = (1 + sin(2*pi*modulation_rate_hz*plotT)) / 2
        else
            plotY = abs(sin(pi*modulation_rate_hz*plotT))
        endif
        Draw line: prevT, prevY, plotT, plotY
        prevT = plotT
        prevY = plotY
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "LFO"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 3.88, 4.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select inner viewport: 0.28, 7.72, 3.96, 4.64
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.01, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.01, "left", 0.52, "half", "Rate: " + fixed$(modulation_rate_hz, 2) + " Hz | Dry/Wet: " + fixed$(wet_dry_percent, 0) + "% | Safety: " + fixed$(safety_peak, 2) + " | Channels: " + string$(numChannels)
    if mode = 1
        Text: 0.01, "left", 0.22, "half", "Max depth: " + fixed$(max_modulation_depth, 2) + " | Sensitivity: " + fixed$(signal_sensitivity, 2) + " | Offset: " + fixed$(sensitivity_offset, 2) + " | Smoothing: " + fixed$(envelope_smoothing_ms, 1) + " ms"
    else
        Text: 0.01, "left", 0.22, "half", "Strong mode: full-depth rectified-sine pulse | Audible pulse rate = requested rate"
    endif

    removeObject: visInput, visOutput

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

# === Final Info ===
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
