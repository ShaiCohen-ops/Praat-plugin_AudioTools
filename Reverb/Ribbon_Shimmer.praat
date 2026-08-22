# ============================================================
# Praat AudioTools - Ribbon_Shimmer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026) - Tap-bank/mix/geometry repair
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ribbon Shimmer - lush reverb effect with exponentially-
#   spaced delays and high-frequency enhancement. Delay times
#   follow: delay = minD × (maxD/minD)^(k/n), creating dense
#   early reflections that thin out over time. HF sparkle via
#   differentiation adds "air". Polarity alternation creates
#   rich phase texture.
#
# Changelog v0.4:
#   - Public form/defaults, output naming and final selection are unchanged.
#   - The shimmer engine is now a true feed-forward tapped-delay bank driven
#     by the source, matching the documented/visualized tap pattern; the old
#     recursive self(x-delay) loop created undocumented cross-echoes.
#   - Correct Wet/Dry semantics: 0% = dry only, 100% = shimmer taps only.
#   - The exact jittered left tap plan is shown in the visualization.
#   - Deterministic internal seed for tap jitter; Praat global RNG is restored.
#   - Fadeout is constrained to the appended tail and cannot attenuate source.
#   - Exact-channel silent tails support arbitrary multichannel input.
#   - Custom delay bounds/decay/base/sparkle/count are sanitized.
#   - Final normalization is a ceiling only; quiet material is not boosted.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Fixed variable name mismatches
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Ribbon Shimmer
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Ribbon
        option Medium Ribbon
        option Heavy Ribbon
        option Extreme Ribbon
    
    comment === Effect Parameters ===
    positive Tail_duration_s 0.5
    natural Number_of_delays 48
    positive Base_amplitude 0.24
    positive Min_delay_s 0.015
    positive Max_delay_s 1.35
    positive Decay_factor 0.955
    
    comment === HF Sparkle ===
    positive Sparkle_amount 0.25
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Ribbon
    tail_duration_s = 0.3
    number_of_delays = 50
    base_amplitude = 0.16
    min_delay_s = 0.012
    max_delay_s = 0.8
    decay_factor = 0.965
    sparkle_amount = 0.2
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Ribbon
    tail_duration_s = 0.5
    number_of_delays = 72
    base_amplitude = 0.24
    min_delay_s = 0.015
    max_delay_s = 1.35
    decay_factor = 0.955
    sparkle_amount = 0.25
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Ribbon
    tail_duration_s = 0.8
    number_of_delays = 90
    base_amplitude = 0.3
    min_delay_s = 0.012
    max_delay_s = 1.8
    decay_factor = 0.945
    sparkle_amount = 0.3
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Ribbon
    tail_duration_s = 1.2
    number_of_delays = 100
    base_amplitude = 0.38
    min_delay_s = 0.01
    max_delay_s = 2.5
    decay_factor = 0.935
    sparkle_amount = 0.35
    fadeout_duration_s = 1.8
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Internal geometry/stability guards; built-in presets remain unchanged.
effectiveDelays = round(number_of_delays)
if effectiveDelays < 1
    effectiveDelays = 1
endif

minDelayEff = max(2 / sr, min_delay_s)
maxDelayEff = max(2 / sr, max_delay_s)
if minDelayEff > maxDelayEff
    tmpDelay = minDelayEff
    minDelayEff = maxDelayEff
    maxDelayEff = tmpDelay
endif

baseAmpEff = base_amplitude
if baseAmpEff < 0
    baseAmpEff = 0
elsif baseAmpEff > 0.99
    baseAmpEff = 0.99
endif

decayEff = decay_factor
if decayEff < 0
    decayEff = 0
elsif decayEff > 1
    decayEff = 1
endif

sparkleEff = sparkle_amount
if sparkleEff < 0
    sparkleEff = 0
elsif sparkleEff > 2
    sparkleEff = 2
endif

tailEff = max(2 / sr, tail_duration_s)
fadeEff = fadeout_duration_s
if fadeEff < 0
    fadeEff = 0
endif
if fadeEff > tailEff
    fadeEff = tailEff
endif

# Build the literal render plans once. The left plan is also the QC diagram.
researchSeed = 20260814
random_initializeWithSeedUnsafelyButPredictably (researchSeed)

for k from 1 to effectiveDelays
    u = k / effectiveDelays
    nominalDelay = minDelayEff * ((maxDelayEff / minDelayEff) ^ u)
    jitterNow = randomUniform(-0.003, 0.003)
    leftDelay[k] = max(2 / sr, nominalDelay + jitterNow)
    leftAmp[k] = baseAmpEff * (decayEff ^ k)
    if k mod 3 = 0
        leftAmp[k] = -leftAmp[k]
        echoPol[k] = -1
    else
        echoPol[k] = 1
    endif
    echoDelay[k] = leftDelay[k]
    echoAmp[k] = abs(leftAmp[k])
endfor

