# ============================================================
# Praat AudioTools - Flute_KlattGrid.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3.1 runtime fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Flute-LIKE KlattGrid synthesis with a twelve-tone pitch row and
#   interval-derived rhythmic palette.
#
#   This is not a physical waveguide model of a flute. KlattGrid is a
#   source/filter synthesizer; here its phonation/noise controls and a
#   pitch-tracking five-resonance cascade are deliberately repurposed
#   to create a flute-like family of timbres.
#
# SERIAL PITCH:
#   - A fixed 12-pitch-class seed row is transposed to the pitch class
#     of Seed_frequency_Hz.
#   - Prime, inversion, retrograde and retrograde-inversion are computed
#     relative to that transposition anchor.
#   - The 12 pitch classes remain unique.
#
# SERIAL RHYTHM:
#   - A 5-value palette spans Min_IOI..Max_IOI.
#   - The directed pitch-class interval to the next row member selects
#     one of the 5 rhythmic values.
#   - For notes 1..11, that rhythmic value is the TRUE onset-to-onset IOI.
#   - Note 12 uses its cyclicly-derived value as the final phrase duration.
#   - Legato overlap is added to sounding note duration; it no longer
#     shortens the audible onset interval.
#
# KLATTGRID TONE:
#   - Pitch + vibrato in the KlattGrid pitch tier.
#   - Voicing, aspiration and breathiness amplitude tiers.
#   - Five pitch-tracking oral resonances:
#       1.0*f0, 2.0*f0, 3.5*f0, 5.5*f0, 8.0*f0
#   - First-note chiff layers:
#       A broadband turbulence
#       B short sub-tone pitch sweep
#       C high-frequency frication edge
#
# v2.3 reviewed:
#   - Corrected the rhythm semantics: displayed IOI now equals actual
#     onset-to-onset interval despite the legato crossfade.
#   - Short-note-safe attack/release/chiff timing. No KlattGrid control
#     point can be pushed to negative time by the old fixed 250-ms release.
#   - Amplitude vibrato is now an additive dB deviation rather than
#     multiplying the absolute dB value.
#   - Replaced the four-Sound "Combine to stereo -> Convert to mono" chiff
#     summation hack with direct mono sample-index summation.
#   - Added reproducible Random_seed for all stochastic breath/chiff synthesis.
#   - Added validation for rhythm, octave, open phase, vibrato and levels.
#   - Added practical single-note Nyquist guard for the 8*f0 resonance.
#   - Renamed P0/I0/R0/RI0 labels to Prime/Inversion/Retrograde forms
#     relative to the selected seed; "P0" was inaccurate after transposition.
#   - Renamed instrument-claim presets to mechanism-faithful flute-like
#     timbral/tessitura descriptions. "Sul Ponticello" was removed because
#     it is a bowed-string technique, not a flute technique.
#   - Compact laptop-safe main form plus optional Voice/Chiff detail page.
#   - Final peak normalization is optional and is applied only once to the
#     complete phrase; note-level scaling is used only as an intentional
#     per-note calibration step before overlap.
#   - Visualization rebuilt around the actual mechanism:
#       A serial pitch/rhythm timeline
#       B actual pitch-tracking resonance trajectories
#       C measured spectrogram + F0 guides
#       D measured output waveform
#       row/rhythm/source-filter/output QC
# ============================================================

form Flute-like KlattGrid Serial Melody v2.3.1
    optionmenu Preset 1
        option Custom (baseline values)
        option Balanced Flute-like
        option Soft Historical Tone
        option Bright Folk Tone
        option Breathy Low Tone
        option High Bright Tone
        option Mellow Low Tone
        option Glassy Air Tone

    boolean Melody_mode 1
    positive Seed_frequency_Hz 523.25
    integer Base_octave 5
    optionmenu Row_form 1
        option Prime
        option Inversion
        option Retrograde
        option Retrograde-Inversion

    positive Min_IOI_s 0.20
    positive Max_IOI_s 0.80
    positive Duration_scale 1.0

    boolean Edit_voice_and_chiff 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
open_phase = 0.90
vibrato_rate_Hz = 5.3
vibrato_depth_st = 0.25
amplitude_vibrato_depth_dB = 1.2
amp_voice_dB = 90
amp_asp_sustain_dB = 54
amp_asp_peak_dB = 58
amp_breath_dB = 50

chiff_A_amp = 0.06
chiff_B_amp = 0.04
chiff_C_amp = 0.02
random_seed = 0

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    seed_frequency_Hz = 523.25
    base_octave = 5
    min_IOI_s = 0.20
    max_IOI_s = 0.80
    duration_scale = 1.0
    open_phase = 0.90
    vibrato_rate_Hz = 5.3
    vibrato_depth_st = 0.25
    amplitude_vibrato_depth_dB = 1.2
    amp_voice_dB = 90
    amp_asp_sustain_dB = 54
    amp_asp_peak_dB = 58
    amp_breath_dB = 50
    chiff_A_amp = 0.06
    chiff_B_amp = 0.04
    chiff_C_amp = 0.02
    preset_name$ = "Balanced Flute-like"

