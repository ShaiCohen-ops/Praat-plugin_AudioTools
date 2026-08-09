# ============================================================
# Praat AudioTools - L-System_Granular_Pitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   L-System Granular Pitch Effect - uses Lindenmayer systems
#   to generate algorithmic patterns for granular gating and
#   pitch control. Symbols: G=grain, S=skip, U=pitch up,
#   D=pitch down, N=neutral. Creates self-similar structures.
#
# Changelog v0.5:
#   - Preserves the original number of channels.
#   - U/D now affect their OWN grain rather than the following grain.
#   - Grain schedule uses ceiling(), so the final partial grain reaches end_t.
#   - Preserves the detected source F0 contour on a fixed 100-Hz control grid.
#   - No-pitch material skips PSOLA gracefully and still receives L-System gating.
#   - Separates source pitch-analysis range from target F0 safety limits.
#   - BasePitchShift is clamped before the first grain.
#   - L-System generation stops growing at MaxStringLength while building,
#     avoiding a large temporary string before truncation.
#   - Attenuation-only peak safety replaces unconditional normalization.
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

# === Validation ===
iterations = floor(iterations)
maxStringLength = floor(maxStringLength)

if iterations < 1
    exitScript: "Iterations must be at least 1."
endif
if maxStringLength < 1
    exitScript: "MaxStringLength must be at least 1."
endif
if length(axiom$) < 1
    exitScript: "Axiom must not be empty."
endif
if grainDuration_ms <= 0
    exitScript: "GrainDuration_ms must be greater than zero."
endif
if baseSkipGain < 0 or repeatGain < 0
    exitScript: "BaseSkipGain and RepeatGain must be non-negative."
endif
if maxPitchShift_semitones <= 0
    exitScript: "MaxPitchShift_semitones must be greater than zero."
endif

# Clamp the starting shift before scheduling the first symbol.
if basePitchShift_semitones > maxPitchShift_semitones
    basePitchShift_semitones = maxPitchShift_semitones
elsif basePitchShift_semitones < -maxPitchShift_semitones
    basePitchShift_semitones = -maxPitchShift_semitones
endif

# === Info ===
writeInfoLine: "=== L-System Granular Pitch v0.5 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels preserved: ", n_ch
appendInfoLine: ""
appendInfoLine: "Axiom: ", axiom$
appendInfoLine: "Rules: G→", rule_G$, " S→", rule_S$, " U→", rule_U$, " D→", rule_D$, " N→", rule_N$
appendInfoLine: "Iterations: ", iterations
appendInfoLine: ""

# === L-System Generation ===
appendInfoLine: "Generating L-System..."

curr_str$ = axiom$
if length(curr_str$) > maxStringLength
    curr_str$ = left$(curr_str$, maxStringLength)
endif
curr_len = length(curr_str$)

for iter from 1 to iterations
    next_str$ = ""
    reachedMax = 0

    for i from 1 to curr_len
        if reachedMax = 0
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

            remaining = maxStringLength - length(next_str$)
            repLen = length(rep$)

            if remaining <= 0
                reachedMax = 1
            elsif repLen <= remaining
                next_str$ = next_str$ + rep$
            else
                next_str$ = next_str$ + left$(rep$, remaining)
                reachedMax = 1
            endif
        endif
    endfor

    curr_str$ = next_str$
    curr_len = length(curr_str$)

    if curr_len < 1
        exitScript: "The L-System rules produced an empty string."
    endif

    if reachedMax
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
n_grains = ceiling(dur / grain_dur_sec)
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
    t2 = min(end_t, t1 + grain_dur_sec)
    tc = (t1 + t2) / 2

    # U/D affect THIS grain.
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

    this_pitch = cum_pitch

    do_play = 1
    if sym$ = "S"
        do_play = 0
    endif

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

# === Pitch Analysis ===
appendInfoLine: "Analysing source pitch..."

analysisFloor = 40
analysisCeiling = min(1200, 0.45 * sr)

if analysisCeiling <= analysisFloor
    removeObject: scheduleTable
    exitScript: "Sampling rate is too low for pitch analysis."
endif

selectObject: original
if n_ch > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: name$ + "_pitch_analysis"
endif

selectObject: analysisMono
refPitch = To Pitch: 0.01, analysisFloor, analysisCeiling

selectObject: refPitch
medianF0 = Get quantile: 0, 0, 0.5, "Hertz"

pitchApplied = 0
limitedPitchPoints = 0

if medianF0 = undefined
    appendInfoLine: "  No usable F0 detected: pitch stage skipped; gating will still run."

    selectObject: original
    resynthSound = Copy: name$ + "_pitch_passthrough"

    removeObject: refPitch, analysisMono
else
    appendInfoLine: "  Median detected F0: ", fixed$(medianF0, 1), " Hz"

    # Build a source-F0-preserving target PitchTier on a fixed 100-Hz grid.
    Create PitchTier: "lsys_pitch", start_t, end_t
    pitchTier = selected("PitchTier")

    controlStep = 0.01
    nControl = ceiling(dur / controlStep) + 1
    if nControl < 2
        nControl = 2
    endif

    targetMinHz = 20
    targetMaxHz = 0.45 * sr
    voicedPoints = 0

    for i from 0 to nControl - 1
        if i = nControl - 1
            t = end_t
        else
            t = min(end_t, start_t + i * controlStep)
        endif

        grainIndex = floor((t - start_t) / grain_dur_sec) + 1
        if grainIndex < 1
            grainIndex = 1
        elsif grainIndex > n_grains
            grainIndex = n_grains
        endif

        selectObject: scheduleTable
        shift = Get value: grainIndex, "pitchShift"

        selectObject: refPitch
        f_orig = Get value at time: t, "Hertz", "Linear"

        if f_orig <> undefined and f_orig > 0
            f_target = f_orig * (2 ^ (shift / 12))

            if f_target < targetMinHz
                f_target = targetMinHz
                limitedPitchPoints += 1
            elsif f_target > targetMaxHz
                f_target = targetMaxHz
                limitedPitchPoints += 1
            endif

            selectObject: pitchTier
            Add point: t, f_target
            voicedPoints += 1
        endif
    endfor

    if voicedPoints = 0
        appendInfoLine: "  No usable F0 control points: pitch stage skipped."

        selectObject: original
        resynthSound = Copy: name$ + "_pitch_passthrough"

        removeObject: pitchTier, refPitch, analysisMono
    else
        appendInfoLine: "  Pitch control points: ", voicedPoints
        if limitedPitchPoints > 0
            appendInfoLine: "  Sampling-safe F0 limits applied: ", limitedPitchPoints, " point(s)"
        endif

        # Resynthesize each original channel independently with the SAME
        # source-derived target PitchTier, then rebuild the original layout.
        channelResultIDs# = zero#(n_ch)

        for ch from 1 to n_ch
            selectObject: original
            if n_ch = 1
                channelWork = Copy: name$ + "_lsys_ch1"
            else
                channelWork = Extract one channel: ch
                Rename: name$ + "_lsys_ch" + string$(ch)
            endif

            selectObject: channelWork
            channelManip = To Manipulation: 0.01, analysisFloor, analysisCeiling

            selectObject: pitchTier
            plusObject: channelManip
            Replace pitch tier

            selectObject: channelManip
            channelRes = Get resynthesis (overlap-add)
            Rename: name$ + "_lsys_pitch_ch" + string$(ch)
            channelResultIDs#[ch] = channelRes

            removeObject: channelManip, channelWork
        endfor

        if n_ch = 1
            resynthSound = channelResultIDs#[1]
        else
            selectObject: channelResultIDs#[1]
            for ch from 2 to n_ch
                plusObject: channelResultIDs#[ch]
            endfor
            resynthSound = Combine to stereo
            Rename: name$ + "_pitched"

            for ch from 1 to n_ch
                removeObject: channelResultIDs#[ch]
            endfor
        endif

        removeObject: pitchTier, refPitch, analysisMono
        pitchApplied = 1
    endif
endif

# === Granular Gating ===
selectObject: resynthSound
result = Copy: name$ + "_LSystem_" + presetName$
channels = Get number of channels

# Smooth gating: build a continuous gain envelope. Each grain holds
# its own gain and ramps ONLY at its head, from the previous grain's
# gain to its own (raised-cosine).
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
            if ft > 0
                Formula (part): t1, t2, 1, channels,
                    ... ~ self * (if x < t1 + ft then prevGain + (thisGain - prevGain) * (0.5 - 0.5 * cos(pi * (x - t1) / ft)) else thisGain fi)
            else
                Formula (part): t1, t2, 1, channels, ~ self * thisGain
            endif
        else
            Formula (part): t1, t2, 1, channels, ~ self * thisGain
        endif

        prevGain = thisGain
    endif
endfor

# === Attenuation-only Peak Safety ===
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.95
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

    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: 0, 0, maxVizGrains, 0
    Solid line

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
appendInfoLine: "Output channels: ", channels
if pitchApplied
    appendInfoLine: "Pitch stage: applied"
else
    appendInfoLine: "Pitch stage: skipped"
endif
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
