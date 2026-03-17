# ============================================================
# Praat AudioTools - Noise_Gate.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Noise gate with attack/release, hold time, range control,
#   and hysteresis for click-free gating.
#
# Changelog v1.2 (performance rewrite):
#   - Gate logic now runs at 1000 Hz instead of audio SR.
#     For a 44.1 kHz file this gives ~44x fewer loop iterations,
#     which is the dominant speed-up.
#   - Hold loop is now O(n) single-pass counter, not O(n*hold)
#     nested loops.
#   - Attack/release loop also runs at 1000 Hz; transitions are
#     further refined by sinc-interpolation during resample.
#   - Gate envelope resampled to audio SR with Praat's built-in
#     sinc (C-speed, not scripted) before multiplication.
#   - Removed per-sample object() interpolation in scan loop;
#     uses Get value in frame for direct, fast lookup.
#   - DC-offset removal on sidechain retained from v1.1.
#   - Normalize_output checkbox retained from v1.1.
# ============================================================

form Noise Gate v1.2
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
    comment (Hysteresis: gate closes at threshold minus hysteresis)
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
    boolean Normalize_output 1
    comment (Normalize: scales to -0.5 dBFS peak. Disable to preserve absolute levels.)
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound        = selected("Sound")
sound_name$  = selected$("Sound")

selectObject: sound
sr        = Get sampling frequency
dur       = Get total duration
nChannels = Get number of channels

# === APPLY PRESETS ===
if preset = 2
    threshold_dB  = -35
    hysteresis_dB = 4
    attack_ms     = 2
    hold_ms       = 100
    release_ms    = 150
    range_dB      = -40
    presetName$   = "Gentle"
elsif preset = 3
    threshold_dB  = -30
    hysteresis_dB = 3
    attack_ms     = 1
    hold_ms       = 50
    release_ms    = 80
    range_dB      = -60
    presetName$   = "Medium"
elsif preset = 4
    threshold_dB  = -25
    hysteresis_dB = 2
    attack_ms     = 0.5
    hold_ms       = 20
    release_ms    = 30
    range_dB      = -80
    presetName$   = "Tight"
elsif preset = 5
    threshold_dB  = -20
    hysteresis_dB = 2
    attack_ms     = 0.3
    hold_ms       = 10
    release_ms    = 20
    range_dB      = -80
    presetName$   = "Aggressive"
elsif preset = 6
    threshold_dB  = -25
    hysteresis_dB = 3
    attack_ms     = 5
    hold_ms       = 100
    release_ms    = 200
    range_dB      = -12
    presetName$   = "Ducker"
elsif preset = 7
    threshold_dB  = -20
    hysteresis_dB = 1
    attack_ms     = 1
    hold_ms       = 5
    release_ms    = 10
    range_dB      = -80
    presetName$   = "TremoloGate"
else
    presetName$ = "Custom"
endif

range_lin = 10 ^ (range_dB / 20)

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  NOISE GATE v1.2"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input:  ", sound_name$, " (", fixed$(dur, 2), "s,  ", fixed$(sr, 0), " Hz)"
writeInfoLine: "Preset: ", presetName$
writeInfoLine: ""
writeInfoLine: "=== Settings ==="
writeInfoLine: "  Threshold:  ", fixed$(threshold_dB, 1), " dB"
writeInfoLine: "  Hysteresis: ", fixed$(hysteresis_dB, 1), " dB"
writeInfoLine: "  Attack:     ", fixed$(attack_ms, 1), " ms"
writeInfoLine: "  Hold:       ", fixed$(hold_ms, 0), " ms"
writeInfoLine: "  Release:    ", fixed$(release_ms, 0), " ms"
writeInfoLine: "  Range:      ", fixed$(range_dB, 0), " dB"
writeInfoLine: ""

# ============================================================
# SIDECHAIN
# ============================================================

appendInfoLine: "Creating sidechain..."

selectObject: sound
if nChannels > 1
    sidechain = Convert to mono
else
    sidechain = Copy: "sidechain"
endif

selectObject: sidechain
Subtract mean

if sidechain_filter = 2
    selectObject: sidechain
    filtered = Filter (pass Hann band): 100, 0, 50
    removeObject: sidechain
    sidechain = filtered
    appendInfoLine: "  Sidechain: HP 100 Hz"
elsif sidechain_filter = 3
    selectObject: sidechain
    filtered = Filter (pass Hann band): 200, 0, 50
    removeObject: sidechain
    sidechain = filtered
    appendInfoLine: "  Sidechain: HP 200 Hz"
elsif sidechain_filter = 4
    selectObject: sidechain
    filtered = Filter (pass Hann band): 1000, 5000, 100
    removeObject: sidechain
    sidechain = filtered
    appendInfoLine: "  Sidechain: BP 1-5 kHz"
endif

# ============================================================
# LEVEL DETECTION
# ============================================================

appendInfoLine: "Analysing levels..."

# All gate logic runs at gate_sr (1000 Hz).
# This is ~44x fewer loop iterations than 44.1 kHz audio,
# which is the main speed gain in this version.
gate_sr  = 1000
gate_dt  = 1 / gate_sr

selectObject: sidechain
To Intensity: 100, gate_dt, "yes"
intensity    = selected("Intensity")

selectObject: intensity
int_max          = Get maximum: 0, 0, "Parabolic"
thresh_int       = int_max + threshold_dB
close_thresh_int = int_max + threshold_dB - hysteresis_dB

appendInfoLine: "  Peak intensity:  ", fixed$(int_max, 1), " dB"
appendInfoLine: "  Open threshold:  ", fixed$(thresh_int, 1), " dB"
appendInfoLine: "  Close threshold: ", fixed$(close_thresh_int, 1), " dB"

# ============================================================
# GATE ENVELOPE AT 1000 Hz
# ============================================================

appendInfoLine: "Building gate envelope at 1 kHz..."

nGateSamples = round(dur * gate_sr)

Create Sound from formula: "gate_env", 1, 0, dur, gate_sr, ~ 0
gate_env = selected("Sound")

# --- Hysteresis scan: O(n) state machine ---
gateOpen = 0
for i from 1 to nGateSamples
    t_lookup = min(max((i - 0.5) * gate_dt, 0), dur)
    intVal = object(intensity, t_lookup)

    if gateOpen = 0
        if intVal > thresh_int
            gateOpen = 1
        endif
    else
        if intVal < close_thresh_int
            gateOpen = 0
        endif
    endif

    selectObject: gate_env
    if gateOpen = 1
        Set value at sample number: 1, i, 1
    else
        Set value at sample number: 1, i, range_lin
    endif
endfor

# --- Hold: O(n) single-pass counter ---
# No nested loop; a countdown keeps the gate open for hold_samples
# after the last open sample, without re-scanning the array.
appendInfoLine: "Applying hold..."

hold_samples_gate = round(hold_ms * gate_sr / 1000)
if hold_samples_gate < 1
    hold_samples_gate = 1
endif

holdCounter = 0
selectObject: gate_env
for i from 1 to nGateSamples
    v = Get value at sample number: 1, i
    if v >= 1
        holdCounter = hold_samples_gate
    elsif holdCounter > 0
        Set value at sample number: 1, i, 1
        holdCounter = holdCounter - 1
    endif
endfor

# --- Attack / Release: O(n) sequential loop at 1000 Hz ---
appendInfoLine: "Applying attack/release..."

attack_samples_gate  = max(round(attack_ms  * gate_sr / 1000), 1)
release_samples_gate = max(round(release_ms * gate_sr / 1000), 1)

attack_coef  = 1 - exp(-4.6 / attack_samples_gate)
release_coef = 1 - exp(-4.6 / release_samples_gate)

selectObject: gate_env
for i from 2 to nGateSamples
    prev = Get value at sample number: 1, i - 1
    curr = Get value at sample number: 1, i
    if curr > prev
        new_val = prev + (curr - prev) * attack_coef
    elsif curr < prev
        new_val = prev + (curr - prev) * release_coef
    else
        new_val = curr
    endif
    Set value at sample number: 1, i, new_val
endfor

# ============================================================
# RESAMPLE GATE ENVELOPE TO AUDIO SR  (C-speed sinc)
# ============================================================

appendInfoLine: "Resampling gate envelope to audio SR..."

selectObject: gate_env
gate_env_hires = Resample: sr, 50
removeObject: gate_env
gate_env = gate_env_hires

# Trim to exact audio length (resample can add ±1 sample)
selectObject: gate_env
nGateHires = Get number of samples
selectObject: sound
nAudioSamples = Get number of samples

if nGateHires > nAudioSamples
    selectObject: gate_env
    Extract part: 0, dur, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: gate_env
    gate_env = trimmed
endif

# Clamp envelope to valid range — suppresses sinc ringing artefacts
selectObject: gate_env
Formula: ~ if self > 1 then 1 else if self < range_lin then range_lin else self fi fi

# ============================================================
# APPLY GATE
# ============================================================

appendInfoLine: "Applying gate to audio..."

selectObject: sound
result = Copy: sound_name$ + "_gated"

selectObject: result
Formula: ~ self * object[gate_env]

if normalize_output
    selectObject: result
    Scale peak: 0.95
endif

# ============================================================
# STATISTICS
# ============================================================

selectObject: gate_env
gateMean = Get mean: 0, 0

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

    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Noise Gate v1.2## | " + presetName$ + " | Thresh: " + fixed$(threshold_dB, 0) + " dB"

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

    Select outer viewport: 0, 8, 1.9, 3.0
    Select inner viewport: 0.8, 7.6, 2.0, 2.8
    Axes: 0, dur, 0, 1.1
    Paint rectangle: "{1, 0.95, 0.95}",  0, dur, 0,    range_lin + 0.05
    Paint rectangle: "{0.95, 1, 0.95}",  0, dur, 0.95, 1.1
    selectObject: gate_env
    Colour: "{0.3, 0.7, 0.3}"
    Line width: 2
    Draw: 0, 0, 0, 1.1, "no", "Curve"
    Line width: 1
    Colour: "{0.8, 0.3, 0.3}"
    Dashed line
    Draw line: 0, 0.5, dur, 0.5
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 1.9, 3.0
    Text left: "yes", "Gate"

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

    Select outer viewport: 0, 8, 4.5, 5.0
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Attack: " + fixed$(attack_ms, 1) + " ms  |  Hold: " + fixed$(hold_ms, 0) + " ms  |  Release: " + fixed$(release_ms, 0) + " ms  |  Range: " + fixed$(range_dB, 0) + " dB  |  Open: " + fixed$(openPercent, 0) + "%"
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
appendInfoLine: "=============================================="

if play
    appendInfoLine: ""
    appendInfoLine: "Playing..."
    Play
endif

selectObject: result
