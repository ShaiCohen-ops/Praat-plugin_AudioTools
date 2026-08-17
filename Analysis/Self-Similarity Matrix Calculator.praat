# ============================================================
# Praat AudioTools - Self-Similarity_Matrix_Calculator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4.2 (2026) - Audited similarity semantics and scalable rendering
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

form Self-Similarity Matrix v1.4.2
    optionmenu Feature: 3
        option Pitch (fast)
        option Pitch + Intensity
        option MFCC (recommended)
        option Spectral Entropy
        option LPC coefficients
        option Mel filterbank
    comment === Analysis ===
    positive Time_step 0.01
    natural Frame_skip 1
    comment (1=all, 2=every 2nd, etc.)
    comment === Visualization ===
    optionmenu Color_scheme: 2
        option Grayscale
        option Heat (black-red-yellow-white)
        option Viridis (blue-green-yellow)
        option Plasma (purple-red-yellow)
        option Inverted Grayscale
    boolean Auto_contrast 1
    positive Gamma 1.0
endform

# ============================================================
# FIXED PARAMETERS
# ============================================================

pitch_floor = 75
pitch_ceiling = 600
number_of_mfcc = 12
lpc_order = 16
num_mel_bands = 40
window_length = 0.025

# Similarity kernels and safety cap. The SSM itself is quadratic in frame count.
pitch_sigma_semitones = 1.5
intensity_sigma_db = 12
max_ssm_frames = 2000

# Choose a user-requested skip unless that would create an impractically large SSM.
procedure chooseEffectiveSkip: .totalFrames
    chooseEffectiveSkip.skip = frame_skip
    .limitSkip = ceiling(.totalFrames / max_ssm_frames)
    if .limitSkip > chooseEffectiveSkip.skip
        chooseEffectiveSkip.skip = .limitSkip
    endif
    if chooseEffectiveSkip.skip < 1
        chooseEffectiveSkip.skip = 1
    endif
    chooseEffectiveSkip.frames = ceiling(.totalFrames / chooseEffectiveSkip.skip)
endproc

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
original_duration = Get total duration
original_start = Get start time
original_end = Get end time
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
    feature_name$ = "LPCcoef"
else
    feature_name$ = "MelFB"
endif

clearinfo
writeInfoLine: "=== Self-Similarity Matrix v1.4.2 ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"
appendInfoLine: "Feature: ", feature_name$
appendInfoLine: ""

# ============================================================
# PREPROCESSING
# ============================================================

workingID = originalID
selected_channel = 1

# Do not fold stereo/multichannel audio to mono: opposite-phase material can cancel.
# Instead analyse the channel with the strongest full-duration RMS.
if num_channels > 1
    best_rms = -1
    best_channel_id = 0
    for ch from 1 to num_channels
        selectObject: originalID
        channelID = Extract one channel: ch
        rms = Get root-mean-square: 0, 0
        if rms > best_rms
            if best_channel_id <> 0
                removeObject: best_channel_id
            endif
            best_rms = rms
            best_channel_id = channelID
            selected_channel = ch
        else
            removeObject: channelID
        endif
    endfor
    workingID = best_channel_id
    appendInfoLine: "Multichannel input: analysing strongest channel ", selected_channel
endif

if original_duration < 0.05
    if workingID <> originalID
        removeObject: workingID
    endif
    exitScript: "Sound is too short for reliable frame-based SSM analysis (minimum 0.05 s)."
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
    # PITCH: store pitch on a logarithmic/semitone axis. Unvoiced frames are 0.
    pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
    total_frames = Get number of frames
    actual_step = Get time step
    @chooseEffectiveSkip: total_frames
    effective_skip = chooseEffectiveSkip.skip
    num_frames = chooseEffectiveSkip.frames
    effective_time_step = actual_step * effective_skip
    num_features = 1

    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")

    selectObject: pitchID
    out_f = 0
    for i from 1 to total_frames
        if (i - 1) mod effective_skip = 0
            out_f = out_f + 1
            pval = Get value in frame: i, "Hertz"
            if pval = undefined or pval <= 0
                pitch_st = 0
            else
                pitch_st = 69 + 12 * ln(pval / 440) / ln(2)
            endif
            selectObject: featureMatrixID
            Set value: out_f, 1, pitch_st
            selectObject: pitchID
        endif
    endfor
    removeObject: pitchID

elsif feature = 2
    # PITCH + INTENSITY: align by physical time, not by assuming frame i means
    # the same time in two independently-created analysis objects.
    pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling
    selectObject: workingID
    intID = To Intensity: pitch_floor, time_step, "yes"

    selectObject: pitchID
    total_frames = Get number of frames
    actual_step = Get time step
    @chooseEffectiveSkip: total_frames
    effective_skip = chooseEffectiveSkip.skip
    num_frames = chooseEffectiveSkip.frames
    effective_time_step = actual_step * effective_skip
    num_features = 2

    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")

    out_f = 0
    for i from 1 to total_frames
        if (i - 1) mod effective_skip = 0
            out_f = out_f + 1
            selectObject: pitchID
            frame_time = Get time from frame number: i
            pval = Get value in frame: i, "Hertz"
            if pval = undefined or pval <= 0
                pitch_st = 0
            else
                pitch_st = 69 + 12 * ln(pval / 440) / ln(2)
            endif

            selectObject: intID
            ival = Get value at time: frame_time, "cubic"
            if ival = undefined
                ival = 0
            endif

            selectObject: featureMatrixID
            Set value: out_f, 1, pitch_st
            Set value: out_f, 2, ival
        endif
    endfor
    removeObject: pitchID, intID

elsif feature = 3
    # MFCC
    mfccID = To MFCC: number_of_mfcc, window_length, time_step, 100, 100, 0
    total_frames = Get number of frames
    @chooseEffectiveSkip: total_frames
    effective_skip = chooseEffectiveSkip.skip
    num_frames = chooseEffectiveSkip.frames
    effective_time_step = time_step * effective_skip
    num_features = number_of_mfcc

    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")

    selectObject: mfccID
    out_f = 0
    for i from 1 to total_frames
        if (i - 1) mod effective_skip = 0
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
    # NORMALIZED SPECTRAL ENTROPY. This feature is already bounded 0..1;
    # do not min-max stretch it across the current recording.
    selectObject: workingID
    sr = Get sampling frequency
    nyquist = sr / 2
    specID = To Spectrogram: window_length, nyquist, time_step, 20, "Gaussian"

    selectObject: specID
    matID = To Matrix
    selectObject: matID
    ny = Get number of rows
    nx = Get number of columns
    spec_step = Get column distance

    if ny > 1
        scale_factor = 1 / ln(ny)
    else
        scale_factor = 0
    endif

    @chooseEffectiveSkip: nx
    effective_skip = chooseEffectiveSkip.skip
    num_frames = chooseEffectiveSkip.frames
    effective_time_step = spec_step * effective_skip
    num_features = 1

    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")

    selectObject: matID
    out_f = 0
    for i from 1 to nx
        if (i - 1) mod effective_skip = 0
            out_f = out_f + 1
            tot_p = 0
            for j from 1 to ny
                val = Get value in cell: j, i
                if val > 0
                    tot_p = tot_p + val
                endif
            endfor

            entropy = 0
            if tot_p > 0
                inv_tot_p = 1 / tot_p
                for j from 1 to ny
                    val = Get value in cell: j, i
                    if val > 0
                        prob = val * inv_tot_p
                        entropy = entropy - prob * ln(prob)
                    endif
                endfor
                entropy = entropy * scale_factor
            endif

            selectObject: featureMatrixID
            Set value: out_f, 1, entropy
            selectObject: matID
        endif
    endfor

    removeObject: specID, matID

