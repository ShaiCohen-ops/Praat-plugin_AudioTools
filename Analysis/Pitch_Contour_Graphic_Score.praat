# ========================================================================================
# Praat AudioTools - Pitch_Contour_Graphic_Score.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.0 (2026) - Paginated score: fixed pages, page browser, per-page PNG
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Transforms a sound's continuous pitch into a PERFORMABLE graphic
#   score in the idiom of contemporary vocal/instrumental notation
#   (Ligeti / Crumb / Berberian / Aperghis lineage):
#
#     - A real 5-line staff (treble, bass, or grand staff) with clefs
#       and ledger lines; pitch height maps to true staff position.
#     - The f0 trace is rendered as a GLISSANDO CONTOUR: where pitch
#       stabilises it becomes a notehead (with accidental); where it
#       moves it becomes a slide line between noteheads.
#     - Proportional / spatial time (seconds), not metered bars - the
#       performer reads gestures left to right in real time.
#     - A continuous DYNAMIC RIBBON (hairpin envelope) under the staff
#       derived from intensity, with pp..ff reference band.
#
#   This is an interpretive transcription, not a literal one: the
#   gesture segmentation (hold vs. glide) is parameterised below.
#
# Pipeline:
#   1. Pitch + intensity analysis (frame level).
#   2. Optional contour smoothing (median / moving average).
#   3. Gesture segmentation: contiguous voiced frames are split into
#      HELD notes (pitch within a tolerance for a minimum duration)
#      and GLIDES (everything between holds).
#   4. Staff layout from the detected pitch range.
#   5. Render: staff + clefs, contour line, noteheads + accidentals,
#      dynamic ribbon, proportional time axis with second marks.
#
# Changelog v4.0:
#   - PAGINATION. The score is cut into fixed-size pages, each holding as
#     many whole systems as fit; systems never split. Staff layout, time
#     scale and line weights are computed once, so every page matches.
#     Page formats: Portrait page (8 x 10.5 in), HD 16:9 page (16 x 9 in),
#     or Continuous (v3.7's single tall page). v3.7's HD mode silently
#     dropped the systems that did not fit one frame; they now continue
#     on the next pages.
#   - PAGE BROWSER in the Picture window (Previous / Next / Export all /
#     Done). On the last page the default button is Done, so a run that
#     cannot show dialogs ends instead of looping. Browse_pages off =
#     unattended export (note: Praat 7 stops silently at any pause
#     dialog in a headless run, so switch browsing off for batch use).
#   - PER-PAGE PNG: <name>_score[_window]_pNN.png, one file per page
#     (a single-page score keeps v3.7's file name).
#   - FIT TO PAGES: optional target page count; seconds-per-system is
#     then chosen so the render window fills exactly that many pages.
#   - Every page carries its page number and time range in the title.
#   - FIX: system 1 was drawn with different viewport margins from all
#     the other systems (font-size state at Select viewport time), so its
#     bracket and staff lines were offset. Every system now draws with
#     the same margins (identical to v3.7's systems 2..N).
#   - Form reorganised and shortened (16 -> 13 rows); analysis,
#     segmentation and the system drawing code are unchanged.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Notation / Visualization
# ========================================================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
sound$ = selected$("Sound")

form Pitch Contour Graphic Score v4.0
    comment === Notation ===
    optionmenu Preset: 1
        option Balanced score (general purpose)
        option Sparse phrase (only sustained notes)
        option Dense detail (catch short holds)
        option Pure glissando (contour only, no noteheads)
        option Vocal (narrow tessitura, fine wobble)
        option Custom (use Advanced settings below)
    optionmenu Staff_system: 3
        option Treble only
        option Bass only
        option Grand staff (treble + bass)
    optionmenu Staff_size: 2
        option Small
        option Medium
        option Large
    comment === Pages ===
    optionmenu Page_format: 1
        option Portrait page (8 x 10.5 in)
        option HD 16:9 page (16 x 9 in)
        option Continuous (one tall page, v3.7)
    positive Seconds_per_system 6.0
    integer Fit_to_pages_(0_=_off) 0
    real Render_from_seconds 0.0
    real Render_to_seconds_(0_=_end) 0.0
    comment === Output ===
    boolean Browse_pages 1
    boolean Save_png 0
    sentence Png_folder_(empty_=_chooser)
    optionmenu Png_dpi: 1
        option 300 dpi
        option 600 dpi
endform

# ========================================================================================
# DEFAULTS  (edit these instead of crowding the dialog)
#   Analysis + display parameters that rarely change live here. The
#   "Custom" preset reads adv_* below; all other presets ignore them.
# ========================================================================================

# --- Analysis ---
# auto_pitch_range = 1 : a first wide pass measures the input, then the
#   real analysis uses a floor/ceiling fitted to it (Hirst two-pass).
#   pitch_floor / pitch_ceiling below are the fallback when the sound is
#   unvoiced, and the hard clamp bounds for the auto estimate.
auto_pitch_range = 1
pitch_floor = 75
pitch_ceiling = 600
probe_floor = 50
probe_ceiling = 800
time_step = 0.01
intensity_min_db = 40
intensity_max_db = 80
use_log_loudness = 1

# --- Grid / title display ---
show_second_marks = 1
show_title_block = 1

# --- "Custom" preset overrides (used only when Preset = Custom) ---
adv_smoothing = 2
adv_hold_tolerance_semitones = 0.4
adv_min_hold_seconds = 0.12
adv_show_glissando_lines = 1
adv_show_noteheads = 1
adv_show_dynamic_ribbon = 1
adv_show_note_names = 0

# ========================================================================================
# PRESET RESOLUTION
#   Presets set the gesture/notation parameters; "Custom" falls back to
#   the Adv_* fields. This keeps the dialog short without losing control.
# ========================================================================================

if preset = 1
    # Balanced score
    smoothing = 2
    hold_tolerance_semitones = 0.4
    min_hold_seconds = 0.12
    show_glissando_lines = 1
    show_noteheads = 1
    show_dynamic_ribbon = 1
    show_note_names = 0
    presetName$ = "Balanced"
elsif preset = 2
    # Sparse phrase: only clearly sustained pitches become noteheads
    smoothing = 3
    hold_tolerance_semitones = 0.35
    min_hold_seconds = 0.30
    show_glissando_lines = 1
    show_noteheads = 1
    show_dynamic_ribbon = 1
    show_note_names = 0
    presetName$ = "Sparse"
elsif preset = 3
    # Dense detail: catch short holds, tighter tolerance
    smoothing = 1
    hold_tolerance_semitones = 0.5
    min_hold_seconds = 0.07
    show_glissando_lines = 1
    show_noteheads = 1
    show_dynamic_ribbon = 1
    show_note_names = 0
    presetName$ = "Dense"
elsif preset = 4
    # Pure glissando: contour + dynamics, no noteheads at all
    smoothing = 2
    hold_tolerance_semitones = 0.4
    min_hold_seconds = 0.12
    show_glissando_lines = 1
    show_noteheads = 0
    show_dynamic_ribbon = 1
    show_note_names = 0
    presetName$ = "Glissando"
elsif preset = 5
    # Vocal: fine wobble tolerance, moderate hold floor
    smoothing = 3
    hold_tolerance_semitones = 0.3
    min_hold_seconds = 0.18
    show_glissando_lines = 1
    show_noteheads = 1
    show_dynamic_ribbon = 1
    show_note_names = 0
    presetName$ = "Vocal"
else
    # Custom: take the Advanced fields
    smoothing = adv_smoothing
    hold_tolerance_semitones = adv_hold_tolerance_semitones
    min_hold_seconds = adv_min_hold_seconds
    show_glissando_lines = adv_show_glissando_lines
    show_noteheads = adv_show_noteheads
    show_dynamic_ribbon = adv_show_dynamic_ribbon
    show_note_names = adv_show_note_names
    presetName$ = "Custom"
endif

# ========================================================================================
# HELPER PROCEDURES
# ========================================================================================

procedure hzToMidi: .hz
    if .hz > 0
        .midi = 69 + 12 * log2(.hz / 440)
    else
        .midi = undefined
    endif
endproc

procedure mapToRange: .value, .fromMin, .fromMax, .toMin, .toMax
    .value = max(.fromMin, min(.fromMax, .value))
    .result = .toMin + (.value - .fromMin) / (.fromMax - .fromMin) * (.toMax - .toMin)
endproc

procedure logCompress: .db, .minDb, .maxDb
    .normalized = (.db - .minDb) / (.maxDb - .minDb)
    .normalized = max(0, min(1, .normalized))
    if .normalized > 0
        .result = (log10(.normalized * 9 + 1)) / log10(10)
    else
        .result = 0
    endif
endproc

procedure getMidiNoteName: .midi
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave = floor(.midi / 12) - 1
    
    if .noteClass = 0
        .noteName$ = "C"
    elsif .noteClass = 1
        .noteName$ = "C#"
    elsif .noteClass = 2
        .noteName$ = "D"
    elsif .noteClass = 3
        .noteName$ = "D#"
    elsif .noteClass = 4
        .noteName$ = "E"
    elsif .noteClass = 5
        .noteName$ = "F"
    elsif .noteClass = 6
        .noteName$ = "F#"
    elsif .noteClass = 7
        .noteName$ = "G"
    elsif .noteClass = 8
        .noteName$ = "G#"
    elsif .noteClass = 9
        .noteName$ = "A"
    elsif .noteClass = 10
        .noteName$ = "A#"
    elsif .noteClass = 11
        .noteName$ = "B"
    endif
    
    .fullName$ = .noteName$ + string$(.octave)
endproc

procedure medianFilter3: .i
    if .i = 1 or .i = numFrames
        .result = midiNote_'.i'
    else
        .iPrev = .i - 1
        .iNext = .i + 1
        .valPrev = midiNote_'.iPrev'
        .valCurr = midiNote_'.i'
        .valNext = midiNote_'.iNext'
        
        if .valPrev <> undefined and .valCurr <> undefined and .valNext <> undefined
            .a = .valPrev
            .b = .valCurr
            .c = .valNext
            
            if .a <= .b and .b <= .c
                .result = .b
            elsif .a <= .c and .c <= .b
                .result = .c
            elsif .b <= .a and .a <= .c
                .result = .a
            elsif .b <= .c and .c <= .a
                .result = .c
            elsif .c <= .a and .a <= .b
                .result = .a
            else
                .result = .b
            endif
        else
            .result = midiNote_'.i'
        endif
    endif
endproc

procedure medianFilter5: .i
    if .i <= 2 or .i >= numFrames - 1
        .result = midiNote_'.i'
    else
        # Collect up to 5 values
        .count = 0
        for .offset from -2 to 2
            .idx = .i + .offset
            .val = midiNote_'.idx'
            if .val <> undefined
                .count = .count + 1
                .sortVal_'.count' = .val
            endif
        endfor
        
        if .count >= 3
            # Bubble sort
            for .pass from 1 to .count - 1
                for .k from 1 to .count - .pass
                    .k1 = .k + 1
                    .v1 = .sortVal_'.k'
                    .v2 = .sortVal_'.k1'
                    if .v1 > .v2
                        .sortVal_'.k' = .v2
                        .sortVal_'.k1' = .v1
                    endif
                endfor
            endfor
            .medianIdx = floor(.count / 2) + 1
            .result = .sortVal_'.medianIdx'
        else
            .result = midiNote_'.i'
        endif
    endif
endproc

procedure movingAverage: .i
    if .i = 1 or .i = numFrames
        .result = midiNote_'.i'
    else
        .count = 0
        .sum = 0
        for .offset from -1 to 1
            .idx = .i + .offset
            .val = midiNote_'.idx'
            if .val <> undefined
                .sum = .sum + .val
                .count = .count + 1
            endif
        endfor
        if .count > 0
            .result = .sum / .count
        else
            .result = midiNote_'.i'
        endif
    endif
endproc




# ========================================================================================
# MAIN SCRIPT
# ========================================================================================

selectObject: soundID
duration = Get total duration
startTime = Get start time
endTime = Get end time

clearinfo
writeInfoLine: "=== Continuous Pitch MIDI Grid Visualizer v2.1 ==="
appendInfoLine: "Sound: ", sound$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""

# ========================================================================================
# STEP 1: Extract Pitch and Intensity
# ========================================================================================

appendInfoLine: "Extracting pitch..."

# Effective floor/ceiling actually used for analysis.
useFloor = pitch_floor
useCeiling = pitch_ceiling

if auto_pitch_range
    # Pass 1: wide probe to measure the input's own range.
    selectObject: soundID
    probeID = To Pitch: time_step, probe_floor, probe_ceiling
    q25 = Get quantile: 0, 0, 0.25, "Hertz"
    q75 = Get quantile: 0, 0, 0.75, "Hertz"
    removeObject: probeID

    if q25 <> undefined and q75 <> undefined and q25 > 0 and q75 > q25
        # Hirst's factors: floor = 0.75 * q25, ceiling = 1.5 * q75.
        estFloor = q25 * 0.75
        estCeiling = q75 * 1.5
        # Clamp to sane bounds (the manual values act as outer limits).
        if estFloor < probe_floor
            estFloor = probe_floor
        endif
        if estCeiling > probe_ceiling
            estCeiling = probe_ceiling
        endif
        if estCeiling <= estFloor + 20
            estCeiling = estFloor + 20
        endif
        useFloor = estFloor
        useCeiling = estCeiling
        appendInfoLine: "  Auto pitch range: ", fixed$(useFloor, 1),
            ... " - ", fixed$(useCeiling, 1), " Hz",
            ... "  (q25=", fixed$(q25, 1), " q75=", fixed$(q75, 1), ")"
    else
        appendInfoLine: "  Auto range: input too unvoiced; using manual ",
            ... fixed$(useFloor, 1), " - ", fixed$(useCeiling, 1), " Hz"
    endif
else
    appendInfoLine: "  Manual pitch range: ", fixed$(useFloor, 1),
        ... " - ", fixed$(useCeiling, 1), " Hz"
endif

# Pass 2: the real analysis with the chosen range.
selectObject: soundID
pitchID = To Pitch: time_step, useFloor, useCeiling

appendInfoLine: "Extracting intensity..."
selectObject: soundID
intensityID = To Intensity: useFloor, time_step, "yes"

# ========================================================================================
# STEP 2: Collect Data
# ========================================================================================

appendInfoLine: "Collecting data..."

selectObject: pitchID
numFrames = Get number of frames

midiMinFound = 1000
midiMaxFound = 0

for i from 1 to numFrames
    selectObject: pitchID
    t_'i' = Get time from frame number: i
    f0_'i' = Get value in frame: i, "Hertz"
    
    f0val = f0_'i'
    if f0val <> undefined
        @hzToMidi: f0val
        midiNote_'i' = hzToMidi.midi
        quantizedMidi_'i' = round(hzToMidi.midi)
        voiced_'i' = 1
        
        if midiNote_'i' < midiMinFound
            midiMinFound = midiNote_'i'
        endif
        if midiNote_'i' > midiMaxFound
            midiMaxFound = midiNote_'i'
        endif
    else
        midiNote_'i' = undefined
        quantizedMidi_'i' = undefined
        voiced_'i' = 0
    endif
    
    selectObject: intensityID
    intensity_'i' = Get value at time: t_'i', "Cubic"
    if intensity_'i' = undefined
        intensity_'i' = intensity_min_db
    endif
endfor

# ========================================================================================
# STEP 3: Apply Smoothing
# ========================================================================================

if smoothing > 1
    appendInfoLine: "Applying smoothing..."
    
    # Copy to smoothed array
    for i from 1 to numFrames
        smoothedMidi_'i' = midiNote_'i'
    endfor
    
    # Apply filter
    for i from 1 to numFrames
        v = voiced_'i'
        if v = 1
            if smoothing = 2
                @medianFilter3: i
                smoothedMidi_'i' = medianFilter3.result
            elsif smoothing = 3
                @medianFilter5: i
                smoothedMidi_'i' = medianFilter5.result
            elsif smoothing = 4
                @movingAverage: i
                smoothedMidi_'i' = movingAverage.result
            endif
        endif
    endfor
    
    # Copy back
    for i from 1 to numFrames
        v = voiced_'i'
        if v = 1
            midiNote_'i' = smoothedMidi_'i'
        endif
    endfor
endif

# ========================================================================================
# STEP 4: GESTURE SEGMENTATION (held notes vs. glides)
#   Walk contiguous voiced runs. Within a run, a HOLD is a maximal
#   span where every frame stays within hold_tolerance_semitones of
#   the span's running mean AND the span lasts >= min_hold_seconds.
#   Everything else is glide. Holds get a notehead at their mean
#   pitch; glides are drawn as the raw contour line.
# ========================================================================================

appendInfoLine: "Segmenting gestures (hold vs. glide)..."

# Per-frame hold flag + the hold id each frame belongs to (0 = glide)
hold_count = 0
for i from 1 to numFrames
    holdFlag_'i' = 0
    holdId_'i' = 0
endfor

i = 1
while i <= numFrames
    if voiced_'i' = 1
        # Try to extend a hold starting at i
        runMean = midiNote_'i'
        runN = 1
        j = i + 1
        ok = 1
        while ok = 1 and j <= numFrames
            if voiced_'j' = 1
                cand = midiNote_'j'
                newMean = (runMean * runN + cand) / (runN + 1)
                # check the whole tentative span stays within tolerance
                dev = cand - newMean
                if dev < 0
                    dev = -dev
                endif
                if dev <= hold_tolerance_semitones
                    runMean = newMean
                    runN = runN + 1
                    j = j + 1
                else
                    ok = 0
                endif
            else
                ok = 0
            endif
        endwhile

        spanStart = i
        spanEnd = j - 1
        spanDur = t_'spanEnd' - t_'spanStart'

        if runN >= 2 and spanDur >= min_hold_seconds
            hold_count = hold_count + 1
            hold_start_'hold_count' = spanStart
            hold_end_'hold_count' = spanEnd
            hold_midi_'hold_count' = runMean
            hold_t0_'hold_count' = t_'spanStart'
            hold_t1_'hold_count' = t_'spanEnd'
            for k from spanStart to spanEnd
                holdFlag_'k' = 1
                holdId_'k' = hold_count
            endfor
            i = spanEnd + 1
        else
            # Not a hold; advance by one frame (stays glide)
            i = i + 1
        endif
    else
        i = i + 1
    endif
endwhile

appendInfoLine: "  Held notes detected: ", hold_count

# ========================================================================================
# STEP 5: PITCH RANGE + STAFF LAYOUT
# ========================================================================================

# Use the found pitch range (already computed in analysis as
# midiMinFound / midiMaxFound). Fall back to a sane window if silent.
if midiMaxFound < midiMinFound
    midiMinFound = 55
    midiMaxFound = 67
endif

# Pad a little so the contour never touches the frame edge.
scoreMidiMin = floor(midiMinFound) - 2
scoreMidiMax = ceiling(midiMaxFound) + 2

# Staff reference pitches (MIDI):
#   Treble: E4(64) G4 B4 D5 F5(77)   - lines bottom->top
#   Bass:   G2(43) B2 D3 F3 A3(57)
# We map MIDI -> vertical "staff units" where one diatonic step = 0.5.
# For a clean contemporary look we map by MIDI linearly within each
# staff's drawing band, but place the 5 staff lines at their true
# pitch positions so noteheads land correctly.

# === Procedures for staff drawing ===

procedure diatonicStep: .midi
    # Number of diatonic steps above C-1 (MIDI 0) for staff positioning.
    # Maps chromatic MIDI to a diatonic line/space index using a fixed
    # C-major ladder; sharps share the line/space of their natural and
    # carry an accidental.
    .pc = .midi - 12 * floor(.midi / 12)
    .oct = floor(.midi / 12)
    # diatonic index within octave for each pitch class (C=0,D=1,...B=6)
    if .pc = 0
        .d = 0
        .acc = 0
    elsif .pc = 1
        .d = 0
        .acc = 1
    elsif .pc = 2
        .d = 1
        .acc = 0
    elsif .pc = 3
        .d = 1
        .acc = 1
    elsif .pc = 4
        .d = 2
        .acc = 0
    elsif .pc = 5
        .d = 3
        .acc = 0
    elsif .pc = 6
        .d = 3
        .acc = 1
    elsif .pc = 7
        .d = 4
        .acc = 0
    elsif .pc = 8
        .d = 4
        .acc = 1
    elsif .pc = 9
        .d = 5
        .acc = 0
    elsif .pc = 10
        .d = 5
        .acc = 1
    else
        .d = 6
        .acc = 0
    endif
    .step = .oct * 7 + .d
endproc

# Map a continuous MIDI value to a continuous diatonic staff coordinate
# (for the glissando contour). We interpolate the diatonic ladder so a
# semitone slide reads smoothly.
procedure midiToStaffY: .midi
    .lo = floor(.midi)
    .frac = .midi - .lo
    @diatonicStep: .lo
    .yLo = diatonicStep.step
    .hi = .lo + 1
    @diatonicStep: .hi
    .yHi = diatonicStep.step
    .y = .yLo + (.yHi - .yLo) * .frac
endproc

# Reference staff-Y for the bottom and top lines of each clef:
@diatonicStep: 64
trebleBottomY = diatonicStep.step
@diatonicStep: 77
trebleTopY = diatonicStep.step
@diatonicStep: 43
bassBottomY = diatonicStep.step
@diatonicStep: 57
bassTopY = diatonicStep.step

# Overall staff-Y span we must draw, from the data range:
@midiToStaffY: scoreMidiMin
yDataMin = midiToStaffY.y
@midiToStaffY: scoreMidiMax
yDataMax = midiToStaffY.y

# Make sure the chosen staff system's lines are inside the drawn band.
if staff_system = 1
    yLo = min(yDataMin, trebleBottomY - 1)
    yHi = max(yDataMax, trebleTopY + 1)
elsif staff_system = 2
    yLo = min(yDataMin, bassBottomY - 1)
    yHi = max(yDataMax, bassTopY + 1)
else
    yLo = min(yDataMin, bassBottomY - 1)
    yHi = max(yDataMax, trebleTopY + 1)
endif

# ========================================================================================
# STEP 6: SCORE LAYOUT + PAGINATION
# ========================================================================================

# --- Resolve the render window (phrase export). Analysis covered the
# whole file, so pitch range and staff layout below are identical no
# matter which window is drawn: adjacent exports line up when joined. ---
winFrom = render_from_seconds
winTo = render_to_seconds
if winTo <= 0 or winTo > duration
    winTo = duration
endif
if winFrom < 0
    winFrom = 0
endif
if winFrom >= winTo
    exitScript: "Render_from_seconds must be less than Render_to_seconds (or to=0 for end)."
endif
winDur = winTo - winFrom
appendInfoLine: "Render window: ", fixed$(winFrom, 2), " - ", fixed$(winTo, 2), " s"

# ----- Staff-size scale factor -----
if staff_size = 1
    sizeScale = 0.78
elsif staff_size = 3
    sizeScale = 1.30
else
    sizeScale = 1.0
endif

# ----- Page geometry -----
topPad = 0.95
botPad = 0.25
leftMargin = 1.0
rightMargin = 0.3
sysSlotH = 1.7 * sizeScale

if page_format = 2
    # HD 16:9 page (16 x 9 in -> 1920 x 1080 at 120 dpi-equivalent)
    canvasW = 16.0
    pageH = 9.0
    leftMargin = 1.6
    rightMargin = 0.5
elsif page_format = 1
    # Portrait page: 8 in wide, US-letter-like height
    canvasW = 8.0
    pageH = 10.5
else
    canvasW = 8.0
    pageH = 0
endif

if page_format <= 2
    systemsPerPage = floor((pageH - topPad - botPad) / sysSlotH)
    if systemsPerPage < 1
        systemsPerPage = 1
    endif
endif

# ----- Fit to pages: choose seconds per system from a page count -----
if fit_to_pages > 0 and page_format <= 2
    sps = winDur / (fit_to_pages * systemsPerPage)
    if sps < 1.0
        sps = 1.0
        appendInfoLine: "  Fit to ", fit_to_pages, " pages would need < 1 s per system; clamped to 1 s."
    endif
    seconds_per_system = sps
    appendInfoLine: "  Fit to pages: ", fixed$(seconds_per_system, 2), " s per system"
endif
if seconds_per_system < 1.0
    seconds_per_system = 1.0
endif

# Systems span the WINDOW, but their absolute time origin is winFrom so
# the second-marks keep the file's real timestamps.
nSystems = ceiling(winDur / seconds_per_system)
if nSystems < 1
    nSystems = 1
endif

if page_format = 3
    # Continuous (v3.7 portrait): one tall page holding every system.
    systemsPerPage = nSystems
    pageH = topPad + nSystems * sysSlotH + botPad
endif
nPages = ceiling(nSystems / systemsPerPage)
totalH = pageH
appendInfoLine: "Layout: ", nSystems, " system(s) of ", fixed$(seconds_per_system, 2), " s, ",
    ... systemsPerPage, " per page -> ", nPages, " page(s) of ", fixed$(canvasW, 1), " x ", fixed$(pageH, 2), " in"

# Within one system slot (inches from slot top), scaled by staff size.
staffTopIn = 0.30 * sizeScale
staffBotIn = 1.00 * sizeScale
ribTopIn = 1.12 * sizeScale
ribBotIn = 1.45 * sizeScale

# Staff-Y world span (musical, higher pitch = larger staff-Y).
if staff_system = 1
    yLo = min(yDataMin, trebleBottomY - 1)
    yHi = max(yDataMax, trebleTopY + 1)
elsif staff_system = 2
    yLo = min(yDataMin, bassBottomY - 1)
    yHi = max(yDataMax, bassTopY + 1)
else
    yLo = min(yDataMin, bassBottomY - 1)
    yHi = max(yDataMax, trebleTopY + 1)
endif
if yHi - yLo < 4
    yHi = yLo + 4
endif

xL = leftMargin
xR = canvasW - rightMargin

# Map staff-Y (world) to a fraction 0..1 of the staff band (1 = top).
procedure staffFrac: .staffY
    .f = (.staffY - yLo) / (yHi - yLo)
endproc

# ========================================================================================
# STEP 7: DRAWING PROCEDURES  (one system per viewport; one page at a time)
# ========================================================================================

# Draw system number sys (global time position) into slot .slot of the
# current page. The body is v3.7's system code, unchanged except that the
# slot, not the system number, sets the vertical position.
procedure drawSystem: .sys, .slot
    sys = .sys
    # v4.0 FIX: Praat derives the inner-viewport margins from the font size
    # current at Select viewport / Axes time. v3.7 drew system 1 at the
    # default size (10) and every later system at the 6 left over from the
    # previous system's second marks, so system 1 was offset (bracket
    # ~0.02 in to the right, staff lines ending ~0.03 in short). Fixing the
    # size here makes every system identical to v3.7's systems 2..N.
    Font size: 6
    sysT0 = winFrom + (sys - 1) * seconds_per_system
    slotDur = seconds_per_system
    # True music end within this system (the last system is usually
    # partial). Scale is constant - we only stop the grid here so the
    # staff/ribbon/ticks don't overrun past the music.
    sysEnd = sysT0 + slotDur
    if sysEnd > winTo
        sysEnd = winTo
    endif
    xEndSys = xL + (sysEnd - sysT0) / slotDur * (xR - xL)

    vpTop = topPad + (drawSystem.slot - 1) * sysSlotH
    vpBot = vpTop + sysSlotH

    # This system's viewport. Local Axes: x = time-in-slot, y = inches
    # from slot top (0 at top, sysSlotH at bottom).
    Select outer viewport: 0, canvasW, vpTop, vpBot
    Axes: 0, canvasW, sysSlotH, 0

    # ----- helper inline maps (recomputed per draw) -----
    # time -> x:   px = xL + (t - sysT0)/slotDur * (xR - xL)
    # staffY -> y: @staffFrac -> y = staffTopIn + (1-frac)*(staffBotIn-staffTopIn)

    # ===== Staff lines =====
    Line width: 1
    Colour: "{0.12, 0.12, 0.12}"
    if staff_system = 1 or staff_system = 3
        for ln from 0 to 4
            @staffFrac: trebleBottomY + ln
            yy = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
            Draw line: xL, yy, xEndSys, yy
        endfor
    endif
    if staff_system = 2 or staff_system = 3
        for ln from 0 to 4
            @staffFrac: bassBottomY + ln
            yy = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
            Draw line: xL, yy, xEndSys, yy
        endfor
    endif

    # left bracket
    Line width: 1.2
    @staffFrac: yHi
    yTopB = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
    @staffFrac: yLo
    yBotB = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
    Draw line: xL, yTopB, xL, yBotB

    # ===== Clef labels =====
    Colour: "{0.12, 0.12, 0.12}"
    Font size: 8
    if staff_system = 1 or staff_system = 3
        @staffFrac: trebleBottomY + 2
        yy = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
        Text special: xL - 0.55, "left", yy, "half", "Helvetica", 7, "0", "treble"
    endif
    if staff_system = 2 or staff_system = 3
        @staffFrac: bassBottomY + 2
        yy = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
        Text special: xL - 0.55, "left", yy, "half", "Helvetica", 7, "0", "bass"
    endif

    # ===== Second marks =====
    if show_second_marks
        Line width: 0.4
        Font size: 6
        tick = ceiling(sysT0)
        while tick <= sysEnd + 0.0001
            px = xL + (tick - sysT0) / slotDur * (xR - xL)
            if px <= xEndSys + 0.001 and px >= xL - 0.001
                Colour: "{0.85, 0.85, 0.85}"
                Draw line: px, staffTopIn - 0.04, px, staffBotIn
                Colour: "{0.6, 0.6, 0.6}"
                Text special: px, "centre", staffTopIn - 0.12, "half", "Helvetica", 6, "0", fixed$(tick, 0) + "s"
            endif
            tick = tick + 1
        endwhile
    endif

    # ===== Dynamic ribbon frame =====
    if show_dynamic_ribbon
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 0.5
        Draw line: xL, ribTopIn, xEndSys, ribTopIn
        Draw line: xL, ribBotIn, xEndSys, ribBotIn
        Colour: "{0.55, 0.55, 0.6}"
        Text special: xL - 0.10, "right", (ribTopIn + ribBotIn) / 2, "half", "Helvetica", 6, "0", "dyn"
    endif

    # ===== Glissando contour =====
    if show_glissando_lines
        Line width: 1.4
        Colour: "{0.15, 0.25, 0.55}"
        for i from 1 to numFrames - 1
            i1 = i + 1
            if voiced_'i' = 1 and voiced_'i1' = 1
                ta = t_'i'
                tb = t_'i1'
                if tb >= sysT0 - 0.0001 and ta <= sysT0 + slotDur + 0.0001
                    @midiToStaffY: midiNote_'i'
                    @staffFrac: midiToStaffY.y
                    ya = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
                    @midiToStaffY: midiNote_'i1'
                    @staffFrac: midiToStaffY.y
                    yb = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
                    pxa = xL + (ta - sysT0) / slotDur * (xR - xL)
                    pxb = xL + (tb - sysT0) / slotDur * (xR - xL)
                    Draw line: pxa, ya, pxb, yb
                endif
            endif
        endfor
    endif

    # ===== Noteheads + sustain bars for holds =====
    if show_noteheads
        for h from 1 to hold_count
            ht0 = hold_t0_'h'
            ht1 = hold_t1_'h'
            if ht1 >= sysT0 - 0.0001 and ht0 <= sysT0 + slotDur + 0.0001
                hmid = hold_midi_'h'
                @midiToStaffY: hmid
                @staffFrac: midiToStaffY.y
                ny = staffTopIn + (1 - staffFrac.f) * (staffBotIn - staffTopIn)
                ds = ht0
                de = ht1
                if ds < sysT0
                    ds = sysT0
                endif
                if de > sysT0 + slotDur
                    de = sysT0 + slotDur
                endif
                nx0 = xL + (ds - sysT0) / slotDur * (xR - xL)
                nx1 = xL + (de - sysT0) / slotDur * (xR - xL)

                # sustain bar
                Colour: "{0.12, 0.12, 0.12}"
                Line width: 2.5
                Draw line: nx0, ny, nx1, ny

                # notehead: small filled circle (radius in mm, scaled by size)
                Paint circle (mm): "{0.12, 0.12, 0.12}", nx0, ny, 0.9 * sizeScale

                # accidental
                @diatonicStep: round(hmid)
                if diatonicStep.acc = 1
                    Colour: "{0.12, 0.12, 0.12}"
                    Text special: nx0 - 0.08, "centre", ny, "half", "Helvetica", 10, "0", "#"
                endif

                if show_note_names
                    @getMidiNoteName: round(hmid)
                    Colour: "{0.45, 0.45, 0.55}"
                    Text special: nx0, "centre", ny - 0.10, "half", "Helvetica", 6, "0", getMidiNoteName.fullName$
                endif
            endif
        endfor
    endif

    # ===== Dynamic ribbon contour =====
    if show_dynamic_ribbon
        Line width: 1.2
        Colour: "{0.55, 0.30, 0.55}"
        for i from 1 to numFrames - 1
            i1 = i + 1
            if voiced_'i' = 1 and voiced_'i1' = 1
                ta = t_'i'
                tb = t_'i1'
                if tb >= sysT0 - 0.0001 and ta <= sysT0 + slotDur + 0.0001
                    if use_log_loudness
                        @logCompress: intensity_'i', intensity_min_db, intensity_max_db
                        la = logCompress.result
                        @logCompress: intensity_'i1', intensity_min_db, intensity_max_db
                        lb = logCompress.result
                    else
                        @mapToRange: intensity_'i', intensity_min_db, intensity_max_db, 0, 1
                        la = mapToRange.result
                        @mapToRange: intensity_'i1', intensity_min_db, intensity_max_db, 0, 1
                        lb = mapToRange.result
                    endif
                    pxa = xL + (ta - sysT0) / slotDur * (xR - xL)
                    pxb = xL + (tb - sysT0) / slotDur * (xR - xL)
                    ya = ribBotIn - (ribBotIn - ribTopIn) * la
                    yb = ribBotIn - (ribBotIn - ribTopIn) * lb
                    Draw line: pxa, ya, pxb, yb
                endif
            endif
        endfor
    endif
endproc

procedure drawTitle: .page
    if show_title_block
        Font size: 6
        Select outer viewport: 0, canvasW, 0, topPad
        Axes: 0, canvasW, topPad, 0
        Colour: "{0.12, 0.12, 0.12}"
        Text special: leftMargin, "left", 0.30, "half", "Helvetica", 13, "0", sound$
        Colour: "{0.45, 0.45, 0.55}"
        sysWord$ = "treble"
        if staff_system = 2
            sysWord$ = "bass"
        elsif staff_system = 3
            sysWord$ = "grand staff"
        endif
        winLabel$ = ""
        if winFrom > 0 or winTo < duration - 0.0005
            winLabel$ = " | window " + fixed$(winFrom, 1) + "-" + fixed$(winTo, 1) + "s"
        endif
        Text special: leftMargin, "left", 0.62, "half", "Helvetica", 7, "0",
            ... "graphic score | " + presetName$ + " | " + sysWord$
            ... + " | holds: " + string$(hold_count)
            ... + " | " + fixed$(duration, 1) + "s" + winLabel$
        if nPages > 1
            .s1 = (.page - 1) * systemsPerPage + 1
            .s2 = min(.page * systemsPerPage, nSystems)
            .t0 = winFrom + (.s1 - 1) * seconds_per_system
            .t1 = min(winTo, winFrom + .s2 * seconds_per_system)
            # fixed$(0, 1) prints a bare "0"; spell zero out so labels align
            if .t0 < 0.05
                .t0$ = "0.0"
            else
                .t0$ = fixed$(.t0, 1)
            endif
            Colour: "{0.12, 0.12, 0.12}"
            Text special: canvasW - rightMargin, "right", 0.62, "half", "Helvetica", 8, "0",
                ... "p. " + string$(.page) + " / " + string$(nPages) + "   " + .t0$ + "-" + fixed$(.t1, 1) + " s"
        endif
        Colour: "{0.45, 0.45, 0.55}"
        Text special: canvasW - rightMargin, "right", 0.30, "half", "Helvetica", 7, "0", "Praat AudioTools"
    endif
endproc

procedure drawPage: .page
    Erase all
    Helvetica
    .s1 = (.page - 1) * systemsPerPage + 1
    .s2 = min(.page * systemsPerPage, nSystems)
    for .s from .s1 to .s2
        @drawSystem: .s, .s - .s1 + 1
    endfor
    @drawTitle: .page
    # leave the selection on the whole page (Save / Copy from the GUI
    # then captures the full page, not the last system)
    Select outer viewport: 0, canvasW, 0, pageH
    currentPage = .page
endproc

# ========================================================================================
# STEP 8: PNG EXPORT HELPERS
# ========================================================================================

pngDir$ = ""
pngAsked = 0
procedure resolvePngDir
    if pngAsked = 0
        pngAsked = 1
        pngDir$ = png_folder$
        if pngDir$ = ""
            pngDir$ = chooseDirectory$: "Choose a folder to save the score pages"
        endif
        if pngDir$ <> ""
            if right$(pngDir$, 1) <> "/" and right$(pngDir$, 1) <> "\"
                if index(pngDir$, "\") > 0
                    pngDir$ = pngDir$ + "\"
                else
                    pngDir$ = pngDir$ + "/"
                endif
            endif
        endif
    endif
endproc

# Safe base filename from the sound name (alnum / dash / underscore).
safeName$ = ""
for ci from 1 to length(sound$)
    ch$ = mid$(sound$, ci, 1)
    if index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", ch$) > 0
        safeName$ = safeName$ + ch$
    else
        safeName$ = safeName$ + "_"
    endif
endfor
if safeName$ = ""
    safeName$ = "score"
endif
winTag$ = ""
if winFrom > 0 or winTo < duration - 0.0005
    winTag$ = "_" + fixed$(winFrom, 1) + "-" + fixed$(winTo, 1) + "s"
endif

pngSaved = 0
pngFailed = 0
procedure exportAllPages
    @resolvePngDir
    if pngDir$ = ""
        appendInfoLine: "PNG export cancelled (no folder chosen)."
    else
        .keep = currentPage
        for .p from 1 to nPages
            @drawPage: .p
            if nPages > 1
                .path$ = pngDir$ + safeName$ + "_score" + winTag$ + "_p" + if .p < 10 then "0" else "" fi + string$(.p) + ".png"
            else
                .path$ = pngDir$ + safeName$ + "_score" + winTag$ + ".png"
            endif
            Select outer viewport: 0, canvasW, 0, pageH
            if png_dpi = 2
                nocheck Save as 600-dpi PNG file: .path$
            else
                nocheck Save as 300-dpi PNG file: .path$
            endif
            if fileReadable(.path$)
                pngSaved += 1
                appendInfoLine: "  saved ", .path$
            else
                pngFailed += 1
                appendInfoLine: "  FAILED (check folder exists / is writable): ", .path$
            endif
        endfor
        @drawPage: .keep
    endif
endproc

# ========================================================================================
# STEP 9: RENDER - browse pages, export
# ========================================================================================

appendInfoLine: "Drawing page 1 of ", nPages, "..."
@drawPage: 1

if save_png
    appendInfoLine: ""
    appendInfoLine: "Exporting ", nPages, " page(s)..."
    @exportAllPages
endif

if browse_pages and nPages > 1
    browsing = 1
    while browsing
        @drawPage: currentPage
        beginPause: "Score page " + string$(currentPage) + " of " + string$(nPages)
            comment: "Page " + string$(currentPage) + " of " + string$(nPages) + " is in the Picture window."
            comment: "Export all saves every page as a numbered PNG."
        # buttons depend on the position; on the last page the default is
        # Done, so an environment that auto-answers dialogs cannot loop
        if currentPage = 1
            btn$[1] = "next"
            btn$[2] = "export"
            btn$[3] = "done"
            nBtn = 3
            clicked = endPause: "Next", "Export all", "Done", 1, 3
        elsif currentPage = nPages
            btn$[1] = "prev"
            btn$[2] = "export"
            btn$[3] = "done"
            nBtn = 3
            clicked = endPause: "Previous", "Export all", "Done", 3, 3
        else
            btn$[1] = "prev"
            btn$[2] = "next"
            btn$[3] = "export"
            btn$[4] = "done"
            nBtn = 4
            clicked = endPause: "Previous", "Next", "Export all", "Done", 2, 4
        endif
        # Headless Praat (praat_nogui --run, 6.4.06) auto-continues a pause
        # and returns 0, not the default button: treat anything outside the
        # button range as Done so the browser can never loop or crash.
        if clicked < 1 or clicked > nBtn
            act$ = "done"
        else
            act$ = btn$[clicked]
        endif
        if act$ = "next"
            currentPage = min(nPages, currentPage + 1)
        elsif act$ = "prev"
            currentPage = max(1, currentPage - 1)
        elsif act$ = "export"
            @exportAllPages
        else
            browsing = 0
        endif
    endwhile
endif

# ========================================================================================
# CLEANUP
# ========================================================================================

appendInfoLine: ""
appendInfoLine: "=== SCORE COMPLETE ==="
appendInfoLine: "Frames: ", numFrames
appendInfoLine: "Held notes: ", hold_count
appendInfoLine: "Systems: ", nSystems, "   pages: ", nPages, " (", systemsPerPage, " systems per page)"
if pngSaved + pngFailed > 0
    appendInfoLine: "PNG pages saved: ", pngSaved, if pngFailed > 0 then "   FAILED: " + string$(pngFailed) else "" fi
endif
appendInfoLine: "Pitch range (MIDI): ", scoreMidiMin, " - ", scoreMidiMax

removeObject: pitchID, intensityID

selectObject: soundID
Play
