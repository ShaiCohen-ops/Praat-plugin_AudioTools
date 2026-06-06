# ============================================================
# Praat AudioTools - ChirikovStandardMap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chirikov Standard Map (kicked rotor) synthesis:
#   p[n+1] = p[n] + K*sin(theta[n])
#   theta[n+1] = theta[n] + p[n+1] (mod 2*pi)
#
#   K < 0.97: Periodic/quasiperiodic orbits
#   K ~ 0.97: KAM threshold, onset of global chaos
#   K > 0.97: Mixed phase space, increasing chaos
#   K >> 1: Strong chaos, diffusive behavior
#
# Algorithmic note on FM mode (mapping_mode = 3):
#   The instantaneous frequency in FM mode ranges from
#   base_frequency_Hz to base_frequency_Hz + frequency_range_Hz.
#   Phase is accumulated at control_rate_Hz, then resampled.
#   If max instantaneous frequency exceeds control_rate_Hz / 2,
#   the phase signal aliases. v0.3's parameter-report panel
#   flags this when it happens. The "Frequency Shimmer" preset
#   intentionally operates in this regime — chaotic aliasing
#   IS the shimmer character. To eliminate aliasing, raise
#   control_rate_Hz to at least 2 * (base + range).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. Same Chirikov iteration,
#     same 7 presets, same control-rate-then-resample
#     architecture, same fade and Scale peak.
#   - Form syntax modernized: `optionmenu Preset:` and
#     `optionmenu Mapping_mode:` (added colons).
#   - Dropped 6 decorative `comment === ... ===` form section
#     dividers.
#   - Visualization rewritten to suite 8x8 standard (v0.2 was a
#     single phase-space plot in a 7-wide viewport with title
#     and footer):
#       Title bar + metadata subtitle (preset, K, KAM context,
#         mode, initial conditions)
#       Panel A (left, headline): phase-space trajectory —
#         PRESERVED v0.2 design (black background, blue->cyan->
#         green->yellow->red time gradient, no wrap-around lines)
#       Panel B (right, headline): parameter report — preset,
#         K value with KAM threshold context, mapping mode,
#         initial conditions, frequency parameters (FM mode),
#         control rate, aliasing warning when applicable
#       Panel C: zoom audio waveform (first 100 ms) — shows the
#         synthesized output's character at small scale
#       Panel D: full audio waveform — the complete synthesized
#         signal
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Control-rate iteration + resampling (100x faster)
#   - Large phase space visualization with color gradient
#   - Added fade in/out
#   - Modern syntax throughout
# ============================================================

form Chirikov Standard Map Generator
    optionmenu Preset: 1
        option Custom (use settings below)
        option Periodic Islands (K=0.5)
        option KAM Threshold (K=0.97)
        option Partial Chaos (K=1.5)
        option Strong Chaos (K=5.0)
        option Frequency Shimmer (FM)
        option Stereo Chaos
        option Deep Chaos Drone
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Control_rate_Hz 2000
    real Initial_theta 0.5
    real Initial_p 0.0
    positive K_parameter 1.5
    optionmenu Mapping_mode: 1
        option Theta to Amplitude
        option P to Amplitude
        option Theta to Frequency (FM)
        option Theta+P Stereo
    positive Base_frequency_Hz 220
    positive Frequency_range_Hz 880
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Periodic Islands (K < 0.97, stable KAM tori)
    k_parameter = 0.5
    initial_theta = 0.5
    initial_p = 0.0
    mapping_mode = 1
    preset_name$ = "PeriodicIslands"
elsif preset = 3
    # KAM Threshold (K ~ 0.971635, critical transition)
    k_parameter = 0.971635
    initial_theta = 1.0
    initial_p = 0.5
    mapping_mode = 3
    preset_name$ = "KAMThreshold"
elsif preset = 4
    # Partial Chaos (mixed phase space)
    k_parameter = 1.5
    initial_theta = 0.5
    initial_p = 0.0
    mapping_mode = 1
    preset_name$ = "PartialChaos"
elsif preset = 5
    # Strong Chaos (diffusive)
    k_parameter = 5.0
    initial_theta = 0.1
    initial_p = 0.1
    mapping_mode = 2
    preset_name$ = "StrongChaos"
elsif preset = 6
    # Frequency Shimmer (FM synthesis)
    k_parameter = 2.5
    initial_theta = 1.57
    initial_p = 0.0
    mapping_mode = 3
    base_frequency_Hz = 440
    frequency_range_Hz = 1760
    preset_name$ = "FrequencyShimmer"
