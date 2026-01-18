# ============================================================
# Praat AudioTools - Parametric_Autoencoder_Resynthesis_with_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True autoencoder with latent space perturbation for novel variations.
#   Uses KlattGrid source-filter synthesis to render independent F0 and
#   F1-F4 trajectories. Dynamic voicing amplitude for natural silence.
#
# Changelog v0.7:
#   - Fixed output selection (use ID array instead of name)
#   - Added visualization option
#   - Code cleanup
# ============================================================

# === Input Validation ===
if numberOfSelected() <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound_orig = selected()
sound_name$ = selected$("Sound")

form Parametric Autoencoder v0.7
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
writeInfoLine: "=== Parametric Autoencoder v0.7 ==="
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

for p from 1 to nparams
    selectObject: mins_mat
    pmin = Get value in cell: p, 1
    selectObject: maxs_mat
    pmax = Get value in cell: p, 1
    prange = pmax - pmin
    selectObject: norm_matrix
    for frameIdx from 1 to num_frames
        val = Get value in cell: p, frameIdx
        norm_val = (val - pmin) / prange
        Set value: p, frameIdx, norm_val
    endfor
endfor

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
    
    Select outer viewport: 0.5, 5, 0.5, 3
    selectObject: autoencoder
    Draw topology
    Select outer viewport: 0.5, 5, 0.2, 0.7
    Text top: "no", "Encoder: " + string$(nparams) + " -> " + string$(bottleneck_size)

    Select outer viewport: 5.5, 10, 0.5, 3
    selectObject: decoder
    Draw topology
    Select outer viewport: 5.5, 10, 0.2, 0.7
    Text top: "no", "Decoder: " + string$(bottleneck_size) + " -> " + string$(nparams)

    Select outer viewport: 0.5, 5, 4.5, 7.5
    selectObject: autoencoder
    Draw weights: 1, "yes"
    Select outer viewport: 0.5, 5, 4, 4.5
    Text top: "no", "Encoder weights (Input->Latent)"

    Select outer viewport: 5.5, 10, 4.5, 7.5
    selectObject: decoder
    Draw weights: 1, "yes"
    Select outer viewport: 5.5, 10, 4, 4.5
    Text top: "no", "Decoder weights (Latent->Output)"

    Select outer viewport: 0.5, 10, 8, 8.5
    Text top: "no", "Preset: " + presetName$ + " | Params: " + string$(nparams) + " | Latent: " + string$(bottleneck_size)
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
    
    # === VARIATION TYPES ===
    if var_num = 0
        var_name$ = "Original"
        appendInfoLine: "  Var0: Original reconstruction (no perturbation)"
        
    elsif var_num = 1
        var_name$ = "Noise"
        appendInfoLine: "  Var1: Random noise injection in latent space"
        noise_amt = latent_noise * latent_range * 0.3
        selectObject: latent_var
        for ri from 1 to nLatentRows
            for ci from 1 to nLatentCols
                val = Get value in cell: ri, ci
                val = val + randomGauss(0, noise_amt)
                Set value: ri, ci, val
            endfor
        endfor
        
    elsif var_num = 2
        var_name$ = "Scale"
        appendInfoLine: "  Var2: Scale first latent dimension"
        selectObject: latent_var
        for ri from 1 to nLatentRows
            val = Get value in cell: ri, 1
            val = val * 1.3 + 0.1
            Set value: ri, 1, val
        endfor
        
    elsif var_num = 3
        var_name$ = "Invert"
        appendInfoLine: "  Var3: Mirror second latent dimension around mean"
        if bottleneck_size >= 2
            selectObject: latent_var
            dmean = 0
            for ri from 1 to nLatentRows
                val = Get value in cell: ri, 2
                dmean = dmean + val
            endfor
            dmean = dmean / nLatentRows
            for ri from 1 to nLatentRows
                val = Get value in cell: ri, 2
                new_val = 2 * dmean - val
                Set value: ri, 2, new_val
            endfor
        endif
        
    elsif var_num = 4
        var_name$ = "Smooth"
        appendInfoLine: "  Var4: Temporal smoothing in latent space"
        selectObject: latent_var
        for ci from 1 to nLatentCols
            for ri from 2 to nLatentRows - 1
                prev_val = Get value in cell: ri - 1, ci
                curr_val = Get value in cell: ri, ci
                next_val = Get value in cell: ri + 1, ci
                smoothed = (prev_val + curr_val + next_val) / 3
                Set value: ri, ci, smoothed
            endfor
        endfor
        
    elsif var_num = 5
        var_name$ = "Warp"
        appendInfoLine: "  Var5: Time-warping in latent space"
        selectObject: latent_var
        Copy: "LatentWarpTemp"
        warp_temp = selected()
        
        selectObject: latent_var
        for ri from 1 to nLatentRows
            warp_idx = round(1 + (nLatentRows - 1) * ((ri - 1) / max(1, nLatentRows - 1))^1.5)
            if warp_idx < 1
                warp_idx = 1
            endif
            if warp_idx > nLatentRows
                warp_idx = nLatentRows
            endif
            for ci from 1 to nLatentCols
                selectObject: warp_temp
                val = Get value in cell: warp_idx, ci
                selectObject: latent_var
                Set value: ri, ci, val
            endfor
        endfor
        
        selectObject: warp_temp
        Remove
        
    elsif var_num = 6
        var_name$ = "Swap"
        appendInfoLine: "  Var6: Swap latent dimensions"
        if bottleneck_size >= 2
            selectObject: latent_var
            for ri from 1 to nLatentRows
                d1 = Get value in cell: ri, 1
                d2 = Get value in cell: ri, 2
                Set value: ri, 1, d2
                Set value: ri, 2, d1
            endfor
        endif
        
    elsif var_num = 7
        var_name$ = "Interp"
        appendInfoLine: "  Var7: Interpolate toward mean latent"
        selectObject: latent_var
        for ci from 1 to nLatentCols
            dmean = 0
            for ri from 1 to nLatentRows
                val = Get value in cell: ri, ci
                dmean = dmean + val
            endfor
            dmean = dmean / nLatentRows
            for ri from 1 to nLatentRows
                val = Get value in cell: ri, ci
                new_val = 0.6 * val + 0.4 * dmean
                Set value: ri, ci, new_val
            endfor
        endfor
        
    else
        var_name$ = "Var" + string$(var_num)
        appendInfoLine: "  Var", var_num, ": Extra variation (noise)"
        noise_amt = latent_noise * latent_range * 0.2 * var_num
        selectObject: latent_var
        for ri from 1 to nLatentRows
            for ci from 1 to nLatentCols
                val = Get value in cell: ri, ci
                val = val + randomGauss(0, noise_amt)
                Set value: ri, ci, val
            endfor
        endfor
    endif

    # === CLAMP TO [0, 1] ===
    selectObject: latent_var
    for ri from 1 to nLatentRows
        for ci from 1 to nLatentCols
            val = Get value in cell: ri, ci
            if val < 0
                val = 0
            endif
            if val > 1
                val = 1
            endif
            Set value: ri, ci, val
        endfor
    endfor

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
    nReconCols = Get number of columns
    for p from 1 to nparams
        selectObject: mins_mat
        pmin = Get value in cell: p, 1
        selectObject: maxs_mat
        pmax = Get value in cell: p, 1
        prange = pmax - pmin
        selectObject: recon_matrix
        for frameIdx from 1 to nReconCols
            val = Get value in cell: p, frameIdx
            denorm_val = val * prange + pmin
            Set value: p, frameIdx, denorm_val
        endfor
    endfor
    
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
    
    # --- AMPLITUDE LOGIC ---
    selectObject: klatt
    Remove voicing amplitude points: start_time, end_time
    Remove aspiration amplitude points: start_time, end_time

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
            else
                Add voicing amplitude point: t, 0
                Add aspiration amplitude point: t, aspiration_during_unvoiced
            endif
        endfor
        
    else
        # === GLITCH (Constant Drone) ===
        selectObject: klatt
        Add voicing amplitude point: start_time, 90
        Add voicing amplitude point: end_time, 90
        Add aspiration amplitude point: start_time, 0
        Add aspiration amplitude point: end_time, 0
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
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Parametric Autoencoder: " + sound_name$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: sound_orig
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # First variation waveform
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: outputIDs#[1]
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Var0"
    Text bottom: "yes", "Time (s)"
    
    # Stats
    Select outer viewport: 0, 8, 2.9, 3.5
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.2, "centre", 0.5, "half", "Params: " + string$(nparams)
    Text: 0.4, "centre", 0.5, "half", "Bottleneck: " + string$(bottleneck_size)
    Text: 0.6, "centre", 0.5, "half", "Epochs: " + string$(epochs)
    Text: 0.8, "centre", 0.5, "half", "Variations: " + string$(num_variations + 1)
    
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