# ============================================================
# Praat AudioTools - BABBITT'S COMBINATORIAL ARRAYS
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Serial-array synthesizer after the opening of Milton Babbitt's
#   Semi-Simple Variations (1956). Three engines, kept separate:
#
#   SERIAL ENGINE
#     ordered hexachord P -> combinatorial partner Y (I_n or T_k whose image
#     is the complementary hexachord) -> four-line array {P, R, Y, RY}.
#     Because R(P) opens with the reversed last trichord of P, the first
#     trichords of the four lines form one aggregate and the second
#     trichords another (trichordal aggregate control).
#     Opening array:
#       S = P  10 6 11 8 7 9      A = RI  2 4 3 0 5 1
#       T = R   9 7 8 11 6 10     B = I   1 5 0 3 4 2      (I = I11)
#     The opening P uses every interval class 1-5 exactly once between
#     adjacent notes (4 5 3 1 2), and its four contiguous trichords are
#     015 025 014 012 (the "segmental trichords").
#
#   HEXACHORD SOURCES
#     Opening          the hexachord above.
#     Type-A generator chromatic (Type-A, first-order all-combinatorial)
#                      content, ordered so adjacent ICs 1-5 occur once each:
#                      24 orderings per transposition level, enumerated.
#     Any combinatorial any six pcs whose complement is an I or T image.
#
#   SECONDARY SETS (Secondary sets cycle = on)
#     After the opening array, a second cycle gives every line the retrograde
#     of its form transposed by the combinatorial interval (T6 for Type-A
#     content; I_n R when only inversional combinatoriality exists). Each line
#     of cycle 1 followed by its line in cycle 2 is then a 12-tone "secondary
#     set". For the opening, S yields 10 6 11 8 7 9 | 3 1 2 5 0 4, which is the
#     basic set itself; the four secondary forms are RT6, I5, T6, RI5.
#
#   TRICHORD DERIVATION (Derivation cycles > 0)
#     Cycle 1 is the basic array. Each later cycle is built from a segmental
#     trichord g of P: the aggregate is partitioned into g itself plus three
#     further T/I forms of g (a trichord-derived set), assigned to S A T B.
#     The second aggregate of a cycle is the retrograde array of the first
#     (S=R(T) A=R(B) T=R(S) B=R(A)), so T=R(S) and B=R(A) still hold.
#     The first derived cycle is a hybrid (first aggregate from the preceding
#     array, basic or secondary; second aggregate derived); later derived
#     cycles are derived in both aggregates. Plan order:
#     opening array -> secondary sets -> trichord-derived sets. Generators follow the order of
#     the segments in P; a class with no partition (036) is skipped.
#
#   TIME-POINT ENGINE
#     each quarter = 4 sixteenth time points = a 4-bit partition (0..15);
#     an exhaustive ordering of all 16 partitions always yields 32 attacks.
#     Opening order: Z 5 4 X 3 T 9 Y | 7 1 E 6 2 8 W 0
#     (T=10 E=11 W=12 X=13 Y=14 Z=15). Bit convention (assumption): the
#     most significant bit is the first sixteenth of the quarter.
#     With several cycles the rhythm advances one transform per cycle
#     (Original -> Retrograde -> Binary complement -> Retrograde binary
#     complement), or draws a new exhaustive ordering per cycle.
#
#   REARTICULATION
#     32 attacks - 24 array entries = 8 rearticulations per cycle, 4 per
#     aggregate (every 16 attacks form one aggregate).
#       Strict       slots 4/8/12/16 of each aggregate; repeat previous attack
#       Grouped      slots on quarter onsets; repeat previous attack
#       Associative  slots on quarter onsets; the repeated pitch class is
#                    chosen from the current aggregate so that surface
#                    trichords (3 consecutive attacks) fall in a target class.
#                    "Current generator" targets the derived aggregate's own
#                    generator class (segmental classes in basic aggregates).
#
#   SYNTHESIS ENGINE
#     each attack -> fixed-register pitch in its voice band -> small additive
#     spectrum -> attack/decay/release envelope, written with Formula (part).
#     Halo: when a line completes an aggregate trichord, that trichord sounds
#     softly as a chord.
#
#   STRUCTURAL TIMBRE (Timbre = Structural)
#     The spectrum is derived from the array itself. Partial 1 is a fixed
#     anchor; pitch class x owns partial slot x + 2 (partials 2..13). In each
#     cycle every voice takes the six pitch classes of its current line; the
#     slot of the n-th note gets weight 0.55 * (7 - n) / 6, tilted by h^-0.6.
#     So the serial operations act on timbre exactly as on pitch:
#     T_n rotates the emphasised partial set, I_n reflects it, R reverses the
#     order of emphasis, and a combinatorial partner line lights the
#     complementary slots (the two together form a "spectral aggregate").
#     Upper partials decay faster (rate (1 + 0.12 (h-1)) / tau).
#
#   MUSICXML OUTPUT
#     The realized stream is written as a four-part score (S A T B),
#     4/4, divisions = 4 (one sixteenth per time point). Each part is
#     monophonic: notes last their sounding duration, gaps become rests,
#     values that cross a barline or have no single note value are tied.
#     Rearticulations get a parenthesised notehead; every cycle start
#     carries a label with the cycle kind and the line form. Trichord
#     halos and Structural Timbre are sound only and are not notated.
#     Two sinks, one shared line buffer (so they cannot diverge):
#       Keep MusicXML Strings  a Strings object
#                              "musicxml_babbitt_arrays_<preset>", one score
#                              line per string, built in memory (no temp
#                              file, so no Praat 7.0 full-trust gate);
#                              write it out later with "Save as raw text
#                              file..." if needed.
#       Write MusicXML file    (Details) file picker; on Praat 7.0 the
#                              script asks for write permission first.
#
# HONEST SCOPE:
#   "Opening Model" encodes the pitch array, the 16-partition order and the
#   32-attack count from the supplied analysis. The distribution of attacks
#   among the four voices and the placement of the 8 rearticulations are
#   MODEL RULES of this script, not a transcription of the score (a future
#   "Score Realization" preset needs voice assignment and rearticulations
#   taken from the score). "Binary complement" (attack/rest exchange) is not
#   Babbitt's modular time-point inversion. The derivation schedule is this
#   script's reading of trichord-derived sets replacing the basic set, not
#   the actual plan of the later variations. In the video's description of
#   Variations 2-5 each array is derived from a PAIR of segmental trichords
#   with the complementary pair in the associative harmony; this script
#   derives from ONE trichord at a time (a paired mode is future work).
#   The secondary-set cycle follows the described Variation 1 operation
#   (retrograde + tritone) but not its rhythm or register. Structural Timbre
#   is this script's own extension, not a Babbitt technique.
#
# Changelog v0.3.1:
#   - MusicXML output: in-memory Strings object (main form, default on)
#     and optional file (Details), from one shared line buffer, following
#     Formant_to_MusicXML_Chord_Converter v0.4.
#   - FORM ARGUMENT ORDER CHANGED: Keep_MusicXML_Strings is a new LAST
#     field of the main form; existing runScript calls need one more
#     argument.
#   - QC panel reports the MusicXML status and line count.
#
# Changelog v0.3:
#   - Secondary Sets: optional cycle after the opening (Details: "Secondary
#     sets cycle"); every line = combinatorial transposition of its
#     retrograde; QC checks that all four lines form 12-tone sets.
#   - Derivation now follows the preceding array: the hybrid cycle takes its
#     first aggregate from the secondary array when that cycle is present.
#   - Structural Timbre (Timbre option 5): spectrum from the current line
#     form, partial slot = pitch class + 2; new figure panel E shows the
#     spectral rows per cycle and voice.
#   - New presets "Secondary Sets" and "Serial Synthesizer"; "Trichord
#     Derivation" now runs opening -> secondary -> derived (6 cycles).
#   - Form labels of secondary lines are identified against P (T/I/RT/RI).
#
# Changelog v0.2:
#   - Preset 1 renamed "Opening Model"; header separates model from score.
#   - New hexachord source "Type-A generator": chromatic content with
#     adjacent ICs 1-5 each once (the property of the opening ordering).
#     "Any combinatorial" keeps the v0.1 behaviour.
#   - New "Trichord Derivation" preset and Derivation cycles detail:
#     segmental trichords of P generate derived four-line arrays that
#     progressively replace the basic array.
#   - Former "Trichord Projection" renamed "Associative Trichords".
#   - Associative target options now: 015+012, 025+014, Segmental trichords
#     of P (computed, was fixed 015/012/025/014), Current generator.
#   - Rhythm options renamed "Binary complement" / "Retrograde binary
#     complement".
#   - Engine generalized from 2 aggregates to 2 x cycles; figure adds a
#     derivation timeline and aggregate table when cycles > 1; QC reports
#     IC exhaustion, Type-A ordering index and derived-set partitions.
#   - Fixed (v0.1 hotfix, kept): empty T-form list no longer crashes the
#     generator.
# ============================================================

# ============================================================
# COMPACT FORM
# ============================================================
form Babbitt's Combinatorial Arrays v0.3.1
    optionmenu Preset 1
        option Opening Model (Semi-Simple Variations)
        option Type-A Generator
        option Rhythmic Transformations
        option Associative Trichords
        option Secondary Sets
        option Trichord Derivation
        option Serial Synthesizer
        option Free Serial Field
    positive Tempo_bpm 60
    integer Register_centre_MIDI 60
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Keep_MusicXML_Strings 1
endform

# ============================================================
# PRESET DEFAULTS (shown pre-filled in the Details dialog)
# ============================================================
hexachord_source = 1
basic_set_transposition = 0
array_operation = 1
entry_order = 1
derivation_cycles = 0
secondary_sets = 0
rhythm = 1
rearticulation = 2
associative_target = 1
timbre = 2
trichord_halo = 0
register_spread = 10
decay_scale = 1.0
sample_rate = 44100
output_peak = 0.95
random_seed = 0
write_MusicXML_file = 0

if preset = 1
    preset_name$ = "OpeningModel"
    preset_label$ = "Opening Model (Var. 0)"
elsif preset = 2
    preset_name$ = "TypeAGenerator"
    preset_label$ = "Type-A Generator"
    hexachord_source = 2
    entry_order = 2
    rhythm = 5
elsif preset = 3
    preset_name$ = "RhythmicTransformations"
    preset_label$ = "Rhythmic Transformations"
    rhythm = 4
elsif preset = 4
    preset_name$ = "AssociativeTrichords"
    preset_label$ = "Associative Trichords"
    rearticulation = 3
    associative_target = 3
    timbre = 3
    trichord_halo = 1
elsif preset = 5
    preset_name$ = "SecondarySets"
    preset_label$ = "Secondary Sets"
    secondary_sets = 1
elsif preset = 6
    preset_name$ = "TrichordDerivation"
    preset_label$ = "Trichord Derivation"
    secondary_sets = 1
    derivation_cycles = 4
    rearticulation = 3
    associative_target = 4
    trichord_halo = 1
elsif preset = 7
    preset_name$ = "SerialSynthesizer"
    preset_label$ = "Serial Synthesizer"
    secondary_sets = 1
    derivation_cycles = 4
    rearticulation = 3
    associative_target = 4
    timbre = 5
else
    preset_name$ = "FreeSerialField"
    preset_label$ = "Free Serial Field"
    hexachord_source = 3
    array_operation = 5
    entry_order = 2
    rhythm = 5
    rearticulation = 3
    associative_target = 3
    timbre = 4
    trichord_halo = 1
endif

