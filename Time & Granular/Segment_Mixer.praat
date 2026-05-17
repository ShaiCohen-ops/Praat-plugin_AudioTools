# ============================================================
# Praat AudioTools - Segment_Mixer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Segment Mixer - creates stereo composites from multiple
#   selected Sound objects. LEFT channel uses beginning segments,
#   RIGHT channel uses end / offset / random segments. Supports
#   multiple repeat cycles for longer compositions.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#
#   TIER 1 (Praat polish):
#     - Dropped 4 decorative `comment === ... ===` form rows
#       (Preset, Segment, Right Channel Strategy, Output).
#       Form: 12 rows -> 8 rows. The "Select multiple Sound
#       objects first" instruction is kept (actionable info).
#     - Added colons to `optionmenu Preset` and
#       `optionmenu Right_part_strategy` for consistency with
#       the rest of the AudioTools suite.
#     - Fixed title viewport bug at line 350 of v0.2:
#       `Select outer viewport: 1, 8, ...` -> `0, 8, ...`
#       (asymmetric placement -> centered).
#     - Visualization rewritten from custom 6-panel layout to
#       suite 8x8 standard:
#         Title bar (suite light) + metadata subtitle
#         Panel A (left, headline): L segment map
#         Panel B (right, headline): R segment map
#         Panel C: Output stereo waveform
#         Panel D: File color legend with actual file names
#         Panel E: light-grey summary stats bar (suite standard)
#     - Restored actual file names in the legend. v0.2 had a
#       fallback "File 1", "File 2", ... because of a comment
#       claiming names were removed with objects; in fact
#       `soundNames$#` survives the monoSounds cleanup, so the
#       real names display now.
#     - Fixed color hue wrap-around: v0.2 computed
#       hue = (i-1) / (N-1), giving hue=0 for the first file
#       and hue=1 for the last, which are the same point on
#       sin(2*pi*hue) -- so first and last files got identical
#       colors. v0.3 uses hue = (i-1) / N, so hue ranges
#       0 .. (N-1)/N and no two files collide.
#
#   TIER 2 (small correctness):
#     - Fade clamp (AUDIO CHANGE for edge case): when a source
#       file is shorter than 2 * fade_time_s, v0.2 fell through
#       to an else branch that applied attenuation only -- no
#       fade -- producing click artifacts at segment boundaries.
#       v0.3 clamps effFade = min(fade_time_s, extractDuration / 2)
#       and always applies a fade. For files longer than
#       2 * fade_time_s (the common case) effFade == fade_time_s
#       and audio is bit-identical to v0.2. Only short files get
#       different audio (now click-free).
#     - Output filename suffix:
#       `stereo_mix_<N>files_<C>x`
#         -> `stereo_mix_<N>files_<C>x_<preset>_<strategy>`
#       so multiple runs with different settings don't silently
#       overwrite each other.
#     - Original selection re-applied at end. v0.2 captured
#       `originalSounds#` but never re-selected; v0.3 selects
#       the result plus the original inputs so the user can
#       continue working from a sensible selection state.
#
# Changelog v0.2:
#   - Fixed header
#   - Added presets
#   - Added visualization
# ============================================================

form Segment Mixer v0.3
    comment Select multiple Sound objects first
    optionmenu Preset: 1
        option Custom
        option Quick Collage (short segments)
        option Slow Morph (long segments)
        option Random Scatter
        option Stereo Spread (L=start, R=end)
        option Dense Layers (many cycles)
    positive Segment_duration_s 0.25
    real Fade_time_s 0.05
    positive Attenuation_divisor 1.1
    integer Repeat_cycles 3
    optionmenu Right_part_strategy: 1
        option End of file
        option Fixed offset
        option Random
    real Right_fixed_offset_s 0.10
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Quick Collage
    segment_duration_s = 0.15
    fade_time_s = 0.03
    attenuation_divisor = 1.2
    repeat_cycles = 4
    right_part_strategy = 3
    right_fixed_offset_s = 0.1
    presetName$ = "QuickCollage"
elsif preset = 3
    # Slow Morph
    segment_duration_s = 0.5
    fade_time_s = 0.1
    attenuation_divisor = 1.0
    repeat_cycles = 2
    right_part_strategy = 1
    right_fixed_offset_s = 0.1
    presetName$ = "SlowMorph"
elsif preset = 4
    # Random Scatter
    segment_duration_s = 0.2
    fade_time_s = 0.04
    attenuation_divisor = 1.3
    repeat_cycles = 5
    right_part_strategy = 3
    right_fixed_offset_s = 0.1
    presetName$ = "RandomScatter"
elsif preset = 5
    # Stereo Spread
    segment_duration_s = 0.3
    fade_time_s = 0.05
    attenuation_divisor = 1.1
    repeat_cycles = 3
    right_part_strategy = 1
    right_fixed_offset_s = 0.1
    presetName$ = "StereoSpread"
elsif preset = 6
    # Dense Layers
    segment_duration_s = 0.1
    fade_time_s = 0.02
    attenuation_divisor = 1.5
    repeat_cycles = 8
    right_part_strategy = 3
    right_fixed_offset_s = 0.1
    presetName$ = "DenseLayers"
else
    presetName$ = "Custom"
endif

# === Input Validation ===
numberOfSelectedSounds = numberOfSelected("Sound")

if numberOfSelectedSounds = 0
    exitScript: "Please select some Sound objects first."
endif
if numberOfSelectedSounds < 2
    exitScript: "Please select at least two Sound objects."
endif
if fade_time_s <= 0
    exitScript: "Fade time must be positive."
endif
if fade_time_s > segment_duration_s / 2
    exitScript: "Fade time cannot exceed half the segment duration."
endif
if repeat_cycles < 1
    exitScript: "Repeat cycles must be at least 1."
endif
if right_part_strategy = 2 and right_fixed_offset_s < 0
    exitScript: "Right fixed offset must be >= 0."
endif

# === Get Strategy Name ===
if right_part_strategy = 1
    strategyName$ = "End"
elsif right_part_strategy = 2
    strategyName$ = "Offset"
else
    strategyName$ = "Random"
endif

# === Info ===
writeInfoLine: "=== Segment Mixer v0.3 ==="
appendInfoLine: "Files:     ", numberOfSelectedSounds
appendInfoLine: "Preset:    ", presetName$
appendInfoLine: "Segment:   ", fixed$(segment_duration_s, 3), " s"
appendInfoLine: "Fade:      ", fixed$(fade_time_s * 1000, 0), " ms"
appendInfoLine: "Atten:     /", fixed$(attenuation_divisor, 2)
appendInfoLine: "Cycles:    ", repeat_cycles
appendInfoLine: "R strategy:", strategyName$
appendInfoLine: ""

# === Store Original Selection ===
originalSounds# = selected#("Sound")

# === Convert All to Mono ===
monoSounds# = zero#(numberOfSelectedSounds)
soundNames$# = empty$#(numberOfSelectedSounds)

for i to numberOfSelectedSounds
    selectObject: originalSounds#[i]
    soundNames$#[i] = selected$("Sound")
    numChannels = Get number of channels

    Copy: "mono_work_" + string$(i)
    workID = selected("Sound")

    if numChannels > 1
        Convert to mono
        monoID = selected("Sound")
        removeObject: workID
        monoSounds#[i] = monoID
    else
        monoSounds#[i] = workID
    endif
endfor

# === Normalise Sampling Frequency ===
# Use the first sound's sampling frequency as the target for all sounds and buffers.
selectObject: monoSounds#[1]
targetSR = Get sampling frequency

for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    sr_i = Get sampling frequency
    if sr_i <> targetSR
        Resample: targetSR, 50
        resampledID = selected("Sound")
        removeObject: monoSounds#[i]
        monoSounds#[i] = resampledID
        selectObject: monoSounds#[i]
        Rename: "mono_work_" + string$(i)
    endif
endfor

appendInfoLine: "Target SR: ", fixed$(targetSR, 0), " Hz"
appendInfoLine: "Processing files:"
for i to numberOfSelectedSounds
    selectObject: monoSounds#[i]
    dur = Get total duration
    appendInfoLine: "  ", i, ": ", soundNames$#[i], " (", fixed$(dur, 2), " s)"
endfor
appendInfoLine: ""

# === Create Initial Buffers ===
Create Sound from formula: "temp_left", 1, 0, 0.01, targetSR, "0"
leftID = selected("Sound")

Create Sound from formula: "temp_right", 1, 0, 0.01, targetSR, "0"
rightID = selected("Sound")

# === Store Segment Info for Visualization ===
maxSegments = numberOfSelectedSounds * repeat_cycles
leftStarts# = zero#(maxSegments)
leftEnds# = zero#(maxSegments)
rightStarts# = zero#(maxSegments)
rightEnds# = zero#(maxSegments)
segmentFile# = zero#(maxSegments)
segmentIdx = 0

# === Main Processing Loop ===
appendInfoLine: "Building composite..."

for cycle to repeat_cycles
    for i to numberOfSelectedSounds
        selectObject: monoSounds#[i]
        total_duration = Get total duration

        # Determine extract duration
        if segment_duration_s > total_duration
            extractDuration = total_duration
        else
            extractDuration = segment_duration_s
        endif

        # v0.3: clamp effective fade so it always fits the segment.
        # v0.2 fell through to an else branch with NO fade when a file
        # was shorter than 2 * fade_time_s -- producing clicks at
        # segment boundaries on short inputs. For inputs longer than
        # 2 * fade_time_s (the common case), effFade == fade_time_s
        # and audio is bit-identical to v0.2.
        effFade = fade_time_s
        if effFade > extractDuration / 2
            effFade = extractDuration / 2
        endif

        # === LEFT SEGMENT (from start) ===
        leftStart = 0
        leftEnd = leftStart + extractDuration
        if leftEnd > total_duration
            leftEnd = total_duration
        endif

        Extract part: leftStart, leftEnd, "rectangular", 1, "no"
        leftSeg = selected("Sound")

        # Apply attenuation + fade (always with effFade)
        selectObject: leftSeg
        Formula: "self / attenuation_divisor"
        Formula: "self * min(1, x / effFade)"
        Formula: "self * min(1, (xmax - x) / effFade)"

        # Concatenate to left channel
        selectObject: leftID, leftSeg
        Concatenate
        newLeft = selected("Sound")
        removeObject: leftID, leftSeg
        leftID = newLeft
        selectObject: leftID
        Rename: "temp_left"

        # === RIGHT SEGMENT (based on strategy) ===
        if right_part_strategy = 1
            # End of file
            rightEnd = total_duration
            rightStart = rightEnd - extractDuration
            if rightStart < 0
                rightStart = 0
            endif
        elsif right_part_strategy = 2
            # Fixed offset
            rightStart = right_fixed_offset_s
            if rightStart > total_duration - extractDuration
                rightStart = total_duration - extractDuration
            endif
            if rightStart < 0
                rightStart = 0
            endif
        else
            # Random
            usableWindow = total_duration - extractDuration
            if usableWindow <= 0
                rightStart = 0
            else
                rightStart = randomUniform(0, usableWindow)
            endif
        endif

        rightEnd = rightStart + extractDuration
        if rightEnd > total_duration
            rightEnd = total_duration
            rightStart = rightEnd - extractDuration
            if rightStart < 0
                rightStart = 0
            endif
        endif

        selectObject: monoSounds#[i]
        Extract part: rightStart, rightEnd, "rectangular", 1, "no"
        rightSeg = selected("Sound")

        # Apply attenuation + fade (always with effFade)
        selectObject: rightSeg
        Formula: "self / attenuation_divisor"
        Formula: "self * min(1, x / effFade)"
        Formula: "self * min(1, (xmax - x) / effFade)"

        # Concatenate to right channel
        selectObject: rightID, rightSeg
        Concatenate
        newRight = selected("Sound")
        removeObject: rightID, rightSeg
        rightID = newRight
        selectObject: rightID
        Rename: "temp_right"

        # Store for visualization
        segmentIdx += 1
        leftStarts#[segmentIdx] = leftStart
        leftEnds#[segmentIdx] = leftEnd
        rightStarts#[segmentIdx] = rightStart
        rightEnds#[segmentIdx] = rightEnd
        segmentFile#[segmentIdx] = i
    endfor

    appendInfoLine: "  Cycle ", cycle, " complete"
endfor

totalSegments = segmentIdx

# === Finalize ===
selectObject: leftID
Scale peak: 0.99

selectObject: rightID
Scale peak: 0.99

selectObject: leftID, rightID
Combine to stereo
result = selected("Sound")

# v0.3: output filename now includes preset + R-strategy suffix.
compositeName$ = "stereo_mix_" + string$(numberOfSelectedSounds) + "files_"
    ... + string$(repeat_cycles) + "x_"
    ... + presetName$ + "_" + strategyName$
Rename: compositeName$

selectObject: result
finalDuration = Get total duration
rms_out = Get root-mean-square: 0, 0

# === Cleanup of working buffers (keep result + soundNames$#) ===
removeObject: leftID, rightID

for i to numberOfSelectedSounds
    if monoSounds#[i] > 0
        removeObject: monoSounds#[i]
    endif
endfor

