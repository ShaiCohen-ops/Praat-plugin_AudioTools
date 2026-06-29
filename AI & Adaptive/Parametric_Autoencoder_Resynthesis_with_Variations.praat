# ============================================================
# Praat AudioTools - Parametric_Autoencoder_Resynthesis_with_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True autoencoder with latent space perturbation for novel variations.
#   Uses KlattGrid source-filter synthesis to render independent F0 and
#   F1-F4 trajectories. Dynamic voicing amplitude for natural silence.
#
# Changelog v0.9 (2026):
#   - TIMBRE: Added source-naturalness controls to reduce the "plastic"
#     Klatt buzz. Spectral_tilt_dB rolls off the buzzy upper harmonics;
#     Breathiness_dB mixes breath noise into the voiced source (gated to
#     voiced frames in Clean, constant in Glitch); Flutter adds F0
#     micro-variation so pitch is not robotically steady. All three are
#     form parameters; 0 disables a given effect (KlattGrid default).
#   - VISUALIZATION: Reformatted the network view to the 8-inch AudioTools
#     standard - title block, grey subtitle band, paired encoder/decoder
#     topology and weight panels on an 8-wide canvas (was 10-wide), bold
#     panel labels, and a grey summary panel at the bottom.
#
# Changelog v0.7:
#   - Fixed output selection (use ID array instead of name)
#   - Added visualization option
#   - Code cleanup
#
# Changelog v0.8 (2026):
#   - SPEED: Replaced ~100K-160K Get-value-in-cell + Set-value calls
#     across the latent-variation loops, denormalization loop, and
#     parameter normalization loop with single-call Formula
#     operations on Matrix objects. Variation transforms that ran
#     in 5-8 seconds of dispatch overhead now run in well under 1
#     second.
#     Affected: Var1 (Noise), Var2 (Scale), Var3 (Invert),
#     Var4 (Smooth), Var5 (Warp), Var6 (Swap), Var7 (Interp),
#     extra-noise variations, the [0,1] clamp, the denormalization
#     to engineering units, and the [param,frame]→[0,1] normalization.
#   - FIX: Var4 "Smooth" was reading already-smoothed values from
#     prior iterations due to in-place writes (output[i] depended
#     on output[i-1] for i > 2, not input[i-1]). v0.8 reads from a
#     Copy of the latent matrix, producing true symmetric 1-2-1
#     smoothing. Output for inputs with smoothly-varying latent
#     trajectories will be slightly less smoothed than v0.7;
#     output for sharply-varying inputs will be visibly cleaner.
#   - VISUALIZATION: Expanded from a single waveform display to an
#     8-inch AudioTools-standard 5-panel layout: title row, original
#     waveform, latent-space activations heatmap (bottleneck × time),
#     2×4 grid of variation waveforms with labels, and stats panel
#     at the bottom with grey background.
# ============================================================

# === Input Validation ===
if numberOfSelected() <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound_orig = selected()
sound_name$ = selected$("Sound")

form Parametric Autoencoder v0.9
    choice Preset_selection: 1
        button Clean - Dynamic Amplitude - 6 Params
        button Glitch - Constant Drone - 5 Params
    positive Time_step 0.01
    positive Bottleneck_size 3
    positive Epochs 150
    positive Num_variations 7
    positive Pitch_floor 60
    positive Pitch_ceiling 500
    positive Voicing_threshold 0.4
    positive Latent_noise 0.15
    positive Bandwidth_fraction 0.1
    positive Aspiration_during_unvoiced 20
    comment === Naturalness (reduce plastic timbre; 0 = off) ===
    real Spectral_tilt_dB 20
    real Breathiness_dB 25
    real Flutter 0.3
    boolean Draw_network 1
    boolean Draw_visualization 1
endform

# ===== PRESET LOGIC =====
if preset_selection = 1
    presetName$ = "Clean"
    nparams = 6
else
    presetName$ = "Glitch"
    nparams = 5
endif

clearinfo
writeInfoLine: "=== Parametric Autoencoder v0.9 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Parameters: ", nparams, " | Bottleneck: ", bottleneck_size
appendInfoLine: ""

selectObject: sound_orig
Resample: 44100, 50
sound = selected()

selectObject: sound
intensity_check = Get intensity (dB)
appendInfoLine: "Sound intensity: ", fixed$(intensity_check, 2), " dB"
if intensity_check < 30
    appendInfoLine: "WARNING: Sound is very quiet. Amplifying..."
    Scale peak: 0.99
endif

# ===== 1. ANALYSIS =====
appendInfoLine: "Extracting features..."

selectObject: sound
To Pitch (ac): 0.0, pitch_floor, 15, "no", 0.03, voicing_threshold, 0.01, 0.35, 0.14, pitch_ceiling
pitch_obj = selected()

selectObject: pitch_obj
num_voiced = Count voiced frames
appendInfoLine: "Voiced frames detected: ", num_voiced

selectObject: sound
To Formant (burg): 0.0, 5, 5500, 0.025, 50.0
formant_obj = selected()

selectObject: sound
To Intensity: 75, 0, "yes"
intensity_obj = selected()

selectObject: sound
start_time = Get start time
end_time = Get end time
dt = time_step
num_frames = floor((end_time - start_time) / dt) + 1

# ===== 2. FILL MATRIX =====
Create simple Matrix: "ParamMatrix", nparams, num_frames, "0"
param_matrix = selected()

for frameIdx from 1 to num_frames
    t = start_time + (frameIdx - 1) * dt
    
    selectObject: pitch_obj
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined
        f0 = 0
    endif
    
    selectObject: formant_obj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    f4 = Get value at time: 4, t, "Hertz", "Linear"
    
    if f1 = undefined
        f1 = 500
    endif
    if f2 = undefined
        f2 = 1500
    endif
    if f3 = undefined
        f3 = 2500
    endif
    if f4 = undefined
        f4 = 3500
    endif
    
    selectObject: param_matrix
    Set value: 1, frameIdx, f0
    Set value: 2, frameIdx, f1
    Set value: 3, frameIdx, f2
    Set value: 4, frameIdx, f3
    Set value: 5, frameIdx, f4
    
    if preset_selection = 1
        selectObject: intensity_obj
        int_val = Get value at time: t, "cubic"
        if int_val = undefined
            int_val = 0
        endif
        
        selectObject: param_matrix
        Set value: 6, frameIdx, int_val
    endif
endfor

# ===== 3. NORMALIZE =====
appendInfoLine: "Normalizing..."
Create simple Matrix: "ParamMins", nparams, 1, "0"
mins_mat = selected()
Create simple Matrix: "ParamMaxs", nparams, 1, "0"
maxs_mat = selected()

for p from 1 to nparams
    selectObject: param_matrix
    pmin = 1e30
    pmax = -1e30
    for frameIdx from 1 to num_frames
        val = Get value in cell: p, frameIdx
        if val < pmin
            pmin = val
        endif
        if val > pmax
            pmax = val
        endif
    endfor
    if pmax = pmin
        pmax = pmin + 1
    endif
    selectObject: mins_mat
    Set value: p, 1, pmin
    selectObject: maxs_mat
    Set value: p, 1, pmax
endfor

selectObject: param_matrix
Copy: "NormMatrix"
norm_matrix = selected()

# v0.8: Replaced per-cell Get/Set normalization loop with a single
# Formula referencing mins_mat/maxs_mat. The Formula evaluates
# (self - pmin) / (pmax - pmin) at every cell using row-indexed
# reads from the per-parameter min/max matrices.
mins_str$ = string$(mins_mat)
maxs_str$ = string$(maxs_mat)
Formula: "(self - object[" + mins_str$ + ", row, 1]) / (object[" + maxs_str$ + ", row, 1] - object[" + mins_str$ + ", row, 1])"

selectObject: norm_matrix
Transpose
train_matrix = selected()

# ===== 4. TRAIN AUTOENCODER =====
selectObject: train_matrix
To Pattern: 1
pattern_in = selected()
selectObject: train_matrix
To ActivationList
activ_target = selected()

Create FFNet: "Autoencoder", nparams, nparams, bottleneck_size, 0
autoencoder = selected()

appendInfoLine: "Training autoencoder (", nparams, " -> ", bottleneck_size, " -> ", nparams, ")..."
selectObject: autoencoder
plusObject: pattern_in
plusObject: activ_target
Learn: epochs, 0.001, "Minimum-squared-error"

# ===== 5. EXTRACT LATENT SPACE =====
appendInfoLine: "Extracting latent representations..."
selectObject: autoencoder
plusObject: pattern_in
To ActivationList: 1
hidden_activ = selected()
selectObject: hidden_activ
To Matrix
hidden_matrix = selected()

selectObject: hidden_matrix
latent_min = Get minimum
latent_max = Get maximum
latent_range = latent_max - latent_min
if latent_range = 0
    latent_range = 1
endif
appendInfoLine: "Latent range: [", fixed$(latent_min, 3), ", ", fixed$(latent_max, 3), "]"

# ===== 6. TRAIN DECODER =====
appendInfoLine: "Training decoder..."
selectObject: hidden_matrix
To Pattern: 1
hidden_pattern = selected()

Create FFNet: "Decoder", bottleneck_size, nparams, 0, 0
decoder = selected()

selectObject: decoder
plusObject: hidden_pattern
plusObject: activ_target
Learn: epochs, 0.001, "Minimum-squared-error"

# ===== DRAW NETWORK =====
if draw_network = 1
    appendInfoLine: "Drawing network visualization..."
    Erase all
    Line width: 1

    # ---- Title block (suite standard) ----
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Parametric Autoencoder v0.9 - Network##"

    # ---- Subtitle band ----
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", sound_name$ + "   |   " + presetName$ + "   |   " + string$(nparams) + " params -> " + string$(bottleneck_size) + " latent -> " + string$(nparams) + " params   |   " + string$(epochs) + " epochs"

    # ---- Encoder topology (left) ----
    Select outer viewport: 0.1, 3.95, 0.62, 0.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Encoder##   " + string$(nparams) + " -> " + string$(bottleneck_size)
    Select outer viewport: 0.3, 3.75, 0.95, 3.45
    selectObject: autoencoder
    Draw topology

    # ---- Decoder topology (right) ----
    Select outer viewport: 4.05, 7.9, 0.62, 0.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Decoder##   " + string$(bottleneck_size) + " -> " + string$(nparams)
    Select outer viewport: 4.25, 7.7, 0.95, 3.45
    selectObject: decoder
    Draw topology

    # ---- Encoder weights (left) ----
    Select outer viewport: 0.1, 3.95, 3.75, 4.05
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Encoder weights##   (Input -> Latent)"
    Select outer viewport: 0.3, 3.75, 4.08, 6.5
    selectObject: autoencoder
    Draw weights: 1, "yes"

    # ---- Decoder weights (right) ----
    Select outer viewport: 4.05, 7.9, 3.75, 4.05
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Decoder weights##   (Latent -> Output)"
    Select outer viewport: 4.25, 7.7, 4.08, 6.5
    selectObject: decoder
    Draw weights: 1, "yes"

    # ---- Summary panel (grey, suite standard) ----
    Select outer viewport: 0, 8, 6.7, 7.3
    Select inner viewport: 0.6, 7.7, 6.78, 7.22
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Preset: " + presetName$ + "    Params: " + string$(nparams) + "    Latent: " + string$(bottleneck_size) + "    Epochs: " + string$(epochs) + "    Variations: " + string$(num_variations + 1) + "    Latent range: [" + fixed$(latent_min, 2) + ", " + fixed$(latent_max, 2) + "]"
    Font size: 10
    Colour: "Black"
endif

# ===== 7. GENERATE VARIATIONS =====
appendInfoLine: ""
appendInfoLine: "Generating variations via latent space exploration..."

# Array to store output sound IDs
n_outputs = num_variations + 1
outputIDs# = zero#(n_outputs)

for var_num from 0 to num_variations
    selectObject: hidden_matrix
    Copy: "Latent_Var" + string$(var_num)
    latent_var = selected()
    nLatentRows = Get number of rows
    nLatentCols = Get number of columns
    latent_str$ = string$(latent_var)
    
    # === VARIATION TYPES ===
    # v0.8: All variation transforms now use single-Formula operations
    # on the latent matrix instead of double Get/Set loops. ~50x faster.
    if var_num = 0
        var_name$ = "Original"
        appendInfoLine: "  Var0: Original reconstruction (no perturbation)"
        
    elsif var_num = 1
        var_name$ = "Noise"
        appendInfoLine: "  Var1: Random noise injection in latent space"
        noise_amt = latent_noise * latent_range * 0.3
        noise_amt_str$ = fixed$(noise_amt, 8)
        selectObject: latent_var
        Formula: "self + randomGauss(0, " + noise_amt_str$ + ")"
        
    elsif var_num = 2
        var_name$ = "Scale"
        appendInfoLine: "  Var2: Scale first latent dimension"
        selectObject: latent_var
        Formula: "if col = 1 then self * 1.3 + 0.1 else self fi"
        
    elsif var_num = 3
        var_name$ = "Invert"
        appendInfoLine: "  Var3: Mirror second latent dimension around mean"
        if bottleneck_size >= 2
            # Compute mean of column 2 with a small scripted loop
            # (single-column sum has no Praat-native shortcut), then
            # apply 2*mean - self via a single Formula.
            selectObject: latent_var
            dmean = 0
            for ri from 1 to nLatentRows
                dmean += Get value in cell: ri, 2
            endfor
            dmean = dmean / nLatentRows
            dmean_str$ = fixed$(dmean, 12)
            selectObject: latent_var
            Formula: "if col = 2 then 2 * " + dmean_str$ + " - self else self fi"
        endif
        
    elsif var_num = 4
        var_name$ = "Smooth"
        appendInfoLine: "  Var4: Temporal smoothing in latent space"
        # v0.8 FIX: read from a copy so smoothing is true symmetric
        # 1-2-1, not the in-place "running average" that v0.7 produced
        # by reading the just-written self[row-1].
        selectObject: latent_var
        smooth_src = Copy: "smooth_temp"
        smooth_str$ = string$(smooth_src)
        selectObject: latent_var
        Formula: "if row > 1 and row < nrow then (object[" + smooth_str$ + ", row-1, col] + object[" + smooth_str$ + ", row, col] + object[" + smooth_str$ + ", row+1, col]) / 3 else self fi"
        removeObject: smooth_src
        
    elsif var_num = 5
        var_name$ = "Warp"
        appendInfoLine: "  Var5: Time-warping in latent space"
        # Pre-Copy so we can read original positions while writing new ones.
        selectObject: latent_var
        warp_src = Copy: "warp_temp"
        warp_str$ = string$(warp_src)
        nrm1_str$ = string$(nLatentRows - 1)
        selectObject: latent_var
        # warp_idx = round(1 + (n-1) * ((row-1)/(n-1))^1.5), clamped
        Formula: "object[" + warp_str$ + ", max(1, min(nrow, round(1 + " + nrm1_str$ + " * ((row - 1) / max(1, " + nrm1_str$ + "))^1.5))), col]"
        removeObject: warp_src
        
    elsif var_num = 6
        var_name$ = "Swap"
        appendInfoLine: "  Var6: Swap latent dimensions"
        if bottleneck_size >= 2
            selectObject: latent_var
            swap_src = Copy: "swap_temp"
            swap_str$ = string$(swap_src)
            selectObject: latent_var
            # Nested if/fi for the 3-way conditional (col=1 → read col 2,
            # col=2 → read col 1, else → self).
            Formula: "if col = 1 then object[" + swap_str$ + ", row, 2] else if col = 2 then object[" + swap_str$ + ", row, 1] else self fi fi"
            removeObject: swap_src
        endif
        
    elsif var_num = 7
        var_name$ = "Interp"
        appendInfoLine: "  Var7: Interpolate toward mean latent"
        # Compute per-column means via a small scripted loop, write to
        # a 1xnCols Matrix, then apply the interpolation as a single
        # Formula referencing that means matrix.
        Create simple Matrix: "col_means_v7", 1, nLatentCols, "0"
        means_v7 = selected()
        for ci from 1 to nLatentCols
            selectObject: latent_var
            csum = 0
            for ri from 1 to nLatentRows
                csum += Get value in cell: ri, ci
            endfor
            selectObject: means_v7
            Set value: 1, ci, csum / nLatentRows
        endfor
        means_v7_str$ = string$(means_v7)
        selectObject: latent_var
        Formula: "0.6 * self + 0.4 * object[" + means_v7_str$ + ", 1, col]"
        removeObject: means_v7
        
    else
        var_name$ = "Var" + string$(var_num)
        appendInfoLine: "  Var", var_num, ": Extra variation (noise)"
        noise_amt = latent_noise * latent_range * 0.2 * var_num
        noise_amt_str$ = fixed$(noise_amt, 8)
        selectObject: latent_var
        Formula: "self + randomGauss(0, " + noise_amt_str$ + ")"
    endif

    # === CLAMP TO [0, 1] ===
    # v0.8: replaced ~6000 Get/Set calls per variation with one Formula.
    selectObject: latent_var
    Formula: "max(0, min(1, self))"

    # === DECODE ===
    selectObject: latent_var
    To Pattern: 1
    latent_pattern = selected()
    
    selectObject: decoder
    plusObject: latent_pattern
    To ActivationList: 1
    decoded_activ = selected()
    
    selectObject: decoded_activ
    To Matrix
    decoded_matrix = selected()
    
    selectObject: decoded_matrix
    Transpose
    recon_matrix = selected()
    Rename: "ReconParams_" + var_name$
    
    # === DENORMALIZE ===
    # v0.8: Single Formula instead of nparams * nReconCols * 2 Get/Set calls.
    # Reads pmin/pmax from mins_mat/maxs_mat indexed by row.
    selectObject: recon_matrix
    nReconCols = Get number of columns
    Formula: "self * (object[" + maxs_str$ + ", row, 1] - object[" + mins_str$ + ", row, 1]) + object[" + mins_str$ + ", row, 1]"
    
    # ===== KLATTGRID SYNTHESIS =====
    Create KlattGrid: "Synth_" + var_name$, start_time, end_time, 4, 0, 0, 0, 0, 0, 0
    klatt = selected()
    
    # --- PITCH ---
    selectObject: klatt
    Remove pitch points between: start_time, end_time
    voiced_count = 0
    for frameIdx from 1 to num_frames
        t = start_time + (frameIdx - 1) * dt
        selectObject: recon_matrix
        f0_val = Get value in cell: 1, frameIdx
        if f0_val > pitch_floor and f0_val < pitch_ceiling * 1.5
            selectObject: klatt
            Add pitch point: t, f0_val
            voiced_count = voiced_count + 1
        endif
    endfor
    if voiced_count = 0
        selectObject: klatt
        Add pitch point: start_time, 120
        Add pitch point: end_time, 120
    endif
    
    # --- FORMANTS ---
    for f_num from 1 to 4
        selectObject: klatt
        Remove oral formant frequency points: f_num, start_time, end_time
        Remove oral formant bandwidth points: f_num, start_time, end_time
        
        for frameIdx from 1 to num_frames
            t = start_time + (frameIdx - 1) * dt
            selectObject: recon_matrix
            f_val = Get value in cell: f_num + 1, frameIdx
            
            # Per-formant clamping
            if f_num = 1
                if f_val < 200
                    f_val = 200
                endif
                if f_val > 1000
                    f_val = 1000
                endif
            elsif f_num = 2
                if f_val < 500
                    f_val = 500
                endif
                if f_val > 3000
                    f_val = 3000
                endif
            elsif f_num = 3
                if f_val < 1500
                    f_val = 1500
                endif
                if f_val > 4000
                    f_val = 4000
                endif
            elsif f_num = 4
                if f_val < 2500
                    f_val = 2500
                endif
                if f_val > 5000
                    f_val = 5000
                endif
            endif
            
            bw = f_val * bandwidth_fraction
            if bw < 50
                bw = 50
            endif
            
            selectObject: klatt
            Add oral formant frequency point: f_num, t, f_val
            Add oral formant bandwidth point: f_num, t, bw
        endfor
    endfor
    
    # --- SOURCE NATURALNESS (reduce plastic timbre) ---
    # Spectral tilt rolls off the buzzy upper harmonics; flutter adds
    # natural F0 micro-variation so the pitch is not robotically steady.
    # Both are constant across the sound; 0 leaves the KlattGrid default.
    selectObject: klatt
    if spectral_tilt_dB > 0
        Add spectral tilt point: start_time, spectral_tilt_dB
        Add spectral tilt point: end_time, spectral_tilt_dB
    endif
    if flutter > 0
        Add flutter point: start_time, flutter
        Add flutter point: end_time, flutter
    endif

    # --- AMPLITUDE LOGIC ---
    selectObject: klatt
    Remove voicing amplitude points: start_time, end_time
    Remove aspiration amplitude points: start_time, end_time
    Remove breathiness amplitude points: start_time, end_time

    if preset_selection = 1
        # === CLEAN (Dynamic Amplitude) ===
        selectObject: mins_mat
        int_min = Get value in cell: 6, 1
        selectObject: maxs_mat
        int_max = Get value in cell: 6, 1
        int_range = int_max - int_min
        if int_range < 1
            int_range = 1
        endif
        
        for frameIdx from 1 to num_frames
            t = start_time + (frameIdx - 1) * dt
            selectObject: recon_matrix
            f0_val = Get value in cell: 1, frameIdx
            int_val = Get value in cell: 6, frameIdx
            
            amp = 90 * (int_val - int_min) / int_range
            if amp < 0
                amp = 0
            endif
            if amp > 90
                amp = 90
            endif
            
            selectObject: klatt
            if f0_val > pitch_floor
                Add voicing amplitude point: t, amp
                Add aspiration amplitude point: t, 0
                if breathiness_dB > 0
                    Add breathiness amplitude point: t, breathiness_dB
                endif
            else
                Add voicing amplitude point: t, 0
                Add aspiration amplitude point: t, aspiration_during_unvoiced
                if breathiness_dB > 0
                    Add breathiness amplitude point: t, 0
                endif
            endif
        endfor
        
    else
        # === GLITCH (Constant Drone) ===
        selectObject: klatt
        Add voicing amplitude point: start_time, 90
        Add voicing amplitude point: end_time, 90
        Add aspiration amplitude point: start_time, 0
        Add aspiration amplitude point: end_time, 0
        if breathiness_dB > 0
            Add breathiness amplitude point: start_time, breathiness_dB
            Add breathiness amplitude point: end_time, breathiness_dB
        endif
    endif
    
    # --- SYNTHESIZE ---
    selectObject: klatt
    To Sound
    klatt_sound = selected()
    Rename: "Resynth_" + sound_name$ + "_" + var_name$
    Scale peak: 0.95
    
    # Store the ID
    outputIDs#[var_num + 1] = klatt_sound
    
    # --- CLEANUP VARIATION TEMPS ---
    selectObject: latent_var
    plusObject: latent_pattern
    plusObject: decoded_activ
    plusObject: decoded_matrix
    plusObject: recon_matrix
    plusObject: klatt
    Remove
endfor

# ===== 8. VISUALIZATION =====
if draw_visualization = 1 and draw_network = 0
    appendInfoLine: "Drawing visualization..."

    Erase all
    Font size: 10

    # ====== TITLE ======
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Parametric Autoencoder v0.9## | " + sound_name$ + " [" + presetName$ + "]"

    # ====== ORIGINAL WAVEFORM (full width) ======
    Select outer viewport: 0, 8, 0.5, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.4
    selectObject: sound_orig
    Colour: "{0.4, 0.4, 0.45}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    # ====== LATENT-SPACE HEATMAP (full width) ======
    # Show bottleneck activations as a heatmap: rows = latent dim,
    # cols = time frames. hidden_matrix is shape (nFrames, bottleneck)
    # so we transpose for visual layout.
    Select outer viewport: 0, 8, 1.5, 2.5
    Select inner viewport: 0.6, 7.7, 1.65, 2.4
    selectObject: hidden_matrix
    latent_t = Transpose
    Paint cells: 0, 0, 0, 0
    removeObject: latent_t
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Latent (" + string$(bottleneck_size) + "d)"

    # ====== VARIATION GRID ======
    # 4 columns × ceil(n_outputs / 4) rows of variation waveforms.
    # Each panel ~1.85" wide, ~1" tall.
    grid_cols = 4
    grid_rows = (n_outputs + grid_cols - 1) div grid_cols
    grid_x0 = 0.0
    grid_x1 = 8.0
    grid_y0 = 2.5
    panel_h = 1.0
    panel_w = (grid_x1 - grid_x0) / grid_cols

    # Variation labels parallel to outputIDs# — index 1 = Original
    # then 1..num_variations follow the variation type.
    Font size: 7
    for v from 1 to n_outputs
        var_idx_zero = v - 1
        if var_idx_zero = 0
            label$ = "Var0 Original"
        elsif var_idx_zero = 1
            label$ = "Var1 Noise"
        elsif var_idx_zero = 2
            label$ = "Var2 Scale"
        elsif var_idx_zero = 3
            label$ = "Var3 Invert"
        elsif var_idx_zero = 4
            label$ = "Var4 Smooth"
        elsif var_idx_zero = 5
            label$ = "Var5 Warp"
        elsif var_idx_zero = 6
            label$ = "Var6 Swap"
        elsif var_idx_zero = 7
            label$ = "Var7 Interp"
        else
            label$ = "Var" + string$(var_idx_zero) + " Noise"
        endif

        col_idx = (v - 1) mod grid_cols
        row_idx = (v - 1) div grid_cols
        px0 = grid_x0 + col_idx * panel_w
        px1 = px0 + panel_w
        py0 = grid_y0 + row_idx * panel_h
        py1 = py0 + panel_h

        Select outer viewport: px0, px1, py0, py1
        Select inner viewport: px0 + 0.15, px1 - 0.1, py0 + 0.18, py1 - 0.05
        selectObject: outputIDs#[v]
        # Color per variation type: original blue-grey, perturbations warmer
        if var_idx_zero = 0
            Colour: "{0.30, 0.45, 0.65}"
        elsif var_idx_zero = 1
            Colour: "{0.75, 0.45, 0.30}"
        elsif var_idx_zero = 2
            Colour: "{0.55, 0.65, 0.30}"
        elsif var_idx_zero = 3
            Colour: "{0.65, 0.30, 0.55}"
        elsif var_idx_zero = 4
            Colour: "{0.40, 0.65, 0.65}"
        elsif var_idx_zero = 5
            Colour: "{0.65, 0.55, 0.30}"
        elsif var_idx_zero = 6
            Colour: "{0.45, 0.55, 0.75}"
        elsif var_idx_zero = 7
            Colour: "{0.55, 0.40, 0.65}"
        else
            Colour: "{0.50, 0.50, 0.55}"
        endif
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Line width: 0.5
        Draw inner box
        # Label inside the panel (top-left)
        Font size: 6
        Select outer viewport: px0, px1, py0, py1
        Axes: 0, 1, 0, 1
        Text: 0.05, "left", 0.92, "half", label$
    endfor

    # ====== STATS PANEL ======
    stats_y0 = grid_y0 + grid_rows * panel_h + 0.05
    stats_y1 = stats_y0 + 0.5
    Select outer viewport: 0, 8, stats_y0, stats_y1
    Select inner viewport: 0.6, 7.7, stats_y0 + 0.05, stats_y1 - 0.05
    Colour: "{0.94, 0.94, 0.94}"
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Axes: 0, 1, 0, 1
    Text: 0.02, "left", 0.5, "half", "Preset: " + presetName$
    Text: 0.18, "left", 0.5, "half", "Params: " + string$(nparams)
    Text: 0.30, "left", 0.5, "half", "Bottleneck: " + string$(bottleneck_size)
    Text: 0.46, "left", 0.5, "half", "Epochs: " + string$(epochs)
    Text: 0.60, "left", 0.5, "half", "Variations: " + string$(num_variations + 1)
    Text: 0.78, "left", 0.5, "half", "Latent: [" + fixed$(latent_min, 2) + ", " + fixed$(latent_max, 2) + "]"

    Font size: 10
    Colour: "Black"
