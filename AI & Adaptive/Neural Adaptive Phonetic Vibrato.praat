# ============================================================
# Praat AudioTools - Neural_Adaptive_Phonetic_Vibrato.praat
# Author: Shai Cohen (Enhanced by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025) - Enhanced with Visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Phonetic Vibrato - Applies stereo vibrato to vowels
#   while keeping consonants clean for intelligibility.
#   
#   Pipeline:
#   1. Extract 18D phonetic features (MFCC, formants, pitch, HNR)
#   2. Label frames using acoustic rules (vowel/fricative/silence/other)
#   3. Train FFNet (24 hidden units) to predict categories
#   4. Infer mixing weights via softmax with adaptive voicing boost
#   5. Apply stereo vibrato (180° phase offset) to vowel regions only
#
# Improvements in v1.0:
#   - 6-panel comprehensive visualization
#   - Category statistics and distribution
#   - Feature space clustering display
#   - Mixing mask timeline
#   - Softmax confidence visualization
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

form Neural Phonetic Vibrato v1.0 (Enhanced)
    comment === PRESETS ===
    optionmenu Preset 1
        option Manual
        option Lush Chorus
        option Wide & Slow
        option Nervous Shimmer
        option Subtle Thickener
        option Dreamy Wash
    comment === Vowel Effect (Stereo Vibrato) ===
    positive Vibrato_rate_hz 6.0
    positive Vibrato_depth_ms 2.5
    comment === Neural Mixing ===
    positive Confidence_threshold 0.15
    positive Temperature 0.45
    positive Voiced_boost 0.4
    comment === Output ===
    real Stereo_width 0.9
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================
# PRESET LOGIC
# ============================================
if preset = 2
    # Lush Chorus
    vibrato_rate_hz = 6.0
    vibrato_depth_ms = 2.5
    confidence_threshold = 0.15
    temperature = 0.45
    stereo_width = 0.9
    presetName$ = "LushChorus"
elsif preset = 3
    # Wide & Slow
    vibrato_rate_hz = 2.5
    vibrato_depth_ms = 5.0
    confidence_threshold = 0.10
    temperature = 0.5
    stereo_width = 1.0
    presetName$ = "WideSlow"
elsif preset = 4
    # Nervous Shimmer
    vibrato_rate_hz = 8.5
    vibrato_depth_ms = 1.5
    confidence_threshold = 0.15
    temperature = 0.4
    stereo_width = 0.7
    presetName$ = "NervousShimmer"
elsif preset = 5
    # Subtle Thickener
    vibrato_rate_hz = 5.0
    vibrato_depth_ms = 1.2
    confidence_threshold = 0.25
    temperature = 0.6
    stereo_width = 0.5
    presetName$ = "SubtleThickener"
elsif preset = 6
    # Dreamy Wash
    vibrato_rate_hz = 4.0
    vibrato_depth_ms = 4.0
    confidence_threshold = 0.05
    temperature = 0.8
    stereo_width = 1.0
    presetName$ = "DreamyWash"
else
    presetName$ = "Manual"
endif

# ============================================
# SETTINGS
# ============================================
training_iterations = 1000
train_chunk = 100
learning_rate = 0.001

hidden_units = 24
frame_step_seconds = 0.01
max_formant_hz = 5500
vowel_hnr_threshold = 5.0
fricative_hnr_max = 3.0
silence_intensity_threshold = 45

# ============================================
# INIT & MONO CONVERSION
# ============================================
selectObject: original
duration = Get total duration

if duration < frame_step_seconds
    exitScript: "Error: Sound duration too short."
endif

selectObject: original
sound = Convert to mono
Rename: "Analysis_Copy"
sound_work = selected("Sound")

clearinfo
writeInfoLine: "=== Neural Phonetic Vibrato v1.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sound: ", sound_name$
appendInfoLine: ""
appendInfoLine: "Neural Network Architecture:"
appendInfoLine: "  Input: 18 features (MFCC, formants, pitch, HNR)"
appendInfoLine: "  Hidden: ", hidden_units, " units"
appendInfoLine: "  Output: 4 categories (vowel, fricative, silence, other)"
appendInfoLine: ""

# ============================================
# ANALYSIS (BATCH)
# ============================================
appendInfoLine: "Step 1: Extracting phonetic features..."

selectObject: sound_work
To Pitch: 0, 75, 600
pitch = selected("Pitch")

selectObject: sound_work
To Intensity: 75, 0, "yes"
intensity = selected("Intensity")

selectObject: sound_work
To Formant (burg): 0, 5, max_formant_hz, 0.025, 50
formant = selected("Formant")

selectObject: sound_work
To MFCC: 12, 0.025, frame_step_seconds, 100, 100, 0
mfcc = selected("MFCC")

selectObject: sound_work
To Harmonicity (cc): frame_step_seconds, 75, 0.1, 1.0
harmonicity = selected("Harmonicity")

selectObject: mfcc
nFrames = Get number of frames
rows_target = nFrames
n_features = 18

appendInfoLine: "  Extracted ", rows_target, " frames x ", n_features, " features"

# ============================================
# FEATURE MATRIX
# ============================================
Create TableOfReal: "features", rows_target, n_features
feature_matrix = selected("TableOfReal")

# 1. MFCC
selectObject: mfcc
for i from 1 to rows_target
    for c from 1 to 12
        v = Get value in frame: i, c
        if v = undefined
            v = 0
        endif
        # Calculate column index
        if c <= 3
            col_idx = c
        else
            col_idx = 9 + c - 3
        endif
        selectObject: feature_matrix
        Set value: i, col_idx, v
        selectObject: mfcc
    endfor
endfor

# 2. Formants
selectObject: formant
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    if f1 = undefined
        f1 = 500
    endif
    if f2 = undefined
        f2 = 1500
    endif
    if f3 = undefined
        f3 = 2500
    endif
    selectObject: feature_matrix
    Set value: i, 4, f1 / 1000
    Set value: i, 5, f2 / 1000
    Set value: i, 6, f3 / 1000
    selectObject: formant
endfor

# 3. Intensity
selectObject: intensity
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: t, "cubic"
    if v = undefined
        v = 60
    endif
    selectObject: feature_matrix
    Set value: i, 7, (v - 60) / 20
    selectObject: intensity
endfor

# 4. Harmonicity
selectObject: harmonicity
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: t, "cubic"
    if v = undefined
        v = 0
    endif
    selectObject: feature_matrix
    Set value: i, 8, v / 20
    selectObject: harmonicity
endfor

# 5. Pitch
selectObject: pitch
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: t, "Hertz", "Linear"
    if v = undefined or v <= 0
        z = 0.5
    else
        z = v / 500
        if z <= 0
            z = 0.5
        endif
    endif
    selectObject: feature_matrix
    Set value: i, 9, z
    selectObject: pitch
endfor

# ============================================
# CATEGORIZATION (Rule-based labels)
# ============================================
appendInfoLine: "Step 2: Labeling frames (rule-based)..."

Create Categories: "output_categories"
output_categories = selected("Categories")

Create TableOfReal: "RawData", rows_target, 4
raw_data = selected("TableOfReal")

selectObject: intensity
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: t, "cubic"
    if v = undefined
        v = -100
    endif
    selectObject: raw_data
    Set value: i, 1, v
    selectObject: intensity
endfor

selectObject: harmonicity
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: t, "cubic"
    if v = undefined
        v = -100
    endif
    selectObject: raw_data
    Set value: i, 2, v
    selectObject: harmonicity
endfor

selectObject: pitch
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: t, "Hertz", "Linear"
    if v = undefined
        v = 0
    endif
    selectObject: raw_data
    Set value: i, 3, v
    selectObject: pitch
endfor

selectObject: formant
for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    v = Get value at time: 1, t, "Hertz", "Linear"
    if v = undefined
        v = 500
    endif
    selectObject: raw_data
    Set value: i, 4, v
    selectObject: formant
endfor

# Count categories
count_vowel = 0
count_fricative = 0
count_silence = 0
count_other = 0

# Store raw feature data for visualization
viz_f1# = zero#(rows_target)
viz_f2# = zero#(rows_target)
viz_category# = zero#(rows_target)

selectObject: raw_data
for i from 1 to rows_target
    int_val = Get value: i, 1
    hnr_val = Get value: i, 2
    f0_val  = Get value: i, 3
    f1_val  = Get value: i, 4
    
    viz_f1#[i] = f1_val
    selectObject: formant
    t = frame_step_seconds * (i - 0.5)
    f2_val = Get value at time: 2, t, "Hertz", "Linear"
    if f2_val = undefined
        f2_val = 1500
    endif
    viz_f2#[i] = f2_val
    
    selectObject: output_categories
    if int_val < silence_intensity_threshold
        Append category: "silence"
        viz_category#[i] = 3
        count_silence += 1
    elsif hnr_val > vowel_hnr_threshold and f0_val > 0 and f1_val > 300
        Append category: "vowel"
        viz_category#[i] = 1
        count_vowel += 1
    elsif int_val > silence_intensity_threshold and hnr_val < fricative_hnr_max and f0_val = 0
        Append category: "fricative"
        viz_category#[i] = 2
        count_fricative += 1
    else
        Append category: "other"
        viz_category#[i] = 4
        count_other += 1
    endif
    selectObject: raw_data
endfor
removeObject: raw_data

appendInfoLine: "  Label distribution:"
appendInfoLine: "    Vowel: ", count_vowel, " (", fixed$(100*count_vowel/rows_target, 1), "%)"
appendInfoLine: "    Fricative: ", count_fricative, " (", fixed$(100*count_fricative/rows_target, 1), "%)"
appendInfoLine: "    Silence: ", count_silence, " (", fixed$(100*count_silence/rows_target, 1), "%)"
appendInfoLine: "    Other: ", count_other, " (", fixed$(100*count_other/rows_target, 1), "%)"

# ============================================
# NORMALIZE
# ============================================
selectObject: feature_matrix
cols = n_features
for j from 1 to cols
    col_min = 1e30
    col_max = -1e30
    for i from 1 to rows_target
        val = Get value: i, j
        if val <> undefined
            if val < col_min
                col_min = val
            endif
            if val > col_max
                col_max = val
            endif
        endif
    endfor
    range = col_max - col_min
    if range = 0
        range = 1
    endif
    for i from 1 to rows_target
        val = Get value: i, j
        if val <> undefined
            norm = (val - col_min) / range
            Set value: i, j, norm
        else
            Set value: i, j, 0
        endif
    endfor
endfor

# ============================================
# TRAINING
# ============================================
appendInfoLine: "Step 3: Training neural network..."

selectObject: feature_matrix
To Matrix
feature_matrix_m = selected("Matrix")
To Pattern: 1
pattern = selected("PatternList")

selectObject: pattern
plusObject: output_categories
To FFNet: hidden_units, 0
ffnet = selected("FFNet")

total_trained = 0

while total_trained < training_iterations
    selectObject: ffnet
    plusObject: pattern
    plusObject: output_categories
    Learn: train_chunk, learning_rate, "Minimum-squared-error"
    total_trained = total_trained + train_chunk
    if total_trained mod 200 = 0
        appendInfoLine: "  Iteration: ", total_trained, "/", training_iterations
    endif
endwhile

appendInfoLine: "  Training complete"

# ============================================
# INFERENCE & MASKS
# ============================================
appendInfoLine: "Step 4: Neural inference and mask generation..."

selectObject: ffnet
plusObject: pattern
To ActivationList: 1
activations = selected("Activation")
To Matrix
activation_matrix = selected("Matrix")

Create IntensityTier: "Mask_Vibrato", 0, duration
mask_vib = selected("IntensityTier")
Create IntensityTier: "Mask_Dry", 0, duration
mask_dry = selected("IntensityTier")

# Store for visualization
viz_w_vowel# = zero#(rows_target)
viz_w_dry# = zero#(rows_target)
viz_time# = zero#(rows_target)
viz_predicted_category# = zero#(rows_target)
viz_softmax# = zero#(rows_target * 4)

for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    viz_time#[i] = t
    
    selectObject: activation_matrix
    a1 = Get value in cell: i, 1
    a2 = Get value in cell: i, 2
    a3 = Get value in cell: i, 3
    a4 = Get value in cell: i, 4
    
    # Softmax
    tdiv = temperature
    if tdiv <= 0.0001
        tdiv = 0.0001
    endif
    max_a = max(a1, max(a2, max(a3, a4)))
    e1 = exp((a1-max_a) / tdiv)
    e2 = exp((a2-max_a) / tdiv)
    e3 = exp((a3-max_a) / tdiv)
    e4 = exp((a4-max_a) / tdiv)
    denom = e1 + e2 + e3 + e4
    if denom <= 0
        denom = 1e-12
    endif
    
    p1 = e1 / denom
    p2 = e2 / denom
    p3 = e3 / denom
    p4 = e4 / denom
    
    # Store softmax for visualization
    viz_softmax#[(i-1)*4 + 1] = p1
    viz_softmax#[(i-1)*4 + 2] = p2
    viz_softmax#[(i-1)*4 + 3] = p3
    viz_softmax#[(i-1)*4 + 4] = p4
    
    # Predicted category (argmax)
    if p1 >= p2 and p1 >= p3 and p1 >= p4
        viz_predicted_category#[i] = 1
    elsif p2 >= p3 and p2 >= p4
        viz_predicted_category#[i] = 2
    elsif p3 >= p4
        viz_predicted_category#[i] = 3
    else
        viz_predicted_category#[i] = 4
    endif
    
    w_vowel = p1
    w_rest  = p2 + p3 + p4

    # Adaptive boost
    selectObject: feature_matrix
    norm_hnr = Get value: i, 8
    norm_f0 = Get value: i, 9
    voicedness = (norm_hnr * 0.5) + (norm_f0 * 0.5) 
    adapt_weight = 1 + voiced_boost * (voicedness - 0.5) * 2
    
    w_vowel = w_vowel * adapt_weight
    
    total = w_vowel + w_rest
    w_vowel = w_vowel / total
    w_dry = 1.0 - w_vowel
    
    viz_w_vowel#[i] = w_vowel
    viz_w_dry#[i] = w_dry
    
    # Prob to dB
    floor_w = 0.001
    if w_vowel < floor_w
        db_vib = -100
    else
        db_vib = 20 * log10(w_vowel)
    endif
    if w_dry < floor_w
        db_dry = -100
    else
        db_dry = 20 * log10(w_dry)
    endif

    selectObject: mask_vib
    Add point: t, db_vib
    selectObject: mask_dry
    Add point: t, db_dry
endfor

# ============================================
# PARALLEL DSP (STEREO VIBRATO)
# ============================================
appendInfoLine: "Step 5: Applying stereo vibrato to vowel regions..."

selectObject: sound_work

vib_depth_sec = vibrato_depth_ms / 1000
vib_rate = vibrato_rate_hz
depthStr$ = string$(vib_depth_sec)
rateStr$ = string$(vib_rate)
soundWorkStr$ = string$(sound_work)

# LEFT CHANNEL (Phase 0)
selectObject: sound_work
Copy: "Vib_Left"
s_vib_L = selected("Sound")
Formula: "Object_" + soundWorkStr$ + "(x + " + depthStr$ + " * sin(2*pi*" + rateStr$ + "*x))"

# RIGHT CHANNEL (Phase 180)
selectObject: sound_work
Copy: "Vib_Right"
s_vib_R = selected("Sound")
Formula: "Object_" + soundWorkStr$ + "(x + " + depthStr$ + " * sin(2*pi*" + rateStr$ + "*x + 3.14159))"

# Dry Track
selectObject: sound_work
Copy: "Dry_Track"
s_dry = selected("Sound")

# ============================================
# APPLY MASKS
# ============================================

selectObject: s_vib_L
plusObject: mask_vib
Multiply
s_vib_L_masked = selected("Sound")
Rename: "Mix_Vib_L"

selectObject: s_vib_R
plusObject: mask_vib
Multiply
s_vib_R_masked = selected("Sound")
Rename: "Mix_Vib_R"

selectObject: s_dry
plusObject: mask_dry
Multiply
s_dry_masked = selected("Sound")
Rename: "Mix_Dry"

# ============================================
# STEREO MIX
# ============================================

vibLStr$ = string$(s_vib_L_masked)
vibRStr$ = string$(s_vib_R_masked)
dryStr$ = string$(s_dry_masked)

selectObject: sound_work
Copy: "Ch_Left"
ch_L = selected("Sound")
Formula: "Object_" + vibLStr$ + "[col] + Object_" + dryStr$ + "[col]"

selectObject: sound_work
Copy: "Ch_Right"
ch_R = selected("Sound")
Formula: "Object_" + vibRStr$ + "[col] + Object_" + dryStr$ + "[col]"

# Stereo Combine
selectObject: ch_L
plusObject: ch_R
Combine to stereo
final_stereo = selected("Sound")
Rename: sound_name$ + "_neuralVib_" + presetName$

# Width control
if stereo_width <> 1
    chLStr$ = string$(ch_L)
    chRStr$ = string$(ch_R)
    widthStr$ = string$(stereo_width)
    monoStr$ = string$(1 - stereo_width)
    selectObject: final_stereo
    Formula: "self * " + widthStr$ + " + (Object_" + chLStr$ + "[col] + Object_" + chRStr$ + "[col])/2 * " + monoStr$
endif

selectObject: final_stereo
Scale peak: 0.99

# Store for visualization
viz_left = ch_L
viz_right = ch_R

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    appendInfoLine: "Step 6: Drawing visualization..."
    
    Erase all
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "Neural Phonetic Vibrato"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.1, "half", sound_name$ + " | " + presetName$ + " | FFNet: 18→24→4"
    
    # === ORIGINAL WAVEFORM ===
    Select outer viewport: 0, 8, 0.6, 1.2
    Select inner viewport: 0.6, 7.7, 0.7, 1.15
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # === RESULT WAVEFORMS (STEREO) ===
    # Left channel
    Select outer viewport: 0, 4, 1.3, 1.9
    Select inner viewport: 0.6, 3.7, 1.4, 1.85
    selectObject: viz_left
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result L"
    
    # Right channel
    Select outer viewport: 4, 8, 1.3, 1.9
    Select inner viewport: 4.4, 7.7, 1.4, 1.85
    selectObject: viz_right
    Colour: "{0.8, 0.5, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Result R"
    Text bottom: "yes", "Time (s)"
    
    # === NEURAL NETWORK PREDICTIONS (Timeline) ===
    Select outer viewport: 0, 8, 2.0, 3.2
    Select inner viewport: 0.6, 7.7, 2.1, 3.1
    
    # Calculate max time for axis
    max_time = duration
    
    Axes: 0, max_time, 0.5, 4.5
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time, 0.5, 4.5
    
    # Define category colors
    cat_colors$# = {"", "", "", ""}
    cat_colors$#[1] = "{0.3, 0.7, 0.3}"  
	# Vowel - green
    cat_colors$#[2] = "{0.9, 0.5, 0.3}"  
	# Fricative - orange
    cat_colors$#[3] = "{0.5, 0.5, 0.5}"  
	# Silence - grey
    cat_colors$#[4] = "{0.6, 0.6, 0.9}"  
	# Other - blue
    
    # Draw predicted categories
    for i from 1 to rows_target
        t = viz_time#[i]
        cat = viz_predicted_category#[i]
        y_pos = cat
        
        Colour: cat_colors$#[cat]
        Paint rectangle: cat_colors$#[cat], t - frame_step_seconds/2, t + frame_step_seconds/2, y_pos - 0.35, y_pos + 0.35
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Category"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Neural Network Predictions"
    
    # Y-axis labels
    Font size: 6
    Text: -0.5, "right", 1, "half", "Vowel"
    Text: -0.5, "right", 2, "half", "Fricative"
    Text: -0.5, "right", 3, "half", "Silence"
    Text: -0.5, "right", 4, "half", "Other"
    
    # === MIXING MASKS (Vibrato vs Dry) ===
    Select outer viewport: 0, 8, 3.3, 4.8
    Select inner viewport: 0.6, 7.7, 3.4, 4.7
    
    Axes: 0, max_time, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time, 0, 1.1
    
    # Draw vibrato weight (red)
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 2
    for i from 1 to rows_target - 1
        Draw line: viz_time#[i], viz_w_vowel#[i], viz_time#[i+1], viz_w_vowel#[i+1]
    endfor
    
    # Draw dry weight (blue)
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 2
    for i from 1 to rows_target - 1
        Draw line: viz_time#[i], viz_w_dry#[i], viz_time#[i+1], viz_w_dry#[i+1]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Weight"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Mixing Masks (Adaptive)"
    
    # === FEATURE SPACE (F1 vs F2) ===
    Select outer viewport: 0, 4, 4.9, 6.7
    Select inner viewport: 0.6, 3.7, 5.0, 6.6
    
    # Find min/max for axes
    min_f1 = 200
    max_f1 = 1200
    min_f2 = 500
    max_f2 = 3000
    
    Axes: min_f1, max_f1, min_f2, max_f2
    Paint rectangle: "{0.97, 0.97, 0.97}", min_f1, max_f1, min_f2, max_f2
    
    # Draw data points (subsample for clarity)
    step = max(1, floor(rows_target / 400))
    for i from 1 to rows_target
        if i mod step = 0
            cat = viz_predicted_category#[i]
            f1 = viz_f1#[i]
            f2 = viz_f2#[i]
            
            if f1 >= min_f1 and f1 <= max_f1 and f2 >= min_f2 and f2 <= max_f2
                Colour: cat_colors$#[cat]
                Paint circle (mm): cat_colors$#[cat], f1, f2, 0.4
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "F2 (Hz)"
    Text bottom: "yes", "F1 (Hz)"
    Text top: "no", "Feature Space (Predicted)"
    
    # === SOFTMAX PROBABILITIES ===
    Select outer viewport: 4, 8, 4.9, 6.7
    Select inner viewport: 4.4, 7.7, 5.0, 6.6
    
    Axes: 0, max_time, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, max_time, 0, 1.05
    
    # Draw softmax probabilities as overlaid lines
    # Vowel probability
    Colour: cat_colors$#[1]
    Line width: 1.5
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 1]
        p_next = viz_softmax#[i*4 + 1]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor
    
    # Fricative probability
    Colour: cat_colors$#[2]
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 2]
        p_next = viz_softmax#[i*4 + 2]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor
    
    # Silence probability
    Colour: cat_colors$#[3]
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 3]
        p_next = viz_softmax#[i*4 + 3]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor
    
    # Other probability
    Colour: cat_colors$#[4]
    for i from 1 to rows_target - 1
        p = viz_softmax#[(i-1)*4 + 4]
        p_next = viz_softmax#[i*4 + 4]
        Draw line: viz_time#[i], p, viz_time#[i+1], p_next
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Probability"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Softmax Confidence"
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 6.8, 7.5
    Select inner viewport: 0, 8, 6.8, 7.5
    Axes: 0, 1, 0, 1
    Font size: 7
    
    Colour: "Black"
    Text: 0.02, "left", 0.75, "half", "Categories:"
    
    # Category legend
    x_pos = 0.15
    Paint rectangle: cat_colors$#[1], x_pos, x_pos + 0.03, 0.65, 0.85
    Text: x_pos + 0.04, "left", 0.75, "half", "Vowel"
    x_pos += 0.12
    
    Paint rectangle: cat_colors$#[2], x_pos, x_pos + 0.03, 0.65, 0.85
    Text: x_pos + 0.04, "left", 0.75, "half", "Fricative"
    x_pos += 0.14
    
    Paint rectangle: cat_colors$#[3], x_pos, x_pos + 0.03, 0.65, 0.85
    Text: x_pos + 0.04, "left", 0.75, "half", "Silence"
    x_pos += 0.12
    
    Paint rectangle: cat_colors$#[4], x_pos, x_pos + 0.03, 0.65, 0.85
    Text: x_pos + 0.04, "left", 0.75, "half", "Other"
    
    # Mixing legend
    Text: 0.52, "left", 0.75, "half", "Mixing:"
    x_pos = 0.62
    
    Colour: "{0.9, 0.3, 0.3}"
    Draw line: x_pos, 0.75, x_pos + 0.03, 0.75
    Colour: "Black"
    Text: x_pos + 0.04, "left", 0.75, "half", "Vibrato"
    x_pos += 0.13
    
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: x_pos, 0.75, x_pos + 0.03, 0.75
    Colour: "Black"
    Text: x_pos + 0.04, "left", 0.75, "half", "Dry"
    
    # Bottom text
    Font size: 6
    Text: 0.02, "left", 0.25, "half", "Phonetic FFNet learns vowel regions → applies stereo vibrato adaptively"
    
    Font size: 10