elsif preset = 3
    seed_frequency_Hz = 440.0
    base_octave = 4
    min_IOI_s = 0.22
    max_IOI_s = 0.75
    duration_scale = 1.0
    open_phase = 0.85
    vibrato_rate_Hz = 5.0
    vibrato_depth_st = 0.14
    amplitude_vibrato_depth_dB = 0.7
    amp_voice_dB = 88
    amp_asp_sustain_dB = 49
    amp_asp_peak_dB = 54
    amp_breath_dB = 46
    chiff_A_amp = 0.035
    chiff_B_amp = 0.055
    chiff_C_amp = 0.010
    preset_name$ = "Soft Historical Tone"

elsif preset = 4
    seed_frequency_Hz = 587.33
    base_octave = 5
    min_IOI_s = 0.15
    max_IOI_s = 0.50
    duration_scale = 1.0
    open_phase = 0.92
    vibrato_rate_Hz = 6.5
    vibrato_depth_st = 0.38
    amplitude_vibrato_depth_dB = 1.6
    amp_voice_dB = 92
    amp_asp_sustain_dB = 56
    amp_asp_peak_dB = 61
    amp_breath_dB = 49
    chiff_A_amp = 0.095
    chiff_B_amp = 0.045
    chiff_C_amp = 0.030
    preset_name$ = "Bright Folk Tone"

elsif preset = 5
    seed_frequency_Hz = 392.0
    base_octave = 4
    min_IOI_s = 0.30
    max_IOI_s = 1.20
    duration_scale = 1.0
    open_phase = 0.95
    vibrato_rate_Hz = 4.5
    vibrato_depth_st = 0.20
    amplitude_vibrato_depth_dB = 0.9
    amp_voice_dB = 82
    amp_asp_sustain_dB = 62
    amp_asp_peak_dB = 66
    amp_breath_dB = 58
    chiff_A_amp = 0.025
    chiff_B_amp = 0.018
    chiff_C_amp = 0.045
    preset_name$ = "Breathy Low Tone"

elsif preset = 6
    seed_frequency_Hz = 1046.50
    base_octave = 6
    min_IOI_s = 0.10
    max_IOI_s = 0.40
    duration_scale = 1.0
    open_phase = 0.88
    vibrato_rate_Hz = 7.2
    vibrato_depth_st = 0.30
    amplitude_vibrato_depth_dB = 1.0
    amp_voice_dB = 94
    amp_asp_sustain_dB = 48
    amp_asp_peak_dB = 56
    amp_breath_dB = 43
    chiff_A_amp = 0.075
    chiff_B_amp = 0.060
    chiff_C_amp = 0.040
    preset_name$ = "High Bright Tone"

elsif preset = 7
    seed_frequency_Hz = 261.63
    base_octave = 4
    min_IOI_s = 0.35
    max_IOI_s = 1.40
    duration_scale = 1.0
    open_phase = 0.96
    vibrato_rate_Hz = 4.0
    vibrato_depth_st = 0.15
    amplitude_vibrato_depth_dB = 0.7
    amp_voice_dB = 85
    amp_asp_sustain_dB = 58
    amp_asp_peak_dB = 61
    amp_breath_dB = 54
    chiff_A_amp = 0.018
    chiff_B_amp = 0.018
    chiff_C_amp = 0.010
    preset_name$ = "Mellow Low Tone"

elsif preset = 8
    seed_frequency_Hz = 523.25
    base_octave = 5
    min_IOI_s = 0.25
    max_IOI_s = 1.00
    duration_scale = 1.0
    open_phase = 0.98
    vibrato_rate_Hz = 3.0
    vibrato_depth_st = 0.08
    amplitude_vibrato_depth_dB = 0.4
    amp_voice_dB = 79
    amp_asp_sustain_dB = 65
    amp_asp_peak_dB = 68
    amp_breath_dB = 61
    chiff_A_amp = 0.010
    chiff_B_amp = 0.010
    chiff_C_amp = 0.055
    preset_name$ = "Glassy Air Tone"
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_voice_and_chiff
    beginPause: "Flute-like KlattGrid - Voice & Chiff"
        real: "Open phase (0..1)", open_phase
        positive: "Vibrato rate (Hz)", vibrato_rate_Hz
        real: "Vibrato depth (semitones)", vibrato_depth_st
        real: "Amplitude vibrato depth (dB)", amplitude_vibrato_depth_dB
        real: "Voicing level (dB)", amp_voice_dB
        real: "Aspiration sustain (dB)", amp_asp_sustain_dB
        real: "Aspiration attack peak (dB)", amp_asp_peak_dB
        real: "Breathiness level (dB)", amp_breath_dB
        real: "Chiff A peak", chiff_A_amp
        real: "Chiff B peak", chiff_B_amp
        real: "Chiff C peak", chiff_C_amp
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# VALIDATION / CONSTANTS
# ---------------------------------------------------------------------------
if seed_frequency_Hz <= 0
    exitScript: "Seed/single-note frequency must be greater than zero."
endif
if base_octave < 3 or base_octave > 7
    exitScript: "Base octave must be an integer from 3 through 7."
endif
if min_IOI_s <= 0 or max_IOI_s <= 0
    exitScript: "Min and Max IOI must be greater than zero."
