# ============================================================
# Praat AudioTools - Dynamic True-Peak Limiter
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True Dynamic Peak Limiter with True 4x+ Oversampled Sidechain,
#   Future-Window Minimum Lookahead, Multi-channel Linked Peak Envelope,
#   Continuous Monotonic Soft Knee, Causal Asymmetric Exponential Release,
#   and Sinc70 True Peak Safety Ceiling.
# ============================================================

# Changelog v3.4 (2026):
#   - FIX: Peak_normalize_to_ceiling now operates on every non-silent result;
#     the old 0.001 amplitude cutoff incorrectly skipped very quiet material.
#   - FIX: final-stage reporting now distinguishes signed global gain from
#     attenuation. Peak-normalization attenuation is included in Total Peak
#     Attenuation, while positive normalization gain is not misreported as loss.
#   - FIX: Input/Output waveform panels and their Threshold/Ceiling reference
#     lines now use one explicit shared amplitude scale instead of mixing
#     autoscaled waveform drawing with fixed -1..1 reference-line axes.
#   - SAFETY: 4x+ oversampled sidechain construction now checks the estimated
#     total number of oversampled sample values before Resample and exits with a
#     clear message if the temporary Sound would exceed the configured limit.
#
# Changelog v3.3 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
form Dynamic True-Peak Limiter v3.4
    optionmenu Preset 1
        option Custom
        option -1 dBTP Transparent Limiter
        option -0.3 dBTP Peak Maxima
        option -2 dBTP Gentle Limiter
        option -1 dBTP Streaming Ceiling
        option -1.5 dBTP Smooth Limiter
        option -0.1 dBTP Brickwall Fast
    comment === Threshold & Ceiling ===
    real Threshold_dB -1.0
    real Ceiling_dBTP -1.0
    comment === Dynamics & Character ===
    real Release_ms 30.0
    real Lookahead_ms 3.0
    real Knee_dB 2.0
    comment === Output Options ===
    boolean Peak_normalize_to_ceiling 0
    boolean Visualize 1
    boolean Play 1
endform

# === INPUT SELECTION CHECK ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sr = Get sampling frequency
start_time = Get start time
end_time = Get end time
dur = end_time - start_time
nChannels = Get number of channels

# === APPLY PRESETS (Executed BEFORE Parameter Validation) ===
if preset = 2
    threshold_dB = -1.0
    ceiling_dBTP = -1.0
    release_ms = 40.0
    lookahead_ms = 3.0
    knee_dB = 3.0
    presetName$ = "Transparent Limiter"
elsif preset = 3
    threshold_dB = -0.3
    ceiling_dBTP = -0.3
    release_ms = 15.0
    lookahead_ms = 1.5
    knee_dB = 1.0
    presetName$ = "Peak Maxima"
elsif preset = 4
    threshold_dB = -2.0
    ceiling_dBTP = -2.0
    release_ms = 50.0
    lookahead_ms = 5.0
    knee_dB = 4.0
    presetName$ = "Gentle Limiter"
elsif preset = 5
    threshold_dB = -1.0
    ceiling_dBTP = -1.0
    release_ms = 30.0
    lookahead_ms = 2.5
    knee_dB = 2.0
    presetName$ = "Streaming Ceiling"
elsif preset = 6
    threshold_dB = -1.5
    ceiling_dBTP = -1.0
    release_ms = 60.0
    lookahead_ms = 4.0
    knee_dB = 6.0
    presetName$ = "Smooth Limiter"
elsif preset = 7
    threshold_dB = -0.1
    ceiling_dBTP = -0.1
    release_ms = 5.0
    lookahead_ms = 1.0
    knee_dB = 0.0
    presetName$ = "Brickwall Fast"
else
    presetName$ = "Custom"
endif

# === PARAMETER VALIDATION GUARDRAILS ===
if ceiling_dBTP > 0
    exitScript: "Validation Error: Ceiling_dBTP must be <= 0 dBTP."
endif
if threshold_dB > 0
    exitScript: "Validation Error: Threshold_dB must be <= 0 dB."
endif
if knee_dB < 0
    exitScript: "Validation Error: Knee_dB must be >= 0 dB."
endif
if release_ms < 1.0
    exitScript: "Validation Error: Release_ms must be >= 1.0 ms."
endif
if lookahead_ms < 0
    exitScript: "Validation Error: Lookahead_ms must be >= 0 ms."
endif
if lookahead_ms / 1000 >= dur / 2
    exitScript: "Validation Error: Lookahead_ms is too long for this sound duration."
endif

# Handle Threshold > Ceiling safely
if threshold_dB > ceiling_dBTP
    threshold_dB = ceiling_dBTP
endif

threshold = 10 ^ (threshold_dB / 20)
ceiling = 10 ^ (ceiling_dBTP / 20)
lookahead_sec = lookahead_ms / 1000

# === INFO HEADER ===
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "  DYNAMIC TRUE-PEAK LIMITER v3.4"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), "s, ", nChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Threshold: ", fixed$(threshold_dB, 1), " dB"
appendInfoLine: "Ceiling: ", fixed$(ceiling_dBTP, 1), " dBTP"
appendInfoLine: "Release: ", fixed$(release_ms, 1), " ms"
appendInfoLine: "Lookahead: ", fixed$(lookahead_ms, 1), " ms"
appendInfoLine: "Knee: ", fixed$(knee_dB, 1), " dB"
appendInfoLine: ""

# === INPUT ANALYSIS ===
selectObject: sound
inPeak = Get maximum: start_time, end_time, "Sinc70"
inPeakNeg = Get minimum: start_time, end_time, "Sinc70"
inPeakAbs = max(abs(inPeak), abs(inPeakNeg))
inPeak_dB = 20 * log10(inPeakAbs + 1e-10)

appendInfoLine: "Input True Peak: ", fixed$(inPeak_dB, 2), " dBTP (Sinc70)"

# ============================================================
# DYNAMIC TRUE-PEAK LIMITING ENGINE
# ============================================================
appendInfoLine: ""
appendInfoLine: "Building 4x+ oversampled True-Peak sidechain..."

# 1. Oversampled True-Peak Sidechain (Guaranteed 4x+ Oversampling for ISPs)
target_sr = max(sr * 4, 176400)
# v3.4 safety guard: estimate total sample VALUES (frames x channels) in the
# temporary oversampled Sound before allocating it. This preserves the 4x+
# requirement rather than silently lowering the oversampling factor.
maxOversampledValues = 20000000
estimatedOversampledFrames = ceiling(dur * target_sr)
estimatedOversampledValues = estimatedOversampledFrames * nChannels
if estimatedOversampledValues > maxOversampledValues
    exitScript: "Oversampled true-peak sidechain would require about " + string$(estimatedOversampledValues) + " sample values at " + fixed$(target_sr, 0) + " Hz (safety limit " + string$(maxOversampledValues) + "). Process a shorter Sound or reduce the source sampling rate."
endif
appendInfoLine: "Oversampled sidechain: ", fixed$(target_sr, 0), " Hz; estimated ", estimatedOversampledValues, " sample values"
selectObject: sound
sound_oversampled = Resample: target_sr, 50
sound_os_id = sound_oversampled

selectObject: sound_os_id
os_nCh = Get number of channels

if os_nCh = 1
    sidechain = Copy: sound_name$ + "_sidechain"
    Formula: ~ abs(self)
else
    sidechain = Extract one channel: 1
    Rename: sound_name$ + "_sidechain"
    Formula: ~ abs(self)
    for c from 2 to os_nCh
        selectObject: sidechain
        Formula: ~ max(self, abs(Object_'sound_os_id'[c, col]))
    endfor
endif
removeObject: sound_os_id

# 2. Monotonic Soft-Knee Target Gain Calculation in dB Domain
appendInfoLine: "Computing continuous gain reduction envelope..."
selectObject: sidechain
target_gain = Copy: sound_name$ + "_targetGain"

if knee_dB > 0
    lower_dB = threshold_dB - knee_dB / 2
    upper_dB = threshold_dB + knee_dB / 2
    Formula: ~ 10 ^ ((if 20*log10(self+1e-12) < lower_dB then 0 else if 20*log10(self+1e-12) > upper_dB then threshold_dB - 20*log10(self+1e-12) else -((20*log10(self+1e-12) - lower_dB) ^ 2) / (2 * knee_dB) fi fi) / 20)
else
    Formula: ~ 10 ^ ((if 20*log10(self+1e-12) > threshold_dB then threshold_dB - 20*log10(self+1e-12) else 0 fi) / 20)
endif

# Clamp target_gain
Formula: ~ max(0.0001, min(1.0, self))

# 3. Future-Window Minimum Lookahead (Protects exact peak moment t_0)
if lookahead_sec > 0
    os_end_time = Get end time
    os_sr = Get sampling frequency
    step_sec = 1 / os_sr
    curr_win = step_sec
    while curr_win < lookahead_sec
        shift_sec = min(curr_win, lookahead_sec - curr_win)
        Formula: ~ min(self, self(min(os_end_time - 1e-5, x + shift_sec)))
        curr_win = curr_win + shift_sec
    endwhile
endif

# 4. Causal Asymmetric Exponential Release Envelope Follower
os_sr = Get sampling frequency
release_sec = release_ms / 1000
alpha_release = exp(-1 / (os_sr * release_sec))
rel_factor = 1 - alpha_release

Formula: ~ if col = 1 then self else if self < self[1, max(1, col-1)] then self else min(self, self[1, max(1, col-1)] + (1 - self[1, max(1, col-1)]) * rel_factor) fi fi

# 5. Resample Envelope, Apply Post-Resample Clamp, & Multiply Audio
selectObject: target_gain
gain_envelope = Resample: sr, 50
Rename: sound_name$ + "_envelope"

# Post-resampling clamp to remove any sinc interpolation ringing
Formula: ~ max(0.0001, min(1.0, self))

removeObject: sidechain
removeObject: target_gain

selectObject: sound
result = Copy: sound_name$ + "_limited"
Formula: ~ self * Object_'gain_envelope'[1, col]

# === CEILING & PEAK NORMALIZATION STAGE ===
selectObject: result
currentPeak = Get maximum: start_time, end_time, "Sinc70"
currentPeakNeg = Get minimum: start_time, end_time, "Sinc70"
currentPeakAbs = max(abs(currentPeak), abs(currentPeakNeg))

safety_attenuation_dB = 0.0
final_global_gain_dB = 0.0
final_global_attenuation_dB = 0.0

if peak_normalize_to_ceiling
    # Normalize every genuinely non-silent result. The former 0.001 threshold
    # (~-60 dBFS) incorrectly skipped quiet but valid signals.
    if currentPeakAbs > 1e-12
        gainRatio = ceiling / currentPeakAbs
        Formula: ~ self * gainRatio
        final_global_gain_dB = 20 * log10(gainRatio)
        if final_global_gain_dB < 0
            final_global_attenuation_dB = -final_global_gain_dB
        endif
        appendInfoLine: "  Peak Normalization applied: ", fixed$(final_global_gain_dB, 2), " dB global gain"
    else
        appendInfoLine: "  Peak Normalization requested but output is silent; no gain applied."
    endif
else
    if currentPeakAbs > ceiling
        gainRatio = ceiling / currentPeakAbs
        Formula: ~ self * gainRatio
        safety_attenuation_dB = -20 * log10(gainRatio)
        final_global_gain_dB = -safety_attenuation_dB
        final_global_attenuation_dB = safety_attenuation_dB
        appendInfoLine: "  Final safety ceiling adjustment: -", fixed$(safety_attenuation_dB, 2), " dB"
    else
        appendInfoLine: "  Signal within ceiling limit - no global safety adjustment required."
    endif
endif

# === OUTPUT ANALYSIS & REPORTING ===
selectObject: result
outPeak = Get maximum: start_time, end_time, "Sinc70"
outPeakNeg = Get minimum: start_time, end_time, "Sinc70"
outPeakAbs = max(abs(outPeak), abs(outPeakNeg))
outPeak_dB = 20 * log10(outPeakAbs + 1e-10)

selectObject: gain_envelope
minGain = Get minimum: start_time, end_time, "None"
maxDynamicGR_dB = -20 * log10(minGain + 1e-10)
totalMaxAttenuation_dB = maxDynamicGR_dB + final_global_attenuation_dB

appendInfoLine: ""
appendInfoLine: "Output True Peak: ", fixed$(outPeak_dB, 2), " dBTP (Sinc70)"
appendInfoLine: "Max Dynamic Gain Reduction: ", fixed$(maxDynamicGR_dB, 2), " dB"
appendInfoLine: "Final Global Gain: ", fixed$(final_global_gain_dB, 2), " dB"
if peak_normalize_to_ceiling
    appendInfoLine: "Peak-Normalization Attenuation: ", fixed$(final_global_attenuation_dB, 2), " dB"
else
    appendInfoLine: "Final Safety Ceiling Attenuation: ", fixed$(safety_attenuation_dB, 2), " dB"
endif
appendInfoLine: "Total Peak Attenuation: ", fixed$(totalMaxAttenuation_dB, 2), " dB"
appendInfoLine: "Peak Level Change: ", fixed$(outPeak_dB - inPeak_dB, 2), " dB"

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Rendering visual analytics..."
    
    Erase all
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Dynamic True-Peak Limiter v3.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | ceiling " + fixed$(ceiling_dBTP, 1) + " dBTP"

    # Explicit shared vertical range for Input and Output. This keeps the
    # waveforms and their Threshold/Ceiling reference lines in the same
    # coordinate system and also makes before/after amplitude comparable.
    waveAmp = max(inPeakAbs, outPeakAbs)
    if threshold > waveAmp
        waveAmp = threshold
    endif
    if ceiling > waveAmp
        waveAmp = ceiling
    endif
    if waveAmp < 0.001
        waveAmp = 0.001
    endif
    waveAmp = waveAmp * 1.10

    # Input Waveform
    Select outer viewport: 0, 8, 0.4, 1.9
    Select inner viewport: 0.8, 7.6, 0.5, 1.8
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: start_time, end_time, -waveAmp, waveAmp, "no", "Curve"
    
    # Threshold Lines
    Axes: start_time, end_time, -waveAmp, waveAmp
    Colour: "{0.9, 0.3, 0.3}"
    Dashed line
    Draw line: start_time, threshold, end_time, threshold
    Draw line: start_time, -threshold, end_time, -threshold
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.4, 1.9
    Text left: "yes", "Input Wave"
    
    # Output Waveform
    Select outer viewport: 0, 8, 2.0, 3.5
    Select inner viewport: 0.8, 7.6, 2.1, 3.4
    selectObject: result
    Colour: "{0.2, 0.5, 0.3}"
    Draw: start_time, end_time, -waveAmp, waveAmp, "no", "Curve"
    
    # Ceiling Lines
    Axes: start_time, end_time, -waveAmp, waveAmp
    Colour: "{0.3, 0.3, 0.8}"
    Dashed line
    Draw line: start_time, ceiling, end_time, ceiling
    Draw line: start_time, -ceiling, end_time, -ceiling
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 2.0, 3.5
    Text left: "yes", "Output Wave"
    
    # Dynamic Gain Reduction Envelope
    Select outer viewport: 0, 4.2, 3.6, 5.8
    Select inner viewport: 0.8, 3.8, 3.8, 5.5
    selectObject: gain_envelope
    Colour: "{0.8, 0.2, 0.2}"
    Draw: start_time, end_time, 0, 1.1, "no", "Curve"
    Axes: start_time, end_time, 0, 1.1
    Colour: "{0.7, 0.7, 0.7}"
    Dashed line
    Draw line: start_time, 1.0, end_time, 1.0
    Solid line
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.15, 4.2, 3.6, 5.8
    Text left: "yes", "Gain Target (0..1)"
    
    # Summary panel
    Select outer viewport: 4.3, 8, 3.6, 5.8
    Select inner viewport: 4.45, 7.70, 3.78, 5.62
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "{0.20, 0.20, 0.25}"
    Text: 0.5, "centre", 0.95, "half", "##Summary##"
    Font size: 6
    Text: 0.05, "left", 0.75, "half", "Input True Peak (Sinc70):"
    Text: 0.80, "left", 0.75, "half", fixed$(inPeak_dB, 2) + " dBTP"
    Text: 0.05, "left", 0.60, "half", "Output True Peak (Sinc70):"
    Text: 0.80, "left", 0.60, "half", fixed$(outPeak_dB, 2) + " dBTP"
    Text: 0.05, "left", 0.45, "half", "Max Dynamic Gain Reduction:"
    Text: 0.80, "left", 0.45, "half", fixed$(maxDynamicGR_dB, 2) + " dB"
    if peak_normalize_to_ceiling
        finalStageLabel$ = "Peak Normalize Global Gain:"
        finalStageValue$ = fixed$(final_global_gain_dB, 2) + " dB"
    else
        finalStageLabel$ = "Safety Ceiling Attenuation:"
        finalStageValue$ = fixed$(safety_attenuation_dB, 2) + " dB"
    endif
    Text: 0.05, "left", 0.30, "half", finalStageLabel$
    Text: 0.80, "left", 0.30, "half", finalStageValue$
    Text: 0.05, "left", 0.15, "half", "Total Peak Attenuation:"
    Text: 0.80, "left", 0.15, "half", fixed$(totalMaxAttenuation_dB, 2) + " dB"
    
    Font size: 10
    Colour: "Black"
    # Restore complete page for Picture export / clipboard.
    pageHeight = 6.20
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# Clean up envelope object
removeObject: gain_envelope

# Final Output Selection & Play
selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE: ", selected$("Sound")
appendInfoLine: "=============================================="

if play
    appendInfoLine: "Playing result..."
    Play
endif

selectObject: result