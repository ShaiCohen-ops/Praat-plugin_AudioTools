# ============================================================
# Praat AudioTools - SpectraScore_Orchestration_Matcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SpectraScore - Orchestration Matcher
#   Analyzes target sound spectrum and suggests instrument combinations
#   Outputs MusicXML orchestrated chord with microtonal support
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed all array syntax for Praat compatibility
#   - Fixed form title
#   - Fixed != to <> operator
#   - Added input validation
#   - Added XML file save option
#   - Added visualization
#
# Changelog v0.3 (2026):
#   - FIX (consequential): K=2/3/4 combination scoring was passing the
#     first instrument's index to scoreInstrument() along with the MIX's
#     centroid/spread/odd_even values, computing |inst_i - mix| instead
#     of the intended |mix - target|. The "best" combination found was
#     scored against a meaningless reference. Now combinations are scored
#     by direct mix-to-target distance via a new scoreCombo procedure.
#     Best-match results from v0.2 may differ noticeably from v0.3.
#   - REFACTOR: The four hand-written K=1..4 search loops with progressively
#     deeper nesting and progressively more @getInstCentroid/Spread calls
#     are now driven by a single nested-loop core that uses scoreCombo
#     for any combination size. Eliminates ~150 lines of copy-paste and
#     makes max_combination_size=5+ trivial to support if needed later.
#   - FIX: Procedure-local "low"/"high" variables in canPlay and
#     assignVoicing were leaking to the global script scope. Now properly
#     scoped as .low/.high to prevent silent reuse across calls.
#   - FIX: harmonic_num display in voicing report rounded chord-voicing
#     ratios (1.26, 1.5) to 1 or 2, mislabelling third/fifth as H1/H2.
#     Now only spectral-voicing assignments report harmonic numbers;
#     other strategies report the interval name.
#   - QUALITY: Microtonal accidental ranges extended to cover three-quarter
#     sharps/flats (62.5-87.5 cents) which previously got an <alter> value
#     but no <accidental> element.
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

clearinfo

form SpectraScore Orchestration Matcher v0.3
    comment Select instruments to include:
    boolean BTb 1
    boolean Bn 1
    boolean Cb 1
    boolean ClBb 1
    boolean Fl 1
    boolean Hn 1
    boolean Ob 1
    boolean Tbn 1
    boolean TpC 1
    boolean Va 1
    boolean Vc 1
    boolean Vn 1
    comment Search parameters:
    integer Max_combination_size 4
    boolean Allow_divisi 0
    comment Voicing strategy:
    optionmenu Voicing_strategy: 4
        option Unison (all on root)
        option Octaves (spread by brightness)
        option Chord (root fifth octave)
        option Spectral (match harmonics)
    comment Microtonal settings:
    boolean Enable_microtones 1
    real Microtone_precision_cents 12.5
    integer Min_harmonic 7
    integer Max_harmonic 16
    comment Output:
    boolean Save_xml_file 0
    boolean Draw_visualization 1
endform

# ============================================================================
# INSTRUMENT DATABASE
# ============================================================================
# Using indexed variables instead of arrays for Praat compatibility

n_instruments = 0

procedure addInstrument: .name$, .midi_low, .midi_high, .transpose, .clef$, .cent_pp, .cent_mf, .cent_ff, .spr_pp, .spr_mf, .spr_ff, .odd_even, .inharm
    n_instruments += 1
    n = n_instruments
    inst_name_'n'$ = .name$
    inst_midi_low_'n' = .midi_low
    inst_midi_high_'n' = .midi_high
    inst_transpose_'n' = .transpose
    inst_clef_'n'$ = .clef$
    inst_cent_pp_'n' = .cent_pp
    inst_cent_mf_'n' = .cent_mf
    inst_cent_ff_'n' = .cent_ff
    inst_spr_pp_'n' = .spr_pp
    inst_spr_mf_'n' = .spr_mf
    inst_spr_ff_'n' = .spr_ff
    inst_odd_even_'n' = .odd_even
    inst_inharm_'n' = .inharm
endproc

# Add instruments based on selection
if bTb
    @addInstrument: "BTb", 28, 60, 0, "bass", 350, 450, 600, 200, 280, 400, 0.65, 0.02
endif
if bn
    @addInstrument: "Bn", 34, 75, 0, "bass", 400, 520, 680, 220, 300, 420, 0.70, 0.03
endif
if cb
    @addInstrument: "Cb", 28, 67, -12, "bass", 280, 380, 520, 180, 250, 350, 0.60, 0.04
endif
if clBb
    @addInstrument: "ClBb", 50, 94, 2, "treble", 800, 1100, 1500, 400, 550, 750, 0.55, 0.02
endif
if fl
    @addInstrument: "Fl", 60, 96, 0, "treble", 1200, 1600, 2200, 600, 800, 1100, 0.50, 0.01
endif
if hn
    @addInstrument: "Hn", 34, 77, -7, "treble", 450, 600, 850, 250, 350, 500, 0.68, 0.03
endif
if ob
    @addInstrument: "Ob", 58, 91, 0, "treble", 1000, 1350, 1800, 500, 650, 900, 0.72, 0.02
endif
if tbn
    @addInstrument: "Tbn", 40, 72, 0, "bass", 380, 500, 680, 210, 290, 410, 0.67, 0.02
endif
if tpC
    @addInstrument: "TpC", 52, 82, 0, "treble", 1100, 1500, 2100, 550, 750, 1000, 0.58, 0.02
endif
if va
    @addInstrument: "Va", 48, 84, 0, "alto", 600, 850, 1200, 320, 450, 650, 0.62, 0.02
endif
if vc
    @addInstrument: "Vc", 36, 76, 0, "bass", 400, 580, 820, 240, 340, 480, 0.64, 0.03
endif
if vn
    @addInstrument: "Vn", 55, 103, 0, "treble", 900, 1250, 1750, 450, 600, 850, 0.60, 0.02
endif

if n_instruments = 0
    exitScript: "No instruments selected!"
endif

# ============================================================================
# ANALYZE TARGET SOUND
# ============================================================================

selectObject: sound
duration = Get total duration

writeInfoLine: "=== SpectraScore Orchestration Matcher v0.3 ==="
appendInfoLine: "Analyzing: ", sound_name$
appendInfoLine: ""

# 1. PITCH ANALYSIS
selectObject: sound
pitch = To Pitch (ac): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
target_f0 = Get mean: 0, 0, "Hertz"
if target_f0 = undefined
    target_f0 = Get quantile: 0, 0, 0.50, "Hertz"
endif
if target_f0 = undefined or target_f0 < 50
    target_f0 = 261.63
    appendInfoLine: "Warning: Could not detect pitch, using C4 (261.63 Hz)"
endif
target_midi = 69 + 12 * log2(target_f0 / 440)

# 2. INTENSITY ANALYSIS
selectObject: sound
intensity = To Intensity: 100, 0, "yes"
target_db = Get mean: 0, 0, "dB"

# 3. HARMONICITY
selectObject: sound
harmonicity = To Harmonicity (cc): 0.01, 75, 0.1, 1
target_hnr = Get mean: 0, 0

# 4. SPECTRAL ANALYSIS
selectObject: sound
spectrum = To Spectrum: "yes"
target_centroid = Get centre of gravity: 2
target_spread = Get standard deviation: 2

# Get spectral energy in bands
selectObject: spectrum
band_energy_1 = Get band energy: 50, 200
band_energy_2 = Get band energy: 200, 500
band_energy_3 = Get band energy: 500, 1000
band_energy_4 = Get band energy: 1000, 2000
band_energy_5 = Get band energy: 2000, 5000
band_energy_6 = Get band energy: 5000, 10000

# Normalize band energies
total_energy = band_energy_1 + band_energy_2 + band_energy_3 + band_energy_4 + band_energy_5 + band_energy_6
if total_energy > 0
    band_energy_1 = band_energy_1 / total_energy
    band_energy_2 = band_energy_2 / total_energy
    band_energy_3 = band_energy_3 / total_energy
    band_energy_4 = band_energy_4 / total_energy
    band_energy_5 = band_energy_5 / total_energy
    band_energy_6 = band_energy_6 / total_energy
endif

# Estimate odd/even ratio
selectObject: spectrum
low_band = Get band energy: 100, 1000
high_band = Get band energy: 1000, 5000
if low_band + high_band > 0
    target_odd_even = high_band / (low_band + high_band)
else
    target_odd_even = 0.5
endif

# Map intensity to dynamic
if target_db < 50
    target_dynamic$ = "pp"
    dyn_idx = 1
elsif target_db < 70
    target_dynamic$ = "mf"
    dyn_idx = 2
else
    target_dynamic$ = "ff"
    dyn_idx = 3
endif

# Clean up analysis objects
removeObject: pitch, intensity, harmonicity, spectrum

appendInfoLine: "=== TARGET ANALYSIS ==="
appendInfoLine: "F0: ", fixed$(target_f0, 2), " Hz (MIDI ", fixed$(target_midi, 1), ")"
appendInfoLine: "Intensity: ", fixed$(target_db, 1), " dB -> ", target_dynamic$
appendInfoLine: "HNR: ", fixed$(target_hnr, 1), " dB"
appendInfoLine: "Centroid: ", fixed$(target_centroid, 0), " Hz"
appendInfoLine: "Spread: ", fixed$(target_spread, 0), " Hz"
appendInfoLine: "Odd/Even ratio: ", fixed$(target_odd_even, 3)
appendInfoLine: ""

if voicing_strategy = 4
    appendInfoLine: "Target harmonics (H", min_harmonic, "-H", max_harmonic, "):"
    for h from min_harmonic to max_harmonic
        h_freq = target_f0 * h
        appendInfoLine: "  H", h, " = ", fixed$(h_freq, 1), " Hz"
    endfor
    appendInfoLine: ""
endif

# ============================================================================
# HELPER PROCEDURES
# ============================================================================

procedure getInstCentroid: .idx
    if dyn_idx = 1
        .result = inst_cent_pp_'.idx'
    elsif dyn_idx = 2
        .result = inst_cent_mf_'.idx'
    else
        .result = inst_cent_ff_'.idx'
    endif
endproc

procedure getInstSpread: .idx
    if dyn_idx = 1
        .result = inst_spr_pp_'.idx'
    elsif dyn_idx = 2
        .result = inst_spr_mf_'.idx'
    else
        .result = inst_spr_ff_'.idx'
    endif
endproc

procedure canPlay: .idx, .midi
    .low = inst_midi_low_'.idx'
    .high = inst_midi_high_'.idx'
    .can = (.midi >= .low and .midi <= .high)
endproc

procedure scoreInstrument: .idx, .target_cent, .target_spr, .target_oe
    @getInstCentroid: .idx
    .cent = getInstCentroid.result
    @getInstSpread: .idx
    .spr = getInstSpread.result
    .oe = inst_odd_even_'.idx'
    
    .d_cent = abs(.cent - .target_cent) / 2000
    .d_spr = abs(.spr - .target_spr) / 1000
    .d_oe = abs(.oe - .target_oe)
    
    .score = .d_cent + .d_spr + 0.5 * .d_oe
endproc

procedure scoreCombo: .n_in_combo
    # v0.3: Score a combination of instruments by computing the
    # mix's (centroid, spread, odd/even) and measuring the distance
    # from this mix to the TARGET. v0.2 incorrectly compared the
    # first instrument's descriptors to the mix's descriptors,
    # which is a meaningless reference.
    #
    # Caller convention: set combo_idx_1, combo_idx_2, ...,
    # combo_idx_'n_in_combo' as the indices of the instruments
    # in the combination, then call @scoreCombo: n_in_combo.
    .sum_cent = 0
    .sum_spr = 0
    .sum_oe = 0
    for .pos from 1 to .n_in_combo
        .ix = combo_idx_'.pos'
        @getInstCentroid: .ix
        .sum_cent = .sum_cent + getInstCentroid.result
        @getInstSpread: .ix
        .sum_spr = .sum_spr + getInstSpread.result
        .sum_oe = .sum_oe + inst_odd_even_'.ix'
    endfor
    .mix_cent = .sum_cent / .n_in_combo
    .mix_spr  = .sum_spr  / .n_in_combo
    .mix_oe   = .sum_oe   / .n_in_combo
    
    .d_cent = abs(.mix_cent - target_centroid) / 2000
    .d_spr  = abs(.mix_spr  - target_spread)   / 1000
    .d_oe   = abs(.mix_oe   - target_odd_even)
    .score = .d_cent + .d_spr + 0.5 * .d_oe
endproc

procedure assignVoicing: .inst_idx, .position, .n_total
    .target_freq = target_f0
    .cents_offset = 0
    
    if voicing_strategy = 1
        # Unison
        .midi_note = target_midi
        
    elsif voicing_strategy = 2
        # Octaves - spread by brightness
        @getInstCentroid: .inst_idx
        inst_brightness = getInstCentroid.result
        
        if inst_brightness < 500
            .midi_note = target_midi - 12
            .target_freq = target_f0 / 2
        elsif inst_brightness > 1200
            .midi_note = target_midi + 12
            .target_freq = target_f0 * 2
        else
            .midi_note = target_midi
            .target_freq = target_f0
        endif
        
    elsif voicing_strategy = 3
        # Chord voicing
        if .n_total = 1
            .midi_note = target_midi
        elsif .n_total = 2
            if .position = 1
                .midi_note = target_midi
            else
                .midi_note = target_midi + 7
                .target_freq = target_f0 * 1.5
            endif
        elsif .n_total = 3
            if .position = 1
                .midi_note = target_midi
            elsif .position = 2
                .midi_note = target_midi + 7
                .target_freq = target_f0 * 1.5
            else
                .midi_note = target_midi + 12
                .target_freq = target_f0 * 2
            endif
        else
            if .position = 1
                .midi_note = target_midi
            elsif .position = 2
                .midi_note = target_midi + 4
                .target_freq = target_f0 * 1.26
            elsif .position = 3
                .midi_note = target_midi + 7
                .target_freq = target_f0 * 1.5
            else
                .midi_note = target_midi + 12
                .target_freq = target_f0 * 2
            endif
        endif
        
    else
        # Spectral - match harmonics
        @getInstCentroid: .inst_idx
        inst_brightness = getInstCentroid.result
        
        # Find best matching harmonic
        harmonic = min_harmonic
        min_diff = 999999
        for h from min_harmonic to max_harmonic
            harm_freq = target_f0 * h
            diff = abs(inst_brightness - harm_freq)
            if diff < min_diff
                min_diff = diff
                harmonic = h
            endif
        endfor
        
        .target_freq = target_f0 * harmonic
        .midi_note_exact = 69 + 12 * log2(.target_freq / 440)
        .midi_note = round(.midi_note_exact)
        .cents_offset = (.midi_note_exact - .midi_note) * 100
        
        if enable_microtones and microtone_precision_cents > 0
            .cents_offset = round(.cents_offset / microtone_precision_cents) * microtone_precision_cents
        elsif not enable_microtones
            .cents_offset = 0
        endif
    endif
    
    # Ensure in range  (v0.3: procedure-local .low/.high, not globals)
    .low = inst_midi_low_'.inst_idx'
    .high = inst_midi_high_'.inst_idx'
    
    if .midi_note < .low
        .midi_note += 12
        .target_freq *= 2
    endif
    if .midi_note > .high
        .midi_note -= 12
        .target_freq /= 2
    endif
    
    if .midi_note < .low or .midi_note > .high
        .midi_note = target_midi
        .target_freq = target_f0
        .cents_offset = 0
    endif
endproc

# ============================================================================
# SEARCH COMBINATIONS
# ============================================================================

# ============================================================================
# SEARCH COMBINATIONS
# ============================================================================
# v0.3: K=1..4 are now driven by a single scoreCombo procedure that
# averages the candidate's centroid/spread/odd_even and measures the
# distance to the target. v0.2's separate K=2/3/4 paths each had ~50
# lines of repeated @getInstCentroid/Spread calls and a bug where
# scoreInstrument was passed the first instrument's index alongside
# the mix's descriptors, computing |inst_i - mix| instead of the
# intended |mix - target|.

best_score = 1e10
best_n = 0

appendInfoLine: "=== SEARCHING COMBINATIONS ==="
appendInfoLine: "Instruments available: ", n_instruments
appendInfoLine: "Max combination size: ", max_combination_size
appendInfoLine: ""

# K=1 (single instrument) — direct |inst - target| via scoreInstrument
appendInfoLine: "Searching K=1..."
for i from 1 to n_instruments
    @canPlay: i, target_midi
    if canPlay.can
        @scoreInstrument: i, target_centroid, target_spread, target_odd_even
        if scoreInstrument.score < best_score
            best_score = scoreInstrument.score
            best_n = 1
            best_inst_1 = i
            appendInfoLine: "  Found: ", inst_name_'i'$, " (score=", fixed$(scoreInstrument.score, 4), ")"
        endif
    endif
endfor

# K=2 (pairs)
if max_combination_size >= 2
    appendInfoLine: "Searching K=2..."
    for i from 1 to n_instruments - 1
        @canPlay: i, target_midi
        if canPlay.can
            for j from i + 1 to n_instruments
                @canPlay: j, target_midi
                if canPlay.can
                    name_i$ = inst_name_'i'$
                    name_j$ = inst_name_'j'$
                    if allow_divisi or name_i$ <> name_j$
                        combo_idx_1 = i
                        combo_idx_2 = j
                        @scoreCombo: 2
                        if scoreCombo.score < best_score
                            best_score = scoreCombo.score
                            best_n = 2
                            best_inst_1 = i
                            best_inst_2 = j
                            appendInfoLine: "  Found: ", name_i$, "+", name_j$, " (", fixed$(scoreCombo.score, 4), ")"
                        endif
                    endif
                endif
            endfor
        endif
    endfor
endif

# K=3 (triples)
if max_combination_size >= 3
    appendInfoLine: "Searching K=3..."
    for i from 1 to n_instruments - 2
        @canPlay: i, target_midi
        if canPlay.can
            for j from i + 1 to n_instruments - 1
                @canPlay: j, target_midi
                if canPlay.can
                    for k from j + 1 to n_instruments
                        @canPlay: k, target_midi
                        if canPlay.can
                            combo_idx_1 = i
                            combo_idx_2 = j
                            combo_idx_3 = k
                            @scoreCombo: 3
                            if scoreCombo.score < best_score
                                best_score = scoreCombo.score
                                best_n = 3
                                best_inst_1 = i
                                best_inst_2 = j
                                best_inst_3 = k
                                appendInfoLine: "  Found: ", inst_name_'i'$, "+", inst_name_'j'$, "+", inst_name_'k'$, " (", fixed$(scoreCombo.score, 4), ")"
                            endif
                        endif
                    endfor
                endif
            endfor
        endif
    endfor
endif

# K=4 (quadruples)
if max_combination_size >= 4
    appendInfoLine: "Searching K=4..."
    for i from 1 to n_instruments - 3
        @canPlay: i, target_midi
        if canPlay.can
            for j from i + 1 to n_instruments - 2
                @canPlay: j, target_midi
                if canPlay.can
                    for k from j + 1 to n_instruments - 1
                        @canPlay: k, target_midi
                        if canPlay.can
                            for m from k + 1 to n_instruments
                                @canPlay: m, target_midi
                                if canPlay.can
                                    combo_idx_1 = i
                                    combo_idx_2 = j
                                    combo_idx_3 = k
                                    combo_idx_4 = m
                                    @scoreCombo: 4
                                    if scoreCombo.score < best_score
                                        best_score = scoreCombo.score
                                        best_n = 4
                                        best_inst_1 = i
                                        best_inst_2 = j
                                        best_inst_3 = k
                                        best_inst_4 = m
                                        appendInfoLine: "  Found: ", inst_name_'i'$, "+", inst_name_'j'$, "+", inst_name_'k'$, "+", inst_name_'m'$, " (", fixed$(scoreCombo.score, 4), ")"
                                    endif
                                endif
                            endfor
                        endif
                    endfor
                endif
            endfor
        endif
    endfor
endif

if best_n = 0
    exitScript: "No valid instrument combination found for MIDI note " + fixed$(target_midi, 1)
endif

appendInfoLine: ""
appendInfoLine: "=== BEST MATCH (score=", fixed$(best_score, 4), ") ==="
for p from 1 to best_n
    idx = best_inst_'p'
    appendInfoLine: "  ", inst_name_'idx'$
endfor

# ============================================================================
# VOICING ASSIGNMENTS
# ============================================================================

appendInfoLine: ""
appendInfoLine: "=== VOICING ASSIGNMENTS ==="

for p from 1 to best_n
    idx = best_inst_'p'
    @assignVoicing: idx, p, best_n
    
    voicing_midi_'p' = assignVoicing.midi_note
    voicing_cents_'p' = assignVoicing.cents_offset
    voicing_freq_'p' = assignVoicing.target_freq
    
    # v0.3: Only label "H<n>" for the spectral voicing strategy.
    # Other strategies use intervals (unison/fifth/octave/third) so
    # round(target_freq / target_f0) misleadingly rounds 1.26 -> 1
    # and 1.5 -> 2, mislabelling thirds and fifths.
    if voicing_strategy = 4
        harmonic_num = round(assignVoicing.target_freq / target_f0)
        labelStr$ = "H" + string$(harmonic_num)
    elsif voicing_strategy = 1
        labelStr$ = "unison"
    elsif voicing_strategy = 2
        ratio = assignVoicing.target_freq / target_f0
        if ratio < 0.75
            labelStr$ = "octave_down"
        elsif ratio > 1.5
            labelStr$ = "octave_up"
        else
            labelStr$ = "unison"
        endif
    else
        # voicing_strategy = 3 (chord)
        ratio = assignVoicing.target_freq / target_f0
        if ratio < 1.1
            labelStr$ = "root"
        elsif ratio < 1.35
            labelStr$ = "major3rd"
        elsif ratio < 1.7
            labelStr$ = "fifth"
        else
            labelStr$ = "octave"
        endif
    endif
    appendInfoLine: inst_name_'idx'$, ": ", labelStr$, " (", fixed$(assignVoicing.target_freq, 1), " Hz) -> MIDI ", fixed$(assignVoicing.midi_note, 1), " + ", fixed$(assignVoicing.cents_offset, 1), " cents"
endfor

# ============================================================================
# GENERATE MUSICXML
# ============================================================================

appendInfoLine: ""
appendInfoLine: "=== GENERATING MUSICXML ==="

# Pitch class names
step_0$ = "C"
step_1$ = "C"
step_2$ = "D"
step_3$ = "D"
step_4$ = "E"
step_5$ = "F"
step_6$ = "F"
step_7$ = "G"
step_8$ = "G"
step_9$ = "A"
step_10$ = "A"
step_11$ = "B"

# Base alterations
alter_0 = 0
alter_1 = 1
alter_2 = 0
alter_3 = 1
alter_4 = 0
alter_5 = 0
alter_6 = 1
alter_7 = 0
alter_8 = 1
alter_9 = 0
alter_10 = 1
alter_11 = 0

xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$
xml$ = xml$ + "  <work><work-title>SpectraScore: " + sound_name$ + "</work-title></work>" + newline$
xml$ = xml$ + "  <identification>" + newline$
xml$ = xml$ + "    <creator type=""software"">Praat SpectraScore v0.3</creator>" + newline$
xml$ = xml$ + "  </identification>" + newline$

# Part list
xml$ = xml$ + "  <part-list>" + newline$
for p from 1 to best_n
    idx = best_inst_'p'
    xml$ = xml$ + "    <score-part id=""P" + string$(p) + """>" + newline$
    xml$ = xml$ + "      <part-name>" + inst_name_'idx'$ + "</part-name>" + newline$
    xml$ = xml$ + "    </score-part>" + newline$
endfor
xml$ = xml$ + "  </part-list>" + newline$

# Parts with notes
for p from 1 to best_n
    idx = best_inst_'p'
    
    written_midi = voicing_midi_'p' - inst_transpose_'idx'
    cents_dev = voicing_cents_'p'
    
    pitch_class = round(written_midi) mod 12
    if pitch_class < 0
        pitch_class = pitch_class + 12
    endif
    octave = floor(written_midi / 12) - 1
    
    step$ = step_'pitch_class'$
    base_alt = alter_'pitch_class'
    total_alter = base_alt + (cents_dev / 100.0)
    
    clef$ = inst_clef_'idx'$
    if clef$ = "treble"
        clef_sign$ = "G"
        clef_line = 2
    elsif clef$ = "alto"
        clef_sign$ = "C"
        clef_line = 3
    else
        clef_sign$ = "F"
        clef_line = 4
    endif
    
    xml$ = xml$ + "  <part id=""P" + string$(p) + """>" + newline$
    xml$ = xml$ + "    <measure number=""1"">" + newline$
    xml$ = xml$ + "      <attributes>" + newline$
    xml$ = xml$ + "        <divisions>1</divisions>" + newline$
    xml$ = xml$ + "        <key><fifths>0</fifths></key>" + newline$
    xml$ = xml$ + "        <time><beats>4</beats><beat-type>4</beat-type></time>" + newline$
    xml$ = xml$ + "        <clef><sign>" + clef_sign$ + "</sign><line>" + string$(clef_line) + "</line></clef>" + newline$
    
    transpose = inst_transpose_'idx'
    if transpose <> 0
        xml$ = xml$ + "        <transpose><chromatic>" + string$(transpose) + "</chromatic></transpose>" + newline$
    endif
    
    xml$ = xml$ + "      </attributes>" + newline$
    
    # Note
    xml$ = xml$ + "      <note>" + newline$
    xml$ = xml$ + "        <pitch>" + newline$
    xml$ = xml$ + "          <step>" + step$ + "</step>" + newline$
    if abs(total_alter) > 0.01
        xml$ = xml$ + "          <alter>" + fixed$(total_alter, 2) + "</alter>" + newline$
    endif
    xml$ = xml$ + "          <octave>" + string$(octave) + "</octave>" + newline$
    xml$ = xml$ + "        </pitch>" + newline$
    xml$ = xml$ + "        <duration>4</duration>" + newline$
    xml$ = xml$ + "        <type>whole</type>" + newline$
    
    # Microtonal accidental
    # v0.3: Extended ranges so three-quarter-tone alterations (62.5-87.5
    # cents) get a proper <accidental> element. v0.2 only covered up
    # to 62.5 cents, leaving wider microtones with <alter> only and no
    # accidental glyph.
    if enable_microtones and abs(cents_dev) > 10
        abs_cents = abs(cents_dev)
        if abs_cents >= 62.5 and abs_cents <= 87.5
            if cents_dev > 0
                accidental$ = "three-quarters-sharp"
            else
                accidental$ = "three-quarters-flat"
            endif
            xml$ = xml$ + "        <accidental>" + accidental$ + "</accidental>" + newline$
        elsif abs_cents >= 37.5 and abs_cents < 62.5
            if cents_dev > 0
                accidental$ = "quarter-sharp"
            else
                accidental$ = "quarter-flat"
            endif
            xml$ = xml$ + "        <accidental>" + accidental$ + "</accidental>" + newline$
        elsif abs_cents >= 12.5 and abs_cents < 37.5
            if cents_dev > 0
                accidental$ = "sharp-up"
            else
                accidental$ = "flat-down"
            endif
            xml$ = xml$ + "        <accidental>" + accidental$ + "</accidental>" + newline$
        endif
    endif
    
    # Dynamics
    xml$ = xml$ + "        <notations>" + newline$
    xml$ = xml$ + "          <dynamics><" + target_dynamic$ + "/></dynamics>" + newline$
    xml$ = xml$ + "        </notations>" + newline$
    xml$ = xml$ + "      </note>" + newline$
    xml$ = xml$ + "    </measure>" + newline$
    xml$ = xml$ + "  </part>" + newline$
endfor

xml$ = xml$ + "</score-partwise>" + newline$

# ============================================================================
# OUTPUT
# ============================================================================

if save_xml_file
    filename$ = sound_name$ + "_SpectraScore.musicxml"
    writeFile: filename$, xml$
    appendInfoLine: "Saved: ", filename$
endif

appendInfoLine: ""
appendInfoLine: "=== MUSICXML OUTPUT ==="
appendInfoLine: xml$

# ============================================================================
# VISUALIZATION
# ============================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "SpectraScore v0.3: " + sound_name$
    
    # Spectral analysis display
    Select outer viewport: 0, 4, 0.8, 3.5
    Select inner viewport: 0.5, 3.8, 1.0, 3.3
    
    Axes: 0, 7, 0, 0.5
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 7, 0, 0.5
    
    # Draw band energies
    Colour: "{0.3, 0.5, 0.8}"
    Paint rectangle: "{0.3, 0.5, 0.8}", 0.1, 0.9, 0, band_energy_1
    Paint rectangle: "{0.4, 0.6, 0.8}", 1.1, 1.9, 0, band_energy_2
    Paint rectangle: "{0.5, 0.7, 0.8}", 2.1, 2.9, 0, band_energy_3
    Paint rectangle: "{0.6, 0.7, 0.7}", 3.1, 3.9, 0, band_energy_4
    Paint rectangle: "{0.7, 0.6, 0.6}", 4.1, 4.9, 0, band_energy_5
    Paint rectangle: "{0.8, 0.5, 0.5}", 5.1, 5.9, 0, band_energy_6
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Spectral Band Energy"
    Font size: 6
    Text: 0.5, "centre", -0.05, "half", "50-200"
    Text: 1.5, "centre", -0.05, "half", "200-500"
    Text: 2.5, "centre", -0.05, "half", "500-1k"
    Text: 3.5, "centre", -0.05, "half", "1k-2k"
    Text: 4.5, "centre", -0.05, "half", "2k-5k"
    Text: 5.5, "centre", -0.05, "half", "5k-10k"
    
    # Orchestration result
    Select outer viewport: 4, 8, 0.8, 3.5
    Select inner viewport: 4.5, 7.8, 1.0, 3.3
    
    Axes: 0, 130, 0, best_n + 1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 130, 0, best_n + 1
    
    # Draw instrument ranges and notes
    for p from 1 to best_n
        idx = best_inst_'p'
        yPos = best_n - p + 1
        
        low = inst_midi_low_'idx'
        high = inst_midi_high_'idx'
        note_midi = voicing_midi_'p'
        
        # Range bar
        Colour: "{0.8, 0.8, 0.8}"
        Paint rectangle: "{0.85, 0.85, 0.85}", low, high, yPos - 0.3, yPos + 0.3
        
        # Note marker
        Colour: "{0.9, 0.4, 0.3}"
        Paint circle (mm): "{0.9, 0.4, 0.3}", note_midi, yPos, 3
        
        # Label
        Colour: "Black"
        Font size: 8
        Text: 5, "left", yPos, "half", inst_name_'idx'$
    endfor
    
    # Target MIDI line
    Colour: "{0.3, 0.6, 0.3}"
    Dotted line
    Draw line: target_midi, 0, target_midi, best_n + 1
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Orchestration (MIDI range)"
    Font size: 6
    Text bottom: "yes", "MIDI Note"
    
    # Info panel
    Select outer viewport: 0, 8, 3.7, 4.3
    Font size: 8
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.5, "centre", 0.5, "half", "F0: " + fixed$(target_f0, 1) + " Hz | Dynamic: " + target_dynamic$ + " | Centroid: " + fixed$(target_centroid, 0) + " Hz | Score: " + fixed$(best_score, 4)
    
    Font size: 10
    Colour: "Black"
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="