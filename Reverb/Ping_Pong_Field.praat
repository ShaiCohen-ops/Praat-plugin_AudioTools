# ============================================================
# Praat AudioTools - Ping_Pong_Field_fast.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - Stereo/mix/geometry repair
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ping-Pong Field - stereo ping-pong delay effect with
#   high-frequency sparkle enhancement.
#
# v0.4 repair:
#   - Public form/defaults, output naming and final selection are unchanged.
#   - Mono input now returns the stereo ping-pong field that the script already
#     computed instead of discarding the right convolution.
#   - 3+ channel input is safely downmixed to mono for the stereo field.
#   - Custom delay bounds are ordered; jitter/offset cannot create negative or
#     zero-sample IR taps; right-channel narrow ranges are sanitized.
#   - Decay is constrained to a true decay [0,1]; right-channel derived values
#     cannot become negative.
#   - Fadeout is constrained to the appended tail and cannot attenuate source.
#   - Dry/effect mixing uses explicit row/column reads.
#   - Stereo is peak-limited only after L/R are combined, preserving channel
#     balance and avoiding unnecessary gain on quiet material.
#
# v0.3 Performance rewrite:
#   Instead of applying N Formula passes over the full audio,
#   this version builds a sparse impulse response (IR) Sound
#   for each channel, then uses Praat's built-in FFT convolution
#   (Convolve: "sum", "zero") to apply all echoes in one shot.
#   Building the IR only iterates over N short samples, not the
#   full audio buffer. Convolution is O(M log M) vs O(N*M).
# ============================================================

form Ping-Pong Field
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Ping-Pong
        option Medium Ping-Pong
        option Heavy Ping-Pong
        option Extreme Ping-Pong

    comment === Delay Parameters ===
    positive Tail_duration_s 2.0
    natural Number_of_echoes 90
    positive Min_delay_s 0.02
    positive Max_delay_s 1.2

    comment === Amplitude ===
    positive Base_amplitude 0.25
    positive Decay_factor 0.95

    comment === Stereo / Sparkle ===
    positive Ping_pong_offset_s 0.003
    positive Jitter_s 0.004
    positive HF_sparkle 0.3

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
    tail_duration_s = 1.5
    number_of_echoes = 50
    base_amplitude = 0.18
    min_delay_s = 0.025
    max_delay_s = 0.8
    decay_factor = 0.96
    ping_pong_offset_s = 0.002
    jitter_s = 0.003
    hF_sparkle = 0.2
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    tail_duration_s = 2.0
    number_of_echoes = 90
    base_amplitude = 0.25
    min_delay_s = 0.02
    max_delay_s = 1.2
    decay_factor = 0.95
    ping_pong_offset_s = 0.003
    jitter_s = 0.004
    hF_sparkle = 0.3
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    tail_duration_s = 2.5
    number_of_echoes = 130
    base_amplitude = 0.3
    min_delay_s = 0.015
    max_delay_s = 1.6
    decay_factor = 0.94
    ping_pong_offset_s = 0.004
    jitter_s = 0.006
    hF_sparkle = 0.4
    fadeout_duration_s = 1.4
    presetName$ = "Heavy"
elsif preset = 5
    tail_duration_s = 3.5
    number_of_echoes = 180
    base_amplitude = 0.35
    min_delay_s = 0.01
    max_delay_s = 2.2
    decay_factor = 0.93
    ping_pong_offset_s = 0.006
    jitter_s = 0.008
    hF_sparkle = 0.5
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

# Internal geometry guards. Built-in presets already lie inside these bounds.
effectiveEchoes = round(number_of_echoes)
if effectiveEchoes < 1
    effectiveEchoes = 1
endif

minDelayEff = max(2 / sr, min_delay_s)
maxDelayEff = max(2 / sr, max_delay_s)
if minDelayEff > maxDelayEff
    tmpDelay = minDelayEff
    minDelayEff = maxDelayEff
    maxDelayEff = tmpDelay
endif

jitterEff = max(0, jitter_s)
offsetEff = max(0, ping_pong_offset_s)
baseAmpEff = max(0, base_amplitude)
decayEff = decay_factor
if decayEff < 0
    decayEff = 0
elsif decayEff > 1
    decayEff = 1
endif
sparkleEff = max(0, hF_sparkle)

tailEff = tail_duration_s
if tailEff < 2 / sr
    tailEff = 2 / sr
endif
fadeEff = fadeout_duration_s
if fadeEff < 0
    fadeEff = 0
endif
if fadeEff > tailEff
    fadeEff = tailEff
endif

# Pre-calculate echo parameters for visualization
for k from 1 to min(effectiveEchoes, 50)
    t = minDelayEff + (maxDelayEff - minDelayEff) * k / effectiveEchoes
    if k mod 2 = 0
        off = offsetEff
    else
        off = -offsetEff
    endif
    echoDelay[k] = max(2 / sr, t + off)
    echoAmp[k] = baseAmpEff * (decayEff ^ k)
    if k mod 4 < 2
        echoSgn[k] = 1
    else
        echoSgn[k] = -1
    endif
endfor

# === Info ===
writeInfoLine: "=== Ping-Pong Field (convolution) ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Echoes: ", effectiveEchoes
appendInfoLine: "Delay range: ", minDelayEff * 1000, "-", maxDelayEff * 1000, " ms"
appendInfoLine: "Ping-pong offset: +/-", offsetEff * 1000, " ms"
appendInfoLine: "HF sparkle: ", sparkleEff
appendInfoLine: "Decay factor: ", decayEff
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Building impulse responses..."

# ============================================================
# PROCESSING
# ============================================================

totalDur = originalDur + tailEff

# IR covers the full delay range (echoes only, no direct signal spike)
irDur = maxDelayEff + jitterEff + offsetEff + 2 / sr

# -------------------------------------------------------
# BUILD LEFT IR
# -------------------------------------------------------
Create Sound from formula: "ir_left", 1, 0, irDur, sr, "0"
irLeft = selected("Sound")

for k from 1 to effectiveEchoes
    t = minDelayEff + (maxDelayEff - minDelayEff) * k / effectiveEchoes
    if k mod 2 = 0
        off = offsetEff
    else
        off = -offsetEff
    endif
    jitterNow = 0
    if jitterEff > 0
        jitterNow = randomUniform(-jitterEff, jitterEff)
    endif
    delay = t + off + jitterNow
    if delay < 2 / sr
        delay = 2 / sr
    endif
    if k mod 4 < 2
        sgn = 1
    else
        sgn = -1
    endif
    a = baseAmpEff * (decayEff ^ k) * (0.9 + 0.2 * randomUniform(0, 1)) * sgn
    col_main = round(delay * sr)
    col_pre  = col_main - 1
    if col_main >= 1
        selectObject: irLeft
        Formula: "if col = " + string$(col_main) + " then self + " + string$(a * (1 + sparkleEff)) + " else self fi"
    endif
    if col_pre >= 1
        selectObject: irLeft
        Formula: "if col = " + string$(col_pre) + " then self + " + string$(-a * sparkleEff) + " else self fi"
    endif
endfor

appendInfoLine: "  Left IR done."

# -------------------------------------------------------
# BUILD RIGHT IR
# -------------------------------------------------------
Create Sound from formula: "ir_right", 1, 0, irDur, sr, "0"
irRight = selected("Sound")

minD_R = max(2 / sr, minDelayEff + 0.002)
maxD_R = max(2 / sr, maxDelayEff - 0.02)
if maxD_R < minD_R
    maxD_R = minD_R
endif
rightBase = max(0, baseAmpEff - 0.01)
rightDecay = max(0, decayEff - 0.01)

for k from 1 to effectiveEchoes
    t = minD_R + (maxD_R - minD_R) * k / effectiveEchoes
    if k mod 2 = 0
        off = -offsetEff * 0.83
    else
        off = offsetEff * 0.83
    endif
    jitterNow = 0
    if jitterEff > 0
        jitterNow = randomUniform(-jitterEff * 0.875, jitterEff * 0.875)
    endif
    delay = t + off + jitterNow
    if delay < 2 / sr
        delay = 2 / sr
    endif
    if k mod 3 < 1.5
        sgn = 1
    else
        sgn = -1
    endif
    a = rightBase * (rightDecay ^ k) * (0.85 + 0.3 * randomUniform(0, 1)) * sgn
    sparkleR = sparkleEff * 0.83
    col_main = round(delay * sr)
    col_pre  = col_main - 1
    if col_main >= 1
        selectObject: irRight
        Formula: "if col = " + string$(col_main) + " then self + " + string$(a * (1 + sparkleR)) + " else self fi"
    endif
    if col_pre >= 1
        selectObject: irRight
        Formula: "if col = " + string$(col_pre) + " then self + " + string$(-a * sparkleR) + " else self fi"
    endif
endfor

appendInfoLine: "  Right IR done."
appendInfoLine: "Convolving..."

# -------------------------------------------------------
# EXTEND DRY SOURCE WITH SILENT TAIL
# -------------------------------------------------------
if numChannels = 2
    selectObject: original
    Extract one channel: 1
    dryL = selected("Sound")
    selectObject: original
    Extract one channel: 2
    dryR = selected("Sound")

    Create Sound from formula: "silent_tail", 1, 0, tailEff, sr, "0"
    silentTail = selected("Sound")

    selectObject: dryL, silentTail
    Concatenate
    dryLext = selected("Sound")
    removeObject: dryL

    selectObject: dryR, silentTail
    Concatenate
    dryRext = selected("Sound")
    removeObject: dryR
