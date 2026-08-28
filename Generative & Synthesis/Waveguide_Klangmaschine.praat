# ============================================================
# Praat AudioTools - Waveguide_Klangmaschine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4.2 (2026)
#
# Changelog v2.4.2 (2026):
#   - FIX (default internal rate): raised the default 11025 -> 12000 Hz.
#     A single analyzed pitch-track anchor can legitimately transpose the
#     manual soprano range by +6 semitones, reaching MIDI 90 (~1480 Hz);
#     11025 Hz provides fewer than the required 8 samples per waveguide
#     period. 12000 Hz safely covers that analysis path while preserving
#     the temporal-resolution guard.
#   - SAFETY: SATB rate validation now includes the maximum 2.5 Hz
#     multi-string detune when checking the highest possible string.
#
# Changelog v2.4.1 (2026):
#   - SAFETY: added final reverb workload guards after preset/audio-analysis
#     overrides and before tail/IR allocation: extended output <= 30,000,000
#     samples/channel, each IR <= 12,000,000 samples, and expected Poisson
#     events/channel <= 250,000. This prevents accidental custom tail/IR
#     settings from exhausting memory or making convolution impractical.
#
# Changelog v2.4 (2026):
#   - FIX (tuning): compensates the fractional delay for the phase
#     delay of the stiffness allpass and loop low-pass at each target
#     F0. This removes the increasingly flat pitch error of the old
#     fixed -0.5-sample correction, especially in the upper voices.
#   - FIX (audio analysis): a single stable pitch track now transposes
#     the manual SATB ranges to the detected pitch class; the old code
#     suppressed that transposition whenever any Sound was analyzed.
#     The sampled values are described as pitch-track anchors rather
#     than simultaneous multi-pitch detection.
#   - FIX (stereo): final wet+dry normalization is joint after stereo
#     combination; no independent L/R peak scaling remains.
#   - Added reproducible Random seed and explicit validation of rates,
#     transposition, output ceiling, body-mode bandwidth, and waveguide
#     temporal resolution.
#   - Compact main form with optional Reverb / Render Details page.
#   - Visualization rebuilt as process explanation: SATB string geometry
#     -> tuned delay loop -> modelled soundboard transfer ->
#     realized Poisson reverb events -> measured stereo output.
#   - Terminology corrected: the reverb is independent L/R (dual-mono)
#     stereo convolution, not four-IR true-stereo convolution.
#
# Changelog v2.3 (2026):
#   - Internal_rate default raised 5512.5 -> 11025 Hz. The old
#     default put a structural 2.76 kHz Nyquist under the whole
#     instrument (the soundboard's 3200 Hz mode was clamped below
#     its own design frequency; the stereo split filtered content
#     that could not exist). MEASURED: the raise costs +1.1 s on
#     an 8 s render (10.3 -> 11.4 s; 22050 -> 39.3 s, available
#     for patient renders) and adds ~3 dB integrated energy in
#     the newly available 2.8-3.9 kHz band (seeded same-chord
#     comparison) -- concentrated in attack transients and body
#     air; the instrument's own damping keeps it dark by design.
#   - FIX (pitch): the delay-line buffer sized for >= 82 Hz, but
#     analysis constraints and transpose legitimately reach
#     MIDI 28 (41.2 Hz); the index guard then silently FLOORED
#     the read -- low bass notes played at a wrong,
#     buffer-limited pitch. Buffer now covers the true floor.
#   - FIX: clearinfo ran AFTER the audio-analysis pipeline,
#     erasing its entire report (pitches, SATB ranges, HNR,
#     centroid, decay mapping) before it could be read.
#   - FIX: the wet reverb channels were peak-normalized
#     INDEPENDENTLY -- rebalancing the deliberately spectral-split
#     stereo arbitrarily per run. Now scaled jointly.
#   - Draw_visualization / Play_result gates added (house
#     convention; Play was unconditional).
#
# Changelog v2.2 (2025): audio analysis drives reverb (cutoff/wet/decay/tail)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Waveguide Klangmaschine: generates a randomized SATB
#   chord using digital waveguide synthesis with per-string
#   allpass fractional delay, stiffness dispersion, LP damping,
#   and bridge coupling — processed through an 8-mode soundboard
#   resonator bank, spectral-split stereo imaging, and an independent-L/R
#   Poisson-process spectral decay reverb.
#
# v2.1 Audio Analysis Pipeline:
#   If a Sound object is selected before running, the script
#   analyzes it and automatically derives synthesis parameters:
#     - Root pitch / F0    → Transpose_semitones (key center)
#     - Pitch-track anchors → Heuristically constrain SATB note ranges
#     - Duration           → Duration_s
#     - HNR                → Randomize_depth
#     - Spectral centroid  → High_cutoff_Hz + reverb brightness
#     - Decay rate         → Decay_base + Tail_duration_s
#     - RMS / loudness     → velocity + Wet_dry_percent
#     - Envelope shape     → Reverb Preset selection
#   Falls back to manual form values when no Sound is selected.
#
# ============================================================

form Synthesize Random SATB Klang Machine v2.4.2
    comment === Source / Musical Control ===
    boolean Use_selected_sound 1
    real Duration_s 8.0
    integer Transpose_semitones 0

    optionmenu Preset 3
        option Custom
        option Subtle Decay
        option Medium Decay
        option Heavy Decay
        option Extreme Decay

    optionmenu Randomize_depth 2
        option None
        option Subtle
        option Wild

    boolean Edit_reverb_render_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
internal_rate = 12000
final_rate = 44100
tail_duration_s = 2.0
impulse_duration_s = 3.0
poisson_density = 2000
decay_base = 110
low_cutoff_Hz = 100
high_cutoff_Hz = 4000
smoothing_Hz = 100
wet_dry_percent = 50
fadeout_duration_s = 1.2
output_peak = 0.98
random_seed = 0

if edit_reverb_render_details
    beginPause: "Waveguide Klangmaschine v2.4.2 - Reverb / Render Details"
        positive: "Internal waveguide rate (Hz)", internal_rate
        positive: "Final output rate (Hz)", final_rate
        positive: "Tail duration (s)", tail_duration_s
        positive: "Impulse duration (s)", impulse_duration_s
        positive: "Poisson density (events/s)", poisson_density
        positive: "Decay base", decay_base
        positive: "Low cutoff (Hz)", low_cutoff_Hz
        positive: "High cutoff (Hz)", high_cutoff_Hz
        positive: "Filter smoothing (Hz)", smoothing_Hz
        real: "Wet mix (%)", wet_dry_percent
        positive: "Fadeout duration (s)", fadeout_duration_s
        real: "Output peak (0..1)", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# =============================================================
# AUDIO ANALYSIS PIPELINE
# =============================================================

clearinfo
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

        # Represent the detected pitch class as the shortest signed shift
        # away from C. This is used only when the pitch track supplies fewer
        # than two distinct anchors; with >=2 anchors the SATB ranges are
        # already placed in absolute MIDI space and no second shift is needed.
        root_pc = root_midi mod 12
        transpose_semitones = root_pc
        if transpose_semitones > 6
            transpose_semitones = transpose_semitones - 12
        endif
        appendInfoLine: "  Pitch-class shift:", transpose_semitones, " semitones from C reference"

        # Heuristic pitch-track analysis: sample monophonic F0 at 8 time points
        # and collect distinct MIDI anchors for SATB range narrowing. This is
        # NOT simultaneous polyphonic multi-pitch detection.
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
        appendInfoLine: "  Pitch-track anchors: ", p_count

        # If the pitch track supplies multiple anchors, constrain SATB ranges around them.
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

            # Clamp BOTH endpoints to physical SATB ranges.  The old code
            # clamped only the low endpoint at the bottom and the high endpoint
            # at the top; an anchor far outside a voice range could therefore
            # leave lo > hi and the subsequent +1 repair escaped the range.
            bass_lo = max(28, min(59, bass_lo))
            bass_hi = max(29, min(60, bass_hi))
            tenor_lo = max(40, min(68, tenor_lo))
            tenor_hi = max(41, min(69, tenor_hi))
            alto_lo = max(48, min(73, alto_lo))
            alto_hi = max(49, min(74, alto_hi))
            soprano_lo = max(55, min(87, soprano_lo))
            soprano_hi = max(56, min(88, soprano_hi))

            # Guarantee an ordered, non-empty range without leaving the
            # physical voice limits.
            if bass_lo >= bass_hi
                bass_lo = max(28, min(59, p1))
                bass_hi = min(60, bass_lo + 1)
            endif
            if tenor_lo >= tenor_hi
                if p_count >= 3
                    tenor_anchor = p2
                else
                    tenor_anchor = p1
                endif
                tenor_lo = max(40, min(68, tenor_anchor))
                tenor_hi = min(69, tenor_lo + 1)
            endif
            if alto_lo >= alto_hi
                if p_count >= 4
                    alto_anchor = p3
                else
                    alto_anchor = p2
                endif
                alto_lo = max(48, min(73, alto_anchor))
                alto_hi = min(74, alto_lo + 1)
            endif
            if soprano_lo >= soprano_hi
                if p_count >= 4
                    soprano_anchor = p4
                elsif p_count = 3
                    soprano_anchor = p3
                else
                    soprano_anchor = p2
                endif
                soprano_lo = max(55, min(87, soprano_anchor))
                soprano_hi = min(88, soprano_lo + 1)
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
# VALIDATION / REPRODUCIBILITY
# =============================================================
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if internal_rate < 8000 or internal_rate > 96000
    exitScript: "Internal waveguide rate must be between 8000 and 96000 Hz."
endif
if final_rate < 8000 or final_rate > 192000
    exitScript: "Final output rate must be between 8000 and 192000 Hz."
endif
if transpose_semitones < -12 or transpose_semitones > 12
    exitScript: "Transpose must be between -12 and +12 semitones."
endif
if tail_duration_s <= 0 or impulse_duration_s <= 0
    exitScript: "Tail and impulse durations must be positive."
endif
if poisson_density <= 0 or poisson_density > 20000
    exitScript: "Poisson density must be > 0 and <= 20000 events/s."
endif
if decay_base <= 1
    exitScript: "Decay base must be greater than 1."
endif
if smoothing_Hz <= 0
    exitScript: "Filter smoothing must be positive."
endif
if wet_dry_percent < 0 or wet_dry_percent > 100
    exitScript: "Wet mix must be between 0 and 100 percent."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be > 0 and <= 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if fadeout_duration_s <= 0
    exitScript: "Fadeout duration must be positive."
endif

# The manual ranges can reach MIDI 28 with -12 transposition.  Ensure the
# highest possible fundamental still has enough samples per loop for the
# strike / pickup geometry and the phase-compensated delay stages.
if audio_was_analyzed and analysis_pitch_count >= 2
    highest_midi_for_rate = soprano_hi
else
    highest_midi_for_rate = soprano_hi + transpose_semitones
