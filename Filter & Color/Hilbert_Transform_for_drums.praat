# ============================================================
# Praat AudioTools - Hilbert Transform for Drums.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7.1 (2026) - Preserve source time domain
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Hilbert transform for envelope extraction and transient processing.
#   
# Output modes:
#   - Transient Enhanced: Envelope-driven expansion that increases
#     attack/sustain contrast (amount > 1) or reduces it (amount < 1)
#   - Envelope Shaped: Original multiplied by a normalized smoothed envelope
#   - Hilbert (90deg): Discrete Hilbert transform (DC/Nyquist removed)
#   - Normalized Envelope: Hilbert magnitude, optionally smoothed, normalized to 1
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.7 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.6:
#   - Visualization redesigned to match the Praat AudioTools house style:
#     title/subtitle header, input/output waveforms, paired spectrograms,
#     waveform-detail diagnostic, and compact summary panel.
#   - DSP/output are unchanged from v0.5.
#
# Changelog v0.5:
#   - Faster execution: skips envelope/smoothing entirely for Hilbert-only mode.
#   - Fully dry output bypasses all Hilbert processing.
#   - Removes unnecessary full-Sound/output copies and uses exact sample indexing.
#   - Reuses Hilbert/envelope objects directly when they are already the output.
#
# Changelog v0.4:
#   - Correct Hilbert construction: no FFT zero-padding; DC and Nyquist bins
#     are explicitly zeroed before inverse transform.
#   - Peak normalization is now optional (scale_peak = 0 preserves level).
#   - Rejects >2-channel inputs instead of silently dropping channels 3+.
#   - Renamed Raw Envelope to Normalized Envelope and clarified transient mode.
#
# Changelog v0.3:
#   - Normalized elif -> elsif (documented keyword; was mixed with elsif).
#   - Dry/wet mix now references a safe ID-named copy of the original
#     instead of Sound_<name>(x), so object names with spaces/punctuation
#     can't break the formula on other Praat builds.
# ============================================================

form Hilbert Transform Envelope v0.7.1
    optionmenu Preset: 1
        option Custom
        option Drum Punch (transient enhance)
        option Soft Attack (reduce transients)
        option Phase Shift (90 deg)
        option Gate Effect (envelope shape)
    optionmenu Output_mode: 1
        option Transient Enhanced
        option Envelope Shaped
        option Hilbert (90deg shift)
        option Normalized Envelope (for analysis)
    real transient_amount 1.5
    comment (> 1 = punchier attacks, < 1 = softer attacks)
    real envelope_smoothing_ms 5
    real dry_wet_mix 1.0
    real scale_peak 0
    comment (0 = preserve natural level; > 0 = normalize peak to this target)
    boolean draw_visualization 1
    boolean play_after_processing 1
endform

# ============================================================
# Apply presets
# ============================================================
if preset$ = "Drum Punch (transient enhance)"
    output_mode = 1
    transient_amount = 2.0
    envelope_smoothing_ms = 2
elsif preset$ = "Soft Attack (reduce transients)"
    output_mode = 1
    transient_amount = 0.5
    envelope_smoothing_ms = 10
elsif preset$ = "Phase Shift (90 deg)"
    output_mode = 3
    transient_amount = 1.0
    envelope_smoothing_ms = 5
elsif preset$ = "Gate Effect (envelope shape)"
    output_mode = 2
    transient_amount = 1.0
    envelope_smoothing_ms = 1
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels
nyquist = sampleRate / 2
originalXmin = Get start time

if numChannels > 2
    exitScript: "This script supports mono or stereo Sound objects only."
endif

if scale_peak < 0
    scale_peak = 0
endif

if envelope_smoothing_ms < 0.1
    envelope_smoothing_ms = 0.1
endif
if transient_amount <= 0
    transient_amount = 0.1
endif
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif

uniqueID$ = string$(randomInteger(10000, 99999))

if output_mode = 1
    modeName$ = "TransientEnhanced"
elsif output_mode = 2
    modeName$ = "EnvelopeShaped"
elsif output_mode = 3
    modeName$ = "Hilbert90"
else
    modeName$ = "NormalizedEnvelope"
endif

# ============================================================
# Report
# ============================================================
writeInfoLine: "Hilbert Transform Envelope"
appendInfoLine: "=========================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Output: ", modeName$
if output_mode = 1
    appendInfoLine: "Transient amount: ", transient_amount
endif
if output_mode <> 3
    appendInfoLine: "Smoothing: ", envelope_smoothing_ms, " ms"
endif
appendInfoLine: ""

# ============================================================
# Process
# ============================================================
appendInfoLine: "Computing Hilbert transform..."

