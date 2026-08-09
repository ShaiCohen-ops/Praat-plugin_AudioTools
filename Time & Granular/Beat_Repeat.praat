# ============================================================
# Praat AudioTools - Beat_Repeat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Beat Repeat effect - extracts a rhythmically-aligned segment
#   and repeats it with optional amplitude decay. Classic DJ/
#   production tool for stutters, fills, and glitch effects.
#
# v0.3 adds SILENCE-AWARE beat selection: the script pre-scans
# every beat for RMS energy, marks beats below a configurable
# threshold as silent, and avoids them when picking the source
# segment to repeat. Each mode handles silence differently:
#   - Specific beat: shifts outward (+/- offsets) to the nearest
#     non-silent beat if the requested one is silent
#   - Random beat: picks uniformly from non-silent beats only
#   - Beat range: finds the first non-silent beat WITHIN the
#     range as the source (replacement target stays the user's
#     specified range — only the source shifts)
#   - Auto: searches forward first (then backward as fallback)
#     from the 1-second mark for the first non-silent beat
#
# Algorithmic note (v0.4):
#   Beat Repeat now extracts the source slice RECTANGULARLY so
#   the repeated audio preserves its attack and spectral content.
#   The optional Fade_repeats control applies only short edge
#   fades; it no longer sits on top of a full-duration Hann
#   window. This gives the stutter presets the crisp character
#   expected from a beat-repeat effect while retaining a smooth
#   option for slower repeats.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - DSP: source slice extraction changed from full-duration
#     Hanning to rectangular. The old Hann window attenuated both
#     ends of every repeated slice and produced soft "puffs"
#     instead of a crisp DJ-style repeat. Fade_repeats remains
#     available for short click-reducing edge fades.
#   - FIXED non-zero Sound time domains. All analysis/extraction
#     queries now use absolute source time; assembled output and
#     visualization remain zero-based.
#   - Selection now counts only rhythmically aligned beat starts
#     from which the complete chosen note duration fits. This
#     prevents late selections from being silently shifted
#     backwards off the beat grid.
#   - Added validation for BPM, repeat count, amplitude decay,
#     fade duration, and note duration versus source duration.
#   - Silence diagnostic wording now says "candidate slice"
#     because RMS is measured over the actual repeat-slice length,
#     not over an entire quarter-note beat.
#   - Visualization normalizes a shifted/non-zero-domain source
#     copy to a zero-based time domain before drawing.
#
# Changelog v0.3:
#   - Audio output is bit-identical to v0.2 when
#     Skip_silence = 0. Same Hann-windowed extract, same
#     amplitude decay (decay^k), same Concatenate-based
#     repeat assembly, same fade_repeats logic, same 7
#     presets with same values.
#   - NEW: Silence-aware beat selection (Skip_silence default
#     1). When ON, audio may differ from v0.2 in cases where
#     v0.2 would have picked a silent beat. For non-silent
#     inputs (or with Skip_silence = 0), output is identical.
#   - NEW: Silence_threshold_dB form field (default -40 dB).
#     Beats with RMS below this threshold are considered
#     silent. Common values: -30 (strict), -40 (balanced),
#     -50 (lenient).
#   - Output filename includes preset name suffix:
#     `<name>_beatRepeat_<presetName>` (was just
#     `<name>_beatRepeat`).
#   - Form syntax modernized: 3 optionmenus with colons
#     (Preset, Note_value, Beat_selection_mode).
#   - Dropped 7 decorative form lines (5 `comment === ... ===`
#     section dividers, 1 instructional, 1 inline parenthetical).
#     Form went from 19 effective rows to 13 (plus 2 new fields,
#     net 15).
#   - Visualization rewritten to suite 8x8 standard (v0.2 was
#     8x4.8 with title + 2 unconsolidated waveforms + legend):
#       Title bar + metadata subtitle (preset, BPM, note value,
#         mode, beat info, silence stats)
#       Panel A (left, headline): beat energy bar chart — the
#         silence diagnostic. One bar per beat, height = RMS-dB.
#         Color-coded: blue (non-silent), light gray (silent).
#         Selected beat highlighted with orange outline. Red
#         dashed line at silence threshold. Range mode also
#         marks the range bounds.
#       Panel B (right, headline): parameter report with mode,
#         shift info, silence stats, repeat parameters
#       Panel C: zoom centered on the repeated section
#         (gray = original, blue = result, SHARED y-axis)
#       Panel D: full waveform comparison (gray = original,
#         blue = result, SHARED y-axis)
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Fixed fade out position
#   - Added visualization
#   - Added play option
#   - Added presets
# ============================================================

