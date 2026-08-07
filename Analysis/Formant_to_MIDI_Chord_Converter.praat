# ============================================================
# Praat AudioTools - Formant to MIDI Chord Converter with Visualizations
# Author: Shai Cohen 
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Added cent deviation visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant to MIDI Chord Converter with Visual Analysis
#   - Extracts formants and converts to MIDI chords
#   - Creates formant trajectory plots over time
#   - Generates MIDI piano roll visualization
#   - Shows spectral formant positions
#   - Displays chord progression analysis
#   - Visualizes cent deviations from pure MIDI notes
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Check if a Sound object is selected
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Formant Analysis Parameters
    comment === Analysis Parameters ===
    positive Number_of_segments 8
    positive Time_step 0.01
    positive Max_formant_Hz 5500
    positive Number_of_formants 5
    positive Window_length 0.025
    comment === Visualization Options ===
    boolean Show_formant_trajectories 0
    boolean Show_MIDI_piano_roll 0
    boolean Show_spectral_analysis 0
    boolean Show_chord_progression 0
    boolean Show_cent_deviations 0
    comment === Audio Preview ===
    boolean Play_chord_preview 1
    positive Preview_chord_duration_s 1.20
    positive Preview_attack_s 0.025
    positive Preview_decay_s 0.20
    real Preview_sustain_level 0.50
    positive Preview_release_s 0.35
    real Preview_stagger_s 0.018
    integer Preview_num_harmonics 3
    boolean Normalize_chord_preview 1
endform

clearinfo

# ------------------------------------------------------------
# Analysis source: use the loudest input channel. This avoids
# anti-phase cancellation in a mono fold-down while keeping the
# analysis independent from the output channel layout.
# ------------------------------------------------------------
selectObject: sound
duration = Get total duration
fs = Get sampling frequency
nChannels = Get number of channels
segmentDuration = duration / number_of_segments

bestRms = -1
analysisSound = 0
for ch from 1 to nChannels
    selectObject: sound
    if nChannels = 1
        tmpCh = Copy: "FormantMidi_Analysis"
    else
        tmpCh = Extract one channel: ch
    endif
    selectObject: tmpCh
    tmpRms = Get root-mean-square: 0, 0
    if tmpRms > bestRms
        if analysisSound <> 0
            removeObject: analysisSound
        endif
        analysisSound = tmpCh
        bestRms = tmpRms
    else
        removeObject: tmpCh
    endif
endfor

maxFormantEff = min(max_formant_Hz, 0.48 * fs)
if maxFormantEff < 1600
    removeObject: analysisSound
    exitScript: "Sampling rate is too low for reliable four-formant chord analysis."
endif

appendInfoLine: "=== Formant to MIDI Chord Analysis ==="
appendInfoLine: "Sound: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"
appendInfoLine: "Segments: ", number_of_segments
appendInfoLine: "Segment duration: ", fixed$(segmentDuration, 3), " seconds"
appendInfoLine: "Analysis channel: loudest of ", nChannels
if maxFormantEff < max_formant_Hz
    appendInfoLine: "Formant ceiling clamped to ", fixed$(maxFormantEff, 0), " Hz for sampling rate"
endif
appendInfoLine: ""

# Batch analysis objects.
selectObject: analysisSound
formant = To Formant (burg): time_step, number_of_formants, maxFormantEff, window_length, 50
selectObject: analysisSound
hnrObj = To Harmonicity (cc): max(time_step, 0.005), 75, 0.1, 1.0

# Store the same musical information as the original script, plus
# reliability diagnostics used only for reporting/visualization.
dataTable = Create Table with column names: "analysisData", number_of_segments,
    ... "segment time valid_fraction contrast_dB confidence F1_Hz F2_Hz F3_Hz F4_Hz F1_MIDI F2_MIDI F3_MIDI F4_MIDI F1_note F2_note F3_note F4_note F1_cents F2_cents F3_cents F4_cents"

procedure freqToMidiCent: .freq
    if .freq > 0
        .midiNote = 69 + 12 * ln(.freq / 440) / ln(2)
        .midiCent = .midiNote * 100
    else
        .midiCent = 0
        .midiNote = 0
    endif
endproc

procedure getNoteNameFromMIDI: .midiNote
    .noteNum = round(.midiNote)
    .octave = floor((.noteNum - 12) / 12)
    .pitchClass = (.noteNum - 12) mod 12
    if .pitchClass = 0
        .noteName$ = "C"
    elsif .pitchClass = 1
        .noteName$ = "C#"
    elsif .pitchClass = 2
        .noteName$ = "D"
    elsif .pitchClass = 3
        .noteName$ = "D#"
    elsif .pitchClass = 4
        .noteName$ = "E"
    elsif .pitchClass = 5
        .noteName$ = "F"
    elsif .pitchClass = 6
        .noteName$ = "F#"
    elsif .pitchClass = 7
        .noteName$ = "G"
    elsif .pitchClass = 8
        .noteName$ = "G#"
    elsif .pitchClass = 9
        .noteName$ = "A"
    elsif .pitchClass = 10
        .noteName$ = "A#"
    else
        .noteName$ = "B"
    endif
    .noteName$ = .noteName$ + string$(.octave)
endproc

# ------------------------------------------------------------
# Analyze each segment across many frames. A chord is emitted only
# when the segment has enough structurally plausible formant frames
# AND either real spectral resonance contrast or strong harmonicity.
# ------------------------------------------------------------
for segment from 1 to number_of_segments
    startTime = (segment - 1) * segmentDuration
    endTime = segment * segmentDuration
    if segment = number_of_segments
        endTime = duration
    endif
    midTime = 0.5 * (startTime + endTime)

    nProbe = max(5, floor((endTime - startTime) / max(time_step, 0.005)))
    sumF1 = 0
    sumF2 = 0
    sumF3 = 0
    sumF4 = 0
    nValid = 0

    for ip from 1 to nProbe
        t = startTime + (ip - 0.5) * (endTime - startTime) / nProbe
        selectObject: formant
        f1 = Get value at time: 1, t, "Hertz", "Linear"
        f2 = Get value at time: 2, t, "Hertz", "Linear"
        f3 = Get value at time: 3, t, "Hertz", "Linear"
        f4 = Get value at time: 4, t, "Hertz", "Linear"

        structural = 0
        if f1 <> undefined and f2 <> undefined and f3 <> undefined and f4 <> undefined
            if f1 >= 150 and f1 <= 1500 and f2 > f1 + 180 and f3 > f2 + 200 and f4 > f3 + 100 and f4 - f1 >= 1500 and f4 < 0.99 * maxFormantEff
                structural = 1
            endif
        endif
        if structural
            nValid += 1
            sumF1 += f1
            sumF2 += f2
            sumF3 += f3
            sumF4 += f4
        endif
    endfor

    validFraction = nValid / nProbe
    avgF1 = 0
    avgF2 = 0
    avgF3 = 0
    avgF4 = 0
    if nValid > 0
        avgF1 = sumF1 / nValid
        avgF2 = sumF2 / nValid
        avgF3 = sumF3 / nValid
        avgF4 = sumF4 / nValid
    endif

    # Spectral evidence from the real segment, not from the LPC model.
    contrastAvg = -99
    if nValid >= 3
        selectObject: analysisSound
        segSound = Extract part: startTime, endTime, "rectangular", 1, "no"
        selectObject: segSound
        segSpectrum = To Spectrum: "yes"

        contrastSum = 0
        contrastN = 0
        for fn from 1 to 4
            if fn = 1
                ff = avgF1
                ww = max(90, 0.06 * ff)
            elsif fn = 2
                ff = avgF2
                ww = max(130, 0.05 * ff)
            elsif fn = 3
                ff = avgF3
                ww = max(170, 0.045 * ff)
            else
                ff = avgF4
                ww = max(210, 0.04 * ff)
            endif
            lo0 = max(50, ff - ww)
            hi0 = min(0.49 * fs, ff + ww)
            lo1 = max(50, ff - 3 * ww)
            hi1 = max(50, ff - 1.5 * ww)
            lo2 = min(0.49 * fs, ff + 1.5 * ww)
            hi2 = min(0.49 * fs, ff + 3 * ww)
            if hi0 > lo0 and hi1 > lo1 and hi2 > lo2
                selectObject: segSpectrum
                ec = Get band energy: lo0, hi0
                el = Get band energy: lo1, hi1
                er = Get band energy: lo2, hi2
                side = 0.5 * (el + er)
                cdb = 10 * ln((ec + 1e-30) / (side + 1e-30)) / ln(10)
                contrastSum += cdb
                contrastN += 1
            endif
        endfor
        if contrastN > 0
            contrastAvg = contrastSum / contrastN
        endif
        removeObject: segSpectrum, segSound
    endif

    selectObject: hnrObj
    meanHnr = Get mean: startTime, endTime
    if meanHnr = undefined
        meanHnr = -99
    endif

    enoughStructure = validFraction >= 0.25 and nValid >= 3
    spectralEvidence = contrastAvg >= 2.5
    harmonicEvidence = meanHnr >= 5 and validFraction >= 0.45
    segmentValid = enoughStructure and (spectralEvidence or harmonicEvidence)

    # Confidence is diagnostic only; chord validity remains binary.
    confidence = 0
    if enoughStructure
        confidence = min(1, validFraction / 0.75)
        if spectralEvidence
            confidence = min(1, confidence * 0.7 + min(1, contrastAvg / 3) * 0.3)
        elsif harmonicEvidence
            confidence = min(1, confidence * 0.85)
        else
            confidence = 0
        endif
    endif

    selectObject: dataTable
    Set numeric value: segment, "segment", segment
    Set numeric value: segment, "time", midTime
    Set numeric value: segment, "valid_fraction", validFraction
    Set numeric value: segment, "contrast_dB", contrastAvg
    Set numeric value: segment, "confidence", confidence

    appendInfoLine: "--- Segment ", segment, " ---"
    appendInfoLine: "Time range: ", fixed$(startTime, 3), " - ", fixed$(endTime, 3), " s"
    appendInfoLine: "Valid formant frames: ", nValid, "/", nProbe, " (", fixed$(100 * validFraction, 1), "%)"
    if contrastAvg > -90
        appendInfoLine: "Spectral resonance contrast: ", fixed$(contrastAvg, 2), " dB | HNR: ", fixed$(meanHnr, 1), " dB"
    else
        appendInfoLine: "Spectral resonance contrast: unavailable | HNR: ", fixed$(meanHnr, 1), " dB"
    endif

    if segmentValid
        appendInfoLine: "Chord (4-part harmony):"
        for formantNum from 1 to 4
            if formantNum = 1
                freq = avgF1
            elsif formantNum = 2
                freq = avgF2
            elsif formantNum = 3
                freq = avgF3
            else
                freq = avgF4
            endif
            @freqToMidiCent: freq
            midiCent = freqToMidiCent.midiCent
            midiNote = freqToMidiCent.midiNote
            noteNum = round(midiNote)
            cents_deviation = round(midiCent - noteNum * 100)
            @getNoteNameFromMIDI: midiNote

            selectObject: dataTable
            Set numeric value: segment, "F" + string$(formantNum) + "_Hz", freq
            Set numeric value: segment, "F" + string$(formantNum) + "_MIDI", midiNote
            Set numeric value: segment, "F" + string$(formantNum) + "_cents", cents_deviation
            Set string value: segment, "F" + string$(formantNum) + "_note", getNoteNameFromMIDI.noteName$

            appendInfoLine: "  F", formantNum, ": ", fixed$(freq, 1), " Hz -> MIDI ", fixed$(midiNote, 2), " = ", getNoteNameFromMIDI.noteName$, " (", if cents_deviation >= 0 then "+" else "" fi, cents_deviation, " cents)"
        endfor
    else
        appendInfoLine: "Chord: -- (insufficient reliable formant evidence)"
        for formantNum from 1 to 4
            selectObject: dataTable
            Set numeric value: segment, "F" + string$(formantNum) + "_Hz", 0
            Set numeric value: segment, "F" + string$(formantNum) + "_MIDI", 0
            Set numeric value: segment, "F" + string$(formantNum) + "_cents", 0
            Set string value: segment, "F" + string$(formantNum) + "_note", "--"
        endfor
    endif
    appendInfoLine: ""
endfor

appendInfoLine: "=== Analysis Complete ==="
appendInfoLine: ""

# ============================================================
# AUDIO PREVIEW: MusicXML converter synthesis engine
# ============================================================
# Use the same synthesis architecture and defaults as
# Formant_to_MusicXML_Chord_Converter.praat: raw reliable formant
# frequencies are octave-folded into C2-C5, each voice uses a
# 1/k harmonic stack with gaussian rolloff, per-formant gains,
# ADSR and a small onset stagger. Rejected segments remain silent.
previewDur = max(0.10, preview_chord_duration_s)
previewAttack = max(0.001, preview_attack_s)
previewDecay = max(0.001, preview_decay_s)
previewSustain = max(0, min(1, preview_sustain_level))
previewRelease = max(0.001, preview_release_s)
previewStagger = max(0, preview_stagger_s)
previewHarmonics = max(1, preview_num_harmonics)
previewFs = 44100
previewTwoPi = 2 * pi
previewVoiceGain = 0.18
previewFGain[1] = 1.00
previewFGain[2] = 0.80
previewFGain[3] = 0.60
previewFGain[4] = 0.45
previewRegLow = 65
previewRegHigh = 523
previewFadeT = 0.003
previewUid$ = string$(randomInteger(10000, 99999))

# Same timing guard as the MusicXML converter.
maxPreviewStagger = (previewDur - previewRelease - previewAttack - previewDecay - 0.05) / 3
if maxPreviewStagger < 0
    exitScript: "Preview ADSR does not fit inside Preview_chord_duration_s. Increase duration or shorten A/D/R."
endif
previewStaggerClamped = min(previewStagger, maxPreviewStagger)

for seg from 1 to number_of_segments
    chordBuf = Create Sound from formula: "midiPreviewChord_" + previewUid$ + "_" + string$(seg), 1, 0, previewDur, previewFs, "0"

    for fNum from 1 to 4
        selectObject: dataTable
        segF = Get value: seg, "F" + string$(fNum) + "_Hz"
        if segF > 0
            pGain = previewFGain[fNum]

            # Exact MusicXML register-correction rule: octave-fold to C2-C5.
            playF = segF
            while playF > previewRegHigh
                playF = playF / 2
            endwhile
            while playF < previewRegLow
                playF = playF * 2
            endwhile

            onsetDelay = (fNum - 1) * previewStaggerClamped

            # Same mellow harmonic stack as MusicXML converter.
            waveFormula$ = "0"
            for k from 1 to previewHarmonics
                kAmp = previewVoiceGain * (1 / k) * exp(-((k - 1)^2) / 8) * pGain
                kFreq = k * playF
                waveFormula$ = waveFormula$ + " + " + fixed$(kAmp, 6) + " * sin(" + fixed$(previewTwoPi * kFreq, 4) + " * x)"
            endfor

            partialSnd = Create Sound from formula: "midiPreviewPart_" + previewUid$, 1, 0, previewDur, previewFs, waveFormula$

            decEnd = onsetDelay + previewAttack + previewDecay
            relStart = previewDur - previewRelease
            od$ = fixed$(onsetDelay, 6)
            at$ = fixed$(previewAttack, 6)
            dc$ = fixed$(previewDecay, 6)
            de$ = fixed$(decEnd, 6)
            rs$ = fixed$(relStart, 6)
            rl$ = fixed$(previewRelease, 6)
            sl$ = fixed$(previewSustain, 6)
            nd$ = fixed$(previewDur, 6)
            ft$ = fixed$(previewFadeT, 6)

            selectObject: partialSnd
            Formula: "if x < " + od$ + " then 0 else self fi"
            selectObject: partialSnd
            Formula: "if x >= " + od$ + " and x < " + od$ + " + " + at$ + " then self * ((x - " + od$ + ") / " + at$ + ") else self fi"
            selectObject: partialSnd
            Formula: "if x >= " + od$ + " + " + at$ + " and x < " + de$ + " then self * (1 - (1 - " + sl$ + ") * ((x - " + od$ + " - " + at$ + ") / " + dc$ + ")) else self fi"
            selectObject: partialSnd
            Formula: "if x >= " + de$ + " and x < " + rs$ + " then self * " + sl$ + " else self fi"
            selectObject: partialSnd
            Formula: "if x >= " + rs$ + " then self * " + sl$ + " * ((" + nd$ + " - x) / " + rl$ + ") else self fi"
            selectObject: partialSnd
            Formula: "if x > " + nd$ + " - " + ft$ + " then self * ((" + nd$ + " - x) / " + ft$ + ") else self fi"

            pid = partialSnd
            selectObject: chordBuf
            Formula: "self + object[pid, 1, col]"
            removeObject: partialSnd
        endif
    endfor
    previewSegSoundId[seg] = chordBuf
endfor

selectObject: previewSegSoundId[1]
for seg from 2 to number_of_segments
    plusObject: previewSegSoundId[seg]
endfor
previewSound = Concatenate
for seg from 1 to number_of_segments
    removeObject: previewSegSoundId[seg]
endfor

selectObject: previewSound
Rename: soundName$ + "_FormantMIDI_Preview"
if normalize_chord_preview
    previewPeak = Get absolute extremum: 0, 0, "Sinc70"
    if previewPeak > 0
        Scale peak: 0.95
    endif
endif
appendInfoLine: "Audio preview: ", selected$("Sound"), " (", fixed$(number_of_segments * previewDur, 2), " s)"
appendInfoLine: "  MusicXML synth engine: octave-folded reliable formants, harmonic stack, ADSR, stagger."
if play_chord_preview
    Play
endif

# ============================================================
# VISUALIZATION 1: Formant Trajectories Over Time
# ============================================================
if show_formant_trajectories
    appendInfoLine: "Creating Formant Trajectory Visualization..."
    minFreq = 1e30
    maxFreq = 0
    selectObject: dataTable
    for seg from 1 to number_of_segments
        for fnum from 1 to 4
            freq = Get value: seg, "F" + string$(fnum) + "_Hz"
            if freq > 0
                minFreq = min(minFreq, freq)
                maxFreq = max(maxFreq, freq)
            endif
        endfor
    endfor
    if maxFreq > 0
        Erase all
        Select inner viewport: 0.5, 6.5, 0.5, 3
        freqRange = max(100, maxFreq - minFreq)
        Axes: 0, duration, max(0, minFreq - 0.1 * freqRange), maxFreq + 0.1 * freqRange
        Draw inner box
        Text top: "yes", "Formant Trajectories Over Time"
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Frequency (Hz)"
        for fnum from 1 to 4
            if fnum = 1
                col$ = "Red"
            elsif fnum = 2
                col$ = "Blue"
            elsif fnum = 3
                col$ = "Green"
            else
                col$ = "Magenta"
            endif
            Colour: col$
            prevOk = 0
            for seg from 1 to number_of_segments
                selectObject: dataTable
                tt = Get value: seg, "time"
                ff = Get value: seg, "F" + string$(fnum) + "_Hz"
                if ff > 0
                    Paint circle: col$, tt, ff, 0.03
                    if prevOk
                        Draw line: prevT, prevF, tt, ff
                    endif
                    prevT = tt
                    prevF = ff
                    prevOk = 1
                else
                    prevOk = 0
                endif
            endfor
        endfor
        Colour: "Black"
        appendInfoLine: "Formant Trajectory plot created"
    else
        appendInfoLine: "Formant Trajectory plot skipped: no reliable segments"
    endif
endif

# ============================================================
# VISUALIZATION 2: MIDI Piano Roll
# ============================================================
if show_MIDI_piano_roll
    minMIDI = 1e30
    maxMIDI = 0
    selectObject: dataTable
    for seg from 1 to number_of_segments
        for fnum from 1 to 4
            mm = Get value: seg, "F" + string$(fnum) + "_MIDI"
            if mm > 0
                minMIDI = min(minMIDI, mm)
                maxMIDI = max(maxMIDI, mm)
            endif
        endfor
    endfor
    if maxMIDI > 0
        Erase all
        minMIDI = floor(minMIDI / 12) * 12
        maxMIDI = ceiling(maxMIDI / 12) * 12
        if maxMIDI <= minMIDI
            maxMIDI = minMIDI + 12
        endif
        Select inner viewport: 0.5, 7.5, 0.5, 4
        Axes: 0.5, number_of_segments + 0.5, minMIDI, maxMIDI
        Draw inner box
        Text top: "yes", "MIDI Piano Roll - Reliable Formant Chords"
        Text bottom: "yes", "Segment Number"
        Text left: "yes", "MIDI Note Number"
        boxWidth = 0.8 / 4
        for seg from 1 to number_of_segments
            for fnum from 1 to 4
                selectObject: dataTable
                mm = Get value: seg, "F" + string$(fnum) + "_MIDI"
                if mm > 0
                    if fnum = 1
                        col$ = "Red"
                    elsif fnum = 2
                        col$ = "Blue"
                    elsif fnum = 3
                        col$ = "Green"
                    else
                        col$ = "Magenta"
                    endif
                    xLeft = seg - 0.4 + (fnum - 1) * boxWidth
                    xRight = xLeft + boxWidth
                    Paint rectangle: col$, xLeft, xRight, mm - 0.5, mm + 0.5
                    Colour: "Black"
                    Draw rectangle: xLeft, xRight, mm - 0.5, mm + 0.5
                endif
            endfor
        endfor
        appendInfoLine: "MIDI Piano Roll created"
    else
        appendInfoLine: "MIDI Piano Roll skipped: no reliable chords"
    endif
endif

# ============================================================
# VISUALIZATION 3: Spectral Analysis (Formant Positions)
# ============================================================
if show_spectral_analysis
    Erase all
    numCols = ceiling(sqrt(number_of_segments))
    numRows = ceiling(number_of_segments / numCols)
    plotWidth = 7 / numCols
    plotHeight = 4.5 / numRows
    for seg from 1 to number_of_segments
        row = floor((seg - 1) / numCols)
        col = (seg - 1) mod numCols
        xLeft = 0.5 + col * plotWidth
        xRight = xLeft + plotWidth - 0.2
        yBottom = 4.5 - (row + 1) * plotHeight + 0.5
        yTop = yBottom + plotHeight - 0.5
        Select inner viewport: xLeft, xRight, yBottom, yTop
        Axes: 0, maxFormantEff, 0, 1
        selectObject: dataTable
        for fnum from 1 to 4
            ff = Get value: seg, "F" + string$(fnum) + "_Hz"
            if ff > 0
                if fnum = 1
                    col$ = "Red"
                    hh = 0.9
                elsif fnum = 2
                    col$ = "Blue"
                    hh = 0.75
                elsif fnum = 3
                    col$ = "Green"
                    hh = 0.6
                else
                    col$ = "Magenta"
                    hh = 0.45
                endif
                Colour: col$
                Draw line: ff, 0, ff, hh
            endif
        endfor
        Colour: "Black"
        Draw inner box
        Text top: "no", "Seg " + string$(seg)
    endfor
    appendInfoLine: "Spectral Analysis created"
endif

# ============================================================
# VISUALIZATION 4: Chord Progression Summary
# ============================================================
if show_chord_progression
    Erase all
    Select inner viewport: 0.5, 7.5, 0.5, 5
    Axes: 0, 10, 0, number_of_segments + 1
    Text top: "yes", "Chord Progression Summary"
    Text: 1, "centre", number_of_segments + 0.75, "half", "Segment"
    Text: 3, "centre", number_of_segments + 0.75, "half", "Time (s)"
    Text: 5, "centre", number_of_segments + 0.75, "half", "F1"
    Text: 6.5, "centre", number_of_segments + 0.75, "half", "F2"
    Text: 8, "centre", number_of_segments + 0.75, "half", "F3"
    Text: 9.5, "centre", number_of_segments + 0.75, "half", "F4"
    for seg from 1 to number_of_segments
        yPos = number_of_segments - seg + 0.5
        selectObject: dataTable
        tt = Get value: seg, "time"
        n1$ = Get value: seg, "F1_note"
        n2$ = Get value: seg, "F2_note"
        n3$ = Get value: seg, "F3_note"
        n4$ = Get value: seg, "F4_note"
        if seg mod 2 = 0
            Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, yPos - 0.4, yPos + 0.4
        endif
        Colour: "Black"
        Text: 1, "centre", yPos, "half", string$(seg)
        Text: 3, "centre", yPos, "half", fixed$(tt, 2)
        Colour: "Red"
        Text: 5, "centre", yPos, "half", n1$
        Colour: "Blue"
        Text: 6.5, "centre", yPos, "half", n2$
        Colour: "Green"
        Text: 8, "centre", yPos, "half", n3$
        Colour: "Magenta"
        Text: 9.5, "centre", yPos, "half", n4$
    endfor
    Colour: "Black"
    appendInfoLine: "Chord Progression Summary created"
endif

# ============================================================
# VISUALIZATION 5: Cent Deviations
# ============================================================
if show_cent_deviations
    Erase all
    Select inner viewport: 0.5, 6.5, 0.5, 4
    Axes: 0.5, number_of_segments + 0.5, -50, 50
    Draw inner box
    Text top: "yes", "Cent Deviations from Nearest MIDI Note"
    Text bottom: "yes", "Segment Number"
    Text left: "yes", "Cents"
    Colour: "{0.7, 0.7, 0.7}"
    Draw line: 0.5, 0, number_of_segments + 0.5, 0
    barWidth = 0.15
    for seg from 1 to number_of_segments
        for fnum from 1 to 4
            selectObject: dataTable
            cents = Get value: seg, "F" + string$(fnum) + "_cents"
            ff = Get value: seg, "F" + string$(fnum) + "_Hz"
            if ff > 0
                if fnum = 1
                    col$ = "Red"
                elsif fnum = 2
                    col$ = "Blue"
                elsif fnum = 3
                    col$ = "Green"
                else
                    col$ = "Magenta"
                endif
                xLeft = seg - 0.3 + (fnum - 1) * barWidth
                xRight = xLeft + barWidth
                if cents >= 0
                    Paint rectangle: col$, xLeft, xRight, 0, cents
                else
                    Paint rectangle: col$, xLeft, xRight, cents, 0
                endif
            endif
        endfor
    endfor
    Colour: "Black"
    appendInfoLine: "Cent Deviation plot created"
endif

removeObject: formant, hnrObj, analysisSound, dataTable
selectObject: previewSound
appendInfoLine: ""
appendInfoLine: "=== All Visualizations Complete ==="
appendInfoLine: "Check the Picture window for graphical displays"
appendInfoLine: "Audio preview remains selected for replay."