elsif preset = 7
    # Stereo Chaos
    k_parameter = 3.0
    initial_theta = 0.8
    initial_p = 0.3
    mapping_mode = 4
    preset_name$ = "StereoChaos"
elsif preset = 8
    # Deep Chaos Drone
    duration_s = 10.0
    k_parameter = 4.0
    initial_theta = 0.1
    initial_p = 0.2
    mapping_mode = 3
    base_frequency_Hz = 55
    frequency_range_Hz = 110
    control_rate_Hz = 500
    preset_name$ = "DeepChaosDrone"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# Mapping mode short label for visualization
if mapping_mode = 1
    modeShort$ = "Theta->Amp"
elsif mapping_mode = 2
    modeShort$ = "P->Amp"
elsif mapping_mode = 3
    modeShort$ = "Theta->FM"
else
    modeShort$ = "Theta+P stereo"
endif

# Chaos regime label
if k_parameter < 0.97
    chaosLabel$ = "below KAM (periodic/quasiperiodic)"
elsif k_parameter < 1.5
    chaosLabel$ = "near KAM (mixed phase space)"
else
    chaosLabel$ = "above KAM (chaotic)"
endif

# Aliasing check for FM mode
fmMaxFreq = base_frequency_Hz + frequency_range_Hz
controlNyquist = control_rate_Hz / 2
fmAliased = 0
if mapping_mode = 3 and fmMaxFreq > controlNyquist
    fmAliased = 1
endif

# === Info ===
writeInfoLine: "=== Chirikov Standard Map Generator v0.3 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "K parameter: ", k_parameter
appendInfoLine: "  ", chaosLabel$
appendInfoLine: "Mode: ", mapping_mode$
if mapping_mode = 3
    appendInfoLine: "FM range: ", base_frequency_Hz, "-", fmMaxFreq, " Hz"
    appendInfoLine: "Control Nyquist: ", controlNyquist, " Hz"
    if fmAliased
        appendInfoLine: "  -> FM aliased (max freq > control Nyquist)"
    endif
endif
appendInfoLine: ""

# === Create control-rate signals ===
appendInfoLine: "Iterating Chirikov map at control rate..."

thetaCtrl = Create Sound from formula: "theta_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
pCtrl = Create Sound from formula: "p_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"

if mapping_mode = 3
    phaseCtrl = Create Sound from formula: "phase_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
endif

selectObject: thetaCtrl
nControlPoints = Get number of samples
timeStep = 1 / control_rate_Hz

# Initialize map state
theta = initial_theta
p = initial_p

# For phase accumulation in FM mode
phase = 0

# Store for visualization
if draw_visualization
    maxDrawPoints = min(nControlPoints, 5000)
    drawStride = max(1, floor(nControlPoints / maxDrawPoints))
    drawCount = 0
endif

# === Iterate the Chirikov map ===
for cp to nControlPoints
    # Chirikov Standard Map equations:
    # p[n+1] = p[n] + K * sin(theta[n])
    # theta[n+1] = theta[n] + p[n+1] (mod 2*pi)
    
    p = p + k_parameter * sin(theta)
    theta = theta + p
    
    # Wrap theta to [0, 2pi)
    theta = theta - twoPi * floor(theta / twoPi)
    
    # Store values
    selectObject: thetaCtrl
    Set value at sample number: 1, cp, theta
    selectObject: pCtrl
    Set value at sample number: 1, cp, p
    
    # FM mode: accumulate phase
    if mapping_mode = 3
        currentFreq = base_frequency_Hz + (theta / twoPi) * frequency_range_Hz
        phase = phase + twoPi * currentFreq * timeStep
        if phase > twoPi * 1000
            phase = phase - twoPi * 1000
        endif
        selectObject: phaseCtrl
        Set value at sample number: 1, cp, phase
    endif
    
    # Store for visualization
    if draw_visualization and (cp mod drawStride = 0)
        drawCount = drawCount + 1
        phaseSpace_theta[drawCount] = theta
        phaseSpace_p[drawCount] = p
    endif
endfor

# === Resample to audio rate ===
appendInfoLine: "Resampling to audio rate..."

selectObject: thetaCtrl
thetaAudio = Resample: sample_rate_Hz, 50
thetaAudioName$ = "theta_audio_" + uid$
Rename: thetaAudioName$

selectObject: pCtrl
pAudio = Resample: sample_rate_Hz, 50
pAudioName$ = "p_audio_" + uid$
Rename: pAudioName$

if mapping_mode = 3
    selectObject: phaseCtrl
    phaseAudio = Resample: sample_rate_Hz, 50
    phaseAudioName$ = "phase_audio_" + uid$
    Rename: phaseAudioName$
endif

