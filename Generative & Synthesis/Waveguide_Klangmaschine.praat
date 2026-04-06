# ============================================================
# Praat AudioTools - Waveguide_Klangmaschine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2025) - Audio Analysis Input Pipeline
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Waveguide Klangmaschine: generates a randomized SATB
#   chord using digital waveguide synthesis with per-string
#   allpass fractional delay, stiffness dispersion, LP damping,
#   and bridge coupling — processed through an 8-mode soundboard
#   resonator bank, spectral-split stereo imaging, and a true-
#   stereo Poisson-process spectral decay reverb.
#
# v2.1 Audio Analysis Pipeline:
#   If a Sound object is selected before running, the script
#   analyzes it and automatically derives synthesis parameters:
#     - Root pitch / F0    → Transpose_semitones (key center)
#     - Up to 4 pitches    → Constrain SATB note ranges
#     - Duration           → Duration_s
#     - HNR                → Randomize_depth
#     - Spectral centroid  → High_cutoff_Hz + reverb brightness
#     - Decay rate         → Decay_base + Tail_duration_s
#     - RMS / loudness     → velocity + Wet_dry_percent
#     - Envelope shape     → Reverb Preset selection
#   Falls back to manual form values when no Sound is selected.
#
# ============================================================

form Synthesize Random SATB Klang Machine
    comment === Input Mode ===
    comment (Select a Sound object before running to use audio analysis)
    boolean Use_selected_sound 1
    comment (If unchecked, manual parameters below are used)

    real Duration_s 8.0
    comment --- CPU Optimization ---
    positive Internal_rate 5512.5
    positive Final_rate 44100
    integer Transpose_semitones 0

    comment === Spectral Decay Reverb ===
    optionmenu Preset 3
        option Custom (use settings below)
        option Subtle Decay
        option Medium Decay
        option Heavy Decay
        option Extreme Decay
    positive Tail_duration_s 2.0
    positive Impulse_duration_s 3.0
    positive Poisson_density 2000
    positive Decay_base 110
    positive Low_cutoff_Hz 100
    positive High_cutoff_Hz 4000
    positive Smoothing_Hz 100
    real Wet_dry_percent 50
    positive Fadeout_duration_s 1.2

    comment === Output ===
    optionmenu Randomize_depth 2
        option None (standard waveguide)
        option Subtle (slight per-voice variation)
        option Wild (imaginary instrument space)
endform

# =============================================================
# AUDIO ANALYSIS PIPELINE
# =============================================================

audio_was_analyzed = 0
analysis_pitch_count = 0

# SATB note constraint ranges (defaults — may be overridden by analysis)
bass_lo = 40
bass_hi = 55
tenor_lo = 52
tenor_hi = 64
alto_lo = 53
alto_hi = 72
soprano_lo = 60
soprano_hi = 84

