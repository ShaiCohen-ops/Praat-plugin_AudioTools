# ============================================================
# Praat AudioTools - Quantum_Uncertainty_Reverb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
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
# Changelog v0.4:
#   - Public form/defaults, output naming and final selection are unchanged.
#   - The stored state arrays are now the ACTUAL left/mono render plan:
#     visualization and collapse statistics describe the rendered realization.
#   - Rendering is deterministic via an internal research seed; Praat's global
#     RNG is restored after left/mono and decorrelated-right plans are built.
#   - Corrected Wet/Dry semantics: 0% = dry only, 100% = quantum effect only.
#   - Exact-channel silent tails support arbitrary multichannel inputs.
#   - Substate delays are clamped to >= 2 samples and Custom decay/collapse/base
#     values are sanitized to stable ranges.
#   - Fadeout is constrained to the appended tail and cannot attenuate source.
#   - Stereo normalization occurs only after L/R combination; peak handling is
#     a ceiling only, so quiet material is not boosted.
#
# Changelog v0.3:
#   - Viz: set world axes explicitly before title & parameters text
#     (parameters line was inheriting the state-diagram axes -> mis-placed)
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

# Internal geometry/stability guards; built-in presets are already valid.
effectiveStates = round(quantum_states)
if effectiveStates < 1
    effectiveStates = 1
endif
effectiveSubstates = round(substates)
if effectiveSubstates < 1
    effectiveSubstates = 1
endif

tailEff = max(2 / sr, tail_duration_s)
uncertaintyEff = max(0, uncertainty_stddev)

collapseEff = collapse_threshold
if collapseEff < 0
    collapseEff = 0
elsif collapseEff > 1
    collapseEff = 1
endif

subJitterEff = max(0, substate_jitter_s)

baseAmpEff = base_amplitude
if baseAmpEff < 0
    baseAmpEff = 0
elsif baseAmpEff > 0.99
    baseAmpEff = 0.99
endif

timeMeanEff = max(0, time_mean_s)
minDelayEff = max(2 / sr, min_delay_s)

decayMinEff = state_decay_min
if decayMinEff < 0
    decayMinEff = 0
elsif decayMinEff > 1
    decayMinEff = 1
endif
decayRangeEff = max(0, state_decay_range)

fadeEff = fadeout_duration_s
if fadeEff < 0
    fadeEff = 0
endif
if fadeEff > tailEff
    fadeEff = tailEff
endif

# Deterministic render plan. The left/mono arrays below also drive the figure.
researchSeed = 20260814
random_initializeWithSeedUnsafelyButPredictably (researchSeed)

collapsedCount = 0
superposedCount = 0

for state from 1 to effectiveStates
    if uncertaintyEff > 0
        time_uncertainty = randomGauss(timeMeanEff, uncertaintyEff)
    else
        time_uncertainty = timeMeanEff
    endif

    stateTime[state] = max(2 / sr, abs(time_uncertainty) + minDelayEff)
    stateAmpPrecision[state] = 1 / (1 + abs(time_uncertainty))
    stateDecay[state] = decayMinEff + decayRangeEff * (effectiveStates - state) / effectiveStates
    if stateDecay[state] < 0
        stateDecay[state] = 0
    elsif stateDecay[state] > 1
        stateDecay[state] = 1
    endif

    probability = randomUniform(0, 1)
    if probability > collapseEff
        stateCollapsed[state] = 1
        collapsedCount = collapsedCount + 1
        stateAmp[state] = baseAmpEff * stateAmpPrecision[state] * stateDecay[state] * 0.8
        if stateAmp[state] > 0.99
            stateAmp[state] = 0.99
        endif
    else
        stateCollapsed[state] = 0
        superposedCount = superposedCount + 1
        for sub from 1 to effectiveSubstates
            idx = (state - 1) * effectiveSubstates + sub
            subJitterNow = 0
            if subJitterEff > 0
                subJitterNow = randomGauss(0, subJitterEff)
            endif
            stateSubDelay[idx] = max(2 / sr, abs(time_uncertainty) + subJitterNow + minDelayEff)
            stateSubAmp[idx] = baseAmpEff * stateAmpPrecision[state] * stateDecay[state] * 0.5 / sub
            if stateSubAmp[idx] > 0.99
                stateSubAmp[idx] = 0.99
            endif
        endfor
    endif
endfor

# Deterministic decorrelated right plan for stereo input.
rightCollapseEff = collapseEff - 0.03
if rightCollapseEff < 0
    rightCollapseEff = 0
elsif rightCollapseEff > 1
    rightCollapseEff = 1
endif

rightBaseEff = max(0, baseAmpEff - 0.02)
rightMinDelayEff = max(2 / sr, minDelayEff * 1.25)
rightTimeMeanEff = timeMeanEff * 0.89
rightUncertaintyEff = uncertaintyEff * 1.09
rightSubJitterEff = subJitterEff * 1.2

for state from 1 to effectiveStates
    if rightUncertaintyEff > 0
        r_uncertainty = randomGauss(rightTimeMeanEff, rightUncertaintyEff)
    else
        r_uncertainty = rightTimeMeanEff
    endif

    rightTime[state] = max(2 / sr, abs(r_uncertainty) + rightMinDelayEff)
    rightPrecision[state] = 1 / (1 + abs(r_uncertainty))
    rightDecay[state] = max(0, decayMinEff - 0.05) + (decayRangeEff + 0.05) * (effectiveStates - state) / effectiveStates
    if rightDecay[state] > 1
        rightDecay[state] = 1
    endif

    probability = randomUniform(0, 1)
    if probability > rightCollapseEff
        rightCollapsed[state] = 1
        rightAmp[state] = rightBaseEff * rightPrecision[state] * rightDecay[state] * 0.75
        if rightAmp[state] > 0.99
            rightAmp[state] = 0.99
        endif
    else
        rightCollapsed[state] = 0
        for sub from 1 to effectiveSubstates
            idx = (state - 1) * effectiveSubstates + sub
            subJitterNow = 0
            if rightSubJitterEff > 0
                subJitterNow = randomGauss(0, rightSubJitterEff)
            endif
            rightSubDelay[idx] = max(2 / sr, abs(r_uncertainty) + subJitterNow + rightMinDelayEff)
            rightSubAmp[idx] = rightBaseEff * rightPrecision[state] * rightDecay[state] * 0.45 / sub
            if rightSubAmp[idx] > 0.99
                rightSubAmp[idx] = 0.99
            endif
        endfor
    endif
endfor

# Do not leak the fixed research seed into caller scripts.
random_initializeSafelyAndUnpredictably ()

# === Info ===
writeInfoLine: "=== Quantum Uncertainty Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Quantum states: ", effectiveStates
appendInfoLine: "Uncertainty σ: ", uncertaintyEff
appendInfoLine: "Collapse threshold: ", collapseEff
appendInfoLine: "Collapsed states (L/mono plan): ", collapsedCount, " (", fixed$(collapsedCount / effectiveStates * 100, 1), "%)"
appendInfoLine: "Superposed states (L/mono plan): ", superposedCount, " (", fixed$(superposedCount / effectiveStates * 100, 1), "%)"
appendInfoLine: "Substates per superposition: ", effectiveSubstates
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "% | Seed: ", researchSeed
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tailEff

# Create silent tail with the exact source channel count.
Create Sound from formula: "silent_tail", numChannels, 0, tailEff, sr, "0"
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
    
    # Process left from the exact state plan used by the visualization.
    selectObject: leftChannel
    Copy: "reverb_left"
    reverbLeft = selected("Sound")

    for state from 1 to effectiveStates
        if stateCollapsed[state] = 1
            delay_str$ = string$(stateTime[state])
            amp_str$ = string$(stateAmp[state])
            selectObject: reverbLeft
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        else
            for sub from 1 to effectiveSubstates
                idx = (state - 1) * effectiveSubstates + sub
                delay_str$ = string$(stateSubDelay[idx])
                amp_str$ = string$(stateSubAmp[idx])
                selectObject: reverbLeft
                Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
            endfor
        endif
    endfor

    # Process right from a deterministic decorrelated state plan.
    selectObject: rightChannel
    Copy: "reverb_right"
    reverbRight = selected("Sound")

    for state from 1 to effectiveStates
        if rightCollapsed[state] = 1
            delay_str$ = string$(rightTime[state])
            amp_str$ = string$(rightAmp[state])
            selectObject: reverbRight
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        else
            for sub from 1 to effectiveSubstates
                idx = (state - 1) * effectiveSubstates + sub
                delay_str$ = string$(rightSubDelay[idx])
                amp_str$ = string$(rightSubAmp[idx])
                selectObject: reverbRight
                Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
            endfor
        endif
    endfor

    # True dry/effect crossfade. reverbLeft/Right = dry + quantum resonance.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    left_str$ = string$(leftChannel)
    right_str$ = string$(rightChannel)

    selectObject: reverbLeft
    Formula: "object[" + left_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + left_str$ + ", row, col]) * " + wet_str$

    selectObject: reverbRight
    Formula: "object[" + right_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + right_str$ + ", row, col]) * " + wet_str$

    # Fade is constrained to the appended tail only.
    if fadeEff > 0
        fade_start = totalDur - fadeEff
        fade_str$ = string$(fadeEff)
        start_str$ = string$(fade_start)

        selectObject: reverbLeft
        Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"

        selectObject: reverbRight
        Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    endif

    # Combine first; then one stereo ceiling preserves L/R balance.
    selectObject: reverbLeft, reverbRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_quantum_" + presetName$

    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0.95
        Scale peak: 0.95
    endif

    removeObject: leftChannel, rightChannel, reverbLeft, reverbRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono/multichannel..."
    
    selectObject: extendedSound
    Copy: "reverb_mono"
    reverbMono = selected("Sound")
    
    for state from 1 to effectiveStates
        if stateCollapsed[state] = 1
            delay_str$ = string$(stateTime[state])
            amp_str$ = string$(stateAmp[state])
            selectObject: reverbMono
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
        else
            for sub from 1 to effectiveSubstates
                idx = (state - 1) * effectiveSubstates + sub
                delay_str$ = string$(stateSubDelay[idx])
                amp_str$ = string$(stateSubAmp[idx])
                selectObject: reverbMono
                Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ")"
            endfor
        endif
    endfor

    # True dry/effect crossfade; row/col preserves arbitrary channel count.
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    ext_str$ = string$(extendedSound)

    selectObject: reverbMono
    Formula: "object[" + ext_str$ + ", row, col] * " + dry_str$ + " + (self - object[" + ext_str$ + ", row, col]) * " + wet_str$

    # Fade is constrained to the appended tail only.
    if fadeEff > 0
        fade_start = totalDur - fadeEff
        fade_str$ = string$(fadeEff)
        start_str$ = string$(fade_start)

        selectObject: reverbMono
        Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    endif

    selectObject: reverbMono
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0.95
        Scale peak: 0.95
    endif
    Rename: originalName$ + "_quantum_" + presetName$
    result = reverbMono

    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Quantum Uncertainty Reverb: " + originalName$ + " (" + presetName$ + ")" + " | v0.5.1"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.7, 1.3
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Dry"
    Select inner viewport: 0.60, 7.70, 0.7, 1.3
    Axes: 0, 1, 0, 1
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Quantum " + fixed$(wet_dry_percent, 0) + "\%  "
    Select inner viewport: 0.60, 7.70, 1.6, 2.2
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    
    # State collapse diagram
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.60, 7.70, 2.6, 3.9
    
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
            # Superposition: exact stored substate delays from this render.
            Colour: "{0.8, 0.5, 0.3}"
            for sub from 1 to effectiveSubstates
                idx = (state - 1) * effectiveSubstates + sub
                subDelayMs = stateSubDelay[idx] * 1000
                subSize = maxTime * 5 * precision / sub
                Paint circle: "{0.8, 0.5, 0.3}", subDelayMs, y, subSize
            endfor
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 2.6, 3.9
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "State #"
    Select inner viewport: 0.60, 7.70, 2.6, 3.9
    Axes: 0, maxTime * 1000, 0, quantum_states + 1
    Text bottom: "yes", "Delay (ms)"
    
    # Legend
    Font size: 6
    Colour: "{0.3, 0.5, 0.8}"
    Text: maxTime * 850, "centre", effectiveStates * 0.95, "half", "● Collapsed (" + string$(collapsedCount) + ")"
    Colour: "{0.8, 0.5, 0.3}"
    Text: maxTime * 850, "centre", effectiveStates * 0.85, "half", "● Superposed (" + string$(superposedCount) + ")"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "States: " + string$(effectiveStates) + " | Uncertainty: σ=" + fixed$(uncertaintyEff, 2) + " | Threshold: " + fixed$(collapseEff, 2) + " | Substates: " + string$(effectiveSubstates) + " | Seed: " + string$(researchSeed)
    
    Font size: 10
    Colour: "Black"

    # Summary strip - compact house spacing.
    Select outer viewport: 0, 8, 4.60, 5.60
    Select inner viewport: 0.60, 7.70, 4.67, 5.53
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", "State map shows realized delay states and collapse/superposition structure"
    Colour: "{0.25, 0.25, 0.35}"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", "Randomness is visualized from the actual run rather than as a decorative motif"

    # Restore full-page viewport before leaving visualization.
    Select inner viewport: 0.60, 7.70, 4.67, 5.53
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, 5.70
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
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
