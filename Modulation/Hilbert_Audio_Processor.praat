# ============================================================
# Praat AudioTools - Hilbert_Audio_Processor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Exact-length FFT Hilbert processor providing quadrature
#   transformation, single-sideband frequency shifting, envelope
#   extraction, and constant phase rotation.
#
#   Mono uses the L controls. For multichannel sounds, L controls are
#   applied to odd-numbered channels and R controls to even-numbered
#   channels. Sample rate, sample count, start time, duration, and all
#   channels are preserved.
#
# v1.4 changes:
#   - Replaces interpreted spectral antialias Formula calls with Praat's
#     compiled Hann-band filter using a sub-bin transition, preserving the
#     discrete brick-wall mask while reducing shift-mode runtime.
#   - Computes constant phase rotation directly in the frequency domain,
#     avoiding construction of a Hilbert Sound for that mode.
#   - Keeps v1.3 DSP semantics, routing, safety, and visualization unchanged.
#
# v1.3 changes:
#   - Renames misleading "No shift" mode to Hilbert transform (-90 deg).
#   - Uses exact-length FFT (no zero-padding) and handles DC/Nyquist
#     correctly, including odd sample counts.
#   - Preserves arbitrary channel counts and non-zero start times.
#   - Frequency-shift modulation uses local sound time.
#   - Adds exact 0% dry bypass and attenuation-only Safety_peak.
#   - Replaces Hann-band envelope smoothing with a one-pole envelope
#     low-pass whose parameter is an actual cutoff frequency.
#   - Avoids creating the envelope path when it is not requested.
#   - Updates visualization to the AudioTools house text layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Error: Please select exactly one Sound object."
endif

originalSound = selected("Sound")
baseName$ = selected$("Sound")

form Hilbert Audio Processor
    optionmenu Preset: 1
        option Custom
        option L: Shift Up (+50) / R: Shift Down (-50)
        option L: Envelope Only / R: Hilbert Phase
        option Stereo Shift Up (+200Hz)
        option Stereo Hilbert Phase

    comment --- Left / odd channels (or mono) ---
    choice Operation_L: 2
        option Hilbert transform (-90 deg)
        option Shift up
        option Shift down
        option Envelope only
        option Phase rotate
    real Shift_amount_Hz_L: 500.0
    real Phase_angle_degrees_L: 90.0

    comment --- Right / even channels ---
    choice Operation_R: 3
        option Hilbert transform (-90 deg)
        option Shift up
        option Shift down
        option Envelope only
        option Phase rotate
    real Shift_amount_Hz_R: 500.0
    real Phase_angle_degrees_R: 90.0

    comment --- Global ---
    boolean Antialiasing: 1
    real Dry_wet_percent: 100
    real Safety_peak: 0.99
    real Envelope_lowpass_Hz: 0
    boolean Play_output: 1
    boolean Draw_visualization: 1
endform

# ============================================================
# PRESET OVERRIDES
# ============================================================
presetName$ = preset$

if preset = 2
    operation_L$ = "Shift up"
    shift_amount_Hz_L = 50.0
    operation_R$ = "Shift down"
    shift_amount_Hz_R = 50.0
elsif preset = 3
    operation_L$ = "Envelope only"
    operation_R$ = "Hilbert transform (-90 deg)"
elsif preset = 4
    operation_L$ = "Shift up"
    shift_amount_Hz_L = 200.0
    operation_R$ = "Shift up"
    shift_amount_Hz_R = 200.0
elsif preset = 5
    operation_L$ = "Hilbert transform (-90 deg)"
    operation_R$ = "Hilbert transform (-90 deg)"
endif

# ============================================================
# VALIDATION / SOURCE METADATA
# ============================================================
selectObject: originalSound
numChannels = Get number of channels
sampleRate = Get sampling frequency
sampleCount = Get number of samples
originalStart = Get start time
originalDuration = Get total duration
nyquist = sampleRate / 2

# Clamp user controls to defensible ranges.
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))
shift_amount_Hz_L = min(nyquist, max(0, shift_amount_Hz_L))
shift_amount_Hz_R = min(nyquist, max(0, shift_amount_Hz_R))
envelope_lowpass_Hz = min(0.49 * sampleRate, max(0, envelope_lowpass_Hz))

appendInfoLine: "=== Hilbert Audio Processor v1.4 ==="
appendInfoLine: "Source: ", baseName$, " (", fixed$(originalDuration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sampleRate, 0), " Hz"
if numChannels = 1
    appendInfoLine: "Routing: mono -> L controls"
else
    appendInfoLine: "Routing: odd channels -> L controls | even channels -> R controls"
endif
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"

# ============================================================
# PROCESSING
# ============================================================
# True dry bypass: preserve the selected Sound sample-for-sample.
if dry_wet_percent <= 0
    selectObject: originalSound
    finalOutput = Copy: baseName$ + "_Hilbert_Processed"
else
    processedIDs# = zero#(numChannels)

    for ch from 1 to numChannels
        selectObject: originalSound
        Extract one channel: ch
        channelIn = selected("Sound")

        if ch = 1 or (ch mod 2 = 1)
            currentOp$ = operation_L$
            currentShift = shift_amount_Hz_L
            currentPhase = phase_angle_degrees_L
        else
            currentOp$ = operation_R$
            currentShift = shift_amount_Hz_R
            currentPhase = phase_angle_degrees_R
        endif

        @processChannel: channelIn, currentOp$, currentShift, currentPhase
        processedIDs#[ch] = outID_result
        removeObject: channelIn
    endfor

    if numChannels = 1
        finalOutput = processedIDs#[1]
        selectObject: finalOutput
        Rename: baseName$ + "_Hilbert_Processed"
    else
        selectObject: processedIDs#[1]
        for ch from 2 to numChannels
            plusObject: processedIDs#[ch]
        endfor
        Combine to stereo
        finalOutput = selected("Sound")
        Rename: baseName$ + "_Hilbert_Processed"
        for ch from 1 to numChannels
            removeObject: processedIDs#[ch]
        endfor
    endif

    # Linear dry/wet blend after all channels are reconstructed.
    if dry_wet_percent < 100
        globalWet = dry_wet_percent / 100
        globalDry = 1 - globalWet
        globalOriginal = originalSound
        selectObject: finalOutput
        Formula: "'globalWet' * self + 'globalDry' * object ['globalOriginal', row, col]"
    endif
endif

# Attenuation-only output safety. Never boost a quiet result.
selectObject: finalOutput
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if dry_wet_percent > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
outputPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "L/odd operation: ", operation_L$
if numChannels > 1
    appendInfoLine: "R/even operation: ", operation_R$
endif
appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(outputPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
else
    appendInfoLine: "Safety: disabled"
endif
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if draw_visualization
    @drawViz
endif

selectObject: finalOutput
if play_output
    Play
endif

# ============================================================
# DSP PROCEDURE - one mono channel
# ============================================================
procedure processChannel: .inSnd, .op$, .shiftHz, .phaseDeg
    selectObject: .inSnd
    .sr = Get sampling frequency
    .nx = Get number of samples
    .xmin = Get start time
    .dur = Get total duration
    .nyquist = .sr / 2

    # Internal processing always starts at t=0 so the modulation phase is
    # independent of the Sound object's absolute time domain.
    .work = .inSnd
    selectObject: .work
    if .xmin <> 0
        Shift times by: -.xmin
    endif

    # Exact no-op fast paths.
    if (.op$ = "Shift up" or .op$ = "Shift down") and .shiftHz <= 0
        .result = Copy: "hilbert_result"
    elsif .op$ = "Phase rotate" and abs(.phaseDeg) < 1e-15
        .result = Copy: "hilbert_result"
    else
        # Exact-length FFT avoids the zero-padding edge distortion produced
        # by To Spectrum "yes". The spectrum is one-sided, so multiplication
        # by -i produces the Hilbert/quadrature signal.
        selectObject: .work
        .spectrum = To Spectrum: "no"

        # Optional brick-wall-equivalent pre-bandlimit for single-sideband
        # shifting. Praat's compiled Hann-band filter is much faster than an
        # interpreted Spectrum Formula. The transition is one millionth of an
        # FFT bin, so sampled bins receive the same 0/1 mask except at
        # numerically pathological boundary coincidences.
        if antialiasing and (.op$ = "Shift up" or .op$ = "Shift down") and .shiftHz > 0
            .df = .sr / .nx
            .aaSmooth = max(1e-12, .df * 1e-6)
            selectObject: .spectrum
            if .op$ = "Shift up"
                globalLimitF = max(0, .nyquist - .shiftHz)
                Filter (pass Hann band): 0, globalLimitF + .aaSmooth, .aaSmooth
            else
                globalLimitF = min(.nyquist, .shiftHz)
                Filter (pass Hann band): max(1e-12, globalLimitF - .aaSmooth), 0, .aaSmooth
            endif
        endif

        if .nx mod 2 = 0
            globalNyquistCol = .nx / 2 + 1
        else
            globalNyquistCol = 0
        endif

        # Constant phase rotation can be done directly on the complex
        # positive-frequency spectrum. This is algebraically equivalent to
        # x*cos(theta) - Hilbert(x)*sin(theta), but avoids an extra Sound and
        # time-domain Formula pass. DC/Nyquist have zero Hilbert component and
        # therefore scale only by cos(theta).
        if .op$ = "Phase rotate"
            .theta = .phaseDeg * pi / 180
            globalCosT = cos(.theta)
            globalSinT = sin(.theta)
            globalSpectrum = .spectrum
            selectObject: .spectrum
            .phaseSpec = Copy: "phase_spec"
            Formula: "if col=1 or col='globalNyquistCol' then if row=1 then 'globalCosT'*object ['globalSpectrum',1,col] else 0 fi else if row=1 then 'globalCosT'*object ['globalSpectrum',1,col]-'globalSinT'*object ['globalSpectrum',2,col] else 'globalSinT'*object ['globalSpectrum',1,col]+'globalCosT'*object ['globalSpectrum',2,col] fi fi"
            .result = To Sound
            removeObject: .phaseSpec, .spectrum

        else
            # Hilbert spectrum. DC is always zero. The final FFT bin is Nyquist
            # only for an even sample count; for odd N it is a legitimate bin
            # and must not be discarded.
            selectObject: .spectrum
            .hilbertSpec = Copy: "hilbert_spec"
            globalSpectrum = .spectrum
            Formula: "if col=1 or col='globalNyquistCol' then 0 else if row=1 then object ['globalSpectrum', 2, col] else -object ['globalSpectrum', 1, col] fi fi"
            .hilbertSound = To Sound

            if .op$ = "Hilbert transform (-90 deg)"
                selectObject: .hilbertSound
                .result = Copy: "hilbert_result"

            elsif .op$ = "Envelope only"
            # Use the original exact waveform with the quadrature component.
            selectObject: .work
            .result = Copy: "hilbert_envelope"
            globalHilbert = .hilbertSound
            Formula: "sqrt(self^2 + object ['globalHilbert', row, col]^2)"

            # Optional first-order low-pass on the envelope.
            if envelope_lowpass_Hz > 0
                .alpha = exp(-2*pi*envelope_lowpass_Hz/.sr)
                globalEnvAlpha = .alpha
                Formula: "if col=1 then self else (1-'globalEnvAlpha')*self + 'globalEnvAlpha'*self[col-1] fi"
            endif

            else
                # Single-sideband frequency translation of the real analytic pair.
            globalShiftHz = .shiftHz
            globalHilbert = .hilbertSound

            # With antialiasing enabled, use the pre-bandlimited real part.
            if antialiasing and .shiftHz > 0
                selectObject: .spectrum
                .realForShift = To Sound
            else
                selectObject: .work
                .realForShift = Copy: "hilbert_real"
            endif

            selectObject: .realForShift
            .result = Copy: "hilbert_shift"
            if .op$ = "Shift up"
                Formula: "self*cos(2*pi*'globalShiftHz'*x) - object ['globalHilbert', row, col]*sin(2*pi*'globalShiftHz'*x)"
            else
                Formula: "self*cos(2*pi*'globalShiftHz'*x) + object ['globalHilbert', row, col]*sin(2*pi*'globalShiftHz'*x)"
            endif
                removeObject: .realForShift
            endif

            removeObject: .hilbertSound, .hilbertSpec, .spectrum
        endif
    endif

    selectObject: .result
    if .xmin <> 0
        Shift times by: .xmin
    endif
    Rename: "hilbert_channel"
    outID_result = .result
endproc

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
procedure drawViz
    selectObject: originalSound
    .sr = Get sampling frequency
    .nyq = .sr / 2
    .maxF = min(8000, .nyq)

    if numChannels = 1
        .opStr$ = operation_L$
    else
        .opStr$ = "odd: " + operation_L$ + " | even: " + operation_R$
    endif

    if antialiasing
        .aaStr$ = "on"
    else
        .aaStr$ = "off"
    endif

    if envelope_lowpass_Hz > 0
        .envStr$ = fixed$(envelope_lowpass_Hz, 0) + " Hz"
    else
        .envStr$ = "off"
    endif

    if safety_peak > 0
        .safeStr$ = fixed$(safety_peak, 2)
    else
        .safeStr$ = "off"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ---- TITLE ----
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Hilbert Audio Processor##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half", baseName$ + "  |  " + presetName$ + "  |  " + .opStr$

    # ---- INPUT WAVEFORM ----
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: originalSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- OUTPUT WAVEFORM ----
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    selectObject: finalOutput
    Colour: "{0.25, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Font size: 6
    Text left: "yes", "Amp"

    # ---- INPUT SPECTRUM ----
    Select outer viewport: 0, 4.2, 2.40, 4.40
    Select inner viewport: 0.55, 4.00, 2.60, 4.28
    selectObject: originalSound
    if numChannels > 1
        .inMono = Convert to mono
    else
        .inMono = Copy: "viz_in_mono"
    endif
    selectObject: .inMono
    .inSpec = To Spectrum: "no"
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, .maxF, 0, 0, "yes"
    removeObject: .inSpec, .inMono
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Input spectrum"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # ---- OUTPUT SPECTRUM ----
    Select outer viewport: 4.2, 8, 2.40, 4.40
    Select inner viewport: 4.55, 7.75, 2.60, 4.28
    selectObject: finalOutput
    .outCh = Get number of channels
    if .outCh > 1
        .outMono = Convert to mono
    else
        .outMono = Copy: "viz_out_mono"
    endif
    selectObject: .outMono
    .outSpec = To Spectrum: "no"
    Colour: "{0.25, 0.45, 0.80}"
    Draw: 0, .maxF, 0, 0, "yes"
    removeObject: .outSpec, .outMono
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output spectrum"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # ---- SUMMARY ----
    Select outer viewport: 0, 8, 4.50, 5.35
    Select inner viewport: 0.55, 7.75, 4.57, 5.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half", "L/odd: " + operation_L$ + "  |  R/even: " + operation_R$ + "  |  shift: " + fixed$(shift_amount_Hz_L, 0) + "/" + fixed$(shift_amount_Hz_R, 0) + " Hz  |  phase: " + fixed$(phase_angle_degrees_L, 0) + "/" + fixed$(phase_angle_degrees_R, 0) + " deg"
    Text: 0.02, "left", 0.20, "half", "Wet: " + fixed$(dry_wet_percent, 0) + "%  |  antialias: " + .aaStr$ + "  |  envelope LP: " + .envStr$ + "  |  safety: " + .safeStr$ + "  |  " + fixed$(originalDuration, 2) + " s / " + fixed$(sampleRate, 0) + " Hz / " + string$(numChannels) + " ch"

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
