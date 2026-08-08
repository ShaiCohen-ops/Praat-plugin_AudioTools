# ============================================================
# Praat AudioTools - Golden-Chaos Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Deterministic multi-rate delay vibrato. A primary sinusoidal delay
#   modulation is phase-modulated by two additional low-frequency
#   oscillators. Presets based on pi, e and phi can be periodic or
#   quasi-periodic depending on their frequency ratios.
#
#   This is not a chaotic dynamical system. "Golden-Chaos" is retained
#   as the artistic effect name.
#
# Changelog v0.3:
#   - Corrected "never repeats / irrational ratios" claims.
#   - Mathematical presets use Praat's pi, exp(1), and exact phi.
#   - Local-time modulation: result no longer depends on Sound xmin.
#   - Fractional-delay linear interpolation replaces rounded sample reads.
#   - Added exact Dry/Wet control and attenuation-only Safety_peak.
#   - Preserves sample rate, start time, duration, and all channels.
#   - Updated visualization to the AudioTools text/layout standard.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency
numChannels = Get number of channels
sourceStart = Get start time
sourceEnd = Get end time

# === Form ===
form Golden-Chaos Vibrato
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Golden Shimmer (phi quasi-periodic)
        option Euler Wobble (e quasi-periodic)
        option Pi Cycle (periodic)
        option Mathematical Quasiperiodic (pi/e/phi)
        option Subtle Irregularity
        option Deep Math Texture

    comment === Delay Parameters ===
    positive Base_delay_ms 6.0
    real Modulation_depth 0.14
    comment (0 = fixed delay; values are clamped to 0..0.95)

    comment === Modulation Rates ===
    positive Rate1_hz 3.1415926536
    positive Rate2_hz 2.7182818285
    positive Rate3_hz 1.6180339887

    comment === Phase-Modulation Amounts ===
    real Rate2_mix 0.6
    real Rate3_mix 0.4

    comment === Output ===
    real Dry_wet_percent 100
    comment (0 = exact dry bypass; 100 = full effect)
    real Safety_peak 0.99
    comment (0 disables; otherwise attenuates only)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Constants ===
phi = (1 + sqrt(5)) / 2
euler = exp(1)

# === Apply Presets ===
if preset = 2
    base_delay_ms = 5.0
    modulation_depth = 0.08
    rate1_hz = phi
    rate2_hz = 2 * phi
    rate3_hz = 1 / phi
    rate2_mix = 0.3
    rate3_mix = 0.5
    presetName$ = "Golden Shimmer"
    periodicity$ = "quasi-periodic"
elsif preset = 3
    base_delay_ms = 7.0
    modulation_depth = 0.15
    rate1_hz = euler
    rate2_hz = 2 * euler
    rate3_hz = 1.0
    rate2_mix = 0.8
    rate3_mix = 0.2
    presetName$ = "Euler Wobble"
    periodicity$ = "quasi-periodic"
elsif preset = 4
    base_delay_ms = 6.0
    modulation_depth = 0.12
    rate1_hz = pi
    rate2_hz = 2 * pi
    rate3_hz = pi / 2
    rate2_mix = 0.2
    rate3_mix = 0.1
    presetName$ = "Pi Cycle"
    periodicity$ = "periodic"
elsif preset = 5
    base_delay_ms = 8.0
    modulation_depth = 0.20
    rate1_hz = pi
    rate2_hz = euler
    rate3_hz = phi
    rate2_mix = 1.0
    rate3_mix = 1.0
    presetName$ = "Mathematical Quasiperiodic"
    periodicity$ = "quasi-periodic"
elsif preset = 6
    base_delay_ms = 4.0
    modulation_depth = 0.05
    rate1_hz = pi
    rate2_hz = euler
    rate3_hz = phi
    rate2_mix = 0.5
    rate3_mix = 0.5
    presetName$ = "Subtle Irregularity"
    periodicity$ = "quasi-periodic"
elsif preset = 7
    base_delay_ms = 12.0
    modulation_depth = 0.25
    rate1_hz = pi / 10
    rate2_hz = euler / 10
    rate3_hz = phi / 10
    rate2_mix = 0.7
    rate3_mix = 0.7
    presetName$ = "Deep Math Texture"
    periodicity$ = "quasi-periodic"
else
    presetName$ = "Custom"
    periodicity$ = "user-defined"
endif

