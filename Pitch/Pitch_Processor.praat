# ============================================================
# Praat AudioTools - Pitch_Processor.praat
# Author: Shai Cohen (Enhanced by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script with two modes:
#   1. Stereo Pitch Detune: stereo spread from a pitch difference
#   2. Time-Delayed Canon: multi-voice canon with a pitch pattern
#
#   Pitch-shift methods:
#   - PSOLA: duration-preserving PitchTier scaling + overlap-add
#   - Varispeed: sample-rate override + resampling (tape transposition)
#   - Positive semitones raise pitch; negative semitones lower pitch
#
# New in v2.1:
#   - The form is six rows: mode, detune preset, canon preset, a settings
#     switch and the draw/play toggles. Every radio-button "choice" block
#     became a single-row "optionmenu", which removed about 25 rows.
#   - All parameters moved out of the form into two optional dialogs that
#     only appear if you ask for them, and only show the fields that apply
#     to the chosen mode. They open pre-filled with whatever the preset just
#     set, so a preset stays inspectable rather than becoming a black box.
#       "Run the preset as it is"           - no dialog, straight to render
#       "Edit main settings"                - the mode's own parameters
#       "Edit main and advanced settings"   - plus output and analysis
#
# New in v2.0:
#   PRESETS
#   - Split into two mode-specific preset menus (5 detune + 8 canon).
#   - Canon presets can carry an explicit semitone PATTERN, not just a step,
#     so chord shapes (0 4 7 11) are first-class instead of special-cased.
#   OPTIONS
#   - Detune balance: right-channel-only (legacy) or symmetric split.
#   - Detune method selectable: PSOLA or varispeed.
#   - Haas (precedence) delay between the two channels.
#   - Free semitone list for the canon ("0 3 7 10 14"), overrides the step rule.
#   - Canon spatialisation: mono, constant-power stereo spread, alternating L-R.
#   - Humanize: per-voice cent and timing jitter with a reproducible seed.
#   - Fade in/out, user peak ceiling, spectrogram range, analysis floor/ceiling.
#   - Secondary "More options" dialog keeps the main form short and shows the
#     values a preset just applied instead of hiding them.
#   VISUALIZATION
#   - Rebuilt on the AudioTools 8-inch grid: title, original, result,
#     dual spectrograms, an analysis panel, a structure panel, and a summary.
#   - Mode 1 analysis panel now draws the MEASURED F0 of both output channels
#     against each other, replacing the schematic rectangles.
#   - Mode 2 structure panel names every interval and shows the wrapped and
#     unwrapped pitch ladder.
#   - Waveform panels share one explicit amplitude range, so the original and
#     the result are directly comparable rather than independently autoscaled.
#   CORRECTNESS
#   - PSOLA is skipped with a warning when the source has no voiced frames
#     (previously it silently returned an unshifted copy).
#   - Peak safety is attenuate-only against a user ceiling; quiet material is
#     never boosted, and the achieved peak is reported.
#   - Object names are sanitized before reaching the Picture window, so a
#     source called "my_take#2" no longer renders as subscript and bold.
# ============================================================

form Pitch Processor v2.1
    optionmenu Mode: 1
        option Stereo Pitch Detune
        option Time-Delayed Canon
    optionmenu Detune_preset: 3
        option Custom
        option Subtle chorus
        option Classic detune
        option Wide doubler
        option Honky-tonk
        option Extreme split
    optionmenu Canon_preset: 1
        option Custom
        option Major arpeggio (fast)
        option Minor arpeggio
        option Spooky cluster (slow)
        option Octave stacks
        option Quartal stack
        option Whole-tone cloud
        option Descending canon
        option Shepard spiral
    optionmenu Settings: 1
        option Run the preset as it is
        option Edit main settings
        option Edit main and advanced settings
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# ============================================================
# DEFAULT PARAMETER SET
# The form carries only the mode, the preset and three switches, so every
# parameter lives here. A preset overwrites what it cares about, and the
# optional dialogs below then show the result, pre-filled and editable.
# ============================================================
stereo_detune_semitones = 1.65
detune_balance = 1
number_of_voices = 4
delay_between_entries = 0.5
semitone_step = 7
wrap_to_octave = 1
semitone_list$ = ""
start_intensity_dB = 70
intensity_step_dB = -3
canon_spatialisation = 1
output_sample_rate = 44100
detune_method = 1
haas_delay_ms = 0
pitch_floor_Hz = 40
pitch_ceiling_Hz = 1200
humanize_cents = 0
humanize_timing_ms = 0
random_seed = 20260829
fade_ms = 10
peak_ceiling = 0.99
resample_precision = 50
spectrogram_max_Hz = 5000

# ============================================================
# PRESETS
# Each preset writes the ordinary form variables, so whatever it sets
# is visible and editable in the More options dialog.
# ============================================================
preset_pattern$ = ""

if mode = 1
    if detune_preset = 2
        stereo_detune_semitones = 0.10
        detune_balance = 2
        haas_delay_ms = 0
        presetName$ = "SubtleChorus"
    elsif detune_preset = 3
        stereo_detune_semitones = 1.65
        detune_balance = 1
        haas_delay_ms = 0
        presetName$ = "ClassicDetune"
    elsif detune_preset = 4
        stereo_detune_semitones = 3.00
        detune_balance = 2
        haas_delay_ms = 14
        presetName$ = "WideDoubler"
    elsif detune_preset = 5
        stereo_detune_semitones = 0.50
        detune_balance = 2
        haas_delay_ms = 0
        presetName$ = "HonkyTonk"
    elsif detune_preset = 6
        stereo_detune_semitones = 7.00
        detune_balance = 2
        haas_delay_ms = 22
        presetName$ = "ExtremeSplit"
    else
        presetName$ = "Custom"
    endif
else
    if canon_preset = 2
        number_of_voices = 4
        delay_between_entries = 0.25
        preset_pattern$ = "0 4 7 11"
        intensity_step_dB = -2
        presetName$ = "MajorArpeggio"
    elsif canon_preset = 3
        number_of_voices = 4
        delay_between_entries = 0.30
        preset_pattern$ = "0 3 7 10"
        intensity_step_dB = -2
        presetName$ = "MinorArpeggio"
    elsif canon_preset = 4
        number_of_voices = 5
        delay_between_entries = 1.20
        semitone_step = 1
        wrap_to_octave = 0
        intensity_step_dB = -1
        presetName$ = "SpookyCluster"
    elsif canon_preset = 5
        number_of_voices = 3
        delay_between_entries = 0.50
        semitone_step = 12
        wrap_to_octave = 0
        intensity_step_dB = -2
        presetName$ = "OctaveStacks"
    elsif canon_preset = 6
        number_of_voices = 4
        delay_between_entries = 0.40
        semitone_step = 5
        wrap_to_octave = 0
        intensity_step_dB = -2
        presetName$ = "QuartalStack"
    elsif canon_preset = 7
        number_of_voices = 6
        delay_between_entries = 0.70
        semitone_step = 2
        wrap_to_octave = 0
        intensity_step_dB = -1.5
        presetName$ = "WholeToneCloud"
    elsif canon_preset = 8
        number_of_voices = 4
        delay_between_entries = 0.45
        semitone_step = -3
        wrap_to_octave = 0
        intensity_step_dB = -2
        presetName$ = "DescendingCanon"
    elsif canon_preset = 9
        number_of_voices = 8
        delay_between_entries = 0.35
        semitone_step = 7
        wrap_to_octave = 1
        intensity_step_dB = -1.5
        canon_spatialisation = 2
        presetName$ = "ShepardSpiral"
    else
        presetName$ = "Custom"
    endif
endif

# ============================================================
# OPTIONAL DIALOGS
# Only the fields that apply to the chosen mode are shown, so neither
# dialog is longer than the main form used to be.
# ============================================================
if settings >= 2
    if mode = 1
        beginPause: "Detune settings - " + presetName$
            real: "Stereo_detune_semitones", string$ (stereo_detune_semitones)
            optionMenu: "Detune_balance", detune_balance
                option: "Right channel only"
                option: "Symmetric split"
            optionMenu: "Detune_method", detune_method
                option: "PSOLA (duration preserving)"
                option: "Varispeed (tape transposition)"
            real: "Haas_delay_ms", string$ (haas_delay_ms)
            comment: "Haas: positive delays the right channel, negative the left"
        endPause: "Continue", 1
    else
        beginPause: "Canon settings - " + presetName$
            natural: "Number_of_voices", string$ (number_of_voices)
            positive: "Delay_between_entries", string$ (delay_between_entries)
            integer: "Semitone_step", string$ (semitone_step)
            boolean: "Wrap_to_octave", wrap_to_octave
            sentence: "Semitone_list", semitone_list$
            comment: "A list such as 0 4 7 11 overrides the step and voice count"
            real: "Start_intensity_dB", string$ (start_intensity_dB)
            real: "Intensity_step_dB", string$ (intensity_step_dB)
            optionMenu: "Canon_spatialisation", canon_spatialisation
                option: "Mono"
                option: "Stereo spread"
                option: "Alternating L-R"
        endPause: "Continue", 1
    endif
endif

if settings >= 3
    beginPause: "Advanced settings"
        positive: "Output_sample_rate", string$ (output_sample_rate)
        real: "Fade_ms", string$ (fade_ms)
        positive: "Peak_ceiling", string$ (peak_ceiling)
        positive: "Pitch_floor_Hz", string$ (pitch_floor_Hz)
        positive: "Pitch_ceiling_Hz", string$ (pitch_ceiling_Hz)
        positive: "Resample_precision", string$ (resample_precision)
        positive: "Spectrogram_max_Hz", string$ (spectrogram_max_Hz)
        if mode = 2
            real: "Humanize_cents", string$ (humanize_cents)
            real: "Humanize_timing_ms", string$ (humanize_timing_ms)
            integer: "Random_seed", string$ (random_seed)
        endif
    endPause: "Continue", 1
endif

# ============================================================
# VALIDATION
# ============================================================
if output_sample_rate < 8000 or output_sample_rate > 384000
    exitScript: "Output_sample_rate must be between 8000 and 384000 Hz."
endif
if resample_precision < 1 or resample_precision > 1000
    exitScript: "Resample_precision must be between 1 and 1000."
endif
if peak_ceiling <= 0 or peak_ceiling > 1
    exitScript: "Peak_ceiling must be greater than 0 and at most 1."
endif
if fade_ms < 0
    exitScript: "Fade_ms cannot be negative."
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch_ceiling_Hz must be greater than Pitch_floor_Hz."
endif
if abs (haas_delay_ms) > 200
    exitScript: "Haas_delay_ms is limited to 200 ms in either direction."
endif

orig$ = selected$ ("Sound")
id_original = selected ("Sound")
id_final_output = 0
safety_applied = 0
warning$ = ""

selectObject: id_original
source_xmin = Get start time
source_xmax = Get end time
original_duration = source_xmax - source_xmin
original_rate = Get sampling frequency
original_channels = Get number of channels

if original_duration <= 0
    exitScript: "The selected Sound has no positive duration."
endif

nyquist = original_rate / 2
if pitch_ceiling_Hz > 0.45 * original_rate
    pitch_ceiling_Hz = 0.45 * original_rate
    warning$ = warning$ + "Pitch ceiling clamped to " + fixed$ (pitch_ceiling_Hz, 1) + " Hz. "
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Source sampling rate is too low for the requested pitch analysis range."
endif
if spectrogram_max_Hz > nyquist
    spectrogram_max_Hz = nyquist
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

# ------------------------------------------------------------
# Build the canon pitch pattern before any rendering, so voice
# count and validation are settled up front.
# ------------------------------------------------------------
voice_st# = zero# (64)
n_voices = 0
pattern_source$ = ""

if mode = 2
    if length (semitone_list$) > 0
        @parseList: semitone_list$
        pattern_source$ = "user list"
    elsif length (preset_pattern$) > 0
        @parseList: preset_pattern$
        pattern_source$ = "preset pattern"
    else
        parse_n = 0
    endif

    if parse_n > 0
        n_voices = parse_n
        for v from 1 to n_voices
            voice_st# [v] = parse_v# [v]
        endfor
    else
        n_voices = number_of_voices
        pattern_source$ = "step rule"
        for v from 1 to n_voices
            s = (v - 1) * semitone_step
            if wrap_to_octave
                s = s - 12 * floor (s / 12)
            endif
            voice_st# [v] = s
        endfor
    endif

    if n_voices < 1
        exitScript: "The canon needs at least one voice."
    endif
    if n_voices > 32
        exitScript: "Number of voices is limited to 32 for safe rendering."
    endif
endif

# ============================================================
# SOURCE PREPARATION
# Zero-based mono working copy, so non-zero xmin and multichannel
# input behave identically downstream.
# ============================================================
selectObject: id_original
if original_channels > 1
    tmp_mono = Convert to mono
    selectObject: tmp_mono
    source_work = Extract part: source_xmin, source_xmax, "rectangular", 1, "no"
    Rename: "PP_source_work"
    removeObject: tmp_mono
else
    source_work = Extract part: source_xmin, source_xmax, "rectangular", 1, "no"
    Rename: "PP_source_work"
endif

clearinfo
writeInfoLine: "=== Pitch Processor v2.1 ==="
if mode = 1
    appendInfoLine: "Mode: Stereo Pitch Detune"
    appendInfoLine: "Preset: ", presetName$
else
    appendInfoLine: "Mode: Time-Delayed Canon"
    appendInfoLine: "Preset: ", presetName$
