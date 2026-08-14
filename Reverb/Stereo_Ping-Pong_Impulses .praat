# ============================================================
# Praat AudioTools - Stereo_Ping_Pong_Impulses.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Convolution-based stereo ping-pong delay built from two
#   alternating band-limited impulse trains. The wet signal is
#   generated from a mono sum so that each tap occupies a clear
#   left/right position; the dry path preserves the original
#   stereo channels. Random timing jitter is generated once and
#   reused by the processing, Info output, and visualization.
#
# Review changes v0.3:
#   - Corrected pulse-train UI terminology: the final argument of
#     To Sound (pulse train) is sinc interpolation depth, not period.
#   - Removed the ineffective "pulse width" control (adaptation
#     factor is 1, so adaptation time does not change pulse height).
#   - Preserves original stereo dry path instead of collapsing it.
#   - 0% wet uses a true dry-only fast path.
#   - Generates jittered tap times once; DSP and visualization match.
#   - Bounds jitter to preserve L/R alternation.
#   - Removed per-channel/IR Scale peak normalization.
#   - Uses a single down-only clipping safeguard on the final stereo.
#   - Uses time-based object() reads for correct dry alignment.
#   - Visualization updated to the Praat AudioTools house style.
# ============================================================

form Stereo Ping-Pong Impulses
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset: 1
        option Default (balanced)
        option Tight Ping-Pong
        option Wide and Slow
        option Rapid Micro-Taps
        option Offbeat Start
        option Custom (use settings below)

    comment === Timing ===
    positive Impulse_train_duration_s 1.6
    positive Step_interval_s 0.22
    real Jitter_s 0.01
    positive Initial_delay_s 0.10

    comment === Impulse Rendering ===
    natural Sinc_interpolation_depth 2000

    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT AND PRESET SETUP
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
origStart = Get start time
sr = Get sampling frequency
numChannels = Get number of channels
origEnd = origStart + originalDur

if numChannels <> 1 and numChannels <> 2
    exitScript: "Stereo Ping-Pong Impulses currently supports mono or stereo Sound objects only."
endif

if preset = 1
    impulse_train_duration_s = 1.6
    step_interval_s = 0.22
    jitter_s = 0.01
    initial_delay_s = 0.10
    sinc_interpolation_depth = 2000
    presetName$ = "Default"
elsif preset = 2
    impulse_train_duration_s = 1.0
    step_interval_s = 0.15
    jitter_s = 0.005
    initial_delay_s = 0.08
    sinc_interpolation_depth = 1500
    presetName$ = "Tight"
elsif preset = 3
    impulse_train_duration_s = 2.5
    step_interval_s = 0.35
    jitter_s = 0.012
    initial_delay_s = 0.12
    sinc_interpolation_depth = 2600
    presetName$ = "Wide"
elsif preset = 4
    impulse_train_duration_s = 1.2
    step_interval_s = 0.08
    jitter_s = 0.003
    initial_delay_s = 0.05
    sinc_interpolation_depth = 1200
    presetName$ = "Rapid"
elsif preset = 5
    impulse_train_duration_s = 1.8
    step_interval_s = 0.22
    jitter_s = 0.02
    initial_delay_s = 0.17
    sinc_interpolation_depth = 2000
    presetName$ = "Offbeat"
else
    presetName$ = "Custom"
endif

# Validate/clamp user controls.
if jitter_s < 0
    jitter_s = 0
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

if sinc_interpolation_depth < 1
    sinc_interpolation_depth = 1
endif

if initial_delay_s + step_interval_s >= impulse_train_duration_s
    exitScript: "Impulse train duration must be longer than Initial delay + Step interval so that both L and R receive at least one tap."
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Bound jitter so independently jittered neighbouring L/R taps cannot
# cross each other. Also keep the first left tap safely above time zero.
effectiveJitter = jitter_s
jitterLimit = 0.45 * step_interval_s
if effectiveJitter > jitterLimit
    effectiveJitter = jitterLimit
endif

firstTapLimit = 0.9 * initial_delay_s
if effectiveJitter > firstTapLimit
    effectiveJitter = firstTapLimit
endif

halfSample = 0.5 / sr

# ============================================================
# GENERATE ACTUAL TAP TIMES ONCE
# ============================================================

