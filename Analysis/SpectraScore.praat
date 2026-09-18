# ============================================================
# Praat AudioTools - SpectraScore_Orchestration_Matcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SpectraScore - Orchestration Matcher
#   Analyzes the multichannel target power spectrum and suggests instrument
#   combinations. Outputs a MusicXML orchestration with microtonal support
#   plus a persistent Praat Table summarizing the selected instrumentation.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
#
# Changelog v0.9.0:
#   - CORE: measured-peak detection now uses frequency-dependent local
#     prominence plus valley-aware consolidation. Close low-frequency ripples
#     are merged unless a real spectral valley separates them, reducing false
#     orchestration targets around one broad/complex low component without
#     automatically deleting genuine close pitches.
#   - CORE: spectral coverage now uses square-root-compressed peak power
#     (salience coverage) rather than raw power. A dominant fundamental can no
#     longer make one instrument appear to explain an otherwise rich harmonic
#     spectrum merely because it carries most of the physical energy.
#   - CORE: peak separation is adaptive: the user value remains the high-
#     frequency minimum, while low/mid regions use wider consolidation windows
#     (120 cents below 200 Hz, 60 cents from 200-1000 Hz) unless a sufficiently
#     deep valley proves that two peaks are distinct.
#   - CORE FIX: spectral pitch assignment no longer compares a candidate
#     fundamental to the instrument's timbral spectral centroid. Timbre and
#     register are now separate dimensions.
#   - ORCHESTRATION: instrument records now include a soft preferred/idiomatic
#     sounding range inside the absolute playable range. Spectral assignment
#     penalizes excursions outside that preferred range instead of treating
#     every technically possible extreme as equally natural.
#   - DIAGNOSTIC: Info and Results Table report mean register penalty and each
#     assigned instrument's preferred sounding range.
#
# Changelog v0.8.0:
#   - CORE: Spectral voicing no longer restricts pitch candidates to integer
#     harmonics of the estimated root. It detects general measured spectral
#     peaks across 40 Hz..10 kHz (bounded by Nyquist), then assigns playable
#     peaks directly to instruments. Polyphonic and inharmonic components can
#     therefore become orchestration pitches even when they are not Hn.
#   - CORE: root/F0 remains a descriptive reference for harmonic confidence,
#     odd/even analysis and the visualization grid; it is no longer a pitch
#     gate for Spectral mode.
#   - CORE: general-peak detection uses a log-frequency scan, relative power
#     floor and cents-domain non-maximum suppression. Peak coverage in the
#     spectral score is now coverage of these general measured peaks.
#   - OUTPUT: spectral assignments are labelled P<n>; peaks close to an integer
#     root harmonic also report the optional H<n> relation. Results Table adds
#     PeakIndex, PeakRel_dB and RootRelation columns.
#   - UI: Advanced settings replace the obsolete H1-H16 window with peak-floor,
#     minimum peak separation and maximum measured-peak controls.
#
# Changelog v0.7.0:
#   - CORE FIX: Spectral voicing now starts at H1 by default instead of H7.
#     The old H7-H16 default structurally forced high-register output.
#   - CORE FIX: measured harmonic significance is referenced to the strongest
#     measured H1..Hmax candidate, not merely to the requested sub-window.
#     This prevents numerical leakage in an empty high-harmonic region from
#     being promoted to a 0 dB "measured partial".
#   - CORE: ensemble search now evaluates spectral peak coverage and performs
#     combo-level assignments before scoring. Distinct significant partials
#     are preferred; duplicate partial assignments are allowed only as a
#     fallback and are penalized.
#   - CORE: spectral scoring now includes peak coverage and assignment quality,
#     so additional instruments can win when they cover genuinely different
#     parts of a complex spectrum; a single sine still prefers K=1.
#   - SEARCH: default extra-instrument penalty reduced from 0.01 to 0.005,
#     because ensemble complexity is now controlled by measured coverage as
#     well as by the explicit size penalty.
#   - DIAGNOSTIC: result table and Info report spectral coverage, assignment
#     cost and duplicate fraction for the selected orchestration.
#
# Changelog v0.6.3:
#   - INFO: removed raw MusicXML document dump from the Info window.
#   - SEARCH/UI: added ensemble-size selection mode: Automatic chooses the
#     best score from K=1..Max; Exact forces K=Max while still reporting
#     the per-K scores. This makes Max combination size unambiguous.
#   - DIAGNOSTIC: Info now reports the best score for every searched K.
#   - No change to target analysis, instrument descriptors or MusicXML content.
#
# Changelog v0.6.2 (2026):
#   - OUTPUT: added a persistent Praat Table object named
#     <sound>_SpectraScore_Results, one row per instrument in the selected
#     orchestration. The table exposes instrument, strategy/voicing label,
#     sounding and written note names, assigned and notated frequency, MIDI,
#     cents, transposition, dynamic, ensemble size, selection/acoustic score,
#     size penalty and the four weighted matching-error components.
#   - WORKFLOW: after creating the Table, the script reselects the MusicXML
#     Strings object so the existing VST-instrument workflow remains unchanged.
#   - No change to analysis, search, voicing or MusicXML content.
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
#          candidate partials, and the peak each instrument plays, in
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

form SpectraScore Orchestration Matcher v0.9.0
    comment Instruments: BTb Bn Cb ClBb Fl Hn Ob Tbn TpC Va Vc Vn
    sentence Instruments BTb Bn Cb ClBb Fl Hn Ob Tbn TpC Va Vc Vn
    integer Max_combination_size 4
    optionmenu Ensemble_size_mode: 1
        option Automatic (best score 1..max)
        option Exact max size
    optionmenu Spectral_profile_dynamic: 2
        option pp
        option mf
        option ff
    optionmenu Voicing_strategy: 4
        option Unison (all on root)
        option Octaves (spread by brightness)
        option Chord (root fifth octave)
        option Spectral (match measured peaks)
    boolean Enable_microtones 1
    boolean Advanced_settings 0
    boolean Save_xml_file 0
    boolean Draw_visualization 1
endform

# ---- Advanced settings (second dialog; v0.9 peak-quality defaults) ----
allow_repeated_instruments = 0
additional_instrument_penalty = 0.005
microtone_precision_cents = 12.5
peak_floor_db = -30
min_peak_separation_cents = 35
minimum_peak_prominence_db = 3
max_spectral_peaks = 24
if advanced_settings
    beginPause: "SpectraScore - advanced settings"
        comment: "Search"
        boolean: "Allow repeated instruments", allow_repeated_instruments
        real: "Additional instrument penalty", string$(additional_instrument_penalty)
        comment: "Microtones and general spectral peaks"
        positive: "Microtone precision cents", string$(microtone_precision_cents)
        real: "Peak floor dB", string$(peak_floor_db)
        positive: "Min peak separation cents", string$(min_peak_separation_cents)
        positive: "Minimum peak prominence dB", string$(minimum_peak_prominence_db)
        integer: "Max spectral peaks", string$(max_spectral_peaks)
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
if peak_floor_db > 0 or peak_floor_db < -80
    exitScript: "Peak floor dB must be between -80 and 0."
endif
if min_peak_separation_cents <= 0
    exitScript: "Minimum peak separation must be > 0 cents."
endif
if minimum_peak_prominence_db <= 0 or minimum_peak_prominence_db > 30
    exitScript: "Minimum peak prominence must be > 0 and <= 30 dB."
endif
if max_spectral_peaks < 1 or max_spectral_peaks > 64
    exitScript: "Max spectral peaks must be between 1 and 64."
endif

# ============================================================================
# INSTRUMENT DATABASE
# ============================================================================
# Using indexed variables instead of arrays for Praat compatibility

n_instruments = 0

procedure addInstrument: .name$, .midi_low, .midi_high, .pref_low, .pref_high, .transpose, .clef$, .cent_pp, .cent_mf, .cent_ff, .spr_pp, .spr_mf, .spr_ff, .odd_even, .inharm
    n_instruments += 1
    n = n_instruments
    inst_name_'n'$ = .name$
    inst_midi_low_'n' = .midi_low
    inst_midi_high_'n' = .midi_high
    inst_pref_low_'n' = .pref_low
    inst_pref_high_'n' = .pref_high
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
    @addInstrument: "BTb", 28, 60, 34, 53, 0, "bass", 350, 450, 600, 200, 280, 400, 0.65, 0.02
endif
if bn
    @addInstrument: "Bn", 34, 75, 40, 69, 0, "bass", 400, 520, 680, 220, 300, 420, 0.70, 0.03
endif
if cb
    @addInstrument: "Cb", 28, 67, 28, 55, -12, "bass", 280, 380, 520, 180, 250, 350, 0.60, 0.04
endif
if clBb
    @addInstrument: "ClBb", 50, 94, 55, 88, -2, "treble", 800, 1100, 1500, 400, 550, 750, 0.55, 0.02
endif
if fl
    @addInstrument: "Fl", 60, 96, 60, 91, 0, "treble", 1200, 1600, 2200, 600, 800, 1100, 0.50, 0.01
endif
if hn
    @addInstrument: "Hn", 34, 77, 41, 72, -7, "treble", 450, 600, 850, 250, 350, 500, 0.68, 0.03
endif
if ob
    @addInstrument: "Ob", 58, 91, 60, 84, 0, "treble", 1000, 1350, 1800, 500, 650, 900, 0.72, 0.02
endif
if tbn
    @addInstrument: "Tbn", 40, 72, 40, 67, 0, "bass", 380, 500, 680, 210, 290, 410, 0.67, 0.02
endif
if tpC
    @addInstrument: "TpC", 52, 82, 55, 79, 0, "treble", 1100, 1500, 2100, 550, 750, 1000, 0.58, 0.02
endif
if va
    @addInstrument: "Va", 48, 84, 48, 79, 0, "alto", 600, 850, 1200, 320, 450, 650, 0.62, 0.02
endif
if vc
    @addInstrument: "Vc", 36, 76, 36, 69, 0, "bass", 400, 580, 820, 240, 340, 480, 0.64, 0.03
endif
if vn
    @addInstrument: "Vn", 55, 103, 55, 96, 0, "treble", 900, 1250, 1750, 450, 600, 850, 0.60, 0.02
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

writeInfoLine: "=== SpectraScore Orchestration Matcher v0.9.0 ==="
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
# analysis so every descriptor and every measured peak refers to the same
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
# 3. ROOT-HARMONIC DESCRIPTORS + GENERAL MEASURED SPECTRAL PEAKS
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

# Spectral voicing uses GENERAL measured peaks, not only integer harmonics of
# the detected root. The root remains a descriptor; it does not gate pitch
# candidates. We scan log frequency, find local maxima above a relative power
# v0.9 general-peak detector. First scan in log-frequency, then apply a
# small frequency-dependent smoothing window. Low-frequency FFT/interference
# ripples otherwise create several local maxima around one perceptual component.
# Candidate peaks must also have local prominence, and close candidates are
# consolidated unless a real valley separates them.
peak_search_min_hz = 40
peak_search_max_hz = min(10000, nyquist * 0.95)
peak_scan_step_cents = 12.5
if enable_microtones and microtone_precision_cents < peak_scan_step_cents
    peak_scan_step_cents = microtone_precision_cents
endif
if peak_scan_step_cents < 2.5
    peak_scan_step_cents = 2.5
endif

if peak_search_max_hz <= peak_search_min_hz
    peak_search_max_hz = nyquist * 0.90
endif

n_peak_scan = floor(1200 * log2(peak_search_max_hz / peak_search_min_hz) / peak_scan_step_cents) + 1
peak_scan_max_density = 0
peak_scan_global_index = 0
for ps from 1 to n_peak_scan
    scan_freq = peak_search_min_hz * 2 ^ (((ps - 1) * peak_scan_step_cents) / 1200)
    peak_scan_freq_'ps' = scan_freq
    peak_halfwidth = scan_freq * 0.003
    if peak_halfwidth < 1
        peak_halfwidth = 1
    endif
    @combinedBandEnergy: scan_freq - peak_halfwidth, scan_freq + peak_halfwidth
    scan_density = combinedBandEnergy.result / (2 * peak_halfwidth)
    peak_scan_raw_'ps' = scan_density
endfor

# Adaptive constant-Q smoothing: wider in cents at low frequencies, where the
# raw scan is most vulnerable to side-lobes/beating ripples.
for ps from 1 to n_peak_scan
    scan_freq = peak_scan_freq_'ps'
    if scan_freq < 200
        smooth_cents = 50
    elsif scan_freq < 1000
        smooth_cents = 25
    else
        smooth_cents = 12.5
    endif
    smooth_steps = max(1, round(smooth_cents / peak_scan_step_cents))
    smooth_sum = 0
    smooth_weight = 0
    left_ps = max(1, ps - smooth_steps)
    right_ps = min(n_peak_scan, ps + smooth_steps)
    for sj from left_ps to right_ps
        distance_steps = abs(sj - ps)
        weight = smooth_steps + 1 - distance_steps
        smooth_sum += weight * peak_scan_raw_'sj'
        smooth_weight += weight
    endfor
    if smooth_weight > 0
        peak_scan_density_'ps' = smooth_sum / smooth_weight
    else
        peak_scan_density_'ps' = peak_scan_raw_'ps'
    endif
    if peak_scan_density_'ps' > peak_scan_max_density
        peak_scan_max_density = peak_scan_density_'ps'
        peak_scan_global_index = ps
    endif
endfor

# Strongest LOCAL maximum defines the relative floor.
peak_local_max_density = 0
for ps from 2 to n_peak_scan - 1
    ps_prev = ps - 1
    ps_next = ps + 1
    this_density = peak_scan_density_'ps'
    if this_density >= peak_scan_density_'ps_prev' and this_density > peak_scan_density_'ps_next'
        if this_density > peak_local_max_density
            peak_local_max_density = this_density
        endif
    endif
endfor
if peak_local_max_density > 0
    peak_reference_density = peak_local_max_density
elsif peak_scan_max_density > 0
    peak_reference_density = peak_scan_max_density
else
    peak_reference_density = 0
endif
if peak_reference_density > 0
    measured_peak_threshold = peak_reference_density * 10 ^ (peak_floor_db / 10)
else
    measured_peak_threshold = 0
endif

# Local prominence in a frequency-dependent neighbourhood. The baseline is the
# higher of the left/right local minima, analogous to spectral peak prominence.
procedure getPeakProminence: .ps, .freq
    .this_density = peak_scan_density_'.ps'
    .window_cents = min_peak_separation_cents
    if .freq < 200
        .window_cents = max(.window_cents, 120)
    elsif .freq < 1000
        .window_cents = max(.window_cents, 60)
    endif
    .steps = max(1, round(.window_cents / peak_scan_step_cents))
    .left_min = .this_density
    .right_min = .this_density
    .left_start = max(1, .ps - .steps)
    .right_end = min(n_peak_scan, .ps + .steps)
    if .left_start < .ps
        for .j from .left_start to .ps - 1
            if peak_scan_density_'.j' < .left_min
                .left_min = peak_scan_density_'.j'
            endif
        endfor
    endif
    if .ps < .right_end
        for .j from .ps + 1 to .right_end
            if peak_scan_density_'.j' < .right_min
                .right_min = peak_scan_density_'.j'
            endif
        endfor
    endif
    .baseline = max(.left_min, .right_min)
    if .baseline <= 1e-300
        .prom_db = 100
    elsif .this_density <= .baseline
        .prom_db = 0
    else
        .prom_db = 10 * log10(.this_density / .baseline)
    endif
endproc

n_measured_peaks = 0
peak_selection_done = 0
for pick from 1 to max_spectral_peaks
    if not peak_selection_done
        best_peak_index = 0
        best_peak_density = -1
        best_peak_prominence = 0
        for ps from 2 to n_peak_scan - 1
            this_density = peak_scan_density_'ps'
            if this_density >= measured_peak_threshold and this_density > 0
                ps_prev = ps - 1
                ps_next = ps + 1
                prev_density = peak_scan_density_'ps_prev'
                next_density = peak_scan_density_'ps_next'
                if this_density >= prev_density and this_density > next_density
                    this_freq = peak_scan_freq_'ps'
                    @getPeakProminence: ps, this_freq
                    this_prominence = getPeakProminence.prom_db
                    if this_prominence >= minimum_peak_prominence_db
                        separated = 1
                        for q from 1 to n_measured_peaks
                            selected_freq = measured_peak_freq_'q'
                            separation = abs(1200 * log2(this_freq / selected_freq))
                            adaptive_separation = min_peak_separation_cents
                            lower_freq = min(this_freq, selected_freq)
                            if lower_freq < 200
                                adaptive_separation = max(adaptive_separation, 120)
                            elsif lower_freq < 1000
                                adaptive_separation = max(adaptive_separation, 60)
                            endif

                            if separation < adaptive_separation
                                # Keep two close peaks only when the valley
                                # between them is deep enough to establish two
                                # distinct spectral components.
                                selected_ps = measured_peak_scan_index_'q'
                                valley_density = min(this_density, measured_peak_energy_'q')
                                valley_left = min(ps, selected_ps)
                                valley_right = max(ps, selected_ps)
                                if valley_right > valley_left + 1
                                    for vj from valley_left + 1 to valley_right - 1
                                        if peak_scan_density_'vj' < valley_density
                                            valley_density = peak_scan_density_'vj'
                                        endif
                                    endfor
                                endif
                                weaker_peak = min(this_density, measured_peak_energy_'q')
                                if valley_density <= 1e-300
                                    valley_drop_db = 100
                                elsif weaker_peak > valley_density
                                    valley_drop_db = 10 * log10(weaker_peak / valley_density)
                                else
                                    valley_drop_db = 0
                                endif
                                if valley_drop_db < minimum_peak_prominence_db
                                    separated = 0
                                endif
                            endif
                        endfor
                        if separated and this_density > best_peak_density
                            best_peak_density = this_density
                            best_peak_index = ps
                            best_peak_prominence = this_prominence
                        endif
                    endif
                endif
            endif
        endfor

        if best_peak_index = 0
            peak_selection_done = 1
        else
            n_measured_peaks += 1
            measured_peak_freq_'n_measured_peaks' = peak_scan_freq_'best_peak_index'
            measured_peak_energy_'n_measured_peaks' = best_peak_density
            measured_peak_scan_index_'n_measured_peaks' = best_peak_index
            measured_peak_prominence_'n_measured_peaks' = best_peak_prominence
        endif
    endif
endfor

# Safety fallback for extremely smooth/sparse spectra.
if n_measured_peaks = 0 and peak_scan_global_index > 0
    n_measured_peaks = 1
    measured_peak_freq_1 = peak_scan_freq_'peak_scan_global_index'
    measured_peak_energy_1 = peak_scan_density_'peak_scan_global_index'
    measured_peak_scan_index_1 = peak_scan_global_index
    measured_peak_prominence_1 = 0
endif

# Root-anchor rescue. Root estimation remains descriptive and does not gate the
# general detector, but a broad fundamental can fail a local-prominence test
# precisely because energy around it forms a plateau. When root confidence is
# meaningful, retain the strongest measured location within +/-50 cents of the
# root if it clears the global peak floor and no selected peak already represents
# that neighbourhood. This restores a physically strong fundamental without
# forcing unrelated peaks onto an Hn grid.
if target_root_confidence >= 0.25 and target_f0 >= peak_search_min_hz and target_f0 <= peak_search_max_hz
    root_anchor_ps = 0
    root_anchor_density = 0
    for ps from 1 to n_peak_scan
        root_anchor_cents = abs(1200 * log2(peak_scan_freq_'ps' / target_f0))
        if root_anchor_cents <= 50 and peak_scan_density_'ps' > root_anchor_density
            root_anchor_density = peak_scan_density_'ps'
            root_anchor_ps = ps
        endif
    endfor
    if root_anchor_ps > 0 and root_anchor_density >= measured_peak_threshold
        root_anchor_freq = peak_scan_freq_'root_anchor_ps'
        root_anchor_present = 0
        for q from 1 to n_measured_peaks
            root_anchor_sep = abs(1200 * log2(measured_peak_freq_'q' / root_anchor_freq))
            if root_anchor_sep <= 60
                root_anchor_present = 1
            endif
        endfor
        if not root_anchor_present
            @getPeakProminence: root_anchor_ps, root_anchor_freq
            if n_measured_peaks < max_spectral_peaks
                n_measured_peaks += 1
                measured_peak_freq_'n_measured_peaks' = root_anchor_freq
                measured_peak_energy_'n_measured_peaks' = root_anchor_density
                measured_peak_scan_index_'n_measured_peaks' = root_anchor_ps
                measured_peak_prominence_'n_measured_peaks' = getPeakProminence.prom_db
            else
                weakest_pk = 1
                weakest_energy = measured_peak_energy_1
                for q from 2 to n_measured_peaks
                    if measured_peak_energy_'q' < weakest_energy
                        weakest_energy = measured_peak_energy_'q'
                        weakest_pk = q
                    endif
                endfor
                if root_anchor_density > weakest_energy
                    measured_peak_freq_'weakest_pk' = root_anchor_freq
                    measured_peak_energy_'weakest_pk' = root_anchor_density
                    measured_peak_scan_index_'weakest_pk' = root_anchor_ps
                    measured_peak_prominence_'weakest_pk' = getPeakProminence.prom_db
                endif
            endif
        endif
    endif
endif

# Sort selected peaks by frequency. Keep scan-index/prominence metadata aligned.
if n_measured_peaks > 1
    for a from 1 to n_measured_peaks - 1
        for b from a + 1 to n_measured_peaks
            if measured_peak_freq_'b' < measured_peak_freq_'a'
                temp_freq = measured_peak_freq_'a'
                temp_energy = measured_peak_energy_'a'
                temp_scan = measured_peak_scan_index_'a'
                temp_prom = measured_peak_prominence_'a'
                measured_peak_freq_'a' = measured_peak_freq_'b'
                measured_peak_energy_'a' = measured_peak_energy_'b'
                measured_peak_scan_index_'a' = measured_peak_scan_index_'b'
                measured_peak_prominence_'a' = measured_peak_prominence_'b'
                measured_peak_freq_'b' = temp_freq
                measured_peak_energy_'b' = temp_energy
                measured_peak_scan_index_'b' = temp_scan
                measured_peak_prominence_'b' = temp_prom
            endif
        endfor
    endfor
endif

measured_peak_max = 0
highest_measured_peak = peak_search_min_hz
for pk from 1 to n_measured_peaks
    if measured_peak_energy_'pk' > measured_peak_max
        measured_peak_max = measured_peak_energy_'pk'
    endif
    highest_measured_peak = max(highest_measured_peak, measured_peak_freq_'pk')
endfor

# Coverage is based on compressed salience, not raw power. This keeps a strong
# fundamental from numerically overwhelming several clearly resolved partials.
measured_peak_total = 0
for pk from 1 to n_measured_peaks
    if measured_peak_max > 0
        measured_peak_weight_'pk' = sqrt(max(0, measured_peak_energy_'pk' / measured_peak_max))
    else
        measured_peak_weight_'pk' = 0
    endif
    measured_peak_total += measured_peak_weight_'pk'
endfor

# Optional relation to the root: this is descriptive only. A peak is labelled
# Hn only when it lies within 35 cents of that integer harmonic; otherwise it
# remains explicitly non-harmonic/general.
for pk from 1 to n_measured_peaks
    measured_peak_harmonic_'pk' = 0
    measured_peak_harmonic_cents_'pk' = 0
    nearest_h = round(measured_peak_freq_'pk' / target_f0)
    if nearest_h >= 1
        nearest_h_freq = target_f0 * nearest_h
        relation_cents = 1200 * log2(measured_peak_freq_'pk' / nearest_h_freq)
        if abs(relation_cents) <= 35
            measured_peak_harmonic_'pk' = nearest_h
            measured_peak_harmonic_cents_'pk' = relation_cents
        endif
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
    vizSpecHi = max(5000, 1.15 * highest_measured_peak)
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

# Spectra are no longer needed after all target features/peaks are stored.
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
    appendInfoLine: "General measured spectral peaks (floor ", fixed$(peak_floor_db, 1), " dB; prominence >= ", fixed$(minimum_peak_prominence_db, 1), " dB; adaptive consolidation):"
    for pk from 1 to n_measured_peaks
        if measured_peak_max > 0
            rel_peak_db = 10 * log10(measured_peak_energy_'pk' / measured_peak_max)
        else
            rel_peak_db = -999
        endif
        if measured_peak_harmonic_'pk' > 0
            relation$ = "H" + string$(measured_peak_harmonic_'pk') + " " + fixed$(measured_peak_harmonic_cents_'pk', 1) + "c"
        else
            relation$ = "non-harmonic"
        endif
        appendInfoLine: "  P", pk, ": ", fixed$(measured_peak_freq_'pk', 1), " Hz  ", fixed$(rel_peak_db, 1), " dB  prom ", fixed$(measured_peak_prominence_'pk', 1), " dB  [", relation$, "]"
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

# Soft register realism. Absolute MIDI range remains a hard playability gate;
# this function measures only how far a sounding pitch lies outside the
# instrument's preferred/idiomatic core. One octave beyond the preferred range
# reaches penalty 1; farther extremes remain playable but do not get cheaper.
procedure getRegisterPenalty: .inst_idx, .midi
    .pref_low = inst_pref_low_'.inst_idx'
    .pref_high = inst_pref_high_'.inst_idx'
    if .midi < .pref_low
        .penalty = (.pref_low - .midi) / 12
    elsif .midi > .pref_high
        .penalty = (.midi - .pref_high) / 12
    else
        .penalty = 0
    endif
    if .penalty > 1
        .penalty = 1
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
        # Spectral voicing: choose a general MEASURED spectral peak. Timbre is
        # deliberately NOT used as a pitch target: instrument spectral centroid
        # describes colour, not the fundamental it should play. Candidate pitch
        # cost therefore combines measured peak strength with idiomatic register.
        .found = 0
        .min_cost = 1e30
        .peak_index = 0
        .register_penalty = 1

        for .pk from 1 to n_measured_peaks
            .peak_freq = measured_peak_freq_'.pk'
            .peak_midi = 69 + 12 * log2(.peak_freq / 440)
            if .peak_midi >= .low and .peak_midi <= .high
                .rel_energy = measured_peak_energy_'.pk' / measured_peak_max
                if .rel_energy < 0
                    .rel_energy = 0
                endif
                if .rel_energy > 1
                    .rel_energy = 1
                endif
                .energy_cost = 1 - sqrt(.rel_energy)
                @getRegisterPenalty: .inst_idx, .peak_midi
                .reg_cost = getRegisterPenalty.penalty
                .cost = 0.55 * .energy_cost + 0.45 * .reg_cost
                if .cost < .min_cost
                    .min_cost = .cost
                    .peak_index = .pk
                    .target_freq = .peak_freq
                    .midi_exact = .peak_midi
                    .register_penalty = .reg_cost
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

# Combo-level spectral assignment. The old code assigned each instrument
# independently after ensemble selection, so several instruments could all
# choose the same peak and larger ensembles gained no credit for covering
# additional target structure. Here we greedily match instrument positions to
# significant measured peaks. Unique partials are preferred. If a forced
# ensemble has more instruments than distinct playable peaks, duplication is
# allowed as a fallback but receives an explicit cost.
procedure assignSpectralCombo: .n_in_combo
    .valid = 1
    .covered_energy = 0
    .cost_sum = 0
    .register_sum = 0
    .duplicate_count = 0

    for .pos from 1 to .n_in_combo
        spec_done_'.pos' = 0
        current_spec_peak_'.pos' = 0
        current_spec_freq_'.pos' = undefined
        current_spec_cost_'.pos' = 1
        current_spec_register_'.pos' = 1
    endfor
    for .pk from 1 to n_measured_peaks
        spec_used_peak_'.pk' = 0
    endfor

    for .step from 1 to .n_in_combo
        .best_metric = 1e30
        .best_pos = 0
        .best_peak = 0
        .best_freq = undefined
        .best_pair_cost = 1
        .best_register = 1

        # First pass: unused significant general peaks only.
        for .pos from 1 to .n_in_combo
            if spec_done_'.pos' = 0
                .ix = combo_idx_'.pos'
                .low = inst_midi_low_'.ix'
                .high = inst_midi_high_'.ix'
                for .pk from 1 to n_measured_peaks
                    if spec_used_peak_'.pk' = 0
                        .freq = measured_peak_freq_'.pk'
                        .midi = 69 + 12 * log2(.freq / 440)
                        if .midi >= .low and .midi <= .high
                            .rel_energy = measured_peak_energy_'.pk' / measured_peak_max
                            if .rel_energy < 0
                                .rel_energy = 0
                            endif
                            if .rel_energy > 1
                                .rel_energy = 1
                            endif
                            .energy_cost = 1 - sqrt(.rel_energy)
                            @getRegisterPenalty: .ix, .midi
                            .reg_cost = getRegisterPenalty.penalty
                            .pair_cost = 0.55 * .energy_cost + 0.45 * .reg_cost
                            if .pair_cost < .best_metric
                                .best_metric = .pair_cost
                                .best_pos = .pos
                                .best_peak = .pk
                                .best_freq = .freq
                                .best_pair_cost = .pair_cost
                                .best_register = .reg_cost
                            endif
                        endif
                    endif
                endfor
            endif
        endfor

        # Fallback: allow doubling an already-used peak. Exact-K remains usable
        # on sparse spectra, but duplication receives an explicit cost.
        if .best_pos = 0
            for .pos from 1 to .n_in_combo
                if spec_done_'.pos' = 0
                    .ix = combo_idx_'.pos'
                    .low = inst_midi_low_'.ix'
                    .high = inst_midi_high_'.ix'
                    for .pk from 1 to n_measured_peaks
                        .freq = measured_peak_freq_'.pk'
                        .midi = 69 + 12 * log2(.freq / 440)
                        if .midi >= .low and .midi <= .high
                            .rel_energy = measured_peak_energy_'.pk' / measured_peak_max
                            if .rel_energy < 0
                                .rel_energy = 0
                            endif
                            if .rel_energy > 1
                                .rel_energy = 1
                            endif
                            .energy_cost = 1 - sqrt(.rel_energy)
                            @getRegisterPenalty: .ix, .midi
                            .reg_cost = getRegisterPenalty.penalty
                            .pair_cost = 0.55 * .energy_cost + 0.45 * .reg_cost + 0.35
                            if .pair_cost < .best_metric
                                .best_metric = .pair_cost
                                .best_pos = .pos
                                .best_peak = .pk
                                .best_freq = .freq
                                .best_pair_cost = .pair_cost
                                .best_register = .reg_cost
                            endif
                        endif
                    endfor
                endif
            endfor
        endif

        if .best_pos = 0
            .valid = 0
        else
            spec_done_'.best_pos' = 1
            current_spec_peak_'.best_pos' = .best_peak
            current_spec_freq_'.best_pos' = .best_freq
            current_spec_cost_'.best_pos' = .best_pair_cost
            current_spec_register_'.best_pos' = .best_register
            .cost_sum += .best_pair_cost
            .register_sum += .best_register
            if spec_used_peak_'.best_peak' = 0
                spec_used_peak_'.best_peak' = 1
                .covered_energy += measured_peak_weight_'.best_peak'
            else
                .duplicate_count += 1
            endif
        endif
    endfor

    if .valid and measured_peak_total > 0
        .coverage = .covered_energy / measured_peak_total
    else
        .coverage = 0
    endif
    if .coverage > 1
        .coverage = 1
    endif
    if .n_in_combo > 0
        .mean_cost = .cost_sum / .n_in_combo
        .mean_register_penalty = .register_sum / .n_in_combo
        .duplicate_fraction = .duplicate_count / .n_in_combo
    else
        .mean_cost = 1
        .mean_register_penalty = 1
        .duplicate_fraction = 1
    endif
    if .mean_cost > 1
        .mean_cost = 1
    endif
endproc

procedure comboPlayable: .n_in_combo
    .can = 1
    if voicing_strategy = 4
        @assignSpectralCombo: .n_in_combo
        .can = assignSpectralCombo.valid
        current_spec_coverage = assignSpectralCombo.coverage
        current_spec_assignment_cost = assignSpectralCombo.mean_cost
        current_spec_register_penalty = assignSpectralCombo.mean_register_penalty
        current_spec_duplicate_fraction = assignSpectralCombo.duplicate_fraction
    else
        current_spec_coverage = 0
        current_spec_assignment_cost = 0
        current_spec_register_penalty = 0
        current_spec_duplicate_fraction = 0
        for .pos from 1 to .n_in_combo
            .ix = combo_idx_'.pos'
            @assignVoicing: .ix, .pos, .n_in_combo
            if not assignVoicing.valid
                .can = 0
            endif
        endfor
    endif
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
    if voicing_strategy = 4
        .d_coverage = 1 - current_spec_coverage
        .d_assignment = current_spec_assignment_cost
        .d_register = current_spec_register_penalty
        .d_duplicate = current_spec_duplicate_fraction
        # Spectral mode evaluates timbral-envelope similarity, measured-peak
        # coverage, assignment quality and idiomatic register independently.
        .raw_score = 0.32 * .d_band + 0.21 * .d_cent + 0.12 * .d_spr + 0.21 * .d_coverage + 0.05 * .d_assignment + 0.05 * .d_register + 0.03 * .d_duplicate + 0.01 * .oe_confidence * .d_oe
    else
        .d_coverage = 0
        .d_assignment = 0
        .d_register = 0
        .d_duplicate = 0
        .raw_score = 0.45 * .d_band + 0.30 * .d_cent + 0.20 * .d_spr + 0.05 * .oe_confidence * .d_oe
    endif
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
if ensemble_size_mode = 1
    appendInfoLine: "Ensemble-size mode: Automatic (best score from K=1..", max_combination_size, ")"
else
    appendInfoLine: "Ensemble-size mode: Exact K=", max_combination_size
endif
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
        if scoreCombo.score < best_score and (ensemble_size_mode = 1 or max_combination_size = 1)
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
                    if scoreCombo.score < best_score and (ensemble_size_mode = 1 or max_combination_size = 2)
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
                            if scoreCombo.score < best_score and (ensemble_size_mode = 1 or max_combination_size = 3)
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
                                    if scoreCombo.score < best_score and (ensemble_size_mode = 1 or max_combination_size = 4)
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

appendInfoLine: ""
appendInfoLine: "Best selection score by ensemble size:"
if best_score_k1 < 1e29
    appendInfoLine: "  K=1: ", fixed$(best_score_k1, 4)
else
    appendInfoLine: "  K=1: not playable"
endif
if max_combination_size >= 2
    if best_score_k2 < 1e29
        appendInfoLine: "  K=2: ", fixed$(best_score_k2, 4)
    else
        appendInfoLine: "  K=2: not playable"
    endif
endif
if max_combination_size >= 3
    if best_score_k3 < 1e29
        appendInfoLine: "  K=3: ", fixed$(best_score_k3, 4)
    else
        appendInfoLine: "  K=3: not playable"
    endif
endif
if max_combination_size >= 4
    if best_score_k4 < 1e29
        appendInfoLine: "  K=4: ", fixed$(best_score_k4, 4)
    else
        appendInfoLine: "  K=4: not playable"
    endif
endif

if best_n = 0
    exitScript: "No playable instrument combination found for the selected voicing strategy, ensemble-size mode and ranges."
endif

# Recompute descriptors for the selected combination for reporting/visualization.
for p from 1 to best_n
    combo_idx_'p' = best_inst_'p'
endfor
@comboPlayable: best_n
@scoreCombo: best_n
if voicing_strategy = 4
    for p from 1 to best_n
        best_spec_peak_'p' = current_spec_peak_'p'
        best_spec_freq_'p' = current_spec_freq_'p'
        best_spec_cost_'p' = current_spec_cost_'p'
        best_spec_register_'p' = current_spec_register_'p'
    endfor
endif
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
best_error_coverage = scoreCombo.d_coverage
best_error_assignment = scoreCombo.d_assignment
best_error_register = scoreCombo.d_register
best_error_duplicate = scoreCombo.d_duplicate

appendInfoLine: ""
appendInfoLine: "=== BEST MATCH ==="
appendInfoLine: "Selection score: ", fixed$(best_score, 4), "  (acoustic=", fixed$(best_raw_score, 4), ", size penalty=", fixed$(best_score - best_raw_score, 4), ")"
appendInfoLine: "Matched centroid: ", fixed$(best_mix_centroid, 0), " Hz"
appendInfoLine: "Matched spread: ", fixed$(best_mix_spread, 0), " Hz"
appendInfoLine: "Matched odd-harmonic fraction: ", fixed$(best_mix_odd_even, 3)
appendInfoLine: "Band-envelope distance: ", fixed$(best_error_band, 4)
if voicing_strategy = 4
    appendInfoLine: "Measured-peak salience coverage: ", fixed$(1 - best_error_coverage, 3)
    appendInfoLine: "Assignment cost: ", fixed$(best_error_assignment, 3), "   register penalty: ", fixed$(best_error_register, 3), "   duplicate fraction: ", fixed$(best_error_duplicate, 3)
endif
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
    if voicing_strategy = 4
        assigned_freq = best_spec_freq_'p'
        assigned_peak = best_spec_peak_'p'
        assigned_midi_exact = 69 + 12 * log2(assigned_freq / 440)
        assigned_midi_note = round(assigned_midi_exact)
        assigned_cents = (assigned_midi_exact - assigned_midi_note) * 100
        if enable_microtones
            assigned_cents = round(assigned_cents / microtone_precision_cents) * microtone_precision_cents
        else
            assigned_cents = 0
        endif
        voicing_midi_'p' = assigned_midi_note
        voicing_cents_'p' = assigned_cents
        voicing_freq_'p' = assigned_freq
        voicing_register_penalty_'p' = best_spec_register_'p'
    else
        @assignVoicing: idx, p, best_n
        voicing_midi_'p' = assignVoicing.midi_note
        voicing_cents_'p' = assignVoicing.cents_offset
        voicing_freq_'p' = assignVoicing.target_freq
        @getRegisterPenalty: idx, voicing_midi_'p' + voicing_cents_'p' / 100
        voicing_register_penalty_'p' = getRegisterPenalty.penalty
    endif
    
    # Spectral mode labels the selected general peak P<n>; when that peak is
    # genuinely close to an integer harmonic of the root, the H<n> relation is
    # appended descriptively. Other strategies retain interval labels.
    if voicing_strategy = 4
        peak_num = assigned_peak
        if measured_peak_harmonic_'peak_num' > 0
            labelStr$ = "P" + string$(peak_num) + " (H" + string$(measured_peak_harmonic_'peak_num') + ")"
        else
            labelStr$ = "P" + string$(peak_num)
        endif
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
    appendInfoLine: inst_name_'idx'$, ": ", labelStr$, " (", fixed$(voicing_freq_'p', 1), " Hz) -> MIDI ", fixed$(voicing_midi_'p', 1), " + ", fixed$(voicing_cents_'p', 1), " cents = ", fixed$(440 * 2 ^ ((voicing_midi_'p' + voicing_cents_'p' / 100 - 69) / 12), 1), " Hz notated   preferred MIDI ", inst_pref_low_'idx', "-", inst_pref_high_'idx', "   reg penalty ", fixed$(voicing_register_penalty_'p', 2)
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
@xmlAdd: "    <creator type=""software"">Praat SpectraScore v0.9.0</creator>"
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
# RESULTS TABLE
# ============================================================================
# Persistent, inspectable summary of the selected orchestration. One row per
# instrument; ensemble-level diagnostics are repeated intentionally so that
# each exported row remains self-contained when the Table is saved as CSV/TSV.
if voicing_strategy = 1
    table_strategy$ = "Unison"
elsif voicing_strategy = 2
    table_strategy$ = "Octaves"
elsif voicing_strategy = 3
    table_strategy$ = "Chord"
else
    table_strategy$ = "Spectral"
endif

results_table = Create Table with column names: sound_name$ + "_SpectraScore_Results", best_n,
    ... "Part Instrument Strategy Voicing PeakIndex PeakRel_dB PeakProminence_dB RootRelation SoundingNote Assignment_Hz MIDI Cents Notated_Hz WrittenNote Transpose_semitones PreferredLow_MIDI PreferredHigh_MIDI RegisterPenalty Dynamic K SelectionScore AcousticScore SizePenalty BandDistance CentroidError SpreadError OddEvenError PeakSalienceCoverage AssignmentCost MeanRegisterPenalty DuplicateFraction Root_Hz RootConfidence TargetCentroid_Hz MatchedCentroid_Hz TargetSpread_Hz MatchedSpread_Hz"
results_table_name$ = selected$("Table")

for p from 1 to best_n
    idx = best_inst_'p'

    # Sounding pitch name: nearest equal-tempered semitone; the separate Cents
    # column carries the exact quantized deviation used by MusicXML.
    table_sound_midi = voicing_midi_'p'
    table_sound_pc = table_sound_midi mod 12
    if table_sound_pc < 0
        table_sound_pc = table_sound_pc + 12
    endif
    table_sound_oct = floor(table_sound_midi / 12) - 1
    table_sound_note$ = step_'table_sound_pc'$
    if alter_'table_sound_pc' <> 0
        table_sound_note$ = table_sound_note$ + "#"
    endif
    table_sound_note$ = table_sound_note$ + string$(table_sound_oct)

    # Written pitch follows the same transposition rule as the MusicXML block.
    table_written_midi = table_sound_midi - inst_transpose_'idx'
    table_written_pc = table_written_midi mod 12
    if table_written_pc < 0
        table_written_pc = table_written_pc + 12
    endif
    table_written_oct = floor(table_written_midi / 12) - 1
    table_written_note$ = step_'table_written_pc'$
    if alter_'table_written_pc' <> 0
        table_written_note$ = table_written_note$ + "#"
    endif
    table_written_note$ = table_written_note$ + string$(table_written_oct)

    table_notated_hz = 440 * 2 ^ ((voicing_midi_'p' + voicing_cents_'p' / 100 - 69) / 12)

    selectObject: results_table
    Set numeric value: p, "Part", p
    Set string value: p, "Instrument", inst_name_'idx'$
    Set string value: p, "Strategy", table_strategy$
    Set string value: p, "Voicing", voicing_label_'p'$
    if voicing_strategy = 4
        table_peak = best_spec_peak_'p'
        if measured_peak_max > 0
            table_peak_db = 10 * log10(measured_peak_energy_'table_peak' / measured_peak_max)
        else
            table_peak_db = -999
        endif
        table_peak_prominence = measured_peak_prominence_'table_peak'
        if measured_peak_harmonic_'table_peak' > 0
            table_root_relation$ = "H" + string$(measured_peak_harmonic_'table_peak') + " " + fixed$(measured_peak_harmonic_cents_'table_peak', 1) + "c"
        else
            table_root_relation$ = "non-harmonic"
        endif
    else
        table_peak = 0
        table_peak_db = 0
        table_peak_prominence = 0
        table_root_relation$ = "n/a"
    endif
    Set numeric value: p, "PeakIndex", table_peak
    Set numeric value: p, "PeakRel_dB", table_peak_db
    Set numeric value: p, "PeakProminence_dB", table_peak_prominence
    Set string value: p, "RootRelation", table_root_relation$
    Set string value: p, "SoundingNote", table_sound_note$
    Set numeric value: p, "Assignment_Hz", voicing_freq_'p'
    Set numeric value: p, "MIDI", voicing_midi_'p'
    Set numeric value: p, "Cents", voicing_cents_'p'
    Set numeric value: p, "Notated_Hz", table_notated_hz
    Set string value: p, "WrittenNote", table_written_note$
    Set numeric value: p, "Transpose_semitones", inst_transpose_'idx'
    Set numeric value: p, "PreferredLow_MIDI", inst_pref_low_'idx'
    Set numeric value: p, "PreferredHigh_MIDI", inst_pref_high_'idx'
    Set numeric value: p, "RegisterPenalty", voicing_register_penalty_'p'
    Set string value: p, "Dynamic", target_dynamic$
    Set numeric value: p, "K", best_n
    Set numeric value: p, "SelectionScore", best_score
    Set numeric value: p, "AcousticScore", best_raw_score
    Set numeric value: p, "SizePenalty", best_score - best_raw_score
    Set numeric value: p, "BandDistance", best_error_band
    Set numeric value: p, "CentroidError", best_error_cent
    Set numeric value: p, "SpreadError", best_error_spr
    Set numeric value: p, "OddEvenError", best_error_oe
    Set numeric value: p, "PeakSalienceCoverage", 1 - best_error_coverage
    Set numeric value: p, "AssignmentCost", best_error_assignment
    Set numeric value: p, "MeanRegisterPenalty", best_error_register
    Set numeric value: p, "DuplicateFraction", best_error_duplicate
    Set numeric value: p, "Root_Hz", target_f0
    Set numeric value: p, "RootConfidence", target_root_confidence
    Set numeric value: p, "TargetCentroid_Hz", target_centroid
    Set numeric value: p, "MatchedCentroid_Hz", best_mix_centroid
    Set numeric value: p, "TargetSpread_Hz", target_spread
    Set numeric value: p, "MatchedSpread_Hz", best_mix_spread
endfor

# Preserve the established VST workflow: leave the MusicXML Strings object
# selected when the script finishes creating its persistent outputs.
selectObject: musicxml_object

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
appendInfoLine: "Results table: Table ", results_table_name$, " (", best_n, " instrument rows)"

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
        vzStrat$ = "Spectral measured peaks"
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
    Text: 0.5, "centre", 0.68, "half", "##SpectraScore Orchestration Matcher v0.9.0##"
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
        vzWLo = max(peak_search_min_hz, vizSpecLo)
        vzWHi = min(peak_search_max_hz, vizSpecHi)
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

    # measured candidate general peaks (spectral voicing only)
    if voicing_strategy = 4
        for pk from 1 to n_measured_peaks
            vzF = measured_peak_freq_'pk'
            if vzF > vizSpecLo and vzF < vizSpecHi
                @specAt: vzF
                Paint circle (mm): vzGrey$, log10(vzF), specAt.result, 0.9
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
        Text: log10(target_f0), "left", vzAy1 + 3, "bottom", " root"
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
    Text top: "no", "##A   Target spectrum \-- general measured peaks and assigned notes##"

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
    if voicing_strategy = 4
        Text: 0.01, "left", 0.61, "half", "##Score:## " + fixed$(best_score, 3) + " = acoustic " + fixed$(best_raw_score, 3) + " + size penalty " + fixed$(best_score - best_raw_score, 3) + "     ##Errors:## band " + fixed$(best_error_band, 3) + "   coverage " + fixed$(best_error_coverage, 3) + "   assignment " + fixed$(best_error_assignment, 3) + "   register " + fixed$(best_error_register, 3) + "   duplicates " + fixed$(best_error_duplicate, 3)
    else
        Text: 0.01, "left", 0.61, "half", "##Score:## " + fixed$(best_score, 3) + " = acoustic " + fixed$(best_raw_score, 3) + " + size penalty " + fixed$(best_score - best_raw_score, 3) + "     ##Errors:## band " + fixed$(best_error_band, 3) + " (x0.45)   centroid " + fixed$(best_error_cent, 3) + " (x0.30)   spread " + fixed$(best_error_spr, 3) + " (x0.20)   odd/even " + fixed$(best_error_oe, 3) + " (x0.05)"
    endif
    Text: 0.01, "left", 0.39, "half", "##Target:## root " + fixed$(target_f0, 1) + " Hz (confidence " + fixed$(target_root_confidence, 2) + ")   centroid " + fixed$(target_centroid, 0) + " Hz vs model " + fixed$(best_mix_centroid, 0) + "   spread " + fixed$(target_spread, 0) + " vs " + fixed$(best_mix_spread, 0) + " Hz   " + string$(n_channels) + " ch power-summed"
    Text: 0.01, "left", 0.16, "half", "##Note:## panel C uses a Gaussian instrument-timbre model (stored centroid/spread, " + target_dynamic$ + "), not measured samples. Spectral pitch assignment uses measured peak energy + preferred register; timbral centroid never acts as a pitch target."
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