# === Defensive parameter limits ===
modulation_depth = max(0, min(0.95, modulation_depth))
rate2_mix = max(-4, min(4, rate2_mix))
rate3_mix = max(-4, min(4, rate3_mix))
dry_wet_percent = max(0, min(100, dry_wet_percent))
safety_peak = max(0, min(1, safety_peak))

# Prevent unreasonable delay memory/time offsets.
maxBaseMs = max(0.1, duration * 1000 * 0.45 / (1 + modulation_depth))
if base_delay_ms > maxBaseMs
    base_delay_ms = maxBaseMs
endif

baseSamples = base_delay_ms * sampling / 1000
wetAmt = dry_wet_percent / 100
dryAmt = 1 - wetAmt

# === Info ===
writeInfoLine: "=== Golden-Chaos Vibrato v0.3 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$, " | ", periodicity$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", round(sampling), " Hz"
appendInfoLine: ""
appendInfoLine: "Base delay: ", fixed$(base_delay_ms, 3), " ms"
appendInfoLine: "Delay modulation depth: ", fixed$(modulation_depth, 3)
appendInfoLine: "Delay range: ", fixed$(base_delay_ms * (1 - modulation_depth), 3), " - ", fixed$(base_delay_ms * (1 + modulation_depth), 3), " ms"
appendInfoLine: "Rates: ", fixed$(rate1_hz, 6), ", ", fixed$(rate2_hz, 6), ", ", fixed$(rate3_hz, 6), " Hz"
appendInfoLine: "Phase-mod amounts: ", fixed$(rate2_mix, 3), ", ", fixed$(rate3_mix, 3)
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
appendInfoLine: ""

# === Process ===
selectObject: original
result = Copy: original_name$ + "_golden_chaos"

if dry_wet_percent = 0
    # Exact bypass: do not apply safety to a dry-only result.
    appendInfoLine: "Dry bypass: exact copy."
else
    appendInfoLine: "Applying fractional-delay vibrato..."

    # Continuous fractional-delay read with linear interpolation.
    # Delay(t) = base * [1 + depth * sin(primary phase + nested phase modulation)].
    # Local time (x - sourceStart) makes the modulation independent of Sound xmin.
    startStr$ = fixed$(sourceStart, 12)
    baseSamplesStr$ = fixed$(baseSamples, 12)
    depthStr$ = fixed$(modulation_depth, 12)
    r1Str$ = fixed$(rate1_hz, 12)
    r2Str$ = fixed$(rate2_hz, 12)
    r3Str$ = fixed$(rate3_hz, 12)
    m2Str$ = fixed$(rate2_mix, 12)
    m3Str$ = fixed$(rate3_mix, 12)

    localTime$ = "(x-" + startStr$ + ")"
    phase$ = "(2*pi*" + r1Str$ + "*" + localTime$ + "+" + m2Str$ + "*sin(2*pi*" + r2Str$ + "*" + localTime$ + ")+" + m3Str$ + "*sin(2*pi*" + r3Str$ + "*" + localTime$ + "))"
    delay$ = "(" + baseSamplesStr$ + "*(1+" + depthStr$ + "*sin(" + phase$ + ")))"
    srcIndex$ = "(col-" + delay$ + ")"
    i0$ = "floor(" + srcIndex$ + ")"
    frac$ = "(" + srcIndex$ + "-" + i0$ + ")"
    idx0$ = "max(1,min(ncol," + i0$ + "))"
    idx1$ = "max(1,min(ncol," + i0$ + "+1))"

    selectObject: result
    for ch from 1 to numChannels
        chStr$ = string$(ch)
        idStr$ = string$(original)
        interp$ = "(1-" + frac$ + ")*object[" + idStr$ + "," + chStr$ + "," + idx0$ + "]+" + frac$ + "*object[" + idStr$ + "," + chStr$ + "," + idx1$ + "]"
        Formula (part): sourceStart, sourceEnd, ch, ch, interp$
    endfor

    if dry_wet_percent < 100
        wetStr$ = fixed$(wetAmt, 12)
        dryStr$ = fixed$(dryAmt, 12)
        selectObject: result
        for ch from 1 to numChannels
            mix$ = "self*" + wetStr$ + "+object[" + string$(original) + "," + string$(ch) + ",col]*" + dryStr$
            Formula (part): sourceStart, sourceEnd, ch, ch, mix$
        endfor
    endif

    # Attenuation-only safety ceiling.
    if safety_peak > 0
        selectObject: result
        peakBeforeSafety = Get absolute extremum: 0, 0, "None"
        if peakBeforeSafety > safety_peak
            safetyGain = safety_peak / peakBeforeSafety
            Multiply: safetyGain
            appendInfoLine: "Safety attenuation: x", fixed$(safetyGain, 6)
        else
            appendInfoLine: "Safety attenuation: none"
        endif
    else
        appendInfoLine: "Safety: disabled"
    endif
endif

selectObject: result
Rename: original_name$ + "_golden_" + replace$(presetName$, " ", "_", 0)

# === Visualization ===
if draw_visualization
    # Display copies only; DSP objects remain untouched.
    selectObject: original
    if numChannels > 1
        origDisplay = Convert to mono
    else
        origDisplay = Copy: "origDisplay"
    endif

    selectObject: result
    if numChannels > 1
        resultDisplay = Convert to mono
    else
        resultDisplay = Copy: "resultDisplay"
    endif

    Erase all

    # --- Title ---
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.60, "half", "##Golden-Chaos Vibrato##"

    # --- Metadata subtitle ---
    Select outer viewport: 0, 8, 0.36, 0.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35,0.35,0.52}"
    Text: 0.5, "centre", 0.55, "half", original_name$ + " | " + presetName$ + " | " + periodicity$

    # --- Input waveform ---
    Select outer viewport: 0, 8, 0.65, 1.45
    Select inner viewport: 0.65, 7.65, 0.75, 1.35
    selectObject: origDisplay
    Colour: "{0.55,0.55,0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # --- Output waveform ---
    Select outer viewport: 0, 8, 1.50, 2.30
    Select inner viewport: 0.65, 7.65, 1.60, 2.20
    selectObject: resultDisplay
    Colour: "{0.22,0.46,0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # --- Delay trajectory ---
    Select outer viewport: 0, 8, 2.45, 3.65
    Select inner viewport: 0.65, 7.65, 2.58, 3.53
    modDisplayDur = min(3, duration)
    minDelay = base_delay_ms * (1 - modulation_depth)
    maxDelay = base_delay_ms * (1 + modulation_depth)
    marginDelay = max(0.01, (maxDelay - minDelay) * 0.12)
    Axes: 0, modDisplayDur, minDelay - marginDelay, maxDelay + marginDelay
    Paint rectangle: "{0.97,0.97,0.97}", 0, modDisplayDur, minDelay - marginDelay, maxDelay + marginDelay

    Colour: "{0.82,0.82,0.82}"
    Dotted line
    Draw line: 0, base_delay_ms, modDisplayDur, base_delay_ms
    Solid line

    nModPoints = 400
    Colour: "{0.50,0.34,0.74}"
    Line width: 1.5
    prevT = 0
    prevPhase = rate2_mix * sin(0) + rate3_mix * sin(0)
    prevDelay = base_delay_ms * (1 + modulation_depth * sin(prevPhase))
    for mp from 2 to nModPoints
        nowT = (mp - 1) / (nModPoints - 1) * modDisplayDur
        nowPhase = 2*pi*rate1_hz*nowT + rate2_mix*sin(2*pi*rate2_hz*nowT) + rate3_mix*sin(2*pi*rate3_hz*nowT)
        nowDelay = base_delay_ms * (1 + modulation_depth * sin(nowPhase))
        Draw line: prevT, prevDelay, nowT, nowDelay
        prevT = nowT
        prevDelay = nowDelay
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Time (s)"

    # --- Summary ---
    Select outer viewport: 0, 8, 3.82, 4.60
    Select inner viewport: 0.55, 7.75, 3.90, 4.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30,0.30,0.30}"
    Text: 0.02, "left", 0.48, "half", "Delay: " + fixed$(base_delay_ms, 2) + " ms | Depth: " + fixed$(modulation_depth, 3) + " | Wet: " + fixed$(dry_wet_percent, 0) + "% | Safety: " + fixed$(safety_peak, 2)
    Text: 0.02, "left", 0.20, "half", "Rates: " + fixed$(rate1_hz, 3) + " / " + fixed$(rate2_hz, 3) + " / " + fixed$(rate3_hz, 3) + " Hz | PM: " + fixed$(rate2_mix, 2) + " / " + fixed$(rate3_mix, 2) + " | " + string$(numChannels) + " ch"

    removeObject: origDisplay, resultDisplay

    Colour: "Black"
    Font size: 10
    Line width: 1
endif

# === Final Info ===
selectObject: result
peakOut = Get absolute extremum: 0, 0, "None"
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output peak: ", fixed$(peakOut, 6)

if play_result
    Play
endif

selectObject: result