minD_R = max(2 / sr, minDelayEff * 1.13)
maxD_R = max(2 / sr, maxDelayEff * 0.98)
if minD_R > maxD_R
    tmpDelay = minD_R
    minD_R = maxD_R
    maxD_R = tmpDelay
endif
baseAmp_R = baseAmpEff * 0.96
decay_R = max(0, decayEff - 0.005)
sparkleR = sparkleEff * 0.8

for k from 1 to effectiveDelays
    u = k / effectiveDelays
    nominalDelay = minD_R * ((maxD_R / minD_R) ^ u)
    jitterNow = randomUniform(-0.002, 0.002)
    rightDelay[k] = max(2 / sr, nominalDelay + jitterNow)
    rightAmp[k] = baseAmp_R * (decay_R ^ k)
    if k mod 4 = 0
        rightAmp[k] = -rightAmp[k]
    endif
endfor

random_initializeSafelyAndUnpredictably ()

# Sample period for HF differentiation.
samplePeriod = 1 / sr
# === Info ===
writeInfoLine: "=== Ribbon Shimmer ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Delays: ", effectiveDelays
appendInfoLine: "Delay range: ", minDelayEff * 1000, " - ", maxDelayEff * 1000, " ms (exponential)"
appendInfoLine: "Decay factor: ", decayEff
appendInfoLine: "HF sparkle: ", sparkleEff
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "% | Seed: ", researchSeed
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tailEff

# Create silent tail with the exact source channel count.
Create Sound from formula: "silent_tail", numChannels, 0, tailEff, sr, "0"
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

sp_str$ = string$(samplePeriod)
sparkle_str$ = string$(sparkleEff)

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Feed-forward left tap bank: zero effect buffer, source-driven taps.
    selectObject: leftChannel
    Copy: "shimmer_left"
    shimmerLeft = selected("Sound")
    Formula: "0"
    left_str$ = string$(leftChannel)

    for k from 1 to effectiveDelays
        delay_str$ = string$(leftDelay[k])
        a_str$ = string$(leftAmp[k])

        selectObject: shimmerLeft
        Formula: "self + " + a_str$ + " * (object(" + left_str$ + ", x - " + delay_str$ + ", 1) + " + sparkle_str$ + " * (object(" + left_str$ + ", x - " + delay_str$ + ", 1) - object(" + left_str$ + ", x - " + delay_str$ + " - " + sp_str$ + ", 1)))"
    endfor

    # Feed-forward right tap bank with decorrelated deterministic plan.
    selectObject: rightChannel
    Copy: "shimmer_right"
    shimmerRight = selected("Sound")
    Formula: "0"
    right_str$ = string$(rightChannel)
    sparkleR_str$ = string$(sparkleR)

    for k from 1 to effectiveDelays
        delay_str$ = string$(rightDelay[k])
        a_str$ = string$(rightAmp[k])

        selectObject: shimmerRight
        Formula: "self + " + a_str$ + " * (object(" + right_str$ + ", x - " + delay_str$ + ", 1) + " + sparkleR_str$ + " * (object(" + right_str$ + ", x - " + delay_str$ + ", 1) - object(" + right_str$ + ", x - " + delay_str$ + " - " + sp_str$ + ", 1)))"
    endfor

    # True dry/effect crossfade. shimmerLeft/Right are effect-only buffers.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_str$ = string$(leftChannel)
    right_str$ = string$(rightChannel)

    selectObject: shimmerLeft
    Formula: "self * " + wet_str$ + " + object[" + left_str$ + ", row, col] * " + dry_str$

    selectObject: shimmerRight
    Formula: "self * " + wet_str$ + " + object[" + right_str$ + ", row, col] * " + dry_str$

    # Fade only within the appended tail.
    if fadeEff > 0
        fade_start = totalDur - fadeEff
        fade_str$ = string$(fadeEff)
        start_str$ = string$(fade_start)

        selectObject: shimmerLeft
        Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"

        selectObject: shimmerRight
        Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    endif

    # Combine first, then one safety ceiling to preserve L/R balance.
    selectObject: shimmerLeft, shimmerRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_ribbon_" + presetName$

    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0.98
        Scale peak: 0.98
    endif

    # Cleanup
    removeObject: leftChannel, rightChannel, shimmerLeft, shimmerRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "shimmer_mono"
    shimmerMono = selected("Sound")
    Formula: "0"
    ext_str$ = string$(extendedSound)

    for k from 1 to effectiveDelays
        delay_str$ = string$(leftDelay[k])
        a_str$ = string$(leftAmp[k])

        selectObject: shimmerMono
        Formula: "self + " + a_str$ + " * (object(" + ext_str$ + ", x - " + delay_str$ + ", row) + " + sparkle_str$ + " * (object(" + ext_str$ + ", x - " + delay_str$ + ", row) - object(" + ext_str$ + ", x - " + delay_str$ + " - " + sp_str$ + ", row)))"
    endfor

    # True dry/effect crossfade; row/col preserves arbitrary channels.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    ext_str$ = string$(extendedSound)

    selectObject: shimmerMono
    Formula: "self * " + wet_str$ + " + object[" + ext_str$ + ", row, col] * " + dry_str$

    # Fade only within the appended tail.
    if fadeEff > 0
        fade_start = totalDur - fadeEff
        fade_str$ = string$(fadeEff)
        start_str$ = string$(fade_start)

        selectObject: shimmerMono
        Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    endif

    selectObject: shimmerMono
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0.98
        Scale peak: 0.98
    endif
    Rename: originalName$ + "_ribbon_" + presetName$
    result = shimmerMono

    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Select outer viewport: 0, 8, 0, 8

    selectObject: result
    resultDur = Get total duration

    # === TITLE ===
    Select outer viewport: 0, 8, 0.0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.66, "half", "##Ribbon Shimmer##  |  " + presetName$ + " | v0.5.1"
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.24, "half", originalName$ + "   |   " + string$(effectiveDelays) + " delays   |   wet/dry " + fixed$(wet_dry_percent, 0) + "%"

    # === DRY WAVEFORM ===
    Select outer viewport: 0, 8, 0.7, 2.5
    Select inner viewport: 0.60, 7.70, 0.8, 2.4
    selectObject: original
    Axes: 0, resultDur, -1, 1
    Colour: "{0.55, 0.55, 0.6}"
    Draw: 0, originalDur, -1, 1, "no", "Curve"
    Colour: "{0.75, 0.75, 0.8}"
    Dotted line
    Draw line: originalDur, -1, originalDur, 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Select inner viewport: 0.20, 0.48, 0.8, 2.4
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.8, 2.4
    Axes: 0, resultDur, -1, 1
    Font size: 7
    Text top: "no", "##Original (dry) — ends before the tail##"

    # === RESULT WAVEFORM (full length, including shimmer tail) ===
    Select outer viewport: 0, 8, 2.6, 4.4
    Select inner viewport: 0.60, 7.70, 2.7, 4.3
    selectObject: result
    Axes: 0, resultDur, -1, 1
    Colour: "{0.55, 0.45, 0.7}"
    Draw: 0, resultDur, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Select inner viewport: 0.20, 0.48, 2.7, 4.3
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Shimmer " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 2.7, 4.3
    Axes: 0, resultDur, -1, 1
    Text bottom: "yes", "Time (s)"
    Font size: 7
    Text top: "no", "##Shimmered Output (full length with tail)##"

    # === DELAY / ECHO PATTERN ===
    Select outer viewport: 0, 8, 4.5, 6.9
    Select inner viewport: 0.60, 7.70, 4.6, 6.8
    maxDelayMs = maxDelayEff * 1000 * 1.1
    maxAmp = max(0.05, baseAmpEff * 1.2)
    Axes: 0, maxDelayMs, -maxAmp, maxAmp
    Paint rectangle: "{0.96, 0.96, 0.97}", 0, maxDelayMs, -maxAmp, maxAmp
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, maxDelayMs, 0

    numShow = min(effectiveDelays, 100)
    radius = maxDelayMs * 0.006
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        amp = echoAmp[k] * echoPol[k]
        if echoPol[k] > 0
            col$ = "{0.45, 0.55, 0.80}"
        else
            col$ = "{0.80, 0.45, 0.45}"
        endif
        Colour: col$
        Draw line: delayMs, 0, delayMs, amp
        Paint circle: col$, delayMs, amp, radius
    endfor

    # exponential decay envelope
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    prevX = 0
    prevY = baseAmpEff
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        env = baseAmpEff * (decayEff ^ k)
        Draw line: prevX, prevY, delayMs, env
        prevX = delayMs
        prevY = env
    endfor
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Select inner viewport: 0.20, 0.48, 4.6, 6.8
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amplitude"
    Select inner viewport: 0.60, 7.70, 4.6, 6.8
    Axes: 0, maxDelayMs, -maxAmp, maxAmp
    Text bottom: "yes", "Delay (ms) — exponential spacing"
    Font size: 7
    Text top: "no", "##Echo Tap Pattern (blue +, red −)##"

    # === GREY SUMMARY PANEL ===
    Select outer viewport: 0, 8, 7.05, 8.05
    Select inner viewport: 0.60, 7.70, 7.12, 7.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "Delays: " + string$(effectiveDelays) + "    Range: " + fixed$(minDelayEff * 1000, 0) + "–" + fixed$(maxDelayEff * 1000, 0) + " ms    Decay: " + fixed$(decayEff, 3) + "    Sparkle: " + fixed$(sparkleEff, 2)
    Colour: "{0.4, 0.4, 0.5}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Output: " + fixed$(resultDur, 2) + " s  (original " + fixed$(originalDur, 2) + " s + " + fixed$(tailEff, 2) + " s tail)    Wet/dry: " + fixed$(wet_dry_percent, 0) + "\%  "
    Colour: "Black"

    Select inner viewport: 0.60, 7.70, 7.12, 7.98
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 8.15
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

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
