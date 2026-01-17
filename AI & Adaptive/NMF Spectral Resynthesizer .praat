# ============================================================
# Praat AudioTools - NMF_Spectral_Resynthesizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   NMF Spectral Resynthesizer - Decomposes spectrogram via
#   Non-negative Matrix Factorization for creative resynthesis.
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Added preset name to output
#   - Added visualization
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

id_original = selected("Sound")
name_original$ = selected$("Sound")

form NMF Spectral Resynthesizer v0.4
    optionmenu Preset: 1
        option Manual
        option Fast Preview
        option Smooth Gliss
        option Clicks
        option Texture
        option High Definition
    comment === Analysis Window ===
    positive Window_ms 10
    positive Step_ms 4.0
    comment === Smoothing ===
    positive Trans_decay 0.6
    integer Texture_blur_passes 4
    comment === Pitch Tracking ===
    positive Min_pitch 75
    positive Max_pitch 600
    positive Pitch_smoothing_hz 10
    comment === NMF Engine ===
    natural Max_freq_hz 4000
    integer N_components 4
    integer N_iterations 8
    comment === Output ===
    boolean Stereo_output 1
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Fast Preview
    window_ms = 15
    step_ms = 8.0
    trans_decay = 0.5
    texture_blur_passes = 2
    max_freq_hz = 3000
    n_components = 2
    n_iterations = 4
    presetName$ = "FastPreview"
elsif preset = 3
    # Smooth Gliss
    window_ms = 2.0
    step_ms = 50.0
    trans_decay = 0.9
    texture_blur_passes = 1
    max_freq_hz = 4000
    n_components = 3
    n_iterations = 10
    presetName$ = "SmoothGliss"
elsif preset = 4
    # Clicks
    window_ms = 60.0
    step_ms = 15.0
    trans_decay = 0.4
    texture_blur_passes = 5
    max_freq_hz = 5000
    n_components = 5
    n_iterations = 8
    presetName$ = "Clicks"
elsif preset = 5
    # Texture
    window_ms = 1.0
    step_ms = 2.0
    trans_decay = 0.5
    texture_blur_passes = 2
    max_freq_hz = 4000
    n_components = 4
    n_iterations = 8
    presetName$ = "Texture"
elsif preset = 6
    # High Definition
    window_ms = 8
    step_ms = 3.0
    trans_decay = 0.6
    texture_blur_passes = 3
    max_freq_hz = 6000
    n_components = 6
    n_iterations = 15
    presetName$ = "HighDefinition"
else
    presetName$ = "Manual"
endif

# ============================================
# SETUP
# ============================================

clearinfo
writeInfoLine: "=== NMF Spectral Resynthesizer v0.4 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Window: ", window_ms, " ms | Step: ", step_ms, " ms"
appendInfoLine: "Components: ", n_components, " | Iterations: ", n_iterations
appendInfoLine: "Decay: ", trans_decay, " | Blur passes: ", texture_blur_passes
if stereo_output
    appendInfoLine: "Output: Stereo (shared W, independent H)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

selectObject: id_original
sampling_rate = Get sampling frequency
duration = Get total duration
original_channels = Get number of channels

if original_channels > 1
    id_mono = Convert to mono
    Rename: name_original$ + "_mono"
else
    id_mono = Copy: name_original$ + "_mono"
endif

# ============================================
# SPECTROGRAM & INIT
# ============================================

appendInfoLine: "Creating spectrogram..."

selectObject: id_mono
spectrogram = To Spectrogram: window_ms/1000, max_freq_hz, step_ms/1000, 20, "Gaussian"
selectObject: spectrogram
matV = To Matrix
Rename: "NMF_V"
Formula: "self + 1e-9"
nRows = Get number of rows
nCols = Get number of columns

appendInfoLine: "  Matrix size: ", nRows, " x ", nCols

matW = Create simple Matrix: "NMF_W", nRows, n_components, "randomUniform(0.1, 1)"
matH = Create simple Matrix: "NMF_H", n_components, nCols, "randomUniform(0.1, 1)"

# Store IDs for Formula references
matV_id$ = string$(matV)
matW_id$ = string$(matW)
matH_id$ = string$(matH)

# ============================================
# PRE-ALLOCATE TEMPORARY MATRICES
# ============================================

matNum_H = Create simple Matrix: "Num_H", n_components, nCols, "0"
matWtW = Create simple Matrix: "WtW", n_components, n_components, "0"
matDenom_H = Create simple Matrix: "Denom_H", n_components, nCols, "0"

matNum_W = Create simple Matrix: "Num_W", nRows, n_components, "0"
matHHt = Create simple Matrix: "HHt", n_components, n_components, "0"
matDenom_W = Create simple Matrix: "Denom_W", nRows, n_components, "0"

matNum_H_id$ = string$(matNum_H)
matWtW_id$ = string$(matWtW)
matDenom_H_id$ = string$(matDenom_H)
matNum_W_id$ = string$(matNum_W)
matHHt_id$ = string$(matHHt)
matDenom_W_id$ = string$(matDenom_W)

# ============================================
# NMF LOOP
# ============================================

appendInfoLine: "Decomposing (", n_iterations, " iterations)..."

for iter from 1 to n_iterations
    appendInfo: "."
    
    # --- UPDATE H ---
    # Compute Num_H = W' * V
    selectObject: matNum_H
    Formula: "0"
    for k from 1 to nRows
        k_str$ = fixed$(k, 0)
        selectObject: matNum_H
        Formula: "self + Object_" + matW_id$ + "[" + k_str$ + ", row] * Object_" + matV_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Compute WtW = W' * W
    selectObject: matWtW
    Formula: "0"
    for k from 1 to nRows
        k_str$ = fixed$(k, 0)
        selectObject: matWtW
        Formula: "self + Object_" + matW_id$ + "[" + k_str$ + ", row] * Object_" + matW_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Compute Denom_H = WtW * H
    selectObject: matDenom_H
    Formula: "0"
    for k from 1 to n_components
        k_str$ = fixed$(k, 0)
        selectObject: matDenom_H
        Formula: "self + Object_" + matWtW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Update H
    selectObject: matH
    Formula: "self * Object_" + matNum_H_id$ + "[row,col] / (Object_" + matDenom_H_id$ + "[row,col] + 1e-9)"

    # --- UPDATE W ---
    # Compute Num_W = V * H'
    selectObject: matNum_W
    Formula: "0"
    for k from 1 to nCols
        k_str$ = fixed$(k, 0)
        selectObject: matNum_W
        Formula: "self + Object_" + matV_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[col, " + k_str$ + "]"
    endfor
    
    # Compute HHt = H * H'
    selectObject: matHHt
    Formula: "0"
    for k from 1 to nCols
        k_str$ = fixed$(k, 0)
        selectObject: matHHt
        Formula: "self + Object_" + matH_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[col, " + k_str$ + "]"
    endfor
    
    # Compute Denom_W = W * HHt
    selectObject: matDenom_W
    Formula: "0"
    for k from 1 to n_components
        k_str$ = fixed$(k, 0)
        selectObject: matDenom_W
        Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matHHt_id$ + "[" + k_str$ + ", col]"
    endfor
    
    # Update W
    selectObject: matW
    Formula: "self * Object_" + matNum_W_id$ + "[row,col] / (Object_" + matDenom_W_id$ + "[row,col] + 1e-9)"
endfor

appendInfoLine: " done"

removeObject: matNum_H, matWtW, matDenom_H, matNum_W, matHHt, matDenom_W

# ============================================
# DUAL-MODE SMOOTHING
# ============================================

appendInfoLine: "Applying smoothing..."

selectObject: matH

if trans_decay > 0
    Formula: "if row <= 2 and col > 1 then (self * (1-trans_decay)) + (self[row, col-1] * trans_decay) else self fi"
endif

for i from 1 to texture_blur_passes
    Formula: "if row > 2 and col > 1 and col < ncol then (self[row, col-1]*0.25 + self*0.5 + self[row, col+1]*0.25) else self fi"
endfor

# ============================================
# RECONSTRUCT SPECTROGRAM
# ============================================

appendInfoLine: "Reconstructing spectrogram..."

selectObject: matV
matRecon = Copy: "V_Recon"
matRecon_id$ = string$(matRecon)
Formula: "0"

for k from 1 to n_components
    k_str$ = fixed$(k, 0)
    selectObject: matRecon
    Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
endfor

# ============================================
# RESYNTHESIS
# ============================================

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

appendInfoLine: "Extracting pitch contour..."
selectObject: id_mono
pitchOrig = To Pitch: 0.0, min_pitch, max_pitch
pitchSmooth = Smooth: pitch_smoothing_hz
pitchTier = Down to PitchTier
removeObject: pitchOrig, pitchSmooth

for pass from 1 to n_passes
    if stereo_output
        if pass = 1
            appendInfoLine: "Synthesizing LEFT channel..."
        else
            appendInfoLine: "Synthesizing RIGHT channel..."
            
            selectObject: matH
            Formula: "self * randomUniform(0.85, 1.15)"
            
            if trans_decay > 0
                Formula: "if row <= 2 and col > 1 then (self * (1-trans_decay)) + (self[row, col-1] * trans_decay) else self fi"
            endif
            for i from 1 to texture_blur_passes
                Formula: "if row > 2 and col > 1 and col < ncol then (self[row, col-1]*0.25 + self*0.5 + self[row, col+1]*0.25) else self fi"
            endfor
            
            selectObject: matRecon
            Formula: "0"
            for k from 1 to n_components
                k_str$ = fixed$(k, 0)
                selectObject: matRecon
                Formula: "self + Object_" + matW_id$ + "[row, " + k_str$ + "] * Object_" + matH_id$ + "[" + k_str$ + ", col]"
            endfor
        endif
    else
        appendInfoLine: "Synthesizing..."
    endif
    
    selectObject: matRecon
    specRecon = To Spectrogram
    selectObject: specRecon
    soundRecon = To Sound: sampling_rate
    Rename: "NMF_Raw_" + string$(pass)
    
    selectObject: soundRecon
    manipulation = To Manipulation: 0.01, min_pitch, max_pitch
    selectObject: manipulation
    plusObject: pitchTier
    Replace pitch tier
    
    selectObject: manipulation
    soundPitched = Get resynthesis (overlap-add)
    
    removeObject: manipulation, soundRecon, specRecon
    
    if pass = 1
        channel_left = soundPitched
        selectObject: channel_left
        Rename: "Channel_Left"
    else
        channel_right = soundPitched
        selectObject: channel_right
        Rename: "Channel_Right"
    endif
endfor

removeObject: pitchTier

# ============================================
# COMBINE STEREO / FINALIZE
# ============================================

if stereo_output
    appendInfoLine: "Combining to stereo..."
    
    selectObject: channel_left
    dur_left = Get total duration
    
    selectObject: channel_right
    dur_right = Get total duration
    
    if dur_left < dur_right
        selectObject: channel_right
        channel_right_trim = Extract part: 0, dur_left, "rectangular", 1.0, "no"
        removeObject: channel_right
        channel_right = channel_right_trim
    elsif dur_right < dur_left
        selectObject: channel_left
        channel_left_trim = Extract part: 0, dur_right, "rectangular", 1.0, "no"
        removeObject: channel_left
        channel_left = channel_left_trim
    endif
    
    selectObject: channel_left
    plusObject: channel_right
    soundFinal = Combine to stereo
    Rename: name_original$ + "_NMF_" + presetName$
    
    removeObject: channel_left, channel_right
else
    soundFinal = channel_left
    Rename: name_original$ + "_NMF_" + presetName$
endif

selectObject: soundFinal
Scale peak: 0.99

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "NMF Spectral Resynthesizer: " + name_original$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: id_original
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: soundFinal
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # W matrix (basis vectors) - as heatmap
    Select outer viewport: 0, 4, 2.7, 4.2
    Select inner viewport: 0.6, 3.6, 2.9, 4.1
    
    selectObject: matW
    wRows = Get number of rows
    wCols = Get number of columns
    
    # Find max for normalization
    wMax = 0
    for r from 1 to wRows
        for c from 1 to wCols
            selectObject: matW
            val = Get value in cell: r, c
            if val > wMax
                wMax = val
            endif
        endfor
    endfor
    if wMax < 0.001
        wMax = 1
    endif
    
    Axes: 0, wCols, 0, wRows
    
    # Draw W heatmap (downsample if too large)
    step_r = max(1, floor(wRows / 50))
    r = 1
    while r <= wRows
        for c from 1 to wCols
            selectObject: matW
            val = Get value in cell: r, c
            intensity = val / wMax
            rVal$ = fixed$(1 - intensity * 0.8, 2)
            gVal$ = fixed$(1 - intensity * 0.5, 2)
            bVal$ = fixed$(1 - intensity * 0.2, 2)
            Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", c - 1, c, wRows - r, wRows - r + step_r
        endfor
        r += step_r
    endwhile
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "W (Basis)"
    Text bottom: "yes", "Component"
    
    # H matrix (activations) - as lines over time
    Select outer viewport: 4, 8, 2.7, 4.2
    Select inner viewport: 4.4, 7.6, 2.9, 4.1
    
    selectObject: matH
    hRows = Get number of rows
    hCols = Get number of columns
    
    # Find max
    hMax = 0
    for r from 1 to hRows
        for c from 1 to hCols
            selectObject: matH
            val = Get value in cell: r, c
            if val > hMax
                hMax = val
            endif
        endfor
    endfor
    if hMax < 0.001
        hMax = 1
    endif
    
    Axes: 0, duration, 0, hMax * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, hMax * 1.1
    
    # Draw each component as a line
    for comp from 1 to hRows
        colorVal = comp / hRows
        rVal$ = fixed$(0.2 + colorVal * 0.6, 2)
        gVal$ = fixed$(0.6 - colorVal * 0.3, 2)
        bVal$ = fixed$(0.8 - colorVal * 0.5, 2)
        Colour: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}"
        
        for c from 2 to hCols
            t1 = (c - 2) * step_ms / 1000
            t2 = (c - 1) * step_ms / 1000
            selectObject: matH
            v1 = Get value in cell: comp, c - 1
            v2 = Get value in cell: comp, c
            Draw line: t1, v1, t2, v2
        endfor
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "H (Activ)"
    Text bottom: "yes", "Time (s)"
    
    # Stats box
    Select outer viewport: 0, 8, 4.4, 5.0
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.2, "centre", 0.5, "half", "Window: " + string$(window_ms) + " ms"
    Text: 0.4, "centre", 0.5, "half", "Step: " + string$(step_ms) + " ms"
    Text: 0.6, "centre", 0.5, "half", "Components: " + string$(n_components)
    Text: 0.8, "centre", 0.5, "half", "Iterations: " + string$(n_iterations)
    
    Font size: 10
    Colour: "Black"
endif

# ============================================
# CLEANUP
# ============================================

removeObject: spectrogram, matV, matW, matH, matRecon, id_mono

# ============================================
# OUTPUT
# ============================================

selectObject: id_original
plusObject: soundFinal

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: soundFinal
n_ch = Get number of channels
dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "Channels: ", n_ch

if play_output
    appendInfoLine: "Playing..."
    selectObject: soundFinal
    Play
endif

selectObject: soundFinal