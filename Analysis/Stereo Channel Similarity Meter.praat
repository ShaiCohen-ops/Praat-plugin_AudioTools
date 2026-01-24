# ============================================================
# Praat AudioTools - Stereo Channel Similarity Meter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Comprehensive stereo channel analysis tool. Measures channel
#   correlation, Mid/Side balance, phase coherence, and spectral
#   similarity between left and right channels.
#
# Changelog v0.2:
#   - Added Pearson correlation coefficient
#   - Added Mid/Side (M/S) energy analysis
#   - Added stereo width metric
#   - Added phase coherence measurement
#   - Added time-varying correlation curve
#   - Added visualization
#   - Fixed syntax (!=, select, echo)
#   - Vectorized for performance
#
# Usage:
#   Select a stereo Sound object in Praat and run this script.
# ============================================================

form Stereo Channel Similarity Meter
    comment === Analysis Options ===
    positive Window_size_seconds 0.1
    comment (for time-varying analysis)
    boolean Show_visualization 1
    boolean Show_detailed_report 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: sound
numberOfChannels = Get number of channels

if numberOfChannels <> 2
    exitScript: "This is not a stereo file. It has " + string$(numberOfChannels) + " channel(s)."
endif

selectObject: sound
duration = Get total duration
samplingRate = Get sampling frequency
totalSamples = Get number of samples

writeInfoLine: "=== Stereo Channel Similarity Meter v0.2 ==="
appendInfoLine: "File: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Sample rate: ", samplingRate, " Hz"
appendInfoLine: ""

# === EXTRACT CHANNELS ===
selectObject: sound
channel1 = Extract one channel: 1
Rename: "Left"

selectObject: sound
channel2 = Extract one channel: 2
Rename: "Right"

# === 1. GLOBAL PEARSON CORRELATION ===
appendInfoLine: "Computing correlation..."

# Get channel statistics
selectObject: channel1
mean_L = Get mean: 0, 0
stdev_L = Get standard deviation: 0, 0
rms_L = Get root-mean-square: 0, 0

selectObject: channel2
mean_R = Get mean: 0, 0
stdev_R = Get standard deviation: 0, 0
rms_R = Get root-mean-square: 0, 0

# Compute correlation using formula
# r = sum((L - mean_L)(R - mean_R)) / (n * stdev_L * stdev_R)

# Create difference signals for computation
selectObject: channel1
ch1_centered = Copy: "L_centered"
Formula: "self - " + string$(mean_L)

selectObject: channel2
ch2_centered = Copy: "R_centered"
Formula: "self - " + string$(mean_R)

# Multiply centered channels
selectObject: ch1_centered
product = Copy: "product"
ch2_str$ = string$(ch2_centered)
Formula: "self * object[" + ch2_str$ + "]"

# Get sum of products
selectObject: product
sum_product = Get mean: 0, 0
sum_product = sum_product * totalSamples

# Pearson correlation
if stdev_L > 0 and stdev_R > 0
    correlation = sum_product / (totalSamples * stdev_L * stdev_R)
else
    correlation = 0
endif

# Clamp to valid range
if correlation > 1
    correlation = 1
elsif correlation < -1
    correlation = -1
endif

removeObject: ch1_centered, ch2_centered, product

# === 2. MID/SIDE ANALYSIS ===
appendInfoLine: "Computing Mid/Side balance..."

# Mid = (L + R) / 2, Side = (L - R) / 2
ch1_str$ = string$(channel1)
ch2_str$ = string$(channel2)

Create Sound from formula: "Mid", 1, 0, duration, samplingRate, 
    ... "(object[" + ch1_str$ + "] + object[" + ch2_str$ + "]) / 2"
mid_sound = selected("Sound")

Create Sound from formula: "Side", 1, 0, duration, samplingRate, 
    ... "(object[" + ch1_str$ + "] - object[" + ch2_str$ + "]) / 2"
side_sound = selected("Sound")

# Get RMS of Mid and Side
selectObject: mid_sound
rms_Mid = Get root-mean-square: 0, 0

selectObject: side_sound
rms_Side = Get root-mean-square: 0, 0

# Stereo width: ratio of Side to Mid energy
if rms_Mid > 0.0001
    stereo_width = rms_Side / rms_Mid
else
    stereo_width = 0
endif

# M/S balance in dB
if rms_Mid > 0.0001 and rms_Side > 0.0001
    ms_balance_dB = 20 * log10(rms_Side / rms_Mid)
else
    ms_balance_dB = -96
endif

# === 3. CHANNEL BALANCE ===
if rms_R > 0.0001
    lr_balance = rms_L / rms_R
else
    lr_balance = 1
endif

lr_balance_dB = 20 * log10(lr_balance)

# === 4. PHASE COHERENCE ===
# Count samples where L and R have same sign
selectObject: channel1
phase_check = Copy: "phase_check"
Formula: "if self * object[" + ch2_str$ + "] >= 0 then 1 else 0 fi"

selectObject: phase_check
phase_coherence = Get mean: 0, 0

removeObject: phase_check

# === 5. SAMPLE IDENTITY (original metric, improved) ===
# Count samples where |L - R| < threshold
selectObject: channel1
diff_check = Copy: "diff_check"
Formula: "if abs(self - object[" + ch2_str$ + "]) < 0.001 then 1 else 0 fi"

selectObject: diff_check
identity_ratio = Get mean: 0, 0

removeObject: diff_check

# === 6. TIME-VARYING CORRELATION ===
appendInfoLine: "Computing time-varying correlation..."

hop_size = window_size_seconds / 2
n_windows = floor((duration - window_size_seconds) / hop_size) + 1
if n_windows < 1
    n_windows = 1
endif

time_corr# = zero#(n_windows)
time_points# = zero#(n_windows)

for w to n_windows
    t_start = (w - 1) * hop_size
    t_end = t_start + window_size_seconds
    if t_end > duration
        t_end = duration
    endif
    
    time_points#[w] = t_start + window_size_seconds / 2
    
    # Get local statistics
    selectObject: channel1
    local_mean_L = Get mean: t_start, t_end
    local_stdev_L = Get standard deviation: t_start, t_end
    
    selectObject: channel2
    local_mean_R = Get mean: t_start, t_end
    local_stdev_R = Get standard deviation: t_start, t_end
    
    # Extract windows
    selectObject: channel1
    win_L = Extract part: t_start, t_end, "rectangular", 1, "no"
    Formula: "self - " + string$(local_mean_L)
    
    selectObject: channel2
    win_R = Extract part: t_start, t_end, "rectangular", 1, "no"
    Formula: "self - " + string$(local_mean_R)
    
    # Compute local correlation
    win_R_str$ = string$(win_R)
    selectObject: win_L
    Formula: "self * object[" + win_R_str$ + "]"
    local_sum = Get mean: 0, 0
    local_n = Get number of samples
    
    if local_stdev_L > 0.0001 and local_stdev_R > 0.0001
        time_corr#[w] = local_sum / (local_stdev_L * local_stdev_R)
        if time_corr#[w] > 1
            time_corr#[w] = 1
        elsif time_corr#[w] < -1
            time_corr#[w] = -1
        endif
    else
        time_corr#[w] = 1
    endif
    
    removeObject: win_L, win_R
endfor

# Get correlation statistics
min_corr = time_corr#[1]
max_corr = time_corr#[1]
for w to n_windows
    if time_corr#[w] < min_corr
        min_corr = time_corr#[w]
    endif
    if time_corr#[w] > max_corr
        max_corr = time_corr#[w]
    endif
endfor

# === 7. INTERPRETATION ===
# Correlation interpretation
if correlation > 0.99
    corr_desc$ = "Mono (channels nearly identical)"
elsif correlation > 0.95
    corr_desc$ = "Very narrow stereo"
elsif correlation > 0.8
    corr_desc$ = "Narrow stereo"
elsif correlation > 0.5
    corr_desc$ = "Normal stereo"
elsif correlation > 0.2
    corr_desc$ = "Wide stereo"
elsif correlation > -0.2
    corr_desc$ = "Very wide / decorrelated"
else
    corr_desc$ = "Out of phase (potential issue)"
endif

# Width interpretation
if stereo_width < 0.05
    width_desc$ = "Mono"
elsif stereo_width < 0.2
    width_desc$ = "Narrow"
elsif stereo_width < 0.5
    width_desc$ = "Normal"
elsif stereo_width < 1.0
    width_desc$ = "Wide"
else
    width_desc$ = "Very wide / M-S imbalanced"
endif

# === 8. VISUALIZATION ===
if show_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Analysis: " + soundName$
    
    # --- Waveforms (L and R overlaid) ---
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.4, 7.6, 0.7, 1.9
    
    selectObject: channel1
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    selectObject: channel2
    Colour: "{0.8, 0.4, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "L (blue) / R (red)"
    Text bottom: "yes", "Time (s)"
    
    # --- Difference signal ---
    Select outer viewport: 0, 4, 2.2, 3.2
    Select inner viewport: 0.4, 3.8, 2.3, 3.1
    
    selectObject: side_sound
    Colour: "{0.5, 0.7, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Side (L-R)"
    
    # --- Mid signal ---
    Select outer viewport: 4, 8, 2.2, 3.2
    Select inner viewport: 4.4, 7.8, 2.3, 3.1
    
    selectObject: mid_sound
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mid (L+R)"
    Text bottom: "yes", "Time (s)"
    
    # --- Time-varying correlation ---
    Select outer viewport: 0, 8, 3.4, 4.6
    Select inner viewport: 0.4, 7.6, 3.5, 4.5
    
    Axes: 0, duration, -1, 1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, -1, 1
    
    # Reference lines
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, duration, 0
    Colour: "{0.9, 0.9, 0.9}"
    Draw line: 0, 0.5, duration, 0.5
    Draw line: 0, -0.5, duration, -0.5
    
    # Correlation curve
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1.5
    for w from 2 to n_windows
        Draw line: time_points#[w-1], time_corr#[w-1], time_points#[w], time_corr#[w]
    endfor
    
    # Mean correlation line
    Colour: "{0.8, 0.4, 0.2}"
    Line width: 1
    Dotted line
    Draw line: 0, correlation, duration, correlation
    Solid line
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Correlation"
    Text bottom: "yes", "Time (s)"
    
    # --- Meter display ---
    Select outer viewport: 0, 8, 4.8, 5.8
    Select inner viewport: 0.5, 7.5, 4.9, 5.7
    
    Axes: 0, 10, 0, 3
    
    # Correlation meter
    Colour: "{0.9, 0.9, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, 10, 2, 3
    
    # Fill based on correlation (0-10 scale, where 5 = 0 correlation)
    meter_val = (correlation + 1) / 2 * 10
    if correlation > 0.5
        col$ = "{0.4, 0.7, 0.4}"
    elsif correlation > 0
        col$ = "{0.7, 0.7, 0.4}"
    elsif correlation > -0.5
        col$ = "{0.8, 0.6, 0.3}"
    else
        col$ = "{0.8, 0.3, 0.3}"
    endif
    Paint rectangle: col$, 0, meter_val, 2.1, 2.9
    
    Colour: "Black"
    Line width: 1
    Draw rectangle: 0, 10, 2, 3
    Font size: 6
    Text: 0, "left", 2.5, "half", " -1"
    Text: 5, "centre", 2.5, "half", "0"
    Text: 10, "right", 2.5, "half", "+1 "
    Font size: 7
    Text: 5, "centre", 3.3, "half", "Correlation: " + fixed$(correlation, 3) + " (" + corr_desc$ + ")"
    
    # Width meter
    Colour: "{0.9, 0.9, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, 10, 0.5, 1.5
    
    width_meter = min(10, stereo_width * 5)
    Paint rectangle: "{0.4, 0.6, 0.8}", 0, width_meter, 0.6, 1.4
    
    Colour: "Black"
    Line width: 1
    Draw rectangle: 0, 10, 2, 3
    Font size: 6
    Text: 0, "left", 2.5, "half", " -1"
    Text: 5, "centre", 2.5, "half", "0"
    Text: 10, "right", 2.5, "half", "+1 "
    Font size: 7
    Text: 5, "centre", 3.3, "half", "Correlation: " + fixed$(correlation, 3) + " (" + corr_desc$ + ")"
    
    # Width meter
    Colour: "{0.9, 0.9, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.9}", 0, 10, 0.5, 1.5
    
    width_meter = min(10, stereo_width * 5)
    Colour: "{0.4, 0.6, 0.8}"
    Paint rectangle: "{0.4, 0.6, 0.8}", 0, width_meter, 0.6, 1.4
    
    Colour: "Black"
    Draw rectangle: 0, 10, 0.5, 1.5
    Font size: 6
    Text: 0, "left", 1.0, "half", " 0"
    Text: 5, "centre", 1.0, "half", "1"
    Text: 10, "right", 1.0, "half", "2+ "
    Font size: 7
    Text: 5, "centre", 1.8, "half", "Stereo Width: " + fixed$(stereo_width, 2) + " (" + width_desc$ + ")"
    
    Font size: 10
    Colour: "Black"
endif

# === 9. REPORT ===
appendInfoLine: "=== RESULTS ==="
appendInfoLine: ""
appendInfoLine: "--- Correlation ---"
appendInfoLine: "Global correlation: ", fixed$(correlation, 4)
appendInfoLine: "Interpretation: ", corr_desc$
appendInfoLine: "Correlation range: ", fixed$(min_corr, 3), " to ", fixed$(max_corr, 3)
appendInfoLine: ""
appendInfoLine: "--- Stereo Width ---"
appendInfoLine: "Width (Side/Mid ratio): ", fixed$(stereo_width, 3)
appendInfoLine: "M/S balance: ", fixed$(ms_balance_dB, 1), " dB"
appendInfoLine: "Interpretation: ", width_desc$
appendInfoLine: ""
appendInfoLine: "--- Channel Balance ---"
appendInfoLine: "L/R RMS ratio: ", fixed$(lr_balance, 3)
appendInfoLine: "L/R balance: ", fixed$(lr_balance_dB, 1), " dB"
appendInfoLine: "Left RMS: ", fixed$(rms_L, 4)
appendInfoLine: "Right RMS: ", fixed$(rms_R, 4)
appendInfoLine: ""
appendInfoLine: "--- Phase ---"
appendInfoLine: "Phase coherence: ", fixed$(phase_coherence * 100, 1), "%"
appendInfoLine: "(% of time L and R have same polarity)"
appendInfoLine: ""
appendInfoLine: "--- Sample Identity ---"
appendInfoLine: "Identical samples: ", fixed$(identity_ratio * 100, 1), "%"
appendInfoLine: "(samples where |L-R| < 0.001)"

if show_detailed_report
    appendInfoLine: ""
    appendInfoLine: "--- Detailed Statistics ---"
    appendInfoLine: "Left mean: ", fixed$(mean_L, 6)
    appendInfoLine: "Right mean: ", fixed$(mean_R, 6)
    appendInfoLine: "Left stdev: ", fixed$(stdev_L, 4)
    appendInfoLine: "Right stdev: ", fixed$(stdev_R, 4)
    appendInfoLine: "Mid RMS: ", fixed$(rms_Mid, 4)
    appendInfoLine: "Side RMS: ", fixed$(rms_Side, 4)
endif

appendInfoLine: ""
appendInfoLine: "Done!"

# === CLEANUP ===
removeObject: channel1, channel2, mid_sound, side_sound

selectObject: sound