form Beat Repeat v0.4
    optionmenu Preset: 1
        option Custom
        option Stutter 1/16
        option Fast Stutter 1/32
        option Slow Repeat 1/4
        option Triplet Fill
        option Decaying Echo
        option Glitch Burst
    real Bpm 120
    optionmenu Note_value: 2
        option 1/32
        option 1/16
        option 1/8
        option 1/4
        option 1/2
        option 1/16 triplet
        option 1/8 triplet
        option 1/4 triplet
        option dotted 1/16
        option dotted 1/8
        option dotted 1/4
        option dotted 1/2
    optionmenu Beat_selection_mode: 1
        option Specific beat number
        option Random beat
        option Beat range
        option Auto (1 second in)
    integer Specific_beat 4
    integer Beat_range_start 2
    integer Beat_range_end 4
    integer Num_repeats 4
    real Amplitude_decay 0.9
    boolean Skip_silence 1
    real Silence_threshold_dB -40
    boolean Fade_repeats 0
    real Fade_duration_s 0.01
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
presetName$ = "Custom"

if preset = 2
    note_value = 2
    num_repeats = 4
    amplitude_decay = 1.0
    fade_repeats = 0
    presetName$ = "Stutter16"
elsif preset = 3
    note_value = 1
    num_repeats = 8
    amplitude_decay = 1.0
    fade_repeats = 0
    presetName$ = "FastStutter32"
elsif preset = 4
    note_value = 4
    num_repeats = 4
    amplitude_decay = 0.85
    fade_repeats = 1
    fade_duration_s = 0.02
    presetName$ = "SlowRepeat4"
elsif preset = 5
    note_value = 7
    num_repeats = 6
    amplitude_decay = 0.95
    fade_repeats = 0
    presetName$ = "TripletFill"
elsif preset = 6
    note_value = 3
    num_repeats = 8
    amplitude_decay = 0.7
    fade_repeats = 1
    fade_duration_s = 0.01
    presetName$ = "DecayingEcho"
elsif preset = 7
    note_value = 1
    num_repeats = 16
    amplitude_decay = 0.95
    fade_repeats = 0
    presetName$ = "GlitchBurst"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sourceStart = Get start time
sourceEnd = Get end time
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Validate ===
if bpm <= 0
    exitScript: "BPM must be > 0"
endif
if num_repeats < 1
    exitScript: "Number of repeats must be at least 1"
endif
if num_repeats > 512
    exitScript: "Number of repeats must not exceed 512"
endif
if amplitude_decay < 0 or amplitude_decay > 1
    exitScript: "Amplitude decay must be between 0 and 1"
endif
if fade_duration_s < 0
    exitScript: "Fade duration must be >= 0"
endif

# === Calculate Timing ===
secondsPerBeat = 60 / bpm

# Note duration
if note_value = 1
    noteDuration = secondsPerBeat / 8
    note_name$ = "1/32"
elsif note_value = 2
    noteDuration = secondsPerBeat / 4
    note_name$ = "1/16"
elsif note_value = 3
    noteDuration = secondsPerBeat / 2
    note_name$ = "1/8"
elsif note_value = 4
    noteDuration = secondsPerBeat
    note_name$ = "1/4"
elsif note_value = 5
    noteDuration = secondsPerBeat * 2
    note_name$ = "1/2"
elsif note_value = 6
    noteDuration = (secondsPerBeat / 4) * (2/3)
    note_name$ = "1/16 triplet"
elsif note_value = 7
    noteDuration = (secondsPerBeat / 2) * (2/3)
    note_name$ = "1/8 triplet"
elsif note_value = 8
    noteDuration = secondsPerBeat * (2/3)
    note_name$ = "1/4 triplet"
elsif note_value = 9
    noteDuration = secondsPerBeat / 4 * 1.5
    note_name$ = "dotted 1/16"
elsif note_value = 10
    noteDuration = secondsPerBeat / 2 * 1.5
    note_name$ = "dotted 1/8"
elsif note_value = 11
    noteDuration = secondsPerBeat * 1.5
    note_name$ = "dotted 1/4"
elsif note_value = 12
    noteDuration = secondsPerBeat * 2 * 1.5
    note_name$ = "dotted 1/2"
endif

if noteDuration > duration
    exitScript: "The selected note value (" + note_name$ + ", " + fixed$(noteDuration, 3) + " s) is longer than the source Sound (" + fixed$(duration, 3) + " s)"
endif

# Count only beat-grid starts from which the complete slice fits.
totalBeats = floor((duration - noteDuration) / secondsPerBeat) + 1
if totalBeats < 1
    totalBeats = 1
endif

# === Info ===
writeInfoLine: "=== Beat Repeat v0.4 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "BPM: ", bpm, " | Valid beat starts: ", totalBeats
appendInfoLine: "Note value: ", note_name$, " (", fixed$(noteDuration * 1000, 1), " ms)"
appendInfoLine: ""

# ============================================================
# SILENCE DETECTION — pre-scan all candidate slices
# ============================================================
appendInfoLine: "Scanning beats for silence..."

silence_thresh_lin = 10 ^ (silence_threshold_dB / 20)

beatRMS# = zero#(totalBeats)
beatRMSdB# = zero#(totalBeats)
beatSilent# = zero#(totalBeats)

silentCount = 0

selectObject: sound
for b from 1 to totalBeats
    outT1 = (b - 1) * secondsPerBeat
    outT2 = outT1 + noteDuration
    t1 = sourceStart + outT1
    t2 = sourceStart + outT2
    
    if outT2 - outT1 < 0.001
        beatRMS#[b] = 0
        beatRMSdB#[b] = -120
        beatSilent#[b] = 1
        silentCount = silentCount + 1
    else
        rms = Get root-mean-square: t1, t2
        if rms = undefined
            rms = 0
        endif
        if rms < 1e-12
            rms = 1e-12
        endif
        beatRMS#[b] = rms
        beatRMSdB#[b] = 20 * log10(rms)
        if rms < silence_thresh_lin
            beatSilent#[b] = 1
            silentCount = silentCount + 1
        else
            beatSilent#[b] = 0
        endif
    endif
endfor

nonSilentCount = totalBeats - silentCount
appendInfoLine: "  Silent candidate slices: ", silentCount, "/", totalBeats, " (threshold: ", silence_threshold_dB, " dB re 1.0)"

# ============================================================
# BEAT SELECTION (silence-aware)
# ============================================================

# Track what was requested vs what was used (for reporting)
shiftReport$ = ""

