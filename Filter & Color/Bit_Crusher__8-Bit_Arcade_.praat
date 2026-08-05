# ============================================================
# Praat AudioTools - Bit_Crusher__8-Bit_Arcade_.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bit crusher for 8-bit arcade sound. Reduces bit depth and
#   sample rate for lo-fi retro effects.
#
#   Mode 2 is NOT spectral bit crushing. It multiplies each bin by
#   a staircase that depends on the bin's POSITION in the chosen
#   frequency range - it quantizes neither magnitude nor phase nor
#   any spectral word length. It is a stepped filter, and it is
#   named one.
#
# Changelog v0.2:
#   - Fixed preset/mode comparison (number not string)
#   - Fixed Formula variable syntax
#   - Added visualization
#   - Added preset name to output
#   - True stereo processing
#
# Changelog v0.3:
#   - Sample-rate reduction now uses sample-and-hold (true aliasing crush);
#     the old Resample down/up was anti-aliased and only low-passed the sound.
#   - Spectral mode trims FFT zero-padding so output length matches the input.
#
# Changelog v0.4 - reviewed by running the script under Parselmouth,
# so the figures below are measurements. The sample-and-hold and the
# v0.3 length fix both passed (output sample counts matched the input
# at 1, 2, 3, 10, 999, 1000, 1001, 44101 and 50000 samples).
#   - v0.4's quantizer was withdrawn in v0.5; see below.
#   - BIT DEPTH NOW PRODUCES THE PROMISED NUMBER OF LEVELS.
#     round(self * 2^bits) / 2^bits spans -2^bits..+2^bits, giving
#     2 x 2^bits + 1 levels. Measured on a dense ramp: 2-bit gave 9
#     levels instead of 4, 4-bit gave 33 instead of 16, 8-bit gave 513
#     instead of 256, 12-bit gave 8193 instead of 4096 - so "8-bit" was
#     really closer to 9-bit. The quantizer now maps the clamped input
#     onto exactly 2^bits levels spanning -1..+1. The old curve is kept
#     as Quantizer_mode = "Legacy v0.3" for anything already made with it.
#   - Peak normalization is optional and off by default. It ran
#     unconditionally at 0.99, so in 8-bit mode a 0.1-peak sine came
#     back +19.78 dB and a 0.01-peak sine +38.66 dB - a quiet input was
#     amplified by nearly 40 dB, which flattened every preset to the
#     same output peak and lifted quantization noise with it.
#   - Bit depth and sample-rate reduction must be whole numbers, and
#     the rounded value is used for processing, reporting AND the
#     effective-SR readout. v0.3 reported "1.6x" while processing 2x,
#     and reported "1.49x" while processing 1x, i.e. no reduction at all.
#   - Mode 2 renamed Stepped Spectral Shaping. Measured response at
#     200-3000 Hz / 2 steps / 0.5 outside: 100 Hz 0.5, 300 Hz almost 0,
#     1 kHz 0.5, 2 kHz 0.5, 2.5 kHz 1.0, 3.5 kHz 0.5. That is a
#     staircase filter with an internal tilt, not bit crushing. Its
#     step count is also Quantization_steps + 1, which the report now
#     states.
#   - xmin preserved. In spectral mode a Sound at 5.000-6.486 s came
#     back at 0.000-1.486 s. All work now happens on a copy shifted to
#     0 and the result is returned to the source's own time domain.
#   - Every channel is processed and kept. Any non-mono input took a
#     hard-coded two-channel branch, so 4-channel material came back as
#     2 channels with nothing said about it.
#   - Presets each select their own mode, and the ones that were not
#     what their name said are fixed:
#       * Telephone applies a real 300-3400 Hz band limit before
#         crushing. Its frequency values were previously read only in
#         spectral mode, where they produced a tilted staircase rather
#         than a telephone band; in time domain it was exactly
#         "8-bit + 4x hold".
#       * Radio Static renamed Crunch (6-bit): it added no noise,
#         static, crackle, dropout or modulation, and measured
#         identical to Manual at 6-bit / 3x hold.
#       * Heavy and Extreme select time domain, where their bit depth
#         and hold factor actually differ. In spectral mode both set
#         Quantization_steps = 1 and produced identical output.
#   - Validation on bit depth, reduction factor, band order, band
#     frequencies against Nyquist, step count, outside multiplier and
#     the output ceiling. v0.3 accepted Bit_depth = 7.5 and reported
#     "181.01933598375618 levels", and accepted Lower >= Upper by
#     silently multiplying the whole spectrum by the outside multiplier.
#   - Version strings synchronized, the Output line reports the result
#     rather than the source (v0.3 selected both before reading
#     selected$), and the two waveform panels share a Y range so a gain
#     change is visible instead of being auto-scaled away.
#
# Changelog v0.5 - Parselmouth-verified again. The v0.4 level-count fix
# was arithmetically right and audio-functionally wrong, and it is
# withdrawn.
#   - ZERO SURVIVES QUANTIZATION. v0.4 spread exactly 2^bits levels
#     evenly across -1..+1. An EVEN level count symmetric about zero
#     cannot contain zero, so silence landed on the nearest level above
#     it. Measured DC from a silent input: 2-bit +0.3333333, 4-bit
#     +0.0666667, 6-bit +0.015873, 8-bit +0.0039216, 12-bit +0.0002442.
#     With peak normalize on, silence became a constant +0.99. A
#     0.0001-peak sine came out at that same DC level, i.e. lifted by
#     34.9 dB at 8-bit and 73.5 dB at 2-bit. That is what produced
#     clicks entering and leaving silence, low-frequency thump, odd
#     fades and buzz on quiet material.
#     Two correct quantizers replace it:
#       * Symmetric, zero-preserving (default): codes -S..+S with
#         S = 2^(bits-1) - 1, giving 2^bits - 1 levels. -1, 0 and +1
#         all exist, there is no DC offset, and fades behave.
#       * Signed PCM: codes -2^(bits-1) .. 2^(bits-1)-1, exactly 2^bits
#         levels including zero, at the cost of a slightly asymmetric
#         top (max +0.9922 at 8-bit, +0.5 at 2-bit).
#     Legacy v0.3 remains as the third option; it also contains 0.
#     Verified numerically before shipping: both new modes map 0 to
#     exactly 0 at every depth, and the v0.4 formula reproduces the
#     reviewer's measured DC values exactly.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Bit Crusher v0.5
    optionmenu Preset: 1
        option Manual
        option Classic 8-bit
        option Subtle (12-bit)
        option Heavy (4-bit)
        option Extreme (2-bit)
        option Telephone (band-limited)
        option Crunch (6-bit)
    comment === Processing Mode ===
    optionmenu Mode: 1
        option Time Domain (Fast)
        option Stepped Spectral Shaping (not bit crushing)
    comment === Time Domain Parameters ===
    positive Bit_depth 8
    positive Sample_rate_reduction 1
    optionmenu Quantizer_mode: 1
        option Symmetric, zero-preserving (recommended)
        option Signed PCM (exact 2^bits codes)
        option Legacy v0.3 (2 x 2^bits + 1 levels)
    boolean Band_limit_before_crushing 0
    comment === Band / Spectral Parameters ===
    positive Lower_frequency 200
    positive Upper_frequency 3000
    positive Quantization_steps 2
    real Outside_range_multiplier 0.5
    comment === Output ===
    optionmenu Output_level_mode: 1
        option None (leave level as crushed)
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.99
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# Presets
# ============================================================
# Each preset now selects its own mode. v0.3 left the mode on whatever
# the form had, so presets whose parameters belong to one mode were
# routinely run in the other: Heavy and Extreme both set
# Quantization_steps = 1 and were byte-identical in spectral mode, and
# Telephone's band was ignored entirely in time domain.
if preset = 2
    # Classic 8-bit
    mode = 1
    bit_depth = 8
    sample_rate_reduction = 1
    quantization_steps = 2
    band_limit_before_crushing = 0
    presetName$ = "8bit"
elsif preset = 3
    # Subtle (12-bit)
    mode = 1
    bit_depth = 12
    sample_rate_reduction = 1
    quantization_steps = 4
    band_limit_before_crushing = 0
    presetName$ = "12bit"
elsif preset = 4
    # Heavy (4-bit)
    mode = 1
    bit_depth = 4
    sample_rate_reduction = 2
    quantization_steps = 1
    band_limit_before_crushing = 0
    presetName$ = "4bit"
elsif preset = 5
    # Extreme (2-bit)
    mode = 1
    bit_depth = 2
    sample_rate_reduction = 4
    quantization_steps = 1
    band_limit_before_crushing = 0
    presetName$ = "2bit"
elsif preset = 6
    # Telephone: a real 300-3400 Hz band limit, then the crush.
    mode = 1
    bit_depth = 8
    sample_rate_reduction = 4
    lower_frequency = 300
    upper_frequency = 3400
    band_limit_before_crushing = 1
    presetName$ = "Telephone"
elsif preset = 7
    # Crunch (6-bit). Renamed from "Radio Static", which added no
    # noise, static, crackle or dropout and measured identical to
    # Manual at 6-bit / 3x hold.
    mode = 1
    bit_depth = 6
    sample_rate_reduction = 3
    band_limit_before_crushing = 0
    presetName$ = "Crunch6bit"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup and validation
# ============================================================
selectObject: originalSound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2

# Whole numbers, resolved ONCE and used for processing, reporting and
# the effective-SR readout alike.
bitDepth = round(bit_depth)
if abs(bit_depth - bitDepth) > 1e-9
    exitScript: "Bit_depth must be a whole number (got " + fixed$(bit_depth, 4) +
    ... "). v0.3 accepted 7.5 and reported 181.01933598375618 levels."
endif
if bitDepth < 1 or bitDepth > 24
    exitScript: "Bit_depth must be between 1 and 24 (got " + string$(bitDepth) + ")."
endif

reductionFactor = round(sample_rate_reduction)
if abs(sample_rate_reduction - reductionFactor) > 1e-9
    exitScript: "Sample_rate_reduction must be a whole number (got " +
    ... fixed$(sample_rate_reduction, 4) + "). v0.3 reported the value you typed and " +
    ... "processed the rounded one, so 1.49x meant no reduction at all."
endif
if reductionFactor < 1
    exitScript: "Sample_rate_reduction must be at least 1 (got " + string$(reductionFactor) + ")."
endif

if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(ceiling_peak, 3) + ")."
endif

if mode = 2 or band_limit_before_crushing
    if lower_frequency >= upper_frequency
        exitScript: "Lower_frequency (" + fixed$(lower_frequency, 0) + " Hz) must be below " +
        ... "Upper_frequency (" + fixed$(upper_frequency, 0) + " Hz). v0.3 accepted this and " +
        ... "silently multiplied the whole spectrum by the outside multiplier."
    endif
    if lower_frequency >= nyquist
        exitScript: "Lower_frequency (" + fixed$(lower_frequency, 0) + " Hz) is at or above " +
        ... "Nyquist (" + fixed$(nyquist, 0) + " Hz)."
    endif
    upperClamped = 0
    if upper_frequency > nyquist
        upper_frequency = nyquist
        upperClamped = 1
    endif
endif

if mode = 2
    qSteps = round(quantization_steps)
    if abs(quantization_steps - qSteps) > 1e-9 or qSteps < 1
        exitScript: "Quantization_steps must be a whole number of at least 1 (got " +
        ... fixed$(quantization_steps, 4) + ")."
    endif
    quantization_steps = qSteps
    if outside_range_multiplier < 0
        exitScript: "Outside_range_multiplier must be 0 or greater (got " +
        ... fixed$(outside_range_multiplier, 3) + "); negative values invert polarity."
    endif
endif

# ============================================================
# Quantizer
# ============================================================
# Zero has to survive quantization. v0.4 spread exactly 2^bits levels
# evenly across -1..+1, which is arithmetically what "8-bit" promises
# but audio-functionally wrong: an EVEN level count symmetric about
# zero cannot contain zero, so silence landed on the nearest level
# above it. Measured DC out of a silent input: 2-bit +0.3333333,
# 4-bit +0.0666667, 6-bit +0.015873, 8-bit +0.0039216, 12-bit
# +0.0002442 - and with peak normalize on, silence became +0.99. A
# 0.0001-peak sine came out at the same DC, i.e. amplified by up to
# 73.5 dB. Both replacements below map 0 to exactly 0.
if quantizer_mode = 1
    # Symmetric: codes -S..+S, so -1, 0 and +1 all exist. 2^bits - 1
    # levels rather than 2^bits - one fewer than the nominal word
    # length, which is the standard trade for a symmetric audio
    # quantizer.
    quantScale = 2 ^ (bitDepth - 1) - 1
    if quantScale < 1
        quantScale = 1
    endif
    quantLevels = 2 * quantScale + 1
    quantName$ = "symmetric, zero-preserving"
