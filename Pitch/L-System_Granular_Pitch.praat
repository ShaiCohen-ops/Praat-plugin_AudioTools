# ============================================================
# Praat AudioTools - L-System_Granular_Pitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   L-System Granular Pitch Effect - uses Lindenmayer systems
#   to generate algorithmic patterns for granular gating and
#   pitch control. Symbols: G=grain, S=skip, U=pitch up,
#   D=pitch down, N=neutral. Creates self-similar structures.
#
# Changelog v0.4.1 (from 0.4.0):
#   - Fixed the Fibonacci preset, which had no audible effect: its
#     rules only produced G and N, and N is a no-op (plays like G,
#     no skip, no pitch). New rules emit G/U/D/S so the self-similar
#     pattern drives both gating (S) and pitch (U/D, oscillating).
#
# Changelog v0.4.0 (from 0.3.0):
#   - Smoother gating: grains now form a continuous gain envelope
#     (raised-cosine head ramp from the previous grain's gain to its
#     own, then hold) instead of fading each grain to zero at both
#     edges. Contiguous play grains are no longer notched at every
#     boundary, removing the grain-rate tremolo. Transition window
#     widened to 12 ms. GrainOverlap=0 still gives hard steps.
#
# Changelog v0.3.0 (from 0.2.1):
#   - Mono-safe: source folded to mono before To Manipulation /
#     To Pitch (both mono-only); stereo no longer errors
#   - Visualization: pattern-panel legend spread across the panel
#     (x was a width-fraction under a 0..grains axis, so all four
#     labels piled at the left); Axes set before the title,
#     L-System info, and stats captions so they center correctly
#   - Clamp pitch-tier targets to the manipulation's [75,600] range
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
dur = Get total duration
sr = Get sampling frequency
start_t = Get start time
end_t = Get end time
n_ch = Get number of channels

# === Form ===
form L-System Granular Pitch
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 9
        option Rhythmic Stutter
        option Pitch Walk Up
        option Pitch Walk Down
        option Chaotic Glitch
        option Melodic Arpeggio
        option Sparse Texture
        option Dense Granular
        option Fibonacci Pattern
        option Custom
    
    comment === L-System Rules ===
    sentence Axiom G
    sentence Rule_G GSUN
    sentence Rule_S N
    sentence Rule_U UD
    sentence Rule_D DU
    sentence Rule_N G
    positive Iterations 3
    positive MaxStringLength 10000
    
    comment === Granular ===
    positive GrainDuration_ms 50
    boolean GrainOverlap 1
    real BaseSkipGain 0.0
    real RepeatGain 1.0
    
    comment === Pitch ===
    real BasePitchShift_semitones 0
    real PitchStep_semitones 2
    positive MaxPitchShift_semitones 12
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Rhythmic Stutter
    axiom$ = "GS"
    rule_G$ = "GSS"
    rule_S$ = "SG"
    rule_U$ = "U"
    rule_D$ = "D"
    rule_N$ = "N"
    iterations = 4
    grainDuration_ms = 40
    grainOverlap = 1
    baseSkipGain = 0.0
    repeatGain = 1.0
    basePitchShift_semitones = 0
    pitchStep_semitones = 1
    presetName$ = "Stutter"
elsif preset = 2
    # Pitch Walk Up
    axiom$ = "GU"
    rule_G$ = "GUN"
    rule_S$ = "N"
    rule_U$ = "UUN"
    rule_D$ = "N"
    rule_N$ = "G"
    iterations = 3
    grainDuration_ms = 60
    basePitchShift_semitones = -6
    pitchStep_semitones = 1
    presetName$ = "Walk Up"
elsif preset = 3
    # Pitch Walk Down
    axiom$ = "GD"
    rule_G$ = "GDN"
    rule_S$ = "N"
    rule_U$ = "N"
    rule_D$ = "DDN"
    rule_N$ = "G"
    iterations = 3
    grainDuration_ms = 60
    basePitchShift_semitones = 6
    pitchStep_semitones = 1
    presetName$ = "Walk Down"
elsif preset = 4
    # Chaotic Glitch
    axiom$ = "GSUD"
    rule_G$ = "GSUN"
    rule_S$ = "N"
    rule_U$ = "UD"
    rule_D$ = "DU"
    rule_N$ = "G"
    iterations = 3
    grainDuration_ms = 50
    basePitchShift_semitones = 0
    pitchStep_semitones = 2
    presetName$ = "Chaotic"
elsif preset = 5
    # Melodic Arpeggio
    axiom$ = "GUUUDDD"
    rule_G$ = "G"
    rule_S$ = "G"
    rule_U$ = "UN"
    rule_D$ = "DN"
    rule_N$ = "N"
    iterations = 2
    grainDuration_ms = 80
    basePitchShift_semitones = -4
    pitchStep_semitones = 2
    presetName$ = "Arpeggio"
elsif preset = 6
    # Sparse Texture
    axiom$ = "S"
    rule_G$ = "GSSS"
    rule_S$ = "SSSG"
    rule_U$ = "U"
    rule_D$ = "D"
    rule_N$ = "S"
    iterations = 4
    grainDuration_ms = 30
    baseSkipGain = 0.05
    repeatGain = 0.8
    pitchStep_semitones = 3
    presetName$ = "Sparse"
elsif preset = 7
    # Dense Granular
    axiom$ = "G"
    rule_G$ = "GGUNG"
    rule_S$ = "G"
    rule_U$ = "UNG"
    rule_D$ = "DNG"
    rule_N$ = "NG"
    iterations = 3
    grainDuration_ms = 25
    baseSkipGain = 0.2
    repeatGain = 0.9
    pitchStep_semitones = 1
    presetName$ = "Dense"
elsif preset = 8
    # Fibonacci Pattern (self-similar substitution driving BOTH
    # gating and pitch: G=play, U=play+up, D=play+down, S=skip)
    axiom$ = "GU"
    rule_G$ = "GU"
    rule_S$ = "G"
    rule_U$ = "SD"
    rule_D$ = "GU"
    rule_N$ = "N"
    iterations = 5
    grainDuration_ms = 45
    basePitchShift_semitones = -6
    pitchStep_semitones = 1
    presetName$ = "Fibonacci"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== L-System Granular Pitch ==="
appendInfoLine: "Source: ", name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Axiom: ", axiom$
appendInfoLine: "Rules: G→", rule_G$, " S→", rule_S$, " U→", rule_U$, " D→", rule_D$, " N→", rule_N$
appendInfoLine: "Iterations: ", iterations
appendInfoLine: ""

# === L-System Generation ===
appendInfoLine: "Generating L-System..."

curr_str$ = axiom$
curr_len = length(curr_str$)

for iter from 1 to iterations
    next_str$ = ""
    for i from 1 to curr_len
        char$ = mid$(curr_str$, i, 1)
        rep$ = char$
        if char$ = "G"
            rep$ = rule_G$
        elsif char$ = "S"
            rep$ = rule_S$
        elsif char$ = "U"
            rep$ = rule_U$
        elsif char$ = "D"
            rep$ = rule_D$
        elsif char$ = "N"
            rep$ = rule_N$
        endif
        next_str$ = next_str$ + rep$
    endfor
    curr_str$ = next_str$
    curr_len = length(curr_str$)
    
    if curr_len > maxStringLength
        curr_str$ = left$(curr_str$, maxStringLength)
        curr_len = maxStringLength
        iter = iterations
    endif
endfor

l_sys$ = curr_str$
l_len = curr_len

appendInfoLine: "L-System length: ", l_len, " symbols"
appendInfoLine: "First 50 chars: ", left$(l_sys$, 50), "..."
appendInfoLine: ""

# === Grain Schedule ===
grain_dur_sec = grainDuration_ms / 1000
n_grains = floor(dur / grain_dur_sec)
if n_grains < 1
    n_grains = 1
endif

# Store for visualization
maxVizGrains = min(n_grains, 200)
vizSymbols$# = empty$#(maxVizGrains)
vizPitch# = zero#(maxVizGrains)
vizPlay# = zero#(maxVizGrains)

scheduleTable = Create Table with column names: "schedule", n_grains,
    ... "idx symbol tStart tEnd tCenter pitchShift play"

cum_pitch = basePitchShift_semitones
appendInfoLine: "Building grain schedule (", n_grains, " grains)..."

for k from 1 to n_grains
    sym_idx = ((k - 1) mod l_len) + 1
    sym$ = mid$(l_sys$, sym_idx, 1)
    
    t1 = start_t + (k - 1) * grain_dur_sec
    t2 = t1 + grain_dur_sec
    if t2 > end_t
        t2 = end_t
    endif
    tc = (t1 + t2) / 2
    
    this_pitch = cum_pitch
    
    if sym$ = "U"
        cum_pitch = cum_pitch + pitchStep_semitones
    elsif sym$ = "D"
        cum_pitch = cum_pitch - pitchStep_semitones
    endif
    
    if cum_pitch > maxPitchShift_semitones
        cum_pitch = maxPitchShift_semitones
    elsif cum_pitch < -maxPitchShift_semitones
        cum_pitch = -maxPitchShift_semitones
    endif
    
    do_play = 1
    if sym$ = "S"
        do_play = 0
    endif
    
    # Store for visualization
    if k <= maxVizGrains
        vizSymbols$#[k] = sym$
        vizPitch#[k] = this_pitch
        vizPlay#[k] = do_play
    endif
    
    selectObject: scheduleTable
    Set numeric value: k, "idx", k
    Set string value: k, "symbol", sym$
    Set numeric value: k, "tStart", t1
    Set numeric value: k, "tEnd", t2
    Set numeric value: k, "tCenter", tc
    Set numeric value: k, "pitchShift", this_pitch
    Set numeric value: k, "play", do_play
endfor

# === Pitch Processing ===
appendInfoLine: "Applying pitch shifting..."

# Fold to mono (To Manipulation / To Pitch are mono-only)
selectObject: original
nch = Get number of channels
if nch > 1
    src = Convert to mono
    appendInfoLine: "  (stereo input folded to mono)"
else
    src = Copy: name$ + "_srcmono"
endif

selectObject: src
manipulation = To Manipulation: 0.01, 75, 600

selectObject: manipulation
pitchTier = Extract pitch tier
selectObject: pitchTier
Remove points between: start_t, end_t

selectObject: src
refPitch = To Pitch: 0.01, 75, 600

for k from 1 to n_grains
    selectObject: scheduleTable
    tc = Get value: k, "tCenter"
    shift = Get value: k, "pitchShift"
    
    selectObject: refPitch
    f_orig = Get value at time: tc, "Hertz", "Linear"
    if f_orig = undefined
        f_orig = 150
    endif
    
    f_target = f_orig * (2 ^ (shift / 12))
    if f_target < 75
        f_target = 75
    elsif f_target > 600
        f_target = 600
    endif
    
    selectObject: pitchTier
    Add point: tc, f_target
endfor

selectObject: manipulation, pitchTier
Replace pitch tier

selectObject: manipulation
resynthSound = Get resynthesis (overlap-add)
Rename: name$ + "_pitched"

removeObject: manipulation, pitchTier, refPitch, src

# === Granular Gating ===
selectObject: resynthSound
result = Copy: name$ + "_LSystem_" + presetName$
channels = Get number of channels

# Smooth gating: build a continuous gain envelope. Each grain holds
# its own gain and ramps ONLY at its head, from the previous grain's
# gain to its own (raised-cosine). Within a run of equal-gain grains
# the head ramp is flat, so contiguous grains are no longer notched
# to zero at every boundary (which caused the grain-rate tremolo).
fade_time = min(grain_dur_sec / 2, 0.012)

appendInfoLine: "Applying granular gating..."

prevGain = 0
for k from 1 to n_grains
    selectObject: scheduleTable
    t1 = Get value: k, "tStart"
    t2 = Get value: k, "tEnd"
    play = Get value: k, "play"
    
    len = t2 - t1
    if len > 0
        if play = 1
            thisGain = repeatGain
        else
            thisGain = baseSkipGain
        endif
        
        ft = fade_time
        if ft > len
            ft = len
        endif
        
        selectObject: result
        
        if grainOverlap
            # Raised-cosine head ramp prevGain -> thisGain, then hold
            Formula (part): t1, t2, 1, channels,
                ... ~ self * (if x < t1 + ft then prevGain + (thisGain - prevGain) * (0.5 - 0.5 * cos(pi * (x - t1) / ft)) else thisGain fi)
        else
            # Hard step (no smoothing)
            Formula (part): t1, t2, 1, channels, ~ self * thisGain
        endif
        
        prevGain = thisGain
    endif
endfor

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "L-System Granular: " + name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "L-System"
    Text bottom: "yes", "Time (s)"
    
    # L-System pattern visualization
    Select outer viewport: 0, 8, 2.7, 3.6
    Select inner viewport: 0.6, 7.6, 2.9, 3.5
    
    Axes: 0, maxVizGrains, -1, 1.5
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxVizGrains, -1, 1.5
    
    # Draw grain bars colored by symbol
    barWidth = 0.8
    for g from 1 to maxVizGrains
        sym$ = vizSymbols$#[g]
        
        if sym$ = "G"
            col$ = "{0.5, 0.7, 0.5}"
            yTop = 1
        elsif sym$ = "S"
            col$ = "{0.7, 0.5, 0.5}"
            yTop = 0.3
        elsif sym$ = "U"
            col$ = "{0.5, 0.5, 0.8}"
            yTop = 1
        elsif sym$ = "D"
            col$ = "{0.8, 0.6, 0.5}"
            yTop = 1
        else
            col$ = "{0.6, 0.6, 0.6}"
            yTop = 0.7
        endif
        
        Paint rectangle: col$, g - barWidth/2, g + barWidth/2, 0, yTop * vizPlay#[g] + 0.1
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pattern"
    
    # Legend
    Font size: 5
    Colour: "{0.5, 0.7, 0.5}"
    Text: 0.02 * maxVizGrains, "left", 1.3, "half", "G=grain"
    Colour: "{0.7, 0.5, 0.5}"
    Text: 0.12 * maxVizGrains, "left", 1.3, "half", "S=skip"
    Colour: "{0.5, 0.5, 0.8}"
    Text: 0.22 * maxVizGrains, "left", 1.3, "half", "U=up"
    Colour: "{0.8, 0.6, 0.5}"
    Text: 0.32 * maxVizGrains, "left", 1.3, "half", "D=down"
    
    # Pitch curve
    Select outer viewport: 0, 8, 3.8, 4.8
    Select inner viewport: 0.6, 7.6, 3.9, 4.7
    
    # Find pitch range
    minP = vizPitch#[1]
    maxP = vizPitch#[1]
    for g from 2 to maxVizGrains
        if vizPitch#[g] < minP
            minP = vizPitch#[g]
        endif
        if vizPitch#[g] > maxP
            maxP = vizPitch#[g]
        endif
    endfor
    
    pMargin = max(2, (maxP - minP) * 0.1)
    
    Axes: 0, maxVizGrains, minP - pMargin, maxP + pMargin
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, maxVizGrains, minP - pMargin, maxP + pMargin
    
    # Zero line
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, maxVizGrains, 0
    Solid line
    
    # Draw pitch curve
    Colour: "{0.4, 0.5, 0.7}"
    Line width: 1.5
    for g from 2 to maxVizGrains
        Draw line: g - 1, vizPitch#[g - 1], g, vizPitch#[g]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (st)"
    
    # L-System info
    Select outer viewport: 0, 8, 5.0, 5.3
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Axiom: " + axiom$ + " | Rules: G→" + rule_G$ + " S→" + rule_S$ + " U→" + rule_U$ + " | Iter: " + string$(iterations) + " → " + string$(l_len) + " symbols"
    
    # Stats
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Grains: " + string$(n_grains) + " (" + string$(grainDuration_ms) + "ms) | Pitch step: " + fixed$(pitchStep_semitones, 1) + " st | Range: ±" + string$(maxPitchShift_semitones) + " st"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: scheduleTable, resynthSound

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