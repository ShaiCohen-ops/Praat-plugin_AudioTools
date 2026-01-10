# ============================================================
# Praat AudioTools - Quantum_Uncertainty_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Quantum Uncertainty Reverb - uses quantum mechanics
#   metaphors for stochastic delay patterns. Simulates
#   Heisenberg uncertainty (more time uncertainty = less
#   amplitude precision) and state collapse vs superposition.
#   Each "quantum state" either collapses to a single echo
#   or spreads into multiple superposed substates based on
#   probability threshold.
#
# Changelog v0.2:
#   - Fixed selection and formula syntax
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Quantum Uncertainty Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Quantum
        option Medium Quantum
        option Heavy Quantum
        option Extreme Quantum
    
    comment === Quantum Parameters ===
    positive Tail_duration_s 1.0
    natural Quantum_states 35
    positive Uncertainty_stddev 0.35
    
    comment === State Collapse ===
    positive Collapse_threshold 0.65
    comment (probability for collapse vs superposition)
    natural Substates 4
    positive Substate_jitter_s 0.015
    
    comment === Amplitude ===
    positive Base_amplitude 0.25
    positive Time_mean_s 0.18
    positive Min_delay_s 0.02
    positive State_decay_min 0.7
    positive State_decay_range 0.3
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Quantum
    tail_duration_s = 0.8
    quantum_states = 20
    uncertainty_stddev = 0.25
    collapse_threshold = 0.7
    base_amplitude = 0.18
    time_mean_s = 0.12
    min_delay_s = 0.015
    state_decay_min = 0.75
    state_decay_range = 0.25
    substates = 3
    substate_jitter_s = 0.01
    fadeout_duration_s = 0.8
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Quantum
    tail_duration_s = 1.0
    quantum_states = 35
    uncertainty_stddev = 0.35
    collapse_threshold = 0.65
    base_amplitude = 0.25
    time_mean_s = 0.18
    min_delay_s = 0.02
    state_decay_min = 0.7
    state_decay_range = 0.3
    substates = 4
    substate_jitter_s = 0.015
    fadeout_duration_s = 1.0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Quantum
    tail_duration_s = 1.3
    quantum_states = 45
    uncertainty_stddev = 0.42
    collapse_threshold = 0.62
    base_amplitude = 0.28
    time_mean_s = 0.22
    min_delay_s = 0.022
    state_decay_min = 0.72
    state_decay_range = 0.28
    substates = 5
    substate_jitter_s = 0.018
    fadeout_duration_s = 1.3
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Quantum
    tail_duration_s = 1.8
    quantum_states = 60
    uncertainty_stddev = 0.5
    collapse_threshold = 0.6
    base_amplitude = 0.3
    time_mean_s = 0.28
    min_delay_s = 0.025
    state_decay_min = 0.74
    state_decay_range = 0.26
    substates = 6
    substate_jitter_s = 0.022
    fadeout_duration_s = 1.6
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Pre-generate state data for visualization
collapsedCount = 0
superposedCount = 0

for state from 1 to quantum_states
    time_uncertainty = randomGauss(time_mean_s, uncertainty_stddev)
    stateTime[state] = abs(time_uncertainty) + min_delay_s
    stateAmpPrecision[state] = 1 / (1 + abs(time_uncertainty))
    stateDecay[state] = state_decay_min + state_decay_range * (quantum_states - state) / quantum_states
    
    probability = randomUniform(0, 1)
    if probability > collapse_threshold
        stateCollapsed[state] = 1
        collapsedCount = collapsedCount + 1
    else
        stateCollapsed[state] = 0
        superposedCount = superposedCount + 1
    endif
endfor

# === Info ===
writeInfoLine: "=== Quantum Uncertainty Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Quantum states: ", quantum_states
appendInfoLine: "Uncertainty σ: ", uncertainty_stddev
appendInfoLine: "Collapse threshold: ", collapse_threshold
appendInfoLine: "Collapsed states: ", collapsedCount, " (", fixed$(collapsedCount / quantum_states * 100, 1), "%)"
appendInfoLine: "Superposed states: ", superposedCount, " (", fixed$(superposedCount / quantum_states * 100, 1), "%)"
appendInfoLine: "Substates per superposition: ", substates
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tail_duration_s

# Create silent tail
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left
    selectObject: leftChannel
    Copy: "reverb_left"
    reverbLeft = selected("Sound")
    
    for state from 1 to quantum_states
        time_uncertainty = randomGauss(time_mean_s, uncertainty_stddev)
        amplitude_precision = 1 / (1 + abs(time_uncertainty))
        state_decay = state_decay_min + state_decay_range * (quantum_states - state) / quantum_states
        probability = randomUniform(0, 1)
        
        if probability > collapse_threshold
            # COLLAPSED STATE: single echo
            delay = abs(time_uncertainty) + min_delay_s
            amp = base_amplitude * amplitude_precision * state_decay * 0.8
            
            delay_str$ = string$(delay)
            amp_str$ = string$(amp)
            
            selectObject: reverbLeft
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        else
            # SUPERPOSITION: multiple substates
            for sub from 1 to substates
                sub_delay = abs(time_uncertainty) + randomGauss(0, substate_jitter_s) + min_delay_s
                sub_amp = base_amplitude * amplitude_precision * state_decay * 0.5 / sub
                
                delay_str$ = string$(sub_delay)
                amp_str$ = string$(sub_amp)
                
                selectObject: reverbLeft
                Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
            endfor
        endif
    endfor
    
    # Process right (different random seeds for decorrelation)
    selectObject: rightChannel
    Copy: "reverb_right"
    reverbRight = selected("Sound")
    
    for state from 1 to quantum_states
        time_uncertainty = randomGauss(time_mean_s * 0.89, uncertainty_stddev * 1.09)
        amplitude_precision = 1 / (1 + abs(time_uncertainty))
        state_decay = (state_decay_min - 0.05) + (state_decay_range + 0.05) * (quantum_states - state) / quantum_states
        probability = randomUniform(0, 1)
        
        if probability > (collapse_threshold - 0.03)
            delay = abs(time_uncertainty) + min_delay_s * 1.25
            amp = (base_amplitude - 0.02) * amplitude_precision * state_decay * 0.75
            
            delay_str$ = string$(delay)
            amp_str$ = string$(amp)
            
            selectObject: reverbRight
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        else
            for sub from 1 to substates
                sub_delay = abs(time_uncertainty) + randomGauss(0, substate_jitter_s * 1.2) + min_delay_s * 1.25
                sub_amp = (base_amplitude - 0.02) * amplitude_precision * state_decay * 0.45 / sub
                
                delay_str$ = string$(sub_delay)
                amp_str$ = string$(sub_amp)
                
                selectObject: reverbRight
                Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
            endfor
        endif
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: reverbLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: reverbRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: reverbLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.95
    
    selectObject: reverbRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.95
    
    # Combine
    selectObject: reverbLeft, reverbRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_quantum_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, reverbLeft, reverbRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "reverb_mono"
    reverbMono = selected("Sound")
    
    for state from 1 to quantum_states
        time_uncertainty = randomGauss(time_mean_s, uncertainty_stddev)
        amplitude_precision = 1 / (1 + abs(time_uncertainty))
        state_decay = state_decay_min + state_decay_range * (quantum_states - state) / quantum_states
        probability = randomUniform(0, 1)
        
        if probability > collapse_threshold
            delay = abs(time_uncertainty) + min_delay_s
            amp = base_amplitude * amplitude_precision * state_decay * 0.8
            
            delay_str$ = string$(delay)
            amp_str$ = string$(amp)
            
            selectObject: reverbMono
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        else
            for sub from 1 to substates
                sub_delay = abs(time_uncertainty) + randomGauss(0, substate_jitter_s) + min_delay_s
                sub_amp = base_amplitude * amplitude_precision * state_decay * 0.5 / sub
                
                delay_str$ = string$(sub_delay)
                amp_str$ = string$(sub_amp)
                
                selectObject: reverbMono
                Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
            endfor
        endif
    endfor
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: reverbMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: reverbMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Scale peak: 0.95
    Rename: originalName$ + "_quantum_" + presetName$
    result = reverbMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Quantum Uncertainty Reverb: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Quantum " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # State collapse diagram
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    maxTime = time_mean_s + 3 * uncertainty_stddev + min_delay_s
    Axes: 0, maxTime * 1000, 0, quantum_states + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxTime * 1000, 0, quantum_states + 1
    
    # Draw each quantum state
    for state from 1 to quantum_states
        y = quantum_states - state + 1
        delay = stateTime[state] * 1000
        precision = stateAmpPrecision[state]
        
        if stateCollapsed[state] = 1
            # Collapsed: single point
            Colour: "{0.3, 0.5, 0.8}"
            Paint circle: "{0.3, 0.5, 0.8}", delay, y, maxTime * 8 * precision
        else
            # Superposition: spread of points
            Colour: "{0.8, 0.5, 0.3}"
            for sub from 1 to substates
                subOffset = randomGauss(0, substate_jitter_s) * 1000
                subSize = maxTime * 5 * precision / sub
                Paint circle: "{0.8, 0.5, 0.3}", delay + subOffset, y, subSize
            endfor
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "State #"
    Text bottom: "yes", "Delay (ms)"
    
    # Legend
    Font size: 5
    Colour: "{0.3, 0.5, 0.8}"
    Text: maxTime * 850, "centre", quantum_states * 0.95, "half", "● Collapsed (" + string$(collapsedCount) + ")"
    Colour: "{0.8, 0.5, 0.3}"
    Text: maxTime * 850, "centre", quantum_states * 0.85, "half", "● Superposed (" + string$(superposedCount) + ")"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "States: " + string$(quantum_states) + " | Uncertainty: σ=" + fixed$(uncertainty_stddev, 2) + " | Threshold: " + fixed$(collapse_threshold, 2) + " | Substates: " + string$(substates)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result