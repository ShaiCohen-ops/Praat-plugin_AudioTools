# ============================================================
# Praat AudioTools - Stereo_Flanger.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Flanger - causal fractional-delay flanger with a true
#   recursive feedback loop. A sinusoidal LFO sweeps the delay time;
#   odd channels use the left trajectory and even channels use the
#   phase-offset right trajectory. Mono input becomes stereo while the
#   effect is active. Existing multichannel layouts are preserved.
#
#   The feedback loop is:
#       state(t) = input(t) + feedback * state(t - delay(t))
#   and the output is:
#       dry * input(t) + wet * state(t - delay(t))
#
#   Delay interpolation is linear between adjacent samples. The effective
#   minimum delay is clamped to one sample so the recursive loop remains
#   causal. "Through-Zero" remains a simulated near-zero-delay preset;
#   true through-zero flanging would require delaying the dry reference too.
#
# v0.3 changes:
#   - Replaces the first-reflection approximation with true recursive feedback.
#   - Replaces rounded sample delays with continuous fractional interpolation.
#   - Uses local Sound time for shift-invariant LFO phase.
#   - Preserves arbitrary multichannel input; mono becomes stereo only when wet.
#   - Adds exact 0% dry bypass and attenuation-only Safety_peak.
#   - Removes forced peak normalization.
#   - Clamps |feedback| below unity and keeps delay strictly causal.
#   - Replaces the old approximate feedback plot with the actual static
#     transfer magnitude at the base delay.
#   - Updates visualization to the AudioTools house layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

form Stereo Flanger
    optionmenu Preset: 1
        option Custom (use settings below)
        option Classic 80s Flanger
        option Slow Jet (High Feedback)
        option Liquid Metal (Negative FB)
        option Deep Throat (Long Delay)
        option Through-Zero (Simulated)
        option Subtle Stereo Widener

    comment --- LFO / Delay ---
    real Rate_Hz: 0.3
    real Depth_ms: 2.0
    real Base_delay_ms: 3.0

    comment --- Stereo image ---
    real Stereo_phase_offset_deg: 180
    comment 180 = counter-sweep; odd channels use L, even channels use R

    comment --- Mix / Feedback ---
    real Feedback: 0.7
    comment True recursive feedback; internally clamped to -0.98..0.98
    real Dry_wet_percent: 50

    comment --- Output ---
    real Safety_peak: 0.99
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

# ============================================================
# PRESET OVERRIDES
# ============================================================
if preset = 2
    rate_Hz = 0.5
    depth_ms = 1.5
    base_delay_ms = 2.0
    stereo_phase_offset_deg = 90
    feedback = 0.6
    dry_wet_percent = 50
    presetName$ = "Classic80s"
elsif preset = 3
    rate_Hz = 0.15
    depth_ms = 2.5
    base_delay_ms = 3.0
    stereo_phase_offset_deg = 180
    feedback = 0.85
    dry_wet_percent = 50
    presetName$ = "SlowJet"
elsif preset = 4
    rate_Hz = 3.0
    depth_ms = 0.5
    base_delay_ms = 1.0
    stereo_phase_offset_deg = 180
    feedback = -0.7
    dry_wet_percent = 60
    presetName$ = "LiquidMetal"
elsif preset = 5
    rate_Hz = 0.4
    depth_ms = 4.0
    base_delay_ms = 8.0
    stereo_phase_offset_deg = 45
    feedback = 0.5
    dry_wet_percent = 50
    presetName$ = "DeepThroat"
elsif preset = 6
    rate_Hz = 0.2
    depth_ms = 0.9
    base_delay_ms = 1.0
    stereo_phase_offset_deg = 180
    feedback = 0.4
    dry_wet_percent = 70
    presetName$ = "ThroughZero"
elsif preset = 7
    rate_Hz = 0.1
    depth_ms = 1.0
    base_delay_ms = 5.0
    stereo_phase_offset_deg = 180
    feedback = 0.1
    dry_wet_percent = 40
    presetName$ = "Widener"
else
    presetName$ = "Custom"
endif

# ============================================================
# SOURCE / VALIDATION
# ============================================================
selectObject: original
duration = Get total duration
sr = Get sampling frequency
channels = Get number of channels
sourceStart = Get start time
sourceEnd = Get end time
inputPeak = Get absolute extremum: 0, 0, "None"

rate_Hz = max(0, rate_Hz)
depth_ms = max(0, depth_ms)
base_delay_ms = max(0, base_delay_ms)
stereo_phase_offset_deg = stereo_phase_offset_deg mod 360
if stereo_phase_offset_deg < 0
    stereo_phase_offset_deg = stereo_phase_offset_deg + 360
endif
feedback = min(0.98, max(-0.98, feedback))
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))

oneSampleMs = 1000 / sr
effectiveBaseMs = max(oneSampleMs, base_delay_ms)
maxDepthMs = max(0, effectiveBaseMs - oneSampleMs)
effectiveDepthMs = min(depth_ms, maxDepthMs)
minDelayMs = effectiveBaseMs - effectiveDepthMs
maxDelayMs = effectiveBaseMs + effectiveDepthMs
phase_rad = stereo_phase_offset_deg * pi / 180

baseSamples = effectiveBaseMs * sr / 1000
depthSamples = effectiveDepthMs * sr / 1000

if feedback >= 0
    fbType$ = "positive"
else
    fbType$ = "negative"
endif

appendInfoLine: "=== Stereo Flanger v0.3 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", channels, " | Sample rate: ", fixed$(sr, 0), " Hz"
appendInfoLine: "Rate: ", fixed$(rate_Hz, 3), " Hz"
appendInfoLine: "Delay: ", fixed$(effectiveBaseMs, 3), " +/- ", fixed$(effectiveDepthMs, 3), " ms"
appendInfoLine: "Range: ", fixed$(minDelayMs, 3), " - ", fixed$(maxDelayMs, 3), " ms"
appendInfoLine: "Stereo phase: ", fixed$(stereo_phase_offset_deg, 1), " deg"
appendInfoLine: "Feedback: ", fixed$(feedback, 3), " (", fbType$, ")"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
if abs(effectiveBaseMs-base_delay_ms) > 1e-12 or abs(effectiveDepthMs-depth_ms) > 1e-12
    appendInfoLine: "Causal delay clamp applied (minimum = one sample = ", fixed$(oneSampleMs, 4), " ms)"
endif

# ============================================================
# PROCESSING
# ============================================================
if dry_wet_percent <= 0
    selectObject: original
    result = Copy: name$ + "_flanger_" + presetName$
else
    # Mono becomes stereo for an actual stereo flanger. Existing multichannel
    # layouts are kept. Odd channels use the L trajectory; even channels the R.
    selectObject: original
    if channels = 1
        Convert to stereo
        source = selected("Sound")
        processingChannels = 2
    else
        source = Copy: "flanger_source"
        processingChannels = channels
    endif

    # Read-position control. Each sample stores the fractional source/state
    # sample index to read for that output sample.
    selectObject: source
    readPos = Copy: "flanger_read_position"
    globalStart = sourceStart
    globalRate = rate_Hz
    globalBaseSamples = baseSamples
    globalDepthSamples = depthSamples
    globalPhase = phase_rad
    Formula: "col - ('globalBaseSamples' + 'globalDepthSamples' * sin(2*pi*'globalRate'*(x-'globalStart') + if row mod 2 = 1 then 0 else 'globalPhase' fi))"

    # Recursive state:
    #   state[n] = input[n] + fb * state[n-delay[n]]
    selectObject: source
    state = Copy: "flanger_feedback_state"
    globalReadPos = readPos
    globalFeedback = feedback

    Formula: "self + 'globalFeedback' * (if object ['globalReadPos',row,col] < 1 then 0 else if object ['globalReadPos',row,col] >= col-1 then self[row,col-1] else (1-(object ['globalReadPos',row,col]-floor(object ['globalReadPos',row,col]))) * self[row,floor(object ['globalReadPos',row,col])] + (object ['globalReadPos',row,col]-floor(object ['globalReadPos',row,col])) * self[row,floor(object ['globalReadPos',row,col])+1] fi fi)"

    # Delayed feedback-state branch mixed with the untouched source.
    selectObject: source
    result = Copy: name$ + "_flanger_" + presetName$
    globalState = state
    globalWet = dry_wet_percent / 100
    globalDry = 1 - globalWet
    Formula: "'globalDry' * self + 'globalWet' * (if object ['globalReadPos',row,col] < 1 then 0 else if object ['globalReadPos',row,col] >= col-1 then object ['globalState',row,col-1] else (1-(object ['globalReadPos',row,col]-floor(object ['globalReadPos',row,col]))) * object ['globalState',row,floor(object ['globalReadPos',row,col])] + (object ['globalReadPos',row,col]-floor(object ['globalReadPos',row,col])) * object ['globalState',row,floor(object ['globalReadPos',row,col])+1] fi fi)"

    removeObject: state, readPos, source
endif

# Attenuation-only safety. Exact dry bypass is never altered.
selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if dry_wet_percent > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"
outputChannels = Get number of channels

appendInfoLine: "Output channels: ", outputChannels
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
else
    appendInfoLine: "Safety: disabled"
endif

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
if draw_visualization
    @drawViz
endif

selectObject: result
if play_result
    Play
endif

appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

procedure drawViz
    if channels = 1 and dry_wet_percent > 0
        .routing$ = "mono -> stereo"
    elsif channels > 1
        .routing$ = "odd=L | even=R"
    else
        .routing$ = "bypass"
    endif

    if safety_peak > 0
        .safe$ = fixed$(safety_peak, 2)
    else
        .safe$ = "off"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Colour: "Black"
    Font size: 10
    Line width: 1

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Stereo Flanger##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half", name$ + "  |  " + presetName$ + "  |  " + .routing$

    # ---- INPUT ----
    Select outer viewport: 0, 4.2, 0.75, 2.20
    Select inner viewport: 0.55, 4.00, 0.94, 2.08
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT ----
    Select outer viewport: 4.2, 8, 0.75, 2.20
    Select inner viewport: 4.55, 7.75, 0.94, 2.08
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- DELAY TRAJECTORIES ----
    Select outer viewport: 0, 4.2, 2.30, 4.35
    Select inner viewport: 0.55, 4.00, 2.52, 4.22
    .vizDur = min(3, duration)
    .margin = max(0.05, 0.12 * max(0.1, maxDelayMs-minDelayMs))
    Axes: 0, .vizDur, minDelayMs-.margin, maxDelayMs+.margin
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .vizDur, minDelayMs-.margin, maxDelayMs+.margin

    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, effectiveBaseMs, .vizDur, effectiveBaseMs
    Solid line

    .nPts = 300
    Colour: "{0.22, 0.46, 0.82}"
    Line width: 1.5
    for .i from 2 to .nPts
        .t1 = (.i-2)/(.nPts-1) * .vizDur
        .t2 = (.i-1)/(.nPts-1) * .vizDur
        .d1 = effectiveBaseMs + effectiveDepthMs*sin(2*pi*rate_Hz*.t1)
        .d2 = effectiveBaseMs + effectiveDepthMs*sin(2*pi*rate_Hz*.t2)
        Draw line: .t1, .d1, .t2, .d2
    endfor

    Colour: "{0.48, 0.35, 0.74}"
    for .i from 2 to .nPts
        .t1 = (.i-2)/(.nPts-1) * .vizDur
        .t2 = (.i-1)/(.nPts-1) * .vizDur
        .d1 = effectiveBaseMs + effectiveDepthMs*sin(2*pi*rate_Hz*.t1 + phase_rad)
        .d2 = effectiveBaseMs + effectiveDepthMs*sin(2*pi*rate_Hz*.t2 + phase_rad)
        Draw line: .t1, .d1, .t2, .d2
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Delay trajectory"
    Font size: 6
    Text left: "yes", "ms"
    Text bottom: "yes", "Local time (s)"

    # ---- STATIC TRANSFER AT BASE DELAY ----
    Select outer viewport: 4.2, 8, 2.30, 4.35
    Select inner viewport: 4.55, 7.75, 2.52, 4.22
    .maxF = min(8000, sr/2)
    Axes: 0, .maxF, -30, 18
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .maxF, -30, 18
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, .maxF, 0

    .wet = dry_wet_percent/100
    .dry = 1-.wet
    .nF = 320
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    for .i from 2 to .nF
        .f1 = (.i-2)/(.nF-1) * .maxF
        .f2 = (.i-1)/(.nF-1) * .maxF

        .ph1 = 2*pi*.f1*effectiveBaseMs/1000
        .c1 = cos(.ph1)
        .s1 = sin(.ph1)
        .den1 = 1 - 2*feedback*.c1 + feedback^2
        .re1 = .dry + .wet*(.c1-feedback)/.den1
        .im1 = -.wet*.s1/.den1
        .mag1 = max(0.000001, sqrt(.re1^2+.im1^2))
        .db1 = max(-30, min(18, 20*ln(.mag1)/ln(10)))

        .ph2 = 2*pi*.f2*effectiveBaseMs/1000
        .c2 = cos(.ph2)
        .s2 = sin(.ph2)
        .den2 = 1 - 2*feedback*.c2 + feedback^2
        .re2 = .dry + .wet*(.c2-feedback)/.den2
        .im2 = -.wet*.s2/.den2
        .mag2 = max(0.000001, sqrt(.re2^2+.im2^2))
        .db2 = max(-30, min(18, 20*ln(.mag2)/ln(10)))

        Draw line: .f1, .db1, .f2, .db2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Static transfer @ base delay"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, 4.48, 5.35
    Select inner viewport: 0.55, 7.75, 4.55, 5.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", "Rate " + fixed$(rate_Hz, 2) + " Hz  |  delay " + fixed$(effectiveBaseMs, 2) + " +/- " + fixed$(effectiveDepthMs, 2) + " ms  |  phase " + fixed$(stereo_phase_offset_deg, 0) + " deg  |  feedback " + fixed$(feedback, 2)
    Text: 0.02, "left", 0.18, "half", "Wet " + fixed$(dry_wet_percent, 0) + "%  |  " + string$(outputChannels) + " ch  |  " + fixed$(sr, 0) + " Hz  |  " + fixed$(duration, 2) + " s  |  safety " + .safe$

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc

selectObject: result
