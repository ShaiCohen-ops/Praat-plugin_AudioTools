# ============================================================
# Praat AudioTools - ChirikovStandardMap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.2 visual spacing (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chirikov Standard Map / kicked-rotor sonification:
#
#       p[n+1]     = p[n] + K sin(theta[n])
#       theta[n+1] = theta[n] + p[n+1]  (mod 2*pi)
#
#   The dynamics are evolved on the cylinder:
#       theta is wrapped modulo 2*pi
#       p is retained unwrapped
#
#   For visualization, p is additionally projected modulo 2*pi to [-pi,pi],
#   producing the familiar torus phase portrait without altering the dynamics.
#
#   IMPORTANT INTERPRETATION OF K:
#   Kc ~= 0.971635406 is the breakup threshold of the golden-mean spanning
#   invariant KAM curve. It is NOT a universal "chaos on/off" threshold:
#   resonant chaotic regions can exist below Kc, and stability islands can
#   remain above Kc. Above Kc, global momentum transport becomes possible.
#
# Sonification modes:
#   1. Theta -> AM:
#        A_theta = 0.5 [1 + cos(theta)]
#        y = A_theta sin(2*pi*f0*t)
#   2. P -> AM:
#        A_p = 0.5 [1 + sin(p)]
#        y = A_p sin(2*pi*f0*t)
#   3. Theta -> FM:
#        f_inst = f0 + (theta/2*pi) * frequency_range
#        phase is integrated at AUDIO sample rate
#   4. Theta + P stereo:
#        Left  = A_theta * carrier
#        Right = A_p     * carrier
#
# v0.4.3 visual refinement:
#   - Increased inter-panel spacing after runtime screenshot review.
#   - B/C/D share the time axis: tick labels remain in every panel, but
#     the explicit 'Time (s)' title appears only on the lowest panel D.
#   - Preserved a dedicated title strip above every data viewport.
#   - No DSP, map, preset, or sonification changes.
#
# v0.4 reviewed:
#   - Corrected the KAM interpretation: Kc is the breakup of the last
#     golden-mean spanning invariant curve, not a universal global-chaos switch.
#   - "Periodic Islands" preset moved into the primary stable island
#     (theta near pi, p=0), rather than near the hyperbolic fixed-point region.
#   - KAM preset uses an initial momentum near the golden-mean rotation value.
#   - K_parameter can now be zero (integrable limit).
#   - Added finite-time maximal Lyapunov estimate from the actual orbit using
#     the tangent map Jacobian; QC therefore reports orbit behavior, not K alone.
#   - FM architecture rewritten: frequency control is resampled, then phase is
#     accumulated at AUDIO rate. No resampling of phase and no phase resets.
#   - Removed intentional control-rate aliasing from Frequency Shimmer.
#   - Theta/P "Amplitude" modes are now genuine carrier AM, not direct playback
#     of low-rate control trajectories.
#   - Stereo mode is genuine theta-vs-p carrier AM; no mono fold-down in figures.
#   - Sonification control is derived at control rate then sinc-resampled.
#   - Nyquist guard is based on audio sample rate, not control-rate Nyquist.
#   - Replaced dynamic Sound_'name$' formula access with object-ID access.
#   - One combined edge fade; optional single final/common normalization.
#   - Added workload/range guards and measured RMS.
#   - Visualization rebuilt:
#       A actual map orbit projected to torus
#       B actual sonification control
#       C measured spectrogram + model frequency guide
#       D measured representative-channel waveform
#       process equation + compact dynamics/audio QC
# ============================================================

