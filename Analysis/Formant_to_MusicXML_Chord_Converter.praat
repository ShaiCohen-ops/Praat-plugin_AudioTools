# ============================================================
# Praat AudioTools - Formant_to_MusicXML_Chord_Converter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reads a Sound, segments it uniformly, and for each segment
#   extracts the time-averaged F1-F4 via Burg LPC. The four
#   formants become a 4-voice chord which is:
#     (a) written to a MusicXML file (optional, via file picker),
#         using 8th-tone microtonal alter values; and
#     (b) resynthesised as an additive chord with per-voice
#         ADSR envelope and small onset stagger.
#
#   The synthesised pitches are register-folded into C2-C5 for
#   musical listenability. This keeps pitch-class information but
#   collapses the original formant geometry (F1~700Hz and
#   F3~2500Hz both end up in the same octave window). This is a
#   deliberate artistic choice; the MusicXML output reflects the
#   same folding, so score and audio agree.
#
# Usage:
#   Select a Sound. Run. If "Write MusicXML file" is checked,
#   you will be prompted for a save path. A resynthesised
#   Sound "formant_chords_<name>" is left selected at the end.
#
# Dependencies: Praat 6.3+ only (no Python).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-
#   Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sourceId   = selected("Sound")
soundName$ = selected$("Sound")

form Formant to MusicXML Chord Converter
    positive Number_of_segments  8
    positive Max_formant_Hz       5500
    integer  Transpose_semitones -24
    positive Note_duration_s      1.2
    positive Attack_s             0.025
    positive Decay_s              0.20
    real     Sustain_level        0.50
    positive Release_s            0.35
    real     Stagger_s            0.018
    integer  Num_harmonics        3
    boolean  Write_MusicXML_file  1
    boolean  Normalize_output     1
    boolean  Play_result          1
    boolean  Draw_visualization   1
endform

# Fixed analysis/mix settings (kept compatible with v0.3).
time_step          = 0.01
number_of_formants = 5
window_length      = 0.025
tone_division      = 8
sample_rate_Hz     = 44100
fGain[1] = 1.00
fGain[2] = 0.80
fGain[3] = 0.60
fGain[4] = 0.45
voiceGain = 0.18

xmlPath$       = ""
writeXmlActual = 0
if write_MusicXML_file
    xmlPath$ = chooseWriteFile$: "Save MusicXML as...", soundName$ + "_formant_chords.xml"
    if xmlPath$ <> ""
        writeXmlActual = 1
    endif
endif

twoPi = 2 * pi
uid$  = string$(randomInteger(10000, 99999))
fColour$[1] = "{0.85, 0.22, 0.12}"
fColour$[2] = "{0.09, 0.37, 0.65}"
fColour$[3] = "{0.06, 0.43, 0.34}"
fColour$[4] = "{0.33, 0.29, 0.72}"
regLow  = 65
regHigh = 523
adsrFadeT = 0.003

maxStagger = (note_duration_s - release_s - attack_s - decay_s - 0.05) / 3
if maxStagger < 0
    exitScript: "ADSR does not fit inside note_duration_s. Increase note duration or shorten A/D/R."
endif
staggerClamped = stagger_s
if staggerClamped > maxStagger
    staggerClamped = maxStagger
endif

procedure xmlEscape: .s$
    .out$ = replace_regex$(.s$, "&", "&amp;", 0)
    .out$ = replace_regex$(.out$, "<", "&lt;", 0)
    .out$ = replace_regex$(.out$, ">", "&gt;", 0)
    .out$ = replace_regex$(.out$, """", "&quot;", 0)
    .out$ = replace_regex$(.out$, "'", "&apos;", 0)
endproc

procedure freqToMidi: .freq
    if .freq > 0
        .midiFloat = 69 + 12 * ln(.freq / 440) / ln(2) + transpose_semitones
        .midiNote  = floor(.midiFloat)
        .frac      = .midiFloat - .midiNote
        .divSteps  = round(.frac * tone_division)
        .alter     = .divSteps / tone_division
        if .alter >= 1
            .midiNote = .midiNote + floor(.alter)
            .alter    = .alter - floor(.alter)
        endif
    else
        .midiNote = 0
        .alter    = 0
    endif
endproc

procedure midiToNoteName: .midiNum
    .octave     = floor((.midiNum - 12) / 12)
    .pitchClass = (.midiNum - 12) mod 12
    .alter      = 0
    if .pitchClass = 0
        .step$ = "C"
    elsif .pitchClass = 1
        .step$ = "C"
        .alter = 1
    elsif .pitchClass = 2
        .step$ = "D"
    elsif .pitchClass = 3
        .step$ = "D"
        .alter = 1
    elsif .pitchClass = 4
        .step$ = "E"
    elsif .pitchClass = 5
        .step$ = "F"
    elsif .pitchClass = 6
        .step$ = "F"
        .alter = 1
    elsif .pitchClass = 7
        .step$ = "G"
    elsif .pitchClass = 8
        .step$ = "G"
        .alter = 1
    elsif .pitchClass = 9
        .step$ = "A"
    elsif .pitchClass = 10
        .step$ = "A"
        .alter = 1
    else
        .step$ = "B"
    endif
endproc

procedure registerCorrect: .hz
    .out = .hz
    if .out > 0
        while .out > regHigh
            .out = .out / 2
        endwhile
        while .out < regLow
            .out = .out * 2
        endwhile
    endif
endproc

# ============================================================
# Phase 1 - validity-aware per-segment formant landmarks
# ============================================================
clearinfo
writeInfoLine: "=== Formant to MusicXML Chord Converter ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "[1/5] Extracting reliable formant landmarks..."

selectObject: sourceId
totalSourceDur  = Get total duration
sourceFs        = Get sampling frequency
nSourceCh       = Get number of channels
segmentDuration = totalSourceDur / number_of_segments

if totalSourceDur < 0.1
    exitScript: "Sound too short (minimum 0.1 seconds)."
endif

# Analyze the loudest physical channel. This avoids anti-phase
# cancellation in a mono fold-down while keeping multichannel input intact.
bestRms = -1
analysisSound = 0
for ch from 1 to nSourceCh
    selectObject: sourceId
    if nSourceCh = 1
        tmpCh = Copy: "fmtxml_analysis"
    else
        tmpCh = Extract one channel: ch
    endif
    selectObject: tmpCh
    chRms = Get root-mean-square: 0, 0
    if chRms > bestRms
        if analysisSound <> 0
            removeObject: analysisSound
        endif
        analysisSound = tmpCh
        bestRms = chRms
    else
        removeObject: tmpCh
    endif
endfor

maxFormantEff = min(max_formant_Hz, 0.48 * sourceFs)
if maxFormantEff < 1600
    removeObject: analysisSound
    exitScript: "Sampling rate is too low for reliable four-formant chord analysis."
endif
if maxFormantEff < max_formant_Hz
    appendInfoLine: "  Formant ceiling clamped to ", fixed$(maxFormantEff, 0), " Hz for sampling rate."
endif
appendInfoLine: "  Analysis channel: loudest of ", nSourceCh

selectObject: analysisSound
formantObj = To Formant (burg): time_step, number_of_formants, maxFormantEff, window_length, 50
selectObject: analysisSound
hnrObj = To Harmonicity (cc): max(time_step, 0.005), 75, 0.1, 1.0

nAccepted = 0
for seg from 1 to number_of_segments
    tStart = (seg - 1) * segmentDuration
    tEnd   = seg * segmentDuration
    if seg = number_of_segments
        tEnd = totalSourceDur
    endif

    nProbe = max(5, floor((tEnd - tStart) / max(time_step, 0.005)))
    sumF1 = 0
    sumF2 = 0
    sumF3 = 0
    sumF4 = 0
    nValid = 0

    for ip from 1 to nProbe
        t = tStart + (ip - 0.5) * (tEnd - tStart) / nProbe
        selectObject: formantObj
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

    # Real spectral evidence around the four candidate landmarks.
    contrastAvg = -99
    contrastGood = 0
    if nValid >= 3
        selectObject: analysisSound
        segSound = Extract part: tStart, tEnd, "rectangular", 1, "no"
        selectObject: segSound
        segSpectrum = To Spectrum: "yes"
        contrastSum = 0
        contrastN = 0
        contrastGood = 0
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
            hi0 = min(0.49 * sourceFs, ff + ww)
            lo1 = max(50, ff - 3 * ww)
            hi1 = max(50, ff - 1.5 * ww)
            lo2 = min(0.49 * sourceFs, ff + 1.5 * ww)
            hi2 = min(0.49 * sourceFs, ff + 3 * ww)
            if hi0 > lo0 and hi1 > lo1 and hi2 > lo2
                selectObject: segSpectrum
                ec = Get band energy: lo0, hi0
                el = Get band energy: lo1, hi1
                er = Get band energy: lo2, hi2
                side = 0.5 * (el + er)
                cdb = 10 * ln((ec + 1e-30) / (side + 1e-30)) / ln(10)
                contrastSum += cdb
                contrastN += 1
                if cdb >= 1.5
                    contrastGood += 1
                endif
            endif
        endfor
        if contrastN > 0
            contrastAvg = contrastSum / contrastN
        endif
        removeObject: segSpectrum, segSound
    endif

    selectObject: hnrObj
    meanHnr = Get mean: tStart, tEnd
    if meanHnr = undefined
        meanHnr = -99
    endif

    enoughStructure = validFraction >= 0.25 and nValid >= 3
    spectralEvidence = contrastAvg >= 3.5 and contrastGood >= 3
    harmonicEvidence = meanHnr >= 5 and validFraction >= 0.45
    segmentValid = enoughStructure and (spectralEvidence or harmonicEvidence)

    segValid[seg] = segmentValid
    segValidFraction[seg] = validFraction
    segContrast[seg] = contrastAvg
    segHnr[seg] = meanHnr

    if segmentValid
        nAccepted += 1
        segFreq[seg, 1] = avgF1
        segFreq[seg, 2] = avgF2
        segFreq[seg, 3] = avgF3
        segFreq[seg, 4] = avgF4
    else
        for fNum from 1 to 4
            segFreq[seg, fNum] = 0
        endfor
    endif

    appendInfoLine: "  Segment ", seg, ": valid ", fixed$(100 * validFraction, 1),
        ... "% | contrast ", if contrastAvg > -90 then fixed$(contrastAvg, 2) else "n/a" fi,
        ... " dB | HNR ", fixed$(meanHnr, 1), " dB | ",
        ... if segmentValid then "CHORD" else "REST" fi
endfor

appendInfoLine: "  Reliable chords: ", nAccepted, "/", number_of_segments

for seg from 1 to number_of_segments
    for fNum from 1 to 4
        if segFreq[seg, fNum] > 0
            @freqToMidi: segFreq[seg, fNum]
            storedMidi[seg, fNum]  = freqToMidi.midiNote
            storedAlter[seg, fNum] = freqToMidi.alter
        else
            storedMidi[seg, fNum]  = 0
            storedAlter[seg, fNum] = 0
        endif
    endfor
endfor

# ============================================================
# Phase 2 - MusicXML
# ============================================================
if writeXmlActual
    appendInfoLine: "[2/5] Writing MusicXML to:"
    appendInfoLine: "  ", xmlPath$
    @xmlEscape: soundName$
    titleEsc$ = xmlEscape.out$

    xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
    xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
    xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$
    xml$ = xml$ + "  <work><work-title>Formant Analysis: " + titleEsc$ + "</work-title></work>" + newline$
    xml$ = xml$ + "  <identification><creator type=""software"">Praat AudioTools - Formant Chord Converter</creator></identification>" + newline$
    xml$ = xml$ + "  <part-list><score-part id=""P1""><part-name>Formant Chords</part-name></score-part></part-list>" + newline$
    xml$ = xml$ + "  <part id=""P1"">" + newline$

    for seg from 1 to number_of_segments
        xml$ = xml$ + "    <measure number=""" + string$(seg) + """>" + newline$
        if seg = 1
            xml$ = xml$ + "      <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>" + newline$
        endif

        noteIndex = 0
        for fNum from 1 to 4
            if storedMidi[seg, fNum] > 0
                noteIndex += 1
                @midiToNoteName: storedMidi[seg, fNum]
                step$      = midiToNoteName.step$
                octaveOut  = midiToNoteName.octave
                baseAlter  = midiToNoteName.alter
                microAlter = storedAlter[seg, fNum]
                totalAlter = baseAlter + microAlter
                xml$ = xml$ + "      <note>" + newline$
                if noteIndex > 1
                    xml$ = xml$ + "        <chord/>" + newline$
                endif
                xml$ = xml$ + "        <pitch><step>" + step$ + "</step>"
                if totalAlter <> 0
                    xml$ = xml$ + "<alter>" + fixed$(totalAlter, 4) + "</alter>"
                endif
                xml$ = xml$ + "<octave>" + string$(octaveOut) + "</octave></pitch>" + newline$
                xml$ = xml$ + "        <duration>4</duration><type>whole</type>" + newline$
                xml$ = xml$ + "      </note>" + newline$
            endif
        endfor

        if noteIndex = 0
            xml$ = xml$ + "      <note><rest/><duration>4</duration><type>whole</type></note>" + newline$
        endif
        xml$ = xml$ + "    </measure>" + newline$
    endfor
    xml$ = xml$ + "  </part>" + newline$ + "</score-partwise>" + newline$
    writeFile: xmlPath$, xml$
    appendInfoLine: "  MusicXML written (", length(xml$), " bytes)."
else
    appendInfoLine: "[2/5] MusicXML output skipped."
endif

# ============================================================
# Phase 3 - same additive/ADSR synth engine as v0.3
# ============================================================
appendInfoLine: "[3/5] Synthesising ", number_of_segments, " chords/rests..."
for seg from 1 to number_of_segments
    chordBuf = Create Sound from formula: "chord_" + uid$ + "_" + string$(seg), 1, 0, note_duration_s, sample_rate_Hz, "0"

    for fNum from 1 to 4
        segF = segFreq[seg, fNum]
        if segF > 0
            pGain = fGain[fNum]
            @registerCorrect: segF
            playF = registerCorrect.out
            onsetDelay = (fNum - 1) * staggerClamped

            waveFormula$ = "0"
            for k from 1 to num_harmonics
                kAmp  = voiceGain * (1 / k) * exp(-((k - 1)^2) / 8) * pGain
                kFreq = k * playF
                waveFormula$ = waveFormula$ + " + " + fixed$(kAmp, 6) + " * sin(" + fixed$(twoPi * kFreq, 4) + " * x)"
            endfor

            partialSnd = Create Sound from formula: "p_" + uid$, 1, 0, note_duration_s, sample_rate_Hz, waveFormula$
            decEnd   = onsetDelay + attack_s + decay_s
            relStart = note_duration_s - release_s
            od$ = fixed$(onsetDelay, 6)
            at$ = fixed$(attack_s, 6)
            dc$ = fixed$(decay_s, 6)
            de$ = fixed$(decEnd, 6)
            rs$ = fixed$(relStart, 6)
            rl$ = fixed$(release_s, 6)
            sl$ = fixed$(sustain_level, 6)
            nd$ = fixed$(note_duration_s, 6)
            ft$ = fixed$(adsrFadeT, 6)

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
    segSoundId[seg] = chordBuf
endfor
appendInfoLine: "  Done."

# ============================================================
# Phase 4 - concatenate
# ============================================================
appendInfoLine: "[4/5] Concatenating..."
selectObject: segSoundId[1]
for seg from 2 to number_of_segments
    plusObject: segSoundId[seg]
endfor
outputSound = Concatenate
for seg from 1 to number_of_segments
    removeObject: segSoundId[seg]
endfor

selectObject: outputSound
Rename: "formant_chords_" + soundName$
if normalize_output
    outPeak = Get absolute extremum: 0, 0, "Sinc70"
    if outPeak > 1e-12
        Scale peak: 0.95
    endif
endif

# ============================================================
# Phase 5 - confidence-aware visualization
# ============================================================
if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."
    Erase all
    Select outer viewport: 0, 8, 0, 8

    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Formant-to-MusicXML Chord Converter##"
    Font size: 7
    Text: 0.5, "centre", 0.20, "half", soundName$ + " | reliable chords=" + string$(nAccepted) + "/" + string$(number_of_segments)

    # Source spectrogram from the analysis channel.
    Select outer viewport: 0, 8, 0.60, 3.10
    Select inner viewport: 0.65, 7.7, 0.70, 3.00
    selectObject: analysisSound
    To Spectrogram: 0.03, maxFormantEff, 0.002, 20, "Gaussian"
    specObj = selected("Spectrogram")
    Paint: 0, 0, 0, maxFormantEff, 100, "yes", 50, 6, 0, "no"
    Axes: 0, totalSourceDur, 0, maxFormantEff

    # Only accepted landmarks are drawn; rejected Burg tracks are omitted.
    Line width: 2
    for fNum from 1 to 4
        Colour: fColour$[fNum]
        havePrev = 0
        for seg from 1 to number_of_segments
            if segFreq[seg, fNum] > 0
                tMid = (seg - 0.5) * segmentDuration
                hz = segFreq[seg, fNum]
                Paint circle: fColour$[fNum], tMid, hz, 0.035
                if havePrev
                    Draw line: prevT, prevHz, tMid, hz
                endif
                prevT = tMid
                prevHz = hz
                havePrev = 1
            else
                havePrev = 0
            endif
        endfor
    endfor
    Line width: 0.7
    Colour: "{0.4,0.4,0.4}"
    for seg from 0 to number_of_segments
        segT = min(totalSourceDur, seg * segmentDuration)
        Draw line: segT, 0, segT, maxFormantEff
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Accepted per-segment formant landmarks only"
    removeObject: specObj

    # Chord/rest timeline.
    Select outer viewport: 0, 8, 3.25, 5.45
    Select inner viewport: 0.65, 7.7, 3.35, 5.35
    Axes: 0.5, number_of_segments + 0.5, 0, 1
    Paint rectangle: "{0.97,0.97,0.97}", 0.5, number_of_segments + 0.5, 0, 1
    for seg from 1 to number_of_segments
        if segValid[seg]
            Paint rectangle: "{0.82,0.92,0.84}", seg - 0.42, seg + 0.42, 0.12, 0.88
            Colour: "Black"
            Text: seg, "centre", 0.70, "half", "Chord"
            Text: seg, "centre", 0.40, "half", fixed$(segContrast[seg], 1) + " dB"
            Text: seg, "centre", 0.20, "half", fixed$(100 * segValidFraction[seg], 0) + "%"
        else
            Paint rectangle: "{0.92,0.88,0.88}", seg - 0.42, seg + 0.42, 0.12, 0.88
            Colour: "Black"
            Text: seg, "centre", 0.55, "half", "REST"
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "Segment"
    Text top: "no", "Reliability gate: valid-frame fraction + spectral contrast / harmonic evidence"

    # Summary.
    Select outer viewport: 0, 8, 5.65, 7.75
    Select inner viewport: 0.65, 7.7, 5.75, 7.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.86, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.66, "half", "Reliable chords: " + string$(nAccepted) + "/" + string$(number_of_segments) + " | source SR=" + string$(sourceFs) + " Hz | formant ceiling=" + fixed$(maxFormantEff,0) + " Hz"
    Text: 0.02, "left", 0.46, "half", "Note=" + fixed$(note_duration_s,2) + "s | A=" + fixed$(attack_s*1000,0) + "ms D=" + fixed$(decay_s*1000,0) + "ms S=" + fixed$(sustain_level,2) + " R=" + fixed$(release_s*1000,0) + "ms"
    xmlStatus$ = "skipped"
    if writeXmlActual
        xmlStatus$ = "written"
    endif
    Text: 0.02, "left", 0.26, "half", "Harmonics=" + string$(num_harmonics) + " | stagger=" + fixed$(staggerClamped*1000,0) + "ms | MusicXML=" + xmlStatus$ + " | normalize=" + string$(normalize_output)
    Text: 0.02, "left", 0.08, "half", "Rejected segments are RESTS in both score and audio; no canonical formant fallback."
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

removeObject: formantObj, hnrObj, analysisSound
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== DONE ==="
appendInfoLine: "Output Sound: ", selected$("Sound")
appendInfoLine: "Reliable chords: ", nAccepted, "/", number_of_segments
appendInfoLine: "Total duration: ", fixed$(note_duration_s * number_of_segments, 2), " s"
if writeXmlActual
    appendInfoLine: "MusicXML file: ", xmlPath$
endif
if play_result
    Play
endif
selectObject: outputSound