elsif quantizer_mode = 2
    # Signed PCM: codes -2^(b-1) .. 2^(b-1)-1, exactly 2^bits levels
    # including zero. Slightly asymmetric at the extremes (the most
    # positive value is 1 - 1/S), which is negligible at 8-bit and
    # audible at 2-bit.
    quantScale = 2 ^ (bitDepth - 1)
    quantLevels = 2 ^ bitDepth
    quantName$ = "signed PCM"
else
    quantLevels = 2 * (2 ^ bitDepth) + 1
    quantName$ = "legacy v0.3"
endif

# ============================================================
# Info
# ============================================================
clearinfo
writeInfoLine: "=== Bit Crusher v0.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 3), " s, ",
    ... numChannels, " ch, ", sampleRate, " Hz)"
appendInfoLine: ""

if mode = 1
    appendInfoLine: "Mode: Time Domain (Fast)"
    appendInfoLine: "Bit depth: ", bitDepth, " (", quantLevels, " levels, ", quantName$, ")"
    if quantizer_mode = 1
        appendInfoLine: "  Silence maps to exactly 0. This is 2^bits - 1 levels: an even"
        appendInfoLine: "  count symmetric about zero cannot include zero."
        if bitDepth = 1
            appendInfoLine: "  At 1 bit the scale floors at 1, so this is the same 3 levels as 2-bit."
        endif
    elsif quantizer_mode = 2
        appendInfoLine: "  Silence maps to exactly 0. Codes run -", quantScale, " to ",
            ... quantScale - 1, ", so the most positive value is ",
            ... fixed$((quantScale - 1) / quantScale, 6), " rather than 1."
    else
        appendInfoLine: "  Legacy quantizer: 2 x 2^bits + 1 levels, not 2^bits, and it does"
        appendInfoLine: "  contain 0, so silence is preserved."
    endif
    appendInfoLine: "Sample rate reduction: ", reductionFactor, "x (effective ",
        ... round(sampleRate / reductionFactor), " Hz)"
    if band_limit_before_crushing
        appendInfoLine: "Band limit before crushing: ", round(lower_frequency), " - ",
            ... round(upper_frequency), " Hz"
    endif
else
    appendInfoLine: "Mode: Stepped Spectral Shaping"
    appendInfoLine: "  Not bit crushing: each bin is multiplied by a staircase that"
    appendInfoLine: "  depends on its POSITION in the range below. No magnitude, phase"
    appendInfoLine: "  or spectral word length is quantized."
    appendInfoLine: "Frequency range: ", round(lower_frequency), " - ",
        ... round(upper_frequency), " Hz"
    appendInfoLine: "Steps: ", quantization_steps, " (which gives ", quantization_steps + 1,
        ... " gain levels, from 0 to 1)"
    appendInfoLine: "Outside the range: x", fixed$(outside_range_multiplier, 3)
    if upperClamped
        appendInfoLine: "  Upper frequency clamped to Nyquist"
    endif
endif
appendInfoLine: ""

# ============================================================
# Work copy at time 0
# ============================================================
# Spectral mode rebuilds the Sound through To Spectrum / To Sound,
# which returns a domain starting at 0: a Sound at 5.000-6.486 s came
# back at 0.000-1.486 s. The zoom panels also query a fixed 0..zoomEnd
# range. Working at 0 and restoring the domain at the end covers both.
selectObject: originalSound
workSound = Copy: "bc_work"
Shift times to: "start time", 0

