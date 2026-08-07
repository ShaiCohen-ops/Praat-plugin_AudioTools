# ============================================================
# Praat AudioTools - LPC_Excitation_Lab.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LPC Excitation Lab v2.1 - Unified resynthesis engine that
#   drives LPC spectral envelopes with five excitation sources,
#   now with cross-synthesis and per-method modulations.
#
#   Five excitation methods:
#     1. Pitch Sweep   - PitchTier glide with optional vibrato/jitter
#     2. Pulse Train   - periodic impulses with optional jitter/shimmer
#     3. Time Stretch  - noise-excited LPC with optional density modulation
#     4. Chirp Burst   - one or more stacked exponential chirps
#     5. Granular Noise - windowed noise grains with density curve
#
#   Three cross-synthesis modes:
#     1. Off                      - single-Sound resynthesis (v1.0 behaviour)
#     2. Sound2 residual          - inverse-filter Sound2, then drive Sound1's
#                                   spectral envelope with that residual. Classic cross-synthesis:
#                                   "Sound1's vowel-color, Sound2's rhythm."
#     3. Synth exc thru Sound2 fl - Synthetic excitation through Sound2's
#                                   spectral envelope, with Sound1 providing
#                                   the amplitude envelope only.
#
#   Modulations per method (set to 0 to disable; v1.0-like behaviour):
#     Pitch Sweep   : Vibrato_rate_hz, Vibrato_depth_cents, Pitch_jitter_cents
#     Pulse Train   : Pulse_jitter_pct (period drift), Pulse_shimmer_pct
#                     (amplitude wobble)
#     Time Stretch  : Noise_AM_rate_hz, Noise_AM_depth (noise volume LFO)
#     Chirp Burst   : Chirp_layers + Layer_ratios (stacked chirps for
#                     inharmonic shimmer)
#     Granular Noise: Grain_density_start/end (linear density curve),
#                     Grain_size_modulation_pct (per-grain size jitter)
#
#   LPC analysis window and frame step are hardcoded to v1.0's
#   defaults (0.025 s window, 0.005 s step) to keep the form compact.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.1:
#   - FIX: processing is normalized to a 0-based time domain, then output is
#     shifted back to Sound1's original start time. Non-zero start times work.
#   - FIX: synthetic excitation now uses the input sample rate instead of a
#     hardcoded 44.1 kHz.
#   - FIX: Granular Noise density now increases grain rate as documented
#     (grain step = grain_size / density).
#   - FIX: mode 2 is labelled Sound2Residual; synthetic excitation controls
#     are explicitly reported as ignored in that mode.
#   - FIX: Time Stretch modulation controls renamed Noise_AM_* because they
#     modulate noise amplitude, not event density.
#   - FIX: chirp ratio parser falls back to the last supplied ratio when
#     Chirp_layers exceeds the number of ratios.
#   - FIX: chirp layers are clamped below Nyquist to avoid aliasing.
#   - FIX: short inputs now fail early with a clear 64 ms minimum message.
#   - NOTE: LPC processing/output is mono; multichannel inputs are averaged.
#   - FIX: single-source Time Stretch now stretches and applies Sound1's
#     intensity contour instead of skipping it.
#   - NOTE: output is peak-normalized to 0.99 after the intensity contour.
#
# Changelog v2.0:
#   - NEW: Cross-synthesis modes (Sound2 as excitation through Sound1's
#     filter, or synth exc through Sound2's filter). For modes 2 and 3
#     the user selects 2 Sounds; output duration is min(d1, d2).
#   - NEW: Per-method modulations as listed above. All modulation
#     parameters default to 0 (no modulation), so the script
#     reproduces v1.0 character when modulations are off and
#     cross_synth_mode = 1.
#   - NEW presets demonstrating v2.0 capabilities:
#       7. Vibrato Voice      - pitch sweep with 5 Hz vibrato, gentle jitter
#       8. Jittered Pulse     - pulse train with 8% period jitter + shimmer
#       9. Density Cloud      - granular with density curve 0.2 -> 0.9
#      10. Chirp Stack        - 4 stacked chirps at inharmonic ratios
#      11. Cross-Synth        - Sound2 as excitation through Sound1 filter
#     Original preset parameter settings 1-6 unchanged.
#   - In cross-synth modes, the intensity contour comes from the sound providing articulation:
#     Sound2 in mode 2, Sound1 in modes 1 and 3. In single-source Time
#     Stretch, the intensity tier is stretched with the LPC envelope.
#   - Time Stretch only applies its LPC time-scaling when
#     cross_synth_mode = 1; in modes 2/3 the time_stretch_factor
#     is silently ignored (output duration is min(d1, d2)).
#   - Visualization extended to show cross-synth mode and active
#     modulations in the title bar.
#   - Form compacted: all 24 method/modulation parameters remain
#     directly visible in the single form (no second dialog).
#     The blank "comment ===" separators from v1.0's longer form
#     are dropped to save vertical space. The Analysis_window_s
#     and Frame_step_s LPC fields are dropped (now hardcoded
#     at v1.0's defaults: 0.025 s and 0.005 s respectively).
# Changelog v1.0:
#   - Initial release with 5 methods, 6 presets, 8x8 visualization.
# ============================================================

# ============================================================
# FORM  (single compact form, all params directly visible)
# ============================================================

form LPC Excitation Lab v2.1
    optionmenu Preset: 1
        option Custom
        option Voiced Sweep
        option Robotic Pulse
        option Stretched Whisper
        option Chirp Texture
        option Grain Cloud
        option Vibrato Voice
        option Jittered Pulse
        option Density Cloud
        option Chirp Stack
        option Cross-Synth (needs 2 Sounds)
    optionmenu Cross_synth_mode: 1
        option Off (single Sound)
        option Sound2 residual through Sound1 filter
        option Synth excitation, through Sound2 filter
    optionmenu Excitation_method: 1
        option Pitch Sweep
        option Pulse Train
        option Time Stretch
        option Chirp Burst
        option Granular Noise
    positive Start_freq_hz 80
    positive End_freq_hz 300
    real Vibrato_rate_hz 0
    real Vibrato_depth_cents 0
    real Pitch_jitter_cents 0
    positive Period_s 0.01
    real Pulse_jitter_pct 0
    real Pulse_shimmer_pct 0
    positive Time_stretch_factor 3.0
    real Noise_am_rate_hz 0
    real Noise_am_depth 0
    positive Chirp_start_hz 100
    positive Chirp_end_hz 4000
    natural Chirp_layers 1
    sentence Layer_ratios 1.0, 1.5, 2.0, 2.7
    real Grain_density_start 0.6
    real Grain_density_end 0.6
    real Grain_size_modulation_pct 0
    natural Lpc_order 46
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# LPC analysis advanced (not in form to save space)
analysis_window_s = 0.025
frame_step_s = 0.005

# ============================================================
# PRESET APPLICATION
# ============================================================

if preset = 2
    excitation_method = 1
    start_freq_hz = 80
    end_freq_hz = 400
    lpc_order = 46
    presetName$ = "VoicedSweep"
elsif preset = 3
    excitation_method = 2
    period_s = 0.008
    lpc_order = 46
    presetName$ = "RoboticPulse"
elsif preset = 4
    excitation_method = 3
    time_stretch_factor = 5.0
    lpc_order = 50
    presetName$ = "StretchedWhisper"
elsif preset = 5
    excitation_method = 4
    chirp_start_hz = 60
    chirp_end_hz = 8000
    lpc_order = 46
    presetName$ = "ChirpTexture"
elsif preset = 6
    excitation_method = 5
    grain_density_start = 0.4
    grain_density_end = 0.4
    lpc_order = 40
    presetName$ = "GrainCloud"
elsif preset = 7
    # NEW: Vibrato Voice — pitch sweep with vibrato and gentle jitter
    excitation_method = 1
    start_freq_hz = 120
    end_freq_hz = 220
    vibrato_rate_hz = 5.5
    vibrato_depth_cents = 35
    pitch_jitter_cents = 8
    lpc_order = 46
    presetName$ = "VibratoVoice"
elsif preset = 8
    # NEW: Jittered Pulse — pulse train with period jitter + shimmer
    excitation_method = 2
    period_s = 0.0073
    pulse_jitter_pct = 8
    pulse_shimmer_pct = 25
    lpc_order = 46
    presetName$ = "JitteredPulse"
elsif preset = 9
    # NEW: Density Cloud — granular with density curve from sparse to dense
    excitation_method = 5
    grain_density_start = 0.2
    grain_density_end = 0.9
    grain_size_modulation_pct = 30
    lpc_order = 42
    presetName$ = "DensityCloud"
elsif preset = 10
    # NEW: Chirp Stack — 4 stacked chirps at inharmonic ratios
    excitation_method = 4
    chirp_start_hz = 80
    chirp_end_hz = 3000
    chirp_layers = 4
    layer_ratios$ = "1.0, 1.5, 2.7, 4.2"
    lpc_order = 50
    presetName$ = "ChirpStack"
elsif preset = 11
    # NEW: Cross-Synth — Sound2 as excitation through Sound1 filter
    cross_synth_mode = 2
    excitation_method = 1
    lpc_order = 48
    presetName$ = "CrossSynth"
else
    presetName$ = "Custom"
endif

# Resolve method display name
if excitation_method = 1
    methodName$ = "PitchSweep"
elsif excitation_method = 2
    methodName$ = "PulseTrain"
elsif excitation_method = 3
    methodName$ = "TimeStretch"
elsif excitation_method = 4
    methodName$ = "ChirpBurst"
else
    methodName$ = "GranularNoise"
endif

# Resolve cross-synth mode display name
if cross_synth_mode = 1
    modeName$ = "single"
elsif cross_synth_mode = 2
    modeName$ = "S2-residual-thru-S1"
    # Synthetic excitation controls are ignored in this mode.
    methodName$ = "Sound2Residual"
else
    modeName$ = "synth-thru-S2"
endif

# ============================================================
# INPUT VALIDATION + DURATION RESOLUTION
# ============================================================

n_sel = numberOfSelected("Sound")

if cross_synth_mode = 1
    if n_sel <> 1
        exitScript: "For single-source mode, select exactly 1 Sound."
    endif
    s1 = selected("Sound")
    sourceName$ = selected$("Sound")
    s2 = 0
    secondName$ = ""
else
    if n_sel <> 2
        exitScript: "For cross-synthesis (mode 2 or 3), select exactly 2 Sounds."
    endif
    s1 = selected("Sound", 1)
    s2 = selected("Sound", 2)
    selectObject: s1
    sourceName$ = selected$("Sound")
    selectObject: s2
    secondName$ = selected$("Sound")
endif

selectObject: s1
d1 = Get total duration
sr = Get sampling frequency
s1_xmin = Get start time
s1_channels = Get number of channels

if d1 <= 0
    exitScript: "Sound1 has zero duration."
endif

if cross_synth_mode = 1
    d = d1
    d2 = 0
    s2_xmin = 0
    s2_channels = 0
else
    selectObject: s2
    d2 = Get total duration
    sr2 = Get sampling frequency
    s2_xmin = Get start time
    s2_channels = Get number of channels
    if sr2 <> sr
        exitScript: "Sample rates must match (S1: " + string$(sr) + " Hz, S2: " + string$(sr2) + " Hz)"
    endif
    if d2 <= 0
        exitScript: "Sound2 has zero duration."
    endif
    d = min(d1, d2)
endif

# Intensity analysis at 100 Hz and the 25 ms LPC analysis both need enough
# context. Fail explicitly instead of letting Praat emit a low-level error.
if d < 0.064
    exitScript: "LPC Excitation Lab requires at least 64 ms of audio."
endif

# LPC analysis/resynthesis is mono. Make owned mono working copies and
# normalize their time domains to 0 so arbitrary Sound start times are safe.
selectObject: s1
if s1_channels > 1
    s1_work = Convert to mono
else
    s1_work = Copy: "s1_work"
endif
selectObject: s1_work
Shift times to: "start time", 0
if d < d1
    s1_use = Extract part: 0, d, "rectangular", 1, "no"
    removeObject: s1_work
else
    s1_use = s1_work
endif
selectObject: s1_use
Rename: "s1_use"

if cross_synth_mode = 1
    s2_use = 0
else
    selectObject: s2
    if s2_channels > 1
        s2_work = Convert to mono
    else
        s2_work = Copy: "s2_work"
    endif
    selectObject: s2_work
    Shift times to: "start time", 0
    if d < d2
        s2_use = Extract part: 0, d, "rectangular", 1, "no"
        removeObject: s2_work
    else
        s2_use = s2_work
    endif
    selectObject: s2_use
    Rename: "s2_use"
endif

# Decide which sound provides the intensity (amplitude) envelope.
# Mode 1, 3: Sound1 articulates (drives amplitude).
# Mode 2:    Sound2 articulates (drives amplitude — that's the cross-synth idea).
if cross_synth_mode = 2
    int_source = s2_use
    intSourceName$ = secondName$
else
    int_source = s1_use
    intSourceName$ = sourceName$
endif

selectObject: int_source
intensity_obj = To Intensity: 100, 0, "yes"
intensity_tier = Down to IntensityTier

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine: "=== LPC Excitation Lab v2.1 ==="
appendInfoLine: "Source 1: ", sourceName$, " (", fixed$(d1, 3), " s)"
if cross_synth_mode <> 1
    appendInfoLine: "Source 2: ", secondName$, " (", fixed$(d2, 3), " s)"
    appendInfoLine: "Effective duration: ", fixed$(d, 3), " s (min of S1, S2)"
endif
appendInfoLine: "SR: ", round(sr), " Hz"
appendInfoLine: "Processing: mono LPC/resynthesis"
if s1_channels > 1
    appendInfoLine: "  Sound1 averaged from ", s1_channels, " channels"
endif
if cross_synth_mode <> 1 and s2_channels > 1
    appendInfoLine: "  Sound2 averaged from ", s2_channels, " channels"
endif
appendInfoLine: "Cross-synth: ", modeName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Method: ", methodName$
appendInfoLine: "LPC order: ", lpc_order
appendInfoLine: ""

# ============================================================
# STEP 1: BUILD EXCITATION SIGNAL
# ============================================================

appendInfoLine: "Building excitation..."

if cross_synth_mode = 2
    # In mode 2, Sound2 IS the excitation. No synthetic build.
    excit_sound = s2_use
    excit_owned = 0
    appendInfoLine: "  Using LPC residual of Sound2 as excitation (synthetic controls ignored)"
else
    excit_owned = 1
    
    # --- 1. Pitch Sweep ---
    if excitation_method = 1
        appendInfoLine: "  Pitch Sweep: ", fixed$(start_freq_hz, 1), " -> ", fixed$(end_freq_hz, 1), " Hz"
        if vibrato_depth_cents > 0
            appendInfoLine: "    Vibrato: ", fixed$(vibrato_rate_hz, 2), " Hz, +/- ", fixed$(vibrato_depth_cents, 0), " cents"
        endif
        if pitch_jitter_cents > 0
            appendInfoLine: "    Jitter: +/- ", fixed$(pitch_jitter_cents, 0), " cents (random walk)"
        endif
        
        pitch_tier_id = Create PitchTier: "excit_tier", 0, d
        
        # Build the tier with many points so vibrato + jitter can be expressed.
        # Step every 5 ms; v1.0's two-point linear behaviour is preserved when
        # vibrato and jitter are both 0 (each intermediate point lies on the
        # linear Hz line between the endpoints).
        tier_step = 0.005
        n_tier_pts = floor(d / tier_step) + 1
        if n_tier_pts < 2
            n_tier_pts = 2
        endif
        
        # Random-walk accumulator for jitter (in cents)
        jit_walk = 0
        jit_max = pitch_jitter_cents * 3
        
        for iPt from 0 to n_tier_pts
            t = iPt * tier_step
            if t > d
                t = d
            endif
            # Linear Hz glide (matches v1.0 with 2 points)
            if d > 0
                base_hz = start_freq_hz + (end_freq_hz - start_freq_hz) * (t / d)
            else
                base_hz = start_freq_hz
            endif
            # Vibrato in cents
            vib_cents = vibrato_depth_cents * sin(2 * pi * vibrato_rate_hz * t)
            # Random walk in cents (mean-reverting so it doesn't drift forever)
            if pitch_jitter_cents > 0
                step_cents = randomGauss(0, pitch_jitter_cents / 3)
                jit_walk = jit_walk + step_cents - jit_walk * 0.05
                if jit_walk > jit_max
                    jit_walk = jit_max
                endif
                if jit_walk < -jit_max
                    jit_walk = -jit_max
                endif
            endif
            total_cents = vib_cents + jit_walk
            # Convert to Hz
            pitch_hz = base_hz * 2 ^ (total_cents / 1200)
            if pitch_hz < 20
                pitch_hz = 20
            endif
            Add point: t, pitch_hz
        endfor
        
        excit_sound = To Sound (pulse train): sr, 1, 0.05, 2000, "no"
        Rename: "Excitation_" + methodName$
        removeObject: pitch_tier_id

    # --- 2. Pulse Train ---
    elsif excitation_method = 2
        appendInfoLine: "  Pulse Train: period ", fixed$(period_s * 1000, 2), " ms"
        if pulse_jitter_pct > 0
            appendInfoLine: "    Jitter: +/- ", fixed$(pulse_jitter_pct, 1), "% of period"
        endif
        if pulse_shimmer_pct > 0
            appendInfoLine: "    Shimmer: +/- ", fixed$(pulse_shimmer_pct, 1), "% amplitude"
        endif
        
        pp_id = Create empty PointProcess: "excit_pp", 0, d
        
        if pulse_jitter_pct = 0
            # v1.0 uniform path
            Fill: 0, 0, period_s
        else
            # Jittered: add points one-by-one with random period offset
            jit_amt = pulse_jitter_pct / 100
            tcur = 0
            while tcur < d
                Add point: tcur
                period_jit = period_s * (1 + jit_amt * randomUniform(-1, 1))
                if period_jit < period_s * 0.1
                    period_jit = period_s * 0.1
                endif
                tcur = tcur + period_jit
            endwhile
        endif
        
        excit_sound = To Sound (pulse train): sr, 1, 0.05, 2000
        Rename: "Excitation_" + methodName$
        removeObject: pp_id
        
        # Apply shimmer as a slow two-sinusoid AM envelope.
        # Two sines with incommensurable frequencies give a quasi-random
        # amplitude wobble across the file without a clear LFO period.
        if pulse_shimmer_pct > 0
            shimmer_amp = pulse_shimmer_pct / 100
            selectObject: excit_sound
            Formula: "self * (1 + " + fixed$(shimmer_amp, 4) + " * sin(2 * pi * 3.7 * x) * sin(2 * pi * 1.3 * x + 0.7))"
        endif

    # --- 3. Time Stretch (noise, LPC scaled) ---
    elsif excitation_method = 3
        # Time stretch only applies in cross_synth_mode = 1; in modes 2/3 we
        # never reach this branch in mode 2 (short-circuited above), and in
        # mode 3 we treat factor as 1.
        if cross_synth_mode = 1
            d_eff = d * time_stretch_factor
        else
            d_eff = d
        endif
        if cross_synth_mode = 1
            appendInfoLine: "  Time Stretch: factor ", fixed$(time_stretch_factor, 2), "  ->  ", fixed$(d_eff, 3), " s"
        else
            appendInfoLine: "  Noise excitation: Time_stretch_factor ignored in cross-synth mode 3"
        endif
        if noise_am_depth > 0
            appendInfoLine: "    Noise AM: ", fixed$(noise_am_rate_hz, 2), " Hz at depth ", fixed$(noise_am_depth, 2)
        endif
        
        if noise_am_depth > 0
            dmd_str$ = fixed$(noise_am_depth, 4)
            dmr_str$ = fixed$(noise_am_rate_hz, 4)
            excit_sound = Create Sound from formula: "Excitation_" + methodName$,
                ... 1, 0, d_eff, sr,
                ... "randomGauss(0, 0.1) * (1 + " + dmd_str$ + " * sin(2*pi*" + dmr_str$ + "*x))"
        else
            excit_sound = Create Sound from formula: "Excitation_" + methodName$,
                ... 1, 0, d_eff, sr,
                ... "randomGauss(0, 0.1)"
        endif

    # --- 4. Chirp Burst ---
    elsif excitation_method = 4
        if chirp_end_hz <= chirp_start_hz
            chirp_end_hz = chirp_start_hz + 1000
        endif
        n_layers = chirp_layers
        if n_layers < 1
            n_layers = 1
        endif
        if n_layers > 8
            n_layers = 8
        endif
        appendInfoLine: "  Chirp Burst: ", fixed$(chirp_start_hz, 0), " -> ", fixed$(chirp_end_hz, 0), " Hz"
        appendInfoLine: "    Layers: ", n_layers, "  Ratios: ", layer_ratios$
        
        # Build first chirp at ratio = first parsed value
        @parseRatioFromList: layer_ratios$, 1
        ratio_1 = parseRatioFromList.result
        if ratio_1 <= 0
            ratio_1 = 1.0
        endif
        
        f_start_1 = chirp_start_hz * ratio_1
        f_end_1 = chirp_end_hz * ratio_1
        chirpNyq = sr / 2 * 0.95
        if f_start_1 >= chirpNyq
            f_start_1 = chirpNyq * 0.5
        endif
        if f_end_1 > chirpNyq
            f_end_1 = chirpNyq
        endif
        if f_end_1 <= f_start_1
            f_end_1 = min(chirpNyq, f_start_1 + 100)
        endif
        k_1 = f_end_1 / f_start_1
        fStartStr$ = fixed$(f_start_1, 4)
        dStr$ = fixed$(d, 6)
        lnkStr$ = fixed$(ln(k_1), 8)
        kStr$ = fixed$(k_1, 6)
        excit_sound = Create Sound from formula: "Excitation_" + methodName$,
            ... 1, 0, d, sr,
            ... "sin(2*pi*" + fStartStr$ + "*" + dStr$ + "/" + lnkStr$ + "*((" + kStr$ + ")^(x/" + dStr$ + ")-1))"
        
        # Add additional layers (if any)
        for ilayer from 2 to n_layers
            @parseRatioFromList: layer_ratios$, ilayer
            ratio_L = parseRatioFromList.result
            if ratio_L <= 0
                ratio_L = 1.0
            endif
            
            f_start_L = chirp_start_hz * ratio_L
            f_end_L = chirp_end_hz * ratio_L
            if f_start_L >= chirpNyq
                f_start_L = chirpNyq * 0.5
            endif
            if f_end_L > chirpNyq
                f_end_L = chirpNyq
            endif
            if f_end_L <= f_start_L
                f_end_L = min(chirpNyq, f_start_L + 100)
            endif
            k_L = f_end_L / f_start_L
            fStartStrL$ = fixed$(f_start_L, 4)
            lnkStrL$ = fixed$(ln(k_L), 8)
            kStrL$ = fixed$(k_L, 6)
            
            layer_chirp = Create Sound from formula: "chirp_layer_tmp",
                ... 1, 0, d, sr,
                ... "sin(2*pi*" + fStartStrL$ + "*" + dStr$ + "/" + lnkStrL$ + "*((" + kStrL$ + ")^(x/" + dStr$ + ")-1))"
            layerStr$ = string$(layer_chirp)
            
            selectObject: excit_sound
            Formula: "self + object[" + layerStr$ + "]"
            
            removeObject: layer_chirp
        endfor
        
        # Normalise by layer count to keep amplitude reasonable
        if n_layers > 1
            selectObject: excit_sound
            Formula: "self / " + string$(n_layers)
        endif
    
    # --- 5. Granular Noise ---
    else
        appendInfoLine: "  Granular Noise: density ", fixed$(grain_density_start, 2), " -> ", fixed$(grain_density_end, 2)
        if grain_size_modulation_pct > 0
            appendInfoLine: "    Size modulation: +/- ", fixed$(grain_size_modulation_pct, 0), "%"
        endif
        
        grain_size = 0.04
        if grain_density_start <= 0
            grain_density_start = 0.01
        endif
        if grain_density_start > 1
            grain_density_start = 1
        endif
        if grain_density_end <= 0
            grain_density_end = 0.01
        endif
        if grain_density_end > 1
            grain_density_end = 1
        endif
        size_mod = grain_size_modulation_pct / 100
        
        # Pre-allocate output buffer
        excit_sound = Create Sound from formula: "Excitation_" + methodName$,
            ... 1, 0, d, sr, "0"
        
        # Loop: place grains with time-varying density
        tcur = 0
        ng_total = 0
        while tcur < d
            # Density at current time (linear interp from start to end)
            if d > 0
                cur_density = grain_density_start + (grain_density_end - grain_density_start) * (tcur / d)
            else
                cur_density = grain_density_start
            endif
            if cur_density < 0.01
                cur_density = 0.01
            endif
            if cur_density > 1
                cur_density = 1
            endif
            
            # Grain size with per-grain jitter
            if size_mod > 0
                gs = grain_size * (1 + size_mod * randomUniform(-1, 1))
            else
                gs = grain_size
            endif
            if gs < 0.005
                gs = 0.005
            endif
            
            g_end = tcur + gs
            if g_end > d
                g_end = d
            endif
            if g_end > tcur + 0.001
                grain = Create Sound from formula: "grain_tmp",
                    ... 1, 0, g_end - tcur, sr,
                    ... "randomGauss(0, 0.15) * exp(-0.5*((x - " + fixed$(gs/2, 5) + ")/" + fixed$(gs/4, 5) + ")^2)"
                
                grainStr$ = string$(grain)
                offsetStr$ = string$(round(tcur * sr))
                
                selectObject: excit_sound
                Formula (part): tcur, g_end, 1, 1,
                    ... "self + object[" + grainStr$ + ", 1, col - " + offsetStr$ + "]"
                
                removeObject: grain
                ng_total = ng_total + 1
            endif
            
            grain_step = grain_size / cur_density
            if grain_step < 0.001
                grain_step = 0.001
            endif
            tcur = tcur + grain_step
        endwhile
        
        appendInfoLine: "    Built ", ng_total, " grains"
        selectObject: excit_sound
        Rename: "Excitation_" + methodName$
    endif
endif

appendInfoLine: "  Excitation ready."

# ============================================================
# STEP 2: LPC ANALYSIS
# ============================================================

appendInfoLine: "Running LPC analysis..."

# Which sound provides the FILTER (lpc_a)?
#   mode 1, 2: Sound1's LPC
#   mode 3:    Sound2's LPC
if cross_synth_mode = 3
    filter_source = s2_use
    filterSourceName$ = secondName$
else
    filter_source = s1_use
    filterSourceName$ = sourceName$
endif

selectObject: filter_source
if cross_synth_mode = 1 and excitation_method = 3
    # v1.0 behaviour: scale source LPC times by stretch factor
    lpc_a = To LPC (burg): lpc_order, analysis_window_s, frame_step_s, 50
    selectObject: lpc_a
    Scale times by: time_stretch_factor
else
    lpc_a = To LPC (burg): lpc_order, analysis_window_s, frame_step_s, 50
endif

selectObject: excit_sound
lpc_b = To LPC (burg): lpc_order, analysis_window_s, frame_step_s, 50

appendInfoLine: "  Filter LPC from: ", filterSourceName$
appendInfoLine: "  LPC order ", lpc_order, " — done."

# ============================================================
# STEP 3: INVERSE FILTER + RE-FILTER + AMPLITUDE ENVELOPE
# ============================================================

appendInfoLine: "Filtering and applying amplitude envelope..."

selectObject: excit_sound
plusObject: lpc_b
residual = Filter (inverse)
Rename: "Residual_" + methodName$

selectObject: residual
plusObject: lpc_a
output_raw = Filter: "no"

# Apply the articulation/intensity contour in every mode. For single-source
# Time Stretch, stretch the IntensityTier to the same duration as the LPC.
if cross_synth_mode = 1 and excitation_method = 3
    selectObject: intensity_tier
    Scale times by: time_stretch_factor
    appendInfoLine: "  Intensity envelope time-stretched by ", fixed$(time_stretch_factor, 2)
endif

selectObject: output_raw
plusObject: intensity_tier
output = Multiply: "yes"
Rename: sourceName$ + "_" + methodName$ + "_" + presetName$
removeObject: output_raw
appendInfoLine: "  Intensity envelope applied (from ", intSourceName$, ")"

selectObject: output
Scale peak: 0.99

selectObject: output
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "  Output: ", selected$("Sound"), " (", fixed$(finalDur, 3), " s)"

# ============================================================
# VISUALIZATION  (8x8 suite)
# ============================================================

if draw_visualization
    
    Erase all
    Helvetica
    Line width: 1
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##LPC EXCITATION LAB v2.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    
    # Build a compact summary of active modulations
    modStr$ = ""
    if excitation_method = 1
        if vibrato_depth_cents > 0
            modStr$ = modStr$ + " vib " + fixed$(vibrato_rate_hz, 1) + "Hz/" + fixed$(vibrato_depth_cents, 0) + "ct"
        endif
        if pitch_jitter_cents > 0
            modStr$ = modStr$ + " jit " + fixed$(pitch_jitter_cents, 0) + "ct"
        endif
    elsif excitation_method = 2
        if pulse_jitter_pct > 0
            modStr$ = modStr$ + " jit " + fixed$(pulse_jitter_pct, 0) + "%"
        endif
        if pulse_shimmer_pct > 0
            modStr$ = modStr$ + " shim " + fixed$(pulse_shimmer_pct, 0) + "%"
        endif
    elsif excitation_method = 3
        if noise_am_depth > 0
            modStr$ = modStr$ + " AM " + fixed$(noise_am_rate_hz, 1) + "Hz/" + fixed$(noise_am_depth, 2)
        endif
    elsif excitation_method = 4
        if chirp_layers > 1
            modStr$ = modStr$ + " x" + string$(chirp_layers) + " layers"
        endif
    elsif excitation_method = 5
        if grain_density_start <> grain_density_end
            modStr$ = modStr$ + " AM " + fixed$(grain_density_start, 2) + "->" + fixed$(grain_density_end, 2)
        endif
        if grain_size_modulation_pct > 0
            modStr$ = modStr$ + " size+/-" + fixed$(grain_size_modulation_pct, 0) + "%"
        endif
    endif
    
    # Source label includes cross-synth mode
    if cross_synth_mode = 1
        srcLabel$ = sourceName$
    elsif cross_synth_mode = 2
        srcLabel$ = sourceName$ + " <- " + secondName$ + " (S2-as-exc)"
    else
        srcLabel$ = sourceName$ + " thru " + secondName$ + " (synth-thru-S2)"
    endif
    
    Text: 0.5, "centre", -0.15, "half",
        ... srcLabel$
        ... + "  |  " + methodName$
        ... + "  |  " + presetName$
        ... + modStr$
        ... + "  |  LPC " + string$(lpc_order)
        ... + "  |  " + fixed$(finalDur, 2) + " s"

    # ----------------------------------------------------------
    # PANEL A: EXCITATION WAVEFORM  (left upper)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 0.75, 3.00
    Select inner viewport: 0.55, 3.90, 0.95, 2.85
    
    selectObject: excit_sound
    excit_peak = Get absolute extremum: 0, 0, "None"
    if excit_peak < 0.001
        excit_peak = 0.001
    endif
    excit_amp = excit_peak * 1.2
    excit_dur = Get total duration
    
    Axes: 0, excit_dur, -excit_amp, excit_amp
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, excit_dur, -excit_amp, excit_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, excit_dur, 0
    
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1
    Draw: 0, 0, -excit_amp, excit_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL B: LPC RESIDUAL  (right upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 0.75, 3.00
    Select inner viewport: 4.45, 7.75, 0.95, 2.85
    
    selectObject: residual
    res_peak = Get absolute extremum: 0, 0, "None"
    if res_peak < 0.001
        res_peak = 0.001
    endif
    res_amp = res_peak * 1.2
    res_dur = Get total duration
    
    Axes: 0, res_dur, -res_amp, res_amp
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, res_dur, -res_amp, res_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, res_dur, 0
    
    Colour: "{0.38, 0.32, 0.62}"
    Line width: 1
    Draw: 0, 0, -res_amp, res_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL TITLES (A and B aligned)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Font size: 7
    Colour: "Black"
    if cross_synth_mode = 2
        Text: 2.05, "centre", 7.28, "half", "Excitation = " + secondName$ + "  (Sound2)"
    else
        Text: 2.05, "centre", 7.28, "half", "Excitation  [" + methodName$ + "]"
    endif
    Text: 6.10, "centre", 7.28, "half", "LPC Residual  (inverse-filtered)"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.10, 4.60
    Select inner viewport: 0.55, 7.72, 3.20, 4.50
    
    selectObject: output
    out_peak_v = Get absolute extremum: 0, 0, "None"
    if out_peak_v < 0.001
        out_peak_v = 0.001
    endif
    out_amp = out_peak_v * 1.15
    out_dur = Get total duration
    
    Axes: 0, out_dur, -out_amp, out_amp
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, out_dur, -out_amp, out_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, out_dur, 0
    
    Colour: "{0.20, 0.45, 0.80}"
    Line width: 1
    Draw: 0, 0, -out_amp, out_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (LPC resynthesis + Intensity from " + intSourceName$ + ")"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OVERLAY SPECTRUM  (filter source vs output)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.88
    Select inner viewport: 0.55, 7.72, 4.75, 5.82
    
    selectObject: filter_source
    spec_src = To Spectrum: "yes"
    
    selectObject: output
    spec_out_tmp_dur = Get total duration
    win_len = 0.08
    if win_len > spec_out_tmp_dur
        win_len = spec_out_tmp_dur * 0.8
    endif
    mid_t = spec_out_tmp_dur / 2
    t_from = mid_t - win_len / 2
    if t_from < 0
        t_from = 0
    endif
    t_to = t_from + win_len
    
    if spec_out_tmp_dur >= win_len
        spec_win = Extract part: t_from, t_to, "Hanning", 1, "no"
        spec_out = To Spectrum: "yes"
        removeObject: spec_win
    else
        spec_out = To Spectrum: "yes"
    endif
    
    # Frequency display range
    selectObject: spec_src
    maxF_disp = 8000
    Axes: 0, maxF_disp, -60, 0
    
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxF_disp, -60, 0
    
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Draw line: 0, -20, maxF_disp, -20
    Draw line: 0, -40, maxF_disp, -40
    
    selectObject: spec_src
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1.5
    Draw: 0, maxF_disp, -60, 0, "no"
    
    selectObject: spec_out
    Colour: "{0.20, 0.45, 0.80}"
    Line width: 1.5
    Draw: 0, maxF_disp, -60, 0, "no"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Legend
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Font size: 6
    Colour: "{0.45, 0.45, 0.45}"
    Text: 1.5, "left", 2.18, "half", "— Filter source (" + filterSourceName$ + ")"
    Colour: "{0.20, 0.45, 0.80}"
    Text: 4.0, "left", 2.18, "half", "— Output"
    Colour: "Black"
    Text: 5.7, "left", 2.18, "half", "Spectrum overlay (0-8 kHz)"
    
    removeObject: spec_src, spec_out
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.95, 6.72
    Select inner viewport: 0.55, 7.72, 6.00, 6.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if cross_synth_mode = 1
        srcStat$ = "Source: " + sourceName$ + " (" + fixed$(d1, 2) + " s)"
    else
        srcStat$ = "S1: " + sourceName$ + " (" + fixed$(d1, 2) + ") | S2: " + secondName$ + " (" + fixed$(d2, 2) + ")"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  Method: " + methodName$
        ... + "  |  Cross-synth: " + modeName$
        ... + "  |  LPC: " + string$(lpc_order)
        ... + "  |  Window: " + fixed$(analysis_window_s * 1000, 0) + " ms"
        ... + "  |  Step: " + fixed$(frame_step_s * 1000, 0) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... srcStat$
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s"
        ... + "  |  Peak: " + fixed$(finalPeak, 3) + " (norm 0.99)"
        ... + "  |  SR: " + string$(round(sr)) + " Hz"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: lpc_a, lpc_b, residual, intensity_obj, intensity_tier

# Only remove excit_sound if we created it (mode 1, 3) — in mode 2 it's s2_use
if excit_owned = 1
    removeObject: excit_sound
endif

# Remove owned mono working copies.
if cross_synth_mode = 1
    removeObject: s1_use
else
    removeObject: s1_use, s2_use
endif

# ============================================================
# FINAL INFO + SELECT
# ============================================================

selectObject: output
if s1_xmin <> 0
    Shift times by: s1_xmin
endif
selectObject: output

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 3)

# ============================================================
# PLAY
# ============================================================

if play_result
    Play
endif

selectObject: output

# ============================================================
# PROCEDURES
# ============================================================

# Parse the Nth comma-separated value from a string like "1.0, 1.5, 2.7, 4.2"
# Result lives in parseRatioFromList.result (a numeric value).
procedure parseRatioFromList: .listStr$, .idx
    .result = 1.0
    .last = 1.0
    .work$ = .listStr$ + ","
    .count = 0
    while length(.work$) > 0 and .count < .idx
        .commaPos = index(.work$, ",")
        if .commaPos > 0
            .count = .count + 1
            .item$ = left$(.work$, .commaPos - 1)
            # Trim spaces
            while length(.item$) > 0 and left$(.item$, 1) = " "
                .item$ = mid$(.item$, 2, length(.item$) - 1)
            endwhile
            while length(.item$) > 0 and right$(.item$, 1) = " "
                .item$ = left$(.item$, length(.item$) - 1)
            endwhile
            .val = number(.item$)
            if .val <> undefined and .val > 0
                .last = .val
            endif
            if .count = .idx
                .result = .last
            endif
            .work$ = mid$(.work$, .commaPos + 1, length(.work$) - .commaPos)
        else
            .work$ = ""
        endif
    endwhile
    if .count < .idx
        .result = .last
    endif
endproc
