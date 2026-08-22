# ============================================================
# Praat AudioTools - 8-Channel_Canon.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# v0.4.2 (2026): RUNTIME VISUAL QA - vertical panel gaps corrected; DSP unchanged.
# v0.4 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Canon Generator - creates a musical canon effect
#   with 8 pitch-shifted voices on separate channels, deliverable
#   as octophonic, stems, or a downmix.
#
# Changelog v0.4 (2026):
#   - NEW: Output_format menu. The canon mechanism is untouched; the
#     branch happens only after ch1-ch8 are complete.
#       1  8 channels - octophonic          (default, v0.2 behaviour)
#       2  4 stereo pairs                   V1|V2  V3|V4  V5|V6  V7|V8
#       3  2 quadraphonic groups            V1-V4, V5-V8
#       4  4-channel fold-down              V1+V5, V2+V6, V3+V7, V4+V8
#       5  Stereo mix                       L: V1-V4   R: V5-V8
#     The fold-down pairs voices four apart rather than adjacent, so
#     both turns of the canon land on the same channel pattern and the
#     cyclic identity of the array survives the downmix.
#   - NEW: shared-gain normalisation. v0.2 scaled a single result to
#     0.95, which does not generalise: normalising four stereo pairs
#     independently would give a quiet pair more gain than a loud one
#     and silently rewrite the balance between voice groups. One gain
#     is now derived from the loudest of the eight working channels and
#     applied to all of them, so every format - and every stem within a
#     format - carries the same level. The two summing formats are
#     summed first and the finished object normalised once.
#   - NEW: monitoring mix. The spectrogram was built by folding the
#     single 8-channel result to mono, which only worked because there
#     was always exactly one output object. Using the first stem
#     instead would show a quarter or a half of the canon, so a
#     temporary mono mix of all eight working channels now feeds the
#     spectrogram in every format.
#   - NEW: in stem formats, Play_result auditions that monitoring mix
#     rather than the first stem, and says so. Playing out[1] alone
#     would be a quarter of the canon presented as the result.
#   - NEW: the Info window reports the output format, the number of
#     output objects, their channel counts and the exact mapping, and
#     the closing line is no longer hard-coded to "8-channel".
#   - FIX: the Sound check ran after the form, so a wrong selection was
#     only reported once ~20 fields had been filled in. It runs first.
#   - FIX: negative delays. Delay fields accept any real, but a
#     negative delay made Formula (part) start before the buffer, which
#     truncates the voice. Delays are now shifted as a block so the
#     earliest entry is 0, preserving every relative offset.
#   - FIX: fade guard. Fade_time longer than half a voice made the
#     fade-in and fade-out overlap. It is now clamped per voice.
#   - FIX: voice placement used "Sound_'name$'(x - 'd')". The backtick
#     numeric form is fragile across versions; string$() concatenation
#     is the portable idiom. Voices are also renamed to canonvoiceN so
#     the by-name reference cannot collide with a user object called
#     voice_1.
#   - FIX: cleanup is driven by an explicit output list. v0.2's cleanup
#     assumed one result; formats 2 and 3 leave four and two objects
#     alive and every intermediate still has to go.
#
# Changelog v0.2:
#   - Added time delays for true canon effect
#   - Changed from Hz to semitones (more musical)
#   - Fixed cleanup
#   - Added visualization
#   - Refactored with loops
# ============================================================

