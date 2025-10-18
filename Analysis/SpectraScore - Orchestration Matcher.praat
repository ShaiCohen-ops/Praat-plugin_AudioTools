# ============================================================
# Praat AudioTools - SpectraScore.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SpectraScore - Orchestration Matcher for Praat
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
clearinfo
# SpectraScore - Orchestration Matcher for Praat
# Analyzes target sound and suggests instrument combinations
# Output: MusicXML orchestrated chord

form SpectraScore: Orchestration Analysis
    comment Select instruments to include in search:
    boolean BTb 1
    boolean Bn 1
    boolean Cb 1
    boolean ClVv 1
    boolean Fl 1
    boolean Hn 1
    boolean Ob 1
    boolean Tbn 1
    boolean TpC 1
    boolean Va 1
    boolean Vc 1
    boolean Vn 1
    comment Search parameters:
    integer max_combination_size 4
    boolean allow_divisi 0
    real loudness_overshoot_limit_(dB) 6
    comment Orchestration strategy:
    optionmenu voicing_strategy 4
        option Unison (all on root)
        option Octaves (spread across octaves)
        option Chord (root + fifth + octave)
        option Spectral (match harmonic bands)
    comment Microtonal tuning:
    boolean enable_microtones 1
    real microtone_precision_(cents) 12.5
    comment Spectral harmonic range (use 7-16 for microtones):
    integer min_harmonic 7
    integer max_harmonic 16
endform

# ============================================================================
# INSTRUMENT DATABASE
# ============================================================================
# Format: name, MIDI_low, MIDI_high, transposition_semitones, clef
# Timbre stats: centroid_pp, centroid_mf, centroid_ff, spread_pp, spread_mf, spread_ff, odd_even_ratio, inharmonicity

# Initialize instrument database
instruments$ = ""
n_instruments = 0

procedure addInstrument: .name$, .midi_low, .midi_high, .transpose, .clef$, .cent_pp, .cent_mf, .cent_ff, .spr_pp, .spr_mf, .spr_ff, .odd_even, .inharm
    n_instruments += 1
    inst_name$[n_instruments] = .name$
    inst_midi_low[n_instruments] = .midi_low
    inst_midi_high[n_instruments] = .midi_high
    inst_transpose[n_instruments] = .transpose
    inst_clef$[n_instruments] = .clef$
    inst_cent_pp[n_instruments] = .cent_pp
    inst_cent_mf[n_instruments] = .cent_mf
    inst_cent_ff[n_instruments] = .cent_ff
    inst_spr_pp[n_instruments] = .spr_pp
    inst_spr_mf[n_instruments] = .spr_mf
    inst_spr_ff[n_instruments] = .spr_ff
    inst_odd_even[n_instruments] = .odd_even
    inst_inharm[n_instruments] = .inharm
    inst_enabled[n_instruments] = 0
endproc

# Bass Trombone
if bTb
    @addInstrument: "BTb", 28, 60, 0, "bass", 350, 450, 600, 200, 280, 400, 0.65, 0.02
endif

# Bassoon
if bn
    @addInstrument: "Bn", 34, 75, 0, "bass", 400, 520, 680, 220, 300, 420, 0.70, 0.03
endif

# Contrabass
if cb
    @addInstrument: "Cb", 28, 67, -12, "bass", 280, 380, 520, 180, 250, 350, 0.60, 0.04
endif

# Clarinet (Bb)
if clVv
    @addInstrument: "ClVv", 50, 94, 2, "treble", 800, 1100, 1500, 400, 550, 750, 0.55, 0.02
endif

# Flute
if fl
    @addInstrument: "Fl", 60, 96, 0, "treble", 1200, 1600, 2200, 600, 800, 1100, 0.50, 0.01
endif

# Horn (F)
if hn
    @addInstrument: "Hn", 34, 77, -7, "treble", 450, 600, 850, 250, 350, 500, 0.68, 0.03
