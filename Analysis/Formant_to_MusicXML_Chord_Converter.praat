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

# ============================================================
# Form
# ============================================================
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

# Pre-scale per voice to prevent clipping of the summed chord.
# Sum of 4 voices, each with 1/k gaussian-tapered partials, can
# peak around 5.0; voiceGain=0.18 keeps the chord comfortably
# under unity even without normalize_output.
voiceGain = 0.18

# ============================================================
# Output file path (prompted AFTER the form)
# ============================================================
xmlPath$        = ""
writeXmlActual  = 0
if write_MusicXML_file
    xmlPath$ = chooseWriteFile$: "Save MusicXML as...", soundName$ + "_formant_chords.xml"
    if xmlPath$ <> ""
        writeXmlActual = 1
    endif
endif

# ============================================================
# Constants
# ============================================================
twoPi = 2 * pi
uid$  = string$(randomInteger(10000, 99999))

# Formant voice colours (shared by spectrogram overlay, staff
# noteheads, and legend).
fColour$[1] = "{0.85, 0.22, 0.12}"
fColour$[2] = "{0.09, 0.37, 0.65}"
fColour$[3] = "{0.06, 0.43, 0.34}"
fColour$[4] = "{0.33, 0.29, 0.72}"

# Register target: synthesised pitch lives in C2 (65 Hz)..C5 (523 Hz).
regLow  = 65
regHigh = 523

# ADSR global timing
adsrFadeT = 0.003

# Guard: if the user's ADSR + stagger timing does not fit inside
# the note duration, the sustain region collapses and decay/release
# overlap (compound envelope bug). Clamp and warn.
maxStagger = (note_duration_s - release_s - attack_s - decay_s - 0.05) / 3
if maxStagger < 0
    exitScript: "ADSR does not fit inside note_duration_s. Increase note duration or shorten A/D/R."
endif
staggerClamped = stagger_s
if staggerClamped > maxStagger
    staggerClamped = maxStagger
endif

# ============================================================
# Procedures
# ============================================================