numLeftImp = 0
t = initial_delay_s
while t < impulse_train_duration_s
    jitterLow = -effectiveJitter
    jitterHigh = effectiveJitter

    if t + jitterLow < halfSample
        jitterLow = halfSample - t
    endif
    if t + jitterHigh > impulse_train_duration_s - halfSample
        jitterHigh = impulse_train_duration_s - halfSample - t
    endif

    if jitterHigh > jitterLow
        u = t + randomUniform(jitterLow, jitterHigh)
    else
        u = t
    endif

    numLeftImp = numLeftImp + 1
    leftTime[numLeftImp] = u
    t = t + 2 * step_interval_s
endwhile

numRightImp = 0
t = initial_delay_s + step_interval_s
while t < impulse_train_duration_s
    jitterLow = -effectiveJitter
    jitterHigh = effectiveJitter

    if t + jitterLow < halfSample
        jitterLow = halfSample - t
    endif
    if t + jitterHigh > impulse_train_duration_s - halfSample
        jitterHigh = impulse_train_duration_s - halfSample - t
    endif

    if jitterHigh > jitterLow
        u = t + randomUniform(jitterLow, jitterHigh)
    else
        u = t
    endif

    numRightImp = numRightImp + 1
    rightTime[numRightImp] = u
    t = t + 2 * step_interval_s
endwhile

# ============================================================
# INFO
# ============================================================

writeInfoLine: "=== Stereo Ping-Pong Impulses ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Impulse-train span: ", fixed$(impulse_train_duration_s, 3), " s"
appendInfoLine: "Step interval: ", fixed$(step_interval_s * 1000, 1), " ms"
appendInfoLine: "Initial delay: ", fixed$(initial_delay_s * 1000, 1), " ms"
appendInfoLine: "Requested jitter: ±", fixed$(jitter_s * 1000, 2), " ms"
appendInfoLine: "Effective jitter: ±", fixed$(effectiveJitter * 1000, 2), " ms"
appendInfoLine: "Sinc interpolation depth: ", sinc_interpolation_depth, " samples"
appendInfoLine: "Left taps: ", numLeftImp
appendInfoLine: "Right taps: ", numRightImp
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

if wet_level = 0
    # True dry-only fast path.
    if numChannels = 2
        selectObject: original
        Copy: originalName$ + "_pingpong_" + presetName$
        result = selected("Sound")
    else
        selectObject: original
        Copy: "pingpong_dry_left"
        dryLeft = selected("Sound")

        selectObject: original
        Copy: "pingpong_dry_right"
        dryRight = selected("Sound")

        selectObject: dryLeft, dryRight
        Combine to stereo
        result = selected("Sound")
        Rename: originalName$ + "_pingpong_" + presetName$

        removeObject: dryLeft, dryRight
    endif

else
    # Preserve original dry channels. The wet source is mono so that
    # alternating convolution taps have unambiguous stereo positions.
    if numChannels = 2
        selectObject: original
        Extract one channel: 1
        dryLeft = selected("Sound")

        selectObject: original
        Extract one channel: 2
        dryRight = selected("Sound")

        selectObject: original
        Convert to mono
        monoSource = selected("Sound")
    else
        selectObject: original
        Copy: "pingpong_dry_left"
        dryLeft = selected("Sound")

        selectObject: original
        Copy: "pingpong_dry_right"
        dryRight = selected("Sound")

        selectObject: original
        Copy: "pingpong_mono_source"
        monoSource = selected("Sound")
    endif

    # Build left PointProcess from the exact pre-generated times.
    Create empty PointProcess: "pp_left", 0, impulse_train_duration_s
    ppLeft = selected("PointProcess")
    for i from 1 to numLeftImp
        selectObject: ppLeft
        Add point: leftTime[i]
    endfor

    # Build right PointProcess from the exact pre-generated times.
    Create empty PointProcess: "pp_right", 0, impulse_train_duration_s
    ppRight = selected("PointProcess")
    for i from 1 to numRightImp
        selectObject: ppRight
        Add point: rightTime[i]
    endfor

    # Convert ideal pulse locations to band-limited sampled impulses.
    # With adaptation factor = 1, adaptation time does not alter height.
    adaptationTime = 0.05

    selectObject: ppLeft
    To Sound (pulse train): sr, 1, adaptationTime, sinc_interpolation_depth
    impLeft = selected("Sound")

    selectObject: ppRight
    To Sound (pulse train): sr, 1, adaptationTime, sinc_interpolation_depth
    impRight = selected("Sound")

    # Convolution as a sum is appropriate here: each unit impulse
    # triggers one delayed copy of the mono wet source.
    appendInfoLine: "  Convolving left..."
    selectObject: monoSource, impLeft
    Convolve: "sum", "zero"
    resLeft = selected("Sound")

    appendInfoLine: "  Convolving right..."
    selectObject: monoSource, impRight
    Convolve: "sum", "zero"
    resRight = selected("Sound")

    # True wet/dry mix, with original stereo dry preserved.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_left_id_str$ = string$(dryLeft)
    dry_right_id_str$ = string$(dryRight)

    selectObject: resLeft
    Formula: "self * " + wet_str$ + " + object(" + dry_left_id_str$ + ", x, 1) * " + dry_str$

    selectObject: resRight
    Formula: "self * " + wet_str$ + " + object(" + dry_right_id_str$ + ", x, 1) * " + dry_str$

    selectObject: resLeft, resRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_pingpong_" + presetName$

    # One common down-only safeguard. Do not normalize quiet material.
    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "none"
    if resultPeak > 1
        Scale peak: 0.98
    endif

    removeObject: dryLeft, dryRight, monoSource, ppLeft, ppRight, impLeft, impRight, resLeft, resRight