endif
appendInfoLine: "Source: ", orig$, "  (", fixed$ (original_duration, 3), " s, ",
    ... original_channels, " ch, ", fixed$ (original_rate, 0), " Hz)"
appendInfoLine: "Source domain: ", fixed$ (source_xmin, 6), " ... ", fixed$ (source_xmax, 6), " s"
appendInfoLine: ""

# ------------------------------------------------------------
# Source F0, used by the report and by the visualization
# ------------------------------------------------------------
meanPitch = 0
voicedFraction = 0
selectObject: source_work
if original_duration >= 3 / pitch_floor_Hz
    To Pitch: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
    pitchObj = selected ("Pitch")
    meanPitch = Get mean: 0, 0, "Hertz"
    if meanPitch = undefined
        meanPitch = 0
    endif
    nFrames = Get number of frames
    nVoiced = Count voiced frames
    if nFrames > 0
        voicedFraction = nVoiced / nFrames
    endif
    removeObject: pitchObj
else
    warning$ = warning$ + "Source too short for pitch analysis. "
endif

appendInfoLine: "Source mean F0: ", fixed$ (meanPitch, 1), " Hz"
appendInfoLine: "Voiced frames: ", fixed$ (100 * voicedFraction, 1), " percent"
appendInfoLine: ""

# PSOLA needs voiced material and a long enough window.
psola_possible = 1
if voicedFraction <= 0
    psola_possible = 0
endif
if original_duration < 3 / pitch_floor_Hz
    psola_possible = 0
endif

# ============================================================
# MODE 1: STEREO PITCH DETUNE
# ============================================================
if mode = 1
    if detune_balance = 2
        balance$ = "symmetric split"
        shift_L = -stereo_detune_semitones / 2
        shift_R = stereo_detune_semitones / 2
    else
        balance$ = "right channel only"
        shift_L = 0
        shift_R = stereo_detune_semitones
    endif

    if detune_method = 1 and psola_possible = 0
        detune_method = 2
        warning$ = warning$ + "No voiced frames: PSOLA fell back to varispeed. "
    endif

    if detune_method = 1
        method$ = "PSOLA (duration preserving)"
    else
        method$ = "Varispeed (tape transposition)"
    endif

    appendInfoLine: "Creating stereo detune..."
    appendInfoLine: "  Interval between channels: ", fixed$ (stereo_detune_semitones, 2), " ST"
    appendInfoLine: "  Left channel:  ", fixed$ (shift_L, 3), " ST"
    appendInfoLine: "  Right channel: ", fixed$ (shift_R, 3), " ST"
    appendInfoLine: "  Method: ", method$
    appendInfoLine: "  Ratio L/R: ", fixed$ (2 ^ (shift_L / 12), 5), " / ", fixed$ (2 ^ (shift_R / 12), 5)

    @makeShifted: shift_L
    left_id = shifted_id
    selectObject: left_id
    Rename: "PP_detune_left"

    @makeShifted: shift_R
    right_id = shifted_id
    selectObject: right_id
    Rename: "PP_detune_right"

    # Haas / precedence delay
    if haas_delay_ms > 0.0001
        @prependSilence: right_id, haas_delay_ms / 1000
        right_id = res_id
    elsif haas_delay_ms < -0.0001
        @prependSilence: left_id, -haas_delay_ms / 1000
        left_id = res_id
    endif

    selectObject: left_id
    dur_left = Get total duration
    selectObject: right_id
    dur_right = Get total duration
    final_duration = max (dur_left, dur_right)

    @padToLength: left_id, final_duration
    left_id = res_id
    @padToLength: right_id, final_duration
    right_id = res_id

    # Ordered copies, so Combine to stereo sees L before R in the object list.
    selectObject: left_id
    left_ordered = Copy: "PP_L_ordered"
    selectObject: right_id
    right_ordered = Copy: "PP_R_ordered"
    removeObject: left_id, right_id

    selectObject: left_ordered
    plusObject: right_ordered
    id_final_output = Combine to stereo
    Rename: orig$ + "_detune_" + presetName$
    removeObject: left_ordered, right_ordered

    if stereo_detune_semitones >= 0
        detuneLabel$ = "+" + fixed$ (stereo_detune_semitones, 2)
    else
        detuneLabel$ = fixed$ (stereo_detune_semitones, 2)
    endif

    if meanPitch > 0
        beat_rate = abs (meanPitch * (2 ^ (shift_R / 12) - 2 ^ (shift_L / 12)))
    else
        beat_rate = 0
    endif
endif

# ============================================================
# MODE 2: TIME-DELAYED CANON
# ============================================================
if mode = 2
    appendInfoLine: "Creating canon with ", n_voices, " voices..."
    appendInfoLine: "  Pattern source: ", pattern_source$
    if canon_spatialisation = 1
        spat$ = "Mono"
    elsif canon_spatialisation = 2
        spat$ = "Stereo spread"
    else
        spat$ = "Alternating L-R"
    endif
    appendInfoLine: "  Spatialisation: ", spat$

    stereo_out = 0
    if canon_spatialisation > 1
        stereo_out = 1
    endif

    voice_ids# = zero# (n_voices)
    voice_delay# = zero# (n_voices)
    voice_gain# = zero# (n_voices)
    voice_gainL# = zero# (n_voices)
    voice_gainR# = zero# (n_voices)
    voice_cents# = zero# (n_voices)

    final_duration = 0

    for v from 1 to n_voices
        s = voice_st# [v]

        if humanize_cents <> 0
            cents = randomUniform (-humanize_cents, humanize_cents)
        else
            cents = 0
        endif
        voice_cents# [v] = cents

        factor = 2 ^ ((s + cents / 100) / 12)
        f_override = round (original_rate * factor)

        if f_override < 100 or f_override > 655350
            for vv from 1 to v - 1
                if voice_ids# [vv] > 0
                    removeObject: voice_ids# [vv]
                endif
            endfor
            removeObject: source_work
            exitScript: "Voice " + string$ (v) + " needs an unsafe override sample rate ("
                ... + string$ (f_override) + " Hz). Reduce the semitone range."
        endif

        delay_time = (v - 1) * delay_between_entries
        if humanize_timing_ms <> 0
            delay_time = delay_time + randomUniform (-humanize_timing_ms, humanize_timing_ms) / 1000
        endif
        if delay_time < 0
            delay_time = 0
        endif
        voice_delay# [v] = delay_time

        intensity = start_intensity_dB + (v - 1) * intensity_step_dB
        voice_gain# [v] = intensity

        # Constant-power spatialisation
        if canon_spatialisation = 2
            if n_voices > 1
                angle = (v - 1) / (n_voices - 1) * pi / 2
            else
                angle = pi / 4
            endif
            gL = cos (angle)
            gR = sin (angle)
        elsif canon_spatialisation = 3
            if v mod 2 = 1
                gL = 0.9511
                gR = 0.3090
            else
                gL = 0.3090
                gR = 0.9511
            endif
        else
            gL = 1
            gR = 1
        endif
        # fixed$ ignores its precision argument for values near zero, so clamp
        # the numerical residue of cos(pi/2) before it reaches any report.
        if abs (gL) < 0.000000001
            gL = 0
        endif
        if abs (gR) < 0.000000001
            gR = 0
        endif
        voice_gainL# [v] = gL
        voice_gainR# [v] = gR

        if abs (cents) < 0.000000001
            centsReport$ = ""
        else
            centsReport$ = "  (" + fixed$ (cents, 1) + " cents)"
        endif
        appendInfoLine: "  Voice ", v, ": ", fixed$ (s, 2), " ST", centsReport$,
            ... "  delay ", fixed$ (delay_time, 3), " s",
            ... "  ", fixed$ (intensity, 1), " dB",
            ... "  pan L/R ", fixed$ (gL, 2), "/", fixed$ (gR, 2)

        selectObject: source_work
        voice_raw = Copy: "PP_voice_raw_" + string$ (v)
        Override sampling frequency: f_override
        voice_shifted = Resample: output_sample_rate, resample_precision
        Rename: "PP_voice_active_" + string$ (v)
        removeObject: voice_raw

        selectObject: voice_shifted
        Scale intensity: intensity

        active_dur = Get total duration
        voice_ids# [v] = voice_shifted

        voice_end = delay_time + active_dur
        if voice_end > final_duration
            final_duration = voice_end
        endif
    endfor

    if final_duration <= 0
        for v from 1 to n_voices
            removeObject: voice_ids# [v]
        endfor
        removeObject: source_work
        exitScript: "Canon rendering produced no positive duration."
    endif

    Create Sound from formula: "PP_canon_L", 1, 0, final_duration, output_sample_rate, "0"
    id_mixL = selected ("Sound")
    id_mixR = 0
    if stereo_out
        Create Sound from formula: "PP_canon_R", 1, 0, final_duration, output_sample_rate, "0"
        id_mixR = selected ("Sound")
    endif

    for v from 1 to n_voices
        id_voice = voice_ids# [v]
        delay_time = voice_delay# [v]

        if delay_time > 0.000001
            @prependSilence: id_voice, delay_time
            with_delay = res_id
        else
            with_delay = id_voice
        endif

        @padToLength: with_delay, final_duration
        full_layer = res_id

        selectObject: id_mixL
        Formula: "self + " + string$ (voice_gainL# [v]) + " * object [" + string$ (full_layer) + ", 1, col]"
        if stereo_out
            selectObject: id_mixR
            Formula: "self + " + string$ (voice_gainR# [v]) + " * object [" + string$ (full_layer) + ", 1, col]"
        endif
        removeObject: full_layer
    endfor

    if stereo_out
        selectObject: id_mixL
        plusObject: id_mixR
        id_final_output = Combine to stereo
        removeObject: id_mixL, id_mixR
    else
        id_final_output = id_mixL
    endif
    selectObject: id_final_output
    Rename: orig$ + "_canon_" + presetName$
endif

removeObject: source_work

# ============================================================
# OUTPUT STAGE: fade, peak ceiling
# ============================================================
selectObject: id_final_output
final_duration = Get total duration
final_channels = Get number of channels

fade_sec = fade_ms / 1000
if fade_sec > 0 and 2 * fade_sec < final_duration
    Formula: "self * (if x < " + string$ (fade_sec) + " then 0.5 - 0.5 * cos (pi * x / " + string$ (fade_sec) + ")"
        ... + " else if x > " + string$ (final_duration - fade_sec) + " then 0.5 - 0.5 * cos (pi * ("
        ... + string$ (final_duration) + " - x) / " + string$ (fade_sec) + ") else 1 fi fi)"
    fade_applied = fade_ms
else
    fade_applied = 0
endif

peak_before = Get absolute extremum: 0, 0, "None"
if peak_before > peak_ceiling
    Scale peak: peak_ceiling
    safety_applied = 1
endif
peak_after = Get absolute extremum: 0, 0, "None"

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    @sanitize: orig$
    src$ = sanitized$

    pageWidth = 8
    pageHeight = 8.75

    # Shared amplitude range, so original and result panels are comparable.
    selectObject: id_original
    o_max = Get maximum: 0, 0, "None"
    o_min = Get minimum: 0, 0, "None"
    selectObject: id_final_output
    r_max = Get maximum: 0, 0, "None"
    r_min = Get minimum: 0, 0, "None"
    amp = max (abs (o_max), abs (o_min))
    amp = max (amp, max (abs (r_max), abs (r_min)))
    if amp <= 0
        amp = 1
    endif
    amp = amp * 1.08

    Erase all
    Line width: 1
    Solid line

    # ----------------------------------------------------------
    # Title strip
    # ----------------------------------------------------------
    Font size: 13
    Select inner viewport: 0.60, 7.70, 0.10, 0.55
    Axes: 0, 1, 0, 1
    Colour: "Black"
    if mode = 1
        Text: 0.5, "centre", 0.72, "half", "##Pitch Processor v2.1 - Stereo Pitch Detune##"
    else
        Text: 0.5, "centre", 0.72, "half", "##Pitch Processor v2.1 - Time-Delayed Canon##"
    endif

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.10, 0.55
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    if mode = 1
        Text: 0.5, "centre", 0.20, "half", src$ + "   |   preset: " + presetName$
            ... + "   |   interval: " + detuneLabel$ + " ST   |   " + method$
    else
        Text: 0.5, "centre", 0.20, "half", src$ + "   |   preset: " + presetName$
            ... + "   |   " + string$ (n_voices) + " voices   |   " + spat$
    endif

    # ----------------------------------------------------------
    # Panel 1: original waveform
    # ----------------------------------------------------------
    Font size: 7
    Select outer viewport: 0, 8, 0.60, 1.60
    Select inner viewport: 0.60, 7.70, 0.72, 1.45
    Axes: 0, original_duration, -amp, amp
    selectObject: id_original
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, -amp, amp, "no", "Curve"

    Select inner viewport: 0.60, 7.70, 0.72, 1.45
    Axes: 0, original_duration, -amp, amp
    Colour: "Black"
    Draw inner box

    Select inner viewport: 0.60, 7.70, 0.72, 1.45
    Axes: 0, original_duration, -amp, amp
    Text left: "no", "##Original##"
    Text top: "no", fixed$ (original_duration, 2) + " s   |   "
        ... + fixed$ (original_rate, 0) + " Hz   |   peak " + fixed$ (max (abs (o_max), abs (o_min)), 3)

    # ----------------------------------------------------------
    # Panel 2: result waveform
    # ----------------------------------------------------------
    Font size: 7
    Select outer viewport: 0, 8, 1.60, 2.65
    Select inner viewport: 0.60, 7.70, 1.75, 2.50
    Axes: 0, final_duration, -amp, amp
    selectObject: id_final_output
    if mode = 1
        Colour: "{0.20, 0.40, 0.80}"
    else
        Colour: "{0.20, 0.55, 0.45}"
    endif
    Draw: 0, 0, -amp, amp, "no", "Curve"

    Select inner viewport: 0.60, 7.70, 1.75, 2.50
    Axes: 0, final_duration, -amp, amp
    Colour: "Black"
    Draw inner box

    Select inner viewport: 0.60, 7.70, 1.75, 2.50
    Axes: 0, final_duration, -amp, amp
    if final_channels > 1
        Text left: "no", "##Result (L / R)##"
    else
        Text left: "no", "##Result##"
    endif
    Text top: "no", fixed$ (final_duration, 2) + " s   |   " + string$ (final_channels)
        ... + " ch   |   peak " + fixed$ (peak_after, 3)

    # ----------------------------------------------------------
    # Panel 3 and 4: spectrograms
    # ----------------------------------------------------------
    selectObject: id_original
    if original_channels > 1
        origMono = Convert to mono
    else
        origMono = Copy: "PP_orig_mono"
    endif
    selectObject: origMono
    To Spectrogram: 0.005, spectrogram_max_Hz, 0.002, 20, "Gaussian"
    origSpec = selected ("Spectrogram")

    Font size: 7
    Select outer viewport: 0, 4, 2.70, 4.30
    Select inner viewport: 0.60, 3.70, 2.85, 4.10
    selectObject: origSpec
    Paint: 0, 0, 0, spectrogram_max_Hz, 100, "yes", 50, 6, 0, "no"

    Select inner viewport: 0.60, 3.70, 2.85, 4.10
    Axes: 0, original_duration, 0, spectrogram_max_Hz
    Colour: "Black"
    Draw inner box

    Select inner viewport: 0.60, 3.70, 2.85, 4.10
    Axes: 0, original_duration, 0, spectrogram_max_Hz
    @niceStep: spectrogram_max_Hz, 5
    Marks left every: 1, niceStep, "yes", "yes", "no"
    @niceStep: original_duration, 5
    Marks bottom every: 1, niceStep, "yes", "yes", "no"

    Select inner viewport: 0.60, 3.70, 2.85, 4.10
    Axes: 0, original_duration, 0, spectrogram_max_Hz
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "##Original spectrum##"

    removeObject: origSpec, origMono

    selectObject: id_final_output
    if final_channels > 1
        resMono = Convert to mono
    else
        resMono = Copy: "PP_res_mono"
    endif
    selectObject: resMono
    To Spectrogram: 0.005, spectrogram_max_Hz, 0.002, 20, "Gaussian"
    resSpec = selected ("Spectrogram")

    Font size: 7
    Select outer viewport: 4, 8, 2.70, 4.30
    Select inner viewport: 4.40, 7.70, 2.85, 4.10
    selectObject: resSpec
    Paint: 0, 0, 0, spectrogram_max_Hz, 100, "yes", 50, 6, 0, "no"

    Select inner viewport: 4.40, 7.70, 2.85, 4.10
    Axes: 0, final_duration, 0, spectrogram_max_Hz
    Colour: "Black"
    Draw inner box

    Select inner viewport: 4.40, 7.70, 2.85, 4.10
    Axes: 0, final_duration, 0, spectrogram_max_Hz
    @niceStep: spectrogram_max_Hz, 5
    Marks left every: 1, niceStep, "yes", "yes", "no"
    @niceStep: final_duration, 5
    Marks bottom every: 1, niceStep, "yes", "yes", "no"

    Select inner viewport: 4.40, 7.70, 2.85, 4.10
    Axes: 0, final_duration, 0, spectrogram_max_Hz
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "##Result spectrum##"

    removeObject: resSpec, resMono

    # ----------------------------------------------------------
    # Panel 5: analysis
    #   mode 1 - measured F0 of both output channels
    #   mode 2 - canon entry timeline
    # ----------------------------------------------------------
    if mode = 1
        selectObject: id_final_output
        vizL = Extract one channel: 1
        selectObject: id_final_output
        vizR = Extract one channel: 2

        f_lo = 0
        f_hi = 0
        pitchL = 0
        pitchR = 0
        if final_duration >= 3 / pitch_floor_Hz
            selectObject: vizL
            pitchL = To Pitch: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
            selectObject: vizR
            pitchR = To Pitch: 0.01, pitch_floor_Hz, pitch_ceiling_Hz

            # Quantiles rather than min/max: a single octave-doubling frame
            # would otherwise set the axis and flatten the real contour.
            selectObject: pitchL
            aL = Get quantile: 0, 0, 0.02, "Hertz"
            bL = Get quantile: 0, 0, 0.98, "Hertz"
            selectObject: pitchR
            aR = Get quantile: 0, 0, 0.02, "Hertz"
            bR = Get quantile: 0, 0, 0.98, "Hertz"

            if aL <> undefined and aR <> undefined
                f_lo = min (aL, aR)
                f_hi = max (bL, bR)
            elsif aL <> undefined
                f_lo = aL
                f_hi = bL
            elsif aR <> undefined
                f_lo = aR
                f_hi = bR
            endif
        endif

        if f_hi <= f_lo
            f_lo = pitch_floor_Hz
            f_hi = min (pitch_ceiling_Hz, 4 * pitch_floor_Hz)
            f_valid = 0
        else
            span = f_hi - f_lo
            f_lo = max (0, f_lo - 0.15 * span)
            f_hi = f_hi + 0.15 * span
            f_valid = 1
        endif

        Font size: 7
        Select outer viewport: 0, 8, 4.65, 6.35
        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, f_lo, f_hi

        if f_valid and pitchL > 0
            # Pitch Draw does not clip to the panel, so an octave-error frame
            # outside the axis range would be painted over a neighbouring
            # panel. Clamp the drawing copies to unvoiced instead.
            clamp$ = "if self > " + string$ (f_hi) + " or (self > 0 and self < "
                ... + string$ (f_lo) + ") then 0 else self fi"
            selectObject: pitchL
            drawL = Copy: "PP_drawL"
            Formula: clamp$
            selectObject: pitchR
            drawR = Copy: "PP_drawR"
            Formula: clamp$

            Select inner viewport: 0.60, 7.70, 4.80, 6.10
            Axes: 0, final_duration, f_lo, f_hi
            selectObject: drawL
            Colour: "{0.20, 0.40, 0.80}"
            Draw: 0, final_duration, f_lo, f_hi, "no"

            Select inner viewport: 0.60, 7.70, 4.80, 6.10
            Axes: 0, final_duration, f_lo, f_hi
            selectObject: drawR
            Colour: "{0.85, 0.45, 0.15}"
            Draw: 0, final_duration, f_lo, f_hi, "no"

            removeObject: drawL, drawR
        endif

        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, f_lo, f_hi
        Colour: "Black"
        Draw inner box

        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, f_lo, f_hi
        @niceStep: f_hi - f_lo, 5
        Marks left every: 1, niceStep, "yes", "yes", "no"
        @niceStep: final_duration, 8
        Marks bottom every: 1, niceStep, "yes", "yes", "no"

        Font size: 7
        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, f_lo, f_hi
        Text left: "yes", "F0 (Hz)"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "##Measured F0 of the two output channels##"

        Font size: 6
        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, 1, 0, 1
        if f_valid
            Colour: "{0.20, 0.40, 0.80}"
            Text: 0.02, "left", 0.94, "half", "left  " + fixed$ (shift_L, 2) + " ST"
            Colour: "{0.85, 0.45, 0.15}"
            Text: 0.13, "left", 0.94, "half", "right " + fixed$ (shift_R, 2) + " ST"
            Colour: "{0.30, 0.30, 0.35}"
            if beat_rate > 0
                Text: 0.98, "right", 0.94, "half", "beat rate at mean F0: "
                    ... + fixed$ (beat_rate, 2) + " Hz"
            endif
        else
            Colour: "{0.45, 0.45, 0.50}"
            Text: 0.5, "centre", 0.5, "half", "No voiced frames detected in the output"
        endif

        if pitchL > 0
            removeObject: pitchL, pitchR
        endif
        removeObject: vizL, vizR

    else
        max_entry = 0
        for v from 1 to n_voices
            if voice_delay# [v] > max_entry
                max_entry = voice_delay# [v]
            endif
        endfor

        st_lo = voice_st# [1]
        st_hi = voice_st# [1]
        for v from 1 to n_voices
            if voice_st# [v] < st_lo
                st_lo = voice_st# [v]
            endif
            if voice_st# [v] > st_hi
                st_hi = voice_st# [v]
            endif
        endfor

        Font size: 7
        Select outer viewport: 0, 8, 4.65, 6.35
        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, 0, n_voices + 1
        Paint rectangle: "{0.975, 0.975, 0.975}", 0, final_duration, 0, n_voices + 1

        # Voice bars, hue keyed to the pitch of the voice
        for v from 1 to n_voices
            Select inner viewport: 0.60, 7.70, 4.80, 6.10
            Axes: 0, final_duration, 0, n_voices + 1
            y_pos = n_voices - v + 1
            d0 = voice_delay# [v]
            selectObject: id_final_output
            d1 = d0 + original_duration / (2 ^ (voice_st# [v] / 12))
            if d1 > final_duration
                d1 = final_duration
            endif
            if st_hi > st_lo
                t = (voice_st# [v] - st_lo) / (st_hi - st_lo)
            else
                t = 0.5
            endif
            cr = 0.25 + 0.60 * t
            cg = 0.55 - 0.20 * t
            cb = 0.85 - 0.55 * t
            Paint rectangle: "{" + fixed$ (cr, 3) + ", " + fixed$ (cg, 3) + ", "
                ... + fixed$ (cb, 3) + "}", d0, d1, y_pos - 0.32, y_pos + 0.32
        endfor

        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, 0, n_voices + 1
        Font size: 6
        for v from 1 to n_voices
            Select inner viewport: 0.60, 7.70, 4.80, 6.10
            Axes: 0, final_duration, 0, n_voices + 1
            y_pos = n_voices - v + 1
            d0 = voice_delay# [v]
            Colour: "Black"
            Text: d0 + 0.01 * final_duration, "left", y_pos, "half",
                ... "V" + string$ (v) + "   " + fixed$ (voice_st# [v], 2) + " ST   "
                ... + fixed$ (voice_gain# [v], 1) + " dB"
        endfor

        Font size: 7
        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, 0, n_voices + 1
        Colour: "Black"
        Draw inner box

        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, 0, n_voices + 1
        @niceStep: final_duration, 8
        Marks bottom every: 1, niceStep, "yes", "yes", "no"

        # Voice rows run top to bottom, so a plain numeric axis would print 8
        # beside voice 1. Label each row with its own voice number instead.
        Font size: 6
        for v from 1 to n_voices
            Select inner viewport: 0.60, 7.70, 4.80, 6.10
            Axes: 0, final_duration, 0, n_voices + 1
            One mark left: n_voices - v + 1, "no", "yes", "no", "V" + string$ (v)
        endfor

        Font size: 7
        Select inner viewport: 0.60, 7.70, 4.80, 6.10
        Axes: 0, final_duration, 0, n_voices + 1
        Text left: "yes", "Entry order"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "##Canon entry timeline - bar length is the varispeed duration, colour is pitch##"
    endif

    # ----------------------------------------------------------
    # Panel 6: structure
    # ----------------------------------------------------------
    Font size: 7
    Select inner viewport: 0.60, 3.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.975}", 0, 1, 0, 1

    Select inner viewport: 0.60, 3.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.93, "half", "##Interval structure##"

    Font size: 6
    if mode = 1
        @intervalName: stereo_detune_semitones
        Select inner viewport: 0.60, 3.70, 6.70, 7.95
        Axes: 0, 1, 0, 1
        Colour: "{0.25, 0.25, 0.35}"
        Text: 0.04, "left", 0.79, "half", "Channel interval: " + detuneLabel$ + " ST  ("
            ... + intervalName$ + ")"
        Text: 0.04, "left", 0.68, "half", "Left  " + fixed$ (shift_L, 3) + " ST   ratio "
            ... + fixed$ (2 ^ (shift_L / 12), 5)
        Text: 0.04, "left", 0.57, "half", "Right " + fixed$ (shift_R, 3) + " ST   ratio "
            ... + fixed$ (2 ^ (shift_R / 12), 5)
        if meanPitch > 0
            Text: 0.04, "left", 0.46, "half", "Mean F0 " + fixed$ (meanPitch, 1) + " Hz  ->  L "
                ... + fixed$ (meanPitch * 2 ^ (shift_L / 12), 1) + " Hz / R "
                ... + fixed$ (meanPitch * 2 ^ (shift_R / 12), 1) + " Hz"
            Text: 0.04, "left", 0.35, "half", "Beat rate " + fixed$ (beat_rate, 2) + " Hz"
        else
            Text: 0.04, "left", 0.46, "half", "Mean F0 not measurable on this source"
        endif
        if abs (haas_delay_ms) > 0.0001
            if haas_delay_ms > 0
                haasSide$ = "right"
            else
                haasSide$ = "left"
            endif
            Text: 0.04, "left", 0.24, "half", "Haas delay " + fixed$ (abs (haas_delay_ms), 1)
                ... + " ms on the " + haasSide$ + " channel"
            Text: 0.04, "left", 0.13, "half", "Image pulls toward the earlier channel"
        else
            Text: 0.04, "left", 0.24, "half", "No Haas delay - image is symmetric in time"
        endif
    else
        Select inner viewport: 0.60, 3.70, 6.70, 7.95
        Axes: 0, 1, 0, 1
        rows = n_voices
        if rows > 9
            rows = 9
        endif
        Colour: "{0.25, 0.25, 0.35}"
        for v from 1 to rows
            Select inner viewport: 0.60, 3.70, 6.70, 7.95
            Axes: 0, 1, 0, 1
            @intervalName: voice_st# [v]
            yv = 0.80 - (v - 1) * 0.075
            Text: 0.04, "left", yv, "half", "V" + string$ (v) + "   "
                ... + fixed$ (voice_st# [v], 2) + " ST   " + intervalName$
                ... + "   entry " + fixed$ (voice_delay# [v], 2) + " s"
        endfor
        if n_voices > rows
            Select inner viewport: 0.60, 3.70, 6.70, 7.95
            Axes: 0, 1, 0, 1
            Text: 0.04, "left", 0.80 - rows * 0.075, "half",
                ... "... " + string$ (n_voices - rows) + " further voices, see the Info window"
        endif
        Select inner viewport: 0.60, 3.70, 6.70, 7.95
        Axes: 0, 1, 0, 1
        Colour: "{0.45, 0.45, 0.50}"
        Text: 0.04, "left", 0.06, "half", "Total range " + fixed$ (st_hi - st_lo, 2)
            ... + " ST   |   pattern from " + pattern_source$
    endif

    Font size: 7
    Select inner viewport: 0.60, 3.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # Panel 7: technique
    # ----------------------------------------------------------
    Font size: 7
    Select inner viewport: 4.40, 7.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.975}", 0, 1, 0, 1

    Select inner viewport: 4.40, 7.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.93, "half", "##Technique##"

    Font size: 6
    Select inner viewport: 4.40, 7.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    if mode = 1
        if detune_method = 1
            Text: 0.04, "left", 0.79, "half", "1  Analyse F0 on a mono reference copy"
            Text: 0.04, "left", 0.68, "half", "2  Multiply the PitchTier by the channel ratio"
            Text: 0.04, "left", 0.57, "half", "3  Resynthesize by PSOLA overlap-add"
            Text: 0.04, "left", 0.46, "half", "4  Duration is preserved exactly"
        else
            Text: 0.04, "left", 0.79, "half", "1  Copy the mono reference per channel"
            Text: 0.04, "left", 0.68, "half", "2  Override the sample rate by the channel ratio"
            Text: 0.04, "left", 0.57, "half", "3  Resample back to the output rate"
            Text: 0.04, "left", 0.46, "half", "4  Duration follows the pitch (tape behaviour)"
        endif
        Text: 0.04, "left", 0.35, "half", "5  Pad both channels, then combine to stereo"
        Text: 0.04, "left", 0.24, "half", "Output " + fixed$ (output_sample_rate, 0)
            ... + " Hz   |   fade " + fixed$ (fade_applied, 0) + " ms"
        Text: 0.04, "left", 0.13, "half", "Peak " + fixed$ (peak_before, 3) + " -> "
            ... + fixed$ (peak_after, 3) + "   (ceiling " + fixed$ (peak_ceiling, 2) + ")"
    else
        Text: 0.04, "left", 0.79, "half", "1  One varispeed copy per voice"
        Text: 0.04, "left", 0.68, "half", "2  Override rate = " + fixed$ (original_rate, 0)
            ... + " Hz x the voice ratio"
        Text: 0.04, "left", 0.57, "half", "3  Scale intensity, then prepend the entry delay"
        Text: 0.04, "left", 0.46, "half", "4  Sum into a fixed-length accumulator"
        if canon_spatialisation = 1
            Text: 0.04, "left", 0.35, "half", "5  Mono sum"
        else
            Text: 0.04, "left", 0.35, "half", "5  Constant-power pan into L and R buses"
        endif
        Text: 0.04, "left", 0.24, "half", "Output " + fixed$ (output_sample_rate, 0)
            ... + " Hz   |   fade " + fixed$ (fade_applied, 0) + " ms"
        Text: 0.04, "left", 0.13, "half", "Peak " + fixed$ (peak_before, 3) + " -> "
            ... + fixed$ (peak_after, 3) + "   (ceiling " + fixed$ (peak_ceiling, 2) + ")"
    endif

    Font size: 7
    Select inner viewport: 4.40, 7.70, 6.70, 7.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Font size: 7
    Select inner viewport: 0.60, 7.70, 8.05, 8.60
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 8.05, 8.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.76, "half", "##Summary##"

    Font size: 6
    Select inner viewport: 0.60, 7.70, 8.05, 8.60
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.35}"
    if mode = 1
        Text: 0.02, "left", 0.47, "half", "Detune " + detuneLabel$ + " ST ("
            ... + presetName$ + ")   |   balance " + balance$ + "   |   " + method$
            ... + "   |   Haas " + fixed$ (haas_delay_ms, 1) + " ms"
        Text: 0.02, "left", 0.20, "half", "Duration " + fixed$ (original_duration, 2) + " s -> "
            ... + fixed$ (final_duration, 2) + " s   |   output " + fixed$ (output_sample_rate, 0)
            ... + " Hz   |   peak " + fixed$ (peak_after, 3)
    else
        Text: 0.02, "left", 0.47, "half", string$ (n_voices) + " voices ("
            ... + presetName$ + ")   |   range " + fixed$ (st_hi - st_lo, 2)
            ... + " ST   |   entry step " + fixed$ (delay_between_entries, 2)
            ... + " s   |   " + spat$
        Text: 0.02, "left", 0.20, "half", "Duration " + fixed$ (original_duration, 2) + " s -> "
            ... + fixed$ (final_duration, 2) + " s   |   output " + fixed$ (output_sample_rate, 0)
            ... + " Hz   |   peak " + fixed$ (peak_after, 3)
    endif

    Font size: 7
    Select inner viewport: 0.60, 7.70, 8.05, 8.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Full-canvas selection, so Save as PNG and Copy capture the whole page.
    Select outer viewport: 0, pageWidth, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# REPORT
# ============================================================
selectObject: id_final_output

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", selected$ ("Sound")
appendInfoLine: "Duration: ", fixed$ (final_duration, 3), " s   Channels: ", final_channels
if mode = 1
    appendInfoLine: "Channel interval: ", fixed$ (stereo_detune_semitones, 2), " ST"
    appendInfoLine: "Method: ", method$
    appendInfoLine: "Haas delay: ", fixed$ (haas_delay_ms, 1), " ms"
    if beat_rate > 0
        appendInfoLine: "Beat rate at mean F0: ", fixed$ (beat_rate, 2), " Hz"
    endif
else
    appendInfoLine: "Voices: ", n_voices, "   Pattern from: ", pattern_source$
    appendInfoLine: "Semitone range: ", fixed$ (st_hi - st_lo, 2), " ST"
endif
appendInfoLine: "Fade applied: ", fixed$ (fade_applied, 1), " ms"
appendInfoLine: "Peak: ", fixed$ (peak_before, 4), " -> ", fixed$ (peak_after, 4),
    ... "   (ceiling ", fixed$ (peak_ceiling, 3), ", attenuation applied: ", safety_applied, ")"
if length (warning$) > 0
    appendInfoLine: ""
    appendInfoLine: "Notes: ", warning$
endif

if play_after_processing
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    Play
endif

# ============================================================
# PROCEDURES
# ============================================================

# Produce a pitch-shifted copy of source_work at the output rate.
# Result id is returned in the global shifted_id.
procedure makeShifted: .semitones
    if abs (.semitones) < 0.0000001
        selectObject: source_work
        shifted_id = Resample: output_sample_rate, resample_precision
    elsif detune_method = 2
        selectObject: source_work
        .cp = Copy: "PP_varispeed_tmp"
        .f = round (original_rate * 2 ^ (.semitones / 12))
        Override sampling frequency: .f
        shifted_id = Resample: output_sample_rate, resample_precision
        removeObject: .cp
    else
        selectObject: source_work
        .man = To Manipulation: 0.01, pitch_floor_Hz, pitch_ceiling_Hz
        selectObject: .man
        .tier = Extract pitch tier
        selectObject: .tier
        Formula: "self * " + string$ (2 ^ (.semitones / 12))
        selectObject: .man
        plusObject: .tier
        Replace pitch tier
        selectObject: .man
        .res = Get resynthesis (overlap-add)
        removeObject: .man, .tier
        selectObject: .res
        shifted_id = Resample: output_sample_rate, resample_precision
        removeObject: .res
    endif
endproc

# Prepend silence to a Sound. Result id in the global res_id.
procedure prependSilence: .id, .secs
    selectObject: .id
    .rate = Get sampling frequency
    .nPad = round (.secs * .rate)
    if .nPad >= 1
        Create Sound from formula: "PP_pad_head", 1, 0, .nPad / .rate, .rate, "0"
        .pad = selected ("Sound")
        selectObject: .id
        .cp = Copy: "PP_pad_body"
        selectObject: .pad
        plusObject: .cp
        res_id = Concatenate
        removeObject: .pad, .cp, .id
    else
        res_id = .id
    endif
endproc

# Pad or trim a Sound to an exact length. Result id in the global res_id.
procedure padToLength: .id, .target
    # Works in whole samples: a sub-sample duration difference would otherwise
    # ask Create Sound from formula for a zero-sample object and abort.
    .cur = .id
    selectObject: .cur
    .rate = Get sampling frequency
    .nTarget = round (.target * .rate)
    .n = Get number of samples

    if .nTarget - .n >= 1
        Create Sound from formula: "PP_pad_tail", 1, 0, (.nTarget - .n) / .rate, .rate, "0"
        .pad = selected ("Sound")
        selectObject: .cur
        plusObject: .pad
        .cat = Concatenate
        removeObject: .cur, .pad
        .cur = .cat
        selectObject: .cur
        .n = Get number of samples
    endif

    if .n - .nTarget >= 1
        selectObject: .cur
        .trim = Extract part: 0, .nTarget / .rate, "rectangular", 1, "no"
        removeObject: .cur
        .cur = .trim
    endif

    res_id = .cur
endproc

# Parse a whitespace or comma separated semitone list.
# Results in the globals parse_n and parse_v#.
procedure parseList: .raw$
    parse_v# = zero# (64)
    parse_n = 0
    .s$ = replace$ (.raw$, ",", " ", 0)
    .s$ = replace$ (.s$, ";", " ", 0)
    .s$ = replace$ (.s$, tab$, " ", 0)
    .go = 1
    while .go = 1
        while left$ (.s$, 1) = " "
            .s$ = mid$ (.s$, 2, length (.s$) - 1)
        endwhile
        if length (.s$) = 0
            .go = 0
        else
            .sp = index (.s$, " ")
            if .sp = 0
                .tok$ = .s$
                .s$ = ""
            else
                .tok$ = left$ (.s$, .sp - 1)
                .s$ = mid$ (.s$, .sp + 1, length (.s$) - .sp)
            endif
            if length (.tok$) > 0
                .val = number (.tok$)
                if .val = undefined
                    exitScript: "Could not read """ + .tok$ + """ as a semitone value."
                endif
                if parse_n >= 32
                    exitScript: "The semitone list is limited to 32 voices."
                endif
                parse_n = parse_n + 1
                parse_v# [parse_n] = .val
            endif
        endif
    endwhile
endproc

# Interval name for a semitone distance. Result in the global intervalName$.
procedure intervalName: .st
    .a = round (abs (.st))
    .pc = .a mod 12
    .oct = floor (.a / 12)
    if .pc = 0
        .n$ = "unison"
    elsif .pc = 1
        .n$ = "m2"
    elsif .pc = 2
        .n$ = "M2"
    elsif .pc = 3
        .n$ = "m3"
    elsif .pc = 4
        .n$ = "M3"
    elsif .pc = 5
        .n$ = "P4"
    elsif .pc = 6
        .n$ = "tritone"
    elsif .pc = 7
        .n$ = "P5"
    elsif .pc = 8
        .n$ = "m6"
    elsif .pc = 9
        .n$ = "M6"
    elsif .pc = 10
        .n$ = "m7"
    else
        .n$ = "M7"
    endif
    if .oct = 1 and .pc = 0
        .n$ = "octave"
    elsif .oct >= 1
        .n$ = .n$ + " + " + string$ (.oct) + " oct"
    endif
    if .st < 0
        .n$ = .n$ + " down"
    endif
    intervalName$ = .n$
endproc

# Snap a tick step to 1, 2 or 5 times a power of ten.
# Result in the global niceStep.
procedure niceStep: .span, .n
    if .span <= 0 or .n <= 0
        niceStep = 1
    else
        .raw = .span / .n
        .p = 10 ^ floor (log10 (.raw))
        .m = .raw / .p
        if .m < 1.5
            .k = 1
        elsif .m < 3.5
            .k = 2
        elsif .m < 7.5
            .k = 5
        else
            .k = 10
        endif
        niceStep = .k * .p
    endif
endproc

# Escape Praat Picture markup in a machine-supplied name.
# Result in the global sanitized$.
procedure sanitize: .s$
    .t$ = replace$ (.s$, "_", "\_ ", 0)
    .t$ = replace$ (.t$, "#", "\# ", 0)
    .t$ = replace$ (.t$, "%", "\% ", 0)
    .t$ = replace$ (.t$, "^", "\^ ", 0)
    sanitized$ = .t$
endproc
