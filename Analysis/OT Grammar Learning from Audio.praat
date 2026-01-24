# ============================================================
# Praat AudioTools - OT Grammar Learning from Audio
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Optimality Theory (OT) melodic analysis. Extracts melody from
#   audio using pitch detection, quantizes to scale, and evaluates
#   against ranked melodic well-formedness constraints. Outputs
#   violation counts, weighted scores, and interval statistics.
#
# Changelog v0.3:
#   - Added constraint ranking with weights
#   - Added visualization (piano roll, constraint chart, intervals)
#   - Added output Table with results
#   - Added interval histogram
#   - Fixed scale pitch class definitions
#   - Added more minor scales
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Melody OT Analysis
    comment === Instrument ===
    optionmenu Instrument: 1
        option Violin
        option Vocal
        option Guitar
        option Flute
        option Piano
        option Other
    comment === Scale ===
    optionmenu Scale: 1
        option C major
        option G major
        option D major
        option A major
        option E major
        option F major
        option Bb major
        option Eb major
        option A minor (natural)
        option E minor (natural)
        option D minor (natural)
        option A minor (harmonic)
        option Chromatic (no quantization)
    boolean Quantize_to_scale 1
    comment === Constraint Ranking ===
    optionmenu Ranking_preset: 1
        option Default (balanced)
        option Prefer stepwise motion
        option Prefer leaps allowed
        option Strict tonal
        option Free atonal
    comment === Output ===
    boolean Show_visualization 1
    boolean Create_output_table 1
endform

clearinfo

# =============================================================================
# INSTRUMENT-SPECIFIC PITCH DETECTION SETTINGS
# =============================================================================

if instrument = 1
    minPitch = 180
    maxPitch = 800
    timeStep = 0.005
    voicingThreshold = 0.25
    instrumentName$ = "Violin"
elsif instrument = 2
    minPitch = 75
    maxPitch = 600
    timeStep = 0.01
    voicingThreshold = 0.35
    instrumentName$ = "Vocal"
elsif instrument = 3
    minPitch = 80
    maxPitch = 500
    timeStep = 0.01
    voicingThreshold = 0.30
    instrumentName$ = "Guitar"
elsif instrument = 4
    minPitch = 200
    maxPitch = 2000
    timeStep = 0.005
    voicingThreshold = 0.40
    instrumentName$ = "Flute"
elsif instrument = 5
    minPitch = 50
    maxPitch = 2000
    timeStep = 0.01
    voicingThreshold = 0.45
    instrumentName$ = "Piano"
else
    minPitch = 75
    maxPitch = 600
    timeStep = 0.01
    voicingThreshold = 0.35
    instrumentName$ = "Other"
endif

# =============================================================================
# SCALE DEFINITION (Fixed pitch classes)
# =============================================================================

if scale = 1
    scaleName$ = "C major"
    scalePC$ = "0 2 4 5 7 9 11"
    tonicPC = 0
elsif scale = 2
    scaleName$ = "G major"
    scalePC$ = "2 4 6 7 9 11 0"
    tonicPC = 7
elsif scale = 3
    scaleName$ = "D major"
    scalePC$ = "1 2 4 6 9 11 0"
    tonicPC = 2
elsif scale = 4
    scaleName$ = "A major"
    scalePC$ = "1 2 4 6 8 9 11"
    tonicPC = 9
elsif scale = 5
    scaleName$ = "E major"
    scalePC$ = "1 3 4 6 8 9 11"
    tonicPC = 4
elsif scale = 6
    scaleName$ = "F major"
    scalePC$ = "0 2 4 5 7 9 10"
    tonicPC = 5
elsif scale = 7
    scaleName$ = "Bb major"
    scalePC$ = "0 2 3 5 7 9 10"
    tonicPC = 10
elsif scale = 8
    scaleName$ = "Eb major"
    scalePC$ = "0 2 3 5 7 8 10"
    tonicPC = 3
elsif scale = 9
    scaleName$ = "A minor (nat)"
    scalePC$ = "0 2 4 5 7 9 10"
    tonicPC = 9
elsif scale = 10
    scaleName$ = "E minor (nat)"
    scalePC$ = "0 2 4 6 7 9 11"
    tonicPC = 4
elsif scale = 11
    scaleName$ = "D minor (nat)"
    scalePC$ = "0 2 3 5 7 9 10"
    tonicPC = 2
elsif scale = 12
    scaleName$ = "A minor (harm)"
    scalePC$ = "0 2 4 5 8 9 11"
    tonicPC = 9
else
    scaleName$ = "Chromatic"
    scalePC$ = "0 1 2 3 4 5 6 7 8 9 10 11"
    tonicPC = 0
    quantize_to_scale = 0
endif

# =============================================================================
# CONSTRAINT WEIGHTS (OT Ranking)
# =============================================================================

# Default weights
w_leap = 3.0
w_tritone = 4.0
w_nonstep = 1.0
w_repeat = 1.5
w_semitone = 0.5
w_wide = 2.0
w_narrow = 1.5
w_nonscale = 5.0
w_cadence = 2.0
w_end = 3.0
w_peak_early = 1.0
w_peak_late = 0.5
w_arc = 1.5
w_dirchange = 1.0
w_monotonic = 1.0

if ranking_preset = 2
    # Prefer stepwise motion
    w_leap = 5.0
    w_nonstep = 3.0
    w_semitone = 0.0
elsif ranking_preset = 3
    # Prefer leaps allowed
    w_leap = 0.5
    w_nonstep = 0.5
    w_tritone = 2.0
elsif ranking_preset = 4
    # Strict tonal
    w_nonscale = 10.0
    w_end = 5.0
    w_cadence = 4.0
    w_tritone = 6.0
elsif ranking_preset = 5
    # Free atonal
    w_nonscale = 0.0
    w_end = 0.0
    w_cadence = 0.0
    w_tritone = 0.0
endif

# Parse scale pitch classes
@parseScale: scalePC$

# =============================================================================
# INPUT VALIDATION & MELODY EXTRACTION
# =============================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency

writeInfoLine: "=== OT Melody Analysis v0.3 ==="
appendInfoLine: "File: ", soundName$
appendInfoLine: "Instrument: ", instrumentName$
appendInfoLine: "Scale: ", scaleName$
if quantize_to_scale
    appendInfoLine: "Quantization: ON"
else
    appendInfoLine: "Quantization: OFF"
endif
appendInfoLine: "Ranking: ", ranking_preset$
appendInfoLine: ""

# Pitch detection
selectObject: soundID
pitchID = To Pitch (ac): timeStep, minPitch, 15, "no", 0.03, voicingThreshold, 0.01, 0.35, 0.14, maxPitch

selectObject: pitchID
melody$ = ""
lastMIDI = -999
numFrames = Get number of frames

# Store note times for visualization
maxNotes = 1000
noteTimes# = zero#(maxNotes)
noteCount = 0

for frame to numFrames
    f0 = Get value in frame: frame, "Hertz"
    
    if f0 <> undefined and f0 > 0
        midi = 69 + 12 * log2(f0 / 440)
        midiRound = round(midi)
        
        if quantize_to_scale
            pc = midiRound mod 12
            if pc < 0
                pc = pc + 12
            endif
            octave = floor(midiRound / 12)
            
            @quantizeToScale: pc
            quantPC = quantized_pc
            
            midiRound = octave * 12 + quantPC
        endif
        
        if midiRound <> lastMIDI
            if melody$ <> ""
                melody$ = melody$ + " "
            endif
            melody$ = melody$ + string$(midiRound)
            lastMIDI = midiRound
            
            noteCount += 1
            if noteCount <= maxNotes
                t = Get time from frame number: frame
                noteTimes#[noteCount] = t
            endif
        endif
    endif
endfor

removeObject: pitchID

if melody$ = ""
    melody$ = "60"
    noteCount = 1
    noteTimes#[1] = 0
endif

appendInfoLine: "=== EXTRACTED MELODY ==="
appendInfoLine: melody$
appendInfoLine: ""

@parseMelody: melody$
numNotes = parsed_count

appendInfoLine: "Number of notes: ", numNotes
appendInfoLine: ""

# =============================================================================
# INTERVAL ANALYSIS
# =============================================================================

# Count intervals from -12 to +12 semitones (index 1-25)
interval_counts# = zero#(25)

for i from 2 to numNotes
    interval = notes[i] - notes[i-1]
    # Map -12..+12 to 1..25
    idx = interval + 13
    if idx >= 1 and idx <= 25
        interval_counts#[idx] += 1
    endif
endfor

# =============================================================================
# CONSTRAINT EVALUATION
# =============================================================================

appendInfoLine: "=== CONSTRAINT VIOLATIONS ==="
appendInfoLine: ""
appendInfoLine: "Constraint               Violations  Weight  Score"
appendInfoLine: "------------------------------------------------"

# Calculate all violations
v_faith = 0

@countLeaps
v_leap = result
score_leap = v_leap * w_leap

@countTritones
v_tritone = result
score_tritone = v_tritone * w_tritone

@countNonSteps
v_nonstep = result
score_nonstep = v_nonstep * w_nonstep

@countRepeats
v_repeat = result
score_repeat = v_repeat * w_repeat

@countSemitones
v_semitones = result
score_semitones = v_semitones * w_semitone

@analyzeRange
v_wide = range_wide
v_narrow = range_narrow
score_wide = v_wide * w_wide
score_narrow = v_narrow * w_narrow
melodic_range = range_value

@countNonScale
v_nonscale = result
score_nonscale = v_nonscale * w_nonscale

@checkCadence
v_cadence = result
score_cadence = v_cadence * w_cadence

@checkTonicEnding
v_end = result
score_end = v_end * w_end

@analyzePeakPosition
v_peak_early = peak_early
v_peak_late = peak_late
score_peak_early = v_peak_early * w_peak_early
score_peak_late = v_peak_late * w_peak_late

@checkArcShape
v_arc = result
score_arc = v_arc * w_arc

@countDirectionChanges
v_dirchange = result
score_dirchange = v_dirchange * w_dirchange

@checkMonotonic
v_monotonic = result
score_monotonic = v_monotonic * w_monotonic

# Report
appendInfoLine: "*LEAP (>5 st)            ", v_leap, "           ", fixed$(w_leap, 1), "     ", fixed$(score_leap, 1)
appendInfoLine: "*TRITONE                 ", v_tritone, "           ", fixed$(w_tritone, 1), "     ", fixed$(score_tritone, 1)
appendInfoLine: "STEP (>2 st)             ", v_nonstep, "           ", fixed$(w_nonstep, 1), "     ", fixed$(score_nonstep, 1)
appendInfoLine: "*REPEAT                  ", v_repeat, "           ", fixed$(w_repeat, 1), "     ", fixed$(score_repeat, 1)
appendInfoLine: "SEMITONE                 ", v_semitones, "           ", fixed$(w_semitone, 1), "     ", fixed$(score_semitones, 1)
appendInfoLine: "*WIDE-RANGE              ", v_wide, "           ", fixed$(w_wide, 1), "     ", fixed$(score_wide, 1)
appendInfoLine: "*NARROW-RANGE            ", v_narrow, "           ", fixed$(w_narrow, 1), "     ", fixed$(score_narrow, 1)
appendInfoLine: "*NON-SCALE               ", v_nonscale, "           ", fixed$(w_nonscale, 1), "     ", fixed$(score_nonscale, 1)
appendInfoLine: "CADENCE                  ", v_cadence, "           ", fixed$(w_cadence, 1), "     ", fixed$(score_cadence, 1)
appendInfoLine: "*END (non-tonic)         ", v_end, "           ", fixed$(w_end, 1), "     ", fixed$(score_end, 1)
appendInfoLine: "*PEAK-EARLY              ", v_peak_early, "           ", fixed$(w_peak_early, 1), "     ", fixed$(score_peak_early, 1)
appendInfoLine: "*PEAK-LATE               ", v_peak_late, "           ", fixed$(w_peak_late, 1), "     ", fixed$(score_peak_late, 1)
appendInfoLine: "ARC                      ", v_arc, "           ", fixed$(w_arc, 1), "     ", fixed$(score_arc, 1)
appendInfoLine: "*DIR-CHANGE              ", v_dirchange, "           ", fixed$(w_dirchange, 1), "     ", fixed$(score_dirchange, 1)
appendInfoLine: "MONOTONIC                ", v_monotonic, "           ", fixed$(w_monotonic, 1), "     ", fixed$(score_monotonic, 1)

total_violations = v_leap + v_tritone + v_nonstep + v_repeat + v_semitones + v_wide + v_narrow + v_nonscale + v_cadence + v_end + v_peak_early + v_peak_late + v_arc + v_dirchange + v_monotonic

total_score = score_leap + score_tritone + score_nonstep + score_repeat + score_semitones + score_wide + score_narrow + score_nonscale + score_cadence + score_end + score_peak_early + score_peak_late + score_arc + score_dirchange + score_monotonic

appendInfoLine: "------------------------------------------------"
appendInfoLine: "TOTAL                    ", total_violations, "                   ", fixed$(total_score, 1)
appendInfoLine: ""

# Melodic quality rating
if total_score < 5
    quality$ = "Excellent"
elsif total_score < 15
    quality$ = "Good"
elsif total_score < 30
    quality$ = "Fair"
elsif total_score < 50
    quality$ = "Poor"
else
    quality$ = "Very Poor"
endif

appendInfoLine: "Melodic Quality: ", quality$, " (score: ", fixed$(total_score, 1), ")"
appendInfoLine: "Range: ", melodic_range, " semitones"

# =============================================================================
# VISUALIZATION
# =============================================================================

if show_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "OT Melody Analysis: " + soundName$ + " [" + scaleName$ + "]"
    
    # --- Piano roll ---
    Select outer viewport: 0, 8, 0.6, 2.2
    Select inner viewport: 0.5, 7.5, 0.7, 2.1
    
    # Find note range
    minNote = notes[1]
    maxNote = notes[1]
    for i from 2 to numNotes
        if notes[i] < minNote
            minNote = notes[i]
        endif
        if notes[i] > maxNote
            maxNote = notes[i]
        endif
    endfor
    
    Axes: 0, duration, minNote - 2, maxNote + 2
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, minNote - 2, maxNote + 2
    
    # Draw piano roll grid
    Colour: "{0.9, 0.9, 0.9}"
    for n from minNote - 1 to maxNote + 1
        pc = n mod 12
        if pc < 0
            pc = pc + 12
        endif
        # Highlight scale tones
        inScale = 0
        for j to numScalePCs
            if pc = scalePCs[j]
                inScale = 1
            endif
        endfor
        if inScale
            col$ = "{0.85, 0.9, 0.85}"
        else
            col$ = "{0.95, 0.92, 0.92}"
        endif
        Paint rectangle: col$, 0, duration, n - 0.4, n + 0.4
    endfor
    
    # Draw notes
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    for i from 2 to numNotes
        t1 = noteTimes#[i-1]
        t2 = noteTimes#[i]
        if t2 > duration
            t2 = duration
        endif
        
        # Draw note as horizontal bar
        Draw line: t1, notes[i-1], t2, notes[i-1]
        # Draw connection
        Colour: "{0.5, 0.5, 0.5}"
        Line width: 1
        Draw line: t2, notes[i-1], t2, notes[i]
        Colour: "{0.2, 0.5, 0.8}"
        Line width: 2
    endfor
    # Last note
    if numNotes > 0
        t1 = noteTimes#[numNotes]
        Draw line: t1, notes[numNotes], duration, notes[numNotes]
    endif
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "MIDI"
    Text bottom: "yes", "Time (s)"
    
    # --- Interval histogram ---
    Select outer viewport: 0, 4, 2.4, 3.8
    Select inner viewport: 0.5, 3.8, 2.5, 3.7
    
    # Find max count
    maxCount = 1
    for i to 25
        if interval_counts#[i] > maxCount
            maxCount = interval_counts#[i]
        endif
    endfor
    
    Axes: -12, 12, 0, maxCount * 1.1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", -12, 12, 0, maxCount * 1.1
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, 0, maxCount * 1.1
    
    # Draw bars
    for i to 25
        interval = i - 13
        count = interval_counts#[i]
        if count > 0
            if abs(interval) <= 2
                col$ = "{0.4, 0.7, 0.4}"
            elsif abs(interval) <= 5
                col$ = "{0.7, 0.7, 0.4}"
            elsif abs(interval) = 6
                col$ = "{0.8, 0.4, 0.4}"
            else
                col$ = "{0.6, 0.5, 0.7}"
            endif
            Paint rectangle: col$, interval - 0.4, interval + 0.4, 0, count
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Count"
    Text bottom: "yes", "Interval (semitones)"
    
    # --- Constraint violation chart ---
    Select outer viewport: 4, 8, 2.4, 3.8
    Select inner viewport: 4.5, 7.8, 2.5, 3.7
    
    # Top 8 constraints by weighted score
    scores# = {score_leap, score_tritone, score_nonstep, score_nonscale, score_end, score_cadence, score_wide, score_dirchange}
    names$[1] = "LEAP"
    names$[2] = "TRIT"
    names$[3] = "STEP"
    names$[4] = "NSCL"
    names$[5] = "END"
    names$[6] = "CAD"
    names$[7] = "WIDE"
    names$[8] = "DIR"
    
    maxScore = 1
    for i to 8
        if scores#[i] > maxScore
            maxScore = scores#[i]
        endif
    endfor
    
    Axes: 0, 9, 0, maxScore * 1.2
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 9, 0, maxScore * 1.2
    
    for i to 8
        if scores#[i] > 0
            col$ = "{0.8, 0.4, 0.4}"
        else
            col$ = "{0.7, 0.8, 0.7}"
        endif
        Paint rectangle: col$, i - 0.35, i + 0.35, 0, max(0.1, scores#[i])
        
        Font size: 5
        Colour: "Black"
        Text: i, "centre", -maxScore * 0.1, "half", names$[i]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Score"
    Text bottom: "yes", "Constraint"
    
    # --- Summary ---
    Select outer viewport: 0, 8, 3.9, 4.3
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Quality: " + quality$ + " | Score: " + fixed$(total_score, 1) + " | Notes: " + string$(numNotes) + " | Range: " + string$(melodic_range) + " st | Violations: " + string$(total_violations)
    
    Font size: 10
    Colour: "Black"
endif

# =============================================================================
# OUTPUT TABLE
# =============================================================================

if create_output_table
    table = Create Table with column names: "OT_Analysis_" + soundName$, 15, "constraint violations weight score"
    
    selectObject: table
    Set string value: 1, "constraint", "*LEAP"
    Set numeric value: 1, "violations", v_leap
    Set numeric value: 1, "weight", w_leap
    Set numeric value: 1, "score", score_leap
    
    Set string value: 2, "constraint", "*TRITONE"
    Set numeric value: 2, "violations", v_tritone
    Set numeric value: 2, "weight", w_tritone
    Set numeric value: 2, "score", score_tritone
    
    Set string value: 3, "constraint", "STEP"
    Set numeric value: 3, "violations", v_nonstep
    Set numeric value: 3, "weight", w_nonstep
    Set numeric value: 3, "score", score_nonstep
    
    Set string value: 4, "constraint", "*REPEAT"
    Set numeric value: 4, "violations", v_repeat
    Set numeric value: 4, "weight", w_repeat
    Set numeric value: 4, "score", score_repeat
    
    Set string value: 5, "constraint", "SEMITONE"
    Set numeric value: 5, "violations", v_semitones
    Set numeric value: 5, "weight", w_semitone
    Set numeric value: 5, "score", score_semitones
    
    Set string value: 6, "constraint", "*WIDE-RANGE"
    Set numeric value: 6, "violations", v_wide
    Set numeric value: 6, "weight", w_wide
    Set numeric value: 6, "score", score_wide
    
    Set string value: 7, "constraint", "*NARROW-RANGE"
    Set numeric value: 7, "violations", v_narrow
    Set numeric value: 7, "weight", w_narrow
    Set numeric value: 7, "score", score_narrow
    
    Set string value: 8, "constraint", "*NON-SCALE"
    Set numeric value: 8, "violations", v_nonscale
    Set numeric value: 8, "weight", w_nonscale
    Set numeric value: 8, "score", score_nonscale
    
    Set string value: 9, "constraint", "CADENCE"
    Set numeric value: 9, "violations", v_cadence
    Set numeric value: 9, "weight", w_cadence
    Set numeric value: 9, "score", score_cadence
    
    Set string value: 10, "constraint", "*END"
    Set numeric value: 10, "violations", v_end
    Set numeric value: 10, "weight", w_end
    Set numeric value: 10, "score", score_end
    
    Set string value: 11, "constraint", "*PEAK-EARLY"
    Set numeric value: 11, "violations", v_peak_early
    Set numeric value: 11, "weight", w_peak_early
    Set numeric value: 11, "score", score_peak_early
    
    Set string value: 12, "constraint", "*PEAK-LATE"
    Set numeric value: 12, "violations", v_peak_late
    Set numeric value: 12, "weight", w_peak_late
    Set numeric value: 12, "score", score_peak_late
    
    Set string value: 13, "constraint", "ARC"
    Set numeric value: 13, "violations", v_arc
    Set numeric value: 13, "weight", w_arc
    Set numeric value: 13, "score", score_arc
    
    Set string value: 14, "constraint", "*DIR-CHANGE"
    Set numeric value: 14, "violations", v_dirchange
    Set numeric value: 14, "weight", w_dirchange
    Set numeric value: 14, "score", score_dirchange
    
    Set string value: 15, "constraint", "MONOTONIC"
    Set numeric value: 15, "violations", v_monotonic
    Set numeric value: 15, "weight", w_monotonic
    Set numeric value: 15, "score", score_monotonic
    
    appendInfoLine: ""
    appendInfoLine: "Created output Table: OT_Analysis_", soundName$
endif

appendInfoLine: ""
appendInfoLine: "Done!"

selectObject: soundID

# =============================================================================
# PROCEDURES
# =============================================================================

procedure parseScale: .scaleString$
    .remaining$ = .scaleString$ + " "
    .count = 0
    
    while index(.remaining$, " ") > 0
        .spacePos = index(.remaining$, " ")
        .token$ = left$(.remaining$, .spacePos - 1)
        .remaining$ = mid$(.remaining$, .spacePos + 1, 10000)
        
        if .token$ <> ""
            .count = .count + 1
            scalePCs[.count] = number(.token$)
        endif
    endwhile
    
    numScalePCs = .count
endproc

procedure quantizeToScale: .pc
    .minDist = 12
    .closestPC = 0
    
    for .i to numScalePCs
        .scalePC = scalePCs[.i]
        .dist1 = abs(.pc - .scalePC)
        .dist2 = abs(.pc - (.scalePC + 12))
        .dist3 = abs(.pc - (.scalePC - 12))
        
        .dist = .dist1
        if .dist2 < .dist
            .dist = .dist2
        endif
        if .dist3 < .dist
            .dist = .dist3
        endif
        
        if .dist < .minDist
            .minDist = .dist
            .closestPC = .scalePC
        endif
    endfor
    
    quantized_pc = .closestPC
endproc

procedure parseMelody: .melody$
    .remaining$ = .melody$ + " "
    .count = 0
    
    while index(.remaining$, " ") > 0
        .spacePos = index(.remaining$, " ")
        .token$ = left$(.remaining$, .spacePos - 1)
        .remaining$ = mid$(.remaining$, .spacePos + 1, 10000)
        
        if .token$ <> ""
            .count = .count + 1
            notes[.count] = number(.token$)
        endif
    endwhile
    
    parsed_count = .count
endproc

procedure countLeaps
    .leaps = 0
    for .i from 2 to numNotes
        .interval = abs(notes[.i] - notes[.i-1])
        if .interval > 5
            .leaps = .leaps + 1
        endif
    endfor
    result = .leaps
endproc

procedure countTritones
    .tritones = 0
    for .i from 2 to numNotes
        .interval = abs(notes[.i] - notes[.i-1])
        if .interval = 6
            .tritones = .tritones + 1
        endif
    endfor
    result = .tritones
endproc

procedure countNonSteps
    .nonsteps = 0
    for .i from 2 to numNotes
        .interval = abs(notes[.i] - notes[.i-1])
        if .interval > 2
            .nonsteps = .nonsteps + 1
        endif
    endfor
    result = .nonsteps
endproc

procedure countRepeats
    .repeats = 0
    for .i from 2 to numNotes
        if notes[.i] = notes[.i-1]
            .repeats = .repeats + 1
        endif
    endfor
    result = .repeats
endproc

procedure countSemitones
    .count = 0
    for .i from 2 to numNotes
        .interval = abs(notes[.i] - notes[.i-1])
        if .interval = 1
            .count = .count + 1
        endif
    endfor
    result = .count
endproc

procedure analyzeRange
    .min = notes[1]
    .max = notes[1]
    
    for .i from 2 to numNotes
        if notes[.i] < .min
            .min = notes[.i]
        endif
        if notes[.i] > .max
            .max = notes[.i]
        endif
    endfor
    
    .range = .max - .min
    range_value = .range
    
    if .range > 12
        range_wide = 1
    else
        range_wide = 0
    endif
    
    if .range < 7
        range_narrow = 1
    else
        range_narrow = 0
    endif
endproc

procedure countNonScale
    .violations = 0
    
    for .i to numNotes
        .pc = notes[.i] mod 12
        if .pc < 0
            .pc = .pc + 12
        endif
        .inScale = 0
        
        for .j to numScalePCs
            if .pc = scalePCs[.j]
                .inScale = 1
            endif
        endfor
        
        if .inScale = 0
            .violations = .violations + 1
        endif
    endfor
    
    result = .violations
endproc

procedure checkCadence
    if numNotes < 2
        result = 1
    else
        .last = notes[numNotes] mod 12
        if .last < 0
            .last = .last + 12
        endif
        .penult = notes[numNotes - 1] mod 12
        if .penult < 0
            .penult = .penult + 12
        endif
        
        # Check for standard cadential approaches to tonic
        # Leading tone (semitone below) or supertonic (whole tone above) or dominant (5th)
        .leadingTone = (tonicPC - 1 + 12) mod 12
        .supertonic = (tonicPC + 2) mod 12
        .dominant = (tonicPC + 7) mod 12
        
        if .last = tonicPC and (.penult = .leadingTone or .penult = .supertonic or .penult = .dominant)
            result = 0
        else
            result = 1
        endif
    endif
endproc

procedure checkTonicEnding
    .last = notes[numNotes] mod 12
    if .last < 0
        .last = .last + 12
    endif
    
    if .last <> tonicPC
        result = 1
    else
        result = 0
    endif
endproc

procedure analyzePeakPosition
    .maxNote = notes[1]
    .maxPos = 1
    
    for .i from 2 to numNotes
        if notes[.i] > .maxNote
            .maxNote = notes[.i]
            .maxPos = .i
        endif
    endfor
    
    .midpoint = numNotes / 2
    
    if .maxPos <= .midpoint
        peak_early = 1
    else
        peak_early = 0
    endif
    
    if .maxPos > .midpoint
        peak_late = 1
    else
        peak_late = 0
    endif
endproc

procedure checkArcShape
    if numNotes < 3
        result = 0
    else
        .maxNote = notes[1]
        .maxPos = 1
        
        for .i from 2 to numNotes
            if notes[.i] > .maxNote
                .maxNote = notes[.i]
                .maxPos = .i
            endif
        endfor
        
        .ascendingViolations = 0
        for .i from 2 to .maxPos
            if notes[.i] < notes[.i-1]
                .ascendingViolations = .ascendingViolations + 1
            endif
        endfor
        
        .descendingViolations = 0
        for .i from (.maxPos + 1) to numNotes
            if notes[.i] > notes[.i-1]
                .descendingViolations = .descendingViolations + 1
            endif
        endfor
        
        .totalViolations = .ascendingViolations + .descendingViolations
        if .totalViolations > (numNotes / 4)
            result = 1
        else
            result = 0
        endif
    endif
endproc

procedure countDirectionChanges
    .changes = 0
    
    if numNotes < 3
        result = 0
    else
        for .i from 3 to numNotes
            .prev_dir = notes[.i-1] - notes[.i-2]
            .curr_dir = notes[.i] - notes[.i-1]
            
            if .prev_dir > 0 and .curr_dir < 0
                .changes = .changes + 1
            elsif .prev_dir < 0 and .curr_dir > 0
                .changes = .changes + 1
            endif
        endfor
        
        if .changes > (numNotes / 3)
            result = 1
        else
            result = 0
        endif
    endif
endproc

procedure checkMonotonic
    if numNotes < 2
        result = 0
    else
        .ascending = 0
        .descending = 0
        
        for .i from 2 to numNotes
            if notes[.i] > notes[.i-1]
                .ascending = .ascending + 1
            elsif notes[.i] < notes[.i-1]
                .descending = .descending + 1
            endif
        endfor
        
        .total_moves = .ascending + .descending
        .dominant = .ascending
        if .descending > .ascending
            .dominant = .descending
        endif
        
        if .total_moves > 0
            .ratio = .dominant / .total_moves
            if .ratio < 0.6
                result = 1
            else
                result = 0
            endif
        else
            result = 0
        endif
    endif
endproc