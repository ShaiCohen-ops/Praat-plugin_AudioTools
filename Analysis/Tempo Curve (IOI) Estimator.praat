# ============================================================
# Praat AudioTools - Tempo Curve (IOI) Estimator.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tempo Curve (IOI) Estimator
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Replaced O(n²) bubble sort with built-in sort#() for major performance improvement
#   - Added zero-phase smoothing option for offline analysis
#   - Fixed naming: local_mean (was incorrectly called local_median)
# ============================================================

# Tempo Curve (IOI) Estimator 
# Estimates BPM over time from onset intervals
# Outputs: TextGrid (beats) + Table (time, BPM curve)

form Tempo Curve Estimator
    comment Tempo Range
    positive Min_BPM 60
    positive Max_BPM 180
    comment Onset Detection
    optionmenu Method 1
        option Spectral flux
        option Intensity slope
    positive Sensitivity 1.5
    comment Tempo Curve Settings
    positive Smoothing_(Hz) 0.5
    boolean Zero_phase_smoothing 1
endform

# Auto-calculate dependent parameters
refractory_period = 60 / max_BPM
window_size = max(4.0, 4 * (60 / min_BPM))
hop_size = window_size / 8

# Get selected sound
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency

writeInfoLine: "=== Tempo Curve Estimator ==="
appendInfoLine: "Refractory period: ", fixed$(refractory_period, 3), " s"
appendInfoLine: "Window size: ", fixed$(window_size, 2), " s"
appendInfoLine: "Hop size: ", fixed$(hop_size, 2), " s"
appendInfoLine: ""

# === Helper procedure: calculate median from array ===
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

# === Helper procedure: calculate MAD (Median Absolute Deviation) ===
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

# === Helper procedure: trim array to size ===
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

# === OPTIMIZATION: Resample if needed ===
target_sr = 11025
if sampleRate > target_sr
    appendInfoLine: "Resampling to ", target_sr, " Hz..."
    selectObject: sound
    sound_work = Resample: target_sr, 50
else
    sound_work = sound
endif

# Pre-processing: high-pass filter to remove DC and rumble
selectObject: sound_work
sound_filt = Filter (pass Hann band): 30, 0, 100

# === 1. ONSET DETECTION ===
appendInfoLine: "Detecting onsets..."

if method = 1
    # Spectral Flux method - IMPROVED
    selectObject: sound_filt
    
    # Spectrogram with good time resolution
    spectrum = To Spectrogram: 0.03, 4000, 0.005, 20, "Gaussian"
    
    # Get time properties
    tStart = Get start time
    tStep = Get time step
    
    matrix = To Matrix
    
    # Get matrix dimensions
    nRows = Get number of rows
    nCols = Get number of columns
    
    # Use log-spaced frequency sampling for better perceptual weighting
    nBands = 30
    
    appendInfoLine: "Processing ", nCols, " frames with ", nBands, " log-spaced bands..."
    
    # Calculate spectral flux with log compression
    flux# = zero#(nCols)
    
    for col from 2 to nCols
        diff = 0
        
        # Log-spaced frequency bands
        for band to nBands
            # Exponential spacing: more resolution at low freqs
            f_ratio = (band - 1) / (nBands - 1)
            row = floor(1 + (nRows - 1) * (f_ratio ^ 1.5))
            if row > nRows
                row = nRows
            endif
            
            selectObject: matrix
            val_curr = Get value in cell: row, col
            val_prev = Get value in cell: row, col-1
            
            # Log compression to reduce loudness variance
            mag_curr = ln(1 + abs(val_curr))
            mag_prev = ln(1 + abs(val_prev))
            
            # Spectral flux = sum of positive differences
            diff += max(mag_curr - mag_prev, 0)
        endfor
        
        flux#[col] = diff
    endfor
    
    # Calculate median and MAD using optimized procedures
    @getMedian: flux#
    flux_median = getMedian.result
    @getMAD: flux#, flux_median
    flux_mad = getMAD.result
    
    # Adaptive threshold per frame (local mean in ~0.5s window)
    window_frames = round(0.5 / tStep)
    
    # Peak picking with adaptive threshold + refractory period
    onsets# = zero#(nCols)
    nOnsets = 0
    last_onset_time = -999
    
    for col from 3 to nCols - 2
        # Calculate local mean (for computational efficiency)
        local_sum = 0
        local_count = 0
        for offset from -window_frames to window_frames
            idx = col + offset
            if idx >= 1 and idx <= nCols
                local_sum += flux#[idx]
                local_count += 1
            endif
        endfor
        local_mean = local_sum / local_count
        
        # Adaptive threshold: local mean + sensitivity * MAD
        threshold = local_mean + sensitivity * flux_mad
        
        # Check if local maximum above threshold
        isMax = 1
        if flux#[col] <= threshold
            isMax = 0
        endif
        
        for offset from -2 to 2
            if offset != 0 and flux#[col] <= flux#[col + offset]
                isMax = 0
            endif
        endfor
        
        if isMax
            # Calculate time
            t = tStart + (col - 1) * tStep
            
            # Refractory period check
            if t - last_onset_time >= refractory_period
                nOnsets += 1
                onsets#[nOnsets] = t
                last_onset_time = t
            endif
        endif
    endfor
    
    # Trim to actual size
    @trimArray: onsets#, nOnsets
    onsets# = trimArray.result#
    
    removeObject: spectrum, matrix

else
    # Intensity slope method - IMPROVED
    selectObject: sound_filt
    
    intensity = To Intensity: 50, 0.01, "yes"
    
    # Get time properties
    tStart = Get start time
    tStep = Get time step
    
    # Apply median filtering to intensity
    nFrames = Get number of frames
    int_raw# = zero#(nFrames)
    
    for i to nFrames
        selectObject: intensity
        t = Get time from frame number: i
        int_raw#[i] = Get value at time: t, "Cubic"
        if int_raw#[i] = undefined
            int_raw#[i] = 0
        endif
    endfor
    
    # Median filter (3-point)
    int_filt# = zero#(nFrames)
    for i from 2 to nFrames - 1
        vals# = {int_raw#[i-1], int_raw#[i], int_raw#[i+1]}
        vals# = sort#(vals#)
        int_filt#[i] = vals#[2]
    endfor
    int_filt#[1] = int_raw#[1]
    int_filt#[nFrames] = int_raw#[nFrames]
    
    # Calculate slope
    slope# = zero#(nFrames)
    for i from 2 to nFrames
        slope#[i] = int_filt#[i] - int_filt#[i-1]
    endfor
    
    # Calculate median and MAD using optimized procedures
    @getMedian: slope#
    slope_median = getMedian.result
    @getMAD: slope#, slope_median
    slope_mad = getMAD.result
    
    # Adaptive peak picking with refractory period
    window_frames = round(0.5 / tStep)
    
    onsets# = zero#(nFrames)
    nOnsets = 0
    last_onset_time = -999
    
    for i from 3 to nFrames - 2
        # Local mean (for computational efficiency)
        local_sum = 0
        local_count = 0
        for offset from -window_frames to window_frames
            idx = i + offset
            if idx >= 1 and idx <= nFrames
                local_sum += slope#[idx]
                local_count += 1
            endif
        endfor
        local_mean = local_sum / local_count
        
        threshold = local_mean + sensitivity * slope_mad
        
        # Check if local maximum
        isMax = 1
        if slope#[i] <= threshold
            isMax = 0
        endif
        
        for offset from -2 to 2
            if offset != 0 and slope#[i] <= slope#[i + offset]
                isMax = 0
            endif
        endfor
        
        if isMax
            t = tStart + (i - 1) * tStep
            
            # Refractory period
            if t - last_onset_time >= refractory_period
                nOnsets += 1
                onsets#[nOnsets] = t
                last_onset_time = t
            endif
        endif
    endfor
    
    # Trim to actual size
    @trimArray: onsets#, nOnsets
    onsets# = trimArray.result#
    
    removeObject: intensity
endif

# Clean up
removeObject: sound_filt
if sound_work != sound
    removeObject: sound_work
endif

nOnsets = size(onsets#)
appendInfoLine: "Found ", nOnsets, " onsets"

# === 2. CREATE TEXTGRID WITH BEATS ===
selectObject: sound
textGrid = To TextGrid: "beats", "beats"

if nOnsets > 0
    for i to nOnsets
        selectObject: textGrid
        Insert point: 1, onsets#[i], "beat"
    endfor
endif

# === 3. CALCULATE IOI AND BPM CURVE WITH CONTINUITY ===
if nOnsets > 1
    appendInfoLine: "Calculating tempo curve..."
    
    # Calculate inter-onset intervals
    ioi# = zero#(nOnsets - 1)
    for i to nOnsets - 1
        ioi#[i] = onsets#[i+1] - onsets#[i]
    endfor
    
    # Create time grid for BPM curve
    nSteps = floor((duration - window_size) / hop_size) + 1
    if nSteps < 1
        nSteps = 1
    endif
    
    time# = zero#(nSteps)
    bpm# = zero#(nSteps)
    confidence# = zero#(nSteps)
    
    prev_bpm = (min_BPM + max_BPM) / 2
    
    for step to nSteps
        t_center = (step - 1) * hop_size + window_size / 2
        time#[step] = t_center
        
        # Find onsets in window
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
        
        # Store confidence (number of IOIs)
        confidence#[step] = n_window
        
        if n_window > 0
            # Trim and calculate median using optimized procedure
            @trimArray: window_ioi#, n_window
            window_ioi# = trimArray.result#
            @getMedian: window_ioi#
            median_ioi = getMedian.result
            
            # Convert to BPM
            raw_bpm = 60 / median_ioi
            
            # Test octave candidates (½×, 1×, 2×)
            candidates# = {raw_bpm / 2, raw_bpm, raw_bpm * 2}
            best_bpm = raw_bpm
            best_cost = 999999
            
            for c to 3
                candidate = candidates#[c]
                
                # Clamp to valid range
                if candidate >= min_BPM and candidate <= max_BPM
                    # Continuity cost: prefer candidates close to previous BPM
                    cost = abs(candidate - prev_bpm)
                    
                    if cost < best_cost
                        best_cost = cost
                        best_bpm = candidate
                    endif
                endif
            endfor
            
            bpm#[step] = best_bpm
            prev_bpm = best_bpm
        else
            # No onsets in window
            bpm#[step] = prev_bpm
        endif
    endfor
    
    # === 4. SMOOTH BPM CURVE ===
    if smoothing > 0
        appendInfoLine: "Smoothing tempo curve..."
        
        # One-pole low-pass coefficient
        alpha = 1 - exp(-2 * pi * smoothing * hop_size)
        if alpha > 1
            alpha = 1
        endif
        if alpha < 0
            alpha = 0
        endif
        
        smoothed# = zero#(nSteps)
        
        if zero_phase_smoothing
            # Zero-phase filtering (forward-backward) for offline analysis
            # Forward pass
            smoothed#[1] = bpm#[1]
            for i from 2 to nSteps
                smoothed#[i] = smoothed#[i-1] + alpha * (bpm#[i] - smoothed#[i-1])
            endfor
            
            # Backward pass
            for i from nSteps - 1 to 1
                smoothed#[i] = smoothed#[i+1] + alpha * (smoothed#[i] - smoothed#[i+1])
            endfor
        else
            # Causal one-pole filter
            smoothed#[1] = bpm#[1]
            for i from 2 to nSteps
                smoothed#[i] = smoothed#[i-1] + alpha * (bpm#[i] - smoothed#[i-1])
            endfor
        endif
        
        bpm# = smoothed#
    endif
    
    # === 5. CREATE OUTPUT TABLE ===
    table = Create Table with column names: "TempoCurve_" + soundName$, nSteps, "time bpm confidence"
    
    for i to nSteps
        selectObject: table
        Set numeric value: i, "time", time#[i]
        Set numeric value: i, "bpm", bpm#[i]
        Set numeric value: i, "confidence", confidence#[i]
    endfor
    
    # === 6. OUTPUT ===
    selectObject: textGrid, table
    
    # Calculate mean BPM excluding low-confidence regions
    valid_bpm_sum = 0
    valid_count = 0
    for i to nSteps
        if confidence#[i] >= 2
            valid_bpm_sum += bpm#[i]
            valid_count += 1
        endif
    endfor
    
    appendInfoLine: ""
    appendInfoLine: "=== RESULTS ==="
    appendInfoLine: "TextGrid: ", nOnsets, " beat points"
    appendInfoLine: "Table: ", nSteps, " tempo estimates"
    if valid_count > 0
        appendInfoLine: "Mean BPM (confident regions): ", fixed$(valid_bpm_sum / valid_count, 1)
    endif
    appendInfoLine: "Done!"
else
    selectObject: textGrid
    appendInfoLine: ""
    appendInfoLine: "Not enough onsets detected (need at least 2)."
    appendInfoLine: "Try lowering sensitivity or adjusting tempo range."
endif