# === Synthesize audio ===
appendInfoLine: "Synthesizing audio..."

if mapping_mode = 1
    # Theta to Amplitude
    outputSound = Create Sound from formula: "chirikov_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "(Sound_'thetaAudioName$'[] / pi) - 1"

elsif mapping_mode = 2
    # P to Amplitude (use sin to bound it)
    outputSound = Create Sound from formula: "chirikov_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "sin(Sound_'pAudioName$'[])"

elsif mapping_mode = 3
    # FM Synthesis
    outputSound = Create Sound from formula: "chirikov_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "sin(Sound_'phaseAudioName$'[])"

elsif mapping_mode = 4
    # Stereo: Theta=Left, P=Right
    leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "(Sound_'thetaAudioName$'[] / pi) - 1"
    rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "sin(Sound_'pAudioName$'[])"
    
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "chirikov_" + uid$
    
    removeObject: leftSound, rightSound
endif

# === Cleanup control-rate objects ===
removeObject: thetaCtrl, pCtrl, thetaAudio, pAudio
if mapping_mode = 3
    removeObject: phaseCtrl, phaseAudio
endif

# === Apply fade ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

selectObject: outputSound
Rename: "chirikov_" + preset_name$

# Capture stats for visualization
selectObject: outputSound
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
outputNumCh = Get number of channels

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing phase space + audio..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization  (8 x 8 canvas — suite standard)
# ==============================================================================
procedure drawVisualization
    
    Erase all
    Black
    Plain line
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##CHIRIKOV STANDARD MAP##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... preset_name$
        ... + "  |  K = " + fixed$(k_parameter, 4)
        ... + "  |  " + chaosLabel$
        ... + "  |  " + modeShort$
        ... + "  |  theta0 = " + fixed$(initial_theta, 2)
        ... + "  |  p0 = " + fixed$(initial_p, 2)
        ... + "  |  " + string$(drawCount) + " iter"

    # ----------------------------------------------------------
    # PANEL A: PHASE-SPACE TRAJECTORY  (left, headline)
    # Black background, blue->cyan->green->yellow->red gradient.
    # Preserved from v0.2 design.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, twoPi, -10, 10
    Paint rectangle: "Black", 0, twoPi, -10, 10
    
    Line width: 1
    
    for .i from 2 to drawCount
        .theta1 = phaseSpace_theta[.i - 1]
        .theta2 = phaseSpace_theta[.i]
        .p1 = phaseSpace_p[.i - 1]
        .p2 = phaseSpace_p[.i]
        
        # Clamp p for display
        if .p1 > 10
            .p1 = 10
        elsif .p1 < -10
            .p1 = -10
        endif
        if .p2 > 10
            .p2 = 10
        elsif .p2 < -10
            .p2 = -10
        endif
        
        # Time-based color: Blue -> Cyan -> Green -> Yellow -> Red
        .t = (.i - 1) / drawCount
        
        if .t < 0.25
            .phase_g = .t / 0.25
            .r = 0
            .g = .phase_g
            .b = 1
        elsif .t < 0.5
            .phase_g = (.t - 0.25) / 0.25
            .r = 0
            .g = 1
            .b = 1 - .phase_g
        elsif .t < 0.75
            .phase_g = (.t - 0.5) / 0.25
            .r = .phase_g
            .g = 1
            .b = 0
        else
            .phase_g = (.t - 0.75) / 0.25
            .r = 1
            .g = 1 - .phase_g
            .b = 0
        endif
        
        Colour: "{" + fixed$(.r, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(.b, 3) + "}"
        
        # Don't draw wrap-around lines
        if abs(.theta2 - .theta1) < pi
            Draw line: .theta1, .p1, .theta2, .p2
        endif
    endfor
    
    Line width: 1
    Colour: "{0.5, 0.5, 0.5}"
    Draw inner box
    
    Colour: "White"
    Font size: 5
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 5, "yes", "yes", "no"
    
    Colour: "Black"
    Font size: 6
    Text left: "yes", "p (momentum)"
    Text bottom: "yes", "theta (radians)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Map:"
    
    Font size: 11
    Colour: "{0.55, 0.35, 0.78}"
    Text: 0.10, "left", 0.85, "half", "##K = " + fixed$(k_parameter, 4) + "##"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.79, "half", chaosLabel$
    Text: 0.10, "left", 0.74, "half", "(KAM critical K* = 0.971635)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.66, "half", "Initial conditions:"
    
    Font size: 10
    Colour: "{0.20, 0.50, 0.82}"
    Text: 0.10, "left", 0.59, "half", "theta_0 = " + fixed$(initial_theta, 4)
    Text: 0.10, "left", 0.52, "half", "p_0     = " + fixed$(initial_p, 4)
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.44, "half", "Sonification:"
    
    Font size: 10
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.37, "half", "Mode:    " + modeShort$
    if mapping_mode = 3
        Text: 0.10, "left", 0.30, "half", "Freq:    " + fixed$(base_frequency_Hz, 0) + "-" + fixed$(fmMaxFreq, 0) + " Hz"
    else
        Text: 0.10, "left", 0.30, "half", "Channels: " + string$(outputNumCh)
    endif
    Text: 0.10, "left", 0.23, "half", "Control: " + fixed$(control_rate_Hz, 0) + " Hz"
    Text: 0.10, "left", 0.16, "half", "Audio:   " + fixed$(sample_rate_Hz, 0) + " Hz"
    
    # Aliasing warning (only in FM mode when applicable)
    if fmAliased
        Font size: 7
        Colour: "{0.82, 0.30, 0.25}"
        Text: 0.05, "left", 0.08, "half", "FM aliased:"
        Font size: 7
        Colour: "{0.55, 0.25, 0.20}"
        Text: 0.10, "left", 0.02, "half", "max " + fixed$(fmMaxFreq, 0) + " Hz > control Nyq " + fixed$(controlNyquist, 0) + " Hz"
    else
        Font size: 7
        if mapping_mode = 3
            Colour: "{0.30, 0.55, 0.30}"
            Text: 0.05, "left", 0.05, "half", "FM within control Nyquist (no aliasing)"
        else
            Colour: "{0.30, 0.55, 0.30}"
            Text: 0.05, "left", 0.05, "half", "Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        endif
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Phase space (color = time: blue->cyan->green->yellow->red)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM AUDIO WAVEFORM  (first 100 ms)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.1
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    # Mono copy for waveform display (output may be stereo for mode 4)
    selectObject: outputSound
    if outputNumCh > 1
        Convert to mono
        zoomCopy = selected("Sound")
    else
        Copy: "zoom_copy"
        zoomCopy = selected("Sound")
    endif
    
    selectObject: zoomCopy
    z_peak = Get absolute extremum: 0, zoomDur, "None"
    if z_peak < 0.001
        z_peak = 0.001
    endif
    z_amp = z_peak * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    selectObject: zoomCopy
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    removeObject: zoomCopy
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms (synthesized output)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL AUDIO WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: outputSound
    if outputNumCh > 1
        Convert to mono
        fullCopy = selected("Sound")
    else
        Copy: "full_copy"
        fullCopy = selected("Sound")
    endif
    
    selectObject: fullCopy
    out_peak_v = Get absolute extremum: 0, 0, "None"
    if out_peak_v < 0.001
        out_peak_v = 0.001
    endif
    out_amp = out_peak_v * 1.15
    
    Axes: 0, finalDur, -out_amp, out_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -out_amp, out_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: fullCopy
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, finalDur, -out_amp, out_amp, "no", "Curve"
    
    removeObject: fullCopy
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if outputNumCh > 1
        Text top: "no", "Full output (mono mix shown; stereo via " + modeShort$ + ")"
    else
        Text top: "no", "Full output (" + modeShort$ + ")"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if fmAliased
        aliasStr$ = "  |  FM aliased"
    else
        aliasStr$ = ""
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + preset_name$ + "##"
        ... + "  |  K = " + fixed$(k_parameter, 4)
        ... + "  |  " + chaosLabel$
        ... + "  |  Mode: " + modeShort$
        ... + "  |  theta_0 = " + fixed$(initial_theta, 3)
        ... + "  |  p_0 = " + fixed$(initial_p, 3)
        ... + aliasStr$
    
    if mapping_mode = 3
        Text: 0.02, "left", 0.28, "half",
            ... "FM: " + fixed$(base_frequency_Hz, 0) + "-" + fixed$(fmMaxFreq, 0) + " Hz"
            ... + "  |  Control: " + fixed$(control_rate_Hz, 0) + " Hz (Nyq " + fixed$(controlNyquist, 0) + ")"
            ... + "  |  Audio: " + fixed$(sample_rate_Hz, 0) + " Hz"
            ... + "  |  Iter: " + string$(drawCount)
            ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    else
        Text: 0.02, "left", 0.28, "half",
            ... "Control: " + fixed$(control_rate_Hz, 0) + " Hz"
            ... + "  |  Audio: " + fixed$(sample_rate_Hz, 0) + " Hz"
            ... + "  |  Iter: " + string$(drawCount)
            ... + "  |  Channels: " + string$(outputNumCh)
            ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
