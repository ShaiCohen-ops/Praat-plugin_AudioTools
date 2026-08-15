# ============================================================
# Praat AudioTools - Random_Walk_Melody.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (layout fix 2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generates a melody from a bounded discrete random walk on scale degrees.
#   At each note transition, a Bernoulli decision with probability p either
#   holds the current degree or chooses uniformly among all legal, non-zero
#   steps up to Max_step_size.  This makes Step_probability the actual
#   probability of changing pitch, without extra zero-steps or sticky clamps.
#
#   The selected scale maps degree -> frequency.  Each note is synthesized as
#   a phase-reset sine inside a Hann window, and the final sound is normalized
#   once at the end.
#
# Visualization is mechanism-first:
#   A. random walk decisions (hold / signed legal step),
#   B. bounded degree trajectory,
#   C. scale-to-frequency mapping + analytical note kernel,
#   D. measured output waveform, followed by QC.
#
# Changelog v0.4.1:
#   - Fixed Picture viewport inheritance that caused title/QC text collisions.
#   - Gave title, process, panel labels, formula, and QC their own inner viewports.
#   - Increased vertical separation around axes and panel labels.
#   - Replaced long QC lines with six short fields in a two-row summary bar.
#
# Changelog v0.4:
#   - Fixed Step_probability semantics: moving no longer draws a zero step.
#   - Removed clamp-induced edge sticking by sampling only legal non-zero steps.
#   - Added true 12-TET Chromatic scale; Chromatic Drift is now actually chromatic.
#   - Clarified 12-TET Major as a separate seven-degree scale.
#   - Uses ceiling(Duration / Note_duration), so a partial final note fills the
#     requested duration instead of leaving an unintended silent tail.
#   - Reset oscillator phase at each note; Hann window still gives zero endpoints.
#   - Added optional deterministic seed, output peak, sample-rate validation,
#     and scale-degree override on a compact Details page.
#   - Removed redundant global fades; each Hann-windowed note already starts
#     and ends smoothly at zero.
#   - Rebuilt visualization around the generating mechanism rather than a
#     spectrogram of the result.
# ============================================================

# ============================================================
# COMPACT FORM
# ============================================================
form Random Walk Melody v0.4.1
    optionmenu Preset 1
        option Custom
        option Slow Wandering
        option Quick Steps
        option Wide Leaps
        option Sticky Notes
        option Pentatonic Float
        option Chromatic Drift

    positive Duration_s 15.0
    positive Note_duration_s 0.5
    positive Base_frequency_Hz 220

    optionmenu Scale 1
        option Just Intonation Major (5-limit)
        option Equal Temperament Major (12-TET)
        option Major Pentatonic (5-limit)
        option Whole Tone (12-TET)
        option Chromatic (12-TET)

    real Step_probability 0.7
    integer Max_step_size 2

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS / OPTIONAL DETAILS
# ============================================================
sample_rate_Hz = 44100
scale_degrees_override = 0
output_peak = 0.9
random_seed = 0

if edit_details
    beginPause: "Random Walk Melody - Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        integer: "Scale degrees override (0 = full scale)", scale_degrees_override
        real: "Output peak (0..1]", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ============================================================
# PRESETS
# ============================================================
preset_name$ = "Custom"
scale_choice = scale

if preset = 2
    duration_s = 20.0
    note_duration_s = 0.8
    base_frequency_Hz = 180
    step_probability = 0.5
    max_step_size = 1
    scale_choice = 1
    preset_name$ = "SlowWandering"
elsif preset = 3
    duration_s = 12.0
    note_duration_s = 0.2
    base_frequency_Hz = 330
    step_probability = 0.9
    max_step_size = 1
    scale_choice = 1
    preset_name$ = "QuickSteps"
elsif preset = 4
    duration_s = 15.0
    note_duration_s = 0.4
    base_frequency_Hz = 220
    step_probability = 0.8
    max_step_size = 3
    scale_choice = 2
    preset_name$ = "WideLeaps"
elsif preset = 5
    duration_s = 15.0
    note_duration_s = 0.6
    base_frequency_Hz = 196
    step_probability = 0.3
    max_step_size = 1
    scale_choice = 1
    preset_name$ = "StickyNotes"
elsif preset = 6
    duration_s = 18.0
    note_duration_s = 0.5
    base_frequency_Hz = 261.63
    step_probability = 0.7
    max_step_size = 2
    scale_choice = 3
    preset_name$ = "PentatonicFloat"
elsif preset = 7
    duration_s = 10.0
    note_duration_s = 0.25
    base_frequency_Hz = 440
    step_probability = 0.85
    max_step_size = 1
    scale_choice = 5
    preset_name$ = "ChromaticDrift"
endif

# ============================================================
# VALIDATION
# ============================================================
if sample_rate_Hz < 1000
    exitScript: "Sample rate must be at least 1000 Hz."
endif
if step_probability < 0 or step_probability > 1
    exitScript: "Step probability must be between 0 and 1."
endif
if max_step_size < 1
    exitScript: "Max step size must be at least 1."
endif
if scale_degrees_override < 0
    exitScript: "Scale degrees override must be 0 or at least 2."
endif
if scale_degrees_override = 1
    exitScript: "Scale degrees override must be 0 or at least 2."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and at most 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (random) or a positive integer."
endif
if note_duration_s * sample_rate_Hz < 8
    exitScript: "Note duration is too short for the selected sample rate (need at least 8 samples per note)."
endif

# ============================================================
# SCALE TABLES
# ============================================================
# Just-intonation major, one octave without octave duplication.
jiRatio[1] = 1.0
jiRatio[2] = 9/8
jiRatio[3] = 5/4
jiRatio[4] = 4/3
jiRatio[5] = 3/2
jiRatio[6] = 5/3
jiRatio[7] = 15/8

# 12-TET major scale: 0, 2, 4, 5, 7, 9, 11 semitones.
etMajorRatio[1] = 1.0
etMajorRatio[2] = 2^(2/12)
etMajorRatio[3] = 2^(4/12)
etMajorRatio[4] = 2^(5/12)
etMajorRatio[5] = 2^(7/12)
etMajorRatio[6] = 2^(9/12)
etMajorRatio[7] = 2^(11/12)

# 5-limit major pentatonic.
pentRatio[1] = 1.0
pentRatio[2] = 9/8
pentRatio[3] = 5/4
pentRatio[4] = 3/2
pentRatio[5] = 5/3

# 12-TET whole-tone scale: 0, 2, 4, 6, 8, 10 semitones.
wtRatio[1] = 1.0
wtRatio[2] = 2^(2/12)
wtRatio[3] = 2^(4/12)
wtRatio[4] = 2^(6/12)
wtRatio[5] = 2^(8/12)
wtRatio[6] = 2^(10/12)

# True 12-TET chromatic collection: 0..11 semitones.
for .d to 12
    chromRatio[.d] = 2^((.d - 1) / 12)
endfor

if scale_choice = 1
    scale_name$ = "JI Major"
    scale_max_degrees = 7
elsif scale_choice = 2
    scale_name$ = "12-TET Major"
    scale_max_degrees = 7
elsif scale_choice = 3
    scale_name$ = "Major Pentatonic"
    scale_max_degrees = 5
elsif scale_choice = 4
    scale_name$ = "Whole Tone"
    scale_max_degrees = 6
else
    scale_name$ = "12-TET Chromatic"
    scale_max_degrees = 12
endif

scale_degrees = scale_max_degrees
if scale_degrees_override >= 2
    scale_degrees = min(scale_degrees_override, scale_max_degrees)
endif

effective_max_step = min(max_step_size, scale_degrees - 1)

# Materialize the selected degree -> ratio -> frequency mapping once.
for .d to scale_degrees
    if scale_choice = 1
        scaleRatio[.d] = jiRatio[.d]
    elsif scale_choice = 2
        scaleRatio[.d] = etMajorRatio[.d]
    elsif scale_choice = 3
        scaleRatio[.d] = pentRatio[.d]
    elsif scale_choice = 4
        scaleRatio[.d] = wtRatio[.d]
    else
        scaleRatio[.d] = chromRatio[.d]
    endif
    scaleFreq[.d] = base_frequency_Hz * scaleRatio[.d]
endfor

nyquist = sample_rate_Hz / 2
highest_frequency = scaleFreq[scale_degrees]
if highest_frequency >= 0.95 * nyquist
    exitScript: "Highest scale frequency (" + fixed$(highest_frequency, 2) + " Hz) must be below 95% of Nyquist (" + fixed$(0.95 * nyquist, 2) + " Hz)."
endif

# ============================================================
# RANDOM WALK
# ============================================================
uid$ = string$(randomInteger(10000, 99999))
notesPerChunk = 15
totalNotes = ceiling(duration_s / note_duration_s)
if totalNotes < 1
    totalNotes = 1
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

currentDegree = ceiling(scale_degrees / 2)
moveCount = 0
holdCount = 0
upCount = 0
downCount = 0
sumAbsStep = 0
edgeDecisionCount = 0

for n to totalNotes
    noteTime[n] = (n - 1) * note_duration_s
    noteDegree[n] = currentDegree
    noteFreq[n] = scaleFreq[currentDegree]

    # Transition n -> n+1.  A triggered move samples uniformly from the
    # legal non-zero offsets available at the CURRENT degree.  No zero draw,
    # no clamping, and therefore no artificial edge residence.
    walkStep[n] = 0
    if n < totalNotes
        if currentDegree = 1 or currentDegree = scale_degrees
            edgeDecisionCount = edgeDecisionCount + 1
        endif

        if randomUniform(0, 1) < step_probability
            leftSteps = min(effective_max_step, currentDegree - 1)
            rightSteps = min(effective_max_step, scale_degrees - currentDegree)
            legalChoices = leftSteps + rightSteps

            if legalChoices > 0
                choice = randomInteger(1, legalChoices)
                if choice <= leftSteps
                    step = -choice
                else
                    step = choice - leftSteps
                endif
                currentDegree = currentDegree + step
                walkStep[n] = step
                moveCount = moveCount + 1
                sumAbsStep = sumAbsStep + abs(step)
                if step > 0
                    upCount = upCount + 1
                else
                    downCount = downCount + 1
                endif
            else
                holdCount = holdCount + 1
            endif
        else
            holdCount = holdCount + 1
        endif
    endif
endfor

# Restore unpredictable RNG state so this script does not leave Praat's global
# generator deterministic after a reproducible run.
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

transitionCount = max(0, totalNotes - 1)
if transitionCount > 0
    realizedMoveProbability = moveCount / transitionCount
else
    realizedMoveProbability = 0
endif
if moveCount > 0
    meanAbsStep = sumAbsStep / moveCount
else
    meanAbsStep = 0
endif

# Pitch-range QC from the actual realization.
minDegree = noteDegree[1]
maxDegree = noteDegree[1]
minFreq = noteFreq[1]
maxFreq = noteFreq[1]
for n from 2 to totalNotes
    if noteDegree[n] < minDegree
        minDegree = noteDegree[n]
    endif
    if noteDegree[n] > maxDegree
        maxDegree = noteDegree[n]
    endif
    if noteFreq[n] < minFreq
        minFreq = noteFreq[n]
    endif
    if noteFreq[n] > maxFreq
        maxFreq = noteFreq[n]
    endif
endfor

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== Random Walk Melody v0.4.1 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Scale: ", scale_name$, " (", scale_degrees, " degrees)"
appendInfoLine: "Duration / note duration: ", duration_s, " s / ", note_duration_s, " s"
appendInfoLine: "Notes: ", totalNotes
appendInfoLine: "Base / realized frequency range: ", fixed$(base_frequency_Hz, 2), " Hz / ", fixed$(minFreq, 2), "..", fixed$(maxFreq, 2), " Hz"
appendInfoLine: "Move probability target / realized: ", fixed$(step_probability, 3), " / ", fixed$(realizedMoveProbability, 3)
appendInfoLine: "Max step requested / effective: ", max_step_size, " / ", effective_max_step
appendInfoLine: "Moves up/down/holds: ", upCount, " / ", downCount, " / ", holdCount
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed: unpredictable"
endif
appendInfoLine: ""

# ============================================================
# SYNTHESIS
# ============================================================
outputSound = Create Sound from formula: "walk_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
nChunks = ceiling(totalNotes / notesPerChunk)

for chunk to nChunks
    startNote = (chunk - 1) * notesPerChunk + 1
    endNote = min(chunk * notesPerChunk, totalNotes)
    chunkFormula$ = ""

    for n from startNote to endNote
        t = noteTime[n]
        d = min(note_duration_s, duration_s - t)

        if d * sample_rate_Hz >= 2
            t$ = fixed$(t, 9)
            d$ = fixed$(d, 9)
            f$ = fixed$(noteFreq[n], 6)

            # Local phase reset + Hann note window.
            term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then 0.7 * sin(2*pi*" + f$ + "*(x-" + t$ + ")) * (1-cos(2*pi*(x-" + t$ + ")/" + d$ + "))/2 else 0 fi"

            if chunkFormula$ = ""
                chunkFormula$ = term$
            else
                chunkFormula$ = chunkFormula$ + " + " + term$
            endif
        endif
    endfor

    if chunkFormula$ <> ""
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
endfor

# One final level operation; note windows already supply smooth endpoints.
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0
if preNormPeak > 0
    Scale peak: output_peak
endif
Rename: "random_walk_" + preset_name$
outputSound = selected("Sound")
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

appendInfoLine: "Output pre-normalization peak/RMS: ", fixed$(preNormPeak, 4), " / ", fixed$(preNormRMS, 4)
appendInfoLine: "Output final peak/RMS: ", fixed$(finalPeak, 4), " / ", fixed$(finalRMS, 4)

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    Erase all

    # IMPORTANT: every text strip explicitly selects its own inner viewport.
    # Praat keeps Picture viewport state; selecting only an outer viewport can
    # leave subsequent Text commands inside the previous plot frame.

    # ---------------- Title strip ----------------
    Select outer viewport: 0, 8, 0.04, 0.34
    Select inner viewport: 0.20, 7.80, 0.06, 0.31
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Random Walk Melody: " + preset_name$

    # ---------------- Process strip ----------------
    Select outer viewport: 0, 8, 0.36, 0.62
    Select inner viewport: 0.28, 7.72, 0.39, 0.59
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.50, "half", "Bernoulli decision  ->  legal signed step  ->  bounded degree  ->  scale map  ->  Hann note  ->  sum"

    # ---------------- Panel A title ----------------
    Select outer viewport: 0, 8, 0.68, 0.88
    Select inner viewport: 0.10, 7.90, 0.70, 0.86
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "A  Random decisions: hold = 0; a move samples uniformly from legal non-zero steps"

    # ---------------- Panel A: decision process ----------------
    Select outer viewport: 0, 8, 0.90, 2.22
    Select inner viewport: 0.78, 7.62, 1.00, 2.02
    .stepY = effective_max_step + 0.6
    Axes: 0, duration_s, -.stepY, .stepY
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, -.stepY, .stepY
    Colour: "{0.72, 0.72, 0.72}"
    Draw line: 0, 0, duration_s, 0

    if transitionCount > 0
        for .n to transitionCount
            .tx = noteTime[.n] + note_duration_s
            if .tx > duration_s
                .tx = duration_s
            endif
            if walkStep[.n] = 0
                Colour: "{0.45, 0.45, 0.45}"
                Paint circle (mm): "{0.45, 0.45, 0.45}", .tx, 0, 1.2
            else
                if walkStep[.n] > 0
                    Colour: "{0.18, 0.48, 0.76}"
                else
                    Colour: "{0.78, 0.38, 0.20}"
                endif
                Draw line: .tx, 0, .tx, walkStep[.n]
                Paint circle (mm): "{0.25, 0.25, 0.25}", .tx, walkStep[.n], 1.1
            endif
        endfor
    endif

    Colour: "Black"
    Draw inner box
    # Re-select the data viewport after box/text-state operations.
    Select inner viewport: 0.78, 7.62, 1.00, 2.02
    Axes: 0, duration_s, -.stepY, .stepY
    Font size: 8
    Marks left every: 1, 1, "yes", "yes", "no"
    Marks bottom every: 1, max(1, floor(duration_s / 6)), "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Applied step"
    Text bottom: "yes", "Transition time (s)"

    # ---------------- Panel B title ----------------
    Select outer viewport: 0, 8, 2.34, 2.54
    Select inner viewport: 0.10, 7.90, 2.36, 2.52
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "B  State trajectory: bounded degrees 1.." + string$(scale_degrees) + "; no clamp-induced edge holds"

    # ---------------- Panel B: bounded walk ----------------
    Select outer viewport: 0, 8, 2.56, 3.78
    Select inner viewport: 0.78, 7.62, 2.66, 3.58
    Axes: 0, duration_s, 0.5, scale_degrees + 0.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration_s, 0.5, scale_degrees + 0.5
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 1
    for .d to scale_degrees
        Draw line: 0, .d, duration_s, .d
    endfor

    Colour: "{0.18, 0.48, 0.76}"
    Line width: 1.5
    for .n from 2 to totalNotes
        Draw line: noteTime[.n - 1], noteDegree[.n - 1], noteTime[.n], noteDegree[.n]
    endfor
    Line width: 1
    for .n to totalNotes
        Paint circle (mm): "{0.18, 0.48, 0.76}", noteTime[.n], noteDegree[.n], 1.15
    endfor

    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 2.66, 3.58
    Axes: 0, duration_s, 0.5, scale_degrees + 0.5
    Font size: 8
    Marks left every: 1, 1, "yes", "yes", "no"
    Marks bottom every: 1, max(1, floor(duration_s / 6)), "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Scale degree"
    Text bottom: "yes", "Time (s)"

    # ---------------- Panel C title ----------------
    Select outer viewport: 0, 8, 3.92, 4.12
    Select inner viewport: 0.10, 7.90, 3.94, 4.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "C  Scale mapping -> local oscillator x Hann window; oscillator phase resets at each note"

    # ---------------- Panel C-left: scale mapping ----------------
    Select outer viewport: 0, 4.0, 4.14, 5.42
    Select inner viewport: 0.78, 3.75, 4.25, 5.22
    .mapMin = scaleFreq[1] * 0.94
    .mapMax = scaleFreq[scale_degrees] * 1.06
    if .mapMax <= .mapMin
        .mapMax = .mapMin + 1
    endif
    Axes: 0.5, scale_degrees + 0.5, .mapMin, .mapMax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, scale_degrees + 0.5, .mapMin, .mapMax
    Colour: "{0.78, 0.38, 0.20}"
    for .d to scale_degrees
        Draw line: .d, .mapMin, .d, scaleFreq[.d]
        Paint circle (mm): "{0.78, 0.38, 0.20}", .d, scaleFreq[.d], 1.35
    endfor
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 3.75, 4.25, 5.22
    Axes: 0.5, scale_degrees + 0.5, .mapMin, .mapMax
    Font size: 8
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left: 4, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Degree"
    Text left: "yes", "Frequency (Hz)"

    # ---------------- Panel C-right: analytical note window ----------------
    # Draw the envelope itself rather than an undersampled carrier.
    Select outer viewport: 4.0, 8, 4.14, 5.42
    Select inner viewport: 4.28, 7.62, 4.25, 5.22
    .kernelD = min(note_duration_s, duration_s)
    .kernelDegree = ceiling(scale_degrees / 2)
    .kernelF = scaleFreq[.kernelDegree]
    Axes: 0, .kernelD, 0, 1.05
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, .kernelD, 0, 1.05
    .segments = 180
    .prevT = 0
    .prevEnv = 0
    Colour: "{0.18, 0.48, 0.76}"
    Line width: 1.5
    for .k from 1 to .segments
        .kt = .k * .kernelD / .segments
        .env = (1 - cos(2 * pi * .kt / .kernelD)) / 2
        Draw line: .prevT, .prevEnv, .kt, .env
        .prevT = .kt
        .prevEnv = .env
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.28, 7.62, 4.25, 5.22
    Axes: 0, .kernelD, 0, 1.05
    Font size: 8
    Marks bottom: 3, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Local note time (s)"
    Text left: "yes", "Hann envelope"

    # Small formula strip belongs to C, but has its own viewport.
    Select outer viewport: 4.0, 8, 5.43, 5.58
    Select inner viewport: 4.18, 7.82, 5.44, 5.57
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.50, "half", "g(tau) = sin(2*pi*f*tau) * (1-cos(2*pi*tau/D))/2"

    # ---------------- Panel D title ----------------
    Select outer viewport: 0, 8, 5.66, 5.86
    Select inner viewport: 0.10, 7.90, 5.68, 5.84
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "D  Measured output (verification only)"

    # ---------------- Panel D: measured output ----------------
    Select outer viewport: 0, 8, 5.88, 7.02
    Select inner viewport: 0.78, 7.62, 5.98, 6.82
    selectObject: outputSound
    Draw: 0, 0, -1, 1, "no", "Curve"
    Select inner viewport: 0.78, 7.62, 5.98, 6.82
    Axes: 0, duration_s, -1, 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 5.98, 6.82
    Axes: 0, duration_s, -1, 1
    Font size: 8
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, max(1, floor(duration_s / 6)), "yes", "yes", "no"
    Font size: 9
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    # ---------------- QC summary bar ----------------
    Select outer viewport: 0, 8, 7.18, 7.88
    Select inner viewport: 0.18, 7.82, 7.21, 7.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    # Draw six short fields in two rows; this is robust to Picture-window size.
    Select inner viewport: 0.18, 7.82, 7.21, 7.85
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.68, "half", "QC  " + scale_name$ + " | " + string$(totalNotes) + " notes"
    Text: 0.34, "left", 0.68, "half", "Degrees " + string$(minDegree) + ".." + string$(maxDegree) + " | pitch " + fixed$(minFreq,1) + ".." + fixed$(maxFreq,1) + " Hz"
    Text: 0.68, "left", 0.68, "half", "Move p " + fixed$(step_probability,3) + "/" + fixed$(realizedMoveProbability,3) + " | mean |step| " + fixed$(meanAbsStep,2)
    Text: 0.02, "left", 0.25, "half", "Up/down/hold " + string$(upCount) + "/" + string$(downCount) + "/" + string$(holdCount)
    Text: 0.34, "left", 0.25, "half", "Note " + fixed$(note_duration_s,3) + " s | max step +/-" + string$(effective_max_step)
    Text: 0.68, "left", 0.25, "half", "Nyquist " + fixed$(nyquist,0) + " Hz | peak/RMS " + fixed$(finalPeak,3) + "/" + fixed$(finalRMS,3)

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