endif
if max_IOI_s < min_IOI_s
    exitScript: "Max IOI must be greater than or equal to Min IOI."
endif
if duration_scale <= 0
    exitScript: "Duration scale must be greater than zero."
endif
if open_phase <= 0 or open_phase >= 1
    exitScript: "Open phase must be greater than 0 and smaller than 1."
endif
if vibrato_rate_Hz <= 0 or vibrato_rate_Hz > 20
    exitScript: "Vibrato rate must be > 0 and <= 20 Hz."
endif
if vibrato_depth_st < 0 or vibrato_depth_st > 2
    exitScript: "Vibrato depth must be between 0 and 2 semitones."
endif
if amplitude_vibrato_depth_dB < 0 or amplitude_vibrato_depth_dB > 12
    exitScript: "Amplitude vibrato depth must be between 0 and 12 dB."
endif
if amp_voice_dB < 0 or amp_voice_dB > 120
    exitScript: "Voicing level must be between 0 and 120 dB."
endif
if amp_asp_sustain_dB < 0 or amp_asp_sustain_dB > 120 or
    ... amp_asp_peak_dB < 0 or amp_asp_peak_dB > 120 or
    ... amp_breath_dB < 0 or amp_breath_dB > 120
    exitScript: "Aspiration/breathiness levels must be between 0 and 120 dB."
endif
if chiff_A_amp < 0 or chiff_A_amp > 1 or
    ... chiff_B_amp < 0 or chiff_B_amp > 1 or
    ... chiff_C_amp < 0 or chiff_C_amp > 1
    exitScript: "Chiff peak amplitudes must be between 0 and 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

sr = 44100
twoPi = 2*pi
safeTop = 0.45*sr
pwr1 = 2
pwr2 = 10

# Timing references; note-specific values are clipped safely in makeFluteNote.
stabilise_s = 0.08
release_reference_s = 0.25
single_note_dur = 2.5

# Crossfade is at most 50 ms and never more than 20 percent of minimum IOI.
xfade_s = min(0.05, 0.20*min_IOI_s*duration_scale)

# A high custom single-note F0 would put the 8*f0 resonance beyond
# practical audio bandwidth. Melody-mode notes are octave-bounded below.
if melody_mode = 0 and 8*seed_frequency_Hz > safeTop
    exitScript: "Single-note frequency is too high for the 8*f0 resonance at 44.1 kHz. Use <= ",
        ... fixed$(safeTop/8,1), " Hz."
endif

seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# ============================================================
# 1. TWELVE-TONE ROW
# ============================================================
base_pc# = {0,11,3,4,8,7,9,6,1,5,2,10}

root_midi = round(69 + 12*log2(seed_frequency_Hz/440))
root_pc = root_midi mod 12
base_octave_midi = (base_octave+1)*12

row_pc# = zero#(12)
final_pc# = zero#(12)
inverse_pc# = zero#(12)
midi_notes# = zero#(12)
note_hz# = zero#(12)
ioi# = zero#(12)
note_onset# = zero#(12)
note_synth_dur# = zero#(12)

for i from 1 to 12
    row_pc#[i] = (base_pc#[i]+root_pc) mod 12
endfor

if row_form = 1
    for i from 1 to 12
        final_pc#[i] = row_pc#[i]
    endfor

elsif row_form = 2
    for i from 1 to 12
        final_pc#[i] = (root_pc-(row_pc#[i]-root_pc)+120) mod 12
    endfor

elsif row_form = 3
    for i from 1 to 12
        final_pc#[i] = row_pc#[13-i]
    endfor

else
    for i from 1 to 12
        inverse_pc#[i] = (root_pc-(row_pc#[i]-root_pc)+120) mod 12
    endfor
    for i from 1 to 12
        final_pc#[i] = inverse_pc#[13-i]
    endfor
endif

# Place each pitch class in the nearest octave to the previous note.
# Bound the resulting flute-like tessitura to C3..C7.
midi_notes#[1] = base_octave_midi+final_pc#[1]
while midi_notes#[1] < 48
    midi_notes#[1] = midi_notes#[1]+12
endwhile
while midi_notes#[1] > 96
    midi_notes#[1] = midi_notes#[1]-12
endwhile

for i from 2 to 12
    prev = midi_notes#[i-1]
    this_pc = final_pc#[i]
    cand = floor(prev/12)*12+this_pc

    if abs(cand-prev) > 6
        if cand < prev
            cand = cand+12
        else
            cand = cand-12
        endif
    endif

    while cand < 48
        cand = cand+12
    endwhile
    while cand > 96
        cand = cand-12
    endwhile
    midi_notes#[i] = cand
endfor

maxNoteHz = 0
minNoteHz = 1e9
for i from 1 to 12
    note_hz#[i] = 440*(2^((midi_notes#[i]-69)/12))
    maxNoteHz = max(maxNoteHz,note_hz#[i])
    minNoteHz = min(minNoteHz,note_hz#[i])
endfor

if 8*maxNoteHz > safeTop
    exitScript: "Generated melody tessitura exceeds practical 8*f0 resonance bandwidth."
endif

# Validate 12 unique pitch classes.
seen# = zero#(12)
uniquePC = 0
for i from 1 to 12
    idx = final_pc#[i]+1
    if seen#[idx] = 0
        seen#[idx] = 1
        uniquePC = uniquePC+1
    endif
endfor
if uniquePC <> 12
    exitScript: "Internal row error: pitch-class row is not unique."
endif

# ============================================================
# 2. SERIAL RHYTHM
# ============================================================
rhythm_palette# = zero#(5)
palette_step = (max_IOI_s-min_IOI_s)/4

for i from 1 to 5
    rhythm_palette#[i] = min_IOI_s+(i-1)*palette_step
endfor

for i from 1 to 12
    if i < 12
        intv = (final_pc#[i+1]-final_pc#[i]+12) mod 12
    else
        intv = (final_pc#[1]-final_pc#[12]+12) mod 12
    endif

    pal_idx = floor(intv*5/12)+1
    pal_idx = max(1,min(5,pal_idx))
    ioi#[i] = rhythm_palette#[pal_idx]*duration_scale
endfor

# True onset times. Notes 1..11 receive xfade extra sounding time;
# note 12 ends the phrase with its own cyclicly-derived rhythmic value.
note_onset#[1] = 0
for i from 2 to 12
    note_onset#[i] = note_onset#[i-1]+ioi#[i-1]
endfor

for i from 1 to 11
    note_synth_dur#[i] = ioi#[i]+xfade_s
endfor
note_synth_dur#[12] = ioi#[12]
totalPhraseDuration = note_onset#[12]+ioi#[12]

# ============================================================
# MIDI -> NOTE NAME
# ============================================================
note_names$ = "C C# D D# E F F# G G# A A# B"

procedure midiName: .midi
    .pc = .midi mod 12
    .oct = floor(.midi/12)-1
    .pc_pos = .pc*3+1
    .n$ = mid$(note_names$,.pc_pos,2)
    if right$(.n$,1) = " "
        .n$ = left$(.n$,1)
    endif
    .result$ = .n$+string$(.oct)
endproc

# ============================================================
# 3. INFO
# ============================================================
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  FLUTE-LIKE KLATTGRID SERIAL MELODY v2.3.1"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$

if row_form = 1
    row_form$ = "Prime"
elsif row_form = 2
    row_form$ = "Inversion"
elsif row_form = 3
    row_form$ = "Retrograde"
else
    row_form$ = "Retrograde-Inversion"
endif

@midiName: root_midi
root_name$ = midiName.result$

appendInfoLine: "Row form: ", row_form$, " relative to seed pitch class"
appendInfoLine: "Seed: ", root_name$, " | Base octave: ", base_octave
appendInfoLine: "Unique pitch classes: ", uniquePC, "/12"
appendInfoLine: "Melody F0 range: ", fixed$(minNoteHz,1), "-", fixed$(maxNoteHz,1), " Hz"
appendInfoLine: "Legato crossfade: ", fixed$(1000*xfade_s,1), " ms"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

appendInfoLine: "Rhythm palette (s): ",
    ... fixed$(rhythm_palette#[1]*duration_scale,3), "  ",
    ... fixed$(rhythm_palette#[2]*duration_scale,3), "  ",
    ... fixed$(rhythm_palette#[3]*duration_scale,3), "  ",
    ... fixed$(rhythm_palette#[4]*duration_scale,3), "  ",
    ... fixed$(rhythm_palette#[5]*duration_scale,3)
appendInfoLine: ""
appendInfoLine: "Pitch row / true onset intervals:"

for i from 1 to 12
    @midiName: midi_notes#[i]
    note_label$ = midiName.result$
    if i < 12
        appendInfoLine: "  ", i, ": ", note_label$,
            ... " | onset ", fixed$(note_onset#[i],3),
            ... " s | IOI ", fixed$(ioi#[i],3), " s"
    else
        appendInfoLine: "  ", i, ": ", note_label$,
            ... " | onset ", fixed$(note_onset#[i],3),
            ... " s | final duration ", fixed$(ioi#[i],3), " s"
    endif
endfor
appendInfoLine: ""

# ============================================================
# 4. SYNTHESIS
# ============================================================
if melody_mode
    appendInfoLine: "Generating twelve-tone flute-like phrase..."

    note_id# = zero#(12)

    for i from 1 to 12
        @makeFluteNote: note_hz#[i], note_synth_dur#[i], (i=1)
        note_id#[i] = selected("Sound")
    endfor

    # Apply equal-power-style cosine overlap windows BEFORE shifting time axes.
    xf_str$ = fixed$(xfade_s,9)

    for i from 1 to 12
        selectObject: note_id#[i]
        nd = note_synth_dur#[i]

        if i > 1
            Formula (part): 0, xfade_s, 1, 1,
                ... "self*(0.5-0.5*cos(pi*x/" + xf_str$ + "))"
        endif

        if i < 12
            fadeStart = nd-xfade_s
            fadeStart$ = fixed$(fadeStart,9)
            Formula (part): fadeStart, nd, 1, 1,
                ... "self*(0.5+0.5*cos(pi*(x-" + fadeStart$ + ")/" + xf_str$ + "))"
        endif
    endfor

    # Shift to TRUE serial onset times.
    for i from 1 to 12
        selectObject: note_id#[i]
        Shift times to: "start time", note_onset#[i]
    endfor

    melody = Create Sound from formula: "flute_serial_melody",
        ... 1,0,totalPhraseDuration,sr,"0"

    for i from 1 to 12
        nid = note_id#[i]
        tStart = note_onset#[i]
        tEnd = min(totalPhraseDuration,note_onset#[i]+note_synth_dur#[i])
        nid$ = string$(nid)

        selectObject: melody
        Formula (part): tStart,tEnd,1,1,
            ... "self+object(" + nid$ + ",x)"

        removeObject: nid
    endfor

    sound = melody

else
    appendInfoLine: "Generating single flute-like note..."
    @makeFluteNote: seed_frequency_Hz, single_note_dur, 1
    sound = selected("Sound")
    @midiName: root_midi
    Rename: "flute_like_" + midiName.result$
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# Short end protection only; the note/phrase envelopes already define articulation.
selectObject: sound
soundDuration = Get total duration
edgeFade = min(0.008,0.10*soundDuration)
if edgeFade > 0
    fadeOutStart = soundDuration-edgeFade
    Formula: "if x<edgeFade then self*(x/edgeFade) else if x>fadeOutStart then self*((soundDuration-x)/edgeFade) else self fi fi"
endif

# One final/common normalization only when requested.
preNormPeak = Get absolute extremum: 0,0,"None"
preNormRMS = Get root-mean-square: 0,0

if normalize_output and preNormPeak > 0
    Scale peak: 0.92
endif

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalDuration = Get total duration

# ============================================================
# 5. VISUALIZATION
# ============================================================
if draw_visualization
    @drawVisualization
endif

# ============================================================
# 6. PLAY / FINAL INFO
# ============================================================
selectObject: sound
appendInfoLine: ""
appendInfoLine: "Pre-normalization peak/RMS: ",
    ... fixed$(preNormPeak,4), " / ", fixed$(preNormRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Duration: ", fixed$(finalDuration,3), " s"
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: sound


# ===========================================================================
# PROCEDURE: makeFluteNote
# ===========================================================================
procedure makeFluteNote: .freq, .dur, .do_attack

    # Short-note-safe timing. Every derived time is guaranteed to remain
    # inside [0,dur], even for aggressive Custom rhythmic values.
    .stabilise = max(0.001,min(stabilise_s,0.45*.dur))
    .release = max(0.001,min(release_reference_s,0.28*.dur))
    .releaseStart = max(.stabilise,.dur-.release)

    .attack1 = min(0.008,0.15*.stabilise)
    .attack2 = min(0.025,0.45*.stabilise)
    .attack3 = min(0.060,0.78*.stabilise)

    .chiff_A_dur = max(0.001,min(0.020,0.22*.dur))
    .chiff_B_dur = max(0.001,min(0.060,0.40*.dur))
    .chiff_C_dur = max(0.001,min(0.015,0.16*.dur))

    # Pitch-tracking resonance ladder.
    .f1_hz = .freq
    .f1_bw = .freq*0.25
    .f2_hz = .freq*2.0
    .f2_bw = .freq*0.35
    .f3_hz = .freq*3.5
    .f3_bw = 350
    .f4_hz = .freq*5.5
    .f4_bw = 500
    .f5_hz = .freq*8.0
    .f5_bw = 700

    if .f5_hz > safeTop
        exitScript: "Internal resonance exceeds practical Nyquist headroom at F0=",
            ... fixed$(.freq,2), " Hz."
    endif

    # -----------------------------------------------------------------------
    # MAIN KLATTGRID TONE
    # -----------------------------------------------------------------------
    .kg = Create KlattGrid: "flute_like",0,.dur,5,0,0,0,0,1,0

    selectObject: .kg
    Add open phase point: 0,open_phase
    Add power1 point: 0,pwr1
    Add power2 point: 0,pwr2

    # Pitch attack/sag.
    if .do_attack
        Add pitch point: 0.001,.freq*0.985
        Add pitch point: min(0.030,0.20*.dur),.freq*0.995
        Add pitch point: .stabilise,.freq
    else
        Add pitch point: 0.001,.freq
    endif

    # Vibrato samples. Avoid negative/empty windows on short notes.
    .vib_period = 1/vibrato_rate_Hz
    if .do_attack
        .vib_start = .stabilise
    else
        .vib_start = min(0.04,0.18*.dur)
    endif
    .vib_end = max(.vib_start,.dur-min(0.01,0.05*.dur))

    if .vib_end > .vib_start
        .n_vib = ceiling((.vib_end-.vib_start)/(.vib_period/8))
    else
        .n_vib = 0
    endif

    for .i from 1 to .n_vib
        .t_v = .vib_start+(.i-1)*(.vib_period/8)
        if .t_v <= .vib_end
            .ph = twoPi*vibrato_rate_Hz*(.t_v-.vib_start)
            Add pitch point: .t_v,
                ... .freq*(2^(vibrato_depth_st*sin(.ph)/12))
        endif
    endfor
    Add pitch point: max(0.001,.dur-0.001),.freq

    # Voicing amplitude.
    if .do_attack
        Add voicing amplitude point: 0,0
        Add voicing amplitude point: .attack1,amp_voice_dB-30
        Add voicing amplitude point: .attack2,amp_voice_dB-12
        Add voicing amplitude point: .attack3,amp_voice_dB-3
        Add voicing amplitude point: .stabilise,amp_voice_dB
        Add voicing amplitude point: .releaseStart,amp_voice_dB
        Add voicing amplitude point: .dur,0
    else
        Add voicing amplitude point: 0,amp_voice_dB
        Add voicing amplitude point: .dur,amp_voice_dB
    endif

    # Correct dB-domain amplitude vibrato: additive +/- dB.
    for .i from 1 to .n_vib
        .t_v = .vib_start+(.i-1)*(.vib_period/8)
        if .t_v <= .vib_end
            .ph = twoPi*vibrato_rate_Hz*(.t_v-.vib_start)
            .av_mod = amp_voice_dB+
                ... amplitude_vibrato_depth_dB*sin(.ph)
            Add voicing amplitude point: .t_v,.av_mod
        endif
    endfor

    # Aspiration.
    if .do_attack
        .aspPeakT = min(0.015,0.10*.dur)
        .aspSettleT = min(0.060,0.34*.dur)

        Add aspiration amplitude point: 0,0
        Add aspiration amplitude point: .aspPeakT,amp_asp_peak_dB
        Add aspiration amplitude point: .aspSettleT,amp_asp_sustain_dB+2
        Add aspiration amplitude point: .stabilise,amp_asp_sustain_dB
        Add aspiration amplitude point: .releaseStart,amp_asp_sustain_dB
        Add aspiration amplitude point: .dur,0
    else
        Add aspiration amplitude point: 0,amp_asp_sustain_dB
        Add aspiration amplitude point: .dur,amp_asp_sustain_dB
    endif

    # Breathiness.
    if .do_attack
        .breathT = min(0.020,0.14*.dur)
        Add breathiness amplitude point: 0,0
        Add breathiness amplitude point: .breathT,amp_breath_dB
        Add breathiness amplitude point: .stabilise,max(0,amp_breath_dB-5)
        Add breathiness amplitude point: .releaseStart,max(0,amp_breath_dB-5)
        Add breathiness amplitude point: .dur,0
    else
        Add breathiness amplitude point: 0,max(0,amp_breath_dB-5)
        Add breathiness amplitude point: .dur,max(0,amp_breath_dB-5)
    endif

    # Mild flutter.
    Add flutter point: 0,0.02
    Add flutter point: .dur,0.02

    # Oral resonances.
    Add oral formant frequency point: 1,0,.f1_hz
    Add oral formant bandwidth point: 1,0,.f1_bw
    Add oral formant frequency point: 2,0,.f2_hz
    Add oral formant bandwidth point: 2,0,.f2_bw
    Add oral formant frequency point: 3,0,.f3_hz
    Add oral formant bandwidth point: 3,0,.f3_bw
    Add oral formant frequency point: 4,0,.f4_hz
    Add oral formant bandwidth point: 4,0,.f4_bw
    Add oral formant frequency point: 5,0,.f5_hz
    Add oral formant bandwidth point: 5,0,.f5_bw

    selectObject: .kg
    .flute_raw = To Sound

    # Keep the musically relevant band but leave substantially more high
    # frequency headroom than the old fixed 7-kHz ceiling.
    .mainHi = min(safeTop,max(8000,1.12*.f5_hz))
    selectObject: .flute_raw
    .main_tone = Filter (pass Hann band): 40,.mainHi,180

    if .do_attack
        # -------------------------------------------------------------------
        # CHIFF A: broadband turbulence
        # -------------------------------------------------------------------
        .chA_dur$ = fixed$(.chiff_A_dur,9)
        .chiff_A_noise = Create Sound from formula: "chiffA",
            ... 1,0,.dur,sr,
            ... "if x<" + .chA_dur$ + " then randomGauss(0,1) else 0 fi"

        .chAlo = max(40,.freq*0.70)
        .chAhi = min(safeTop,max(.chAlo+100,.freq*4.0))
        selectObject: .chiff_A_noise
        .chiff_A_filt = Filter (pass Hann band): .chAlo,.chAhi,200

        selectObject: .chiff_A_filt
        Formula: "self*exp(-6*x/" + .chA_dur$ +
            ... ")*if x<" + .chA_dur$ + " then 1 else 0 fi"
        .aPeak = Get absolute extremum: 0,0,"None"
        if .aPeak > 0 and chiff_A_amp > 0
            Scale peak: chiff_A_amp
        endif
        removeObject: .chiff_A_noise

        # -------------------------------------------------------------------
        # CHIFF B: sub-tone pitch sweep
        # -------------------------------------------------------------------
        .kg_b = Create KlattGrid: "chiffB",0,.dur,2,0,0,0,0,1,0
        selectObject: .kg_b
        Add open phase point: 0,min(0.98,max(0.55,open_phase+0.03))
        Add power1 point: 0,2
        Add power2 point: 0,12
        Add pitch point: 0.001,.freq*0.60
        Add pitch point: .chiff_B_dur,.freq
        Add pitch point: .dur,.freq

        Add voicing amplitude point: 0,0
        Add voicing amplitude point: .chiff_B_dur*0.15,75
        Add voicing amplitude point: .chiff_B_dur*0.60,80
        Add voicing amplitude point: .chiff_B_dur,0
        Add voicing amplitude point: .dur,0

        Add oral formant frequency point: 1,0,.freq*0.60
        Add oral formant frequency point: 1,.chiff_B_dur,.freq
        Add oral formant bandwidth point: 1,0,.freq*0.50
        Add oral formant frequency point: 2,0,.freq*1.50
        Add oral formant bandwidth point: 2,0,.freq*0.60

        .chiff_B_raw = To Sound
        .chBhi = min(safeTop,max(500,.freq*5))
        selectObject: .chiff_B_raw
        .chiff_B = Filter (pass Hann band): 40,.chBhi,150
        .bPeak = Get absolute extremum: 0,0,"None"
        if .bPeak > 0 and chiff_B_amp > 0
            Scale peak: chiff_B_amp
        endif
        removeObject: .kg_b,.chiff_B_raw

        # -------------------------------------------------------------------
        # CHIFF C: high-frequency frication
        # -------------------------------------------------------------------
        .chC_dur$ = fixed$(.chiff_C_dur,9)
        .chiff_C_noise = Create Sound from formula: "chiffC",
            ... 1,0,.dur,sr,
            ... "if x<" + .chC_dur$ + " then randomGauss(0,1) else 0 fi"

        .chClo = min(2000,0.25*safeTop)
        .chChi = min(safeTop,9000)
        selectObject: .chiff_C_noise
        .chiff_C_filt = Filter (pass Hann band): .chClo,.chChi,300

        selectObject: .chiff_C_filt
        Formula: "self*exp(-9*x/" + .chC_dur$ +
            ... ")*if x<" + .chC_dur$ + " then 1 else 0 fi"
        .cPeak = Get absolute extremum: 0,0,"None"
        if .cPeak > 0 and chiff_C_amp > 0
            Scale peak: chiff_C_amp
        endif
        removeObject: .chiff_C_noise

        # Direct mono summation; no multi-object channel trick.
        selectObject: .main_tone
        Copy: "fluteNote"
        .mix = selected("Sound")

        .aID$ = string$(.chiff_A_filt)
        .bID$ = string$(.chiff_B)
        .cID$ = string$(.chiff_C_filt)

        Formula: "self+object[" + .aID$ + ",1,col]+object[" +
            ... .bID$ + ",1,col]+object[" + .cID$ + ",1,col]"

        removeObject: .kg,.flute_raw,.main_tone
        removeObject: .chiff_A_filt,.chiff_B,.chiff_C_filt

    else
        selectObject: .main_tone
        Copy: "fluteNote"
        .mix = selected("Sound")
        removeObject: .kg,.flute_raw,.main_tone
    endif

    # Intentional per-note calibration before overlap.
    selectObject: .mix
    .notePeak = Get absolute extremum: 0,0,"None"
    if .notePeak > 0
        Scale peak: 0.72
    endif

    selectObject: .mix
endproc


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    selectObject: sound
    .totalDur = Get total duration

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    if melody_mode
        Text: 0.5,"centre",0.55,"half",
            ... "FLUTE-LIKE KLATTGRID SERIAL MELODY | " + preset_name$
    else
        Text: 0.5,"centre",0.55,"half",
            ... "FLUTE-LIKE KLATTGRID SINGLE NOTE | " + preset_name$
    endif

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    if melody_mode
        Text: 0.5,"centre",0.68,"half",
            ... row_form$ + " | 12 unique pitch classes | true IOI palette "
            ... + fixed$(min_IOI_s*duration_scale,2) + "-"
            ... + fixed$(max_IOI_s*duration_scale,2) + " s"
    else
        Text: 0.5,"centre",0.68,"half",
            ... "F0 " + fixed$(seed_frequency_Hz,1) + " Hz | single-note duration "
            ... + fixed$(single_note_dur,2) + " s"
    endif

    Text: 0.5,"centre",0.20,"half",
        ... "KlattGrid source/noise -> pitch-tracking 5-resonance cascade -> first-note chiff -> phrase mix"

    # -----------------------------------------------------------------------
    # PANEL A: SERIAL PITCH / RHYTHM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  PITCH + RHYTHM | actual onset timing; bar width = serial rhythmic cell"

    if melody_mode
        .logFLo = ln(max(40,0.90*minNoteHz))
        .logFHi = ln(min(safeTop,1.10*maxNoteHz))
    else
        .logFLo = ln(max(40,0.85*seed_frequency_Hz))
        .logFHi = ln(min(safeTop,1.15*seed_frequency_Hz))
    endif
    if .logFHi <= .logFLo
        .logFHi = .logFLo+0.5
    endif

    Select inner viewport: .left,.right,1.05,1.99
    Axes: 0,.totalDur,.logFLo,.logFHi
    Paint rectangle: .bg$,0,.totalDur,.logFLo,.logFHi

    if melody_mode
        for .i from 1 to 12
            .x0 = note_onset#[.i]
            .x1 = min(.totalDur,.x0+ioi#[.i])
            .yf = ln(note_hz#[.i])

            if (.i mod 3)=1
                Colour: .blue$
            elsif (.i mod 3)=2
                Colour: .orange$
            else
                Colour: .green$
            endif

            Line width: 2
            Draw line: .x0,.yf,.x1,.yf
            Line width: 1

            @midiName: midi_notes#[.i]
            Colour: "{0.25,0.25,0.27}"
            Font size: 4
            Text: .x0+0.5*(.x1-.x0),"centre",.yf,"bottom",
                ... midiName.result$
        endfor
    else
        Colour: .blue$
        Line width: 2
        Draw line: 0,ln(seed_frequency_Hz),.totalDur,ln(seed_frequency_Hz)
        Line width: 1
    endif

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","log F0"

    # -----------------------------------------------------------------------
    # PANEL B: PITCH-TRACKING RESONANCE MODEL
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.15,2.37
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  SOURCE-FILTER MODEL | actual resonance targets: 1x, 2x, 3.5x, 5.5x, 8x F0"

    if melody_mode
        .maxModelF = min(safeTop,8*maxNoteHz)
        .minModelF = max(40,minNoteHz)
    else
        .maxModelF = min(safeTop,8*seed_frequency_Hz)
        .minModelF = max(40,seed_frequency_Hz)
    endif

    .logMLo = ln(.minModelF)
    .logMHi = ln(.maxModelF)

    Select inner viewport: .left,.right,2.44,3.44
    Axes: 0,.totalDur,.logMLo,.logMHi
    Paint rectangle: .bg$,0,.totalDur,.logMLo,.logMHi

    .mult# = {1,2,3.5,5.5,8}
    for .k to 5
        if .k=1
            Colour: .blue$
        elsif .k=2
            Colour: .green$
        elsif .k=3
            Colour: .orange$
        else
            Colour: "{0.48,0.48,0.52}"
        endif

        if melody_mode
            for .i from 1 to 12
                .x0 = note_onset#[.i]
                .x1 = min(.totalDur,.x0+note_synth_dur#[.i])
                .rf = note_hz#[.i]*.mult#[.k]
                if .rf <= .maxModelF
                    Draw line: .x0,ln(.rf),.x1,ln(.rf)
                endif
            endfor
        else
            .rf = seed_frequency_Hz*.mult#[.k]
            if .rf <= .maxModelF
                Draw line: 0,ln(.rf),.totalDur,ln(.rf)
            endif
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","log frequency"

    # -----------------------------------------------------------------------
    # PANEL C: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.60,3.82
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + actual F0 guides"

    .specMax = min(safeTop,max(6000,.maxModelF))
    .specStep = max(0.002,.totalDur/1200)

    selectObject: sound
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,3.89,5.03
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,.totalDur,0,.specMax
    Colour: .blue$
    Line width: 1.1

    if melody_mode
        for .i from 1 to 12
            Draw line: note_onset#[.i],note_hz#[.i],
                ... min(.totalDur,note_onset#[.i]+note_synth_dur#[.i]),
                ... note_hz#[.i]
        endfor
    else
        Draw line: 0,seed_frequency_Hz,.totalDur,seed_frequency_Hz
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.19,5.41
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MEASURED OUTPUT | waveform after overlap and final level stage"

    selectObject: sound
    .wavePeak = Get absolute extremum: 0,0,"None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05*.wavePeak

    Select inner viewport: .left,.right,5.48,6.23
    Axes: 0,.totalDur,-.waveY,.waveY
    Paint rectangle: .bg$,0,.totalDur,-.waveY,.waveY
    selectObject: sound
    Colour: .orange$
    Draw: 0,0,-.waveY,.waveY,"no","Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Amplitude"
    Text bottom: "yes","Time (s)"

    # -----------------------------------------------------------------------
    # QC / PROCESS SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.48,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.81,"half",
        ... "MODEL  |  KlattGrid phonation+noise -> oral resonances at 1/2/3.5/5.5/8 x F0 -> chiff"

    if melody_mode
        Text: 0.02,"left",0.60,"half",
            ... "SERIAL  |  " + row_form$ + "  |  unique PCs " + string$(uniquePC)
            ... + "/12  |  phrase " + fixed$(totalPhraseDuration,2) + " s"
            ... + "  |  overlap " + fixed$(1000*xfade_s,0) + " ms"
    else
        Text: 0.02,"left",0.60,"half",
            ... "NOTE  |  F0 " + fixed$(seed_frequency_Hz,1) + " Hz"
            ... + "  |  duration " + fixed$(single_note_dur,2) + " s"
    endif

    Text: 0.02,"left",0.39,"half",
        ... "VOICE  |  vibrato " + fixed$(vibrato_rate_Hz,1) + " Hz / "
        ... + fixed$(vibrato_depth_st,2) + " st"
        ... + "  |  aspiration " + fixed$(amp_asp_sustain_dB,0) + " dB"
        ... + "  |  " + seedLabel$

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.18,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