# === Check Input (before the form, so a bad selection costs nothing) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Canon Settings
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Canon (unison, staggered)"
        option: "Cluster (1-3 semitones)"
        option: "Wide Spread (4-10 semitones)"
        option: "Microtonal (quarter-tones)"
        option: "Symmetrical (mirror intervals)"
        option: "Octave Stack"
        option: "Major Scale"
        option: "Chromatic"
        option: "Fifths Tower"
    
    comment === Pitch shifts (semitones) ===
    real Semitones_1 0
    real Semitones_2 2
    real Semitones_3 4
    real Semitones_4 5
    real Semitones_5 7
    real Semitones_6 9
    real Semitones_7 11
    real Semitones_8 12
    
    comment === Canon delays (seconds) ===
    real Delay_1 0.0
    real Delay_2 0.2
    real Delay_3 0.4
    real Delay_4 0.6
    real Delay_5 0.8
    real Delay_6 1.0
    real Delay_7 1.2
    real Delay_8 1.4
    
    comment === Settings ===
    positive Resample_frequency 44100
    real Fade_time 0.01
    
    comment === Output format ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (V1-V8)"
        option: "4 stereo pairs (V1|V2, V3|V4, V5|V6, V7|V8)"
        option: "2 quadraphonic groups (V1-V4, V5-V8)"
        option: "4-channel fold-down (V1+V5, V2+V6, V3+V7, V4+V8)"
        option: "Stereo mix (L: V1-V4, R: V5-V8)"
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Canon (unison, staggered)
    semitones_1 = 0
    semitones_2 = 0
    semitones_3 = 0
    semitones_4 = 0
    semitones_5 = 0
    semitones_6 = 0
    semitones_7 = 0
    semitones_8 = 0
    delay_1 = 0.0
    delay_2 = 0.3
    delay_3 = 0.6
    delay_4 = 0.9
    delay_5 = 1.2
    delay_6 = 1.5
    delay_7 = 1.8
    delay_8 = 2.1
    presetName$ = "Classic"
elsif preset = 3
    # Cluster (1-3 semitones)
    semitones_1 = 0
    semitones_2 = 1
    semitones_3 = 2
    semitones_4 = 3
    semitones_5 = -1
    semitones_6 = -2
    semitones_7 = -3
    semitones_8 = -4
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    delay_5 = 0.6
    delay_6 = 0.75
    delay_7 = 0.9
    delay_8 = 1.05
    presetName$ = "Cluster"
elsif preset = 4
    # Wide Spread
    semitones_1 = 0
    semitones_2 = 4
    semitones_3 = 7
    semitones_4 = 10
    semitones_5 = -3
    semitones_6 = -7
    semitones_7 = -10
    semitones_8 = -14
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    delay_5 = 1.0
    delay_6 = 1.25
    delay_7 = 1.5
    delay_8 = 1.75
    presetName$ = "Wide"
elsif preset = 5
    # Microtonal (quarter-tones = 0.5 semitones)
    semitones_1 = 0
    semitones_2 = 0.5
    semitones_3 = 1.0
    semitones_4 = 1.5
    semitones_5 = 2.0
    semitones_6 = -0.5
    semitones_7 = -1.0
    semitones_8 = -1.5
    delay_1 = 0.0
    delay_2 = 0.1
    delay_3 = 0.2
    delay_4 = 0.3
    delay_5 = 0.4
    delay_6 = 0.5
    delay_7 = 0.6
    delay_8 = 0.7
    presetName$ = "Microtonal"
elsif preset = 6
    # Symmetrical (mirror intervals)
    semitones_1 = 6
    semitones_2 = 4
    semitones_3 = 2
    semitones_4 = 0
    semitones_5 = 0
    semitones_6 = -2
    semitones_7 = -4
    semitones_8 = -6
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    delay_5 = 0.6
    delay_6 = 0.8
    delay_7 = 1.0
    delay_8 = 1.2
    presetName$ = "Symmetrical"
elsif preset = 7
    # Octave Stack
    semitones_1 = 0
    semitones_2 = 12
    semitones_3 = -12
    semitones_4 = 24
    semitones_5 = -24
    semitones_6 = 12
    semitones_7 = -12
    semitones_8 = 0
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    delay_5 = 0.8
    delay_6 = 1.0
    delay_7 = 1.2
    delay_8 = 1.4
    presetName$ = "Octaves"
elsif preset = 8
    # Major Scale
    semitones_1 = 0
    semitones_2 = 2
    semitones_3 = 4
    semitones_4 = 5
    semitones_5 = 7
    semitones_6 = 9
    semitones_7 = 11
    semitones_8 = 12
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    delay_5 = 0.6
    delay_6 = 0.75
    delay_7 = 0.9
    delay_8 = 1.05
    presetName$ = "MajorScale"