endif

# Oboe
if ob
    @addInstrument: "Ob", 58, 91, 0, "treble", 1000, 1350, 1800, 500, 650, 900, 0.72, 0.02
endif

# Trombone
if tbn
    @addInstrument: "Tbn", 40, 72, 0, "bass", 380, 500, 680, 210, 290, 410, 0.67, 0.02
endif

# Trumpet (C)
if tpC
    @addInstrument: "TpC", 52, 82, 0, "treble", 1100, 1500, 2100, 550, 750, 1000, 0.58, 0.02
endif

# Viola
if va
    @addInstrument: "Va", 48, 84, 0, "alto", 600, 850, 1200, 320, 450, 650, 0.62, 0.02
endif

# Cello
if vc
    @addInstrument: "Vc", 36, 76, 0, "bass", 400, 580, 820, 240, 340, 480, 0.64, 0.03
endif

# Violin
if vn
    @addInstrument: "Vn", 55, 103, 0, "treble", 900, 1250, 1750, 450, 600, 850, 0.60, 0.02
endif

if n_instruments = 0
    exitScript: "No instruments selected!"
endif

# ============================================================================
# ANALYZE TARGET SOUND
# ============================================================================
sound = selected("Sound")
sound_name$ = selected$("Sound")
duration = Get total duration

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

# 3. HARMONICITY (voicedness)
selectObject: sound
harmonicity = To Harmonicity (cc): 0.01, 75, 0.1, 1
target_hnr = Get mean: 0, 0

# 4. SPECTRAL ANALYSIS
selectObject: sound
spectrum = To Spectrum: "yes"
target_centroid = Get centre of gravity: 2
target_spread = Get standard deviation: 2

# Get spectral energy in bands for orchestration
selectObject: spectrum
band_energy[1] = Get band energy: 50, 200
band_energy[2] = Get band energy: 200, 500
band_energy[3] = Get band energy: 500, 1000
band_energy[4] = Get band energy: 1000, 2000
band_energy[5] = Get band energy: 2000, 5000
band_energy[6] = Get band energy: 5000, 10000

# Normalize band energies
total_energy = 0
for b to 6
    total_energy += band_energy[b]
endfor
if total_energy > 0
    for b to 6
        band_energy[b] = band_energy[b] / total_energy
    endfor
endif

# Estimate odd/even ratio (simplified)
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
appendInfoLine: "Intensity: ", fixed$(target_db, 1), " dB → ", target_dynamic$
appendInfoLine: "HNR: ", fixed$(target_hnr, 1), " dB"
appendInfoLine: "Centroid: ", fixed$(target_centroid, 0), " Hz"
appendInfoLine: "Spread: ", fixed$(target_spread, 0), " Hz"
appendInfoLine: "Spectral bands: ", fixed$(band_energy[1], 3), " ", fixed$(band_energy[2], 3), " ", fixed$(band_energy[3], 3), " ", fixed$(band_energy[4], 3), " ", fixed$(band_energy[5], 3), " ", fixed$(band_energy[6], 3)
appendInfoLine: "Harmonic range: H", min_harmonic, " to H", max_harmonic
if voicing_strategy = 4
    appendInfoLine: "Target harmonics:"
    for h from min_harmonic to min(max_harmonic, 16)
        h_freq = target_f0 * h
        appendInfoLine: "  H", h, " = ", fixed$(h_freq, 1), " Hz"
    endfor
endif
appendInfoLine: ""

# ============================================================================
# VOICING STRATEGIES
# ============================================================================

procedure assignVoicing: .inst_idx, .position, .n_total
    # Assign MIDI note based on voicing strategy
    # .position = 1, 2, 3, ... (this instrument's position in the ensemble)
    # .n_total = total number of instruments
    
    .target_freq = target_f0
    .cents_offset = 0
    
    if voicing_strategy = 1
        # Unison - everyone on root
        .midi_note = target_midi
        
    elsif voicing_strategy = 2
        # Octaves - spread across octaves based on instrument brightness
        if dyn_idx = 1
            inst_brightness = inst_cent_pp[.inst_idx]
        elsif dyn_idx = 2
            inst_brightness = inst_cent_mf[.inst_idx]
        else
            inst_brightness = inst_cent_ff[.inst_idx]
        endif
        
        # Dark instruments go low, bright go high
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
        # Chord - root, fifth, octave
        if .n_total = 1
            .midi_note = target_midi
            .target_freq = target_f0
        elsif .n_total = 2
            if .position = 1
                .midi_note = target_midi
                .target_freq = target_f0
            else
                .midi_note = target_midi + 7
                .target_freq = target_f0 * 1.5
            endif
        elsif .n_total = 3
            if .position = 1
                .midi_note = target_midi
                .target_freq = target_f0
            elsif .position = 2
                .midi_note = target_midi + 7
                .target_freq = target_f0 * 1.5
            else
                .midi_note = target_midi + 12
                .target_freq = target_f0 * 2
            endif
        else
            # 4+ instruments: root, third, fifth, octave
            if .position = 1
                .midi_note = target_midi
                .target_freq = target_f0
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
        # Spectral - assign instruments to frequency bands they should reinforce
        if dyn_idx = 1
            inst_brightness = inst_cent_pp[.inst_idx]
        elsif dyn_idx = 2
            inst_brightness = inst_cent_mf[.inst_idx]
        else
            inst_brightness = inst_cent_ff[.inst_idx]
        endif
        
        # Find which harmonic this instrument should reinforce
        # Based on matching instrument brightness to harmonic frequency
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
        
        # Calculate exact harmonic frequency
        .target_freq = target_f0 * harmonic
        
        # Convert to MIDI (exact, with microtones)
        .midi_note_exact = 69 + 12 * log2(.target_freq / 440)
        .midi_note = round(.midi_note_exact)
        
        # Calculate cent deviation from rounded MIDI note
        .cents_offset = (.midi_note_exact - .midi_note) * 100
        
        # Apply microtone quantization if enabled
        if enable_microtones and microtone_precision > 0
            .cents_offset = round(.cents_offset / microtone_precision) * microtone_precision
        elsif not enable_microtones
            .cents_offset = 0
        endif
    endif
    
    # Ensure note is in instrument range
    if .midi_note < inst_midi_low[.inst_idx]
        .midi_note += 12
        .target_freq *= 2
    endif
    if .midi_note > inst_midi_high[.inst_idx]
        .midi_note -= 12
        .target_freq /= 2
    endif
    
    # Final range check
    if .midi_note < inst_midi_low[.inst_idx] or .midi_note > inst_midi_high[.inst_idx]
        .midi_note = target_midi
        .target_freq = target_f0
        .cents_offset = 0
    endif
endproc

# ============================================================================
# INSTRUMENT MATCHING ENGINE
# ============================================================================

# Score single instrument against target
procedure scoreInstrument: .inst_idx, .target_cent, .target_spr, .target_oe
    # Select timbre stats based on dynamic
    if dyn_idx = 1
        .cent = inst_cent_pp[.inst_idx]
        .spr = inst_spr_pp[.inst_idx]
    elsif dyn_idx = 2
        .cent = inst_cent_mf[.inst_idx]
        .spr = inst_spr_mf[.inst_idx]
    else
        .cent = inst_cent_ff[.inst_idx]
        .spr = inst_spr_ff[.inst_idx]
    endif
    
    .oe = inst_odd_even[.inst_idx]
    
    # Weighted distance (normalized)
    .d_cent = abs(.cent - .target_cent) / 2000
    .d_spr = abs(.spr - .target_spr) / 1000
    .d_oe = abs(.oe - .target_oe)
    
    .score = .d_cent + .d_spr + 0.5 * .d_oe