endif

selectObject: result
resultDur = Get total duration
resultStart = Get start time
resultEnd = resultStart + resultDur

# ============================================================
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ============================================================

if draw_visualization
    Erase all

    # Main title.
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "Stereo Ping-Pong Impulses | " + presetName$

    # Compact metadata line.
    Select outer viewport: 0, 8, 0.36, 0.58
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + string$(numLeftImp + numRightImp) + " taps | Wet " + fixed$(wet_dry_percent, 0) + "%"

    # Dry waveform.
    Select outer viewport: 0, 8, 0.65, 1.35
    Select inner viewport: 0.65, 7.65, 0.72, 1.28
    selectObject: original
    Colour: "{0.65, 0.65, 0.65}"
    Draw: origStart, resultEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Dry"

    # Output waveform.
    Select outer viewport: 0, 8, 1.42, 2.12
    Select inner viewport: 0.65, 7.65, 1.49, 2.05
    selectObject: result
    Colour: "{0.48, 0.60, 0.76}"
    Draw: resultStart, resultEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Impulse-pattern panel title.
    Select outer viewport: 0, 8, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Alternating impulse pattern"

    # Actual jittered impulse pattern used by the DSP.
    Select outer viewport: 0, 8, 2.45, 3.82
    Select inner viewport: 0.65, 7.65, 2.60, 3.68
    Axes: 0, impulse_train_duration_s, -1.2, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, impulse_train_duration_s, -1.2, 1.2

    Colour: "{0.83, 0.83, 0.83}"
    Draw line: 0, 0, impulse_train_duration_s, 0

    # Left taps.
    Colour: "{0.42, 0.58, 0.76}"
    for i from 1 to numLeftImp
        t = leftTime[i]
        Draw line: t, 0.05, t, 0.80
        Paint circle (mm): "{0.42, 0.58, 0.76}", t, 0.80, 1.3
    endfor

    # Right taps.
    Colour: "{0.78, 0.48, 0.42}"
    for i from 1 to numRightImp
        t = rightTime[i]
        Draw line: t, -0.05, t, -0.80
        Paint circle (mm): "{0.78, 0.48, 0.42}", t, -0.80, 1.3
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "L / R"
    Text bottom: "yes", "Impulse time (s)"

    Font size: 5
    Colour: "{0.42, 0.58, 0.76}"
    Text: impulse_train_duration_s * 0.96, "right", 0.98, "half", "LEFT  " + string$(numLeftImp)
    Colour: "{0.78, 0.48, 0.42}"
    Text: impulse_train_duration_s * 0.96, "right", -0.98, "half", "RIGHT  " + string$(numRightImp)

    # Summary panel.
    Select outer viewport: 0.35, 7.65, 3.92, 4.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.35}"
    Font size: 6
    Text: 0.5, "centre", 0.68, "half", "IR span " + fixed$(impulse_train_duration_s, 2) + " s | Step " + fixed$(step_interval_s * 1000, 0) + " ms | Initial " + fixed$(initial_delay_s * 1000, 0) + " ms"
    Text: 0.5, "centre", 0.30, "half", "Jitter ±" + fixed$(effectiveJitter * 1000, 1) + " ms | Sinc depth " + string$(sinc_interpolation_depth) + " | Output " + fixed$(resultDur, 2) + " s"

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL INFO / PLAY
# ============================================================

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output duration: ", fixed$(resultDur, 3), " s"

if play_result
    selectObject: result
    Play
endif

selectObject: result
