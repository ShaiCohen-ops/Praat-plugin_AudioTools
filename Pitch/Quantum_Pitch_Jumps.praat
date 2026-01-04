# ============================================================
# Praat AudioTools - Quantum_Pitch_Jumps.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Quantum Pitch Jumps - stochastic pitch transformation using
#   harmonic ratios. Pitch "tunnels" between quantum levels with
#   configurable probability, glitch events, and uncertainty.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Fixed resample result tracking
#   - Added visualization
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
orig_sr = Get sampling frequency
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

# === Form ===
form Quantum Pitch Jumps
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Quantum
        option Moderate Quantum
        option Aggressive Quantum
        option Extreme Quantum
        option Glitchy Micro
        option Harmonic Leaps
        option Chaotic Quantum
    
    comment === Quantum Parameters ===
    natural Quantum_levels 12
    positive Jump_probability 0.4
    positive Glitch_probability 0.15
    
    comment === Energy ===
    positive Energy_min 0.5
    positive Energy_max 2.0
    
    comment === Glitch Range ===
    real Glitch_min_semitones -2
    real Glitch_max_semitones 3
    
    comment === Uncertainty ===
    positive Uncertainty_min 0.98
    positive Uncertainty_max 1.02
    
    comment === Pitch Analysis ===
    positive Time_step 0.005
    positive Minimum_pitch 50
    positive Maximum_pitch 900
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Quantum
    quantum_levels = 8
    jump_probability = 0.2
    glitch_probability = 0.05
    energy_min = 0.8
    energy_max = 1.5
    glitch_min_semitones = -1
    glitch_max_semitones = 1.5
    uncertainty_min = 0.99
    uncertainty_max = 1.01
    presetName$ = "Gentle"
elsif preset = 3
    # Moderate Quantum
    quantum_levels = 12
    jump_probability = 0.3
    glitch_probability = 0.1
    energy_min = 0.7
    energy_max = 1.8
    glitch_min_semitones = -1.5
    glitch_max_semitones = 2
    uncertainty_min = 0.98
    uncertainty_max = 1.02
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive Quantum
    quantum_levels = 16
    jump_probability = 0.5
    glitch_probability = 0.2
    energy_min = 0.5
    energy_max = 2.2
    glitch_min_semitones = -3
    glitch_max_semitones = 4
    uncertainty_min = 0.95
    uncertainty_max = 1.05
    presetName$ = "Aggressive"
elsif preset = 5
    # Extreme Quantum
    quantum_levels = 24
    jump_probability = 0.7
    glitch_probability = 0.3
    energy_min = 0.3
    energy_max = 3.0
    glitch_min_semitones = -5
    glitch_max_semitones = 6
    uncertainty_min = 0.9
    uncertainty_max = 1.1
    presetName$ = "Extreme"
elsif preset = 6
    # Glitchy Micro
    quantum_levels = 5
    jump_probability = 0.6
    glitch_probability = 0.4
    energy_min = 0.9
    energy_max = 1.2
    glitch_min_semitones = -0.5
    glitch_max_semitones = 1
    uncertainty_min = 0.995
    uncertainty_max = 1.005
    presetName$ = "Glitchy"
elsif preset = 7
    # Harmonic Leaps
    quantum_levels = 7
    jump_probability = 0.4
    glitch_probability = 0.05
    energy_min = 0.6
    energy_max = 1.8
    glitch_min_semitones = -1
    glitch_max_semitones = 1
    uncertainty_min = 0.98
    uncertainty_max = 1.02
    presetName$ = "Harmonic"
elsif preset = 8
    # Chaotic Quantum
    quantum_levels = 32
    jump_probability = 0.8
    glitch_probability = 0.5
    energy_min = 0.2
    energy_max = 4.0
    glitch_min_semitones = -8
    glitch_max_semitones = 10
    uncertainty_min = 0.8
    uncertainty_max = 1.2
    presetName$ = "Chaotic"
else
    presetName$ = "Manual"
endif

# === Harmonic Ratios ===
ratios# = {1, 16/15, 9/8, 6/5, 5/4, 4/3, 7/5, 3/2, 8/5, 5/3, 16/9, 15/8, 2}

# === Info ===
writeInfoLine: "=== Quantum Pitch Jumps ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Quantum levels: ", quantum_levels
appendInfoLine: "Jump probability: ", jump_probability
appendInfoLine: "Glitch probability: ", glitch_probability
appendInfoLine: "Energy range: ", energy_min, " - ", energy_max
appendInfoLine: "Uncertainty: ", uncertainty_min, " - ", uncertainty_max
appendInfoLine: ""

# === Calculate Number of Points ===
npoints = round(dur / 0.01)
if npoints < 200
    npoints = 200
endif
if npoints > 2000
    npoints = 2000
endif

# === Create Working Copy and Manipulation ===
selectObject: original
Copy: originalName$ + "_quantum_tmp"
tmpSound = selected("Sound")

selectObject: tmpSound
manipulation = To Manipulation: time_step, minimum_pitch, maximum_pitch

# === Get Median Pitch ===
selectObject: tmpSound
To Pitch: time_step, minimum_pitch, maximum_pitch
tmpPitch = selected("Pitch")
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if median_f0 = undefined
    median_f0 = 200
    appendInfoLine: "No pitch detected, using default: ", median_f0, " Hz"
else
    appendInfoLine: "Median pitch: ", fixed$(median_f0, 1), " Hz"
endif

removeObject: tmpPitch

# === Create Pitch Tier ===
appendInfoLine: ""
appendInfoLine: "Building quantum pitch curve..."

Create PitchTier: "quantum_pitch", xmin, xmax
pitchTier = selected("PitchTier")

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizPitch# = zero#(maxVizPoints)
vizLevels# = zero#(maxVizPoints)
vizJumps# = zero#(maxVizPoints)
vizGlitches# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# Initialize quantum state
current_level = 1
energy_level = 1
jump_count = 0
glitch_count = 0

# === Build Quantum Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    pos = i / (npoints - 1)
    
    # Quantum tunnel events
    jumped = 0
    if randomUniform(0, 1) < (jump_probability / (npoints / 100))
        current_level = randomInteger(1, quantum_levels)
        energy_level = randomUniform(energy_min, energy_max)
        jumped = 1
        jump_count = jump_count + 1
    endif
    
    # Glitch events
    glitch_factor = 0
    glitched = 0
    if randomUniform(0, 1) < (glitch_probability / (npoints / 100))
        glitch_factor = randomUniform(glitch_min_semitones, glitch_max_semitones)
        glitched = 1
        glitch_count = glitch_count + 1
    endif
    
    ratio_index = ((current_level - 1) mod size(ratios#)) + 1
    base_ratio = ratios#[ratio_index]
    
    # Apply energy modulation and glitches
    glitch_multiplier = exp((ln(2) / 12) * glitch_factor)
    final_ratio = base_ratio * energy_level * glitch_multiplier
    
    # Add quantum uncertainty
    uncertainty = randomUniform(uncertainty_min, uncertainty_max)
    final_ratio = final_ratio * uncertainty
    
    # Convert ratio to frequency
    new_f0 = median_f0 * final_ratio
    
    # Clamp to range
    if new_f0 < minimum_pitch
        new_f0 = minimum_pitch
    elsif new_f0 > maximum_pitch
        new_f0 = maximum_pitch
    endif
    
    # Store for visualization
    vizIdx = floor(i / vizStep) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizPitch#[vizIdx] = new_f0
            vizLevels#[vizIdx] = current_level
            vizJumps#[vizIdx] = jumped
            vizGlitches#[vizIdx] = glitched
        endif
    endif
    
    selectObject: pitchTier
    Add point: t, new_f0
endfor

appendInfoLine: "Jumps: ", jump_count, " | Glitches: ", glitch_count

# === Replace Pitch Tier ===
selectObject: manipulation, pitchTier
Replace pitch tier

# === Resynthesize ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."
selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_quantum_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Quantum Pitch Jumps: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Quantum"
    Text bottom: "yes", "Time (s)"
    
    # Quantum pitch curve
    Select outer viewport: 0, 8, 2.5, 3.8
    Select inner viewport: 0.6, 7.6, 2.7, 3.7
    
    # Find range
    minP = vizPitch#[1]
    maxP = vizPitch#[1]
    for vp from 2 to maxVizPoints
        if vizPitch#[vp] > 0
            if vizPitch#[vp] < minP
                minP = vizPitch#[vp]
            endif
            if vizPitch#[vp] > maxP
                maxP = vizPitch#[vp]
            endif
        endif
    endfor
    
    pMargin = (maxP - minP) * 0.1
    if pMargin < 20
        pMargin = 20
    endif
    
    Axes: xmin, xmax, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minP - pMargin, maxP + pMargin
    
    # Draw median line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: xmin, median_f0, xmax, median_f0
    Solid line
    
    # Mark jumps and glitches
    for vp from 1 to maxVizPoints
        if vizJumps#[vp] = 1
            Colour: "{0.8, 0.5, 0.5}"
            Draw line: vizTimes#[vp], minP - pMargin * 0.5, vizTimes#[vp], maxP + pMargin * 0.5
        endif
        if vizGlitches#[vp] = 1
            Colour: "{0.5, 0.8, 0.5}"
            Paint circle (mm): "{0.5, 0.8, 0.5}", vizTimes#[vp], vizPitch#[vp], 1
        endif
    endfor
    
    # Draw pitch curve
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizPitch#[vp] > 0 and vizPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizPitch#[vp - 1], vizTimes#[vp], vizPitch#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.8, 0.5, 0.5}"
    Text: 0.02, "left", 1.08, "half", "│ Jump"
    Colour: "{0.5, 0.8, 0.5}"
    Text: 0.10, "left", 1.08, "half", "● Glitch"
    
    # Quantum level display
    Select outer viewport: 0, 8, 4.0, 4.8
    Select inner viewport: 0.6, 7.6, 4.1, 4.7
    
    Axes: xmin, xmax, 0, quantum_levels + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, 0, quantum_levels + 1
    
    # Draw level changes
    Colour: "{0.6, 0.5, 0.7}"
    for vp from 2 to maxVizPoints
        if vizLevels#[vp] > 0 and vizLevels#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizLevels#[vp - 1], vizTimes#[vp], vizLevels#[vp]
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Level"
    
    # Harmonic ratios display
    Select outer viewport: 0, 8, 5.0, 5.5
    Select inner viewport: 0.6, 7.6, 5.1, 5.4
    
    nRatios = size(ratios#)
    Axes: 0, nRatios + 1, 0, 2.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, nRatios + 1, 0, 2.2
    
    # Draw ratio bars
    for r from 1 to nRatios
        barHeight = ratios#[r]
        Colour: "{0.6, 0.7, 0.8}"
        Paint rectangle: "{0.6, 0.7, 0.8}", r - 0.35, r + 0.35, 0, barHeight
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ratios"
    
    # Stats
    Select outer viewport: 0, 8, 5.6, 5.9
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Levels: " + string$(quantum_levels) + " | Jumps: " + string$(jump_count) + " | Glitches: " + string$(glitch_count) + " | P(jump): " + fixed$(jump_probability, 2) + " | P(glitch): " + fixed$(glitch_probability, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: tmpSound, manipulation, pitchTier

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