# ============================================================
# Praat AudioTools - Neural_Adaptive_Phonetic_Vibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed syntax
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Neural Phonetic Vibrato - Applies stereo vibrato to vowels
#   while keeping consonants clean for intelligibility.
#
# Changelog v0.3:
#   - Fixed preset comparison (number not string)
#   - Fixed == to = operator
#   - Fixed call to @ procedure syntax
#   - Fixed inline if statements
#   - Added preset names
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

form Neural Phonetic Vibrato v0.3
    comment === PRESETS ===
    optionmenu Preset: 1
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
writeInfoLine: "=== Neural Phonetic Vibrato v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sound: ", sound_name$
appendInfoLine: ""

# ============================================
# ANALYSIS (BATCH)
# ============================================
appendInfoLine: "Analyzing audio features..."

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
# CATEGORIZATION
# ============================================
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

selectObject: raw_data
for i from 1 to rows_target
    int_val = Get value: i, 1
    hnr_val = Get value: i, 2
    f0_val  = Get value: i, 3
    f1_val  = Get value: i, 4
    
    selectObject: output_categories
    if int_val < silence_intensity_threshold
        Append category: "silence"
    elsif hnr_val > vowel_hnr_threshold and f0_val > 0 and f1_val > 300
        Append category: "vowel"
    elsif int_val > silence_intensity_threshold and hnr_val < fricative_hnr_max and f0_val = 0
        Append category: "fricative"
    else
        Append category: "other"
    endif
    selectObject: raw_data
endfor
removeObject: raw_data

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
appendInfoLine: "Training Neural Network..."

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
        appendInfoLine: "  Iter: ", total_trained
    endif
endwhile

# ============================================
# INFERENCE & MASKS
# ============================================
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

appendInfoLine: "Generating mixing masks..."

for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    
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
    
    w_vowel = e1 / denom
    w_rest  = (e2 + e3 + e4) / denom

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
@safeRemove: ch_L
@safeRemove: ch_R

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", sound_name$, "_neuralVib_", presetName$

selectObject: final_stereo

if play_result
    Play
endif