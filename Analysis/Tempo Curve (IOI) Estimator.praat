# ============================================================
# Praat AudioTools - Tempo_Curve_IOI_Estimator.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Added presets, visualization, fixed operators
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tempo Curve (IOI) Estimator - Estimates BPM over time from
#   onset intervals using spectral flux or intensity slope detection.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Added presets for different musical styles
#   - Added visualization of tempo curve
#   - Fixed != to <> operators
#   - Added input validation
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Tempo Curve Estimator v0.3
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Pop/Rock (90-180 BPM)
        option Classical (40-120 BPM)
        option Electronic (100-160 BPM)
        option Jazz (60-200 BPM)
        option Slow Ballad (50-80 BPM)
    comment === Tempo Range ===
    positive Min_BPM 60
    positive Max_BPM 180
    comment === Onset Detection ===
    optionmenu Method: 1
        option Spectral flux
        option Intensity slope
    positive Sensitivity 1.5
    comment === Tempo Curve ===
    positive Smoothing_Hz 0.5
    boolean Zero_phase_smoothing 1
    boolean Draw_visualization 1
endform

# Apply presets
if preset = 2
    # Pop/Rock
    min_BPM = 90
    max_BPM = 180
    sensitivity = 1.5
    smoothing_Hz = 0.5
    presetName$ = "Pop/Rock"
elsif preset = 3
    # Classical
    min_BPM = 40
    max_BPM = 120
    sensitivity = 1.2
    smoothing_Hz = 0.3
    presetName$ = "Classical"
elsif preset = 4
    # Electronic
    min_BPM = 100
    max_BPM = 160
    sensitivity = 2.0
    smoothing_Hz = 0.8
    presetName$ = "Electronic"
elsif preset = 5
    # Jazz
    min_BPM = 60
    max_BPM = 200
    sensitivity = 1.3
    smoothing_Hz = 0.4
    presetName$ = "Jazz"
elsif preset = 6
    # Slow Ballad
    min_BPM = 50
    max_BPM = 80
    sensitivity = 1.0
    smoothing_Hz = 0.2
    presetName$ = "SlowBallad"
else
    presetName$ = "Custom"
endif

# Auto-calculate dependent parameters
refractory_period = 60 / max_BPM
window_size = max(4.0, 4 * (60 / min_BPM))
hop_size = window_size / 8

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Tempo Curve Estimator v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Tempo range: ", min_BPM, " - ", max_BPM, " BPM"
appendInfoLine: "Refractory period: ", fixed$(refractory_period, 3), " s"
appendInfoLine: "Window size: ", fixed$(window_size, 2), " s"
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

# === Helper procedure: calculate MAD ===
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

# === Helper procedure: trim array ===
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

# === Resample if needed ===
target_sr = 11025
if sampleRate > target_sr
    appendInfoLine: "Resampling to ", target_sr, " Hz..."
    selectObject: sound
    sound_work = Resample: target_sr, 50
else
    sound_work = sound
endif

# Pre-processing: high-pass filter
selectObject: sound_work
sound_filt = Filter (pass Hann band): 30, 0, 100

# === 1. ONSET DETECTION ===
appendInfoLine: "Detecting onsets..."

if method = 1
    # Spectral Flux method
    selectObject: sound_filt
    
    spectrum = To Spectrogram: 0.03, 4000, 0.005, 20, "Gaussian"
    
    tStart = Get start time
    tStep = Get time step
    
    matrix = To Matrix
    nRows = Get number of rows
    nCols = Get number of columns
    
    nBands = 30
    appendInfoLine: "Processing ", nCols, " frames..."
    
    # Calculate spectral flux
    flux# = zero#(nCols)
    
    for col from 2 to nCols
        diff = 0
        
        for band to nBands
            f_ratio = (band - 1) / (nBands - 1)
            row = floor(1 + (nRows - 1) * (f_ratio ^ 1.5))
            if row > nRows
                row = nRows
            endif
            
            selectObject: matrix
            val_curr = Get value in cell: row, col
            val_prev = Get value in cell: row, col-1
            
            mag_curr = ln(1 + abs(val_curr))
            mag_prev = ln(1 + abs(val_prev))
            
            diff += max(mag_curr - mag_prev, 0)
        endfor
        
        flux#[col] = diff
    endfor
    
    @getMedian: flux#
    flux_median = getMedian.result
    @getMAD: flux#, flux_median
    flux_mad = getMAD.result
    
    window_frames = round(0.5 / tStep)
    
    onsets# = zero#(nCols)
    nOnsets = 0
    last_onset_time = -999
    
    for col from 3 to nCols - 2
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
        
        threshold = local_mean + sensitivity * flux_mad
        
        isMax = 1
        if flux#[col] <= threshold
            isMax = 0
        endif
        
        for offset from -2 to 2
            if offset <> 0 and flux#[col] <= flux#[col + offset]
                isMax = 0
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
    
    removeObject: spectrum, matrix

else
    # Intensity slope method
    selectObject: sound_filt
    
    intensity = To Intensity: 50, 0.01, "yes"
    
    tStart = Get start time
    tStep = Get time step
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
    
    @getMedian: slope#
    slope_median = getMedian.result
    @getMAD: slope#, slope_median
    slope_mad = getMAD.result
    
    window_frames = round(0.5 / tStep)
    
    onsets# = zero#(nFrames)
    nOnsets = 0
    last_onset_time = -999
    
    for i from 3 to nFrames - 2
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
        
        isMax = 1
        if slope#[i] <= threshold
            isMax = 0
        endif
        
        for offset from -2 to 2
            if offset <> 0 and slope#[i] <= slope#[i + offset]
                isMax = 0
            endif
        endfor
        
        if isMax
            t = tStart + (i - 1) * tStep
            
            if t - last_onset_time >= refractory_period
                nOnsets += 1
                onsets#[nOnsets] = t
                last_onset_time = t
            endif
        endif
    endfor
    
    @trimArray: onsets#, nOnsets
    onsets# = trimArray.result#
    
    removeObject: intensity
endif

# Clean up
removeObject: sound_filt
if sound_work <> sound
    removeObject: sound_work
endif

nOnsets = size(onsets#)
appendInfoLine: "Found ", nOnsets, " onsets"

# === 2. CREATE TEXTGRID ===
selectObject: sound
textGrid = To TextGrid: "beats", "beats"

if nOnsets > 0
    for i to nOnsets
        selectObject: textGrid
        Insert point: 1, onsets#[i], "beat"
    endfor
endif

# === 3. CALCULATE BPM CURVE ===
if nOnsets > 1
    appendInfoLine: "Calculating tempo curve..."
    
    # Calculate IOIs
    ioi# = zero#(nOnsets - 1)
    for i to nOnsets - 1
        ioi#[i] = onsets#[i+1] - onsets#[i]
    endfor
    
    # Create time grid
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
        
        if n_window > 0
            @trimArray: window_ioi#, n_window
            window_ioi# = trimArray.result#
            @getMedian: window_ioi#
            median_ioi = getMedian.result
            
            raw_bpm = 60 / median_ioi
            
            # Octave disambiguation
            candidates# = {raw_bpm / 2, raw_bpm, raw_bpm * 2}
            best_bpm = raw_bpm
            best_cost = 999999
            
            for c to 3
                candidate = candidates#[c]
                
                if candidate >= min_BPM and candidate <= max_BPM
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
            bpm#[step] = prev_bpm
        endif
    endfor
    
    # === 4. SMOOTH BPM CURVE ===
    if smoothing_Hz > 0
        appendInfoLine: "Smoothing..."
        
        alpha = 1 - exp(-2 * pi * smoothing_Hz * hop_size)
        if alpha > 1
            alpha = 1
        endif
        if alpha < 0
            alpha = 0
        endif
        
        smoothed# = zero#(nSteps)
        
        if zero_phase_smoothing
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
            # Causal filter
            smoothed#[1] = bpm#[1]
            for i from 2 to nSteps
                smoothed#[i] = smoothed#[i-1] + alpha * (bpm#[i] - smoothed#[i-1])
            endfor
        endif
        
        bpm# = smoothed#
    endif
    
    # === 5. CREATE TABLE ===
    table = Create Table with column names: "TempoCurve_" + soundName$, nSteps, "time bpm confidence"
    
    for i to nSteps
        selectObject: table
        Set numeric value: i, "time", time#[i]
        Set numeric value: i, "bpm", bpm#[i]
        Set numeric value: i, "confidence", confidence#[i]
    endfor
    
    # Calculate statistics
    valid_bpm_sum = 0
    valid_count = 0
    bpm_min = 999
    bpm_max = 0
    for i to nSteps
        if confidence#[i] >= 2
            valid_bpm_sum += bpm#[i]
            valid_count += 1
            if bpm#[i] < bpm_min
                bpm_min = bpm#[i]
            endif
            if bpm#[i] > bpm_max
                bpm_max = bpm#[i]
            endif
        endif
    endfor
    
    if valid_count > 0
        mean_bpm = valid_bpm_sum / valid_count
    else
        mean_bpm = (min_BPM + max_BPM) / 2
        bpm_min = min_BPM
        bpm_max = max_BPM
    endif
    
    # === 6. VISUALIZATION ===
    if draw_visualization
        Erase all
        
        # Title
        Select outer viewport: 0, 8, 0, 0.6
        Font size: 14
        Colour: "Black"
        Text: 0.5, "centre", 0.5, "half", "Tempo Curve: " + soundName$ + " [" + presetName$ + "]"
        
        # Waveform with beat markers
        Select outer viewport: 0, 8, 0.8, 2.5
        Select inner viewport: 0.6, 7.6, 1.0, 2.3
        selectObject: sound
        Colour: "{0.6, 0.6, 0.6}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        
        # Draw beat markers
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
        
        # Tempo curve
        Select outer viewport: 0, 8, 2.7, 5.0
        Select inner viewport: 0.6, 7.6, 2.9, 4.8
        
        # Background
        Axes: 0, duration, min_BPM - 10, max_BPM + 10
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, min_BPM - 10, max_BPM + 10
        
        # BPM range reference lines
        Colour: "{0.8, 0.8, 0.8}"
        Dotted line
        Draw line: 0, min_BPM, duration, min_BPM
        Draw line: 0, max_BPM, duration, max_BPM
        Solid line
        
        # Mean BPM line
        Colour: "{0.5, 0.7, 0.5}"
        Line width: 1
        Dotted line
        Draw line: 0, mean_bpm, duration, mean_bpm
        Solid line
        
        # Tempo curve
        Colour: "{0.2, 0.4, 0.8}"
        Line width: 2
        for i from 2 to nSteps
            Draw line: time#[i-1], bpm#[i-1], time#[i], bpm#[i]
        endfor
        
        # Confidence shading (low confidence = lighter)
        Colour: "{0.8, 0.8, 1.0}"
        for i to nSteps
            if confidence#[i] < 2
                t1 = time#[i] - hop_size/2
                t2 = time#[i] + hop_size/2
                if t1 < 0
                    t1 = 0
                endif
                if t2 > duration
                    t2 = duration
                endif
                Paint rectangle: "{0.9, 0.9, 1.0}", t1, t2, min_BPM - 10, max_BPM + 10
            endif
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "BPM"
        Marks left every: 1, 20, "yes", "yes", "no"
        Marks bottom every: 1, 1, "yes", "yes", "no"
        Text bottom: "yes", "Time (s)"
        
        # Stats
        Select outer viewport: 0, 8, 5.2, 5.8
        Font size: 9
        Colour: "Black"
        statsText$ = "Mean: " + fixed$(mean_bpm, 1) + " BPM | Range: " + fixed$(bpm_min, 1) + "-" + fixed$(bpm_max, 1) + " | Beats: " + string$(nOnsets)
        Text: 0.5, "centre", 0.5, "half", statsText$
        
        Font size: 10
        Line width: 1
    endif
    
    # === OUTPUT ===
    selectObject: textGrid, table
    
    appendInfoLine: ""
    appendInfoLine: "=== RESULTS ==="
    appendInfoLine: "TextGrid: ", nOnsets, " beat points"
    appendInfoLine: "Table: ", nSteps, " tempo estimates"
    if valid_count > 0
        appendInfoLine: "Mean BPM: ", fixed$(mean_bpm, 1)
        appendInfoLine: "Range: ", fixed$(bpm_min, 1), " - ", fixed$(bpm_max, 1), " BPM"
    endif
    appendInfoLine: "Done!"
else
    selectObject: textGrid
    appendInfoLine: ""
    appendInfoLine: "Not enough onsets (need at least 2)."
    appendInfoLine: "Try lowering sensitivity or adjusting tempo range."
endif