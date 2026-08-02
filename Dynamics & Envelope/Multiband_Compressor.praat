# ============================================================
# Praat AudioTools - Multiband_Compressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.0 (2026) - Production Release
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   High-precision 3-band dynamic multiband compressor featuring 
#   complementary Hann crossover filtering, calibrated absolute dBFS 
#   level detection, envelope-following Attack/Release smoothing, 
#   stereo-linked processing, presets, and graphical visualization.
#
#   v1.0 initial release:
#   - 3-band crossover filter bank (Low, Mid, High).
#   - Per-band threshold, ratio, and makeup gain controls.
#   - Basic visualization and preset management.
#
#   v2.0 enhancements:
#   - Absolute dBFS threshold calibration derived from Praat Intensity (SPL).
#   - Inverted and corrected Attack/Release envelope smoothing logic.
#   - Stereo-safe gain reduction envelope application across all channels.
#   - Expanded library of targeted dynamics presets.
#
#   v3.0 production release:
#   - Transparent 1:1 bypass and static makeup-only paths using structured 
#     if/elsif/else branching (eliminating non-standard exit statements).
#   - Dynamic pitch floor scaling based on sound duration, guaranteeing 
#     stable processing on ultra-short audio files (down to 5 ms).
#   - Time-offset handling using absolute Sound start times, 
#     ensuring full compression accuracy on time-shifted objects.
#   - Pipeline re-ordering: presets are applied before validation checks.
#   - Real-time output True Peak overflow detection warnings and refined UI 
#     terminology (RMS Threshold, Interpolated Peak).
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Multiband Compressor v3.0
    optionmenu Preset 1
        option Custom
        option Master Bus (gentle glue)
        option Vocal Polish
        option Bass Control
        option Brighten & Punch
        option De-Harsh
        option Dense Broadcast Style
        option Lo-Fi Crush
    comment === Crossover Frequencies ===
    positive Low_mid_crossover_Hz 200
    positive Mid_high_crossover_Hz 2000
    comment === LOW Band ===
    real Low_RMS_threshold_dBFS -20.0
    positive Low_ratio 2.0
    real Low_makeup_dB 0.0
    comment === MID Band ===
    real Mid_RMS_threshold_dBFS -18.0
    positive Mid_ratio 2.0
    real Mid_makeup_dB 0.0
    comment === HIGH Band ===
    real High_RMS_threshold_dBFS -15.0
    positive High_ratio 3.0
    real High_makeup_dB 0.0
    comment === Dynamic Settings ===
    positive Attack_ms 10.0
    positive Release_ms 100.0
    boolean Peak_normalize_output 0
    comment === Monitor ===
    optionmenu Solo 1
        option Off (full mix)
        option Solo LOW
        option Solo MID
        option Solo HIGH
    boolean Visualize 1
    boolean Play 1
endform

# === READ INPUT OBJECT ===
if numberOfSelected("Sound") <> 1
    exitScript: "Validation Error: Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sr = Get sampling frequency
dur = Get total duration
nChannels = Get number of channels
nyquist = sr / 2

# Assign RMS Threshold variables from Form
low_threshold_dBFS = low_RMS_threshold_dBFS
mid_threshold_dBFS = mid_RMS_threshold_dBFS
high_threshold_dBFS = high_RMS_threshold_dBFS

# === Step 1: APPLY PRESETS (Must execute BEFORE validation) ===
if preset = 2
    # Master Bus (gentle glue)
    low_mid_crossover_Hz = 150
    mid_high_crossover_Hz = 3000
    low_threshold_dBFS = -18.0
    low_ratio = 2.0
    low_makeup_dB = 1.0
    mid_threshold_dBFS = -16.0
    mid_ratio = 1.5
    mid_makeup_dB = 0.0
    high_threshold_dBFS = -14.0
    high_ratio = 2.0
    high_makeup_dB = 1.0
    presetName$ = "MasterBus"
elsif preset = 3
    # Vocal Polish
    low_mid_crossover_Hz = 200
    mid_high_crossover_Hz = 4000
    low_threshold_dBFS = -24.0
    low_ratio = 4.0
    low_makeup_dB = -2.0
    mid_threshold_dBFS = -18.0
    mid_ratio = 2.5
    mid_makeup_dB = 2.0
    high_threshold_dBFS = -20.0
    high_ratio = 2.0
    high_makeup_dB = 1.0
    presetName$ = "VocalPolish"
elsif preset = 4
    # Bass Control
    low_mid_crossover_Hz = 120
    mid_high_crossover_Hz = 2500
    low_threshold_dBFS = -15.0
    low_ratio = 6.0
    low_makeup_dB = 3.0
    mid_threshold_dBFS = -20.0
    mid_ratio = 1.5
    mid_makeup_dB = 0.0
    high_threshold_dBFS = -18.0
    high_ratio = 1.5
    high_makeup_dB = 0.0
    presetName$ = "BassControl"
elsif preset = 5
    # Brighten & Punch
    low_mid_crossover_Hz = 200
    mid_high_crossover_Hz = 3500
    low_threshold_dBFS = -18.0
    low_ratio = 3.0
    low_makeup_dB = 2.0
    mid_threshold_dBFS = -20.0
    mid_ratio = 2.0
    mid_makeup_dB = 0.0
    high_threshold_dBFS = -12.0
    high_ratio = 2.5
    high_makeup_dB = 3.0
    presetName$ = "BrightenPunch"
elsif preset = 6
    # De-Harsh
    low_mid_crossover_Hz = 250
    mid_high_crossover_Hz = 2500
    low_threshold_dBFS = -20.0
    low_ratio = 1.5
    low_makeup_dB = 0.0
    mid_threshold_dBFS = -16.0
    mid_ratio = 3.0
    mid_makeup_dB = -1.0
    high_threshold_dBFS = -10.0
    high_ratio = 4.0
    high_makeup_dB = -2.0
    presetName$ = "DeHarsh"
elsif preset = 7
    # Dense Broadcast Style
    low_mid_crossover_Hz = 150
    mid_high_crossover_Hz = 3000
    low_threshold_dBFS = -20.0
    low_ratio = 4.0
    low_makeup_dB = 2.0
    mid_threshold_dBFS = -18.0
    mid_ratio = 3.0
    mid_makeup_dB = 2.0
    high_threshold_dBFS = -16.0
    high_ratio = 3.0
    high_makeup_dB = 1.0
    presetName$ = "DenseBroadcast"
elsif preset = 8
    # Lo-Fi Crush
    low_mid_crossover_Hz = 300
    mid_high_crossover_Hz = 2000
    low_threshold_dBFS = -25.0
    low_ratio = 8.0
    low_makeup_dB = 4.0
    mid_threshold_dBFS = -22.0
    mid_ratio = 6.0
    mid_makeup_dB = 3.0
    high_threshold_dBFS = -20.0
    high_ratio = 10.0
    high_makeup_dB = 2.0
    presetName$ = "LoFiCrush"
else
    presetName$ = "Custom"
endif

# === Step 2: INPUT VALIDATIONS (Runs AFTER preset application) ===
if dur < 0.005
    exitScript: "Validation Error: Sound duration is too short (< 5 ms) for processing."
endif

if low_mid_crossover_Hz >= mid_high_crossover_Hz
    exitScript: "Validation Error: Low-Mid crossover (" + string$(low_mid_crossover_Hz) + " Hz) must be strictly less than Mid-High crossover (" + string$(mid_high_crossover_Hz) + " Hz)."
endif

if mid_high_crossover_Hz >= nyquist - 100
    exitScript: "Validation Error: Mid-High crossover (" + string$(mid_high_crossover_Hz) + " Hz) must be below Nyquist (" + string$(nyquist) + " Hz)."
endif

if low_mid_crossover_Hz < 20
    exitScript: "Validation Error: Low-Mid crossover must be at least 20 Hz."
endif

if low_ratio < 1.0 or mid_ratio < 1.0 or high_ratio < 1.0
    exitScript: "Validation Error: Compression ratios must be >= 1.0."
endif

# === INFO HEADER ===
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "  MULTIBAND COMPRESSOR v3.0"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 3), "s, ", sr, " Hz, ", nChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Crossovers: ", low_mid_crossover_Hz, " Hz | ", mid_high_crossover_Hz, " Hz"
appendInfoLine: ""
appendInfoLine: "=== Band Settings ==="
appendInfoLine: "  LOW  (<", low_mid_crossover_Hz, " Hz):  RMS Thresh ", fixed$(low_threshold_dBFS, 1), " dBFS | Ratio ", fixed$(low_ratio, 1), ":1 | Makeup ", fixed$(low_makeup_dB, 1), " dB"
appendInfoLine: "  MID  (", low_mid_crossover_Hz, "-", mid_high_crossover_Hz, " Hz): RMS Thresh ", fixed$(mid_threshold_dBFS, 1), " dBFS | Ratio ", fixed$(mid_ratio, 1), ":1 | Makeup ", fixed$(mid_makeup_dB, 1), " dB"
appendInfoLine: "  HIGH (>", mid_high_crossover_Hz, " Hz): RMS Thresh ", fixed$(high_threshold_dBFS, 1), " dBFS | Ratio ", fixed$(high_ratio, 1), ":1 | Makeup ", fixed$(high_makeup_dB, 1), " dB"
appendInfoLine: ""

# ============================================================
# HELPER PROCEDURES
# ============================================================

procedure getPeakdBFS: .sndObj
    selectObject: .sndObj
    .maxVal = Get maximum: 0, 0, "Sinc70"
    .minVal = Get minimum: 0, 0, "Sinc70"
    .absPeak = max(abs(.maxVal), abs(.minVal))
    if .absPeak > 1e-10
        .peak_dBFS = 20 * log10(.absPeak)
    else
        .peak_dBFS = -100.0
    endif
endproc

# ============================================================
# SPLIT INTO FREQUENCY BANDS (perfect reconstruction)
# ============================================================

appendInfoLine: "Splitting into frequency bands (perfect reconstruction)..."

selectObject: sound
lowBand = Filter (pass Hann band): 0, low_mid_crossover_Hz, 100
Rename: "low_band"

selectObject: sound
highBand = Filter (pass Hann band): mid_high_crossover_Hz, 0, 100
Rename: "high_band"

# MID = original - LOW - HIGH (perfect complement)
selectObject: sound
midBand = Copy: "mid_band"
Formula: ~ self - object[lowBand] - object[highBand]

# ============================================================
# COMPRESS EACH BAND (Envelope-following)
# ============================================================

appendInfoLine: "Compressing bands (envelope-following)..."

gate_sr = 1000
gate_dt = 1 / gate_sr

attack_samples  = max(round(attack_ms  * gate_sr / 1000), 1)
release_samples = max(round(release_ms * gate_sr / 1000), 1)
attack_coef  = 1 - exp(-4.6 / attack_samples)
release_coef = 1 - exp(-4.6 / release_samples)

procedure compressBand: .band, .thresh_dBFS, .ratio, .makeup_dB
    selectObject: .band
    .dur_band = Get total duration
    .band_start = Get start time
    .band_end = Get end time

    # Case 1: Pure Bypass (Ratio 1:1 and no Makeup Gain)
    if .ratio <= 1.0001 and abs(.makeup_dB) < 0.0001
        appendInfoLine: "  Bypassed band (Ratio 1:1, 0 dB makeup)"

    # Case 2: Static Makeup Gain Only (Ratio 1:1 with Makeup Gain)
    elsif .ratio <= 1.0001
        .makeup_lin = 10 ^ (.makeup_dB / 20)
        selectObject: .band
        Formula: ~ self * .makeup_lin
        appendInfoLine: "  Static Gain Only (Ratio 1:1, ", fixed$(.makeup_dB, 1), " dB makeup)"

    # Case 3: Dynamic Compression
    else
        # Dynamic Pitch Floor calculation: ensures safety for short files down to 5ms
        .p_floor = max(100, ceiling(9.6 / .dur_band))

        # Level detection via Intensity (calibrated to absolute dBFS)
        To Intensity: .p_floor, gate_dt, "yes"
        .intens = selected("Intensity")

        nEnvSamples = max(1, round(.dur_band * gate_sr))

        # Calculate target gain reduction array with exact real-time alignment
        for i from 1 to nEnvSamples
            t_i = .band_start + (i - 0.5) * gate_dt
            t_i = min(t_i, .band_end)
            
            selectObject: .intens
            .level_SPL = Get value at time: t_i, "Nearest"
            if .level_SPL = undefined
                .level_SPL = 0
            endif
            
            # Absolute dBFS conversion (SPL - 93.9794)
            .level_dBFS = .level_SPL - 93.9794

            if .level_dBFS > .thresh_dBFS
                .gr_dB = (.thresh_dBFS - .level_dBFS) * (1 - 1 / .ratio)
            else
                .gr_dB = 0.0
            endif
            target_gr[i] = 10 ^ (.gr_dB / 20)
        endfor

        # Create gain envelope sound object aligned to band's time domain
        Create Sound from formula: "gr_env", 1, .band_start, .band_end, gate_sr, "1.0"
        .gr_env = selected("Sound")

        # Attack and Release Smoothing
        prev_val = 1.0
        for i from 1 to nEnvSamples
            curr_target = target_gr[i]
            if curr_target < prev_val
                # Attenuation (Attack)
                new_val = prev_val + (curr_target - prev_val) * attack_coef
            elsif curr_target > prev_val
                # Recovery (Release)
                new_val = prev_val + (curr_target - prev_val) * release_coef
            else
                new_val = curr_target
            endif
            selectObject: .gr_env
            Set value at sample number: 1, i, new_val
            prev_val = new_val
        endfor

        # Resample gain envelope to audio sampling rate
        selectObject: .gr_env
        .gr_hires = Resample: sr, 50
        removeObject: .gr_env

        # Clamp overshoot/undershoot from Sinc interpolation
        selectObject: .gr_hires
        Formula: ~ min(1.0, max(0.0, self))

        # Apply gain reduction envelope + makeup gain safely across all audio channels
        .makeup_lin = 10 ^ (.makeup_dB / 20)
        .gr_hires_id = .gr_hires
        selectObject: .band
        Formula: ~ self * object['.gr_hires_id', 1, col] * '.makeup_lin'

        removeObject: .intens, .gr_hires
    endif
endproc

@compressBand: lowBand, low_threshold_dBFS, low_ratio, low_makeup_dB
@getPeakdBFS: lowBand
appendInfoLine: "  LOW:  Peak after compression: ", fixed$(getPeakdBFS.peak_dBFS, 1), " dBFS"

@compressBand: midBand, mid_threshold_dBFS, mid_ratio, mid_makeup_dB
@getPeakdBFS: midBand
appendInfoLine: "  MID:  Peak after compression: ", fixed$(getPeakdBFS.peak_dBFS, 1), " dBFS"

@compressBand: highBand, high_threshold_dBFS, high_ratio, high_makeup_dB
@getPeakdBFS: highBand
appendInfoLine: "  HIGH: Peak after compression: ", fixed$(getPeakdBFS.peak_dBFS, 1), " dBFS"

# ============================================================
# RECOMBINE BANDS
# ============================================================

appendInfoLine: ""
appendInfoLine: "Recombining bands..."

if solo = 1
    selectObject: lowBand
    result = Copy: sound_name$ + "_multiband"
    selectObject: result
    Formula: ~ self + object[midBand] + object[highBand]
elsif solo = 2
    selectObject: lowBand
    result = Copy: sound_name$ + "_LOW_solo"
elsif solo = 3
    selectObject: midBand
    result = Copy: sound_name$ + "_MID_solo"
else
    selectObject: highBand
    result = Copy: sound_name$ + "_HIGH_solo"
endif

# Peak Normalization (Optional)
if peak_normalize_output
    selectObject: result
    Scale peak: 0.95
endif

# Output Stats
@getPeakdBFS: result
outPeak_dB = getPeakdBFS.peak_dBFS

selectObject: result
outRMS = Get root-mean-square: 0, 0
if outRMS > 1e-10
    outRMS_dB = 20 * log10(outRMS)
else
    outRMS_dB = -100.0
endif

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Generating visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Multiband Compressor v3.0## | " + presetName$ + " | " + string$(low_mid_crossover_Hz) + "/" + string$(mid_high_crossover_Hz) + " Hz"
    
    # Input Waveform
    Select outer viewport: 0, 8, 0.5, 1.5
    Select inner viewport: 0.8, 7.6, 0.6, 1.3
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.5, 1.5
    Text left: "yes", "Input"
    
    # LOW Band
    Select outer viewport: 0, 8, 1.6, 2.4
    Select inner viewport: 0.8, 7.6, 1.7, 2.25
    selectObject: lowBand
    Colour: "{0.8, 0.3, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 0.15, 8, 1.6, 2.4
    Text left: "yes", "LOW"
    
    # MID Band
    Select outer viewport: 0, 8, 2.5, 3.3
    Select inner viewport: 0.8, 7.6, 2.6, 3.15
    selectObject: midBand
    Colour: "{0.3, 0.7, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 0.15, 8, 2.5, 3.3
    Text left: "yes", "MID"
    
    # HIGH Band
    Select outer viewport: 0, 8, 3.4, 4.2
    Select inner viewport: 0.8, 7.6, 3.5, 4.05
    selectObject: highBand
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 0.15, 8, 3.4, 4.2
    Text left: "yes", "HIGH"
    
    # Output Waveform
    Select outer viewport: 0, 8, 4.3, 5.3
    Select inner viewport: 0.8, 7.6, 4.4, 5.1
    selectObject: result
    Colour: "{0.4, 0.4, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 4.3, 5.3
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Band Info Panel
    Select outer viewport: 0, 8, 5.4, 6.0
    Axes: 0, 1, 0, 1
    Font size: 6
    
    Colour: "{0.8, 0.3, 0.3}"
    Paint rectangle: "{0.8, 0.3, 0.3}", 0.02, 0.05, 0.3, 0.7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.07, "left", 0.5, "half", "LOW <" + string$(low_mid_crossover_Hz) + "Hz: " + fixed$(low_ratio, 1) + ":1 @ " + fixed$(low_threshold_dBFS, 1) + "dBFS"
    
    Colour: "{0.3, 0.7, 0.3}"
    Paint rectangle: "{0.3, 0.7, 0.3}", 0.35, 0.38, 0.3, 0.7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.40, "left", 0.5, "half", "MID: " + fixed$(mid_ratio, 1) + ":1 @ " + fixed$(mid_threshold_dBFS, 1) + "dBFS"
    
    Colour: "{0.3, 0.5, 0.8}"
    Paint rectangle: "{0.3, 0.5, 0.8}", 0.68, 0.71, 0.3, 0.7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.73, "left", 0.5, "half", "HIGH >" + string$(mid_high_crossover_Hz) + "Hz: " + fixed$(high_ratio, 1) + ":1 @ " + fixed$(high_threshold_dBFS, 1) + "dBFS"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP & OUTPUT
# ============================================================

removeObject: lowBand, midBand, highBand

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="
appendInfoLine: "Output Interpolated Peak (Sinc70): ", fixed$(outPeak_dB, 1), " dBFS"
appendInfoLine: "Output RMS Level: ", fixed$(outRMS_dB, 1), " dBFS"

if outPeak_dB > 0.0
    appendInfoLine: ""
    appendInfoLine: "** WARNING: Output peak exceeds 0 dBFS (", fixed$(outPeak_dB, 1), " dBFS)! Potential digital clipping. Consider lowering makeup gain or enabling Peak Normalization. **"
endif

if solo > 1
    if solo = 2
        appendInfoLine: ""
        appendInfoLine: "** SOLO: LOW band only **"
    elsif solo = 3
        appendInfoLine: ""
        appendInfoLine: "** SOLO: MID band only **"
    else
        appendInfoLine: ""
        appendInfoLine: "** SOLO: HIGH band only **"
    endif
endif

if play
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    Play
endif

selectObject: result