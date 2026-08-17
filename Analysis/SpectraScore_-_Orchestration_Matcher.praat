# ============================================================
# Praat AudioTools - SpectraScore_Orchestration_Matcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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
#
# Changelog v0.4 (2026):
#   - FIX: odd/even descriptor now measures actual odd vs even harmonic-band
#     energy around the detected F0; the previous high-band/low-band proxy was
#     not an odd/even measure.
#   - FIX: combination spectral spread now uses the variance law for an
#     equal-energy spectral mixture instead of averaging standard deviations.
#   - FIX: Bb clarinet MusicXML transposition is -2 semitones (written pitch
#     plus -2 = sounding pitch), consistent with the MusicXML transpose model.
#   - FIX: microtonal cents are derived from exact target frequency for every
#     voicing strategy, not only Spectral; common quarter-tone glyphs are
#     emitted from total alteration while arbitrary fractional <alter> values
#     remain exact.
#   - FIX: Allow repeated instruments now actually permits repeated entries in
#     K=2..4 searches; v0.3's i<j<k<m loops made the old divisi switch inert.
#   - QUALITY: pp/mf/ff instrument profile is selected explicitly rather than
#     inferred from uncalibrated digital Sound level.
#   - QUALITY: stereo/multichannel targets are analysed on the strongest RMS
#     channel, avoiding phase-cancelling fold-down.
#   - QUALITY: search rejects combinations whose actual assigned voicing is
#     outside instrument range; Spectral voicing only chooses playable target
#     harmonics.
#   - QUALITY: optional per-extra-instrument penalty prevents larger K from
#     winning merely because it has more degrees of freedom.
#   - VIS: 8x8 AudioTools report now shows adaptive band energy, playable
#     ranges/notes, target-vs-match diagnostic errors, best score by K, and a
#     concise selection summary.
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

form SpectraScore Orchestration Matcher v0.4
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
    boolean Allow_repeated_instruments 0
    real Additional_instrument_penalty 0.01
    comment Instrument spectral profile:
    optionmenu Spectral_profile_dynamic: 2
        option pp
        option mf
        option ff
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


if max_combination_size < 1 or max_combination_size > 4
    exitScript: "Max combination size must be between 1 and 4."
endif
if additional_instrument_penalty < 0
    exitScript: "Additional instrument penalty must be >= 0."
endif
if enable_microtones and microtone_precision_cents <= 0
    exitScript: "Microtone precision must be > 0 cents when microtones are enabled."
endif
if min_harmonic < 1 or max_harmonic < min_harmonic
    exitScript: "Harmonic range must satisfy 1 <= Min harmonic <= Max harmonic."
endif

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
    @addInstrument: "ClBb", 50, 94, -2, "treble", 800, 1100, 1500, 400, 550, 750, 0.55, 0.02
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

# For multichannel material, analyse the strongest RMS channel rather than
# folding to mono. This avoids phase cancellation changing the target spectrum.
selectObject: sound
n_channels = Get number of channels
analysis_sound = sound
analysis_channel = 1
analysis_sound_is_temporary = 0

if n_channels > 1
    best_channel_rms = -1
    best_channel_sound = 0
    for ch from 1 to n_channels
        selectObject: sound
        ch_sound = Extract one channel: ch
        ch_rms = Get root-mean-square: 0, 0
        if ch_rms > best_channel_rms
            if best_channel_sound <> 0
                removeObject: best_channel_sound
            endif
            best_channel_rms = ch_rms
            best_channel_sound = ch_sound
            analysis_channel = ch
        else
            removeObject: ch_sound
        endif
    endfor
    analysis_sound = best_channel_sound
    analysis_sound_is_temporary = 1
endif

selectObject: analysis_sound
duration = Get total duration
sampling_frequency = Get sampling frequency
nyquist = sampling_frequency / 2

writeInfoLine: "=== SpectraScore Orchestration Matcher v0.4 ==="
appendInfoLine: "Analyzing: ", sound_name$
if n_channels > 1
    appendInfoLine: "Analysis channel: ", analysis_channel, " of ", n_channels, " (strongest RMS)"
endif
appendInfoLine: ""

# 1. PITCH ANALYSIS
selectObject: analysis_sound
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

# 2. FILE LEVEL (descriptive only; not used to infer musical dynamic)
selectObject: analysis_sound
intensity = To Intensity: 100, 0, "yes"
target_db = Get mean: 0, 0, "dB"

# 3. HARMONICITY (descriptive)
selectObject: analysis_sound
harmonicity = To Harmonicity (cc): 0.01, 75, 0.1, 1
target_hnr = Get mean: 0, 0

# 4. SPECTRAL ANALYSIS
selectObject: analysis_sound
spectrum = To Spectrum: "yes"
target_centroid = Get centre of gravity: 2
target_spread = Get standard deviation: 2

if target_centroid = undefined or target_spread = undefined
    removeObject: pitch, intensity, harmonicity, spectrum
    if analysis_sound_is_temporary
        removeObject: analysis_sound
    endif
    exitScript: "Could not obtain a stable target spectrum."
endif

# Six broad energy bands for the report. Clip every query to Nyquist so
# low-sample-rate Sounds cannot request a band outside the Spectrum domain.
selectObject: spectrum
band_energy_1 = 0
band_energy_2 = 0
band_energy_3 = 0
band_energy_4 = 0
band_energy_5 = 0
band_energy_6 = 0

band_hi = 200
if band_hi > nyquist
    band_hi = nyquist
endif
if band_hi > 50
    band_energy_1 = Get band energy: 50, band_hi
endif

band_hi = 500
if band_hi > nyquist
    band_hi = nyquist
endif
if band_hi > 200
    band_energy_2 = Get band energy: 200, band_hi
endif

band_hi = 1000
if band_hi > nyquist
    band_hi = nyquist
endif
if band_hi > 500
    band_energy_3 = Get band energy: 500, band_hi
endif

band_hi = 2000
if band_hi > nyquist
    band_hi = nyquist
endif
if band_hi > 1000
    band_energy_4 = Get band energy: 1000, band_hi
endif

band_hi = 5000
if band_hi > nyquist
    band_hi = nyquist
endif
if band_hi > 2000
    band_energy_5 = Get band energy: 2000, band_hi
endif

band_hi = 10000
if band_hi > nyquist
    band_hi = nyquist
endif
if band_hi > 5000
    band_energy_6 = Get band energy: 5000, band_hi
endif

total_energy = band_energy_1 + band_energy_2 + band_energy_3 + band_energy_4 + band_energy_5 + band_energy_6
if total_energy > 0
    band_energy_1 = band_energy_1 / total_energy
    band_energy_2 = band_energy_2 / total_energy
    band_energy_3 = band_energy_3 / total_energy
    band_energy_4 = band_energy_4 / total_energy
    band_energy_5 = band_energy_5 / total_energy
    band_energy_6 = band_energy_6 / total_energy
endif

# True odd/even harmonic descriptor: integrate small bands around harmonics
# of the measured F0. Values near 1 mean odd-harmonic dominance.
selectObject: spectrum
odd_harmonic_energy = 0
even_harmonic_energy = 0
harmonic_halfwidth = target_f0 * 0.05
if harmonic_halfwidth < 5
    harmonic_halfwidth = 5
endif
n_harmonics_measured = floor(nyquist / target_f0)
if n_harmonics_measured > 20
    n_harmonics_measured = 20
endif

for h from 1 to n_harmonics_measured
    h_center = target_f0 * h
    h_low = h_center - harmonic_halfwidth
    h_high = h_center + harmonic_halfwidth
    if h_low < 0
        h_low = 0
    endif
    if h_high > nyquist
        h_high = nyquist
    endif
    h_energy = Get band energy: h_low, h_high
    if h mod 2 = 1
        odd_harmonic_energy = odd_harmonic_energy + h_energy
    else
        even_harmonic_energy = even_harmonic_energy + h_energy
    endif
endfor

if odd_harmonic_energy + even_harmonic_energy > 0
    target_odd_even = odd_harmonic_energy / (odd_harmonic_energy + even_harmonic_energy)
else
    target_odd_even = 0.5
endif

# The pp/mf/ff instrument profiles are a user-selected modelling choice.
# Absolute Praat Sound level is not a calibrated performance dynamic.
dyn_idx = spectral_profile_dynamic
if dyn_idx = 1
    target_dynamic$ = "pp"
elsif dyn_idx = 2
    target_dynamic$ = "mf"
else
    target_dynamic$ = "ff"
endif

# Clean up analysis objects
removeObject: pitch, intensity, harmonicity, spectrum
if analysis_sound_is_temporary
    removeObject: analysis_sound
endif

appendInfoLine: "=== TARGET ANALYSIS ==="
appendInfoLine: "F0: ", fixed$(target_f0, 2), " Hz (MIDI ", fixed$(target_midi, 1), ")"
appendInfoLine: "File intensity: ", fixed$(target_db, 1), " dB (descriptive, not dynamic inference)"
appendInfoLine: "Instrument profile: ", target_dynamic$
appendInfoLine: "HNR: ", fixed$(target_hnr, 1), " dB"
appendInfoLine: "Centroid: ", fixed$(target_centroid, 0), " Hz"
appendInfoLine: "Spread: ", fixed$(target_spread, 0), " Hz"
appendInfoLine: "Odd-harmonic fraction: ", fixed$(target_odd_even, 3)
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

# Compute the target pitch for one instrument/position and verify that the
# resulting note is playable. Microtonal deviation is derived from the exact
# target frequency for ALL voicing strategies, not spectral voicing only.
procedure assignVoicing: .inst_idx, .position, .n_total
    .low = inst_midi_low_'.inst_idx'
    .high = inst_midi_high_'.inst_idx'
    .valid = 1
    .target_freq = target_f0
    .cents_offset = 0
    .harmonic = 0

    if voicing_strategy = 1
        # True unison: do not silently octave-fold an impossible root.
        .target_freq = target_f0
        .midi_exact = target_midi
        if .midi_exact < .low or .midi_exact > .high
            .valid = 0
        endif

    elsif voicing_strategy = 2
        # Octaves - spread by instrument brightness.
        @getInstCentroid: .inst_idx
        .inst_brightness = getInstCentroid.result
        if .inst_brightness < 500
            .target_freq = target_f0 / 2
        elsif .inst_brightness > 1200
            .target_freq = target_f0 * 2
        else
            .target_freq = target_f0
        endif

        .midi_exact = 69 + 12 * log2(.target_freq / 440)
        while .midi_exact < .low
            .target_freq = .target_freq * 2
            .midi_exact = .midi_exact + 12
        endwhile
        while .midi_exact > .high
            .target_freq = .target_freq / 2
            .midi_exact = .midi_exact - 12
        endwhile
        if .midi_exact < .low or .midi_exact > .high
            .valid = 0
        endif

    elsif voicing_strategy = 3
        # Chord voicing. Ratios are intentional musical intervals; if a pitch
        # is outside the instrument range, octave-displace it while preserving
        # pitch class / interval identity.
        if .n_total = 1
            .target_freq = target_f0
        elsif .n_total = 2
            if .position = 1
                .target_freq = target_f0
            else
                .target_freq = target_f0 * 1.5
            endif
        elsif .n_total = 3
            if .position = 1
                .target_freq = target_f0
            elsif .position = 2
                .target_freq = target_f0 * 1.5
            else
                .target_freq = target_f0 * 2
            endif
        else
            if .position = 1
                .target_freq = target_f0
            elsif .position = 2
                .target_freq = target_f0 * 1.26
            elsif .position = 3
                .target_freq = target_f0 * 1.5
            else
                .target_freq = target_f0 * 2
            endif
        endif

        .midi_exact = 69 + 12 * log2(.target_freq / 440)
        while .midi_exact < .low
            .target_freq = .target_freq * 2
            .midi_exact = .midi_exact + 12
        endwhile
        while .midi_exact > .high
            .target_freq = .target_freq / 2
            .midi_exact = .midi_exact - 12
        endwhile
        if .midi_exact < .low or .midi_exact > .high
            .valid = 0
        endif

    else
        # Spectral: choose the centroid-nearest TARGET HARMONIC that is
        # actually inside this instrument's range; do not fold a non-playable
        # harmonic into a non-integer harmonic by octave displacement.
        @getInstCentroid: .inst_idx
        .inst_brightness = getInstCentroid.result
        .found = 0
        .min_diff = 1e30

        for .h from min_harmonic to max_harmonic
            .harm_freq = target_f0 * .h
            .harm_midi = 69 + 12 * log2(.harm_freq / 440)
            if .harm_midi >= .low and .harm_midi <= .high
                .diff = abs(.inst_brightness - .harm_freq)
                if .diff < .min_diff
                    .min_diff = .diff
                    .harmonic = .h
                    .target_freq = .harm_freq
                    .midi_exact = .harm_midi
                    .found = 1
                endif
            endif
        endfor

        if not .found
            .valid = 0
        endif
    endif

    if .valid
        .midi_note = round(.midi_exact)
        .cents_offset = (.midi_exact - .midi_note) * 100
        if enable_microtones
            .cents_offset = round(.cents_offset / microtone_precision_cents) * microtone_precision_cents
        else
            .cents_offset = 0
        endif
    else
        .midi_note = undefined
        .cents_offset = 0
        .target_freq = undefined
    endif
endproc

procedure comboPlayable: .n_in_combo
    .can = 1
    for .pos from 1 to .n_in_combo
        .ix = combo_idx_'.pos'
        @assignVoicing: .ix, .pos, .n_in_combo
        if not assignVoicing.valid
            .can = 0
        endif
    endfor
endproc

# Equal-energy spectral mixture. The centroid is the mean centroid, while the
# mixture variance obeys E[var + mean^2] - mixture_mean^2; averaging standard
# deviations directly underestimates spread when component centroids differ.
procedure scoreCombo: .n_in_combo
    .sum_cent = 0
    .sum_second = 0
    .sum_oe = 0

    for .pos from 1 to .n_in_combo
        .ix = combo_idx_'.pos'
        @getInstCentroid: .ix
        .cent = getInstCentroid.result
        @getInstSpread: .ix
        .spr = getInstSpread.result

        .sum_cent = .sum_cent + .cent
        .sum_second = .sum_second + .spr * .spr + .cent * .cent
        .sum_oe = .sum_oe + inst_odd_even_'.ix'
    endfor

    .mix_cent = .sum_cent / .n_in_combo
    .mix_var = .sum_second / .n_in_combo - .mix_cent * .mix_cent
    if .mix_var < 0
        .mix_var = 0
    endif
    .mix_spr = sqrt(.mix_var)
    .mix_oe = .sum_oe / .n_in_combo

    .d_cent = abs(.mix_cent - target_centroid) / 2000
    .d_spr = abs(.mix_spr - target_spread) / 1000
    .d_oe = abs(.mix_oe - target_odd_even)
    .raw_score = .d_cent + .d_spr + 0.5 * .d_oe
    .size_penalty = additional_instrument_penalty * (.n_in_combo - 1)
    .score = .raw_score + .size_penalty
endproc

procedure xmlEscape: .s$
    .s$ = replace_regex$(.s$, "&", "&amp;", 0)
    .s$ = replace_regex$(.s$, "<", "&lt;", 0)
    .s$ = replace_regex$(.s$, ">", "&gt;", 0)
    .result$ = .s$
endproc

# ============================================================================
# SEARCH COMBINATIONS
# ============================================================================

best_score = 1e30
best_raw_score = 1e30
best_n = 0
best_score_k1 = 1e30
best_score_k2 = 1e30
best_score_k3 = 1e30
best_score_k4 = 1e30

appendInfoLine: "=== SEARCHING COMBINATIONS ==="
appendInfoLine: "Instruments available: ", n_instruments
appendInfoLine: "Max combination size: ", max_combination_size
appendInfoLine: "Additional-instrument penalty: ", fixed$(additional_instrument_penalty, 3)
if allow_repeated_instruments
    appendInfoLine: "Repeated instruments: allowed"
else
    appendInfoLine: "Repeated instruments: off"
endif
appendInfoLine: ""

# K=1
appendInfoLine: "Searching K=1..."
for i from 1 to n_instruments
    combo_idx_1 = i
    @comboPlayable: 1
    if comboPlayable.can
        @scoreCombo: 1
        if scoreCombo.score < best_score_k1
            best_score_k1 = scoreCombo.score
        endif
        if scoreCombo.score < best_score
            best_score = scoreCombo.score
            best_raw_score = scoreCombo.raw_score
            best_n = 1
            best_inst_1 = i
        endif
    endif
endfor

# K=2
if max_combination_size >= 2
    appendInfoLine: "Searching K=2..."
    for i from 1 to n_instruments
        j_start = i + 1
        if allow_repeated_instruments
            j_start = i
        endif
        if j_start <= n_instruments
            for j from j_start to n_instruments
                combo_idx_1 = i
                combo_idx_2 = j
                @comboPlayable: 2
                if comboPlayable.can
                    @scoreCombo: 2
                    if scoreCombo.score < best_score_k2
                        best_score_k2 = scoreCombo.score
                    endif
                    if scoreCombo.score < best_score
                        best_score = scoreCombo.score
                        best_raw_score = scoreCombo.raw_score
                        best_n = 2
                        best_inst_1 = i
                        best_inst_2 = j
                    endif
                endif
            endfor
        endif
    endfor
endif

# K=3
if max_combination_size >= 3
    appendInfoLine: "Searching K=3..."
    for i from 1 to n_instruments
        j_start = i + 1
        if allow_repeated_instruments
            j_start = i
        endif
        if j_start <= n_instruments
            for j from j_start to n_instruments
                k_start = j + 1
                if allow_repeated_instruments
                    k_start = j
                endif
                if k_start <= n_instruments
                    for k from k_start to n_instruments
                        combo_idx_1 = i
                        combo_idx_2 = j
                        combo_idx_3 = k
                        @comboPlayable: 3
                        if comboPlayable.can
                            @scoreCombo: 3
                            if scoreCombo.score < best_score_k3
                                best_score_k3 = scoreCombo.score
                            endif
                            if scoreCombo.score < best_score
                                best_score = scoreCombo.score
                                best_raw_score = scoreCombo.raw_score
                                best_n = 3
                                best_inst_1 = i
                                best_inst_2 = j
                                best_inst_3 = k
                            endif
                        endif
                    endfor
                endif
            endfor
        endif
    endfor
endif

# K=4
if max_combination_size >= 4
    appendInfoLine: "Searching K=4..."
    for i from 1 to n_instruments
        j_start = i + 1
        if allow_repeated_instruments
            j_start = i
        endif
        if j_start <= n_instruments
            for j from j_start to n_instruments
                k_start = j + 1
                if allow_repeated_instruments
                    k_start = j
                endif
                if k_start <= n_instruments
                    for k from k_start to n_instruments
                        m_start = k + 1
                        if allow_repeated_instruments
                            m_start = k
                        endif
                        if m_start <= n_instruments
                            for m from m_start to n_instruments
                                combo_idx_1 = i
                                combo_idx_2 = j
                                combo_idx_3 = k
                                combo_idx_4 = m
                                @comboPlayable: 4
                                if comboPlayable.can
                                    @scoreCombo: 4
                                    if scoreCombo.score < best_score_k4
                                        best_score_k4 = scoreCombo.score
                                    endif
                                    if scoreCombo.score < best_score
                                        best_score = scoreCombo.score
                                        best_raw_score = scoreCombo.raw_score
                                        best_n = 4
                                        best_inst_1 = i
                                        best_inst_2 = j
                                        best_inst_3 = k
                                        best_inst_4 = m
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
    exitScript: "No playable instrument combination found for the selected voicing strategy and ranges."
endif

# Recompute descriptors for the selected combination for reporting/visualization.
for p from 1 to best_n
    combo_idx_'p' = best_inst_'p'
endfor
@scoreCombo: best_n
best_mix_centroid = scoreCombo.mix_cent
best_mix_spread = scoreCombo.mix_spr
best_mix_odd_even = scoreCombo.mix_oe

appendInfoLine: ""
appendInfoLine: "=== BEST MATCH ==="
appendInfoLine: "Selection score: ", fixed$(best_score, 4), "  (acoustic=", fixed$(best_raw_score, 4), ", size penalty=", fixed$(best_score - best_raw_score, 4), ")"
appendInfoLine: "Matched centroid: ", fixed$(best_mix_centroid, 0), " Hz"
appendInfoLine: "Matched spread: ", fixed$(best_mix_spread, 0), " Hz"
appendInfoLine: "Matched odd-harmonic fraction: ", fixed$(best_mix_odd_even, 3)
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
        harmonic_num = assignVoicing.harmonic
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

@xmlEscape: sound_name$
xml_sound_name$ = xmlEscape.result$

xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$
xml$ = xml$ + "  <work><work-title>SpectraScore: " + xml_sound_name$ + "</work-title></work>" + newline$
xml$ = xml$ + "  <identification>" + newline$
xml$ = xml$ + "    <creator type=""software"">Praat SpectraScore v0.4</creator>" + newline$
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
    
    # Explicit accidental glyph only when the total alteration lands on a
    # standard quarter-tone / three-quarter-tone symbol. <alter> above always
    # carries the exact fractional semitone value, including 12.5-cent grids.
    if enable_microtones and abs(cents_dev) > 0.01
        accidental$ = ""
        if abs(total_alter - 0.5) < 0.06
            accidental$ = "quarter-sharp"
        elsif abs(total_alter - 1.5) < 0.06
            accidental$ = "three-quarters-sharp"
        elsif abs(total_alter + 0.5) < 0.06
            accidental$ = "quarter-flat"
        elsif abs(total_alter + 1.5) < 0.06
            accidental$ = "three-quarters-flat"
        endif
        if accidental$ <> ""
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
    Select outer viewport: 0, 8, 0, 8

    # ---------- title / metadata ----------
    Select outer viewport: 0, 8, 0.00, 0.42
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "##SpectraScore Orchestration Matcher##"

    Select outer viewport: 0, 8, 0.43, 0.78
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.35, 0.35, 0.45}"
    vizMeta$ = sound_name$ + "  |  F0 " + fixed$(target_f0, 1) + " Hz  |  profile " + target_dynamic$ + "  |  K=" + string$(best_n) + "  |  score " + fixed$(best_score, 3)
    Text: 0.5, "centre", 0.50, "half", vizMeta$

    # ---------- spectral band energy ----------
    vizBandMax = band_energy_1
    if band_energy_2 > vizBandMax
        vizBandMax = band_energy_2
    endif
    if band_energy_3 > vizBandMax
        vizBandMax = band_energy_3
    endif
    if band_energy_4 > vizBandMax
        vizBandMax = band_energy_4
    endif
    if band_energy_5 > vizBandMax
        vizBandMax = band_energy_5
    endif
    if band_energy_6 > vizBandMax
        vizBandMax = band_energy_6
    endif
    vizBandY = vizBandMax * 1.18
    if vizBandY < 0.25
        vizBandY = 0.25
    endif

    Select outer viewport: 0.25, 3.90, 0.95, 3.45
    Select inner viewport: 0.72, 3.72, 1.20, 3.25
    Axes: 0, 6, 0, vizBandY
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 6, 0, vizBandY
    Paint rectangle: "{0.30, 0.50, 0.80}", 0.10, 0.90, 0, band_energy_1
    Paint rectangle: "{0.40, 0.60, 0.80}", 1.10, 1.90, 0, band_energy_2
    Paint rectangle: "{0.50, 0.70, 0.80}", 2.10, 2.90, 0, band_energy_3
    Paint rectangle: "{0.60, 0.70, 0.70}", 3.10, 3.90, 0, band_energy_4
    Paint rectangle: "{0.70, 0.60, 0.60}", 4.10, 4.90, 0, band_energy_5
    Paint rectangle: "{0.80, 0.50, 0.50}", 5.10, 5.90, 0, band_energy_6

    Select inner viewport: 0.72, 3.72, 1.20, 3.25
    Axes: 0, 6, 0, vizBandY
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Font size: 9
    Text top: "no", "##Target spectral energy##"
    Font size: 6
    Text bottom: "no", "Band: 50-200 | 200-500 | 500-1k | 1-2k | 2-5k | 5-10k"

    # ---------- orchestration ranges ----------
    vizXLow = 127
    vizXHigh = 0
    for vizP from 1 to best_n
        vizIdx = best_inst_'vizP'
        vizLo = inst_midi_low_'vizIdx'
        vizHi = inst_midi_high_'vizIdx'
        if vizLo < vizXLow
            vizXLow = vizLo
        endif
        if vizHi > vizXHigh
            vizXHigh = vizHi
        endif
    endfor
    if target_midi < vizXLow
        vizXLow = floor(target_midi)
    endif
    if target_midi > vizXHigh
        vizXHigh = ceil(target_midi)
    endif
    vizXLow = vizXLow - 4
    vizXHigh = vizXHigh + 4
    if vizXLow < 0
        vizXLow = 0
    endif
    if vizXHigh > 127
        vizXHigh = 127
    endif

    Select outer viewport: 4.10, 7.80, 0.95, 3.45
    Select inner viewport: 4.55, 7.62, 1.20, 3.25
    Axes: vizXLow, vizXHigh, 0, best_n + 1
    Paint rectangle: "{0.96, 0.96, 0.96}", vizXLow, vizXHigh, 0, best_n + 1

    for vizP from 1 to best_n
        vizIdx = best_inst_'vizP'
        vizYPos = best_n - vizP + 1
        vizLo = inst_midi_low_'vizIdx'
        vizHi = inst_midi_high_'vizIdx'
        vizNote = voicing_midi_'vizP'

        Paint rectangle: "{0.84, 0.84, 0.84}", vizLo, vizHi, vizYPos - 0.28, vizYPos + 0.28
        Select inner viewport: 4.55, 7.62, 1.20, 3.25
        Axes: vizXLow, vizXHigh, 0, best_n + 1
        Paint circle (mm): "{0.88, 0.35, 0.25}", vizNote, vizYPos, 2.2

        Select inner viewport: 4.55, 7.62, 1.20, 3.25
        Axes: vizXLow, vizXHigh, 0, best_n + 1
        Font size: 7
        Colour: "Black"
        Text: vizXLow + 0.8, "left", vizYPos, "half", inst_name_'vizIdx'$
    endfor

    Select inner viewport: 4.55, 7.62, 1.20, 3.25
    Axes: vizXLow, vizXHigh, 0, best_n + 1
    Colour: "{0.25, 0.55, 0.25}"
    Dotted line
    Draw line: target_midi, 0, target_midi, best_n + 1
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks bottom: 4, "yes", "yes", "no"
    Font size: 9
    Text top: "no", "##Playable ranges and assigned notes##"

    # ---------- match diagnostics ----------
    vizECent = abs(best_mix_centroid - target_centroid) / 2000
    vizESpr = abs(best_mix_spread - target_spread) / 1000
    vizEOdd = abs(best_mix_odd_even - target_odd_even)
    if vizECent > 1
        vizECent = 1
    endif
    if vizESpr > 1
        vizESpr = 1
    endif
    if vizEOdd > 1
        vizEOdd = 1
    endif

    Select outer viewport: 0.25, 3.90, 3.70, 6.55
    Select inner viewport: 0.72, 3.72, 4.05, 6.30
    Axes: 0, 1, 0, 4
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 4
    Paint rectangle: "{0.80, 0.42, 0.34}", 0, vizECent, 2.75, 3.25
    Paint rectangle: "{0.80, 0.55, 0.30}", 0, vizESpr, 1.75, 2.25
    Paint rectangle: "{0.55, 0.55, 0.75}", 0, vizEOdd, 0.75, 1.25

    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "##Match diagnostics: normalized error##"
    Font size: 7
    Text: 0.02, "left", 3.52, "half", "Centroid: target " + fixed$(target_centroid, 0) + " Hz | match " + fixed$(best_mix_centroid, 0)
    Text: 0.02, "left", 2.52, "half", "Spread: target " + fixed$(target_spread, 0) + " Hz | match " + fixed$(best_mix_spread, 0)
    Text: 0.02, "left", 1.52, "half", "Odd fraction: target " + fixed$(target_odd_even, 3) + " | match " + fixed$(best_mix_odd_even, 3)
    Text: 0.02, "left", 0.25, "half", "Shorter bars = closer match"

    # ---------- best score by ensemble size ----------
    vizScoreMax = 0
    if best_score_k1 < 1e29 and best_score_k1 > vizScoreMax
        vizScoreMax = best_score_k1
    endif
    if best_score_k2 < 1e29 and best_score_k2 > vizScoreMax
        vizScoreMax = best_score_k2
    endif
    if best_score_k3 < 1e29 and best_score_k3 > vizScoreMax
        vizScoreMax = best_score_k3
    endif
    if best_score_k4 < 1e29 and best_score_k4 > vizScoreMax
        vizScoreMax = best_score_k4
    endif
    if vizScoreMax <= 0
        vizScoreMax = 1
    endif
    vizScoreX = vizScoreMax * 1.15

    Select outer viewport: 4.10, 7.80, 3.70, 6.55
    Select inner viewport: 4.55, 7.62, 4.05, 6.30
    Axes: 0, vizScoreX, 0, 5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, vizScoreX, 0, 5

    if best_score_k1 < 1e29
        Paint rectangle: "{0.45, 0.60, 0.78}", 0, best_score_k1, 3.65, 4.25
    endif
    if best_score_k2 < 1e29
        Paint rectangle: "{0.45, 0.68, 0.68}", 0, best_score_k2, 2.65, 3.25
    endif
    if best_score_k3 < 1e29
        Paint rectangle: "{0.55, 0.68, 0.52}", 0, best_score_k3, 1.65, 2.25
    endif
    if best_score_k4 < 1e29
        Paint rectangle: "{0.72, 0.62, 0.45}", 0, best_score_k4, 0.65, 1.25
    endif

    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "##Best penalized score by ensemble size##"
    Font size: 7
    Text: vizScoreX * 0.02, "left", 4.48, "half", "K=1"
    Text: vizScoreX * 0.02, "left", 3.48, "half", "K=2"
    Text: vizScoreX * 0.02, "left", 2.48, "half", "K=3"
    Text: vizScoreX * 0.02, "left", 1.48, "half", "K=4"
    Text: vizScoreX * 0.02, "left", 0.22, "half", "Lower is better; size penalty = " + fixed$(additional_instrument_penalty, 3) + " per extra instrument"

    # ---------- summary ----------
    vizCombo$ = ""
    for vizP from 1 to best_n
        vizIdx = best_inst_'vizP'
        if vizP > 1
            vizCombo$ = vizCombo$ + " + "
        endif
        vizCombo$ = vizCombo$ + inst_name_'vizIdx'$
    endfor

    Select outer viewport: 0.25, 7.80, 6.80, 7.85
    Select inner viewport: 0.45, 7.60, 6.90, 7.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.93}", 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Selected orchestration:## " + vizCombo$
    Font size: 8
    Colour: "{0.30, 0.30, 0.35}"
    Text: 0.02, "left", 0.42, "half", "Acoustic score " + fixed$(best_raw_score, 3) + " + size penalty " + fixed$(best_score - best_raw_score, 3) + " = " + fixed$(best_score, 3)
    Text: 0.02, "left", 0.15, "half", "Profile " + target_dynamic$ + " | F0 " + fixed$(target_f0, 1) + " Hz | odd-harmonic fraction " + fixed$(target_odd_even, 3) + " | analysis ch " + string$(analysis_channel)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="