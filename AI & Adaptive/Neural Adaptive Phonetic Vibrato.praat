# ============================================================
# Praat AudioTools - Neural Phonetic Vibrato
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
# - Vowels = Lush Stereo Vibrato.
# - Consonants = 100% Dry & Clean (Perfect intelligibility).
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis—Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ============================================================
# Neural Phonetic Vibrato 
# ============================================================

form Neural Phonetic Vibrato (Pure)
    comment === PRESETS ===
    optionmenu Preset 1
        option Manual (Use Settings Below)
        option Lush Chorus (Default)
        option Wide & Slow
        option Nervous Shimmer
        option Subtle Thickener
        option Dreamy Wash

    comment === Vowel Effect (Stereo Vibrato) ===
    positive Vibrato_rate_hz 6.0
    positive Vibrato_depth_ms 2.5
    
    comment === Neural Mixing ===
    # How easily it switches to Vibrato (Lower = More Vibrato)
    positive Confidence_threshold 0.15
    positive Temperature 0.45
    # Boost vibrato intensity on strongly voiced segments
    positive Voiced_boost 0.4
    
    comment === Output ===
    real Stereo_width 0.9
    boolean Play_result 1
endform

# ============================================
# PRESET LOGIC
# ============================================
if preset$ = "Lush Chorus (Default)"
    vibrato_rate_hz = 6.0
    vibrato_depth_ms = 2.5
    confidence_threshold = 0.15
    temperature = 0.45
    stereo_width = 0.9

elsif preset$ = "Wide & Slow"
    vibrato_rate_hz = 2.5
    vibrato_depth_ms = 5.0
    confidence_threshold = 0.10
    temperature = 0.5
    stereo_width = 1.0

elsif preset$ = "Nervous Shimmer"
    vibrato_rate_hz = 8.5
    vibrato_depth_ms = 1.5
    confidence_threshold = 0.15
    temperature = 0.4
    stereo_width = 0.7
    
elsif preset$ = "Subtle Thickener"
    vibrato_rate_hz = 5.0
    vibrato_depth_ms = 1.2
    confidence_threshold = 0.25
    temperature = 0.6
    stereo_width = 0.5

elsif preset$ = "Dreamy Wash"
    vibrato_rate_hz = 4.0
    vibrato_depth_ms = 4.0
    confidence_threshold = 0.05
    temperature = 0.8
    stereo_width = 1.0
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

nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
duration = Get total duration

if duration < frame_step_seconds
    exitScript: "Error: Sound duration too short."
endif

# FORCE MONO for Analysis & Source
selectObject: original
sound = Convert to mono
Rename: "Analysis_Copy"
sound_work = selected("Sound")

# ============================================
# ANALYSIS (BATCH)
# ============================================
writeInfoLine: "Analyzing audio features..."

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
        col_idx = if c <= 3 then c else 9 + c - 3 fi
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

# Fill Temp Table
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
selectObject: raw_data
Remove

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
writeInfoLine: "Training Neural Network (1000 Iterations)..."

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
    if total_trained mod 200 == 0
        appendInfoLine: "Iter: ", total_trained
    endif
endwhile

# ============================================
# INFERENCE & MASKS (LIQUID MIX)
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

writeInfoLine: "Generating Liquid Masks..."

for i from 1 to rows_target
    t = frame_step_seconds * (i - 0.5)
    
    selectObject: activation_matrix
    a1 = Get value in cell: i, 1 
# Vowel
    a2 = Get value in cell: i, 2 
# Fricative
    a3 = Get value in cell: i, 3 
# Other
    a4 = Get value in cell: i, 4 
# Silence
    
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

    # Adaptive boost for Vowel
    selectObject: feature_matrix
    norm_hnr = Get value: i, 8
    norm_f0 = Get value: i, 9
    voicedness = (norm_hnr * 0.5) + (norm_f0 * 0.5) 
    adapt_weight = 1 + voiced_boost * (voicedness - 0.5) * 2
    
    w_vowel = w_vowel * adapt_weight
    
    # MIXING LOGIC:
    # Vowels get Vibrato. Everything else gets DRY.
    # We ensure they sum to 1.0 (roughly) for volume consistency
    
    total = w_vowel + w_rest
    w_vowel = w_vowel / total
    w_dry = 1.0 - w_vowel
    
    # Prob to dB
    floor_w = 0.001
    db_vib = if w_vowel < floor_w then -100 else 20 * log10(w_vowel) fi
    db_dry = if w_dry < floor_w then -100 else 20 * log10(w_dry) fi

    selectObject: mask_vib
    Add point: t, db_vib
    selectObject: mask_dry
    Add point: t, db_dry
endfor

# ============================================
# PARALLEL DSP (PURE STEREO VIBRATO)
# ============================================
selectObject: sound_work

# PREPARE VARIABLES
vib_depth_sec = vibrato_depth_ms / 1000
vib_rate = vibrato_rate_hz

# 1. Stereo Vibrato Tracks (Pitch ONLY)
# LEFT CHANNEL (Phase 0)
selectObject: sound_work
Copy: "Vib_Left"
s_vib_L = selected("Sound")
Formula: "Sound_Analysis_Copy(x + " + string$(vib_depth_sec) + " * sin(2*pi*" + string$(vib_rate) + "*x))"

# RIGHT CHANNEL (Phase 180 / Inverted)
selectObject: sound_work
Copy: "Vib_Right"
s_vib_R = selected("Sound")
Formula: "Sound_Analysis_Copy(x + " + string$(vib_depth_sec) + " * sin(2*pi*" + string$(vib_rate) + "*x + 3.14159))"

# 2. Dry Track (Clean Mono)
selectObject: sound_work
Copy: "Dry_Track"
s_dry = selected("Sound")
# No processing, just the original

# ============================================
# APPLY MASKS
# ============================================

# Apply Vibrato Mask
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

# Apply Dry Mask
selectObject: s_dry
plusObject: mask_dry
Multiply
s_dry_masked = selected("Sound")
Rename: "Mix_Dry"

# ============================================
# STEREO MIX
# ============================================

# Create base channels
selectObject: sound_work
Copy: "Ch_Left"
ch_L = selected("Sound")
Formula: "0"

selectObject: sound_work
Copy: "Ch_Right"
ch_R = selected("Sound")
Formula: "0"

# Sum Left (Vib L + Dry)
selectObject: ch_L
Formula: "Sound_Mix_Vib_L[] + Sound_Mix_Dry[]"

# Sum Right (Vib R + Dry)
selectObject: ch_R
Formula: "Sound_Mix_Vib_R[] + Sound_Mix_Dry[]"

# Stereo Combine
selectObject: ch_L
plusObject: ch_R
Combine to stereo
final_stereo = selected("Sound")
Rename: sound_name$ + "_neural_vibrato_pure"

if stereo_width <> 1
    # Width control
    selectObject: final_stereo
    Formula: "self * " + string$(stereo_width) + " + (Sound_Ch_Left[] + Sound_Ch_Right[])/2 * " + string$(1 - stereo_width)
endif

selectObject: final_stereo
Scale peak: 0.99

# ============================================
# CLEANUP
# ============================================
procedure safeRemove .id
    if .id > 0
        selectObject: .id
        Remove
    endif
endproc

call safeRemove: sound_work
call safeRemove: pitch
call safeRemove: intensity
call safeRemove: formant
call safeRemove: mfcc
call safeRemove: harmonicity
call safeRemove: feature_matrix
call safeRemove: feature_matrix_m
call safeRemove: pattern
call safeRemove: output_categories
call safeRemove: ffnet
call safeRemove: activations
call safeRemove: activation_matrix
call safeRemove: mask_vib
call safeRemove: mask_dry
call safeRemove: s_vib_L
call safeRemove: s_vib_R
call safeRemove: s_dry
call safeRemove: s_vib_L_masked
call safeRemove: s_vib_R_masked
call safeRemove: s_dry_masked
call safeRemove: ch_L
call safeRemove: ch_R

if play_result
    selectObject: final_stereo
    Play
endif
