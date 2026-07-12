# ============================================================
# Praat AudioTools - Fractal_Spectral_Hologram.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
#
# Changelog v1.1 (2026):
#   - FIX (correctness): the blur kernel read self[1, col-k] IN
#     PLACE -- the left taps returned already-smoothed values from
#     the same pass (Formula overwrites left to right). Now
#     ping-pong buffers, making the kernel the true binomial the
#     comment describes. Per the Spectral_Blur v2.1 calibration,
#     the audible footprint of this pattern on contraction kernels
#     is ~0.1 dB: fixed on principle, character unchanged.
#   - FIX: Blur_passes and Sharpen_strength were "positive" form
#     fields whose own comments say "0 = off" -- typing 0 in
#     Custom was rejected by Praat (presets bypassed validation,
#     which is why HolographicFreeze's sharpen 0.0 worked). Now
#     integer / real.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only form compresses the mapping via font margins and
#     collides the two text lines).
#   - Reconstructed sample rate pinned (Override) after the
#     Spectrum -> Sound round-trip.
#   - VERIFIED CORRECT as written: the fractal-zoom accumulation
#     (frozen-source reads, weight normalization), the
#     phase-preserving ratio application, the row-aware dry/wet
#     with channel-mismatch fallback, and the unsharp mask.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creates holographic/crystalline textures by processing the
#   magnitude spectrum directly:
#   - Blur: smooths magnitude across frequency bins (smears harmonics)
#   - Sharpen: accentuates spectral peaks (enhances partials)
#   - Fractal Zoom: remaps frequency bins from a centre point,
#     stretching harmonic series into inharmonic positions
#     (creates bell-like, metallic, crystalline timbres)
#
#   All processing preserves the original phase — only magnitude
#   is transformed.  Single full-file FFT round-trip per channel.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Fractal Spectral Hologram v1.1
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer (light blur + sharpen)
        option Crystal Echo (zoom + sharpen)
        option Fractal Storm (extreme zoom + blur)
        option Holographic Freeze (heavy blur)
        option Metallic Bell (zoom stretches harmonics)
        option Glass Fracture (sharpen + wide zoom)
    comment === Spectral Processing ===
    integer Blur_passes 3
    comment (0 = off, 3 = subtle, 10 = heavy)
    real Sharpen_strength 0.5
    comment (0 = off, 0.5 = moderate, 2.0 = extreme)
    comment === Fractal Zoom ===
    positive Fractal_zoom 1.3
    comment (1.0 = off, 1.3 = subtle, 2.0 = extreme)
    positive Zoom_centre_Hz 1000
    comment (frequency around which zoom expands)
    natural Fractal_iterations 4
    comment (1 = linear, 3-5 = fractal, 8 = deep recursion)
    positive Fractal_decay 0.6
    comment (amplitude of each nested copy: 0.3 = sparse, 0.7 = dense)
    comment === Output ===
    real Dry_wet 0.8
    comment (0 = dry, 1 = full wet)
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    blur_passes = 3
    sharpen_strength = 0.6
    fractal_zoom = 1.15
    zoom_centre_Hz = 800
    fractal_iterations = 3
    fractal_decay = 0.5
    dry_wet = 0.7
    presetName$ = "SubtleShimmer"
elsif preset = 3
    blur_passes = 2
    sharpen_strength = 1.0
    fractal_zoom = 1.3
    zoom_centre_Hz = 1200
    fractal_iterations = 5
    fractal_decay = 0.55
    dry_wet = 0.8
    presetName$ = "CrystalEcho"
elsif preset = 4
    blur_passes = 8
    sharpen_strength = 0.3
    fractal_zoom = 1.5
    zoom_centre_Hz = 500
    fractal_iterations = 6
    fractal_decay = 0.65
    dry_wet = 0.9
    presetName$ = "FractalStorm"
elsif preset = 5
    blur_passes = 15
    sharpen_strength = 0.0
    fractal_zoom = 1.0
    zoom_centre_Hz = 1000
    fractal_iterations = 1
    fractal_decay = 0.5
    dry_wet = 0.8
    presetName$ = "HolographicFreeze"
elsif preset = 6
    blur_passes = 1
    sharpen_strength = 0.8
    fractal_zoom = 1.4
    zoom_centre_Hz = 400
    fractal_iterations = 5
    fractal_decay = 0.6
    dry_wet = 0.85
    presetName$ = "MetallicBell"
