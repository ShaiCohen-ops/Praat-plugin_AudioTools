# ============================================================
# Praat AudioTools - Spectral_Blur.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
#
# Changelog v2.3 (2026):
#   - FIX: multichannel inputs no longer lose channels above R. Every source
#     channel is processed independently and recombined; mono/stereo behavior
#     is unchanged.
#   - MUSICAL/FFT CLARITY: Tail behavior is explicit. The v2.2 Extended FFT
#     tail remains the default character (padding before the FFT can change the
#     FFT lattice and therefore the blur texture). A new Stable core mode keeps
#     the original FFT lattice and retains only the internal FFT-generated tail,
#     so changing Tail cannot retune the core blur.
#   - FORM/ROBUSTNESS: Blur passes are integer; output peak validated to (0,1].
#   - VIZ: input/output waveforms now share one amplitude scale and all
#     spectrogram ranges are Nyquist-safe.
#   - CLARITY: this is full-file magnitude smoothing with original FFT phase,
#     not phase smearing. Its time-domain spread is zero-phase/time-symmetric.
#
# Changelog v2.2 (2026):
#   - ADDED tail + fade-out. The blur makes the signal no longer
#     time-limited: spectral smearing spills energy past the
#     input's end, which the pad trim used to discard. Each
#     channel is now zero-padded by Tail_seconds BEFORE the FFT,
#     so the blur spills organically into real tail room; the
#     wet/dry mix leaves the tail pure wet (the dry ends with the
#     input); and a raised-cosine Fade_out_seconds closes the
#     output. Tail 0 + fade 0 reproduces v2.1 exactly.
#
# Changelog v2.1 (2026):
#   - FIX (correctness): the binomial smoothing kernels read
#     self[1, col-k] IN PLACE -- Praat's Formula overwrites left
#     to right, so the left taps returned already-smoothed values
#     from the same pass while the right taps read originals: a
#     recursive asymmetric smoother, not the documented binomial.
#     v2.1 ping-pongs between two magnitude buffers (read frozen,
#     write other), making the kernel exactly what the comment
#     says. Measured honestly: for CONTRACTION kernels the
#     recursion's audible footprint is small (skirt asymmetry
#     around an isolated partial ~0.1 dB after 50 ExtremeWash
#     passes) -- unlike difference/shift formulas, where the same
#     in-place pattern is catastrophic. Fixed on principle; the
#     blur character is essentially unchanged.
#   - Verified on 6.4.42: procedure-local dotted variables
#     (.nBins) ARE resolvable inside Formula strings.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral blur effect via full-file frequency-bin MAGNITUDE smoothing.
#   The original complex-spectrum phase is retained while the global magnitude
#   curve is diffused across neighboring FFT bins. The corresponding time-domain
#   spread is zero-phase/time-symmetric rather than a causal reverberant decay.
#
#   v2.0 fixes the v1.0 architecture:
#   - OLD: chunked Spectrogram (power only, phase discarded)
#     then per-chunk phase reconstruction then concatenation
#     = audible clicks at every chunk boundary
#   - NEW: single full-file FFT on the complex Spectrum
#     then smooth magnitude bins and scale real+imag together
#     then single iFFT.  No chunk-boundary joins; original FFT phase retained.
#
#   All source channels are processed independently.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Spectral Blur v2.3
    optionmenu Preset: 1
        option Standard Blur (smooth smear)
        option Ethereal Pad (heavy, dreamy)
        option Underwater (deep, warm)
        option Metallic Sheen (light, bright)
        option Extreme Wash (maximum blur)
        option Custom
    comment === Blur Parameters ===
    integer Blur_passes 10
    comment (3 = subtle, 10 = clear, 30+ = extreme)
    optionmenu Blur_type: 2
        option Narrow (3-bin kernel)
        option Medium (5-bin kernel)
        option Wide (7-bin kernel)
    comment === Mix ===
    real Wet_dry_percent 100
    comment === Tail & Fade ===
    real Tail_seconds 1.0
    optionmenu Tail_behavior: 1
        option Extended FFT tail (v2.2 character)
        option Stable core (retain internal FFT tail)
    comment (Extended can change the FFT texture; Stable keeps the core blur fixed)
    real Fade_out_seconds 0.5
    comment === Output ===
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 1
    blur_passes = 10
    blur_type = 2
    wet_dry_percent = 100
    presetName$ = "StandardBlur"
elsif preset = 2
    blur_passes = 30
    blur_type = 3
    wet_dry_percent = 100
    presetName$ = "EtherealPad"
elsif preset = 3
    blur_passes = 20
    blur_type = 3
    wet_dry_percent = 85
    presetName$ = "Underwater"
elsif preset = 4
    blur_passes = 5
    blur_type = 1
    wet_dry_percent = 70
    presetName$ = "MetallicSheen"
