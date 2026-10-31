# ============================================================
# Praat AudioTools - Stockhausen_Studie_II_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Generator after Karlheinz Stockhausen's Studie II (1954).
#   Random mode: a creative quasi-Studie II generator.
#   Serial mode: a serial RECONSTRUCTION of the whole piece (5 parts + coda,
#   380 mixtures) from the input series 3 5 1 4 2, following the procedures
#   documented by Silberhorn (1980) and re-programmed by Heintz (2010). It is
#   a regeneration of the method, not a transcription of the published score.
#   Core materials:
#   - 81-tone scale 100 Hz * 5^(n/25), n = 0..80
#   - 61 tape durations 2.5 cm * 5^(n/25), 61 intensities 0..-30..0 dB
#   - ten 5x5 number squares R1-R5, U1-U5 derived from 3 5 1 4 2
#   - five-sine Tongemische with interval class (column) 1..5
#   - two-system score visualization informed by the published score:
#       upper system = 81-line tone-mixture field
#       centre strip = tape ruler (cm of the 1954 tape, s of the output)
#       lower system = dB envelopes
#
# Changelog v0.9 (Serial mode rebuilt):
#   SOURCES: Heintz, "Re-Generating Stockhausen's Studie II in Csound"
#   (LAC 2010), and the serial logic of his Csound regeneration shipped with
#   CsoundQt (Examples > Music), itself based on Silberhorn, Die Reihentechnik
#   in Stockhausens Studie II (1980). Algorithms re-implemented in Praat.
#   - DOCUMENTED, now implemented:
#     * R1 by interval-preserving transposition of 3 5 1 4 2 onto each of its
#       own values (rows 3-5-1-4-2 / 5-2-3-1-4 / ...). The old cyclic square
#       was wrong.
#     * R2-R5 by Stockhausen's "hop" procedure: the new top line is a line
#       of R1, the line starts are read from it with step 2..5, and each
#       line follows R1's own line-to-head distance pattern.
#     * U1-U5 as inversions (6 - n) of R1-R5.
#     * Frequency selection by four independent streams: abstract group (A),
#       transposition (B), column = interval class (C), position (D).
#       Degree = 5(A+B-2) + C(D-1); the mixture adds 4 more tones C degrees
#       apart. The five fixed pitch registers of v0.8 are gone.
#     * Hierarchical repetition: a superior square S gives the number of
#       sounds per sequence (1-5); A and C hold for a sequence, D advances
#       every sound, B is constant for a part (I = 3, II = 5) and becomes a
#       per-sequence series from Part III on. Each parameter (frequency,
#       duration, intensity, starts) has its OWN assignment of squares and
#       its own transposition, so the streams run at different rates.
#     * 61-value geometric duration pool, longest first, read by the same
#       group/transposition/column/position mechanism.
#     * Starting times from an independent GHOST-DURATION series: durations
#       read as succeeding each other, their sums captured as start points
#       (per sequence in I, II, IV; per sound in III and V).
#     * Part I linked sequences; Parts II and IV chords with common start
#       (durations accumulated forward) or common end (accumulated
#       backward); Part III isolated events with mobile transposition;
#       Part V mixing linked, chord and isolated sequences; five-event coda
#       read directly from 3 5 1 4 2.
#     * Linear-in-dB envelopes between -40 dB and the series intensity, as
#       in the realisation (crescendo / diminuendo / joined diminuendi).
#   - TRANSCRIBED FROM THE SCORE (no serial origin found by Heintz in the
#     sketches): the envelope series of Parts I, II, IV, V and the Part V
#     sequence-type table. Used as data, flagged in the Info window.
#   - SCORE CORRECTIONS (Part V): Heintz's replacement of the group by 2 in
#     certain sequences, column 3 in the last sequence, and 38 corrected dB
#     values. On by default; "Apply score corrections (Part V)" off gives the
#     plain serial derivation. The event count is 380 either way.
#   - ARCHITECTURE: the whole piece (5 parts + coda, 380 mixtures) is
#     always generated first as an event table in tape centimetres.
#   - TIMING: playback is ALWAYS at the historical 76.2 cm/s (~175 s for the
#     piece); the structure is never time-compressed, since a uniform
#     speed-up sounds like fast-forward. Duration is a WINDOW cut from the
#     piece: "Start at (Serial)" in Edit details picks Part I-V or Coda as
#     its start, and Duration sets its length. Sounds of the previous part
#     still ringing at the window start are kept, rendered from mid-sound;
#     sounds cut by either window edge get a 5 ms fade. A window running
#     past the end is shortened, and the Info window says so.
#     "Whole piece (Serial)" ignores Duration and renders everything.
#   - SOUND PRODUCTION after the score (p. VII, as reported by Williams
#     2016): each Tongemisch is a tape LOOP of the five sines, 4 cm each
#     (52.5 ms), spliced lowest to highest with 45-degree splices (8.3 ms
#     crossfades), played into a reverberation chamber of about 10 s and
#     recorded WET ONLY; the fader then shapes it in dB down to -40 dB, and
#     rising sounds are the tape played backwards. The loop's steady state
#     through the room is periodic, so one period is computed exactly by
#     circular convolution with the room response folded onto the loop.
#     The room is synthetic (no WDR impulse response survives): decaying
#     noise, RT60 10 s below 1 kHz, 8 s to 4 kHz, 5 s above (damping is an
#     assumption; the score asks for "regular frequency response").
#     RANDOM MODE now uses the same chamber process for its mixtures
#     (its random structure and envelopes are unchanged; envelope 2, the
#     rising ramp, is the reverberated tape reversed). The post-mix echo
#     taps and the "Wet-only reverb model" option are removed from both
#     modes: they were never part of the 1954 process. Random output
#     therefore differs from v0.8 by design.
#   - Rendering writes each mixture straight into its own time window
#     (Formula (part)), so the whole piece renders in about 11 s.
#   - "Serial rotation offset" now rotates the input series (0 = historical).
#   - Score: tape ruler reads absolute 1954 tape cm for any window; lower
#     system plots the actual dB ramps; a Coda marker is added.
#
# Changelog v0.8:
#   SOURCES CHECKED against Toop 2005 (in Six Lectures from the Stockhausen
#   Courses Kürten 2002), Stockhausen Texte 2, and the score preface as
#   reported by Llorente and Krzyzaniak.
#   - CONFIRMED CORRECT: the 81-degree scale on 5^(1/25) from 100 Hz to
#     ~17.2 kHz; the 5 sections x 5 subsections x 5 groups x 1-5 sounds
#     hierarchy; mixture width held constant within a group and changing
#     from group to group; five-sine mixtures spaced by 1-5 SCALE DEGREES,
#     i.e. geometric in Hz. Some secondary sources describe the mixtures as
#     equally spaced in Hz; that reading is inconsistent with a scale whose
#     step is a fixed ratio, and the arithmetic examples they give are
#     rounded oscillator settings. v0.7's correction to geometric was right.
#   - CORRECTED: the five partials of a mixture were weighted 1.00 / 0.88 /
#     0.76 by distance from the centre. Stockhausen specifies that the five
#     frequencies are recorded at equal level, so equal levels are now the
#     default (Equal partial levels, in Edit details). This changes the sound
#     slightly: mixtures are brighter at their extremes.
#   - FLAGGED, NOT CHANGED: the historical realisation used the reverberation
#     chamber's WET signal only, the direct sound being physically cut from
#     the tape head. Wet-only reverb is still off by default here.
#   - Score redrawn. Colour is not in the original and is used for exactly one
#     purpose: the five Tongemisch widths I-V, the parameter Stockhausen
#     serialised and the one hardest to read in monochrome, since width shows
#     only as box height on a log axis. Grid, boxes and lettering stay black.
#   - Upper system now bands the five sections and marks them with numerals;
#     the five-part form was previously invisible.
#   - The tape strip, formerly an uninformative picket fence, is now a real
#     dual ruler: centimetres of tape above, seconds below.
#   - Lower system now draws ONE envelope per mixture in dB, coloured by width
#     class. The previous single overlaid curve merged simultaneous mixtures
#     into one unreadable line.
#   - Added a fidelity strip separating what comes from the sources from what
#     is a modelling choice. The largest remaining divergence is that mixtures
#     are built on five fixed pitch registers rather than the historical
#     series of starting degrees; the new figure makes that visible as five
#     horizontal bands.
#
# Changelog v0.7:
#   - HISTORICAL CORRECTION: serial Tongemische again use equally spaced
#     scale indices (geometric spacing in Hz), not equal-Hz spacing.
#   - Score redesigned as a historically informed two-system monochrome layout,
#     preserving the 81 frequency lines and a separate articulation/amplitude
#     system rather than a generic modern data plot.
#   - Added tape-material time reference: 76.2 cm/s and 2.5 cm base unit.
#   - Compact main form; engineering/model controls moved to Edit details.
#   - Added random seed, output peak, validation, final peak/RMS QC.
#   - Fixed the exponential envelope so it closes smoothly at the event end.
#   - Score text strips use explicit viewports to avoid collisions.
# ============================================================

form Studie II Generator v0.9
    optionmenu Generation_mode 1
        option Random (creative, varied)
        option Serial (Studie II reconstruction)
    positive Duration_s 10.0

    boolean Edit_details 0
    boolean Draw_score 1
    boolean Play_result 1
endform

# === Advanced defaults ===
sample_rate_Hz = 44100
base_frequency_Hz = 100
min_amplitude = 0.10
max_amplitude = 0.30
random_groups = 7
rotation_offset = 0
equal_partial_levels = 1
output_peak = 0.95
random_seed = 0
whole_piece = 0
start_at = 1
apply_score_corrections = 1

if edit_details
    beginPause: "Studie II v0.9 - Model / Audio Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        positive: "Base frequency (Hz)", base_frequency_Hz
        positive: "Minimum event amplitude", min_amplitude
        positive: "Maximum event amplitude", max_amplitude
        integer: "Random-mode groups", random_groups
        integer: "Serial rotation offset", rotation_offset
        optionmenu: "Start at (Serial)", start_at
            option: "Part I"
            option: "Part II"
            option: "Part III"
            option: "Part IV"
            option: "Part V"
            option: "Coda"
        boolean: "Whole piece (Serial)", whole_piece
        boolean: "Apply score corrections (Part V)", apply_score_corrections
        boolean: "Equal partial levels (historical)", equal_partial_levels
        positive: "Output peak", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# === Validation ===
if duration_s < 0.20
    exitScript: "Duration must be at least 0.20 s."
endif
if sample_rate_Hz < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be positive."
endif
if min_amplitude <= 0 or max_amplitude <= 0 or min_amplitude > max_amplitude
    exitScript: "Amplitude range must be positive and Min <= Max."
endif
if random_groups < 1
    exitScript: "Random-mode groups must be at least 1."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in (0, 1]."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

if random_seed = 0
    random_initializeSafelyAndUnpredictably()
else
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

num_groups = random_groups

# === Constants ===

uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
scaleRatio = 5 ^ (1 / 25)
tapeSpeed_cm_s = 76.2
baseTapeUnit_cm = 2.5
baseTimeUnit = baseTapeUnit_cm / tapeSpeed_cm_s

# === Build idealized 81-tone frequency scale ===
# Adjacent scale degrees have the constant ratio 5^(1/25).
for i to 81
    freq[i] = base_frequency_Hz * (scaleRatio ^ (i - 1))
endfor

nyquist_Hz = sample_rate_Hz / 2
safeNyquist_Hz = 0.95 * nyquist_Hz
if freq[81] >= safeNyquist_Hz
    exitScript: "The 81-tone scale reaches " + fixed$(freq[81], 1) + " Hz, above the safe Nyquist limit " + fixed$(safeNyquist_Hz, 1) + " Hz. Lower Base frequency or raise Sample rate."
endif

# === Info ===
writeInfoLine: "=== Stockhausen Studie II Generator ==="
if generation_mode = 1
    appendInfoLine: "Mode: Random (quasi-Studie II)"
else
    appendInfoLine: "Mode: Serial (reconstruction of the method after Silberhorn/Heintz; not a transcription)"
endif
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Frequency range: ", fixed$(freq[1], 1), " - ", fixed$(freq[81], 1), " Hz"
appendInfoLine: "Scale ratio: 5^(1/25) = ", fixed$(scaleRatio, 6)
appendInfoLine: "Tape reference: ", fixed$(tapeSpeed_cm_s, 1), " cm/s | base unit ", fixed$(baseTapeUnit_cm, 1), " cm = ", fixed$(baseTimeUnit * 1000, 2), " ms"
appendInfoLine: ""

# === Serial Mode Setup: material pools and number squares ===
winStart = 0
startName$[1] = "Part I"
startName$[2] = "Part II"
startName$[3] = "Part III"
startName$[4] = "Part IV"
startName$[5] = "Part V"
startName$[6] = "Coda"
if generation_mode = 2
    # Input series. Rotation 0 is Stockhausen's 3 5 1 4 2; any other value
    # rotates it and leaves the historical derivation behind.
    histRow[1] = 3
    histRow[2] = 5
    histRow[3] = 1
    histRow[4] = 4
    histRow[5] = 2
    rotN = abs(rotation_offset) mod 5
    for i to 5
        inRow[i] = histRow[((i - 1 + rotN) mod 5) + 1]
    endfor

    # 61 durations in cm, 2.5 * 5^(n/25), stored LONGEST FIRST as in the
    # sketches, so a low table index is a long sound.
    for i to 61
        durCm[i] = baseTapeUnit_cm * (scaleRatio ^ (61 - i))
    endfor
    # 61 intensities: 0 down to -30 dB in 1 dB steps, then mirrored back.
    for i to 61
        if i <= 31
            dbTab[i] = 1 - i
        else
            dbTab[i] = i - 61
        endif
    endfor

    @buildSquares
endif

# === Create Temporary Master Sound (will be recreated after timing adjustment) ===
master = Create Sound from formula: "master_temp_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Event Storage ===
numEvents = 0
maxStoredEvents = 500
sectionNum = 0
subsectionNum = 0
groupNum = 0

# Pre-allocate arrays
for i to maxStoredEvents
    evStart[i] = 0
    evEnd[i] = 0
    evDur[i] = 0
    evAmp[i] = 0
    evEnv[i] = 0
    evWidth[i] = 0
    evSection[i] = 0
    evSub[i] = 0
    evGroup[i] = 0
    evRegister[i] = 0
    evNote[i] = 0
    evKind[i] = 0
    evDb1[i] = -40
    evDb2[i] = -40
    for c to 5
        evFreq[i, c] = 0
    endfor
endfor

# === Main Generation ===
appendInfoLine: "Generating..."

currentTime = 0

if generation_mode = 1
    # ========================================
    # RANDOM MODE
    # ========================================
    
    for iGroup to num_groups
        if currentTime >= duration_s - 0.05
            goto doneGeneration
        endif
        
        groupType = randomInteger(0, 1)
        numMixtures = randomInteger(1, 5)
        
        if groupType = 0
            # Horizontal: sequential events
            for iMix to numMixtures
                if currentTime >= duration_s - 0.05
                    goto doneGeneration
                endif
                
                spreadFactor = randomInteger(1, 5)
                startIdx = randomInteger(10, 65 - 4 * spreadFactor)
                evDuration = randomUniform(0.08, 0.45)
                
                if currentTime + evDuration > duration_s
                    evDuration = duration_s - currentTime
                endif
                
                evAmplitude = randomUniform(min_amplitude, max_amplitude)
                envType = randomInteger(1, 5)
                
                @storeEvent: currentTime, evDuration, startIdx, spreadFactor, evAmplitude, envType
                
                currentTime = currentTime + evDuration + randomUniform(0.005, 0.06)
            endfor
            
            if randomUniform(0, 1) > 0.4
                currentTime = currentTime + randomUniform(0.03, 0.25)
            endif
        else
            # Vertical: overlapping events
            groupStart = currentTime
            groupLen = randomUniform(0.25, 0.7)
            
            for iMix to numMixtures
                if groupStart >= duration_s - 0.05
                    goto skipVertical
                endif
                
                spreadFactor = randomInteger(1, 5)
                startIdx = randomInteger(10, 65 - 4 * spreadFactor)
                evDuration = randomUniform(groupLen * 0.6, groupLen * 1.3)
                evStart = groupStart + randomUniform(0, groupLen * 0.25)
                
                if evStart + evDuration > duration_s
                    evDuration = duration_s - evStart
                endif
                
                if evDuration >= 0.03
                    evAmplitude = randomUniform(min_amplitude, max_amplitude)
                    envType = randomInteger(1, 5)
                    @storeEvent: evStart, evDuration, startIdx, spreadFactor, evAmplitude, envType
                endif
            endfor
            
            label skipVertical
            currentTime = groupStart + groupLen + randomUniform(0.01, 0.12)
        endif
        
        appendInfoLine: "  Group ", iGroup, "/", num_groups
    endfor

else
    # ========================================
    # SERIAL MODE (Studie II reconstruction)
    # ========================================
    # The whole piece is built first, in centimetres of 1954 tape, and only
    # then mapped to the output duration (see "MAP THE COMPLETE STRUCTURE").
    #
    # Terminology after Silberhorn/Heintz: 1-5 SOUNDS form a SEQUENCE, 5
    # sequences a SET, 5 sets a PART; 5 parts + coda = 380 sounds.
    #
    # Squares: 1-5 = R1-R5, 6-10 = U1-U5. For every parameter of every part:
    #   counts square S  -> sounds per sequence (the "superior" series)
    #   group square A   -> one value per sequence (repeated S times)
    #   transposition B  -> constant per part (I, II) or one square value per
    #                       sequence (III, IV, V: the mobile transposition)
    #   column square C  -> one value per sequence = mixture interval class
    #   positions D      -> three squares end to end, one value per sound
    # Table index (0-based) = 5 (A + B - 2) + C (D - 1).

    appendInfoLine: ""
    appendInfoLine: "Number squares (R = derived from the series, U = inversion):"
    for zq to 10
        if zq <= 5
            zName$ = "R" + string$(zq)
        else
            zName$ = "U" + string$(zq - 5)
        endif
        zLine$ = "  " + zName$ + ":"
        for zr to 5
            zLine$ = zLine$ + "  "
            for zi to 5
                zLine$ = zLine$ + string$(sq[zq, (zr - 1) * 5 + zi])
            endfor
        endfor
        appendInfoLine: zLine$
    endfor
    appendInfoLine: ""

    # ---------------------------------------------------------- PART I
    # Linked horizontal sequences: one ghost start per sequence, the sounds
    # inside a sequence follow each other without gaps. B = 3 throughout.
    sectionNum = 1
    @parseList: "2 1 1 2 2 1 2 2 2 1 2 2 2 1 2 2 1 1 2 2 2 1 2 1 2 2 1 2 1 2 1 2 1 2 2 1 2 2 2 2 1 2 2 2 1 2 2 2 2 1 2 2 1 2 2 1 2 2 1 2 1 2 2 2 1 2 1 2 2 2 1 2 1 2 2"
    for zn to 75
        wE[zn] = listV[zn]
    endfor
    @setStel: 1, 2, 3
    @meth1: 5, 1, 3, 2
    @copyFreq
    @setStel: 3, 4, 5
    @meth1: 5, 3, 1, 4
    @copyDur
    @setStel: 2, 3, 4
    @meth1: 5, 2, 5, 3
    @copyDb
    @setStel: 4, 5, 1
    @seqStarts: 5, 4, 1, 10, 0
    zn = 0
    for zk to 25
        zc = sq[5, zk]
        zt = seqSt[zk]
        for zj to zc
            zn = zn + 1
            if wE[zn] = 1
                # crescendo, always from -40 dB
                za = -40
                zb = wB[zn]
            else
                if zj = zc
                    zNextDb = 0
                    zNextEnv = 1
                else
                    zNextDb = wB[zn + 1]
                    zNextEnv = wE[zn + 1]
                endif
                if zj = zc or zNextEnv = 1 or zNextDb > wB[zn]
                    za = wB[zn]
                    zb = -40
                else
                    # diminuendo joined to the next, softer diminuendo
                    za = wB[zn]
                    zb = zNextDb
                endif
            endif
            @addSerial: 1, zk, zj, zt, wD[zn], wF[zn], wC[zn], za, zb, 1
            zt = zt + wD[zn]
        endfor
    endfor
    zPartEnd = seqSt[26]

    # ---------------------------------------------------------- PART II
    # Vertical: each sequence is a chord with a common start (durations
    # accumulated forward) or a common end (accumulated backward). B = 5.
    sectionNum = 2
    @parseList: "1 2 4 3 5 1 4 3 5 2 1 4 5 2 3 4 3 1 5 2 3 1 4 5 2"
    for zk to 25
        cEnv[zk] = listV[zk]
        seqCS[zk] = (cEnv[zk] = 1 or cEnv[zk] = 2)
        @shapeOf: 2, cEnv[zk]
        cShape[zk] = shapeOf.shape
    endfor
    @setStel: 4, 5, 1
    @meth1: 1, 2, 5, 3
    @copyFreq
    @setStel: 1, 2, 3
    @meth1: 1, 4, 3, 5
    @copyDur
    @chordDurs: 1
    @setStel: 5, 1, 2
    @meth1: 1, 3, 2, 4
    @copyDb
    @setStel: 2, 3, 4
    @seqStarts: 1, 5, 3, 6, zPartEnd
    @emitChords: 2, 1
    zPartEnd = seqSt[26]

    # ---------------------------------------------------------- PART III
    # Isolated events, one ghost start per SOUND. Frequency and intensity
    # switch to the second method: group = position, transposition mobile.
    sectionNum = 3
    @setStel: 2, 3, 4
    @meth2: 2, 3, 4
    @copyFreq
    @setStel: 4, 5, 1
    @meth1: 2, 5, 4, 1
    @copyDur
    @setStel: 4, 5, 1
    @meth2: 2, 4, 5
    @copyDb
    @setStel: 5, 1, 2
    @meth1: 2, 1, 4, 7
    zt = zPartEnd
    zn = 0
    for zk to 25
        zc = sq[2, zk]
        for zj to zc
            zn = zn + 1
            @addSerial: 3, zk, zj, zt, wD[zn], wF[zn], wC[zn], wB[zn], -40, 4
            zt = zt + durCm[mDeg[zn] + 1]
        endfor
    endfor
    zPartEnd = zt

    # ---------------------------------------------------------- PART IV
    # Chords again, now with the mobile transposition of Part III.
    # Intensity: only the first-sounding member of a chord takes its table
    # value; each further member is that value minus its position (dB).
    sectionNum = 4
    @parseList: "2 5 4 3 1 2 1 5 4 3 2 3 1 4 5 2 5 1 3 4 2 3 5 1 4"
    for zk to 25
        cEnv[zk] = listV[zk]
        seqCS[zk] = (cEnv[zk] = 1 or cEnv[zk] = 2 or cEnv[zk] = 5)
        @shapeOf: 4, cEnv[zk]
        cShape[zk] = shapeOf.shape
    endfor
    @setStel: 5, 1, 2
    @meth2: 3, 4, 5
    @copyFreq
    @setStel: 2, 3, 4
    @meth1: 3, 1, 2, 2
    @copyDur
    @chordDurs: 3
    @setStel: 1, 2, 3
    zn = 0
    for zk to 25
        zc = sq[3, zk]
        for zm to zc
            if seqCS[zk]
                zi = zn + zm
            else
                zi = zn + zc - zm + 1
            endif
            zp = stel[zi]
            if zm = 1
                zRef = dbTab[5 * (sq[5, zk] - 1) + sq[1, zk] * (zp - 1) + 1]
            else
                zRef = zRef - zp
            endif
            wB[zi] = zRef
        endfor
        zn = zn + zc
    endfor
    @setStel: 3, 4, 5
    @seqStarts: 3, 2, 2, 8, zPartEnd
    @emitChords: 4, 3
    zPartEnd = seqSt[26]

    # ---------------------------------------------------------- PART V
    # Mixture of the three behaviours, one type per sequence:
    # 1 = linked (as I), 2 = chord (as II/IV), 3 = isolated (as III).
    sectionNum = 5
    @parseList: "3 1 2 1 2 2 3 2 1 1 2 3 1 2 1 2 2 3 1 1 2 2 1 1 3"
    for zk to 25
        cType[zk] = listV[zk]
    endfor
    # envelopes of the linked sounds (1 = cresc, 2 = dim), one per sound
    @parseList: "2 1 2 2 1 2 2 2 1 2 2 1 2 1 1 2 1 2 2 1 2 1 2 2 2 2 2 2 1 2"
    for zi to 30
        env5a[zi] = listV[zi]
    endfor
    # envelopes of the ten chords (1-6), one per chord sequence
    @parseList: "5 6 3 2 1 4 2 3 2 3"
    for zi to 10
        env5b[zi] = listV[zi]
    endfor
    @parseList: "1 4 2 5 3"
    for zi to 5
        rplA[zi] = listV[zi]
    endfor
    @parseList: "2 2 5 3 5"
    for zi to 5
        rplB[zi] = listV[zi]
    endfor

    # Frequencies: second method (transposition R5, column R1), with the
    # documented score deviations when corrections are on.
    @setStel: 3, 4, 5
    zn = 0
    for zg to 5
        for zs to 5
            zk = (zg - 1) * 5 + zs
            zCol = sq[1, zk]
            if apply_score_corrections and zg = 5 and zs = 5
                zCol = 3
            endif
            for zj to sq[4, zk]
                zn = zn + 1
                zp = stel[zn]
                zGrp = zp
                if apply_score_corrections and (zs = rplA[zg] or zs = rplB[zg])
                    zGrp = 2
                endif
                wF[zn] = 5 * (zGrp + sq[5, zk] - 2) + zCol * (zp - 1)
                wC[zn] = zCol
            endfor
        endfor
    endfor
    # Durations, with chord accumulation in the chord sequences only.
    @setStel: 5, 1, 2
    @meth2: 4, 2, 3
    @copyDur
    zc2 = 0
    for zk to 25
        if cType[zk] = 2
            zc2 = zc2 + 1
            zEnv = env5b[zc2]
            seqCS[zk] = (zEnv = 1 or zEnv = 2 or zEnv = 5)
            @shapeOf: 5, zEnv
            cShape[zk] = shapeOf.shape
        else
            seqCS[zk] = -1
            cShape[zk] = 0
        endif
    endfor
    @chordDurs: 4
    # Ghost starts, one per sound (transposition R3, column U4).
    @setStel: 1, 2, 3
    @meth2: 4, 3, 9
    for zn to 75
        wG[zn] = durCm[mDeg[zn] + 1]
    endfor
    # Intensities (transposition R1, column R2) and the dB corrections.
    @setStel: 4, 5, 1
    @meth2: 4, 1, 2
    @copyDb
    if apply_score_corrections
        @parseList: "0 -22 1 -18 2 -17 3 -15 6 -18 7 -26 8 -27 9 -30 10 -29 11 -28 12 -21 13 -18 19 -30 21 -22 22 -29 23 -18 25 -4 31 -12 32 -13 33 -17 34 -4 36 -21 38 -10 39 -30 40 -29 41 -27 46 -23 47 -15 48 -24 50 -13 53 -21 54 -9 55 -21 56 -13 59 -7 61 -14 62 -11 63 -7 64 -5 66 -11 67 -13 68 -18 69 -21 70 -29 71 -23 73 -19"
        for zi to listN / 2
            wB[listV[2 * zi - 1] + 1] = listV[2 * zi]
        endfor
    endif
    # Start times: type 1 joins sounds to the end of the previous one,
    # type 2 builds the chord on the sequence start, type 3 and the first
    # sound of type 1 take the running ghost time.
    zAbs = zPartEnd
    wS[1] = zAbs
    zn = 0
    zc2 = 0
    for zk to 25
        zc = sq[4, zk]
        zSeq = zAbs
        zShift = 0
        zMax = 0
        for zj to zc
            zMax = max(zMax, wD[zn + zj])
        endfor
        if cType[zk] = 2
            zc2 = zc2 + 1
        endif
        for zj to zc
            zn = zn + 1
            zAbs = zAbs + wG[zn]
            if cType[zk] = 1 and zj < zc
                zShift = zShift + wD[zn]
                wS[zn + 1] = zSeq + zShift
            elsif cType[zk] = 2
                if seqCS[zk] and zj < zc
                    wS[zn] = zSeq
                else
                    wS[zn] = zSeq + zMax - wD[zn]
                endif
                wS[zn + 1] = zAbs
            else
                wS[zn + 1] = zAbs
            endif
        endfor
    endfor
    zCodaStart = wS[76]
    # Envelopes and emission.
    zn = 0
    zi1 = 0
    zc2 = 0
    for zk to 25
        zc = sq[4, zk]
        zMax = 0
        for zj to zc
            zMax = max(zMax, wD[zn + zj])
        endfor
        if cType[zk] = 2
            zc2 = zc2 + 1
        endif
        zLink = 0
        for zj to zc
            zn = zn + 1
            zdb = wB[zn]
            if cType[zk] = 3
                za = zdb
                zb = -40
                zKind = 4
            elsif cType[zk] = 2
                @chordDb: zdb, cShape[zk], zMax, wD[zn]
                za = chordDb.a
                zb = chordDb.b
                zKind = 3 - seqCS[zk]
            else
                zi1 = zi1 + 1
                zKind = 1
                if env5a[zi1] = 1
                    if zLink = 0
                        za = -40
                    else
                        za = zPrevB
                        zLink = 0
                    endif
                    zb = zdb
                else
                    if zj = zc
                        zNextDb = 0
                        zNextEnv = 2
                    else
                        zNextDb = wB[zn + 1]
                        zNextEnv = env5a[zi1 + 1]
                    endif
                    za = zdb
                    if zj = zc or (zNextEnv = 2 and zNextDb > zdb) or (zNextEnv = 1 and zNextDb < zdb) or (zNextEnv = 1 and zdb < -21)
                        zb = -40
                    elsif zNextEnv = 1
                        zb = -25
                        zLink = 1
                    else
                        zb = zNextDb
                        zLink = 1
                    endif
                endif
            endif
            zPrevB = zb
            @addSerial: 5, zk, zj, wS[zn], wD[zn], wF[zn], wC[zn], za, zb, zKind
        endfor
    endfor

    # ---------------------------------------------------------- CODA
    # Five sounds read directly from the input series: degree s-1,
    # interval class 1, duration from table column 5, intensity from set 2.
    sectionNum = 6
    zt = zCodaStart
    for zi to 5
        zs = inRow[zi]
        zDur = durCm[5 * (zs - 1) + 1]
        zdb = dbTab[5 + zs]
        if zs > 3
            if zdb < -8
                za = -30
            else
                za = -40
            endif
            zb = zdb
        else
            za = zdb
            if zdb < -6
                zb = -30
            else
                zb = -40
            endif
        endif
        @addSerial: 6, 1, zi, zt, zDur, zs - 1, 1, za, zb, 5
        zt = zt + zDur
    endfor

    # ======================================================
    # TAPE CM -> SECONDS AT THE HISTORICAL SPEED, THEN CUT THE WINDOW
    # ======================================================
    # The structure is always complete; Duration only chooses how much of
    # it is heard. Playback speed is always 76.2 cm/s, never compressed.
    spanCm = 0
    for zi to numEvents
        spanCm = max(spanCm, evStart[zi] + evDur[zi])
    endfor
    spanTapeSec = spanCm / tapeSpeed_cm_s
    for zi to numEvents
        evStart[zi] = evStart[zi] / tapeSpeed_cm_s
        evDur[zi] = evDur[zi] / tapeSpeed_cm_s
        evEnd[zi] = evStart[zi] + evDur[zi]
    endfor
    numAll = numEvents
    @reportSerial

    # Window start = first sound of the chosen part.
    winStart = 0
    if whole_piece = 0
        winStart = 1e9
        for zi to numEvents
            if evSection[zi] = start_at
                winStart = min(winStart, evStart[zi])
            endif
        endfor
    endif
    requestedDur = duration_s
    winLen = duration_s
    if whole_piece or winStart + winLen > spanTapeSec + 1
        winLen = spanTapeSec + 1 - winStart
    endif
    winEnd = winStart + winLen
    # Keep every sound that is audible inside the window, including sounds
    # of the previous part still ringing at the window start (parts
    # overlap); those are rendered from mid-sound with a short fade-in.
    zKeep = 0
    nClipped = 0
    for zi to numEvents
        if evEnd[zi] > winStart and evStart[zi] < winEnd
            zKeep = zKeep + 1
            evStart[zKeep] = evStart[zi] - winStart
            evDur[zKeep] = evDur[zi]
            evEnd[zKeep] = evStart[zKeep] + evDur[zKeep]
            if evStart[zKeep] < 0 or evEnd[zKeep] > winLen
                nClipped = nClipped + 1
            endif
            evAmp[zKeep] = evAmp[zi]
            evEnv[zKeep] = evEnv[zi]
            evWidth[zKeep] = evWidth[zi]
            evSection[zKeep] = evSection[zi]
            evSub[zKeep] = evSub[zi]
            evGroup[zKeep] = evGroup[zi]
            evRegister[zKeep] = evRegister[zi]
            evNote[zKeep] = evNote[zi]
            evKind[zKeep] = evKind[zi]
            evDb1[zKeep] = evDb1[zi]
            evDb2[zKeep] = evDb2[zi]
            for zc to 5
                evFreq[zKeep, zc] = evFreq[zi, zc]
            endfor
        endif
    endfor
    numEvents = zKeep
    duration_s = winLen

    appendInfoLine: ""
    appendInfoLine: "Window (always at the historical 76.2 cm/s):"
    if whole_piece
        appendInfoLine: "  Whole piece: ", fixed$(winLen, 2), " s incl. 1 s tail (Duration ignored)."
    else
        appendInfoLine: "  Start at ", startName$[start_at], ": tape ", fixed$(winStart * tapeSpeed_cm_s, 1),
            ... " cm = ", fixed$(winStart, 2), " s into the piece"
        appendInfoLine: "  Length ", fixed$(winLen, 2), " s (", fixed$(winStart, 2), " - ", fixed$(winEnd, 2),
            ... " s of ", fixed$(spanTapeSec, 2), " s)"
        if winLen < requestedDur - 1e-6
            appendInfoLine: "  Requested ", requestedDur, " s; shortened because the piece ends there."
        endif
    endif
    appendInfoLine: "  ", numEvents, " of ", numAll, " mixtures audible, ", nClipped, " cut at a window edge (5 ms fade)."