# optionmenu inside beginPause needs Praat 6.3 or newer.
if edit_details
    beginPause: "Babbitt Arrays - Details"
        optionmenu: "Hexachord source", hexachord_source
            option: "Opening hexachord 10 6 11 8 7 9"
            option: "Type-A generator (ICs 1-5 once)"
            option: "Any combinatorial hexachord"
        integer: "Basic set transposition", string$(basic_set_transposition)
        optionmenu: "Array operation", array_operation
            option: "P RI R I (opening array)"
            option: "P I R RI (inversional pair)"
            option: "P Tk R RTk (transpositional pair)"
            option: "P RTk R Tk (retrograde pair)"
            option: "Random valid operation"
        optionmenu: "Entry order", entry_order
            option: "Round robin S A T B"
            option: "Shuffled (line order kept)"
        boolean: "Secondary sets cycle", secondary_sets
        integer: "Derivation cycles (0-7)", string$(derivation_cycles)
        optionmenu: "Rhythm", rhythm
            option: "Original 16 partitions"
            option: "Retrograde (mirrored)"
            option: "Binary complement"
            option: "Retrograde binary complement"
            option: "New exhaustive ordering"
        optionmenu: "Rearticulation", rearticulation
            option: "Strict"
            option: "Grouped (quarter onsets)"
            option: "Associative"
        optionmenu: "Associative target", associative_target
            option: "015 + 012"
            option: "025 + 014"
            option: "Segmental trichords of P"
            option: "Current generator"
        optionmenu: "Timbre", timbre
            option: "Pure"
            option: "Additive"
            option: "Bright"
            option: "Percussive"
            option: "Structural (serial)"
        boolean: "Trichord halo", trichord_halo
        real: "Register spread (st)", string$(register_spread)
        real: "Decay scale", string$(decay_scale)
        integer: "Sample rate (Hz)", string$(sample_rate)
        real: "Output peak", string$(output_peak)
        integer: "Random seed (0 = unpredictable)", string$(random_seed)
        boolean: "Write MusicXML file", write_MusicXML_file
    endPause: "Run", 1
endif

# ============================================================
# VALIDATION
# ============================================================
if tempo_bpm < 20 or tempo_bpm > 300
    exitScript: "Tempo must be between 20 and 300 bpm."
endif
if derivation_cycles < 0 or derivation_cycles > 7
    exitScript: "Derivation cycles must be between 0 and 7."
endif
if register_spread < 0 or register_spread > 18
    exitScript: "Register spread must be between 0 and 18 semitones."
endif
if decay_scale <= 0
    exitScript: "Decay scale must be greater than 0."
endif
if sample_rate < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and at most 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (unpredictable) or a positive integer."
endif
lowest_band = register_centre_MIDI - 1.5 * register_spread - 6
highest_band = register_centre_MIDI + 1.5 * register_spread + 6
if lowest_band < 21 or highest_band > 108
    exitScript: "Voice bands leave the piano range (MIDI 21-108): " + fixed$(lowest_band, 1) + " .. " + fixed$(highest_band, 1) + ". Move the register centre or reduce the spread."
endif

beat = 60 / tempo_bpm
nyquist = sample_rate / 2
transp = ((round(basic_set_transposition) mod 12) + 12) mod 12
n_cyc = 1 + secondary_sets + round(derivation_cycles)
n_agg = 2 * n_cyc
half_att = 16

# Non-seeded UID keeps object names distinct without consuming the seeded sequence.
run_id = randomInteger(100000, 999999)

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# ============================================================
# TABLES
# ============================================================
for c from 0 to 9
    codeChar$[c] = string$(c)
endfor
codeChar$[10] = "T"
codeChar$[11] = "E"
codeChar$[12] = "W"
codeChar$[13] = "X"
codeChar$[14] = "Y"
codeChar$[15] = "Z"

origCode[1] = 15
origCode[2] = 5
origCode[3] = 4
origCode[4] = 13
origCode[5] = 3
origCode[6] = 10
origCode[7] = 9
origCode[8] = 14
origCode[9] = 7
origCode[10] = 1
origCode[11] = 11
origCode[12] = 6
origCode[13] = 2
origCode[14] = 8
origCode[15] = 12
origCode[16] = 0

rhName$[1] = "Original"
rhName$[2] = "Retrograde"
rhName$[3] = "Binary complement"
rhName$[4] = "Retro. binary complement"
rhName$[5] = "New ordering"

# Trichord set classes, coded 10*a + (a+b) from the sorted cyclic intervals.
n_cls = 12
clsCode[1] = 12
clsCode[2] = 13
clsCode[3] = 14
clsCode[4] = 15
clsCode[5] = 16
clsCode[6] = 24
clsCode[7] = 25
clsCode[8] = 26
clsCode[9] = 27
clsCode[10] = 36
clsCode[11] = 37
clsCode[12] = 48
surfCount[0] = 0
anyTarget[0] = 0
for k from 1 to n_cls
    surfCount[clsCode[k]] = 0
    anyTarget[clsCode[k]] = 0
endfor

vName$[1] = "S"
vName$[2] = "A"
vName$[3] = "T"
vName$[4] = "B"
# Retrograde map for the second aggregate of a derived cycle.
dmap[1] = 3
dmap[2] = 4
dmap[3] = 1
dmap[4] = 2

# ============================================================
# SERIAL ENGINE: hexachord
# ============================================================
gen_attempts = 0
typeA_count = 0
typeA_pick = 0
if hexachord_source = 1
    gv_hex[1] = 10
    gv_hex[2] = 6
    gv_hex[3] = 11
    gv_hex[4] = 8
    gv_hex[5] = 7
    gv_hex[6] = 9
elsif hexachord_source = 2
    # Enumerate every ordering of 0..5 whose five adjacent intervals are all
    # different (between distinct pcs of a chromatic hexachord this means
    # ICs 1-5 each once). d6 is implied because the digits sum to 15.
    for d1 from 0 to 5
        for d2 from 0 to 5
            if d2 <> d1
                for d3 from 0 to 5
                    if d3 <> d1 and d3 <> d2
                        for d4 from 0 to 5
                            if d4 <> d1 and d4 <> d2 and d4 <> d3
                                for d5 from 0 to 5
                                    if d5 <> d1 and d5 <> d2 and d5 <> d3 and d5 <> d4
                                        d6 = 15 - d1 - d2 - d3 - d4 - d5
                                        for q from 1 to 5
                                            icUsed[q] = 0
                                        endfor
                                        icUsed[abs(d2 - d1)] = 1
                                        icUsed[abs(d3 - d2)] = 1
                                        icUsed[abs(d4 - d3)] = 1
                                        icUsed[abs(d5 - d4)] = 1
                                        icUsed[abs(d6 - d5)] = 1
                                        if icUsed[1] + icUsed[2] + icUsed[3] + icUsed[4] + icUsed[5] = 5
                                            typeA_count = typeA_count + 1
                                            typeA[typeA_count, 1] = d1
                                            typeA[typeA_count, 2] = d2
                                            typeA[typeA_count, 3] = d3
                                            typeA[typeA_count, 4] = d4
                                            typeA[typeA_count, 5] = d5
                                            typeA[typeA_count, 6] = d6
                                        endif
                                    endif
                                endfor
                            endif
                        endfor
                    endif
                endfor
            endif
        endfor
    endfor
    if typeA_count = 0
        exitScript: "Internal error: no Type-A orderings found."
    endif
    typeA_pick = randomInteger(1, typeA_count)
    content_level = randomInteger(0, 11)
    for k from 1 to 6
        gv_hex[k] = (typeA[typeA_pick, k] + content_level) mod 12
    endfor
else
    found = 0
    while found = 0 and gen_attempts < 5000
        gen_attempts = gen_attempts + 1
        for k from 1 to 12
            perm[k] = k - 1
        endfor
        for k from 1 to 11
            j = randomInteger(k, 12)
            tmp = perm[k]
            perm[k] = perm[j]
            perm[j] = tmp
        endfor
        for k from 1 to 6
            gv_hex[k] = perm[k]
        endfor
        @combCheck
        if array_operation <= 2
            found = comb_nInv > 0
        elsif array_operation <= 4
            found = comb_nTr > 0
        else
            found = (comb_nInv + comb_nTr) > 0
        endif
    endwhile
    if found = 0
        exitScript: "No combinatorial hexachord found for the selected array operation."
    endif
endif

for k from 1 to 6
    gv_hex[k] = (gv_hex[k] + transp) mod 12
    pP[k] = gv_hex[k]
endfor
@combCheck

# Adjacent interval classes of P.
for q from 1 to 6
    icUsed[q] = 0
endfor
ic_list$ = ""
for k from 1 to 5
    dd = ((pP[k + 1] - pP[k]) mod 12 + 12) mod 12
    icv = min(dd, 12 - dd)
    icUsed[icv] = 1
    ic_list$ = ic_list$ + string$(icv) + " "
endfor
all_ic = icUsed[1] + icUsed[2] + icUsed[3] + icUsed[4] + icUsed[5] = 5

# ============================================================
# SERIAL ENGINE: four-line basic array
# ============================================================
op = array_operation
if op = 5
    if comb_nInv > 0 and comb_nTr > 0
        op = randomInteger(1, 4)
    elsif comb_nInv > 0
        op = randomInteger(1, 2)
    else
        op = randomInteger(3, 4)
    endif
endif
if op <= 2 and comb_nInv = 0
    exitScript: "This hexachord is not inversionally combinatorial."
endif
if op >= 3 and comb_nTr = 0
    exitScript: "This hexachord is not transpositionally combinatorial."
endif

# Pick the partner index; index 0 is a safe placeholder when a family is empty.
inv_pick = 0
tr_pick = 0
if comb_nInv > 0
    inv_pick = 1
    if hexachord_source >= 2
        inv_pick = randomInteger(1, comb_nInv)
    endif
endif
if comb_nTr > 0
    tr_pick = 1
    if hexachord_source >= 2
        tr_pick = randomInteger(1, comb_nTr)
    endif
endif
inv_n = comb_inv[inv_pick]
tr_k = comb_tr[tr_pick]

# Picture label uses per-character subscripts (I_1_1); braces are not grouped.
if op <= 2
    y_plain$ = "I" + string$(inv_n)
else
    y_plain$ = "T" + string$(tr_k)
endif
y_label$ = left$(y_plain$, 1)
for k from 2 to length(y_plain$)
    y_label$ = y_label$ + "_" + mid$(y_plain$, k, 1)
endfor

for k from 1 to 6
    if op <= 2
        yY[k] = ((inv_n - pP[k]) mod 12 + 12) mod 12
    else
        yY[k] = (pP[k] + tr_k) mod 12
    endif
endfor
for k from 1 to 6
    line[1, k] = pP[k]
    line[3, k] = pP[7 - k]
    if op = 1 or op = 4
        line[2, k] = yY[7 - k]
        line[4, k] = yY[k]
    else
        line[2, k] = yY[k]
        line[4, k] = yY[7 - k]
    endif
endfor
opLab$[1] = "P"
opLab$[3] = "R"
opPlain$[1] = "P"
opPlain$[3] = "R"
if op = 1 or op = 4
    opLab$[2] = "R" + y_label$
    opLab$[4] = y_label$
    opPlain$[2] = "R" + y_plain$
    opPlain$[4] = y_plain$
else
    opLab$[2] = y_label$
    opLab$[4] = "R" + y_label$
    opPlain$[2] = y_plain$
    opPlain$[4] = "R" + y_plain$
endif
if op = 1
    op_name$ = "P RI R I"
elsif op = 2
    op_name$ = "P I R RI"
elsif op = 3
    op_name$ = "P Tk R RTk"
else
    op_name$ = "P RTk R Tk"
endif

# Discrete trichords of each line.
for v from 1 to 4
    for hh from 1 to 2
        b0 = 3 * hh - 2
        @trichordClass: line[v, b0], line[v, b0 + 1], line[v, b0 + 2]
        triCode[v, hh] = trichordClass.code
    endfor
endfor

# Array bank: 1 = basic array, 2 = secondary array.
for v from 1 to 4
    for k from 1 to 6
        arrLine[1, v, k] = line[v, k]
    endfor
    arrLab$[1, v] = opPlain$[v]
endfor

# ============================================================
# SERIAL ENGINE: secondary sets
# Each line -> combinatorial transposition (or inversion) of its retrograde.
# ============================================================
if comb_nTr > 0
    sec_useT = 1
    sec_n = tr_k
    sec_op$ = "T" + string$(tr_k) + "R"
else
    sec_useT = 0
    sec_n = inv_n
    sec_op$ = "I" + string$(inv_n) + "R"
endif
sec_ok = 0
for v from 1 to 4
    for k from 1 to 6
        src_pc = line[v, 7 - k]
        if sec_useT = 1
            arrLine[2, v, k] = (src_pc + sec_n) mod 12
        else
            arrLine[2, v, k] = ((sec_n - src_pc) mod 12 + 12) mod 12
        endif
        fl_line[k] = arrLine[2, v, k]
    endfor
    @formLabel
    arrLab$[2, v] = formLabel.lab$
    for c from 0 to 11
        seen[c] = 0
    endfor
    for k from 1 to 6
        seen[arrLine[1, v, k]] = 1
        seen[arrLine[2, v, k]] = 1
    endfor
    cnt = 0
    for c from 0 to 11
        cnt = cnt + seen[c]
    endfor
    secSetOk[v] = cnt = 12
    sec_ok = sec_ok + secSetOk[v]