# Fast path: a fully dry result does not require any Hilbert processing.
if dry_wet_mix = 0
    selectObject: sound
    result = Copy: "output_" + uniqueID$

elsif numChannels = 1
    # --- MONO PROCESSING ---
    # Work directly from the selected source Sound. To Spectrum creates a new
    # object and does not alter the source, so an additional full Sound copy is
    # unnecessary.
    selectObject: sound
    nSamples = Get number of samples
    To Spectrum: "no"
    origSpec = selected("Spectrum")
    Rename: "origSpec_" + uniqueID$
    nBins = Get number of bins
    hasNyquist = (nSamples mod 2 = 0)

    # A second Spectrum is required because an in-place row swap would corrupt
    # the complex rotation while Formula evaluates the matrix.
    hilbertSpec = Copy: "hilbertSpec_" + uniqueID$
    Formula: "if col = 1 or ('hasNyquist' = 1 and col = 'nBins') then 0 else if row = 1 then Spectrum_origSpec_'uniqueID$'[2, col] else -Spectrum_origSpec_'uniqueID$'[1, col] fi fi"

    To Sound
    hilbert = selected("Sound")
    Rename: "hilbert_" + uniqueID$
    removeObject: origSpec, hilbertSpec

    if output_mode = 3
        # HILBERT ONLY: no envelope, smoothing, normalization or extra Sound
        # copy is needed. This is the major fast path for phase-shift mode.
        result = hilbert

    else
        # Compute envelope: sqrt(x^2 + H{x}^2). Direct sample indexing avoids
        # time-domain interpolation and is exact because both Sounds share the
        # same sampling grid.
        selectObject: sound
        envelope = Copy: "envelope_" + uniqueID$
        Formula: "sqrt(self^2 + Sound_hilbert_'uniqueID$'[col]^2)"

        # Smooth envelope
        if envelope_smoothing_ms > 0
            smoothHz = 1000 / envelope_smoothing_ms
            if smoothHz < nyquist
                selectObject: envelope
                Filter (pass Hann band): 0, smoothHz, smoothHz * 0.2
                smoothed = selected("Sound")
                removeObject: envelope
                envelope = smoothed
                Rename: "envelope_" + uniqueID$
            endif
        endif

        # Normalize envelope to max = 1, with floor to avoid divide-by-zero
        selectObject: envelope
        envMax = Get maximum: 0, 0, "Sinc70"
        if envMax > 0.0001
            Formula: "max(0.001, self / 'envMax')"
        else
            Formula: "0.001"
        endif

        if output_mode = 4
            # NORMALIZED ENVELOPE: the envelope object already is the output.
            result = envelope
            removeObject: hilbert

        else
            # TRANSIENT / ENVELOPE-SHAPED output
            selectObject: sound
            output = Copy: "output_" + uniqueID$

            if output_mode = 1
                exponent = transient_amount - 1
                Formula: "self * Sound_envelope_'uniqueID$'[col]^'exponent'"
            else
                Formula: "self * Sound_envelope_'uniqueID$'[col]"
            endif

            removeObject: hilbert, envelope
            result = output
        endif
    endif

