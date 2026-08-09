# ============================================================
# Praat AudioTools - Rhythmic_Pitch_Percussion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic Pitch Percussion - applies percussive pitch hits
#   based on a rhythm pattern. Creates kick-drum-like pitch
#   envelopes with polyrhythmic ghost hits and tension waves.
#
# Changelog v0.3:
#   - Hit_strength is treated consistently as a Hz offset, matching the
#     existing preset values and the v0.2 pitch-calculation changelog.
#   - Rhythm_pattern parser validates at least one beat and only 0/1 tokens.
#   - Full xmin/xmax-safe processing; PitchTier clearing no longer assumes 0.
#   - Npoints is validated and bounded to avoid division-by-zero / runaway work.
#   - Ghost_hits can be 0 and parameter ranges are validated.
#   - Humanization is correlated per beat instead of random jitter at every point.
#   - Analysis range is separated from synthesis safety (20 Hz .. 0.45*SR).
#   - Stops cleanly when no usable voiced pitch is detected.
#   - Preserves source channel count by applying one shared PitchTier
#     independently to each source channel.
#   - Peak protection is attenuation-only.
#   - Visualization layout/style preserved; title/stats/xmin robustness fixed.
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
n_channels = Get number of channels

# === Form ===
form Rhythmic Pitch Percussion v0.3
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
    real Ghost_hits 0.3
    
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
    rhythm_pattern$ = "1_0_1_0_1_0_1_0_1_0_1_0_1_0"
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

# === Validation ===
if dur <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if hit_strength < 0
    exitScript: "Hit_strength must be zero or greater."
endif
if decay_rate <= 0
    exitScript: "Decay_rate must be greater than zero."
endif
if polyrhythm_factor <= 0
    exitScript: "Polyrhythm_factor must be greater than zero."
endif
if ghost_hits < 0
    exitScript: "Ghost_hits must be zero or greater."
endif
if time_step <= 0
    exitScript: "Time_step must be greater than zero."
endif
if floor_pitch <= 0 or ceiling_pitch <= floor_pitch
    exitScript: "Floor_pitch / Ceiling_pitch are invalid."
endif
if ceiling_pitch >= 0.45 * orig_sr
    exitScript: "Ceiling_pitch must be below 45% of the source sampling frequency."
endif
if npoints < 2 or npoints > 20000
    exitScript: "Npoints must be between 2 and 20000."
endif

# === Parse Rhythm Pattern ===
# Count underscore-separated tokens robustly.
if length(rhythm_pattern$) < 1
    exitScript: "Rhythm_pattern cannot be empty."
endif

n_beats = 1
for ci from 1 to length(rhythm_pattern$)
    if mid$(rhythm_pattern$, ci, 1) = "_"
        n_beats += 1
    endif
endfor

if n_beats < 1
    exitScript: "Rhythm_pattern must contain at least one beat."
endif
if n_beats > 512
    exitScript: "Rhythm_pattern is too long (maximum 512 beats)."
endif

beatValues# = zero#(n_beats)
rhythm$ = rhythm_pattern$ + "_"

for bIdx from 1 to n_beats
    sep = index(rhythm$, "_")
    if sep <= 1
        exitScript: "Rhythm_pattern contains an empty or malformed token."
    endif

    thisVal$ = left$(rhythm$, sep - 1)
    thisVal = number(thisVal$)

    if thisVal = undefined
        exitScript: "Rhythm_pattern contains a non-numeric token: " + thisVal$
    endif
    if thisVal <> 0 and thisVal <> 1
        exitScript: "Rhythm_pattern values must be exactly 0 or 1."
    endif

    beatValues#[bIdx] = thisVal
    rhythm$ = right$(rhythm$, length(rhythm$) - sep)
endfor

# === Info ===
writeInfoLine: "=== Rhythmic Pitch Percussion v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Pattern (", n_beats, " beats): ", rhythm_pattern$
appendInfoLine: "Hit strength: ", hit_strength, " Hz"
appendInfoLine: "Decay rate: ", decay_rate
appendInfoLine: "Polyrhythm: ", polyrhythm_factor
appendInfoLine: "Ghost hits: ", ghost_hits
appendInfoLine: ""

# === Mono Pitch Analysis ===
selectObject: original
if n_channels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: "RPP_analysis"
endif

selectObject: analysisMono
tmpPitchObj = To Pitch: time_step, floor_pitch, ceiling_pitch

selectObject: tmpPitchObj
voiced_frames = Count voiced frames
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"

if voiced_frames < 1 or median_f0 = undefined or median_f0 <= 0
    removeObject: tmpPitchObj, analysisMono
    exitScript: "No usable voiced pitch was detected in the selected analysis range."
endif

appendInfoLine: "Median pitch: ", fixed$(median_f0, 1), " Hz"
removeObject: tmpPitchObj, analysisMono

# === Create New Pitch Tier ===
Create PitchTier: "rhythm_pitch", xmin, xmax
pitchTier = selected("PitchTier")

beat_duration = dur / n_beats

# Store for visualization
maxVizPoints = min(npoints, 500)
if maxVizPoints < 1
    maxVizPoints = 1
endif
vizTimes# = zero#(maxVizPoints)
vizShifts# = zero#(maxVizPoints)
vizFilled# = zero#(maxVizPoints)
vizStep = npoints / maxVizPoints

# One humanization value per beat, not per PitchTier point.
beatHuman# = zero#(n_beats)
for hb from 1 to n_beats
    beatHuman#[hb] = randomUniform(0.95, 1.05)
endfor

# One humanization value per polyrhythmic subdivision bucket.
poly_count = ceiling(n_beats * polyrhythm_factor) + 1
polyHuman# = zero#(poly_count)
for ph from 1 to poly_count
    polyHuman#[ph] = randomUniform(0.95, 1.05)
endfor

appendInfoLine: ""
appendInfoLine: "Building percussive pitch curve..."

synth_floor = 20
synth_ceil = 0.45 * orig_sr
limited_points = 0

# === Build Rhythmic Pitch Curve ===
for i from 0 to npoints - 1
    t = xmin + (i / (npoints - 1)) * dur

    beat_pos = (t - xmin) / beat_duration
    current_beat = floor(beat_pos) + 1
    beat_phase = beat_pos - floor(beat_pos)

    if current_beat > n_beats
        current_beat = n_beats
        beat_phase = 1
    endif

    beat_value = beatValues#[current_beat]

    # Pitch offset in Hz around the source median F0.
    pitch_offset_hz = 0

    # Main hit envelope.
    if beat_value > 0
        attack = exp(-decay_rate * 3 * beat_phase)
        body = 0.6 * exp(-decay_rate * 0.8 * beat_phase)
        tail = 0.2 * exp(-decay_rate * 0.3 * beat_phase)
        envelope = attack + body + tail

        fundamental_hit = hit_strength * envelope
        harmonic_hit = 0.4 * hit_strength * envelope * sin(beat_phase * 8 * pi)

        pitch_offset_hz += (fundamental_hit + harmonic_hit) * beatHuman#[current_beat]
    endif

    # Polyrhythmic ghost hits.
    poly_beat_pos = beat_pos * polyrhythm_factor
    poly_phase = poly_beat_pos - floor(poly_beat_pos)
    poly_index = floor(poly_beat_pos) + 1
    if poly_index < 1
        poly_index = 1
    elsif poly_index > poly_count
        poly_index = poly_count
    endif

    if ghost_hits > 0 and poly_phase < 0.1
        ghost_envelope = exp(-20 * poly_phase)
        ghost_hit = ghost_hits * hit_strength * ghost_envelope
        pitch_offset_hz += ghost_hit * polyHuman#[poly_index]
    endif

    # Tension wave, now in Hz to match the rest of the engine.
    tension_base = sin(beat_pos * 2 * pi)
    tension_modulation = 1 + 0.3 * sin(beat_pos * 7 * pi)
    tension_wave_hz = 0.8 * tension_base * tension_modulation
    pitch_offset_hz += tension_wave_hz

    new_f0 = median_f0 + pitch_offset_hz

    # Synthesis safety, independent of the analysis range.
    if new_f0 < synth_floor
        new_f0 = synth_floor
        limited_points += 1
    elsif new_f0 > synth_ceil
        new_f0 = synth_ceil
        limited_points += 1
    endif

    selectObject: pitchTier
    Add point: t, new_f0

    # Visualization stores the actual Hz offset used.
    vizIdx = floor(i / vizStep) + 1
    if vizIdx < 1
        vizIdx = 1
    elsif vizIdx > maxVizPoints
        vizIdx = maxVizPoints
    endif
    if vizFilled#[vizIdx] = 0
        vizTimes#[vizIdx] = t
        vizShifts#[vizIdx] = pitch_offset_hz
        vizFilled#[vizIdx] = 1
    endif
endfor

if limited_points > 0
    appendInfoLine: "Sampling-safe pitch limits applied: ", limited_points, " point(s)"
endif

# === Resynthesize each source channel with shared PitchTier ===
appendInfoLine: "Resynthesizing ", n_channels, " channel(s)..."

channelResults# = zero#(n_channels)

for ch from 1 to n_channels
    selectObject: original
    if n_channels = 1
        channelWork = Copy: "RPP_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: "RPP_ch" + string$(ch)
    endif

    selectObject: channelWork
    manipulation = To Manipulation: time_step, floor_pitch, ceiling_pitch

    selectObject: manipulation
    plusObject: pitchTier
    Replace pitch tier

    selectObject: manipulation
    channelResult = Get resynthesis (overlap-add)
    Rename: "RPP_result_ch" + string$(ch)
    channelResults#[ch] = channelResult

    removeObject: manipulation, channelWork
endfor

# Rebuild exact source channel count / time domain.
Create Sound from formula: "RPP_result_build", n_channels,
    ... xmin, xmax, orig_sr, "0"
result = selected("Sound")

for ch from 1 to n_channels
    selectObject: result
    Formula (part): xmin, xmax, ch, ch,
        ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
    removeObject: channelResults#[ch]
endfor

selectObject: result
Rename: originalName$ + "_rhythm_" + presetName$

# Attenuation-only peak safety.
result_peak = Get absolute extremum: 0, 0, "None"
if result_peak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
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
    firstViz = 0
    for vp from 1 to maxVizPoints
        if vizFilled#[vp] = 1
            if firstViz = 0
                minS = vizShifts#[vp]
                maxS = vizShifts#[vp]
                firstViz = 1
            else
                if vizShifts#[vp] > maxS
                    maxS = vizShifts#[vp]
                endif
                if vizShifts#[vp] < minS
                    minS = vizShifts#[vp]
                endif
            endif
        endif
    endfor
    if firstViz = 0
        minS = -5
        maxS = 5
    endif
    
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
        if vizFilled#[vp] = 1 and vizFilled#[vp - 1] = 1
            Draw line: vizTimes#[vp - 1], vizShifts#[vp - 1], vizTimes#[vp], vizShifts#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch offset (Hz)"
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
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    # Count hits
    hitCount = 0
    for b from 1 to n_beats
        if beatValues#[b] > 0
            hitCount = hitCount + 1
        endif
    endfor
    
    Text: 0.5, "centre", 0.5, "half", "Beats: " + string$(n_beats) + " | Hits: " + string$(hitCount) + " | Strength: " + string$(hit_strength) + " Hz | Decay: " + fixed$(decay_rate, 1) + " | Poly: " + string$(polyrhythm_factor)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: pitchTier

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
