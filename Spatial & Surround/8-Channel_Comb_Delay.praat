# ============================================================
# Praat AudioTools - 8-Channel_Comb_Delay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# v0.5 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Comb Filter / Delay Processor
#   Creates 8 channels with different comb-filter settings.
#   Optional: Reverse even-numbered channels for spatial effects.
#   Deliverable as octophonic, stems, or a downmix.
#
# Changelog v0.5 (2026):
#   - NEW: Output_format menu. The preset choice, the b calculation, the
#     comb formula, the even-channel reversal and the construction of
#     the eight working channels are untouched; the branch begins only
#     once ch[1]-ch[8] exist.
#       1  8 channels - octophonic     Ch1-Ch8
#       2  4 stereo pairs              Ch1|Ch2  Ch3|Ch4  Ch5|Ch6  Ch7|Ch8
#       3  2 quadraphonic groups       Ch1-Ch4, Ch5-Ch8
#       4  4-channel fold-down         Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8
#       5  Stereo mix                  L: odd channels   R: even channels
#     The two downmixes are keyed to parity rather than to position,
#     which is where this script differs from the canon. Odd channels
#     stay with odd and even with even, so with Reverse_even_channels on
#     a forward channel is never summed into the same output channel as
#     a reversed one, and the stereo mix puts the forward channels left
#     and the reversed ones right. That turns the reversal from a
#     per-channel curiosity into an audible property of the downmix,
#     and it spreads the comb divisors across both sides instead of
#     stacking the four shortest delays on one.
#   - NEW: shared-gain normalisation, reported as two distinct stages.
#     Formats that keep the eight channels separate take one gain
#     derived from the loudest of them, applied to all eight, so no
#     stem is lifted relative to another and the relation between comb
#     settings survives. Formats that sum channels do all the sums
#     first and normalise the finished object once. For format 1 this
#     is numerically identical to v0.3's Scale peak on the 8-channel
#     result, so the default output is unchanged.
#   - NEW: monitoring mix, L = Ch1+Ch3+Ch5+Ch7, R = Ch2+Ch4+Ch6+Ch8 -
#     the same mapping the stereo format offers, so a preview sounds
#     like the downmix it previews. Auditioned in the stem formats,
#     where playing the first pair or quad alone would present a
#     quarter or a half of the result as the whole.
#   - FIX: the waveform panel drew Ch1 and Ch2 by extracting them from
#     the single output object. That only holds when there is exactly
#     one output with the channels in that order. It now draws the
#     working channels directly, so the panel is identical in all five
#     formats and always shows the processed source.
#   - FIX: b = floor(numSamples / n) silently reached 0 when a divisor
#     exceeded the sample count - Exponential (/256) on a short source,
#     for instance. The comb then evaluated self[col] - self[col],
#     i.e. digital silence on that channel, with no warning. b is
#     clamped to at least 1 and the degenerate cases are reported.
#   - FIX: the comb formula interpolated 'b' with backticks. string$()
#     is the portable idiom and cannot produce a non-integer index.
#   - FIX: Scale_peak is a plain real, so 0 or a negative value was
#     reachable and would have made Scale peak fail. Clamped to (0, 1].
#   - FIX: cleanup is driven by an explicit output list. v0.3's cleanup
#     assumed one result; formats 2 and 3 leave four and two objects.
#
# Changelog v0.3:
#   - Resized visualization from non-standard 10x canvas to 8x8
#     to match suite standard
#   - Multi-panel layout:
#       Panel A: Delay divisor bar chart (b samples, proportional)
#       Panel B: Comb period in ms per channel
#       Panel C: Forward/reverse direction diagram
#       Panel D: Output waveform strip
#       Panel E: Summary bar
# ============================================================

# === Check Input (before the form, so a bad selection costs nothing) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Comb Delay
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Linear (2,4,6,8,10,12,14,16)"
        option: "Exponential (2,4,8,16,32,64,128,256)"
        option: "Fibonacci (2,3,5,8,13,21,34,55)"
        option: "Prime Numbers (2,3,5,7,11,13,17,19)"
        option: "Octaves (2,4,8,16,2,4,8,16)"
        option: "Dense Cluster (2,3,4,5,6,7,8,9)"
        option: "Wide Spread (2,8,18,32,50,72,98,128)"
        option: "Alternating (2,16,4,14,6,12,8,10)"
        option: "Reverse (24,20,16,12,10,8,4,2)"

    comment === Comb filter divisors (higher = shorter delay) ===
    positive Delay_1 2
    positive Delay_2 4
    positive Delay_3 8
    positive Delay_4 10
    positive Delay_5 12
    positive Delay_6 16
    positive Delay_7 20
    positive Delay_8 24

    comment === Processing options ===
    boolean Reverse_even_channels 0
    real Scale_peak 0.99

    comment === Output format ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 stereo pairs (Ch1|Ch2, Ch3|Ch4, Ch5|Ch6, Ch7|Ch8)"
        option: "2 quadraphonic groups (Ch1-Ch4, Ch5-Ch8)"
        option: "4-channel fold-down (Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8)"
        option: "Stereo mix (L: odd channels, R: even channels)"

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    delay_1 = 2
    delay_2 = 4
    delay_3 = 6
    delay_4 = 8
    delay_5 = 10
    delay_6 = 12
    delay_7 = 14
    delay_8 = 16
    presetName$ = "Linear"
elsif preset = 3
    delay_1 = 2
    delay_2 = 4
    delay_3 = 8
    delay_4 = 16
    delay_5 = 32
    delay_6 = 64
    delay_7 = 128
    delay_8 = 256
    presetName$ = "Exponential"
elsif preset = 4
    delay_1 = 2
    delay_2 = 3
    delay_3 = 5
    delay_4 = 8
    delay_5 = 13
    delay_6 = 21
    delay_7 = 34
    delay_8 = 55
    presetName$ = "Fibonacci"
elsif preset = 5
    delay_1 = 2
    delay_2 = 3
    delay_3 = 5
    delay_4 = 7
    delay_5 = 11
    delay_6 = 13
    delay_7 = 17
    delay_8 = 19
    presetName$ = "Primes"
elsif preset = 6
    delay_1 = 2
    delay_2 = 4
    delay_3 = 8
    delay_4 = 16
    delay_5 = 2
    delay_6 = 4
    delay_7 = 8
    delay_8 = 16
    presetName$ = "Octaves"
elsif preset = 7
    delay_1 = 2
    delay_2 = 3
    delay_3 = 4
    delay_4 = 5
    delay_5 = 6
    delay_6 = 7
    delay_7 = 8
    delay_8 = 9
    presetName$ = "Dense"
elsif preset = 8
    delay_1 = 2
    delay_2 = 8
    delay_3 = 18
    delay_4 = 32
    delay_5 = 50
    delay_6 = 72
    delay_7 = 98
    delay_8 = 128
    presetName$ = "Wide"
elsif preset = 9
    delay_1 = 2
    delay_2 = 16
    delay_3 = 4
    delay_4 = 14
    delay_5 = 6
    delay_6 = 12
    delay_7 = 8
    delay_8 = 10
    presetName$ = "Alternating"
elsif preset = 10
    delay_1 = 24
    delay_2 = 20
    delay_3 = 16
    delay_4 = 12
    delay_5 = 10
    delay_6 = 8
    delay_7 = 4
    delay_8 = 2
    presetName$ = "Reverse"
else
    presetName$ = "Custom"
endif

# v0.5: Scale_peak is a plain real; 0 or negative would make Scale peak
# fail after all the processing had already been done.
if scale_peak <= 0
    scale_peak = 0.99
endif
if scale_peak > 1
    scale_peak = 1
endif

# === Output format labels ===
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "ch1-ch8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 stereo pairs"
    mapLine$ = "Ch1|Ch2   Ch3|Ch4   Ch5|Ch6   Ch7|Ch8"
elsif output_format = 3
    formatName$ = "2 quadraphonic groups"
    mapLine$ = "quad 1 = Ch1-Ch4    quad 2 = Ch5-Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "1=Ch1+Ch5  2=Ch2+Ch6  3=Ch3+Ch7  4=Ch4+Ch8"
else
    formatName$ = "Stereo mix (L odd / R even)"
    mapLine$ = "L = Ch1+Ch3+Ch5+Ch7    R = Ch2+Ch4+Ch6+Ch8"
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency

nch = Get number of channels
if nch > 1
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: originalID
    Copy: "mono_copy"
    monoID = selected("Sound")
endif

selectObject: monoID
Rename: "soundObj"
numSamples = Get number of samples

# === Store delay divisors ===
divisor[1] = delay_1
divisor[2] = delay_2
divisor[3] = delay_3
divisor[4] = delay_4
divisor[5] = delay_5
divisor[6] = delay_6
divisor[7] = delay_7
divisor[8] = delay_8

# === Create 8 channels with comb filter ===
# The formula reads self[col + b], i.e. forward, into samples the
# in-place pass has not reached yet, so the read is of original values.
bClamped = 0
bInverted = 0
for i from 1 to 8
    selectObject: monoID
    Copy: "Ch" + string$(i)
    ch[i] = selected("Sound")

    n = divisor[i]
    b = floor(numSamples / n)

    # v0.5: a divisor larger than the sample count gave b = 0, which
    # turns the comb into self[col] - self[col] - a silent channel, with
    # nothing reported. b >= 1 keeps it a first difference at worst.
    if b < 1
        b = 1
        bClamped = 1
    endif
    if b >= numSamples
        bInverted = 1
    endif
    b_[i] = b

    # v0.5: string$() instead of backtick interpolation of b
    Formula: "if col + " + string$(b) + " <= ncol then self[col + "
        ... + string$(b) + "] - self[col] else -self[col] fi"
endfor

# === Optionally reverse even-numbered channels ===
if reverse_even_channels
    for i from 1 to 8
        if i mod 2 = 0
            selectObject: ch[i]
            Reverse
        endif
    endfor
    revLabel$ = " (even rev.)"
else
    revLabel$ = ""
endif

# ============================================================
# SHARED-GAIN NORMALISATION
# ============================================================
# Stage 1, applied in every format: one gain taken from the loudest of
# the eight processed channels and applied to all eight. Normalising a
# pair or a quad on its own would give a quiet group more gain than a
# loud one and rewrite the relation between comb settings, which is the
# whole content of this script.

peakAll = 0
for i from 1 to 8
    selectObject: ch[i]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
if peakAll < 1e-9
    peakAll = 1e-9
endif
sharedGain = scale_peak / peakAll
sharedGain$ = fixed$(sharedGain, 10)

for i from 1 to 8
    selectObject: ch[i]
    Formula: "self * " + sharedGain$
endfor

# ============================================================
# ODD / EVEN FOLD  (monitoring mix, and the stereo format)
# ============================================================
# Combine + Convert to mono averages the group. The divisor is the same
# for both sides, so the L/R balance is untouched.

selectObject: ch[1], ch[3], ch[5], ch[7]
Combine to stereo
oddQuad = selected("Sound")
Convert to mono
mixL = selected("Sound")
Rename: "mix_odd"
removeObject: oddQuad

selectObject: ch[2], ch[4], ch[6], ch[8]
Combine to stereo
evenQuad = selected("Sound")
Convert to mono
mixR = selected("Sound")
Rename: "mix_even"
removeObject: evenQuad

selectObject: mixL, mixR
Combine to stereo
monitorID = selected("Sound")
Rename: "comb_monitor"
Scale peak: scale_peak

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
# out[1..outCount] is what the user keeps; everything else goes below.
# downmixNorm marks the formats that sum channels and therefore need a
# second, whole-object normalisation after the sums exist.

downmixNorm = 0

if output_format = 1
    # --- 8 channels, octophonic ---
    selectObject: ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7], ch[8]
    Combine to stereo
    oct = selected("Sound")
    Rename: originalName$ + "_8chComb_" + presetName$
    outCount = 1
    out[1] = oct
    outChannels = 8

elsif output_format = 2
    # --- 4 stereo pairs ---
    selectObject: ch[1], ch[2]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_comb_pair_12_" + presetName$
    selectObject: ch[3], ch[4]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_comb_pair_34_" + presetName$
    selectObject: ch[5], ch[6]
    Combine to stereo
    out[3] = selected("Sound")
    Rename: originalName$ + "_comb_pair_56_" + presetName$
    selectObject: ch[7], ch[8]
    Combine to stereo
    out[4] = selected("Sound")
    Rename: originalName$ + "_comb_pair_78_" + presetName$
    outCount = 4
    outChannels = 2

elsif output_format = 3
    # --- 2 quadraphonic groups ---
    selectObject: ch[1], ch[2], ch[3], ch[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_comb_quad_1to4_" + presetName$
    selectObject: ch[5], ch[6], ch[7], ch[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_comb_quad_5to8_" + presetName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    # --- 4-channel fold-down: Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8 ---
    # Pairing four apart keeps odd with odd and even with even, so with
    # Reverse_even_channels on no output channel carries a forward and
    # a reversed channel at the same time.
    for k from 1 to 4
        selectObject: ch[k], ch[k + 4]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "fold_" + string$(k)
        removeObject: foldPair
    endfor
    selectObject: fold[1], fold[2], fold[3], fold[4]
    Combine to stereo
    foldOut = selected("Sound")
    Rename: originalName$ + "_comb_fold4_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    out[1] = foldOut
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4]

else
    # --- Stereo mix: L = odd channels, R = even channels ---
    # With Reverse_even_channels on, this puts the forward channels
    # left and the reversed ones right, and it spreads the comb
    # divisors across both sides instead of stacking the four shortest
    # delays on one.
    selectObject: mixL, mixR
    Combine to stereo
    stereoOut = selected("Sound")
    Rename: originalName$ + "_comb_stereo_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    out[1] = stereoOut
    outChannels = 2
endif

removeObject: mixL, mixR

# === Info ===
writeInfoLine: "=== 8-Channel Comb Delay ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$, revLabel$
appendInfoLine: "Samples: ", numSamples
appendInfoLine: ""
appendInfoLine: "Channel settings:"
for i from 1 to 8
    if reverse_even_channels and (i mod 2 = 0)
        dir$ = "REVERSED"
    else
        dir$ = "forward"
    endif
    appendInfoLine: "  Ch", i, ": /", divisor[i], " -> b=", b_[i], " (", dir$, ")"
endfor
if bClamped = 1
    appendInfoLine: ""
    appendInfoLine: "NOTE: at least one divisor exceeded the sample count, so b would"
    appendInfoLine: "      have been 0 and that channel silent. b was clamped to 1,"
    appendInfoLine: "      which makes the comb a first difference on that channel."
endif
if bInverted = 1
    appendInfoLine: ""
    appendInfoLine: "NOTE: at least one b reaches the end of the source, so that channel"
    appendInfoLine: "      is a phase-inverted copy rather than a comb."
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
if output_format = 1
    appendInfoLine: "  ch1-ch8: Ch1 - Ch8"
elsif output_format = 2
    appendInfoLine: "  Pair 1: Ch1 -> L, Ch2 -> R"
    appendInfoLine: "  Pair 2: Ch3 -> L, Ch4 -> R"
    appendInfoLine: "  Pair 3: Ch5 -> L, Ch6 -> R"
    appendInfoLine: "  Pair 4: Ch7 -> L, Ch8 -> R"
elsif output_format = 3
    appendInfoLine: "  Quad 1: Ch1 Ch2 Ch3 Ch4"
    appendInfoLine: "  Quad 2: Ch5 Ch6 Ch7 Ch8"
elsif output_format = 4
    appendInfoLine: "  ch1: Ch1 + Ch5   ch2: Ch2 + Ch6"
    appendInfoLine: "  ch3: Ch3 + Ch7   ch4: Ch4 + Ch8"
else
    appendInfoLine: "  L: Ch1 + Ch3 + Ch5 + Ch7"
    appendInfoLine: "  R: Ch2 + Ch4 + Ch6 + Ch8"
endif

appendInfoLine: ""
appendInfoLine: "Normalisation:"
appendInfoLine: "  Shared gain across all eight processed channels: x",
    ... fixed$(sharedGain, 4), " (from peak ", fixed$(peakAll, 4), ")"
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
# v0.5: the working channels ch[1]-ch[8] are still alive here. The
# waveform panel draws them directly instead of extracting from an
# output object, so it is identical in all five formats.

if draw_visualization

    Erase all

    # Find max/min b for axis scaling
    maxB = b_[1]
    minB = b_[1]
    for i from 2 to 8
        if b_[i] > maxB
            maxB = b_[i]
        endif
        if b_[i] < minB
            minB = b_[i]
        endif
    endfor

    # Max divisor for panel B axis
    maxDiv = divisor[1]
    for i from 2 to 8
        if divisor[i] > maxDiv
            maxDiv = divisor[i]
        endif
    endfor

    # Per-channel colour: blue = forward, red = reversed
    for i from 1 to 8
        if reverse_even_channels and (i mod 2 = 0)
            chR[i] = 0.80
            chG[i] = 0.38
            chB[i] = 0.32
        else
            # Blue, shaded by divisor rank
            intensity = (divisor[i] - 1) / (maxDiv + 1)
            chR[i] = 0.22 + intensity * 0.10
            chG[i] = 0.42 + intensity * 0.08
            chB[i] = 0.78 + intensity * 0.18
            if chB[i] > 1
                chB[i] = 1
            endif
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL COMB DELAY v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$ + revLabel$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  @" + string$(sr) + " Hz"
        ... + "  |  Format: " + formatName$

    # ----------------------------------------------------------
    # PANEL A: DELAY SAMPLES BAR CHART  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.85, 4.34

    axMax = maxB * 1.12
    Axes: 0, axMax, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, axMax, 0.5, 8.5

    # Vertical grid lines
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    gStep = maxB / 4
    if gStep < 1
        gStep = 1
    endif
    gVal = gStep
    while gVal < axMax
        Draw line: gVal, 0.5, gVal, 8.5
        gVal = gVal + gStep
    endwhile

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38

        Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 0, b_[i], yLo, yHi
        Colour: "{0.30, 0.30, 0.30}"
        Line width: 1
        Draw rectangle: 0, b_[i], yLo, yHi

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: -axMax * 0.02, "right", y, "half", "Ch" + string$(i)
        Colour: "White"
        if b_[i] > maxB * 0.12
            Text: b_[i] / 2, "centre", y, "half", string$(b_[i])
        endif
        Colour: "{0.30, 0.30, 0.30}"
        Text: b_[i] + axMax * 0.02, "left", y, "half", "/" + string$(divisor[i])
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Comb delay b (samples)"
    Select outer viewport: 0.08, 0.52, 0.75, 4.6
    Select inner viewport: 0.08, 0.52, 0.77, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Ch"
    Select outer viewport: 0, 4.2, 0.75, 4.6
    Select inner viewport: 0.55, 4, 0.85, 4.34
    Axes: 0, axMax, 0.5, 8.5

    # ----------------------------------------------------------
    # PANEL B: COMB PERIOD IN MS  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48

    # b samples → ms = b / sr * 1000
    maxMs = (maxB / sr) * 1000 * 1.12
    if maxMs < 1
        maxMs = 1
    endif

    Axes: 0, maxMs, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxMs, 0.5, 8.5

    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    msGrid = maxMs / 4
    if msGrid < 0.1
        msGrid = 0.1
    endif
    msVal = msGrid
    while msVal < maxMs
        Draw line: msVal, 0.5, msVal, 8.5
        msVal = msVal + msGrid
    endwhile

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38
        ms = (b_[i] / sr) * 1000

        Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 0, ms, yLo, yHi
        Colour: "{0.30, 0.30, 0.30}"
        Draw rectangle: 0, ms, yLo, yHi

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: -maxMs * 0.02, "right", y, "half", "Ch" + string$(i)
        Colour: "White"
        if ms > maxMs * 0.12
            Text: ms / 2, "centre", y, "half", fixed$(ms, 1) + " ms"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.75, 2.70
    Select inner viewport: 4.02, 4.4, 0.77, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Ch"
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48
    Axes: 0, maxMs, 0.5, 8.5
    Text bottom: "yes", "Comb period (ms)"

    # ----------------------------------------------------------
    # PANEL C: DIRECTION AND OUTPUT ROUTING  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38

    Axes: 0, 10, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 10, 0.5, 8.5

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38
        yMid = y

        # v0.5: where this channel lands in the chosen output format
        if output_format = 1
            route$ = "out" + string$(i)
        elsif output_format = 2
            if i mod 2 = 1
                route$ = "P" + string$((i + 1) / 2) + "L"
            else
                route$ = "P" + string$(i / 2) + "R"
            endif
        elsif output_format = 3
            if i <= 4
                route$ = "Q1"
            else
                route$ = "Q2"
            endif
        elsif output_format = 4
            if i <= 4
                route$ = "out" + string$(i)
            else
                route$ = "out" + string$(i - 4)
            endif
        else
            if i mod 2 = 1
                route$ = "L"
            else
                route$ = "R"
            endif
        endif

        if reverse_even_channels and (i mod 2 = 0)
            # Reversed: draw arrow pointing left
            Paint rectangle: "{0.90, 0.72, 0.70}", 0.3, 9.7, yLo, yHi
            Colour: "{0.70, 0.25, 0.20}"
            Line width: 2
            Draw arrow: 8.5, yMid, 1.5, yMid
            Line width: 1
            Font size: 6
            Colour: "White"
            Text: 5.0, "centre", yMid, "half",
                ... "Ch" + string$(i) + "  REV  /÷" + string$(divisor[i])
                ... + "  → " + route$
        else
            # Forward: draw arrow pointing right
            Paint rectangle: "{0.72, 0.80, 0.90}", 0.3, 9.7, yLo, yHi
            Colour: "{0.20, 0.35, 0.70}"
            Line width: 2
            Draw arrow: 1.5, yMid, 8.5, yMid
            Line width: 1
            Font size: 6
            Colour: "White"
            Text: 5.0, "centre", yMid, "half",
                ... "Ch" + string$(i) + "  fwd  /÷" + string$(divisor[i])
                ... + "  → " + route$
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Direction and routing  (blue = forward,  red = reversed)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Comb delay b (samples) & divisor"
    Text: 6.10, "centre", 7.30, "half", "Period ms (upper) & routing (lower)"

    # ----------------------------------------------------------
    # PANEL D: PROCESSED CHANNELS Ch1 / Ch2 (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72

    # v0.5: drawn from the working channels, not from an output object
    selectObject: ch[1]
    outDurViz = Get total duration
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: ch[2]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: ch[1]
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: ch[2]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Processed channels  (blue = Ch1,  orange = Ch2)"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 7.08
    Select inner viewport: 0.55, 7.72, 6.26, 7.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetName$ + "##" + revLabel$
        ... + "  " + originalName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  " + string$(numSamples) + " smp"
        ... + "  |  @" + string$(sr) + " Hz"

    Text: 0.02, "left", 0.45, "half",
        ... "÷" + string$(divisor[1])
        ... + "  ÷" + string$(divisor[2])
        ... + "  ÷" + string$(divisor[3])
        ... + "  ÷" + string$(divisor[4])
        ... + "  ÷" + string$(divisor[5])
        ... + "  ÷" + string$(divisor[6])
        ... + "  ÷" + string$(divisor[7])
        ... + "  ÷" + string$(divisor[8])
        ... + "  [Ch1–Ch8]"

    Text: 0.02, "left", 0.18, "half",
        ... "Format: " + formatName$
        ... + "  |  " + string$(outCount) + " object"
        ... + " x " + string$(outChannels) + " ch"
        ... + "  |  " + mapLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.18
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# === Cleanup ===
removeObject: monoID
for i from 1 to 8
    removeObject: ch[i]
endfor

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel comb delay"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels, "-channel each"
endif

if play_result
    if outCount = 1
        # One object: play it directly, as v0.3 did.
        selectObject: out[1]
        Play
    else
        # v0.5: playing the first pair or quad alone would present a
        # quarter or a half of the result as the whole.
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview, L = odd channels, R = even channels."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

removeObject: monitorID

# === Select the output object(s) for the user ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
