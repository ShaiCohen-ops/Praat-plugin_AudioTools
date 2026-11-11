# ============================================================
# Praat AudioTools - Ligeti_Micropolyphonic_Choir_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ligeti Micropolyphonic Choir Machine - dense, slowly-evolving
#   textures via N pitch-detuned, time-offset, fade-enveloped voices
#   summed into a single output buffer.
#
#   PROCESSING MODES
#   Legacy        the v1.3.1 engine, unchanged: every voice is a whole,
#                 transformed copy of the source with ONE fixed offset.
#   Microtemporal every voice reads the source through a time-varying
#                 displacement:
#                   offset_v(t) = macro_v + micro_v(t) - divergence_v
#                 macro_v      whole-voice displacement (Time_offset_range_s),
#                              symmetric: + = later, - = earlier
#                 micro_v(t)   +/- Micro_offset_ms x trajectory_v(t), static
#                              or evolving (Emergence, Convergence,
#                              Breathing, Waves, Stochastic drift)
#                 divergence_v 0..Source_divergence_ms read advance: the
#                              voice starts on time but from a later
#                              point of the source
#
#   MICROTEMPORAL RECONSTRUCTION (overlap-add, two interleaved streams)
#     Grains of L samples (Grain_ms), hop L/2, sin^2 windows that sum to
#     exactly 1. Within a grain the displacement is a constant INTEGER
#     number of samples, so the material is never resampled: a static
#     offset gives an exact delayed copy. The displacement changes only
#     from grain to grain, through the crossfade.
#     An evolving displacement always moves the phase of the material
#     (the average frequency deviation equals the rate of change of the
#     delay - the Doppler effect); no reconstruction method avoids it.
#     Doppler_limit_cents caps it with a slew limit on the displacement
#     (applied to the PEAK deviation inside a crossfade, pi/2 times the
#     average) and the report gives the largest deviation actually used.
#
# Changelog v2.1 (2026), after the first review of v2.0:
#   - Coherence compensation (0-100 %): a slow gain (50 ms frames) that
#     removes the level change caused by voices adding coherently or
#     cancelling, measured against the expected level of independent voices
#     at their actual read positions, so the source's own dynamics remain.
#   - Trajectory endpoints: a backward slew pass puts the END of every
#     trajectory exactly on plan (Convergence reaches synchrony); the start
#     was already exact. Report: share of grains off plan and by how much.
#   - Rate_unit: Hz or cycles over the whole timeline.
#   - (v2.1.1) Infeasible evolutions: the depth is reduced per voice until
#     the trajectory runs from its exact start to its exact end within the
#     Doppler limit (v2.1 moved the start instead, with a contradictory
#     report). Scatter_mode Free / Smooth. Silent-source report. Vector
#     max()/min() replaced by loops (failed on Praat 6.1.x).
#   - Read_scatter_ms: independent per-grain read positions, scaled by the
#     evolution envelope. Decorrelates voices without a systematic pitch
#     shift; on tonal material it produces per-grain phase jumps
#     (roughness), not a glide.
#   - Waves: groups 60 degrees apart (at 120 degrees the three envelopes
#     summed to a constant, so the mass could not expand and contract).
#   - Musical presets retuned: 1-2 cycles over the timeline, read scatter,
#     coherence compensation 100 %.
#   - Info reports the EFFECTIVE pitch deviation including the varispeed of
#     Duration_variation (legacy sound unchanged).
#
# Changelog v2.0 (2026):
#   NEW
#   - Processing_mode: Legacy / Microtemporal. Legacy is the v1.3.1 engine,
#     sample-for-sample (verified with equal seeds).
#   - Microtemporal engine (above), its settings in a second dialog
#     (Microtemporal_settings), report with per-voice displacements at
#     five positions, displacement dispersion over time, summation
#     coherence and Doppler bound; new trajectory and dispersion panels.
#   - Presets: Experiments A-D (Synchronous, Static Micro Offset, Evolving
#     Micro Offset, Macro Cloud: 24 voices, mono, no pitch or duration
#     variation, wet only, RMS level-matched) and Emergence, Convergence,
#     Breathing Coherence, Coherence Waves.
#   - Random_seed (0 = new seed, reported): every mode is reproducible.
#     Seeding does not change the legacy random distribution.
#   - Output_level: Peak normalize to 0.95 (v1.3.1 default) / Match source
#     RMS (level-matched comparison, clipping-safe, shortfall reported) /
#     None (clipping reported). Replaces the Normalize_output box:
#     Normalize_output = 1 is option 1, = 0 is option 3.
#   CHANGED (no effect on the legacy sound)
#   - Time_offset_range_s, Duration_variation, Max_pitch_cents,
#     Attack_fade_ms and Voice_gain accept 0 (were "positive").
#   - Legacy figure no longer fails when the offset or pitch range is 0.
#   - Info header showed "v1.1".
#   DOCUMENTED, NOT CHANGED (changing them would change legacy presets)
#   - Duration_variation is applied by sample-rate reinterpretation, so it
#     changes pitch as well as duration (+/-5 % is about +/-85 cents).
#   - Legacy negative offsets trim the start of a voice and place it at
#     time 0 (a read advance); positive offsets delay it.
#   - Legacy voices longer than the source are trimmed at its end; the
#     output is source + offset range + 0.5 s.
#   - The runScript argument list changed (new fields).
#
# Changelog v1.3.1 (2026): shared left panel-label rails and user-approved
#   Summary geometry; DSP/analysis unchanged.
# Changelog v1.2 / v1.1: see repository history (offset semantics fix,
#   single combined resample per voice, folded envelope).
# ============================================================

form Ligeti Micropolyphonic Choir v2.1.1
    comment === Behavioral Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Static Spectral Fog (Gaussian Mass)
        option Fracturing Mass (Gradual Detuning)
        option Stereo Torsion (L=Pure, R=Detuned)
        option Bimodal Web (High/Low Split)
        option Breathing Field (Uniform Cloud)
        option Experiment A: Synchronous (mono reference)
        option Experiment B: Static Micro Offset (10 ms)
        option Experiment C: Evolving Micro Offset (10 ms)
        option Experiment D: Macro Cloud (500 ms)
        option Emergence (coherent to mass)
        option Convergence (mass to unison)
        option Breathing Coherence
        option Coherence Waves (3 voice groups)
    optionmenu Processing_mode 1
        option Legacy (fixed offsets, v1.3.1 engine)
        option Microtemporal (evolving voice offsets)
    boolean Microtemporal_settings 0
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    comment === Voice Parameters ===
    positive Number_of_voices 60
    real Time_offset_range_s 0.8
    real Duration_variation 0.05
    real Max_pitch_cents 15.0
    integer Random_seed_(0_=_new_each_run) 0
    comment === Output ===
    boolean Stereo_spread 1
    real Attack_fade_ms 30
    real Voice_gain 1.0
    real Wet_dry_percent 80
    optionmenu Output_level: 1
        option Peak normalize to 0.95 (v1.3.1)
        option Match source RMS (level-matched comparison)
        option None
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Check Input
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sampleRate = Get sampling frequency
originalChannels = Get number of channels

if random_seed < 0
    exitScript: "Random_seed must be 0 (new seed each run) or a positive whole number."
endif

# Setup Defaults
structure$ = "uniform"
dist_shape$ = "flat"
time_range = 0.5
pitch_max = 15
dur_var = 0.05
n_voices = 50
gain = 1.0
fade = 25
use_stereo = stereo_spread

# Microtemporal defaults (Custom and legacy presets in Microtemporal mode).
procMode = processing_mode
micro_offset_ms = 20
evolution = 7
evolution_rate_Hz = 0.2
source_divergence_ms = 0
grain_ms = 40
doppler_limit_cents = 15
rate_unit = 1
read_scatter_ms = 0
scatter_mode = 1
coherence_compensation_pct = 0
timeline = 1
isExperiment = 0
monoOut = 0
levelMode = output_level

# Apply Presets
if preset = 2
    structure$ = "uniform"
    dist_shape$ = "gaussian"
    n_voices = 60
    time_range = 0.5
    pitch_max = 8
    dur_var = 0.02
    gain = 0.8
    fade = 50
    presetName$ = "Fog"
elsif preset = 3
    structure$ = "arc_fracture"
    dist_shape$ = "flat"
    n_voices = 60
    time_range = 1.0
    pitch_max = 35
    dur_var = 0.08
    gain = 0.7
    fade = 30
    presetName$ = "Fracture"
elsif preset = 4
    structure$ = "asymmetry"
    dist_shape$ = "flat"
    n_voices = 50
    time_range = 0.6
    pitch_max = 25
    dur_var = 0.05
    gain = 0.9
    fade = 20
    use_stereo = 1
    presetName$ = "Torsion"
elsif preset = 5
    structure$ = "bimodal"
    dist_shape$ = "flat"
    n_voices = 40
    time_range = 0.8
    pitch_max = 20
    dur_var = 0.1
    gain = 0.85
    fade = 15
    presetName$ = "Bimodal"
elsif preset = 6
    structure$ = "uniform"
    dist_shape$ = "flat"
    n_voices = 40
    time_range = 1.2
    pitch_max = 12
    dur_var = 0.08
    gain = 0.8
    fade = 40
    presetName$ = "Breathing"
elsif preset >= 7 and preset <= 10
    # Controlled experiments: identical voice count, format and level
    # matching; mono; no pitch, duration, stereo or dry contribution.
    structure$ = "uniform"
    dist_shape$ = "flat"
    n_voices = 24
    pitch_max = 0
    dur_var = 0
    gain = 1.0
    fade = 20
    use_stereo = 0
    monoOut = 1
    wet_dry_percent = 100
    levelMode = 2
    procMode = 2
    isExperiment = 1
    time_range = 0
    micro_offset_ms = 0
    evolution = 1
    source_divergence_ms = 0
    evolution_rate_Hz = 0.2
    if preset = 7
        presetName$ = "ExpA_Synchronous"
    elsif preset = 8
        micro_offset_ms = 10
        evolution = 2
        presetName$ = "ExpB_StaticMicro"
    elsif preset = 9
        micro_offset_ms = 10
        evolution = 7
        presetName$ = "ExpC_EvolvingMicro"
    else
        time_range = 0.5
        presetName$ = "ExpD_MacroCloud"
    endif
elsif preset >= 11
    # Microtemporal musical presets: no pitch or duration variation, so the
    # texture changes only through the temporal relations of the voices.
    structure$ = "uniform"
    dist_shape$ = "flat"
    pitch_max = 0
    dur_var = 0
    gain = 1.0
    fade = 30
    time_range = 0
    procMode = 2
    # Rates are given in cycles over the timeline, so a short source still
    # gets a complete process. Read scatter supplies independence without a
    # pitch cost; coherence compensation keeps synchrony from acting as an
    # unintended crescendo or fade.
    rate_unit = 2
    coherence_compensation_pct = 100
    if preset = 11
        n_voices = 40
        micro_offset_ms = 20
        evolution = 3
        evolution_rate_Hz = 1
        read_scatter_ms = 40
        source_divergence_ms = 0
        presetName$ = "Emergence"
    elsif preset = 12
        n_voices = 40
        micro_offset_ms = 20
        evolution = 4
        evolution_rate_Hz = 1
        read_scatter_ms = 40
        source_divergence_ms = 0
        presetName$ = "Convergence"
    elsif preset = 13
        n_voices = 40
        micro_offset_ms = 8
        evolution = 5
        evolution_rate_Hz = 1
        read_scatter_ms = 25
        source_divergence_ms = 0
        presetName$ = "BreathingCoherence"
    else
        n_voices = 48
        micro_offset_ms = 8
        evolution = 6
        evolution_rate_Hz = 1
        read_scatter_ms = 20
        source_divergence_ms = 0
        presetName$ = "CoherenceWaves"
    endif
else
    n_voices = number_of_voices
    time_range = time_offset_range_s
    pitch_max = max_pitch_cents
    dur_var = duration_variation
    gain = voice_gain
    fade = attack_fade_ms
    presetName$ = "Custom"
endif

# Internal guards for Custom/caller-supplied values.
n_voices = round(n_voices)
if n_voices < 2
    n_voices = 2
endif
if time_range < 0
    time_range = 0
endif
if pitch_max < 0
    pitch_max = abs(pitch_max)
endif
if dur_var < 0
    dur_var = 0
endif
if dur_var >= 1
    dur_var = 0.95
endif
if gain < 0
    gain = 0
endif
if fade < 0
    fade = 0
endif

# Optional Microtemporal dialog, pre-filled with the current values.
# (Keep it unticked for batch use: newer Praat builds stop a headless
# script at a pause window.)
if procMode = 2 and microtemporal_settings = 1
    beginPause: "Ligeti Choir - Microtemporal settings"
        comment: "offset_v(t) = macro_v + micro_v(t) - divergence_v"
        real: "Micro_offset_ms", string$(micro_offset_ms)
        optionMenu: "Evolution", evolution
            option: "None (no micro offset)"
            option: "Static (fixed per voice)"
            option: "Emergence (synchronous -> independent)"
            option: "Convergence (independent -> synchronous)"
            option: "Breathing (all voices expand and contract)"
            option: "Waves (3 groups, shifted phases)"
            option: "Stochastic drift (smooth, bounded)"
        real: "Evolution_rate_Hz", string$(evolution_rate_Hz)
        optionMenu: "Rate_unit", rate_unit
            option: "Hz"
            option: "Cycles over the whole timeline"
        real: "Source_divergence_ms", string$(source_divergence_ms)
        real: "Read_scatter_ms", string$(read_scatter_ms)
        optionMenu: "Scatter_mode", scatter_mode
            option: "Free (per-grain jumps, rough, outside the Doppler limit)"
            option: "Smooth (inside the Doppler limit)"
        real: "Coherence_compensation_pct", string$(coherence_compensation_pct)
        comment: "Reconstruction"
        real: "Grain_ms", string$(grain_ms)
        real: "Doppler_limit_cents", string$(doppler_limit_cents)
        comment: "(largest pitch deviation an evolving offset may cause; 0 = no limit)"
        optionMenu: "Timeline", timeline
            option: "Preserve source duration (late material fades out)"
            option: "Extend to include late voices"
    clickedMT = endPause: "Cancel", "Continue", 2, 1
    if clickedMT = 1
        exitScript: ""
    endif
endif

if procMode = 2
    if micro_offset_ms < 0 or micro_offset_ms > 100
        exitScript: "Micro_offset_ms must be between 0 and 100 ms."
    endif
    if rate_unit = 1 and (evolution_rate_Hz < 0.01 or evolution_rate_Hz > 5)
        exitScript: "Evolution_rate_Hz must be between 0.01 and 5 Hz."
    endif
    if rate_unit = 2 and (evolution_rate_Hz < 0.1 or evolution_rate_Hz > 50)
        exitScript: "With Rate_unit = cycles, the rate must be between 0.1 and 50 cycles."
    endif
    if read_scatter_ms < 0 or read_scatter_ms > 200
        exitScript: "Read_scatter_ms must be between 0 and 200 ms."
    endif
    if coherence_compensation_pct < 0 or coherence_compensation_pct > 100
        exitScript: "Coherence_compensation_pct must be between 0 and 100."
    endif
    if source_divergence_ms < 0 or source_divergence_ms > 2000
        exitScript: "Source_divergence_ms must be between 0 and 2000 ms."
    endif
    if grain_ms < 10 or grain_ms > 200
        exitScript: "Grain_ms must be between 10 and 200 ms."
    endif
    if doppler_limit_cents < 0 or doppler_limit_cents > 200
        exitScript: "Doppler_limit_cents must be between 0 (no limit) and 200."
    endif
    if evolution = 1
        micro_offset_ms = 0
    endif
endif

# Random seed: 0 draws a new one. The seed only fixes WHICH random values
# are drawn; the distributions are those of v1.3.1.
if random_seed = 0
    random_initializeSafelyAndUnpredictably ()
    seedUsed = randomInteger (1, 999999)
    seedNote$ = "new this run"
else
    seedUsed = random_seed
    seedNote$ = "as entered"
endif
random_initializeWithSeedUnsafelyButPredictably (seedUsed)

# Set target sample rate and resample precision per speed mode.
if speed_mode = 1
    targetSR = 0
    resamplePrecision = 50
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    resamplePrecision = 10
    speedStr$ = "Balanced"
else
    targetSR = 11025
    resamplePrecision = 5
    speedStr$ = "Fast"
endif

# Clamp wet/dry
wet_dry_percent = max(0, min(100, wet_dry_percent))
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Output channels
if monoOut = 1
    outChannels = 1
elsif use_stereo = 1
    outChannels = 2
else
    outChannels = originalChannels
endif

modeName$ = "Legacy"
if procMode = 2
    modeName$ = "Microtemporal"
endif
evolName$ = "None"
if evolution = 2
    evolName$ = "Static"
elsif evolution = 3
    evolName$ = "Emergence"
elsif evolution = 4
    evolName$ = "Convergence"
elsif evolution = 5
    evolName$ = "Breathing"
elsif evolution = 6
    evolName$ = "Waves"
elsif evolution = 7
    evolName$ = "Stochastic drift"
endif
levelName$ = "Peak normalize 0.95"
if levelMode = 2
    levelName$ = "Match source RMS"
elsif levelMode = 3
    levelName$ = "None"
endif

startTime = stopwatch

# Info
writeInfoLine: "=== Ligeti Micropolyphonic Choir v2.1.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s, ",
    ... originalChannels, " ch, ", sampleRate, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Processing mode: ", modeName$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Random seed: ", seedUsed, " (", seedNote$, "; enter it to reproduce this run)"
appendInfoLine: ""
appendInfoLine: "Structure: ", structure$
appendInfoLine: "Distribution: ", dist_shape$
appendInfoLine: "Voices: ", n_voices
if procMode = 1
    appendInfoLine: "Time range: ±", fixed$(time_range, 2), " s"
else
    appendInfoLine: "Macro offset range: ±", fixed$(time_range, 3), " s (symmetric: + later, - earlier)"
    appendInfoLine: "Micro offset range: ±", fixed$(micro_offset_ms, 2), " ms, evolution: ", evolName$,
        ... " at ", fixed$(evolution_rate_Hz, 3), if rate_unit = 2 then " cycles over the timeline" else " Hz" fi
    appendInfoLine: "Read scatter: ±", fixed$(read_scatter_ms, 1), " ms;  coherence compensation: ",
        ... fixed$(coherence_compensation_pct, 0), "%"
    appendInfoLine: "Source divergence: 0 - ", fixed$(source_divergence_ms, 1), " ms read advance"
endif
appendInfoLine: "Pitch range: ±", pitch_max, " cents"
appendInfoLine: "Duration variation: ±", fixed$(dur_var * 100, 1), " % (varispeed: changes pitch too)"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: "Output level: ", levelName$
appendInfoLine: ""

# === OPTIONAL DOWNSAMPLING / CHOIR SOURCE PREP ===
workingSound = original
workingIsTemporary = 0
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: original
    Resample: targetSR, 50
    workingSound = selected("Sound")
    workingIsTemporary = 1
    workingSR = targetSR
else
    workingSR = sampleRate
endif

# A panned choir is conceptually a set of mono voices positioned in stereo.
# Convert once here instead of implicitly reading channel 1 from every voice.
# Experiments are mono throughout.
selectObject: workingSound
workingChannels = Get number of channels
if (use_stereo = 1 or monoOut = 1) and workingChannels > 1
    Convert to mono
    monoWork = selected("Sound")
    if workingIsTemporary = 1
        removeObject: workingSound
    endif
    workingSound = monoWork
    workingIsTemporary = 1
    workingChannels = 1
endif

# Store voice data for visualization
for v from 1 to n_voices
    voicePitch[v] = 0
    voiceOffset[v] = 0
    voicePan[v] = 0
endfor

selectObject: workingSound
workingDur = Get total duration
workRms = Get root-mean-square: 0, 0
if workRms = undefined
    workRms = 0
endif
workTot = workRms * sqrt(workingChannels)

if procMode = 1
    # ============================================================
    # LEGACY ENGINE (v1.3.1, unchanged)
    # ============================================================
    output_dur = workingDur + time_range + 0.5

    Create Sound from formula: "choir_output", outChannels, 0, output_dur, workingSR, "0"
    output = selected("Sound")

    appendInfoLine: "Generating ", n_voices, " voices..."

for voice from 1 to n_voices
    
    if voice mod 10 = 0
        appendInfoLine: "  Voice ", voice, " / ", n_voices
    endif
    
    selectObject: workingSound
    Copy: "voice_temp"
    voiceCopy = selected("Sound")
    
    # Reset start time
    t_start = Get start time
    if t_start <> 0
        Shift times by: -t_start
    endif
    
    # === 1. CALCULATE PANNING ===
    pan_pos = randomUniform(-1, 1)
    voicePan[voice] = pan_pos
    
    # === 2. CALCULATE PITCH DEVIATION ===
    current_pitch_cents = 0
    
    if structure$ = "uniform"
        if pitch_max <= 0
            current_pitch_cents = 0
        elsif dist_shape$ = "gaussian"
            r1 = randomUniform(-1, 1)
            r2 = randomUniform(-1, 1)
            current_pitch_cents = ((r1 + r2) / 2) * pitch_max
        else
            current_pitch_cents = randomUniform(-pitch_max, pitch_max)
        endif
    elsif structure$ = "arc_fracture"
        intensity = voice / n_voices
        current_range = pitch_max * intensity
        current_pitch_cents = randomUniform(-current_range, current_range)
    elsif structure$ = "asymmetry"
        tension = (pan_pos + 1) / 2
        current_range = pitch_max * tension
        current_pitch_cents = randomUniform(-current_range, current_range)
    elsif structure$ = "bimodal"
        if voice mod 2 = 0
            current_pitch_cents = randomUniform(5, pitch_max)
        else
            current_pitch_cents = randomUniform(-pitch_max, -5)
        endif
    endif
    
    voicePitch[voice] = current_pitch_cents

    # === 3 + 4. COMBINED PITCH SHIFT + TIME STRETCH ===
    # v1.1: both operations are SR-override + resample, so they
    # commute as multiplicative factors on the override SR.
    # combined_factor = pitch_ratio / dur_factor.
    # When this rounds to ~1, the resample is skipped entirely.
    pitch_ratio = 2 ^ (current_pitch_cents / 1200)

    if dur_var <= 0
        dur_factor = 1
    elsif dist_shape$ = "gaussian"
        raw_rand = (randomUniform(-1, 1) + randomUniform(-1, 1)) / 2
        dur_factor = 1 + (raw_rand * dur_var)
    else
        dur_factor = 1 + randomUniform(-dur_var, dur_var)
    endif

    combined_factor = pitch_ratio / dur_factor
    voiceDurF[voice] = dur_factor

    if abs(combined_factor - 1) > 0.0008
        selectObject: voiceCopy
        new_sr_combined = workingSR * combined_factor
        Override sampling frequency: new_sr_combined
        Resample: workingSR, resamplePrecision
        temp = selected("Sound")
        removeObject: voiceCopy
        voiceCopy = temp

        # If the combined operation lengthened the voice past the
        # working duration window, trim. (When dur_factor > 1 and
        # pitch_ratio < 1 — voice is both lower and longer.)
        selectObject: voiceCopy
        s_dur = Get total duration
        if s_dur > workingDur + 0.01
            Extract part: 0, workingDur, "rectangular", 1, "no"
            temp = selected("Sound")
            removeObject: voiceCopy
            voiceCopy = temp
        endif
    endif

    # === 5 + 6. ENVELOPE + GAIN ===
    # v1.1: envelope and gain are no longer applied via separate
    # full-buffer Formulas. They are folded into the mix Formula
    # below, saving two passes over the voice buffer per voice.
    # We just compute the constants here.
    gain_per_voice = gain / sqrt(n_voices)
    fade_sec = fade / 1000
    fade_samples = round(fade_sec * workingSR)
    if fade_samples < 1
        fade_samples = 1
    endif
    
    # === 7. TIME OFFSET ===
    if time_range <= 0
        offset = 0
    elsif dist_shape$ = "gaussian"
        r1 = randomUniform(-0.5, 0.5)
        r2 = randomUniform(-0.5, 0.5)
        offset = (r1 + r2) * time_range
    else
        offset = randomUniform(-time_range, time_range)
    endif
    
    voiceOffset[voice] = offset
    
    # For negative offset: trim voice start
    if offset < 0
        cut_dur = abs(offset)
        selectObject: voiceCopy
        curr_dur = Get total duration
        if cut_dur < curr_dur
            Extract part: cut_dur, curr_dur, "rectangular", 1, "no"
            v_cut = selected("Sound")
            removeObject: voiceCopy
            voiceCopy = v_cut
        endif
        voiceMixStart = 0
    else
        voiceMixStart = offset
    endif
    
    # === 8. MIX INTO OUTPUT (folded envelope + gain + mix) ===
    # v1.1: envelope and gain are folded into this Formula instead
    # of running two prior full-buffer passes. This saves 2N voice-
    # buffer scans across N voices.
    #
    # Envelope (in sample units, voice-local index vCol = col - sOff):
    #   vCol < fade_samples            -> ramp in:  vCol / fade_samples
    #   voiceNs - vCol + 1 < fade_samples -> ramp out: (voiceNs - vCol + 1) / fade_samples
    #   else                           -> 1.0
    # When fade = 0, the envelope multiplier is constant 1 and we
    # build a simpler formula.
    selectObject: voiceCopy
    voiceNs = Get number of samples

    # A symmetric attack/release should not overlap on short rendered voices.
    if fade > 0 and voiceNs > 1
        maxFadeSamples = floor(voiceNs / 2)
        if fade_samples > maxFadeSamples
            fade_samples = maxFadeSamples
        endif
        if fade_samples < 1
            fade_samples = 1
        endif
    endif

    selectObject: output
    s1 = Get sample number from time: voiceMixStart
    if s1 < 1
        s1 = 1
    endif
    s2 = s1 + voiceNs - 1
    outNs = Get number of samples
    if s2 > outNs
        s2 = outNs
    endif
    sOff = s1 - 1

    voiceEnd_t = voiceMixStart + voiceNs / workingSR
    if voiceEnd_t > output_dur
        voiceEnd_t = output_dur
    endif

    voiceIdStr$ = string$(voiceCopy)
    sOffStr$ = string$(sOff)
    gainStr$ = string$(gain_per_voice)
    voiceNsStr$ = string$(voiceNs)
    fadeNsStr$ = string$(fade_samples)

    # Build the envelope/gain suffix once; channel routing is explicit below.
    if fade > 0
        vSuffix$ = " * (if (col - " + sOffStr$ + ") < " + fadeNsStr$
            ... + " then (col - " + sOffStr$ + ") / " + fadeNsStr$
            ... + " else if (" + voiceNsStr$ + " - (col - " + sOffStr$
            ... + ") + 1) < " + fadeNsStr$
            ... + " then (" + voiceNsStr$ + " - (col - " + sOffStr$
            ... + ") + 1) / " + fadeNsStr$
            ... + " else 1 fi fi)"
            ... + " * " + gainStr$
    else
        vSuffix$ = " * " + gainStr$
    endif

    if use_stereo = 1
        # workingSound/voiceCopy is explicitly mono in stereo-spread mode.
        vRead$ = "object[" + voiceIdStr$ + ", 1, col - " + sOffStr$ + "]" + vSuffix$
        l_gain = sqrt((1 - pan_pos) / 2)
        r_gain = sqrt((1 + pan_pos) / 2)
        selectObject: output
        Formula (part): voiceMixStart, voiceEnd_t, 1, 1,
            ... "self + " + vRead$ + " * " + string$(l_gain)
        Formula (part): voiceMixStart, voiceEnd_t, 2, 2,
            ... "self + " + vRead$ + " * " + string$(r_gain)
    elsif outChannels > 1
        # Preserve corresponding source channels when stereo spreading is off.
        selectObject: output
        for ch from 1 to outChannels
            vRead$ = "object[" + voiceIdStr$ + ", " + string$(ch) + ", col - " + sOffStr$ + "]" + vSuffix$
            Formula (part): voiceMixStart, voiceEnd_t, ch, ch,
                ... "self + " + vRead$
        endfor
    else
        vRead$ = "object[" + voiceIdStr$ + ", 1, col - " + sOffStr$ + "]" + vSuffix$
        selectObject: output
        Formula (part): voiceMixStart, voiceEnd_t, 1, 1,
            ... "self + " + vRead$
    endif

    removeObject: voiceCopy

endfor
else
    @microEngine
endif

# Effective pitch of every voice: declared pitch deviation plus the pitch
# change that Duration_variation causes (it is applied as varispeed).
effMax = 0
declMax = 0
for v from 1 to n_voices
    if procMode = 1
        effC = voicePitch[v] - 1200 * log2(voiceDurF[v])
    else
        effC = 1200 * log2(voiceFactor[v])
    endif
    effMax = max(effMax, abs(effC))
    declMax = max(declMax, abs(voicePitch[v]))
endfor
appendInfoLine: ""
appendInfoLine: "Pitch: declared deviation up to ±", fixed$(declMax, 1), " cents; effective deviation incl. ",
    ... "Duration_variation (varispeed) up to ±", fixed$(effMax, 1), " cents"

# Summation coherence (diagnostic only): measured wet level against the
# level N independent voices would give with the 1/sqrt(N) gain law.
# 0 dB = voices add as unrelated signals; 10*log10(N) = fully coherent.
selectObject: output
wetRms = Get root-mean-square: 0, min(workingDur, output_dur)
outChN = Get number of channels
if wetRms = undefined
    wetRms = 0
endif
wetTot = wetRms * sqrt(outChN)
coherenceDb = undefined
if workTot > 1e-9 and gain > 0 and wetTot > 1e-12
    coherenceDb = 20 * log10(wetTot / (workTot * gain))
endif

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: ""
    appendInfoLine: "Upsampling to ", sampleRate, " Hz..."
    selectObject: output
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: output
    output = upsampledID
endif

# workingSound is no longer needed after all voice copies have been rendered.
if workingIsTemporary = 1
    removeObject: workingSound
endif

# Apply Wet/Dry Mix
if dry_level > 0
    selectObject: original
    Copy: "dry_extended"
    dryExt = selected("Sound")

    # Convert to stereo if needed
    if outChannels = 2 and originalChannels = 1
        Copy: "dry_R"
        dryR = selected("Sound")
        selectObject: dryExt, dryR
        Combine to stereo
        temp = selected("Sound")
        removeObject: dryExt, dryR
        dryExt = temp
    endif

    # Pad to output length
    selectObject: output
    finalOutputDur = Get total duration

    selectObject: dryExt
    curr_dur = Get total duration
    dryChannels = Get number of channels
    if curr_dur < finalOutputDur
        Create Sound from formula: "sil_dry", dryChannels, 0, finalOutputDur - curr_dur, sampleRate, "0"
        sil_dry = selected("Sound")
        selectObject: dryExt, sil_dry
        Concatenate
        temp = selected("Sound")
        removeObject: sil_dry, dryExt
        dryExt = temp
    endif

    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dryExt)

    selectObject: output
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$

    removeObject: dryExt
endif

# ============================================================
# OUTPUT LEVEL
# ============================================================
selectObject: output
prePeak = Get absolute extremum: 0, 0, "None"
levelNote$ = ""
levelGainDb = 0
if levelMode = 1
    # v1.3.1 behaviour (Normalize_output = 1), silence-safe.
    if prePeak > 0
        Scale peak: 0.95
        levelGainDb = 20 * log10(0.95 / prePeak)
    endif
    levelNote$ = "peak normalized to 0.95 (" + fixed$(levelGainDb, 2) + " dB)"
elsif levelMode = 2
    # Reference: total-power RMS of the original source over its whole
    # duration. Measured on the output over the same span.
    selectObject: original
    refRms = Get root-mean-square: 0, 0
    if refRms = undefined
        refRms = 0
    endif
    refTot = refRms * sqrt(originalChannels)
    selectObject: output
    outCh2 = Get number of channels
    oRms = Get root-mean-square: 0, min(originalDur, output_dur)
    if oRms = undefined
        oRms = 0
    endif
    oTot = oRms * sqrt(outCh2)
    if refTot < 1e-9 or oTot < 1e-9
        levelNote$ = "RMS matching skipped: source or output is silent"
    else
        gMatch = refTot / oTot
        gSafe = gMatch
        if prePeak * gMatch > 0.99
            gSafe = 0.99 / prePeak
        endif
        Multiply: gSafe
        levelGainDb = 20 * log10(gSafe)
        if gSafe < gMatch
            levelNote$ = "RMS match NOT reached: stopped " + fixed$(20 * log10(gMatch / gSafe), 2)
                ... + " dB below the source RMS to keep the peak at 0.99"
        else
            levelNote$ = "matched to source RMS (" + fixed$(levelGainDb, 2) + " dB applied)"
        endif
    endif
else
    levelNote$ = "no level change"
    if prePeak > 1
        levelNote$ = "no level change - OUTPUT CLIPS when saved: peak " + fixed$(prePeak, 3)
    endif
endif
selectObject: output
finalPeak = Get absolute extremum: 0, 0, "None"

Rename: originalName$ + "_ligeti_" + presetName$
result = selected("Sound")

processingTime = stopwatch - startTime

# VISUALIZATION
if procMode = 1
if draw_visualization
    # v2.0: guarded axis ranges (a 0 offset or pitch range used to stop the figure)
    vizT = max(time_range, 0.01)
    vizP = max(pitch_max, 1)
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.62
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Ligeti Micropolyphonic Choir##" + " | v1.3.1"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + string$(n_voices) + " voices"
        ... + "  |  ±" + fixed$(pitch_max, 0) + " cents"
        ... + "  |  " + speedStr$
        ... + "  |  " + fixed$(processingTime, 1) + "s"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.60, 7.70, 0.57, 1.27
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 0.57, 1.27
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Input"
    Select inner viewport: 0.60, 7.70, 0.57, 1.27
    Axes: 0, 1, 0, 1
    Text top: "no", "Source: " + originalName$

    # ----------------------------------------------------------
    # Output waveform (L blue, R orange)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.60, 7.70, 1.41, 2.11
    selectObject: result
    nChResult = Get number of channels
    if nChResult > 1
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, originalDur, 0, 0, "no", "Curve"
        selectObject: result
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, originalDur, 0, 0, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: result
        Colour: "{0.55, 0.45, 0.68}"
        Draw: 0, originalDur, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 1.41, 2.11
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Choir"
    Select inner viewport: 0.60, 7.70, 1.41, 2.11
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Output spectrogram (shows the dense micropolyphonic mass)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.22, 3.42
    Select inner viewport: 0.60, 7.70, 2.28, 3.36
    selectObject: result
    if nChResult > 1
        Extract one channel: 1
        vizSpec = selected("Sound")
    else
        Copy: "vizSpec"
        vizSpec = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, originalDur, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, vizSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 2.28, 3.36
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Hz"
    Select inner viewport: 0.60, 7.70, 2.28, 3.36
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Choir spectrogram  (micropolyphonic texture)"

    # ----------------------------------------------------------
    # Voice scatter: Pitch vs Time Offset (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 3.50, 4.90
    Select inner viewport: 0.60, 3.85, 3.58, 4.82

    Axes: -vizT, vizT, -vizP * 1.2, vizP * 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -vizT, vizT, -vizP * 1.2, vizP * 1.2

    for v from 1 to n_voices
        vR = 0.50 + voicePan[v] * 0.30
        vG = 0.50
        vB = 0.50 - voicePan[v] * 0.30
        Paint circle: "{" + fixed$(vR, 2) + ", " + fixed$(vG, 2) + ", " + fixed$(vB, 2) + "}",
            ... voiceOffset[v], voicePitch[v], vizT * 0.025
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, -vizP * 1.2, 0, vizP * 1.2
    Draw line: -vizT, 0, vizT, 0
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 3.58, 4.82
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Pitch (cents)"
    Select inner viewport: 0.60, 3.85, 3.58, 4.82
    Axes: -vizT, vizT, -vizP * 1.2, vizP * 1.2
    Text bottom: "yes", "Time offset (s)"
    Text top: "no", "Voice cloud  (colour = pan)"

    # ----------------------------------------------------------
    # Voice scatter: Pan vs Pitch (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 3.50, 4.90
    Select inner viewport: 4.45, 7.70, 3.58, 4.82

    Axes: -1.2, 1.2, -vizP * 1.2, vizP * 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.2, 1.2, -vizP * 1.2, vizP * 1.2

    for v from 1 to n_voices
        vR = 0.50 + voicePan[v] * 0.30
        vG = 0.50
        vB = 0.50 - voicePan[v] * 0.30
        Paint circle: "{" + fixed$(vR, 2) + ", " + fixed$(vG, 2) + ", " + fixed$(vB, 2) + "}",
            ... voicePan[v], voicePitch[v], 0.04
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, -vizP * 1.2, 0, vizP * 1.2
    Draw line: -1.2, 0, 1.2, 0
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select inner viewport: 4.05, 4.33, 3.58, 4.82
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Pitch (cents)"
    Select inner viewport: 4.45, 7.70, 3.58, 4.82
    Axes: -1.2, 1.2, -vizP * 1.2, vizP * 1.2
    Text bottom: "yes", "Pan (L ← → R)"
    Text top: "no", "Stereo field"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.05, 6.05
    Select inner viewport: 0.60, 7.70, 5.12, 5.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", 
        ... "Preset: " + presetName$
        ... + "  |  Structure: " + structure$
        ... + "  |  Voices: " + string$(n_voices)
        ... + "  |  Pitch: ±" + fixed$(pitch_max, 0) + " ct"
        ... + "  |  Time: ±" + fixed$(time_range, 2) + " s"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", 
        ... "Wet/Dry: " + string$(wet_dry_percent) + "\%  "
        ... + "  |  Gain: " + fixed$(gain, 2)
        ... + "  |  Fade: " + string$(fade) + " ms"
        ... + "  |  " + speedStr$
        ... + "  |  Render: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"

    Select inner viewport: 0.60, 7.70, 5.12, 5.98
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 6.15
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif
else
    if draw_visualization
        @microViz
    endif
endif

# Final Info
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Levels ==="
if coherenceDb <> undefined
    appendInfoLine: "Summation coherence: ", fixed$(coherenceDb, 2), " dB above independent voices (0 = unrelated, ",
        ... fixed$(10 * log10(n_voices), 2), " = all identical)"
endif
appendInfoLine: "Output level: ", levelNote$
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", selected$("Sound")

# Play
if play_result
    Play
endif

selectObject: result

# ============================================================
# MICROTEMPORAL ENGINE
# ============================================================
procedure microEngine
    # Grain geometry (even L so the two streams interleave exactly).
    mtL = 2 * round(grain_ms / 1000 * workingSR / 2)
    if mtL < 8
        mtL = 8
    endif
    mtH = mtL / 2
    mtF = max(1, round(fade / 1000 * workingSR))
    mtM = micro_offset_ms / 1000
    mtS = source_divergence_ms / 1000

    # ---- 1. Voice parameters (fixed draw order per voice) ----
    nCP = 0
    for v from 1 to n_voices
        pan_pos = randomUniform(-1, 1)
        voicePan[v] = pan_pos
        current_pitch_cents = 0
        if structure$ = "uniform"
            if pitch_max <= 0
                current_pitch_cents = 0
            elsif dist_shape$ = "gaussian"
                r1 = randomUniform(-1, 1)
                r2 = randomUniform(-1, 1)
                current_pitch_cents = ((r1 + r2) / 2) * pitch_max
            else
                current_pitch_cents = randomUniform(-pitch_max, pitch_max)
            endif
        elsif structure$ = "arc_fracture"
            intensity = v / n_voices
            current_range = pitch_max * intensity
            current_pitch_cents = randomUniform(-current_range, current_range)
        elsif structure$ = "asymmetry"
            tension = (pan_pos + 1) / 2
            current_range = pitch_max * tension
            current_pitch_cents = randomUniform(-current_range, current_range)
        elsif structure$ = "bimodal"
            if v mod 2 = 0
                current_pitch_cents = randomUniform(5, pitch_max)
            else
                current_pitch_cents = randomUniform(-pitch_max, -5)
            endif
        endif
        voicePitch[v] = current_pitch_cents
        if dur_var <= 0
            dur_factor = 1
        elsif dist_shape$ = "gaussian"
            raw_rand = (randomUniform(-1, 1) + randomUniform(-1, 1)) / 2
            dur_factor = 1 + (raw_rand * dur_var)
        else
            dur_factor = 1 + randomUniform(-dur_var, dur_var)
        endif
        voiceFactor[v] = 2 ^ (current_pitch_cents / 1200) / dur_factor
        if time_range <= 0
            offset = 0
        elsif dist_shape$ = "gaussian"
            r1 = randomUniform(-0.5, 0.5)
            r2 = randomUniform(-0.5, 0.5)
            offset = (r1 + r2) * time_range
        else
            offset = randomUniform(-time_range, time_range)
        endif
        voiceOffset[v] = offset
        voiceStatic[v] = randomUniform(-1, 1)
        voiceSigma[v] = randomUniform(0, 1) * mtS
    endfor

    # Timeline length.
    maxLate = 0
    for v from 1 to n_voices
        maxLate = max(maxLate, voiceOffset[v] + mtM - voiceSigma[v])
    endfor
    if timeline = 1
        output_dur = workingDur
    else
        output_dur = workingDur + maxLate + mtF / workingSR
    endif
    Create Sound from formula: "choir_output", outChannels, 0, output_dur, workingSR, "0"
    output = selected("Sound")
    outNs = Get number of samples
    mtT = outNs / workingSR

    # Evolution rate: in Hz, or as a number of cycles over the timeline.
    if rate_unit = 2
        mtRate = evolution_rate_Hz / mtT
    else
        mtRate = evolution_rate_Hz
    endif
    # Smooth stochastic control points (one every 1/rate seconds).
    nCP = ceiling(mtT * mtRate) + 2
    cp# = zero#(n_voices * nCP)
    for v from 1 to n_voices
        for j from 1 to nCP
            cp#[(v - 1) * nCP + j] = randomUniform(-1, 1)
        endfor
    endfor

    # ---- 2. Displacement table: one value per grain and stream ----
    # Half-hop grid q = 1..Q, centre time (q-1)*H/fs. Odd q = stream 1
    # grain (q+1)/2, even q = stream 0 grain q/2.
    mtK = ceiling(outNs / mtL) + 2
    mtQ = 2 * mtK
    tab = Create simple Matrix: "mt_displacement", 2 * n_voices, mtK, "0"
    # Largest displacement step between neighbouring grains (crossfade of
    # mtH samples) for the requested Doppler limit, in whole samples. One
    # sample per crossfade is the finest step possible.
    stepFloor = 0
    if doppler_limit_cents > 0
        # sin^2 crossfade: the phase moves fastest mid-crossfade, pi/2 times
        # the average rate, so the limit is applied to that peak.
        maxStepI = floor((1 - 2 ^ (-doppler_limit_cents / 1200)) * mtH * 2 / pi)
        if maxStepI < 1
            maxStepI = 1
            stepFloor = 1
        endif
    else
        maxStepI = 1e9
    endif
    dispMin# = zero#(mtQ)
    dispMax# = zero#(mtQ)
    dispSum# = zero#(mtQ)
    dispSq# = zero#(mtQ)
    for q from 1 to mtQ
        dispMin#[q] = 1e9
        dispMax#[q] = -1e9
    endfor
    nShow = min(n_voices, 10)
    showD# = zero#(nShow * mtQ)
    maxUsedStep = 0
    planDiffCount = 0
    planDiffMax = 0
    endConflict = 0
    stepCount = 0
    # Grid point at the end of the timeline: the endpoint of every trajectory.
    qEnd = min(mtQ, 1 + round(outNs / mtH))
    # Frames for coherence compensation (50 ms).
    frameDur = 0.05
    nFr = max(1, ceiling(mtT / frameDur))
    fD# = zero#(n_voices * nFr)
    des# = zero#(mtQ)
    trj# = zero#(mtQ)
    env# = zero#(mtQ)
    scat# = zero#(mtQ)
    depthMin = 1
    depthReduced = 0
    maxScatJump = 0
    for v from 1 to n_voices
        # 1. independence envelope and this voice's scatter values (drawn
        #    once; Free = added after the slew limit, Smooth = part of the
        #    planned trajectory and therefore inside the Doppler limit)
        for q from 1 to mtQ
            tq = min((q - 1) * mtH / workingSR, mtT)
            @trajectory: v, tq
            env#[q] = trajectory.e
            uq[q] = trajectory.u
            scat#[q] = 0
            if read_scatter_ms > 0
                scat#[q] = env#[q] * read_scatter_ms / 1000 * workingSR * randomUniform(-1, 1)
            endif
        endfor
        # 2. Plan, then limit. If the limit cannot reach the END from the
        #    START, the evolving part is made shallower until it can:
        #    both endpoints stay exact and the reduction is reported.
        depth = 1
        feasible = 0
        while feasible = 0
            for q from 1 to mtQ
                des#[q] = (voiceOffset[v] - voiceSigma[v]) * workingSR + depth * mtM * uq[q] * workingSR
                if scatter_mode = 2
                    des#[q] = des#[q] + depth * scat#[q]
                endif
            endfor
            trj#[1] = round(des#[1])
            for q from 2 to mtQ
                dI = round(des#[q])
                stp = dI - trj#[q - 1]
                if abs(stp) > maxStepI
                    dI = trj#[q - 1] + maxStepI * (if stp > 0 then 1 else -1 fi)
                endif
                trj#[q] = dI
            endfor
            trj#[qEnd] = round(des#[qEnd])
            for q from qEnd + 1 to mtQ
                trj#[q] = trj#[qEnd]
            endfor
            for jb from 1 to qEnd - 1
                q = qEnd - jb
                trj#[q] = min(max(trj#[q], trj#[q + 1] - maxStepI), trj#[q + 1] + maxStepI)
            endfor
            if trj#[1] = round(des#[1]) or depth < 0.02
                feasible = 1
            else
                depth = depth * 0.85
            endif
        endwhile
        if depth < 1
            depthReduced += 1
            depthMin = min(depthMin, depth)
        endif
        if trj#[1] <> round(des#[1])
            endConflict += 1
        endif
        for q from 1 to qEnd
            dv = abs(trj#[q] - round(des#[q]))
            if dv > 0
                planDiffCount += 1
                planDiffMax = max(planDiffMax, dv)
            endif
            if q > 1
                maxUsedStep = max(maxUsedStep, abs(trj#[q] - trj#[q - 1]))
            endif
            stepCount += 1
        endfor
        # 3. store (Free scatter is added here, outside the limit)
        prevTot = 0
        for q from 1 to mtQ
            dI = trj#[q]
            if scatter_mode = 1 and read_scatter_ms > 0
                dI = dI + round(depth * scat#[q])
            endif
            if q > 1 and q <= qEnd
                maxScatJump = max(maxScatJump, abs(dI - prevTot))
            endif
            prevTot = dI
            if q mod 2 = 1
                selectObject: tab
                Set value: 2 * v, (q + 1) / 2, dI
            else
                selectObject: tab
                Set value: 2 * v - 1, q / 2, dI
            endif
            dMs = 1000 * dI / workingSR
            dispMin#[q] = min(dispMin#[q], dMs)
            dispMax#[q] = max(dispMax#[q], dMs)
            dispSum#[q] = dispSum#[q] + dMs
            dispSq#[q] = dispSq#[q] + dMs ^ 2
            if v <= nShow
                showD#[(v - 1) * mtQ + q] = dMs
            endif
            for pp from 1 to 5
                qp = 1 + round((pp - 1) / 4 * (qEnd - 1))
                if q = qp
                    rep[v, pp] = dMs
                endif
            endfor
            tdI[q] = dI
        endfor
        # displacement at each compensation frame centre
        for fr from 1 to nFr
            qf = min(mtQ, 1 + round((fr - 0.5) * frameDur * workingSR / mtH))
            fD#[(v - 1) * nFr + fr] = tdI[qf]
        endfor
    endfor
    # Peak instantaneous deviation over a sin^2 crossfade (pi/2 x average).
    dopplerCents = 1200 * log2(1 + pi / 2 * maxUsedStep / mtH)

    # ---- 3. Render: one Formula per voice over the whole buffer ----
    appendInfoLine: "Rendering ", n_voices, " voices (overlap-add, grain ", fixed$(1000 * mtL / workingSR, 1),
        ... " ms = ", mtL, " samples, hop ", mtH, ")..."
    tab$ = string$(tab)
    gL$ = string$(mtL)
    gH$ = string$(mtH)
    gF$ = string$(mtF)
    # Shared per-sample helpers (identical for every voice): stream-0
    # window and the grain index of each stream.
    winS = Create Sound from formula: "mt_win", 1, 0, output_dur, workingSR,
        ... "sin(pi * ((col - 1) mod " + gL$ + ") / " + gL$ + ") ^ 2"
    kaS = Create Sound from formula: "mt_ka", 1, 0, output_dur, workingSR,
        ... "floor((col - 1) / " + gL$ + ") + 1"
    kbS = Create Sound from formula: "mt_kb", 1, 0, output_dur, workingSR,
        ... "floor((col - 1 + " + gH$ + ") / " + gL$ + ") + 1"
    w$ = "object[" + string$(winS) + ", 1, col]"
    # The read-position fade depends only on the position in the source, so
    # it is applied to the source once instead of per output sample.
    selectObject: workingSound
    fadedWork = Copy: "mt_src_faded"
    wNs = Get number of samples
    Formula: "self * max(0, min(1, (col - 0.5) / " + gF$ + ", (" + string$(wNs) + " - col + 0.5) / " + gF$ + "))"
    gainPerVoice = gain / sqrt(n_voices)
    expPow# = zero#(nFr)
    for v from 1 to n_voices
        # Pitch / duration variation: the v1.3.1 single combined resample.
        if abs(voiceFactor[v] - 1) > 0.0008
            selectObject: workingSound
            vSrc = Copy: "voice_src"
            Override sampling frequency: workingSR * voiceFactor[v]
            vRes = Resample: workingSR, resamplePrecision
            removeObject: vSrc
            vSrc = vRes
            vNs = Get number of samples
            Formula: "self * max(0, min(1, (col - 0.5) / " + gF$ + ", (" + string$(vNs) + " - col + 0.5) / " + gF$ + "))"
            vTemp = 1
        else
            vSrc = fadedWork
            vTemp = 0
        endif
        src$ = string$(vSrc)
        gD0$ = "object[" + tab$ + ", " + string$(2 * v - 1) + ", object[" + string$(kaS) + ", 1, col]]"
        gD1$ = "object[" + tab$ + ", " + string$(2 * v) + ", object[" + string$(kbS) + ", 1, col]]"
        if use_stereo = 1 and monoOut = 0
            rowSel$ = "1"
            l_gain = sqrt((1 - voicePan[v]) / 2)
            r_gain = sqrt((1 + voicePan[v]) / 2)
            pan$ = " * (if row = 1 then " + fixed$(l_gain, 10) + " else " + fixed$(r_gain, 10) + " fi)"
        elsif outChannels > 1
            rowSel$ = "row"
            pan$ = ""
        else
            rowSel$ = "1"
            pan$ = ""
        endif
        # Expected (independent-voice) power of this voice in each frame:
        # the source power at the voice's read position.
        if coherence_compensation_pct > 0
            selectObject: vSrc
            vT2 = Get end time
            if use_stereo = 1 and monoOut = 0
                chanF = 1
            else
                chanF = outChannels
            endif
            for fr from 1 to nFr
                tA = (fr - 1) * frameDur - fD#[(v - 1) * nFr + fr] / workingSR
                tB = tA + frameDur
                if tB > 0 and tA < vT2
                    rr = Get root-mean-square: max(0, tA), min(vT2, tB)
                    if rr <> undefined
                        expPow#[fr] = expPow#[fr] + gainPerVoice ^ 2 * rr ^ 2 * chanF
                    endif
                endif
            endfor
        endif
        selectObject: output
        Formula: "self + " + fixed$(gainPerVoice, 12) + " * (" + w$ + " * object[" + src$ + ", " + rowSel$
            ... + ", col - " + gD0$ + "] + (1 - " + w$ + ") * object[" + src$ + ", " + rowSel$
            ... + ", col - " + gD1$ + "])" + pan$
        if vTemp = 1
            removeObject: vSrc
        endif
    endfor
    removeObject: winS, kaS, kbS, fadedWork

    # ---- Coherence compensation ----
    # Voices that are nearly synchronous add coherently (up to +10log10 N dB),
    # voices that drift apart can cancel. The expected level of N
    # INDEPENDENT voices follows the source's own dynamics; the measured
    # level differs from it by the coherence. A slow gain (50 ms frames,
    # smoothed, at most 10log10(N)+2 dB) removes Compensation % of that difference,
    # leaving the source dynamics in place.
    cohBeforeMin = undefined
    cohBeforeMax = undefined
    cohAfterMin = undefined
    cohAfterMax = undefined
    compMinDb = 0
    compMaxDb = 0
    if coherence_compensation_pct > 0
        selectObject: output
        nchO = Get number of channels
        actPow# = zero#(nFr)
        valid# = zero#(nFr)
        expMax = 0
        for fr from 1 to nFr
            expMax = max(expMax, expPow#[fr])
        endfor
        cohDb# = zero#(nFr)
        for fr from 1 to nFr
            tA = (fr - 1) * frameDur
            tB = min(mtT, tA + frameDur)
            rr = Get root-mean-square: tA, tB
            if rr <> undefined
                actPow#[fr] = rr ^ 2 * nchO
            endif
            if expPow#[fr] > expMax * 1e-6 and actPow#[fr] > expMax * 1e-9
                valid#[fr] = 1
                cohDb#[fr] = 10 * log10(actPow#[fr] / expPow#[fr])
            endif
        endfor
        # Clamp: full synchrony of N voices is +10log10(N) dB, so the gain
        # may reach that (plus 2 dB) but no further.
        compClamp = max(12, 10 * log10(n_voices) + 2)
        gDb# = zero#(nFr)
        for fr from 1 to nFr
            if valid#[fr] = 1
                gDb#[fr] = max(-compClamp, min(compClamp, -coherence_compensation_pct / 100 * cohDb#[fr]))
            endif
        endfor
        # 3-frame smoothing
        gS# = zero#(nFr)
        for fr from 1 to nFr
            gS#[fr] = (gDb#[max(1, fr - 1)] + 2 * gDb#[fr] + gDb#[min(nFr, fr + 1)]) / 4
        endfor
        compMinDb = 0
        compMaxDb = 0
        for fr from 1 to nFr
            compMinDb = min(compMinDb, gS#[fr])
            compMaxDb = max(compMaxDb, gS#[fr])
        endfor
        gEnv = Create Sound from formula: "mt_gain", 1, 0, nFr * frameDur, 1 / frameDur, "0"
        for fr from 1 to nFr
            Set value at sample number: 1, fr, 10 ^ (gS#[fr] / 20)
        endfor
        gE$ = string$(gEnv)
        nFr$ = string$(nFr)
        pos$ = "(x / " + fixed$(frameDur, 6) + " + 0.5)"
        selectObject: output
        Formula: "self * (object[" + gE$ + ", 1, max(1, min(" + nFr$ + ", floor(" + pos$ + ")))] * (1 - ("
            ... + pos$ + " - floor(" + pos$ + "))) + object[" + gE$ + ", 1, max(1, min(" + nFr$
            ... + ", floor(" + pos$ + ") + 1))] * (" + pos$ + " - floor(" + pos$ + ")))"
        removeObject: gEnv
        # frame coherence before and after
        cohBeforeMin = 1e9
        cohBeforeMax = -1e9
        cohAfterMin = 1e9
        cohAfterMax = -1e9
        selectObject: output
        for fr from 1 to nFr
            if valid#[fr] = 1
                tA = (fr - 1) * frameDur
                tB = min(mtT, tA + frameDur)
                rr = Get root-mean-square: tA, tB
                ca = 10 * log10(max(rr ^ 2 * nchO, 1e-30) / expPow#[fr])
                cohBeforeMin = min(cohBeforeMin, cohDb#[fr])
                cohBeforeMax = max(cohBeforeMax, cohDb#[fr])
                cohAfterMin = min(cohAfterMin, ca)
                cohAfterMax = max(cohAfterMax, ca)
            endif
        endfor
    endif

    # Edge fades of the output timeline (voices that read ahead start
    # mid-material at 0; late voices are cut at the end when preserved).
    selectObject: output
    Formula: "self * min(1, (col - 0.5) / " + gF$ + ", (" + string$(outNs) + " - col + 0.5) / " + gF$ + ")"

    # Material lost at the end when the timeline is preserved.
    cutMax = 0
    for v from 1 to n_voices
        cutMax = max(cutMax, rep[v, 5])
    endfor

    removeObject: tab

    # ---- 4. Report ----
    appendInfoLine: ""
    appendInfoLine: "=== Microtemporal reconstruction ==="
    appendInfoLine: "Overlap-add, 2 streams, sin^2 windows (sum = 1), integer displacement per grain"
    appendInfoLine: "Grain ", mtL, " samples (", fixed$(1000 * mtL / workingSR, 2), " ms), hop ", mtH,
        ... " samples, ", mtK, " grains per stream, working rate ", workingSR, " Hz"
    appendInfoLine: "Largest trajectory step between neighbouring grains: ", maxUsedStep, " samples (",
        ... fixed$(1000 * maxUsedStep / workingSR, 3), " ms)"
    appendInfoLine: "Largest resulting pitch deviation (Doppler, peak within a crossfade): ", fixed$(dopplerCents, 2), " cents",
        ... if doppler_limit_cents > 0 then " (limit " + fixed$(doppler_limit_cents, 1) + ")" else " (no limit)" fi
    if stepFloor = 1
        appendInfoLine: "NOTE: at ", workingSR, " Hz one sample per crossfade already exceeds the Doppler limit; steps are held to 1 sample (",
            ... fixed$(1200 * log2(1 + pi / 2 / mtH), 1), " cents). Use Full Quality or a longer grain for finer steps."
    endif
    appendInfoLine: "Evolution rate: ", fixed$(mtRate, 4), " Hz (", fixed$(mtRate * mtT, 2), " cycles over ",
        ... fixed$(mtT, 2), " s)"
    if depthReduced > 0
        appendInfoLine: "NOTE: for ", depthReduced, " of ", n_voices, " voices the requested evolution could not",
            ... " run from start to end within the Doppler limit in ", fixed$(mtT, 2), " s; its depth was reduced",
            ... " (to ", fixed$(100 * depthMin, 0), "% at most) so that BOTH endpoints stay exact."
        appendInfoLine: "      For the full depth: a longer source, a smaller Micro_offset_ms or a higher Doppler_limit_cents."
    endif
    if endConflict > 0
        appendInfoLine: "WARNING: ", endConflict, " voice(s) still miss their start state (timeline too short even at 2% depth)."
    endif
    if planDiffCount > 0
        appendInfoLine: "Doppler limit: the rendered trajectory differs from the plan on ",
            ... fixed$(100 * planDiffCount / stepCount, 1), "% of grains (at most ",
            ... fixed$(1000 * planDiffMax / workingSR, 2), " ms)",
            ... if endConflict = 0 then "; start and end are exactly on plan" else "" fi
    else
        appendInfoLine: "Trajectories rendered exactly as planned (Doppler limit not reached)"
    endif
    if read_scatter_ms > 0
        if scatter_mode = 1
            appendInfoLine: "Read scatter (Free): ±", fixed$(read_scatter_ms, 1), " ms per grain, independent per voice,",
                ... " scaled by the evolution envelope. NOT covered by the Doppler figure: jumps up to ",
                ... fixed$(1000 * maxScatJump / workingSR, 2), " ms between neighbouring grains, i.e. phase jumps"
            appendInfoLine: "      (no systematic pitch shift, but strong per-grain pitch jitter on tonal material)"
        else
            appendInfoLine: "Read scatter (Smooth): ±", fixed$(read_scatter_ms, 1), " ms target per grain, part of the",
                ... " trajectory, so inside the Doppler limit (largest step ", fixed$(1000 * maxScatJump / workingSR, 3), " ms)"
        endif
    endif
    if coherence_compensation_pct > 0 and cohBeforeMin = 1e9
        appendInfoLine: "Coherence compensation: not available - no frame carries signal (silent source?); no gain applied"
        cohBeforeMin = undefined
    elsif coherence_compensation_pct > 0
        appendInfoLine: "Coherence compensation ", fixed$(coherence_compensation_pct, 0), "%: frame coherence ",
            ... fixed$(cohBeforeMin, 1), " .. ", fixed$(cohBeforeMax, 1), " dB before, ",
            ... fixed$(cohAfterMin, 1), " .. ", fixed$(cohAfterMax, 1), " dB after; gain ",
            ... fixed$(compMinDb, 1), " .. +", fixed$(compMaxDb, 1), " dB"
    endif
    if timeline = 1
        appendInfoLine: "Timeline: source duration preserved (", fixed$(mtT, 3), " s); up to ",
            ... fixed$(max(0, cutMax), 1), " ms of late material fades out at the end"
    else
        appendInfoLine: "Timeline: extended to ", fixed$(mtT, 3), " s to include late voices"
    endif
    appendInfoLine: ""
    appendInfoLine: "Displacement (ms, + = later) at 0 / 25 / 50 / 75 / 100 % of the timeline"
    appendInfoLine: "  voice  pitch c   pan   macro ms  static  diverg ms |      0%     25%     50%     75%    100%"
    for v from 1 to min(n_voices, 12)
        @padL: string$(v), 7
        a$ = padL$
        @fmt: voicePitch[v], 1
        @padL: fmt$, 9
        b$ = padL$
        @fmt: voicePan[v], 2
        @padL: fmt$, 6
        c$ = padL$
        @fmt: 1000 * voiceOffset[v], 1
        @padL: fmt$, 10
        d$ = padL$
        @fmt: voiceStatic[v], 2
        @padL: fmt$, 8
        e$ = padL$
        @fmt: 1000 * voiceSigma[v], 1
        @padL: fmt$, 10
        f$ = padL$
        line$ = a$ + b$ + c$ + d$ + e$ + f$ + " |"
        for pp from 1 to 5
            @fmt: rep[v, pp], 2
            @padL: fmt$, 8
            line$ = line$ + padL$
        endfor
        appendInfoLine: line$
    endfor
    if n_voices > 12
        appendInfoLine: "  (", n_voices - 12, " more voices not listed)"
    endif
    d0$ = ""
    for v from 1 to n_voices
        d0$ = d0$ + " " + string$(round(rep[v, 1] * workingSR / 1000))
    endfor
    appendInfoLine: "Displacement at the start, every voice (samples):", d0$
    appendInfoLine: "Spread across all voices (standard deviation, ms):"
    sd$ = ""
    for pp from 1 to 5
        qp = 1 + round((pp - 1) / 4 * (qEnd - 1))
        mu = dispSum#[qp] / n_voices
        sdv = sqrt(max(0, dispSq#[qp] / n_voices - mu ^ 2))
        @fmt: sdv, 2
        @padL: fmt$, 8
        sd$ = sd$ + padL$
    endfor
    appendInfoLine: "                                                       ", sd$
endproc

# Normalised trajectory u in [-1, 1] for voice v at time t, and the
# independence envelope e in [0, 1] that also scales the read scatter.
procedure trajectory: .v, .t
    .u = 0
    .e = 1
    if evolution = 2
        .u = voiceStatic[.v]
    elsif evolution = 3 or evolution = 4 or evolution = 7
        # smooth stochastic drift between control points (smoothstep)
        .x = .t * mtRate
        .j = floor(.x)
        .a = .x - .j
        .s = .a * .a * (3 - 2 * .a)
        .base = (.v - 1) * nCP
        .c0 = cp#[.base + min(.j + 1, nCP)]
        .c1 = cp#[.base + min(.j + 2, nCP)]
        .drift = .c0 + (.c1 - .c0) * .s
        if evolution = 7
            .u = .drift
        else
            .ramp = 0.5 - 0.5 * cos(pi * min(1, .t / mtT))
            if evolution = 3
                .e = .ramp
            else
                .e = 1 - .ramp
            endif
            .u = .e * .drift
        endif
    elsif evolution = 5
        .e = 0.5 - 0.5 * cos(2 * pi * mtRate * .t)
        .u = .e * voiceStatic[.v]
    elsif evolution = 6
        # three groups peak in succession, 60 degrees apart, so the mass as
        # a whole still expands and contracts (120 degrees would sum to a
        # constant)
        .g = (.v - 1) mod 3
        .e = 0.5 - 0.5 * cos(2 * pi * mtRate * .t - pi * .g / 3)
        .u = .e * voiceStatic[.v]
    endif
    trajectory.u = .u
    trajectory.e = .e
endproc

# ============================================================
# MICROTEMPORAL VISUALIZATION
# ============================================================
procedure microViz
    Erase all
    labelX = -0.035
    labelFont = 7
    @vizSafe: originalName$
    vName$ = vizSafe$

    # Title
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.05, 0.30
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Ligeti Micropolyphonic Choir##" + " | v2.1.1 | Microtemporal"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.30, 0.48
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.5, "half",
        ... vName$ + "  |  " + presetName$
        ... + "  |  " + string$(n_voices) + " voices"
        ... + "  |  micro ±" + fixed$(micro_offset_ms, 1) + " ms " + evolName$
        ... + "  |  seed " + string$(seedUsed)
        ... + "  |  " + speedStr$

    # Input waveform
    selectObject: original
    inPk = Get absolute extremum: 0, 0, "None"
    selectObject: result
    outPk = Get absolute extremum: 0, 0, "None"
    resDur = Get total duration
    vPk = max(outPk, 1e-6) * 1.05
    vPkIn = max(inPk, 1e-6) * 1.05
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.72, 1.32
    Axes: 0, resDur, -vPkIn, vPkIn
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, resDur, -vPkIn, vPkIn, "no", "Curve"
    Select inner viewport: 0.60, 7.70, 0.72, 1.32
    Axes: 0, 1, 0, 1
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Input"
    Select inner viewport: 0.60, 7.70, 0.72, 1.32
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text top: "no", "Source: " + vName$ + "  (own amplitude scale)"
    Select inner viewport: 0.60, 7.70, 0.72, 1.32
    Axes: 0, resDur, -vPkIn, vPkIn
    Draw inner box

    # Output waveform
    Select inner viewport: 0.60, 7.70, 1.52, 2.12
    Axes: 0, resDur, -vPk, vPk
    selectObject: result
    nChR = Get number of channels
    if nChR > 1
        cL = Extract one channel: 1
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, resDur, -vPk, vPk, "no", "Curve"
        selectObject: result
        cR = Extract one channel: 2
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, resDur, -vPk, vPk, "no", "Curve"
        removeObject: cL, cR
    else
        Colour: "{0.55, 0.45, 0.68}"
        Draw: 0, resDur, -vPk, vPk, "no", "Curve"
    endif
    Select inner viewport: 0.60, 7.70, 1.52, 2.12
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Choir"
    Select inner viewport: 0.60, 7.70, 1.52, 2.12
    Axes: 0, resDur, -vPk, vPk
    Draw inner box

    # Spectrogram
    selectObject: result
    if nChR > 1
        vizSpec = Extract one channel: 1
    else
        vizSpec = Copy: "vizSpec"
    endif
    specOut = To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    Select inner viewport: 0.60, 7.70, 2.32, 3.22
    Axes: 0, resDur, 0, 5000
    Paint: 0, resDur, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, vizSpec
    Select inner viewport: 0.60, 7.70, 2.32, 3.22
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: labelX, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Hz"
    Select inner viewport: 0.60, 7.70, 2.32, 3.22
    Axes: 0, 1, 0, 1
    Text top: "no", "Choir spectrogram  (0 - 5 kHz)"
    Select inner viewport: 0.60, 7.70, 2.32, 3.22
    Axes: 0, resDur, 0, 5000
    Draw inner box
    Marks bottom every: 1, if resDur > 8 then 2 else 0.5 fi, "yes", "yes", "no"

    # Displacement range for both lower panels (from the rendered table)
    yLo = 1e9
    yHi = -1e9
    for q from 1 to mtQ
        yLo = min(yLo, dispMin#[q])
        yHi = max(yHi, dispMax#[q])
    endfor
    if yHi - yLo < 1
        yLo = yLo - 0.5
        yHi = yHi + 0.5
    endif
    yPad = (yHi - yLo) * 0.08
    yLo = yLo - yPad
    yHi = yHi + yPad
    tEndQ = (mtQ - 1) * mtH / workingSR
    tShow = min(tEndQ, resDur)
    @niceStep: (yHi - yLo) / 4
    yStep = niceStep.v
    @niceStep: tShow / 4
    tStep = niceStep.v

    # Trajectories (left)
    Font size: 6
    Select inner viewport: 0.60, 3.85, 3.62, 4.82
    Axes: 0, tShow, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, tShow, yLo, yHi
    for v from 1 to nShow
        cFrac = (v - 1) / max(nShow - 1, 1)
        Colour: "{" + fixed$(0.20 + 0.65 * cFrac, 2) + ", 0.35, " + fixed$(0.80 - 0.60 * cFrac, 2) + "}"
        for q from 2 to mtQ
            t1 = (q - 2) * mtH / workingSR
            t2 = (q - 1) * mtH / workingSR
            if t2 <= tShow
                Draw line: t1, showD#[(v - 1) * mtQ + q - 1], t2, showD#[(v - 1) * mtQ + q]
            endif
        endfor
    endfor
    Colour: "{0.70, 0.70, 0.70}"
    Dotted line
    if yLo < 0 and yHi > 0
        Draw line: 0, 0, tShow, 0
    endif
    Solid line
    Select inner viewport: 0.60, 3.85, 3.62, 4.82
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: labelX - 0.05, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Offset (ms)"
    Select inner viewport: 0.60, 3.85, 3.62, 4.82
    Axes: 0, 1, 0, 1
    Text top: "no", "##Temporal trajectories## (first " + string$(nShow) + " voices, as rendered)"
    Select inner viewport: 0.60, 3.85, 3.62, 4.82
    Axes: 0, tShow, yLo, yHi
    Draw inner box
    Marks left every: 1, yStep, "yes", "yes", "no"
    Marks bottom every: 1, tStep, "yes", "yes", "no"

    # Dispersion (right): min-max band and +/- one standard deviation
    Select inner viewport: 4.45, 7.70, 3.62, 4.82
    Axes: 0, tShow, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, tShow, yLo, yHi
    for q from 2 to mtQ
        t1 = (q - 2) * mtH / workingSR
        t2 = (q - 1) * mtH / workingSR
        if t2 <= tShow
            Paint rectangle: "{0.82, 0.86, 0.94}", t1, t2, dispMin#[q], dispMax#[q]
        endif
    endfor
    Colour: "{0.20, 0.30, 0.65}"
    Line width: 1.5
    for q from 2 to mtQ
        t1 = (q - 2) * mtH / workingSR
        t2 = (q - 1) * mtH / workingSR
        if t2 <= tShow
            m1 = dispSum#[q - 1] / n_voices
            m2 = dispSum#[q] / n_voices
            s1 = sqrt(max(0, dispSq#[q - 1] / n_voices - m1 ^ 2))
            s2 = sqrt(max(0, dispSq#[q] / n_voices - m2 ^ 2))
            Draw line: t1, m1 + s1, t2, m2 + s2
            Draw line: t1, m1 - s1, t2, m2 - s2
        endif
    endfor
    Line width: 1
    Select inner viewport: 4.45, 7.70, 3.62, 4.82
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text top: "no", "##Temporal dispersion## (band = all voices, lines = mean ± SD)"
    Select inner viewport: 4.45, 7.70, 3.62, 4.82
    Axes: 0, tShow, yLo, yHi
    Draw inner box
    Marks left every: 1, yStep, "yes", "yes", "no"
    Marks bottom every: 1, tStep, "yes", "yes", "no"

    # Summary
    Font size: 7
    Select inner viewport: 0.60, 7.70, 5.25, 6.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.60, 7.70, 5.25, 6.05
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.57, "half",
        ... "Mode: Microtemporal  |  micro ±" + fixed$(micro_offset_ms, 1) + " ms, " + evolName$
        ... + " " + fixed$(evolution_rate_Hz, 2) + (if rate_unit = 2 then " cycles" else " Hz" fi) + "  |  macro ±" + fixed$(1000 * time_range, 0)
        ... + " ms  |  divergence 0-" + fixed$(source_divergence_ms, 0) + " ms  |  pitch ±"
        ... + fixed$(pitch_max, 0) + " ct"
    Text: 0.02, "left", 0.35, "half",
        ... "Grain " + fixed$(1000 * mtL / workingSR, 1) + " ms  |  max step "
        ... + fixed$(1000 * maxUsedStep / workingSR, 3) + " ms = " + fixed$(dopplerCents, 1)
        ... + " ct Doppler  |  coherence " + (if coherenceDb = undefined then "-" else fixed$(coherenceDb, 1) + " dB" fi)
        ... + "  |  scatter ±" + fixed$(read_scatter_ms, 0) + " ms  |  " + levelName$
    Text: 0.02, "left", 0.13, "half",
        ... (if coherence_compensation_pct > 0 and cohBeforeMin <> undefined then "Coherence comp. " + fixed$(coherence_compensation_pct, 0)
        ... + "\%  : frames " + fixed$(cohBeforeMin, 1) + ".." + fixed$(cohBeforeMax, 1) + " dB -> "
        ... + fixed$(cohAfterMin, 1) + ".." + fixed$(cohAfterMax, 1) + " dB  |  " else "" fi)
        ... + "Output " + fixed$(resDur, 2) + " s, " + string$(nChR) + " ch  |  peak "
        ... + fixed$(finalPeak, 3) + "  |  seed " + string$(seedUsed)
        ... + "  |  render " + fixed$(processingTime, 1) + " s"
    Select inner viewport: 0.60, 7.70, 5.25, 6.05
    Axes: 0, 1, 0, 1
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Select outer viewport: 0, 8, 0, 6.15
endproc

# Round step of 1, 2 or 5 x 10^k close to x.
procedure niceStep: .x
    .p = 10 ^ floor(log10(max(.x, 1e-9)))
    .n = .x / .p
    if .n < 1.5
        niceStep.v = .p
    elsif .n < 3.5
        niceStep.v = 2 * .p
    elsif .n < 7.5
        niceStep.v = 5 * .p
    else
        niceStep.v = 10 * .p
    endif
endproc

procedure padL: .s$, .w
    padL$ = .s$
    while length(padL$) < .w
        padL$ = " " + padL$
    endwhile
endproc

procedure fmt: .v, .d
    .m = 10 ^ .d
    .r = round(.v * .m) / .m
    if abs(.r) < 0.5 / .m
        .r = 0
    endif
    fmt$ = fixed$(.r, .d)
    if .d > 0 and index(fmt$, ".") = 0
        fmt$ = fmt$ + "." + left$("000000", .d)
    endif
endproc

procedure vizSafe: .s$
    vizSafe$ = replace$(.s$, "#", "\# ", 0)
    vizSafe$ = replace$(vizSafe$, "%", "\% ", 0)
    vizSafe$ = replace$(vizSafe$, "^", "\^ ", 0)
    vizSafe$ = replace$(vizSafe$, "_", "\_ ", 0)
endproc
