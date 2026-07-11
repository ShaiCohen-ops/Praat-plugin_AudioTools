# ============================================================
# Praat AudioTools - Non-Linear_Frequency_Folding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
#
# Changelog v0.5 (2026):
#   - ADDED stereo output with spectral width. The fold map is
#     IDENTICAL in both channels (coherent pitch image); the
#     modulation comb gets a per-channel phase offset of
#     +/- width*pi/4, so where the left comb dips the right one
#     peaks -- complementary spectral decorrelation at width 1,
#     dual mono at width 0. Mono inputs are folded twice with the
#     offset combs and combined; stereo inputs fold per channel
#     (image preserved) with the same width offsets. Output menu:
#     match input / mono / stereo (wide).
#   - VIZ: spectrogram panel extracts channel 1 of stereo results
#     (To Spectrogram on stereo is a known crash pattern).
#
# Changelog v0.4 (2026):
#   - REMOVED the optimization block (downsampling + chunking),
#     with benchmarks. Whole-file full-rate: 60 s of audio in
#     ~2-3 s, 300 s in ~8-10 s; the "optimized" path saved ~2 s
#     on the 5-minute file while (a) discarding all content above
#     11 kHz BEFORE folding -- the very material the fold
#     relocates downward -- and (b) folding each 10 s chunk
#     independently, so the texture decorrelated at every chunk
#     boundary (and complex-mode time reversal happened per chunk
#     instead of across the whole gesture). Both defaulted ON, so
#     users got the degraded version out of the box. The effect
#     now always processes the whole file at the original rate.
#
# Changelog v0.3.1 (2026):
#   - ADDED Fold_phase mode. v0.3's faithful complex-bin fold
#     revealed the fold's true nature: frequency-mirrored complex
#     segments are TIME-REVERSED audio (X(-f) = conj(X(f))), so
#     alternating bands play backward. That is now the explicit
#     "complex bins" mode; the new default, "magnitude on
#     original phase", relocates only the folded magnitude onto
#     each bin's own phase -- spectral energy moves, time flows
#     forward. Both modes read exclusively from the frozen copy.
#
# Changelog v0.3 (2026):
#   - FIX (audible, three bugs in one formula):
#     (a) self[1, ...] wrote ROW 1 (the real part) into BOTH
#         spectrum rows -- phase destroyed on every run, in both
#         branches (even the "preserved" low band).
#     (b) the folded read was IN PLACE: folded indices land at or
#         below the folding period, i.e. on columns already
#         overwritten earlier in the same Formula pass -- the
#         fold read its own output, not the input (recursive
#         self-composition).
#     (c) col is an FFT BIN index, but the info panel and the
#         folding-map panel both label the parameters in HERTZ --
#         "period 1000" acted at ~100 Hz on a 10 s / 22 kHz
#         chunk, and the effect changed with chunk length.
#     v0.3 reads from a FROZEN copy of the spectrum, row-aware,
#     with Hz-domain arithmetic (x, folded frequency converted to
#     a bin via the spectrum's measured bin width). The quirky
#     round(f/period) reflect map itself is unchanged -- it is
#     what the visualization has always drawn.
#   - FIX: chunked mode concatenated each chunk's FFT PAD (To
#     Sound returns the padded fast-FFT length): ~30 ms of junk
#     between chunks and duration drift; and rectangular butt
#     joins between independently processed chunks clicked.
#     Chunks now overlap by 50 ms with raised-cosine edge fades
#     and Concatenate-with-overlap; pads trimmed; output trimmed
#     to the exact input duration.
#   - FIX: whole-file path never trimmed the FFT pad either
#     (output up to ~20% longer than the input).
#   - FIX: final selection is now consistently original+result
#     (the Play branch used to clobber it).
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Non-linear frequency folding - wraps frequencies around
#   a folding point and modulates with sine/cosine pattern.
#   Creates "knotted" spectral textures.
# ============================================================

form Non-Linear Frequency Folding v0.5
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Tight Knots
        option Loose Knots
        option High Preservation
        option Fast Modulation
        option Metallic
        option Subtle Fold
    
    comment === FOLDING PARAMETERS ===
    optionmenu Fold_phase: 1
        option magnitude on original phase (forward time)
        option complex bins (mirrored bands play time-reversed)
    boolean Fast_fourier 1
    positive Low_freq_threshold 100
    positive Folding_period 1000
    positive Sine_modulation_divisor 300
    positive Cosine_modulation_divisor 150
    
    comment === OUTPUT ===
    optionmenu Output_channels: 1
        option match input
        option mono
        option stereo (wide)
    positive Stereo_width 0.6
    comment (0 = dual mono ... 1 = fully complementary combs)
    positive Scale_peak 0.88
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===================================================================
# PRESETS
# ===================================================================

