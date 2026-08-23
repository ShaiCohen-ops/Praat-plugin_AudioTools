# ============================================================
# Praat AudioTools - Quantum_State_Superposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Quantum State Superposition - creates complex interference
#   patterns through phase-rotated bidirectional delays. Combines
#   forward and backward sample offsets with cos/sin rotation,
#   producing unique swirling, evolving textures.
#
# Changelog v0.4.1:
#   - Visualization only. DSP and public form parameters are unchanged.
#   - Replaced generic before/after spectrograms with a Quantum state
#     interference map that exposes the actual three-tap FIR at every state.
#   - Marker size is physical (mm) and encodes coefficient magnitude; colour
#     identifies tap role only; +/- text shows coefficient polarity.
#   - Added shared Source/Output waveform scaling, house-style Summary panel,
#     and underscore-safe display names.
#
# Changelog v0.4:
#   - API COMPATIBILITY: public form parameters are byte-for-byte unchanged.
#   - CRITICAL FIX: clamp superposition strength at EVERY state. v0.3 only
#     clamped the initial value, so Custom decay > 1 could make a later
#     sqrt(1-strength) invalid despite the v0.3 safety fix.
#   - Added Custom-range validation for randomized superposition and phase.
#   - State offsets are clamped to at least one sample and at most n-1,
#     preventing accidental zero-delay states or impossible offsets.
#   - Silent outputs are safe: Scale peak is skipped when the absolute
#     extremum is zero, while non-silent output keeps the historical target.
#   - Visualization spectrograms are capped at Nyquist.
#   - Clarified internally that the cos/sin operation is a coefficient-space
#     rotation of two delayed real taps (quantum-inspired), not a Hilbert
#     analytic-signal phase rotation.
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
sampleRate = Get sampling frequency
nyquist = sampleRate / 2
vizMaxHz = min(5000, nyquist)

# === Guards (v0.4; public parameters unchanged) ===
if superposition_min > superposition_max
    exitScript: "Superposition_min must be <= Superposition_max"
endif
if phase_shift_min > phase_shift_max
    exitScript: "Phase_shift_min must be <= Phase_shift_max"
endif
if state_offset_base <= 0 or state_offset_increment <= 0
    exitScript: "State offset base/increment must be > 0"
endif
if superposition_decay <= 0
    exitScript: "Superposition decay must be > 0"
endif

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
initialSuperpositionStrength = superpositionStrength

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

# Per-state values retained only for visualization/reporting.
stateStrength# = zero#(states)
statePhase# = zero#(states)
stateOffsetSamples# = zero#(states)
stateDryCoef# = zero#(states)
stateForwardCoef# = zero#(states)
stateBackwardCoef# = zero#(states)

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
    # Keep each state a genuine delayed state. Very small custom files/large
    # divisors can otherwise round to zero; very small divisors can exceed n.
    if stateOffset < 1
        stateOffset = 1
    endif
    if totalSamples > 1 and stateOffset > totalSamples - 1
        stateOffset = totalSamples - 1
    endif
    
    # v0.3 clamped only before state 1. Clamp again here because a Custom
    # decay > 1 can grow the strength between states.
    if superpositionStrength < 0
        superpositionStrength = 0
    endif
    if superpositionStrength > 1
        superpositionStrength = 1
    endif
    
    # Sqrt-law dry/wet coefficients. cos/sin rotate the two delayed real-tap
    # coefficients; this is a quantum-inspired state-space metaphor rather
    # than a Hilbert-transform phase rotation of the audio waveform.
    dryCoef = sqrt(1 - superpositionStrength)
    wetCoef = sqrt(superpositionStrength) * probAmplitude
    cosPhase = cos(phaseShift)
    sinPhase = sin(phaseShift)

    # Visualization data only: capture the exact coefficients used by this state.
    stateStrength#[state] = superpositionStrength
    statePhase#[state] = phaseShift
    stateOffsetSamples#[state] = stateOffset
    stateDryCoef#[state] = dryCoef
    stateForwardCoef#[state] = wetCoef * cosPhase
    stateBackwardCoef#[state] = wetCoef * sinPhase
    
    appendInfoLine: "  State ", state, ": offset=", stateOffset, " phase=", fixed$(phaseShift, 2), " strength=", fixed$(superpositionStrength, 3)
    
    # State superposition with bounds checking (true FIR via pre-pass snapshot)
    selectObject: result
    snapshot = Copy: "quantum_snapshot"
    selectObject: result
    Formula: ~ if col + stateOffset <= ncol and col - stateOffset >= 1 
        ... then dryCoef * self + wetCoef * (cosPhase * object[snapshot, row, col + stateOffset] + sinPhase * object[snapshot, row, col - stateOffset])
        ... else self fi
    removeObject: snapshot

    # Collapse probability. Presets use decay < 1; Custom values > 1 are
    # allowed by the historical positive field, but are safely saturated.
    superpositionStrength = superpositionStrength * superposition_decay
    if superpositionStrength > 1
        superpositionStrength = 1
    endif
endfor

# === Scale Peak ===
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > 0
    Scale peak: scale_peak
endif

# === Visualization ===
if draw_visualization
    Erase all

    # ----------------------------------------------------------
    # HOUSE-STYLE GEOMETRY / SHARED SCALES
    # Source -> Quantum state interference map -> Output -> Summary
    # ----------------------------------------------------------
    displayName$ = replace$(original_name$, "_", " ", 0)

    selectObject: original
    inputPeak = Get absolute extremum: 0, 0, "None"
    selectObject: result
    outputPeak = Get absolute extremum: 0, 0, "None"
    sharedAmp = max(inputPeak, outputPeak)
    if sharedAmp <= 0
        sharedAmp = 1
    else
        sharedAmp = 1.08 * sharedAmp
    endif

    maxDelayMs = 0
    minDelayMs = 1e30
    maxCoefficient = 0
    for state from 1 to states
        delayMs = 1000 * stateOffsetSamples#[state] / sampleRate
        if delayMs > maxDelayMs
            maxDelayMs = delayMs
        endif
        if delayMs < minDelayMs
            minDelayMs = delayMs
        endif
        maxCoefficient = max(maxCoefficient, abs(stateDryCoef#[state]))
        maxCoefficient = max(maxCoefficient, abs(stateForwardCoef#[state]))
        maxCoefficient = max(maxCoefficient, abs(stateBackwardCoef#[state]))
    endfor
    if maxDelayMs <= 0
        maxDelayMs = 1
    endif
    if minDelayMs = 1e30
        minDelayMs = 0
    endif
    if maxCoefficient <= 0
        maxCoefficient = 1
    endif

    # Physical marker radii. Keep a real lower bound so weak taps remain legible.
    if states <= 7
        markerBaseMm = 0.95
        markerSpanMm = 2.00
    elsif states <= 12
        markerBaseMm = 0.85
        markerSpanMm = 1.65
    else
        markerBaseMm = 0.75
        markerSpanMm = 1.35
    endif

    mapX = 1.30 * maxDelayMs
    mapYmin = 0.35
    mapYmax = states + 1.45

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Quantum State Superposition##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Quantum State Superposition.praat  |  " + displayName$ + "  |  " + presetName$

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    selectObject: original
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", "three-tap state cascade  |  " + string$(states) + " states"

    # ----------------------------------------------------------
    # QUANTUM STATE INTERFERENCE MAP
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.22, 4.40
    Axes: -mapX, mapX, mapYmin, mapYmax
    Paint rectangle: "{0.97, 0.97, 0.97}", -mapX, mapX, mapYmin, mapYmax

    # Neutral zero-delay reference.
    Colour: "{0.70, 0.70, 0.73}"
    Dotted line
    Draw line: 0, mapYmin, 0, mapYmax
    Solid line

    # One row per actual processing state, state 1 at the top.
    for state from 1 to states
        y = states - state + 1
        delayMs = 1000 * stateOffsetSamples#[state] / sampleRate
        backCoef = stateBackwardCoef#[state]
        dryC = stateDryCoef#[state]
        fwdCoef = stateForwardCoef#[state]

        Colour: "{0.86, 0.86, 0.88}"
        Draw line: -maxDelayMs, y, maxDelayMs, y

        # A thin neutral kernel span makes the three-tap geometry explicit.
        Colour: "{0.68, 0.68, 0.72}"
        Line width: 1.2
        Draw line: -delayMs, y, delayMs, y
        Line width: 1

        backRadius = markerBaseMm + markerSpanMm * sqrt(abs(backCoef) / maxCoefficient)
        dryRadius = markerBaseMm + markerSpanMm * sqrt(abs(dryC) / maxCoefficient)
        fwdRadius = markerBaseMm + markerSpanMm * sqrt(abs(fwdCoef) / maxCoefficient)

        # Colour has one meaning only: tap role.
        Paint circle (mm): "{0.56, 0.34, 0.74}", -delayMs, y, backRadius
        Paint circle (mm): "{0.50, 0.50, 0.54}", 0, y, dryRadius
        Paint circle (mm): "{0.88, 0.48, 0.20}", delayMs, y, fwdRadius

        # Polarity is carried by a glyph, not by another colour mapping.
        Font size: 5
        Colour: "White"
        if backCoef < 0
            Text: -delayMs, "centre", y, "half", "-"
        else
            Text: -delayMs, "centre", y, "half", "+"
        endif
        Text: 0, "centre", y, "half", "+"
        if fwdCoef < 0
            Text: delayMs, "centre", y, "half", "-"
        else
            Text: delayMs, "centre", y, "half", "+"
        endif

        # Aligned row labels and exact state parameters.
        Font size: 5.5
        Colour: "{0.30, 0.30, 0.32}"
        Text: -1.22 * maxDelayMs, "left", y, "half", "S" + string$(state)
        Text: 1.22 * maxDelayMs, "right", y, "half", "q=" + fixed$(stateStrength#[state], 2) + "  phi=" + fixed$(statePhase#[state], 2)
    endfor

    # Legend / law lives in dedicated headroom above state 1.
    legendY = states + 1.03
    Font size: 5.5
    Paint circle (mm): "{0.56, 0.34, 0.74}", -0.82 * maxDelayMs, legendY, 0.85
    Colour: "{0.30, 0.30, 0.32}"
    Text: -0.76 * maxDelayMs, "left", legendY, "half", "x[n-D]"
    Paint circle (mm): "{0.50, 0.50, 0.54}", -0.22 * maxDelayMs, legendY, 0.85
    Colour: "{0.30, 0.30, 0.32}"
    Text: -0.16 * maxDelayMs, "left", legendY, "half", "x[n]"
    Paint circle (mm): "{0.88, 0.48, 0.20}", 0.30 * maxDelayMs, legendY, 0.85
    Colour: "{0.30, 0.30, 0.32}"
    Text: 0.36 * maxDelayMs, "left", legendY, "half", "x[n+D]"
    Text: 1.18 * maxDelayMs, "right", legendY, "half", "bubble = |coef|  |  +/- = polarity"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Quantum state interference map##"
    Font size: 6
    Text left: "yes", "Processing state"
    Text bottom: "yes", "Relative tap offset (ms)"

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, duration, 0
    selectObject: result
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", "phase-rotated bidirectional FIR cascade  |  peak target " + fixed$(scale_peak, 2)

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    if use_fixed_phase
        phaseMode$ = "fixed phase " + fixed$(fixed_phase_shift, 2) + " rad"
    else
        phaseMode$ = "random phase " + fixed$(phase_shift_min, 2) + "-" + fixed$(phase_shift_max, 2) + " rad"
    endif
    if use_fixed_superposition
        strengthMode$ = "fixed q " + fixed$(fixed_superposition, 2)
    else
        strengthMode$ = "random q " + fixed$(superposition_min, 2) + "-" + fixed$(superposition_max, 2)
    endif

    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetName$ + "  |  " + string$(states) + " states  |  " + strengthMode$ + "  |  decay " + fixed$(superposition_decay, 2) + "  |  " + phaseMode$
    Text: 0.02, "left", 0.18, "half", "offset " + fixed$(minDelayMs, 1) + "-" + fixed$(maxDelayMs, 1) + " ms  |  initial q " + fixed$(initialSuperpositionStrength, 3) + "  |  output " + fixed$(duration, 2) + " s  |  peak " + fixed$(outputPeak, 3)

    Font size: 10
    Colour: "Black"
    Line width: 1
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