endif
highest_f_for_rate = 440 * (2 ^ ((highest_midi_for_rate - 69) / 12))
# Up to 2.5 Hz detune is added to the outer unison string, so validate
# the highest possible STRING frequency rather than only the MIDI center.
max_string_detune_Hz = 2.5
highest_string_f_for_rate = highest_f_for_rate + max_string_detune_Hz
if internal_rate / highest_string_f_for_rate < 8
    min_rate_needed = ceiling(8 * highest_string_f_for_rate)
    exitScript: "Internal rate is too low for the highest possible SATB string (including detune). Use at least " + string$(min_rate_needed) + " Hz."
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    appendInfoLine: "Random seed:       ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed:       unpredictable"
endif

# Phase-delay compensated first-order fractional delay.  The old fixed
# -0.5-sample correction ignored the phase delay added by the stiffness
# allpass and loop low-pass, so upper notes ran progressively flat.
procedure tunedWaveguideDelay: .freq, .damp, .stiff, .rate
    .omega = 2 * pi * .freq / .rate
    .period = .rate / .freq

    .num_phase = arctan2(-sin(.omega), .stiff + cos(.omega))
    .den_phase = arctan2(-.stiff * sin(.omega), 1 + .stiff * cos(.omega))
    .phase_ap = .num_phase - .den_phase
    if .phase_ap > 0
        .phase_ap = .phase_ap - 2 * pi
    endif
    .pd_stiff = -.phase_ap / .omega

    .pd_lp = arctan2(.damp * sin(.omega), 1 - .damp * cos(.omega)) / .omega
    .remaining = .period - .pd_stiff - .pd_lp
    .l_int = floor(.remaining)
    .target_frac_pd = .remaining - .l_int

    .lo = 0.000000001
    .hi = 0.999999999
    for .iter to 30
        .q = (.lo + .hi) / 2
        .cc = (1 - .q) / (1 + .q)
        .np = arctan2(-sin(.omega), .cc + cos(.omega))
        .dp = arctan2(-.cc * sin(.omega), 1 + .cc * cos(.omega))
        .ph = .np - .dp
        if .ph > 0
            .ph = .ph - 2 * pi
        endif
        .pd = -.ph / .omega
        if .pd < .target_frac_pd
            .lo = .q
        else
            .hi = .q
        endif
    endfor
    .frac = (.lo + .hi) / 2
    .c = (1 - .frac) / (1 + .frac)

    .np = arctan2(-sin(.omega), .c + cos(.omega))
    .dp = arctan2(-.c * sin(.omega), 1 + .c * cos(.omega))
    .ph = .np - .dp
    if .ph > 0
        .ph = .ph - 2 * pi
    endif
    .pd_frac = -.ph / .omega
    .total_pd = .l_int + .pd_frac + .pd_stiff + .pd_lp
    .predicted_f = .rate / .total_pd
    .error_cents = 1200 * log2(.predicted_f / .freq)
endproc

# =============================================================
# 1. GLOBAL SETUP & RANDOMIZED PARAMETERS
# =============================================================
Erase all
appendInfoLine: "KLANG MACHINE v2.4.2: Generating New Patch..."
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
if not audio_was_analyzed and transpose_semitones <> 0
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

# Validate the actual randomized body before constructing filters.  Clamping
# resonances to Nyquist changes the instrument; reject that configuration
# instead of silently moving a mode.
max_body_f = body_f1
if body_f2 > max_body_f
    max_body_f = body_f2
endif
if body_f3 > max_body_f
    max_body_f = body_f3
endif
if body_f4 > max_body_f
    max_body_f = body_f4
endif
if body_f5 > max_body_f
    max_body_f = body_f5
endif
if body_f6 > max_body_f
    max_body_f = body_f6
endif
if body_f7 > max_body_f
    max_body_f = body_f7
endif
if body_f8 > max_body_f
    max_body_f = body_f8
endif
if max_body_f >= 0.45 * internal_rate
    needed_body_rate = ceiling(max_body_f / 0.45)
    exitScript: "Internal rate is too low for the randomized soundboard modes. Use at least " + string$(needed_body_rate) + " Hz for this seed/depth."
endif

# =============================================================
# 2. VOICE LOOP (Generate 4 SATB notes — constrained if analyzed)
# =============================================================
# Parameters retained for process visualization / QC
voice_midi# = zero#(4)
voice_freq# = zero#(4)
voice_velocity# = zero#(4)
voice_onset_ms# = zero#(4)
voice_strike# = zero#(4)
voice_loop_gain# = zero#(4)
voice_damp# = zero#(4)
voice_stiff# = zero#(4)
voice_delay_samples# = zero#(4)
voice_tuning_error_cents# = zero#(4)

for voice from 1 to 4
    # When audio was analyzed, SATB ranges are already centered on detected pitches,
    # so transpose_semitones must not be added again (it would double-apply the shift).
    if audio_was_analyzed and analysis_pitch_count >= 2
        effective_transpose = 0
    else
        effective_transpose = transpose_semitones
    endif

    if voice = 1
        midi_note = randomInteger(bass_lo, bass_hi) + effective_transpose
        bass_note = midi_note
        voice_name$ = "Bass   "
    elsif voice = 2
        midi_note = randomInteger(tenor_lo, tenor_hi) + effective_transpose
        tenor_note = midi_note
        voice_name$ = "Tenor  "
    elsif voice = 3
        midi_note = randomInteger(alto_lo, alto_hi) + effective_transpose
        alto_note = midi_note
        voice_name$ = "Alto   "
    else
        midi_note = randomInteger(soprano_lo, soprano_hi) + effective_transpose
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

    # v2.3: sized for the true bass floor (MIDI 28 = 41.2 Hz is
    # reachable via analysis constraints or transpose; the old
    # /82 sizing made the index guard floor the read -- wrong
    # pitch on low notes)
    buffer_size = round(internal_rate / 38.0) + 40

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

    @tunedWaveguideDelay: f1, damp1, stiff_c, internal_rate
    l_int1 = tunedWaveguideDelay.l_int
    l_frac1 = tunedWaveguideDelay.frac
    c1 = tunedWaveguideDelay.c
    tuning_error1 = tunedWaveguideDelay.error_cents

    @tunedWaveguideDelay: f2, damp2, stiff_c, internal_rate
    l_int2 = tunedWaveguideDelay.l_int
    l_frac2 = tunedWaveguideDelay.frac
    c2 = tunedWaveguideDelay.c
    tuning_error2 = tunedWaveguideDelay.error_cents

    @tunedWaveguideDelay: f3, damp3, stiff_c, internal_rate
    l_int3 = tunedWaveguideDelay.l_int
    l_frac3 = tunedWaveguideDelay.frac
    c3 = tunedWaveguideDelay.c
    tuning_error3 = tunedWaveguideDelay.error_cents

    voice_midi#[voice] = midi_note
    voice_freq#[voice] = base_freq
    voice_velocity#[voice] = voice_vel
    voice_onset_ms#[voice] = onset_delay_s * 1000
    voice_strike#[voice] = strike_a
    voice_loop_gain#[voice] = loop_gain
    voice_damp#[voice] = damp_lp
    voice_stiff#[voice] = stiff_c
    voice_delay_samples#[voice] = l_int1 + l_frac1
    voice_tuning_error_cents#[voice] = tuning_error1

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
peak_val = 0
for n to total_samples
    av = abs(out#[n])
    if av > peak_val
        peak_val = av
    endif
endfor
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
# 7. SPECTRAL DECAY REVERB (INDEPENDENT L/R CONVOLUTION)
# =============================================================
original = final_stereo_id
originalName$ = "KlangMachine"
selectObject: original
originalDur = Get total duration
sr = Get sampling frequency

# Preserve the audio-analysed reverb params (centroid->cutoff, RMS->wet,
# decay->decay_base/tail). The envelope-selected preset below sets ALL reverb
# params; without this, it would silently discard the analysed values. They are
# restored just after the preset block.
if audio_was_analyzed
    an_high_cutoff_Hz = high_cutoff_Hz
    an_wet_dry_percent = wet_dry_percent
    an_decay_base = decay_base
    an_tail_duration_s = tail_duration_s
    an_impulse_duration_s = impulse_duration_s
endif

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

# Restore the audio-analysed reverb params, overriding the envelope preset's
# fixed cutoff/wet/decay/tail (as documented). The preset still supplies the
# remaining reverb settings (density, low cut, smoothing, fadeout) and the
# character name.
if audio_was_analyzed
    high_cutoff_Hz = an_high_cutoff_Hz
    wet_dry_percent = an_wet_dry_percent
    decay_base = an_decay_base
    tail_duration_s = an_tail_duration_s
    impulse_duration_s = an_impulse_duration_s
    presetName$ = presetName$ + " (from audio)"
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
if high_cutoff_Hz >= 0.48 * sr
    exitScript: "Final reverb high cutoff must stay below 48% of the output sample rate."
endif
if low_cutoff_Hz <= 0 or high_cutoff_Hz <= low_cutoff_Hz
    exitScript: "Final reverb cutoff range is invalid."
endif

# Final reverb workload guards. These are evaluated here, after preset and
# audio-analysis overrides, and before allocating the silent tail / IR Sounds.
maxExtendedSamplesPerChannel = 30000000
maxIrSamplesPerChannel = 12000000
maxExpectedPoissonEventsPerChannel = 250000
extendedSamplesPerChannel = round((originalDur + tail_duration_s) * sr)
irSamplesPerChannel = round(impulse_duration_s * sr)
expectedPoissonEventsLeft = impulse_duration_s * poisson_density
expectedPoissonEventsRight = impulse_duration_s * 0.93 * poisson_density * 0.95
maxExpectedPoissonEvents = max(expectedPoissonEventsLeft, expectedPoissonEventsRight)

if extendedSamplesPerChannel > maxExtendedSamplesPerChannel
    maxTailAtRate = max(0, maxExtendedSamplesPerChannel / sr - originalDur)
    exitScript: "Reverb tail workload is too large at the current output rate. Reduce Tail duration or Final output rate. Maximum tail for this render is about " + fixed$(maxTailAtRate, 2) + " s."
endif
if irSamplesPerChannel > maxIrSamplesPerChannel
    maxImpulseAtRate = maxIrSamplesPerChannel / sr
    exitScript: "Reverb impulse workload is too large at the current output rate. Reduce Impulse duration or Final output rate. Maximum impulse duration at this rate is about " + fixed$(maxImpulseAtRate, 2) + " s."
endif
if maxExpectedPoissonEvents > maxExpectedPoissonEventsPerChannel
    maxDensityAtImpulse = maxExpectedPoissonEventsPerChannel / max(0.001, impulse_duration_s)
    exitScript: "Reverb Poisson workload is too large. Reduce Impulse duration or Poisson density. At this impulse duration, density should be about " + fixed$(maxDensityAtImpulse, 0) + " events/s or lower."
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

appendInfoLine: "=== Applying Independent-L/R Spectral Decay Reverb ==="
appendInfoLine: "Preset: ", presetName$

totalDur = originalDur + tail_duration_s
if fadeout_duration_s > totalDur
    fadeout_duration_s = totalDur
endif
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
poisson_left_total = Get number of points
poisson_plot_capacity = 96
poisson_left_plot_count = min(poisson_plot_capacity, poisson_left_total)
poisson_left_plot# = zero#(poisson_plot_capacity)
if poisson_left_plot_count = 1
    poisson_left_plot#[1] = Get time from index: 1
elsif poisson_left_plot_count > 1
    for pk to poisson_left_plot_count
        pidx = round(1 + (pk - 1) * (poisson_left_total - 1) / (poisson_left_plot_count - 1))
        poisson_left_plot#[pk] = Get time from index: pidx
    endfor
endif
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
poisson_right_total = Get number of points
poisson_right_plot_count = min(poisson_plot_capacity, poisson_right_total)
poisson_right_plot# = zero#(poisson_plot_capacity)
if poisson_right_plot_count = 1
    poisson_right_plot#[1] = Get time from index: 1
elsif poisson_right_plot_count > 1
    for pk to poisson_right_plot_count
        pidx = round(1 + (pk - 1) * (poisson_right_total - 1) / (poisson_right_plot_count - 1))
        poisson_right_plot#[pk] = Get time from index: pidx
    endfor
endif
To Sound (pulse train): sr, 1, 0.032, 2600
irRight = selected("Sound")
Formula: "self * " + decay_R_str$ + "^(-(x-xmin)/(xmax-xmin)) * (1 + 0.65*sin(2*pi*x*140 + (x-xmin)*22))"
selectObject: rightChannel, irRight
Convolve: "sum", "zero"
convRight = selected("Sound")
Filter (pass Hann band): low_cutoff_Hz * 1.2, high_cutoff_Hz * 0.95, smoothing_Hz * 0.9
filtRight = selected("Sound")
removeObject: convRight

# v2.4: JOINT wet scaling -- independent per-channel peaks
# rebalanced the deliberately spectral-split stereo
selectObject: filtLeft
wpL = Get absolute extremum: 0, 0, "None"
selectObject: filtRight
wpR = Get absolute extremum: 0, 0, "None"
wpMax = max(wpL, wpR)
if wpMax > 1e-9
    wjs = 0.95 / wpMax
    selectObject: filtLeft
    Formula: "self * wjs"
    selectObject: filtRight
    Formula: "self * wjs"
endif

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
selectObject: filtRight
Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"

selectObject: filtLeft, filtRight
Combine to stereo
result = selected("Sound")
Scale peak: output_peak
Rename: originalName$ + "_spectral_" + presetName$

removeObject: leftChannel, rightChannel, extendedSound
removeObject: poissonLeft, poissonRight, irLeft, irRight
removeObject: filtLeft, filtRight, original

# =============================================================
# 8. VISUALIZATION — PROCESS, NOT JUST RESULT
# =============================================================
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

if draw_visualization
    appendInfoLine: "Drawing process visualization..."
    @midiName: bass_note, ""
    bass_name$ = midiName.result$
    @midiName: tenor_note, ""
    tenor_name$ = midiName.result$
    @midiName: alto_note, ""
    alto_name$ = midiName.result$
    @midiName: soprano_note, ""
    soprano_name$ = midiName.result$

    Erase all

    # Header strip
    Select outer viewport: 0, 8, 0.05, 0.48
    Select inner viewport: 0, 8, 0.05, 0.48
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text special: 0.5, "centre", 0.68, "half", "Helvetica", 11, "0", "##Waveguide Klangmaschine v2.4.2##"
    Font size: 7
    Colour: "{0.35,0.35,0.38}"
    if audio_was_analyzed
        Text: 0.5, "centre", 0.18, "half", presetName$ + " | parameters partly derived from selected audio"
    else
        Text: 0.5, "centre", 0.18, "half", presetName$ + " | stochastic SATB realization"
    endif

    # Process strip
    Select outer viewport: 0.35, 7.65, 0.52, 0.88
    Select inner viewport: 0.35, 7.65, 0.52, 0.88
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.28,0.28,0.31}"
    Text: 0.5, "centre", 0.5, "half", "hammer -> tuned delay -> dispersion/loss -> 8-mode soundboard -> stereo split -> Poisson IR -> output"

    # ---------------------------------------------------------
    # A. SATB STRING REALIZATION / GEOMETRY
    # ---------------------------------------------------------
    Select outer viewport: 0.25, 3.92, 0.98, 3.28
    Select inner viewport: 0.62, 3.75, 1.20, 3.10
    Axes: 0, 1, 0.5, 4.5
    Paint rectangle: "{0.975,0.975,0.975}", 0, 1, 0.5, 4.5
    Colour: "{0.78,0.78,0.78}"
    for vr from 1 to 4
        Draw line: 0.05, vr, 0.95, vr
    endfor

    for vr from 1 to 4
        strike_x = 0.08 + 0.78 * voice_strike#[vr]
        pickup_x = 0.08 + 0.78 * (1 - voice_strike#[vr])
        Colour: "{0.16,0.31,0.52}"
        Line width: 2
        Draw line: 0.08, vr, 0.86, vr
        Line width: 1
        Colour: "{0.75,0.30,0.18}"
        Draw line: strike_x, vr - 0.16, strike_x, vr + 0.16
        Colour: "{0.18,0.52,0.36}"
        Draw line: pickup_x, vr - 0.13, pickup_x, vr + 0.13
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box

    # Re-enter data viewport after box
    Select inner viewport: 0.62, 3.75, 1.20, 3.10
    Axes: 0, 1, 0.5, 4.5
    Font size: 6.4
    Colour: "Black"
    Text: 0.01, "right", 1, "half", "B " + bass_name$ + "  " + fixed$(voice_freq#[1], 1) + "Hz"
    Text: 0.01, "right", 2, "half", "T " + tenor_name$ + "  " + fixed$(voice_freq#[2], 1) + "Hz"
    Text: 0.01, "right", 3, "half", "A " + alto_name$ + "  " + fixed$(voice_freq#[3], 1) + "Hz"
    Text: 0.01, "right", 4, "half", "S " + soprano_name$ + "  " + fixed$(voice_freq#[4], 1) + "Hz"

    # title strip A
    Select outer viewport: 0.25, 3.92, 0.90, 1.16
    Select inner viewport: 0.25, 3.92, 0.90, 1.16
    Axes: 0, 1, 0, 1
    Font size: 7.5
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "A | Four SATB voices: strike position -> tuned loop -> pickup"

    # A-note strip
    Select outer viewport: 0.45, 3.80, 3.12, 3.42
    Select inner viewport: 0.45, 3.80, 3.12, 3.42
    Axes: 0, 1, 0, 1
    Font size: 5.2
    Colour: "{0.35,0.35,0.38}"
    maxTuneErr = 0
    for vr to 4
        if abs(voice_tuning_error_cents#[vr]) > maxTuneErr
            maxTuneErr = abs(voice_tuning_error_cents#[vr])
        endif
    endfor
    Text: 0.5, "centre", 0.70, "half", "red=hammer | green=pickup | strings/note=" + string$(strings) + " | detune=" + fixed$(detune, 2) + " Hz"
    Text: 0.5, "centre", 0.22, "half", "phase-compensated model tuning error <= " + fixed$(maxTuneErr, 3) + " cent"

    # ---------------------------------------------------------
    # B. REPRESENTATIVE WAVEGUIDE LOOP (TENOR)
    # ---------------------------------------------------------
    Select outer viewport: 4.08, 7.75, 0.98, 3.42
    Select inner viewport: 4.30, 7.55, 1.20, 3.12
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975,0.975,0.975}", 0, 1, 0, 1
    Colour: "{0.18,0.18,0.20}"
    Line width: 1.5
    Draw line: 0.08, 0.58, 0.25, 0.58
    Draw line: 0.39, 0.58, 0.50, 0.58
    Draw line: 0.64, 0.58, 0.73, 0.58
    Draw line: 0.86, 0.58, 0.94, 0.58
    Draw line: 0.94, 0.58, 0.94, 0.27
    Draw line: 0.94, 0.27, 0.18, 0.27
    Draw line: 0.18, 0.27, 0.18, 0.49
    Line width: 1

    Colour: "{0.82,0.90,0.97}"
    Paint rectangle: "{0.82,0.90,0.97}", 0.25, 0.39, 0.48, 0.68
    Colour: "{0.91,0.86,0.96}"
    Paint rectangle: "{0.91,0.86,0.96}", 0.50, 0.64, 0.48, 0.68
    Colour: "{0.88,0.94,0.86}"
    Paint rectangle: "{0.88,0.94,0.86}", 0.73, 0.86, 0.48, 0.68
    Colour: "Black"
    Draw rectangle: 0.25, 0.39, 0.48, 0.68
    Draw rectangle: 0.50, 0.64, 0.48, 0.68
    Draw rectangle: 0.73, 0.86, 0.48, 0.68
    Font size: 5.7
    Text: 0.08, "centre", 0.66, "half", "hammer"
    Text: 0.32, "centre", 0.58, "half", "integer +"
    Text: 0.32, "centre", 0.52, "half", "frac delay"
    Text: 0.57, "centre", 0.58, "half", "stiffness"
    Text: 0.57, "centre", 0.52, "half", "allpass"
    Text: 0.795, "centre", 0.58, "half", "loss LP"
    Text: 0.56, "centre", 0.20, "half", "feedback + bridge coupling"

    tenor_period = internal_rate / voice_freq#[2]
    Font size: 5.3
    Colour: "{0.30,0.30,0.33}"
    Text: 0.5, "centre", 0.12, "half", tenor_name$ + ": target=" + fixed$(tenor_period, 3) + " samp | core=" + fixed$(voice_delay_samples#[2], 3) + " samp"
    Text: 0.5, "centre", 0.035, "half", "damp=" + fixed$(voice_damp#[2], 3) + " | stiff=" + fixed$(voice_stiff#[2], 4) + " | feedback=" + fixed$(voice_loop_gain#[2], 5)

    Select outer viewport: 4.08, 7.75, 0.90, 1.16
    Select inner viewport: 4.08, 7.75, 0.90, 1.16
    Axes: 0, 1, 0, 1
    Font size: 7.5
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "B | Phase-compensated digital waveguide loop"

    # ---------------------------------------------------------
    # C. SOUNDBOARD TRANSFER MODEL
    # ---------------------------------------------------------
    Select outer viewport: 0.25, 7.75, 3.55, 5.68
    Select inner viewport: 0.72, 7.52, 3.80, 5.43
    fPlotMin = 40
    fPlotMax = min(5000, 0.45 * internal_rate)
    xLogMin = ln(fPlotMin)
    xLogMax = ln(fPlotMax)
    Axes: xLogMin, xLogMax, -36, 2
    Paint rectangle: "{0.985,0.985,0.985}", xLogMin, xLogMax, -36, 2

    # Find normalization of the exact eight-resonator transfer function.
    respMax = 0.000000001
    for qi from 0 to 220
        qf = exp(xLogMin + (xLogMax - xLogMin) * qi / 220)
        qw = 2 * pi * qf / internal_rate
        c1w = cos(qw)
        s1w = sin(qw)
        c2w = cos(2 * qw)
        s2w = sin(2 * qw)
        sumRe = 0.25
        sumIm = 0
        for mode to 8
            if mode = 1
                aa1 = ba1_1
                aa2 = ba2_1
                bb = bsc1
            elsif mode = 2
                aa1 = ba1_2
                aa2 = ba2_2
                bb = bsc2
            elsif mode = 3
                aa1 = ba1_3
                aa2 = ba2_3
                bb = bsc3
            elsif mode = 4
                aa1 = ba1_4
                aa2 = ba2_4
                bb = bsc4
            elsif mode = 5
                aa1 = ba1_5
                aa2 = ba2_5
                bb = bsc5
            elsif mode = 6
                aa1 = ba1_6
                aa2 = ba2_6
                bb = bsc6
            elsif mode = 7
                aa1 = ba1_7
                aa2 = ba2_7
                bb = bsc7
            else
                aa1 = ba1_8
                aa2 = ba2_8
                bb = bsc8
            endif
            denRe = 1 - aa1 * c1w - aa2 * c2w
            denIm = aa1 * s1w + aa2 * s2w
            denSq = denRe * denRe + denIm * denIm
            sumRe = sumRe + resonance * bb * denRe / denSq
            sumIm = sumIm - resonance * bb * denIm / denSq
        endfor
        mag = sqrt(sumRe * sumRe + sumIm * sumIm)
        if mag > respMax
            respMax = mag
        endif
    endfor

    prevX = xLogMin
    prevY = -36
    Colour: "{0.16,0.31,0.52}"
    Line width: 1.5
    for qi from 0 to 220
        qf = exp(xLogMin + (xLogMax - xLogMin) * qi / 220)
        qw = 2 * pi * qf / internal_rate
        c1w = cos(qw)
        s1w = sin(qw)
        c2w = cos(2 * qw)
        s2w = sin(2 * qw)
        sumRe = 0.25
        sumIm = 0
        for mode to 8
            if mode = 1
                aa1 = ba1_1
                aa2 = ba2_1
                bb = bsc1
            elsif mode = 2
                aa1 = ba1_2
                aa2 = ba2_2
                bb = bsc2
            elsif mode = 3
                aa1 = ba1_3
                aa2 = ba2_3
                bb = bsc3
            elsif mode = 4
                aa1 = ba1_4
                aa2 = ba2_4
                bb = bsc4
            elsif mode = 5
                aa1 = ba1_5
                aa2 = ba2_5
                bb = bsc5
            elsif mode = 6
                aa1 = ba1_6
                aa2 = ba2_6
                bb = bsc6
            elsif mode = 7
                aa1 = ba1_7
                aa2 = ba2_7
                bb = bsc7
            else
                aa1 = ba1_8
                aa2 = ba2_8
                bb = bsc8
            endif
            denRe = 1 - aa1 * c1w - aa2 * c2w
            denIm = aa1 * s1w + aa2 * s2w
            denSq = denRe * denRe + denIm * denIm
            sumRe = sumRe + resonance * bb * denRe / denSq
            sumIm = sumIm - resonance * bb * denIm / denSq
        endfor
        mag = sqrt(sumRe * sumRe + sumIm * sumIm)
        ydb = 20 * log10(max(0.000000001, mag / respMax))
        if ydb < -36
            ydb = -36
        endif
        xx = ln(qf)
        if qi > 0
            Draw line: prevX, prevY, xx, ydb
        endif
        prevX = xx
        prevY = ydb
    endfor
    Line width: 1

    # Mark actual randomized modes.
    Colour: "{0.70,0.30,0.18}"
    modeFreq# = zero#(8)
    modeFreq#[1] = body_f1
    modeFreq#[2] = body_f2
    modeFreq#[3] = body_f3
    modeFreq#[4] = body_f4
    modeFreq#[5] = body_f5
    modeFreq#[6] = body_f6
    modeFreq#[7] = body_f7
    modeFreq#[8] = body_f8
    for mode to 8
        if modeFreq#[mode] >= fPlotMin and modeFreq#[mode] <= fPlotMax
            mx = ln(modeFreq#[mode])
            Draw line: mx, -36, mx, -31
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    # custom log ticks
    Select inner viewport: 0.72, 7.52, 3.80, 5.43
    Axes: xLogMin, xLogMax, -36, 2
    Font size: 5.8
    tickF# = zero#(7)
    tickF#[1] = 50
    tickF#[2] = 100
    tickF#[3] = 200
    tickF#[4] = 500
    tickF#[5] = 1000
    tickF#[6] = 2000
    tickF#[7] = 5000
    for tk to 7
        tf = tickF#[tk]
        if tf >= fPlotMin and tf <= fPlotMax
            tx = ln(tf)
            Colour: "{0.72,0.72,0.72}"
            Draw line: tx, -36, tx, -34.5
            Colour: "Black"
            if tf >= 1000
                Text: tx, "centre", -38.2, "half", fixed$(tf/1000, 0) + "k"
            else
                Text: tx, "centre", -38.2, "half", string$(tf)
            endif
        endif
    endfor

    Select outer viewport: 0.25, 7.75, 3.47, 3.75
    Select inner viewport: 0.25, 7.75, 3.47, 3.75
    Axes: 0, 1, 0, 1
    Font size: 7.5
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "C | Exact 8-mode soundboard transfer model (normalized dB)"

    # ---------------------------------------------------------
    # D. REALIZED POISSON REVERB + MEASURED OUTPUT
    # ---------------------------------------------------------
    Select outer viewport: 0.25, 3.92, 5.86, 7.62
    Select inner viewport: 0.62, 3.72, 6.12, 7.38
    reverbPlotDur = impulse_duration_s
    Axes: 0, reverbPlotDur, 0, 1.05
    Paint rectangle: "{0.985,0.985,0.985}", 0, reverbPlotDur, 0, 1.05
    # decay reference
    Colour: "{0.45,0.45,0.48}"
    prevT=0
    prevEnv=1
    for qq from 1 to 100
        tt = reverbPlotDur * qq / 100
        env = decay_base ^ (-tt / reverbPlotDur)
        Draw line: prevT, prevEnv, tt, env
        prevT=tt
        prevEnv=env
    endfor
    # actual left Poisson events (decimated only for display)
    Colour: "{0.16,0.31,0.52}"
    for pk to poisson_left_plot_count
        tt = poisson_left_plot#[pk]
        env = decay_base ^ (-tt / reverbPlotDur)
        Draw line: tt, 0, tt, env
    endfor
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, max(0.25, reverbPlotDur/4), "yes", "yes", "no"

    Select outer viewport: 0.25, 3.92, 5.78, 6.06
    Select inner viewport: 0.25, 3.92, 5.78, 6.06
    Axes: 0,1,0,1
    Font size: 7.5
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "D | Realized Poisson decay IR (L; sampled events)"

    Select outer viewport: 0.45, 3.82, 7.38, 7.72
    Select inner viewport: 0.45, 3.82, 7.38, 7.72
    Axes: 0,1,0,1
    Font size: 5.2
    Colour: "{0.35,0.35,0.38}"
    Text: 0.5, "centre", 0.70, "half", "realized: L=" + string$(poisson_left_total) + " | R=" + string$(poisson_right_total) + " events"
    Text: 0.5, "centre", 0.22, "half", "target=" + fixed$(poisson_density,0) + "/s | decay base=" + fixed$(decay_base,0) + " | wet=" + fixed$(wet_dry_percent,0) + "%"

    # Measured stereo output, same amplitude scale.
    selectObject: result
    outputPeakMeasured = Get absolute extremum: 0, 0, "None"
    outputRmsMeasured = Get root-mean-square: 0, 0
    Extract one channel: 1
    vizLeft = selected("Sound")
    selectObject: result
    Extract one channel: 2
    vizRight = selected("Sound")

    Select outer viewport: 4.08, 7.75, 5.86, 7.62
    Select inner viewport: 4.36, 7.55, 6.08, 6.66
    selectObject: vizLeft
    Draw: 0, 0, -1, 1, "no", "curve"
    Select inner viewport: 4.36, 7.55, 6.80, 7.38
    selectObject: vizRight
    Draw: 0, 0, -1, 1, "no", "curve"

    Select outer viewport: 4.08, 7.75, 5.78, 6.06
    Select inner viewport: 4.08, 7.75, 5.78, 6.06
    Axes: 0,1,0,1
    Font size: 7.5
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "E | Measured stereo output (L / R, same -1..1 scale)"

    Select outer viewport: 4.20, 7.65, 7.40, 7.72
    Select inner viewport: 4.20, 7.65, 7.40, 7.72
    Axes: 0,1,0,1
    Font size: 5.2
    Colour: "{0.35,0.35,0.38}"
    Text: 0.5, "centre", 0.70, "half", "peak=" + fixed$(outputPeakMeasured,3) + " | RMS=" + fixed$(outputRmsMeasured,4) + " | " + fixed$(final_rate,0) + " Hz"
    Text: 0.5, "centre", 0.22, "half", "wet + dry stereo normalized jointly after channel combination"

    removeObject: vizLeft, vizRight

    # QC bar: six short fields, independent viewport.
    Select outer viewport: 0.25, 7.75, 7.78, 8.32
    Select inner viewport: 0.25, 7.75, 7.78, 8.32
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.965,0.965,0.965}", 0,3,0,2
    Font size: 5.6
    Colour: "{0.25,0.25,0.28}"
    seedText$ = "random"
    if random_seed > 0
        seedText$ = string$(random_seed)
    endif
    Text: 0.08, "left", 1.48, "half", "Chord: " + bass_name$ + " " + tenor_name$ + " " + alto_name$ + " " + soprano_name$
    Text: 1.08, "left", 1.48, "half", "Loop: " + fixed$(internal_rate,0) + " Hz | err<=" + fixed$(maxTuneErr,3) + "c"
    Text: 2.08, "left", 1.48, "half", "Body: 8 modes | amount=" + fixed$(resonance,2)
    Text: 0.08, "left", 0.50, "half", "Reverb: " + presetName$ + " | " + fixed$(wet_dry_percent,0) + "% wet"
    Text: 1.08, "left", 0.50, "half", "Stereo: split + independent L/R IR"
    Text: 2.08, "left", 0.50, "half", "Seed: " + seedText$ + " | peak=" + fixed$(outputPeakMeasured,3)

    Colour: "Black"
    Font size: 10
    selectObject: result
endif

appendInfoLine: "=== Done ==="

if play_result
    selectObject: result
    Play
endif
selectObject: result
