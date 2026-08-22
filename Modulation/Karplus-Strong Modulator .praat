# ============================================================
# Praat AudioTools - Karplus_Strong_Modulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Karplus-Strong-style continuously excited feedback resonator.
#   The selected Sound excites a one-delay feedback loop with the
#   classic two-sample averaging loss filter. The resonant frequency
#   can be modulated sinusoidally in semitones.
#
#   This is an audio effect, not a standalone plucked-string generator:
#   the source continues to excite the loop for the full Sound.
#   Sample rate, duration, start time, and all channels are preserved.
#
# Changelog v0.4:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# v0.3 changes:
#   - Corrects loop tuning for the half-sample phase delay introduced by
#     the two-sample averaging filter.
#   - Makes LFO phase independent of the Sound's absolute start time.
#   - Adds exact Mix=0 bypass and attenuation-only Safety_peak.
#   - Removes unconditional peak normalization.
#   - Removes the unnecessary full-size reference copy.
#   - Computes dynamic delay modulation once in a shared mono control Sound;
#     static modulation uses a constant-delay fast path.
#   - Allows Mod_rate=0 for a static resonator.
#   - Clamps feedback, mix, and modulation range to stable/Nyquist-safe
#     values while preserving the requested sign of modulation depth.
#   - Updates visualization to the AudioTools house text layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

originalSound = selected("Sound")
baseName$ = selected$("Sound")

form Karplus-Strong Modulator v0.4
    optionmenu Preset: 1
        option Custom (use settings below)
        option Deep Bass Pluck
        option Sci-Fi Siren
        option Metallic Chime
        option Warp Drive Engine

    comment --- Resonator ---
    positive KS_base_frequency_Hz: 220

    comment --- Frequency modulation ---
    real KS_mod_rate_Hz: 0.5
    real KS_mod_depth_semitones: 12

    comment --- Feedback ---
    real KS_decay: 0.95

    comment --- Mix / output ---
    real KS_mix: 0.5
    real Safety_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# ============================================================
# PRESETS
# ============================================================
presetName$ = "Custom"

if preset = 2
    presetName$ = "Deep_Bass_Pluck"
    kS_base_frequency_Hz = 80
    kS_mod_rate_Hz = 0.2
    kS_mod_depth_semitones = 1.0
    kS_decay = 0.85
    kS_mix = 0.6
elsif preset = 3
    presetName$ = "Sci-Fi_Siren"
    kS_base_frequency_Hz = 440
    kS_mod_rate_Hz = 0.3
    kS_mod_depth_semitones = 12
    kS_decay = 0.96
    kS_mix = 0.5
elsif preset = 4
    presetName$ = "Metallic_Chime"
    kS_base_frequency_Hz = 880
    kS_mod_rate_Hz = 6.0
    kS_mod_depth_semitones = 0.5
    kS_decay = 0.99
    kS_mix = 0.4
elsif preset = 5
    presetName$ = "Warp_Drive_Engine"
    kS_base_frequency_Hz = 150
    kS_mod_rate_Hz = 8.0
    kS_mod_depth_semitones = 24
    kS_decay = 0.92
    kS_mix = 0.8
endif

# ============================================================
# VALIDATION / SOURCE METADATA
# ============================================================
selectObject: originalSound
duration = Get total duration
sampleRate = Get sampling frequency
sampleCount = Get number of samples
numChannels = Get number of channels
originalStart = Get start time
dt = 1 / sampleRate
nyquistSafe = 0.49 * sampleRate

# Stable / meaningful ranges.
kS_mod_rate_Hz = max(0, kS_mod_rate_Hz)
kS_decay = min(0.9999, max(0, kS_decay))
kS_mix = min(1, max(0, kS_mix))
safety_peak = min(1, max(0, safety_peak))
kS_base_frequency_Hz = min(nyquistSafe, max(0.001, kS_base_frequency_Hz))

# Limit depth so the highest instantaneous resonance remains below 0.49 Fs.
maxDepthAbs = 12 * ln(nyquistSafe / kS_base_frequency_Hz) / ln(2)
maxDepthAbs = max(0, maxDepthAbs)
if kS_mod_depth_semitones < 0
    kS_mod_depth_semitones = -min(abs(kS_mod_depth_semitones), maxDepthAbs)
else
    kS_mod_depth_semitones = min(kS_mod_depth_semitones, maxDepthAbs)
endif

minTargetFreq = kS_base_frequency_Hz * 2^(-abs(kS_mod_depth_semitones) / 12)
maxTargetFreq = kS_base_frequency_Hz * 2^( abs(kS_mod_depth_semitones) / 12)
minTapDelayMs = (1 / maxTargetFreq - 0.5 * dt) * 1000
maxTapDelayMs = (1 / minTargetFreq - 0.5 * dt) * 1000

appendInfoLine: "=== Karplus-Strong Modulator v0.4 ==="
appendInfoLine: "Source: ", baseName$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sampleRate, 0), " Hz"
appendInfoLine: "Mode: continuously excited Karplus-Strong-style feedback resonator"
appendInfoLine: ""
appendInfoLine: "Base resonance: ", fixed$(kS_base_frequency_Hz, 3), " Hz"
appendInfoLine: "Mod rate: ", fixed$(kS_mod_rate_Hz, 3), " Hz"
appendInfoLine: "Mod depth: ", fixed$(kS_mod_depth_semitones, 3), " semitones"
appendInfoLine: "Target range: ", fixed$(minTargetFreq, 2), " - ", fixed$(maxTargetFreq, 2), " Hz"
appendInfoLine: "Decay / loop: ", fixed$(kS_decay, 4)
appendInfoLine: "Wet mix: ", fixed$(100*kS_mix, 1), "%"

# ============================================================
# PROCESSING
# ============================================================
# Exact dry bypass. Safety is deliberately not applied to a bypass.
if kS_mix <= 0
    selectObject: originalSound
    finalOutput = Copy: baseName$ + "_KS_" + presetName$
else
    # The output itself is the feedback delay memory. The original selected
    # Sound remains untouched and is the continuous excitation source.
    selectObject: originalSound
    finalOutput = Copy: baseName$ + "_KS_" + presetName$

    globalOriginal = originalSound
    globalDt = dt
    globalDecay = kS_decay

    # Two adjacent delayed samples implement the classic averaging loss
    # filter. Their average has an effective extra delay of about 0.5 sample,
    # so subtract 0.5*dt from the explicit tap delay for pitch tuning.
    #
    # Static modulation uses a constant-delay fast path. Dynamic modulation
    # computes the delay trajectory once in one mono control Sound and reuses
    # it for every output channel, instead of evaluating sin()/pow() twice for
    # every output sample and channel.
    if kS_mod_rate_Hz <= 0 or abs(kS_mod_depth_semitones) < 1e-15
        globalStaticDelay = 1/kS_base_frequency_Hz - 0.5*dt
        selectObject: finalOutput
        Formula: "object ['globalOriginal', row, col] + 'globalDecay' * (self (x-'globalStaticDelay') + self (x-'globalStaticDelay'-'globalDt'))/2"
    else
        selectObject: originalSound
        Extract one channel: 1
        delayControl = selected("Sound")
        globalStart = originalStart
        globalBase = kS_base_frequency_Hz
        globalRate = kS_mod_rate_Hz
        globalDepth = kS_mod_depth_semitones
        Formula: "1/('globalBase' * 2^('globalDepth' * sin(2*pi*'globalRate'*(x-'globalStart'))/12)) - 0.5*'globalDt'"

        globalDelayControl = delayControl
        selectObject: finalOutput
        Formula: "object ['globalOriginal', row, col] + 'globalDecay' * (self (x-object['globalDelayControl',1,col]) + self (x-object['globalDelayControl',1,col]-'globalDt'))/2"
        removeObject: delayControl
    endif

    # Linear dry/wet blend. The wet resonator naturally contains the direct
    # excitation plus feedback; therefore intermediate mix values scale only
    # the resonant contribution relative to the untouched source.
    if kS_mix < 1
        globalWet = kS_mix
        globalDry = 1 - globalWet
        Formula: "'globalWet' * self + 'globalDry' * object ['globalOriginal', row, col]"
    endif
endif

# Attenuation-only safety. Never boost quiet material.
selectObject: finalOutput
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if kS_mix > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
else
    appendInfoLine: "Safety: disabled"