endfor

# Segmental (contiguous) trichords of P: the derivation generators.
seg_label$ = ""
for gi from 1 to 4
    for m from 1 to 3
        segPc[gi, m] = pP[gi + m - 1]
    endfor
    @trichordClass: segPc[gi, 1], segPc[gi, 2], segPc[gi, 3]
    segCode[gi] = trichordClass.code
    seg_label$ = seg_label$ + "0" + string$(segCode[gi]) + " "
endfor

# Aggregate check of the basic array (first trichords / second trichords).
arr_agg_ok = 1
for hh from 1 to 2
    for c from 0 to 11
        seen[c] = 0
    endfor
    for v from 1 to 4
        for k from 3 * hh - 2 to 3 * hh
            seen[line[v, k]] = 1
        endfor
    endfor
    for c from 0 to 11
        if seen[c] = 0
            arr_agg_ok = 0
        endif
    endfor
endfor

# ============================================================
# SERIAL ENGINE: trichord derivation
# ============================================================
derive_random = hexachord_source >= 2 or entry_order = 2
n_valid = 0
deriv_label$ = ""
if derivation_cycles > 0
    for gi from 1 to 4
        @derive: gi
        if dervNSol[gi] > 0
            n_valid = n_valid + 1
            validG[n_valid] = gi
            deriv_label$ = deriv_label$ + "0" + string$(segCode[gi]) + "(" + string$(dervNSet[gi]) + ") "
        else
            deriv_label$ = deriv_label$ + "0" + string$(segCode[gi]) + "(none) "
        endif
    endfor
    if n_valid = 0
        exitScript: "No segmental trichord of this hexachord can partition the aggregate; trichord derivation is impossible here."
    endif
endif

# Plan: cycle 1 basic -> (cycle 2 secondary) -> derived cycles.
n_derived_agg = 0
last_arr = 1 + secondary_sets
for k from 1 to n_cyc
    j1 = 2 * k - 1
    j2 = 2 * k
    cycGen[k] = 0
    d = k - 1 - secondary_sets
    if k = 1
        cycKind$[k] = "basic"
        @aggArray: j1, 1, 1
        @aggArray: j2, 1, 2
    elsif d <= 0
        cycKind$[k] = "secondary"
        @aggArray: j1, 2, 1
        @aggArray: j2, 2, 2
    else
        g = validG[((d - 1) mod n_valid) + 1]
        cycGen[k] = segCode[g]
        cycKind$[k] = "0" + string$(segCode[g])
        if d = 1
            @aggArray: j1, last_arr, 1
            @aggDerived: j2, g, 0
            n_derived_agg = n_derived_agg + 1
        else
            @aggDerived: j1, g, 0
            @aggDerived: j2, g, 1
            n_derived_agg = n_derived_agg + 2
        endif
    endif
endfor

# Target classes per aggregate.
for j from 1 to n_agg
    blkTgt[j, 0] = 0
    for k from 1 to n_cls
        blkTgt[j, clsCode[k]] = 0
    endfor
    if associative_target = 1
        blkTgt[j, 15] = 1
        blkTgt[j, 12] = 1
    elsif associative_target = 2
        blkTgt[j, 25] = 1
        blkTgt[j, 14] = 1
    elsif associative_target = 4 and aggGen[j] > 0
        blkTgt[j, aggGen[j]] = 1
    else
        for gi from 1 to 4
            blkTgt[j, segCode[gi]] = 1
        endfor
    endif
    for k from 1 to n_cls
        if blkTgt[j, clsCode[k]] = 1
            anyTarget[clsCode[k]] = 1
        endif
    endfor
endfor
if associative_target = 1
    target_label$ = "015 012"
elsif associative_target = 2
    target_label$ = "025 014"
elsif associative_target = 3
    target_label$ = "segmental " + seg_label$
else
    target_label$ = "current generator"
endif

# ============================================================
# TIME-POINT ENGINE
# ============================================================
partitions_ok = 0
n_att = 0
for k from 1 to n_cyc
    if rhythm = 5
        cycRh[k] = 5
        for q from 1 to 16
            perm[q] = q - 1
        endfor
        for q from 1 to 15
            j = randomInteger(q, 16)
            tmp = perm[q]
            perm[q] = perm[j]
            perm[j] = tmp
        endfor
    else
        cycRh[k] = ((rhythm - 1 + k - 1) mod 4) + 1
    endif
    for c from 0 to 15
        codeUsed[c] = 0
    endfor
    cyc_att = 0
    for u from 1 to 16
        uu = 16 * (k - 1) + u
        rk = cycRh[k]
        if rk = 1
            code[uu] = origCode[u]
        elsif rk = 2
            @mirror4: origCode[17 - u]
            code[uu] = mirror4.m
        elsif rk = 3
            code[uu] = 15 - origCode[u]
        elsif rk = 4
            @mirror4: origCode[17 - u]
            code[uu] = 15 - mirror4.m
        else
            code[uu] = perm[u]
        endif
        codeUsed[code[uu]] = 1
        for p from 0 to 3
            if (floor(code[uu] / 2 ^ (3 - p)) mod 2) = 1
                n_att = n_att + 1
                cyc_att = cyc_att + 1
                atkBeat[n_att] = (uu - 1) + p / 4
                atkUnit[n_att] = uu
                atkPos[n_att] = p
            endif
        endfor
    endfor
    used = 0
    for c from 0 to 15
        used = used + codeUsed[c]
    endfor
    if used = 16 and cyc_att = 32
        partitions_ok = partitions_ok + 1
    endif
endfor
if n_att <> 32 * n_cyc or partitions_ok <> n_cyc
    exitScript: "Internal error: partition ordering is not exhaustive (" + string$(partitions_ok) + " of " + string$(n_cyc) + " cycles, " + string$(n_att) + " attacks)."
endif
if n_cyc = 1
    rhythm_name$ = rhName$[cycRh[1]]
elsif rhythm = 5
    rhythm_name$ = "New ordering per cycle"
else
    rhythm_name$ = "Rotating from " + rhName$[rhythm]
endif

# ============================================================
# REARTICULATION SLOTS
# ============================================================
for a from 1 to n_att
    isRe[a] = 0
    atkBlk[a] = floor((a - 1) / half_att) + 1
endfor
for blk from 1 to n_agg
    bs = (blk - 1) * half_att
    if rearticulation = 1
        for j from 1 to 4
            isRe[bs + 4 * j] = 1
        endfor
    else
        n_cand = 0
        for lp from 2 to half_att
            if atkPos[bs + lp] = 0
                n_cand = n_cand + 1
                cand[n_cand] = lp
            endif
        endfor
        if n_cand >= 4
            for j from 1 to 4
                ci = floor((j - 0.5) * n_cand / 4) + 1
                isRe[bs + cand[ci]] = 1
            endfor
        else
            chosen = 0
            for j from 1 to n_cand
                isRe[bs + cand[j]] = 1
                chosen = chosen + 1
            endfor
            j = 1
            while chosen < 4
                if isRe[bs + 4 * j] = 0
                    isRe[bs + 4 * j] = 1
                    chosen = chosen + 1
                endif
                j = j + 1
            endwhile
        endif
    endif
endfor

# Entry order: 12 new entries per aggregate, 3 per voice.
for blk from 1 to n_agg
    for i from 1 to 12
        vorder[blk, i] = ((i - 1) mod 4) + 1
    endfor
    if entry_order = 2
        for i from 1 to 11
            j = randomInteger(i, 12)
            tmp = vorder[blk, i]
            vorder[blk, i] = vorder[blk, j]
            vorder[blk, j] = tmp
        endfor
    endif
    newInBlk[blk] = 0
    for v from 1 to 4
        nextPos[blk, v] = 1
    endfor
endfor

# Assign aggregate trichord entries.
for a from 1 to n_att
    blk = atkBlk[a]
    if isRe[a] = 0
        newInBlk[blk] = newInBlk[blk] + 1
        v = vorder[blk, newInBlk[blk]]
        atkVoice[a] = v
        atkIdx[a] = nextPos[blk, v]
        atkPc[a] = aggPc[blk, v, nextPos[blk, v]]
        nextPos[blk, v] = nextPos[blk, v] + 1
    else
        atkVoice[a] = 0
        atkIdx[a] = 0
        atkPc[a] = -1
    endif
endfor

# Resolve rearticulations left to right.
for a from 1 to n_att
    if isRe[a] = 1
        blk = atkBlk[a]
        if rearticulation < 3
            src = a - 1
        else
            bs = (blk - 1) * half_att
            best = -1e9
            src = a - 1
            for b from bs + 1 to a - 1
                if isRe[b] = 0
                    cpc = atkPc[b]
                    score = 0
                    if a - 2 >= 1
                        @trichordClass: atkPc[a - 2], atkPc[a - 1], cpc
                        score = score + blkTgt[blk, trichordClass.code]
                    endif
                    if a + 1 <= n_att
                        if isRe[a + 1] = 0
                            @trichordClass: atkPc[a - 1], cpc, atkPc[a + 1]
                            score = score + blkTgt[blk, trichordClass.code]
                        endif
                    endif
                    if cpc = atkPc[a - 1]
                        score = score - 0.5
                    endif
                    score = score + randomUniform(0, 0.01)
                    if score > best
                        best = score
                        src = b
                    endif
                endif
            endfor
        endif
        atkVoice[a] = atkVoice[src]
        atkIdx[a] = atkIdx[src]
        atkPc[a] = atkPc[src]
    endif
endfor

# Structural checks on the realized stream.
n_agg_ok = 0
for blk from 1 to n_agg
    for c from 0 to 11
        seen[c] = 0
    endfor
    for a from (blk - 1) * half_att + 1 to blk * half_att
        seen[atkPc[a]] = 1
    endfor
    cnt = 0
    for c from 0 to 11
        cnt = cnt + seen[c]
    endfor
    aggFull[blk] = cnt
    if cnt = 12
        n_agg_ok = n_agg_ok + 1
    endif
    blkStart[blk] = atkBeat[(blk - 1) * half_att + 1]
endfor
n_new = 0
n_re = 0
for a from 1 to n_att
    if isRe[a] = 1
        n_re = n_re + 1
    else
        n_new = n_new + 1
    endif
endfor

# Surface trichords (three consecutive attacks); target = middle attack's aggregate.
n_surf = 0
surf_hits = 0
for a from 1 to n_att - 2
    @trichordClass: atkPc[a], atkPc[a + 1], atkPc[a + 2]
    tc = trichordClass.code
    surfCount[tc] = surfCount[tc] + 1
    if tc > 0
        n_surf = n_surf + 1
        surf_hits = surf_hits + blkTgt[atkBlk[a + 1], tc]
    endif
endfor

if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

# ============================================================
# DURATIONS, REGISTER, FREQUENCIES
# ============================================================
for v from 1 to 4
    vc[v] = register_centre_MIDI + (2.5 - v) * register_spread
endfor
max_end_beat = 0
min_midi = 1000
max_midi = -1000
for a from 1 to n_att
    v = atkVoice[a]
    b = a + 1
    nxt = 0
    while nxt = 0 and b <= n_att
        if atkVoice[b] = v
            nxt = b
        endif
        b = b + 1
    endwhile
    if nxt > 0
        atkHold[a] = min(atkBeat[nxt] - atkBeat[a], 2)
    else
        atkHold[a] = 1.5
    endif
    atkMidi[a] = atkPc[a] + 12 * round((vc[v] - atkPc[a]) / 12)
    atkF[a] = 440 * 2 ^ ((atkMidi[a] - 69) / 12)
    if atkBeat[a] + atkHold[a] > max_end_beat
        max_end_beat = atkBeat[a] + atkHold[a]
    endif
    min_midi = min(min_midi, atkMidi[a])
    max_midi = max(max_midi, atkMidi[a])
endfor
if trichord_halo
    max_end_beat = max(max_end_beat, atkBeat[n_att] + 1.5)
endif
master_duration = (max_end_beat + 0.25) * beat