# ============================================================
# Processing procedure for a single channel
# ============================================================
procedure processChannel: .inputSound
    selectObject: .inputSound

    if mode = 1
        # ========================================
        # TIME DOMAIN BIT CRUSHING
        # ========================================

        # Optional band limit, so Telephone is actually band-limited
        if band_limit_before_crushing
            selectObject: .inputSound
            .filtered = Filter (pass Hann band): lower_frequency, upper_frequency, 100
            removeObject: .inputSound
            .work = .filtered
        else
            .work = .inputSound
        endif

        selectObject: .work
        if quantizer_mode = 1
            # Symmetric about zero: silence stays silence.
            .s$ = string$(quantScale)
            Formula: "round(min(1, max(-1, self)) * " + .s$ + ") / " + .s$
        elsif quantizer_mode = 2
            # Signed PCM codes, clamped to -S .. S-1.
            .s$ = string$(quantScale)
            .top$ = string$(quantScale - 1)
            Formula: "min(" + .top$ + ", max(-" + .s$ + ", round(min(1, max(-1, self)) * " +
                ... .s$ + "))) / " + .s$
        else
            # v0.3 curve: round(self * 2^bits) / 2^bits, which spans
            # -2^bits..+2^bits, i.e. 2 x 2^bits + 1 levels (measured 9
            # for 2-bit, 33 for 4-bit, 513 for 8-bit). Kept for material
            # already made with it.
            .q$ = string$(2 ^ bitDepth)
            Formula: "round(self * " + .q$ + ") / " + .q$
        endif

        # Sample-and-hold decimation: holds each block of N samples, the
        # aliased stair-step of a real bit crusher. (Praat's Resample is
        # anti-aliased, so down+up resampling would only muffle it.)
        if reductionFactor > 1
            .srRed$ = string$(reductionFactor)
            Formula: "self[col - ((col - 1) mod " + .srRed$ + ")]"
        endif

        processedSound = .work

    else
        # ========================================
        # STEPPED SPECTRAL SHAPING
        # ========================================
        selectObject: .inputSound
        .origDur = Get total duration
        To Spectrum: "yes"
        .spectrum = selected("Spectrum")

        lowF$ = string$(lower_frequency)
        highF$ = string$(upper_frequency)
        qSteps$ = string$(quantization_steps)
        outMult$ = string$(outside_range_multiplier)

        # Real and imaginary parts take the same gain, so phase survives.
        Formula: "if x >= " + lowF$ + " and x <= " + highF$ + " then self * (round(" +
            ... qSteps$ + " * (x - " + lowF$ + ") / (" + highF$ + " - " + lowF$ + ")) / " +
            ... qSteps$ + ") else self * " + outMult$ + " endif"

        To Sound
        .padded = selected("Sound")

        # To Spectrum: "yes" zero-pads to a power of 2, so To Sound is
        # longer than the input -- trim back to the original duration.
        Extract part: 0, .origDur, "rectangular", 1, "no"
        .result = selected("Sound")

        removeObject: .spectrum, .inputSound, .padded
        processedSound = .result
    endif

    selectObject: processedSound
endproc

# ============================================================
# Main processing
# ============================================================
appendInfoLine: "Processing..."

if numChannels = 1
    selectObject: workSound
    chCopy = Copy: "work_mono"
    @processChannel: chCopy
    finalOutput = processedSound
else
    # Every channel is processed and kept. v0.3 extracted exactly
    # channels 1 and 2 for any non-mono input, so a 4-channel file came
    # back as 2 channels with no warning.
    for ch from 1 to numChannels
        selectObject: workSound
        chIn[ch] = Extract one channel: ch
        @processChannel: chIn[ch]
        chOut[ch] = selected("Sound")
        appendInfo: "."
    endfor
    appendInfoLine: ""

    # Row-write assembly: takes any channel count, unlike Combine to
    # stereo, which caps at two.
    selectObject: chOut[1]
    outDurCh = Get total duration
    Create Sound from formula: "bc_multi", numChannels, 0, outDurCh, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to numChannels
        selectObject: finalOutput
        Formula (part): 0, outDurCh, ch, ch,
            ... "object[" + string$(chOut[ch]) + ", 1, col]"
    endfor
    for ch from 1 to numChannels
        removeObject: chOut[ch]
    endfor
endif

# ============================================================
# Output level stage
# ============================================================
selectObject: finalOutput
pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

if output_level_mode = 2
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

selectObject: finalOutput
out_peak = Get absolute extremum: 0, 0, "None"

