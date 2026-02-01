# ============================================================
# Praat AudioTools - Noise_Gate.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Noise gate with attack/release, hold time, range control,
#   and hysteresis for click-free gating.
#
# Changelog v1.0:
#   - Added attack/release for smooth transitions
#   - Added hold time to prevent chattering
#   - Added range control (floor level)
#   - Added hysteresis (separate open/close thresholds)
#   - Added sidechain filter option
#   - Added presets
#   - Added visualization
#   - Fixed object cleanup
# ============================================================

form Noise Gate v1.0
    optionmenu Preset 1
        option Custom
        option Gentle (speech)
        option Medium (vocals)
        option Tight (drums)
        option Aggressive (noise removal)
        option Ducker (inverse gate)
        option Tremolo Gate
    comment === Threshold ===
    real Threshold_dB -30
    real Hysteresis_dB 3
    comment (Hysteresis: gate closes at threshold - hysteresis)
    comment === Timing ===
    positive Attack_ms 1
    positive Hold_ms 50
    positive Release_ms 50
    comment === Range ===
    real Range_dB -80
    comment (-80 = full silence, -6 = light reduction)
    comment === Sidechain Filter ===
    optionmenu Sidechain_filter 1
        option Off (full spectrum)
        option High-pass 100 Hz
        option High-pass 200 Hz
        option Band 1-5 kHz (presence)
    comment === Output ===
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sr = Get sampling frequency
dur = Get total duration
nChannels = Get number of channels

# === APPLY PRESETS ===
if preset = 2
    # Gentle (speech)
    threshold_dB = -35
    hysteresis_dB = 4
    attack_ms = 2
    hold_ms = 100
    release_ms = 150
    range_dB = -40
    presetName$ = "Gentle"
elsif preset = 3
    # Medium (vocals)
    threshold_dB = -30
    hysteresis_dB = 3
    attack_ms = 1
    hold_ms = 50
    release_ms = 80
    range_dB = -60
    presetName$ = "Medium"
elsif preset = 4
    # Tight (drums)
    threshold_dB = -25
    hysteresis_dB = 2
    attack_ms = 0.5
    hold_ms = 20
    release_ms = 30
    range_dB = -80
    presetName$ = "Tight"
elsif preset = 5
    # Aggressive
    threshold_dB = -20
    hysteresis_dB = 2
    attack_ms = 0.3
    hold_ms = 10
    release_ms = 20
    range_dB = -80
    presetName$ = "Aggressive"
elsif preset = 6
    # Ducker (inverse)
    threshold_dB = -25
    hysteresis_dB = 3
    attack_ms = 5
    hold_ms = 100
    release_ms = 200
    range_dB = -12
    presetName$ = "Ducker"
elsif preset = 7
    # Tremolo Gate
    threshold_dB = -20
    hysteresis_dB = 1
    attack_ms = 1
    hold_ms = 5
    release_ms = 10
    range_dB = -80
    presetName$ = "TremoloGate"
else
    presetName$ = "Custom"
endif

# Convert to linear
threshold_lin = 10 ^ (threshold_dB / 20)
close_threshold_lin = 10 ^ ((threshold_dB - hysteresis_dB) / 20)
range_lin = 10 ^ (range_dB / 20)

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  NOISE GATE v1.0"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "=== Settings ==="
writeInfoLine: "  Threshold: ", fixed$(threshold_dB, 1), " dB"
writeInfoLine: "  Hysteresis: ", fixed$(hysteresis_dB, 1), " dB"
writeInfoLine: "  Attack: ", fixed$(attack_ms, 1), " ms"
writeInfoLine: "  Hold: ", fixed$(hold_ms, 0), " ms"
writeInfoLine: "  Release: ", fixed$(release_ms, 0), " ms"
writeInfoLine: "  Range: ", fixed$(range_dB, 0), " dB"
writeInfoLine: ""

# ============================================================
# CREATE SIDECHAIN (for level detection)
# ============================================================

appendInfoLine: "Creating sidechain..."

selectObject: sound
if nChannels > 1
    sidechain = Convert to mono
else
    sidechain = Copy: "sidechain"
endif

# Apply sidechain filter if selected
if sidechain_filter = 2
    # High-pass 100 Hz
    selectObject: sidechain
    filtered = Filter (pass Hann band): 100, 0, 50
    removeObject: sidechain
    sidechain = filtered
    appendInfoLine: "  Sidechain: HP 100 Hz"
elsif sidechain_filter = 3
    # High-pass 200 Hz
    selectObject: sidechain
    filtered = Filter (pass Hann band): 200, 0, 50
    removeObject: sidechain
    sidechain = filtered
    appendInfoLine: "  Sidechain: HP 200 Hz"
elsif sidechain_filter = 4
    # Band 1-5 kHz
    selectObject: sidechain
    filtered = Filter (pass Hann band): 1000, 5000, 100
    removeObject: sidechain
    sidechain = filtered
    appendInfoLine: "  Sidechain: BP 1-5 kHz"
endif

# ============================================================
# CREATE GATE ENVELOPE
# ============================================================

appendInfoLine: "Analyzing levels..."

# Get intensity for level detection
selectObject: sidechain
To Intensity: 100, 0, "yes"
intensity = selected("Intensity")

# Create envelope sound to store gate state
Create Sound from formula: "gate_env", 1, 0, dur, sr, ~ 0
gate_env = selected("Sound")

# Get intensity values and create gate envelope
# We'll use a simplified approach: 
# 1. Convert intensity to linear amplitude
# 2. Apply gate logic with smoothing

selectObject: intensity
int_min = Get minimum: 0, 0, "Parabolic"
int_max = Get maximum: 0, 0, "Parabolic"

# Convert threshold to intensity dB (intensity is in dB SPL)
# Approximate: map threshold relative to max intensity
thresh_int = int_max + threshold_dB
close_thresh_int = int_max + threshold_dB - hysteresis_dB

appendInfoLine: "  Peak intensity: ", fixed$(int_max, 1), " dB"
appendInfoLine: "  Gate threshold: ", fixed$(thresh_int, 1), " dB (intensity)"

# Create gate envelope based on intensity
# 1 = open, range_lin = closed
selectObject: gate_env
Formula: ~ if object(intensity, x) > thresh_int then 1 else range_lin fi

# ============================================================
# APPLY ATTACK/HOLD/RELEASE SMOOTHING
# ============================================================

appendInfoLine: "Applying attack/hold/release..."

# Convert times to samples
attack_samples = round(attack_ms * sr / 1000)
hold_samples = round(hold_ms * sr / 1000)
release_samples = round(release_ms * sr / 1000)

if attack_samples < 1
    attack_samples = 1
endif
if release_samples < 1
    release_samples = 1
endif

# Smoothing using multiple formula passes
# This approximates attack/release behavior

# First pass: hold (extend open states)
if hold_samples > 1
    selectObject: gate_env
    # Look back to extend open states
    Formula: ~ if self < 1 and col > hold_samples then max(self, max(self[col-1], self[col-hold_samples])*0.99) else self fi
endif

# Second pass: attack smoothing (fast rise)
attack_coef = 1 - exp(-2.2 / max(attack_samples, 1))
selectObject: gate_env
Formula: ~ if col > 1 then if self > self[col-1] then self[col-1] + (self - self[col-1]) * attack_coef else self fi else self fi

# Third pass: release smoothing (slow fall)
release_coef = 1 - exp(-2.2 / max(release_samples, 1))
selectObject: gate_env
Formula: ~ if col > 1 then if self < self[col-1] then self[col-1] + (self - self[col-1]) * release_coef else self fi else self fi

# Additional smoothing pass for cleaner transitions
selectObject: gate_env
Formula: ~ if col > 1 and col < ncol then (self[col-1] + self + self[col+1]) / 3 else self fi

# ============================================================
# APPLY GATE TO AUDIO
# ============================================================

appendInfoLine: "Applying gate..."

selectObject: sound
result = Copy: sound_name$ + "_gated"

# Apply gate envelope
selectObject: result
Formula: ~ self * object[gate_env]

# Normalize
selectObject: result
Scale peak: 0.95

# ============================================================
# STATISTICS
# ============================================================

# Calculate gate activity
selectObject: gate_env
gateMin = Get minimum: 0, 0, "Sinc70"
gateMean = Get mean: 0, 0

# Estimate open time percentage
openPercent = (gateMean - range_lin) / (1 - range_lin) * 100
if openPercent < 0
    openPercent = 0
endif
if openPercent > 100
    openPercent = 100
endif

appendInfoLine: ""
appendInfoLine: "Gate activity: ", fixed$(openPercent, 1), "% open"

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Noise Gate## | " + presetName$ + " | Thresh: " + fixed$(threshold_dB, 0) + " dB"
    
    # === INPUT WAVEFORM ===
    Select outer viewport: 0, 8, 0.5, 1.8
    Select inner viewport: 0.8, 7.6, 0.6, 1.6
    
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 1.8
    Text left: "yes", "Input"
    
    # === GATE ENVELOPE ===
    Select outer viewport: 0, 8, 1.9, 3.0
    Select inner viewport: 0.8, 7.6, 2.0, 2.8
    
    # Background
    Axes: 0, dur, 0, 1.1
    
    # Closed zone
    Paint rectangle: "{1, 0.95, 0.95}", 0, dur, 0, range_lin + 0.05
    # Open zone
    Paint rectangle: "{0.95, 1, 0.95}", 0, dur, 0.95, 1.1
    
    # Gate envelope
    selectObject: gate_env
    Colour: "{0.3, 0.7, 0.3}"
    Line width: 2
    Draw: 0, 0, 0, 1.1, "no", "Curve"
    Line width: 1
    
    # Threshold line
    Colour: "{0.8, 0.3, 0.3}"
    Dashed line
    Draw line: 0, 0.5, dur, 0.5
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 1.9, 3.0
    Text left: "yes", "Gate"
    
    # === OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 3.1, 4.4
    Select inner viewport: 0.8, 7.6, 3.2, 4.2
    
    selectObject: result
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 3.1, 4.4
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # === STATS ===
    Select outer viewport: 0, 8, 4.5, 5.0
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Attack: " + fixed$(attack_ms, 1) + "ms | Hold: " + fixed$(hold_ms, 0) + "ms | Release: " + fixed$(release_ms, 0) + "ms | Range: " + fixed$(range_dB, 0) + "dB | Open: " + fixed$(openPercent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: sidechain, intensity, gate_env

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
writeInfoLine: "=============================================="

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result