elsif preset = 5
    blur_passes = 50
    blur_type = 3
    wet_dry_percent = 100
    presetName$ = "ExtremeWash"
else
    presetName$ = "Custom"
endif

# Validation / clamps
if blur_passes < 1
    blur_passes = 1
endif
if blur_passes > 100
    blur_passes = 100
endif
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level
if tail_seconds < 0
    tail_seconds = 0
endif
if fade_out_seconds < 0
    fade_out_seconds = 0
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and at most 1."
endif

if tail_behavior = 1
    tailName$ = "Extended FFT tail (v2.2)"
else
    tailName$ = "Stable core"
endif

# Kernel name
if blur_type = 1
    blurName$ = "Narrow (3-bin)"
elsif blur_type = 2
    blurName$ = "Medium (5-bin)"
else
    blurName$ = "Wide (7-bin)"
endif

# Setup
selectObject: originalID
sampleRate = Get sampling frequency
totalDuration = Get total duration
numChannels = Get number of channels

startTime = stopwatch

clearinfo
writeInfoLine: "=== Spectral Blur v2.3 ==="
appendInfoLine: "Input: ", originalName$, " (", fixed$(totalDuration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Blur passes: ", blur_passes
appendInfoLine: "Kernel: ", blurName$
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Tail behavior: ", tailName$
appendInfoLine: ""

# ============================================================
# BLUR PROCEDURE
# ============================================================
#
# Smooths the MAGNITUDE of the spectrum while preserving phase.
#
# Method (all Formula-based, no per-bin loops):
#   1. Convert Spectrum → Matrix (2 rows: re, im)
#   2. Extract magnitude into a 1-row Matrix via Formula
#   3. Smooth magnitude with multi-pass binomial kernel
#   4. Compute ratio (smoothed/original) and scale re+im
#   5. Convert back to Spectrum
#
# Phase untouched → no temporal concentration.
# Magnitude smeared → audible spectral blur.

procedure blurSpectrum: .specID, .nPasses, .kernelSize
    selectObject: .specID
    .nBins = Get number of bins
    .specStr$ = string$(.specID)
    blurSpectrum.nBins = .nBins
    .binHz = (sampleRate / 2) / max(1, .nBins - 1)
    if .kernelSize = 1
        .kernelVar = 0.5
    elsif .kernelSize = 2
        .kernelVar = 1.0
    else
        .kernelVar = 1.5
    endif
    # Repeated binomial kernels add variances: sigma_bins = sqrt(P*variance).
    # This is an interior-bin approximation; FFT-edge bins are held unchanged.
    blurSpectrum.sigmaHz = .binHz * sqrt(.nPasses * .kernelVar)

    # Step 1: Extract magnitude into a 1-row Matrix
    Create simple Matrix: "origMag", 1, .nBins, "0"
    .origMag = selected("Matrix")
    Formula: "sqrt(object[" + .specStr$ + ", 1, col]^2"
        ... + " + object[" + .specStr$ + ", 2, col]^2)"

    # Step 2: Smooth magnitude (multi-pass binomial kernel)
    # v2.1: ping-pong buffers -- each pass READS the previous
    # buffer via object[] and WRITES the other. The old in-place
    # self[1, col-k] reads returned just-written values (Formula
    # overwrites left to right): a recursive asymmetric smoother
    # drifting energy downward in frequency.
    Copy: "smoothedMagA"
    .bufA = selected("Matrix")
    Copy: "smoothedMagB"
    .bufB = selected("Matrix")
    .bufAStr$ = string$(.bufA)
    .bufBStr$ = string$(.bufB)

    for .pass from 1 to .nPasses
        if .pass mod 2 = 1
            .srcStr$ = .bufAStr$
            selectObject: .bufB
        else
            .srcStr$ = .bufBStr$
            selectObject: .bufA
        endif

        if .kernelSize = 1
            Formula: "if col > 1 and col < .nBins then "
                ... + "(object[" + .srcStr$ + ", 1, col-1] + 2*object[" + .srcStr$ + ", 1, col]"
                ... + " + object[" + .srcStr$ + ", 1, col+1]) / 4 "
                ... + "else object[" + .srcStr$ + ", 1, col] endif"
        elsif .kernelSize = 2
            Formula: "if col > 2 and col < .nBins - 1 then "
                ... + "(object[" + .srcStr$ + ", 1, col-2] + 4*object[" + .srcStr$ + ", 1, col-1]"
                ... + " + 6*object[" + .srcStr$ + ", 1, col]"
                ... + " + 4*object[" + .srcStr$ + ", 1, col+1] + object[" + .srcStr$ + ", 1, col+2]) / 16 "
                ... + "else object[" + .srcStr$ + ", 1, col] endif"
        else
            Formula: "if col > 3 and col < .nBins - 2 then "
                ... + "(object[" + .srcStr$ + ", 1, col-3] + 6*object[" + .srcStr$ + ", 1, col-2]"
                ... + " + 15*object[" + .srcStr$ + ", 1, col-1] + 20*object[" + .srcStr$ + ", 1, col]"
                ... + " + 15*object[" + .srcStr$ + ", 1, col+1] + 6*object[" + .srcStr$ + ", 1, col+2]"
                ... + " + object[" + .srcStr$ + ", 1, col+3]) / 64 "
                ... + "else object[" + .srcStr$ + ", 1, col] endif"
        endif
    endfor

    if .nPasses mod 2 = 1
        .smoothMag = .bufB
        .unusedBuf = .bufA
    else
        .smoothMag = .bufA
        .unusedBuf = .bufB
    endif

    # Step 3: Apply ratio directly to Spectrum (both re and im rows)
    # ratio = smoothedMag / origMag — scales magnitude, preserves phase
    .origMagStr$ = string$(.origMag)
    .smoothMagStr$ = string$(.smoothMag)

    selectObject: .specID
    Formula: "self * object[" + .smoothMagStr$ + ", 1, col]"
        ... + " / max(1e-30, object[" + .origMagStr$ + ", 1, col])"

    removeObject: .origMag, .bufA, .bufB

    # Spectrum modified in-place — no new ID needed
    blurSpectrum.resultSpec = .specID
endproc

# ============================================================
# PROCESS EACH CHANNEL
# ============================================================

procedure processChannel: .channelID
    selectObject: .channelID
    .chDur = Get total duration
    .chSR = Get sampling frequency

    if tail_behavior = 1
        # Extended FFT tail (v2.2): explicitly pad BEFORE the FFT. This keeps
        # the existing long-tail character, but the larger padded FFT can change
        # the bin lattice and therefore the blur heard inside the source duration.
        .outDur = .chDur + tail_seconds
        if tail_seconds > 0
            .chStr$ = string$(.channelID)
            Create Sound from formula: "tailpad", 1, 0, .outDur, .chSR,
                ... "object[" + .chStr$ + ", col]"
            .fftInput = selected("Sound")
        else
            selectObject: .channelID
            Copy: "tailpad"
            .fftInput = selected("Sound")
        endif
    else
        # Stable core: do NOT change the FFT input length. To Spectrum: yes
        # already zero-pads internally to a fast FFT length; after the iFFT we
        # may retain up to Tail_seconds from that existing padding. Thus Tail
        # cannot alter the core FFT lattice or blur character.
        selectObject: .channelID
        Copy: "stableCoreInput"
        .fftInput = selected("Sound")
        .outDur = .chDur
    endif

    selectObject: .fftInput
    To Spectrum: "yes"
    .wetSpec = selected("Spectrum")
    removeObject: .fftInput

    @blurSpectrum: .wetSpec, blur_passes, blur_type
    .blurSigmaHz = blurSpectrum.sigmaHz
    .fftBins = blurSpectrum.nBins

    selectObject: .wetSpec
    To Sound
    .wetSound = selected("Sound")
    removeObject: .wetSpec

    selectObject: .wetSound
    .rDur = Get total duration

    if tail_behavior = 2
        .availableTail = .rDur - .chDur
        if .availableTail < 0
            .availableTail = 0
        endif
        .retainedTail = tail_seconds
        if .retainedTail > .availableTail
            .retainedTail = .availableTail
        endif
        .outDur = .chDur + .retainedTail
    else
        .retainedTail = tail_seconds
    endif

    # Trim FFT padding to the requested/available output duration.
    selectObject: .wetSound
    if .rDur > .outDur
        Extract part: 0, .outDur, "rectangular", 1, "no"
        .trimmed = selected("Sound")
        removeObject: .wetSound
        .wetSound = .trimmed
    endif

    processChannel.retainedTail = .retainedTail
    processChannel.blurSigmaHz = .blurSigmaHz
    processChannel.fftBins = .fftBins
    processChannel.result = .wetSound
endproc

# ============================================================
# MAIN PROCESSING
# ============================================================

appendInfoLine: "Processing..."

wetIDs# = zero#(numChannels)
retainedTail = 0
blurSigmaHz = 0
fftBinsUsed = 0
for ch from 1 to numChannels
    appendInfoLine: "  Channel ", ch, "..."
    selectObject: originalID
    if numChannels = 1
        chWork = Copy: "blur_work"
    else
        chWork = Extract one channel: ch
    endif
    @processChannel: chWork
    wetIDs#[ch] = processChannel.result
    retainedTail = processChannel.retainedTail
    blurSigmaHz = processChannel.blurSigmaHz
    fftBinsUsed = processChannel.fftBins
    removeObject: chWork
endfor

if numChannels = 1
    wetSound = wetIDs#[1]
else
    selectObject: wetIDs#[1]
    for ch from 2 to numChannels
        plusObject: wetIDs#[ch]
    endfor
    Combine to stereo
    wetSound = selected("Sound")
    for ch from 1 to numChannels
        removeObject: wetIDs#[ch]
    endfor
endif

appendInfoLine: "Retained tail: ", fixed$(retainedTail, 4), " s"
appendInfoLine: "FFT bins: ", fftBinsUsed, "   Approx blur sigma: ", fixed$(blurSigmaHz, 3), " Hz"
if tail_behavior = 2 and retainedTail + 1e-9 < tail_seconds
    appendInfoLine: "NOTE: Stable core retained the available internal FFT tail (",
        ... fixed$(retainedTail, 4), " s of ", fixed$(tail_seconds, 4), " s requested)."
endif

# ============================================================
# WET/DRY MIX
# ============================================================

if dry_level > 0
    appendInfoLine: "  Mixing wet/dry..."
    origStr$ = string$(originalID)
    selectObject: wetSound
    wetNch = Get number of channels
    selectObject: originalID
    origNch = Get number of channels

    if wetNch = origNch
        selectObject: wetSound
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + origStr$ + ", row, col] * " + string$(dry_level)
    else
        selectObject: originalID
        if origNch > 1
            origMix = Convert to mono
        else
            origMix = Copy: "origMix"
        endif
        origMixStr$ = string$(origMix)
        selectObject: wetSound
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + origMixStr$ + ", col] * " + string$(dry_level)
        removeObject: origMix
    endif
endif

# ============================================================
# FINALIZE
# ============================================================

# Raised-cosine fade at the very end. In Stable-core mode, when a positive
# tail was requested, do not let a requested fade longer than the actually
# retained FFT tail reach backward into the source core. Tail=0 still means
# the user explicitly asked to fade the source ending itself.
appliedFade = 0
if fade_out_seconds > 0
    selectObject: wetSound
    outDurF = Get total duration
    fd = fade_out_seconds
    if tail_behavior = 2 and tail_seconds > 0 and fd > retainedTail
        fd = retainedTail
    endif
    if fd > outDurF
        fd = outDurF
    endif
    if fd > 0
        Fade out: 0, outDurF, -fd, "yes"
        appliedFade = fd
    endif
endif
appendInfoLine: "Applied fade: ", fixed$(appliedFade, 4), " s"

selectObject: wetSound
Scale peak: scale_peak
Rename: originalName$ + "_blur_" + presetName$
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
    Select outer viewport: 0, 8, 0, 0.45
    Select inner viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Spectral Blur##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.18, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + string$(blur_passes) + " passes"
        ... + "  |  " + blurName$

    # Shared waveform scale for an honest before/after comparison.
    selectObject: originalID
    inVizPeak = Get absolute extremum: 0, 0, "None"
    selectObject: resultID
    outVizPeak = Get absolute extremum: 0, 0, "None"
    waveVizPeak = 1.05 * max(inVizPeak, outVizPeak)
    if waveVizPeak < 1e-12
        waveVizPeak = 1
    endif
    vizFreqMax = min(5000, sampleRate / 2)

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: originalID
    if numChannels > 1
        Extract one channel: 1
        vizInCh = selected("Sound")
    else
        Copy: "vizInCh"
        vizInCh = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -waveVizPeak, waveVizPeak, "no", "Curve"
    removeObject: vizInCh
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
        Draw: 0, 0, -waveVizPeak, waveVizPeak, "no", "Curve"
        selectObject: resultID
        Extract one channel: 2
        vizOutR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -waveVizPeak, waveVizPeak, "no", "Curve"
        removeObject: vizOutL, vizOutR
    else
        selectObject: resultID
        Colour: "{0.35, 0.58, 0.72}"
        Draw: 0, 0, -waveVizPeak, waveVizPeak, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Blurred"
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
    To Spectrogram: 0.02, vizFreqMax, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, vizFreqMax, 100, "yes", 50, 6, 0, "no"
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
    To Spectrogram: 0.02, vizFreqMax, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, vizFreqMax, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes, vizSpecOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Blurred spectrogram"

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
        ... + "  |  Passes: " + string$(blur_passes)
        ... + "  |  Kernel: " + blurName$
        ... + "  |  Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"
        ... + "  |  Tail/Fade: " + fixed$(retainedTail, 3) + "/" + fixed$(appliedFade, 3) + "s"
        ... + "  |  sigma: " + fixed$(blurSigmaHz, 2) + " Hz"
        ... + "  |  Time: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# FINAL
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID
