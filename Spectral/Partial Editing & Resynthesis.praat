# ============================================================
# Praat AudioTools - Partial_Editing___Resynthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025) - Fixed syntax, added visualization
# License: MIT License
#
# Description:
#   SPEAR-like sinusoidal analysis-resynthesis. Extracts
#   frequency peaks frame-by-frame and resynthesizes with
#   pure sine waves.
# ============================================================

form Sinusoidal Texture Resynthesis v0.3
    optionmenu Preset: 1
        option Custom
        option Clean Resynth (faithful)
        option Diffuse Texture (jittery)
        option Sparse Partials (hollow)
        option Dense Partials (rich)
        option Pitch Up Octave
        option Pitch Down Octave
        option Formant Shift Up (chipmunk)
        option Formant Shift Down (giant)
        option Glassy Shimmer
        option Robotic (precise)
        option Whisper Ghost
    comment === Synthesis Parameters ===
    positive Window_length 0.060
    positive Hop_size 0.015
    positive Min_frequency 60
    positive Max_frequency 8000
    integer Max_partials_per_frame 15
    comment === Diffusion & Texture ===
    positive Freq_jitter 3.0
    real Amp_jitter 0.1
    comment === Pitch/Formant ===
    real Transpose_semitones 0
    real Formant_shift_ratio 1.0
    comment === Quality ===
    choice Processing_quality: 2
        button High (original rate)
        button Medium (22050 Hz)
        button Low (11025 Hz)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === APPLY PRESETS ===
if preset = 2
    freq_jitter = 0.5
    amp_jitter = 0.02
    max_partials_per_frame = 20
    presetName$ = "CleanResynth"
elsif preset = 3
    freq_jitter = 8.0
    amp_jitter = 0.3
    max_partials_per_frame = 15
    presetName$ = "DiffuseTexture"
elsif preset = 4
    max_partials_per_frame = 5
    freq_jitter = 2.0
    amp_jitter = 0.1
    presetName$ = "SparsePartials"
elsif preset = 5
    max_partials_per_frame = 30
    freq_jitter = 1.0
    amp_jitter = 0.05
    presetName$ = "DensePartials"
elsif preset = 6
    transpose_semitones = 12
    freq_jitter = 1.0
    amp_jitter = 0.05
    presetName$ = "PitchUpOctave"
elsif preset = 7
    transpose_semitones = -12
    freq_jitter = 1.0
    amp_jitter = 0.05
    presetName$ = "PitchDownOctave"
elsif preset = 8
    formant_shift_ratio = 1.5
    freq_jitter = 2.0
    amp_jitter = 0.1
    presetName$ = "FormantUp"
elsif preset = 9
    formant_shift_ratio = 0.7
    freq_jitter = 2.0
    amp_jitter = 0.1
    presetName$ = "FormantDown"
elsif preset = 10
    freq_jitter = 15.0
    amp_jitter = 0.4
    max_partials_per_frame = 20
    max_frequency = 12000
    presetName$ = "GlassyShimmer"
elsif preset = 11
    freq_jitter = 0.0
    amp_jitter = 0.0
    max_partials_per_frame = 12
    presetName$ = "Robotic"
elsif preset = 12
    max_partials_per_frame = 4
    freq_jitter = 10.0
    amp_jitter = 0.5
    max_frequency = 6000
    presetName$ = "WhisperGhost"
else
    presetName$ = "Custom"
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

clearinfo
writeInfoLine: "=== Sinusoidal Texture Resynthesis v0.3 ==="
appendInfoLine: "Input: ", orig_name$
appendInfoLine: "Duration: ", fixed$(dur, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
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
    Formula: "if row = 1 then sqrt(self^2 + self[2,col]^2) else 0 endif"
    
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
    
    Formula: "if col < " + string$(col_min) + " or col > " + string$(col_max) + " then 0 else self endif"

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
            Formula: "if col >= " + string$(sup_c1) + " and col <= " + string$(sup_c2) + " then 0 else self endif"
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
    Formula: "if x >= " + s_start$ + " and x <= " + s_end$ + " then self + object(" + s_grain_id$ + ", x) else self endif"
    
    removeObject: frame_id, spec_id, mat_id, grain_id
endfor

# === FINALIZE ===
selectObject: output_id
Rename: orig_name$ + "_resynth_" + presetName$
Scale intensity: 70

# Restore original sample rate
if work_sr <> orig_sr
    appendInfoLine: "Restoring sample rate..."
    resampled_id = Resample: orig_sr, 50
    removeObject: output_id
    output_id = resampled_id
    selectObject: output_id
    Rename: orig_name$ + "_resynth_" + presetName$
endif

removeObject: input_id

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Sinusoidal Resynthesis: " + orig_name$ + " [" + presetName$ + "]"
    
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: orig_id
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: output_id
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Resynthesized"
    
    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: orig_id
    origSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: output_id
    resSpecID = To Spectrogram: 0.01, 5000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Resynthesized Spectrogram"
    removeObject: resSpecID
    
    Select outer viewport: 0, 8, 4.0, 4.6
    Select inner viewport: 0.5, 7.7, 4.05, 4.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Partials: " + string$(max_partials_per_frame)
    Text: 0.18, "left", 0.5, "half", "Jitter: " + fixed$(freq_jitter, 1) + " Hz"
    Text: 0.38, "left", 0.5, "half", "Transpose: " + fixed$(transpose_semitones, 0)
    Text: 0.55, "left", 0.5, "half", "Formant: " + fixed$(formant_shift_ratio, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", orig_name$, "_resynth_", presetName$

selectObject: orig_id
plusObject: output_id

if play_result
    selectObject: output_id
    Play
endif