if use_selected_sound
    nSel = numberOfSelected("Sound")

    if nSel = 0
        appendInfoLine: "[Analysis] No Sound selected — using manual parameters."
    else
        inputSound = selected("Sound")
        inputSound$ = selected$("Sound")
        appendInfoLine: "[Analysis] Analyzing: '", inputSound$, "'"
        selectObject: inputSound

        # ------------------------------------------------------------------
        # 1. DURATION
        # ------------------------------------------------------------------
        analysed_dur = Get total duration
        duration_s = analysed_dur
        appendInfoLine: "  Duration:         ", fixed$(duration_s, 3), " s"

        # ------------------------------------------------------------------
        # 2. PITCH ANALYSIS — root pitch + up to 4 voices
        #    Uses To Pitch to get a sequence of F0 values, then clusters
        #    them into up to 4 distinct pitch classes for SATB constraint.
        # ------------------------------------------------------------------
        selectObject: inputSound
        pitchObj = To Pitch: 0, 60, 800

        meanPitch = Get mean: 0, 0, "Hertz"
        minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
        maxPitch = Get maximum: 0, 0, "Hertz", "Parabolic"

        if meanPitch = undefined or meanPitch < 60
            root_hz = 220
            root_midi = 57
            appendInfoLine: "  Pitch:            undefined (unpitched) → A3 default"
        else
            root_hz = meanPitch
            root_midi = round(69 + 12 * log2(root_hz / 440))
            appendInfoLine: "  Root pitch:       ", fixed$(root_hz, 1), " Hz  → MIDI ", root_midi
        endif

        # Transpose to align root pitch to nearest C, then compute offset
        root_pc = root_midi mod 12
        nearest_c_midi = root_midi - root_pc
        transpose_semitones = nearest_c_midi - 60

        if transpose_semitones < -12
            transpose_semitones = transpose_semitones + 12
        endif
        if transpose_semitones > 12
            transpose_semitones = transpose_semitones - 12
        endif
        appendInfoLine: "  Transpose offset: ", transpose_semitones, " semitones (key-center alignment)"

        # Attempt multi-pitch detection by sampling pitch at 8 time points
        # and collecting distinct MIDI values for SATB range narrowing
        pitchDur = Get total duration
        step = pitchDur / 9
        p_count = 0
        p1 = 0
        p2 = 0
        p3 = 0
        p4 = 0

        for ti from 1 to 8
            t_sample = ti * step
            hz_val = Get value at time: t_sample, "Hertz", "Linear"
            if hz_val <> undefined and hz_val > 60 and hz_val < 1200
                midi_val = round(69 + 12 * log2(hz_val / 440))
                # Store if distinct from existing (within 2 semitones = same note)
                is_new = 1
                if p_count >= 1
                    if abs(midi_val - p1) < 3
                        is_new = 0
                    endif
                endif
                if p_count >= 2
                    if abs(midi_val - p2) < 3
                        is_new = 0
                    endif
                endif
                if p_count >= 3
                    if abs(midi_val - p3) < 3
                        is_new = 0
                    endif
                endif
                if p_count >= 4
                    if abs(midi_val - p4) < 3
                        is_new = 0
                    endif
                endif
                if is_new = 1 and p_count < 4
                    p_count = p_count + 1
                    if p_count = 1
                        p1 = midi_val
                    elsif p_count = 2
                        p2 = midi_val
                    elsif p_count = 3
                        p3 = midi_val
                    else
                        p4 = midi_val
                    endif
                endif
            endif
        endfor

        analysis_pitch_count = p_count
        appendInfoLine: "  Detected pitches: ", p_count

        # If we found multiple pitches, constrain SATB ranges around them.
        # Sort detected pitches low→high and assign to Bass/Tenor/Alto/Soprano.
        # Each voice range is narrowed to ±5 semitones around the detected pitch.
        if p_count >= 2
            # Simple bubble sort of p1..p4
            if p_count >= 2 and p1 > p2
                tmp = p1
                p1 = p2
                p2 = tmp
            endif
            if p_count >= 3 and p2 > p3
                tmp = p2
                p2 = p3
                p3 = tmp
            endif
            if p_count >= 4 and p3 > p4
                tmp = p3
                p3 = p4
                p4 = tmp
            endif
            if p_count >= 2 and p1 > p2
                tmp = p1
                p1 = p2
                p2 = tmp
            endif
            if p_count >= 3 and p2 > p3
                tmp = p2
                p2 = p3
                p3 = tmp
            endif
            if p_count >= 2 and p1 > p2
                tmp = p1
                p1 = p2
                p2 = tmp
            endif

            spread = 5

            if p_count = 2
                bass_lo  = p1 - spread
                bass_hi  = p1 + spread
                tenor_lo = p1 - spread
                tenor_hi = p1 + spread
                alto_lo  = p2 - spread
                alto_hi  = p2 + spread
                soprano_lo = p2 - spread
                soprano_hi = p2 + spread
            elsif p_count = 3
                bass_lo  = p1 - spread
                bass_hi  = p1 + spread
                tenor_lo = p2 - spread
                tenor_hi = p2 + spread
                alto_lo  = p2 - spread
                alto_hi  = p2 + spread
                soprano_lo = p3 - spread
                soprano_hi = p3 + spread
            else
                bass_lo  = p1 - spread
                bass_hi  = p1 + spread
                tenor_lo = p2 - spread
                tenor_hi = p2 + spread
                alto_lo  = p3 - spread
                alto_hi  = p3 + spread
                soprano_lo = p4 - spread
                soprano_hi = p4 + spread
            endif

            # Clamp to SATB physical ranges
            if bass_lo < 28
                bass_lo = 28
            endif
            if bass_hi > 60
                bass_hi = 60
            endif
            if tenor_lo < 40
                tenor_lo = 40
            endif
            if tenor_hi > 69
                tenor_hi = 69
            endif
            if alto_lo < 48
                alto_lo = 48
            endif
            if alto_hi > 74
                alto_hi = 74
            endif
            if soprano_lo < 55
                soprano_lo = 55
            endif
            if soprano_hi > 88
                soprano_hi = 88
            endif

            # Guarantee at least 1-semitone range
            if bass_lo >= bass_hi
                bass_hi = bass_lo + 1
            endif
            if tenor_lo >= tenor_hi
                tenor_hi = tenor_lo + 1
            endif
            if alto_lo >= alto_hi
                alto_hi = alto_lo + 1
            endif
            if soprano_lo >= soprano_hi
                soprano_hi = soprano_lo + 1
            endif

            appendInfoLine: "  SATB ranges constrained from detected pitches:"
            appendInfoLine: "    Bass:    MIDI ", bass_lo, "–", bass_hi
            appendInfoLine: "    Tenor:   MIDI ", tenor_lo, "–", tenor_hi
            appendInfoLine: "    Alto:    MIDI ", alto_lo, "–", alto_hi
            appendInfoLine: "    Soprano: MIDI ", soprano_lo, "–", soprano_hi
        endif

        removeObject: pitchObj

        # ------------------------------------------------------------------
        # 3. HNR → Randomize_depth
        #    High HNR (>15 dB) → None (clean piano waveguide)
        #    Mid  HNR (5–15)   → Subtle
        #    Low  HNR (<5)     → Wild
        # ------------------------------------------------------------------
        selectObject: inputSound
        hnrObj = To Harmonicity (cc): 0.01, 75, 0.1, 1.0
        meanHNR = Get mean: 0, 0
        removeObject: hnrObj

        if meanHNR = undefined
            meanHNR = 0
        endif
        appendInfoLine: "  HNR:              ", fixed$(meanHNR, 2), " dB"

        if meanHNR > 15
            randomize_depth = 1
            appendInfoLine: "  Randomize depth: None (harmonic source)"
        elsif meanHNR > 5
            randomize_depth = 2
            appendInfoLine: "  Randomize depth: Subtle (mixed source)"
        else
            randomize_depth = 3
            appendInfoLine: "  Randomize depth: Wild (noisy source)"
        endif

        # ------------------------------------------------------------------
        # 4. SPECTRAL CENTROID → High_cutoff_Hz + reverb brightness
        #    Brighter input = wider high shelf in stereo reverb
        # ------------------------------------------------------------------
        selectObject: inputSound
        specObj = To Spectrum: "yes"
        centroid = Get centre of gravity: 2
        removeObject: specObj

        if centroid = undefined
            centroid = 2000
        endif
        appendInfoLine: "  Spectral centroid:", fixed$(centroid, 0), " Hz"

        # Map centroid 500–6000 Hz → high_cutoff 2000–8000 Hz
        high_cutoff_Hz = 2000 + ((centroid - 500) / 5500) * 6000
        if high_cutoff_Hz < 2000
            high_cutoff_Hz = 2000
        endif
        if high_cutoff_Hz > 8000
            high_cutoff_Hz = 8000
        endif
        appendInfoLine: "  High cutoff:      ", fixed$(high_cutoff_Hz, 0), " Hz"

        # ------------------------------------------------------------------
        # 5. RMS → velocity + wet_dry_percent
        #    Louder input → higher velocity, drier mix
        #    Quieter input → lower velocity, wetter mix
        # ------------------------------------------------------------------
        selectObject: inputSound
        rmsVal = Get root-mean-square: 0, 0

        if rmsVal = undefined or rmsVal <= 0
            rmsVal = 0.1
        endif
        # Clamp to sensible range 0.001–0.5
        if rmsVal > 0.5
            rmsVal = 0.5
        endif
        if rmsVal < 0.001
            rmsVal = 0.001
        endif

        # Map RMS log-scale to velocity 0.3–0.95
        log_rms = ln(rmsVal / 0.001) / ln(0.5 / 0.001)
        velocity_from_audio = 0.3 + log_rms * 0.65
        if velocity_from_audio < 0.3
            velocity_from_audio = 0.3
        endif
        if velocity_from_audio > 0.95
            velocity_from_audio = 0.95
        endif

        # Louder → drier (lower wet%), quieter → wetter
        wet_dry_percent = 75 - (log_rms * 40)
        if wet_dry_percent < 20
            wet_dry_percent = 20
        endif
        if wet_dry_percent > 80
            wet_dry_percent = 80
        endif
        appendInfoLine: "  RMS:              ", fixed$(rmsVal, 4), "  → velocity=", fixed$(velocity_from_audio, 2), "  wet=", fixed$(wet_dry_percent, 0), "%"

        # ------------------------------------------------------------------
        # 6. DECAY RATE → Decay_base + Tail_duration_s
        #    Fast-decaying input → shorter reverb tail & higher decay_base
        #    Sustained input    → longer tail & lower decay_base
        # ------------------------------------------------------------------
        selectObject: inputSound
        totalDurDecay = Get total duration
        earlyEnd = totalDurDecay * 0.1
        lateStart = totalDurDecay * 0.7

        rmsEarly = Get root-mean-square: 0, earlyEnd
        rmsLate  = Get root-mean-square: lateStart, totalDurDecay

        if rmsEarly = undefined or rmsEarly <= 0
            rmsEarly = 0.01
        endif
        if rmsLate = undefined or rmsLate <= 0
            rmsLate = 0.0001
        endif

        timeSpan = (lateStart + totalDurDecay) / 2 - earlyEnd / 2
        if timeSpan > 0 and rmsEarly > 0 and rmsLate > 0
            decayExp = -ln(rmsLate / rmsEarly) / timeSpan
        else
            decayExp = 5
        endif
        appendInfoLine: "  Decay exponent:   ", fixed$(decayExp, 3)

        # Map decayExp 0–30 → decay_base 50–200 (fast decay = high base = short reverb)
        decay_base = 50 + (decayExp / 30) * 150
        if decay_base < 50
            decay_base = 50
        endif
        if decay_base > 200
            decay_base = 200
        endif

        # Map decayExp to tail duration: fast → short tail, slow → long tail
        tail_duration_s = 3.5 - (decayExp / 30) * 2.5
        if tail_duration_s < 1.0
            tail_duration_s = 1.0
        endif
        if tail_duration_s > 4.5
            tail_duration_s = 4.5
        endif
        impulse_duration_s = tail_duration_s * 1.3
        appendInfoLine: "  Decay base:       ", fixed$(decay_base, 0), "  tail=", fixed$(tail_duration_s, 2), " s"

        # ------------------------------------------------------------------
        # 7. ENVELOPE SHAPE → Reverb Preset
        #    Compare RMS in 3 zones to classify shape
        # ------------------------------------------------------------------
        selectObject: inputSound
        envDur = Get total duration
        zone = envDur / 3

        rmsZ1 = Get root-mean-square: 0,        zone
        rmsZ2 = Get root-mean-square: zone,      zone * 2
        rmsZ3 = Get root-mean-square: zone * 2,  envDur

        if rmsZ1 = undefined
            rmsZ1 = 0.01
        endif
        if rmsZ2 = undefined
            rmsZ2 = 0.01
        endif
        if rmsZ3 = undefined
            rmsZ3 = 0.01
        endif

        if rmsZ1 > rmsZ2 * 1.5 and rmsZ1 > rmsZ3 * 2.5
            preset = 2
            appendInfoLine: "  Envelope:         Percussive → Subtle reverb"
        elsif rmsZ3 > rmsZ1 * 1.5
            preset = 4
            appendInfoLine: "  Envelope:         Swell → Heavy reverb"
        elsif rmsZ1 < rmsZ2 * 0.7 and rmsZ2 > rmsZ3 * 1.5
            preset = 3
            appendInfoLine: "  Envelope:         ADSR → Medium reverb"
        elsif decayExp < 2
            preset = 5
            appendInfoLine: "  Envelope:         Sustained/drone → Extreme reverb"
        else
            preset = 3
            appendInfoLine: "  Envelope:         Steady → Medium reverb"
        endif

        appendInfoLine: ""
        audio_was_analyzed = 1
        selectObject: inputSound
    endif
endif

# =============================================================
# 1. GLOBAL SETUP & RANDOMIZED PARAMETERS
# =============================================================
Erase all
clearinfo
appendInfoLine: "KLANG MACHINE v2.1: Generating New Patch..."
if audio_was_analyzed
    appendInfoLine: "(Parameters derived from audio analysis)"
endif

if audio_was_analyzed
    velocity = velocity_from_audio
else
    velocity = randomUniform(0.4, 0.95)
endif
strings = randomInteger(1, 3)
detune = randomUniform(0.1, 2.5)
resonance = randomUniform(0.2, 0.95)

if randomize_depth = 1
    depth_frac = 0.0
    depth_name$ = "None"
elsif randomize_depth = 2
    depth_frac = 0.3
    depth_name$ = "Subtle"
else
    depth_frac = 1.0
    depth_name$ = "Wild"
endif

appendInfoLine: "Randomize Depth:    ", depth_name$, " (", fixed$(depth_frac, 1), ")"
if transpose_semitones <> 0
    appendInfoLine: "Transpose:          ", transpose_semitones, " semitones"
endif
appendInfoLine: "Velocity (Force):   ", fixed$(velocity, 2)
appendInfoLine: "Strings per Note:   ", strings
appendInfoLine: "Detune Amount:      ", fixed$(detune, 2)
appendInfoLine: "Body Resonance:     ", fixed$(resonance, 2)
appendInfoLine: "------------------------------------"

total_samples = round(duration_s * internal_rate)
rate_ratio = internal_rate / 44100.0
master_dry# = zero#(total_samples)

# --- LAYER 2: Randomize body resonator parameters ---
body_f1 = 65.0
body_f2 = 130.0
body_f3 = 210.0
body_f4 = 340.0
body_f5 = 560.0
body_f6 = 950.0
body_f7 = 1800.0
body_f8 = 3200.0

body_bw1 = 7.0
body_bw2 = 13.0
body_bw3 = 22.0
body_bw4 = 36.0
body_bw5 = 60.0
body_bw6 = 100.0
body_bw7 = 175.0
body_bw8 = 320.0

body_g1 = 0.42
body_g2 = 0.34
body_g3 = 0.26
body_g4 = 0.19
body_g5 = 0.13
body_g6 = 0.08
body_g7 = 0.05
body_g8 = 0.025

