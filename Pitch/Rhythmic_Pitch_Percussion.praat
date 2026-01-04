# ============================================================
# Praat AudioTools - Rhythmic_Pitch_Percussion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic Pitch Percussion - applies percussive pitch hits
#   based on a rhythm pattern. Creates kick-drum-like pitch
#   envelopes with polyrhythmic ghost hits and tension waves.
#
# Changelog v0.2:
#   - Modern syntax
#   - Fixed input check
#   - Fixed array handling (numeric instead of string)
#   - Fixed pitch calculation (was adding ratios, now adds Hz)
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
form Rhythmic Pitch Percussion
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Techno Kick
        option Trap Hi-Hat
        option Dubstep Wobble
        option Breakbeat
        option Minimal Pulse
    
    comment === Rhythm Pattern ===
    sentence Rhythm_pattern 1_0_1_1_0_1_0_1_1_0_0_1
    comment (1=hit, 0=rest, underscore-separated)
    
    comment === Hit Parameters ===
    positive Hit_strength 25
    positive Decay_rate 6
    positive Polyrhythm_factor 3
    positive Ghost_hits 0.3
    
    comment === Analysis ===
    positive Time_step 0.005
    positive Floor_pitch 50
    positive Ceiling_pitch 900
    natural Npoints 600
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Techno Kick
    rhythm_pattern$ = "1_0_0_0_1_0_0_0_1_0_0_0_1_0_0_0"
    hit_strength = 150
    decay_rate = 15
    polyrhythm_factor = 1
    ghost_hits = 0
    presetName$ = "Techno"
elsif preset = 3
    # Trap Hi-Hat
    rhythm_pattern$ = "1_1_1_1_0_1_1_1_1_1_0_1_1_1_1_0"
    hit_strength = 8
    decay_rate = 40
    polyrhythm_factor = 8
    ghost_hits = 2.0
    presetName$ = "Trap"
elsif preset = 4
    # Dubstep Wobble
    rhythm_pattern$ = "1_0_1_0_1_0_1_0_1_0_1_0_1_0_1_0"
    hit_strength = 120
    decay_rate = 2
    polyrhythm_factor = 11
    ghost_hits = 0.8
    presetName$ = "Dubstep"
elsif preset = 5
    # Breakbeat
    rhythm_pattern$ = "1_0_0_1_0_1_0_0_1_0_1_0_1_0_0_1"
    hit_strength = 100
    decay_rate = 20
    polyrhythm_factor = 7
    ghost_hits = 1.2
    presetName$ = "Breakbeat"
elsif preset = 6
    # Minimal Pulse
    rhythm_pattern$ = "1_0_0_0_0_0_0_0_0_0_0_0_0_0_0_0"
    hit_strength = 180
    decay_rate = 0.5
    polyrhythm_factor = 1
    ghost_hits = 0
    presetName$ = "Minimal"
else
    presetName$ = "Custom"
endif

# === Parse Rhythm Pattern ===
# First pass: count beats
tempRhythm$ = rhythm_pattern$ + "_"
tempRhythm$ = replace$(tempRhythm$, "_", " ", 0)
n_beats = 0

repeat
    space_pos = index(tempRhythm$, " ")
    if space_pos > 1
        n_beats = n_beats + 1
        tempRhythm$ = right$(tempRhythm$, length(tempRhythm$) - space_pos)
    endif
until space_pos <= 1

# Create numeric array
beatValues# = zero#(n_beats)

# Second pass: store values
rhythm$ = rhythm_pattern$ + "_"
rhythm$ = replace$(rhythm$, "_", " ", 0)
bIdx = 0

repeat
    space_pos = index(rhythm$, " ")
    if space_pos > 1
        bIdx = bIdx + 1
        thisVal$ = left$(rhythm$, space_pos - 1)
        beatValues#[bIdx] = number(thisVal$)
        rhythm$ = right$(rhythm$, length(rhythm$) - space_pos)
    endif
until space_pos <= 1

# === Info ===
writeInfoLine: "=== Rhythmic Pitch Percussion ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Pattern (", n_beats, " beats): ", rhythm_pattern$
appendInfoLine: "Hit strength: ", hit_strength
appendInfoLine: "Decay rate: ", decay_rate
appendInfoLine: "Polyrhythm: ", polyrhythm_factor
appendInfoLine: "Ghost hits: ", ghost_hits
appendInfoLine: ""

# === Create Working Copy and Manipulation ===
selectObject: original
Copy: originalName$ + "_rhythm_tmp"
tmpSound = selected("Sound")

# === Get Median Pitch ===
selectObject: tmpSound
To Pitch: time_step, floor_pitch, ceiling_pitch
tmpPitchObj = selected("Pitch")
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if median_f0 = undefined
    median_f0 = 200
    appendInfoLine: "No pitch detected, using default: ", median_f0, " Hz"
else
    appendInfoLine: "Median pitch: ", fixed$(median_f0, 1), " Hz"
endif

removeObject: tmpPitchObj

# === Create Manipulation ===
selectObject: tmpSound
manipulation = To Manipulation: time_step, floor_pitch, ceiling_pitch

selectObject: manipulation
pitchTier = Extract pitch tier
Rename: "rhythm_pitch"

selectObject: pitchTier
Remove points between: 0, dur + 1

beat_duration = dur / n_beats

# Store for visualization
maxVizPoints = min(npoints, 500)
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

appendInfoLine: ""
appendInfoLine: "Building percussive pitch curve..."

# === Build Rhythmic Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur
    
    beat_pos = (t - xmin) / beat_duration
    current_beat = floor(beat_pos) + 1
    beat_phase = beat_pos - floor(beat_pos)
    
    if current_beat >= 1 and current_beat <= n_beats
        beat_value = beatValues#[current_beat]
    else
        beat_value = 0
    endif
    
    pitch_shift = 0
    
    # Main hit envelope
    if beat_value > 0
        attack = exp(-decay_rate * 3 * beat_phase)
        body = 0.6 * exp(-decay_rate * 0.8 * beat_phase)
        tail = 0.2 * exp(-decay_rate * 0.3 * beat_phase)
        envelope = attack + body + tail
        
        fundamental_hit = hit_strength * envelope
        harmonic_hit = 0.4 * hit_strength * envelope * sin(beat_phase * 8 * pi)
        
        pitch_shift = pitch_shift + fundamental_hit + harmonic_hit
    endif
    
    # Polyrhythmic ghost hits
    poly_beat_pos = beat_pos * polyrhythm_factor
    poly_phase = poly_beat_pos - floor(poly_beat_pos)
    if poly_phase < 0.1
        ghost_envelope = exp(-20 * poly_phase)
        ghost_hit = ghost_hits * hit_strength * ghost_envelope
        pitch_shift = pitch_shift + ghost_hit
    endif
    
    # Tension wave
    tension_base = sin(beat_pos * 2 * pi)
    tension_modulation = 1 + 0.3 * sin(beat_pos * 7 * pi)
    tension_wave = 0.8 * tension_base * tension_modulation
    pitch_shift = pitch_shift + tension_wave
    
    # Humanize
    human_factor = randomUniform(0.95, 1.05)
    pitch_shift = pitch_shift * human_factor
    
    # Store for visualization
    vizIdx = floor(i / vizStep) + 1
    if vizIdx >= 1 and vizIdx <= maxVizPoints
        if vizTimes#[vizIdx] = 0
            vizTimes#[vizIdx] = t
            vizShifts#[vizIdx] = pitch_shift
        endif
    endif
    
    # Convert pitch shift (semitones) to actual frequency
    new_f0 = median_f0 * exp((ln(2) / 12) * pitch_shift)
    
    # Clamp to range
    if new_f0 < floor_pitch
        new_f0 = floor_pitch
    elsif new_f0 > ceiling_pitch
        new_f0 = ceiling_pitch
    endif
    
    selectObject: pitchTier
    Add point: t, new_f0
endfor

# === Replace Pitch Tier ===
selectObject: manipulation, pitchTier
Replace pitch tier

# === Resynthesize ===
appendInfoLine: "Resynthesizing..."
selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: originalName$ + "_rhythm_" + presetName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Rhythmic Pitch Percussion: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.7, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Rhythm"
    Text bottom: "yes", "Time (s)"
    
    # Pitch shift curve
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.7, 3.9
    
    # Find range
    minS = 0
    maxS = vizShifts#[1]
    for vp from 2 to maxVizPoints
        if vizShifts#[vp] > maxS
            maxS = vizShifts#[vp]
        endif
        if vizShifts#[vp] < minS
            minS = vizShifts#[vp]
        endif
    endfor
    
    sMargin = (maxS - minS) * 0.1
    if sMargin < 5
        sMargin = 5
    endif
    
    Axes: xmin, xmax, minS - sMargin, maxS + sMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", xmin, xmax, minS - sMargin, maxS + sMargin
    
    # Draw beat grid
    Colour: "{0.85, 0.85, 0.85}"
    for b from 1 to n_beats
        beatTime = xmin + (b - 1) * beat_duration
        if beatValues#[b] > 0
            Colour: "{0.9, 0.8, 0.8}"
            Paint rectangle: "{0.9, 0.8, 0.8}", beatTime, beatTime + beat_duration, minS - sMargin, maxS + sMargin
        endif
        Colour: "{0.8, 0.8, 0.8}"
        Dotted line
        Draw line: beatTime, minS - sMargin, beatTime, maxS + sMargin
        Solid line
    endfor
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Draw line: xmin, 0, xmax, 0
    
    # Draw pitch curve
    Colour: "{0.7, 0.4, 0.4}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizTimes#[vp] > 0 and vizTimes#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (st)"
    Text bottom: "yes", "Time (s)"
    
    # Rhythm pattern display
    Select outer viewport: 0, 8, 4.2, 4.9
    Select inner viewport: 0.6, 7.6, 4.3, 4.8
    
    Axes: 0, n_beats, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, n_beats, 0, 1.2
    
    # Draw beat bars
    for b from 1 to n_beats
        if beatValues#[b] > 0
            Colour: "{0.7, 0.4, 0.4}"
            Paint rectangle: "{0.7, 0.4, 0.4}", b - 0.8, b - 0.2, 0.1, 1.0
        else
            Colour: "{0.8, 0.8, 0.8}"
            Paint rectangle: "{0.8, 0.8, 0.8}", b - 0.8, b - 0.2, 0.1, 0.3
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pattern"
    
    # Stats
    Select outer viewport: 0, 8, 5.0, 5.3
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    # Count hits
    hitCount = 0
    for b from 1 to n_beats
        if beatValues#[b] > 0
            hitCount = hitCount + 1
        endif
    endfor
    
    Text: 0.5, "centre", 0.5, "half", "Beats: " + string$(n_beats) + " | Hits: " + string$(hitCount) + " | Strength: " + string$(hit_strength) + " | Decay: " + fixed$(decay_rate, 1) + " | Poly: " + string$(polyrhythm_factor)
    
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
