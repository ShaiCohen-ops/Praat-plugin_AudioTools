# ============================================================
# Praat AudioTools - Tempo_Curve_IOI_Estimator.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.5 (2025) - Fixed octave doubling
# License: MIT License
#
# Description:
#   Tempo Curve (IOI) Estimator with autocorrelation-based
#   periodicity detection and octave disambiguation.
#
# Changelog v0.5:
#   - Added autocorrelation on ODF for robust period detection
#   - Added "prefer lower BPM" bias for subdivision-heavy material
#   - Fixed octave doubling bug (180 vs 90 BPM)
#   - Added tempo prior weighting
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Tempo Curve Estimator v0.5
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Pop/Rock (90-180 BPM)
        option Classical (40-120 BPM)
        option Electronic (100-160 BPM)
        option Jazz (60-200 BPM)
        option Slow Ballad (50-80 BPM)
        option Fast Metal (140-220 BPM)
    comment === Tempo Range ===
    positive Min_BPM 60
    positive Max_BPM 180
    comment === Detection ===
    optionmenu Method: 1
        option Autocorrelation (recommended)
        option Spectral flux
        option Intensity slope
    positive Sensitivity 1.5
    comment === Octave Preference ===
    optionmenu Tempo_preference: 2
        option Prefer higher BPM (fast subdivisions)
        option Prefer lower BPM (quarter note feel)
        option Neutral (closest to range center)
    comment === Smoothing ===
    positive Smoothing_Hz 0.5
    real Tempo_continuity_weight 0.3
    boolean Zero_phase_smoothing 1
    boolean Draw_visualization 1
endform

# Apply presets
if preset = 2
    min_BPM = 90
    max_BPM = 180
    sensitivity = 1.5
    smoothing_Hz = 0.5
    tempo_continuity_weight = 0.3
    tempo_preference = 2
    presetName$ = "Pop/Rock"
elsif preset = 3
    min_BPM = 40
    max_BPM = 120
    sensitivity = 1.2
    smoothing_Hz = 0.3
    tempo_continuity_weight = 0.4
    tempo_preference = 2
    presetName$ = "Classical"
elsif preset = 4
    min_BPM = 100
    max_BPM = 160
    sensitivity = 2.0
    smoothing_Hz = 0.6
    tempo_continuity_weight = 0.2
    tempo_preference = 2
    presetName$ = "Electronic"
elsif preset = 5
    min_BPM = 60
    max_BPM = 200
    sensitivity = 1.3
    smoothing_Hz = 0.4
    tempo_continuity_weight = 0.3
    tempo_preference = 2
    presetName$ = "Jazz"
elsif preset = 6
    min_BPM = 50
    max_BPM = 80
    sensitivity = 1.0
    smoothing_Hz = 0.2
    tempo_continuity_weight = 0.5
    tempo_preference = 2
    presetName$ = "SlowBallad"
elsif preset = 7
    min_BPM = 140
    max_BPM = 220
    sensitivity = 1.8
    smoothing_Hz = 0.7
    tempo_continuity_weight = 0.2
    tempo_preference = 1
    presetName$ = "FastMetal"
else
    presetName$ = "Custom"
endif

# Calculate dependent parameters
min_period = 60 / max_BPM
max_period = 60 / min_BPM
refractory_period = min_period * 0.4
window_size = max(4.0, 4 * max_period)
hop_size = window_size / 6

# Center of tempo range (for neutral preference)
center_bpm = (min_BPM + max_BPM) / 2

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Tempo Curve Estimator v0.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Tempo range: ", min_BPM, " - ", max_BPM, " BPM"
appendInfoLine: "Period range: ", fixed$(min_period, 3), " - ", fixed$(max_period, 3), " s"
appendInfoLine: "Preference: ", tempo_preference$
appendInfoLine: ""

# === HELPER PROCEDURES ===

procedure getMedian: .data#
    .n = size(.data#)
    if .n = 0
        .result = 0
    elsif .n = 1
        .result = .data#[1]
    else
        .sorted# = sort#(.data#)
        if .n mod 2 = 1
            .result = .sorted#[floor(.n / 2) + 1]
        else
            .result = (.sorted#[.n / 2] + .sorted#[.n / 2 + 1]) / 2
        endif
    endif
endproc

procedure getMAD: .data#, .median
    .n = size(.data#)
    if .n = 0
        .result = 0
    else
        .deviations# = zero#(.n)
        for .i to .n
            .deviations#[.i] = abs(.data#[.i] - .median)
        endfor
        @getMedian: .deviations#
        .result = getMedian.result
    endif
endproc

procedure trimArray: .data#, .newSize
    if .newSize <= 0
        .result# = zero#(0)
    else
        .result# = zero#(.newSize)
        for .i to .newSize
            .result#[.i] = .data#[.i]
        endfor
    endif
endproc

# Score a BPM candidate based on preference
procedure scoreBPM: .bpm, .prev_bpm, .global_bpm
    .score = 0
    
    # 1. Tempo preference bias (KEY FIX for octave errors)
    if tempo_preference = 1
        # Prefer higher BPM - score increases with BPM
        .score += (.bpm - min_BPM) / (max_BPM - min_BPM) * 30
    elsif tempo_preference = 2
        # Prefer lower BPM - score increases as BPM decreases
        .score += (max_BPM - .bpm) / (max_BPM - min_BPM) * 30
    else
        # Neutral - prefer center of range
        .dist = abs(.bpm - center_bpm) / (max_BPM - min_BPM)
        .score += (1 - .dist) * 20
    endif
    
    # 2. Continuity with previous tempo
    if .prev_bpm > 0
        .diff = abs(.bpm - .prev_bpm) / .prev_bpm
        .score -= 50 * .diff * tempo_continuity_weight
    endif
    
    # 3. Consistency with global estimate
    if .global_bpm > 0
        .diff = abs(.bpm - .global_bpm) / .global_bpm
        .score -= 20 * .diff
    endif
    
    .result = .score
endproc

# Find best BPM from a raw estimate considering octaves
procedure findBestBPM: .raw_bpm, .prev_bpm, .global_bpm
    # Generate candidates at different octave relationships
    .n_candidates = 0
    .candidates# = zero#(20)
    
    # Check multipliers: 1/4, 1/3, 1/2, 2/3, 1, 3/2, 2, 3, 4
    .multipliers# = {0.25, 0.333, 0.5, 0.667, 1.0, 1.5, 2.0, 3.0, 4.0}
    
    for .m to 9
        .candidate = .raw_bpm * .multipliers#[.m]
        if .candidate >= min_BPM and .candidate <= max_BPM
            .n_candidates += 1
            .candidates#[.n_candidates] = .candidate
        endif
    endfor
    
    # Score each candidate
    .best_bpm = .raw_bpm
    .best_score = -999999
    
    for .c to .n_candidates
        @scoreBPM: .candidates#[.c], .prev_bpm, .global_bpm
        if scoreBPM.result > .best_score
            .best_score = scoreBPM.result
            .best_bpm = .candidates#[.c]
        endif
    endfor
    
    # Fallback: if nothing in range, clamp raw
    if .n_candidates = 0
        if .raw_bpm < min_BPM
            .best_bpm = min_BPM
        elsif .raw_bpm > max_BPM
            .best_bpm = max_BPM
        else
            .best_bpm = .raw_bpm
        endif
    endif
    
    .result = .best_bpm
endproc

# AUTOCORRELATION-BASED PERIOD DETECTION (key improvement)
procedure findPeriodByAutocorr: .odf#, .n_frames, .t_step
    # Compute autocorrelation of ODF within valid lag range
    .min_lag = floor(min_period / .t_step)
    .max_lag = ceiling(max_period / .t_step)
    
    if .max_lag > .n_frames / 2
        .max_lag = floor(.n_frames / 2)
    endif
    if .min_lag < 1
        .min_lag = 1
    endif
    
    .n_lags = .max_lag - .min_lag + 1
    if .n_lags < 3
        .result = (min_period + max_period) / 2
    else
        .acf# = zero#(.n_lags)
        
        # Compute mean for normalization
        .sum = 0
        for .i to .n_frames
            .sum += .odf#[.i]
        endfor
        .mean = .sum / .n_frames
        
        # Compute variance
        .var_sum = 0
        for .i to .n_frames
            .var_sum += (.odf#[.i] - .mean) ^ 2
        endfor
        .variance = .var_sum / .n_frames
        if .variance < 0.0001
            .variance = 0.0001
        endif
        
        # Compute normalized autocorrelation
        for .l to .n_lags
            .lag = .min_lag + .l - 1
            .sum = 0
            .count = 0
            for .i to .n_frames - .lag
                .sum += (.odf#[.i] - .mean) * (.odf#[.i + .lag] - .mean)
                .count += 1
            endfor
            if .count > 0
                .acf#[.l] = .sum / (.count * .variance)
            endif
        endfor
        
        # Find peaks in ACF
        .best_lag_idx = 1
        .best_val = .acf#[1]
        
        for .l from 2 to .n_lags - 1
            # Check if local maximum
            if .acf#[.l] > .acf#[.l-1] and .acf#[.l] > .acf#[.l+1]
                # Apply tempo preference weighting
                .lag = .min_lag + .l - 1
                .period = .lag * .t_step
                .bpm = 60 / .period
                
                .weighted_val = .acf#[.l]
                
                # Boost based on preference
                if tempo_preference = 1
                    # Prefer higher BPM = shorter period = smaller lag
                    .weighted_val *= (1 + 0.3 * (1 - (.l - 1) / .n_lags))
                elsif tempo_preference = 2
                    # Prefer lower BPM = longer period = larger lag
                    .weighted_val *= (1 + 0.3 * ((.l - 1) / .n_lags))
                endif
                
                if .weighted_val > .best_val
                    .best_val = .weighted_val
                    .best_lag_idx = .l
                endif
            endif
        endfor
        
        # Parabolic interpolation for sub-sample accuracy
        if .best_lag_idx > 1 and .best_lag_idx < .n_lags
            .y0 = .acf#[.best_lag_idx - 1]
            .y1 = .acf#[.best_lag_idx]
            .y2 = .acf#[.best_lag_idx + 1]
            .denom = .y0 - 2 * .y1 + .y2
            if abs(.denom) > 0.0001
                .offset = 0.5 * (.y0 - .y2) / .denom
            else
                .offset = 0
            endif
            .refined_idx = .best_lag_idx + .offset
        else
            .refined_idx = .best_lag_idx
        endif
        
        .best_lag = .min_lag + .refined_idx - 1
        .result = .best_lag * .t_step
    endif
endproc

# IOI histogram method (backup)
procedure findPeriodByHistogram: .ioi#, .n_ioi
    if .n_ioi < 2
        .result = (min_period + max_period) / 2
    else
        .n_bins = 80
        .bin_width = (max_period - min_period) / .n_bins
        .hist# = zero#(.n_bins)
        .sigma = .bin_width * 1.5
        
        for .i to .n_ioi
            .period = .ioi#[.i]
            
            # Add IOI and its multiples/divisions
            for .mult_idx to 5
                if .mult_idx = 1
                    .p = .period
                    .weight = 1.0
                elsif .mult_idx = 2
                    .p = .period * 2
                    .weight = 0.6
                elsif .mult_idx = 3
                    .p = .period / 2
                    .weight = 0.6
                elsif .mult_idx = 4
                    .p = .period * 3
                    .weight = 0.3
                else
                    .p = .period / 3
                    .weight = 0.3
                endif
                
                if .p >= min_period and .p <= max_period
                    .bin = floor((.p - min_period) / .bin_width) + 1
                    if .bin >= 1 and .bin <= .n_bins
                        for .b from max(1, .bin - 2) to min(.n_bins, .bin + 2)
                            .dist = abs(.b - .bin) * .bin_width
                            .g = exp(-0.5 * (.dist / .sigma) ^ 2) * .weight
                            .hist#[.b] += .g
                        endfor
                    endif
                endif
            endfor
        endfor
        
        # Apply tempo preference weighting to histogram
        for .b to .n_bins
            .period = min_period + (.b - 0.5) * .bin_width
            .bpm = 60 / .period
            
            if tempo_preference = 1
                # Prefer higher BPM = boost shorter periods
                .hist#[.b] *= (1 + 0.4 * (1 - (.b - 1) / .n_bins))
            elsif tempo_preference = 2
                # Prefer lower BPM = boost longer periods
                .hist#[.b] *= (1 + 0.4 * ((.b - 1) / .n_bins))
            endif
        endfor
        
        # Find peak
        .max_val = 0
        .max_bin = floor(.n_bins / 2)
        for .b to .n_bins
            if .hist#[.b] > .max_val
                .max_val = .hist#[.b]
                .max_bin = .b
            endif
        endfor
        
        # Parabolic refinement
        if .max_bin > 1 and .max_bin < .n_bins
            .y0 = .hist#[.max_bin - 1]
            .y1 = .hist#[.max_bin]
            .y2 = .hist#[.max_bin + 1]
            .denom = .y0 - 2 * .y1 + .y2
            if abs(.denom) > 0.0001
                .offset = 0.5 * (.y0 - .y2) / .denom
            else
                .offset = 0
            endif
            .refined_bin = .max_bin + .offset
        else
            .refined_bin = .max_bin
        endif
        
        .result = min_period + (.refined_bin - 0.5) * .bin_width
    endif
endproc

# === RESAMPLE IF NEEDED ===
target_sr = 11025
if sampleRate > target_sr
    appendInfoLine: "Resampling to ", target_sr, " Hz..."
    selectObject: sound
    sound_work = Resample: target_sr, 50
else
    sound_work = sound
endif

# Pre-processing
selectObject: sound_work
sound_filt = Filter (pass Hann band): 50, 8000, 100

# === 1. COMPUTE ONSET DETECTION FUNCTION ===
appendInfoLine: "Computing onset detection function..."

selectObject: sound_filt

if method = 1 or method = 2
    # Spectral flux based ODF
    spec = To Spectrogram: 0.023, 8000, 0.005, 20, "Gaussian"
    tStart = Get start time
    tStep = Get time step
    mat = To Matrix
    nRows = Get number of rows
    nCols = Get number of columns
    
    odf# = zero#(nCols)
    
    # Multi-band with weighting
    band_edges# = {0, 80, 250, 500, 2000, 4000, 8000}
    band_weights# = {0.6, 1.2, 1.0, 0.9, 0.7, 0.5}
    
    for col from 2 to nCols
        flux = 0
        for band to 6
            f_low = band_edges#[band]
            f_high = band_edges#[band + 1]
            row_low = max(1, round(f_low / 8000 * nRows))
            row_high = min(nRows, round(f_high / 8000 * nRows))
            
            band_flux = 0
            for row from row_low to row_high
                selectObject: mat
                v_curr = Get value in cell: row, col
                v_prev = Get value in cell: row, col - 1
                band_flux += max(0, v_curr - v_prev)
            endfor
            flux += band_flux * band_weights#[band]
        endfor
        odf#[col] = flux
    endfor
    
    removeObject: spec, mat
else
    # Intensity slope
    intensity = To Intensity: 50, 0.005, "yes"
    tStart = Get start time
    tStep = Get time step
    nCols = Get number of frames
    
    int_raw# = zero#(nCols)
    for i to nCols
        selectObject: intensity
        t = Get time from frame number: i
        int_raw#[i] = Get value at time: t, "Cubic"
        if int_raw#[i] = undefined
            int_raw#[i] = 0
        endif
    endfor
    
    # Median filter
    int_filt# = zero#(nCols)
    for i from 3 to nCols - 2
        vals# = {int_raw#[i-2], int_raw#[i-1], int_raw#[i], int_raw#[i+1], int_raw#[i+2]}
        vals# = sort#(vals#)
        int_filt#[i] = vals#[3]
    endfor
    int_filt#[1] = int_raw#[1]
    int_filt#[2] = int_raw#[2]
    int_filt#[nCols-1] = int_raw#[nCols-1]
    int_filt#[nCols] = int_raw#[nCols]
    
    odf# = zero#(nCols)
    for i from 2 to nCols
        odf#[i] = max(0, int_filt#[i] - int_filt#[i-1])
    endfor
    
    removeObject: intensity
endif

# === 2. GLOBAL TEMPO ESTIMATION ===
appendInfoLine: "Estimating global tempo..."

if method = 1
    # Autocorrelation method
    @findPeriodByAutocorr: odf#, nCols, tStep
    global_period = findPeriodByAutocorr.result
else
    # Need to detect onsets first for histogram method
    global_period = (min_period + max_period) / 2
endif

global_bpm_raw = 60 / global_period

# Apply octave disambiguation to global estimate
@findBestBPM: global_bpm_raw, 0, 0
global_bpm = findBestBPM.result

appendInfoLine: "Raw period: ", fixed$(global_period, 3), " s (", fixed$(global_bpm_raw, 1), " BPM)"
appendInfoLine: "Adjusted global BPM: ", fixed$(global_bpm, 1)

# === 3. ONSET PEAK PICKING ===
appendInfoLine: "Detecting onsets..."

@getMedian: odf#
odf_median = getMedian.result
@getMAD: odf#, odf_median
odf_mad = getMAD.result
if odf_mad < 0.0001
    odf_mad = 0.0001
endif

window_frames = round(0.25 / tStep)
if window_frames < 2
    window_frames = 2
endif

onsets# = zero#(nCols)
nOnsets = 0
last_onset_time = -999

for col from 4 to nCols - 3
    local_sum = 0
    local_count = 0
    for offset from -window_frames to window_frames
        idx = col + offset
        if idx >= 1 and idx <= nCols
            local_sum += odf#[idx]
            local_count += 1
        endif
    endfor
    local_mean = local_sum / local_count
    
    threshold = local_mean + sensitivity * odf_mad
    
    isMax = 1
    if odf#[col] <= threshold
        isMax = 0
    endif
    
    for offset from -3 to 3
        if offset <> 0 and col + offset >= 1 and col + offset <= nCols
            if odf#[col] <= odf#[col + offset]
                isMax = 0
            endif
        endif
    endfor
    
    if isMax
        t = tStart + (col - 1) * tStep
        if t - last_onset_time >= refractory_period
            nOnsets += 1
            onsets#[nOnsets] = t
            last_onset_time = t
        endif
    endif
endfor

@trimArray: onsets#, nOnsets
onsets# = trimArray.result#

removeObject: sound_filt
if sound_work <> sound
    removeObject: sound_work
endif

appendInfoLine: "Found ", nOnsets, " onsets"

# === 4. CREATE TEXTGRID ===
selectObject: sound
textGrid = To TextGrid: "beats", "beats"

if nOnsets > 0
    for i to nOnsets
        selectObject: textGrid
        Insert point: 1, onsets#[i], "beat"
    endfor
endif

# === 5. CALCULATE BPM CURVE ===
if nOnsets > 2
    appendInfoLine: "Calculating tempo curve..."
    
    # Calculate IOIs
    ioi# = zero#(nOnsets - 1)
    for i to nOnsets - 1
        ioi#[i] = onsets#[i+1] - onsets#[i]
    endfor
    
    # If using histogram method, refine global estimate
    if method <> 1
        @findPeriodByHistogram: ioi#, nOnsets - 1
        global_period = findPeriodByHistogram.result
        global_bpm_raw = 60 / global_period
        @findBestBPM: global_bpm_raw, 0, 0
        global_bpm = findBestBPM.result
        appendInfoLine: "Refined global BPM: ", fixed$(global_bpm, 1)
    endif
    
    # Time grid
    nSteps = floor((duration - window_size) / hop_size) + 1
    if nSteps < 1
        nSteps = 1
    endif
    
    time# = zero#(nSteps)
    bpm# = zero#(nSteps)
    confidence# = zero#(nSteps)
    
    prev_bpm = global_bpm
    
    for step to nSteps
        t_center = (step - 1) * hop_size + window_size / 2
        time#[step] = t_center
        
        t_start = t_center - window_size / 2
        t_end = t_center + window_size / 2
        
        # Collect IOIs in window
        window_ioi# = zero#(nOnsets)
        n_window = 0
        
        for i to nOnsets - 1
            if onsets#[i] >= t_start and onsets#[i+1] <= t_end
                n_window += 1
                window_ioi#[n_window] = ioi#[i]
            endif
        endfor
        
        confidence#[step] = n_window
        
        if n_window >= 2
            @trimArray: window_ioi#, n_window
            window_ioi# = trimArray.result#
            
            @findPeriodByHistogram: window_ioi#, n_window
            local_period = findPeriodByHistogram.result
            raw_bpm = 60 / local_period
            
            @findBestBPM: raw_bpm, prev_bpm, global_bpm
            bpm#[step] = findBestBPM.result
            prev_bpm = bpm#[step]
        elsif n_window = 1
            raw_bpm = 60 / window_ioi#[1]
            @findBestBPM: raw_bpm, prev_bpm, global_bpm
            bpm#[step] = findBestBPM.result
            prev_bpm = bpm#[step]
        else
            bpm#[step] = prev_bpm
        endif
    endfor
    
    # === 6. MEDIAN PRE-FILTER ===
    if nSteps >= 5
        filtered# = zero#(nSteps)
        for i from 3 to nSteps - 2
            vals# = {bpm#[i-2], bpm#[i-1], bpm#[i], bpm#[i+1], bpm#[i+2]}
            vals# = sort#(vals#)
            filtered#[i] = vals#[3]
        endfor
        filtered#[1] = bpm#[1]
        filtered#[2] = bpm#[2]
        filtered#[nSteps-1] = bpm#[nSteps-1]
        filtered#[nSteps] = bpm#[nSteps]
        bpm# = filtered#
    endif
    
    # === 7. SMOOTH ===
    if smoothing_Hz > 0
        alpha = 1 - exp(-2 * pi * smoothing_Hz * hop_size)
        alpha = min(1, max(0, alpha))
        
        smoothed# = zero#(nSteps)
        
        if zero_phase_smoothing
            smoothed#[1] = bpm#[1]
            for i from 2 to nSteps
                smoothed#[i] = smoothed#[i-1] + alpha * (bpm#[i] - smoothed#[i-1])
            endfor
            for i from nSteps - 1 to 1
                smoothed#[i] = smoothed#[i+1] + alpha * (smoothed#[i] - smoothed#[i+1])
            endfor
        else
            smoothed#[1] = bpm#[1]
            for i from 2 to nSteps
                smoothed#[i] = smoothed#[i-1] + alpha * (bpm#[i] - smoothed#[i-1])
            endfor
        endif
        
        bpm# = smoothed#
    endif
    
    # === 8. CREATE TABLE ===
    table = Create Table with column names: "TempoCurve_" + soundName$, nSteps, "time bpm confidence"
    
    for i to nSteps
        selectObject: table
        Set numeric value: i, "time", time#[i]
        Set numeric value: i, "bpm", bpm#[i]
        Set numeric value: i, "confidence", confidence#[i]
    endfor
    
    # Statistics
    valid_bpm# = zero#(nSteps)
    valid_count = 0
    for i to nSteps
        if confidence#[i] >= 2
            valid_count += 1
            valid_bpm#[valid_count] = bpm#[i]
        endif
    endfor
    
    if valid_count > 0
        @trimArray: valid_bpm#, valid_count
        valid_bpm# = trimArray.result#
        @getMedian: valid_bpm#
        median_bpm = getMedian.result
        
        bpm_sum = 0
        bpm_min = 999
        bpm_max = 0
        for i to valid_count
            bpm_sum += valid_bpm#[i]
            if valid_bpm#[i] < bpm_min
                bpm_min = valid_bpm#[i]
            endif
            if valid_bpm#[i] > bpm_max
                bpm_max = valid_bpm#[i]
            endif
        endfor
        mean_bpm = bpm_sum / valid_count
    else
        mean_bpm = global_bpm
        median_bpm = global_bpm
        bpm_min = min_BPM
        bpm_max = max_BPM
    endif
    
    # === 9. VISUALIZATION ===
    if draw_visualization
        Erase all
        
        Select outer viewport: 0, 8, 0, 0.6
        Font size: 14
        Colour: "Black"
        Text: 0.5, "centre", 0.5, "half", "Tempo Curve: " + soundName$ + " [" + presetName$ + "]"
        
        Select outer viewport: 0, 8, 0.8, 2.5
        Select inner viewport: 0.6, 7.6, 1.0, 2.3
        selectObject: sound
        Colour: "{0.6, 0.6, 0.6}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        selectObject: sound
        ampMax = Get maximum: 0, 0, "Sinc70"
        ampMin = Get minimum: 0, 0, "Sinc70"
        
        Colour: "{0.8, 0.2, 0.2}"
        Line width: 1
        for i to nOnsets
            Draw line: onsets#[i], ampMin, onsets#[i], ampMax
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Waveform"
        Marks bottom every: 1, 1, "yes", "yes", "no"
        
        Select outer viewport: 0, 8, 2.7, 5.0
        Select inner viewport: 0.6, 7.6, 2.9, 4.8
        
        Axes: 0, duration, min_BPM - 10, max_BPM + 10
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, min_BPM - 10, max_BPM + 10
        
        Colour: "{0.85, 0.85, 0.85}"
        Dotted line
        Draw line: 0, min_BPM, duration, min_BPM
        Draw line: 0, max_BPM, duration, max_BPM
        Solid line
        
        Colour: "{0.4, 0.7, 0.4}"
        Line width: 1.5
        Dotted line
        Draw line: 0, median_bpm, duration, median_bpm
        Solid line
        
        for i to nSteps
            if confidence#[i] < 2
                t1 = max(0, time#[i] - hop_size/2)
                t2 = min(duration, time#[i] + hop_size/2)
                Paint rectangle: "{0.92, 0.92, 0.98}", t1, t2, min_BPM - 10, max_BPM + 10
            endif
        endfor
        
        Colour: "{0.2, 0.4, 0.8}"
        Line width: 2
        for i from 2 to nSteps
            Draw line: time#[i-1], bpm#[i-1], time#[i], bpm#[i]
        endfor
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 8
        Text left: "yes", "BPM"
        Marks left every: 1, 20, "yes", "yes", "no"
        Marks bottom every: 1, 1, "yes", "yes", "no"
        Text bottom: "yes", "Time (s)"
        
        Select outer viewport: 0, 8, 5.2, 5.8
        Font size: 9
        Colour: "Black"
        Text: 0.5, "centre", 0.5, "half", "Median: " + fixed$(median_bpm, 1) + " BPM | Mean: " + fixed$(mean_bpm, 1) + " | Range: " + fixed$(bpm_min, 1) + "-" + fixed$(bpm_max, 1) + " | Beats: " + string$(nOnsets)
        
        Font size: 10
        Line width: 1
    endif
    
    selectObject: textGrid, table
    
    appendInfoLine: ""
    appendInfoLine: "=== RESULTS ==="
    appendInfoLine: "Median BPM: ", fixed$(median_bpm, 1)
    appendInfoLine: "Mean BPM: ", fixed$(mean_bpm, 1)
    appendInfoLine: "Range: ", fixed$(bpm_min, 1), " - ", fixed$(bpm_max, 1)
    appendInfoLine: "Beats: ", nOnsets
    appendInfoLine: "Done!"
else
    selectObject: textGrid
    appendInfoLine: ""
    appendInfoLine: "Not enough onsets (need at least 3)."
endif