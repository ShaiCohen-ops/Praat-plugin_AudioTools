# ============================================================
# Praat AudioTools - Fractal_Spectral_Hologram.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
#
# Changelog v1.2 (2026):
#   - MUSICAL PRIORITY / GEOMETRY: v1.1's centre conversion sits one FFT bin
#     below the requested Hz value because Spectrum col 1 = 0 Hz. Correcting
#     it can materially change the nearest-bin texture across many remapped
#     bins, so the v1.1 geometry remains the DEFAULT. New Exact_zoom_centre
#     aligns the axis to the nearest true Hz bin when precise mapping is wanted.
#   - FIX (custom contraction): zoom factors below 1 no longer clamp
#     out-of-range source lookups to DC/Nyquist. Those copies are zero-filled
#     outside the source spectrum, preventing broad edge-bin shelves.
#   - FIX (dead custom control): Sharpen now works when Blur passes = 0 by
#     constructing a one-pass binomial reference only for the unsharp mask.
#     All shipped presets keep their existing blur-reference behaviour.
#   - NOMENCLATURE: Fractal iterations -> Fractal levels. The engine layers
#     geometrically scaled copies from one frozen source spectrum; it is
#     self-similar / fractal-inspired, not recursive generation-to-generation.
#   - DOCUMENTATION: weighted magnitude normalization is described as such;
#     it is not an energy-conservation law.
#   - VIZ: replaced generic before/after spectrograms with the actual frequency
#     scaling law and a measured dry-vs-pure-wet spectrum. The figure now shows
#     the mechanism that creates the crystalline copies.
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
#   - Fractal Zoom: layers geometrically scaled magnitude copies around a
#     centre frequency, producing self-similar / fractal-inspired spectra
#     (bell-like, metallic, crystalline timbres).
#
#   The term "hologram" is a musical metaphor, not an optical holography model.
#   All processing preserves the source FFT phase — only magnitude is
#   transformed. Single full-file FFT round-trip per channel.
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

form Fractal Spectral Hologram v1.2
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer (light zoom + detail sharpen)
        option Crystal Echo (zoom + sharpen)
        option Fractal Storm (extreme zoom + broad-detail sharpen)
        option Holographic Freeze (heavy blur)
        option Metallic Bell (zoom stretches harmonics)
        option Glass Fracture (strong sharpen + wide zoom)
    comment === Spectral Processing ===
    integer Blur_passes 3
    comment (0 = off; with Sharpen > 0, passes set the blur-reference scale)
    real Sharpen_strength 0.5
    comment (0 = off, 0.5 = moderate, 2.0 = extreme)
    comment === Fractal Zoom ===
    positive Fractal_zoom 1.3
    comment (<1 = contraction, 1 = off, >1 = expansion)
    real Zoom_centre_Hz 1000
    comment (frequency axis around which scaled copies are placed)
    boolean Exact_zoom_centre 0
    comment (off = v1.1 bin character; on = nearest true-Hz FFT bin)
    natural Fractal_levels 4
    comment (number of geometric copy levels; not recursive generations)
    real Fractal_decay 0.6
    comment (weight per level: decay^k; 0 = no copies, 0.7 = dense)
    comment === Output ===
    real Dry_wet 0.8
    comment (0 = dry, 1 = full wet)
    real Scale_peak 0.95
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
    fractal_levels = 3
    fractal_decay = 0.5
    dry_wet = 0.7
    presetName$ = "SubtleShimmer"
elsif preset = 3
    blur_passes = 2
    sharpen_strength = 1.0
    fractal_zoom = 1.3
    zoom_centre_Hz = 1200
    fractal_levels = 5
    fractal_decay = 0.55
    dry_wet = 0.8
    presetName$ = "CrystalEcho"
elsif preset = 4
    blur_passes = 8
    sharpen_strength = 0.3
    fractal_zoom = 1.5
    zoom_centre_Hz = 500
    fractal_levels = 6
    fractal_decay = 0.65
    dry_wet = 0.9
    presetName$ = "FractalStorm"
