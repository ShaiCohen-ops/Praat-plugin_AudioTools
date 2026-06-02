# ============================================================
# Praat AudioTools - Time-domain RMS Envelope Follower
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time-domain RMS Envelope Follower
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.1:
#   - Replaced non-ASCII box-drawing/dash characters with ASCII for
#     console portability.
#   - Extract mode emits silence (not DC) when no signal exceeds threshold.
#   - Transfer mode documents the donor/recipient duration behaviour and
#     notes it in the stats when the recipient is longer than the donor.
# ============================================================

form Time-domain RMS Envelope Follower
    # --- Mode & Selection ---
    optionmenu Mode: 2
        option Extract (envelope only)
        option Gate / Expand
        option Reverse (swell/ghost)
        option Duck (inverse)
        option Transfer (from donor)
        
    # --- Presets (New!) ---
    optionmenu Preset: 1
        option Custom (use settings below)
        option Snappy (Percussion)
        option Smooth (Vocals/Speech)
        option Sustain (Pads/Texture)
        option Crunch (Aggressive)
    
    comment -------------------------------------------------------------------
    comment Transfer: Select 2 sounds (1=Donor, 2=Recipient). Others: Select 1.
    
    # --- Envelope Timing ---
    positive Attack_time_ms 5
    positive Release_time_ms 50
    
    # --- Threshold & Shaping ---
    real Threshold_dB -40
    real Range_dB 60
    positive Curve_exponent 1.0
    
    # --- Performance & Output ---
    boolean Use_downsampling 1
    positive Processing_sample_rate 16000
    positive Scale_peak 0.99
    boolean Show_visualization 1
    boolean Show_statistics 1
    boolean Play_after_processing 1
endform

# ============================================================
# 0. PRESET LOGIC (New!)
# ============================================================

# If a preset is selected (not Custom), overwrite variables
if preset = 2
    # Snappy (Percussion)
    attack_time_ms = 2
    release_time_ms = 30
    threshold_dB = -30
    range_dB = 60
    curve_exponent = 0.5
elsif preset = 3
    # Smooth (Vocals)
    attack_time_ms = 20
    release_time_ms = 200
    threshold_dB = -45
    range_dB = 40
    curve_exponent = 1.0
elsif preset = 4
    # Sustain (Pads)
    attack_time_ms = 200
    release_time_ms = 800
    threshold_dB = -50
    range_dB = 30
    curve_exponent = 1.5
elsif preset = 5
    # Crunch (Aggressive)
    attack_time_ms = 1
    release_time_ms = 10
    threshold_dB = -20
    range_dB = 80
    curve_exponent = 0.3
endif

# ============================================================
# 1. VALIDATION & SETUP
# ============================================================

n_selected = numberOfSelected("Sound")

# Validate selection based on mode
if mode = 5
    # Transfer mode requires exactly 2 sounds
    if n_selected <> 2
        exitScript: "Transfer mode requires exactly TWO Sound objects:" + newline$ +
        ... "  1st selected = Envelope DONOR" + newline$ +
        ... "  2nd selected = Sound RECIPIENT"
    endif
    donor_id = selected("Sound", 1)
    recipient_id = selected("Sound", 2)
    donor_name$ = selected$("Sound", 1)
    recipient_name$ = selected$("Sound", 2)
    source_id = donor_id
    source_name$ = donor_name$
else
    # All other modes require exactly 1 sound
    if n_selected <> 1
        exitScript: "Please select exactly ONE Sound object."
    endif
    source_id = selected("Sound")
    source_name$ = selected$("Sound")
endif

# Get source properties
selectObject: source_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
duration = Get total duration
recipient_dur = duration

# Mode suffix for output naming
if mode = 1
    suffix$ = "_Envelope"
    mode$ = "Extract"
elsif mode = 2
    suffix$ = "_Gated"
    mode$ = "Gate/Expand"
elsif mode = 3
    suffix$ = "_Reverse"
    mode$ = "Reverse"
elsif mode = 4
    suffix$ = "_Ducked"
    mode$ = "Duck"
else
    suffix$ = "_Transfer"
    mode$ = "Transfer"
endif

# Preset name for display
if preset = 1
    preset$ = "Custom"
elsif preset = 2
    preset$ = "Snappy"
elsif preset = 3
    preset$ = "Smooth"
elsif preset = 4
    preset$ = "Sustain"
else
    preset$ = "Crunch"
endif

# ============================================================
# 2. CREATE WORKING COPY FOR ENVELOPE EXTRACTION
# ============================================================

if mode = 5
    selectObject: donor_id
else
    selectObject: source_id
endif

# Convert to mono for envelope calculation
if n_channels > 1
    work_id = Convert to mono
else
    work_id = Copy: "working_copy"
endif

# ============================================================
# 3. OPTIONAL DOWNSAMPLING
# ============================================================

selectObject: work_id
current_sr = Get sampling frequency
did_downsample = 0
env_sr = current_sr

if use_downsampling and processing_sample_rate < current_sr
    downsampled_id = Resample: processing_sample_rate, 50
    removeObject: work_id
    work_id = downsampled_id
    did_downsample = 1
    env_sr = processing_sample_rate
endif

# ============================================================
# 4. RMS ENVELOPE EXTRACTION
# ============================================================

selectObject: work_id
env_id = Copy: "envelope_raw"

# A. Rectify
Formula: "self * self"

# B. Smoothing
attack_hz = 1000 / (2 * pi * attack_time_ms)
release_hz = 1000 / (2 * pi * release_time_ms)

primary_hz = max(attack_hz, release_hz)
secondary_hz = min(attack_hz, release_hz)

# Primary smoothing pass
selectObject: env_id
filtered_id = Filter (pass Hann band): 0, primary_hz, primary_hz * 0.5
removeObject: env_id
env_id = filtered_id

# Secondary smoothing
selectObject: env_id
if attack_hz <> release_hz
    slow_env_id = Filter (pass Hann band): 0, secondary_hz, secondary_hz * 0.5
    selectObject: env_id
    slow_str$ = string$(slow_env_id)
    if attack_hz > release_hz
        Formula: "if self > object(" + slow_str$ + ", x) then self else object(" + slow_str$ + ", x) fi"
    else
        Formula: "if self < object(" + slow_str$ + ", x) then self else object(" + slow_str$ + ", x) fi"
    endif
    removeObject: slow_env_id
endif

# C. Square root
selectObject: env_id
Formula: "sqrt(abs(self))"

# ============================================================
# 5. THRESHOLD & RANGE PROCESSING
# ============================================================

selectObject: env_id
env_max = Get maximum: 0, 0, "Parabolic"
env_min = Get minimum: 0, 0, "Parabolic"
env_mean = Get mean: 0, 0
env_rms = Get root-mean-square: 0, 0

# Convert threshold/range
threshold_linear = 10 ^ (threshold_dB / 20)
range_linear = 10 ^ (range_dB / 20)
env_max_viz = env_max

# Apply threshold
selectObject: env_id
Formula: "max(self, threshold_linear)"

# Normalize
selectObject: env_id
current_max = Get maximum: 0, 0, "Parabolic"
signal_present = current_max > threshold_linear
denom = (min(current_max, threshold_linear * range_linear) - threshold_linear)
if denom = 0
    denom = 1
endif

if current_max > threshold_linear
    Formula: "(self - threshold_linear) / denom"
    Formula: "min(max(self, 0), 1)"
endif

# ============================================================
# 6. ENVELOPE CURVE SHAPING
# ============================================================

selectObject: env_id
if curve_exponent <> 1.0
    Formula: "self ^ curve_exponent"
endif

# ============================================================
# 7. MODE-SPECIFIC PROCESSING
# ============================================================

# --- MODE 1: Extract ---
if mode = 1
    selectObject: env_id
    # With no signal above threshold the envelope is a constant floor;
    # scaling that to peak would emit DC, so emit silence instead.
    if not signal_present
        Formula: "0"
    endif
    if did_downsample
        result_id = Resample: orig_sr, 50
        Rename: source_name$ + suffix$
    else
        result_id = Copy: source_name$ + suffix$
    endif
    if signal_present
        Scale peak: scale_peak
    endif

# --- MODE 2: Gate / Expand ---
elsif mode = 2
    selectObject: source_id
    result_id = Copy: source_name$ + suffix$
    env_str$ = string$(env_id)
    Formula: "self * object(" + env_str$ + ", x)"
    Scale peak: scale_peak

# --- MODE 3: Reverse ---
elsif mode = 3
    selectObject: env_id
    Reverse
    selectObject: source_id
    result_id = Copy: source_name$ + suffix$
    env_str$ = string$(env_id)
    Formula: "self * object(" + env_str$ + ", x)"
    Scale peak: scale_peak

# --- MODE 4: Duck ---
elsif mode = 4
    selectObject: env_id
    Formula: "1 - self"
    selectObject: source_id
    result_id = Copy: source_name$ + suffix$
    env_str$ = string$(env_id)
    Formula: "self * object(" + env_str$ + ", x)"
    Scale peak: scale_peak

# --- MODE 5: Transfer ---
# The donor envelope is sampled by time via object(env, x). If the recipient
# is longer than the donor, object() returns 0 past the donor's end (output
# silent there); a longer donor is truncated to the recipient's length.
elsif mode = 5
    selectObject: recipient_id
    recipient_dur = Get total duration
    result_id = Copy: recipient_name$ + "_from_" + donor_name$
    env_str$ = string$(env_id)
    Formula: "self * object(" + env_str$ + ", x)"
    Scale peak: scale_peak
endif

# ============================================================
# 8. VISUALIZATION (Green Upper Curve)
# ============================================================

if show_visualization
    selectObject: env_id
    if did_downsample
        vis_env_id = Resample: orig_sr, 50
    else
        vis_env_id = Copy: "vis_envelope"
    endif
    selectObject: vis_env_id
    Scale peak: 0.8
    
    if mode = 5
        selectObject: recipient_id
    else
        selectObject: source_id
    endif
    vis_source_id = Copy: "vis_source"
    Scale peak: 0.9
    
    Erase all
    Font size: 10
    
    # === PANEL 1: TRANSFER CURVE (TOP) ===
    Select outer viewport: 0, 4, 0, 4.5
    Axes: -60, 0, -60, 0
    
    Colour: "Silver"
    Line width: 1
    grid_line = -50
    while grid_line <= -10
        Draw line: grid_line, -60, grid_line, 0
        Draw line: -60, grid_line, 0, grid_line
        grid_line = grid_line + 10
    endwhile
    
    Colour: "{0.6,0.6,0.6}"
    Line width: 1
    Dashed line
    Draw line: -60, -60, 0, 0
    Solid line
    
    Colour: "{0.3,0.3,0.8}"
    Dashed line
    Draw line: threshold_dB, -60, threshold_dB, 0
    Solid line

    # --- GREEN TRANSFER CURVE ---
    Colour: "{0.0, 0.8, 0.0}"
    Line width: 3
    
    denom_viz = (min(env_max_viz, threshold_linear * range_linear) - threshold_linear)
    if denom_viz = 0
        denom_viz = 1
    endif

    in_lev = -60
    prev_out = -60
    
    while in_lev <= 0
        in_lin = 10 ^ (in_lev / 20)
        sim_env = max(in_lin, threshold_linear)
        
        if env_max_viz > threshold_linear
             sim_norm = (sim_env - threshold_linear) / denom_viz
             sim_norm = min(max(sim_norm, 0), 1)
        else
             sim_norm = 0
        endif

        if curve_exponent <> 1.0
            sim_norm = sim_norm ^ curve_exponent
        endif
        
        if mode = 1
             out_lin = sim_norm
        elsif mode = 4
             out_lin = in_lin * (1 - sim_norm)
        else
             out_lin = in_lin * sim_norm
        endif
        
        out_lev = 20 * log10(out_lin + 1e-10)
        
        # Clamp to bounds
        if out_lev < -60
            out_lev = -60
        endif
        if out_lev > 0
            out_lev = 0
        endif
        
        if in_lev > -60
            Draw line: in_lev - 1, prev_out, in_lev, out_lev
        endif
        prev_out = out_lev
        in_lev = in_lev + 1
    endwhile

    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Text bottom: "yes", "Input Level (dB)"
    Text left: "yes", "Output Level (dB)"
    Text top: "yes", "Transfer Curve (" + mode$ + ")"
    Marks bottom every: 1, 20, "yes", "yes", "no"
    Marks left every: 1, 20, "yes", "yes", "no"
    
    # === PANEL 2: SOURCE + ENVELOPE (MIDDLE) ===
    Select outer viewport: 0, 8, 4.6, 6.5
    
    selectObject: vis_source_id
    Black
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    selectObject: vis_env_id
    Red
    Line width: 2
    Draw: 0, 0, 0, 0, "no", "Curve"
    Line width: 1
    
    selectObject: vis_env_id
    Formula: "-self"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Black
    Text top: "yes", "Source & Envelope Overlay"
    Draw inner box
    
    # === PANEL 3: RESULT (BOTTOM) ===
    Select outer viewport: 0, 8, 6.6, 8.5
    selectObject: result_id
    Black
    Draw: 0, 0, 0, 0, "no", "Curve"
    Text top: "yes", "Result: " + selected$("Sound")
    Draw inner box
    
    removeObject: vis_env_id, vis_source_id
endif

# ============================================================
# 9. STATISTICS OUTPUT
# ============================================================

if show_statistics
    selectObject: result_id
    result_max = Get maximum: 0, 0, "Parabolic"
    result_rms = Get root-mean-square: 0, 0
    result_duration = Get total duration
    
    result_name$ = selected$("Sound")
    
    writeInfoLine: "======================================================="
    appendInfoLine: "        TIME-DOMAIN RMS ENVELOPE FOLLOWER - STATS"
    appendInfoLine: "======================================================="
    appendInfoLine: ""
    appendInfoLine: "MODE: ", mode$, " (", preset$, ")"
    appendInfoLine: ""
    appendInfoLine: "--- Source ---"
    appendInfoLine: "  Name:         ", source_name$
    appendInfoLine: "  Duration:     ", fixed$(duration, 3), " s"
    appendInfoLine: "  Sample rate:  ", orig_sr, " Hz"
    appendInfoLine: "  Channels:     ", n_channels
    appendInfoLine: ""
    appendInfoLine: "--- Envelope Parameters ---"
    appendInfoLine: "  Attack:       ", attack_time_ms, " ms (", fixed$(attack_hz, 1), " Hz)"
    appendInfoLine: "  Release:      ", release_time_ms, " ms (", fixed$(release_hz, 1), " Hz)"
    appendInfoLine: "  Threshold:    ", threshold_dB, " dB"
    appendInfoLine: "  Range:        ", range_dB, " dB"
    appendInfoLine: "  Curve:        ", curve_exponent
    appendInfoLine: ""
    appendInfoLine: "--- Raw Envelope Stats (pre-threshold) ---"
    appendInfoLine: "  Max:          ", fixed$(env_max, 6)
    appendInfoLine: "  Min:          ", fixed$(env_min, 6)
    appendInfoLine: "  Mean:         ", fixed$(env_mean, 6)
    appendInfoLine: "  RMS:          ", fixed$(env_rms, 6)
    appendInfoLine: ""
    appendInfoLine: "--- Result ---"
    appendInfoLine: "  Name:         ", result_name$
    appendInfoLine: "  Peak:         ", fixed$(result_max, 4)
    appendInfoLine: "  RMS:          ", fixed$(result_rms, 6)
    if mode = 5 and recipient_dur > duration + 0.001
        appendInfoLine: "  Note: recipient longer than donor (", fixed$(recipient_dur, 2), "s > ", fixed$(duration, 2), "s); silent past donor end."
    endif
    if did_downsample
        appendInfoLine: "  (Envelope computed at ", processing_sample_rate, " Hz)"
    endif
    appendInfoLine: ""
    appendInfoLine: "======================================================="
endif

# ============================================================
# 10. PLAYBACK & CLEANUP
# ============================================================

if play_after_processing
    selectObject: result_id
    Play
endif

removeObject: env_id, work_id
selectObject: result_id

if not show_statistics
    writeInfoLine: "Done! Created: ", selected$("Sound")
endif