if preset = 2
    # Tight Knots
    folding_period = 500
    presetName$ = "TightKnots"
elsif preset = 3
    # Loose Knots
    folding_period = 2000
    presetName$ = "LooseKnots"
elsif preset = 4
    # High Preservation
    low_freq_threshold = 500
    presetName$ = "HighPreserve"
elsif preset = 5
    # Fast Modulation
    sine_modulation_divisor = 150
    cosine_modulation_divisor = 75
    presetName$ = "FastMod"
elsif preset = 6
    # Metallic
    folding_period = 300
    sine_modulation_divisor = 100
    cosine_modulation_divisor = 50
    presetName$ = "Metallic"
elsif preset = 7
    # Subtle Fold
    folding_period = 1500
    low_freq_threshold = 300
    sine_modulation_divisor = 500
    cosine_modulation_divisor = 250
    presetName$ = "SubtleFold"
else
    presetName$ = "Custom"
endif

# ===================================================================
# SETUP
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
original_sr = Get sampling frequency
original_duration = Get total duration
num_channels = Get number of channels

clearinfo
writeInfoLine: "=== Non-Linear Frequency Folding v0.5 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 1), " s"
appendInfoLine: "Sample rate: ", original_sr, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Folding period: ", folding_period
appendInfoLine: "Low freq threshold: ", low_freq_threshold
appendInfoLine: ""

# ===================================================================
# CONVERT TO MONO
# ===================================================================

# v0.5: resolve output channels
if output_channels = 2
    outCh = 1
elsif output_channels = 3
    outCh = 2
else
    outCh = num_channels
    if outCh > 2
        outCh = 2
    endif
endif
if stereo_width > 1
    stereo_width = 1
endif
appendInfoLine: "Output: ", outCh, " channel(s)",
    ... if outCh = 2 then " | width " + fixed$(stereo_width, 2) else "" fi

# channel sources: per-channel folding for stereo input + stereo
# out; otherwise a mono mixdown (folded once, or twice with offset
# combs for mono-in stereo-out)
converted_to_mono = 0
perChannelIn = 0
if num_channels > 1 and outCh = 2
    perChannelIn = 1
    selectObject: originalID
    srcCh1 = Extract one channel: 1
    selectObject: originalID
    srcCh2 = Extract one channel: 2
    workingID = srcCh1
else
    workingID = originalID
    if num_channels > 1
        selectObject: originalID
        monoID = Convert to mono
        workingID = monoID
        converted_to_mono = 1
        appendInfoLine: "Converted to mono"
    endif
endif

selectObject: workingID
current_sr = Get sampling frequency

# ===================================================================
# FORMULA (v0.3: built per spectrum -- needs that spectrum's bin
# width and a frozen copy's object id)
# ===================================================================
# out(x) = frozen(fold(x)) * (sin(x/sdiv) + cos(x/cdiv))^2 for
# x >= threshold; identity below. All in Hz; the folded frequency
# is converted to a bin index via dx (bin = f/dx + 1; non-integer
# indices round, same as self[]). Reads come from the FROZEN copy:
# in-place reads returned already-overwritten columns.
thrStr$ = string$(low_freq_threshold)
perStr$ = string$(folding_period)
sdivStr$ = string$(sine_modulation_divisor)
cdivStr$ = string$(cosine_modulation_divisor)

# v0.3.1: two phase modes. The fold map is descending in alternating
# segments, and frequency-mirrored COMPLEX bins are, by X(-f) =
# conj(X(f)), TIME-REVERSED audio in those bands. "complex" keeps
# that (the mathematically literal fold; reversed transients are its
# signature). "magnitude on original phase" relocates only the
# folded bin's magnitude onto each bin's own phase: energy moves,
# time flows forward. Both read exclusively from the frozen copy.

# ===================================================================
# PROCESS (WITH OR WITHOUT CHUNKING)
# ===================================================================

selectObject: workingID
total_duration = Get total duration

# WHOLE FILE PROCESSING (v0.5: one pass per output channel; at
# stereo width w the modulation comb gets phase -w*pi/4 in L and
# +w*pi/4 in R -- complementary combs at w = 1)
appendInfo: "Processing spectrum..."
for pass to outCh
    if perChannelIn
        if pass = 1
            passSrc = srcCh1
        else
            passSrc = srcCh2
        endif
    else
        passSrc = workingID
    endif
    
    if outCh = 2
        if pass = 1
            modPhase = -stereo_width * pi / 4
        else
            modPhase = stereo_width * pi / 4
        endif
    else
        modPhase = 0
    endif
    phStr$ = string$(modPhase)
    
    selectObject: passSrc
    To Spectrum: fast_fourier
    specID = selected("Spectrum")
    dxBin = Get bin width
    frozenSpec = Copy: "frozen_spec"
    frozenStr$ = string$(frozenSpec)
    dxStr$ = string$(dxBin)
    selectObject: specID
    foldIdx$ = "abs(x - 2 * round(x / " + perStr$ + ") * " + perStr$ + ") / " + dxStr$ + " + 1"
    modTerm$ = "(sin(x / " + sdivStr$ + " + " + phStr$ + ") + cos(x / " + cdivStr$ + " + " + phStr$ + ")) ^ 2"
    if fold_phase = 2
        Formula: "if x < " + thrStr$ + " then self else object[" + frozenStr$
        ... + ", row, " + foldIdx$ + "] * " + modTerm$ + " endif"
    else
        Formula: "if x < " + thrStr$ + " then self else "
        ... + "sqrt(object[" + frozenStr$ + ", 1, " + foldIdx$ + "]^2 + object[" + frozenStr$ + ", 2, " + foldIdx$ + "]^2)"
        ... + " * object[" + frozenStr$ + ", row, col]"
        ... + " / sqrt(object[" + frozenStr$ + ", 1, col]^2 + object[" + frozenStr$ + ", 2, col]^2 + 1e-12)"
        ... + " * " + modTerm$ + " endif"
    endif
    removeObject: frozenSpec
    
    selectObject: specID
    To Sound
    paddedID = selected("Sound")
    Override sampling frequency: current_sr
    Extract part: 0, total_duration, "rectangular", 1.0, "no"
    chanOut'pass' = selected("Sound")
    removeObject: paddedID, specID
endfor

if outCh = 2
    selectObject: chanOut1
    plusObject: chanOut2
    processedID = Combine to stereo
    removeObject: chanOut1, chanOut2
else
    processedID = chanOut1
endif
appendInfoLine: " done"
# ===================================================================
# FINALIZE
# ===================================================================

selectObject: processedID
outName$ = originalName$ + "_freqFold_" + presetName$
Rename: outName$
Scale peak: scale_peak

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Frequency Folding: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: processedID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Frequency Folded"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: processedID
    vizNch = Get number of channels
    if vizNch > 1
        vizMonoID = Extract one channel: 1
    else
        vizMonoID = Copy: "viz_mono"
    endif
    resSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    removeObject: vizMonoID
    selectObject: resSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Folded Spectrogram"
    removeObject: resSpecID
    
    # Folding pattern visualization
    Select outer viewport: 0, 8, 4.0, 5.4
    Select inner viewport: 0.6, 7.6, 4.2, 5.2
    
    maxFreq = 5000
    Axes: 0, maxFreq, 0, maxFreq
    
    # Draw folding mapping
    Colour: "{0.9, 0.5, 0.2}"
    Line width: 2
    
    step = 50
    prevF = 0
    # Low freq: identity mapping
    if low_freq_threshold > 0
        Draw line: 0, 0, low_freq_threshold, low_freq_threshold
        prevF = low_freq_threshold
    endif
    
    # Folded region
    f = low_freq_threshold + step
    while f <= maxFreq
        # Folding formula: abs(f - 2 * round(f / period) * period)
        folded = abs(f - 2 * round(f / folding_period) * folding_period)
        if folded < 0
            folded = 0
        endif
        if folded > maxFreq
            folded = maxFreq
        endif
        Draw line: prevF, abs(prevF - 2 * round(prevF / folding_period) * folding_period), f, folded
        prevF = f
        f = f + step
    endwhile
    
    # Mark folding period
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 1
    Dotted line
    p = folding_period
    while p < maxFreq
        Draw line: p, 0, p, maxFreq
        p = p + folding_period
    endwhile
    Solid line
    
    # Mark low freq threshold
    Colour: "{0.2, 0.7, 0.4}"
    Draw line: low_freq_threshold, 0, low_freq_threshold, maxFreq
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text top: "no", "Frequency Folding Map (green=threshold, gray=folding periods)"
    Text left: "yes", "Output (Hz)"
    Text bottom: "yes", "Input Frequency (Hz)"
    
    # Info panel
    Select outer viewport: 0, 8, 5.5, 6.1
    Select inner viewport: 0.5, 7.7, 5.55, 6.05
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Folding: " + string$(folding_period) + " Hz"
    Text: 0.22, "left", 0.5, "half", "Threshold: " + string$(low_freq_threshold) + " Hz"
    Text: 0.45, "left", 0.5, "half", "Sin div: " + string$(sine_modulation_divisor)
    Text: 0.65, "left", 0.5, "half", "Cos div: " + string$(cosine_modulation_divisor)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ===================================================================
# CLEANUP
# ===================================================================

if converted_to_mono
    removeObject: monoID
endif
if perChannelIn
    removeObject: srcCh1, srcCh2
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", outName$

if play_result
    selectObject: processedID
    Play
endif

# v0.3: consistent final selection (Play used to clobber it)
selectObject: originalID
plusObject: processedID