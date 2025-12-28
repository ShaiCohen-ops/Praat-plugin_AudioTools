# ============================================================
# Praat AudioTools - Partial Editing & Resynthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2025)
# License: MIT License
#
# Description:
#   SPEAR-like sinusoidal analysis-resynthesis. Extracts
#   frequency peaks frame-by-frame and resynthesizes with
#   pure sine waves. Creates clean, synthetic textures from
#   any sound. Jitter parameters add organic variation.
#   Can transpose pitch and shift formants independently.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Sinusoidal Texture Resynthesis
    optionmenu Preset: 1
        option Custom
        option Clean Resynth (faithful recreation)
        option Diffuse Texture (jittery, organic)
        option Sparse Partials (minimal, hollow)
        option Dense Partials (rich, full)
        option Pitch Up Octave
        option Pitch Down Octave
        option Formant Shift Up (chipmunk)
        option Formant Shift Down (giant)
        option Glassy Shimmer (high jitter)
        option Robotic (no jitter, precise)
        option Whisper Ghost (sparse, diffuse)
    comment === Synthesis Parameters ===
    positive window_length 0.060
    positive hop_size 0.015
    positive min_frequency 60
    positive max_frequency 8000
    integer max_partials_per_frame 15
    comment === Diffusion & Texture ===
    positive freq_jitter 3.0
    real amp_jitter 0.1
    comment === Pitch/Formant ===
    real transpose_semitones 0
    real formant_shift_ratio 1.0
    comment === Quality ===
    choice Processing_quality: 2
        button High (original rate - slow)
        button Medium (22050 Hz - fast)
        button Low (11025 Hz - very fast)
    boolean play_result 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Clean Resynth
    freq_jitter = 0.5
    amp_jitter = 0.02
    max_partials_per_frame = 20
elsif preset = 3
    # Diffuse Texture
    freq_jitter = 8.0
    amp_jitter = 0.3
    max_partials_per_frame = 15
elsif preset = 4
    # Sparse Partials
    max_partials_per_frame = 5
    freq_jitter = 2.0
    amp_jitter = 0.1
elsif preset = 5
    # Dense Partials
    max_partials_per_frame = 30
    freq_jitter = 1.0
    amp_jitter = 0.05
elsif preset = 6
    # Pitch Up Octave
    transpose_semitones = 12
    freq_jitter = 1.0
    amp_jitter = 0.05
elsif preset = 7
    # Pitch Down Octave
    transpose_semitones = -12
    freq_jitter = 1.0
    amp_jitter = 0.05
elsif preset = 8
    # Formant Shift Up
    formant_shift_ratio = 1.5
    freq_jitter = 2.0
    amp_jitter = 0.1
elsif preset = 9
    # Formant Shift Down
    formant_shift_ratio = 0.7
    freq_jitter = 2.0
    amp_jitter = 0.1
elsif preset = 10
    # Glassy Shimmer
    freq_jitter = 15.0
    amp_jitter = 0.4
    max_partials_per_frame = 20
    max_frequency = 12000
elsif preset = 11
    # Robotic
    freq_jitter = 0.0
    amp_jitter = 0.0
    max_partials_per_frame = 12
elsif preset = 12
    # Whisper Ghost
    max_partials_per_frame = 4
    freq_jitter = 10.0
    amp_jitter = 0.5
    max_frequency = 6000
endif

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound."
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
t1 = Get start time
t2 = Get end time
dur = t2 - t1

writeInfoLine: "=== Sinusoidal Texture Resynthesis ==="
appendInfoLine: "Partials: ", max_partials_per_frame
appendInfoLine: "Freq jitter: ", freq_jitter, " Hz"
appendInfoLine: "Amp jitter: ", amp_jitter
appendInfoLine: "Transpose: ", transpose_semitones, " semitones"
appendInfoLine: "Formant ratio: ", formant_shift_ratio
appendInfoLine: ""

# Prepare working copy
selectObject: orig_id
input_id = Copy: "input"

# Handle quality/speed resampling
if processing_quality = 2
    Resample: 22050, 50
    temp_id = selected("Sound")
    removeObject: input_id
    input_id = temp_id
elsif processing_quality = 3
    Resample: 11025, 50
    temp_id = selected("Sound")
    removeObject: input_id
    input_id = temp_id
endif

selectObject: input_id
work_sr = Get sampling frequency
nyq = work_sr / 2
totdur = Get total duration

# Create output buffer
output_id = Create Sound from formula: "resynth", 1, 0, totdur, work_sr, "0"

# Constants
tr = 2 ^ (transpose_semitones / 12)
fr = formant_shift_ratio
nframes = floor((totdur - window_length) / hop_size)

# Suppression width
approx_bin_width = 1 / window_length
suppress_hz = 40
suppress_bins = round(suppress_hz / approx_bin_width)
if suppress_bins < 1
    suppress_bins = 1
endif

appendInfoLine: "Processing ", nframes, " frames..."

# === FRAME LOOP ===
for i from 0 to nframes - 1
    if (i mod 50) = 0
        perc = i / nframes * 100
        appendInfoLine: "Progress: ", fixed$(perc, 0), "%"
    endif

    # Time calculations
    tc = i * hop_size + window_length/2
    t_start = tc - window_length/2
    t_end = tc + window_length/2
    
    if t_start < 0
        t_start = 0
    endif
    if t_end > totdur
        t_end = totdur
    endif
    current_win_dur = t_end - t_start

    # A. EXTRACT FRAME
    selectObject: input_id
    frame_id = Extract part: t_start, t_end, "hanning", 1, "yes"
    
    # B. ANALYZE
    spec_id = To Spectrum: "yes"
    selectObject: spec_id
    mat_id = To Matrix
    
    # Calculate magnitude in row 1
    Formula: "if row = 1 then sqrt(self^2 + self[2,col]^2) else 0 fi"
    
    nc = Get number of columns
    freq_step = nyq / (nc - 1)

    # C. MASK FREQUENCY RANGE
    col_min = round(min_frequency / freq_step) + 1
    col_max = round(max_frequency / freq_step) + 1
    if col_min < 1
        col_min = 1
    endif
    if col_max > nc
        col_max = nc
    endif
    
    Formula: "if col < " + string$(col_min) + " or col > " + string$(col_max) + " then 0 else self fi"

    # D. CREATE GRAIN
    Create Sound from formula: "grain", 1, 0, current_win_dur, work_sr, "0"
    grain_id = selected("Sound")
    Shift times to: "start time", t_start
    
    # E. FIND PEAKS & SYNTHESIZE
    for k from 1 to max_partials_per_frame
        selectObject: mat_id
        
        # Find maximum
        current_max_val = -1
        current_max_col = -1
        
        for c from col_min to col_max
            val = Get value in cell: 1, c
            if val > current_max_val
                current_max_val = val
                current_max_col = c
            endif
        endfor
        
        if current_max_val > 0.000001
            freq_hz = (current_max_col - 1) * freq_step
            
            # Apply jitter
            amp_rand = randomUniform(1.0 - amp_jitter, 1.0 + amp_jitter)
            amp_linear = (current_max_val * amp_rand) / (window_length * work_sr / 4)
            
            freq_rand = randomUniform(-freq_jitter, freq_jitter)
            freq_target = (freq_hz + freq_rand) * tr * fr
            
            if freq_target < nyq and freq_target > 20
                selectObject: grain_id
                s_amp$ = fixed$(amp_linear, 6)
                s_freq$ = fixed$(freq_target, 2)
                Formula: "self + " + s_amp$ + " * sin(2*pi*" + s_freq$ + "*x)"
            endif
            
            # Suppress this peak
            selectObject: mat_id
            sup_c1 = current_max_col - suppress_bins
            sup_c2 = current_max_col + suppress_bins
            Formula: "if col >= " + string$(sup_c1) + " and col <= " + string$(sup_c2) + " then 0 else self fi"
        else
            k = max_partials_per_frame
        endif
    endfor
    
    # F. APPLY HANNING WINDOW (click-free)
    selectObject: grain_id
    s_start$ = fixed$(t_start, 6)
    s_dur$ = fixed$(current_win_dur, 6)
    Formula: "self * 0.5 * (1 - cos(2*pi * (x - " + s_start$ + ") / " + s_dur$ + "))"
    
    # G. ADD TO OUTPUT
    selectObject: output_id
    s_grain_id$ = string$(grain_id)
    s_end$ = fixed$(t_end, 6)
    Formula: "if x >= " + s_start$ + " and x <= " + s_end$ + " then self + object(" + s_grain_id$ + ", x) else self fi"
    
    removeObject: frame_id, spec_id, mat_id, grain_id
endfor

# === FINALIZE ===
selectObject: output_id
Rename: orig_name$ + "_resynth"
Scale intensity: 70

# Restore original sample rate
if work_sr <> orig_sr
    appendInfoLine: "Restoring sample rate..."
    resampled_id = Resample: orig_sr, 50
    removeObject: output_id
    output_id = resampled_id
    selectObject: output_id
    Rename: orig_name$ + "_resynth"
endif

removeObject: input_id

appendInfoLine: ""
appendInfoLine: "Complete!"

selectObject: output_id
if play_result
    Play
endif