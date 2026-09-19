# ============================================================
# Praat AudioTools - Correlation-Based Pitch Class Extraction
# Author: Shai Cohen
# Version: 0.9 (2026)
# License: MIT License
#
# Description:
#   Pitch-guided matched-filter activation for PREDOMINANTLY MONOPHONIC
#   material (one pitch at a time: voice, a melody instrument, a line).
#   Praat's Pitch gives one F0 trajectory; the script segments it into
#   notes, takes a stable stretch of each note as a waveform template,
#   and asks where else that template recurs: cross-correlation ->
#   time-aligned envelope -> weighted by pitch evidence -> threshold ->
#   events. Pitch-class mode folds octave-specific activations.
#
#   It is NOT a polyphonic chroma extractor: a chord yields one F0 (often
#   a phantom common fundamental), not its notes.
#
#   Activation unit (Normalize off): 1.0 = as strong as the template's
#   own source occurrence; the same unit for every octave, so pitch-class
#   folding compares like with like.
#
#   Outputs, two levels of the same analysis:
#     <name>_<note>_activation   continuous evidence (Sound)
#     <name>_events              discrete occurrences (TextGrid, one
#                                interval tier per note / pitch class)
#     <name>_<note>_extracted    optional: the input with only the
#                                detected occurrences kept
#
# Changelog v0.9:
#   - NEW: TextGrid of events - one interval tier per output, each
#     occurrence a labelled interval, in the input's time domain (so it
#     lines up with the Sound in View & Edit).
#   - NEW: Extract detected material - the input (all channels) times a
#     mask per output. Mask "Events" (default): 1 inside occurrences with
#     10 ms raised-cosine edges. Mask "Activation": y = x * A(t) in
#     self-match units capped at 1; note that the matched-filter envelope
#     of a vibrato tone peaks once per vibrato period (panel B), which this
#     mask imprints as tremolo - hence Events is the default.
#
# Changelog v0.8:
#   - FIX (core): the activation is now an ENVELOPE, not a correlation
#     waveform. v0.7 took |r| of the correlation, which for a periodic tone
#     oscillates at the F0 period (two steady A4 notes gave 573 separate
#     non-zero fragments; the event counter papered over it with a merge
#     gap). Now: sum cross-correlation -> time alignment -> square ->
#     low-pass (Envelope smoothing, capped below 2 x pitch floor so the
#     2 F0 ripple cannot pass) -> square root.
#   - FIX (core): note tracking with HYSTERESIS instead of frame-wise
#     round(MIDI). v0.7 split an A4 with +-80 cent vibrato into G#4 / A4 /
#     A#4 runs of 43-53 ms and extracted nothing. Now: median-smoothed F0,
#     a running note centre, and a change only when the deviation exceeds
#     the Note change threshold for the Minimum note change duration.
#   - FIX: "Normalize activation = off" really is off. v0.7 cross-
#     correlated with "peak 0.99", so every output was already scaled to
#     0.99 before the switch was read. Now "sum", divided by the template's
#     self-match, so outputs are in self-match units.
#   - FIX: pitch-class folding takes the max of UN-normalised octave
#     activations (common self-match unit), then normalises ONCE. v0.7
#     scaled each octave to 0.99 first, erasing relative strength.
#   - FIX: soft pitch evidence (Gaussian in cents, sigma = Pitch tolerance)
#     on each note segment's centre, replacing the 0/1 gate on raw frames.
#   - FIX: note-name parser - accidentals that cross an octave boundary
#     (Cb4 -> B3, B#3 -> C4) were placed in the wrong octave.
#   - FIX: outputs keep the input's time domain (v0.7 shifted to 0 s).
#   - Events: minimum duration and minimum gap (min-on / min-off);
#     per-event times and peaks in the Info window.
#   - Pitch-class mode reports octaves that had pitch evidence but no
#     template (too short), instead of dropping them silently.
#   - Method options renamed honestly (cc / ac); form shortened, details
#     moved to an Advanced settings page. Target MIDI number and name are
#     one field. Visualization redrawn in the house style; panel B shows
#     the raw correlation against the envelope that replaces it.
#   - Unchanged (verified correct in review): lag-to-input-time mapping,
#     strongest-RMS analysis channel, unvoiced frames break a note.
# ============================================================

# === Input validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Correlation-Based Pitch Class Extraction v0.9
    comment For predominantly monophonic material (one pitch at a time)
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    optionmenu Scope: 1
        option Exact MIDI notes
        option Pitch classes (fold octaves)
    word Target_note_(empty_=_all) 
    positive Pitch_tolerance_cents 50
    real Gate_threshold_dB -18
    boolean Normalize_activation 1
    boolean Create_TextGrid_of_events 1
    boolean Extract_detected_material 0
    boolean Draw_visualization 1
    boolean Advanced_settings 0
endform

# ---- advanced defaults (initialised before the pause) ----
pitch_method = 1
note_change_threshold_cents = 70
minimum_note_change_ms = 50
median_smoothing_frames = 5
note_centre_window_ms = 250
minimum_stable_ms = 60
maximum_template_ms = 200
envelope_smoothing_ms = 25
minimum_event_ms = 30
minimum_gap_ms = 40
apply_gate = 1
peak_amplitude = 0.99
keep_templates = 0
keep_raw_correlations = 0
extraction_mask = 1
if advanced_settings
    beginPause: "Pitch Class Extraction v0.9 - advanced"
        comment: "Pitch analysis"
        optionmenu: "Pitch method", pitch_method
            option: "Cross-correlation (cc)"
            option: "Autocorrelation (ac)"
        comment: "Note tracking (hysteresis)"
        real: "Note change threshold cents", string$ (note_change_threshold_cents)
        real: "Minimum note change ms", string$ (minimum_note_change_ms)
        integer: "Median smoothing frames", string$ (median_smoothing_frames)
        real: "Note centre window ms", string$ (note_centre_window_ms)
        comment: "Template and envelope"
        real: "Minimum stable ms", string$ (minimum_stable_ms)
        real: "Maximum template ms", string$ (maximum_template_ms)
        real: "Envelope smoothing ms", string$ (envelope_smoothing_ms)
        comment: "Events and output"
        real: "Minimum event ms", string$ (minimum_event_ms)
        real: "Minimum gap ms", string$ (minimum_gap_ms)
        boolean: "Apply gate", apply_gate
        real: "Peak amplitude", string$ (peak_amplitude)
        boolean: "Keep templates", keep_templates
        boolean: "Keep raw correlations", keep_raw_correlations
        optionmenu: "Extraction mask", extraction_mask
            option: "Events (clean excerpts)"
            option: "Activation (continuous weighting)"
    clickedAdv = endPause: "Cancel", "Continue", 2, 1
    if clickedAdv = 1
        exitScript: "Cancelled."
    endif
endif

# --- Parameter validation / clamping ---
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be greater than pitch floor."
endif
pitch_tolerance_cents = max (1, min (100, pitch_tolerance_cents))
note_change_threshold_cents = max (20, min (200, note_change_threshold_cents))
minimum_note_change_ms = max (0, minimum_note_change_ms)
median_smoothing_frames = max (1, round (median_smoothing_frames))
if median_smoothing_frames mod 2 = 0
    median_smoothing_frames += 1
endif
note_centre_window_ms = max (0, note_centre_window_ms)
minimum_stable_ms = max (10, minimum_stable_ms)
maximum_template_ms = max (minimum_stable_ms, maximum_template_ms)
envelope_smoothing_ms = max (2, envelope_smoothing_ms)
minimum_event_ms = max (0, minimum_event_ms)
minimum_gap_ms = max (0, minimum_gap_ms)
gate_threshold_dB = max (-120, min (0, gate_threshold_dB))
if peak_amplitude <= 0 or peak_amplitude > 0.999
    peak_amplitude = 0.99
endif

minStable = minimum_stable_ms / 1000
maxTemplate = maximum_template_ms / 1000
hystSemi = note_change_threshold_cents / 100
minChange = minimum_note_change_ms / 1000
gateRatio = 10 ^ (gate_threshold_dB / 20)
sigmaSemi = pitch_tolerance_cents / 100
# envelope low-pass: 1 / smoothing, but never high enough to pass the
# 2 x F0 ripple of the squared correlation (lowest ripple = 2 x floor)
envCut = min (1 / (envelope_smoothing_ms / 1000), pitch_floor_Hz / 2)

# ============================================================
# STEP 0: REPRESENTATIVE ANALYSIS CHANNEL (v0.7 logic)
# ============================================================
selectObject: originalSound
duration = Get total duration
xmin0 = Get start time
sampleRate = Get sampling frequency
nChannels = Get number of channels
sourceSamples = Get number of samples

analysisSound = 0
analysisChannel = 1
bestRMS = -1
if nChannels = 1
    analysisSound = Copy: "cpc_analysis"
    Shift times to: "start time", 0
    bestRMS = Get root-mean-square: 0, 0
else
    for ch from 1 to nChannels
        selectObject: originalSound
        Extract one channel: ch
        chID = selected("Sound")
        rms = Get root-mean-square: 0, 0
        if rms > bestRMS
            if analysisSound <> 0
                removeObject: analysisSound
            endif
            analysisSound = chID
            analysisChannel = ch
            bestRMS = rms
        else
            removeObject: chID
        endif
    endfor
    selectObject: analysisSound
    Shift times to: "start time", 0
endif

clearinfo
writeInfoLine: "=== Correlation-Based Pitch Class Extraction v0.9 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s (", fixed$(xmin0, 3), " - ", fixed$(xmin0 + duration, 3), " s) | ", sampleRate, " Hz | ", nChannels, " ch"
appendInfoLine: "Analysis channel: ", analysisChannel, " (strongest RMS)"
if scope = 1
    appendInfoLine: "Scope: exact MIDI notes (octave-specific)"
else
    appendInfoLine: "Scope: pitch classes folded across octaves"
endif
appendInfoLine: ""

# ============================================================
# STEP 1: PITCH ANALYSIS
# ============================================================
appendInfoLine: "[1/7] Analyzing fundamental frequency..."
selectObject: analysisSound
if pitch_method = 1
    pitch = To Pitch (cc): 0, pitch_floor_Hz, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitch_ceiling_Hz
else
    pitch = To Pitch: 0, pitch_floor_Hz, pitch_ceiling_Hz
endif
selectObject: pitch
nFrames = Get number of frames
pitchDX = Get time step
frameTime# = zero# (nFrames)
f0# = zero# (nFrames)
midi# = zero# (nFrames)
smidi# = zero# (nFrames)
voiced# = zero# (nFrames)
segOf# = zero# (nFrames)
midiMinFound = 999
midiMaxFound = -999
voicedCount = 0
for i from 1 to nFrames
    selectObject: pitch
    tt = Get time from frame number: i
    ff = Get value in frame: i, "Hertz"
    frameTime#[i] = tt
    if ff <> undefined and ff > 0
        voiced#[i] = 1
        f0#[i] = ff
        mm = 69 + 12 * ln(ff / 440) / ln(2)
        midi#[i] = mm
        voicedCount += 1
        midiMinFound = min (midiMinFound, mm)
        midiMaxFound = max (midiMaxFound, mm)
    endif
endfor
appendInfoLine: "  Frames: ", nFrames, " | voiced: ", voicedCount
if voicedCount = 0
    removeObject: pitch, analysisSound
    exitScript: "No pitch detected. Try adjusting pitch floor/ceiling."
endif

# ============================================================
# STEP 2: NOTE SEGMENTS WITH HYSTERESIS
#   1. median-smooth MIDI within voiced runs (octave jumps, glitches);
#   2. SLOW curve = moving mean over Note centre window (about one vibrato
#      period), inside voiced runs - vibrato cancels, note steps survive;
#   3. hysteresis on the slow curve: a new note starts only when it stays
#      more than Note change threshold from the running note centre for
#      Minimum note change;
#   4. the boundary is moved back to where the FAST (median) curve first
#      sits closer to the new centre than to the old one.
#   Vibrato and bends around a centre therefore stay one note.
# ============================================================
appendInfoLine: "[2/7] Note tracking (median ", median_smoothing_frames, " frames, centre window ", fixed$(note_centre_window_ms, 0), " ms, change > ", fixed$(note_change_threshold_cents, 0), " cents for ", fixed$(minimum_note_change_ms, 0), " ms)..."
halfWin = (median_smoothing_frames - 1) / 2
for i from 1 to nFrames
    if voiced#[i] = 1
        # neighbours inside the same voiced run only
        lo = i
        while lo > 1 and i - lo < halfWin and voiced#[max (1, lo - 1)] = 1 and lo - 1 >= 1
            lo -= 1
        endwhile
        hi = i
        while hi < nFrames and hi - i < halfWin and voiced#[min (nFrames, hi + 1)] = 1
            hi += 1
        endwhile
        win# = zero# (hi - lo + 1)
        for k from lo to hi
            win#[k - lo + 1] = midi#[k]
        endfor
        sw# = sort# (win#)
        smidi#[i] = sw#[round ((hi - lo + 2) / 2)]
    endif
endfor

# slow curve: moving mean over the note-centre window, within voiced runs
halfSlow = round (note_centre_window_ms / 1000 / pitchDX / 2)
slow# = zero# (nFrames)
for i from 1 to nFrames
    if voiced#[i] = 1
        lo = i
        while lo > 1 and i - lo < halfSlow and voiced#[max (1, lo - 1)] = 1
            lo -= 1
        endwhile
        hi = i
        while hi < nFrames and hi - i < halfSlow and voiced#[min (nFrames, hi + 1)] = 1
            hi += 1
        endwhile
        acc = 0
        for k from lo to hi
            acc += smidi#[k]
        endfor
        slow#[i] = acc / (hi - lo + 1)
    endif
endfor

nNote = 0
inNote = 0
pend = 0
for i from 1 to nFrames + 1
    closeNow = 0
    if i > nFrames
        closeNow = inNote
    elsif voiced#[i] = 0
        closeNow = inNote
    endif
    if closeNow
        # close the current note at the last frame before i (or before a
        # pending change that never completed - those frames stay in it)
        @closeNote: noteA, i - 1, nCentre
        inNote = 0
        pend = 0
    endif
    if i <= nFrames
        if voiced#[i] = 1
            m = slow#[i]
            if inNote = 0
                inNote = 1
                noteA = i
                nSum = m
                nCnt = 1
                nCentre = m
                pend = 0
            elsif abs (m - nCentre) > hystSemi
                if pend = 0
                    pend = 1
                    pendA = i
                endif
                if frameTime#[i] - frameTime#[pendA] + pitchDX >= minChange
                    # refine the boundary on the fast curve: first frame
                    # (searching back one centre window) nearer the new pitch
                    newEst = m
                    bnd = pendA
                    kLo = max (noteA + 1, pendA - 2 * halfSlow)
                    found = 0
                    for k from kLo to i
                        if found = 0 and abs (smidi#[k] - newEst) < abs (smidi#[k] - nCentre)
                            bnd = k
                            found = 1
                        endif
                    endfor
                    @closeNote: noteA, bnd - 1, nCentre
                    noteA = bnd
                    nSum = 0
                    nCnt = 0
                    for k from bnd to i
                        nSum += slow#[k]
                        nCnt += 1
                    endfor
                    nCentre = nSum / nCnt
                    pend = 0
                endif
            else
                pend = 0
                nSum += m
                nCnt += 1
                nCentre = nSum / nCnt
            endif
        endif
    endif
endfor
appendInfoLine: "  Note segments: ", nNote

procedure closeNote: .a, .b, .centre
    if .b >= .a
        nNote += 1
        noteFA[nNote] = .a
        noteFB[nNote] = .b
        noteT0[nNote] = max (0, frameTime#[.a] - pitchDX / 2)
        noteT1[nNote] = min (duration, frameTime#[.b] + pitchDX / 2)
        noteCentre[nNote] = .centre
        noteLabel[nNote] = round (.centre)
        for .k from .a to .b
            segOf#[.k] = nNote
        endfor
    endif
endproc

# ============================================================
# STEP 3: CANDIDATES (labels of note segments) + TARGET
# ============================================================
appendInfoLine: "[3/7] Candidates and target..."
uniqueCount = 0
for s from 1 to nNote
    lab = noteLabel[s]
    found = 0
    for u from 1 to uniqueCount
        if uniqueMidi[u] = lab
            found = u
        endif
    endfor
    if found = 0
        uniqueCount += 1
        uniqueMidi[uniqueCount] = lab
        uniqueSupport[uniqueCount] = 0
        uniqueBestSeg[uniqueCount] = 0
        uniqueBestDur[uniqueCount] = 0
        uniqueCentreSum[uniqueCount] = 0
        found = uniqueCount
    endif
    d = noteT1[s] - noteT0[s]
    uniqueSupport[found] += d
    uniqueCentreSum[found] += d * noteCentre[s]
    if d > uniqueBestDur[found]
        uniqueBestDur[found] = d
        uniqueBestSeg[found] = s
    endif
endfor
# sort ascending (ascending loops only)
for a from 1 to uniqueCount - 1
    for b from a + 1 to uniqueCount
        if uniqueMidi[a] > uniqueMidi[b]
            for fld from 1 to 5
                if fld = 1
                    tmp = uniqueMidi[a]
                    uniqueMidi[a] = uniqueMidi[b]
                    uniqueMidi[b] = tmp
                elsif fld = 2
                    tmp = uniqueSupport[a]
                    uniqueSupport[a] = uniqueSupport[b]
                    uniqueSupport[b] = tmp
                elsif fld = 3
                    tmp = uniqueBestSeg[a]
                    uniqueBestSeg[a] = uniqueBestSeg[b]
                    uniqueBestSeg[b] = tmp
                elsif fld = 4
                    tmp = uniqueBestDur[a]
                    uniqueBestDur[a] = uniqueBestDur[b]
                    uniqueBestDur[b] = tmp
                else
                    tmp = uniqueCentreSum[a]
                    uniqueCentreSum[a] = uniqueCentreSum[b]
                    uniqueCentreSum[b] = tmp
                endif
            endfor
        endif
    endfor
endfor
for u from 1 to uniqueCount
    @midiToName: uniqueMidi[u]
    uniqueName$[u] = midiToName.full$
    uniquePC[u] = midiToName.pc
    uniqueFreq[u] = 440 * 2 ^ ((uniqueCentreSum[u] / uniqueSupport[u] - 69) / 12)
endfor
appendInfoLine: "  ", uniqueCount, " note candidate(s) from ", nNote, " segment(s)"

manualTarget = 0
targetMidiParsed = 0
targetPCParsed = -1
tgt$ = target_note$
tgt$ = replace_regex$ (tgt$, "^[ \t]+|[ \t]+$", "", 0)
if tgt$ <> ""
    tgtNum = number (tgt$)
    if tgtNum <> undefined
        targetMidiParsed = round (tgtNum)
        targetPCParsed = targetMidiParsed mod 12
        manualTarget = 1
    else
        @parseNoteName: tgt$
        if parseNoteName.ok = 0
            removeObject: pitch, analysisSound
            exitScript: "Could not parse the target. Use a MIDI number (69), a note (A4, F#3, Bb3, Cb4) or, in pitch-class mode, a pitch class (C, Eb)."
        endif
        targetPCParsed = parseNoteName.pc
        if parseNoteName.hasOctave
            targetMidiParsed = parseNoteName.midi
        endif
        manualTarget = 1
    endif
endif
if scope = 1 and manualTarget = 1 and targetMidiParsed = 0
    removeObject: pitch, analysisSound
    exitScript: "Exact-MIDI scope needs an octave (for example C4) or a MIDI number."
endif

numToProcess = 0
for u from 1 to uniqueCount
    include = 0
    if manualTarget = 0
        include = 1
    elsif scope = 1
        include = uniqueMidi[u] = targetMidiParsed
    else
        include = uniquePC[u] = targetPCParsed
    endif
    if include
        numToProcess += 1
        procU[numToProcess] = u
    endif
endfor
if numToProcess = 0
    removeObject: pitch, analysisSound
    exitScript: "The requested target was not found among the tracked notes."
endif

# representative candidate for panel B = most support
repU = procU[1]
for p from 2 to numToProcess
    if uniqueSupport[procU[p]] > uniqueSupport[repU]
        repU = procU[p]
    endif
endfor
repPC = uniquePC[repU]

# ============================================================
# STEP 4: TEMPLATE -> CORRELATION ENVELOPE -> PITCH EVIDENCE
# ============================================================
appendInfoLine: "[4/7] Templates, correlation envelopes, pitch evidence (envelope low-pass ", fixed$(envCut, 1), " Hz)..."
numEx = 0
numSkipped = 0
keptTemplateCount = 0
keptCorrCount = 0
repRaw = 0
nSrc$ = string$ (sourceSamples)
for p from 1 to numToProcess
    u = procU[p]
    targetMidi = uniqueMidi[u]
    targetName$ = uniqueName$[u]
    bs = uniqueBestSeg[u]
    bestDur = uniqueBestDur[u]
    if bestDur < minStable
        numSkipped += 1
        skipName$[numSkipped] = targetName$
        skipDur[numSkipped] = bestDur
        skipPC[numSkipped] = uniquePC[u]
        appendInfoLine: "  ", targetName$, ": no template - longest note ", fixed$(bestDur * 1000, 0), " ms < minimum ", fixed$(minimum_stable_ms, 0), " ms"
    else
        # centre-cropped, Hann-tapered template from the longest note
        templateDur = min (bestDur, maxTemplate)
        centre = (noteT0[bs] + noteT1[bs]) / 2
        templateStart = max (0, centre - templateDur / 2)
        templateEnd = min (duration, templateStart + templateDur)
        templateStart = max (0, templateEnd - templateDur)
        templateDur = templateEnd - templateStart
        selectObject: analysisSound
        template = Extract part: templateStart, templateEnd, "rectangular", 1, "no"
        Rename: originalName$ + "_" + targetName$ + "_template"
        Formula: "self * (0.5 - 0.5*cos(2*pi*x/" + fixed$(templateDur, 12) + "))"

        # raw SUM correlation (no hidden normalisation)
        selectObject: analysisSound
        plusObject: template
        corr = Cross-correlate: "sum", "zero"
        Rename: originalName$ + "_" + targetName$ + "_raw_correlation"

        # input-time alignment. v0.7's mapping (sample k <- Nsrc + 1 - k) is
        # correct but marks where a matching window STARTS (measured: a
        # pattern at 0.300-0.400 s peaks at 0.300 s). v0.8 shifts it by half
        # the template, so activation(t) scores the template-length window
        # CENTRED on t, and the self-match sits at the template's centre.
        hS = round (templateDur * sampleRate / 2)
        aligned = Create Sound from formula: "cpc_aligned", 1, 0, duration, sampleRate,
            ... "if col - " + string$ (hS) + " < 1 then 0 else object[" + string$ (corr) + ", 1, " + nSrc$ + " + 1 - (col - " + string$ (hS) + ")] fi"

        # envelope: square -> low-pass -> sqrt
        envl = Copy: "cpc_env"
        Formula: "self * self"
        envf = Filter (pass Hann band): 0, envCut, envCut
        Formula: "sqrt (max (0, self))"
        removeObject: envl

        # self-match unit: the envelope at the template's own centre = 1
        selfVal = Get value at time: 1, (templateStart + templateEnd) / 2, "Sinc70"
        if selfVal = undefined or selfVal <= 0
            selfVal = Get maximum: 0, 0, "None"
        endif
        if selfVal <= 0
            selfVal = 1
        endif
        Formula: "self / " + string$ (selfVal)

        # soft pitch evidence per note segment: Gaussian of centre distance
        evid = Create Sound from formula: "cpc_evidence", 1, 0, duration, sampleRate, "0"
        for s from 1 to nNote
            w = exp (-0.5 * ((noteCentre[s] - targetMidi) / sigmaSemi) ^ 2)
            if w >= 0.01
                Formula (part): noteT0[s], noteT1[s], 1, 1, "max (self, " + string$ (w) + ")"
            endif
        endfor
        selectObject: envf
        Formula: "self * object[" + string$ (evid) + ", 1, col]"
        Rename: originalName$ + "_" + targetName$ + "_activation"

        # panel B material: raw |aligned correlation| in the same unit
        if u = repU or (scope = 2 and repRaw = 0 and uniquePC[u] = repPC)
            if repRaw > 0
                removeObject: repRaw
            endif
            selectObject: aligned
            repRaw = Copy: "cpc_rep_raw"
            Formula: "abs (self) / " + string$ (selfVal)
            repRawName$ = targetName$
        endif
        removeObject: aligned, evid

        numEx += 1
        exAct[numEx] = envf
        exTemplate[numEx] = template
        exMidi[numEx] = targetMidi
        exPC[numEx] = uniquePC[u]
        exName$[numEx] = targetName$
        exFreq[numEx] = uniqueFreq[u]
        exSupport[numEx] = uniqueSupport[u]
        exTDur[numEx] = templateDur
        exT0[numEx] = templateStart
        exT1[numEx] = templateEnd
        exSelf[numEx] = selfVal
        appendInfoLine: "  ", targetName$, ": longest note ", fixed$(bestDur * 1000, 0), " ms | template ", fixed$(templateDur * 1000, 0), " ms"
        if keep_templates
            keptTemplateCount += 1
            keptTemplate[keptTemplateCount] = template
        endif
        if keep_raw_correlations
            keptCorrCount += 1
            keptCorr[keptCorrCount] = corr
        else
            removeObject: corr
        endif
    endif
endfor
if numEx = 0
    removeObject: pitch, analysisSound
    if repRaw > 0
        removeObject: repRaw
    endif
    exitScript: "No candidate had a note long enough (Minimum stable) to build a template."
endif

# ============================================================
# STEP 5: OUTPUTS - exact notes, or octaves folded (max, un-normalised),
#         then ONE gate and ONE normalisation per output
# ============================================================
appendInfoLine: "[5/7] Building outputs..."
numOutputs = 0
if scope = 1
    for ex from 1 to numEx
        numOutputs += 1
        outID[numOutputs] = exAct[ex]
        outName$[numOutputs] = exName$[ex]
        outMidi[numOutputs] = exMidi[ex]
        outPC[numOutputs] = exPC[ex]
        outFreq[numOutputs] = exFreq[ex]
        outSupport[numOutputs] = exSupport[ex]
        outTDur[numOutputs] = exTDur[ex]
        outOctaves$[numOutputs] = exName$[ex]
        outMissing$[numOutputs] = ""
    endfor
else
    pcCount = 0
    for ex from 1 to numEx
        seen = 0
        for q from 1 to pcCount
            if pcList[q] = exPC[ex]
                seen = 1
            endif
        endfor
        if seen = 0
            pcCount += 1
            pcList[pcCount] = exPC[ex]
        endif
    endfor
    for a from 1 to pcCount - 1
        for b from a + 1 to pcCount
            if pcList[a] > pcList[b]
                tmp = pcList[a]
                pcList[a] = pcList[b]
                pcList[b] = tmp
            endif
        endfor
    endfor
    for q from 1 to pcCount
        pc = pcList[q]
        combined = 0
        supportSum = 0
        maxTDur = 0
        octs$ = ""
        for ex from 1 to numEx
            if exPC[ex] = pc
                if combined = 0
                    selectObject: exAct[ex]
                    combined = Copy: "cpc_pc"
                else
                    selectObject: combined
                    Formula: "max (self, object[" + string$ (exAct[ex]) + ", 1, col])"
                endif
                supportSum += exSupport[ex]
                maxTDur = max (maxTDur, exTDur[ex])
                octs$ = octs$ + if octs$ = "" then "" else "," fi + exName$[ex]
            endif
        endfor
        missing$ = ""
        for k from 1 to numSkipped
            if skipPC[k] = pc
                missing$ = missing$ + if missing$ = "" then "" else ", " fi + skipName$[k] + " (" + fixed$(skipDur[k] * 1000, 0) + " ms)"
            endif
        endfor
        @pcToName: pc
        selectObject: combined
        Rename: originalName$ + "_" + pcToName.name$ + "_pitchclass_activation"
        numOutputs += 1
        outID[numOutputs] = combined
        outName$[numOutputs] = pcToName.name$
        outMidi[numOutputs] = -1
        outPC[numOutputs] = pc
        outFreq[numOutputs] = 0
        outSupport[numOutputs] = supportSum
        outTDur[numOutputs] = maxTDur
        outOctaves$[numOutputs] = octs$
        outMissing$[numOutputs] = missing$
    endfor
    for ex from 1 to numEx
        removeObject: exAct[ex]
    endfor
endif

# representative output = the one containing repU
repOut = 1
for o from 1 to numOutputs
    if scope = 1
        if outMidi[o] = uniqueMidi[repU]
            repOut = o
        endif
    elsif outPC[o] = repPC
        repOut = o
    endif
endfor

# gate + normalise once; keep a pre-gate copy of the representative
minEv = minimum_event_ms / 1000
minGap = minimum_gap_ms / 1000
eventCountTotal = 0
for o from 1 to numOutputs
    selectObject: outID[o]
    outPeakSelf[o] = Get maximum: 0, 0, "None"
    outThrSelf[o] = outPeakSelf[o] * gateRatio
    if o = repOut
        repPre = Copy: "cpc_rep_pre"
        selectObject: outID[o]
    endif
    if apply_gate and outPeakSelf[o] > 0
        Formula: "if self < " + string$ (outThrSelf[o]) + " then 0 else self fi"
    endif
    outScale[o] = 1
    if normalize_activation and outPeakSelf[o] > 0
        outScale[o] = peak_amplitude / outPeakSelf[o]
        Formula: "self * " + string$ (outScale[o])
    endif

    # events on the Pitch frame grid. activation(t) scores the window
    # centred on t and is confined to tracked notes by the pitch evidence,
    # so a run of active frames IS the occurrence span (a centred window
    # keeps a partial match up to the note edges - no widening needed).
    # Spans closer than Minimum gap merge; spans shorter than Minimum
    # event are dropped.
    selectObject: outID[o]
    active = 0
    nRaw = 0
    halfT = pitchDX / 2
    for i from 1 to nFrames
        vv = Get value at time: 1, frameTime#[i], "Linear"
        if vv = undefined
            vv = 0
        endif
        on = vv / outScale[o] >= outThrSelf[o] and outPeakSelf[o] > 0
        if on
            if active = 0
                active = 1
                nRaw += 1
                rawA[nRaw] = max (0, frameTime#[i] - halfT)
                rawPk[nRaw] = 0
            endif
            rawB[nRaw] = min (duration, frameTime#[i] + halfT)
            rawPk[nRaw] = max (rawPk[nRaw], vv / outScale[o])
        else
            active = 0
        endif
    endfor
    nLoc = 0
    k = 1
    while k <= nRaw
        evA = rawA[k]
        evB = rawB[k]
        evPk = rawPk[k]
        k += 1
        merging = 1
        while merging and k <= nRaw
            if rawA[k] - evB < minGap
                evB = max (evB, rawB[k])
                evPk = max (evPk, rawPk[k])
                k += 1
            else
                merging = 0
            endif
        endwhile
        @storeEvent: o
    endwhile
    outEvents[o] = nLoc
endfor

procedure storeEvent: .o
    if evB - evA >= minEv
        nLoc += 1
        eventCountTotal += 1
        eventOut[eventCountTotal] = .o
        eventStart[eventCountTotal] = evA + xmin0
        eventEnd[eventCountTotal] = evB + xmin0
        eventPeak[eventCountTotal] = evPk
    endif
endproc

# ---- restore the input's time domain on everything that leaves ----
for o from 1 to numOutputs
    selectObject: outID[o]
    Shift times to: "start time", xmin0
endfor
selectObject: repPre
Shift times to: "start time", xmin0

# ============================================================
# STEP 5b: DISCRETE OUTPUTS - TextGrid of events, extracted material
# ============================================================
tgID = 0
if create_TextGrid_of_events
    tiers$ = ""
    for o from 1 to numOutputs
        tiers$ = tiers$ + if o = 1 then "" else " " fi + outName$[o]
    endfor
    tgID = Create TextGrid: xmin0, xmin0 + duration, tiers$, ""
    Rename: originalName$ + "_events"
    for ev from 1 to eventCountTotal
        o = eventOut[ev]
        a = eventStart[ev]
        b = eventEnd[ev]
        selectObject: tgID
        if a > xmin0 + 1e-6
            nocheck Insert boundary: o, a
        endif
        if b < xmin0 + duration - 1e-6
            nocheck Insert boundary: o, b
        endif
        k = Get interval at time: o, (a + b) / 2
        Set interval text: o, k, outName$[o]
    endfor
endif

numExtracted = 0
if extract_detected_material
    selectObject: originalSound
    srcSR = Get sampling frequency
    for o from 1 to numOutputs
        if extraction_mask = 2
            # continuous: activation in self-match units, capped at 1
            selectObject: outID[o]
            mask = Copy: "cpc_mask"
            Formula: "min (1, self / " + string$ (outScale[o]) + ")"
            if srcSR <> sampleRate
                maskR = Resample: srcSR, 50
                removeObject: mask
                mask = maskR
            endif
        else
            # events: 1 inside occurrences, 10 ms raised-cosine edges
            mask = Create Sound from formula: "cpc_mask", 1, xmin0, xmin0 + duration, srcSR, "0"
            for ev from 1 to eventCountTotal
                if eventOut[ev] = o
                    a = eventStart[ev]
                    b = eventEnd[ev]
                    f = min (0.01, (b - a) / 2)
                    Formula (part): a, b, 1, 1, "if x < " + string$ (a + f) + " then 0.5 - 0.5 * cos (pi * (x - " + string$ (a) + ") / " + string$ (f)
                        ... + ") else if x > " + string$ (b - f) + " then 0.5 - 0.5 * cos (pi * (" + string$ (b) + " - x) / " + string$ (f) + ") else 1 fi fi"
                endif
            endfor
        endif
        selectObject: originalSound
        numExtracted += 1
        extID[numExtracted] = Copy: originalName$ + "_" + outName$[o] + "_extracted"
        Formula: "self * object[" + string$ (mask) + ", 1, col]"
        removeObject: mask
    endfor
endif
if repRaw > 0
    selectObject: repRaw
    Shift times to: "start time", xmin0
endif

# ============================================================
# STEP 6: INFO SUMMARY
# ============================================================
appendInfoLine: "[6/7] Summary..."
appendInfoLine: ""
appendInfoLine: "Note/PC     MIDI   Centre Hz   Template   Notes (s)   Peak (self)   Events"
appendInfoLine: "-------     ----   ---------   --------   ---------   -----------   ------"
for o from 1 to numOutputs
    @padR: outName$[o], 10
    lab$ = padR.result$
    if outMidi[o] >= 0
        @padR: string$ (outMidi[o]), 5
        mid$ = padR.result$
        @padR: fixed$ (outFreq[o], 1), 10
        hz$ = padR.result$
    else
        @padR: "PC", 5
        mid$ = padR.result$
        @padR: "multi", 10
        hz$ = padR.result$
    endif
    @padR: fixed$ (outTDur[o] * 1000, 0) + " ms", 9
    td$ = padR.result$
    @padR: fixed$ (outSupport[o], 2), 10
    sp$ = padR.result$
    @padR: fixed$ (outPeakSelf[o], 3), 12
    pk$ = padR.result$
    appendInfoLine: lab$, "  ", mid$, "  ", hz$, "  ", td$, "  ", sp$, "  ", pk$, "  ", outEvents[o]
    if scope = 2
        appendInfoLine: "             templates: ", outOctaves$[o]
        if outMissing$[o] <> ""
            appendInfoLine: "             no template (too short, not represented): ", outMissing$[o]
        endif
    endif
endfor
appendInfoLine: ""
appendInfoLine: "Peak (self) = strongest activation in self-match units (1.0 = as strong as the"
appendInfoLine: "template's own source occurrence); gate at ", fixed$ (gate_threshold_dB, 0), " dB below each output's peak."
appendInfoLine: ""
appendInfoLine: "Events (input time, s):"
for o from 1 to numOutputs
    line$ = "  " + outName$[o] + ":"
    shown = 0
    for ev from 1 to eventCountTotal
        if eventOut[ev] = o and shown < 30
            line$ = line$ + "  " + fixed$ (eventStart[ev], 3) + "-" + fixed$ (eventEnd[ev], 3) + " (" + fixed$ (eventPeak[ev], 2) + ")"
            shown += 1
        endif
    endfor
    if shown = 0
        line$ = line$ + "  none"
    endif
    appendInfoLine: line$
endfor
appendInfoLine: ""
appendInfoLine: "Outputs: ", numOutputs, " activation curve(s) | events: ", eventCountTotal
if numSkipped > 0 and scope = 1
    appendInfoLine: "Not extracted (note shorter than Minimum stable): ", numSkipped
endif

# ============================================================
# STEP 7: VISUALIZATION (house style, 8 x 7.25 in)
# ============================================================
if draw_visualization
    appendInfoLine: "[7/7] Drawing visualization..."
    cPrim$ = "{0.20, 0.48, 0.75}"
    cSec$ = "{0.85, 0.38, 0.18}"
    cGrey$ = "{0.55, 0.55, 0.60}"
    cGround$ = "{0.97, 0.97, 0.97}"
    cGrid$ = "{0.80, 0.80, 0.80}"
    cSub$ = "{0.35, 0.35, 0.50}"
    cSum$ = "{0.25, 0.25, 0.35}"
    cLight$ = "{0.86, 0.91, 0.97}"
    tA = xmin0
    tB = xmin0 + duration
    @vizSafe: originalName$
    nm$ = vizSafe.result$
    Erase all

    # ---- title band ----
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Correlation-Based Pitch Class Extraction v0.9##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: cSub$
    Text: 0.5, "centre", 0.22, "half", nm$ + "   |   analysis ch " + string$ (analysisChannel) + "   |   " + if scope = 1 then "exact MIDI" else "pitch-class fold" fi + "   |   " + string$ (numOutputs) + " output(s), " + string$ (eventCountTotal) + " event(s)"

    # ---- A: pitch track + note segments ----
    vMin = floor (midiMinFound) - 1
    vMax = ceiling (midiMaxFound) + 1
    if vMax - vMin < 6
        vMax = vMin + 6
    endif
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Axes: tA, tB, vMin, vMax
    Paint rectangle: cGround$, tA, tB, vMin, vMax
    Colour: cGrid$
    for m from vMin to vMax
        if m mod 12 = 0
            Solid line
        else
            Dotted line
        endif
        Draw line: tA, m, tB, m
    endfor
    Solid line
    # raw F0 (grey)
    Colour: cGrey$
    Line width: 1
    for i from 2 to nFrames
        if voiced#[i-1] = 1 and voiced#[i] = 1
            Draw line: frameTime#[i-1] + xmin0, midi#[i-1], frameTime#[i] + xmin0, midi#[i]
        endif
    endfor
    # note segments: bar at the tracked centre; extracted = primary
    for s from 1 to nNote
        isOut = 0
        for ex from 1 to numEx
            if exMidi[ex] = noteLabel[s]
                isOut = 1
            endif
        endfor
        if isOut
            Colour: cPrim$
            Line width: 3
        else
            Colour: "{0.70, 0.70, 0.75}"
            Line width: 2
        endif
        Draw line: noteT0[s] + xmin0, noteCentre[s], noteT1[s] + xmin0, noteCentre[s]
    endfor
    # template spans (secondary)
    Line width: 2
    Colour: cSec$
    for ex from 1 to numEx
        Draw line: exT0[ex] + xmin0, exMidi[ex] - 0.45, exT1[ex] + xmin0, exMidi[ex] - 0.45
    endfor
    Line width: 1
    Font size: 6
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Axes: tA, tB, vMin, vMax
    for s from 1 to nNote
        if noteT1[s] - noteT0[s] > duration * 0.03
            @midiToName: noteLabel[s]
            Colour: cSum$
            Text: noteT0[s] + xmin0, "left", noteCentre[s] + 0.35, "bottom", midiToName.full$
        endif
    endfor
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Axes: tA, tB, vMin, vMax
    Colour: "Black"
    Draw inner box
    @niceStep: vMax - vMin, 6
    Marks left every: 1, niceStep.result, "yes", "yes", "no"
    @niceStep: duration, 8
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "MIDI"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 0.95, 2.35
    Text top: "no", "##A   Pitch track (grey) and tracked notes##   bar = note centre with hysteresis; blue = extracted; orange = template"

    # ---- B: raw correlation vs envelope, representative output ----
    selectObject: repPre
    bMax = Get maximum: 0, 0, "None"
    if repRaw > 0
        selectObject: repRaw
        rMax = Get maximum: 0, 0, "None"
        bMax = max (bMax, rMax)
    endif
    bMax = max (bMax, 1e-9) * 1.08
    Font size: 7
    Select inner viewport: 0.60, 7.70, 2.85, 4.25
    Axes: tA, tB, 0, bMax
    Paint rectangle: cGround$, tA, tB, 0, bMax
    for ev from 1 to eventCountTotal
        if eventOut[ev] = repOut
            Paint rectangle: cLight$, eventStart[ev], eventEnd[ev], 0, bMax
        endif
    endfor
    if repRaw > 0
        selectObject: repRaw
        Colour: "{0.72, 0.72, 0.76}"
        Draw: 0, 0, 0, bMax, "no", "Curve"
    endif
    Select inner viewport: 0.60, 7.70, 2.85, 4.25
    selectObject: repPre
    Colour: cPrim$
    Line width: 2
    Draw: 0, 0, 0, bMax, "no", "Curve"
    Line width: 1
    Select inner viewport: 0.60, 7.70, 2.85, 4.25
    Axes: tA, tB, 0, bMax
    Colour: cSec$
    Dotted line
    Draw line: tA, outThrSelf[repOut], tB, outThrSelf[repOut]
    Solid line
    Colour: "Black"
    Draw inner box
    @niceStep: bMax, 4
    Marks left every: 1, niceStep.result, "yes", "yes", "no"
    @niceStep: duration, 8
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "Self-match units"
    Text bottom: "yes", "Time (s, input time domain)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 2.85, 4.25
    Text top: "no", "##B   " + outName$[repOut] + ": |correlation| (grey) -> envelope x pitch evidence (blue) -> gate (dotted); events shaded##"

    # ---- C: peak per output (self units) ----
    cMax = 0
    for o from 1 to numOutputs
        cMax = max (cMax, outPeakSelf[o])
    endfor
    cMax = max (cMax, 1e-9) * 1.25
    Font size: 7
    Select inner viewport: 0.60, 3.85, 4.80, 6.10
    Axes: 0.4, numOutputs + 0.6, 0, cMax
    Paint rectangle: cGround$, 0.4, numOutputs + 0.6, 0, cMax
    Colour: cGrid$
    Dotted line
    Draw line: 0.4, 1, numOutputs + 0.6, 1
    Solid line
    for o from 1 to numOutputs
        Paint rectangle: if o = repOut then cPrim$ else cGrey$ fi, o - 0.3, o + 0.3, 0, outPeakSelf[o]
    endfor
    Font size: 6
    Select inner viewport: 0.60, 3.85, 4.80, 6.10
    Axes: 0.4, numOutputs + 0.6, 0, cMax
    for o from 1 to numOutputs
        Colour: cSum$
        Text: o, "centre", outPeakSelf[o] + cMax * 0.02, "bottom", string$ (outEvents[o]) + " ev"
    endfor
    Font size: 7
    Select inner viewport: 0.60, 3.85, 4.80, 6.10
    Axes: 0.4, numOutputs + 0.6, 0, cMax
    Colour: "Black"
    Draw inner box
    @niceStep: cMax, 4
    Marks left every: 1, niceStep.result, "yes", "yes", "no"
    for o from 1 to min (numOutputs, 12)
        @vizSafe: outName$[o]
        One mark bottom: o, "no", "yes", "no", vizSafe.result$
    endfor
    Text left: "yes", "Peak (self units)"
    Font size: 8
    Select inner viewport: 0.60, 3.85, 4.80, 6.10
    Text top: "no", "##C   Peak activation per output##   dotted = self-match"

    # ---- D: event timeline ----
    rows = min (numOutputs, 12)
    Font size: 7
    Select inner viewport: 4.45, 7.70, 4.80, 6.10
    Axes: tA, tB, rows + 0.5, 0.5
    Paint rectangle: cGround$, tA, tB, rows + 0.5, 0.5
    for ev from 1 to eventCountTotal
        oo = eventOut[ev]
        if oo <= rows
            Paint rectangle: if oo = repOut then cPrim$ else cGrey$ fi, eventStart[ev], eventEnd[ev], oo - 0.3, oo + 0.3
        endif
    endfor
    Colour: "Black"
    Draw inner box
    @niceStep: duration, 5
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    for o from 1 to rows
        @vizSafe: outName$[o]
        One mark left: o, "no", "yes", "no", vizSafe.result$
    endfor
    Font size: 8
    Select inner viewport: 4.45, 7.70, 4.80, 6.10
    Text top: "no", "##D   Events##"

    # ---- summary strip ----
    Font size: 6
    Select inner viewport: 0.60, 7.70, 6.60, 7.20
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: cSum$
    Text: 0.01, "left", 0.78, "half", "##Tracking:## change > " + fixed$ (note_change_threshold_cents, 0) + " cents for " + fixed$ (minimum_note_change_ms, 0) + " ms, median " + string$ (median_smoothing_frames) + " frames   ##Evidence:## Gaussian, sigma " + fixed$ (pitch_tolerance_cents, 0) + " cents   ##Template:## " + fixed$ (minimum_stable_ms, 0) + "\--" + fixed$ (maximum_template_ms, 0) + " ms, Hann"
    Text: 0.01, "left", 0.48, "half", "##Envelope:## low-pass " + fixed$ (envCut, 1) + " Hz on squared correlation   ##Gate:## " + fixed$ (gate_threshold_dB, 0) + " dB   ##Events:## >= " + fixed$ (minimum_event_ms, 0) + " ms, gaps < " + fixed$ (minimum_gap_ms, 0) + " ms merged   ##Normalise:## " + if normalize_activation then "once, to " + fixed$ (peak_amplitude, 2) else "off (self-match units)" fi
    Text: 0.01, "left", 0.18, "half", "##Scope note:## one F0 track (Praat Pitch) - for monophonic material; a chord yields one (possibly phantom) pitch, not its notes."
    Select inner viewport: 0.60, 7.70, 6.60, 7.20
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Line width: 1
    Select outer viewport: 0, 8, 0, 7.25
endif

# ============================================================
# CLEANUP / FINAL SELECTION
# ============================================================
removeObject: pitch, analysisSound, repPre
if repRaw > 0
    removeObject: repRaw
endif
if keep_templates = 0
    for ex from 1 to numEx
        removeObject: exTemplate[ex]
    endfor
endif
selectObject: outID[1]
for o from 2 to numOutputs
    plusObject: outID[o]
endfor
if keep_templates
    for k from 1 to keptTemplateCount
        plusObject: keptTemplate[k]
    endfor
endif
if keep_raw_correlations
    for k from 1 to keptCorrCount
        plusObject: keptCorr[k]
    endfor
endif
if tgID > 0
    plusObject: tgID
endif
for k from 1 to numExtracted
    plusObject: extID[k]
endfor
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created ", numOutputs, " activation curve(s) in the input's time domain."
if tgID > 0
    appendInfoLine: "TextGrid ", originalName$, "_events: ", numOutputs, " tier(s), ", eventCountTotal, " interval(s) - select it with the Sound and View & Edit."
endif
if numExtracted > 0
    appendInfoLine: "Extracted material: ", numExtracted, " Sound(s), mask = ", if extraction_mask = 1 then "events" else "activation" fi, "."
endif

# ============================================================
# HELPERS
# ============================================================
procedure padR: .s$, .w
    while length (.s$) < .w
        .s$ = .s$ + " "
    endwhile
    .result$ = .s$
endproc

procedure vizSafe: .s$
    .s$ = replace$ (.s$, "\", "\bs", 0)
    .s$ = replace$ (.s$, "_", "\_ ", 0)
    .s$ = replace$ (.s$, "%", "\% ", 0)
    .s$ = replace$ (.s$, "#", "\# ", 0)
    .s$ = replace$ (.s$, "^", "\^ ", 0)
    .result$ = .s$
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc

procedure midiToName: .midi
    .pc = .midi mod 12
    if .pc < 0
        .pc += 12
    endif
    .oct = floor(.midi / 12) - 1
    @pcToName: .pc
    .full$ = pcToName.name$ + string$(.oct)
endproc

procedure pcToName: .pc
    if .pc = 0
        .name$ = "C"
    elsif .pc = 1
        .name$ = "C#"
    elsif .pc = 2
        .name$ = "D"
    elsif .pc = 3
        .name$ = "D#"
    elsif .pc = 4
        .name$ = "E"
    elsif .pc = 5
        .name$ = "F"
    elsif .pc = 6
        .name$ = "F#"
    elsif .pc = 7
        .name$ = "G"
    elsif .pc = 8
        .name$ = "G#"
    elsif .pc = 9
        .name$ = "A"
    elsif .pc = 10
        .name$ = "A#"
    else
        .name$ = "B"
    endif
endproc


# v0.8 FIX: accidentals are applied to the chromatic position BEFORE the
# octave is combined, so Cb4 = B3 (59) and B#3 = C4 (60). v0.7 folded the
# pitch class first (Cb -> 11) and then added octave 4 (-> B4, 71).
procedure parseNoteName: .input$
    .ok = 0
    .hasOctave = 0
    .midi = 0
    .pc = -1
    .s$ = .input$
    .len = length (.s$)
    if .len >= 1
        .letter$ = left$ (.s$, 1)
        .li = index ("CDEFGAB", .letter$) + index ("cdefgab", .letter$)
        if .li > 0
            .semis# = {0, 2, 4, 5, 7, 9, 11}
            .base = .semis#[.li]
            .acc = 0
            .pos = 2
            .more = 1
            while .more and .pos <= .len
                .c$ = mid$ (.s$, .pos, 1)
                if .c$ = "#" or .c$ = "s"
                    .acc += 1
                    .pos += 1
                elsif .c$ = "b"
                    .acc -= 1
                    .pos += 1
                else
                    .more = 0
                endif
            endwhile
            .chroma = .base + .acc
            .pc = .chroma mod 12
            if .pc < 0
                .pc += 12
            endif
            .ok = 1
            if .pos <= .len
                .oct = number (mid$ (.s$, .pos, .len - .pos + 1))
                if .oct <> undefined
                    .hasOctave = 1
                    .midi = (.oct + 1) * 12 + .chroma
                else
                    .ok = 0
                endif
            endif
        endif
    endif
endproc