elsif feature = 5
    # LPC COEFFICIENTS (not formant frequencies). The former menu label
    # "LPC (formants)" overstated what the representation contained.
    lpcID = To LPC (autocorrelation): lpc_order, window_length, time_step, 50
    matID = Down to Matrix (lpc)
    transID = Transpose

    num_rows = Get number of rows
    num_features = Get number of columns
    @chooseEffectiveSkip: num_rows
    effective_skip = chooseEffectiveSkip.skip
    num_frames = chooseEffectiveSkip.frames
    effective_time_step = time_step * effective_skip

    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")

    selectObject: transID
    out_f = 0
    for i from 1 to num_rows
        if (i - 1) mod effective_skip = 0
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
    # TRUE MEL FILTERBANK: integrate Spectrogram power with overlapping
    # triangular filters on the mel scale, rather than sampling one frequency
    # point per nominal band.
    selectObject: workingID
    sr = Get sampling frequency
    nyquist = sr / 2
    mel_max_hz = 8000
    if mel_max_hz > nyquist
        mel_max_hz = nyquist
    endif
    mel_min_hz = 100
    if mel_max_hz <= mel_min_hz
        exitScript: "Sampling rate is too low for the 100-Hz-to-Nyquist mel filterbank."
    endif

    specID = To Spectrogram: window_length, mel_max_hz, time_step, 20, "Gaussian"
    selectObject: specID
    matID = To Matrix
    selectObject: matID
    ny = Get number of rows
    nx = Get number of columns
    y1 = Get y of row: 1
    dy = Get row distance
    spec_step = Get column distance

    @chooseEffectiveSkip: nx
    effective_skip = chooseEffectiveSkip.skip
    num_frames = chooseEffectiveSkip.frames
    effective_time_step = spec_step * effective_skip
    num_features = num_mel_bands

    Create simple Matrix: "TheFeatureData", num_frames, num_features, "0"
    featureMatrixID = selected("Matrix")

    m_min = 2595 * log10(1 + mel_min_hz / 700)
    m_max = 2595 * log10(1 + mel_max_hz / 700)
    m_step = (m_max - m_min) / (num_mel_bands + 1)

    for b from 1 to num_mel_bands
        mel_lo = m_min + (b - 1) * m_step
        mel_mid = m_min + b * m_step
        mel_hi = m_min + (b + 1) * m_step
        hz_lo_'b' = 700 * (10^(mel_lo / 2595) - 1)
        hz_mid_'b' = 700 * (10^(mel_mid / 2595) - 1)
        hz_hi_'b' = 700 * (10^(mel_hi / 2595) - 1)

        row_lo_'b' = ceiling((hz_lo_'b' - y1) / dy) + 1
        row_hi_'b' = floor((hz_hi_'b' - y1) / dy) + 1
        if row_lo_'b' < 1
            row_lo_'b' = 1
        endif
        if row_hi_'b' > ny
            row_hi_'b' = ny
        endif
    endfor

    selectObject: matID
    out_f = 0
    for i from 1 to nx
        if (i - 1) mod effective_skip = 0
            out_f = out_f + 1

            for b from 1 to num_features
                band_power = 0
                weight_sum = 0
                if row_hi_'b' >= row_lo_'b'
                    for j from row_lo_'b' to row_hi_'b'
                        freq = y1 + (j - 1) * dy
                        if freq <= hz_mid_'b'
                            weight = (freq - hz_lo_'b') / (hz_mid_'b' - hz_lo_'b')
                        else
                            weight = (hz_hi_'b' - freq) / (hz_hi_'b' - hz_mid_'b')
                        endif
                        if weight < 0
                            weight = 0
                        endif
                        val = Get value in cell: j, i
                        if weight > 0
                            weight_sum = weight_sum + weight
                            if val > 0
                                band_power = band_power + weight * val
                            endif
                        endif
                    endfor
                endif

                if weight_sum > 0
                    band_power = band_power / weight_sum
                endif
                if band_power > 0.000000000000000000000000000001
                    melp_'b' = 10 * log10(band_power) + 100
                    if melp_'b' < 0
                        melp_'b' = 0
                    endif
                else
                    melp_'b' = 0
                endif
            endfor

            selectObject: featureMatrixID
            for b from 1 to num_features
                Set value: out_f, b, melp_'b'
            endfor
            selectObject: matID
        endif
    endfor
    removeObject: specID, matID
endif
appendInfoLine: " ", num_frames, " frames"

# ============================================================
# NORMALIZE VECTOR FEATURES
# ============================================================

appendInfo: "Normalizing..."
selectObject: featureMatrixID

# Pitch, Pitch+Intensity and Entropy have feature-specific similarity kernels.
# MFCC, LPC and Mel use row-normalized vectors and cosine similarity.
if feature = 3 or feature = 5 or feature = 6
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

if feature = 1
    # Pitch similarity is local in musical pitch space: one octave should not
    # remain highly similar merely because the global pitch range is wide.
    Formula: "if Matrix_TheFeatureData[row, 1] <= 0 or Matrix_TheFeatureData[col, 1] <= 0 then 0 else exp(-0.5 * ((Matrix_TheFeatureData[row, 1] - Matrix_TheFeatureData[col, 1]) / " + string$(pitch_sigma_semitones) + ")^2) endif"

elsif feature = 2
    # Balanced multimodal kernel: pitch carries 75 percent, intensity 25 percent.
    # When either frame is unvoiced, only intensity contributes.
    Formula: "if Matrix_TheFeatureData[row, 1] > 0 and Matrix_TheFeatureData[col, 1] > 0 then 0.75 * exp(-0.5 * ((Matrix_TheFeatureData[row, 1] - Matrix_TheFeatureData[col, 1]) / " + string$(pitch_sigma_semitones) + ")^2) + 0.25 * exp(-0.5 * ((Matrix_TheFeatureData[row, 2] - Matrix_TheFeatureData[col, 2]) / " + string$(intensity_sigma_db) + ")^2) else 0.25 * exp(-0.5 * ((Matrix_TheFeatureData[row, 2] - Matrix_TheFeatureData[col, 2]) / " + string$(intensity_sigma_db) + ")^2) endif"

elsif feature = 4
    Formula: "min(max(1 - abs(Matrix_TheFeatureData[row, 1] - Matrix_TheFeatureData[col, 1]), 0), 1)"

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

    if feature = 3 or feature = 5
        # MFCC and LPC coefficients can be signed. Negative cosine means
        # opposition, not similarity, so clamp it to zero.
        Formula: "min(max(" + formula$ + ", 0), 1)"
    else
        # Mel filterbank vectors are non-negative, hence cosine is already [0,1].
        Formula: "min(max(" + formula$ + ", 0), 1)"
    endif
endif

# By definition every frame is maximally similar to itself. This also keeps
# the main diagonal intact for unvoiced/zero-vector frames without allowing
# silence to create large off-diagonal false blocks.
Formula: "if row = col then 1 else self endif"

appendInfoLine: " done"

# ============================================================
# DISPLAY POST-PROCESSING
# ============================================================

# Preserve the output SSM as the raw, interpretable similarity matrix.
# Contrast and gamma affect only a temporary display copy.
selectObject: ssmID
displayID = Copy: "SSM_display"
selectObject: displayID

if auto_contrast
    mean_val = Get mean: 0, 0, 0, 0
    if mean_val > 0.95
        contrast_power = 20
    elsif mean_val > 0.90
        contrast_power = 10
    elsif mean_val > 0.80
        contrast_power = 5
    else
        contrast_power = 3
    endif
    Formula: "self ^ " + string$(contrast_power)

    min_v = Get minimum
    max_v = Get maximum
    if max_v > min_v
        Formula: "(self - " + string$(min_v) + ") / " + string$(max_v - min_v)
    endif
endif

if gamma <> 1
    Formula: "min(max(self, 0), 1) ^ " + string$(gamma)
endif

# ============================================================
# FAST COLOR RENDERING
# ============================================================

appendInfo: "Drawing..."

Erase all

# AudioTools house figure size: 8 x 8. The SSM itself remains square;
# a separate title strip is reserved above it.
Select outer viewport: 0, 8, 0, 8
plot_left = 0.85
plot_right = 7.35
plot_top = 1.25
plot_bottom = 7.75

if color_scheme = 1
    # GRAYSCALE - Use built-in Paint cells (FASTEST)
    Select outer viewport: plot_left, plot_right, plot_top, plot_bottom
    selectObject: displayID
    Paint cells: 0, 0, 0, 0, 0, 1
    Draw inner box
    scheme$ = "Grayscale"

elsif color_scheme = 5
    # INVERTED GRAYSCALE
    selectObject: displayID
    Formula: "1 - self"
    Select outer viewport: plot_left, plot_right, plot_top, plot_bottom
    Paint cells: 0, 0, 0, 0, 0, 1
    Draw inner box
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
    
    selectObject: displayID
    rID = Copy: "R"
    selectObject: displayID
    gID = Copy: "G"
    selectObject: displayID
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
    Select outer viewport: plot_left, plot_right, plot_top, plot_bottom
    selectObject: photoID
    Paint image: 0, 0, 0, 0
    
    Colour: "Black"
    Draw inner box
    
    removeObject: rID, gID, bID, photoID
endif

# Axis labels. Re-select the square plot viewport explicitly so Picture state
# left by Photo/Matrix drawing cannot leak into the labels.
Select outer viewport: plot_left, plot_right, plot_top, plot_bottom
Font size: 9
Colour: "Black"
mark_step = round(num_frames / 5)
if mark_step < 1
    mark_step = 1
endif
Marks left every: 1, mark_step, "no", "yes", "no"
Marks bottom every: 1, mark_step, "no", "yes", "no"
Text left: "yes", "Frame"
Text bottom: "yes", "Frame"

# AudioTools title area -- two independent strips prevent collisions between
# the main heading and long metadata lines.
Select outer viewport: 0, 8, 0, 0.45
Axes: 0, 1, 0, 1
Font size: 13
Colour: "Black"
Text: 0.5, "centre", 0.50, "half", "##Self-Similarity Matrix##"

Select outer viewport: 0, 8, 0.50, 0.92
Axes: 0, 1, 0, 1
Font size: 7
Colour: "{0.35, 0.35, 0.50}"
Text: 0.5, "centre", 0.50, "half", originalName$ + "   |   " + feature_name$ + "   |   " + scheme$ + "   |   " + string$(num_frames) + " frames   |   dt=" + fixed$(effective_time_step, 3) + " s"
Colour: "Black"

appendInfoLine: " done"

# ============================================================
# CLEANUP
# ============================================================

removeObject: displayID
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
appendInfoLine: "Requested frame skip: ", frame_skip
appendInfoLine: "Effective frame skip: ", effective_skip
appendInfoLine: "Effective time step: ", fixed$(effective_time_step, 4), " s"
if effective_skip > frame_skip
    appendInfoLine: "Adaptive cap applied (max ", max_ssm_frames, " SSM frames)."
endif
appendInfoLine: "Output Matrix contains RAW similarity; display contrast/gamma are not baked in."

selectObject: ssmID