# ============================================================
# Praat AudioTools - Advanced Chaotic Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Real Chaos Implementation
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic modulation synthesis using actual chaotic maps:
#   - Logistic map for frequency modulation
#   - Lorenz attractor for amplitude modulation
#   - Hénon map for filter/timbre modulation
#
# Usage:
#   Run this script (no input sound required).
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Implemented REAL chaotic maps (Logistic, Lorenz, Hénon)
#   - Fixed filter object handling
#   - Fixed double fade issue
#   - Modern Praat syntax throughout
#   - Added presets and visualization
# ============================================================

form Advanced Chaotic Modulation
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Logistic
        option Lorenz Drift
        option Hénon Stutter
        option Double Pendulum
        option Chaotic Bells
        option Insect Chorus
        option Deep Chaos
    
    comment === Basic Settings ===
    positive Duration_s 12
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 150
    integer Number_of_layers 3
    
    comment === Chaos Parameters ===
    real Logistic_r 3.9
    real Lorenz_sigma 10
    real Lorenz_rho 28
    real Lorenz_beta 2.667
    real Henon_a 1.4
    real Henon_b 0.3
    
    comment === Modulation ===
    real Freq_mod_depth 0.5
    real Amp_mod_depth 0.5
    positive Control_rate_Hz 500
    
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Logistic FM
        option Lorenz AM
        option Hénon Timbre
        option Combined Chaos
        option Layered Attractors
    
    comment === Output ===
    positive Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Gentle Logistic
    duration_s = 10
    base_frequency_Hz = 220
    number_of_layers = 2
    logistic_r = 3.7
    freq_mod_depth = 0.3
    amp_mod_depth = 0.2
    synthesis_mode = 1
    spatial_mode = 1
    preset_name$ = "GentleLogistic"
elsif preset = 3
    # Lorenz Drift
    duration_s = 15
    base_frequency_Hz = 110
    number_of_layers = 3
    lorenz_sigma = 10
    lorenz_rho = 28
    lorenz_beta = 2.667
    freq_mod_depth = 0.2
    amp_mod_depth = 0.6
    synthesis_mode = 2
    spatial_mode = 3
    preset_name$ = "LorenzDrift"
elsif preset = 4
    # Hénon Stutter
    duration_s = 8
    base_frequency_Hz = 300
    number_of_layers = 4
    henon_a = 1.4
    henon_b = 0.3
    freq_mod_depth = 0.4
    amp_mod_depth = 0.7
    synthesis_mode = 3
    spatial_mode = 2
    preset_name$ = "HenonStutter"
elsif preset = 5
    # Double Pendulum (Combined)
    duration_s = 12
    base_frequency_Hz = 180
    number_of_layers = 3
    logistic_r = 3.95
    lorenz_rho = 25
    freq_mod_depth = 0.5
    amp_mod_depth = 0.5
    synthesis_mode = 4
    spatial_mode = 3
    preset_name$ = "DoublePendulum"
elsif preset = 6
    # Chaotic Bells
    duration_s = 10
    base_frequency_Hz = 440
    number_of_layers = 5
    logistic_r = 3.85
    freq_mod_depth = 0.15
    amp_mod_depth = 0.4
    synthesis_mode = 5
    spatial_mode = 2
    preset_name$ = "ChaoticBells"
elsif preset = 7
    # Insect Chorus
    duration_s = 8
    base_frequency_Hz = 800
    number_of_layers = 6
    logistic_r = 3.99
    henon_a = 1.35
    freq_mod_depth = 0.6
    amp_mod_depth = 0.8
    control_rate_Hz = 800
    synthesis_mode = 4
    spatial_mode = 2
    preset_name$ = "InsectChorus"
elsif preset = 8
    # Deep Chaos
    duration_s = 20
    base_frequency_Hz = 55
    number_of_layers = 2
    lorenz_sigma = 12
    lorenz_rho = 30
    freq_mod_depth = 0.3
    amp_mod_depth = 0.7
    control_rate_Hz = 200
    synthesis_mode = 2
    spatial_mode = 3
    fade_time_s = 4
    preset_name$ = "DeepChaos"
endif

# === Validation ===
if number_of_layers > 8
    number_of_layers = 8
endif
if number_of_layers < 1
    number_of_layers = 1
endif
if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif
if logistic_r > 4
    logistic_r = 4
endif
if logistic_r < 3.5
    logistic_r = 3.5
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Info ===
writeInfoLine: "=== Advanced Chaotic Modulation ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "chaos_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Process each layer ===
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."
    
    # Layer-specific frequency (spread harmonically)
    if synthesis_mode = 5
        # Layered Attractors: harmonic series
        layerFreq = base_frequency_Hz * layer
        layerAmp = (0.6 / number_of_layers) / sqrt(layer)
    else
        # Other modes: slight frequency spread
        layerFreq = base_frequency_Hz * (0.9 + layer * 0.2)
        layerAmp = 0.6 / number_of_layers
    endif
    
    # --- Create control-rate sounds ---
    freqModCtrl = Create Sound from formula: "freqMod_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
    ampModCtrl = Create Sound from formula: "ampMod_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
    phaseCtrl = Create Sound from formula: "phase_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
    
    selectObject: freqModCtrl
    nControlPoints = Get number of samples
    timeStep = 1 / control_rate_Hz
    
    # --- Initialize chaotic systems with layer-dependent seeds ---
    # Logistic map state
    logX = 0.1 + layer * 0.1
    if logX > 0.9
        logX = 0.9
    endif
    
    # Lorenz system state
    lorX = 1.0 + layer * 0.5
    lorY = 1.0 + layer * 0.3
    lorZ = 1.0 + layer * 0.7
    
    # Hénon map state
    henX = 0.1 + layer * 0.05
    henY = 0.1 + layer * 0.03
    
    # Phase accumulator
    phase = 0
    
    # --- Iterate chaotic maps at control rate ---
    for cp to nControlPoints
        
        # === LOGISTIC MAP ===
        # x[n+1] = r * x[n] * (1 - x[n])
        logX = logistic_r * logX * (1 - logX)
        
        # === LORENZ SYSTEM (Euler integration) ===
        # dx/dt = sigma * (y - x)
        # dy/dt = x * (rho - z) - y
        # dz/dt = x * y - beta * z
        dt = timeStep * 10
        dlorX = lorenz_sigma * (lorY - lorX) * dt
        dlorY = (lorX * (lorenz_rho - lorZ) - lorY) * dt
        dlorZ = (lorX * lorY - lorenz_beta * lorZ) * dt
        lorX = lorX + dlorX
        lorY = lorY + dlorY
        lorZ = lorZ + dlorZ
        
        # Normalize Lorenz to [-1, 1] range (typical bounds are roughly [-20, 20])
        lorNorm = lorX / 20
        if lorNorm > 1
            lorNorm = 1
        elsif lorNorm < -1
            lorNorm = -1
        endif
        
        # === HÉNON MAP ===
        # x[n+1] = 1 - a * x[n]^2 + y[n]
        # y[n+1] = b * x[n]
        henXnew = 1 - henon_a * henX * henX + henY
        henYnew = henon_b * henX
        henX = henXnew
        henY = henYnew
        
        # Bound Hénon (can escape to infinity)
        if henX > 2
            henX = 0.1
            henY = 0.1
        elsif henX < -2
            henX = 0.1
            henY = 0.1
        endif
        henNorm = henX / 1.5
        if henNorm > 1
            henNorm = 1
        elsif henNorm < -1
            henNorm = -1
        endif
        
        # === Apply chaos to modulation based on mode ===
        if synthesis_mode = 1
            # Logistic FM
            freqMod = (logX - 0.5) * 2 * freq_mod_depth
            ampMod = 1
        elsif synthesis_mode = 2
            # Lorenz AM
            freqMod = 0
            ampMod = 0.5 + lorNorm * amp_mod_depth * 0.5
        elsif synthesis_mode = 3
            # Hénon Timbre (affects both)
            freqMod = henNorm * freq_mod_depth * 0.5
            ampMod = 0.5 + henNorm * amp_mod_depth * 0.5
        elsif synthesis_mode = 4
            # Combined Chaos
            freqMod = (logX - 0.5) * freq_mod_depth
            ampMod = 0.3 + lorNorm * amp_mod_depth * 0.3 + (henNorm + 1) * 0.2
        elsif synthesis_mode = 5
            # Layered Attractors (different chaos per layer)
            layerType = (layer - 1) mod 3
            if layerType = 0
                freqMod = (logX - 0.5) * freq_mod_depth
                ampMod = 0.7 + (logX - 0.5) * amp_mod_depth * 0.3
            elsif layerType = 1
                freqMod = lorNorm * freq_mod_depth * 0.3
                ampMod = 0.5 + lorNorm * amp_mod_depth * 0.5
            else
                freqMod = henNorm * freq_mod_depth * 0.5
                ampMod = 0.5 + henNorm * amp_mod_depth * 0.5
            endif
        endif
        
        # Bound amplitude modulation to positive values
        if ampMod < 0.05
            ampMod = 0.05
        endif
        if ampMod > 1
            ampMod = 1
        endif
        
        # Calculate instantaneous frequency
        instFreq = layerFreq * (1 + freqMod)
        if instFreq < 20
            instFreq = 20
        endif
        if instFreq > 10000
            instFreq = 10000
        endif
        
        # Accumulate phase
        phase = phase + twoPi * instFreq * timeStep
        
        # Store values
        selectObject: freqModCtrl
        Set value at sample number: 1, cp, freqMod
        selectObject: ampModCtrl
        Set value at sample number: 1, cp, ampMod * layerAmp
        selectObject: phaseCtrl
        Set value at sample number: 1, cp, phase
    endfor
    
    # --- Resample to audio rate ---
    selectObject: ampModCtrl
    ampAudio = Resample: sample_rate_Hz, 50
    ampAudioName$ = "ampAudio_" + uid$
    Rename: ampAudioName$
    
    selectObject: phaseCtrl
    phaseAudio = Resample: sample_rate_Hz, 50
    phaseAudioName$ = "phaseAudio_" + uid$
    Rename: phaseAudioName$
    
    # --- Synthesize layer ---
    layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz, "Sound_'ampAudioName$'[] * sin(Sound_'phaseAudioName$'[])"
    layerName$ = selected$("Sound")
    
    # Add to output
    selectObject: outputSound
    Formula: "self + Sound_'layerName$'[]"
    
    # Cleanup
    removeObject: freqModCtrl, ampModCtrl, phaseCtrl, ampAudio, phaseAudio, layerSound
endfor

# === Apply Fade (single pass) ===
appendInfoLine: "Applying envelope..."
selectObject: outputSound
Formula: "if x < fade_time_s then self * (x / fade_time_s) else self fi"
fadeOutStart = duration_s - fade_time_s
Formula: "if x > fadeOutStart then self * ((duration_s - x) / fade_time_s) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, 4000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 200, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "chaotic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.15 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.15 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "chaotic_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "chaotic_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSpectrogram: duration_s
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
# Procedure: drawSpectrogram
# ==============================================================================
procedure drawSpectrogram: .duration
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text top: "no", "Chaotic Modulation: " + preset_name$ + " (" + synthesis_mode$ + ")"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 0.6, 4.5
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    
    # Get mono version for spectrogram
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoForSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_for_spec"
        .monoForSpec = selected("Sound")
    endif
    
    selectObject: .monoForSpec
    .maxFreqSpec = min(6000, max(2000, base_frequency_Hz * number_of_layers * 3))
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoForSpec, .spec
    
    # Axis labels
    Select outer viewport: 0, .leftMargin, 0.6, 4.5
    Colour: "Black"
    Font size: 10
    Text: 0.5, "centre", 0.5, "half", "Hz"
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    Axes: 0, .duration, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 4.6, 5.0
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    if synthesis_mode = 1
        .chaosInfo$ = "Logistic r=" + fixed$(logistic_r, 2)
    elsif synthesis_mode = 2
        .chaosInfo$ = "Lorenz σ=" + fixed$(lorenz_sigma, 1) + " ρ=" + fixed$(lorenz_rho, 1)
    elsif synthesis_mode = 3
        .chaosInfo$ = "Hénon a=" + fixed$(henon_a, 2) + " b=" + fixed$(henon_b, 2)
    else
        .chaosInfo$ = "Combined"
    endif
    .paramText$ = .chaosInfo$ + " | FM: " + fixed$(freq_mod_depth, 2) + " | AM: " + fixed$(amp_mod_depth, 2) + " | Layers: " + string$(number_of_layers)
    Text top: "no", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc