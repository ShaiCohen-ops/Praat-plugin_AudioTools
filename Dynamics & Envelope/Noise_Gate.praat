# ============================================================
# Praat AudioTools - Noise_Gate.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4 (2026) - Production Release
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   High-precision Noise Gate & Ducker featuring absolute dBFS thresholding,
#   pre-rectification stereo-linked sidechain filtering, time-aligned
#   edge padding, dynamic detector windowing, hold time, and range control.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

# Changelog v2.4 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
form Noise Gate v2.4
    optionmenu Preset 1
        option Custom
        option Gentle (speech)
        option Medium (vocals)
        option Tight (drums)
        option Aggressive (noise removal)
        option Ducker (inverse gate)
        option Fast Choppy Gate
    comment === Threshold ===
    real Threshold_dBFS -30.0
    real Hysteresis_dB 3.0
    comment (Gate closes at Threshold minus Hysteresis)
    comment === Timing ===
    positive Attack_ms 1.0
    positive Hold_ms 50.0
    positive Release_ms 50.0
    comment === Range & Mute ===
    real Range_dB -80.0
    boolean Mute_when_closed 0
    comment === Sidechain Filter ===
    optionmenu Sidechain_filter 1
        option Off (full spectrum)
        option High-pass 100 Hz
        option High-pass 200 Hz
        option Band 1-5 kHz (presence)
    comment === Output ===
    boolean Peak_normalize_final_output 0
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Validation Error: Please select exactly one Sound object."
endif

sound       = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sr        = Get sampling frequency
dur       = Get total duration
t_start   = Get start time
t_end     = Get end time
nChannels = Get number of channels
nyquist   = sr / 2

if nChannels > 2
    exitScript: "Validation Error: This script supports mono (1 channel) or stereo (2 channels) Sound objects."
endif

if dur < 0.001
    exitScript: "Validation Error: Sound duration is too short (< 1 ms)."
endif

if hysteresis_dB < 0
    exitScript: "Validation Error: Hysteresis must be non-negative (>= 0 dB)."
endif

if range_dB > 0
    exitScript: "Validation Error: Range_dB must be <= 0 dB to prevent accidental gain boost."
endif

# === APPLY PRESETS ===
is_ducker = 0
if preset = 2
    # Gentle (speech)
    threshold_dBFS = -35.0
    hysteresis_dB  = 4.0
    attack_ms      = 2.0
    hold_ms        = 100.0
    release_ms     = 150.0
    range_dB       = -40.0
    presetName$    = "Gentle"
elsif preset = 3
    # Medium (vocals)
    threshold_dBFS = -30.0
    hysteresis_dB  = 3.0
    attack_ms      = 1.0
    hold_ms        = 50.0
    release_ms     = 80.0
    range_dB       = -60.0
    presetName$    = "Medium"
elsif preset = 4
    # Tight (drums)
    threshold_dBFS = -25.0
    hysteresis_dB  = 2.0
    attack_ms      = 0.5
    hold_ms        = 20.0
    release_ms     = 30.0
    range_dB       = -80.0
    presetName$    = "Tight"
elsif preset = 5
    # Aggressive (noise removal)
    threshold_dBFS = -20.0
    hysteresis_dB  = 2.0
    attack_ms      = 0.3
    hold_ms        = 10.0
    release_ms     = 20.0
    range_dB       = -80.0
    presetName$    = "Aggressive"
elsif preset = 6
    # Ducker (inverse gate)
    threshold_dBFS = -25.0
    hysteresis_dB  = 3.0
    attack_ms      = 5.0
    hold_ms        = 100.0
    release_ms     = 200.0
    range_dB       = -12.0
    is_ducker      = 1
    presetName$    = "Ducker"
elsif preset = 7
    # Fast Choppy Gate
    threshold_dBFS = -20.0
    hysteresis_dB  = 1.0
    attack_ms      = 1.0
    hold_ms        = 5.0
    release_ms     = 10.0
    range_dB       = -80.0
    presetName$    = "FastChoppyGate"
else
    presetName$    = "Custom"
endif

if mute_when_closed
    range_lin = 0.0
else
    range_lin = 10 ^ (range_dB / 20)
endif

# === INFO HEADER ===
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "  NOISE GATE v2.4 (Production Release)"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input:  ", sound_name$, " (", fixed$(dur, 3), "s, ", fixed$(sr, 0), " Hz, ", nChannels, " ch)"
appendInfoLine: "Domain: [", fixed$(t_start, 3), "s - ", fixed$(t_end, 3), "s]"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "=== Settings ==="
appendInfoLine: "  Mode:       ", if is_ducker then "Ducker (Inverse Gate)" else "Noise Gate" fi
appendInfoLine: "  Threshold:  ", fixed$(threshold_dBFS, 1), " dBFS"
appendInfoLine: "  Hysteresis: ", fixed$(hysteresis_dB, 1), " dB"
appendInfoLine: "  Attack:     ", fixed$(attack_ms, 2), " ms"
appendInfoLine: "  Hold:       ", fixed$(hold_ms, 1), " ms"
appendInfoLine: "  Release:    ", fixed$(release_ms, 1), " ms"
appendInfoLine: "  Range:      ", if mute_when_closed then "-inf dB (Mute)" else fixed$(range_dB, 1) + " dB" fi
appendInfoLine: ""

# ============================================================
# SIDECHAIN CREATION (Pre-rectification Filtered & Stereo-linked)
# ============================================================

appendInfoLine: "Filtering raw sidechain signal..."

selectObject: sound
sound_sc = Copy: "sound_sc"

# Pre-rectification Filtering
if sidechain_filter = 2
    selectObject: sound_sc
    filtered = Filter (pass Hann band): 100, 0, 50
    removeObject: sound_sc
    sound_sc = filtered
    appendInfoLine: "  Sidechain Filter: HP 100 Hz"
elsif sidechain_filter = 3
    selectObject: sound_sc
    filtered = Filter (pass Hann band): 200, 0, 50
    removeObject: sound_sc
    sound_sc = filtered
    appendInfoLine: "  Sidechain Filter: HP 200 Hz"
elsif sidechain_filter = 4
    top_freq = min(5000, nyquist - 100)
    if top_freq > 1000
        selectObject: sound_sc
        filtered = Filter (pass Hann band): 1000, top_freq, 100
        removeObject: sound_sc
        sound_sc = filtered
        appendInfoLine: "  Sidechain Filter: BP 1-5 kHz"
    endif
endif

appendInfoLine: "Creating stereo-linked peak detector..."

selectObject: sound_sc
if nChannels = 1
    sc_raw = Copy: "sc_raw"
    Formula: ~ abs(self)
elsif nChannels = 2
    sc_raw = Create Sound from formula: "sc_raw", 1, t_start, t_end, sr, ~ max(abs(object[sound_sc, 1, col]), abs(object[sound_sc, 2, col]))
endif
removeObject: sound_sc

# ============================================================
# LEVEL DETECTION WITH TIME-ALIGNED EDGE PADDING
# ============================================================

appendInfoLine: "Analysing levels with time-aligned padding..."

min_timing_ms = min(attack_ms, min(release_ms, hold_ms))
if min_timing_ms < 0.5
    gate_sr = 10000
    p_floor_base = 800
elsif min_timing_ms < 1.0
    gate_sr = 5000
    p_floor_base = 400
else
    gate_sr = 1000
    p_floor_base = 100
endif
gate_dt = 1 / gate_sr

pad_dur = 0.1
Create Sound from formula: "pad1", 1, 0, pad_dur, sr, "1e-12"
pad1 = selected("Sound")

selectObject: pad1
pad2 = Copy: "pad2"

selectObject: pad1
plusObject: sc_raw
plusObject: pad2
sc_padded = Concatenate
removeObject: sc_raw, pad1, pad2

# Align time domain of padded sound to match [t_start - pad_dur, t_end + pad_dur]
selectObject: sc_padded
Shift times by: t_start - pad_dur

padded_dur = Get total duration
p_floor = max(p_floor_base, ceiling(9.6 / padded_dur))

selectObject: sc_padded
To Intensity: p_floor, gate_dt, "yes"
intensity = selected("Intensity")
removeObject: sc_padded

close_thresh_dBFS = threshold_dBFS - hysteresis_dB

appendInfoLine: "  Control Rate:    ", gate_sr, " Hz"
appendInfoLine: "  Detector Window: ", fixed$(3200 / p_floor, 1), " ms"
appendInfoLine: "  Open Threshold:  ", fixed$(threshold_dBFS, 1), " dBFS"
appendInfoLine: "  Close Threshold: ", fixed$(close_thresh_dBFS, 1), " dBFS"

# ============================================================
# GATE ENVELOPE GENERATION
# ============================================================

appendInfoLine: "Building gate envelope..."

nGateSamples = max(1, round(dur * gate_sr))

Create Sound from formula: "gate_env", 1, t_start, t_end, gate_sr, "0"
gate_env = selected("Sound")

gateOpen = 0
binaryOpenCount = 0

for i from 1 to nGateSamples
    t_lookup = t_start + (i - 0.5) * gate_dt
    t_lookup = min(max(t_lookup, t_start), t_end)

    selectObject: intensity
    level_SPL = Get value at time: t_lookup, "Nearest"
    if level_SPL = undefined
        level_SPL = 0
    endif

    # Absolute dBFS conversion (SPL - 93.9794)
    level_dBFS = level_SPL - 93.9794

    if gateOpen = 0
        if level_dBFS > threshold_dBFS
            gateOpen = 1
        endif
    else
        if level_dBFS < close_thresh_dBFS
            gateOpen = 0
        endif
    endif

    if gateOpen = 1
        binaryOpenCount = binaryOpenCount + 1
    endif

    selectObject: gate_env
    if is_ducker
        if gateOpen = 1
            Set value at sample number: 1, i, range_lin
        else
            Set value at sample number: 1, i, 1.0
        endif
    else
        if gateOpen = 1
            Set value at sample number: 1, i, 1.0
        else
            Set value at sample number: 1, i, range_lin
        endif
    endif
endfor

# --- Hold Time Processing ---
hold_samples_gate = max(1, round(hold_ms * gate_sr / 1000))

holdCounter = 0
selectObject: gate_env
for i from 1 to nGateSamples
    v = Get value at sample number: 1, i
    target_active = if is_ducker then (v <= range_lin + 1e-5) else (v >= 1.0 - 1e-5) fi

    if target_active
        holdCounter = hold_samples_gate
    elsif holdCounter > 0
        if is_ducker
            Set value at sample number: 1, i, range_lin
        else
            Set value at sample number: 1, i, 1.0
        endif
        holdCounter = holdCounter - 1
    endif
endfor

# --- Attack & Release Exponential Smoothing ---
attack_samples_gate  = max(1, round(attack_ms  * gate_sr / 1000))
release_samples_gate = max(1, round(release_ms * gate_sr / 1000))

attack_coef  = 1 - exp(-4.6 / attack_samples_gate)
release_coef = 1 - exp(-4.6 / release_samples_gate)

selectObject: gate_env
for i from 2 to nGateSamples
    prev = Get value at sample number: 1, i - 1
    curr = Get value at sample number: 1, i
    
    if is_ducker
        # In Ducker mode, dropping gain is Attack, recovering gain is Release
        if curr < prev
            new_val = prev + (curr - prev) * attack_coef
        elsif curr > prev
            new_val = prev + (curr - prev) * release_coef
        else
            new_val = curr
        endif
    else
        # In Gate mode, rising gain is Attack, dropping gain is Release
        if curr > prev
            new_val = prev + (curr - prev) * attack_coef
        elsif curr < prev
            new_val = prev + (curr - prev) * release_coef
        else
            new_val = curr
        endif
    endif
    
    Set value at sample number: 1, i, new_val
endfor

# ============================================================
# RESAMPLE GATE ENVELOPE & APPLY TO AUDIO
# ============================================================

appendInfoLine: "Resampling gate envelope to audio rate..."

selectObject: gate_env
gate_env_hires = Resample: sr, 50
removeObject: gate_env
gate_env = gate_env_hires

selectObject: gate_env
nGateHires = Get number of samples
selectObject: sound
nAudioSamples = Get number of samples

if nGateHires > nAudioSamples
    selectObject: gate_env
    Extract part: t_start, t_end, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: gate_env
    gate_env = trimmed
endif

selectObject: gate_env
Formula: ~ min(1.0, max(range_lin, self))

appendInfoLine: "Applying gain envelope..."
gate_env_id = gate_env
selectObject: sound
result = Copy: sound_name$ + if is_ducker then "_ducked" else "_gated" fi

selectObject: result
Formula: ~ self * object['gate_env_id', 1, col]

if peak_normalize_final_output
    selectObject: result
    Scale peak: 0.95
endif

# ============================================================
# STATISTICS
# ============================================================

selectObject: gate_env
gateMean = Get mean: 0, 0, 0

if range_lin < 1.0
    avgOpenness = (gateMean - range_lin) / (1 - range_lin) * 100
else
    avgOpenness = 100.0
endif
avgOpenness = min(100.0, max(0.0, avgOpenness))

binaryOpenPercent = (binaryOpenCount / nGateSamples) * 100

appendInfoLine: ""
if is_ducker
    appendInfoLine: "Average Unducked Gain: ", fixed$(avgOpenness, 1), "%"
else
    appendInfoLine: "Average Gate Openness: ", fixed$(avgOpenness, 1), "%"
endif
appendInfoLine: "Time Signal > Thresh:   ", fixed$(binaryOpenPercent, 1), "%"

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Generating visualization..."
    Erase all
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Noise Gate v2.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | threshold " + fixed$(threshold_dBFS, 1) + " dBFS"

    # Input Waveform
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

    # Envelope
    Select outer viewport: 0, 8, 1.9, 3.0
    Select inner viewport: 0.8, 7.6, 2.0, 2.8
    Axes: t_start, t_end, 0, 1.1
    Paint rectangle: "{1, 0.95, 0.95}",  t_start, t_end, 0,    range_lin + 0.05
    Paint rectangle: "{0.95, 1, 0.95}",  t_start, t_end, 0.95, 1.1
    selectObject: gate_env
    Colour: "{0.3, 0.7, 0.3}"
    Line width: 2
    Draw: 0, 0, 0, 1.1, "no", "Curve"
    Line width: 1
    Colour: "{0.8, 0.3, 0.3}"
    Dashed line
    Draw line: t_start, 0.5, t_end, 0.5
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 1.9, 3.0
    Text left: "yes", "Envelope"

    # Output Waveform
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

    # === Summary strip ===
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    Select outer viewport: 0, 8, 4.52, 5.72
    Select inner viewport: 0.60, 7.70, 4.60, 5.64
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half", "##Gate##  " + presetName$ + " | threshold " + fixed$(threshold_dBFS, 1) + " dBFS | range " + fixed$(range_dB, 1) + " dB | attack " + fixed$(attack_ms, 1) + " ms | hold " + fixed$(hold_ms, 1) + " ms | release " + fixed$(release_ms, 1) + " ms"
    Text: 0.02, "left", 0.50, "half", "##Activity##  average openness " + fixed$(avgOpenness, 1) + "\% | signal above threshold " + fixed$(binaryOpenPercent, 1) + "\% | " + if is_ducker then "ducking mode" else "gate mode" fi
    Text: 0.02, "left", 0.22, "half", "##Output##  " + fixed$(dur, 3) + " s | " + string$(nChannels) + " ch | peak " + fixed$(outPeakViz, 3)
    Colour: "Black"
    Draw inner box
    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.20
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: intensity, gate_env

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