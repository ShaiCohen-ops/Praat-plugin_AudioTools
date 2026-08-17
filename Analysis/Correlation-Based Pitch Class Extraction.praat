# ============================================================
# Praat AudioTools - Correlation-Based Pitch Class Extraction
# Author: Shai Cohen
# Version: 0.7 (2026)
# License: MIT License
#
# Description:
#   Pitch-guided matched-filter activation extraction.
#   A stable detected MIDI-note segment is used as a tapered waveform
#   template. Cross-correlation is converted from lag-domain into an
#   input-time activation curve, then intersected with measured pitch
#   evidence so unrelated correlation sidelobes do not masquerade as
#   note occurrences.
#
#   The legacy exact-MIDI mode remains the default. An optional
#   pitch-class mode folds octave-specific activations by taking their
#   pointwise maximum, using one template per detected octave.
#
# Changelog v0.7:
#   - FIX: continuity is measured on the full Pitch frame timeline;
#     unvoiced gaps no longer join separate note occurrences.
#   - FIX: correlation output is time-aligned to the input and made
#     non-negative; legacy raw negative-lag correlations are optional.
#   - FIX: the analysis/correlation channel is the strongest-RMS input
#     channel, avoiding stereo fold-down cancellation.
#   - Templates are centre-cropped to a bounded stable duration and
#     Hann tapered, rather than using arbitrarily long note regions.
#   - Correlation activation is intersected with pitch evidence.
#   - Added true pitch-class folding across octaves via max-combination
#     of octave-specific matched-filter activations.
#   - Added mechanism-first 2x2 visualization and event timeline.
# ============================================================

# === Input validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")

form Correlation-Based Pitch Class Extraction v0.7
    comment === Pitch analysis ===
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    optionmenu Method: 1
        option Accurate (cc)
        option Standard (ac)
    comment === Extraction scope ===
    optionmenu Scope: 1
        option Exact MIDI notes (legacy)
        option Pitch classes (fold octaves)
    comment Leave both target fields empty/zero to extract all detected candidates
    integer Target_MIDI_note 0
    word Target_note_name
    positive Pitch_tolerance_cents 50
    comment === Matched-filter template ===
    positive Minimum_stable_ms 60
    positive Maximum_template_ms 200
    comment === Activation gate ===
    boolean Apply_gate_function 1
    real Gate_threshold_dB -18
    boolean Normalize_activation 1
    real Peak_amplitude 0.99
    comment === Output / visualization ===
    boolean Draw_visualization 1
    boolean Keep_templates 0
    boolean Keep_raw_correlations 0
endform

# --- Parameter validation / clamping ---
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be greater than pitch floor."
endif
if pitch_tolerance_cents > 100
    pitch_tolerance_cents = 100
endif
if pitch_tolerance_cents < 1
    pitch_tolerance_cents = 1
endif
if minimum_stable_ms < 10
    minimum_stable_ms = 10
endif
if maximum_template_ms < minimum_stable_ms
    maximum_template_ms = minimum_stable_ms
endif
if gate_threshold_dB > 0
    gate_threshold_dB = 0
elsif gate_threshold_dB < -120
    gate_threshold_dB = -120
endif
if peak_amplitude <= 0
    peak_amplitude = 0.99
elsif peak_amplitude > 0.999
    peak_amplitude = 0.999
endif

minStable = minimum_stable_ms / 1000
maxTemplate = maximum_template_ms / 1000
gateRatio = 10 ^ (gate_threshold_dB / 20)

# ============================================================
# STEP 0: REPRESENTATIVE ANALYSIS CHANNEL
# ============================================================
selectObject: originalSound
duration = Get total duration
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
writeInfoLine: "=== Correlation-Based Pitch Class Extraction v0.7 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s | ", sampleRate, " Hz | ", nChannels, " ch"
appendInfoLine: "Analysis channel: ", analysisChannel, " (strongest RMS)"
if scope = 1
    appendInfoLine: "Scope: exact MIDI notes (octave-specific)"
else
    appendInfoLine: "Scope: pitch classes folded across octaves"
endif
appendInfoLine: ""

# ============================================================
# STEP 1: PITCH ANALYSIS ON REPRESENTATIVE CHANNEL
# ============================================================
appendInfoLine: "[1/7] Analyzing fundamental frequency..."
selectObject: analysisSound
if method = 1
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
voiced# = zero# (nFrames)

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
        if mm < midiMinFound
            midiMinFound = mm
        endif
        if mm > midiMaxFound
            midiMaxFound = mm
        endif
    else
        voiced#[i] = 0
        f0#[i] = 0
        midi#[i] = 0
    endif
endfor

appendInfoLine: "  Frames: ", nFrames, " | voiced: ", voicedCount
if voicedCount = 0
    removeObject: pitch, analysisSound
    exitScript: "No pitch detected. Try adjusting pitch floor/ceiling."
endif

# ============================================================
# STEP 2: UNIQUE OCTAVE-SPECIFIC MIDI NOTES
# ============================================================
appendInfoLine: "[2/7] Building measured MIDI-note candidates..."

uniqueCount = 0
for i from 1 to nFrames
    if voiced#[i] = 1
        note = round(midi#[i])
        isUnique = 1
        for j from 1 to uniqueCount
            if note = uniqueMidi_'j'
                isUnique = 0
            endif
        endfor
        if isUnique = 1
            uniqueCount += 1
            uniqueMidi_'uniqueCount' = note
        endif
    endif
endfor

# Sort MIDI notes ascending
for i from 1 to uniqueCount - 1
    for j from i + 1 to uniqueCount
        if uniqueMidi_'i' > uniqueMidi_'j'
            tmp = uniqueMidi_'i'
            uniqueMidi_'i' = uniqueMidi_'j'
            uniqueMidi_'j' = tmp
        endif
    endfor
endfor

# Measure support and average frequency for each candidate
for u from 1 to uniqueCount
    target = uniqueMidi_'u'
    support = 0
    sumHz = 0
    for i from 1 to nFrames
        if voiced#[i] = 1 and abs((midi#[i] - target) * 100) <= pitch_tolerance_cents
            support += 1
            sumHz += f0#[i]
        endif
    endfor
    uniqueSupport_'u' = support
    if support > 0
        uniqueFreq_'u' = sumHz / support
    else
        uniqueFreq_'u' = 440 * 2 ^ ((target - 69) / 12)
    endif
    @midiToName: target
    uniqueName_'u'$ = midiToName.full$
    uniquePC_'u' = midiToName.pc
endfor

appendInfoLine: "  Detected ", uniqueCount, " octave-specific MIDI candidate(s)"

# ============================================================
# STEP 3: TARGET PARSING / CANDIDATE FILTER
# ============================================================
appendInfoLine: "[3/7] Determining target set..."

manualTarget = 0
targetMidiParsed = 0
targetPCParsed = -1

if target_note_name$ <> ""
    @parseNoteName: target_note_name$
    if parseNoteName.ok = 0
        removeObject: pitch, analysisSound
        exitScript: "Could not parse target note name. Use names such as C4, F#3, Bb3, or C in pitch-class mode."
    endif
    targetPCParsed = parseNoteName.pc
    if parseNoteName.hasOctave = 1
        targetMidiParsed = parseNoteName.midi
    endif
    manualTarget = 1
elsif target_MIDI_note <> 0
    targetMidiParsed = target_MIDI_note
    targetPCParsed = target_MIDI_note mod 12
    if targetPCParsed < 0
        targetPCParsed += 12
    endif
    manualTarget = 1
endif

if scope = 1 and manualTarget = 1 and targetMidiParsed = 0
    removeObject: pitch, analysisSound
    exitScript: "Exact-MIDI scope requires an octave (for example C4) or a non-zero Target MIDI note."
endif

numExactToProcess = 0
for u from 1 to uniqueCount
    include = 0
    if manualTarget = 0
        include = 1
    elsif scope = 1
        if uniqueMidi_'u' = targetMidiParsed
            include = 1
        endif
    else
        if uniquePC_'u' = targetPCParsed
            include = 1
        endif
    endif
    if include = 1
        numExactToProcess += 1
        processUniqueIndex_'numExactToProcess' = u
    endif
endfor

if numExactToProcess = 0
    removeObject: pitch, analysisSound
    exitScript: "Requested target was not found in the measured pitch track."
endif
appendInfoLine: "  Octave-specific templates to evaluate: ", numExactToProcess

# ============================================================
# STEP 4: STABLE TEMPLATE + MATCHED-FILTER ACTIVATION PER MIDI NOTE
# ============================================================
appendInfoLine: "[4/7] Building stable templates and matched-filter activations..."

numExactExtracted = 0
keptTemplateCount = 0
keptCorrCount = 0

for p from 1 to numExactToProcess
    u = processUniqueIndex_'p'
    targetMidi = uniqueMidi_'u'
    targetName$ = uniqueName_'u'$
    targetFreq = uniqueFreq_'u'

    # Find longest truly continuous matching run on FULL Pitch timeline.
    bestStart = 0
    bestEnd = 0
    bestDur = 0
    inRun = 0
    runStart = 0

    for i from 1 to nFrames
        match = 0
        if voiced#[i] = 1 and abs((midi#[i] - targetMidi) * 100) <= pitch_tolerance_cents
            match = 1
        endif

        if match = 1
            if inRun = 0
                runStart = max(0, frameTime#[i] - pitchDX / 2)
                inRun = 1
            endif
        else
            if inRun = 1
                ip = i - 1
                runEnd = min(duration, frameTime#[ip] + pitchDX / 2)
                runDur = runEnd - runStart
                if runDur > bestDur
                    bestDur = runDur
                    bestStart = runStart
                    bestEnd = runEnd
                endif
                inRun = 0
            endif
        endif
    endfor
    if inRun = 1
        runEnd = min(duration, frameTime#[nFrames] + pitchDX / 2)
        runDur = runEnd - runStart
        if runDur > bestDur
            bestDur = runDur
            bestStart = runStart
            bestEnd = runEnd
        endif
    endif

    if bestDur < minStable
        appendInfoLine: "  ", targetName$, ": skipped; longest stable run ", fixed$(bestDur * 1000, 0), " ms < minimum ", fixed$(minimum_stable_ms, 0), " ms"
    else
        # Centre-crop the stable run to a bounded template duration.
        templateDur = min(bestDur, maxTemplate)
        centre = (bestStart + bestEnd) / 2
        templateStart = max(0, centre - templateDur / 2)
        templateEnd = min(duration, templateStart + templateDur)
        if templateEnd - templateStart < templateDur
            templateStart = max(0, templateEnd - templateDur)
        endif
        templateDur = templateEnd - templateStart

        selectObject: analysisSound
        template = Extract part: templateStart, templateEnd, "rectangular", 1, "no"
        Rename: originalName$ + "_" + targetName$ + "_template"

        # Hann taper avoids hard-edge correlation energy.
        td$ = fixed$(templateDur, 12)
        Formula: "self * (0.5 - 0.5*cos(2*pi*x/" + td$ + "))"

        # Raw lag-domain cross-correlation.
        selectObject: analysisSound
        plusObject: template
        corr = Cross-correlate: "peak 0.99", "zero"
        Rename: originalName$ + "_" + targetName$ + "_raw_correlation"

        # Convert the physically useful negative-lag half into INPUT TIME.
        # For source sample col k, correlation sample = Nsource + 1 - k.
        corrStr$ = string$(corr)
        nSrc$ = string$(sourceSamples)
        activationRaw = Create Sound from formula: originalName$ + "_" + targetName$ + "_activation_raw", 1, 0, duration, sampleRate,
            ... "abs(object[" + corrStr$ + ", 1, " + nSrc$ + " + 1 - col])"

        # Build a sample-rate pitch-eligibility gate from ALL matching runs.
        pitchGate = Create Sound from formula: "pitch_gate_" + targetName$, 1, 0, duration, sampleRate, "0"
        inGate = 0
        gateStart = 0
        for i from 1 to nFrames
            match = 0
            if voiced#[i] = 1 and abs((midi#[i] - targetMidi) * 100) <= pitch_tolerance_cents
                match = 1
            endif
            if match = 1
                if inGate = 0
                    gateStart = max(0, frameTime#[i] - pitchDX / 2)
                    inGate = 1
                endif
            else
                if inGate = 1
                    ip = i - 1
                    gateEnd = min(duration, frameTime#[ip] + pitchDX / 2)
                    selectObject: pitchGate
                    Formula (part): gateStart, gateEnd, 1, 1, "1"
                    inGate = 0
                endif
            endif
        endfor
        if inGate = 1
            gateEnd = min(duration, frameTime#[nFrames] + pitchDX / 2)
            selectObject: pitchGate
            Formula (part): gateStart, gateEnd, 1, 1, "1"
        endif

        gateStr$ = string$(pitchGate)
        selectObject: activationRaw
        Formula: "self * object[" + gateStr$ + ", 1, col]"
        rawMax = Get maximum: 0, 0, "None"

        if rawMax > 0
            threshold = rawMax * gateRatio
        else
            threshold = 1
        endif

        selectObject: activationRaw
        activation = Copy: originalName$ + "_" + targetName$ + "_activation"
        if apply_gate_function
            thr$ = fixed$(threshold, 15)
            Formula: "if self < " + thr$ + " then 0 else self fi"
        endif
        if normalize_activation
            maxAfter = Get maximum: 0, 0, "None"
            if maxAfter > 0
                Scale peak: peak_amplitude
            endif
        endif

        numExactExtracted += 1
        exactActivation_'numExactExtracted' = activation
        exactTemplate_'numExactExtracted' = template
        exactCorr_'numExactExtracted' = corr
        exactMidi_'numExactExtracted' = targetMidi
        exactPC_'numExactExtracted' = targetMidi mod 12
        if exactPC_'numExactExtracted' < 0
            exactPC_'numExactExtracted' += 12
        endif
        exactName_'numExactExtracted'$ = targetName$
        exactFreq_'numExactExtracted' = targetFreq
        exactSupport_'numExactExtracted' = uniqueSupport_'u'
        exactTemplateDur_'numExactExtracted' = templateDur
        exactRawMax_'numExactExtracted' = rawMax

        removeObject: activationRaw, pitchGate

        appendInfoLine: "  ", targetName$, ": stable ", fixed$(bestDur * 1000, 0), " ms | template ", fixed$(templateDur * 1000, 0), " ms"

        if keep_templates
            keptTemplateCount += 1
            keptTemplate_'keptTemplateCount' = template
        endif
        if keep_raw_correlations
            keptCorrCount += 1
            keptCorr_'keptCorrCount' = corr
        else
            removeObject: corr
            exactCorr_'numExactExtracted' = 0
        endif
    endif
endfor

if numExactExtracted = 0
    removeObject: pitch, analysisSound
    exitScript: "No candidate had a stable segment long enough to build a template."
endif

# ============================================================
# STEP 5: BUILD FINAL OUTPUT SET (EXACT NOTES OR FOLDED PITCH CLASSES)
# ============================================================
appendInfoLine: "[5/7] Building final activation set..."

numOutputs = 0

if scope = 1
    for ex from 1 to numExactExtracted
        numOutputs += 1
        outID_'numOutputs' = exactActivation_'ex'
        outName_'numOutputs'$ = exactName_'ex'$
        outMidi_'numOutputs' = exactMidi_'ex'
        outPC_'numOutputs' = exactPC_'ex'
        outFreq_'numOutputs' = exactFreq_'ex'
        outSupport_'numOutputs' = exactSupport_'ex'
        outTemplateDur_'numOutputs' = exactTemplateDur_'ex'
    endfor
else
    # Unique pitch classes represented by successfully built templates.
    pcCount = 0
    for ex from 1 to numExactExtracted
        pc = exactPC_'ex'
        exists = 0
        for q from 1 to pcCount
            if pc = pcList_'q'
                exists = 1
            endif
        endfor
        if exists = 0
            pcCount += 1
            pcList_'pcCount' = pc
        endif
    endfor
    # Sort pitch classes.
    for a from 1 to pcCount - 1
        for b from a + 1 to pcCount
            if pcList_'a' > pcList_'b'
                tmp = pcList_'a'
                pcList_'a' = pcList_'b'
                pcList_'b' = tmp
            endif
        endfor
    endfor

    for q from 1 to pcCount
        pc = pcList_'q'
        combined = 0
        supportSum = 0
        maxTDur = 0
        octaveList$ = ""
        first = 1
        for ex from 1 to numExactExtracted
            if exactPC_'ex' = pc
                if combined = 0
                    selectObject: exactActivation_'ex'
                    combined = Copy: "pitchclass_activation"
                else
                    otherStr$ = string$(exactActivation_'ex')
                    selectObject: combined
                    Formula: "max(self, object[" + otherStr$ + ", 1, col])"
                endif
                supportSum += exactSupport_'ex'
                if exactTemplateDur_'ex' > maxTDur
                    maxTDur = exactTemplateDur_'ex'
                endif
                if first = 1
                    octaveList$ = exactName_'ex'$
                    first = 0
                else
                    octaveList$ = octaveList$ + "," + exactName_'ex'$
                endif
            endif
        endfor

        @pcToName: pc
        selectObject: combined
        Rename: originalName$ + "_" + pcToName.name$ + "_pitchclass_activation"

        numOutputs += 1
        outID_'numOutputs' = combined
        outName_'numOutputs'$ = pcToName.name$
        outMidi_'numOutputs' = -1
        outPC_'numOutputs' = pc
        outFreq_'numOutputs' = 0
        outSupport_'numOutputs' = supportSum
        outTemplateDur_'numOutputs' = maxTDur
        outOctaves_'numOutputs'$ = octaveList$
    endfor

    # Exact-note activations are intermediates in folded mode.
    for ex from 1 to numExactExtracted
        removeObject: exactActivation_'ex'
    endfor
endif

# Count activation events on the Pitch time grid and store intervals for visualization.
eventCountTotal = 0
repOut = 1
repSupport = -1
for o from 1 to numOutputs
    if outSupport_'o' > repSupport
        repSupport = outSupport_'o'
        repOut = o
    endif

    selectObject: outID_'o'
    active = 0
    localEvents = 0
    eventStart = 0
    lastActiveTime = 0
    # Correlation of periodic tones can dip briefly between adjacent peaks.
    # Merge short gaps, but preserve real note/silence separations.
    mergeGap = max(0.03, min(0.12, outTemplateDur_'o' * 0.25))
    for i from 1 to nFrames
        vv = Get value at time: 1, frameTime#[i], "Sinc70"
        if vv = undefined
            vv = 0
        endif
        now = 0
        if vv > 0
            now = 1
        endif
        if now = 1
            if active = 0
                eventStart = max(0, frameTime#[i] - pitchDX / 2)
                active = 1
            endif
            lastActiveTime = frameTime#[i]
        elsif active = 1
            if frameTime#[i] - lastActiveTime > mergeGap
                eventEnd = min(duration, lastActiveTime + pitchDX / 2)
                localEvents += 1
                eventCountTotal += 1
                eventOut_'eventCountTotal' = o
                eventStart_'eventCountTotal' = eventStart
                eventEnd_'eventCountTotal' = eventEnd
                active = 0
            endif
        endif
    endfor
    if active = 1
        eventEnd = min(duration, lastActiveTime + pitchDX / 2)
        localEvents += 1
        eventCountTotal += 1
        eventOut_'eventCountTotal' = o
        eventStart_'eventCountTotal' = eventStart
        eventEnd_'eventCountTotal' = eventEnd
    endif
    outEvents_'o' = localEvents
endfor

# ============================================================
# STEP 6: INFO SUMMARY
# ============================================================
appendInfoLine: "[6/7] Summary..."
appendInfoLine: ""
appendInfoLine: "Note/PC     MIDI    Avg Hz     Template    Support    Events"
appendInfoLine: "-------     ----    ------     --------    -------    ------"
for o from 1 to numOutputs
    label$ = outName_'o'$
    while length(label$) < 10
        label$ = label$ + " "
    endwhile
    if outMidi_'o' >= 0
        midiTxt$ = string$(outMidi_'o')
        hzTxt$ = fixed$(outFreq_'o', 1)
    else
        midiTxt$ = "PC"
        hzTxt$ = "multi"
    endif
    while length(midiTxt$) < 4
        midiTxt$ = midiTxt$ + " "
    endwhile
    while length(hzTxt$) < 8
        hzTxt$ = hzTxt$ + " "
    endwhile
    tdTxt$ = fixed$(outTemplateDur_'o' * 1000, 0) + " ms"
    while length(tdTxt$) < 10
        tdTxt$ = tdTxt$ + " "
    endwhile
    appendInfoLine: label$, "  ", midiTxt$, "    ", hzTxt$, "  ", tdTxt$, "  ", outSupport_'o', "        ", outEvents_'o'
    if scope = 2
        appendInfoLine: "             templates: ", outOctaves_'o'$
    endif
endfor
appendInfoLine: ""
appendInfoLine: "Outputs: ", numOutputs, " activation curve(s) | matched events: ", eventCountTotal

# ============================================================
# STEP 7: VISUALIZATION
# ============================================================
if draw_visualization
    appendInfoLine: "[7/7] Drawing visualization..."
    Erase all

    # House geometry: width 8, compact 2x2, independent title strips.
    # Main title.
    Select outer viewport: 0, 8, 0, 0.42
    Select inner viewport: 0, 8, 0, 0.42
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "Correlation-Based Pitch Activation v0.7"
    Font size: 7
    Colour: "{0.35,0.35,0.40}"
    Text: 0.5, "centre", 0.18, "half", originalName$ + " | analysis ch " + string$(analysisChannel) + " | " + string$(numOutputs) + " output(s)"

    # Process strip.
    Select outer viewport: 0.25, 7.75, 0.44, 0.78
    Select inner viewport: 0.25, 7.75, 0.44, 0.78
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25,0.25,0.30}"
    Text: 0.5, "centre", 0.5, "half", "Pitch -> stable run -> Hann template -> cross-correlation -> align |r(-t)| -> pitch gate -> activation"

    # MIDI display bounds.
    vizMidiMin = floor(midiMinFound) - 2
    vizMidiMax = ceiling(midiMaxFound) + 2
    if vizMidiMax <= vizMidiMin
        vizMidiMax = vizMidiMin + 12
    endif

    # ----- A title -----
    Select outer viewport: 0.25, 3.9, 0.86, 1.12
    Select inner viewport: 0.25, 3.9, 0.86, 1.12
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "A  MEASURED CONTINUOUS PITCH"

    # ----- A data -----
    Select outer viewport: 0.25, 3.9, 1.12, 2.72
    Select inner viewport: 0.62, 3.75, 1.20, 2.58
    Axes: 0, duration, vizMidiMin - 0.5, vizMidiMax + 0.5
    Colour: "{0.96,0.96,0.96}"
    Paint rectangle: "{0.96,0.96,0.96}", 0, duration, vizMidiMin - 0.5, vizMidiMax + 0.5
    for m from vizMidiMin to vizMidiMax
        pc = m mod 12
        if pc < 0
            pc += 12
        endif
        if pc = 0
            Colour: "{0.72,0.72,0.72}"
            Line width: 1.2
        else
            Colour: "{0.88,0.88,0.88}"
            Line width: 0.5
        endif
        Draw line: 0, m, duration, m
    endfor
    Colour: "{0.18,0.40,0.72}"
    Line width: 1.5
    for i from 2 to nFrames
        if voiced#[i-1] = 1 and voiced#[i] = 1
            if frameTime#[i] - frameTime#[i-1] < pitchDX * 1.6
                Draw line: frameTime#[i-1], midi#[i-1], frameTime#[i], midi#[i]
            endif
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "MIDI"
    Text bottom: "yes", "Time (s)"

    # ----- B title -----
    Select outer viewport: 4.1, 7.75, 0.86, 1.12
    Select inner viewport: 4.1, 7.75, 0.86, 1.12
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "B  REPRESENTATIVE MATCHED-FILTER ACTIVATION"

    # ----- B data -----
    repID = outID_'repOut'
    repLabel$ = outName_'repOut'$
    selectObject: repID
    repMax = Get maximum: 0, 0, "None"
    if repMax <= 0
        repMax = 1
    endif
    Select outer viewport: 4.1, 7.75, 1.12, 2.72
    Select inner viewport: 4.48, 7.60, 1.20, 2.58
    Axes: 0, duration, 0, repMax * 1.08
    Colour: "{0.97,0.97,0.97}"
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, 0, repMax * 1.08
    # Event blocks for representative output.
    for ev from 1 to eventCountTotal
        if eventOut_'ev' = repOut
            Paint rectangle: "{0.91,0.95,1.0}", eventStart_'ev', eventEnd_'ev', 0, repMax * 1.08
        endif
    endfor
    selectObject: repID
    Colour: "{0.18,0.40,0.72}"
    Line width: 1.5
    Draw: 0, duration, 0, repMax * 1.08, "no", "Curve"
    if apply_gate_function
        if normalize_activation
            thresholdDisplay = peak_amplitude * gateRatio
        else
            thresholdDisplay = repMax * gateRatio
        endif
        Colour: "{0.65,0.30,0.30}"
        Dotted line
        Draw line: 0, thresholdDisplay, duration, thresholdDisplay
        Solid line
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Activation"
    Text bottom: "yes", "Time (s)"
    # In-panel label, kept below title strip.
    Select inner viewport: 4.48, 7.60, 1.20, 2.58
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25,0.25,0.30}"
    Text: 0.02, "left", 0.92, "half", repLabel$ + " | " + fixed$(outTemplateDur_'repOut' * 1000, 0) + " ms template | " + string$(outEvents_'repOut') + " event(s)"

    # ----- C title -----
    Select outer viewport: 0.25, 3.9, 2.88, 3.14
    Select inner viewport: 0.25, 3.9, 2.88, 3.14
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "C  PITCH-EVIDENCE SUPPORT"

    # ----- C data -----
    maxSupport = 1
    for o from 1 to numOutputs
        if outSupport_'o' > maxSupport
            maxSupport = outSupport_'o'
        endif
    endfor
    Select outer viewport: 0.25, 3.9, 3.14, 4.72
    Select inner viewport: 0.62, 3.75, 3.22, 4.56
    Axes: 0.4, numOutputs + 0.6, 0, 1.08
    Colour: "{0.97,0.97,0.97}"
    Paint rectangle: "{0.97,0.97,0.97}", 0.4, numOutputs + 0.6, 0, 1.08
    for o from 1 to numOutputs
        h = outSupport_'o' / maxSupport
        Paint rectangle: "{0.40,0.58,0.78}", o - 0.30, o + 0.30, 0, h
        if numOutputs <= 10
            Colour: "Black"
            Font size: 5
            Text: o, "centre", -0.06, "half", outName_'o'$
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Relative frames"
    if numOutputs > 10
        Text bottom: "yes", "Outputs (labels omitted >10)"
    endif

    # ----- D title -----
    Select outer viewport: 4.1, 7.75, 2.88, 3.14
    Select inner viewport: 4.1, 7.75, 2.88, 3.14
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "D  MATCHED EVENT TIMELINE"

    # ----- D data -----
    rowsShown = min(numOutputs, 10)
    Select outer viewport: 4.1, 7.75, 3.14, 4.72
    Select inner viewport: 4.52, 7.60, 3.22, 4.56
    Axes: 0, duration, 0.5, rowsShown + 0.5
    Colour: "{0.97,0.97,0.97}"
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration, 0.5, rowsShown + 0.5
    for r from 1 to rowsShown
        Colour: "{0.88,0.88,0.88}"
        Draw line: 0, r, duration, r
    endfor
    for ev from 1 to eventCountTotal
        oo = eventOut_'ev'
        if oo <= rowsShown
            Paint rectangle: "{0.30,0.55,0.78}", eventStart_'ev', eventEnd_'ev', oo - 0.28, oo + 0.28
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Time (s)"
    # Left row labels in a dedicated strip to avoid overlap.
    Select outer viewport: 4.1, 4.50, 3.14, 4.72
    Select inner viewport: 4.1, 4.50, 3.22, 4.56
    Axes: 0, 1, 0.5, rowsShown + 0.5
    Font size: 5
    for r from 1 to rowsShown
        Colour: "Black"
        Text: 0.95, "right", r, "half", outName_'r'$
    endfor

    # Footer summary.
    Select outer viewport: 0.25, 7.75, 4.90, 5.32
    Select inner viewport: 0.25, 7.75, 4.90, 5.32
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30,0.30,0.35}"
    if scope = 1
        scopeTxt$ = "exact MIDI"
    else
        scopeTxt$ = "pitch-class fold"
    endif
    Text: 0.5, "centre", 0.5, "half", "Scope: " + scopeTxt$ + " | tolerance " + fixed$(pitch_tolerance_cents, 0) + " cents | template <= " + fixed$(maximum_template_ms, 0) + " ms | gate " + fixed$(gate_threshold_dB, 0) + " dB | events " + string$(eventCountTotal)

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP / FINAL SELECTION
# ============================================================
removeObject: pitch, analysisSound

# Templates are kept until after visualization because they are part of
# the measured process. Remove them now unless explicitly requested.
if keep_templates = 0
    for ex from 1 to numExactExtracted
        removeObject: exactTemplate_'ex'
    endfor
endif

# Select final activation outputs plus optional raw process objects.
selectObject: outID_1
for o from 2 to numOutputs
    plusObject: outID_'o'
endfor
if keep_templates
    for k from 1 to keptTemplateCount
        plusObject: keptTemplate_'k'
    endfor
endif
if keep_raw_correlations
    for k from 1 to keptCorrCount
        plusObject: keptCorr_'k'
    endfor
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created ", numOutputs, " time-aligned activation curve(s)."

# ============================================================
# HELPERS
# ============================================================
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

procedure parseNoteName: .input$
    .ok = 0
    .hasOctave = 0
    .midi = 0
    .pc = -1
    .s$ = replace$(.input$, "#", "s", 0)
    .s$ = replace$(.s$, "b", "b", 0)
    .len = length(.s$)
    if .len >= 1
        .letter$ = left$(.s$, 1)
        if .letter$ = "c"
            .letter$ = "C"
        elsif .letter$ = "d"
            .letter$ = "D"
        elsif .letter$ = "e"
            .letter$ = "E"
        elsif .letter$ = "f"
            .letter$ = "F"
        elsif .letter$ = "g"
            .letter$ = "G"
        elsif .letter$ = "a"
            .letter$ = "A"
        elsif .letter$ = "b"
            .letter$ = "B"
        endif
        .acc$ = ""
        .pos = 2
        if .len >= 2
            .c2$ = mid$(.s$, 2, 1)
            if .c2$ = "s" or .c2$ = "b"
                .acc$ = .c2$
                .pos = 3
            endif
        endif

        if .letter$ = "C"
            .base = 0
        elsif .letter$ = "D"
            .base = 2
        elsif .letter$ = "E"
            .base = 4
        elsif .letter$ = "F"
            .base = 5
        elsif .letter$ = "G"
            .base = 7
        elsif .letter$ = "A"
            .base = 9
        elsif .letter$ = "B"
            .base = 11
        else
            .base = -99
        endif

        if .base >= 0
            if .acc$ = "s"
                .base += 1
            elsif .acc$ = "b"
                .base -= 1
            endif
            .pc = .base mod 12
            if .pc < 0
                .pc += 12
            endif
            .ok = 1

            if .pos <= .len
                .octText$ = right$(.s$, .len - .pos + 1)
                .oct = number(.octText$)
                if .oct <> undefined
                    .hasOctave = 1
                    .midi = (.oct + 1) * 12 + .pc
                endif
            endif
        endif
    endif
endproc