# Escape XML-reserved characters in a string.
procedure xmlEscape: .s$
    .out$ = replace_regex$(.s$, "&", "&amp;", 0)
    .out$ = replace_regex$(.out$, "<", "&lt;", 0)
    .out$ = replace_regex$(.out$, ">", "&gt;", 0)
    .out$ = replace_regex$(.out$, """", "&quot;", 0)
    .out$ = replace_regex$(.out$, "'", "&apos;", 0)
endproc

# Frequency -> (midi note, fractional alter in eighth-tones).
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

# MIDI -> (note letter, octave, sharp alter 0/1). Uses sharps only.
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
    elsif .pitchClass = 11
        .step$ = "B"
    endif
endproc

# MIDI -> integer diatonic-staff position (for Draw-based notation).
# C4 = 28, E4 = 30, ..., A3 = 26.
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

# Octave-shift a frequency into [regLow, regHigh].
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
# Phase 1 — Extract per-segment formants (time-averaged, robust)
# ============================================================
clearinfo
writeInfoLine: "=== Formant to MusicXML Chord Converter ==="
appendInfoLine: "Source: ", soundName$
appendInfoLine: "[1/5] Extracting formants..."

selectObject: sourceId
totalSourceDur  = Get total duration
segmentDuration = totalSourceDur / number_of_segments

selectObject: sourceId
formantObj = To Formant (burg): time_step, number_of_formants, max_formant_Hz, window_length, 50

# For each segment, use the MEAN formant across the full segment
# (not a single snapshot at midTime), which damps spurious Burg jumps.
for seg from 1 to number_of_segments
    tStart = (seg - 1) * segmentDuration
    tEnd   = seg * segmentDuration
    selectObject: formantObj
    for fNum from 1 to 4
        fHz = Get mean: fNum, tStart, tEnd, "Hertz"
        if fHz <> undefined and fHz > 0
            segFreq[seg, fNum] = fHz
        else
            segFreq[seg, fNum] = 0
        endif
    endfor
endfor

appendInfoLine: "  Done. Segments: ", number_of_segments,
    ... " | Segment length: ", fixed$(segmentDuration, 3), " s"

# Precompute MIDI + alter values used by both the XML emitter
# and the visualisation.
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
# Phase 2 — Write MusicXML file (if requested)
# ============================================================
if writeXmlActual
    appendInfoLine: "[2/5] Writing MusicXML to:"
    appendInfoLine: "  ", xmlPath$

    @xmlEscape: soundName$
    titleEsc$ = xmlEscape.out$

    # Build the whole XML in memory, then write once. Cleaner than
    # dozens of appendFile calls and avoids partial-file failures.
    xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
    xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
    xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$
    xml$ = xml$ + "  <work>" + newline$
    xml$ = xml$ + "    <work-title>Formant Analysis: " + titleEsc$ + "</work-title>" + newline$
    xml$ = xml$ + "  </work>" + newline$
    xml$ = xml$ + "  <identification>" + newline$
    xml$ = xml$ + "    <creator type=""software"">Praat AudioTools — Formant Chord Converter</creator>" + newline$
    xml$ = xml$ + "  </identification>" + newline$
    xml$ = xml$ + "  <part-list>" + newline$
    xml$ = xml$ + "    <score-part id=""P1"">" + newline$
    xml$ = xml$ + "      <part-name>Formant Chords</part-name>" + newline$
    xml$ = xml$ + "    </score-part>" + newline$
    xml$ = xml$ + "  </part-list>" + newline$
    xml$ = xml$ + "  <part id=""P1"">" + newline$

    for seg from 1 to number_of_segments
        xml$ = xml$ + "    <measure number=""" + string$(seg) + """>" + newline$

        if seg = 1
            xml$ = xml$ + "      <attributes>" + newline$
            xml$ = xml$ + "        <divisions>1</divisions>" + newline$
            xml$ = xml$ + "        <key><fifths>0</fifths></key>" + newline$
            xml$ = xml$ + "        <time><beats>4</beats><beat-type>4</beat-type></time>" + newline$
            xml$ = xml$ + "        <clef><sign>G</sign><line>2</line></clef>" + newline$
            xml$ = xml$ + "      </attributes>" + newline$
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
                xml$ = xml$ + "        <pitch>" + newline$
                xml$ = xml$ + "          <step>" + step$ + "</step>" + newline$
                if totalAlter <> 0
                    xml$ = xml$ + "          <alter>" + fixed$(totalAlter, 4) + "</alter>" + newline$
                endif
                xml$ = xml$ + "          <octave>" + string$(octaveOut) + "</octave>" + newline$
                xml$ = xml$ + "        </pitch>" + newline$
                xml$ = xml$ + "        <duration>4</duration>" + newline$
                xml$ = xml$ + "        <type>whole</type>" + newline$
                xml$ = xml$ + "      </note>" + newline$
            endif
        endfor

        if noteIndex = 0
            xml$ = xml$ + "      <note>" + newline$
            xml$ = xml$ + "        <rest/>" + newline$
            xml$ = xml$ + "        <duration>4</duration>" + newline$
            xml$ = xml$ + "        <type>whole</type>" + newline$
            xml$ = xml$ + "      </note>" + newline$
        endif

        xml$ = xml$ + "    </measure>" + newline$
    endfor

    xml$ = xml$ + "  </part>" + newline$
    xml$ = xml$ + "</score-partwise>" + newline$

    writeFile: xmlPath$, xml$
    appendInfoLine: "  MusicXML written (", length(xml$), " bytes)."
else
    appendInfoLine: "[2/5] MusicXML output skipped."
endif

# ============================================================
# Phase 3 — Synthesise one chord per segment
#
# Each voice (F1-F4):
#   1. Register-correct the frequency into C2-C5
#   2. Build a mellow waveform: sum of num_harmonics sine partials
#      with 1/k amplitude and a soft gaussian spectral rolloff;
#      all amplitudes and frequencies are baked in as literals so
#      the Formula string contains no variable names (safe across
#      Praat versions and contexts).
#   3. Apply a piano-like ADSR envelope with per-voice onset stagger.
#      The envelope is implemented as five successive Formula passes
#      over disjoint time regions. Because each pass guards its
#      region with an `else self fi` clause, the phases do NOT
#      compound — inside each region, `self` is still the raw
#      waveform value, and the envelope is applied exactly once.
#   4. Mix into the shared chord buffer.
# ============================================================
appendInfoLine: "[3/5] Synthesising ", number_of_segments, " chords..."

for seg from 1 to number_of_segments

    chordBuf = Create Sound from formula: "chord_" + uid$ + "_" + string$(seg),
        ... 1, 0, note_duration_s, sample_rate_Hz, "0"

    for fNum from 1 to 4
        segF = segFreq[seg, fNum]
        if segF > 0
            pGain = fGain[fNum]

            # Register correction
            @registerCorrect: segF
            playF = registerCorrect.out

            # Onset stagger for this voice (clamped earlier)
            onsetDelay = (fNum - 1) * staggerClamped

            # Build the mellow waveform (literals only inside Formula)
            waveFormula$ = "0"
            for k from 1 to num_harmonics
                kAmp  = voiceGain * (1 / k) * exp(-((k - 1)^2) / 8) * pGain
                kFreq = k * playF
                waveFormula$ = waveFormula$ + " + " +
                    ... fixed$(kAmp, 6) + " * sin(" + fixed$(twoPi * kFreq, 4) + " * x)"
            endfor

            partialSnd = Create Sound from formula: "p_" + uid$,
                ... 1, 0, note_duration_s, sample_rate_Hz, waveFormula$

            # ADSR breakpoints for this voice
            decEnd   = onsetDelay + attack_s + decay_s
            relStart = note_duration_s - release_s

            # Stringify all timing values so the Formula string is
            # self-contained (no reliance on script-variable visibility
            # inside the formula engine).
            od$ = fixed$(onsetDelay, 6)
            at$ = fixed$(attack_s, 6)
            dc$ = fixed$(decay_s, 6)
            de$ = fixed$(decEnd, 6)
            rs$ = fixed$(relStart, 6)
            rl$ = fixed$(release_s, 6)
            sl$ = fixed$(sustain_level, 6)
            nd$ = fixed$(note_duration_s, 6)
            ft$ = fixed$(adsrFadeT, 6)

            # 1. Zero samples before onset
            selectObject: partialSnd
            Formula: "if x < " + od$ + " then 0 else self fi"

            # 2. Attack ramp  (0 -> 1 over attack_s)
            selectObject: partialSnd
            Formula: "if x >= " + od$ + " and x < " + od$ + " + " + at$
                ... + " then self * ((x - " + od$ + ") / " + at$ + ") else self fi"

            # 3. Decay (1 -> sustain_level over decay_s)
            selectObject: partialSnd
            Formula: "if x >= " + od$ + " + " + at$ + " and x < " + de$
                ... + " then self * (1 - (1 - " + sl$ + ") * ((x - " + od$ + " - " + at$ + ") / " + dc$ + ")) else self fi"

            # 4. Sustain
            selectObject: partialSnd
            Formula: "if x >= " + de$ + " and x < " + rs$
                ... + " then self * " + sl$ + " else self fi"

            # 5. Release (sustain_level -> 0)
            selectObject: partialSnd
            Formula: "if x >= " + rs$
                ... + " then self * " + sl$ + " * ((" + nd$ + " - x) / " + rl$ + ") else self fi"

            # Final tiny fade at the very end (anti-click)
            selectObject: partialSnd
            Formula: "if x > " + nd$ + " - " + ft$
                ... + " then self * ((" + nd$ + " - x) / " + ft$ + ") else self fi"

            # Mix into chord buffer (column index; matches Praat Formula conventions)
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
# Phase 4 — Concatenate chords
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
    Scale peak: 0.95
endif

# ============================================================
# Phase 5 — Visualization
# Shows the *phenomenon*: source spectrogram with F1-F4 tracks
# overlaid, above the notation staff that carries the same
# colour coding. Footer reports ADSR/synth parameters.
# ============================================================
if draw_visualization
    appendInfoLine: "[5/5] Drawing visualization..."

    # ---- Collect diatonic positions for the staff panel ----
    globalMinDia =  999
    globalMaxDia = -999
    for seg from 1 to number_of_segments
        for fNum from 1 to 4
            if segFreq[seg, fNum] > 0
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

    # Staff diatonic lines (C4 = 28)
    trebleLine1 = 30
    trebleLine5 = 38
    bassLine1   = 18
    bassLine5   = 26
    middleC     = 28

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

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ---- Title ----
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Formant-to-MusicXML Chord Converter##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.20, "half",
        ... soundName$
        ... + "   |   segments=" + string$(number_of_segments)
        ... + "   |   note=" + fixed$(note_duration_s, 2) + "s"
        ... + "   |   transpose=" + string$(transpose_semitones) + " st"

    # ---- Source spectrogram with F1-F4 overlay ----
    Select outer viewport: 0, 8, 0.55, 2.55
    Select inner viewport: 0.6, 7.7, 0.60, 2.50

    selectObject: sourceId
    nChSrc = Get number of channels
    if nChSrc > 1
        Extract one channel: 1
        tmpMono = selected("Sound")
    else
        Copy: "tmpMono_fmt"
        tmpMono = selected("Sound")
    endif
    specMaxHz = max_formant_Hz
    To Spectrogram: 0.03, specMaxHz, 0.002, 20, "Gaussian"
    specObj = selected("Spectrogram")
    Paint: 0, 0, 0, specMaxHz, 100, "yes", 50, 6, 0, "no"

    # Overlay formant tracks from the existing Formant object.
    # Axes are (time, Hz) after Paint, so Draw line works in that space.
    Axes: 0, totalSourceDur, 0, specMaxHz
    selectObject: formantObj
    nFrames = Get number of frames
    Line width: 1.5
    for fNum from 1 to 4
        Colour: fColour$[fNum]
        havePrev = 0
        prevT = 0
        prevHz = 0
        for frame from 1 to nFrames
            selectObject: formantObj
            tFrame = Get time from frame number: frame
            hz = Get value at time: fNum, tFrame, "Hertz", "Linear"
            if hz <> undefined and hz > 0 and hz <= specMaxHz
                if havePrev = 1
                    Draw line: prevT, prevHz, tFrame, hz
                endif
                prevT = tFrame
                prevHz = hz
                havePrev = 1
            else
                havePrev = 0
            endif
        endfor
    endfor

    # Segment boundary ticks (thin vertical lines)
    Line width: 0.6
    Colour: "{0.4, 0.4, 0.4}"
    for seg from 0 to number_of_segments
        segT = seg * segmentDuration
        if segT <= totalSourceDur
            Draw line: segT, 0, segT, specMaxHz
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Source spectrogram with F1-F4 tracks (per-segment means drive the chord)"

    removeObject: specObj, tmpMono

    # ---- Notation staff ----
    staffTop    = 2.65
    staffBottom = 6.50
    Select outer viewport: 0, 8, staffTop, staffBottom
    Select inner viewport: 0.6, 7.7, staffTop + 0.10, staffBottom - 0.05

    xMin = 0
    xMax = number_of_segments + 1.5
    Axes: xMin, xMax, plotMinDia - 1, plotMaxDia + 1

    staffLeft  = 0.8
    staffRight = number_of_segments + 0.8

    # Staff lines
    Colour: {0.45, 0.45, 0.45}
    Line width: 1
    if drawTreble = 1
        for li from 1 to 5
            yLine = trebleLine1 + (li - 1) * 2
            Draw line: staffLeft, yLine, staffRight, yLine
        endfor
    endif
    if drawBass = 1
        for li from 1 to 5
            yLine = bassLine1 + (li - 1) * 2
            Draw line: staffLeft, yLine, staffRight, yLine
        endfor
    endif

    # Barlines
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

    # Clef labels
    Font size: 7
    Colour: {0.3, 0.3, 0.3}
    if drawTreble = 1
        Text special: 0.4, "centre", trebleLine1 + 4, "half", "Helvetica", 7, "0", "T"
    endif
    if drawBass = 1
        Text special: 0.4, "centre", bassLine1 + 4, "half", "Helvetica", 7, "0", "B"
    endif

    # Segment numbers
    Font size: 6
    Colour: {0.5, 0.5, 0.5}
    for seg from 1 to number_of_segments
        noteX = seg + 0.3
        Text special: noteX, "centre", plotMinDia - 0.5, "top", "Helvetica", 6, "0", string$(seg)
    endfor

    # Noteheads + ledger lines + Hz annotation
    noteW = 0.25
    noteH = 0.7
    for seg from 1 to number_of_segments
        noteX = seg + 0.3
        for fNum from 1 to 4
            if segMidi[seg, fNum] > 0
                noteY = segDia[seg, fNum]

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

                Paint ellipse: fColour$[fNum], noteX - noteW, noteX + noteW, noteY - noteH, noteY + noteH

                Font size: 4
                Colour: {0.6, 0.6, 0.6}
                Text special: noteX + 0.35, "left", noteY, "half", "Helvetica", 4, "0",
                    ... fixed$(segFreq[seg, fNum], 0)
            endif
        endfor
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Chord score (noteheads coloured by formant: red=F1 blue=F2 green=F3 purple=F4)"

    # Legend (inside the staff panel, bottom edge)
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

    # ---- Summary panel ----
    Select outer viewport: 0, 8, 6.60, 7.75
    Select inner viewport: 0.6, 7.7, 6.65, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.66, "half",
        ... "Source: " + soundName$
        ... + "  |  duration=" + fixed$(totalSourceDur, 2) + "s"
        ... + "  |  segment=" + fixed$(segmentDuration, 3) + "s"
        ... + "  |  max formant=" + string$(max_formant_Hz) + " Hz"
    Text: 0.02, "left", 0.44, "half",
        ... "Note=" + fixed$(note_duration_s, 2) + "s"
        ... + "  |  A=" + fixed$(attack_s * 1000, 0)
        ... + "ms D=" + fixed$(decay_s * 1000, 0)
        ... + "ms S=" + fixed$(sustain_level, 2)
        ... + " R=" + fixed$(release_s * 1000, 0) + "ms"
        ... + "  |  harmonics=" + string$(num_harmonics)
        ... + "  |  stagger=" + fixed$(staggerClamped * 1000, 0) + "ms"
    xmlStatus$ = "skipped"
    if writeXmlActual
        xmlStatus$ = "written"
    endif
    Text: 0.02, "left", 0.22, "half",
        ... "Register fold: " + string$(regLow) + "-" + string$(regHigh) + " Hz"
        ... + "  |  8th-tone alter"
        ... + "  |  MusicXML: " + xmlStatus$
        ... + "  |  normalize=" + string$(normalize_output)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# Cleanup + play
# ============================================================
removeObject: formantObj
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
appendInfoLine: "Output Sound: ", selected$("Sound")
appendInfoLine: "Total duration: ", fixed$(note_duration_s * number_of_segments, 2), " s"
if writeXmlActual
    appendInfoLine: "MusicXML file: ", xmlPath$
endif

if play_result
    Play
endif