form Chirikov Standard Map Generator v0.4.3
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Periodic Island (K=0.5)
        option Near KAM Threshold (K=0.971635)
        option Partial Chaos (K=1.5)
        option Strong Chaos (K=5.0)
        option Frequency Shimmer (FM)
        option Stereo Chaos
        option Deep Chaos Drone

    comment === Map ===
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Control_rate_Hz 2000
    real Initial_theta 0.5
    real Initial_p 0.0
    real K_parameter 1.5

    comment === Sonification ===
    optionmenu Mapping_mode 1
        option Theta to Amplitude
        option P to Amplitude
        option Theta to Frequency (FM)
        option Theta+P Stereo
    positive Base_frequency_Hz 220
    positive Frequency_range_Hz 880

    comment === Output ===
    real Edge_fade_s 0.02
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    k_parameter = 0.5
    initial_theta = pi + 0.30
    initial_p = 0.0
    mapping_mode = 1
    base_frequency_Hz = 220
    preset_name$ = "Periodic Island"

elsif preset = 3
    k_parameter = 0.971635406
    initial_theta = 0.50
    initial_p = 2 * pi * ((sqrt(5) - 1) / 2)
    mapping_mode = 3
    base_frequency_Hz = 220
    frequency_range_Hz = 660
    preset_name$ = "Near KAM Threshold"

elsif preset = 4
    k_parameter = 1.5
    initial_theta = 0.5
    initial_p = 0.0
    mapping_mode = 1
    base_frequency_Hz = 220
    preset_name$ = "Partial Chaos"

elsif preset = 5
    k_parameter = 5.0
    initial_theta = 0.1
    initial_p = 0.1
    mapping_mode = 2
    base_frequency_Hz = 180
    preset_name$ = "Strong Chaos"

elsif preset = 6
    k_parameter = 2.5
    initial_theta = 1.57
    initial_p = 0.0
    mapping_mode = 3
    base_frequency_Hz = 440
    frequency_range_Hz = 1760
    preset_name$ = "Frequency Shimmer"

elsif preset = 7
    k_parameter = 3.0
    initial_theta = 0.8
    initial_p = 0.3
    mapping_mode = 4
    base_frequency_Hz = 220
    preset_name$ = "Stereo Chaos"

elsif preset = 8
    duration_s = 10.0
    k_parameter = 4.0
    initial_theta = 0.1
    initial_p = 0.2
    mapping_mode = 3
    base_frequency_Hz = 55
    frequency_range_Hz = 110
    control_rate_Hz = 500
    preset_name$ = "Deep Chaos Drone"
endif

# ---------------------------------------------------------------------------
# 1. CONSTANTS / VALIDATION
# ---------------------------------------------------------------------------
twoPi = 2 * pi
kCritical = 0.971635406

if duration_s <= 0
    exitScript: "Duration must be greater than zero."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if control_rate_Hz < 20 or control_rate_Hz > 20000
    exitScript: "Control rate must be between 20 and 20000 Hz."
endif
if duration_s * control_rate_Hz > 2000000
    exitScript: "Duration * control rate exceeds 2,000,000 map iterations. Reduce duration or control rate."
endif
if k_parameter < 0 or k_parameter > 50
    exitScript: "K parameter must be between 0 and 50."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if frequency_range_Hz < 0
    exitScript: "Frequency range cannot be negative."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

safeTop = 0.45 * sample_rate_Hz
nyquistAdjusted = 0

if mapping_mode = 3
    # Instantaneous-frequency guard. Rapid FM can still generate higher
    # sidebands, so 0.45*Fs leaves practical headroom.
    if base_frequency_Hz >= safeTop
        base_frequency_Hz = 0.5 * safeTop
        nyquistAdjusted = 1
    endif
    if base_frequency_Hz + frequency_range_Hz > safeTop
        frequency_range_Hz = max(0, safeTop - base_frequency_Hz)
        nyquistAdjusted = 1
    endif
else
    # AM shifts the control spectrum around the carrier. Reserve headroom
    # for approximately the control Nyquist bandwidth instead of checking
    # the carrier alone.
    controlBandwidthEstimate = min(0.5 * control_rate_Hz, 0.40 * sample_rate_Hz)
    maxAmCarrier = max(20, safeTop - controlBandwidthEstimate)
    if base_frequency_Hz > maxAmCarrier
        base_frequency_Hz = maxAmCarrier
        nyquistAdjusted = 1
    endif