else
    selectObject: original
    if numChannels > 1
        Convert to mono
        dryMono = selected("Sound")
    else
        Copy: "dry_mono"
        dryMono = selected("Sound")
    endif

    Create Sound from formula: "silent_tail", 1, 0, tailEff, sr, "0"
    silentTail = selected("Sound")

    selectObject: dryMono, silentTail
    Concatenate
    dryLext = selected("Sound")
    removeObject: dryMono

    # Same mono source drives two decorrelated IRs, yielding a true stereo field.
    selectObject: dryLext
    Copy: "dry_right_ext"
    dryRext = selected("Sound")
endif

removeObject: silentTail

# -------------------------------------------------------
# CONVOLVE: produces echoes-only output (no direct signal)
# -------------------------------------------------------
selectObject: dryLext, irLeft
Convolve: "sum", "zero"
echoesLfull = selected("Sound")
removeObject: irLeft

selectObject: dryRext, irRight
Convolve: "sum", "zero"
echoesRfull = selected("Sound")
removeObject: irRight

appendInfoLine: "  Convolution done."

# -------------------------------------------------------
# TRIM: convolution output starts at t=0, trim to totalDur
# -------------------------------------------------------
selectObject: echoesLfull
convStart = Get start time
selectObject: echoesLfull
Extract part: convStart, convStart + totalDur, "rectangular", 1, "no"
echoesL = selected("Sound")
Shift times to: "start time", 0
removeObject: echoesLfull

selectObject: echoesRfull
Extract part: convStart, convStart + totalDur, "rectangular", 1, "no"
echoesR = selected("Sound")
Shift times to: "start time", 0
removeObject: echoesRfull

# -------------------------------------------------------
# MIX: output = dry * dry_level + echoes * wet_level
# -------------------------------------------------------
wet_str$ = string$(wet_level)
dry_str$ = string$(dry_level)

selectObject: echoesL
Formula: "self * " + wet_str$ + " + object[" + string$(dryLext) + ", row, col] * " + dry_str$
wetLeft = echoesL

selectObject: echoesR
Formula: "self * " + wet_str$ + " + object[" + string$(dryRext) + ", row, col] * " + dry_str$
wetRight = echoesR

removeObject: dryLext, dryRext

# -------------------------------------------------------
# FADEOUT — constrained to the appended tail
# -------------------------------------------------------
if fadeEff > 0
    fade_start = totalDur - fadeEff
    fs$ = string$(fade_start)
    fd$ = string$(fadeEff)

    selectObject: wetLeft
    Formula: "if x > " + fs$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + fs$ + ") / " + fd$ + ")) else self fi"

    selectObject: wetRight
    Formula: "if x > " + fs$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + fs$ + ") / " + fd$ + ")) else self fi"
endif

# -------------------------------------------------------
# COMBINE — Ping-Pong Field is a stereo effect for every input topology.
# -------------------------------------------------------
selectObject: wetLeft, wetRight
Combine to stereo
result = selected("Sound")
Rename: originalName$ + "_pingpong_" + presetName$
removeObject: wetLeft, wetRight

# Safety ceiling only, applied once to the stereo object so L/R balance survives.
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > 0.98
    Scale peak: 0.98
endif


# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Ping-Pong Field: " + originalName$ + " (" + presetName$ + ")"

    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"

    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "PP " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9

    maxDelay = maxDelayEff * 1.1
    Axes: 0, maxDelay * 1000, -1.2, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxDelay * 1000, -1.2, 1.2

    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, maxDelay * 1000, 0

    numShow = min(effectiveEchoes, 50)
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        amp = 0
        if baseAmpEff > 0
            amp = echoAmp[k] / baseAmpEff
        endif
        sgn = echoSgn[k]

        if k mod 2 = 0
            yPos = 0.6
            col$ = "{0.5, 0.6, 0.8}"
        else
            yPos = -0.6
            col$ = "{0.8, 0.5, 0.5}"
        endif

        circleSize = amp * maxDelay * 15
        Colour: col$
        Paint circle: col$, delayMs, yPos * sgn, circleSize

        Colour: "{0.7, 0.7, 0.7}"
        Draw line: delayMs, 0, delayMs, yPos * sgn * 0.8
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "L <-> R"
    Text bottom: "yes", "Delay (ms)"

    Font size: 5
    Colour: "{0.5, 0.6, 0.8}"
    Text: maxDelay * 900, "centre", 1.0, "half", "Even echoes (R)"
    Colour: "{0.8, 0.5, 0.5}"
    Text: maxDelay * 900, "centre", -1.0, "half", "Odd echoes (L)"

    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Echoes: " + string$(effectiveEchoes) + " | Delay: " + fixed$(minDelayEff * 1000, 0) + "-" + fixed$(maxDelayEff * 1000, 0) + "ms | Offset: +/-" + fixed$(offsetEff * 1000, 1) + "ms | Sparkle: " + fixed$(sparkleEff, 2)

    Font size: 10
    Colour: "Black"
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