else
    # --- STEREO PROCESSING ---
    selectObject: sound
    Extract one channel: 1
    leftIn = selected("Sound")
    Rename: "leftIn_" + uniqueID$

    selectObject: sound
    Extract one channel: 2
    rightIn = selected("Sound")
    Rename: "rightIn_" + uniqueID$

    # === Process LEFT Hilbert transform ===
    selectObject: leftIn
    nSamplesL = Get number of samples
    To Spectrum: "no"
    specL = selected("Spectrum")
    Rename: "specL_" + uniqueID$
    nBinsL = Get number of bins
    hasNyquistL = (nSamplesL mod 2 = 0)

    hilbertSpecL = Copy: "hilbertSpecL_" + uniqueID$
    Formula: "if col = 1 or ('hasNyquistL' = 1 and col = 'nBinsL') then 0 else if row = 1 then Spectrum_specL_'uniqueID$'[2, col] else -Spectrum_specL_'uniqueID$'[1, col] fi fi"
    To Sound
    hilbertL = selected("Sound")
    Rename: "hilbertL_" + uniqueID$
    removeObject: specL, hilbertSpecL

    # === Process RIGHT Hilbert transform ===
    selectObject: rightIn
    nSamplesR = Get number of samples
    To Spectrum: "no"
    specR = selected("Spectrum")
    Rename: "specR_" + uniqueID$
    nBinsR = Get number of bins
    hasNyquistR = (nSamplesR mod 2 = 0)

    hilbertSpecR = Copy: "hilbertSpecR_" + uniqueID$
    Formula: "if col = 1 or ('hasNyquistR' = 1 and col = 'nBinsR') then 0 else if row = 1 then Spectrum_specR_'uniqueID$'[2, col] else -Spectrum_specR_'uniqueID$'[1, col] fi fi"
    To Sound
    hilbertR = selected("Sound")
    Rename: "hilbertR_" + uniqueID$
    removeObject: specR, hilbertSpecR

    if output_mode = 3
        # HILBERT ONLY: combine the two Hilbert channels directly.
        selectObject: hilbertL, hilbertR
        Combine to stereo
        result = selected("Sound")
        removeObject: leftIn, rightIn, hilbertL, hilbertR

    else
        # === Envelope LEFT ===
        selectObject: leftIn
        envelopeL = Copy: "envelopeL_" + uniqueID$
        Formula: "sqrt(self^2 + Sound_hilbertL_'uniqueID$'[col]^2)"

        if envelope_smoothing_ms > 0
            smoothHz = 1000 / envelope_smoothing_ms
            if smoothHz < nyquist
                selectObject: envelopeL
                Filter (pass Hann band): 0, smoothHz, smoothHz * 0.2
                smoothedL = selected("Sound")
                removeObject: envelopeL
                envelopeL = smoothedL
                Rename: "envelopeL_" + uniqueID$
            endif
        endif

        selectObject: envelopeL
        envMaxL = Get maximum: 0, 0, "Sinc70"
        if envMaxL > 0.0001
            Formula: "max(0.001, self / 'envMaxL')"
        else
            Formula: "0.001"
        endif

        # === Envelope RIGHT ===
        selectObject: rightIn
        envelopeR = Copy: "envelopeR_" + uniqueID$
        Formula: "sqrt(self^2 + Sound_hilbertR_'uniqueID$'[col]^2)"

        if envelope_smoothing_ms > 0
            smoothHz = 1000 / envelope_smoothing_ms
            if smoothHz < nyquist
                selectObject: envelopeR
                Filter (pass Hann band): 0, smoothHz, smoothHz * 0.2
                smoothedR = selected("Sound")
                removeObject: envelopeR
                envelopeR = smoothedR
                Rename: "envelopeR_" + uniqueID$
            endif
        endif

        selectObject: envelopeR
        envMaxR = Get maximum: 0, 0, "Sinc70"
        if envMaxR > 0.0001
            Formula: "max(0.001, self / 'envMaxR')"
        else
            Formula: "0.001"
        endif

        if output_mode = 4
            # NORMALIZED ENVELOPE: combine the normalized envelope channels
            # directly; no output copies are needed.
            selectObject: envelopeL, envelopeR
            Combine to stereo
            result = selected("Sound")
            removeObject: leftIn, rightIn, hilbertL, hilbertR, envelopeL, envelopeR

        else
            # TRANSIENT / ENVELOPE-SHAPED LEFT
            selectObject: leftIn
            outputL = Copy: "outputL_" + uniqueID$
            if output_mode = 1
                exponent = transient_amount - 1
                Formula: "self * Sound_envelopeL_'uniqueID$'[col]^'exponent'"
            else
                Formula: "self * Sound_envelopeL_'uniqueID$'[col]"
            endif

            # TRANSIENT / ENVELOPE-SHAPED RIGHT
            selectObject: rightIn
            outputR = Copy: "outputR_" + uniqueID$
            if output_mode = 1
                exponent = transient_amount - 1
                Formula: "self * Sound_envelopeR_'uniqueID$'[col]^'exponent'"
            else
                Formula: "self * Sound_envelopeR_'uniqueID$'[col]"
            endif

            selectObject: outputL, outputR
            Combine to stereo
            result = selected("Sound")

            removeObject: leftIn, rightIn, hilbertL, hilbertR, envelopeL, envelopeR, outputL, outputR
        endif
    endif
endif

# ============================================================
# Dry/wet mix
# ============================================================
if dry_wet_mix > 0 and dry_wet_mix < 1
    # Robust dry reference: copy the original under a safe ID-based name so the
    # mix formula never depends on the user's object name (spaces/punctuation).
    selectObject: sound
    dryCopy = Copy: "dry_" + uniqueID$
    selectObject: result
    Formula: "'dry_wet_mix' * self + (1 - 'dry_wet_mix') * Sound_dry_'uniqueID$'[row, col]"
    removeObject: dryCopy
endif

selectObject: result
if scale_peak > 0
    Scale peak: scale_peak
endif
# Spectrum -> Sound resets the time domain to zero. Restore the source
# start time for every wet path; dry bypass already has the same xmin, so
# shifting to the same start time is a no-op there.
Shift times to: "start time", originalXmin
Rename: originalName$ + "_" + modeName$

finalOutput = selected("Sound")

# ============================================================
# VISUALIZATION - Praat AudioTools house style
# ============================================================
if draw_visualization
    appendInfoLine: "Creating AudioTools visualization..."

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    # Visualization uses mono display copies only; processing output is untouched.
    selectObject: sound
    if numChannels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "viz_input_" + uniqueID$
    endif

    selectObject: finalOutput
    if numChannels > 1
        resultMono = Convert to mono
    else
        resultMono = Copy: "viz_output_" + uniqueID$
    endif

    # The diagnostic layout uses a 0-based display time axis. Keep the audio
    # object's original time domain intact and shift only the visualization
    # copies to zero.
    selectObject: origMono
    Shift times to: "start time", 0
    selectObject: resultMono
    Shift times to: "start time", 0

    # Human-readable display label.
    if output_mode = 1
        modeLabel$ = "Transient Enhanced"
    elsif output_mode = 2
        modeLabel$ = "Envelope Shaped"
    elsif output_mode = 3
        modeLabel$ = "Hilbert 90deg"
    else
        modeLabel$ = "Normalized Envelope"
    endif

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Hilbert Transform Envelope v0.7.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + preset$

    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: origMono
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: resultMono
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Paired spectrograms
    # ----------------------------------------------------------
    vizMaxHz = min(8000, nyquist)
    if vizMaxHz > 100
        Select outer viewport: 0, 4.1, 2.24, 3.64
        Select inner viewport: 0.55, 3.85, 2.34, 3.54
        selectObject: origMono
        To Spectrogram: 0.02, vizMaxHz, 0.005, 20, "Gaussian"
        vizSpecIn = selected("Spectrogram")
        Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
        removeObject: vizSpecIn
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Input spectrogram"

        Select outer viewport: 4.1, 8, 2.24, 3.64
        Select inner viewport: 4.40, 7.65, 2.34, 3.54
        selectObject: resultMono
        To Spectrogram: 0.02, vizMaxHz, 0.005, 20, "Gaussian"
        vizSpecOut = selected("Spectrogram")
        Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
        removeObject: vizSpecOut
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Processed output"
    endif

    # ----------------------------------------------------------
    # Waveform-detail diagnostic: first 50 ms (or full sound)
    # ----------------------------------------------------------
    detailEnd = min(0.05, duration)
    if detailEnd <= 0
        detailEnd = duration
    endif

    selectObject: origMono
    inMin = Get minimum: 0, detailEnd, "Sinc70"
    inMax = Get maximum: 0, detailEnd, "Sinc70"
    selectObject: resultMono
    outMin = Get minimum: 0, detailEnd, "Sinc70"
    outMax = Get maximum: 0, detailEnd, "Sinc70"
    detailMin = min(inMin, outMin)
    detailMax = max(inMax, outMax)
    if detailMax <= detailMin
        detailMin = detailMin - 1
        detailMax = detailMax + 1
    endif
    detailPad = 0.08 * (detailMax - detailMin)
    detailMin = detailMin - detailPad
    detailMax = detailMax + detailPad

    Select outer viewport: 0, 8, 3.72, 4.92
    Select inner viewport: 0.55, 7.65, 3.80, 4.84
    selectObject: origMono
    Colour: "{0.68, 0.68, 0.68}"
    Draw: 0, detailEnd, detailMin, detailMax, "no", "Curve"
    selectObject: resultMono
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, detailEnd, detailMin, detailMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "First " + fixed$(detailEnd * 1000, 0) + " ms  |  gray=input  blue=output"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.02, 5.72
    Select inner viewport: 0.55, 7.65, 5.08, 5.66
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.48, "half",
        ... "Mode: " + modeLabel$
        ... + "  |  Preset: " + preset$
        ... + "  |  Channels: " + string$(numChannels)
        ... + "  |  SR: " + fixed$(sampleRate, 0) + " Hz"
    if output_mode = 1
        extraParam$ = "Transient amount: " + fixed$(transient_amount, 2)
            ... + "  |  Smoothing: " + fixed$(envelope_smoothing_ms, 1) + " ms"
    elsif output_mode = 3
        extraParam$ = "Phase rotation: 90 deg  |  DC/Nyquist removed"
    else
        extraParam$ = "Smoothing: " + fixed$(envelope_smoothing_ms, 1) + " ms"
    endif
    if scale_peak > 0
        peakText$ = fixed$(scale_peak, 2)
    else
        peakText$ = "off"
    endif
    Text: 0.02, "left", 0.18, "half",
        ... extraParam$
        ... + "  |  Wet: " + fixed$(dry_wet_mix * 100, 0) + "%"
        ... + "  |  Peak norm: " + peakText$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: origMono, resultMono
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=========================="
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", selected$("Sound")

if play_after_processing
    Play
endif