elsif preset = 5
    blur_passes = 15
    sharpen_strength = 0.0
    fractal_zoom = 1.0
    zoom_centre_Hz = 1000
    fractal_levels = 1
    fractal_decay = 0.5
    dry_wet = 0.8
    presetName$ = "HolographicFreeze"
elsif preset = 6
    blur_passes = 1
    sharpen_strength = 0.8
    fractal_zoom = 1.4
    zoom_centre_Hz = 400
    fractal_levels = 5
    fractal_decay = 0.6
    dry_wet = 0.85
    presetName$ = "MetallicBell"
elsif preset = 7
    blur_passes = 2
    sharpen_strength = 1.5
    fractal_zoom = 1.6
    zoom_centre_Hz = 2000
    fractal_levels = 4
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

# Validation / bounded musical controls
if dry_wet < 0 or dry_wet > 1
    exitScript: "Dry/Wet must be between 0 and 1."
endif
if blur_passes < 0
    exitScript: "Blur passes must be 0 or greater."
endif
if sharpen_strength < 0
    exitScript: "Sharpen strength must be 0 or greater."
endif
if fractal_zoom < 0.5 or fractal_zoom > 4.0
    exitScript: "Fractal zoom must be between 0.5 and 4.0."
endif
if fractal_levels < 1 or fractal_levels > 10
    exitScript: "Fractal levels must be between 1 and 10."
endif
if fractal_decay < 0 or fractal_decay >= 1
    exitScript: "Fractal decay must be >= 0 and < 1."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be > 0 and <= 1."
endif
if sampleRate < 400
    exitScript: "Sample rate is too low for this spectral processor."
endif

# The centre can legitimately sit at DC or Nyquist. Presets are authored for
# normal audio rates, so clamp only when the source Nyquist makes one impossible.
centreClampNote$ = ""
if zoom_centre_Hz < 0
    zoom_centre_Hz = 0
    centreClampNote$ = "Zoom centre clamped to 0 Hz."
elsif zoom_centre_Hz > nyquist
    zoom_centre_Hz = nyquist
    centreClampNote$ = "Zoom centre clamped to Nyquist (" + fixed$(nyquist, 1) + " Hz)."
endif

clearinfo
writeInfoLine: "=== Fractal Spectral Hologram v1.2 ==="
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Blur passes: ", blur_passes
appendInfoLine: "Sharpen: ", fixed$(sharpen_strength, 2)
appendInfoLine: "Fractal zoom: ", fixed$(fractal_zoom, 2),
    ... "x around ", fixed$(zoom_centre_Hz, 0), " Hz"
if exact_zoom_centre
    appendInfoLine: "Zoom centre geometry: exact nearest-Hz FFT bin"
else
    appendInfoLine: "Zoom centre geometry: legacy v1.1 bin character"
endif
appendInfoLine: "Fractal levels: ", fractal_levels,
    ... "  decay: ", fixed$(fractal_decay, 2)
if centreClampNote$ <> ""
    appendInfoLine: centreClampNote$
endif
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
#   3. Build multi-pass binomial blur (output if sharpen=0; otherwise reference)
#   4. Apply sharpen (unsharp mask against that blur reference)
#   5. Apply multi-scale zoom copies around the centre frequency
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
    # Spectrum column 1 is 0 Hz. v1.1 omitted the +1 and therefore placed
    # the axis one FFT bin low. That nearest-bin geometry has an audible
    # texture in multi-level remapping, so preserve it by default and offer
    # exact-centre mapping explicitly rather than silently changing presets.
    if exact_zoom_centre
        .centreCol = round(zoom_centre_Hz / .binWidth) + 1
    else
        .centreCol = round(zoom_centre_Hz / .binWidth)
    endif
    .centreCol = max(1, min(.nBins, .centreCol))
    .centreHzActual = (.centreCol - 1) * .binWidth

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
        .sharpStr$ = fixed$(sharpen_strength, 4)

        if blur_passes = 0
            # In v1.1 Sharpen was a dead control when Blur=0 because procMag
            # equalled origMag. Make one binomial reference pass ONLY for the
            # unsharp mask; presets with Blur>0 are unchanged.
            selectObject: .origMag
            Copy: "sharpRef"
            .sharpRef = selected("Matrix")
            .srStr$ = string$(.sharpRef)
            selectObject: .sharpRef
            Formula: "if col > 2 and col < .nBins - 1 then "
                ... + "(object[" + .origMagStr$ + ",1,col-2] + 4*object[" + .origMagStr$ + ",1,col-1]"
                ... + " + 6*object[" + .origMagStr$ + ",1,col] + 4*object[" + .origMagStr$ + ",1,col+1]"
                ... + " + object[" + .origMagStr$ + ",1,col+2]) / 16 else object[" + .origMagStr$ + ",1,col] fi"
            selectObject: .procMag
            Formula: "object[" + .origMagStr$ + ",1,col] + " + .sharpStr$
                ... + " * (object[" + .origMagStr$ + ",1,col] - object[" + .srStr$ + ",1,col])"
            removeObject: .sharpRef
        else
            # Preserve the established preset sound: the multi-pass blurred
            # magnitude is the reference scale for the unsharp mask.
            selectObject: .procMag
            Formula: "object[" + .origMagStr$ + ", 1, col] + " + .sharpStr$
                ... + " * (object[" + .origMagStr$ + ", 1, col] - self)"
        endif
        Formula: "max(0, self)"
    endif

    # ---- Fractal Zoom (multi-scale geometric copies) ----
    #
    # From ONE frozen post-blur/sharpen magnitude spectrum M, layer N
    # geometrically scaled copies:
    #
    #   M_out(f) = [ M(f) + SUM_{k=1..N} d^k M(c + (f-c)/z^k) ]
    #              / [ 1 + SUM d^k ]
    #
    # Hence a source feature at f_s appears at
    #   f_k = c + z^k (f_s - c), weight d^k.
    #
    # This is self-similar / fractal-inspired multi-scale superposition,
    # not recursive generation-to-generation feedback. The denominator is a
    # weighted MAGNITUDE average to control level growth; it does not conserve
    # spectral energy exactly. For z<1, copies that map beyond 0..Nyquist are
    # zero-filled rather than clamped to edge bins.

    if fractal_zoom > 1.001 or fractal_zoom < 0.999
        appendInfoLine: "  Fractal zoom (", fractal_levels, " levels,"
            ... + " zoom=", fixed$(fractal_zoom, 2), "x,"
            ... + " decay=", fixed$(fractal_decay, 2), ")..."

        .centreBin = .centreCol
        .cbStr$ = string$(.centreBin)

        # Save the blur/sharpen result as the source for all levels
        selectObject: .procMag
        Copy: "fractalSource"
        .fracSrc = selected("Matrix")
        .fracSrcStr$ = string$(.fracSrc)

        # Accumulate fractal copies into procMag
        # Start with the original magnitude (weight = 1.0)
        .totalWeight = 1.0

        for .k from 1 to fractal_levels
            # Scale factor for this level: zoom^k
            .scaleFactor = fractal_zoom ^ .k
            .invScale = 1 / .scaleFactor
            .weight = fractal_decay ^ .k
            .totalWeight = .totalWeight + .weight

            .isStr$ = fixed$(.invScale, 8)
            .wStr$ = fixed$(.weight, 6)

            appendInfoLine: "    k=", .k,
                ... "  zoom^k=", fixed$(.scaleFactor, 2),
                ... "  weight=", fixed$(.weight, 3)

            # Add rescaled copy. Out-of-range lookups are ZERO, not clamped to
            # DC/Nyquist (important for contraction z<1).
            selectObject: .procMag
            .mapExpr$ = "round(" + .cbStr$ + " + (col - " + .cbStr$ + ") * " + .isStr$ + ")"
            Formula: "self + " + .wStr$ + " * (if " + .mapExpr$ + " >= 1 and "
                ... + .mapExpr$ + " <= " + .nBinsStr$ + " then object[" + .fracSrcStr$
                ... + ",1," + .mapExpr$ + "] else 0 fi)"
        endfor

        # Normalise by total COPY WEIGHT (magnitude-average control, not energy conservation)
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
    processChannel.binWidth = .binWidth
    processChannel.centreHzActual = .centreHzActual
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

# Grid metadata is identical for L/R because both channels share duration/SR.
fftBinWidth = processChannel.binWidth
actualCentreHz = processChannel.centreHzActual
appendInfoLine: "FFT bin width: ", fixed$(fftBinWidth, 4), " Hz; actual zoom axis: ", fixed$(actualCentreHz, 2), " Hz"

# Preserve pure first-channel dry/wet references only for the process figure.
# These copies never feed the audio path.
if draw_visualization
    selectObject: originalID
    if numChannels > 1
        Extract one channel: 1
        vizDryID = selected("Sound")
    else
        Copy: "viz_dry"
        vizDryID = selected("Sound")
    endif
    selectObject: wetSound
    wetVizNch = Get number of channels
    if wetVizNch > 1
        Extract one channel: 1
        vizWetID = selected("Sound")
    else
        Copy: "viz_wet"
        vizWetID = selected("Sound")
    endif
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
    appendInfoLine: "Drawing process visualization..."

    # Measured spectra from channel 1: pristine source vs PURE wet, before
    # dry/wet mixing and final peak scaling. This isolates the spectral operator.
    selectObject: vizDryID
    drySpec = To Spectrum: "yes"
    selectObject: vizWetID
    wetSpec = To Spectrum: "yes"

    vizFreqMax = min(nyquist, 16000)
    if vizFreqMax < 1000
        vizFreqMax = nyquist
    endif

    # Band-average both spectra on one common relative-dB scale.
    nBands = 180
    dryDb# = zero#(nBands)
    wetDb# = zero#(nBands)
    maxDensity = 1e-30
    strongestDryDensity = -1
    strongestDryHz = 0
    for q from 1 to nBands
        fLo = vizFreqMax * (q - 1) / nBands
        fHi = vizFreqMax * q / nBands
        selectObject: drySpec
        dDen = Get band density: fLo, fHi
        selectObject: wetSpec
        wDen = Get band density: fLo, fHi
        if dDen = undefined or dDen <= 0
            dDen = 1e-30
        endif
        if wDen = undefined or wDen <= 0
            wDen = 1e-30
        endif
        dryDb#[q] = dDen
        wetDb#[q] = wDen
        if dDen > maxDensity
            maxDensity = dDen
        endif
        if wDen > maxDensity
            maxDensity = wDen
        endif
        if dDen > strongestDryDensity
            strongestDryDensity = dDen
            strongestDryHz = (fLo + fHi) / 2
        endif
    endfor
    for q from 1 to nBands
        dryDb#[q] = max(-80, 10 * log10(dryDb#[q] / maxDensity))
        wetDb#[q] = max(-80, 10 * log10(wetDb#[q] / maxDensity))
    endfor

    # Final output channels on one shared amplitude scale.
    selectObject: resultID
    nChRes = Get number of channels
    if nChRes > 1
        Extract one channel: 1
        vizOutL = selected("Sound")
        selectObject: resultID
        Extract one channel: 2
        vizOutR = selected("Sound")
    else
        selectObject: resultID
        Copy: "viz_out_mono"
        vizOutL = selected("Sound")
        vizOutR = 0
    endif
    selectObject: vizDryID
    dryPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizOutL
    outPeakL = Get absolute extremum: 0, 0, "None"
    if nChRes > 1
        selectObject: vizOutR
        outPeakR = Get absolute extremum: 0, 0, "None"
    else
        outPeakR = outPeakL
    endif
    wavePeak = 1.05 * max(dryPeak, max(outPeakL, outPeakR))
    if wavePeak < 1e-9
        wavePeak = 1
    endif

    procedure niceStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all

    # ---------------- Header ----------------
    Select outer viewport: 0, 8, 0, 0.38
    Select inner viewport: 0, 8, 0, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "Fractal Spectral Hologram v1.2 — " + presetName$

    Select outer viewport: 0, 8, 0.39, 0.69
    Select inner viewport: 0, 8, 0.39, 0.69
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    if sharpen_strength > 0.001
        if blur_passes > 0
            blurRole$ = "blur " + string$(blur_passes) + "x = sharpen reference"
        else
            blurRole$ = "one-pass blur reference for sharpen"
        endif
    else
        blurRole$ = "blur " + string$(blur_passes) + "x remains in output"
    endif
    Text: 0.5, "centre", 0.5, "half",
        ... "FFT magnitude -> " + blurRole$ + " -> geometric zoom copies -> original phase -> iFFT -> dry/wet"

    # ---------------- A title ----------------
    Select outer viewport: 0, 8, 0.76, 0.98
    Select inner viewport: 0, 8, 0.76, 0.98
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  Fractal-inspired frequency map: one source feature -> geometric copy levels"

    # ---------------- A map ----------------
    Select outer viewport: 0, 8, 1.00, 2.18
    Select inner viewport: 0.72, 7.65, 1.09, 1.94
    Axes: 0, vizFreqMax, 0, 1
    Paint rectangle: "{0.975,0.975,0.978}", 0, vizFreqMax, 0, 1

    # Shared frequency line and actual quantized zoom axis.
    Colour: "{0.45,0.45,0.48}"
    Line width: 1
    Draw line: 0, 0.34, vizFreqMax, 0.34
    Dashed line
    Colour: "{0.28,0.55,0.38}"
    if actualCentreHz <= vizFreqMax
        Draw line: actualCentreHz, 0.10, actualCentreHz, 0.88
    endif
    Solid line

    # Representative measured source component and its predicted copies.
    Colour: "{0.20,0.35,0.65}"
    Paint circle (mm): "{0.20,0.35,0.65}", strongestDryHz, 0.34, 1.2
    # Paint circle disturbs the drawing frame: restore before every later draw/text.
    Select inner viewport: 0.72, 7.65, 1.09, 1.94
    Axes: 0, vizFreqMax, 0, 1
    Font size: 5
    Colour: "{0.20,0.35,0.65}"
    Text: strongestDryHz, "centre", 0.20, "half", "source " + fixed$(strongestDryHz/1000,2) + "k"
    if actualCentreHz <= vizFreqMax
        Colour: "{0.28,0.55,0.38}"
        Text: actualCentreHz, "centre", 0.94, "half", "axis " + fixed$(actualCentreHz,0) + " Hz"
    endif

    # Curved folds embody f_k = c + z^k(f_s-c). Use a few readable levels.
    maxDrawLevels = min(fractal_levels, 6)
    for k from 1 to maxDrawLevels
        dst = actualCentreHz + (fractal_zoom ^ k) * (strongestDryHz - actualCentreHz)
        if dst >= 0 and dst <= vizFreqMax
            yBase = 0.34
            arcH = min(0.50, 0.16 + 0.055*k)
            Colour: "{0.72,0.38,0.24}"
            Line width: 1
            for qq from 1 to 28
                u0 = (qq-1)/28
                u1 = qq/28
                x0 = strongestDryHz + (dst-strongestDryHz)*u0
                x1 = strongestDryHz + (dst-strongestDryHz)*u1
                y0 = yBase + arcH*sin(pi*u0)
                y1 = yBase + arcH*sin(pi*u1)
                Draw line: x0,y0,x1,y1
            endfor
            Paint circle (mm): "{0.72,0.38,0.24}", dst, yBase, 0.7
            Select inner viewport: 0.72, 7.65, 1.09, 1.94
            Axes: 0, vizFreqMax, 0, 1
            Font size: 4.8
            Colour: "{0.72,0.38,0.24}"
            Text: dst, "centre", 0.07 + 0.06*(k mod 2), "half", "k" + string$(k)
        endif
    endfor
    Line width: 1

    Select inner viewport: 0.72, 7.65, 1.09, 1.94
    Axes: 0, vizFreqMax, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 5
    @niceStep: vizFreqMax, 8
    stepA = niceStep.step
    nA = floor(vizFreqMax/stepA)
    for q from 0 to nA
        fMark = q*stepA
        if fMark >= 1000
            lab$ = fixed$(fMark/1000,1) + "k"
        else
            lab$ = fixed$(fMark,0)
        endif
        One mark bottom: fMark, "no", "yes", "no", lab$
    endfor

    Select outer viewport: 0, 8, 2.18, 2.39
    Select inner viewport: 0, 8, 2.18, 2.39
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    if exact_zoom_centre
        centreMode$ = "exact"
    else
        centreMode$ = "legacy"
    endif
    Text: 0.5,"centre",0.5,"half",
        ... "f_k = c + zoom^k (f_source - c), weight = decay^k  |  c=" + fixed$(actualCentreHz,2)
        ... + " Hz (" + centreMode$ + ", FFT df " + fixed$(fftBinWidth,3) + " Hz)  |  levels=" + string$(fractal_levels)

    # ---------------- B title ----------------
    Select outer viewport: 0, 8, 2.47, 2.69
    Select inner viewport: 0, 8, 2.47, 2.69
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","B  Measured spectrum: pristine source vs pure wet spectral target"

    # ---------------- B spectrum ----------------
    Select outer viewport: 0, 8, 2.71, 4.04
    Select inner viewport: 0.72, 7.65, 2.81, 3.78
    Axes: 0, vizFreqMax, -80, 0
    Paint rectangle: "{0.975,0.975,0.978}", 0, vizFreqMax, -80, 0
    for q from 1 to nBands-1
        f0 = vizFreqMax*(q-0.5)/nBands
        f1 = vizFreqMax*(q+0.5)/nBands
        Colour: "{0.55,0.55,0.58}"
        Line width: 1
        Draw line: f0,dryDb#[q],f1,dryDb#[q+1]
        Colour: "{0.25,0.50,0.80}"
        Line width: 1.5
        Draw line: f0,wetDb#[q],f1,wetDb#[q+1]
    endfor
    Line width: 1

    # Mark predicted copy locations from the measured strongest source band.
    Dashed line
    for k from 1 to maxDrawLevels
        dst = actualCentreHz + (fractal_zoom ^ k) * (strongestDryHz - actualCentreHz)
        if dst >= 0 and dst <= vizFreqMax
            Colour: "{0.72,0.38,0.24}"
            Draw line: dst,-80,dst,-2
        endif
    endfor
    Solid line

    Select inner viewport: 0.72, 7.65, 2.81, 3.78
    Axes: 0, vizFreqMax, -80, 0
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, 20, "yes", "yes", "no"
    @niceStep: vizFreqMax, 8
    stepB = niceStep.step
    nB = floor(vizFreqMax/stepB)
    for q from 0 to nB
        fMark = q*stepB
        if fMark >= 1000
            lab$ = fixed$(fMark/1000,1) + "k"
        else
            lab$ = fixed$(fMark,0)
        endif
        One mark bottom: fMark, "no", "yes", "no", lab$
    endfor
    Font size: 5
    Colour: "{0.55,0.55,0.58}"
    Text: 0.02*vizFreqMax,"left",-7,"half","gray source"
    Colour: "{0.25,0.50,0.80}"
    Text: 0.20*vizFreqMax,"left",-7,"half","blue pure wet"
    Colour: "{0.72,0.38,0.24}"
    Text: 0.39*vizFreqMax,"left",-7,"half","dashed = predicted zoom copies"

    Select outer viewport: 0, 8, 4.04, 4.25
    Select inner viewport: 0, 8, 4.04, 4.25
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5,"centre",0.5,"half",
        ... "relative dB, common scale  |  strongest measured source band ~" + fixed$(strongestDryHz/1000,2)
        ... + "k Hz  |  pure wet is measured before dry/wet mix"

    # ---------------- C title ----------------
    Select outer viewport: 0, 8, 4.33, 4.55
    Select inner viewport: 0, 8, 4.33, 4.55
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","C  Measured waveform: source and final output on one amplitude scale"

    # Source waveform
    Select outer viewport: 0, 8, 4.57, 5.18
    Select inner viewport: 0.68, 7.70, 4.61, 5.14
    selectObject: vizDryID
    Colour: "{0.55,0.55,0.58}"
    Draw: 0,0,-wavePeak,wavePeak,"no","Curve"
    Select inner viewport: 0.68, 7.70, 4.61, 5.14
    Axes: 0,duration,-wavePeak,wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes","source"

    # Output waveform(s)
    Select outer viewport: 0, 8, 5.18, 5.94
    Select inner viewport: 0.68, 7.70, 5.22, 5.88
    selectObject: vizOutL
    Colour: "{0.25,0.50,0.80}"
    Draw: 0,0,-wavePeak,wavePeak,"no","Curve"
    if nChRes > 1
        selectObject: vizOutR
        Colour: "{0.80,0.42,0.24}"
        Draw: 0,0,-wavePeak,wavePeak,"no","Curve"
    endif
    Select inner viewport: 0.68, 7.70, 5.22, 5.88
    Axes: 0,duration,-wavePeak,wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 5
    @niceStep: duration, 7
    Marks bottom every: 1,niceStep.step,"yes","yes","no"
    if nChRes > 1
        Text left: "yes","L/R"
    else
        Text left: "yes","output"
    endif

    Select outer viewport: 0, 8, 5.94, 6.15
    Select inner viewport: 0, 8, 5.94, 6.15
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5,"centre",0.5,"half",
        ... "time in seconds  |  final peak L/R=" + fixed$(outPeakL,3) + "/" + fixed$(outPeakR,3)
        ... + "  |  dry/wet=" + fixed$(dry_wet,2) + "  |  output peak target=" + fixed$(scale_peak,2)

    # ---------------- QC / operator strip ----------------
    Select outer viewport: 0, 8, 6.23, 7.12
    Select inner viewport: 0.18, 7.82, 6.28, 7.07
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.965,0.965,0.97}",0,3,0,2
    Colour: "{0.82,0.82,0.84}"
    Draw line: 1,0,1,2
    Draw line: 2,0,2,2
    Draw line: 0,1,3,1
    Colour: "Black"
    Draw rectangle: 0,3,0,2
    Font size: 5.5
    Text: 0.05,"left",1.55,"half","blur kernel: [1 4 6 4 1] / 16"
    Text: 1.05,"left",1.55,"half","passes " + string$(blur_passes) + " | sharpen " + fixed$(sharpen_strength,2)
    Text: 2.05,"left",1.55,"half","zoom " + fixed$(fractal_zoom,2) + " | levels " + string$(fractal_levels)
    Text: 0.05,"left",0.55,"half","decay " + fixed$(fractal_decay,2) + " | weighted magnitude average"
    Text: 1.05,"left",0.55,"half","axis " + centreMode$ + " req/actual " + fixed$(zoom_centre_Hz,1) + "/" + fixed$(actualCentreHz,1) + " Hz"
    Text: 2.05,"left",0.55,"half","FFT df " + fixed$(fftBinWidth,3) + " Hz | render " + fixed$(processingTime,2) + " s"

    removeObject: drySpec, wetSpec, vizDryID, vizWetID
    if nChRes > 1
        removeObject: vizOutL, vizOutR
    else
        removeObject: vizOutL
    endif
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