endif

# ============================================
# CLEANUP
# ============================================
procedure safeRemove: .id
    if .id > 0
        selectObject: .id
        Remove
    endif
endproc

@safeRemove: sound_work
@safeRemove: pitch
@safeRemove: intensity
@safeRemove: formant
@safeRemove: mfcc
@safeRemove: harmonicity
@safeRemove: feature_matrix
@safeRemove: feature_matrix_m
@safeRemove: pattern
@safeRemove: output_categories
@safeRemove: ffnet
@safeRemove: activations
@safeRemove: activation_matrix
@safeRemove: mask_vib
@safeRemove: mask_dry
@safeRemove: s_vib_L
@safeRemove: s_vib_R
@safeRemove: s_dry
@safeRemove: s_vib_L_masked
@safeRemove: s_vib_R_masked
@safeRemove: s_dry_masked

if draw_visualization
    @safeRemove: viz_left
    @safeRemove: viz_right
endif

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", sound_name$, "_neuralVib_", presetName$
appendInfoLine: "Vibrato rate: ", vibrato_rate_hz, " Hz"
appendInfoLine: "Vibrato depth: ", vibrato_depth_ms, " ms"
appendInfoLine: "Stereo width: ", stereo_width

selectObject: final_stereo

if play_result
    Play
endif