###############################################################################
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: L segment map  (left, headline)
# Panel B: R segment map  (right, headline)
# Panel C: Output stereo waveform
# Panel D: File color legend with names
# Panel E: light-grey summary stats bar
###############################################################################

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SEGMENT MIXER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... string$(numberOfSelectedSounds) + " files x " + string$(repeat_cycles) + " cycles"
        ... + "  |  " + presetName$
        ... + "  |  Seg " + fixed$(segment_duration_s * 1000, 0) + " ms"
        ... + "  |  Fade " + fixed$(fade_time_s * 1000, 0) + " ms"
        ... + "  |  R: " + strategyName$

    # ----------------------------------------------------------
    # PANEL A: LEFT SEGMENT MAP  (left, headline)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    Axes: 0, totalSegments, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalSegments, 0, 1

    for s to totalSegments
        fileIdx = segmentFile#[s]
        if fileIdx >= 1 and fileIdx <= numberOfSelectedSounds
            # v0.3: hue ranges 0..(N-1)/N instead of 0..1, so no
            # wrap-around (first and last files no longer collide).
            hue = (fileIdx - 1) / numberOfSelectedSounds
            r = 0.3 + 0.5 * sin(hue * 2 * pi)
            g = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            b = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            Paint rectangle: barColor$, s - 0.9, s - 0.1, 0.1, 0.9
        endif
    endfor

    # Cycle dividers (light vertical lines between cycles)
    if repeat_cycles > 1
        Colour: "{0.65, 0.65, 0.70}"
        Line width: 1
        for cyc from 1 to repeat_cycles - 1
            xDiv = cyc * numberOfSelectedSounds
            Draw line: xDiv, 0, xDiv, 1
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Segment #"

    # ----------------------------------------------------------
    # PANEL B: RIGHT SEGMENT MAP  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, totalSegments, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalSegments, 0, 1

    for s to totalSegments
        fileIdx = segmentFile#[s]
        if fileIdx >= 1 and fileIdx <= numberOfSelectedSounds
            hue = (fileIdx - 1) / numberOfSelectedSounds
            r = 0.3 + 0.5 * sin(hue * 2 * pi)
            g = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
            b = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
            barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            Paint rectangle: barColor$, s - 0.9, s - 0.1, 0.1, 0.9
        endif
    endfor

    if repeat_cycles > 1
        Colour: "{0.65, 0.65, 0.70}"
        Line width: 1
        for cyc from 1 to repeat_cycles - 1
            xDiv = cyc * numberOfSelectedSounds
            Draw line: xDiv, 0, xDiv, 1
        endfor
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Segment #"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES  (above A and B)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Left channel  (start segments)"
    Text: 6.10, "centre", 7.30, "half", "Right channel  (" + strategyName$ + " segments)"

    # ----------------------------------------------------------
    # PANEL C: OUTPUT STEREO WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    selectObject: result
    Colour: "{0.30, 0.50, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output stereo waveform  (" + fixed$(finalDuration, 2) + " s)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: FILE COLOR LEGEND  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, numberOfSelectedSounds, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numberOfSelectedSounds, 0, 1

    for i to numberOfSelectedSounds
        hue = (i - 1) / numberOfSelectedSounds
        r = 0.3 + 0.5 * sin(hue * 2 * pi)
        g = 0.3 + 0.5 * sin(hue * 2 * pi + 2)
        b = 0.3 + 0.5 * sin(hue * 2 * pi + 4)
        barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"

        # Color swatch
        Paint rectangle: barColor$, i - 0.9, i - 0.4, 0.55, 0.85

        # v0.3: actual file name (truncated to fit). soundNames$# was
        # preserved across the monoSounds cleanup, so we can show real
        # names instead of v0.2's "File 1", "File 2", ... fallback.
        rawName$ = soundNames$#[i]
        # Truncate long names to fit panel width
        if length(rawName$) > 14
            displayName$ = left$(rawName$, 12) + ".."
        else
            displayName$ = rawName$
        endif

        Colour: "Black"
        Font size: 6
        Text: i - 0.65, "centre", 0.30, "half", displayName$
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "File color legend"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + string$(numberOfSelectedSounds) + " files x " + string$(repeat_cycles) + " cycles"
        ... + "  =  " + string$(totalSegments) + " segments"
        ... + "  |  R-strategy: " + strategyName$

    Text: 0.02, "left", 0.50, "half",
        ... "Segment: " + fixed$(segment_duration_s * 1000, 0) + " ms"
        ... + "  |  Fade: " + fixed$(fade_time_s * 1000, 0) + " ms"
        ... + "  |  Attenuation: /" + fixed$(attenuation_divisor, 2)
        ... + "  |  SR: " + fixed$(targetSR / 1000, 1) + " kHz"

    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  Duration: " + fixed$(finalDuration, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", compositeName$
appendInfoLine: "Duration:  ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Segments:  ", totalSegments
appendInfoLine: "RMS:       ", fixed$(rms_out, 6)

# === Play ===
if play_result
    selectObject: result
    Play
endif

# v0.3: restore a sensible selection state for the user. v0.2 only
# selected `result`, leaving originals deselected. v0.3 selects the
# result plus the originals so the user can continue working without
# manually re-selecting their source sounds.
selectObject: result
for i to numberOfSelectedSounds
    plusObject: originalSounds#[i]
endfor
