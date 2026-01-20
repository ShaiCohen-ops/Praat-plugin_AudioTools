# ============================================================
# Praat AudioTools - Self-Similarity_Matrix_Calculator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2025) - Optimized Visualization Engine
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Computes and visualizes self-similarity matrix from audio
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Self-Similarity Matrix v1.3
    optionmenu Feature: 3
        option Pitch (fast)
        option Pitch + Intensity
        option MFCC (recommended)
        option Spectral Entropy
        option LPC (formants)
        option Mel Bands
    comment === Analysis ===
    positive Time_step 0.01
    integer Frame_skip 1
    comment (1=all, 2=every 2nd, etc.)
    comment === Visualization ===
    optionmenu Color_scheme: 2
        option Grayscale
        option Heat (black-red-yellow-white)
        option Viridis (blue-green-yellow)
        option Plasma (purple-red-yellow)
        option Inverted Grayscale
    boolean Auto_contrast 1
    real Gamma 1.0
endform

# ============================================================
# FIXED PARAMETERS
# ============================================================

pitch_floor = 75
pitch_ceiling = 600
number_of_mfcc = 12
num_freq_bands = 40
lpc_order = 16
num_mel_bands = 40
window_length = 0.025

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
original_duration = Get total duration
original_sr = Get sampling frequency
num_channels = Get number of channels

if feature = 1
    feature_name$ = "Pitch"
elsif feature = 2
    feature_name$ = "Pitch+Int"
elsif feature = 3
    feature_name$ = "MFCC"
elsif feature = 4
    feature_name$ = "Entropy"
elsif feature = 5
    feature_name$ = "LPC"
else
    feature_name$ = "Mel"
endif

clearinfo
writeInfoLine: "=== Self-Similarity Matrix v1.3 ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Feature: ", feature_name$
appendInfoLine: ""

# ============================================================
# PREPROCESSING
# ============================================================

workingID = originalID

if num_channels > 1
    selectObject: originalID
    workingID = Convert to mono
endif

if original_sr > 22050
    selectObject: workingID
    tempID = workingID
    workingID = Resample: 22050, 50
    if tempID <> originalID
        removeObject: tempID
    endif
endif

# ============================================================
# EXTRACT FEATURES
# ============================================================

appendInfo: "Extracting features..."
selectObject: workingID

if feature = 1
    # PITCH
    pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
    total_frames = Get number of frames
    num_frames = ceiling(total_frames / frame_skip)
    num_features = 1
    
    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")
    
    selectObject: pitchID
    out_f = 0
    for i from 1 to total_frames
        if (i - 1) mod frame_skip = 0
            out_f = out_f + 1
            val = Get value in frame: i, "Hertz"
            if val = undefined
                val = 0
            endif
            selectObject: featureMatrixID
            Set value: out_f, 1, val
            selectObject: pitchID
        endif
    endfor
    removeObject: pitchID

elsif feature = 2
    # PITCH + INTENSITY
    pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
    selectObject: workingID
    intID = To Intensity: pitch_floor, time_step, "yes"
    
    selectObject: pitchID
    total_frames = Get number of frames
    num_frames = ceiling(total_frames / frame_skip)
    num_features = 2
    
    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")
    
    out_f = 0
    for i from 1 to total_frames
        if (i - 1) mod frame_skip = 0
            out_f = out_f + 1
            selectObject: pitchID
            pval = Get value in frame: i, "Hertz"
            if pval = undefined
                pval = 0
            endif
            selectObject: intID
            ival = Get value in frame: i
            if ival = undefined
                ival = 0
            endif
            selectObject: featureMatrixID
            Set value: out_f, 1, pval
            Set value: out_f, 2, ival
        endif
    endfor
    removeObject: pitchID, intID

elsif feature = 3
    # MFCC
    mfccID = To MFCC: number_of_mfcc, window_length, time_step, 100, 100, 0
    total_frames = Get number of frames
    num_frames = ceiling(total_frames / frame_skip)
    num_features = number_of_mfcc
    
    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")
    
    selectObject: mfccID
    out_f = 0
    for i from 1 to total_frames
        if (i - 1) mod frame_skip = 0
            out_f = out_f + 1
            for c from 1 to num_features
                val = Get value in frame: i, c
                selectObject: featureMatrixID
                Set value: out_f, c, val
                selectObject: mfccID
            endfor
        endif
    endfor
    removeObject: mfccID

elsif feature = 4
    # SPECTRAL ENTROPY (Universal Matrix - Optimized)
    selectObject: workingID
    sr = Get sampling frequency
    nyquist = sr / 2
    
    # 1. Create Spectrogram
    # (Standard window_length 0.025 gives good frequency resolution)
    specID = To Spectrogram: window_length, nyquist, time_step, 20, "Gaussian"
    
    # 2. Convert to Matrix (The robust fix)
    selectObject: specID
    matID = To Matrix
    
    selectObject: matID
    ny = Get number of rows
    nx = Get number of columns
    
    # OPTIMIZATION: Pre-calculate the normalization constant
    # We do this once here, instead of doing division 10,000 times inside the loop.
    if ny > 1
        scale_factor = 1 / ln(ny)
    else
        scale_factor = 0
    endif
    
    num_frames = ceiling(nx / frame_skip)
    num_features = 1
    
    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")
    
    selectObject: matID
    out_f = 0
    
    # Loop through Time (Columns)
    for i from 1 to nx
        if (i - 1) mod frame_skip = 0
            out_f = out_f + 1
            
            # PASS 1: Sum Total Power
            tot_p = 0
            for j from 1 to ny
                val = Get value in cell: j, i
                tot_p = tot_p + val
            endfor
            
            # PASS 2: Calculate Entropy
            entropy = 0
            # Only run expensive math if there is actually sound here
            if tot_p > 0.0000001
                inv_tot_p = 1 / tot_p
                for j from 1 to ny
                    val = Get value in cell: j, i
                    if val > 0
                        # Calculate probability
                        prob = val * inv_tot_p
                        # Sum -p * ln(p)
                        entropy = entropy - prob * ln(prob)
                    endif
                endfor
                # Apply pre-calculated normalization
                entropy = entropy * scale_factor
            endif
            
            selectObject: featureMatrixID
            Set value: out_f, 1, entropy
            selectObject: matID
        endif
    endfor
    
    removeObject: specID
    removeObject: matID

elsif feature = 5
    # LPC
    lpcID = To LPC (autocorrelation): lpc_order, window_length, time_step, 50
    matID = Down to Matrix (lpc)
    transID = Transpose
    
    num_rows = Get number of rows
    num_frames = ceiling(num_rows / frame_skip)
    num_features = Get number of columns
    
    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")
    
    selectObject: transID
    out_f = 0
    for i from 1 to num_rows
        if (i - 1) mod frame_skip = 0
            out_f = out_f + 1
            for c from 1 to num_features
                val = Get value in cell: i, c
                selectObject: featureMatrixID
                Set value: out_f, c, val
                selectObject: transID
            endfor
        endif
    endfor
    removeObject: lpcID, matID, transID

else
    # MEL BANDS
    specID = To Spectrogram: window_length, 8000, time_step, 20, "Gaussian"
    
    start_time = Get start time
    end_time = Get end time
    total_time_frames = floor((end_time - start_time) / time_step)
    num_frames = ceiling(total_time_frames / frame_skip)
    num_features = num_mel_bands
    
    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")
    
    m_min = 2595 * log10(1 + 100/700)
    m_max = 2595 * log10(1 + 8000/700)
    m_step = (m_max - m_min) / num_mel_bands
    
    for b from 1 to num_mel_bands
        m = m_min + (b - 0.5) * m_step
        fc_'b' = 700 * (10^(m/2595) - 1)
    endfor
    
    selectObject: specID
    out_f = 0
    for i from 1 to total_time_frames
        if (i - 1) mod frame_skip = 0
            out_f = out_f + 1
            time = start_time + (i - 0.5) * time_step
            
            for b from 1 to num_features
                freq = fc_'b'
                p = Get power at: time, freq
                if p > 0
                    lp = 10 * log10(p) + 100
                    if lp < 0
                        lp = 0
                    endif
                else
                    lp = 0
                endif
                melp_'b' = lp
            endfor
            
            selectObject: featureMatrixID
            for b from 1 to num_features
                Set value: out_f, b, melp_'b'
            endfor
            selectObject: specID
        endif
    endfor
    removeObject: specID
endif

appendInfoLine: " ", num_frames, " frames"

# ============================================================
# NORMALIZE
# ============================================================

appendInfo: "Normalizing..."
selectObject: featureMatrixID

if feature = 4 or feature = 1
    min_v = Get minimum
    max_v = Get maximum
    if max_v > min_v
        Formula: "(self - " + string$(min_v) + ") / " + string$(max_v - min_v)
    endif
else
    for r from 1 to num_frames
        sum_sq = 0
        for c from 1 to num_features
            val = Get value in cell: r, c
            sum_sq = sum_sq + val * val
        endfor
        if sum_sq > 0
            norm_factor = 1 / sqrt(sum_sq)
            for c from 1 to num_features
                val = Get value in cell: r, c
                Set value: r, c, val * norm_factor
            endfor
        endif
    endfor
endif
appendInfoLine: " done"

# ============================================================
# COMPUTE SSM
# ============================================================

appendInfo: "Computing SSM (", num_frames, "x", num_frames, ")..."

Create simple Matrix: "SSM", num_frames, num_frames, "0"
ssmID = selected("Matrix")

if feature = 4 or feature = 1
    Formula: "1 - abs(Matrix_TheFeatureData[row, 1] - Matrix_TheFeatureData[col, 1])"
else
    formula$ = ""
    for c from 1 to num_features
        part$ = "Matrix_TheFeatureData[row, " + string$(c) + "] * Matrix_TheFeatureData[col, " + string$(c) + "]"
        if c = 1
            formula$ = part$
        else
            formula$ = formula$ + " + " + part$
        endif
    endfor
    Formula: formula$
endif

appendInfoLine: " done"

# ============================================================
# POST-PROCESSING
# ============================================================

selectObject: ssmID

if auto_contrast
    mean_val = Get mean: 0, 0, 0, 0
    if mean_val > 0.95
        pow = 20
    elsif mean_val > 0.90
        pow = 10
    elsif mean_val > 0.80
        pow = 5
    else
        pow = 3
    endif
    Formula: "self ^ " + string$(pow)
    
    min_v = Get minimum
    max_v = Get maximum
    if max_v > min_v
        Formula: "(self - " + string$(min_v) + ") / " + string$(max_v - min_v)
    endif
endif

if gamma <> 1
    Formula: "self ^ " + string$(gamma)
endif

# ============================================================
# FAST COLOR RENDERING
# ============================================================

appendInfo: "Drawing..."

Erase all

if color_scheme = 1
    # GRAYSCALE - Use built-in Paint cells (FASTEST)
    Select outer viewport: 0, 6, 0, 6
    selectObject: ssmID
    Paint cells: 0, 0, 0, 0, 0, 1
    Draw inner box
    scheme$ = "Grayscale"

elsif color_scheme = 5
    # INVERTED GRAYSCALE
    selectObject: ssmID
    Formula: "1 - self"
    Select outer viewport: 0, 6, 0, 6
    Paint cells: 0, 0, 0, 0, 0, 1
    Draw inner box
    Formula: "1 - self"
    scheme$ = "Inverted"

else
    # COLOR SCHEMES - R, G, B separation
    
    if color_scheme = 2
        scheme$ = "Heat"
    elsif color_scheme = 3
        scheme$ = "Viridis"
    else
        scheme$ = "Plasma"
    endif
    
    selectObject: ssmID
    rID = Copy: "R"
    selectObject: ssmID
    gID = Copy: "G"
    selectObject: ssmID
    bID = Copy: "B"
    
    if color_scheme = 2
        # Heat: black -> red -> yellow -> white
        selectObject: rID
        Formula: "min(self * 3, 1)"
        selectObject: gID
        Formula: "if self < 0.33 then 0 else min((self - 0.33) * 3, 1) endif"
        selectObject: bID
        Formula: "if self < 0.66 then 0 else (self - 0.66) * 3 endif"
        
    elsif color_scheme = 3
        # Viridis approximation
        selectObject: rID
        Formula: "0.27 + self * 0.46"
        selectObject: gID
        Formula: "0.004 + self * 0.85"
        selectObject: bID
        Formula: "0.33 + self * 0.17 - self * self * 0.5"
        
    else
        # Plasma approximation
        selectObject: rID
        Formula: "0.05 + self * 0.95"
        selectObject: gID
        Formula: "0.03 + self * self * 0.97"
        selectObject: bID
        Formula: "0.53 - self * 0.53"
    endif
    
    # Clamp values to 0-1
    selectObject: rID
    Formula: "min(max(self, 0), 1)"
    selectObject: gID
    Formula: "min(max(self, 0), 1)"
    selectObject: bID
    Formula: "min(max(self, 0), 1)"
    
    # --- ROBUST MERGE (The New Method) ---
    # 1. Extract Geometry from Red Matrix
    selectObject: rID
    nx = Get number of columns
    ny = Get number of rows
    dx = Get column distance
    dy = Get row distance
    x1 = Get x of column: 1
    y1 = Get y of row: 1
    
    xmin = x1 - dx/2
    xmax = x1 + (nx - 1) * dx + dx/2
    ymin = y1 - dy/2
    ymax = y1 + (ny - 1) * dy + dy/2
    
    # 2. Create the Canvas Photo
    Create Photo: "SSM_Photo", xmin, xmax, nx, dx, x1, ymin, ymax, ny, dy, y1, "0", "0", "0"
    photoID = selected("Photo")
    
    # 3. Inject Channels (Replace)
    selectObject: rID
    plusObject: photoID
    Replace red
    
    selectObject: gID
    plusObject: photoID
    Replace green
    
    selectObject: bID
    plusObject: photoID
    Replace blue
    
    # 4. Draw
    Select outer viewport: 0, 6, 0, 6
    selectObject: photoID
    Paint image: 0, 0, 0, 0
    
    Colour: "Black"
    Draw inner box
    
    removeObject: rID, gID, bID, photoID
endif

# Axis labels
Font size: 9
Marks left every: 1, round(num_frames / 5), "no", "yes", "no"
Marks bottom every: 1, round(num_frames / 5), "no", "yes", "no"
Text left: "yes", "Frame"
Text bottom: "yes", "Frame"

# Title
Font size: 11
Text top: "yes", "SSM: " + originalName$ + " [" + feature_name$ + ", " + scheme$ + "]"

appendInfoLine: " done"

# ============================================================
# CLEANUP
# ============================================================

selectObject: ssmID
Rename: originalName$ + "_SSM_" + feature_name$
removeObject: featureMatrixID

if workingID <> originalID
    removeObject: workingID
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Matrix: ", originalName$, "_SSM_", feature_name$
appendInfoLine: "Size: ", num_frames, " x ", num_frames

selectObject: ssmID