endif

label doneGeneration

appendInfoLine: "Generated ", numEvents, " mixture events"

# ============================================================
# TIMING ADJUSTMENT - SCALE TO FIT DURATION
# ============================================================

# Random mode only: Serial mode has already mapped its complete structure
# with one global factor, and must not be re-stretched here.
if generation_mode = 1
    # Find actual span of events
    actualEndTime = 0
    for i to numEvents
        if evEnd[i] > actualEndTime
            actualEndTime = evEnd[i]
        endif
    endfor

    appendInfoLine: ""
    appendInfoLine: "Adjusting timing to fit ", duration_s, " seconds..."
    appendInfoLine: "  Generated span: ", fixed$(actualEndTime, 2), " s"
    timeScale = 1.0

    if actualEndTime > 0 and actualEndTime < duration_s
        # Scale all times to fill the duration
        timeScale = (duration_s * 0.98) / actualEndTime
    
        appendInfoLine: "  Time scaling: ", fixed$(timeScale, 3), "x"
    
        for i to numEvents
            evStart[i] = evStart[i] * timeScale
            evEnd[i] = evEnd[i] * timeScale
            evDur[i] = evDur[i] * timeScale
        endfor
    
        actualEndTime = actualEndTime * timeScale
        appendInfoLine: "  Adjusted span: ", fixed$(actualEndTime, 2), " s"
    elsif actualEndTime > duration_s
        # Scale down if exceeded
        timeScale = (duration_s * 0.98) / actualEndTime
    
        appendInfoLine: "  Time scaling: ", fixed$(timeScale, 3), "x"
    
        for i to numEvents
            evStart[i] = evStart[i] * timeScale
            evEnd[i] = evEnd[i] * timeScale
            evDur[i] = evDur[i] * timeScale
        endfor
    
        actualEndTime = actualEndTime * timeScale
        appendInfoLine: "  Adjusted span: ", fixed$(actualEndTime, 2), " s"
    endif
endif

# ============================================================
# RENDER AUDIO WITH SCALED TIMES
# ============================================================

appendInfoLine: ""
appendInfoLine: "Rendering audio..."

# Remove temporary master and create final one
removeObject: master
master = Create Sound from formula: "master_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Serial: every Tongemisch is made in the reverberation chamber model
# BEFORE assembly, as in 1954 (the reverb is part of the sound, not a mix
# effect).
appendInfoLine: "  Building reverberation chamber (RT60 10 s, wet only) ..."
@buildChamber

# Render all events with scaled times
for i to numEvents
    if evEnv[i] = 8
        @renderSerial: i
    else
        @renderMixture: i
    endif
    
    if (i mod 20) = 0
        appendInfoLine: "  Rendered ", i, "/", numEvents
    endif
endfor

appendInfoLine: "Rendering complete"
removeObject: chamberFold

# === Reverberation ===
# Both modes pass every mixture through the chamber model before assembly;
# the 1954 tape was built from those sounds with no further reverb, so no
# post-mix reverb is added.

# === Normalize ===
selectObject: master
if generation_mode = 1
    Rename: "studieII_random"
else
    Rename: "studieII_serial"
endif
Scale peak: output_peak

outputSound = selected("Sound")
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

# === Draw Score ===
if draw_score
    appendInfoLine: ""
    appendInfoLine: "Drawing score..."
    @drawScore
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: storeEvent (Random Mode)
# ==============================================================================
procedure storeEvent: .startTime, .duration, .startIdx, .spreadFactor, .amplitude, .envType
    
    numEvents = numEvents + 1
    
    evStart[numEvents] = .startTime
    evEnd[numEvents] = .startTime + .duration
    evDur[numEvents] = .duration
    evAmp[numEvents] = .amplitude
    evEnv[numEvents] = .envType
    evWidth[numEvents] = .spreadFactor
    evSection[numEvents] = sectionNum
    evSub[numEvents] = subsectionNum
    evGroup[numEvents] = groupNum
    evRegister[numEvents] = 0
    
    for .c to 5
        .ix = .startIdx + (.c - 1) * .spreadFactor
        if .ix < 1
            .ix = 1
        endif
        if .ix > 81
            .ix = 81
        endif
        evFreq[numEvents, .c] = freq[.ix]
    endfor
endproc

# ==============================================================================
# SERIAL PROCEDURES
# Shared state (globals): sq[q, i] squares (1-5 R, 6-10 U, i = 1..25 row-wise),
# stel[1..75] position stream, mDeg/mCol method output (0-based table index,
# column), wF/wC/wD/wB/wS/wG per-part working arrays, seqSt[1..26] sequence
# starts in cm, seqCS[k] chord type (1 common start, 0 common end, -1 none).
# ==============================================================================

# ------------------------------------------------------------------------------
# buildSquares: R1 from the input series, R2-R5 by the hop procedure,
# U1-U5 by inversion. Port of Heintz's SS2_Transp_R / SS2_Hop / SS2_Umk.
# ------------------------------------------------------------------------------
procedure buildSquares
    # R1: the INTERVAL sequence of the series (read cyclically) is laid onto
    # each of the series' own values in turn, wrapping inside 1..5.
    for .r to 5
        .tv = inRow[.r]
        for .i to 5
            .nx = (.i mod 5) + 1
            .iv = inRow[.nx] - inRow[.i]
            sq[1, (.r - 1) * 5 + .i] = .tv
            .nv = .tv + .iv
            if .nv > 5
                .nv = .nv - 5
            elsif .nv < 1
                .nv = .nv + 5
            endif
            .tv = .nv
        endfor
    endfor

    # Distance pattern of R1: for lines 2-5, how far (mod 5) each next value
    # lies from the current one, measured as positions in line 1.
    for .i to 5
        sqHead[.i] = sq[1, .i]
    endfor
    for .r from 2 to 5
        for .i to 4
            @posInHead: sq[1, (.r - 1) * 5 + .i]
            .a = posInHead.ix
            @posInHead: sq[1, (.r - 1) * 5 + .i + 1]
            .d = posInHead.ix - .a
            if .d < 0
                .d = .d + 5
            endif
            sqDist[(.r - 2) * 4 + .i] = .d
        endfor
    endfor

    # R2-R5: line q of R1 becomes the top line; line starts are read from it
    # with step q; each line then walks R1's distance pattern through it.
    for .q from 2 to 5
        for .i to 5
            sqHead[.i] = sq[1, (.q - 1) * 5 + .i]
            sq[.q, .i] = sqHead[.i]
        endfor
        for .ln from 2 to 5
            .start = sqHead[(((.ln - 1) * .q) mod 5) + 1]
            sq[.q, (.ln - 1) * 5 + 1] = .start
            @posInHead: .start
            .ix = posInHead.ix
            for .k to 4
                .ix = ((.ix - 1 + sqDist[(.ln - 2) * 4 + .k]) mod 5) + 1
                sq[.q, (.ln - 1) * 5 + 1 + .k] = sqHead[.ix]
            endfor
        endfor
    endfor

    # U1-U5: inversion n -> 6 - n.
    for .q to 5
        for .i to 25
            sq[.q + 5, .i] = 6 - sq[.q, .i]
        endfor
    endfor