elsif preset = 7
    blur_passes = 2
    sharpen_strength = 1.5
    fractal_zoom = 1.6
    zoom_centre_Hz = 2000
    fractal_iterations = 4
    fractal_decay = 0.45
    dry_wet = 0.75
    presetName$ = "GlassFracture"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
numChannels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency
nyquist = sampleRate / 2

# Clamps
if dry_wet < 0
    dry_wet = 0
elsif dry_wet > 1
    dry_wet = 1
endif
if blur_passes < 0
    blur_passes = 0
endif
if sharpen_strength < 0
    sharpen_strength = 0
endif
if fractal_zoom < 0.5
    fractal_zoom = 0.5
elsif fractal_zoom > 4.0
    fractal_zoom = 4.0
endif
if zoom_centre_Hz < 50
    zoom_centre_Hz = 50
elsif zoom_centre_Hz > nyquist - 100
    zoom_centre_Hz = nyquist - 100
endif
if fractal_iterations < 1
    fractal_iterations = 1
endif
if fractal_iterations > 10
    fractal_iterations = 10
endif
if fractal_decay < 0.1
    fractal_decay = 0.1
elsif fractal_decay > 0.9
    fractal_decay = 0.9
endif

clearinfo
writeInfoLine: "=== Fractal Spectral Hologram v1.1 ==="
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Blur passes: ", blur_passes
appendInfoLine: "Sharpen: ", fixed$(sharpen_strength, 2)
appendInfoLine: "Fractal zoom: ", fixed$(fractal_zoom, 2),
    ... "x around ", fixed$(zoom_centre_Hz, 0), " Hz"
appendInfoLine: "Fractal iterations: ", fractal_iterations,
    ... "  decay: ", fixed$(fractal_decay, 2)
appendInfoLine: "Dry/Wet: ", fixed$((1 - dry_wet) * 100, 0), "/",
    ... fixed$(dry_wet * 100, 0), "%"
appendInfoLine: ""

startTime = stopwatch

# ============================================================
# PROCESSING PROCEDURE
# ============================================================
#
# For each channel:
#   1. FFT -> complex Spectrum
#   2. Extract magnitude into a 1-row Matrix
#   3. Apply blur (multi-pass binomial smoothing on magnitude)
#   4. Apply sharpen (unsharp mask: orig + strength*(orig - blurred))
#   5. Apply fractal zoom (remap bins around centre frequency)
#   6. Compute ratio (processed / original magnitude)
#   7. Scale Spectrum re+im by ratio -> preserves phase
#   8. iFFT -> Sound

