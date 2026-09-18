# ============================================================
# Praat AudioTools - SpectraScore_Orchestration_Matcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SpectraScore - Orchestration Matcher
#   Analyzes the multichannel target power spectrum and suggests instrument
#   combinations. Outputs a MusicXML orchestration with microtonal support.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
#
# Changelog v0.6.1 (2026):
#   - VIS: panel B now separates MEASURED from NOTATED pitch. Above each note:
#     the notated deviation, exactly as written to MusicXML. Below it: the
#     measured frequency with its deviation from the notated semitone, and the
#     notated frequency (midi + quantized cents). Previously the measured Hz
#     was printed beside the quantized cents; with microtones off it showed
#     "0 cents" beside a peak up to 50 cents away.
#   - VIS: panel A caption and the summary note state that partials are
#     assigned AFTER ensemble selection and do not enter the score.
#   - INFO: voicing lines also report the notated frequency.
#   - No change to analysis, search, voicing or MusicXML content.
#
# Changelog v0.6.0 (2026):
#   - FORM: 31 rows -> 9. The twelve instrument checkboxes are one text field
#     ("Instruments", space- or comma-separated abbreviations, any case,
#     unknown names rejected with the valid list). Allow repeated instruments,
#     Additional instrument penalty, Microtone precision and the harmonic
#     window moved to an optional second dialog (Advanced settings); their
#     defaults are unchanged, so results are identical when it is left off.
#   - VIS: redesigned 8 x 9 in report that tells the orchestration story:
#       A  measured target spectrum (log-band density, log frequency) with the
#          root's harmonic grid, the spectral-voicing search window, the
#          candidate partials, and the partial each instrument plays, in
#          that instrument's colour;
#       B  the resulting chord on a grand staff in concert pitch, low to high:
#          target root as a hollow reference note, each instrument's note with
#          ledger lines, sharps, cents deviation, harmonic/interval label,
#          frequency and written pitch for transposing instruments;
#       C  target six-band energy vs the orchestration model, stacked by
#          instrument so each instrument's contribution is visible;
#       D  best score for each ensemble size, acoustic part vs size penalty,
#          winner highlighted;
#       plus a summary strip with the weighted error breakdown and an honest
#       note that instrument spectra are a Gaussian model.
#   - No change to analysis, search, voicing or MusicXML (except version text).
#
# Changelog v0.5.0 (2026):
#   - CORE: multichannel analysis now sums per-channel POWER spectra instead of
#     selecting only the strongest RMS channel.
#   - CORE: monophonic To Pitch averaging replaced by spectral harmonic-sum
#     root estimation with direct-fundamental support and microtonal refinement.
#   - CORE: Spectral voicing now uses measured significant partial peaks near
#     the requested harmonic slots; absent theoretical harmonics are rejected.
#   - CORE: six measured target band energies now participate directly in the
#     orchestration score via an explicit instrument envelope model.
#   - CORE: odd/even matching is confidence-gated by root confidence and
#     harmonic spectral coverage for polyphonic/inharmonic targets.
#   - FIX: XML escaping now uses literal replace$ rather than regex replacement.
#
# Changelog v0.4.2 (2026):
#   - FIX: MusicXML Strings output now follows the AudioTools/VST instrument
#     contract: one XML source line per Strings item, compatible with
#     VST_Effect_from_Praat.praat.
#
# Changelog v0.4.1 (2026):
#   - OUTPUT: MusicXML is also exposed as an in-memory Praat Strings object.
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

form SpectraScore Orchestration Matcher v0.6.1
    comment Instruments: BTb Bn Cb ClBb Fl Hn Ob Tbn TpC Va Vc Vn
    sentence Instruments BTb Bn Cb ClBb Fl Hn Ob Tbn TpC Va Vc Vn
    integer Max_combination_size 4
    optionmenu Spectral_profile_dynamic: 2
        option pp
        option mf
        option ff
    optionmenu Voicing_strategy: 4
        option Unison (all on root)
        option Octaves (spread by brightness)
        option Chord (root fifth octave)
        option Spectral (match harmonics)
    boolean Enable_microtones 1
    boolean Advanced_settings 0
    boolean Save_xml_file 0
    boolean Draw_visualization 1
endform

# ---- Advanced settings (second dialog; defaults = v0.5 form defaults) ----
allow_repeated_instruments = 0
additional_instrument_penalty = 0.01
microtone_precision_cents = 12.5
min_harmonic = 7
max_harmonic = 16
if advanced_settings
    beginPause: "SpectraScore - advanced settings"
        comment: "Search"
        boolean: "Allow repeated instruments", allow_repeated_instruments
        real: "Additional instrument penalty", string$(additional_instrument_penalty)
        comment: "Microtones and spectral voicing"
        positive: "Microtone precision cents", string$(microtone_precision_cents)
        integer: "Min harmonic", string$(min_harmonic)
        integer: "Max harmonic", string$(max_harmonic)
    clickedAdv = endPause: "Cancel", "Continue", 2, 1
    if clickedAdv = 1
        exitScript: "Cancelled."
    endif
endif

# ---- Instrument list -> the per-instrument switches used below ----
bTb = 0
bn = 0
cb = 0
clBb = 0
fl = 0
hn = 0
ob = 0
tbn = 0
tpC = 0
va = 0
vc = 0
vn = 0
instKnown$ = " btb bn cb clbb fl hn ob tbn tpc va vc vn "
instList$ = replace$(instruments$, ",", " ", 0)
instTok = Create Strings as tokens: instList$, " "
nInstTok = Get number of strings
for iTok from 1 to nInstTok
    selectObject: instTok
    tok$ = Get string: iTok
    tokLc$ = replace_regex$(tok$, "([A-Z])", "\L\1", 0)
    if index(instKnown$, " " + tokLc$ + " ") = 0
        removeObject: instTok
        exitScript: "Unknown instrument """ + tok$ + """." + newline$ + "Use any of: BTb Bn Cb ClBb Fl Hn Ob Tbn TpC Va Vc Vn"
    endif
    if tokLc$ = "btb"
        bTb = 1
    elsif tokLc$ = "bn"
        bn = 1
    elsif tokLc$ = "cb"
        cb = 1
    elsif tokLc$ = "clbb"
        clBb = 1
    elsif tokLc$ = "fl"
        fl = 1
    elsif tokLc$ = "hn"
        hn = 1
    elsif tokLc$ = "ob"
        ob = 1
    elsif tokLc$ = "tbn"
        tbn = 1
    elsif tokLc$ = "tpc"
        tpC = 1
    elsif tokLc$ = "va"
        va = 1
    elsif tokLc$ = "vc"
        vc = 1
    elsif tokLc$ = "vn"
        vn = 1
    endif
endfor
removeObject: instTok
selectObject: sound


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

# v0.5: analyse every channel independently in the spectral domain and combine
# POWER, not waveform amplitude. This preserves stereo/multichannel spectral
# information without phase-cancelling fold-down and without discarding quieter
# channels.
selectObject: sound
n_channels = Get number of channels
duration = Get total duration
sampling_frequency = Get sampling frequency
nyquist = sampling_frequency / 2

writeInfoLine: "=== SpectraScore Orchestration Matcher v0.6.1 ==="
appendInfoLine: "Analyzing: ", sound_name$
appendInfoLine: "Channels: ", n_channels, " (power spectra combined)"
appendInfoLine: ""

# Build one Spectrum per channel. The original Sound is never mixed down.
sum_rms_squared = 0
hnr_sum = 0
hnr_count = 0
for ch from 1 to n_channels
    selectObject: sound
    channel_sound = Extract one channel: ch

    channel_rms = Get root-mean-square: 0, 0
    sum_rms_squared = sum_rms_squared + channel_rms * channel_rms

    channel_harmonicity = To Harmonicity (cc): 0.01, 75, 0.1, 1
    channel_hnr = Get mean: 0, 0
    if channel_hnr <> undefined
        hnr_sum = hnr_sum + channel_hnr
        hnr_count += 1
    endif
    removeObject: channel_harmonicity

    selectObject: channel_sound
    channel_spectrum = To Spectrum: "yes"
    spectrum_ch_'ch' = channel_spectrum
    removeObject: channel_sound
endfor

target_rms = sqrt(sum_rms_squared / n_channels)
if target_rms > 0
    target_db = 20 * log10(target_rms / 0.00002)
else
    target_db = -300
endif
if hnr_count > 0
    target_hnr = hnr_sum / hnr_count
else
    target_hnr = undefined
endif

# Sum spectral energy over all channels. This procedure is used throughout the
# analysis so every descriptor and every measured partial refers to the same
# multichannel power spectrum.
procedure combinedBandEnergy: .lo, .hi
    .sum = 0
    if .lo < 0
        .lo = 0
    endif
    if .hi > nyquist
        .hi = nyquist
    endif
    if .hi > .lo
        for .c from 1 to n_channels
            selectObject: spectrum_ch_'.c'
            .e = Get band energy: .lo, .hi
            if .e <> undefined
                .sum = .sum + .e
            endif
        endfor
    endif
    .result = .sum
endproc

# --------------------------------------------------------------------------
# 1. GLOBAL SPECTRAL DESCRIPTORS FROM THE SUMMED CHANNEL POWER
# --------------------------------------------------------------------------
# Combine each channel's spectral first and second moments by energy weighting.
# For a mixture, E[f^2] = variance + mean^2.
total_spectral_energy = 0
sum_centroid_weighted = 0
sum_second_weighted = 0
for ch from 1 to n_channels
    selectObject: spectrum_ch_'ch'
    channel_energy = Get band energy: 0, nyquist
    channel_centroid = Get centre of gravity: 2
    channel_spread = Get standard deviation: 2
    if channel_energy <> undefined and channel_energy > 0 and channel_centroid <> undefined and channel_spread <> undefined
        total_spectral_energy = total_spectral_energy + channel_energy
        sum_centroid_weighted = sum_centroid_weighted + channel_energy * channel_centroid
        sum_second_weighted = sum_second_weighted + channel_energy * (channel_spread * channel_spread + channel_centroid * channel_centroid)
    endif
endfor

if total_spectral_energy <= 0
    for ch from 1 to n_channels
        removeObject: spectrum_ch_'ch'
    endfor
    exitScript: "Could not obtain a stable target spectrum."
endif

target_centroid = sum_centroid_weighted / total_spectral_energy
target_variance = sum_second_weighted / total_spectral_energy - target_centroid * target_centroid
if target_variance < 0
    target_variance = 0
endif
target_spread = sqrt(target_variance)

# Six broad target-energy bands. These are now part of the matching score,
# rather than report-only metadata.
@combinedBandEnergy: 50, 200
band_energy_1 = combinedBandEnergy.result
@combinedBandEnergy: 200, 500
band_energy_2 = combinedBandEnergy.result
@combinedBandEnergy: 500, 1000
band_energy_3 = combinedBandEnergy.result
@combinedBandEnergy: 1000, 2000
band_energy_4 = combinedBandEnergy.result
@combinedBandEnergy: 2000, 5000
band_energy_5 = combinedBandEnergy.result
@combinedBandEnergy: 5000, 10000
band_energy_6 = combinedBandEnergy.result

total_band_energy = band_energy_1 + band_energy_2 + band_energy_3 + band_energy_4 + band_energy_5 + band_energy_6
if total_band_energy > 0
    band_energy_1 = band_energy_1 / total_band_energy
    band_energy_2 = band_energy_2 / total_band_energy
    band_energy_3 = band_energy_3 / total_band_energy
    band_energy_4 = band_energy_4 / total_band_energy
    band_energy_5 = band_energy_5 / total_band_energy
    band_energy_6 = band_energy_6 / total_band_energy
endif

# --------------------------------------------------------------------------
# 2. SPECTRAL ROOT / REFERENCE PITCH
# --------------------------------------------------------------------------
# Do NOT average a monophonic To Pitch track for polyphonic material. Instead,
# estimate a reference root by harmonic summation on the measured spectrum.
# A direct-energy support term suppresses phantom subharmonics (e.g. C2 winning
# only because C3 happens to be its H2).
root_min_hz = 30
root_max_hz = 500
if root_max_hz > nyquist / 2
    root_max_hz = nyquist / 2
endif
root_step_cents = 25
n_root_candidates = floor(1200 * log2(root_max_hz / root_min_hz) / root_step_cents) + 1
root_max_direct_density = 0

for r from 1 to n_root_candidates
    candidate_freq = root_min_hz * 2 ^ (((r - 1) * root_step_cents) / 1200)
    root_candidate_freq_'r' = candidate_freq
    halfwidth = candidate_freq * 0.015
    if halfwidth < 2
        halfwidth = 2
    endif
    @combinedBandEnergy: candidate_freq - halfwidth, candidate_freq + halfwidth
    direct_density = combinedBandEnergy.result / (2 * halfwidth)
    root_direct_density_'r' = direct_density
    if direct_density > root_max_direct_density
        root_max_direct_density = direct_density
    endif
endfor

best_root_score = -1
best_root_candidate = root_min_hz
for r from 1 to n_root_candidates
    candidate_freq = root_candidate_freq_'r'
    harmonic_sum = 0
    for h from 1 to 12
        harmonic_freq = candidate_freq * h
        if harmonic_freq <= nyquist and harmonic_freq <= 5000
            halfwidth = harmonic_freq * 0.015
            if halfwidth < 2
                halfwidth = 2
            endif
            @combinedBandEnergy: harmonic_freq - halfwidth, harmonic_freq + halfwidth
            harmonic_density = combinedBandEnergy.result / (2 * halfwidth)
            harmonic_sum = harmonic_sum + harmonic_density / (h ^ 0.7)
        endif
    endfor

    direct_support = 0
    if root_max_direct_density > 0
        direct_support = sqrt(root_direct_density_'r' / root_max_direct_density)
    endif
    root_score = harmonic_sum * (0.25 + 0.75 * direct_support)
    root_score_'r' = root_score
    if root_score > best_root_score
        best_root_score = root_score
        best_root_candidate = candidate_freq
    endif
endfor

# Confidence is measured against the strongest DISTINCT alternative, not the
# adjacent 25-cent grid point around the same peak.
second_root_score = 0
for r from 1 to n_root_candidates
    candidate_freq = root_candidate_freq_'r'
    separation_cents = abs(1200 * log2(candidate_freq / best_root_candidate))
    if separation_cents >= 75 and root_score_'r' > second_root_score
        second_root_score = root_score_'r'
    endif
endfor
if best_root_score > 0
    target_root_confidence = (best_root_score - second_root_score) / best_root_score
else
    target_root_confidence = 0
endif
if target_root_confidence < 0
    target_root_confidence = 0
endif
if target_root_confidence > 1
    target_root_confidence = 1
endif

# Refine the root to the actual local spectral maximum around the winning
# candidate. This preserves microtonal detuning instead of snapping to the grid.
target_f0 = best_root_candidate
best_refine_density = -1
for rr from -16 to 16
    refine_cents = rr * 2.5
    refine_freq = best_root_candidate * 2 ^ (refine_cents / 1200)
    halfwidth = refine_freq * 0.003
    if halfwidth < 0.75
        halfwidth = 0.75
    endif
    @combinedBandEnergy: refine_freq - halfwidth, refine_freq + halfwidth
    refine_density = combinedBandEnergy.result / (2 * halfwidth)
    if refine_density > best_refine_density
        best_refine_density = refine_density
        target_f0 = refine_freq
    endif
endfor

target_midi = 69 + 12 * log2(target_f0 / 440)

# --------------------------------------------------------------------------
# 3. HARMONIC STRUCTURE AND MEASURED SPECTRAL PARTIALS
# --------------------------------------------------------------------------
# Odd/even is now based on the robust spectral root. Also measure how much of
# the overall spectrum is actually explained by harmonic bands; this confidence
# attenuates odd/even scoring for strongly polyphonic or inharmonic targets.
odd_harmonic_energy = 0
even_harmonic_energy = 0
n_harmonics_measured = floor(nyquist / target_f0)
if n_harmonics_measured > 20
    n_harmonics_measured = 20
endif
for h from 1 to n_harmonics_measured
    h_center = target_f0 * h
    harmonic_halfwidth = h_center * 0.02
    if harmonic_halfwidth < 2
        harmonic_halfwidth = 2
    endif
    @combinedBandEnergy: h_center - harmonic_halfwidth, h_center + harmonic_halfwidth
    h_energy = combinedBandEnergy.result
    if h mod 2 = 1
        odd_harmonic_energy = odd_harmonic_energy + h_energy
    else
        even_harmonic_energy = even_harmonic_energy + h_energy
    endif
endfor

harmonic_energy_total = odd_harmonic_energy + even_harmonic_energy
if harmonic_energy_total > 0
    target_odd_even = odd_harmonic_energy / harmonic_energy_total
else
    target_odd_even = 0.5
endif
if total_band_energy > 0
    target_harmonic_coverage = harmonic_energy_total / total_band_energy
else
    target_harmonic_coverage = 0
endif
if target_harmonic_coverage > 1
    target_harmonic_coverage = 1
endif

# Spectral voicing must choose a partial that is actually present. For each
# requested harmonic slot, search +/-60 cents around the theoretical position,
# store the strongest measured local peak, and later reject peaks more than
# 30 dB below the strongest peak in the requested region.
measured_peak_max = 0
peak_scan_step_cents = 12.5
if enable_microtones and microtone_precision_cents < peak_scan_step_cents
    peak_scan_step_cents = microtone_precision_cents
endif
if peak_scan_step_cents < 2.5
    peak_scan_step_cents = 2.5
endif
n_peak_scan_steps = floor(60 / peak_scan_step_cents)

for h from min_harmonic to max_harmonic
    theoretical_freq = target_f0 * h
    measured_harmonic_valid_'h' = 0
    measured_harmonic_freq_'h' = theoretical_freq
    measured_harmonic_energy_'h' = 0

    if theoretical_freq < nyquist
        best_peak_density = -1
        best_peak_freq = theoretical_freq
        for ps from -n_peak_scan_steps to n_peak_scan_steps
            cents_shift = ps * peak_scan_step_cents
            scan_freq = theoretical_freq * 2 ^ (cents_shift / 1200)
            peak_halfwidth = scan_freq * 0.004
            if peak_halfwidth < 1
                peak_halfwidth = 1
            endif
            @combinedBandEnergy: scan_freq - peak_halfwidth, scan_freq + peak_halfwidth
            peak_density = combinedBandEnergy.result / (2 * peak_halfwidth)
            if peak_density > best_peak_density
                best_peak_density = peak_density
                best_peak_freq = scan_freq
            endif
        endfor
        measured_harmonic_freq_'h' = best_peak_freq
        measured_harmonic_energy_'h' = best_peak_density
        if best_peak_density > measured_peak_max
            measured_peak_max = best_peak_density
        endif
    endif
endfor

if measured_peak_max > 0
    measured_peak_threshold = measured_peak_max * 0.001
else
    measured_peak_threshold = 0
endif
for h from min_harmonic to max_harmonic
    if measured_harmonic_energy_'h' >= measured_peak_threshold and measured_harmonic_energy_'h' > 0
        measured_harmonic_valid_'h' = 1
    endif
endfor

# The pp/mf/ff instrument profiles are a user-selected modelling choice.
dyn_idx = spectral_profile_dynamic
if dyn_idx = 1
    target_dynamic$ = "pp"
elsif dyn_idx = 2
    target_dynamic$ = "mf"
else
    target_dynamic$ = "ff"
endif

# v0.6: keep a log-frequency picture of the measured target for panel A of the
# report (log-spaced band densities, each band at least 2 FFT bins wide).
if draw_visualization
    vizSpecLo = 30
    vizSpecHi = max(5000, 1.3 * target_f0 * max_harmonic)
    vizSpecHi = min(vizSpecHi, nyquist * 0.95)
    vizNB = 480
    vizMinBw = 2 / duration
    vizSpecMax = -1e30
    for b from 1 to vizNB
        vzLo = vizSpecLo * (vizSpecHi / vizSpecLo) ^ ((b - 1) / vizNB)
        vzHi = vizSpecLo * (vizSpecHi / vizSpecLo) ^ (b / vizNB)
        vzFc = sqrt(vzLo * vzHi)
        if vzHi - vzLo < vizMinBw
            vzLo = vzFc - vizMinBw / 2
            vzHi = vzFc + vizMinBw / 2
        endif
        @combinedBandEnergy: vzLo, vzHi
        vzDens = combinedBandEnergy.result / (vzHi - vzLo)
        vizSpecF[b] = vzFc
        if vzDens > 0
            vizSpecDb[b] = 10 * log10(vzDens)
            vizSpecMax = max(vizSpecMax, vizSpecDb[b])
        else
            vizSpecDb[b] = -1e30
        endif
    endfor
    for b from 1 to vizNB
        vizSpecDb[b] = max(vizSpecDb[b] - vizSpecMax, -70)
    endfor
endif

# Spectra are no longer needed after all target features/partials are stored.
for ch from 1 to n_channels
    removeObject: spectrum_ch_'ch'
endfor

appendInfoLine: "=== TARGET ANALYSIS ==="
appendInfoLine: "Spectral root/reference: ", fixed$(target_f0, 2), " Hz (MIDI ", fixed$(target_midi, 1), ")"
appendInfoLine: "Root confidence: ", fixed$(target_root_confidence, 3), " (spectral harmonic summation)"
appendInfoLine: "File level: ", fixed$(target_db, 1), " dB re 20 uPa (descriptive)"
appendInfoLine: "Instrument profile: ", target_dynamic$
if target_hnr <> undefined
    appendInfoLine: "Mean channel HNR: ", fixed$(target_hnr, 1), " dB (descriptive only)"
endif
appendInfoLine: "Centroid: ", fixed$(target_centroid, 0), " Hz"
appendInfoLine: "Spread: ", fixed$(target_spread, 0), " Hz"
appendInfoLine: "Odd-harmonic fraction: ", fixed$(target_odd_even, 3), " (coverage ", fixed$(target_harmonic_coverage, 3), ")"
appendInfoLine: "Band profile [50-200 | 200-500 | 500-1k | 1-2k | 2-5k | 5-10k]:"
appendInfoLine: "  ", fixed$(band_energy_1, 3), "  ", fixed$(band_energy_2, 3), "  ", fixed$(band_energy_3, 3), "  ", fixed$(band_energy_4, 3), "  ", fixed$(band_energy_5, 3), "  ", fixed$(band_energy_6, 3)
appendInfoLine: ""

if voicing_strategy = 4
    appendInfoLine: "Measured spectral partials near H", min_harmonic, "-H", max_harmonic, " (>= -30 dB regional peak):"
    for h from min_harmonic to max_harmonic
        if measured_harmonic_valid_'h'
            rel_peak_db = 10 * log10(measured_harmonic_energy_'h' / measured_peak_max)
            appendInfoLine: "  H", h, ": ", fixed$(measured_harmonic_freq_'h', 1), " Hz  ", fixed$(rel_peak_db, 1), " dB"
        else
            appendInfoLine: "  H", h, ": no significant measured peak"
        endif
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

# Approximate each instrument's six-band spectral envelope from its stored
# centroid/spread profile. The database currently stores moments rather than a
# full measured spectrum, so this is an explicit Gaussian envelope model. It
# lets the target's measured band-energy profile constrain the match instead of
# relying on centroid/spread alone.
procedure gaussianBandMass: .cent, .spr, .lo, .hi
    .sum = 0
    if .spr <= 0
        .result = 0
    else
        .width = .hi - .lo
        for .s from 1 to 5
            .f = .lo + (.s - 0.5) * .width / 5
            .z = (.f - .cent) / .spr
            .sum = .sum + exp(-0.5 * .z * .z)
        endfor
        .result = .sum * .width / 5
    endif
endproc

procedure computeInstBandProfile: .idx
    @getInstCentroid: .idx
    .cent = getInstCentroid.result
    @getInstSpread: .idx
    .spr = getInstSpread.result

    @gaussianBandMass: .cent, .spr, 50, 200
    inst_band1_'.idx' = gaussianBandMass.result
    @gaussianBandMass: .cent, .spr, 200, 500
    inst_band2_'.idx' = gaussianBandMass.result
    @gaussianBandMass: .cent, .spr, 500, 1000
    inst_band3_'.idx' = gaussianBandMass.result
    @gaussianBandMass: .cent, .spr, 1000, 2000
    inst_band4_'.idx' = gaussianBandMass.result
    @gaussianBandMass: .cent, .spr, 2000, 5000
    inst_band5_'.idx' = gaussianBandMass.result
    @gaussianBandMass: .cent, .spr, 5000, 10000
    inst_band6_'.idx' = gaussianBandMass.result

    .total = inst_band1_'.idx' + inst_band2_'.idx' + inst_band3_'.idx' + inst_band4_'.idx' + inst_band5_'.idx' + inst_band6_'.idx'
    if .total > 0
        inst_band1_'.idx' = inst_band1_'.idx' / .total
        inst_band2_'.idx' = inst_band2_'.idx' / .total
        inst_band3_'.idx' = inst_band3_'.idx' / .total
        inst_band4_'.idx' = inst_band4_'.idx' / .total
        inst_band5_'.idx' = inst_band5_'.idx' / .total
        inst_band6_'.idx' = inst_band6_'.idx' / .total
    endif
endproc

for inst_i from 1 to n_instruments
    @computeInstBandProfile: inst_i
endfor

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
        # Spectral voicing: choose only a MEASURED significant peak near the
        # requested harmonic slots. Cost balances timbral placement (distance
        # from the instrument profile centroid) with measured peak strength.
        # This prevents assigning an instrument to a theoretical harmonic that
        # is absent from the source spectrum.
        @getInstCentroid: .inst_idx
        .inst_brightness = getInstCentroid.result
        .found = 0
        .min_cost = 1e30

        for .h from min_harmonic to max_harmonic
            if measured_harmonic_valid_'.h'
                .peak_freq = measured_harmonic_freq_'.h'
                .peak_midi = 69 + 12 * log2(.peak_freq / 440)
                if .peak_midi >= .low and .peak_midi <= .high
                    .rel_energy = measured_harmonic_energy_'.h' / measured_peak_max
                    if .rel_energy < 0
                        .rel_energy = 0
                    endif
                    .brightness_distance = abs(log2(.peak_freq / .inst_brightness))
                    .energy_penalty = 0.5 * (1 - sqrt(.rel_energy))
                    .cost = .brightness_distance + .energy_penalty
                    if .cost < .min_cost
                        .min_cost = .cost
                        .harmonic = .h
                        .target_freq = .peak_freq
                        .midi_exact = .peak_midi
                        .found = 1
                    endif
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

# Equal-energy spectral mixture. In addition to centroid/spread, v0.5 scores
# the six-band envelope against the measured target profile. Odd/even receives
# only a small confidence-weighted contribution because it is meaningful only
# to the extent that the target is actually harmonic around the detected root.
procedure scoreCombo: .n_in_combo
    .sum_cent = 0
    .sum_second = 0
    .sum_oe = 0
    .sum_b1 = 0
    .sum_b2 = 0
    .sum_b3 = 0
    .sum_b4 = 0
    .sum_b5 = 0
    .sum_b6 = 0

    for .pos from 1 to .n_in_combo
        .ix = combo_idx_'.pos'
        @getInstCentroid: .ix
        .cent = getInstCentroid.result
        @getInstSpread: .ix
        .spr = getInstSpread.result

        .sum_cent = .sum_cent + .cent
        .sum_second = .sum_second + .spr * .spr + .cent * .cent
        .sum_oe = .sum_oe + inst_odd_even_'.ix'
        .sum_b1 = .sum_b1 + inst_band1_'.ix'
        .sum_b2 = .sum_b2 + inst_band2_'.ix'
        .sum_b3 = .sum_b3 + inst_band3_'.ix'
        .sum_b4 = .sum_b4 + inst_band4_'.ix'
        .sum_b5 = .sum_b5 + inst_band5_'.ix'
        .sum_b6 = .sum_b6 + inst_band6_'.ix'
    endfor

    .mix_cent = .sum_cent / .n_in_combo
    .mix_var = .sum_second / .n_in_combo - .mix_cent * .mix_cent
    if .mix_var < 0
        .mix_var = 0
    endif
    .mix_spr = sqrt(.mix_var)
    .mix_oe = .sum_oe / .n_in_combo
    .mix_b1 = .sum_b1 / .n_in_combo
    .mix_b2 = .sum_b2 / .n_in_combo
    .mix_b3 = .sum_b3 / .n_in_combo
    .mix_b4 = .sum_b4 / .n_in_combo
    .mix_b5 = .sum_b5 / .n_in_combo
    .mix_b6 = .sum_b6 / .n_in_combo

    # Log-ratio moment errors are scale-aware: a 2:1 centroid mismatch has
    # comparable importance at low and high spectral centres. Clamp at 1.
    .d_cent = abs(log2((.mix_cent + 1) / (target_centroid + 1))) / 2
    .d_spr = abs(log2((.mix_spr + 1) / (target_spread + 1))) / 2
    if .d_cent > 1
        .d_cent = 1
    endif
    if .d_spr > 1
        .d_spr = 1
    endif

    # L1 distance between normalized band profiles, divided by two so the
    # distance lies in [0,1].
    .d_band = 0.5 * (abs(.mix_b1 - band_energy_1) + abs(.mix_b2 - band_energy_2) + abs(.mix_b3 - band_energy_3) + abs(.mix_b4 - band_energy_4) + abs(.mix_b5 - band_energy_5) + abs(.mix_b6 - band_energy_6))
    .d_oe = abs(.mix_oe - target_odd_even)
    .oe_confidence = target_root_confidence * target_harmonic_coverage
    if .oe_confidence > 1
        .oe_confidence = 1
    endif

    # The measured broad-band envelope is now the largest term. The global
    # moments stabilize the coarse spectral shape; odd/even is deliberately
    # weak and confidence-gated.
    .raw_score = 0.45 * .d_band + 0.30 * .d_cent + 0.20 * .d_spr + 0.05 * .oe_confidence * .d_oe
    .size_penalty = additional_instrument_penalty * (.n_in_combo - 1)
    .score = .raw_score + .size_penalty
endproc

procedure xmlEscape: .s$
    # Literal replacement, not regex: < and > are regex metacharacters in
    # Praat and the old implementation could corrupt ordinary titles.
    .s$ = replace$(.s$, "&", "&amp;", 0)
    .s$ = replace$(.s$, "<", "&lt;", 0)
    .s$ = replace$(.s$, ">", "&gt;", 0)
    .s$ = replace$(.s$, """", "&quot;", 0)
    .result$ = .s$
endproc

# Append one logical MusicXML source line to both the complete xml$ document
# and the line array used to construct the canonical Praat Strings object.
procedure xmlAdd: .line$
    nXmlLines += 1
    xmlLine$[nXmlLines] = .line$
    xml$ = xml$ + .line$ + newline$
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
best_mix_band1 = scoreCombo.mix_b1
best_mix_band2 = scoreCombo.mix_b2
best_mix_band3 = scoreCombo.mix_b3
best_mix_band4 = scoreCombo.mix_b4
best_mix_band5 = scoreCombo.mix_b5
best_mix_band6 = scoreCombo.mix_b6
best_error_band = scoreCombo.d_band
best_error_cent = scoreCombo.d_cent
best_error_spr = scoreCombo.d_spr
best_error_oe = scoreCombo.oe_confidence * scoreCombo.d_oe

appendInfoLine: ""
appendInfoLine: "=== BEST MATCH ==="
appendInfoLine: "Selection score: ", fixed$(best_score, 4), "  (acoustic=", fixed$(best_raw_score, 4), ", size penalty=", fixed$(best_score - best_raw_score, 4), ")"
appendInfoLine: "Matched centroid: ", fixed$(best_mix_centroid, 0), " Hz"
appendInfoLine: "Matched spread: ", fixed$(best_mix_spread, 0), " Hz"
appendInfoLine: "Matched odd-harmonic fraction: ", fixed$(best_mix_odd_even, 3)
appendInfoLine: "Band-envelope distance: ", fixed$(best_error_band, 4)
appendInfoLine: "Matched band profile:"
appendInfoLine: "  ", fixed$(best_mix_band1, 3), "  ", fixed$(best_mix_band2, 3), "  ", fixed$(best_mix_band3, 3), "  ", fixed$(best_mix_band4, 3), "  ", fixed$(best_mix_band5, 3), "  ", fixed$(best_mix_band6, 3)
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
    voicing_label_'p'$ = replace$(labelStr$, "_", " ", 0)
    appendInfoLine: inst_name_'idx'$, ": ", labelStr$, " (", fixed$(assignVoicing.target_freq, 1), " Hz) -> MIDI ", fixed$(assignVoicing.midi_note, 1), " + ", fixed$(assignVoicing.cents_offset, 1), " cents = ", fixed$(440 * 2 ^ ((assignVoicing.midi_note + assignVoicing.cents_offset / 100 - 69) / 12), 1), " Hz notated"
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

xml$ = ""
nXmlLines = 0

@xmlAdd: "<?xml version=""1.0"" encoding=""UTF-8""?>"
@xmlAdd: "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">"
@xmlAdd: "<score-partwise version=""3.1"">"
@xmlAdd: "  <work><work-title>SpectraScore: " + xml_sound_name$ + "</work-title></work>"
@xmlAdd: "  <identification>"
@xmlAdd: "    <creator type=""software"">Praat SpectraScore v0.6.1</creator>"
@xmlAdd: "  </identification>"

# Part list
@xmlAdd: "  <part-list>"
for p from 1 to best_n
    idx = best_inst_'p'
    @xmlAdd: "    <score-part id=""P" + string$(p) + """>"
    @xmlAdd: "      <part-name>" + inst_name_'idx'$ + "</part-name>"
    @xmlAdd: "    </score-part>"
endfor
@xmlAdd: "  </part-list>"

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
    
    @xmlAdd: "  <part id=""P" + string$(p) + """>"
    @xmlAdd: "    <measure number=""1"">"
    @xmlAdd: "      <attributes>"
    @xmlAdd: "        <divisions>1</divisions>"
    @xmlAdd: "        <key><fifths>0</fifths></key>"
    @xmlAdd: "        <time><beats>4</beats><beat-type>4</beat-type></time>"
    @xmlAdd: "        <clef><sign>" + clef_sign$ + "</sign><line>" + string$(clef_line) + "</line></clef>"
    
    transpose = inst_transpose_'idx'
    if transpose <> 0
        @xmlAdd: "        <transpose><chromatic>" + string$(transpose) + "</chromatic></transpose>"
    endif
    
    @xmlAdd: "      </attributes>"
    
    # Note
    @xmlAdd: "      <note>"
    @xmlAdd: "        <pitch>"
    @xmlAdd: "          <step>" + step$ + "</step>"
    if abs(total_alter) > 0.01
        @xmlAdd: "          <alter>" + fixed$(total_alter, 2) + "</alter>"
    endif
    @xmlAdd: "          <octave>" + string$(octave) + "</octave>"
    @xmlAdd: "        </pitch>"
    @xmlAdd: "        <duration>4</duration>"
    @xmlAdd: "        <type>whole</type>"
    
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
            @xmlAdd: "        <accidental>" + accidental$ + "</accidental>"
        endif
    endif

    # Dynamics
    @xmlAdd: "        <notations>"
    @xmlAdd: "          <dynamics><" + target_dynamic$ + "/></dynamics>"
    @xmlAdd: "        </notations>"
    @xmlAdd: "      </note>"
    @xmlAdd: "    </measure>"
    @xmlAdd: "  </part>"
endfor

@xmlAdd: "</score-partwise>"

# Canonical AudioTools in-memory MusicXML representation:
# one XML source line per Strings item. This is the format consumed by
# VST_Effect_from_Praat.praat, which checks the first lines and then saves
# the selected Strings object as a raw-text .musicxml file.
musicxml_object = Create Strings as tokens: "placeholder", " "
Set string: 1, xmlLine$[1]
for lineNo from 2 to nXmlLines
    Insert string: 0, xmlLine$[lineNo]
endfor
Rename: "musicxml_" + sound_name$ + "_SpectraScore"
musicxml_name$ = selected$("Strings")

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
appendInfoLine: "Praat object: Strings ", musicxml_name$, " (", nXmlLines, " XML lines)"
appendInfoLine: xml$

# ============================================================================
# VISUALIZATION
# ============================================================================

if draw_visualization
    # --------------------------------------------------------------
    # Shared state
    # --------------------------------------------------------------
    vzCol$[1] = "{0.20, 0.48, 0.75}"
    vzCol$[2] = "{0.85, 0.38, 0.18}"
    vzCol$[3] = "{0.25, 0.55, 0.45}"
    vzCol$[4] = "{0.55, 0.35, 0.65}"
    vzGrey$   = "{0.55, 0.55, 0.60}"
    vzGround$ = "{0.97, 0.97, 0.97}"
    vzGrid$   = "{0.80, 0.80, 0.80}"
    vzSubTx$  = "{0.35, 0.35, 0.50}"
    vzSumTx$  = "{0.25, 0.25, 0.35}"

    if voicing_strategy = 1
        vzStrat$ = "Unison"
    elsif voicing_strategy = 2
        vzStrat$ = "Octaves"
    elsif voicing_strategy = 3
        vzStrat$ = "Chord"
    else
        vzStrat$ = "Spectral H" + string$(min_harmonic) + "-H" + string$(max_harmonic)
    endif

    # Diatonic step index of each pitch class (C=0 ... B=6)
    vzStep_0 = 0
    vzStep_1 = 0
    vzStep_2 = 1
    vzStep_3 = 1
    vzStep_4 = 2
    vzStep_5 = 3
    vzStep_6 = 3
    vzStep_7 = 4
    vzStep_8 = 4
    vzStep_9 = 5
    vzStep_10 = 5
    vzStep_11 = 6

    # Per-instrument staff data, then order by sounding pitch (low -> high)
    for p from 1 to best_n
        vzOrd[p] = p
        vzM = voicing_midi_'p'
        vzPc = vzM mod 12
        vzOct = floor(vzM / 12) - 1
        vzD[p] = vzOct * 7 + vzStep_'vzPc'
        vzSharp[p] = alter_'vzPc'
        vzIdx = best_inst_'p'
        vzW = vzM - inst_transpose_'vzIdx'
        vzWPc = vzW mod 12
        vzWOct = floor(vzW / 12) - 1
        vzWritten$[p] = step_'vzWPc'$
        if alter_'vzWPc'
            vzWritten$[p] = vzWritten$[p] + "\# "
        endif
        vzWritten$[p] = vzWritten$[p] + string$(vzWOct)
    endfor
    for vzA from 1 to best_n - 1
        for vzB from vzA + 1 to best_n
            vzIa = vzOrd[vzA]
            vzIb = vzOrd[vzB]
            if voicing_freq_'vzIb' < voicing_freq_'vzIa'
                vzOrd[vzA] = vzIb
                vzOrd[vzB] = vzIa
            endif
        endfor
    endfor

    vzRootMidi = round(target_midi)
    vzRootCents = (target_midi - vzRootMidi) * 100
    vzPc = vzRootMidi mod 12
    vzRootD = (floor(vzRootMidi / 12) - 1) * 7 + vzStep_'vzPc'
    vzRootSharp = alter_'vzPc'

    @vizSafe: sound_name$
    vzName$ = vizSafe.result$

    Erase all

    # --------------------------------------------------------------
    # Title band
    # --------------------------------------------------------------
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SpectraScore Orchestration Matcher v0.6.1##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: vzSubTx$
    Text: 0.5, "centre", 0.22, "half", vzName$ + "   |   root " + fixed$(target_f0, 1) + " Hz   |   " + vzStrat$ + "   |   profile " + target_dynamic$ + "   |   K = " + string$(best_n) + " of max " + string$(max_combination_size)

    # --------------------------------------------------------------
    # A  Target spectrum: where each instrument sits in it
    # --------------------------------------------------------------
    vzAx1 = log10(vizSpecLo)
    vzAx2 = log10(vizSpecHi)
    vzAy1 = -70
    vzAy2 = 18

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.55
    Axes: vzAx1, vzAx2, vzAy1, vzAy2
    Paint rectangle: vzGround$, vzAx1, vzAx2, vzAy1, vzAy2
    if voicing_strategy = 4
        vzWLo = target_f0 * min_harmonic * 2 ^ (-60 / 1200)
        vzWHi = target_f0 * max_harmonic * 2 ^ (60 / 1200)
        vzWLo = max(vzWLo, vizSpecLo)
        vzWHi = min(vzWHi, vizSpecHi)
        if vzWHi > vzWLo
            Paint rectangle: "{0.91, 0.91, 0.93}", log10(vzWLo), log10(vzWHi), vzAy1, vzAy2
        endif
    endif

    # harmonic grid of the detected root
    Colour: vzGrid$
    Dotted line
    vzH = 1
    while vzH <= 48 and target_f0 * vzH < vizSpecHi
        vzX = log10(target_f0 * vzH)
        if vzX > vzAx1
            Draw line: vzX, vzAy1, vzX, 0
        endif
        vzH += 1
    endwhile
    Solid line

    # measured spectrum (log-band densities, dB re strongest band)
    Colour: vzGrey$
    Line width: 1
    for b from 2 to vizNB
        vzB0 = b - 1
        Draw line: log10(vizSpecF[vzB0]), vizSpecDb[vzB0], log10(vizSpecF[b]), vizSpecDb[b]
    endfor

    # measured candidate partials (spectral voicing only)
    if voicing_strategy = 4
        for h from min_harmonic to max_harmonic
            if measured_harmonic_valid_'h'
                vzF = measured_harmonic_freq_'h'
                if vzF > vizSpecLo and vzF < vizSpecHi
                    @specAt: vzF
                    Paint circle (mm): vzGrey$, log10(vzF), specAt.result, 0.9
                endif
            endif
        endfor
    endif

    # the notes actually given to instruments
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        vzIdx = best_inst_'p'
        vzF = voicing_freq_'p'
        vzF = min(max(vzF, vizSpecLo * 1.001), vizSpecHi * 0.999)
        vzX = log10(vzF)
        @specAt: vzF
        vzDb = specAt.result
        Colour: vzCol$[p]
        Line width: 2
        Draw line: vzX, vzAy1, vzX, vzDb
        Line width: 1
        Paint circle (mm): vzCol$[p], vzX, vzDb, 1.8
    endfor

    # labels (own font block)
    Font size: 6
    Select inner viewport: 0.60, 7.70, 0.95, 2.55
    Axes: vzAx1, vzAx2, vzAy1, vzAy2
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        vzIdx = best_inst_'p'
        vzF = min(max(voicing_freq_'p', vizSpecLo * 1.001), vizSpecHi * 0.999)
        # stack labels of instruments that sit close together in frequency
        vzRow = 0
        for vzQ from 1 to vzR - 1
            vzPq = vzOrd[vzQ]
            vzFq = min(max(voicing_freq_'vzPq', vizSpecLo * 1.001), vizSpecHi * 0.999)
            if abs(log10(vzF / vzFq)) < 0.06
                vzRow += 1
            endif
        endfor
        vzLy = 1.0 + 4.2 * vzRow
        Colour: vzCol$[p]
        Text: log10(vzF), "centre", vzLy, "bottom", "##" + inst_name_'vzIdx'$ + "##  " + voicing_label_'p'$
    endfor
    Colour: vzSubTx$
    if target_f0 > vizSpecLo
        Text: log10(target_f0), "left", vzAy1 + 3, "bottom", " H1"
    endif
    if voicing_strategy = 4
        if vzWHi > vzWLo
            Text: log10(vzWHi), "right", vzAy2 - 1, "top", "search window "
        endif
    endif

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.55
    Axes: vzAx1, vzAx2, vzAy1, vzAy2
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    vzTick_1 = 50
    vzTick_2 = 100
    vzTick_3 = 200
    vzTick_4 = 500
    vzTick_5 = 1000
    vzTick_6 = 2000
    vzTick_7 = 5000
    vzTick_8 = 10000
    vzTick_9 = 20000
    for vzT from 1 to 9
        vzTf = vzTick_'vzT'
        if vzTf >= vizSpecLo and vzTf <= vizSpecHi
            if vzTf >= 1000
                vzTl$ = string$(vzTf / 1000) + "k"
            else
                vzTl$ = string$(vzTf)
            endif
            One mark bottom: log10(vzTf), "no", "yes", "no", vzTl$
        endif
    endfor
    Text left: "yes", "dB re peak"
    Text bottom: "yes", "Frequency (Hz)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 0.95, 2.55
    Text top: "no", "##A   Target spectrum \-- partials assigned after ensemble selection##"

    # --------------------------------------------------------------
    # B  Resulting chord on a grand staff (concert pitch)
    # --------------------------------------------------------------
    # y axis = diatonic step (C4 = 28); treble lines E4..F5 = 30..38,
    # bass lines G2..A3 = 18..26. x axis = inches across the panel.
    vzStW = 7.10
    vzDLo = 11
    vzDHi = 43
    for p from 1 to best_n
        vzDLo = min(vzDLo, vzD[p] - 8)
        vzDHi = max(vzDHi, vzD[p] + 6)
    endfor
    vzDLo = min(vzDLo, vzRootD - 8)
    vzDHi = max(vzDHi, vzRootD + 6)
    # one aligned annotation row (cents, label) above the highest note/staff
    vzRowY = max(38, vzRootD)
    for p from 1 to best_n
        vzRowY = max(vzRowY, vzD[p])
    endfor
    vzRowY = vzRowY + 2.2
    vzDHi = max(vzDHi, vzRowY + 5)
    vzStepIn = 2.60 / (vzDHi - vzDLo)
    vzHeadW = 1.75 * vzStepIn * 1.35
    vzLedW = vzHeadW * 0.95
    vzRootX = 1.35
    vzSepX = 2.00
    vzColW = (vzStW - 0.20 - vzSepX) / best_n

    Font size: 7
    Select inner viewport: 0.60, 7.70, 3.05, 5.65
    Axes: 0, vzStW, vzDLo, vzDHi
    Paint rectangle: vzGround$, 0, vzStW, vzDLo, vzDHi

    # staves, system barline, end barline
    Colour: "Black"
    Line width: 1
    for vzL from 0 to 4
        Draw line: 0.35, 18 + 2 * vzL, vzStW - 0.20, 18 + 2 * vzL
        Draw line: 0.35, 30 + 2 * vzL, vzStW - 0.20, 30 + 2 * vzL
    endfor
    Draw line: 0.35, 18, 0.35, 38
    Draw line: vzStW - 0.20, 18, vzStW - 0.20, 38
    Colour: vzGrid$
    Dotted line
    Draw line: vzSepX, vzDLo + 4.2, vzSepX, vzDHi - 0.5
    Solid line

    # faint guides from the annotation row down to each note
    Colour: vzGrid$
    Dotted line
    Draw line: vzRootX, vzRowY - 0.4, vzRootX, vzRootD + 1.2
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        vzNX = vzSepX + (vzR - 0.5) * vzColW
        if vzRowY - 0.4 > vzD[p] + 1.2
            Draw line: vzNX, vzRowY - 0.4, vzNX, vzD[p] + 1.2
        endif
    endfor
    Solid line

    # root reference (hollow grey) and instrument notes (filled, coloured)
    vzNX = vzRootX
    vzND = vzRootD
    vzNCol$ = vzGrey$
    vzNFill = 0
    @drawStaffNote
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        vzNX = vzSepX + (vzR - 0.5) * vzColW
        vzND = vzD[p]
        vzNCol$ = vzCol$[p]
        vzNFill = 1
        @drawStaffNote
    endfor

    # clefs (letter clefs on their reference lines)
    Font size: 13
    Select inner viewport: 0.60, 7.70, 3.05, 5.65
    Axes: 0, vzStW, vzDLo, vzDHi
    Colour: "Black"
    Text: 0.58, "centre", 32, "half", "##G##"
    Text: 0.58, "centre", 24, "half", "##F##"

    # accidentals
    Font size: 9
    Select inner viewport: 0.60, 7.70, 3.05, 5.65
    Axes: 0, vzStW, vzDLo, vzDHi
    if vzRootSharp
        Colour: vzGrey$
        Text: vzRootX - vzHeadW * 0.65, "right", vzRootD, "half", "\# "
    endif
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        if vzSharp[p]
            Colour: vzCol$[p]
            Text: vzSepX + (vzR - 0.5) * vzColW - vzHeadW * 0.65, "right", vzD[p], "half", "\# "
        endif
    endfor

    # annotations above and below each note
    Font size: 6
    Select inner viewport: 0.60, 7.70, 3.05, 5.65
    Axes: 0, vzStW, vzDLo, vzDHi
    Colour: vzSubTx$
    if vzRootCents >= 0
        vzCt$ = "+" + fixed$(vzRootCents, 0) + "¢"
    else
        vzCt$ = fixed$(vzRootCents, 0) + "¢"
    endif
    Text: vzRootX, "centre", vzRowY, "bottom", vzCt$
    Text: vzRootX, "centre", vzRowY + 2.0, "bottom", "root"
    Text: vzRootX, "centre", vzDLo + 4.0, "bottom", "##target root##"
    Text: vzRootX, "centre", vzDLo + 2.3, "bottom", "meas. " + fixed$(target_f0, 1) + " Hz"
    Text: vzRootX, "centre", vzDLo + 0.6, "bottom", "(reference only)"
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        vzIdx = best_inst_'p'
        vzNX = vzSepX + (vzR - 0.5) * vzColW
        Colour: vzCol$[p]
        vzC = voicing_cents_'p'
        if abs(vzC) > 0.01
            if vzC > 0
                vzCt$ = "+" + fixed$(vzC, 1) + "¢"
            else
                vzCt$ = fixed$(vzC, 1) + "¢"
            endif
            Text: vzNX, "centre", vzRowY, "bottom", vzCt$
        else
            Text: vzNX, "centre", vzRowY, "bottom", "0¢"
        endif
        Text: vzNX, "centre", vzRowY + 2.0, "bottom", voicing_label_'p'$
        vzLine$ = "##" + inst_name_'vzIdx'$ + "##"
        if inst_transpose_'vzIdx' <> 0
            vzLine$ = vzLine$ + "  (written " + vzWritten$[p] + ")"
        endif
        Text: vzNX, "centre", vzDLo + 4.0, "bottom", vzLine$
        # measured peak, with its deviation from the NOTATED semitone
        vzMeasF = voicing_freq_'p'
        vzMeasC = (69 + 12 * log2(vzMeasF / 440) - voicing_midi_'p') * 100
        if vzMeasC >= 0
            vzMc$ = "+" + fixed$(vzMeasC, 1) + "¢"
        else
            vzMc$ = fixed$(vzMeasC, 1) + "¢"
        endif
        Text: vzNX, "centre", vzDLo + 2.3, "bottom", "meas. " + fixed$(vzMeasF, 1) + " Hz  " + vzMc$
        vzNotF = 440 * 2 ^ ((voicing_midi_'p' + voicing_cents_'p' / 100 - 69) / 12)
        Text: vzNX, "centre", vzDLo + 0.6, "bottom", "notated " + fixed$(vzNotF, 1) + " Hz"
    endfor

    Font size: 7
    Select inner viewport: 0.60, 7.70, 3.05, 5.65
    Axes: 0, vzStW, vzDLo, vzDHi
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select inner viewport: 0.60, 7.70, 3.05, 5.65
    Text top: "no", "##B   Resulting chord \-- concert pitch, low to high##"

    # --------------------------------------------------------------
    # C  Band energy: target vs orchestration model, by instrument
    # --------------------------------------------------------------
    vzCMax = 0
    for i from 1 to 6
        vzCMax = max(vzCMax, band_energy_'i')
        vzCMix = 0
        for p from 1 to best_n
            vzIdx = best_inst_'p'
            vzCMix = vzCMix + inst_band'i'_'vzIdx' / best_n
        endfor
        vzCMax = max(vzCMax, vzCMix)
    endfor
    vzCY = max(0.2, vzCMax * 1.15)
    if vzCY > 0.8
        vzCStep = 0.2
    elsif vzCY > 0.35
        vzCStep = 0.1
    else
        vzCStep = 0.05
    endif

    Font size: 7
    Select inner viewport: 0.60, 3.85, 6.15, 7.55
    Axes: 0, 6, 0, vzCY
    Paint rectangle: vzGround$, 0, 6, 0, vzCY
    for i from 1 to 6
        Paint rectangle: vzGrey$, i - 1 + 0.12, i - 0.52, 0, band_energy_'i'
        vzBase = 0
        for vzR from 1 to best_n
            p = vzOrd[vzR]
            vzIdx = best_inst_'p'
            vzC = inst_band'i'_'vzIdx' / best_n
            if vzC > vzCY * 0.002
                Paint rectangle: vzCol$[p], i - 0.48, i - 0.12, vzBase, min(vzBase + vzC, vzCY)
            endif
            vzBase = vzBase + vzC
        endfor
    endfor
    Select inner viewport: 0.60, 3.85, 6.15, 7.55
    Axes: 0, 6, 0, vzCY
    Colour: "Black"
    Draw inner box
    Marks left every: 1, vzCStep, "yes", "yes", "no"
    One mark bottom: 0.5, "no", "no", "no", "50\--200"
    One mark bottom: 1.5, "no", "no", "no", "200\--500"
    One mark bottom: 2.5, "no", "no", "no", ".5\--1k"
    One mark bottom: 3.5, "no", "no", "no", "1\--2k"
    One mark bottom: 4.5, "no", "no", "no", "2\--5k"
    One mark bottom: 5.5, "no", "no", "no", "5\--10k"
    Text left: "yes", "Energy share"
    Text bottom: "yes", "Band (Hz)"
    Font size: 6
    Select inner viewport: 0.60, 3.85, 6.15, 7.55
    Axes: 0, 1, 0, 1
    Colour: vzSubTx$
    Text: 0.98, "right", 0.92, "half", "grey = target   colour = model"
    Font size: 8
    Select inner viewport: 0.60, 3.85, 6.15, 7.55
    Colour: "Black"
    Text top: "no", "##C   Band energy: target vs model##"

    # --------------------------------------------------------------
    # D  Why this many instruments
    # --------------------------------------------------------------
    vzDMax = 0
    for k from 1 to max_combination_size
        if best_score_k'k' < 1e29
            vzDMax = max(vzDMax, best_score_k'k')
        endif
    endfor
    if vzDMax <= 0
        vzDMax = 1
    endif
    vzDY = vzDMax * 1.30
    if vzDY > 0.8
        vzDStep = 0.2
    elsif vzDY > 0.35
        vzDStep = 0.1
    else
        vzDStep = 0.05
    endif

    Font size: 7
    Select inner viewport: 4.45, 7.70, 6.15, 7.55
    Axes: 0.4, max_combination_size + 0.6, 0, vzDY
    Paint rectangle: vzGround$, 0.4, max_combination_size + 0.6, 0, vzDY
    for k from 1 to max_combination_size
        vzS = best_score_k'k'
        if vzS < 1e29
            vzPen = additional_instrument_penalty * (k - 1)
            if k = best_n
                vzBar$ = vzCol$[1]
            else
                vzBar$ = vzGrey$
            endif
            Paint rectangle: vzBar$, k - 0.28, k + 0.28, 0, vzS - vzPen
            if vzPen > 0
                Paint rectangle: vzGrid$, k - 0.28, k + 0.28, vzS - vzPen, vzS
            endif
        endif
    endfor
    Font size: 6
    Select inner viewport: 4.45, 7.70, 6.15, 7.55
    Axes: 0.4, max_combination_size + 0.6, 0, vzDY
    for k from 1 to max_combination_size
        vzS = best_score_k'k'
        if vzS < 1e29
            if k = best_n
                Colour: vzCol$[1]
                Text: k, "centre", vzS + vzDY * 0.03, "bottom", "##" + fixed$(vzS, 3) + "  best##"
            else
                Colour: vzSumTx$
                Text: k, "centre", vzS + vzDY * 0.03, "bottom", fixed$(vzS, 3)
            endif
        else
            Colour: vzSumTx$
            Text: k, "centre", vzDY * 0.05, "bottom", "none playable"
        endif
    endfor
    Font size: 7
    Select inner viewport: 4.45, 7.70, 6.15, 7.55
    Axes: 0.4, max_combination_size + 0.6, 0, vzDY
    Colour: "Black"
    Draw inner box
    Marks left every: 1, vzDStep, "yes", "yes", "no"
    for k from 1 to max_combination_size
        One mark bottom: k, "no", "yes", "no", string$(k)
    endfor
    Text left: "yes", "Score (lower = closer)"
    Text bottom: "yes", "Instruments in the ensemble"
    Font size: 8
    Select inner viewport: 4.45, 7.70, 6.15, 7.55
    Text top: "no", "##D   Best score by ensemble size##"

    # --------------------------------------------------------------
    # Summary strip
    # --------------------------------------------------------------
    vzCombo$ = ""
    for vzR from 1 to best_n
        p = vzOrd[vzR]
        vzIdx = best_inst_'p'
        if vzR > 1
            vzCombo$ = vzCombo$ + "  +  "
        endif
        vzCombo$ = vzCombo$ + inst_name_'vzIdx'$ + " " + voicing_label_'p'$
    endfor

    Font size: 6
    Select inner viewport: 0.60, 7.70, 8.10, 8.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: vzSumTx$
    Text: 0.01, "left", 0.83, "half", "##Orchestration:## " + vzCombo$
    Text: 0.01, "left", 0.61, "half", "##Score:## " + fixed$(best_score, 3) + " = acoustic " + fixed$(best_raw_score, 3) + " + size penalty " + fixed$(best_score - best_raw_score, 3) + "     ##Errors:## band " + fixed$(best_error_band, 3) + " (x0.45)   centroid " + fixed$(best_error_cent, 3) + " (x0.30)   spread " + fixed$(best_error_spr, 3) + " (x0.20)   odd/even " + fixed$(best_error_oe, 3) + " (x0.05)"
    Text: 0.01, "left", 0.39, "half", "##Target:## root " + fixed$(target_f0, 1) + " Hz (confidence " + fixed$(target_root_confidence, 2) + ")   centroid " + fixed$(target_centroid, 0) + " Hz vs model " + fixed$(best_mix_centroid, 0) + "   spread " + fixed$(target_spread, 0) + " vs " + fixed$(best_mix_spread, 0) + " Hz   " + string$(n_channels) + " ch power-summed"
    Text: 0.01, "left", 0.16, "half", "##Note:## the ensemble is chosen by a Gaussian timbre model (stored centroid/spread, " + target_dynamic$ + "), not measured samples (panel C); the partials in A and B are assigned afterwards and do not enter the score."
    Select inner viewport: 0.60, 7.70, 8.10, 8.90
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Select outer viewport: 0, 8, 0, 9
endif

# ---- visualization helpers ----
procedure vizSafe: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    .result$ = .s$
endproc

procedure specAt: .f
    .b = round(vizNB * ln(.f / vizSpecLo) / ln(vizSpecHi / vizSpecLo) + 0.5)
    .b = max(1, min(vizNB, .b))
    .result = vizSpecDb[.b]
endproc

# Draws one notehead at (vzNX, vzND) with any ledger lines it needs.
# Uses globals only (quote-interpolated indices do not resolve locals).
procedure drawStaffNote
    Colour: "Black"
    Line width: 1
    if vzND <= 16
        for .k from 1 to floor((18 - vzND) / 2)
            Draw line: vzNX - vzLedW, 18 - 2 * .k, vzNX + vzLedW, 18 - 2 * .k
        endfor
    endif
    if vzND >= 40
        for .k from 1 to floor((vzND - 38) / 2)
            Draw line: vzNX - vzLedW, 38 + 2 * .k, vzNX + vzLedW, 38 + 2 * .k
        endfor
    endif
    if vzND = 28
        Draw line: vzNX - vzLedW, 28, vzNX + vzLedW, 28
    endif
    if vzNFill
        Paint ellipse: vzNCol$, vzNX - vzHeadW / 2, vzNX + vzHeadW / 2, vzND - 0.85, vzND + 0.85
    else
        Colour: vzNCol$
        Line width: 2
        Draw ellipse: vzNX - vzHeadW / 2, vzNX + vzHeadW / 2, vzND - 0.85, vzND + 0.85
        Line width: 1
    endif
endproc

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="