endproc

procedure posInHead: .v
    .ix = 0
    for .i to 5
        if sqHead[.i] = .v
            .ix = .i
        endif
    endfor
endproc

# ------------------------------------------------------------------------------
# parseList: space-separated numbers -> listV[1..listN]
# ------------------------------------------------------------------------------
procedure parseList: .s$
    listN = 0
    .s$ = .s$ + " "
    while length(.s$) > 0
        .sp = index(.s$, " ")
        .tok$ = left$(.s$, .sp - 1)
        .s$ = mid$(.s$, .sp + 1, length(.s$) - .sp)
        if .tok$ <> ""
            listN = listN + 1
            listV[listN] = number(.tok$)
        endif
    endwhile
endproc

# ------------------------------------------------------------------------------
# setStel: the position stream D = three squares read end to end (75 values,
# one per sound of a part).
# ------------------------------------------------------------------------------
procedure setStel: .a, .b, .c
    for .i to 25
        stel[.i] = sq[.a, .i]
        stel[25 + .i] = sq[.b, .i]
        stel[50 + .i] = sq[.c, .i]
    endfor
endproc

# ------------------------------------------------------------------------------
# meth1: counts square S, group square A, constant transposition B, column
# square C. A and C are read once per sequence and so repeat S times; D
# advances every sound. Output: mDeg (0-based table index), mCol.
# ------------------------------------------------------------------------------
procedure meth1: .cq, .gq, .t, .colq
    .n = 0
    for .k to 25
        .g = sq[.gq, .k]
        .c = sq[.colq, .k]
        for .j to sq[.cq, .k]
            .n = .n + 1
            mDeg[.n] = 5 * (.g + .t - 2) + .c * (stel[.n] - 1)
            mCol[.n] = .c
        endfor
    endfor
endproc

# ------------------------------------------------------------------------------
# meth2 (Parts III-V): the group follows the POSITION sound by sound, and the
# transposition becomes a series read once per sequence.
# ------------------------------------------------------------------------------
procedure meth2: .cq, .tq, .colq
    .n = 0
    for .k to 25
        .t = sq[.tq, .k]
        .c = sq[.colq, .k]
        for .j to sq[.cq, .k]
            .n = .n + 1
            .p = stel[.n]
            mDeg[.n] = 5 * (.p + .t - 2) + .c * (.p - 1)
            mCol[.n] = .c
        endfor
    endfor
endproc

procedure copyFreq
    for .i to 75
        wF[.i] = mDeg[.i]
        wC[.i] = mCol[.i]
    endfor
endproc

procedure copyDur
    for .i to 75
        wD[.i] = durCm[mDeg[.i] + 1]
    endfor
endproc

procedure copyDb
    for .i to 75
        wB[.i] = dbTab[mDeg[.i] + 1]
    endfor
endproc

# ------------------------------------------------------------------------------
# seqStarts: ghost-duration starts, one per sequence. The ghost durations of
# a sequence are summed and taken as the distance to the next sequence
# start; seqSt[26] is where the next part begins.
# ------------------------------------------------------------------------------
procedure seqStarts: .cq, .gq, .t, .colq, .s0
    seqSt[1] = .s0
    .s = .s0
    .n = 0
    for .k to 25
        .acc = 0
        for .j to sq[.cq, .k]
            .n = .n + 1
            .deg = 5 * (sq[.gq, .k] + .t - 2) + sq[.colq, .k] * (stel[.n] - 1)
            .acc = .acc + durCm[.deg + 1]
        endfor
        .s = .s + .acc
        seqSt[.k + 1] = .s
    endfor
endproc

# ------------------------------------------------------------------------------
# chordDurs: common start -> first duration as read, each further one is
# the running sum; common end -> the same, counted from the last sound.
# ------------------------------------------------------------------------------
procedure chordDurs: .cq
    for .i to 75
        wDn[.i] = wD[.i]
    endfor
    .n = 0
    for .k to 25
        .c = sq[.cq, .k]
        .acc = 0
        if seqCS[.k] = 1
            for .j to .c
                .acc = .acc + wDn[.n + .j]
                wD[.n + .j] = .acc
            endfor
        elsif seqCS[.k] = 0
            for .j to .c
                .i = .n + .c - .j + 1
                .acc = .acc + wDn[.i]
                wD[.i] = .acc
            endfor
        endif
        .n = .n + .c
    endfor
endproc

# ------------------------------------------------------------------------------
# shapeOf: envelope number of a chord -> dB shape.
#   1 = diminuendo converging on a common vanishing point (shorter sounds stop
#       above -40 dB), 2 = crescendo from -40, 3 = diminuendo to -40,
#   4 = crescendo from a common vanishing point.
# Part II: env 5 = common end, crescendo. Part IV/V: env 5 = common start,
# diminuendo. Part V: env 6 = common end, crescendo.
# ------------------------------------------------------------------------------
procedure shapeOf: .part, .env
    .shape = .env
    if .env = 5
        if .part = 2
            .shape = 2
        else
            .shape = 3
        endif
    elsif .env = 6
        .shape = 2
    endif
endproc

procedure chordDb: .db, .shape, .mx, .d
    if .shape = 2
        .a = -40
        .b = .db
    elsif .shape = 3
        .a = .db
        .b = -40
    elsif .shape = 1
        .a = .db
        .b = .db - (.d / .mx) * (.db + 35)
        if .b <= -35
            .b = -40
        endif
    else
        .b = .db
        .a = .db - (.d / .mx) * (.db + 35)
        if .a <= -35
            .a = -40
        endif
    endif
endproc

# ------------------------------------------------------------------------------
# emitChords: Parts II and IV. Common start: every sound begins on the
# sequence start. Common end: every sound ends with the longest one.
# ------------------------------------------------------------------------------
procedure emitChords: .part, .cq
    .n = 0
    for .k to 25
        .c = sq[.cq, .k]
        .mx = 0
        for .j to .c
            .mx = max(.mx, wD[.n + .j])
        endfor
        for .j to .c
            .n = .n + 1
            @chordDb: wB[.n], cShape[.k], .mx, wD[.n]
            if seqCS[.k] = 1
                .st = seqSt[.k]
                .kind = 2
            else
                .st = seqSt[.k] + .mx - wD[.n]
                .kind = 3
            endif
            @addSerial: .part, .k, .j, .st, wD[.n], wF[.n], wC[.n], chordDb.a, chordDb.b, .kind
        endfor
    endfor
endproc

# ------------------------------------------------------------------------------
# addSerial: append one mixture to the event table (times in tape cm until
# the global mapping). .kind: 1 linked, 2 chord common start, 3 chord common
# end, 4 isolated, 5 coda.
# ------------------------------------------------------------------------------
procedure addSerial: .part, .k, .j, .startCm, .durCm, .deg, .col, .db1, .db2, .kind
    numEvents = numEvents + 1
    evStart[numEvents] = .startCm
    evDur[numEvents] = .durCm
    evEnd[numEvents] = .startCm + .durCm
    evDb1[numEvents] = .db1
    evDb2[numEvents] = .db2
    evAmp[numEvents] = 10 ^ (max(.db1, .db2) / 20)
    evEnv[numEvents] = 8
    evWidth[numEvents] = .col
    evSection[numEvents] = .part
    evSub[numEvents] = floor((.k - 1) / 5) + 1
    evGroup[numEvents] = ((.k - 1) mod 5) + 1
    evNote[numEvents] = .j
    evKind[numEvents] = .kind
    evRegister[numEvents] = .deg
    for .c to 5
        evFreq[numEvents, .c] = freq[.deg + 1 + (.c - 1) * .col]
    endfor
endproc

