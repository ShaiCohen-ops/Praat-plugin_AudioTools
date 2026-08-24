# ============================================================
# Praat AudioTools - Parametric_Autoencoder_Resynthesis_with_Variations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True autoencoder with latent space perturbation for novel variations.
#   Uses KlattGrid source-filter synthesis to render independent F0 and
#   F1-F4 trajectories. Dynamic voicing amplitude for natural silence.
#
# Changelog v1.2 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; analysis, network training,
#     latent transforms, KlattGrid synthesis and output rendering are unchanged.
#   - Standardized both visualization modes (Network and Latent and outputs)
#     to the Praat AudioTools 8-inch page convention with explicit inner
#     viewports, suite-standard header, typography, neutral colours,
#     summary strip and full-page export viewport.
#   - The variation page height now expands dynamically with the number
#     of output rows instead of compressing or clipping the grid.
#   - Added draw-safe source names and clearer measured/model summaries.
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

form Parametric Autoencoder v1.2
    choice Preset_selection: 1
        button Clean - Dynamic Amplitude - 6 Params
        button Glitch - Constant Drone - 5 Params
    positive Time_step 0.01
    natural Bottleneck_size 3
    natural Epochs 150
    integer Num_variations 7
    positive Pitch_floor 60
    positive Pitch_ceiling 500
    positive Voicing_threshold 0.4
    positive Latent_noise 0.15
    positive Bandwidth_fraction 0.1
    positive Aspiration_during_unvoiced 20
    real Spectral_tilt_dB 20
    real Breathiness_dB 25
    real Flutter 0.3
    optionmenu Intensity_mapping: 1
        option Preserve dB contour
        option Expand to full Klatt range
    optionmenu Protect_mode: 1
        option Baseline only
        option All variations
        option Disabled
    optionmenu Output_level_mode: 2
        option Preserve decoded amplitude
        option Conditional limiter
        option Normalize all variations
    optionmenu Visualization: 2
        option None
        option Network
        option Latent and outputs
    integer Random_seed 0
endform

# Output_level_mode decides whether the Intensity dimension is a real
# musical parameter (1, 2) or only a within-file contour (3). v0.9
# always normalised, so a latent change that lowered the whole
# amplitude trajectory was pushed straight back up.
# Var0 is a BASELINE RECONSTRUCTION, not the original: encoder from the
# autoencoder, then a SEPARATELY TRAINED secondary decoder, then
# KlattGrid. Its reconstruction error is reported.
# Random_seed 0 = unpredictable. Output is mono.
draw_network = 0
draw_visualization = 0
if visualization = 2
    draw_network = 1
elsif visualization = 3
    draw_visualization = 1
endif

# ============================================
# VALIDATION  (v1.0)
# ============================================
if time_step <= 0.0005
    time_step = 0.0005
    appendInfoLine: "  ! Time_step too small -> 0.5 ms"
endif
if bottleneck_size < 1
    bottleneck_size = 1
endif

if epochs < 1
    epochs = 1
endif
if num_variations < 0
    num_variations = 0
endif
if pitch_floor >= pitch_ceiling
    pitch_floor = 60
    pitch_ceiling = 500
    appendInfoLine: "  ! Pitch_floor >= Pitch_ceiling -> reset to 60 / 500"
endif
if voicing_threshold <= 0 or voicing_threshold >= 1
    voicing_threshold = 0.4
    appendInfoLine: "  ! Voicing_threshold must be strictly between 0 and 1 -> 0.4"
endif
if bandwidth_fraction <= 0
    bandwidth_fraction = 0.1
endif
if spectral_tilt_dB < 0
    spectral_tilt_dB = 0
endif
if breathiness_dB < 0
    breathiness_dB = 0
endif
if flutter < 0
    flutter = 0
endif
if flutter > 1
    flutter = 1
endif



# ===== PRESET LOGIC =====
if preset_selection = 1
    presetName$ = "Clean"
    nparams = 6
else
    presetName$ = "Glitch"
    nparams = 5
endif

# v1.1: a "bottleneck" at or above nparams is an OVERCOMPLETE layer,
# not a bottleneck - nothing is forced through a narrower space.
if bottleneck_size >= nparams
    bottleneck_size = nparams - 1
    if bottleneck_size < 1
        bottleneck_size = 1
    endif
    appendInfoLine: "  ! Bottleneck_size >= parameter count is not a bottleneck -> ",
        ... bottleneck_size
endif

clearinfo
writeInfoLine: "=== Parametric Autoencoder v1.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Parameters: ", nparams, " | Bottleneck: ", bottleneck_size
appendInfoLine: ""

selectObject: sound_orig
Resample: 44100, 50
sound = selected()

# v1.0 CRITICAL 4: reject silence, and stop amplifying at a hard
# threshold. v0.9 normalised anything below 30 dB SPL - and since
# Intensity is one of the TRAINED parameters, that amplification did
# not just change output gain, it changed the data the autoencoder
# learned. Material at 29.9 dB and 30.1 dB were treated completely
# differently. A silent input was worse still: F0 -> 0, formants ->
# the canonical fallback, a 120 Hz pitch fallback, Glitch's constant
# 90 dB voicing, and a final normalise to 0.95 - silence became a loud
# drone.
selectObject: sound
srcPeakChk = Get absolute extremum: 0, 0, "None"
if srcPeakChk < 1e-5
    exitScript: "The selected Sound is silent (or near-silent); there is nothing to encode."
endif
# v1.1: seeded AFTER the silent-input check. v1.0 seeded first, so a
# rejected input left Praat globally predictable.
# v1.0: Both networks are initialised and trained
# stochastically, so v0.9's Var0 could differ between runs even before
# any perturbation, and the variations were never recoverable.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

selectObject: sound
intensity_check = Get intensity (dB)
appendInfoLine: "Sound intensity: ", fixed$(intensity_check, 2), " dB"
if intensity_check < 30
    appendInfoLine: "  Note: quiet input (", fixed$(intensity_check, 1),
        ... " dB). NOT amplified - Intensity is a trained parameter, so"
    appendInfoLine: "  changing the gain would change what the model learns."
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

formantValid# = zero#(num_frames)
haveLastFormant = 0
lastF1 = 500
lastF2 = 1500
lastF3 = 2500
lastF4 = 3500

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
    
    # v1.0 CRITICAL 3: 500 / 1500 / 2500 / 3500 Hz is not "missing" -
    # it is a perfectly plausible synthetic vowel. In Clean, an
    # unvoiced region's aspiration then passed through a canonical
    # vowel filter; in Glitch, where voicing amplitude is held at
    # 90 dB, any region without formants became a drone with textbook
    # formants. CLEAN now holds the last VALID measurement (and
    # back-fills the head from the first valid one), so undefined
    # regions inherit real neighbouring colour instead of an invented
    # vowel. GLITCH keeps the canonical quartet, which is a deliberate
    # "synthetic vowel completion" and part of that preset's sound.
    formantValid#[frameIdx] = 1
    if f1 = undefined or f2 = undefined or f3 = undefined or f4 = undefined
        formantValid#[frameIdx] = 0
        if preset_selection = 1 and haveLastFormant = 1
            f1 = lastF1
            f2 = lastF2
            f3 = lastF3
            f4 = lastF4
        else
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
        endif
    else
        haveLastFormant = 1
        lastF1 = f1
        lastF2 = f2
        lastF3 = f3
        lastF4 = f4
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

# v1.1: BACK-FILL the head. v1.0's comment claimed this and the code
# only ever held the LAST valid measurement, so before the first valid
# formant haveLastFormant was 0 and Clean still wrote the canonical
# 500/1500/2500/3500 quartet - an artificial vowel at exactly the
# place a file is most likely to start with silence or noise.
if preset_selection = 1
    firstValid = 0
    for bfIdx from 1 to num_frames
        if firstValid = 0
            fvHere = formantValid#[bfIdx]
            if fvHere = 1
                firstValid = bfIdx
            endif
        endif
    endfor
    if firstValid > 1
        selectObject: param_matrix
        bf1 = Get value in cell: 2, firstValid
        selectObject: param_matrix
        bf2 = Get value in cell: 3, firstValid
        selectObject: param_matrix
        bf3 = Get value in cell: 4, firstValid
        selectObject: param_matrix
        bf4 = Get value in cell: 5, firstValid
        for bfIdx from 1 to firstValid - 1
            selectObject: param_matrix
            Set value: 2, bfIdx, bf1
            Set value: 3, bfIdx, bf2
            Set value: 4, bfIdx, bf3
            Set value: 5, bfIdx, bf4
        endfor
        appendInfoLine: "  Back-filled ", firstValid - 1,
            ... " leading frame(s) from the first valid formant measurement"
    endif
endif

# ===== 3. NORMALIZE =====
appendInfoLine: "Normalizing..."
Create simple Matrix: "ParamMins", nparams, 1, "0"
mins_mat = selected()
Create simple Matrix: "ParamMaxs", nparams, 1, "0"
maxs_mat = selected()

realRange# = zero#(nparams)
isConstantParam# = zero#(nparams)

# v1.1: "constant enough to be worth protecting", per parameter type.
# Edit these if your material needs different tolerances.
constThreshF0 = 2.0
constThreshFmt = 15.0
constThreshInt = 1.5

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
    # v1.0 CRITICAL 1: remember the REAL range before inventing one.
    # A dimension with no variance was given an artificial 1-unit span
    # so the 0-1 normalisation would not divide by zero - but nothing
    # downstream knew the span was fabricated, and for Intensity the
    # decode maps that 1 dB straight onto Klatt's full 0-90 dB. A 0.05
    # decoder output on a source with NO dynamics became 4.5 dB of
    # amplitude; 0.50 became 45 dB. Measured, from a constant 70 dB
    # source:  0.05 -> 4.50 dB, 0.25 -> 22.50, 0.50 -> 45.00,
    #          0.90 -> 81.00, 1.00 -> 90.00.
    # v1.1: MUSICAL thresholds, not a numeric epsilon. 1e-9 only caught
    # an exactly flat parameter; a source whose intensity moves 0.2 dB
    # was still stretched across Klatt's full 0-90 dB, and a formant
    # wobbling by a few Hz of measurement noise filled the whole 0-1
    # training range and carried the same weight as a dimension that
    # genuinely moved.
    realRange#[p] = pmax - pmin
    isConstantParam#[p] = 0
    if p = 1
        constThresh = constThreshF0
    elsif p <= 5
        constThresh = constThreshFmt
    else
        constThresh = constThreshInt
    endif
    if pmax - pmin < constThresh
        isConstantParam#[p] = 1
        pmax = pmin + 1
    endif
    selectObject: mins_mat
    Set value: p, 1, pmin
    selectObject: maxs_mat
    Set value: p, 1, pmax
endfor

nConstParams = 0
constList$ = ""
for p from 1 to nparams
    if isConstantParam#[p] = 1
        nConstParams = nConstParams + 1
        constList$ = constList$ + " " + string$(p)
    endif
endfor
if nConstParams > 0
    appendInfoLine: "  ", nConstParams, " parameter(s) constant in the source:",
        ... constList$
    appendInfoLine: "    Their decoded output is replaced by the original constant,"
    appendInfoLine: "    so decoder noise cannot invent dynamics that were never there."
endif

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

    pageHeight = 7.45
    Erase all
    Line width: 1
    Select outer viewport: 0, 8, 0, pageHeight

    vizSoundName$ = replace$(sound_name$, "_", "\_ ", 0)

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Parametric Autoencoder v1.2 - Network##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizSoundName$ + " | " + presetName$ + " | " + string$(nparams) + " params -> " + string$(bottleneck_size) + " latent -> " + string$(nparams) + " params | " + string$(epochs) + " epochs"

    # === Autoencoder topology ===
    Select outer viewport: 0, 4, 0.70, 3.35
    Select inner viewport: 0.60, 3.85, 0.96, 3.13
    selectObject: autoencoder
    Draw topology
    Select outer viewport: 0, 4, 0.70, 3.35
    Select inner viewport: 0.60, 3.85, 0.72, 0.94
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Autoencoder topology##  " + string$(nparams) + " -> " + string$(bottleneck_size) + " -> " + string$(nparams)

    # === Decoder topology ===
    Select outer viewport: 4, 8, 0.70, 3.35
    Select inner viewport: 4.45, 7.70, 0.96, 3.13
    selectObject: decoder
    Draw topology
    Select outer viewport: 4, 8, 0.70, 3.35
    Select inner viewport: 4.45, 7.70, 0.72, 0.94
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Decoder##  " + string$(bottleneck_size) + " -> " + string$(nparams)

    # === Encoder weights ===
    Select outer viewport: 0, 4, 3.55, 6.35
    Select inner viewport: 0.60, 3.85, 3.86, 6.13
    selectObject: autoencoder
    Draw weights: 1, "yes"
    Select outer viewport: 0, 4, 3.55, 6.35
    Select inner viewport: 0.60, 3.85, 3.57, 3.82
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Encoder weights##  Input -> Latent"

    # === Decoder weights ===
    Select outer viewport: 4, 8, 3.55, 6.35
    Select inner viewport: 4.45, 7.70, 3.86, 6.13
    selectObject: decoder
    Draw weights: 1, "yes"
    Select outer viewport: 4, 8, 3.55, 6.35
    Select inner viewport: 4.45, 7.70, 3.57, 3.82
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Decoder weights##  Latent -> Output"

    # === Summary strip ===
    Select outer viewport: 0, 8, 6.55, 7.40
    Select inner viewport: 0.60, 7.70, 6.63, 7.32
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    netSummary1$ = "##Input##  " + vizSoundName$ + " | preset " + presetName$ + " | " + string$(nparams) + " normalized synthesis parameters"
    netSummary2$ = "##Architecture##  encoder " + string$(nparams) + " -> " + string$(bottleneck_size) + " | secondary decoder " + string$(bottleneck_size) + " -> " + string$(nparams) + " | " + string$(epochs) + " epochs"
    netSummary3$ = "##Latent##  range [" + fixed$(latent_min, 2) + ", " + fixed$(latent_max, 2) + "] | requested outputs " + string$(num_variations + 1) + " including baseline reconstruction"
    Text: 0.02, "left", 0.78, "half", netSummary1$
    Text: 0.02, "left", 0.50, "half", netSummary2$
    Text: 0.02, "left", 0.22, "half", netSummary3$
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
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
        var_name$ = "Baseline"
        appendInfoLine: "  Var0: Baseline reconstruction (encoder + secondary decoder, no perturbation)"
        
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

    # v1.0 CRITICAL 2: measure the BASELINE. Var0 is not the original
    # and not even the first autoencoder's reconstruction - it is
    # encoder -> SEPARATELY TRAINED secondary decoder -> KlattGrid, so
    # a difference from the source can come from the latent bottleneck,
    # from the second decoder, or from the parameter-to-audio step.
    # Without this number there is no way to tell whether Var1-Var7 are
    # variations of a good representation or of a poor one. Computed in
    # NORMALISED parameter space, before denormalisation, and reported
    # per dimension group.
    if var_num = 0
        sumSqAll = 0
        cntAll = 0
        sumSqF0 = 0
        cntF0 = 0
        sumSqFmt = 0
        cntFmt = 0
        sumSqInt = 0
        cntInt = 0
        for p from 1 to nparams
            for c from 1 to num_frames
                selectObject: recon_matrix
                rv = Get value in cell: p, c
                selectObject: norm_matrix
                tv = Get value in cell: p, c
                dv = rv - tv
                sumSqAll = sumSqAll + dv * dv
                cntAll = cntAll + 1
                if p = 1
                    sumSqF0 = sumSqF0 + dv * dv
                    cntF0 = cntF0 + 1
                elsif p <= 5
                    sumSqFmt = sumSqFmt + dv * dv
                    cntFmt = cntFmt + 1
                else
                    sumSqInt = sumSqInt + dv * dv
                    cntInt = cntInt + 1
                endif
            endfor
        endfor
        baselineMSE = sumSqAll / max(cntAll, 1)
        appendInfoLine: ""
        appendInfoLine: "  Baseline reconstruction error (normalised parameter space):"
        appendInfoLine: "    overall MSE : ", fixed$(baselineMSE, 6),
            ... "   (RMSE ", fixed$(sqrt(baselineMSE), 5), " of a 0-1 range)"
        appendInfoLine: "    F0          : ", fixed$(sumSqF0 / max(cntF0, 1), 6)
        appendInfoLine: "    F1-F4       : ", fixed$(sumSqFmt / max(cntFmt, 1), 6)
        if cntInt > 0
            appendInfoLine: "    Intensity   : ", fixed$(sumSqInt / max(cntInt, 1), 6)
        endif
        appendInfoLine: "    [RAW secondary-decoder error, before constant-dimension"
        appendInfoLine: "     protection - this describes the MODEL]"
        appendInfoLine: ""
    endif

    
    # === DENORMALIZE ===
    # v0.8: Single Formula instead of nparams * nReconCols * 2 Get/Set calls.
    # Reads pmin/pmax from mins_mat/maxs_mat indexed by row.
    selectObject: recon_matrix
    nReconCols = Get number of columns
    Formula: "self * (object[" + maxs_str$ + ", row, 1] - object[" + mins_str$ + ", row, 1]) + object[" + mins_str$ + ", row, 1]"
    
    # ===== KLATTGRID SYNTHESIS =====
    # v1.1 CRITICAL: this MUST run before the KlattGrid is built.
    # v1.0 placed it after the pitch and formant tiers were already
    # written, so pinning only ever reached Intensity - a constant F0
    # or a constant formant still got the decoder's wobble into the
    # output. Order is now: decode -> denormalise -> protect -> pitch
    # -> formants -> amplitude -> synthesise.
    #
    # protect_mode: 1 = baseline only (Var0 is a faithful
    # reconstruction, variations are free to move), 2 = every
    # variation, 3 = off. Pinning ALL variations on a steady source
    # can lock F0 and all four formants at once and leave Var1-Var7
    # nearly identical - correct engineering, but it can also empty
    # out the latent space, so it is a choice.
    doProtect = 0
    if protect_mode = 2
        doProtect = 1
    elsif protect_mode = 1 and var_num = 0
        doProtect = 1
    endif
    if doProtect
        for p from 1 to nparams
            if isConstantParam#[p] = 1
                selectObject: mins_mat
                constVal = Get value in cell: p, 1
                selectObject: recon_matrix
                for frameIdx from 1 to num_frames
                    Set value: p, frameIdx, constVal
                endfor
            endif
        endfor
    endif

    # v1.1: the DELIVERED baseline error, measured after protection.
    # v1.0 reported only the pre-protection figure, so a pinned
    # dimension the decoder had put at 0.5 still contributed 0.25 to a
    # number describing a result that no longer contained it. Both are
    # now reported: the raw one describes the model, this one describes
    # what the user actually receives. Computed in denormalised units
    # rescaled back to 0-1 so the two are comparable.
    if var_num = 0
        sumSqDel = 0
        cntDel = 0
        for p from 1 to nparams
            selectObject: mins_mat
            pmn = Get value in cell: p, 1
            selectObject: maxs_mat
            pmx = Get value in cell: p, 1
            spanP = pmx - pmn
            if spanP < 1e-12
                spanP = 1
            endif
            for c from 1 to num_frames
                selectObject: recon_matrix
                rv = Get value in cell: p, c
                selectObject: norm_matrix
                tv = Get value in cell: p, c
                dv = (rv - pmn) / spanP - tv
                sumSqDel = sumSqDel + dv * dv
                cntDel = cntDel + 1
            endfor
        endfor
        deliveredMSE = sumSqDel / max(cntDel, 1)
        appendInfoLine: "  Delivered baseline MSE (after protection): ",
            ... fixed$(deliveredMSE, 6), "   [describes the OUTPUT]"
        appendInfoLine: ""
    endif

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
        # v1.0 CRITICAL 1: map amplitude from the REAL range. If the
        # source had no dynamics the whole file sits at one amplitude,
        # which is what the source did.
        int_range = realRange#[6]
        constIntensity = isConstantParam#[6]
        if int_range < 1e-9
            int_range = 1
        endif
        
        for frameIdx from 1 to num_frames
            t = start_time + (frameIdx - 1) * dt
            selectObject: recon_matrix
            f0_val = Get value in cell: 1, frameIdx
            int_val = Get value in cell: 6, frameIdx
            
            if constIntensity = 1
                # a flat source gets a flat, mid-scale amplitude
                amp = 60
            elsif intensity_mapping = 1
                # v1.1: PRESERVE the dB contour. Stretching whatever
                # range happens to be present onto 0-90 turns a 1 dB
                # source into full-scale pumping; this keeps the
                # source's own dB differences, anchored so the loudest
                # frame reaches 90.
                amp = 90 - (int_max - int_val)
                if amp < 0
                    amp = 0
                endif
            else
                amp = 90 * (int_val - int_min) / int_range
            endif
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
    # v1.0 CRITICAL 5: output level is a choice. v0.9 always ran
    # Scale peak: 0.95, so a latent change that lowered the whole
    # amplitude trajectory was pushed straight back up - the Intensity
    # dimension controlled only the relative contour inside a file,
    # never the loudness of the variation.
    if output_level_mode = 3
        Scale peak: 0.95
    else
        varPeakNow = Get absolute extremum: 0, 0, "None"
        if output_level_mode = 2 and varPeakNow > 0.95
            Scale peak: 0.95
        elsif varPeakNow > 0.99
            Scale peak: 0.99
        endif
    endif
    
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

    grid_cols = 4
    grid_rows = (n_outputs + grid_cols - 1) div grid_cols
    panel_h = 1.05
    grid_y0 = 2.82
    grid_y1 = grid_y0 + grid_rows * panel_h
    summary_y0 = grid_y1 + 0.22
    summary_y1 = summary_y0 + 0.90
    pageHeight = summary_y1 + 0.05

    Erase all
    Select outer viewport: 0, 8, 0, pageHeight

    vizSoundName$ = replace$(sound_name$, "_", "\_ ", 0)

    if intensity_mapping = 1
        intensityDesc$ = "preserve dB contour"
    else
        intensityDesc$ = "expand to full Klatt range"
    endif

    if protect_mode = 1
        protectDesc$ = "protect baseline"
    elsif protect_mode = 2
        protectDesc$ = "protect all variations"
    else
        protectDesc$ = "protection disabled"
    endif

    if output_level_mode = 1
        levelDesc$ = "preserve decoded amplitude"
    elsif output_level_mode = 2
        levelDesc$ = "conditional limiter"
    else
        levelDesc$ = "normalize all variations"
    endif

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Parametric Autoencoder v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizSoundName$ + " | " + presetName$ + " | " + string$(nparams) + " params -> " + string$(bottleneck_size) + " latent | " + string$(n_outputs) + " outputs"

    # === Original waveform ===
    Select outer viewport: 0, 8, 0.66, 1.54
    Select inner viewport: 0.60, 7.70, 0.78, 1.37
    selectObject: sound_orig
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Source Sound"

    # === Latent-space heatmap ===
    Select outer viewport: 0, 8, 1.70, 2.60
    Select inner viewport: 0.60, 7.70, 1.83, 2.43
    selectObject: hidden_matrix
    latent_t = Transpose
    Paint cells: 0, 0, 0, 0
    removeObject: latent_t
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Latent (" + string$(bottleneck_size) + "d)"
    Text top: "no", "Latent Activations | time ->"

    # === Variation waveform grid ===
    grid_x0 = 0.0
    grid_x1 = 8.0
    panel_w = (grid_x1 - grid_x0) / grid_cols

    for v from 1 to n_outputs
        var_idx_zero = v - 1
        if var_idx_zero = 0
            label$ = "Var0 Baseline recon"
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

        # Keep an explicit gutter inside every cell.
        Select outer viewport: px0, px1, py0, py1
        Select inner viewport: px0 + 0.18, px1 - 0.12, py0 + 0.22, py1 - 0.12
        selectObject: outputIDs#[v]

        if var_idx_zero = 0
            Colour: "{0.25, 0.45, 0.75}"
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
        Draw inner box

        # Label in a dedicated top strip so it cannot collide with the waveform.
        Select outer viewport: px0, px1, py0, py1
        Select inner viewport: px0 + 0.18, px1 - 0.12, py0 + 0.02, py0 + 0.20
        Axes: 0, 1, 0, 1
        Font size: 6
        Colour: "{0.25, 0.25, 0.35}"
        Text: 0.02, "left", 0.5, "half", label$
    endfor

    # === Summary strip ===
    Select outer viewport: 0, 8, summary_y0, summary_y1
    Select inner viewport: 0.60, 7.70, summary_y0 + 0.08, summary_y1 - 0.08
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Model##  " + presetName$ + " | " + string$(nparams) + " params -> " + string$(bottleneck_size) + " latent -> " + string$(nparams) + " params | " + string$(epochs) + " epochs"
    summary2$ = "##Latent & reconstruction##  range [" + fixed$(latent_min, 2) + ", " + fixed$(latent_max, 2) + "] | baseline MSE " + fixed$(baselineMSE, 6) + " | " + protectDesc$
    summary3$ = "##Synthesis & output##  " + string$(n_outputs) + " outputs | " + intensityDesc$ + " | " + levelDesc$ + " | KlattGrid source-filter"
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
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
# v1.1: hand the generator back. v1.0 seeded and never reset.
random_initializeSafelyAndUnpredictably ()

appendInfoLine: "  Var0 Baseline : encoder + secondary decoder, no perturbation"
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