# ============================================================
# Visualization  (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    Erase all

    # Shared Y range, so a level change between the two panels is
    # visible rather than being auto-scaled away by Draw: 0,0,0,0.
    selectObject: workSound
    origPeakViz = Get absolute extremum: 0, 0, "None"
    vizMax = max(origPeakViz, out_peak)
    if vizMax < 0.001
        vizMax = 0.001
    endif
    vizAmp = vizMax * 1.15

    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Bit Crusher##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if mode = 1
        Text: 0.5, "centre", -0.30, "half",
            ... originalName$ + "  |  " + presetName$
            ... + "  |  " + string$(bitDepth) + "-bit (" + string$(quantLevels) + " levels)"
            ... + "  |  " + string$(reductionFactor) + "x hold"
    else
        Text: 0.5, "centre", -0.30, "half",
            ... originalName$ + "  |  " + presetName$
            ... + "  |  stepped spectral " + string$(round(lower_frequency)) + "-"
            ... + string$(round(upper_frequency)) + " Hz"
            ... + "  |  " + string$(quantization_steps + 1) + " gain levels"
    endif

    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.7, 0.75, 1.9
    selectObject: workSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    # Crushed waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.7, 2.25, 3.4
    selectObject: finalOutput
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Crushed"
    Text bottom: "yes", "Time (s)"

    # Zoomed comparison (first 50 ms), same shared Y range
    zoomEnd = min(0.05, duration)

    Select outer viewport: 0, 4, 3.7, 5.2
    Select inner viewport: 0.6, 3.6, 3.9, 5.1
    selectObject: workSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, zoomEnd, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Orig"
    Text top: "no", "Zoomed (first " + fixed$(zoomEnd * 1000, 0) + " ms)"

    Select outer viewport: 4, 8, 3.7, 5.2
    Select inner viewport: 4.4, 7.7, 3.9, 5.1
    selectObject: finalOutput
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, zoomEnd, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Crush"
    Text bottom: "yes", "Time (s)"

    # Summary panel
    Select outer viewport: 0, 8, 5.4, 6.5
    Select inner viewport: 0.6, 7.7, 5.5, 6.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if output_level_mode = 1
        levelStr$ = "none"
    elsif output_level_mode = 2
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2) + " (" + level_action$ + ")"
    else
        levelStr$ = "normalized to " + fixed$(ceiling_peak, 2)
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    if mode = 1
        Text: 0.02, "left", 0.52, "half",
            ... "Time domain  |  Bit depth: " + string$(bitDepth)
            ... + " (" + string$(quantLevels) + " levels, " + quantName$ + ")"
            ... + "  |  Hold: " + string$(reductionFactor) + "x"
            ... + "  |  Effective SR: " + string$(round(sampleRate / reductionFactor)) + " Hz"
    else
        Text: 0.02, "left", 0.52, "half",
            ... "Stepped spectral shaping (not bit crushing)  |  Range: "
            ... + string$(round(lower_frequency)) + "-" + string$(round(upper_frequency)) + " Hz"
            ... + "  |  " + string$(quantization_steps + 1) + " gain levels"
            ... + "  |  Outside: x" + fixed$(outside_range_multiplier, 2)
    endif
    Text: 0.02, "left", 0.20, "half",
        ... "Peak in: " + fixed$(origPeakViz, 4)
        ... + "  |  Peak before output stage: " + fixed$(pre_level_peak, 4)
        ... + "  |  Peak out: " + fixed$(out_peak, 4)
        ... + "  |  Level: " + levelStr$
        ... + "  |  Channels: " + string$(numChannels)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: finalOutput
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_crushed_" + presetName$
finalName$ = selected$("Sound")

removeObject: workSound

appendInfoLine: "Done!"
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
# v0.3 selected the source and the result together and then read
# selected$("Sound"), which reported the SOURCE name.
appendInfoLine: "Output: ", finalName$
appendInfoLine: "  Peak before output stage: ", fixed$(pre_level_peak, 4)
if output_level_mode = 1
    appendInfoLine: "  Output stage: none"
elsif output_level_mode = 2
    appendInfoLine: "  Output stage: safety ceiling ", fixed$(ceiling_peak, 2), " - ", level_action$
else
    appendInfoLine: "  Output stage: peak normalize to ", fixed$(ceiling_peak, 2),
        ... " (x", fixed$(level_gain, 4), ")"
    appendInfoLine: "  NOTE: a quiet input is lifted a long way by this - a 0.01-peak"
    appendInfoLine: "        sine measured +38.66 dB in 8-bit mode."
endif
if output_level_mode <> 3 and out_peak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput
