# ============================================================
# Praat AudioTools - Formant_to_MusicXML_Chord_Converter
#                    With Additive Player
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Additive resynthesis player companion to
#   Formant_to_MusicXML_Chord_Converter.
#   Re-analyses the selected Sound, extracts F1-F4 per segment,
#   renders each segment as a 4-voice additive chord using a
#   mellow multi-partial waveform (soft organ/cello tone) shaped
#   by a piano ADSR envelope.
#
#
# Usage:
#   Select the same Sound object used in the Converter and run.
#   Match Number_of_segments and analysis settings to the Converter.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound      = selected("Sound")
soundName$ = selected$("Sound")

# ============================================================
# Form
# ============================================================
form Formant to MusicXML Chord Converter Player
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
    boolean  Normalize_output     1
    boolean  Play_result          1
    boolean  Draw_visualization   1
endform

# Fixed analysis/mix settings (edit here if needed)
time_step          = 0.01
number_of_formants = 5
window_length      = 0.025
tone_division      = 8
sample_rate_Hz     = 44100
fGain[1] = 1.00
fGain[2] = 0.80
fGain[3] = 0.60
fGain[4] = 0.45

# ============================================================
# Constants
# ============================================================
twoPi = 2 * pi
uid$  = string$(randomInteger(10000, 99999))

fColour$[1] = "{0.85, 0.22, 0.12}"
fColour$[2] = "{0.09, 0.37, 0.65}"
fColour$[3] = "{0.06, 0.43, 0.34}"
fColour$[4] = "{0.33, 0.29, 0.72}"

# Register target: keep synthesised pitch between C2 (65 Hz) and C5 (523 Hz)
regLow  = 65
regHigh = 523

# ADSR breakpoints — computed after form, safe here
adsrDecEnd   = attack_s + decay_s
adsrRelStart = note_duration_s - release_s
adsrFadeT    = 0.003

# ============================================================
# Procedures
# ============================================================

procedure freqToMidi: .freq
    if .freq > 0
        .midiFloat = 69 + 12 * ln(.freq / 440) / ln(2) + transpose_semitones
        .midiNote  = floor(.midiFloat)
        fractionalSemitones = .midiFloat - .midiNote
        divisionSteps = round(fractionalSemitones * tone_division)
        .alter = divisionSteps / tone_division
        if .alter >= 1
            .midiNote = .midiNote + floor(.alter)
            .alter    = .alter - floor(.alter)
        endif
    else
        .midiNote = 0
        .alter    = 0
    endif
endproc

# Get note name and octave from MIDI number (same as Converter)
procedure midiToNoteName: .midiNum
    .octave = floor((.midiNum - 12) / 12)
    .pitchClass = (.midiNum - 12) mod 12
    .alter = 0
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
    elsif .pitchClass = 11
        .step$ = "B"
    endif
endproc

procedure midiToDiatonic: .midiNum
    .pc  = (.midiNum - 12) mod 12
    .oct = floor((.midiNum - 12) / 12)
    if .pc = 0
        .dia = 0
    elsif .pc = 1
        .dia = 0
    elsif .pc = 2
        .dia = 1
    elsif .pc = 3
        .dia = 1
    elsif .pc = 4
        .dia = 2
    elsif .pc = 5
        .dia = 3
    elsif .pc = 6
        .dia = 3
    elsif .pc = 7
        .dia = 4
    elsif .pc = 8
        .dia = 4
    elsif .pc = 9
        .dia = 5
    elsif .pc = 10
        .dia = 5
    elsif .pc = 11
        .dia = 6
    endif
    .diatonic = .oct * 7 + .dia
endproc

# Octave-shift a frequency into [regLow, regHigh]
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
# Phase 1 — Extract formant frequencies
# ============================================================
clearinfo
appendInfoLine: "=== Formant to MusicXML Chord Converter Player ==="
appendInfoLine: "Source: ", soundName$

selectObject: sound
totalSourceDur  = Get total duration
segmentDuration = totalSourceDur / number_of_segments

selectObject: sound
formantObj = To Formant (burg): time_step, number_of_formants, max_formant_Hz, window_length, 50

for seg from 1 to number_of_segments
    midTime = ((seg - 1) + 0.5) * segmentDuration
    selectObject: formantObj
    for fNum from 1 to 4
        fHz = Get value at time: fNum, midTime, "hertz", "Linear"
        if fHz <> undefined and fHz > 0
            segFreq[seg, fNum] = fHz
        else
            segFreq[seg, fNum] = 0
        endif
    endfor
endfor

removeObject: formantObj
appendInfoLine: "Formant extraction done."

# ============================================================
# MusicXML output to Info window (same as Converter)
# ============================================================

# Build storedMidi and storedAlter arrays for XML output
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

writeInfoLine: "<?xml version=""1.0"" encoding=""UTF-8""?>"
appendInfoLine: "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">"
appendInfoLine: "<score-partwise version=""3.1"">"
appendInfoLine: "  <work>"
appendInfoLine: "    <work-title>Formant Analysis: ", soundName$, "</work-title>"
appendInfoLine: "  </work>"
appendInfoLine: "  <identification>"
appendInfoLine: "    <creator type=""software"">Praat Formant Analyzer</creator>"
appendInfoLine: "  </identification>"
appendInfoLine: "  <part-list>"
appendInfoLine: "    <score-part id=""P1"">"
appendInfoLine: "      <part-name>Formant Chords</part-name>"
appendInfoLine: "    </score-part>"
appendInfoLine: "  </part-list>"
appendInfoLine: "  <part id=""P1"">"

for seg from 1 to number_of_segments
    appendInfoLine: "    <measure number=""", seg, """>"

    if seg = 1
        appendInfoLine: "      <attributes>"
        appendInfoLine: "        <divisions>1</divisions>"
        appendInfoLine: "        <key>"
        appendInfoLine: "          <fifths>0</fifths>"
        appendInfoLine: "        </key>"
        appendInfoLine: "        <time>"
        appendInfoLine: "          <beats>4</beats>"
        appendInfoLine: "          <beat-type>4</beat-type>"
        appendInfoLine: "        </time>"
        appendInfoLine: "        <clef>"
        appendInfoLine: "          <sign>G</sign>"
        appendInfoLine: "          <line>2</line>"
        appendInfoLine: "        </clef>"
        appendInfoLine: "      </attributes>"
    endif

    noteCount = 0
    noteIndex = 0
    for fNum from 1 to 4
        if storedMidi[seg, fNum] > 0
            noteCount += 1
            noteIndex += 1

            @midiToNoteName: storedMidi[seg, fNum]
            step$ = midiToNoteName.step$
            octave = midiToNoteName.octave

            appendInfoLine: "      <note>"
            if noteIndex > 1
                appendInfoLine: "        <chord/>"
            endif
            appendInfoLine: "        <pitch>"
            appendInfoLine: "          <step>", step$, "</step>"

            baseAlter  = midiToNoteName.alter
            microAlter = storedAlter[seg, fNum]
            totalAlter = baseAlter + microAlter
            if totalAlter <> 0
                appendInfoLine: "          <alter>", totalAlter, "</alter>"
            endif

            appendInfoLine: "          <octave>", octave, "</octave>"
            appendInfoLine: "        </pitch>"
            appendInfoLine: "        <duration>4</duration>"
            appendInfoLine: "        <type>whole</type>"
            appendInfoLine: "      </note>"
        endif
    endfor

    if noteCount = 0
        appendInfoLine: "      <note>"
        appendInfoLine: "        <rest/>"
        appendInfoLine: "        <duration>4</duration>"
        appendInfoLine: "        <type>whole</type>"
        appendInfoLine: "      </note>"
    endif

    appendInfoLine: "    </measure>"
endfor

appendInfoLine: "  </part>"
appendInfoLine: "</score-partwise>"

# ============================================================
# Phase 2 — Synthesise one chord per segment
#
# Each voice (F1-F4):
#   1. Register-correct the frequency into C2-C5
#   2. Build a mellow waveform: sum of num_harmonics sine partials
#      with 1/n amplitude and a soft gaussian spectral rolloff
#   3. Apply piano ADSR with per-voice onset stagger
#   4. Mix into a shared chord buffer
# ============================================================
appendInfoLine: "Synthesising ", number_of_segments, " chords..."

for seg from 1 to number_of_segments

    chordBuf = Create Sound from formula: "chord_" + uid$ + "_" + string$(seg),
        ... 1, 0, note_duration_s, sample_rate_Hz, "0"

    for fNum from 1 to 4
        segF = segFreq[seg, fNum]
        if segF > 0
            pGain = fGain[fNum]

            # --- Register correction ---
            @registerCorrect: segF
            playF = registerCorrect.out

            # --- Onset stagger: voice fNum starts fNum*stagger_s later ---
            onsetDelay = (fNum - 1) * stagger_s

            # --- Build mellow waveform as sum of harmonics ---
            # Each harmonic k: amplitude = (1/k) * gaussian(k, sigma=2)
            # Gaussian softens upper harmonics for a mellow timbre.
            # We write the full formula string as a sum over num_harmonics.

            # Build mellow waveform: sum of harmonics with 1/k gaussian rolloff.
            # Amplitude and frequency are baked in as literals so the formula
            # string contains no variable names (safe for Praat Formula engine).
            # Onset silencing is handled separately by a Formula pass below.
            waveFormula$ = "0"
            for k from 1 to num_harmonics
                kAmp = (1 / k) * exp(-((k - 1)^2) / (2 * 4)) * pGain
                kFreq = k * playF
                waveFormula$ = waveFormula$ + " + " +
                    ... fixed$(kAmp, 6) + " * sin(" + fixed$(twoPi * kFreq, 4) + " * x)"
            endfor

            partialSnd = Create Sound from formula: "p_" + uid$,
                ... 1, 0, note_duration_s, sample_rate_Hz,
                ... waveFormula$

            # --- Piano ADSR (four passes, relative to onset) ---
            # We shift the ADSR window by onsetDelay so it tracks
            # the staggered onset correctly.
            voiceDecEnd   = onsetDelay + attack_s + decay_s
            voiceRelStart = onsetDelay + note_duration_s - release_s - onsetDelay
            # (relStart stays at note_duration_s - release_s, independent of onset)
            voiceRelStart = note_duration_s - release_s

            # Zero out samples before onset, then apply attack ramp
            selectObject: partialSnd
            Formula: "if x < onsetDelay then 0 else self fi"

            selectObject: partialSnd
            Formula: "if x >= onsetDelay and x < onsetDelay + attack_s then self * ((x - onsetDelay) / attack_s) else self fi"

            selectObject: partialSnd
            Formula: "if x >= onsetDelay + attack_s and x < voiceDecEnd then self * (1 - (1 - sustain_level) * ((x - onsetDelay - attack_s) / decay_s)) else self fi"

            selectObject: partialSnd
            Formula: "if x >= voiceDecEnd and x < voiceRelStart then self * sustain_level else self fi"

            selectObject: partialSnd
            Formula: "if x >= voiceRelStart then self * sustain_level * ((note_duration_s - x) / release_s) else self fi"

            # Global fade-out only (onset fade handled above)
            selectObject: partialSnd
            Formula: "if x > note_duration_s - adsrFadeT then self * ((note_duration_s - x) / adsrFadeT) else self fi"

            # --- Mix into chord buffer ---
            pid = partialSnd
            selectObject: chordBuf
            Formula: "self + object[pid, 1, col]"

            removeObject: partialSnd
        endif
    endfor

    segSoundId[seg] = chordBuf
    appendInfoLine: "  Segment ", seg, " done."

endfor

# ============================================================
# Phase 3 — Concatenate
# ============================================================
appendInfoLine: "Concatenating..."

selectObject: segSoundId[1]
for seg from 2 to number_of_segments
    plusObject: segSoundId[seg]
endfor
outputSound = Concatenate

for seg from 1 to number_of_segments
    removeObject: segSoundId[seg]
endfor

# ============================================================
# Normalize and rename
# ============================================================
selectObject: outputSound
Rename: "formant_chords_" + soundName$

if normalize_output
    selectObject: outputSound
    Scale peak: 0.95
endif

# ============================================================
# Visualization — notation style (mirrors Converter)
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawNotationViz
endif

# ============================================================
# Play
# ============================================================
if play_result
    appendInfoLine: "Playing..."
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Total duration: ", fixed$(note_duration_s * number_of_segments, 2), " s"


# ============================================================
# Procedure: drawNotationViz
# Staff-notation style, identical layout to the Converter.
# Uses register-corrected frequencies for correct staff placement.
# ============================================================
procedure drawNotationViz

    # --- Collect MIDI / diatonic data ---
    globalMinDia = 999
    globalMaxDia = -999

    for seg from 1 to number_of_segments
        for fNum from 1 to 4
            if segFreq[seg, fNum] > 0
                # Use register-corrected pitch for staff placement
                @registerCorrect: segFreq[seg, fNum]
                @freqToMidi: registerCorrect.out
                segMidi[seg, fNum] = freqToMidi.midiNote
                @midiToDiatonic: freqToMidi.midiNote
                segDia[seg, fNum] = midiToDiatonic.diatonic
                if midiToDiatonic.diatonic < globalMinDia
                    globalMinDia = midiToDiatonic.diatonic
                endif
                if midiToDiatonic.diatonic > globalMaxDia
                    globalMaxDia = midiToDiatonic.diatonic
                endif
            else
                segMidi[seg, fNum] = 0
                segDia[seg, fNum]  = 0
            endif
        endfor
    endfor

    if globalMinDia = 999
        globalMinDia = 28
        globalMaxDia = 38
    endif

    plotMinDia = globalMinDia - 3
    plotMaxDia = globalMaxDia + 3

    # --- Staff diatonic positions ---
    trebleLine1 = 30
    trebleLine2 = 32
    trebleLine3 = 34
    trebleLine4 = 36
    trebleLine5 = 38

    bassLine1 = 18
    bassLine2 = 20
    bassLine3 = 22
    bassLine4 = 24
    bassLine5 = 26

    middleC = 28

    drawTreble = 0
    drawBass   = 0
    if globalMaxDia >= middleC
        drawTreble = 1
    endif
    if globalMinDia < middleC
        drawBass = 1
    endif
    if drawTreble = 0 and drawBass = 0
        drawTreble = 1
        drawBass   = 1
    endif

    # --- Picture window ---
    Erase all
    Select outer viewport: 0, 8, 0, 5.5
    Select inner viewport: 0.6, 7.7, 0.4, 4.8

    xMin = 0
    xMax = number_of_segments + 1.5
    Axes: xMin, xMax, plotMinDia - 1, plotMaxDia + 1

    staffLeft  = 0.8
    staffRight = number_of_segments + 0.8

    # --- Staff lines ---
    Colour: {0.45, 0.45, 0.45}
    Line width: 1

    if drawTreble = 1
        for li from 1 to 5
            if li = 1
                yLine = trebleLine1
            elsif li = 2
                yLine = trebleLine2
            elsif li = 3
                yLine = trebleLine3
            elsif li = 4
                yLine = trebleLine4
            elsif li = 5
                yLine = trebleLine5
            endif
            Draw line: staffLeft, yLine, staffRight, yLine
        endfor
    endif

    if drawBass = 1
        for li from 1 to 5
            if li = 1
                yLine = bassLine1
            elsif li = 2
                yLine = bassLine2
            elsif li = 3
                yLine = bassLine3
            elsif li = 4
                yLine = bassLine4
            elsif li = 5
                yLine = bassLine5
            endif
            Draw line: staffLeft, yLine, staffRight, yLine
        endfor
    endif

    # --- Barlines ---
    Colour: {0.55, 0.55, 0.55}
    Line width: 0.8
    for seg from 1 to number_of_segments + 1
        barX = seg - 0.5 + 0.8
        if barX <= staffRight
            if drawTreble = 1 and drawBass = 1
                Draw line: barX, bassLine1, barX, trebleLine5
            elsif drawTreble = 1
                Draw line: barX, trebleLine1, barX, trebleLine5
            else
                Draw line: barX, bassLine1, barX, bassLine5
            endif
        endif
    endfor

    # --- Clef labels ---
    Font size: 7
    Colour: {0.3, 0.3, 0.3}
    if drawTreble = 1
        Text special: 0.4, "centre", trebleLine3, "half", "Helvetica", 7, "0", "T"
    endif
    if drawBass = 1
        Text special: 0.4, "centre", bassLine3, "half", "Helvetica", 7, "0", "B"
    endif

    # --- Segment numbers ---
    Font size: 6
    Colour: {0.5, 0.5, 0.5}
    for seg from 1 to number_of_segments
        noteX = seg + 0.3
        Text special: noteX, "centre", plotMinDia - 0.5, "top", "Helvetica", 6, "0", string$(seg)
    endfor

    # --- Noteheads, ledger lines, Hz annotations ---
    noteW = 0.25
    noteH = 0.7

    for seg from 1 to number_of_segments
        noteX = seg + 0.3

        for fNum from 1 to 4
            if segMidi[seg, fNum] > 0
                noteY = segDia[seg, fNum]

                # Ledger lines
                Colour: {0.55, 0.55, 0.55}
                Line width: 0.6

                if drawTreble = 1
                    if noteY > trebleLine5
                        ldia = trebleLine5 + 2
                        while ldia <= noteY
                            if ldia mod 2 = 0
                                Draw line: noteX - 0.3, ldia, noteX + 0.3, ldia
                            endif
                            ldia += 2
                        endwhile
                    endif
                    if noteY < trebleLine1 and noteY >= middleC
                        ldia = trebleLine1 - 2
                        while ldia >= noteY
                            if ldia mod 2 = 0
                                Draw line: noteX - 0.3, ldia, noteX + 0.3, ldia
                            endif
                            ldia -= 2
                        endwhile
                    endif
                endif

                if drawBass = 1
                    if noteY < bassLine1
                        ldia = bassLine1 - 2
                        while ldia >= noteY
                            if ldia mod 2 = 0
                                Draw line: noteX - 0.3, ldia, noteX + 0.3, ldia
                            endif
                            ldia -= 2
                        endwhile
                    endif
                    if noteY > bassLine5 and noteY <= middleC
                        ldia = bassLine5 + 2
                        while ldia <= noteY
                            if ldia mod 2 = 0
                                Draw line: noteX - 0.3, ldia, noteX + 0.3, ldia
                            endif
                            ldia += 2
                        endwhile
                    endif
                endif

                # Filled notehead
                Paint ellipse: fColour$[fNum], noteX - noteW, noteX + noteW, noteY - noteH, noteY + noteH

                # Hz annotation (original formant frequency)
                Font size: 4
                Colour: {0.6, 0.6, 0.6}
                Text special: noteX + 0.35, "left", noteY, "half", "Helvetica", 4, "0",
                    ... fixed$(segFreq[seg, fNum], 0)

            endif
        endfor
    endfor

    # --- Title ---
    Font size: 8
    Colour: "Black"
    Text special: (xMin + xMax) / 2, "centre", plotMaxDia + 1.5, "bottom", "Helvetica", 8, "0",
        ... "##Formant Chord Player: " + soundName$ + "##"

    # --- Legend ---
    Font size: 6
    legendY       = plotMinDia - 2
    legendStartX  = 1.5
    legendSpacing = 2.2

    Paint circle: fColour$[1], legendStartX, legendY, 0.12
    Colour: {0.3, 0.3, 0.3}
    Text special: legendStartX + 0.25, "left", legendY, "half", "Helvetica", 6, "0", "F1"

    Paint circle: fColour$[2], legendStartX + legendSpacing, legendY, 0.12
    Colour: {0.3, 0.3, 0.3}
    Text special: legendStartX + legendSpacing + 0.25, "left", legendY, "half", "Helvetica", 6, "0", "F2"

    Paint circle: fColour$[3], legendStartX + 2 * legendSpacing, legendY, 0.12
    Colour: {0.3, 0.3, 0.3}
    Text special: legendStartX + 2 * legendSpacing + 0.25, "left", legendY, "half", "Helvetica", 6, "0", "F3"

    Paint circle: fColour$[4], legendStartX + 3 * legendSpacing, legendY, 0.12
    Colour: {0.3, 0.3, 0.3}
    Text special: legendStartX + 3 * legendSpacing + 0.25, "left", legendY, "half", "Helvetica", 6, "0", "F4"

    # --- Summary footer ---
    Font size: 5
    Colour: {0.45, 0.45, 0.45}
    summaryText$ = string$(number_of_segments) + " segs | " +
        ... "note=" + fixed$(note_duration_s, 2) + "s | " +
        ... "harmonics=" + string$(num_harmonics) + " | " +
        ... "stagger=" + fixed$(stagger_s * 1000, 0) + "ms | " +
        ... "A=" + fixed$(attack_s * 1000, 0) +
        ... "ms D=" + fixed$(decay_s * 1000, 0) +
        ... "ms S=" + fixed$(sustain_level, 2) +
        ... " R=" + fixed$(release_s * 1000, 0) + "ms"
    Text special: (xMin + xMax) / 2, "centre", plotMinDia - 3, "half", "Helvetica", 5, "0", summaryText$

    # --- Restore defaults ---
    Font size: 10
    Colour: "Black"
    Line width: 1

endproc