endif
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
if draw_visualization
    pageHeight = 6.6
    if safety_peak > 0
        safeStr$ = fixed$(safety_peak, 2)
    else
        safeStr$ = "off"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 6.4
    Black
    Plain line

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Karplus-Strong Modulator v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", baseName$ + "  |  " + presetName$ + "  |  continuously excited feedback resonator"

    # ---- INPUT WAVEFORM ----
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: originalSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT WAVEFORM ----
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    selectObject: finalOutput
    Colour: "{0.25, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- TARGET RESONANCE TRAJECTORY ----
    modDisplayDur = min(3, duration)
    freqMargin = max(1, 0.1 * (maxTargetFreq - minTargetFreq))
    Select outer viewport: 0, 8, 2.40, 3.75
    Select inner viewport: 0.55, 7.75, 2.58, 3.63
    Axes: 0, modDisplayDur, max(0, minTargetFreq-freqMargin), maxTargetFreq+freqMargin
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, modDisplayDur, max(0, minTargetFreq-freqMargin), maxTargetFreq+freqMargin
    Colour: "{0.78, 0.78, 0.78}"
    Dotted line
    Draw line: 0, kS_base_frequency_Hz, modDisplayDur, kS_base_frequency_Hz
    Plain line
    Colour: "{0.48, 0.36, 0.72}"
    Line width: 1.5
    nModPoints = 300
    for mp from 2 to nModPoints
        t1 = (mp - 2) / (nModPoints - 1) * modDisplayDur
        t2 = (mp - 1) / (nModPoints - 1) * modDisplayDur
        f1 = kS_base_frequency_Hz * 2^(kS_mod_depth_semitones * sin(2*pi*kS_mod_rate_Hz*t1) / 12)
        f2 = kS_base_frequency_Hz * 2^(kS_mod_depth_semitones * sin(2*pi*kS_mod_rate_Hz*t2) / 12)
        Draw line: t1, f1, t2, f2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Target resonance"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"

    # ---- TUNED DELAY TRAJECTORY ----
    delayMargin = max(0.05, 0.1 * (maxTapDelayMs - minTapDelayMs))
    Select outer viewport: 0, 8, 3.85, 5.20
    Select inner viewport: 0.55, 7.75, 4.03, 5.08
    Axes: 0, modDisplayDur, max(0, minTapDelayMs-delayMargin), maxTapDelayMs+delayMargin
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, modDisplayDur, max(0, minTapDelayMs-delayMargin), maxTapDelayMs+delayMargin
    Colour: "{0.48, 0.36, 0.72}"
    Line width: 1.5
    for mp from 2 to nModPoints
        t1 = (mp - 2) / (nModPoints - 1) * modDisplayDur
        t2 = (mp - 1) / (nModPoints - 1) * modDisplayDur
        f1 = kS_base_frequency_Hz * 2^(kS_mod_depth_semitones * sin(2*pi*kS_mod_rate_Hz*t1) / 12)
        f2 = kS_base_frequency_Hz * 2^(kS_mod_depth_semitones * sin(2*pi*kS_mod_rate_Hz*t2) / 12)
        d1 = (1/f1 - 0.5*dt) * 1000
        d2 = (1/f2 - 0.5*dt) * 1000
        Draw line: t1, d1, t2, d2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Tuned feedback delay"
    Font size: 6
    Text left: "yes", "ms"
    Text bottom: "yes", "Time (s)"

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, 5.30, 6.15
    Select inner viewport: 0.55, 7.75, 5.37, 6.08
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half", "Base: " + fixed$(kS_base_frequency_Hz, 1) + " Hz  |  rate: " + fixed$(kS_mod_rate_Hz, 2) + " Hz  |  depth: " + fixed$(kS_mod_depth_semitones, 2) + " st  |  decay/loop: " + fixed$(kS_decay, 3) + "  |  wet: " + fixed$(100*kS_mix, 0) + "%"
    Text: 0.02, "left", 0.20, "half", "Range: " + fixed$(minTargetFreq, 1) + "-" + fixed$(maxTargetFreq, 1) + " Hz  |  safety: " + safeStr$ + "  |  " + fixed$(duration, 2) + " s / " + fixed$(sampleRate, 0) + " Hz / " + string$(numChannels) + " ch"

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

selectObject: finalOutput
if play_result
    Play
endif

selectObject: finalOutput