elsif preset = 9
    # Chromatic
    semitones_1 = 0
    semitones_2 = 1
    semitones_3 = 2
    semitones_4 = 3
    semitones_5 = 4
    semitones_6 = 5
    semitones_7 = 6
    semitones_8 = 7
    delay_1 = 0.0
    delay_2 = 0.1
    delay_3 = 0.2
    delay_4 = 0.3
    delay_5 = 0.4
    delay_6 = 0.5
    delay_7 = 0.6
    delay_8 = 0.7
    presetName$ = "Chromatic"
elsif preset = 10
    # Fifths Tower (stacked perfect fifths)
    semitones_1 = 0
    semitones_2 = 7
    semitones_3 = 14
    semitones_4 = 21
    semitones_5 = -7
    semitones_6 = -14
    semitones_7 = -21
    semitones_8 = -28
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    delay_5 = 1.0
    delay_6 = 1.25
    delay_7 = 1.5
    delay_8 = 1.75
    presetName$ = "Fifths"
else
    presetName$ = "Custom"
endif

# === Output format labels and mapping ===
if output_format = 1
    formatName$ = "8-channel octophonic"
    formatShort$ = "8ch"
elsif output_format = 2
    formatName$ = "4 stereo pairs"
    formatShort$ = "4 pairs"
elsif output_format = 3
    formatName$ = "2 quadraphonic groups"
    formatShort$ = "2 quads"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    formatShort$ = "fold-4"
else
    formatName$ = "Stereo mix"
    formatShort$ = "stereo"
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration

# === Create Base Mono ===
selectObject: originalID
Copy: "base_work"
baseWorkID = selected("Sound")
Convert to mono
monoID = selected("Sound")
Resample: resample_frequency, 50
baseResampledID = selected("Sound")
Rename: "base_resampled"
baseDur = Get total duration

removeObject: baseWorkID, monoID

# === Store parameters in arrays ===
semi[1] = semitones_1
semi[2] = semitones_2
semi[3] = semitones_3
semi[4] = semitones_4
semi[5] = semitones_5
semi[6] = semitones_6
semi[7] = semitones_7
semi[8] = semitones_8

delay[1] = delay_1
delay[2] = delay_2
delay[3] = delay_3
delay[4] = delay_4
delay[5] = delay_5
delay[6] = delay_6
delay[7] = delay_7
delay[8] = delay_8

# v0.4: the delay fields are plain reals, so a negative value is
# reachable. Formula (part) starting before the buffer truncates the
# voice, so shift the whole set until the earliest entry is at 0. This
# keeps every relative offset, which is what the canon actually is.
minDelay = delay[1]
for i from 2 to 8
    if delay[i] < minDelay
        minDelay = delay[i]
    endif
endfor
delaysShifted = 0
if minDelay < 0
    for i from 1 to 8
        delay[i] = delay[i] - minDelay
    endfor
    delaysShifted = 1
endif

# === Create 8 pitched versions ===
for i from 1 to 8
    selectObject: baseResampledID
    Copy: "v" + string$(i) + "_work"
    vWork = selected("Sound")
    
    # Calculate shift rate from semitones
    ratio = 2 ^ (semi[i] / 12)
    shiftRate = resample_frequency * ratio
    
    Override sampling frequency: shiftRate
    Resample: resample_frequency, 50
    Rename: "canonvoice" + string$(i)
    voice[i] = selected("Sound")
    dur[i] = Get total duration
    
    # v0.4: clamp so fade-in and fade-out cannot overlap on short voices
    fadeUse = fade_time
    if fadeUse > dur[i] / 2
        fadeUse = dur[i] / 2
    endif
    if fadeUse > 0
        Fade in: 0, 0, fadeUse, "yes"
        Fade out: 0, dur[i], -fadeUse, "yes"
    endif
    
    removeObject: vWork