# ------------------------------------------------------------------------------
# reportSerial: structure, validation and fidelity notes in the Info window.
# ------------------------------------------------------------------------------
procedure reportSerial
    for .p to 6
        .cnt[.p] = 0
        .t0[.p] = 1e9
        .t1[.p] = 0
        .dLo[.p] = 99
        .dHi[.p] = -1
    endfor
    .maxIdx = 0
    for .i to numEvents
        .p = evSection[.i]
        .cnt[.p] = .cnt[.p] + 1
        .t0[.p] = min(.t0[.p], evStart[.i])
        .t1[.p] = max(.t1[.p], evEnd[.i])
        .dLo[.p] = min(.dLo[.p], evRegister[.i])
        .dHi[.p] = max(.dHi[.p], evRegister[.i] + 4 * evWidth[.i])
        .maxIdx = max(.maxIdx, evRegister[.i] + 4 * evWidth[.i])
    endfor
    .k = tapeSpeed_cm_s

    appendInfoLine: "Serial structure of the whole piece (tape cm -> s at 76.2 cm/s):"
    for .p to 6
        if .p <= 5
            .nm$ = "Part " + string$(.p)
        else
            .nm$ = "Coda  "
        endif
        appendInfoLine: "  ", .nm$, ": ", .cnt[.p], " mixtures | ",
            ... fixed$(.t0[.p] * .k, 1), " - ", fixed$(.t1[.p] * .k, 1), " cm | ",
            ... fixed$(.t0[.p], 3), " - ", fixed$(.t1[.p], 3), " s | degrees ",
            ... .dLo[.p], " - ", .dHi[.p]
    endfor
    appendInfoLine: "  Total span: ", fixed$(spanCm, 1), " cm = ",
        ... fixed$(spanTapeSec, 2), " s of tape"
    appendInfoLine: ""
    appendInfoLine: "Validation:"
    .ok$ = if numEvents = 380 then "OK" else "MISMATCH" fi
    appendInfoLine: "  Event count ", numEvents, " (theoretical 5 x 75 + 5 = 380): ", .ok$
    if rotN = 0
        .r1$ = string$(sq[1, 1]) + string$(sq[1, 2]) + string$(sq[1, 3]) + string$(sq[1, 4]) + string$(sq[1, 5])
            ... + "/" + string$(sq[1, 6]) + string$(sq[1, 7]) + string$(sq[1, 8]) + string$(sq[1, 9]) + string$(sq[1, 10])
        .ok$ = if .r1$ = "35142/52314" then "OK" else "MISMATCH" fi
        appendInfoLine: "  R1 rows 1-2 = ", .r1$, " (Heintz: 35142/52314): ", .ok$
        .ok$ = if round(evFreq[1, 1]) = 690 and evWidth[1] = 5 then "OK" else "MISMATCH" fi
        appendInfoLine: "  First mixture ", fixed$(evFreq[1, 1], 1), " Hz, interval class ", evWidth[1],
            ... " (Heintz: 690 Hz, mixture 5): ", .ok$
        # Part II, first chord: Heintz's worked example of accumulation
        # (18.4, 18.4 + 14.2, 18.4 + 14.2 + 23.8 cm).
        .c1 = 0
        while evSection[.c1 + 1] < 2
            .c1 = .c1 + 1
        endwhile
        .s$ = fixed$(evDur[.c1 + 1] * .k, 1) + "/" + fixed$(evDur[.c1 + 2] * .k, 1) + "/" + fixed$(evDur[.c1 + 3] * .k, 1)
        .ok$ = if .s$ = "18.4/32.6/56.4" then "OK" else "MISMATCH" fi
        appendInfoLine: "  Part II first chord ", .s$, " cm (Heintz: 18.4/32.6/56.4): ", .ok$
    else
        appendInfoLine: "  Input series rotated by ", rotN, ": NOT the historical derivation."
    endif
    .ok$ = if .maxIdx <= 80 then "OK" else "OUT OF RANGE" fi
    appendInfoLine: "  Highest scale degree used: ", .maxIdx, " (limit 80): ", .ok$

    appendInfoLine: ""
    appendInfoLine: "Fidelity:"
    appendInfoLine: "  Derived from the series: squares, frequencies, mixtures, durations,"
    appendInfoLine: "    intensities, ghost-duration starts, chord accumulation, coda."
    appendInfoLine: "  Transcribed from the score (no serial origin found in the sketches):"
    appendInfoLine: "    envelope series of Parts I, II, IV, V; sequence types of Part V."
    if apply_score_corrections
        appendInfoLine: "  Part V score corrections ON (group 2 substitutions, last column 3, 38 dB values)."
    else
        appendInfoLine: "  Part V score corrections OFF: plain serial derivation of Part V."
    endif
    appendInfoLine: "  Sound production (score p. VII via Williams 2016): each mixture is a loop of five"
    appendInfoLine: "    4 cm sines (lowest to highest, 45-degree splices) played into a 10 s chamber, wet"
    appendInfoLine: "    only; fader in dB; rising sounds played backwards. The chamber itself is synthetic:"
    appendInfoLine: "    no impulse response of the WDR rooms survives (damping above 1 kHz is assumed)."
    appendInfoLine: "  Not modelled: Stockhausen's errors and local changes in Parts I-IV."
    appendInfoLine: "  Serial levels come from the dB series; Min/Max event amplitude apply to Random mode only."

    appendInfoLine: ""
    appendInfoLine: "Event list  (Part.Set.Seq.Sound  start cm  dur cm  degree  class  f1-f5 Hz  dB1 > dB2  kind)"
    for .i to numEvents
        .pn$ = if evSection[.i] = 6 then "C" else string$(evSection[.i]) fi
        appendInfoLine: "  ", .pn$, ".", evSub[.i], ".", evGroup[.i], ".", evNote[.i], tab$,
            ... fixed$(evStart[.i] * .k, 1), tab$, fixed$(evDur[.i] * .k, 1), tab$,
            ... evRegister[.i], tab$, evWidth[.i], tab$,
            ... fixed$(evFreq[.i, 1], 0), "-", fixed$(evFreq[.i, 5], 0), tab$,
            ... fixed$(evDb1[.i], 0), " > ", fixed$(evDb2[.i], 0), tab$, evKind[.i]
    endfor
endproc

# ------------------------------------------------------------------------------
# buildChamber: synthetic reverberation chamber and the tape-loop period.
#   Score, p. VII (as reported by Williams 2016): the five sines, each 4 cm
#   of tape recorded at 0 dB, are spliced end to end into a loop from the
#   lowest to the highest note; the loop is played at 0 dB into a room with
#   about 10 s reverberation time and regular frequency response, and only
#   the reverberated sound is kept.
#   A loop through a time-invariant room settles into a PERIODIC signal with
#   the loop's period, so the steady-state chamber output is computed
#   EXACTLY for one period by circular convolution with the room response
#   folded onto that period. No impulse response of the WDR chambers
#   survives; the room here is exponentially decaying noise, RT60 10 s,
#   with mild air-absorption damping above 1 kHz (an assumption).
# ------------------------------------------------------------------------------
procedure buildChamber
    loopSegN = round(4 / tapeSpeed_cm_s * sample_rate_Hz)
    loopN = 5 * loopSegN
    loopT = loopN / sample_rate_Hz
    # 45-degree splice (the WDR default) across 6.35 mm tape = 6.35 mm of
    # tape length = a linear crossfade of 0.635 / 76.2 s = 8.3 ms.
    spliceT = 0.635 / tapeSpeed_cm_s
    .len = 12
    .ir = Create Sound from formula: "chamberNoise_" + uid$, 1, 0, .len, sample_rate_Hz, "randomGauss(0, 1)"
    .lo = Filter (pass Hann band): 0, 1000, 200
    Formula: "self * exp(-6.9078 * x / 10)"
    selectObject: .ir
    .mid = Filter (pass Hann band): 1000, 4000, 500
    Formula: "self * exp(-6.9078 * x / 8)"
    selectObject: .ir
    .hi = Filter (pass Hann band): 4000, 0, 1000
    Formula: "self * exp(-6.9078 * x / 5)"
    selectObject: .lo
    Formula: "self + object[" + string$(.mid) + ", col] + object[" + string$(.hi) + ", col]"
    # Fold the room response onto one loop period.
    chamberFold = Create Sound from formula: "chamberFold_" + uid$, 1, 0, loopT, sample_rate_Hz, "0"
    .nSeg = ceiling(.len * sample_rate_Hz / loopN)
    for .k from 0 to .nSeg - 1
        Formula: "self + object[" + string$(.lo) + ", 1, col + " + string$(.k * loopN) + "]"
    endfor
    removeObject: .ir, .lo, .mid, .hi
endproc

# ------------------------------------------------------------------------------
# chamberPeriod: one steady-state period of the reverberated loop for event
# .e -> chamberPeriod.id (a Sound of loopN samples, RMS-normalised so that
# 0 dB means the same loudness for every mixture, as on the 1954 tapes).
# ------------------------------------------------------------------------------
procedure chamberPeriod: .e
    .loop = Create Sound from formula: "loop_" + uid$, 1, 0, loopT, sample_rate_Hz, "0"
    .segT = loopSegN / sample_rate_Hz
    for .c to 5
        if equal_partial_levels
            .w = 1
        else
            .w = 1.0 - abs(.c - 3) * 0.12
        endif
        # Each 4 cm length cut from a recording of the sine: arbitrary phase.
        .ph = randomUniform(0, 2 * pi)
        # u = time since the start of this segment's splice crossfade
        .u$ = "((x - " + fixed$((.c - 1) * .segT - spliceT / 2, 7) + " + " + fixed$(loopT, 7) + ") mod " + fixed$(loopT, 7) + ")"
        .win$ = "(if " + .u$ + " < " + fixed$(spliceT, 7) + " then " + .u$ + " / " + fixed$(spliceT, 7)
            ... + " else if " + .u$ + " < " + fixed$(.segT, 7) + " then 1"
            ... + " else if " + .u$ + " < " + fixed$(.segT + spliceT, 7) + " then 1 - (" + .u$ + " - " + fixed$(.segT, 7) + ") / " + fixed$(spliceT, 7)
            ... + " else 0 fi fi fi)"
        Formula: "self + " + fixed$(.w, 3) + " * " + .win$ + " * sin(" + fixed$(2 * pi * evFreq[.e, .c], 6) + " * " + .u$ + " + " + fixed$(.ph, 6) + ")"
    endfor
    plusObject: chamberFold
    .conv = Convolve: "sum", "zero"
    .id = Create Sound from formula: "period_" + uid$, 1, 0, loopT, sample_rate_Hz,
        ... "object[" + string$(.conv) + ", 1, col] + object[" + string$(.conv) + ", 1, col + " + string$(loopN) + "]"
    .rms = Get root-mean-square: 0, 0
    # Five equal sines at amplitude 1 have RMS sqrt(5/2).
    Formula: "self * " + fixed$(sqrt(2.5) / max(1e-12, .rms), 9)
    removeObject: .loop, .conv
endproc

# ------------------------------------------------------------------------------
# renderSerial: cut the reverberated loop to the event's length, shape it
# with the fader (linear in dB, dB1 -> dB2, down to -40 dB) and write it
# straight into the master. Rising sounds are the tape played BACKWARDS, as
# in the realisation. Edges: 2 ms, as in Williams's realisation; sounds cut
# by a window edge get 5 ms.
# ------------------------------------------------------------------------------
procedure renderSerial: .e
    .t0 = evStart[.e]
    .d = evDur[.e]
    .tEnd = .t0 + .d
    .lo = max(0, .t0)
    .hi = min(duration_s, .tEnd)
    if .hi > .lo
        @chamberPeriod: .e
        .per = chamberPeriod.id
        .fa = min(0.002, .d / 4)
        .slope = (evDb2[.e] - evDb1[.e]) / .d
        .t0$ = fixed$(.t0, 7)
        .ix$ = "(floor((x - " + .t0$ + ") * " + string$(sample_rate_Hz) + ") mod " + string$(loopN) + ")"
        if evDb2[.e] > evDb1[.e]
            .read$ = "object[" + string$(.per) + ", 1, " + string$(loopN) + " - " + .ix$ + "]"
        else
            .read$ = "object[" + string$(.per) + ", 1, " + .ix$ + " + 1]"
        endif
        .edge$ = ""
        .fw = min(0.005, (.hi - .lo) / 4)
        if .t0 < 0
            .edge$ = .edge$ + " * min(1, (x-" + fixed$(.lo, 7) + ")/" + fixed$(.fw, 7) + ")"
        endif
        if .tEnd > duration_s
            .edge$ = .edge$ + " * min(1, (" + fixed$(.hi, 7) + "-x)/" + fixed$(.fw, 7) + ")"
        endif
        .f$ = "self + 10^((" + fixed$(evDb1[.e], 4) + " + " + fixed$(.slope, 6) + "*(x-" + .t0$ + "))/20)"
            ... + " * min(1, (x-" + .t0$ + ")/" + fixed$(.fa, 7) + ", (" + fixed$(.tEnd, 7) + "-x)/" + fixed$(.fa, 7) + ")"
            ... + .edge$ + " * " + .read$
        selectObject: master
        Formula (part): .lo, .hi, 1, 1, .f$
        removeObject: .per
    endif
endproc

# ==============================================================================
# Procedure: renderMixture
# ==============================================================================
procedure renderMixture: .eventNum
    
    .startTime = evStart[.eventNum]
    .duration = evDur[.eventNum]
    .amplitude = evAmp[.eventNum]
    .envType = evEnv[.eventNum]
    
    # Create mixture sound
    .mixSound = Create Sound from formula: "mix_" + uid$, 1, 0, .duration, sample_rate_Hz, "0"
    
    # Source: the reverberated tape loop of this mixture's five sines (the
    # same chamber process as Serial mode), tiled over the event and scaled
    # to the event amplitude. A rising ramp (envelope 2) is the reverberated
    # tape played backwards, as in 1954.
    @chamberPeriod: .eventNum
    .per = chamberPeriod.id
    selectObject: .mixSound
    if .envType = 2
        Formula: fixed$(.amplitude, 5) + " * object[" + string$(.per) + ", 1, " + string$(loopN) + " - ((col - 1) mod " + string$(loopN) + ")]"
    else
        Formula: fixed$(.amplitude, 5) + " * object[" + string$(.per) + ", 1, ((col - 1) mod " + string$(loopN) + ") + 1]"
    endif
    removeObject: .per
    
    # Apply envelope
    selectObject: .mixSound
    if .envType = 1
        .att = min(0.025, .duration * 0.2)
        .rel = min(0.018, .duration * 0.15)
        Fade in: 0, 0, .att, "yes"
        Fade out: 0, .duration - .rel, .rel, "yes"
    elsif .envType = 2
        .rampEnd = .duration * 0.72
        Formula: "self * min(1, x / " + fixed$(.rampEnd, 4) + ")"
        Fade out: 0, .duration - 0.01, 0.01, "yes"
    elsif .envType = 3
        .tau = .duration / 2.8
        Formula: "self * exp(-x / " + fixed$(.tau, 6) + ")"
        .att3 = min(0.004, .duration * 0.08)
        .rel3 = min(0.012, .duration * 0.15)
        Fade in: 0, 0, .att3, "yes"
        Fade out: 0, .duration - .rel3, .rel3, "yes"
    elsif .envType = 4
        .peak = .duration / 2
        Formula: "self * (1 - abs(x - " + fixed$(.peak, 6) + ") / " + fixed$(.peak, 6) + ")"
    elsif .envType = 5
        .att5 = min(0.003, .duration * 0.08)
        .rel5 = min(0.006, .duration * 0.12)
        Fade in: 0, 0, .att5, "yes"
        Fade out: 0, .duration - .rel5, .rel5, "yes"
    elsif .envType = 6
        # Falling reverberant envelope (forward tape direction).
        Formula: "self * exp(-3 * x / " + fixed$(.duration, 6) + ") * (1 - x / " + fixed$(.duration, 6) + ")"
    else
        # Rising envelope: time-reversed counterpart of type 6.
        Formula: "self * exp(-3 * (" + fixed$(.duration, 6) + " - x) / " + fixed$(.duration, 6) + ") * (x / " + fixed$(.duration, 6) + ")"
    endif
    
    # Add to master at correct time position
    .sampleOffset = round(.startTime * sample_rate_Hz)
    
    selectObject: master
    Formula: "self + Sound_mix_" + uid$ + "[col - " + string$(.sampleOffset) + "]"
    
    removeObject: .mixSound
endproc

# ==============================================================================
# Procedure: drawScore
# ==============================================================================
# ==============================================================================
# Procedure: drawScore
#
# Two systems, as in the published score of 1954: an upper system plotting the
# frequency band of each Tongemisch against time, and a lower system plotting
# its amplitude envelope. Between them runs the tape ruler, because the score's
# own time unit is centimetres of tape at 76.2 cm/s.
#
# Colour is not in the original, which is ink on graph paper. It is used here
# for one thing only: the five Tongemisch WIDTHS (I-V = 1..5 scale steps). That
# is the parameter Stockhausen serialised and the one a monochrome print makes
# hardest to read, since width shows only as box height on a log axis. Grid,
# rules, boxes and lettering stay black so the page still reads as a score.
# ==============================================================================
procedure drawScore

    .lo = 1.32
    .hi = 7.72
    .ink$ = "{0.12,0.12,0.14}"
    .grid$ = "{0.86,0.86,0.88}"
    .grid5$ = "{0.72,0.72,0.75}"
    .faint$ = "{0.45,0.45,0.50}"
    .paper$ = "{0.995,0.993,0.985}"

    # Width classes I-V. Ordered dark-to-light so the narrowest mixture reads
    # as the most concentrated.
    .w1$ = "{0.16,0.24,0.48}"
    .w2$ = "{0.20,0.48,0.60}"
    .w3$ = "{0.32,0.55,0.35}"
    .w4$ = "{0.78,0.55,0.20}"
    .w5$ = "{0.66,0.24,0.26}"

    .logLo = ln(freq[1])
    .logHi = ln(freq[81])
    .span = .logHi - .logLo

    if duration_s <= 6
        .tTick = 1
    elsif duration_s <= 30
        .tTick = 2
    elsif duration_s <= 90
        .tTick = 10
    else
        .tTick = 30
    endif

    # Section spans, for the banding in the upper system.
    for .s to 6
        .secStart[.s] = -1
        .secEnd[.s] = -1
    endfor
    .haveSections = 0
    for .e to numEvents
        .s = evSection[.e]
        if .s >= 1 and .s <= 6
            .haveSections = 1
            .st = max(0, evStart[.e])
            if .secStart[.s] < 0 or .st < .secStart[.s]
                .secStart[.s] = .st
            endif
            if evEnd[.e] > .secEnd[.s]
                .secEnd[.s] = evEnd[.e]
            endif
        endif
    endfor

    for .w to 5
        .widthCount[.w] = 0
    endfor
    for .e to numEvents
        .w = evWidth[.e]
        if .w >= 1 and .w <= 5
            .widthCount[.w] = .widthCount[.w] + 1
        endif
    endfor

    Erase all
    Solid line
    Line width: 1

    # ======================= TITLE =======================
    Select inner viewport: 0.60, 7.72, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    if generation_mode = 2
        Text: 0.5, "centre", 0.80, "half", "##STUDIE II — SERIAL RECONSTRUCTION##"
    else
        Text: 0.5, "centre", 0.80, "half", "##STUDIE II — RANDOM MODE##"
    endif
    Font size: 6
    Colour: .faint$
    Text: 0.5, "centre", 0.44, "half",
        ... "81-tone scale on 5\^ (1/25), 100 Hz to 17.2 kHz  |  five-sine Tongemische  |  "
        ... + "tape ruler at 76.2 cm/s  |  " + string$(numEvents) + " mixtures"
    Font size: 5
    if generation_mode = 2
        Text: 0.5, "centre", 0.12, "half",
            ... "regenerated from 3 5 1 4 2 after Silberhorn / Heintz, not a transcription; colour encodes interval class and is not in the original score"
    else
        Text: 0.5, "centre", 0.12, "half",
            ... "a creative quasi-Studie II, not a reconstruction; colour encodes Tongemisch width and is not in the original score"
    endif

    # ======================= UPPER SYSTEM =======================
    Select inner viewport: 0.60, 7.72, 0.86, 1.04
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##UPPER SYSTEM — Tongemische on the 81-tone scale##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "each box spans the five sine tones of one mixture; inner rules are the tones themselves"

    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Paint rectangle: .paper$, 0, duration_s, .logLo, .logHi

    # Section banding: the five-part form, invisible in the previous layout.
    if .haveSections
        Select inner viewport: .lo, .hi, 1.10, 3.62
        Axes: 0, duration_s, .logLo, .logHi
        for .s to 5
            if .secStart[.s] >= 0 and (.s mod 2) = 0
                Paint rectangle: "{0.955,0.955,0.972}",
                    ... .secStart[.s], min(duration_s, .secEnd[.s]), .logLo, .logHi
            endif
        endfor
    endif

    # The 81 scale degrees, every fifth one stronger: this is the score's
    # own ruled staff, and the reason the piece has no octaves.
    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Line width: 1
    for .i to 81
        .y = ln(freq[.i])
        if ((.i - 1) mod 5) = 0
            Colour: .grid5$
        else
            Colour: .grid$
        endif
        Draw line: 0, .y, duration_s, .y
    endfor

    # Mixture boxes.
    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    for .e to numEvents
        .t0 = max(0, evStart[.e])
        .t1 = min(duration_s, evEnd[.e])
        if .t1 > .t0
            .fLoE = ln(evFreq[.e, 1])
            .fHiE = ln(evFreq[.e, 5])
            .w = evWidth[.e]
            if .w = 1
                .col$ = .w1$
            elsif .w = 2
                .col$ = .w2$
            elsif .w = 3
                .col$ = .w3$
            elsif .w = 4
                .col$ = .w4$
            else
                .col$ = .w5$
            endif
            # Amplitude reads as tint, so a quiet mixture is a pale box.
            .k = 0.30 + 0.70 * min(1, evAmp[.e] / max(1e-9, max_amplitude))
            Paint rectangle: .col$, .t0, .t1, .fLoE, .fHiE
        endif
    endfor

    # The five sine tones inside each box, and the box outline, in ink.
    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Line width: 1
    Colour: .ink$
    for .e to numEvents
        .t0 = max(0, evStart[.e])
        .t1 = min(duration_s, evEnd[.e])
        if .t1 > .t0
            for .c to 5
                .y = ln(evFreq[.e, .c])
                Draw line: .t0, .y, .t1, .y
            endfor
            Draw rectangle: .t0, .t1, ln(evFreq[.e, 1]), ln(evFreq[.e, 5])
        endif
    endfor

    # Section numerals sit on the staff, as structural marks rather than a key.
    if .haveSections
        Select inner viewport: .lo, .hi, 1.10, 3.62
        Axes: 0, duration_s, .logLo, .logHi
        Font size: 7
        Colour: "{0.55,0.55,0.60}"
        for .s to 6
            if .secStart[.s] >= 0 and .secStart[.s] < duration_s
                if .s = 1
                    .num$ = "I"
                elsif .s = 2
                    .num$ = "II"
                elsif .s = 3
                    .num$ = "III"
                elsif .s = 4
                    .num$ = "IV"
                elsif .s = 5
                    .num$ = "V"
                else
                    .num$ = "Coda"
                endif
                Text: .secStart[.s] + 0.004 * duration_s, "left", .logHi - 0.04 * .span, "half", .num$
            endif
        endfor
    endif

    Select inner viewport: .lo, .hi, 1.10, 3.62
    Axes: 0, duration_s, .logLo, .logHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    # Label every tenth scale degree with its degree number and frequency:
    # the degree is the compositional unit, the hertz value the acoustic one.
    for .i from 1 to 81
        if ((.i - 1) mod 10) = 0
            .fv = freq[.i]
            if .fv >= 1000
                .lab$ = string$(.i - 1) + "  " + fixed$(.fv / 1000, 1) + "k"
            else
                .lab$ = string$(.i - 1) + "  " + fixed$(.fv, 0)
            endif
            One mark left: ln(.fv), "no", "yes", "no", .lab$
        endif
    endfor
    Font size: 6
    Text left: "yes", "degree / Hz"

    # ======================= TAPE RULER =======================
    Select inner viewport: .lo, .hi, 3.78, 4.02
    Axes: 0, duration_s, 0, 1
    Paint rectangle: "{0.97,0.97,0.97}", 0, duration_s, 0, 1

    Select inner viewport: .lo, .hi, 3.78, 4.02
    Axes: 0, duration_s, 0, 1
    Colour: .ink$
    Line width: 1
    Draw inner box
    Font size: 5
    Colour: .faint$
    # Ruler in absolute centimetres of the 1954 tape. In Serial mode the
    # output is a window starting winStart seconds into the piece.
    .cm0 = winStart * tapeSpeed_cm_s
    .cmTotal = duration_s * tapeSpeed_cm_s
    .cmTick = 100
    if .cmTotal > 12000
        .cmTick = 2000
    elsif .cmTotal > 6000
        .cmTick = 1000
    elsif .cmTotal > 3000
        .cmTick = 500
    elsif .cmTotal < 300
        .cmTick = 20
    elsif .cmTotal < 600
        .cmTick = 50
    endif
    .kLo = ceiling(.cm0 / .cmTick)
    .kHi = floor((.cm0 + .cmTotal) / .cmTick)
    Colour: .ink$
    for .k from .kLo to .kHi
        .tc = (.k * .cmTick - .cm0) / tapeSpeed_cm_s
        if .tc >= 0 and .tc <= duration_s
            Draw line: .tc, 0.52, .tc, 1
            Text: .tc, "centre", 0.30, "half", string$(.k * .cmTick)
        endif
    endfor
    Font size: 5
    Colour: .faint$
    Text: duration_s * 0.998, "right", 0.78, "half", "cm of tape"

    Select inner viewport: .lo, .hi, 3.78, 4.02
    Axes: 0, duration_s, 0, 1
    Font size: 5
    Colour: "Black"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"

    # ======================= LOWER SYSTEM =======================
    Select inner viewport: 0.60, 7.72, 4.42, 4.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##LOWER SYSTEM — amplitude envelopes##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "one envelope per mixture, in dB, coloured by its interval class"

    .dbFloor = -40
    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    Paint rectangle: .paper$, 0, duration_s, .dbFloor, 2

    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    Colour: .grid$
    Line width: 1
    for .d from -40 to 0
        if (.d mod 10) = 0
            Draw line: 0, .d, duration_s, .d
        endif
    endfor

    # Each event as its own envelope, drawn as a filled shape in its width
    # colour. Separating them by event is what the previous single overlaid
    # curve could not do: there, overlapping mixtures merged into one line.
    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    for .e to numEvents
        .t0 = max(0, evStart[.e])
        .t1 = min(duration_s, evEnd[.e])
        .dur = evEnd[.e] - evStart[.e]
        if .t1 > .t0 and .dur > 0
            .w = evWidth[.e]
            if .w = 1
                .col$ = .w1$
            elsif .w = 2
                .col$ = .w2$
            elsif .w = 3
                .col$ = .w3$
            elsif .w = 4
                .col$ = .w4$
            else
                .col$ = .w5$
            endif
            .peakLin = evAmp[.e] / max(1e-9, max_amplitude)
            .nSeg = 24
            .prevT = .t0
            .prevD = .dbFloor
            for .k from 0 to .nSeg
                .u = .k / .nSeg
                .tt = evStart[.e] + .u * .dur
                if evEnv[.e] = 8
                    # Serial: the realised linear-in-dB ramp, in absolute dB.
                    .db = evDb1[.e] + .u * (evDb2[.e] - evDb1[.e])
                else
                    # Random mode: the same five shapes renderMixture applies.
                    .tl = .u * .dur
                    .env = evEnv[.e]
                    if .env = 1
                        .g = min(1, .tl / max(1e-6, min(0.025, .dur * 0.2)), (.dur - .tl) / max(1e-6, min(0.018, .dur * 0.15)))
                    elsif .env = 2
                        .g = min(1, .u / 0.72) * min(1, (.dur - .tl) / 0.01)
                    elsif .env = 3
                        .g = exp(-2.8 * .u) * min(1, .tl / max(1e-6, min(0.004, .dur * 0.08)), (.dur - .tl) / max(1e-6, min(0.012, .dur * 0.15)))
                    elsif .env = 4
                        .g = 1 - abs(2 * .u - 1)
                    elsif .env = 5
                        .g = min(1, .tl / max(1e-6, min(0.003, .dur * 0.08)), (.dur - .tl) / max(1e-6, min(0.006, .dur * 0.12)))
                    elsif .env = 7
                        .g = exp(-3 * (1 - .u)) * .u
                    else
                        .g = exp(-3 * .u) * (1 - .u)
                    endif
                    .g = max(0, .g)
                    .lin = .peakLin * .g
                    if .lin > 1e-4
                        .db = 20 * log10(.lin)
                    else
                        .db = .dbFloor
                    endif
                endif
                if .db < .dbFloor
                    .db = .dbFloor
                endif
                if .tt <= duration_s and .k > 0 and .tt > 0
                    Paint rectangle: .col$, max(0, .prevT), .tt, .dbFloor,
                        ... (.prevD + .db) / 2
                endif
                .prevT = .tt
                .prevD = .db
            endfor
        endif
    endfor

    Select inner viewport: .lo, .hi, 4.66, 6.10
    Axes: 0, duration_s, .dbFloor, 2
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1, 10, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Time (s)"

    # ======================= KEY =======================
    Select inner viewport: 0.60, 7.72, 6.36, 6.72
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "Black"
    Text: 0.0, "left", 0.80, "half", "##TONGEMISCH WIDTH##"
    Font size: 5
    Colour: .faint$
    Text: 0.0, "left", 0.30, "half",
        ... "column C: tones C degrees apart, constant within a sequence"

    Select inner viewport: 2.60, 7.72, 6.36, 6.72
    Axes: 0, 5, 0, 1
    for .w to 5
        if .w = 1
            .col$ = .w1$
            .rn$ = "I"
        elsif .w = 2
            .col$ = .w2$
            .rn$ = "II"
        elsif .w = 3
            .col$ = .w3$
            .rn$ = "III"
        elsif .w = 4
            .col$ = .w4$
            .rn$ = "IV"
        else
            .col$ = .w5$
            .rn$ = "V"
        endif
        Paint rectangle: .col$, .w - 1 + 0.04, .w - 1 + 0.30, 0.42, 0.86
        Colour: .ink$
        Line width: 1
        Draw rectangle: .w - 1 + 0.04, .w - 1 + 0.30, 0.42, 0.86
        Font size: 6
        Colour: "Black"
        Text: .w - 1 + 0.36, "left", 0.64, "half",
            ... .rn$ + " = " + string$(.w) + " step"
        Font size: 5
        Colour: .faint$
        Text: .w - 1 + 0.36, "left", 0.22, "half",
            ... string$(.widthCount[.w]) + " mixtures"
    endfor

    # ======================= FIDELITY / QC =======================
    Select inner viewport: 0.60, 7.72, 6.94, 7.56
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Select inner viewport: 0.60, 7.72, 6.94, 7.56
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.25,0.25,0.25}"
    if generation_mode = 2
        Text: 0.02, "left", 0.80, "half",
            ... "DERIVED  |  squares R1-R5, U1-U5 from 3 5 1 4 2  |  degree = 5(A+B-2) + C(D-1)  |  "
            ... + "61 durations, 61 dB values  |  ghost-duration starts  |  chord accumulation  |  coda"
        .corr$ = if apply_score_corrections then "Part V score corrections on" else "Part V score corrections off" fi
        Text: 0.02, "left", 0.50, "half",
            ... "TRANSCRIBED  |  envelope series of I, II, IV, V and the Part V type table  |  "
            ... + .corr$ + "  |  chamber synthetic (RT60 10 s, wet only)"
    else
        Text: 0.02, "left", 0.80, "half",
            ... "FROM THE SOURCES  |  81 degrees of 5\^ (1/25) from "
            ... + fixed$(freq[1], 0) + " to " + fixed$(freq[81], 0)
            ... + " Hz  |  five-sine mixtures spaced 1-5 scale degrees  |  equal partial levels"
        Text: 0.02, "left", 0.50, "half",
            ... "RANDOM MODE  |  groups, registers, durations and envelopes are random, "
            ... + "not serial  |  sound: 4 cm tape loops through the synthetic 10 s chamber"
    endif
    Text: 0.02, "left", 0.20, "half",
        ... "OUTPUT  |  " + string$(numEvents) + " mixtures  |  span "
        ... + fixed$(duration_s, 2) + " s = tape " + fixed$(winStart * tapeSpeed_cm_s, 0) + " - "
        ... + fixed$((winStart + duration_s) * tapeSpeed_cm_s, 0) + " cm at 76.2 cm/s  |  peak " + fixed$(finalPeak, 3) + "  |  RMS "
        ... + fixed$(finalRMS, 4)

    Select inner viewport: 0.60, 7.72, 6.94, 7.56
    Axes: 0, 1, 0, 1
    Colour: "{0.52,0.52,0.54}"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
    # Leave the whole page selected so Save/Copy exports the full score.
    Select outer viewport: 0, 8, 0, 7.7
endproc