if beat_selection_mode = 1
    # ----- Specific beat -----
    requestedBeat = specific_beat
    if requestedBeat < 1
        requestedBeat = 1
    endif
    if requestedBeat > totalBeats
        requestedBeat = totalBeats
    endif
    
    selectedBeat = requestedBeat
    
    if skip_silence and beatSilent#[selectedBeat] = 1
        # Search outward: try +1, -1, +2, -2, ...
        found = 0
        for offset from 1 to totalBeats
            if found = 0
                cand = requestedBeat + offset
                if cand >= 1 and cand <= totalBeats
                    if beatSilent#[cand] = 0
                        selectedBeat = cand
                        found = 1
                    endif
                endif
            endif
            if found = 0
                cand = requestedBeat - offset
                if cand >= 1 and cand <= totalBeats
                    if beatSilent#[cand] = 0
                        selectedBeat = cand
                        found = 1
                    endif
                endif
            endif
        endfor
        
        if found
            shiftReport$ = "requested #" + string$(requestedBeat) + " was silent, shifted to #" + string$(selectedBeat) + " (offset " + string$(selectedBeat - requestedBeat) + ")"
            appendInfoLine: "  Specific beat: ", shiftReport$
        else
            shiftReport$ = "all beats silent; using #" + string$(requestedBeat)
            appendInfoLine: "  Specific beat: ", shiftReport$
        endif
    else
        shiftReport$ = "#" + string$(selectedBeat)
        appendInfoLine: "Mode: Specific beat #", selectedBeat
    endif
    
elsif beat_selection_mode = 2
    # ----- Random beat -----
    if skip_silence and nonSilentCount > 0
        # Pick uniformly from non-silent beats
        target = randomInteger(1, nonSilentCount)
        idx = 0
        chosen = 0
        for b from 1 to totalBeats
            if beatSilent#[b] = 0
                idx = idx + 1
                if idx = target and chosen = 0
                    selectedBeat = b
                    chosen = 1
                endif
            endif
        endfor
        requestedBeat = selectedBeat
        shiftReport$ = "picked #" + string$(selectedBeat) + " from " + string$(nonSilentCount) + " non-silent beats"
        appendInfoLine: "  Random beat: ", shiftReport$
    else
        # v0.2 behavior: random in [2, totalBeats-1] avoiding first/last
        if totalBeats > 2
            selectedBeat = randomInteger(2, totalBeats - 1)
        else
            selectedBeat = 1
        endif
        requestedBeat = selectedBeat
        shiftReport$ = "#" + string$(selectedBeat) + " (no silence skip)"
        appendInfoLine: "Mode: Random beat #", selectedBeat
    endif
    
elsif beat_selection_mode = 3
    # ----- Beat range -----
    rangeStart = max(1, min(totalBeats, beat_range_start))
    rangeEnd = max(1, min(totalBeats, beat_range_end))
    if rangeStart > rangeEnd
        temp = rangeStart
        rangeStart = rangeEnd
        rangeEnd = temp
    endif
    
    requestedBeat = rangeStart
    selectedBeat = rangeStart
    
    if skip_silence
        # Find first non-silent in [rangeStart, rangeEnd]
        found = 0
        for b from rangeStart to rangeEnd
            if found = 0 and beatSilent#[b] = 0
                selectedBeat = b
                found = 1
            endif
        endfor
        
        if found
            if selectedBeat = rangeStart
                shiftReport$ = "range [" + string$(rangeStart) + "-" + string$(rangeEnd) + "], source #" + string$(selectedBeat) + " (range start)"
            else
                shiftReport$ = "range [" + string$(rangeStart) + "-" + string$(rangeEnd) + "], source #" + string$(selectedBeat) + " (first non-silent in range)"
            endif
            appendInfoLine: "  Beat range: ", shiftReport$
        else
            shiftReport$ = "range [" + string$(rangeStart) + "-" + string$(rangeEnd) + "] all silent; using #" + string$(rangeStart)
            appendInfoLine: "  Beat range: ", shiftReport$
        endif
    else
        shiftReport$ = "range [" + string$(rangeStart) + "-" + string$(rangeEnd) + "], source #" + string$(rangeStart)
        appendInfoLine: "Mode: Beat range #", rangeStart, " to #", rangeEnd
    endif
    
else
    # ----- Auto mode (1 second in) -----
    autoStartTime = 1.0
    if duration < 2.0
        autoStartTime = duration * 0.25
    endif
    autoBeat = floor(autoStartTime / secondsPerBeat) + 1
    if autoBeat < 1
        autoBeat = 1
    endif
    if autoBeat > totalBeats
        autoBeat = totalBeats
    endif
    
    requestedBeat = autoBeat
    selectedBeat = autoBeat
    
    if skip_silence and beatSilent#[autoBeat] = 1
        # Search forward first
        foundAuto = 0
        for b from autoBeat + 1 to totalBeats
            if foundAuto = 0 and beatSilent#[b] = 0
                selectedBeat = b
                foundAuto = 1
            endif
        endfor
        # Fallback: search backward
        if foundAuto = 0
            for offset from 1 to autoBeat - 1
                cand = autoBeat - offset
                if foundAuto = 0 and cand >= 1
                    if beatSilent#[cand] = 0
                        selectedBeat = cand
                        foundAuto = 1
                    endif
                endif
            endfor
        endif
        
        if foundAuto
            shiftReport$ = "requested #" + string$(autoBeat) + " (1s in) was silent, advanced to #" + string$(selectedBeat)
            appendInfoLine: "  Auto: ", shiftReport$
        else
            shiftReport$ = "all beats silent; using #" + string$(autoBeat)
            appendInfoLine: "  Auto: ", shiftReport$
        endif
    else
        shiftReport$ = "#" + string$(autoBeat) + " (1s in)"
        appendInfoLine: "Mode: Auto beat #", selectedBeat
    endif
endif

# ============================================================
# CALCULATE TIME POINTS
# ============================================================
# sourceStartTime: where the segment is extracted from
# beforeEnd:       where the before-section ends (cut point)
# afterStart:      where the after-section starts (cut point)
#
# For modes 1/2/4, all three correspond to the selected beat.
# For mode 3 (range), beforeEnd/afterStart use the ORIGINAL
# user range (replacement target), while sourceStartTime can
# be inside the range (silence-shifted).

sourceStartTime = (selectedBeat - 1) * secondsPerBeat

# Safety check (normally guaranteed by valid beat-start counting).
if sourceStartTime + noteDuration > duration
    sourceStartTime = max(0, duration - noteDuration)
endif

if beat_selection_mode = 3
    beforeEnd = (rangeStart - 1) * secondsPerBeat
    afterStart = rangeEnd * secondsPerBeat
    if afterStart > duration
        afterStart = duration
    endif
else
    beforeEnd = sourceStartTime
    afterStart = sourceStartTime + noteDuration
endif

appendInfoLine: "Extract from: ", fixed$(sourceStartTime, 3), " s"

# ============================================================
# EXTRACT SOURCE SEGMENT
# ============================================================
selectObject: sound
sourceExtractStart = sourceStart + sourceStartTime
sourceExtractEnd = sourceExtractStart + noteDuration
segment = Extract part: sourceExtractStart, sourceExtractEnd, "rectangular", 1.0, "no"
Rename: "segment"

# Check level (post-extraction sanity check; the pre-scan
# already informed beat selection)
selectObject: segment
segment_rms = Get root-mean-square: 0, 0
if segment_rms = undefined
    segment_rms = 0
endif
if segment_rms < silence_thresh_lin
    appendInfoLine: "Note: selected segment is below silence threshold (RMS = ", fixed$(20 * log10(segment_rms + 1e-12), 1), " dB)"
endif

# Apply fades if requested
if fade_repeats = 1
    selectObject: segment
    segDur = Get total duration
    fadeDur = min(fade_duration_s, segDur * 0.3)
    if fadeDur > 0
        Fade in: 0, 0, fadeDur, "yes"
        Fade out: 0, segDur - fadeDur, fadeDur, "yes"
    endif
endif

# === Extract Before Part ===
selectObject: sound
if beforeEnd > 0
    before = Extract part: sourceStart, sourceStart + beforeEnd, "rectangular", 1.0, "no"
    hasBefore = 1
else
    hasBefore = 0
endif

# === Create Repeats ===
appendInfoLine: "Creating ", num_repeats, " repeats (decay: ", amplitude_decay, ")..."

selectObject: segment
repeated = Copy: "repeated"

for i from 2 to num_repeats
    selectObject: segment
    this_repeat = Copy: "temp_repeat"
    
    # Apply amplitude decay
    decayFactor = amplitude_decay ^ (i - 1)
    Formula: "self * " + string$(decayFactor)
    
    # Concatenate
    selectObject: repeated, this_repeat
    new_repeated = Concatenate
    removeObject: repeated, this_repeat
    repeated = new_repeated
endfor

Rename: "repeated_section"

selectObject: repeated
repeatedDuration = Get total duration

# === Extract After Part ===
selectObject: sound
if afterStart < duration
    after = Extract part: sourceStart + afterStart, sourceEnd, "rectangular", 1.0, "no"
    hasAfter = 1
else
    hasAfter = 0
endif

# === Assemble Result ===
appendInfoLine: "Assembling result..."

if hasBefore = 1 and hasAfter = 1
    selectObject: before, repeated, after
    result = Concatenate
    removeObject: before, after
elsif hasBefore = 1 and hasAfter = 0
    selectObject: before, repeated
    result = Concatenate
    removeObject: before
elsif hasBefore = 0 and hasAfter = 1
    selectObject: repeated, after
    result = Concatenate
    removeObject: after
else
    selectObject: repeated
    result = Copy: "result"
endif

Rename: sound_name$ + "_beatRepeat_" + presetName$

# Cleanup
removeObject: segment, repeated

# === Get Result Info ===
selectObject: result
resultDuration = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Mono copies of original and result for waveform panels
    selectObject: sound
    if numChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    
    selectObject: result
    resNumCh = Get number of channels
    if resNumCh > 1
        vizResult = Convert to mono
    else
        vizResult = Copy: "viz_result"
    endif
    
    # SHARED y-axis from BOTH original and result
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    rPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if rPeak > sharedPeak
        sharedPeak = rPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BEAT REPEAT##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
    if skip_silence
        silStr$ = "skip silence (" + fixed$(silence_threshold_dB, 0) + " dB)"
    else
        silStr$ = "no silence skip"
    endif
    
    Text: 0.5, "centre", -0.22, "half",
        ... sound_name$
        ... + "  |  " + presetName$
        ... + "  |  " + fixed$(bpm, 0) + " BPM"
        ... + "  |  " + note_name$
        ... + "  |  beat #" + string$(selectedBeat) + " of " + string$(totalBeats)
        ... + "  |  " + string$(num_repeats) + "x decay " + fixed$(amplitude_decay, 2)
        ... + "  |  " + silStr$
    
    # ----------------------------------------------------------
    # PANEL A: CANDIDATE-SLICE ENERGY BAR CHART  (left, headline)
    # The silence diagnostic: one bar per valid beat start at height
    # = RMS-dB. Blue = non-silent, gray = silent. Selected
    # beat highlighted with orange. Range bounds (mode 3)
    # also shown as orange vertical lines.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    # Y range: -60 dB to 0 dB (or threshold-5 to 0 if threshold < -55)
    yMinDB = -60
    if silence_threshold_dB < yMinDB + 5
        yMinDB = silence_threshold_dB - 5
    endif
    yMaxDB = 0
    
    xMin = 0.5
    xMax = totalBeats + 0.5
    
    Axes: xMin, xMax, yMinDB, yMaxDB
    Paint rectangle: "{0.97, 0.97, 0.99}", xMin, xMax, yMinDB, yMaxDB
    
    # Reference horizontal grid
    Colour: "{0.88, 0.88, 0.92}"
    Dotted line
    Draw line: xMin, -20, xMax, -20
    Draw line: xMin, -40, xMax, -40
    Solid line
    
    # Draw bars
    for b from 1 to totalBeats
        barDB = beatRMSdB#[b]
        if barDB < yMinDB
            barDB = yMinDB
        endif
        if barDB > yMaxDB
            barDB = yMaxDB
        endif
        
        if beatSilent#[b] = 1
            barColor$ = "{0.75, 0.75, 0.78}"
        else
            barColor$ = "{0.25, 0.50, 0.82}"
        endif
        
        Paint rectangle: barColor$, b - 0.4, b + 0.4, yMinDB, barDB
    endfor
    
    # Range mode: orange vertical bands for [rangeStart, rangeEnd]
    if beat_selection_mode = 3
        Colour: "{0.95, 0.55, 0.20}"
        Line width: 1
        Dashed line
        Draw line: rangeStart - 0.5, yMinDB, rangeStart - 0.5, yMaxDB
        Draw line: rangeEnd + 0.5, yMinDB, rangeEnd + 0.5, yMaxDB
        Solid line
    endif
    
    # Selected beat: orange outline + dot at top
    Colour: "{0.95, 0.55, 0.20}"
    Line width: 2
    selBarDB = beatRMSdB#[selectedBeat]
    if selBarDB < yMinDB
        selBarDB = yMinDB
    endif
    if selBarDB > yMaxDB
        selBarDB = yMaxDB
    endif
    Draw line: selectedBeat - 0.4, yMinDB, selectedBeat - 0.4, selBarDB
    Draw line: selectedBeat + 0.4, yMinDB, selectedBeat + 0.4, selBarDB
    Draw line: selectedBeat - 0.4, selBarDB, selectedBeat + 0.4, selBarDB
    Paint circle (mm): "{0.95, 0.55, 0.20}", selectedBeat, yMaxDB - 2, 1.0
    Line width: 1
    
    # Threshold line (red dashed)
    Colour: "{0.85, 0.30, 0.30}"
    Line width: 1.5
    Dashed line
    Draw line: xMin, silence_threshold_dB, xMax, silence_threshold_dB
    Solid line
    Line width: 1
    
    # Threshold label
    Font size: 5
    Colour: "{0.55, 0.20, 0.20}"
    Text: xMax - (xMax - xMin) * 0.02, "right", silence_threshold_dB + 2, "half", "thresh " + fixed$(silence_threshold_dB, 0) + " dB"
    
    # Selected beat label
    Colour: "{0.55, 0.30, 0.15}"
    Text: selectedBeat, "centre", yMaxDB - 5, "half", "#" + string$(selectedBeat)
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "RMS (dB re 1.0)"
    Text bottom: "yes", "Beat number"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.94, "half", "Algorithm:"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.88, "half", "Extract beat -> repeat N times w/decay -> assemble"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.80, "half", "Tempo:"
    
    Font size: 9
    Colour: "{0.20, 0.50, 0.82}"
    Text: 0.10, "left", 0.74, "half", fixed$(bpm, 1) + " BPM | note " + note_name$
    Text: 0.10, "left", 0.68, "half", fixed$(noteDuration * 1000, 1) + " ms / " + string$(totalBeats) + " beats total"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.60, "half", "Beat selection:"
    
    Font size: 9
    Colour: "{0.55, 0.30, 0.78}"
    if beat_selection_mode = 1
        Text: 0.10, "left", 0.54, "half", "Specific beat"
    elsif beat_selection_mode = 2
        Text: 0.10, "left", 0.54, "half", "Random beat"
    elsif beat_selection_mode = 3
        Text: 0.10, "left", 0.54, "half", "Beat range [" + string$(rangeStart) + "-" + string$(rangeEnd) + "]"
    else
        Text: 0.10, "left", 0.54, "half", "Auto (1 s in)"
    endif
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.48, "half", shiftReport$
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.40, "half", "Silence detection:"
    
    Font size: 9
    if skip_silence
        if silentCount > 0
            Colour: "{0.85, 0.45, 0.30}"
            Text: 0.10, "left", 0.34, "half", string$(silentCount) + "/" + string$(totalBeats) + " slices silent (< " + fixed$(silence_threshold_dB, 0) + " dB)"
        else
            Colour: "{0.30, 0.55, 0.30}"
            Text: 0.10, "left", 0.34, "half", "0 silent slices found"
        endif
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.34, "half", "OFF (using v0.2 behavior)"
    endif
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.26, "half", "Repeat parameters:"
    
    Font size: 9
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.20, "half", string$(num_repeats) + " repeats | decay " + fixed$(amplitude_decay, 2)
    if fade_repeats
        Text: 0.10, "left", 0.14, "half", "Edge fades: " + fixed$(fade_duration_s * 1000, 1) + " ms"
    else
        Text: 0.10, "left", 0.14, "half", "Edge fades: OFF"
    endif
    
    Font size: 9
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.05, "left", 0.05, "half", "Out: " + fixed$(resultDuration, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Candidate-slice energy (blue = active, gray = silent, orange = selected)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM AROUND REPEAT SECTION
    # Gray = original, blue = result.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    # Center the zoom on the repeat section, with padding
    padding = 0.3
    zoomStart = beforeEnd - padding
    if zoomStart < 0
        zoomStart = 0
    endif
    zoomEnd = beforeEnd + repeatedDuration + padding
    if zoomEnd > resultDuration
        zoomEnd = resultDuration
    endif
    
    Axes: zoomStart, zoomEnd, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", zoomStart, zoomEnd, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: zoomStart, 0, zoomEnd, 0
    
    # Mark repeat region (orange dotted)
    Colour: "{0.95, 0.65, 0.30}"
    Line width: 1
    Dotted line
    Draw line: beforeEnd, -sharedAmp, beforeEnd, sharedAmp
    Draw line: beforeEnd + repeatedDuration, -sharedAmp, beforeEnd + repeatedDuration, sharedAmp
    Solid line
    Line width: 1
    
    # Original behind (gray) — only over its own time range
    origEnd = zoomEnd
    if origEnd > duration
        origEnd = duration
    endif
    if zoomStart < duration
        selectObject: vizOrig
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, origEnd, -sharedAmp, sharedAmp, "no", "Curve"
    endif
    
    # Result on top (blue)
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: zoomStart, zoomEnd, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom on repeat section  (gray = original, blue = result, orange = cut points)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (SHARED y-axis)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if resultDuration > duration
        dispDur = resultDuration
    else
        dispDur = duration
    endif
    
    Axes: 0, dispDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dispDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dispDur, 0
    
    # Original behind (only its duration)
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Result on top (full)
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, resultDuration, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Mark repeat region
    Colour: "{0.95, 0.65, 0.30}"
    Line width: 1
    Dotted line
    Draw line: beforeEnd, -sharedAmp, beforeEnd, sharedAmp
    Draw line: beforeEnd + repeatedDuration, -sharedAmp, beforeEnd + repeatedDuration, sharedAmp
    Solid line
    Line width: 1
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full waveform  (gray = original, blue = result, orange = repeat region)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if skip_silence
        skipStr$ = "ON (" + fixed$(silence_threshold_dB, 0) + " dB)"
    else
        skipStr$ = "OFF"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sound_name$
        ... + "  |  " + fixed$(bpm, 0) + " BPM"
        ... + "  |  " + note_name$ + " (" + fixed$(noteDuration * 1000, 1) + " ms)"
        ... + "  |  Beat #" + string$(selectedBeat) + " of " + string$(totalBeats)
        ... + "  |  Repeats: " + string$(num_repeats) + " (decay " + fixed$(amplitude_decay, 2) + ")"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Silence skip: " + skipStr$
        ... + "  |  Silent: " + string$(silentCount) + "/" + string$(totalBeats)
        ... + "  |  " + shiftReport$
        ... + "  |  Out: " + fixed$(resultDuration, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOrig, vizResult
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
selectObject: result
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Original: ", fixed$(duration, 2), " s"
appendInfoLine: "Result: ", fixed$(resultDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
