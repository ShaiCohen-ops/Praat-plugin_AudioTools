# ============================================================
# Praat AudioTools - Quantum_State_Superposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Quantum State Superposition - creates complex interference
#   patterns through phase-rotated bidirectional delays. Combines
#   forward and backward sample offsets with cos/sin rotation,
#   producing unique swirling, evolving textures.
#
# Changelog v0.3:
#   - Bidirectional delay is now true FIR: a pre-pass snapshot is
#     read for both taps, so the backward tap no longer feeds back
#     on already-modified samples (was a recursive/IIR path)
#   - Clamped superposition strength to [0,1] (custom values >1 made
#     sqrt(1-strength) undefined -> corrupted output)
#   - Visualization: set Axes before Text on title and legend (the
#     legend was inheriting the spectrogram's data axes), and made
#     the spectrogram panels mono-safe (convert before To Spectrogram)
#   - Removed unused sampleRate variable
#
# Changelog v0.2:
#   - Modern syntax
#   - Added bounds checking
#   - Added visualization
#   - Fixed unused variable
# ============================================================

form Quantum State Superposition
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (balanced)
        option Gentle Quantum Drift
        option Intense Superposition
        option Phase Entanglement
        option Custom
    
    comment === States ===
    natural States 5
    
    comment === Superposition Strength ===
    positive Superposition_min 0.3
    positive Superposition_max 0.8
    boolean Use_fixed_superposition 0
    positive Fixed_superposition 0.55
    
    comment === Phase Shift ===
    positive Phase_shift_min 0.1
    positive Phase_shift_max 6.283
    boolean Use_fixed_phase 0
    positive Fixed_phase_shift 3.14159
    
    comment === State Offset ===
    positive State_offset_base 10
    positive State_offset_increment 2
    
    comment === Decay ===
    positive Superposition_decay 0.75
    
    comment === Output ===
    positive Scale_peak 0.96
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    states = 5
    superposition_min = 0.3
    superposition_max = 0.8
    fixed_superposition = 0.55
    phase_shift_min = 0.1
    phase_shift_max = 6.283
    fixed_phase_shift = 3.14159
    state_offset_base = 10
    state_offset_increment = 2
    superposition_decay = 0.75
elsif preset = 2
    # Gentle Quantum Drift
    states = 4
    superposition_min = 0.2
    superposition_max = 0.5
    fixed_superposition = 0.35
    phase_shift_min = 0.1
    phase_shift_max = 3.14
    fixed_phase_shift = 1.57
    state_offset_base = 12
    state_offset_increment = 3
    superposition_decay = 0.85
elsif preset = 3
    # Intense Superposition
    states = 6
    superposition_min = 0.6
    superposition_max = 0.9
    fixed_superposition = 0.75
    phase_shift_min = 0.2
    phase_shift_max = 6.0
    fixed_phase_shift = 3.14159
    state_offset_base = 8
    state_offset_increment = 2
    superposition_decay = 0.7
elsif preset = 4
    # Phase Entanglement
    states = 7
    superposition_min = 0.4
    superposition_max = 0.9
    fixed_superposition = 0.65
    phase_shift_min = 0.5
    phase_shift_max = 5.5
    fixed_phase_shift = 2.618
    state_offset_base = 9
    state_offset_increment = 1.5
    superposition_decay = 0.8
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
totalSamples = Get number of samples

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Gentle Drift"
elsif preset = 3
    presetName$ = "Intense"
elsif preset = 4
    presetName$ = "Entanglement"
else
    presetName$ = "Custom"
endif

# === Determine Initial Superposition Strength ===
if use_fixed_superposition
    superpositionStrength = fixed_superposition
else
    superpositionStrength = randomUniform(superposition_min, superposition_max)
endif

# Clamp to [0,1] so sqrt(1-strength) stays defined
if superpositionStrength < 0
    superpositionStrength = 0
endif
if superpositionStrength > 1
    superpositionStrength = 1
endif

# === Info ===
writeInfoLine: "=== Quantum State Superposition ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "States: ", states
appendInfoLine: "Initial strength: ", fixed$(superpositionStrength, 3)
appendInfoLine: "Decay: ", superposition_decay
appendInfoLine: ""

# === Copy for Processing ===
selectObject: original
Copy: original_name$ + "_quantum"
result = selected("Sound")

# === Main Quantum-Inspired Processing Loop ===
appendInfoLine: "Processing states..."

for state from 1 to states
    selectObject: result
    
    # Probability amplitude (for weighting)
    probAmplitude = sin(state * pi / (states + 1))
    
    # Determine phase shift for this state
    if use_fixed_phase
        phaseShift = fixed_phase_shift
    else
        phaseShift = randomUniform(phase_shift_min, phase_shift_max)
    endif
    
    stateOffset = round(totalSamples / (state_offset_base + state * state_offset_increment))
    
    # Mixing coefficients (sqrt-law gain; exact energy conservation only when probAmplitude = 1)
    dryCoef = sqrt(1 - superpositionStrength)
    wetCoef = sqrt(superpositionStrength) * probAmplitude
    cosPhase = cos(phaseShift)
    sinPhase = sin(phaseShift)
    
    appendInfoLine: "  State ", state, ": offset=", stateOffset, " phase=", fixed$(phaseShift, 2), " strength=", fixed$(superpositionStrength, 3)
    
    # State superposition with bounds checking (true FIR via pre-pass snapshot)
    selectObject: result
    snapshot = Copy: "quantum_snapshot"
    selectObject: result
    Formula: ~ if col + stateOffset <= ncol and col - stateOffset >= 1 
        ... then dryCoef * self + wetCoef * (cosPhase * object[snapshot, row, col + stateOffset] + sinPhase * object[snapshot, row, col - stateOffset])
        ... else self fi
    removeObject: snapshot

    # Collapse probability (decay toward original)
    superpositionStrength = superpositionStrength * superposition_decay
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Quantum Superposition: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Quantum"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    selectObject: original
    nchOrig = Get number of channels
    if nchOrig > 1
        origMono = Convert to mono
    else
        origMono = Copy: "orig_mono_viz"
    endif
    selectObject: origMono
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec, origMono
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Original (s)"
    
    # Result spectrogram
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    nchRes = Get number of channels
    if nchRes > 1
        resMono = Convert to mono
    else
        resMono = Copy: "res_mono_viz"
    endif
    selectObject: resMono
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, resMono
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq"
    Text bottom: "yes", "Quantum (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "States: " + string$(states) + " | Decay: " + fixed$(superposition_decay, 2) + " | Offset base: " + string$(state_offset_base)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result