endfor

# === Calculate output duration ===
maxEnd = 0
for i from 1 to 8
    thisEnd = delay[i] + dur[i]
    if thisEnd > maxEnd
        maxEnd = thisEnd
    endif
endfor
outputDur = maxEnd + 0.05

# === Create 8 output channel buffers ===
for i from 1 to 8
    Create Sound from formula: "ch" + string$(i), 1, 0, outputDur, resample_frequency, "0"
    ch[i] = selected("Sound")
endfor

# === Place each voice in its channel with delay ===
for i from 1 to 8
    selectObject: ch[i]
    d = delay[i]
    voiceDur = dur[i]
    
    # v0.4: string$() concatenation instead of backtick interpolation
    voiceName$ = "canonvoice" + string$(i)
    Formula (part): d, d + voiceDur, 1, 1,
        ... "Sound_" + voiceName$ + "(x - " + fixed$(d, 9) + ")"
endfor

# ============================================================
# SHARED-GAIN NORMALISATION
# ============================================================
# One gain for all eight working channels, taken from the loudest of
# them. Every format and every stem inherits it, so switching format
# never changes the level and no stem is boosted relative to another.
# The two summing formats re-normalise their finished object once,
# after the sums exist.

peakAll = 0
for i from 1 to 8
    selectObject: ch[i]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
if peakAll < 1e-9
    peakAll = 1e-9
endif
sharedGain = 0.95 / peakAll
sharedGain$ = fixed$(sharedGain, 10)

for i from 1 to 8
    selectObject: ch[i]
    Formula: "self * " + sharedGain$
endfor

# ============================================================
# BUILD THE CHANNEL TREE
# ============================================================
# The pairwise cascade is kept from v0.2 because every format needs
# some node of it: format 2 takes the four pairs, format 3 the two
# quads, format 5 folds the quads to mono, and the 8-channel node
# feeds both format 1 and the monitoring mix.

selectObject: ch[1], ch[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: ch[3], ch[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: ch[5], ch[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: ch[7], ch[8]
Combine to stereo
pair78 = selected("Sound")

selectObject: pair12, pair34
Combine to stereo
quad1234 = selected("Sound")

selectObject: pair56, pair78
Combine to stereo
quad5678 = selected("Sound")

selectObject: quad1234, quad5678
Combine to stereo
oct = selected("Sound")

# Monitoring mix: all eight voices folded to mono. Used for the
# spectrogram in every format, and auditioned in the stem formats.
selectObject: oct
Convert to mono
monitorID = selected("Sound")
Rename: "canon_monitor"
Scale peak: 0.95

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
# out[1..outCount] is the list of objects the user keeps. Everything
# else built above is an intermediate and is removed below.

if output_format = 1
    # --- 8 channels, octophonic ---
    selectObject: oct
    Rename: originalName$ + "_canon8ch_" + presetName$
    outCount = 1
    out[1] = oct
    outChannels = 8
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

elsif output_format = 2
    # --- 4 stereo pairs ---
    selectObject: pair12
    Rename: originalName$ + "_canon_pair_12_" + presetName$
    selectObject: pair34
    Rename: originalName$ + "_canon_pair_34_" + presetName$
    selectObject: pair56
    Rename: originalName$ + "_canon_pair_56_" + presetName$
    selectObject: pair78
    Rename: originalName$ + "_canon_pair_78_" + presetName$
    outCount = 4
    out[1] = pair12
    out[2] = pair34
    out[3] = pair56
    out[4] = pair78
    outChannels = 2
    removeObject: quad1234, quad5678, oct

elsif output_format = 3
    # --- 2 quadraphonic groups ---
    selectObject: quad1234
    Rename: originalName$ + "_canon_quad_1to4_" + presetName$
    selectObject: quad5678
    Rename: originalName$ + "_canon_quad_5to8_" + presetName$
    outCount = 2
    out[1] = quad1234
    out[2] = quad5678
    outChannels = 4
    removeObject: pair12, pair34, pair56, pair78, oct

elsif output_format = 4
    # --- 4-channel fold-down: V1+V5, V2+V6, V3+V7, V4+V8 ---
    # Voices four apart share a physical channel, so the first turn of
    # the canon (V1-V4) and the second (V5-V8) keep the same channel
    # pattern. Combine + Convert to mono averages the pair; the factor
    # is identical for all four channels, so the balance is untouched
    # and the finished object is normalised once at the end.
    for k from 1 to 4
        selectObject: ch[k], ch[k + 4]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "fold_" + string$(k)
        removeObject: foldPair
    endfor

    selectObject: fold[1], fold[2]
    Combine to stereo
    foldA = selected("Sound")
    selectObject: fold[3], fold[4]
    Combine to stereo
    foldB = selected("Sound")
    selectObject: foldA, foldB
    Combine to stereo
    foldOut = selected("Sound")
    Rename: originalName$ + "_canon_fold4_" + presetName$
    Scale peak: 0.95

    outCount = 1
    out[1] = foldOut
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4], foldA, foldB
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678, oct

else
    # --- Stereo mix: L = V1-V4, R = V5-V8 ---
    # A functional split of the voices into two groups, not a spatial
    # downmix: there is no speaker geometry anywhere in this script.
    selectObject: quad1234
    Convert to mono
    mixL = selected("Sound")
    Rename: "mix_L"
    selectObject: quad5678
    Convert to mono
    mixR = selected("Sound")
    Rename: "mix_R"

    selectObject: mixL, mixR
    Combine to stereo
    stereoOut = selected("Sound")
    Rename: originalName$ + "_canon_stereo_" + presetName$
    Scale peak: 0.95

    outCount = 1
    out[1] = stereoOut
    outChannels = 2
    removeObject: mixL, mixR
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678, oct
endif

# === Info ===
writeInfoLine: "=== 8-Channel Canon ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
for i from 1 to 8
    if semi[i] >= 0
        appendInfoLine: "Voice ", i, ": +", fixed$(semi[i], 1), " st, delay ", fixed$(delay[i], 2), "s"
    else
        appendInfoLine: "Voice ", i, ": ", fixed$(semi[i], 1), " st, delay ", fixed$(delay[i], 2), "s"
    endif
endfor
if delaysShifted = 1
    appendInfoLine: ""
    appendInfoLine: "NOTE: delays contained a negative value and were shifted as a block"
    appendInfoLine: "      by ", fixed$(-minDelay, 2), " s so the earliest entry starts at 0."
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
if output_format = 1
    appendInfoLine: "  Ch1-Ch8: V1 - V8"
elsif output_format = 2
    appendInfoLine: "  Pair 1: V1 -> L, V2 -> R"
    appendInfoLine: "  Pair 2: V3 -> L, V4 -> R"
    appendInfoLine: "  Pair 3: V5 -> L, V6 -> R"
    appendInfoLine: "  Pair 4: V7 -> L, V8 -> R"
elsif output_format = 3
    appendInfoLine: "  Quad 1: V1 V2 V3 V4"
    appendInfoLine: "  Quad 2: V5 V6 V7 V8"
elsif output_format = 4
    appendInfoLine: "  Ch1: V1 + V5"
    appendInfoLine: "  Ch2: V2 + V6"
    appendInfoLine: "  Ch3: V3 + V7"
    appendInfoLine: "  Ch4: V4 + V8"
else
    appendInfoLine: "  L: V1 + V2 + V3 + V4"
    appendInfoLine: "  R: V5 + V6 + V7 + V8"
endif
appendInfoLine: "Normalisation: one shared gain across all eight voices"

# === Cleanup of everything that is not an output ===
removeObject: baseResampledID
for i from 1 to 8
    removeObject: voice[i], ch[i]
endfor

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.95, "half", "##8-Channel Canon v0.4.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + fixed$(outputDur, 2) + " s"
        ... + "  |  Format: " + formatName$

    # ----------------------------------------------------------
    # Canon timeline diagram
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.50, 3.50
    Select inner viewport: 0.55, 7.65, 0.60, 3.40

    Axes: -outputDur * 0.02, outputDur * 1.05, 0, 9
    Paint rectangle: "{0.96, 0.96, 0.96}",
        ... -outputDur * 0.02, outputDur * 1.05, 0, 9

    # Vertical time grid
    Colour: "{0.88, 0.88, 0.88}"
    timeStep = 0.5
    if outputDur > 5
        timeStep = 1.0
    endif
    gridT = timeStep
    while gridT < outputDur
        Draw line: gridT, 0, gridT, 9
        gridT = gridT + timeStep
    endwhile

    # Output-group banding: shows which voices share an output object
    if output_format = 2
        groupSize = 2
    elsif output_format = 3
        groupSize = 4
    elsif output_format = 5
        groupSize = 4
    else
        groupSize = 0
    endif
    if groupSize > 0
        Colour: "{0.90, 0.92, 0.96}"
        gStart = 1
        while gStart <= 8
            if (((gStart - 1) / groupSize) mod 2) = 0
                Paint rectangle: "{0.91, 0.93, 0.97}",
                    ... -outputDur * 0.02, outputDur * 1.05,
                    ... 9 - (gStart + groupSize - 1), 9 - gStart + 1
            endif
            gStart = gStart + groupSize
        endwhile
    endif

    # Draw each channel bar
    for i from 1 to 8
        yPos = 9 - i

        # Colour: warm (positive semitones) / cool (negative)
        if semi[i] >= 0
            cFrac = min(semi[i] / 24, 1)
            cR = 0.40 + cFrac * 0.45
            cG = 0.48 - cFrac * 0.18
            cB = 0.72 - cFrac * 0.45
        else
            cFrac = min(-semi[i] / 24, 1)
            cR = 0.35 - cFrac * 0.10
            cG = 0.48 + cFrac * 0.18
            cB = 0.72 + cFrac * 0.18
        endif
        barCol$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"

        Paint rectangle: barCol$, delay[i], delay[i] + dur[i],
            ... yPos + 0.10, yPos + 0.82

        # Bar outline
        Colour: "{0.40, 0.40, 0.40}"
        Line width: 1
        Draw rectangle: delay[i], delay[i] + dur[i],
            ... yPos + 0.10, yPos + 0.82

        # Label inside bar: channel + semitones + delay
        Font size: 6
        Colour: "White"
        if semi[i] >= 0
            semiLbl$ = "+" + fixed$(semi[i], 1)
        else
            semiLbl$ = fixed$(semi[i], 1)
        endif
        barMidX = delay[i] + dur[i] * 0.5
        barMidY = yPos + 0.46
        # Only draw label if bar is wide enough
        if dur[i] > outputDur * 0.08
            Text: barMidX, "centre", barMidY, "half",
                ... "V" + string$(i) + "  " + semiLbl$ + " st"
        endif

        # Delay label at left edge (outside bar if needed)
        Font size: 6
        Colour: "{0.40, 0.40, 0.40}"
        if delay[i] > outputDur * 0.04
            Text: delay[i] - outputDur * 0.01, "right", barMidY, "half",
                ... fixed$(delay[i], 2) + "s"
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    tlNote$ = "Canon timeline  (colour = pitch direction,  warm = up,  cool = down"
    if groupSize > 0
        tlNote$ = tlNote$ + ",  bands = output grouping"
    endif
    tlNote$ = tlNote$ + ")"
    Text top: "no", tlNote$

    # Voice labels on left, with the output routing they receive
    for i from 1 to 8
        yPos = 9 - i
        Font size: 6
        Colour: "{0.35, 0.35, 0.35}"
        # Kept to about five characters: this sits in the 0.55 inch
        # margin left of the inner viewport, so a long label would clip.
        if output_format = 1
            routeLbl$ = string$(i) + ">c" + string$(i)
        elsif output_format = 2
            if i mod 2 = 1
                routeLbl$ = string$(i) + ">P" + string$((i + 1) / 2) + "L"
            else
                routeLbl$ = string$(i) + ">P" + string$(i / 2) + "R"
            endif
        elsif output_format = 3
            if i <= 4
                routeLbl$ = string$(i) + ">Q1"
            else
                routeLbl$ = string$(i) + ">Q2"
            endif
        elsif output_format = 4
            if i <= 4
                routeLbl$ = string$(i) + ">c" + string$(i)
            else
                routeLbl$ = string$(i) + ">c" + string$(i - 4)
            endif
        else
            if i <= 4
                routeLbl$ = string$(i) + ">L"
            else
                routeLbl$ = string$(i) + ">R"
            endif
        endif
        Text: -outputDur * 0.015, "right", yPos + 0.46, "half", routeLbl$
    endfor

    # ----------------------------------------------------------
    # Spectrogram of the monitoring mix (all eight voices)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.78, 5.08
    Select inner viewport: 0.55, 7.65, 3.85, 5.00

    # v0.4: built from the monitoring mix, not from an output object.
    # In a stem format the first output holds a quarter or a half of the
    # canon, so drawing it would show part of the piece as the whole.
    selectObject: monitorID
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specMix = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specMix

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 3.78, 5.08
    Select inner viewport: 0.08, 0.52, 3.80, 5.06
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Hz"
    Select outer viewport: 0, 8, 3.78, 5.08
    Select inner viewport: 0.55, 7.65, 3.85, 5.00
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Canon spectrogram  (mono monitoring mix of all 8 voices)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.28, 6.58
    Select inner viewport: 0.55, 7.65, 5.34, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.94, "half", "##Summary##"

    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Build compact interval list
    intList$ = ""
    for i from 1 to 8
        if i > 1
            intList$ = intList$ + "  "
        endif
        if semi[i] >= 0
            intList$ = intList$ + "+" + fixed$(semi[i], 1)
        else
            intList$ = intList$ + fixed$(semi[i], 1)
        endif
    endfor

    # Build compact delay list
    delList$ = ""
    for i from 1 to 8
        if i > 1
            delList$ = delList$ + "  "
        endif
        delList$ = delList$ + fixed$(delay[i], 2)
    endfor

    # Mapping line
    if output_format = 1
        mapLine$ = "ch1-ch8 = V1-V8"
    elsif output_format = 2
        mapLine$ = "V1|V2   V3|V4   V5|V6   V7|V8"
    elsif output_format = 3
        mapLine$ = "quad 1 = V1-V4    quad 2 = V5-V8"
    elsif output_format = 4
        mapLine$ = "ch1=V1+V5   ch2=V2+V6   ch3=V3+V7   ch4=V4+V8"
    else
        mapLine$ = "L = V1+V2+V3+V4    R = V5+V6+V7+V8"
    endif

    Text: 0.02, "left", 0.72, "half",
        ... "Preset: " + presetName$
        ... + "  |  Source: " + originalName$
        ... + "  |  Duration: " + fixed$(outputDur, 2) + " s"
    Text: 0.02, "left", 0.52, "half",
        ... "Semitones:  " + intList$
    Text: 0.02, "left", 0.32, "half",
        ... "Delays (s): " + delList$
    Text: 0.02, "left", 0.12, "half",
        ... "Format: " + formatName$
        ... + "  |  " + string$(outCount) + " object"
        ... + " x " + string$(outChannels) + " ch"
        ... + "  |  " + mapLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 6.68
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel, ",
        ... fixed$(outputDur, 2), "s"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels,
        ... "-channel each, ", fixed$(outputDur, 2), "s"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        # v0.4: playing out[1] alone would present a quarter or a half of
        # the canon as the result. The monitoring mix is auditioned
        # instead, and labelled as a preview rather than a deliverable.
        appendInfoLine: ""
        appendInfoLine: "Playback: mono preview downmix of all 8 voices."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

removeObject: monitorID

# === Select the output object(s) for the user ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