endproc

# Check if instrument can play the MIDI note
procedure canPlay: .inst_idx, .midi_note
    .can = (.midi_note >= inst_midi_low[.inst_idx] and .midi_note <= inst_midi_high[.inst_idx])
endproc

# ============================================================================
# SEARCH COMBINATIONS
# ============================================================================

best_score = 1e10
best_n = 0

appendInfoLine: "=== SEARCHING COMBINATIONS ==="
appendInfoLine: "Search space: K=1..", max_combination_size, " from ", n_instruments, " instruments"

# Single instruments (K=1)
appendInfoLine: "Searching K=1..."
for i to n_instruments
    @canPlay: i, target_midi
    if canPlay.can
        @scoreInstrument: i, target_centroid, target_spread, target_odd_even
        if scoreInstrument.score < best_score
            best_score = scoreInstrument.score
            best_n = 1
            best_inst[1] = i
            appendInfoLine: "  Found better: ", inst_name$[i], " (score=", fixed$(scoreInstrument.score, 4), ")"
        endif
    endif
endfor

# Pairs (K=2)
if max_combination_size >= 2
    appendInfoLine: "Searching K=2..."
    for i to n_instruments - 1
        @canPlay: i, target_midi
        if canPlay.can
            for j from i+1 to n_instruments
                # Check divisi rule
                if not allow_divisi and inst_name$[i] = inst_name$[j]
                    ; skip
                else
                    @canPlay: j, target_midi
                    if canPlay.can
                        # Simulate spectral mixing (simplified)
                        if dyn_idx = 1
                            mix_cent = (inst_cent_pp[i] + inst_cent_pp[j]) / 2
                            mix_spr = (inst_spr_pp[i] + inst_spr_pp[j]) / 2
                        elsif dyn_idx = 2
                            mix_cent = (inst_cent_mf[i] + inst_cent_mf[j]) / 2
                            mix_spr = (inst_spr_mf[i] + inst_spr_mf[j]) / 2
                        else
                            mix_cent = (inst_cent_ff[i] + inst_cent_ff[j]) / 2
                            mix_spr = (inst_spr_ff[i] + inst_spr_ff[j]) / 2
                        endif
                        mix_oe = (inst_odd_even[i] + inst_odd_even[j]) / 2
                        
                        # Rescore combination
                        @scoreInstrument: i, mix_cent, mix_spr, mix_oe
                        combo_score = scoreInstrument.score
                        
                        if combo_score < best_score
                            best_score = combo_score
                            best_n = 2
                            best_inst[1] = i
                            best_inst[2] = j
                            appendInfoLine: "  Found better: ", inst_name$[i], "+", inst_name$[j], " (score=", fixed$(combo_score, 4), ")"
                        endif
                    endif
                endif
            endfor
        endif
    endfor
endif

# Triples (K=3)
if max_combination_size >= 3
    appendInfoLine: "Searching K=3..."
    for i to n_instruments - 2
        @canPlay: i, target_midi
        if canPlay.can
            for j from i+1 to n_instruments - 1
                @canPlay: j, target_midi
                if canPlay.can
                    for k from j+1 to n_instruments
                        @canPlay: k, target_midi
                        if canPlay.can
                            # Mix three spectra
                            if dyn_idx = 1
                                mix_cent = (inst_cent_pp[i] + inst_cent_pp[j] + inst_cent_pp[k]) / 3
                                mix_spr = (inst_spr_pp[i] + inst_spr_pp[j] + inst_spr_pp[k]) / 3
                            elsif dyn_idx = 2
                                mix_cent = (inst_cent_mf[i] + inst_cent_mf[j] + inst_cent_mf[k]) / 3
                                mix_spr = (inst_spr_mf[i] + inst_spr_mf[j] + inst_spr_mf[k]) / 3
                            else
                                mix_cent = (inst_cent_ff[i] + inst_cent_ff[j] + inst_cent_ff[k]) / 3
                                mix_spr = (inst_spr_ff[i] + inst_spr_ff[j] + inst_spr_ff[k]) / 3
                            endif
                            mix_oe = (inst_odd_even[i] + inst_odd_even[j] + inst_odd_even[k]) / 3
                            
                            @scoreInstrument: i, mix_cent, mix_spr, mix_oe
                            combo_score = scoreInstrument.score
                            
                            if combo_score < best_score
                                best_score = combo_score
                                best_n = 3
                                best_inst[1] = i
                                best_inst[2] = j
                                best_inst[3] = k
                                appendInfoLine: "  Found better: ", inst_name$[i], "+", inst_name$[j], "+", inst_name$[k], " (score=", fixed$(combo_score, 4), ")"
                            endif
                        endif
                    endfor
                endif
            endfor
        endif
    endfor
endif

# Quadruples (K=4)
if max_combination_size >= 4
    appendInfoLine: "Searching K=4..."
    for i to n_instruments - 3
        @canPlay: i, target_midi
        if canPlay.can
            for j from i+1 to n_instruments - 2
                @canPlay: j, target_midi
                if canPlay.can
                    for k from j+1 to n_instruments - 1
                        @canPlay: k, target_midi
                        if canPlay.can
                            for m from k+1 to n_instruments
                                @canPlay: m, target_midi
                                if canPlay.can
                                    # Mix four spectra
                                    if dyn_idx = 1
                                        mix_cent = (inst_cent_pp[i] + inst_cent_pp[j] + inst_cent_pp[k] + inst_cent_pp[m]) / 4
                                        mix_spr = (inst_spr_pp[i] + inst_spr_pp[j] + inst_spr_pp[k] + inst_spr_pp[m]) / 4
                                    elsif dyn_idx = 2
                                        mix_cent = (inst_cent_mf[i] + inst_cent_mf[j] + inst_cent_mf[k] + inst_cent_mf[m]) / 4
                                        mix_spr = (inst_spr_mf[i] + inst_spr_mf[j] + inst_spr_mf[k] + inst_spr_mf[m]) / 4
                                    else
                                        mix_cent = (inst_cent_ff[i] + inst_cent_ff[j] + inst_cent_ff[k] + inst_cent_ff[m]) / 4
                                        mix_spr = (inst_spr_ff[i] + inst_spr_ff[j] + inst_spr_ff[k] + inst_spr_ff[m]) / 4
                                    endif
                                    mix_oe = (inst_odd_even[i] + inst_odd_even[j] + inst_odd_even[k] + inst_odd_even[m]) / 4
                                    
                                    @scoreInstrument: i, mix_cent, mix_spr, mix_oe
                                    combo_score = scoreInstrument.score
                                    
                                    if combo_score < best_score
                                        best_score = combo_score
                                        best_n = 4
                                        best_inst[1] = i
                                        best_inst[2] = j
                                        best_inst[3] = k
                                        best_inst[4] = m
                                        appendInfoLine: "  Found better: ", inst_name$[i], "+", inst_name$[j], "+", inst_name$[k], "+", inst_name$[m], " (score=", fixed$(combo_score, 4), ")"
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
    exitScript: "No valid instrument combination found for MIDI note ", fixed$(target_midi, 1)
endif

appendInfoLine: "Best match (score=", fixed$(best_score, 4), "):"
for i to best_n
    appendInfoLine: "  ", inst_name$[best_inst[i]]
endfor
appendInfoLine: ""
appendInfoLine: "=== VOICING ASSIGNMENTS ==="
for i to best_n
    @assignVoicing: best_inst[i], i, best_n
    harmonic_num = round(assignVoicing.target_freq / target_f0)
    appendInfoLine: inst_name$[best_inst[i]], ": H", harmonic_num, " (", fixed$(assignVoicing.target_freq, 1), " Hz) → MIDI ", fixed$(assignVoicing.midi_note, 1), " + ", fixed$(assignVoicing.cents_offset, 1), " cents"
endfor
appendInfoLine: ""
appendInfoLine: "=== MICROTONAL ALTER VALUES ==="
for i to best_n
    @assignVoicing: best_inst[i], i, best_n
    inst_idx = best_inst[i]
    written_midi = assignVoicing.midi_note - inst_transpose[inst_idx]
    cents_deviation = assignVoicing.cents_offset
    pitch_class = round(written_midi) mod 12
    
    base_alter[0] = 0
    base_alter[1] = 1
    base_alter[2] = 0
    base_alter[3] = 1
    base_alter[4] = 0
    base_alter[5] = 0
    base_alter[6] = 1
    base_alter[7] = 0
    base_alter[8] = 1
    base_alter[9] = 0
    base_alter[10] = 1
    base_alter[11] = 0
    
    total_alter = base_alter[pitch_class] + (cents_deviation / 100.0)
    appendInfoLine: inst_name$[best_inst[i]], ": <alter>", fixed$(total_alter, 2), "</alter> (base=", base_alter[pitch_class], " + ", fixed$(cents_deviation, 1), "/100)"
endfor
appendInfoLine: ""

# ============================================================================
# GENERATE MUSICXML
# ============================================================================

xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$
xml$ = xml$ + "  <work><work-title>SpectraScore Output</work-title></work>" + newline$
xml$ = xml$ + "  <identification>" + newline$
xml$ = xml$ + "    <creator type=""software"">Praat SpectraScore</creator>" + newline$
xml$ = xml$ + "    <encoding><software>Praat</software></encoding>" + newline$
xml$ = xml$ + "  </identification>" + newline$

# Part list
xml$ = xml$ + "  <part-list>" + newline$
for i to best_n
    part_id$ = "P" + string$(i)
    xml$ = xml$ + "    <score-part id=""" + part_id$ + """>" + newline$
    xml$ = xml$ + "      <part-name>" + inst_name$[best_inst[i]] + "</part-name>" + newline$
    xml$ = xml$ + "    </score-part>" + newline$
endfor
xml$ = xml$ + "  </part-list>" + newline$

# Parts
for i to best_n
    part_id$ = "P" + string$(i)
    inst_idx = best_inst[i]
    
    xml$ = xml$ + "  <part id=""" + part_id$ + """>" + newline$
    xml$ = xml$ + "    <measure number=""1"">" + newline$
    xml$ = xml$ + "      <attributes>" + newline$
    xml$ = xml$ + "        <divisions>1</divisions>" + newline$
    xml$ = xml$ + "        <key><fifths>0</fifths></key>" + newline$
    xml$ = xml$ + "        <time><beats>4</beats><beat-type>4</beat-type></time>" + newline$
    # Clef line: treble (G clef on line 2), alto (C clef on line 3), bass (F clef on line 4)
    # But MusicXML counts from bottom: bass=4, treble=2, alto=3 for standard positions
    if inst_clef$[inst_idx] = "treble"
        clef_sign$ = "G"
        clef_line = 2
    elsif inst_clef$[inst_idx] = "alto"
        clef_sign$ = "C"
        clef_line = 3
    else
        clef_sign$ = "F"
        clef_line = 4
    endif
    xml$ = xml$ + "        <clef><sign>" + clef_sign$ + "</sign><line>" + string$(clef_line) + "</line></clef>" + newline$
    
    # Transposition
    if inst_transpose[inst_idx] != 0
        xml$ = xml$ + "        <transpose>" + newline$
        xml$ = xml$ + "          <chromatic>" + string$(inst_transpose[inst_idx]) + "</chromatic>" + newline$
        xml$ = xml$ + "        </transpose>" + newline$
    endif
    
    xml$ = xml$ + "      </attributes>" + newline$
    
    # Assign note based on voicing strategy
    @assignVoicing: inst_idx, i, best_n
    written_midi = assignVoicing.midi_note - inst_transpose[inst_idx]
    cents_deviation = assignVoicing.cents_offset
    pitch_class = round(written_midi) mod 12
    octave = floor(written_midi / 12) - 1
    
    step$[0] = "C"
    step$[1] = "C"
    step$[2] = "D"
    step$[3] = "D"
    step$[4] = "E"
    step$[5] = "F"
    step$[6] = "F"
    step$[7] = "G"
    step$[8] = "G"
    step$[9] = "A"
    step$[10] = "A"
    step$[11] = "B"
    
    # Base alteration (sharps/flats)
    base_alter[0] = 0
    base_alter[1] = 1
    base_alter[2] = 0
    base_alter[3] = 1
    base_alter[4] = 0
    base_alter[5] = 0
    base_alter[6] = 1
    base_alter[7] = 0
    base_alter[8] = 1
    base_alter[9] = 0
    base_alter[10] = 1
    base_alter[11] = 0
    
    # Calculate microtonal alter value (in semitones, with decimals)
    # <alter> expects semitones: 1.0 = sharp, 0.5 = quarter-tone sharp, etc.
    total_alter = base_alter[pitch_class] + (cents_deviation / 100.0)
    
    xml$ = xml$ + "      <note>" + newline$
    xml$ = xml$ + "        <pitch>" + newline$
    xml$ = xml$ + "          <step>" + step$[pitch_class] + "</step>" + newline$
    if abs(total_alter) > 0.01
        xml$ = xml$ + "          <alter>" + fixed$(total_alter, 2) + "</alter>" + newline$
    endif
    xml$ = xml$ + "          <octave>" + string$(octave) + "</octave>" + newline$
    xml$ = xml$ + "        </pitch>" + newline$
    xml$ = xml$ + "        <duration>4</duration>" + newline$
    xml$ = xml$ + "        <type>whole</type>" + newline$
    
    # Add accidental for microtones
    if enable_microtones and abs(cents_deviation) > 1
        if abs(cents_deviation) >= 37.5 and abs(cents_deviation) <= 62.5
            if cents_deviation > 0
                accidental$ = "quarter-sharp"
            else
                accidental$ = "quarter-flat"
            endif
        elsif abs(cents_deviation) >= 12.5 and abs(cents_deviation) < 37.5
            if cents_deviation > 0
                accidental$ = "sharp-up"
            else
                accidental$ = "flat-down"
            endif
        elsif abs(cents_deviation) >= 62.5 and abs(cents_deviation) <= 87.5
            if cents_deviation > 0
                accidental$ = "three-quarters-sharp"
            else
                accidental$ = "three-quarters-flat"
            endif
        else
            accidental$ = ""
        endif
        
        if accidental$ != ""
            xml$ = xml$ + "        <accidental>" + accidental$ + "</accidental>" + newline$
        endif
    endif
    
    xml$ = xml$ + "        <notations>" + newline$
    xml$ = xml$ + "          <dynamics default-x=""0"" default-y=""-40"">" + newline$
    xml$ = xml$ + "            <" + target_dynamic$ + "/>" + newline$
    xml$ = xml$ + "          </dynamics>" + newline$
    xml$ = xml$ + "        </notations>" + newline$
    xml$ = xml$ + "      </note>" + newline$
    xml$ = xml$ + "    </measure>" + newline$
    xml$ = xml$ + "  </part>" + newline$
endfor

xml$ = xml$ + "</score-partwise>" + newline$

# Output to Info window
appendInfoLine: "=== MUSICXML OUTPUT ==="
appendInfoLine: xml$

appendInfoLine: newline$, "✓ MusicXML generated successfully!"
appendInfoLine: "Copy the XML above to save to a .musicxml file"

