# ============================================================
# Praat AudioTools - Adaptive_Transient_Decomposition.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2025) - Added presets, fixed formula variables
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Transient Decomposition using LPC residual and sigmoid gating.
#   Separates a sound into Transients and Sustain/Residual components.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.6:
#   - Added presets for different material types
#   - Fixed Formula variable scope issues
#   - More robust object references in formulas
#   - Improved parameter documentation
# ============================================================

# --- Input Validation ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

origId = selected("Sound")
origName$ = selected$("Sound")

form Adaptive Transient Decomposition v0.6
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Percussion (sharp attacks)
        option Piano (medium attacks)
        option Strings (soft attacks)
        option Speech (consonants)
        option Gentle (preserve sustain)
        option Aggressive (isolate transients)
    comment === Analysis ===
    positive LPC_order_per_kHz 2.0
    positive Analysis_window_ms 25.0
    positive Time_step_ms 5.0
    comment === Envelope Detection ===
    positive Integration_ms 5.0
    positive Floor_rate_Hz 10.0
    comment === Transient Detection ===
    real Threshold_dB 6.0
    positive Sigmoid_steepness 2.0
    positive Burst_padding_ms 15.0
    comment === Output ===
    real Transient_gain_dB 0.0
    boolean Draw_visualization 1
endform

# --- Apply Presets ---
if preset = 2
    # Percussion
    lPC_order_per_kHz = 2.0
    analysis_window_ms = 20.0
    time_step_ms = 3.0
    integration_ms = 3.0
    floor_rate_Hz = 8.0
    threshold_dB = 4.0
    sigmoid_steepness = 3.0
    burst_padding_ms = 10.0
    presetName$ = "Percussion"
elsif preset = 3
    # Piano
    lPC_order_per_kHz = 2.5
    analysis_window_ms = 25.0
    time_step_ms = 5.0
    integration_ms = 5.0
    floor_rate_Hz = 10.0
    threshold_dB = 6.0
    sigmoid_steepness = 2.0
    burst_padding_ms = 20.0
    presetName$ = "Piano"
elsif preset = 4
    # Strings
    lPC_order_per_kHz = 3.0
    analysis_window_ms = 30.0
    time_step_ms = 8.0
    integration_ms = 8.0
    floor_rate_Hz = 5.0
    threshold_dB = 8.0
    sigmoid_steepness = 1.5
    burst_padding_ms = 25.0
    presetName$ = "Strings"
elsif preset = 5
    # Speech
    lPC_order_per_kHz = 2.0
    analysis_window_ms = 25.0
    time_step_ms = 5.0
    integration_ms = 4.0
    floor_rate_Hz = 12.0
    threshold_dB = 5.0
    sigmoid_steepness = 2.5
    burst_padding_ms = 15.0
    presetName$ = "Speech"
elsif preset = 6
    # Gentle
    lPC_order_per_kHz = 2.0
    analysis_window_ms = 30.0
    time_step_ms = 8.0
    integration_ms = 10.0
    floor_rate_Hz = 5.0
    threshold_dB = 10.0
    sigmoid_steepness = 1.0
    burst_padding_ms = 30.0
    presetName$ = "Gentle"
elsif preset = 7
    # Aggressive
    lPC_order_per_kHz = 1.5
    analysis_window_ms = 15.0
    time_step_ms = 2.0
    integration_ms = 2.0
    floor_rate_Hz = 15.0
    threshold_dB = 3.0
    sigmoid_steepness = 4.0
    burst_padding_ms = 5.0
    presetName$ = "Aggressive"
else
    presetName$ = "Custom"
endif

# --- Constants ---
epsilon = 1e-9
minDur = 0.1
padDur = 0.1

# --- Setup ---
uid$ = string$(randomInteger(10000, 99999))

selectObject: origId
nChannels = Get number of channels
totalDur = Get total duration
sr = Get sampling frequency

# --- Duration Check ---
if totalDur < minDur
    exitScript: "Sound is too short (minimum " + fixed$(minDur, 2) + " s)"
endif

# Adjust padding for short sounds
if totalDur < 0.5
    padDur = totalDur * 0.25
endif

# --- Info Header ---
writeInfoLine: "=== Adaptive Transient Decomposition v0.6 ==="
appendInfoLine: "Input: ", origName$
appendInfoLine: "Channels: ", nChannels
appendInfoLine: "Duration: ", fixed$(totalDur, 3), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "LPC order factor: ", lPC_order_per_kHz, " / kHz"
appendInfoLine: "Threshold: ", threshold_dB, " dB"
appendInfoLine: ""

# --- Main Processing ---
vizEnvFast = 0
vizEnvSlow = 0
vizMask = 0

if nChannels = 1
    # Mono
    @processChannel: origId, padDur, uid$, draw_visualization
    transId = processChannel.transId
    sustId = processChannel.sustId
    
    if draw_visualization
        vizEnvFast = processChannel.vizEnvFast
        vizEnvSlow = processChannel.vizEnvSlow
        vizMask = processChannel.vizMask
    endif
    
    selectObject: transId
    Rename: origName$ + "_transients"
    
    selectObject: sustId
    Rename: origName$ + "_sustain"

elsif nChannels = 2
    # Stereo
    appendInfoLine: "Processing stereo channels..."
    
    selectObject: origId
    Extract all channels
    ch1 = selected("Sound", 1)
    ch2 = selected("Sound", 2)
    
    # Process Left (with visualization if requested)
    @processChannel: ch1, padDur, uid$ + "L", draw_visualization
    transL = processChannel.transId
    sustL = processChannel.sustId
    
    if draw_visualization
        vizEnvFast = processChannel.vizEnvFast
        vizEnvSlow = processChannel.vizEnvSlow
        vizMask = processChannel.vizMask
    endif
    
    # Process Right (no visualization needed)
    @processChannel: ch2, padDur, uid$ + "R", 0
    transR = processChannel.transId
    sustR = processChannel.sustId
    
    # Merge Transients
    selectObject: transL
    plusObject: transR
    Combine to stereo
    transId = selected("Sound")
    Rename: origName$ + "_transients"
    
    # Merge Sustain
    selectObject: sustL
    plusObject: sustR
    Combine to stereo
    sustId = selected("Sound")
    Rename: origName$ + "_sustain"
    
    # Cleanup
    removeObject: ch1, ch2, transL, transR, sustL, sustR
endif

# --- Output Gain Stage ---
if transient_gain_dB <> 0
    selectObject: transId
    gainLinear = 10 ^ (transient_gain_dB / 20)
    gainStr$ = string$(gainLinear)
    Formula: "self * " + gainStr$
    appendInfoLine: "Applied ", fixed$(transient_gain_dB, 1), " dB gain to transients"
endif

# --- Visualization ---
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    # For stereo, extract channel 1 for display
    if nChannels = 2
        selectObject: origId
        Extract one channel: 1
        vizOrig = selected("Sound")
        
        selectObject: transId
        Extract one channel: 1
        vizTrans = selected("Sound")
        
        selectObject: sustId
        Extract one channel: 1
        vizSust = selected("Sound")
    else
        vizOrig = origId
        vizTrans = transId
        vizSust = sustId
    endif
    
    @drawVisualization: vizOrig, vizTrans, vizSust, vizEnvFast, vizEnvSlow, vizMask, origName$, presetName$
    
    # Cleanup visualization copies for stereo
    if nChannels = 2
        removeObject: vizOrig, vizTrans, vizSust
    endif
    
    # Cleanup envelope/mask objects
    removeObject: vizEnvFast, vizEnvSlow, vizMask
endif

# --- Final Selection ---
selectObject: origId
plusObject: transId
plusObject: sustId

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", origName$, "_transients"
appendInfoLine: "Created: ", origName$, "_sustain"

# ==============================================================================
# Procedure: processChannel
# ==============================================================================
procedure processChannel: .inputId, .pad, .id$, .keepVizObjects
    selectObject: .inputId
    .sr = Get sampling frequency
    .dur = Get total duration
    
    # Convert ms parameters to seconds
    .analysisWindow = analysis_window_ms / 1000
    .timeStep = time_step_ms / 1000
    
    # --- 1. Padding (prevents edge artifacts) ---
    .srStr$ = string$(.sr)
    .sil1 = Create Sound from formula: "sil1_" + .id$, 1, 0, .pad, .sr, "0"
    .sil2 = Create Sound from formula: "sil2_" + .id$, 1, 0, .pad, .sr, "0"
    
    selectObject: .sil1
    plusObject: .inputId
    plusObject: .sil2
    .workSnd = Concatenate
    Rename: "work_" + .id$
    
    removeObject: .sil1, .sil2
    
    # --- 2. LPC Analysis & Inverse Filtering ---
    selectObject: .workSnd
    .nyquistKHz = (.sr / 2) / 1000
    .lpcOrder = round(.nyquistKHz * lPC_order_per_kHz + 2)
    
    To LPC (autocorrelation): .lpcOrder, .analysisWindow, .timeStep, 50
    .lpcObj = selected("LPC")
    
    selectObject: .workSnd
    plusObject: .lpcObj
    Filter (inverse)
    Rename: "residual_" + .id$
    .residual = selected("Sound")
    
    removeObject: .lpcObj
    
    # --- 3. Fast Envelope (transient energy) ---
    selectObject: .residual
    Copy: "resid_sq_" + .id$
    .residSq = selected("Sound")
    Formula: "self * self"
    
    .bwFast = 1000 / integration_ms
    Filter (pass Hann band): 0, .bwFast, 100
    .envFast = selected("Sound")
    Rename: "env_fast_" + .id$
    Formula: "sqrt(abs(self))"
    
    removeObject: .residSq
    
    # --- 4. Slow Envelope (noise floor) ---
    selectObject: .residual
    Copy: "resid_sq_slow_" + .id$
    .residSqSlow = selected("Sound")
    Formula: "self * self"
    
    Filter (pass Hann band): 0, floor_rate_Hz, 20
    .envSlow = selected("Sound")
    Rename: "env_slow_" + .id$
    Formula: "sqrt(abs(self))"
    
    removeObject: .residSqSlow
    
    # --- 5. Mask Generation (sigmoid in dB domain) ---
    # Using Object ID reference for robustness
    .envSlowIdStr$ = string$(.envSlow)
    .steepStr$ = string$(sigmoid_steepness)
    .threshStr$ = string$(threshold_dB)
    .epsStr$ = string$(epsilon)
    
    selectObject: .envFast
    Copy: "mask_" + .id$
    .mask = selected("Sound")
    
    # Sigmoid: 1 / (1 + exp(-steepness * (dB_ratio - threshold)))
    # dB_ratio = 20 * log10(fast / (slow + epsilon))
    Formula: "1 / (1 + exp(-" + .steepStr$ + " * ((20 * log10(self / (Object_" + .envSlowIdStr$ + "[col] + " + .epsStr$ + "))) - " + .threshStr$ + ")))"
    
    # --- 6. Mask Dilation (burst padding) ---
    if burst_padding_ms > 0
        .bwPad = 1000 / burst_padding_ms
        selectObject: .mask
        Filter (pass Hann band): 0, .bwPad, 100
        .maskDilated = selected("Sound")
        Rename: "mask_dilated_" + .id$
        Formula: "1 / (1 + exp(-10 * (self - 0.1)))"
        
        removeObject: .mask
        .mask = .maskDilated
    endif
    
    # --- Keep visualization objects if requested ---
    if .keepVizObjects
        # Crop envelopes and mask to original duration (remove padding)
        selectObject: .envFast
        Extract part: .pad, .pad + .dur, "rectangular", 1, "no"
        Shift times to: "start time", 0
        .vizEnvFast = selected("Sound")
        Rename: "viz_env_fast_" + .id$
        
        selectObject: .envSlow
        Extract part: .pad, .pad + .dur, "rectangular", 1, "no"
        Shift times to: "start time", 0
        .vizEnvSlow = selected("Sound")
        Rename: "viz_env_slow_" + .id$
        
        selectObject: .mask
        Extract part: .pad, .pad + .dur, "rectangular", 1, "no"
        Shift times to: "start time", 0
        .vizMask = selected("Sound")
        Rename: "viz_mask_" + .id$
    else
        .vizEnvFast = 0
        .vizEnvSlow = 0
        .vizMask = 0
    endif
    
    # Cleanup envelopes (originals with padding)
    removeObject: .envFast, .envSlow, .residual
    
    # --- 7. Apply Mask to Original (in padded domain) ---
    .maskIdStr$ = string$(.mask)
    
    selectObject: .workSnd
    Copy: "trans_padded_" + .id$
    .transPadded = selected("Sound")
    Formula: "self * Object_" + .maskIdStr$ + "[col]"
    
    removeObject: .mask
    
    # --- 8. Compute Sustain in Padded Domain ---
    # This ensures perfect sample alignment
    .transPaddedIdStr$ = string$(.transPadded)
    
    selectObject: .workSnd
    Copy: "sust_padded_" + .id$
    .sustPadded = selected("Sound")
    Formula: "self - Object_" + .transPaddedIdStr$ + "[col]"
    
    # --- 9. Crop Both to Original Duration ---
    selectObject: .transPadded
    Extract part: .pad, .pad + .dur, "rectangular", 1, "no"
    Shift times to: "start time", 0
    .transId = selected("Sound")
    Rename: "trans_" + .id$
    
    selectObject: .sustPadded
    Extract part: .pad, .pad + .dur, "rectangular", 1, "no"
    Shift times to: "start time", 0
    .sustId = selected("Sound")
    Rename: "sust_" + .id$
    
    # Cleanup
    removeObject: .transPadded, .sustPadded, .workSnd
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization: .origId, .transId, .sustId, .envFastId, .envSlowId, .maskId, .name$, .preset$
    
    # Get time bounds
    selectObject: .origId
    .tMin = Get start time
    .tMax = Get end time
    .dur = .tMax - .tMin
    
    # Get amplitude bounds for waveforms
    selectObject: .origId
    .origMax = Get maximum: 0, 0, "Sinc70"
    .origMin = Get minimum: 0, 0, "Sinc70"
    .ampMax = max(abs(.origMax), abs(.origMin)) * 1.1
    
    # Get envelope bounds
    selectObject: .envFastId
    .envMax = Get maximum: 0, 0, "Sinc70"
    .envMax = .envMax * 1.2
    
    # === Setup Picture Window ===
    Erase all
    
    # Define colors
    .colOrig$ = "Black"
    .colTrans$ = "{0.8, 0.2, 0.2}"
    .colSust$ = "{0.2, 0.5, 0.8}"
    .colEnvFast$ = "{0.9, 0.4, 0.1}"
    .colEnvSlow$ = "{0.2, 0.6, 0.3}"
    .colMask$ = "{0.6, 0.2, 0.8}"
    .colThresh$ = "{0.5, 0.5, 0.5}"
    .colGrid$ = "{0.85, 0.85, 0.85}"
    
    .leftMargin = 0.8
    .rightMargin = 6.5
    .rowHeight = 1.2
    .gap = 0.15
    
    # === Row 1: Title ===
    Select outer viewport: 0, 7, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text top: "no", "Adaptive Transient Decomposition: " + .name$ + " [" + .preset$ + "]"
    
    # === Row 2: Original Waveform ===
    .top = 0.6
    .bottom = .top + .rowHeight
    Select outer viewport: 0, 7, .top, .bottom
    Font size: 10
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    
    Colour: .colGrid$
    Line width: 1
    Draw line: .tMin, 0, .tMax, 0
    
    Colour: .colOrig$
    Line width: 1
    selectObject: .origId
    Draw: .tMin, .tMax, -.ampMax, .ampMax, "no", "Curve"
    
    Select outer viewport: 0, .leftMargin, .top, .bottom
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Original"
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    Colour: "Black"
    Marks left: 3, "yes", "yes", "no"
    
    # === Row 3: Transients Waveform ===
    .top = .bottom
    .bottom = .top + .rowHeight
    Select outer viewport: 0, 7, .top, .bottom
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    
    Colour: .colGrid$
    Line width: 1
    Draw line: .tMin, 0, .tMax, 0
    
    Colour: .colTrans$
    Line width: 1
    selectObject: .transId
    Draw: .tMin, .tMax, -.ampMax, .ampMax, "no", "Curve"
    
    Select outer viewport: 0, .leftMargin, .top, .bottom
    Colour: .colTrans$
    Text: 0.5, "centre", 0.5, "half", "Transients"
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    Colour: "Black"
    Marks left: 3, "yes", "yes", "no"
    
    # === Row 4: Sustain Waveform ===
    .top = .bottom
    .bottom = .top + .rowHeight
    Select outer viewport: 0, 7, .top, .bottom
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    
    Colour: .colGrid$
    Line width: 1
    Draw line: .tMin, 0, .tMax, 0
    
    Colour: .colSust$
    Line width: 1
    selectObject: .sustId
    Draw: .tMin, .tMax, -.ampMax, .ampMax, "no", "Curve"
    
    Select outer viewport: 0, .leftMargin, .top, .bottom
    Colour: .colSust$
    Text: 0.5, "centre", 0.5, "half", "Sustain"
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -.ampMax, .ampMax
    Colour: "Black"
    Marks left: 3, "yes", "yes", "no"
    
    # === Row 5: Envelopes ===
    .top = .bottom
    .bottom = .top + .rowHeight
    Select outer viewport: 0, 7, .top, .bottom
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, 0, .envMax
    
    # Slow envelope (floor)
    Colour: .colEnvSlow$
    Line width: 2
    selectObject: .envSlowId
    Draw: .tMin, .tMax, 0, .envMax, "no", "Curve"
    
    # Fast envelope
    Colour: .colEnvFast$
    Line width: 1.5
    selectObject: .envFastId
    Draw: .tMin, .tMax, 0, .envMax, "no", "Curve"
    
    Select outer viewport: 0, .leftMargin, .top, .bottom
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Envelopes"
    
    # Legend
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: .colEnvFast$
    Text: 0.02, "left", 0.92, "half", "Fast"
    Colour: .colEnvSlow$
    Text: 0.12, "left", 0.92, "half", "Slow"
    
    Axes: .tMin, .tMax, 0, .envMax
    Colour: "Black"
    Font size: 10
    Marks left: 3, "yes", "yes", "no"
    
    # === Row 6: Mask ===
    .top = .bottom
    .bottom = .top + .rowHeight
    Select outer viewport: 0, 7, .top, .bottom
    Colour: .colGrid$
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -0.1, 1.1
    
    # Threshold reference
    Colour: .colThresh$
    Line width: 1
    Dotted line
    Draw line: .tMin, 0.5, .tMax, 0.5
    Solid line
    
    # Mask curve
    Colour: .colMask$
    Line width: 2
    selectObject: .maskId
    Draw: .tMin, .tMax, -0.1, 1.1, "no", "Curve"
    
    Select outer viewport: 0, .leftMargin, .top, .bottom
    Colour: .colMask$
    Text: 0.5, "centre", 0.5, "half", "Mask"
    
    Select inner viewport: .leftMargin, .rightMargin, .top + .gap, .bottom - .gap
    Axes: .tMin, .tMax, -0.1, 1.1
    Colour: "Black"
    Marks left: 3, "yes", "yes", "no"
    
    # Time axis
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    
    # === Footer ===
    .top = .bottom
    .bottom = .top + 0.5
    Select outer viewport: 0, 7, .top, .bottom
    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Threshold: " + fixed$(threshold_dB, 1) + " dB | Integration: " + fixed$(integration_ms, 1) + " ms | Floor: " + fixed$(floor_rate_Hz, 1) + " Hz | Steepness: " + fixed$(sigmoid_steepness, 1) + " | Padding: " + fixed$(burst_padding_ms, 1) + " ms"
    Text top: "no", .paramText$
    
    # Reset
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc