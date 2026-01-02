# ============================================================
# Praat AudioTools - ChirikovStandardMap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chirikov Standard Map (kicked rotor) synthesis:
#   p[n+1] = p[n] + K*sin(θ[n])
#   θ[n+1] = θ[n] + p[n+1] (mod 2π)
#
#   K < 0.97: Periodic/quasiperiodic orbits
#   K ≈ 0.97: KAM threshold, onset of global chaos
#   K > 0.97: Mixed phase space, increasing chaos
#   K >> 1: Strong chaos, diffusive behavior
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Control-rate iteration + resampling (100x faster)
#   - Large phase space visualization with color gradient
#   - Added fade in/out
#   - Modern syntax throughout
# ============================================================

form Chirikov Standard Map Generator
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Periodic Islands (K=0.5)
        option KAM Threshold (K=0.97)
        option Partial Chaos (K=1.5)
        option Strong Chaos (K=5.0)
        option Frequency Shimmer (FM)
        option Stereo Chaos
        option Deep Chaos Drone
    
    comment === Basic Settings ===
    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Control_rate_Hz 2000
    
    comment === Initial Conditions ===
    real Initial_theta 0.5
    real Initial_p 0.0
    
    comment === Map Parameters ===
    positive K_parameter 1.5
    
    comment === Sonification ===
    optionmenu Mapping_mode 1
        option Theta to Amplitude
        option P to Amplitude
        option Theta to Frequency (FM)
        option Theta+P Stereo
    positive Base_frequency_Hz 220
    positive Frequency_range_Hz 880
    
    comment === Output ===
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
    # KAM Threshold (K ≈ 0.971635, critical transition)
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

# === Info ===
writeInfoLine: "=== Chirikov Standard Map Generator ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "K parameter: ", k_parameter
if k_parameter < 0.97
    appendInfoLine: "  (Below KAM threshold - periodic/quasiperiodic)"
elsif k_parameter < 1.5
    appendInfoLine: "  (Near KAM threshold - mixed phase space)"
else
    appendInfoLine: "  (Above KAM threshold - chaotic)"
endif
appendInfoLine: "Mode: ", mapping_mode$
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
    # p[n+1] = p[n] + K * sin(θ[n])
    # θ[n+1] = θ[n] + p[n+1] (mod 2π)
    
    p = p + k_parameter * sin(theta)
    theta = theta + p
    
    # Wrap theta to [0, 2π)
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

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing phase space..."
    @drawPhaseSpace
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
# Procedure: drawPhaseSpace
# ==============================================================================
procedure drawPhaseSpace
    
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text top: "no", "Chirikov Standard Map: K = " + fixed$(k_parameter, 4)
    
    # === Phase Space Plot ===
    Select inner viewport: 0.7, 6.5, 0.8, 6.3
    Axes: 0, twoPi, -10, 10
    
    # Paint background black AFTER setting axes
    Paint rectangle: "Black", 0, twoPi, -10, 10
    
    # Draw trajectory with time-based color gradient
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
        
        # Time-based color: Blue → Cyan → Green → Yellow → Red
        .t = (.i - 1) / drawCount
        
        if .t < 0.25
            .phase = .t / 0.25
            .r = 0
            .g = .phase
            .b = 1
        elsif .t < 0.5
            .phase = (.t - 0.25) / 0.25
            .r = 0
            .g = 1
            .b = 1 - .phase
        elsif .t < 0.75
            .phase = (.t - 0.5) / 0.25
            .r = .phase
            .g = 1
            .b = 0
        else
            .phase = (.t - 0.75) / 0.25
            .r = 1
            .g = 1 - .phase
            .b = 0
        endif
        
        Colour: "{" + fixed$(.r, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(.b, 3) + "}"
        
        # Don't draw wrap-around lines
        if abs(.theta2 - .theta1) < pi
            Draw line: .theta1, .p1, .theta2, .p2
        endif
    endfor
    
    # Axes
    Line width: 1
    Colour: "{0.5, 0.5, 0.5}"
    Draw inner box
    
    Colour: "White"
    Font size: 10
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 5, "yes", "yes", "no"
    
    Font size: 11
    Text bottom: "yes", "θ (radians)"
    Text left: "yes", "p (momentum)"
    
    # Footer
    Select outer viewport: 0, 7, 6.4, 7
    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    .infoText$ = "θ₀ = " + fixed$(initial_theta, 2) + "  |  p₀ = " + fixed$(initial_p, 2) + "  |  " + string$(drawCount) + " iterations  |  Color: time (blue→red)"
    Text top: "no", .infoText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc