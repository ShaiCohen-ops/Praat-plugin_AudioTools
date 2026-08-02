# ============================================================
# Praat AudioTools - LUFS_Tool.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 4.1 (2026) - Bugfix Release for Parselmouth/Praat Formula Scope
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Implements core ITU-R BS.1770-5 / EBU R128 & EBU Tech 3342 algorithms.
#   Features Gated Integrated LUFS, High-Density LRA with Trailing Silence Padding,
#   Channel-Layout Validated Multichannel Analysis, True Peak Measurement (4x Oversampled Sinc70),
#   Safe Target Gain, Dynamic Peak Limiting with Iterative Convergence, and Post-Processing Re-measurement.
# ============================================================

form LUFS Tool v4.1
    optionmenu Preset 1
        option Custom
        option Spotify (-14 LUFS / -1 dBTP)
        option Apple Podcasts (-16 LUFS / -1 dBTP)
        option YouTube (-14 LUFS / -1 dBTP)
        option Broadcast EU (EBU R128 -23 LUFS / -1 dBTP)
        option Broadcast US (ATSC A/85 -24 LUFS / -2 dBTP)
        option Film / Cinema (-27 LUFS) (Suggested Target)
        option Classical Music (-18 LUFS) (Suggested Target)
        option CD Master (-9 LUFS) (Suggested Target)
    real Custom_target_LUFS -14.0
    comment === Channel Configuration ===
    optionmenu Channel_Layout 1
        option Mono / Stereo (1 or 2 channels)
        option 5.1 Surround (6 channels: L, R, C, LFE, Ls, Rs)
    comment === Processing Mode ===
    optionmenu Mode 1
        option Analyze Only
        option Apply Exact Gain (may clip)
        option Apply Safe Gain (no clipping)
        option Normalize to Target (with dynamic limiting)
    comment === True Peak Ceiling ===
    real True_peak_ceiling_dB -1.0
    comment === Output Options ===
    boolean Visualize 1
    boolean Play 0
endform

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Validation Error: Please select exactly one Sound object."
endif

input = selected("Sound")
input$ = selected$("Sound")

selectObject: input
sr = Get sampling frequency
sourceStart = Get start time
sourceEnd = Get end time
duration = sourceEnd - sourceStart
nChannels = Get number of channels

if duration < 0.4
    exitScript: "Validation Error: Audio file is too short (< 0.4s) for standard EBU R128 gated measurement."
endif

if true_peak_ceiling_dB > 0.0
    exitScript: "Validation Error: True Peak Ceiling must be <= 0.0 dBTP."
endif

# Channel Layout Validation
if channel_Layout = 1
    if nChannels <> 1 and nChannels <> 2
        exitScript: "Validation Error: Selected 'Mono / Stereo' layout requires 1 or 2 channels (Input file has " + string$(nChannels) + " channels)."
    endif
elsif channel_Layout = 2
    if nChannels <> 6
        exitScript: "Validation Error: Selected '5.1 Surround' layout requires exactly 6 channels: L, R, C, LFE, Ls, Rs (Input file has " + string$(nChannels) + " channels)."
    endif
endif

# === APPLY PRESETS ===
if preset = 2
    target_LUFS = -14.0
    true_peak_ceiling_dB = -1.0
    presetName$ = "Spotify"
elsif preset = 3
    target_LUFS = -16.0
    true_peak_ceiling_dB = -1.0
    presetName$ = "Apple Podcasts"
elsif preset = 4
    target_LUFS = -14.0
    true_peak_ceiling_dB = -1.0
    presetName$ = "YouTube"
elsif preset = 5
    target_LUFS = -23.0
    true_peak_ceiling_dB = -1.0
    presetName$ = "EBU R128 (EU Broadcast)"
elsif preset = 6
    target_LUFS = -24.0
    true_peak_ceiling_dB = -2.0
    presetName$ = "ATSC A/85 (US Broadcast)"
elsif preset = 7
    target_LUFS = -27.0
    presetName$ = "Cinema (Suggested)"
elsif preset = 8
    target_LUFS = -18.0
    presetName$ = "Classical (Suggested)"
elsif preset = 9
    target_LUFS = -9.0
    true_peak_ceiling_dB = -0.5
    presetName$ = "CD Master (Suggested)"
else
    target_LUFS = custom_target_LUFS
    presetName$ = "Custom"
endif

# Define Channel Weights (BS.1770-5)
for c from 1 to nChannels
    chWeight[c] = 1.0
endfor

if channel_Layout = 2 and nChannels = 6
    # 5.1 Surround: L=1, R=2, C=3, LFE=4, Ls=5, Rs=6
    chWeight[1] = 1.0
    chWeight[2] = 1.0
    chWeight[3] = 1.0
    chWeight[4] = 0.0  ; LFE channel ignored
    chWeight[5] = 1.41 ; +1.5 dB surround weighting
    chWeight[6] = 1.41 ; +1.5 dB surround weighting
endif

# === INFO HEADER ===
clearinfo
appendInfoLine: "=============================================="
appendInfoLine: "  LUFS TOOL v4.1 (BS.1770-5 / EBU R128)"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", input$, " (", fixed$(duration, 2), "s, ", sr, " Hz, ", nChannels, " ch)"
appendInfoLine: "Time Domain: ", fixed$(sourceStart, 2), "s to ", fixed$(sourceEnd, 2), "s"
appendInfoLine: "Preset: ", presetName$, " | Target: ", fixed$(target_LUFS, 1), " LUFS"
appendInfoLine: "Target Ceiling: ", fixed$(true_peak_ceiling_dB, 1), " dBTP"
appendInfoLine: ""

# ============================================================
# HELPER PROCEDURES DEFINITION
# ============================================================

# Procedure: Measure True Peak via 4x Oversampling + Sinc70
procedure measureTruePeak: .soundObj, .pStart, .pEnd
    selectObject: .soundObj
    .sr_orig = Get sampling frequency
    .os = Resample: max(.sr_orig * 4, 176400), 50
    selectObject: .os
    .maxVal = Get maximum: .pStart, .pEnd, "Sinc70"
    .minVal = Get minimum: .pStart, .pEnd, "Sinc70"
    .tpVal = max(abs(.maxVal), abs(.minVal))
    if .tpVal > 1e-5
        .tp_dB = 20 * log10(.tpVal)
    else
        .tp_dB = -100.0
    endif
    removeObject: .os
endproc

# Procedure: Apply Biquad Filter in-place (Robust ID Expansion)
procedure biquad: .sig, .b0, .b1, .b2, .a1, .a2
    selectObject: .sig
    .xcopy = Copy: "biquad_x"
    selectObject: .sig
    Formula: ~ if col > 2 then ('.b0')*object['.xcopy',row,col] + ('.b1')*object['.xcopy',row,col-1] + ('.b2')*object['.xcopy',row,col-2] - ('.a1')*self[col-1] - ('.a2')*self[col-2] else self fi
    removeObject: .xcopy
endproc

# Procedure: Perform Dynamic True-Peak Limiter
procedure applyLimiter: .snd, .pStart, .pEnd, .srVal, .nCh, .ceiling_dB
    .ceilingLinear = 10 ^ (.ceiling_dB / 20)
    .target_sr = max(.srVal * 4, 176400)
    selectObject: .snd
    .os_sound = Resample: .target_sr, 50
    
    selectObject: .os_sound
    if .nCh = 1
        .sidechain = Copy: "sc_env"
        Formula: ~ abs(self)
    else
        .sidechain = Extract one channel: 1
        Rename: "sc_env"
        Formula: ~ abs(self)
        for .c from 2 to .nCh
            selectObject: .sidechain
            Formula: ~ max(self, abs(Object_'.os_sound'['.c', col]))
        endfor
    endif
    removeObject: .os_sound
    
    selectObject: .sidechain
    Formula: ~ if self > '.ceilingLinear' then '.ceilingLinear' / self else 1.0 fi
    
    .os_end_time = Get end time
    .os_sr = Get sampling frequency
    .lookahead_sec = 0.003
    .step_sec = 1 / .os_sr
    .curr_win = .step_sec
    while .curr_win < .lookahead_sec
        .shift_sec = min(.curr_win, .lookahead_sec - .curr_win)
        Formula: ~ min(self, self(min('.os_end_time' - 1e-5, x + '.shift_sec')))
        .curr_win = .curr_win + .shift_sec
    endwhile
    
    .release_sec = 0.030
    .alpha_release = exp(-1 / (.os_sr * .release_sec))
    .rel_factor = 1 - .alpha_release
    Formula: ~ if col = 1 then self else if self < self[1, max(1, col-1)] then self else min(self, self[1, max(1, col-1)] + (1 - self[1, max(1, col-1)]) * '.rel_factor') fi fi
    
    .gain_envelope = Resample: .srVal, 50
    Formula: ~ max(0.0001, min(1.0, self))
    
    selectObject: .snd
    Formula: ~ self * Object_'.gain_envelope'[1, col]
    
    removeObject: .sidechain
    removeObject: .gain_envelope
endproc

# Procedure: Perform Full Loudness Measurement Pipeline
procedure analyzeLoudness: .soundObj, .pStart, .pEnd, .srVal, .nCh
    # 1. K-Weighting Filtering
    .hs_f0 = 1681.974450955533
    .hs_Q = 0.7071752369554196
    .hs_K = tan(pi * .hs_f0 / .srVal)
    .hs_Vh = 10 ^ (3.999843853973347 / 20)
    .hs_Vb = .hs_Vh ^ 0.4996667741545416
    .hs_a0 = 1 + .hs_K / .hs_Q + .hs_K * .hs_K
    .hs_b0 = (.hs_Vh + .hs_Vb * .hs_K / .hs_Q + .hs_K * .hs_K) / .hs_a0
    .hs_b1 = 2 * (.hs_K * .hs_K - .hs_Vh) / .hs_a0
    .hs_b2 = (.hs_Vh - .hs_Vb * .hs_K / .hs_Q + .hs_K * .hs_K) / .hs_a0
    .hs_a1 = 2 * (.hs_K * .hs_K - 1) / .hs_a0
    .hs_a2 = (1 - .hs_K / .hs_Q + .hs_K * .hs_K) / .hs_a0

    .hp_f0 = 38.13547087602444
    .hp_Q = 0.5003270373238773
    .hp_K = tan(pi * .hp_f0 / .srVal)
    .hp_a0 = 1 + .hp_K / .hp_Q + .hp_K * .hp_K
    .hp_b0 = 1.0
    .hp_b1 = -2.0
    .hp_b2 = 1.0
    .hp_a1 = 2 * (.hp_K * .hp_K - 1) / .hp_a0
    .hp_a2 = (1 - .hp_K / .hp_Q + .hp_K * .hp_K) / .hp_a0

    selectObject: .soundObj
    .k_weighted = Copy: "k_weighted_temp"
    @biquad: .k_weighted, .hs_b0, .hs_b1, .hs_b2, .hs_a1, .hs_a2
    @biquad: .k_weighted, .hp_b0, .hp_b1, .hp_b2, .hp_a1, .hp_a2

    # 2. Integrated LUFS (Gated BS.1770-5)
    .blockDur = 0.4
    .hop = 0.1
    .durVal = .pEnd - .pStart
    if .durVal >= .blockDur
        .nBlocks = floor((.durVal - .blockDur) / .hop) + 1
    else
        .nBlocks = 1
    endif

    .sumMS_abs = 0
    .countAbs = 0
    for .bk from 1 to .nBlocks
        .t1 = .pStart + (.bk - 1) * .hop
        .t2 = .t1 + .blockDur
        if .t2 > .pEnd
            .t2 = .pEnd
        endif
        
        .ms_b = 0
        for .c from 1 to .nCh
            if chWeight[.c] > 0
                selectObject: .k_weighted
                if .nCh > 1
                    .chSig = Extract one channel: .c
                else
                    .chSig = .k_weighted
                endif
                .rms_c = Get root-mean-square: .t1, .t2
                if .nCh > 1
                    removeObject: .chSig
                endif
                .ms_b = .ms_b + chWeight[.c] * .rms_c * .rms_c
            endif
        endfor

        .blockMS[.bk] = .ms_b
        if .ms_b > 0
            .blockL[.bk] = -0.691 + 10 * log10(.ms_b)
        else
            .blockL[.bk] = -100
        endif

        if .blockL[.bk] >= -70
            .sumMS_abs = .sumMS_abs + .ms_b
            .countAbs = .countAbs + 1
        endif
    endfor

    if .countAbs > 0
        .relGate = -0.691 + 10 * log10(.sumMS_abs / .countAbs) - 10
    else
        .relGate = -70
    endif

    .sumMS_rel = 0
    .countRel = 0
    for .bk from 1 to .nBlocks
        if .blockL[.bk] >= -70 and .blockL[.bk] >= .relGate
            .sumMS_rel = .sumMS_rel + .blockMS[.bk]
            .countRel = .countRel + 1
        endif
    endfor

    if .countRel > 0
        .out_integrated = -0.691 + 10 * log10(.sumMS_rel / .countRel)
    else
        .out_integrated = -70.0
    endif

    # 3. Short-Term LUFS & EBU Tech 3342 LRA (with 1.5s Trailing Silence Padding)
    .stWin = 3.0
    .stHop = 0.1
    
    if .durVal < .stWin
        .out_LRA = -999.0 ; Flag as unavailable for files < 3s
        .maxShortTerm = -999.0
        .numWindows = 0
    else
        # Append 1.5s trailing silence for file-based LRA window alignment
        selectObject: .k_weighted
        .pad = Create Sound from formula: "silence_pad", .nCh, 0, 1.5, .srVal, "0"
        selectObject: .k_weighted
        plusObject: .pad
        .k_padded = Concatenate
        removeObject: .pad
        
        .paddedDur = .durVal + 1.5
        .numWindows = floor((.paddedDur - .stWin) / .stHop) + 1

        .maxShortTerm = -100
        .stSumMS = 0
        .stCount = 0
        for .w from 1 to .numWindows
            .t1 = .pStart + (.w - 1) * .stHop
            .t2 = .t1 + .stWin

            .ms_s = 0
            for .c from 1 to .nCh
                if chWeight[.c] > 0
                    selectObject: .k_padded
                    if .nCh > 1
                        .chSig = Extract one channel: .c
                    else
                        .chSig = .k_padded
                    endif
                    .rms_c = Get root-mean-square: .t1, .t2
                    if .nCh > 1
                        removeObject: .chSig
                    endif
                    .ms_s = .ms_s + chWeight[.c] * .rms_c * .rms_c
                endif
            endfor

            if .ms_s > 0
                .lufs_s = -0.691 + 10 * log10(.ms_s)
            else
                .lufs_s = -100
            endif

            .shortTermLUFS[.w] = .lufs_s
            .shortTermT[.w] = (.t1 + .t2) / 2

            if .lufs_s > .maxShortTerm
                .maxShortTerm = .lufs_s
            endif
            if .lufs_s >= -70
                .stSumMS = .stSumMS + .ms_s
                .stCount = .stCount + 1
            endif
        endfor

        if .stCount > 0
            .stRelGate = -0.691 + 10 * log10(.stSumMS / .stCount) - 20
        else
            .stRelGate = -70
        endif

        .nLRA = 0
        for .w from 1 to .numWindows
            if .shortTermLUFS[.w] >= -70 and .shortTermLUFS[.w] >= .stRelGate
                .nLRA = .nLRA + 1
                .lraVals[.nLRA] = .shortTermLUFS[.w]
            endif
        endfor

        # Insertion sort
        for .i from 2 to .nLRA
            .key = .lraVals[.i]
            .j = .i - 1
            while .j >= 1 and .lraVals[.j] > .key
                .lraVals[.j + 1] = .lraVals[.j]
                .j = .j - 1
            endwhile
            .lraVals[.j + 1] = .key
        endfor

        if .nLRA >= 2
            .loIdx = round((.nLRA - 1) * 0.10 + 1)
            .hiIdx = round((.nLRA - 1) * 0.95 + 1)
            .out_LRA = .lraVals[.hiIdx] - .lraVals[.loIdx]
        else
            .out_LRA = 0.0
        endif
        if .out_LRA < 0
            .out_LRA = 0.0
        endif

        removeObject: .k_padded
    endif

    removeObject: .k_weighted
endproc

# ============================================================
# INPUT MEASUREMENT
# ============================================================

appendInfoLine: "Analyzing input sound..."
@measureTruePeak: input, sourceStart, sourceEnd
inPeak_dB = measureTruePeak.tp_dB
appendInfoLine: "  Input True Peak: ", fixed$(inPeak_dB, 1), " dBTP (Sinc70)"

@analyzeLoudness: input, sourceStart, sourceEnd, sr, nChannels
inIntegrated_LUFS = analyzeLoudness.out_integrated
inLRA = analyzeLoudness.out_LRA
inMaxST = analyzeLoudness.maxShortTerm
numSTWindows = analyzeLoudness.numWindows

for w from 1 to numSTWindows
    stLUFS[w] = analyzeLoudness.shortTermLUFS[w]
    stTime[w] = analyzeLoudness.shortTermT[w]
endfor

appendInfoLine: "  Integrated LUFS: ", fixed$(inIntegrated_LUFS, 1)
if inLRA >= 0
    appendInfoLine: "  Loudness Range (LRA): ", fixed$(inLRA, 1), " LU"
    appendInfoLine: "  Max Short-Term: ", fixed$(inMaxST, 1), " LUFS"
else
    appendInfoLine: "  Loudness Range (LRA): N/A (requires duration >= 3s)"
    appendInfoLine: "  Max Short-Term: N/A (requires duration >= 3s)"
endif
appendInfoLine: ""

# ============================================================
# GAIN & PROCESSING CALCULATIONS
# ============================================================

gainNeeded = target_LUFS - inIntegrated_LUFS
headroom = true_peak_ceiling_dB - inPeak_dB
maxSafeGain = headroom

appendInfoLine: "=== GAIN ANALYSIS ==="
appendInfoLine: "  Target LUFS: ", fixed$(target_LUFS, 1)
appendInfoLine: "  Required Gain: ", fixed$(gainNeeded, 1), " dB"
appendInfoLine: "  Available Headroom: ", fixed$(headroom, 1), " dB"

processed = 0

if mode = 1
    # Analyze Only
    appendInfoLine: ""
    appendInfoLine: "Mode: Analyze Only - No processing applied."
    selectObject: input
    result = input
    
elsif mode = 2
    # Apply Exact Gain (may clip) - Completely Unconstrained
    appendInfoLine: ""
    appendInfoLine: "Mode: Apply Exact Gain (Unconstrained)..."
    selectObject: input
    result = Copy: input$ + "_ExactGain"
    gainLinear = 10 ^ (gainNeeded / 20)
    Formula: ~ self * gainLinear
    appendInfoLine: "  Applied Exact Gain: ", fixed$(gainNeeded, 1), " dB"
    processed = 1

elsif mode = 3
    # Apply Safe Gain (no clipping)
    appendInfoLine: ""
    appendInfoLine: "Mode: Apply Safe Gain..."
    selectObject: input
    result = Copy: input$ + "_SafeGain"
    appliedGain_dB = min(gainNeeded, maxSafeGain)
    gainLinear = 10 ^ (appliedGain_dB / 20)
    Formula: ~ self * gainLinear
    appendInfoLine: "  Applied Safe Gain: ", fixed$(appliedGain_dB, 1), " dB"
    processed = 1

else
    # Normalize to Target (with dynamic limiting and iterative convergence)
    appendInfoLine: ""
    appendInfoLine: "Mode: Normalize to Target (Dynamic Limiting + Iterative Convergence)..."
    selectObject: input
    result = Copy: input$ + "_Normalized"
    
    maxIter = 5
    tolerance = 0.1
    iter = 1
    converged = 0
    current_gain_needed = gainNeeded
    prevRemGain = 999.0
    
    while iter <= maxIter and converged = 0
        gainLinear = 10 ^ (current_gain_needed / 20)
        selectObject: result
        Formula: ~ self * gainLinear
        
        @measureTruePeak: result, sourceStart, sourceEnd
        currTP = measureTruePeak.tp_dB
        
        if currTP > true_peak_ceiling_dB
            @applyLimiter: result, sourceStart, sourceEnd, sr, nChannels, true_peak_ceiling_dB
        endif
        
        @analyzeLoudness: result, sourceStart, sourceEnd, sr, nChannels
        currLUFS = analyzeLoudness.out_integrated
        
        remGain = target_LUFS - currLUFS
        if abs(remGain) <= tolerance
            converged = 1
        else
            if iter > 1 and abs(remGain - prevRemGain) < 0.05
                # Limiter brick-wall reached; no further gain convergence possible
                converged = 0
                iter = maxIter + 1
            else
                prevRemGain = remGain
                current_gain_needed = remGain
                iter = iter + 1
            endif
        endif
    endwhile
    
    if converged = 0 and abs(remGain) > tolerance
        appendInfoLine: "  [WARNING] Target not attainable under the selected true-peak ceiling!"
        appendInfoLine: "    Achieved: ", fixed$(currLUFS, 1), " LUFS | Shortfall: ", fixed$(remGain, 1), " LU"
    else
        appendInfoLine: "  Successfully converged to target within ", string$(min(iter, maxIter)), " iteration(s)."
    endif
    
    processed = 1
endif

# ============================================================
# POST-PROCESSING RE-MEASUREMENT
# ============================================================

if processed
    appendInfoLine: ""
    appendInfoLine: "=== POST-PROCESSING RE-MEASUREMENT ==="
    @measureTruePeak: result, sourceStart, sourceEnd
    outPeak_dB = measureTruePeak.tp_dB
    
    @analyzeLoudness: result, sourceStart, sourceEnd, sr, nChannels
    outIntegrated_LUFS = analyzeLoudness.out_integrated
    outLRA = analyzeLoudness.out_LRA
    outMaxST = analyzeLoudness.maxShortTerm
    outNumSTWindows = analyzeLoudness.numWindows

    for w from 1 to outNumSTWindows
        outStLUFS[w] = analyzeLoudness.shortTermLUFS[w]
    endfor
    
    # Final Safety Verification: Attenuation ONLY for Modes 3 & 4 (Excludes Exact Gain Mode 2)
    if mode <> 1 and mode <> 2
        if outPeak_dB > true_peak_ceiling_dB + 0.001
            safety_atten_dB = outPeak_dB - true_peak_ceiling_dB
            selectObject: result
            Formula: ~ self * (10 ^ (-safety_atten_dB / 20))
            appendInfoLine: "  [Safety Ceiling Adjustment] Applied -", fixed$(safety_atten_dB, 2), " dB attenuation"
            
            # Re-measure
            @measureTruePeak: result, sourceStart, sourceEnd
            outPeak_dB = measureTruePeak.tp_dB
            @analyzeLoudness: result, sourceStart, sourceEnd, sr, nChannels
            outIntegrated_LUFS = analyzeLoudness.out_integrated
            outLRA = analyzeLoudness.out_LRA
        endif
    endif
    
    appendInfoLine: "  Output Integrated LUFS: ", fixed$(outIntegrated_LUFS, 1)
    appendInfoLine: "  Output True Peak: ", fixed$(outPeak_dB, 1), " dBTP"
    if outLRA >= 0
        appendInfoLine: "  Output LRA: ", fixed$(outLRA, 1), " LU"
    else
        appendInfoLine: "  Output LRA: N/A (< 3s duration)"
    endif
else
    outPeak_dB = inPeak_dB
    outIntegrated_LUFS = inIntegrated_LUFS
    outLRA = inLRA
    outNumSTWindows = numSTWindows
    for w from 1 to outNumSTWindows
        outStLUFS[w] = stLUFS[w]
    endfor
endif

# ============================================================
# VISUALIZATION
# ============================================================

if visualize
    appendInfoLine: ""
    appendInfoLine: "Generating analytics display..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.4
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##LUFS Tool v4.1## | Preset: " + presetName$ + " | Target: " + fixed$(target_LUFS, 1) + " LUFS"
    
    # Loudness Meter Bar
    Select outer viewport: 0, 2.5, 0.5, 5.2
    Select inner viewport: 0.6, 2.1, 0.7, 5.0
    
    Axes: 0, 1, -60, 0
    Paint rectangle: "{0.2, 0.6, 0.2}", 0, 1, -60, -24
    Paint rectangle: "{0.6, 0.6, 0.2}", 0, 1, -24, -14
    Paint rectangle: "{0.8, 0.4, 0.2}", 0, 1, -14, -9
    Paint rectangle: "{0.8, 0.2, 0.2}", 0, 1, -9, 0
    
    if outIntegrated_LUFS > -60
        Colour: "{0.3, 0.7, 0.9}"
        Paint rectangle: "{0.3, 0.7, 0.9}", 0.15, 0.5, -60, outIntegrated_LUFS
    endif
    
    Colour: "White"
    Line width: 2
    Draw line: 0, target_LUFS, 1, target_LUFS
    Line width: 1
    
    Colour: "Black"
    Font size: 6
    dbVal = 0
    while dbVal >= -60
        Draw line: 0.85, dbVal, 1, dbVal
        Text: 0.9, "left", dbVal, "half", string$(dbVal)
        dbVal = dbVal - 6
    endwhile
    Draw inner box
    
    Font size: 8
    Select outer viewport: 0.1, 2.5, 0.5, 5.2
    Text left: "yes", "LUFS"
    
    # Input Waveform
    Select outer viewport: 2.6, 8, 0.5, 2.0
    Select inner viewport: 3.0, 7.6, 0.6, 1.9
    selectObject: input
    Colour: "{0.5, 0.5, 0.5}"
    Draw: sourceStart, sourceEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 2.7, 8, 0.5, 2.0
    Text left: "yes", "Input"
    
    # Short-Term LUFS Curve (Input vs Output)
    Select outer viewport: 2.6, 8, 2.1, 3.6
    Select inner viewport: 3.0, 7.6, 2.2, 3.5
    Axes: sourceStart, sourceEnd, -50, 0
    Paint rectangle: "{0.95, 0.95, 0.95}", sourceStart, sourceEnd, -50, 0
    
    Colour: "{0.8, 0.3, 0.3}"
    Dashed line
    Draw line: sourceStart, target_LUFS, sourceEnd, target_LUFS
    Solid line
    
    if duration >= 3.0
        # Draw Input Short-Term (Grey)
        Colour: "{0.6, 0.6, 0.6}"
        Line width: 1
        for w from 2 to numSTWindows
            l1 = stLUFS[w - 1]
            l2 = stLUFS[w]
            if l1 > -60 and l2 > -60
                Draw line: stTime[w - 1], l1, stTime[w], l2
            endif
        endfor

        # Draw Output Short-Term (Blue)
        if processed
            Colour: "{0.2, 0.5, 0.8}"
            Line width: 2
            for w from 2 to outNumSTWindows
                l1 = outStLUFS[w - 1]
                l2 = outStLUFS[w]
                if l1 > -60 and l2 > -60
                    Draw line: stTime[w - 1], l1, stTime[w], l2
                endif
            endfor
        endif
    else
        Font size: 8
        Colour: "Red"
        Text: (sourceStart + sourceEnd) / 2, "centre", -25, "half", "Short-Term / LRA Unavailable (< 3s duration)"
    endif

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 2.7, 8, 2.1, 3.6
    Text left: "yes", "Short-Term"
    
    # Output Waveform
    Select outer viewport: 2.6, 8, 3.7, 5.2
    Select inner viewport: 3.0, 7.6, 3.8, 5.1
    selectObject: result
    Colour: "{0.2, 0.5, 0.3}"
    Draw: sourceStart, sourceEnd, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 2.7, 8, 3.7, 5.2
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Metrics Panel
    Select outer viewport: 0, 8, 5.3, 6.2
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.2, 0.2, 0.2}"
    
    if inLRA >= 0
        lraInStr$ = fixed$(inLRA, 1) + " LU"
    else
        lraInStr$ = "N/A"
    endif
    
    if outLRA >= 0
        lraOutStr$ = fixed$(outLRA, 1) + " LU"
    else
        lraOutStr$ = "N/A"
    endif

    Text: 0.05, "left", 0.75, "half", "Input:  " + fixed$(inIntegrated_LUFS, 1) + " LUFS | " + fixed$(inPeak_dB, 1) + " dBTP | LRA: " + lraInStr$
    Text: 0.05, "left", 0.35, "half", "Output: " + fixed$(outIntegrated_LUFS, 1) + " LUFS | " + fixed$(outPeak_dB, 1) + " dBTP | LRA: " + lraOutStr$
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# SUMMARY & TERMINATION
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  FINAL SUMMARY: ", selected$("Sound")
appendInfoLine: "=============================================="
appendInfoLine: "  Integrated Loudness: ", fixed$(outIntegrated_LUFS, 1), " LUFS"
appendInfoLine: "  True Peak Level:     ", fixed$(outPeak_dB, 1), " dBTP"
if outLRA >= 0
    appendInfoLine: "  Loudness Range:      ", fixed$(outLRA, 1), " LU"
else
    appendInfoLine: "  Loudness Range:      N/A (duration < 3s)"
endif
appendInfoLine: "=============================================="

if play and processed
    appendInfoLine: "Playing result..."
    Play
endif

selectObject: result