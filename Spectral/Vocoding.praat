# ============================================================
# Praat AudioTools - Vocoding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Offline Bark-band channel vocoder with three carrier modes,
#   coarse envelope-band shifting, high-frequency noise takeover,
#   and algorithmic stereo spreading.
#
#   The "frequency shift" control moves analyzed Bark-band envelopes
#   to different carrier bands. It is not a spectral pitch shifter
#   and does not track or move individual formants.
#
# Changelog v0.4:
#   - Preserve a true dry path: stereo input stays stereo; wet=0 is
#     sample-identical to the dry signal (for input peaks <= 0.99).
#   - Stereo analysis uses the strongest input channel instead of a
#     phase-cancelling mono fold-down.
#   - Added equal-power Stereo spread control; 100% preserves the
#     original hard odd/even band distribution.
#   - Clamp analysis range to Nyquist and validate band limits.
#   - Clarified noise takeover: target bands entirely above the
#     threshold use the noise carrier.
#   - Conditional final limiting only when a wet mix would clip.
#   - Rebuilt visualization around the actual algorithm:
#       A band mapping, B measured envelope transfer,
#       C source/pure-wet spectral shape, D applied stereo pan law.
# ============================================================

form Poly-Carrier Vocoder
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Classic Robot
        option Whisper Ghost
        option Deep Monster
        option Chipmunk
        option Pitch Follower
        option Metallic Drone
    comment === Vocoder Style ===
    optionmenu Carrier_type: 2
        option 1. Noise (Whisper)
        option 2. Robot Drone (Sawtooth)
        option 3. Pitch-Tracking (Pulse)
    positive Robot_pitch_hz 100
    comment === Spectral Routing ===
    integer Frequency_shift_bands 0
    comment (Moves source Bark-band envelopes to carrier bands; not a pitch shift)
    positive High_freq_noise_threshold 3500
    comment (Target bands entirely above this frequency use Noise)
    comment === Bands ===
    natural Number_of_bands 20
    positive Lower_freq_limit 50
    positive Upper_freq_limit 7500
    comment === Envelope ===
    positive Envelope_smoothness_hz 100
    comment (Envelope low-pass cutoff: lower = smoother/slower)
    comment === Mix / Stereo ===
    real Wet_dry_percent 100
    comment (0 = dry, 100 = full vocoder)
    real Stereo_spread_percent 100
    comment (0 = centered wet, 100 = alternating hard L/R bands)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_after 1
endform

# ============================================================
# PRESETS
# ============================================================
presetName$ = "Custom"

if preset = 2
    carrier_type = 2
    robot_pitch_hz = 100
    frequency_shift_bands = 0
    number_of_bands = 20
    presetName$ = "ClassicRobot"
elsif preset = 3
    carrier_type = 1
    frequency_shift_bands = 0
    number_of_bands = 24
    envelope_smoothness_hz = 80
    presetName$ = "WhisperGhost"
elsif preset = 4
    carrier_type = 2
    robot_pitch_hz = 60
    frequency_shift_bands = -3
    number_of_bands = 20
    presetName$ = "DeepMonster"
elsif preset = 5
    carrier_type = 2
    robot_pitch_hz = 200
    frequency_shift_bands = 4
    number_of_bands = 20
    presetName$ = "Chipmunk"
elsif preset = 6
    carrier_type = 3
    frequency_shift_bands = 0
    number_of_bands = 24
    presetName$ = "PitchFollower"
elsif preset = 7
    carrier_type = 2
    robot_pitch_hz = 150
    frequency_shift_bands = 0
    number_of_bands = 32
    envelope_smoothness_hz = 50
    presetName$ = "MetallicDrone"
endif

# ============================================================
# SETUP / VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
orig_dur = Get total duration
nyquist = orig_sr / 2

if n_channels > 2
    exitScript: "This vocoder currently supports mono or stereo input. Please extract or mix the desired channels first."
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
if stereo_spread_percent < 0
    stereo_spread_percent = 0
elsif stereo_spread_percent > 100
    stereo_spread_percent = 100
endif

if upper_freq_limit > nyquist
    upper_effective = nyquist
else
    upper_effective = upper_freq_limit
endif
lower_effective = max(1, lower_freq_limit)

if upper_effective <= lower_effective
    exitScript: "Upper frequency limit must be above the lower limit after Nyquist clamping."
endif

env_cutoff = min(envelope_smoothness_hz, 0.95 * nyquist)
if env_cutoff <= 0
    exitScript: "Envelope smoothness must be above 0 Hz."
endif

if abs(frequency_shift_bands) >= number_of_bands
    exitScript: "Frequency shift leaves no active Bark bands. Use a shift smaller than the number of bands."
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level
spread = stereo_spread_percent / 100

if carrier_type = 1
    carrierName$ = "Noise"
elsif carrier_type = 2
    carrierName$ = "Sawtooth"
else
    carrierName$ = "PitchTrack"
endif

writeInfoLine: "=== Poly-Carrier Vocoder v0.4 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Carrier: ", carrierName$
appendInfoLine: "Bands: ", number_of_bands, " | Envelope shift: ", frequency_shift_bands
appendInfoLine: "Analysis range: ", fixed$(lower_effective, 0), "-", fixed$(upper_effective, 0), " Hz"
appendInfoLine: "Wet: ", fixed$(wet_dry_percent, 0), "% | Stereo spread: ", fixed$(stereo_spread_percent, 0), "%"
appendInfoLine: ""

# ============================================================
# 1. ANALYSIS SOURCE
# Use one representative channel for analysis; avoid stereo
# cancellation from blind mono summation.
# ============================================================
analysis_channel = 1

if n_channels = 1
    selectObject: orig_id
    input_id = Copy: "Vocoder_Modulator"
else
    selectObject: orig_id
    ch1 = Extract one channel: 1
    rms1 = Get root-mean-square: 0, 0

    selectObject: orig_id
    ch2 = Extract one channel: 2
    rms2 = Get root-mean-square: 0, 0

    if rms2 > rms1
        analysis_channel = 2
        input_id = ch2
        removeObject: ch1
    else
        analysis_channel = 1
        input_id = ch1
        removeObject: ch2
    endif
    selectObject: input_id
    Rename: "Vocoder_Modulator"
endif

appendInfoLine: "Analysis channel: ", analysis_channel

# ============================================================
# 2. PITCH-TRACKED PULSE SOURCE (if requested)
# ============================================================
pp_id = 0
if carrier_type = 3
    appendInfoLine: "Extracting pitch contour..."
    selectObject: input_id
    pitch_id = To Pitch: 0.0, 75, 600
    selectObject: pitch_id
    pp_id = To PointProcess
    removeObject: pitch_id
endif

# ============================================================
# 3. CARRIERS
# ============================================================
appendInfoLine: "Generating carriers..."

if carrier_type = 1
    Create Sound from formula: "Carrier_Main", 1, 0, orig_dur, orig_sr, "randomGauss(0, 0.2)"
elsif carrier_type = 2
    s_pitch$ = string$(robot_pitch_hz)
    Create Sound from formula: "Carrier_Main", 1, 0, orig_dur, orig_sr, "0.2 * 2 * (x * " + s_pitch$ + " - floor(0.5 + x * " + s_pitch$ + "))"
else
    selectObject: pp_id
    To Sound (pulse train): orig_sr, 1, 0.05, 2000
    Scale peak: 0.2
    Rename: "Carrier_Main"
    removeObject: pp_id
endif
carrier_main_id = selected("Sound")

Create Sound from formula: "Carrier_Noise", 1, 0, orig_dur, orig_sr, "randomGauss(0, 0.1)"
carrier_noise_id = selected("Sound")

# ============================================================
# 4. OUTPUT BUFFERS
# ============================================================
out_L_id = Create Sound from formula: "Vocoder_Wet_L", 1, 0, orig_dur, orig_sr, "0"
out_R_id = Create Sound from formula: "Vocoder_Wet_R", 1, 0, orig_dur, orig_sr, "0"

# ============================================================
# 5. BARK-SCALE BANK
# ============================================================
b_low = hertzToBark(lower_effective)
b_high = hertzToBark(upper_effective)
step = (b_high - b_low) / number_of_bands
filter_smoothing_hz = 50

src_center# = zero#(number_of_bands)
car_center# = zero#(number_of_bands)
active# = zero#(number_of_bands)
noise_flag# = zero#(number_of_bands)
pan# = zero#(number_of_bands)

active_bands = 0
noise_bands = 0
best_env_rms = -1
rep_env_id = 0
rep_band_id = 0
rep_i = 0
rep_j = 0
rep_src_low = 0
rep_src_high = 0
rep_car_low = 0
rep_car_high = 0

# Equal-power spread law. At 100%, old hard alternating
# L/R routing is preserved exactly.
pan_angle = (1 - spread) * pi / 4
primary_gain = cos(pan_angle)
cross_gain = sin(pan_angle)

appendInfoLine: "Processing Bark filter bank..."

# ============================================================
# 6. BAND LOOP
# ============================================================
for i from 1 to number_of_bands
    b_src_upper = b_low + i * step
    b_src_lower = b_src_upper - step
    f_src_low = barkToHertz(b_src_lower)
    f_src_high = barkToHertz(b_src_upper)
    f_src_mid = sqrt(max(1, f_src_low) * max(1, f_src_high))
    src_center#[i] = f_src_mid

    j = i + frequency_shift_bands

    if j > 0 and j <= number_of_bands
        active#[i] = 1
        active_bands += 1

        b_car_upper = b_low + j * step
        b_car_lower = b_car_upper - step
        f_car_low = barkToHertz(b_car_lower)
        f_car_high = barkToHertz(b_car_upper)
        f_car_mid = sqrt(max(1, f_car_low) * max(1, f_car_high))
        car_center#[i] = f_car_mid

        # --- Source envelope ---
        selectObject: input_id
        src_band = Filter (pass Hann band): f_src_low, f_src_high, filter_smoothing_hz
        Formula: "self * self"
        env_id = Filter (pass Hann band): 0, env_cutoff, 20
        Formula: "sqrt(abs(self))"
        removeObject: src_band

        selectObject: env_id
        env_rms = Get root-mean-square: 0, 0

        # --- Carrier band ---
        # Preserve v0.3 takeover rule: only a band whose LOWER edge
        # is above the threshold uses noise.
        if f_car_low > high_freq_noise_threshold
            selectObject: carrier_noise_id
            noise_flag#[i] = 1
            noise_bands += 1
        else
            selectObject: carrier_main_id
            noise_flag#[i] = 0
        endif

        carrier_band_id = Filter (pass Hann band): f_car_low, f_car_high, filter_smoothing_hz

        # --- Envelope multiplication ---
        selectObject: carrier_band_id
        env_id_str$ = string$(env_id)
        Formula: "self * object(" + env_id_str$ + ", x)"

        # Keep the strongest active envelope for a measured proof panel.
        if env_rms > best_env_rms
            if rep_env_id <> 0
                removeObject: rep_env_id
            endif
            if rep_band_id <> 0
                removeObject: rep_band_id
            endif
            selectObject: env_id
            rep_env_id = Copy: "Vocoder_Viz_SourceEnvelope"
            selectObject: carrier_band_id
            rep_band_id = Copy: "Vocoder_Viz_ModulatedBand"
            best_env_rms = env_rms
            rep_i = i
            rep_j = j
            rep_src_low = f_src_low
            rep_src_high = f_src_high
            rep_car_low = f_car_low
            rep_car_high = f_car_high
        endif

        # --- Stereo distribution ---
        if i mod 2 = 1
            left_gain = primary_gain
            right_gain = cross_gain
        else
            left_gain = cross_gain
            right_gain = primary_gain
        endif

        if left_gain + right_gain > 0
            pan#[i] = (left_gain - right_gain) / (left_gain + right_gain)
        else
            pan#[i] = 0
        endif

        carrier_str$ = string$(carrier_band_id)
        left_str$ = string$(left_gain)
        right_str$ = string$(right_gain)

        selectObject: out_L_id
        Formula: "self + " + left_str$ + " * object(" + carrier_str$ + ", x)"
        selectObject: out_R_id
        Formula: "self + " + right_str$ + " * object(" + carrier_str$ + ", x)"

        removeObject: env_id
        removeObject: carrier_band_id
    endif
endfor

appendInfoLine: "Active bands: ", active_bands, "/", number_of_bands, " | Noise-carrier bands: ", noise_bands

# ============================================================
# 7. PURE WET
# ============================================================
selectObject: out_L_id
plusObject: out_R_id
wet_id = Combine to stereo
Rename: "Vocoder_PureWet"
Scale peak: 0.99

# Keep an exact pure-wet reference for visualization.
selectObject: wet_id
wet_viz_id = Copy: "Vocoder_PureWet_Viz"

# ============================================================
# 8. WET / DRY
# ============================================================
if wet_level = 1
    selectObject: wet_id
    final_id = Copy: "Vocoder_Final"
elsif wet_level = 0
    selectObject: orig_id
    if n_channels = 1
        final_id = Convert to stereo
    else
        final_id = Copy: "Vocoder_Final"
    endif
else
    selectObject: orig_id
    if n_channels = 1
        dry_stereo_id = Convert to stereo
    else
        dry_stereo_id = Copy: "Vocoder_DryStereo"
    endif

    selectObject: wet_id
    final_id = Copy: "Vocoder_Final"
    dry_id_str$ = string$(dry_stereo_id)
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$

    # Do not normalize every mix. Only protect a genuinely clipping
    # wet/dry result; this preserves the meaning of the mix control.
    mix_peak = Get absolute extremum: 0, 0, "None"
    if mix_peak > 0.99
        Scale peak: 0.99
    endif

    removeObject: dry_stereo_id
endif

selectObject: final_id
Rename: orig_name$ + "_vocoder_" + presetName$

# ============================================================
# 9. VISUALIZATION PREPARATION
# ============================================================
if draw_visualization
    # --- Representative envelope proof ---
    env_rmse = undefined
    viz_env_src = 0
    viz_env_wet = 0
    if rep_env_id <> 0 and rep_band_id <> 0
        selectObject: rep_env_id
        viz_env_src = Copy: "Viz_Env_Source"
        Scale peak: 1

        selectObject: rep_band_id
        rep_sq = Copy: "Viz_Band_Squared"
        Formula: "self * self"
        viz_env_wet = Filter (pass Hann band): 0, env_cutoff, 20
        Formula: "sqrt(abs(self))"
        Scale peak: 1
        removeObject: rep_sq

        selectObject: viz_env_wet
        env_diff = Copy: "Viz_Env_Diff"
        env_src_str$ = string$(viz_env_src)
        Formula: "self - object(" + env_src_str$ + ", x)"
        env_rmse = Get root-mean-square: 0, 0
        removeObject: env_diff
    endif

    # --- Source and pure-wet LTAS ---
    selectObject: input_id
    viz_src_spec = To Spectrum: "yes"
    To Ltas (1-to-1)
    viz_src_ltas = selected("Ltas")

    selectObject: wet_viz_id
    viz_wet_mono = Convert to mono
    viz_wet_spec = To Spectrum: "yes"
    To Ltas (1-to-1)
    viz_wet_ltas = selected("Ltas")

    fPlotMin = max(20, lower_effective)
    fPlotMax = min(upper_effective, 0.98 * nyquist)
    if fPlotMax <= fPlotMin * 1.1
        fPlotMin = max(1, fPlotMax / 4)
    endif
    logFmin = log10(fPlotMin)
    logFmax = log10(fPlotMax)

    specPoints = 90
    specFreq# = zero#(specPoints)
    specSrc# = zero#(specPoints)
    specWet# = zero#(specPoints)
    specMax = -1e30

    for q from 1 to specPoints
        frac = (q - 1) / (specPoints - 1)
        freq = fPlotMin * (fPlotMax / fPlotMin)^frac
        specFreq#[q] = freq
        bandLo = max(fPlotMin, freq / 1.04)
        bandHi = min(fPlotMax, freq * 1.04)
        if bandHi <= bandLo
            bandHi = min(fPlotMax, bandLo + 1)
        endif

        selectObject: viz_src_ltas
        sdb = Get mean: bandLo, bandHi, "dB"
        selectObject: viz_wet_ltas
        wdb = Get mean: bandLo, bandHi, "dB"
        if sdb = undefined
            sdb = -300
        endif
        if wdb = undefined
            wdb = -300
        endif
        specSrc#[q] = sdb
        specWet#[q] = wdb
        if sdb > specMax
            specMax = sdb
        endif
        if wdb > specMax
            specMax = wdb
        endif
    endfor

    for q from 1 to specPoints
        specSrc#[q] = specSrc#[q] - specMax
        specWet#[q] = specWet#[q] - specMax
    endfor

    # --- Output QC ---
    selectObject: final_id
    final_peak = Get absolute extremum: 0, 0, "None"
    final_rms = Get root-mean-square: 0, 0
    selectObject: orig_id
    dry_rms = Get root-mean-square: 0, 0
    if dry_rms > 1e-12
        rms_ratio_db = 20 * log10(max(1e-12, final_rms) / dry_rms)
    else
        rms_ratio_db = 0
    endif

    # ========================================================
    # VISUALIZATION - AudioTools house layout (8 x 5.3)
    # ========================================================
    Erase all

    # Title strip
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Poly-Carrier Vocoder v0.4 - " + presetName$

    # Process strip
    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.50, "half", "analysis channel -> Bark band envelope -> shifted carrier band -> L/R pan -> sum -> wet/dry"

    # --------------------------------------------------------
    # A  BAND MAP
    # --------------------------------------------------------
    Select outer viewport: 0.3, 3.95, 0.60, 2.60
    Select inner viewport: 0.75, 3.70, 1.02, 2.36
    Axes: logFmin, logFmax, logFmin, logFmax
    Paint rectangle: "{0.97,0.97,0.97}", logFmin, logFmax, logFmin, logFmax

    Colour: "{0.78,0.78,0.78}"
    Draw line: logFmin, logFmin, logFmax, logFmax

    # Actual active source-center -> carrier-center mapping.
    Line width: 1
    for i from 1 to number_of_bands
        if active#[i] = 1
            xlog = log10(max(fPlotMin, min(fPlotMax, src_center#[i])))
            ylog = log10(max(fPlotMin, min(fPlotMax, car_center#[i])))
            if noise_flag#[i] = 1
                Colour: "{0.72,0.30,0.26}"
            else
                Colour: "{0.15,0.42,0.68}"
            endif
            dxMark = 0.010 * (logFmax - logFmin)
            dyMark = dxMark
            Draw line: xlog - dxMark, ylog, xlog + dxMark, ylog
            Draw line: xlog, ylog - dyMark, xlog, ylog + dyMark
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    if fPlotMin <= 100 and 100 <= fPlotMax
        One mark bottom: log10(100), "no", "yes", "no", "100"
        One mark left: log10(100), "no", "yes", "no", "100"
    endif
    if fPlotMin <= 500 and 500 <= fPlotMax
        One mark bottom: log10(500), "no", "yes", "no", "500"
        One mark left: log10(500), "no", "yes", "no", "500"
    endif
    if fPlotMin <= 1000 and 1000 <= fPlotMax
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
        One mark left: log10(1000), "no", "yes", "no", "1k"
    endif
    if fPlotMin <= 2000 and 2000 <= fPlotMax
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
        One mark left: log10(2000), "no", "yes", "no", "2k"
    endif
    if fPlotMin <= 5000 and 5000 <= fPlotMax
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
        One mark left: log10(5000), "no", "yes", "no", "5k"
    endif
    if fPlotMin <= 10000 and 10000 <= fPlotMax
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
        One mark left: log10(10000), "no", "yes", "no", "10k"
    endif
    Text bottom: "yes", "Source band centre (Hz, log)"
    Text left: "yes", "Carrier band centre (Hz, log)"

    # Compact legend
    legendX = logFmin + 0.06*(logFmax-logFmin)
    legendY1 = logFmax - 0.08*(logFmax-logFmin)
    legendY2 = logFmax - 0.17*(logFmax-logFmin)
    legendLen = 0.045 * (logFmax-logFmin)
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: legendX, legendY1, legendX + legendLen, legendY1
    Line width: 1
    Colour: "Black"
    Text: legendX + 1.25*legendLen, "left", legendY1, "half", "main"
    Colour: "{0.72,0.30,0.26}"
    Line width: 1.5
    Draw line: legendX, legendY2, legendX + legendLen, legendY2
    Line width: 1
    Colour: "Black"
    Text: legendX + 1.25*legendLen, "left", legendY2, "half", "noise"

    Select outer viewport: 0.3, 3.95, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "A  BAND MAP"

    # --------------------------------------------------------
    # B  ENVELOPE TRANSFER
    # --------------------------------------------------------
    Select outer viewport: 4.05, 7.75, 0.60, 2.60
    Select inner viewport: 4.48, 7.52, 1.02, 2.36
    Axes: 0, orig_dur, 0, 1.08
    Paint rectangle: "{0.97,0.97,0.97}", 0, orig_dur, 0, 1.08

    if viz_env_src <> 0 and viz_env_wet <> 0
        selectObject: viz_env_src
        Colour: "{0.55,0.55,0.55}"
        Draw: 0, 0, 0, 1.08, "no", "Curve"

        selectObject: viz_env_wet
        Colour: "{0.15,0.42,0.68}"
        Line width: 1.5
        Draw: 0, 0, 0, 1.08, "no", "Curve"
        Line width: 1

        Select inner viewport: 4.48, 7.52, 1.02, 2.36
        Axes: 0, orig_dur, 0, 1.08

        # compact legend
        lx = 0.06 * orig_dur
        llen = 0.12 * orig_dur
        Colour: "{0.55,0.55,0.55}"
        Draw line: lx, 0.96, lx + llen, 0.96
        Colour: "Black"
        Font size: 6
        Text: lx + 1.12*llen, "left", 0.96, "half", "source envelope"
        Colour: "{0.15,0.42,0.68}"
        Line width: 1.5
        Draw line: lx, 0.84, lx + llen, 0.84
        Line width: 1
        Colour: "Black"
        Text: lx + 1.12*llen, "left", 0.84, "half", "modulated band"
    endif

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Text left: "yes", "Normalized envelope"
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 4.05, 7.75, 0.60, 0.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "B  ENVELOPE TRANSFER"
    Font size: 5.5
    if env_rmse <> undefined
        mapText$ = fixed$(rep_src_low,0) + "-" + fixed$(rep_src_high,0) + " -> " + fixed$(rep_car_low,0) + "-" + fixed$(rep_car_high,0) + " Hz"
        Text: 0.98, "right", 0.55, "half", mapText$ + " | RMSE " + fixed$(env_rmse,2)
    endif

    # --------------------------------------------------------
    # C  SOURCE / PURE WET
    # --------------------------------------------------------
    Select outer viewport: 0.3, 3.95, 2.82, 4.82
    Select inner viewport: 0.75, 3.70, 3.22, 4.56
    Axes: logFmin, logFmax, -60, 3
    Paint rectangle: "{0.97,0.97,0.97}", logFmin, logFmax, -60, 3

    Colour: "{0.55,0.55,0.55}"
    Line width: 1
    for q from 1 to specPoints
        xlog = log10(specFreq#[q])
        yval = max(-60, specSrc#[q])
        if q > 1
            Draw line: prevX, prevSrc, xlog, yval
        endif
        prevX = xlog
        prevSrc = yval
    endfor

    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    for q from 1 to specPoints
        xlog = log10(specFreq#[q])
        yval = max(-60, specWet#[q])
        if q > 1
            Draw line: prevWetX, prevWetY, xlog, yval
        endif
        prevWetX = xlog
        prevWetY = yval
    endfor
    Line width: 1

    # Noise takeover threshold
    if high_freq_noise_threshold >= fPlotMin and high_freq_noise_threshold <= fPlotMax
        Colour: "{0.72,0.30,0.26}"
        Dotted line
        Draw line: log10(high_freq_noise_threshold), -60, log10(high_freq_noise_threshold), 3
        Solid line
    endif

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 12, "yes", "yes", "no"
    Text left: "yes", "Relative magnitude (dB)"
    if fPlotMin <= 100 and 100 <= fPlotMax
        One mark bottom: log10(100), "no", "yes", "no", "100"
    endif
    if fPlotMin <= 200 and 200 <= fPlotMax
        One mark bottom: log10(200), "no", "yes", "no", "200"
    endif
    if fPlotMin <= 500 and 500 <= fPlotMax
        One mark bottom: log10(500), "no", "yes", "no", "500"
    endif
    if fPlotMin <= 1000 and 1000 <= fPlotMax
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
    endif
    if fPlotMin <= 2000 and 2000 <= fPlotMax
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
    endif
    if fPlotMin <= 5000 and 5000 <= fPlotMax
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if fPlotMin <= 10000 and 10000 <= fPlotMax
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif
    Text bottom: "yes", "Frequency (Hz, log)"

    # in-panel legend
    sx = logFmin + 0.05*(logFmax-logFmin)
    sl = 0.12*(logFmax-logFmin)
    Colour: "{0.55,0.55,0.55}"
    Draw line: sx, -7, sx + sl, -7
    Colour: "Black"
    Font size: 6
    Text: sx + 1.12*sl, "left", -7, "half", "source"
    Colour: "{0.15,0.42,0.68}"
    Line width: 1.5
    Draw line: sx, -15, sx + sl, -15
    Line width: 1
    Colour: "Black"
    Text: sx + 1.12*sl, "left", -15, "half", "pure wet"

    Select outer viewport: 0.3, 3.95, 2.82, 3.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "C  SOURCE / PURE WET"

    # --------------------------------------------------------
    # D  APPLIED STEREO PAN
    # --------------------------------------------------------
    Select outer viewport: 4.05, 7.75, 2.82, 4.82
    Select inner viewport: 4.48, 7.52, 3.22, 4.56
    Axes: logFmin, logFmax, -1.1, 1.1
    Paint rectangle: "{0.97,0.97,0.97}", logFmin, logFmax, -1.1, 1.1
    Colour: "{0.78,0.78,0.78}"
    Draw line: logFmin, 0, logFmax, 0

    havePrevPan = 0
    for i from 1 to number_of_bands
        if active#[i] = 1 and car_center#[i] >= fPlotMin and car_center#[i] <= fPlotMax
            xlog = log10(car_center#[i])
            ypan = pan#[i]
            if noise_flag#[i] = 1
                Colour: "{0.72,0.30,0.26}"
            else
                Colour: "{0.15,0.42,0.68}"
            endif
            dxPan = 0.010 * (logFmax - logFmin)
            dyPan = 0.035
            Draw line: xlog - dxPan, ypan, xlog + dxPan, ypan
            Draw line: xlog, ypan - dyPan, xlog, ypan + dyPan
        endif
    endfor

    Colour: "Black"
    Draw inner box
    One mark left: -1, "yes", "yes", "no", "R"
    One mark left: 0, "yes", "yes", "no", "C"
    One mark left: 1, "yes", "yes", "no", "L"
    if fPlotMin <= 100 and 100 <= fPlotMax
        One mark bottom: log10(100), "no", "yes", "no", "100"
    endif
    if fPlotMin <= 500 and 500 <= fPlotMax
        One mark bottom: log10(500), "no", "yes", "no", "500"
    endif
    if fPlotMin <= 1000 and 1000 <= fPlotMax
        One mark bottom: log10(1000), "no", "yes", "no", "1k"
    endif
    if fPlotMin <= 2000 and 2000 <= fPlotMax
        One mark bottom: log10(2000), "no", "yes", "no", "2k"
    endif
    if fPlotMin <= 5000 and 5000 <= fPlotMax
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if fPlotMin <= 10000 and 10000 <= fPlotMax
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif
    Text bottom: "yes", "Carrier band centre (Hz, log)"
    Text left: "yes", "Applied pan"

    Select outer viewport: 4.05, 7.75, 2.82, 3.10
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "D  STEREO BAND SPREAD"

    # Summary strip
    Select outer viewport: 0.4, 7.7, 4.96, 5.22
    Axes: 0, 1, 0, 1
    Font size: 6.2
    Colour: "{0.35,0.35,0.35}"
    summary$ = "bands " + string$(active_bands) + "/" + string$(number_of_bands) + " | shift " + string$(frequency_shift_bands) + " | noise " + string$(noise_bands) + " | spread " + fixed$(stereo_spread_percent,0) + "% | wet " + fixed$(wet_dry_percent,0) + "% | final peak " + fixed$(final_peak,3) + " | RMS change " + fixed$(rms_ratio_db,1) + " dB"
    Text: 0.5, "centre", 0.52, "half", summary$

    Font size: 10
    Colour: "Black"

    # Viz cleanup
    if viz_env_src <> 0
        removeObject: viz_env_src
    endif
    if viz_env_wet <> 0
        removeObject: viz_env_wet
    endif
    removeObject: viz_src_spec, viz_src_ltas, viz_wet_mono, viz_wet_spec, viz_wet_ltas
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: input_id
removeObject: carrier_main_id
removeObject: carrier_noise_id
removeObject: out_L_id
removeObject: out_R_id
removeObject: wet_id
removeObject: wet_viz_id
if rep_env_id <> 0
    removeObject: rep_env_id
endif
if rep_band_id <> 0
    removeObject: rep_band_id
endif

appendInfoLine: ""
appendInfoLine: "Done!"

if play_after
    selectObject: final_id
    Play
endif

selectObject: final_id