# ============================================================
# SYNTHESIS ENGINE
# ============================================================
n_h = if timbre = 5 then 13 else 8 fi
for v from 1 to 4
    for h from 1 to n_h
        w[v, h] = 0
    endfor
    w[v, 1] = 1
endfor
if timbre = 2
    w[1, 2] = 0.18
    w[1, 3] = 0.08
    w[2, 3] = 0.12
    w[3, 2] = 0.15
    w[3, 4] = 0.06
    w[4, 2] = 0.20
    w[4, 3] = 0.10
    timbre_name$ = "Additive"
elsif timbre = 3
    for v from 1 to 4
        for h from 1 to 6
            w[v, h] = 1 / h ^ 0.9
        endfor
    endfor
    timbre_name$ = "Bright"
elsif timbre = 4
    for v from 1 to 4
        for h from 1 to 6
            w[v, h] = 1 / h
        endfor
    endfor
    timbre_name$ = "Percussive"
elsif timbre = 5
    timbre_name$ = "Structural"
    # Spectral rows from the array: one row per cycle and voice.
    for k from 1 to n_cyc
        for v from 1 to 4
            for h from 1 to 13
                stw[k, v, h] = 0
            endfor
            stw[k, v, 1] = 1
            for q from 1 to 6
                if q <= 3
                    spc = aggPc[2 * k - 1, v, q]
                else
                    spc = aggPc[2 * k, v, q - 3]
                endif
                hh = spc + 2
                stw[k, v, hh] = max(stw[k, v, hh], 0.55 * (7 - q) / 6 / hh ^ 0.6)
            endfor
            stwCent[k, v] = 0
            stwSum = 0
            for h from 1 to 13
                stwCent[k, v] = stwCent[k, v] + h * stw[k, v, h]
                stwSum = stwSum + stw[k, v, h]
            endfor
            stwCent[k, v] = stwCent[k, v] / stwSum
        endfor
    endfor
else
    timbre_name$ = "Pure"
endif
if timbre = 4
    tau = 0.22 * decay_scale
else
    tau = 0.9 * decay_scale
endif
voiceGain[1] = 0.9
voiceGain[2] = 1.0
voiceGain[3] = 1.0
voiceGain[4] = 1.1

if rearticulation = 1
    rearticulation_name$ = "Strict"
elsif rearticulation = 2
    rearticulation_name$ = "Grouped"
else
    rearticulation_name$ = "Associative"
endif
if hexachord_source = 1
    source_name$ = "opening"
elsif hexachord_source = 2
    source_name$ = "Type-A " + string$(typeA_pick) + "/" + string$(typeA_count)
else
    source_name$ = "any comb."
endif

clearinfo
writeInfoLine: "=== Babbitt Combinatorial Arrays v0.3.1 ==="
appendInfoLine: "Preset: ", preset_label$
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed: unpredictable"
endif
if hexachord_source = 2
    appendInfoLine: "Type-A ordering ", typeA_pick, " of ", typeA_count, " (content level ", content_level, " before transposition)"
elsif hexachord_source = 3
    appendInfoLine: "Combinatorial hexachord after ", gen_attempts, " draw(s)"
endif
appendInfoLine: "Adjacent ICs of P: ", ic_list$, if all_ic then "(1-5 each once)" else "(not all-IC)" fi
appendInfoLine: "Segmental trichords of P: ", seg_label$
appendInfoLine: "Basic array ", op_name$, " with Y = ", y_plain$, " | transposition ", transp
for v from 1 to 4
    row$ = vName$[v] + "  " + opPlain$[v] + tab$
    for k from 1 to 6
        row$ = row$ + string$(line[v, k]) + " "
        if k = 3
            row$ = row$ + "| "
        endif
    endfor
    row$ = row$ + tab$ + "0" + string$(triCode[v, 1]) + " / 0" + string$(triCode[v, 2])
    appendInfoLine: row$
endfor
if secondary_sets
    appendInfoLine: "Secondary array (", sec_op$, " of each line); lines forming 12-tone sets: ", sec_ok, "/4"
    for v from 1 to 4
        row$ = vName$[v] + "  " + arrLab$[2, v] + tab$
        for k from 1 to 6
            row$ = row$ + string$(arrLine[2, v, k]) + " "
        endfor
        row$ = row$ + tab$ + "secondary set: "
        for k from 1 to 6
            row$ = row$ + string$(arrLine[1, v, k]) + " "
        endfor
        row$ = row$ + "| "
        for k from 1 to 6
            row$ = row$ + string$(arrLine[2, v, k]) + " "
        endfor
        appendInfoLine: row$
    endfor
endif
if derivation_cycles > 0
    appendInfoLine: "Derived-set partitions per generator (distinct sets): ", deriv_label$
endif
if n_cyc > 1
    appendInfoLine: "Aggregate schedule:"
    for j from 1 to n_agg
        row$ = "  agg " + string$(j) + tab$ + aggSrc$[j] + tab$
        for v from 1 to 4
            row$ = row$ + vName$[v] + " " + string$(aggPc[j, v, 1]) + " " + string$(aggPc[j, v, 2]) + " " + string$(aggPc[j, v, 3]) + " (" + aggLab$[j, v] + ")  "
        endfor
        appendInfoLine: row$
    endfor
endif
for k from 1 to n_cyc
    row$ = "Cycle " + string$(k) + " [" + cycKind$[k] + "] partitions (" + rhName$[cycRh[k]] + "): "
    for u from 1 to 16
        row$ = row$ + codeChar$[code[16 * (k - 1) + u]] + " "
        if u = 8
            row$ = row$ + "| "
        endif
    endfor
    appendInfoLine: row$
endfor
appendInfoLine: "Attacks ", n_att, " = ", n_new, " entries + ", n_re, " rearticulations (", rearticulation_name$, ")"

master_name$ = "BabbittArrays_" + preset_name$ + "_" + string$(run_id)
Create Sound from formula: master_name$, 1, 0, master_duration, sample_rate, "0"
master_id = selected("Sound")

dropped_partials = 0
max_partial = 0
n_halo = 0
for a from 1 to n_att
    v = atkVoice[a]
    blk = atkBlk[a]
    f0 = atkF[a]
    t0 = atkBeat[a] * beat
    t1 = t0 + atkHold[a] * beat
    rel = min(0.015, 0.3 * (t1 - t0))
    rel_start = t1 - rel
    t0$ = fixed$(t0, 6)
    accent = 1
    if rearticulation > 1 and atkPos[a] = 0
        accent = 1.15
    endif
    if isRe[a] = 1
        accent = 0.8
    endif
    cy = floor((blk - 1) / 2) + 1
    sum_w = 0
    harm$ = ""
    for h from 1 to n_h
        if timbre = 5
            wh = stw[cy, v, h]
        else
            wh = w[v, h]
        endif
        if wh > 0
            if h * f0 < 0.45 * sample_rate
                sum_w = sum_w + wh
                max_partial = max(max_partial, h * f0)
                sin$ = "sin(" + fixed$(2 * pi * h * f0, 6) + "*(x-" + t0$ + "))"
                if timbre = 4
                    harm$ = harm$ + "+" + fixed$(wh, 5) + "*exp(-" + fixed$(h / tau, 5) + "*(x-" + t0$ + "))*" + sin$
                elsif timbre = 5
                    harm$ = harm$ + "+" + fixed$(wh, 5) + "*exp(-" + fixed$((1 + 0.12 * (h - 1)) / tau, 5) + "*(x-" + t0$ + "))*" + sin$
                else
                    harm$ = harm$ + "+" + fixed$(wh, 5) + "*" + sin$
                endif
            else
                dropped_partials = dropped_partials + 1
            endif
        endif
    endfor
    amp = 0.22 * voiceGain[v] * accent / max(sum_w, 1e-9)
    relf$ = "(if x > " + fixed$(rel_start, 6) + " then 0.5+0.5*cos(pi*(x-" + fixed$(rel_start, 6) + ")/" + fixed$(rel, 6) + ") else 1 fi)"
    if timbre = 4
        env$ = "min(1,(x-" + t0$ + ")/0.003)*" + relf$
    elsif timbre = 5
        env$ = "min(1,(x-" + t0$ + ")/0.006)*" + relf$
    else
        env$ = "min(1,(x-" + t0$ + ")/0.006)*exp(-(x-" + t0$ + ")/" + fixed$(tau, 5) + ")*" + relf$
    endif
    Formula (part): t0, t1, 1, 1, "self + " + fixed$(amp, 6) + "*" + env$ + "*(0" + harm$ + ")"

    # Trichord halo: when a line completes its trichord in this aggregate.
    if trichord_halo and isRe[a] = 0 and atkIdx[a] = 3
        n_halo = n_halo + 1
        haloVoice[n_halo] = v
        haloBeat[n_halo] = atkBeat[a]
        h_dur = min(1.5 * beat, master_duration - t0 - 0.001)
        haloDurBeat[n_halo] = h_dur / beat
        chord$ = ""
        for kk from 1 to 3
            hpc = aggPc[blk, v, kk]
            hmidi = hpc + 12 * round((vc[v] - hpc) / 12)
            hf = 440 * 2 ^ ((hmidi - 69) / 12)
            chord$ = chord$ + "+sin(" + fixed$(2 * pi * hf, 6) + "*(x-" + t0$ + "))"
        endfor
        Formula (part): t0, t0 + h_dur, 1, 1, "self + 0.07*sin(pi*(x-" + t0$ + ")/" + fixed$(h_dur, 6) + ")^2*(0" + chord$ + ")"
    endif
endfor

# ============================================================
# FINALIZE / QC
# ============================================================
selectObject: master_id
pre_norm_peak = Get absolute extremum: 0, 0, "None"
if pre_norm_peak > 0
    Scale peak: output_peak
endif
Rename: "babbitt_arrays_" + preset_name$
master_id = selected("Sound")
final_peak = Get absolute extremum: 0, 0, "None"
final_rms = Get root-mean-square: 0, 0

appendInfoLine: "Aggregates complete: ", n_agg_ok, " of ", n_agg, " | cycles with exhaustive partitions: ", partitions_ok, " of ", n_cyc
appendInfoLine: "Surface trichords in target (", target_label$, "): ", surf_hits, " of ", n_surf
appendInfoLine: "Timbre ", timbre_name$, " | halos ", n_halo, " | dropped partials ", dropped_partials
appendInfoLine: "MIDI range ", min_midi, "..", max_midi, " | max partial ", fixed$(max_partial, 0), " Hz"
appendInfoLine: "Duration ", fixed$(master_duration, 3), " s | peak/RMS ", fixed$(final_peak, 4), " / ", fixed$(final_rms, 4)
appendInfoLine: ""
appendInfoLine: "a", tab$, "beat", tab$, "agg", tab$, "voice", tab$, "pc", tab$, "midi", tab$, "type"
for a from 1 to n_att
    type$ = if isRe[a] = 1 then "re" else "entry " + string$(atkIdx[a]) fi
    appendInfoLine: a, tab$, fixed$(atkBeat[a], 2), tab$, atkBlk[a], tab$, vName$[atkVoice[a]], tab$, atkPc[a], tab$, atkMidi[a], tab$, type$
endfor

# ============================================================
# MUSICXML (in-memory Strings object and/or file)
# ============================================================
xmlPath$ = ""
writeXmlActual = 0
xml_note$ = ""
if write_MusicXML_file
    xmlPath$ = chooseWriteFile$: "Save MusicXML as...", "babbitt_arrays_" + preset_name$ + ".musicxml"
    if xmlPath$ <> ""
        writeXmlActual = 1
        # Praat 7.0 gates file writing; the guard keeps 6.x from
        # ever evaluating askForTrust, which it does not know.
        if praatVersion >= 7000
            trust_ok = askForTrust ()
            if trust_ok = 0
                writeXmlActual = 0
                xml_note$ = " (file refused: no write permission)"
            endif
        endif
    else
        xml_note$ = " (file picker cancelled)"
    endif
endif
buildXml = writeXmlActual or keep_MusicXML_Strings
xmlStringsId = 0
xmlStringsName$ = ""
nXmlLines = 0
xml$ = ""
if buildXml
    @buildMusicXml
    if writeXmlActual
        writeFile: xmlPath$, xml$
        appendInfoLine: "MusicXML file written: ", xmlPath$, " (", length(xml$), " bytes, ", nXmlLines, " lines)"
    endif
    # Created from a one-token Strings so the first line can be written
    # with "Set string" and the rest appended with "Insert string: 0"
    # (0 = at the end). No temporary file is involved.
    if keep_MusicXML_Strings
        xmlStringsId = Create Strings as tokens: "placeholder", " "
        Set string: 1, xmlLine$[1]
        for lineNo from 2 to nXmlLines
            Insert string: 0, xmlLine$[lineNo]
        endfor
        Rename: "musicxml_babbitt_arrays_" + preset_name$
        xmlStringsName$ = selected$("Strings")
        appendInfoLine: "MusicXML kept as Strings object """, xmlStringsName$, """ (", nXmlLines, " strings, ", xml_measures, " measures x 4 parts)"
    endif
endif
if writeXmlActual and xmlStringsId <> 0
    xmlStatus$ = "file+Strings"
elsif writeXmlActual
    xmlStatus$ = "file"
elsif xmlStringsId <> 0
    xmlStatus$ = "Strings"
else
    xmlStatus$ = "skipped"
endif
if xml_note$ <> ""
    appendInfoLine: "MusicXML note:", xml_note$
endif

if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: master_id
    Play
endif

selectObject: master_id
appendInfoLine: "Done. Created Sound: ", selected$("Sound")

# ==============================================================================
# Procedures: serial helpers (globals only; no dotted interpolation)
# ==============================================================================
procedure combCheck
    for .c from 0 to 11
        comb_in[.c] = 0
    endfor
    for .k from 1 to 6
        comb_in[gv_hex[.k]] = 1
    endfor
    comb_nInv = 0
    for .n from 0 to 11
        .ok = 1
        for .k from 1 to 6
            .img = ((.n - gv_hex[.k]) mod 12 + 12) mod 12
            if comb_in[.img] = 1
                .ok = 0
            endif
        endfor
        if .ok = 1
            comb_nInv = comb_nInv + 1
            comb_inv[comb_nInv] = .n
        endif
    endfor
    comb_nTr = 0
    for .t from 1 to 11
        .ok = 1
        for .k from 1 to 6
            .img = (gv_hex[.k] + .t) mod 12
            if comb_in[.img] = 1
                .ok = 0
            endif
        endfor
        if .ok = 1
            comb_nTr = comb_nTr + 1
            comb_tr[comb_nTr] = .t
        endif
    endfor
    comb_inv[0] = 0
    comb_tr[0] = 0
endproc

procedure trichordClass: .p1, .p2, .p3
    .code = 0
    if .p1 >= 0 and .p2 >= 0 and .p3 >= 0
        if .p1 <> .p2 and .p1 <> .p3 and .p2 <> .p3
            .a = min(.p1, .p2, .p3)
            .c = max(.p1, .p2, .p3)
            .b = .p1 + .p2 + .p3 - .a - .c
            .i1 = .b - .a
            .i2 = .c - .b
            .i3 = 12 - (.c - .a)
            .lo = min(.i1, .i2, .i3)
            .hi = max(.i1, .i2, .i3)
            .mid = .i1 + .i2 + .i3 - .lo - .hi
            .code = 10 * .lo + (.lo + .mid)
        endif
    endif
endproc

procedure mirror4: .c
    .m = 0
    for .p from 0 to 3
        .bit = floor(.c / 2 ^ (3 - .p)) mod 2
        .m = .m + .bit * 2 ^ .p
    endfor
endproc

procedure formsDisjoint: .fa, .fb
    .res = 1
    for .x from 1 to 3
        for .y from 1 to 3
            if dv_form[.fa, .x] = dv_form[.fb, .y]
                .res = 0
            endif
        endfor
    endfor
endproc

# Trichord-derived set for segmental generator .gi: the generator itself
# plus three disjoint T/I forms of it that complete the aggregate.
procedure derive: .gi
    for .n from 0 to 11
        for .m from 1 to 3
            dv_form[.n + 1, .m] = (segPc[.gi, .m] + .n) mod 12
            dv_form[.n + 13, .m] = ((.n - segPc[.gi, .m]) mod 12 + 12) mod 12
        endfor
        dv_mask[.n + 1] = 2 ^ dv_form[.n + 1, 1] + 2 ^ dv_form[.n + 1, 2] + 2 ^ dv_form[.n + 1, 3]
        dv_mask[.n + 13] = 2 ^ dv_form[.n + 13, 1] + 2 ^ dv_form[.n + 13, 2] + 2 ^ dv_form[.n + 13, 3]
    endfor
    for .c from 0 to 11
        dv_inG[.c] = 0
    endfor
    for .m from 1 to 3
        dv_inG[segPc[.gi, .m]] = 1
    endfor
    .nL = 0
    for .f from 1 to 24
        .ok = 1
        for .m from 1 to 3
            if dv_inG[dv_form[.f, .m]] = 1
                .ok = 0
            endif
        endfor
        if .ok = 1
            .nL = .nL + 1
            dv_L[.nL] = .f
        endif
    endfor
    dv_nSol = 0
    dv_nSet = 0
    for .i from 1 to .nL - 2
        for .j from .i + 1 to .nL - 1
            @formsDisjoint: dv_L[.i], dv_L[.j]
            if formsDisjoint.res = 1
                for .k from .j + 1 to .nL
                    @formsDisjoint: dv_L[.i], dv_L[.k]
                    .d1 = formsDisjoint.res
                    @formsDisjoint: dv_L[.j], dv_L[.k]
                    if .d1 = 1 and formsDisjoint.res = 1
                        dv_nSol = dv_nSol + 1
                        dv_sol[dv_nSol, 1] = dv_L[.i]
                        dv_sol[dv_nSol, 2] = dv_L[.j]
                        dv_sol[dv_nSol, 3] = dv_L[.k]
                        # distinct pc-set partitions (T and I forms of a
                        # symmetric trichord can be the same set)
                        .ma = dv_mask[dv_L[.i]]
                        .mb = dv_mask[dv_L[.j]]
                        .mc = dv_mask[dv_L[.k]]
                        .sig$ = string$(min(.ma, .mb, .mc)) + "-" + string$(max(.ma, .mb, .mc))
                        .new = 1
                        for .q from 1 to dv_nSet
                            if dv_sig$[.q] = .sig$
                                .new = 0
                            endif
                        endfor
                        if .new = 1
                            dv_nSet = dv_nSet + 1
                            dv_sig$[dv_nSet] = .sig$
                        endif
                    endif
                endfor
            endif
        endfor
    endfor
    dervNSol[.gi] = dv_nSol
    dervNSet[.gi] = dv_nSet
    if dv_nSol > 0
        .pick = 1
        if derive_random
            .pick = randomInteger(1, dv_nSol)
        endif
        for .s from 1 to 3
            .ord[.s] = .s
        endfor
        if derive_random
            for .s from 1 to 2
                .r = randomInteger(.s, 3)
                .tmp = .ord[.s]
                .ord[.s] = .ord[.r]
                .ord[.r] = .tmp
            endfor
        endif
        for .m from 1 to 3
            dervPc[.gi, 1, .m] = segPc[.gi, .m]
        endfor
        dervLab$[.gi, 1] = "T0"
        for .s from 1 to 3
            .f = dv_sol[.pick, .ord[.s]]
            for .m from 1 to 3
                dervPc[.gi, .s + 1, .m] = dv_form[.f, .m]
            endfor
            if .f <= 12
                dervLab$[.gi, .s + 1] = "T" + string$(.f - 1)
            else
                dervLab$[.gi, .s + 1] = "I" + string$(.f - 13)
            endif
        endfor
    endif
endproc

procedure aggArray: .j, .arr, .half
    for .v from 1 to 4
        for .m from 1 to 3
            aggPc[.j, .v, .m] = arrLine[.arr, .v, 3 * (.half - 1) + .m]
        endfor
        aggLab$[.j, .v] = arrLab$[.arr, .v]
    endfor
    aggGen[.j] = 0
    aggGenIdx[.j] = 0
    aggArr[.j] = .arr
    if .arr = 1
        aggSrcShort$[.j] = "P" + string$(.half)
        aggSrc$[.j] = "basic array, trichords " + string$(.half)
    else
        aggSrcShort$[.j] = "Sec" + string$(.half)
        aggSrc$[.j] = "secondary array (" + sec_op$ + "), trichords " + string$(.half)
    endif
endproc

# Identify a six-note line as T_n / I_n / RT_n / RI_n of P (reads fl_line[]).
procedure formLabel
    .lab$ = "?"
    for .n from 0 to 11
        .t = 1
        .i = 1
        .rt = 1
        .ri = 1
        for .k from 1 to 6
            if fl_line[.k] <> (pP[.k] + .n) mod 12
                .t = 0
            endif
            if fl_line[.k] <> ((.n - pP[.k]) mod 12 + 12) mod 12
                .i = 0
            endif
            if fl_line[.k] <> (pP[7 - .k] + .n) mod 12
                .rt = 0
            endif
            if fl_line[.k] <> ((.n - pP[7 - .k]) mod 12 + 12) mod 12
                .ri = 0
            endif
        endfor
        if .t = 1
            .lab$ = if .n = 0 then "P" else "T" + string$(.n) fi
        elsif .i = 1
            .lab$ = "I" + string$(.n)
        elsif .rt = 1
            .lab$ = if .n = 0 then "R" else "RT" + string$(.n) fi
        elsif .ri = 1
            .lab$ = "RI" + string$(.n)
        endif
    endfor
endproc

procedure aggDerived: .j, .gi, .even
    for .v from 1 to 4
        if .even = 0
            for .m from 1 to 3
                aggPc[.j, .v, .m] = dervPc[.gi, .v, .m]
            endfor
            aggLab$[.j, .v] = dervLab$[.gi, .v]
        else
            .sv = dmap[.v]
            for .m from 1 to 3
                aggPc[.j, .v, .m] = dervPc[.gi, .sv, 4 - .m]
            endfor
            aggLab$[.j, .v] = "R" + dervLab$[.gi, .sv]
        endif
    endfor
    aggGen[.j] = segCode[.gi]
    aggGenIdx[.j] = .gi
    aggArr[.j] = 0
    if .even = 0
        aggSrcShort$[.j] = "0" + string$(segCode[.gi])
    else
        aggSrcShort$[.j] = "R 0" + string$(segCode[.gi])
    endif
    aggSrc$[.j] = "derived from 0" + string$(segCode[.gi]) + " (segment " + string$(.gi) + ")"
endproc

# ==============================================================================
# Procedures: MusicXML writer (globals only; no dotted interpolation)
# ==============================================================================
# One score line in, two sinks out: stored as its own array element (for the
# Strings object) and, when a file is wanted, appended to the flat text.
procedure xmlAdd: .line$
    nXmlLines = nXmlLines + 1
    xmlLine$[nXmlLines] = .line$
    if writeXmlActual
        xml$ = xml$ + .line$ + newline$
    endif
endproc

procedure xmlEscape: .s$
    .out$ = replace$(.s$, "&", "&amp;", 0)
    .out$ = replace$(.out$, "<", "&lt;", 0)
    .out$ = replace$(.out$, ">", "&gt;", 0)
endproc

procedure buildMusicXml
    xm_step$[0] = "C"
    xm_step$[1] = "C"
    xm_step$[2] = "D"
    xm_step$[3] = "D"
    xm_step$[4] = "E"
    xm_step$[5] = "F"
    xm_step$[6] = "F"
    xm_step$[7] = "G"
    xm_step$[8] = "G"
    xm_step$[9] = "A"
    xm_step$[10] = "A"
    xm_step$[11] = "B"
    for .c from 0 to 11
        xm_alter[.c] = 0
    endfor
    xm_alter[1] = 1
    xm_alter[3] = 1
    xm_alter[6] = 1
    xm_alter[8] = 1
    xm_alter[10] = 1
    # diatonic step index for measure-scoped accidental memory
    xm_stepIdx[0] = 0
    xm_stepIdx[1] = 0
    xm_stepIdx[2] = 1
    xm_stepIdx[3] = 1
    xm_stepIdx[4] = 2
    xm_stepIdx[5] = 3
    xm_stepIdx[6] = 3
    xm_stepIdx[7] = 4
    xm_stepIdx[8] = 4
    xm_stepIdx[9] = 5
    xm_stepIdx[10] = 5
    xm_stepIdx[11] = 6
    for .key from 0 to 79
        xm_accStamp[.key] = -1
        xm_accVal[.key] = 0
    endfor
    # note values in sixteenths, largest first
    xm_val[1] = 16
    xm_val[2] = 12
    xm_val[3] = 8
    xm_val[4] = 6
    xm_val[5] = 4
    xm_val[6] = 3
    xm_val[7] = 2
    xm_val[8] = 1
    xm_type$[16] = "whole"
    xm_type$[12] = "half"
    xm_type$[8] = "half"
    xm_type$[6] = "quarter"
    xm_type$[4] = "quarter"
    xm_type$[3] = "eighth"
    xm_type$[2] = "eighth"
    xm_type$[1] = "16th"
    for .q from 1 to 8
        xm_dot[xm_val[.q]] = 0
    endfor
    xm_dot[12] = 1
    xm_dot[6] = 1
    xm_dot[3] = 1

    .end16 = 0
    for .a from 1 to n_att
        .end16 = max(.end16, round(atkBeat[.a] * 4) + round(atkHold[.a] * 4))
    endfor
    xml_measures = max(4 * n_cyc, ceiling(.end16 / 16))

    @xmlEscape: preset_label$
    .title$ = xmlEscape.out$
    @xmlAdd: "<?xml version=""1.0"" encoding=""UTF-8""?>"
    @xmlAdd: "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">"
    @xmlAdd: "<score-partwise version=""3.1"">"
    # ASCII only: Praat writes non-ASCII text files as UTF-16, which would
    # contradict the UTF-8 declaration, so typographic marks are entities.
    @xmlAdd: "  <work><work-title>Babbitt&#8217;s Combinatorial Arrays &#8212; " + .title$ + "</work-title></work>"
    @xmlAdd: "  <identification><creator type=""software"">Praat AudioTools - Babbitt Combinatorial Arrays v0.3.1</creator></identification>"
    @xmlAdd: "  <part-list>"
    xm_name$[1] = "Soprano"
    xm_name$[2] = "Alto"
    xm_name$[3] = "Tenor"
    xm_name$[4] = "Bass"
    for .v from 1 to 4
        @xmlAdd: "    <score-part id=""P" + string$(.v) + """><part-name>" + xm_name$[.v] + " (" + arrLab$[1, .v] + ")</part-name><part-abbreviation>" + vName$[.v] + "</part-abbreviation></score-part>"
    endfor
    @xmlAdd: "  </part-list>"

    for .v from 1 to 4
        xm_voice = .v
        xm_meas = 0
        for .key from 0 to 79
            xm_accStamp[.key] = -1
        endfor
        @xmlAdd: "  <part id=""P" + string$(.v) + """>"
        .pos = 0
        for .a from 1 to n_att
            if atkVoice[.a] = .v
                .s16 = round(atkBeat[.a] * 4)
                .l16 = round(atkHold[.a] * 4)
                if .s16 > .pos
                    @xmSpan: 0, 0, .pos, .s16, 0
                endif
                @xmSpan: 1, atkMidi[.a], .s16, .s16 + .l16, isRe[.a]
                .pos = .s16 + .l16
            endif
        endfor
        if .pos < 16 * xml_measures
            @xmSpan: 0, 0, .pos, 16 * xml_measures, 0
        endif
        @xmlAdd: "    </measure>"
        @xmlAdd: "  </part>"
    endfor
    @xmlAdd: "</score-partwise>"
endproc

procedure xmOpenMeasure
    xm_meas = xm_meas + 1
    @xmlAdd: "    <measure number=""" + string$(xm_meas) + """>"
    if xm_meas = 1
        if vc[xm_voice] >= 60
            .clef$ = "<clef><sign>G</sign><line>2</line></clef>"
        else
            .clef$ = "<clef><sign>F</sign><line>4</line></clef>"
        endif
        @xmlAdd: "      <attributes><divisions>4</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time>" + .clef$ + "</attributes>"
        if xm_voice = 1
            @xmlAdd: "      <direction placement=""above""><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>" + fixed$(tempo_bpm, 0) + "</per-minute></metronome></direction-type><sound tempo=""" + fixed$(tempo_bpm, 0) + """/></direction>"
        endif
    endif
    # cycle label (a cycle is 16 quarters = 4 measures)
    if ((xm_meas - 1) mod 4) = 0
        .k = (xm_meas - 1) / 4 + 1
        if .k <= n_cyc
            .lab$ = aggLab$[2 * .k - 1, xm_voice]
            if xm_voice = 1
                .lab$ = "c" + string$(.k) + " " + cycKind$[.k] + " &#8212; " + .lab$
            endif
            @xmlAdd: "      <direction placement=""above""><direction-type><words>" + .lab$ + "</words></direction-type></direction>"
        endif
    endif
endproc

procedure xmEnsureMeasure: .pos
    .need = floor(.pos / 16) + 1
    while xm_meas < .need
        if xm_meas > 0
            @xmlAdd: "    </measure>"
        endif
        @xmOpenMeasure
    endwhile
endproc

# A note or rest from .from to .to (sixteenths), split at barlines and into
# single note values; note pieces are tied.
procedure xmSpan: .isNote, .midi, .from, .to, .paren
    .cur = .from
    while .cur < .to
        @xmEnsureMeasure: .cur
        .barEnd = (floor(.cur / 16) + 1) * 16
        .rem = min(.to, .barEnd) - .cur
        .chunk = 0
        for .q from 1 to 8
            if .chunk = 0 and xm_val[.q] <= .rem
                .chunk = xm_val[.q]
            endif
        endfor
        .tStop = 0
        .tStart = 0
        .pz = 0
        if .isNote
            .tStop = .cur > .from
            .tStart = .cur + .chunk < .to
            .pz = .paren and .cur = .from
        endif
        @xmNote: .isNote, .midi, .chunk, .tStart, .tStop, .pz
        .cur = .cur + .chunk
    endwhile
endproc

procedure xmNote: .isNote, .midi, .dur, .tStart, .tStop, .paren
    @xmlAdd: "      <note>"
    if .isNote
        .pc = .midi mod 12
        .line$ = "        <pitch><step>" + xm_step$[.pc] + "</step>"
        if xm_alter[.pc] <> 0
            .line$ = .line$ + "<alter>1</alter>"
        endif
        .line$ = .line$ + "<octave>" + string$(floor(.midi / 12) - 1) + "</octave></pitch>"
    else
        .line$ = "        <rest/>"
    endif
    @xmlAdd: .line$
    .line$ = "        <duration>" + string$(.dur) + "</duration>"
    if .tStop
        .line$ = .line$ + "<tie type=""stop""/>"
    endif
    if .tStart
        .line$ = .line$ + "<tie type=""start""/>"
    endif
    .line$ = .line$ + "<voice>1</voice><type>" + xm_type$[.dur] + "</type>"
    if xm_dot[.dur] = 1
        .line$ = .line$ + "<dot/>"
    endif
    # Accidentals are scoped to the measure (no key signature): show one when
    # the alteration differs from the last one written for this step and
    # octave in this measure. Tie continuations show none and leave the
    # state alone, so a later re-attack in the new bar is spelled again.
    if .isNote and .tStop = 0
        .key = xm_stepIdx[.pc] * 10 + floor(.midi / 12)
        .prev = 0
        if xm_accStamp[.key] = xm_meas
            .prev = xm_accVal[.key]
        endif
        if xm_alter[.pc] <> .prev
            if xm_alter[.pc] = 1
                .line$ = .line$ + "<accidental>sharp</accidental>"
            else
                .line$ = .line$ + "<accidental>natural</accidental>"
            endif
        endif
        xm_accStamp[.key] = xm_meas
        xm_accVal[.key] = xm_alter[.pc]
    endif
    if .paren
        .line$ = .line$ + "<notehead parentheses=""yes"">normal</notehead>"
    endif
    @xmlAdd: .line$
    if .tStart or .tStop
        .line$ = "        <notations>"
        if .tStop
            .line$ = .line$ + "<tied type=""stop""/>"
        endif
        if .tStart
            .line$ = .line$ + "<tied type=""start""/>"
        endif
        @xmlAdd: .line$ + "</notations>"
    endif
    @xmlAdd: "      </note>"
endproc

# ==============================================================================
# Procedures: drawing frame helpers
# Font is set BEFORE the viewport; every Text re-selects the panel first.
# ==============================================================================
procedure frame
    Font size: pf_font
    Select inner viewport: pf_l, pf_r, pf_b, pf_t
    Axes: pf_x0, pf_x1, pf_y0, pf_y1
endproc

procedure setPanel: .l, .r, .b, .t, .x0, .x1, .y0, .y1, .font
    pf_l = .l
    pf_r = .r
    pf_b = .b
    pf_t = .t
    pf_x0 = .x0
    pf_x1 = .x1
    pf_y0 = .y0
    pf_y1 = .y1
    pf_font = .font
    @frame
endproc

procedure label: .x, .h$, .y, .v$, .s$
    @frame
    Text: .x, .h$, .y, .v$, .s$
endproc

procedure strip: .l, .r, .b, .t, .size, .x, .h$, .s$
    @setPanel: .l, .r, .b, .t, 0, 1, 0, 1, .size
    Text: .x, .h$, 0.5, "half", .s$
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    col$[1] = "{0.20, 0.40, 0.80}"
    col$[2] = "{0.85, 0.40, 0.15}"
    col$[3] = "{0.15, 0.58, 0.35}"
    col$[4] = "{0.55, 0.25, 0.65}"
    tint$[1] = "{0.80, 0.86, 0.96}"
    tint$[2] = "{0.98, 0.86, 0.78}"
    tint$[3] = "{0.80, 0.92, 0.84}"
    tint$[4] = "{0.90, 0.83, 0.94}"
    genTint$[1] = "{0.90, 0.85, 0.97}"
    genTint$[2] = "{0.84, 0.94, 0.89}"
    genTint$[3] = "{0.98, 0.87, 0.84}"
    genTint$[4] = "{0.95, 0.93, 0.78}"
    .agg1$ = "{0.95, 0.96, 0.99}"
    .agg2$ = "{0.99, 0.97, 0.93}"
    .sec1$ = "{0.88, 0.96, 0.97}"
    .sec2$ = "{0.97, 0.91, 0.95}"
    .bnd$ = "{0.70, 0.15, 0.15}"
    .grid$ = "{0.86, 0.86, 0.86}"
    rhShort$[1] = "Orig."
    rhShort$[2] = "Retro."
    rhShort$[3] = "Bin. compl."
    rhShort$[4] = "Retro. bin. compl."
    rhShort$[5] = "New order"
    .multi = n_cyc > 1
    .xMax = ceiling((max_end_beat + 0.25) * 2) / 2
    .xPerInch = .xMax / 7.1
    for .j from 1 to n_agg
        if aggGen[.j] > 0
            aggTint$[.j] = genTint$[aggGenIdx[.j]]
        elsif aggArr[.j] = 2
            aggTint$[.j] = if (.j mod 2) = 1 then .sec1$ else .sec2$ fi
        elsif (.j mod 2) = 1
            aggTint$[.j] = .agg1$
        else
            aggTint$[.j] = .agg2$
        endif
        .tx0[.j] = if .j = 1 then 0 else blkStart[.j] fi
    endfor
    for .j from 1 to n_agg
        .tx1[.j] = if .j = n_agg then .xMax else blkStart[.j + 1] fi
    endfor
    if .xMax <= 20
        .tick = 2
    elsif .xMax <= 40
        .tick = 4
    elsif .xMax <= 80
        .tick = 8
    else
        .tick = 16
    endif
    if associative_target = 1
        .tgtShort$ = "015 012"
    elsif associative_target = 2
        .tgtShort$ = "025 014"
    elsif associative_target = 3
        .tgtShort$ = "segmental"
    else
        .tgtShort$ = "generator"
    endif

    # Vertical layout (inches); the table grows with the number of aggregates.
    if .multi
        .rows = n_agg + 1
        .rowH = 0.15
    else
        .rows = 5
        .rowH = 0.216
    endif
    .tabTop = 5.26
    .tabBot = .tabTop + .rows * .rowH
    .histBot = .tabTop + max(0.80, .rows * .rowH - 0.28)
    .eOn = timbre = 5
    .eRows = 4 * n_cyc
    if .eOn
        .eHeadTop = .tabBot + 0.14
        .eTop = .eHeadTop + 0.24
        .eH = min(1.8, max(0.56, .eRows * 0.06))
        .eBot = .eTop + .eH
        .qcTop = .eBot + 0.36
    else
        .qcTop = .tabBot + 0.18
    endif
    .qcBot = .qcTop + 1.30
    .canvasH = .qcBot + 0.10
    .plan$ = ""
    for .k from 1 to n_cyc
        .sep$ = if .k = 1 then "" else " > " fi
        .plan$ = .plan$ + .sep$ + cycKind$[.k]
    endfor

    Erase all
    Line width: 1
    Colour: "Black"

    # ---------------- Title / process ----------------
    @strip: 0.6, 7.7, 0.08, 0.38, 14, 0.5, "centre", "##Babbitt’s Combinatorial Arrays## — " + preset_label$
    Colour: "{0.30, 0.30, 0.30}"
    if .multi
        .mid$ = ""
        if secondary_sets
            .mid$ = .mid$ + "  ->  secondary sets"
        endif
        if derivation_cycles > 0
            .mid$ = .mid$ + "  ->  derived sets"
        endif
        .voices$ = if timbre = 5 then "array-derived spectra" else "4 additive voices" fi
        .proc$ = "hexachord  ->  " + op_name$ + " array" + .mid$ + "   |   " + string$(n_cyc) + " cycles x 16 partitions  ->  " + string$(n_att) + " time points   |   " + .voices$
    else
        .voices$ = if timbre = 5 then "array-derived spectra" else "4 additive voices" fi
        .proc$ = "hexachord  ->  " + op_name$ + " array  ->  trichordal aggregates   |   16 partitions  ->  32 time points   |   24 entries + 8 rearticulations  ->  " + .voices$
    endif
    @strip: 0.6, 7.7, 0.40, 0.60, 7, 0.5, "centre", .proc$
    Colour: "Black"
    @strip: 0.6, 7.7, 0.62, 0.80, 9, 0, "left", "##A  Four-voice array score##   (lane height = register within the voice band)"

    # ---------------- A: array score ----------------
    @setPanel: 0.6, 7.7, 1.00, 3.30, 0, .xMax, 0, 4, 7
    for .j from 1 to n_agg
        Paint rectangle: aggTint$[.j], .tx0[.j], .tx1[.j], 0, 4
    endfor
    Colour: .grid$
    Line width: 0.8
    if .multi
        .g = 4
        while .g < .xMax
            Draw line: .g, 0, .g, 4
            .g = .g + 4
        endwhile
    else
        for .u from 1 to 16
            Draw line: .u, 0, .u, 4
        endfor
    endif
    Colour: "{0.60, 0.60, 0.60}"
    Line width: 1.2
    if .multi
        for .k from 2 to n_cyc
            Draw line: 16 * (.k - 1), 0, 16 * (.k - 1), 4
        endfor
    else
        Draw line: 8, 0, 8, 4
    endif
    Draw line: 0, 1, .xMax, 1
    Draw line: 0, 2, .xMax, 2
    Draw line: 0, 3, .xMax, 3

    # halos
    for .i from 1 to n_halo
        .v = haloVoice[.i]
        .yb = 4 - .v
        Paint rectangle: tint$[.v], haloBeat[.i], haloBeat[.i] + haloDurBeat[.i], .yb + 0.03, .yb + 0.13
    endfor

    # sounding durations
    Line width: if .multi then 1.6 else 2.2 fi
    for .a from 1 to n_att
        .v = atkVoice[.a]
        .y = (4 - .v) + 0.18 + 0.64 * (atkMidi[.a] - (vc[.v] - 6)) / 12
        atkY[.a] = .y
        Colour: tint$[.v]
        Draw line: atkBeat[.a], .y, atkBeat[.a] + atkHold[.a], .y
    endfor

    # attacks
    .dot = if .multi then 0.9 else 1.4 fi
    Line width: if .multi then 1.0 else 1.3 fi
    for .a from 1 to n_att
        .v = atkVoice[.a]
        if isRe[.a] = 0
            Paint circle (mm): col$[.v], atkBeat[.a], atkY[.a], .dot
        else
            Paint circle (mm): "White", atkBeat[.a], atkY[.a], .dot
            Colour: col$[.v]
            Draw circle (mm): atkBeat[.a], atkY[.a], .dot
        endif
    endfor

    # aggregate boundaries
    Colour: .bnd$
    Line width: if .multi then 1.0 else 1.5 fi
    Dashed line
    for .j from 2 to n_agg
        Draw line: blkStart[.j], 0, blkStart[.j], 4
    endfor
    Solid line
    Line width: 1

    # labels: pitch classes (single cycle only) and aggregate tags above the frame
    if .multi = 0
        pf_font = 6
        for .a from 1 to n_att
            .v = atkVoice[.a]
            if isRe[.a] = 0
                Colour: col$[.v]
            else
                Colour: "{0.55, 0.55, 0.55}"
            endif
            @label: atkBeat[.a] + 0.045 * .xPerInch, "left", atkY[.a] + 0.06, "bottom", string$(atkPc[.a])
        endfor
        Colour: .bnd$
        @label: blkStart[2] - 0.04 * .xPerInch, "right", 4, "bottom", "aggregate 1"
        @label: blkStart[2] + 0.04 * .xPerInch, "left", 4, "bottom", "aggregate 2"
    else
        pf_font = 6
        Colour: "{0.25, 0.25, 0.25}"
        for .j from 1 to n_agg
            @label: 0.5 * (.tx0[.j] + .tx1[.j]), "centre", 4, "bottom", aggSrcShort$[.j]
        endfor
    endif

    # lane labels in the left margin
    for .v from 1 to 4
        pf_font = 9
        Colour: col$[.v]
        @label: -0.08 * .xPerInch, "right", 4 - .v + 0.62, "half", "##" + vName$[.v] + "##"
        pf_font = 7
        @label: -0.08 * .xPerInch, "right", 4 - .v + 0.30, "half", opLab$[.v]
    endfor

    pf_font = 7
    Colour: "Black"
    @frame
    Draw inner box
    Marks bottom every: 1, .tick, "yes", "yes", "no"
    Text bottom: "yes", "Quarter-note units  (quarter = " + fixed$(tempo_bpm, 0) + " bpm)"

    Colour: "{0.30, 0.30, 0.30}"
    if .multi
        .leg$ = "dot = entry   |   ring = rearticulation   |   pale blue / cream = basic   |   teal / rose = secondary   |   other tints = derived generator   |   dashed = aggregate   |   grey = cycle   |   lane labels = cycle 1"
    else
        .leg$ = "filled dot = new array entry   |   ring = rearticulation   |   bar = sounding duration   |   tint under lane = trichord halo   |   dashed = aggregate boundary (attack 17)"
    endif
    @strip: 0.6, 7.7, 3.78, 3.94, 6, 0.5, "centre", .leg$

    # ---------------- B ----------------
    Colour: "Black"
    if .multi = 0
        @strip: 0.6, 7.7, 3.98, 4.16, 9, 0, "left", "##B  Time-point partitions## — " + rhythm_name$ + " (bits = four sixteenths of each quarter)"
        @setPanel: 0.6, 7.7, 4.22, 4.90, 0, .xMax, 0, 1, 7
        for .u from 1 to 16
            Paint rectangle: "{0.93, 0.93, 0.93}", .u - 1 - 0.09, .u - 1 + 0.84, 0.46, 0.94
        endfor
        Colour: "{0.60, 0.60, 0.60}"
        Line width: 1.2
        Draw line: 8 - 0.125, 0, 8 - 0.125, 1
        for .u from 1 to 16
            for .p from 0 to 3
                .bit = floor(code[.u] / 2 ^ (3 - .p)) mod 2
                if .bit = 0
                    Paint circle (mm): "{0.72, 0.72, 0.72}", .u - 1 + .p / 4, 0.70, 0.5
                endif
            endfor
        endfor
        Line width: 1.3
        for .a from 1 to n_att
            .v = atkVoice[.a]
            if isRe[.a] = 0
                Paint circle (mm): col$[.v], atkBeat[.a], 0.70, 1.3
            else
                Paint circle (mm): "White", atkBeat[.a], 0.70, 1.3
                Colour: col$[.v]
                Draw circle (mm): atkBeat[.a], 0.70, 1.3
            endif
        endfor
        Colour: .bnd$
        Line width: 1.5
        Dashed line
        Draw line: blkStart[2], 0, blkStart[2], 1
        Solid line
        Line width: 1
        for .u from 1 to 16
            .bits$ = ""
            for .p from 0 to 3
                .bits$ = .bits$ + string$(floor(code[.u] / 2 ^ (3 - .p)) mod 2)
            endfor
            pf_font = 9
            Colour: "Black"
            @label: .u - 1 + 0.375, "centre", 0.27, "half", "##" + codeChar$[code[.u]] + "##"
            pf_font = 6
            Colour: "{0.40, 0.40, 0.40}"
            @label: .u - 1 + 0.375, "centre", 0.08, "half", .bits$
        endfor
    else
        @strip: 0.6, 7.7, 3.98, 4.16, 9, 0, "left", "##B  Array plan## — " + .plan$ + "   |   rhythm: " + rhythm_name$
        @setPanel: 0.6, 7.7, 4.22, 4.90, 0, .xMax, 0, 1, 7
        for .j from 1 to n_agg
            Paint rectangle: aggTint$[.j], .tx0[.j], .tx1[.j], 0.52, 0.97
        endfor
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, .xMax, 0, 0.48
        Colour: .bnd$
        Line width: 1.0
        Dashed line
        for .j from 2 to n_agg
            Draw line: blkStart[.j], 0.52, blkStart[.j], 0.97
        endfor
        Solid line
        Colour: "{0.60, 0.60, 0.60}"
        Line width: 1.2
        for .k from 2 to n_cyc
            Draw line: 16 * (.k - 1), 0, 16 * (.k - 1), 1
        endfor
        Line width: 1
        pf_font = 7
        Colour: "Black"
        for .j from 1 to n_agg
            @label: 0.5 * (.tx0[.j] + .tx1[.j]), "centre", 0.745, "half", "##" + aggSrcShort$[.j] + "##"
        endfor
        for .k from 1 to n_cyc
            .codes$ = ""
            for .u from 1 to 16
                .codes$ = .codes$ + codeChar$[code[16 * (.k - 1) + .u]]
                if .u = 8
                    .codes$ = .codes$ + if n_cyc > 5 then "|" else " | " fi
                endif
            endfor
            # long schedules leave under an inch per cycle: compact string, smaller font
            pf_font = if n_cyc > 5 then 5 else 6 fi
            Colour: "{0.20, 0.20, 0.20}"
            @label: 16 * (.k - 1) + 8, "centre", 0.34, "half", .codes$
            Colour: "{0.45, 0.45, 0.45}"
            @label: 16 * (.k - 1) + 8, "centre", 0.12, "half", "c" + string$(.k) + "  " + rhShort$[cycRh[.k]]
        endfor
    endif
    pf_font = 7
    Colour: "Black"
    @frame
    Draw inner box

    # ---------------- C: array / derivation table ----------------
    if .multi = 0
        @strip: 0.6, 4.0, 5.02, 5.20, 9, 0, "left", "##C  Four-line array## (columns 1-3 / 4-6 = aggregates)"
    else
        @strip: 0.6, 4.0, 5.02, 5.20, 9, 0, "left", "##C  Aggregate derivation## (one row per aggregate)"
    endif
    @strip: 4.55, 7.7, 5.02, 5.20, 9, 0, "left", "##D  Surface trichords## (orange = target classes)"

    if .multi = 0
        @setPanel: 0.6, 4.0, .tabTop, .tabBot, 0, 10, 0, 5, 8
        Paint rectangle: .agg1$, 2.2, 4.9, 0, 4
        Paint rectangle: .agg2$, 4.9, 7.6, 0, 4
        Paint rectangle: "{0.90, 0.90, 0.90}", 0, 10, 4, 5
        Colour: "{0.75, 0.75, 0.75}"
        Line width: 0.8
        for .r from 1 to 3
            Draw line: 0, .r, 10, .r
        endfor
        Draw line: 2.2, 0, 2.2, 5
        Draw line: 7.6, 0, 7.6, 5
        Colour: .bnd$
        Line width: 1.5
        Dashed line
        Draw line: 4.9, 0, 4.9, 5
        Solid line
        Line width: 1
        pf_font = 7
        Colour: "{0.25, 0.25, 0.25}"
        @label: 1.1, "centre", 4.5, "half", "line"
        for .k from 1 to 6
            @label: 2.2 + (.k - 0.5) * 0.9, "centre", 4.5, "half", string$(.k)
        endfor
        @label: 8.8, "centre", 4.5, "half", "trichords"
        for .v from 1 to 4
            .yr = 4 - .v + 0.5
            pf_font = 8
            Colour: col$[.v]
            @label: 0.25, "left", .yr, "half", "##" + vName$[.v] + "##   " + opLab$[.v]
            for .k from 1 to 6
                @label: 2.2 + (.k - 0.5) * 0.9, "centre", .yr, "half", string$(line[.v, .k])
            endfor
            pf_font = 7
            Colour: "{0.25, 0.25, 0.25}"
            @label: 8.8, "centre", .yr, "half", "0" + string$(triCode[.v, 1]) + "  /  0" + string$(triCode[.v, 2])
        endfor
    else
        .nR = .rows
        @setPanel: 0.6, 4.0, .tabTop, .tabBot, 0, 10, 0, .nR, 6
        Paint rectangle: "{0.90, 0.90, 0.90}", 0, 10, .nR - 1, .nR
        for .j from 1 to n_agg
            Paint rectangle: aggTint$[.j], 0, 10, .nR - 1 - .j, .nR - .j
        endfor
        Colour: "{0.75, 0.75, 0.75}"
        Line width: 0.8
        for .j from 1 to n_agg - 1
            Draw line: 0, .nR - 1 - .j, 10, .nR - 1 - .j
        endfor
        Draw line: 0.7, 0, 0.7, .nR
        Draw line: 2.2, 0, 2.2, .nR
        Draw line: 4.15, 0, 4.15, .nR
        Draw line: 6.1, 0, 6.1, .nR
        Draw line: 8.05, 0, 8.05, .nR
        Colour: "{0.45, 0.45, 0.45}"
        Line width: 1.2
        for .k from 1 to n_cyc - 1
            Draw line: 0, .nR - 1 - 2 * .k, 10, .nR - 1 - 2 * .k
        endfor
        Line width: 1
        pf_font = 6
        Colour: "{0.25, 0.25, 0.25}"
        @label: 0.35, "centre", .nR - 0.5, "half", "agg"
        @label: 1.45, "centre", .nR - 0.5, "half", "source"
        for .v from 1 to 4
            Colour: col$[.v]
            @label: 2.2 + (.v - 0.5) * 1.95, "centre", .nR - 0.5, "half", "##" + vName$[.v] + "##"
        endfor
        for .j from 1 to n_agg
            .yr = .nR - .j - 0.5
            Colour: "{0.25, 0.25, 0.25}"
            @label: 0.35, "centre", .yr, "half", string$(.j)
            @label: 1.45, "centre", .yr, "half", aggSrcShort$[.j]
            for .v from 1 to 4
                Colour: col$[.v]
                @label: 2.2 + (.v - 0.5) * 1.95, "centre", .yr, "half", string$(aggPc[.j, .v, 1]) + " " + string$(aggPc[.j, .v, 2]) + " " + string$(aggPc[.j, .v, 3]) + "   " + aggLab$[.j, .v]
            endfor
        endfor
    endif
    pf_font = 7
    Colour: "Black"
    @frame
    Draw inner box

    # ---------------- D: surface-trichord histogram ----------------
    .maxCount = 1
    for .k from 1 to n_cls
        .maxCount = max(.maxCount, surfCount[clsCode[.k]])
    endfor
    if .maxCount <= 5
        .step = 1
    elsif .maxCount <= 12
        .step = 2
    elsif .maxCount <= 30
        .step = 5
    else
        .step = 10
    endif
    .yTop = ceiling(.maxCount * 1.15 / .step) * .step
    @setPanel: 4.55, 7.7, .tabTop, .histBot, 0.4, 12.6, 0, .yTop, 6
    for .k from 1 to n_cls
        .cnt = surfCount[clsCode[.k]]
        if .cnt > 0
            if anyTarget[clsCode[.k]] = 1
                .bc$ = "{0.85, 0.40, 0.15}"
            else
                .bc$ = "{0.62, 0.62, 0.62}"
            endif
            Paint rectangle: .bc$, .k - 0.32, .k + 0.32, 0, .cnt
        endif
    endfor
    for .k from 1 to n_cls
        .cnt = surfCount[clsCode[.k]]
        if .cnt > 0
            Colour: "{0.25, 0.25, 0.25}"
            @label: .k, "centre", .cnt, "bottom", string$(.cnt)
        endif
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    for .k from 1 to n_cls
        One mark bottom: .k, "no", "yes", "no", "0" + string$(clsCode[.k])
    endfor
    Marks left every: 1, .step, "yes", "yes", "no"

    # ---------------- E: structural timbre ----------------
    if .eOn
        Colour: "Black"
        @strip: 0.6, 7.7, .eHeadTop, .eHeadTop + 0.18, 9, 0, "left", "##E  Structural timbre## — partial h = pitch class h-2 (h1 = anchor); shade = order position in the current line"
        colR[1] = 0.20
        colG[1] = 0.40
        colB[1] = 0.80
        colR[2] = 0.85
        colG[2] = 0.40
        colB[2] = 0.15
        colR[3] = 0.15
        colG[3] = 0.58
        colB[3] = 0.35
        colR[4] = 0.55
        colG[4] = 0.25
        colB[4] = 0.65
        .rH = .eH / .eRows
        @setPanel: 1.0, 7.7, .eTop, .eBot, 0.5, 13.5, 0, .eRows, 6
        Paint rectangle: "{0.98, 0.98, 0.98}", 0.5, 13.5, 0, .eRows
        for .k from 1 to n_cyc
            for .v from 1 to 4
                .row = .eRows - ((.k - 1) * 4 + .v)
                .rowMax = 0
                for .h from 2 to 13
                    .rowMax = max(.rowMax, stw[.k, .v, .h])
                endfor
                for .h from 1 to 13
                    .wv = stw[.k, .v, .h]
                    if .h = 1
                        .mix = 0.35
                    elsif .rowMax > 0
                        .mix = .wv / .rowMax
                    else
                        .mix = 0
                    endif
                    if .mix > 0
                        .cr = 1 - .mix * (1 - colR[.v])
                        .cg = 1 - .mix * (1 - colG[.v])
                        .cb = 1 - .mix * (1 - colB[.v])
                        .cc$ = "{" + fixed$(.cr, 3) + ", " + fixed$(.cg, 3) + ", " + fixed$(.cb, 3) + "}"
                        Paint rectangle: .cc$, .h - 0.45, .h + 0.45, .row + 0.08, .row + 0.92
                    endif
                endfor
            endfor
        endfor
        Colour: "{0.45, 0.45, 0.45}"
        Line width: 1.2
        for .k from 1 to n_cyc - 1
            Draw line: 0.5, .eRows - 4 * .k, 13.5, .eRows - 4 * .k
        endfor
        Line width: 1
        Colour: "{0.75, 0.75, 0.75}"
        Draw line: 1.5, 0, 1.5, .eRows
        # left rail: cycle kind and voice letters
        for .k from 1 to n_cyc
            pf_font = 6
            Colour: "{0.25, 0.25, 0.25}"
            @label: -0.35, "right", .eRows - (.k - 1) * 4 - 2, "half", "c" + string$(.k) + " " + cycKind$[.k]
            if .rH >= 0.08
                for .v from 1 to 4
                    Colour: col$[.v]
                    @label: 0.25, "right", .eRows - ((.k - 1) * 4 + .v) + 0.5, "half", vName$[.v]
                endfor
            endif
        endfor
        pf_font = 6
        Colour: "Black"
        @frame
        Draw inner box
        One mark bottom: 1, "no", "yes", "no", "h1"
        for .h from 2 to 13
            One mark bottom: .h, "no", "yes", "no", "h" + string$(.h) + " / " + string$(.h - 2)
        endfor
    endif

    # ---------------- Structural QC ----------------
    @setPanel: 0.6, 7.7, .qcTop, .qcBot, 0, 3, 0, 5, 7
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 3, 0, 5
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 1, 0, 1, 5
    Draw line: 2, 0, 2, 5
    Draw line: 0, 1, 3, 1
    Draw line: 0, 2, 3, 2
    Draw line: 0, 3, 3, 3
    Draw line: 0, 4, 3, 4
    Colour: "Black"
    @frame
    Draw inner box
    Colour: "{0.25, 0.25, 0.25}"
    .hexa$ = ""
    for .k from 1 to 6
        .hexa$ = .hexa$ + string$(pP[.k]) + " "
    endfor
    .arrOk$ = if arr_agg_ok = 1 then "ok" else "FAIL" fi
    .icOk$ = if all_ic then "= 1-5 once" else "(not all-IC)" fi
    if .multi
        .der$ = "Derived partitions " + deriv_label$
    else
        .der$ = "Derivation off (0 cycles)"
    endif
    if secondary_sets
        .sec$ = "Secondary sets " + sec_op$ + " | 12-tone lines " + string$(sec_ok) + "/4"
    else
        .sec$ = "Secondary sets off"
    endif
    if timbre = 5
        .cMin = 99
        .cMax = 0
        for .k from 1 to n_cyc
            for .v from 1 to 4
                .cMin = min(.cMin, stwCent[.k, .v])
                .cMax = max(.cMax, stwCent[.k, .v])
            endfor
        endfor
        .tim$ = "Structural | centroid h" + fixed$(.cMin, 1) + "-h" + fixed$(.cMax, 1) + " | halos " + string$(n_halo)
    else
        .tim$ = "Timbre " + timbre_name$ + " | halos " + string$(n_halo)
    endif
    if xmlStatus$ = "skipped"
        .xmlQc$ = "MusicXML skipped"
    else
        .xmlQc$ = "MusicXML " + xmlStatus$ + " | " + string$(nXmlLines) + " lines, " + string$(xml_measures) + " bars"
    endif
    .planShow$ = .plan$
    if length(.planShow$) > 46
        .planShow$ = left$(.planShow$, 43) + "..."
    endif
    @label: 0.5, "centre", 4.5, "half", .sec$
    @label: 1.5, "centre", 4.5, "half", "Plan " + .planShow$
    @label: 2.5, "centre", 4.5, "half", .tim$
    @label: 0.5, "centre", 3.5, "half", "Hexachord " + .hexa$ + "(" + source_name$ + ")"
    @label: 1.5, "centre", 3.5, "half", "Adjacent ICs " + ic_list$ + .icOk$
    @label: 2.5, "centre", 3.5, "half", "Array " + op_name$ + " (Y = " + y_label$ + ") | trichord aggregates " + .arrOk$
    @label: 0.5, "centre", 2.5, "half", "Combinatorial: " + string$(comb_nInv) + " I-forms, " + string$(comb_nTr) + " T-forms"
    @label: 1.5, "centre", 2.5, "half", "Segmental trichords " + seg_label$
    @label: 2.5, "centre", 2.5, "half", .der$
    @label: 0.5, "centre", 1.5, "half", "Aggregates realized " + string$(n_agg_ok) + "/" + string$(n_agg) + " | derived " + string$(n_derived_agg)
    @label: 1.5, "centre", 1.5, "half", "Partitions exhaustive " + string$(partitions_ok) + "/" + string$(n_cyc) + " cycles | " + string$(n_att) + " attacks (" + string$(n_new) + " + " + string$(n_re) + " re)"
    @label: 2.5, "centre", 1.5, "half", rearticulation_name$ + " | target " + .tgtShort$ + ": " + string$(surf_hits) + "/" + string$(n_surf)
    @label: 0.5, "centre", 0.5, "half", .xmlQc$
    @label: 1.5, "centre", 0.5, "half", "MIDI " + string$(min_midi) + "-" + string$(max_midi) + " | max partial " + fixed$(max_partial, 0) + " Hz | dropped " + string$(dropped_partials)
    @label: 2.5, "centre", 0.5, "half", "Dur " + fixed$(master_duration, 2) + " s | Peak/RMS " + fixed$(final_peak, 3) + "/" + fixed$(final_rms, 3)

    Font size: 10
    Colour: "Black"
    Line width: 1
    Select outer viewport: 0, 8, 0, .canvasH
    viz_canvas_height = .canvasH
endproc
