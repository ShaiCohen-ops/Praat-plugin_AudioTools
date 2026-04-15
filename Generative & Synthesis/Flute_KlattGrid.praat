# ============================================================
# Praat AudioTools - Flute_KlattGrid.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025) - Audio Analysis Input Pipeline
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
# KlattGrid flute synthesis with dodecaphonic melody
# and serial rhythm derived from the tone row.
# SERIAL TECHNIQUE:
#   - A 12-tone row is generated from a user-chosen seed pitch.
#   - The row contains all 12 chromatic pitch classes exactly once.
#   - A serial rhythm row (also 12 values) is derived from the
#     pitch-class intervals: interval → IOI in seconds.
#   - The melody plays the pitch row once through, each note
#     lasting its serial duration.
#
# CHIFF LAYERS (v4, preserved):
#   A: broadband turbulence burst (~40 ms)
#   B: sub-tone pitch sweep (60%→100% of note over ~130 ms)
#   C: high-frequency frication edge (~30 ms)
#
# ============================================================

form Flute KlattGrid Serial Melody
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use values below)
        option Default Flute
        option Baroque Flute
        option Irish Folk Flute
        option Breathy Alto Flute
        option Piercing Piccolo
        option Mellow Bass Flute
        option Sul Ponticello (Glassy)
    comment === Mode & Pitch ===
    boolean Melody_mode 1
    positive Frequency_Hz 523.25
    positive Base_octave 5
    optionmenu Row_form 1
        option Prime (P0)
        option Inversion (I0)
        option Retrograde (R0)
        option Retrograde-Inversion (RI0)
    comment === Serial Rhythm ===
    positive Min_IOI_s 0.15
    positive Max_IOI_s 1.20
    positive Duration_scale 2.5
    comment === Flute Body ===
    real Open_phase 0.90
    real Vibrato_rate_Hz 5.3
    real Vibrato_depth_st 0.25
    real Amp_voice_dB 90
    real Amp_asp_sustain_dB 54
    comment === Chiff & Output ===
    real Chiff_A_amp 0.06
    real Chiff_B_amp 0.04
    real Chiff_C_amp 0.02
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET APPLICATION
# Overwrite form values when a named preset is selected.
# Preset 1 = Custom → keep all user values as-is.
# ============================================================
#
# Preset parameter table:
#   Preset name          | freq  | oct | minIOI | maxIOI | scale | open | vib_r | vib_d | voice | asp  | chA  | chB  | chC
#   Default Flute        | 523.25|  5  |  0.15  |  1.20  |  2.5  | 0.90 |  5.3  |  0.25 |  90   |  54  | 0.06 | 0.04 | 0.02
#   Baroque Flute        | 440.0 |  4  |  0.20  |  0.90  |  2.0  | 0.85 |  5.8  |  0.18 |  88   |  50  | 0.04 | 0.06 | 0.01
#   Irish Folk Flute     | 587.33|  5  |  0.10  |  0.60  |  1.5  | 0.92 |  6.5  |  0.40 |  92   |  56  | 0.10 | 0.05 | 0.03
#   Breathy Alto Flute   | 392.0 |  4  |  0.25  |  1.50  |  3.0  | 0.95 |  4.5  |  0.20 |  82   |  62  | 0.03 | 0.02 | 0.05
#   Piercing Piccolo     |1046.5 |  6  |  0.08  |  0.50  |  1.2  | 0.88 |  7.2  |  0.30 |  94   |  48  | 0.08 | 0.07 | 0.04
#   Mellow Bass Flute    | 261.63|  4  |  0.30  |  1.80  |  3.5  | 0.96 |  4.0  |  0.15 |  85   |  58  | 0.02 | 0.02 | 0.01
#   Sul Ponticello (Glassy)| 523.25| 5 |  0.18  |  1.00  |  2.0  | 0.98 |  3.0  |  0.08 |  78   |  66  | 0.01 | 0.01 | 0.06

if preset = 2
    # Default Flute — the script's original values
    frequency_Hz       = 523.25
    base_octave        = 5
    min_IOI_s          = 0.15
    max_IOI_s          = 1.20
    duration_scale     = 2.5
    open_phase         = 0.90
    vibrato_rate_Hz    = 5.3
    vibrato_depth_st   = 0.25
    amp_voice_dB       = 90
    amp_asp_sustain_dB = 54
    chiff_A_amp        = 0.06
    chiff_B_amp        = 0.04
    chiff_C_amp        = 0.02
    appendInfoLine: "[Preset] Default Flute loaded."

elsif preset = 3
    # Baroque Flute — lower pitch, gentler vibrato, more chiff B (embouchure colour)
    frequency_Hz       = 440.0
    base_octave        = 4
    min_IOI_s          = 0.20
    max_IOI_s          = 0.90
    duration_scale     = 2.0
    open_phase         = 0.85
    vibrato_rate_Hz    = 5.8
    vibrato_depth_st   = 0.18
    amp_voice_dB       = 88
    amp_asp_sustain_dB = 50
    chiff_A_amp        = 0.04
    chiff_B_amp        = 0.06
    chiff_C_amp        = 0.01
    appendInfoLine: "[Preset] Baroque Flute loaded."

elsif preset = 4
    # Irish Folk Flute — bright, fast articulation, punchy chiff A
    frequency_Hz       = 587.33
    base_octave        = 5
    min_IOI_s          = 0.10
    max_IOI_s          = 0.60
    duration_scale     = 1.5
    open_phase         = 0.92
    vibrato_rate_Hz    = 6.5
    vibrato_depth_st   = 0.40
    amp_voice_dB       = 92
    amp_asp_sustain_dB = 56
    chiff_A_amp        = 0.10
    chiff_B_amp        = 0.05
    chiff_C_amp        = 0.03
    appendInfoLine: "[Preset] Irish Folk Flute loaded."

elsif preset = 5
    # Breathy Alto Flute — lower register, high breathiness, slow and spacious
    frequency_Hz       = 392.0
    base_octave        = 4
    min_IOI_s          = 0.25
    max_IOI_s          = 1.50
    duration_scale     = 3.0
    open_phase         = 0.95
    vibrato_rate_Hz    = 4.5
    vibrato_depth_st   = 0.20
    amp_voice_dB       = 82
    amp_asp_sustain_dB = 62
    chiff_A_amp        = 0.03
    chiff_B_amp        = 0.02
    chiff_C_amp        = 0.05
    appendInfoLine: "[Preset] Breathy Alto Flute loaded."

elsif preset = 6
    # Piercing Piccolo — high register, fast notes, strong edge chiff C
    frequency_Hz       = 1046.5
    base_octave        = 6
    min_IOI_s          = 0.08
    max_IOI_s          = 0.50
    duration_scale     = 1.2
    open_phase         = 0.88
    vibrato_rate_Hz    = 7.2
    vibrato_depth_st   = 0.30
    amp_voice_dB       = 94
    amp_asp_sustain_dB = 48
    chiff_A_amp        = 0.08
    chiff_B_amp        = 0.07
    chiff_C_amp        = 0.04
    appendInfoLine: "[Preset] Piercing Piccolo loaded."

elsif preset = 7
    # Mellow Bass Flute — sub-register, slow and warm, minimal chiff
    frequency_Hz       = 261.63
    base_octave        = 4
    min_IOI_s          = 0.30
    max_IOI_s          = 1.80
    duration_scale     = 3.5
    open_phase         = 0.96
    vibrato_rate_Hz    = 4.0
    vibrato_depth_st   = 0.15
    amp_voice_dB       = 85
    amp_asp_sustain_dB = 58
    chiff_A_amp        = 0.02
    chiff_B_amp        = 0.02
    chiff_C_amp        = 0.01
    appendInfoLine: "[Preset] Mellow Bass Flute loaded."

elsif preset = 8
    # Sul Ponticello (Glassy) — nearly closed embouchure, slow vibrato,
    #   very high breathiness (chiff C dominant), ethereal and hollow
    frequency_Hz       = 523.25
    base_octave        = 5
    min_IOI_s          = 0.18
    max_IOI_s          = 1.00
    duration_scale     = 2.0
    open_phase         = 0.98
    vibrato_rate_Hz    = 3.0
    vibrato_depth_st   = 0.08
    amp_voice_dB       = 78
    amp_asp_sustain_dB = 66
    chiff_A_amp        = 0.01
    chiff_B_amp        = 0.01
    chiff_C_amp        = 0.06
    appendInfoLine: "[Preset] Sul Ponticello (Glassy) loaded."

else
    appendInfoLine: "[Preset] Custom — using form values."
endif

# ============================================================
# Global constants / defaults for removed form fields
# ============================================================
sr              = 44100
pwr1            = 2
pwr2            = 10
vibrato_amp_mod = 0.03
amp_asp_peak_dB = 58
amp_breath_dB   = 50
attack_s        = 0.14
stabilise_s     = 0.30
release_s       = 0.25
xfade_s         = 0.05
single_note_dur = 2.5    ; duration for single-note mode

# ============================================================
# 1.  12-TONE ROW GENERATION
# ============================================================
# Strategy:
#   Start from a fixed seed sequence (Webern Op.24-style tritone
#   construction) transposed to start on the user's pitch class.
#   Then apply the requested row form (P/I/R/RI).
#
# seed_row#  = the 12 pitch-class intervals from note to note
#              (semitones, positive = up, negative = down)
# pc#        = the 12 pitch classes in order (0–11)
# hz#        = final Hz values, placed in a sensible register

# --- Base row (pitch classes, 0=C) ---
# A classic all-interval row: each adjacent interval is unique.
base_pc# = {0, 11, 3, 4, 8, 7, 9, 6, 1, 5, 2, 10}

# User's first pitch class from Frequency_Hz
root_midi   = round(69 + 12 * log2(frequency_Hz / 440))
root_pc     = root_midi mod 12
base_octave_midi = (base_octave + 1) * 12   ; MIDI note for C in base_octave

# Declare vectors before indexed assignment (required in Praat)
row_pc#    = zero# (12)
final_pc#  = zero# (12)
ri_pc#     = zero# (12)
midi_notes# = zero# (12)
note_hz#   = zero# (12)
ioi#       = zero# (12)

# Transpose base row to start on root_pc
for i from 1 to 12
    row_pc# [i] = (base_pc# [i] + root_pc) mod 12
endfor

# Apply row form
if row_form = 1
    # Prime: as-is
    for i from 1 to 12
        final_pc# [i] = row_pc# [i]
    endfor
elsif row_form = 2
    # Inversion: reflect pitch classes around root
    for i from 1 to 12
        final_pc# [i] = (root_pc - (row_pc# [i] - root_pc) + 120) mod 12
    endfor
elsif row_form = 3
    # Retrograde: reverse the row
    for i from 1 to 12
        final_pc# [i] = row_pc# [13 - i]
    endfor
else
    # Retrograde-Inversion
    for i from 1 to 12
        ri_pc# [i] = (root_pc - (row_pc# [i] - root_pc) + 120) mod 12
    endfor
    for i from 1 to 12
        final_pc# [i] = ri_pc# [13 - i]
    endfor
endif

# Assign each pitch class to a MIDI note in a sensible register.
# Strategy: place each note within one octave of the previous,
# choosing the nearest octave transposition (voice-leading style).
midi_notes# = zero# (12)
midi_notes# [1] = base_octave_midi + final_pc# [1]

for i from 2 to 12
    prev     = midi_notes# [i - 1]
    this_pc  = final_pc# [i]
    # Candidate in same octave as previous
    cand     = floor(prev / 12) * 12 + this_pc
    # Check candidate one octave up or down if closer to prev
    if abs(cand - prev) > 6
        if cand < prev
            cand = cand + 12
        else
            cand = cand - 12
        endif
    endif
    # Clamp to a playable flute range (MIDI 60–90 = C4–F#6)
    if cand < 60
        cand = cand + 12
    endif
    if cand > 90
        cand = cand - 12
    endif
    midi_notes# [i] = cand
endfor

# Convert MIDI to Hz
for i from 1 to 12
    note_hz# [i] = 440 * (2 ^ ((midi_notes# [i] - 69) / 12))
endfor

# ============================================================
# 2.  SERIAL RHYTHM DERIVATION
# ============================================================
# Derive a 12-value rhythm row from the pitch-class intervals.
# Method:
#   interval[i] = (final_pc[i+1] - final_pc[i] + 12) mod 12
#   interval 0 (tritone enharmonic) → treated as 6
#   Map interval 1–11 linearly to Min_IOI .. Max_IOI
#   This gives each note a duration determined by where the
#   row "moves" next — small intervals = short notes, large = long.

ioi_range = max_IOI_s - min_IOI_s

for i from 1 to 12
    if i < 12
        intv = (final_pc# [i + 1] - final_pc# [i] + 12) mod 12
    else
        intv = (final_pc# [1] - final_pc# [12] + 12) mod 12
    endif
    if intv = 0
        intv = 6
    endif
    ; Map 1..11 → min_IOI..max_IOI
    ioi# [i] = min_IOI_s + (intv - 1) / 10 * ioi_range
endfor

; Stretch all note durations by the user-chosen scale factor
for i from 1 to 12
    ioi# [i] = ioi# [i] * duration_scale
endfor

# ============================================================
# 3.  PRINT ROW & RHYTHM INFO
# ============================================================
writeInfoLine:  "=== Flute KlattGrid — Serial Melody ==="
appendInfoLine: ""

if row_form = 1
    row_form$ = "Prime (P0)"
elsif row_form = 2
    row_form$ = "Inversion (I0)"
elsif row_form = 3
    row_form$ = "Retrograde (R0)"
else
    row_form$ = "Retrograde-Inversion (RI0)"
endif

appendInfoLine: "Row form:   ", row_form$
appendInfoLine: "Root pitch: ", fixed$(frequency_Hz, 1), " Hz  (MIDI ", root_midi, ")"
appendInfoLine: ""
appendInfoLine: "Pitch row (Hz):"

note_names$ = "C C# D D# E F F# G G# A A# B"

for i from 1 to 12
    pc_i = final_pc# [i]
    ; Extract note name from the space-separated string
    pc_pos = pc_i * 3 + 1
    n$ = mid$(note_names$, pc_pos, 2)
    ; Trim trailing space
    if right$(n$, 1) = " "
        n$ = left$(n$, 1)
    endif
    oct_i = floor(midi_notes# [i] / 12) - 1
    appendInfoLine: "  ", i, ":  ", n$, oct_i,
    ...             "  ", fixed$(note_hz# [i], 2), " Hz",
    ...             "   IOI=", fixed$(ioi# [i], 3), " s"
endfor

appendInfoLine: ""

# ============================================================
# 4.  SYNTHESIS
# ============================================================

if melody_mode
    appendInfoLine: "Generating 12-tone row melody..."
    appendInfoLine: ""

    ; Synthesize each note and collect Sound object IDs
    note_id# = zero# (12)
    for i from 1 to 12
        appendInfoLine: "  Note ", i, " / 12  (", fixed$(note_hz# [i], 1), " Hz  ", fixed$(ioi# [i], 3), " s)"
        @makeFluteNote: note_hz# [i], ioi# [i], (i = 1)
        note_id# [i] = selected("Sound")
    endfor

    ; --- Legato crossfade: cosine fades + Shift times + object(id,x) mix ---
    appendInfoLine: ""
    appendInfoLine: "Applying legato crossfades and mixing..."

    ; 1. Collect note durations first (before any time-axis shift)
    note_dur_leg# = zero# (12)
    for i from 1 to 12
        selectObject: note_id# [i]
        note_dur_leg# [i] = Get total duration
    endfor

    ; 2. Apply cosine fades while time axis is still 0-based
    for i from 1 to 12
        selectObject: note_id# [i]
        .nd = note_dur_leg# [i]
        if i > 1
            Formula (part): 0, xfade_s, 1, 1,
            ... "self * (0.5 - 0.5*cos(pi*x/xfade_s))"
        endif
        if i < 12
            .fs = .nd - xfade_s
            Formula (part): .fs, .nd, 1, 1,
            ... "self * (0.5 + 0.5*cos(pi*(x-.fs)/xfade_s))"
        endif
    endfor

    ; 3. Compute offset for each note (overlap = xfade_s)
    note_offset_leg# = zero# (12)
    .running_t = 0
    for i from 1 to 12
        note_offset_leg# [i] = .running_t
        .running_t += note_dur_leg# [i] - xfade_s
    endfor
    total_legato_dur = .running_t + xfade_s

    ; 4. Shift each note's time axis to its absolute position in the melody
    for i from 1 to 12
        selectObject: note_id# [i]
        Shift times to: "start time", note_offset_leg# [i]
    endfor

    ; 5. Create silence output buffer
    melody = Create Sound from formula: "flute_serial_melody", 1, 0, total_legato_dur, sr, "0"

    ; 6. Add each note into the buffer at its shifted position using object(id, x)
    ;    This is the correct Praat technique (learned from Additive_Particle_Field.praat)
    for i from 1 to 12
        .nid  = note_id# [i]
        .tS$  = fixed$(note_offset_leg# [i], 6)
        .tE$  = fixed$(note_offset_leg# [i] + note_dur_leg# [i], 6)
        .nid$ = string$(.nid)
        selectObject: melody
        Formula: "if x >= " + .tS$ + " and x <= " + .tE$ +
        ... " then self + object(" + .nid$ + ", x) else self fi"
        removeObject: .nid
    endfor

    Rename: "flute_serial_melody"

    ; Fast cosine fade-out at the very end of the melody
    .fade_end_s = 0.18
    selectObject: melody
    .meldur = Get total duration
    Formula (part): .meldur - .fade_end_s, .meldur, 1, 1,
    ... "self * (0.5 + 0.5*cos(pi*(x-(.meldur-.fade_end_s))/.fade_end_s))"

    sound = melody

else
    appendInfoLine: "Generating single note..."
    @makeFluteNote: frequency_Hz, single_note_dur, 1
    sound = selected("Sound")
    Rename: "flute_" + fixed$(frequency_Hz, 0) + "Hz"
endif

selectObject: sound
Scale peak: 0.92

# ============================================================
# 5.  VISUALIZATION
# ============================================================
if draw_visualization
    @drawVisualization
endif

# ============================================================
# 6.  PLAY
# ============================================================
if play_result
    selectObject: sound
    Play
endif

selectObject: sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")


# ==============================================================================
# Procedure: makeFluteNote
#   Synthesizes one flute note with layered chiff attack.
#   .freq  = frequency in Hz
#   .dur   = note duration in seconds
#   Leaves the mixed result selected.
# ==============================================================================
procedure makeFluteNote: .freq, .dur, .do_attack
    # .do_attack = 1 : first note — full attack, pitch sag, chiff layers
    # .do_attack = 0 : interior/last notes — start at full sustain, no chiff
    #                  (legato: amplitude never dips; only pitch changes)

    # --- Chiff durations (only used when .do_attack = 1) ---
    .chiff_A_dur = 0.02
    .chiff_B_dur = 0.06
    .chiff_C_dur = 0.015

    # Formants track the note frequency
    .f1_hz = .freq
    .f1_bw = .freq * 0.25
    .f2_hz = .freq * 2.0
    .f2_bw = .freq * 0.35
    .f3_hz = .freq * 3.5
    .f3_bw = 350
    .f4_hz = .freq * 5.5
    .f4_bw = 500
    .f5_hz = .freq * 8.0
    .f5_bw = 700

    # ------------------------------------------------------------------
    # MAIN KLATTGRID TONE
    # ------------------------------------------------------------------
    .kg = Create KlattGrid: "flute", 0, .dur, 5, 0, 0, 0, 0, 1, 0

    selectObject: .kg
    Add open phase point: 0, open_phase
    Add power1 point:     0, pwr1
    Add power2 point:     0, pwr2

    # Pitch — attack note: gentle sag then settle; legato note: on-pitch immediately
    selectObject: .kg
    if .do_attack
        Add pitch point: 0.001,        .freq * 0.97
        Add pitch point: attack_s,     .freq * 0.99
        Add pitch point: stabilise_s,  .freq
    else
        Add pitch point: 0.001, .freq
    endif

    .vib_period = 1.0 / vibrato_rate_Hz
    .vib_end    = .dur - release_s + 0.05
    if .do_attack
        .vib_start = stabilise_s
    else
        .vib_start = 0.05   ; vibrato kicks in quickly on legato notes
    endif
    .n_vib = ceiling((.vib_end - .vib_start) / (.vib_period / 8))

    for .i from 1 to .n_vib
        .t_v = .vib_start + (.i - 1) * (.vib_period / 8)
        if .t_v <= .vib_end
            .ph = 2 * pi * vibrato_rate_Hz * (.t_v - .vib_start)
            Add pitch point: .t_v, .freq * (2 ^ (vibrato_depth_st * sin(.ph) / 12))
        endif
    endfor
    Add pitch point: .dur - 0.01, .freq

    # Voicing amplitude
    selectObject: .kg
    if .do_attack
        ; Ramp up from silence over attack/stabilise, then release
        Add voicing amplitude point: 0,                  0
        Add voicing amplitude point: attack_s,            amp_voice_dB * 0.30
        Add voicing amplitude point: stabilise_s,         amp_voice_dB
        Add voicing amplitude point: .dur - release_s,    amp_voice_dB
        Add voicing amplitude point: .dur,                0
    else
        ; Full sustain from the very first sample — crossfade handles the blend
        Add voicing amplitude point: 0,    amp_voice_dB
        Add voicing amplitude point: .dur, amp_voice_dB
    endif

    for .i from 1 to .n_vib
        .t_v = .vib_start + (.i - 1) * (.vib_period / 8)
        if .t_v <= .vib_end
            .ph     = 2 * pi * vibrato_rate_Hz * (.t_v - .vib_start)
            .av_mod = amp_voice_dB * (1.0 + vibrato_amp_mod * sin(.ph))
            Add voicing amplitude point: .t_v, .av_mod
        endif
    endfor

    # Aspiration
    selectObject: .kg
    if .do_attack
        ; Ramp from 0 — no burst at time zero (fixes noise-at-onset bug)
        Add aspiration amplitude point: 0,               0
        Add aspiration amplitude point: attack_s,         amp_asp_peak_dB
        Add aspiration amplitude point: stabilise_s,      amp_asp_sustain_dB
        Add aspiration amplitude point: .dur - release_s, amp_asp_sustain_dB
        Add aspiration amplitude point: .dur,             0
    else
        Add aspiration amplitude point: 0,    amp_asp_sustain_dB
        Add aspiration amplitude point: .dur, amp_asp_sustain_dB
    endif

    # Breathiness
    selectObject: .kg
    if .do_attack
        Add breathiness amplitude point: 0,               0
        Add breathiness amplitude point: attack_s,         amp_breath_dB
        Add breathiness amplitude point: stabilise_s,      amp_breath_dB - 5
        Add breathiness amplitude point: .dur - release_s, amp_breath_dB - 5
        Add breathiness amplitude point: .dur,             0
    else
        Add breathiness amplitude point: 0,    amp_breath_dB - 5
        Add breathiness amplitude point: .dur, amp_breath_dB - 5
    endif

    # Flutter
    selectObject: .kg
    Add flutter point: 0,    0.02
    Add flutter point: .dur, 0.02

    # Oral formants
    selectObject: .kg
    Add oral formant frequency point: 1, 0, .f1_hz
    Add oral formant bandwidth point: 1, 0, .f1_bw
    Add oral formant frequency point: 2, 0, .f2_hz
    Add oral formant bandwidth point: 2, 0, .f2_bw
    Add oral formant frequency point: 3, 0, .f3_hz
    Add oral formant bandwidth point: 3, 0, .f3_bw
    Add oral formant frequency point: 4, 0, .f4_hz
    Add oral formant bandwidth point: 4, 0, .f4_bw
    Add oral formant frequency point: 5, 0, .f5_hz
    Add oral formant bandwidth point: 5, 0, .f5_bw

    selectObject: .kg
    .flute_raw = To Sound

    selectObject: .flute_raw
    .main_tone = Filter (pass Hann band): 80, 7000, 150

    if .do_attack
        # ------------------------------------------------------------------
        # CHIFF LAYERS — only on the first (attack) note
        # ------------------------------------------------------------------

        # Chiff A — broadband turbulence burst
        .chA_dur$ = fixed$(.chiff_A_dur, 6)
        .chiff_A_noise = Create Sound from formula: "chiffA", 1, 0, .dur, sr,
        ... "if x < " + .chA_dur$ + " then randomGauss(0,1) else 0 fi"
        selectObject: .chiff_A_noise
        .chiff_A_filt = Filter (pass Hann band): .freq * 0.7, .freq * 4.0, 200
        selectObject: .chiff_A_filt
        Formula: "self * exp(-6.0 * x / " + .chA_dur$ + ") * if x < " + .chA_dur$ + " then 1 else 0 fi"
        Scale peak: chiff_A_amp
        removeObject: .chiff_A_noise

        # Chiff B — sub-tone pitch sweep
        .kg_b = Create KlattGrid: "chiffB", 0, .dur, 2, 0, 0, 0, 0, 1, 0
        selectObject: .kg_b
        Add open phase point: 0, 0.95
        Add power1 point:     0, 2
        Add power2 point:     0, 12
        selectObject: .kg_b
        Add pitch point: 0.001,          .freq * 0.60
        Add pitch point: .chiff_B_dur,   .freq * 1.00
        Add pitch point: .dur,           .freq
        selectObject: .kg_b
        Add voicing amplitude point: 0,                    0
        Add voicing amplitude point: .chiff_B_dur * 0.15,  75
        Add voicing amplitude point: .chiff_B_dur * 0.60,  80
        Add voicing amplitude point: .chiff_B_dur,         0
        Add voicing amplitude point: .dur,                 0
        selectObject: .kg_b
        Add oral formant frequency point: 1, 0,              .freq * 0.60
        Add oral formant frequency point: 1, .chiff_B_dur,   .freq
        Add oral formant bandwidth point: 1, 0,              .freq * 0.5
        Add oral formant frequency point: 2, 0,              .freq * 1.5
        Add oral formant bandwidth point: 2, 0,              .freq * 0.6
        selectObject: .kg_b
        .chiff_B_raw = To Sound
        selectObject: .chiff_B_raw
        .chiff_B = Filter (pass Hann band): 80, .freq * 5, 150
        Scale peak: chiff_B_amp
        removeObject: .kg_b, .chiff_B_raw

        # Chiff C — high-frequency frication edge
        .chC_dur$ = fixed$(.chiff_C_dur, 6)
        .chiff_C_noise = Create Sound from formula: "chiffC", 1, 0, .dur, sr,
        ... "if x < " + .chC_dur$ + " then randomGauss(0,1) else 0 fi"
        selectObject: .chiff_C_noise
        .chiff_C_filt = Filter (pass Hann band): 2000, 9000, 300
        selectObject: .chiff_C_filt
        Formula: "self * exp(-9.0 * x / " + .chC_dur$ + ") * if x < " + .chC_dur$ + " then 1 else 0 fi"
        Scale peak: chiff_C_amp
        removeObject: .chiff_C_noise

        # MIX: 4-channel combine → mono → restore additive sum
        selectObject: .main_tone, .chiff_A_filt, .chiff_B, .chiff_C_filt
        Combine to stereo
        .combined = selected("Sound")
        Convert to mono
        .mix = selected("Sound")
        Formula: "self * 4"
        Scale peak: 0.90
        removeObject: .kg, .flute_raw, .main_tone
        removeObject: .chiff_A_filt, .chiff_B, .chiff_C_filt
        removeObject: .combined

    else
        # ------------------------------------------------------------------
        # LEGATO NOTE — main tone only, already at full sustain
        # ------------------------------------------------------------------
        selectObject: .main_tone
        Copy: "fluteNote"
        .mix = selected("Sound")
        Scale peak: 0.90
        removeObject: .kg, .flute_raw, .main_tone

    endif

    selectObject: .mix

endproc


# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    selectObject: sound
    .totalDur = Get total duration

    Erase all

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.95
    Font size: 13
    Colour: "Black"
    if melody_mode
        Text special: 0.5, "centre", 0.95, "half", "Helvetica", 13, "0",
        ... "##Flute KlattGrid — Serial Melody  (" + row_form$ + ")##"
    else
        Text special: 0.5, "centre", 0.6, "half", "Helvetica", 13, "0",
        ... "##Flute KlattGrid — Single Note##"
    endif

    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text special: 0.5, "centre", 0.2, "half", "Helvetica", 8, "0",
    ... "Root: " + fixed$(frequency_Hz, 1) + " Hz  |  "
    ... + "Vibrato: " + fixed$(vibrato_rate_Hz, 1) + " Hz  |  "
    ... + "Voice: " + fixed$(amp_voice_dB, 0) + " dB  |  "
    ... + "Open phase: " + fixed$(open_phase, 2)

    # === Waveform ===
    Select outer viewport: 0, 8, 0.7, 2.6
    Select inner viewport: 0.7, 7.6, 0.8, 2.5

    selectObject: sound
    Colour: "{0.15, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    # === Spectrum ===
    Select outer viewport: 0, 8, 2.8, 4.6
    Select inner viewport: 0.7, 7.6, 2.9, 4.5

    selectObject: sound
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")

    Colour: "{0.55, 0.25, 0.60}"
    Draw: 0, 5000, 0, 0, "no"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 1000, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    removeObject: .spectrum

    # === Spectrogram ===
    Select outer viewport: 0, 8, 4.8, 7.2
    Select inner viewport: 0.7, 7.6, 4.9, 7.1

    selectObject: sound
    .maxFreq = min(6000, frequency_Hz * 14)
    To Spectrogram: 0.025, .maxFreq, 0.005, 20, "Gaussian"
    .spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spectrogram

    Select inner viewport: 0.7, 7.6, 4.9, 7.1
    Axes: 0, .totalDur, 0, .maxFreq
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"

    # === Pitch row annotation (melody mode only) ===
    if melody_mode
        Select outer viewport: 0, 8, 7.3, 7.7
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "{0.3, 0.3, 0.3}"

        ; Build a compact pitch-class string for display
        row_display$ = "Row: "
        .t_cursor = 0
        for .i from 1 to 12
            .pc_i = final_pc# [.i]
            .pc_pos = .pc_i * 3 + 1
            .n$ = mid$(note_names$, .pc_pos, 2)
            if right$(.n$, 1) = " "
                .n$ = left$(.n$, 1)
            endif
            row_display$ = row_display$ + .n$ + " "
        endfor
        row_display$ = row_display$ + "  |  IOI: "
        for .i from 1 to 12
            row_display$ = row_display$ + fixed$(ioi# [.i], 2) + " "
        endfor

        Text special: 0.5, "centre", 0.5, "half", "Helvetica", 7, "0",
        ... row_display$
    endif

    Font size: 10
    Colour: "Black"
    Line width: 1

endproc
