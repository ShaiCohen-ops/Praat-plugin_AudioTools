# ============================================================
# Praat AudioTools - Stereo Channel Similarity Meter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo-channel analysis for correlation, Mid/Side balance,
#   diffuse stereo spread, anti-phase risk, polarity agreement,
#   broad-band spectral-shape similarity, and time-varying correlation.
#
# Changelog v0.3:
#   - Added real spectral-shape similarity using nine broad log-spaced
#     Spectrum energy bands; similarity is gain-invariant cosine similarity.
#   - Renamed the old "phase coherence" metric to polarity agreement.
#     Same-sign sample percentage is not phase coherence.
#   - Added a separate phase-risk metric max(0,-correlation).
#   - Added bounded diffuse stereo spread (0..1), separating decorrelated
#     width from anti-phase and hard-panned imbalance.
#   - Kept Side/Mid RMS and dB ratio as explicit M/S measurements instead
#     of calling an unbounded Side/Mid ratio "stereo width".
#   - Time-varying Pearson correlation no longer creates/extracts two Sound
#     objects per window. L^2, R^2, and L*R are precomputed once.
#   - Silent/constant windows are excluded instead of being assigned +1.
#   - Analysis respects non-zero Sound origins and caps display windows for
#     long files by adapting hop size, not analysis-window size.
#   - L/R balance handles silent channels safely.
#   - Near-identity threshold is relative to programme RMS instead of a
#     fixed absolute threshold.
#   - Visualization rebuilt in AudioTools 8x8 style with explicit waveform
#     scaling, measured correlation trajectory, spectral band comparison,
#     and concise stereo-state summary.
# ============================================================

form Stereo Channel Similarity Meter v0.3
    comment === Temporal analysis ===
    positive Window_size_seconds 0.1
    boolean Show_visualization 1
    boolean Show_detailed_report 1
endform

# ============================================================
# INPUT VALIDATION / METADATA
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
displayName$ = replace$(soundName$, "_", " ", 0)

selectObject: sound
numberOfChannels = Get number of channels
if numberOfChannels <> 2
    exitScript: "This is not a stereo file. It has " + string$(numberOfChannels) + " channel(s)."
endif

sound_tmin = Get start time
sound_tmax = Get end time
duration = sound_tmax - sound_tmin
samplingRate = Get sampling frequency
totalSamples = Get number of samples
nyquist = samplingRate / 2

if duration <= 0 or totalSamples < 2
    exitScript: "The selected Sound is too short to analyse."
endif

# Use a physically valid minimum analysis window, but do not enlarge the
# user's window otherwise. Very long files adapt only the display hop.
window_size = window_size_seconds
min_window = 32 / samplingRate
if window_size < min_window
    window_size = min_window
endif
if window_size > duration
    window_size = duration
endif

# ============================================================
# EXTRACT CHANNELS
# ============================================================
selectObject: sound
channel1 = Extract one channel: 1
Rename: "StereoSimilarity_Left"

selectObject: sound
channel2 = Extract one channel: 2
Rename: "StereoSimilarity_Right"

# ============================================================
# GLOBAL LEVEL / MOMENT STATISTICS
# ============================================================
selectObject: channel1
mean_L = Get mean: 0, 0
rms_L = Get root-mean-square: 0, 0

selectObject: channel2
mean_R = Get mean: 0, 0
rms_R = Get root-mean-square: 0, 0

var_L = rms_L * rms_L - mean_L * mean_L
var_R = rms_R * rms_R - mean_R * mean_R
if var_L < 0
    var_L = 0
endif
if var_R < 0
    var_R = 0
endif
sd_L = sqrt(var_L)
sd_R = sqrt(var_R)

# Precompute L^2, R^2 and L*R once. These objects make local Pearson
# correlation cheap and avoid per-window extraction/copy/formula work.
selectObject: channel1
l_square = Copy: "StereoSimilarity_L2"
Formula: "self * self"

selectObject: channel2
r_square = Copy: "StereoSimilarity_R2"
Formula: "self * self"

ch2_str$ = string$(channel2)
selectObject: channel1
lr_product = Copy: "StereoSimilarity_LR"
Formula: "self * object[" + ch2_str$ + "]"
mean_LR = Get mean: 0, 0

cov_LR = mean_LR - mean_L * mean_R
correlation_valid = 0
correlation = 0
if sd_L > 1e-12 and sd_R > 1e-12
    correlation = cov_LR / (sd_L * sd_R)
    if correlation > 1
        correlation = 1
    elsif correlation < -1
        correlation = -1
    endif
    correlation_valid = 1
endif

# ============================================================
# MID / SIDE AND STEREO-STATE METRICS
# ============================================================
# Preserve the original Sound time domain by copying a channel rather than
# creating a new 0-based Sound from formula.
selectObject: channel1
mid_sound = Copy: "StereoSimilarity_Mid"
Formula: "(self + object[" + ch2_str$ + "]) / 2"

selectObject: channel1
side_sound = Copy: "StereoSimilarity_Side"
Formula: "(self - object[" + ch2_str$ + "]) / 2"

selectObject: mid_sound
rms_Mid = Get root-mean-square: 0, 0
selectObject: side_sound
rms_Side = Get root-mean-square: 0, 0

eps_level = 1e-12
if rms_Mid > eps_level
    ms_ratio = rms_Side / rms_Mid
else
    if rms_Side > eps_level
        ms_ratio = 1e6
    else
        ms_ratio = 0
    endif
endif

if rms_Mid > eps_level and rms_Side > eps_level
    ms_balance_dB = 20 * log10(rms_Side / rms_Mid)
elsif rms_Mid > eps_level
    ms_balance_dB = -96
elsif rms_Side > eps_level
    ms_balance_dB = 96
else
    ms_balance_dB = 0
endif
if ms_balance_dB > 96
    ms_balance_dB = 96
elsif ms_balance_dB < -96
    ms_balance_dB = -96
endif

# Balance factor: 1 for equal L/R level, 0 for a hard single-channel signal.
level_sum = rms_L + rms_R
if level_sum > eps_level
    balance_factor = 2 * min(rms_L, rms_R) / level_sum
else
    balance_factor = 0
endif

# Diffuse spread is intentionally distinct from anti-phase. Balanced,
# decorrelated stereo approaches 1; centered mono, hard pan, and pure
# anti-phase approach 0 for different reasons.
if correlation_valid
    diffuse_spread = balance_factor * (1 - abs(correlation))
    phase_risk = max(0, -correlation)
else
    diffuse_spread = 0
    phase_risk = 0
endif
if diffuse_spread < 0
    diffuse_spread = 0
elsif diffuse_spread > 1
    diffuse_spread = 1
endif
if phase_risk > 1
    phase_risk = 1
endif

# L/R balance in dB, robust to a silent channel.
lr_balance_dB = 20 * log10((rms_L + eps_level) / (rms_R + eps_level))
if lr_balance_dB > 96
    lr_balance_dB = 96
elsif lr_balance_dB < -96
    lr_balance_dB = -96
endif

# ============================================================
# POLARITY AGREEMENT + NEAR-IDENTITY DIAGNOSTICS
# ============================================================
programme_rms = max(rms_L, rms_R)
sample_gate = max(1e-9, programme_rms * 0.001)
identity_threshold = max(1e-9, programme_rms * 0.001)

selectObject: channel1
active_mask = Copy: "StereoSimilarity_active"
Formula: "if abs(self) >= " + string$(sample_gate) + " or abs(object[" + ch2_str$ + "]) >= " + string$(sample_gate) + " then 1 else 0 fi"
active_fraction = Get mean: 0, 0

selectObject: channel1
polarity_mask = Copy: "StereoSimilarity_polarity"
Formula: "if abs(self) >= " + string$(sample_gate) + " or abs(object[" + ch2_str$ + "]) >= " + string$(sample_gate) + " then if self * object[" + ch2_str$ + "] >= 0 then 1 else 0 fi else 0 fi"
polarity_fraction_all = Get mean: 0, 0

if active_fraction > 0
    polarity_agreement = polarity_fraction_all / active_fraction
else
    polarity_agreement = 0
endif
if polarity_agreement > 1
    polarity_agreement = 1
endif

selectObject: channel1
identity_mask = Copy: "StereoSimilarity_identity"
Formula: "if abs(self - object[" + ch2_str$ + "]) <= " + string$(identity_threshold) + " then 1 else 0 fi"
identity_ratio = Get mean: 0, 0

removeObject: active_mask, polarity_mask, identity_mask

# ============================================================
# SPECTRAL-SHAPE SIMILARITY
# ============================================================
# Nine broad octave-like bands. We compare sqrt(band energy), which gives
# an amplitude-like profile; cosine similarity removes overall gain.
# Bands above Nyquist contribute zero.
band_lo[1] = 0
band_hi[1] = 100
band_lo[2] = 100
band_hi[2] = 200
band_lo[3] = 200
band_hi[3] = 400
band_lo[4] = 400
band_hi[4] = 800
band_lo[5] = 800
band_hi[5] = 1600
band_lo[6] = 1600
band_hi[6] = 3200
band_lo[7] = 3200
band_hi[7] = 6400
band_lo[8] = 6400
band_hi[8] = 12800
band_lo[9] = 12800
band_hi[9] = 20000
n_bands = 9

for b to n_bands
    spec_L[b] = 0
    spec_R[b] = 0
endfor

selectObject: channel1
spectrum_L = To Spectrum: "yes"
for b to n_bands
    lo = band_lo[b]
    hi = band_hi[b]
    if hi > nyquist
        hi = nyquist
    endif
    if hi > lo
        energy = Get band energy: lo, hi
        if energy <> undefined
            if energy > 0
                spec_L[b] = sqrt(energy)
            endif
        endif
    endif
endfor

selectObject: channel2
spectrum_R = To Spectrum: "yes"
for b to n_bands
    lo = band_lo[b]
    hi = band_hi[b]
    if hi > nyquist
        hi = nyquist
    endif
    if hi > lo
        energy = Get band energy: lo, hi
        if energy <> undefined
            if energy > 0
                spec_R[b] = sqrt(energy)
            endif
        endif
    endif
endfor

spec_dot = 0
spec_norm_L = 0
spec_norm_R = 0
spec_sum_L = 0
spec_sum_R = 0
for b to n_bands
    spec_dot = spec_dot + spec_L[b] * spec_R[b]
    spec_norm_L = spec_norm_L + spec_L[b] * spec_L[b]
    spec_norm_R = spec_norm_R + spec_R[b] * spec_R[b]
    spec_sum_L = spec_sum_L + spec_L[b]
    spec_sum_R = spec_sum_R + spec_R[b]
endfor

spectral_similarity_valid = 0
spectral_similarity = 0
if spec_norm_L > 0 and spec_norm_R > 0
    spectral_similarity = spec_dot / sqrt(spec_norm_L * spec_norm_R)
    if spectral_similarity > 1
        spectral_similarity = 1
    elsif spectral_similarity < 0
        spectral_similarity = 0
    endif
    spectral_similarity_valid = 1
endif

for b to n_bands
    if spec_sum_L > 0
        spec_plot_L[b] = spec_L[b] / spec_sum_L
    else
        spec_plot_L[b] = 0
    endif
    if spec_sum_R > 0
        spec_plot_R[b] = spec_R[b] / spec_sum_R
    else
        spec_plot_R[b] = 0
    endif
endfor

removeObject: spectrum_L, spectrum_R

# ============================================================
# TIME-VARYING PEARSON CORRELATION
# ============================================================
hop_size = window_size / 2
max_windows = 6000
if duration <= window_size
    n_windows = 1
    hop_size = window_size
else
    n_windows_raw = floor((duration - window_size) / hop_size) + 1
    if n_windows_raw > max_windows
        n_windows = max_windows
        hop_size = (duration - window_size) / (max_windows - 1)
    else
        n_windows = n_windows_raw
    endif
endif

time_corr# = zero#(n_windows)
time_points# = zero#(n_windows)
time_valid# = zero#(n_windows)
valid_windows = 0
corr_gate = max(1e-9, programme_rms * 0.001)

for w to n_windows
    if n_windows = 1
        t_start = sound_tmin
        t_end = sound_tmax
    else
        t_start = sound_tmin + (w - 1) * hop_size
        t_end = t_start + window_size
        if t_end > sound_tmax
            t_end = sound_tmax
        endif
    endif
    time_points#[w] = (t_start + t_end) / 2

    selectObject: channel1
    local_mean_L = Get mean: t_start, t_end
    selectObject: channel2
    local_mean_R = Get mean: t_start, t_end
    selectObject: l_square
    local_ms_L = Get mean: t_start, t_end
    selectObject: r_square
    local_ms_R = Get mean: t_start, t_end
    selectObject: lr_product
    local_mean_LR = Get mean: t_start, t_end

    local_var_L = local_ms_L - local_mean_L * local_mean_L
    local_var_R = local_ms_R - local_mean_R * local_mean_R
    if local_var_L < 0
        local_var_L = 0
    endif
    if local_var_R < 0
        local_var_R = 0
    endif
    local_sd_L = sqrt(local_var_L)
    local_sd_R = sqrt(local_var_R)
    local_rms_L = sqrt(max(0, local_ms_L))
    local_rms_R = sqrt(max(0, local_ms_R))

    if local_rms_L >= corr_gate and local_rms_R >= corr_gate and local_sd_L > 1e-12 and local_sd_R > 1e-12
        local_cov = local_mean_LR - local_mean_L * local_mean_R
        cval = local_cov / (local_sd_L * local_sd_R)
        if cval > 1
            cval = 1
        elsif cval < -1
            cval = -1
        endif
        time_corr#[w] = cval
        time_valid#[w] = 1
        valid_windows = valid_windows + 1
    else
        time_corr#[w] = 0
        time_valid#[w] = 0
    endif
endfor

if valid_windows > 0
    first_valid = 0
    for w to n_windows
        if time_valid#[w] and first_valid = 0
            min_corr = time_corr#[w]
            max_corr = time_corr#[w]
            first_valid = 1
        elsif time_valid#[w]
            if time_corr#[w] < min_corr
                min_corr = time_corr#[w]
            endif
            if time_corr#[w] > max_corr
                max_corr = time_corr#[w]
            endif
        endif
    endfor
else
    min_corr = 0
    max_corr = 0
endif

# ============================================================
# INTERPRETATION
# ============================================================
if not correlation_valid
    corr_desc$ = "Undefined (constant/silent channel)"
elsif correlation > 0.99
    corr_desc$ = "Nearly identical waveform"
elsif correlation > 0.8
    corr_desc$ = "Strongly correlated"
elsif correlation > 0.4
    corr_desc$ = "Moderately correlated"
elsif correlation > -0.2
    corr_desc$ = "Weakly correlated / decorrelated"
elsif correlation > -0.7
    corr_desc$ = "Negative correlation"
else
    corr_desc$ = "Strong anti-phase risk"
endif

if diffuse_spread < 0.08
    spread_desc$ = "Low diffuse spread"
elsif diffuse_spread < 0.30
    spread_desc$ = "Moderate diffuse spread"
elsif diffuse_spread < 0.65
    spread_desc$ = "Wide / decorrelated"
else
    spread_desc$ = "Highly diffuse"
endif

if phase_risk < 0.05
    phase_desc$ = "Low"
elsif phase_risk < 0.30
    phase_desc$ = "Moderate"
elsif phase_risk < 0.70
    phase_desc$ = "High"
else
    phase_desc$ = "Severe"
endif

if not spectral_similarity_valid
    spectral_desc$ = "Undefined"
elsif spectral_similarity >= 0.995
    spectral_desc$ = "Nearly identical spectral shape"
elsif spectral_similarity >= 0.97
    spectral_desc$ = "Very similar spectral shape"
elsif spectral_similarity >= 0.90
    spectral_desc$ = "Similar spectral shape"
elsif spectral_similarity >= 0.75
    spectral_desc$ = "Moderately different spectral shape"
else
    spectral_desc$ = "Different spectral shape"
endif

# ============================================================
# INFO REPORT
# ============================================================
writeInfoLine: "=== Stereo Channel Similarity Meter v0.3 ==="
appendInfoLine: "File: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", samplingRate, " Hz"
appendInfoLine: "Analysis window: ", fixed$(window_size * 1000, 1), " ms"
appendInfoLine: "Correlation windows: ", n_windows, " (", valid_windows, " valid), hop ", fixed$(hop_size * 1000, 1), " ms"
appendInfoLine: ""

appendInfoLine: "--- Waveform relationship ---"
if correlation_valid
    appendInfoLine: "Global Pearson correlation: ", fixed$(correlation, 4), "  |  ", corr_desc$
else
    appendInfoLine: "Global Pearson correlation: undefined  |  ", corr_desc$
endif
if valid_windows > 0
    appendInfoLine: "Valid local-correlation range: ", fixed$(min_corr, 3), " to ", fixed$(max_corr, 3)
else
    appendInfoLine: "Valid local-correlation range: none (signal too quiet/constant in analysis windows)"
endif
appendInfoLine: "Polarity agreement (active samples): ", fixed$(polarity_agreement * 100, 1), "%"
appendInfoLine: "Near-identical samples: ", fixed$(identity_ratio * 100, 1), "%  (|L-R| <= ", fixed$(identity_threshold, 7), ")"
appendInfoLine: ""

appendInfoLine: "--- Stereo state ---"
appendInfoLine: "Diffuse stereo spread: ", fixed$(diffuse_spread, 3), "  |  ", spread_desc$
appendInfoLine: "Phase risk: ", fixed$(phase_risk, 3), "  |  ", phase_desc$
appendInfoLine: "Side/Mid RMS ratio: ", fixed$(ms_ratio, 3)
appendInfoLine: "Side/Mid balance: ", fixed$(ms_balance_dB, 1), " dB"
appendInfoLine: "L/R balance: ", fixed$(lr_balance_dB, 1), " dB"
appendInfoLine: ""

appendInfoLine: "--- Spectral shape ---"
if spectral_similarity_valid
    appendInfoLine: "Broad-band spectral similarity: ", fixed$(spectral_similarity, 4), "  |  ", spectral_desc$
else
    appendInfoLine: "Broad-band spectral similarity: undefined"
endif

if show_detailed_report
    appendInfoLine: ""
    appendInfoLine: "--- Detailed statistics ---"
    appendInfoLine: "Left mean: ", fixed$(mean_L, 7), "   RMS: ", fixed$(rms_L, 6), "   sigma: ", fixed$(sd_L, 6)
    appendInfoLine: "Right mean: ", fixed$(mean_R, 7), "   RMS: ", fixed$(rms_R, 6), "   sigma: ", fixed$(sd_R, 6)
    appendInfoLine: "Mid RMS: ", fixed$(rms_Mid, 6), "   Side RMS: ", fixed$(rms_Side, 6)
    appendInfoLine: "Balanced-channel factor: ", fixed$(balance_factor, 4)
    appendInfoLine: "Active-sample fraction: ", fixed$(active_fraction * 100, 1), "%"
    appendInfoLine: ""
    appendInfoLine: "Spectral bands (sqrt energy; L / R):"
    for b to n_bands
        band_end = min(band_hi[b], nyquist)
        if band_end > band_lo[b]
            appendInfoLine: "  ", fixed$(band_lo[b], 0), "-", fixed$(band_end, 0), " Hz: ", fixed$(spec_L[b], 6), " / ", fixed$(spec_R[b], 6)
        endif
    endfor
endif

# ============================================================
# VISUALIZATION
# ============================================================
if show_visualization
    Erase all

    # Waveform scale shared by L and R.
    selectObject: channel1
    peak_L = Get absolute extremum: 0, 0, "Sinc70"
    selectObject: channel2
    peak_R = Get absolute extremum: 0, 0, "Sinc70"
    wave_peak = max(peak_L, peak_R)
    if wave_peak = undefined
        wave_peak = 1
    elsif wave_peak <= 0
        wave_peak = 1
    else
        wave_peak = wave_peak * 1.03
    endif

    # === TITLE STRIP ===
    Select outer viewport: 0, 8, 0.0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.56, "half", "##Stereo Channel Similarity##"

    Select outer viewport: 0, 8, 0.48, 0.82
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.5, "centre", 0.55, "half", displayName$ + "   |   " + fixed$(duration, 2) + " s   |   " + string$(samplingRate) + " Hz"

    # === PANEL 1: L/R WAVEFORMS ON THE SAME SCALE ===
    Select outer viewport: 0, 8, 0.90, 2.55
    Select inner viewport: 0.70, 7.30, 1.10, 2.38
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Colour: "{0.97, 0.97, 0.98}"
    Paint rectangle: "{0.97, 0.97, 0.98}", sound_tmin, sound_tmax, -wave_peak, wave_peak

    Select inner viewport: 0.70, 7.30, 1.10, 2.38
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    selectObject: channel1
    Colour: "{0.20, 0.45, 0.78}"
    Draw: sound_tmin, sound_tmax, -wave_peak, wave_peak, "no", "Curve"
    selectObject: channel2
    Colour: "{0.82, 0.35, 0.28}"
    Draw: sound_tmin, sound_tmax, -wave_peak, wave_peak, "no", "Curve"

    Select inner viewport: 0.70, 7.30, 1.10, 2.38
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.70, 7.30, 1.10, 2.38
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Font size: 7
    Marks left: 2, "yes", "yes", "no"
    Select inner viewport: 0.70, 7.30, 1.10, 2.38
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Text left: "yes", "Amplitude"
    Select inner viewport: 0.70, 7.30, 1.10, 2.38
    Axes: sound_tmin, sound_tmax, -wave_peak, wave_peak
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 0.82, 1.08
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Left / Right Waveforms - shared amplitude scale##"

    # === PANEL 2: TIME-VARYING CORRELATION ===
    Select outer viewport: 0, 8, 2.72, 4.38
    Select inner viewport: 0.70, 7.30, 2.95, 4.20
    Axes: sound_tmin, sound_tmax, -1, 1
    Colour: "{0.97, 0.97, 0.98}"
    Paint rectangle: "{0.97, 0.97, 0.98}", sound_tmin, sound_tmax, -1, 1
    Select inner viewport: 0.70, 7.30, 2.95, 4.20
    Axes: sound_tmin, sound_tmax, -1, 1
    Colour: "{0.80, 0.80, 0.85}"
    Draw line: sound_tmin, 0, sound_tmax, 0

    Colour: "{0.20, 0.45, 0.78}"
    Line width: 1.5
    for w from 2 to n_windows
        if time_valid#[w - 1] and time_valid#[w]
            Draw line: time_points#[w - 1], time_corr#[w - 1], time_points#[w], time_corr#[w]
        endif
    endfor
    Line width: 1

    if correlation_valid
        Colour: "{0.82, 0.35, 0.28}"
        Dotted line
        Draw line: sound_tmin, correlation, sound_tmax, correlation
        Solid line
    endif

    Select inner viewport: 0.70, 7.30, 2.95, 4.20
    Axes: sound_tmin, sound_tmax, -1, 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.70, 7.30, 2.95, 4.20
    Axes: sound_tmin, sound_tmax, -1, 1
    Font size: 7
    Marks left: 4, "yes", "yes", "no"
    Select inner viewport: 0.70, 7.30, 2.95, 4.20
    Axes: sound_tmin, sound_tmax, -1, 1
    Text left: "yes", "Pearson r"
    Select inner viewport: 0.70, 7.30, 2.95, 4.20
    Axes: sound_tmin, sound_tmax, -1, 1
    Text bottom: "yes", "Time (s)"

    Select outer viewport: 0, 8, 2.55, 2.90
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "##Time-varying Correlation##   blue = valid windows   red = global r"

    # === PANEL 3: SPECTRAL SHAPE ===
    Select outer viewport: 0, 8, 4.55, 6.38
    Select inner viewport: 0.70, 7.30, 4.82, 6.18
    max_spec_plot = 0
    for b to n_bands
        if spec_plot_L[b] > max_spec_plot
            max_spec_plot = spec_plot_L[b]
        endif
        if spec_plot_R[b] > max_spec_plot
            max_spec_plot = spec_plot_R[b]
        endif
    endfor
    if max_spec_plot <= 0
        max_spec_plot = 1
    else
        max_spec_plot = max_spec_plot * 1.15
    endif
    Axes: 0.5, n_bands + 0.5, 0, max_spec_plot
    Colour: "{0.97, 0.97, 0.98}"
    Paint rectangle: "{0.97, 0.97, 0.98}", 0.5, n_bands + 0.5, 0, max_spec_plot

    for b to n_bands
        Select inner viewport: 0.70, 7.30, 4.82, 6.18
        Axes: 0.5, n_bands + 0.5, 0, max_spec_plot
        Colour: "{0.20, 0.45, 0.78}"
        Paint rectangle: "{0.20, 0.45, 0.78}", b - 0.31, b - 0.03, 0, spec_plot_L[b]
        Select inner viewport: 0.70, 7.30, 4.82, 6.18
        Axes: 0.5, n_bands + 0.5, 0, max_spec_plot
        Colour: "{0.82, 0.35, 0.28}"
        Paint rectangle: "{0.82, 0.35, 0.28}", b + 0.03, b + 0.31, 0, spec_plot_R[b]
    endfor

    Select inner viewport: 0.70, 7.30, 4.82, 6.18
    Axes: 0.5, n_bands + 0.5, 0, max_spec_plot
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.70, 7.30, 4.82, 6.18
    Axes: 0.5, n_bands + 0.5, 0, max_spec_plot
    Font size: 7
    Text left: "yes", "Normalized band amplitude"

    # Manual frequency labels keep them readable and avoid scientific notation.
    bandLabel$[1] = "<100"
    bandLabel$[2] = "100-200"
    bandLabel$[3] = "200-400"
    bandLabel$[4] = "400-800"
    bandLabel$[5] = "0.8-1.6k"
    bandLabel$[6] = "1.6-3.2k"
    bandLabel$[7] = "3.2-6.4k"
    bandLabel$[8] = "6.4-12.8k"
    bandLabel$[9] = "12.8-20k"
    for b to n_bands
        Select inner viewport: 0.70, 7.30, 4.82, 6.18
        Axes: 0.5, n_bands + 0.5, 0, max_spec_plot
        Font size: 5
        Colour: "Black"
        Text: b, "centre", -0.055 * max_spec_plot, "top", bandLabel$[b]
    endfor

    Select outer viewport: 0, 8, 4.38, 4.76
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    if spectral_similarity_valid
        Text: 0.5, "centre", 0.55, "half", "##Broad-band Spectral Shape##   L=blue  R=red   cosine similarity = " + fixed$(spectral_similarity, 3)
    else
        Text: 0.5, "centre", 0.55, "half", "##Broad-band Spectral Shape##   similarity undefined"
    endif

    # === SUMMARY STRIP ===
    Select outer viewport: 0, 8, 6.62, 7.92
    Select inner viewport: 0.55, 7.45, 6.72, 7.82
    Axes: 0, 1, 0, 1
    Colour: "{0.94, 0.94, 0.95}"
    Paint rectangle: "{0.94, 0.94, 0.95}", 0, 1, 0, 1

    Select inner viewport: 0.55, 7.45, 6.72, 7.82
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Stereo state##"

    Select inner viewport: 0.55, 7.45, 6.72, 7.82
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.25, 0.25, 0.32}"
    if correlation_valid
        corrText$ = fixed$(correlation, 3)
    else
        corrText$ = "undef"
    endif
    if spectral_similarity_valid
        specText$ = fixed$(spectral_similarity, 3)
    else
        specText$ = "undef"
    endif
    Text: 0.02, "left", 0.47, "half", "Correlation: " + corrText$ + "    Spectral: " + specText$ + "    Diffuse spread: " + fixed$(diffuse_spread, 3) + "    Phase risk: " + fixed$(phase_risk, 3)

    Select inner viewport: 0.55, 7.45, 6.72, 7.82
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.38, 0.38, 0.45}"
    Text: 0.02, "left", 0.18, "half", "M/S: " + fixed$(ms_balance_dB, 1) + " dB    L/R: " + fixed$(lr_balance_dB, 1) + " dB    Polarity agreement: " + fixed$(polarity_agreement * 100, 1) + "%    Valid windows: " + string$(valid_windows) + "/" + string$(n_windows)

    Select inner viewport: 0.55, 7.45, 6.72, 7.82
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: l_square, r_square, lr_product, channel1, channel2, mid_sound, side_sound
selectObject: sound
appendInfoLine: ""
appendInfoLine: "Done."