endif

# Canonicalize initial theta for reporting and the first map step.
initialThetaWrapped = initial_theta - twoPi * floor(initial_theta / twoPi)

# Mapping labels.
if mapping_mode = 1
    modeShort$ = "Theta -> AM"
elsif mapping_mode = 2
    modeShort$ = "P -> AM"
elsif mapping_mode = 3
    modeShort$ = "Theta -> FM"
else
    modeShort$ = "Theta/P -> stereo AM"
endif

# Precise K-context label.
if k_parameter = 0
    chaosLabel$ = "integrable limit"
elsif k_parameter < kCritical - 0.03
    chaosLabel$ = "below Kc: spanning KAM barriers remain"
elsif k_parameter <= kCritical + 0.03
    chaosLabel$ = "near golden-mean KAM breakup"
elsif k_parameter < 4
    chaosLabel$ = "above Kc: global p transport possible; mixed phase space"
else
    chaosLabel$ = "strong-diffusion regime; stability islands may remain"
endif

uid$ = string$(randomInteger(10000, 99999))

# ---------------------------------------------------------------------------
# 2. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  CHIRIKOV STANDARD MAP v0.4.3"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "K: ", fixed$(k_parameter, 6)
appendInfoLine: "Context: ", chaosLabel$
appendInfoLine: "Initial theta: ", fixed$(initialThetaWrapped, 6)
appendInfoLine: "Initial p: ", fixed$(initial_p, 6)
appendInfoLine: "Mapping: ", modeShort$
appendInfoLine: "Control rate: ", fixed$(control_rate_Hz, 1), " iterations/s"
appendInfoLine: "Audio rate: ", sample_rate_Hz, " Hz"
if mapping_mode = 3
    appendInfoLine: "Instantaneous-frequency range requested: ",
        ... fixed$(base_frequency_Hz,1), "-", fixed$(base_frequency_Hz + frequency_range_Hz,1), " Hz"
else
    appendInfoLine: "Carrier: ", fixed$(base_frequency_Hz,1), " Hz"
endif
if nyquistAdjusted
    appendInfoLine: "Frequency parameters were reduced for audio-rate Nyquist safety."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 3. MAP TRAJECTORY AT CONTROL RATE
# ---------------------------------------------------------------------------
appendInfoLine: "Iterating standard map..."

thetaCtrl = Create Sound from formula: "ch_theta_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
pCtrl = Create Sound from formula: "ch_p_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"

selectObject: thetaCtrl
nControlPoints = Get number of samples
if nControlPoints < 4
    exitScript: "Too few map samples for this duration/control rate."
endif

# State on cylinder: theta wrapped, p unwrapped.
theta = initialThetaWrapped
p = initial_p
pMin = p
pMax = p

# Tangent vector for finite-time maximal Lyapunov estimate.
dTheta = 1
dP = 0
lyapSum = 0

# Visualization storage.
drawCount = 0
if draw_visualization
    maxDrawPoints = min(nControlPoints, 5000)
    drawStride = max(1, floor(nControlPoints / maxDrawPoints))
endif

for cp to nControlPoints
    # Tangent map uses theta[n] before the kick:
    # dP'     = dP + K cos(theta) dTheta
    # dTheta' = dTheta + dP'
    tangentP = dP + k_parameter * cos(theta) * dTheta
    tangentTheta = dTheta + tangentP
    tangentNorm = sqrt(tangentTheta*tangentTheta + tangentP*tangentP)

    if tangentNorm > 0
        lyapSum = lyapSum + ln(tangentNorm)
        dTheta = tangentTheta / tangentNorm
        dP = tangentP / tangentNorm
    endif

    # Standard map on the cylinder.
    p = p + k_parameter * sin(theta)
    theta = theta + p
    theta = theta - twoPi * floor(theta / twoPi)

    pMin = min(pMin, p)
    pMax = max(pMax, p)

    selectObject: thetaCtrl
    Set value at sample number: 1, cp, theta

    selectObject: pCtrl
    Set value at sample number: 1, cp, p

    if draw_visualization and (cp mod drawStride = 0)
        drawCount = drawCount + 1
        phaseSpace_theta[drawCount] = theta

        # Torus projection for visualization only.
        pWrapped = p - twoPi * floor((p + pi) / twoPi)
        phaseSpace_pWrapped[drawCount] = pWrapped
    endif
endfor

finiteLyapunov = lyapSum / nControlPoints
pSpan = pMax - pMin
pDrift = p - initial_p

appendInfoLine: "Finite-time Lyapunov / iteration: ", fixed$(finiteLyapunov, 6)
appendInfoLine: "Unwrapped p span: ", fixed$(pSpan, 3)
appendInfoLine: "Net p drift: ", fixed$(pDrift, 3)

# ---------------------------------------------------------------------------
# 4. BUILD ACTUAL SONIFICATION CONTROL
# ---------------------------------------------------------------------------
appendInfoLine: "Building audio-rate sonification control..."

controlA = 0
controlB = 0
frequencyAudio = 0

if mapping_mode = 1 or mapping_mode = 4
    thetaAmpCtrl = Create Sound from formula: "ch_theta_amp_" + uid$, 1, 0, duration_s, control_rate_Hz,
        ... "0.5 * (1 + cos(object[thetaCtrl,1,col]))"
    selectObject: thetaAmpCtrl
    thetaAmpAudio = Resample: sample_rate_Hz, 50
    controlA = thetaAmpAudio
endif

if mapping_mode = 2 or mapping_mode = 4
    pAmpCtrl = Create Sound from formula: "ch_p_amp_" + uid$, 1, 0, duration_s, control_rate_Hz,
        ... "0.5 * (1 + sin(object[pCtrl,1,col]))"
    selectObject: pAmpCtrl
    pAmpAudio = Resample: sample_rate_Hz, 50

    if mapping_mode = 2
        controlA = pAmpAudio
    else
        controlB = pAmpAudio
    endif
endif

if mapping_mode = 3
    frequencyCtrl = Create Sound from formula: "ch_freq_ctrl_" + uid$, 1, 0, duration_s, control_rate_Hz,
        ... "base_frequency_Hz + (object[thetaCtrl,1,col] / twoPi) * frequency_range_Hz"

    selectObject: frequencyCtrl
    frequencyAudio = Resample: sample_rate_Hz, 50
    controlA = frequencyAudio

    selectObject: frequencyAudio
    freqMinRealized = Get minimum: 0, 0, "None"
    freqMaxRealized = Get maximum: 0, 0, "None"
endif

# Control-rate theta/p objects are no longer needed for synthesis.
removeObject: thetaCtrl, pCtrl
if mapping_mode = 1 or mapping_mode = 4
    removeObject: thetaAmpCtrl
endif
if mapping_mode = 2 or mapping_mode = 4
    removeObject: pAmpCtrl
endif
if mapping_mode = 3
    removeObject: frequencyCtrl
endif

# ---------------------------------------------------------------------------
# 5. SYNTHESIZE AUDIO AT AUDIO SAMPLE RATE
# ---------------------------------------------------------------------------
appendInfoLine: "Synthesizing audio..."

if mapping_mode = 1 or mapping_mode = 2
    outputSound = Create Sound from formula: "chirikov_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "object[controlA,1,col] * sin(twoPi * base_frequency_Hz * x)"

elsif mapping_mode = 3
    phaseSound = Create Sound from formula: "ch_phase_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

    selectObject: phaseSound
    Formula: "if col = 1 then twoPi*object[frequencyAudio,1,col]/sample_rate_Hz else self[col-1] + twoPi*object[frequencyAudio,1,col]/sample_rate_Hz fi"

    outputSound = Create Sound from formula: "chirikov_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "sin(object[phaseSound,1,col])"

    removeObject: phaseSound

else
    leftSound = Create Sound from formula: "ch_left_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "object[controlA,1,col] * sin(twoPi * base_frequency_Hz * x)"

    rightSound = Create Sound from formula: "ch_right_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "object[controlB,1,col] * sin(twoPi * base_frequency_Hz * x)"

    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    outputSound = selected("Sound")
    removeObject: leftSound, rightSound
endif

# ---------------------------------------------------------------------------
# 6. EDGE FADE / NORMALIZATION
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s, 0.20 * duration_s)
if actualFade > 0
    fadeOutStart = duration_s - actualFade
    selectObject: outputSound
    Formula: "if x < actualFade then self*(x/actualFade) else if x > fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

if normalize_output
    selectObject: outputSound
    preNormPeak = Get absolute extremum: 0, 0, "None"
    if preNormPeak > 0
        Scale peak: 0.90
    endif
endif

safePreset$ = replace$(preset_name$, " ", "_", 0)
selectObject: outputSound
Rename: "chirikov_" + safePreset$

selectObject: outputSound
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
outputNumCh = Get number of channels

# ---------------------------------------------------------------------------
# 7. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# Remove helper controls after visualization.
if controlA > 0
    removeObject: controlA
endif
if controlB > 0
    removeObject: controlB
endif

# ---------------------------------------------------------------------------
# 8. PLAY / FINAL INFO
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: "RMS: ", fixed$(finalRMS, 4)
appendInfoLine: "Channels: ", outputNumCh
if mapping_mode = 3
    appendInfoLine: "Realized instantaneous frequency: ",
        ... fixed$(freqMinRealized,1), "-", fixed$(freqMaxRealized,1), " Hz"
endif
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .model$ = "{0.18,0.43,0.72}"
    .model2$ = "{0.72,0.35,0.22}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.06, 0.34
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "CHIRIKOV STANDARD MAP | " + preset_name$

    Select inner viewport: 0.35, 7.65, 0.38, 0.70
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.68, "half",
        ... "K " + fixed$(k_parameter,4) + " | " + chaosLabel$ + " | " + modeShort$
    Text: 0.5, "centre", 0.20, "half",
        ... "cylinder dynamics: theta mod 2*pi, p unwrapped | phase portrait below projects p mod 2*pi"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL MAP ORBIT + DIAGNOSTICS
    # Restores the strongest idea from the earlier visualization: a connected
    # trajectory whose colour encodes iteration/time.  The dynamics remain the
    # corrected v0.4 cylinder dynamics; only the display uses p mod 2*pi.
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.79, 1.00
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "A  ACTUAL STANDARD-MAP ORBIT | colour = iteration | torus projection + orbit diagnostics"

    # ---- A1. Phase-space trajectory ---------------------------------------
    Select inner viewport: 0.78, 5.08, 1.07, 2.28
    Axes: 0, twoPi, -pi, pi
    Paint rectangle: "Black", 0, twoPi, -pi, pi

    # Subtle reference grid on the torus.
    Colour: "{0.28,0.28,0.30}"
    Dotted line
    Draw line: pi, -pi, pi, pi
    Draw line: 0, 0, twoPi, 0
    Plain line

    # Connected orbit.  Time/iteration runs blue -> cyan -> green -> yellow -> red.
    # Do not connect across either torus wrap boundary.
    Line width: 1.05
    for .i from 2 to drawCount
        .theta1 = phaseSpace_theta[.i - 1]
        .theta2 = phaseSpace_theta[.i]
        .p1 = phaseSpace_pWrapped[.i - 1]
        .p2 = phaseSpace_pWrapped[.i]
        .progress = (.i - 1) / max(1, drawCount - 1)

        if .progress < 0.25
            .q = .progress / 0.25
            .r = 0
            .g = .q
            .b = 1
        elsif .progress < 0.50
            .q = (.progress - 0.25) / 0.25
            .r = 0
            .g = 1
            .b = 1 - .q
        elsif .progress < 0.75
            .q = (.progress - 0.50) / 0.25
            .r = .q
            .g = 1
            .b = 0
        else
            .q = (.progress - 0.75) / 0.25
            .r = 1
            .g = 1 - .q
            .b = 0
        endif

        Colour: "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"

        if abs(.theta2 - .theta1) < pi and abs(.p2 - .p1) < pi
            Draw line: .theta1, .p1, .theta2, .p2
        endif
    endfor

    # Mark the displayed start and end states.
    if drawCount >= 1
        Paint circle (mm): "White", phaseSpace_theta[1], phaseSpace_pWrapped[1], 1.2
        Paint circle (mm): "{1.0,0.25,0.12}", phaseSpace_theta[drawCount], phaseSpace_pWrapped[drawCount], 1.2
    endif

    Line width: 1
    Colour: "{0.58,0.58,0.60}"
    Draw inner box
    Colour: "White"
    Font size: 5
    Marks left: 5, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "p mod 2*pi"
    Text bottom: "yes", "theta (rad)"

    # ---- A2. Orbit / sonification diagnostics -----------------------------
    Select inner viewport: 5.25, 7.58, 1.07, 2.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955,0.955,0.960}", 0, 1, 0, 1

    # Dedicated header strip: keep the section title physically separate from
    # the large K value below it, so text cannot collide in this narrow panel.
    Paint rectangle: "{0.905,0.905,0.915}", 0, 1, 0.84, 1
    Font size: 7
    Colour: "{0.22,0.22,0.24}"
    Text: 0.06, "left", 0.92, "half", "ORBIT DIAGNOSTICS"

    Font size: 9
    Colour: .model$
    Text: 0.08, "left", 0.72, "half", "K = " + fixed$(k_parameter,4)

    Font size: 6
    Colour: "{0.28,0.28,0.30}"
    Text: 0.08, "left", 0.57, "half", "FTLE / iter   " + fixed$(finiteLyapunov,5)
    Text: 0.08, "left", 0.47, "half", "p span        " + fixed$(pSpan,2)
    Text: 0.08, "left", 0.37, "half", "net p drift   " + fixed$(pDrift,2)
    Text: 0.08, "left", 0.27, "half",
        ... "theta0 " + fixed$(initialThetaWrapped,3) + "   |   p0 " + fixed$(initial_p,3)

    Colour: "{0.72,0.35,0.22}"
    if mapping_mode = 3
        Text: 0.08, "left", 0.13, "half",
            ... modeShort$ + "   |   f " + fixed$(freqMinRealized,0) + "-" + fixed$(freqMaxRealized,0) + " Hz"
    else
        Text: 0.08, "left", 0.13, "half",
            ... modeShort$ + "   |   carrier " + fixed$(base_frequency_Hz,0) + " Hz"
    endif

    Colour: "{0.55,0.55,0.58}"
    Draw rectangle: 0, 1, 0, 1

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL SONIFICATION CONTROL
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.68, 2.90
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"

    if mapping_mode = 1
        Text: 0.5, "centre", 0.52, "half", "B  ACTUAL SONIFICATION CONTROL | theta-derived AM envelope"
    elsif mapping_mode = 2
        Text: 0.5, "centre", 0.52, "half", "B  ACTUAL SONIFICATION CONTROL | momentum-derived AM envelope"
    elsif mapping_mode = 3
        Text: 0.5, "centre", 0.52, "half", "B  ACTUAL SONIFICATION CONTROL | instantaneous frequency"
    else
        Text: 0.5, "centre", 0.52, "half", "B  ACTUAL SONIFICATION CONTROL | theta=L and momentum=R AM envelopes"
    endif

    Select inner viewport: .left, .right, 2.97, 4.00

    if mapping_mode = 3
        .fPad = max(10, 0.08 * (freqMaxRealized - freqMinRealized))
        .fLo = max(0, freqMinRealized - .fPad)
        .fHi = min(safeTop, freqMaxRealized + .fPad)
        if .fHi <= .fLo
            .fHi = .fLo + 10
        endif

        Axes: 0, duration_s, .fLo, .fHi
        Paint rectangle: .bg$, 0, duration_s, .fLo, .fHi
        selectObject: controlA
        Colour: .model$
        Draw: 0, 0, .fLo, .fHi, "no", "Curve"

        Colour: "Black"
        Draw inner box
        Marks left: 4, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "Frequency (Hz)"

    else
        Axes: 0, duration_s, 0, 1.05
        Paint rectangle: .bg$, 0, duration_s, 0, 1.05
        Colour: .grid$
        Dotted line
        Draw line: 0, 0.5, duration_s, 0.5
        Plain line

        selectObject: controlA
        Colour: .model$
        Draw: 0, 0, 0, 1.05, "no", "Curve"

        if mapping_mode = 4
            selectObject: controlB
            Colour: .model2$
            Draw: 0, 0, 0, 1.05, "no", "Curve"

            Axes: 0, duration_s, 0, 1.05
            Font size: 5
            Colour: .model$
            Text: 0.02*duration_s, "left", 0.96, "half", "L theta"
            Colour: .model2$
            Text: 0.02*duration_s, "left", 0.85, "half", "R p"
        endif

        Colour: "Black"
        Draw inner box
        Marks left: 3, "yes", "yes", "no"
        Marks bottom: 5, "yes", "yes", "no"
        Font size: 6
        Text left: "yes", "AM envelope"
    endif

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if outputNumCh = 1
        selectObject: outputSound
        Copy: "ch_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0, 0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL C: MODEL -> MEASUREMENT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 4.22, 4.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram with sonification-frequency guide"

    if mapping_mode = 3
        .specMax = min(safeTop, max(1000, 1.35 * freqMaxRealized))
    else
        # AM creates sidebands around the carrier; show enough range to see them.
        .specMax = min(safeTop, max(1000, base_frequency_Hz + 0.70 * control_rate_Hz))
    endif
    .specStep = max(0.002, duration_s / 1000)

    selectObject: .disp
    To Spectrogram: 0.025, .specMax, .specStep, 20, "Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left, .right, 4.51, 5.53
    selectObject: .spec
    Paint: 0, 0, 0, .specMax, 100, 1, 50, 6, 0, 0
    removeObject: .spec

    Axes: 0, duration_s, 0, .specMax
    Colour: .model$
    Line width: 1.2

    if mapping_mode = 3
        selectObject: controlA
        Draw: 0, 0, 0, .specMax, "no", "Curve"
    else
        if base_frequency_Hz <= .specMax
            Draw line: 0, base_frequency_Hz, duration_s, base_frequency_Hz
        endif
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED WAVEFORM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 5.76, 5.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "D  MEASURED OUTPUT | representative channel"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0, 0, "None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05 * .wavePeak

    Select inner viewport: .left, .right, 6.05, 6.78
    Axes: 0, duration_s, -.waveY, .waveY
    Paint rectangle: .bg$, 0, duration_s, -.waveY, .waveY
    selectObject: .disp
    Colour: .model2$
    Draw: 0, 0, -.waveY, .waveY, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # PROCESS + QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.55, 7.45, 7.08, 7.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02, "left", 0.77, "half",
        ... "MAP  |  p(n+1)=p(n)+K sin(theta(n)); theta(n+1)=theta(n)+p(n+1) mod 2*pi"

    Text: 0.02, "left", 0.52, "half",
        ... "DYNAMICS  |  K " + fixed$(k_parameter,4)
        ... + "  |  FTLE " + fixed$(finiteLyapunov,5) + "/iter"
        ... + "  |  p span " + fixed$(pSpan,2)
        ... + "  |  drift " + fixed$(pDrift,2)

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02, "left", 0.27, "half",
        ... "OUTPUT  |  " + modeShort$
        ... + "  |  peak " + fixed$(finalPeak,3)
        ... + "  |  RMS " + fixed$(finalRMS,4)
        ... + "  |  " + string$(outputNumCh) + " ch"
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