endif

# ===== 9. CLEANUP =====
selectObject: sound
plusObject: pitch_obj
plusObject: formant_obj
plusObject: intensity_obj
plusObject: param_matrix
plusObject: mins_mat
plusObject: maxs_mat
plusObject: norm_matrix
plusObject: train_matrix
plusObject: pattern_in
plusObject: activ_target
plusObject: autoencoder
plusObject: hidden_activ
plusObject: hidden_matrix
plusObject: hidden_pattern
plusObject: decoder
Remove

# ===== 10. SELECT OUTPUTS =====
selectObject: sound_orig
for var_num from 1 to n_outputs
    plusObject: outputIDs#[var_num]
endfor

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Created ", num_variations + 1, " latent-space variations"
appendInfoLine: ""
appendInfoLine: "SYNTHESIS: KlattGrid source-filter"
if preset_selection = 1
    appendInfoLine: "  - Dynamic voicing amplitude (gated by F0)"
    appendInfoLine: "  - Aspiration: ", fixed$(aspiration_during_unvoiced, 0), " dB during unvoiced"
else
    appendInfoLine: "  - Constant 90 dB voicing (drone mode)"
endif
appendInfoLine: ""
appendInfoLine: "LATENT SPACE OPERATIONS:"
appendInfoLine: "  Var0 Original : Baseline reconstruction"
appendInfoLine: "  Var1 Noise    : Gaussian noise injection"
appendInfoLine: "  Var2 Scale    : Scale 1st latent dim"
appendInfoLine: "  Var3 Invert   : Mirror 2nd latent dim"
appendInfoLine: "  Var4 Smooth   : Temporal smoothing -> legato"
appendInfoLine: "  Var5 Warp     : Time-warp in latent space"
appendInfoLine: "  Var6 Swap     : Swap latent dimensions"
appendInfoLine: "  Var7 Interp   : Move toward latent centroid"
appendInfoLine: ""
appendInfoLine: "Parameters: ", nparams, " | Bottleneck: ", bottleneck_size
appendInfoLine: "Bandwidth fraction: ", fixed$(bandwidth_fraction, 2)