if depth_frac > 0
    body_f1 = body_f1  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f2 = body_f2  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f3 = body_f3  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f4 = body_f4  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f5 = body_f5  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f6 = body_f6  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f7 = body_f7  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))
    body_f8 = body_f8  * (1.0 + depth_frac * randomUniform(-0.40, 0.40))

    body_bw1 = body_bw1 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw2 = body_bw2 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw3 = body_bw3 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw4 = body_bw4 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw5 = body_bw5 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw6 = body_bw6 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw7 = body_bw7 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))
    body_bw8 = body_bw8 * (1.0 + depth_frac * randomUniform(-0.50, 0.50))

    body_g1 = body_g1 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g2 = body_g2 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g3 = body_g3 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g4 = body_g4 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g5 = body_g5 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g6 = body_g6 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g7 = body_g7 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))
    body_g8 = body_g8 * (1.0 + depth_frac * randomUniform(-0.60, 0.60))

    if body_g1 < 0.005
        body_g1 = 0.005
    endif
    if body_g2 < 0.005
        body_g2 = 0.005
    endif
    if body_g3 < 0.005
        body_g3 = 0.005
    endif
    if body_g4 < 0.005
        body_g4 = 0.005
    endif
    if body_g5 < 0.005
        body_g5 = 0.005
    endif
    if body_g6 < 0.005
        body_g6 = 0.005
    endif
    if body_g7 < 0.005
        body_g7 = 0.005
    endif
    if body_g8 < 0.005
        body_g8 = 0.005
    endif

    appendInfoLine: ""
    appendInfoLine: "--- LAYER 2: Randomized Body ---"
    appendInfoLine: "  R1: ", fixed$(body_f1, 0), " Hz  bw=",
        ... fixed$(body_bw1, 1), "  g=", fixed$(body_g1, 3)
    appendInfoLine: "  R2: ", fixed$(body_f2, 0), " Hz  bw=",
        ... fixed$(body_bw2, 1), "  g=", fixed$(body_g2, 3)
    appendInfoLine: "  R3: ", fixed$(body_f3, 0), " Hz  bw=",
        ... fixed$(body_bw3, 1), "  g=", fixed$(body_g3, 3)
    appendInfoLine: "  R4: ", fixed$(body_f4, 0), " Hz  bw=",
        ... fixed$(body_bw4, 1), "  g=", fixed$(body_g4, 3)
    appendInfoLine: "  R5: ", fixed$(body_f5, 0), " Hz  bw=",
        ... fixed$(body_bw5, 1), "  g=", fixed$(body_g5, 3)
    appendInfoLine: "  R6: ", fixed$(body_f6, 0), " Hz  bw=",
        ... fixed$(body_bw6, 1), "  g=", fixed$(body_g6, 3)
    appendInfoLine: "  R7: ", fixed$(body_f7, 0), " Hz  bw=",
        ... fixed$(body_bw7, 1), "  g=", fixed$(body_g7, 3)
    appendInfoLine: "  R8: ", fixed$(body_f8, 0), " Hz  bw=",
        ... fixed$(body_bw8, 1), "  g=", fixed$(body_g8, 3)
endif

# =============================================================
# 2. VOICE LOOP (Generate 4 SATB notes — constrained if analyzed)
# =============================================================
for voice from 1 to 4
    if voice = 1
        midi_note = randomInteger(bass_lo, bass_hi) + transpose_semitones
        bass_note = midi_note
        voice_name$ = "Bass   "
    elsif voice = 2
        midi_note = randomInteger(tenor_lo, tenor_hi) + transpose_semitones
        tenor_note = midi_note
        voice_name$ = "Tenor  "
    elsif voice = 3
        midi_note = randomInteger(alto_lo, alto_hi) + transpose_semitones
        alto_note = midi_note
        voice_name$ = "Alto   "
    else
        midi_note = randomInteger(soprano_lo, soprano_hi) + transpose_semitones
        soprano_note = midi_note
        voice_name$ = "Soprano"
    endif

    appendInfoLine: voice_name$, " MIDI Note: ", midi_note

    voice_vel = velocity + randomUniform(-0.05, 0.05)
    if voice_vel < 0.3
        voice_vel = 0.3
    endif
    if voice_vel > 1.0
        voice_vel = 1.0
    endif

    base_freq = 440.0 * (2.0 ^ ((midi_note - 69.0) / 12.0))
    note_idx = midi_note - 21
    if note_idx < 0
        note_idx = 0
    endif
    if note_idx > 87
        note_idx = 87
    endif

    # --- LAYER 1: Per-voice string character ---
    strike_a = 0.125 - (note_idx * 0.0005)
    if strike_a < 0.07
        strike_a = 0.07
    endif
    if depth_frac > 0
        strike_a = strike_a * (1.0 + depth_frac * randomUniform(-0.5, 0.5))
        if strike_a < 0.03
            strike_a = 0.03
        endif
        if strike_a > 0.22
            strike_a = 0.22
        endif
    endif

    onset_delay_s = randomUniform(0.0, 0.030)
    onset_samples = round(onset_delay_s * internal_rate)

    high_penalty = 0.0
    if midi_note > 72
        high_penalty = (midi_note - 72) * 0.00015
    endif

    loop_gain = 1.0 - (0.0008 + note_idx * 0.00005 + high_penalty)
    if loop_gain > 0.9993
        loop_gain = 0.9993
    endif
    if loop_gain < 0.9000
        loop_gain = 0.9000
    endif

    damp_lp = 0.06 + (note_idx * 0.0015)
    if damp_lp > 0.50
        damp_lp = 0.50
    endif
    if depth_frac > 0
        damp_lp = damp_lp * (1.0 + depth_frac * randomUniform(-0.7, 0.7))
        if damp_lp < 0.01
            damp_lp = 0.01
        endif
        if damp_lp > 0.45
            damp_lp = 0.45
        endif
    endif

    stiff_c = 0.005 + (note_idx * 0.00035)
    if stiff_c > 0.12
        stiff_c = 0.12
    endif
    if depth_frac > 0
        stiff_c = stiff_c * (1.0 + depth_frac * randomUniform(-0.8, 0.8))
        if stiff_c < 0.001
            stiff_c = 0.001
        endif
        if stiff_c > 0.15
            stiff_c = 0.15
        endif
    endif

    damp1 = damp_lp * 1.06
    damp2 = damp_lp
    damp3 = damp_lp * 0.95

    omega_0 = 2.0 * pi * base_freq / internal_rate
    hlp_num_sq = (1.0 - damp_lp) ^ 2.0
    hlp_den_sq = 1.0 - 2.0 * damp_lp * cos(omega_0) + damp_lp ^ 2.0
    hlp_f0 = sqrt(hlp_num_sq / hlp_den_sq)

    coupling_max = 1.0 / hlp_f0 - loop_gain
    if coupling_max < 0
        coupling_max = 0
    endif
    coupling_safety = 0.5
    if depth_frac > 0
        coupling_safety = 0.5 + depth_frac * randomUniform(-0.3, 0.3)
        if coupling_safety < 0.1
            coupling_safety = 0.1
        endif
        if coupling_safety > 0.9
            coupling_safety = 0.9
        endif
    endif
    coupling = coupling_max * coupling_safety
    if coupling > 0.001
        coupling = 0.001
    endif
    if coupling < 0
        coupling = 0
    endif

    contact_time = 0.004 - (voice_vel * 0.002)
    if midi_note > 72
        contact_time = contact_time * (72.0 / midi_note)
    endif

    hammer_amp = (voice_vel ^ 1.5) / 10.0
    bright_pow = 3.0 - (2.0 * voice_vel)

    if depth_frac > 0
        contact_time = contact_time * (1.0 + depth_frac * randomUniform(-0.7, 1.0))
        if contact_time < 0.0005
            contact_time = 0.0005
        endif
        if contact_time > 0.015
            contact_time = 0.015
        endif

        hammer_amp = hammer_amp * (1.0 + depth_frac * randomUniform(-0.7, 1.0))
        if hammer_amp < 0.005
            hammer_amp = 0.005
        endif

        bright_pow = bright_pow * (1.0 + depth_frac * randomUniform(-0.5, 0.5))
        if bright_pow < 0.5
            bright_pow = 0.5
        endif
        if bright_pow > 5.0
            bright_pow = 5.0
        endif
    endif

    pulse_width = round(contact_time * internal_rate)
    if pulse_width < 2
        pulse_width = 2
    endif

    if depth_frac > 0
        appendInfoLine: "  → strike=", fixed$(strike_a, 3),
            ... "  damp=", fixed$(damp_lp, 3),
            ... "  stiff=", fixed$(stiff_c, 4),
            ... "  bright=", fixed$(bright_pow, 2),
            ... "  amp=", fixed$(hammer_amp, 4),
            ... "  ct=", fixed$(contact_time * 1000, 1), "ms"
    endif

    buffer_size = round(internal_rate / 82.0) + 40

    if strings = 1
        f1 = base_freq
        f2 = base_freq
        f3 = base_freq
    elsif strings = 2
        f1 = base_freq - detune * 0.5
        f2 = base_freq + detune * 0.5
        f3 = base_freq + detune * 0.5
    else
        f1 = base_freq - detune
        f2 = base_freq
        f3 = base_freq + detune
    endif

    d1 = (internal_rate / f1) - 0.5
    l_int1 = floor(d1)
    l_frac1 = d1 - l_int1

    d2 = (internal_rate / f2) - 0.5
    l_int2 = floor(d2)
    l_frac2 = d2 - l_int2

    d3 = (internal_rate / f3) - 0.5
    l_int3 = floor(d3)
    l_frac3 = d3 - l_int3

    c1 = (1.0 - l_frac1) / (1.0 + l_frac1)
    c2 = (1.0 - l_frac2) / (1.0 + l_frac2)
    c3 = (1.0 - l_frac3) / (1.0 + l_frac3)

    xs_contact1 = round(strike_a * l_int1)
    if xs_contact1 < 2
        xs_contact1 = 2
    endif
    if xs_contact1 > l_int1 - 4
        xs_contact1 = l_int1 - 4
    endif
    if xs_contact1 < 2
        xs_contact1 = 2
    endif
    xs_pickup1 = l_int1 - xs_contact1
    if xs_pickup1 < 2
        xs_pickup1 = 2
    endif

    xs_contact2 = round(strike_a * l_int2)
    if xs_contact2 < 2
        xs_contact2 = 2
    endif
    if xs_contact2 > l_int2 - 4
        xs_contact2 = l_int2 - 4
    endif
    if xs_contact2 < 2
        xs_contact2 = 2
    endif
    xs_pickup2 = l_int2 - xs_contact2
    if xs_pickup2 < 2
        xs_pickup2 = 2
    endif

    xs_contact3 = round(strike_a * l_int3)
    if xs_contact3 < 2
        xs_contact3 = 2
    endif
    if xs_contact3 > l_int3 - 4
        xs_contact3 = l_int3 - 4
    endif
    if xs_contact3 < 2
        xs_contact3 = 2
    endif
    xs_pickup3 = l_int3 - xs_contact3
    if xs_pickup3 < 2
        xs_pickup3 = 2
    endif

    dl1# = zero#(buffer_size)
    dl2# = zero#(buffer_size)
    dl3# = zero#(buffer_size)
    ptr1 = 1
    ptr2 = 1
    ptr3 = 1

    ap_xp1 = 0.0
    ap_yp1 = 0.0
    lp_p1 = 0.0
    frac_y1 = 0.0

    ap_xp2 = 0.0
    ap_yp2 = 0.0
    lp_p2 = 0.0
    frac_y2 = 0.0

    ap_xp3 = 0.0
    ap_yp3 = 0.0
    lp_p3 = 0.0
    frac_y3 = 0.0

    bridge_prev = 0.0
    temp_dry# = zero#(total_samples)

    for n from 1 to total_samples
        n_rel = n - onset_samples
        if n_rel >= 1 and n_rel <= pulse_width
            phase = pi * n_rel / pulse_width
            s_val = sin(phase)
            if s_val < 0.0
                s_val = 0.0
            endif
            exc_val = hammer_amp * (s_val ^ bright_pow)
        else
            exc_val = 0.0
        endif

        bridge_in = coupling * bridge_prev

        idxA1 = ptr1 - l_int1
        if idxA1 < 1
            idxA1 = idxA1 + buffer_size
        endif
        if idxA1 < 1
            idxA1 = 1
        endif
        idxB1 = idxA1 - 1
        if idxB1 < 1
            idxB1 = idxB1 + buffer_size
        endif
        if idxB1 < 1
            idxB1 = 1
        endif

        d_out1 = c1 * dl1#[idxA1] + dl1#[idxB1] - c1 * frac_y1
        frac_y1 = d_out1
        ap_out1 = stiff_c * d_out1 + ap_xp1 - stiff_c * ap_yp1
        ap_xp1 = d_out1
        ap_yp1 = ap_out1
        lp_out1 = (1.0 - damp1) * ap_out1 + damp1 * lp_p1
        lp_p1 = lp_out1
        dl1#[ptr1] = lp_out1 * loop_gain + bridge_in

        inj1 = ptr1 - xs_contact1
        if inj1 < 1
            inj1 = inj1 + buffer_size
        endif
        if inj1 < 1
            inj1 = 1
        endif
        dl1#[inj1] = dl1#[inj1] + exc_val

        pk1 = ptr1 - xs_pickup1
        if pk1 < 1
            pk1 = pk1 + buffer_size
        endif
        if pk1 < 1
            pk1 = 1
        endif
        pickup1 = dl1#[pk1]
        ptr1 = ptr1 + 1
        if ptr1 > buffer_size
            ptr1 = 1
        endif

        pickup2 = 0.0
        if strings >= 2
            idxA2 = ptr2 - l_int2
            if idxA2 < 1
                idxA2 = idxA2 + buffer_size
            endif
            if idxA2 < 1
                idxA2 = 1
            endif
            idxB2 = idxA2 - 1
            if idxB2 < 1
                idxB2 = idxB2 + buffer_size
            endif
            if idxB2 < 1
                idxB2 = 1
            endif

            d_out2 = c2 * dl2#[idxA2] + dl2#[idxB2] - c2 * frac_y2
            frac_y2 = d_out2
            ap_out2 = stiff_c * d_out2 + ap_xp2 - stiff_c * ap_yp2
            ap_xp2 = d_out2
            ap_yp2 = ap_out2
            lp_out2 = (1.0 - damp2) * ap_out2 + damp2 * lp_p2
            lp_p2 = lp_out2
            dl2#[ptr2] = lp_out2 * loop_gain + bridge_in

            inj2 = ptr2 - xs_contact2
            if inj2 < 1
                inj2 = inj2 + buffer_size
            endif
            if inj2 < 1
                inj2 = 1
            endif
            dl2#[inj2] = dl2#[inj2] + exc_val

            pk2 = ptr2 - xs_pickup2
            if pk2 < 1
                pk2 = pk2 + buffer_size
            endif
            if pk2 < 1
                pk2 = 1
            endif
            pickup2 = dl2#[pk2]
            ptr2 = ptr2 + 1
            if ptr2 > buffer_size
                ptr2 = 1
            endif
        endif

        pickup3 = 0.0
        if strings = 3
            idxA3 = ptr3 - l_int3
            if idxA3 < 1
                idxA3 = idxA3 + buffer_size
            endif
            if idxA3 < 1
                idxA3 = 1
            endif
            idxB3 = idxA3 - 1
            if idxB3 < 1
                idxB3 = idxB3 + buffer_size
            endif
            if idxB3 < 1
                idxB3 = 1
            endif

            d_out3 = c3 * dl3#[idxA3] + dl3#[idxB3] - c3 * frac_y3
            frac_y3 = d_out3
            ap_out3 = stiff_c * d_out3 + ap_xp3 - stiff_c * ap_yp3
            ap_xp3 = d_out3
            ap_yp3 = ap_out3
            lp_out3 = (1.0 - damp3) * ap_out3 + damp3 * lp_p3
            lp_p3 = lp_out3
            dl3#[ptr3] = lp_out3 * loop_gain + bridge_in

            inj3 = ptr3 - xs_contact3
            if inj3 < 1
                inj3 = inj3 + buffer_size
            endif
            if inj3 < 1
                inj3 = 1
            endif
            dl3#[inj3] = dl3#[inj3] + exc_val

            pk3 = ptr3 - xs_pickup3
            if pk3 < 1
                pk3 = pk3 + buffer_size
            endif
            if pk3 < 1
                pk3 = 1
            endif
            pickup3 = dl3#[pk3]
            ptr3 = ptr3 + 1
            if ptr3 > buffer_size
                ptr3 = 1
            endif
        endif

        summed = (pickup1 + pickup2 + pickup3) / strings
        bridge_prev = summed
        temp_dry#[n] = summed
    endfor

    master_dry# = master_dry# + temp_dry#
endfor

master_dry# = master_dry# / 4.0

# =============================================================
# 3. GLOBAL SOUNDBOARD SETUP
# =============================================================
nyq = internal_rate * 0.48

r_b1 = exp(-pi * body_bw1 / internal_rate)
ba1_1 = 2.0 * r_b1 * cos(2.0 * pi * min(body_f1, nyq) / internal_rate)
ba2_1 = -(r_b1 ^ 2.0)
bsc1 = (1.0 - r_b1) * body_g1

r_b2 = exp(-pi * body_bw2 / internal_rate)
ba1_2 = 2.0 * r_b2 * cos(2.0 * pi * min(body_f2, nyq) / internal_rate)
ba2_2 = -(r_b2 ^ 2.0)
bsc2 = (1.0 - r_b2) * body_g2

r_b3 = exp(-pi * body_bw3 / internal_rate)
ba1_3 = 2.0 * r_b3 * cos(2.0 * pi * min(body_f3, nyq) / internal_rate)
ba2_3 = -(r_b3 ^ 2.0)
bsc3 = (1.0 - r_b3) * body_g3

r_b4 = exp(-pi * body_bw4 / internal_rate)
ba1_4 = 2.0 * r_b4 * cos(2.0 * pi * min(body_f4, nyq) / internal_rate)
ba2_4 = -(r_b4 ^ 2.0)
bsc4 = (1.0 - r_b4) * body_g4

r_b5 = exp(-pi * body_bw5 / internal_rate)
ba1_5 = 2.0 * r_b5 * cos(2.0 * pi * min(body_f5, nyq) / internal_rate)
ba2_5 = -(r_b5 ^ 2.0)
bsc5 = (1.0 - r_b5) * body_g5

r_b6 = exp(-pi * body_bw6 / internal_rate)
ba1_6 = 2.0 * r_b6 * cos(2.0 * pi * min(body_f6, nyq) / internal_rate)
ba2_6 = -(r_b6 ^ 2.0)
bsc6 = (1.0 - r_b6) * body_g6

r_b7 = exp(-pi * body_bw7 / internal_rate)
ba1_7 = 2.0 * r_b7 * cos(2.0 * pi * min(body_f7, nyq) / internal_rate)
ba2_7 = -(r_b7 ^ 2.0)
bsc7 = (1.0 - r_b7) * body_g7

r_b8 = exp(-pi * body_bw8 / internal_rate)
ba1_8 = 2.0 * r_b8 * cos(2.0 * pi * min(body_f8, nyq) / internal_rate)
ba2_8 = -(r_b8 ^ 2.0)
bsc8 = (1.0 - r_b8) * body_g8

by1_1 = 0.0
by2_1 = 0.0
by1_2 = 0.0
by2_2 = 0.0
by1_3 = 0.0
by2_3 = 0.0
by1_4 = 0.0
by2_4 = 0.0
by1_5 = 0.0
by2_5 = 0.0
by1_6 = 0.0
by2_6 = 0.0
by1_7 = 0.0
by2_7 = 0.0
by1_8 = 0.0
by2_8 = 0.0

out# = zero#(total_samples)

# =============================================================
# 4. MASTER MIX BUS LOOP
# =============================================================
dc_x_prev = 0.0
dc_y_prev = 0.0
dc_R = 0.995

for n from 1 to total_samples
    raw_summed = master_dry#[n]
    summed = raw_summed - dc_x_prev + dc_R * dc_y_prev
    dc_x_prev = raw_summed
    dc_y_prev = summed

    body1 = bsc1 * summed + ba1_1 * by1_1 + ba2_1 * by2_1
    by2_1 = by1_1
    by1_1 = body1

    body2 = bsc2 * summed + ba1_2 * by1_2 + ba2_2 * by2_2
    by2_2 = by1_2
    by1_2 = body2

    body3 = bsc3 * summed + ba1_3 * by1_3 + ba2_3 * by2_3
    by2_3 = by1_3
    by1_3 = body3

    body4 = bsc4 * summed + ba1_4 * by1_4 + ba2_4 * by2_4
    by2_4 = by1_4
    by1_4 = body4

    body5 = bsc5 * summed + ba1_5 * by1_5 + ba2_5 * by2_5
    by2_5 = by1_5
    by1_5 = body5

    body6 = bsc6 * summed + ba1_6 * by1_6 + ba2_6 * by2_6
    by2_6 = by1_6
    by1_6 = body6

    body7 = bsc7 * summed + ba1_7 * by1_7 + ba2_7 * by2_7
    by2_7 = by1_7
    by1_7 = body7

    body8 = bsc8 * summed + ba1_8 * by1_8 + ba2_8 * by2_8
    by2_8 = by1_8
    by1_8 = body8

    out#[n] = 0.25 * summed + resonance * (body1 + body2 + body3 + body4 + body5 + body6 + body7 + body8)
endfor

# =============================================================
# 5. NORMALIZE & FADE
# =============================================================
peak_val = max(max(out#), -min(out#))
if peak_val > 1.0e-6
    norm_gain = 0.88 / peak_val
else
    norm_gain = 1.0
endif
out# = out# * norm_gain

fade_samples = round(0.06 * internal_rate)
fade_start = total_samples - fade_samples + 1
for n from fade_start to total_samples
    out#[n] = out#[n] * (total_samples - n) / fade_samples
endfor

# =============================================================
# 6. CREATE SOUND, RESAMPLE & SPECTRAL-SPLIT STEREO
# =============================================================
raw_sound_id = Create Sound from formula: "KlangMachineRaw", 1, 0, duration_s, internal_rate, "out#[col]"

if internal_rate <> final_rate
    resampled_id = Resample: final_rate, 50
    selectObject: raw_sound_id
    Remove
else
    resampled_id = raw_sound_id
endif

selectObject: resampled_id
left_id = Copy: "KlangLeft"
Filter (pass Hann band): 20, 3000, 100
left_filtered_id = selected("Sound")
removeObject: left_id
left_id = left_filtered_id

selectObject: resampled_id
right_id = Copy: "KlangRight"
Filter (pass Hann band): 150, high_cutoff_Hz, 100
right_filtered_id = selected("Sound")
removeObject: right_id
right_id = right_filtered_id

selectObject: left_id
plusObject: right_id
final_stereo_id = Combine to stereo
Rename: "Random_Klang_Stereo"
removeObject: resampled_id, left_id, right_id

# =============================================================
# 7. SPECTRAL DECAY REVERB (TRUE STEREO CONVOLUTION)
# =============================================================
original = final_stereo_id
originalName$ = "KlangMachine"
selectObject: original
originalDur = Get total duration
sr = Get sampling frequency

if preset = 2
    tail_duration_s = 1.5
    impulse_duration_s = 2.0
    poisson_density = 1200
    decay_base = 150
    low_cutoff_Hz = 120
    high_cutoff_Hz = 3500
    smoothing_Hz = 80
    fadeout_duration_s = 0.8
    wet_dry_percent = 35
    presetName$ = "Subtle"
elsif preset = 3
    tail_duration_s = 2.0
    impulse_duration_s = 3.0
    poisson_density = 2000
    decay_base = 110
    low_cutoff_Hz = 100
    high_cutoff_Hz = 4000
    smoothing_Hz = 100
    fadeout_duration_s = 1.2
    wet_dry_percent = 50
    presetName$ = "Medium"
elsif preset = 4
    tail_duration_s = 3.0
    impulse_duration_s = 4.5
    poisson_density = 3000
    decay_base = 80
    low_cutoff_Hz = 80
    high_cutoff_Hz = 4500
    smoothing_Hz = 120
    fadeout_duration_s = 1.8
    wet_dry_percent = 65
    presetName$ = "Heavy"
elsif preset = 5
    tail_duration_s = 4.5
    impulse_duration_s = 6.5
    poisson_density = 4500
    decay_base = 50
    low_cutoff_Hz = 60
    high_cutoff_Hz = 5000
    smoothing_Hz = 150
    fadeout_duration_s = 2.5
    wet_dry_percent = 80
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Override reverb params with analysed values when audio was analyzed
# (only for Custom preset or when analysis was active)
if audio_was_analyzed and preset = 1
    presetName$ = "Custom (from audio)"
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

appendInfoLine: "=== Applying True-Stereo Spectral Decay Reverb ==="
appendInfoLine: "Preset: ", presetName$

totalDur = originalDur + tail_duration_s
Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
silentTail = selected("Sound")
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail
decay_str$ = string$(decay_base)

appendInfoLine: "  Convolving left and right channels..."

selectObject: extendedSound
Extract one channel: 1
leftChannel = selected("Sound")
selectObject: extendedSound
Extract one channel: 2
rightChannel = selected("Sound")

Create Poisson process: "poisson_left", 0, impulse_duration_s, poisson_density
poissonLeft = selected("PointProcess")
To Sound (pulse train): sr, 1, 0.035, 2800
irLeft = selected("Sound")
Formula: "self * " + decay_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + 0.7*sin(2*pi*x*150 + (x-xmin)*20))"
selectObject: leftChannel, irLeft
Convolve: "sum", "zero"
convLeft = selected("Sound")
Filter (pass Hann band): low_cutoff_Hz, high_cutoff_Hz, smoothing_Hz
filtLeft = selected("Sound")
removeObject: convLeft

decay_R = decay_base * 0.95
decay_R_str$ = string$(decay_R)
Create Poisson process: "poisson_right", 0, impulse_duration_s * 0.93, poisson_density * 0.95
poissonRight = selected("PointProcess")
To Sound (pulse train): sr, 1, 0.032, 2600
irRight = selected("Sound")
Formula: "self * " + decay_R_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + 0.65*sin(2*pi*x*140 + (x-xmin)*22))"
selectObject: rightChannel, irRight
Convolve: "sum", "zero"
convRight = selected("Sound")
Filter (pass Hann band): low_cutoff_Hz * 1.2, high_cutoff_Hz * 0.95, smoothing_Hz * 0.9
filtRight = selected("Sound")
removeObject: convRight

selectObject: filtLeft
Scale peak: 0.95
selectObject: filtRight
Scale peak: 0.95

wet_str$ = string$(wet_level)
dry_str$ = string$(dry_level)
left_str$ = string$(leftChannel)
right_str$ = string$(rightChannel)

selectObject: filtLeft
Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
selectObject: filtRight
Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$

fade_start = totalDur - fadeout_duration_s
fade_str$ = string$(fadeout_duration_s)
start_str$ = string$(fade_start)

selectObject: filtLeft
wetDur = Get total duration
if wetDur > totalDur
    selectObject: filtLeft
    Extract part: 0, totalDur, "rectangular", 1, "no"
    filtLeftTrim = selected("Sound")
    removeObject: filtLeft
    filtLeft = filtLeftTrim
    selectObject: filtRight
    Extract part: 0, totalDur, "rectangular", 1, "no"
    filtRightTrim = selected("Sound")
    removeObject: filtRight
    filtRight = filtRightTrim
endif

selectObject: filtLeft
Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
Scale peak: 0.98
selectObject: filtRight
Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
Scale peak: 0.98

selectObject: filtLeft, filtRight
Combine to stereo
result = selected("Sound")
Rename: originalName$ + "_spectral_" + presetName$

removeObject: leftChannel, rightChannel, extendedSound
removeObject: poissonLeft, poissonRight, irLeft, irRight
removeObject: filtLeft, filtRight, original

# =============================================================
# 8. VISUALIZATION
# =============================================================
appendInfoLine: "Drawing Visualization..."

procedure midiName: .midi, .result$
    .octave = floor(.midi / 12) - 1
    .pc = .midi mod 12
    if .pc = 0
        .n$ = "C"
    elsif .pc = 1
        .n$ = "C#"
    elsif .pc = 2
        .n$ = "D"
    elsif .pc = 3
        .n$ = "D#"
    elsif .pc = 4
        .n$ = "E"
    elsif .pc = 5
        .n$ = "F"
    elsif .pc = 6
        .n$ = "F#"
    elsif .pc = 7
        .n$ = "G"
    elsif .pc = 8
        .n$ = "G#"
    elsif .pc = 9
        .n$ = "A"
    elsif .pc = 10
        .n$ = "A#"
    else
        .n$ = "B"
    endif
    .result$ = .n$ + string$(.octave)
endproc

@midiName: bass_note, ""
bass_name$ = midiName.result$
@midiName: tenor_note, ""
tenor_name$ = midiName.result$
@midiName: alto_note, ""
alto_name$ = midiName.result$
@midiName: soprano_note, ""
soprano_name$ = midiName.result$

Select outer viewport: 0, 8, 0, 0.55
Font size: 11
Colour: "Black"
if audio_was_analyzed
    Text special: 0.5, "centre", 0.5, "half", "Helvetica", 11, "0",
        ... "##Waveguide Klangmaschine v2.1 — " + presetName$ + " [from audio]##"
else
    Text special: 0.5, "centre", 0.5, "half", "Helvetica", 11, "0",
        ... "##Waveguide Klangmaschine — " + presetName$ + " Reverb##"
endif

Select outer viewport: 0.6, 7.7, 0.6, 5.3
Axes: 0, 100, 0, 100
Solid line

x1 = 15 + ((bass_note - 40) / 15) * 20
x2 = 65 + ((tenor_note - 52) / 12) * 20
y1 = 15 + ((alto_note - 53) / 19) * 20
y2 = 65 + ((soprano_note - 60) / 24) * 20

Paint rectangle: "White", 0, 100, 0, 100
Paint rectangle: "Red", x2, 100, y2, 100
Paint rectangle: "Blue", 0, x1, 0, y1
Paint rectangle: "Yellow", x2, 100, 0, y1

Line width: 8
Colour: "Black"
Draw line: 0, 0, 100, 0
Draw line: 100, 0, 100, 100
Draw line: 100, 100, 0, 100
Draw line: 0, 100, 0, 0

Draw line: x1, 0, x1, 100
Draw line: x2, 0, x2, 100
Draw line: 0, y1, 100, y1
Draw line: 0, y2, 100, y2

Draw line: x1, y2 + 5, x2, y2 + 5
Draw line: x1 - 5, y1, x1 - 5, y2
Line width: 1

Font size: 8
Colour: "White"
Text special: x1 / 2, "centre", y1 / 2, "half",
    ... "Helvetica", 8, "0", "B: " + bass_name$
Colour: "Black"
Text special: (x1 + x2) / 2, "centre", (y1 + y2) / 2, "half",
    ... "Helvetica", 9, "0", "T: " + tenor_name$
Colour: "{0.3,0.3,0.3}"
Text special: x1 / 2, "centre", (y2 + 100) / 2, "half",
    ... "Helvetica", 8, "0", "A: " + alto_name$
Colour: "White"
Text special: (x2 + 100) / 2, "centre", (y2 + 100) / 2, "half",
    ... "Helvetica", 8, "0", "S: " + soprano_name$

Select outer viewport: 0, 8, 5.5, 5.9
Axes: 0, 1, 0, 1
Font size: 6
Colour: "{0.4, 0.4, 0.4}"
Text special: 0.5, "centre", 0.5, "half", "Helvetica", 6, "0",
    ... bass_name$ + " / " + tenor_name$ + " / "
    ... + alto_name$ + " / " + soprano_name$
    ... + "  |  Vel=" + fixed$(velocity, 2)
    ... + "  Strings=" + string$(strings)
    ... + "  Detune=" + fixed$(detune, 1)
    ... + "  Body=" + fixed$(resonance, 2)
    ... + "  |  " + presetName$
    ... + "  |  Rnd: " + depth_name$

Font size: 10
Colour: "Black"

appendInfoLine: "=== Done ==="

selectObject: result
Play