procedure processChannel: .chID
    selectObject: .chID
    .chDur = Get total duration

    appendInfoLine: "  FFT..."
    To Spectrum: "yes"
    .spec = selected("Spectrum")
    .specStr$ = string$(.spec)
    .nBins = Get number of bins
    .nBinsStr$ = string$(.nBins)
    .binWidth = Get bin width

    # ---- Extract magnitude ----
    Create simple Matrix: "origMag", 1, .nBins, "0"
    .origMag = selected("Matrix")
    Formula: "sqrt(object[" + .specStr$ + ", 1, col]^2"
        ... + " + object[" + .specStr$ + ", 2, col]^2)"
    .origMagStr$ = string$(.origMag)

    # ---- Blur (smooth magnitude) ----
    # v1.1: ping-pong buffers -- the old in-place self[1, col-k]
    # reads returned just-written values (recursive asymmetric
    # smoother, not the documented binomial)
    selectObject: .origMag
    Copy: "processedMag"
    .procMag = selected("Matrix")

    if blur_passes > 0
        appendInfoLine: "  Blur (", blur_passes, " passes)..."
        selectObject: .procMag
        Copy: "blurAlt"
        .blurAlt = selected("Matrix")
        .pmStr$ = string$(.procMag)
        .baStr$ = string$(.blurAlt)
        for .p from 1 to blur_passes
            if .p mod 2 = 1
                .srcStr$ = .pmStr$
                selectObject: .blurAlt
            else
                .srcStr$ = .baStr$
                selectObject: .procMag
            endif
            Formula: "if col > 2 and col < .nBins - 1 then "
                ... + "(object[" + .srcStr$ + ", 1, col-2] + 4*object[" + .srcStr$ + ", 1, col-1]"
                ... + " + 6*object[" + .srcStr$ + ", 1, col]"
                ... + " + 4*object[" + .srcStr$ + ", 1, col+1] + object[" + .srcStr$ + ", 1, col+2]) / 16 "
                ... + "else object[" + .srcStr$ + ", 1, col] endif"
        endfor
        if blur_passes mod 2 = 1
            # final result sits in blurAlt: swap roles
            removeObject: .procMag
            .procMag = .blurAlt
        else
            removeObject: .blurAlt
        endif
    endif

    # ---- Sharpen (unsharp mask) ----
    if sharpen_strength > 0.001
        appendInfoLine: "  Sharpen (", fixed$(sharpen_strength, 2), ")..."
        # sharpened = original + strength * (original - blurred)
        .sharpStr$ = fixed$(sharpen_strength, 4)
        selectObject: .procMag
        Formula: "object[" + .origMagStr$ + ", 1, col] + " + .sharpStr$
            ... + " * (object[" + .origMagStr$ + ", 1, col] - self)"
        # Clamp negative values
        Formula: "max(0, self)"
    endif

    # ---- Fractal Zoom (true multi-scale self-similar iteration) ----
    #
    # Instead of a single linear remap, we layer N scaled copies
    # of the magnitude spectrum on top of itself:
    #
    #   result(f) = original(f) + SUM_{k=1..N} [
    #       decay^k × magnitude( centre + (f - centre) / zoom^k )
    #   ]
    #
    # Each iteration k reads from a more compressed version of the
    # spectrum — harmonics at zoom^k spacing.  The result has
    # genuine spectral self-similarity: each harmonic spawns
    # sub-harmonics that themselves spawn sub-sub-harmonics.
    #
    # Musically: iteration 1 stretches harmonics into bell-like
    # positions.  Iteration 2 adds ghost partials between them.
    # Iteration 3 fills gaps with micro-partials.  The decay
    # parameter controls how dense the fractal nesting becomes.

    if fractal_zoom > 1.001 or fractal_zoom < 0.999
        appendInfoLine: "  Fractal zoom (", fractal_iterations, " iterations,"
            ... + " zoom=", fixed$(fractal_zoom, 2), "x,"
            ... + " decay=", fixed$(fractal_decay, 2), ")..."

        .centreBin = round(zoom_centre_Hz / .binWidth)
        if .centreBin < 1
            .centreBin = 1
        endif
        .cbStr$ = string$(.centreBin)

        # Save the blur/sharpen result as the source for all iterations
        selectObject: .procMag
        Copy: "fractalSource"
        .fracSrc = selected("Matrix")
        .fracSrcStr$ = string$(.fracSrc)

        # Accumulate fractal copies into procMag
        # Start with the original magnitude (weight = 1.0)
        .totalWeight = 1.0

        for .k from 1 to fractal_iterations
            # Scale factor for this iteration: zoom^k
            .scaleFactor = fractal_zoom ^ .k
            .invScale = 1 / .scaleFactor
            .weight = fractal_decay ^ .k
            .totalWeight = .totalWeight + .weight

            .isStr$ = fixed$(.invScale, 8)
            .wStr$ = fixed$(.weight, 6)

            appendInfoLine: "    k=", .k,
                ... "  zoom^k=", fixed$(.scaleFactor, 2),
                ... "  weight=", fixed$(.weight, 3)

            # Add rescaled copy: procMag += weight * source(centre + (col-centre)/zoom^k)
            selectObject: .procMag
            Formula: "self + " + .wStr$
                ... + " * object[" + .fracSrcStr$ + ", 1,"
                ... + " max(1, min(" + .nBinsStr$ + ","
                ... + " round(" + .cbStr$ + " + (col - " + .cbStr$ + ")"
                ... + " * " + .isStr$ + ")))]"
        endfor

        # Normalise by total weight so energy is preserved
        .twStr$ = fixed$(.totalWeight, 6)
        selectObject: .procMag
        Formula: "self / " + .twStr$

        removeObject: .fracSrc
    endif

    # ---- Apply ratio to Spectrum (preserves phase) ----
    appendInfoLine: "  Applying to spectrum..."
    .procMagStr$ = string$(.procMag)

    selectObject: .spec
    Formula: "self * object[" + .procMagStr$ + ", 1, col]"
        ... + " / max(1e-30, object[" + .origMagStr$ + ", 1, col])"

    removeObject: .origMag, .procMag

    # ---- iFFT ----
    appendInfoLine: "  iFFT..."
    selectObject: .spec
    To Sound
    .result = selected("Sound")
    Override sampling frequency: sampleRate
    removeObject: .spec

    # Trim FFT padding
    selectObject: .result
    .rDur = Get total duration
    if .rDur > .chDur
        Extract part: 0, .chDur, "rectangular", 1, "no"
        .trimmed = selected("Sound")
        removeObject: .result
        .result = .trimmed
    endif

    processChannel.result = .result
endproc

# ============================================================
# PROCESS
# ============================================================

appendInfoLine: "Processing..."

if numChannels >= 2
    appendInfoLine: "Channel 1 (L):"
    selectObject: originalID
    Extract one channel: 1
    chL = selected("Sound")
    @processChannel: chL
    wetL = processChannel.result
    removeObject: chL

    appendInfoLine: "Channel 2 (R):"
    selectObject: originalID
    Extract one channel: 2
    chR = selected("Sound")
    @processChannel: chR
    wetR = processChannel.result
    removeObject: chR

    selectObject: wetL
    plusObject: wetR
    Combine to stereo
    wetSound = selected("Sound")
    removeObject: wetL, wetR
else
    appendInfoLine: "Mono:"
    selectObject: originalID
    Copy: "mono_work"
    monoWork = selected("Sound")
    @processChannel: monoWork
    wetSound = processChannel.result
    removeObject: monoWork
endif

# ============================================================
# DRY/WET MIX
# ============================================================

if dry_wet < 0.999
    appendInfoLine: "Mixing dry/wet..."
    wetStr$ = fixed$(dry_wet, 4)
    dryStr$ = fixed$(1 - dry_wet, 4)
    origStr$ = string$(originalID)

    selectObject: wetSound
    wetNch = Get number of channels
    selectObject: originalID
    origNch = Get number of channels

    if wetNch = origNch
        selectObject: wetSound
        Formula: "self * " + wetStr$
            ... + " + object[" + origStr$ + ", row, col] * " + dryStr$
    else
        selectObject: originalID
        origMix = Convert to mono
        origMixStr$ = string$(origMix)
        selectObject: wetSound
        Formula: "self * " + wetStr$
            ... + " + object[" + origMixStr$ + ", col] * " + dryStr$
        removeObject: origMix
    endif
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: wetSound
Scale peak: scale_peak
Rename: originalName$ + "_hologram_" + presetName$
resultID = selected("Sound")

processingTime = stopwatch

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Fractal Spectral Hologram v1.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  zoom=" + fixed$(fractal_zoom, 2)
        ... + "x @" + fixed$(zoom_centre_Hz, 0) + "Hz"
        ... + "  |  " + string$(fractal_iterations) + " iterations"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: originalID
    if numChannels > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn"
        vizIn = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: resultID
    nChRes = Get number of channels
    if nChRes > 1
        Extract one channel: 1
        vizOutL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: resultID
        Extract one channel: 2
        vizOutR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizOutL, vizOutR
    else
        selectObject: resultID
        Colour: "{0.35, 0.58, 0.72}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Input spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.24, 3.64
    Select inner viewport: 0.55, 3.85, 2.34, 3.54
    selectObject: originalID
    if numChannels > 1
        Extract one channel: 1
        vizSpecIn = selected("Sound")
    else
        Copy: "vizSpecIn"
        vizSpecIn = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig, vizSpecIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original spectrogram"

    # ----------------------------------------------------------
    # Output spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.24, 3.64
    Select inner viewport: 4.40, 7.65, 2.34, 3.54
    selectObject: resultID
    if nChRes > 1
        Extract one channel: 1
        vizSpecOut = selected("Sound")
    else
        Copy: "vizSpecOut"
        vizSpecOut = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes, vizSpecOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Hologram spectrogram"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.74, 4.44
    Select inner viewport: 0.55, 7.65, 3.80, 4.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.42, "half",
        ... "Preset: " + presetName$
        ... + "  |  Blur: " + string$(blur_passes)
        ... + "  |  Sharpen: " + fixed$(sharpen_strength, 2)
        ... + "  |  Zoom: " + fixed$(fractal_zoom, 2) + "x"
        ... + " @" + fixed$(zoom_centre_Hz, 0) + "Hz"
        ... + "  |  Iter: " + string$(fractal_iterations)
        ... + "  decay: " + fixed$(fractal_decay, 2)
        ... + "  |  " + fixed$(processingTime, 1) + "s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# OUTPUT
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 1), " s"
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID
